CREATE SCHEMA IF NOT EXISTS kinnect_chat;
SET search_path TO kinnect_chat, pg_catalog;
-- No credential/profile copy: user IDs reference the future PostgreSQL authority.
CREATE TABLE chat_conversations (
 id TEXT PRIMARY KEY,
 kind TEXT NOT NULL CHECK(kind IN ('direct','group')),
 direct_pair TEXT UNIQUE,
 name TEXT NOT NULL DEFAULT '',
 created_by TEXT NOT NULL,
 created_at BIGINT NOT NULL,
 CHECK((kind='direct' AND direct_pair IS NOT NULL) OR (kind='group' AND direct_pair IS NULL))
);
CREATE TABLE chat_members (
 conversation_id TEXT NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL,
 role TEXT NOT NULL DEFAULT 'member' CHECK(role IN ('owner','deputy','member')),
 joined_at BIGINT NOT NULL,
 left_at BIGINT,
 PRIMARY KEY(conversation_id,user_id)
);
CREATE INDEX chat_members_user ON chat_members(user_id,left_at,conversation_id);
CREATE TABLE chat_messages (
 id TEXT PRIMARY KEY,
 conversation_id TEXT NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
 sender_id TEXT NOT NULL,
 client_nonce TEXT NOT NULL,
 body TEXT NOT NULL,
 kind TEXT NOT NULL DEFAULT 'text' CHECK(kind IN ('text','attachment','system')),
 attachment_key TEXT,
 reply_to TEXT REFERENCES chat_messages(id),
 created_at BIGINT NOT NULL,
 edited_at BIGINT,
 recalled_at BIGINT,
 UNIQUE(sender_id,client_nonce)
);
CREATE INDEX chat_messages_timeline ON chat_messages(conversation_id,created_at,id);
CREATE TABLE chat_receipts (
 message_id TEXT NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL,
 delivered_at BIGINT,
 seen_at BIGINT,
 PRIMARY KEY(message_id,user_id),
 CHECK(seen_at IS NULL OR (delivered_at IS NOT NULL AND seen_at>=delivered_at))
);
CREATE INDEX chat_receipts_user ON chat_receipts(user_id,message_id);

CREATE TABLE chat_hidden_messages (
 message_id TEXT NOT NULL REFERENCES chat_messages(id),
 user_id TEXT NOT NULL,
 PRIMARY KEY(message_id,user_id)
);
CREATE TABLE chat_reactions (
 message_id TEXT NOT NULL REFERENCES chat_messages(id),
 user_id TEXT NOT NULL,
 reaction TEXT NOT NULL CHECK(reaction IN ('like','love','haha','wow','sad','angry')),
 PRIMARY KEY(message_id,user_id)
);
CREATE TABLE chat_preferences (
 conversation_id TEXT NOT NULL REFERENCES chat_conversations(id),
 user_id TEXT NOT NULL,
 hidden BIGINT NOT NULL DEFAULT 0,
 muted BIGINT NOT NULL DEFAULT 0,
 pinned BIGINT NOT NULL DEFAULT 0,
 unread BIGINT NOT NULL DEFAULT 0,
 PRIMARY KEY(conversation_id,user_id)
);
CREATE TABLE chat_pins (
 message_id TEXT PRIMARY KEY REFERENCES chat_messages(id),
 pinned_by TEXT NOT NULL
);
CREATE TABLE chat_attachment_refs (
 id TEXT PRIMARY KEY,
 message_id TEXT NOT NULL REFERENCES chat_messages(id),
 name TEXT NOT NULL,
 mime_type TEXT NOT NULL,
 byte_size BIGINT NOT NULL,
 source_sha256 TEXT NOT NULL,
 local_key TEXT NOT NULL
);


-- No client access. A dedicated backend role is provisioned separately.
REVOKE ALL ON SCHEMA kinnect_chat FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA kinnect_chat FROM PUBLIC;
