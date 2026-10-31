import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
function tone(){const rate=8000,seconds=4,size=rate*seconds*2,b=Buffer.alloc(44+size);b.write('RIFF');b.writeUInt32LE(36+size,4);b.write('WAVEfmt ',8);b.writeUInt32LE(16,16);b.writeUInt16LE(1,20);b.writeUInt16LE(1,22);b.writeUInt32LE(rate,24);b.writeUInt32LE(rate*2,28);b.writeUInt16LE(2,32);b.writeUInt16LE(16,34);b.write('data',36);b.writeUInt32LE(size,40);for(let i=0;i<rate*seconds;i++)b.writeInt16LE(Math.round(Math.sin(i*2*Math.PI*440/rate)*4000),44+i*2);return b;}
test('photo with music records and publishes as a story without requesting camera',async({page})=>{
 const r=await page.request.post('/api/register',{data:{username:'music_'+Date.now(),password:'abcdef',name:'Tin âm nhạc',agree18:true,acceptPrivacyNotice:true}});expect(r.status()).toBe(200);
 await page.addInitScript(()=>{navigator.mediaDevices.getUserMedia=()=>{throw Error('Photo stories must not request the camera');};});
 await page.goto('/');await expect(page.locator('#app')).toBeVisible();await page.locator('[data-tab="feed"]').first().click();
 await page.getByRole('button',{name:'+ Tạo tin',exact:true}).click();
 await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/390-create-story.png'});
 await page.getByLabel('Chọn ảnh tạo tin').setInputFiles({name:'photo.png',mimeType:'image/png',buffer:await readFile(new URL('../public/apple-touch-icon.png',import.meta.url))});
 await expect(page.getByRole('dialog',{name:'Tạo tin',exact:true})).toBeVisible();
 await page.getByRole('button',{name:'Nhạc nền',exact:true}).click();
 await page.getByRole('button',{name:'Nhạc của bạn',exact:true}).click();await page.locator('.mp-upload input').setInputFiles({name:'Test.wav',mimeType:'audio/wav',buffer:tone()});await page.getByRole('button',{name:'Dùng bài này',exact:true}).click();
 await page.getByRole('button',{name:'Tạo tin ảnh',exact:true}).click();
 await expect(page.locator('.studio')).toHaveClass(/recording/);
 await page.waitForTimeout(1800);await page.getByRole('button',{name:'Dừng quay',exact:true}).click();
 await expect(page.getByRole('button',{name:'Đăng tin',exact:true})).toBeVisible();
 await expect.poll(()=>page.locator('.tt-preview').evaluate(v=>v.captureStream().getAudioTracks().length)).toBe(1);
 await page.screenshot({path:'C:/Users/ANH/Documents/Codex/2026-10-24/ki-m-tra-claude-ang-l/outputs/audit/390-photo-music-review.png'});
 const response=page.waitForResponse(r=>r.url().endsWith('/api/stories')&&r.request().method()==='POST');
 await page.getByRole('button',{name:'Đăng tin',exact:true}).click();const posted=await response;expect(posted.status(),await posted.text()).toBe(201);
 await expect(page.getByRole('button',{name:'Xem tin của Tin âm nhạc',exact:true})).toBeVisible();
});
