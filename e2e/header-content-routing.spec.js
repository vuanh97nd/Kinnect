import {test,expect} from '@playwright/test';
test('desktop header icons replace only the center content',async({page})=>{
 await page.setViewportSize({width:1440,height:900});await page.request.post('/api/register',{data:{username:'centerroute'+Date.now(),name:'Điều hướng vùng giữa',password:'abcdef',agree18:true,acceptPrivacyNotice:true}});await page.goto('/');await expect(page.locator('#app')).toBeVisible();
 const header=page.locator('#app>header'),left=page.locator('#app>nav'),right=page.locator('#rail');
 const box=async locator=>{const r=await locator.boundingBox();return r&&{x:r.x,y:r.y,width:r.width,height:r.height};};
 const outerBefore=[await box(header),await box(left)];
 await page.locator('#app .top-actions [data-tab=friends]').click();await expect(page.locator('.view-friends')).toBeVisible();
 await page.locator('#app .top-actions [data-tab=inbox]').click();await expect(page.locator('.view-inbox')).toBeVisible();
 await page.locator('#notification-bell').click();await expect(page.locator('#notification-center')).toBeVisible();await expect(page.locator('.view-inbox')).toBeVisible();
 await page.locator('#me-btn').click();await expect(page.locator('#me-panel')).toBeVisible();await expect(page.locator('#notification-center')).toBeHidden();await expect(page.locator('.view-inbox')).toBeVisible();
 const outerAfter=[await box(header),await box(left)];expect(outerAfter).toEqual(outerBefore);await expect(right).toBeHidden();
});
