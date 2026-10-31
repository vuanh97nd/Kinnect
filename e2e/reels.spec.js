import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
for(const width of [320,390,1440])test('video comments, sound and share at '+width,async({browser})=>{
 const context=await browser.newContext({viewport:{width,height:900},permissions:['clipboard-read','clipboard-write']});
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 try{
  const r=await context.request.post('/api/register',{data:{username:'reel_'+width+'_'+Date.now(),password:'abcdef',name:'Bạn Kinnect',agree18:true,acceptPrivacyNotice:true}});expect(r.status()).toBe(200);
  const bytes=await readFile(new URL('../test/fixtures/short.mp4',import.meta.url));
  const uploaded=await context.request.post('/api/shorts',{data:{caption:'Một khoảnh khắc trên Kinnect',data:'data:video/mp4;base64,'+bytes.toString('base64')}});expect(uploaded.status()).toBe(201);const {id}=await uploaded.json();
  await page.goto('/?video='+id);await expect(page.locator('.reel-item').first()).toBeVisible();
  if(width>=1000){await expect(page.locator('#app>header')).toBeVisible();await expect(page.locator('#app>nav')).toBeVisible();await expect(page.locator('#rail')).toBeVisible();expect(await page.locator('#app').evaluate(el=>getComputedStyle(el).gridTemplateColumns.split(' ').length)).toBe(3);const center=await page.locator('#social-panel').boundingBox(),actions=await page.locator('.reel-side').first().boundingBox(),creator=await page.locator('.reel-meta').first().boundingBox();expect(actions.x).toBeGreaterThanOrEqual(center.x);expect(actions.x+actions.width).toBeLessThanOrEqual(center.x+center.width);expect(creator.x).toBeGreaterThanOrEqual(center.x);expect(creator.x+creator.width).toBeLessThanOrEqual(center.x+center.width);}
  await expect(page.locator('#auth')).toBeHidden();
  await expect(page.locator('#app>header .logo')).toBeVisible();
  expect(await page.locator('#app>header .logo').evaluate(img=>img.naturalWidth)).toBeGreaterThan(0);
  const navBoxes=await page.locator('.reel-feed-tabs>button').evaluateAll(buttons=>buttons.map(b=>{const r=b.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height,overflow:b.scrollWidth>b.clientWidth};}));
  expect(navBoxes).toHaveLength(3);
  for(const b of navBoxes){expect(b.y).toBe(navBoxes[0].y);expect(b.h).toBe(48);expect(b.overflow).toBe(false);}
  expect(Math.abs(navBoxes[0].w-navBoxes[1].w)).toBeLessThan(1);
  expect(Math.abs(navBoxes[1].w-navBoxes[2].w)).toBeLessThan(1);
  for(let i=1;i<navBoxes.length;i++)expect(navBoxes[i].x).toBeGreaterThanOrEqual(navBoxes[i-1].x+navBoxes[i-1].w-1);

  await expect(page.locator('.reel-action').first().locator('svg')).toBeVisible();
  await expect(page.getByRole('button',{name:'Tắt âm thanh',exact:true}).first()).toBeVisible();
  await page.getByRole('button',{name:'Tắt âm thanh',exact:true}).first().click();
  await expect(page.getByRole('button',{name:'Bật âm thanh',exact:true}).first()).toBeVisible();
  await page.locator('.reel-item video').first().evaluate(v=>v.play());
  await page.getByRole('button',{name:'Bình luận video',exact:true}).first().click();
  await expect.poll(()=>page.locator('.reel-item video').first().evaluate(v=>v.paused)).toBe(false);
  await page.getByRole('textbox',{name:'Bình luận của bạn'}).fill('Giao diện mới đẹp hơn');
  await page.getByRole('button',{name:'Gửi bình luận',exact:true}).click();
  await expect(page.locator('.rc-item .rc-text')).toHaveText('Giao diện mới đẹp hơn');
  await page.getByRole('button',{name:'Thích bình luận',exact:true}).click();await expect(page.getByRole('button',{name:'Bỏ thích bình luận',exact:true})).toContainText('1');
  await page.locator('.rc-meta').getByRole('button',{name:'Trả lời',exact:true}).click();await page.getByRole('textbox',{name:'Bình luận của bạn'}).fill('Mình trả lời bình luận này');await page.getByRole('button',{name:'Gửi bình luận',exact:true}).click();await page.getByRole('button',{name:'Xem 1 câu trả lời',exact:true}).click();await expect(page.locator('.rc-replies')).toContainText('Mình trả lời bình luận này');
  expect(await page.locator('.reel-item video').first().evaluate(v=>v.paused)).toBe(false);

  await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/'+width+'-comments.png'});
  await page.getByRole('button',{name:'Đóng bình luận',exact:true}).click();
  await page.evaluate(()=>{Object.defineProperty(navigator,'share',{value:undefined,configurable:true});});
  await page.getByRole('button',{name:'Chia sẻ video',exact:true}).first().click();
  await expect.poll(()=>page.evaluate(()=>navigator.clipboard.readText())).toContain('video='+id);
  await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/'+width+'-video-redesigned.png'});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBe(0);
  await page.getByRole('button',{name:'Báo cáo video',exact:true}).first().click();
  await expect(page.getByRole('dialog',{name:'Báo cáo video'})).toBeVisible();
  const bounds=await page.locator('.report-sheet').boundingBox();
  expect(Math.abs(bounds.x-(width-bounds.x-bounds.width))).toBeLessThanOrEqual(1);
  expect(bounds.x).toBeGreaterThanOrEqual(0);expect(bounds.x+bounds.width).toBeLessThanOrEqual(width);
  expect(await page.locator('.report-sheet').evaluate(el=>el.scrollWidth-el.clientWidth)).toBe(0);
  await page.getByLabel('Lừa đảo hoặc spam',{exact:true}).check();
  await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/'+width+'-report-video.png'});
  const sent=page.waitForResponse(r=>r.url().endsWith('/api/reports')&&r.request().method()==='POST');
  await page.getByRole('button',{name:'Gửi báo cáo',exact:true}).click();expect((await sent).ok()).toBeTruthy();
  await expect(page.getByText('Đã gửi báo cáo',{exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Xong',exact:true}).click();
  await expect(page.locator('.report-sheet')).toHaveCount(0);
  expect(errors).toEqual([]);
 }finally{await context.close()}
});
