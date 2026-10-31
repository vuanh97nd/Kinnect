// Web Push (RFC 8030/8291/8292) without dependencies: lets Chrome/Safari show
// calls and notifications while Kinnect is closed.
import { createECDH, createHmac, createCipheriv, createPrivateKey, generateKeyPairSync, randomBytes, sign } from "node:crypto";

const b64u = (buf) => Buffer.from(buf).toString("base64url");
const hmac = (key, data) => createHmac("sha256", key).update(data).digest();

const TEXT = {
  message: "đã gửi cho bạn một tin nhắn", group_message: "đã nhắn trong nhóm", missed_call: "Cuộc gọi nhỡ",
  like: "đã thích bài viết của bạn", comment: "đã bình luận bài viết của bạn", comment_reply: "đã trả lời bình luận của bạn",
  short_like: "đã thích video của bạn", short_comment: "đã bình luận video của bạn", friend_request: "đã gửi lời mời kết bạn",
  friend_accepted: "đã chấp nhận lời mời kết bạn", follow: "đã bắt đầu theo dõi bạn", gift: "đã gửi quà cho bạn",
  private_request: "muốn xem ảnh riêng tư của bạn", private_granted: "đã cho bạn xem ảnh riêng tư", private_revoked: "đã thu hồi quyền xem ảnh riêng tư",
};

