/* Dedicated wallet workflows. Authentication and authorization remain server-side. */
(() => {
 const KIND_LABELS = {gift:'Chiến dịch xu tặng',paid_correction:'Đề nghị bù xu mua'};
 const STATE_LABELS = {pending:'Chờ Admin duyệt',done:'Đã ghi sổ',rejected:'Đã từ chối',expired:'Đã hết hạn'};
 const number = value => { const n=Number(value); return Number.isFinite(n)?n.toLocaleString('vi-VN'):'—'; };
 window.renderWalletTools = async function renderWalletTools(ctx) {
  const {root,api,el,button,badge,table,empty,toast,confirmAction,me,refresh,date}=ctx;
  const isAdmin=me?.role==='admin',isFinance=me?.team==='finance';
  if(!isAdmin&&!isFinance){root.replaceChildren();empty(root,'Nhóm của bạn không được cấp công cụ quản lý xu.');return;}
  const shell=el('div',undefined,'wallet-tools');root.replaceChildren(shell);
  const alive=()=>shell.isConnected;
  const label=(text,input)=>{const n=el('label',text);n.append(input);return n;};
  const hint=text=>el('p',text,'wallet-hint');
  const icon=(kind)=>{const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('aria-hidden','true');for(const d of (kind==='gift'?['M3 8h18v4H3z','M5 12v9h14v-9','M12 8v13','M12 8H8a3 3 0 1 1 3-3l1 3z','M12 8h4a3 3 0 1 0-3-3l-1 3z']:['M4 5h16v16H4z','M8 9h8M8 13h5','M8 17h3','M15 17l2 2 4-4'])){const path=document.createElementNS('http://www.w3.org/2000/svg','path');path.setAttribute('d',d);svg.append(path);}return svg;};
  const safeRefresh=async()=>{if(alive())await refresh();};
  const loading=el('div','Đang tải công cụ và lịch sử…','empty');shell.append(loading);
  let history;
  try{history=await api('wallet-tools');}catch(error){if(!alive())return;loading.replaceChildren(el('p',error.message,'error'),button('Thử lại',()=>renderWalletTools(ctx)));return;}
  if(!alive())return;loading.remove();
  const operations=Array.isArray(history.operations)?history.operations:[],canApprove=isAdmin&&history.canApprove===true;
  const banner=el('section',undefined,'wallet-banner');const bannerCopy=el('div');bannerCopy.append(el('p','KINNECT / QUẢN LÝ XU','eyebrow'),el('h2',isAdmin?'Phân bổ rõ ràng. Phê duyệt có kiểm soát.':'Đối soát rõ ràng. Trình duyệt đúng người.'),el('p',isAdmin?'Tạo chiến dịch xu tặng hoặc duyệt đề nghị bù xu mua. Mỗi thao tác được lưu bằng một mã duy nhất.':'Gửi đề nghị bù xu mua kèm mã giao dịch gốc và lý do. Chỉ Admin có quyền phê duyệt ghi sổ.'));
  banner.append(bannerCopy,icon(isAdmin?'gift':'correction'));shell.append(banner);
  const stats=el('div',undefined,'wallet-stats');for(const [caption,value] of [['Đang chờ duyệt',operations.filter(o=>o.state==='pending').length],['Đã hoàn tất',operations.filter(o=>o.state==='done').length],['Đã từ chối / hết hạn',operations.filter(o=>['rejected','expired'].includes(o.state)).length]]){const card=el('div',undefined,'wallet-stat');card.append(el('span',caption),el('b',number(value)));stats.append(card);}shell.append(stats);
  const note=el('div',undefined,'wallet-boundary');note.append(el('b','Hai loại xu, hai mục đích.'),el('p','Xu tặng là quyền lợi khuyến mại, không phải xu mua. Bù xu mua là điều chỉnh sổ cái theo giao dịch đã đối soát; công cụ này không chuyển tiền ngân hàng.'));shell.append(note);
  const work=el('section',undefined,'card wallet-workbench'),tabs=el('div',undefined,'wallet-tabs');tabs.setAttribute('role','tablist');tabs.setAttribute('aria-label','Loại thao tác xu');work.append(tabs);shell.append(work);
  const prefill=window.__WALLET_PREFILL||null;window.__WALLET_PREFILL=null;
  let kind=prefill?.kind&&(isAdmin||prefill.kind==='paid_correction')?prefill.kind:(isAdmin?'gift':'paid_correction'),frozen=false,searchSequence=0,searchTimer=null,previewData=null;
  const selected=new Map(),tabButtons=[];
  const body=el('div');body.id='wallet-form-panel';body.setAttribute('role','tabpanel');work.append(body);
  const setKind=value=>{if(frozen||value===kind)return;kind=value;if(kind==='paid_correction'&&selected.size>1){const first=selected.values().next().value;selected.clear();selected.set(first.id,first);}drawForm();};
  for(const value of isAdmin?['gift','paid_correction']:['paid_correction']){const b=button(KIND_LABELS[value],()=>setKind(value),'wallet-tab');b.setAttribute('role','tab');b.id='wallet-tab-'+value;b.setAttribute('aria-controls','wallet-form-panel');b.addEventListener('keydown',event=>{if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)||frozen)return;event.preventDefault();const index=tabButtons.findIndex(([v])=>v===kind),next=event.key==='Home'?0:event.key==='End'?tabButtons.length-1:(index+(event.key==='ArrowRight'?1:-1)+tabButtons.length)%tabButtons.length;setKind(tabButtons[next][0]);tabButtons[next][1].focus();});tabs.append(b);tabButtons.push([value,b]);}
  const reviewArea=el('section',undefined,'wallet-review-area');shell.append(reviewArea);

  function operationFacts(op,recipients,compact=false){
   const summary=el('div',undefined,'wallet-operation-facts');
   const rows=[['Loại',KIND_LABELS[op.kind]||op.kind],['Mã thao tác',op.id],['Tên',op.title],['Xu mỗi người',number(op.coins)],['Số người nhận',number(op.count)],['Tổng xu ghi sổ',number(op.totalCoins)],['Trạng thái',STATE_LABELS[op.state]||op.state],['Người đề nghị',op.createdBy||'—']];
   if(op.reference)rows.push(['Giao dịch gốc',op.reference]);if(op.approvedBy)rows.push(['Người phê duyệt',op.approvedBy]);if(op.created)rows.push(['Thời điểm tạo',date(op.created)]);if(op.completed)rows.push(['Hoàn tất',date(op.completed)]);
   for(const [key,value]of rows){const row=el('div');row.append(el('span',key),el('b',value));summary.append(row);}
   const holder=el('div');holder.append(summary);if(op.reason){holder.append(el('p','Lý do / căn cứ','wallet-field-caption'),el('p',op.reason,'wallet-reason'));}
   if(Array.isArray(recipients)){const details=el('details',undefined,'wallet-recipient-details');details.append(el('summary','Danh sách người nhận đã chốt ('+number(recipients.length)+')'));const list=el('ul'),pages=el('div',undefined,'wallet-recipient-pages');let page=0;const pageSize=100;const paint=()=>{list.replaceChildren();for(const person of recipients.slice(page*pageSize,(page+1)*pageSize)){const li=el('li');li.append(el('b','@'+person.username),el('span',person.name||''));list.append(li);}pages.replaceChildren();if(recipients.length>pageSize){const previous=button('← Trước',()=>{page--;paint();}),next=button('Sau →',()=>{page++;paint();});previous.disabled=page===0;next.disabled=(page+1)*pageSize>=recipients.length;pages.append(previous,el('span','Trang '+(page+1)+' / '+Math.ceil(recipients.length/pageSize)),next);}};paint();details.append(list,pages);holder.append(details);if(recipients.length!==Number(op.count))holder.append(hint('Danh sách hiển thị có thể được giới hạn. Số người và tổng xu của mã thao tác là căn cứ phê duyệt.'));}
   if(compact)holder.classList.add('wallet-facts-compact');return holder;
  }
  function approvalText(op,recipients){const names=(recipients||[]).map(p=>'@'+p.username);const targets=names.length<=12?names.join(', '):'Danh sách '+number(op.count)+' người đã chốt trong bản xem trước';return `${KIND_LABELS[op.kind]||op.kind}: ${op.title}\nMã: ${op.id}\nNgười nhận: ${targets||number(op.count)+' người trong danh sách đã chốt'}\nMỗi người: ${number(op.coins)} xu\nTổng cộng: ${number(op.totalCoins)} xu\n${op.reference?'Giao dịch gốc: '+op.reference+'\n':''}Lý do: ${op.reason||'—'}\nXác nhận sẽ ghi sổ. Nếu cần thử lại, chỉ dùng cùng mã thao tác này.`;}
  async function commit(op,recipients,statusNode){
   if(!canApprove){toast('Chỉ Admin có quyền phê duyệt.');return;}
   if(!await confirmAction('Xác nhận ghi sổ '+number(op.totalCoins)+' xu?',approvalText(op,recipients)))return;
   statusNode.className='wallet-result pending';statusNode.textContent='Đang xác nhận mã '+op.id+'…';
   try{await api('wallet-tools/confirm',{id:op.id});if(!alive())return;toast('Đã xác nhận ghi sổ.');await safeRefresh();}
   catch(error){if(!alive())return;statusNode.className='wallet-result error';statusNode.replaceChildren(el('p','Chưa xác nhận được kết quả: '+error.message),hint('Giữ nguyên mã '+op.id+'. Thử lại cùng mã sẽ không tạo một lượt cộng xu mới.'),button('Thử lại cùng mã',()=>commit(op,recipients,statusNode),'primary'),button('Kiểm tra trạng thái',()=>showDetails(op.id)));}
  }
  async function reject(op,recipients,statusNode){
   if(!canApprove)return;
   const dialog=el('dialog',undefined,'wallet-reject-dialog'),form=el('form');form.method='dialog';form.append(el('p','TỪ CHỐI ĐỀ NGHỊ','eyebrow'),el('h2',op.title),operationFacts(op,recipients,true));const reason=el('textarea');reason.rows=3;reason.required=true;reason.minLength=10;reason.maxLength=2000;form.append(label('Lý do từ chối (ít nhất 10 ký tự)',reason));const actions=el('div',undefined,'dialog-actions');actions.append(button('Hủy',()=>dialog.close('cancel')));const submit=el('button','Xác nhận từ chối','danger');submit.value='reject';actions.append(submit);form.append(actions);dialog.append(form);shell.append(dialog);dialog.showModal();
   const result=await new Promise(resolve=>dialog.addEventListener('close',()=>resolve({confirmed:dialog.returnValue==='reject',reason:reason.value.trim()}),{once:true}));dialog.remove();if(!result.confirmed)return;if(result.reason.length<10){toast('Lý do từ chối cần ít nhất 10 ký tự.');return;}
   try{await api('wallet-tools/reject',{id:op.id,reason:result.reason});if(!alive())return;toast('Đã từ chối đề nghị.');await safeRefresh();}
   catch(error){if(!alive())return;statusNode.className='wallet-result error';statusNode.replaceChildren(el('p',error.message),button('Thử lại từ chối',()=>reject(op,recipients,statusNode)));}
  }
  function review(op,recipients,expiresIn){
   reviewArea.replaceChildren();const panel=el('article',undefined,'card wallet-review');const top=el('div',undefined,'wallet-section-head');top.append(el('div',canApprove?'Kiểm tra lần cuối trước khi ghi sổ':'Đề nghị đã gửi đến Admin','wallet-review-heading'),badge(STATE_LABELS[op.state]||op.state,op.state==='done'?'good':op.state==='pending'?'warn':''));panel.append(top,operationFacts(op,recipients));
   if(expiresIn){const seconds=Number(expiresIn),duration=seconds>=3600?Math.ceil(seconds/3600)+' giờ':Math.ceil(seconds/60)+' phút';panel.append(hint('Bản xem trước có hiệu lực '+duration+'. Danh sách người nhận đã được chốt.'));}if(op.expiresAt&&op.state==='pending')panel.append(hint('Hạn phê duyệt: '+date(op.expiresAt)));
   if(!canApprove&&op.state==='pending')panel.append(el('p','Admin sẽ kiểm tra và phê duyệt đề nghị này. Chưa có xu nào được cộng khi chỉ tạo bản xem trước.','information'));
   const statusNode=el('div');statusNode.setAttribute('role','status');statusNode.setAttribute('aria-live','polite');panel.append(statusNode);
   const actions=el('div',undefined,'actions');if(canApprove&&op.state==='pending')actions.append(button('Xác nhận ghi sổ',()=>commit(op,recipients,statusNode),'primary'),button('Từ chối',()=>reject(op,recipients,statusNode),'danger'));actions.append(button('Kiểm tra trạng thái',()=>showDetails(op.id)));panel.append(actions);reviewArea.append(panel);return panel;
  }
  async function showDetails(id){
   try{const data=await api('wallet-tools/'+encodeURIComponent(id));if(!alive())return;previewData=data;const panel=review(data.operation,data.recipients);panel.scrollIntoView({behavior:'smooth',block:'start'});}
   catch(error){if(alive())toast('Chưa tải được chi tiết: '+error.message);}
  }
  function drawForm(){
   for(const[value,b]of tabButtons){b.classList.toggle('active',value===kind);b.setAttribute('aria-selected',String(value===kind));b.tabIndex=value===kind?0:-1;b.disabled=frozen;}
   body.setAttribute('aria-labelledby','wallet-tab-'+kind);body.replaceChildren();const heading=el('div',undefined,'wallet-form-heading');heading.append(icon(kind),el('div',KIND_LABELS[kind]));body.append(heading,el('p',kind==='gift'?'Xu tặng dành cho chiến dịch khuyến mại, không ghi nhận thành xu đã mua.':'Mỗi đề nghị chỉ dành cho một thành viên và phải có mã giao dịch gốc để đối soát.','muted'));
   const form=el('form',undefined,'wallet-form'),layout=el('div',undefined,'wallet-form-layout'),fields=el('div'),recipientsPanel=el('div',undefined,'wallet-recipients');layout.append(fields,recipientsPanel);form.append(layout);
   const title=el('input');title.required=true;title.maxLength=120;title.placeholder=kind==='gift'?'Ví dụ: Quà chào mừng tháng 11':'Ví dụ: Đối soát xu mua của thành viên';fields.append(label('Tên chiến dịch / đề nghị',title));
   const row=el('div',undefined,'wallet-input-row'),coins=el('input');coins.type='number';coins.inputMode='numeric';coins.required=true;coins.min='1';coins.max='1000000';coins.step='1';coins.placeholder='Nhập số xu';row.append(label(kind==='gift'?'Xu tặng mỗi người':'Số xu mua cần bù',coins));const ticket=el('input');ticket.maxLength=100;ticket.placeholder='Mã phiếu đầy đủ, nếu có';row.append(label('Mã phiếu phối hợp',ticket));fields.append(row);
   const reference=el('input');reference.maxLength=120;reference.minLength=6;reference.required=kind==='paid_correction';reference.placeholder='Mã giao dịch đã đối soát';if(kind==='paid_correction')fields.append(label('Mã giao dịch gốc',reference));
   const reason=el('textarea');reason.rows=4;reason.required=true;reason.minLength=10;reason.maxLength=2000;reason.placeholder='Ghi căn cứ, kết quả kiểm tra và lý do cấp / bù xu.';fields.append(label('Lý do và căn cứ (ít nhất 10 ký tự)',reason));
   const selectorTitle=el('div',undefined,'wallet-section-head');const selectedCount=el('b');selectorTitle.append(el('h3',kind==='gift'?'Chọn người nhận':'Thành viên cần điều chỉnh'),selectedCount);recipientsPanel.append(selectorTitle);
   const all=el('input');all.type='checkbox';if(kind==='gift'){const line=el('label',undefined,'wallet-all');line.append(all,el('span','Tất cả thành viên đủ điều kiện'));recipientsPanel.append(line,hint('Danh sách được chốt tại thời điểm xem trước; không tự cộng cho tài khoản tạo sau.'));}
   const search=el('input');search.type='search';search.placeholder='Tìm tên hoặc @tài khoản';search.maxLength=60;search.setAttribute('aria-label','Tìm thành viên nhận xu');recipientsPanel.append(search);const chosen=el('div',undefined,'wallet-selected'),results=el('div',undefined,'wallet-people');results.setAttribute('aria-live','polite');recipientsPanel.append(chosen,results);
   const totals=el('div',undefined,'wallet-live-total'),formError=el('p','','error');formError.setAttribute('role','alert');const actions=el('div',undefined,'wallet-form-actions'),submit=el('button',isAdmin?'Xem trước danh sách & số xu':'Gửi đề nghị đến Admin','primary');actions.append(submit);form.append(totals,formError,actions);body.append(form);
   let currentPeople=[];
   function updateSummary(){
    selectedCount.textContent=all.checked?'Danh sách chốt sau':'Đã chọn '+number(selected.size);chosen.replaceChildren();
    if(!all.checked)for(const person of selected.values()){const chip=button('@'+person.username+' ×',()=>{if(frozen)return;selected.delete(person.id);renderPeople(currentPeople);updateSummary();},'wallet-person-chip');chip.setAttribute('aria-label','Bỏ chọn '+person.username);chip.disabled=frozen;chosen.append(chip);}
    const amount=Number(coins.value),valid=Number.isSafeInteger(amount)&&amount>=1&&amount<=1000000;
    totals.replaceChildren(el('span',kind==='gift'?'Dự kiến xu tặng':'Dự kiến bù xu mua'),el('b',valid?(all.checked?number(amount)+' xu / người':number(amount*selected.size)+' xu'):'—'));
    if(all.checked)totals.append(el('small','Tổng chính xác sẽ có trong bản xem trước.'));else totals.append(el('small',number(selected.size)+' người × '+(valid?number(amount):'—')+' xu'));
    search.disabled=frozen||all.checked;for(const input of results.querySelectorAll('input'))input.disabled=frozen||all.checked;
   }
   function renderPeople(people){
    currentPeople=people;results.replaceChildren();if(!people.length){results.append(el('p','Không tìm thấy thành viên phù hợp.','wallet-search-empty'));return;}
    for(const person of people){const item=el('label',undefined,'wallet-person'),choice=el('input');choice.type=kind==='paid_correction'?'radio':'checkbox';choice.name='wallet-recipient';choice.value=person.id;choice.checked=selected.has(person.id);choice.disabled=frozen||all.checked;const avatar=el('span',(person.name||person.username||'?').slice(0,1).toUpperCase(),'wallet-avatar'),name=el('span',person.name||person.username,'wallet-person-name');name.append(el('small','@'+person.username));item.append(choice,avatar,name);choice.onchange=()=>{if(frozen)return;if(kind==='paid_correction'){selected.clear();if(choice.checked)selected.set(person.id,person);}else if(choice.checked){if(selected.size>=500){choice.checked=false;toast('Chỉ chọn tối đa 500 thành viên mỗi lượt. Với chiến dịch toàn bộ, dùng lựa chọn tất cả thành viên.');return;}selected.set(person.id,person);}else selected.delete(person.id);updateSummary();};results.append(item);}
   }
   async function searchPeople(){const revision=++searchSequence;results.replaceChildren(el('p','Đang tìm thành viên…','wallet-search-empty'));try{const data=await api('wallet-tools/people?q='+encodeURIComponent(search.value));if(!alive()||revision!==searchSequence||!results.isConnected)return;const list=data.people||[];if(prefill?.username&&!selected.size){const target=String(prefill.username).replace(/^@/,'').toLowerCase();const match=list.find(x=>x.username?.toLowerCase()===target||x.id===target);if(match)selected.set(match.id,match);}renderPeople(list);updateSummary();}catch(error){if(!alive()||revision!==searchSequence||!results.isConnected)return;results.replaceChildren(el('p',error.message,'error'),button('Thử lại tìm kiếm',searchPeople));}}
   if(prefill){if(prefill.title)title.value=prefill.title;if(prefill.ticketId)ticket.value=prefill.ticketId;if(prefill.reference)reference.value=prefill.reference;if(prefill.coins)coins.value=String(prefill.coins);if(prefill.reason)reason.value=prefill.reason;if(prefill.username)search.value=String(prefill.username).replace(/^@/,'');}
   search.oninput=()=>{clearTimeout(searchTimer);searchTimer=setTimeout(searchPeople,280);};all.onchange=updateSummary;coins.oninput=updateSummary;
   form.onsubmit=async event=>{
    event.preventDefault();if(frozen)return;formError.textContent='';const amount=Number(coins.value),why=reason.value.trim(),ref=reference.value.trim();
    if(!Number.isSafeInteger(amount)||amount<1||amount>1000000){formError.textContent='Nhập số xu nguyên từ 1 đến 1.000.000.';return;}
    if(why.length<10){formError.textContent='Lý do cần ít nhất 10 ký tự.';return;}
    if(!all.checked&&!selected.size){formError.textContent='Chọn ít nhất một người nhận.';return;}
    if(kind==='paid_correction'&&(selected.size!==1||ref.length<6)){formError.textContent='Đề nghị bù xu mua cần đúng một thành viên và mã giao dịch gốc ít nhất 6 ký tự.';return;}
    if(!title.value.trim()){formError.textContent='Nhập tên chiến dịch hoặc đề nghị.';return;}
    const payload={kind,title:title.value.trim(),coins:amount,all:kind==='gift'&&all.checked,userIds:all.checked?[]:[...selected.keys()],reference:kind==='paid_correction'?ref:'',reason:why,...(ticket.value.trim()?{ticketId:ticket.value.trim()}:{})};
    frozen=true;for(const control of form.querySelectorAll('input,textarea,button'))control.disabled=true;for(const[,b]of tabButtons)b.disabled=true;submit.textContent='Đang chốt bản xem trước…';
    try{const data=await api('wallet-tools/preview',payload);if(!alive())return;previewData=data;review(data.operation,data.recipients,data.expiresIn);submit.textContent=isAdmin?'Đã tạo bản xem trước':'Đã gửi đề nghị';submit.hidden=true;actions.append(button('Tạo đề nghị khác',safeRefresh));formError.className='wallet-submitted';formError.textContent='Mã '+data.operation.id+' đã được lưu. Các bước phê duyệt dùng đúng mã này.';}
    catch(error){if(!alive())return;frozen=false;for(const control of form.querySelectorAll('input,textarea,button'))control.disabled=false;for(const[,b]of tabButtons)b.disabled=false;submit.textContent=isAdmin?'Xem trước danh sách & số xu':'Gửi đề nghị đến Admin';formError.textContent=error.message;updateSummary();}
   };
   updateSummary();searchPeople();
  }
  drawForm();
  const historySection=el('section',undefined,'wallet-history'),historyHead=el('div',undefined,'wallet-section-head');historyHead.append(el('div',undefined,'wallet-heading'));historyHead.firstChild.append(el('h3',isAdmin?'Lịch sử & đề nghị chờ phê duyệt':'Các đề nghị của bạn'),el('p',isAdmin?'Kiểm tra người nhận, mã giao dịch và lý do trước khi duyệt.':'Theo dõi trạng thái; chỉ Admin thực hiện bước ghi sổ.','muted'));historyHead.append(button('Làm mới lịch sử',safeRefresh));historySection.append(historyHead);shell.append(historySection);
  if(!operations.length)empty(historySection,'Chưa có chiến dịch hoặc đề nghị điều chỉnh xu.');else table(historySection,['Chiến dịch / đề nghị','Số xu','Người đề nghị','Trạng thái','Thao tác'],operations.map(op=>{
   const title=el('div',op.title,'wallet-history-title');title.append(el('small',KIND_LABELS[op.kind]||op.kind),el('small',date(op.created)));if(op.reference)title.append(el('small','Giao dịch: '+op.reference));
   const amount=el('div',number(op.totalCoins)+' xu');amount.append(el('small',number(op.count)+' người × '+number(op.coins)+' xu'));
   const actions=el('div',undefined,'actions');actions.append(button(canApprove&&op.state==='pending'?'Kiểm tra & phê duyệt':'Xem chi tiết',()=>showDetails(op.id),canApprove&&op.state==='pending'?'primary':''));
   return[title,amount,'@'+op.createdBy,badge(STATE_LABELS[op.state]||op.state,op.state==='done'?'good':op.state==='pending'?'warn':''),actions];
  }));
 };
})();
