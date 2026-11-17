-- Phase 1 Chat Indexes: speed up active conversation membership & visible inbox queries.
CREATE INDEX IF NOT EXISTS chat_members_conv_active ON kinnect_chat.chat_members(conversation_id, user_id) WHERE left_at IS NULL;
CREATE INDEX IF NOT EXISTS chat_conversations_kind_created ON kinnect_chat.chat_conversations(kind, created_at DESC);
CREATE INDEX IF NOT EXISTS chat_prefs_user_visible ON kinnect_chat.chat_preferences(user_id, conversation_id) WHERE hidden = 0;
