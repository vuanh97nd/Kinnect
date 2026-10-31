-- Provisioning only: never import a production DB dump or plaintext passwords.
CREATE TABLE identity_accounts (
 id TEXT PRIMARY KEY,
 username TEXT NOT NULL COLLATE NOCASE UNIQUE,
 password_hash TEXT NOT NULL CHECK(length(password_hash)=128),
 password_salt TEXT NOT NULL CHECK(length(password_salt)=32),
 password_algorithm TEXT NOT NULL DEFAULT 'scrypt-node-default-64'
   CHECK(password_algorithm='scrypt-node-default-64'),
 role TEXT NOT NULL DEFAULT 'user' CHECK(role IN ('user','admin')),
 suspended INTEGER NOT NULL DEFAULT 0 CHECK(suspended IN (0,1)),
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','active','deleting','deleted')),
 revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>0),
 created_at INTEGER NOT NULL,
 updated_at INTEGER NOT NULL
);
CREATE TABLE identity_external_accounts (
 provider TEXT NOT NULL CHECK(provider IN ('google','facebook')),
 subject TEXT NOT NULL,
 user_id TEXT NOT NULL REFERENCES identity_accounts(id) ON DELETE CASCADE,
 PRIMARY KEY(provider,subject)
);
CREATE INDEX identity_external_user ON identity_external_accounts(user_id);
CREATE TABLE identity_sync_outbox (
 id TEXT PRIMARY KEY,
 user_id TEXT NOT NULL REFERENCES identity_accounts(id),
 revision INTEGER NOT NULL,
 event_type TEXT NOT NULL CHECK(event_type IN ('created','updated','suspended','deleting','deleted')),
 created_at INTEGER NOT NULL,
 processed_at INTEGER,
 UNIQUE(user_id,revision)
);
CREATE INDEX identity_outbox_pending ON identity_sync_outbox(processed_at,created_at);
CREATE TABLE identity_migration_runs (
 id TEXT PRIMARY KEY,
 state TEXT NOT NULL CHECK(state IN ('prepared','imported','verified','activated','failed')),
 source_snapshot_sha256 TEXT,
 expected_accounts INTEGER NOT NULL DEFAULT 0,
 imported_accounts INTEGER NOT NULL DEFAULT 0,
 started_at INTEGER NOT NULL,
 verified_at INTEGER
);
