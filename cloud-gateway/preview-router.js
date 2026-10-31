const json=(data,status)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
import {backendPreference,preferPcAfterCloudError} from './latency-policy.js';
export async function previewRoute(request,env){
 if(!env.PREVIEW_KEY||request.headers.get('X-Kinnect-Preview')!==env.PREVIEW_KEY)return json({error:'Not found'},404);
 const url=new URL(request.url),path=url.pathname.slice('/preview'.length)+url.search;
 if(path==='/api/preview-connectivity'){
  const checks=[];for(const name of ['PC_ORIGIN','CLOUD_ORIGIN']){try{const target=new URL('/health',env[name]);const r=await fetch(target.toString(),{redirect:'manual',signal:AbortSignal.timeout(5000)});const location=r.headers.get('Location');let payload;try{payload=await r.json();}catch{}checks.push({name,status:r.status,type:r.headers.get('Content-Type'),service:payload?.service,redirectHost:location?new URL(location,target).hostname:null});}catch{checks.push({name,status:0});}}
  return json({checks},200);
 }
 if(request.method==='POST'){
  const origin=request.headers.get('Origin');if(origin&&origin!==url.origin)return json({error:'Origin rejected'},403);
 }
 if(!path.startsWith('/api/'))return json({error:'Not found'},404);
 if(request.headers.get('Upgrade'))return json({error:'Use the shared realtime endpoint during preview'},426);
 let pcReady=false;
 try{const health=await fetch(new URL('/health',env.PC_ORIGIN).toString(),{signal:AbortSignal.timeout(5000),redirect:'manual'});pcReady=health.ok&&(await health.json()).service==='kinnect-pc-shared-api';}catch{}
 const stub=env.ALLOCATOR.get(env.ALLOCATOR.idFromName('global-v1'));
 const internal=async(action,input={})=>(await stub.fetch('https://allocator/'+action,{method:'POST',body:JSON.stringify(input)})).json();
 await internal(pcReady?'pc-heartbeat':'pc-unavailable');
 let backend=await backendPreference(env,pcReady),origin=backend==='pc'?env.PC_ORIGIN:env.CLOUD_ORIGIN;
 async function forward(apiPath,method,body,cookie=request.headers.get('Cookie')){
  const target=new URL(apiPath,origin),headers=new Headers({'X-Kinnect-Preview':env.PREVIEW_KEY,'Content-Type':'application/json','X-Kinnect-Original-Url':target.toString()});
  if(cookie)headers.set('Cookie',cookie);if(request.headers.get('Origin'))headers.set('Origin',target.origin);
  headers.set('X-Kinnect-Client-IP',request.headers.get('CF-Connecting-IP')||'unknown');
  const init={method,headers,...(body!==undefined?{body}:{}),redirect:'manual',signal:AbortSignal.timeout(15000)};
  const result=await(backend==='cloud'&&env.CLOUD_API?env.CLOUD_API.fetch(new Request(target.toString(),init)):fetch(target.toString(),init));
  if(result.status>=300&&result.status<400)throw Error('Upstream redirect rejected');return result;
 }
 if(!['/api/login','/api/register'].includes(path)){
  let authenticated;try{authenticated=await forward('/api/me','GET');}catch{}
  if((!authenticated||authenticated.status>=500)&&backend==='cloud'&&pcReady){preferPcAfterCloudError(env);backend='pc';origin=env.PC_ORIGIN;try{authenticated=await forward('/api/me','GET');}catch{}}
  else if((!authenticated||authenticated.status>=500)&&backend==='pc'){
   await internal('pc-unavailable');pcReady=false;backend='cloud';origin=env.CLOUD_ORIGIN;
   try{authenticated=await forward('/api/me','GET');}catch{}
  }
  if(!authenticated||authenticated.status!==200)return json({error:'Vui lòng đăng nhập.'},authenticated?.status===401?401:503);
  const user=(await authenticated.json()).user;const admission=await internal('allocate',{userId:user.id,preferred:backend});
  if(admission.backend==='waiting')return json({error:'Cloud đang đủ 100 người. Vui lòng chờ.',retryAfter:10},429);
  backend=admission.backend;origin=backend==='pc'?env.PC_ORIGIN:env.CLOUD_ORIGIN;
 }
 let body;if(!['GET','HEAD'].includes(request.method)){body=await request.text();if(body.length>16384)return json({error:'Too large'},413);}
 let response;try{response=await forward(path,request.method,body);}catch(error){const m=String(error.message||'').toLowerCase();return json({error:'Kết nối bị gián đoạn. Kiểm tra kết quả trước khi gửi lại.',diagnostic:{backend,name:error.name,kind:m.includes('redirect')?'redirect':m.includes('body')?'body':m.includes('signal')?'signal':m.includes('loop')?'loop':m.includes('fetch')?'fetch':m.includes('limit')?'limit':'other'}},503);}
 if(['/api/login','/api/register'].includes(path)&&response.status===200){
  const user=(await response.clone().json()).user,admission=await internal('allocate',{userId:user.id,preferred:backend});
  if(admission.backend==='waiting'){
   const cookie=response.headers.get('Set-Cookie')?.split(';')[0];if(cookie)await forward('/api/logout','POST','{}',cookie).catch(()=>{});
   return json({error:'Cloud đang đủ 100 người. Vui lòng chờ.',retryAfter:10},429);
  }
 }
 if(backend==='cloud'&&pcReady&&response.status>=500){
  preferPcAfterCloudError(env);
  if(['GET','HEAD'].includes(request.method)){backend='pc';origin=env.PC_ORIGIN;try{response=await forward(path,request.method,undefined);}catch{return json({error:'Máy chủ tạm thời chưa phản hồi.'},503);}}
 }
 const headers=new Headers(response.headers);headers.set('X-Kinnect-Backend',backend);headers.set('Cache-Control','no-store');
 return new Response(response.body,{status:response.status,headers});
}
