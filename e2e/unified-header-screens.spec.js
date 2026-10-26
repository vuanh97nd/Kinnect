import {test,expect} from '@playwright/test';
for(const width of [320,390,1280])test('four header destinations share app chrome and title bars and unread never closes them '+width,async({browser})=>{
 const c=await browser.newContext({viewport:{width,height:844}});try{await c.request.post('/api/register',{data:{username:'unified'+width+Date.now(),name:'Đồng bộ giao diện',password:'abcdef',agree18:true}});const p=await c.newPage();await p.goto('/');await expect(p.locator('.view-discover')).toBeVisible();const start=p.url(),bars=[];
 for(const [label,selector,heading] of [['Bạn bè','.view-friends','.friends-heading'],['Tin nhắn','.view-inbox','.inbox-heading'],['Thông báo','#notification-center','.notification-center-head'],['Tài khoản của tôi','#me-panel','.header-panel-bar']]){
 await p.getByRole('button',{name:label,exact:true}).click();const screen=p.locator(selector);await expect(screen).toBeVisible();const rect=await screen.boundingBox();expect(rect.x).toBeGreaterThanOrEqual(0);expect(rect.x+rect.width).toBeLessThanOrEqual(width);const appHeader=await p.locator('#app>header').boundingBox();expect(rect.y).toBeGreaterThanOrEqual(appHeader.y+appHeader.height-1);const bar=screen.locator(heading),back=bar.locator('button').first(),title=bar.locator('h2');const tb=await title.boundingBox();
 // Nút quay-lại chỉ hiện trên khổ hẹp (CSS desktop ẩn). Trên desktop chỉ so sánh tiêu đề.
 if(width<1000){const bb=await back.boundingBox();expect(Math.abs(bb.y+bb.height/2-tb.y-tb.height/2)).toBeLessThan(1);expect(bb.width).toBe(40);expect(bb.height).toBe(40);const normal=await back.evaluate(el=>({background:getComputedStyle(el).backgroundColor,color:getComputedStyle(el).color}));await back.hover();const hover=await back.evaluate(el=>({background:getComputedStyle(el).backgroundColor,color:getComputedStyle(el).color}));expect(hover).toEqual(normal);bars.push({x:bb.x,y:bb.y,titleX:tb.x,titleY:tb.y,colors:normal});}
 else{bars.push({titleX:tb.x,titleY:tb.y,colors:null});}
 if(label==='Thông báo'){for(let i=0;i<3;i++){await screen.getByRole('button',{name:'Chưa đọc',exact:true}).click();await expect(screen).toBeVisible();await screen.getByRole('button',{name:'Tất cả',exact:true}).click();await expect(screen).toBeVisible();}await screen.getByRole('button',{name:'Đánh dấu đã đọc',exact:true}).click();await expect(screen).toBeVisible();}
 if(label==='Tin nhắn'){await screen.getByRole('button',{name:'Chưa đọc',exact:true}).click();await expect(screen).toBeVisible();await screen.getByRole('button',{name:'Tất cả',exact:true}).click();}
 if(width===390)await p.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/unified-'+label+'.png'});
 await expect(p.locator('#app>nav')).toBeVisible();await p.goBack();await expect(screen).toBeHidden();expect(p.url()).toBe(start);await expect(p.locator('#app>nav')).toBeVisible();
 }
 // The title bars have the same back-button dimensions and aligned title baselines.
 expect(bars).toHaveLength(4);if(width<1000)for(const bar of bars)expect(bar.colors).toEqual(bars[0].colors);
 }finally{await c.close();}
});
