// Supported modes: Chat and Game only. Legacy karaoke requests normalize to chat.
export const liveMode=value=>value==='game'?'game':'chat';
export function createLiveModes({send,social}){
 function init(room,m){room.mode=liveMode(m.liveMode);room.gameTitle=room.mode==='game'?String(m.gameTitle??'').replace(/[\u0000-\u001f]/g,'').trim().slice(0,60):'';room.screenPaused=false;}
 function state(room,target){const data={type:'live-mode-state',room:room.id,liveMode:room.mode,gameTitle:room.gameTitle,screenPaused:!!room.screenPaused};for(const peer of target?[target]:room.members.values())if(peer&&!social.blocked(peer.userId,room.host.userId))send(peer,data);}
 function handle(room,ws,m){if(m.type?.startsWith('sing-')){send(ws,{type:'live-mode-error',room:room.id,message:'Karaoke đã được gỡ. Chọn Trò chuyện hoặc Chơi game.'});return true;}if(m.type==='live-mode-get'){state(room,ws);return true;}if(m.type!=='live-game-state')return false;if(ws!==room.host||room.mode!=='game'){send(ws,{type:'live-mode-error',room:room.id,message:'Chỉ chủ phòng game được điều khiển màn hình.'});return true;}room.screenPaused=m.paused===true;state(room);return true;}
 return {init,state,handle,left:state,reconcile:state};
}
