import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
async function member(browser,name,viewport={width:390,height:844}){
 const context=await browser.newContext({viewport,permissions:['camera','microphone']});
 await context.addInitScript(()=>{window.callTracks=[];const original=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);navigator.mediaDevices.getUserMedia=async options=>{const stream=await original(options);window.callTracks.push(...stream.getTracks());return stream;};});
 const r=await context.request.post('/api/register',{data:{username:name+Date.now(),name,password:'abcdef',agree18:true,acceptPrivacyNotice:true}});expect(r.status()).toBe(200);return {context,user:(await r.json()).user};
}
for(const mode of ['video','audio'])test('ending accepted '+mode+' call while TURN config is pending ends both peers',async({browser})=>{
 const a=await member(browser,'callera'+mode),b=await member(browser,'receiverb'+mode);let release;const gate=new Promise(r=>release=r);
 try{for(const u of [a,b])await u.context.route('**/api/call-config',async route=>{await gate;await route.fulfill({json:{iceServers:[]}}).catch(()=>{});});
 const pa=await a.context.newPage(),pb=await b.context.newPage();await pa.goto('/?chat='+b.user.id);await pb.goto('/?chat='+a.user.id);for(const p of [pa,pb])await expect(p.locator('#connection')).toHaveText('Đã kết nối');
 await pa.getByRole('button',{name:mode==='video'?'Gọi video':'Gọi thoại',exact:true}).click();await pb.getByRole('button',{name:'Nhận cuộc gọi',exact:true}).click();await expect(pb.getByRole('button',{name:'Kết thúc',exact:true})).toBeVisible();await pb.getByRole('button',{name:'Kết thúc',exact:true}).click();
 for(const p of [pa,pb]){await expect(p.locator('.video-call')).toHaveCount(0);await expect.poll(()=>p.evaluate(()=>window.callTracks.every(t=>t.readyState==='ended'))).toBe(true);}
 // Server must also release the busy state so a new call can ring.
 await pa.getByRole('button',{name:mode==='video'?'Gọi video':'Gọi thoại',exact:true}).click();await expect(pb.getByRole('button',{name:'Nhận cuộc gọi',exact:true})).toBeVisible();await pb.getByRole('button',{name:'Từ chối',exact:true}).click();await expect(pa.locator('.video-call')).toHaveCount(0);
 }finally{release();await a.context.close();await b.context.close();}
});

test('live directory reports API failure and recovers with retry',async({browser})=>{
 const u=await member(browser,'liveerror');try{let fail=true;await u.context.route('**/api/live/rooms',r=>r.fulfill(fail?{status:503,json:{error:'Unavailable'}}:{json:{rooms:[]}}));const p=await u.context.newPage();await p.goto('/?tab=shorts&feed=live');await expect(p.locator('.live-grid-error')).toContainText('Chưa tải được');await expect(p.locator('.live-grid-empty')).toHaveCount(0);fail=false;await p.getByRole('button',{name:'Thử lại',exact:true}).click();await expect(p.locator('.live-grid-empty')).toContainText('Chưa có ai');await expect(p.locator('.live-grid-error')).toHaveCount(0);}finally{await u.context.close();}
});

for(const viewport of [{width:844,height:390},{width:568,height:320}])test('landscape reel and Studio controls remain reachable '+viewport.width,async({browser})=>{
 const u=await member(browser,'landscape',viewport);try{
 const bytes=await readFile(new URL('../test/fixtures/short.mp4',import.meta.url));expect((await u.context.request.post('/api/shorts',{data:{caption:'Landscape',data:'data:video/mp4;base64,'+bytes.toString('base64')}})).status()).toBe(201);
 const p=await u.context.newPage();await p.goto('/?tab=shorts');await expect(p.locator('.reel-side').first()).toBeVisible();for(const action of await p.locator('.reel-side').first().locator('button,a').all()){await expect(action).toBeInViewport({ratio:1});await action.click({trial:true});}
 await p.goto('/?tab=feed');await p.locator('#create-post').click();await expect(p.locator('.tt-stage')).toBeVisible();const stage=await p.locator('.tt-stage').boundingBox();expect(stage.width).toBeGreaterThan(280);
 for(const selector of ['.tt-x','.tt-sound','.tt-rail button','.tt-modes button','.tt-shutter'])for(const button of await p.locator(selector).all()){await expect(button).toBeInViewport({ratio:1});await button.click({trial:true});}
 await p.locator('.tt-shutter').click();await expect(p.locator('.studio')).toHaveClass(/recording/);await p.waitForTimeout(1200);await p.getByRole('button',{name:'Dừng quay',exact:true}).click();await expect(p.locator('.tt-post')).toBeVisible();await p.locator('.tt-back').click();await p.locator('.tt-x').click();await expect.poll(()=>p.evaluate(()=>window.callTracks.every(t=>t.readyState==='ended'))).toBe(true);
 }finally{await u.context.close();}
});

test('configuration loading is bounded and timeout releases both peers and media',async({browser})=>{
 const a=await member(browser,'deadlinea'),b=await member(browser,'deadlineb');let release;const gate=new Promise(r=>release=r);let requested=0;
 try{for(const u of [a,b])await u.context.route('**/api/call-config',async route=>{requested++;await gate;await route.fulfill({json:{iceServers:[]}}).catch(()=>{});});
 const pa=await a.context.newPage(),pb=await b.context.newPage();await pa.clock.install();await pa.goto('/?chat='+b.user.id);await pb.goto('/?chat='+a.user.id);for(const p of [pa,pb])await expect(p.locator('#connection')).toHaveText('Đã kết nối');await pa.getByRole('button',{name:'Gọi video',exact:true}).click();await pb.getByRole('button',{name:'Nhận cuộc gọi',exact:true}).click();await expect.poll(()=>requested).toBe(2);await pa.clock.fastForward(30001);
 for(const p of [pa,pb]){await expect(p.locator('.video-call')).toHaveCount(0);await expect.poll(()=>p.evaluate(()=>window.callTracks.every(t=>t.readyState==='ended'))).toBe(true);}await expect(pa.locator('#notice')).toContainText('quá thời gian');
 }finally{release();await a.context.close();await b.context.close();}
});
