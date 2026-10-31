import {test,expect} from '@playwright/test';
test('desktop message icon opens the conversation workspace in the center column',async({page})=>{
 await page.setViewportSize({width:1280,height:900});
 const registered=await page.request.post('/api/register',{data:{username:'messagehub'+Date.now(),name:'Menu giữa',password:'abcdef',agree18:true,acceptPrivacyNotice:true}});
 expect(registered.ok()).toBeTruthy();await page.goto('/');
 await page.getByRole('button',{name:'Bạn bè',exact:true}).click();await expect(page.locator('.view-friends')).toBeVisible();
 const friends=await page.locator('#social-panel').boundingBox();
 await page.locator('#app .top-actions [data-tab=inbox]').click();await expect(page.locator('.view-inbox')).toBeVisible();
 await expect(page.locator('.messenger-sidebar')).toBeVisible();await expect(page.getByRole('button',{name:'Tin nhắn mới',exact:true})).toBeVisible();
 await expect(page.getByRole('button',{name:'Tạo nhóm',exact:true})).toBeVisible();await expect(page.locator('.messenger-welcome')).toBeVisible();
 await expect(page.locator('#app .top-actions [data-tab=friends]')).toBeVisible();await expect(page.locator('#me-btn')).toBeVisible();
 const center=await page.locator('#social-panel').boundingBox();expect(Math.abs(center.x-friends.x)).toBeLessThan(2);
 await page.locator('#notification-bell').click();await expect(page.locator('#notification-center')).toBeVisible();await expect(page.locator('.view-inbox')).toBeVisible();
 await page.getByRole('button',{name:'Đóng thông báo',exact:true}).click();await page.locator('#me-btn').click();await expect(page.locator('#me-panel')).toBeVisible();
 await page.getByRole('menuitem',{name:'Cài đặt tài khoản',exact:true}).click();await expect(page.locator('.view-settings')).toBeVisible();
});
