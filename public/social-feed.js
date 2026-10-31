// feed: UI functions share live application state through explicit accessors.
export function createFeed(context) {
async function stories(panel) {
  const strip = context.node("div", undefined, "stories");
  strip.setAttribute("aria-label", "Tin của người đang theo dõi");
  const mine = context.node("button", undefined, "story story-me");mine.type="button";
  mine.append(context.avatar(context.me),context.node("span","+ Tạo tin"));
  mine.onclick=()=>createStory();
  strip.append(mine);panel.append(strip);
  const {stories:items}=await context.api("/stories");
  const groups=new Map();for(const item of items){if(!groups.has(item.user_id))groups.set(item.user_id,[]);groups.get(item.user_id).push(item);}
  for(const group of groups.values()){
    const u=group[0].author,b=context.node("button",undefined,"story has-story");b.type="button";b.setAttribute("aria-label","Xem tin của "+u.name);b.append(context.avatar(u),context.node("span",u.name));
    b.onclick=()=>openStory([...group].reverse());strip.append(b);
  }
}

function createStory(){
 const dialog=context.node("dialog",undefined,"story-create");dialog.setAttribute("aria-label","Tạo tin mới");
 const head=context.node("div",undefined,"story-create-head"),close=context.node("button","×");close.type="button";close.setAttribute("aria-label","Đóng tạo tin");close.onclick=()=>dialog.close();head.append(context.node("h2","Tạo tin"),close);
 const camera=context.node("button",undefined,"story-create-camera");camera.type="button";camera.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="4"/></svg><strong>Quay tin</strong><span>Camera · Nhạc · Hiệu ứng</span>';
 const photo=context.node("label",undefined,"story-create-photo");photo.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 16 5-5 4 4 3-3 6 6"/><circle cx="16" cy="9" r="1.5"/></svg><strong>Ảnh kèm nhạc</strong><span>Chọn ảnh · thêm bài hát</span>';
 const input=context.node("input");input.type="file";input.accept="image/jpeg,image/png,image/webp";input.setAttribute("aria-label","Chọn ảnh tạo tin");photo.append(input);
 camera.onclick=()=>{dialog.close();context.openCamera({story:true}).catch(e=>context.status(e.message));};
 input.onchange=()=>{const file=input.files[0];if(!file)return;dialog.close();context.openCamera({story:true,photo:file}).catch(e=>context.status(e.message));};
 dialog.append(head,camera,photo,context.node("p","Tin hiển thị 24 giờ cho những người theo dõi bạn."));dialog.addEventListener("close",()=>dialog.remove(),{once:true});document.body.append(dialog);context.showAppDialog(dialog);
}

function openStory(items){
  const dialog=context.node("dialog",undefined,"story-viewer");dialog.setAttribute("aria-label","Xem tin");let index=0;
  const close=context.node("button","×","story-close");close.type="button";close.setAttribute("aria-label","Đóng tin");close.onclick=()=>dialog.close();
  const progress=context.node("div",undefined,"story-progress");const content=context.node("div",undefined,"story-content"),bar=context.node("div",undefined,"story-viewer-tools");
  const previous=context.node("button","←"),next=context.node("button","→");previous.type=next.type="button";previous.setAttribute("aria-label","Tin trước");next.setAttribute("aria-label","Tin tiếp theo");
  const remove=context.node("button","Xóa tin");remove.type="button";
  previous.onclick=()=>{index--;paint();};next.onclick=()=>{index++;paint();};
  remove.onclick=async()=>{if(!confirm("Xóa tin này?"))return;try{await context.api("/posts/"+items[index].id,"DELETE",{});dialog.close();await context.navigate("feed");}catch(e){context.status(e.message);}};
  bar.append(previous,remove,next);dialog.append(progress,close,content,bar);document.body.append(dialog);
  function paint(){progress.replaceChildren(...items.map((_,i)=>{const segment=context.node("span");segment.classList.toggle("active",i<=index);return segment;}));for(const video of content.querySelectorAll("video"))video.pause();content.replaceChildren();const item=items[index];content.append(context.node("strong",item.author.name));if(item.media){const media=context.node(item.media.kind==="video"?"video":"img");media.src=item.media.url;if(item.media.kind==="video"){media.controls=true;media.playsInline=true;media.autoplay=true;media.muted=context.reelMuted;media.addEventListener("canplay",()=>media.play().catch(()=>{media.muted=true;media.play().catch(()=>{});}),{once:true});}else media.alt="Ảnh trong tin của "+item.author.name;content.append(media);}if(item.body)content.append(context.node("p",item.body));previous.disabled=index===0;next.disabled=index===items.length-1;remove.hidden=item.user_id!==context.me.id;}
  let startY=0;content.addEventListener("touchstart",e=>{startY=e.changedTouches[0].clientY;},{passive:true});content.addEventListener("touchend",e=>{const distance=e.changedTouches[0].clientY-startY;if(distance < -60 && index<items.length-1){index++;paint();}else if(distance>60&&index>0){index--;paint();}},{passive:true});
  dialog.addEventListener("keydown",e=>{if(["ArrowRight","ArrowDown"].includes(e.key)&&index<items.length-1){e.preventDefault();index++;paint();}else if(["ArrowLeft","ArrowUp"].includes(e.key)&&index>0){e.preventDefault();index--;paint();}});
  dialog.addEventListener("close",()=>{for(const v of content.querySelectorAll("video"))v.pause();dialog.remove();},{once:true});paint();context.showAppDialog(dialog);
}

function readMediaFile(file){
  return new Promise((resolve,reject)=>{const r=new FileReader();r.onload=()=>resolve(String(r.result));r.onerror=()=>reject(Error("Không đọc được tệp."));r.readAsDataURL(file);});
}

function composer(panel) {
  const form = context.node("form", undefined, "social-card composer");
  const row = context.node("div", undefined, "composer-row");
  const input = context.node("textarea");
  input.placeholder = context.feedSection==="confessions"?"Bạn muốn chia sẻ điều gì hôm nay?":context.feedSection==="questions"?"Bạn đang cần lời khuyên về điều gì?":"Bạn đang nghĩ gì?";
  input.maxLength = 2000;
  input.required = false;
  input.rows = 1;
  input.setAttribute("aria-label", "Nội dung bài viết");
  input.addEventListener("focus",()=>form.classList.add("composer-expanded"));
  row.append(context.avatar(context.me), input);
  const visibility = context.node("select");
  visibility.setAttribute("aria-label", "Ai có thể xem bài viết");
  for (const [value, label] of [
    ["public", "🌐 Mọi thành viên"],
    ["followers", "👥 Người theo dõi"],
  ]) {
    const o = context.node("option", label);
    o.value = value;
    visibility.append(o);
  }
  const submit = context.node("button", context.feedSection==="questions"?"Đăng câu hỏi":context.feedSection==="confessions"?"Chia sẻ tâm sự":"Chia sẻ");
  const tools = context.node("div", undefined, "composer-tools");
  const video = context.node("button", "🎬 Video", "ghost");
  video.type = "button";
  video.onclick = () => attachment.click();
  const live = context.node("button", "🔴 Live", "ghost");
  live.type = "button";
  live.onclick = () => context.navigate("live");
  const attachment=context.node("input");attachment.type="file";attachment.accept="image/jpeg,image/png,image/webp,video/mp4";attachment.hidden=true;attachment.setAttribute("aria-label","Ảnh hoặc video cho bài viết");
  const photo=context.node("button","Ảnh / Video","ghost");photo.type="button";photo.onclick=()=>attachment.click();
  const preview=context.node("div",undefined,"composer-preview");preview.hidden=true;let mediaData=null;
  attachment.onchange=async()=>{const file=attachment.files[0];if(!file)return;form.classList.add("composer-expanded");const isVideo=file.type==="video/mp4";submit.disabled=true;try{mediaData=await readMediaFile(file);preview.replaceChildren();const media=context.node(isVideo?"video":"img");media.src=mediaData;if(isVideo){media.controls=true;media.playsInline=true;}else media.alt="Ảnh đính kèm";const clear=context.node("button","Gỡ tệp","ghost");clear.type="button";clear.onclick=()=>{mediaData=null;attachment.value="";preview.replaceChildren();preview.hidden=true;};preview.append(media,clear);preview.hidden=false;}catch(e){context.status(e.message);}finally{submit.disabled=false;}};
  const storyLabel=context.node("label",undefined,"composer-story");const story=context.node("input");story.type="checkbox";story.name="story";storyLabel.append(story,document.createTextNode("Đăng vào tin · 24 giờ"));
  const category=context.node('select',undefined,'composer-category');category.setAttribute('aria-label','Mục đăng bài');for(const [value,label] of [['community','Cộng đồng'],['confessions','Tâm sự'],['questions','Hỏi đáp']]){const option=context.node('option',label);option.value=value;category.append(option);}category.value=context.feedSection==='news'?'community':context.feedSection;
  tools.append(photo, live,category, visibility, submit);
  form.append(row, preview, attachment, storyLabel, tools);
  form.onsubmit = async (e) => {
    e.preventDefault();
    submit.disabled = true;
    try {
      if(!input.value.trim()&&!mediaData)throw Error("Thêm nội dung, ảnh hoặc video trước khi đăng.");
      await context.api(story.checked ? "/stories" : "/posts", "POST", { body: input.value, visibility: visibility.value,category:category.value, media:mediaData });
      context.status("Đã đăng bài.");
      await context.navigate("feed");
    } catch (e) {
      context.status(e.message);
      submit.disabled = false;
    }
  };
  if(["confessions","questions"].includes(context.feedSection)){form.classList.add("topic-composer","composer-"+context.feedSection);const hint=context.node("p",context.feedSection==="confessions"?"Câu chuyện của bạn có thể chạm đến một người đang cần được lắng nghe.":"Thêm bối cảnh để mọi người có thể đưa ra câu trả lời hữu ích.","topic-composer-hint");form.append(hint);}
  panel.append(form);
}

function postCard(p) {
  const card = context.node("article", undefined, "social-card post"+(p.category==="confessions"?" confession-card":p.category==="questions"?" question-card":""));
  card.dataset.postId=p.id;
  const head = context.node("div", undefined, "post-head");
  const who = context.node("div", undefined, "post-who");
  const name = context.node("button", p.author.name, "name-link");
  name.type = "button";
  name.onclick = () => context.navigate("profile", { user: p.author.id });
  who.append(
    name,
    context.node("span", context.timeAgo(p.created) + " · " + (p.visibility === "followers" ? "👥 Người theo dõi" : "🌐 Mọi thành viên"), "meta"),
  );
  const options =
    p.user_id === context.me.id
      ? [["Xóa bài", async () => {
          if (!confirm("Xóa bài viết này?")) return;
          await context.api("/posts/" + p.id, "DELETE", {});
          context.status("Đã xóa bài viết.");
          card.remove();
        }, "danger-item"]]
      : [["Báo cáo bài viết", () => context.report("post", p.id)]];
  head.append(context.personLink(p.author), who, context.more(options, "Tùy chọn bài viết"));
  if(p.category&&p.category!=="community")head.append(context.node("span",({confessions:"Tâm sự",questions:"Hỏi đáp",events:"Sự kiện"})[p.category],"post-category-badge"));
  card.append(head, context.node("p", p.body, "post-body"));
  if(p.media){const media=context.node(p.media.kind==="video"?"video":"img",undefined,"post-media");media.src=p.media.url;if(p.media.kind==="video"){media.controls=true;media.playsInline=true;media.preload="metadata";}else{media.alt="Ảnh trong bài viết của "+p.author.name;media.loading="lazy";}card.append(media);}
  let likes = p.likes || 0,
    liked = !!p.liked, myReaction=p.myReaction||(p.liked?"like":null), reactions=p.reactions||{},
    count = p.comments || 0;
  const stats = context.node("div", undefined, "post-stats");
  stats.hidden = true;
  const paintStats = () => {
    comment.innerHTML = context.reelIcon("comment")+"<span>"+(p.category==="questions"?(count?count+" trả lời":"Trả lời"):p.category==="confessions"?(count?count+" chia sẻ":"Chia sẻ cảm nghĩ"):(count||"Bình luận"))+"</span>";
    comment.setAttribute("aria-label", "Bình luận" + (count ? " (" + count + ")" : ""));
  };
  const bar = context.node("div", undefined, "post-actions");
  const like = context.node("button", undefined, "act like");
  like.type = "button";
  const paintLike = () => {
    like.replaceChildren();const emoji=context.node('span',myReaction?context.COMMENT_REACTIONS[myReaction][0]:'👍','post-reaction-icon');like.append(emoji,context.node('span',myReaction?context.COMMENT_REACTIONS[myReaction][1]:'Thích'));
    stats.replaceChildren();stats.hidden=!likes;if(likes){const icons=context.node('span',Object.keys(reactions).filter(k=>reactions[k]>0).slice(0,3).map(k=>context.COMMENT_REACTIONS[k][0]).join(''),'post-reaction-summary');stats.append(icons,context.node('span',String(likes)));}
    like.setAttribute("aria-label", (liked ? "Bỏ thích" : "Thích") + (likes ? " (" + likes + ")" : ""));
    like.classList.toggle("on", liked);
    like.setAttribute("aria-pressed", String(liked));
  };
  paintLike();
  like.onclick=()=>context.reactionPicker(like,myReaction,async reaction=>{
   like.disabled=true;try{const r=await context.api('/posts/'+p.id+'/like',reaction?'POST':'DELETE',reaction?{reaction}:{});likes=r.likes;liked=r.liked;myReaction=r.myReaction;reactions=r.reactions;paintLike();paintStats();}finally{like.disabled=false;}
  });
  const comment = context.node("button", undefined, "act");
  comment.type = "button";
  paintStats();
  const thread = context.node("div", undefined, "comments");
  thread.hidden = true;
  comment.onclick = async () => {
    thread.hidden = !thread.hidden;
    if (!thread.hidden) {
      try { await loadComments(); } catch (e) { context.status(e.message); }
    }
  };
  async function loadComments() {
    const { comments } = await context.api("/posts/" + p.id + "/comments");
    thread.replaceChildren();
    const form = context.node("form", undefined, "comment-form");
    const input = context.node("input");
    input.placeholder = p.category==="questions"?"Viết câu trả lời của bạn…":"Viết bình luận…";
    input.maxLength = 1000;
    input.required = true;
    input.setAttribute("aria-label", "Viết bình luận");
    const send = context.node("button", "➤", "ghost");
    send.setAttribute("aria-label", "Gửi bình luận");
    form.append(context.avatar(context.me), input, send);
    const replyHost=context.node('div');thread.append(replyHost,form);const replyState=context.commentReplyBar(form,input);
    context.renderCommentThread(replyHost,comments,'/posts/'+p.id+'/comments',c=>replyState.reply(c),loadComments);
    form.onsubmit = async (e) => {
      e.preventDefault();
      send.disabled = true;
      try {
        await context.api("/posts/" + p.id + "/comments", "POST", { body: input.value,parentId:replyState.parentId });
        count++;
        paintStats();
        await loadComments();
        thread.querySelector(".comment-form input")?.focus();
      } catch (e) {
        context.status(e.message);
      } finally {
        send.disabled = false;
      }
    };
    thread.append(form);
  }
  bar.append(like, comment);
  if (p.user_id !== context.me.id) {
    const dm = context.action("✉", () => context.openChat(p.author), "act");
    dm.innerHTML=context.reelIcon("comment")+"<span>Nhắn tin</span>";
    dm.setAttribute("aria-label", "Nhắn tin cho " + p.author.name);
    bar.append(dm);
  }
  card.append(stats, bar, thread);
  return card;
}

function openNewsReader(article){
 const dialog=context.node('dialog',undefined,'news-reader');dialog.setAttribute('aria-label','Đọc tin tức');const bar=context.node('div',undefined,'news-reader-bar'),back=context.node('button','‹');back.type='button';back.setAttribute('aria-label','Quay lại tin tức');back.onclick=()=>dialog.close();bar.append(back,context.node('strong',article.source));const content=context.node('article',undefined,'news-reader-content');content.append(context.node('span',article.source,'news-source'),context.node('h1',article.title));if(article.publishedAt)content.append(context.node('p',new Date(article.publishedAt).toLocaleString('vi-VN'),'news-meta'));if(article.image){const image=context.node('img');image.src=article.image;image.alt='';image.referrerPolicy='no-referrer';content.append(image);}if(article.summary)content.append(context.node('p',article.summary,'news-reader-summary'));const original=context.node('a','Đọc toàn bài trên '+article.source,'news-original');original.href=article.url;const note=context.node('p','Phần giới thiệu từ RSS của '+article.source+'. Bài đầy đủ được đọc trên trang báo do nguồn không cho phép nhúng vào Kinnect.','news-reader-note');content.append(original,note);dialog.append(bar,content);document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});context.showAppDialog(dialog);
}

