import { createPrivateKey, createSign } from 'node:crypto';
import { readFile } from 'node:fs/promises';

/**
 * Firebase Cloud Messaging (FCM HTTP v1 API) Server-Side Push Module for Kinnect Android (APK)
 *
 * - Zero external dependencies (uses Node.js built-in node:crypto RS256 JWT + native fetch).
 * - Authenticates via Google OAuth2 Service Account (FCM_SERVICE_ACCOUNT_FILE or FCM_PROJECT_ID + FCM_CLIENT_EMAIL + FCM_PRIVATE_KEY).
 * - Automatically caches OAuth2 access tokens (50 min TTL).
 * - Automatically prunes UNREGISTERED / INVALID_ARGUMENT stale FCM device tokens from `push_devices`.
 * - Delivers high-priority Android notifications, direct/group chat messages, and incoming/ended call signals.
 */

const NOTIFICATION_TEXT = {
  message: 'đã gửi cho bạn một tin nhắn',
  group_message: 'đã nhắn trong nhóm',
  missed_call: 'Cuộc gọi nhỡ',
  like: 'đã thích bài viết của bạn',
  share: 'đã chia sẻ bài viết của bạn',
  comment: 'đã bình luận bài viết của bạn',
  comment_reply: 'đã trả lời bình luận của bạn',
  short_like: 'đã thích video của bạn',
  short_comment: 'đã bình luận video của bạn',
  friend_request: 'đã gửi lời mời kết bạn',
  friend_accepted: 'đã chấp nhận lời mời kết bạn',
  follow: 'đã bắt đầu theo dõi bạn',
  gift: 'đã gửi quà cho bạn',
  private_request: 'muốn xem ảnh riêng tư của bạn',
  private_granted: 'đã cho bạn xem ảnh riêng tư',
  private_revoked: 'đã thu hồi quyền xem ảnh riêng tư',
  security_alert: 'Cảnh báo bảo mật hệ thống Kinnect',
  ai_review: 'Báo cáo mới cần Quản trị viên xem xét'
};

const b64u = input => Buffer.from(input).toString('base64url');

export function isValidFcmToken(token) {
  return typeof token === 'string' && /^[A-Za-z0-9:_\-]{32,4096}$/.test(token);
}

