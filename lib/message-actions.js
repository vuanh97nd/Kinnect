export function messageActions({db,fail,blocked,user,body,onCallMessage}){
 db.exec(`CREATE TABLE IF NOT EXISTS manual_unread_conversations(kind TEXT NOT NULL,conversation_id TEXT NOT NULL,user_id TEXT NOT NULL,PRIMARY KEY(kind,conversation_id,user_id));CREATE TABLE IF NOT EXISTS pinned_conversations(kind TEXT NOT NULL,conversation_id TEXT NOT NULL,user_id TEXT NOT NULL,PRIMARY KEY(kind,conversation_id,user_id));CREATE TABLE IF NOT EXISTS pinned_chat_messages(kind TEXT NOT NULL,message_id TEXT NOT NULL,pinned_by TEXT NOT NULL,PRIMARY KEY(kind,message_id));CREATE TABLE IF NOT EXISTS muted_conversations(kind TEXT NOT NULL,conversation_id TEXT NOT NULL,user_id TEXT NOT NULL,PRIMARY KEY(kind,conversation_id,user_id));CREATE TABLE IF NOT EXISTS chat_message_reactions(kind TEXT NOT NULL,message_id TEXT NOT NULL,user_id TEXT NOT NULL,reaction TEXT NOT NULL,PRIMARY KEY(kind,message_id,user_id));CREATE TABLE IF NOT EXISTS hidden_chat_messages(kind TEXT NOT NULL,message_id TEXT NOT NULL,user_id TEXT NOT NULL,PRIMARY KEY(kind,message_id,user_id));CREATE TABLE IF NOT EXISTS recalled_chat_messages(kind TEXT NOT NULL,message_id TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(kind,message_id));CREATE TABLE IF NOT EXISTS hidden_conversations(kind TEXT NOT NULL,conversation_id TEXT NOT NULL,user_id TEXT NOT NULL,PRIMARY KEY(kind,conversation_id,user_id));CREATE TABLE IF NOT EXISTS chat_message_replies(kind TEXT NOT NULL CHECK(kind IN ('direct','group')),message_id TEXT NOT NULL,reply_to_id TEXT NOT NULL,PRIMARY KEY(kind,message_id));CREATE INDEX IF NOT EXISTS chat_message_replies_target ON chat_message_replies(kind,reply_to_id);CREATE TABLE IF NOT EXISTS edited_chat_messages(kind TEXT NOT NULL CHECK(kind IN ('direct','group')),message_id TEXT NOT NULL,edited_at INTEGER NOT NULL,PRIMARY KEY(kind,message_id));`);
 const get=(s,...p)=>db.prepare(s).get(...p),run=(s,...p)=>db.prepare(s).run(...p);
 const visible=(kind,id,uid)=>!get('SELECT 1 FROM hidden_chat_messages WHERE kind=? AND message_id=? AND user_id=?',kind,id,uid);
 const recalled=(kind,id)=>!!get('SELECT 1 FROM recalled_chat_messages WHERE kind=? AND message_id=?',kind,id);
 function hasMention(content,username){
  if(!username)return false;const token='@'+username;
  for(let at=content.indexOf(token);at>=0;at=content.indexOf(token,at+token.length)){
   const end=at+token.length,before=at===0?' ':content[at-1];
   if((at===0||/[\s([{]/u.test(before))&&(end===content.length||!/[\p{L}\p{N}_.-]/u.test(content[end])))return true;
  }return false;
 }
 function notifyChanged(kind,m,actorId){
  if(!onCallMessage)return;
  if(kind==='direct'){onCallMessage({userIds:[m.sender,m.recipient]});return;}
  const recipients=db.prepare('SELECT gm.user_id FROM group_members gm JOIN users u ON u.id=gm.user_id WHERE gm.group_id=? AND u.suspended=0').all(m.group_id).map(r=>r.user_id).filter(uid=>uid===actorId||!blocked(actorId,uid));
  onCallMessage({userIds:recipients});
 }
 function resolveReplyTarget(kind,conversationId,replyToId,meId){
  if(replyToId===undefined||replyToId===null||replyToId==='')return null;
  if(typeof replyToId!=='string'||replyToId.length>100)fail(400,'Tin nhắn trích dẫn không hợp lệ.');
  const target=kind==='direct'
   ?get('SELECT id,sender,recipient FROM messages WHERE id=? AND ((sender=? AND recipient=?) OR (sender=? AND recipient=?))',replyToId,meId,conversationId,conversationId,meId)
   :get('SELECT id,sender,group_id FROM group_messages WHERE id=? AND group_id=?',replyToId,conversationId);
  if(!target||!visible(kind,replyToId,meId)||recalled(kind,replyToId)||blocked(meId,target.sender)||user(target.sender)?.suspended!==0)fail(400,'Không tìm thấy tin nhắn để trích dẫn.');
  return target.id;
 }
 function linkReply(kind,messageId,replyToId){
  if(!replyToId)return;
  run('INSERT OR REPLACE INTO chat_message_replies(kind,message_id,reply_to_id) VALUES(?,?,?)',kind,messageId,replyToId);
 }
 function replyPreview(kind,messageId,uid){
  const link=get('SELECT reply_to_id FROM chat_message_replies WHERE kind=? AND message_id=?',kind,messageId);
  if(!link)return null;
  const targetId=link.reply_to_id;
  const target=kind==='direct'?get('SELECT id,sender,body FROM messages WHERE id=?',targetId):get('SELECT id,sender,body FROM group_messages WHERE id=?',targetId);
  const senderUser=target?user(target.sender):null;
  if(!target||!visible(kind,targetId,uid)||blocked(uid,target.sender)||senderUser?.suspended!==0){
   return {id:targetId,sender:null,senderName:'',body:'Tin nhắn không còn khả dụng',recalled:false,unavailable:true,attachmentKind:null};
  }
  if(recalled(kind,targetId)){
   return {id:targetId,sender:target.sender,senderName:senderUser.name||'',body:'Tin nhắn đã được thu hồi',recalled:true,unavailable:false,attachmentKind:null};
  }
  const att=get('SELECT type FROM chat_attachments WHERE kind=? AND message_id=?',kind,targetId);
  const attachmentKind=att?(att.type.startsWith('image/')?'image':att.type.startsWith('video/')?'video':att.type.startsWith('audio/')?'audio':'file'):null;
  return {id:target.id,sender:target.sender,senderName:senderUser.name||'',body:target.body.slice(0,120),recalled:false,unavailable:false,attachmentKind};
 }
 function decorate(kind,m,uid){if(recalled(kind,m.id))return {...m,body:'Tin nhắn đã được thu hồi',mentions:[],privateAlbum:null,attachment:null,replyTo:null,editedAt:null,recalled:true,reactions:{},myReaction:null};const rows=db.prepare('SELECT user_id,reaction FROM chat_message_reactions WHERE kind=? AND message_id=?').all(kind,m.id).filter(r=>!blocked(uid,r.user_id)&&user(r.user_id)?.suspended===0),reactions={};for(const r of rows)reactions[r.reaction]=(reactions[r.reaction]||0)+1;const editedAt=get('SELECT edited_at FROM edited_chat_messages WHERE kind=? AND message_id=?',kind,m.id)?.edited_at||null;return {...m,editedAt,replyTo:replyPreview(kind,m.id,uid),pinned:!!get('SELECT 1 FROM pinned_chat_messages WHERE kind=? AND message_id=?',kind,m.id),reactions,myReaction:rows.find(r=>r.user_id===uid)?.reaction||null};}
 function editMessage(kind,id,me,rawBody,{mentions}={}){
  const m=get(kind==='direct'?'SELECT * FROM messages WHERE id=?':'SELECT * FROM group_messages WHERE id=?',id);
  if(!m)fail(404,'Không tìm thấy tin nhắn.');
  if(kind==='direct'){if(![m.sender,m.recipient].includes(me.id)||blocked(m.sender,m.recipient)||user(m.sender)?.suspended!==0||user(m.recipient)?.suspended!==0)fail(404,'Không tìm thấy tin nhắn.');}
  else if(!get('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?',m.group_id,me.id)||user(m.sender)?.suspended!==0)fail(404,'Không tìm thấy tin nhắn.');
  if(m.sender!==me.id)fail(403,'Chỉ chỉnh sửa tin nhắn do bạn gửi.');
  if(recalled(kind,id)||!visible(kind,id,me.id))fail(404,'Tin nhắn không khả dụng.');
  if(Date.now()-Number(m.created||0)>24*3600*1000)fail(400,'Chỉ chỉnh sửa tin nhắn trong vòng 24 giờ sau khi gửi.');
  if(kind==='group'&&mentions!==undefined&&(!Array.isArray(mentions)||mentions.length>50))fail(400,'Danh sách nhắc tên không hợp lệ.');
  const clean=typeof rawBody==='string'?rawBody.trim().slice(0,2000):'';
  if(!clean)fail(400,'Nhập nội dung tin nhắn.');
  const editedAt=Date.now();
  db.exec('BEGIN');
  try{
   run(kind==='direct'?'UPDATE messages SET body=? WHERE id=?':'UPDATE group_messages SET body=? WHERE id=?',clean,id);
   run('INSERT OR REPLACE INTO edited_chat_messages(kind,message_id,edited_at) VALUES(?,?,?)',kind,id,editedAt);
   if(kind==='group'){
    run('DELETE FROM group_mentions WHERE message_id=?',id);
    const allowedIds=Array.isArray(mentions)?new Set(mentions):null;
    const groupMembers=db.prepare('SELECT u.id,u.username,u.suspended FROM users u JOIN group_members gm ON gm.user_id=u.id WHERE gm.group_id=?').all(m.group_id);
    for(const candidate of groupMembers){
     if(candidate.id!==me.id&&candidate.suspended===0&&!blocked(me.id,candidate.id)&&(!allowedIds||allowedIds.has(candidate.id))&&hasMention(clean,candidate.username)){
      run('INSERT OR IGNORE INTO group_mentions VALUES(?,?)',id,candidate.id);
     }
    }
   }
   db.exec('COMMIT');
  }catch(e){if(db.isTransaction)db.exec('ROLLBACK');throw e;}
  notifyChanged(kind,m,me.id);
  return decorate(kind,{...m,body:clean},me.id);
 }
 const manualUnread=(kind,id,uid)=>!!get('SELECT 1 FROM manual_unread_conversations WHERE kind=? AND conversation_id=? AND user_id=?',kind,id,uid);
 const markRead=(kind,id,uid)=>run('DELETE FROM manual_unread_conversations WHERE kind=? AND conversation_id=? AND user_id=?',kind,id,uid);
 function clear(kind,id,uid){db.exec('BEGIN');try{markRead(kind,id,uid);if(kind==='direct')run("INSERT OR IGNORE INTO hidden_chat_messages SELECT 'direct',id,? FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)",uid,uid,id,id,uid);else run("INSERT OR IGNORE INTO hidden_chat_messages SELECT 'group',id,? FROM group_messages WHERE group_id=?",uid,id);run('INSERT OR IGNORE INTO hidden_conversations VALUES(?,?,?)',kind,id,uid);if(kind==='direct')run("UPDATE notifications SET seen=1 WHERE user_id=? AND actor=? AND kind IN ('message','missed_call')",uid,id);else{run("UPDATE notifications SET seen=1 WHERE user_id=? AND ref=? AND kind='group_message'",uid,id);run('UPDATE group_members SET seen_at=MAX(seen_at,COALESCE((SELECT MAX(created) FROM group_messages WHERE group_id=?),0)) WHERE group_id=? AND user_id=?',id,id,uid);}db.exec('COMMIT');}catch(e){if(db.isTransaction)db.exec('ROLLBACK');throw e;}}
 const hidden=(kind,id,uid)=>!!get('SELECT 1 FROM hidden_conversations WHERE kind=? AND conversation_id=? AND user_id=?',kind,id,uid);
 function reveal(kind,id,uid){run('DELETE FROM hidden_conversations WHERE kind=? AND conversation_id=? AND user_id=?',kind,id,uid);}
 const pinnedConversation=(kind,id,uid)=>!!get("SELECT 1 FROM pinned_conversations WHERE kind=? AND conversation_id=? AND user_id=?",kind,id,uid);
 const muted=(kind,id,uid)=>!!get('SELECT 1 FROM muted_conversations WHERE kind=? AND conversation_id=? AND user_id=?',kind,id,uid);
 async function handle(req,path,me,json){
 const preference=path.match(/^\/api\/chat-preferences\/(direct|group)\/([a-zA-Z0-9-]+)$/);if(preference){const [,kind,id]=preference;if(kind==='direct'){if(!user(id)||user(id).suspended||blocked(me.id,id)||id===me.id)fail(404,'Không tìm thấy cuộc trò chuyện.');}else if(!get('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?',id,me.id))fail(404,'Không tìm thấy nhóm.');if(req.method==='POST'){const b=await body(req);if(!['muted','pinned','hidden','unread'].some(k=>typeof b[k]==='boolean'))fail(400,'Cài đặt không hợp lệ.');if(typeof b.hidden==='boolean'){if(b.hidden)run('INSERT OR IGNORE INTO hidden_conversations VALUES(?,?,?)',kind,id,me.id);else reveal(kind,id,me.id);}if(typeof b.unread==='boolean'){if(b.unread)run('INSERT OR IGNORE INTO manual_unread_conversations VALUES(?,?,?)',kind,id,me.id);else markRead(kind,id,me.id);}if(typeof b.muted==='boolean'){if(b.muted)run('INSERT OR IGNORE INTO muted_conversations VALUES(?,?,?)',kind,id,me.id);else run('DELETE FROM muted_conversations WHERE kind=? AND conversation_id=? AND user_id=?',kind,id,me.id);}if(typeof b.pinned==='boolean'){if(b.pinned)run('INSERT OR IGNORE INTO pinned_conversations VALUES(?,?,?)',kind,id,me.id);else run('DELETE FROM pinned_conversations WHERE kind=? AND conversation_id=? AND user_id=?',kind,id,me.id);}}else if(req.method!=='GET')fail(405,'Phương thức không hợp lệ.');json(200,{muted:muted(kind,id,me.id),pinned:pinnedConversation(kind,id,me.id),hidden:hidden(kind,id,me.id),unread:manualUnread(kind,id,me.id)});return true;}
 const route=path.match(/^\/api\/chat-messages\/(direct|group)\/([a-zA-Z0-9-]+)(?:\/(recall|reaction|pin))?$/);if(!route)return false;const [,kind,id,action]=route;const m=get(kind==='direct'?'SELECT * FROM messages WHERE id=?':'SELECT * FROM group_messages WHERE id=?',id);if(!m)fail(404,'Không tìm thấy tin nhắn.');if(kind==='direct'){if(![m.sender,m.recipient].includes(me.id)||blocked(m.sender,m.recipient)||user(m.sender)?.suspended!==0||user(m.recipient)?.suspended!==0)fail(404,'Không tìm thấy tin nhắn.');}else if(!get('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?',m.group_id,me.id)||blocked(me.id,m.sender)||user(m.sender)?.suspended!==0)fail(404,'Không tìm thấy tin nhắn.');
 if(action==='pin'&&['POST','DELETE'].includes(req.method)){if(recalled(kind,id)||!visible(kind,id,me.id))fail(404,'Tin nhắn không khả dụng.');if(req.method==='POST')run('INSERT OR IGNORE INTO pinned_chat_messages VALUES(?,?,?)',kind,id,me.id);else run('DELETE FROM pinned_chat_messages WHERE kind=? AND message_id=?',kind,id);json(200,{ok:true});return true;}
 if(action==='reaction'&&req.method==='POST'){if(recalled(kind,id)||!visible(kind,id,me.id))fail(404,'Tin nhắn không khả dụng.');const b=await body(req);if(b.reaction===null)run('DELETE FROM chat_message_reactions WHERE kind=? AND message_id=? AND user_id=?',kind,id,me.id);else{if(!['like','love','haha','wow','sad','angry'].includes(b.reaction))fail(400,'Biểu cảm không hợp lệ.');run('INSERT INTO chat_message_reactions VALUES(?,?,?,?) ON CONFLICT(kind,message_id,user_id) DO UPDATE SET reaction=excluded.reaction',kind,id,me.id,b.reaction);}notifyChanged(kind,m,me.id);json(200,{message:decorate(kind,m,me.id)});return true;}
 if(!action&&req.method==='PATCH'){const b=await body(req,16000);json(200,{ok:true,message:editMessage(kind,id,me,b.body,{mentions:b.mentions})});return true;}
 if(!action&&req.method==='DELETE'){run('INSERT OR IGNORE INTO hidden_chat_messages VALUES(?,?,?)',kind,id,me.id);if(kind==='direct')run("UPDATE notifications SET seen=1 WHERE user_id=? AND ref=? AND kind IN ('message','missed_call')",me.id,id);else run("UPDATE notifications SET seen=1 WHERE user_id=? AND kind='group_message' AND id IN (SELECT notification_id FROM notification_targets WHERE comment_id=?)",me.id,id);json(200,{ok:true});return true;}
 if(action==='recall'&&req.method==='POST'){if(m.sender!==me.id)fail(403,'Chỉ thu hồi tin nhắn do bạn gửi.');db.exec('BEGIN');try{run('INSERT OR IGNORE INTO recalled_chat_messages VALUES(?,?,?)',kind,id,Date.now());run(kind==='direct'?"UPDATE messages SET body='' WHERE id=?":"UPDATE group_messages SET body='' WHERE id=?",id);run('DELETE FROM chat_attachments WHERE kind=? AND message_id=?',kind,id);run('DELETE FROM pinned_chat_messages WHERE kind=? AND message_id=?',kind,id);run('DELETE FROM edited_chat_messages WHERE kind=? AND message_id=?',kind,id);if(kind==='direct')run("UPDATE notifications SET seen=1 WHERE ref=? AND kind IN ('message','missed_call')",id);else{run("UPDATE notifications SET seen=1 WHERE kind='group_message' AND id IN (SELECT notification_id FROM notification_targets WHERE comment_id=?)",id);run('DELETE FROM group_mentions WHERE message_id=?',id);}db.exec('COMMIT');}catch(e){if(db.isTransaction)db.exec('ROLLBACK');throw e;}notifyChanged(kind,m,me.id);json(200,{ok:true});return true;}
 fail(405,'Phương thức không hợp lệ.');}
 return {manualUnread,markRead,visible,recalled,resolveReplyTarget,linkReply,replyPreview,decorate,editMessage,clear,hidden,reveal,muted,pinnedConversation,handle};
}
