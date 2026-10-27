import {test,expect} from '@playwright/test';import {createApp} from '../server.js';
// Điện thoại 16:9 (360×640): popup, thông báo, chữ dài và lỗi camera.
test('v2 mobile 360x640 popups, toasts, long text and camera errors',async({browser})=>{
  const app=createApp({authLimit:200});await new Promise(r=>app.server.listen(0,'127.0.0.1',r));
  const baseURL='http://127.0.0.1:'+app.server.address().port;
  const ctx=await browser.newContext({baseURL,viewport:{width:360,height:640}}),other=await browser.newContext({baseURL});
  try{
    const reg=async(c,u,n)=>(await (await c.request.post('/api/register',{data:{username:u,password:'abcdef',name:n,agree18:true}})).json()).user;
    const me=await reg(ctx,'mobile_'+Date.now(),'Ngọc Linh Trần Thị Phương'),friend=await reg(other,'friend_'+Date.now(),'Minh Anh');
    const long='Linkdaithatdaikhongcokhoangtrang'+'x'.repeat(120);
    await other.request.post('/api/posts',{data:{body:long}});
    const p=await ctx.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
    await p.goto('/?s=feed');const post=p.locator('.post').filter({hasText:'Linkdaithatdai'});await expect(post).toBeVisible();
    // Chữ dài tự xuống dòng, không tràn khung.
    expect(await post.locator('.post-copy').evaluate(e=>e.scrollWidth<=e.clientWidth+1)).toBeTruthy();
    expect(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBeTruthy();
    // Menu ba chấm đóng khi chạm ra ngoài.
    await post.getByRole('button',{name:'Tuỳ chọn bài viết',exact:true}).click();await expect(p.locator('.v2-context-menu')).toBeVisible();
    await post.locator('.stats').click();await expect(p.locator('.v2-context-menu')).toHaveCount(0);
    // Bảng chia sẻ: nằm gọn màn hình, Back và chạm nền đều đóng, không đổi màn.
    await post.getByRole('button',{name:'Chia sẻ',exact:true}).click();const sheet=p.locator('.composer-sheet section');await expect(sheet).toBeVisible();
    await expect.poll(()=>sheet.evaluate(e=>Math.round(e.getBoundingClientRect().bottom))).toBeLessThanOrEqual(640);
    await p.goBack();await expect(p.locator('.composer-sheet')).toHaveCount(0);await expect(p.locator('#kn .app')).toHaveAttribute('data-screen','feed');
    await post.getByRole('button',{name:'Chia sẻ',exact:true}).click();await expect(sheet).toBeVisible();await p.mouse.click(180,40);await expect(p.locator('.composer-sheet')).toHaveCount(0);
    // Toast căn giữa màn hình.
    await post.getByRole('button',{name:'Chia sẻ',exact:true}).click();await p.locator('.composer-sheet').getByRole('button',{name:/Sao chép/}).click();
    const toast=p.locator('#kn .notice');await expect(toast).toBeVisible();
    const box=await toast.boundingBox();expect(Math.abs(box.x+box.width/2-180)).toBeLessThan(3);expect(box.x).toBeGreaterThanOrEqual(15);
    await p.keyboard.press('Escape');
    // Hộp xác nhận đăng xuất có nền tối và chạm nền thì đóng.
    await p.goto('/?s=account');await p.getByRole('button',{name:'Đăng xuất',exact:true}).first().click();
    await expect(p.locator('.kn-backdrop')).toBeVisible();await p.mouse.click(180,60);await expect(p.locator('.logout-confirm')).toHaveCount(0);
    // Tên dài trên hồ sơ không đè ảnh bìa.
    await p.goto('/?s=profile&user='+me.id);const cover=await p.locator('.profile-cover').boundingBox(),name=await p.locator('.profile-identity h1').boundingBox();
    expect(name.y).toBeGreaterThanOrEqual(cover.y+cover.height-1);
    // Thông báo nổi khi có tin nhắn mới.
    await p.goto('/?s=feed');await p.waitForTimeout(1500);
    await other.request.post('/api/users/'+me.id+'/messages',{data:{body:'Xin chào'}});
    await expect(p.locator('#kn .notice')).toContainText('Minh Anh vừa nhắn tin cho bạn',{timeout:40000});
    // Hộp xác nhận Kinnect thay cho hộp mặc định của trình duyệt.
    await ctx.request.post('/api/users/'+friend.id+'/friend-request',{data:{}});await other.request.post('/api/users/'+me.id+'/friend-request',{data:{}});
    let nativeDialog=false;p.on('dialog',d=>{nativeDialog=true;d.dismiss();});
    await p.goto('/?s=profile&user='+friend.id);await p.getByRole('button',{name:'Tuỳ chọn hồ sơ',exact:true}).click();
    const unfriend=p.getByRole('button',{name:'Huỷ kết bạn',exact:true});
    if(await unfriend.count()){await unfriend.click();const dlg=p.getByRole('alertdialog');await expect(dlg).toContainText('Huỷ kết bạn');await dlg.getByRole('button',{name:'Huỷ',exact:true}).click();await expect(dlg).toHaveCount(0);}
    expect(nativeDialog).toBe(false);
    // Camera bị từ chối quyền: thông báo tiếng Việt và nút Thử lại.
    const denied=await ctx.newPage();await denied.addInitScript(()=>{navigator.mediaDevices.getUserMedia=()=>Promise.reject(Object.assign(new Error('Permission denied'),{name:'NotAllowedError'}));});
    await denied.goto('/?s=studio');const err=denied.locator('.v2-camera-error');await expect(err).toContainText('chưa được phép dùng camera');
    await expect(err.getByRole('button',{name:'Thử lại',exact:true})).toBeVisible();await expect(denied.locator('body')).not.toContainText('Permission denied');
    expect(errors).toEqual([]);
  }finally{await ctx.close();await other.close();await new Promise(r=>app.server.close(r));}
});
