import {test,expect} from '@playwright/test';
test('real message and friendship notifications arrive without reload, including overlapping requests',async({browser})=>{
 const a=await browser.newContext(),b=await browser.newContext();
 try{
 const register=async(c,n)=>(await (await c.request.post('/api/register',{data:{username:n+Date.now(),name:n,password:'abcdef',agree18:true}})).json()).user;
 const ua=await register(a,'noticea'),ub=await register(b,'noticeb');const p=await a.newPage();await p.goto('/');await expect(p.locator('#app')).toBeVisible();
 await expect.poll(()=>p.evaluate(()=>document.querySelector('#unread').textContent)).toBe('');
 const socketEvent=p.waitForEvent('websocket'); // reconnect below also verifies recovery refresh
 await p.reload();await socketEvent;await expect(p.locator('#app')).toBeVisible();
 await b.request.post('/api/users/'+ua.id+'/messages',{data:{body:'Tin nhắn thực tế'}});
 await expect(p.locator('[data-tab="inbox"] .nav-count')).toHaveText('1',{timeout:5000});
 await b.request.post('/api/users/'+ua.id+'/friend-request',{data:{}});
 await expect(p.locator('#friends-count')).toHaveText('+1',{timeout:5000});
 await p.locator('#notification-bell').click();await expect(p.locator('#notification-center')).toContainText('đã gửi lời mời kết bạn');await expect(p.locator('#notification-center')).toContainText('đã gửi tin nhắn');await p.keyboard.press('Escape');
 // Delay a stale snapshot while a new event arrives. It must trigger a fresh fetch immediately.
 let release;const gate=new Promise(r=>release=r);let intercepted=false;
 await p.route('**/api/notifications',async route=>{if(intercepted||route.request().method()!=='GET')return route.continue();intercepted=true;const response=await route.fetch();await gate;await route.fulfill({response});});
 await p.evaluate(()=>window.dispatchEvent(new Event('kinnect-notifications')));await expect.poll(()=>intercepted).toBeTruthy();
 await b.request.post('/api/users/'+ua.id+'/messages',{data:{body:'Thông báo trong lúc đang tải'}});await p.waitForTimeout(150);release();
 await expect(p.locator('[data-tab="inbox"] .nav-count')).toHaveText('2',{timeout:4000});
 await p.unroute('**/api/notifications');await p.getByRole('button',{name:'Bạn bè',exact:true}).click();await p.getByRole('tab',{name:'Lời mời',exact:true}).click();await p.getByRole('button',{name:'Xác nhận kết bạn',exact:true}).click();await expect(p.locator('#friends-count')).toBeHidden();
 }finally{await a.close();await b.close();}
});
