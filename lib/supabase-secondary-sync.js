import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { postgresOptions } from './cloud-postgres.js';
import { feedSnapshot, videoSnapshot } from './feed-snapshot.js';
import { flushWalletCreditsForUser } from './wallet-credit-mirror.js';

let pgModule = null;
function getPg() {
  if (pgModule) return pgModule;
  const candidates = [
    'D:/Codex/Kinnect/cloud-api/package.json',
    'D:/Kinnect-Server/cloud-api/package.json',
    './cloud-api/package.json'
  ];
  for (const p of candidates) {
    try {
      const req = createRequire(p);
      pgModule = req('pg');
      return pgModule;
    } catch {}
  }
  try {
    const req = createRequire(import.meta.url);
    pgModule = req('pg');
    return pgModule;
  } catch {}
  return null;
}

function parseEnv(filePath) {
  if (!existsSync(filePath)) return {};
  return Object.fromEntries(
    readFileSync(filePath, 'utf8')
      .split(/\r?\n/)
      .filter(x => x && !x.startsWith('#'))
      .map(x => {
        const i = x.indexOf('=');
        return [x.slice(0, i).trim(), x.slice(i + 1).trim()];
      })
  );
}

const sha256 = v => createHash('sha256').update(v).digest('hex');
const pair = (a, b) => 'dm-' + sha256(JSON.stringify([a, b].sort())).slice(0, 32);

async function runInTransaction(pool, fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

function chunk(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }
  return out;
}

async function batchUpsert(client, rows, batchSize, queryText, mapColumns) {
  for (const slice of chunk(rows, batchSize)) {
    await client.query(queryText, mapColumns(slice));
  }
}

