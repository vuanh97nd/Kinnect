import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { postgresOptions } from './cloud-postgres.js';
import { feedSnapshot, videoSnapshot } from './feed-snapshot.js';

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
      return { syncNow: async () => {}, stop: async () => {} };
    }

    const coreConfig = parseEnv('cloud-db.env');
    const chatConfig = parseEnv('chat-db.env');
    if (!coreConfig.KINNECT_DATABASE_URL || !chatConfig.KINNECT_DATABASE_URL) {
      console.warn('[Supabase-Secondary] cloud-db.env or chat-db.env missing KINNECT_DATABASE_URL.');
      return { syncNow: async () => {}, stop: async () => {} };
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
  let lastOutboundMsgTs = 0;
  let lastRemoteUserTs = 0;
  let lastRemoteMsgTs = 0;
  let timer = null;
  let initialTimer = null;
  const fingerprints = new Map();

  function buildUserRows() {
    return db.prepare('SELECT * FROM users').all().map(u => {
      const profile = {
        bio: u.bio || '',
        interests: u.interests || '[]',
        birth_date: u.birth_date || '',
        discoverable: u.discoverable ?? 1,
        dm_mode: u.dm_mode || 'everyone',
        identity_public: u.identity_public ?? 0,
        show_activity: u.show_activity ?? 1,
        show_distance: u.show_distance ?? 1,
        profile_visibility: u.profile_visibility || '{}',
        profile_details: u.profile_details || '{}'
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
      const feed = feedSnapshot(db);
      const videos = videoSnapshot(db);
      const staff = hasTable('console_staff')
        ? db.prepare(
            'SELECT id, username, name, password, salt, suspended, must_change, team, created FROM console_staff'
          ).all()
        : [];
      const messages = db.prepare(
        'SELECT id, sender, recipient, body, created FROM messages WHERE created > ? ORDER BY created ASC'
      ).all(lastOutboundMsgTs);

      const userHash = sha256(JSON.stringify(users));
      const sessionHash = sha256(JSON.stringify(sessions));
      const walletHash = sha256(JSON.stringify(wallets));
      const feedHash = sha256(JSON.stringify(feed));
      const videoHash = sha256(JSON.stringify(videos));
      const staffHash = sha256(JSON.stringify(staff));

      const coreDirty =
        fingerprints.get('users') !== userHash ||
        fingerprints.get('sessions') !== sessionHash ||
        fingerprints.get('wallets') !== walletHash ||
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
            await core.query('DELETE FROM kinnect_core.sessions WHERE expires <= $1', [currentNow]);
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
               ON CONFLICT (user_id, reference) DO UPDATE SET
                 coins = EXCLUDED.coins,
                 net_vnd = EXCLUDED.net_vnd,
                 creator_vnd = EXCLUDED.creator_vnd,
                 platform_vnd = EXCLUDED.platform_vnd`,
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

          if (fingerprints.get('feed') !== feedHash && feed.length > 0) {
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

          if (fingerprints.get('videos') !== videoHash && videos.length > 0) {
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

        fingerprints.set('users', userHash);
        fingerprints.set('sessions', sessionHash);
        fingerprints.set('wallets', walletHash);
        fingerprints.set('feed', feedHash);
        fingerprints.set('videos', videoHash);
        fingerprints.set('staff', staffHash);
      }

      if (messages.length > 0) {
        const convMap = new Map();
        const memberMap = new Map();
        const msgRows = [];
        let maxCreated = lastOutboundMsgTs;

        for (const m of messages) {
          const convId = pair(m.sender, m.recipient);
          const createdAt = Number(m.created);
          if (createdAt > maxCreated) maxCreated = createdAt;
          if (!convMap.has(convId)) {
            convMap.set(convId, { id: convId, created_by: m.sender, created_at: createdAt });
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
          await batchUpsert(
            chat,
            [...convMap.values()],
            batchSize,
            `INSERT INTO kinnect_chat.chat_conversations (id, kind, direct_pair, name, created_by, created_at)
             SELECT id, 'direct', id, '', created_by, created_at
             FROM UNNEST($1::text[], $2::text[], $3::bigint[]) AS t(id, created_by, created_at)
             ON CONFLICT (id) DO NOTHING`,
            slice => [
              slice.map(c => c.id),
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
        });

        lastOutboundMsgTs = maxCreated;
      }

      // Pull any new users & direct messages created on Supabase while PC was offline / standby.
      const [remoteUsersRes, remoteMessagesRes] = await Promise.all([
        corePool.query(
          'SELECT id, username, password, salt, name, role, suspended, created, profile FROM kinnect_core.users WHERE created > $1 ORDER BY created ASC LIMIT 500',
          [lastRemoteUserTs]
        ),
        chatPool.query(
          `SELECT m.id, m.sender_id, m.conversation_id, m.body, m.created_at, cm.user_id AS peer_id
           FROM kinnect_chat.chat_messages m
           JOIN kinnect_chat.chat_conversations c ON c.id = m.conversation_id
           LEFT JOIN kinnect_chat.chat_members cm
             ON cm.conversation_id = m.conversation_id
             AND cm.user_id <> m.sender_id
             AND cm.left_at IS NULL
           WHERE m.created_at > $1 AND c.kind = 'direct'
           ORDER BY m.created_at ASC
           LIMIT 500`,
          [lastRemoteMsgTs]
        )
      ]);

      const remoteUsers = remoteUsersRes.rows;
      const remoteMessages = remoteMessagesRes.rows;

      if (remoteUsers.length > 0 || remoteMessages.length > 0) {
        db.exec('BEGIN');
        try {
          if (remoteUsers.length > 0) {
            const insertUser = db.prepare(`
              INSERT OR IGNORE INTO users (id, username, password, salt, name, bio, interests, birth_date, discoverable, dm_mode, suspended, created, role)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            `);
            let maxUserTs = lastRemoteUserTs;
            for (const ru of remoteUsers) {
              const profile = typeof ru.profile === 'string' ? JSON.parse(ru.profile || '{}') : (ru.profile || {});
              const createdAt = Number(ru.created) || currentNow;
              if (createdAt > maxUserTs) maxUserTs = createdAt;
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
            }
            lastRemoteUserTs = maxUserTs;
          }

          if (remoteMessages.length > 0) {
            const candidateIds = new Set();
            const normalized = [];
            let maxMsgTs = lastRemoteMsgTs;
            for (const rm of remoteMessages) {
              const createdAt = Number(rm.created_at);
              if (createdAt > maxMsgTs) maxMsgTs = createdAt;
              const recipient =
                rm.peer_id ||
                String(rm.conversation_id || '')
                  .split('_')
                  .find(p => p && p !== rm.sender_id) ||
                '';
              if (!recipient) continue;
              candidateIds.add(rm.sender_id);
              candidateIds.add(recipient);
              normalized.push({
                id: rm.id,
                sender: rm.sender_id,
                recipient,
                body: rm.body,
                created: createdAt
              });
            }

            if (normalized.length > 0) {
              const ids = [...candidateIds];
              const placeholders = ids.map(() => '?').join(',');
              const existingUsers = new Set(
                db.prepare(`SELECT id FROM users WHERE id IN (${placeholders})`).all(...ids).map(r => r.id)
              );
              const insertMsg = db.prepare(
                'INSERT OR IGNORE INTO messages (id, sender, recipient, body, created) VALUES (?, ?, ?, ?, ?)'
              );
              for (const m of normalized) {
                if (existingUsers.has(m.sender) && existingUsers.has(m.recipient)) {
                  insertMsg.run(m.id, m.sender, m.recipient, m.body, m.created);
                }
              }
            }
            lastRemoteMsgTs = maxMsgTs;
          }

          db.exec('COMMIT');
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

  return {
    syncNow: performSync,
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
