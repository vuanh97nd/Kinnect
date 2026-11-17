import test from 'node:test';
import assert from 'node:assert/strict';
import {createCallConfig} from '../lib/call-config.js';
const entry={urls:['turn:relay.example:3478','turn:relay.example:53'],username:'temporary-user',credential:'temporary-password'};
const response=(data,status=200)=>({ok:status===200,status,json:async()=>data});
const relays=config=>config.iceServers.filter(s=>s.urls.some(u=>/^turns?:/i.test(u)));
const assertStunOnly=config=>{assert.ok(config.iceServers.length>0);for(const s of config.iceServers){assert.ok(s.urls.every(u=>/^stun:/i.test(u)));assert.equal(s.credential,undefined);}};
test('TURN credentials coalesce concurrent requests, expire and never return provider tokens',async()=>{
 let calls=0,time=0;const provider=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'private-token'},now:()=>time,fetchImpl:async(url,options)=>{calls++;assert.equal(options.headers.Authorization,'Bearer private-token');await new Promise(r=>setImmediate(r));return response({iceServers:[entry]});}});
 const [a,b]=await Promise.all([provider(),provider()]);assert.equal(calls,1);assert.deepEqual(a,b);assert.equal(relays(a).length,1);assert.deepEqual(relays(a)[0].urls,['turn:relay.example:3478']);assert.equal(relays(a)[0].username,'temporary-user');assert.equal(relays(a)[0].credential,'temporary-password');assert.ok(!JSON.stringify(a).includes('private-token'));
 await provider();assert.equal(calls,1);time=60001;await provider();assert.equal(calls,2);
});
test('TURN retries the backup token on upstream authentication failure',async()=>{
 const tokens=[];const provider=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'primary',KINNECT_HF_TOKEN_BACKUP:'backup'},fetchImpl:async(url,options)=>{tokens.push(options.headers.Authorization);return tokens.length===1?response(null,401):response([entry]);}});
 assert.equal(relays(await provider()).length,1);assert.deepEqual(tokens,['Bearer primary','Bearer backup']);
});
test('TURN upstream failure falls back to STUN, clears pending and retries on next request',async()=>{
 let calls=0;const provider=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'token'},fetchImpl:async()=>{calls++;return calls===1?response(null,503):response({iceServers:[entry]});}});
 assertStunOnly(await provider());assert.equal(relays(await provider()).length,1);assert.equal(calls,2);
});
test('malformed or STUN-only provider responses never create unauthenticated TURN relays',async()=>{
 for(const data of [null,{iceServers:[{urls:'turn:relay.example'}]},{iceServers:[{urls:'stun:relay.example'}]}]){
  const provider=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'token'},fetchImpl:async()=>response(data)});
  assertStunOnly(await provider());
 }
});
test('TURN missing-token and quota errors degrade to STUN without leaking provider credentials',async()=>{
 const missing=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface'},fetchImpl:()=>{throw Error('Must not fetch without token');}});
 assertStunOnly(await missing());
 const quota=await createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'secret'},fetchImpl:async()=>response(null,429)})();
 assertStunOnly(quota);assert.ok(!JSON.stringify(quota).includes('secret'));
});
test('static TURN configuration remains available without calling an upstream service',async()=>{
 const provider=createCallConfig({env:{TURN_URL:'turn:relay.example:3478, turns:relay.example:5349',TURN_USERNAME:'name',TURN_CREDENTIAL:'password'},fetchImpl:()=>{throw Error('Unexpected network call');}});
 const config=await provider();assert.equal(config.iceServers.length,3);assert.deepEqual(config.iceServers[2].urls,['turn:relay.example:3478','turns:relay.example:5349']);
});
