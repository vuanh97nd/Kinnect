import pg from 'pg';
import {createPostgresIdentity} from '../lib/postgres-identity.js';
import {createPostgresWallet} from '../lib/postgres-wallet.js';
import {cloudChatRoute} from './chat-routes.js';
import {createHash} from 'node:crypto';
import {backendRpc} from './backend-rpc.js';
import {register} from './registration.js';
import {profile} from './profile.js';
import {commerceRoute} from './commerce-routes.js';
import {nativeChatRoute} from './native-chat.js';
import {notificationRoute} from './notification-routes.js';
import {createPostgresChatAdapter} from '../lib/postgres-chat-adapter.js';
import {basicDirectory} from './basic-directory.js';
import {basicFeed,basicVideos,syncFeed} from './basic-feed.js';
export {AuthLimits} from './auth-limits.js';
export {UserEvents} from './realtime.js';
const json=(value,status=200,headers={})=>Response.json(value,{status,headers:{'Cache-Control':'no-store',...headers}});
const cookie=req=>(req.headers.get('Cookie')||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('kinnect_session='))?.slice(16)||'';
export default {async fetch(request,env){
 const path=new URL(request.url).pathname;
 if(path==='/health')return json({ok:true,service:'kinnect-cloud-api',preview:true,productionRouting:false});
 // Isolated integration environment until full route parity and data reconciliation.
 if(!env.PREVIEW_KEY||request.headers.get('X-Kinnect-Preview')!==env.PREVIEW_KEY)return json({error:'Not found'},404);
 if(path==='/internal/d1-query')return backendRpc(request,env);
 if(path==='/internal/auth-limit'){
  if(request.method!=='POST')return json({error:'Method not allowed'},405);
  const raw=await request.text();if(raw.length>256)return json({error:'Too large'},413);
  let body;try{body=JSON.parse(raw);}catch{return json({error:'Invalid JSON'},400);}
  if(!/^[a-f0-9]{64}$/.test(body?.key||''))return json({error:'Invalid key'},400);
  return env.AUTH_LIMITS.get(env.AUTH_LIMITS.idFromName(body.key)).fetch('https://limits/check');
 }
 if(path==='/internal/events'){
  if(request.method!=='POST')return json({error:'Method not allowed'},405);
  const raw=await request.text();if(raw.length>2048)return json({error:'Too large'},413);
  let body;try{body=JSON.parse(raw);}catch{return json({error:'Invalid JSON'},400);}
  if(!/^[A-Za-z0-9_-]{1,100}$/.test(body.userId||'')||!['notify','revoke'].includes(body.action)||body.action==='revoke'&&!/^[a-f0-9]{64}$/.test(body.tokenHash||''))return json({error:'Invalid event'},400);
  return env.USER_EVENTS.get(env.USER_EVENTS.idFromName(body.userId)).fetch('https://events/'+body.action,{method:'POST',body:JSON.stringify({tokenHash:body.tokenHash})});
 }
 if(!['/api/register','/api/login','/api/me','/api/wallet','/api/logout','/api/cloud/events','/api/economy','/api/conversations','/api/notifications','/api/friends','/api/friend-requests','/api/friend-suggestions','/api/discover','/api/posts','/api/shorts','/internal/feed-sync'].includes(path)&&!/^\/api\/users\/[^/]+(?:\/block)?$/.test(path)&&!path.startsWith('/api/cloud/conversations/')&&!path.startsWith('/api/store')&&!path.startsWith('/api/groups')&&!/^\/api\/users\/[^/]+\/messages$/.test(path))return json({error:'Cloud route not ready'},503);
 // Hyperdrive owns the private connection and verifies origin TLS against provider CA.
 // No database response caching: session revocations / wallet reads must be fresh.
 if(!env.HYPERDRIVE)return json({error:'Database binding not ready'},503);
 const client=new pg.Client(env.PC_POSTGRES_OPTIONS||{connectionString:env.HYPERDRIVE.connectionString,connectionTimeoutMillis:10000,query_timeout:10000});
 let chatClient;let stage='request';try{
  if(!['GET','POST','DELETE'].includes(request.method))return json({error:'Method not allowed'},405);
  if(!['GET','HEAD'].includes(request.method)){
   if(!request.headers.get('Content-Type')?.startsWith('application/json'))return json({error:'JSON required'},415);
   const origin=request.headers.get('Origin');if(origin&&new URL(origin).origin!==new URL(request.url).origin)return json({error:'Origin rejected'},403);
  }
  stage='postgres-connect';await client.connect();stage='identity';const identity=createPostgresIdentity({client});
  if(path==='/internal/feed-sync')return syncFeed(request,client,json);
  if(path==='/api/login'||path==='/api/register'){
   if(request.method!=='POST')return json({error:'Method not allowed'},405);
   const address=request.headers.get('X-Kinnect-Client-IP')||request.headers.get('CF-Connecting-IP')||'unknown';
   const bucket=env.AUTH_LIMITS.get(env.AUTH_LIMITS.idFromName(createHash('sha256').update(address).digest('hex')));
   if(!(await(await bucket.fetch('https://limits/check')).json()).allowed)return json({error:'Thử lại sau một phút.'},429);
   const raw=await request.text();if(raw.length>4096)return json({error:'Too large'},413);
   let input;try{input=JSON.parse(raw);}catch{return json({error:'Invalid JSON'},400);}
   if(!input||typeof input!=='object'||Array.isArray(input))return json({error:'Invalid JSON'},400);
   if(path==='/api/register'){
    await client.query('BEGIN');try{const user=await register(client,input),token=await identity.createSession(user.id);await client.query('COMMIT');return json({user:profile(user,true)},200,{'Set-Cookie':`kinnect_session=${token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=604800`});}
    catch(error){await client.query('ROLLBACK');if(error.code==='23505')return json({error:'Tên đăng nhập đã được dùng.'},409);if(error.status)return json({error:error.message},error.status);throw error;}
   }
   const user=await identity.verify(typeof input?.username==='string'?input.username.trim().toLowerCase():null,input?.password);
   if(!user)return json({error:'Thông tin đăng nhập không đúng hoặc tài khoản không khả dụng.'},401);
   const token=await identity.createSession(user.id);
   return json({user:profile(user,true)},200,{'Set-Cookie':`kinnect_session=${token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=604800`});
  }
  const token=cookie(request),user=await identity.authenticate(token);
  if(!user)return json({error:'Vui lòng đăng nhập.'},401);
  const feed=await basicFeed({request,client,user,json});if(feed)return feed;
  const videos=await basicVideos({request,client,user,json});if(videos)return videos;
  const directory=await basicDirectory({request,client,user,json});if(directory)return directory;
  if((env.CHAT_POSTGRES_OPTIONS||env.CHAT_HYPERDRIVE)&&(/\/messages(?:\/|$)/.test(path)||['/api/groups','/api/conversations','/api/notifications'].includes(path)||path.startsWith('/api/groups/'))){
   stage='chat-postgres-connect';chatClient=new pg.Client(env.CHAT_POSTGRES_OPTIONS||{connectionString:env.CHAT_HYPERDRIVE.connectionString,connectionTimeoutMillis:10000,query_timeout:10000});
   await chatClient.connect();env={...env,CHAT_DB:createPostgresChatAdapter(chatClient)};
  }
  const commerce=await commerceRoute({request,client,user,json});if(commerce)return commerce;
  const nativeChat=await nativeChatRoute({request,env,client,user,json});if(nativeChat)return nativeChat;
  const notifications=await notificationRoute({request,env,client,user,json});if(notifications)return notifications;
  if(path==='/api/cloud/events'){
   if(request.method!=='GET'||request.headers.get('Upgrade')?.toLowerCase()!=='websocket')return json({error:'WebSocket required'},426);
   const hash=createHash('sha256').update(token).digest('hex');
   const result=await client.query('SELECT expires FROM kinnect_core.sessions WHERE token_hash=$1',[hash]);
   const forwarded=new Headers(request.headers);forwarded.set('X-User-Id',user.id);forwarded.set('X-Session-Hash',hash);forwarded.set('X-Session-Expires',String(result.rows[0].expires));
   return await env.USER_EVENTS.get(env.USER_EVENTS.idFromName(user.id)).fetch(new Request(request,{headers:forwarded}));
  }
  const chat=await cloudChatRoute({request,env,client,user,json});if(chat)return chat;
  if(path==='/api/me'&&request.method==='GET'){const full=(await client.query('SELECT * FROM kinnect_core.users WHERE id=$1',[user.id])).rows[0];const blocked=(await client.query('SELECT target FROM kinnect_core.blocks WHERE actor=$1',[user.id])).rows.map(r=>r.target);return json({user:{...profile(full,true),blockedUserIds:blocked}});}
  if(path==='/api/wallet'&&request.method==='GET')return json(await createPostgresWallet({client}).state(user.id));
  if(path==='/api/logout'&&request.method==='POST'){
   const tokenHash=createHash('sha256').update(token).digest('hex');await client.query('DELETE FROM kinnect_core.sessions WHERE token_hash=$1',[tokenHash]);
   await env.USER_EVENTS.get(env.USER_EVENTS.idFromName(user.id)).fetch('https://events/revoke',{method:'POST',body:JSON.stringify({tokenHash})});
   return json({ok:true},200,{'Set-Cookie':'kinnect_session=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0'});
  }
  return json({error:'Method not allowed'},405);
 }catch(error){const message=String(error.message||'').toLowerCase();return json({error:'Máy chủ tạm thời chưa phản hồi. Vui lòng thử lại.',diagnostic:{stage,code:/^[A-Z0-9_]{2,60}$/.test(error.code||'')?error.code:'INTERNAL',category:message.includes('not implemented')?'not-implemented':message.includes('cert')?'certificate':message.includes('timeout')?'timeout':message.includes('terminated')?'terminated':message.includes('password')?'password':message.includes('tls')?'tls':message.includes('ca')?'ca':message.includes('ssl')?'ssl':'other',name:error.name}},503);}
 finally{if(chatClient)await chatClient.end().catch(()=>{});await client.end().catch(()=>{});}
}};
