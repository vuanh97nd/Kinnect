import {test,expect} from '@playwright/test';
import {createApp} from '../server.js';
test('discovery search, filters, profiles and responsive cards',async({browser})=>{
 const app=createApp({authLimit:300});await new Promise(r=>app.server.listen(0,'127.0.0.1',r));
 const baseURL='http://127.0.0.1:'+app.server.address().port,c=await browser.newContext({baseURL}),peer=await browser.newContext({baseURL});
 try{
 await c.request.post('/api/register',{data:{username:'discover_owner',name:'Chủ thử',password:'abcdef',agree18:true}});
 await peer.request.post('/api/register',{data:{username:'discover_linh',name:'Ngọc Linh',password:'abcdef',agree18:true}});
 const p=await c.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));await p.goto('/?s=discover');
 await expect(p.locator('.discover-person')).toHaveCount(1);
 await p.getByLabel('Tìm người theo tên hoặc username').fill('khongtontai');await p.getByRole('button',{name:'Tìm kiếm',exact:true}).click();await expect(p.locator('.discover-person')).toHaveCount(0);
 await p.getByRole('button',{name:'Xem tất cả thành viên'}).click();await expect(p.locator('.discover-person')).toHaveCount(1);
 await p.getByRole('button',{name:'Âm nhạc',exact:true}).click();await expect(p.locator('.discover-person')).toHaveCount(0);
 await p.getByRole('button',{name:'Xem tất cả thành viên'}).click();
 for(const width of [320,390,900,1440]){await p.setViewportSize({width,height:900});expect(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);await expect(p.getByRole('button',{name:'Xem hồ sơ',exact:true})).toBeVisible();if(width===390||width===1440)await p.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-27/ti-p-t-c/outputs/kham-pha-'+width+'.png',fullPage:true});}
 await p.getByRole('button',{name:'Quanh đây',exact:true}).click();await p.getByLabel('Bán kính tìm kiếm').selectOption('10');await expect(p.getByLabel('Bán kính tìm kiếm')).toHaveValue('10');
 await p.getByRole('button',{name:'Đang theo dõi',exact:true}).click();await expect(p.getByText('Bạn chưa theo dõi thành viên nào',{exact:true})).toBeVisible();
 await p.getByRole('button',{name:'Xem tất cả thành viên'}).click();await p.getByRole('button',{name:'Xem hồ sơ',exact:true}).click();await expect(p.locator('.app')).toHaveAttribute('data-screen','profile');expect(errors).toEqual([]);
 }finally{await c.close();await peer.close();for(const ws of app.wss.clients)ws.terminate();app.wss.close();app.server.closeAllConnections();await new Promise(r=>app.server.close(r));app.social.close();}
});
