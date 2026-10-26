import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
async function openReels(browser,width){
 const context=await browser.newContext({viewport:{width,height:844}});
 await context.request.post('/api/register',{data:{username:'no_fullscreen_'+width+'_'+Date.now(),password:'abcdef',name:'Video viewer',agree18:true}});
 const bytes=await readFile(new URL('../test/fixtures/short.mp4',import.meta.url));
 const response=await context.request.post('/api/shorts',{data:{caption:'Video kiểm tra',data:'data:video/mp4;base64,'+bytes.toString('base64')}});
 expect(response.status()).toBe(201);
 const {id}=await response.json();
 const page=await context.newPage();await page.goto('/?video='+id);
 await expect(page.locator('.reel-item video').first()).toBeVisible();
 return {context,page};
}
for(const width of [390,1280])test('video viewer hides the fullscreen button at '+width+'px',async({browser})=>{
 const {context,page}=await openReels(browser,width);
 try{
  await expect(page.locator('.reel-fullscreen')).toHaveCount(0);
  await expect(page.getByRole('button',{name:/Toàn màn hình/})).toHaveCount(0);
  await expect(page.locator('.reel-feed-tabs > button')).toHaveCount(3);
  await expect(page.locator('.reel-item video').first()).toHaveAttribute('controlslist',/nofullscreen/);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBeTruthy();
 }finally{await context.close();}
});
