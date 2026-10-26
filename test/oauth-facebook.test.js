import test from 'node:test';import assert from 'node:assert/strict';import {once} from 'node:events';import {createApp} from '../server.js';
test('Facebook OAuth rejects mismatched state, keeps tokens out of URLs and creates a usable session',async t=>{
 const saved={...process.env};Object.assign(process.env,{GOOGLE_CLIENT_ID:'',GOOGLE_CLIENT_SECRET:'',FACEBOOK_APP_ID:'facebook-test',FACEBOOK_APP_SECRET:'facebook-secret',PUBLIC_URL:'https://app.example'});
 t.after(()=>{for(const key of Object.keys(process.env))if(!(key in saved))delete process.env[key];Object.assign(process.env,saved);});
 let providerRequests=0;
 const app=createApp({authLimit:500,fetchImpl:async(url,options)=>{providerRequests++;assert.ok(options.signal instanceof AbortSignal);const target=new URL(url);assert.equal(target.searchParams.has('access_token'),false);
  if(target.pathname.endsWith('/oauth/access_token')){assert.equal(new URLSearchParams(options.body).get('redirect_uri'),'https://app.example/api/oauth/facebook/callback');return Response.json({access_token:'facebook-access-token'});}
  assert.equal(options.headers.Authorization,'Bearer facebook-access-token');return Response.json({id:'facebook-subject',name:'Bạn Facebook',email:'member@example.com'});
 }});
 app.server.listen(0,'127.0.0.1');await once(app.server,'listening');t.after(async()=>{for(const ws of app.wss.clients)ws.terminate();await new Promise(r=>app.wss.close(r));await new Promise(r=>app.server.close(r));app.social.close();});
 const base='http://127.0.0.1:'+app.server.address().port;
 const start=await fetch(base+'/api/oauth/facebook/start',{redirect:'manual'});assert.equal(start.status,302);const authorization=new URL(start.headers.get('location')),cookie=start.headers.get('set-cookie').split(';')[0];assert.equal(authorization.searchParams.get('redirect_uri'),'https://app.example/api/oauth/facebook/callback');
 const wrong=await fetch(base+'/api/oauth/facebook/callback?code=ok&state=wrong',{headers:{Cookie:cookie}});assert.match(await wrong.text(),/oauth_error=state/);assert.equal(providerRequests,0);
 const callback=await fetch(base+'/api/oauth/facebook/callback?code=ok&state='+authorization.searchParams.get('state'),{headers:{Cookie:cookie}});const ticket=(await callback.text()).match(/ticket=([a-f0-9]+)/)[1];assert.equal(providerRequests,2);
 const complete=await fetch(base+'/api/oauth/complete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ticket,username:'facebook_member',agree18:true})});assert.equal(complete.status,200);const session=complete.headers.get('set-cookie').split(';')[0];const me=await (await fetch(base+'/api/me',{headers:{Cookie:session}})).json();assert.equal(me.user.username,'facebook_member');assert.ok(!JSON.stringify(me).includes('facebook-access-token'));
});
