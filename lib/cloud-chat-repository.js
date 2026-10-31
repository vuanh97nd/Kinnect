import {randomUUID} from 'node:crypto';
const deny=()=>{throw Object.assign(Error('Conversation unavailable'),{status:404});};
export function createCloudChatRepository({db,authorize,clock=Date.now,id=randomUUID}){
 if(typeof authorize!=='function')throw Error('Authorization callback required');
 async function access(actor,conversationId){
  // This callback must revalidate account suspension/block/privacy against identity authority.
  if(!actor||!await authorize(actor,conversationId))deny();
  const member=await db.prepare('SELECT user_id FROM chat_members WHERE conversation_id=? AND user_id=? AND left_at IS NULL').bind(conversationId,actor).first();
  if(!member)deny();
 }
 return {
  async list({actor,conversationId,before=null,limit=50}){
   await access(actor,conversationId);
   if(!Number.isInteger(limit)||limit<1||limit>100)throw Error('Invalid page size');
   if(before&&(!Number.isSafeInteger(before.created)||typeof before.id!=='string'))throw Error('Invalid cursor');
   const query=before
    ? db.prepare('SELECT * FROM chat_messages WHERE conversation_id=? AND id NOT IN(SELECT message_id FROM chat_hidden_messages WHERE user_id=?) AND (created_at<? OR (created_at=? AND id<?)) ORDER BY created_at DESC,id DESC LIMIT ?').bind(conversationId,actor,before.created,before.created,before.id,limit)
    : db.prepare('SELECT * FROM chat_messages WHERE conversation_id=? AND id NOT IN(SELECT message_id FROM chat_hidden_messages WHERE user_id=?) ORDER BY created_at DESC,id DESC LIMIT ?').bind(conversationId,actor,limit);
   const {results}=await query.all();return results.map(row=>row.recalled_at?{...row,body:'Tin nhắn đã được thu hồi',attachment_key:null,reply_to:null}:row);
  },
  async send({actor,conversationId,nonce,body,replyTo=null}){
   await access(actor,conversationId);
   if(typeof nonce!=='string'||!/^[A-Za-z0-9_-]{16,80}$/.test(nonce))throw Error('Invalid nonce');
   if(typeof body!=='string'||!body.trim()||body.length>2000)throw Error('Invalid message');
   if(replyTo&&!await db.prepare('SELECT id FROM chat_messages WHERE id=? AND conversation_id=?').bind(replyTo,conversationId).first())deny();
   // Membership is checked inside INSERT too, protecting against a concurrent removal.
   await db.prepare(`INSERT INTO chat_messages(id,conversation_id,sender_id,client_nonce,body,reply_to,created_at)
    SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM chat_members WHERE conversation_id=? AND user_id=? AND left_at IS NULL)
    ON CONFLICT(sender_id,client_nonce) DO NOTHING`).bind(id(),conversationId,actor,nonce,body,replyTo,clock(),conversationId,actor).run();
   const row=await db.prepare('SELECT * FROM chat_messages WHERE sender_id=? AND client_nonce=?').bind(actor,nonce).first();
   if(!row)deny();
   if(row.conversation_id!==conversationId||row.body!==body||row.reply_to!==replyTo)throw Object.assign(Error('Nonce conflict'),{status:409});
   return row;
  },
  async receipt({actor,conversationId,messageId,seen=false}){
   await access(actor,conversationId);
   if(typeof seen!=='boolean')throw Error('Invalid receipt');
   const at=clock();
   // Own messages and pre-join messages cannot be acknowledged; all time is server supplied.
   const result=await db.prepare(`INSERT INTO chat_receipts(message_id,user_id,delivered_at,seen_at)
    SELECT m.id,?,?,? FROM chat_messages m JOIN chat_members c ON c.conversation_id=m.conversation_id
    WHERE m.id=? AND m.conversation_id=? AND m.sender_id<>? AND c.user_id=? AND c.left_at IS NULL AND m.created_at>=c.joined_at
    ON CONFLICT(message_id,user_id) DO UPDATE SET
    delivered_at=MIN(chat_receipts.delivered_at,excluded.delivered_at),
    seen_at=CASE WHEN excluded.seen_at IS NULL THEN chat_receipts.seen_at WHEN chat_receipts.seen_at IS NULL THEN MAX(chat_receipts.delivered_at,excluded.seen_at) ELSE chat_receipts.seen_at END`).bind(actor,at,seen?at:null,messageId,conversationId,actor,actor).run();
   if(!result.meta.changes)deny();
   return await db.prepare('SELECT delivered_at,seen_at FROM chat_receipts WHERE message_id=? AND user_id=?').bind(messageId,actor).first();
  }
 };
}
