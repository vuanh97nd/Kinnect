import test from 'node:test';
import assert from 'node:assert/strict';
import {createCallConfig} from '../lib/call-config.js';
const entry={urls:['turn:relay.example:3478','turn:relay.example:53'],username:'temporary-user',credential:'temporary-password'};
const response=(data,status=200)=>({ok:status===200,status,json:async()=>data});
test('TURN credentials coalesce concurrent requests, expire and never return provider tokens',async()=>{
 let calls=0,time=0;const provider=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'private-token'},now:()=>time,fetchImpl:async(url,options)=>{calls++;assert.equal(options.headers.Authorization,'Bearer private-token');await new Promise(r=>setImmediate(r));return response({iceServers:[entry]});}});
 const [a,b]=await Promise.all([provider(),provider()]);assert.equal(calls,1);assert.deepEqual(a,b);assert.equal(a.iceServers[0].urls.length,1);assert.ok(!JSON.stringify(a).includes('private-token'));
 await provider();assert.equal(calls,1);time=60001;await provider();assert.equal(calls,2);
});
test('TURN retries the backup token on upstream authentication failure',async()=>{
 const tokens=[];const provider=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'primary',KINNECT_HF_TOKEN_BACKUP:'backup'},fetchImpl:async(url,options)=>{tokens.push(options.headers.Authorization);return tokens.length===1?response(null,401):response([entry]);}});
 assert.equal((await provider()).iceServers.length,1);assert.deepEqual(tokens,['Bearer primary','Bearer backup']);
});
test('TURN clears failed requests and rejects malformed or STUN-only credentials',async()=>{
 let calls=0;const provider=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'token'},fetchImpl:async()=>{calls++;return response(calls===1?{iceServers:[{urls:'stun:relay.example'}]}:{iceServers:[entry]});}});
 await assert.rejects(provider(),/TURN hợp lệ/);assert.equal((await provider()).iceServers.length,1);assert.equal(calls,2);
 const malformed=createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'token'},fetchImpl:async()=>response({iceServers:[{urls:'turn:relay.example'}]})});await assert.rejects(malformed(),/TURN hợp lệ/);
});
test('TURN missing-token and quota errors do not expose credentials',async()=>{
 await assert.rejects(createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface'}})(),/Chưa cấu hình/);
 await assert.rejects(createCallConfig({env:{KINNECT_TURN_PROVIDER:'huggingface',KINNECT_HF_TOKEN:'secret'},fetchImpl:async()=>response(null,429)})(),/hạn mức/);
});
test('static TURN configuration remains available without calling an upstream service',async()=>{
 const provider=createCallConfig({env:{TURN_URL:'turn:relay.example:3478, turns:relay.example:5349',TURN_USERNAME:'name',TURN_CREDENTIAL:'password'},fetchImpl:()=>{throw Error('Unexpected network call');}});
 const config=await provider();assert.equal(config.iceServers.length,3);assert.deepEqual(config.iceServers[2].urls,['turn:relay.example:3478','turns:relay.example:5349']);
});
