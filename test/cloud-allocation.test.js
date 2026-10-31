import {test} from 'node:test';
import assert from 'node:assert/strict';
import {allocate,renew} from '../cloud-gateway/allocation.js';
test('PC is primary even when all cloud slots are empty',()=>{
 let state={leases:[],pcSeen:1000};for(let n=0;n<101;n++){const next=allocate(state,{userId:'u'+n},1001,()=>String(n));state=next.state;assert.equal(next.result.backend,'pc');}
 const next=allocate(state,{userId:'u0'},1002,()=> 'new');assert.equal(next.result.backend,'pc');assert.equal(next.state.leases.length,101);
});
test('PC offline queues overflow; expired cloud slot becomes available',()=>{
 let state={leases:[],pcSeen:0};for(let n=0;n<100;n++)state=allocate(state,{userId:'u'+n},100000,()=>String(n)).state;
 assert.equal(allocate(state,{userId:'overflow'},100001,()=> 'overflow').result.backend,'waiting');
 assert.equal(allocate(state,{userId:'later'},200000,()=> 'later').result.backend,'cloud');
});
test('renew requires ownership; PC disappearance uses cloud and returns when PC recovers',()=>{
 let state={leases:[{id:'x',userId:'a',backend:'pc',expires:200000}],pcSeen:100000};
 assert.equal(renew(state,{userId:'b',leaseId:'x'},100001).result.backend,'expired');
 const next=renew(state,{userId:'a',leaseId:'x'},140000);assert.equal(next.result.backend,'cloud');assert.equal(next.state.leases.length,1);
 next.state.pcSeen=140001;assert.equal(renew(next.state,{userId:'a',leaseId:'x'},140002).result.backend,'pc');
});
test('PC loss cannot move more than 100 users into cloud',()=>{
 let state={pcSeen:1,leases:Array.from({length:101},(_,n)=>({id:String(n),userId:'u'+n,backend:'pc',expires:300000}))};
 for(let n=0;n<101;n++){const next=renew(state,{userId:'u'+n,leaseId:String(n)},100000);state=next.state;assert.equal(next.result.backend,n<100?'cloud':'waiting');}
 assert.equal(state.leases.filter(x=>x.backend==='cloud').length,100);
});
