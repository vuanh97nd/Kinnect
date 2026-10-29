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


import {createKinnectAI} from '../lib/kinnect-ai.js';
test('AI replies are durable, labelled, per conversation, and pause for human handoff',async t=>{
 const app=await start(),a=await register(app,'ai_admin'),b=await register(app,'ai_member');app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(a.id);let sent=0;
 const ai=createKinnectAI({db:app.social.db,user:id=>app.social.db.prepare('SELECT * FROM users WHERE id=?').get(id),blocked:()=>false,notice:()=>{},messageState:{reveal(){}},env:{KINNECT_AI_URL:'https://example.com',KINNECT_API_TOKEN:'secret'},send:async()=>{sent++;return Response.json({answer:'[Trợ lý AI của Quản trị Kinnect] Xin chào',automated:true,provider:'cloudflare'});}});t.after(async()=>{ai.close();await app.stop();});ai.configure({adminId:a.id,support:true,moderation:true});
 const id='message-one';app.social.db.prepare('INSERT INTO messages VALUES(?,?,?,?,?)').run(id,b.id,a.id,'Xin chào',1);ai.support({id,sender:b.id,recipient:a.id,body:'Xin chào'});ai.support({id,sender:b.id,recipient:a.id,body:'Xin chào'});await ai.drain();assert.equal(sent,1);assert.equal(app.social.db.prepare('SELECT COUNT(*) n FROM messages WHERE sender=?').get(a.id).n,1);
 ai.pause(b.id,true);ai.enqueue('support','message-two',b.id,{text:'hello'});await ai.drain();assert.equal(sent,1);assert.equal(ai.jobs()[0].state,'skipped');
 ai.pause(b.id,false);app.social.db.prepare('INSERT INTO messages VALUES(?,?,?,?,?)').run('message-human',b.id,a.id,'Tôi muốn gặp quản trị viên',Date.now()+100);ai.support({id:'message-human',sender:b.id,recipient:a.id,body:'Tôi muốn gặp quản trị viên'});await ai.drain();assert.equal(sent,1);assert.equal(app.social.db.prepare('SELECT paused FROM ai_conversations WHERE user_id=?').get(b.id).paused,1);
});
test('AI moderation creates a report without punishing users and ignores unconfigured processing',async t=>{
 const app=await start(),a=await register(app,'ai_modadmin'),b=await register(app,'ai_author');app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(a.id);let alerts=0;
 const ai=createKinnectAI({db:app.social.db,user:id=>app.social.db.prepare('SELECT * FROM users WHERE id=?').get(id),blocked:()=>false,notice:()=>{alerts++;},messageState:{reveal(){}},env:{KINNECT_AI_URL:'https://example.com',KINNECT_API_TOKEN:'secret'},send:async()=>Response.json({decision:'review',reason:'Nghi spam',evidence:'Sample'})});t.after(async()=>{ai.close();await app.stop();});ai.configure({adminId:a.id,moderation:true});ai.enqueue('post','post-one',b.id,{text:'sample'});await ai.drain();assert.equal(alerts,1);assert.equal(app.social.db.prepare('SELECT suspended FROM users WHERE id=?').get(b.id).suspended,0);assert.equal(app.social.db.prepare('SELECT COUNT(*) n FROM reports').get().n,1);assert.equal(ai.jobs()[0].state,'done');assert.equal(app.social.db.prepare('SELECT payload FROM ai_jobs').get().payload,'{}');
 assert.equal((await as(app,b,'/admin/ai')).status,403);
});
test('server automatically switches from Cloudflare to configured NVIDIA and hides both keys',async t=>{
 const app=await start(),a=await register(app,'ai_fallback_admin'),b=await register(app,'ai_fallback_member');app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(a.id);let primaryCalls=0,backupCalls=0;
 const ai=createKinnectAI({db:app.social.db,user:id=>app.social.db.prepare('SELECT * FROM users WHERE id=?').get(id),blocked:()=>false,notice:()=>{},messageState:{reveal(){}},env:{KINNECT_AI_URL:'https://example.com',KINNECT_API_TOKEN:'worker-secret',KINNECT_NVIDIA_ENABLED:'1',KINNECT_NVIDIA_API_KEY:'nvidia-secret',KINNECT_NVIDIA_MODEL:'test/model'},send:async(url,options)=>{if(String(url).startsWith('https://example.com')){primaryCalls++;return Response.json({error:'busy'},{status:503});}backupCalls++;assert.equal(String(url),'https://integrate.api.nvidia.com/v1/chat/completions');assert.equal(options.headers.Authorization,'Bearer nvidia-secret');return Response.json({choices:[{message:{content:'Tôi có thể giúp bạn sử dụng Kinnect.'}}]});}});t.after(async()=>{ai.close();await app.stop();});ai.configure({adminId:a.id,support:true});app.social.db.prepare('INSERT INTO messages VALUES(?,?,?,?,?)').run('fallback-message',b.id,a.id,'Xin chào',Date.now());ai.support({id:'fallback-message',sender:b.id,recipient:a.id,body:'Xin chào'});await ai.drain();assert.equal(primaryCalls,1);assert.equal(backupCalls,1);assert.equal(JSON.parse(ai.jobs()[0].result).provider,'nvidia');const status=JSON.stringify(ai.credentialStatus());assert.ok(!status.includes('worker-secret'));assert.ok(!status.includes('nvidia-secret'));const test=await ai.testConnection('fallback');assert.equal(test.fallbackSimulation,true);assert.equal(test.provider,'nvidia');assert.equal(primaryCalls,1);
 assert.equal((await as(app,b,'/admin/ai/credentials','PATCH',{token:'something'})).status,403);
});
test('welcome is automatic, sent once from admin, independent of AI settings, and never sent to existing older accounts',async t=>{
 const app=await start(),a=await register(app,'welcome_admin');app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(a.id);t.after(()=>app.stop());const b=await register(app,'welcome_new');const rows=app.social.db.prepare('SELECT * FROM messages WHERE recipient=?').all(b.id);assert.equal(rows.length,1);assert.equal(rows[0].sender,a.id);assert.match(rows[0].body,/Chào mừng bạn đến với Kinnect/);assert.match(rows[0].body,/livestream/);await as(app,b,'/me');await as(app,b,'/me');assert.equal(app.social.db.prepare('SELECT COUNT(*) n FROM messages WHERE recipient=?').get(b.id).n,1);assert.equal(app.social.ai.status().support,0);
 const c=await register(app,'welcome_old');app.social.db.prepare('DELETE FROM ai_welcome WHERE user_id=?').run(c.id);app.social.db.prepare('DELETE FROM messages WHERE recipient=?').run(c.id);app.social.db.prepare('UPDATE users SET created=? WHERE id=?').run(Date.now()-8*86400000,c.id);await as(app,c,'/me');assert.equal(app.social.db.prepare('SELECT COUNT(*) n FROM messages WHERE recipient=?').get(c.id).n,0);
});
for(const scenario of ['healthy','quota','empty','unlabelled','timeout','disabled','unconfigured'])test('primary-first AI routing: '+scenario,async t=>{
 const app=await start(),admin=await register(app,'route_admin_'+scenario),member=await register(app,'route_member_'+scenario);app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(admin.id);let primary=0,backup=0;
 const env={KINNECT_AI_URL:'https://primary.example',KINNECT_API_TOKEN:'primary-secret',KINNECT_NVIDIA_ENABLED:scenario==='disabled'?'0':'1',...(scenario==='unconfigured'?{}:{KINNECT_NVIDIA_API_KEY:'backup-secret',KINNECT_NVIDIA_MODEL:'test/model'})};
 const ai=createKinnectAI({db:app.social.db,user:id=>app.social.db.prepare('SELECT * FROM users WHERE id=?').get(id),blocked:()=>false,notice:()=>{},messageState:{reveal(){}},env,send:async(url,options)=>{if(String(url).startsWith('https://primary.example')){primary++;assert.ok(options.signal);if(scenario==='healthy')return Response.json({answer:'Trả lời từ AI chính',automated:true});if(scenario==='empty')return Response.json({answer:'   ',automated:true});if(scenario==='unlabelled')return Response.json({answer:'Chưa có nhãn AI'});if(scenario==='timeout')throw new DOMException('Timed out','TimeoutError');return Response.json({error:'quota'},{status:429});}backup++;return Response.json({choices:[{message:{content:'Trả lời từ AI dự phòng'}}]});}});
 t.after(async()=>{ai.close();await app.stop();});ai.configure({adminId:admin.id,support:true});const id='route-'+scenario;app.social.db.prepare('INSERT INTO messages VALUES(?,?,?,?,?)').run(id,member.id,admin.id,'Hướng dẫn dùng Kinnect',Date.now());ai.support({id,sender:member.id,recipient:admin.id,body:'Hướng dẫn dùng Kinnect'});await ai.drain();assert.equal(primary,1);
 if(scenario==='healthy'){assert.equal(backup,0);assert.equal(JSON.parse(ai.jobs()[0].result).provider,'cloudflare');}else if(['disabled','unconfigured'].includes(scenario)){assert.equal(backup,0);assert.equal(ai.jobs()[0].state,'queued');}else{assert.equal(backup,1);assert.equal(JSON.parse(ai.jobs()[0].result).provider,'nvidia');}
});
