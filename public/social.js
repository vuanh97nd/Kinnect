import {createFeed} from "./social-feed.js";
import {createDiscover} from "./social-discover.js";
import {createProfile} from "./social-profile.js";
import {createMessenger} from "./social-messenger.js";
import { connectLive, disconnectLive, joinLiveRoom, sendTypingSignal } from "./app.js?v=live2";
let callModule=null,callModuleLoading=null;
function loadVideoCalls(){return callModuleLoading||(callModuleLoading=import('./calls.js?v=live-call2').then(module=>{callModule=module;return module;}).catch(error=>{callModuleLoading=null;throw error;}));}
async function startVideoCall(user,mode="video"){const module=await loadVideoCalls();return module.startVideoCall(user,mode);}
function endVideoCall(){callModule?.endVideoCall();}
const REEL_ICONS = {
 heart: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>',
 comment: '<path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8v.5Z"/><path d="M8 11h.01M12 11h.01M16 11h.01"/>',
 share: '<path d="m15 3 7 7-7 7v-4c-6 0-9 2-13 7 1-8 5-12 13-12V3Z"/>',
 sound: '<path d="m11 5-6 4H2v6h3l6 4V5Z"/><path d="M15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
 muted: '<path d="m11 5-6 4H2v6h3l6 4V5Zm6 4 5 6m0-6-5 6"/>',
 more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
 close: '<path d="m6 6 12 12M6 18 18 6"/>',
 send: '<path d="m22 2-7 20-4-9-9-4 20-7ZM22 2 11 13"/>',
 live: '<path d="M3 6h12v12H3zM15 10l6-4v12l-6-4"/>'
};
function reelIcon(kind){return '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'+REEL_ICONS[kind]+'</svg>';}
let reelMuted = false;
try { reelMuted = localStorage.getItem("kinnect-video-muted") === "1"; } catch {}
const COMMENT_REACTIONS={like:['👍','Thích'],love:['❤️','Yêu thích'],haha:['😆','Haha'],wow:['😮','Wow'],sad:['😢','Buồn'],angry:['😠','Phẫn nộ']};
function reactionPicker(anchor,current,onSelect,{iconOnly=false,items=[]}={}){
 document.querySelectorAll('dialog.reaction-picker').forEach(d=>d.close());const dialog=node('dialog',undefined,'reaction-picker');dialog.setAttribute('aria-label','Chọn biểu cảm');if(iconOnly)dialog.classList.add('reaction-icons-only');
 for(const [key,[emoji,label]] of Object.entries(COMMENT_REACTIONS)){const button=node('button',undefined,'reaction-option');button.type='button';button.setAttribute('aria-label',label);button.setAttribute('aria-pressed',String(current===key));button.append(node('span',emoji,'reaction-emoji'),node('span',label,'reaction-label'));button.onclick=async()=>{dialog.close();try{await onSelect(current===key?null:key);}catch(e){status(e.message);}};dialog.append(button);}
 for(const [label,fn] of items){const actionButton=node('button',label,'reaction-message-action');actionButton.type='button';actionButton.onclick=async()=>{dialog.close();try{await fn();}catch(e){status(e.message);}};dialog.append(actionButton);}
 const cancel=node('button','Đóng','reaction-dismiss');cancel.type='button';cancel.onclick=()=>dialog.close();dialog.append(cancel);document.body.append(dialog);dialog.addEventListener('close',()=>{dialog.remove();if(anchor.isConnected)anchor.focus();},{once:true});dialog.onclick=e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientY<r.top||e.clientY>r.bottom||e.clientX<r.left||e.clientX>r.right)dialog.close();}};showAppDialog(dialog);
}
function renderCommentThread(container,comments,base,onReply,reload){
 const ids=new Set(comments.map(c=>c.id)),children=new Map();for(const c of comments){const parent=ids.has(c.parentId)?c.parentId:null;if(!children.has(parent))children.set(parent,[]);children.get(parent).push(c);}
 const visited=new Set();function draw(parent,target,depth=0){for(const c of children.get(parent)||[]){if(visited.has(c.id))continue;visited.add(c.id);const row=node('article',undefined,'fb-comment'+(base.startsWith('/shorts')?' reel-comment':'')),content=node('div',undefined,'fb-comment-content'),bubble=node('div',undefined,'fb-comment-bubble');bubble.append(node('strong',c.author.name),node('p',c.body));const actions=node('div',undefined,'fb-comment-actions'),react=node('button',c.myReaction?COMMENT_REACTIONS[c.myReaction][0]+' '+COMMENT_REACTIONS[c.myReaction][1]:'Thích');react.type='button';react.classList.toggle('reacted',!!c.myReaction);const reply=node('button','Trả lời');reply.type='button';reply.onclick=()=>onReply(c);actions.append(react,reply,node('time',timeAgo(c.created)));
 react.onclick=()=>reactionPicker(react,c.myReaction,async reaction=>{await api(base+'/'+c.id+'/reaction','POST',{reaction});await reload();});
 const counts=node('span',undefined,'fb-reaction-count');for(const [key,n] of Object.entries(c.reactions||{}))if(n)counts.append(node('span',COMMENT_REACTIONS[key][0]+' '+n));bubble.append(counts);content.append(bubble,actions);row.append(avatar(c.author),content);target.append(row);if(children.has(c.id)){const nested=node('div',undefined,'fb-replies');content.append(nested);draw(c.id,nested,depth+1);}}
 }draw(null,container);
}
function commentReplyBar(form,input){let parentId=null;const bar=node('div',undefined,'comment-replying');bar.hidden=true;const label=node('span'),cancel=node('button','×');cancel.type='button';cancel.setAttribute('aria-label','Hủy trả lời');bar.append(label,cancel);form.before(bar);const clear=()=>{parentId=null;bar.hidden=true;input.placeholder='Viết bình luận…';};cancel.onclick=clear;return {get parentId(){return parentId;},clear,reply:c=>{parentId=c.id;label.textContent='Đang trả lời '+c.author.name;bar.hidden=false;input.placeholder='Trả lời '+c.author.name+'…';input.focus();}};}
let activeReelComments = null;
// Bình luận video kiểu TikTok: avatar nhỏ, tên xám, thời gian · Trả lời, tim bên phải, trả lời thu gọn.
function renderReelComments(container,comments,base,onReply,reload){
 const ids=new Set(comments.map(c=>c.id)),children=new Map();
 for(const c of comments){const parent=ids.has(c.parentId)?c.parentId:null;if(!children.has(parent))children.set(parent,[]);children.get(parent).push(c);}
 const row=c=>{
  const r=node('article',undefined,'rc-item'),body=node('div',undefined,'rc-body');
  body.append(node('span',c.author.name,'rc-name'),node('p',c.body,'rc-text'));
  const meta=node('div',undefined,'rc-meta');meta.append(node('time',timeAgo(c.created)));
  const reply=node('button','Trả lời','rc-reply');reply.type='button';reply.onclick=()=>onReply(c);meta.append(reply);body.append(meta);
  const total=Object.values(c.reactions||{}).reduce((a,b)=>a+b,0),liked=!!c.myReaction;
  const like=node('button',undefined,'rc-like'+(liked?' is-liked':''));like.type='button';like.setAttribute('aria-label',liked?'Bỏ thích bình luận':'Thích bình luận');like.setAttribute('aria-pressed',String(liked));
  like.innerHTML=reelIcon('heart');like.append(node('span',total?String(total):''));
  like.onclick=async()=>{like.disabled=true;try{await api(base+'/'+c.id+'/reaction','POST',{reaction:liked?null:'love'});await reload();}catch(e){status(e.message);like.disabled=false;}};
  r.append(avatar(c.author),body,like);return r;
 };
 for(const c of children.get(null)||[]){
  container.append(row(c));
  const kids=[];const walk=id=>{for(const k of children.get(id)||[]){kids.push(k);walk(k.id);}};walk(c.id);
  if(!kids.length)continue;
  const box=node('div',undefined,'rc-replies');box.hidden=true;for(const k of kids)box.append(row(k));
  const more=node('button','Xem '+kids.length+' câu trả lời','rc-more');more.type='button';
  more.onclick=()=>{box.hidden=!box.hidden;more.textContent=box.hidden?'Xem '+kids.length+' câu trả lời':'Ẩn câu trả lời';};
  container.append(box,more);
 }
}
function closeReelComments(){activeReelComments?.close();}
function reelActions({s,video,api,status,avatar,personLink,report}){
 const side=document.createElement('aside');side.className='reel-side';side.setAttribute('aria-label','Tương tác video');
 const creator=personLink(s.author);creator.classList.add('reel-creator');side.append(creator);
 const control=(kind,label,text,fn)=>{const b=document.createElement('button');b.type='button';b.className='reel-action';b.setAttribute('aria-label',label);b.innerHTML=reelIcon(kind);const n=document.createElement('span');n.textContent=String(text);b.append(n);b.onclick=()=>Promise.resolve().then(fn).catch(e=>status(e.message));side.append(b);return b;};
 let liked=!!s.liked,likes=s.likes||0,count=s.comments||0;
 const like=control('heart',liked?'Bỏ thích video':'Thích video',likes,async()=>{
  if(like.disabled)return;like.disabled=true;
  try{await api('/shorts/'+s.id+'/like',liked?'DELETE':'POST',{});liked=!liked;likes+=liked?1:-1;paint();}finally{like.disabled=false;}
 });
 function paint(){like.classList.toggle('is-liked',liked);like.setAttribute('aria-pressed',String(liked));like.setAttribute('aria-label',liked?'Bỏ thích video':'Thích video');like.querySelector('span').textContent=likes;}
 paint();
 const comment=control('comment','Bình luận video',count,async()=>{
  if(activeReelComments)return;
  const dialog=document.createElement('dialog');dialog.className='reel-comments';dialog.setAttribute('aria-label','Bình luận video');
  document.body.classList.add("reel-comments-open");
  dialog.innerHTML='<div class="reel-comments-head rc-head"><span class="rc-spacer"></span><h2>'+count+' bình luận</h2><button type="button" class="reel-close" aria-label="Đóng bình luận">'+reelIcon('close')+'</button></div><div class="reel-comments-list" role="log" aria-live="polite"></div><div class="rc-emojis" aria-label="Chèn biểu tượng cảm xúc">'+['😍','😂','🔥','👏','🥰','😮','😢','💜'].map(e=>'<button type="button">'+e+'</button>').join('')+'</div><form class="reel-comment-form rc-form"><input maxlength="500" required placeholder="Thêm bình luận…" aria-label="Bình luận của bạn"><button type="submit" aria-label="Gửi bình luận">'+reelIcon('send')+'</button></form>';
  if(me)dialog.querySelector('.rc-form').prepend(avatar(me));
  dialog.querySelectorAll('.rc-emojis button').forEach(b=>b.onclick=()=>{const i=dialog.querySelector('.rc-form input');i.value+=b.textContent;i.focus();});
  document.body.append(dialog);activeReelComments=dialog;
  const list=dialog.querySelector('.reel-comments-list'),input=dialog.querySelector('input'),send=dialog.querySelector('[type=submit]');
  dialog.addEventListener('close',()=>{if(activeReelComments===dialog)activeReelComments=null;dialog.remove();document.body.classList.remove('reel-comments-open');},{once:true});
  dialog.querySelector('.reel-close').onclick=()=>dialog.close();
  dialog.onclick=e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)dialog.close();}};
  const replyState=commentReplyBar(dialog.querySelector('form'),input);
  showAppDialog(dialog);
  async function load(){
   list.textContent='Đang tải bình luận…';
   try{
    const {comments}=await api('/shorts/'+s.id+'/comments');if(!dialog.open)return;
    count=comments.length;comment.querySelector('span').textContent=count;dialog.querySelector('.rc-head h2').textContent=count+' bình luận';list.replaceChildren();
    if(!count){const empty=document.createElement('p');empty.className='reel-comments-empty';empty.textContent='Chưa có bình luận. Hãy mở đầu cuộc trò chuyện.';list.append(empty);}
    renderReelComments(list,comments,'/shorts/'+s.id+'/comments',c=>replyState.reply(c),load);
   }catch(e){if(dialog.open){list.textContent=e.message;const retry=document.createElement('button');retry.type='button';retry.textContent='Thử lại';retry.onclick=load;list.append(retry);}}
  }
  dialog.querySelector('form').onsubmit=async e=>{e.preventDefault();if(send.disabled)return;const body=input.value.trim();if(!body)return;send.disabled=true;try{await api('/shorts/'+s.id+'/comments','POST',{body,parentId:replyState.parentId});input.value='';replyState.clear();await load();if(dialog.open){list.scrollTop=list.scrollHeight;input.focus();}}catch(e){status(e.message);}finally{send.disabled=false;}};
  await load();
 });
 control('share','Chia sẻ video','Chia sẻ',async()=>{
  const url=new URL('/',location.origin);url.searchParams.set('video',s.id);
  try{if(navigator.share){await navigator.share({title:'Video của '+s.author.name,text:s.caption||'Xem video trên Kinnect',url:url.href});return;}}catch(e){if(e.name==='AbortError')return;}
  try{await navigator.clipboard.writeText(url.href);status('Đã sao chép liên kết video.');}catch{prompt('Sao chép liên kết video:',url.href);}
 });
 const sound=control(video.muted?'muted':'sound',video.muted?'Bật âm thanh':'Tắt âm thanh',video.muted?'Bật tiếng':'Âm thanh',async()=>{
  video.muted=!video.muted;reelMuted=video.muted;
  try{localStorage.setItem('kinnect-video-muted',reelMuted?'1':'0');}catch{}
  if(video.paused) await video.play();
 });
 const paintSound=()=>{sound.querySelector('svg').outerHTML=reelIcon(video.muted?'muted':'sound');sound.querySelector('span').textContent=video.muted?'Bật tiếng':'Âm thanh';sound.setAttribute('aria-label',video.muted?'Bật âm thanh':'Tắt âm thanh');sound.setAttribute('aria-pressed',String(!video.muted));};
 video.addEventListener('volumechange',paintSound);paintSound();
 control('more','Báo cáo video','Báo cáo',report);
 return side;
}

const websiteSessionProbe = window.parent !== window && new URL(location.href).searchParams.get("website-session") === "1";
const websiteOrigins = new Set(["https://kinnect.io.vn", "https://www.kinnect.io.vn"]);
let websiteParentOrigin;
try {
  const origin = new URL(document.referrer).origin;
  if (websiteOrigins.has(origin)) websiteParentOrigin = origin;
} catch {}
function tellWebsiteSession(authenticated) {
  if (websiteParentOrigin)
    window.parent.postMessage({ type: "kinnect:session-status", authenticated }, websiteParentOrigin);
}
if (websiteSessionProbe) window.addEventListener("message", async (event) => {
  if (event.source !== window.parent || !websiteOrigins.has(event.origin) || event.data?.type !== "kinnect:check-session") return;
  websiteParentOrigin = event.origin;
  try { await api("/me"); tellWebsiteSession(true); }
  catch { tellWebsiteSession(false); }
});
const $ = (id) => document.getElementById(id);
let me = null,
  mode = "login",
  tab = "feed",
  timer = null,
  notificationTimer = null;
