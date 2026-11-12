// Server-only: never send KINNECT_HF_TOKEN to the browser.
export function createCallConfig({env=process.env,fetchImpl=globalThis.fetch,now=Date.now}={}){
 let cache=null,pending=null;
 const stun=[
  {urls:['stun:stun.l.google.com:19302','stun:stun1.l.google.com:19302']},
  {urls:['stun:stun.cloudflare.com:3478','stun:stun.cloudflare.com:443']}
 ];
 return async function callConfig(){
  if(env.KINNECT_TURN_PROVIDER!=='huggingface'){
   const iceServers=[...stun];
   if(env.TURN_URL&&env.TURN_USERNAME&&env.TURN_CREDENTIAL)iceServers.push({urls:env.TURN_URL.split(',').map(s=>s.trim()).filter(Boolean),username:env.TURN_USERNAME,credential:env.TURN_CREDENTIAL});
   return {iceServers};
  }
  const token=env.KINNECT_HF_TOKEN;
  if(!token)return {iceServers:[...stun]};
  const backup=env.KINNECT_HF_TOKEN_BACKUP;
  const key=JSON.stringify([token,backup||'']);
  if(cache&&cache.key===key&&cache.until>now())return cache.value;
  if(pending&&pending.key===key)return pending.promise;
  const promise=(async()=>{
   const tokens=[...new Set([token,backup].filter(Boolean))];
   for(let index=0;index<tokens.length;index++){
    const activeToken=tokens[index];
    let response;
    try{
      response=await fetchImpl('https://fastrtc-turn-service.hf.space/credentials?ttl=3600',{headers:{Authorization:'Bearer '+activeToken},redirect:'error',signal:AbortSignal.timeout(10000)});
    }catch(err){
      if(index+1<tokens.length)continue;
      console.warn('[CALL-CONFIG] TURN service unreachable, using STUN fallback.');
      return {iceServers:[...stun]};
    }
    if(!response.ok&&(response.status===401||response.status>=500)&&index+1<tokens.length)continue;
    if(!response.ok){
      console.warn('[CALL-CONFIG] TURN service HTTP', response.status, ', using STUN fallback.');
      return {iceServers:[...stun]};
    }
    let data;try{data=await response.json();}catch{return {iceServers:[...stun]};}
    const entries=Array.isArray(data)?data:data?.iceServers;
    if(!Array.isArray(entries))return {iceServers:[...stun]};
    const iceServers=entries.flatMap(s=>{
     if(!s||typeof s!=='object')return [];
     const urls=(Array.isArray(s.urls)?s.urls:[s.urls]).filter(u=>typeof u==='string'&&/^(stun|turn|turns):/i.test(u)&&!/:53(?:\?|$)/.test(u));
     if(!urls.length)return [];
     const server={urls};
     if(urls.some(u=>/^turns?:/i.test(u))){if(typeof s.username!=='string'||typeof s.credential!=='string'||!s.credential)return [];server.username=s.username;server.credential=s.credential;}
     return [server];
    });
    // Hợp nhất cả Google STUN và Cloudflare TURN để đảm bảo xuyên NAT tối đa
    const combinedServers=[...stun];
    for(const s of iceServers){
      const uStr=JSON.stringify(s.urls);
      if(!combinedServers.some(existing=>JSON.stringify(existing.urls)===uStr)){
        combinedServers.push(s);
      }
    }
    const value={iceServers:combinedServers};cache={key,until:now()+60000,value};return value;
   }
   return {iceServers:[...stun]};
  })();
  const task={key,promise};pending=task;
  try{return await promise;}finally{if(pending===task)pending=null;}
 };
}
