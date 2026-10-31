import {test,expect} from '@playwright/test';
test('offline page and all UI styles remain available without caching account APIs',async({browser})=>{
 const context=await browser.newContext({serviceWorkers:'allow'});
 try{
  const page=await context.newPage();await page.goto('/');
  await page.evaluate(async()=>{await navigator.serviceWorker.ready;if(!navigator.serviceWorker.controller)await new Promise(resolve=>navigator.serviceWorker.addEventListener('controllerchange',resolve,{once:true}));});
  const assets=['/tokens.css','/polish.css','/desktop.css','/compact.css','/live.css','/studio.css','/social-feed.js','/social-discover.js','/social-profile.js','/social-messenger.js','/camera.js','/calls.js'];
  await expect.poll(()=>page.evaluate(async assets=>{const cache=await caches.open((await caches.keys()).find(name=>name.startsWith('kinnect-static-')));return (await Promise.all(assets.map(path=>cache.match(path)))).every(Boolean);},assets)).toBe(true);
  const requestPaths=await page.evaluate(async()=>{const cache=await caches.open((await caches.keys()).find(name=>name.startsWith('kinnect-static-')));return (await cache.keys()).map(request=>new URL(request.url).pathname);});expect(requestPaths.some(path=>path.startsWith('/api/'))).toBe(false);
  await context.setOffline(true);await page.goto('/?offline-check=1');await expect(page.getByRole('heading',{name:'Kết nối đang tạm nghỉ.'})).toBeVisible();
  const offline=await page.evaluate(async assets=>{const results=await Promise.all(assets.map(async path=>{const r=await fetch(path+'?v=offline-regression');return r.ok&&(await r.text()).length>0;}));let apiFailed=false;try{await fetch('/api/me');}catch{apiFailed=true;}return {allAssets:results.every(Boolean),apiFailed};},assets);
  expect(offline).toEqual({allAssets:true,apiFailed:true});await expect(page.getByRole('link',{name:/Thử kết nối lại/})).toBeVisible();
  await context.setOffline(false);await page.getByRole('link',{name:/Thử kết nối lại/}).click();await expect(page.locator('#auth')).toBeVisible();
 }finally{await context.close();}
});