function newsCard(article){const card=context.node('a',undefined,'news-card');card.href=article.url;card.onclick=e=>{if(e.ctrlKey||e.metaKey||e.shiftKey||e.altKey)return;e.preventDefault();openNewsReader(article);};if(article.image){const image=context.node('img');image.src=article.image;image.alt='';image.loading='lazy';image.referrerPolicy='no-referrer';image.onerror=()=>image.remove();card.append(image);}const copy=context.node('div',undefined,'news-copy');copy.append(context.node('span',article.source,'news-source'),context.node('h3',article.title),context.node('span',article.publishedAt?context.timeAgo(article.publishedAt)+' · Đọc tin':'Đọc tin','news-meta'));card.append(copy);return card;}

async function newsPanel(panel,{preview=false}={}){
 const section=context.node('section',undefined,'news-section');section.setAttribute('aria-label','Tin tức từ báo');const heading=context.node('div',undefined,'news-heading');heading.append(context.node('h2','Tin tức'));if(preview){const all=context.node('button','Xem tất cả');all.type='button';all.onclick=()=>{context.feedSection='news';context.navigate('feed');};heading.append(all);}section.append(heading);const content=context.node('div',undefined,preview?'news-preview':'news-grid');content.textContent='Đang tải tin tức…';section.append(content);panel.append(section);
 try{const data=await context.api('/news');if(!section.isConnected)return;const articles=data.articles||[];let source='all';const filter=context.node('div',undefined,'news-filters');
 function render(){const items=articles.filter(a=>source==='all'||a.sourceId===source);content.replaceChildren(...items.slice(0,preview?3:40).map(newsCard));if(!items.length){const empty=context.node('div',undefined,'news-empty');empty.append(context.node('p','Chưa tải được tin từ báo.'));const retry=context.node('button','Thử lại');retry.type='button';retry.onclick=()=>{section.remove();newsPanel(panel,{preview});};empty.append(retry);content.append(empty);}}
 if(!preview){for(const item of [{id:'all',name:'Tất cả'},...data.sources]){const button=context.node('button',item.name,item.id==='all'?'active':'');button.type='button';button.onclick=()=>{source=item.id;for(const b of filter.children)b.classList.toggle('active',b===button);render();};filter.append(button);}heading.after(filter);}render();
 }catch{content.textContent='Chưa tải được tin tức. Bạn thử lại sau nhé.';}
}

