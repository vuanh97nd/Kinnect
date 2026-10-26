import { connectLive, disconnectLive, joinLiveRoom } from "./app.js?v=live2";
let callModule=null,callModuleLoading=null;
function loadVideoCalls(){return callModuleLoading||(callModuleLoading=import('./calls.js').then(module=>{callModule=module;return module;}).catch(error=>{callModuleLoading=null;throw error;}));}
async function startVideoCall(user,mode="video"){const module=await loadVideoCalls();return module.startVideoCall(user,mode);}
function endVideoCall(){callModule?.endVideoCall();}
const REEL_ICONS = {
 fullscreen:'<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/>',
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
 const cancel=node('button','Đóng','reaction-dismiss');cancel.type='button';cancel.onclick=()=>dialog.close();dialog.append(cancel);document.body.append(dialog);dialog.addEventListener('close',()=>{dialog.remove();if(anchor.isConnected)anchor.focus();},{once:true});dialog.onclick=e=>{if(e.target===dialog){const r=dialog.getBoundingClientRect();if(e.clientY<r.top||e.clientY>r.bottom||e.clientX<r.left||e.clientX>r.right)dialog.close();}};dialog.showModal();
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
  dialog.showModal();
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
    ? "Gửi yêu cầu, quản trị viên sẽ giúp bạn lấy lại tài khoản."
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
  await navigate(
    new URL(location.href).searchParams.has("video") ? "shorts" :
    new URL(location.href).searchParams.get("view") === "live"
      ? "live"
      : "discover",
  );
  if (new URL(location.href).searchParams.get("view") === "live")
    document.body.classList.add("live-only");
  rail().catch(() => {});
  clearInterval(notificationTimer);
  notificationTimer = setInterval(() => refreshUnread().catch(() => {}), 10000);
  await refreshUnread().catch(e => status(e.message));
  const chatId = new URL(location.href).searchParams.get("chat");
  if (chatId) { try { const { user } = await api("/users/" + encodeURIComponent(chatId)); await openChat(user); } catch (e) { status(e.message); } }
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
function menu(open) {
  mePanel.hidden = !open;
  meBtn.setAttribute("aria-expanded", String(open));
}
meBtn.onclick = () => {
  // Popup "Tài khoản" dùng chung cho mọi khổ màn; URL /?tab=account vẫn hoạt động như deep-link.
  menu(mePanel.hidden);
};
document.addEventListener("click", (e) => {
  if (!mePanel.hidden && !e.target.closest(".me-menu")) menu(false);
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !mePanel.hidden) {
    menu(false);
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
// Khung xám nhấp nháy trong lúc tải
function skeleton(kind) {
  const box = node("div", undefined, "skeleton-list");
  box.setAttribute("aria-hidden", "true");
  for (let i = 0; i < (kind === "grid" ? 4 : 3); i++)
    box.append(node("div", undefined, "skeleton " + (kind === "grid" ? "sk-tile" : "sk-card")));
  if (kind === "grid") box.classList.add("grid");
  return box;
}
let inboxRefresh=null,stopChatViewport=null,friendsRefresh=null;
function fitChatViewport(box){
 stopChatViewport?.();if(!window.visualViewport||innerWidth>=1000)return;
 const viewport=window.visualViewport;
 const fit=()=>{if(!box.isConnected)return;const keyboard=innerHeight-viewport.height>150;document.body.classList.toggle('chat-keyboard-open',keyboard);const top=box.getBoundingClientRect().top-viewport.offsetTop;const bottom=keyboard?12:64+parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--safe-bottom')||0)+16;box.style.height=Math.max(180,viewport.height-Math.max(0,top)-bottom)+'px';};
 viewport.addEventListener('resize',fit);viewport.addEventListener('scroll',fit);fit();
 stopChatViewport=()=>{viewport.removeEventListener('resize',fit);viewport.removeEventListener('scroll',fit);document.body.classList.remove('chat-keyboard-open');stopChatViewport=null;};
}
async function navigate(value, opts = {}) {
  stopChatViewport?.();inboxRefresh=null;friendsRefresh=null;
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
    if (value === "notifications") await notifications(view);
    if (value === "admin") await adminPanel(view);
  } catch (e) {
    status(e.message);
    view.append(empty("⚠️", "Không tải được dữ liệu", "Kiểm tra kết nối rồi thử lại."));
  }
  if (revision !== navigationRevision || !me) return false;
  panel.replaceChildren(view);
  window.scrollTo(0, 0);
  if(opts.privateAlbum)view.querySelector(".private-album")?.scrollIntoView({block:"start"});
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
  document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
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
function userCard(u) {
  const card = node("article", undefined, "social-card person-tile");
  const photo = node("div", undefined, "tile-photo " + hue(u.id));
  photo.append(avatar(u));
  if(u.distanceLabel||u.distanceBand){photo.classList.add("has-distance");const distanceText=u.distanceLabel||u.distanceBand.replace("Gần bạn · dưới khoảng ","< ").replace("Khoảng ","");const distance=node("span",distanceText,"tile-chip");distance.title="Khoảng cách ước tính, làm tròn 100 m";photo.append(distance);}
  const head = node("button", undefined, "tile-name");
  head.type = "button";
  head.append(node("h3", u.name), node("p", "@" + u.username, "muted"));
  head.onclick = () => navigate("profile", { user: u.id });
  photo.append(head);
  photo.append(
    more([
      ["Chặn", async () => {
        if (!confirm("Chặn " + u.name + "? Hai bên sẽ không thấy nhau trong khám phá, bảng tin, chat và phòng live.")) return;
        await api("/users/" + u.id + "/block", "POST", {});
        status("Đã chặn " + u.name + ".");
        await navigate(tab);
      }],
      ["Báo cáo", () => report("user", u.id)],
    ]),
  );
  const presence = node("div", undefined, "presence-badges");
  if (u.isActive) presence.append(node("span", "● Online", "presence online"));
  if (u.isNew) presence.append(node("span", "Mới", "presence new-member"));
  photo.append(presence);
  card.append(photo, profileBadges(u));
  if (u.bio) card.append(node("p", u.bio, "tile-bio"));
  const tags = node("div", undefined, "tags");
  u.interests.slice(0, 4).forEach((v) => tags.append(node("span", v)));
  card.append(tags);
  if (u.score) card.append(node("p", u.score + " sở thích chung", "match"));
  const buttons = node("div", undefined, "card-actions");
  buttons.append(
    action(u.following ? "Bỏ theo dõi" : "Theo dõi", async () => {
      await api("/users/" + u.id + "/follow", u.following ? "DELETE" : "POST", {});
      await navigate(tab);
    }, u.following ? "secondary" : "follow"),
    action("Nhắn tin", () => openChat(u)),
  );
  const followButton=buttons.children[0],messageButton=buttons.children[1];
  followButton.setAttribute('aria-label',u.following?'Bỏ theo dõi':'Theo dõi');followButton.title=u.following?'Bỏ theo dõi':'Theo dõi';
  followButton.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="7" r="4"/><path d="M2 21v-2a7 7 0 0 1 14 0v2"/>'+(u.following?'<path d="m17 9 2 2 4-5"/>':'<path d="M20 5v8m-4-4h8"/>')+'</svg>';
  messageButton.setAttribute('aria-label','Nhắn tin');messageButton.title='Nhắn tin';messageButton.innerHTML=reelIcon('comment');
  card.append(buttons);
  return card;
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
  dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
  form.onsubmit=async e=>{e.preventDefault();const selected=form.querySelector('input:checked');if(!selected||send.disabled)return;send.disabled=true;feedback.textContent='';
    try{await api('/reports','POST',{targetType,targetId,reason:selected.value+(detail.value.trim()?': '+detail.value.trim():'')});form.replaceChildren(node('div','Đã gửi báo cáo','report-success'),node('p','Cảm ơn bạn đã giúp Kinnect an toàn hơn.','report-note'));const done=node('button','Xong','report-submit');done.type='button';done.onclick=()=>dialog.close();form.append(done);done.focus();}
    catch(error){feedback.textContent=error.message;send.disabled=false;}
  };
}
let discoveryMode = "nearby";
function profileBadges(user) {
  const box = node("div", undefined, "identity-badges");
  const genderIcons = { "Nam": "♂", "Nữ": "♀", "Nam chuyển giới": "⚧", "Nữ chuyển giới": "⚧", "Phi nhị nguyên": "◇" };
  const roles = { "Top": "↑", "Bottom": "↓", "Vers": "↕", "Vers Top": "↗", "Vers Bottom": "↘", "Side": "○" };
  const labels = [
    user.age ? [String(user.age) + " tuổi", "age"] : null,
    user.city ? ["⌖ " + user.city, "location"] : null,
    user.gender ? [(genderIcons[user.gender] || "◇") + " " + user.gender, "gender"] : null,
    user.orientation ? [user.orientation, "orientation"] : null,
    user.relationshipRole ? [(roles[user.relationshipRole] || "↕") + " " + user.relationshipRole, "role"] : null,
    user.pronouns ? [user.pronouns, "pronouns"] : null,
  ].filter(Boolean);
  for (const [label, kind] of labels) { const badge = node("span", label, "identity-badge badge-" + kind); badge.title = label; box.append(badge); }
  return box;
}
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
async function discover(panel, q = "") {
  let selected = discoveryMode, request = 0;
  const tools = node("section", undefined, "discovery-tools social-card");
  const chips = node("div", undefined, "chips discovery-tabs");
  chips.setAttribute("aria-label", "Lọc thành viên");
  for (const [label, value] of [["Gần đây", "nearby"], ["Mới", "new"], ["Đang online", "active"], ["Hợp gu", "interests"]]) {
    const b = node("button", label, "chip" + (value === selected ? " active" : "")); b.type = "button"; b.setAttribute("aria-pressed", String(value === selected));
    b.onclick = () => { selected = discoveryMode = value; for (const c of chips.children) { c.classList.toggle("active", c === b); c.setAttribute("aria-pressed", String(c === b)); } if(value === "nearby"){if(!enable.disabled)enable.onclick();}else load().catch(showError); };
    chips.append(b);
  }
  const location = node("section", undefined, "nearby-consent");
  const locationText = node("p", "", "muted"); locationText.setAttribute("role", "status");
  const enable = node("button", "Bật vị trí", "secondary"); enable.type = "button";
  const disable = node("button", "Tắt", "ghost"); disable.type = "button";
  location.append(locationText, enable, disable); tools.append(chips, location); panel.append(tools);
  const heading = node("h3", "", "section-title discovery-results-title");
  const list = node("div", undefined, "people-grid"); panel.append(heading, list);
  function showError(e) { locationText.textContent = e.message; list.replaceChildren(empty("📍", "Chưa tải được thành viên", "Bạn có thể thử lại hoặc chọn Mới tham gia.")); }
  async function load() {
    const version = ++request, mode = selected;
    const own = (await api("/me")).user;
    if (version !== request) return;
    me = own;
    location.hidden = mode !== "nearby" || me.hasLocation;
    enable.textContent = "Bật vị trí";
    enable.hidden = me.hasLocation;
    disable.hidden = !me.hasLocation;
    locationText.textContent = me.hasLocation
      ? ""
      : "📍 Bật vị trí để thấy người gần bạn";
    const nearby = mode === "nearby" && me.hasLocation;
    heading.textContent = mode === "nearby" ? (nearby ? "Thành viên quanh bạn" : "Mới tham gia") : mode === "active" ? "Đang hoạt động" : mode === "interests" ? "Người cùng sở thích" : "Mới tham gia";
    list.replaceChildren(skeleton("grid"));
    const { users } = await api("/discover?q=" + encodeURIComponent(q) + (nearby ? "&nearby=1" : "") + "&sort=" + (mode === "nearby" ? "new" : mode));
    if (version !== request) return;
    list.replaceChildren(...users.map(userCard));
    if (!users.length) list.append(empty(nearby ? "📍" : "🔎", nearby ? "Chưa có thành viên quanh bạn" : mode === "active" ? "Chưa có ai đang hoạt động" : "Chưa tìm thấy ai", nearby ? "Chỉ những người đã bật vị trí trong 24 giờ gần nhất mới xuất hiện. Bạn có thể xem thêm ở Mới tham gia." : mode === "active" ? "Chưa có thành viên đang hoạt động. Hãy xem thêm ở Mới tham gia." : "Bổ sung sở thích hoặc thử bộ lọc khác."));
  }
  enable.onclick = async () => {
    enable.disabled = true;
    locationText.textContent = "Đang lấy vị trí của bạn…";
    try {
      if (!window.isSecureContext || !navigator.geolocation) throw Error("Mở Kinnect bằng HTTPS hoặc localhost để sử dụng vị trí.");
      const position = await new Promise((resolve, reject) => navigator.geolocation.getCurrentPosition(resolve, reject, { enableHighAccuracy: true, timeout: 20000, maximumAge: 60000 }));
      me = (await api("/me/location", "PATCH", { enabled: true, latitude: position.coords.latitude, longitude: position.coords.longitude })).user;
      lastGeoSync=Date.now();rememberLocation(true);startLocationTracking();
      await load();
    } catch (e) {
      locationText.textContent = e.code === 1 ? "Quyền vị trí đang bị chặn. Hãy cho phép vị trí trong quyền của trang rồi thử lại." : e.code === 2 ? "Chưa lấy được vị trí. Kiểm tra dịch vụ vị trí trên thiết bị rồi thử lại." : e.code === 3 ? "Lấy vị trí quá thời gian. Hãy thử lại ở nơi có tín hiệu tốt hơn." : e.message;
    } finally { enable.disabled = false; }
  };
  disable.onclick = async () => { disable.disabled = true; try { me = (await api("/me/location", "PATCH", { enabled: false })).user; rememberLocation(false);stopLocationTracking();await load(); } catch (e) { showError(e); } finally { disable.disabled = false; } };
  nearbyRefresh=()=>panel.isConnected&&selected==="nearby"?load().catch(showError):undefined;
  await load();
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
async function stories(panel) {
  const strip = node("div", undefined, "stories");
  strip.setAttribute("aria-label", "Tin của người đang theo dõi");
  const mine = node("button", undefined, "story story-me");mine.type="button";
  mine.append(avatar(me),node("span","+ Tạo tin"));
  mine.onclick=()=>createStory();
  strip.append(mine);panel.append(strip);
  const {stories:items}=await api("/stories");
  const groups=new Map();for(const item of items){if(!groups.has(item.user_id))groups.set(item.user_id,[]);groups.get(item.user_id).push(item);}
  for(const group of groups.values()){
    const u=group[0].author,b=node("button",undefined,"story has-story");b.type="button";b.setAttribute("aria-label","Xem tin của "+u.name);b.append(avatar(u),node("span",u.name));
    b.onclick=()=>openStory([...group].reverse());strip.append(b);
  }
}
function createStory(){
 const dialog=node("dialog",undefined,"story-create");dialog.setAttribute("aria-label","Tạo tin mới");
 const head=node("div",undefined,"story-create-head"),close=node("button","×");close.type="button";close.setAttribute("aria-label","Đóng tạo tin");close.onclick=()=>dialog.close();head.append(node("h2","Tạo tin"),close);
 const camera=node("button",undefined,"story-create-camera");camera.type="button";camera.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="4"/></svg><strong>Quay tin</strong><span>Camera · Nhạc · Hiệu ứng</span>';
 const photo=node("label",undefined,"story-create-photo");photo.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 16 5-5 4 4 3-3 6 6"/><circle cx="16" cy="9" r="1.5"/></svg><strong>Ảnh kèm nhạc</strong><span>Chọn ảnh · thêm bài hát</span>';
 const input=node("input");input.type="file";input.accept="image/jpeg,image/png,image/webp";input.setAttribute("aria-label","Chọn ảnh tạo tin");photo.append(input);
 camera.onclick=()=>{dialog.close();openCamera({story:true}).catch(e=>status(e.message));};
 input.onchange=()=>{const file=input.files[0];if(!file)return;if(file.size>5*1024*1024){status("Ảnh tối đa 5 MB.");return;}dialog.close();openCamera({story:true,photo:file}).catch(e=>status(e.message));};
 dialog.append(head,camera,photo,node("p","Tin hiển thị 24 giờ cho những người theo dõi bạn."));dialog.addEventListener("close",()=>dialog.remove(),{once:true});document.body.append(dialog);dialog.showModal();
}
function openStory(items){
  const dialog=node("dialog",undefined,"story-viewer");dialog.setAttribute("aria-label","Xem tin");let index=0;
  const close=node("button","×","story-close");close.type="button";close.setAttribute("aria-label","Đóng tin");close.onclick=()=>dialog.close();
  const progress=node("div",undefined,"story-progress");const content=node("div",undefined,"story-content"),bar=node("div",undefined,"story-viewer-tools");
  const previous=node("button","←"),next=node("button","→");previous.type=next.type="button";previous.setAttribute("aria-label","Tin trước");next.setAttribute("aria-label","Tin tiếp theo");
  const remove=node("button","Xóa tin");remove.type="button";
  previous.onclick=()=>{index--;paint();};next.onclick=()=>{index++;paint();};
  remove.onclick=async()=>{if(!confirm("Xóa tin này?"))return;try{await api("/posts/"+items[index].id,"DELETE",{});dialog.close();await navigate("feed");}catch(e){status(e.message);}};
  bar.append(previous,remove,next);dialog.append(progress,close,content,bar);document.body.append(dialog);
  function paint(){progress.replaceChildren(...items.map((_,i)=>{const segment=node("span");segment.classList.toggle("active",i<=index);return segment;}));for(const video of content.querySelectorAll("video"))video.pause();content.replaceChildren();const item=items[index];content.append(node("strong",item.author.name));if(item.media){const media=node(item.media.kind==="video"?"video":"img");media.src=item.media.url;if(item.media.kind==="video"){media.controls=true;media.playsInline=true;media.autoplay=true;media.muted=reelMuted;media.addEventListener("canplay",()=>media.play().catch(()=>{media.muted=true;media.play().catch(()=>{});}),{once:true});}else media.alt="Ảnh trong tin của "+item.author.name;content.append(media);}if(item.body)content.append(node("p",item.body));previous.disabled=index===0;next.disabled=index===items.length-1;remove.hidden=item.user_id!==me.id;}
  let startY=0;content.addEventListener("touchstart",e=>{startY=e.changedTouches[0].clientY;},{passive:true});content.addEventListener("touchend",e=>{const distance=e.changedTouches[0].clientY-startY;if(distance < -60 && index<items.length-1){index++;paint();}else if(distance>60&&index>0){index--;paint();}},{passive:true});
  dialog.addEventListener("keydown",e=>{if(["ArrowRight","ArrowDown"].includes(e.key)&&index<items.length-1){e.preventDefault();index++;paint();}else if(["ArrowLeft","ArrowUp"].includes(e.key)&&index>0){e.preventDefault();index--;paint();}});
  dialog.addEventListener("close",()=>{for(const v of content.querySelectorAll("video"))v.pause();dialog.remove();},{once:true});paint();dialog.showModal();
}
function readMediaFile(file){
  return new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result));r.onerror=()=>reject(Error("Không đọc được tệp."));r.readAsDataURL(file);});
}
function composer(panel) {
  const form = node("form", undefined, "social-card composer");
  const row = node("div", undefined, "composer-row");
  const input = node("textarea");
  input.placeholder = feedSection==="confessions"?"Bạn muốn chia sẻ điều gì hôm nay?":feedSection==="questions"?"Bạn đang cần lời khuyên về điều gì?":me.name + " ơi, bạn đang nghĩ gì?";
  input.maxLength = 2000;
  input.required = false;
  input.rows = 1;
  input.setAttribute("aria-label", "Nội dung bài viết");
  input.addEventListener("focus",()=>form.classList.add("composer-expanded"));
  row.append(avatar(me), input);
  const visibility = node("select");
  visibility.setAttribute("aria-label", "Ai có thể xem bài viết");
  for (const [value, label] of [
    ["public", "🌐 Mọi thành viên"],
    ["followers", "👥 Người theo dõi"],
  ]) {
    const o = node("option", label);
    o.value = value;
    visibility.append(o);
  }
  const submit = node("button", feedSection==="questions"?"Đăng câu hỏi":feedSection==="confessions"?"Chia sẻ tâm sự":"Chia sẻ");
  const tools = node("div", undefined, "composer-tools");
  const video = node("button", "🎬 Video", "ghost");
  video.type = "button";
  video.onclick = () => attachment.click();
  const live = node("button", "🔴 Live", "ghost");
  live.type = "button";
  live.onclick = () => navigate("live");
  const attachment=node("input");attachment.type="file";attachment.accept="image/jpeg,image/png,image/webp,video/mp4";attachment.hidden=true;attachment.setAttribute("aria-label","Ảnh hoặc video cho bài viết");
  const photo=node("button","Ảnh / Video","ghost");photo.type="button";photo.onclick=()=>attachment.click();
  const preview=node("div",undefined,"composer-preview");preview.hidden=true;let mediaData=null;
  attachment.onchange=async()=>{const file=attachment.files[0];if(!file)return;form.classList.add("composer-expanded");const isVideo=file.type==="video/mp4";if(file.size>(isVideo?12:5)*1024*1024){status(isVideo?"Video tối đa 12 MB.":"Ảnh tối đa 5 MB.");attachment.value="";return;}submit.disabled=true;try{mediaData=await readMediaFile(file);preview.replaceChildren();const media=node(isVideo?"video":"img");media.src=mediaData;if(isVideo){media.controls=true;media.playsInline=true;}else media.alt="Ảnh đính kèm";const clear=node("button","Gỡ tệp","ghost");clear.type="button";clear.onclick=()=>{mediaData=null;attachment.value="";preview.replaceChildren();preview.hidden=true;};preview.append(media,clear);preview.hidden=false;}catch(e){status(e.message);}finally{submit.disabled=false;}};
  const storyLabel=node("label",undefined,"composer-story");const story=node("input");story.type="checkbox";story.name="story";storyLabel.append(story,document.createTextNode("Đăng vào tin · 24 giờ"));
  const category=node('select',undefined,'composer-category');category.setAttribute('aria-label','Mục đăng bài');for(const [value,label] of [['community','Cộng đồng'],['confessions','Tâm sự'],['questions','Hỏi đáp']]){const option=node('option',label);option.value=value;category.append(option);}category.value=feedSection==='news'?'community':feedSection;
  tools.append(photo, live,category, visibility, submit);
  form.append(row, preview, attachment, storyLabel, tools);
  form.onsubmit = async (e) => {
    e.preventDefault();
    submit.disabled = true;
    try {
      if(!input.value.trim()&&!mediaData)throw Error("Thêm nội dung, ảnh hoặc video trước khi đăng.");
      await api(story.checked ? "/stories" : "/posts", "POST", { body: input.value, visibility: visibility.value,category:category.value, media:mediaData });
      status("Đã đăng bài.");
      await navigate("feed");
    } catch (e) {
      status(e.message);
      submit.disabled = false;
    }
  };
  if(["confessions","questions"].includes(feedSection)){form.classList.add("topic-composer","composer-"+feedSection);const hint=node("p",feedSection==="confessions"?"Câu chuyện của bạn có thể chạm đến một người đang cần được lắng nghe.":"Thêm bối cảnh để mọi người có thể đưa ra câu trả lời hữu ích.","topic-composer-hint");form.append(hint);}
  panel.append(form);
}
function postCard(p) {
  const card = node("article", undefined, "social-card post"+(p.category==="confessions"?" confession-card":p.category==="questions"?" question-card":""));
  const head = node("div", undefined, "post-head");
  const who = node("div", undefined, "post-who");
  const name = node("button", p.author.name, "name-link");
  name.type = "button";
  name.onclick = () => navigate("profile", { user: p.author.id });
  who.append(
    name,
    node("span", timeAgo(p.created) + " · " + (p.visibility === "followers" ? "👥 Người theo dõi" : "🌐 Mọi thành viên"), "meta"),
  );
  const options =
    p.user_id === me.id
      ? [["Xóa bài", async () => {
          if (!confirm("Xóa bài viết này?")) return;
          await api("/posts/" + p.id, "DELETE", {});
          status("Đã xóa bài viết.");
          card.remove();
        }, "danger-item"]]
      : [["Báo cáo bài viết", () => report("post", p.id)]];
  head.append(personLink(p.author), who, more(options, "Tùy chọn bài viết"));
  if(p.category&&p.category!=="community")head.append(node("span",({confessions:"Tâm sự",questions:"Hỏi đáp",events:"Sự kiện"})[p.category],"post-category-badge"));
  card.append(head, node("p", p.body, "post-body"));
  if(p.media){const media=node(p.media.kind==="video"?"video":"img",undefined,"post-media");media.src=p.media.url;if(p.media.kind==="video"){media.controls=true;media.playsInline=true;media.preload="metadata";}else{media.alt="Ảnh trong bài viết của "+p.author.name;media.loading="lazy";}card.append(media);}
  let likes = p.likes || 0,
    liked = !!p.liked, myReaction=p.myReaction||(p.liked?"like":null), reactions=p.reactions||{},
    count = p.comments || 0;
  const stats = node("div", undefined, "post-stats");
  stats.hidden = true;
  const paintStats = () => {
    comment.innerHTML = reelIcon("comment")+"<span>"+(p.category==="questions"?(count?count+" trả lời":"Trả lời"):p.category==="confessions"?(count?count+" chia sẻ":"Chia sẻ cảm nghĩ"):(count||"Bình luận"))+"</span>";
    comment.setAttribute("aria-label", "Bình luận" + (count ? " (" + count + ")" : ""));
  };
  const bar = node("div", undefined, "post-actions");
  const like = node("button", undefined, "act like");
  like.type = "button";
  const paintLike = () => {
    like.replaceChildren();const emoji=node('span',myReaction?COMMENT_REACTIONS[myReaction][0]:'👍','post-reaction-icon');like.append(emoji,node('span',myReaction?COMMENT_REACTIONS[myReaction][1]:'Thích'));
    stats.replaceChildren();stats.hidden=!likes;if(likes){const icons=node('span',Object.keys(reactions).filter(k=>reactions[k]>0).slice(0,3).map(k=>COMMENT_REACTIONS[k][0]).join(''),'post-reaction-summary');stats.append(icons,node('span',String(likes)));}
    like.setAttribute("aria-label", (liked ? "Bỏ thích" : "Thích") + (likes ? " (" + likes + ")" : ""));
    like.classList.toggle("on", liked);
    like.setAttribute("aria-pressed", String(liked));
  };
  paintLike();
  like.onclick=()=>reactionPicker(like,myReaction,async reaction=>{
   like.disabled=true;try{const r=await api('/posts/'+p.id+'/like',reaction?'POST':'DELETE',reaction?{reaction}:{});likes=r.likes;liked=r.liked;myReaction=r.myReaction;reactions=r.reactions;paintLike();paintStats();}finally{like.disabled=false;}
  });
  const comment = node("button", undefined, "act");
  comment.type = "button";
  paintStats();
  const thread = node("div", undefined, "comments");
  thread.hidden = true;
  comment.onclick = async () => {
    thread.hidden = !thread.hidden;
    if (!thread.hidden) {
      try { await loadComments(); } catch (e) { status(e.message); }
    }
  };
  async function loadComments() {
    const { comments } = await api("/posts/" + p.id + "/comments");
    thread.replaceChildren();
    const form = node("form", undefined, "comment-form");
    const input = node("input");
    input.placeholder = p.category==="questions"?"Viết câu trả lời của bạn…":"Viết bình luận…";
    input.maxLength = 1000;
    input.required = true;
    input.setAttribute("aria-label", "Viết bình luận");
    const send = node("button", "➤", "ghost");
    send.setAttribute("aria-label", "Gửi bình luận");
    form.append(avatar(me), input, send);
    const replyHost=node('div');thread.append(replyHost,form);const replyState=commentReplyBar(form,input);
    renderCommentThread(replyHost,comments,'/posts/'+p.id+'/comments',c=>replyState.reply(c),loadComments);
    form.onsubmit = async (e) => {
      e.preventDefault();
      send.disabled = true;
      try {
        await api("/posts/" + p.id + "/comments", "POST", { body: input.value,parentId:replyState.parentId });
        count++;
        paintStats();
        await loadComments();
        thread.querySelector(".comment-form input")?.focus();
      } catch (e) {
        status(e.message);
      } finally {
        send.disabled = false;
      }
    };
    thread.append(form);
  }
  bar.append(like, comment);
  if (p.user_id !== me.id) {
    const dm = action("✉", () => openChat(p.author), "act");
    dm.innerHTML=reelIcon("comment")+"<span>Nhắn tin</span>";
    dm.setAttribute("aria-label", "Nhắn tin cho " + p.author.name);
    bar.append(dm);
  }
  card.append(stats, bar, thread);
  return card;
}
let feedSection='community';
function openNewsReader(article){
 const dialog=node('dialog',undefined,'news-reader');dialog.setAttribute('aria-label','Đọc tin tức');const bar=node('div',undefined,'news-reader-bar'),back=node('button','‹');back.type='button';back.setAttribute('aria-label','Quay lại tin tức');back.onclick=()=>dialog.close();bar.append(back,node('strong',article.source));const content=node('article',undefined,'news-reader-content');content.append(node('span',article.source,'news-source'),node('h1',article.title));if(article.publishedAt)content.append(node('p',new Date(article.publishedAt).toLocaleString('vi-VN'),'news-meta'));if(article.image){const image=node('img');image.src=article.image;image.alt='';image.referrerPolicy='no-referrer';content.append(image);}if(article.summary)content.append(node('p',article.summary,'news-reader-summary'));const original=node('a','Đọc toàn bài trên '+article.source,'news-original');original.href=article.url;const note=node('p','Phần giới thiệu từ RSS của '+article.source+'. Bài đầy đủ được đọc trên trang báo do nguồn không cho phép nhúng vào Kinnect.','news-reader-note');content.append(original,note);dialog.append(bar,content);document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
}
function newsCard(article){const card=node('a',undefined,'news-card');card.href=article.url;card.onclick=e=>{if(e.ctrlKey||e.metaKey||e.shiftKey||e.altKey)return;e.preventDefault();openNewsReader(article);};if(article.image){const image=node('img');image.src=article.image;image.alt='';image.loading='lazy';image.referrerPolicy='no-referrer';image.onerror=()=>image.remove();card.append(image);}const copy=node('div',undefined,'news-copy');copy.append(node('span',article.source,'news-source'),node('h3',article.title),node('span',article.publishedAt?timeAgo(article.publishedAt)+' · Đọc tin':'Đọc tin','news-meta'));card.append(copy);return card;}
async function newsPanel(panel,{preview=false}={}){
 const section=node('section',undefined,'news-section');section.setAttribute('aria-label','Tin tức từ báo');const heading=node('div',undefined,'news-heading');heading.append(node('h2','Tin tức'));if(preview){const all=node('button','Xem tất cả');all.type='button';all.onclick=()=>{feedSection='news';navigate('feed');};heading.append(all);}section.append(heading);const content=node('div',undefined,preview?'news-preview':'news-grid');content.textContent='Đang tải tin tức…';section.append(content);panel.append(section);
 try{const data=await api('/news');if(!section.isConnected)return;const articles=data.articles||[];let source='all';const filter=node('div',undefined,'news-filters');
 function render(){const items=articles.filter(a=>source==='all'||a.sourceId===source);content.replaceChildren(...items.slice(0,preview?3:40).map(newsCard));if(!items.length){const empty=node('div',undefined,'news-empty');empty.append(node('p','Chưa tải được tin từ báo.'));const retry=node('button','Thử lại');retry.type='button';retry.onclick=()=>{section.remove();newsPanel(panel,{preview});};empty.append(retry);content.append(empty);}}
 if(!preview){for(const item of [{id:'all',name:'Tất cả'},...data.sources]){const button=node('button',item.name,item.id==='all'?'active':'');button.type='button';button.onclick=()=>{source=item.id;for(const b of filter.children)b.classList.toggle('active',b===button);render();};filter.append(button);}heading.after(filter);}render();
 }catch{content.textContent='Chưa tải được tin tức. Bạn thử lại sau nhé.';}
}
async function feed(panel) {
 panel.append(node('h2','Bảng tin','sr-title'));const tabs=node('div',undefined,'feed-section-tabs');tabs.setAttribute('aria-label','Nội dung bảng tin');for(const [key,label] of [['community','Cộng đồng'],['confessions','Tâm sự'],['questions','Hỏi đáp'],['news','Tin tức']]){const button=node('button',label,feedSection===key?'active':'');button.type='button';button.setAttribute('aria-pressed',String(feedSection===key));button.onclick=()=>{feedSection=key;navigate('feed').catch(e=>status(e.message));};tabs.append(button);}panel.append(tabs);
 if(feedSection==='news'){newsPanel(panel).catch(()=>{});return;}
 if(['confessions','questions'].includes(feedSection)){
  const isConfession=feedSection==='confessions',intro=node('section',undefined,'topic-intro '+(isConfession?'confession-intro':'question-intro'));const icon=node('span',undefined,'topic-intro-icon');icon.innerHTML=isConfession?'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/></svg>':reelIcon('comment');const text=node('div');text.append(node('span',isConfession?'MỘT GÓC ĐỂ LẮNG NGHE':'CÙNG NHAU TÌM LỜI GIẢI','topic-eyebrow'),node('h2',isConfession?'Chuyện của bạn, có người nghe':'Cứ hỏi, cùng nhau tìm câu trả lời'),node('p',isConfession?'Niềm vui, nỗi buồn hay một điều khó nói. Chia sẻ theo cách bạn thấy thoải mái.':'Tình cảm, cuộc sống hay sở thích — trao đổi từ trải nghiệm và tôn trọng nhau.'));intro.append(icon,text);panel.append(intro);panel.classList.add(isConfession?'topic-confessions':'topic-questions');
 }

 if(feedSection==='community')await stories(panel).catch(()=>{});composer(panel);const {posts}=await api('/posts'+(feedSection==='community'?'':'?category='+feedSection));
 if(['confessions','questions'].includes(feedSection)){const heading=node('div',undefined,'topic-list-heading');heading.append(node('h3',feedSection==='confessions'?'Những câu chuyện mới':'Câu hỏi từ cộng đồng'),node('span',posts.length+(feedSection==='confessions'?' câu chuyện':' câu hỏi')));panel.append(heading);}
 if(!posts.length){const labels={community:['Bảng tin còn trống','Chia sẻ lời chào đầu tiên hoặc theo dõi thêm bạn mới.'],confessions:['Chưa có tâm sự','Chia sẻ câu chuyện, cảm xúc của bạn với cộng đồng.'],questions:['Chưa có câu hỏi','Đặt câu hỏi để cùng trao đổi và tìm lời khuyên.'],events:['Chưa có sự kiện','Chia sẻ hoạt động sắp diễn ra, thời gian và địa điểm trong bài viết.']};panel.append(empty('📝',...labels[feedSection]));}
 for(const [index,p] of posts.entries()){panel.append(postCard(p));if(index===1&&feedSection==='community')newsPanel(panel,{preview:true}).catch(()=>{});}if(posts.length<2&&feedSection==='community')newsPanel(panel,{preview:true}).catch(()=>{});
}
// Tab "Trực tiếp" của trang Video: lưới các buổi đang live, chạm để vào xem ngay.
async function liveGrid(reel, isCurrent) {
  reel.classList.add("live-grid-host");
  const box = node("div", undefined, "live-grid");
  reel.append(box);
  // Trang được dựng ngoài màn rồi mới gắn vào, nên lần vẽ đầu không đòi box đã nằm trên trang.
  let first = true;
  const draw = async () => {
    if (!isCurrent() || (!first && !box.isConnected)) return;
    first = false;
    let rooms = [];
    try { rooms = (await api("/live/rooms")).rooms || []; } catch {}
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
    setTimeout(draw, 8000);
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
    if (blob.size > 12 * 1024 * 1024) throw Error("Video tối đa 12 MB.");
    await api("/shorts", "POST", { data: await toBase64(blob), caption });
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
  file.setAttribute("aria-label", "Tải video MP4 có sẵn, tối đa 12 MB và 60 giây");
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
  const full = node("button",undefined,"reel-fullscreen");full.type="button";full.setAttribute("aria-label","Toàn màn hình");full.innerHTML=reelIcon("fullscreen");
  const liveShortcut=node("button","● Trực tiếp","reel-live-shortcut");liveShortcut.type="button";liveShortcut.setAttribute("aria-label","Các buổi đang live");liveShortcut.classList.toggle("active",feed==="live");liveShortcut.onclick=()=>navigate("shorts",{feed:"live"}).catch(e=>status(e.message));tabs.prepend(liveShortcut);
  const currentVideo=()=>{const bounds=reel.getBoundingClientRect();let best=null,area=-1;for(const slide of reel.children){const r=slide.getBoundingClientRect(),visible=Math.max(0,Math.min(r.bottom,bounds.bottom)-Math.max(r.top,bounds.top));if(visible>area&&slide.querySelector("video")){best=slide.querySelector("video");area=visible;}}return best;};
  const updateFullButton=()=>{const active=!!document.fullscreenElement||document.body.classList.contains("reel-immersive")||!!currentVideo()?.webkitDisplayingFullscreen;full.setAttribute("aria-label",active?"Thoát toàn màn hình":"Toàn màn hình");full.setAttribute("aria-pressed",String(active));};
  const viewportRoot=$("social-panel");
  let viewportFrame=0;
  const syncViewport=()=>{cancelAnimationFrame(viewportFrame);viewportFrame=requestAnimationFrame(()=>{if(!reel.isConnected)return;const viewport=window.visualViewport;const height=viewport?.height||innerHeight,top=viewport?.offsetTop||0;viewportRoot.style.setProperty("--reel-viewport-height",height+"px");viewportRoot.style.setProperty("--reel-viewport-top",top+"px");if(!document.fullscreenElement&&!document.body.classList.contains("reel-immersive")){const bounds=reel.getBoundingClientRect(),nav=$("app")?.querySelector(":scope > nav"),navRect=nav?.getBoundingClientRect();const bottom=Math.min(top+height,navRect&&innerWidth<1000&&getComputedStyle(nav).position==="fixed"?navRect.top:top+height);const index=reel.clientHeight?Math.round(reel.scrollTop/reel.clientHeight):0;viewportRoot.style.setProperty("--reel-available-height",Math.max(0,bottom-bounds.top)+"px");reel.scrollTop=index*reel.clientHeight;}updateFullButton();});};
  const immersive=enabled=>{document.body.classList.toggle("reel-immersive",enabled);updateFullButton();syncViewport();};
  full.onclick=async()=>{
    if(document.body.classList.contains("reel-immersive")){immersive(false);return;}
    const video=currentVideo();
    if(video?.webkitDisplayingFullscreen){video.webkitExitFullscreen?.();return;}
    if(document.fullscreenElement){try{await document.exitFullscreen();}catch{}return;}
    // Call Safari's video API directly inside the tap, before any await loses user activation.
    const nativeEnter=video?.webkitEnterFullscreen||video?.webkitEnterFullScreen;
    if(nativeEnter){try{nativeEnter.call(video);return;}catch{immersive(true);return;}}
    if(panel.requestFullscreen){try{await panel.requestFullscreen();updateFullButton();return;}catch{}}
    immersive(true);
  };tabs.append(full);
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
    const box = empty("🎬", feed === "following" ? "Chưa có video từ người bạn theo dõi" : "Chưa có video nào", feed === "following" ? "Theo dõi thêm bạn mới hoặc khám phá video ở mục Đề xuất." : "Bấm + để quay video đầu tiên.");
    const go = node("button", "+ Quay video", "empty-cta");
    go.type = "button";
    go.onclick = () => openCamera().catch((e) => status(e.message));
    box.append(go);
    reel.append(box);
    return;
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
  document.addEventListener("fullscreenchange",syncViewport);
  cleanupShorts = () => {
    cancelAnimationFrame(viewportFrame);
    resizeObserver.disconnect();
    window.removeEventListener("resize",syncViewport);
    window.visualViewport?.removeEventListener("resize",syncViewport);
    window.visualViewport?.removeEventListener("scroll",syncViewport);
    document.removeEventListener("fullscreenchange",syncViewport);
    for(const name of ["--reel-available-height","--reel-viewport-height","--reel-viewport-top"])viewportRoot.style.removeProperty(name);
    closeReelComments();
    document.body.classList.remove("reel-immersive");
    if(document.fullscreenElement===panel)document.exitFullscreen().catch(()=>{});
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
    v.preload = "metadata";
    v.addEventListener("webkitbeginfullscreen",updateFullButton);
    v.addEventListener("webkitendfullscreen",syncViewport);
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
function field(form, label, value, type = "text") {
  const wrapper = node("label", label, "form-field");
  const input = node(type === "textarea" ? "textarea" : "input");
  if (type !== "textarea") input.type = type;
  input.value = value;
  wrapper.append(input);
  form.append(wrapper);
  return input;
}
function profilePresets(input,title,values,{multiple=false}={}){
 if(!input.hasAttribute('aria-label'))input.setAttribute('aria-label',title);
 input.removeAttribute('list');const wrap=node('div',undefined,'profile-choice-wrap');input.before(wrap);wrap.append(input);
 const trigger=node('button',undefined,'profile-choice-trigger');trigger.type='button';trigger.setAttribute('aria-label','Chọn '+title.toLocaleLowerCase('vi'));trigger.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="m8 10 4 4 4-4"/></svg>';wrap.append(trigger);
 trigger.onclick=event=>{
  event.preventDefault();const dialog=node('dialog',undefined,'profile-options-sheet');dialog.setAttribute('aria-label','Chọn '+title.toLocaleLowerCase('vi'));
  const head=node('div',undefined,'report-sheet-head'),close=node('button','×');close.type='button';close.setAttribute('aria-label','Đóng danh sách');close.onclick=()=>dialog.close();head.append(node('h2',title),close);
  const hint=node('p',multiple?'Chọn tối đa 10 mục. Bạn có thể thêm sở thích riêng.':'Chọn một gợi ý hoặc tự nhập bên dưới.','profile-options-hint');
  const search=node('input');search.type='search';search.placeholder='Tìm trong danh sách';search.setAttribute('aria-label','Tìm lựa chọn');
  const list=node('div',undefined,'profile-options-list');const initial=multiple?input.value.split(',').map(v=>v.trim()).filter(Boolean):[input.value.trim()];const selected=new Set(initial.map(value=>values.find(preset=>preset.toLocaleLowerCase('vi')===value.toLocaleLowerCase('vi'))||value));
  const options=[...new Set([...values,...selected].filter(Boolean))];let rows=[];
  const custom=node('input');custom.placeholder=multiple?'Thêm sở thích riêng':'Tự nhập nội dung khác';custom.maxLength=multiple?30:input.maxLength>0?input.maxLength:60;custom.setAttribute('aria-label','Nội dung tùy chọn');
  const feedback=node('p','','report-feedback');feedback.setAttribute('role','status');const done=node('button','Xong','report-submit');done.type='button';
  function update(){done.textContent=multiple?'Xong'+(selected.size?' · '+selected.size+' mục':''):'Xong';for(const row of rows)row.control.checked=selected.has(row.value);}
  for(const value of ['',...options]){if(multiple&&!value)continue;const row=node('label',undefined,'profile-option-row'),control=node('input');control.type=multiple?'checkbox':'radio';control.name='profile-preset';control.value=value;control.checked=selected.has(value);control.onchange=()=>{if(multiple){if(control.checked&&selected.size>=10){control.checked=false;feedback.textContent='Chọn tối đa 10 sở thích.';return;}if(control.checked)selected.add(value);else selected.delete(value);}else{selected.clear();selected.add(value);custom.value='';}feedback.textContent='';update();};row.append(node('span',value||'Chưa muốn chia sẻ'),control);rows.push({row,value,control});list.append(row);}
  search.oninput=()=>{const query=search.value.trim().toLocaleLowerCase('vi');for(const item of rows)item.row.hidden=!!query&&!item.value.toLocaleLowerCase('vi').includes(query);};
  done.onclick=()=>{const typed=custom.value.trim();if(multiple){const extra=typed.split(',').map(v=>v.trim()).filter(Boolean);const all=[...new Set([...selected,...extra])];if(all.length>10){feedback.textContent='Chọn tối đa 10 sở thích.';return;}input.value=all.join(', ');}else input.value=typed||[...selected][0]||'';input.dispatchEvent(new Event('input',{bubbles:true}));dialog.close();};
  dialog.append(head,hint,search,list,custom,feedback,done);document.body.append(dialog);dialog.addEventListener('close',()=>{dialog.remove();trigger.focus();},{once:true});dialog.showModal();update();
 };
}
async function profileConnections(user,kind){
 const title=kind==='followers'?'Người theo dõi':'Đang theo dõi',dialog=node('dialog',undefined,'connections-sheet');dialog.setAttribute('aria-label',title);const head=node('div',undefined,'report-sheet-head'),close=node('button','×');close.type='button';close.setAttribute('aria-label','Đóng danh sách theo dõi');close.onclick=()=>dialog.close();head.append(node('h2',title),close);const search=node('input');search.type='search';search.placeholder='Tìm theo tên';search.setAttribute('aria-label','Tìm trong danh sách theo dõi');const list=node('div',undefined,'connections-list');list.textContent='Đang tải…';dialog.append(head,search,list);document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
 try{const {users}=await api('/users/'+user.id+'/'+kind);if(!dialog.open)return;function render(){const query=search.value.trim().toLocaleLowerCase('vi');const matches=users.filter(u=>(u.name+' '+u.username).toLocaleLowerCase('vi').includes(query));list.replaceChildren();for(const u of matches){const row=node('button',undefined,'connection-row');row.type='button';const copy=node('span',undefined,'connection-copy');copy.append(node('strong',u.name),node('small','@'+u.username));row.append(avatar(u),copy,node('span','›','connection-arrow'));row.onclick=()=>{dialog.close();navigate('profile',{user:u.id}).catch(e=>status(e.message));};list.append(row);}if(!matches.length)list.append(node('p',query?'Không tìm thấy tài khoản.':kind==='followers'?'Chưa có người theo dõi.':'Chưa theo dõi ai.','connections-empty'));}search.oninput=render;render();}catch(e){list.textContent=e.message;}
}
async function profilePrivateAlbum(panel,user,own){
 const revision=navigationRevision,section=node('section',undefined,'social-card private-album');section.setAttribute('aria-label','Ảnh riêng tư');
 const heading=node('div',undefined,'private-album-head'),title=node('div');title.append(node('h3','Ảnh riêng tư'),node('p','0 ảnh','muted'));
 const refresh=action('↻',()=>reload().catch(e=>status(e.message)),'ghost');refresh.setAttribute('aria-label','Làm mới');refresh.title='Làm mới';heading.append(title,refresh);section.append(heading);

 let upload=null;
 if(own){const tools=node('div',undefined,'private-album-tools'),pick=node('label',undefined,'btn-like primary');upload=node('input');upload.type='file';upload.accept='image/png,image/jpeg,image/webp';upload.setAttribute('aria-label','Thêm ảnh riêng tư');pick.append(upload,node('span','Thêm ảnh'));pick.title='PNG, JPEG, WebP · tối đa 4 MB/ảnh · 24 ảnh';tools.append(pick);section.append(tools);upload.onchange=async()=>{const file=upload.files[0];if(!file)return;if(file.size>4*1024*1024){upload.value='';status('Ảnh phải nhỏ hơn 4 MB.');return;}upload.disabled=true;try{await api('/me/private-photos','POST',{data:await readMediaFile(file)});await reload(true);status('Đã thêm ảnh riêng tư.');}catch(e){status(e.message);}finally{upload.disabled=false;upload.value='';}};}
 const state=node('div',undefined,'private-album-state'),grid=node('div',undefined,'private-photo-grid'),requests=node('div',undefined,'private-access-list');const accessPanel=node('details',undefined,'private-access-panel'),accessSummary=node('summary','Quyền xem');accessPanel.append(accessSummary,requests);accessPanel.hidden=!own;section.append(grid,state,accessPanel);panel.append(section);
 let inFlight=null,signature='';
 async function openPhoto(photo){try{const current=await api('/users/'+user.id+'/private');if(revision!==navigationRevision)return;if(!['owner','granted'].includes(current.status)||!current.photos.some(p=>p.id===photo.id)){await reload(true);status('Bạn chưa có quyền xem ảnh này.');return;}closePrivatePhoto();const dialog=node('dialog',undefined,'private-photo-viewer');privatePhotoViewer=dialog;dialog.setAttribute('aria-label','Xem ảnh riêng tư');const bar=node('div',undefined,'private-photo-viewer-bar'),close=action('×',()=>dialog.close(),'ghost');close.setAttribute('aria-label','Đóng ảnh riêng tư');bar.append(node('strong','Ảnh riêng tư'),close);const image=node('img');image.src=photo.url;image.alt='Ảnh riêng tư của '+user.name;image.onerror=()=>{dialog.close();reload(true).catch(()=>{});status('Ảnh không còn khả dụng.');};dialog.append(bar,image);dialog.addEventListener('close',()=>{image.onerror=null;image.removeAttribute('src');dialog.remove();if(privatePhotoViewer===dialog)privatePhotoViewer=null;},{once:true});document.body.append(dialog);dialog.showModal();}catch(e){status(e.message);}}
 async function decide(viewer,decision,button){button.disabled=true;try{await api('/me/private/requests/'+viewer.id,'POST',{action:decision});await reload(true);status(decision==='grant'?'Đã đồng ý cho xem album.':decision==='revoke'?'Đã thu hồi quyền xem album.':'Đã từ chối yêu cầu.');}catch(e){status(e.message);button.disabled=false;}}
 function render(album,access){state.replaceChildren();grid.replaceChildren();requests.replaceChildren();title.querySelector('p').textContent=album.count+' ảnh';
 if(!own&&!['owner','granted'].includes(album.status)){closePrivatePhoto();if(album.status==='pending')state.append(node('p','Đang chờ duyệt.'));else if(album.status==='denied')state.append(node('p','Yêu cầu chưa được đồng ý.'));if(album.count){const pending=album.status==='pending',button=action(pending?'Hủy yêu cầu':'Yêu cầu xem ảnh riêng tư',async()=>{button.disabled=true;try{await api('/users/'+user.id+'/private/request',pending?'DELETE':'POST',{});await reload(true);if(!pending)status('Đã gửi yêu cầu trong tin nhắn.');}catch(e){status(e.message);button.disabled=false;}},pending?'secondary':'primary');state.append(button);}for(let i=0;i<Math.min(album.count,6);i++){const locked=node('div',undefined,'private-photo-locked');locked.setAttribute('aria-label','Ảnh riêng tư đã khóa');locked.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 018 0v3"/><path d="M12 14v3"/></svg>';grid.append(locked);}}
 else{for(const photo of album.photos){const tile=node('div',undefined,'private-photo-item'),open=action('',()=>openPhoto(photo),'private-photo-open'),image=node('img');open.setAttribute('aria-label','Xem ảnh riêng tư');image.src=photo.url;image.alt='Ảnh riêng tư';image.loading='lazy';open.append(image);tile.append(open);if(own){const remove=action('×',async()=>{if(!confirm('Xóa ảnh riêng tư này?'))return;remove.disabled=true;try{await api('/me/private-photos/'+photo.id,'DELETE');closePrivatePhoto();await reload(true);}catch(e){status(e.message);remove.disabled=false;}},'private-photo-delete');remove.setAttribute('aria-label','Xóa ảnh riêng tư');tile.append(remove);}grid.append(tile);}}
 if(!album.count)state.append(node('p','Chưa có ảnh.','muted'));
 if(own){const pending=access.filter(r=>r.status==='pending'),granted=access.filter(r=>r.status==='granted');accessSummary.textContent='Quyền xem'+(pending.length?' · '+pending.length+' chờ duyệt':'');requests.append(node('h4','Chờ duyệt ('+pending.length+')'));if(granted.length)requests.append(node('p','Đã cấp quyền','private-access-heading'));for(const request of [...pending,...granted]){const row=node('div',undefined,'private-access-row'),who=node('div',undefined,'private-access-person');who.append(personLink(request.user),node("span",request.user.name));const buttons=node('div',undefined,'private-access-actions');for(const [label,decision] of request.status==='pending'?[['Đồng ý','grant'],['Từ chối','deny']]:[['Thu hồi','revoke']]){const button=action(label,()=>decide(request.user,decision,button),decision==='grant'?'primary':'secondary');if(decision==='grant')button.title='Cho xem toàn bộ album, bao gồm ảnh thêm sau này. Người xem có thể lưu hoặc chụp ảnh.';buttons.append(button);}row.append(who,buttons);requests.append(row);}}
 }
 async function reload(force=false){if(inFlight){await inFlight;if(!force)return;}inFlight=(async()=>{const [album,access]=await Promise.all([api('/users/'+user.id+'/private'),own?api('/me/private/requests'):Promise.resolve({requests:[]})]);if(revision!==navigationRevision)return;const next=JSON.stringify([album,access]);if(next!==signature){signature=next;render(album,access.requests);}if(!['owner','granted'].includes(album.status))closePrivatePhoto();})();try{await inFlight;}finally{inFlight=null;}}
 privateAlbumRefresh=()=>{if(!document.hidden)return reload().catch(()=>{if(revision!==navigationRevision)return;closePrivatePhoto();state.textContent='Album không còn khả dụng.';grid.replaceChildren();requests.replaceChildren();});};
 try{await reload();}catch(e){state.textContent=e.message;state.append(action('Thử lại',()=>reload(true).catch(e=>status(e.message)),'secondary'));}
}

async function profile(panel, opts = {}) {
  const own = !opts.user || opts.user === (me && me.id);
  if (own) {
    me = (await api("/me")).user;
    paintMe();
  }
  const info = await api("/users/" + (own ? me.id : opts.user) + "/stats");
  const u = own ? me : info.user;
  // Phần đầu trang cá nhân
  const head = node("section", undefined, "social-card profile-head");
  const cover = node("div", undefined, "cover " + hue(u.id));
  if(u.cover){const image=node('img',undefined,'profile-cover-image');image.src=u.cover;image.alt='Ảnh bìa của '+u.name;cover.append(image);}
  if(own){const editCover=node('label',undefined,'profile-cover-edit'),uploadCover=node('input');uploadCover.type='file';uploadCover.accept='image/png,image/jpeg,image/webp';uploadCover.setAttribute('aria-label','Đổi ảnh bìa');editCover.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 7h4l2-3h4l2 3h4v13H4z"/><circle cx="12" cy="13" r="4"/></svg>';editCover.append(uploadCover);cover.append(editCover);uploadCover.onchange=async()=>{const file=uploadCover.files[0];if(!file)return;if(file.size>1024*1024){status('Chọn ảnh bìa nhỏ hơn 1 MB.');uploadCover.value='';return;}uploadCover.disabled=true;try{const data=await readMediaFile(file);me=(await api('/me/cover','POST',{data})).user;await navigate('profile');status('Đã cập nhật ảnh bìa.');}catch(e){status(e.message);}finally{uploadCover.disabled=false;uploadCover.value='';}};}
  const big = avatar(u);
  big.classList.add("big");
  const id = node("div", undefined, "profile-id");
  id.append(node("h2", u.name), node("p", "@" + u.username, "muted"));
  const bio = node("p", u.bio || (own ? "Thêm vài dòng giới thiệu để mọi người hiểu bạn hơn." : ""), "profile-bio");
  const nums = node("div", undefined, "profile-stats");
  for (const [n, label,kind] of [[info.posts, "bài viết",null], [info.followers, "người theo dõi","followers"], [info.following, "đang theo dõi","following"]]) {
    const s = node(kind?"button":"div");
    if(kind){s.type="button";s.setAttribute("aria-label",label+" ("+n+")");s.onclick=()=>profileConnections(u,kind);}
    s.append(node("b", String(n)), node("span", label));
    nums.append(s);
  }
  const tags = node("div", undefined, "tags");
  (u.interests || []).forEach((v) => tags.append(node("span", v)));
  const acts = node("div", undefined, "profile-actions");
  let directAvatar=null;
  if(own){directAvatar=node('button',undefined,'profile-avatar-edit');directAvatar.type='button';directAvatar.setAttribute('aria-label','Đổi ảnh đại diện trên trang cá nhân');directAvatar.title='Đổi ảnh đại diện';directAvatar.append(big);}
  head.append(cover, directAvatar||big, id);

  head.append(nums, acts);
  if(own)acts.prepend(action('Thêm vào tin',()=>openCamera({story:true}),'profile-story-action'));
  const navigation=node('div',undefined,'profile-sections');navigation.setAttribute('role','tablist');navigation.setAttribute('aria-label','Nội dung trang cá nhân');
  for(const [key,label] of [['posts','Tất cả'],['about','Giới thiệu'],['photos','Ảnh riêng tư']]){const button=node('button',label);button.type='button';button.setAttribute('role','tab');button.id='profile-tab-'+key;button.setAttribute('aria-controls','profile-content-'+key);button.setAttribute('aria-selected',String(key==='posts'));button.tabIndex=key==='posts'?0:-1;button.onclick=()=>{panel.dataset.profileSection=key;for(const other of navigation.children){other.setAttribute('aria-selected',String(other===button));other.tabIndex=other===button?0:-1;}for(const region of panel.querySelectorAll('.profile-content-section')){region.hidden=region.dataset.section!==key&&!(key==='posts'&&region.dataset.section==='about');}};button.onkeydown=e=>{const buttons=[...navigation.children],i=buttons.indexOf(button);let next;if(e.key==='ArrowRight')next=(i+1)%buttons.length;if(e.key==='ArrowLeft')next=(i+buttons.length-1)%buttons.length;if(e.key==='Home')next=0;if(e.key==='End')next=buttons.length-1;if(next!==undefined){e.preventDefault();buttons[next].click();buttons[next].focus();}};navigation.append(button);}head.append(navigation);
  panel.dataset.profileSection='posts';
  const profileContent=node('div',undefined,'profile-content');
  const intro=node('section',undefined,'profile-content-section profile-intro');intro.id='profile-content-about';intro.dataset.section='about';intro.setAttribute('role','region');intro.setAttribute('aria-label','Giới thiệu');intro.hidden=false;
  const timeline=node('section',undefined,'profile-content-section profile-timeline');timeline.id='profile-content-posts';timeline.dataset.section='posts';timeline.setAttribute('role','tabpanel');timeline.setAttribute('aria-labelledby','profile-tab-posts');
  const photos=node('section',undefined,'profile-content-section profile-photos');photos.id='profile-content-photos';photos.dataset.section='photos';photos.setAttribute('role','tabpanel');photos.setAttribute('aria-labelledby','profile-tab-photos');photos.hidden=true;
  profileContent.append(intro,timeline,photos);
  panel.append(head);
  const personalRows=[['Tuổi',u.age?u.age+' tuổi':''],['Thành phố',u.city],['Cách xưng hô',u.pronouns],['Giới tính',u.gender],['Xu hướng',u.orientation],['Vai trò',u.relationshipRole],['Kiểu kết nối',u.lookingFor],['Sở thích',(u.interests||[]).join(', ')]];
  {
   const details=node('section',undefined,'social-card profile-personal-info');details.setAttribute('aria-label','Thông tin cá nhân');details.append(node('h3','Thông tin cá nhân'));
   const values=node('dl');for(const [label,value] of personalRows){if(!value)continue;const row=node('div');const term=node('dt'),icon=node('span',undefined,'profile-detail-icon');icon.setAttribute('aria-hidden','true');const shape=label==='Thành phố'?'<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1116 0Z"/><circle cx="12" cy="10" r="3"/>':label==='Kiểu kết nối'?'<path d="m12 21-8-8a5 5 0 017-7l1 1 1-1a5 5 0 017 7Z"/>':label==='Sở thích'?'<path d="m12 3 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z"/>':'<circle cx="12" cy="8" r="4"/><path d="M4 22v-2a8 8 0 0116 0v2"/>';icon.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+shape+'</svg>';const description=node('span',label,'profile-detail-label');term.append(icon,description);term.title=label;row.append(term,node('dd',String(value)));values.append(row);}details.append(values);
   if(own&&!u.identityPublic&&[u.gender,u.orientation,u.relationshipRole,u.pronouns].some(Boolean))details.append(node('p','Thông tin danh tính chỉ hiển thị với bạn. Bật chia sẻ trong Cài đặt → Chỉnh sửa tài khoản nếu muốn công khai.','profile-info-privacy'));
   details.insertBefore(bio,details.querySelector('dl'));details.append(profileBadges(u),tags);
   if(!personalRows.some(([,value])=>value))details.append(node('p',own?'Thêm thông tin để bạn bè hiểu bạn hơn.':'Chưa có thông tin được chia sẻ.','muted'));

   intro.append(details);
  }
  const settings = node("div", undefined, "settings profile-edit-screen");
  let avatarPicker=null;
  if (own) {
    const pick = node("label", undefined, "btn-like secondary");
    const upload = node("input");
    upload.type = "file";
    upload.accept = "image/png,image/jpeg,image/webp";
    upload.setAttribute("aria-label", "Đổi ảnh đại diện, tối đa 1 MB");
    const photoIcon=node("span");photoIcon.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 7h4l2-3h4l2 3h4v13H4z"/><circle cx="12" cy="13" r="4"/></svg>';pick.append(upload,photoIcon);pick.setAttribute("aria-label","Đổi ảnh đại diện");
    pick.classList.add("avatar-cam");
    const directCamera=node('span',undefined,'profile-avatar-camera');directCamera.innerHTML=photoIcon.innerHTML;directAvatar.append(directCamera);directAvatar.onclick=()=>upload.click();
    upload.onchange = async () => {
      const f = upload.files[0];
      if (!f) return;
      if (f.size > 1024 * 1024){upload.value="";return status("Chọn ảnh nhỏ hơn 1 MB.");}
      const keepEditorOpen=!settings.hidden;directAvatar.disabled=true;
      try {
        const data = await new Promise((resolve, reject) => {
          const r = new FileReader();
          r.onload = () => resolve(r.result);
          r.onerror = reject;
          r.readAsDataURL(f);
        });
        me = (await api("/me/avatar", "POST", { data })).user;
        status("Đã cập nhật ảnh đại diện.");
        await navigate("profile",{settings:keepEditorOpen});
      } catch (e) {
        status(e.message);
      }finally{directAvatar.disabled=false;upload.value="";}
    };
    avatarPicker=pick;

  } else {
    acts.append(friendshipAction(u,()=>navigate("profile",opts)));
    if(u.friendship!=='outgoing')acts.append(
      action(u.following ? "Đang theo dõi" : "Theo dõi", async () => {
        await api("/users/" + u.id + "/follow", u.following ? "DELETE" : "POST", {});
        await navigate("profile", opts);
      }, u.following ? "secondary" : "follow")
    );
    acts.append(
      action("Nhắn tin", () => openChat(u)),
      more([
        ["Chặn", async () => {
          if (!confirm("Chặn " + u.name + "?")) return;
          await api("/users/" + u.id + "/block", "POST", {});
          status("Đã chặn " + u.name + ".");
          await navigate("feed");
        }],
        ["Báo cáo", () => report("user", u.id)],
      ]),
    );
  }
  if (own) {
    settings.hidden = !opts.settings;
    if(opts.settings)document.body.classList.add("profile-edit-open");
    // Sửa hồ sơ
    const form = node("form", undefined, "social-card profile-editor");
    const name = field(form, "Tên hiển thị", me.name);
    name.maxLength = 60;
    name.required = true;
    const bioInput = field(form, "Giới thiệu", me.bio, "textarea");
    bioInput.maxLength = 500;
    bioInput.setAttribute("aria-label","Giới thiệu");
    const interests = field(form, "Sở thích, phân cách bằng dấu phẩy", me.interests.join(", "));
    interests.maxLength = 350;
    const age = field(form, "Tuổi (không bắt buộc)", me.age || "", "number"); age.min = 18; age.max = 99;
    const city = field(form, "Khu vực / thành phố", me.city || ""); city.maxLength = 80;
    for(const [control,label,accessible] of [[age,"Tuổi","Tuổi (không bắt buộc)"],[city,"Thành phố","Khu vực / thành phố"],[interests,"Sở thích","Sở thích, phân cách bằng dấu phẩy"]]){control.closest("label").firstChild.textContent=label;control.setAttribute("aria-label",accessible);}
    interests.placeholder="Cà phê, du lịch, âm nhạc…";bioInput.placeholder="Viết một chút về bạn…";
    const chooseIdentity = (label, value, values, key) => {
      const input = field(form, label, value || ""); input.maxLength = 60;
      input.placeholder = "Chọn hoặc nhập";profilePresets(input,label,values);return input;
    };
    const gender = chooseIdentity("Giới tính", me.gender, ["Nam", "Nữ", "Nam chuyển giới", "Nữ chuyển giới", "Phi nhị nguyên", "Đang tìm hiểu"], "gender");
    const orientation = chooseIdentity("Xu hướng tính dục", me.orientation, ["Gay / Đồng tính nam", "Les / Đồng tính nữ", "Song tính", "Toàn tính", "Dị tính", "Vô tính", "Đang tìm hiểu"], "orientation");
    const relationshipRole = chooseIdentity("Vai trò", me.relationshipRole, ["Top", "Bottom", "Vers", "Vers Top", "Vers Bottom", "Side", "Đang tìm hiểu"], "role");
    const pronouns = field(form, "Cách xưng hô", me.pronouns || ""); pronouns.maxLength = 30;
    const lookingFor = field(form, "Bạn muốn tìm kết nối như thế nào?", me.lookingFor || ""); lookingFor.maxLength = 100;lookingFor.setAttribute("aria-label","Bạn muốn tìm kết nối như thế nào?");lookingFor.closest("label").firstChild.textContent="Tìm kiếm";
    profilePresets(pronouns,'Cách xưng hô',['Anh','Chị','Em','Bạn','Mình','Họ / Them']);pronouns.placeholder='Chọn cách xưng hô';
    profilePresets(city,'Thành phố',['TP. Hồ Chí Minh','Hà Nội','Đà Nẵng','Hải Phòng','Cần Thơ','Huế','Nha Trang','Đà Lạt','Vũng Tàu','Biên Hòa','Quy Nhơn']);city.placeholder='Chọn hoặc nhập thành phố';
    profilePresets(lookingFor,'Kiểu kết nối',['Kết bạn','Trò chuyện','Hẹn hò','Mối quan hệ nghiêm túc','Bạn đồng hành','Đang tìm hiểu']);lookingFor.placeholder='Bạn muốn kết nối thế nào?';
    profilePresets(interests,'Sở thích',['Cà phê','Du lịch','Âm nhạc','Phim ảnh','Đọc sách','Nấu ăn','Thể thao','Gym','Yoga','Chạy bộ','Nhiếp ảnh','Thú cưng','Game','Nghệ thuật','Thiên nhiên','Thời trang'],{multiple:true});
    const identityLabel = node("label", undefined, "switch-row"); const identityPublic = node("input"); identityPublic.type = "checkbox"; identityPublic.checked = !!me.identityPublic; identityLabel.append(node("span", "Hiển thị giới tính, xu hướng và vai trò trên hồ sơ"), identityPublic); form.append(identityLabel);
    form.append(node("p", "Tất cả thông tin đều do bạn tự chọn. Để trống nếu không muốn chia sẻ.", "muted field-help"));
    const activityLabel = node("label", undefined, "switch-row"); const showActivity = node("input"); showActivity.type = "checkbox"; showActivity.checked = me.showActivity !== false; activityLabel.append(node("span", "Hiển thị khi tôi đang hoạt động"), showActivity); form.append(activityLabel);
    const visibleLabel = node("label", undefined, "switch-row");
    const visible = node("input");
    visible.type = "checkbox";
    visible.checked = me.discoverable;
    visibleLabel.append(node("span", "Cho phép xuất hiện trong Khám phá"), visible);
    form.append(visibleLabel);
    const dmLabel = node("label", "Ai được nhắn tin cho bạn", "form-field");
    const dm = node("select");
    for (const [value, label] of [
      ["everyone", "Mọi thành viên"],
    ]) {
      const o = node("option", label);
      o.value = value;
      dm.append(o);
    }
    dm.value = "everyone";
    dmLabel.append(dm);
    form.append(dmLabel);
    const editorHeader=node("div",undefined,"profile-editor-head");
    const editorCopy=node("div");editorCopy.append(node("span","HỒ SƠ CỦA BẠN","profile-editor-eyebrow"),node("h2","Thể hiện chính mình"),node("p","Chọn những điều bạn muốn chia sẻ với mọi người."));editorHeader.append(avatar(me));
    if(avatarPicker){avatarPicker.classList.remove("avatar-cam");avatarPicker.classList.add("profile-photo-edit");avatarPicker.querySelector("span").textContent="Đổi ảnh đại diện";editorHeader.append(avatarPicker);}
    const section=(title,description,inputs)=>{const group=node("fieldset",undefined,"profile-editor-section");group.append(node("legend",title),node("p",description,"field-help"));const grid=node("div",undefined,"profile-field-grid");for(const control of inputs)grid.append(control.closest("label")||control);group.append(grid);return group;};
    const basics=section("Thông tin cơ bản","Những thông tin giúp bạn bè nhận ra bạn.",[name,age,city,pronouns]);
    const about=section("Một chút về bạn","Giới thiệu, sở thích và điều bạn muốn kết nối.",[bioInput,interests,lookingFor]);
    const identity=section("Danh tính của bạn","Bạn có thể tự mô tả hoặc để trống bất kỳ thông tin nào.",[gender,orientation,relationshipRole]);
    const privacy=section("Quyền riêng tư","Bạn quyết định ai có thể tìm thấy và liên hệ với mình.",[identityLabel,activityLabel,visibleLabel,dmLabel]);
    const counter=node("small",bioInput.value.length+" / 500","profile-bio-counter");bioInput.closest("label").append(counter);bioInput.addEventListener("input",()=>{counter.textContent=bioInput.value.length+" / 500";});
    const save = node("button", "Xong");save.className="profile-save";
    const cancel=node("button","‹","secondary");cancel.setAttribute("aria-label","Quay lại hồ sơ");cancel.type="button";cancel.onclick=()=>navigate("profile");
    const savebar=node("div",undefined,"profile-savebar"),saveState=node("span","Thông tin của bạn được bảo vệ.");savebar.append(saveState,cancel,save);
    form.addEventListener("input",()=>{saveState.textContent="Bạn có thay đổi chưa lưu";form.classList.add("has-changes");});
    for(const help of form.querySelectorAll(":scope > .field-help"))help.remove();
    const editorBar=node("div",undefined,"profile-editor-bar");editorBar.append(cancel,node("h2","Chỉnh sửa hồ sơ"),save);
    form.append(editorBar,editorHeader,basics,about,identity,privacy);
    form.onsubmit = async (e) => {
      e.preventDefault();
      save.disabled = true;
      try {
        me = (
          await api("/me", "PATCH", {
            name: name.value,
            bio: bioInput.value,
            interests: interests.value.split(","),
            discoverable: visible.checked,
            dmMode: dm.value,
            age: age.value ? Number(age.value) : null, city: city.value,
            gender: gender.value, orientation: orientation.value, relationshipRole: relationshipRole.value,
            pronouns: pronouns.value, lookingFor: lookingFor.value,
            identityPublic: identityPublic.checked, showActivity: showActivity.checked,
          })
        ).user;
        $("name").value = me.name;
        paintMe();
        await navigate("profile");
        status("Đã lưu hồ sơ.");
      } catch (e) {
        status(e.message);
      } finally {
        save.disabled = false;
      }
    };
    settings.append(form);
    panel.append(settings);
  }
  panel.append(profileContent);
  await profilePrivateAlbum(photos,u,own);
  // Bài viết của người này
  const timelineHead=node('div',undefined,'social-card profile-timeline-head');timelineHead.append(node('h3','Bài viết'));if(own)timelineHead.append(action('Tạo bài viết',async()=>{await navigate('feed');document.querySelector('.composer textarea')?.focus();},'secondary'));timeline.append(timelineHead);
  const { posts } = await api("/posts?user=" + encodeURIComponent(u.id));
  if (!posts.length)
    timeline.append(empty("📝", "Chưa có bài viết", own ? "Chia sẻ điều đầu tiên trên Bảng tin nhé." : "Người này chưa đăng gì."));
  for (const p of posts) timeline.append(postCard(p));
  if(opts.privateAlbum)navigation.querySelector('#profile-tab-photos').click();
}
function friendshipAction(u,refresh){
 if(u.friendship==='friends'){const menu=more([['Hủy kết bạn',async()=>{if(!confirm('Hủy kết bạn với '+u.name+'?'))return;await api('/users/'+u.id+'/friendship','DELETE',{});await refresh();}]],'Bạn bè');menu.classList.add('friendship-menu');menu.querySelector('summary').textContent='Bạn bè ▾';return menu;}
 const incoming=u.friendship==='incoming',outgoing=u.friendship==='outgoing';
 if(outgoing){const menu=more([['Hủy lời mời',async()=>{await api('/users/'+u.id+'/friend-request','DELETE',{});await refresh();}],...(u.following?[['Bỏ theo dõi',async()=>{await api('/users/'+u.id+'/follow','DELETE',{});await refresh();}]]:[])],'Lời mời đã gửi');menu.classList.add('friendship-menu');menu.querySelector('summary').textContent=u.following?'Đang theo dõi ▾':'Đã gửi lời mời ▾';return menu;}
 const button=action(incoming?'Xác nhận kết bạn':outgoing?'Hủy lời mời':'Kết bạn',async()=>{button.disabled=true;try{await api('/users/'+u.id+'/friend-request'+(incoming?'/respond':''),outgoing?'DELETE':'POST',incoming?{action:'accept'}:{});await refresh();}catch(e){status(e.message);button.disabled=false;}},outgoing?'secondary':'primary');return button;
}
async function friendsPage(panel,opts={}){
 const revision=navigationRevision;let section=opts.section||'friends',filter='all',payload=null,signature='';
 const heading=node('div',undefined,'view-head');heading.append(node('h2','Bạn bè'));panel.append(heading);
 const tabs=node('div',undefined,'friends-tabs');tabs.setAttribute('role','tablist');tabs.setAttribute('aria-label','Kết nối bạn bè');panel.append(tabs);
 for(const [key,label] of [['friends','Bạn bè'],['following','Đang theo dõi'],['requests','Lời mời'],['suggestions','Đề xuất']]){const b=node('button',label,'secondary');b.type='button';b.setAttribute('role','tab');b.setAttribute('aria-selected',String(key===section));b.onclick=()=>{section=key;for(const other of tabs.children)other.setAttribute('aria-selected',String(other===b));draw();};tabs.append(b);}
 const search=node('input',undefined,'friends-search');search.type='search';search.placeholder='Tìm bạn bè';search.setAttribute('aria-label','Tìm trong bạn bè');search.oninput=()=>draw();panel.append(search);
 const filters=node('div',undefined,'friends-filters');filters.setAttribute('role','group');filters.setAttribute('aria-label','Trạng thái bạn bè');panel.append(filters);
 for(const [key,label] of [['all','Tất cả'],['online','Trực tuyến'],['offline','Ngoại tuyến']]){const b=node('button',label,'secondary');b.type='button';b.setAttribute('aria-pressed',String(key===filter));b.onclick=()=>{filter=key;for(const other of filters.children)other.setAttribute('aria-pressed',String(other===b));draw();};filters.append(b);}
 const list=node('div',undefined,'friends-list');list.setAttribute('aria-live','polite');panel.append(list);
 function row(u,mode){const card=node('article',undefined,'friend-row'),person=node('button',undefined,'friend-person');person.type='button';person.setAttribute('aria-label','Xem trang của '+u.name);const picture=node('span',undefined,'friend-picture');picture.append(avatar(u));if(u.isActive)picture.append(node('span',undefined,'friend-online-dot'));const text=node('span',undefined,'friend-copy');text.append(node('strong',u.name));const presence=u.activityShared===false?'Ẩn trạng thái':u.isActive?'Trực tuyến':'Ngoại tuyến';text.append(node('span',presence,'friend-presence '+(u.isActive?'is-online':'')));if(mode==='suggestions'&&(u.sharedInterests||u.sameCity))text.append(node('span',u.sharedInterests?u.sharedInterests+' sở thích chung':'Cùng thành phố','friend-reason'));person.append(picture,text);person.onclick=()=>navigate('profile',{user:u.id});const actions=node('div',undefined,'friend-row-actions');
 if(mode==='requests'&&u.friendship==='incoming'){actions.append(friendshipAction(u,()=>reload(true)),action('Xóa lời mời',async()=>{await api('/users/'+u.id+'/friend-request/respond','POST',{action:'decline'});await reload(true);},'secondary'));}
 else if(mode==='following'){actions.append(friendshipAction(u,()=>reload(true)),action('Bỏ theo dõi',async()=>{await api('/users/'+u.id+'/follow','DELETE',{});await reload(true);},'secondary'));}
 else if(mode==='friends')actions.append(action('Nhắn tin',()=>openChat(u),'secondary'),friendshipAction(u,()=>reload(true)));
 else {actions.append(friendshipAction(u,()=>reload(true)));if(mode==='suggestions')actions.append(action(u.following?'Đang theo dõi':'Theo dõi',async()=>{await api('/users/'+u.id+'/follow',u.following?'DELETE':'POST',{});await reload(true);},'secondary'));}
 card.append(person,actions);return card;}
 function draw(){if(!payload)return;filters.hidden=!['friends','following'].includes(section);list.replaceChildren();const q=search.value.trim().toLocaleLowerCase('vi');const matches=u=>(u.name+' '+u.username).toLocaleLowerCase('vi').includes(q);
 if(section==='friends'&&!payload.friends.length&&filter==='all'){list.append(node('h3','Đề xuất kết bạn'));const suggestions=payload.suggestions.filter(matches);for(const u of suggestions)list.append(row(u,'suggestions'));if(!suggestions.length)list.append(node('p','Chưa có đề xuất phù hợp.','friends-empty'));return;}
 if(section==='requests'){for(const [title,users] of [['Lời mời đã nhận',payload.incoming],['Lời mời đã gửi',payload.outgoing]]){const visible=users.filter(matches);if(!visible.length)continue;list.append(node('h3',title+' ('+visible.length+')'));for(const u of visible)list.append(row(u,'requests'));}}
 else{const users=(section==='friends'?payload.friends:section==='following'?payload.following:payload.suggestions).filter(matches).filter(u=>!['friends','following'].includes(section)||filter==='all'||filter==='online'&&u.isActive||filter==='offline'&&!u.isActive&&u.activityShared!==false);users.sort((a,b)=>Number(b.isActive)-Number(a.isActive));for(const u of users)list.append(row(u,section));}
 if(!list.children.length){list.append(node('p',search.value?'Không tìm thấy bạn bè.':section==='requests'?'Chưa có lời mời kết bạn.':section==='suggestions'?'Chưa có đề xuất mới.':filter==='online'?'Chưa có bạn bè trực tuyến.':filter==='offline'?'Chưa có bạn bè ngoại tuyến.':'Danh sách bạn bè đang trống.','friends-empty'));if(section==='friends'&&filter==='all')list.append(action('Xem đề xuất kết bạn',()=>tabs.children[3].click(),'primary'));}}
 async function reload(force=false){const [friends,requests,suggestions,following]=await Promise.all([api('/friends'),api('/friend-requests'),api('/friend-suggestions'),api('/users/'+me.id+'/following')]);if(revision!==navigationRevision)return;payload={friends:friends.users,incoming:requests.incoming,outgoing:requests.outgoing,suggestions:suggestions.users,following:following.users};const badge=$('friends-count');if(badge)badge.textContent=requests.incoming.length?(requests.incoming.length>99?'99+':'+'+requests.incoming.length):'';const next=JSON.stringify(payload);if(force||next!==signature){signature=next;draw();}}
 friendsRefresh=()=>reload().catch(()=>{});await reload();
}
async function accountSettings(panel) {
 me=(await api('/me')).user;
 const header=node('div',undefined,'view-head settings-heading');header.append(action('‹',()=>navigate('profile'),'settings-back'),node('div'));header.lastChild.append(node('h2','Cài đặt & quyền riêng tư'),node('p','Quản lý tài khoản theo cách của bạn.','muted'));header.firstChild.setAttribute('aria-label','Quay lại trang cá nhân');panel.append(header);
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
 const quick=node("section",undefined,"social-card");quick.append(node("h3","Đăng nhập trên thiết bị này"),node("p","Quản lý quyền chạm hồ sơ để đăng nhập nhanh.","muted"));
 const locationControl=node("section",undefined,"social-card");locationControl.append(node("h3","Vị trí"),node("p","Tự động làm mới người ở gần trong lúc sử dụng app.","muted"));
 const locationEnabled=me.hasLocation;
 locationControl.append(action(locationEnabled?"Tắt vị trí":"Bật vị trí",async()=>{if(locationEnabled){me=(await api("/me/location","PATCH",{enabled:false})).user;rememberLocation(false);stopLocationTracking();await navigate("settings");}else{await navigate("discover");const enable=document.querySelector(".nearby-consent button");enable?.click();}}));panel.append(locationControl);
 const remembered=(await api("/remembered")).accounts;
 if(remembered.some(account=>account.id===me.id))quick.append(action("Tắt đăng nhập nhanh trên thiết bị này",async()=>{await api("/remembered/"+me.id,"DELETE",{});status("Đã gỡ quyền đăng nhập nhanh.");await navigate("settings");}));else quick.append(node("p","Tài khoản này chưa bật đăng nhập nhanh.","muted"));panel.append(quick);
 const visibility=node('section',undefined,'social-card settings-visibility');visibility.append(node('h3','Quyền hiển thị'),node('p','Chọn những thông tin bạn muốn chia sẻ.','muted'));
 for(const [key,label,description] of [['discoverable','Xuất hiện trong Khám phá','Cho phép thành viên khác tìm thấy hồ sơ của bạn.'],['showActivity','Trạng thái hoạt động','Hiển thị khi bạn đang online và lần hoạt động gần nhất.'],['identityPublic','Chia sẻ thông tin danh tính','Hiển thị giới tính, xu hướng và vai trò trên trang cá nhân.']]){const row=node('label',undefined,'settings-switch'),text=node('span'),input=node('input');input.type='checkbox';input.checked=key==='showActivity'?me[key]!==false:!!me[key];input.setAttribute('aria-label',label);text.append(node('strong',label),node('small',description));row.append(text,input);input.onchange=async()=>{const before=!input.checked;input.disabled=true;try{me=(await api('/me','PATCH',{[key]:input.checked})).user;status('Đã lưu '+label.toLowerCase()+'.');}catch(e){input.checked=before;status(e.message);}finally{input.disabled=false;}};visibility.append(row);}
 const groups=[];
 function group(title,items){const section=node('section',undefined,'settings-group');section.append(node('h3',title));for(const [label,description,icon,content] of items){const details=node('details',undefined,'settings-entry'),summary=node('summary'),glyph=node('span',undefined,'settings-entry-icon');glyph.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+icon+'</svg>';const copy=node('span',undefined,'settings-entry-copy');copy.append(node('strong',label),node('small',description));const arrow=node('span','›','settings-entry-arrow');arrow.setAttribute('aria-hidden','true');summary.append(glyph,copy,arrow);details.append(summary,content);section.append(details);}groups.push(section);panel.append(section);}
 const userIcon='<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0116 0v2"/>';
 group('Tài khoản & bảo mật',[
 ['Mật khẩu và đăng nhập','Đổi mật khẩu để bảo vệ tài khoản','<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 018 0v3"/>',pw],
 ['Đăng nhập nhanh','Quản lý đăng nhập trên thiết bị này','<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 18h4"/>',quick]]);
 group('Đối tượng & quyền riêng tư',[
 ['Quyền hiển thị','Khám phá, hoạt động và thông tin cá nhân',userIcon,visibility],
 ['Chặn','Quản lý những người bạn đã chặn','<circle cx="12" cy="12" r="9"/><path d="m6 6 12 12"/>',blocks],
 ['Vị trí','Quản lý tính năng tìm người ở gần','<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1116 0Z"/><circle cx="12" cy="10" r="3"/>',locationControl]]);
 group('Ứng dụng & thiết bị',[
 ['Cài Kinnect cho iOS','Thêm Kinnect vào màn hình chính iPhone','<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M9 11h6m-3-3v6"/>',iosInstall]]);
 const noResults=node('p','Không tìm thấy cài đặt phù hợp.','settings-no-results');noResults.hidden=true;panel.append(noResults);
 search.oninput=()=>{const q=search.value.trim().toLocaleLowerCase('vi');let count=0;for(const section of groups){let visible=0;for(const entry of section.querySelectorAll('.settings-entry')){entry.hidden=!!q&&!entry.textContent.toLocaleLowerCase('vi').includes(q);if(!entry.hidden){visible++;count++;}if(q&&!entry.hidden)entry.open=true;}section.hidden=!visible;}noResults.hidden=count>0;};

}
function holdConversation(row,u,refresh){
 const kind=u.isGroup?'group':'direct';let timer=null,x=0,y=0,held=false;
 function stop(){clearTimeout(timer);timer=null;delete row.dataset.holding;}
 function open(){stop();held=true;const dialog=node('dialog',undefined,'more-sheet conversation-menu');dialog.setAttribute('aria-label','Tùy chọn cuộc trò chuyện');const head=node('div',undefined,'report-sheet-head');head.append(node('h2',u.name));const close=node('button','×');close.type='button';close.setAttribute('aria-label','Đóng tùy chọn cuộc trò chuyện');close.onclick=()=>dialog.close();head.append(close);dialog.append(head);
 const actions=[[u.pinned?'Bỏ ghim cuộc trò chuyện':'Ghim cuộc trò chuyện',async()=>{await api('/chat-preferences/'+kind+'/'+u.id,'POST',{pinned:!u.pinned});await refresh();}],[u.muted?'Bật thông báo':'Tắt thông báo',async()=>{await api('/chat-preferences/'+kind+'/'+u.id,'POST',{muted:!u.muted});await refresh();}],["Xóa cuộc trò chuyện",()=>clearConversation(kind,u.id)]];
 for(const [label,fn] of actions){const button=node('button',label);button.type='button';button.onclick=async()=>{dialog.close();try{await fn();}catch(e){status(e.message);}};dialog.append(button);}document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();}
 function start(px,py){stop();held=false;x=px;y=py;row.dataset.holding='true';timer=setTimeout(()=>{if(row.isConnected)open();},450);}
 row.addEventListener('touchstart',e=>{if(e.touches.length===1)start(e.touches[0].clientX,e.touches[0].clientY);},{passive:true});row.addEventListener('touchmove',e=>{const t=e.touches[0];if(!t||Math.abs(t.clientX-x)>12||Math.abs(t.clientY-y)>12)stop();},{passive:true});row.addEventListener('touchend',e=>{stop();if(held&&e.cancelable)e.preventDefault();},{passive:false});row.addEventListener('touchcancel',stop,{passive:true});
 row.addEventListener('pointerdown',e=>{if(e.pointerType!=='touch'&&e.button===0)start(e.clientX,e.clientY);});row.addEventListener('pointermove',e=>{if(e.pointerType!=='touch'&&(Math.abs(e.clientX-x)>12||Math.abs(e.clientY-y)>12))stop();});for(const event of ['pointerup','pointercancel','pointerleave'])row.addEventListener(event,e=>{if(e.pointerType!=='touch')stop();});row.addEventListener('contextmenu',e=>{e.preventDefault();if(!document.querySelector('.conversation-menu[open]'))open();});row.addEventListener('click',e=>{if(held){held=false;e.preventDefault();e.stopImmediatePropagation();}},true);
}
async function inbox(panel) {
  const head=node('div',undefined,'view-head inbox-heading');head.append(node('h2','Tin nhắn'));
  const compose=node('button',undefined,'inbox-new');compose.type='button';compose.setAttribute('aria-label','Tin nhắn mới');compose.innerHTML=reelIcon('send');compose.onclick=async()=>{await navigate('discover');document.querySelector('.search-bar input')?.focus();};head.append(compose);const makeGroup=node('button','Tạo nhóm','inbox-create-group');makeGroup.type='button';makeGroup.onclick=()=>createChatGroup().catch(e=>status(e.message));head.append(makeGroup);panel.append(head);
  const search=node('input',undefined,'inbox-search');search.type='search';search.placeholder='Tìm cuộc trò chuyện';search.setAttribute('aria-label','Tìm cuộc trò chuyện');panel.append(search);
  const [{users},{groups}]=await Promise.all([api('/conversations'),api('/groups')]);
  let entries=[...users,...groups.map(g=>({...g,isGroup:true,username:'',last:g.last?{...g.last,body:(g.last.mine?'':g.last.name+': ')+g.last.body}:null}))].sort((a,b)=>Number(!!b.pinned)-Number(!!a.pinned)||(b.last?.created||b.created||0)-(a.last?.created||a.created||0));
  const filters=node('div',undefined,'inbox-filters');let unreadOnly=false;
  const all=node('button','Tất cả','active'),unread=node('button','Chưa đọc');all.type=unread.type='button';filters.append(all,unread);panel.append(filters);
  const list=node('div',undefined,'inbox-list');panel.append(list);
  function render(){
   all.classList.toggle('active',!unreadOnly);unread.classList.toggle('active',unreadOnly);all.setAttribute('aria-pressed',String(!unreadOnly));unread.setAttribute('aria-pressed',String(unreadOnly));
   const query=search.value.trim().toLocaleLowerCase('vi');const matches=entries.filter(u=>(!unreadOnly||u.unread>0)&&(!query||(u.name+' '+u.username).toLocaleLowerCase('vi').includes(query)));
   list.replaceChildren();
   for(const u of matches){
    const row=node('button',undefined,'inbox-row'+(u.unread?' is-unread':''));row.type='button';
    const photo=node('div',undefined,'inbox-avatar');photo.append(u.isGroup?node('span','Nh','avatar group-avatar'):avatar(u));if(u.isActive)photo.append(node('span',undefined,'inbox-online'));
    const text=node('div',undefined,'row-text');text.append(node('b',u.name),node('span',u.last?(u.last.mine?'Bạn: ':'')+u.last.body:'Bắt đầu trò chuyện','muted'));
    const meta=node('div',undefined,'inbox-meta');meta.append(node('time',u.last?timeAgo(u.last.created):''));if(u.pinned){const pin=node('span','📌','inbox-pin');pin.setAttribute('aria-label','Đã ghim cuộc trò chuyện');meta.append(pin);}if(u.muted){const mute=node('span','🔕','inbox-muted');mute.setAttribute('aria-label','Đã tắt thông báo');meta.append(mute);}if(u.unread){const badge=node('span',u.unread>99?'99+':String(u.unread),'inbox-unread');badge.setAttribute('aria-label',u.unread+' tin nhắn chưa đọc');meta.append(badge);}
    row.append(photo,text,meta);holdConversation(row,u,()=>inboxRefresh?.());row.onclick=()=> (u.isGroup?openGroupChat(u.id):openChat(u)).catch(e=>status(e.message));list.append(row);
   }
   if(!matches.length){list.append(empty('💬',query?'Không tìm thấy cuộc trò chuyện':unreadOnly?'Bạn đã đọc hết tin nhắn':'Chưa có cuộc trò chuyện',query?'Thử tên khác.':unreadOnly?'Tin nhắn mới sẽ xuất hiện ở đây.':'Chọn Tin nhắn mới để bắt đầu kết nối.'));}
  }
  inboxRefresh=async()=>{const [{users},{groups}]=await Promise.all([api('/conversations'),api('/groups')]);if(!list.isConnected||list.querySelector('[data-holding]'))return;entries=[...users,...groups.map(g=>({...g,isGroup:true,username:'',last:g.last?{...g.last,body:(g.last.mine?'':g.last.name+': ')+g.last.body}:null}))].sort((a,b)=>Number(!!b.pinned)-Number(!!a.pinned)||(b.last?.created||b.created||0)-(a.last?.created||a.created||0));render();};
  search.oninput=render;all.onclick=()=>{unreadOnly=false;render();};unread.onclick=()=>{unreadOnly=true;render();};render();
}
async function memberPicker({title='Tạo nhóm',existing=[]}={}){
 const dialog=node('dialog',undefined,'group-picker');dialog.setAttribute('aria-label',title);const head=node('div',undefined,'report-sheet-head');head.append(node('h2',title));const close=node('button','×');close.type='button';close.setAttribute('aria-label','Đóng chọn thành viên');head.append(close);dialog.append(head);
 const name=node('input');name.placeholder='Tên nhóm';name.maxLength=80;name.setAttribute('aria-label','Tên nhóm');if(!existing.length)dialog.append(name);
 const search=node('input');search.type='search';search.placeholder='Tìm thành viên theo tên';search.setAttribute('aria-label','Tìm thành viên nhóm');dialog.append(search);
 const count=node('p','Chưa chọn thành viên','group-selection'),list=node('div',undefined,'group-candidates'),error=node('p','','report-feedback'),submit=node('button',title==='Tạo nhóm'?'Tạo nhóm':'Thêm thành viên','report-submit');submit.type='button';dialog.append(count,list,error,submit);const chosen=new Map();let request=0,delay;
 async function load(){const revision=++request;try{const {users}=await api('/discover?q='+encodeURIComponent(search.value));if(!dialog.open||revision!==request)return;list.replaceChildren();for(const u of users.filter(u=>!existing.includes(u.id))){const label=node('label',undefined,'group-candidate'),check=node('input');check.type='checkbox';check.checked=chosen.has(u.id);check.onchange=()=>{if(check.checked)chosen.set(u.id,u);else chosen.delete(u.id);count.textContent=chosen.size?'Đã chọn '+chosen.size+' thành viên':'Chưa chọn thành viên';};label.append(avatar(u),node('span',u.name),check);list.append(label);}if(!list.children.length)list.append(node('p','Không tìm thấy thành viên.','muted'));}catch(e){error.textContent=e.message;}}
 document.body.append(dialog);dialog.showModal();load();search.oninput=()=>{clearTimeout(delay);delay=setTimeout(load,250);};
 return new Promise(resolve=>{dialog.addEventListener('close',()=>{clearTimeout(delay);dialog.remove();resolve(null);},{once:true});close.onclick=()=>dialog.close();submit.onclick=()=>{if(!chosen.size||(!existing.length&&!name.value.trim())){error.textContent='Nhập tên nhóm và chọn thành viên.';return;}resolve({name:name.value.trim(),members:[...chosen.keys()]});dialog.close();};});
}
async function createChatGroup(){const selected=await memberPicker();if(!selected)return;const {group}=await api('/groups','POST',selected);await openGroupChat(group.id);}
async function groupDetails(group){
 const dialog=node('dialog',undefined,'group-picker');dialog.setAttribute('aria-label','Thông tin nhóm');const head=node('div',undefined,'report-sheet-head');head.append(node('h2','Thông tin nhóm'));const close=node('button','×');close.type='button';close.setAttribute('aria-label','Đóng thông tin nhóm');close.onclick=()=>dialog.close();head.append(close);dialog.append(head);
 if(group.owner===me.id){const rename=node('form',undefined,'group-rename'),name=node('input');name.value=group.name;name.maxLength=80;name.required=true;name.setAttribute('aria-label','Đổi tên nhóm');const save=node('button','Lưu tên');rename.append(name,save);rename.onsubmit=async e=>{e.preventDefault();save.disabled=true;try{await api('/groups/'+group.id,'PATCH',{name:name.value});dialog.close();await openGroupChat(group.id);}catch(e){status(e.message);save.disabled=false;}};dialog.append(rename);}
 dialog.append(node('p',group.members.length+' thành viên','group-selection'));for(const u of group.members){const row=node('div',undefined,'group-candidate');row.append(avatar(u),node('span',u.name),node('small',u.id===group.owner?'Trưởng nhóm':''));if(group.owner===me.id&&u.id!==me.id){const remove=node('button','Xóa','group-remove');remove.type='button';remove.setAttribute('aria-label','Xóa '+u.name+' khỏi nhóm');remove.onclick=async()=>{if(!confirm('Xóa '+u.name+' khỏi nhóm?'))return;try{const {group:updated}=await api('/groups/'+group.id+'/members','DELETE',{userId:u.id});dialog.close();await openGroupChat(group.id);await groupDetails(updated);}catch(e){status(e.message);}};row.append(remove);}dialog.append(row);}
 if(group.owner===me.id){const add=node('button','Thêm thành viên','report-submit');add.type='button';add.onclick=async()=>{dialog.close();const selected=await memberPicker({title:'Thêm thành viên',existing:group.members.map(u=>u.id)});if(selected)try{await api('/groups/'+group.id+'/members','POST',selected);await openGroupChat(group.id);}catch(e){status(e.message);}};dialog.append(add);}
 const leave=node('button','Rời nhóm','group-leave');leave.type='button';leave.onclick=async()=>{if(!confirm('Rời nhóm '+group.name+'?'))return;try{await api('/groups/'+group.id+'/leave','POST',{});dialog.close();await navigate('inbox');}catch(e){status(e.message);}};dialog.append(leave);document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
}
function renderPrivateAlbumMessage(bubble,m,reload){
 const album=m.privateAlbum;if(!album||m.recalled)return false;
 const card=node('div',undefined,'album-chat-card');card.append(node('strong','Ảnh riêng tư'));
 const text=album.event==='request'?(album.owner===me.id?'Yêu cầu xem ảnh riêng tư của bạn':'Bạn đã gửi yêu cầu xem ảnh'):album.event==='granted'?'Đã đồng ý cho xem ảnh':album.event==='revoked'?'Đã thu hồi quyền xem':'Yêu cầu chưa được đồng ý';card.append(node('p',text));
 if(album.status==='pending'&&album.event==='request'&&album.owner===me.id){const actions=node('div',undefined,'album-chat-actions');for(const [label,decision] of [['Đồng ý','grant'],['Từ chối','deny']]){const button=action(label,async()=>{for(const b of actions.children)b.disabled=true;try{await api('/me/private/requests/'+album.viewer,'POST',{action:decision,requestId:album.requestId});await reload();}catch(e){status(e.message);await reload();for(const b of actions.children)b.disabled=false;}},decision==='grant'?'primary':'secondary');actions.append(button);}card.append(actions);}
 else if(album.status==='granted')card.append(action('Xem ảnh riêng tư',()=>navigate('profile',{user:album.owner,privateAlbum:true}),'primary'));
 else card.append(node('span',album.status==='pending'?'Đang chờ duyệt':album.status==='denied'?'Chưa được đồng ý':'Yêu cầu đã kết thúc','album-chat-status'));
 bubble.append(card);return true;
}
function messageControls(bubble,m,kind,reload,conversationId){
 bubble.dataset.messageId=m.id;
 const actions=node('div',undefined,'message-controls');
 if(!m.recalled){const react=node('button',undefined,'message-react');react.type='button';react.setAttribute('aria-label','Thả cảm xúc tin nhắn');react.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><path d="M8 14s1 3 4 3 4-3 4-3M8 9h.01M16 9h.01"/></svg>';react.onclick=()=>reactionPicker(react,m.myReaction,async reaction=>{await api('/chat-messages/'+kind+'/'+m.id+'/reaction','POST',{reaction});await reload();},{iconOnly:true});actions.append(react);}
 const items=[];if(!m.recalled)items.push([m.pinned?'Bỏ ghim tin nhắn':'Ghim tin nhắn',async()=>{await api('/chat-messages/'+kind+'/'+m.id+'/pin',m.pinned?'DELETE':'POST',{});await reload();}]);items.push(['Tắt / bật thông báo',()=>toggleChatMute(kind,conversationId)],['Xóa cuộc trò chuyện',()=>clearConversation(kind,conversationId)]);items.push(['Xóa ở phía tôi',async()=>{await api('/chat-messages/'+kind+'/'+m.id,'DELETE',{});await reload();}]);
 if(m.sender===me.id&&!m.recalled)items.unshift(['Thu hồi với mọi người',async()=>{if(!confirm('Thu hồi tin nhắn này với mọi người?'))return;await api('/chat-messages/'+kind+'/'+m.id+'/recall','POST',{});await reload();}]);
 const menu=more(items,'Tùy chọn tin nhắn');actions.append(menu);bubble.append(actions);
 const openHeld=()=>{if(m.recalled){menu.querySelector('summary').click();return;}reactionPicker(menu.querySelector('summary'),m.myReaction,async reaction=>{await api('/chat-messages/'+kind+'/'+m.id+'/reaction','POST',{reaction});await reload();},{iconOnly:true,items});};
 const quickMenu=node('button','⋯','message-quick-menu');quickMenu.type='button';quickMenu.setAttribute('aria-label','Mở thao tác tin nhắn');quickMenu.onclick=openHeld;bubble.append(quickMenu);
 let holdTimer=null,startX=0,startY=0,held=false;
 const cancelHold=()=>{clearTimeout(holdTimer);holdTimer=null;delete bubble.dataset.holding;};
 const startHold=(x,y)=>{cancelHold();held=false;startX=x;startY=y;bubble.dataset.holding='true';holdTimer=setTimeout(()=>{cancelHold();if(!bubble.isConnected)return;held=true;openHeld();},450);};
 const interactive=target=>target.closest('button,video,summary,input');
 bubble.addEventListener('touchstart',e=>{if(e.touches.length!==1||interactive(e.target))return;startHold(e.touches[0].clientX,e.touches[0].clientY);},{passive:true});
 bubble.addEventListener('touchmove',e=>{const t=e.touches[0];if(!t||Math.abs(t.clientX-startX)>12||Math.abs(t.clientY-startY)>12)cancelHold();},{passive:true});
 bubble.addEventListener('touchend',e=>{cancelHold();if(held&&e.cancelable)e.preventDefault();},{passive:false});bubble.addEventListener('touchcancel',cancelHold,{passive:true});
 bubble.addEventListener('pointerdown',e=>{if(e.pointerType==='touch'||e.button!==0||interactive(e.target))return;startHold(e.clientX,e.clientY);});
 bubble.addEventListener('pointermove',e=>{if(e.pointerType!=='touch'&&(Math.abs(e.clientX-startX)>12||Math.abs(e.clientY-startY)>12))cancelHold();});
 for(const event of ['pointerup','pointercancel','pointerleave'])bubble.addEventListener(event,e=>{if(e.pointerType!=='touch')cancelHold();});
 bubble.addEventListener('click',e=>{if(held&&!e.target.closest('button,summary')){e.preventDefault();e.stopPropagation();}held=false;},true);
 bubble.addEventListener('contextmenu',e=>{if(interactive(e.target))return;e.preventDefault();cancelHold();if(!document.querySelector('dialog.reaction-picker[open]'))openHeld();});

 if(m.pinned)bubble.prepend(node('span','Ghim','message-pin-label'));
 const counts=Object.entries(m.reactions||{}).filter(([,n])=>n>0);if(counts.length){const count=node('button',counts.map(([key,n])=>COMMENT_REACTIONS[key][0]+' '+n).join(' '),'message-reaction-count');count.type='button';count.setAttribute('aria-label','Cảm xúc của tin nhắn');count.onclick=()=>reactionPicker(count,m.myReaction,async reaction=>{await api('/chat-messages/'+kind+'/'+m.id+'/reaction','POST',{reaction});await reload();},{iconOnly:true});bubble.append(count);}if(m.recalled)bubble.classList.add('message-recalled');
}
async function toggleChatMute(kind,id){const current=await api('/chat-preferences/'+kind+'/'+id);const result=await api('/chat-preferences/'+kind+'/'+id,'POST',{muted:!current.muted});status(result.muted?'Đã tắt thông báo cuộc trò chuyện.':'Đã bật thông báo cuộc trò chuyện.');}
function pinnedMessages(box,messages){box.querySelector('.chat-pins')?.remove();const pinned=messages.filter(m=>m.pinned&&!m.recalled);if(!pinned.length)return;const strip=node('div',undefined,'chat-pins');for(const m of pinned){const button=node('button','📌 '+(m.body||m.attachment?.name||'Tệp đính kèm'));button.type='button';button.onclick=()=>{const target=box.querySelector('[data-message-id="'+m.id+'"]');target?.scrollIntoView({block:'center',behavior:'smooth'});};strip.append(button);}box.querySelector('.chat-head').after(strip);}
async function clearConversation(kind,id){if(!confirm('Xóa cuộc trò chuyện ở phía bạn? Lịch sử của người khác vẫn được giữ.'))return;await api(kind==='group'?'/groups/'+id+'/messages':'/users/'+id+'/messages','DELETE',{});await navigate('inbox');status('Đã xóa cuộc trò chuyện ở phía bạn.');}
function activityText(user){if(user.isActive)return 'Đang hoạt động';if(!user.lastActiveAt)return 'Không hiển thị hoạt động';const minutes=Math.max(1,Math.floor((Date.now()-user.lastActiveAt)/60000));return minutes<60?'Hoạt động '+minutes+' phút trước':minutes<1440?'Hoạt động '+Math.floor(minutes/60)+' giờ trước':'Hoạt động '+Math.floor(minutes/1440)+' ngày trước';}
function chatFileSize(size){return size<1024*1024?Math.ceil(size/1024)+' KB':(size/1024/1024).toFixed(1)+' MB';}
function renderChatAttachment(bubble,file){if(!file)return;const box=node('div',undefined,'chat-attachment');if(file.kind==='image'){const link=node('a');link.href=file.url;link.target='_blank';link.rel='noopener';const image=node('img');image.src=file.url;image.alt=file.name;image.loading='lazy';link.append(image);box.append(link);}else if(file.kind==='video'){const video=node('video');video.src=file.url;video.controls=true;video.playsInline=true;video.preload='metadata';box.append(video);}const download=node('a',undefined,'chat-file-download');download.href=file.url;download.download=file.name;download.setAttribute('aria-label','Tải xuống '+file.name);const text=node('span');text.append(node('strong',file.name),node('small',chatFileSize(file.size)));download.append(node('span','↓','chat-file-icon'),text);box.append(download);bubble.append(box);}
function chatAttachmentComposer(form,input){
 input.required=false;const attach=node('button',undefined,'chat-attach-button');attach.type='button';attach.setAttribute('aria-label','Đính kèm ảnh, video hoặc tệp');attach.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="m8 12 6-6a3 3 0 0 1 4 4l-8 8a5 5 0 0 1-7-7l9-9"/><path d="m8 12 6-6"/></svg>';const fileInput=node('input');fileInput.type='file';fileInput.hidden=true;fileInput.setAttribute('aria-label','Tệp đính kèm tin nhắn');const preview=node('div',undefined,'chat-attachment-preview');preview.hidden=true;form.before(preview);form.prepend(attach,fileInput);let selected=null,loading=false,objectUrl=null;const clear=()=>{selected=null;fileInput.value='';preview.replaceChildren();preview.hidden=true;if(objectUrl)URL.revokeObjectURL(objectUrl);objectUrl=null;};attach.onclick=()=>fileInput.click();fileInput.onchange=async()=>{const file=fileInput.files[0];if(!file)return;clear();if(file.size>20*1024*1024){status('Tệp tối đa 20 MB.');return;}loading=true;attach.disabled=true;try{const data=await readMediaFile(file);if(!form.isConnected)return;selected={name:file.name,data};const info=node('span',file.name+' · '+chatFileSize(file.size));if(file.type.startsWith('image/')||file.type.startsWith('video/')){objectUrl=URL.createObjectURL(file);const media=node(file.type.startsWith('image/')?'img':'video');media.src=objectUrl;if(media.tagName==='VIDEO'){media.muted=true;media.playsInline=true;}preview.append(media);}const remove=node('button','×');remove.type='button';remove.setAttribute('aria-label','Gỡ tệp đính kèm');remove.onclick=clear;preview.append(info,remove);preview.hidden=false;}catch(e){status(e.message);}finally{loading=false;attach.disabled=false;}};
 return {get file(){return selected;},get loading(){return loading;},clear};
}
async function openGroupChat(id){
 if(!await navigate('inbox'))return;const revision=navigationRevision,panel=$('social-panel');const {group}=await api('/groups/'+id);if(revision!==navigationRevision)return;
 const box=node('div',undefined,'social-card chat-box'),head=node('div',undefined,'chat-head'),back=node('button','←','icon-btn');back.type='button';back.setAttribute('aria-label','Quay lại hộp thư');back.onclick=()=>navigate('inbox');const info=node('button',undefined,'chat-who');info.type='button';const identity=node('div',undefined,'chat-identity');identity.append(node('b',group.name),node('span',group.members.length+' thành viên'));info.append(node('span','Nh','avatar group-avatar'),identity);info.setAttribute('aria-label','Thông tin nhóm');info.onclick=()=>groupDetails(group).catch(e=>status(e.message));head.append(back,info,more([['Tắt / bật thông báo',()=>toggleChatMute('group',id)],['Xóa cuộc trò chuyện',()=>clearConversation('group',id)]],'Tùy chọn cuộc trò chuyện'));
 const log=node('div',undefined,'dm-log');log.setAttribute('role','log');log.setAttribute('aria-live','polite');const form=node('form',undefined,'dm-compose'),input=node('input');input.placeholder='Nhắn tin cho nhóm…';input.setAttribute('aria-label','Tin nhắn nhóm');input.required=true;input.maxLength=2000;const send=node('button');send.type='submit';send.setAttribute('aria-label','Gửi');send.innerHTML=reelIcon('send');form.append(input,send);box.append(head,log,form);panel.replaceChildren(box);const attachment=chatAttachmentComposer(form,input);fitChatViewport(box);let signature='';
 async function load(){if(document.hidden)return;const {messages}=await api('/groups/'+id+'/messages');if(!log.isConnected||revision!==navigationRevision||log.querySelector('[data-holding]'))return;const next=JSON.stringify(messages);if(next===signature)return;const wasBottom=log.scrollHeight-log.clientHeight-log.scrollTop<60;const first=!signature;signature=next;pinnedMessages(box,messages);log.replaceChildren();if(!messages.length)log.append(node('p','Gửi lời chào đầu tiên đến nhóm.','chat-intro'));let day='';for(const m of messages){const date=new Date(m.created).toLocaleDateString('vi-VN');if(day!==date){log.append(node('div',date,'day-sep'));day=date;}const mine=m.sender===me.id,bubble=node('article',undefined,'bubble'+(mine?' mine':''));if(!mine)bubble.append(node('b',m.author.name,'group-message-author'));if(m.body)bubble.append(node('p',m.body));renderChatAttachment(bubble,m.attachment);bubble.append(node('small',clock(m.created)));if(mine&&!m.recalled)bubble.append(node('span',m.receipt?.seenCount?'Đã xem · '+m.receipt.seenCount:m.receipt?.deliveredCount?'Đã nhận · '+m.receipt.deliveredCount:'Đã gửi','message-receipt'));messageControls(bubble,m,'group',load,id);log.append(bubble);}if(first||wasBottom)log.scrollTop=log.scrollHeight;refreshUnread().catch(()=>{});}
 form.onsubmit=async e=>{e.preventDefault();if(send.disabled||attachment.loading)return;if(!input.value.trim()&&!attachment.file)return;send.disabled=true;try{await api('/groups/'+id+'/messages','POST',{body:input.value,attachment:attachment.file});input.value='';attachment.clear();await load();log.scrollTop=log.scrollHeight;}catch(e){status(e.message);}finally{send.disabled=false;input.focus();}};await load();if(revision!==navigationRevision||!log.isConnected)return;timer=setInterval(()=>load().catch(e=>{clearInterval(timer);status(e.message);}),4000);
}
async function openChat(u) {
  if (!await navigate("inbox")) return;
  const chatRevision = navigationRevision;
  const panel = $("social-panel");
  const head = node("div", undefined, "chat-head");
  const back = node("button", "←", "icon-btn");
  back.type = "button";
  back.setAttribute("aria-label", "Quay lại hộp thư");
  back.onclick = () => navigate("inbox");
  const who = node("button", undefined, "chat-who");
  who.type = "button";
  const identity=node("div",undefined,"chat-identity");identity.append(node("b",u.name),node("span",activityText(u)));
  who.append(avatar(u),identity);
  who.onclick = () => navigate("profile", { user: u.id });
  const call=node("button",undefined,"chat-call");call.type="button";call.setAttribute("aria-label","Gọi video");call.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="5" width="12" height="14" rx="3"/><path d="m15 9 6-4v14l-6-4"/></svg>';call.onclick=()=>startVideoCall(u).catch(e=>status(e.message));
  const voice=node('button',undefined,'chat-call');voice.type='button';voice.setAttribute('aria-label','Gọi thoại');voice.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 3h4l2 5-3 2a15 15 0 0 0 6 6l2-3 5 2v4a2 2 0 0 1-2 2C9 21 3 15 3 5a2 2 0 0 1 2-2Z"/></svg>';voice.onclick=()=>startVideoCall(u,'audio').catch(e=>status(e.message));
  head.append(back, who,voice,call, more([["Tắt / bật thông báo",()=>toggleChatMute('direct',u.id)],["Xóa cuộc trò chuyện",()=>clearConversation('direct',u.id)],["Báo cáo người này", () => report("user", u.id)]]));
  const box = node("div", undefined, "social-card chat-box");
  const log = node("div", undefined, "dm-log");
  log.setAttribute("role", "log");
  log.setAttribute("aria-live", "polite");
  const form = node("form", undefined, "dm-compose");
  const input = node("input");
  input.maxLength = 2000;
  input.required = true;
  input.placeholder = "Nhắn tin…";
  input.setAttribute("aria-label", "Tin nhắn riêng");
  const button = node("button", undefined);button.type="submit";button.setAttribute("aria-label","Gửi");button.innerHTML=reelIcon("send");
  form.append(input, button);
  box.append(head, log, form);
  panel.replaceChildren(box);const attachment=chatAttachmentComposer(form,input);fitChatViewport(box);
  let signature = "";
  async function load() {
    if(document.hidden)return;
    const result = await api("/users/" + u.id + "/messages");
    if(result.user)identity.querySelector("span").textContent=activityText(result.user);
    if (tab !== "inbox" || !log.isConnected||log.querySelector("[data-holding]")) return;
    const next = JSON.stringify(result.messages);
    if (signature === next) return;
    signature = next;
    pinnedMessages(box,result.messages);
    log.replaceChildren();
    if(!result.messages.length){const intro=node("div",undefined,"chat-intro");intro.append(avatar(u),node("h3",u.name),node("p","Gửi lời chào để bắt đầu cuộc trò chuyện."));log.append(intro);}
    let lastDay = "";
    for (const m of result.messages) {
      const day = new Date(m.created).toLocaleDateString("vi-VN");
      if (day !== lastDay) {
        log.append(node("div", day === new Date().toLocaleDateString("vi-VN") ? "Hôm nay" : day, "day-sep"));
        lastDay = day;
      }
      const mine = m.sender === me.id;
      const bubble = node("article", undefined, "bubble " + (mine ? "mine" : ""));
      if(!renderPrivateAlbumMessage(bubble,m,load)&&m.body)bubble.append(node("p",m.body));renderChatAttachment(bubble,m.attachment);bubble.append(node("small",clock(m.created)));
      if (!mine) {
        const flag = node("button", "⚑", "bubble-flag");
        flag.type = "button";
        flag.setAttribute("aria-label", "Báo cáo tin nhắn");
        flag.onclick = () => report("message", m.id).catch((e) => status(e.message));
        bubble.append(flag);
      }
      if(mine&&!m.recalled){const receipt=node("span",m.receipt?.seenAt?"Đã xem":m.receipt?.deliveredAt?"Đã nhận":"Đã gửi","message-receipt");bubble.append(receipt);}
      messageControls(bubble,m,"direct",load,u.id);
      log.append(bubble);
    }
    log.scrollTop = log.scrollHeight;
  }
  form.onsubmit = async (e) => {
    e.preventDefault();
    if(button.disabled||attachment.loading)return;if(!input.value.trim()&&!attachment.file)return;
    button.disabled = true;
    try {
      await api("/users/" + u.id + "/messages", "POST", { body: input.value,attachment:attachment.file });
      input.value = "";attachment.clear();
      await load();
    } catch (e) {
      status(e.message);
    } finally {
      button.disabled = false;
      input.focus();
    }
  };
  await load();
  refreshUnread().catch(()=>{});
  if (chatRevision !== navigationRevision || !log.isConnected) return;
  input.focus();
  timer = setInterval(
    () =>
      load().catch((e) => {
        clearInterval(timer);
        status(e.message);
      }),
    4000,
  );
}
let notificationCache = [], knownNotificationIds = new Set(), notificationBaseline = false;
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
function closeNotificationCenter() {
  if (notificationPanel) notificationPanel.hidden = true;
  $("notification-bell")?.setAttribute("aria-expanded", "false");
}
function requestBrowserNotifications() {
  if (!("Notification" in window)) { status("Trình duyệt này chưa hỗ trợ thông báo. Trên iPhone, hãy thêm Kinnect vào màn hình chính trước."); return; }
  if (Notification.permission === "denied") { status("Thông báo đang bị chặn. Bạn có thể bật lại trong phần quyền của trang trên trình duyệt."); return; }
  Notification.requestPermission().then(permission => {
    if (permission === "granted") { document.querySelector(".notification-optin")?.remove(); status("Đã bật thông báo khi Kinnect đang mở."); }
    else status("Bạn vẫn nhận được thông báo ở biểu tượng chuông trong app.");
    renderNotificationCenter();
  }).catch(() => status("Chưa bật được thông báo trình duyệt. Bạn vẫn xem được thông báo trong app."));
}
function notificationOptIn() {
  document.querySelector(".notification-optin")?.remove();
  if (!("Notification" in window) || Notification.permission !== "default") return;
  try { if (sessionStorage.getItem("kinnect-notification-dismissed") === "1") return; } catch {}
  const banner = node("aside", undefined, "notification-optin"); banner.setAttribute("aria-label", "Bật thông báo tin nhắn");
  const text = node("div"); text.append(node("b", "Bật thông báo tin nhắn?"), node("p", "Nhận thông báo tin nhắn khi Kinnect đang mở, kể cả lúc bạn chuyển sang tab khác."));
  const enable = node("button", "Bật thông báo"); enable.type = "button"; enable.onclick = requestBrowserNotifications;
  const dismiss = node("button", "×", "ghost"); dismiss.type = "button"; dismiss.setAttribute("aria-label", "Để sau"); dismiss.onclick = () => { banner.remove(); try { sessionStorage.setItem("kinnect-notification-dismissed", "1"); } catch {} };
  banner.append(text, enable, dismiss); $("social-panel").before(banner);
}
async function openNotification(n) {
  closeNotificationCenter();
  if (!n.seen) await api("/notifications", "POST", { ids: [n.id] });
  if(n.kind==="friend_request")await navigate("friends",{section:"requests"});
  else if(n.kind==="friend_accepted")await navigate("friends");
  else if(n.kind==="private_request")await openChat(n.actor);
  else if(n.kind.startsWith("private_"))await openChat(n.actor);
  else if (n.kind === "message") await openChat(n.actor);
  else if(n.kind === "group_message")await openGroupChat(n.ref);
  else if (n.kind === "like" || n.kind === "comment") await navigate("profile");
  else if (n.kind === "gift") await navigate("live");
  else await navigate("profile", { user: n.actor.id });
  await refreshUnread();
}
function renderNotificationCenter() {
  if (!notificationPanel) return;
  notificationPanel.replaceChildren();
  const head = node("div", undefined, "notification-center-head"); head.append(node("h2", "Thông báo"));
  const read = action("Đánh dấu đã đọc", async () => { await api("/notifications", "POST", {}); await refreshUnread(); }, "ghost");
  head.append(read); notificationPanel.append(head);
  const tabs = node("div", undefined, "chips");
  for (const [label, value] of [["Tất cả", "all"], ["Chưa đọc", "unread"]]) { const b = node("button", label, "chip" + (notificationFilter === value ? " active" : "")); b.type = "button"; b.onclick = () => { notificationFilter = value; renderNotificationCenter(); }; tabs.append(b); }
  notificationPanel.append(tabs);
  const list = node("div", undefined, "notification-center-list");
  const items = notificationCache.filter(n => notificationFilter !== "unread" || !n.seen).slice(0, 10);
  for (const n of items) {
    const row = node("button", undefined, "list-row note-row" + (n.seen ? "" : " unread")); row.type = "button";
    const text = node("div", undefined, "row-text"); const line = node("p"); line.append(node("b", n.actor.name), " ", node("span", NOTE_TEXT[n.kind] || "có hoạt động mới."));
    text.append(line, node("small", timeAgo(n.created), "meta")); row.append(avatar(n.actor), text); if (!n.seen) row.append(node("span", undefined, "dot"));
    row.onclick = () => openNotification(n).catch(e => status(e.message)); list.append(row);
  }
  if (!items.length) list.append(empty("🔔", notificationFilter === "unread" ? "Bạn đã xem hết thông báo" : "Chưa có thông báo", "Lượt theo dõi và tin nhắn mới sẽ xuất hiện ở đây."));
  notificationPanel.append(list);
  const footer = node("div", undefined, "notification-center-footer");
  footer.append(action("Xem tất cả thông báo", () => navigate("notifications"), "ghost wide"));
  const permission = node("button", "Notification" in window && Notification.permission === "granted" ? "✓ Đã bật thông báo trình duyệt" : "Bật thông báo trình duyệt", "ghost wide"); permission.type = "button"; permission.disabled = "Notification" in window && Notification.permission === "granted"; permission.onclick = requestBrowserNotifications; footer.append(permission);
  const sound = node("label", undefined, "notification-sound"); const check = node("input"); check.type = "checkbox"; check.checked = soundEnabled; check.onchange = () => { soundEnabled = check.checked; try { localStorage.setItem("kinnect-notification-sound", soundEnabled ? "on" : "off"); } catch {} }; sound.append(check, "Âm báo trong app"); footer.append(sound); notificationPanel.append(footer);
}
function initializeNotificationCenter() {
  const bell = $("notification-bell");
  if (!notificationPanel) {
    notificationPanel = node("section", undefined, "notification-center"); notificationPanel.id = "notification-center"; notificationPanel.hidden = true; notificationPanel.setAttribute("role", "dialog"); notificationPanel.setAttribute("aria-label", "Thông báo"); $("app").append(notificationPanel);
    document.addEventListener("click", event => { if (!notificationPanel.hidden && !notificationPanel.contains(event.target) && !bell.contains(event.target)) closeNotificationCenter(); });
    document.addEventListener("keydown", event => { if (event.key === "Escape" && !notificationPanel.hidden) { closeNotificationCenter(); bell.focus(); } });
  }
  bell.onclick = () => openNotificationCenter();
  notificationOptIn();
}
// Mở popup Thông báo từ nút chuông.
function openNotificationCenter() {
  if (!notificationPanel) return;
  menu(false);
  notificationPanel.hidden = false;
  $("notification-bell").setAttribute("aria-expanded", "true");
  renderNotificationCenter();
  refreshUnread().catch(e => status(e.message));
  // Chuyển focus vào nút Đóng nếu giao diện có nút này.
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
async function refreshUnread() {
  if (!me) return;
  if (unreadRequest) return unreadRequest;
  const userId = me.id;
  unreadRequest = (async () => {
    const { notifications,friendRequestsPending } = await api("/notifications");
    const friendBadge=$("friends-count");if(friendBadge)friendBadge.textContent=friendRequestsPending?(friendRequestsPending>99?"99+":"+"+String(friendRequestsPending)):"";
    if (!me || me.id !== userId) return;
    const fresh = notificationBaseline ? notifications.filter(n => !n.seen && !n.muted && !knownNotificationIds.has(n.id)) : [];
    notificationCache = notifications; notificationBaseline = true;
    notifications.forEach(n => knownNotificationIds.add(n.id));
    if (knownNotificationIds.size > 500) knownNotificationIds = new Set(notifications.map(n => n.id));
    const count = notifications.filter(n => !n.seen).length;
    $("unread").textContent = count ? (count > 99 ? "99+" : String(count)) : "";
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
  try { await unreadRequest; } finally { unreadRequest = null; }
}
function startActivityHeartbeat() {
  clearInterval(activityTimer);
  const beat = () => { if (me && !document.hidden) api("/me/activity", "POST", {}).catch(() => {}); };
  beat(); activityTimer = setInterval(beat, 25000);
}
window.addEventListener("kinnect-notifications", () => refreshUnread().catch(() => {}));
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
  gift: "đã gửi quà thử nghiệm miễn phí.",
  like: "đã thích bài viết của bạn.",
  comment: "đã bình luận về bài viết của bạn.",
};
async function notifications(panel) {
  const head = node("div", undefined, "view-head");
  head.append(node("h2", "Thông báo"));
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
async function adminPanel(panel) {
  const head = node("div", undefined, "view-head");
  head.append(node("h2", "Quản trị"));
  panel.append(head);
  await musicAdmin(panel);
  const { requests } = await api("/admin/password-resets");
  const open = requests.filter((r) => r.status === "open");
  panel.append(node("h3", "Yêu cầu quên mật khẩu" + (open.length ? " (" + open.length + ")" : "")));
  if (!open.length) panel.append(node("p", "Không có yêu cầu đang chờ.", "muted"));
  for (const r of open) {
    const card = node("article", undefined, "social-card");
    card.append(
      node("h3", "@" + r.username + (r.user_id ? "" : " · không có tài khoản")),
      node("p", "Liên hệ: " + r.contact),
      node("p", r.note ? "Ghi chú: " + r.note : "Không có ghi chú.", "muted"),
      node("p", new Date(r.created).toLocaleString("vi-VN"), "muted fine"),
    );
    if (r.user_id)
      card.append(
        action("Cấp mật khẩu tạm", async () => {
          if (!confirm("Đặt lại mật khẩu cho @" + r.username + "? Chỉ làm khi đã xác minh đúng chủ tài khoản.")) return;
          const res = await api("/admin/password-resets/" + r.id + "/reset", "POST", {});
          prompt("Mật khẩu tạm của @" + res.username + " (sao chép và gửi cho người dùng):", res.temporaryPassword);
          await navigate("admin");
        }, "follow"),
      );
    card.append(
      action("Bỏ qua", async () => {
        await api("/admin/password-resets/" + r.id + "/dismiss", "POST", {});
        await navigate("admin");
      }),
    );
    panel.append(card);
  }
  panel.append(node("h3", "Báo cáo"));
  const { reports } = await api("/admin/reports");
  if (!reports.length) panel.append(node("p", "Chưa có báo cáo."));
  for (const r of reports) {
    const card = node("article", undefined, "social-card");
    card.append(
      node("h3", r.target_type + " · " + r.status),
      node("p", r.reason),
      node(
        "p",
        r.subject?.body || r.subject?.username || "Nội dung không còn tồn tại.",
      ),
    );
    const perform = async (action, target) => {
      if (!confirm("Xác nhận " + action + "?")) return;
      await api("/admin/moderate", "POST", { action, target });
      await navigate("admin");
    };
    if (r.target_type === "short" && r.subject)
      card.append(
        action(r.subject.hidden ? "Hiện video" : "Ẩn video", () =>
          perform(r.subject.hidden ? "show-short" : "hide-short", r.target_id),
        ),
      );
    if (r.target_type === "post" && r.subject)
      card.append(
        action(r.subject.hidden ? "Hiện bài" : "Ẩn bài", () =>
          perform(r.subject.hidden ? "show-post" : "hide-post", r.target_id),
        ),
      );
    if (r.subject?.userId)
      card.append(
        action("Đình chỉ tài khoản", () =>
          perform("suspend-user", r.subject.userId),
        ),
      );
    if (r.status === "open")
      card.append(action("Đóng báo cáo", () => perform("close-report", r.id)));
    panel.append(card);
  }
  const { users } = await api("/admin/users");
  panel.append(node("h3", "Tài khoản gần đây", "section-title"));
  const userList = node("div", undefined, "social-card list admin-list");
  panel.append(userList);
  for (const u of users) {
    const row = node("div", undefined, "admin-row");
    const who = node("div", undefined, "row-text");
    who.append(
      node("b", "@" + u.username),
      node("span", (u.role === "admin" ? "Quản trị viên" : "Thành viên") + (u.suspended ? " · Đã đình chỉ" : ""), "muted"),
    );
    row.append(avatar({ id: u.id, name: u.username }), who);
    if (u.role !== "admin")
      row.append(
        action(u.suspended ? "Khôi phục" : "Đình chỉ", async () => {
          if (!confirm("Thay đổi trạng thái " + u.username + "?")) return;
          await api("/admin/moderate", "POST", {
            action: u.suspended ? "restore-user" : "suspend-user",
            target: u.id,
          });
          await navigate("admin");
        }, u.suspended ? "secondary" : "danger"),
      );
    userList.append(row);
  }
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
      if (blob.size > 12 * 1024 * 1024) throw Error("Video tối đa 12 MB.");
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
