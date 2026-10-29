import {test,expect} from '@playwright/test';
test('video call connects two peers with compact preview and audio output control',async({browser})=>{
 const contexts=[];try{
 const users=[];for(const name of ['Caller','Receiver']){const c=await browser.newContext({viewport:{width:390,height:844},permissions:['camera','microphone']});contexts.push(c);await c.route('**/api/call-config',route=>route.fulfill({json:{iceServers:[]}}));const r=await c.request.post('/api/register',{data:{username:name.toLowerCase()+Date.now(),name,password:'abcdef',agree18:true}});users.push((await r.json()).user);}
 const a=await contexts[0].newPage(),b=await contexts[1].newPage();await a.goto('/?chat='+users[1].id);await b.goto('/?chat='+users[0].id);
 // Chờ cả hai trang vào xong màn chat VÀ WebSocket đã sẵn sàng trước khi bấm gọi.
 await Promise.all([a,b].map(page=>Promise.all([
   expect(page.getByRole('button',{name:'Gọi video',exact:true})).toBeVisible(),
   expect(page.locator('#connection')).toHaveText('Đã kết nối'),
 ])));
 await a.getByRole('button',{name:'Gọi video',exact:true}).click();await expect(b.getByRole('button',{name:'Nhận cuộc gọi',exact:true})).toBeVisible({timeout:20000});await b.getByRole('button',{name:'Nhận cuộc gọi',exact:true}).click();
 for(const page of [a,b]){await expect(page.locator('.video-call')).toHaveClass(/is-connected/,{timeout:20000});await expect(page.getByRole('button',{name:'Chọn loa và âm thanh'})).toBeVisible();await expect.poll(()=>page.locator('.call-remote').evaluate(v=>v.videoWidth)).toBeGreaterThan(0);const box=await page.locator('.call-local').boundingBox();expect(box.width/box.height).toBeCloseTo(4/3,1);}
 await a.getByRole('button',{name:'Kết thúc',exact:true}).click();await expect(b.locator('.video-call')).toHaveCount(0);
 }finally{for(const c of contexts)await c.close();}
});
