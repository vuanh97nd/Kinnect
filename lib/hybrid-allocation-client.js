export function createAllocationClient({url,secret,fetchImpl=fetch}){
 const origin=new URL(url);if(origin.protocol!=='https:'||origin.username||origin.password)throw Error('HTTPS allocation endpoint required');
 if(typeof secret!=='string'||secret.length<32)throw Error('Internal allocation secret required');
 async function call(path,value){
  const response=await fetchImpl(new URL(path,origin),{method:'POST',headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},body:JSON.stringify(value),redirect:'error',signal:AbortSignal.timeout(5000)});
  if(!response.ok)throw Object.assign(Error('Allocation temporarily unavailable'),{status:503});return response.json();
 }
 return{
  // Call only after validating the session; userId must come from server identity.
  allocate:userId=>call('/allocate',{userId}),
  renew:(userId,leaseId)=>call('/renew',{userId,leaseId}),
  release:(userId,leaseId)=>call('/release',{userId,leaseId}),
  heartbeat:()=>call('/pc-heartbeat',{}),
  status:()=>call('/status',{})
 };
}
