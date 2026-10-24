import {sendCallSignal} from './app.js';
let current=null;
const labels={busy:'Người này đang bận.',unavailable:'Người này chưa sẵn sàng nhận cuộc gọi.',missed:'Không có trả lời.',declined:'Cuộc gọi đã bị từ chối.',ended:'Cuộc gọi đã kết thúc.',disconnected:'Mất kết nối cuộc gọi.',answered_elsewhere:'Đã nhận trên thiết bị khác.'};
function send(c,type,extra={}){sendCallSignal({type,callId:c.id,...extra});}
function finish(c,message='Cuộc gọi đã kết thúc.'){if(current!==c)return;current=null;clearTimeout(c.timeout);clearInterval(c.clock);c.pc?.close();c.stream?.getTracks().forEach(t=>t.stop());c.dialog.close();c.dialog.remove();window.dispatchEvent(new CustomEvent('kinnect-call-status',{detail:message}));}
function shell(person,incoming=false,mode="video"){
 const dialog=document.createElement('dialog');dialog.className='video-call';dialog.setAttribute('aria-label',mode==='audio'?'Cuộc gọi thoại':'Cuộc gọi video');if(mode==='audio')dialog.classList.add('audio-call');
 dialog.innerHTML='<video class="call-remote" autoplay playsinline></video><video class="call-local" autoplay playsinline muted></video><div class="call-identity"><div class="call-avatar"></div><h2></h2><p role="status"></p></div><button class="call-audio" hidden>Bật âm thanh</button><div class="call-controls"><button type="button" class="call-mic">Tắt mic</button><button type="button" class="call-camera">Tắt camera</button><button type="button" class="call-accept">Nhận cuộc gọi</button><button type="button" class="call-end">Kết thúc</button></div>';
 dialog.querySelector('h2').textContent=person.name;dialog.querySelector('.call-avatar').textContent=(person.name||'K').slice(0,1).toUpperCase();
 document.body.append(dialog);dialog.showModal();
 const c={dialog,person,incoming,mode,id:null,requestId:crypto.randomUUID(),pending:[],stream:null,pc:null};current=c;
 c.status=dialog.querySelector('[role=status]');c.status.textContent=incoming?(mode==='audio'?'Cuộc gọi thoại đến':'Cuộc gọi video đến'):(mode==='audio'?'Đang chuẩn bị micro…':'Đang chuẩn bị camera…');
 for(const selector of ['.call-mic','.call-camera'])dialog.querySelector(selector).hidden=incoming;
 dialog.querySelector('.call-accept').hidden=!incoming;
 const end=dialog.querySelector('.call-end');end.textContent=incoming?'Từ chối':'Kết thúc';
 end.onclick=()=>{try{if(c.id)send(c,incoming&&!c.pc?'call-decline':'call-end');}catch{}finish(c);};
 dialog.addEventListener('cancel',e=>{e.preventDefault();end.click();});
 dialog.querySelector('.call-accept').onclick=async()=>{const accept=dialog.querySelector('.call-accept');accept.disabled=true;try{await media(c);if(current!==c)return;send(c,'call-accept');accept.hidden=true;end.textContent='Kết thúc';for(const sel of ['.call-mic','.call-camera'])dialog.querySelector(sel).hidden=false;c.status.textContent='Đang kết nối…';}catch(e){try{send(c,'call-decline');}catch{}finish(c,e.message);}};
 dialog.querySelector('.call-mic').onclick=e=>{const tracks=c.stream?.getAudioTracks()||[];const enabled=!tracks[0]?.enabled;tracks.forEach(t=>t.enabled=enabled);e.currentTarget.textContent=enabled?'Tắt mic':'Bật mic';e.currentTarget.setAttribute('aria-pressed',String(!enabled));};
 dialog.querySelector('.call-camera').onclick=e=>{const tracks=c.stream?.getVideoTracks()||[];const enabled=!tracks[0]?.enabled;tracks.forEach(t=>t.enabled=enabled);e.currentTarget.textContent=enabled?'Tắt camera':'Bật camera';e.currentTarget.setAttribute('aria-pressed',String(!enabled));};
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
 const response=await fetch('/api/call-config',{credentials:'same-origin'});if(!response.ok)throw Error('Không tải được cấu hình cuộc gọi.');const config=await response.json();if(current!==c)return null;
 const pc=new RTCPeerConnection(config);c.pc=pc;c.stream.getTracks().forEach(t=>pc.addTrack(t,c.stream));
 pc.onicecandidate=e=>{if(e.candidate&&current===c)try{send(c,'call-signal',{candidate:e.candidate.toJSON()});}catch{finish(c,'Mất kết nối cuộc gọi.');}};
 pc.ontrack=e=>{const remote=c.dialog.querySelector('.call-remote');remote.srcObject=e.streams[0];remote.play().catch(()=>c.dialog.querySelector('.call-audio').hidden=false);c.dialog.classList.add('has-remote');};
 pc.onconnectionstatechange=()=>{if(current!==c)return;if(pc.connectionState==='connected'){clearTimeout(c.timeout);const started=Date.now();c.clock=setInterval(()=>{const seconds=Math.floor((Date.now()-started)/1000);c.status.textContent=String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0');},1000);c.status.textContent='Đã kết nối';}if(['failed','closed'].includes(pc.connectionState)){try{send(c,'call-end');}catch{}finish(c,'Chưa kết nối được video. Hãy thử lại với mạng khác.');}};
 c.timeout=setTimeout(()=>{if(current===c&&pc.connectionState!=='connected'){try{send(c,'call-end');}catch{}finish(c,'Kết nối quá thời gian. Vui lòng thử lại.');}},30000);
 return pc;
}
export async function startVideoCall(person,mode="video"){if(current)throw Error('Bạn đang có một cuộc gọi.');const c=shell(person,false,mode);try{await media(c);if(current!==c)return;sendCallSignal({type:'call-start',to:person.id,mode,requestId:c.requestId});c.status.textContent='Đang gọi…';}catch(e){finish(c,e.message);}}
export function endVideoCall(){const c=current;if(!c)return;try{if(c.id)send(c,'call-end');}catch{}finish(c);}
window.addEventListener('kinnect-call-event',async event=>{
 const m=event.detail;
 if(m.type==='call-incoming'){if(current){try{sendCallSignal({type:'call-decline',callId:m.callId});}catch{}return;}const c=shell(m.from,true,m.mode);c.id=m.callId;return;}
 const c=current;if(!c){if(m.type==='call-ringing')try{sendCallSignal({type:'call-end',callId:m.callId});}catch{}return;}
 if(m.type==='call-ringing'&&m.requestId===c.requestId){c.id=m.callId;c.status.textContent='Đang đổ chuông…';return;}
 if(m.type==='call-ended'&&((m.callId&&m.callId===c.id)||(m.requestId&&m.requestId===c.requestId))){finish(c,labels[m.reason]||labels.ended);return;}
 if(m.callId!==c.id)return;
 try{
  if(m.type==='call-accepted'){const pc=await connection(c);if(!pc)return;if(!c.incoming){await pc.setLocalDescription(await pc.createOffer());send(c,'call-signal',{description:pc.localDescription.toJSON()});}}
  if(m.type==='call-signal'){const pc=await connection(c);if(!pc)return;if(m.description){await pc.setRemoteDescription(m.description);for(const candidate of c.pending)await pc.addIceCandidate(candidate);c.pending=[];if(m.description.type==='offer'){await pc.setLocalDescription(await pc.createAnswer());send(c,'call-signal',{description:pc.localDescription.toJSON()});}}else if(m.candidate){if(pc.remoteDescription)await pc.addIceCandidate(m.candidate);else c.pending.push(m.candidate);}}
 }catch{try{send(c,'call-end');}catch{}finish(c,'Không thể kết nối cuộc gọi. Vui lòng thử lại.');}
});
window.addEventListener('kinnect-call-disconnected',()=>{if(current)finish(current,'Mất kết nối cuộc gọi.');});
window.addEventListener('pagehide',endVideoCall);
