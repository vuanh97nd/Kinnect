import {test,expect} from '@playwright/test';
for(const width of [320,390])test('compact discovery badges and menu never cover each other at '+width,async({browser})=>{
 const context=await browser.newContext({viewport:{width,height:844}}),page=await context.newPage();try{
 await context.request.post('/api/register',{data:{username:'badge_'+width+'_'+Date.now(),password:'abcdef',name:'Người kiểm tra',agree18:true}});
 await page.route('**/api/discover?*',r=>r.fulfill({json:{users:[{id:'test-profile',username:'ho_so_kiem_tra',name:'Thành viên mới',interests:[],isActive:true,isNew:true,distanceBand:'100 m',distanceLabel:'100 m',distanceMeters:100,following:false}]}}));
 await page.goto('/');await expect(page.locator('.person-tile')).toBeVisible();
 const tile=page.locator('.person-tile'),badge=await tile.locator('.new-member').boundingBox(),menu=await tile.locator('.more summary').boundingBox(),name=await tile.locator('.tile-name').boundingBox(),distance=await tile.locator('.tile-chip').boundingBox();
 expect(badge.x+badge.width).toBeLessThanOrEqual(menu.x);expect(badge.y+badge.height).toBeLessThanOrEqual(name.y);const photo=await tile.locator('.tile-photo').boundingBox();expect(photo.x+photo.width-distance.x-distance.width).toBeLessThanOrEqual(6);expect(photo.y+photo.height-distance.y-distance.height).toBeLessThanOrEqual(7);if(width>=390)expect(name.y+name.height).toBeLessThanOrEqual(distance.y);
 await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/'+width+'-distance-card.png'});
 await tile.locator('.more summary').click();const dialog=page.getByRole('dialog',{name:'Tùy chọn khác'});await expect(dialog.getByRole('button',{name:'Chặn',exact:true})).toBeVisible();await expect(dialog.getByRole('button',{name:'Báo cáo',exact:true})).toBeVisible();const rect=await dialog.boundingBox();expect(rect.x).toBeGreaterThanOrEqual(0);expect(rect.x+rect.width).toBeLessThanOrEqual(width);expect(await dialog.evaluate(el=>el.scrollWidth-el.clientWidth)).toBe(0);
 await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/'+width+'-profile-actions.png'});
 }finally{await context.close();}
});
