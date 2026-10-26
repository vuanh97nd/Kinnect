import {randomUUID} from 'node:crypto';
export function createCalls({social,wss,send}){
 const calls=new Map();
 const peers=(id)=>[...wss.clients].filter(ws=>ws.userId===id&&social.authenticate(ws.authRequest));
 const busy=id=>[...calls.values()].some(c=>c.caller.userId===id||c.targetId===id);
 function finish(c,reason){if(!calls.delete(c.id))return;clearTimeout(c.timeout);for(const ws of new Set([c.caller,...c.targets]))send(ws,{type:'call-ended',callId:c.id,reason});}
 function disconnect(ws){for(const c of calls.values())if(c.caller===ws||c.accepted===ws)finish(c,'disconnected');else if(c.targets.has(ws)){c.targets.delete(ws);if(!c.targets.size){social.recordCallEvent?.(c.caller.userId,c.targetId,c.mode,'missed');finish(c,'unavailable');}}}
 function enforce(){for(const c of calls.values())if(!social.authenticate(c.caller.authRequest)||social.blocked(c.caller.userId,c.targetId)||!social.user(c.targetId)||social.user(c.targetId).suspended||(c.accepted&&!social.authenticate(c.accepted.authRequest)))finish(c,'unavailable');}
 function handle(ws,m){
  if(!String(m.type).startsWith('call-'))return false;
  if(m.type==='call-start'){
   const u=social.user(m.to),targets=peers(m.to).filter(p=>p!==ws&&!p.room);
   const reject=reason=>send(ws,{type:'call-ended',requestId:m.requestId,reason});
   if(ws.room||!u||u.suspended||m.to===ws.userId||social.blocked(ws.userId,m.to)){reject('unavailable');return true;}
   if(!targets.length){social.recordCallEvent?.(ws.userId,m.to,m.mode,'missed');reject('unavailable');return true;}
   if(busy(ws.userId)||busy(m.to)){reject('busy');return true;}
   const c={id:randomUUID(),caller:ws,targetId:m.to,targets:new Set(targets),accepted:null,mode:m.mode==='audio'?'audio':'video'};calls.set(c.id,c);c.timeout=setTimeout(()=>{social.recordCallEvent?.(c.caller.userId,c.targetId,c.mode,'missed');finish(c,'missed');},45000);c.timeout.unref();
   send(ws,{type:'call-ringing',callId:c.id,requestId:m.requestId});const from=social.user(ws.userId);for(const p of targets)send(p,{type:'call-incoming',callId:c.id,mode:c.mode,from:{id:from.id,name:from.name}});return true;
  }
  const c=calls.get(m.callId);if(!c)return true;
  if(c.caller!==ws&&!c.targets.has(ws))return true;
  if(social.blocked(c.caller.userId,c.targetId)){finish(c,'unavailable');return true;}
  if(m.type==='call-end'){finish(c,'ended');return true;}
  if(m.type==='call-decline'&&c.targets.has(ws)&&!c.accepted){social.recordCallEvent?.(c.caller.userId,c.targetId,c.mode,'declined');finish(c,'declined');return true;}
  if(m.type==='call-accept'&&c.targets.has(ws)&&!c.accepted){c.accepted=ws;clearTimeout(c.timeout);for(const p of c.targets)if(p!==ws)send(p,{type:'call-ended',callId:c.id,reason:'answered_elsewhere'});c.targets=new Set([ws]);send(c.caller,{type:'call-accepted',callId:c.id});send(ws,{type:'call-accepted',callId:c.id});return true;}
  if(m.type==='call-signal'&&c.accepted){const target=ws===c.caller?c.accepted:c.caller;if(!social.authenticate(target.authRequest)){finish(c,'unavailable');return true;}if(m.description&&['offer','answer'].includes(m.description.type)&&typeof m.description.sdp==='string'&&m.description.sdp.length<24000)send(target,{type:'call-signal',callId:c.id,description:m.description});else if(m.candidate&&typeof m.candidate==='object')send(target,{type:'call-signal',callId:c.id,candidate:m.candidate});}
  return true;
 }
 return {handle,disconnect,enforce};
}
