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
 hidden INTEGER NOT NULL DEFAULT 0,
 muted INTEGER NOT NULL DEFAULT 0,
 pinned INTEGER NOT NULL DEFAULT 0,
 unread INTEGER NOT NULL DEFAULT 0,
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
 byte_size INTEGER NOT NULL,
 source_sha256 TEXT NOT NULL,
 local_key TEXT NOT NULL
);
