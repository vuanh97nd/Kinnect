import {sendCallSignal} from './app.js';
let current=null;
const callIcons={"mic":"<svg viewBox=\"0 0 24 24\" aria-hidden=\"true\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"9\" y=\"2\" width=\"6\" height=\"12\" rx=\"3\"/><path d=\"M5 10v2a7 7 0 0014 0v-2M12 19v3m-4 0h8\"/></svg>","camera":"<svg viewBox=\"0 0 24 24\" aria-hidden=\"true\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"3\" y=\"5\" width=\"12\" height=\"14\" rx=\"3\"/><path d=\"m15 10 6-4v12l-6-4\"/></svg>","phone":"<svg viewBox=\"0 0 24 24\" aria-hidden=\"true\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M7 3H4a1 1 0 00-1 1c0 9.4 7.6 17 17 17a1 1 0 001-1v-3l-5-2-2 2a14 14 0 01-7-7l2-2-2-5Z\"/></svg>","expand":"<svg viewBox=\"0 0 24 24\" aria-hidden=\"true\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5\"/></svg>"};
function callButton(button,label,icon){button.innerHTML=callIcons[icon]+'<span></span>';button.querySelector('span').textContent=label;button.setAttribute('aria-label',label);button.title=label;}

function stopRingtone(c){clearInterval(c.ringtone);c.ringtone=null;try{c.toneOscillators?.forEach(o=>{try{o.stop()}catch{}})}catch{}c.toneOscillators=[];}
function ring(c){
 stopRingtone(c);
 const Audio=window.AudioContext||window.webkitAudioContext;if(!Audio)return;
 try{const ctx=new Audio();c.ringtoneContext=ctx;const pulse=()=>{if(current!==c||!c.incoming)return;try{const osc=ctx.createOscillator(),gain=ctx.createGain();osc.type='sine';osc.frequency.value=880;gain.gain.setValueAtTime(.0001,ctx.currentTime);gain.gain.exponentialRampToValueAtTime(.14,ctx.currentTime+.04);gain.gain.setValueAtTime(.14,ctx.currentTime+.22);gain.gain.exponentialRampToValueAtTime(.0001,ctx.currentTime+.28);osc.connect(gain);gain.connect(ctx.destination);osc.start();osc.stop(ctx.currentTime+.3);(c.toneOscillators||(c.toneOscillators=[])).push(osc);}catch{}};pulse();c.ringtone=setInterval(pulse,1100);}catch{}
}
function callSystemAlert(c){if(document.visibilityState==='visible'||!('Notification'in window)||Notification.permission!=='granted')return;try{const n=new Notification(c.mode==='audio'?'Cuộc gọi thoại đến':'Cuộc gọi video đến',{body:c.person.name,icon:'/kinnect-logo-v106.svg',tag:'kinnect-call-'+c.id,requireInteraction:true});n.onclick=()=>{window.focus();n.close();};c.systemNotification=n;}catch{}}
const labels={busy:'Người này đang bận.',unavailable:'Người này chưa sẵn sàng nhận cuộc gọi.',missed:'Không có trả lời.',declined:'Cuộc gọi đã bị từ chối.',ended:'Cuộc gọi đã kết thúc.',disconnected:'Mất kết nối cuộc gọi.',answered_elsewhere:'Đã nhận trên thiết bị khác.'};
function send(c,type,extra={}){sendCallSignal({type,callId:c.id,...extra});}
function finish(c,message='Cuộc gọi đã kết thúc.'){if(current!==c)return;stopRingtone(c);c.ringtoneContext?.close().catch(()=>{});c.systemNotification?.close();current=null;c.configRequest?.abort();clearTimeout(c.timeout);clearTimeout(c.recoveryTimer);clearInterval(c.clock);c.pc?.close();c.stream?.getTracks().forEach(t=>t.stop());c.dialog.close();c.dialog.remove();window.dispatchEvent(new CustomEvent('kinnect-call-status',{detail:message}));}
function shell(person,incoming=false,mode="video"){
 const dialog=document.createElement('dialog');dialog.className='video-call';dialog.setAttribute('aria-label',mode==='audio'?'Cuộc gọi thoại':'Cuộc gọi video');if(mode==='audio')dialog.classList.add('audio-call');
 dialog.innerHTML='<div class="call-topline"><span class="call-wordmark">Kinnect<span>CALL</span></span><button type="button" class="call-expand" aria-label="Toàn màn hình"></button></div><video class="call-remote" autoplay playsinline></video><video class="call-local" autoplay playsinline muted></video><div class="call-identity"><div class="call-avatar"></div><h2></h2><p role="status"></p></div><button class="call-audio" hidden>Bật âm thanh</button><div class="call-controls"><button type="button" class="call-mic">Tắt mic</button><button type="button" class="call-camera">Tắt camera</button><button type="button" class="call-output">Âm thanh</button><button type="button" class="call-accept">Nhận cuộc gọi</button><button type="button" class="call-end">Kết thúc</button></div>';
 dialog.querySelector('h2').textContent=person.name;dialog.querySelector('.call-avatar').textContent=(person.name||'K').slice(0,1).toUpperCase();
 if(person.avatar){const img=document.createElement('img');img.src=person.avatar;img.alt='';img.onerror=()=>img.remove();dialog.querySelector('.call-avatar').append(img);}
 for(const [selector,label,icon] of [['.call-mic','Tắt mic','mic'],['.call-camera','Tắt camera','camera'],['.call-accept','Nhận cuộc gọi','phone'],['.call-expand','Toàn màn hình','expand']])callButton(dialog.querySelector(selector),label,icon);
 dialog.querySelector('.call-accept span').textContent='Trả lời';
 const output=dialog.querySelector('.call-output');output.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4V5Z"/><path d="M15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/></svg><span>Âm thanh</span>';output.setAttribute('aria-label','Chọn loa và âm thanh');
 dialog.querySelector('.call-expand').onclick=async()=>{try{if(document.fullscreenElement===dialog)await document.exitFullscreen();else await dialog.requestFullscreen();}catch{dialog.classList.toggle('call-maximized');}};
 dialog.classList.toggle('is-incoming',incoming);
 document.body.append(dialog);dialog.showModal();
 const c={dialog,person,incoming,mode,id:null,requestId:crypto.randomUUID(),pending:[],stream:null,pc:null};current=c;
 c.status=dialog.querySelector('[role=status]');c.status.textContent=incoming?(mode==='audio'?'Cuộc gọi thoại đến':'Cuộc gọi video đến'):(mode==='audio'?'Đang chuẩn bị micro…':'Đang chuẩn bị camera…');
 for(const selector of ['.call-mic','.call-camera'])dialog.querySelector(selector).hidden=incoming;
 dialog.querySelector('.call-accept').hidden=!incoming;
 const end=dialog.querySelector('.call-end');callButton(end,incoming?'Từ chối':'Kết thúc','phone');
 end.onclick=()=>{try{if(c.id)send(c,c.incoming&&!c.accepted?'call-decline':'call-end');}catch{}finish(c);};
 dialog.addEventListener('cancel',e=>{e.preventDefault();end.click();});
 dialog.querySelector('.call-accept').onclick=async()=>{stopRingtone(c);c.ringtoneContext?.close().catch(()=>{});c.systemNotification?.close();const accept=dialog.querySelector('.call-accept');accept.disabled=true;try{await media(c);if(current!==c)return;send(c,'call-accept');c.accepted=true;accept.hidden=true;dialog.classList.remove('is-incoming');callButton(end,'Kết thúc','phone');for(const sel of ['.call-mic','.call-camera'])dialog.querySelector(sel).hidden=false;c.status.textContent='Đang kết nối…';}catch(e){try{send(c,'call-decline');}catch{}finish(c,e.message);}};
 dialog.querySelector('.call-mic').onclick=e=>{const tracks=c.stream?.getAudioTracks()||[];const enabled=!tracks[0]?.enabled;tracks.forEach(t=>t.enabled=enabled);callButton(e.currentTarget,enabled?'Tắt mic':'Bật mic','mic');e.currentTarget.setAttribute('aria-pressed',String(!enabled));};
 dialog.querySelector('.call-camera').onclick=e=>{const tracks=c.stream?.getVideoTracks()||[];const enabled=!tracks[0]?.enabled;tracks.forEach(t=>t.enabled=enabled);callButton(e.currentTarget,enabled?'Tắt camera':'Bật camera','camera');c.dialog.classList.toggle('camera-muted',!enabled);e.currentTarget.setAttribute('aria-pressed',String(!enabled));};
 output.onclick=async()=>{
  const remote=dialog.querySelector('.call-remote');
  try{
   if(navigator.mediaDevices?.selectAudioOutput&&remote.setSinkId){const device=await navigator.mediaDevices.selectAudioOutput();if(current!==c)return;await remote.setSinkId(device.deviceId);output.querySelector('span').textContent=device.label||'Đã chọn loa';}
   else{await remote.play().catch(()=>{});window.alert('Âm thanh phát qua thiết bị đang được điện thoại hoặc trình duyệt chọn. Để đổi sang loa ngoài, tai nghe hoặc Bluetooth, mở bảng điều khiển âm thanh của thiết bị. Trình duyệt này chưa hỗ trợ chọn loa trực tiếp trong web.');}
  }catch(e){if(e.name!=='NotAllowedError'&&e.name!=='AbortError')window.alert('Chưa đổi được thiết bị âm thanh. Hãy kiểm tra quyền và thử lại.');}
 };
 dialog.querySelector('.call-audio').onclick=async e=>{try{await dialog.querySelector('.call-remote').play();e.currentTarget.hidden=true;}catch{}};
 return c;
}
async function media(c){
 if(!navigator.mediaDevices?.getUserMedia)throw Error('Trình duyệt chưa hỗ trợ camera. Hãy mở Kinnect bằng HTTPS.');
 let stream;try{stream=await navigator.mediaDevices.getUserMedia({video:c.mode==='audio'?false:{facingMode:'user',width:{ideal:640},height:{ideal:480}},audio:true});}catch{throw Error('Chưa mở được camera và micro. Kiểm tra quyền truy cập rồi thử lại.');}
 if(current!==c){stream.getTracks().forEach(t=>t.stop());return;}c.stream=stream;const local=c.dialog.querySelector('.call-local');local.muted=true;local.srcObject=stream;local.play().catch(()=>{});
}
function connection(c){return c.connecting||(c.connecting=createConnection(c));}
async function createConnection(c){
 if(c.pc)return c.pc;
 c.status.textContent='Đang kết nối…';
 c.configRequest=new AbortController();
 // Cover configuration loading as well as ICE with the same deadline.
 c.timeout=setTimeout(()=>{if(current===c){try{send(c,'call-end');}catch{}finish(c,'Kết nối cuộc gọi quá thời gian. Vui lòng thử lại.');}},30000);
 const response=await fetch('/api/call-config',{credentials:'same-origin',signal:c.configRequest.signal});const config=await response.json().catch(()=>null);if(!response.ok||!config)throw Error(config?.error||'Không tải được cấu hình cuộc gọi.');if(current!==c)return null;c.turnConfigured=(config.iceServers||[]).some(server=>(Array.isArray(server.urls)?server.urls:[server.urls]).some(url=>typeof url==='string'&&/^turns?:/i.test(url)));
 const pc=new RTCPeerConnection(config);c.pc=pc;c.stream.getTracks().forEach(t=>pc.addTrack(t,c.stream));
 pc.onicecandidate=e=>{if(e.candidate&&current===c)try{send(c,'call-signal',{candidate:e.candidate.toJSON()});}catch{finish(c,'Mất kết nối cuộc gọi.');}};
 pc.ontrack=e=>{const remote=c.dialog.querySelector('.call-remote');remote.srcObject=e.streams[0]||new MediaStream([e.track]);remote.play().catch(()=>c.dialog.querySelector('.call-audio').hidden=false);c.dialog.classList.add('has-remote');};
 pc.onconnectionstatechange=()=>{if(current!==c)return;c.dialog.classList.toggle('is-connected',pc.connectionState==='connected');if(pc.connectionState==='connected'){clearTimeout(c.recoveryTimer);c.recoveryTimer=null;clearTimeout(c.timeout);clearInterval(c.clock);const started=Date.now();c.clock=setInterval(()=>{const seconds=Math.floor((Date.now()-started)/1000);c.status.textContent=String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0');},1000);c.status.textContent='Đã kết nối';}if(pc.connectionState==='disconnected'||pc.connectionState==='failed'){
  c.status.textContent='Đang khôi phục kết nối…';
  if(!c.recoveryTimer)c.recoveryTimer=setTimeout(()=>{if(current===c&&pc.connectionState!=='connected'){try{send(c,'call-end');}catch{}finish(c,'Mất kết nối cuộc gọi. Hãy kiểm tra mạng rồi gọi lại.');}},15000);
  if(pc.connectionState==='failed'&&!c.incoming&&!c.iceRestarted){c.iceRestarted=true;c.signals=(c.signals||Promise.resolve()).then(async()=>{if(current!==c)return;await pc.setLocalDescription(await pc.createOffer({iceRestart:true}));send(c,'call-signal',{description:pc.localDescription.toJSON()});}).catch(()=>finish(c,'Không khôi phục được kết nối cuộc gọi.'));}
  return;
 }if(pc.connectionState==='closed'){try{send(c,'call-end');}catch{}finish(c,c.turnConfigured?'Không kết nối được cuộc gọi '+(c.mode==='audio'?'thoại':'video')+'. Hãy kiểm tra kết nối mạng rồi thử lại.':'Cuộc gọi '+(c.mode==='audio'?'thoại':'video')+' không xuyên được mạng này vì máy chủ chưa cấu hình TURN. Cần bật dịch vụ TURN cho Kinnect.');}};
 return pc;
}
export async function startVideoCall(person,mode="video"){if(current)throw Error('Bạn đang có một cuộc gọi.');const c=shell(person,false,mode);try{await media(c);if(current!==c)return;sendCallSignal({type:'call-start',to:person.id,mode,requestId:c.requestId});c.status.textContent='Đang gọi…';}catch(e){finish(c,e.message);}}
export function endVideoCall(){const c=current;if(!c)return;try{if(c.id)send(c,'call-end');}catch{}finish(c);}
window.addEventListener('kinnect-call-event',async event=>{
 const m=event.detail;
 if(m.type==='call-incoming'){if(current){try{sendCallSignal({type:'call-decline',callId:m.callId});}catch{}return;}const c=shell(m.from,true,m.mode);c.id=m.callId;ring(c);callSystemAlert(c);return;}
 const c=current;if(!c){if(m.type==='call-ringing')try{sendCallSignal({type:'call-end',callId:m.callId});}catch{}return;}
 if(m.type==='call-ringing'&&m.requestId===c.requestId){c.id=m.callId;c.status.textContent='Đang đổ chuông…';return;}
 if(m.type==='call-ended'&&((m.callId&&m.callId===c.id)||(m.requestId&&m.requestId===c.requestId))){finish(c,labels[m.reason]||labels.ended);return;}
 if(m.callId!==c.id)return;
 // Apply each SDP/ICE message fully before processing the next one.
 c.signals=(c.signals||Promise.resolve()).then(async()=>{
  if(current!==c)return;
  if(m.type==='call-accepted'){const pc=await connection(c);if(!pc)return;if(!c.incoming){await pc.setLocalDescription(await pc.createOffer());send(c,'call-signal',{description:pc.localDescription.toJSON()});}}
  if(m.type==='call-signal'){const pc=await connection(c);if(!pc)return;if(m.description){await pc.setRemoteDescription(m.description);for(const candidate of c.pending)await pc.addIceCandidate(candidate);c.pending=[];if(m.description.type==='offer'){await pc.setLocalDescription(await pc.createAnswer());send(c,'call-signal',{description:pc.localDescription.toJSON()});}}else if(m.candidate){if(pc.remoteDescription)await pc.addIceCandidate(m.candidate);else c.pending.push(m.candidate);}}
 }).catch(e=>{if(current!==c)return;try{send(c,'call-end');}catch{}finish(c,e.message||'Không thể kết nối cuộc gọi. Vui lòng thử lại.');});
});
window.addEventListener('kinnect-call-disconnected',()=>{if(current)finish(current,'Mất kết nối cuộc gọi.');});
window.addEventListener('pagehide',endVideoCall);