export function startSupabaseSecondarySync({
  db,
  intervalMs = 60000,
  initialDelayMs = 5000,
  batchSize = 250,
  corePool: injectedCorePool = null,
  chatPool: injectedChatPool = null,
  now = Date.now
} = {}) {
  let corePool = injectedCorePool;
  let chatPool = injectedChatPool;
  const ownsPools = !(injectedCorePool && injectedChatPool);

  if (ownsPools) {
    const pg = getPg();
    if (!pg) {
      console.warn('[Supabase-Secondary] pg driver not found, secondary sync disabled.');
      return { syncNow: async () => {}, purgeAccount: async () => {}, stop: async () => {} };
    }

    const coreConfig = parseEnv('cloud-db.env');
    const chatConfig = parseEnv('chat-db.env');
    if (!coreConfig.KINNECT_DATABASE_URL || !chatConfig.KINNECT_DATABASE_URL) {
      console.warn('[Supabase-Secondary] cloud-db.env or chat-db.env missing KINNECT_DATABASE_URL.');
      return { syncNow: async () => {}, purgeAccount: async () => {}, stop: async () => {} };
    }

    const caPath = existsSync('data/certificates/supabase-prod-ca-2021.crt')
      ? 'data/certificates/supabase-prod-ca-2021.crt'
      : existsSync('D:/Codex/Kinnect/data/certificates/supabase-prod-ca-2021.crt')
      ? 'D:/Codex/Kinnect/data/certificates/supabase-prod-ca-2021.crt'
      : coreConfig.KINNECT_DATABASE_CA_FILE;
    if (caPath) {
      coreConfig.KINNECT_DATABASE_CA_FILE = caPath;
      chatConfig.KINNECT_DATABASE_CA_FILE = caPath;
    }

    const poolDefaults = { max: 3, idleTimeoutMillis: 30000, allowExitOnIdle: true };
    corePool = new pg.Pool({ ...postgresOptions(coreConfig), ...poolDefaults });
    chatPool = new pg.Pool({ ...postgresOptions(chatConfig), ...poolDefaults });
    corePool.on('error', err => console.warn('[Supabase-Secondary] Core pool error:', err.message));
    chatPool.on('error', err => console.warn('[Supabase-Secondary] Chat pool error:', err.message));
  }

  let syncing = false;
  let stopped = false;
  db.exec(`
    CREATE TABLE IF NOT EXISTS supabase_sync_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS supabase_deleted_hashes (hash TEXT PRIMARY KEY, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS mirrored_cloud_users (user_id TEXT PRIMARY KEY);
  `);
  const readMetaInt = (key, fallbackSql) => {
    try {
      const row = db.prepare('SELECT value FROM supabase_sync_meta WHERE key=?').get(key);
      if (row && Number.isFinite(Number(row.value))) return Number(row.value);
      if (fallbackSql) {
        const fb = db.prepare(fallbackSql).get();
        const val = Number(fb?.m) || 0;
        db.prepare('INSERT OR REPLACE INTO supabase_sync_meta(key,value) VALUES(?,?)').run(key, String(val));
        return val;
      }
    } catch {}
    return 0;
  };
  const writeMetaInt = (key, val) => {
    try {
      db.prepare('INSERT OR REPLACE INTO supabase_sync_meta(key,value) VALUES(?,?)').run(key, String(val));
    } catch {}
  };
  const readMetaStr = key => {
    try {
      const row = db.prepare('SELECT value FROM supabase_sync_meta WHERE key=?').get(key);
      return row ? String(row.value) : '';
    } catch {
      return '';
    }
  };
  const writeMetaStr = (key, val) => {
    try {
      db.prepare('INSERT OR REPLACE INTO supabase_sync_meta(key,value) VALUES(?,?)').run(key, String(val ?? ''));
    } catch {}
  };
  const deletedHashOf = id => sha256('kinnect-deleted-user:' + String(id || ''));
  const isDeletedUser = id => {
    if (!id) return false;
    try {
      return !!db.prepare('SELECT 1 FROM supabase_deleted_hashes WHERE hash=?').get(deletedHashOf(id));
    } catch {
      return false;
    }
  };
  let lastOutboundMsgTs = readMetaInt('last_outbound_msg_ts');
  let lastOutboundMsgId = readMetaStr('last_outbound_msg_id');
  let syncedSessionHashes = (() => {
    try {
      const parsed = JSON.parse(readMetaStr('synced_session_hashes') || '[]');
      return new Set(Array.isArray(parsed) ? parsed.filter(x => typeof x === 'string') : []);
    } catch {
      return new Set();
    }
  })();
  let lastRemoteUserTs = readMetaInt('last_remote_user_ts', 'SELECT COALESCE(MAX(created),0) AS m FROM users');
  let lastRemoteUserId = readMetaStr('last_remote_user_id');
  let lastRemoteMsgTs = readMetaInt('last_remote_msg_ts', 'SELECT COALESCE(MAX(created),0) AS m FROM messages');
  let lastRemoteMsgId = readMetaStr('last_remote_msg_id');
  let timer = null;
  let initialTimer = null;
  const fingerprints = new Map();

  const USER_SYNC_COLUMNS = [
    'id', 'username', 'password', 'salt', 'name', 'role', 'suspended', 'created',
    'bio', 'interests', 'birth_date', 'age', 'city', 'looking_for',
    'gender', 'orientation', 'community_role', 'relationship_role', 'pronouns',
    'profile_dob', 'last_active', 'discoverable', 'dm_mode',
    'identity_public', 'show_activity', 'show_distance',
    'profile_visibility', 'profile_details',
    'height', 'weight', 'occupation', 'school'
  ];
  const existingUserCols = new Set(db.prepare('PRAGMA table_info(users)').all().map(c => c.name));
  const userSelectParts = USER_SYNC_COLUMNS.filter(c => existingUserCols.has(c));
  if (existingUserCols.has('avatar')) userSelectParts.push('(avatar IS NOT NULL) AS has_avatar');
  if (existingUserCols.has('cover')) userSelectParts.push('(cover IS NOT NULL) AS has_cover');
  const userSelectCols = userSelectParts.join(', ');

  function buildUserRows() {
    const enabled2fa = hasTable('user_totp')
      ? new Set(db.prepare('SELECT user_id FROM user_totp WHERE enabled = 1').all().map(r => r.user_id))
      : new Set();
    return db.prepare(`SELECT ${userSelectCols} FROM users`).all().map(u => {
      const profile = {
        bio: u.bio || '',
        interests: u.interests || '[]',
        birth_date: u.birth_date || '',
        age: u.age ?? null,
        city: u.city || '',
        looking_for: u.looking_for || '',
        gender: u.gender || '',
        orientation: u.orientation || '',
        community_role: u.community_role || '',
        relationship_role: u.relationship_role || '',
        pronouns: u.pronouns || '',
        profile_dob: u.profile_dob || '',
        last_active: Number(u.last_active) || 0,
        discoverable: u.discoverable ?? 1,
        dm_mode: u.dm_mode || 'everyone',
        identity_public: u.identity_public ?? 0,
        show_activity: u.show_activity ?? 1,
        show_distance: u.show_distance ?? 1,
        profile_visibility: u.profile_visibility || '{}',
        profile_details: u.profile_details || '{}',
        avatar: Boolean(u.has_avatar),
        cover: Boolean(u.has_cover),
        has_avatar: Boolean(u.has_avatar),
        has_cover: Boolean(u.has_cover),
        ...(u.height !== undefined ? { height: u.height } : {}),
        ...(u.weight !== undefined ? { weight: u.weight } : {}),
        ...(u.occupation !== undefined ? { occupation: u.occupation } : {}),
        ...(u.school !== undefined ? { school: u.school } : {}),
        two_factor_enabled: enabled2fa.has(u.id) ? 1 : 0
      };
      return {
        id: u.id,
        username: u.username,
        password: u.password,
        salt: u.salt,
        name: u.name || u.username,
        role: u.role || 'user',
        suspended: u.suspended ? 1 : 0,
        created: Number(u.created) || now(),
        profileJson: JSON.stringify(profile)
      };
    });
  }

  const hasTable = name =>
    !!db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name);

  async function performSync() {
    if (syncing || stopped) return;
    syncing = true;
    const currentNow = now();

    try {
      const users = buildUserRows();
      const sessions = db.prepare('SELECT token, user_id, expires FROM sessions WHERE expires > ?').all(currentNow);
      const wallets = hasTable('wallet_entries')
        ? db.prepare(
            'SELECT id, user_id, reference, kind, coins, net_vnd, creator_vnd, platform_vnd, created FROM wallet_entries'
          ).all()
        : [];
      const trialGifts = (() => {
        if (!hasTable('wallet_trial_gifts')) return [];
        const giftCols = new Set(db.prepare('PRAGMA table_info(wallet_trial_gifts)').all().map(c => c.name));
        return db.prepare(
          `SELECT user_id, request_id, room_id, gift_id, cost, created,
                  ${giftCols.has('recipient_id') ? 'recipient_id' : 'NULL AS recipient_id'},
                  ${giftCols.has('quantity') ? 'quantity' : '1 AS quantity'}
           FROM wallet_trial_gifts`
        ).all();
      })();
      const feed = feedSnapshot(db);
      const videos = videoSnapshot(db);
      const staff = hasTable('console_staff')
        ? db.prepare(
            'SELECT id, username, name, password, salt, suspended, must_change, team, created FROM console_staff'
          ).all()
        : [];
      const messages = db.prepare(
        'SELECT id, sender, recipient, body, created FROM messages WHERE (created > ? OR (created = ? AND id > ?)) ORDER BY created ASC, id ASC LIMIT 1000'
      ).all(lastOutboundMsgTs, lastOutboundMsgTs, lastOutboundMsgId);
      const recalledDirect = hasTable('recalled_chat_messages')
        ? db.prepare(
            "SELECT message_id, created FROM recalled_chat_messages WHERE kind = 'direct' ORDER BY message_id ASC"
          ).all()
        : [];
      const editedDirect = hasTable('edited_chat_messages')
        ? db.prepare(
            `SELECT e.message_id, e.edited_at, m.body
             FROM edited_chat_messages e
             JOIN messages m ON m.id = e.message_id
             WHERE e.kind = 'direct'
             ORDER BY e.message_id ASC`
          ).all()
        : [];

      const userHash = sha256(JSON.stringify(users));
      const sessionHash = sha256(JSON.stringify(sessions));
      const walletHash = sha256(JSON.stringify(wallets));
      const trialGiftHash = sha256(JSON.stringify(trialGifts));
      const feedHash = sha256(JSON.stringify(feed));
      const videoHash = sha256(JSON.stringify(videos));
      const staffHash = sha256(JSON.stringify(staff));
      const recalledHash = sha256(JSON.stringify(recalledDirect));
      const editedHash = sha256(JSON.stringify(editedDirect));

      const coreDirty =
        fingerprints.get('users') !== userHash ||
        fingerprints.get('sessions') !== sessionHash ||
        fingerprints.get('wallets') !== walletHash ||
        fingerprints.get('trialGifts') !== trialGiftHash ||
        fingerprints.get('feed') !== feedHash ||
        fingerprints.get('videos') !== videoHash ||
        fingerprints.get('staff') !== staffHash;

      if (coreDirty) {
        await runInTransaction(corePool, async core => {
          if (fingerprints.get('users') !== userHash && users.length > 0) {
            await batchUpsert(
              core,
              users,
              batchSize,
              `INSERT INTO kinnect_core.users (id, username, password, salt, name, role, suspended, created, profile)
               SELECT * FROM UNNEST($1::text[], $2::text[], $3::text[], $4::text[], $5::text[], $6::text[], $7::integer[], $8::bigint[], $9::jsonb[])
               ON CONFLICT (id) DO UPDATE SET
                 username = EXCLUDED.username,
                 password = EXCLUDED.password,
                 salt = EXCLUDED.salt,
                 name = EXCLUDED.name,
                 role = EXCLUDED.role,
                 suspended = EXCLUDED.suspended,
                 profile = EXCLUDED.profile`,
              slice => [
                slice.map(u => u.id),
                slice.map(u => u.username),
                slice.map(u => u.password),
                slice.map(u => u.salt),
                slice.map(u => u.name),
                slice.map(u => u.role),
                slice.map(u => u.suspended),
                slice.map(u => u.created),
                slice.map(u => u.profileJson)
              ]
            );
          }

          if (fingerprints.get('sessions') !== sessionHash) {
            const currentTokenSet = new Set(sessions.map(s => s.token));
            const revokedTokens = [...syncedSessionHashes].filter(h => !currentTokenSet.has(h));
            const suspendedUserIds = users.filter(u => u.suspended === 1).map(u => u.id);
            await core.query('DELETE FROM kinnect_core.sessions WHERE expires <= $1', [currentNow]);
            if (revokedTokens.length > 0) {
              await core.query('DELETE FROM kinnect_core.sessions WHERE token_hash = ANY($1::text[])', [revokedTokens]);
            }
            if (suspendedUserIds.length > 0) {
              await core.query('DELETE FROM kinnect_core.sessions WHERE user_id = ANY($1::text[])', [suspendedUserIds]);
            }
            if (sessions.length > 0) {
              await batchUpsert(
                core,
                sessions,
                batchSize,
                `INSERT INTO kinnect_core.sessions (token_hash, user_id, expires)
                 SELECT * FROM UNNEST($1::text[], $2::text[], $3::bigint[])
                 ON CONFLICT (token_hash) DO UPDATE SET expires = EXCLUDED.expires`,
                slice => [
                  slice.map(s => s.token),
                  slice.map(s => s.user_id),
                  slice.map(s => Number(s.expires))
                ]
              );
            }
          }

          if (fingerprints.get('wallets') !== walletHash && wallets.length > 0) {
            await batchUpsert(
              core,
              wallets,
              batchSize,
              `INSERT INTO kinnect_core.wallet_entries (id, user_id, reference, kind, coins, net_vnd, creator_vnd, platform_vnd, created)
               SELECT * FROM UNNEST($1::text[], $2::text[], $3::text[], $4::text[], $5::bigint[], $6::bigint[], $7::bigint[], $8::bigint[], $9::bigint[])
               ON CONFLICT (user_id, reference) DO NOTHING`,
              slice => [
                slice.map(w => w.id),
                slice.map(w => w.user_id),
                slice.map(w => w.reference),
                slice.map(w => w.kind),
                slice.map(w => Number(w.coins)),
                slice.map(w => Number(w.net_vnd)),
                slice.map(w => Number(w.creator_vnd)),
                slice.map(w => Number(w.platform_vnd)),
                slice.map(w => Number(w.created))
              ]
            );
          }

          if (fingerprints.get('trialGifts') !== trialGiftHash && trialGifts.length > 0) {
            const hasPgTrialGifts = await core.query(
              "SELECT 1 FROM information_schema.tables WHERE table_schema = 'kinnect_core' AND table_name = 'wallet_trial_gifts' LIMIT 1"
            );
            if (hasPgTrialGifts?.rows?.length) {
              await batchUpsert(
                core,
                trialGifts,
                batchSize,
                `INSERT INTO kinnect_core.wallet_trial_gifts (user_id, request_id, room_id, gift_id, cost, created, recipient_id, quantity)
                 SELECT * FROM UNNEST($1::text[], $2::text[], $3::text[], $4::text[], $5::bigint[], $6::bigint[], $7::text[], $8::integer[])
                 ON CONFLICT (user_id, request_id) DO NOTHING`,
                slice => [
                  slice.map(g => g.user_id),
                  slice.map(g => g.request_id),
                  slice.map(g => g.room_id),
                  slice.map(g => g.gift_id),
                  slice.map(g => Number(g.cost) || 0),
                  slice.map(g => Number(g.created) || currentNow),
                  slice.map(g => g.recipient_id ?? null),
                  slice.map(g => Number(g.quantity) || 1)
                ]
              );
            }
          }

          if (fingerprints.get('feed') !== feedHash) {
            if (feed.length > 0) {
              await batchUpsert(
                core,
                feed,
                batchSize,
                `INSERT INTO kinnect_core.feed_snapshot (id, author_id, body, visibility, hidden, created, data)
                 SELECT * FROM UNNEST($1::text[], $2::text[], $3::text[], $4::text[], $5::integer[], $6::bigint[], $7::jsonb[])
                 ON CONFLICT (id) DO UPDATE SET
                   body = EXCLUDED.body,
                   visibility = EXCLUDED.visibility,
                   hidden = EXCLUDED.hidden,
                   data = EXCLUDED.data`,
                slice => [
                  slice.map(p => p.id),
                  slice.map(p => p.user_id),
                  slice.map(p => p.body || ''),
                  slice.map(p => p.visibility || 'public'),
                  slice.map(p => (p.hidden ? 1 : 0)),
                  slice.map(p => Number(p.created)),
                  slice.map(p => JSON.stringify(p))
                ]
              );
            }
            await core.query(
              'UPDATE kinnect_core.feed_snapshot SET hidden = 1 WHERE NOT (id = ANY($1::text[]))',
              [feed.map(p => p.id)]
            );
          }

          if (fingerprints.get('videos') !== videoHash) {
            if (videos.length > 0) {
              await batchUpsert(
                core,
                videos,
                batchSize,
                `INSERT INTO kinnect_core.video_snapshot (id, author_id, hidden, created, data)
                 SELECT * FROM UNNEST($1::text[], $2::text[], $3::integer[], $4::bigint[], $5::jsonb[])
                 ON CONFLICT (id) DO UPDATE SET
                   hidden = EXCLUDED.hidden,
                   data = EXCLUDED.data`,
                slice => [
                  slice.map(v => v.id),
                  slice.map(v => v.user_id),
                  slice.map(v => (v.hidden ? 1 : 0)),
                  slice.map(v => Number(v.created)),
                  slice.map(v => JSON.stringify(v))
                ]
              );
            }
            await core.query(
              'UPDATE kinnect_core.video_snapshot SET hidden = 1 WHERE NOT (id = ANY($1::text[]))',
              [videos.map(v => v.id)]
            );
          }

          if (fingerprints.get('staff') !== staffHash && staff.length > 0) {
            await batchUpsert(
              core,
              staff,
              batchSize,
              `INSERT INTO kinnect_core.console_staff (id, username, name, password, salt, suspended, must_change, team, created)
               SELECT * FROM UNNEST($1::text[], $2::text[], $3::text[], $4::text[], $5::text[], $6::integer[], $7::integer[], $8::text[], $9::bigint[])
               ON CONFLICT (id) DO UPDATE SET
                 name = EXCLUDED.name,
                 password = EXCLUDED.password,
                 salt = EXCLUDED.salt,
                 suspended = EXCLUDED.suspended,
                 must_change = EXCLUDED.must_change,
                 team = EXCLUDED.team`,
              slice => [
                slice.map(st => st.id),
                slice.map(st => st.username),
                slice.map(st => st.name),
                slice.map(st => st.password),
                slice.map(st => st.salt),
                slice.map(st => (st.suspended ? 1 : 0)),
                slice.map(st => (st.must_change ? 1 : 0)),
                slice.map(st => st.team || 'support'),
                slice.map(st => Number(st.created))
              ]
            );
          }
        });

        if (fingerprints.get('sessions') !== sessionHash) {
          syncedSessionHashes = new Set(sessions.map(s => s.token));
          writeMetaStr('synced_session_hashes', JSON.stringify([...syncedSessionHashes]));
        }
        fingerprints.set('users', userHash);
        fingerprints.set('sessions', sessionHash);
        fingerprints.set('wallets', walletHash);
        fingerprints.set('trialGifts', trialGiftHash);
        fingerprints.set('feed', feedHash);
        fingerprints.set('videos', videoHash);
        fingerprints.set('staff', staffHash);
      }

      const recalledDirty = recalledDirect.length > 0 && fingerprints.get('recalledDirect') !== recalledHash;
      const editedDirty = editedDirect.length > 0 && fingerprints.get('editedDirect') !== editedHash;

      if (messages.length > 0 || recalledDirty || editedDirty) {
        const convMap = new Map();
        const memberMap = new Map();
        const msgRows = [];
        let maxCreated = lastOutboundMsgTs;
        let maxId = lastOutboundMsgId;

        for (const m of messages) {
          const convId = pair(m.sender, m.recipient);
          const createdAt = Number(m.created);
          const msgId = String(m.id || '');
          if (createdAt > maxCreated) {
            maxCreated = createdAt;
            maxId = msgId;
          } else if (createdAt === maxCreated && msgId > maxId) {
            maxId = msgId;
          }
          if (!convMap.has(convId)) {
            convMap.set(convId, {
              id: convId,
              direct_pair: JSON.stringify([m.sender, m.recipient].sort()),
              created_by: m.sender,
              created_at: createdAt
            });
          }
          for (const uid of [m.sender, m.recipient]) {
            const k = `${convId}\0${uid}`;
            if (!memberMap.has(k)) {
              memberMap.set(k, { conversation_id: convId, user_id: uid, joined_at: createdAt });
            }
          }
          msgRows.push({
            id: m.id,
            conversation_id: convId,
            sender_id: m.sender,
            client_nonce: 'msg_' + m.id,
            body: m.body,
            created_at: createdAt
          });
        }

        await runInTransaction(chatPool, async chat => {
          if (msgRows.length > 0) {
            await batchUpsert(
              chat,
              [...convMap.values()],
              batchSize,
              `INSERT INTO kinnect_chat.chat_conversations (id, kind, direct_pair, name, created_by, created_at)
               SELECT id, 'direct', direct_pair, '', created_by, created_at
               FROM UNNEST($1::text[], $2::text[], $3::text[], $4::bigint[]) AS t(id, direct_pair, created_by, created_at)
               ON CONFLICT (id) DO UPDATE SET direct_pair = EXCLUDED.direct_pair
                 WHERE kinnect_chat.chat_conversations.direct_pair IS NULL
                    OR kinnect_chat.chat_conversations.direct_pair NOT LIKE '[%'`,
              slice => [
                slice.map(c => c.id),
                slice.map(c => c.direct_pair),
                slice.map(c => c.created_by),
                slice.map(c => c.created_at)
              ]
            );

            await batchUpsert(
              chat,
              [...memberMap.values()],
              batchSize,
              `INSERT INTO kinnect_chat.chat_members (conversation_id, user_id, role, joined_at)
               SELECT conversation_id, user_id, 'member', joined_at
               FROM UNNEST($1::text[], $2::text[], $3::bigint[]) AS t(conversation_id, user_id, joined_at)
               ON CONFLICT (conversation_id, user_id) DO NOTHING`,
              slice => [
                slice.map(m => m.conversation_id),
                slice.map(m => m.user_id),
                slice.map(m => m.joined_at)
              ]
            );

            await batchUpsert(
              chat,
              msgRows,
              batchSize,
              `INSERT INTO kinnect_chat.chat_messages (id, conversation_id, sender_id, client_nonce, body, kind, created_at)
               SELECT id, conversation_id, sender_id, client_nonce, body, 'text', created_at
               FROM UNNEST($1::text[], $2::text[], $3::text[], $4::text[], $5::text[], $6::bigint[])
                 AS t(id, conversation_id, sender_id, client_nonce, body, created_at)
               ON CONFLICT (id) DO NOTHING`,
              slice => [
                slice.map(m => m.id),
                slice.map(m => m.conversation_id),
                slice.map(m => m.sender_id),
                slice.map(m => m.client_nonce),
                slice.map(m => m.body),
                slice.map(m => m.created_at)
              ]
            );
          }

          if (editedDirty) {
            await batchUpsert(
              chat,
              editedDirect,
              batchSize,
              `UPDATE kinnect_chat.chat_messages AS cm
               SET body = t.body, edited_at = t.edited_at
               FROM UNNEST($1::text[], $2::text[], $3::bigint[]) AS t(id, body, edited_at)
               WHERE cm.id = t.id AND cm.recalled_at IS NULL`,
              slice => [
                slice.map(e => e.message_id),
                slice.map(e => e.body || ''),
                slice.map(e => Number(e.edited_at) || currentNow)
              ]
            );
          }

          if (recalledDirty) {
            await batchUpsert(
              chat,
              recalledDirect,
              batchSize,
              `UPDATE kinnect_chat.chat_messages AS cm
               SET body = '', recalled_at = COALESCE(cm.recalled_at, t.recalled_at)
               FROM UNNEST($1::text[], $2::bigint[]) AS t(id, recalled_at)
               WHERE cm.id = t.id`,
              slice => [
                slice.map(r => r.message_id),
                slice.map(r => Number(r.created) || currentNow)
              ]
            );
          }
        });

        if (messages.length > 0) {
          lastOutboundMsgTs = maxCreated;
          lastOutboundMsgId = maxId;
          writeMetaInt('last_outbound_msg_ts', lastOutboundMsgTs);
          writeMetaStr('last_outbound_msg_id', lastOutboundMsgId);
        }
        if (messages.length < 1000) {
          fingerprints.set('recalledDirect', recalledHash);
          fingerprints.set('editedDirect', editedHash);
        }
      }

      // Pull any new users & direct messages created on Supabase while PC was offline / standby.
      const [remoteUsersRes, remoteMessagesRes] = await Promise.all([
        corePool.query(
          `SELECT id, username, password, salt, name, role, suspended, created, profile
           FROM kinnect_core.users
           WHERE (created > $1 OR (created = $1 AND id > $2))
           ORDER BY created ASC, id ASC
           LIMIT 500`,
          [lastRemoteUserTs, lastRemoteUserId]
        ),
        chatPool.query(
          `SELECT m.id, m.sender_id, m.conversation_id, m.body, m.created_at, cm.user_id AS peer_id
           FROM kinnect_chat.chat_messages m
           JOIN kinnect_chat.chat_conversations c ON c.id = m.conversation_id
           LEFT JOIN kinnect_chat.chat_members cm
             ON cm.conversation_id = m.conversation_id
             AND cm.user_id <> m.sender_id
             AND cm.left_at IS NULL
           WHERE (m.created_at > $1 OR (m.created_at = $1 AND m.id > $2))
             AND c.kind = 'direct'
             AND m.recalled_at IS NULL
           ORDER BY m.created_at ASC, m.id ASC
           LIMIT 500`,
          [lastRemoteMsgTs, lastRemoteMsgId]
        )
      ]);

      const remoteUsers = remoteUsersRes.rows;
      const remoteMessages = remoteMessagesRes.rows;

      if (remoteUsers.length > 0 || remoteMessages.length > 0) {
        let nextRemoteUserTs = lastRemoteUserTs;
        let nextRemoteUserId = lastRemoteUserId;
        let nextRemoteMsgTs = lastRemoteMsgTs;
        let nextRemoteMsgId = lastRemoteMsgId;
        const canFlushWalletCredits = hasTable('wallet_entries');

        db.exec('BEGIN');
        try {
          if (remoteUsers.length > 0) {
            const markMirrored = db.prepare('INSERT OR IGNORE INTO mirrored_cloud_users (user_id) VALUES (?)');
            const insertUser = db.prepare(`
              INSERT OR IGNORE INTO users (id, username, password, salt, name, bio, interests, birth_date, discoverable, dm_mode, suspended, created, role)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `);
            let maxUserTs = lastRemoteUserTs;
            let maxUserId = lastRemoteUserId;
            for (const ru of remoteUsers) {
              const profile = typeof ru.profile === 'string' ? JSON.parse(ru.profile || '{}') : (ru.profile || {});
              const createdAt = Number(ru.created) || currentNow;
              const ruId = String(ru.id || '');
              if (createdAt > maxUserTs) {
                maxUserTs = createdAt;
                maxUserId = ruId;
              } else if (createdAt === maxUserTs && ruId > maxUserId) {
                maxUserId = ruId;
              }
              if (isDeletedUser(ru.id)) continue;
              markMirrored.run(ru.id);
              insertUser.run(
                ru.id,
                ru.username,
                ru.password,
                ru.salt,
                ru.name || ru.username,
                profile.bio || '',
                profile.interests || '[]',
                profile.birth_date || '',
                profile.discoverable ?? 1,
                profile.dm_mode || 'everyone',
                ru.suspended ? 1 : 0,
                createdAt,
                ru.role || 'user'
              );
              if (canFlushWalletCredits && ru.id) {
                try {
                  flushWalletCreditsForUser(db, ru.id);
                } catch (flushErr) {
                  console.warn('[Supabase-Secondary] Wallet credit mirror flush warning:', flushErr.message);
                }
              }
            }
            nextRemoteUserTs = maxUserTs;
            nextRemoteUserId = maxUserId;
            writeMetaInt('last_remote_user_ts', nextRemoteUserTs);
            writeMetaStr('last_remote_user_id', nextRemoteUserId);
          }

          if (remoteMessages.length > 0) {
            const candidateIds = new Set();
            const entries = [];
            for (const rm of remoteMessages) {
              const createdAt = Number(rm.created_at);
              const msgId = String(rm.id || '');
              const recipient =
                rm.peer_id ||
                String(rm.conversation_id || '')
                  .split('_')
                  .find(p => p && p !== rm.sender_id) ||
                '';
              if (!recipient || isDeletedUser(rm.sender_id) || isDeletedUser(recipient)) {
                entries.push({ id: msgId, created: createdAt, ignorable: true });
                continue;
              }
              candidateIds.add(rm.sender_id);
              candidateIds.add(recipient);
              entries.push({
                id: msgId,
                sender: rm.sender_id,
                recipient,
                body: rm.body,
                created: createdAt,
                ignorable: false
              });
            }

            const existingUsers = new Set();
            if (candidateIds.size > 0) {
              const ids = [...candidateIds];
              const placeholders = ids.map(() => '?').join(',');
              for (const r of db.prepare(`SELECT id FROM users WHERE id IN (${placeholders})`).all(...ids)) {
                existingUsers.add(r.id);
              }
            }

            const insertMsg = db.prepare(
              'INSERT OR IGNORE INTO messages (id, sender, recipient, body, created) VALUES (?, ?, ?, ?, ?)'
            );
            let sawDeferred = false;
            let safeTs = lastRemoteMsgTs;
            let safeId = lastRemoteMsgId;

            for (const m of entries) {
              if (!m.ignorable) {
                if (existingUsers.has(m.sender) && existingUsers.has(m.recipient)) {
                  insertMsg.run(m.id, m.sender, m.recipient, m.body, m.created);
                } else {
                  sawDeferred = true;
                  continue;
                }
              }
              if (!sawDeferred) {
                if (m.created > safeTs) {
                  safeTs = m.created;
                  safeId = m.id;
                } else if (m.created === safeTs && m.id > safeId) {
                  safeId = m.id;
                }
              }
            }

            if (!sawDeferred) {
              nextRemoteMsgTs = safeTs;
              nextRemoteMsgId = safeId;
            } else if (safeTs > lastRemoteMsgTs || (safeTs === lastRemoteMsgTs && safeId > lastRemoteMsgId)) {
              nextRemoteMsgTs = safeTs;
              nextRemoteMsgId = safeId;
            }
            writeMetaInt('last_remote_msg_ts', nextRemoteMsgTs);
            writeMetaStr('last_remote_msg_id', nextRemoteMsgId);
          }

          db.exec('COMMIT');
          lastRemoteUserTs = nextRemoteUserTs;
          lastRemoteUserId = nextRemoteUserId;
          lastRemoteMsgTs = nextRemoteMsgTs;
          lastRemoteMsgId = nextRemoteMsgId;
        } catch (sqliteErr) {
          try { db.exec('ROLLBACK'); } catch {}
          throw sqliteErr;
        }
      }
    } catch (err) {
      console.warn('[Supabase-Secondary] Sync warning (PC server remains master):', err.message);
    } finally {
      syncing = false;
    }
  }

  // Trigger initial non-blocking sync
  initialTimer = setTimeout(() => performSync().catch(() => {}), initialDelayMs);
  initialTimer.unref?.();
  timer = setInterval(() => performSync().catch(() => {}), intervalMs);
  timer.unref?.();

  async function purgeAccount(userId) {
    if (!userId) return;
    try {
      db.prepare('INSERT OR REPLACE INTO supabase_deleted_hashes(hash, created) VALUES(?, ?)').run(deletedHashOf(userId), now());
    } catch {}
    if (stopped) return;
    const results = await Promise.allSettled([
      runInTransaction(corePool, async client => {
        await client.query('DELETE FROM kinnect_core.sessions WHERE user_id = $1', [userId]);
        await client.query('DELETE FROM kinnect_core.wallet_entries WHERE user_id = $1', [userId]);
        const hasPgTrialGifts = await client.query(
          "SELECT 1 FROM information_schema.tables WHERE table_schema = 'kinnect_core' AND table_name = 'wallet_trial_gifts' LIMIT 1"
        );
        if (hasPgTrialGifts?.rows?.length) {
          await client.query('UPDATE kinnect_core.wallet_trial_gifts SET recipient_id = NULL WHERE recipient_id = $1', [userId]);
          await client.query('DELETE FROM kinnect_core.wallet_trial_gifts WHERE user_id = $1', [userId]);
        }
        await client.query('DELETE FROM kinnect_core.feed_snapshot WHERE author_id = $1', [userId]);
        await client.query('DELETE FROM kinnect_core.video_snapshot WHERE author_id = $1', [userId]);
        await client.query('DELETE FROM kinnect_core.users WHERE id = $1', [userId]);
      }),
      runInTransaction(chatPool, async client => {
        await client.query(
          `DELETE FROM kinnect_chat.chat_messages
           WHERE sender_id = $1
              OR conversation_id IN (
                SELECT m.conversation_id
                FROM kinnect_chat.chat_members m
                JOIN kinnect_chat.chat_conversations c ON c.id = m.conversation_id
                WHERE m.user_id = $1 AND c.kind = 'direct'
              )`,
          [userId]
        );
        await client.query('DELETE FROM kinnect_chat.chat_members WHERE user_id = $1', [userId]);
        await client.query(
          `DELETE FROM kinnect_chat.chat_conversations
           WHERE kind = 'direct'
             AND NOT EXISTS (SELECT 1 FROM kinnect_chat.chat_members m WHERE m.conversation_id = kinnect_chat.chat_conversations.id)`
        );
      })
    ]);
    const labels = ['core', 'chat'];
    results.forEach((r, idx) => {
      if (r.status === 'rejected') {
        console.warn(`[Supabase-Secondary] purgeAccount(${labels[idx]}) failed:`, r.reason?.message || r.reason);
      }
    });
  }

  return {
    syncNow: performSync,
    purgeAccount,
    stop: async () => {
      stopped = true;
      if (initialTimer) clearTimeout(initialTimer);
      if (timer) clearInterval(timer);
      if (ownsPools) {
        await Promise.allSettled([corePool.end(), chatPool.end()]);
      }
    }
  };
}