let privateAlbumRefresh=null;
let privatePhotoViewer=null;
function closePrivatePhoto(){privatePhotoViewer?.close();}
let cleanupShorts = () => {};
let videoFeed = "recommended";
const node = (tag, text, cls) => {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  if (cls) e.className = cls;
  return e;
};
// Thông báo nhỏ tự ẩn sau vài giây
let noticeTimer = null;
const status = (text) => {
  const n = $("notice");
  n.textContent = text;
  n.classList.toggle("show", !!text);
  clearTimeout(noticeTimer);
  // Toast tự ẩn nhanh hơn để không che vùng tương tác.
  if (text) noticeTimer = setTimeout(() => n.classList.remove("show"), 2500);
};
const action = (text, fn, cls = "secondary") => {
  const b = node("button", text, cls);
  b.type = "button";
  b.onclick = async () => {
    b.disabled = true;
    try {
      await fn();
    } catch (e) {
      status(e.message);
    } finally {
      b.disabled = false;
    }
  };
  return b;
};
let authRevision = 0;
let sessionCheck = null;
let navigationRevision = 0;
// Tải video lên kèm % tiến độ và giới hạn thời gian (mạng chập chờn không làm kẹt nút "Đang đăng…").
function uploadJson(path, data, progress = () => {}) {
  return new Promise((resolve, reject) => {
    const x = new XMLHttpRequest();
    x.open("POST", "/api" + path);
    x.withCredentials = true;
    x.timeout = 180000;
    x.setRequestHeader("Content-Type", "application/json");
    x.upload.onprogress = (e) => e.lengthComputable && progress(Math.round((e.loaded / e.total) * 100));
    x.upload.onload = () => progress(100);
    x.onload = () => {
      let body = {};
      try { body = JSON.parse(x.responseText || "{}"); } catch {}
      if (x.status >= 200 && x.status < 300) resolve(body);
      else reject(Error(body.error || "Đăng không thành công (" + x.status + ")."));
    };
    x.onerror = () => reject(Error("Mất kết nối khi tải video lên. Hãy thử lại."));
    x.ontimeout = () => reject(Error("Tải lên quá lâu. Hãy kiểm tra mạng rồi thử lại."));
    x.send(JSON.stringify(data));
  });
}
// Gom các yêu cầu GET đang bay cùng một đường dẫn: nếu nhiều widget cùng gọi
// (ví dụ /notifications, /conversations, /me) trong khi một request chưa xong,
// chúng sẽ cùng dùng chung một promise thay vì mở nhiều kết nối trùng.
const inFlightGets = new Map();
async function api(path, method = "GET", data) {
  if (method === "GET" && data === undefined) {
    const existing = inFlightGets.get(path);
    if (existing) {
      // Trả bản sao để mỗi caller có thể sửa kết quả riêng mà không ảnh hưởng người khác.
      const shared = await existing;
      return typeof structuredClone === "function" ? structuredClone(shared) : JSON.parse(JSON.stringify(shared));
    }
    const promise = (async () => {
      try { return await apiFetch(path, method, data); }
      finally { if (inFlightGets.get(path) === promise) inFlightGets.delete(path); }
    })();
    inFlightGets.set(path, promise);
    const shared = await promise;
    return typeof structuredClone === "function" ? structuredClone(shared) : JSON.parse(JSON.stringify(shared));
  }
  return apiFetch(path, method, data);
}
async function apiFetch(path, method, data) {
  const revision = authRevision;
  const options = {
    method, credentials: "same-origin", cache: "no-store",
    headers: data === undefined ? {} : { "Content-Type": "application/json" },
    body: data === undefined ? undefined : JSON.stringify(data),
  };
  let r = await fetch("/api" + path, options);
  if (r.status === 401 && me && revision === authRevision) {
    // Confirm session expiry independently of a failed background request.
    if (!sessionCheck || sessionCheck.revision !== revision) {
      sessionCheck = { revision, promise: fetch("/api/me", { credentials: "same-origin", cache: "no-store" }) };
    }
    const check = sessionCheck;
    let verified;
    try { verified = await check.promise; }
    finally { if (sessionCheck === check) sessionCheck = null; }
    if (revision !== authRevision) throw Error("Phiên làm việc đã thay đổi.");
    if (verified.status === 401) {
      me = null;
      disconnectLive();
      showAuth();
      status("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.");
    } else if (verified.ok && method === "GET") {
      r = await fetch("/api" + path, options);
    }
  }
  if (revision !== authRevision && r.ok) throw Error("Phiên làm việc đã thay đổi.");
  const result = await r.json().catch(() => ({}));
  if (!r.ok) throw Error(result.error || "Không thể thực hiện yêu cầu. Hãy thử lại.");
  return result;
}
function showAuth() {
  stopChatTyping?.();
  endVideoCall();
  document.querySelectorAll("dialog.story-viewer,dialog.reel-comments").forEach(dialog=>dialog.close());
  stopLocationTracking();
  authRevision++;
  navigationRevision++;
  if (websiteSessionProbe) { tellWebsiteSession(false); return; }
  clearInterval(activityTimer); closeNotificationCenter();
  notificationCache = []; knownNotificationIds.clear(); notificationBaseline = false;
  document.querySelector(".notification-optin")?.remove();
  privateAlbumRefresh=null;closePrivatePhoto();
  cleanupShorts();
  document.body.classList.remove("profile-edit-open");
  delete document.body.dataset.reel;
  clearInterval(timer);
  clearInterval(notificationTimer);
  $("auth").hidden = false;
  $("app").hidden = true;
  $("password").value = "";
  window.kinnectAuthShown = true;
  setupSocialLogin();
  handleOAuthReturn();
  window.dispatchEvent(new Event("kinnect-auth-shown"));
}
function authMode(value) {
  mode = value;
  const register = mode === "register";
  $("register-fields").hidden = !register;
  $("register-fields").disabled = !register;
  $("auth-submit").textContent = register ? "Tạo tài khoản" : "Đăng nhập";
  $("password").autocomplete = register ? "new-password" : "current-password";
  $("auth-title").textContent = register ? "Tạo tài khoản Kinnect" : "Chào mừng trở lại";
  $("auth-sub").textContent = register
    ? "Miễn phí, chỉ mất chưa tới một phút."
    : "Đăng nhập để tiếp tục với Kinnect.";
  for (const [id, on] of [["login-mode", !register], ["register-mode", register]]) {
    $(id).classList.toggle("active", on);
    $(id).setAttribute("aria-pressed", String(on));
  }
  const sw = $("auth-switch");
  sw.firstChild.textContent = register ? "Đã có tài khoản? " : "Chưa có tài khoản? ";
  sw.querySelector("button").textContent = register ? "Đăng nhập" : "Tạo tài khoản mới";
  sw.querySelector("button").dataset.mode = register ? "login" : "register";
  $("forgot-link").hidden = register;
  $("auth-status").textContent = "";
  if ($("auth-notice")) $("auth-notice").hidden = true;
}
$("login-mode").onclick = () => authMode("login");
$("register-mode").onclick = () => authMode("register");
$("auth-switch").querySelector("button").onclick = (e) =>
  authMode(e.currentTarget.dataset.mode);
// ---- Quên mật khẩu ----
function forgotView(open) {
  $("forgot-view").hidden = !open;
  $("auth-form").hidden = open;
  document.querySelector("#auth .auth-tabs").hidden = open;
  $("auth-switch").hidden = open;
  if (open) $("social-login").hidden = true;
  else setupSocialLogin();
  $("auth-title").textContent = open ? "Quên mật khẩu?" : "Chào mừng trở lại";
  $("auth-sub").textContent = open
    ? "Nhận mã OTP qua email khôi phục để đặt lại mật khẩu."
    : "Đăng nhập để tiếp tục với Kinnect.";
  $("forgot-form").hidden = false;
  $("forgot-done").hidden = true;
  $("forgot-status").textContent = "";
  if (open) {
    $("forgot-username").value = $("username").value;
    ($("forgot-username").value ? $("forgot-contact") : $("forgot-username")).focus();
  } else authMode("login");
}
$("forgot-link").onclick = () => forgotView(true);
$("forgot-back").onclick = () => forgotView(false);
$("forgot-done-back").onclick = () => forgotView(false);
$("forgot-form").onsubmit = async (e) => {
  e.preventDefault();
  $("forgot-submit").disabled = true;
  $("forgot-status").textContent = "";
  try {
    await api("/password-reset", "POST", {
      username: $("forgot-username").value,
      contact: $("forgot-contact").value,
      note: $("forgot-note").value,
    });
    $("forgot-form").hidden = true;
    $("forgot-done").hidden = false;
  } catch (error) {
    $("forgot-status").textContent = error.message;
  } finally {
    $("forgot-submit").disabled = false;
  }
};
// ---- Đăng nhập bằng Google / Facebook ----
const OAUTH_ERRORS = {
  cancelled: "Bạn đã huỷ đăng nhập.",
  state: "Phiên đăng nhập không hợp lệ. Hãy thử lại.",
  provider: "Không kết nối được với Google/Facebook. Hãy thử lại sau.",
  suspended: "Tài khoản này đang bị tạm khoá.",
};
async function setupSocialLogin() {
  try {
    const { providers } = await api("/oauth/providers");
    $("google-login").hidden = !providers.includes("google");
    $("facebook-login").hidden = !providers.includes("facebook");
    $("social-login").hidden = !providers.length;
  } catch {
    $("social-login").hidden = true;
  }
}
function oauthView(open) {
  $("oauth-form").hidden = !open;
  for (const id of ["auth-form", "auth-switch"]) $(id).hidden = open;
  document.querySelector("#auth .auth-tabs").hidden = open;
  if (open) $("social-login").hidden = true;
}
async function handleOAuthReturn() {
  const params = new URL(location.href).searchParams;
  const error = params.get("oauth_error");
  const ticket = params.get("ticket");
  if (error || params.get("oauth")) history.replaceState(null, "", "/");
  if (error) $("auth-status").textContent = OAUTH_ERRORS[error] || OAUTH_ERRORS.provider;
  if (params.get("oauth") !== "complete" || !ticket) return;
  try {
    const p = await api("/oauth/pending?ticket=" + encodeURIComponent(ticket));
    oauthView(true);
    $("auth-title").textContent = "Chỉ còn một bước";
    $("auth-sub").textContent = "Xác nhận thông tin để tạo tài khoản Kinnect.";
    $("oauth-hello").textContent =
      "Đã xác thực qua " + (p.provider === "google" ? "Google" : "Facebook") + (p.name ? " · " + p.name : "");
    $("oauth-name").value = p.name;
    $("oauth-username").value = p.suggestedUsername;
    $("oauth-form").onsubmit = async (e) => {
      e.preventDefault();
      $("oauth-submit").disabled = true;
      $("oauth-status").textContent = "";
      try {
        await api("/oauth/complete", "POST", {
          ticket,
          username: $("oauth-username").value,
          name: $("oauth-name").value,
          agree18: $("oauth-agree").checked,
        });
        me = (await api("/me")).user;
        oauthView(false);
        rememberProfilePrompt();
        await enter();
      } catch (err) {
        $("oauth-status").textContent = err.message;
      } finally {
        $("oauth-submit").disabled = false;
      }
    };
  } catch (err) {
    $("auth-status").textContent = err.message;
  }
}
$("oauth-cancel").onclick = () => {
  oauthView(false);
  authMode("login");
  setupSocialLogin();
};
$("pw-toggle").onclick = () => {
  const show = $("password").type === "password";
  $("password").type = show ? "text" : "password";
  $("pw-toggle").textContent = show ? "Ẩn" : "Hiện";
  $("pw-toggle").setAttribute("aria-label", show ? "Ẩn mật khẩu" : "Hiện mật khẩu");
  $("pw-toggle").setAttribute("aria-pressed", String(show));
};
$("auth-form").onsubmit = async (e) => {
  e.preventDefault();
  $("auth-submit").disabled = true;
  try {
    const result = await api("/" + mode, "POST", {
      username: $("username").value,
      password: $("password").value,
      name: $("display-name").value,
      agree18: $("agree").checked,
      remember: $("remember-device").checked,
    });
    me = result.user;
    if(mode === "register") rememberProfilePrompt();
    $("password").value = "";
    await enter();
  } catch (error) {
    $("auth-status").textContent = error.message;
  } finally {
    $("auth-submit").disabled = false;
  }
};
async function enter() {
  authRevision++;
  if (websiteSessionProbe) { tellWebsiteSession(true); return; }
  $("admin-tab").hidden = me.role !== "admin";
  $("admin-menu").hidden = me.role !== "admin";
  $("auth").hidden = true;
  $("app").hidden = false;
  $("name").value = me.name;
  paintMe();
  initializeNotificationCenter(); startActivityHeartbeat();
  resumeLocationTracking().catch(()=>{});
  window.dispatchEvent(new CustomEvent("kinnect-logged-in", { detail: me }));
  loadVideoCalls().catch(()=>{});
  connectLive();
  status("Chào " + me.name + "!");
  const launchParams=new URL(location.href).searchParams;
  const initialRoute=initialNavigationRoute();
  await renderNavigationRoute(initialRoute,'replace');
  if(launchParams.get('view')==='live')document.body.classList.add('live-only');
  rail().catch(() => {});
  clearInterval(notificationTimer);
  notificationTimer = setInterval(() => refreshUnread().catch(() => {}), 10000);
  await refreshUnread().catch(e => status(e.message));

}
// Ảnh đại diện và tên trên nút tài khoản
function paintMe() {
  const old = $("me-avatar");
  const fresh = avatar(me);
  fresh.id = "me-avatar";
  old.replaceWith(fresh);
  const head = avatar(me);
  head.id = "me-head-avatar";
  $("me-head-avatar").replaceWith(head);
  $("me-name").textContent = me.name;
  $("me-username").textContent = "@" + me.username;
}
// ---- Menu tài khoản ----
const meBtn = $("me-btn"),
  mePanel = $("me-panel");
const accountPanelBar=node('div',undefined,'header-panel-bar');
const accountPanelBack=node('button',undefined,'header-panel-back app-back-button');accountPanelBack.type='button';accountPanelBack.setAttribute('aria-label','Đóng tài khoản');accountPanelBack.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m14 6-6 6 6 6"/></svg>';accountPanelBack.onclick=()=>dismissHeaderPopup();accountPanelBar.append(accountPanelBack,node('h2','Tài khoản'));mePanel.prepend(accountPanelBar);mePanel.setAttribute('role','dialog');mePanel.setAttribute('aria-label','Tài khoản');mePanel.removeAttribute('aria-modal');
function syncHeaderPanelState(){document.body.classList.toggle('header-panel-open',!mePanel.hidden||Boolean(notificationPanel&&!notificationPanel.hidden));}

const appDialogs = new Map();
let appDialogSerial = 0;
function showAppDialog(dialog) {
 dialog.showModal();
 if(!ownNavigationState())return;
 const id=String(++appDialogSerial);appDialogs.set(id,dialog);
 history.pushState({...history.state,headerPopup:undefined,appDialog:id},'',location.href);
 dialog.addEventListener('close',()=>{
  appDialogs.delete(id);
  queueMicrotask(()=>{if(ownNavigationState()&&history.state.appDialog===id)history.back();});
 },{once:true});
}
function positionHeaderPopup(panel) {
 const header=document.querySelector('#app>header').getBoundingClientRect(),content=$('social-panel').getBoundingClientRect();
 const nav=document.querySelector('#app>nav'),navRect=nav.getBoundingClientRect();
 const bottom=innerWidth<1000&&getComputedStyle(nav).position==='fixed'?navRect.top:innerHeight;
 const left=innerWidth<1000?0:Math.max(0,content.left),width=innerWidth<1000?innerWidth:content.width;
 panel.style.setProperty('--header-popup-top',Math.round(header.bottom)+'px');
 panel.style.setProperty('--header-panel-left',Math.round(left)+'px');
 panel.style.setProperty('--header-panel-width',Math.round(width)+'px');
 panel.style.setProperty('--header-panel-height',Math.max(0,Math.round(bottom-header.bottom))+'px');
}

function showHeaderPopup(kind) {
  if (!ownNavigationState()) return;
  saveNavigationScroll();
  const state = {...history.state, headerPopup:kind};
  history[history.state.headerPopup ? 'replaceState' : 'pushState'](state, '', location.href);
}
function dismissHeaderPopup() {
  menu(false); closeNotificationCenter(false);
  if (ownNavigationState() && history.state.headerPopup) history.back();
}
function menu(open) {
  if(open){ closeNotificationCenter(false); showHeaderPopup('account'); positionHeaderPopup(mePanel); }
  mePanel.hidden = !open;
  meBtn.setAttribute("aria-expanded", String(open));
  syncHeaderPanelState();
  if(open)accountPanelBack.focus();
}
meBtn.onclick = () => {
  // Popup "Tài khoản" dùng chung cho mọi khổ màn; URL /?tab=account vẫn hoạt động như deep-link.
  menu(mePanel.hidden);
};
document.addEventListener("click", (e) => {
  if (!mePanel.hidden && !e.target.closest(".me-menu") && !e.target.closest("#notification-bell")) dismissHeaderPopup();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !mePanel.hidden) {
    dismissHeaderPopup();
    meBtn.focus();
  }
});
for (const b of mePanel.querySelectorAll("[data-go]"))
  b.onclick = () => {
    menu(false);
    if (b.dataset.go === "ios-install") window.dispatchEvent(new Event("kinnect-install-ios"));
    else if (b.dataset.go === "settings") navigate("settings");
    else if (b.dataset.go === "admin") navigate("admin");
    else navigate("profile");
  };
$("logout").onclick = async () => {
  menu(false);
  try {
    await api("/logout", "POST", {});
    me = null;
    disconnectLive();
    showAuth();
    const notice = $("auth-notice");
    if (notice) { notice.textContent = "Bạn đã đăng xuất. Hẹn gặp lại!"; notice.hidden = false; }
  } catch (e) {
    status(e.message);
  }
};
// Ô tìm kiếm trên thanh trên cùng → Khám phá
$("top-search").onsubmit = (e) => {
  e.preventDefault();
  navigate("discover", { q: $("top-search-input").value });
};
for (const button of document.querySelectorAll("[data-tab]:not([data-tab=notifications])"))
  button.onclick = () =>
    navigate(button.dataset.tab).catch((e) => status(e.message));
