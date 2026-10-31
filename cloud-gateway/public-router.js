import {sharedApiPath} from '../lib/shared-api-paths.js';
const json=(value,status=200)=>Response.json(value,{status,headers:{'Cache-Control':'no-store'}});
export async function publicRoute(request,env){
 const url=new URL(request.url),path=url.pathname;
 if(!env.PREVIEW_KEY||!env.CLOUD_API)return json({error:'Dịch vụ đang kết nối lại.'},503);
 if(!['GET','HEAD','POST','PUT','PATCH','DELETE'].includes(request.method))return json({error:'Phương thức không hỗ trợ.'},405);
 if(!['GET','HEAD'].includes(request.method)){
  const origin=request.headers.get('Origin');if(origin&&origin!==url.origin)return json({error:'Origin rejected'},403);
 }
 const cloud=async(input)=>{
  const target=new URL(input.url);target.hostname='kinnect-cloud-api.vuanh97nd.workers.dev';
  const headers=new Headers(input.headers);headers.delete('X-Kinnect-Original-Url');headers.set('X-Kinnect-Preview',env.PREVIEW_KEY);
  headers.set('X-Kinnect-Client-IP',request.headers.get('CF-Connecting-IP')||'unknown');
  if(headers.has('Origin'))headers.set('Origin',target.origin);
  return env.CLOUD_API.fetch(new Request(target,{method:input.method,headers,body:['GET','HEAD'].includes(input.method)?undefined:input.body,redirect:'manual'}));
 };
 try{
  if(sharedApiPath(path,request.method)){
   const response=await cloud(request);const headers=new Headers(response.headers);headers.set('X-Kinnect-Backend','cloud');headers.set('Cache-Control','no-store');
   if(path==='/api/me'&&response.ok){
    const data=await response.json();try{
     const pc=await fetch(new URL('/api/me?legacy=1',env.LEGACY_ORIGIN||'https://app.kinnect.io.vn'),{headers:{Cookie:request.headers.get('Cookie')||''},redirect:'manual',signal:AbortSignal.timeout(1800)});
     if(pc.ok){const extra=(await pc.json()).user;if(extra?.id===data.user.id)data.user={...data.user,...extra,role:data.user.role,suspended:data.user.suspended,blockedUserIds:data.user.blockedUserIds};}
    }catch{}
    return new Response(JSON.stringify(data),{status:200,headers});
   }
   return new Response(response.body,{status:response.status,headers});
  }
  // Authenticate on cloud before forwarding private media/social requests to the PC.
  const auth=await cloud(new Request(url.origin+'/api/me',{headers:{Cookie:request.headers.get('Cookie')||''}}));
  if(auth.status!==200)return json({error:auth.status===401?'Vui lòng đăng nhập.':'Dịch vụ đang kết nối lại.'},auth.status===401?401:503);
  const legacy=new URL(url.pathname+url.search,env.LEGACY_ORIGIN||'https://app.kinnect.io.vn');
  const headers=new Headers(request.headers);for(const key of ['Host','X-Kinnect-Preview','X-Kinnect-Original-Url','X-Kinnect-Client-IP'])headers.delete(key);
  if(headers.has('Origin'))headers.set('Origin',legacy.origin);
  if(request.headers.get('Upgrade')?.toLowerCase()==='websocket'){
   const ready=await fetch(new URL('/api/me?legacy=1',legacy),{headers:{Cookie:request.headers.get('Cookie')||''},redirect:'manual',signal:AbortSignal.timeout(3000)});
   if(!ready.ok)return json({error:'Máy chủ cuộc gọi đang ngoại tuyến.'},503);
  }
  const response=await fetch(new Request(legacy,{method:request.method,headers,body:['GET','HEAD'].includes(request.method)?undefined:request.body,redirect:'manual',signal:AbortSignal.timeout(8000)}));
  if(response.status>=500)throw Error('PC unavailable');
  if(response.status===101)return response;
  if(response.status>=300&&response.status<400)return json({error:'Đường dẫn chưa sẵn sàng.'},503);
  return response;
 }catch{
  if(request.method==='GET'&&(['/api/discover','/api/friends','/api/friend-requests','/api/friend-suggestions'].includes(path)||/^\/api\/users\/[^/]+$/.test(path)))return cloud(request);
  if(request.method==='GET'&&['/api/posts','/api/shorts'].includes(path))return cloud(request);
  if(request.method==='GET'&&path==='/api/stories')return json({stories:[],offline:true});
  return json({error:'Máy chủ ảnh/video đang ngoại tuyến. Đăng nhập và nhắn tin vẫn sử dụng được.',offline:true},503);
 }
}
