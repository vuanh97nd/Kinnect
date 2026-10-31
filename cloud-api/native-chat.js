import{createHash,randomUUID}from'node:crypto';
import{profile}from'./profile.js';
import{createCloudChatRepository}from'../lib/cloud-chat-repository.js';
import{invalidateUsers}from'./realtime.js';
const fail=(status,message)=>{throw Object.assign(Error(message),{status});};
const pairId=(a,b)=>'dm-'+createHash('sha256').update(JSON.stringify([a,b].sort())).digest('hex').slice(0,32);
const SQL={
 summaries:`SELECT c.*,p.hidden,p.muted,p.pinned,p.unread,
 (SELECT json_group_array(json_object('user_id',x.user_id,'role',x.role,'joined_at',x.joined_at)) FROM chat_members x WHERE x.conversation_id=c.id AND x.left_at IS NULL) members_json,
 (SELECT json_object('id',z.id,'body',z.body,'sender_id',z.sender_id,'created_at',z.created_at,'recalled_at',z.recalled_at) FROM chat_messages z WHERE z.conversation_id=c.id AND z.id NOT IN(SELECT message_id FROM chat_hidden_messages WHERE user_id=?) AND z.sender_id NOT IN(SELECT value FROM json_each(?)) ORDER BY z.created_at DESC,z.id DESC LIMIT 1) last_json,
 (SELECT COUNT(*) FROM chat_messages z WHERE z.conversation_id=c.id AND z.sender_id<>? AND z.id NOT IN(SELECT message_id FROM chat_hidden_messages WHERE user_id=?) AND z.sender_id NOT IN(SELECT value FROM json_each(?)) AND NOT EXISTS(SELECT 1 FROM chat_receipts r WHERE r.message_id=z.id AND r.user_id=? AND r.seen_at IS NOT NULL)) unread_count
 FROM chat_conversations c JOIN chat_members m ON m.conversation_id=c.id LEFT JOIN chat_preferences p ON p.conversation_id=c.id AND p.user_id=m.user_id WHERE m.user_id=? AND m.left_at IS NULL AND c.kind=? AND COALESCE(p.hidden,0)=0 ORDER BY c.created_at DESC LIMIT 100`,
 list:`SELECT c.*,p.hidden,p.muted,p.pinned,p.unread FROM chat_conversations c JOIN chat_members m ON m.conversation_id=c.id LEFT JOIN chat_preferences p ON p.conversation_id=c.id AND p.user_id=m.user_id WHERE m.user_id=? AND m.left_at IS NULL AND COALESCE(p.hidden,0)=0 ORDER BY c.created_at DESC LIMIT 100`,
 members:`SELECT * FROM chat_members WHERE conversation_id=? AND left_at IS NULL ORDER BY joined_at,user_id`,
 conversation:`SELECT c.* FROM chat_conversations c JOIN chat_members m ON m.conversation_id=c.id WHERE c.id=? AND m.user_id=? AND m.left_at IS NULL`,
 byId:`SELECT * FROM chat_conversations WHERE id=?`,
 last:`SELECT * FROM chat_messages WHERE conversation_id=? AND id NOT IN(SELECT message_id FROM chat_hidden_messages WHERE user_id=?) AND sender_id NOT IN(SELECT value FROM json_each(?)) ORDER BY created_at DESC,id DESC LIMIT 1`,
 unread:`SELECT COUNT(*) n FROM chat_messages m WHERE m.conversation_id=? AND m.sender_id<>? AND m.id NOT IN(SELECT message_id FROM chat_hidden_messages WHERE user_id=?) AND m.sender_id NOT IN(SELECT value FROM json_each(?)) AND NOT EXISTS(SELECT 1 FROM chat_receipts r WHERE r.message_id=m.id AND r.user_id=? AND r.seen_at IS NOT NULL)`,
 receipts:`SELECT * FROM chat_receipts WHERE message_id IN(SELECT value FROM json_each(?))`,
 reactions:`SELECT * FROM chat_reactions WHERE message_id IN(SELECT value FROM json_each(?))`,
 pins:`SELECT * FROM chat_pins WHERE message_id IN(SELECT value FROM json_each(?))`,
 files:`SELECT * FROM chat_attachment_refs WHERE message_id IN(SELECT value FROM json_each(?))`,
 createDirect:`INSERT INTO chat_conversations(id,kind,direct_pair,name,created_by,created_at) VALUES(?,'direct',?,'',?,?) ON CONFLICT(id) DO NOTHING`,
 createGroup:`INSERT INTO chat_conversations(id,kind,name,created_by,created_at) VALUES(?,'group',?,?,?)`,
 addMember:`INSERT INTO chat_members(conversation_id,user_id,role,joined_at) VALUES(?,?,?,?) ON CONFLICT(conversation_id,user_id) DO NOTHING`,
 addMembers:`INSERT INTO chat_members(conversation_id,user_id,role,joined_at) SELECT ?,json_extract(value,'$.id'),json_extract(value,'$.role'),? FROM json_each(?) WHERE true ON CONFLICT(conversation_id,user_id) DO NOTHING`,
 reveal:`UPDATE chat_preferences SET hidden=0,unread=0 WHERE conversation_id=? AND user_id=?`,
 revealAll:`UPDATE chat_preferences SET hidden=0,unread=0 WHERE conversation_id=? AND user_id IN(SELECT user_id FROM chat_members WHERE conversation_id=? AND left_at IS NULL)`,
 totalGroups:`SELECT COUNT(*) n FROM chat_members m JOIN chat_conversations c ON c.id=m.conversation_id WHERE m.user_id=? AND m.left_at IS NULL AND c.kind='group'`,
 markRead:`INSERT INTO chat_receipts(message_id,user_id,delivered_at,seen_at) SELECT z.id,?,?,? FROM chat_messages z JOIN chat_members m ON m.conversation_id=z.conversation_id WHERE z.conversation_id=? AND z.sender_id<>? AND m.user_id=? AND m.left_at IS NULL AND z.created_at>=m.joined_at AND z.id IN(SELECT value FROM json_each(?)) ON CONFLICT(message_id,user_id) DO UPDATE SET delivered_at=COALESCE(chat_receipts.delivered_at,excluded.delivered_at),seen_at=COALESCE(chat_receipts.seen_at,excluded.seen_at) WHERE chat_receipts.seen_at IS NULL`,
};
export async function nativeChatRoute({request,env,client,user,json}){
 const path=new URL(request.url).pathname,dm=path.match(/^\/api\/users\/([A-Za-z0-9-]+)\/messages$/),group=path.match(/^\/api\/groups\/([A-Za-z0-9-]+)(?:\/(messages))?$/);
 if(!['/api/conversations','/api/groups'].includes(path)&&!dm&&!group)return null;
 const db=env.CHAT_DB;
 const blocked=(await client.query('SELECT target AS id FROM kinnect_core.blocks WHERE actor=$1 UNION SELECT actor AS id FROM kinnect_core.blocks WHERE target=$1',[user.id])).rows.map(x=>x.id);
 const banned=(await client.query('SELECT id FROM kinnect_core.users WHERE suspended<>0')).rows.map(x=>x.id),excluded=[...new Set([...blocked,...banned])];
 const statement=(key,...values)=>db.prepare(SQL[key]).bind(...values),rows=async(key,...values)=>(await statement(key,...values).all()).results;
 async function people(ids){if(!ids.length)return new Map();return new Map((await client.query('SELECT * FROM kinnect_core.users WHERE id=ANY($1::text[]) AND suspended=0',[ids])).rows.map(u=>[u.id,u]));}
 async function context(id){const c=await statement('conversation',id,user.id).first();if(!c)fail(404,'Không tìm thấy cuộc trò chuyện.');const members=await rows('members',id);if(c.kind==='direct'&&members.some(m=>excluded.includes(m.user_id)))fail(404,'Không tìm thấy cuộc trò chuyện.');return{c,members};}
 async function summary(c,members,cachedUsers){
  const users=cachedUsers||await people(members.map(m=>m.user_id));
  const last=Object.hasOwn(c,'last_json')?(c.last_json?JSON.parse(c.last_json):null):await statement('last',c.id,user.id,JSON.stringify(excluded)).first(),unread=Object.hasOwn(c,'unread_count')?{n:c.unread_count}:await statement('unread',c.id,user.id,user.id,JSON.stringify(excluded),user.id).first();
  const common={conversationId:c.id,pinned:!!c.pinned,muted:!!c.muted,unread:Math.max(c.unread?1:0,Number(unread.n)),last:last?{body:last.recalled_at?'Tin nhắn đã được thu hồi':last.body.slice(0,120),created:last.created_at,mine:last.sender_id===user.id,name:users.get(last.sender_id)?.name||''}:null};
  if(c.kind==='direct'){const peer=members.find(m=>m.user_id!==user.id);const row=peer&&users.get(peer.user_id);if(!row||excluded.includes(row.id))return null;return{...profile(row),...common};}
  return{id:c.id,name:c.name,owner:c.created_by,created:c.created_at,avatar:null,avatarPreset:'violet',...common,members:members.filter(m=>users.has(m.user_id)&&!excluded.includes(m.user_id)).map(m=>({...profile(users.get(m.user_id)),groupRole:m.role}))};
 }
 async function body(){const raw=await request.text();if(raw.length>8192)fail(413,'Tệp cần máy chủ media trên PC.');let b;try{b=JSON.parse(raw);}catch{fail(400,'JSON không hợp lệ.');}if(!b||typeof b!=='object'||Array.isArray(b))fail(400,'JSON không hợp lệ.');return b;}
 try{
  if(request.method==='GET'&&['/api/conversations','/api/groups'].includes(path)){
   const contexts=await rows('summaries',user.id,JSON.stringify(excluded),user.id,user.id,JSON.stringify(excluded),user.id,user.id,path==='/api/groups'?'group':'direct');
   for(const c of contexts)c.members=JSON.parse(c.members_json||'[]');
   const users=await people([...new Set(contexts.flatMap(c=>c.members.map(m=>m.user_id)))]);
   const result=[];for(const c of contexts){const value=await summary(c,c.members,users);if(value)result.push(value);}
   result.sort((a,b)=>(b.last?.created||b.created||0)-(a.last?.created||a.created||0));return json(path==='/api/groups'?{groups:result}:{users:result});
  }
  if(path==='/api/groups'&&request.method==='POST'){
   const b=await body(),name=typeof b.name==='string'?b.name.trim().slice(0,80):'';if(!Array.isArray(b.members))fail(400,'Danh sách thành viên không hợp lệ.');const ids=[...new Set(b.members)].filter(x=>x!==user.id);
   if(!name||!ids.length||ids.length>49||ids.some(x=>typeof x!=='string'||excluded.includes(x)))fail(400,'Tên hoặc thành viên nhóm không hợp lệ.');
   if((await people(ids)).size!==ids.length)fail(400,'Không tìm thấy thành viên.');if((await statement('totalGroups',user.id).first()).n>=100)fail(400,'Bạn đã tham gia tối đa 100 nhóm.');
   const id=randomUUID(),now=Date.now();await db.batch([statement('createGroup',id,name,user.id,now),statement('addMembers',id,now,JSON.stringify([user.id,...ids].map(uid=>({id:uid,role:uid===user.id?'owner':'member'}))))]);
   const ctx=await context(id);await invalidateUsers(env,[user.id,...ids]);return json({group:await summary(ctx.c,ctx.members)},201);
  }
  let conversationId,peer;
  if(dm){peer=dm[1];if(peer===user.id||excluded.includes(peer))fail(404,'Không tìm thấy người dùng.');const person=(await people([peer])).get(peer);if(!person)fail(404,'Không tìm thấy người dùng.');conversationId=pairId(user.id,peer);
   const existing=await statement('byId',conversationId).first();
   if(request.method==='POST'){
    const mode=person.profile.dm_mode||'everyone';if(mode==='nobody')fail(403,'Không thể gửi tin nhắn.');if(mode==='friends'){const p=[user.id,peer].sort();if(!(await client.query("SELECT 1 FROM kinnect_core.friendships WHERE low_id=$1 AND high_id=$2 AND status='accepted'",p)).rows.length)fail(403,'Chỉ bạn bè được nhắn tin.');}
    if(!existing)await db.batch([statement('createDirect',conversationId,JSON.stringify([user.id,peer].sort()),user.id,Date.now()),... [user.id,peer].map(uid=>statement('addMember',conversationId,uid,'member',0))]);
   }else if(!existing&&request.method==='GET')return json({messages:[]});
  }else if(group){conversationId=group[1];const ctx=await context(conversationId);if(ctx.c.kind!=='group')fail(404,'Không tìm thấy nhóm.');if(!group[2]&&request.method==='GET')return json({group:await summary(ctx.c,ctx.members)});if(!group[2])fail(405,'Phương thức không hỗ trợ.');}
  if(!conversationId)fail(405,'Phương thức không hỗ trợ.');
  const repository=createCloudChatRepository({db,authorize:async(_,id)=>{await context(id);return true;}}),ctx=await context(conversationId);
  if(request.method==='GET'){
   const list=(await repository.list({actor:user.id,conversationId,limit:100})).filter(m=>!excluded.includes(m.sender_id));
   const messageIds=JSON.stringify(list.map(m=>m.id)),at=Date.now();const acknowledged=await statement('markRead',user.id,at,at,conversationId,user.id,user.id,messageIds).run();
   if(acknowledged.meta?.changes)await invalidateUsers(env,ctx.members.filter(m=>m.user_id!==user.id).map(m=>m.user_id));
   const receipts=await rows('receipts',messageIds),reactions=await rows('reactions',messageIds),pins=await rows('pins',messageIds),files=await rows('files',messageIds),users=await people(ctx.members.map(m=>m.user_id));
   await statement('reveal',conversationId,user.id).run();
   await client.query(dm?"UPDATE kinnect_core.notifications SET seen=1 WHERE user_id=$1 AND actor=$2 AND kind IN ('message','missed_call')":"UPDATE kinnect_core.notifications SET seen=1 WHERE user_id=$1 AND ref=$2 AND kind='group_message'",[user.id,dm?peer:conversationId]);
   return json({messages:list.reverse().map(m=>{
    const seen=receipts.filter(r=>r.message_id===m.id),react=reactions.filter(r=>r.message_id===m.id&&!excluded.includes(r.user_id)),f=files.find(f=>f.message_id===m.id),r=seen.find(r=>r.user_id===peer)||{};
    const counts={};for(const item of react)counts[item.reaction]=(counts[item.reaction]||0)+1;
    return{id:m.id,sender:m.sender_id,...(dm?{recipient:peer===m.sender_id?user.id:peer}:{group_id:conversationId,author:users.has(m.sender_id)?{...profile(users.get(m.sender_id)),groupRole:ctx.members.find(x=>x.user_id===m.sender_id)?.role||'member'}:null}),body:m.body,created:m.created_at,recalled:!!m.recalled_at,pinned:!m.recalled_at&&pins.some(p=>p.message_id===m.id),reactions:m.recalled_at?{}:counts,myReaction:m.recalled_at?null:react.find(r=>r.user_id===user.id)?.reaction||null,mentions:[],privateAlbum:null,receipt:dm?{deliveredAt:r.delivered_at||null,seenAt:r.seen_at||null}:{deliveredCount:seen.filter(x=>x.delivered_at!==null).length,seenCount:seen.filter(x=>x.seen_at!==null).length},attachment:f&&!m.recalled_at?{id:f.id,name:f.name,type:f.mime_type,size:f.byte_size,url:'/api/chat-attachments/'+f.id,kind:f.mime_type.split('/')[0]}:null};
   })});
  }
  if(request.method==='POST'){
   const b=await body();if(b.attachment)fail(503,'Tệp đính kèm cần máy chủ media trên PC.');
   const message=await repository.send({actor:user.id,conversationId,nonce:b.requestId||b.nonce||randomUUID(),body:typeof b.body==='string'?b.body.trim().slice(0,2000):'',replyTo:null});
   await client.query(`INSERT INTO kinnect_core.notifications(id,user_id,actor,kind,ref,seen,created)
    SELECT 'chat_'||md5($1||':'||u.id),u.id,$2,$3,$4,0,$5 FROM kinnect_core.users u
    WHERE u.id=ANY($6::text[]) AND u.id<>$2 AND u.suspended=0 AND NOT EXISTS(SELECT 1 FROM kinnect_core.blocks b WHERE (b.actor=u.id AND b.target=$2) OR (b.actor=$2 AND b.target=u.id)) ON CONFLICT(id) DO NOTHING`,[message.id,user.id,dm?'message':'group_message',dm?message.id:conversationId,message.created_at,ctx.members.map(m=>m.user_id)]);
   await statement('revealAll',conversationId,conversationId).run();await invalidateUsers(env,ctx.members.map(m=>m.user_id));
   return json({message:{id:message.id,sender:message.sender_id,...(dm?{recipient:peer}:{group_id:conversationId}),body:message.body,created:message.created_at}},201);
  }
  fail(405,'Phương thức không hỗ trợ.');
 }catch(error){if(error.status)return json({error:error.message},error.status);if(error.message?.startsWith('Invalid'))return json({error:'Tin nhắn không hợp lệ.'},400);throw error;}
}
