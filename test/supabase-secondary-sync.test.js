import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openSocial } from '../lib/social.js';
import { startSupabaseSecondarySync } from '../lib/supabase-secondary-sync.js';

function createFakePool({ failFirstTx = false, onQuery } = {}) {
  let txCount = 0;
  let releaseCount = 0;
  const queries = [];
  const poolQueries = [];

  const pool = {
    async connect() {
      txCount += 1;
      const shouldFail = failFirstTx && txCount === 1;
      return {
        async query(sql, params = []) {
          queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
          if (shouldFail && sql.includes('INSERT INTO kinnect_core.users')) {
            throw new Error('transient pg failure');
          }
          if (onQuery) {
            const custom = onQuery(sql, params);
            if (custom) return custom;
          }
          return { rows: [], rowCount: 0 };
        },
        release() {
          releaseCount += 1;
        }
      };
    },
    async query(sql, params = []) {
      poolQueries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      if (onQuery) {
        const custom = onQuery(sql, params);
        if (custom) return custom;
      }
      return { rows: [], rowCount: 0 };
    },
    stats: () => ({ txCount, releaseCount, queries, poolQueries })
  };
  return pool;
}

test('supabase secondary sync batches upserts via UNNEST, skips unchanged ticks, and syncs chat_members + dm-* reverse pull', async () => {
  const social = openSocial(':memory:');
  const { db } = social;
  try {
    const now = 1_790_000_000_000;
    const salt = '0123456789abcdef0123456789abcdef';
    const hash = 'a'.repeat(128);
    db.prepare(`INSERT INTO users(id,username,password,salt,name,birth_date,created) VALUES(?,?,?,?,?,?,?)`)
      .run('u1', 'alice', hash, salt, 'Alice', '1998-01-01', now - 5000);
    db.prepare(`INSERT INTO users(id,username,password,salt,name,birth_date,created) VALUES(?,?,?,?,?,?,?)`)
      .run('u2', 'bob', hash, salt, 'Bob', '1999-02-02', now - 4000);
    db.prepare(`INSERT INTO users(id,username,password,salt,name,birth_date,created) VALUES(?,?,?,?,?,?,?)`)
      .run('u3', 'charlie', hash, salt, 'Charlie', '1997-03-03', now - 3000);
    db.prepare(`INSERT INTO sessions(token,user_id,expires) VALUES(?,?,?)`).run('tok_1', 'u1', now + 60000);
    db.prepare(`INSERT INTO messages(id,sender,recipient,body,created) VALUES(?,?,?,?,?)`)
      .run('m1', 'u1', 'u2', 'Xin chao Bob', now - 2000);
    db.prepare(`INSERT INTO messages(id,sender,recipient,body,created) VALUES(?,?,?,?,?)`)
      .run('m2', 'u2', 'u1', 'Chao Alice', now - 1000);

    const corePool = createFakePool();
    const chatPool = createFakePool({
      onQuery(sql) {
        if (sql.includes('FROM kinnect_chat.chat_messages m')) {
          return {
            rows: [
              {
                id: 'remote_m1',
                sender_id: 'u3',
                conversation_id: 'dm-0123456789abcdef0123456789abcdef',
                body: 'Tin nhan tu Supabase',
                created_at: now + 500,
                peer_id: 'u1'
              }
            ],
            rowCount: 1
          };
        }
        return null;
      }
    });

    const sync = startSupabaseSecondarySync({
      db,
      corePool,
      chatPool,
      initialDelayMs: 60_000,
      intervalMs: 60_000,
      now: () => now
    });

    await sync.syncNow();

    const coreStatsAfterFirst = corePool.stats();
    assert.equal(coreStatsAfterFirst.txCount, 1);
    assert.equal(coreStatsAfterFirst.releaseCount, 1);
    const userInserts = coreStatsAfterFirst.queries.filter(q => q.sql.includes('INSERT INTO kinnect_core.users'));
    assert.equal(userInserts.length, 1, 'all 3 users must batch into 1 UNNEST query');
    assert.ok(userInserts[0].sql.includes('UNNEST('));
    assert.deepEqual(userInserts[0].params[0], ['u1', 'u2', 'u3']);

    const chatStatsAfterFirst = chatPool.stats();
    const memberInserts = chatStatsAfterFirst.queries.filter(q => q.sql.includes('INSERT INTO kinnect_chat.chat_members'));
    assert.equal(memberInserts.length, 1, 'chat_members must sync for DM readability');
    assert.ok(memberInserts[0].sql.includes('UNNEST('));
    assert.equal(memberInserts[0].params[1].includes('u1'), true);
    assert.equal(memberInserts[0].params[1].includes('u2'), true);

    const msgInserts = chatStatsAfterFirst.queries.filter(q => q.sql.includes('INSERT INTO kinnect_chat.chat_messages'));
    assert.equal(msgInserts.length, 1, 'both DMs must batch into 1 UNNEST query');

    // Remote DM resolved via chat_members join despite dm-<hash> conversation_id without underscores
    const pulled = db.prepare('SELECT id, sender, recipient, body FROM messages WHERE id = ?').get('remote_m1');
    assert.deepEqual({ ...pulled }, {
      id: 'remote_m1',
      sender: 'u3',
      recipient: 'u1',
      body: 'Tin nhan tu Supabase'
    });

    // Second sync with unchanged state must skip core write transaction completely.
    await sync.syncNow();
    assert.equal(corePool.stats().txCount, 1, 'unchanged state should emit 0 redundant core write txs');

    await sync.stop();
  } finally {
    social.close();
  }
});

test('supabase secondary sync rolls back cleanly on transient error and retries on next tick', async () => {
  const social = openSocial(':memory:');
  const { db } = social;
  try {
    const now = 1_790_000_000_000;
    db.prepare(`INSERT INTO users(id,username,password,salt,name,birth_date,created) VALUES(?,?,?,?,?,?,?)`)
      .run('u1', 'alice', 'a'.repeat(128), '0123456789abcdef0123456789abcdef', 'Alice', '1998-01-01', now);

    const corePool = createFakePool({ failFirstTx: true });
    const chatPool = createFakePool();
    const sync = startSupabaseSecondarySync({
      db,
      corePool,
      chatPool,
      initialDelayMs: 60_000,
      intervalMs: 60_000,
      now: () => now
    });

    // First run fails inside tx -> rolls back, does not cache fingerprint.
    await sync.syncNow();
    assert.equal(corePool.stats().txCount, 1);
    assert.equal(corePool.stats().releaseCount, 1);
    assert.ok(corePool.stats().queries.some(q => q.sql === 'ROLLBACK'));

    // Second run retries and succeeds.
    await sync.syncNow();
    assert.equal(corePool.stats().txCount, 2);
    assert.ok(corePool.stats().queries.some(q => q.sql === 'COMMIT'));

    await sync.stop();
  } finally {
    social.close();
  }
});
