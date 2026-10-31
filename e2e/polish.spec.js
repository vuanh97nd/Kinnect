import {test,expect} from '@playwright/test';
for(const width of [320,390,1440])test('v2 polish survives legacy CSS at '+width,async({browser})=>{
 const c=await browser.newContext({viewport:{width,height:900}});
 try{
  const registration=await c.request.post('/api/register',{data:{username:'polish'+width+Date.now(),name:'Quân',password:'abcdef',agree18:true,acceptPrivacyNotice:true}});expect(registration.ok()).toBeTruthy();const {user}=await registration.json();
  const posted=await c.request.post('/api/posts',{data:{body:'Một ngày mới trên Kinnect. Chia sẻ khoảnh khắc và kết nối bạn bè.'}});
  const postId=(await posted.json()).id;
  await c.addInitScript(id=>localStorage.setItem('kinnect-profile-prompt:'+id,'pending'),user.id);
  const page=await c.newPage();await page.goto('/?tab=feed');await expect(page.locator('[data-post-id="'+postId+'"]')).toBeVisible();
  const icon=page.locator('#friends-button'),avatar=page.locator('#me-btn .avatar'),notice=page.locator('#notice');
  await expect(icon).toHaveCSS('border-radius','999px');await expect(avatar).toHaveCSS('width','30px');expect(await avatar.evaluate(e=>getComputedStyle(e).boxShadow)).toContain('2px');
  expect(await page.locator('.profile-completion-actions .primary').evaluate(e=>getComputedStyle(e).boxShadow)).not.toBe('none');
  expect((await page.locator('[data-post-id="'+postId+'"]').evaluate(e=>getComputedStyle(e).boxShadow)).match(/rgba?\(/g)).toHaveLength(2);
  await expect(page.locator('[data-post-id="'+postId+'"]')).toHaveCSS('border-radius','20px');await expect(notice).toHaveClass(/show/);
  const rect=await notice.boundingBox();if(width>=1000){expect(Math.abs(width-rect.x-rect.width-24)).toBeLessThan(1);}else expect(Math.abs(rect.x+rect.width/2-width/2)).toBeLessThan(1);
  if(width===390||width===1440)await page.screenshot({path:test.info().outputPath('polish-'+width+'.png')});
  await expect(notice).not.toHaveClass(/show/,{timeout:3000});await expect(notice).toHaveCSS('opacity','0');
  await icon.hover();await expect.poll(()=>icon.evaluate(e=>getComputedStyle(e).backgroundColor)).not.toBe('rgba(0, 0, 0, 0)');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 }finally{await c.close();}
});
