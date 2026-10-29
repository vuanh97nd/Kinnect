import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createApp} from '../server.js';
import {storeAccountId} from '../lib/store.js';

async function setup(t){
 const receipts=new Map(),acks=[],verifier={enabled:()=>true,verify:async token=>{if(!receipts.has(token))throw Object.assign(Error('invalid receipt'),{status:422});return receipts.get(token);},acknowledge:async(id,token)=>acks.push({id,token})};
 const app=createApp({storeVerifier:verifier,storeEnv:{PLAY_PURCHASE_TOKEN_KEY:'ab'.repeat(32)},authLimit:1000});await new Promise(r=>app.server.listen(0,'127.0.0.1',r));
 t.after(async()=>{for(const ws of app.wss.clients)ws.terminate();app.wss.close();app.server.closeAllConnections();await new Promise(r=>app.server.close(r));app.social.close();});
 const request=async(path,{cookie,method='GET',data,origin}={})=>{const response=await fetch('http://127.0.0.1:'+app.server.address().port+'/api'+path,{method,headers:{...(cookie?{Cookie:cookie}:{}),...(data?{'Content-Type':'application/json'}:{}),...(origin?{Origin:origin}:{})},body:data?JSON.stringify(data):undefined});return {status:response.status,body:await response.json(),cookie:response.headers.get('set-cookie')?.split(';')[0]};};
 const register=async username=>{const r=await request('/register',{method:'POST',data:{username,name:username,password:'strong-password',agree18:true,acceptPrivacyNotice:true}});return {id:r.body.user.id,username,cookie:r.cookie};};
 const receipt=(id,product='kinnect_style_aurora',state='PURCHASED')=>({obfuscatedExternalAccountId:storeAccountId(id),purchaseStateContext:{purchaseState:state},productLineItem:[{productId:product,quantity:1}],acknowledgementState:'ACKNOWLEDGEMENT_STATE_PENDING'});
 return {...app,request,register,receipts,acks,receipt};
}
test('store rejects client-side unlocks, forged owners, products and cross-origin writes',async t=>{
 const a=await setup(t),alice=await a.register('store_alice'),bob=await a.register('store_bob');
 assert.equal((await a.request('/store')).status,401);
 assert.equal((await a.request('/store/style',{cookie:alice.cookie,method:'POST',data:{productId:'kinnect_style_aurora'}})).status,403);
 a.receipts.set('receipt-token-1',a.receipt(alice.id));
 assert.equal((await a.request('/store/verify',{cookie:bob.cookie,method:'POST',data:{productId:'kinnect_style_aurora',purchaseToken:'receipt-token-1'}})).status,403);
 assert.equal((await a.request('/store/verify',{cookie:alice.cookie,method:'POST',data:{productId:'kinnect_studio_pro',purchaseToken:'receipt-token-1'}})).status,422);
 assert.equal((await a.request('/store/verify',{cookie:alice.cookie,method:'POST',origin:'https://evil.example',data:{productId:'kinnect_style_aurora',purchaseToken:'receipt-token-1'}})).status,403);
 assert.deepEqual((await a.request('/store',{cookie:alice.cookie})).body.owned,[]);
});
test('verified purchase restore is idempotent, tokens are encrypted, style is shared publicly and refunds revoke it',async t=>{
 const a=await setup(t),u=await a.register('store_owner'),token='verified-receipt-token';a.receipts.set(token,a.receipt(u.id));
 const data={productId:'kinnect_style_aurora',purchaseToken:token};
 for(let i=0;i<2;i++)assert.equal((await a.request('/store/verify',{cookie:u.cookie,method:'POST',data})).status,200);
 assert.equal(a.social.db.prepare('SELECT COUNT(*) n FROM store_purchases').get().n,1);assert.ok(!a.social.db.prepare('SELECT token_cipher FROM store_purchases').get().token_cipher.includes(token));
 assert.equal((await a.request('/store/style',{cookie:u.cookie,method:'POST',data:{productId:data.productId}})).status,200);
 assert.equal((await a.request('/me',{cookie:u.cookie})).body.user.storeStyle,data.productId);
 a.receipts.set(token,a.receipt(u.id,data.productId,'CANCELLED'));await a.request('/store/verify',{cookie:u.cookie,method:'POST',data});
 assert.deepEqual((await a.request('/store',{cookie:u.cookie})).body.owned,[]);assert.equal((await a.request('/me',{cookie:u.cookie})).body.user.storeStyle,'');
});
test('pending transactions grant nothing; deletion erases receipts and preferences',async t=>{
 const a=await setup(t),u=await a.register('store_pending'),token='pending-token-123';a.receipts.set(token,a.receipt(u.id,'kinnect_studio_pro','PENDING'));
 const r=await a.request('/store/verify',{cookie:u.cookie,method:'POST',data:{productId:'kinnect_studio_pro',purchaseToken:token}});assert.equal(r.body.state,'PENDING');assert.deepEqual(r.body.owned,[]);assert.equal(a.acks.length,0);
 assert.equal((await a.request('/me/account-deletion',{cookie:u.cookie,method:'DELETE',data:{confirmUsername:u.username,confirmDelete:true}})).status,200);assert.equal(a.social.db.prepare('SELECT COUNT(*) n FROM store_purchases').get().n,0);
});
