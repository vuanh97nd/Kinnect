import{profile}from'./profile.js';
export async function notificationRoute({request,client,env,user,json}){
 if(new URL(request.url).pathname!=='/api/notifications')return null;
 if(request.method==='GET'){
  await env.CHAT_DB.prepare(`INSERT INTO chat_receipts(message_id,user_id,delivered_at)
   SELECT z.id,?,? FROM chat_messages z JOIN chat_members m ON m.conversation_id=z.conversation_id
   WHERE m.user_id=? AND m.left_at IS NULL AND z.sender_id<>? AND z.created_at>=m.joined_at
   ON CONFLICT(message_id,user_id) DO UPDATE SET delivered_at=COALESCE(chat_receipts.delivered_at,excluded.delivered_at)`).bind(user.id,Date.now(),user.id,user.id).run();
  const notifications=(await client.query(`SELECT n.* FROM kinnect_core.notifications n JOIN kinnect_core.users a ON a.id=n.actor
   WHERE n.user_id=$1 AND a.suspended=0 AND NOT EXISTS(SELECT 1 FROM kinnect_core.blocks b WHERE (b.actor=$1 AND b.target=a.id) OR (b.actor=a.id AND b.target=$1)) ORDER BY n.created DESC,n.id DESC LIMIT 100`,[user.id])).rows;
  const actors=new Map((await client.query('SELECT * FROM kinnect_core.users WHERE id=ANY($1::text[])',[[...new Set(notifications.map(n=>n.actor))]])).rows.map(u=>[u.id,u]));
  const metadata=notifications.filter(n=>['message','group_message'].includes(n.kind)).map(n=>({id:n.id,kind:n.kind,ref:n.ref,actor:n.actor,created:Number(n.created)}));
  const previews=(await env.CHAT_DB.prepare(`SELECT json_extract(n.value,'$.id') notification_id,
   (SELECT m.body FROM chat_messages m WHERE
    ((json_extract(n.value,'$.kind')='message' AND m.id=json_extract(n.value,'$.ref')) OR
     (json_extract(n.value,'$.kind')='group_message' AND m.conversation_id=json_extract(n.value,'$.ref') AND m.sender_id=json_extract(n.value,'$.actor') AND m.created_at<=json_extract(n.value,'$.created')+5000))
    AND m.recalled_at IS NULL AND m.id NOT IN(SELECT message_id FROM chat_hidden_messages WHERE user_id=?)
    AND EXISTS(SELECT 1 FROM chat_members cm WHERE cm.conversation_id=m.conversation_id AND cm.user_id=? AND cm.left_at IS NULL)
    ORDER BY m.created_at DESC,m.id DESC LIMIT 1) body FROM json_each(?) n`).bind(user.id,user.id,JSON.stringify(metadata)).all()).results;
  const preferences=(await env.CHAT_DB.prepare(`SELECT c.id,c.kind,p.muted,c.direct_pair FROM chat_preferences p JOIN chat_conversations c ON c.id=p.conversation_id WHERE p.user_id=?`).bind(user.id).all()).results;
  const pending=Number((await client.query("SELECT COUNT(*) n FROM kinnect_core.friendships WHERE (low_id=$1 OR high_id=$1) AND requester<>$1 AND status='pending'",[user.id])).rows[0].n);
  return json({friendRequestsPending:pending,notifications:notifications.map(n=>{const p=preferences.find(p=>p.kind==='group'?p.id===n.ref:p.direct_pair&&JSON.parse(p.direct_pair).includes(n.actor));const body=previews.find(x=>x.notification_id===n.id)?.body||'';return{...n,created:Number(n.created),actor:profile(actors.get(n.actor)),preview:body.startsWith('{')?'':body.replace(/\s+/g,' ').slice(0,160),commentId:null,muted:!!p?.muted};})});
 }
 if(request.method==='POST'){
  const raw=await request.text();if(raw.length>8192)return json({error:'Dữ liệu quá lớn.'},413);let b;try{b=JSON.parse(raw);}catch{return json({error:'JSON không hợp lệ.'},400);}
  if(!b||typeof b!=='object'||Array.isArray(b))return json({error:'JSON không hợp lệ.'},400);
  if(b.ids!==undefined){if(!Array.isArray(b.ids)||b.ids.length>100||b.ids.some(x=>typeof x!=='string'))return json({error:'Danh sách không hợp lệ.'},400);await client.query('UPDATE kinnect_core.notifications SET seen=1 WHERE user_id=$1 AND id=ANY($2::text[])',[user.id,b.ids]);}
  else await client.query(b.scope==='social'?"UPDATE kinnect_core.notifications SET seen=1 WHERE user_id=$1 AND kind NOT IN ('message','group_message')":"UPDATE kinnect_core.notifications SET seen=1 WHERE user_id=$1",[user.id]);
  return json({ok:true});
 }
 return json({error:'Phương thức không hỗ trợ.'},405);
}
