-- No credential/profile copy: user IDs reference the future PostgreSQL authority.
CREATE TABLE chat_conversations (
 id TEXT PRIMARY KEY,
 kind TEXT NOT NULL CHECK(kind IN ('direct','group')),
 direct_pair TEXT UNIQUE,
 name TEXT NOT NULL DEFAULT '',
 created_by TEXT NOT NULL,
 created_at INTEGER NOT NULL,
 CHECK((kind='direct' AND direct_pair IS NOT NULL) OR (kind='group' AND direct_pair IS NULL))
);
CREATE TABLE chat_members (
 conversation_id TEXT NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL,
 role TEXT NOT NULL DEFAULT 'member' CHECK(role IN ('owner','deputy','member')),
 joined_at INTEGER NOT NULL,
 left_at INTEGER,
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
 created_at INTEGER NOT NULL,
 edited_at INTEGER,
 recalled_at INTEGER,
 UNIQUE(sender_id,client_nonce)
);
CREATE INDEX chat_messages_timeline ON chat_messages(conversation_id,created_at,id);
CREATE TABLE chat_receipts (
 message_id TEXT NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
 user_id TEXT NOT NULL,
 delivered_at INTEGER,
 seen_at INTEGER,
 PRIMARY KEY(message_id,user_id),
 CHECK(seen_at IS NULL OR (delivered_at IS NOT NULL AND seen_at>=delivered_at))
);
CREATE INDEX chat_receipts_user ON chat_receipts(user_id,message_id);
