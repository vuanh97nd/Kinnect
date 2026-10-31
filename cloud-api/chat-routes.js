import {createCloudChatRepository} from '../lib/cloud-chat-repository.js';
import {invalidateUsers} from './realtime.js';
export async function cloudChatRoute({request,env,client,user,json}){
 const path=new URL(request.url).pathname;
 const match=path.match(/^\/api\/cloud\/conversations\/([A-Za-z0-9-]+)\/messages(?:\/([A-Za-z0-9-]+)\/receipt)?$/);
 if(!match)return null;
 const [,conversationId,messageId]=match;
 const authorize=async(actor,id)=>{
  const active=await client.query('SELECT 1 FROM kinnect_core.users WHERE id=$1 AND suspended=0',[actor]);
  if(!active.rows.length)return false;
  const conversation=await env.CHAT_DB.prepare('SELECT kind FROM chat_conversations WHERE id=?').bind(id).first();
  if(!conversation)return false;
  if(conversation.kind==='direct'){
   const others=await env.CHAT_DB.prepare('SELECT user_id FROM chat_members WHERE conversation_id=? AND user_id<>? AND left_at IS NULL').bind(id,actor).all();
   if(others.results.length!==1)return false;
   const peer=others.results[0].user_id;
   const allowed=await client.query(`SELECT 1 FROM kinnect_core.users WHERE id=$2 AND suspended=0
    AND NOT EXISTS(SELECT 1 FROM kinnect_core.blocks WHERE (actor=$1 AND target=$2) OR (actor=$2 AND target=$1))`,[actor,peer]);
   return !!allowed.rows.length;
  }
  return true;
 };
 const repository=createCloudChatRepository({db:env.CHAT_DB,authorize});
 try{
  if(request.method==='GET'&&!messageId){
   const list=await repository.list({actor:user.id,conversationId});
   const denied=(await client.query('SELECT target AS id FROM kinnect_core.blocks WHERE actor=$1 UNION SELECT actor AS id FROM kinnect_core.blocks WHERE target=$1',[user.id])).rows.map(x=>x.id);
   const suspended=(await client.query('SELECT id FROM kinnect_core.users WHERE suspended<>0')).rows.map(x=>x.id);
   const excluded=new Set([...denied,...suspended]);
   return json({messages:list.filter(m=>!excluded.has(m.sender_id)).map(m=>({id:m.id,conversationId:m.conversation_id,sender:m.sender_id,body:m.body,created:m.created_at,recalled:!!m.recalled_at}))});
  }
  if(request.method==='POST'){
   const raw=await request.text();if(raw.length>8192)return json({error:'Too large'},413);
   let body;try{body=JSON.parse(raw);}catch{return json({error:'Invalid JSON'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body))return json({error:'Invalid JSON'},400);
   if(messageId)return json(await repository.receipt({actor:user.id,conversationId,messageId,seen:body.seen===true}));
   const conversation=await env.CHAT_DB.prepare('SELECT kind FROM chat_conversations WHERE id=?').bind(conversationId).first();
   if(conversation?.kind==='direct'){
    const peer=await env.CHAT_DB.prepare('SELECT user_id FROM chat_members WHERE conversation_id=? AND user_id<>? AND left_at IS NULL').bind(conversationId,user.id).first();
    if(!peer)return json({error:'Conversation unavailable'},404);
    const result=await client.query('SELECT profile FROM kinnect_core.users WHERE id=$1',[peer.user_id]);
    const mode=result.rows[0]?.profile?.dm_mode;
    if(mode==='nobody')return json({error:'Không thể gửi tin nhắn.'},403);
    if(mode==='friends'){
     const pair=[user.id,peer.user_id].sort();const friends=await client.query("SELECT 1 FROM kinnect_core.friendships WHERE low_id=$1 AND high_id=$2 AND status='accepted'",pair);
     if(!friends.rows.length)return json({error:'Chỉ bạn bè được nhắn tin.'},403);
    }
   }
   const message=await repository.send({actor:user.id,conversationId,nonce:body.nonce,body:body.body,replyTo:body.replyTo||null});
   const recipients=await env.CHAT_DB.prepare('SELECT user_id FROM chat_members WHERE conversation_id=? AND left_at IS NULL').bind(conversationId).all();
   await invalidateUsers(env,recipients.results.map(x=>x.user_id));
   return json({message},201);
  }
  return json({error:'Method not allowed'},405);
 }catch(error){if([403,404,409].includes(error.status))return json({error:error.status===409?'Yêu cầu gửi bị trùng mã.':'Không tìm thấy cuộc trò chuyện.'},error.status);if(error.message?.startsWith('Invalid'))return json({error:'Dữ liệu không hợp lệ.'},400);throw error;}
}
