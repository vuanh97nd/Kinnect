-- Phase 1 Postgres Standards: Missing snapshot/staff DDL, composite/partial indexes, and RLS policies.
CREATE TABLE IF NOT EXISTS kinnect_core.feed_snapshot (
 id text PRIMARY KEY,
 author_id text NOT NULL REFERENCES kinnect_core.users(id) ON DELETE CASCADE,
 body text NOT NULL DEFAULT '',
 visibility text NOT NULL CHECK (visibility IN ('public', 'followers')),
 hidden integer NOT NULL DEFAULT 0 CHECK (hidden IN (0, 1)),
 created bigint NOT NULL,
 data jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS kinnect_core.video_snapshot (
 id text PRIMARY KEY,
 author_id text NOT NULL REFERENCES kinnect_core.users(id) ON DELETE CASCADE,
 hidden integer NOT NULL DEFAULT 0 CHECK (hidden IN (0, 1)),
 created bigint NOT NULL,
 data jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS kinnect_core.console_staff (
 id text PRIMARY KEY,
 username text UNIQUE NOT NULL,
 name text NOT NULL,
 password text NOT NULL CHECK (password ~ '^[0-9a-fA-F]{128}$'),
 salt text NOT NULL CHECK (salt ~ '^[0-9a-fA-F]{32}$'),
 suspended integer NOT NULL DEFAULT 0 CHECK (suspended IN (0, 1)),
 must_change integer NOT NULL DEFAULT 1 CHECK (must_change IN (0, 1)),
 team text NOT NULL DEFAULT 'support',
 created bigint NOT NULL
);

ALTER TABLE kinnect_core.feed_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.video_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.console_staff ENABLE ROW LEVEL SECURITY;

-- Composite & partial indexes aligned with hot read queries (Supabase Postgres Best Practices).
CREATE INDEX IF NOT EXISTS core_session_expires ON kinnect_core.sessions(expires);
CREATE INDEX IF NOT EXISTS core_session_user_expires ON kinnect_core.sessions(user_id, expires);
CREATE INDEX IF NOT EXISTS core_feed_active_created ON kinnect_core.feed_snapshot(created DESC, id) WHERE hidden = 0;
CREATE INDEX IF NOT EXISTS core_feed_author_created ON kinnect_core.feed_snapshot(author_id, created DESC) WHERE hidden = 0;
CREATE INDEX IF NOT EXISTS core_video_active_created ON kinnect_core.video_snapshot(created DESC, id) WHERE hidden = 0;
CREATE INDEX IF NOT EXISTS core_video_author_created ON kinnect_core.video_snapshot(author_id, created DESC) WHERE hidden = 0;
CREATE INDEX IF NOT EXISTS core_notification_inbox ON kinnect_core.notifications(user_id, seen, created DESC);
CREATE INDEX IF NOT EXISTS core_blocks_target ON kinnect_core.blocks(target, actor);
CREATE INDEX IF NOT EXISTS core_follows_target ON kinnect_core.follows(target, actor);
CREATE INDEX IF NOT EXISTS core_wallet_created ON kinnect_core.wallet_entries(created DESC);
CREATE INDEX IF NOT EXISTS core_gift_inventory_owner ON kinnect_core.gift_inventory(user_id, gift_id);

DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'kinnect_api') THEN
  GRANT SELECT, INSERT, UPDATE, DELETE ON
   kinnect_core.feed_snapshot,
   kinnect_core.video_snapshot,
   kinnect_core.console_staff
  TO kinnect_api;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'kinnect_core' AND tablename = 'feed_snapshot' AND policyname IN ('backend_runtime', 'backend_feed')) THEN
   CREATE POLICY backend_runtime ON kinnect_core.feed_snapshot FOR ALL TO kinnect_api USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'kinnect_core' AND tablename = 'video_snapshot' AND policyname IN ('backend_runtime', 'backend_video')) THEN
   CREATE POLICY backend_runtime ON kinnect_core.video_snapshot FOR ALL TO kinnect_api USING (true) WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'kinnect_core' AND tablename = 'console_staff' AND policyname = 'backend_runtime') THEN
   CREATE POLICY backend_runtime ON kinnect_core.console_staff FOR ALL TO kinnect_api USING (true) WITH CHECK (true);
  END IF;
 END IF;
END $$;
