import {test,expect} from '@playwright/test';
test('live peers receive server TURN configuration and exchange video frames',async({browser})=>{
 const host=await browser.newContext({permissions:['camera','microphone']}),viewer=await browser.newContext();
 try{
  for(const [context,name] of [[host,'relayhost'],[viewer,'relayviewer']]){
   const registration=await context.request.post('/api/register',{data:{username:name+Date.now(),password:'abcdef',name,agree18:true}});expect(registration.ok()).toBeTruthy();
   await context.route('**/api/call-config',route=>route.fulfill({json:{iceServers:[{urls:'turn:127.0.0.1:9',username:'e2e',credential:'e2e'}]}}));
   await context.addInitScript(()=>{const Original=window.RTCPeerConnection;window.testLivePeers=[];window.RTCPeerConnection=class extends Original{constructor(config){super(config);window.testLivePeers.push(this);}};});
  }
  const h=await host.newPage(),v=await viewer.newPage();await h.goto('/?view=live');await expect(h.locator('#app')).toBeVisible();await expect(h.locator('#connection')).toHaveText('Đã kết nối');
  await h.locator('#create').evaluate(form=>{form.querySelector('#title').value='TURN integration';form.requestSubmit();});await expect(h.locator('#live')).toBeVisible();
  await v.goto('/?tab=shorts&feed=live');await v.locator('.live-card').filter({hasText:'TURN integration'}).click();await expect(v.locator('#live')).toBeVisible();
  for(const page of [h,v])await expect.poll(()=>page.evaluate(()=>window.testLivePeers.map(peer=>peer.getConfiguration().iceServers).flat().some(server=>(Array.isArray(server.urls)?server.urls:[server.urls]).includes('turn:127.0.0.1:9')))).toBe(true);
  await expect.poll(()=>v.locator('#video').evaluate(video=>video.videoWidth>0&&video.readyState>=2),{timeout:15000}).toBe(true);
  await h.locator('#leave').click();await expect(v.locator('#live')).toBeHidden();
 }finally{await host.close();await viewer.close();}
});
