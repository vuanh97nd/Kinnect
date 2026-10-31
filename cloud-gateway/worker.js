import {allocate,renew,CLOUD_CAP} from './allocation.js';
import {previewRoute} from './preview-router.js';
import {publicRoute} from './public-router.js';
const json=(value,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store'}});
async function authorized(request,secret){
 if(!secret||secret.length<32)return false;
 const received=request.headers.get('Authorization')||'';
 const hash=async value=>new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)));
 const [a,b]=await Promise.all([hash(received),hash('Bearer '+secret)]);let diff=0;for(let n=0;n<a.length;n++)diff|=a[n]^b[n];return diff===0;
}
export default {
 async fetch(request,env){
  const path=new URL(request.url).pathname;
  if((path.startsWith('/api/')||request.headers.get('Upgrade')?.toLowerCase()==='websocket')&&env.PUBLIC_BASIC_API==='true')return publicRoute(request,env);
  if(path.startsWith('/preview/'))return previewRoute(request,env);
  if(path==='/health'&&request.method==='GET')return json({ok:true,service:'kinnect-allocation',policy:'shared-cloud-core',cloudCap:CLOUD_CAP,productionRouting:env.PUBLIC_BASIC_API==='true'});
  if(!await authorized(request,env.GATEWAY_INTERNAL_SECRET))return json({error:'Unauthorized'},401);
  if(!['/allocate','/renew','/release','/pc-heartbeat','/pc-unavailable','/status'].includes(path))return json({error:'Not found'},404);
  if(request.method!=='POST')return json({error:'Method not allowed'},405);
  if(Number(request.headers.get('Content-Length')||0)>2048)return json({error:'Too large'},413);
  const raw=await request.text();if(raw.length>2048)return json({error:'Too large'},413);
  let input;try{input=JSON.parse(raw);}catch{return json({error:'Invalid JSON'},400);}
  if(!input||typeof input!=='object'||Array.isArray(input))return json({error:'Invalid request'},400);
  // Only trusted API servers call this service after authenticating the user.
  // The secret is NEVER sent to APK/browser clients.
  if(['/allocate','/renew','/release'].includes(path)&&(!/^[A-Za-z0-9_-]{1,100}$/.test(input.userId||'')||typeof input.userId!=='string'))return json({error:'Invalid user'},400);
  if(['/renew','/release'].includes(path)&&(!/^[a-f0-9-]{36}$/.test(input.leaseId||'')))return json({error:'Invalid lease'},400);
  return env.ALLOCATOR.get(env.ALLOCATOR.idFromName('global-v1')).fetch('https://allocator'+path,{method:'POST',body:JSON.stringify(input)});
 }
};
export class Allocator {
 constructor(ctx){this.ctx=ctx;}
 async fetch(request){
  const path=new URL(request.url).pathname,input=await request.json(),now=Date.now();
  const result=await this.ctx.storage.transaction(async tx=>{
   let state=await tx.get('allocation')||{leases:[],pcSeen:0};let output;
   if(path==='/pc-heartbeat'){state.pcSeen=now;output={ok:true};}
   else if(path==='/pc-unavailable'){state.pcSeen=0;output={ok:true};}
   else if(path==='/allocate'){const next=allocate(state,input,now,()=>crypto.randomUUID());state=next.state;output=next.result;}
   else if(path==='/renew'){const next=renew(state,input,now);state=next.state;output=next.result;}
   else if(path==='/release'){state.leases=state.leases.filter(x=>!(x.userId===input.userId&&x.id===input.leaseId));output={ok:true};}
   else{const leases=state.leases.filter(x=>x.expires>now);output={cloud:leases.filter(x=>x.backend==='cloud').length,pc:leases.filter(x=>x.backend==='pc').length,pcReady:state.pcSeen>now-30000,cap:CLOUD_CAP};}
   await tx.put('allocation',state);return output;
  });
  return json(result);
 }
}
