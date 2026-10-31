export const CLOUD_CAP=100;
export const LEASE_MS=90000;
export const PC_HEARTBEAT_MS=30000;
function preferred(state,leases,now,excludeId,choice){
 const pc=state.pcSeen>0&&state.pcSeen>now-PC_HEARTBEAT_MS;
 const cloud=leases.filter(x=>x.backend==='cloud'&&x.id!==excludeId).length<CLOUD_CAP;
 if(choice==='cloud'&&cloud)return 'cloud';
 if(pc)return 'pc';return cloud?'cloud':null;
}
export function allocate(state,input,now,makeId){
 const leases=(state.leases||[]).filter(x=>x.expires>now);
 const active=leases.find(x=>x.userId===input.userId);
 const backend=preferred(state,leases,now,active?.id,input.preferred);
 if(!backend)return {state:{...state,leases:leases.filter(x=>x!==active)},result:{backend:'waiting',retryAfter:10}};
 if(active){active.backend=backend;active.expires=now+LEASE_MS;return {state:{...state,leases},result:{backend,leaseId:active.id,expires:active.expires}};}
 const lease={id:makeId(),userId:input.userId,backend,expires:now+LEASE_MS};leases.push(lease);
 return {state:{...state,leases},result:{backend,leaseId:lease.id,expires:lease.expires}};
}
export function renew(state,input,now){
 const leases=(state.leases||[]).filter(x=>x.expires>now);
 const lease=leases.find(x=>x.userId===input.userId&&x.id===input.leaseId);
 if(!lease)return {state:{...state,leases},result:{backend:'expired'}};
 const backend=preferred(state,leases,now,lease.id,input.preferred);
 if(!backend){
  return {state:{...state,leases:leases.filter(x=>x!==lease)},result:{backend:'waiting',retryAfter:10}};
 }
 lease.backend=backend;lease.expires=now+LEASE_MS;return{state:{...state,leases},result:{backend,leaseId:lease.id,expires:lease.expires}};
}
