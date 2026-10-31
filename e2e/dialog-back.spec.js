import {test,expect} from '@playwright/test';
test('Back dismisses message and group pickers before leaving inbox',async({page})=>{
 await page.request.post('/api/register',{data:{username:'dialogs'+Date.now(),name:'Kiểm tra popup',password:'abcdef',agree18:true,acceptPrivacyNotice:true}});await page.goto('/');await page.getByRole('button',{name:'Tin nhắn',exact:true}).click();const url=page.url();
 for(const name of ['Tin nhắn mới','Tạo nhóm']){await page.getByRole('button',{name,exact:true}).click();await expect(page.getByRole('dialog')).toBeVisible();await page.goBack();await expect(page.getByRole('dialog')).toHaveCount(0);expect(page.url()).toBe(url);await expect(page.locator('.inbox-list')).toBeVisible();}
 await page.getByRole('button',{name:'Tin nhắn mới',exact:true}).click();await page.getByRole('button',{name:'Đóng tin nhắn mới',exact:true}).click();await expect(page.getByRole('dialog')).toHaveCount(0);await expect.poll(()=>page.evaluate(()=>history.state.appDialog||null)).toBe(null);await page.goBack();await expect(page).toHaveURL(/tab=discover/);
});
