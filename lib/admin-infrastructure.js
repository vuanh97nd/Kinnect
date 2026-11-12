export function createAdminInfrastructure({cloudEnabled,fetchImpl=fetch,clock=Date.now}){
 let cached,at=0;
 async function check(origin){try{const r=await fetchImpl(origin+'/health',{signal:AbortSignal.timeout(1800),redirect:'error'});const d=await r.json();return{origin,status:r.ok&&d.ok?'reachable':'unhealthy',service:d.service||null,productionRouting:d.productionRouting===true};}catch{return{origin,status:'unreachable',service:null,productionRouting:false};}}
 return async()=>{
  if(cached&&clock()-at<10000)return cached;
  const services=cloudEnabled?await Promise.all([check('https://kinnect-allocation.vuanh97nd.workers.dev'),check('https://kinnect-cloud-api.vuanh97nd.workers.dev')]):[];
  cached={checkedAt:clock(),primary:{kind:'pc',status:'responding'},cloud:{configured:!!cloudEnabled,services},defaults:{identity:cloudEnabled?'cloud':'local',wallet:cloudEnabled?'cloud':'local',staff:'pc',tickets:'pc'},failover:{app:cloudEnabled?'configured_partial':'not_configured',adminConsole:'not_configured'}};at=clock();return cached;
 };
}
