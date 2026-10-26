// Server-only: never send KINNECT_HF_TOKEN to the browser.
export function createCallConfig({env=process.env,fetchImpl=globalThis.fetch,now=Date.now}={}){
 let cache=null,pending=null;
 const stun=[{urls:'stun:stun.l.google.com:19302'},{urls:'stun:stun.cloudflare.com:3478'}];
 return async function callConfig(){
  if(env.KINNECT_TURN_PROVIDER!=='huggingface'){
   const iceServers=[...stun];
   if(env.TURN_URL&&env.TURN_USERNAME&&env.TURN_CREDENTIAL)iceServers.push({urls:env.TURN_URL.split(',').map(s=>s.trim()).filter(Boolean),username:env.TURN_USERNAME,credential:env.TURN_CREDENTIAL});
   return {iceServers};
  }
  const token=env.KINNECT_HF_TOKEN;
  if(!token)throw Error('Chưa cấu hình token cho dịch vụ TURN.');
  const backup=env.KINNECT_HF_TOKEN_BACKUP;
  const key=JSON.stringify([token,backup||'']);
  if(cache&&cache.key===key&&cache.until>now())return cache.value;
  if(pending&&pending.key===key)return pending.promise;
  const promise=(async()=>{
   const tokens=[...new Set([token,backup].filter(Boolean))];
   for(let index=0;index<tokens.length;index++){
   const activeToken=tokens[index];
   let response;
   try{response=await fetchImpl('https://fastrtc-turn-service.hf.space/credentials?ttl=3600',{headers:{Authorization:'Bearer '+activeToken},redirect:'error',signal:AbortSignal.timeout(10000)});}catch{if(index+1<tokens.length)continue;throw Error('Không liên lạc được dịch vụ TURN. Vui lòng thử lại.');}
   if(!response.ok&&(response.status===401||response.status>=500)&&index+1<tokens.length)continue;
   if(!response.ok)throw Error(response.status===429||response.status===403?'Dịch vụ TURN từ chối yêu cầu hoặc đã hết hạn mức miễn phí.':'Không lấy được cấu hình TURN. Vui lòng kiểm tra token trên máy chủ.');
   let data;try{data=await response.json();}catch{throw Error('Dịch vụ TURN trả dữ liệu không hợp lệ.');}
   const entries=Array.isArray(data)?data:data?.iceServers;
   if(!Array.isArray(entries))throw Error('Dịch vụ TURN trả cấu hình không hợp lệ.');
   const iceServers=entries.flatMap(s=>{
    if(!s||typeof s!=='object')return [];
    const urls=(Array.isArray(s.urls)?s.urls:[s.urls]).filter(u=>typeof u==='string'&&/^(stun|turn|turns):/i.test(u)&&!/:53(?:\?|$)/.test(u));
    if(!urls.length)return [];
    const server={urls};
    if(urls.some(u=>/^turns?:/i.test(u))){if(typeof s.username!=='string'||typeof s.credential!=='string'||!s.credential)return [];server.username=s.username;server.credential=s.credential;}
    return [server];
   });
   if(!iceServers.some(s=>s.urls.some(u=>/^turns?:/i.test(u))))throw Error('Dịch vụ chưa cấp máy chủ TURN hợp lệ.');
   const value={iceServers};cache={key,until:now()+60000,value};return value;
   }
  })();
  const task={key,promise};pending=task;
  try{return await promise;}finally{if(pending===task)pending=null;}
 };
}
