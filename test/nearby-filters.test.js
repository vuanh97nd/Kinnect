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
      agree18: true, acceptPrivacyNotice: true,
      ...extra,
    },
  });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return { id: r.body.user.id, cookie: r.cookie, user: r.body.user };
}
const as = (app, u, path, method = "GET", body) =>
  request(app, path, { cookie: u.cookie, method, body });

test('nearby filters use public fields before result limits and preserve privacy',async t=>{
 const app=await start();t.after(()=>app.stop());const a=await register(app,'filter_owner'),b=await register(app,'filter_man'),c=await register(app,'filter_woman');
 for(const u of [a,b,c])assert.equal((await as(app,u,'/me/location','PATCH',{enabled:true,latitude:10.7734,longitude:106.6989})).status,200);
 assert.equal((await as(app,b,'/me','PATCH',{gender:'Nam',age:25,identityPublic:true,lookingFor:'Kết bạn'})).status,200);
 assert.equal((await as(app,c,'/me','PATCH',{gender:'Nữ',age:35,identityPublic:true,lookingFor:'Trò chuyện'})).status,200);
 const find=async q=>(await as(app,a,'/discover?nearby=1&radius=50&'+q)).body;
 const men=await find('gender='+encodeURIComponent('Nam'));assert.equal(men.filtersApplied,true);assert.deepEqual(men.users.map(u=>u.id),[b.id]);
 assert.deepEqual((await find('minAge=30&maxAge=40')).users.map(u=>u.id),[c.id]);
 assert.deepEqual((await find('intent='+encodeURIComponent('Kết bạn'))).users.map(u=>u.id),[b.id]);
 await as(app,b,'/me','PATCH',{identityPublic:false});assert.equal((await find('gender=Nam')).users.length,0);
 await as(app,c,'/me','PATCH',{profileVisibility:{age:false}});assert.equal((await find('minAge=30')).users.length,0);
 await as(app,c,'/me/location','PATCH',{enabled:false});assert.equal((await find('')).users.some(u=>u.id===c.id),false);
});


test('all discovery tabs apply filters while preserving following membership and hidden fields',async t=>{
 const app=await start();t.after(()=>app.stop());
 const owner=await register(app,'alltabs_owner'),man=await register(app,'alltabs_man'),woman=await register(app,'alltabs_woman');
 await as(app,man,'/me','PATCH',{gender:'Nam',age:25,identityPublic:true,lookingFor:'Kết bạn'});
 await as(app,woman,'/me','PATCH',{gender:'Nữ',age:35,identityPublic:true,lookingFor:'Trò chuyện'});
 await as(app,owner,'/users/'+woman.id+'/follow','POST',{});
 const find=async q=>(await as(app,owner,'/discover?sort=interests&'+q)).body;
 const men=await find('gender=Nam');assert.equal(men.filterVersion,2);assert.deepEqual(men.users.map(u=>u.id),[man.id]);
 assert.deepEqual((await find('following=1&gender='+encodeURIComponent('Nữ'))).users.map(u=>u.id),[woman.id]);
 assert.equal((await find('following=1&gender=Nam')).users.length,0);
 assert.deepEqual((await find('minAge=30&intent='+encodeURIComponent('Trò chuyện'))).users.map(u=>u.id),[woman.id]);
 await as(app,woman,'/me','PATCH',{identityPublic:false,profileVisibility:{age:false}});
 assert.equal((await find('following=1&gender='+encodeURIComponent('Nữ'))).users.length,0);
 assert.equal((await find('following=1&minAge=30')).users.length,0);
 assert.equal((await find('following=1')).users.length,1);
 await as(app,man,'/me','PATCH',{showActivity:false});await as(app,woman,'/me','PATCH',{showActivity:false});
 assert.equal((await as(app,owner,'/discover?sort=active')).body.users.length,0);
});

