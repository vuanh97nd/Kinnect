import {test} from 'node:test';import assert from 'node:assert/strict';import {Readable} from 'node:stream';
import {openSocial} from '../lib/social.js';import {createAdminConsole} from '../lib/admin-console.js';import {createAdminCloudBridge} from '../lib/admin-cloud-bridge.js';
const secret='isolated-cloud-console-bridge-test-key-2026';
test('cloud outbox replays once before replicas, protects ownership and skips unchanged table writes',async t=>{
 const social=openSocial(':memory:');const route=createAdminConsole(social);t.after(()=>{route.close();social.close();});
 social.db.prepare("INSERT INTO users(id,username,name,password,salt,created,role,birth_date) VALUES('member','member','Fixture','','',1,'user','')").run();
 const event={id:'event-1',action:'reputation-deduct',target:'member',payload:{points:5,reason:'Isolated synchronization test',actor:'QA'}};
 const requests=[];let expose=true;
 const bridge=createAdminCloudBridge(social,{connection:{origin:'https://cloud.example',secret},automatic:false,fetchImpl:async(url,init)=>{
  const path=new URL(url).pathname.split('/').at(-1),body=init.body?JSON.parse(init.body):null;requests.push({path,body});
  if(path==='status')return Response.json({ready:true});if(path==='actions'){const actions=expose?[event]:[];expose=false;return Response.json({actions});}return Response.json({ok:true});
 }});t.after(()=>bridge.close());
 await bridge.sync();assert.equal(social.db.prepare("SELECT reputation_score FROM users WHERE id='member'").get().reputation_score,95);assert(bridge.status().lastSuccess);
 assert(requests.findIndex(r=>r.path==='ack')<requests.findIndex(r=>r.path==='replica'));
 for(const request of requests.filter(r=>r.path==='replica'))for(const table of request.body.tables)assert(!table.name.startsWith('console_'));
 const first=requests.length;expose=true;await bridge.sync();assert.equal(social.db.prepare("SELECT reputation_score FROM users WHERE id='member'").get().reputation_score,95);assert.equal(social.db.prepare('SELECT count(*) n FROM reputation_logs').get().n,1);
 const later=requests.slice(first);assert.equal(later.filter(r=>r.path==='replica'&&r.body.tables.length).length,0);assert.equal(later.filter(r=>r.path==='prune').length,0);
});
test('internal PC controls require the secret, an allowed actor and a fixed operation endpoint',async t=>{
 const social=openSocial(':memory:');t.after(()=>social.close());let dispatched=0;let bridge;
 bridge=createAdminCloudBridge(social,{connection:{origin:'https://cloud.example',secret},automatic:false,dispatch:async(req,res)=>{dispatched++;assert.equal(req.url,'/api/console/operations/action');assert.equal(bridge.trustedPrincipal(req).team,'operations');res.writeHead(200);res.end('{}');return true;}});t.after(()=>bridge.close());
 const call=async(token,actor,action='check-integrity')=>{const req=Readable.from([Buffer.from(JSON.stringify({actor,action}))]);req.url='/internal/admin/action';req.method='POST';req.headers={authorization:'Bearer '+token};req.socket={};const res={writeHead(s){this.status=s;},end(){}};await bridge.handle(req,res);return res.status;};
 const tech={id:'qa',username:'qa_tech',role:'support',team:'operations'};
 assert.equal(await call('wrong',tech),401);assert.equal(await call(secret,{...tech,team:'finance'}),403);assert.equal(await call(secret,tech,'arbitrary-shell'),403);assert.equal(await call(secret,tech),200);assert.equal(dispatched,1);
 assert.equal(bridge.trustedPrincipal({headers:{'x-console-internal':'1',authorization:'Bearer '+secret}}),undefined);
});
