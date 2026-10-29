import {test,expect} from '@playwright/test';
import {createApp} from '../server.js';
test('phone focus preserves readable fields and chat composer stays aligned',async({browser})=>{
 const app=createApp({authLimit:200});await new Promise(r=>app.server.listen(0,'127.0.0.1',r));const baseURL='http://127.0.0.1:'+app.server.address().port;
 const c=await browser.newContext({baseURL,isMobile:true,viewport:{width:390,height:844}}),other=await browser.newContext({baseURL});
 try{
 const p=await c.newPage();
 for(const width of [320,390,430,768]){await p.setViewportSize({width,height:844});await p.goto('/');const input=p.locator('[data-auth-input=username]');await expect(input).toBeVisible();await input.focus();expect(await input.evaluate(e=>parseFloat(getComputedStyle(e).fontSize))).toBeGreaterThanOrEqual(16);expect(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);expect(await p.evaluate(()=>visualViewport.scale)).toBe(1);}
 await c.request.post('/api/register',{data:{username:'compose_self',name:'Self',password:'abcdef',agree18:true}});
 const u=(await(await other.request.post('/api/register',{data:{username:'compose_other',name:'Other',password:'abcdef',agree18:true}})).json()).user;
 await c.request.post('/api/users/'+u.id+'/messages',{data:{body:'Hello'}});
 for(const width of [320,390,430,460,768,900,1280]){
 await p.setViewportSize({width,height:844});await p.goto('/?s=inbox');await p.locator('.v2-conversation').first().click();const form=p.locator('form[data-community-send]'),field=form.locator('textarea');await expect(form).toBeVisible();await expect(field).toBeVisible();
 if(width<900){const row=await form.boundingBox(),nav=await p.locator('.bottom').boundingBox();expect(row.x).toBe(0);expect(Math.abs(row.width-width)).toBeLessThanOrEqual(1);expect(Math.abs(row.y+row.height-nav.y)).toBeLessThanOrEqual(1);}
 for(const value of ['', 'Nội dung nhiều dòng\nĐây là dòng thứ hai để kiểm tra căn chỉnh']){await field.fill(value);const boxes=await form.evaluate(e=>[e,...e.children].map(x=>{const r=x.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height}}));const [row,...children]=boxes;for(const x of children){expect(x.x).toBeGreaterThanOrEqual(row.x);expect(x.x+x.w).toBeLessThanOrEqual(row.x+row.w+1);expect(Math.abs(x.y+x.h/2-(row.y+row.h/2))).toBeLessThanOrEqual(1);}expect(children[2].w).toBeGreaterThanOrEqual(100);expect(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);}
 if(width===390||width===1280)await p.screenshot({path:'work/web-layout-fixed-'+width+'.png'});
 }

 }finally{await c.close();await other.close();for(const ws of app.wss.clients)ws.terminate();app.wss.close();app.server.closeAllConnections();await new Promise(r=>app.server.close(r));app.social.close();}
});



