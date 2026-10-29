import {test,expect} from '@playwright/test';
async function account(page,name){
 await page.goto('/');
 const r = await page.request.post('/api/register',{data:{username:name.slice(0,15)+'_'+Date.now(),password:'abcdef',name,agree18:true,acceptPrivacyNotice:true}}); expect(r.status(), await r.text()).toBe(200);
 expect((await page.request.get('/api/me')).status()).toBe(200);
 await page.reload();
 const skip=page.getByRole('button',{name:'Bỏ qua',exact:true});
 if(await skip.isVisible()) await skip.click();
 await expect(page.locator('#app')).toBeVisible();
}
test('valid session survives notification outage on reload',async({page})=>{
 await account(page,'session_reload_a');
 await page.route('**/api/notifications',route=>route.fulfill({status:503,json:{error:'Temporary outage'}}));
 await page.reload();
 await expect(page.locator('#app')).toBeVisible();
 await expect(page.locator('#auth')).toBeHidden();
 await expect(page.locator('.view-discover')).toBeVisible();
});
test('isolated background 401 does not discard a valid session',async({page})=>{
 await account(page,'session_background_a');
 await page.route('**/api/notifications',route=>route.fulfill({status:401,json:{error:'Temporary authentication failure'}}));
 await page.evaluate(()=>window.dispatchEvent(new Event('kinnect-notifications')));
 await expect(page.locator('#app')).toBeVisible();
 await expect.poll(()=>page.request.get('/api/me').then(r=>r.status())).toBe(200);
 await page.waitForTimeout(300);
 await expect(page.locator('#auth')).toBeHidden();
});

test('revoked session returns to login with an explanation',async({page})=>{
 await account(page,'session_revoked');
 await page.context().clearCookies();
 await page.evaluate(()=>window.dispatchEvent(new Event('kinnect-notifications')));
 await expect(page.locator('#auth')).toBeVisible();
 await expect(page.locator('#app')).toBeHidden();
});

test('notification refresh works with the inbox in the top bar',async({page})=>{
 await account(page,'inbox_location');
 const response=page.waitForResponse(r=>r.url().endsWith('/api/notifications'));
 await page.evaluate(()=>window.dispatchEvent(new Event('kinnect-notifications')));await response;
 await expect(page.locator('#app .top-actions [data-tab="inbox"] .nav-count')).toBeAttached();
 await expect(page.locator('#notice')).not.toContainText('Cannot read');
 await expect(page.locator('#auth')).toBeHidden();
});

test('nearby chip refreshes location directly on every deliberate click',async({page})=>{
 await page.addInitScript(()=>{window.geoCalls=0;Object.defineProperty(navigator,'geolocation',{value:{getCurrentPosition(done){window.geoCalls++;done({coords:{latitude:10.8,longitude:106.7}});}}});});
 await account(page,'nearby_chip');expect(await page.evaluate(()=>window.geoCalls)).toBe(0);
 await page.getByRole('button',{name:'Gần đây',exact:true}).click();
 await expect.poll(()=>page.evaluate(()=>window.geoCalls)).toBe(1);await expect(page.getByRole('heading',{name:'Thành viên quanh bạn',exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Gần đây',exact:true}).click();await expect.poll(()=>page.evaluate(()=>window.geoCalls)).toBe(2);
 await expect(page.getByRole('button',{name:'Cập nhật',exact:true})).toHaveCount(0);
});

 test('location permission starts one watcher and hides GPS update row',async({page})=>{
 await page.addInitScript(()=>{
 window.geoWatchCalls=0;window.geoClearCalls=0;
 Object.defineProperty(navigator,'geolocation',{value:{getCurrentPosition(done){done({coords:{latitude:10.8,longitude:106.7}});},watchPosition(done){window.geoWatchCalls++;window.geoCallback=done;return 7;},clearWatch(){window.geoClearCalls++;}}});
 });
 await account(page,'gps_watch');
 await page.getByRole('button',{name:'Gần đây',exact:true}).click();
 await expect.poll(()=>page.evaluate(()=>window.geoWatchCalls)).toBe(1);
 await expect(page.locator('.nearby-consent')).toBeHidden();
 await page.getByRole('button',{name:'Gần đây',exact:true}).click();
 expect(await page.evaluate(()=>window.geoWatchCalls)).toBe(1);
 await expect(page.getByRole('button',{name:'Cập nhật',exact:true})).toHaveCount(0);
 await page.evaluate(()=>{Object.defineProperty(document,'hidden',{configurable:true,value:true});document.dispatchEvent(new Event('visibilitychange'));});
 await expect.poll(()=>page.evaluate(()=>window.geoClearCalls)).toBe(1);
 });

test('optional calling module failure does not prevent login',async({page})=>{
 await page.route('**/calls.js*',route=>route.fulfill({status:404,body:'Not found'}));
 await account(page,'optional_calls');await expect(page.locator('#app')).toBeVisible();await expect(page.locator('#auth')).toBeHidden();
});
