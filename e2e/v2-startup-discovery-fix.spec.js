import {test,expect} from '@playwright/test';
import {createApp} from '../server.js';
async function start(){const a=createApp({authLimit:200});await new Promise(r=>a.server.listen(0,'127.0.0.1',r));return {a,baseURL:'http://127.0.0.1:'+a.server.address().port};}
async function stop(a){for(const ws of a.wss.clients)ws.terminate();a.wss.close();a.server.closeAllConnections();await new Promise(r=>a.server.close(r));a.social.close();}
test('cold mobile startup reveals only the ready layout and discovery photos keep square bounds',async({browser})=>{
 const {a,baseURL}=await start(),c=await browser.newContext({baseURL,isMobile:true,viewport:{width:390,height:844}});
 try{await c.request.post('/api/register',{data:{username:'photo_owner',name:'Owner',password:'abcdef',agree18:true,acceptPrivacyNotice:true}});
 for(let i=0;i<6;i++)a.social.db.prepare('INSERT INTO users(id,username,password,salt,name,birth_date,created,avatar) SELECT ?,?,password,salt,?,birth_date,?,? FROM users LIMIT 1').run('photo-'+i,'photo_peer_'+i,'Person '+i,Date.now(),'/test-avatar-'+i+'.svg');
 const p=await c.newPage();let release;const ready=new Promise(r=>release=r);await p.route('**/health',async r=>{await ready;await r.continue();});
 await p.goto('/');await expect(p.locator('#kinnect-boot')).toBeVisible();await expect(p.locator('#kn')).toBeHidden();expect(await p.evaluate(()=>visualViewport.scale)).toBe(1);release();await expect(p.locator('#kinnect-boot')).toHaveCount(0);await expect(p.locator('#kn')).toBeVisible();
 let imagesReady;let imageGate=new Promise(r=>imagesReady=r);await p.route('**/api/users/photo-*/avatar',async r=>{await imageGate;const portrait=r.request().url().includes('photo-0/');await r.fulfill({contentType:'image/svg+xml',body:'<svg xmlns="http://www.w3.org/2000/svg" width="'+(portrait?1200:2400)+'" height="'+(portrait?2400:1200)+'"><rect width="100%" height="100%" fill="purple"/></svg>'});});
 await p.getByRole('button',{name:'Khám phá',exact:true}).last().click();await expect(p.locator('.native-person-tile')).toHaveCount(6);
 const before=await p.locator('.native-person-tile').first().boundingBox();imagesReady();await expect.poll(()=>p.locator('.native-person-tile img').first().evaluate(e=>e.complete&&e.naturalWidth>0)).toBe(true);
 for(const width of [320,390,430,460,768]){await p.setViewportSize({width,height:844});const tiles=await p.locator('.native-person-tile').evaluateAll(es=>es.map(e=>{const r=e.getBoundingClientRect(),i=e.querySelector('img').getBoundingClientRect();return {w:r.width,h:r.height,x:r.x,y:r.y,iw:i.width,ih:i.height,ix:i.x,iy:i.y,padding:getComputedStyle(e).padding};}));for(const t of tiles){expect(Math.abs(t.w-t.h)).toBeLessThanOrEqual(1);expect(Math.abs(t.iw-t.w)).toBeLessThanOrEqual(1);expect(Math.abs(t.ih-t.h)).toBeLessThanOrEqual(1);expect(t.ix).toBe(t.x);expect(t.iy).toBe(t.y);expect(t.padding).toBe('0px');}expect(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);expect(await p.evaluate(()=>visualViewport.scale)).toBe(1);if(width===390){const after=await p.locator('.native-person-tile').first().boundingBox();expect(Math.abs(before.height-after.height)).toBeLessThanOrEqual(1);await p.screenshot({path:'work/discovery-photos-fixed.png'});}}
 }finally{await c.close();await stop(a);}
});
test('PC keeps the previous portrait wall login while mobile keeps its own login',async({browser})=>{
 const {a,baseURL}=await start(),c=await browser.newContext({baseURL,viewport:{width:1366,height:900}});
 try{const p=await c.newPage();await p.goto('/?s=login');await expect(p.locator('.auth-shell .auth-wall')).toBeVisible();await expect(p.locator('.auth-main [data-auth-form=login]')).toBeVisible();await expect(p.locator('.native-auth-shell')).toHaveCount(0);expect(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await p.screenshot({path:'work/pc-login-restored.png'});await p.setViewportSize({width:390,height:844});await expect(p.locator('.native-auth-main [data-auth-form=login]')).toBeVisible();await expect(p.locator('.auth-wall')).toHaveCount(0);
 }finally{await c.close();await stop(a);}
});



test('mobile login and signup scroll on short screens and use the white K asset',async({browser})=>{
 const {a,baseURL}=await start(),c=await browser.newContext({baseURL,isMobile:true,viewport:{width:390,height:380}});
 try{const p=await c.newPage();await p.goto('/?s=login');await expect(p.locator('.native-auth-main')).toBeVisible();
 for(const screen of ['login','signup']){if(screen==='signup')await p.getByRole('button',{name:'Tạo tài khoản mới',exact:true}).click();const scroll=p.locator('.app.auth-mode');const dimensions=await scroll.evaluate(e=>({client:e.clientHeight,total:e.scrollHeight,overflow:getComputedStyle(e).overflowY}));expect(dimensions.total).toBeGreaterThan(dimensions.client);expect(dimensions.overflow).toBe('auto');await scroll.hover();await p.mouse.wheel(0,2000);await expect.poll(()=>scroll.evaluate(e=>e.scrollTop)).toBeGreaterThan(0);const submit=p.locator('[data-auth-form="'+screen+'"] button[type=submit]');await submit.scrollIntoViewIfNeeded();const row=await scroll.boundingBox(),button=await submit.boundingBox();expect(button.y).toBeGreaterThanOrEqual(row.y);expect(button.y+button.height).toBeLessThanOrEqual(row.y+row.height+1);await p.setViewportSize({width:390,height:300});await p.locator('[data-auth-input=username]').focus();await expect.poll(()=>scroll.evaluate(e=>e.clientHeight)).toBe(300);await submit.scrollIntoViewIfNeeded();await p.setViewportSize({width:390,height:380});}
 const image=p.locator('.auth-logo img');await expect(image).toHaveAttribute('src','/kinnect-icon-192.png');expect(await image.evaluate(e=>e.complete&&e.naturalWidth>0)).toBe(true);await p.screenshot({path:'work/mobile-auth-scroll-fixed.png'});
 }finally{await c.close();await stop(a);}
});

test('reload clears retained phone zoom before first paint and releases pinch zoom after boot',async({browser})=>{
 const {a,baseURL}=await start(),c=await browser.newContext({baseURL,isMobile:true,deviceScaleFactor:3,viewport:{width:390,height:844}});
 try{const p=await c.newPage();await p.addInitScript(()=>{window.startupScales=[];let frames=0;const record=()=>{window.startupScales.push(visualViewport.scale);if(++frames<180)requestAnimationFrame(record);};requestAnimationFrame(record);});
 await p.goto('/');await expect(p.locator('#kinnect-boot')).toHaveCount(0);const session=await c.newCDPSession(p);await session.send('Emulation.setPageScaleFactor',{pageScaleFactor:1.8});expect(await p.evaluate(()=>visualViewport.scale)).toBeGreaterThan(1.7);
 await p.reload();await expect(p.locator('#kinnect-boot')).toHaveCount(0);const scales=await p.evaluate(()=>startupScales);expect(scales.length).toBeGreaterThan(0);expect(scales.every(value=>Math.abs(value-1)<.01)).toBe(true);expect(await p.evaluate(()=>visualViewport.width)).toBe(390);await expect(p.locator('meta[name=viewport]')).not.toHaveAttribute('content',/maximum-scale/);
 await session.send('Emulation.setPageScaleFactor',{pageScaleFactor:1.5});expect(await p.evaluate(()=>visualViewport.scale)).toBeGreaterThan(1.4);
 }finally{await c.close();await stop(a);}
});
