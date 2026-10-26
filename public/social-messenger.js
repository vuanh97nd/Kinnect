// messenger: UI functions share live application state through explicit accessors.
export function createMessenger(context) {
function conversationMenuButton(u,refresh){
 const kind=u.isGroup?'group':'direct';
 const button=context.node('button','⋯','inbox-more secondary');button.type='button';button.setAttribute('aria-label','Tùy chọn cuộc trò chuyện với '+u.name);button.title='Tùy chọn cuộc trò chuyện';
 button.onclick=e=>{e.stopPropagation();const dialog=context.node('dialog',undefined,'more-sheet conversation-menu');dialog.setAttribute('aria-label','Tùy chọn cuộc trò chuyện với '+u.name);const head=context.node('div',undefined,'report-sheet-head');head.append(context.node('h2',u.name));const close=context.node('button','×');close.type='button';close.setAttribute('aria-label','Đóng tùy chọn cuộc trò chuyện');close.onclick=()=>dialog.close();head.append(close);dialog.append(head);
  const actions=[[u.pinned?'Bỏ ghim cuộc trò chuyện':'Ghim cuộc trò chuyện',async()=>{await context.api('/chat-preferences/'+kind+'/'+u.id,'POST',{pinned:!u.pinned});await refresh();}],[u.muted?'Bật thông báo':'Tắt thông báo',async()=>{await context.api('/chat-preferences/'+kind+'/'+u.id,'POST',{muted:!u.muted});await refresh();}],['Xóa cuộc trò chuyện',()=>clearConversation(kind,u.id)]];
  for(const [label,fn] of actions){const actionButton=context.node('button',label);actionButton.type='button';actionButton.onclick=async()=>{dialog.close();try{await fn();}catch(error){context.status(error.message);}};dialog.append(actionButton);}document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});context.showAppDialog(dialog);
 };
 return button;
}

function messengerSidebar(){const side=context.node('aside',undefined,'messenger-sidebar');side.setAttribute('aria-label','Danh sách cuộc trò chuyện');return side;}

function messengerWelcome(){const welcome=context.node('section',undefined,'messenger-welcome');welcome.innerHTML='<div class="messenger-welcome-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><path d="M21 11.5a8.5 8.5 0 01-8.5 8.5H4l-2 2V11.5a9.5 9.5 0 0119 0Z"/><path d="M7 11h.01M12 11h.01M17 11h.01"/></svg></div><h2>Một lời chào, một kết nối mới</h2><p>Chọn cuộc trò chuyện để bắt đầu.</p>';return welcome;}

function mountConversation(panel,box,selected){const side=messengerSidebar();side.dataset.selected=selected;const workspace=context.node('div',undefined,'view view-inbox');workspace.append(side,box);panel.replaceChildren(workspace);inbox(side).catch(error=>{if(side.isConnected)side.append(context.node('p',error.message,'muted'));});}