const headerInboxButton=document.querySelector('#app .top-actions [data-tab=inbox]');
if(headerInboxButton)headerInboxButton.onclick=()=>navigate('inbox').catch(e=>status(e.message));
// Khung xám nhấp nháy trong lúc tải
function skeleton(kind) {
  const box = node("div", undefined, "skeleton-list");
  box.setAttribute("aria-hidden", "true");
  for (let i = 0; i < (kind === "grid" ? 6 : 3); i++)
    box.append(node("div", undefined, "skeleton " + (kind === "grid" ? "sk-tile" : "sk-card")));
  if (kind === "grid") box.classList.add("grid");
  return box;
}
let inboxRefresh=null,stopChatViewport=null,friendsRefresh=null,adminRequestsRefresh=null,stopChatTyping=null;
function fitChatViewport(box){
 stopChatViewport?.();if(!window.visualViewport)return;
 const viewport=window.visualViewport;let restingHeight=viewport.height,keyboardOpen=false,frame=0;
 const fit=()=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{
  if(!box.isConnected)return;
  if(innerWidth>=1000){box.style.removeProperty('height');box.style.removeProperty('min-height');document.body.classList.remove('chat-keyboard-open');return;}
  const focused=box.contains(document.activeElement)&&document.activeElement.matches('input,textarea,[contenteditable="true"]');
  const reduced=restingHeight-viewport.height>100||innerHeight-viewport.height>100;
  keyboardOpen=(focused||keyboardOpen)&&reduced&&(!viewport.scale||Math.abs(viewport.scale-1)<.05);
  if(!focused&&!keyboardOpen)restingHeight=Math.max(restingHeight,viewport.height);
  document.body.classList.toggle('chat-keyboard-open',keyboardOpen);
  const top=box.getBoundingClientRect().top,visibleBottom=viewport.offsetTop+viewport.height;
  const nav=document.querySelector('#app>nav'),navRect=nav?.getBoundingClientRect();
  const bottom=keyboardOpen?visibleBottom:Math.min(visibleBottom,navRect&&getComputedStyle(nav).position==='fixed'?navRect.top-8:visibleBottom-8);
  box.style.minHeight='0px';box.style.height=Math.max(0,bottom-top-box.offsetHeight+box.clientHeight)+'px';
 });};
 viewport.addEventListener('resize',fit);viewport.addEventListener('scroll',fit);window.addEventListener('resize',fit);box.addEventListener('focusin',fit);box.addEventListener('focusout',fit);fit();
 stopChatViewport=()=>{cancelAnimationFrame(frame);viewport.removeEventListener('resize',fit);viewport.removeEventListener('scroll',fit);window.removeEventListener('resize',fit);box.removeEventListener('focusin',fit);box.removeEventListener('focusout',fit);document.body.classList.remove('chat-keyboard-open');stopChatViewport=null;};
}

const appRoutes=new Set(['feed','discover','shorts','profile','inbox','friends','settings','notifications','account','admin','live']);
let historyRestoreRevision=0,renderedNavigationRoute=null;
function ownNavigationState(state=history.state){return state?.kinnectNavigation===1&&state.userId===me?.id&&appRoutes.has(state.route?.tab);}
function navigationRoute(value,opts={}){
 const clean={};for(const key of ['user','chat','group','q','mode','section','search','profileSection','post','video'])if(typeof opts[key]==='string')clean[key]=opts[key];
 for(const key of ['settings','privateAlbum'])if(opts[key])clean[key]=true;
 if(value==='shorts'){clean.feed=opts.feed||videoFeed;const video=opts.video||new URL(location.href).searchParams.get('video');if(video)clean.video=video;}
 if(value==='feed')clean.section=opts.section||feedSection;
 if(value==='discover')clean.mode=opts.mode||discoveryMode;
 return {tab:value,opts:clean};
}
function navigationUrl(route){
 const url=new URL(location.href);for(const key of ['tab','user','chat','group','q','mode','section','search','profileSection','post','video','feed','edit','album','view'])url.searchParams.delete(key);
 url.searchParams.set('tab',route.tab);for(const [key,value] of Object.entries(route.opts)){if(key==='settings')url.searchParams.set('edit','1');else if(key==='privateAlbum')url.searchParams.set('album','private');else url.searchParams.set(key,value);}
 return url.pathname+url.search+url.hash;
}
function saveNavigationScroll(){if(!ownNavigationState())return;history.replaceState({...history.state,scrollY:window.scrollY,reelTop:document.querySelector('.reel')?.scrollTop||0},'',location.href);}
function recordNavigation(value,opts,mode){
 if(mode==='none')return;
 historyRestoreRevision++;saveNavigationScroll();const route=navigationRoute(value,opts),previous=ownNavigationState()?history.state:null;
 const same=previous&&JSON.stringify(previous.route)===JSON.stringify(route);const replace=mode==='replace'||!previous||same||Boolean(previous.headerPopup||previous.appDialog);
 const state={kinnectNavigation:1,userId:me.id,index:replace?((previous?.index||0)+((previous?.headerPopup||previous?.appDialog)&&!same?1:0)):previous.index+1,route,scrollY:0,reelTop:0};
 history[replace?'replaceState':'pushState'](state,'',navigationUrl(route));if('scrollRestoration' in history)history.scrollRestoration='manual';
}
function replaceNavigationOptions(extra){if(!ownNavigationState())return;const route=navigationRoute(history.state.route.tab,{...history.state.route.opts,...extra});renderedNavigationRoute=route;history.replaceState({...history.state,route},'',navigationUrl(route));}
function goBack(fallback='discover'){
 if(ownNavigationState()&&history.state.index>0){saveNavigationScroll();history.back();return;}
 return navigate(fallback,{},'replace');
}
function initialNavigationRoute(){
 if(ownNavigationState())return history.state.route;
 const params=new URL(location.href).searchParams;if(history.state?.kinnectNavigation===1)return {tab:'discover',opts:{}};
 const value=params.has('video')?'shorts':params.has('chat')||params.has('group')?'inbox':params.get('view')==='live'?'live':appRoutes.has(params.get('tab'))?params.get('tab'):'discover';
 const opts={};for(const key of ['user','chat','group','q','mode','section','search','profileSection','post','video','feed'])if(params.has(key))opts[key]=params.get(key);if(params.get('edit')==='1')opts.settings=true;if(params.get('album')==='private')opts.privateAlbum=true;return {tab:value,opts};
}
async function renderNavigationRoute(route,mode='none'){
 const token=historyRestoreRevision;
 if(route.tab==='inbox'&&route.opts.chat){const {user}=await api('/users/'+encodeURIComponent(route.opts.chat));if(token!==historyRestoreRevision)return;return openChat(user,mode);}
 if(route.tab==='inbox'&&route.opts.group)return openGroupChat(route.opts.group,mode);
 return navigate(route.tab,route.opts,mode);
}
window.addEventListener('popstate',async event=>{
 if(!ownNavigationState(event.state))return;
 for(const [id,dialog] of appDialogs)if(id!==event.state.appDialog&&dialog.open)dialog.close();
 if(event.state.appDialog&&!appDialogs.has(event.state.appDialog)){const state={...history.state};delete state.appDialog;history.replaceState(state,'',location.href);}
 menu(false);closeNotificationCenter(false);
 if(event.state.headerPopup==='account')menu(true);
 else if(event.state.headerPopup==='notifications'){notificationPanel.hidden=false;positionHeaderPopup(notificationPanel);$('notification-bell').setAttribute('aria-expanded','true');renderNotificationCenter();syncHeaderPanelState();}
 if(JSON.stringify(event.state.route)===JSON.stringify(renderedNavigationRoute))return;
 historyRestoreRevision++;const target=event.state;
 document.querySelectorAll('dialog[open]').forEach(dialog=>dialog.close());
 try{await renderNavigationRoute(target.route);if(!ownNavigationState()||history.state.index!==target.index)return;requestAnimationFrame(()=>{window.scrollTo(0,target.scrollY||0);const reel=document.querySelector('.reel');if(reel)reel.scrollTop=target.reelTop||0;});}catch(e){status(e.message);}
});
async function navigate(value, opts = {},historyMode="push") {
  if(!me||!appRoutes.has(value))return false;
  recordNavigation(value,opts,historyMode);
  renderedNavigationRoute=navigationRoute(value,opts);
  if(value==="feed"&&["community","confessions","questions","news"].includes(opts.section))feedSection=opts.section;
  if(value==="discover"&&["nearby","new","active","interests"].includes(opts.mode))discoveryMode=opts.mode;
  stopChatTyping?.();stopChatViewport?.();inboxRefresh=null;friendsRefresh=null;adminRequestsRefresh=null;
  const revision = ++navigationRevision;
  nearbyRefresh=null;
  closeNotificationCenter();
  document.querySelectorAll("dialog.more-sheet,dialog.group-picker,dialog.profile-options-sheet").forEach(d=>d.close());
  privateAlbumRefresh=null;closePrivatePhoto();
  cleanupShorts();
  document.body.classList.remove("profile-edit-open");
  delete document.body.dataset.reel;
  clearInterval(timer);
  timer = null;
  tab = value;
  menu(false);
  document.body.dataset.view = value;
  for (const b of document.querySelectorAll("[data-tab]"))
    b.classList.toggle("active", (b.dataset.tab === value || value === "live" && b.dataset.tab === "shorts") && !opts.user);
  $("social-panel").hidden = value === "live";
  $("live-panel").hidden = value !== "live";
  const panel = $("social-panel");
  if (value === "live") return;
  panel.replaceChildren(skeleton(value === "discover" ? "grid" : "list"));
  const view = node("div", undefined, "view view-" + value);
  try {
    if (value === "feed") await feed(view);
    if (value === "discover") await discover(view, opts.q || "");
    if (value === "shorts") await shorts(view, () => revision === navigationRevision, opts.feed || videoFeed);
    if (value === "profile") await profile(view, opts);
    if (value === "inbox") await inbox(view);
    if (value === "friends") await friendsPage(view,opts);
    if (value === "settings") await accountSettings(view);
    if (value === "account") await accountHome(view);
    if (value === "notifications") await notifications(view);
    if (value === "admin") await adminPanel(view,opts);
  } catch (e) {
    status(e.message);
    view.append(empty("⚠️", "Không tải được dữ liệu", "Kiểm tra kết nối rồi thử lại."));
  }
  if (revision !== navigationRevision || !me) return false;
  panel.replaceChildren(view);
  if(["discover","feed"].includes(value)) renderProfileCompletionPrompt(view);
  window.scrollTo(0, 0);
  if(opts.privateAlbum)view.querySelector(".private-album")?.scrollIntoView({block:"start"});
  if(opts.post){const post=view.querySelector('[data-post-id="'+CSS.escape(opts.post)+'"]');if(post){post.tabIndex=-1;post.focus({preventScroll:true});post.scrollIntoView({block:"center"});}else status("Bài viết không còn khả dụng.");}
  return true;
}
function empty(icon, title, text) {
  const box = node("div", undefined, "empty-state");
  box.append(node("div", icon, "empty-ico"), node("h3", title), node("p", text, "muted"));
  return box;
}
// Màu ảnh đại diện mặc định theo từng người (8 tông, không dùng style nội tuyến)
const hue = (id = "") => {
  let h = 0;
  for (const c of id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return "hue-" + (h % 8);
};
function avatar(u) {
  if (!u.avatar) {
    const e = node(
      "span",
      (u.name || "?").slice(0, 1).toUpperCase(),
      "avatar fallback " + hue(u.id || u.username),
    );
    e.setAttribute("aria-hidden", "true");
    return e;
  }
  const img = node("img");
  img.src = u.avatar;
  img.alt = "Ảnh của " + u.name;
  img.className = "avatar";
  return img;
}
// Menu "⋯" dùng chung cho thẻ người, bài viết, tin nhắn
function more(items, label = "Tùy chọn khác") {
 const wrap=node('details',undefined,'more'),sum=node('summary','⋯');sum.setAttribute('aria-label',label);wrap.append(sum);
 sum.onclick=e=>{e.preventDefault();const dialog=node('dialog',undefined,'more-sheet');dialog.setAttribute('aria-label',label);const head=node('div',undefined,'report-sheet-head');head.append(node('h2','Tùy chọn'));const close=node('button','×');close.type='button';close.setAttribute('aria-label','Đóng tùy chọn');close.onclick=()=>dialog.close();head.append(close);dialog.append(head);
  for(const [text,fn,cls] of items){const button=action(text,async()=>{dialog.close();await fn();},cls||'');dialog.append(button);}
  document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});showAppDialog(dialog);
 };return wrap;
}
function personLink(u, extraClass = "") {
  const b = node("button", undefined, "person-link " + extraClass);
  b.type = "button";
  b.setAttribute("aria-label", "Xem trang của " + u.name);
  b.append(avatar(u));
  b.onclick = () => navigate("profile", { user: u.id });
  return b;
}

async function report(targetType, targetId) {
  if(document.querySelector('dialog.report-sheet'))return;
  const dialog=node('dialog',undefined,'report-sheet');dialog.setAttribute('aria-label',targetType==='short'?'Báo cáo video':'Gửi báo cáo');
  const head=node('div',undefined,'report-sheet-head'),title=node('h2',targetType==='short'?'Báo cáo video':'Gửi báo cáo'),close=node('button');
  close.type='button';close.setAttribute('aria-label','Đóng báo cáo');close.innerHTML=reelIcon('close');close.onclick=()=>dialog.close();head.append(title,close);
  const intro=node('p','Bạn muốn báo cáo nội dung này vì lý do gì?','report-intro'),form=node('form'),choices=node('fieldset');choices.append(node('legend','Chọn lý do'));
  for(const label of ['Nội dung không phù hợp','Quấy rối hoặc bắt nạt','Bạo lực hoặc nguy hiểm','Lừa đảo hoặc spam','Vi phạm bản quyền','Lý do khác']){
    const row=node('label',undefined,'report-choice'),radio=node('input');radio.type='radio';radio.name='reason';radio.value=label;radio.required=true;row.append(radio,node('span',label));choices.append(row);
  }
  const detail=node('textarea');detail.placeholder='Thêm thông tin (không bắt buộc)';detail.setAttribute('aria-label','Thông tin báo cáo');detail.maxLength=1000;detail.rows=3;
  const feedback=node('p','','report-feedback');feedback.setAttribute('role','status');const send=node('button','Gửi báo cáo','report-submit');send.type='submit';
  const note=node('p','Báo cáo của bạn sẽ được quản trị viên xem xét.','report-note');form.append(choices,detail,feedback,send,note);dialog.append(head,intro,form);document.body.append(dialog);
  dialog.addEventListener('close',()=>dialog.remove(),{once:true});showAppDialog(dialog);
  form.onsubmit=async e=>{e.preventDefault();const selected=form.querySelector('input:checked');if(!selected||send.disabled)return;send.disabled=true;feedback.textContent='';
    try{await api('/reports','POST',{targetType,targetId,reason:selected.value+(detail.value.trim()?': '+detail.value.trim():'')});form.replaceChildren(node('div','Đã gửi báo cáo','report-success'),node('p','Cảm ơn bạn đã giúp Kinnect an toàn hơn.','report-note'));const done=node('button','Xong','report-submit');done.type='button';done.onclick=()=>dialog.close();form.append(done);done.focus();}
    catch(error){feedback.textContent=error.message;send.disabled=false;}
  };
}
let discoveryMode = "nearby";

let geoWatch=null,geoTimer=null,lastGeoSync=0,geoOwner=null,nearbyRefresh=null;
function stopLocationTracking(){
 if(geoWatch!==null)navigator.geolocation?.clearWatch?.(geoWatch);geoWatch=null;clearInterval(geoTimer);geoTimer=null;geoOwner=null;
}
function rememberLocation(enabled){try{localStorage.setItem("kinnect-location-enabled",enabled?"1":"0");}catch{}}
function startLocationTracking(){
 if(!me||document.hidden||!navigator.geolocation)return;
 if(geoOwner===me.id&&(geoWatch!==null||geoTimer))return;
 stopLocationTracking();geoOwner=me.id;
 const sync=async position=>{
  if(!me||geoOwner!==me.id||document.hidden||Date.now()-lastGeoSync<60000)return;
  const userId=me.id;lastGeoSync=Date.now();
  try{const result=await api("/me/location","PATCH",{enabled:true,latitude:position.coords.latitude,longitude:position.coords.longitude});if(me?.id!==userId)return;me=result.user;await nearbyRefresh?.();}
  catch(e){if(e.code===1){rememberLocation(false);stopLocationTracking();}}
 };
 const error=e=>{if(e.code===1){rememberLocation(false);stopLocationTracking();}};
 if(navigator.geolocation.watchPosition)geoWatch=navigator.geolocation.watchPosition(sync,error,{enableHighAccuracy:true,maximumAge:60000,timeout:20000});
 else geoTimer=setInterval(()=>{if(!document.hidden)navigator.geolocation.getCurrentPosition(sync,error,{maximumAge:60000,timeout:15000});},60000);
}
async function resumeLocationTracking(){
 if(!me||document.hidden)return;let opted=false;try{opted=localStorage.getItem("kinnect-location-enabled")==="1";}catch{}
 try{const permission=await navigator.permissions?.query({name:"geolocation"});if(permission?.state==="granted"&&(opted||me.hasLocation)){rememberLocation(true);startLocationTracking();return;}if(permission&&permission.state!=="granted")return;}catch{}
 if(opted)startLocationTracking();
}


function timeAgo(t) {
  const m = Math.round((Date.now() - t) / 60000);
  if (m < 1) return "Vừa xong";
  if (m < 60) return m + " phút";
  if (m < 1440) return Math.round(m / 60) + " giờ";
  if (m < 10080) return Math.round(m / 1440) + " ngày";
  return new Date(t).toLocaleDateString("vi-VN");
}
const clock = (t) =>
  new Date(t).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" });


let feedSection='community';


