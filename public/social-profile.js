// profile: UI functions share live application state through explicit accessors.
export function createProfile(context) {
function field(form, label, value, type = "text") {
  const wrapper = context.node("label", label, "form-field");
  const input = context.node(type === "textarea" ? "textarea" : "input");
  if (type !== "textarea") input.type = type;
  input.value = value;
  wrapper.append(input);
  form.append(wrapper);
  return input;
}

function profilePresets(input,title,values,{multiple=false}={}){
 if(!input.hasAttribute('aria-label'))input.setAttribute('aria-label',title);
 input.removeAttribute('list');const wrap=context.node('div',undefined,'profile-choice-wrap');input.before(wrap);wrap.append(input);
 const trigger=context.node('button',undefined,'profile-choice-trigger');trigger.type='button';trigger.setAttribute('aria-label','Chọn '+title.toLocaleLowerCase('vi'));trigger.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="m8 10 4 4 4-4"/></svg>';wrap.append(trigger);
 trigger.onclick=event=>{
  event.preventDefault();const dialog=context.node('dialog',undefined,'profile-options-sheet');dialog.setAttribute('aria-label','Chọn '+title.toLocaleLowerCase('vi'));
  const head=context.node('div',undefined,'report-sheet-head'),close=context.node('button','×');close.type='button';close.setAttribute('aria-label','Đóng danh sách');close.onclick=()=>dialog.close();head.append(context.node('h2',title),close);
  const hint=context.node('p',multiple?'Chọn tối đa 10 mục. Bạn có thể thêm sở thích riêng.':'Chọn một gợi ý hoặc tự nhập bên dưới.','profile-options-hint');
  const search=context.node('input');search.type='search';search.placeholder='Tìm trong danh sách';search.setAttribute('aria-label','Tìm lựa chọn');
  const list=context.node('div',undefined,'profile-options-list');const initial=multiple?input.value.split(',').map(v=>v.trim()).filter(Boolean):[input.value.trim()];const selected=new Set(initial.map(value=>values.find(preset=>preset.toLocaleLowerCase('vi')===value.toLocaleLowerCase('vi'))||value));
  const options=[...new Set([...values,...selected].filter(Boolean))];let rows=[];
  const custom=context.node('input');custom.placeholder=multiple?'Thêm sở thích riêng':'Tự nhập nội dung khác';custom.maxLength=multiple?30:input.maxLength>0?input.maxLength:60;custom.setAttribute('aria-label','Nội dung tùy chọn');
  const feedback=context.node('p','','report-feedback');feedback.setAttribute('role','status');const done=context.node('button','Xong','report-submit');done.type='button';
  function update(){done.textContent=multiple?'Xong'+(selected.size?' · '+selected.size+' mục':''):'Xong';for(const row of rows)row.control.checked=selected.has(row.value);}
  for(const value of ['',...options]){if(multiple&&!value)continue;const row=context.node('label',undefined,'profile-option-row'),control=context.node('input');control.type=multiple?'checkbox':'radio';control.name='profile-preset';control.value=value;control.checked=selected.has(value);control.onchange=()=>{if(multiple){if(control.checked&&selected.size>=10){control.checked=false;feedback.textContent='Chọn tối đa 10 sở thích.';return;}if(control.checked)selected.add(value);else selected.delete(value);}else{selected.clear();selected.add(value);custom.value='';}feedback.textContent='';update();};row.append(context.node('span',value||'Chưa muốn chia sẻ'),control);rows.push({row,value,control});list.append(row);}
  search.oninput=()=>{const query=search.value.trim().toLocaleLowerCase('vi');for(const item of rows)item.row.hidden=!!query&&!item.value.toLocaleLowerCase('vi').includes(query);};
  done.onclick=()=>{const typed=custom.value.trim();if(multiple){const extra=typed.split(',').map(v=>v.trim()).filter(Boolean);const all=[...new Set([...selected,...extra])];if(all.length>10){feedback.textContent='Chọn tối đa 10 sở thích.';return;}input.value=all.join(', ');}else input.value=typed||[...selected][0]||'';input.dispatchEvent(new Event('input',{bubbles:true}));dialog.close();};
  dialog.append(head,hint,search,list,custom,feedback,done);document.body.append(dialog);dialog.addEventListener('close',()=>{dialog.remove();trigger.focus();},{once:true});context.showAppDialog(dialog);update();
 };
}

async function profileConnections(user,kind){
 const title=kind==='followers'?'Người theo dõi':'Đang theo dõi',dialog=context.node('dialog',undefined,'connections-sheet');dialog.setAttribute('aria-label',title);const head=context.node('div',undefined,'report-sheet-head'),close=context.node('button','×');close.type='button';close.setAttribute('aria-label','Đóng danh sách theo dõi');close.onclick=()=>dialog.close();head.append(context.node('h2',title),close);const search=context.node('input');search.type='search';search.placeholder='Tìm theo tên';search.setAttribute('aria-label','Tìm trong danh sách theo dõi');const list=context.node('div',undefined,'connections-list');list.textContent='Đang tải…';dialog.append(head,search,list);document.body.append(dialog);dialog.addEventListener('close',()=>dialog.remove(),{once:true});context.showAppDialog(dialog);
 try{const {users}=await context.api('/users/'+user.id+'/'+kind);if(!dialog.open)return;function render(){const query=search.value.trim().toLocaleLowerCase('vi');const matches=users.filter(u=>(u.name+' '+u.username).toLocaleLowerCase('vi').includes(query));list.replaceChildren();for(const u of matches){const row=context.node('button',undefined,'connection-row');row.type='button';const copy=context.node('span',undefined,'connection-copy');copy.append(context.node('strong',u.name),context.node('small','@'+u.username));row.append(context.avatar(u),copy,context.node('span','›','connection-arrow'));row.onclick=()=>{dialog.close();context.navigate('profile',{user:u.id}).catch(e=>context.status(e.message));};list.append(row);}if(!matches.length)list.append(context.node('p',query?'Không tìm thấy tài khoản.':kind==='followers'?'Chưa có người theo dõi.':'Chưa theo dõi ai.','connections-empty'));}search.oninput=render;render();}catch(e){list.textContent=e.message;}
}

async function profilePrivateAlbum(panel,user,own){
 const revision=context.navigationRevision,section=context.node('section',undefined,'social-card private-album');section.setAttribute('aria-label','Ảnh riêng tư');
 const heading=context.node('div',undefined,'private-album-head'),title=context.node('div');title.append(context.node('h3','Ảnh riêng tư'),context.node('p','0 ảnh','muted'));
 const refresh=context.action('↻',()=>reload().catch(e=>context.status(e.message)),'ghost');refresh.setAttribute('aria-label','Làm mới');refresh.title='Làm mới';heading.append(title,refresh);section.append(heading);

 let upload=null;
 if(own){const tools=context.node('div',undefined,'private-album-tools'),pick=context.node('label',undefined,'btn-like primary');upload=context.node('input');upload.type='file';upload.accept='image/png,image/jpeg,image/webp';upload.setAttribute('aria-label','Thêm ảnh riêng tư');pick.append(upload,context.node('span','Thêm ảnh'));pick.title='PNG, JPEG, WebP · tối đa 4 MB/ảnh · 24 ảnh';tools.append(pick);section.append(tools);upload.onchange=async()=>{const file=upload.files[0];if(!file)return;if(file.size>4*1024*1024){upload.value='';context.status('Ảnh phải nhỏ hơn 4 MB.');return;}upload.disabled=true;try{await context.api('/me/private-photos','POST',{data:await context.readMediaFile(file)});await reload(true);context.status('Đã thêm ảnh riêng tư.');}catch(e){context.status(e.message);}finally{upload.disabled=false;upload.value='';}};}
 const state=context.node('div',undefined,'private-album-state'),grid=context.node('div',undefined,'private-photo-grid'),requests=context.node('div',undefined,'private-access-list');const accessPanel=context.node('details',undefined,'private-access-panel'),accessSummary=context.node('summary','Quyền xem');accessPanel.append(accessSummary,requests);accessPanel.hidden=!own;section.append(grid,state,accessPanel);panel.append(section);
 let inFlight=null,signature='';
 async function openPhoto(photo){try{const current=await context.api('/users/'+user.id+'/private');if(revision!==context.navigationRevision)return;if(!['owner','granted'].includes(current.status)||!current.photos.some(p=>p.id===photo.id)){await reload(true);context.status('Bạn chưa có quyền xem ảnh này.');return;}context.closePrivatePhoto();const dialog=context.node('dialog',undefined,'private-photo-viewer');context.privatePhotoViewer=dialog;dialog.setAttribute('aria-label','Xem ảnh riêng tư');const bar=context.node('div',undefined,'private-photo-viewer-bar'),close=context.action('×',()=>dialog.close(),'ghost');close.setAttribute('aria-label','Đóng ảnh riêng tư');bar.append(context.node('strong','Ảnh riêng tư'),close);const image=context.node('img');image.src=photo.url;image.alt='Ảnh riêng tư của '+user.name;image.onerror=()=>{dialog.close();reload(true).catch(()=>{});context.status('Ảnh không còn khả dụng.');};dialog.append(bar,image);dialog.addEventListener('close',()=>{image.onerror=null;image.removeAttribute('src');dialog.remove();if(context.privatePhotoViewer===dialog)context.privatePhotoViewer=null;},{once:true});document.body.append(dialog);context.showAppDialog(dialog);}catch(e){context.status(e.message);}}
 async function decide(viewer,decision,button){button.disabled=true;try{await context.api('/me/private/requests/'+viewer.id,'POST',{action:decision});await reload(true);context.status(decision==='grant'?'Đã đồng ý cho xem album.':decision==='revoke'?'Đã thu hồi quyền xem album.':'Đã từ chối yêu cầu.');}catch(e){context.status(e.message);button.disabled=false;}}
 function render(album,access){state.replaceChildren();grid.replaceChildren();requests.replaceChildren();title.querySelector('p').textContent=album.count+' ảnh';
 if(!own&&!['owner','granted'].includes(album.status)){context.closePrivatePhoto();if(album.status==='pending')state.append(context.node('p','Đang chờ duyệt.'));else if(album.status==='denied')state.append(context.node('p','Yêu cầu chưa được đồng ý.'));if(album.count){const pending=album.status==='pending',button=context.action(pending?'Hủy yêu cầu':'Yêu cầu xem ảnh riêng tư',async()=>{button.disabled=true;try{await context.api('/users/'+user.id+'/private/request',pending?'DELETE':'POST',{});await reload(true);if(!pending)context.status('Đã gửi yêu cầu trong tin nhắn.');}catch(e){context.status(e.message);button.disabled=false;}},pending?'secondary':'primary');state.append(button);}for(let i=0;i<Math.min(album.count,6);i++){const locked=context.node('div',undefined,'private-photo-locked');locked.setAttribute('aria-label','Ảnh riêng tư đã khóa');locked.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 018 0v3"/><path d="M12 14v3"/></svg>';grid.append(locked);}}
 else{for(const photo of album.photos){const tile=context.node('div',undefined,'private-photo-item'),open=context.action('',()=>openPhoto(photo),'private-photo-open'),image=context.node('img');open.setAttribute('aria-label','Xem ảnh riêng tư');image.src=photo.url;image.alt='Ảnh riêng tư';image.loading='lazy';open.append(image);tile.append(open);if(own){const remove=context.action('×',async()=>{if(!confirm('Xóa ảnh riêng tư này?'))return;remove.disabled=true;try{await context.api('/me/private-photos/'+photo.id,'DELETE');context.closePrivatePhoto();await reload(true);}catch(e){context.status(e.message);remove.disabled=false;}},'private-photo-delete');remove.setAttribute('aria-label','Xóa ảnh riêng tư');tile.append(remove);}grid.append(tile);}}
 if(!album.count)state.append(context.node('p','Chưa có ảnh.','muted'));
 if(own){const pending=access.filter(r=>r.status==='pending'),granted=access.filter(r=>r.status==='granted');accessSummary.textContent='Quyền xem'+(pending.length?' · '+pending.length+' chờ duyệt':'');requests.append(context.node('h4','Chờ duyệt ('+pending.length+')'));if(granted.length)requests.append(context.node('p','Đã cấp quyền','private-access-heading'));for(const request of [...pending,...granted]){const row=context.node('div',undefined,'private-access-row'),who=context.node('div',undefined,'private-access-person');who.append(context.personLink(request.user),context.node("span",request.user.name));const buttons=context.node('div',undefined,'private-access-actions');for(const [label,decision] of request.status==='pending'?[['Đồng ý','grant'],['Từ chối','deny']]:[['Thu hồi','revoke']]){const button=context.action(label,()=>decide(request.user,decision,button),decision==='grant'?'primary':'secondary');if(decision==='grant')button.title='Cho xem toàn bộ album, bao gồm ảnh thêm sau này. Người xem có thể lưu hoặc chụp ảnh.';buttons.append(button);}row.append(who,buttons);requests.append(row);}}
 }
 async function reload(force=false){if(inFlight){await inFlight;if(!force)return;}inFlight=(async()=>{const [album,access]=await Promise.all([context.api('/users/'+user.id+'/private'),own?context.api('/me/private/requests'):Promise.resolve({requests:[]})]);if(revision!==context.navigationRevision)return;const next=JSON.stringify([album,access]);if(next!==signature){signature=next;render(album,access.requests);}if(!['owner','granted'].includes(album.status))context.closePrivatePhoto();})();try{await inFlight;}finally{inFlight=null;}}
 context.privateAlbumRefresh=()=>{if(!document.hidden)return reload().catch(()=>{if(revision!==context.navigationRevision)return;context.closePrivatePhoto();state.textContent='Album không còn khả dụng.';grid.replaceChildren();requests.replaceChildren();});};
 try{await reload();}catch(e){state.textContent=e.message;state.append(context.action('Thử lại',()=>reload(true).catch(e=>context.status(e.message)),'secondary'));}
}

async function profile(panel, opts = {}) {
  const own = !opts.user || opts.user === (context.me && context.me.id);
  if (own) {
    context.me = (await context.api("/me")).user;
    context.paintMe();
  }
  const info = await context.api("/users/" + (own ? context.me.id : opts.user) + "/stats");
  const u = own ? context.me : info.user;
  // Phần đầu trang cá nhân
  const head = context.node("section", undefined, "social-card profile-head");
  const cover = context.node("div", undefined, "cover " + context.hue(u.id));
  if(u.cover){const image=context.node('img',undefined,'profile-cover-image');image.src=u.cover;image.alt='Ảnh bìa của '+u.name;cover.append(image);}
  if(own){const editCover=context.node('label',undefined,'profile-cover-edit'),uploadCover=context.node('input');uploadCover.type='file';uploadCover.accept='image/png,image/jpeg,image/webp';uploadCover.setAttribute('aria-label','Đổi ảnh bìa');editCover.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 7h4l2-3h4l2 3h4v13H4z"/><circle cx="12" cy="13" r="4"/></svg>';editCover.append(uploadCover);cover.append(editCover);uploadCover.onchange=async()=>{const file=uploadCover.files[0];if(!file)return;if(file.size>1024*1024){context.status('Chọn ảnh bìa nhỏ hơn 1 MB.');uploadCover.value='';return;}uploadCover.disabled=true;try{const data=await context.readMediaFile(file);context.me=(await context.api('/me/cover','POST',{data})).user;await context.navigate('profile');context.status('Đã cập nhật ảnh bìa.');}catch(e){context.status(e.message);}finally{uploadCover.disabled=false;uploadCover.value='';}};}
  const big = context.avatar(u);
  big.classList.add("big");
  const id = context.node("div", undefined, "profile-id");
  id.append(context.node("h2", u.name), context.node("p", "@" + u.username, "muted"));
  const bio = context.node("p", u.bio || (own ? "Thêm vài dòng giới thiệu để mọi người hiểu bạn hơn." : ""), "profile-bio");
  const nums = context.node("div", undefined, "profile-stats");
  for (const [n, label,kind] of [[info.posts, "bài viết",null], [info.followers, "người theo dõi","followers"], [info.following, "đang theo dõi","following"]]) {
    const s = context.node(kind?"button":"div");
    if(kind){s.type="button";s.setAttribute("aria-label",label+" ("+n+")");s.onclick=()=>profileConnections(u,kind);}
    s.append(context.node("b", String(n)), context.node("span", label));
    nums.append(s);
  }
  const tags = context.node("div", undefined, "tags");
  (u.interests || []).forEach((v) => tags.append(context.node("span", v)));
  const acts = context.node("div", undefined, "profile-actions");
  let directAvatar=null;
  if(own){directAvatar=context.node('button',undefined,'profile-avatar-edit');directAvatar.type='button';directAvatar.setAttribute('aria-label','Đổi ảnh đại diện trên trang cá nhân');directAvatar.title='Đổi ảnh đại diện';directAvatar.append(big);}
  head.append(cover, directAvatar||big, id);

  head.append(nums, acts);
  if(own)acts.prepend(context.action('Thêm vào tin',()=>context.openCamera({story:true}),'profile-story-action'));
  const navigation=context.node('div',undefined,'profile-sections');navigation.setAttribute('role','tablist');navigation.setAttribute('aria-label','Nội dung trang cá nhân');
  for(const [key,label] of [['posts','Tất cả'],['about','Giới thiệu'],['photos','Ảnh riêng tư']]){const button=context.node('button',label);button.type='button';button.setAttribute('role','tab');button.id='profile-tab-'+key;button.setAttribute('aria-controls','profile-content-'+key);button.setAttribute('aria-selected',String(key==='posts'));button.tabIndex=key==='posts'?0:-1;button.onclick=()=>{panel.dataset.profileSection=key;context.replaceNavigationOptions({profileSection:key,privateAlbum:key==='photos'});for(const other of navigation.children){other.setAttribute('aria-selected',String(other===button));other.tabIndex=other===button?0:-1;}for(const region of panel.querySelectorAll('.profile-content-section')){region.hidden=region.dataset.section!==key&&!(key==='posts'&&region.dataset.section==='about');}};button.onkeydown=e=>{const buttons=[...navigation.children],i=buttons.indexOf(button);let next;if(e.key==='ArrowRight')next=(i+1)%buttons.length;if(e.key==='ArrowLeft')next=(i+buttons.length-1)%buttons.length;if(e.key==='Home')next=0;if(e.key==='End')next=buttons.length-1;if(next!==undefined){e.preventDefault();buttons[next].click();buttons[next].focus();}};navigation.append(button);}head.append(navigation);
  panel.dataset.profileSection='posts';
  const profileContent=context.node('div',undefined,'profile-content');
  const intro=context.node('section',undefined,'profile-content-section profile-intro');intro.id='profile-content-about';intro.dataset.section='about';intro.setAttribute('role','region');intro.setAttribute('aria-label','Giới thiệu');intro.hidden=false;
  const timeline=context.node('section',undefined,'profile-content-section profile-timeline');timeline.id='profile-content-posts';timeline.dataset.section='posts';timeline.setAttribute('role','tabpanel');timeline.setAttribute('aria-labelledby','profile-tab-posts');
  const photos=context.node('section',undefined,'profile-content-section profile-photos');photos.id='profile-content-photos';photos.dataset.section='photos';photos.setAttribute('role','tabpanel');photos.setAttribute('aria-labelledby','profile-tab-photos');photos.hidden=true;
  profileContent.append(intro,timeline,photos);
  panel.append(head);
  const personalRows=[['Tuổi',u.age?u.age+' tuổi':''],['Thành phố',u.city],['Cách xưng hô',u.pronouns],['Giới tính',u.gender],['Xu hướng',u.orientation],['Vai trò',u.relationshipRole],['Kiểu kết nối',u.lookingFor],['Sở thích',(u.interests||[]).join(', ')]];
  {
   const details=context.node('section',undefined,'social-card profile-personal-info');details.setAttribute('aria-label','Thông tin cá nhân');details.append(context.node('h3','Thông tin cá nhân'));
   const values=context.node('dl');for(const [label,value] of personalRows){if(!value)continue;const row=context.node('div');const term=context.node('dt'),icon=context.node('span',undefined,'profile-detail-icon');icon.setAttribute('aria-hidden','true');const shape=label==='Thành phố'?'<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1116 0Z"/><circle cx="12" cy="10" r="3"/>':label==='Kiểu kết nối'?'<path d="m12 21-8-8a5 5 0 017-7l1 1 1-1a5 5 0 017 7Z"/>':label==='Sở thích'?'<path d="m12 3 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z"/>':'<circle cx="12" cy="8" r="4"/><path d="M4 22v-2a8 8 0 0116 0v2"/>';icon.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+shape+'</svg>';const description=context.node('span',label,'profile-detail-label');term.append(icon,description);term.title=label;row.append(term,context.node('dd',String(value)));values.append(row);}details.append(values);
   if(own&&!u.identityPublic&&[u.gender,u.orientation,u.relationshipRole,u.pronouns].some(Boolean))details.append(context.node('p','Thông tin danh tính chỉ hiển thị với bạn. Bật chia sẻ trong Cài đặt → Chỉnh sửa tài khoản nếu muốn công khai.','profile-info-privacy'));
   details.insertBefore(bio,details.querySelector('dl'));details.append(context.profileBadges(u),tags);
   if(!personalRows.some(([,value])=>value))details.append(context.node('p',own?'Thêm thông tin để bạn bè hiểu bạn hơn.':'Chưa có thông tin được chia sẻ.','muted'));

   intro.append(details);
  }
  const settings = context.node("div", undefined, "settings profile-edit-screen");
  let avatarPicker=null;
  if (own) {
    const pick = context.node("label", undefined, "btn-like secondary");
    const upload = context.node("input");
    upload.type = "file";
    upload.accept = "image/png,image/jpeg,image/webp";
    upload.setAttribute("aria-label", "Đổi ảnh đại diện, tối đa 1 MB");
    const photoIcon=context.node("span");photoIcon.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M4 7h4l2-3h4l2 3h4v13H4z"/><circle cx="12" cy="13" r="4"/></svg>';pick.append(upload,photoIcon);pick.setAttribute("aria-label","Đổi ảnh đại diện");
    pick.classList.add("avatar-cam");
    const directCamera=context.node('span',undefined,'profile-avatar-camera');directCamera.innerHTML=photoIcon.innerHTML;directAvatar.append(directCamera);directAvatar.onclick=()=>upload.click();
    upload.onchange = async () => {
      const f = upload.files[0];
      if (!f) return;
      if (f.size > 1024 * 1024){upload.value="";return context.status("Chọn ảnh nhỏ hơn 1 MB.");}
      const keepEditorOpen=!settings.hidden;directAvatar.disabled=true;
      try {
        const data = await new Promise((resolve, reject) => {
          const r = new FileReader();
          r.onload = () => resolve(r.result);
          r.onerror = reject;
          r.readAsDataURL(f);
        });
        context.me = (await context.api("/me/avatar", "POST", { data })).user;
        context.status("Đã cập nhật ảnh đại diện.");
        await context.navigate("profile",{settings:keepEditorOpen},"replace");
      } catch (e) {
        context.status(e.message);
      }finally{directAvatar.disabled=false;upload.value="";}
    };
    avatarPicker=pick;

  } else {
    acts.append(context.friendshipAction(u,()=>context.navigate("profile",opts)));
    if(u.friendship!=='outgoing')acts.append(
      context.action(u.following ? "Đang theo dõi" : "Theo dõi", async () => {
        await context.api("/users/" + u.id + "/follow", u.following ? "DELETE" : "POST", {});
        await context.navigate("profile", opts);
      }, u.following ? "secondary" : "follow")
    );
    acts.append(
      context.action("Nhắn tin", () => context.openChat(u)),
      context.more([
        ["Chặn", async () => {
          if (!confirm("Chặn " + u.name + "?")) return;
          await context.api("/users/" + u.id + "/block", "POST", {});
          context.status("Đã chặn " + u.name + ".");
          await context.navigate("feed");
        }],
        ["Báo cáo", () => context.report("user", u.id)],
      ]),
    );
  }
  if (own) {
    settings.hidden = !opts.settings;
    if(opts.settings)document.body.classList.add("profile-edit-open");
    // Sửa hồ sơ
    const form = context.node("form", undefined, "social-card profile-editor");
    const name = field(form, "Tên hiển thị", context.me.name);
    name.maxLength = 60;
    name.required = true;
    const bioInput = field(form, "Giới thiệu", context.me.bio, "textarea");
    bioInput.maxLength = 500;
    bioInput.setAttribute("aria-label","Giới thiệu");
    const interests = field(form, "Sở thích, phân cách bằng dấu phẩy", context.me.interests.join(", "));
    interests.maxLength = 350;
    const age = field(form, "Tuổi (không bắt buộc)", context.me.age || "", "number"); age.min = 18; age.max = 99;
    const city = field(form, "Khu vực / thành phố", context.me.city || ""); city.maxLength = 80;
    for(const [control,label,accessible] of [[age,"Tuổi","Tuổi (không bắt buộc)"],[city,"Thành phố","Khu vực / thành phố"],[interests,"Sở thích","Sở thích, phân cách bằng dấu phẩy"]]){control.closest("label").firstChild.textContent=label;control.setAttribute("aria-label",accessible);}
    interests.placeholder="Cà phê, du lịch, âm nhạc…";bioInput.placeholder="Viết một chút về bạn…";
    const chooseIdentity = (label, value, values, key) => {
      const input = field(form, label, value || ""); input.maxLength = 60;
      input.placeholder = "Chọn hoặc nhập";profilePresets(input,label,values);return input;
    };
    const gender = chooseIdentity("Giới tính", context.me.gender, ["Nam", "Nữ", "Nam chuyển giới", "Nữ chuyển giới", "Phi nhị nguyên", "Đang tìm hiểu"], "gender");
    const orientation = chooseIdentity("Xu hướng tính dục", context.me.orientation, ["Gay / Đồng tính nam", "Les / Đồng tính nữ", "Song tính", "Toàn tính", "Dị tính", "Vô tính", "Đang tìm hiểu"], "orientation");
    const relationshipRole = chooseIdentity("Vai trò", context.me.relationshipRole, ["Top", "Bottom", "Vers", "Vers Top", "Vers Bottom", "Side", "Đang tìm hiểu"], "role");
    const pronouns = field(form, "Cách xưng hô", context.me.pronouns || ""); pronouns.maxLength = 30;
    const lookingFor = field(form, "Bạn muốn tìm kết nối như thế nào?", context.me.lookingFor || ""); lookingFor.maxLength = 100;lookingFor.setAttribute("aria-label","Bạn muốn tìm kết nối như thế nào?");lookingFor.closest("label").firstChild.textContent="Tìm kiếm";
    profilePresets(pronouns,'Cách xưng hô',['Anh','Chị','Em','Bạn','Mình','Họ / Them']);pronouns.placeholder='Chọn cách xưng hô';
    profilePresets(city,'Thành phố',['TP. Hồ Chí Minh','Hà Nội','Đà Nẵng','Hải Phòng','Cần Thơ','Huế','Nha Trang','Đà Lạt','Vũng Tàu','Biên Hòa','Quy Nhơn']);city.placeholder='Chọn hoặc nhập thành phố';
    profilePresets(lookingFor,'Kiểu kết nối',['Kết bạn','Trò chuyện','Hẹn hò','Mối quan hệ nghiêm túc','Bạn đồng hành','Đang tìm hiểu']);lookingFor.placeholder='Bạn muốn kết nối thế nào?';
    profilePresets(interests,'Sở thích',['Cà phê','Du lịch','Âm nhạc','Phim ảnh','Đọc sách','Nấu ăn','Thể thao','Gym','Yoga','Chạy bộ','Nhiếp ảnh','Thú cưng','Game','Nghệ thuật','Thiên nhiên','Thời trang'],{multiple:true});
    const identityLabel = context.node("label", undefined, "switch-row"); const identityPublic = context.node("input"); identityPublic.type = "checkbox"; identityPublic.checked = !!context.me.identityPublic; identityLabel.append(context.node("span", "Hiển thị giới tính, xu hướng và vai trò trên hồ sơ"), identityPublic); form.append(identityLabel);
    form.append(context.node("p", "Tất cả thông tin đều do bạn tự chọn. Để trống nếu không muốn chia sẻ.", "muted field-help"));
    const activityLabel = context.node("label", undefined, "switch-row"); const showActivity = context.node("input"); showActivity.type = "checkbox"; showActivity.checked = context.me.showActivity !== false; activityLabel.append(context.node("span", "Hiển thị khi tôi đang hoạt động"), showActivity); form.append(activityLabel);
    const visibleLabel = context.node("label", undefined, "switch-row");
    const visible = context.node("input");
    visible.type = "checkbox";
    visible.checked = context.me.discoverable;
    visibleLabel.append(context.node("span", "Cho phép xuất hiện trong Khám phá"), visible);
    form.append(visibleLabel);
    const dmLabel = context.node("label", "Ai được nhắn tin cho bạn", "form-field");
    const dm = context.node("select");
    for (const [value, label] of [
      ["everyone", "Mọi thành viên"],
    ]) {
      const o = context.node("option", label);
      o.value = value;
      dm.append(o);
    }
    dm.value = "everyone";
    dmLabel.append(dm);
    form.append(dmLabel);
    const editorHeader=context.node("div",undefined,"profile-editor-head");
    const editorCopy=context.node("div");editorCopy.append(context.node("span","HỒ SƠ CỦA BẠN","profile-editor-eyebrow"),context.node("h2","Thể hiện chính mình"),context.node("p","Chọn những điều bạn muốn chia sẻ với mọi người."));editorHeader.append(context.avatar(context.me));
    if(avatarPicker){avatarPicker.classList.remove("avatar-cam");avatarPicker.classList.add("profile-photo-edit");avatarPicker.querySelector("span").textContent="Đổi ảnh đại diện";editorHeader.append(avatarPicker);}
    const section=(title,description,inputs)=>{const group=context.node("fieldset",undefined,"profile-editor-section");group.append(context.node("legend",title),context.node("p",description,"field-help"));const grid=context.node("div",undefined,"profile-field-grid");for(const control of inputs)grid.append(control.closest("label")||control);group.append(grid);return group;};
    const basics=section("Thông tin cơ bản","Những thông tin giúp bạn bè nhận ra bạn.",[name,age,city,pronouns]);
    const about=section("Một chút về bạn","Giới thiệu, sở thích và điều bạn muốn kết nối.",[bioInput,interests,lookingFor]);
    const identity=section("Danh tính của bạn","Bạn có thể tự mô tả hoặc để trống bất kỳ thông tin nào.",[gender,orientation,relationshipRole]);
    const privacy=section("Quyền riêng tư","Bạn quyết định ai có thể tìm thấy và liên hệ với mình.",[identityLabel,activityLabel,visibleLabel,dmLabel]);
    const counter=context.node("small",bioInput.value.length+" / 500","profile-bio-counter");bioInput.closest("label").append(counter);bioInput.addEventListener("input",()=>{counter.textContent=bioInput.value.length+" / 500";});
    const save = context.node("button", "Xong");save.className="profile-save";
    const cancel=context.node("button","‹","secondary");cancel.setAttribute("aria-label","Quay lại hồ sơ");cancel.type="button";cancel.onclick=()=>context.goBack("profile");
    const savebar=context.node("div",undefined,"profile-savebar"),saveState=context.node("span","Thông tin của bạn được bảo vệ.");savebar.append(saveState,cancel,save);
    form.addEventListener("input",()=>{saveState.textContent="Bạn có thay đổi chưa lưu";form.classList.add("has-changes");});
    for(const help of form.querySelectorAll(":scope > .field-help"))help.remove();
    const editorBar=context.node("div",undefined,"profile-editor-bar");editorBar.append(cancel,context.node("h2","Chỉnh sửa hồ sơ"),save);
    form.append(editorBar,editorHeader,basics,about,identity,privacy);
    form.onsubmit = async (e) => {
      e.preventDefault();
      save.disabled = true;
      try {
        context.me = (
          await context.api("/me", "PATCH", {
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
        context.$("name").value = context.me.name;
        context.paintMe();
        await context.navigate("profile",{},"replace");
        context.status("Đã lưu hồ sơ.");
      } catch (e) {
        context.status(e.message);
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
  const timelineHead=context.node('div',undefined,'social-card profile-timeline-head');timelineHead.append(context.node('h3','Bài viết'));if(own)timelineHead.append(context.action('Tạo bài viết',async()=>{await context.navigate('feed',{section:'community'});document.querySelector('.composer textarea')?.focus();},'secondary'));timeline.append(timelineHead);
  const { posts } = await context.api("/posts?user=" + encodeURIComponent(u.id));
  if (!posts.length)
    timeline.append(context.empty("📝", "Chưa có bài viết", own ? "Chia sẻ điều đầu tiên trên Bảng tin nhé." : "Người này chưa đăng gì."));
  for (const p of posts) timeline.append(context.postCard(p));
  if(opts.privateAlbum)navigation.querySelector('#profile-tab-photos').click();else if(['about','posts'].includes(opts.profileSection))navigation.querySelector('#profile-tab-'+opts.profileSection).click();
}

  return {field, profilePresets, profileConnections, profilePrivateAlbum, profile};
}
