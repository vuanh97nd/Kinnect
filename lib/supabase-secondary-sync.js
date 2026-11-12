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

const hash = v => createHash('sha256').update(v).digest('hex');
const pair = (a, b) => 'dm-' + hash(JSON.stringify([a, b].sort())).slice(0, 32);

export function startSupabaseSecondarySync({ db, intervalMs = 60000 } = {}) {
  const pg = getPg();
  if (!pg) {
    console.warn('[Supabase-Secondary] pg driver not found, secondary sync disabled.');
    return { syncNow: async () => {}, stop: () => {} };
  }

  const coreConfig = parseEnv('cloud-db.env');
  const chatConfig = parseEnv('chat-db.env');
  if (!coreConfig.KINNECT_DATABASE_URL || !chatConfig.KINNECT_DATABASE_URL) {
    console.warn('[Supabase-Secondary] cloud-db.env or chat-db.env missing KINNECT_DATABASE_URL.');
    return { syncNow: async () => {}, stop: () => {} };
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

  let syncing = false;
  let lastSyncTs = 0;
  let timer = null;

  async function performSync() {
    if (syncing) return;
    syncing = true;
    const core = new pg.Client(postgresOptions(coreConfig));
    const chat = new pg.Client(postgresOptions(chatConfig));

    try {
      await Promise.all([core.connect(), chat.connect()]);

      // 1. Sync Users
      const users = db.prepare('SELECT * FROM users').all();
      for (const u of users) {
        let profile = {};
        try {
          profile = {
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
        } catch {}

        await core.query(
          `INSERT INTO kinnect_core.users (id, username, password, salt, name, role, suspended, created, profile)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
           ON CONFLICT (id) DO UPDATE SET
             username = EXCLUDED.username,
             name = EXCLUDED.name,
             role = EXCLUDED.role,
             suspended = EXCLUDED.suspended,
             profile = EXCLUDED.profile`,
          [
            u.id,
            u.username,
            u.password,
            u.salt,
            u.name || u.username,
            u.role || 'user',
            u.suspended ? 1 : 0,
            Number(u.created) || Date.now(),
            JSON.stringify(profile)
          ]
        );
      }

      // 2. Sync Active Sessions
      const sessions = db.prepare('SELECT token, user_id, expires FROM sessions WHERE expires > ?').all(Date.now());
      for (const s of sessions) {
        await core.query(
          `INSERT INTO kinnect_core.sessions (token_hash, user_id, expires)
           VALUES ($1, $2, $3)
           ON CONFLICT (token_hash) DO UPDATE SET expires = EXCLUDED.expires`,
          [s.token, s.user_id, s.expires]
        );
      }

      // 3. Sync Wallet Entries
      const wallets = db.prepare('SELECT id, user_id, reference, kind, coins, net_vnd, creator_vnd, platform_vnd, created FROM wallet_entries').all();
      for (const w of wallets) {
        await core.query(
          `INSERT INTO kinnect_core.wallet_entries (id, user_id, reference, kind, coins, net_vnd, creator_vnd, platform_vnd, created)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           ON CONFLICT (user_id, reference) DO UPDATE SET
             coins = EXCLUDED.coins,
             net_vnd = EXCLUDED.net_vnd,
             creator_vnd = EXCLUDED.creator_vnd,
             platform_vnd = EXCLUDED.platform_vnd`,
          [w.id, w.user_id, w.reference, w.kind, w.coins, w.net_vnd, w.creator_vnd, w.platform_vnd, w.created]
        );
      }

      // 4. Sync Feed and Video Snapshots (Metadata ONLY - 0 media bytes)
      const feed = feedSnapshot(db);
      for (const p of feed) {
        await core.query(
          `INSERT INTO kinnect_core.feed_snapshot (id, author_id, body, visibility, hidden, created, data)
           VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
           ON CONFLICT (id) DO UPDATE SET
             body = EXCLUDED.body,
             visibility = EXCLUDED.visibility,
             hidden = EXCLUDED.hidden,
             data = EXCLUDED.data`,
          [p.id, p.user_id, p.body || '', p.visibility || 'public', p.hidden ? 1 : 0, p.created, JSON.stringify(p)]
        );
      }

      const videos = videoSnapshot(db);
      for (const v of videos) {
        await core.query(
          `INSERT INTO kinnect_core.video_snapshot (id, author_id, hidden, created, data)
           VALUES ($1, $2, $3, $4, $5::jsonb)
           ON CONFLICT (id) DO UPDATE SET
             hidden = EXCLUDED.hidden,
             data = EXCLUDED.data`,
          [v.id, v.user_id, v.hidden ? 1 : 0, v.created, JSON.stringify(v)]
        );
      }

      // 5. Sync Chat Messages
      const messages = db.prepare('SELECT id, sender, recipient, body, created FROM messages WHERE created > ?').all(lastSyncTs || 0);
      for (const m of messages) {
        const convId = pair(m.sender, m.recipient);
        await chat.query(
          `INSERT INTO kinnect_chat.chat_conversations (id, kind, direct_pair, name, created_by, created_at)
           VALUES ($1, 'direct', $1, '', $2, $3)
           ON CONFLICT (id) DO NOTHING`,
          [convId, m.sender, m.created]
        );
        await chat.query(
          `INSERT INTO kinnect_chat.chat_messages (id, conversation_id, sender_id, client_nonce, body, kind, created_at)
           VALUES ($1, $2, $3, $4, $5, 'text', $6)
           ON CONFLICT (id) DO NOTHING`,
          [m.id, convId, m.sender, 'msg_' + m.id, m.body, m.created]
        );
      }

      // 6. Sync Admin Staff & Audit
      const staff = db.prepare('SELECT id, username, name, password, salt, suspended, must_change, team, created FROM console_staff').all();
      for (const st of staff) {
        await core.query(
          `INSERT INTO kinnect_core.console_staff (id, username, name, password, salt, suspended, must_change, team, created)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           ON CONFLICT (id) DO UPDATE SET
             name = EXCLUDED.name,
             password = EXCLUDED.password,
             salt = EXCLUDED.salt,
             suspended = EXCLUDED.suspended,
             must_change = EXCLUDED.must_change,
             team = EXCLUDED.team`,
          [st.id, st.username, st.name, st.password, st.salt, st.suspended, st.must_change, st.team, st.created]
        );
      }

      // 7. Pull any new users created on Supabase while PC was offline / standby
      const remoteUsers = await core.query('SELECT * FROM kinnect_core.users WHERE created > $1', [lastSyncTs || 0]);
      for (const ru of remoteUsers.rows) {
        const exists = db.prepare('SELECT 1 FROM users WHERE id = ?').get(ru.id);
        if (!exists) {
          const profile = typeof ru.profile === 'string' ? JSON.parse(ru.profile || '{}') : (ru.profile || {});
          db.prepare(`
            INSERT OR IGNORE INTO users (id, username, password, salt, name, bio, interests, birth_date, discoverable, dm_mode, suspended, created, role)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `).run(
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
            Number(ru.created) || Date.now(),
            ru.role || 'user'
          );
        }
      }

      // 8. Pull any new messages sent on Supabase while PC was offline / standby
      const remoteMessages = await chat.query('SELECT id, sender_id, conversation_id, body, created_at FROM kinnect_chat.chat_messages WHERE created_at > $1', [lastSyncTs || 0]);
      for (const rm of remoteMessages.rows) {
        const parts = String(rm.conversation_id || '').split('_');
        const recipient = parts.find(p => p !== rm.sender_id) || '';
        if (!recipient) continue;
        const senderExists = db.prepare('SELECT 1 FROM users WHERE id = ?').get(rm.sender_id);
        const recipientExists = db.prepare('SELECT 1 FROM users WHERE id = ?').get(recipient);
        if (senderExists && recipientExists) {
          try {
            db.prepare('INSERT OR IGNORE INTO messages (id, sender, recipient, body, created) VALUES (?, ?, ?, ?, ?)')
              .run(rm.id, rm.sender_id, recipient, rm.body, Number(rm.created_at));
          } catch {}
        }
      }

      lastSyncTs = Date.now();
    } catch (err) {
      console.warn('[Supabase-Secondary] Sync warning (PC server remains master):', err.message);
    } finally {
      await core.end().catch(() => {});
      await chat.end().catch(() => {});
      syncing = false;
    }
  }

  // Trigger initial non-blocking sync after 5 seconds
  setTimeout(() => performSync().catch(() => {}), 5000);
  timer = setInterval(() => performSync().catch(() => {}), intervalMs);
  timer.unref?.();

  return {
    syncNow: performSync,
    stop: () => {
      if (timer) clearInterval(timer);
    }
  };
}