// Tab "Trực tiếp" của trang Video: lưới các buổi đang live, chạm để vào xem ngay.
async function liveGrid(reel, isCurrent) {
  reel.classList.add("live-grid-host");
  const box = node("div", undefined, "live-grid");
  reel.append(box);
  // Trang được dựng ngoài màn rồi mới gắn vào, nên lần vẽ đầu không đòi box đã nằm trên trang.
  let first = true, refreshTimer, loading = false;
  const draw = async () => {
    if (loading) return;
    clearTimeout(refreshTimer);
    if (!isCurrent() || (!first && !box.isConnected)) return;
    first = false;
    loading = true;
    box.setAttribute('aria-busy', 'true');
    if (!box.children.length) box.append(node('p', 'Đang tải danh sách live…', 'live-grid-loading'));
    let rooms;
    try { rooms = (await api("/live/rooms")).rooms || []; }
    catch {
      if (!isCurrent()) return;
      for (const el of box.querySelectorAll('.live-grid-error,.live-grid-loading,.live-grid-empty')) el.remove();
      const error = node('div', undefined, 'live-grid-error');
      error.setAttribute('role', 'status');
      error.append(node('p', 'Chưa tải được danh sách live. Kiểm tra mạng rồi thử lại.'));
      error.append(action('Thử lại', draw, 'secondary'));
      box.prepend(error);
      refreshTimer = setTimeout(draw, 8000);
      return;
    } finally { loading = false; box.setAttribute('aria-busy', 'false'); }
    if (!isCurrent()) return;
    box.replaceChildren();
    if (!rooms.length) {
      const e = node("div", undefined, "live-grid-empty");
      e.innerHTML = '<span class="live-grid-icon">' + reelIcon("live") + '</span><b>Chưa có ai đang live</b><p>Các buổi trực tiếp sẽ xuất hiện tại đây.</p>';

      box.append(e);
    } else {
      box.append(node("p", "● " + rooms.length + " buổi đang live", "live-grid-count"));
      const grid = node("div", undefined, "live-grid-cards");
      for (const r of rooms) {
        const card = node("button", undefined, "live-card " + hue(r.hostId));
        card.type = "button";
        const top = node("span", undefined, "live-card-top");
        top.append(node("b", "LIVE", "live-card-badge"), node("span", "👁 " + r.viewers, "live-card-viewers"));
        const face = avatar({ id: r.hostId, name: r.host, avatar: r.avatar });
        face.classList.add("live-card-avatar");
        const info = node("span", undefined, "live-card-info");
        info.append(node("b", r.title), node("small", r.host));
        card.append(top, face, info);
        card.onclick = async () => { await navigate("live"); joinLiveRoom(r.id); };
        grid.append(card);
      }
      box.append(grid);
    }
    refreshTimer = setTimeout(draw, 8000);
  };
  await draw();
}
async function shorts(panel, isCurrent = () => true, feed = "recommended") {
  videoFeed = feed;
  const heading = node("div", undefined, "view-head");
  heading.append(node("h2", "Video"), node("p", "Video ngắn từ cộng đồng. Muốn trò chuyện trực tiếp? Mở mục Live.", "muted"));
  panel.append(heading);
  // Thanh tạo video: quay bằng camera (có hiệu ứng) hoặc tải video có sẵn.
  const toBase64 = (blob) =>
    new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(String(r.result).replace(/^data:[^;]*;/, "data:video/mp4;"));
      r.onerror = reject;
      r.readAsDataURL(blob);
    });
  const postVideo = async (blob, caption) => {
    const data = await toBase64(blob);
    await uploadJson("/shorts", { data, caption }, (percent) => {
      status(percent < 0 ? "Đang chuẩn bị video…" : percent < 100 ? `Đang tải video lên ${percent}%…` : "Đang xử lý video…");
    });
    status("Đã đăng video.");
    await navigate("shorts");
  };
  const upload = node("div", undefined, "create-bar");
  const rec = node("button", "🎥 Quay video", "create-rec");
  rec.type = "button";
  rec.onclick = async () => {
    await openCamera();
  };
  const pick = node("label", undefined, "file-pick");
  const file = node("input");
  file.type = "file";
  file.accept = "video/mp4";
  file.setAttribute("aria-label", "Tải video MP4 có sẵn");
  pick.append(file, node("span", "📁 Tải video lên"));
  file.onchange = async () => {
    const f = file.files[0];
    if (!f) return;
    const caption = prompt("Chú thích cho video (có thể để trống):", "") ?? null;
    if (caption === null) return void (file.value = "");
    try {
      status("Đang tải video lên…");
      await postVideo(f, caption);
    } catch (e) {
      status(e.message);
    } finally {
      file.value = "";
    }
  };
  // Quay/tải video nằm trong Kinnect Studio (nút "+" giữa thanh dưới) nên không lặp nút ở đây.
  const tabs = node("div", undefined, "reel-feed-tabs");
  tabs.setAttribute("role", "group");tabs.setAttribute("aria-label", "Nguồn video");
  for (const [key, label] of [["recommended", "Đề xuất"], ["following", "Đang theo dõi"]]) {
    const button = node("button", label);button.type = "button";
    button.classList.toggle("active", feed === key);button.setAttribute("aria-pressed", String(feed === key));
    button.onclick = () => navigate("shorts", { feed: key }).catch(e => status(e.message));
    tabs.append(button);
  }
  const reel = node("div", undefined, "reel");
  const liveShortcut=node("button","● Trực tiếp","reel-live-shortcut");liveShortcut.type="button";liveShortcut.setAttribute("aria-label","Các buổi đang live");liveShortcut.classList.toggle("active",feed==="live");liveShortcut.onclick=()=>navigate("shorts",{feed:"live"}).catch(e=>status(e.message));tabs.prepend(liveShortcut);
  const viewportRoot=$("social-panel");
  let viewportFrame=0;
  const syncViewport=()=>{cancelAnimationFrame(viewportFrame);viewportFrame=requestAnimationFrame(()=>{if(!reel.isConnected)return;const viewport=window.visualViewport;const height=viewport?.height||innerHeight,top=viewport?.offsetTop||0;viewportRoot.style.setProperty("--reel-viewport-height",height+"px");viewportRoot.style.setProperty("--reel-viewport-top",top+"px");const bounds=reel.getBoundingClientRect(),nav=$("app")?.querySelector(":scope > nav"),navRect=nav?.getBoundingClientRect();const bottom=Math.min(top+height,navRect&&innerWidth<1000&&getComputedStyle(nav).position==="fixed"?navRect.top:top+height);const index=reel.clientHeight?Math.round(reel.scrollTop/reel.clientHeight):0;viewportRoot.style.setProperty("--reel-available-height",Math.max(0,bottom-bounds.top)+"px");reel.scrollTop=index*reel.clientHeight;});};
  panel.append(tabs, reel);
  if (feed === "live") { if (tab === "shorts") document.body.dataset.reel = "ready"; await liveGrid(reel, isCurrent); return; }
  const requestedVideo = new URL(location.href).searchParams.get("video");
  const { shorts: items } = await api("/shorts?feed=" + feed + (requestedVideo && feed!=="following" ? "&video="+encodeURIComponent(requestedVideo) : ""));
  if (!isCurrent()) return;
  const requested = new URL(location.href).searchParams.get("video");
  const target = items.findIndex(item => item.id === requested);
  if (target > 0) items.unshift(...items.splice(target, 1));
  if (tab === "shorts") document.body.dataset.reel = items.length ? "ready" : "empty";
  if (!items.length) {
    const following=feed==='following';
    const box=empty('🎬',following?'Chưa có video từ người bạn theo dõi':'Chưa có video nào',following?'Theo dõi người có video hoặc xem các video được đề xuất.':'Bấm + để quay video đầu tiên.');
    box.classList.add('reel-empty');
    if(following){
      box.append(action('Xem video đề xuất',()=>navigate('shorts',{feed:'recommended'}),'primary'));
      try{
        const recommended=await api('/shorts?feed=recommended');if(!isCurrent())return;
        const authors=new Map();for(const item of recommended.shorts||[])if(item.author.id!==me.id&&!item.author.following)authors.set(item.author.id,item.author);
        if(authors.size){const creators=node('section',undefined,'following-creators');creators.setAttribute('aria-label','Người có video để theo dõi');creators.append(node('h4','Theo dõi để xem video'));for(const u of [...authors.values()].slice(0,4)){const row=node('div',undefined,'following-creator'),person=node('button',undefined,'following-creator-person');person.type='button';person.setAttribute('aria-label','Xem trang của '+u.name);person.append(avatar(u),node('strong',u.name));person.onclick=()=>navigate('profile',{user:u.id});const follow=action('Theo dõi',async()=>{follow.disabled=true;try{await api('/users/'+u.id+'/follow','POST',{});await navigate('shorts',{feed:'following'});}catch(e){status(e.message);follow.disabled=false;}},'secondary');row.append(person,follow);creators.append(row);}box.append(creators);}
      }catch{}
    }else box.append(action('+ Quay video',()=>openCamera(),'empty-cta'));
    reel.append(box);return;
  }
  const watcher = new IntersectionObserver(
    (entries) => {
      for (const e of entries) {
        const v = e.target.querySelector("video");
        if (e.isIntersecting) v.play().catch(() => {
          if (!v.isConnected) return;
          v.muted = true;
          v.play().catch(() => { v.controls = true; });
        });
        else v.pause();
      }
    },
    { threshold: 0.6 },
  );
  const resizeObserver=new ResizeObserver(syncViewport);
  for(const element of [tabs,$("app")?.querySelector(":scope > header"),$("app")?.querySelector(":scope > nav")])if(element)resizeObserver.observe(element);
  window.addEventListener("resize",syncViewport);
  window.visualViewport?.addEventListener("resize",syncViewport);
  window.visualViewport?.addEventListener("scroll",syncViewport);
  cleanupShorts = () => {
    cancelAnimationFrame(viewportFrame);
    resizeObserver.disconnect();
    window.removeEventListener("resize",syncViewport);
    window.visualViewport?.removeEventListener("resize",syncViewport);
    window.visualViewport?.removeEventListener("scroll",syncViewport);
    for(const name of ["--reel-available-height","--reel-viewport-height","--reel-viewport-top"])viewportRoot.style.removeProperty(name);
    closeReelComments();
    watcher.disconnect();
    for (const video of reel.querySelectorAll("video")) video.pause();
    cleanupShorts = () => {};
  };
  for (const s of items) {
    const slide = node("article", undefined, "reel-item");
    const v = node("video");
    v.src = s.video;
    v.loop = true;
    v.muted = reelMuted;
    v.playsInline = true;
    v.setAttribute("controlslist", "nofullscreen");
    v.preload = "metadata";
    v.addEventListener("error", () => {
      if (!slide.querySelector(".video-error")) {
        const message = node("div", "Không phát được video này. Hãy thử video khác hoặc kiểm tra kết nối.", "video-error");
        message.setAttribute("role", "status");
        slide.append(message);
      }
    });
    let controlsTimer=0;
    const showControls=()=>{clearTimeout(controlsTimer);slide.classList.remove("controls-hidden");if(!v.paused)controlsTimer=setTimeout(()=>slide.classList.add("controls-hidden"),3000);};
    v.addEventListener("play",showControls);v.addEventListener("pause",()=>{clearTimeout(controlsTimer);slide.classList.remove("controls-hidden");});
    slide.addEventListener("pointermove",e=>{if(e.pointerType==="mouse")showControls();});
    v.onclick = () => { if(slide.classList.contains("controls-hidden")){showControls();return;}if (v.paused) v.play().catch(e => status(e.message)); else v.pause(); };
    const meta = node("div", undefined, "reel-meta");
    meta.append(node("strong", "@" + s.author.username), node("p", s.caption));
    const side = reelActions({ s, video: v, api, status, avatar, personLink,
      report: () => report("short", s.id) });
    slide.append(v, meta, side);
    reel.append(slide);
    watcher.observe(slide);
  }
  syncViewport();
}
async function rail() {
  const box = $("rail");
  if (!box) return;
  const { users } = await api("/discover?q=");
  const list = node("section", undefined, "rail-box");
  list.append(node("h3", "Gợi ý kết bạn"));
  for (const u of users.slice(0, 5)) {
    const row = node("div", undefined, "rail-row");
    const who = node("button", undefined, "rail-who");
    who.type = "button";
    who.append(node("strong", u.name), node("small", u.score ? u.score + " sở thích chung" : "@" + u.username));
    who.onclick = () => navigate("profile", { user: u.id });
    const chat = node("button", "Nhắn", "ghost");
    chat.type = "button";
    chat.onclick = () => openChat(u).catch((e) => status(e.message));
    row.append(avatar(u), who, chat);
    list.append(row);
  }
  if (!users.length) list.append(node("p", "Chưa có gợi ý.", "muted"));
  const go = node("button", "Xem tất cả", "ghost wide");
  go.type = "button";
  go.onclick = () => navigate("discover");
  list.append(go);
  const foot = node("nav", undefined, "rail-foot");
  foot.setAttribute("aria-label", "Thông tin Kinnect");
  for (const [label, href] of [
    ["Giới thiệu", "https://kinnect.io.vn/"],
    ["Cộng đồng", "https://kinnect.io.vn/community"],
    ["Quyền riêng tư", "https://kinnect.io.vn/privacy"],
    ["Trợ giúp", "https://kinnect.io.vn/support"],
  ]) {
    const a = node("a", label);
    a.href = href;
    a.target = "_blank";
    a.rel = "noopener";
    foot.append(a);
  }
  foot.append(node("span", "© 2026 Kinnect · Bản thử nghiệm 18+"));
  const keep = box.querySelector(".platforms");
  box.replaceChildren(list);
  if (keep) box.append(keep);
  box.append(foot);
}


