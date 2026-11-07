import {WebSocket} from 'ws';
export function createTyping({social,wss,send}) {
 const recipients=(sender,kind,targetId)=>{
  if(kind==='direct') {const target=social.user(targetId);return target&&target.id!==sender&&!target.suspended&&!social.blocked(sender,target.id)?[target.id]:[];}
  if(kind!=='group'||!social.db.prepare('SELECT 1 FROM group_members WHERE group_id=? AND user_id=?').get(targetId,sender))return [];
  return social.db.prepare('SELECT user_id FROM group_members WHERE group_id=? AND user_id<>?').all(targetId,sender).map(r=>r.user_id).filter(id=>{const user=social.user(id);return user&&!user.suspended&&!social.blocked(sender,id);});
 };
 function publish(ws,account,kind,targetId,typing){
  const allowed=new Set(recipients(account.id,kind,targetId));
  for(const peer of wss.clients)if(peer.readyState===WebSocket.OPEN&&allowed.has(peer.userId)&&social.authenticate(peer.authRequest))send(peer,{type:'chat-typing',kind,conversationId:kind==='direct'?account.id:targetId,userId:account.id,name:account.name,typing});
 }
 return {
  handle(ws,message,account){
   if(message.type!=='chat-typing')return false;
   const {kind,targetId,typing}=message;if(!['direct','group'].includes(kind)||typeof targetId!=='string'||targetId.length>80||typeof typing!=='boolean')return true;
   const previous=ws.typingState;
   if(previous&&(previous.kind!==kind||previous.targetId!==targetId))publish(ws,account,previous.kind,previous.targetId,false);
   const now=Date.now();if(typing&&previous?.kind===kind&&previous.targetId===targetId&&now-previous.sentAt<700)return true;
   publish(ws,account,kind,targetId,typing);ws.typingState=typing?{kind,targetId,sentAt:now}:null;return true;
  },
  disconnect(ws){const account=social.authenticate(ws.authRequest);if(account&&ws.typingState){const {kind,targetId}=ws.typingState;publish(ws,account,kind,targetId,false);}ws.typingState=null;}
 };
}
