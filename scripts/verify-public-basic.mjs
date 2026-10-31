import assert from'node:assert/strict';import{readFileSync,writeFileSync}from'node:fs';import{randomUUID,randomBytes,scryptSync}from'node:crypto';
import pg from'../cloud-api/node_modules/pg/lib/index.js';import{postgresOptions}from'../lib/cloud-postgres.js';
import{createApp}from'../server.js';
const parse=file=>Object.fromEntries(readFileSync(file,'utf8').split(/\r?\n/).filter(x=>x&&!x.startsWith('#')).map(x=>{const i=x.indexOf('=');return[x.slice(0,i),x.slice(i+1)];}));
const core=new pg.Client(postgresOptions(parse('cloud-db.env'))),chat=new pg.Client(postgresOptions(parse('chat-db.env'))),ids=[randomUUID(),randomUUID(),randomUUID()],password=randomBytes(24).toString('hex'),salt=randomBytes(16).toString('hex');
const base='https://kinnect-allocation.vuanh97nd.workers.dev';let stage='setup',pc;
const call=async(path,cookie,body,method=body?'POST':'GET')=>{const response=await fetch(base+path,{method,headers:{'Content-Type':'application/json',Origin:base,...cookie?{Cookie:cookie}:{}},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(30000)});return{status:response.status,cookie:response.headers.get('Set-Cookie')?.split(';')[0],data:await response.json()};};
try{
 try{await fetch('http://127.0.0.1:3000/health',{signal:AbortSignal.timeout(500)});throw Error('PC must be off for this verification');}catch(e){if(e.message==='PC must be off for this verification')throw e;}
 await core.connect();await chat.connect();for(const id of ids)await core.query("INSERT INTO kinnect_core.users VALUES($1,$1,$2,$3,'Kiểm tra dự phòng','user',0,$4,$5::jsonb)",[id,scryptSync(password,salt,64).toString('hex'),salt,Date.now(),JSON.stringify({dm_mode:'everyone',discoverable:0})]);
 stage='public-auth';assert.equal((await call('/api/me')).status,401);
 const a=await call('/api/login',null,{username:ids[0],password}),b=await call('/api/login',null,{username:ids[1],password}),outsider=await call('/api/login',null,{username:ids[2],password});assert.equal(a.status,200);assert.equal(b.status,200);assert.equal(outsider.status,200);assert.equal((await call('/api/me',a.cookie)).data.user.id,ids[0]);
 stage='direct-send';const nonce=randomUUID(),body={body:'Kiểm tra chat khi PC tắt',requestId:nonce};const first=await call('/api/users/'+ids[1]+'/messages',a.cookie,body);assert.equal(first.status,201);
 const repeat=await call('/api/users/'+ids[1]+'/messages',a.cookie,body);assert.equal(repeat.status,201);assert.equal(repeat.data.message.id,first.data.message.id);
 stage='direct-read';const received=await call('/api/users/'+ids[0]+'/messages',b.cookie);assert.equal(received.status,200);assert.equal(received.data.messages.length,1);assert.equal(received.data.messages[0].body,body.body);
 const seen=await call('/api/users/'+ids[1]+'/messages',a.cookie);assert.ok(seen.data.messages[0].receipt.seenAt);
 stage='group';const group=await call('/api/groups',a.cookie,{name:'Kiểm tra dự phòng',members:[ids[1]]});assert.equal(group.status,201);const gid=group.data.group.id;
 const sent=await call('/api/groups/'+gid+'/messages',a.cookie,{body:'Tin nhóm khi PC tắt',requestId:randomUUID()});assert.equal(sent.status,201);
 assert.equal((await call('/api/groups/'+gid+'/messages',b.cookie)).data.messages.length,1);assert.equal((await call('/api/groups/'+gid+'/messages',outsider.cookie)).status,404);
 stage='native-lists';assert.equal((await call('/api/conversations',b.cookie)).status,200);assert.equal((await call('/api/groups',b.cookie)).status,200);assert.equal((await call('/api/notifications',b.cookie)).status,200);
 stage='offline-ui';const feed=await call('/api/posts',a.cookie);assert.equal(feed.status,200);assert.equal(feed.data.offline,true);assert.ok(feed.data.posts.length>0);assert.equal((await call('/api/friends',a.cookie)).status,200);assert.ok((await call('/api/shorts',a.cookie)).data.shorts.length>0);
 stage='pc-shared-history';pc=createApp({dbPath:'work/pc-core-probe-'+randomUUID()+'.sqlite',liveEnv:{}});await new Promise(resolve=>pc.server.listen(0,'127.0.0.1',resolve));const pcBase='http://127.0.0.1:'+pc.server.address().port;
 const local=async(path,body)=>{const r=await fetch(pcBase+path,{method:body?'POST':'GET',headers:{Cookie:a.cookie,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});return{status:r.status,data:await r.json()};};
 assert.equal((await local('/api/me?legacy=1')).data.user.id,ids[0]);assert.equal((await local('/api/posts')).status,200);
 const fromPc=await local('/api/users/'+ids[1]+'/messages',{body:'PC dùng chung lịch sử',requestId:randomUUID()});assert.equal(fromPc.status,201);const onCloud=await call('/api/users/'+ids[0]+'/messages',b.cookie);assert.ok(onCloud.data.messages.some(m=>m.id===fromPc.data.message.id));
 assert.equal((await local('/api/users/'+ids[1]+'/messages')).data.messages.length,2);
 stage='revoke';assert.equal((await call('/api/logout',a.cookie,{})).status,200);assert.equal((await call('/api/me',a.cookie)).status,401);
 assert.equal((await local('/api/posts')).status,401);
 const report={at:new Date().toISOString(),pcOff:true,publicWithoutPreviewKey:true,passed:['login','same-session','direct-send-read','seen-receipt','idempotent-send','group-send-read','outsider-denied','conversations','notifications','offline-feed-content','offline-video-list','cloud-friends','pc-cloud-same-history','pc-session-bridge','logout-revocation']};writeFileSync('data/reports/public-basic-verification.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}catch(e){console.error(JSON.stringify({stage,error:e.code||e.name,actual:e.actual,expected:e.expected}));process.exitCode=1;}finally{
 if(pc){pc.server.closeAllConnections();await new Promise(resolve=>pc.server.close(resolve));pc.wss.close();pc.social.close();}
 try{const owned=(await chat.query('SELECT id FROM kinnect_chat.chat_conversations WHERE created_by=ANY($1::text[])',[ids])).rows.map(r=>r.id);for(const t of ['chat_receipts','chat_hidden_messages','chat_reactions','chat_pins','chat_attachment_refs'])await chat.query('DELETE FROM kinnect_chat.'+t+' WHERE message_id IN(SELECT id FROM kinnect_chat.chat_messages WHERE conversation_id=ANY($1::text[]))',[owned]);for(const t of ['chat_preferences','chat_messages','chat_members'])await chat.query('DELETE FROM kinnect_chat.'+t+' WHERE conversation_id=ANY($1::text[])',[owned]);await chat.query('DELETE FROM kinnect_chat.chat_conversations WHERE id=ANY($1::text[])',[owned]);await core.query('DELETE FROM kinnect_core.notifications WHERE user_id=ANY($1::text[]) OR actor=ANY($1::text[])',[ids]);await core.query('DELETE FROM kinnect_core.users WHERE id=ANY($1::text[])',[ids]);}catch{console.error('Fixture cleanup needs review');process.exitCode=1;}
 await core.end().catch(()=>{});await chat.end().catch(()=>{});
}
