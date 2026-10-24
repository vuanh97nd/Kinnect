import {test,expect} from '@playwright/test';
async function member(browser,name){const context=await browser.newContext({viewport:{width:390,height:844},permissions:['camera','microphone']});const r=await context.request.post('/api/register',{data:{username:name+'_'+Date.now(),password:'abcdef',name,agree18:true}});expect(r.ok()).toBeTruthy();const {user}=await r.json();const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('/');await expect(page.locator('#app')).toBeVisible();return {context,page,user,errors};}
test('messaging UI: unread filter, group creation, group delivery and private video call',async({browser})=>{
 const a=await member(browser,'ChatAnh'),b=await member(browser,'ChatBinh');try{
  expect((await b.context.request.post('/api/users/'+a.user.id+'/messages',{data:{body:'Chào bạn, mình kết nối nhé!'}})).status()).toBe(201);
  await a.page.locator('[data-tab=inbox]').first().click();await expect(a.page.locator('.inbox-row.is-unread')).toBeVisible();await expect(a.page.locator('.inbox-unread')).toHaveText('1');
  await a.page.getByRole('button',{name:'Chưa đọc',exact:true}).click();await expect(a.page.locator('.inbox-row')).toHaveCount(1);
  await a.page.getByRole('searchbox',{name:'Tìm cuộc trò chuyện'}).fill('not-found');await expect(a.page.locator('.inbox-row')).toHaveCount(0);await a.page.getByRole('searchbox',{name:'Tìm cuộc trò chuyện'}).fill('');
  await a.page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/390-messaging-list.png'});
  await a.page.locator('.inbox-row').click();await expect(a.page.locator('.bubble p')).toHaveText('Chào bạn, mình kết nối nhé!');
  await a.page.getByRole('textbox',{name:'Tin nhắn riêng'}).fill('Mình chào bạn!');await a.page.locator('.dm-compose').getByRole('button',{name:'Gửi',exact:true}).click();await expect(a.page.locator('.bubble.mine p')).toHaveText('Mình chào bạn!');
  await b.context.request.get('/api/notifications');await expect.poll(()=>a.page.locator('.message-receipt').last().innerText()).toBe('Đã nhận');await b.context.request.get('/api/users/'+a.user.id+'/messages');await expect.poll(()=>a.page.locator('.message-receipt').last().innerText()).toBe('Đã xem');
  await a.page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/390-messaging-chat.png'});
  await a.page.getByRole('button',{name:'Gọi video',exact:true}).click();await expect(b.page.getByRole('dialog',{name:'Cuộc gọi video'})).toBeVisible();
  expect(await b.page.locator('.call-local').evaluate(v=>v.srcObject)).toBeNull();
  await b.page.getByRole('button',{name:'Nhận cuộc gọi',exact:true}).click();
  await expect.poll(()=>a.page.locator('.call-remote').evaluate(v=>v.readyState),{timeout:20000}).toBeGreaterThanOrEqual(2);
  await expect.poll(()=>b.page.locator('.call-remote').evaluate(v=>v.readyState),{timeout:20000}).toBeGreaterThanOrEqual(2);
  await a.page.getByRole('button',{name:'Tắt mic',exact:true}).click();expect(await a.page.locator('.call-local').evaluate(v=>v.srcObject.getAudioTracks()[0].enabled)).toBe(false);
  await a.page.getByRole('button',{name:'Tắt camera',exact:true}).click();expect(await a.page.locator('.call-local').evaluate(v=>v.srcObject.getVideoTracks()[0].enabled)).toBe(false);
  await a.page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/390-video-call.png'});
  await a.page.evaluate(()=>window.callTracks=document.querySelector('.call-local').srcObject.getTracks());await a.page.getByRole('button',{name:'Kết thúc',exact:true}).click();await expect(b.page.locator('.video-call')).toHaveCount(0);expect(await a.page.evaluate(()=>window.callTracks.every(t=>t.readyState==='ended'))).toBe(true);
  await a.page.getByRole('button',{name:'Quay lại hộp thư'}).click();await a.page.getByRole('button',{name:'Tạo nhóm',exact:true}).click();await a.page.getByRole('textbox',{name:'Tên nhóm',exact:true}).fill('Hội bạn Kinnect');
  await a.page.getByRole('searchbox',{name:'Tìm thành viên nhóm'}).fill('ChatBinh');await a.page.locator('.group-candidate').filter({hasText:'ChatBinh'}).getByRole('checkbox').check();await a.page.getByRole('dialog').getByRole('button',{name:'Tạo nhóm',exact:true}).click();
  await expect(a.page.locator('.chat-identity b')).toHaveText('Hội bạn Kinnect');await a.page.getByRole('textbox',{name:'Tin nhắn nhóm'}).fill('Xin chào cả nhóm');await a.page.locator('.dm-compose').getByRole('button',{name:'Gửi',exact:true}).click();await expect(a.page.locator('.bubble p')).toHaveText('Xin chào cả nhóm');
  await b.page.locator('[data-tab=inbox]').first().click();await b.page.locator('.inbox-row').filter({hasText:'Hội bạn Kinnect'}).click();await expect(b.page.locator('.bubble p')).toHaveText('Xin chào cả nhóm');
  await a.page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/390-group-chat.png'});
  await a.page.getByRole('button',{name:'Thông tin nhóm',exact:true}).click();await expect(a.page.getByRole('dialog',{name:'Thông tin nhóm'})).toContainText('2 thành viên');
  expect(await a.page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBe(0);expect(a.errors).toEqual([]);expect(b.errors).toEqual([]);
 }finally{await a.context.close();await b.context.close();}
});
