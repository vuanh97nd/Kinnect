import {test,expect} from '@playwright/test';
test('trusted account logs back in with one profile click after logout',async({page})=>{
 await page.goto('/');await page.getByRole('button',{name:'Bỏ qua',exact:true}).click();await page.getByRole('button',{name:'Tạo tài khoản',exact:true}).click();
 await page.locator('#username').fill('remember_browser');await page.locator('#password').fill('abcdef');await page.locator('#display-name').fill('Hồ sơ đã ghi nhớ');await page.locator('#agree').check();await page.getByLabel('Ghi nhớ đăng nhập trên thiết bị này').check();await page.locator('#auth-submit').click();await expect(page.locator('#app')).toBeVisible();
 await page.getByRole('button',{name:'Tài khoản',exact:true}).click();await page.getByRole('menuitem',{name:'Đăng xuất',exact:true}).click();
 await expect(page.getByRole('button',{name:'Đăng nhập với Hồ sơ đã ghi nhớ',exact:true})).toBeVisible();
 await expect(page.locator('.onboarding')).toHaveCount(0);
 await page.getByRole('button',{name:'Đăng nhập với Hồ sơ đã ghi nhớ',exact:true}).click();await expect(page.locator('#app')).toBeVisible();await expect(page.locator('#auth')).toBeHidden();
 await page.getByRole('button',{name:'Hồ sơ',exact:true}).click();await page.getByRole('button',{name:'Sửa hồ sơ',exact:true}).click();
 await expect(page.getByRole('group',{name:'Thông tin cơ bản'})).toBeVisible();await expect(page.getByRole('group',{name:'Quyền riêng tư'})).toBeVisible();
 await page.getByLabel('Giới thiệu',{exact:true}).fill('Một hồ sơ gọn gàng, có cá tính.');await page.getByRole('button',{name:'Xong',exact:true}).click();await expect(page.locator('.profile-bio')).toHaveText('Một hồ sơ gọn gàng, có cá tính.');
});
