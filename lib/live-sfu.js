import {liveRoomBlocks} from './live-access.js';
import {WebSocket} from 'ws';
import {createCallConfig} from './call-config.js';

const bounded=(value,fallback,max)=>{const n=Number(value);return Number.isInteger(n)&&n>0?Math.min(n,max):fallback;};
/** Private SFU control. Accounts, permission decisions and chat stay in Kinnect. */
export function createLiveSFU({env={},send,social,onUnavailable=()=>{},fetchImpl}={}){
 const enabled=env.KINNECT_LIVE_TRANSPORT==='sfu';
 const endpoint=env.KINNECT_SFU_URL||'ws://127.0.0.1:7885/control';
 if(enabled){const u=new URL(endpoint);if(!['ws:','wss:'].includes(u.protocol)||u.username||u.password)throw Error('Invalid SFU control URL');if(u.protocol==='ws:'&&!['127.0.0.1','localhost','[::1]'].includes(u.hostname))throw Error('Remote SFU control requires TLS');if((env.KINNECT_SFU_SECRET||'').length<32)throw Error('SFU control secret must contain at least32 characters');}
 const maxViewers=bounded(env.KINNECT_LIVE_MAX_VIEWERS,100,5000),maxRooms=bounded(env.KINNECT_LIVE_MAX_ROOMS,20,1000);
 const ice=createCallConfig({env,fetchImpl});const snapshots=new Map();let ws,ready=false,closed=false,retry,heartbeat,lastPong=0;
 function transmit(value){if(!ready||ws?.readyState!==WebSocket.OPEN)throw Error('SFU unavailable');ws.send(JSON.stringify(value));}
 function discard(id){snapshots.delete(id);if(ready)transmit({type:'delete',room:id});}
 function fail(){ready=false;for(const id of [...snapshots.keys()]){snapshots.delete(id);onUnavailable(id);}}
 function connect(){if(!enabled||closed)return;ws=new WebSocket(endpoint,{headers:{Authorization:'Bearer '+env.KINNECT_SFU_SECRET},maxPayload:65536,handshakeTimeout:5000});ws.on('error',()=>{});ws.on('message',raw=>{let m;try{m=JSON.parse(raw);}catch{return;}if(m.type==='ready'){ready=true;lastPong=Date.now();return;}if(m.type==='pong'){lastPong=Date.now();return;}const snapshot=snapshots.get(m.room);if(!snapshot||m.revision!==snapshot.value.revision)return;const target=snapshot.room.members.get(m.to);if(!target||!social.authenticate(target.authRequest))return;const allowed=snapshot.byId.get(target.id);if(m.type==='signal'&&allowed&&(m.from==='@sfu'?allowed.publisher:allowed.subscriptions.includes(m.from))){send(target,{type:'signal',from:m.from,revision:m.revision,...(m.description?{description:m.description}:{candidate:m.candidate})});}else if(m.type==='media-error')send(target,{type:'live-mode-error',room:m.room,message:'Kết nối truyền Live bị gián đoạn. Hãy vào lại phòng.'});});ws.on('close',()=>{fail();if(!closed){retry=setTimeout(connect,2000);retry.unref();}});}
 if(enabled){connect();heartbeat=setInterval(()=>{if(!ready)return;if(Date.now()-lastPong>30000){ws.terminate();return;}transmit({type:'ping'});},10000);heartbeat.unref();}
 async function flush(snapshot){if(snapshot.pending)return snapshot.pending;snapshot.pending=(async()=>{const config=await ice();if(snapshots.get(snapshot.room.id)!==snapshot||!ready)return;const serialized=JSON.stringify(snapshot.value);if(serialized!==snapshot.sent){transmit({...snapshot.value,iceServers:config.iceServers});snapshot.sent=serialized;}})().finally(()=>{snapshot.pending=null;});return snapshot.pending;}
 function state(room,publishers,publicPeer,notify,isPublisher){
  const blocks=liveRoomBlocks(social,room);
  const ids=publishers.map(p=>p.id+':'+(room.guests.get(p.id)?.mode||'video')).join('|');let changed=room.sfuRoster!==ids;room.sfuRoster=ids;
  room.sfuAccess??=new Map();const members=[];
  for(const peer of room.members.values()){const visible=publishers.filter(p=>p===peer||!blocks.has(peer.userId,p.userId));const subscriptions=visible.filter(p=>p!==peer).map(p=>p.id);const access=subscriptions.join('|');if(room.sfuAccess.has(peer.id)&&room.sfuAccess.get(peer.id)!==access)changed=true;room.sfuAccess.set(peer.id,access);members.push({id:peer.id,publisher:isPublisher(room,peer),subscriptions});}
  for(const id of room.sfuAccess.keys())if(!room.members.has(id))room.sfuAccess.delete(id);
  if(changed||!room.stageRevision)room.stageRevision++;
  const byId=new Map(members.map(p=>[p.id,p]));
  for(const peer of room.members.values()){
   const stamp=room.id+':'+room.stageRevision+':'+room.liveLayout+':'+room.guestRequests.has(peer.id);if(peer.sfuStage===stamp)continue;peer.sfuStage=stamp;
   const spec=byId.get(peer.id),visible=publishers.filter(p=>p.id===peer.id||spec.subscriptions.includes(p.id));
   send(peer,{type:'live-stage',transport:'sfu',room:room.id,revision:room.stageRevision,selfId:peer.id,role:peer===room.host?'host':room.guests.has(peer.id)?'guest':'viewer',mode:room.guests.get(peer.id)?.mode||'video',requested:room.guestRequests.has(peer.id),layout:room.liveLayout,maxGuests:3,participants:visible.map(p=>publicPeer(room,p)),peers:spec.publisher?[{id:'@sfu',publishes:false,offer:true}]:[]});
  }
  let snapshot=snapshots.get(room.id);const value={type:'sync',room:room.id,revision:room.stageRevision,publishers:publishers.map(p=>({id:p.id,mode:room.guests.get(p.id)?.mode||'video'})),members};if(!snapshot){snapshot={room,value,byId,sent:null,pending:null};snapshots.set(room.id,snapshot);}else{snapshot.value=value;snapshot.byId=byId;}
  void flush(snapshot).catch(()=>{onUnavailable(room.id);});notify(room);
 }
 function signal(room,peer,m){const snapshot=snapshots.get(room.id);if(!snapshot||m.revision!==room.stageRevision)return;const member=snapshot.byId.get(peer.id);if(!member||(m.to==='@sfu'?!member.publisher:!member.subscriptions.includes(m.to)))return;
  if(m.description&&((m.to==='@sfu'&&m.description.type!=='offer')||(m.to!=='@sfu'&&m.description.type!=='answer')||typeof m.description.sdp!=='string'))return;
  if(!m.description&&!m.candidate)return;
  const revision=m.revision;void flush(snapshot).then(()=>{if(ready&&snapshots.get(room.id)===snapshot&&room.members.get(peer.id)===peer&&revision===room.stageRevision)transmit({type:'signal',room:room.id,revision,from:peer.id,to:m.to,...(m.description?{description:m.description}:{candidate:m.candidate})});}).catch(()=>onUnavailable(room.id));
 }
 function close(){closed=true;clearTimeout(retry);clearInterval(heartbeat);snapshots.clear();ready=false;if(ws){ws.removeAllListeners('close');ws.on('error',()=>{});ws.terminate();}}
 return {get available(){return enabled&&ready;},enabled,maxViewers,maxRooms,state,signal,discard,close,status:()=>({configured:enabled,ready,maxViewers,maxRooms})};
}