async function inbox(panel) {
  if(panel.classList.contains('view-inbox')){const side=messengerSidebar();panel.replaceChildren(side,messengerWelcome());await inbox(side);return;}

  const head=context.node('div',undefined,'view-head inbox-heading');head.append(context.screenBackButton(),context.node('h2','Tin nhắn'));
  const compose=context.node('button',undefined,'inbox-new');compose.type='button';compose.setAttribute('aria-label','Tin nhắn mới');compose.innerHTML=context.reelIcon('send');compose.onclick=()=>newMessagePicker().catch(e=>context.status(e.message));head.append(compose);const makeGroup=context.node('button','Tạo nhóm','inbox-create-group');makeGroup.type='button';makeGroup.onclick=()=>createChatGroup().catch(e=>context.status(e.message));head.append(makeGroup);panel.append(head);
  const search=context.node('input',undefined,'inbox-search');search.type='search';search.placeholder='Tìm cuộc trò chuyện';search.setAttribute('aria-label','Tìm cuộc trò chuyện');panel.append(search);
  const [{users},{groups}]=await Promise.all([context.api('/conversations'),context.api('/groups')]);
  let entries=[...users,...groups.map(g=>({...g,isGroup:true,username:'',last:g.last?{...g.last,body:(g.last.mine?'':g.last.name+': ')+g.last.body}:null}))].sort((a,b)=>Number(!!b.pinned)-Number(!!a.pinned)||(b.last?.created||b.created||0)-(a.last?.created||a.created||0));
  const filters=context.node('div',undefined,'inbox-filters');let unreadOnly=false;
  const all=context.node('button','Tất cả','active'),unread=context.node('button','Chưa đọc');all.type=unread.type='button';filters.append(all,unread);panel.append(filters);
  const list=context.node('div',undefined,'inbox-list');panel.append(list);
  function render(){
   all.classList.toggle('active',!unreadOnly);unread.classList.toggle('active',unreadOnly);all.setAttribute('aria-pressed',String(!unreadOnly));unread.setAttribute('aria-pressed',String(unreadOnly));
   const query=search.value.trim().toLocaleLowerCase('vi');const matches=entries.filter(u=>(!unreadOnly||u.unread>0)&&(!query||(u.name+' '+u.username).toLocaleLowerCase('vi').includes(query)));
   list.replaceChildren();
   for(const u of matches){
    const row=context.node('div',undefined,'inbox-row'+(u.unread?' is-unread':''));row.setAttribute('role','group');row.dataset.conversation=u.id;if(panel.dataset.selected===String(u.id)){row.classList.add('is-selected');row.setAttribute('aria-current','true');}
     const open=context.node('button',undefined,'inbox-open secondary');open.type='button';open.setAttribute('aria-label','Mở cuộc trò chuyện với '+u.name);
     const photo=context.node('div',undefined,'inbox-avatar');photo.append(u.isGroup?context.node('span','Nh','avatar group-avatar'):context.avatar(u));if(u.isActive)photo.append(context.node('span',undefined,'inbox-online'));
     const text=context.node('div',undefined,'row-text');text.append(context.node('b',u.name),context.node('span',u.last?(u.last.mine?'Bạn: ':'')+u.last.body:'Bắt đầu trò chuyện','muted'));
     const meta=context.node('div',undefined,'inbox-meta');meta.append(context.node('time',u.last?context.timeAgo(u.last.created):''));if(u.pinned){const pin=context.node('span','📌','inbox-pin');pin.setAttribute('aria-label','Đã ghim cuộc trò chuyện');meta.append(pin);}if(u.muted){const mute=context.node('span','🔕','inbox-muted');mute.setAttribute('aria-label','Đã tắt thông báo');meta.append(mute);}if(u.unread){const badge=context.node('span',u.unread>99?'99+':String(u.unread),'inbox-unread');badge.setAttribute('aria-label',u.unread+' tin nhắn chưa đọc');meta.append(badge);}
     open.append(photo,text,meta);open.onclick=()=> (u.isGroup?openGroupChat(u.id):openChat(u)).catch(e=>context.status(e.message));row.append(open,conversationMenuButton(u,()=>context.inboxRefresh?.()));list.append(row);
   }
   if(!matches.length){list.append(context.empty('💬',query?'Không tìm thấy cuộc trò chuyện':unreadOnly?'Bạn đã đọc hết tin nhắn':'Chưa có cuộc trò chuyện',query?'Thử tên khác.':unreadOnly?'Tin nhắn mới sẽ xuất hiện ở đây.':'Chọn Tin nhắn mới để bắt đầu kết nối.'));}
  }
  context.inboxRefresh=async()=>{const [{users},{groups}]=await Promise.all([context.api('/conversations'),context.api('/groups')]);if(!list.isConnected)return;entries=[...users,...groups.map(g=>({...g,isGroup:true,username:'',last:g.last?{...g.last,body:(g.last.mine?'':g.last.name+': ')+g.last.body}:null}))].sort((a,b)=>Number(!!b.pinned)-Number(!!a.pinned)||(b.last?.created||b.created||0)-(a.last?.created||a.created||0));render();};
  search.oninput=render;all.onclick=()=>{unreadOnly=false;render();};unread.onclick=()=>{unreadOnly=true;render();};render();
}

async function newMessagePicker(){
 const dialog=context.node('dialog',undefined,'group-picker recipient-picker');dialog.setAttribute('aria-label','Tin nhắn mới');
 const head=context.node('div',undefined,'report-sheet-head'),close=context.node('button','×');close.type='button';close.setAttribute('aria-label','Đóng tin nhắn mới');close.onclick=()=>dialog.close();head.append(context.node('h2','Tin nhắn mới'),close);
 const search=context.node('input');search.type='search';search.placeholder='Tên hoặc @username';search.setAttribute('aria-label','Tìm người nhận');
 const list=context.node('div',undefined,'recipient-list'),feedback=context.node('p','','report-feedback');dialog.append(head,search,list,feedback);let revision=0,delay;
 async function load(){const request=++revision;feedback.textContent='';try{const {users}=await context.api('/discover?q='+encodeURIComponent(search.value.trim().replace(/^@/,'')));if(!dialog.open||request!==revision)return;list.replaceChildren();for(const user of users){const row=context.node('button',undefined,'recipient-row');row.type='button';const text=context.node('span',undefined,'row-text');text.append(context.node('strong',user.name),context.node('small','@'+user.username));row.append(context.avatar(user),text);row.onclick=async()=>{row.disabled=true;try{dialog.close();await openChat(user);}catch(e){context.status(e.message);}};list.append(row);}if(!users.length)list.append(context.node('p','Không tìm thấy người nhận.','muted'));}catch(e){if(dialog.open&&request===revision)feedback.textContent=e.message;}}
 search.oninput=()=>{revision++;clearTimeout(delay);delay=setTimeout(load,200);};dialog.addEventListener('close',()=>{revision++;clearTimeout(delay);dialog.remove();},{once:true});document.body.append(dialog);context.showAppDialog(dialog);search.focus();await load();
}

