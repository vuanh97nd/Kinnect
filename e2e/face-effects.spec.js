import {test,expect} from '@playwright/test';import {readFile} from 'node:fs/promises';
test('real face landmarks follow movement and mirroring with native FaceDetector absent',async({page})=>{
 test.setTimeout(60000);await page.goto('/');
 const bytes=(await readFile(new URL('../test/fixtures/face-portrait.jpg',import.meta.url))).toString('base64');
 await page.evaluate(async bytes=>{
  delete window.FaceDetector;const image=new Image();image.src='data:image/jpeg;base64,'+bytes;await image.decode();
  const source=document.createElement('canvas');source.width=640;source.height=640;const ctx=source.getContext('2d');window.faceOffset=0;
  const draw=()=>{ctx.fillStyle='black';ctx.fillRect(0,0,640,640);ctx.drawImage(image,window.faceOffset,0,480,600);};draw();window.faceTimer=setInterval(draw,50);
  const raw=source.captureStream(20);const {createEffects}=await import('/camera.js');window.testFx=createEffects(raw,{width:640,height:640});window.testFx.set({mirror:false,sticker:'glasses',soft:true});window.faceStatus='';window.testFx.onStatus(text=>{window.faceStatus=text;});document.body.append(window.testFx.canvas);
 },bytes);
 await expect.poll(()=>page.evaluate(()=>window.testFx.faceBox?.width||0),{timeout:40000}).toBeGreaterThan(40);
 const before=await page.evaluate(()=>window.testFx.faceBox?.x ?? -1);
 await page.evaluate(()=>{window.faceOffset=100;});
 await expect.poll(()=>page.evaluate(()=>window.testFx.faceBox?.x ?? -1),{timeout:10000}).toBeGreaterThan(before+60);
 const shifted=await page.evaluate(()=>window.testFx.faceBox);
 await page.evaluate(()=>window.testFx.set({mirror:true}));
 await expect.poll(()=>page.evaluate(()=>window.testFx.faceBox?.x ?? 100000),{timeout:10000}).toBeLessThan(640-shifted.x-shifted.width+20);
 expect(await page.evaluate(()=>window.faceStatus)).toBe('Đã nhận diện khuôn mặt');
 await page.evaluate(()=>{window.testFx.stop();clearInterval(window.faceTimer);});
});
