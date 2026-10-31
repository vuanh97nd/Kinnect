CREATE TABLE IF NOT EXISTS kinnect_core.wallet_entries (
 id text PRIMARY KEY,
 user_id text NOT NULL REFERENCES kinnect_core.users(id),
 reference text NOT NULL,
 kind text NOT NULL,
 coins bigint NOT NULL DEFAULT 0,
 net_vnd bigint NOT NULL DEFAULT 0,
 creator_vnd bigint NOT NULL DEFAULT 0,
 platform_vnd bigint NOT NULL DEFAULT 0,
 created bigint NOT NULL,
 UNIQUE(user_id,reference)
);
CREATE INDEX IF NOT EXISTS core_wallet_owner ON kinnect_core.wallet_entries(user_id,created);
CREATE TABLE IF NOT EXISTS kinnect_core.store_packages (
 user_id text NOT NULL REFERENCES kinnect_core.users(id),
 request_id text NOT NULL,
 product_id text NOT NULL,
 expires bigint NOT NULL,
 created bigint NOT NULL,
 PRIMARY KEY(user_id,request_id)
);
CREATE TABLE IF NOT EXISTS kinnect_core.gift_inventory (
 id text PRIMARY KEY,
 user_id text NOT NULL REFERENCES kinnect_core.users(id),
 gift_id text NOT NULL,
 quantity bigint NOT NULL CHECK(quantity>=0),
 source text NOT NULL,
 created bigint NOT NULL
);
CREATE TABLE IF NOT EXISTS kinnect_core.economy_config (
 id integer PRIMARY KEY CHECK(id=1),
 version bigint NOT NULL,
 data jsonb NOT NULL,
 updated bigint NOT NULL,
 actor text
);
CREATE TABLE IF NOT EXISTS kinnect_core.package_preferences (
 user_id text PRIMARY KEY REFERENCES kinnect_core.users(id),
 live text NOT NULL DEFAULT ''
);
ALTER TABLE kinnect_core.wallet_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.store_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.gift_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.economy_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE kinnect_core.package_preferences ENABLE ROW LEVEL SECURITY;