async function memberPicker({title='Tạo nhóm',existing=[]}={}){
 const dialog=context.node('dialog',undefined,'group-picker');dialog.setAttribute('aria-label',title);const head=context.node('div',undefined,'report-sheet-head');head.append(context.node('h2',title));const close=context.node('button','×');close.type='button';close.setAttribute('aria-label','Đóng chọn thành viên');head.append(close);dialog.append(head);
 const name=context.node('input');name.placeholder='Tên nhóm';name.maxLength=80;name.setAttribute('aria-label','Tên nhóm');if(!existing.length)dialog.append(name);
 const search=context.node('input');search.type='search';search.placeholder='Tìm thành viên theo tên';search.setAttribute('aria-label','Tìm thành viên nhóm');dialog.append(search);
 const count=context.node('p','Chưa chọn thành viên','group-selection'),list=context.node('div',undefined,'group-candidates'),error=context.node('p','','report-feedback'),submit=context.node('button',title==='Tạo nhóm'?'Tạo nhóm':'Thêm thành viên','report-submit');submit.type='button';dialog.append(count,list,error,submit);const chosen=new Map();let request=0,delay;
 async function load(){const revision=++request;try{const {users}=await context.api('/discover?q='+encodeURIComponent(search.value));if(!dialog.open||revision!==request)return;list.replaceChildren();for(const u of users.filter(u=>!existing.includes(u.id))){const label=context.node('label',undefined,'group-candidate'),check=context.node('input');check.type='checkbox';check.checked=chosen.has(u.id);check.onchange=()=>{if(check.checked)chosen.set(u.id,u);else chosen.delete(u.id);count.textContent=chosen.size?'Đã chọn '+chosen.size+' thành viên':'Chưa chọn thành viên';};label.append(context.avatar(u),context.node('span',u.name),check);list.append(label);}if(!list.children.length)list.append(context.node('p','Không tìm thấy thành viên.','muted'));}catch(e){error.textContent=e.message;}}
 document.body.append(dialog);context.showAppDialog(dialog);load();search.oninput=()=>{clearTimeout(delay);delay=setTimeout(load,250);};
 return new Promise(resolve=>{dialog.addEventListener('close',()=>{clearTimeout(delay);dialog.remove();resolve(null);},{once:true});close.onclick=()=>dialog.close();submit.onclick=()=>{if(!chosen.size||(!existing.length&&!name.value.trim())){error.textContent='Nhập tên nhóm và chọn thành viên.';return;}resolve({name:name.value.trim(),members:[...chosen.keys()]});dialog.close();};});
}

async function createChatGroup(){const selected=await memberPicker();if(!selected)return;const {group}=await context.api('/groups','POST',selected);await openGroupChat(group.id);}

async function groupDetails(group){
 const dialog=context.node('dialog',undefined,'group-picker');dialog.setAttribute('aria-label','Thông tin nhóm');const head=context.node('div',undefined,'report-sheet-head');head.append(context.node('h2','Thông tin nhóm'));const close=context.node('button','×');close.type='button';close.setAttribute('aria-label','Đóng thông tin nhóm');close.onclick=()=>dialog.close();head.append(close);dialog.append(head);
 if(group.owner===context.me.id){const rename=context.node('form',undefined,'group-rename'),name=context.node('input');name.value=group.name;name.maxLength=80;name.required=true;name.setAttribute('aria-label','Đổi tên nhóm');const save=context.node('button','Lưu tên');rename.append(name,save);rename.onsubmit=async e=>{e.preventDefault();save.disabled=true;try{await context.api('/groups/'+group.id,'PATCH',{name:name.value});dialog.close();await openGroupChat(group.id);}catch(e){context.status(e.message);save.disabled=false;}};dialog.append(rename);}
 dialog.append(context.node('p',group.members.length+' thành viên','group-selection'));for(const u of group.members){const row=context.node('div',undefined,'group-candidate');row.append(context.avatar(u),context.node('span',u.name),context.node('small',u.id===group.owner?'Trưởng nhóm':''));if(group.owner===context.me.id&&u.id!==context.me.id){const remove=context.node('button','Xóa','group-remove');remove.type='button';remove.setAttribute('aria-label','Xóa '+u.name+' khỏi nhóm');remove.onclick=async()=>{if(!confirm('Xóa '+u.name+' khỏi nhóm?'))return;try{const {group:updated}=await context.api('/groups/'+group.id+'/members','DELETE',{userId:u.id});dialog.close();await openGroupChat(group.id);await groupDetails(updated);}catch(e){context.status(e.message);}};row.append(remove);}dialog.append(row);}
 if(group.owner===context.me.id){const add=context.node('button','Thêm thành viên','report-submit');add.type='button';add.onclick=async()=>{dialog.close();const selected=await memberPicker({title:'Thêm thành viên',existing:group.members.map(u=>u.id)});if(selected)try{await context.api('/groups/'+group.id+'/members','POST',selected);await openGroupChat(group.id);}catch(e){context.status(e.message);}};dialog.append(add);}
 const leave=context.node('button','Rời nhóm','group-leave');leave.type='button';leave.onclick=async()=>{if(!confirm('Rời nhóm '+group.name+'?'))return;try{await context.api('/groups/'+group.id+'/leave','POST',{});dialog.close();await context.navigate('inbox');}catch(e){context.status(e.message);}};dialog.append(leave);document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});context.showAppDialog(dialog);
}

