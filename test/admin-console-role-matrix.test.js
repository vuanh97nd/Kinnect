import http from 'node:http';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server.js';

const HOSTS = {admin:'admin.kinnect.io.vn',support:'hotro.kinnect.io.vn',operations:'kythuat.kinnect.io.vn',finance:'taichinh.kinnect.io.vn'};
const ROOT_PASSWORD = 'matrix-root-test-only-2026!';
const STAFF_PASSWORD = 'matrix-staff-test-only-2026!';
async function setup(t) {
 const app=createApp({authLimit:100});
 await new Promise(resolve=>app.server.listen(0,'127.0.0.1',resolve));
 const base='http://127.0.0.1:'+app.server.address().port;
 t.after(async()=>{for(const socket of app.wss.clients)socket.terminate();app.wss.close();app.server.closeAllConnections();await new Promise(resolve=>app.server.close(resolve));app.social.close();});
 async function call(path,{portal='admin',method='GET',data,cookie}={}) {
  const host=HOSTS[portal],payload=data===undefined?null:JSON.stringify(data);
  return new Promise((resolve,reject)=>{
   const req=http.request(base+'/api/console/'+path,{method,headers:{Host:host,...(cookie?{Cookie:cookie}:{}),...(payload===null?{}:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(payload)}),...(method==='POST'?{Origin:'https://'+host}:{})}},res=>{
    const chunks=[];res.on('data',chunk=>chunks.push(chunk));res.on('end',()=>{const text=Buffer.concat(chunks).toString();resolve({status:res.statusCode,body:JSON.parse(text),cookie:res.headers['set-cookie']?.[0]?.split(';')[0],headers:res.headers});});
   });req.on('error',reject);req.end(payload);
  });
 }
 async function register(username){const response=await fetch(base+'/api/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({username,password:ROOT_PASSWORD,name:username,agree18:true,acceptPrivacyNotice:true,acceptTerms:true})});assert.equal(response.status,200);return(await response.json()).user;}
 const admin=await register('matrix_owner'),member=await register('matrix_member');
 app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(admin.id);
 async function login(portal,username,password=STAFF_PASSWORD){return call('login',{portal,method:'POST',data:{username,password}});}
 let rootCookie=(await login('admin',admin.username,ROOT_PASSWORD)).cookie;assert(rootCookie);
 const staff={};
 for(const team of ['support','operations','finance']){
  const username='matrix_'+team;
  const made=await call('team',{method:'POST',cookie:rootCookie,data:{action:'create',username,name:'Nhân sự '+team,team}});assert.equal(made.status,200);
  const first=await login(team,username,made.body.temporaryPassword);assert.equal(first.status,200);assert.equal(first.body.user.mustChange,true);
  const changed=await call('password',{portal:team,method:'POST',cookie:first.cookie,data:{current:made.body.temporaryPassword,password:STAFF_PASSWORD}});assert.equal(changed.status,200);
  const next=await login(team,username);assert.equal(next.status,200);assert.equal(next.body.user.mustChange,false);assert.equal(next.body.user.team,team);assert.equal(next.body.user.role,'support');
  staff[team]={username,id:next.body.user.id,cookie:next.cookie};
 }
 return {...app,call,login,admin,member,rootCookie,staff};
}

test('each team is limited to its server-enforced API capability matrix',async t=>{
 const a=await setup(t);
 const permitted={
  support:['overview','users','reports','content','resets','tickets','activity'],
  operations:['overview','operations','tickets','activity'],
  finance:['overview','finance','tickets','activity'],
 };
 const denied={
  support:['operations','finance','team'],
  operations:['users','reports','content','resets','finance','team'],
  finance:['users','reports','content','resets','operations','team'],
 };
 for(const team of Object.keys(permitted)){
  const options={portal:team,cookie:a.staff[team].cookie};
  for(const endpoint of permitted[team])assert.equal((await a.call(endpoint,options)).status,200,team+' allowed '+endpoint);
  for(const endpoint of denied[team])assert.equal((await a.call(endpoint,options)).status,403,team+' denied '+endpoint);
 }
 for(const team of ['operations','finance']){
  const result=await a.call('moderate',{portal:team,cookie:a.staff[team].cookie,method:'POST',data:{action:'suspend-user',target:a.member.id}});
  assert.equal(result.status,403,team+' cannot moderate');
 }
 assert.equal(a.social.user(a.member.id).suspended,0);
 const ops=await a.call('operations',{portal:'operations',cookie:a.staff.operations.cookie});assert.equal(typeof ops.body.uptime,'number');assert.equal(typeof ops.body.ai.ready,'boolean');assert.equal(ops.body.ai.token,undefined);
 for(const endpoint of ['users','reports','content','resets','finance','operations','team','tickets'])assert.equal((await a.call(endpoint,{cookie:a.rootCookie})).status,200,'root allowed '+endpoint);
});

test('staff credentials and cookies cannot be replayed into another team or root portal',async t=>{
 const a=await setup(t);
 for(const team of ['support','operations','finance']){
  for(const portal of Object.keys(HOSTS)){
   if(portal===team)continue;
   const wrong=await a.login(portal,a.staff[team].username);
   assert.equal(wrong.status,401,team+' credentials denied at '+portal);
  }
 }
 for(const portal of ['support','operations','finance'])assert.equal((await a.login(portal,a.admin.username,ROOT_PASSWORD)).status,401,'root credentials not accepted at '+portal);
 for(const [team,portal] of [['support','admin'],['operations','support'],['finance','operations']]){
  const login=await a.login(team,a.staff[team].username);assert.equal(login.status,200);
  assert.equal((await a.call('overview',{portal,cookie:login.cookie})).status,401,team+' cookie denied at '+portal);
 }
 const valid=await a.login('operations',a.staff.operations.username);assert.equal(valid.status,200);
 const me=await a.call('me',{portal:'operations',cookie:valid.cookie});assert.equal(me.body.user.team,'operations');assert.equal(me.body.user.key,undefined);
 assert.match(valid.headers['set-cookie'][0],/HttpOnly/);assert.match(valid.headers['set-cookie'][0],/SameSite=Strict/);assert.doesNotMatch(valid.headers['set-cookie'][0],/Domain=/i);
});

test('staff cannot manage root or other personnel and admin reassignment immediately revokes old access',async t=>{
 const a=await setup(t);
 for(const team of ['support','operations','finance']){
  const denied=await a.call('team',{portal:team,cookie:a.staff[team].cookie,method:'POST',data:{action:'move',id:a.staff.support.id,team:'finance'}});assert.equal(denied.status,403);
 }
 const blocked=await a.call('moderate',{portal:'support',cookie:a.staff.support.cookie,method:'POST',data:{action:'suspend-user',target:a.admin.id}});assert.equal(blocked.status,403);assert.equal(a.social.user(a.admin.id).suspended,0);
 // A malicious recovery request for root must not bypass the member-only reset gate.
 a.social.db.prepare("INSERT INTO password_resets(id,username,user_id,contact,note,status,created) VALUES(?,?,?,?,?,'open',?)").run('root-reset-fixture',a.admin.username,a.admin.id,'test-only','Do not reset root',Date.now());
 assert.equal((await a.call('resets',{portal:'support',cookie:a.staff.support.cookie,method:'POST',data:{action:'reset',id:'root-reset-fixture'}})).status,403);
 const moved=await a.call('team',{method:'POST',cookie:a.rootCookie,data:{action:'move',id:a.staff.support.id,team:'finance'}});assert.equal(moved.status,200);
 assert.equal((await a.call('overview',{portal:'support',cookie:a.staff.support.cookie})).status,401);
 assert.equal((await a.login('support',a.staff.support.username)).status,401);
 const next=await a.login('finance',a.staff.support.username);assert.equal(next.status,200);assert.equal(next.body.user.team,'finance');
 assert.equal((await a.call('finance',{portal:'finance',cookie:next.cookie})).status,200);
 assert.equal((await a.call('users',{portal:'finance',cookie:next.cookie})).status,403);
 assert.equal((await a.call('team',{cookie:a.rootCookie})).body.staff.find(x=>x.id===a.staff.support.id).team,'finance');
 assert.equal((await a.call('me',{cookie:a.rootCookie})).body.user.role,'admin');
});

test('ops monitor metrics, actions, confirmToken and adminOnly RBAC are enforced server-side',async t=>{
 const a=await setup(t);
 for(const team of ['support','finance']){
  assert.equal((await a.call('ops/metrics',{portal:team,cookie:a.staff[team].cookie})).status,403);
  assert.equal((await a.call('ops/audit',{portal:team,cookie:a.staff[team].cookie})).status,403);
  assert.equal((await a.call('ops/action',{portal:team,cookie:a.staff[team].cookie,method:'POST',data:{serverId:'app-1',action:'drain',confirmToken:'app-1:0'}})).status,403);
 }
 const metrics=await a.call('ops/metrics',{portal:'operations',cookie:a.staff.operations.cookie});
 assert.equal(metrics.status,200);
 assert.equal(metrics.body.servers.length,6);
 const appSrv=metrics.body.servers.find(s=>s.id==='app-1');
 const turnSrv=metrics.body.servers.find(s=>s.id==='turn-1');
 assert.ok(appSrv.actionToken);
 // Stale token rejected with 409
 assert.equal((await a.call('ops/action',{portal:'operations',cookie:a.staff.operations.cookie,method:'POST',data:{serverId:'app-1',action:'drain',confirmToken:'app-1:100'}})).status,409);
 // Operations allowed safe action with fresh token
 const drained=await a.call('ops/action',{portal:'operations',cookie:a.staff.operations.cookie,method:'POST',data:{serverId:'app-1',action:'drain',confirmToken:appSrv.actionToken}});
 assert.equal(drained.status,200);
 assert.equal(drained.body.state.acceptingNew,false);
 // Operations denied adminOnly actions (failover, switch-replica, toggle-maintenance)
 assert.equal((await a.call('ops/action',{portal:'operations',cookie:a.staff.operations.cookie,method:'POST',data:{serverId:'turn-1',action:'failover',confirmToken:turnSrv.actionToken}})).status,403);
 // Root admin allowed adminOnly action
 const failover=await a.call('ops/action',{portal:'admin',cookie:a.rootCookie,method:'POST',data:{serverId:'turn-1',action:'failover',confirmToken:turnSrv.actionToken}});
 assert.equal(failover.status,200);
 assert.equal(failover.body.state.onStandby,true);
 const audit=await a.call('ops/audit',{portal:'admin',cookie:a.rootCookie});
 assert.equal(audit.status,200);
 assert.ok(audit.body.entries.length>=3);
});