function friendshipAction(u,refresh){
 if(u.friendship==='friends'){const menu=more([['Hủy kết bạn',async()=>{if(!confirm('Hủy kết bạn với '+u.name+'?'))return;await api('/users/'+u.id+'/friendship','DELETE',{});await refresh();}]],'Bạn bè');menu.classList.add('friendship-menu');menu.querySelector('summary').textContent='Bạn bè ▾';return menu;}
 const incoming=u.friendship==='incoming',outgoing=u.friendship==='outgoing';
 if(outgoing){const menu=more([['Hủy lời mời',async()=>{await api('/users/'+u.id+'/friend-request','DELETE',{});await refresh();}],...(u.following?[['Bỏ theo dõi',async()=>{await api('/users/'+u.id+'/follow','DELETE',{});await refresh();}]]:[])],'Lời mời đã gửi');menu.classList.add('friendship-menu');menu.querySelector('summary').textContent=u.following?'Đang theo dõi ▾':'Đã gửi lời mời ▾';return menu;}
 const button=action(incoming?'Xác nhận kết bạn':outgoing?'Hủy lời mời':'Kết bạn',async()=>{button.disabled=true;try{await api('/users/'+u.id+'/friend-request'+(incoming?'/respond':''),outgoing?'DELETE':'POST',incoming?{action:'accept'}:{});await refresh();}catch(e){status(e.message);button.disabled=false;}},outgoing?'secondary':'primary');return button;
}
function rememberProfilePrompt(){
 try{localStorage.setItem('kinnect-profile-prompt:'+me.id,'pending');}catch{}
}
function renderProfileCompletionPrompt(view){
 let pending=false;try{pending=localStorage.getItem('kinnect-profile-prompt:'+me.id)==='pending';}catch{}
 if(!pending)return;
 if(me.avatar&&me.bio&&me.interests?.length){try{localStorage.removeItem('kinnect-profile-prompt:'+me.id);}catch{}return;}
 const card=node('section',undefined,'profile-completion-prompt');card.setAttribute('aria-label','Hoàn thiện hồ sơ');
 const text=node('div',undefined,'profile-completion-copy');text.append(node('h2','Chào mừng bạn đến với Kinnect'),node('p','Thêm ảnh đại diện, giới thiệu và sở thích để mọi người dễ kết nối với bạn.'));
 const buttons=node('div',undefined,'profile-completion-actions');buttons.append(action('Hoàn thiện hồ sơ',()=>navigate('profile',{settings:true}),'primary'),action('Để sau',()=>{try{localStorage.removeItem('kinnect-profile-prompt:'+me.id);}catch{}card.remove();},'ghost'));card.append(text,buttons);view.prepend(card);
}
function screenBackButton() {
 const button=node('button',undefined,'screen-back app-back-button');button.type='button';button.setAttribute('aria-label','Quay lại');
 button.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m14 6-6 6 6 6"/></svg>';
 button.onclick=()=>goBack();return button;
}
async function friendsPage(panel,opts={}){
 const revision=navigationRevision;let section=opts.section||'friends',filter='all',payload=null,signature='',appliedQuery=opts.search||'';
 const heading=node('div',undefined,'view-head friends-heading');heading.append(screenBackButton(),node('h2','Bạn bè'));panel.append(heading);
 const tabs=node('div',undefined,'friends-tabs');tabs.setAttribute('role','tablist');tabs.setAttribute('aria-label','Kết nối bạn bè');panel.append(tabs);
 for(const [key,label] of [['friends','Bạn bè'],['following','Đang theo dõi'],['requests','Lời mời'],['suggestions','Đề xuất']]){const b=node('button',label,'secondary');b.type='button';b.setAttribute('role','tab');b.setAttribute('aria-selected',String(key===section));if(key==='requests'){const count=node('span','','friends-request-count');count.setAttribute('aria-hidden','true');count.hidden=true;b.append(count);}b.onclick=()=>{section=key;replaceNavigationOptions({section:key});for(const other of tabs.children)other.setAttribute('aria-selected',String(other===b));draw();};tabs.append(b);}
 const searchWrap=node('form',undefined,'friends-search-wrap'),searchIcon=node('button',undefined,'friends-search-icon secondary');searchIcon.type='submit';searchIcon.setAttribute('aria-label','Tìm bạn bè');searchIcon.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/></svg>';const search=node('input',undefined,'friends-search');search.type='search';search.value=appliedQuery;search.placeholder='Tìm tên hoặc @username';search.setAttribute('aria-label','Tìm trong bạn bè');search.autocomplete='off';searchWrap.onsubmit=e=>{e.preventDefault();appliedQuery=search.value.trim();replaceNavigationOptions({search:appliedQuery});draw();};searchWrap.append(search,searchIcon);panel.append(searchWrap);
 const filters=node('div',undefined,'friends-filters');filters.setAttribute('role','group');filters.setAttribute('aria-label','Trạng thái bạn bè');panel.append(filters);
 for(const [key,label] of [['all','Tất cả'],['online','Trực tuyến'],['offline','Ngoại tuyến']]){const b=node('button',label,'secondary');b.type='button';b.setAttribute('aria-pressed',String(key===filter));b.onclick=()=>{filter=key;for(const other of filters.children)other.setAttribute('aria-pressed',String(other===b));draw();};filters.append(b);}
 const list=node('div',undefined,'friends-list');list.setAttribute('aria-live','polite');panel.append(list);
 function row(u,mode){const card=node('article',undefined,'friend-row'),person=node('button',undefined,'friend-person');person.type='button';person.setAttribute('aria-label','Xem trang của '+u.name);const picture=node('span',undefined,'friend-picture');picture.append(avatar(u));if(u.isActive)picture.append(node('span',undefined,'friend-online-dot'));const text=node('span',undefined,'friend-copy');text.append(node('strong',u.name));const presence=u.activityShared===false?'Ẩn trạng thái':u.isActive?'Trực tuyến':'Ngoại tuyến';text.append(node('span',presence,'friend-presence '+(u.isActive?'is-online':'')));if(mode==='suggestions'&&(u.sharedInterests||u.sameCity))text.append(node('span',u.sharedInterests?u.sharedInterests+' sở thích chung':'Cùng thành phố','friend-reason'));person.append(picture,text);person.onclick=()=>navigate('profile',{user:u.id});const actions=node('div',undefined,'friend-row-actions');
 if(mode==='requests'&&u.friendship==='incoming'){actions.append(friendshipAction(u,()=>reload(true)),action('Xóa lời mời',async()=>{await api('/users/'+u.id+'/friend-request/respond','POST',{action:'decline'});await reload(true);},'secondary'));}
 else if(mode==='following'){actions.append(friendshipAction(u,()=>reload(true)),action('Bỏ theo dõi',async()=>{await api('/users/'+u.id+'/follow','DELETE',{});await reload(true);},'secondary'));}
 else if(mode==='friends')actions.append(action('Nhắn tin',()=>openChat(u),'secondary'),friendshipAction(u,()=>reload(true)));
 else {actions.append(friendshipAction(u,()=>reload(true)));if(mode==='suggestions')actions.append(action(u.following?'Đang theo dõi':'Theo dõi',async()=>{await api('/users/'+u.id+'/follow',u.following?'DELETE':'POST',{});await reload(true);},'secondary'));}
 card.append(person,actions);return card;}
 function draw(){if(!payload)return;filters.hidden=!['friends','following'].includes(section);list.replaceChildren();const q=appliedQuery.toLocaleLowerCase('vi');const matches=u=>(u.name+' @'+u.username).toLocaleLowerCase('vi').includes(q);
 if(section==='friends'&&!payload.friends.length&&filter==='all'){list.append(node('h3','Đề xuất kết bạn'));const suggestions=payload.suggestions.filter(matches);for(const u of suggestions)list.append(row(u,'suggestions'));if(!suggestions.length)list.append(node('p','Chưa có đề xuất phù hợp.','friends-empty'));return;}
 if(section==='requests'){for(const [title,users] of [['Lời mời đã nhận',payload.incoming],['Lời mời đã gửi',payload.outgoing]]){const visible=users.filter(matches);if(!visible.length)continue;list.append(node('h3',title+' ('+visible.length+')'));for(const u of visible)list.append(row(u,'requests'));}}
 else{const users=(section==='friends'?payload.friends:section==='following'?payload.following:payload.suggestions).filter(matches).filter(u=>!['friends','following'].includes(section)||filter==='all'||filter==='online'&&u.isActive||filter==='offline'&&!u.isActive&&u.activityShared!==false);users.sort((a,b)=>Number(b.isActive)-Number(a.isActive));for(const u of users)list.append(row(u,section));}
 if(!list.children.length){list.append(node('p',appliedQuery?'Không tìm thấy bạn bè.':section==='requests'?'Chưa có lời mời kết bạn.':section==='suggestions'?'Chưa có đề xuất mới.':filter==='online'?'Chưa có bạn bè trực tuyến.':filter==='offline'?'Chưa có bạn bè ngoại tuyến.':'Danh sách bạn bè đang trống.','friends-empty'));if(section==='friends'&&filter==='all')list.append(action('Xem đề xuất kết bạn',()=>tabs.children[3].click(),'primary'));}}
 async function reload(force=false){const [friends,requests,suggestions,following]=await Promise.all([api('/friends'),api('/friend-requests'),api('/friend-suggestions'),api('/users/'+me.id+'/following')]);if(revision!==navigationRevision)return;payload={friends:friends.users,incoming:requests.incoming,outgoing:requests.outgoing,suggestions:suggestions.users,following:following.users};const badge=$('friends-count');if(badge)badge.textContent=(requests.incoming.length||notificationCache.some(n=>n.kind==='follow'&&!n.seen))?'●':'';const tabBadge=tabs.querySelector('.friends-request-count');if(tabBadge){tabBadge.textContent=requests.incoming.length?'●':'';tabBadge.hidden=!requests.incoming.length;}const next=JSON.stringify(payload);if(force||next!==signature){signature=next;draw();}}
 friendsRefresh=()=>reload().catch(()=>{});await reload();
}
async function accountHome(panel) {
  me=(await api('/me')).user;
  const head=node('div',undefined,'view-head settings-heading');
  head.append(node('div'));
  head.firstChild.append(node('h2','Tài khoản'),node('p','Quản lý hồ sơ và tùy chọn tài khoản.','muted'));
  panel.append(head);
  const identity=node('button',undefined,'social-card account-home-profile secondary');
  identity.type='button';identity.setAttribute('aria-label','Mở trang cá nhân của '+me.name);
  identity.append(avatar(me));
  const who=node('span',undefined,'account-home-who');who.append(node('strong',me.name),node('small','@'+me.username,'muted'));
  identity.append(who,node('span','›','account-home-arrow'));identity.onclick=()=>navigate('profile');panel.append(identity);
  const section=node('section',undefined,'account-home-section');section.append(node('h3','Tài khoản'));
  const settings=action('Cài đặt tài khoản',()=>navigate('settings'),'social-card account-home-link secondary');
  settings.append(node('small','Mật khẩu, quyền riêng tư và thông báo','muted'));
  const install=action('Cài Kinnect cho iOS',()=>window.dispatchEvent(new Event('kinnect-install-ios')),'social-card account-home-link secondary');
  install.append(node('small','Thêm Kinnect vào màn hình chính iPhone hoặc iPad','muted'));
  section.append(settings,install);
  if(me.role==='admin'){
    const adminLink=action('Quản trị',()=>navigate('admin'),'social-card account-home-link secondary');
    adminLink.append(node('small','Xem yêu cầu quên mật khẩu và cấp mật khẩu tạm','muted'));
    const dot=node('span','','admin-request-dot');dot.setAttribute('aria-hidden','true');dot.hidden=true;adminLink.append(dot);
    section.append(adminLink);
    api('/notifications').then(result=>{if(adminLink.isConnected)dot.hidden=!result.passwordResetsPending;}).catch(()=>{});
  }
  panel.append(section);
  const help=node('section',undefined,'account-home-section');help.append(node('h3','Hỗ trợ & thông tin'));
  const links=node('div',undefined,'social-card account-home-links');
  for(const [label,url] of [['Giới thiệu Kinnect','https://kinnect.io.vn/'],['Quy tắc cộng đồng','https://kinnect.io.vn/community'],['Quyền riêng tư','https://kinnect.io.vn/privacy'],['Trợ giúp','https://kinnect.io.vn/support']]){const link=node('a',label);link.href=url;link.target='_blank';link.rel='noopener';links.append(link);}
  help.append(links);panel.append(help);
  panel.append(action('Đăng xuất',()=>$('logout').click(),'danger-item account-home-logout secondary'));
}
async function accountSettings(panel) {
 me=(await api('/me')).user;
 const header=node('div',undefined,'view-head settings-heading');header.append(action('‹',()=>goBack('profile'),'settings-back'),node('div'));header.lastChild.append(node('h2','Cài đặt & quyền riêng tư'),node('p','Quản lý tài khoản theo cách của bạn.','muted'));header.firstChild.setAttribute('aria-label','Quay lại trang cá nhân');panel.append(header);
 const search=node('input',undefined,'settings-search');search.type='search';search.placeholder='Tìm trong cài đặt';search.setAttribute('aria-label','Tìm trong cài đặt');panel.append(search);
 const identity=node("section",undefined,"social-card account-settings-id");identity.append(avatar(me),node("strong",me.name),action("Chỉnh sửa tài khoản",()=>navigate("profile",{settings:true}),"ghost"));panel.append(identity);
 const iosInstall=node("section",undefined,"social-card ios-install-settings");iosInstall.append(node("h3","Cài Kinnect cho iOS"),node("p","Thêm biểu tượng Kinnect có logo trên iPhone hoặc iPad. Quét mã QR từ máy tính hoặc mở hướng dẫn bằng Safari.","muted"),action("Mở hướng dẫn cài iOS",()=>window.dispatchEvent(new Event("kinnect-install-ios")),"primary"));panel.append(iosInstall);
    // Đổi mật khẩu
    const pw = node("form", undefined, "social-card");
    pw.append(node("h3", "Đổi mật khẩu"));
    const current = field(pw, "Mật khẩu hiện tại", "", "password");
    current.autocomplete = "current-password";
    current.required = true;
    const next = field(pw, "Mật khẩu mới (tối thiểu 6 ký tự)", "", "password");
    next.autocomplete = "new-password";
    next.minLength = 6;
    next.maxLength = 128;
    next.required = true;
    const pwSave = node("button", "Đổi mật khẩu");
    pw.append(pwSave);
    pw.onsubmit = async (e) => {
      e.preventDefault();
      pwSave.disabled = true;
      try {
        await api("/me/password", "POST", { current: current.value, next: next.value });
        current.value = next.value = "";
        status("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.");
      } catch (e) {
        status(e.message);
      } finally {
        pwSave.disabled = false;
      }
    };
    // Người đã chặn
    const blocks = node("section", undefined, "social-card");
    blocks.append(node("h3", "Người đã chặn"));
    const { users } = await api("/blocks");
    if (!users.length) blocks.append(node("p", "Bạn chưa chặn ai.", "muted"));
    for (const b of users) {
      const line = node("div", undefined, "block-row");
      line.append(avatar(b), node("span", b.name));
      line.append(
        action("Bỏ chặn", async () => {
          await api("/users/" + b.id + "/block", "DELETE", {});
          await navigate("settings");
        }),
      );
      blocks.append(line);
    }

 panel.append(pw,blocks);
 const recoveryEmail=await recoveryEmailPanel();
 const quick=node("section",undefined,"social-card");quick.append(node("h3","Đăng nhập trên thiết bị này"),node("p","Quản lý quyền chạm hồ sơ để đăng nhập nhanh.","muted"));
 const locationControl=node("section",undefined,"social-card");locationControl.append(node("h3","Vị trí"),node("p","Tự động làm mới người ở gần trong lúc sử dụng app.","muted"));
 const locationEnabled=me.hasLocation;
 locationControl.append(action(locationEnabled?"Tắt vị trí":"Bật vị trí",async()=>{if(locationEnabled){me=(await api("/me/location","PATCH",{enabled:false})).user;rememberLocation(false);stopLocationTracking();await navigate("settings");}else{await navigate("discover");const enable=document.querySelector(".nearby-consent button");enable?.click();}}));panel.append(locationControl);
 const remembered=(await api("/remembered")).accounts;
 if(remembered.some(account=>account.id===me.id))quick.append(action("Tắt đăng nhập nhanh trên thiết bị này",async()=>{await api("/remembered/"+me.id,"DELETE",{});status("Đã gỡ quyền đăng nhập nhanh.");await navigate("settings");}));else quick.append(node("p","Tài khoản này chưa bật đăng nhập nhanh.","muted"));panel.append(quick);
 const visibility=node('section',undefined,'social-card settings-visibility');visibility.append(node('h3','Quyền hiển thị'),node('p','Chọn những thông tin bạn muốn chia sẻ.','muted'));
 for(const [key,label,description] of [['discoverable','Xuất hiện trong Khám phá','Cho phép thành viên khác tìm thấy hồ sơ của bạn.'],['showActivity','Trạng thái hoạt động','Hiển thị khi bạn đang online và lần hoạt động gần nhất.'],['identityPublic','Chia sẻ thông tin danh tính','Hiển thị giới tính, xu hướng và vai trò trên trang cá nhân.']]){const row=node('label',undefined,'settings-switch'),text=node('span'),input=node('input');input.type='checkbox';input.checked=key==='showActivity'?me[key]!==false:!!me[key];input.setAttribute('aria-label',label);text.append(node('strong',label),node('small',description));row.append(text,input);input.onchange=async()=>{const before=!input.checked;input.disabled=true;try{me=(await api('/me','PATCH',{[key]:input.checked})).user;status('Đã lưu '+label.toLowerCase()+'.');}catch(e){input.checked=before;status(e.message);}finally{input.disabled=false;}};visibility.append(row);}
 const notificationSettings=node('section',undefined,'social-card settings-notifications');notificationSettings.append(node('h3','Thông báo và âm thanh'));
 const permissionDescription=node('p','Nhận thông báo khi Kinnect đang mở, kể cả lúc bạn chuyển sang tab khác.','muted');
 const permissionButton=node('button',undefined,'secondary');permissionButton.type='button';permissionButton.setAttribute('aria-label','Bật thông báo trình duyệt');
 function updatePermission(){const supported='Notification' in window,permission=supported?Notification.permission:'unsupported';permissionButton.disabled=permission!=='default';permissionButton.textContent=permission==='granted'?'Đã bật thông báo':permission==='denied'?'Thông báo đang bị chặn':!supported?'Trình duyệt chưa hỗ trợ':'Bật thông báo';permissionButton.setAttribute('aria-label',permission==='default'?'Bật thông báo trình duyệt':permissionButton.textContent);if(permission==='denied')permissionDescription.textContent='Cho phép thông báo trong phần quyền của trang trên trình duyệt.';if(!supported)permissionDescription.textContent='Trên iPhone, hãy thêm Kinnect vào màn hình chính để dùng thông báo.';}
 permissionButton.onclick=async()=>{permissionButton.disabled=true;await requestBrowserNotifications();updatePermission();};updatePermission();notificationSettings.append(permissionDescription,permissionButton);
 const soundRow=node('label',undefined,'settings-switch'),soundCopy=node('span'),soundToggle=node('input');soundCopy.append(node('strong','Âm tin nhắn'),node('small','Phát âm báo khi nhận tin nhắn và thông báo trong ứng dụng.'));soundToggle.type='checkbox';soundToggle.checked=soundEnabled;soundToggle.setAttribute('aria-label','Âm tin nhắn');soundToggle.onchange=()=>{soundEnabled=soundToggle.checked;try{localStorage.setItem('kinnect-notification-sound',soundEnabled?'on':'off');}catch{}};soundRow.append(soundCopy,soundToggle);notificationSettings.append(soundRow);
 const groups=[];
 function group(title,items){const section=node('section',undefined,'settings-group');section.append(node('h3',title));for(const [label,description,icon,content] of items){const details=node('details',undefined,'settings-entry'),summary=node('summary'),glyph=node('span',undefined,'settings-entry-icon');glyph.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+icon+'</svg>';const copy=node('span',undefined,'settings-entry-copy');copy.append(node('strong',label),node('small',description));const arrow=node('span','›','settings-entry-arrow');arrow.setAttribute('aria-hidden','true');summary.append(glyph,copy,arrow);details.append(summary,content);section.append(details);}groups.push(section);panel.append(section);}
 const userIcon='<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0116 0v2"/>';
 group('Tài khoản & bảo mật',[
 ['Email khôi phục','Nhận mã OTP khi quên mật khẩu',userIcon,recoveryEmail],
 ['Mật khẩu và đăng nhập','Đổi mật khẩu để bảo vệ tài khoản','<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 018 0v3"/>',pw],
 ['Đăng nhập nhanh','Quản lý đăng nhập trên thiết bị này','<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 18h4"/>',quick]]);
 group('Đối tượng & quyền riêng tư',[
 ['Quyền hiển thị','Khám phá, hoạt động và thông tin cá nhân',userIcon,visibility],
 ['Chặn','Quản lý những người bạn đã chặn','<circle cx="12" cy="12" r="9"/><path d="m6 6 12 12"/>',blocks],
 ['Vị trí','Quản lý tính năng tìm người ở gần','<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1116 0Z"/><circle cx="12" cy="10" r="3"/>',locationControl]]);
 group('Tùy chọn',[['Thông báo và âm thanh','Thông báo trình duyệt và âm tin nhắn','<path d="M6 16V10a6 6 0 0112 0v6l2 2H4Z"/><path d="M10 21h4"/>',notificationSettings]]);
 group('Ứng dụng & thiết bị',[
 ['Cài Kinnect cho iOS','Thêm Kinnect vào màn hình chính iPhone','<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M9 11h6m-3-3v6"/>',iosInstall]]);
 const noResults=node('p','Không tìm thấy cài đặt phù hợp.','settings-no-results');noResults.hidden=true;panel.append(noResults);
 search.oninput=()=>{const q=search.value.trim().toLocaleLowerCase('vi');let count=0;for(const section of groups){let visible=0;for(const entry of section.querySelectorAll('.settings-entry')){entry.hidden=!!q&&!entry.textContent.toLocaleLowerCase('vi').includes(q);if(!entry.hidden){visible++;count++;}if(q&&!entry.hidden)entry.open=true;}section.hidden=!visible;}noResults.hidden=count>0;};

}