function renderPrivateAlbumMessage(bubble,m,reload){
 const album=m.privateAlbum;if(!album||m.recalled)return false;
 const card=context.node('div',undefined,'album-chat-card');card.append(context.node('strong','Ảnh riêng tư'));
 const text=album.event==='request'?(album.owner===context.me.id?'Yêu cầu xem ảnh riêng tư của bạn':'Bạn đã gửi yêu cầu xem ảnh'):album.event==='granted'?'Đã đồng ý cho xem ảnh':album.event==='revoked'?'Đã thu hồi quyền xem':'Yêu cầu chưa được đồng ý';card.append(context.node('p',text));
 if(album.status==='pending'&&album.event==='request'&&album.owner===context.me.id){const actions=context.node('div',undefined,'album-chat-actions');for(const [label,decision] of [['Đồng ý','grant'],['Từ chối','deny']]){const button=context.action(label,async()=>{for(const b of actions.children)b.disabled=true;try{await context.api('/me/private/requests/'+album.viewer,'POST',{action:decision,requestId:album.requestId});await reload();}catch(e){context.status(e.message);await reload();for(const b of actions.children)b.disabled=false;}},decision==='grant'?'primary':'secondary');actions.append(button);}card.append(actions);}
 else if(album.status==='granted')card.append(context.action('Xem ảnh riêng tư',()=>context.navigate('profile',{user:album.owner,privateAlbum:true}),'primary'));
 else card.append(context.node('span',album.status==='pending'?'Đang chờ duyệt':album.status==='denied'?'Chưa được đồng ý':'Yêu cầu đã kết thúc','album-chat-status'));
 bubble.append(card);return true;
}

