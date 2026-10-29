import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
test('feed publishes media and followed stories open in a vertical viewer',async({browser})=>{
 const context=await browser.newContext({viewport:{width:390,height:844}}),page=await context.newPage();
 try{
  const username='feed_'+Date.now();const registered=await context.request.post('/api/register',{data:{username,password:'abcdef',name:'Bạn đăng tin',agree18:true}});expect(registered.status()).toBe(200);
  await page.goto('/');await expect(page.locator('#app')).toBeVisible();
  await page.locator('[data-tab="feed"]').first().click();await expect(page.locator('.composer')).toBeVisible();
  await expect(page.locator('.composer-tools')).toBeHidden();
  await expect(page.locator('.composer-story')).toBeHidden();
  await page.getByLabel('Nội dung bài viết').click();
  await expect(page.locator('.composer-tools')).toBeVisible();
  await page.getByLabel('Ảnh hoặc video cho bài viết').setInputFiles(new URL('../public/apple-touch-icon.png',import.meta.url).pathname.replace(/^\/(C:)/,'$1'));
  await expect.poll(()=>page.locator('.composer-preview img').evaluate(img=>img.naturalWidth)).toBeGreaterThan(0);
  await page.getByLabel('Nội dung bài viết').fill('Ảnh mới trên bảng tin');await page.locator('.composer').getByRole('button',{name:'Chia sẻ',exact:true}).click();
  await expect(page.locator('.post-media').first()).toBeVisible();
  await expect(page.locator('.composer-tools')).toBeHidden();
  await page.getByLabel('Nội dung bài viết').click();
  await page.getByLabel('Đăng vào tin · 24 giờ').check();await page.getByLabel('Nội dung bài viết').fill('Tin mới của mình');
  await page.getByLabel('Ảnh hoặc video cho bài viết').setInputFiles(new URL('../public/apple-touch-icon.png',import.meta.url).pathname.replace(/^\/(C:)/,'$1'));
  await page.locator('.composer').getByRole('button',{name:'Chia sẻ',exact:true}).click();
  await page.getByRole('button',{name:'Xem tin của Bạn đăng tin',exact:true}).click();
  await expect(page.getByRole('dialog',{name:'Xem tin',exact:true})).toBeVisible();await expect(page.locator('.story-content img')).toBeVisible();
  await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/390-story.png'});
  await page.getByRole('button',{name:'Đóng tin',exact:true}).click();
 }finally{await context.close();}
});
