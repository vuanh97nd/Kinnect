CREATE TABLE IF NOT EXISTS kinnect_core.blocks(actor text NOT NULL REFERENCES kinnect_core.users(id),target text NOT NULL REFERENCES kinnect_core.users(id),PRIMARY KEY(actor,target));
CREATE TABLE IF NOT EXISTS kinnect_core.friendships(low_id text NOT NULL REFERENCES kinnect_core.users(id),high_id text NOT NULL REFERENCES kinnect_core.users(id),requester text NOT NULL,status text NOT NULL CHECK(status IN ('pending','accepted')),created bigint NOT NULL,PRIMARY KEY(low_id,high_id));
ALTER TABLE kinnect_core.blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.friendships ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON kinnect_core.blocks,kinnect_core.friendships TO kinnect_api;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='kinnect_core' AND tablename='blocks' AND policyname='api_blocks_read') THEN CREATE POLICY api_blocks_read ON kinnect_core.blocks FOR SELECT TO kinnect_api USING(true); END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='kinnect_core' AND tablename='friendships' AND policyname='api_friends_read') THEN CREATE POLICY api_friends_read ON kinnect_core.friendships FOR SELECT TO kinnect_api USING(true); END IF;
END $$;