async function feed(panel) {
 panel.append(context.node('h2','Bảng tin','sr-title'));const tabs=context.node('div',undefined,'feed-section-tabs');tabs.setAttribute('aria-label','Nội dung bảng tin');for(const [key,label] of [['community','Cộng đồng'],['confessions','Tâm sự'],['questions','Hỏi đáp'],['news','Tin tức']]){const button=context.node('button',label,context.feedSection===key?'active':'');button.type='button';button.setAttribute('aria-pressed',String(context.feedSection===key));button.onclick=()=>{context.feedSection=key;context.navigate('feed').catch(e=>context.status(e.message));};tabs.append(button);}panel.append(tabs);
 if(context.feedSection==='news'){newsPanel(panel).catch(()=>{});return;}
 if(['confessions','questions'].includes(context.feedSection)){
  const isConfession=context.feedSection==='confessions',intro=context.node('section',undefined,'topic-intro '+(isConfession?'confession-intro':'question-intro'));const icon=context.node('span',undefined,'topic-intro-icon');icon.innerHTML=isConfession?'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/></svg>':context.reelIcon('comment');const text=context.node('div');text.append(context.node('span',isConfession?'MỘT GÓC ĐỂ LẮNG NGHE':'CÙNG NHAU TÌM LỜI GIẢI','topic-eyebrow'),context.node('h2',isConfession?'Chuyện của bạn, có người nghe':'Cứ hỏi, cùng nhau tìm câu trả lời'),context.node('p',isConfession?'Niềm vui, nỗi buồn hay một điều khó nói. Chia sẻ theo cách bạn thấy thoải mái.':'Tình cảm, cuộc sống hay sở thích — trao đổi từ trải nghiệm và tôn trọng nhau.'));intro.append(icon,text);panel.append(intro);panel.classList.add(isConfession?'topic-confessions':'topic-questions');
 }

 if(context.feedSection==='community')await stories(panel).catch(()=>{});composer(panel);const {posts}=await context.api('/posts'+(context.feedSection==='community'?'':'?category='+context.feedSection));
 if(['confessions','questions'].includes(context.feedSection)){const heading=context.node('div',undefined,'topic-list-heading');heading.append(context.node('h3',context.feedSection==='confessions'?'Những câu chuyện mới':'Câu hỏi từ cộng đồng'),context.node('span',posts.length+(context.feedSection==='confessions'?' câu chuyện':' câu hỏi')));panel.append(heading);}
 if(!posts.length){const labels={community:['Bảng tin còn trống','Chia sẻ lời chào đầu tiên hoặc theo dõi thêm bạn mới.'],confessions:['Chưa có tâm sự','Chia sẻ câu chuyện, cảm xúc của bạn với cộng đồng.'],questions:['Chưa có câu hỏi','Đặt câu hỏi để cùng trao đổi và tìm lời khuyên.'],events:['Chưa có sự kiện','Chia sẻ hoạt động sắp diễn ra, thời gian và địa điểm trong bài viết.']};panel.append(context.empty('📝',...labels[context.feedSection]));}
 for(const [index,p] of posts.entries()){panel.append(postCard(p));if(index===1&&context.feedSection==='community')newsPanel(panel,{preview:true}).catch(()=>{});}if(posts.length<2&&context.feedSection==='community')newsPanel(panel,{preview:true}).catch(()=>{});
}

  return {stories, createStory, openStory, readMediaFile, composer, postCard, openNewsReader, newsCard, newsPanel, feed};
}