export function createFirebasePush({
  social,
  env = process.env,
  fetchImpl = fetch,
  clock = Date.now
} = {}) {
  let cachedSa = null;
  let cachedAccessToken = null;
  let cachedTokenExpiresAt = 0;
  let pendingTokenRefresh = null;

  const isFlagEnabled = () => {
    const flag = String(env.FCM_ENABLED || '').trim().toLowerCase();
    return flag === 'true' || flag === '1';
  };

  const hasCredentialsConfigured = () => {
    if (env.FCM_SERVICE_ACCOUNT_FILE) return true;
    return Boolean(env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY);
  };

  const enabled = () => isFlagEnabled() && hasCredentialsConfigured();

  const has = userId =>
    enabled() &&
    Boolean(social.db.prepare("SELECT 1 FROM push_devices WHERE user_id=? AND kind='fcm' LIMIT 1").get(userId));

  async function loadServiceAccount() {
    if (cachedSa) return cachedSa;
    if (env.FCM_SERVICE_ACCOUNT_FILE) {
      const raw = await readFile(env.FCM_SERVICE_ACCOUNT_FILE, 'utf8');
      const parsed = JSON.parse(raw);
      if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
        throw new Error('FCM service account JSON missing project_id, client_email, or private_key');
      }
      cachedSa = {
        projectId: String(parsed.project_id).trim(),
        clientEmail: String(parsed.client_email).trim(),
        privateKey: String(parsed.private_key).replace(/\\n/g, '\n'),
        tokenUri: String(parsed.token_uri || 'https://oauth2.googleapis.com/token')
      };
      return cachedSa;
    }

    if (env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY) {
      cachedSa = {
        projectId: String(env.FCM_PROJECT_ID).trim(),
        clientEmail: String(env.FCM_CLIENT_EMAIL).trim(),
        privateKey: String(env.FCM_PRIVATE_KEY).replace(/\\n/g, '\n'),
        tokenUri: String(env.FCM_TOKEN_URI || 'https://oauth2.googleapis.com/token')
      };
      return cachedSa;
    }

    throw new Error('FCM credentials not configured');
  }

  async function getAccessToken(forceRefresh = false) {
    const now = clock();
    if (!forceRefresh && cachedAccessToken && now < cachedTokenExpiresAt - 60000) {
      return cachedAccessToken;
    }
    if (pendingTokenRefresh) {
      return pendingTokenRefresh;
    }

    pendingTokenRefresh = (async () => {
      const sa = await loadServiceAccount();
      const refreshNow = clock();
      const iat = Math.floor(refreshNow / 1000);
      const exp = iat + 3600;
      const header = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
      const claims = b64u(JSON.stringify({
        iss: sa.clientEmail,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: sa.tokenUri,
        iat,
        exp
      }));
      const unsignedJwt = `${header}.${claims}`;
      const signer = createSign('RSA-SHA256');
      signer.update(unsignedJwt);
      signer.end();
      const privateKeyObj = createPrivateKey(sa.privateKey);
      const signature = signer.sign(privateKeyObj).toString('base64url');
      const assertion = `${unsignedJwt}.${signature}`;

      const resp = await fetchImpl(sa.tokenUri, {
        method: 'POST',
        signal: AbortSignal.timeout(10000),
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion
        }).toString()
      });

      if (!resp.ok) {
        throw new Error(`FCM OAuth2 token exchange failed: HTTP ${resp.status}`);
      }
      const data = await resp.json();
      if (!data?.access_token) {
        throw new Error('FCM OAuth2 response missing access_token');
      }

      cachedAccessToken = data.access_token;
      cachedTokenExpiresAt = refreshNow + (Number(data.expires_in) || 3600) * 1000;
      return cachedAccessToken;
    })();

    try {
      return await pendingTokenRefresh;
    } finally {
      pendingTokenRefresh = null;
    }
  }

  function buildDataStrings(dataObj = {}) {
    const out = {};
    for (const [k, v] of Object.entries(dataObj)) {
      if (v === undefined || v === null) continue;
      out[String(k)] = typeof v === 'string' ? v : JSON.stringify(v);
    }
    return out;
  }

  async function deliver(userId, { title = '', body = '', data = {}, highPriority = true, ttlSeconds = 86400, channelId = 'kinnect_messages_v1', dataOnly = false } = {}) {
    if (!enabled()) return [];
    const user = social.user(userId);
    if (!user || user.suspended) return [];

    const rows = social.db
      .prepare("SELECT token FROM push_devices WHERE user_id=? AND kind='fcm'")
      .all(userId);
    if (!rows.length) return [];

    const sa = await loadServiceAccount();
    const accessToken = await getAccessToken();
    const endpoint = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(sa.projectId)}/messages:send`;

    return Promise.all(rows.map(async ({ token }) => {
      if (!isValidFcmToken(token)) return { skipped: true };

      const message = {
        token,
        data: buildDataStrings(data),
        android: {
          priority: highPriority ? 'HIGH' : 'NORMAL',
          ttl: `${Math.max(0, Math.min(2419200, Number(ttlSeconds) || 86400))}s`,
          ...(dataOnly ? {} : {
            notification: {
              channel_id: channelId,
              sound: 'default'
            }
          })
        }
      };

      if (!dataOnly && (title || body)) {
        message.notification = { title, body };
      }

      try {
        const sendOnce = async (bearer) => {
          const resp = await fetchImpl(endpoint, {
            method: 'POST',
            signal: AbortSignal.timeout(10000),
            headers: {
              Authorization: `Bearer ${bearer}`,
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({ message })
          });
          let respBody = {};
          try { respBody = await resp.json(); } catch {}
          return { resp, respBody };
        };

        let { resp, respBody } = await sendOnce(accessToken);
        if (resp.status === 401) {
          if (cachedAccessToken === accessToken) {
            cachedAccessToken = null;
            cachedTokenExpiresAt = 0;
          }
          const refreshedToken = await getAccessToken(true);
          ({ resp, respBody } = await sendOnce(refreshedToken));
        }

        const details = Array.isArray(respBody?.error?.details) ? respBody.error.details : [];
        const errCode = details.find(d => d?.errorCode)?.errorCode || respBody?.error?.status || '';
        const errMsg = String(respBody?.error?.message || '');
        const isTokenInvalidArg = resp.status === 400 && errCode === 'INVALID_ARGUMENT' && (
          details.some(d => Array.isArray(d?.fieldViolations) && d.fieldViolations.some(v => v?.field === 'message.token' || v?.field === 'token')) ||
          /not a valid fcm registration token|registration token is not a valid|invalid registration token/i.test(errMsg)
        );
        if (resp.status === 404 || errCode === 'UNREGISTERED' || isTokenInvalidArg) {
          social.db.prepare("DELETE FROM push_devices WHERE user_id=? AND kind='fcm' AND token=?").run(userId, token);
        }

        return { ok: resp.ok, status: resp.status, errorCode: errCode || undefined };
      } catch (e) {
        return { ok: false, error: e.message };
      }
    }));
  }

  function preview(n, targetId, userId) {
    const q = (sql, ...a) => social.db.prepare(sql).get(...a);
    let r = null;
    if (n.kind === 'message') {
      if (n.ref && !q("SELECT 1 FROM recalled_chat_messages WHERE kind='direct' AND message_id=?", n.ref) && !q("SELECT 1 FROM hidden_chat_messages WHERE kind='direct' AND message_id=? AND user_id=?", n.ref, userId)) {
        r = q('SELECT body FROM messages WHERE id=?', n.ref);
      }
    } else if (n.kind === 'group_message') {
      const gm = targetId
        ? q('SELECT id,body FROM group_messages WHERE id=? AND group_id=?', targetId, n.ref)
        : q('SELECT id,body FROM group_messages WHERE group_id=? AND sender=? AND created<=? ORDER BY created DESC,rowid DESC LIMIT 1', n.ref, n.actor, n.created);
      if (gm && !q("SELECT 1 FROM recalled_chat_messages WHERE kind='group' AND message_id=?", gm.id) && !q("SELECT 1 FROM hidden_chat_messages WHERE kind='group' AND message_id=? AND user_id=?", gm.id, userId)) {
        r = gm;
      }
    } else if (n.kind === 'comment' || n.kind === 'comment_reply') {
      const p = q('SELECT id,hidden FROM posts WHERE id=?', n.ref);
      if (p && !p.hidden) {
        r = targetId
          ? q('SELECT body FROM post_comments WHERE id=? AND post_id=?', targetId, n.ref)
          : q('SELECT body FROM post_comments WHERE post_id=? AND user_id=? ORDER BY created DESC LIMIT 1', n.ref, n.actor);
      } else {
        const s = q('SELECT id,hidden FROM shorts WHERE id=?', n.ref);
        if (s && !s.hidden) {
          r = targetId
            ? q('SELECT body FROM short_comments WHERE id=? AND short_id=?', targetId, n.ref)
            : q('SELECT body FROM short_comments WHERE short_id=? AND user_id=? ORDER BY created DESC LIMIT 1', n.ref, n.actor);
        }
      }
    } else if (n.kind === 'short_comment') {
      const s = q('SELECT id,hidden FROM shorts WHERE id=?', n.ref);
      if (s && !s.hidden) {
        r = targetId
          ? q('SELECT body FROM short_comments WHERE id=? AND short_id=?', targetId, n.ref)
          : q('SELECT body FROM short_comments WHERE short_id=? AND user_id=? ORDER BY created DESC LIMIT 1', n.ref, n.actor);
      }
    } else if (n.kind === 'like' || n.kind === 'share') {
      r = q('SELECT body FROM posts WHERE id=? AND hidden=0', n.ref);
    } else if (n.kind === 'short_like') {
      r = q('SELECT caption AS body FROM shorts WHERE id=? AND hidden=0', n.ref);
    }
    return r && typeof r.body === 'string' && !r.body.startsWith('{')
      ? r.body.replace(/\s+/g, ' ').trim().slice(0, 160)
      : '';
  }

  const background = promise => { promise.catch(() => {}); };

  function notification(userId, id) {
    if (!enabled()) return;
    setTimeout(() => {
      try {
        const n = social.db.prepare('SELECT * FROM notifications WHERE id=? AND user_id=?').get(id, userId);
        if (!n || n.seen) return;
        const actor = social.user(n.actor);
        if (!actor || actor.suspended || social.blocked(userId, n.actor)) return;

        const targetId = social.db.prepare('SELECT comment_id FROM notification_targets WHERE notification_id=?').get(id)?.comment_id || null;
        const isChat = n.kind === 'message' || n.kind === 'group_message';
        if (n.kind === 'group_message' && !social.db.prepare('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?').get(n.ref, userId)) return;
        if (isChat) {
          const convKind = n.kind === 'message' ? 'direct' : 'group';
          const convId = n.kind === 'message' ? n.actor : n.ref;
          const isMuted = convId && social.db.prepare('SELECT 1 FROM muted_conversations WHERE kind=? AND conversation_id=? AND user_id=?').get(convKind, convId, userId);
          if (isMuted) return;
        }
        const text = preview(n, targetId, userId);
        const base = NOTIFICATION_TEXT[n.kind] || 'có thông báo mới trên Kinnect';

        background(deliver(userId, {
          title: actor.name || 'Kinnect',
          body: isChat ? (text || base) : base + (text ? `: “${text}”` : ''),
          channelId: 'kinnect_messages_v1',
          highPriority: true,
          ttlSeconds: 86400,
          data: {
            type: 'notification',
            notificationId: n.id,
            kind: n.kind,
            actorId: n.actor,
            ref: n.ref || '',
            created: String(n.created)
          }
        }));
      } catch {}
    }, 50).unref?.();
  }

  function call(userId, session, from) {
    if (!enabled() || !from || social.blocked(userId, from.id)) return;
    background(deliver(userId, {
      title: from.name || 'Kinnect',
      body: session.mode === 'video' ? 'Cuộc gọi video đến…' : 'Cuộc gọi thoại đến…',
      channelId: 'kinnect_calls_v2',
      highPriority: true,
      ttlSeconds: 45,
      dataOnly: true,
      data: {
        type: 'call',
        callId: session.id,
        mode: session.mode || 'audio',
        callerId: from.id,
        callerName: from.name || 'Kinnect',
        at: String(clock())
      }
    }));
  }

  function callEnded(userId, session, reason, from) {
    if (!enabled()) return;
    background(deliver(userId, {
      highPriority: true,
      ttlSeconds: 60,
      dataOnly: true,
      data: {
        type: 'call-ended',
        callId: session.id,
        reason: reason || 'ended',
        mode: session.mode || 'audio',
        callerId: from?.id || '',
        callerName: from?.name || ''
      }
    }));
  }

  function notifyTest(userId) {
    return deliver(userId, {
      title: 'Kinnect Android Push (FCM)',
      body: 'Thông báo đẩy Firebase FCM đã hoạt động! Bạn sẽ nhận tin nhắn và cuộc gọi ngay cả khi tắt ứng dụng.',
      channelId: 'kinnect_messages_v1',
      highPriority: true,
      data: {
        type: 'notification',
        kind: 'test',
        created: String(clock())
      }
    });
  }

  function status() {
    const deviceCount = social.db.prepare("SELECT COUNT(*) AS n FROM push_devices WHERE kind='fcm'").get()?.n || 0;
    return {
      enabled: enabled(),
      flagEnabled: isFlagEnabled(),
      credentialsConfigured: hasCredentialsConfigured(),
      registeredAndroidDevices: deviceCount
    };
  }

  return {
    enabled,
    has,
    deliver,
    notification,
    call,
    callEnded,
    notifyTest,
    status
  };
}