let notificationCache = [], knownNotificationIds = new Set(), notificationBaseline = false;
let unreadRefreshPending = false;
let unreadRequest = null, activityTimer = null, notificationPanel = null, notificationFilter = "all";
let audioContext;
let soundEnabled = true;
try { soundEnabled = localStorage.getItem("kinnect-notification-sound") !== "off"; } catch {}
document.addEventListener("pointerdown", () => {
  if (!audioContext && (window.AudioContext || window.webkitAudioContext)) audioContext = new (window.AudioContext || window.webkitAudioContext)();
  if (audioContext?.state === "suspended") audioContext.resume().catch(() => {});
}, { passive: true });
function notificationSound() {
  if (!soundEnabled || !audioContext || audioContext.state !== "running" || document.hidden) return;
  const tone = audioContext.createOscillator(), volume = audioContext.createGain(), now = audioContext.currentTime;
  tone.type = "sine"; tone.frequency.setValueAtTime(880, now); tone.frequency.setValueAtTime(1174, now + .12);
  volume.gain.setValueAtTime(.001, now); volume.gain.exponentialRampToValueAtTime(.08, now + .02); volume.gain.exponentialRampToValueAtTime(.001, now + .3);
  tone.connect(volume); volume.connect(audioContext.destination); tone.start(now); tone.stop(now + .32);
}
function closeNotificationCenter(consumeHistory = false) {
  if(consumeHistory){dismissHeaderPopup();return;}
  if (notificationPanel) notificationPanel.hidden = true;
  $("notification-bell")?.setAttribute("aria-expanded", "false");
  syncHeaderPanelState();
}
function requestBrowserNotifications() {
  if (!("Notification" in window)) { status("Trình duyệt này chưa hỗ trợ thông báo. Trên iPhone, hãy thêm Kinnect vào màn hình chính trước."); return; }
  if (Notification.permission === "denied") { status("Thông báo đang bị chặn. Bạn có thể bật lại trong phần quyền của trang trên trình duyệt."); return; }
  return Notification.requestPermission().then(permission => {
    if (permission === "granted") { document.querySelector(".notification-optin")?.remove(); status("Đã bật thông báo khi Kinnect đang mở."); }
    else status("Bạn vẫn nhận được thông báo ở biểu tượng chuông trong app.");
  }).catch(() => status("Chưa bật được thông báo trình duyệt. Bạn vẫn xem được thông báo trong app."));
}
async function openNotification(n) {
  closeNotificationCenter();
  if (!n.seen) await api("/notifications", "POST", { ids: [n.id] });
  if(n.kind==="friend_request")await navigate("friends",{section:"requests"});
  else if(n.kind==="friend_accepted")await navigate("friends");
  else if(n.kind==="private_request")await openChat(n.actor);
  else if(n.kind.startsWith("private_"))await openChat(n.actor);
  else if (n.kind === "message" || n.kind === "missed_call") await openChat(n.actor);
  else if(n.kind === "group_message")await openGroupChat(n.ref);
  else if (n.kind === "like" || n.kind === "comment") await navigate("profile",{post:n.ref});
  else if (n.kind === "gift") await navigate("live");
  else await navigate("profile", { user: n.actor.id });
  await refreshUnread();
}
function renderNotificationCenter() {
  if (!notificationPanel) return;
  const active=!notificationPanel.hidden&&notificationPanel.contains(document.activeElement)?document.activeElement.closest('button'):null;
  const focusKey=active?{id:active.dataset.notificationId,label:active.getAttribute('aria-label'),text:active.textContent}:null;
  const scrollTop=notificationPanel.querySelector('.notification-center-list')?.scrollTop||0;
  notificationPanel.replaceChildren();
  const head = node("div", undefined, "notification-center-head"); const back=node('button',undefined,'header-panel-back app-back-button');back.type='button';back.setAttribute('aria-label','Đóng thông báo');back.innerHTML=accountPanelBack.innerHTML;back.onclick=()=>dismissHeaderPopup();head.append(back,node("h2", "Thông báo"));
  const read = action("Đánh dấu đã đọc", async () => { await api("/notifications", "POST", {}); await refreshUnread(); }, "ghost");
  head.append(read); notificationPanel.append(head);
  const tabs = node("div", undefined, "chips");
  for (const [label, value] of [["Tất cả", "all"], ["Chưa đọc", "unread"]]) { const b = node("button", label, "chip" + (notificationFilter === value ? " active" : "")); b.type = "button"; b.onclick = () => { notificationFilter = value; renderNotificationCenter(); }; tabs.append(b); }
  notificationPanel.append(tabs);
  const list = node("div", undefined, "notification-center-list");
  const items = notificationCache.filter(n => notificationFilter !== "unread" || !n.seen);
  for (const n of items) {
    const row = node("button", undefined, "list-row note-row" + (n.seen ? "" : " unread")); row.type = "button";
    const text = node("div", undefined, "row-text"); const line = node("p"); line.append(node("b", n.actor.name), " ", node("span", NOTE_TEXT[n.kind] || "có hoạt động mới."));
    text.append(line, node("small", timeAgo(n.created), "meta")); row.append(avatar(n.actor), text); if (!n.seen) row.append(node("span", undefined, "dot"));
    row.dataset.notificationId=n.id;row.onclick = () => openNotification(n).catch(e => status(e.message)); list.append(row);
  }
  if (!items.length) list.append(empty("🔔", notificationFilter === "unread" ? "Bạn đã xem hết thông báo" : "Chưa có thông báo", "Lượt theo dõi và tin nhắn mới sẽ xuất hiện ở đây."));
  notificationPanel.append(list);
  list.scrollTop=scrollTop;
  if(focusKey){const target=[...notificationPanel.querySelectorAll('button')].find(button=>focusKey.id?button.dataset.notificationId===focusKey.id:focusKey.label?button.getAttribute('aria-label')===focusKey.label:button.textContent===focusKey.text);target?.focus({preventScroll:true});}
}
// Chấm trên chuông chỉ báo thông báo chưa xem mới đến kể từ lần mở khung gần nhất.
// Số chưa đọc (#unread) và trạng thái "seen" phía máy chủ giữ nguyên.
const bellOpenedKey = "kinnect-bell-opened";
function bellOpenedIds() { try { return new Set(JSON.parse(localStorage.getItem(bellOpenedKey) || "[]")); } catch { return new Set(); } }
function updateBellDot() { const opened = bellOpenedIds(); $("notification-bell")?.classList.toggle("bell-fresh", notificationCache.some(n => !n.seen && !opened.has(n.id))); }
function markBellOpened() { try { localStorage.setItem(bellOpenedKey, JSON.stringify(notificationCache.filter(n => !n.seen).map(n => n.id).slice(-500))); } catch {} updateBellDot(); }
function initializeNotificationCenter() {
  const bell = $("notification-bell");
  if (!notificationPanel) {
    notificationPanel = node("section", undefined, "notification-center"); notificationPanel.id = "notification-center"; notificationPanel.hidden = true; notificationPanel.setAttribute("role", "dialog"); notificationPanel.setAttribute("aria-label", "Thông báo"); notificationPanel.removeAttribute("aria-modal"); $("app").append(notificationPanel);
    document.addEventListener("click", event => { if (!notificationPanel.hidden && !event.composedPath().includes(notificationPanel) && !event.composedPath().includes(bell)) dismissHeaderPopup(); });
    document.addEventListener("keydown", event => { if (event.key === "Escape" && !notificationPanel.hidden) { dismissHeaderPopup(); bell.focus(); } });
  }
  bell.onclick = () => openNotificationCenter();
}
// Mở popup Thông báo đồng bộ với history-state (giống menu Tài khoản).
function openNotificationCenter() {
  if (!notificationPanel) return;
  menu(false);
  showHeaderPopup("notifications");
  notificationPanel.hidden = false;
  positionHeaderPopup(notificationPanel);
  $("notification-bell").setAttribute("aria-expanded", "true");
  markBellOpened();
  renderNotificationCenter();
  syncHeaderPanelState();
  // Chuyển focus vào nút Đóng để truy cập bằng bàn phím/trình đọc màn hình.
  notificationPanel.querySelector(".header-panel-back")?.focus();
}
async function showSystemNotification(n) {
  if (!("Notification" in window) || Notification.permission !== "granted" || !document.hidden) return;
  const title = n.kind === "message" ? "Tin nhắn mới từ " + n.actor.name : "Thông báo từ " + n.actor.name;
  const options = { body: n.kind === "message" ? "Bạn có tin nhắn mới trên Kinnect." : NOTE_TEXT[n.kind] || "Có hoạt động mới trên Kinnect.", icon: "/kinnect-icon-192.png", tag: "kinnect-" + n.id, data: { url: n.kind === "message" ? "/?chat=" + encodeURIComponent(n.actor.id) : "/" } };
  try {
    const registration = await navigator.serviceWorker?.getRegistration();
    if (registration?.active) await registration.showNotification(title, options);
    else { const notification = new Notification(title, options); notification.onclick = () => { window.focus(); notification.close(); openNotification(n).catch(e => status(e.message)); }; }
  } catch {}
}
async function refreshUnread(realtime = false) {
  if (!me) return;
  if (unreadRequest) {
    if (realtime) unreadRefreshPending = true;
    return unreadRequest;
  }
  const userId = me.id;
  unreadRequest = (async () => {
    const { notifications,friendRequestsPending,passwordResetsPending } = await api("/notifications");
    if (!me || me.id !== userId) return;
    const friendBadge=$("friends-count");if(friendBadge)friendBadge.textContent=(friendRequestsPending||notifications.some(n=>n.kind==="follow"&&!n.seen))?"●":"";
    for(const id of ['admin-menu','admin-tab']){const target=$(id);if(!target)continue;let dot=target.querySelector('.admin-request-dot');if(!dot){dot=node('span','','admin-request-dot');dot.setAttribute('aria-hidden','true');target.append(dot);}dot.hidden=me.role!=='admin'||!passwordResetsPending;target.setAttribute('aria-label',passwordResetsPending?'Quản trị · Có yêu cầu quên mật khẩu đang chờ':'Quản trị');}
    adminRequestsRefresh?.();
    const fresh = notificationBaseline ? notifications.filter(n => !n.seen && !n.muted && !knownNotificationIds.has(n.id)) : [];
    notificationCache = notifications; notificationBaseline = true;
    notifications.forEach(n => knownNotificationIds.add(n.id));
    if (knownNotificationIds.size > 500) knownNotificationIds = new Set(notifications.map(n => n.id));
    const count = notifications.filter(n => !n.seen).length;
    $("unread").textContent = count ? (count > 99 ? "99+" : String(count)) : "";
    if ($("notification-bell")?.getAttribute("aria-expanded") === "true") markBellOpened(); else updateBellDot();
    const inbox = document.querySelector('#app [data-tab="inbox"]'); inbox.setAttribute("aria-label", "Tin nhắn");
    let badge = inbox.querySelector(".nav-count"); if (!badge) { badge = node("span", "", "nav-count"); badge.setAttribute("aria-hidden", "true"); inbox.append(badge); }
    const messages = notifications.filter(n => !n.seen && ["message","group_message"].includes(n.kind)).length;
    badge.textContent = messages ? messages > 99 ? "99+" : String(messages) : ""; badge.hidden = !messages;
    if (fresh.length) {
      notificationSound(); const bell = $("notification-bell"); bell.classList.add("ringing"); setTimeout(() => bell.classList.remove("ringing"), 900);
      const latest = fresh[0]; status(latest.actor.name + " " + (NOTE_TEXT[latest.kind] || "có hoạt động mới."));
      await showSystemNotification(latest);
    }
    renderNotificationCenter();
    inboxRefresh?.().catch(()=>{});
    privateAlbumRefresh?.();friendsRefresh?.();
  })();
  try { await unreadRequest; } finally {
    unreadRequest = null;
    if (unreadRefreshPending) {
      unreadRefreshPending = false;
      if (me) queueMicrotask(() => refreshUnread().catch(() => {}));
    }
  }
}
function startActivityHeartbeat() {
  clearInterval(activityTimer);
  const beat = () => { if (me && !document.hidden) api("/me/activity", "POST", {}).catch(() => {}); };
  beat(); activityTimer = setInterval(beat, 25000);
}
window.addEventListener("kinnect-notifications", () => refreshUnread(true).catch(() => {}));
window.addEventListener("kinnect-conversations", () => inboxRefresh?.().catch(() => {}));
window.addEventListener("online", () => { if (me) { connectLive(); refreshUnread(true).catch(() => {}); } });
window.addEventListener("pageshow", () => { if (me) refreshUnread(true).catch(() => {}); });
window.addEventListener('resize',()=>{if(!mePanel.hidden)positionHeaderPopup(mePanel);if(notificationPanel&&!notificationPanel.hidden)positionHeaderPopup(notificationPanel);});
window.addEventListener("focus", () => { if (me) refreshUnread().catch(() => {}); });
document.addEventListener("visibilitychange", () => { if(document.hidden)stopLocationTracking();else if(me){startActivityHeartbeat();refreshUnread().catch(()=>{});resumeLocationTracking().catch(()=>{});} });
window.addEventListener("pagehide",stopLocationTracking);

