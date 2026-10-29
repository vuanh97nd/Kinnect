import {test,expect} from '@playwright/test';
test('live theatre supports comments, gifts and switching on PC and mobile',async({browser})=>{
 const contexts=[];
 try{
 const member=async name=>{const context=await browser.newContext({viewport:{width:390,height:844}});contexts.push(context);await context.request.post('/api/register',{data:{username:name+Date.now(),name,password:'abcdef',agree18:true}});const page=await context.newPage();await page.goto('/');return page;};
 for(const name of ['StudioOne','StudioTwo']){const page=await member(name);await page.evaluate(name=>new Promise((resolve,reject)=>{const socket=window.designSocket=new WebSocket(location.origin.replace('http','ws'));const timeout=setTimeout(()=>reject(Error('Host socket timeout')),6000);socket.onopen=()=>socket.send(JSON.stringify({type:'create',title:name}));socket.onmessage=event=>{const m=JSON.parse(event.data);if(m.type==='joined'){clearTimeout(timeout);resolve();}if(m.type==='error'){clearTimeout(timeout);reject(Error(m.message));}};socket.onerror=()=>reject(Error('Host socket failed'));}),name);}
 const page=await member('StudioViewer');await page.locator('[data-tab=shorts]').first().click();await page.getByRole('button',{name:'Các buổi đang live'}).click();await expect(page.locator('.live-card')).toHaveCount(2);await page.locator('.live-card').first().click();await expect(page.locator('#live')).toBeVisible();const title=await page.locator('#room-title').textContent();
 await page.locator('#message').fill('Chào mọi người!');await page.locator('#chat button').click();await expect(page.locator('#messages')).toContainText('Chào mọi người!');await page.locator('#gift').click();
 const surface=page.locator('#live .video-wrap');await surface.dispatchEvent('touchstart',{touches:[{identifier:1,clientX:120,clientY:400}]});await surface.dispatchEvent('touchend',{changedTouches:[{identifier:1,clientX:120,clientY:160}]});await expect(page.locator('#room-title')).not.toHaveText(title);
 for(const width of [1440,390]){await page.setViewportSize({width,height:844});const bounds=await page.locator('#chat').boundingBox();expect(bounds.x).toBeGreaterThanOrEqual(0);expect(bounds.x+bounds.width).toBeLessThanOrEqual(width);await expect(page.locator('.live-play')).toBeVisible();await expect(page.locator('#gift')).toBeVisible();}
 await page.locator('#live-browse').click();await expect(page.locator('#live')).toBeHidden();
 }finally{for(const c of contexts){for(const p of c.pages())await p.evaluate(()=>window.designSocket?.close()).catch(()=>{});await c.close();}}
});
