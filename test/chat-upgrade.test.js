import { test } from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtemp, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { WebSocket } from "ws";
import { createApp } from "../server.js";
async function start(dbPath) {
  const app = createApp({ dbPath });
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  const url = `http://127.0.0.1:${app.server.address().port}`;
  return {
    ...app,
    url,
    async stop() {
      for (const ws of app.wss.clients) ws.terminate();
      await new Promise((r) => app.wss.close(r));
      await new Promise((r) => app.server.close(r));
      app.social.close();
    },
  };
}
async function request(
  app,
  path,
  { cookie, method = "GET", body, headers = {} } = {},
) {
  const r = await fetch(app.url + "/api" + path, {
    method,
    headers: {
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(cookie ? { Cookie: cookie } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return {
    status: r.status,
    body: await r.json(),
    cookie: r.headers.get("set-cookie")?.split(";")[0],
  };
}
async function register(app, username, extra = {}) {
  const r = await request(app, "/register", {
    method: "POST",
    body: {
      username,
      password: "very-strong-test-password",
      name: username,
      birthDate: "1994-05-10",
      agree18: true,
      ...extra,
    },
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return { id: r.body.user.id, cookie: r.cookie, user: r.body.user };
}
const as = (app, u, path, method = "GET", body) =>
  request(app, path, { cookie: u.cookie, method, body });

test('chat roles reject privilege escalation and mentions only reference real group members',async t=>{
 const app=await start();t.after(()=>app.stop());
 const a=await register(app,'roles_owner'),b=await register(app,'roles_deputy'),c=await register(app,'roles_member'),d=await register(app,'roles_outside');
 let created=await as(app,a,'/groups','POST',{name:'Nhóm thử',members:[b.id,c.id]});assert.equal(created.status,201);const id=created.body.group.id,base='/groups/'+id;
 assert.equal((await as(app,c,base+'/roles','PATCH',{userId:b.id,role:'deputy'})).status,403);
 let promoted=await as(app,a,base+'/roles','PATCH',{userId:b.id,role:'deputy'});assert.equal(promoted.status,200);assert.equal(promoted.body.group.members.find(u=>u.id===b.id).groupRole,'deputy');
 assert.equal((await as(app,b,base,'PATCH',{name:'Tên mới'})).status,200);
 assert.equal((await as(app,b,base+'/roles','PATCH',{userId:c.id,role:'owner'})).status,403);
 assert.equal((await as(app,b,base+'/members','DELETE',{userId:a.id})).status,403);
 let msg=await as(app,b,base+'/messages','POST',{body:'Chào @roles_member @roles_outside',mentions:[c.id,d.id]});assert.equal(msg.status,201);
 let messages=(await as(app,c,base+'/messages')).body.messages;assert.deepEqual(messages.at(-1).mentions.map(u=>u.id),[c.id]);
 assert.equal(messages.at(-1).author.groupRole,'deputy');
 assert.equal((await as(app,d,base+'/messages')).status,404);
 assert.equal((await as(app,b,base+'/messages','POST',{body:'invalid',mentions:'fake'})).status,400);
 assert.equal((await as(app,c,base+'/messages')).body.messages.length,1);
 assert.equal((await as(app,a,base+'/roles','PATCH',{userId:c.id,role:'deputy'})).status,200);
 assert.equal((await as(app,b,base+'/members','DELETE',{userId:c.id})).status,403);
 assert.equal((await as(app,a,base+'/roles','PATCH',{userId:b.id,role:'owner'})).status,200);
 assert.equal((await as(app,a,base+'/roles','PATCH',{userId:c.id,role:'member'})).status,403);
 assert.equal((await as(app,b,base+'/roles','PATCH',{userId:c.id,role:'member'})).status,200);
});

test('conversation unread, pin, mute, hide and local delete remain user-specific for both kinds',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'prefs_owner'),b=await register(app,'prefs_friend');
 await as(app,a,'/users/'+b.id+'/friend-request','POST',{});await as(app,b,'/users/'+a.id+'/friend-request/respond','POST',{action:'accept'});
 await as(app,a,'/users/'+b.id+'/messages','POST',{body:'hello'});
 const created=await as(app,a,'/groups','POST',{name:'Preferences',members:[b.id]});const group=created.body.group.id;
 for(const [kind,id] of [['direct',b.id],['group',group]]){
  const prefs='/chat-preferences/'+kind+'/'+id,messages=kind==='direct'?'/users/'+id+'/messages':'/groups/'+id+'/messages';
  assert.equal((await as(app,a,prefs,'POST',{unread:true,pinned:true,muted:true})).status,200);
  const state=(await as(app,a,prefs)).body;assert.equal(state.unread,true);assert.equal(state.pinned,true);assert.equal(state.muted,true);
  const rows=(await as(app,a,kind==='direct'?'/conversations':'/groups')).body[kind==='direct'?'users':'groups'];assert.equal(rows.find(u=>u.id===id).unread>=1,true);
  await as(app,a,messages);assert.equal((await as(app,a,prefs)).body.unread,false);
  await as(app,a,prefs,'POST',{hidden:true});const hidden=(await as(app,a,kind==='direct'?'/conversations':'/groups')).body[kind==='direct'?'users':'groups'];assert.equal(hidden.some(u=>u.id===id),false);
  await as(app,a,prefs,'POST',{hidden:false});assert.equal((await as(app,a,prefs)).body.hidden,false);
 }
 assert.equal((await as(app,b,'/chat-preferences/direct/'+a.id)).body.muted,false);
});


test('live ICE candidate bursts do not trigger the chat-action rate limiter',async t=>{
 const app=await start();t.after(()=>app.stop());const account=await register(app,'signal_burst');
 const ws=new WebSocket(app.url.replace('http:','ws:'),{headers:{Cookie:account.cookie,Origin:app.url}});t.after(()=>ws.terminate());
 const rows=[];ws.on('message',raw=>rows.push(JSON.parse(String(raw))));await once(ws,'open');
 const waitFor=async predicate=>{for(let i=0;i<100;i++){if(rows.some(predicate))return;await new Promise(r=>setTimeout(r,10));}throw new Error('timed out waiting for live event');};
 await waitFor(m=>m.type==='welcome');ws.send(JSON.stringify({type:'create',title:'Burst test'}));await waitFor(m=>m.type==='joined');
 for(let i=0;i<60;i++)ws.send(JSON.stringify({type:'signal',to:'no-peer',candidate:{candidate:'candidate-'+i}}));
 ws.send(JSON.stringify({type:'chat',text:'still connected'}));await waitFor(m=>m.type==='chat'&&m.text==='still connected');assert.equal(ws.readyState,WebSocket.OPEN);
});


test('mentions match complete usernames and avoid emails or longer names',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'edge_owner'),b=await register(app,'edge_member');
 const g=(await as(app,a,'/groups','POST',{name:'Mention edges',members:[b.id]})).body.group;
 for(const [body,count] of [['@edge_member_more',0],['email@edge_member',0],['@@edge_member',0],['@edge_member',1],['Hello @edge_member,',1],['(@edge_member)',1],['@edge_member_more and @edge_member ',1]]){
  assert.equal((await as(app,a,'/groups/'+g.id+'/messages','POST',{body,mentions:[b.id]})).status,201);
  const messages=(await as(app,b,'/groups/'+g.id+'/messages')).body.messages;assert.equal(messages.at(-1).mentions.length,count,body);
 }
});

test('group photo changes require manager rights and persist samples and validated images',async t=>{
 const app=await start();t.after(()=>app.stop());const owner=await register(app,'photo_owner'),member=await register(app,'photo_member'),outside=await register(app,'photo_outside');
 const group=(await as(app,owner,'/groups','POST',{name:'Photos',members:[member.id]})).body.group,path='/groups/'+group.id;
 assert.equal((await as(app,member,path+'/avatar','POST',{preset:'ocean'})).status,403);
 assert.equal((await as(app,outside,path+'/avatar','POST',{preset:'ocean'})).status,404);
 assert.equal((await as(app,owner,path+'/avatar','POST',{preset:'bogus'})).status,400);
 assert.equal((await as(app,owner,path+'/avatar','POST',{data:'data:image/png;base64,'+Buffer.alloc(20).toString('base64')})).status,400);
 const photo='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=';
 assert.equal((await as(app,owner,path+'/avatar','POST',{data:photo})).status,200);
 assert.equal((await as(app,member,path)).body.group.avatar,photo);
 await as(app,owner,path+'/roles','PATCH',{userId:member.id,role:'deputy'});
 assert.equal((await as(app,member,path+'/avatar','POST',{preset:'forest'})).status,200);
 const saved=(await as(app,owner,path)).body.group;assert.equal(saved.avatarPreset,'forest');assert.equal(saved.avatar,null);
});

test('community role and orientation filters only match publicly shared identity',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'identity_seeker'),b=await register(app,'identity_match');
 assert.equal((await as(app,b,'/me','PATCH',{orientation:'Gay / Đồng tính nam',communityRole:'Vers',identityPublic:true})).status,200);
 const path='/discover?orientation='+encodeURIComponent('Gay / Đồng tính nam')+'&communityRole=Vers';
 assert.ok((await as(app,a,path)).body.users.some(u=>u.id===b.id));
 assert.ok(!(await as(app,a,'/discover?communityRole=Top')).body.users.some(u=>u.id===b.id));
 await as(app,b,'/me','PATCH',{profileVisibility:{communityRole:false}});
 assert.ok(!(await as(app,a,path)).body.users.some(u=>u.id===b.id));
 assert.equal((await as(app,b,'/me')).body.user.communityRole,'Vers');
});

test('height and weight ranges exclude missing or private measurements and preserve profile values',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'measure_seeker'),b=await register(app,'measure_match'),c=await register(app,'measure_missing');
 assert.equal((await as(app,b,'/me','PATCH',{height:'175',weight:'68'})).status,200);
 const path='/discover?minHeight=170&maxHeight=180&minWeight=60&maxWeight=75';let found=(await as(app,a,path)).body.users;assert.ok(found.some(u=>u.id===b.id));assert.ok(!found.some(u=>u.id===c.id));
 assert.ok(!(await as(app,a,'/discover?minWeight=70')).body.users.some(u=>u.id===b.id));
 await as(app,b,'/me','PATCH',{profileVisibility:{weight:false}});assert.ok(!(await as(app,a,path)).body.users.some(u=>u.id===b.id));
 assert.equal((await as(app,b,'/me')).body.user.weight,68);
 assert.equal((await as(app,b,'/me','PATCH',{height:'wrong'})).status,400);
 assert.equal((await as(app,b,'/me','PATCH',{height:''})).status,200);
 assert.equal((await as(app,b,'/me')).body.user.height,null);
});
