CREATE SCHEMA IF NOT EXISTS kinnect_core;
CREATE TABLE IF NOT EXISTS kinnect_core.users (
 id text PRIMARY KEY,
 username text UNIQUE NOT NULL,
 password text NOT NULL CHECK(password ~ '^[0-9a-fA-F]{128}$'),
 salt text NOT NULL CHECK(salt ~ '^[0-9a-fA-F]{32}$'),
 name text NOT NULL,
 role text NOT NULL CHECK(role IN ('user','admin')),
 suspended integer NOT NULL CHECK(suspended IN (0,1)),
 created bigint NOT NULL,
 profile jsonb NOT NULL
);
CREATE TABLE IF NOT EXISTS kinnect_core.sessions (
 token_hash text PRIMARY KEY,
 user_id text NOT NULL REFERENCES kinnect_core.users(id) ON DELETE CASCADE,
 expires bigint NOT NULL
);
CREATE INDEX IF NOT EXISTS core_session_user ON kinnect_core.sessions(user_id);
CREATE TABLE IF NOT EXISTS kinnect_core.oauth_accounts (
 provider text NOT NULL,
 subject text NOT NULL,
 user_id text NOT NULL REFERENCES kinnect_core.users(id),
 email text NOT NULL DEFAULT '',
 created bigint NOT NULL,
 PRIMARY KEY(provider,subject)
);
ALTER TABLE kinnect_core.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.oauth_accounts ENABLE ROW LEVEL SECURITY;
