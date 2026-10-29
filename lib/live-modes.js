// Only room metadata/control travels over signalling; audio is mixed on the sender.
export const liveMode = value => ['chat','karaoke','game'].includes(value) ? value : 'chat';
export function createLiveModes({send,social,listing}) {
 const cleanText=(v,n)=>String(v??'').replace(/[\u0000-\u0008\u000b-\u001f]/g,'').trim().slice(0,n);
 function init(room,m){room.mode=liveMode(m.liveMode);room.gameTitle=room.mode==='game'?cleanText(m.gameTitle,60):'';room.karaoke={singerId:room.host.id,title:'',lines:[],playing:false,positionMs:0,durationMs:0,updatedAt:Date.now(),revision:0};room.singQueue=new Map();}
 function snapshot(room){const k=room.karaoke;return {type:'live-mode-state',room:room.id,liveMode:room.mode,gameTitle:room.gameTitle,screenPaused:!!room.screenPaused,serverNow:Date.now(),karaoke:{...k,singerName:room.members.get(k.singerId)?.name||'',queue:[...room.singQueue].filter(([id])=>room.members.has(id)).map(([id,title])=>({id,name:room.members.get(id).name,title}))}};}
 function state(room,target){const data=snapshot(room);for(const peer of target?[target]:room.members.values())if(peer&&!social.blocked(peer.userId,room.host.userId))send(peer,data);}
 function reset(room,singerId=room.host.id){const revision=room.karaoke.revision+1;room.karaoke={singerId,title:'',lines:[],playing:false,positionMs:0,durationMs:0,updatedAt:Date.now(),revision};}
 function left(room,peer){room.singQueue.delete(peer.id);if(room.karaoke.singerId===peer.id)reset(room);state(room);}
 function reconcile(room){if(room.karaoke.singerId!==room.host.id&&!room.guests.has(room.karaoke.singerId))reset(room);for(const [id]of room.singQueue)if(!room.members.has(id)||social.blocked(room.host.userId,room.members.get(id).userId))room.singQueue.delete(id);state(room);}
 function handle(room,ws,m){if(!['live-mode-get','live-game-state','sing-request','sing-cancel','sing-select','sing-remove','sing-track','sing-transport'].includes(m.type))return false;
  try{
   if(m.type==='live-mode-get'){state(room,ws);return true;}
   if(m.type==='live-game-state'){if(ws!==room.host||room.mode!=='game')throw Error('Chỉ chủ phòng game được điều khiển màn hình.');room.screenPaused=m.paused===true;state(room);return true;}
   if(room.mode!=='karaoke')throw Error('Phòng này chưa bật hát karaoke.');
   if(m.type==='sing-request'){if(ws===room.host)return true;if(!ws.liveModes||!social.hasPrivacyConsent(ws.userId))throw Error('Cần cập nhật ứng dụng và đồng ý thông báo dữ liệu để xin hát.');if(!room.singQueue.has(ws.id)&&room.singQueue.size>=6)throw Error('Hàng chờ đã đầy.');room.singQueue.set(ws.id,cleanText(m.title,80));}
   if(m.type==='sing-cancel')room.singQueue.delete(ws.id);
   if(m.type==='sing-remove'){if(ws!==room.host)throw Error('Chỉ chủ phòng được quản lý hàng chờ.');room.singQueue.delete(m.to);}
   if(m.type==='sing-select'){if(ws!==room.host)throw Error('Chỉ chủ phòng được chuyển lượt hát.');const target=room.members.get(m.to);if(!target||!target.liveModes||target!==room.host&&!room.guests.has(target.id)||social.blocked(ws.userId,target.userId))throw Error('Mời người này lên Live và chờ họ đồng ý trước khi chuyển lượt.');reset(room,target.id);room.singQueue.delete(target.id);}
   if(m.type==='sing-track'||m.type==='sing-transport'){
    if(ws.id!==room.karaoke.singerId||ws!==room.host&&!room.guests.has(ws.id))throw Error('Chỉ người đang đến lượt được phát nhạc.');
    const k=room.karaoke;
    if(m.type==='sing-track'){
     if(!Number.isFinite(m.durationMs)||m.durationMs<1000||m.durationMs>600000)throw Error('Nhạc nền phải dài từ 1 giây đến 10 phút.');
     if(!Array.isArray(m.lines)||m.lines.length>500)throw Error('Lời bài hát quá dài.');let last=-1;
     const lines=m.lines.map(line=>{if(!line||typeof line!=='object'||!Number.isFinite(line.at)||line.at<0||line.at>m.durationMs||line.at<last)throw Error('Mốc lời không hợp lệ.');last=line.at;return {at:Math.round(line.at),text:cleanText(line.text,180)};});
     if(JSON.stringify(lines).length>40000)throw Error('Lời bài hát quá dài.');
     Object.assign(k,{title:cleanText(m.title,80)||'Karaoke',durationMs:Math.round(m.durationMs),lines,positionMs:0,playing:false});k.revision++;
    }else{if(m.revision!==k.revision)throw Error('Bài hát đã thay đổi.');if(!Number.isFinite(m.positionMs))throw Error('Vị trí không hợp lệ.');k.positionMs=Math.max(0,Math.min(k.durationMs,Math.round(m.positionMs)));k.playing=m.playing===true&&k.positionMs<k.durationMs;}
    k.updatedAt=Date.now();
   }
   state(room);
  }catch(e){send(ws,{type:'live-mode-error',room:room.id,message:e.message});}return true;
 }
 return {init,state,handle,left,reconcile};
}