const NOTE_TEXT = {
 friend_request:"đã gửi lời mời kết bạn.",friend_accepted:"đã chấp nhận lời mời kết bạn.",
  private_request: "đã yêu cầu xem ảnh riêng tư của bạn.",
  private_granted: "đã đồng ý cho bạn xem album riêng tư.",
  private_revoked: "đã thu hồi quyền xem album riêng tư.",
  group_message: "đã gửi tin nhắn trong nhóm.",
  follow: "đã theo dõi bạn.",
  message: "đã gửi tin nhắn cho bạn.",
  missed_call: "đã gọi cho bạn. Gọi nhỡ.",
  gift: "đã gửi quà thử nghiệm miễn phí.",
  like: "đã thích bài viết của bạn.",
  comment: "đã bình luận về bài viết của bạn.",
};
async function notifications(panel) {
  const head = node("div", undefined, "view-head notifications-heading");
  const back=node('button',undefined,'screen-back header-panel-back app-back-button');back.type='button';back.setAttribute('aria-label','Đóng thông báo');back.innerHTML=accountPanelBack.innerHTML;back.onclick=()=>goBack();head.append(back,node("h2", "Thông báo"));
  panel.append(head);
  const { notifications } = await api("/notifications");
  if (!notifications.length) panel.append(empty("🔔", "Chưa có thông báo", "Khi có người theo dõi, thích hay nhắn tin cho bạn, thông báo sẽ hiện ở đây."));
  const today = new Date().toDateString();
  let group = "";
  let list;
  for (const n of notifications) {
    const g = new Date(n.created).toDateString() === today ? "Hôm nay" : "Trước đó";
    if (g !== group) {
      group = g;
      panel.append(node("h3", g, "section-title"));
      list = node("div", undefined, "social-card list");
      panel.append(list);
    }
    const row = node("button", undefined, "list-row note-row" + (n.seen ? "" : " unread"));
    row.type = "button";
    const text = node("div", undefined, "row-text");
    const line = node("p");
    line.append(node("b", n.actor.name), " ", node("span", NOTE_TEXT[n.kind] || "có hoạt động mới."));
    text.append(line, node("small", timeAgo(n.created), "meta"));
    row.append(avatar(n.actor), text);
    if (!n.seen) row.append(node("span", undefined, "dot"));
    row.onclick = () => openNotification(n).catch(e => status(e.message));
    list.append(row);
  }
  await api("/notifications", "POST", {});
  await refreshUnread();
}
async function adminPanel(panel,opts={}) {
  if(me.role!=='admin'){panel.append(node('p','Bạn cần quyền quản trị để mở mục này.'));return;}
  const revision=navigationRevision,root=node('div',undefined,'admin-dashboard');panel.append(root);
  const head=node('div',undefined,'admin-heading'),title=node('div');title.append(node('h2','Quản trị'),node('p','Yêu cầu hỗ trợ, tài khoản và nội dung cộng đồng.','muted'));head.append(title);root.append(head);
  const feedback=node('p','','admin-feedback');feedback.setAttribute('role','status');root.append(feedback);
  const stats=node('div',undefined,'admin-stats');root.append(stats);
  let current=opts.section||'requests';const panes={},buttons={},statsValues={};
  const labels={requests:'Yêu cầu mật khẩu',users:'Người dùng',reports:'Báo cáo',music:'Thư viện nhạc',ai:'Cấu hình AI',activity:'Nhật ký'};
  const tabs=node('div',undefined,'admin-tabs');tabs.setAttribute('role','tablist');tabs.setAttribute('aria-label','Các mục quản trị');root.append(tabs);
  for(const [key,label] of Object.entries(labels)){
    const button=action(label,()=>select(key),'secondary');button.setAttribute('role','tab');button.id='admin-tab-'+key;button.setAttribute('aria-controls','admin-pane-'+key);tabs.append(button);buttons[key]=button;
    const pane=node('section',undefined,'admin-pane');pane.id='admin-pane-'+key;pane.setAttribute('role','tabpanel');pane.setAttribute('aria-labelledby',button.id);root.append(pane);panes[key]=pane;
  }
  let aiLoaded=false;
  let musicLoaded=false;
  function select(key){current=panes[key]?key:'requests';replaceNavigationOptions({section:current});for(const name of Object.keys(panes)){panes[name].hidden=name!==current;buttons[name].setAttribute('aria-selected',String(name===current));}if(current==='ai'&&!aiLoaded){aiLoaded=true;kinnectAIAdmin(panes.ai).catch(e=>{aiLoaded=false;feedback.textContent=e.message;});}if(current==='music'&&!musicLoaded){musicLoaded=true;musicAdmin(panes.music).catch(e=>{musicLoaded=false;feedback.textContent=e.message;});}}
  tabs.onkeydown=e=>{const keys=Object.keys(buttons),index=keys.indexOf(current);if(['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){e.preventDefault();const next=e.key==='Home'?0:e.key==='End'?keys.length-1:(index+(e.key==='ArrowRight'?1:-1)+keys.length)%keys.length;select(keys[next]);buttons[keys[next]].focus();}};
  function filterSelect(label,items){const select=node('select');select.setAttribute('aria-label',label);for(const [value,text] of items){const option=node('option',text);option.value=value;select.append(option);}return select;}
  function tools(pane,placeholder){const form=node('form',undefined,'admin-tools'),search=node('input');search.type='search';search.placeholder=placeholder;search.setAttribute('aria-label',placeholder);form.append(search);pane.append(form);return {form,search};}
  function actions(card){const row=node('div',undefined,'admin-actions');card.append(row);return row;}
  function info(card,label,value){const line=node('p');line.append(node('span',label+': ','muted'),document.createTextNode(value||'Chưa có'));card.append(line);}
  async function overview(){const data=await api('/admin/overview');if(revision!==navigationRevision)return;for(const [key,label,value,target] of [['users','Tài khoản',data.users,'users'],['pendingResets','Yêu cầu chờ',data.pendingResets,'requests'],['openReports','Báo cáo chờ',data.openReports,'reports'],['suspended','Đã đình chỉ',data.suspended,'users']]){if(!statsValues[key]){const b=action('',()=>{if(key==='suspended'){userState.value='suspended';loadUsers().catch(showError);}select(target);},'admin-stat secondary');const count=node('strong'),caption=node('span',label);b.append(count,caption);statsValues[key]=count;stats.append(b);}statsValues[key].textContent=String(value);}buttons.requests.textContent=labels.requests+(data.pendingResets?' ('+data.pendingResets+')':'');buttons.reports.textContent=labels.reports+(data.openReports?' ('+data.openReports+')':'');}
  function showError(e){feedback.textContent=e.message||'Không tải được dữ liệu. Vui lòng thử lại.';}
  // Password requests retain contact information and a separate history filter.
  const requestTools=tools(panes.requests,'Tìm tài khoản hoặc thông tin liên hệ');
  const requestState=filterSelect('Trạng thái yêu cầu',[['open','Đang chờ'],['done','Đã xử lý'],['dismissed','Đã bỏ qua'],['all','Tất cả']]);requestTools.form.append(requestState);
  panes.requests.append(node('p','Xác minh chủ tài khoản qua thông tin liên hệ trước khi cấp mật khẩu tạm. Hiển thị tối đa 100 yêu cầu gần nhất.','muted admin-hint'));
  const requestList=node('div',undefined,'admin-card-list');panes.requests.append(requestList);let requests=[],requestSignature='',requestLoading=false;
  function drawRequests(){requestList.replaceChildren();const q=requestTools.search.value.trim().toLocaleLowerCase('vi');const matches=requests.filter(r=>(requestState.value==='all'||r.status===requestState.value)&&[r.username,r.name,r.contact,r.note].join(' ').toLocaleLowerCase('vi').includes(q));
    if(!matches.length)requestList.append(node('p','Không có yêu cầu phù hợp.','admin-empty muted'));
    for(const r of matches){const card=node('article',undefined,'social-card admin-request-card');card.append(node('h3',r.name||'@'+r.username));info(card,'Tài khoản','@'+r.username+(r.user_id?'':' · Không tồn tại'));info(card,'Liên hệ',r.contact);if(r.note)info(card,'Ghi chú',r.note);info(card,'Thời gian',new Date(r.created).toLocaleString('vi-VN'));info(card,'Trạng thái',({open:'Đang chờ',done:'Đã xử lý',dismissed:'Đã bỏ qua'})[r.status]||r.status);
      const controls=actions(card);
      if(r.user_id)controls.append(action('Xem hồ sơ',()=>navigate('profile',{user:r.user_id})));
      if(r.status==='open'){
        if(r.user_id)controls.append(action('Cấp mật khẩu tạm',async()=>{if(!confirm('Đã xác minh chủ tài khoản @'+r.username+'? Đặt lại mật khẩu sẽ đăng xuất các phiên hiện tại.'))return;const result=await api('/admin/password-resets/'+r.id+'/reset','POST',{});prompt('Mật khẩu tạm của @'+r.username+' — gửi qua '+r.contact+':',result.temporaryPassword);await refreshAll();await refreshUnread();},'primary'));
        controls.append(action('Bỏ qua',async()=>{if(!confirm('Bỏ qua yêu cầu của @'+r.username+'?'))return;await api('/admin/password-resets/'+r.id+'/dismiss','POST',{});await refreshAll();await refreshUnread();}));
      }
      requestList.append(card);
    }
  }
  requestTools.form.onsubmit=e=>{e.preventDefault();drawRequests();};requestTools.search.oninput=drawRequests;requestState.onchange=drawRequests;
  async function loadRequests(){if(requestLoading)return;requestLoading=true;try{const result=await api('/admin/password-resets');if(revision!==navigationRevision)return;const next=JSON.stringify(result.requests);if(next!==requestSignature){requests=result.requests;requestSignature=next;drawRequests();}}finally{requestLoading=false;}}
  // Search is performed on the server, including accounts outside the latest 100.
  const userTools=tools(panes.users,'Tìm tên hoặc @tên đăng nhập');
  const userState=filterSelect('Lọc tài khoản',[['all','Tất cả tài khoản'],['active','Không bị đình chỉ'],['suspended','Đã đình chỉ'],['admin','Quản trị viên'],['no-email','Chưa có email']]);const find=node('button','Tìm kiếm','primary');find.type='submit';userTools.form.append(userState,find);
  const userCount=node('p','','muted admin-hint'),userList=node('div',undefined,'social-card admin-list');panes.users.append(userCount,userList);let userSearchRevision=0;
  async function loadUsers(){const turn=++userSearchRevision;const q=userTools.search.value.trim().replace(/^@/,'');const result=await api('/admin/users?q='+encodeURIComponent(q)+'&state='+encodeURIComponent(userState.value));if(revision!==navigationRevision||turn!==userSearchRevision)return;userList.replaceChildren();userCount.textContent=result.total>100?'Hiển thị 100 / '+result.total+' tài khoản. Nhập tên để thu hẹp kết quả.':result.total+' tài khoản phù hợp.';
    for(const u of result.users){const row=node('article',undefined,'admin-row admin-user-row'),who=node('div',undefined,'row-text admin-user-info');who.append(node('b',u.name||u.username),node('span','@'+u.username),node('span',(u.role==='admin'?'Quản trị viên':'Thành viên')+(u.suspended?' · Đã đình chỉ':' · Không bị đình chỉ'),'muted'),node('small','Tham gia '+new Date(u.created).toLocaleDateString('vi-VN'),'muted'),node('small',u.recoveryEmail?'Email: '+u.recoveryEmail+(u.emailVerified?' · Đã xác minh':' · Chưa xác minh'):'Chưa có email khôi phục','muted'));
      row.append(avatar({id:u.id,name:u.name||u.username}),who);const controls=actions(row);controls.append(action('Hồ sơ',()=>navigate('profile',{user:u.id})));
      if(u.role!=='admin')controls.append(action(u.suspended?'Khôi phục':'Đình chỉ',async()=>{if(!confirm((u.suspended?'Khôi phục':'Đình chỉ')+' tài khoản '+(u.name||u.username)+' (@'+u.username+')?'))return;await api('/admin/moderate','POST',{action:u.suspended?'restore-user':'suspend-user',target:u.id});await Promise.all([loadUsers(),overview(),loadActivity()]);},u.suspended?'secondary':'danger'));
      if(!u.suspended)row.append(adminRecoveryForm(u,()=>{loadUsers().catch(showError);loadActivity().catch(showError);}));userList.append(row);
    }
    if(!result.users.length)userList.append(node('p','Không tìm thấy tài khoản.','admin-empty muted'));
  }
  userTools.form.onsubmit=e=>{e.preventDefault();loadUsers().catch(showError);};userState.onchange=()=>loadUsers().catch(showError);
  const reportTools=tools(panes.reports,'Tìm lý do hoặc nội dung báo cáo'),reportState=filterSelect('Trạng thái báo cáo',[['open','Đang chờ'],['closed','Đã đóng'],['all','Tất cả']]);reportTools.form.append(reportState);panes.reports.append(node('p','Hiển thị tối đa 100 báo cáo gần nhất.','muted admin-hint'));const reportList=node('div',undefined,'admin-card-list');panes.reports.append(reportList);let reports=[];
  function drawReports(){reportList.replaceChildren();const q=reportTools.search.value.trim().toLocaleLowerCase('vi');const matches=reports.filter(r=>(reportState.value==='all'||r.status===reportState.value)&&[r.reason,r.subject?.body,r.subject?.username].join(' ').toLocaleLowerCase('vi').includes(q));for(const r of matches){const card=node('article',undefined,'social-card');card.append(node('h3',({post:'Bài viết',short:'Video',comment:'Bình luận',message:'Tin nhắn',user:'Tài khoản'})[r.target_type]||r.target_type));info(card,'Lý do',r.reason);info(card,'Nội dung',r.subject?.body||r.subject?.username||'Nội dung không còn tồn tại');info(card,'Trạng thái',r.status==='open'?'Đang chờ':'Đã đóng');const controls=actions(card);
      async function perform(verb,target){if(!confirm('Xác nhận thao tác cho nội dung báo cáo này?'))return;await api('/admin/moderate','POST',{action:verb,target});await refreshAll();}
      if(r.subject?.userId)controls.append(action('Xem hồ sơ',()=>navigate('profile',{user:r.subject.userId})));
      if(r.status==='open'){
        if(['post','short'].includes(r.target_type)&&r.subject)controls.append(action(r.subject.hidden?'Hiện nội dung':'Ẩn nội dung',()=>perform((r.subject.hidden?'show-':'hide-')+r.target_type,r.target_id)));
        if(r.subject?.userId)controls.append(action('Đình chỉ tài khoản',()=>perform('suspend-user',r.subject.userId),'danger'));
        controls.append(action('Đóng báo cáo',()=>perform('close-report',r.id),'primary'));
      }reportList.append(card);
    }if(!matches.length)reportList.append(node('p','Không có báo cáo phù hợp.','admin-empty muted'));}
  reportTools.form.onsubmit=e=>{e.preventDefault();drawReports();};reportTools.search.oninput=drawReports;reportState.onchange=drawReports;
  async function loadReports(){const result=await api('/admin/reports');if(revision!==navigationRevision)return;reports=result.reports;drawReports();}
  panes.activity.append(node('h3','Nhật ký thao tác'),node('p','100 thao tác gần nhất. Không lưu mật khẩu hoặc mã OTP trong nhật ký.','muted admin-hint'));const activityList=node('div',undefined,'admin-card-list');panes.activity.append(activityList);
  const verbs={'suspend-user':'Đình chỉ tài khoản','restore-user':'Khôi phục tài khoản','hide-post':'Ẩn bài viết','show-post':'Hiện bài viết','hide-short':'Ẩn video','show-short':'Hiện video','close-report':'Đóng báo cáo','reset-password':'Cấp mật khẩu tạm','set-recovery-email':'Gán email khôi phục','dismiss-password-request':'Bỏ qua yêu cầu mật khẩu'};
  async function loadActivity(){const result=await api('/admin/activity');if(revision!==navigationRevision)return;activityList.replaceChildren();for(const e of result.entries){const card=node('article',undefined,'social-card admin-log-row'),split=e.action.indexOf(':');const verb=split<0?e.action:e.action.slice(0,split);card.append(node('b',verbs[verb]||verb),node('p',e.username?(e.name||e.username)+' (@'+e.username+')':'Mã đối tượng: '+e.target),node('small',(e.actorUsername?'Bởi @'+e.actorUsername+' · ':'')+new Date(e.created).toLocaleString('vi-VN'),'muted'));activityList.append(card);}if(!result.entries.length)activityList.append(node('p','Chưa có thao tác quản trị.','admin-empty muted'));}
  async function refreshAll(){feedback.textContent='Đang cập nhật…';const results=await Promise.allSettled([overview(),loadRequests(),loadUsers(),loadReports(),loadActivity()]);if(revision!==navigationRevision)return;const failure=results.find(r=>r.status==='rejected');feedback.textContent=failure?'Một số dữ liệu chưa tải được: '+failure.reason.message:'Đã cập nhật '+new Date().toLocaleTimeString('vi-VN');}
  head.append(action('Làm mới',refreshAll));
  adminRequestsRefresh=()=>Promise.all([loadRequests(),overview()]).catch(showError);
  select(current);await refreshAll();
}


async function kinnectAIAdmin(panel){
 panel.replaceChildren(node('p','Đang tải cấu hình AI…','muted'));
 let data;try{data=await api('/admin/ai');}catch(error){panel.replaceChildren(node('h3','Cấu hình AI chưa tải được'),node('p',/không tìm thấy/i.test(error.message)?'Máy chủ đang chạy chưa nạp API cấu hình AI. Cần khởi động lại máy chủ Kinnect sau khi cập nhật, rồi tải lại trang.':error.message,'admin-feedback'));panel.append(action('Thử lại',()=>kinnectAIAdmin(panel),'secondary'));return;}const cfg=data.config,credentials=data.credentials;panel.replaceChildren();
 panel.append(node('h3','Cloudflare chính · NVIDIA dự phòng'),node('p','Khóa chỉ lưu trên máy chủ. Để trống trường khóa để giữ khóa hiện tại. AI chỉ cảnh báo để quản trị viên xem xét, không tự xử phạt.','muted'));
 const form=node('form',undefined,'social-card list');panel.append(form);
 function field(title,value,secret=false){const label=node('label',title),input=node('input');input.type=secret?'password':'text';input.value=value||'';input.autocomplete=secret?'new-password':'off';label.append(input);form.append(label);return input;}
 function check(title,value){const label=node('label'),input=node('input');input.type='checkbox';input.checked=!!value;label.append(input,document.createTextNode(' '+title));form.append(label);return input;}
 const url=field('URL Worker Cloudflare',credentials.workerUrl),token=field('Khóa kết nối Worker'+(credentials.tokenSaved?' · Đã lưu':''),'',true),key=field('Khóa NVIDIA API'+(credentials.nvidiaKeySaved?' · Đã lưu':''),'',true),model=field('Model NVIDIA trả lời hỗ trợ',credentials.nvidiaModel),vision=field('Model NVIDIA đọc ảnh (tùy chọn)',credentials.nvidiaVisionModel);
 model.placeholder='Mã model chính xác từ NVIDIA API Catalog';vision.placeholder='Để trống nếu chưa dùng NVIDIA kiểm duyệt ảnh';const fallback=check('Tự chuyển NVIDIA khi Cloudflare lỗi hoặc quá tải',credentials.fallbackEnabled),password=field('Mật khẩu quản trị để lưu khóa','',true);password.autocomplete='current-password';
 const message=node('p','','admin-feedback');message.setAttribute('role','status');form.append(message);const save=node('button','Lưu cấu hình kết nối','primary');save.type='submit';form.append(save);
 form.onsubmit=async event=>{event.preventDefault();save.disabled=true;try{const result=await api('/admin/ai/credentials','PATCH',{workerUrl:url.value.trim(),token:token.value.trim(),nvidiaKey:key.value.trim(),nvidiaModel:model.value.trim(),nvidiaVisionModel:vision.value.trim(),fallbackEnabled:fallback.checked,password:password.value});token.value=key.value=password.value='';message.textContent='Đã lưu cấu hình. Khóa đã được che và không trả về trình duyệt.';if(result.credentials.tokenSaved)token.placeholder='Đã lưu — để trống để giữ nguyên';if(result.credentials.nvidiaKeySaved)key.placeholder='Đã lưu — để trống để giữ nguyên';}catch(error){password.value='';message.textContent=error.message;}finally{save.disabled=false;}};
 const testButtons=node('div',undefined,'admin-actions');panel.append(testButtons);for(const [provider,title] of [['cloudflare','Kiểm tra Cloudflare'],['nvidia','Kiểm tra NVIDIA'],['fallback','Kiểm tra chuyển dự phòng']]){const button=action(title,async()=>{button.disabled=true;message.textContent='Đang kiểm tra…';try{const result=await api('/admin/ai/test','POST',{provider});message.textContent=result.message+' · '+result.provider;}catch(error){message.textContent=error.message;}finally{button.disabled=false;}},'secondary');testButtons.append(button);}
 const features=node('div',undefined,'social-card list');panel.append(features);function toggle(title,value){const label=node('label'),input=node('input');input.type='checkbox';input.checked=!!value;label.append(input,document.createTextNode(' '+title));features.append(label);return input;}
 const support=toggle('AI tự trả lời từ tài khoản quản trị của tôi',cfg.support),moderation=toggle('AI duyệt avatar, bài viết, video và khung hình Live',cfg.moderation);features.append(node('p','Nhắn “quản trị viên” để chuyển người thật. Admin tự trả lời sẽ tạm dừng AI trong cuộc trò chuyện. Video: tối đa 8 khung hình trong 105 giây đầu; Live: một khung hình khoảng 20 giây khi chủ phòng dùng app hỗ trợ. Không kiểm tra âm thanh.','muted'));
 features.append(action('Lưu bật/tắt AI',async()=>{try{await api('/admin/ai','PATCH',{adminId:me.id,support:support.checked,moderation:moderation.checked});message.textContent='Đã lưu trạng thái AI.';}catch(error){message.textContent=error.message;}},'primary'));
 panel.append(node('h3','Hàng chờ và cảnh báo AI'),node('p','Đang chờ: '+cfg.queue+' · Lỗi: '+cfg.failed+'. Cảnh báo xuất hiện trong mục Báo cáo.','muted'));
 for(const job of data.jobs){const card=node('article',undefined,'social-card');card.append(node('b',job.kind+' · '+job.state),node('small',new Date(job.created).toLocaleString('vi-VN'),'muted'));try{const result=JSON.parse(job.result||'{}');if(result.reason)card.append(node('p',result.reason));}catch{}if(job.kind==='support')card.append(action('Bật lại AI cho hội thoại',async()=>{await api('/admin/ai/conversations/'+job.actor,'PATCH',{paused:false});message.textContent='Đã bật lại AI cho cuộc trò chuyện.'},'secondary'));panel.append(card);}
}

// Quản trị: thư viện nhạc dùng chung trong Kinnect Studio
async function musicAdmin(panel) {
  panel.append(node("h3", "Thư viện nhạc", "section-title"));
  const box = node("div", undefined, "social-card list admin-list");
  panel.append(box);
  let tracks = [];
  try {
    tracks = (await (await fetch("/api/music", { credentials: "same-origin" })).json()).tracks || [];
  } catch {}
  const player = new Audio();
  if (!tracks.length) box.append(node("p", "Chưa có bài nào.", "muted admin-empty"));
  for (const t of tracks) {
    const row = node("div", undefined, "admin-row");
    const play = node("button", "▶", "icon-btn");
    play.type = "button";
    play.setAttribute("aria-label", "Nghe thử " + t.title);
    play.onclick = () => {
      if (!player.paused && player.dataset.file === t.file) {
        player.pause();
        play.textContent = "▶";
        return;
      }
      for (const b of box.querySelectorAll(".icon-btn")) b.textContent = "▶";
      player.src = t.url;
      player.dataset.file = t.file;
      player.play().catch(() => {});
      play.textContent = "⏸";
    };
    const text = node("div", undefined, "row-text");
    text.append(node("b", t.title), node("span", [t.artist, t.license].filter(Boolean).join(" · ") || "Chưa có thông tin giấy phép", "muted"));
    const del = action("Xoá", async () => {
      if (!confirm("Xoá bài “" + t.title + "” khỏi thư viện?")) return;
      const r = await fetch("/api/music", { method: "DELETE", credentials: "same-origin", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ file: t.file }) });
      if (!r.ok) throw Error((await r.json()).error || "Không xoá được.");
      player.pause();
      status("Đã xoá bài nhạc.");
      await navigate("admin");
    }, "danger");
    row.append(play, text, del);
    box.append(row);
  }
  // Tải bài mới
  const form = node("form", undefined, "social-card music-upload");
  form.append(node("b", "Thêm bài vào thư viện"));
  const pick = node("label", undefined, "btn-like secondary");
  const file = node("input");
  file.type = "file";
  file.accept = "audio/mpeg,audio/mp4,.mp3,.m4a";
  file.required = true;
  file.setAttribute("aria-label", "Chọn file MP3 hoặc M4A, tối đa 15 MB");
  const fileText = node("span", "🎵 Chọn file MP3/M4A");
  pick.append(file, fileText);
  const title = node("input");
  title.placeholder = "Tên bài";
  title.required = true;
  title.maxLength = 80;
  title.setAttribute("aria-label", "Tên bài");
  const artist = node("input");
  artist.placeholder = "Nghệ sĩ";
  artist.required = true;
  artist.maxLength = 60;
  artist.setAttribute("aria-label", "Nghệ sĩ");
  const license = node("input");
  license.placeholder = "Giấy phép (vd: CC0, CC BY 4.0, tự sáng tác)";
  license.required = true;
  license.maxLength = 80;
  license.setAttribute("aria-label", "Giấy phép");
  const source = node("input");
  source.placeholder = "Link nguồn (không bắt buộc)";
  source.maxLength = 300;
  source.setAttribute("aria-label", "Link nguồn");
  const rightsLabel = node("label", undefined, "check");
  const rights = node("input");
  rights.type = "checkbox";
  rights.required = true;
  rightsLabel.append(rights, node("span", "Tôi có quyền dùng và chia sẻ bài này trên Kinnect."));
  const send = node("button", "Tải lên");
  form.append(pick, title, artist, license, source, rightsLabel, send);
  file.onchange = () => {
    const f = file.files[0];
    fileText.textContent = f ? "✓ " + f.name : "🎵 Chọn file MP3/M4A";
    if (f && !title.value) title.value = f.name.replace(/\.[^.]+$/, "");
  };
  form.onsubmit = async (e) => {
    e.preventDefault();
    const f = file.files[0];
    if (!f) return status("Chọn file nhạc.");
    if (f.size > 15 * 1024 * 1024) return status("File nhạc tối đa 15 MB.");
    send.disabled = true;
    send.textContent = "Đang tải…";
    try {
      const data = await new Promise((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(String(r.result).replace(/^data:[^;]*;/, /\.m4a$/i.test(f.name) ? "data:audio/mp4;" : "data:audio/mpeg;"));
        r.onerror = reject;
        r.readAsDataURL(f);
      });
      const r = await fetch("/api/music", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ data, title: title.value, artist: artist.value, license: license.value, source: source.value, rights: rights.checked }),
      });
      if (!r.ok) throw Error((await r.json()).error || "Không tải lên được.");
      status("Đã thêm bài vào thư viện nhạc.");
      await navigate("admin");
    } catch (err) {
      status(err.message);
      send.disabled = false;
      send.textContent = "Tải lên";
    }
  };
  panel.append(form);
}
// Live accessors keep authentication, navigation and refresh ownership in this entry point.
const socialContext = {
  get $() { return $; },
  get COMMENT_REACTIONS() { return COMMENT_REACTIONS; },
  get action() { return action; },
  get api() { return api; },
  get avatar() { return avatar; },
  get clock() { return clock; },
  get closePrivatePhoto() { return closePrivatePhoto; },
  get commentReplyBar() { return commentReplyBar; },
  get discoveryMode() { return discoveryMode; }, set discoveryMode(value) { discoveryMode = value; },
  get empty() { return empty; },
  get feedSection() { return feedSection; }, set feedSection(value) { feedSection = value; },
  get fitChatViewport() { return fitChatViewport; },
  get friendshipAction() { return friendshipAction; },
  get goBack() { return goBack; },
  get hue() { return hue; },
  get inboxRefresh() { return inboxRefresh; }, set inboxRefresh(value) { inboxRefresh = value; },
  get lastGeoSync() { return lastGeoSync; }, set lastGeoSync(value) { lastGeoSync = value; },
  get me() { return me; }, set me(value) { me = value; },
  get more() { return more; },
  get navigate() { return navigate; },
  get navigationRevision() { return navigationRevision; },
  get nearbyRefresh() { return nearbyRefresh; }, set nearbyRefresh(value) { nearbyRefresh = value; },
  get node() { return node; },
  get openCamera() { return openCamera; },
  get openChat() { return openChat; },
  get paintMe() { return paintMe; },
  get personLink() { return personLink; },
  get postCard() { return postCard; },
  get privateAlbumRefresh() { return privateAlbumRefresh; }, set privateAlbumRefresh(value) { privateAlbumRefresh = value; },
  get privatePhotoViewer() { return privatePhotoViewer; }, set privatePhotoViewer(value) { privatePhotoViewer = value; },
  get profileBadges() { return profileBadges; },
  get reactionPicker() { return reactionPicker; },
  get readMediaFile() { return readMediaFile; },
  get reelIcon() { return reelIcon; },
  get reelMuted() { return reelMuted; },
  get refreshUnread() { return refreshUnread; },
  get rememberLocation() { return rememberLocation; },
  get renderCommentThread() { return renderCommentThread; },
  get replaceNavigationOptions() { return replaceNavigationOptions; },
  get report() { return report; },
  get screenBackButton() { return screenBackButton; },
  get sendTypingSignal() { return sendTypingSignal; },
  get showAppDialog() { return showAppDialog; },
  get skeleton() { return skeleton; },
  get startLocationTracking() { return startLocationTracking; },
  get startVideoCall() { return startVideoCall; },
  get status() { return status; },
  get stopChatTyping() { return stopChatTyping; }, set stopChatTyping(value) { stopChatTyping = value; },
  get stopLocationTracking() { return stopLocationTracking; },
  get tab() { return tab; },
  get timeAgo() { return timeAgo; },
  get timer() { return timer; }, set timer(value) { timer = value; },
};
const {stories, createStory, openStory, readMediaFile, composer, postCard, openNewsReader, newsCard, newsPanel, feed} = createFeed(socialContext);
const {userCard, profileBadges, discover} = createDiscover(socialContext);
const {field, profilePresets, profileConnections, profilePrivateAlbum, profile} = createProfile(socialContext);
const {conversationMenuButton, messengerSidebar, messengerWelcome, mountConversation, inbox, newMessagePicker, memberPicker, createChatGroup, groupDetails, renderPrivateAlbumMessage, messageControls, toggleChatMute, pinnedMessages, clearConversation, bindChatTyping, activityText, chatFileSize, renderChatAttachment, chatAttachmentComposer, openGroupChat, openChat} = createMessenger(socialContext);

