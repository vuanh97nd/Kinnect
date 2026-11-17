import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { openSocial } from '../lib/social.js';
import { syncFeed } from '../cloud-api/basic-feed.js';

test('Postgres schemas define RLS and composite/partial indexes for hot feed, notification, and chat queries', () => {
  const core0005 = readFileSync(new URL('../cloud-postgres/0005_snapshots_indexes_rls.sql', import.meta.url), 'utf8');
  const chat0002 = readFileSync(new URL('../cloud-chat-postgres/migrations/0002_chat_indexes.sql', import.meta.url), 'utf8');

  for (const tbl of ['feed_snapshot', 'video_snapshot', 'console_staff']) {
    assert.match(core0005, new RegExp(`CREATE TABLE IF NOT EXISTS kinnect_core\\.${tbl}`));
    assert.match(core0005, new RegExp(`ALTER TABLE kinnect_core\\.${tbl} ENABLE ROW LEVEL SECURITY`));
  }
  assert.match(core0005, /core_feed_active_created ON kinnect_core\.feed_snapshot\(created DESC, id\) WHERE hidden = 0/);
  assert.match(core0005, /core_video_active_created ON kinnect_core\.video_snapshot\(created DESC, id\) WHERE hidden = 0/);
  assert.match(core0005, /core_notification_inbox ON kinnect_core\.notifications\(user_id, seen, created DESC\)/);
  assert.match(core0005, /core_blocks_target ON kinnect_core\.blocks\(target, actor\)/);
  assert.match(chat0002, /chat_members_conv_active ON kinnect_chat\.chat_members\(conversation_id, user_id\) WHERE left_at IS NULL/);
});

test('cloud-api syncFeed batches posts and videos with UNNEST inside a single transaction', async () => {
  const calls = [];
  const client = {
    async query(sql, params = []) {
      calls.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      return { rows: [], rowCount: 0 };
    }
  };
  const payload = {
    posts: [
      { id: 'p1', user_id: 'u1', body: 'Hello', visibility: 'public', hidden: 0, created: 1000 },
      { id: 'p2', user_id: 'u2', body: 'World', visibility: 'followers', hidden: 0, created: 2000 }
    ],
    videos: [
      { id: 'v1', user_id: 'u1', hidden: 0, created: 1500 },
      { id: 'v2', user_id: 'u2', hidden: 0, created: 2500 }
    ]
  };
  const res = await syncFeed(
    new Request('https://example.test/internal/feed-sync', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    }),
    client,
    (body, status = 200) => ({ body, status })
  );

  assert.equal(res.status, 200);
  assert.equal(res.body.count, 2);
  assert.equal(calls[0].sql, 'BEGIN');
  assert.equal(calls.at(-1).sql, 'COMMIT');
  const feedInserts = calls.filter(c => c.sql.includes('INSERT INTO kinnect_core.feed_snapshot'));
  const videoInserts = calls.filter(c => c.sql.includes('INSERT INTO kinnect_core.video_snapshot'));
  assert.equal(feedInserts.length, 1);
  assert.equal(videoInserts.length, 1);
  assert.ok(feedInserts[0].sql.includes('UNNEST('));
  assert.ok(videoInserts[0].sql.includes('UNNEST('));
});

test('SQLite openSocial creates indexes for sessions, posts, messages, notifications, comments, blocks, and follows', () => {
  const social = openSocial(':memory:');
  try {
    const names = new Set(
      social.db.prepare("SELECT name FROM sqlite_master WHERE type = 'index'").all().map(r => r.name)
    );
    for (const expected of [
      'idx_sessions_user_expires',
      'idx_sessions_expires',
      'idx_posts_hidden_created',
      'idx_posts_user_created',
      'idx_messages_sender_recipient_created',
      'idx_messages_recipient_sender_created',
      'idx_notifications_user_seen_created',
      'idx_post_comments_post_created',
      'idx_short_comments_short_created',
      'idx_blocks_target_actor',
      'idx_follows_target_actor'
    ]) {
      assert.ok(names.has(expected), `Expected SQLite index ${expected} to exist`);
    }
  } finally {
    social.close();
  }
});
