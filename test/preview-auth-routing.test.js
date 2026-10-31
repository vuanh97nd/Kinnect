import {test} from 'node:test';
import assert from 'node:assert/strict';
import {previewRoute} from '../cloud-gateway/preview-router.js';
test('routing keeps healthy PC when probes inconclusive, falls back when unavailable',async()=>{
 const original=globalThis.fetch;
 try{for(const pcReady of [true,false]){
  let cloudCalls=0,pcCalls=0;
  globalThis.fetch=async url=>{if(String(url).endsWith('/health'))return pcReady?Response.json({service:'kinnect-pc-shared-api'}):new Response('',{status:503});pcCalls++;return Response.json({user:{id:'test-user'}});};
  const env={PREVIEW_KEY:'test-key',PC_ORIGIN:'https://pc.example',CLOUD_ORIGIN:'https://cloud.example',ALLOCATOR:{idFromName:x=>x,get:()=>({fetch:async()=>Response.json({backend:pcReady?'pc':'cloud'})})},CLOUD_API:{fetch:async()=>{cloudCalls++;return Response.json({user:{id:'test-user'}});}}};
  for(const [path,method]of [['/api/login','POST'],['/api/me','GET'],['/api/logout','POST']]){
   const response=await previewRoute(new Request('https://gateway.example/preview'+path,{method,headers:{'X-Kinnect-Preview':'test-key','Content-Type':'application/json'},...(method==='POST'?{body:'{}'}:{})}),env);
   assert.equal(response.status,200);assert.equal(response.headers.get('X-Kinnect-Backend'),pcReady?'pc':'cloud');
  }
  assert.equal(pcReady?cloudCalls:pcCalls,pcReady?1:0); // one read-only cloud latency probe
 }}finally{globalThis.fetch=original;}
});
test('cross-site auth writes and missing preview access are rejected',async()=>{
 const env={PREVIEW_KEY:'test-key'};
 assert.equal((await previewRoute(new Request('https://gateway.example/preview/api/login',{method:'POST',headers:{'X-Kinnect-Preview':'test-key',Origin:'https://evil.example'},body:'{}'}),env)).status,403);
 assert.equal((await previewRoute(new Request('https://gateway.example/preview/api/me'),env)).status,404);
});

test('PC failing after health check uses cloud authentication and admission',async()=>{
 const original=globalThis.fetch;let unavailable=false;
 try{
  globalThis.fetch=async url=>String(url).endsWith('/health')?Response.json({service:'kinnect-pc-shared-api'}):new Response('',{status:503});
  const env={PREVIEW_KEY:'test-key',PC_ORIGIN:'https://pc.example',CLOUD_ORIGIN:'https://cloud.example',
   ALLOCATOR:{idFromName:x=>x,get:()=>({fetch:async url=>{if(String(url).endsWith('/pc-unavailable'))unavailable=true;return Response.json({backend:'cloud'});}})},
   CLOUD_API:{fetch:async req=>req.headers.get('Cookie')?.includes('A'.repeat(43))?new Response('',{status:503}):Response.json({user:{id:'test-user'}})}};
  const response=await previewRoute(new Request('https://gateway.example/preview/api/me',{headers:{'X-Kinnect-Preview':'test-key',Cookie:'kinnect_session=real-session'}}),env);
  assert.equal(response.status,200);assert.equal(response.headers.get('X-Kinnect-Backend'),'cloud');assert.equal(unavailable,true);
 }finally{globalThis.fetch=original;}
});
