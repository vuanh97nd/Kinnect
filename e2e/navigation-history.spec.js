import {test,expect} from '@playwright/test';
test('back and forward restore previous app screens',async({page})=>{
 await page.request.post('/api/register',{data:{username:'back'+Date.now(),name:'Kiểm tra quay lại',password:'abcdef',agree18:true}});await page.goto('/');await expect(page.locator('#app')).toBeVisible();await page.getByRole('button',{name:'Bảng tin',exact:true}).click();await expect(page).toHaveURL(/tab=feed/);await page.getByRole('button',{name:'Bạn bè',exact:true}).click();await expect(page).toHaveURL(/tab=friends/);await page.goBack();await expect(page).toHaveURL(/tab=feed/);await expect(page.locator('#app')).toBeVisible();await page.goForward();await expect(page).toHaveURL(/tab=friends/);await page.reload();await expect(page.locator('.friends-tabs')).toBeVisible();await page.goBack();await expect(page).toHaveURL(/tab=feed/);
});

test('friends and inbox close with browser and screen Back',async({browser})=>{
 const a=await browser.newContext(),b=await browser.newContext();try{
 await a.request.post('/api/register',{data:{username:'nav_a'+Date.now(),name:'Điều hướng A',password:'abcdef',agree18:true}});const r=await b.request.post('/api/register',{data:{username:'nav_b'+Date.now(),name:'Điều hướng B',password:'abcdef',agree18:true}});const user=(await r.json()).user;
 const p=await a.newPage();await p.goto('/');await p.getByRole('button',{name:'Bảng tin',exact:true}).click();
 for(const name of ['Bạn bè','Tin nhắn']){
 await p.getByRole('button',{name,exact:true}).click();await p.locator('.screen-back').click();await expect(p).toHaveURL(/tab=feed/);
 await p.getByRole('button',{name,exact:true}).click();await p.goBack();await expect(p).toHaveURL(/tab=feed/);
 }
 await b.request.post('/api/users/'+(await (await a.request.get('/api/me')).json()).user.id+'/messages',{data:{body:'Kiểm tra điều hướng chat'}});
 await p.getByRole('button',{name:'Tin nhắn',exact:true}).click();await p.locator('.inbox-row').filter({hasText:user.name}).click();await expect(p.locator('.chat-identity b')).toHaveText(user.name);await p.getByRole('button',{name:'Quay lại hộp thư'}).click();await expect(p.locator('.inbox-list')).toBeVisible();await p.locator('.screen-back').click();await expect(p).toHaveURL(/tab=feed/);
 }finally{await a.close();await b.close();}
});
