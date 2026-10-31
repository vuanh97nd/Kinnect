export function selectFastest({pcMs,cloudMs,previous='pc',marginMs=25}){
 const pc=Number.isFinite(pcMs)&&pcMs>=0,cloud=Number.isFinite(cloudMs)&&cloudMs>=0;
 if(!pc)return cloud?'cloud':null;if(!cloud)return 'pc';
 if(previous==='pc'&&cloudMs+marginMs>=pcMs)return 'pc';
 if(previous==='cloud'&&pcMs+marginMs>=cloudMs)return 'cloud';
 return pcMs<=cloudMs?'pc':'cloud';
}
const cache=new WeakMap();
export async function backendPreference(env,pcReady){
 if(!pcReady)return 'cloud';
 let state=cache.get(env);if(!state){state={until:0,selected:'pc',pending:null};cache.set(env,state);}
 if(state.until>Date.now())return state.selected;
 if(!state.pending)state.pending=(async()=>{
  async function probe(backend){const target=new URL('/api/me',backend==='pc'?env.PC_ORIGIN:env.CLOUD_ORIGIN);
   const headers={'X-Kinnect-Preview':env.PREVIEW_KEY,'X-Kinnect-Original-Url':target.toString(),Cookie:'kinnect_session='+'A'.repeat(43)};
   const request=new Request(target.toString(),{headers,redirect:'manual',signal:AbortSignal.timeout(8000)}),start=Date.now();
   try{const r=await(backend==='cloud'?env.CLOUD_API.fetch(request):fetch(request));await r.arrayBuffer();return r.status===401?Date.now()-start:Infinity;}catch{return Infinity;}
  }
  const [pcMs,cloudMs]=await Promise.all([probe('pc'),probe('cloud')]);
  state.selected=selectFastest({pcMs,cloudMs,previous:state.selected})||'pc';state.until=Date.now()+60000;return state.selected;
 })().finally(()=>{state.pending=null;});
 return state.pending;
}
export function preferPcAfterCloudError(env){const state=cache.get(env);if(state){state.selected='pc';state.until=Date.now()+30000;}}