export function createWebPush({ social, fetchImpl = fetch, subject = "mailto:admin@kinnect.io.vn" }) {
  const db = social.db;
  db.exec(`CREATE TABLE IF NOT EXISTS push_keys(id INTEGER PRIMARY KEY CHECK(id=1),jwk TEXT NOT NULL);
 CREATE TABLE IF NOT EXISTS push_subs(endpoint TEXT PRIMARY KEY,user_id TEXT NOT NULL,p256dh TEXT NOT NULL,auth TEXT NOT NULL,created INTEGER NOT NULL);
 CREATE INDEX IF NOT EXISTS push_subs_user ON push_subs(user_id);`);
  let row = db.prepare("SELECT jwk FROM push_keys WHERE id=1").get();
  if (!row) {
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    row = { jwk: JSON.stringify(privateKey.export({ format: "jwk" })) };
    db.prepare("INSERT INTO push_keys VALUES(1,?)").run(row.jwk);
  }
  const jwk = JSON.parse(row.jwk);
  const key = createPrivateKey({ key: jwk, format: "jwk" });
  const publicKey = b64u(Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, "base64url"), Buffer.from(jwk.y, "base64url")]));
  const jwtCache = new Map();

  function vapid(endpoint) {
    const aud = new URL(endpoint).origin, now = Math.floor(Date.now() / 1000), cached = jwtCache.get(aud);
    if (cached && cached.exp - now > 3600) return cached.token;
    const exp = now + 12 * 3600;
    const data = b64u(JSON.stringify({ typ: "JWT", alg: "ES256" })) + "." + b64u(JSON.stringify({ aud, exp, sub: subject }));
    const token = data + "." + b64u(sign("sha256", Buffer.from(data), { key, dsaEncoding: "ieee-p1363" }));
    jwtCache.set(aud, { token, exp });
    return token;
  }

  function encrypt(sub, payload) {
    const uaPublic = Buffer.from(sub.p256dh, "base64url"), authSecret = Buffer.from(sub.auth, "base64url");
    const ecdh = createECDH("prime256v1"); ecdh.generateKeys();
    const asPublic = ecdh.getPublicKey(), shared = ecdh.computeSecret(uaPublic), salt = randomBytes(16);
    const ikm = hmac(hmac(authSecret, shared), Buffer.concat([Buffer.from("WebPush: info\0"), uaPublic, asPublic, Buffer.from([1])]));
    const prk = hmac(salt, ikm);
    const cek = hmac(prk, Buffer.from("Content-Encoding: aes128gcm\0\x01")).subarray(0, 16);
    const nonce = hmac(prk, Buffer.from("Content-Encoding: nonce\0\x01")).subarray(0, 12);
    const cipher = createCipheriv("aes-128-gcm", cek, nonce);
    const body = Buffer.concat([cipher.update(Buffer.concat([Buffer.from(JSON.stringify(payload)), Buffer.from([2])])), cipher.final(), cipher.getAuthTag()]);
    const header = Buffer.alloc(21); salt.copy(header); header.writeUInt32BE(4096, 16); header[20] = asPublic.length;
    return Buffer.concat([header, asPublic, body]);
  }

  async function deliver(sub, payload, { urgency = "normal", ttl = 86400, topic } = {}) {
    try {
      const headers = { TTL: String(ttl), Urgency: urgency, "Content-Encoding": "aes128gcm", "Content-Type": "application/octet-stream", Authorization: `vapid t=${vapid(sub.endpoint)}, k=${publicKey}` };
      if (topic) headers.Topic = topic;
      const res = await fetchImpl(sub.endpoint, { method: "POST", headers, body: encrypt(sub, payload) });
      if (res.status === 404 || res.status === 410) db.prepare("DELETE FROM push_subs WHERE endpoint=?").run(sub.endpoint);
      else if (res.status >= 400) console.warn("[webpush]", res.status, new URL(sub.endpoint).host);
    } catch (e) { console.warn("[webpush]", e.message); }
  }

  const subsFor = (userId) => db.prepare("SELECT * FROM push_subs WHERE user_id=?").all(userId);
  const has = (userId) => !!db.prepare("SELECT 1 FROM push_subs WHERE user_id=? LIMIT 1").get(userId);
  const toUser = (userId, payload, opts) => Promise.all(subsFor(userId).map((s) => deliver(s, payload, opts)));

  function subscribe(userId, s) {
    const endpoint = String(s?.endpoint || ""), p256dh = String(s?.keys?.p256dh || ""), auth = String(s?.keys?.auth || "");
    if (!/^https:\/\//.test(endpoint) || endpoint.length > 1000 || p256dh.length < 80 || p256dh.length > 100 || auth.length < 16 || auth.length > 40) return false;
    db.prepare("INSERT INTO push_subs VALUES(?,?,?,?,?) ON CONFLICT(endpoint) DO UPDATE SET user_id=excluded.user_id,p256dh=excluded.p256dh,auth=excluded.auth").run(endpoint, userId, p256dh, auth, Date.now());
    return true;
  }
  const unsubscribe = (userId, endpoint) => db.prepare("DELETE FROM push_subs WHERE endpoint=? AND user_id=?").run(String(endpoint || ""), userId);
  const avatarOf = (u) => (u?.avatar ? "/api/users/" + u.id + "/avatar" : "/kinnect-icon-192.png");

  function preview(n, commentId) {
    const q = (sql, ...a) => db.prepare(sql).get(...a);
    const r = n.kind === "message" ? q("SELECT body FROM messages WHERE id=?", n.ref)
      : n.kind === "group_message" ? q("SELECT body FROM group_messages WHERE group_id=? AND sender=? AND created<=? ORDER BY created DESC LIMIT 1", n.ref, n.actor, n.created + 5000)
      : n.kind === "comment" || n.kind === "comment_reply" ? (commentId ? q("SELECT body FROM post_comments WHERE id=?", commentId) : q("SELECT body FROM post_comments WHERE post_id=? AND user_id=? ORDER BY created DESC LIMIT 1", n.ref, n.actor))
      : n.kind === "like" ? q("SELECT body FROM posts WHERE id=?", n.ref) : null;
    return r && typeof r.body === "string" && !r.body.startsWith("{") ? r.body.replace(/\s+/g, " ").trim().slice(0, 160) : "";
  }

  /** Called after a notification row is inserted. */
  function notification(userId, id) {
    if (!has(userId)) return;
    // Delay one tick so related rows (notification_targets) are written first.
    setTimeout(() => {
      try {
        const n = db.prepare("SELECT * FROM notifications WHERE id=? AND user_id=?").get(id, userId);
        if (!n || n.seen) return;
        const actor = social.user(n.actor);
        if (!actor || actor.suspended || social.blocked(userId, n.actor)) return;
        const commentId = db.prepare("SELECT comment_id FROM notification_targets WHERE notification_id=?").get(id)?.comment_id || null;
        const chat = n.kind === "message" || n.kind === "group_message", text = preview(n, commentId), base = TEXT[n.kind] || "có thông báo mới";
        const url = n.kind === "message" ? "/?chat=" + encodeURIComponent(n.actor) : "/?notification=" + encodeURIComponent(n.id);
        toUser(userId, {
          type: "notification", id: n.id, kind: n.kind, tag: chat ? "chat-" + n.actor + "-" + n.ref : "n-" + n.id,
          title: actor.name, body: chat ? text || base : base + (text ? `: “${text}”` : ""), icon: avatarOf(actor), url, created: n.created,
        });
      } catch (e) { console.warn("[webpush]", e.message); }
    }, 50);
  }

  function call(userId, c, from) {
    return toUser(userId, { type: "call", callId: c.id, mode: c.mode, from: { id: from.id, name: from.name }, icon: avatarOf(from), at: Date.now() }, { urgency: "high", ttl: 45, topic: "call" });
  }
  function callEnded(userId, c, reason, from) {
    return toUser(userId, { type: "call-ended", callId: c.id, reason, mode: c.mode, from: from ? { id: from.id, name: from.name } : null, icon: avatarOf(from) }, { urgency: "high", ttl: 120, topic: "call" });
  }
  const notifyTest = (userId) => toUser(userId, { type: "notification", id: "test-" + Date.now(), kind: "test", tag: "kinnect-test", title: "Kinnect", body: "Thông báo nền đã hoạt động. Bạn sẽ nhận cuộc gọi và tin nhắn cả khi đóng Kinnect.", icon: "/kinnect-icon-192.png", url: "/" });
  return { publicKey, subscribe, unsubscribe, has, notification, call, callEnded, notifyTest };
}