try {
  me = (await api("/me")).user;
} catch {
  showAuth();
}
if (me) await enter().catch(e => status(e.message));

// Nút "+" giữa thanh dưới: mở Kinnect Studio
async function openCamera({story = false, photo = null} = {}) {
  const toBase64 = (blob) =>
    new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(String(r.result).replace(/^data:[^;]*;/, "data:video/mp4;"));
      r.onerror = reject;
      r.readAsDataURL(blob);
    });
  const { openStudio } = await import("./camera.js?v=5");
  await openStudio({
    story, photo,
    notify: status,
    // Từ chế độ LIVE của Studio: mở phòng live với tiêu đề và hiệu ứng đã chọn
    onLive: async (live) => {
      await navigate("live");
      if (!live) return;
      window.kinnectPendingFx = live.state;
      $("title").value = live.title;
      $("create").requestSubmit();
    },
    onDone: async (blob, caption, progress) => {
      progress(-1);
      const data=await toBase64(blob);
      progress(0);
      await uploadJson(story ? "/stories" : "/shorts", story ? {media:data,body:caption} : {data,caption}, progress);
      status(story ? "Đã đăng tin." : "Đã đăng video.");
      await navigate(story ? "feed" : "shorts");
    },
  });
}
window.addEventListener("kinnect-quick-login", async event=>{
 try { me=(await api("/remembered/login","POST",{userId:event.detail})).user;await enter(); }
 catch(e){status(e.message);window.dispatchEvent(new CustomEvent("kinnect-quick-login-failed"));}
});
$("create-post").onclick = () => openCamera().catch((e) => status(e.message));

window.addEventListener("kinnect-report", (event) =>
  report(event.detail.targetType, event.detail.targetId).catch((e) =>
    status(e.message),
  ),
);

window.addEventListener("kinnect-live-state", (event) => {
  document.querySelector('[data-tab="live"]').textContent = event.detail
    ? "Live ●"
    : "Live";
});

window.addEventListener("kinnect-call-status",event=>status(event.detail));

function setupForgotOtp(){
 const start=$('otp-request-form');if(!start)return;
 let challenge=null;const note=$('otp-status'),finish=$('otp-reset-form'),send=$('otp-send'),save=$('otp-save');
 $('otp-email').oninput=()=>{challenge=null;finish.hidden=true;};
 start.onsubmit=async e=>{e.preventDefault();send.disabled=true;note.textContent='Đang yêu cầu mã…';try{const result=await api('/recovery/reset/start','POST',{identifier:$('otp-email').value});challenge=result.challengeId;finish.hidden=false;note.textContent=result.message;$('otp-code').focus();}catch(error){note.textContent=error.message;}finally{send.disabled=false;}};
 finish.onsubmit=async e=>{e.preventDefault();if(!challenge)return;save.disabled=true;try{const result=await api('/recovery/reset/finish','POST',{challengeId:challenge,code:$('otp-code').value,password:$('otp-password').value});challenge=null;finish.reset();finish.hidden=true;note.textContent=result.message;}catch(error){note.textContent=error.message;}finally{save.disabled=false;}};
}
setupForgotOtp();
async function recoveryEmailPanel(){
 const box=node('section',undefined,'social-card');box.append(node('h3','Email khôi phục'),node('p','Xác minh email để nhận OTP khi quên mật khẩu. Email này không hiển thị trên hồ sơ.','muted'));
 const message=node('p');message.setAttribute('role','status');box.append(message);let state;try{state=await api('/recovery/email');message.textContent=state.email?'Email hiện tại: '+state.email:'Bạn chưa có email khôi phục.';}catch{message.textContent='Chưa tải được cấu hình email. Vui lòng thử lại sau.';return box;}
 const form=node('form'),email=field(form,'Email khôi phục','','email'),password=field(form,'Xác nhận mật khẩu hiện tại','','password'),send=node('button','Gửi mã xác minh');email.required=password.required=true;email.autocomplete='email';password.autocomplete='current-password';form.append(send);form.hidden=!!state.email;box.append(form);
 const change=node('button','Đổi email khôi phục');change.type='button';change.hidden=!state.email;change.onclick=()=>{form.hidden=false;change.hidden=true;password.value='';email.focus();};box.append(change);
 const verify=node('form'),code=field(verify,'Mã xác minh email','','text'),submit=node('button','Xác minh email');code.inputMode='numeric';code.autocomplete='one-time-code';code.maxLength=6;code.pattern='[0-9]{6}';code.required=true;verify.append(submit);verify.hidden=true;box.append(verify);let challenge;
 if(!state.mailReady){message.append(node('span',' Chức năng gửi email hiện chưa sẵn sàng.'));send.disabled=true;}
 form.onsubmit=async e=>{e.preventDefault();send.disabled=true;try{const result=await api('/recovery/email/start','POST',{email:email.value,password:password.value});password.value='';challenge=result.challengeId;verify.hidden=false;message.textContent=result.message;code.focus();}catch(error){message.textContent=error.message;}finally{send.disabled=false;}};
 verify.onsubmit=async e=>{e.preventDefault();submit.disabled=true;try{const result=await api('/recovery/email/verify','POST',{challengeId:challenge,code:code.value});message.textContent='Đã xác minh: '+result.email;form.hidden=true;verify.hidden=true;change.hidden=false;password.value='';code.value='';}catch(error){message.textContent=error.message;}finally{submit.disabled=false;}};
 return box;
}
function adminRecoveryForm(u,onSaved){
 const details=node('details'),summary=node('summary','Email khôi phục cho @'+u.username),form=node('form');details.append(summary,node('p','Chỉ gán email sau khi đã xác minh người yêu cầu là chủ tài khoản. Người dùng vẫn phải nhận OTP trước khi đổi mật khẩu.','muted'));
 const email=field(form,'Email khôi phục của @'+u.username,'','email'),password=field(form,'Mật khẩu quản trị viên','','password'),save=node('button','Lưu email khôi phục'),message=node('p');email.required=password.required=true;password.autocomplete='current-password';message.setAttribute('role','status');form.append(save,message);details.append(form);
 form.onsubmit=async e=>{e.preventDefault();save.disabled=true;try{const result=await api('/recovery/admin/users/'+u.id+'/email','POST',{email:email.value,password:password.value});password.value='';message.textContent=result.message;onSaved?.();}catch(error){password.value='';message.textContent=error.message;}finally{save.disabled=false;}};return details;
}
