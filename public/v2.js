// Kinnect — giao diện mới (2026-10), dựng lại theo bản thiết kế đã duyệt.
// Giao diện chính mới, dùng dữ liệu thật và API của Kinnect.
(() => {
  "use strict";
  const root = document.getElementById("kn");
  const app = root.querySelector(".app");
  const ICONS = window.KN_ICONS || {};

  // ---------- Helpers ----------
  const esc = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const ic = (n) => `<svg class="lucide lucide-${n}" width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="${app.classList.contains("postlogin-polish") ? 1.7 : 2}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${(app.classList.contains("postlogin-polish") && window.KN_POSTLOGIN_ICONS?.[n]) || ICONS[n] || ""}</svg>`;
  const btn = (text, icon, action, cls = "", value) =>
    `<button type="button" class="cursor-interaction ${cls}" data-do="${action}"${value !== undefined ? ` data-value="${esc(value)}"` : ""} aria-label="${esc(text)}">${icon ? ic(icon) : ""}<span>${esc(text)}</span></button>`;
  const initials = (name) => (String(name || "?").trim().split(/\s+/).map((w) => w[0]).join("").slice(-2) || "?").toUpperCase();
  const av = (u, you = false) => `<span class="av ${you ? "you" : ""} ${["kinnect_style_aurora","kinnect_style_ocean","kinnect_style_sunset"].includes(u?.storeStyle)?"store-"+u.storeStyle:""}">${u?.avatar ? `<img src="${esc(u.avatar)}" alt="">` : (u?.isGroup?ic("users-round"):esc(initials(u?.name || u?.username)))}</span>`;
  const person = (u, sub, extra = "") => `<div class="person">${av(u)}<div class="grow"><strong>${esc(u?.name || u?.username)}</strong><small>${sub}</small></div>${extra}</div>`;
  const head = (t, p, extra = "") => `<div class="heading"><div><h1>${t}</h1><p>${p}</p></div>${extra}</div>`;
  const scene = () => `<div class="scene" aria-hidden="true"><span class="sun"></span></div>`;
  const tabs = (labels, selected, action) => `<div class="tabs">${labels.map((l) => `<button type="button" class="cursor-interaction ${selected === l ? "active" : ""}" aria-pressed="${selected === l}" data-do="${action}" data-value="${esc(l)}">${esc(l)}</button>`).join("")}</div>`;
  const ago = (ts) => {
    const d = Math.max(0, Date.now() - Number(ts || 0)) / 1000;
    if (d < 60) return "Vừa xong";
    if (d < 3600) return Math.floor(d / 60) + " phút trước";
    if (d < 86400) return Math.floor(d / 3600) + " giờ trước";
    if (d < 7 * 86400) return Math.floor(d / 86400) + " ngày trước";
    return new Date(Number(ts)).toLocaleDateString("vi-VN");
  };
  const loading = (text = "Đang tải…") => `<div class="kn-loading"><span class="kn-spin"></span><span>${text}</span></div>`;
  const emptyState = (icon, title, text) => `<div class="kn-empty">${ic(icon)}<h2>${title}</h2><p>${text}</p></div>`;

  function uploadRequest(path,method,body){return new Promise((resolve,reject)=>{
    const card=document.createElement('div');card.className='kn-upload-progress';card.setAttribute('role','status');card.innerHTML='<span class="kn-upload-symbol" aria-hidden="true">↑</span><div><strong>0%</strong><progress max="100" value="0" aria-label="Tiến độ đăng tải"></progress><small>Đang tải lên</small></div>';document.body.append(card);
    const xhr=new XMLHttpRequest();xhr.open(method,'/api'+path);xhr.withCredentials=true;xhr.timeout=600000;xhr.setRequestHeader('Content-Type','application/json');
    xhr.upload.onprogress=e=>{if(e.lengthComputable){const percent=Math.min(99,Math.floor(e.loaded/e.total*100));card.querySelector('strong').textContent=percent+'%';card.querySelector('progress').value=percent;if(e.loaded===e.total)card.querySelector('small').textContent='Đang hoàn tất…';}};
    xhr.upload.onload=()=>{card.querySelector('small').textContent='Đang hoàn tất…';};
    xhr.onload=()=>{if(xhr.status>=200&&xhr.status<300){card.querySelector('strong').textContent='✓';card.querySelector('progress').value=100;card.querySelector('small').textContent='Đã đăng';setTimeout(()=>card.remove(),1800);}else card.remove();resolve(new Response(xhr.responseText,{status:xhr.status||502,headers:{'Content-Type':'application/json'}}));};
    xhr.onerror=()=>{card.remove();reject(new Error('Mất kết nối. Nội dung vẫn được giữ để thử lại.'));};xhr.ontimeout=()=>{card.remove();reject(new Error('Tải lên hết thời gian chờ. Hãy thử lại.'));};xhr.send(JSON.stringify(body));
  });}
  const inFlightGets=new Map(),validatedGets=new Map();let apiSessionEpoch=0;
  async function api(path,method='GET',body){
    const epoch=apiSessionEpoch,expired=()=>{const error=new Error('Yêu cầu đã hết hiệu lực.');error.status=409;error.stale=true;return error;};
    const key=epoch+':'+path,shared=method==='GET'&&inFlightGets.get(key);
    if(shared){const data=await shared;if(epoch!==apiSessionEpoch)throw expired();return structuredClone(data);}
    const cached=method==='GET'?validatedGets.get(key):null;
    const request=(async()=>{
    const mediaUpload=body&&["POST","PATCH"].includes(method)&&[body.media,body.data,...(Array.isArray(body.mediaItems)?body.mediaItems:[])].some(v=>typeof v==="string"&&v.startsWith("data:"));
    const response = mediaUpload?await uploadRequest(path,method,body):await fetch("/api" + path, {
      method,
      credentials: "same-origin",
      headers: !["GET","HEAD"].includes(method) ? { "Content-Type": "application/json" } : cached?{"If-None-Match":cached.etag}:{},
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if(response.status===304&&cached)return structuredClone(cached.data);
    const data = await response.json().catch(() => ({}));
    if(response.status===428&&data.version){if(await knConfirm(data.error,{danger:false,acceptLabel:'Tôi đồng ý'})){await api('/me/privacy-consent','POST',{accepted:true,version:data.version});return api(path,method,body);}throw new Error('Bạn chưa đồng ý thông báo sử dụng dữ liệu.');}
    if (!response.ok) {
      const error = new Error(data.error || "Có lỗi xảy ra. Vui lòng thử lại.");
      error.status = response.status;
      error.data = data;
      throw error;
    }
    if(method==='GET'&&response.headers.get("ETag")&&epoch===apiSessionEpoch){validatedGets.set(key,{etag:response.headers.get("ETag"),data:structuredClone(data)});if(validatedGets.size>64)validatedGets.delete(validatedGets.keys().next().value);}
    return data;
    })();
    if(method==='GET')inFlightGets.set(key,request);
    try{const data=await request;if(epoch!==apiSessionEpoch)throw expired();return structuredClone(data);}finally{if(inFlightGets.get(key)===request)inFlightGets.delete(key);}
  }
  let mediaEditorModule=null;
  async function chooseVideoPath(file){const url=URL.createObjectURL(file);try{return await new Promise(resolve=>{const d=liveDialog('Hoàn thiện video','<video class="video-route-preview" src="'+url+'" autoplay muted playsinline loop></video><div class="video-route-options"><button type="button" data-video-path="pro">'+ic('sparkles')+'<strong>Studio Pro</strong><small>Chỉnh sửa video</small></button><button type="button" data-video-path="basic">'+ic('arrow-right')+'<strong>Tiếp tục</strong><small>Đăng cơ bản</small></button></div>');let selected=false;d.querySelectorAll('[data-video-path]').forEach(b=>b.onclick=async()=>{selected=true;media.videoPath=b.dataset.videoPath;d.close();if(media.videoPath==='basic')resolve(file);else try{resolve(await reviewMediaFile(file,'video'));}catch(error){toast(error.message);resolve(null);}});d.addEventListener('close',()=>{if(!selected)resolve(null);},{once:true});});}finally{URL.revokeObjectURL(url);}}
  async function reviewMediaFile(file,kind='post'){
    if(s.screen==='studio'||s.params.storyCamera)stopCapture();
    stopMusicPreview();media.musicAudio?.pause();
    mediaEditorModule ||= await import('/media-editor.js');
    const edited=await mediaEditorModule.openMediaEditor(file,{kind,loadMusic:()=>api('/music')});
    if(edited){media.musicTrack=null;media.musicAudio?.pause();media.musicAudio=null;}
    return edited;
  }
  const readFile = (file) => new Promise((resolve, reject) => { const r = new FileReader(); r.onload = () => resolve(r.result); r.onerror = reject; r.readAsDataURL(file); });

  // ---------- State ----------
  const authScreens = ["login", "signup", "forgotPassword", "oauthComplete","oauth2fa","forgotSupport","maintenance"];
  const s = {
    me: null, screen: "loading", device: "mobile", params: {},
    posts: null, stories: [], suggestions: [], notifications: [], counts: { bell: 0, friends: false, messages: 0 },
    profileMenu:false,postMenu:"",reportTarget:null,reportReason:"",reactionPost:"",reactionComment:"",commentEditing:null,liveQuick:null,storyViewers:null,sharePost:"",emojiTarget:"",commentDrafts:{},replyComments:{},
    profile: null, profileTab: "Bài viết", openComments: {}, comments: {},
    composer: null, editProfile: null, logoutConfirm: false, note: "", noteTimer: 0, error: "",
    auth: { values: {}, errors: {}, showPw: false, remember: true, agree: false, note: "", step: 0, challengeId: "", providers: [], busy: false },
  };
  const device = window.matchMedia("(min-width: 900px)");
  const setDevice = () => { s.device = device.matches ? "pc" : "mobile"; };
  setDevice();

  function syncNotice(){let n=app.querySelector('.notice');if(!s.note)return n?.remove();if(!n){n=document.createElement('div');n.className='notice';n.setAttribute('role','status');(app.querySelector('main')||app).append(n);}n.textContent=s.note;}
  function toast(t){s.note=t||'';clearTimeout(s.noteTimer);syncNotice();if(s.note)s.noteTimer=setTimeout(()=>{s.note='';syncNotice();},3200);}

  // ---------- Navigation ----------
  const titles = { feed: "Bảng tin", discover: "Khám phá", video: "Video", live: "Trực tiếp", inbox: "Tin nhắn", friends: "Bạn bè", notifications: "Thông báo", profile: "Trang cá nhân", account: "Tài khoản", settings: "Cài đặt", admin: "Quản trị", studio: "Tạo nội dung" };
  async function go(screen, params = {}, { push = true } = {}) {
    if(s.screen==='feed'&&screen==='feed'&&s.posts!==null){await loadFeed();render();s.feedPosition={shell:0,main:0,page:0};app.querySelector('.shell')?.scrollTo(0,0);app.querySelector('main')?.scrollTo(0,0);window.scrollTo(0,0);return;}
    if(s.screen==='feed'&&screen!=='feed'){s.feedSnapshot=s.posts;s.feedPosition={shell:app.querySelector('.shell')?.scrollTop||0,main:app.querySelector('main')?.scrollTop||0,page:window.scrollY};}
    const restoreFeed=screen==='feed'&&s.feedSnapshot!=null;
    if(restoreFeed)s.posts=s.feedSnapshot;

    if(media.room && screen!=="live")await leaveLive();
    if(s.screen==="studio"&&screen!=="studio"&&!media.room)stopCapture();
    const navigationRevision=s.navigationRevision=(s.navigationRevision||0)+1;
    if(!["editProfilePage","profilePreview"].includes(screen))s.editProfile=null;
    s.profileMenu=false;s.postMenu="";
    s.screen = screen;
    s.params = params;
    s.error = "";
    s.logoutConfirm = false;
    if (push) {
      const q = new URLSearchParams({ s: screen, ...params });
      history.pushState({ screen, params }, "", "?" + q.toString());
    }
    currentHistory={state:{screen,params},url:location.search};
    render();
    try {
      if(screen==="login")s.rememberedAccounts=(await api("/remembered")).accounts;
      await communityNavigate(screen, params);
      if(screen === "discover")await loadExplore();
      if(screen==='postDetail'){s.posts=(await api('/posts?post='+encodeURIComponent(params.post))).posts;s.openComments[params.post]=true;await loadComments(params.post);}
      if(screen==='storyView'){s.stories=(await api('/stories')).stories;const i=s.stories.findIndex(st=>st.id===(params.story||storiesState.storyId));storiesState.index=i>=0?i:Math.min(storiesState.index,Math.max(0,s.stories.length-1));await markStoryViewed();}
      if(screen==='groupDetails'){community.chat={...(await api('/groups/'+params.group)).group,isGroup:true};community.candidates=(await api('/discover')).users;}
      if(screen==='store'){const [,storeData,meData]=await Promise.all([ensureCommerceModule(),api('/store'),api('/me')]);s.store=storeData;s.me=meData.user;}
      if(screen==='devices')profileExtras.sessions=(await api('/me/sessions')).sessions;
      if(screen==='twoFactor'){await ensurePlusModule();await plusModule.loadTwoFactor(api,s.me?.id);}
      if(screen==='admin')await loadAdmin();
      if(screen==='privateAlbum')await loadPrivateAlbum(params.user||s.me.id);
      if(screen==='blockedAccounts')profileExtras.blocks=(await api('/blocks')).users;
      if(screen==='recoveryEmail'){profileExtras.email=(await api('/recovery/email')).email;profileExtras.challenge='';}
      if(screen === "video")await loadVideos();
      if(screen === "wallet"){const [,walletData]=await Promise.all([ensureCommerceModule(),api("/wallet")]);s.wallet=walletData;}
      if(screen === "live"){media.rooms=rankLiveRooms((await api("/live/rooms")).rooms);if(!media.room)await enterTopLive(params.room);}
      if(screen === "studio"&&!media.fx&&!media.previewURL)await prepareCamera();
      if (screen === "feed"&&!restoreFeed) await loadFeed();
      if (screen === "bookmarks") await loadBookmarks();
      if (screen === "profile") await loadProfile(params.user || s.me?.id);
      if (screen === "notifications") await refreshCounts();
    } catch (e) {
      if(navigationRevision!==s.navigationRevision||e.stale)return;
      if (e.status === 401) return signedOut();
      s.error = e.message;
    }
    if(navigationRevision!==s.navigationRevision)return;
    render();
    app.querySelector(".shell")?.scrollTo?.(0, restoreFeed?s.feedPosition?.shell||0:0);
    app.querySelector("main")?.scrollTo?.(0, restoreFeed?s.feedPosition?.main||0:0);
    window.scrollTo(0, restoreFeed?s.feedPosition?.page||0:0);
    if(screen==="postDetail"&&params.comment)requestAnimationFrame(()=>{const target=app.querySelector('[data-comment-id="'+CSS.escape(params.comment)+'"]');target?.scrollIntoView({block:"center"});target?.classList.add("v2-comment-highlight");});
  }

  // Hộp xác nhận theo giao diện Kinnect, thay hộp xác nhận mặc định của trình duyệt.
  let knConfirmState=null;
  function knConfirm(message,options={}){
    if(knConfirmState)knConfirmState.finish(false);
    return new Promise(resolve=>{
      const danger=options.danger??/xoá|xóa|chặn|rời|kết thúc|đăng xuất|huỷ kết bạn|hủy kết bạn|thu hồi|đình chỉ|cấp mật khẩu/i.test(message);
      const layer=document.createElement('div');layer.className='kn-confirm-layer';
      layer.innerHTML='<section class="kn-confirm" role="alertdialog" aria-modal="true" aria-labelledby="kn-confirm-text"><p id="kn-confirm-text"></p><div class="kn-confirm-actions"><button type="button" class="secondary" data-kn-confirm="no">Huỷ</button><button type="button" class="'+(danger?'kn-danger':'primary')+'" data-kn-confirm="yes">'+(danger?'Đồng ý':'Xác nhận')+'</button></div></section>';
      layer.querySelector('p').textContent=message;if(options.acceptLabel)layer.querySelector('[data-kn-confirm="yes"]').textContent=options.acceptLabel;
      const finish=ok=>{if(!knConfirmState)return;knConfirmState=null;layer.remove();overlayWasOpen=overlayOpen();resolve(ok);};
      layer.addEventListener('click',e=>{const choice=e.target.closest('[data-kn-confirm]')?.dataset.knConfirm;if(choice)finish(choice==='yes');else if(e.target===layer)finish(false);});
      knConfirmState={finish};root.append(layer);syncOverlayHistory();layer.querySelector('[data-kn-confirm=yes]').focus({preventScroll:true});
    });
  }
  // Popup đang mở: Back/Esc/chạm ra ngoài sẽ đóng popup trước khi đổi màn.
  function overlayOpen(){return !!(knConfirmState||s.composer||s.forwardMessage||s.sharePost||s.reportTarget||s.logoutConfirm||s.emojiTarget||s.postMenu||s.profileMenu||s.reactionPost||s.reactionComment||s.liveQuick||s.storyViewers||community.attachOpen||community.menu||(s.editProfile&&!["editProfilePage","profilePreview"].includes(s.screen)));}
  function closeOverlays(){if(knConfirmState){knConfirmState.finish(false);}s.composer=null;s.forwardMessage=null;s.sharePost='';s.reportTarget=null;s.logoutConfirm=false;s.emojiTarget='';s.postMenu='';s.profileMenu=false;s.reactionPost='';s.reactionComment='';s.liveQuick=null;s.storyViewers=null;community.attachOpen=false;community.menu='';if(s.editProfile&&!["editProfilePage","profilePreview"].includes(s.screen))s.editProfile=null;}
  let currentHistory=null,overlayWasOpen=false;
  // Mở popup thì thêm một mục lịch sử, để nút Back của điện thoại chỉ đóng popup.
  function syncOverlayHistory(){const open=overlayOpen();if(open&&!overlayWasOpen&&currentHistory)history.pushState({...currentHistory.state,overlay:true},"",currentHistory.url);overlayWasOpen=open;}
  window.addEventListener("popstate", (e) => {
    if(overlayOpen()){closeOverlays();overlayWasOpen=false;render();return;}
    const st = e.state || {};
    if (st.screen) go(st.screen, st.params || {}, { push: false });
  });

  // ---------- Data ----------
  async function loadFeed() {
    const revision=s.navigationRevision;
    const f=s.feedFilter||(s.feedFilter={q:'',tag:''});
    const qs=new URLSearchParams({limit:'25',...(f.q?{q:f.q}:{}),...(f.tag?{tag:f.tag}:{})}).toString();
    const [posts, stories] = await Promise.all([api("/posts?"+qs), api("/stories").catch(() => ({ stories: s.stories||[] }))]);
    if(revision!==s.navigationRevision)return;
    s.posts = posts.posts;
    s.feedHasMore = !!posts.hasMore;
    s.feedNextCursor = posts.nextCursor || null;
    s.stories = stories.stories;
    api("/hashtags/trending?limit=8").then((r) => { s.trendingTags = r.hashtags || []; if (s.screen === "feed") render(); }).catch(() => {});
    if (s.device === "pc") api("/friend-suggestions").then((r) => { s.suggestions = (r.users || []).slice(0, 3); render(); }).catch(() => {});
  }
  async function loadMoreFeed() {
    if (!s.feedHasMore || !s.feedNextCursor || s.feedLoadingMore) return;
    s.feedLoadingMore = true; render();
    try {
      const f=s.feedFilter||{q:'',tag:''};
      const qs=new URLSearchParams({limit:'25',before:String(s.feedNextCursor),...(f.q?{q:f.q}:{}),...(f.tag?{tag:f.tag}:{})}).toString();
      const r=await api("/posts?"+qs);
      const seen=new Set((s.posts||[]).map(p=>p.id));
      s.posts=[...(s.posts||[]),...(r.posts||[]).filter(p=>!seen.has(p.id))];
      s.feedHasMore=!!r.hasMore;s.feedNextCursor=r.nextCursor||null;
    } finally { s.feedLoadingMore = false; render(); }
  }
  async function loadBookmarks(more=false) {
    if (more && (!s.bookmarksHasMore || !s.bookmarksCursor || s.bookmarksLoading)) return;
    s.bookmarksLoading = true; if (!more) s.bookmarks = null; render();
    try {
      const qs=new URLSearchParams({limit:'25',...(more&&s.bookmarksCursor?{before:String(s.bookmarksCursor)}:{})}).toString();
      const r=await api("/bookmarks?"+qs);
      const prev=more?(s.bookmarks||[]):[];const seen=new Set(prev.map(p=>p.id));
      s.bookmarks=[...prev,...(r.posts||[]).filter(p=>!seen.has(p.id))];
      s.bookmarksHasMore=!!r.hasMore;s.bookmarksCursor=r.nextCursor||null;
    } finally { s.bookmarksLoading = false; render(); }
  }
  async function loadProfile(id) {
    const revision=s.navigationRevision;
    if(s.profile?.id!==id){s.profile={id,user:null,stats:null,posts:null};render();}
    const [stats, posts, shorts] = await Promise.all([api("/users/" + id + "/stats"), api("/posts?user=" + encodeURIComponent(id)),api("/shorts?user="+encodeURIComponent(id))]);
    if(revision!==s.navigationRevision)return;
    s.profile = { id, user: stats.user, stats, posts: posts.posts, shorts:shorts.shorts };
  }
  async function refreshCounts() {
    if (!s.me) return;
    try {
      const userId=s.me.id,previousIds=new Set(s.notifications.map(n=>n.id)),hasBaseline=!!s.notificationBaseline;
      const r = await api("/notifications");
      if(s.me?.id!==userId)return;
      s.notificationBaseline=true;
      s.notifications = r.notifications || [];
      if(hasBaseline){const fresh=s.notifications.filter(n=>!n.seen&&!n.muted&&!previousIds.has(n.id)&&['message','group_message'].includes(n.kind));if(fresh.length&&s.screen!=='inbox'){const who=fresh[0].actor?.name||fresh[0].actor?.username||'Ai đó';toast(fresh.length>1?who+' và '+(fresh.length-1)+' người khác vừa nhắn tin cho bạn':who+' vừa nhắn tin cho bạn');}}
      const pref=notificationPreferences();if(hasBaseline&&pref.enabled&&!pushOn()&&'Notification' in window&&Notification.permission==='granted'){for(const n of s.notifications.filter(n=>!n.seen&&!n.muted&&!previousIds.has(n.id))){const key=['message','group_message'].includes(n.kind)?'messages':n.kind.startsWith('friend_')?'friends':'posts';if(pref[key]){const notification=new Notification(n.actor?.name||'Kinnect',{body:notifText(n),tag:'kinnect-'+n.id,icon:'/kinnect-logo-v106.svg'});notification.onclick=()=>{window.focus();go('notifications');notification.close();};}}}
      s.counts = {
        bell: s.notifications.filter((n) => !n.seen && !["message", "group_message"].includes(n.kind)).length,
        messages: s.notifications.filter((n) => !n.seen && ["message", "group_message"].includes(n.kind)).length,
        friends: !!r.friendRequestsPending,
      };
      render();
    } catch (e) {
      if (e.status === 401) signedOut();
    }
  }
  let countTimer = 0;
  function startPolling() { ensureSocket().catch(()=>{}); clearInterval(countTimer); countTimer = setInterval(()=>{api("/me/activity","POST",{}).catch(()=>{});refreshCounts();}, 30000); api("/me/activity","POST",{}).catch(()=>{});refreshCounts(); }

  // ---------- Auth ----------
  function signedOut(note = "") {
    apiSessionEpoch++;inFlightGets.clear();validatedGets.clear();
    plusModule?.resetGroupCallState?.();plusModule?.resetTwoFactorState?.();
    stopCapture();if(media.call)stopCallTracks(media.call);media.call=null;media.room=null;for(const pc of media.peers.values())pc.close();media.peers.clear();clearTimeout(media.reconnect);media.socket?.close();media.socket=null;
    stopVoice();
    community.revision++; community.chat = null; community.messages = []; community.entries = []; community.draft = ""; community.attachment = null; community.requestId = ""; community.friends = []; community.incoming = []; community.outgoing = [];
    if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.previewURL='';media.recorded=null;media.caption='';media.shorts=[];media.shortHasMore=false;media.shortNextCursor=null;media.shortNextOffset=null;media.giftRanking=null;media.musicAudio?.pause();media.musicAudio=null;media.musicTrack=null;media.rooms=[];
    s.profileMenu=false;s.postMenu="";s.reportTarget=null;s.reportReason="";s.reactionPost="";s.reactionComment="";s.sharePost="";media.chunks=[];s.feedSnapshot=null;s.feedPosition=null;s.posts=null;s.stories=[];s.suggestions=[];s.profile=null;s.comments={};s.openComments={};s.commentDrafts={};s.replyComments={};s.editProfile=null;s.emojiTarget='';
    community.searchResults=[];community.searchSubmitted='';community.outgoing=[];community.suggestions=[];community.candidates=[];community.selected=[];community.groupName='';community.query='';community.menu='';community.replyTo=null;community.hasMore=false;community.nextCursor=null;community.msgSearchOpen=false;community.msgSearchQuery='';community.msgSearchResults=null;community.inboxMsgResults=[];s.feedFilter={q:'',tag:''};s.feedHasMore=false;s.feedNextCursor=null;s.trendingTags=[];s.bookmarks=null;s.shareCaption='';
    explore.revision++;explore.users=[];explore.query='';explore.filters={};storiesState.text='';storiesState.media='';storiesState.storyId='';
    Object.assign(adminState,{users:[],reports:[],requests:[],activity:[],music:[],overview:{},query:'',temporary:''});
    Object.assign(profileExtras,{sessions:[],blocks:[],privatePhotos:[],privateRequests:[],album:null,email:null,challenge:''});
    s.notificationBaseline=false;s.notifications=[];s.counts={bell:0,friends:false,messages:0};adminState.temporary="";s.auth.values={};s.auth.oauth2faCode='';
    s.me = null;siteSession(false);
    clearInterval(countTimer);
    s.auth.note = note;
    go("login", {}, { push: true });
  }
  const siteSession=on=>{if(!/(^|\.)kinnect\.io\.vn$/.test(location.hostname))return;document.cookie='kinnect_signed_in='+(on?'1':'')+'; Domain=kinnect.io.vn; Path=/; SameSite=Lax; Secure; Max-Age='+(on?60*60*24*60:0);};
  async function signedIn(user, note) {
    apiSessionEpoch++;inFlightGets.clear();validatedGets.clear();
    s.me = user;siteSession(true);
    s.auth = { ...s.auth, values: {}, errors: {}, showPw: false, agree: false, note: "", step: 0, busy: false, need2fa: false, rememberedId: "", oauth2faCode: "" };
    startPolling();
    toast(note);
    await go("feed");
  }
  function authField(id, label, icon, attrs, hint = "") {
    const a = s.auth, err = a.errors[id] || "", pw = id === "password" || id === "newPassword";
    return `<label class="auth-field${err ? " has-error" : ""}"><span class="auth-label">${label}</span><span class="auth-input">${ic(icon)}<input data-auth-input="${id}" ${pw ? `type="${a.showPw ? "text" : "password"}" ` : ""}${attrs} value="${esc(a.values[id] || "")}"${err ? ' aria-invalid="true"' : ""}>${pw ? `<button type="button" class="cursor-interaction auth-eye" data-do="auth-toggle-pw" aria-label="${a.showPw ? "Ẩn mật khẩu" : "Hiện mật khẩu"}" aria-pressed="${a.showPw}">${ic(a.showPw ? "eye-off" : "eye")}</button>` : ""}</span>${err ? `<small class="auth-error">${esc(err)}</small>` : hint ? `<small class="auth-hint">${hint}</small>` : ""}</label>`;
  }
  const authHead = (t, p) => `<div class="auth-head"><a class="auth-logo" href="https://kinnect.io.vn/" aria-label="Về trang chủ Kinnect"><img src="/kinnect-logo-v106.svg" alt="">Kinnect</a><h1>${t}</h1><p>${p}</p></div>`;
  const authTabs = () => (s.device === "pc" || s.screen === "login") ? `<div class="auth-switch"><span class="auth-or">${s.screen === "login" ? "Mới đến Kinnect?" : "Đã có tài khoản?"}</span><button type="button" class="secondary" data-do="auth-screen" data-value="${s.screen === "login" ? "signup" : "login"}">${s.screen === "login" ? "Tạo tài khoản mới" : "Đăng nhập"}</button></div>` : `<div class="tabs auth-tabs">${[["login", "Đăng nhập"], ["signup", "Tạo tài khoản"]].map(([k, l]) => `<button type="button" class="cursor-interaction ${s.screen === k ? "active" : ""}" aria-pressed="${s.screen === k}" data-do="auth-screen" data-value="${k}">${l}</button>`).join("")}</div>`;
  const authBanner = () => (s.auth.note ? `<p class="auth-banner" role="status">${ic("circle-check")}<span>${esc(s.auth.note)}</span></p>` : "");
  const authFormError = () => (s.auth.errors._form ? `<p class="kn-error" role="alert">${esc(s.auth.errors._form)}</p>` : "");
  function authSocial() {
    const p = s.auth.providers;
    if (!p.length) return "";
    return `<div class="auth-social">${p.includes("google") ? `<a class="cursor-interaction secondary" href="/api/oauth/google/start"><b class="auth-brand-g">G</b>Google</a>` : ""}${p.includes("facebook") ? `<a class="cursor-interaction secondary" href="/api/oauth/facebook/start"><b class="auth-brand-f">f</b>Facebook</a>` : ""}</div><p class="auth-divider">hoặc dùng tên đăng nhập</p>`;
  }
  const authFine = '<p class="auth-fine">Bằng việc tiếp tục, bạn đồng ý với <a href="https://kinnect.io.vn/community">quy tắc cộng đồng</a> và <a href="https://kinnect.io.vn/privacy">chính sách quyền riêng tư</a> của Kinnect.</p>';
  const submitBtn = (icon, label) => `<button type="submit" class="cursor-interaction primary auth-submit"${s.auth.busy ? " disabled" : ""}>${ic(icon)}<span>${s.auth.busy ? "Đang xử lý…" : label}</span></button>`;
  function loginScreen() {
    return authHead("Chào bạn trở lại!", "Đăng nhập để tiếp tục những kết nối của bạn.") + authTabs() + authBanner() + ((s.rememberedAccounts||[]).length?'<section class="v2-remembered" aria-label="Tài khoản đã lưu">'+(s.rememberedAccounts||[]).map(u=>'<div class="v2-remembered-item">'+btn("Tiếp tục với "+u.name,"user-round","remembered-login","secondary",u.id)+btn("Gỡ tài khoản đã lưu","x","remembered-remove","icon",u.id)+'</div>').join("")+'</section>':'') + authSocial() +
      `<form class="auth-form" data-auth-form="login" novalidate>${authFormError()}${authField("username", "Tên đăng nhập", "user-round", 'autocomplete="username" autocapitalize="none" spellcheck="false" maxlength="30" placeholder="vd: minh_anh"')}${authField("password", "Mật khẩu", "lock-keyhole", 'autocomplete="current-password" maxlength="128" placeholder="Tối thiểu 6 ký tự"')}${s.auth.need2fa?authField("totpCode","Mã xác thực 2 lớp (6 số / mã dự phòng)","shield-check",'inputmode="numeric" autocomplete="one-time-code" maxlength="12" placeholder="123456"'):""}<div class="auth-row"><label class="auth-check"><input type="checkbox" data-auth-check="remember"${s.auth.remember ? " checked" : ""}><span>Ghi nhớ đăng nhập</span></label><button type="button" class="cursor-interaction auth-link" data-do="auth-screen" data-value="forgotPassword">Quên mật khẩu?</button></div>${submitBtn("log-in", "Đăng nhập")}</form>` + authFine;
  }
  function signupScreen() {
    const err = s.auth.errors.agree || "";
    return authHead("Bắt đầu kết nối của bạn.", "Tạo tài khoản để chia sẻ và gặp người cùng tần số.") + authTabs() + authBanner() + authSocial() +
      `<form class="auth-form" data-auth-form="signup" novalidate>${authFormError()}${authField("name", "Tên hiển thị", "pen-line", 'maxlength="60" placeholder="Tên mọi người sẽ thấy"')}${authField("username", "Tên đăng nhập", "at-sign", 'autocomplete="username" autocapitalize="none" spellcheck="false" maxlength="30" placeholder="vd: minh_anh"', "Dùng để bạn bè tìm bạn. 3–30 ký tự không dấu, số hoặc gạch dưới.")}${authField("password", "Mật khẩu", "lock-keyhole", 'autocomplete="new-password" maxlength="128" placeholder="Tối thiểu 6 ký tự"')}<label class="auth-check auth-agree${err ? " has-error" : ""}"><input type="checkbox" data-auth-check="agree"${s.auth.agree ? " checked" : ""}${err ? ' aria-invalid="true"' : ""}><span>Tôi xác nhận mình <b>đủ 18 tuổi</b> và đồng ý với quy tắc cộng đồng.</span></label>${err ? `<small class="auth-error">${esc(err)}</small>` : ""}${submitBtn("user-plus", "Tạo tài khoản")}</form>` + authFine;
  }
  function maintenanceScreen(){return authHead('Kinnect đang cập nhật','Giao diện mới đã sẵn sàng.')+'<div class="panel settings-section"><p class="body-copy">Chúng tôi đang hoàn tất giao diện mới. Vui lòng quay lại sau ít phút.</p>'+btn('Kiểm tra lại','rotate-ccw','reload-update','primary')+'</div>';}
  function forgotSupportScreen(){return authHead('Hỗ trợ lấy lại tài khoản','Dùng khi bạn chưa có email khôi phục.')+'<form data-forgot-support class="auth-form">'+authFormError()+authField('username','Tên đăng nhập','at-sign','maxlength="30"')+authField('contact','Thông tin liên hệ','mail','maxlength="120" placeholder="Email hoặc số điện thoại để quản trị liên hệ"')+authField('note','Mô tả yêu cầu','message-square','maxlength="500"')+'<button type="submit" class="primary">Gửi yêu cầu hỗ trợ</button></form>'+btn('Quay lại đăng nhập','arrow-left','auth-screen','','login');}
  function oauthCompleteScreen(){return authHead('Hoàn tất tài khoản','Chọn tên để bắt đầu kết nối.')+'<form data-oauth-complete class="auth-form">'+authFormError()+authField('name','Tên hiển thị','pen-line','maxlength="60" autocomplete="name"')+authField('username','Tên đăng nhập','at-sign','maxlength="30" autocomplete="username"')+'<label class="auth-check"><input type="checkbox" name="agree18" required> Tôi xác nhận đủ 18 tuổi và đồng ý quy tắc cộng đồng.</label><button type="submit" class="primary auth-submit">Hoàn tất</button></form>';}
  function forgotScreen() {
    const step = s.auth.step;
    return `<button type="button" class="cursor-interaction auth-back" data-do="auth-screen" data-value="login">${ic("arrow-left")}<span>Quay lại đăng nhập</span></button>` +
      authHead("Quên mật khẩu", step ? "Nhập mã 6 số vừa gửi tới email khôi phục của bạn và mật khẩu mới." : "Chúng tôi sẽ gửi mã xác minh tới email khôi phục của bạn.") +
      `<div class="auth-steps" aria-label="Bước ${step + 1} trên 2"><i class="on"></i><i class="${step ? "on" : ""}"></i></div>` + authBanner() +
      `<form class="auth-form" data-auth-form="forgot" novalidate>${authFormError()}${step
        ? authField("code", "Mã xác minh", "key-round", 'inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="6 chữ số"') + authField("newPassword", "Mật khẩu mới", "lock-keyhole", 'autocomplete="new-password" maxlength="128" placeholder="Tối thiểu 6 ký tự"') + submitBtn("check", "Đặt lại mật khẩu") + `<button type="button" class="cursor-interaction auth-link auth-center" data-do="forgot-restart">Gửi lại mã</button>`
        : authField("identifier", "Tên đăng nhập hoặc email khôi phục", "mail", 'autocapitalize="none" spellcheck="false" maxlength="254" placeholder="vd: minh_anh"') + submitBtn("send", "Gửi mã qua email")
      }</form><p class="auth-fine">Chưa có email khôi phục? <button type="button" class="auth-link" data-do="auth-screen" data-value="forgotSupport">Gửi yêu cầu cho quản trị viên</button>.</p>`;
  }
  let authWallModule = null, authWallPromise = null;
  function authDesktopWall() {
    if (!authWallModule && !authWallPromise) {
      authWallPromise = import('/v2-auth-wall.js').then((mod) => {
        authWallModule = mod;
        if (authScreens.includes(s.screen) && s.device === 'pc') render();
      }).catch(() => { authWallPromise = null; });
    }
    return authWallModule
      ? authWallModule.renderAuthDesktopWall()
      : '<aside class="auth-wall auth-wall-loading" aria-hidden="true"></aside>';
  }
  function authFrame(inner){
    if(s.device==='pc')return '<div class="auth-shell">'+authDesktopWall()+'<main class="auth-main">'+(s.screen!=='forgotPassword'?'<a class="cursor-interaction auth-back auth-home" href="https://kinnect.io.vn/">'+ic('arrow-left')+'<span>Trang chủ</span></a>':'')+inner+'<small class="auth-credit">Ảnh minh họa tạo bằng AI · hồ sơ hư cấu</small></main></div>';
    return '<div class="native-auth-shell"><aside class="native-auth-preview"><img src="/auth-preview.jpg" alt="Kết nối và chia sẻ cùng Kinnect"></aside><main class="native-auth-main"><a class="native-auth-home" href="https://kinnect.io.vn/">'+ic('arrow-left')+'<span>Trang chủ</span></a>'+inner+'</main></div>';
  }
  async function submitAuth(kind) {
    const a = s.auth, v = a.values, er = {}, okName = /^[a-zA-Z0-9_]{3,30}$/, quick2fa = kind === "login" && a.rememberedId && !v.password && a.need2fa;
    if (kind === "signup" && !(v.name || "").trim()) er.name = "Nhập tên mọi người sẽ thấy.";
    if (kind !== "forgot" && !quick2fa) {
      if (!okName.test(v.username || "")) er.username = "Tên đăng nhập gồm 3–30 ký tự không dấu, số hoặc gạch dưới.";
      if ((v.password || "").length < 6) er.password = "Mật khẩu cần ít nhất 6 ký tự.";
    }
    if (quick2fa && !(v.totpCode || "").trim()) er.totpCode = "Nhập mã xác thực 2 lớp (2FA).";
    if (kind === "signup" && !a.agree) er.agree = "Bạn cần xác nhận đủ 18 tuổi và đồng ý quy tắc cộng đồng.";
    if (kind === "forgot") {
      if (!a.step && !(v.identifier || "").trim()) er.identifier = "Nhập tên đăng nhập hoặc email khôi phục.";
      if (a.step && !/^\d{6}$/.test(v.code || "")) er.code = "Nhập mã gồm 6 chữ số.";
      if (a.step && (v.newPassword || "").length < 6) er.newPassword = "Mật khẩu mới cần ít nhất 6 ký tự.";
    }
    a.errors = er;
    a.note = "";
    if (Object.keys(er).length) { render(); app.querySelector("[aria-invalid=true]")?.focus({ preventScroll: true }); return; }
    a.busy = true;
    render();
    try {
      if (kind === "login") {
        const r = quick2fa
          ? await api("/remembered/login", "POST", { userId: a.rememberedId, totpCode: v.totpCode.trim() })
          : await api("/login", "POST", { username: v.username.toLowerCase(), password: v.password, remember: a.remember, ...(v.totpCode ? { totpCode: v.totpCode } : {}) });
        return await signedIn(r.user, "Chào mừng trở lại, " + (r.user.name || r.user.username));
      }
      if (kind === "signup") {
        const r = await api("/register", "POST", { username: v.username.toLowerCase(), password: v.password, name: v.name.trim(), agree18: true });
        return await signedIn(r.user, "Đã tạo tài khoản. Chào mừng " + (r.user.name || r.user.username) + " đến với Kinnect");
      }
      if (!a.step) {
        const r = await api("/recovery/reset/start", "POST", { identifier: v.identifier.trim().toLowerCase() });
        a.challengeId = r.challengeId;
        a.step = 1;
        a.note = r.message || "Nếu tài khoản có email khôi phục, mã xác minh đã được gửi.";
      } else {
        const r = await api("/recovery/reset/finish", "POST", { challengeId: a.challengeId, code: v.code, password: v.newPassword });
        const id = (v.identifier || "").trim();
        a.step = 0;
        a.values = okName.test(id) ? { username: id } : {};
        a.note = r.message || "Đã đặt lại mật khẩu. Hãy đăng nhập bằng mật khẩu mới.";
        a.busy = false;
        return go("login");
      }
    } catch (e) {
      if (e.data?.requires2fa) { a.need2fa = true; a.errors = { totpCode: e.message }; }
      else a.errors = { _form: e.message };
    } finally {
      a.busy = false;
    }
    render();
  }

  app.addEventListener('click',event=>{const menu=app.querySelector('.pc-account-menu[open]');if(menu&&!menu.contains(event.target))menu.open=false;});
  app.addEventListener('keydown',event=>{if(event.key==='Escape'){const menu=app.querySelector('.pc-account-menu[open]');if(menu){menu.open=false;menu.querySelector('summary')?.focus();}}});
  app.addEventListener("click", event => { const menu = app.querySelector(".pc-header-search[open]"); if (menu && !menu.contains(event.target)) menu.open = false; });
  app.addEventListener("keydown", event => { if (event.key === "Escape") { const menu = app.querySelector(".pc-header-search[open]"); if (menu) { menu.open = false; menu.querySelector("summary")?.focus(); } } });
  // ---------- Shell ----------
  function header() {
    const c = s.counts, sc = s.screen;
    const desktopNav=s.device==='pc'?'<nav class="pc-top-nav" aria-label="Lối tắt chính">'+[['feed','house','Bảng tin'],['inbox','message-square','Tin nhắn'],['discover','compass','Khám phá']].map(([key,icon,label])=>'<button type="button" class="cursor-interaction '+(sc===key?'active':'')+'" data-do="nav" data-value="'+key+'" aria-label="'+label+(key==='inbox'&&c.messages?' · '+c.messages+' chưa đọc':'')+'" title="'+label+'">'+ic(icon)+'</button>').join('')+'</nav>':'';
    const accountControl=s.device==='pc'?'<details class="pc-account-menu"><summary aria-label="Tài khoản của tôi">'+av(s.me,true)+'</summary><div class="pc-account-pop"><div class="pc-account-person">'+person(s.me,'@'+esc(s.me.username))+'</div>'+btn('Trang cá nhân','user-round','nav','','profile')+btn('Cài đặt tài khoản','settings','nav','','account')+btn('Đăng xuất','log-out','logout-ask')+'</div></details>':`<button type="button" class="cursor-interaction account-button${sc === "account" ? " active" : ""}" data-do="nav" data-value="account" aria-label="Tài khoản của tôi">${av(s.me, true)}</button>`;
    const searchForm = `<form class="top-search-form" data-top-search>${ic('search')}<input type="search" data-top-search-input placeholder="Tìm người, nội dung…" value="${esc(explore.query)}" aria-label="Tìm kiếm"></form>`;
    const searchControl = s.device === "pc" ? `<details class="pc-header-search"><summary aria-label="Mở tìm kiếm" title="Tìm kiếm">${ic("search")}</summary>${searchForm}</details>` : searchForm;
    return `<header class="top"><a class="brand" href="?s=feed" data-nav="feed" aria-label="Kinnect — Bảng tin"><img class="native-brand-mark" src="/kinnect-logo-v106.svg" alt="">Kinnect</a>${searchControl}${desktopNav}<div class="top-actions">` +
      `<button type="button" class="cursor-interaction icon notification-button${c.bell ? " has-unread" : ""}${sc === "notifications" ? " active" : ""}" data-do="nav" data-value="notifications" aria-label="Thông báo${c.bell ? " · " + c.bell + " chưa xem" : ""}">${ic("bell")}</button>` +
      `<button type="button" class="cursor-interaction icon friends-header-button${sc === "friends" ? " active" : ""}" data-do="nav" data-value="friends" aria-label="Bạn bè">${ic("users-round")}${c.friends ? '<span class="friend-request-badge" aria-label="Có lời mời kết bạn mới"></span>' : ""}</button>` +
      `<button type="button" class="cursor-interaction icon message-header-button${sc === "inbox" ? " active" : ""}${c.messages ? " has-unread" : ""}" data-do="nav" data-value="inbox" aria-label="Tin nhắn${c.messages ? " · " + c.messages + " chưa đọc" : ""}">${ic("message-square")}</button>` +
      accountControl + '</div></header>';
  }
  function sideNav() {
    const nav = [["feed", "house", "Bảng tin"], ["discover", "compass", "Khám phá"], ["video", "clapperboard", "Video"], ["live", "radio", "Trực tiếp"], ["inbox", "message-square", "Tin nhắn"], ["notifications", "bell", "Thông báo"], ["friends", "users-round", "Bạn bè"], ["bookmarks", "bookmark", "Đã lưu"], ["profile", "user-round", "Trang cá nhân"], ["wallet","wallet","Ví Kinnect"],["store","shopping-bag","Cửa hàng Kinnect"],["account", "settings", "Cài đặt tài khoản"]].concat(s.me?.role === "admin" ? [["admin", "shield-check", "Quản trị"]] : []);
    return `<nav class="side" aria-label="Điều hướng chính">${nav.map(([k, i, l]) => btn(l, i, "nav", s.screen === k && (k !== "profile" || s.params.user === undefined || s.params.user === s.me?.id) ? "active" : "", k)).join("")}${btn("Tạo nội dung", "plus", "nav", "primary", "studio")}<footer>${av(s.me, true)}<div><b>${esc(s.me?.name)}</b><small>@${esc(s.me?.username)}</small></div></footer></nav>`;
  }
  function bottomNav() {
    const b = (label, icon, key) => btn(label, icon, "nav", s.screen === key ? "active" : "", key);
    return `<nav class="bottom" aria-label="Điều hướng mobile">${b("Bảng tin", "house", "feed")}${b("Khám phá", "compass", "discover")}${btn("Tạo", "plus", "nav", "create", "studio")}${b("Video", "clapperboard", "video")}${b("Live", "radio", "live")}</nav>`;
  }
  const noticeBar = () => (s.note ? `<div class="notice" role="status">${esc(s.note)}</div>` : "");

  // ---------- Screens ----------
  function hiddenPostIds(){try{return JSON.parse(localStorage.getItem('kinnect-hidden-posts:'+s.me.id)||'[]');}catch{return [];}}
  function findPost(id){return [...(s.posts||[]),...(s.profile?.posts||[]),...(s.bookmarks||[])].find(p=>p.id===id);}
  function renderPostMedia(media, items){
    if(items?.length>1)return `<div class="post-album-grid count-${Math.min(4,items.length)}">${items.slice(0,4).map((it,idx)=>`<a class="post-album-tile" href="${esc(it.url)}" target="_blank" rel="noopener"><img src="${esc(it.url)}" alt="Ảnh ${idx+1}" loading="lazy">${idx===3&&items.length>4?`<span class="post-album-more">+${items.length-4}</span>`:''}</a>`).join('')}</div>`;
    if(!media)return '';
    return `<div class="post-media-real">${media.kind==="video"?`<video src="${esc(media.url)}"${media.thumbnail?` poster="${esc(media.thumbnail)}"`:''} controls playsinline preload="metadata"></video>`:`<img src="${esc(media.url)}" alt="Ảnh trong bài viết" loading="lazy">`}</div>`;
  }
  function postCard(p) {
    if(hiddenPostIds().includes(p.id))return `<article class="panel post-hidden"><span>${ic('eye-off')} Đã ẩn bài viết</span>${btn('Hoàn tác','undo-2','unhide-post','',p.id)}</article>`;
    const mine = p.user_id === s.me?.id, open = s.openComments[p.id], list = s.comments[p.id];
    const media = renderPostMedia(p.media, p.mediaItems);
    const shared = p.sharedPost ? `<div class="post-shared-card"><button type="button" class="cursor-interaction person-link" data-do="open-profile" data-value="${esc(p.sharedPost.author?.id||'')}">${person(p.sharedPost.author, ago(p.sharedPost.created))}</button>${p.sharedPost.body?`<p class="post-copy">${esc(p.sharedPost.body)}</p>`:''}${renderPostMedia(p.sharedPost.media,p.sharedPost.mediaItems)}</div>` : "";
    const tags = p.hashtags?.length ? `<div class="post-hashtags">${p.hashtags.map(t=>`<button type="button" class="post-tag-pill" data-do="feed-tag" data-value="${esc(t)}">#${esc(t)}</button>`).join('')}</div>` : "";
    const sub = ago(p.created) + " · " + (p.visibility === "followers" ? "Người theo dõi" : "Mọi thành viên");
    return `<article class="panel post" data-post="${esc(p.id)}"><div class="post-head"><button type="button" class="cursor-interaction person-link" data-do="open-profile" data-value="${esc(p.user_id)}">${person(p.author, sub)}</button>${btn("Tuỳ chọn bài viết","ellipsis","post-menu","icon post-menu-trigger",p.id).replace('aria-label=','aria-haspopup="menu" aria-expanded="'+(s.postMenu===p.id)+'" aria-label=')}</div>${s.postMenu===p.id?'<div class="v2-context-menu post-options" role="menu">'+(mine?btn("Chỉnh sửa bài viết","pencil","edit-post","",p.id)+btn("Thay đổi đối tượng xem","users","post-audience","",p.id):"")+btn(p.bookmarked?"Bỏ lưu bài viết":"Lưu bài viết","bookmark","post-bookmark","",p.id)+btn("Ẩn bài viết","eye-off","hide-post","",p.id)+(mine?btn("Xoá bài viết","trash-2","delete-post","danger",p.id):btn("Báo cáo bài viết","flag","report-open","","post:"+p.id))+'</div>':""}${p.body ? `<p class="post-copy">${esc(p.body)}</p>` : ""}${tags}${media}${shared}<div class="stats"><span class="reaction-summary"${p.likes?` role="button" tabindex="0" data-do="post-reactors" data-value="${esc(p.id)}" title="Xem ai đã bày tỏ cảm xúc"`:""}>${Object.entries(p.reactions||{}).filter(([k,n])=>n>0&&reactionIcons[k]).sort((a,b)=>b[1]-a[1]).slice(0,3).map(([k])=>`<span aria-label="${reactionNames[k]}">${reactionIcons[k]}</span>`).join("")} ${p.likes} cảm xúc</span><button type="button" class="post-comment-count" data-do="show-comments" data-value="${esc(p.id)}" aria-expanded="${!!open}" aria-label="Xem ${p.comments} bình luận">${p.comments} bình luận${p.shares?' · '+p.shares+' chia sẻ':''}</button></div><div class="post-actions"><div class="reaction-control"><button type="button" class="cursor-interaction reaction-trigger ${p.liked?'active':''}" data-do="post-reaction-toggle" data-value="${esc(p.id)}" aria-expanded="${s.reactionPost===p.id}" aria-label="${p.liked?reactionNames[p.myReaction||'like']:'Cảm xúc'}">${p.liked?`<span class="reaction-emoji">${reactionIcons[p.myReaction||'like']}</span>`:ic('smile')}<span>${p.liked?reactionNames[p.myReaction||'like']:'Cảm xúc'}</span></button>${s.reactionPost===p.id?`<div class="v2-post-reactions" role="group" aria-label="Chọn cảm xúc"><div class="reaction-options">${Object.entries(reactionIcons).map(([key,emoji])=>`<button type="button" data-do="post-reaction" data-value="${esc(p.id)}:${key}" title="${reactionNames[key]}" aria-label="${reactionNames[key]}" aria-pressed="${p.myReaction===key}" class="${p.myReaction===key?'selected':''}">${emoji}</button>`).join('')}</div>${p.liked?btn('Gỡ cảm xúc','x','post-reaction-remove','reaction-remove',p.id):''}</div>`:''}</div>${btn("Bình luận", "message-circle", "toggle-comments", open ? "active" : "", p.id)}${btn("Chia sẻ", "send", "share", "", p.id)}${btn(p.bookmarked ? "Đã lưu" : "Lưu", "bookmark", "post-bookmark", p.bookmarked ? "active" : "", p.id)}</div>${open ? `<div class="post-comments">${list ? postCommentRows(p.id,list) || '<p class="body-copy">Chưa có bình luận. Hãy là người đầu tiên.</p>' : loading("Đang tải bình luận…")}<form class="comment-form" data-comment-form="${esc(p.id)}">${s.replyComments[p.id]?'<div class="v2-reply-context">Đang trả lời <b>'+esc(s.replyNames?.[p.id]||'bình luận')+'</b> '+btn("Huỷ trả lời","x","comment-cancel-reply","icon",p.id)+'</div>':""}<textarea name="body" rows="1" maxlength="1000" placeholder="Viết bình luận…" aria-label="Viết bình luận" autocomplete="off">${esc(s.commentDrafts[p.id]||'')}</textarea>${btn("Emoji bình luận","smile","emoji-open","icon comment-emoji","comment:"+p.id)}${btn("Gửi", "send-horizontal", "noop", "icon primary").replace('type="button"', 'type="submit"')}</form></div>` : ""}</article>`;
  }
  function profileCompletion(){if(!s.me||!s.me.isNew)return '';try{if(localStorage.getItem('kinnect-profile-dismiss:'+s.me.id)==='1')return '';}catch{}const values=[s.me.avatar,s.me.bio,s.me.city,s.me.lookingFor,s.me.interests?.length],percent=Math.round(values.filter(Boolean).length/values.length*100);if(percent===100)return '';return '<section class="panel profile-progress"><div><strong>Hoàn thiện hồ sơ · '+percent+'%</strong><progress max="100" value="'+percent+'" aria-label="Tiến độ hoàn thiện hồ sơ"></progress></div>'+btn('Hoàn thiện hồ sơ','pencil','edit-profile','secondary')+btn('Đóng nhắc hoàn thiện hồ sơ','x','profile-progress-hide','icon')+'</section>';}
  function feed() {
    const groups = [];
    for (const st of s.stories) if (!groups.find((g) => g.author.id === st.author.id)) groups.push(st);
    const stories = `<div class="stories" aria-label="Tin trong 24 giờ"><button type="button" class="cursor-interaction story" data-do="story-create" aria-label="Tạo tin">${av(s.me, true)}<span>Tạo tin</span></button>${groups.slice(0, 10).map((st) => `<button type="button" class="cursor-interaction story" data-do="story-open" data-value="${esc(st.id)}" aria-label="Xem tin của ${esc(st.author.name)}">${av(st.author)}<span>${esc(st.author.name)}</span></button>`).join("")}</div>`;
    const postCards = s.posts === null ? null : s.posts.map(postCard);
    const suggestions = s.device === "pc" && s.suggestions.length ? `<section class="inline-follow-suggestions" aria-label="Gợi ý kết nối"><div class="inline-suggest-heading"><h2>Gợi ý kết nối</h2><span>${s.suggestions.length}</span></div><div class="inline-suggest-row">${s.suggestions.slice(0,3).map((u) => `<div class="inline-suggest-person">${person(u, u.city ? esc(u.city) : "@" + esc(u.username))}${friendActions(u, "suggestion")}</div>`).join("")}</div></section>` : "";
    const f = s.feedFilter || { q: "", tag: "" };
    const filterBar = `<section class="panel feed-filter-bar"><form data-feed-search class="v2-search"><input type="search" data-feed-query aria-label="Tìm bài viết hoặc hashtag" placeholder="Tìm bài viết, #hashtag…" value="${esc(f.q)}"><button type="submit" class="icon" aria-label="Tìm bài viết">${ic("search")}</button>${btn("Đã lưu","bookmark","nav","secondary","bookmarks")}</form>${(f.q||f.tag||(s.trendingTags||[]).length)?`<div class="feed-tag-strip">${f.tag?`<button type="button" class="post-tag-pill active" data-do="feed-filter-clear">#${esc(f.tag)} ×</button>`:""}${f.q?`<button type="button" class="post-tag-pill active" data-do="feed-filter-clear">“${esc(f.q)}” ×</button>`:""}${(s.trendingTags||[]).filter(t=>t.tag!==f.tag).slice(0,6).map(t=>`<button type="button" class="post-tag-pill" data-do="feed-tag" data-value="${esc(t.tag)}">#${esc(t.tag)} <small>${t.count}</small></button>`).join("")}</div>`:""}</section>`;
    const loadMoreBtn = s.feedHasMore && s.feedNextCursor ? `<button type="button" class="secondary v2-load-more" data-do="feed-load-more" ${s.feedLoadingMore?'disabled':''}>${s.feedLoadingMore?'Đang tải…':'Xem thêm bài viết'}</button>` : "";
    const emptyFeed = `<div class="panel">${emptyState("newspaper", f.q||f.tag?"Không tìm thấy bài viết":"Bảng tin còn trống", f.q||f.tag?"Thử từ khóa hoặc hashtag khác.":"Hãy đăng bài đầu tiên, hoặc theo dõi bạn bè để thấy bài của họ.")}</div>`;
    const posts = postCards === null ? loading() : postCards.length ? postCards.slice(0, 1).join("") + suggestions + postCards.slice(1).join("") + loadMoreBtn : suggestions + emptyFeed;
    const aside = "";
    return profileCompletion()+head("Bảng tin", "Một chút kết nối, mỗi ngày.") + (s.error ? `<p class="kn-error">${esc(s.error)}</p>` : "") +
      `<div class="cols feed-cols"><div class="stack feed-stack"><section class="panel feed-stories">${stories}</section><div class="panel feed-composer"><div class="compose">${av(s.me, true)}<button type="button" class="cursor-interaction composer-open" data-do="compose">Bạn đang nghĩ gì?</button></div><div class="compose-tools">${btn("Ảnh / video", "image", "compose")}${btn("Quay video", "video", "nav", "", "studio")}</div></div>${filterBar}${posts}</div>${aside}</div>`;
  }
  function bookmarksScreen() {
    const rows = s.bookmarks;
    return childHeading("Bài viết đã lưu", "feed") + (rows === null ? loading() : rows.length ? `<div class="stack">${rows.map(postCard).join("")}${s.bookmarksHasMore&&s.bookmarksCursor?`<button type="button" class="secondary v2-load-more" data-do="bookmarks-load-more" ${s.bookmarksLoading?'disabled':''}>${s.bookmarksLoading?'Đang tải…':'Xem thêm bài đã lưu'}</button>`:""}</div>` : `<div class="panel">${emptyState("bookmark", "Chưa có bài viết đã lưu", "Bấm nút Lưu trên bất kỳ bài viết nào để xem lại sau.")}</div>`);
  }
  const notifText = (n) => ({ share:"đã chia sẻ bài viết của bạn.", comment_reply:"đã trả lời bình luận của bạn.", missed_call:"đã gọi nhỡ cho bạn.", friend_accepted:"đã chấp nhận lời mời kết bạn.", like: "đã thích bài viết của bạn.", comment: "đã bình luận bài viết của bạn.", short_like: "đã thích video của bạn.", short_comment: "đã bình luận video của bạn.", follow: "đã bắt đầu theo dõi bạn.", message: "đã gửi tin nhắn cho bạn.", group_message: "đã nhắn trong nhóm.", friend_request: "đã gửi lời mời kết bạn.", friend_accept: "đã chấp nhận lời mời kết bạn." })[n.kind] || "có hoạt động mới.";
  function notifications() {
    const list = s.notifications.filter(n=>!["message","group_message"].includes(n.kind));
    return head("Thông báo", "Những cập nhật dành cho bạn.", btn("Đánh dấu đã đọc", "check", "read-all", "secondary")) +
      (list.length ? `<div class="notif-list">${list.map((n) => `<button type="button" class="cursor-interaction notif-row${n.seen ? "" : " unread"}" data-do="open-notification" data-value="${esc(n.id)}">${av(n.actor)}<div><b>${esc(n.actor?.name || n.actor?.username)}</b> ${notifText(n)}<small>${ago(n.created)}</small></div></button>`).join("")}</div>` : `<div class="panel">${emptyState("bell", "Chưa có thông báo", "Khi có người thích, bình luận hoặc theo dõi bạn, thông báo sẽ xuất hiện ở đây.")}</div>`);
  }
  function account() {
    const me = s.me;
    const rows = [["Bài viết đã lưu","bookmark","bookmarks"],["Ví Kinnect","wallet","wallet"],["Cửa hàng Kinnect","shopping-bag","store"],["Cài đặt và quyền riêng tư", "settings", "settings"], ["Bảo mật và đăng nhập", "shield-check", "security"], ["Cài đặt thông báo", "bell", "notificationSettings"], ["Giao diện", "moon", "appearance"], ["Trợ giúp và báo lỗi", "circle-help", "help"]];
    return `<div class="account-page account-flat"><h1 class="account-page-title">Tài khoản</h1><button type="button" class="cursor-interaction account-profile-card" data-do="nav" data-value="profile">${av(me, true)}<span><strong>${esc(me.name)}</strong><small>@${esc(me.username)}${me.role === "admin" ? ' · <em class="admin-role">Quản trị viên</em>' : ""}</small></span>${ic("chevron-right")}</button>${me.role === "admin" ? `<button type="button" class="cursor-interaction account-admin-entry" data-do="nav" data-value="admin"><span class="account-flat-icon">${ic("shield-check")}</span><span><b>Bảng quản trị</b><small>Yêu cầu hỗ trợ, tài khoản và báo cáo</small></span>${ic("chevron-right")}</button>` : ""}<div class="account-flat-list">${rows.map(([t, i, k]) => `<button type="button" class="cursor-interaction account-flat-row" data-do="nav" data-value="${k}"><span class="account-flat-icon">${ic(i)}</span><span>${t}</span>${ic("chevron-right")}</button>`).join("")}</div><div class="account-flat-bottom"><button type="button" class="cursor-interaction account-flat-row" data-do="nav" data-value="changePassword"><span class="account-flat-icon">${ic("key-round")}</span><span>Đổi mật khẩu</span></button><button type="button" class="cursor-interaction account-flat-row logout-action" data-do="logout-ask"><span class="account-flat-icon">${ic("log-out")}</span><span>Đăng xuất</span></button></div><p class="account-page-foot">Kinnect · Kết nối theo cách của bạn.</p></div>`;
  }
  function profileAbout(u,mine){
    const fields=[['Tuổi',u.age?u.age+' tuổi':''],['Nơi sống',u.city],['Chiều cao',u.height?u.height+' cm':''],['Cân nặng',u.weight?u.weight+' kg':''],['Nghề nghiệp',u.occupation],['Trường học',u.school],['Bản dạng giới',u.gender],['Xu hướng',u.orientation],['Vai trò cộng đồng',u.communityRole],['Cách xưng hô',u.pronouns],['Tình trạng quan hệ',u.relationshipRole],['Mong muốn',u.lookingFor]].filter(([,v])=>v);
    const interests=u.interests||[],filled=fields.length||u.bio||interests.length;
    return '<section class="panel profile-about-details" aria-label="Giới thiệu"><div class="profile-facts-title"><h2>Giới thiệu</h2><span>'+ic('globe')+' Công khai</span></div>'+(u.bio?'<div class="profile-about-bio"><h3>Tiểu sử</h3><p>'+esc(u.bio)+'</p></div>':'')+(fields.length?'<div class="profile-fact-grid">'+fields.map(([label,value])=>'<div class="profile-fact"><small>'+label+'</small><strong>'+esc(value)+'</strong></div>').join('')+'</div>':'')+(interests.length?'<div class="profile-about-interests"><h3>Sở thích</h3><div class="profile-interests">'+interests.map(value=>'<span>'+esc(value)+'</span>').join('')+'</div></div>':'')+(!filled?emptyState('user-round','Chưa có thông tin công khai',mine?'Cập nhật hồ sơ để mọi người hiểu bạn hơn.':'Thành viên này chưa chia sẻ thông tin giới thiệu.'):'')+(u.joinedAt?'<p class="profile-about-joined">'+ic('calendar-days')+' Tham gia Kinnect từ '+new Date(u.joinedAt).toLocaleDateString('vi-VN',{month:'2-digit',year:'numeric'})+'</p>':'')+'</section>';
  }
  function profileAlbums(p,mine){const photos=(p.posts||[]).filter(post=>post.media?.kind==='image');if(s.profileAlbum==='posted')return '<section class="profile-album-detail"><div class="album-detail-heading">'+btn('Quay lại album ảnh','arrow-left','profile-albums-back','icon')+'<div><h2>Ảnh đã đăng</h2><small>'+photos.length+' ảnh</small></div></div>'+(photos.length?'<div class="profile-media">'+photos.map(post=>'<a class="profile-media-tile" href="'+esc(post.media.url)+'" target="_blank" rel="noopener"><img src="'+esc(post.media.url)+'" alt="Ảnh đã đăng" loading="lazy" class="kn-fill"></a>').join('')+'</div>':emptyState('image','Chưa có ảnh',mine?'Ảnh trong bài viết của bạn sẽ xuất hiện tại đây.':'Thành viên này chưa đăng ảnh.'))+'</section>';return '<section class="profile-albums-section"><div class="profile-albums-toolbar"><h2>Album ảnh</h2>'+(mine?btn('Thêm ảnh','image-plus','profile-album-add','secondary'):'')+'</div><div class="profile-album-grid"><button type="button" class="profile-album-card" data-do="profile-album-open" data-value="posted"><div class="profile-album-cover">'+(photos[0]?'<img src="'+esc(photos[0].media.url)+'" alt="" loading="lazy">':ic('image'))+'<span>'+ic('image')+'</span></div><div class="profile-album-caption"><strong>Ảnh đã đăng</strong><small>'+photos.length+' ảnh</small></div></button><button type="button" class="profile-album-card private-album-card" data-do="profile-private"><div class="profile-album-cover private-album-cover">'+ic('lock-keyhole')+'<span>'+ic('lock-keyhole')+'</span></div><div class="profile-album-caption"><strong>Ảnh riêng tư</strong><small>'+(mine?'Quản lý ảnh và quyền xem':'Cần được chủ album cho phép')+'</small></div></button></div></section>';}
  function profile() {
    const p = s.profile;
    if (!p || !p.user) return s.error ? `<p class="kn-error">${esc(s.error)}</p>` : loading();
    const u = p.user, mine = u.id === s.me.id;
    const cover = u.cover ? `<img class="saved-profile-cover" src="${esc(u.cover)}" alt="Ảnh bìa">` : scene();
    const actions = mine ? btn("Chỉnh sửa hồ sơ", "pencil", "edit-profile", "primary") : btn(u.following ? "Đang theo dõi" : "Theo dõi", u.following ? "user-check" : "user-plus", "follow", u.following ? "secondary" : "primary", u.id) + btn("Nhắn tin", "message-square", "community-chat", "secondary", u.id)+btn("Tuỳ chọn hồ sơ","ellipsis","profile-menu","icon");
    const interests = (u.interests || []).map((v) => `<span>${esc(v)}</span>`).join("");
    const facts = [["Tuổi", u.age], ["Nơi sống", u.city], ["Bản dạng giới", u.gender], ["Xu hướng", u.orientation], ["Cách xưng hô", u.pronouns], ["Mong muốn", u.lookingFor],["Tình trạng quan hệ",u.relationshipRole],["Nghề nghiệp",u.occupation],["Trường học",u.school]].filter(([, v]) => v);
    const posts = s.profileTab === "Giới thiệu" ? profileAbout(u,mine) : p.posts === null ? loading() : s.profileTab === "Video" ? ((p.shorts||[]).length?'<div class="profile-media">'+p.shorts.map(v=>'<button type="button" class="profile-media-tile" data-do="profile-open-video" data-value="'+esc(v.id)+'" aria-label="Xem video '+esc(v.caption||'cá nhân')+'">'+(v.thumbnail?'<img src="'+esc(v.thumbnail)+'" alt="" loading="lazy" class="kn-fill">':'<video src="'+esc(v.video)+'" muted playsinline preload="metadata" class="kn-fill"></video>')+'<span class="media-duration">'+Math.round(v.duration)+'s</span></button>').join('')+'</div>':emptyState('clapperboard','Chưa có video','Video đã đăng sẽ hiển thị tại đây.')) : s.profileTab === "Album ảnh" ? profileAlbums(p,mine)
      : p.posts.length ? p.posts.map(postCard).join("") : `<div class="panel">${emptyState("newspaper", "Chưa có bài viết", mine ? "Chia sẻ khoảnh khắc đầu tiên của bạn." : "Thành viên này chưa đăng bài.")}</div>`;
    return (!mine ? `<div class="public-profile-heading">${btn("Quay lại", "arrow-left", "back", "icon")}<h1>Trang cá nhân</h1></div>` : "") +
      `<div class="profile-cover">${cover}</div><div class="profile-intro"><div class="profile-identity">${av(u, mine)}<div><h1>${esc(u.name)}</h1><p>@${esc(u.username)}</p></div></div><div class="profile-actions">${actions}${s.profileMenu&&!mine?'<div class="v2-context-menu">'+friendActions(u,u.friendship==='friends'?'friends':'suggestion')+(u.friendship==='friends'?btn("Huỷ kết bạn","user-round","profile-unfriend","",u.id):'')+btn("Báo cáo hồ sơ","flag","report-open","","user:"+u.id)+btn("Chặn tài khoản","shield-check","profile-block","danger-action",u.id)+'</div>':""}</div></div><div class="profile-bio">${u.bio ? `<p>${esc(u.bio)}</p>` : mine ? '<p class="body-copy">Thêm vài dòng giới thiệu để mọi người hiểu bạn hơn.</p>' : ""}<div class="profile-interests">${interests}</div></div>` +
      `<div class="profile-stats">${[[p.stats.posts, "Bài viết"], [p.stats.followers, "Người theo dõi"], [p.stats.following, "Đang theo dõi"]].map(([n, l]) => `<div><b>${n}</b><span>${l}</span></div>`).join("")}</div><div class="profile-layout profile-with-about-tab"><div class="profile-content">${tabs(["Giới thiệu", "Bài viết", "Album ảnh", "Video"], s.profileTab, "profile-tab")}${posts}</div></div>`;
  }
  // Community screens use the existing authenticated APIs; no demo users or messages.
  const community = { replyTo:null,hasMore:false,nextCursor:null,loadingOlder:false,msgSearchOpen:false,msgSearchQuery:'',msgSearchResults:null,inboxMsgResults:[],searchResults:[],searchSubmitted:'',voiceRecorder:null,voiceStream:null,voiceURL:"",voiceBlob:null,voiceStage:"idle",voiceTimer:null,voiceStarted:0, friends: [], incoming: [], outgoing: [], suggestions: [], entries: [], chat: null, messages: [], query: '', friendTab: 'Bạn bè', unreadOnly: false, draft: '', attachment: null, busy: false, groupName: '', selected: [], candidates: [], menu: '', signature: '', revision: 0 };
  const activity = u => u.activityShared === false ? 'Ẩn trạng thái' : u.isActive ? 'Đang trực tuyến' : 'Ngoại tuyến';
  const normalized = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/g, 'd').toLowerCase().replace(/^@/, '');
  const matchesPerson = (u, query) => normalized(u.name + ' ' + (u.username || '')).includes(normalized(query.trim()));
  const chatKey = u => (u.isGroup ? 'group:' : 'direct:') + u.id;
  const chatPath = u => (u.isGroup ? '/groups/' : '/users/') + encodeURIComponent(u.id) + '/messages';
  const clock = value => new Date(value).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' });
  async function loadFriends() {
    const userId=s.me?.id;
    const [f, r, d] = await Promise.all([api('/friends'), api('/friend-requests'), api('/friend-suggestions')]);
    if(s.me?.id!==userId)return;
    community.friends = f.users || []; community.incoming = r.incoming || []; community.outgoing = r.outgoing || []; community.suggestions = d.users || [];
    s.counts.friends = community.incoming.length > 0;
    if(s.screen==='friends'&&community.query.trim()&&community.searchSubmitted===community.query)community.searchResults=(await api('/discover?q='+encodeURIComponent(community.query.replace(/^@/,'')))).users;
  }
  async function loadInbox() {
    const userId=s.me?.id;
    const [d, g] = await Promise.all([api('/conversations'), api('/groups')]);
    if(s.me?.id!==userId)return;
    community.entries = [...d.users, ...g.groups.map(u => ({ ...u, isGroup: true }))].sort((a, b) => Number(!!b.pinned) - Number(!!a.pinned) || (b.last?.created || b.created || 0) - (a.last?.created || a.created || 0));
    s.counts.messages = community.entries.reduce((n, u) => n + (u.unread || 0), 0);
  }
  async function loadChat(target = community.chat) {
    if (!target) return;
    const revision = community.revision, result = await api(chatPath(target));
    if (revision !== community.revision || chatKey(target) !== (community.chat && chatKey(community.chat))) return;
    if (result.user) community.chat = { ...community.chat, ...result.user };
    const latest = result.messages || [];
    if (community.messages.length && latest.length && community.messages[0].created < latest[0].created) {
      const freshIds = new Set(latest.map(m => m.id));
      const older = community.messages.filter(m => !freshIds.has(m.id) && m.created < latest[0].created);
      community.messages = [...older, ...latest];
    } else {
      community.messages = latest;
      community.hasMore = !!result.hasMore;
      community.nextCursor = result.nextCursor || null;
    }
    community.aiSupport=result.aiSupport||null;
    community.entries.forEach(u => { if (chatKey(u) === chatKey(target)) u.unread = 0; });
    s.counts.messages = community.entries.reduce((n, u) => n + (u.unread || 0), 0);
  }
  async function loadOlderChat() {
    const target = community.chat;
    if (!target || !community.hasMore || !community.nextCursor || community.loadingOlder) return;
    community.loadingOlder = true; render();
    try {
      const revision = community.revision;
      const result = await api(chatPath(target) + '?limit=50&before=' + encodeURIComponent(community.nextCursor));
      if (revision !== community.revision || !community.chat || chatKey(target) !== chatKey(community.chat)) return;
      const existing = new Set(community.messages.map(m => m.id));
      const older = (result.messages || []).filter(m => !existing.has(m.id));
      community.messages = [...older, ...community.messages];
      community.hasMore = !!result.hasMore;
      community.nextCursor = result.nextCursor || null;
    } finally { community.loadingOlder = false; render(); }
  }
  async function openCommunityChat(id, isGroup = false) {
    stopVoice();
    community.revision++; community.draft = ''; community.attachment = null; community.requestId = ''; community.replyTo = null; community.messages = []; community.hasMore = false; community.nextCursor = null; community.msgSearchOpen = false; community.msgSearchQuery = ''; community.msgSearchResults = null; community.menu = '';
    const known = [...community.entries, ...community.friends, ...community.suggestions, ...community.candidates].find(u => u.id === id && !!u.isGroup === isGroup);
    community.chat = known || { id, isGroup, name: 'Cuộc trò chuyện' };
    if (isGroup) { community.chat = { ...(await api('/groups/' + id)).group, isGroup: true }; ensurePlusModule().then((m)=>m.refreshGroupCallBanner(id,api).then(()=>render())).catch(()=>{}); }
    await go('inbox', { [isGroup ? 'group' : 'chat']: id });
  }
  function friendActions(u, kind) {
    if (kind === 'incoming' || u.friendship === 'incoming') return btn('Chấp nhận', 'user-check', 'friend-accept', 'primary', u.id) + btn('Từ chối', 'x', 'friend-decline', 'secondary', u.id);
    if (kind === 'outgoing' || u.friendship === 'outgoing') return btn('Huỷ lời mời', 'x', 'friend-cancel', 'secondary', u.id);
    if (kind === 'friends' || u.friendship === 'friends') return btn('Nhắn tin', 'message-square', 'community-chat', 'secondary', u.id);
    return btn('Kết bạn', 'user-plus', 'friend-request', 'primary', u.id);
  }
  function friendRow(u, kind) {
    return `<article class="v2-friend-row"><button type="button" class="person-link" data-do="open-profile" data-value="${esc(u.id)}">${person(u, '@' + esc(u.username) + ' · ' + activity(u))}</button><div class="friend-actions">${friendActions(u, kind)}</div></article>`;
  }
  function friendsScreen() {
    const tab = community.friendTab, query = community.query;
    const kind = tab === 'Lời mời' ? 'incoming' : tab === 'Đã gửi' ? 'outgoing' : 'friends';
    const source = community[kind];
    const rows = source.filter(u => matchesPerson(u, query));
    const section = (title, users) => `<section class="v2-friend-section"><h2>${title} <small>${users.length}</small></h2>${users.map(u => friendRow(u, kind)).join('')}</section>`;
    return '<section class="friends-page">'+head('Bạn bè', 'Kết nối và giữ liên lạc.') + tabs(['Bạn bè', 'Lời mời', 'Đã gửi'], tab, 'community-friends-tab') + `<form data-community-search class="v2-search"><input type="search" data-community-query aria-label="Tìm bạn bè theo tên hoặc username" placeholder="Tên hoặc @username" value="${esc(query)}">${btn('Tìm kiếm', 'search', 'community-search', 'icon')}</form>` +
      (rows.length ? kind === 'friends' ? section('Đang trực tuyến', rows.filter(u => u.isActive && u.activityShared !== false)) + section('Ngoại tuyến', rows.filter(u => !u.isActive || u.activityShared === false)) : section(tab, rows) : emptyState('users-round', query ? 'Không tìm thấy bạn bè' : 'Chưa có ' + tab.toLowerCase(), query ? 'Bạn có thể tìm thêm thành viên trong Khám phá.' : 'Lời mời và kết nối mới sẽ hiển thị tại đây.')) + (kind === 'friends' ? `<section class="v2-friend-section"><h2>Gợi ý kết bạn</h2>${(query.trim()&&community.searchSubmitted===query?community.searchResults.filter(u=>u.friendship!=='friends'):community.suggestions).filter(u => matchesPerson(u, query)).map(u => friendRow(u, 'suggestion')).join('')}</section>` : '')+'</section>';
  }
  function conversationList() {
    const rows = community.entries.filter(u => (!community.unreadOnly || u.unread) && matchesPerson(u, community.query));
    const msgHits = community.query.trim() && (community.inboxMsgResults || []).length
      ? `<div class="v2-msg-search-hits"><p class="v2-chat-day">Tin nhắn khớp (${community.inboxMsgResults.length})</p>${community.inboxMsgResults.map(r => `<button type="button" class="v2-conversation" data-do="${r.kind === 'group' ? 'community-group-chat' : 'community-chat'}" data-value="${esc(r.conversationId)}">${av(r.kind === 'group' ? { isGroup: true, name: r.groupName } : r.peer)}<span class="v2-conversation-copy"><strong>${esc(r.kind === 'group' ? r.groupName : r.peer?.name)}</strong><small>${esc(r.message?.body || '')}</small></span><span class="v2-conversation-meta"><time>${clock(r.created)}</time></span></button>`).join('')}</div>`
      : '';
    return `<section class="v2-conversations"><form data-community-search class="v2-search"><input type="search" data-community-query aria-label="Tìm cuộc trò chuyện hoặc tin nhắn" placeholder="Tìm hội thoại hoặc tin nhắn…" value="${esc(community.query)}">${btn('Tìm kiếm', 'search', 'community-search', 'icon')}</form>${tabs(['Tất cả', 'Chưa đọc'], community.unreadOnly ? 'Chưa đọc' : 'Tất cả', 'community-inbox-tab')}<div class="v2-conversation-list">${rows.map(u => `<div class="v2-conversation-row"><button type="button" class="v2-conversation ${community.chat && chatKey(community.chat) === chatKey(u) ? 'active' : ''}" data-do="${u.isGroup ? 'community-group-chat' : 'community-chat'}" data-value="${esc(u.id)}">${av(u)}<span class="v2-conversation-copy"><strong>${esc(u.name)}</strong><small>${esc((u.last?.mine ? 'Bạn: ' : '') + (u.last?.body || 'Bắt đầu cuộc trò chuyện'))}</small></span><span class="v2-conversation-meta"><time>${u.last ? clock(u.last.created) : ''}</time>${u.unread ? '<b class="v2-unread">' + u.unread + '</b>' : ''}${u.pinned ? ic('pin') : ''}${u.muted ? ic('bell-off') : ''}</span></button>${btn('Tùy chọn hội thoại ' + u.name, 'ellipsis', 'community-menu', 'icon', chatKey(u))}</div>${community.menu === chatKey(u) ? `<div class="v2-chat-menu">${btn('Đánh dấu chưa đọc','mail','community-unread','',chatKey(u))}${btn('Ẩn hội thoại','eye-off','community-hide','',chatKey(u))}${btn(u.pinned ? 'Bỏ ghim' : 'Ghim hội thoại', 'pin', 'community-pin', '', chatKey(u))}${btn(u.muted ? 'Bật thông báo' : 'Tắt thông báo', 'bell-off', 'community-mute', '', chatKey(u))}${btn('Xoá hội thoại', 'trash-2', 'community-clear', 'danger-action', chatKey(u))}</div>` : ''}`).join('') || (!msgHits ? emptyState('message-square', 'Không có cuộc trò chuyện', community.unreadOnly ? 'Bạn đã đọc hết tin nhắn.' : 'Nhắn tin từ hồ sơ hoặc danh sách Bạn bè.') : '')}${msgHits}</div></section>`;
  }
  function attachmentView(m) {
    const a = m.attachment;
    if (!a || m.recalled) return '';
    const url = esc(a.url);
    return a.kind === 'audio' ? `<audio src="${url}" controls preload="metadata"></audio>` : a.kind === 'image' ? `<a href="${url}" target="_blank" rel="noopener"><img src="${url}" alt="${esc(a.name)}" loading="lazy"></a>` : a.kind === 'video' ? `<video src="${url}" controls playsinline preload="metadata"></video>` : `<a href="${url}" download>${ic('paperclip')}${esc(a.name)}</a>`;
  }
  function stopVoice(discard=true){if(community.voiceRecorder?.state==='recording')community.voiceRecorder.stop();community.voiceStream?.getTracks().forEach(t=>t.stop());community.voiceStream=null;clearInterval(community.voiceTimer);if(discard){community.voiceStage='idle';community.voiceBlob=null;if(community.voiceURL)URL.revokeObjectURL(community.voiceURL);community.voiceURL='';}}
  function voiceComposer(){return community.voiceStage==='recording'?'<div class="v2-voice-composer"><span class="v2-recording-dot"></span><strong>Đang ghi âm</strong><time data-voice-clock>00:00</time>'+btn('Huỷ ghi âm','x','voice-cancel','icon')+btn('Dừng ghi âm','square','voice-stop','primary')+'</div>':'<div class="v2-voice-composer"><audio src="'+esc(community.voiceURL)+'" controls></audio>'+btn('Huỷ ghi âm','x','voice-cancel','icon')+btn('Gửi ghi âm','send-horizontal','voice-send','primary')+'</div>';}
  async function voiceAction(action){
    if(action==='voice-start'){if(!community.chat||community.voiceStage!=='idle')return;const target=chatKey(community.chat),stream=await navigator.mediaDevices.getUserMedia({audio:true});if(s.screen!=='inbox'||!community.chat||chatKey(community.chat)!==target){stream.getTracks().forEach(t=>t.stop());return;}community.voiceStream=stream;const mime=['audio/webm;codecs=opus','audio/mp4','audio/webm'].find(m=>MediaRecorder.isTypeSupported(m));if(!mime){stopVoice();throw Error('Trình duyệt chưa hỗ trợ ghi âm.');}const recorder=community.voiceRecorder=new MediaRecorder(stream,{mimeType:mime}),chunks=[];recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data);};recorder.onstop=()=>{if(community.voiceStage==='recording'){community.voiceBlob=new Blob(chunks,{type:mime.split(';')[0]});community.voiceURL=URL.createObjectURL(community.voiceBlob);community.voiceStage='preview';render();}stream.getTracks().forEach(t=>t.stop());clearInterval(community.voiceTimer);};community.voiceStage='recording';community.voiceStarted=Date.now();recorder.start();render();community.voiceTimer=setInterval(()=>{const seconds=Math.floor((Date.now()-community.voiceStarted)/1000),el=app.querySelector('[data-voice-clock]');if(el)el.textContent=String(Math.floor(seconds/60)).padStart(2,'0')+':'+String(seconds%60).padStart(2,'0');if(seconds>=120&&recorder.state==='recording')recorder.stop();},500);return true;}
    if(action==='voice-cancel'){community.voiceStage='idle';stopVoice();render();return true;}
    if(action==='voice-stop'){if(community.voiceRecorder?.state==='recording')community.voiceRecorder.stop();return true;}
    if(action==='voice-send'){if(!community.voiceBlob)return true;community.attachment={name:'Ghi-am-'+Date.now()+(community.voiceBlob.type==='audio/mp4'?'.m4a':'.webm'),data:await readFile(community.voiceBlob)};community.requestId='';stopVoice();await sendCommunityMessage();return true;}
    return false;
  }

  function groupMentions(){const match=community.draft.match(/(?:^|\s)@([^\s@]*)$/);if(!community.chat?.isGroup||!match)return '';const rows=(community.chat.members||[]).filter(u=>u.id!==s.me.id&&matchesPerson(u,match[1]));return rows.length?'<div class="v2-group-mentions">'+rows.map(u=>btn(u.name+' · @'+u.username,'','community-mention','',u.username)).join('')+'</div>':'';}
  function chatScreen() {
    const u = community.chat;
    let day = '';
    const olderBtn = community.hasMore && community.nextCursor ? `<button type="button" class="secondary v2-load-more" data-do="chat-load-more" ${community.loadingOlder?'disabled':''}>${community.loadingOlder?'Đang tải…':'Xem tin nhắn cũ hơn'}</button>` : '';
    const messages = community.messages.map(m => {
      const current = new Date(m.created).toLocaleDateString('vi-VN'), divider = current !== day ? `<p class="v2-chat-day">${current}</p>` : ''; day = current;
      const own = m.sender === s.me.id, seen = m.receipt?.seenAt || m.receipt?.seenCount;
      const quote = !m.recalled && m.replyTo ? `<div class="v2-quote-box"><strong>${esc(m.replyTo.senderName || 'Tin nhắn')}</strong><span>${esc(m.replyTo.body || (m.replyTo.attachmentKind ? 'Tệp đính kèm' : ''))}</span></div>` : '';
      return divider + `<div class="v2-bubble ${own ? 'outgoing' : 'incoming'}" data-message-id="${esc(m.id)}">${u.isGroup && !own ? '<small>' + esc(m.author?.name) + '</small>' : ''}${quote}<p>${m.recalled ? 'Tin nhắn đã được thu hồi' : withMentions(m.body)}</p>${attachmentView(m)}${!m.recalled?`<div class="v2-message-reactions">${Object.entries(m.reactions||{}).map(([key,n])=>`<button type="button" data-do="message-react" data-value="${esc(m.id)}:${key}" aria-label="${esc(key)} · ${n}" class="${m.myReaction===key?"active":""}">${reactionIcons[key]||"👍"} ${n}</button>`).join("")}<span class="v2-message-tools">${btn("Trả lời tin nhắn","message-circle","message-reply","icon",m.id)}${btn("Cảm xúc tin nhắn","smile","emoji-open","icon","message:"+m.id)}${btn("Chuyển tiếp tin nhắn","forward","message-forward","icon",m.id)}${own&&m.body?btn("Sửa tin nhắn","pencil","message-edit","icon",m.id):""}${own?btn("Thu hồi tin nhắn","rotate-ccw","message-recall","icon",m.id):""}`: ""}${m.recalled?'<div class="v2-message-reactions"><span class="v2-message-tools">':''}${!own?btn("Báo cáo tin nhắn","flag","report-open","icon",(u.isGroup?"group_message":"message")+":"+m.id):""}${btn("Xoá tin nhắn ở phía tôi","trash-2","message-delete","icon",m.id)}</span></div><time>${clock(m.created)}${m.editedAt?' · Đã sửa':''}${own ? ' · ' + (seen ? 'Đã xem' : m.receipt?.deliveredAt || m.receipt?.deliveredCount ? 'Đã nhận' : 'Đã gửi') : ''}</time></div>`;
    }).join('');
    const searchPanel = community.msgSearchOpen ? `<div class="v2-chat-search-bar"><form data-chat-msg-search class="v2-search"><input type="search" data-chat-msg-query aria-label="Tìm trong cuộc trò chuyện" placeholder="Tìm tin nhắn trong hội thoại…" value="${esc(community.msgSearchQuery)}"><button type="submit" class="icon" aria-label="Tìm">${ic('search')}</button>${btn('Đóng tìm kiếm','x','chat-search-toggle','icon')}</form>${community.msgSearchResults!==null?`<div class="v2-chat-search-results">${community.msgSearchResults.length?community.msgSearchResults.map(m=>`<button type="button" class="v2-search-hit" data-do="chat-search-jump" data-value="${esc(m.id)}"><strong>${esc(m.author?.name||(m.sender===s.me.id?'Bạn':u.name))}</strong><span>${esc(m.body)}</span><time>${clock(m.created)}</time></button>`).join(''):'<p class="body-copy">Không tìm thấy tin nhắn nào.</p>'}</div>`:''}</div>` : '';
    const replyBanner = community.replyTo ? `<div class="v2-reply-banner"><div class="grow"><small>Đang trả lời <b>${esc(community.replyTo.senderName)}</b></small><span>${esc(community.replyTo.body||'Tệp đính kèm')}</span></div>${btn('Huỷ trả lời','x','message-reply-cancel','icon')}</div>` : '';
    return `<section class="v2-chat"><header class="v2-chat-header">${btn('Quay lại hộp thư', 'arrow-left', 'community-back', 'icon')}<button type="button" class="person-link" data-do="${u.isGroup ? 'community-group-info' : 'open-profile'}" data-value="${esc(u.id)}">${person(u, u.isGroup ? (u.members?.length || 0) + ' thành viên' : activity(u))}</button>${btn('Tìm tin nhắn','search','chat-search-toggle','icon')}${u.isGroup?btn('Bình chọn nhóm','list-plus','group-polls-open','icon')+btn('Gọi thoại nhóm','phone','group-call-audio','icon')+btn('Gọi video nhóm','video','group-call-video','icon'):''}${btn('Tùy chọn cuộc trò chuyện','menu','chat-options','icon')}${!u.isGroup?btn('Gọi thoại','phone','call-audio','icon')+btn('Gọi video','video','call-video','icon'):''}</header>${u.isGroup&&plusModule?plusModule.groupCallBannerHtml(u.id,{esc,ic,btn}):''}${searchPanel}${s.lastCallError?'<div class="v2-call-error" role="alert">'+esc(s.lastCallError)+'</div>':''}${community.aiSupport?.available?'<div class="panel ai-consent-note"><p>'+(community.aiSupport.consent==='enabled'?'Trợ lý AI đã bật.':'Trợ lý AI đang tắt. Bạn vẫn có thể nhắn quản trị viên.')+'</p>'+btn(community.aiSupport.consent==='enabled'?'Tắt AI':'Bật trợ lý AI','sparkles','ai-consent','secondary',community.aiSupport.consent==='enabled'?'off':'on')+'</div>':''}<div class="v2-message-history" role="log" aria-label="Lịch sử tin nhắn" aria-live="polite">${olderBtn}${messages || emptyState('message-square', 'Bắt đầu trò chuyện', 'Gửi lời chào đầu tiên của bạn.')}</div>${replyBanner}${community.attachment ? `<div class="v2-attachment-pending">${ic('paperclip')}${esc(community.attachment.name)}${btn('Bỏ tệp', 'x', 'community-remove-file', 'icon')}</div>` : ''}${approvedAttachmentTray()}${groupMentions()}${community.voiceStage!=='idle'?voiceComposer():''}<form data-community-send class="v2-chat-compose" ${community.voiceStage!=='idle'?'hidden':''}>${btn('Đính kèm tệp','plus','approved-attach','icon')}${btn("Biểu tượng cảm xúc","smile","emoji-open","icon","chat")}<textarea data-community-draft aria-label="Tin nhắn" maxlength="2000" rows="1" placeholder="Nhắn tin…">${esc(community.draft)}</textarea>${btn("Ghi âm","mic","voice-start","icon")}<button type="submit" class="primary icon" aria-label="Gửi tin nhắn" ${community.busy ? 'disabled' : ''}>${ic('send-horizontal')}</button></form></section>`;
  }
  function forwardMessageSheet(){const f=s.forwardMessage;if(!f)return '';return '<div class="composer-sheet"><section class="message-forward-sheet" role="dialog" aria-modal="true" aria-label="Chuyển tiếp tin nhắn"><div class="sheet-head"><h2>Chuyển tiếp tin nhắn</h2>'+btn('Đóng chuyển tiếp','x','message-forward-close','icon')+'</div><p class="forward-preview">'+esc(f.preview||'Tệp đính kèm')+'</p><p class="body-copy">Chọn người hoặc nhóm nhận</p><div class="forward-recipients">'+f.targets.map(u=>'<button type="button" class="v2-share-person" data-do="message-forward-send" data-value="'+esc(chatKey(u))+'" '+(f.busy?'disabled':'')+'>'+person(u,u.isGroup?'Nhóm trò chuyện':'@'+esc(u.username||''))+ic('forward')+'</button>').join('')+(!f.targets.length?'<p class="body-copy">Chưa có bạn bè hoặc hội thoại để chuyển tiếp.</p>':'')+'</div>'+(f.error?'<p class="kn-error" role="alert">'+esc(f.error)+'</p>':'')+(f.busy?'<p role="status">Đang chuyển tiếp…</p>':'')+'</section></div>';}
  function approvedAttachmentTray(){return community.attachOpen?'<section class="attachment-tray" aria-label="Đính kèm tin nhắn"><div class="sheet-head"><h2>Gửi trong cuộc trò chuyện</h2>'+btn('Đóng đính kèm','x','approved-attach','icon')+'</div><div class="attachment-grid">'+[['Ảnh / video','image','image/*,video/*',''],['Tệp','file-text','*/*',''],['Camera','camera','image/*','capture="environment"']].map(([label,icon,accept,capture])=>'<label class="attachment-option kn-file-btn">'+ic(icon)+'<span>'+label+'</span><input type="file" data-community-file accept="'+accept+'" '+capture+' aria-label="Chọn '+label.toLowerCase()+' để gửi" hidden></label>').join('')+btn('Ghi âm','mic','approved-voice')+'</div></section>':'';}
  function inboxScreen() { return head("Tin nhắn","Những cuộc trò chuyện của bạn.",btn("Tạo nhóm","message-square-plus","community-create-group","icon"))+`<div class="v2-messenger ${community.chat ? 'has-chat' : ''}">${conversationList()}${community.chat ? chatScreen() : '<section class="v2-chat-welcome">' + emptyState('message-square', 'Chọn cuộc trò chuyện', 'Tin nhắn của bạn sẽ hiển thị tại đây.') + '</section>'}</div>`; }
  function createGroupScreen() {
    const people = community.candidates.filter(u => matchesPerson(u, community.query));
    return `<section class="create-group-page"><div class="heading">${btn('Quay lại tin nhắn', 'arrow-left', 'community-back', 'icon')}<h1>Tạo nhóm</h1>${btn('Tạo nhóm mới', 'check', 'community-save-group', 'primary')}</div><label class="v2-field">Tên nhóm<input data-community-group-name aria-label="Tên nhóm" maxlength="80" value="${esc(community.groupName)}" placeholder="Đặt tên cho nhóm"></label><form data-community-search class="v2-search"><input type="search" data-community-query aria-label="Tìm thành viên" value="${esc(community.query)}" placeholder="Tên hoặc @username">${btn('Tìm kiếm', 'search', 'community-search', 'icon')}</form><p class="body-copy">Đã chọn ${community.selected.length} thành viên · Tối đa 49 người</p>${people.map(u => `<label class="group-contact">${av(u)}<span><strong>${esc(u.name)}</strong><small>@${esc(u.username)}</small></span><input type="checkbox" data-community-member="${esc(u.id)}" aria-label="Chọn ${esc(u.name)}" ${community.selected.includes(u.id) ? 'checked' : ''}></label>`).join('') || emptyState('users-round', 'Không tìm thấy thành viên', 'Thử tên hoặc username khác.')}</section>`;
  }
  async function communityNavigate(screen, params) {
    if(screen!=="inbox")stopVoice();
    community.query = '';
    if (screen === 'friends') await loadFriends();
    if (screen === 'inbox') {
      await loadInbox();
      const id = params.chat || params.group;
      if (id) {
        if (!community.chat || community.chat.id !== id) community.chat = { id, isGroup: !!params.group, name: 'Cuộc trò chuyện' };
        if (params.group) community.chat = { ...(await api('/groups/' + id)).group, isGroup: true };
        await loadChat();
      } else { community.revision++; community.chat = null; }
    }
  }
  async function communityAction(action, value) {
    const c = community;
    switch (action) {
      case 'community-chat': await openCommunityChat(value); break;
      case 'community-group-chat': await openCommunityChat(value, true); break;
      case 'community-back': stopVoice();c.revision++; c.chat = null; c.requestId = ''; c.menu = ''; await go('inbox'); break;
      case 'community-inbox-tab': c.unreadOnly = value === 'Chưa đọc'; c.menu = ''; render(); break;
      case 'community-friends-tab': c.friendTab = value; c.query = ''; c.searchSubmitted='';c.searchResults=[]; render(); break;
      case 'community-search':
        if(s.screen==='friends'){c.searchSubmitted=c.query;c.searchResults=c.query.trim()?(await api('/discover?q='+encodeURIComponent(c.query.replace(/^@/,'')))).users:[];}
        if(s.screen==='inbox'){c.inboxMsgResults=c.query.trim()?(await api('/messages/search?q='+encodeURIComponent(c.query.trim())+'&limit=20')).results:[];}
        if (s.screen === 'createGroup') c.candidates = (await api('/discover?q=' + encodeURIComponent(c.query.replace(/^@/, '')))).users;
        render(); break;
      case 'community-create-group': c.groupName = ''; c.selected = []; c.query = ''; c.candidates = (await api('/discover')).users; await go('createGroup'); break;
      case 'community-save-group': {
        if (c.busy) break;
        if (!c.groupName.trim() || !c.selected.length) throw Error('Nhập tên nhóm và chọn ít nhất một thành viên.');
        c.busy = true;
        try { const { group } = await api('/groups', 'POST', { name: c.groupName.trim(), members: c.selected }); await openCommunityChat(group.id, true); } finally { c.busy = false; render(); }
        break;
      }
      case 'community-mention':c.draft=c.draft.replace(/(^|\s)@[^\s@]*$/,(_,space)=>space+'@'+value+' ');c.requestId='';render();app.querySelector('[data-community-draft]')?.focus({preventScroll:true});break;
      case 'community-menu': c.menu = c.menu === value ? '' : value; render(); break;
      case 'community-unread': case 'community-hide': case 'community-pin': case 'community-mute': case 'community-clear': {
        const u = c.entries.find(u => chatKey(u) === value); if (!u) break;
        if (action === 'community-clear') { if (!(await knConfirm('Xoá hội thoại ở phía bạn? Người còn lại vẫn giữ tin nhắn.'))) break; await api(chatPath(u), 'DELETE'); if (c.chat && chatKey(c.chat) === value) c.chat = null; }
        else await api('/chat-preferences/' + value.replace(':', '/'), 'POST', action === 'community-unread' ? {unread:true} : action === 'community-hide' ? {hidden:true} : action === 'community-pin' ? { pinned: !u.pinned } : { muted: !u.muted });
        if(['community-unread','community-hide'].includes(action)&&c.chat&&chatKey(c.chat)===value){c.chat=null;c.revision++;} c.menu = ''; await loadInbox(); render(); break;
      }
      case 'community-remove-file': c.attachment = null; c.requestId = ''; render(); break;
      case 'community-group-info': await go('groupDetails',{group:c.chat.id});break;
      case 'friend-request': await api('/users/' + value + '/friend-request', 'POST', {}); await loadFriends(); if(s.screen==='discover')await loadExplore(); render(); break;
      case 'friend-accept': case 'friend-decline': await api('/users/' + value + '/friend-request/respond', 'POST', { action: action === 'friend-accept' ? 'accept' : 'decline' }); await loadFriends(); render(); break;
      case 'friend-cancel': await api('/users/' + value + '/friend-request', 'DELETE'); await loadFriends(); if(s.screen==='discover')await loadExplore(); render(); break;
      default: return false;
    }
    return true;
  }
  async function sendCommunityMessage() {
    const c = community, target = c.chat;
    if (!target || c.busy || (!c.draft.trim() && !c.attachment)) return;
    c.requestId ||= crypto.randomUUID ? crypto.randomUUID() : Date.now() + '-' + Math.random().toString(36).slice(2);
    const requestId = c.requestId;
    c.busy = true; render();
    try {
      await api(chatPath(target), 'POST', { requestId, body: c.draft.trim(), ...(c.replyTo ? { replyToId: c.replyTo.id } : {}), ...(target.isGroup?{mentions:(target.members||[]).filter(u=>u.id!==s.me.id&&c.draft.split(/\s+/).some(word=>word==='@'+u.username)).map(u=>u.id)}:{}), ...(c.attachment ? { attachment: c.attachment } : {}) });
      if (c.chat && chatKey(c.chat) === chatKey(target)) { c.draft = ''; c.attachment = null; c.replyTo = null; c.requestId = ''; await loadChat(target); }
      await loadInbox(); c.scrollEnd = true;
    } finally { c.busy = false; render(); }
  }
  // Poll only visible community screens, with one request batch in flight.
  let communityPolling = false;
  setInterval(async () => {
    if (!s.me || document.hidden || communityPolling || !['friends', 'inbox'].includes(s.screen)) return;
    communityPolling = true;
    const before = JSON.stringify([community.messages, community.entries, community.friends, community.incoming, community.outgoing]);
    try {
      if (s.screen === 'friends') await loadFriends();
      else { await loadInbox(); if (community.chat) await loadChat(); }
      if (before !== JSON.stringify([community.messages, community.entries, community.friends, community.incoming, community.outgoing])) render();
    } catch (e) { if (e.status === 401) signedOut(); }
    finally { communityPolling = false; }
  }, 3000);

  const explore = { tab: 'Dành cho bạn', users: [], query: '', error: '', revision: 0, radius:5, interest:'Tất cả',filters:{} };
  async function loadExplore() {
    const revision = ++explore.revision;
    explore.error = '';
    try {
      const result = await api('/discover?' + new URLSearchParams({ q: explore.query.replace(/^@/, ''), ...explore.filters, ...(explore.tab === 'Quanh đây' ? { nearby: '1', radius:String(explore.radius) } : { sort: 'interests' }), ...(explore.tab === 'Đang theo dõi'?{following:'1'}:{}) }));
      if(revision === explore.revision)explore.users = result.users || [];
    } catch(err) { if(err.status===401)throw err;if(revision === explore.revision){explore.users=[];explore.error=err.message;} }
  }
  function discoveryFilterBar(){return '<div class="discovery-filter-row">'+[['Tuổi','age'],['Cân nặng','weight'],['Chiều cao','height'],['Giới tính','gender'],['Bộ lọc','all']].map(([name,key])=>btn(name,key==='all'?'sliders-horizontal':'','discover-filter',key==='all'?'icon':'secondary',key)).join('')+'</div>';}
  root.addEventListener('error',event=>{
    const image=event.target;
    if(!image.matches?.('.native-person-tile>img'))return;
    const tile=image.parentElement;image.remove();tile.insertAdjacentHTML('afterbegin',ic('user-round'));
  },true);
  function discoverScreen() {
    const nearby=explore.tab==='Quanh đây',following=explore.tab==='Đang theo dõi';
    const users=explore.users.filter(u=>matchesPerson(u,explore.query));
    const search='<form data-explore-search class="v2-search discover-search">'+ic('search')+'<input type="search" data-explore-query aria-label="Tìm người theo tên hoặc username" placeholder="Bạn muốn kết nối với ai? Tên hoặc @username" value="'+esc(explore.query)+'"><button type="submit" class="primary">Tìm kiếm</button></form>';
    const controls=nearby?'<div class="discover-nearby"><div><strong>'+ic('map-pin')+' Vị trí</strong></div><div class="discover-location-actions"><label class="field">Bán kính<select data-approved-radius aria-label="Bán kính tìm kiếm">'+[1,5,10,25].map(n=>'<option value="'+n+'" '+(explore.radius===n?'selected':'')+'>'+n+' km</option>').join('')+'</select></label>'+btn('Cập nhật vị trí','locate-fixed','explore-location','secondary')+'</div></div>':'';
    const cards=users.map(u=>'<button type="button" class="native-person-tile" data-do="open-profile" data-value="'+esc(u.id)+'" aria-label="Xem hồ sơ '+esc(u.name)+'">'+(u.avatar?'<img src="'+esc(u.avatar)+'" alt="" loading="lazy">':ic('user-round'))+(u.isActive?'<i class="native-online" aria-label="Đang trực tuyến"></i>':'')+'<span class="native-person-caption">'+(u.distanceLabel?'<small>'+esc(u.distanceLabel)+'</small>':'')+'<strong>'+esc(u.name)+'</strong></span></button>').join('');
    return '<section class="discover-page"><div class="discover-heading"><div><h1>Khám phá</h1><p>Tìm những kết nối hợp với bạn.</p></div></div><section class="panel discover-controls" aria-label="Bộ lọc khám phá">'+tabs(['Dành cho bạn','Quanh đây','Đang theo dõi'],explore.tab,'explore-tab')+search+controls+discoveryFilterBar()+'</section><div class="discover-results-heading'+(nearby?' nearby-results-heading':'')+'"><div><h2>'+esc(nearby?'Thành viên quanh đây':following?'Những người bạn theo dõi':'Khám phá kết nối mới')+'</h2><p>'+(nearby?'Tìm bạn trong bán kính bạn chọn.':following?'Tiếp tục những kết nối bạn quan tâm.':'Tìm hiểu nhau từ những điều cùng yêu thích.')+'</p></div>'+(!explore.error?'<span>'+users.length+' thành viên</span>':'')+'</div>'+(explore.error?'<section class="panel discover-empty'+(nearby?' nearby-location-empty':'')+'" role="status">'+ic(nearby?'map-pin':'users-round')+'<h2>'+(nearby?'Khám phá những kết nối gần bạn':'Chưa tải được thành viên')+'</h2><p>'+esc(explore.error)+'</p>'+(nearby?btn('Cập nhật vị trí','locate-fixed','explore-location','primary')+btn('Khám phá thành viên','compass','explore-tab','secondary','Dành cho bạn'):btn('Thử lại','refresh-cw','explore-search','primary'))+'</section>':users.length?'<div class="discover-people">'+cards+'</div>':'<section class="panel discover-empty">'+emptyState('users-round',following?'Bạn chưa theo dõi thành viên nào':'Chưa tìm thấy thành viên',following?'Khám phá hồ sơ và theo dõi những người bạn quan tâm.':'Thử tìm theo tên hoặc tên người dùng.')+btn('Xem tất cả thành viên','users-round','discover-reset','secondary')+'</section>')+'</section>';
  }

  function childHeading(title, back='account') {return `<div class="account-child-heading">${btn('Quay lại','arrow-left','nav','icon',back)}<h1>${title}</h1></div>`;}
  let commerceModule = null, commercePromise = null;
  function ensureCommerceModule() {
    if (commerceModule) return Promise.resolve(commerceModule);
    commercePromise ||= import('/v2-commerce.js').then((mod) => {
      commerceModule = mod;
      return mod;
    }).catch((err) => {
      commercePromise = null;
      throw err;
    });
    return commercePromise;
  }
  function walletScreen(){
    if (!commerceModule) {
      ensureCommerceModule().then(() => { if (s.screen === 'wallet') render(); }).catch(() => {});
      return childHeading('Ví Kinnect') + loading();
    }
    return commerceModule.renderWalletScreen({ s, ic, esc, btn, loading, childHeading });
  }
  function storeScreen(){
    if (!commerceModule) {
      ensureCommerceModule().then(() => { if (s.screen === 'store') render(); }).catch(() => {});
      return childHeading('Cửa hàng Kinnect') + loading();
    }
    return commerceModule.renderStoreScreen({ s, ic, esc, av, btn, loading, childHeading });
  }
  function settingsScreen(){const toggle=(key,label,sub)=>'<label class="setting-toggle"><span><strong>'+label+'</strong><small>'+sub+'</small></span><input type="checkbox" data-v2-setting="'+key+'" aria-label="'+label+'" '+(s.me[key]!==false?'checked':'')+'></label>';return childHeading('Cài đặt & riêng tư')+'<div class="stack privacy-page">'+'<p class="body-copy">Quản lý thông tin bạn muốn chia sẻ.</p><section class="panel settings-section"><h2>'+ic('user-round')+' Thông tin cá nhân</h2>'+person(s.me,'@'+esc(s.me.username))+btn('Mở hồ sơ để chỉnh sửa','pencil','edit-profile','secondary')+'</section><section class="panel settings-section"><h2>'+ic('shield-check')+' Quyền riêng tư</h2>'+toggle('discoverable','Cho phép tìm thấy tôi','Xuất hiện trong Khám phá và Bạn bè quanh đây')+toggle('showDistance','Hiển thị khoảng cách','Chỉ hiện khoảng cách gần đúng')+toggle('showActivity','Trạng thái hoạt động','Cho người khác biết khi bạn đang online')+'<label class="field">Ai có thể nhắn tin<select data-approved-dm aria-label="Ai có thể nhắn tin"><option value="everyone" '+(s.me.dmMode==='everyone'?'selected':'')+'>Mọi thành viên</option><option value="friends" '+(['friends','mutual'].includes(s.me.dmMode)?'selected':'')+'>Bạn bè</option></select></label></section><section class="panel settings-section"><h2>'+ic('lock-keyhole')+' Quyền truy cập</h2>'+btn('Ảnh riêng tư','image','profile-private','secondary')+btn('Tài khoản đã chặn','user-round-x','nav','secondary','blockedAccounts')+'<p class="body-copy">Vị trí chỉ cập nhật khi bạn chọn tìm quanh đây.</p>'+btn('Tắt tìm quanh đây','map-pin-off','explore-disable-location','secondary')+'</section><section class="panel settings-section"><h2>Quản lý tài khoản</h2><a class="secondary" href="/delete-account">Xóa tài khoản và dữ liệu</a><p class="body-copy">Xóa vĩnh viễn; không thể khôi phục.</p></section></div>';}
  function securityScreen(){return childHeading('Bảo mật và đăng nhập')+`<section class="panel settings-section">${btn('Đổi mật khẩu','key-round','nav','secondary','changePassword')}<p class="body-copy">Đổi mật khẩu sẽ đăng xuất các phiên khác.</p>${btn("Xác thực 2 lớp (2FA)","shield-check","nav","secondary","twoFactor")}${btn("Email khôi phục","mail","nav","secondary","recoveryEmail")}${btn("Thiết bị đăng nhập","monitor","nav","secondary","devices")}<a class="secondary" href="https://kinnect.io.vn/support">Hỗ trợ tài khoản và khôi phục</a></section>`;}
  let plusModule=null,plusPromise=null;
  function ensurePlusModule(){if(plusModule)return Promise.resolve(plusModule);plusPromise||=import('/v2-plus.js').then(m=>(plusModule=m)).catch(e=>{plusPromise=null;throw e;});return plusPromise;}
  function twoFactorScreen(){if(!plusModule){ensurePlusModule().then(()=>plusModule.loadTwoFactor(api,s.me?.id)).then(()=>{if(s.screen==='twoFactor')render();}).catch(()=>{});return childHeading('Xác thực 2 lớp (2FA)','security')+loading();}return plusModule.renderTwoFactorScreen({s,ic,esc,btn,childHeading,loading});}
  function passwordScreen(){const hp=s.me?.hasPassword!==false;return childHeading(hp?'Đổi mật khẩu':'Đặt mật khẩu')+`<form data-v2-password class="panel settings-section">${hp?'<label class="v2-field">Mật khẩu hiện tại<input type="password" name="current" autocomplete="current-password" required></label>':'<p class="body-copy">Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Đặt mật khẩu mới (cần phiên đăng nhập gần đây).</p>'}<label class="v2-field">Mật khẩu mới<input type="password" name="next" autocomplete="new-password" minlength="6" maxlength="128" required></label><label class="v2-field">Nhập lại mật khẩu mới<input type="password" name="confirm" autocomplete="new-password" required></label><button type="submit" class="primary">Lưu mật khẩu</button></form>`;}
  function appearanceScreen(){const selected=localStorage.getItem('kinnect-v2-theme')||'auto';return childHeading('Giao diện')+'<p class="security-intro">Màu tím Kinnect được giữ ở cả chế độ sáng và tối.</p><div class="panel appearance-options">'+[['auto','monitor','Theo hệ thống','Tự đổi theo cài đặt thiết bị'],['light','sun','Sáng','Nền sáng, chữ tối rõ ràng'],['dark','moon','Tối','Nền tối, dịu mắt khi thiếu sáng']].map(([value,icon,title,sub])=>'<button type="button" class="appearance-option '+(selected===value?'selected':'')+'" data-do="v2-theme" data-value="'+title+'" aria-pressed="'+(selected===value)+'">'+ic(icon)+'<span><strong>'+title+'</strong><small>'+sub+'</small></span>'+ic(selected===value?'circle-check':'circle')+'</button>').join('')+'</div>';}
  function helpScreen(){return childHeading('Trợ giúp và hỗ trợ')+`<section class="panel settings-section"><h2>Cần hỗ trợ?</h2>${btn("Báo sự cố","flag","report-open","secondary","app:"+s.me.id)}<p class="body-copy">Gửi mô tả sự cố và màn hình bạn đang dùng cho Kinnect.</p>${btn("Trung tâm hỗ trợ","message-square","support-chat","secondary")}<a href="https://kinnect.io.vn/privacy">Chính sách quyền riêng tư</a><a href="https://kinnect.io.vn/community">Quy tắc cộng đồng</a></section>`;}

  const media = { sound:true,swipeAt:0,musicTracks:[],musicQuery:"",musicTab:"all",musicPreview:null,musicPlaying:"",musicOffset:0,musicVolume:.35,originalVolume:1,musicTrack:null,musicAudio:null,musicContext:null,musicMix:null, shorts: [], index: 0, feed: 'Đề xuất', shortHasMore:false, shortNextCursor:null, shortNextOffset:null, shortLoadingMore:false, comments: null, commentDraft: '', stream: null, fx: null, cameraModule: null, tool: '', duration: 0, delay: 0, caption: '', facing: 'user', recording: false, recorder: null, chunks: [], recorded: null, previewURL: '', busy: false, generation: 0, studioMode: 'Camera', liveTitle: '', rooms: [], room: null, liveRole: '', peers: new Map(), liveMessages: [], remote: null, call: null, socket: null, socketReady: null, reconnect: null };
  async function loadVideosBase(more=false){
    if(more&&(media.shortLoadingMore||!media.shortHasMore))return;
    const following=media.feed==='Đang theo dõi';
    const qs=new URLSearchParams({feed:following?'following':'recommended',...(s.params.video&&!more?{video:s.params.video}:{}),...(more&&following&&media.shortNextCursor?{before:String(media.shortNextCursor)}:{}),...(more&&!following&&media.shortNextOffset!=null?{offset:String(media.shortNextOffset)}:{})});
    if(more)media.shortLoadingMore=true;
    try{
      const r=await api('/shorts?'+qs),list=r.shorts||[];
      if(more){const seen=new Set(media.shorts.map(v=>v.id));media.shorts=[...media.shorts,...list.filter(v=>!seen.has(v.id))];}
      else{media.shorts=list;if(s.params.video)media.index=Math.max(0,media.shorts.findIndex(v=>v.id===s.params.video));media.index=Math.min(media.index,Math.max(0,media.shorts.length-1));}
      media.shortHasMore=!!r.hasMore;media.shortNextCursor=r.nextCursor||null;media.shortNextOffset=r.nextOffset??null;
    }finally{media.shortLoadingMore=false;}
  }
  async function loadApprovedVideoComments(){const v=media.shorts[media.index];if(!v||s.device!=='pc')return;const id=v.id;try{const result=await api('/shorts/'+id+'/comments');if(media.shorts[media.index]?.id===id)media.comments=result.comments;}catch(err){toast(err.message);}}
  async function loadVideos(){await loadVideosBase();await loadApprovedVideoComments();}
  function videoAuthorAction(v){const own=v.user_id===s.me.id;return '<button type="button" class="video-author-follow" data-do="'+(own?'open-profile':'media-follow')+'" data-value="'+esc(v.user_id)+'" aria-label="'+(own?'Trang cá nhân':v.author.following?'Huỷ theo dõi '+esc(v.author.name):'Theo dõi '+esc(v.author.name))+'" aria-pressed="'+!!v.author.following+'" title="'+(own?'Trang cá nhân':v.author.following?'Huỷ theo dõi':'Theo dõi')+'">'+av(v.author)+(own?'':'<span class="video-follow-badge '+(v.author.following?'following':'')+'">'+ic(v.author.following?'check':'plus')+'</span>')+'</button>';}
  function videoPlaybackControls(){return '<button type="button" class="video-play-toggle" data-do="video-play-toggle" aria-label="Tạm dừng video">'+ic('play')+'</button><button type="button" class="video-enable-sound" data-do="video-enable-sound" hidden>'+ic('volume-2')+' Chạm để bật âm thanh</button>';}
  function bindVideoPlayback(video){
    const stage=video.closest('.v2-video-stage');if(!stage)return;
    const sync=()=>{const toggle=stage.querySelector('.video-play-toggle');if(toggle){toggle.classList.toggle('paused',video.paused);toggle.setAttribute('aria-label',video.paused?'Phát video':'Tạm dừng video');}const enable=stage.querySelector('.video-enable-sound');if(enable)enable.hidden=!video.muted||!media.sound;};
    video.addEventListener('play',sync);video.addEventListener('pause',sync);video.addEventListener('volumechange',sync);
    bindMediaSwipe(stage,async direction=>{if(direction<0&&media.index===0){await loadVideos();media.index=0;render();}else await mediaAction(direction>0?'media-next':'media-previous');},()=>media.comments===null||s.device==='pc',()=>{if(video.paused){video.muted=!media.sound;video.play().catch(()=>{});}else video.pause();},'.v2-video-stage');
    sync();
  }
  function videoCountButton(v,kind){const like=kind==='like',count=Number((like?v.likes:v.comments)||0),label=like?(v.liked?'Bỏ thích':'Thích')+' · '+count:'Bình luận · '+count;return `<button type="button" class="cursor-interaction ${like&&v.liked?'active':''}" data-do="${like?'media-like':'media-comments'}" aria-label="${label}" ${like?'aria-pressed="'+!!v.liked+'"':''}>${ic(like?'heart':'message-circle')}<span>${count.toLocaleString('vi-VN')}</span></button>`;}
  function compactVideoScreen(){const v=media.shorts[media.index];return `<div class="v2-video-page ${v?'':'video-empty-page'}">${tabs(['Đề xuất','Đang theo dõi'],media.feed,'media-feed')}${v?`<section class="v2-video-stage"><video data-short-player src="${esc(v.video)}"${v.thumbnail?` poster="${esc(v.thumbnail)}"`:''} autoplay playsinline loop preload="auto" disablepictureinpicture controlslist="nofullscreen nodownload noremoteplayback"></video><div class="v2-video-caption"><p>${esc(v.caption)}</p></div><div class="v2-video-actions">${videoAuthorAction(v)}${videoCountButton(v,'like')}${videoCountButton(v,'comment')}${btn('Chia sẻ','send','media-share')}${btn('Tải video','download','media-download')}${v.user_id===s.me.id?btn('Xoá video','trash-2','media-delete','danger'):''}${btn('Video trước','chevron-up','media-previous')}${btn('Video tiếp','chevron-down','media-next')}</div>${videoPlaybackControls()}</section>`:emptyState('clapperboard','Chưa có video',media.feed==='Đang theo dõi'?'Theo dõi thêm thành viên để xem video mới.':'Tạo video đầu tiên của bạn.')}${v&&media.comments!==null?`<button type="button" class="video-comments-backdrop" data-do="media-close-comments" aria-label="Đóng bảng bình luận"></button><section class="v2-media-comments panel video-comments-sheet" role="dialog" aria-modal="true" aria-label="Bình luận của video"><div class="video-comments-grip" aria-hidden="true"><span></span></div><div class="video-comments-heading"><h2>${Number(v.comments||0).toLocaleString('vi-VN')} bình luận</h2>${btn('Đóng bình luận','x','media-close-comments','icon')}</div>${videoComments()}</section>`:''}</div>`;}
  function videoComments(){const v=media.shorts[media.index];if(!v)return '';return '<div class="approved-comment-list">'+(media.comments===null?'<p class="body-copy">Mở bình luận để tham gia trò chuyện.</p>':postCommentRows(v.id,media.comments)||'<p class="body-copy">Chưa có bình luận. Hãy bắt đầu cuộc trò chuyện.</p>')+'</div><form data-media-comment class="comment-form video-comment-compose">'+(s.replyComments[v.id]?'<div class="v2-reply-context">Đang trả lời <b>'+esc(s.replyNames?.[v.id]||'bình luận')+'</b> '+btn('Huỷ trả lời','x','comment-cancel-reply','icon',v.id)+'</div>':'')+av(s.me,true)+'<textarea rows="1" data-media-comment-input aria-label="Bình luận video" maxlength="500" placeholder="Viết bình luận…">'+esc(media.commentDraft)+'</textarea>'+btn('Emoji bình luận','smile','emoji-open','icon comment-emoji','comment:'+v.id)+'<button type="submit" class="primary icon" aria-label="Gửi bình luận">'+ic('send-horizontal')+'</button></form>';}

  function videoScreen(){if(s.device!=='pc')return compactVideoScreen();const v=media.shorts[media.index];if(!v)return head('Video','Những khoảnh khắc đáng xem.')+compactVideoScreen();return head('Video','Những khoảnh khắc đáng xem.')+tabs(['Đề xuất','Đang theo dõi'],media.feed,'media-feed')+'<div class="stage-cols approved-video"><div class="theatre"><section class="v2-video-stage reel"><video data-short-player src="'+esc(v.video)+'"'+(v.thumbnail?' poster="'+esc(v.thumbnail)+'"':'')+' autoplay muted playsinline loop preload="metadata"></video><div class="v2-video-caption"><p>'+esc(v.caption)+'</p></div><div class="v2-video-actions">'+videoAuthorAction(v)+videoCountButton(v,'like')+videoCountButton(v,'comment')+btn('Chia sẻ','send','media-share')+btn('Tải video','download','media-download')+(v.user_id===s.me.id?btn('Xoá video','trash-2','media-delete','danger'):'')+'</div>'+videoPlaybackControls()+'</section><div class="approved-video-paging">'+btn('Video trước','chevron-up','media-previous','icon')+btn('Video tiếp','chevron-down','media-next','icon')+'</div></div><aside class="panel details">'+person(v.author,'@'+esc(v.author.username)+' · '+Number(v.author.followerCount||0).toLocaleString('vi-VN')+' người theo dõi')+'<hr><h2>Bình luận · '+Number(v.comments||0)+'</h2>'+videoComments()+'</aside></div>';}
  function stopCapture(){stopMusicPreview();media.musicAudio?.pause();media.musicContext?.close();media.musicContext=null;media.generation++;clearTimeout(media.recordTimeout);if(media.recorder?.state==='recording'){media.recorder.onstop=null;media.recorder.stop();}media.recorder=null;media.recording=false;media.fx?.stop();media.fx=null;media.stream?.getTracks().forEach(t=>t.stop());media.stream=null;}
  function cameraErrorMessage(error){const n=error?.name||'';if(n==='NotAllowedError'||n==='SecurityError')return 'Kinnect chưa được phép dùng camera và micro. Bấm biểu tượng ổ khoá cạnh địa chỉ web, chọn Cho phép camera và micro, rồi bấm Thử lại.';if(n==='NotFoundError'||n==='OverconstrainedError')return 'Không tìm thấy camera trên thiết bị này. Bạn vẫn có thể tải video MP4 có sẵn lên.';if(n==='NotReadableError'||n==='AbortError')return 'Camera đang được ứng dụng khác sử dụng. Hãy đóng ứng dụng đó (gọi video, máy ảnh…) rồi bấm Thử lại.';return 'Không mở được camera. Hãy thử lại hoặc tải video MP4 có sẵn lên.';}
  async function prepareCamera(){
    const generation=++media.generation;stopCapture();const current=media.generation;
    if(!navigator.mediaDevices?.getUserMedia)throw Error('Cần mở Kinnect bằng HTTPS để dùng camera.');
    let stream;media.cameraError='';try{stream=await navigator.mediaDevices.getUserMedia({audio:true,video:{facingMode:media.facing,width:{ideal:1280},height:{ideal:720},resizeMode:'none'}});}catch(error){if(current!==media.generation)return;media.cameraError=cameraErrorMessage(error);render();return;}
    if(current!==media.generation||s.screen!=='studio'){stream.getTracks().forEach(t=>t.stop());return;}
    media.stream=stream;media.cameraModule ||= await import('/camera.js');
    if(current!==media.generation){stream.getTracks().forEach(t=>t.stop());return;}
    media.fx=media.cameraModule.createEffects(stream,{portrait:true,fit:s.device==='pc'?'contain':'cover'});media.fx.set({mirror:media.facing==='user'});render();
  }
  function musicSaved(){try{return JSON.parse(localStorage.getItem('kinnect-saved-sounds:'+s.me.id)||'[]');}catch{return [];}}
  const soundTime=n=>Math.floor((n||0)/60)+':'+String(Math.floor((n||0)%60)).padStart(2,'0');
  function stopMusicPreview(){media.musicPreview?.pause();media.musicPreview=null;media.musicPlaying='';}
  function musicRows(){const saved=musicSaved(),tracks=media.musicTracks.filter(t=>(media.musicTab!=='saved'||saved.includes(t.file))&&normalized(t.title+' '+t.artist).includes(normalized(media.musicQuery)));return tracks.length?tracks.map((t,i)=>`<div class="sound-row ${media.musicTrack?.file===t.file?'selected':''}" data-sound-row><button type="button" class="sound-cover sound-color-${i%5}" data-do="music-preview" data-value="${esc(t.file)}" aria-label="${media.musicPlaying===t.file?'Dừng nghe':'Nghe thử'} ${esc(t.title)}">${ic(media.musicPlaying===t.file?'pause':'play')}</button><div class="sound-info"><strong>${esc(t.title)}</strong><small>${esc(t.artist||'Âm thanh của bạn')} · ${soundTime(t.duration)}</small></div><button class="sound-save icon" type="button" data-do="music-save" data-value="${esc(t.file)}" aria-label="Lưu ${esc(t.title)}" aria-pressed="${saved.includes(t.file)}">${ic(saved.includes(t.file)?'check':'bookmark')}</button>${btn(media.musicTrack?.file===t.file?'Đã chọn':'Dùng','check','media-select-music','sound-use',t.file)}</div>`).join(''):'<div class="sound-empty">'+ic('music-2')+'<strong>'+(media.musicTab==='saved'?'Chưa có âm thanh đã lưu':'Không tìm thấy âm thanh')+'</strong><span>'+(media.musicTab==='saved'?'Bấm biểu tượng lưu bên cạnh bài bạn thích.':'Thử tìm bằng tên bài hoặc nghệ sĩ khác.')+'</span></div>';}
  document.addEventListener('keydown',e=>{if(e.key==='Escape'){if(media.tool==='Âm thanh'){stopMusicPreview();media.tool='';render();}else if(s.postMenu){s.postMenu='';render();}}});
  function musicPicker(){const t=media.musicTrack,max=Math.max(0,(t?.duration||0)-(s.params.storyCamera&&media.storyMode==='Ảnh'?15:media.duration));return `<div class="sound-picker-layer"><section class="sound-picker" role="dialog" aria-modal="true" aria-label="Thêm âm thanh"><div class="sound-grip"></div><header><div><small>THƯ VIỆN ÂM THANH</small><h2>Thêm âm thanh</h2></div>${btn('Đóng âm thanh','x','media-tool','icon','')}</header><label class="sound-search">${ic('search')}<input data-music-query aria-label="Tìm âm thanh" placeholder="Tìm bài hát, nghệ sĩ" value="${esc(media.musicQuery)}" autocomplete="off"></label><div class="sound-tabs" role="group" aria-label="Thư viện nhạc">${btn('Khám phá','music-2','music-tab',media.musicTab==='all'?'active':'','all')}${btn('Đã lưu','bookmark','music-tab',media.musicTab==='saved'?'active':'','saved')}<label class="sound-upload" title="Tải âm thanh lên">${ic('upload')}<span>Của bạn</span><input data-own-music type="file" accept="audio/*" hidden></label></div><div class="sound-section-label"><strong>${media.musicTab==='saved'?'Bộ sưu tập của bạn':'Dành cho video & tin'}</strong><span>${media.musicTracks.length} âm thanh</span></div><div class="sound-results">${musicRows()}</div>${t?`<footer class="sound-mix"><div class="sound-current">${ic('music-2')}<strong>${esc(t.title)}</strong>${btn('Gỡ nhạc','x','media-clear-music','icon')}</div><label>Đoạn bắt đầu <output data-sound-offset>${soundTime(media.musicOffset)}</output><input aria-label="Đoạn bắt đầu" data-music-offset type="range" min="0" max="${max}" step=".1" value="${media.musicOffset}"></label><div class="sound-volumes"><label>Nhạc <output data-sound-music>${Math.round(media.musicVolume*100)}%</output><input aria-label="Âm lượng nhạc" data-music-volume type="range" min="0" max="1" step=".05" value="${media.musicVolume}"></label><label>Âm gốc <output data-sound-original>${Math.round(media.originalVolume*100)}%</output><input aria-label="Âm lượng gốc" data-original-volume type="range" min="0" max="1" step=".05" value="${media.originalVolume}"></label></div>${btn('Xong','check','media-tool','primary','')}</footer>`:'<footer class="sound-hint">'+ic('headphones')+' Nghe thử, sau đó bấm Dùng để chọn nhạc.</footer>'}</section></div>`;}
  function mediaTool(){const mod=media.cameraModule;if(!media.tool||!mod)return '';let content='';
    if(media.tool==='Bộ lọc')content=`<div class="v2-filter-options">${mod.FILTERS.map(([id,label])=>`<button type="button" class="${media.fx?.state.filter===id?'active':''}" data-do="media-filter" data-value="${id}"><span class="v2-filter-swatch" data-filter-css="${esc(mod.FILTERS.find(f=>f[0]===id)[2])}"></span>${esc(label)}</button>`).join('')}</div>`;
    if(media.tool==='Làm đẹp')content=`<label class="setting-toggle">Làm mịn da<input type="checkbox" data-media-soft ${media.fx?.state.soft?'checked':''}></label><label class="v2-field">Mức độ làm mịn<input type="range" min="0" max="1" step="0.05" value="${media.fx?.state.smooth||.5}" data-media-smooth></label>`;
    if(media.tool==='Hiệu ứng')content=`<div class="v2-filter-options">${mod.STICKERS.map(([id,label,emoji])=>`<button type="button" data-do="media-sticker" data-value="${id}" class="${media.fx?.state.sticker===id?'active':''}"><span class="v2-filter-swatch">${esc(emoji||'✦')}</span>${esc(label)}</button>`).join('')}</div>`;
    if(media.tool==='Âm thanh')return '';
    if(media.tool==='Hẹn giờ')content=tabs(['Tắt','3 giây','10 giây'],media.delay?media.delay+' giây':'Tắt','media-delay');
    return `<section class="v2-camera-tool panel"><div class="heading"><h2>${media.tool}</h2>${btn('Đóng công cụ','x','media-tool','icon','')}</div>${content}</section>`;
  }
  function storyCameraScreen(){const review=!!media.previewURL,photo=media.recorded?.type.startsWith('image/');return '<section class="story-camera-shell"><div class="v2-camera-stage story-camera-stage">'+(review&&photo?'<img class="story-photo-preview" src="'+esc(media.previewURL)+'" alt="Ảnh tin vừa chụp">':'<video data-camera-preview autoplay muted playsinline '+(review?'src="'+esc(media.previewURL)+'" controls':'')+'></video>')+(media.cameraError&&!review?'<div class="v2-camera-error" role="alert">'+ic('camera-off')+'<p>'+esc(media.cameraError)+'</p>'+btn('Thử lại','rotate-ccw','media-retry','primary')+'</div>':'')+'<div class="v2-camera-top">'+btn('Đóng tạo tin','x','story-camera-close','icon')+btn(media.musicTrack?.title||'Thêm nhạc','music-2','media-music','v2-sound-pill')+(!review?btn('Đổi camera','switch-camera','media-flip','icon'):'')+'</div>'+(!review?'<div class="v2-camera-tools">'+['Bộ lọc','Làm đẹp','Hiệu ứng'].map((l,i)=>btn(l,['sliders-horizontal','sparkles','wand-sparkles'][i],'media-tool','',l)).join('')+'</div>':'')+'<div class="v2-camera-bottom">'+(media.storyError?'<p class="story-camera-error" role="alert">'+esc(media.storyError)+'</p>':'')+(review?'<input data-media-caption aria-label="Chú thích tin" maxlength="500" placeholder="Thêm chú thích…" value="'+esc(media.caption)+'">'+(photo&&media.musicTrack?'<small>Ảnh có nhạc sẽ thành video 15 giây.</small>':'')+'<div class="row">'+btn('Chụp / quay lại','rotate-ccw','story-camera-retake','secondary')+btn(media.busy?'Đang xử lý…':'Đăng tin','send','story-camera-publish','primary')+'</div>':(media.storyMode==='Video'?tabs(['∞','15s','60s'],media.duration?media.duration+'s':'∞','media-duration'):'')+'<div class="v2-shutter-row"><label class="kn-file-btn">'+ic('image')+'<span>Thư viện</span><input aria-label="Ảnh hoặc video từ thư viện" data-story-camera-file type="file" accept="image/png,image/jpeg,image/webp,video/mp4" hidden></label><button type="button" class="v2-shutter '+(media.recording?'recording':'')+'" data-do="'+(media.storyMode==='Video'?'media-record':'story-camera-photo')+'" aria-label="'+(media.storyMode==='Video'?(media.recording?'Dừng quay':'Bắt đầu quay'):'Chụp ảnh')+'"><span></span></button><span data-record-clock></span></div>'+tabs(['Ảnh','Video'],media.storyMode||'Ảnh','story-camera-mode'))+'</div>'+mediaTool()+'</div></section>';}
  async function openStoryCamera(file){if(file&&(!['image/png','image/jpeg','image/webp','video/mp4'].includes(file.type)||false))throw Error('Chọn ảnh PNG/JPEG/WebP hoặc video MP4 hợp lệ.');stopCapture();if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.previewURL=file?URL.createObjectURL(file):'';media.recorded=file||null;media.caption='';media.storyMode='Ảnh';media.studioMode='Camera';media.tool='';media.musicAudio?.pause();media.musicTrack=null;media.musicAudio=null;await go('studio',{storyCamera:'1'});}
  async function finalizeRecordedMp4(blob,seconds){const buffer=await blob.arrayBuffer(),view=new DataView(buffer),bytes=new Uint8Array(buffer);if(bytes.length<24)return blob;const type=at=>String.fromCharCode(...bytes.slice(at+4,at+8));function scan(start,end){for(let at=start;at+8<=end;){let size=view.getUint32(at),header=8;if(size===1){if(at+16>end)return;size=Number(view.getBigUint64(at+8));header=16;}if(size===0)size=end-at;if(size<header||at+size>end)return;const kind=type(at),data=at+header;if(kind==='moov')scan(data,at+size);if(kind==='mvhd'){if(bytes[data]===0&&data+20<=at+size){const scale=view.getUint32(data+12);if(scale&&view.getUint32(data+16)===0)view.setUint32(data+16,Math.round(seconds*scale));}else if(bytes[data]===1&&data+32<=at+size){const scale=view.getUint32(data+20);if(scale&&view.getBigUint64(data+24)===0n)view.setBigUint64(data+24,BigInt(Math.round(seconds*scale)));}}at+=size;}}scan(0,bytes.length);return new Blob([buffer],{type:'video/mp4'});}
  async function storyWithMusic(blob){
    const AudioContextClass=window.AudioContext||window.webkitAudioContext,ctx=new AudioContextClass();await ctx.resume();media.musicAudio?.pause();
    let objectURL,source,output,recorder,raf,timer;const chunks=[];
    try{let musicBytes;if(media.musicTrack.blob)musicBytes=await media.musicTrack.blob.arrayBuffer();else{const response=await fetch(media.musicTrack.url);if(!response.ok)throw Error('Không tải được nhạc.');musicBytes=await response.arrayBuffer();}const audio=await ctx.decodeAudioData(musicBytes),destination=ctx.createMediaStreamDestination(),music=ctx.createBufferSource(),gain=ctx.createGain();music.buffer=audio;music.loop=true;gain.gain.value=media.musicVolume;music.connect(gain).connect(destination);objectURL=URL.createObjectURL(blob);const photo=blob.type.startsWith('image/');source=document.createElement(photo?'img':'video');if(!photo){source.muted=true;source.playsInline=true;source.preload='auto';}await new Promise((resolve,reject)=>{source[photo?'onload':'onloadeddata']=resolve;source.onerror=()=>reject(Error('Không đọc được ảnh/video.'));source.src=objectURL;});
      const canvas=document.createElement('canvas');canvas.width=540;canvas.height=960;const draw=()=>{const w=photo?source.naturalWidth:source.videoWidth,h=photo?source.naturalHeight:source.videoHeight,k=Math.min(540/w,960/h),g=canvas.getContext('2d');g.fillStyle='#111';g.fillRect(0,0,540,960);g.drawImage(source,(540-w*k)/2,(960-h*k)/2,w*k,h*k);raf=requestAnimationFrame(draw);};draw();
      output=new MediaStream([...canvas.captureStream(25).getVideoTracks(),...destination.stream.getAudioTracks()]);if(!photo){const original=ctx.createMediaElementSource(source),originalGain=ctx.createGain();originalGain.gain.value=media.originalVolume;original.connect(originalGain).connect(destination);}
      const mime=['video/mp4;codecs=avc1.42001E,mp4a.40.2','video/mp4'].find(t=>MediaRecorder.isTypeSupported(t));if(!mime)throw Error('Trình duyệt chưa hỗ trợ ghép nhạc MP4.');recorder=new MediaRecorder(output,{mimeType:mime,videoBitsPerSecond:1100000});
      const done=new Promise((resolve,reject)=>{recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data);};recorder.onerror=()=>reject(Error('Không ghép được nhạc.'));recorder.onstop=()=>resolve(new Blob(chunks,{type:'video/mp4'}));});
      const stop=()=>{if(recorder.state==='recording')recorder.stop();};recorder.start(250);music.start(0,media.musicOffset%audio.duration);if(!photo){source.onended=stop;await source.play();}timer=setTimeout(stop,(photo?15:(source.duration||15))*1000);const result=await done;music.stop();return finalizeRecordedMp4(result,photo?15:(source.duration||15));
    }finally{clearTimeout(timer);cancelAnimationFrame(raf);if(recorder?.state==='recording'){recorder.onstop=null;recorder.stop();}if(source?.pause)source.pause();output?.getTracks().forEach(t=>t.stop());if(objectURL)URL.revokeObjectURL(objectURL);await ctx.close();}
  }
  function mobileStudioScreen(){return `<section class="v2-camera-stage"><video data-camera-preview autoplay muted playsinline ${media.previewURL?'src="'+esc(media.previewURL)+'" controls':''}></video>${media.cameraError&&!media.previewURL?'<div class="v2-camera-error" role="alert">'+ic('camera-off')+'<p>'+esc(media.cameraError)+'</p>'+btn('Thử lại','rotate-ccw','media-retry','primary')+'</div>':''}<div class="v2-camera-top">${btn('Đóng camera','x','media-close','icon')}${media.studioMode==='Camera'?btn(media.musicTrack?.title||'Thêm âm thanh','music-2','media-music','v2-sound-pill'):''}${btn('Đổi camera','switch-camera','media-flip','icon')}</div>${!media.previewURL?`<div class="v2-camera-tools">${['Bộ lọc','Làm đẹp','Hiệu ứng',...(media.studioMode==='Camera'?['Hẹn giờ']:[])].map((l,i)=>btn(l,['sliders-horizontal','sparkles','wand-sparkles','timer'][i],'media-tool','',l)).join('')}${btn(media.fx?.state.fit==='cover'?'Lấp đầy':'Toàn cảnh','maximize','media-framing','')}</div>`:''}<div class="v2-camera-bottom">${media.previewURL?`<input data-media-caption aria-label="Chú thích video" placeholder="Thêm chú thích…" maxlength="500" value="${esc(media.caption)}"><div class="row">${btn('Quay lại','rotate-ccw','media-retake','secondary')}${btn(media.busy?'Đang đăng…':'Đăng video','send','media-publish','primary')}</div>`:media.studioMode==='Live'?`<input data-media-live-title aria-label="Tiêu đề buổi live" value="${esc(media.liveTitle)}" placeholder="Bạn muốn trò chuyện về gì?" maxlength="100"><small>Chưa lên sóng · Chỉ bắt đầu khi bạn bấm Lên sóng</small>${btn('Lên sóng','radio','media-live-start','primary')}`:`${tabs(['∞','15s','60s'],media.duration?media.duration+'s':'∞','media-duration')}<div class="v2-shutter-row"><label class="kn-file-btn">${ic('image')}<span>Tải lên</span><input data-media-upload type="file" accept="video/mp4" hidden></label><button type="button" class="v2-shutter ${media.recording?'recording':''}" data-do="media-record" aria-label="${media.recording?'Dừng quay':'Bắt đầu quay'}"><span></span></button><span data-record-clock></span></div>`}${!media.previewURL?tabs(['Camera','Live'],media.studioMode,'media-studio-mode'):''}</div>${mediaTool()}</section>`;}
  function studioScreen(){if(s.params.storyCamera)return storyCameraScreen();if(s.device!=='pc')return mobileStudioScreen();const preview=!!media.previewURL,step=preview?(media.reviewStep||1):0,live=media.studioMode==='Live';return '<div class="steps">'+['Quay','Xem lại','Đăng'].map((x,i)=>'<span class="'+(step===i?'current':'')+'">'+x+'</span>').join('<span>›</span>')+'</div><div class="stage-cols approved-studio"><div><div class="camera-stage"><section class="v2-camera-stage"><video data-camera-preview autoplay muted playsinline '+(preview?'src="'+esc(media.previewURL)+'" controls':'')+'></video>'+(media.cameraError&&!preview?'<div class="v2-camera-error" role="alert">'+ic('camera-off')+'<p>'+esc(media.cameraError)+'</p>'+btn('Thử lại','rotate-ccw','media-retry','primary')+'</div>':'')+'<div class="v2-camera-top">'+btn('Đóng camera','x','media-close','icon')+(!preview?btn('Đổi camera','switch-camera','media-flip','icon'):'')+'</div>'+mediaTool()+'</section></div><div class="shutter-row">'+(preview?btn('Quay lại','rotate-ccw','media-retake','secondary')+(step===1?btn('Tiếp tục','arrow-right','approved-review-next','primary'):''):live?'<small>Chưa lên sóng · Chỉ bắt đầu khi bạn bấm Lên sóng</small>':'<label class="kn-file-btn">'+ic('image-plus')+'Tải lên<input data-media-upload type="file" accept="video/mp4" hidden></label><button type="button" class="shutter v2-shutter '+(media.recording?'recording':'')+'" data-do="media-record" aria-label="'+(media.recording?'Dừng quay':'Bắt đầu quay')+'"><span></span></button><span data-record-clock></span>')+'</div></div><aside class="panel details"><h2>'+(preview?'Hoàn thiện video':'Thiết lập quay')+'</h2>'+(preview?'<label class="field">Chú thích<input data-media-caption aria-label="Chú thích video" maxlength="500" value="'+esc(media.caption)+'" placeholder="Viết vài dòng về video…"></label><p class="body-copy">Video dọc · Ảnh bìa lấy từ khung hình đầu.</p>'+btn(media.busy?'Đang đăng…':'Đăng video','send','media-publish','primary'):tabs(['Camera','Live'],media.studioMode,'media-studio-mode')+(live?'<label class="field">Tiêu đề buổi live<input data-media-live-title aria-label="Tiêu đề buổi live" value="'+esc(media.liveTitle)+'" maxlength="100"></label>'+btn('Lên sóng','radio','media-live-start','primary'):'<div class="field">Thời lượng'+tabs(['∞','15s','60s'],media.duration?media.duration+'s':'∞','media-duration')+'</div>')+'<label class="field">Camera<select data-approved-camera aria-label="Camera"><option value="user" '+(media.facing==='user'?'selected':'')+'>Camera trước</option><option value="environment" '+(media.facing==='environment'?'selected':'')+'>Camera sau</option></select></label>'+btn(media.fx?.state.fit==='cover'?'Lấp đầy':'Toàn cảnh','maximize','media-framing','secondary')+'<hr>'+btn(media.musicTrack?.title||'Chọn nhạc nền','music','media-music','secondary')+['Bộ lọc','Làm đẹp','Hiệu ứng','Hẹn giờ'].map((l,i)=>btn(l,['sliders-horizontal','sparkles','wand-sparkles','timer'][i],'media-tool','secondary',l)).join(''))+'</aside></div>';}
  async function recordVideo(){
    if(media.recording){media.recorder.stop();return;}
    if(!media.fx)throw Error('Camera chưa sẵn sàng.');
    const mime=['video/mp4;codecs=avc1.42001E,mp4a.40.2','video/mp4'].find(m=>MediaRecorder.isTypeSupported(m));
    if(!mime)throw Error('Trình duyệt chưa hỗ trợ quay MP4. Bạn có thể tải video MP4 lên.');
    const generation=media.generation;if(media.delay){toast('Bắt đầu quay sau '+media.delay+' giây');render();await new Promise(r=>setTimeout(r,media.delay*1000));if(generation!==media.generation||s.screen!=='studio')return;}
    let recordStream=media.fx.stream;
    if(media.musicAudio&&!s.params.storyCamera){media.musicAudio.pause();media.musicAudio=new Audio(media.musicTrack.url);media.musicAudio.loop=true;media.musicAudio.volume=media.musicVolume;const AudioContextClass=window.AudioContext||window.webkitAudioContext;media.musicContext=new AudioContextClass();await media.musicContext.resume();const dest=media.musicContext.createMediaStreamDestination();if(media.fx.stream.getAudioTracks().length){const original=media.musicContext.createGain();original.gain.value=media.originalVolume;media.musicContext.createMediaStreamSource(media.fx.stream).connect(original).connect(dest);}media.musicContext.createMediaElementSource(media.musicAudio).connect(dest);media.musicAudio.currentTime=media.musicOffset;await media.musicAudio.play();recordStream=new MediaStream([...media.fx.stream.getVideoTracks(),...dest.stream.getAudioTracks()]);}
    media.chunks=[];media.recorder=new MediaRecorder(recordStream,{mimeType:mime,videoBitsPerSecond:1200000});media.recorder.ondataavailable=e=>{if(e.data.size)media.chunks.push(e.data);};
    media.recorder.onstop=async()=>{media.musicAudio?.pause();media.musicContext?.close();media.musicContext=null;clearTimeout(media.recordTimeout);media.recording=false;if(generation!==media.generation)return;media.recorded=await finalizeRecordedMp4(new Blob(media.chunks,{type:'video/mp4'}),(Date.now()-media.recordStarted)/1000);try{const edited=s.params.storyCamera?await reviewMediaFile(media.recorded,'story'):await chooseVideoPath(media.recorded);if(!edited)return;media.recorded=edited;}catch(err){toast(err.message);}if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.previewURL=URL.createObjectURL(media.recorded);stopCapture();render();};
    media.recording=true;media.recorder.start(500);media.recordStarted=Date.now();media.recordTimeout=media.duration>0?setTimeout(()=>{if(media.recorder?.state==='recording')media.recorder.stop();},media.duration*1000):null;render();
  }
  function attachMedia(){
    const reviewStage=app.querySelector('.v2-camera-stage');
    if(media.recorded&&media.videoPath!=='basic'&&media.previewURL&&reviewStage&&!reviewStage.querySelector('[data-do="media-edit"]'))reviewStage.insertAdjacentHTML('beforeend',btn('Chỉnh sửa','wand-sparkles','media-edit','approved-media-edit'));
    const composerPreview=app.querySelector('.composer-preview');
    if(s.composer?.media&&composerPreview&&!composerPreview.querySelector('[data-do="composer-edit-media"]'))composerPreview.insertAdjacentHTML('beforeend',btn('Chỉnh sửa','wand-sparkles','composer-edit-media','secondary'));

    app.querySelectorAll('[data-filter-css]').forEach(el=>{el.style.filter=el.dataset.filterCss;});
    const preview=app.querySelector('[data-camera-preview]');if(preview&&!media.previewURL&&media.fx){preview.srcObject=media.fx.stream;preview.play().catch(()=>{});}
    const remote=app.querySelector('[data-call-remote]');if(remote&&media.call?.remote){if(remote.srcObject!==media.call.remote)remote.srcObject=media.call.remote;remote.play().catch(()=>{if(media.call&&!media.call.playbackBlocked){media.call.playbackBlocked=true;render();}});}
    const local=app.querySelector('[data-call-local]');if(local&&media.call?.stream){if(local.srcObject!==media.call.stream)local.srcObject=media.call.stream;local.play().catch(()=>{});}
    app.querySelectorAll('[data-live-peer]').forEach(video=>{const id=video.dataset.livePeer,own=id===media.liveStage?.selfId,stream=own||!media.liveStage&&media.liveRole==='host'?liveLocalStream():media.liveStreams?.get(id)||(!media.liveStage?media.remote:null);if(video.srcObject!==stream)video.srcObject=stream||null;video.muted=own||!!media.liveMuted;video.onplaying=()=>app.querySelector('.live-stream-status')?.classList.add('ready');if(video.readyState>=2)video.onplaying();if(stream)video.play().catch(()=>{video.muted=true;video.play().catch(()=>{});});});
  }
  async function mediaAction(action,value){const v=media.shorts[media.index];switch(action){
    case 'media-feed':delete s.params.video;media.feed=value;media.index=0;media.comments=null;await loadVideos();render();break;
    case 'media-next':case 'media-previous':{const count=media.shorts.length;if(!count)break;const next=media.index+(action==='media-next'?1:-1);if(action==='media-next'&&media.shortHasMore){if(next>=count)await loadVideosBase(true);else if(next>=count-3)loadVideosBase(true).catch(()=>{});}const total=media.shorts.length;media.index=media.feed==='Đề xuất'&&!media.shortHasMore?(next+total)%total:Math.max(0,Math.min(total-1,next));media.comments=null;await loadApprovedVideoComments();render();break;}
    case 'media-like':if(v&&!v.likePending){v.likePending=true;try{await api('/shorts/'+v.id+'/like',v.liked?'DELETE':'POST',{});v.likes+=v.liked?-1:1;v.liked=!v.liked;if(media.shorts[media.index]?.id===v.id)app.querySelectorAll('[data-do=media-like]').forEach(b=>{b.outerHTML=videoCountButton(v,'like');});}finally{v.likePending=false;}}break;
    case 'media-delete':if(v&&v.user_id===s.me.id){if(!(await knConfirm('Xoá video này? Không thể hoàn tác.')))break;await api('/shorts/'+v.id,'DELETE');delete s.params.video;media.shorts.splice(media.index,1);media.index=Math.min(media.index,Math.max(0,media.shorts.length-1));media.comments=null;if(media.shorts.length)await loadApprovedVideoComments();toast('Đã xoá video');render();}break;
    case 'media-comments':if(v){const r=await api('/shorts/'+v.id+'/comments');if(media.shorts[media.index]?.id===v.id){media.comments=r.comments;render();focusCommentInput(v.id);}}break;
    case 'media-close-comments':media.comments=null;render();break;
    case 'media-follow':if(v&&!v.followPending){v.followPending=true;try{const r=await api('/users/'+v.user_id+'/follow',v.author.following?'DELETE':'POST',{});const followerCount=Math.max(0,Number(v.author.followerCount||0)+(v.author.following?-1:1));for(const item of media.shorts)if(item.user_id===v.user_id)item.author={...r.user,followerCount};if(media.shorts[media.index]?.id===v.id)app.querySelectorAll('[data-do=media-follow]').forEach(b=>{b.outerHTML=videoAuthorAction(v);});}finally{v.followPending=false;}}break;
    case 'media-download':if(v){const response=await fetch(v.video,{credentials:'same-origin'});if(!response.ok)throw Error('Chưa tải được video. Vui lòng thử lại.');const url=URL.createObjectURL(await response.blob()),link=document.createElement('a');link.href=url;link.download='Kinnect-'+v.id+'.mp4';document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);}break;
    case 'media-share':if(v){await navigator.clipboard.writeText(location.origin+'/share/short/'+encodeURIComponent(v.id));toast('Đã sao chép liên kết video');render();}break;
    case 'media-music':media.cameraModule ||= await import('/camera.js');media.musicAudio?.pause();media.musicTracks=[...(await api('/music')).tracks,...media.musicTracks.filter(t=>t.blob)];const catalog={"tiktok-01.mp3": {"duration": 66.43}, "tiktok-02.mp3": {"duration": 18.94}, "tiktok-03.mp3": {"duration": 47.75}, "tiktok-04.mp3": {"duration": 34.53}, "tiktok-05.mp3": {"duration": 59.82}, "tiktok-06.mp3": {"duration": 58.64}, "tiktok-07.mp3": {"duration": 56.58}, "tiktok-08.mp3": {"duration": 56.4}, "tiktok-09.mp3": {"duration": 40.33}, "tiktok-10.mp3": {"duration": 60.89}};media.musicTracks=media.musicTracks.map(t=>({...t,...catalog[t.file]}));media.tool='Âm thanh';render();break;
    case 'music-tab':media.musicTab=value;render();break;
    case 'music-save':{let ids=musicSaved();ids=ids.includes(value)?ids.filter(x=>x!==value):[...ids,value];localStorage.setItem('kinnect-saved-sounds:'+s.me.id,JSON.stringify(ids));render();break;}
    case 'music-preview':{const track=media.musicTracks.find(t=>t.file===value);if(!track)break;const was=media.musicPlaying===value;stopMusicPreview();media.musicAudio?.pause();if(!was){const audio=new Audio(track.url);media.musicPreview=audio;media.musicPlaying=value;audio.volume=media.musicVolume;audio.currentTime=media.musicTrack?.file===value?media.musicOffset:0;audio.onended=()=>{stopMusicPreview();if(media.tool==='Âm thanh')render();};try{await audio.play();}catch{stopMusicPreview();toast('Không phát được âm thanh. Hãy thử lại.');}}render();break;}
    case 'media-select-music':{const track=media.musicTracks.find(t=>t.file===value);if(track){stopMusicPreview();media.musicAudio?.pause();if(media.musicTrack?.file!==track.file)media.musicOffset=0;media.musicTrack=track;media.musicAudio=new Audio(track.url);media.musicAudio.loop=true;media.musicAudio.volume=media.musicVolume;render();}break;}
    case 'media-clear-music':stopMusicPreview();media.musicOffset=0;media.musicAudio?.pause();media.musicAudio=null;media.musicTrack=null;render();break;
    case 'media-tool':stopMusicPreview();media.tool=value;render();break;
    case 'media-filter':media.fx?.set({filter:value});render();break;
    case 'media-sticker':media.fx?.set({sticker:value});render();break;
    case 'media-delay':media.delay=parseInt(value)||0;render();break;
    case 'media-duration':if(!media.recording)media.duration=parseInt(value)||0;render();break;
    case 'media-retry':await prepareCamera();render();break;
    case 'media-record':await recordVideo();break;
    case 'media-framing':if(media.fx){media.fx.set({fit:media.fx.state.fit==='contain'?'cover':'contain'});render();}break;
    case 'media-flip':if(media.recording)throw Error('Dừng quay trước khi đổi camera.');media.facing=media.facing==='user'?'environment':'user';await prepareCamera();break;
    case 'media-studio-mode':if(media.recording)throw Error('Dừng quay trước khi chuyển chế độ.');media.studioMode=value;media.tool='';render();break;
    case 'media-close':stopCapture();await go('feed');break;
    case 'media-retake':if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.previewURL='';media.reviewStep=0;media.recorded=null;render();if(!media.fx)await prepareCamera();break;
    case 'media-publish':if(!media.recorded||media.busy)break;media.busy=true;render();try{await api('/shorts','POST',{caption:media.caption,data:await readFile(media.recorded)});media.previewURL&&URL.revokeObjectURL(media.previewURL);media.previewURL='';media.recorded=null;stopCapture();await go('video');toast('Đã đăng video');}finally{media.busy=false;render();}break;
    default:return false;
  }return true;}

  const candidateQueue=[];let candidateTimer=null;
  function clearCandidateQueue(){candidateQueue.length=0;clearTimeout(candidateTimer);candidateTimer=null;}
  function flushCandidateQueue(){candidateTimer=null;const item=candidateQueue.shift();if(item&&item.socket===media.socket&&item.socket.readyState===WebSocket.OPEN)item.socket.send(JSON.stringify(item.data));if(candidateQueue.length)candidateTimer=setTimeout(flushCandidateQueue,70);}
  function socketSend(data){if(media.socket?.readyState!==WebSocket.OPEN)throw Error('Đang kết nối lại. Vui lòng thử sau.');if(data.candidate&&['call-signal','signal'].includes(data.type)){if(candidateQueue.length>=256)throw Error('Quá nhiều tín hiệu kết nối. Vui lòng thử gọi lại.');candidateQueue.push({socket:media.socket,data});if(!candidateTimer)candidateTimer=setTimeout(flushCandidateQueue,70);return;}media.socket.send(JSON.stringify(data));}
  async function ensureSocket(){
    if(media.socket?.readyState===WebSocket.OPEN)return;
    if(media.socketReady)return media.socketReady;
    media.socketReady=new Promise((resolve,reject)=>{
      const ownerId=s.me?.id,ws=media.socket=new WebSocket((location.protocol==='https:'?'wss:':'ws:')+'//'+location.host);
      const timeout=setTimeout(()=>{ws.close();reject(Error('Kết nối máy chủ quá thời gian.'));},10000);
      ws.onopen=()=>{clearTimeout(timeout);resolve();if(media.call?.reconnecting)ws.send(JSON.stringify({type:'call-resume',callId:media.call.id}));};
      let queue=Promise.resolve();ws.onmessage=e=>{if(s.me?.id!==ownerId)return;queue=queue.then(()=>handleMediaSignal(JSON.parse(e.data))).catch(err=>{toast(err.message);render();});};
      ws.onclose=event=>{if(media.socket!==ws)return;aiDrafts.clear();paintAIStream();clearCandidateQueue();clearTimeout(timeout);media.socketReady=null;if(event.code===4401){clearTimeout(media.reconnect);media.socket=null;if(s.me)signedOut('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');reject(Error('Phiên đăng nhập đã hết hạn.'));return;}if(media.call?.accepted&&media.callResumeSupported){const c=media.call;c.reconnecting=true;c.status='Đang nối lại với máy chủ…';clearTimeout(c.timeout);clearTimeout(c.disconnectTimer);clearTimeout(c.resumeTimeout);c.resumeTimeout=setTimeout(()=>{if(media.call===c)finishCall('Không nối lại được với máy chủ ('+event.code+').');},48000);startReconnectTone();render();}else if(media.call)finishCall(event.code===1008?'Máy chủ đã ngắt tín hiệu cuộc gọi ('+event.code+': '+event.reason+').':'Mất kết nối cuộc gọi ('+event.code+').');if(media.room){leaveLive(false);toast('Kết nối buổi live đã kết thúc.');render();}if(s.me)media.reconnect=setTimeout(()=>ensureSocket().catch(()=>{}),2500);reject(Error('Mất kết nối máy chủ.'));};
      ws.onerror=()=>{};
    });return media.socketReady;
  }
  async function newPeer(sendSignal,stream,onTrack,live=false){
    const config=await api('/call-config');const pc=new RTCPeerConnection(config);pc.pendingCandidates=[];
    if(stream)for(const track of stream.getTracks()){const sender=pc.addTrack(track,stream);if(track.kind==='video'){const parameters=sender.getParameters();if(!parameters.encodings?.length)parameters.encodings=[{}];parameters.encodings[0].maxBitrate=650000;parameters.encodings[0].maxFramerate=24;parameters.degradationPreference='balanced';try{await sender.setParameters(parameters);}catch{}}}
    if(live){if(!stream?.getVideoTracks().length)pc.addTransceiver('video',{direction:'recvonly'});if(!stream?.getAudioTracks().length)pc.addTransceiver('audio',{direction:'recvonly'});}
    pc.onicecandidate=e=>{if(e.candidate)try{sendSignal({candidate:e.candidate.toJSON()});}catch{}};
    const remoteStream=new MediaStream();pc.ontrack=e=>{const tracks=e.streams[0]?.getTracks()||[e.track];for(const track of tracks)if(!remoteStream.getTracks().some(t=>t.id===track.id))remoteStream.addTrack(track);onTrack(remoteStream);};return pc;
  }
  async function peerSignal(pc,message,sendSignal){
    if(message.description){await pc.setRemoteDescription(message.description);for(const candidate of pc.pendingCandidates)await pc.addIceCandidate(candidate);pc.pendingCandidates=[];if(message.description.type==='offer'){await pc.setLocalDescription(await pc.createAnswer());sendSignal({description:pc.localDescription.toJSON()});}}
    else if(message.candidate){if(pc.remoteDescription)await pc.addIceCandidate(message.candidate);else pc.pendingCandidates.push(message.candidate);}
  }
  function stopCallTracks(c){clearTimeout(c.timeout);clearTimeout(c.disconnectTimer);clearTimeout(c.resumeTimeout);clearInterval(c.clock);c.pc?.close();c.stream?.getTracks().forEach(t=>t.stop());}
  const terminalCalls=new Map();try{for(const [key,value]of JSON.parse(sessionStorage.getItem('kinnect-call-ends')||'[]'))if(value.until>Date.now())terminalCalls.set(key,value);}catch{}
  function saveTerminalCalls(){for(const [key,row]of terminalCalls)if(row.until<Date.now())terminalCalls.delete(key);try{sessionStorage.setItem('kinnect-call-ends',JSON.stringify([...terminalCalls].slice(-24)));}catch{}}
  function queueCallEnd(c){const payload=c.id?{type:c.incoming&&!c.accepted?'call-decline':'call-end',callId:c.id}:c.requestId?{type:'call-cancel',requestId:c.requestId}:null;if(!payload)return;const key=payload.callId||payload.requestId;terminalCalls.set(key,{owner:s.me?.id,until:Date.now()+60000,payload});saveTerminalCalls();try{socketSend(payload);}catch{}}
  function callWasEnded(id){saveTerminalCalls();return !!id&&[...terminalCalls.values()].some(row=>row.owner===s.me?.id&&(row.payload.callId===id||row.payload.requestId===id));}
  function flushCallEnds(){saveTerminalCalls();for(const row of terminalCalls.values())if(row.owner===s.me?.id&&!row.ack)try{socketSend(row.payload);}catch{}}
  async function finishCall(note='Cuộc gọi đã kết thúc.'){const c=media.call;if(!c)return;media.call=null;c.ended=true;c.reconnecting=false;stopRinging();stopDialing();stopReconnectTone();callCue('end');clearCandidateQueue();stopCallTracks(c);if(/kết nối|camera|mic/i.test(note))s.lastCallError='CALL-27B · '+note;toast(note);if(s.me){if(s.screen==='call')await go('inbox',c.person.id?{chat:c.person.id}:{});else render();}}
  async function prepareCall(c){
    if(!navigator.mediaDevices?.getUserMedia)throw Error('Trình duyệt chưa cho phép camera/mic. Mở Kinnect bằng Safari qua HTTPS.');
    let stream;try{stream=await navigator.mediaDevices.getUserMedia({audio:true,video:c.mode==='video'?{facingMode:{ideal:'user'},width:{ideal:640},height:{ideal:480},frameRate:{ideal:24,max:30}}:false});}catch(err){if(err.name!=='OverconstrainedError')throw err;stream=await navigator.mediaDevices.getUserMedia({audio:true,video:c.mode==='video'});}
    if(media.call!==c){stream.getTracks().forEach(t=>t.stop());return false;}c.stream=stream;return true;
  }
  async function connectCall(c){
    if(c.pc)return c.pc;
    c.pc=await newPeer(data=>socketSend({type:'call-signal',callId:c.id,...data}),c.stream,stream=>{if(media.call===c){c.remote=stream;attachMedia();syncCallDock();}});
    if(media.call!==c){c.pc.close();return;}
    const connected=()=>{if(media.call!==c)return;clearTimeout(c.timeout);clearTimeout(c.disconnectTimer);const changed=c.status!=='Đã kết nối';if(c.reconnecting||reconnectTimer){stopReconnectTone();callCue('connected');}c.reconnecting=false;c.status='Đã kết nối';c.connectedAt ||= Date.now();if(changed)render();c.clock ||= setInterval(()=>{const el=app.querySelector('[data-call-clock]');if(el){const sec=Math.floor((Date.now()-c.connectedAt)/1000);el.textContent=String(Math.floor(sec/60)).padStart(2,'0')+':'+String(sec%60).padStart(2,'0');}},1000);};
    const fail=()=>{if(media.call!==c)return;try{socketSend({type:'call-end',callId:c.id});}catch{}finishCall('Không kết nối được cuộc gọi. Hãy thử lại hoặc đổi mạng.');};
    const recover=async()=>{if(media.call!==c||c.recovering)return;if(c.retried){fail();return;}c.recovering=true;c.retried=true;c.status='Đang thử kết nối qua máy chủ chuyển tiếp…';render();try{const config=await api('/call-config');if(media.call!==c)return;const hasTurn=config.iceServers?.some(server=>(Array.isArray(server.urls)?server.urls:[server.urls]).some(url=>/^turns?:/.test(url)));c.pc.setConfiguration({...config,...(hasTurn?{iceTransportPolicy:'relay'}:{})});if(!c.incoming){await c.pc.setLocalDescription(await c.pc.createOffer({iceRestart:true}));socketSend({type:'call-signal',callId:c.id,description:c.pc.localDescription.toJSON()});}clearTimeout(c.timeout);c.timeout=setTimeout(fail,25000);}catch{fail();}finally{c.recovering=false;}};
    c.pc.onconnectionstatechange=()=>{if(media.call!==c)return;if(c.pc.connectionState==='connected')connected();if(c.pc.connectionState==='failed')recover();};
    c.pc.oniceconnectionstatechange=()=>{if(media.call!==c)return;const state=c.pc.iceConnectionState;if(state==='connected'||state==='completed')connected();else if(state==='failed')recover();else if(state==='disconnected'){c.reconnecting=true;c.status='Đang kết nối lại…';startReconnectTone();render();clearTimeout(c.disconnectTimer);c.disconnectTimer=setTimeout(recover,5000);}};
    c.timeout=setTimeout(recover,18000);return c.pc;
  }
  async function startCall(mode){
    if(media.call||media.room)throw Error('Kết thúc phiên hiện tại trước khi gọi.');
    const u=community.chat;if(!u||u.isGroup)return;
    s.lastCallError='';const c=media.call={person:u,mode,incoming:false,id:'',requestId:crypto.randomUUID(),status:'Đang chuẩn bị…',accepted:false};await go('call');
    try{await ensureSocket();if(!await prepareCall(c))return;socketSend({type:'call-start',to:u.id,mode,requestId:c.requestId});c.status='Đang gọi…';startDialing();render();}catch(err){if(media.call===c)await finishCall(err.message);}
  }
  function callStageScreen(){const c=media.call;if(!c)return emptyState('phone','Không có cuộc gọi','Mở cuộc trò chuyện để bắt đầu gọi.');return `<section class="v2-call-stage"><video data-call-remote autoplay playsinline></video>${c.mode==='video'?'<video data-call-local autoplay playsinline muted></video>':''}<div class="v2-call-identity">${av(c.person)}<h1>${esc(c.person.name)}</h1><p role="status">${esc(c.status)}</p><small class="v2-call-build">CALL-27B</small><time data-call-clock></time></div><div class="v2-call-controls">${c.incoming&&!c.accepted?btn(c.answering?'Đang chuẩn bị…':'Trả lời','phone','call-answer','primary').replace('type="button"','type="button"'+(c.answering?' disabled':'')):btn(c.stream?.getAudioTracks()[0]?.enabled===false?'Bật mic':'Tắt mic','mic','call-mic','secondary')+(c.mode==='video'?btn(c.stream?.getVideoTracks()[0]?.enabled===false?'Bật camera':'Tắt camera','video','call-camera','secondary'):'')}${c.playbackBlocked?btn('Bật âm thanh cuộc gọi','volume-2','call-play','secondary'):''}${c.accepted?btn('Âm thanh','volume-2','call-output','secondary'):''}${btn(c.incoming&&!c.accepted?'Từ chối':'Kết thúc','phone-off','call-end','danger-action')}</div></section>`;}
  function callScreen(){const c=media.call;if(!c)return callStageScreen();return head(c.mode==='audio'?'Cuộc gọi thoại':'Cuộc gọi video','Kết nối gần hơn, trò chuyện thoải mái hơn.')+'<div class="stage-cols approved-call"><div>'+callStageScreen()+'</div><aside class="panel details approved-device-panel"><h2>Thiết bị cuộc gọi</h2>'+callDeviceField('audioinput','Micro')+callDeviceField('audiooutput','Loa')+(c.mode==='video'?callDeviceField('videoinput','Camera cuộc gọi'):'')+'<hr><p class="body-copy">Chọn thiết bị khi trình duyệt hỗ trợ. Trạng thái kết nối luôn hiển thị trong cuộc gọi.</p></aside></div>';}
  const approvedDevices={list:[]};
  function callDeviceField(kind,label){const track=kind==='audioinput'?media.call?.stream?.getAudioTracks()[0]:media.call?.stream?.getVideoTracks()[0],current=kind==='audiooutput'?approvedDevices.output:track?.getSettings().deviceId;return '<label class="field">'+label+'<select data-approved-device="'+kind+'" aria-label="'+label+'"><option value="">'+(kind==='audiooutput'?'Loa mặc định':kind==='audioinput'?'Micro mặc định':'Camera mặc định')+'</option>'+approvedDevices.list.filter(d=>d.kind===kind).map((d,i)=>'<option value="'+esc(d.deviceId)+'" '+(d.deviceId===current?'selected':'')+'>'+esc(d.label||label+' '+(i+1))+'</option>').join('')+'</select></label>';}
  async function refreshApprovedDevices(){if(!media.call||!navigator.mediaDevices?.enumerateDevices)return;try{approvedDevices.list=await navigator.mediaDevices.enumerateDevices();}catch{} }
  async function changeApprovedDevice(kind,id){const c=media.call;if(!c?.stream||!id)return;if(kind==='audiooutput'){const video=app.querySelector('[data-call-remote]');if(!video?.setSinkId){toast('Trình duyệt này dùng đầu ra âm thanh do thiết bị chọn.');render();return;}await video.setSinkId(id);approvedDevices.output=id;return;}if(!c.pc){toast('Hãy nhận cuộc gọi trước khi chọn thiết bị.');render();return;}const stream=await navigator.mediaDevices.getUserMedia(kind==='audioinput'?{audio:{deviceId:{exact:id}},video:false}:{audio:false,video:{deviceId:{exact:id}}});if(media.call!==c){stream.getTracks().forEach(t=>t.stop());return;}const track=stream.getTracks()[0],old=kind==='audioinput'?c.stream.getAudioTracks()[0]:c.stream.getVideoTracks()[0],sender=c.pc.getSenders().find(t=>t.track?.kind===track.kind);try{if(sender)await sender.replaceTrack(track);if(old){track.enabled=old.enabled;c.stream.removeTrack(old);old.stop();}c.stream.addTrack(track);await refreshApprovedDevices();render();}catch(err){track.stop();throw err;}}
  async function leaveLive(send=true){if(send)try{socketSend({type:'leave'});}catch{}s.liveQuick=null;media.room=null;media.liveJoining='';media.liveRole='';media.remote=null;media.liveStage=null;media.liveTray='';media.guestRequested=false;media.giftRanking=null;closeLiveDialog();media.guestStream?.getTracks().forEach(t=>t.stop());media.guestStream=null;media.liveStreams=new Map();for(const pc of media.peers.values())pc.close();media.peers.clear();media.liveMessages=[];media.liveDraft='';stopCapture();}
  function liveQuickCard(){const q=s.liveQuick;if(!q)return '';const u=q.data?.user;return '<div class="live-quick-overlay"><button type="button" class="live-quick-backdrop" data-do="live-quick-close" aria-label="Đóng xem nhanh"></button><section class="live-quick-card" role="dialog" aria-modal="true" aria-label="Thông tin tài khoản"><div class="live-quick-grip"></div><div class="live-quick-top"><h2>Thông tin tài khoản</h2>'+btn('Đóng xem nhanh','x','live-quick-close','icon')+'</div>'+(u?'<div class="live-quick-identity">'+av(u)+'<h3>'+esc(u.name)+'</h3><small>@'+esc(u.username)+'</small></div><div class="live-quick-stats">'+[[q.data.followers,'Người theo dõi'],[q.data.following,'Đang theo dõi'],[q.data.posts,'Bài viết']].map(([n,label])=>'<div><strong>'+Number(n||0).toLocaleString('vi-VN')+'</strong><span>'+label+'</span></div>').join('')+'</div>'+(u.bio?'<p class="live-quick-bio">'+esc(u.bio)+'</p>':'')+'<div class="live-quick-interests">'+(u.interests||[]).slice(0,6).map(i=>'<span>'+esc(i)+'</span>').join('')+'</div><div class="live-quick-actions">'+(u.id!==s.me.id?btn(u.following?'Huỷ theo dõi':'Theo dõi',u.following?'user-check':'user-plus','live-quick-follow','secondary',u.id):'')+btn('Xem chi tiết tài khoản','arrow-up-right','live-quick-detail','primary',u.id)+'</div>':q.error?'<p role="alert" class="body-copy">'+esc(q.error)+'</p>':loading('Đang tải thông tin…'))+'</section></div>';}
  function liveMessageRow(m){return '<p>'+ (m.senderId?'<button type="button" class="live-comment-profile" data-do="live-quick-open" data-value="'+esc(m.senderId)+'" aria-label="Xem nhanh '+esc(m.name)+'">'+esc(m.name)+'</button>':'<b>'+esc(m.name)+'</b>')+' '+esc(m.text)+'</p>';}
  function liveChat(){return '<div class="v2-live-chat"><div class="v2-live-chat-log" role="log" aria-live="polite">'+media.liveMessages.slice(-200).map(liveMessageRow).join('')+'</div><form data-live-chat class="v2-chat-compose"><input name="message" aria-label="Bình luận live" maxlength="500" value="'+esc(media.liveDraft||'')+'" placeholder="Nói điều gì đó…"><button type="submit" class="icon" aria-label="Gửi bình luận live">'+ic('send-horizontal')+'</button></form></div>';}
  const rankLiveRooms=rooms=>(rooms||[]).slice().sort((a,b)=>Number(b.viewers||0)-Number(a.viewers||0)||Number(b.started||0)-Number(a.started||0)||a.id.localeCompare(b.id));
  async function enterTopLive(preferred){if(media.room||media.liveJoining||media.call)return;const next=preferred?{id:preferred}:media.rooms[0];if(!next)return;media.liveJoining=next.id;try{await ensureSocket();socketSend({type:'join',room:next.id,multiGuest:true});}catch(err){media.liveJoining='';throw err;}}
  function liveDirectory(){return '<section class="live-idle">'+(media.liveJoining?loading('Đang mở buổi live…'):emptyState('radio','Chưa có buổi live','Quay lại sau để xem những buổi trò chuyện mới.')+btn('Làm mới','rotate-ccw','live-refresh','secondary'))+'</section>';}

  function liveAudienceRow(){return (media.liveAudience||[]).map(u=>'<button type="button" data-do="live-quick-open" data-value="'+esc(u.id)+'" aria-label="'+esc(u.name)+'">'+av(u)+'</button>').join('');}
  function liveReaction(kind,name){const layer=app.querySelector('.live-reactions');if(!layer||layer.children.length>24)return;const el=document.createElement('span');el.className='live-floating-reaction';el.textContent=({heart:'♥',rose:'🌹',star:'⭐',crown:'👑'})[kind]||'♥';el.style.left=(65+Math.random()*23)+'%';layer.append(el);el.addEventListener('animationend',()=>el.remove(),{once:true});setTimeout(()=>el.remove(),2600);if(kind!=='heart')toast(name+' đã gửi '+el.textContent);}
  function liveGifts(){const d=document.createElement('dialog');d.className='kn-feature-sheet live-gift-sheet';d.innerHTML='<div class="sheet-head"><h2>Quà tặng miễn phí</h2><button aria-label="Đóng">'+ic('x')+'</button></div><p>Gửi một chút yêu thương đến buổi live.</p><div class="live-gift-options">'+[['rose','🌹','Hoa hồng'],['star','⭐','Ngôi sao'],['crown','👑','Vương miện']].map(([k,e,n])=>'<button data-kind="'+k+'"><span>'+e+'</span>'+n+'<small>Miễn phí</small></button>').join('')+'</div>';d.querySelector('.sheet-head button').onclick=()=>d.close();d.querySelectorAll('[data-kind]').forEach(b=>b.onclick=()=>{socketSend({type:'live-reaction',kind:b.dataset.kind});d.close();});d.addEventListener('close',()=>d.remove(),{once:true});document.body.append(d);d.showModal();}

  async function flipLiveCamera(){if(media.liveRole!=='host'||!media.fx||media.flippingLive)return;media.flippingLive=true;let raw,fx;try{const facing=media.facing==='user'?'environment':'user';raw=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:facing},width:{ideal:1280},height:{ideal:960}},audio:false});const combined=new MediaStream([...media.stream.getAudioTracks(),...raw.getVideoTracks()]);fx=media.cameraModule.createEffects(combined,{portrait:true,fit:'contain'});fx.set({...media.fx.state,mirror:facing==='user',fit:'contain'});const old=media.fx;try{await Promise.all([...media.peers.values()].map(pc=>{const sender=pc.getSenders().find(s=>s.track?.kind==='video');return sender?.replaceTrack(fx.stream.getVideoTracks()[0]);}));}catch(error){await Promise.allSettled([...media.peers.values()].map(pc=>pc.getSenders().find(s=>s.track?.kind==='video')?.replaceTrack(old.stream.getVideoTracks()[0])));throw error;}media.stream.getVideoTracks().forEach(t=>t.stop());old.stop();media.stream=combined;media.fx=fx;media.facing=facing;attachMedia();}catch(error){fx?.stop();raw?.getTracks().forEach(t=>t.stop());throw error;}finally{media.flippingLive=false;}}
  const liveLocalStream=()=>media.liveRole==='host'?media.fx?.stream:media.guestStream;
  function liveTiles(){const stage=media.liveStage,people=stage?.participants||[{id:'host',name:media.room.host,userId:media.room.hostId,role:'host',mode:'video'}];return '<div class="live-board '+(people.length>1?'multi':'solo')+' layout-'+(stage?.layout||'panel')+'" data-count="'+people.length+'">'+people.map(p=>'<div class="live-tile" data-tile="'+esc(p.id)+'">'+(p.mode==='audio'?'<div class="live-audio-avatar">'+av({id:p.userId,name:p.name,avatar:p.avatar})+ic('mic')+'</div>':'<video '+(p.role==='host'?'data-live-video ':'')+'data-live-peer="'+esc(p.id)+'" data-live-room="'+esc(media.room.id)+'" autoplay playsinline '+(p.id===stage?.selfId?'muted':'')+'></video>')+'<span class="live-tile-name">'+esc(p.name)+(p.id===stage?.selfId?' · Bạn':'')+'</span></div>').join('')+'</div>';}
  function liveHorizontalTray(){const tray=media.liveTray;if(!tray)return '';let body='';if(tray==='gifts')body=[['rose','🌹','Hoa hồng'],['star','⭐','Ngôi sao'],['crown','👑','Vương miện']].map(([kind,art,name])=>'<button type="button" data-do="live-free-gift" data-value="'+kind+'"><span class="live-gift-art">'+art+'</span><span>'+name+'</span><small>Miễn phí</small></button>').join('');else{const stream=liveLocalStream();if(media.liveRole!=='viewer'){body+=btn(stream?.getAudioTracks().some(t=>!t.enabled)?'Bật mic':'Tắt mic','mic','live-host-mic','')+btn(stream?.getVideoTracks().some(t=>!t.enabled)?'Bật camera':'Tắt camera','camera','live-host-camera','');if(media.liveRole==='host')body+=btn('Đổi camera','switch-camera','live-flip','')+btn('Hiệu ứng','sparkles','live-effects','');}if(media.liveRole==='host')body+=btn('Lưới','layout-grid','live-layout','','grid')+btn('Chủ phòng lớn','users-round','live-layout','','panel');else body+=btn('Báo cáo','flag','approved-live-report','')+btn('Chặn','shield-check','approved-live-block','')+btn('Âm thanh','volume-2','live-sound','');body+=btn('Chia sẻ','send','approved-share-live','');}return '<div class="live-horizontal-tray" aria-label="'+(tray==='gifts'?'Tặng quà':'Công cụ Live')+'">'+body+'</div>';}
  function liveStage(){const r=media.room,host=media.liveRole==='host',u={id:r.hostId,name:r.host||(host?s.me.name:'Chủ buổi live'),avatar:r.avatar||(host?s.me.avatar:null)};return '<section class="v2-live-stage live-immersive live-studio" data-live-room="'+esc(r.id)+'">'+liveTiles()+'<div class="live-stream-status" role="status">'+ic('radio')+'<span>Đang kết nối…</span></div><div class="v2-live-heading"><button type="button" class="live-host-chip" aria-label="Xem nhanh chủ live" data-do="live-quick-open" data-value="'+esc(r.hostId||s.me.id)+'">'+av(u)+'<div><strong>'+esc(u.name)+'</strong><small><span class="live-pill">LIVE</span></small></div></button><div class="live-audience-strip" aria-label="Người đang xem">'+liveAudienceRow()+'</div><button type="button" class="live-count" data-do="live-viewers" aria-label="Người đang xem">'+ic('eye')+'<span data-live-viewers>'+Number(r.viewers||0)+'</span></button>'+btn(host?'Kết thúc Live':'Rời Live','x','live-leave','icon')+'</div><div class="live-arrival" role="status" hidden></div><div class="live-reactions" aria-hidden="true"></div>'+(r.title?'<div class="live-stream-title">'+esc(r.title)+'</div>':'')+'<div class="live-side-actions">'+btn('Thả tim','heart','live-heart','')+btn('Chia sẻ','send','approved-share-live','')+'</div>'+liveChat()+'<div class="live-bottom-actions">'+btn(host?'Khách mời':'Lên Live','users-round','live-guests','')+btn('Tặng quà','gift','live-gifts','')+btn('Công cụ','sliders-horizontal','live-tools','')+'</div>'+liveHorizontalTray()+'</section>';}
  function closeLiveDialog(){document.querySelectorAll('dialog.live-guest-dialog').forEach(d=>d.close());}
  function liveDialog(title,content){closeLiveDialog();const d=document.createElement('dialog');d.className='kn-feature-sheet live-guest-dialog';d.innerHTML='<div class="sheet-head"><h2>'+esc(title)+'</h2><button type="button" aria-label="Đóng">'+ic('x')+'</button></div>'+content;d.querySelector('.sheet-head button').onclick=()=>d.close();d.addEventListener('close',()=>d.remove(),{once:true});document.body.append(d);d.showModal();return d;}
  function liveGuestManagement(){if(media.liveRole!=='host')return;const requests=(media.guestRequests||[]).filter(p=>p.expiresAt>Date.now()),users=media.guestUsers||[];const row=(u,request)=>'<div class="live-guest-row">'+av({id:u.userId,name:u.name,avatar:u.avatar})+'<span>'+esc(u.name)+'</span><button type="button" data-guest-action="'+(request?'approve':u.onStage?'remove':'invite')+'" data-peer="'+esc(u.id)+'">'+(request?'Duyệt':u.onStage?'Gỡ':'Mời')+'</button>'+(request?'<button type="button" data-guest-action="decline" data-peer="'+esc(u.id)+'" aria-label="Từ chối">'+ic('x')+'</button>':'')+'</div>';const d=liveDialog('Khách mời','<p>Mời người đang xem · Tối đa 3 khách</p><div class="live-guest-rows">'+requests.map(u=>row(u,true)).join('')+users.filter(u=>!requests.some(p=>p.id===u.id)).map(u=>row(u,false)).join('')+(!users.length&&!requests.length?'<p>Chưa có người xem để mời</p>':'')+'</div>');d.querySelectorAll('[data-guest-action]').forEach(b=>b.onclick=()=>{socketSend({type:'live-guest-'+b.dataset.guestAction,to:b.dataset.peer});d.close();});}
  function openLiveGuests(){if(media.liveRole==='host'){socketSend({type:'live-guest-list'});return;}if(media.liveRole==='guest'){const d=liveDialog('Bạn đang lên Live','<button type="button" data-leave-guest>Rời ghế khách</button>');d.querySelector('[data-leave-guest]').onclick=()=>{socketSend({type:'live-guest-leave'});d.close();};return;}const d=liveDialog(media.guestRequested?'Đang chờ chủ phòng duyệt':'Xin lên Live',media.guestRequested?'<button type="button" data-cancel-guest>Hủy yêu cầu</button>':'<p>Camera và micro chỉ bật sau khi bạn đồng ý lên Live.</p><div class="live-join-modes"><button type="button" data-guest-mode="video">'+ic('video')+'Video</button><button type="button" data-guest-mode="audio">'+ic('mic')+'Âm thanh</button></div>');d.querySelectorAll('[data-guest-mode]').forEach(b=>b.onclick=()=>{socketSend({type:'live-guest-request',mode:b.dataset.guestMode});d.close();});d.querySelector('[data-cancel-guest]')?.addEventListener('click',()=>{socketSend({type:'live-guest-cancel'});d.close();});}
  function liveInvitation(m){const d=liveDialog('Mời lên Live','<p>'+esc(m.from.name)+' mời bạn trò chuyện cùng.</p><div class="live-join-modes"><button type="button" data-guest-mode="video">'+ic('video')+'Video</button><button type="button" data-guest-mode="audio">'+ic('mic')+'Âm thanh</button></div><button type="button" data-decline-guest>Từ chối</button>');let answered=false;const reject=()=>{if(!answered&&media.room?.id===m.room){answered=true;socketSend({type:'live-guest-answer',token:m.token,accept:false});}};d.addEventListener('close',reject,{once:true});d.querySelector('[data-decline-guest]').onclick=()=>d.close();const expiry=setTimeout(()=>{d.close();},Math.max(0,m.expiresAt-Date.now()));d.addEventListener('close',()=>clearTimeout(expiry),{once:true});d.querySelectorAll('[data-guest-mode]').forEach(b=>b.onclick=async()=>{d.querySelectorAll('button').forEach(el=>el.disabled=true);let stream;try{stream=await navigator.mediaDevices.getUserMedia({audio:true,video:b.dataset.guestMode==='video'?{facingMode:'user',width:{ideal:640},height:{ideal:960}}:false});if(!d.open||media.room?.id!==m.room||Date.now()>m.expiresAt){stream.getTracks().forEach(t=>t.stop());return;}media.guestStream?.getTracks().forEach(t=>t.stop());media.guestStream=stream;answered=true;socketSend({type:'live-guest-answer',token:m.token,accept:true,mode:b.dataset.guestMode});d.close();}catch(error){stream?.getTracks().forEach(t=>t.stop());toast(cameraErrorMessage(error));d.querySelectorAll('button').forEach(el=>el.disabled=false);}});}
  async function applyLiveStage(m){if(media.room?.id!==m.room)return;if(media.liveStage?.revision===m.revision){media.liveStage=m;media.guestRequested=m.requested===true;render();return;}media.liveStage=m;media.liveRole=m.role;media.guestRequested=m.requested===true;if(m.role==='viewer'){media.guestStream?.getTracks().forEach(t=>t.stop());media.guestStream=null;}for(const pc of media.peers.values())pc.close();media.peers.clear();media.liveStreams=new Map();render();for(const link of m.peers){const pc=await newPeer(data=>socketSend({type:'signal',to:link.id,revision:m.revision,...data}),liveLocalStream(),stream=>{if(media.liveStage?.revision!==m.revision)return;media.liveStreams.set(link.id,stream);attachMedia();},true);if(media.room?.id!==m.room){pc.close();return;}media.peers.set(link.id,pc);if(link.offer){await pc.setLocalDescription(await pc.createOffer());socketSend({type:'signal',to:link.id,revision:m.revision,description:pc.localDescription.toJSON()});}}}
  function compactLiveScreen(){return media.room?liveStage():liveDirectory();}
  function liveScreen(){if(!media.room||s.device!=='pc')return compactLiveScreen();return '<div class="live-layout-shell"><div class="live-video-column">'+liveStage()+'</div><aside class="live-chat-panel"><div class="live-discussion-heading"><h2>Trò chuyện trực tiếp</h2><span class="live-dot"></span></div>'+liveChat()+'</aside></div>';}

  async function switchLive(direction){if(s.liveQuick)return;if(media.liveRole!=='viewer'||!media.room||Date.now()-(media.liveSwipeAt||0)<900)return;const current=media.rooms.findIndex(r=>r.id===media.room.id),next=media.rooms[current+direction];if(!next){toast(direction>0?'Bạn đã xem đến buổi live cuối.':'Đây là buổi live đầu tiên.');return;}media.liveSwipeAt=Date.now();await leaveLive();await enterTopLive(next.id);}
  function enterMediaStage(stage,direction){if(!stage)return;stage.style.transform='';stage.style.opacity='';if(!matchMedia('(prefers-reduced-motion: reduce)').matches)stage.animate([{transform:'translateY('+(direction*48)+'px)',opacity:.25},{transform:'translateY(0)',opacity:1}],{duration:180,easing:'ease-out'});}
  function bindMediaSwipe(stage,step,enabled,tap,selector){let start=null,drag=false,suppress=false;const settle=()=>{stage.style.transition='transform 180ms ease-out, opacity 180ms ease-out';stage.style.transform='';stage.style.opacity='';};const advance=async direction=>{if(!enabled()||document.querySelector('dialog[open],.video-comments-sheet,.kn-edit')||Date.now()<(media.swipeBusyUntil||0)){settle();return;}media.swipeBusyUntil=Date.now()+320;stage.style.transition='transform 120ms ease-in,opacity 120ms ease-in';stage.style.transform='translateY('+(-direction*82)+'px)';stage.style.opacity='.2';await new Promise(r=>setTimeout(r,120));try{await step(direction);const next=app.querySelector(selector);if(next)enterMediaStage(next,direction);}catch(error){toast(error.message);settle();}};
    stage.addEventListener('click',e=>{if(suppress){suppress=false;e.preventDefault();e.stopPropagation();}},{capture:true});
    stage.addEventListener('pointerdown',e=>{if(!enabled()||document.querySelector('dialog[open],.video-comments-sheet,.kn-edit')||e.target.closest('button:not(.video-play-toggle),input,textarea,select,a,form,.v2-live-chat-log,.live-horizontal-tray'))return;start={x:e.clientX,y:e.clientY,lastY:e.clientY,time:performance.now(),lastTime:performance.now()};drag=false;});
    stage.addEventListener('pointermove',e=>{if(!start)return;const dy=e.clientY-start.y,dx=e.clientX-start.x;if(!drag&&Math.abs(dy)>10&&Math.abs(dy)>Math.abs(dx)*1.35){drag=true;stage.setPointerCapture?.(e.pointerId);}if(drag){e.preventDefault();stage.style.transition='none';stage.style.transform='translateY('+(Math.tanh(dy/170)*76)+'px)';stage.style.opacity=1-Math.min(.12,Math.abs(dy)/1800);}start.lastY=e.clientY;start.lastTime=performance.now();});
    stage.addEventListener('pointerup',e=>{if(!start)return;const dy=e.clientY-start.y,dx=e.clientX-start.x,elapsed=performance.now()-start.time,speed=dy/Math.max(1,elapsed)*1000,was=drag;start=null;drag=false;if(was&&(Math.abs(dy)>64||Math.abs(dy)>24&&Math.abs(speed)>700)){suppress=true;advance(dy<0?1:-1);return;}settle();if(!was&&Math.abs(dx)<12&&Math.abs(dy)<12&&!e.target.closest('button'))tap?.();});
    stage.addEventListener('pointercancel',()=>{start=null;drag=false;settle();});stage.addEventListener('wheel',e=>{if(e.target.closest('form,.v2-live-chat-log,.live-horizontal-tray')||Math.abs(e.deltaY)<30)return;e.preventDefault();advance(e.deltaY>0?1:-1);},{passive:false});
  }
  function bindLiveStage(){const stage=app.querySelector('.live-immersive');if(stage)bindMediaSwipe(stage,direction=>switchLive(direction),()=>media.liveRole==='viewer'&&!s.liveQuick,null,'.live-immersive');}

  const aiDrafts=new Map();
  function paintAIStream(){
    const log=app.querySelector('.v2-message-history');
    if(!log)return;
    const bottom=log.scrollHeight-log.scrollTop-log.clientHeight<64;
    log.querySelectorAll('[data-ai-stream]').forEach(el=>el.remove());
    for(const [id,m] of aiDrafts){if(community.chat?.isGroup||community.chat?.id!==m.sender)continue;
      const bubble=document.createElement('div');bubble.className='v2-bubble incoming';bubble.dataset.aiStream=id;
      const text=document.createElement('p');text.textContent=m.body;bubble.append(text);log.append(bubble);if(bottom)log.scrollTop=log.scrollHeight;
    }
  }
  async function handleMediaSignal(m){
    if(String(m.type||'').startsWith('group-call-')){const mod=await ensurePlusModule();await mod.handleGroupCallSignal(m,{api,socketSend,toast,render});return;}
    if(m.type==='ai-stream'){if(m.done){aiDrafts.delete(m.id);paintAIStream();if(s.screen==='inbox'&&!community.chat?.isGroup&&community.chat?.id===m.sender){await loadChat();render();}}else{aiDrafts.set(m.id,m);paintAIStream();}return;}
    if(m.type==='welcome'){flushCallEnds();media.callResumeSupported=m.callResume===true;if(media.call?.accepted&&media.call.reconnecting)socketSend({type:'call-resume',callId:media.call.id});sendVisibility();return;}
    if(m.type==='call-reconnecting'&&media.call?.id===m.callId){startReconnectTone();media.call.status='Đang chờ thiết bị bên kia nối lại…';render();return;}
    if(m.type==='call-resumed'&&media.call?.id===m.callId){const c=media.call;clearTimeout(c.resumeTimeout);c.reconnecting=false;c.status='Đang khôi phục cuộc gọi…';render();if(c.pc&&!c.incoming){await c.pc.setLocalDescription(await c.pc.createOffer({iceRestart:true}));socketSend({type:'call-signal',callId:c.id,description:c.pc.localDescription.toJSON()});}return;}

    if(m.type==='notification'||m.type==='notifications-changed'||m.type==='conversations-changed'){refreshCounts();if(s.screen==='inbox'){await loadInbox();if(community.chat)await loadChat();render();}return;}
    if(m.type==='live-stage'){await applyLiveStage(m);return;}
    if(m.type==='live-guest-invitation'&&media.room?.id===m.room){liveInvitation(m);return;}
    if(m.type==='live-guest-state'&&media.room?.id===m.room){media.guestRequests=m.requests||[];return;}
    if(m.type==='live-guest-list'&&media.room?.id===m.room){media.guestUsers=m.users||[];liveGuestManagement();return;}
    if(['live-guest-requested','live-guest-cancelled','live-guest-declined'].includes(m.type)){media.guestRequested=m.type==='live-guest-requested';toast(media.guestRequested?'Đã gửi yêu cầu lên Live':m.type==='live-guest-declined'?'Chủ phòng đã từ chối yêu cầu':'Đã hủy yêu cầu');return;}
    if(m.type==='live-guest-error'){if(media.liveRole!=='guest'){media.guestStream?.getTracks().forEach(t=>t.stop());media.guestStream=null;}toast(m.message);return;}
    if(m.type==='viewers'&&media.room){document.querySelector('dialog.live-viewer-list')?.close();const d=document.createElement('dialog');d.className='kn-feature-sheet live-viewer-list';d.setAttribute('aria-label','Người đang xem livestream');d.innerHTML='<div class="sheet-head"><h2>Người đang xem</h2><button aria-label="Đóng">'+ic('x')+'</button></div>';d.querySelector('button').onclick=()=>d.close();for(const u of m.users||[]){const b=document.createElement('button');b.className='native-sheet-option';b.innerHTML=av(u)+'<span>'+esc(u.name)+'</span>';b.onclick=()=>{d.close();go('profile',{user:u.id});};d.append(b);}if(!m.users?.length){const p=document.createElement('p');p.textContent='Chưa có người xem.';d.append(p);}document.body.append(d);d.addEventListener('close',()=>d.remove(),{once:true});d.showModal();return;}
    if(m.type==='count'&&media.room){if(m.room&&m.room!==media.room.id)return;media.room.viewers=m.viewers;media.liveAudience=m.users||[];app.querySelectorAll('[data-live-viewers]').forEach(el=>el.textContent=Number(m.viewers||0));const strip=app.querySelector('.live-audience-strip');if(strip)strip.innerHTML=liveAudienceRow();return;}
    if(m.type==='viewer-joined'&&media.room?.id===m.room&&m.user){media.liveArrival={text:m.user.name+' vừa tham gia',until:Date.now()+3500};const el=app.querySelector('.live-arrival');if(el){el.textContent=m.user.name+' vừa tham gia';el.hidden=false;clearTimeout(media.arrivalTimer);media.arrivalTimer=setTimeout(()=>{const current=app.querySelector('.live-arrival');if(current)current.hidden=true;},3500);}return;}
    if(m.type==='live-reaction'&&media.room?.id===m.room){liveReaction(m.kind,m.name);return;}
    if(m.type==='live-gift-receipt'&&media.room?.id===m.room){if(m.catalog)media.giftCatalog=m.catalog;if(Number.isFinite(m.balance)){media.giftBalance=m.balance;if(s.wallet){s.wallet.trialCoins=s.wallet.giftedCoins=m.balance;s.wallet.coins=m.balance+Number(s.wallet.purchasedCoins||0);}}return;}
    if(m.type==='live-gift-ranking'&&media.room?.id===m.room){media.giftRanking=m;media.room.giftTotalCoins=m.totalCoins||0;media.room.giftTotalCount=m.totalGifts||0;return;}
    if(m.type==='live-gift-error'){if(m.catalog)media.giftCatalog=m.catalog;if(Number.isFinite(m.balance)){media.giftBalance=m.balance;if(s.wallet){s.wallet.trialCoins=s.wallet.giftedCoins=m.balance;s.wallet.coins=m.balance+Number(s.wallet.purchasedCoins||0);}}toast(m.message||'Không thể gửi quà.');render();return;}
    if(m.type==='rooms'){media.rooms=rankLiveRooms(m.rooms);if(media.room){const listing=media.rooms.find(r=>r.id===media.room.id);if(listing)Object.assign(media.room,listing);}if(s.screen==='live'){if(!media.room&&!media.liveJoining)await enterTopLive(s.params.room);render();}return;}
    if(m.type==='call-incoming'&&callWasEnded(m.callId)){flushCallEnds();return;}
    if(m.type==='call-ended'){for(const row of terminalCalls.values())if(row.payload.callId===m.callId||m.requestId&&row.payload.requestId===m.requestId)row.ack=true;saveTerminalCalls();}
    if(m.type==='call-incoming'){if(!pushOn()&&document.hidden&&'Notification' in window&&Notification.permission==='granted'){const notification=new Notification(m.mode==='audio'?'Cuộc gọi thoại đến':'Cuộc gọi video đến',{body:m.from.name,icon:'/kinnect-logo-v106.svg',tag:'kinnect-call'});notification.onclick=()=>{window.focus();notification.close();};}if(media.call||media.room){socketSend({type:'call-decline',callId:m.callId});return;}media.call={person:m.from,id:m.callId,mode:m.mode,incoming:true,accepted:false,status:m.mode==='audio'?'Cuộc gọi thoại đến':'Cuộc gọi video đến'};await go('call');if(media.autoAnswer===m.callId){media.autoAnswer=null;app.querySelector('[data-do="call-answer"]')?.click();}else startRinging();return;}
    if(m.type==='call-ringing'){const c=media.call;if(!c||c.ended||m.requestId!==c.requestId){queueCallEnd({id:m.callId,incoming:false,accepted:false});return;}c.id=m.callId;return;}
    if(m.type==='call-ended'){const c=media.call;if(c&&(m.callId===c.id||m.requestId===c.requestId)){await finishCall(({busy:'Người này đang bận.',unavailable:'Người này chưa trực tuyến.',missed:'Không có trả lời.',declined:'Cuộc gọi bị từ chối.',disconnected:'Thiết bị bên kia mất kết nối máy chủ.',answered_elsewhere:'Cuộc gọi đã được nhận trên thiết bị khác.'})[m.reason]||'Cuộc gọi đã kết thúc.');}return;}
    if(m.type==='call-accepted'){stopDialing();callCue('connected');const c=media.call;if(!c||c.id!==m.callId)return;c.accepted=true;c.status='Đang kết nối…';const pc=await connectCall(c);if(pc&&!c.incoming){await pc.setLocalDescription(await pc.createOffer());socketSend({type:'call-signal',callId:c.id,description:pc.localDescription.toJSON()});}render();return;}
    if(m.type==='call-signal'){const c=media.call;if(!c||c.id!==m.callId||!c.stream)return;const pc=await connectCall(c);if(pc){await peerSignal(pc,m,data=>socketSend({type:'call-signal',callId:c.id,...data}));if(['connected','completed'].includes(pc.iceConnectionState))pc.oniceconnectionstatechange?.();}return;}
    if(m.type==='joined'){media.liveAudience=[];media.liveJoining='';delete s.params.room;media.room={...(media.rooms.find(r=>r.id===m.room.id)||{}),...m.room,hostId:m.hostUserId||(m.role==='host'?s.me.id:undefined)};media.liveRole=m.role;media.liveMessages=Array.isArray(m.history)?m.history.filter(item=>!item.roomId||item.roomId===m.room.id).slice(-200):[];s.screen='live';render();return;}
    if(m.type==='peer'&&(media.liveRole==='host'||media.liveRole==='guest')){
      const pc=await newPeer(data=>socketSend({type:'signal',to:m.id,...data}),liveLocalStream(),()=>{});media.peers.set(m.id,pc);await pc.setLocalDescription(await pc.createOffer());socketSend({type:'signal',to:m.id,description:pc.localDescription.toJSON()});return;
    }
    if(m.type==='signal'&&media.room){if(media.liveStage&&m.revision&&m.revision!==media.liveStage.revision)return;let pc=media.peers.get(m.from);if(!pc){pc=await newPeer(data=>socketSend({type:'signal',to:m.from,revision:media.liveStage?.revision,...data}),liveLocalStream(),stream=>{media.liveStreams||=new Map();media.liveStreams.set(m.from,stream);media.remote=stream;attachMedia();});media.peers.set(m.from,pc);}await peerSignal(pc,m,data=>socketSend({type:'signal',to:m.from,revision:media.liveStage?.revision,...data}));return;}
    if(m.type==='peer-left'){media.peers.get(m.id)?.close();media.peers.delete(m.id);return;}
    if(m.type==='chat'&&media.room){if(m.roomId&&m.roomId!==media.room.id)return;if(m.id&&media.liveMessages.some(item=>item.id===m.id))return;media.liveMessages.push(m);if(media.liveMessages.length>200)media.liveMessages.splice(0,media.liveMessages.length-200);const log=app.querySelector('.v2-live-chat-log');if(log){const template=document.createElement('template');template.innerHTML=liveMessageRow(m);log.append(template.content);while(log.children.length>200)log.firstChild.remove();log.scrollTop=log.scrollHeight;}return;}
    if(m.type==='ended'){const ended=media.room?.id;await leaveLive(false);media.rooms=media.rooms.filter(r=>r.id!==ended);toast('Buổi live đã kết thúc.');await enterTopLive();render();return;}
    if(m.type==='error'){if(media.liveJoining){const failed=media.liveJoining;media.liveJoining='';media.rooms=media.rooms.filter(r=>r.id!==failed);await enterTopLive();}toast(m.message);render();}
  }
  async function realtimeAction(a,v){switch(a){
    case 'call-audio':await startCall('audio');break;
    case 'call-video':await startCall('video');break;
    case 'call-play':{const video=app.querySelector('[data-call-remote]');if(video){await video.play();if(media.call)media.call.playbackBlocked=false;}break;}
    case 'call-answer':{stopRinging();const c=media.call;if(!c||c.accepted||c.answering)return;c.answering=true;c.status='Đang mở camera và mic…';render();try{if(!await prepareCall(c))return;if(!await connectCall(c))return;if(media.call!==c)return;c.accepted=true;c.status='Đang kết nối…';socketSend({type:'call-accept',callId:c.id});render();}catch(err){if(media.call!==c)return;stopCallTracks(c);c.pc=null;c.stream=null;c.accepted=false;const errors={NotAllowedError:'Chưa được cấp quyền camera/mic. Cho phép trong cài đặt Safari rồi bấm nhận lại.',NotReadableError:'Camera hoặc mic đang bận. Đóng ứng dụng đang dùng camera rồi nhận lại.',NotFoundError:'Không tìm thấy camera hoặc mic.'};c.status=errors[err.name]||('Chưa nhận được cuộc gọi: '+err.message);render();}finally{if(media.call===c){c.answering=false;render();}}break;}
    case 'call-output':{const video=app.querySelector('[data-call-remote]');if(navigator.mediaDevices?.selectAudioOutput&&video?.setSinkId){const device=await navigator.mediaDevices.selectAudioOutput();await video.setSinkId(device.deviceId);}else toast('Đổi loa hoặc tai nghe bằng bảng âm thanh của thiết bị.');render();break;}
    case 'call-end':{const c=media.call;if(c){c.ended=true;c.reconnecting=false;queueCallEnd(c);}await finishCall();break;}
    case 'call-mic':case 'call-camera':{const tracks=a==='call-mic'?media.call?.stream?.getAudioTracks():media.call?.stream?.getVideoTracks();if(tracks?.length)tracks.forEach(t=>t.enabled=!t.enabled);render();break;}
    case 'live-join':if(media.call)throw Error('Kết thúc cuộc gọi trước khi xem live.');await enterTopLive(v);break;
    case 'approved-live-report':if(media.room?.hostId){s.reportTarget={type:'user',id:media.room.hostId};s.reportReason='[Livestream '+media.room.id+'] ';render();}break;
    case 'approved-live-block':if(media.room?.hostId&&await knConfirm('Chặn người phát và rời buổi live này?')){await api('/users/'+media.room.hostId+'/block','POST',{});await leaveLive();await go('discover');}break;
    case 'media-live-start':await api('/me/content-consent','POST',{});if(!media.fx)throw Error('Camera chưa sẵn sàng.');await ensureSocket();media.fx.set({fit:'contain'});socketSend({type:'create',title:media.liveTitle.trim(),multiGuest:true});break;
    case 'live-leave':if(media.liveRole==='host'&&!(await knConfirm('Kết thúc buổi live?')))break;{const host=media.liveRole==='host';await leaveLive();await go(host?'live':'feed');}break;
    default:return false;
  }return true;}
  window.addEventListener('pagehide',()=>{plusModule?.leaveGroupCall?.(true);stopCapture();if(media.call)stopCallTracks(media.call);media.socket?.close();});

  const identityChoices={gender:['Nam','Nữ','Nam chuyển giới','Nữ chuyển giới','Phi nhị nguyên','Linh hoạt giới','Vô giới'],orientation:['Dị tính','Gay / Đồng tính nam','Lesbian / Đồng tính nữ','Song tính / Bisexual','Toàn tính / Pansexual','Vô tính / Asexual','Đang tìm hiểu'],pronouns:['Anh','Chị','Em','Bạn','Họ / They'],relationshipRole:['Độc thân','Đang tìm hiểu','Đang trong mối quan hệ','Đã kết hôn','Mối quan hệ mở'],lookingFor:['Kết bạn','Trò chuyện','Hẹn hò','Mối quan hệ nghiêm túc','Cùng sở thích']};
  const interestChoices=['Nhiếp ảnh','Du lịch','Âm nhạc','Đọc sách','Thể thao','Ẩm thực','Phim ảnh','Công nghệ','Nghệ thuật','Thiên nhiên','Game','Thú cưng'];
  function profileField(key,label,type='text'){
    const e=s.editProfile,visKey=key==='birthDate'?'age':key;
    const toggle=key==='name'?'':`<label class="profile-field-visibility"><input type="checkbox" data-edit-visible="${visKey}" aria-label="${key==='birthDate'?'Hiển thị tuổi trên hồ sơ':'Công khai '+label.toLowerCase()}" ${e.visibility[visKey]!==false?'checked':''}>${ic(e.visibility[visKey]!==false?'globe':'lock-keyhole')}</label>`;
    if(key==='lookingFor'){const chosen=(e.lookingFor||'').split(',').map(x=>x.trim()).filter(Boolean),custom=chosen.filter(x=>!identityChoices.lookingFor.includes(x));return '<div class="profile-edit-field"><div class="profile-field-title"><label>'+label+'</label>'+toggle+'</div><div class="profile-interest-options">'+identityChoices.lookingFor.map(value=>'<label><input type="checkbox" data-approved-intent="'+esc(value)+'" '+(chosen.includes(value)?'checked':'')+'>'+esc(value)+'</label>').join('')+'</div><label class="field">Tự mô tả<input data-approved-intent-custom aria-label="Tự mô tả mong muốn kết nối" maxlength="60" value="'+esc(custom.join(', '))+'"></label></div>';}
    let control=type==='textarea'?`<textarea data-edit="${key}" aria-label="${label}" maxlength="500">${esc(e[key]||'')}</textarea>`:type==='select'?`<select data-edit-select="${key}" aria-label="${label}"><option value="">Không muốn tiết lộ</option>${identityChoices[key].map(value=>`<option ${e[key]===value?'selected':''}>${esc(value)}</option>`).join('')}<option value="__custom__" ${e.custom[key]?'selected':''}>Tự mô tả</option></select>${e.custom[key]?`<input data-edit="${key}" aria-label="Tự mô tả ${label.toLowerCase()}" value="${esc(e[key]||'')}" maxlength="60" placeholder="Nhập mô tả của bạn">`:''}`:`<input type="${type}" data-edit="${key}" aria-label="${label}" value="${esc(e[key]||'')}" ${type==='date'?'max="'+new Date().toISOString().slice(0,10)+'"':'maxlength="100"'}>`;
    return `<div class="profile-edit-field"><div class="profile-field-title"><label>${label}</label>${toggle}</div>${control}${key==='birthDate'?'<small>Ngày sinh đầy đủ chỉ bạn xem được. Bật biểu tượng quả địa cầu để hiển thị tuổi.</small>':''}</div>`;
  }
  function profileEditorScreen(){const e=s.editProfile;if(!e)return emptyState('user-round','Chưa mở chỉnh sửa hồ sơ','Mở từ trang cá nhân của bạn.');return `<section class="profile-edit-page"><div class="profile-edit-toolbar">${btn('Quay lại hồ sơ','arrow-left','edit-close','icon')}<h1>Chỉnh sửa hồ sơ</h1>${btn('Xem trước hồ sơ công khai','eye','profile-preview','icon')}${btn(e.busy?'Đang lưu…':'Lưu','check','edit-save','primary')}</div><p class="profile-edit-note">Chọn thông tin bạn muốn chia sẻ. Tắt quả địa cầu để ẩn từng mục.</p><details class="profile-edit-section" open><summary>Thông tin cơ bản</summary><div class="profile-edit-section-body"><div class="row"><label class="kn-file-btn">${ic('camera')}Ảnh đại diện<input type="file" accept="image/png,image/jpeg,image/webp" data-avatar-file hidden></label><label class="kn-file-btn">${ic('image')}Ảnh bìa<input type="file" accept="image/png,image/jpeg,image/webp" data-cover-file hidden></label></div>${profileField('name','Tên hiển thị')}<small>Tên người dùng · @${esc(s.me.username)}</small>${profileField('birthDate','Ngày tháng năm sinh','date')}</div></details><details class="profile-edit-section" open><summary>Giới thiệu và sở thích</summary><div class="profile-edit-section-body">${profileField('bio','Giới thiệu bản thân','textarea')}<div class="profile-interest-options">${interestChoices.map(name=>`<label><input type="checkbox" data-edit-interest="${name}" ${e.interests.split(',').map(x=>x.trim()).includes(name.toLowerCase())||e.interests.split(',').map(x=>x.trim()).includes(name)?'checked':''}>${name}</label>`).join('')}</div>${profileField('interests','Sở thích (cách nhau bằng dấu phẩy)')}</div></details><details class="profile-edit-section"><summary>Bản thân và cách xưng hô</summary><div class="profile-edit-section-body"><p class="body-copy">Bản dạng giới và xu hướng tính dục là hai thông tin riêng. Bạn có thể bỏ trống hoặc tự mô tả.</p>${profileField('gender','Bản dạng giới','select')}${profileField('orientation','Xu hướng tính dục','select')}${profileField('pronouns','Cách xưng hô','select')}</div></details><details class="profile-edit-section"><summary>Kết nối và cuộc sống</summary><div class="profile-edit-section-body">${profileField('relationshipRole','Tình trạng quan hệ','select')}${profileField('lookingFor','Mong muốn kết nối','select')}${profileField('city','Nơi sống')}${profileField('occupation','Nghề nghiệp')}${profileField('school','Trường học')}</div></details>${e.error?'<p class="kn-error" role="alert">'+esc(e.error)+'</p>':''}</section>`;}
  function previewProfileScreen(){const e=s.editProfile;if(!e)return profileEditorScreen();const fields=['bio','city','gender','orientation','pronouns','relationshipRole','lookingFor','occupation','school'];const u={...s.me,...Object.fromEntries(fields.map(k=>[k,e.visibility[k]===false?'':e[k]])),name:e.name,interests:e.visibility.interests===false?[]:e.interests.split(',').map(x=>x.trim()).filter(Boolean),birthDate:undefined};return childHeading('Hồ sơ công khai','editProfilePage')+`<section class="panel"><div class="person">${av(u)}<div><h1>${esc(u.name)}</h1><small>@${esc(u.username)}</small></div></div><p class="profile-bio">${esc(u.bio)}</p><div class="profile-interests">${u.interests.map(v=>'<span>'+esc(v)+'</span>').join('')}</div><div class="profile-fact-grid">${[['gender','Bản dạng giới'],['orientation','Xu hướng tính dục'],['pronouns','Cách xưng hô'],['relationshipRole','Tình trạng quan hệ'],['lookingFor','Mong muốn kết nối'],['city','Nơi sống'],['occupation','Nghề nghiệp'],['school','Trường học']].filter(([key])=>u[key]).map(([key,label])=>'<div class="profile-fact"><small>'+label+'</small><strong>'+esc(u[key])+'</strong></div>').join('')}</div></section>`;}

  const adminState={tab:'Yêu cầu mật khẩu',overview:{},users:[],reports:[],requests:[],activity:[],music:[],query:'',temporary:''};
  let adminModule = null, adminPromise = null;
  function ensureAdminModule() {
    if (adminModule) return Promise.resolve(adminModule);
    adminPromise ||= import('/v2-admin.js').then((mod) => {
      adminModule = mod;
      return mod;
    }).catch((err) => {
      adminPromise = null;
      throw err;
    });
    return adminPromise;
  }
  async function loadAdmin(){if(s.me?.role!=='admin')return;await ensureAdminModule();const [o,u,r,p,a,m]=await Promise.all([api('/admin/overview'),api('/admin/users?q='+encodeURIComponent(adminState.query)),api('/admin/reports'),api('/admin/password-resets'),api('/admin/activity'),api('/music')]);Object.assign(adminState,{overview:o,users:u.users,reports:r.reports,requests:p.requests,activity:a.entries,music:m.tracks});}
  function adminScreen(){
    if(s.me.role!=='admin')return emptyState('shield-check','Không có quyền quản trị','Chỉ tài khoản quản trị được mở mục này.');
    if(!adminModule){ensureAdminModule().then(()=>{if(s.screen==='admin')render();}).catch(()=>{});return childHeading('Quản trị')+loading();}
    return adminModule.renderAdminScreen({ s, adminState, aiSettings, aiSettingsError, esc, ic, btn, person, tabs, ago, emptyState, childHeading });
  }
  function notificationPreferences(){try{return {messages:true,friends:true,posts:true,...JSON.parse(localStorage.getItem('kinnect-v2-notifications-'+s.me.id)||'{}')};}catch{return {};}}
  // ---------- Web Push: nhận cuộc gọi và thông báo khi đã đóng Kinnect ----------
  const pushEnv=()=>{const ua=navigator.userAgent,ios=/iPad|iPhone|iPod/.test(ua)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1),standalone=navigator.standalone===true||matchMedia('(display-mode: standalone)').matches,android=/Android/i.test(ua),safari=/Safari/.test(ua)&&!/Chrome|CriOS|Edg|FxiOS|Android/.test(ua);
    return {ios,standalone,android,safari,supported:'serviceWorker' in navigator&&'PushManager' in window&&'Notification' in window&&window.isSecureContext,perm:'Notification' in window?Notification.permission:'unsupported'};};
  const pushOn=()=>{try{return !!s.me&&localStorage.getItem('kinnect-push-'+s.me.id)==='1'&&Notification.permission==='granted';}catch{return false;}};
  const b64key=k=>{const raw=atob((k+'='.repeat((4-k.length%4)%4)).replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(raw,c=>c.charCodeAt(0));};
  async function pushSubscribe(ask){const env=pushEnv();if(!env.supported)throw Error(env.ios&&!env.standalone?'Trên iPhone/iPad, hãy thêm Kinnect vào Màn hình chính rồi mở từ biểu tượng đó.':'Trình duyệt này chưa hỗ trợ thông báo nền.');
    if(Notification.permission!=='granted'){if(!ask)return false;if(await Notification.requestPermission()!=='granted')throw Error('Bạn chưa cho phép thông báo. Xem hướng dẫn bên dưới để bật lại.');}
    if(!await navigator.serviceWorker.getRegistration())await navigator.serviceWorker.register('/sw.js',{updateViaCache:'none'});
    const reg=await navigator.serviceWorker.ready,{publicKey}=await api('/push/key');let sub=await reg.pushManager.getSubscription();
    if(sub&&localStorage.getItem('kinnect-push-key')!==publicKey){await sub.unsubscribe().catch(()=>{});sub=null;}
    if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:b64key(publicKey)});
    await api('/push/subscribe','POST',{subscription:sub.toJSON()});localStorage.setItem('kinnect-push-key',publicKey);localStorage.setItem('kinnect-push-'+s.me.id,'1');return true;}
  async function pushUnsubscribe(){try{const reg=await navigator.serviceWorker.getRegistration(),sub=await reg?.pushManager.getSubscription();if(sub){await api('/push/unsubscribe','POST',{endpoint:sub.endpoint}).catch(()=>{});await sub.unsubscribe();}}finally{localStorage.removeItem('kinnect-push-'+s.me.id);}}
  // Báo cho máy chủ biết tab có đang hiển thị: khi ẩn, máy chủ gửi push thay cho tab.
  function sendVisibility(){try{if(media.socket?.readyState===WebSocket.OPEN)media.socket.send(JSON.stringify({type:'visibility',visible:document.visibilityState==='visible'}));}catch{}}
  document.addEventListener('visibilitychange',sendVisibility);
  navigator.serviceWorker?.addEventListener('message',e=>{if(e.data?.type==='push-call')ensureSocket().catch(()=>{});});
  // Chuông trong trang khi có cuộc gọi đến (WebAudio, không cần tệp âm thanh).
  let ringTimer=null,ringCtx=null,dialTimer=null,reconnectTimer=null;
  function startReconnectTone(){if(!media.call||media.call.ended||reconnectTimer)return;callCue('reconnect');reconnectTimer=setInterval(()=>{if(!media.call){stopReconnectTone();return;}callCue('reconnect');},4000);}
  function stopReconnectTone(){clearInterval(reconnectTimer);reconnectTimer=null;}
  function callCue(kind){try{ringCtx=ringCtx||new(window.AudioContext||window.webkitAudioContext)();ringCtx.resume();const at=ringCtx.currentTime;const notes=kind==='end'?[480,380]:kind==='connected'?[660,880]:kind==='reconnect'?[520,620]:[440,480];notes.forEach((freq,i)=>{const o=ringCtx.createOscillator(),g=ringCtx.createGain();o.frequency.value=freq;g.gain.setValueAtTime(0,at+i*.18);g.gain.linearRampToValueAtTime(.1,at+i*.18+.02);g.gain.linearRampToValueAtTime(0,at+i*.18+.16);o.connect(g).connect(ringCtx.destination);o.start(at+i*.18);o.stop(at+i*.18+.18);});}catch{}}
  function startDialing(){stopDialing();callCue('dial');dialTimer=setInterval(()=>{if(!media.call||media.call.accepted){stopDialing();return;}callCue('dial');},2800);}
  function stopDialing(){clearInterval(dialTimer);dialTimer=null;}

  function ringTone(){try{ringCtx=ringCtx||new (window.AudioContext||window.webkitAudioContext)();ringCtx.resume?.();const t=ringCtx.currentTime;[0,.45].forEach(o=>{const osc=ringCtx.createOscillator(),g=ringCtx.createGain();osc.type='sine';osc.frequency.setValueAtTime(880,t+o);osc.frequency.setValueAtTime(660,t+o+.18);g.gain.setValueAtTime(0,t+o);g.gain.linearRampToValueAtTime(.22,t+o+.03);g.gain.linearRampToValueAtTime(0,t+o+.36);osc.connect(g).connect(ringCtx.destination);osc.start(t+o);osc.stop(t+o+.38);});navigator.vibrate?.([400,200,400]);}catch{}}
  function startRinging(){if(ringTimer)return;ringTone();ringTimer=setInterval(()=>{if(!media.call?.incoming||media.call.accepted){stopRinging();return;}ringTone();},2200);}
  function stopRinging(){clearInterval(ringTimer);ringTimer=null;try{navigator.vibrate?.(0);}catch{}}
  function pushGuide(){const env=pushEnv(),on=pushOn(),step=(n,t)=>`<li><b>${n}</b><span>${t}</span></li>`;
    let state,action='';
    if(on){state=`<p class="push-state ok">${ic('check')}<span>Đã bật trên thiết bị này. Bạn sẽ nhận cuộc gọi đổ chuông, tin nhắn và thông báo cả khi đã đóng Kinnect.</span></p>`;action=btn('Gửi thông báo thử','bell','push-test','primary')+btn('Tắt trên thiết bị này','bell-off','push-disable','secondary');}
    else if(env.ios&&!env.standalone){state=`<p class="push-state warn">Safari trên iPhone/iPad chỉ nhận thông báo nền khi Kinnect được thêm vào Màn hình chính (iOS 16.4 trở lên). Làm theo các bước bên dưới.</p>`;}
    else if(!env.supported){state=`<p class="push-state warn">Trình duyệt này chưa hỗ trợ thông báo nền. Hãy dùng Chrome, Edge hoặc Safari bản mới.</p>`;}
    else if(env.perm==='denied'){state=`<p class="push-state warn">Bạn đã chặn thông báo của Kinnect. Làm theo hướng dẫn bên dưới để cho phép lại, rồi tải lại trang.</p>`;action=btn('Tải lại trang','arrow-right','push-reload','secondary');}
    else{state=`<p class="push-state">Chưa bật. Bấm nút bên dưới và chọn <b>Cho phép</b> khi trình duyệt hỏi.</p>`;action=btn('Bật thông báo nền','bell','push-enable','primary');}
    const guides=[
      ['iPhone / iPad (Safari)',env.ios,[['1','Mở app.kinnect.io.vn bằng Safari, bấm nút Chia sẻ (ô vuông có mũi tên lên).'],['2','Chọn “Thêm vào MH chính” rồi bấm Thêm.'],['3','Mở Kinnect từ biểu tượng mới trên Màn hình chính và đăng nhập.'],['4','Vào Cài đặt thông báo, bấm “Bật thông báo nền”, chọn Cho phép.'],['5','Để chuông kêu: Cài đặt iPhone › Thông báo › Kinnect › bật Âm thanh, kiểu biểu ngữ “Liên tục”. Tắt chế độ Im lặng/Tập trung.']]],
      ['Chrome / Edge trên Android',env.android,[['1','Bấm “Bật thông báo nền” và chọn Cho phép.'],['2','Cài đặt điện thoại › Ứng dụng › Chrome › Thông báo › app.kinnect.io.vn: bật Âm thanh và “Hiện trên màn hình”.'],['3','Cài đặt › Pin › Chrome: chọn “Không hạn chế” để không bị trễ khi máy khoá.'],['4','Muốn chuông toàn màn hình như Zalo, hãy cài app Kinnect cho Android.']]],
      ['Chrome / Edge trên máy tính',!env.ios&&!env.android&&!env.safari,[['1','Bấm “Bật thông báo nền” và chọn Cho phép.'],['2','Nếu lỡ chặn: bấm biểu tượng ổ khoá cạnh địa chỉ › Quyền trang web › Thông báo › Cho phép.'],['3','Windows: Cài đặt › Hệ thống › Thông báo › bật cho Chrome/Edge và tắt “Không làm phiền”.'],['4','macOS: Cài đặt hệ thống › Thông báo › Google Chrome › kiểu “Cảnh báo” để cuộc gọi không tự ẩn.'],['5','Để nhận khi đã đóng cửa sổ: Cài đặt Chrome › Hệ thống › bật “Tiếp tục chạy ứng dụng nền khi đóng Google Chrome”.']]],
      ['Safari trên Mac',env.safari&&!env.ios,[['1','Bấm “Bật thông báo nền” và chọn Cho phép.'],['2','Nếu lỡ chặn: Safari › Cài đặt › Trang web › Thông báo › app.kinnect.io.vn › Cho phép.'],['3','Cài đặt hệ thống › Thông báo › Safari › kiểu “Cảnh báo” và bật âm thanh.']]],
    ];
    return `<section class="panel settings-section push-panel"><h2>${ic('phone')} Cuộc gọi &amp; thông báo khi đóng Kinnect</h2><p class="body-copy">Chuông cuộc gọi, nội dung tin nhắn, bình luận và lời mời kết bạn sẽ hiện cả khi bạn đã đóng tab hoặc khoá màn hình.</p>${state}<div class="push-actions">${action}</div>
      ${guides.map(([title,mine,steps])=>`<details class="push-guide"${mine?' open':''}><summary>${esc(title)}${mine?' <em>thiết bị này</em>':''}</summary><ol>${steps.map(([n,t])=>step(n,t)).join('')}</ol></details>`).join('')}
      <p class="body-copy push-note">Lưu ý: trình duyệt đổ chuông bằng âm báo hệ thống trong khoảng 40 giây và không hiện toàn màn hình khi máy khoá. Chạm vào thông báo để mở cuộc gọi; trên Chrome có sẵn nút Trả lời / Từ chối.</p></section>`;}
  function pushBanner(){const env=pushEnv();if(!s.me||pushOn()||(!env.supported&&!env.ios)||env.perm==='denied')return '';try{if(localStorage.getItem('kinnect-push-banner-'+s.me.id)==='hide')return '';}catch{}
    return `<section class="panel push-banner">${ic('bell')}<div class="grow"><strong>Không bỏ lỡ cuộc gọi</strong><small>Bật thông báo nền để nhận chuông cuộc gọi và tin nhắn khi đã đóng Kinnect.</small></div>${btn('Bật ngay','','push-setup','primary')}${btn('Để sau','x','push-banner-hide','icon')}</section>`;}
  async function pushAction(a){switch(a){
    case 'push-enable':try{await pushSubscribe(true);toast('Đã bật thông báo nền. Đang gửi thông báo thử…');await api('/push/test','POST',{});}catch(err){toast(err.message);}render();return true;
    case 'push-test':try{await api('/push/test','POST',{});toast('Đã gửi. Hãy thử đóng tab để xem thông báo.');}catch(err){toast(err.message);}return true;
    case 'push-disable':await pushUnsubscribe();toast('Đã tắt thông báo nền trên thiết bị này.');render();return true;
    case 'push-reload':location.reload();return true;
    case 'push-setup':await go('notificationSettings');return true;
    case 'push-banner-hide':try{localStorage.setItem('kinnect-push-banner-'+s.me.id,'hide');}catch{}render();return true;}
    return false;}
  function notificationSettingsScreen(){const pref=notificationPreferences();return childHeading('Cài đặt thông báo')+`<section class="panel settings-section"><h2>Thông báo trên thiết bị này</h2><p class="body-copy">Áp dụng khi Kinnect đang mở trong trình duyệt. Chấm chưa đọc vẫn được giữ để bạn không bỏ sót nội dung.</p>${[['enabled','Hiện thông báo trình duyệt'],['messages','Tin nhắn'],['friends','Lời mời kết bạn'],['posts','Bài viết và tương tác']].map(([key,label])=>`<label class="setting-toggle"><strong>${label}</strong><input type="checkbox" data-notification-pref="${key}" aria-label="${label}" ${pref[key]?'checked':''}></label>`).join('')}</section>`+pushGuide();}
  const profileExtras={sessions:[],blocks:[],privatePhotos:[],privateRequests:[],album:null,email:null,challenge:''};
  async function loadPrivateAlbum(id=s.me.id){profileExtras.album=await api('/users/'+id+'/private');if(id===s.me.id)profileExtras.privateRequests=(await api('/me/private/requests')).requests;}
  function privateAlbumScreen(){const album=profileExtras.album;if(!album)return loading();const mine=!s.params.user||s.params.user===s.me.id,allowed=album.status==='owner'||album.status==='granted';return '<div class="account-child-heading">'+btn('Quay lại album ảnh','arrow-left','private-back','icon')+'<h1>Ảnh riêng tư</h1></div><section class="private-album-panel panel"><div class="private-album-toolbar"><div><span class="album-privacy-label">'+ic('lock-keyhole')+' Chỉ người được cấp quyền</span>'+(allowed?'<small>'+album.photos.length+' ảnh</small>':'')+'</div>'+(mine?'<label class="kn-file-btn private-add-photo">'+ic('image-plus')+'<span>Thêm ảnh</span><input type="file" data-private-photo accept="image/png,image/jpeg,image/webp" hidden></label>':'')+'</div>'+(allowed?album.photos.length?'<div class="profile-media private-album-media">'+album.photos.map(photo=>'<a class="profile-media-tile" href="'+esc(photo.url)+'" target="_blank" rel="noopener"><img class="kn-fill" src="'+esc(photo.url)+'" alt="Ảnh riêng tư" loading="lazy"></a>').join('')+'</div>':emptyState('lock-keyhole','Album chưa có ảnh','Ảnh bạn thêm vào đây chỉ dành cho người được bạn cấp quyền.'):'<div class="private-album-locked">'+emptyState('lock-keyhole','Album riêng tư',album.status==='pending'?'Yêu cầu của bạn đang chờ chủ album duyệt.':'Gửi yêu cầu để chủ album cấp quyền xem ảnh.')+btn(album.status==='pending'?'Đang chờ duyệt':'Yêu cầu xem ảnh','lock-keyhole','private-request','primary').replace('type="button"','type="button" '+(album.status==='pending'?'disabled':''))+'</div>')+'</section>'+(mine?'<section class="panel album-access-panel"><h2>Quyền truy cập</h2>'+(profileExtras.privateRequests.length?profileExtras.privateRequests.map(r=>'<article class="v2-friend-row">'+person(r.user,r.status==='pending'?'Đang chờ duyệt':'Đã được duyệt')+'<div class="row">'+(r.status==='pending'?btn('Đồng ý','check','private-decision','primary','grant:'+r.user.id)+btn('Từ chối','x','private-decision','secondary','deny:'+r.user.id):btn('Thu hồi','x','private-decision','secondary','revoke:'+r.user.id))+'</div></article>').join(''):'<p class="body-copy">Chưa có yêu cầu xem ảnh. Bạn sẽ duyệt quyền truy cập tại đây.</p>')+'</section>':'');}

  function blockedScreen(){return childHeading('Tài khoản đã chặn','settings')+`<section class="panel">${profileExtras.blocks.map(u=>`<article class="v2-friend-row">${person(u,'@'+esc(u.username))}${btn('Bỏ chặn','user-check','unblock-user','secondary',u.id)}</article>`).join('')||emptyState('shield-check','Chưa chặn tài khoản nào','Các tài khoản bạn chặn sẽ hiển thị tại đây.')}</section>`;}
  function recoveryEmailScreen(){const hp=s.me?.hasPassword!==false;return childHeading('Email khôi phục','security')+`<form data-recovery-email class="panel settings-section"><p class="body-copy">${profileExtras.email?'Email hiện tại: '+esc(profileExtras.email):'Thêm email để lấy lại mật khẩu khi cần.'}</p>${profileExtras.challenge?'<label class="v2-field">Mã OTP<input name="code" inputmode="numeric" maxlength="6" required autocomplete="one-time-code"></label>':'<label class="v2-field">Email<input name="email" type="email" required autocomplete="email"></label>'+(hp?'<label class="v2-field">Mật khẩu hiện tại<input name="password" type="password" required autocomplete="current-password"></label>':'<p class="body-copy"><small>Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập trong 10 phút gần đây).</small></p>')}<button type="submit" class="primary">${profileExtras.challenge?'Xác minh':'Gửi mã xác minh'}</button></form>`;}

  const storiesState={text:'',media:'',background:'purple',index:0,stage:'choose'};
  function storyCanvasScreen(){return `<section class="v2-story-editor"><div class="heading">${btn('Đóng tạo tin','x','story-close','icon')}<h1>Tạo tin</h1>${btn('Đăng tin','send','story-publish','primary')}</div><div class="v2-story-canvas" data-background="${storiesState.background}">${storiesState.media?storiesState.media.startsWith('data:video')?'<video src="'+esc(storiesState.media)+'" controls playsinline></video>':'<img src="'+esc(storiesState.media)+'" alt="Ảnh tin">':''}<textarea data-story-text aria-label="Nội dung tin" placeholder="Chia sẻ khoảnh khắc của bạn…" maxlength="500">${esc(storiesState.text)}</textarea></div><div class="row"><label class="kn-file-btn">${ic('image-plus')}Ảnh / video<input type="file" data-story-file accept="image/png,image/jpeg,image/webp,video/mp4" hidden></label>${['purple','sunset','forest','ocean'].map(bg=>btn(({purple:'Tím',sunset:'Hoàng hôn',forest:'Rừng',ocean:'Biển'})[bg],'','story-background',storiesState.background===bg?'active':'secondary',bg)).join('')}</div><p class="body-copy">Tin hiển thị trong 24 giờ với người theo dõi bạn.</p></section>`;}
  function storyEditorScreen(){if(storiesState.stage!=='choose')return storyCanvasScreen().replace('data-do="story-close"','data-do="approved-story-back"');return '<section class="create-page story-redesign"><div class="create-heading">'+btn('Quay lại','arrow-left','story-close','icon')+'<h1>Tạo tin</h1><span class="story-expiry">24 giờ</span></div><div class="story-create-welcome"><h2>Một khoảnh khắc, một câu chuyện.</h2><p>Chia sẻ điều bạn muốn giữ lại hôm nay.</p></div><div class="story-source-grid"><label class="story-source-card">'+ic('image')+'<strong>Ảnh / video</strong><small>Chọn khoảnh khắc từ thiết bị</small><input type="file" data-story-file accept="image/png,image/jpeg,image/webp,video/mp4" hidden></label><button type="button" class="story-source-card" data-do="story-camera-open">'+ic('camera')+'<strong>Chụp / quay trực tiếp</strong><small>Camera, hiệu ứng và ghép nhạc</small></button><button type="button" class="story-source-card" data-do="approved-story-text">'+ic('type')+'<strong>Văn bản</strong><small>Viết điều bạn muốn chia sẻ</small></button></div></section>';}
  async function markStoryViewed(){const st=s.stories[storiesState.index];if(st&&st.user_id!==s.me.id)try{await api('/stories/'+st.id+'/view','POST',{});}catch(err){toast(err.message);}}
  function storyViewersSheet(){const q=s.storyViewers;if(!q)return '';return '<div class="composer-sheet"><section class="story-viewers-dialog" role="dialog" aria-label="Người xem tin"><div class="sheet-head"><h2>'+Number(q.viewers?.length||0)+' người xem</h2>'+btn('Đóng danh sách người xem','x','story-viewers-close','icon')+'</div>'+(q.error?'<p class="kn-error">'+esc(q.error)+'</p>':q.viewers?q.viewers.length?'<div class="story-viewer-list">'+q.viewers.map(u=>'<button type="button" data-do="story-viewer-profile" data-value="'+esc(u.id)+'" aria-label="Xem trang cá nhân '+esc(u.name)+'">'+person(u,'@'+esc(u.username))+ic('chevron-right')+'</button>').join('')+'</div>':emptyState('eye','Chưa có người xem','Người xem tin của bạn sẽ xuất hiện tại đây.'):loading('Đang tải người xem…'))+'</section></div>';}
  function storyViewerScreen(){const st=s.stories[storiesState.index];if(!st)return emptyState('image','Tin đã hết hạn','Quay về Bảng tin để xem tin mới.');return `<section class="v2-story-viewer" data-background="${esc(st.background||'purple')}"><div class="v2-story-header">${person(st.author,ago(st.created))}${st.user_id===s.me.id?btn('Xoá tin','trash-2','story-delete','icon',st.id):''}${btn('Đóng xem tin','x','story-close','icon')}</div>${st.media?st.media.kind==='video'?'<video src="'+esc(st.media.url)+'"'+(st.media.thumbnail?' poster="'+esc(st.media.thumbnail)+'"':'')+' controls playsinline autoplay></video>':'<img src="'+esc(st.media.url)+'" alt="Tin của '+esc(st.author.name)+'">':''}<p class="v2-story-copy">${esc(st.body)}</p><div class="v2-story-navigation">${btn('Tin trước','chevron-left','story-previous','icon')}${btn('Tin tiếp','chevron-right','story-next','icon')}</div>${st.user_id===s.me.id?'<div class="story-view-count">'+btn(Number(st.viewCount||0)+' người xem','eye','story-viewers-open','',st.id)+'</div>':''}</section>`;}
  const reactionNames={like:'Thích',love:'Yêu thích',haha:'Haha',wow:'Wow',sad:'Buồn',angry:'Phẫn nộ'};
  const reactionIcons={like:'👍',love:'❤️',haha:'😂',wow:'😮',sad:'😢',angry:'😡'};
  const emojiList=['😀','😊','🥰','😍','😘','😂','🤣','🥹','🥺','😎','🤔','😭','😡','❤️','💜','💖','🔥','👍','👏','🙏','🎉','✨','🌈','🏳️‍🌈','🏳️‍⚧️','🌻','☕','🎶','💬','🤝'];
  function reportSheet(){return '<div class="composer-sheet"><section role="dialog" aria-label="Gửi báo cáo"><div class="heading"><h2>'+ (s.reportTarget.type==='app'?'Báo sự cố':'Báo cáo nội dung')+'</h2>'+btn('Đóng báo cáo','x','report-close','icon')+'</div><form data-v2-report><p class="body-copy">Nếu liên quan an toàn trẻ em, ghi rõ CSAE/CSAM và ID nội dung; không gửi lại ảnh vi phạm. Liên hệ riêng: anhvn53@wru.vn.</p><label class="v2-field">Mô tả<textarea data-report-reason aria-label="Mô tả báo cáo" minlength="5" maxlength="1000" required>'+esc(s.reportReason)+'</textarea></label><button type="submit" class="primary">Gửi báo cáo</button></form></section></div>';}

  function reactorsSheet(){const r=s.reactors,users=r.users||[],counts={};users.forEach(u=>counts[u.reaction]=(counts[u.reaction]||0)+1);const tabs=[['all','Tất cả '+users.length]].concat(Object.entries(counts).sort((a,b)=>b[1]-a[1]).map(([k,n])=>[k,(reactionIcons[k]||'')+' '+n]));const shown=r.tab==='all'?users:users.filter(u=>u.reaction===r.tab);return '<div class="composer-sheet reactors-sheet"><button type="button" class="reactors-backdrop" data-do="post-reactors-close" aria-label="Đóng"></button><section role="dialog" aria-modal="true" aria-label="Người đã bày tỏ cảm xúc"><div class="heading"><div class="reactors-tabs" role="tablist">'+tabs.map(([k,l])=>'<button type="button" role="tab" aria-selected="'+(r.tab===k)+'" class="'+(r.tab===k?'active':'')+'" data-do="post-reactors-tab" data-value="'+esc(k)+'">'+esc(l)+'</button>').join('')+'</div>'+btn('Đóng','x','post-reactors-close','icon')+'</div><div class="reactors-list">'+(r.loading?loading('Đang tải…'):shown.length?shown.map(u=>'<button type="button" class="cursor-interaction reactor-row" data-do="open-profile" data-value="'+esc(u.id)+'"><span class="reactor-av">'+av(u)+'<i aria-label="'+esc(reactionNames[u.reaction]||'')+'">'+(reactionIcons[u.reaction]||'')+'</i></span><span><b>'+esc(u.name)+'</b><small>@'+esc(u.username)+'</small></span></button>').join(''):'<p class="body-copy">Chưa có ai bày tỏ cảm xúc.</p>')+'</div></section></div>';}
  function shareSheet(){const p=findPost(s.sharePost),url=location.origin+'/?s=postDetail&post='+encodeURIComponent(s.sharePost);return '<div class="composer-sheet"><section role="dialog" aria-label="Chia sẻ bài viết"><div class="heading"><h2>Chia sẻ</h2>'+btn('Đóng chia sẻ','x','share-close','icon')+'</div>'+(!p||p.visibility==='public'?'<label class="v2-field">Chia sẻ lên bảng tin<textarea data-share-caption rows="2" maxlength="500" placeholder="Viết cảm nghĩ của bạn…">'+esc(s.shareCaption||'')+'</textarea></label>'+btn('Chia sẻ lên bảng tin','send','share-repost','primary'):'')+'<label class="v2-field">Liên kết bài viết<input readonly value="'+esc(url)+'" aria-label="Liên kết bài viết"></label>'+btn('Sao chép liên kết','copy','share-copy','secondary')+'<h2>Gửi qua tin nhắn</h2>'+community.friends.map(u=>'<button type="button" class="v2-share-person" data-do="share-to" data-value="'+esc(u.id)+'">'+person(u,'@'+esc(u.username))+ic('send')+'</button>').join('')+(!community.friends.length?'<p class="body-copy">Kết bạn để gửi bài viết trực tiếp tại đây.</p>':'')+'</section></div>';}

  function emojiSheet(){return `<section class="v2-emoji-sheet panel" aria-label="Biểu tượng cảm xúc"><div class="heading"><h2>Biểu tượng cảm xúc</h2>${btn('Đóng biểu tượng cảm xúc','x','emoji-close','icon')}</div><div>${(s.emojiTarget.startsWith('message:')?Object.keys(reactionIcons):emojiList).map(emoji=>btn(reactionIcons[emoji]||emoji,'','emoji-choose','',emoji)).join('')}</div></section>`;}
  function threadComments(list){const t=c=>new Date(c.created||0).getTime()||0,byTime=(a,b)=>t(a)-t(b),ids=new Set(list.map(c=>c.id)),kids=new Map();for(const c of list)if(c.parentId&&ids.has(c.parentId)){if(!kids.has(c.parentId))kids.set(c.parentId,[]);kids.get(c.parentId).push(c);}const out=[],walk=c=>{out.push(c);(kids.get(c.id)||[]).sort(byTime).forEach(walk);};list.filter(c=>!c.parentId||!ids.has(c.parentId)).sort(byTime).forEach(walk);return out;}
function postCommentRows(id,comments){return threadComments(comments).map(c=>{
    const key=id+':'+c.id,opened=s.reactionComment===key,editing=s.commentEditing?.key===key,counts=Object.entries(c.reactions||{}).filter(([k,n])=>reactionIcons[k]&&n>0),total=counts.reduce((n,[k,v])=>n+v,0);
    return `<article class="post-comment ${c.parentId?'v2-comment-reply':''}" data-comment-id="${esc(c.id)}">${av(c.author)}<div class="comment-content"><b>${esc(c.author?.name||c.author?.username)}</b>${editing?`<div class="comment-editor"><textarea data-comment-edit aria-label="Sửa bình luận" maxlength="${videoCommentContext(id)?500:1000}">${esc(s.commentEditing.text)}</textarea><div>${btn('Huỷ','','comment-edit-cancel','secondary')}${btn('Lưu','check','comment-edit-save','primary',key)}</div></div>`:`<p>${withMentions(c.body)}</p>`}<div class="comment-footer"><small class="comment-time">${ago(c.created)}</small><div class="comment-actions"><button type="button" data-do="comment-reaction-toggle" data-value="${esc(key)}" title="${c.myReaction?reactionNames[c.myReaction]:'Cảm xúc'}" class="comment-reaction-trigger ${c.myReaction?'active':''}" aria-expanded="${opened}" aria-label="${c.myReaction?reactionNames[c.myReaction]:'Cảm xúc bình luận'}">${c.myReaction?`<span class="comment-reaction-emoji">${reactionIcons[c.myReaction]}</span>`:ic('smile')}<span>${c.myReaction?reactionNames[c.myReaction]:'Cảm xúc'}</span>${total?`<span class="comment-reaction-count">${total}</span>`:''}</button><button type="button" data-do="comment-reply" data-value="${esc(key)}" title="Trả lời" aria-label="Trả lời" class="comment-reply-trigger">${ic('message-circle')}${comments.filter(r=>r.parentId===c.id).length?`<span class="comment-reply-count">${comments.filter(r=>r.parentId===c.id).length}</span>`:''}</button>${c.user_id===s.me.id&&!editing?btn('Sửa','pencil','comment-edit','icon',key).replace('<button ', '<button title="Sửa" aria-label="Sửa" ')+btn('Xoá','trash-2','comment-delete','icon',key).replace('<button ', '<button title="Xoá" aria-label="Xoá" '):''}</div></div>${opened?`<div class="comment-reaction-picker" role="group" aria-label="Chọn cảm xúc bình luận"><div class="reaction-options">${Object.entries(reactionIcons).map(([k,emoji])=>`<button type="button" data-do="comment-reaction-select" data-value="${esc(key)}:${k}" title="${reactionNames[k]}" aria-label="${reactionNames[k]}" aria-pressed="${c.myReaction===k}" class="${c.myReaction===k?'selected':''}">${emoji}</button>`).join('')}</div>${c.myReaction?btn('Gỡ cảm xúc','x','comment-reaction-select','reaction-remove',key+':remove'):''}</div>`:''}</div></article>`;
  }).join('');}


  function openChatOptions(){const u=community.chat;if(!u)return;const d=document.createElement('dialog');d.className='kn-feature-sheet';d.setAttribute('aria-label','Tùy chọn cuộc trò chuyện');const rows=u.isGroup?[['Thông tin và quản lý nhóm','users-round',()=>go('groupDetails',{group:u.id})]]:[['Xem hồ sơ','user-round',()=>go('profile',{user:u.id})],['Báo cáo tài khoản','flag',()=>{s.reportTarget={type:'user',id:u.id};render();}]];rows.push(['Ghim / bỏ ghim','pin',()=>communityAction('community-pin',chatKey(u))],['Tắt / bật thông báo','bell-off',()=>communityAction('community-mute',chatKey(u))],['Đánh dấu chưa đọc','mail',()=>communityAction('community-unread',chatKey(u))],['Ẩn hội thoại','eye-off',()=>communityAction('community-hide',chatKey(u))]);d.innerHTML='<div class="sheet-head"><h2>'+esc(u.name)+'</h2><button aria-label="Đóng">'+ic('x')+'</button></div>';d.querySelector('button').onclick=()=>d.close();for(const [label,icon,fn] of rows){const b=document.createElement('button');b.className='native-sheet-option';b.innerHTML=ic(icon)+'<span>'+esc(label)+'</span>';b.onclick=async()=>{d.close();try{await fn();}catch(e){toast(e.message);}};d.append(b);}d.addEventListener('close',()=>d.remove(),{once:true});document.body.append(d);d.showModal();}
  function groupAvatarControls(g,manages){return '<div class="group-avatar-settings">'+av(g)+(manages?'<label class="kn-file-btn">'+ic('image-plus')+' Đổi ảnh nhóm<input data-group-avatar type="file" accept="image/png,image/jpeg,image/webp" hidden></label><div class="row">'+[['violet','Tím'],['ocean','Biển'],['sunset','Hoàng hôn'],['forest','Rừng']].map(([key,name])=>btn(name,'users-round','group-avatar-preset','group-preset preset-'+key,key)).join('')+'</div>':'')+'</div>';}
  function groupDetailsScreen(){const g=community.chat;if(!g?.isGroup)return emptyState('users-round','Không tìm thấy nhóm','Quay lại hộp thư để mở nhóm.');const mine=g.owner===s.me.id,manages=mine||g.members.some(u=>u.id===s.me.id&&u.groupRole==='deputy');return childHeading('Thông tin nhóm','inbox')+'<section class="panel settings-section">'+groupAvatarControls(g,manages)+(manages?'<form data-group-rename class="v2-search"><input name="name" aria-label="Tên nhóm" maxlength="80" value="'+esc(g.name)+'" required><button type="submit" class="primary">Lưu</button></form>':'<h2>'+esc(g.name)+'</h2>')+'<h2>'+g.members.length+' thành viên</h2>'+g.members.map(u=>'<article class="v2-friend-row">'+person(u,'@'+esc(u.username)+(u.id===g.owner?' · Trưởng nhóm':u.groupRole==='deputy'?' · Phó nhóm':' · Thành viên'))+(mine&&u.id!==s.me.id?btn(u.groupRole==='deputy'?'Gỡ phó nhóm':'Bổ nhiệm phó nhóm','shield-check','group-role','secondary',(u.groupRole==='deputy'?'member:':'deputy:')+u.id)+btn('Chuyển trưởng nhóm','users-round','group-role','secondary','owner:'+u.id):'')+(manages&&u.id!==g.owner&&u.id!==s.me.id&&(mine||u.groupRole!=='deputy')?btn('Xoá thành viên '+u.name,'x','group-remove-member','icon',u.id):'')+'</article>').join('')+(manages?'<details><summary>Thêm thành viên</summary><form data-group-add>'+community.candidates.filter(u=>!g.members.some(m=>m.id===u.id)).map(u=>'<label class="group-contact">'+av(u)+'<span>'+esc(u.name)+'</span><input type="checkbox" name="members" value="'+esc(u.id)+'" aria-label="Thêm '+esc(u.name)+'"></label>').join('')+'<button type="submit" class="primary">Thêm thành viên</button></form></details>':'')+btn('Rời nhóm','log-out','group-leave','secondary')+'</section>';}

  function devicesScreen(){return childHeading('Thiết bị đăng nhập','security')+'<section class="panel settings-section"><p class="body-copy">Thu hồi phiên để đăng xuất thiết bị khác và huỷ đăng nhập nhanh của thiết bị đó.</p>'+profileExtras.sessions.map(d=>'<article class="v2-friend-row"><div><strong>'+esc(d.label)+'</strong><small>'+(d.current?'Thiết bị hiện tại':'Hết hạn '+new Date(d.expires).toLocaleDateString('vi-VN'))+'</small></div>'+(!d.current?btn('Đăng xuất thiết bị','log-out','device-revoke','secondary',d.id):'')+'</article>').join('')+'</section>';}

  const screens = { feed, bookmarks: bookmarksScreen, notifications:()=>pushBanner()+notifications(), account, profile, friends: friendsScreen, inbox: inboxScreen, createGroup: createGroupScreen, devices:devicesScreen, twoFactor:twoFactorScreen, groupDetails:groupDetailsScreen, createStory:storyEditorScreen, storyView:storyViewerScreen, postDetail:()=>head("Bài viết","",btn("Quay lại","arrow-left","back","icon"))+(s.posts?.find(p=>p.id===s.params.post)?postCard(s.posts.find(p=>p.id===s.params.post)):emptyState("newspaper","Nội dung không còn khả dụng","Bài viết có thể đã bị xoá hoặc thay đổi quyền xem.")), admin:adminScreen, notificationSettings:notificationSettingsScreen, privateAlbum:privateAlbumScreen, blockedAccounts:blockedScreen, recoveryEmail:recoveryEmailScreen, editProfilePage: profileEditorScreen, profilePreview: previewProfileScreen, video: videoScreen, studio: studioScreen, call: callScreen, live: liveScreen, discover: discoverScreen, store: storeScreen, wallet:walletScreen, settings: settingsScreen, security: securityScreen, changePassword: passwordScreen, appearance: appearanceScreen, help: helpScreen };

  // ---------- Sheets ----------
  function logoutSheet() {
    return `<section class="logout-confirm panel" aria-label="Xác nhận đăng xuất"><h2>Đăng xuất khỏi Kinnect?</h2><p>Bạn có thể đăng nhập lại bất cứ lúc nào.</p><div>${btn("Ở lại", "", "logout-cancel", "secondary")}${btn("Đăng xuất", "log-out", "logout", "primary")}</div></section>`;
  }
  function composerSheet(){const c=s.composer;if(!c)return '';if(c.audienceOnly)return `<section class="panel post-audience-sheet" aria-label="Đối tượng xem bài viết"><div class="heading"><h2>Ai có thể xem?</h2>${btn('Đóng','x','composer-close','icon')}</div><p>Chọn đối tượng xem bài viết này.</p><label class="field">Đối tượng xem<select data-composer-visibility aria-label="Ai có thể xem"><option value="public" ${c.visibility==='public'?'selected':''}>Mọi thành viên</option><option value="followers" ${c.visibility==='followers'?'selected':''}>Người theo dõi</option></select></label>${c.error?'<p class="kn-error">'+esc(c.error)+'</p>':''}${btn(c.busy?'Đang lưu…':'Lưu thay đổi','check','composer-submit','primary')}</section>`;const albumPreview=c.mediaItems?.length>1?`<div class="composer-album-strip">${c.mediaItems.map((src,i)=>`<div class="composer-album-item"><img src="${src}" alt="Ảnh ${i+1}">${btn('Bỏ ảnh','x','composer-remove-item','icon',String(i))}</div>`).join('')}</div>`:'';return `<section class="create-page approved-composer" aria-label="Tạo bài viết"><div class="create-heading">${btn('Quay lại','arrow-left','composer-close','icon')}<h1>${c.editId?'Chỉnh sửa bài viết':'Tạo bài viết'}</h1>${btn(c.busy?'Đang lưu…':c.editId?'Lưu':'Đăng','send','composer-submit','primary')}</div><div class="post-author">${person(s.me,'@'+esc(s.me.username))}<label class="field">Ai có thể xem<select data-composer-visibility aria-label="Ai có thể xem"><option value="public" ${c.visibility==='public'?'selected':''}>Mọi thành viên</option><option value="followers" ${c.visibility==='followers'?'selected':''}>Người theo dõi</option></select></label><div class="compose-tools post-compose-toolbar post-compose-toolbar-inline" aria-label="Thêm nội dung vào bài viết"><label class="kn-file-btn post-attach-icon" title="Thêm ảnh (tối đa 10)" aria-label="Thêm ảnh" tabindex="0">${ic('image')}<input aria-label="Chọn ảnh cho bài viết" type="file" accept="image/png,image/jpeg,image/webp" multiple data-composer-file hidden></label><label class="kn-file-btn post-attach-icon" title="Thêm video" aria-label="Thêm video" tabindex="0">${ic('video')}<input aria-label="Chọn video cho bài viết" type="file" accept="video/mp4" data-composer-file hidden></label></div></div>${!c.media&&!albumPreview&&c.existingMedia?'<div class="composer-preview">'+(c.existingMedia.kind==='video'?'<video src="'+esc(c.existingMedia.url)+'" controls playsinline></video>':'<img src="'+esc(c.existingMedia.url)+'" alt="Ảnh đính kèm hiện tại">')+'</div>':''}<textarea data-composer-text maxlength="2000" aria-label="Nội dung bài viết" placeholder="Bạn đang nghĩ gì? (có thể thêm #hashtag)">${esc(c.text)}</textarea>${albumPreview||(c.media?'<div class="composer-preview">'+(c.media.startsWith('data:video')?'<video src="'+esc(c.media)+'" controls playsinline></video>':'<img src="'+esc(c.media)+'" alt="Ảnh đính kèm">')+'</div>':'')}${c.error?'<p class="kn-error">'+esc(c.error)+'</p>':''}</section>`;}


  function editProfileSheet() {
    const e = s.editProfile;
    return `<div class="composer-sheet"><section role="dialog" aria-label="Chỉnh sửa hồ sơ"><div class="sheet-head"><h2>Chỉnh sửa hồ sơ</h2>${btn("Đóng", "x", "edit-close", "icon")}</div><label class="auth-field"><span class="auth-label">Tên hiển thị</span><span class="auth-input">${ic("pen-line")}<input data-edit="name" maxlength="60" value="${esc(e.name)}"></span></label><label class="auth-field"><span class="auth-label">Giới thiệu</span><textarea data-edit="bio" maxlength="500" class="kn-bio-input">${esc(e.bio)}</textarea></label><label class="auth-field"><span class="auth-label">Nơi sống</span><span class="auth-input">${ic("map-pin")}<input data-edit="city" maxlength="80" value="${esc(e.city)}"></span></label><label class="auth-field"><span class="auth-label">Sở thích (cách nhau bằng dấu phẩy)</span><span class="auth-input">${ic("heart")}<input data-edit="interests" maxlength="300" value="${esc(e.interests)}"></span></label><div class="row"><label class="cursor-interaction secondary kn-file-btn">${ic("camera")}<span>Đổi ảnh đại diện</span><input type="file" accept="image/png,image/jpeg,image/webp" data-avatar-file hidden></label><label class="cursor-interaction secondary kn-file-btn">${ic("image")}<span>Đổi ảnh bìa</span><input type="file" accept="image/png,image/jpeg,image/webp" data-cover-file hidden></label></div>${e.error ? `<p class="kn-error">${esc(e.error)}</p>` : ""}${btn(e.busy ? "Đang lưu…" : "Lưu thay đổi", "check", "edit-save", "primary")}</section></div>`;
  }

  function openDiscoveryFilters(kind){
    const dialog=document.createElement('dialog');dialog.className='kn-feature-sheet';dialog.setAttribute('aria-label','Bộ lọc khám phá');
    const selected=explore.filters,range=(title,key,min,max)=>'<fieldset><legend>'+title+'</legend><div class="row">'+[['min','Từ'],['max','Đến']].map(([prefix,label])=>'<label>'+label+'<input type="number" name="'+prefix+key+'" min="'+min+'" max="'+max+'" value="'+esc(selected[prefix+key]||'')+'"></label>').join('')+'</div></fieldset>',select=(title,key,values)=>'<label>'+title+'<select name="'+key+'"><option value="">Tất cả</option>'+values.map(v=>'<option '+(selected[key]===v?'selected':'')+'>'+esc(v)+'</option>').join('')+'</select></label>';
    let fields='';if(['all','age'].includes(kind))fields+=range('Tuổi','Age',18,120);if(['all','weight'].includes(kind))fields+=range('Cân nặng (kg)','Weight',20,400);if(['all','height'].includes(kind))fields+=range('Chiều cao (cm)','Height',80,250);if(['all','gender'].includes(kind))fields+=select('Giới tính','gender',identityChoices.gender);if(kind==='all')fields+=select('Xu hướng','orientation',identityChoices.orientation);
    dialog.innerHTML='<form><div class="sheet-head"><h2>Bộ lọc khám phá</h2><button type="button" data-close aria-label="Đóng bộ lọc">'+ic('x')+'</button></div>'+fields+'<p role="status"></p><div class="row"><button type="button" data-reset>Đặt lại</button><button class="primary" type="submit">Áp dụng</button></div></form>';
    dialog.querySelector('[data-close]').onclick=()=>dialog.close();dialog.querySelector('[data-reset]').onclick=()=>{dialog.querySelectorAll('input,select').forEach(i=>i.value='');};dialog.querySelector('form').onsubmit=async e=>{e.preventDefault();const data=Object.fromEntries(new FormData(e.target));for(const key of ['Age','Height','Weight'])if(data['min'+key]&&data['max'+key]&&Number(data['min'+key])>Number(data['max'+key])){dialog.querySelector('[role=status]').textContent='Giá trị từ phải nhỏ hơn hoặc bằng giá trị đến.';return;}Object.assign(explore.filters,data);dialog.close();await loadExplore();render();};dialog.addEventListener('close',()=>dialog.remove(),{once:true});document.body.append(dialog);dialog.showModal();
  }
  let aiSettings=null,aiSettingsError='';
  async function loadAISettings(){await ensureAdminModule();try{aiSettings=await api('/admin/ai');aiSettingsError='';}catch(e){aiSettings=null;aiSettingsError=e.status===404?'Máy chủ chưa nạp API AI. Cần cập nhật và khởi động lại máy chủ.':e.message;}}
  root.addEventListener('submit',async e=>{
    const form=e.target;if(!form.matches('[data-ai-credentials],[data-ai-features]'))return;e.preventDefault();if(s.me?.role!=='admin')return;const button=form.querySelector('[type=submit]'),note=form.querySelector('[role=status]');if(button.disabled)return;button.disabled=true;
    try{const data=Object.fromEntries(new FormData(form));if(form.matches('[data-ai-credentials]')){data.fallbackEnabled=form.elements.fallbackEnabled.checked;await api('/admin/ai/credentials','PATCH',data);}else await api('/admin/ai','PATCH',{adminId:s.me.id,support:form.elements.support.checked,moderation:form.elements.moderation.checked});form.querySelectorAll('[type=password]').forEach(i=>i.value='');await loadAISettings();note.textContent='Đã lưu cấu hình.';}catch(err){note.textContent=err.message;form.querySelector('[name=password]')?.setAttribute('value','');if(form.elements.password)form.elements.password.value='';}finally{button.disabled=false;}
  });

  // ---------- Render ----------
  function render() { renderView(); syncCallDock(); syncOverlayHistory(); }
  function syncCallDock(){document.querySelector('.kinnect-call-dock')?.remove();let audio=document.getElementById('kinnect-call-audio');if(!media.call){if(audio){audio.srcObject=null;audio.remove();}return;}if(!audio){audio=document.createElement('audio');audio.id='kinnect-call-audio';audio.autoplay=true;document.body.append(audio);}audio.srcObject=s.screen==='call'?null:media.call.remote||null;if(audio.srcObject)audio.play().catch(()=>{});if(s.screen==='call')return;const dock=document.createElement('div');dock.className='kinnect-call-dock';const open=document.createElement('button');open.textContent='↗ '+(media.call.person?.name||'Cuộc gọi')+' · Quay lại';open.onclick=()=>go('call');const end=document.createElement('button');end.textContent='Kết thúc';end.onclick=()=>realtimeAction('call-end');dock.append(open,end);document.body.append(dock);}

  function renderView() {
    const formSnapshots=[...app.querySelectorAll('form')].filter(f=>!f.matches('[data-comment-form],[data-community-send],[data-auth-form],[data-recovery-email]')).map(f=>({attribute:[...f.attributes].find(a=>a.name.startsWith('data-'))?.name,fields:[...f.elements].filter(e=>e.name&&e.type!=='file'&&e.type!=='password'&&e.type!=='submit').map(e=>({name:e.name,type:e.type,value:e.value,checked:e.checked}))}));
    const oldLives=new Map([...app.querySelectorAll('[data-live-peer]')].map(v=>[v.dataset.livePeer,v]));
    const oldVideo=app.querySelector('[data-short-player]'),videoState=oldVideo?{src:oldVideo.getAttribute('src'),time:oldVideo.currentTime,muted:oldVideo.muted,paused:oldVideo.paused}:null;
    const oldFocus=document.activeElement,focusAttr=[...(oldFocus?.attributes||[])].find(a=>a.name.startsWith('data-')&&a.name!=='data-value'),focusName=oldFocus?.name,focusPosition=oldFocus?.selectionStart;
    const openSections=[...app.querySelectorAll(".profile-edit-section")].map(d=>d.open);
    if(media.call?.stream&&approvedDevices.call!==media.call){approvedDevices.call=media.call;refreshApprovedDevices().then(()=>{if(s.screen==="call")render();});}
    const accountMenuOpen=!!app.querySelector('.pc-account-menu[open]');
    const oldScreen = app.dataset.screen, historyEl = app.querySelector(".v2-message-history"), historyTop = historyEl?.scrollTop || 0, atBottom = !historyEl || historyEl.scrollHeight-historyEl.scrollTop-historyEl.clientHeight<70;
    const scrollKey=e=>e.tagName+'.'+[...e.classList].filter(c=>!/^(active|open|is-)/.test(c)).sort().join('.'),innerTops=[...app.querySelectorAll('main *, .v2-sheet *, dialog *')].filter(e=>e.scrollTop>0).map(e=>{const k=scrollKey(e);return [k,[...app.querySelectorAll(e.tagName)].filter(x=>scrollKey(x)===k).indexOf(e),e.scrollTop];});const shellTop=app.querySelector(".shell")?.scrollTop || 0,mainTop=app.querySelector('main')?.scrollTop||0,pageTop=window.scrollY,pageLeft=window.scrollX;
    const imageSizes=new Map([...app.querySelectorAll('.post-media-real img')].filter(img=>img.naturalWidth&&img.naturalHeight).map(img=>[img.getAttribute('src'),{width:img.naturalWidth,height:img.naturalHeight}]));
    const active=document.activeElement, focusedChat=active?.matches?.("[data-community-draft]"), selection=focusedChat?active.selectionStart:null;
    app.classList.toggle("v2-inbox-mode", s.screen === "inbox");
    app.classList.toggle("v2-media-mode", ["studio","call","video"].includes(s.screen)||(s.screen==="live"&&!!media.room));
    app.dataset.device = s.device;
    app.classList.toggle("approved-compose-mode",!!s.composer);
    app.dataset.screen = s.screen;
    app.dataset.storeStyle=s.me?.storeStyle||'';
    app.dataset.theme = localStorage.getItem("kinnect-v2-theme") || "auto";
    // Keep the live video elements mounted while call controls/status change.
    if(s.screen==='call'&&oldScreen==='call'&&media.call&&app.querySelector('.v2-call-stage')){
      const template=document.createElement('template');template.innerHTML=callScreen();
      for(const selector of ['.v2-call-identity','.v2-call-controls']){const old=app.querySelector(selector),next=template.content.querySelector(selector);if(old&&next){if(selector==='.v2-call-identity'){const clock=old.querySelector('[data-call-clock]')?.textContent||'';next.querySelector('[data-call-clock]').textContent=clock;}if(old.outerHTML!==next.outerHTML)old.replaceWith(next);}}
      attachMedia();return;
    }
    const auth = authScreens.includes(s.screen);
    app.classList.toggle("postlogin-polish", !!s.me && !auth && s.screen !== "loading");
    app.classList.toggle("auth-mode", auth);
    if (s.screen === "loading") { app.innerHTML = loading("Đang mở Kinnect…"); return; }
    if (auth) {
      const view = { login: loginScreen, signup: signupScreen, forgotPassword: forgotScreen, oauthComplete:oauthCompleteScreen, oauth2fa:()=>plusModule?plusModule.renderOauth2faScreen({authHead,authBanner,authFormError,authField,submitBtn,btn}):loading(), forgotSupport:forgotSupportScreen, maintenance:maintenanceScreen }[s.screen];
      const focused = document.activeElement?.dataset?.authInput, pos = document.activeElement?.selectionStart;
      app.innerHTML = authFrame(view());
      if (focused) { const el = app.querySelector(`[data-auth-input="${focused}"]`); if (el) { el.focus({ preventScroll: true }); try { el.setSelectionRange(pos, pos); } catch {} } }
      return;
    }
    if (!s.me) return;
    const view = screens[s.screen] || (()=>emptyState("circle-help","Không tìm thấy trang","Chọn một mục trong thanh điều hướng để tiếp tục."));
    app.innerHTML = header() + `<div class="shell">${sideNav()}<main>${s.error&&s.screen!=="feed"?'<p class="kn-error" role="alert">'+esc(s.error)+'</p>':""}${s.composer?composerSheet():view()}${noticeBar()}</main></div>` + bottomNav() + (s.logoutConfirm ? '<div class="kn-backdrop"></div>' + logoutSheet() : "") + "" + (s.editProfile && !["editProfilePage","profilePreview"].includes(s.screen) ? editProfileSheet() : "")+(s.emojiTarget?emojiSheet():"")+(s.sharePost?shareSheet():"")+(s.reactors?reactorsSheet():"")+(s.reportTarget?reportSheet():"")+liveQuickCard()+storyViewersSheet()+forwardMessageSheet()+(media.tool==='Âm thanh'?musicPicker():'');
    for (const control of app.querySelectorAll("button[aria-label], summary[aria-label]")) { if (!control.hasAttribute("title")) control.title = control.getAttribute("aria-label"); }
    if(accountMenuOpen&&oldScreen===s.screen){const menu=app.querySelector('.pc-account-menu');if(menu)menu.open=true;}
    if(oldScreen===s.screen){for(const img of app.querySelectorAll('.post-media-real img')){const size=imageSizes.get(img.getAttribute('src'));if(size){img.width=size.width;img.height=size.height;img.style.height='auto';}}app.querySelector('.shell')?.scrollTo(0,shellTop);app.querySelector('main')?.scrollTo(0,mainTop);window.scrollTo({left:pageLeft,top:pageTop,behavior:'instant'});innerTops.forEach(([k,i,top])=>{const el=[...app.querySelectorAll(k.split('.')[0])].filter(x=>scrollKey(x)===k)[i];if(el)el.scrollTop=top;});}
    const log=app.querySelector(".v2-message-history");if(log)log.scrollTop=atBottom||community.scrollEnd?log.scrollHeight:historyTop;community.scrollEnd=false;
    if(oldScreen===s.screen)app.querySelectorAll(".profile-edit-section").forEach((d,i)=>{if(openSections[i]!==undefined)d.open=openSections[i];});
    app.querySelectorAll('[data-live-peer]').forEach(next=>{const old=oldLives.get(next.dataset.livePeer);if(old&&old.dataset.liveRoom===next.dataset.liveRoom)next.replaceWith(old);});bindLiveStage();paintAIStream();const liveLog=app.querySelector('.v2-live-chat-log');if(liveLog)liveLog.scrollTop=liveLog.scrollHeight;
    const author=app.querySelector('.approved-composer .post-author'),visibility=author?.querySelector('[data-composer-visibility]'),toolbar=author?.querySelector('.post-compose-toolbar-inline');if(author&&visibility&&toolbar){const box=author.getBoundingClientRect(),select=visibility.getBoundingClientRect();toolbar.style.top=(select.top-box.top)+'px';toolbar.style.right=(box.right-select.left+10)+'px';toolbar.style.height=select.height+'px';toolbar.style.bottom='auto';}
    attachMedia();
    if(oldScreen===s.screen){for(const snap of formSnapshots){const form=snap.attribute&&app.querySelector('form['+snap.attribute+']');for(const field of snap.fields){const el=[...(form?.elements||[])].find(el=>el.name===field.name&&el.type===field.type&&(el.type!=='checkbox'||el.value===field.value));if(el){el.value=field.value;if(el.type==='checkbox')el.checked=field.checked;}}}if(focusAttr){const selector='['+focusAttr.name+(focusAttr.value?'="'+CSS.escape(focusAttr.value)+'"':'')+']',el=app.querySelector(selector);if(el&&el.matches('input,textarea,select')){el.focus({preventScroll:true});try{el.setSelectionRange(focusPosition,focusPosition);}catch{}}}else if(focusName){const el=app.querySelector('[name="'+CSS.escape(focusName)+'"]');el?.focus({preventScroll:true});try{el?.setSelectionRange(focusPosition,focusPosition);}catch{}}}
    const sheet=app.querySelector('.video-comments-sheet');if(sheet){const grip=sheet.querySelector('.video-comments-grip');let startY=null;grip.addEventListener('pointerdown',e=>{startY=e.clientY;grip.setPointerCapture(e.pointerId);});grip.addEventListener('pointermove',e=>{if(startY!==null)sheet.style.transform='translateY('+Math.max(0,e.clientY-startY)+'px)';});grip.addEventListener('pointerup',e=>{if(startY!==null&&e.clientY-startY>70){media.comments=null;render();}else sheet.style.transform='';startY=null;});grip.addEventListener('pointercancel',()=>{startY=null;sheet.style.transform='';});}
    const video=app.querySelector('[data-short-player]');if(video){bindVideoPlayback(video);const same=videoState&&video.getAttribute('src')===videoState.src;video.loop=true;video.muted=same?videoState.muted:!media.sound;if(same)video.currentTime=videoState.time;if(!same||!videoState.paused)video.play().catch(()=>{video.muted=true;video.play().catch(()=>{});});}
    if(focusedChat){const el=app.querySelector("[data-community-draft]");el?.focus({preventScroll:true});if(el)el.setSelectionRange(selection,selection);}
  }

  // ---------- Actions ----------
  function updatePost(id, patch) { for (const list of [s.posts, s.profile?.posts, s.bookmarks, media.shorts]) { const p = list?.find((x) => x.id === id); if (p) Object.assign(p, patch); } }
  const videoCommentContext=id=>s.screen==='video'&&media.shorts[media.index]?.id===id;
  const withMentions=text=>esc(text).replace(/(^|\s)(@[\p{L}\p{N}_.]+)/gu,'$1<span class="mention">$2</span>');
  function commentMentionCandidates(post){const video=videoCommentContext(post),owner=video?media.shorts[media.index]?.author:findPost(post)?.author,list=[owner,...((video?media.comments:s.comments[post])||[]).map(c=>c.author),...(community.friends||[])],seen=new Set();return list.filter(u=>u?.username&&u.id!==s.me?.id&&!seen.has(u.id)&&seen.add(u.id));}
  function updateCommentMentions(input,post){const form=input.closest('form');form?.querySelector('.v2-comment-mentions')?.remove();const match=input.value.slice(0,input.selectionStart??input.value.length).match(/(?:^|\s)@([^\s@]*)$/);if(!form||!match)return;const people=commentMentionCandidates(post).filter(u=>matchesPerson(u,match[1])).slice(0,6);if(!people.length)return;const box=document.createElement('div');box.className='v2-comment-mentions';box.setAttribute('role','listbox');box.innerHTML=people.map(u=>'<button type="button" class="cursor-interaction" role="option" data-do="comment-mention" data-value="'+esc(post+'|'+u.username)+'">'+av(u,true)+'<span><b>'+esc(u.name)+'</b><small>@'+esc(u.username)+'</small></span></button>').join('');form.prepend(box);}
  function focusCommentInput(post){const input=app.querySelector(videoCommentContext(post)||!post?'[data-media-comment-input]':'[data-comment-form="'+post+'"] textarea');if(!input)return;input.focus({preventScroll:true});input.scrollIntoView({block:'nearest',behavior:'smooth'});const end=input.value.length;try{input.setSelectionRange(end,end);}catch{}}
  const commentsFor=id=>videoCommentContext(id)?media.comments:s.comments[id];
  const commentsPath=id=>(videoCommentContext(id)?'/shorts/':'/posts/')+id+'/comments';
  async function loadComments(id) {
    if(videoCommentContext(id)){media.comments=(await api(commentsPath(id))).comments;render();return;}
    try { s.comments[id] = (await api("/posts/" + id + "/comments")).comments; } catch (e) { s.comments[id] = []; toast(e.message); }
    render();
  }

  root.addEventListener("click", async (e) => {
    const link = e.target.closest("a[data-nav]");
    if (link) { e.preventDefault(); return go(link.dataset.nav); }
    if(e.target.classList?.contains("composer-sheet")||e.target.classList?.contains("kn-backdrop")){closeOverlays();render();return;}
    if((s.postMenu||s.profileMenu||community.menu||s.reactionPost)&&!e.target.closest(".v2-context-menu,.v2-chat-menu,.v2-post-reactions,[data-do=post-menu],[data-do=profile-menu],[data-do=community-menu],[data-do=post-reaction-toggle]")){s.postMenu="";s.profileMenu=false;community.menu="";s.reactionPost="";if(!e.target.closest("[data-do]")){render();return;}}
    const b = e.target.closest("[data-do]");
    if (!b) return;
    const a = b.dataset.do, v = b.dataset.value;
    if (a === "composer-close-backdrop" && e.target !== b) return;
    try {
      if(a==='approved-video-sound'||a==='video-enable-sound'){const video=app.querySelector('[data-short-player]');if(video){media.sound=a==='video-enable-sound'?true:video.muted;video.muted=!media.sound;video.play().catch(()=>{});}return;}
      if(a==='video-play-toggle'){const video=app.querySelector('[data-short-player]');if(video){if(video.paused){video.muted=!media.sound;video.play().catch(()=>{video.muted=true;video.play().catch(()=>{});});}else video.pause();}return;}
      if(a==='store-apply'){await api('/store/style','POST',{productId:v||''});s.store=await api('/store');s.me=(await api('/me')).user;render();return;}
      if(a==='store-info'){toast('Studio Pro dùng trong trình chỉnh sửa video Android.');return;}
      if(a==='wallet-unavailable'){toast('Chưa kết nối dịch vụ thanh toán và chi trả. Không phát sinh giao dịch.');return;}
      if(a==='store-filter'){s.storeFilter=v;s.storePreview='';render();return;}
      if(a==='store-preview'){s.storePreview=v;render();return;}
      if(a==='approved-interest'){explore.interest=v;render();return;}
      if(a==='approved-attach'){community.attachOpen=!community.attachOpen;render();return;}
      if(a==='approved-voice'){community.attachOpen=false;await voiceAction('voice-start');return;}

      if(a==='composer-edit-media'&&s.composer?.media){const composer=s.composer;let blob=composer.mediaBlob;if(!blob){const [header,data]=composer.media.split(',');blob=new Blob([Uint8Array.from(atob(data),c=>c.charCodeAt(0))],{type:/data:([^;]+)/.exec(header)[1]});}const edited=await reviewMediaFile(blob,'post');if(edited&&s.composer===composer){composer.mediaBlob=edited;composer.media=await readFile(edited);}render();return;}
      if(a==='media-edit'&&media.recorded){const edited=await reviewMediaFile(media.recorded,s.params.storyCamera?'story':'video');if(edited){media.recorded=edited;if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.previewURL=URL.createObjectURL(edited);}render();return;}
      if(a==='approved-review-next'){media.reviewStep=2;render();return;}
      if(a==='approved-story-text'){storiesState.stage='edit';render();return;}
      if(a==='approved-story-back'){storiesState.stage='choose';render();return;}
      if(a==='live-quick-open'){s.liveQuick={id:v};render();try{const data=await api('/users/'+encodeURIComponent(v)+'/stats');if(s.liveQuick?.id===v){s.liveQuick.data=data;render();app.querySelector('.live-quick-top button')?.focus({preventScroll:true});}}catch(err){if(s.liveQuick?.id===v){s.liveQuick.error=err.message;render();}}return;}
      if(a==='live-quick-close'){s.liveQuick=null;render();return;}
      if(a==='live-quick-detail'){s.liveQuick=null;return go('profile',{user:v});}
      if(a==='live-quick-follow'){const q=s.liveQuick;if(!q?.data)return;await api('/users/'+v+'/follow',q.data.user.following?'DELETE':'POST',{});const data=await api('/users/'+v+'/stats');if(s.liveQuick===q){q.data=data;if(media.room?.hostId===v)media.room.following=data.user.following;render();}return;}
      if(a==='live-prepare'){media.studioMode='Live';return go('studio');}
      if(a==='live-refresh'){media.rooms=rankLiveRooms((await api('/live/rooms')).rooms);await enterTopLive();render();return;}
      if(a==='live-next'||a==='live-previous'){await switchLive(a==='live-next'?1:-1);return;}
      if(a==='live-host-mic'||a==='live-host-camera'){const tracks=a==='live-host-mic'?liveLocalStream()?.getAudioTracks():liveLocalStream()?.getVideoTracks();tracks?.forEach(t=>t.enabled=!t.enabled);render();return;}
      if(a==='live-sound'){media.liveMuted=!media.liveMuted;attachMedia();render();return;}
      if(a==='approved-live-follow'){const id=media.room?.hostId;if(id){const current=(await api('/users/'+id+'/stats')).user;const result=await api('/users/'+id+'/follow',current.following?'DELETE':'POST',{});media.room.following=result.user.following;render();}return;}
      if(a==='approved-share-live'){await navigator.clipboard.writeText(location.origin+'/?s=live&room='+encodeURIComponent(media.room.id));toast('Đã sao chép liên kết buổi live');render();return;}
      if(a==='profile-open-video'){media.feed='Đề xuất';return go('video',{video:v});}
      if(a==='discover-reset'){explore.query='';explore.interest='Tất cả';explore.tab='Dành cho bạn';explore.filters={};await loadExplore();render();return;}
      if(a==='post-reaction-toggle'){s.reactionPost=s.reactionPost===v?'':v;render();return;}
      if(a==='post-reaction-remove'){const r=await api('/posts/'+v+'/like','DELETE');updatePost(v,{liked:r.liked,likes:r.likes,myReaction:r.myReaction,reactions:r.reactions});s.reactionPost='';render();return;}
      if(a==='post-reaction'){const [id,reaction]=v.split(':');const post=findPost(id),remove=false;const r=await api('/posts/'+id+'/like',remove?'DELETE':'POST',remove?undefined:{reaction});updatePost(id,{liked:r.liked,likes:r.likes,myReaction:r.myReaction,reactions:r.reactions});s.reactionPost='';render();return;}
      if(a==='reload-update'){location.reload();return;}
      if(a==='profile-menu'){s.profileMenu=!s.profileMenu;render();return;}
      if(a==='hide-post'||a==='unhide-post'){const ids=hiddenPostIds().filter(id=>id!==v);if(a==='hide-post')ids.push(v);localStorage.setItem('kinnect-hidden-posts:'+s.me.id,JSON.stringify(ids));s.postMenu='';render();return;}
      if(a==='edit-post'||a==='post-audience'){const p=findPost(v);if(!p||p.user_id!==s.me.id)return;s.postMenu='';s.composer={editId:p.id,audienceOnly:a==='post-audience',text:p.body,media:'',existingMedia:p.media,visibility:p.visibility,busy:false,error:''};render();if(a==='edit-post')app.querySelector('[data-composer-text]')?.focus();return;}
      if(a==='post-menu'){s.postMenu=s.postMenu===v?'':v;render();return;}
      if(a==='report-open'){const [type,id]=v.split(':');s.reportTarget={type,id};s.reportReason='';s.profileMenu=false;s.postMenu='';render();return;}
      if(a==='report-close'){s.reportTarget=null;s.reportReason='';render();return;}
      if(a==='profile-block'){if(!(await knConfirm('Chặn tài khoản này? Hai bên sẽ không thể liên lạc hoặc xem nội dung của nhau.')))return;await api('/users/'+v+'/block','POST',{});s.profileMenu=false;toast('Đã chặn tài khoản');return go('feed');}
      if(a==='profile-unfriend'){if(!(await knConfirm('Huỷ kết bạn với người này?')))return;await api('/users/'+v+'/friendship','DELETE');s.profileMenu=false;await loadProfile(v);render();return;}
      if(a==='remembered-login'){try{const r=await api('/remembered/login','POST',{userId:v,...(s.auth.values.totpCode?{totpCode:s.auth.values.totpCode.trim()}:{})});return signedIn(r.user||(await api('/me')).user,'Chào mừng trở lại');}catch(err){if(err.data?.requires2fa){const acc=(s.rememberedAccounts||[]).find(u=>u.id===v);s.auth.need2fa=true;s.auth.rememberedId=v;if(acc?.username)s.auth.values.username=acc.username;s.auth.errors={totpCode:err.message};render();app.querySelector('[data-auth-input="totpCode"]')?.focus({preventScroll:true});return;}throw err;}}
      if(a==='remembered-remove'){if(!(await knConfirm('Gỡ tài khoản đã lưu khỏi thiết bị này? Tài khoản sẽ không bị xoá.')))return;await api('/remembered/'+encodeURIComponent(v),'DELETE');s.rememberedAccounts=(s.rememberedAccounts||[]).filter(u=>u.id!==v);toast('Đã gỡ tài khoản khỏi thiết bị này');return render();}
      if(a==='emoji-open'){s.emojiTarget=v;if(v.startsWith('comment:')){const id=v.slice(8),input=app.querySelector(videoCommentContext(id)?'[data-media-comment-input]':'[data-comment-form="'+id+'"] textarea');s.emojiSelection={start:input?.selectionStart,end:input?.selectionEnd};}render();return;}
      if(a==='emoji-close'){s.emojiTarget='';render();return;}
      if(a==='message-reply'){const m=community.messages.find(x=>x.id===v);if(m&&!m.recalled){community.replyTo={id:m.id,senderName:m.author?.name||(m.sender===s.me.id?'Bạn':community.chat?.name||''),body:m.body||m.attachment?.name||''};render();app.querySelector('[data-community-draft]')?.focus({preventScroll:true});}return;}
      if(a==='message-reply-cancel'){community.replyTo=null;render();return;}
      if(a==='chat-load-more'){await loadOlderChat();return;}
      if(a==='chat-search-toggle'){community.msgSearchOpen=!community.msgSearchOpen;if(!community.msgSearchOpen){community.msgSearchQuery='';community.msgSearchResults=null;}render();if(community.msgSearchOpen)app.querySelector('[data-chat-msg-query]')?.focus({preventScroll:true});return;}
      if(a==='chat-search-jump'){const el=app.querySelector('[data-message-id="'+CSS.escape(v)+'"]');if(el){el.scrollIntoView({block:'center',behavior:'smooth'});el.classList.add('v2-comment-highlight');setTimeout(()=>el.classList.remove('v2-comment-highlight'),1800);}else toast('Tin nhắn nằm ở trang cũ hơn — bấm "Xem tin nhắn cũ hơn" để tải.');return;}
      if(a==='post-bookmark'){const p=findPost(v);if(!p)return;const r=await api('/posts/'+v+'/bookmark',p.bookmarked?'DELETE':'POST',p.bookmarked?undefined:{});updatePost(v,{bookmarked:r.bookmarked});if(s.bookmarks){if(r.bookmarked){const found=findPost(v);if(found&&!s.bookmarks.some(x=>x.id===v))s.bookmarks=[found,...s.bookmarks];}else s.bookmarks=s.bookmarks.filter(x=>x.id!==v);}s.postMenu='';toast(r.bookmarked?'Đã lưu bài viết':'Đã bỏ lưu bài viết');render();return;}
      if(a==='share-repost'){if(!s.sharePost)return;const pid=s.sharePost;await api('/posts/'+pid+'/share','POST',{body:(s.shareCaption||'').trim()});s.sharePost='';s.shareCaption='';toast('Đã chia sẻ bài viết lên bảng tin');if(s.screen==='feed')await loadFeed();render();return;}
      if(a==='feed-load-more'){await loadMoreFeed();return;}
      if(a==='bookmarks-load-more'){await loadBookmarks(true);return;}
      if(a==='feed-tag'){s.feedFilter={q:'',tag:s.feedFilter?.tag===v?'':v};if(s.screen!=='feed'){await go('feed');await loadFeed();}else await loadFeed();render();return;}
      if(a==='feed-filter-clear'){s.feedFilter={q:'',tag:''};await loadFeed();render();return;}
      if(a==='composer-remove-item'&&s.composer?.mediaItems){s.composer.mediaItems.splice(Number(v),1);if(s.composer.mediaItems.length===1){s.composer.media=s.composer.mediaItems[0];s.composer.mediaItems=[];}render();return;}
      if(a==='message-edit'){const target=community.chat,m=community.messages.find(m=>m.id===v);if(!target||!m||m.sender!==s.me.id||m.recalled)return;(await ensurePlusModule()).openEditMessageDialog(m,target,{api,ic,esc,toast,loadChat,loadInbox,render});return;}
      if(a==='group-polls-open'&&community.chat?.isGroup){(await ensurePlusModule()).openGroupPollsDialog(community.chat,{api,s,ic,esc,toast,knConfirm});return;}
      if((a==='group-call-audio'||a==='group-call-video')&&community.chat?.isGroup){await (await ensurePlusModule()).startGroupCall(community.chat,a==='group-call-video'?'video':'audio',{api,ensureSocket,socketSend,toast,busy:!!(media.call||media.room)});return;}
      if(a==='2fa-copy-secret'){(await ensurePlusModule()).copyTwoFactorSecret(toast);return;}
      if(a==='message-recall'||a==='message-delete'){const target=community.chat,m=community.messages.find(m=>m.id===v);if(!target||!m)return;if(a==='message-recall'&&(m.sender!==s.me.id||m.recalled))return;const recall=a==='message-recall';if(!(await knConfirm(recall?'Thu hồi tin nhắn này với mọi người?':'Xoá tin nhắn ở phía bạn? Người khác vẫn giữ tin nhắn.')))return;await api('/chat-messages/'+(target.isGroup?'group':'direct')+'/'+encodeURIComponent(m.id)+(recall?'/recall':''),recall?'POST':'DELETE',recall?{}:undefined);await loadInbox();if(community.chat&&chatKey(community.chat)===chatKey(target))await loadChat(target);render();return;}
      if(a==='message-forward'){const source=community.chat,m=community.messages.find(m=>m.id===v);if(!m||m.recalled)return;await Promise.all([loadFriends(),loadInbox()]);const targets=[...new Map([...community.entries,...community.friends].map(u=>[chatKey(u),u])).values()];s.forwardMessage={id:m.id,source:{...source},preview:m.body||m.attachment?.name,targets,busy:false};render();return;}
      if(a==='message-forward-close'){if(!s.forwardMessage?.busy){s.forwardMessage=null;render();}return;}
      if(a==='message-forward-send'){const f=s.forwardMessage,u=f?.targets.find(u=>chatKey(u)===v);if(!f||!u||f.busy)return;f.busy=true;f.error='';render();try{const data=await api(chatPath(f.source)),m=data.messages.find(m=>m.id===f.id);if(!m||m.recalled)throw Error('Tin nhắn không còn khả dụng để chuyển tiếp.');let attachment;if(m.attachment){const response=await fetch(m.attachment.url,{credentials:'same-origin'});if(!response.ok)throw Error('Không tải được tệp đính kèm.');attachment={name:m.attachment.name,data:await readFile(await response.blob())};}await api(chatPath(u),'POST',{body:m.body||'',...(attachment?{attachment}:{})});if(s.forwardMessage===f)s.forwardMessage=null;await loadInbox();if(community.chat&&chatKey(community.chat)===chatKey(u))await loadChat(u);toast('Đã chuyển tiếp đến '+u.name);}catch(err){f.error=err.message;}finally{f.busy=false;render();}return;}
      if(a==='message-react'){if(!community.chat)return;const [id,reaction]=v.split(':');const message=community.messages.find(m=>m.id===id);if(!message)return;const r=await api('/chat-messages/'+(community.chat.isGroup?'group':'direct')+'/'+id+'/reaction','POST',{reaction:message.myReaction===reaction?null:reaction});if(message&&r?.message)Object.assign(message,r.message);render();return;}
      if(a==='emoji-choose'){if(s.emojiTarget.startsWith('comment:')){const id=s.emojiTarget.slice(8),video=videoCommentContext(id),text=(video?media.commentDraft:s.commentDrafts[id])||'',start=s.emojiSelection?.start??text.length,end=s.emojiSelection?.end??start,next=text.slice(0,start)+v+text.slice(end);if(next.length>(video?500:1000)){toast('Bình luận đã đạt giới hạn ký tự.');return;}if(video)media.commentDraft=next;else s.commentDrafts[id]=next;s.emojiTarget='';render();focusCommentInput(id);const input=app.querySelector(video?'[data-media-comment-input]':'[data-comment-form="'+id+'"] textarea');input?.setSelectionRange(start+v.length,start+v.length);return;}if(s.emojiTarget.startsWith('message:')){const id=s.emojiTarget.slice(8),message=community.messages.find(m=>m.id===id);if(community.chat&&message){const r=await api('/chat-messages/'+(community.chat.isGroup?'group':'direct')+'/'+id+'/reaction','POST',{reaction:message.myReaction===v?null:v});if(message&&r?.message)Object.assign(message,r.message);}}else if(s.emojiTarget==='chat'){community.draft+=v;community.requestId='';}else if(s.composer)s.composer.text+=v;s.emojiTarget='';render();return;}
      if(a==='comment-mention'){const [post,username]=v.split('|'),swap=t=>(t||'').replace(/(^|\s)@[^\s@]*$/,(_,space)=>space+'@'+username+' ');if(videoCommentContext(post))media.commentDraft=swap(media.commentDraft);else s.commentDrafts[post]=swap(s.commentDrafts[post]);render();focusCommentInput(post);return;}
      if(a==='comment-reply'){const [post,id]=v.split(':'),video=videoCommentContext(post),author=((video?media.comments:s.comments[post])||[]).find(c=>c.id===id)?.author,name=author?.name||author?.username||'';s.replyComments[post]=id;(s.replyNames||={})[post]=name;render();focusCommentInput(post);return;}
      if(a==='comment-cancel-reply'){delete s.replyComments[v];if(s.replyNames)delete s.replyNames[v];if(s.replyMentions)delete s.replyMentions[v];render();focusCommentInput(v);return;}
      if(a==='comment-edit'){const [post,id]=v.split(':'),c=commentsFor(post)?.find(c=>c.id===id);if(c){s.commentEditing={key:v,text:c.body};s.reactionComment='';render();app.querySelector('[data-comment-edit]')?.focus({preventScroll:true});}return;}
      if(a==='comment-edit-cancel'){s.commentEditing=null;render();return;}
      if(a==='comment-edit-save'){const [post,id]=v.split(':');if(!s.commentEditing?.text.trim()){toast('Nhập bình luận.');return;}await api(commentsPath(post)+'/'+id,'PATCH',{body:s.commentEditing.text});s.commentEditing=null;await loadComments(post);return;}
      if(a==='comment-delete'){const [post,id]=v.split(':');if(!(await knConfirm('Xoá bình luận của bạn? Các phản hồi của người khác vẫn được giữ.')))return;const r=await api(commentsPath(post)+'/'+id,'DELETE');updatePost(post,{comments:r.comments});if(s.replyComments[post]===id)delete s.replyComments[post];s.commentEditing=null;s.reactionComment='';await loadComments(post);return;}
      if(a==='comment-reaction-toggle'){s.reactionComment=s.reactionComment===v?'':v;s.reactionPost='';render();return;}
      if(a==='comment-reaction-select'){const [post,id,reaction]=v.split(':');await api(commentsPath(post)+'/'+id+'/reaction','POST',{reaction:reaction==='remove'?null:reaction});s.reactionComment='';await loadComments(post);return;}

      if(a==='story-viewers-open'){s.storyViewers={id:v};render();try{const data=await api('/stories/'+v+'/viewers');if(s.storyViewers?.id===v){s.storyViewers.viewers=data.viewers;const st=s.stories.find(st=>st.id===v);if(st)st.viewCount=data.count;render();}}catch(err){if(s.storyViewers?.id===v){s.storyViewers.error=err.message;render();}}return;}
      if(a==='story-viewers-close'){s.storyViewers=null;render();return;}
      if(a==='story-viewer-profile'){s.storyViewers=null;return go('profile',{user:v});}
      if(a==='story-camera-open'){await openStoryCamera();return;}
      if(a==='story-camera-mode'){if(media.recording)throw Error('Dừng quay trước khi đổi chế độ.');media.storyMode=v;render();return;}
      if(a==='story-camera-photo'){if(!media.fx?.canvas)throw Error('Camera chưa sẵn sàng.');const blob=await new Promise(resolve=>media.fx.canvas.toBlob(resolve,'image/jpeg',.9));if(!blob)throw Error('Chưa chụp được ảnh.');const edited=await reviewMediaFile(blob,'story');media.recorded=edited||blob;media.previewURL=URL.createObjectURL(media.recorded);stopCapture();render();return;}
      if(a==='story-camera-retake'){if(media.busy)return;if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.previewURL='';media.recorded=null;media.cameraError='';await prepareCamera();return;}
      if(a==='story-camera-close'){if(media.busy){toast('Đang xử lý tin. Vui lòng chờ.');return;}stopCapture();if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.previewURL='';media.recorded=null;storiesState.stage='choose';return go('createStory');}
      if(a==='story-camera-publish'){if(!media.recorded||media.busy)return;media.busy=true;media.storyError='';render();try{const blob=media.musicTrack?await storyWithMusic(media.recorded):media.recorded;await api('/stories','POST',{body:media.caption,media:await readFile(blob),background:'purple'});if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.previewURL='';media.recorded=null;stopCapture();media.musicTrack=null;await go('feed');toast('Đã đăng tin 24 giờ');}catch(err){media.storyError=err.message;throw err;}finally{media.busy=false;render();}return;}
      if(a==='story-create'){storiesState.stage='choose';storiesState.text='';storiesState.media='';return go('createStory');}
      if(a==='story-close')return go('feed');
      if(a==='story-open'){storiesState.storyId=v;storiesState.index=Math.max(0,s.stories.findIndex(st=>st.id===v));return go('storyView',{story:v});}
      if(a==='story-background'){storiesState.background=v;render();return;}
      if(a==='story-previous'||a==='story-next'){storiesState.index=Math.max(0,Math.min(s.stories.length-1,storiesState.index+(a==='story-next'?1:-1)));storiesState.storyId=s.stories[storiesState.index]?.id||'';await markStoryViewed();render();return;}
      if(a==='story-publish'){if(!storiesState.text.trim()&&!storiesState.media)throw Error('Nhập nội dung hoặc chọn ảnh/video.');await api('/stories','POST',{body:storiesState.text,media:storiesState.media||undefined,background:storiesState.background});storiesState.text='';storiesState.media='';await go('feed');toast('Đã đăng tin 24 giờ');render();return;}
      if(a==='story-delete'){if(!(await knConfirm('Xoá tin này?')))return;await api('/posts/'+v,'DELETE');await go('feed');return;}
      if(a==='group-role'){const [role,userId]=v.split(':');if(role==='owner'&&!await knConfirm('Chuyển quyền trưởng nhóm cho thành viên này?'))return;community.chat={...(await api('/groups/'+community.chat.id+'/roles','PATCH',{role,userId})).group,isGroup:true};render();return;}
      if(a==='group-avatar-preset'){community.chat={...(await api('/groups/'+community.chat.id+'/avatar','POST',{preset:v})).group,isGroup:true};render();return;}
      if(a==='group-remove-member'){if(!(await knConfirm('Xoá thành viên này khỏi nhóm?')))return;community.chat={...(await api('/groups/'+community.chat.id+'/members','DELETE',{userId:v})).group,isGroup:true};render();return;}
      if(a==='group-leave'){if(!(await knConfirm('Rời nhóm này?')))return;await api('/groups/'+community.chat.id+'/leave','POST',{});community.chat=null;return go('inbox');}
      if(a==='private-back'){s.profileTab='Album ảnh';s.profileAlbum=null;return go('profile',{user:s.params.user||s.me.id});}
      if(a==='device-revoke'){if(!(await knConfirm('Đăng xuất thiết bị này?')))return;await api('/me/sessions/'+v,'DELETE');profileExtras.sessions=(await api('/me/sessions')).sessions;render();return;}
      if(a==='profile-album-add'){s.composer={text:'',media:'',visibility:'public',busy:false,error:''};render();return;}
      if(a==='profile-album-open'){s.profileAlbum=v;render();return;}
      if(a==='profile-albums-back'){s.profileAlbum=null;render();return;}
      if(a==='profile-private'){return go('privateAlbum',{user:s.profile?.user?.id||s.me.id});}
      if(a==='private-request'){await api('/users/'+s.params.user+'/private/request','POST',{});await loadPrivateAlbum(s.params.user);render();return;}
      if(a==='private-decision'){const [action,id]=v.split(':');await api('/me/private/requests/'+id,'POST',{action});await loadPrivateAlbum();render();return;}
      if(a==='unblock-user'){await api('/users/'+v+'/block','DELETE');profileExtras.blocks=(await api('/blocks')).users;render();return;}
      if(a==='admin-tab'){adminState.tab=v;adminState.temporary='';if(v==='Cấu hình AI')await loadAISettings();render();return;}
      if(a==='chat-options'){openChatOptions();return;}
      if(a==='support-chat'){const result=await api('/support-account');await openCommunityChat(result.user.id);return;}
      if(a==='live-heart'){if(Date.now()-(media.reactionAt||0)>400){media.reactionAt=Date.now();socketSend({type:'live-reaction',kind:'heart'});}return;}
      if(a==='live-gifts'||a==='live-tools'){const tray=a==='live-gifts'?'gifts':'tools';media.liveTray=media.liveTray===tray?'':tray;render();return;}
      if(a==='live-free-gift'){socketSend({type:'live-reaction',kind:v});return;}
      if(a==='live-layout'){socketSend({type:'live-layout',layout:v});return;}
      if(a==='live-guests'){openLiveGuests();return;}
      if(a==='live-flip'){await flipLiveCamera();return;}
      if(a==='live-effects'&&media.fx){const d=liveDialog('Hiệu ứng Live','');d.append(media.cameraModule.effectPicker(media.fx,{dark:false}));return;}
      if(a==='live-viewers'){socketSend({type:'viewers'});return;}
      if(a==='ai-reload'){await loadAISettings();render();return;}
      if(a==='ai-test'){b.disabled=true;try{const result=await api('/admin/ai/test','POST',{provider:v});toast(result.message);}finally{b.disabled=false;}return;}
      if(a==='admin-hide-secret'){adminState.temporary='';render();return;}
      if(a==='admin-user'||a==='admin-moderate'){if(!(await knConfirm('Thực hiện thao tác quản trị này?')))return;const [action,target]=v.split(':');await api('/admin/moderate','POST',{action,target});await loadAdmin();render();return;}
      if(a==='admin-reset'||a==='admin-dismiss'){if(!(await knConfirm(a==='admin-reset'?'Cấp mật khẩu tạm và đăng xuất các thiết bị của tài khoản này?':'Đóng yêu cầu này?')))return;const r=await api('/admin/password-resets/'+v+(a==='admin-reset'?'/reset':'/dismiss'),'POST',{});if(r.temporaryPassword)adminState.temporary='@'+r.username+': '+r.temporaryPassword;await loadAdmin();render();return;}
      if(a==='admin-delete-music'){if(!(await knConfirm('Xoá âm thanh này khỏi thư viện?')))return;await api('/music','DELETE',{file:v});await loadAdmin();render();return;}
      if(a==='discover-filter'){openDiscoveryFilters(v);return;}
      if(a==='explore-tab'){explore.tab=v;await loadExplore();render();return;}
      if(a==='profile-progress-hide'){localStorage.setItem('kinnect-profile-dismiss:'+s.me.id,'1');render();return;}
      if(a==='explore-search'){await loadExplore();render();return;}
      if(a==='explore-location'){const position=await new Promise((resolve,reject)=>navigator.geolocation.getCurrentPosition(resolve,reject,{enableHighAccuracy:false,timeout:15000}));const result=await api('/me/location','PATCH',{enabled:true,latitude:position.coords.latitude,longitude:position.coords.longitude});s.me=result.user;await loadExplore();render();return;}
      if(a==='explore-disable-location'){s.me=(await api('/me/location','PATCH',{enabled:false})).user;toast('Đã tắt tìm quanh đây');render();return;}
      if(a==='v2-theme'){localStorage.setItem('kinnect-v2-theme',({'Theo hệ thống':'auto','Sáng':'light','Tối':'dark'})[v]);render();return;}
      if (await voiceAction(a))return;
      if (await pushAction(a))return;
      if (await realtimeAction(a,v))return;
      if (await mediaAction(a,v))return;
      if (await communityAction(a, v)) return;
      switch (a) {
        case "nav":
          if (v === "profile") return go("profile", { user: s.me.id });
          return go(v);
        case "back": return history.back();
        case "open-profile": s.reactors = null; return go("profile", { user: v });
        case "auth-screen":
          s.auth.errors = {}; s.auth.note = ""; s.auth.showPw = false; s.auth.animate = true; s.auth.oauth2faCode = "";
          if (v === "forgotPassword") s.auth.step = 0;
          return go(v);
        case "auth-toggle-pw":
          s.auth.showPw = !s.auth.showPw; render();
          app.querySelector("[data-auth-input=password],[data-auth-input=newPassword]")?.focus({ preventScroll: true });
          return;
        case "forgot-restart": s.auth.step = 0; s.auth.errors = {}; s.auth.note = ""; return render();
        case "ai-consent": {
          const enabled=v==='on';if(enabled&&!await knConfirm('Bật trợ lý AI? Nội dung bạn gửi và tối đa 6 tin nhắn liên quan trong cuộc trò chuyện hỗ trợ sẽ được gửi tới Cloudflare, hoặc NVIDIA khi dự phòng, để tạo câu trả lời. Không gửi mật khẩu, OTP hoặc dữ liệu nhạy cảm. Bạn có thể tắt bất cứ lúc nào và tiếp tục nhắn quản trị viên.'))return;
          await api('/me/ai-consent','POST',{enabled});await loadChat();return render();
        }
        case "logout-ask": s.logoutConfirm = true; return render();
        case "logout-cancel": s.logoutConfirm = false; return render();
        case "logout":
          await pushUnsubscribe().catch(() => {});
          await api("/logout", "POST", {});
          s.auth.values = s.auth.remember ? { username: s.me.username } : {};
          return signedOut("Bạn đã đăng xuất. Hẹn gặp lại!");
        case "like": {
          const p = findPost(v);
          const r = await api("/posts/" + v + "/like", p.liked ? "DELETE" : "POST", p.liked ? undefined : { reaction: "like" });
          updatePost(v, { liked: r.liked, likes: r.likes });
          return render();
        }
        case "show-comments":
        case "toggle-comments":
          s.openComments[v] = a === "show-comments" ? true : !s.openComments[v];
          render();
          if (s.openComments[v]) { focusCommentInput(v); if (!s.comments[v]) loadComments(v).then(() => focusCommentInput(v)); }
          return;
        case 'share':s.sharePost=v;s.shareCaption='';await loadFriends();return render();
        case 'share-close':s.sharePost='';s.shareCaption='';return render();
        case 'post-reactors':s.reactors={post:v,tab:'all',users:[],loading:true};render();try{const r=await api('/posts/'+v+'/reactions');if(s.reactors?.post===v){s.reactors.users=r.users||[];s.reactors.loading=false;}}catch(err){s.reactors=null;toast(err.message);}return render();
        case 'post-reactors-tab':if(s.reactors)s.reactors.tab=v;return render();
        case 'post-reactors-close':s.reactors=null;return render();
        case 'share-copy':try{await navigator.clipboard.writeText(location.origin+'/?s=postDetail&post='+encodeURIComponent(s.sharePost));toast('Đã sao chép liên kết');}catch{toast('Chọn và sao chép liên kết trong ô phía trên.');}return render();
        case 'share-to':await api('/users/'+v+'/messages','POST',{body:location.origin+'/?s=postDetail&post='+encodeURIComponent(s.sharePost)});s.sharePost='';toast('Đã chia sẻ qua tin nhắn');return render();
        case "delete-post":
          if (!(await knConfirm("Xoá bài viết này? Không thể hoàn tác."))) return;
          await api("/posts/" + v, "DELETE");
          s.posts = s.posts?.filter((p) => p.id !== v) ?? s.posts;
          if (s.profile?.posts) s.profile.posts = s.profile.posts.filter((p) => p.id !== v);
          if (s.bookmarks) s.bookmarks = s.bookmarks.filter((p) => p.id !== v);
          toast("Đã xoá bài viết");
          return render();
        case "compose": s.composer = { text: "", media: "", mediaItems: [], visibility: "public", busy: false, error: "" }; render(); app.querySelector("[data-composer-text]")?.focus(); return;
        case "composer-close": case "composer-close-backdrop": s.composer = null; return render();
        case "composer-submit": {
          const c = s.composer;
          if (c.busy) return;
          if (!c.text.trim() && !c.media && !(c.mediaItems?.length) && !c.existingMedia) { c.error = "Nhập nội dung hoặc chọn ảnh / video."; return render(); }
          c.busy = true; c.error = ""; render();
          try {
            const mediaPayload = c.mediaItems?.length > 1 ? { mediaItems: c.mediaItems } : (c.mediaItems?.length === 1 ? { media: c.mediaItems[0] } : (c.media ? { media: c.media } : {}));
            await api(c.editId?"/posts/"+c.editId:"/posts", c.editId?"PATCH":"POST", { body: c.text.trim(), visibility: c.visibility, ...mediaPayload });
            s.composer = null; toast(c.editId?"Đã lưu bài viết":"Đã đăng bài viết");
            if (s.screen === "feed") await loadFeed(); else if (s.screen === "profile") await loadProfile(s.profile.id); else return go("feed");
          } catch (err) { c.busy = false; c.error = err.message; }
          return render();
        }
        case "follow": {
          const u = s.profile.user;
          const r = await api("/users/" + u.id + "/follow", u.following ? "DELETE" : "POST", u.following ? undefined : {});
          s.profile.user = r.user;
          s.profile.stats.followers += r.user.following ? 1 : -1;
          return render();
        }
        case "profile-tab": s.profileTab = v;s.profileAlbum=null; return render();
        case "edit-profile": {
          const me = s.me;
          s.editProfile = { ...me, identityPublic:me.identityPublic!==false, name:me.name||'',bio:me.bio||'',city:me.city||'',birthDate:me.birthDate||'',interests:(me.interests||[]).join(', '),busy:false,error:'',custom:{},visibility:{bio:true,age:true,interests:true,city:true,lookingFor:true,occupation:true,school:true,gender:!me.gender||!!me.identityPublic,orientation:!me.orientation||!!me.identityPublic,pronouns:!me.pronouns||!!me.identityPublic,relationshipRole:!me.relationshipRole||!!me.identityPublic,...me.profileVisibility} };
          for(const key of Object.keys(identityChoices))s.editProfile.custom[key]=!!me[key]&&!identityChoices[key].includes(me[key]);
          return go('editProfilePage');
        }
        case "profile-preview": return go("profilePreview");
        case "edit-close": s.editProfile = null; return go("profile",{user:s.me.id});
        case "edit-save": {
          const ed = s.editProfile;
          if (!ed.name.trim()) { ed.error = "Tên hiển thị không được để trống."; return render(); }
          ed.busy = true; render();
          try {
            const r = await api("/me", "PATCH", { name: ed.name.trim(), bio: ed.bio, city: ed.city, birthDate:ed.birthDate,gender:ed.gender||"",orientation:ed.orientation||"",pronouns:ed.pronouns||"",relationshipRole:ed.relationshipRole||"",lookingFor:ed.lookingFor||"",occupation:ed.occupation||"",school:ed.school||"",identityPublic:ed.identityPublic!==false,profileVisibility:ed.visibility, interests: ed.interests.split(",").map((x) => x.trim()).filter(Boolean) });
            s.me = r.user; s.editProfile = null; toast("Đã lưu hồ sơ");
            await go("profile",{user:s.me.id});
          } catch (err) { ed.busy = false; ed.error = err.message; }
          return render();
        }
        case "read-all":
          await api("/notifications", "POST", {scope:"social"});
          s.notifications.filter(n=>!["message","group_message"].includes(n.kind)).forEach(n=>n.seen=1);
          await refreshCounts();
          return toast("Đã đánh dấu tất cả là đã đọc");
        case "open-notification": {
          const n = s.notifications.find((x) => x.id === v);
          if (n && !n.seen) { await api("/notifications", "POST", { ids: [n.id] }); n.seen = 1; refreshCounts(); }
          if(n?.kind==='message'||n?.kind==='missed_call')return openCommunityChat(n.actor.id);
          if(n?.kind==='group_message')return openCommunityChat(n.ref,true);
          if(n?.kind==='friend_request'){community.friendTab='Lời mời';return go('friends');}
          if(['short_like','short_comment'].includes(n?.kind)){media.feed='Đề xuất';return go('video',{video:n.ref});}
          if(n?.kind==='comment_reply'){if(n.targetKind==='short'){media.feed='Đề xuất';return go('video',{video:n.ref});}const found=await api('/posts?post='+encodeURIComponent(n.ref)).catch(()=>null);if(!found?.posts?.some(p=>p.id===n.ref)){media.feed='Đề xuất';return go('video',{video:n.ref});}return go('postDetail',{post:n.ref,comment:n.commentId||''});}
          if(['like','comment','share'].includes(n?.kind))return go('postDetail',{post:n.ref,comment:n.commentId||''});
          if(n?.kind?.startsWith('private_'))return go('privateAlbum',{user:n.kind==='private_request'?s.me.id:n.ref});
          if (n?.actor?.id) return go("profile", { user: n.actor.id });
          return render();
        }
      }
    } catch (err) {
      if(err.stale)return;
      if (err.status === 401) return signedOut("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.");
      toast(err.message);
      render();
    }
  });

  root.addEventListener("input", (e) => {
    const t = e.target;
    if(t.matches('[data-report-reason]'))s.reportReason=t.value;
    if(t.matches('[data-story-text]'))storiesState.text=t.value;
    const commentForm=t.closest('[data-comment-form]');if(commentForm&&t.name==='body'){s.commentDrafts[commentForm.dataset.commentForm]=t.value;updateCommentMentions(t,commentForm.dataset.commentForm);}
    if(t.matches('[data-admin-query]'))adminState.query=t.value;
    if(t.matches('[data-music-query]')){media.musicQuery=t.value;const el=app.querySelector('.sound-results');if(el)el.innerHTML=musicRows();}
    if(t.matches('[data-music-offset]')){media.musicOffset=Number(t.value);app.querySelector('[data-sound-offset]').textContent=soundTime(media.musicOffset);if(media.musicPreview)media.musicPreview.currentTime=media.musicOffset;}
    if(t.matches('[data-music-volume]')){media.musicVolume=Number(t.value);app.querySelector('[data-sound-music]').textContent=Math.round(media.musicVolume*100)+'%';if(media.musicPreview)media.musicPreview.volume=media.musicVolume;}
    if(t.matches('[data-original-volume]')){media.originalVolume=Number(t.value);app.querySelector('[data-sound-original]').textContent=Math.round(media.originalVolume*100)+'%';}
    if(t.matches('[data-media-caption]'))media.caption=t.value;
    if(t.matches('[data-media-live-title]'))media.liveTitle=t.value;
    if(t.matches('[data-live-chat] input'))media.liveDraft=t.value;
    if(t.matches('[data-media-comment-input]')){media.commentDraft=t.value;updateCommentMentions(t,media.shorts[media.index]?.id);}
    if(t.matches('[data-media-smooth]'))media.fx?.set({smooth:Number(t.value)});
    if(t.matches("[data-comment-edit]")&&s.commentEditing)s.commentEditing.text=t.value;
    if(t.matches("[data-explore-query]"))explore.query=t.value;
    if(t.matches("[data-top-search-input]"))explore.query=t.value;
    if(t.matches("[data-community-query]")){community.query=t.value;if(!t.value.trim())community.inboxMsgResults=[];}
    if(t.matches("[data-chat-msg-query]"))community.msgSearchQuery=t.value;
    if(t.matches("[data-feed-query]")){s.feedFilter={...(s.feedFilter||{q:'',tag:''}),q:t.value};}
    if(t.matches("[data-share-caption]"))s.shareCaption=t.value;
    if(t.matches("[data-community-draft]")){community.draft=t.value;community.requestId='';if(community.chat?.isGroup){app.querySelector('.v2-group-mentions')?.remove();const html=groupMentions(),f=t.closest('form');if(html&&f)f.insertAdjacentHTML('beforebegin',html);}}
    if(t.matches("[data-community-group-name]"))community.groupName=t.value;
    if (t.dataset.authInput) {
      const k = t.dataset.authInput;
      s.auth.values[k] = t.value;
      if (k === "username" || k === "password") s.auth.rememberedId = "";
      if (s.auth.errors[k]) { delete s.auth.errors[k]; const f = t.closest(".auth-field"); f.classList.remove("has-error"); t.removeAttribute("aria-invalid"); f.querySelector(".auth-error")?.remove(); }
    }
    if (t.matches("[data-composer-text]") && s.composer) s.composer.text = t.value;
    if (t.dataset.edit && s.editProfile) s.editProfile[t.dataset.edit] = t.value;
  });
  root.addEventListener("change", async (e) => {
    const t = e.target;
    if(t.matches('[data-approved-dm]')){try{s.me=(await api('/me','PATCH',{dmMode:t.value})).user;}catch(err){toast(err.message);}render();return;}
    if(t.matches('[data-approved-radius]')){explore.radius=Number(t.value);await loadExplore();render();return;}
    if(t.matches('[data-approved-camera]')){if(media.recording){toast('Dừng quay trước khi đổi camera.');render();return;}media.facing=t.value;await prepareCamera();render();return;}
    if(t.dataset.approvedDevice){try{await changeApprovedDevice(t.dataset.approvedDevice,t.value);}catch(err){toast(err.message);render();}return;}
    if(t.matches('[data-approved-intent]')&&s.editProfile){const values=new Set((s.editProfile.lookingFor||'').split(',').map(x=>x.trim()).filter(Boolean));t.checked?values.add(t.dataset.approvedIntent):values.delete(t.dataset.approvedIntent);s.editProfile.lookingFor=[...values].join(', ');return;}
    if(t.matches('[data-approved-intent-custom]')&&s.editProfile){s.editProfile.lookingFor=[...(s.editProfile.lookingFor||'').split(',').map(x=>x.trim()).filter(x=>identityChoices.lookingFor.includes(x)),t.value.trim()].filter(Boolean).join(', ');return;}
    if(t.matches('[data-own-music]')&&t.files[0]){if(t.files[0].size>15*1024*1024){toast('Âm thanh tối đa 15 MB.');render();return;}stopMusicPreview();media.musicOffset=0;media.musicAudio?.pause();media.musicTrack={file:'own:'+t.files[0].name,title:t.files[0].name,url:URL.createObjectURL(t.files[0]),blob:t.files[0]};media.musicAudio=new Audio(media.musicTrack.url);media.musicAudio.loop=true;media.musicAudio.volume=media.musicVolume;const own=media.musicTrack;media.musicTracks=media.musicTracks.filter(t=>t.file!==own.file).concat(own);media.musicAudio.onloadedmetadata=()=>{own.duration=media.musicAudio.duration;if(media.tool==='Âm thanh')render();};render();return;}
    if(t.matches('[data-story-file]')&&t.files[0]){try{const file=t.files[0];if(!['image/png','image/jpeg','image/webp','video/mp4'].includes(file.type))throw Error('Chọn ảnh hoặc video MP4 hợp lệ.');const edited=await reviewMediaFile(file,'story');if(edited)await openStoryCamera(edited);}catch(err){toast(err.message);render();}return;}
    if(t.dataset.notificationPref){const pref=notificationPreferences();if(t.dataset.notificationPref==='enabled'&&t.checked){if(!('Notification' in window)||await Notification.requestPermission()!=='granted'){t.checked=false;toast('Trình duyệt chưa cho phép thông báo.');render();return;}}pref[t.dataset.notificationPref]=t.checked;localStorage.setItem('kinnect-v2-notifications-'+s.me.id,JSON.stringify(pref));return;}
    if(t.matches('[data-group-avatar]')&&t.files[0]){const file=t.files[0];try{if(file.size>1024*1024)throw Error('Ảnh nhóm tối đa 1 MB.');community.chat={...(await api('/groups/'+community.chat.id+'/avatar','POST',{data:await readFile(file)})).group,isGroup:true};render();}catch(err){toast(err.message);}return;}
    if(t.matches('[data-private-photo]')&&t.files[0]){try{const file=t.files[0];if(file.size>4*1024*1024)throw Error('Ảnh tối đa 4 MB.');await api('/me/private-photos','POST',{data:await readFile(file)});await loadPrivateAlbum();render();}catch(err){toast(err.message);render();}return;}
    if(t.dataset.editVisible&&s.editProfile){s.editProfile.visibility[t.dataset.editVisible]=t.checked;return;}
    if(t.dataset.editSelect&&s.editProfile){const key=t.dataset.editSelect;s.editProfile.custom[key]=t.value==='__custom__';s.editProfile[key]=t.value==='__custom__'?'':t.value;render();return;}
    if(t.dataset.editInterest&&s.editProfile){const e=s.editProfile,values=e.interests.split(',').map(x=>x.trim()).filter(Boolean),value=t.dataset.editInterest;e.interests=t.checked?[...new Set([...values,value])].join(', '):values.filter(v=>v.toLowerCase()!==value.toLowerCase()).join(', ');render();return;}
    if(t.matches('[data-media-soft]'))media.fx?.set({soft:t.checked});
    if(t.matches('[data-story-camera-file]')&&t.files[0]){const file=t.files[0],photo=file.type.startsWith('image/');if(!['image/png','image/jpeg','image/webp','video/mp4'].includes(file.type)){toast('Chọn ảnh PNG/JPEG/WebP hoặc video MP4 hợp lệ.');return;}const edited=await reviewMediaFile(file,'story');if(!edited){render();return;}stopCapture();if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.recorded=edited;media.previewURL=URL.createObjectURL(edited);render();return;}
    if(t.matches('[data-media-upload]')&&t.files[0]){const file=t.files[0];if(file.type!=='video/mp4'){toast('Chọn video MP4 hợp lệ.');render();return;}try{const edited=await chooseVideoPath(file);if(!edited){render();return;}if(media.previewURL)URL.revokeObjectURL(media.previewURL);media.recorded=edited;media.previewURL=URL.createObjectURL(edited);render();}catch(err){toast(err.message);render();}}
    if(t.dataset.v2Setting){try{s.me=(await api('/me','PATCH',{[t.dataset.v2Setting]:t.checked})).user;render();}catch(err){toast(err.message);render();}return;}
    if(t.dataset.communityMember){const id=t.dataset.communityMember;community.selected=t.checked?[...new Set([...community.selected,id])]:community.selected.filter(x=>x!==id);render();}
    if(t.matches("[data-community-file]")&&t.files[0]){try{const f=t.files[0];if(f.size>20*1024*1024)throw Error("Tệp tối đa 20 MB.");community.attachment={name:f.name,data:await readFile(f)};community.requestId='';community.attachOpen=false;render();}catch(err){toast(err.message);render();}}
    if (t.dataset.authCheck === "remember") s.auth.remember = t.checked;
    if (t.dataset.authCheck === "agree") { s.auth.agree = t.checked; if (t.checked && s.auth.errors.agree) { delete s.auth.errors.agree; render(); } }
    if (t.matches("[data-composer-visibility]") && s.composer) s.composer.visibility = t.value;
    if (t.matches("[data-composer-file]") && s.composer && t.files.length) {
      const files = [...t.files];
      if (files.length > 1) {
        if (files.length > 10) { s.composer.error = "Album bài viết tối đa 10 ảnh."; return render(); }
        if (files.some(f => !['image/png','image/jpeg','image/webp'].includes(f.type))) { s.composer.error = "Album nhiều tệp chỉ hỗ trợ ảnh PNG/JPEG/WebP."; return render(); }
        try {
          const composer = s.composer;
          const urls = await Promise.all(files.map(f => readFile(f)));
          if (s.composer === composer) { composer.mediaItems = urls; composer.media = ''; composer.error = ''; }
          render();
        } catch (err) { if (s.composer) s.composer.error = err.message; render(); }
      } else {
        const f = files[0];
        if (!['image/png','image/jpeg','image/webp','video/mp4'].includes(f.type)) { s.composer.error = "Chọn ảnh hoặc video MP4 hợp lệ."; return render(); }
        try{const composer=s.composer,edited=await reviewMediaFile(f,'post');if(edited&&s.composer===composer){composer.mediaBlob=edited;composer.media=await readFile(edited);composer.mediaItems=[];composer.error='';}render();}catch(err){if(s.composer)s.composer.error=err.message;render();}
      }
    }
    if ((t.matches("[data-avatar-file]") || t.matches("[data-cover-file]")) && t.files[0]) {
      const f = t.files[0];
      if (f.size > 1024 * 1024) { s.editProfile.error = "Ảnh phải nhỏ hơn 1 MB."; return render(); }
      try {
        const r = await api(t.matches("[data-cover-file]") ? "/me/cover" : "/me/avatar", "POST", { data: await readFile(f) });
        s.me = r.user; toast("Đã cập nhật ảnh");
        await loadProfile(s.me.id);
      } catch (err) { s.editProfile.error = err.message; }
      render();
    }
  });
  root.addEventListener("submit", async (e) => {
    if(e.target.matches('[data-2fa-setup],[data-2fa-enable],[data-2fa-disable],[data-2fa-recovery],[data-oauth-2fa]')){e.preventDefault();await (await ensurePlusModule()).handleTwoFactorSubmit(e.target,{api,s,toast,render,signedIn});return;}
    if(e.target.matches('[data-forgot-support]')){e.preventDefault();try{const v=s.auth.values,r=await api('/password-reset','POST',{username:v.username,contact:v.contact,note:v.note||''});s.auth.note=r.message;s.auth.errors={};await go('login');}catch(err){s.auth.errors._form=err.message;render();}return;}
    if(e.target.matches('[data-oauth-complete]')){e.preventDefault();try{const r=await api('/oauth/complete','POST',{ticket:s.auth.ticket,username:s.auth.values.username,name:s.auth.values.name,agree18:e.target.elements.agree18.checked});s.auth.ticket='';await signedIn((await api('/me')).user,'Chào mừng đến Kinnect');}catch(err){s.auth.errors._form=err.message;render();}return;}
    if(e.target.matches('[data-group-rename],[data-group-add]')){e.preventDefault();const f=new FormData(e.target);try{const id=community.chat.id;const result=e.target.matches('[data-group-rename]')?await api('/groups/'+id,'PATCH',{name:f.get('name')}):await api('/groups/'+id+'/members','POST',{members:f.getAll('members')});community.chat={...result.group,isGroup:true};render();}catch(err){toast(err.message);render();}return;}
    if(e.target.matches('[data-v2-report]')){e.preventDefault();try{if(!s.reportTarget||s.reportReason.trim().length<5)throw Error('Mô tả ít nhất 5 ký tự.');await api('/reports','POST',{targetType:s.reportTarget.type,targetId:s.reportTarget.id,reason:s.reportReason.trim()});s.reportTarget=null;s.reportReason='';toast('Đã gửi báo cáo');render();}catch(err){toast(err.message);render();}return;}
    if(e.target.matches('[data-admin-search]')){e.preventDefault();try{await loadAdmin();render();}catch(err){toast(err.message);render();}return;}
    if(e.target.matches('[data-admin-music]')){e.preventDefault();const form=new FormData(e.target),file=form.get('file');try{if(!file?.size||file.size>15*1024*1024)throw Error('Chọn âm thanh tối đa 15 MB.');await api('/music','POST',{title:form.get('title'),artist:form.get('artist'),license:form.get('license'),source:form.get('source'),rights:form.get('rights')==='on',data:await readFile(file)});await loadAdmin();render();}catch(err){toast(err.message);render();}return;}
    if(e.target.matches('[data-recovery-email]')){e.preventDefault();const form=new FormData(e.target);try{if(!profileExtras.challenge){const r=await api('/recovery/email/start','POST',{email:form.get('email'),password:String(form.get('password')||'')});profileExtras.challenge=r.challengeId;}else{const r=await api('/recovery/email/verify','POST',{challengeId:profileExtras.challenge,code:form.get('code')});profileExtras.email=r.email;profileExtras.challenge='';toast('Đã xác minh email.');}render();}catch(err){toast(err.message);render();}return;}
    if(e.target.matches('[data-live-chat]')){e.preventDefault();const field=e.target.elements.message;if(field.value.trim()){try{await api('/me/content-consent','POST',{});socketSend({type:'chat',text:field.value.trim()});field.value='';media.liveDraft='';}catch(err){toast(err.message);render();}}return;}
    if(e.target.matches('[data-media-comment]')){e.preventDefault();const v=media.shorts[media.index];if(v&&media.commentDraft.trim()){try{await api('/shorts/'+v.id+'/comments','POST',{body:media.commentDraft.trim(),parentId:s.replyComments[v.id]||undefined});media.commentDraft='';delete s.replyComments[v.id];media.comments=(await api('/shorts/'+v.id+'/comments')).comments;v.comments++;render();}catch(err){toast(err.message);render();}}return;}
    if(e.target.matches('[data-top-search]')){e.preventDefault();const q=e.target.querySelector('[data-top-search-input]');explore.query=q?q.value:'';await go('discover');await loadExplore();render();return;}
    if(e.target.matches('[data-explore-search]')){e.preventDefault();await loadExplore();render();return;}
    if(e.target.matches('[data-v2-password]')){e.preventDefault();const values=new FormData(e.target);if(values.get('next')!==values.get('confirm')){toast('Mật khẩu nhập lại chưa khớp.');render();return;}try{await api('/me/password','POST',{current:String(values.get('current')||''),next:values.get('next')});if(s.me)s.me.hasPassword=true;toast('Đã lưu mật khẩu');await go('security');}catch(err){toast(err.message);render();}return;}
    if(e.target.matches("[data-feed-search]")){e.preventDefault();try{const raw=(s.feedFilter?.q||'').trim();if(raw.startsWith('#'))s.feedFilter={q:'',tag:raw.slice(1)};await loadFeed();render();}catch(err){toast(err.message);render();}return;}
    if(e.target.matches("[data-chat-msg-search]")){e.preventDefault();try{const q=community.msgSearchQuery.trim();community.msgSearchResults=q&&community.chat?(await api(chatPath(community.chat)+'/search?q='+encodeURIComponent(q)+'&limit=30')).messages:[];render();}catch(err){toast(err.message);render();}return;}
    if(e.target.matches("[data-community-send],[data-community-search]")){e.preventDefault();try{if(e.target.matches("[data-community-send]"))await sendCommunityMessage();else await communityAction("community-search");}catch(err){toast(err.message);render();}return;}
    const auth = e.target.closest("[data-auth-form]");
    if (auth) { e.preventDefault(); return submitAuth(auth.dataset.authForm); }
    const cf = e.target.closest("[data-comment-form]");
    if (cf) {
      e.preventDefault();
      const id = cf.dataset.commentForm, input = cf.querySelector("textarea"), body = input.value.trim();
      if (!body) return;
      try {
        await api("/posts/" + id + "/comments", "POST", { body,parentId:s.replyComments[id]||undefined });
        s.commentDrafts[id]="";delete s.replyComments[id];
        updatePost(id, { comments: (findPost(id)?.comments || 0) + 1 });
        await loadComments(id);
        app.querySelector(`[data-comment-form="${id}"] textarea`)?.focus();
      } catch (err) { toast(err.message); render(); }
    }
  });
  document.addEventListener("keydown", (e) => {
    if(e.key==='Tab'&&s.liveQuick){const dialog=app.querySelector('.live-quick-card'),items=dialog?.querySelectorAll('button:not([disabled]),a[href],input,textarea,select');if(items?.length){const first=items[0],last=items[items.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}return;}
    if(e.key==='Enter'&&s.device==='pc'&&!e.shiftKey&&!e.isComposing&&e.keyCode!==229&&e.target.matches?.('textarea')){const form=e.target.closest('form');if(form&&!e.target.closest('.profile-edit-field')){e.preventDefault();if(e.target.value.trim())form.requestSubmit();}return;}
    if (e.key !== "Escape") return;
    if(s.screen==='video'&&s.device!=='pc'&&media.comments!==null&&!s.reactionComment&&!s.commentEditing&&!s.liveQuick){media.comments=null;render();return;}
    if(s.editProfile&&["editProfilePage","profilePreview"].includes(s.screen)){s.editProfile=null;go("profile",{user:s.me.id});return;}
    if (overlayOpen()) { closeOverlays(); render(); }
  });
  device.addEventListener("change", () => { setDevice(); render(); });

  if('serviceWorker' in navigator&&location.protocol==='https:'){navigator.serviceWorker.register('/sw.js',{updateViaCache:'none'}).then(reg=>reg.update()).catch(()=>{});}
  // Video and LIVE gestures are handled once by bindMediaSwipe.

  function syncAuthViewport(){
    const viewport=window.visualViewport;
    if(viewport&&Math.abs(viewport.scale-1)>.02)return;
    root.style.setProperty('--auth-viewport-height',Math.round(viewport?.height||innerHeight)+'px');
    if(app.classList.contains('auth-mode')&&document.activeElement?.matches('input,textarea,select'))requestAnimationFrame(()=>document.activeElement?.scrollIntoView({block:'nearest',inline:'nearest'}));
  }
  window.addEventListener('resize',syncAuthViewport);window.visualViewport?.addEventListener('resize',syncAuthViewport);syncAuthViewport();
  function syncMediaViewport(){if(innerWidth>=900){root.style.removeProperty('--media-viewport-height');return;}const viewport=window.visualViewport;if(viewport&&Math.abs(viewport.scale-1)>.02)return;root.style.setProperty('--media-viewport-height',Math.round(viewport?.height||innerHeight)+'px');}
  function keepCommentEditorVisible(){
    const field=document.activeElement,editing=field?.matches?.('[data-comment-form] textarea,[data-media-comment-input],[data-story-text],[data-media-caption],[data-composer-text]'),vp=window.visualViewport;
    if(vp&&Math.abs(vp.scale-1)>.02)return;
    const keyboard=!!editing&&innerWidth<900&&!!vp&&innerHeight-vp.height>100;
    app.classList.toggle('keyboard-editing',keyboard);root.style.setProperty('--editor-viewport-height',Math.round(vp?.height||innerHeight)+'px');
    root.style.setProperty('--editor-keyboard-inset',keyboard?Math.max(0,innerHeight-vp.height-vp.offsetTop)+'px':'0px');
    if(editing)requestAnimationFrame(()=>field.scrollIntoView({block:'nearest',inline:'nearest',behavior:'instant'}));
  }
  app.addEventListener('focusin',e=>{if(e.target.matches('textarea,[data-media-caption]')){keepCommentEditorVisible();setTimeout(keepCommentEditorVisible,300);}});
  app.addEventListener('focusout',()=>setTimeout(keepCommentEditorVisible,0));
  window.visualViewport?.addEventListener('resize',keepCommentEditorVisible);
  window.visualViewport?.addEventListener('scroll',keepCommentEditorVisible);
  window.addEventListener('resize',syncMediaViewport);window.visualViewport?.addEventListener('resize',syncMediaViewport);syncMediaViewport();
  // ---------- Boot ----------
  (async () => {
    render();
    if(new URLSearchParams(location.search).has('website-session')){app.innerHTML='';const allowed=new Set(['https://kinnect.io.vn','https://www.kinnect.io.vn']);window.addEventListener('message',async event=>{if(event.source!==window.parent||!allowed.has(event.origin)||event.data?.type!=='kinnect:check-session')return;let authenticated=false;try{authenticated=!!(await api('/me')).user;}catch{}siteSession(authenticated);event.source.postMessage({type:'kinnect:session-status',authenticated},event.origin);});return;}
    try{const health=await fetch("/health",{cache:"no-store"}).then(r=>r.json());if(health.uiVersion!=="2026-10-26-new-ui"){await go("maintenance",{},{push:false});return;}}catch{await go("maintenance",{},{push:false});return;}
    api("/oauth/providers").then((r) => { const p = r.providers; s.auth.providers = Array.isArray(p) ? p : Object.keys(p || {}).filter((k) => p[k]); if (authScreens.includes(s.screen)) render(); }).catch(() => {});
    const q = new URLSearchParams(location.search), screen = q.get("s") || (q.get("chat") || q.get("group") ? "inbox" : q.get("notification") ? "notifications" : "feed"), params = {};
    if(q.get('oauth_error'))s.auth.note='Đăng nhập mạng xã hội chưa hoàn tất. Vui lòng thử lại.';
    if(q.get('oauth')==='complete'&&q.get('ticket')){try{const pending=await api('/oauth/pending?ticket='+encodeURIComponent(q.get('ticket')));s.auth.ticket=q.get('ticket');s.auth.values={name:pending.name,username:pending.suggestedUsername};history.replaceState({},'',location.pathname);await go('oauthComplete');return;}catch(err){s.auth.note=err.message;}}
    if(q.get('oauth')==='2fa'&&q.get('code')){s.auth.oauth2faCode=q.get('code');s.auth.values={};s.auth.errors={};history.replaceState({},'',location.pathname);await ensurePlusModule();await go('oauth2fa',{},{push:false});return;}
    if (q.get("user")) params.user = q.get("user");
    if(q.get("video"))params.video=q.get("video");
    if(q.get("room"))params.room=q.get("room");
    if(q.get("post"))params.post=q.get("post");
    if(q.get('call')){media.autoAnswer=q.get('answer')==='1'?q.get('call'):null;}
    if(q.get("chat"))params.chat=q.get("chat");if(q.get("group"))params.group=q.get("group");
    try {
      const r = await api("/me");
      s.me = r.user;siteSession(!!r.user);
      startPolling();if(pushOn())pushSubscribe(false).catch(()=>{});
      history.replaceState({ screen, params }, "", location.search || "?s=feed");
      await go(authScreens.includes(screen) ? "feed" : screen, params, { push: false });
    } catch {
      siteSession(false);
      s.auth.animate = true;
      await go(authScreens.includes(screen) ? screen : "login", {}, { push: false });
    }
  })().finally(async()=>{
    await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
    // Drop a previous document's restored zoom before revealing the app.
    // Release the startup limit so pinch zoom remains available afterwards.
    const viewportMeta=document.querySelector('meta[name="viewport"]');
    viewportMeta?.setAttribute('content','width=device-width,initial-scale=1,viewport-fit=cover');
    await new Promise(resolve=>requestAnimationFrame(resolve));
    root.removeAttribute('data-booting');root.removeAttribute('aria-busy');
    document.getElementById('kinnect-boot')?.remove();
  });
})();


