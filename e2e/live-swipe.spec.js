import {test,expect} from '@playwright/test';
import {WebSocket} from 'ws';
import {once} from 'node:events';
test('Video live keeps creation in camera and switches streams vertically',async({browser,baseURL})=>{
 const contexts=[],sockets=[];
 try{
 const account=async name=>{const c=await browser.newContext();contexts.push(c);const r=await c.request.post('/api/register',{data:{username:name+Date.now(),name,password:'abcdef',agree18:true}});expect(r.ok()).toBeTruthy();return c;};
 for(const title of ['Live One','Live Two']){const c=await account(title.replaceAll(' ','')),cookies=await c.cookies();const ws=new WebSocket(baseURL.replace('http','ws'),{headers:{Cookie:cookies.map(x=>x.name+'='+x.value).join('; ')}});sockets.push(ws);await once(ws,'open');const joined=new Promise(resolve=>{ws.on('message',raw=>{const m=JSON.parse(raw);if(m.type==='joined')resolve(m);});});ws.send(JSON.stringify({type:'create',title,name:title}));await joined;}
 const c=await account('LiveViewer'),p=await c.newPage();await p.goto('/');await p.locator('[data-tab=shorts]').first().click();await p.getByRole('button',{name:'Các buổi đang live'}).click();await expect(p.locator('.live-card')).toHaveCount(2);await p.locator('.live-card').first().click();await expect(p.locator('#live')).toBeVisible();await expect(p.locator('#create')).toBeHidden();const first=await p.locator('#room-title').textContent();
 await p.getByRole('button',{name:'Buổi trực tiếp tiếp theo',exact:true}).click();await expect(p.locator('#room-title')).not.toHaveText(first);
 const surface=p.locator('#live .video-wrap');await surface.dispatchEvent('touchstart',{touches:[{identifier:1,clientX:120,clientY:300}]});await surface.dispatchEvent('touchend',{changedTouches:[{identifier:1,clientX:120,clientY:100}]});await expect(p.locator('#room-title')).toHaveText(first);
 await p.getByRole('button',{name:'Quay lại danh sách trực tiếp'}).click();await expect(p.locator('.live-card')).toHaveCount(2);await expect(p.locator('#live')).toBeHidden();
 }finally{for(const ws of sockets)ws.close();for(const c of contexts)await c.close();}
});