function messageControls(bubble,m,kind,reload,conversationId){
 bubble.dataset.messageId=m.id;
 const actions=context.node('div',undefined,'message-controls');
 if(!m.recalled){const react=context.node('button',undefined,'message-react');react.type='button';react.setAttribute('aria-label','Thả cảm xúc tin nhắn');react.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><path d="M8 14s1 3 4 3 4-3 4-3M8 9h.01M16 9h.01"/></svg>';react.onclick=()=>context.reactionPicker(react,m.myReaction,async reaction=>{await context.api('/chat-messages/'+kind+'/'+m.id+'/reaction','POST',{reaction});await reload();},{iconOnly:true});actions.append(react);}
 const items=[];if(!m.recalled)items.push([m.pinned?'Bỏ ghim tin nhắn':'Ghim tin nhắn',async()=>{await context.api('/chat-messages/'+kind+'/'+m.id+'/pin',m.pinned?'DELETE':'POST',{});await reload();}]);items.push(['Tắt / bật thông báo',()=>toggleChatMute(kind,conversationId)],['Xóa cuộc trò chuyện',()=>clearConversation(kind,conversationId)]);items.push(['Xóa ở phía tôi',async()=>{await context.api('/chat-messages/'+kind+'/'+m.id,'DELETE',{});await reload();}]);
 if(m.sender===context.me.id&&!m.recalled)items.unshift(['Thu hồi với mọi người',async()=>{if(!confirm('Thu hồi tin nhắn này với mọi người?'))return;await context.api('/chat-messages/'+kind+'/'+m.id+'/recall','POST',{});await reload();}]);
 const menu=context.more(items,'Tùy chọn tin nhắn');actions.append(menu);bubble.append(actions);
 const openHeld=()=>{if(m.recalled){menu.querySelector('summary').click();return;}context.reactionPicker(menu.querySelector('summary'),m.myReaction,async reaction=>{await context.api('/chat-messages/'+kind+'/'+m.id+'/reaction','POST',{reaction});await reload();},{iconOnly:true,items});};
 const quickMenu=context.node('button','⋯','message-quick-menu');quickMenu.type='button';quickMenu.setAttribute('aria-label','Mở thao tác tin nhắn');quickMenu.onclick=openHeld;bubble.append(quickMenu);
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

 if(m.pinned)bubble.prepend(context.node('span','Ghim','message-pin-label'));
 const counts=Object.entries(m.reactions||{}).filter(([,n])=>n>0);if(counts.length){const count=context.node('button',counts.map(([key,n])=>context.COMMENT_REACTIONS[key][0]+' '+n).join(' '),'message-reaction-count');count.type='button';count.setAttribute('aria-label','Cảm xúc của tin nhắn');count.onclick=()=>context.reactionPicker(count,m.myReaction,async reaction=>{await context.api('/chat-messages/'+kind+'/'+m.id+'/reaction','POST',{reaction});await reload();},{iconOnly:true});bubble.append(count);}if(m.recalled)bubble.classList.add('message-recalled');
}

async function toggleChatMute(kind,id){const current=await context.api('/chat-preferences/'+kind+'/'+id);const result=await context.api('/chat-preferences/'+kind+'/'+id,'POST',{muted:!current.muted});context.status(result.muted?'Đã tắt thông báo cuộc trò chuyện.':'Đã bật thông báo cuộc trò chuyện.');}

function pinnedMessages(box,messages){box.querySelector('.chat-pins')?.remove();const pinned=messages.filter(m=>m.pinned&&!m.recalled);if(!pinned.length)return;const strip=context.node('div',undefined,'chat-pins');for(const m of pinned){const button=context.node('button','📌 '+(m.body||m.attachment?.name||'Tệp đính kèm'));button.type='button';button.onclick=()=>{const target=box.querySelector('[data-message-id="'+m.id+'"]');target?.scrollIntoView({block:'center',behavior:'smooth'});};strip.append(button);}box.querySelector('.chat-head').after(strip);}

async function clearConversation(kind,id){if(!confirm('Xóa cuộc trò chuyện ở phía bạn? Lịch sử của người khác vẫn được giữ.'))return;await context.api(kind==='group'?'/groups/'+id+'/messages':'/users/'+id+'/messages','DELETE',{});await context.navigate('inbox');context.status('Đã xóa cuộc trò chuyện ở phía bạn.');}

function bindChatTyping(box,input,kind,targetId){
 context.stopChatTyping?.();
 const indicator=context.node('div',undefined,'chat-typing-indicator');indicator.hidden=true;indicator.setAttribute('role','status');indicator.setAttribute('aria-live','polite');
 const dots=context.node('span',undefined,'typing-dots');dots.setAttribute('aria-hidden','true');for(let i=0;i<3;i++)dots.append(context.node('i'));const text=context.node('span');indicator.append(dots,text);input.closest('form').before(indicator);
 const people=new Map();let active=false,lastSent=0,idleTimer;
 const paint=()=>{const names=[...people.values()].map(person=>person.name);indicator.hidden=!names.length;text.textContent=names.length?names.slice(0,2).join(', ')+(names.length>2?' và '+(names.length-2)+' người khác':'')+' đang soạn tin…':'';};
 const clearPeople=()=>{for(const person of people.values())clearTimeout(person.timer);people.clear();paint();};
 const stop=()=>{clearTimeout(idleTimer);if(active)context.sendTypingSignal({kind,targetId,typing:false});active=false;};
 const update=()=>{if(document.hidden||!input.value.trim()){stop();return;}const now=Date.now();if(!active||now-lastSent>=1000){if(context.sendTypingSignal({kind,targetId,typing:true})){active=true;lastSent=now;}}clearTimeout(idleTimer);idleTimer=setTimeout(stop,1800);};
 const receive=event=>{const data=event.detail;if(document.hidden||!box.isConnected||data.kind!==kind||data.conversationId!==targetId||data.userId===context.me?.id)return;const previous=people.get(data.userId);clearTimeout(previous?.timer);people.delete(data.userId);if(data.typing)people.set(data.userId,{name:data.name,timer:setTimeout(()=>{people.delete(data.userId);paint();},4000)});paint();};
 const hide=()=>{if(document.hidden){stop();clearPeople();}},disconnect=()=>{stop();clearPeople();};
 input.addEventListener('input',update);input.addEventListener('focus',update);input.addEventListener('blur',stop);input.form.addEventListener('submit',stop);window.addEventListener('kinnect-chat-typing',receive);window.addEventListener('kinnect-call-disconnected',disconnect);document.addEventListener('visibilitychange',hide);window.addEventListener('pagehide',disconnect);
 context.stopChatTyping=()=>{stop();clearPeople();input.removeEventListener('input',update);input.removeEventListener('focus',update);input.removeEventListener('blur',stop);input.form?.removeEventListener('submit',stop);window.removeEventListener('kinnect-chat-typing',receive);window.removeEventListener('kinnect-call-disconnected',disconnect);document.removeEventListener('visibilitychange',hide);window.removeEventListener('pagehide',disconnect);indicator.remove();context.stopChatTyping=null;};
}

function activityText(user){if(user.isActive)return 'Đang hoạt động';if(!user.lastActiveAt)return 'Không hiển thị hoạt động';const minutes=Math.max(1,Math.floor((Date.now()-user.lastActiveAt)/60000));return minutes<60?'Hoạt động '+minutes+' phút trước':minutes<1440?'Hoạt động '+Math.floor(minutes/60)+' giờ trước':'Hoạt động '+Math.floor(minutes/1440)+' ngày trước';}

function chatFileSize(size){return size<1024*1024?Math.ceil(size/1024)+' KB':(size/1024/1024).toFixed(1)+' MB';}

function renderChatAttachment(bubble,file){if(!file)return;const box=context.node('div',undefined,'chat-attachment');if(file.kind==='image'){const link=context.node('a');link.href=file.url;link.target='_blank';link.rel='noopener';const image=context.node('img');image.src=file.url;image.alt=file.name;image.loading='lazy';link.append(image);box.append(link);}else if(file.kind==='video'){const video=context.node('video');video.src=file.url;video.controls=true;video.playsInline=true;video.preload='metadata';box.append(video);}const download=context.node('a',undefined,'chat-file-download');download.href=file.url;download.download=file.name;download.setAttribute('aria-label','Tải xuống '+file.name);const text=context.node('span');text.append(context.node('strong',file.name),context.node('small',chatFileSize(file.size)));download.append(context.node('span','↓','chat-file-icon'),text);box.append(download);bubble.append(box);}

function chatAttachmentComposer(form,input){
 form.autocomplete='off';input.autocomplete='off';input.name='chat-message';input.enterKeyHint='send';input.setAttribute('data-lpignore','true');input.setAttribute('data-1p-ignore','true');
 input.required=false;const attach=context.node('button',undefined,'chat-attach-button');attach.type='button';attach.setAttribute('aria-label','Đính kèm ảnh, video hoặc tệp');attach.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="m8 12 6-6a3 3 0 0 1 4 4l-8 8a5 5 0 0 1-7-7l9-9"/><path d="m8 12 6-6"/></svg>';const fileInput=context.node('input');fileInput.type='file';fileInput.hidden=true;fileInput.setAttribute('aria-label','Tệp đính kèm tin nhắn');const preview=context.node('div',undefined,'chat-attachment-preview');preview.hidden=true;form.before(preview);form.prepend(attach,fileInput);let selected=null,loading=false,objectUrl=null;const clear=()=>{selected=null;fileInput.value='';preview.replaceChildren();preview.hidden=true;if(objectUrl)URL.revokeObjectURL(objectUrl);objectUrl=null;};attach.onclick=()=>fileInput.click();fileInput.onchange=async()=>{const file=fileInput.files[0];if(!file)return;clear();if(file.size>20*1024*1024){context.status('Tệp tối đa 20 MB.');return;}loading=true;attach.disabled=true;try{const data=await context.readMediaFile(file);if(!form.isConnected)return;selected={name:file.name,data};const info=context.node('span',file.name+' · '+chatFileSize(file.size));if(file.type.startsWith('image/')||file.type.startsWith('video/')){objectUrl=URL.createObjectURL(file);const media=context.node(file.type.startsWith('image/')?'img':'video');media.src=objectUrl;if(media.tagName==='VIDEO'){media.muted=true;media.playsInline=true;}preview.append(media);}const remove=context.node('button','×');remove.type='button';remove.setAttribute('aria-label','Gỡ tệp đính kèm');remove.onclick=clear;preview.append(info,remove);preview.hidden=false;}catch(e){context.status(e.message);}finally{loading=false;attach.disabled=false;}};
 return {get file(){return selected;},get loading(){return loading;},clear};
}

async function openGroupChat(id,historyMode='push'){
 if(!await context.navigate('inbox',{group:id},historyMode))return;const revision=context.navigationRevision,panel=context.$('social-panel');const {group}=await context.api('/groups/'+id);if(revision!==context.navigationRevision)return;
 const box=context.node('div',undefined,'social-card chat-box'),head=context.node('div',undefined,'chat-head'),back=context.node('button','←','icon-btn');back.type='button';back.setAttribute('aria-label','Quay lại hộp thư');back.onclick=()=>context.goBack('inbox');const info=context.node('button',undefined,'chat-who');info.type='button';const identity=context.node('div',undefined,'chat-identity');identity.append(context.node('b',group.name),context.node('span',group.members.length+' thành viên'));info.append(context.node('span','Nh','avatar group-avatar'),identity);info.setAttribute('aria-label','Thông tin nhóm');info.onclick=()=>groupDetails(group).catch(e=>context.status(e.message));head.append(back,info,context.more([['Tắt / bật thông báo',()=>toggleChatMute('group',id)],['Xóa cuộc trò chuyện',()=>clearConversation('group',id)]],'Tùy chọn cuộc trò chuyện'));
 const log=context.node('div',undefined,'dm-log');log.setAttribute('role','log');log.setAttribute('aria-live','polite');const form=context.node('form',undefined,'dm-compose'),input=context.node('input');input.placeholder='Nhắn tin cho nhóm…';input.setAttribute('aria-label','Tin nhắn nhóm');input.required=true;input.maxLength=2000;const send=context.node('button');send.type='submit';send.setAttribute('aria-label','Gửi');send.innerHTML=context.reelIcon('send');form.append(input,send);box.append(head,log,form);mountConversation(panel,box,id);const attachment=chatAttachmentComposer(form,input);context.fitChatViewport(box);bindChatTyping(box,input,'group',id);let signature='';
 async function load(){if(document.hidden)return;const {messages}=await context.api('/groups/'+id+'/messages');if(!log.isConnected||revision!==context.navigationRevision||log.querySelector('[data-holding]'))return;const next=JSON.stringify(messages);if(next===signature)return;const wasBottom=log.scrollHeight-log.clientHeight-log.scrollTop<60;const first=!signature;signature=next;pinnedMessages(box,messages);log.replaceChildren();if(!messages.length)log.append(context.node('p','Gửi lời chào đầu tiên đến nhóm.','chat-intro'));let day='';for(const m of messages){const date=new Date(m.created).toLocaleDateString('vi-VN');if(day!==date){log.append(context.node('div',date,'day-sep'));day=date;}const mine=m.sender===context.me.id,bubble=context.node('article',undefined,'bubble'+(mine?' mine':''));if(!mine)bubble.append(context.node('b',m.author.name,'group-message-author'));if(m.body)bubble.append(context.node('p',m.body));renderChatAttachment(bubble,m.attachment);bubble.append(context.node('small',context.clock(m.created)));if(mine&&!m.recalled)bubble.append(context.node('span',m.receipt?.seenCount?'Đã xem · '+m.receipt.seenCount:m.receipt?.deliveredCount?'Đã nhận · '+m.receipt.deliveredCount:'Đã gửi','message-receipt'));messageControls(bubble,m,'group',load,id);log.append(bubble);}if(first||wasBottom)log.scrollTop=log.scrollHeight;context.refreshUnread().catch(()=>{});}
 form.onsubmit=async e=>{e.preventDefault();if(send.disabled||attachment.loading)return;if(!input.value.trim()&&!attachment.file)return;send.disabled=true;try{await context.api('/groups/'+id+'/messages','POST',{body:input.value,attachment:attachment.file});input.value='';attachment.clear();await load();await context.inboxRefresh?.();log.scrollTop=log.scrollHeight;}catch(e){context.status(e.message);}finally{send.disabled=false;input.focus();}};await load();if(revision!==context.navigationRevision||!log.isConnected)return;context.timer=setInterval(()=>load().catch(e=>{clearInterval(context.timer);context.status(e.message);}),4000);
}

async function openChat(u,historyMode="push") {
  if (!await context.navigate("inbox",{chat:u.id},historyMode)) return;
  const chatRevision = context.navigationRevision;
  const panel = context.$("social-panel");
  const head = context.node("div", undefined, "chat-head");
  const back = context.node("button", "←", "icon-btn");
  back.type = "button";
  back.setAttribute("aria-label", "Quay lại hộp thư");
  back.onclick = () => context.goBack("inbox");
  const who = context.node("button", undefined, "chat-who");
  who.type = "button";
  const identity=context.node("div",undefined,"chat-identity");identity.append(context.node("b",u.name),context.node("span",activityText(u)));
  who.append(context.avatar(u),identity);
  who.onclick = () => context.navigate("profile", { user: u.id });
  const call=context.node("button",undefined,"chat-call");call.type="button";call.title="Gọi video";call.setAttribute("aria-label","Gọi video");call.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="5" width="12" height="14" rx="3"/><path d="m15 9 6-4v14l-6-4"/></svg>';call.onclick=()=>context.startVideoCall(u).catch(e=>context.status(e.message));
  const voice=context.node('button',undefined,'chat-call');voice.type='button';voice.title='Gọi thoại';voice.setAttribute('aria-label','Gọi thoại');voice.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 3h4l2 5-3 2a15 15 0 0 0 6 6l2-3 5 2v4a2 2 0 0 1-2 2C9 21 3 15 3 5a2 2 0 0 1 2-2Z"/></svg>';voice.onclick=()=>context.startVideoCall(u,'audio').catch(e=>context.status(e.message));
  head.append(back, who,voice,call, context.more([["Tắt / bật thông báo",()=>toggleChatMute('direct',u.id)],["Xóa cuộc trò chuyện",()=>clearConversation('direct',u.id)],["Báo cáo người này", () => context.report("user", u.id)]]));
  const box = context.node("div", undefined, "social-card chat-box");
  const log = context.node("div", undefined, "dm-log");
  log.setAttribute("role", "log");
  log.setAttribute("aria-live", "polite");
  const form = context.node("form", undefined, "dm-compose");
  const input = context.node("input");
  input.maxLength = 2000;
  input.required = true;
  input.placeholder = "Nhắn tin…";
  input.setAttribute("aria-label", "Tin nhắn riêng");
  const button = context.node("button", undefined);button.type="submit";button.setAttribute("aria-label","Gửi");button.innerHTML=context.reelIcon("send");
  form.append(input, button);
  box.append(head, log, form);
  mountConversation(panel,box,u.id);const attachment=chatAttachmentComposer(form,input);context.fitChatViewport(box);bindChatTyping(box,input,'direct',u.id);
  let signature = "";
  async function load() {
    if(document.hidden)return;
    const result = await context.api("/users/" + u.id + "/messages");
    if(result.user)identity.querySelector("span").textContent=activityText(result.user);
    if (context.tab !== "inbox" || !log.isConnected||log.querySelector("[data-holding]")) return;
    const next = JSON.stringify(result.messages);
    if (signature === next) return;
    signature = next;
    pinnedMessages(box,result.messages);
    log.replaceChildren();
    if(!result.messages.length){const intro=context.node("div",undefined,"chat-intro");intro.append(context.avatar(u),context.node("h3",u.name),context.node("p","Gửi lời chào để bắt đầu cuộc trò chuyện."));log.append(intro);}
    let lastDay = "";
    for (const m of result.messages) {
      const day = new Date(m.created).toLocaleDateString("vi-VN");
      if (day !== lastDay) {
        log.append(context.node("div", day === new Date().toLocaleDateString("vi-VN") ? "Hôm nay" : day, "day-sep"));
        lastDay = day;
      }
      const mine = m.sender === context.me.id;
      const bubble = context.node("article", undefined, "bubble " + (mine ? "mine" : ""));
      if(!renderPrivateAlbumMessage(bubble,m,load)&&m.body)bubble.append(context.node("p",m.body));renderChatAttachment(bubble,m.attachment);bubble.append(context.node("small",context.clock(m.created)));
      if (!mine) {
        const flag = context.node("button", "⚑", "bubble-flag");
        flag.type = "button";
        flag.setAttribute("aria-label", "Báo cáo tin nhắn");
        flag.onclick = () => context.report("message", m.id).catch((e) => context.status(e.message));
        bubble.append(flag);
      }
      if(mine&&!m.recalled){const receipt=context.node("span",m.receipt?.seenAt?"Đã xem":m.receipt?.deliveredAt?"Đã nhận":"Đã gửi","message-receipt");bubble.append(receipt);}
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
      await context.api("/users/" + u.id + "/messages", "POST", { body: input.value,attachment:attachment.file });
      input.value = "";attachment.clear();
      await load();
      await context.inboxRefresh?.();
    } catch (e) {
      context.status(e.message);
    } finally {
      button.disabled = false;
      input.focus();
    }
  };
  await load();
  context.refreshUnread().catch(()=>{});
  if (chatRevision !== context.navigationRevision || !log.isConnected) return;
  input.focus();
  context.timer = setInterval(
    () =>
      load().catch((e) => {
        clearInterval(context.timer);
        context.status(e.message);
      }),
    4000,
  );
}

  return {conversationMenuButton, messengerSidebar, messengerWelcome, mountConversation, inbox, newMessagePicker, memberPicker, createChatGroup, groupDetails, renderPrivateAlbumMessage, messageControls, toggleChatMute, pinnedMessages, clearConversation, bindChatTyping, activityText, chatFileSize, renderChatAttachment, chatAttachmentComposer, openGroupChat, openChat};
}
