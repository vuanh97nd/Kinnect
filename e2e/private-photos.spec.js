import {test,expect} from '@playwright/test';
test('private album upload request approval and revoke on mobile',async({browser})=>{
 const owner=await browser.newContext({viewport:{width:320,height:780}}),viewer=await browser.newContext({viewport:{width:390,height:844}});
 try{
 const create=async(context,name)=>{const r=await context.request.post('/api/register',{data:{username:name+Date.now(),name,password:'abcdef',agree18:true}});expect(r.ok()).toBeTruthy();return (await r.json()).user;};
 const a=await create(owner,'AlbumOwner'),b=await create(viewer,'AlbumViewer');await viewer.request.post('/api/users/'+a.id+'/follow',{data:{}});
 const p=await owner.newPage(),q=await viewer.newPage();await p.goto('/');await p.locator('[data-tab=profile]').first().click();await p.getByRole('tab',{name:'Ảnh riêng tư',exact:true}).click();const album=p.getByRole('region',{name:'Ảnh riêng tư',exact:true});
 await album.getByLabel('Thêm ảnh riêng tư').setInputFiles('public/apple-touch-icon.png');await expect(album.locator('.private-photo-item')).toHaveCount(1);
 await q.goto('/');await q.locator('[data-tab=profile]').first().click();await q.getByRole('button',{name:'đang theo dõi (1)',exact:true}).click();await q.locator('.connection-row').click();await expect(q.locator('.profile-id h2')).toHaveText(a.name);
 await q.getByRole('tab',{name:'Ảnh riêng tư',exact:true}).click();const locked=q.getByRole('region',{name:'Ảnh riêng tư',exact:true});await expect(locked.locator('.private-photo-locked')).toHaveCount(1);await expect(locked.locator('img')).toHaveCount(0);await locked.getByRole('button',{name:'Yêu cầu xem ảnh riêng tư',exact:true}).click();await expect(locked.getByRole('button',{name:'Hủy yêu cầu'})).toBeVisible();
 await album.getByRole('button',{name:'Làm mới'}).click();await album.locator('.private-access-panel>summary').click();await expect(album.getByRole('button',{name:'Đồng ý',exact:true})).toBeVisible();await album.getByRole('button',{name:'Đồng ý',exact:true}).click();await expect(album.getByRole('button',{name:'Thu hồi',exact:true})).toBeVisible();
 await locked.getByRole('button',{name:'Làm mới'}).click();await expect(locked.locator('.private-photo-item')).toHaveCount(1);await locked.getByRole('button',{name:'Xem ảnh riêng tư',exact:true}).click();await expect(q.getByRole('dialog',{name:'Xem ảnh riêng tư',exact:true})).toBeVisible();
 await album.getByRole('button',{name:'Thu hồi',exact:true}).click();await expect(q.getByRole('dialog',{name:'Xem ảnh riêng tư',exact:true})).toHaveCount(0);await locked.getByRole('button',{name:'Làm mới'}).click();await expect(locked.locator('.private-photo-locked')).toHaveCount(1);await expect(locked.locator('img')).toHaveCount(0);
 for(const page of [p,q])expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBeTruthy();
 }finally{await owner.close();await viewer.close();}
});
