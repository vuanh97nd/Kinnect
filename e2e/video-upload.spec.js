import {test,expect} from '@playwright/test';
import {fileURLToPath} from 'node:url';
test('Studio uploads an MP4 and publishes it to the video feed',async({browser})=>{
 const context=await browser.newContext({viewport:{width:1280,height:900},permissions:['camera','microphone']});
 const page=await context.newPage();
 try{
  const reg=await context.request.post('/api/register',{data:{username:'upload_ui_'+Date.now(),password:'abcdef',name:'Upload UI',agree18:true,acceptPrivacyNotice:true}});
  expect(reg.status()).toBe(200);
  await page.goto('/');
  await page.getByRole('button',{name:'Quay video',exact:true}).click();
  await expect(page.getByRole('dialog',{name:'Quay video'})).toBeVisible();
  await page.locator('.tt-gallery input').setInputFiles(fileURLToPath(new URL('../test/fixtures/short.mp4',import.meta.url)));
  await expect(page.locator('.tt-post')).toBeVisible();
  await page.getByLabel('Chú thích video',{exact:true}).fill('Kiểm tra tải lên');
  const uploaded=page.waitForResponse(response=>new URL(response.url()).pathname==='/api/shorts'&&response.request().method()==='POST');
  await page.getByRole('button',{name:'Chia sẻ',exact:true}).click();
  const response=await uploaded;expect(response.status()).toBe(201);const {id}=await response.json();
  await expect(page.locator('#notice')).toHaveText('Đã đăng video.');
  await expect(page.locator('.reel-item video').first()).toBeVisible();
  const feed=await (await context.request.get('/api/shorts')).json();
  expect(feed.shorts.find(video=>video.id===id)?.caption).toBe('Kiểm tra tải lên');
 }finally{await context.close();}
});
