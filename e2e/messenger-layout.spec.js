import {test,expect} from '@playwright/test';
for(const width of [1440,1024,390])test('messenger layout and delivery '+width,async({browser,baseURL})=>{
 const sender=await browser.newContext({viewport:{width,height:844}}),receiver=await browser.newContext();
 try{
  const stamp=Date.now();await sender.request.post('/api/register',{data:{username:'layouta'+stamp,name:'Hoàng Nam',password:'abcdef',agree18:true}});
  const r=await receiver.request.post('/api/register',{data:{username:'layoutb'+stamp,name:'Minh Anh',password:'abcdef',agree18:true}});const user=(await r.json()).user;
  await sender.request.post('/api/users/'+user.id+'/messages',{data:{body:'Cuối tuần mình đi cà phê nhé? ☕'}});
  const page=await sender.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto('/?chat='+user.id);
  const side=page.locator('.messenger-sidebar');await expect(page.locator('.chat-identity b')).toHaveText('Minh Anh');
  if(width>=1000){await expect(side).toBeVisible();await expect(side.locator('.inbox-row.is-selected')).toHaveCount(1);const a=await side.boundingBox(),b=await page.locator('.chat-box').boundingBox();expect(a.x+a.width).toBeLessThanOrEqual(b.x+1);expect(b.width).toBeGreaterThan(280);}
  else await expect(side).toBeHidden();
  await page.getByRole('textbox',{name:'Tin nhắn riêng',exact:true}).fill('Hẹn bạn chiều thứ bảy nhé!');await page.locator('.dm-compose').getByRole('button',{name:'Gửi',exact:true}).click();await expect(page.locator('.bubble p').last()).toHaveText('Hẹn bạn chiều thứ bảy nhé!');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBe(0);
  await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-25/m-nh-xu-t-l-m/outputs/messenger-actual-'+width+'.png'});
  if(width>=1000){await side.locator('.inbox-open').click();await expect(page.locator('.bubble p').last()).toHaveText('Hẹn bạn chiều thứ bảy nhé!');}
  else{await page.getByRole('button',{name:'Quay lại hộp thư'}).click();await expect(page.locator('.inbox-open').first()).toBeVisible();}
  expect(errors).toEqual([]);
 }finally{await sender.close();await receiver.close();}
});
