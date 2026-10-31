import{test}from'node:test';import assert from'node:assert/strict';import{selectFastest}from'../cloud-gateway/latency-policy.js';import{allocate}from'../cloud-gateway/allocation.js';
test('select healthy faster backend and avoid jitter',()=>{
 assert.equal(selectFastest({pcMs:500,cloudMs:400}),'cloud');
 assert.equal(selectFastest({pcMs:500,cloudMs:490}),'pc');
 assert.equal(selectFastest({pcMs:Infinity,cloudMs:800}),'cloud');
 assert.equal(selectFastest({pcMs:300,cloudMs:Infinity,previous:'cloud'}),'pc');
 assert.equal(selectFastest({pcMs:Infinity,cloudMs:Infinity}),null);
});
test('faster cloud preference never bypasses 100 slots',()=>{
 let state={pcSeen:1000,leases:[]};for(let n=0;n<101;n++){const next=allocate(state,{userId:'u'+n,preferred:'cloud'},1001,()=>String(n));state=next.state;assert.equal(next.result.backend,n<100?'cloud':'pc');}
});
