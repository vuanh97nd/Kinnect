import {randomUUID} from 'node:crypto';
import {createGroupPolls} from './group-polls.js';
export function createGroups({db,body,fail,text,user,publicUser,blocked,notice,attachments,messageState,mediaCompressor,onCallMessage}){
 const pollsApi=createGroupPolls({db,body,fail,text,user,publicUser,blocked,notice});
 db.exec(`CREATE TABLE IF NOT EXISTS group_deputies(group_id TEXT NOT NULL,user_id TEXT NOT NULL,PRIMARY KEY(group_id,user_id));CREATE TABLE IF NOT EXISTS group_mentions(message_id TEXT NOT NULL,user_id TEXT NOT NULL,PRIMARY KEY(message_id,user_id));CREATE TABLE IF NOT EXISTS group_message_receipts(message_id TEXT NOT NULL,user_id TEXT NOT NULL,delivered_at INTEGER,seen_at INTEGER,PRIMARY KEY(message_id,user_id));CREATE TABLE IF NOT EXISTS chat_groups(id TEXT PRIMARY KEY,name TEXT NOT NULL,owner TEXT NOT NULL REFERENCES users(id),created INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS group_members(group_id TEXT REFERENCES chat_groups(id) ON DELETE CASCADE,user_id TEXT REFERENCES users(id),joined INTEGER NOT NULL,seen_at INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(group_id,user_id));
 CREATE TABLE IF NOT EXISTS group_messages(id TEXT PRIMARY KEY,group_id TEXT REFERENCES chat_groups(id) ON DELETE CASCADE,sender TEXT REFERENCES users(id),body TEXT NOT NULL,created INTEGER NOT NULL);`);
 db.exec(`CREATE TABLE IF NOT EXISTS group_avatars(group_id TEXT PRIMARY KEY, data TEXT NOT NULL DEFAULT '',preset TEXT NOT NULL DEFAULT 'violet',updated INTEGER NOT NULL);
 CREATE TABLE IF NOT EXISTS chat_request_ids(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,kind TEXT NOT NULL CHECK(kind IN ('direct','group')),target_id TEXT NOT NULL,request_id TEXT NOT NULL,message_id TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(user_id,kind,target_id,request_id));
 CREATE INDEX IF NOT EXISTS chat_request_ids_created ON chat_request_ids(created);`);
 const get=(s,...p)=>db.prepare(s).get(...p),all=(s,...p)=>db.prepare(s).all(...p),run=(s,...p)=>db.prepare(s).run(...p);
 const members=id=>all('SELECT u.* FROM users u JOIN group_members m ON m.user_id=u.id WHERE m.group_id=? ORDER BY m.joined,u.id',id);
 function access(id,me){const group=get('SELECT g.* FROM chat_groups g JOIN group_members m ON m.group_id=g.id WHERE g.id=? AND m.user_id=?',id,me.id);if(!group)fail(404,'Không tìm thấy nhóm.');return group;}
 function hasMention(content,username){
   if(!username)return false;const token='@'+username;
   for(let at=content.indexOf(token);at>=0;at=content.indexOf(token,at+token.length)){
     const end=at+token.length,before=at===0?' ':content[at-1];
     if((at===0||/[\s([{]/u.test(before))&&(end===content.length||!/[\p{L}\p{N}_.-]/u.test(content[end])))return true;
   }return false;
 }
 const deputy=(id,uid)=>!!get('SELECT 1 FROM group_deputies WHERE group_id=? AND user_id=?',id,uid);
 const manages=(g,uid)=>g.owner===uid||deputy(g.id,uid);
 const decorateGroupMessage=(m,group,viewer)=>messageState.decorate('group',{
  ...m,
  receipt:{
   deliveredCount:get('SELECT COUNT(*) AS n FROM group_message_receipts WHERE message_id=? AND delivered_at IS NOT NULL',m.id).n,
   seenCount:get('SELECT COUNT(*) AS n FROM group_message_receipts WHERE message_id=? AND seen_at IS NOT NULL',m.id).n,
  },
  attachment:attachments.metadata('group',m.id),
  mentions:all('SELECT user_id FROM group_mentions WHERE message_id=?',m.id)
   .filter(row=>!blocked(viewer.id,row.user_id)&&user(row.user_id)?.suspended===0)
   .map(row=>publicUser(user(row.user_id),viewer.id)),
  author:{
   ...publicUser(user(m.sender),viewer.id),
   groupRole:m.sender===group.owner?'owner':deputy(group.id,m.sender)?'deputy':'member',
  },
 },viewer.id);
 function summary(g,me){const last=all("SELECT m.*,u.name FROM group_messages m JOIN users u ON u.id=m.sender WHERE group_id=? AND u.suspended=0 AND m.id NOT IN (SELECT message_id FROM hidden_chat_messages WHERE kind='group' AND user_id=?) ORDER BY m.created DESC,m.rowid DESC LIMIT 20",g.id,me.id).find(m=>!blocked(me.id,m.sender));const photo=get('SELECT * FROM group_avatars WHERE group_id=?',g.id);return {...g,avatar:photo?.data||null,avatarPreset:photo?.preset||'violet',pinned:messageState.pinnedConversation('group',g.id,me.id),muted:messageState.muted('group',g.id,me.id),members:members(g.id).filter(u=>!u.suspended).map(u=>({...publicUser(u,me.id),groupRole:u.id===g.owner?'owner':deputy(g.id,u.id)?'deputy':'member'})),unread:Math.max(messageState.manualUnread('group',g.id,me.id)?1:0,all('SELECT m.sender FROM group_messages m JOIN users u ON u.id=m.sender WHERE m.group_id=? AND m.sender<>? AND u.suspended=0 AND m.created>(SELECT seen_at FROM group_members WHERE group_id=? AND user_id=?)',g.id,me.id,g.id,me.id).filter(m=>!blocked(me.id,m.sender)).length),last:last?{body:messageState.recalled('group',last.id)?'Tin nhắn đã được thu hồi':last.body.slice(0,120)||attachments.metadata('group',last.id)?.name||'Tệp đính kèm',created:last.created,mine:last.sender===me.id,name:last.name}:null};}
 function validMembers(ids,me){if(!Array.isArray(ids)||ids.length>49)fail(400,'Nhóm tối đa 50 thành viên.');const unique=[...new Set(ids)].filter(id=>id!==me.id);for(const id of unique){const u=user(id);if(!u||u.suspended||blocked(id,me.id))fail(400,'Không thể thêm thành viên đã chọn.');}return unique;}
 return async function groups(req,path,me,json){
  if(path==='/api/groups'){
   if(req.method==='GET'){run('INSERT INTO group_message_receipts(message_id,user_id,delivered_at) SELECT m.id,?,? FROM group_messages m JOIN group_members gm ON gm.group_id=m.group_id WHERE gm.user_id=? AND m.sender<>? AND m.created>=gm.joined AND NOT EXISTS (SELECT 1 FROM group_message_receipts r WHERE r.message_id=m.id AND r.user_id=? AND r.delivered_at IS NOT NULL) ON CONFLICT(message_id,user_id) DO UPDATE SET delivered_at=COALESCE(delivered_at,excluded.delivered_at)',me.id,Date.now(),me.id,me.id,me.id);const groups=all('SELECT g.* FROM chat_groups g JOIN group_members m ON m.group_id=g.id WHERE m.user_id=?',me.id).filter(g=>!messageState.hidden('group',g.id,me.id)).map(g=>summary(g,me)).sort((a,b)=>(b.last?.created||b.created)-(a.last?.created||a.created));json(200,{groups});return true;}
   if(req.method==='POST'){const b=await body(req),name=text(b.name,80),ids=validMembers(b.members||b.memberIds,me);if(!name||!ids.length)fail(400,'Nhập tên nhóm và chọn ít nhất một thành viên.');if(get('SELECT COUNT(*) AS n FROM group_members WHERE user_id=?',me.id).n>=100)fail(400,'Bạn đã tham gia tối đa 100 nhóm.');const id=randomUUID(),now=Date.now();db.exec('BEGIN');try{run('INSERT INTO chat_groups VALUES(?,?,?,?)',id,name,me.id,now);for(const uid of [me.id,...ids])run('INSERT INTO group_members VALUES(?,?,?,?)',id,uid,now,now);db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}json(201,{group:summary(access(id,me),me)});return true;}
  }
  const msgEdit=path.match(/^\/api\/groups\/([a-zA-Z0-9-]+)\/messages\/([a-zA-Z0-9-]+)$/);
  if(msgEdit&&req.method==='PATCH'){
   const [,gid,mid]=msgEdit;const group=access(gid,me);
   const existing=get('SELECT group_id FROM group_messages WHERE id=?',mid);
   if(!existing||existing.group_id!==gid)fail(404,'Không tìm thấy tin nhắn.');
   const b=await body(req,16000);
   const edited=messageState.editMessage('group',mid,me,b.body,{mentions:b.mentions});
   const fresh=get('SELECT * FROM group_messages WHERE id=?',mid);
   json(200,{ok:true,message:fresh?decorateGroupMessage(fresh,group,me):edited});return true;
  }
  const pollMatch=path.match(/^\/api\/groups\/([a-zA-Z0-9-]+)\/polls(?:\/([a-zA-Z0-9-]+)(?:\/(vote|close))?)?$/);
  if(pollMatch){
   const [,gid,pollId,subAction]=pollMatch,group=access(gid,me);
   return await pollsApi.handle({req,group,pollId,subAction,me,manages,members,json});
  }
  const match=path.match(/^\/api\/groups\/([a-zA-Z0-9-]+)(?:\/(messages\/search|messages|members|leave|roles|avatar))?$/);if(!match)return false;const [,id,action]=match,g=access(id,me);
  if(action==='avatar'&&req.method==='POST'){
    if(!manages(g,me.id))fail(403,'Chỉ trưởng hoặc phó nhóm được đổi ảnh nhóm.');const b=await body(req,1500000);let data='',preset='violet';
    if(b.preset!==undefined){if(!['violet','ocean','sunset','forest'].includes(b.preset))fail(400,'Ảnh mẫu không hợp lệ.');preset=b.preset;}
    else {if(typeof b.data!=='string'||!/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(b.data))fail(400,'Chọn ảnh PNG/JPEG/WebP.');const bytes=Buffer.from(b.data.split(',')[1],'base64');if(bytes.length<16||bytes.length>1024*1024)fail(400,'Ảnh phải nhỏ hơn 1 MB.');const type=b.data.split(';')[0];const valid=type==='data:image/png'?bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])):type==='data:image/jpeg'?bytes[0]===255&&bytes[1]===216&&bytes[2]===255:bytes.toString('ascii',0,4)==='RIFF'&&bytes.toString('ascii',8,12)==='WEBP';if(!valid)fail(400,'Ảnh không hợp lệ.');const rawType=type.slice(5);const opt=mediaCompressor?await mediaCompressor.compressImage(bytes,rawType,'avatar'):{type:rawType,bytes};data='data:'+opt.type+';base64,'+opt.bytes.toString('base64');}
    run('INSERT INTO group_avatars VALUES(?,?,?,?) ON CONFLICT(group_id) DO UPDATE SET data=excluded.data,preset=excluded.preset,updated=excluded.updated',id,data,preset,Date.now());json(200,{group:summary(access(id,me),me)});return true;
  }
  if(action==='roles'&&req.method==='PATCH'){
    if(g.owner!==me.id)fail(403,'Chỉ trưởng nhóm được phân quyền.');
    const b=await body(req);if(!['deputy','member','owner'].includes(b.role)||b.userId===me.id)fail(400,'Vai trò không hợp lệ.');
    if(!get('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?',id,b.userId)||user(b.userId)?.suspended!==0)fail(404,'Không tìm thấy thành viên.');
    if(b.role==='owner'){db.exec('BEGIN');try{run('UPDATE chat_groups SET owner=? WHERE id=?',b.userId,id);run('DELETE FROM group_deputies WHERE group_id=? AND user_id=?',id,b.userId);db.exec('COMMIT');}catch(e){db.exec('ROLLBACK');throw e;}}
    else if(b.role==='deputy')run('INSERT OR IGNORE INTO group_deputies VALUES(?,?)',id,b.userId);
    else run('DELETE FROM group_deputies WHERE group_id=? AND user_id=?',id,b.userId);
    json(200,{group:summary(access(id,me),me)});return true;
  }
  if(!action&&req.method==='GET'){json(200,{group:summary(g,me)});return true;}
  if(!action&&req.method==='PATCH'){if(!manages(g,me.id))fail(403,'Chỉ trưởng hoặc phó nhóm được đổi tên.');const b=await body(req),name=text(b.name,80);if(!name)fail(400,'Nhập tên nhóm.');run('UPDATE chat_groups SET name=? WHERE id=?',name,id);json(200,{group:summary(access(id,me),me)});return true;}
  if(action==='messages'&&req.method==='DELETE'){messageState.clear('group',id,me.id);json(200,{ok:true});return true;}
  if(action==='messages'&&req.method==='GET'){
   const params=new URL(req.url,'http://local').searchParams,rawBefore=Number(params.get('before')),before=Number.isSafeInteger(rawBefore)&&rawBefore>0?rawBefore:null,rawLimit=Number.parseInt(params.get('limit')||'',10),limit=Number.isFinite(rawLimit)&&rawLimit>=1?Math.min(100,rawLimit):100;
   if(!before){messageState.markRead('group',id,me.id);const readAt=Date.now();run('INSERT INTO group_message_receipts(message_id,user_id,delivered_at,seen_at) SELECT id,?,?,? FROM group_messages WHERE group_id=? AND sender<>? AND NOT EXISTS (SELECT 1 FROM group_message_receipts r WHERE r.message_id=group_messages.id AND r.user_id=? AND r.seen_at IS NOT NULL) ON CONFLICT(message_id,user_id) DO UPDATE SET delivered_at=COALESCE(delivered_at,excluded.delivered_at),seen_at=COALESCE(seen_at,excluded.seen_at)',me.id,readAt,readAt,id,me.id,me.id);}
   const raw=before
    ?all("SELECT m.* FROM group_messages m JOIN users u ON u.id=m.sender WHERE m.group_id=? AND m.created<? AND u.suspended=0 AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.actor=? AND b.target=m.sender) OR (b.target=? AND b.actor=m.sender)) AND NOT EXISTS (SELECT 1 FROM hidden_chat_messages h WHERE h.kind='group' AND h.message_id=m.id AND h.user_id=?) ORDER BY m.created DESC,m.rowid DESC LIMIT ?",id,before,me.id,me.id,me.id,limit+1)
    :all("SELECT m.* FROM group_messages m JOIN users u ON u.id=m.sender WHERE m.group_id=? AND u.suspended=0 AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.actor=? AND b.target=m.sender) OR (b.target=? AND b.actor=m.sender)) AND NOT EXISTS (SELECT 1 FROM hidden_chat_messages h WHERE h.kind='group' AND h.message_id=m.id AND h.user_id=?) ORDER BY m.created DESC,m.rowid DESC LIMIT ?",id,me.id,me.id,me.id,limit+1);
   const hasMore=raw.length>limit,slice=raw.slice(0,limit),nextCursor=hasMore&&slice.length?slice[slice.length-1].created:null;
   const messages=slice.reverse().map(m=>decorateGroupMessage(m,g,me));
   if(!before){const newest=get('SELECT COALESCE(MAX(created),0) AS t FROM group_messages WHERE group_id=?',id).t;run('UPDATE group_members SET seen_at=MAX(seen_at,?) WHERE group_id=? AND user_id=?',newest,id,me.id);run("UPDATE notifications SET seen=1 WHERE user_id=? AND kind='group_message' AND ref=?",me.id,id);}
   json(200,{messages,hasMore,nextCursor});return true;
  }
  if(action==='messages/search'&&req.method==='GET'){
   const params=new URL(req.url,'http://local').searchParams,q=text(params.get('q'),100),rawLimit=Number.parseInt(params.get('limit')||'',10),limit=Number.isFinite(rawLimit)&&rawLimit>=1?Math.min(50,rawLimit):30;
   if(!q)return json(200,{messages:[],query:''}),true;
   const needle=q.normalize('NFD').replace(/\p{M}/gu,'').replace(/[đĐ]/g,'d').toLowerCase();
   const messages=all(
    "SELECT m.* FROM group_messages m JOIN users u ON u.id=m.sender WHERE m.group_id=? AND u.suspended=0 AND admin_search_key(m.body) LIKE ? ESCAPE '\\' AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.actor=? AND b.target=m.sender) OR (b.target=? AND b.actor=m.sender)) AND NOT EXISTS (SELECT 1 FROM hidden_chat_messages h WHERE h.kind='group' AND h.message_id=m.id AND h.user_id=?) AND NOT EXISTS (SELECT 1 FROM recalled_chat_messages r WHERE r.kind='group' AND r.message_id=m.id) ORDER BY m.created DESC,m.rowid DESC LIMIT ?",
    id,'%'+needle.replace(/[\\%_]/g,'\\$&')+'%',me.id,me.id,me.id,limit
   ).map(m=>messageState.decorate('group',{...m,attachment:attachments.metadata('group',m.id),author:{...publicUser(user(m.sender),me.id),groupRole:m.sender===g.owner?'owner':deputy(id,m.sender)?'deputy':'member'}},me.id));
   json(200,{messages,query:q});return true;
  }
  if(action==='messages'&&req.method==='POST'){
   const b=await body(req,29000000);
   if(b.mentions!==undefined&&(!Array.isArray(b.mentions)||b.mentions.length>50))fail(400,'Danh sách nhắc tên không hợp lệ.');
   let reqId='';
   if(b.requestId!==undefined&&b.requestId!==null&&b.requestId!==''){
    if(typeof b.requestId!=='string'||!b.requestId.trim()||b.requestId.trim().length>128)fail(400,'Mã yêu cầu không hợp lệ.');
    reqId=b.requestId.trim();
    const prev=get("SELECT message_id FROM chat_request_ids WHERE user_id=? AND kind='group' AND target_id=? AND request_id=?",me.id,id,reqId);
    if(prev){
     const existingMsg=get('SELECT * FROM group_messages WHERE id=? AND group_id=?',prev.message_id,id);
     if(existingMsg){json(200,{duplicate:true,message:decorateGroupMessage(existingMsg,g,me)});return true;}
    }
   }
   const content=text(b.body,2000),file=attachments.decode(b.attachment);
   if(!content&&!file)fail(400,'Nhập tin nhắn hoặc chọn tệp.');
   const replyToId=messageState.resolveReplyTarget('group',id,b.replyToId,me.id);
   if(file&&mediaCompressor&&file.type.startsWith('image/')){const opt=await mediaCompressor.compressImage(file.bytes,file.type,'chat');if(opt.compressed){file.bytes=opt.bytes;file.type=opt.type;file.name=file.name.replace(/\.(png|webp)$/i,'.jpg');}}
   let groupMembers=[];
   const mentioned=new Set(Array.isArray(b.mentions)?b.mentions:[]);
   let message=null,duplicateMessage=null;
   db.exec('BEGIN IMMEDIATE');
   try{
    if(user(me.id)?.suspended!==0)fail(401,'Tài khoản không còn hoạt động.');
    if(!get('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?',id,me.id))fail(404,'Không tìm thấy nhóm.');
    groupMembers=members(id);
    if(reqId){
     const prev=get("SELECT message_id FROM chat_request_ids WHERE user_id=? AND kind='group' AND target_id=? AND request_id=?",me.id,id,reqId);
     if(prev){
      const existingMsg=get('SELECT * FROM group_messages WHERE id=? AND group_id=?',prev.message_id,id);
      if(existingMsg)duplicateMessage=existingMsg;
     }
    }
    if(!duplicateMessage){
     const now=Math.max(Date.now(),(get('SELECT MAX(created) AS t FROM group_messages WHERE group_id=?',id).t||0)+1);
     message={id:randomUUID(),group_id:id,sender:me.id,body:content,created:now};
     run('INSERT INTO group_messages VALUES(?,?,?,?,?)',message.id,id,me.id,content,now);
     messageState.linkReply('group',message.id,replyToId);
     attachments.save('group',message.id,file);
     for(const candidate of groupMembers)if(candidate.id!==me.id&&candidate.suspended===0&&!blocked(me.id,candidate.id)&&mentioned.has(candidate.id)&&hasMention(content,candidate.username))run('INSERT OR IGNORE INTO group_mentions VALUES(?,?)',message.id,candidate.id);
     if(reqId)run("INSERT OR REPLACE INTO chat_request_ids(user_id,kind,target_id,request_id,message_id,created) VALUES(?, 'group', ?, ?, ?, ?)",me.id,id,reqId,message.id,now);
    }
    db.exec('COMMIT');
   }catch(e){db.exec('ROLLBACK');throw e;}
   if(duplicateMessage){json(200,{duplicate:true,message:decorateGroupMessage(duplicateMessage,g,me)});return true;}
   if(file&&mediaCompressor&&(file.type==='video/mp4'||file.type==='video/webm'))mediaCompressor.enqueueVideo({table:'chat_attachments',id:file.id,bytes:file.bytes,type:file.type,profile:'chat'});
   const activeRecipients=[];
   for(const member of groupMembers){
    if(member.id===me.id||(member.suspended===0&&!blocked(me.id,member.id))){
     messageState.reveal('group',id,member.id);
     activeRecipients.push(member.id);
     if(member.id!==me.id)notice(member.id,me.id,'group_message',id,message.id);
    }
   }
   onCallMessage?.({userIds:activeRecipients});
   json(201,{message:decorateGroupMessage(message,g,me)});return true;
  }
  if(action==='members'&&req.method==='POST'){if(!manages(g,me.id))fail(403,'Chỉ trưởng hoặc phó nhóm được thêm thành viên.');const b=await body(req),ids=validMembers(b.members,me);const existing=members(id).map(u=>u.id);if(new Set([...existing,...ids]).size>50)fail(400,'Nhóm tối đa 50 thành viên.');const now=Date.now();for(const uid of ids)run('INSERT OR IGNORE INTO group_members VALUES(?,?,?,?)',id,uid,now,now);json(200,{group:summary(g,me)});return true;}
  if(action==='members'&&req.method==='DELETE'){if(!manages(g,me.id))fail(403,'Chỉ trưởng hoặc phó nhóm được xóa thành viên.');const b=await body(req);if(b.userId===me.id)fail(400,'Dùng Rời nhóm để chuyển quyền và rời nhóm.');if(b.userId===g.owner||(g.owner!==me.id&&deputy(id,b.userId)))fail(403,'Không được xóa trưởng hoặc phó nhóm.');if(!get('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?',id,b.userId))fail(404,'Không tìm thấy thành viên.');run('DELETE FROM group_deputies WHERE group_id=? AND user_id=?',id,b.userId);run('DELETE FROM group_members WHERE group_id=? AND user_id=?',id,b.userId);run("DELETE FROM notifications WHERE user_id=? AND kind='group_message' AND ref=?",b.userId,id);json(200,{group:summary(g,me)});return true;}
  if(action==='leave'&&req.method==='POST'){
   db.exec('BEGIN IMMEDIATE');
   try{
    run('DELETE FROM group_deputies WHERE group_id=? AND user_id=?',id,me.id);
    run('DELETE FROM group_members WHERE group_id=? AND user_id=?',id,me.id);
    const next=get('SELECT gm.user_id FROM group_members gm JOIN users u ON u.id=gm.user_id WHERE gm.group_id=? ORDER BY u.suspended ASC, EXISTS(SELECT 1 FROM group_deputies d WHERE d.group_id=gm.group_id AND d.user_id=gm.user_id) DESC, gm.joined ASC, gm.user_id ASC LIMIT 1',id);
    if(!next){
     const msgIds='SELECT id FROM group_messages WHERE group_id=?';
     for(const aux of ['chat_attachments','pinned_chat_messages','chat_message_reactions','hidden_chat_messages','recalled_chat_messages','edited_chat_messages']){
      run(`DELETE FROM ${aux} WHERE kind='group' AND message_id IN (${msgIds})`,id);
     }
     run(`DELETE FROM chat_message_replies WHERE kind='group' AND (message_id IN (${msgIds}) OR reply_to_id IN (${msgIds}))`,id,id);
     run(`DELETE FROM group_mentions WHERE message_id IN (${msgIds})`,id);
     run(`DELETE FROM group_message_receipts WHERE message_id IN (${msgIds})`,id);
     run('DELETE FROM group_deputies WHERE group_id=?',id);
     run('DELETE FROM group_avatars WHERE group_id=?',id);
     for(const conv of ['manual_unread_conversations','pinned_conversations','muted_conversations','hidden_conversations']){
      run(`DELETE FROM ${conv} WHERE kind='group' AND conversation_id=?`,id);
     }
     run("DELETE FROM chat_request_ids WHERE kind='group' AND target_id=?",id);
     run("DELETE FROM notifications WHERE kind='group_message' AND ref=?",id);
     run('DELETE FROM chat_groups WHERE id=?',id);
    }else if(g.owner===me.id){
     run('UPDATE chat_groups SET owner=? WHERE id=?',next.user_id,id);
     run('DELETE FROM group_deputies WHERE group_id=? AND user_id=?',id,next.user_id);
    }
    run("DELETE FROM notifications WHERE user_id=? AND kind='group_message' AND ref=?",me.id,id);
    db.exec('COMMIT');
   }catch(e){db.exec('ROLLBACK');throw e;}
   json(200,{ok:true});return true;
  }
  fail(405,'Thao tác không được hỗ trợ.');
 };
}
