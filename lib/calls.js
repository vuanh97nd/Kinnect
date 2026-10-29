import {randomUUID} from 'node:crypto';
export function createCalls({social,wss,send,webPush,visible=()=>true}){
 const calls=new Map();
 const peers=(id)=>[...wss.clients].filter(ws=>ws.userId===id&&social.authenticate(ws.authRequest));
 const busy=id=>[...calls.values()].some(c=>c.caller.userId===id||c.targetId===id);
 function finish(c,reason){if(!calls.delete(c.id))return;if(c.pushed&&webPush)webPush.callEnded(c.targetId,c,c.acceptedAt?'answered':reason,social.user(c.caller.userId));if(c.acceptedAt)social.recordCallEvent?.(c.caller.userId,c.targetId,c.mode,'ended',Math.max(1,Math.floor((Date.now()-c.acceptedAt)/1000)));clearTimeout(c.timeout);for(const timer of c.reconnects?.values()||[])clearTimeout(timer);for(const ws of new Set([c.caller,...c.targets]))send(ws,{type:'call-ended',callId:c.id,reason});}
 function disconnect(ws){for(const c of calls.values())if(c.caller===ws||c.accepted===ws){if(!c.accepted){finish(c,'disconnected');continue;}c.reconnects ||= new Map();if(c.reconnects.has(ws.userId))continue;const timer=setTimeout(()=>finish(c,'disconnected'),45000);timer.unref?.();c.reconnects.set(ws.userId,timer);for(const other of new Set([c.caller,c.accepted]))if(other!==ws)send(other,{type:'call-reconnecting',callId:c.id});}else if(c.targets.has(ws)){c.targets.delete(ws);if(!c.targets.size&&!c.pushed&&!c.accepted){social.recordCallEvent?.(c.caller.userId,c.targetId,c.mode,'missed');finish(c,'unavailable');}}}
 function enforce(){for(const c of calls.values())if(!social.authenticate(c.caller.authRequest)||social.blocked(c.caller.userId,c.targetId)||!social.user(c.targetId)||social.user(c.targetId).suspended||(c.accepted&&!social.authenticate(c.accepted.authRequest)))finish(c,'unavailable');}
 function handle(ws,m){
  if(!String(m.type).startsWith('call-'))return false;
  if(m.type==='call-start'){
   const u=social.user(m.to),targets=peers(m.to).filter(p=>p!==ws&&!p.room);
   const reject=reason=>send(ws,{type:'call-ended',requestId:m.requestId,reason});
   if(ws.room||!u||u.suspended||m.to===ws.userId||social.blocked(ws.userId,m.to)){reject('unavailable');return true;}
   const pushable=!!webPush?.has(m.to);
   if(!targets.length&&!pushable){social.recordCallEvent?.(ws.userId,m.to,m.mode,'missed');reject('unavailable');return true;}
   if(busy(ws.userId)||busy(m.to)){reject('busy');return true;}
   const c={id:randomUUID(),caller:ws,targetId:m.to,targets:new Set(targets),accepted:null,mode:m.mode==='audio'?'audio':'video'};calls.set(c.id,c);c.timeout=setTimeout(()=>{social.recordCallEvent?.(c.caller.userId,c.targetId,c.mode,'missed');finish(c,'missed');},45000);c.timeout.unref();
   send(ws,{type:'call-ringing',callId:c.id,requestId:m.requestId});const from=social.user(ws.userId);for(const p of targets)send(p,{type:'call-incoming',callId:c.id,mode:c.mode,from:{id:from.id,name:from.name}});
   if(pushable&&!visible(m.to)){c.pushed=true;webPush.call(m.to,c,from);}return true;
  }
  const c=calls.get(m.callId);if(!c)return true;
  if(m.type==='call-resume'){
   if(ws.room||!c.reconnects?.has(ws.userId)||![c.caller.userId,c.targetId].includes(ws.userId)||!social.authenticate(ws.authRequest)||social.blocked(c.caller.userId,c.targetId))return true;
   clearTimeout(c.reconnects.get(ws.userId));c.reconnects.delete(ws.userId);
   if(ws.userId===c.caller.userId)c.caller=ws;else{c.targets.delete(c.accepted);c.accepted=ws;c.targets.add(ws);}
   if(!c.reconnects.size)for(const endpoint of [c.caller,c.accepted])send(endpoint,{type:'call-resumed',callId:c.id});return true;
  }
  if(c.caller!==ws&&!c.targets.has(ws))return true;
  if(social.blocked(c.caller.userId,c.targetId)){finish(c,'unavailable');return true;}
  if(m.type==='call-end'){finish(c,'ended');return true;}
  if(m.type==='call-decline'&&c.targets.has(ws)&&!c.accepted){social.recordCallEvent?.(c.caller.userId,c.targetId,c.mode,'declined');finish(c,'declined');return true;}
  if(m.type==='call-accept'&&c.targets.has(ws)&&!c.accepted){c.accepted=ws;c.acceptedAt=Date.now();clearTimeout(c.timeout);if(c.pushed){c.pushed=false;webPush.callEnded(c.targetId,c,'answered',social.user(c.caller.userId));}for(const p of c.targets)if(p!==ws)send(p,{type:'call-ended',callId:c.id,reason:'answered_elsewhere'});c.targets=new Set([ws]);send(c.caller,{type:'call-accepted',callId:c.id});send(ws,{type:'call-accepted',callId:c.id});return true;}
  if(m.type==='call-signal'&&c.accepted){const target=ws===c.caller?c.accepted:c.caller;if(!social.authenticate(target.authRequest)){finish(c,'unavailable');return true;}if(m.description&&['offer','answer'].includes(m.description.type)&&typeof m.description.sdp==='string'&&m.description.sdp.length<24000)send(target,{type:'call-signal',callId:c.id,description:m.description});else if(m.candidate&&typeof m.candidate==='object')send(target,{type:'call-signal',callId:c.id,candidate:m.candidate});}
  return true;
 }
 // A tab opened from the call notification connects after the call started: let it ring too.
 function join(ws){for(const c of calls.values())if(c.targetId===ws.userId&&!c.accepted&&!c.targets.has(ws)&&!social.blocked(c.caller.userId,c.targetId)){c.targets.add(ws);const from=social.user(c.caller.userId);send(ws,{type:'call-incoming',callId:c.id,mode:c.mode,from:{id:from.id,name:from.name}});}}
 // "Từ chối" pressed on a push notification (no socket involved).
 function declineById(userId,callId){const c=calls.get(callId);if(!c||c.targetId!==userId||c.accepted)return;social.recordCallEvent?.(c.caller.userId,c.targetId,c.mode,'declined');c.pushed=false;finish(c,'declined');}
 return {handle,disconnect,enforce,join,declineById};
}
