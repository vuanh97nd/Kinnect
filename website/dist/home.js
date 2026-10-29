document.querySelectorAll('.wall-like').forEach(b=>b.onclick=()=>{const liked=b.getAttribute('aria-pressed')==='true';b.setAttribute('aria-pressed',!liked);b.textContent=liked?'♡':'♥';});
const iosDialog=document.querySelector('#ios-dialog');document.querySelector('#ios-open').onclick=()=>iosDialog.showModal();document.querySelector('#ios-close').onclick=()=>iosDialog.close();iosDialog.addEventListener('click',e=>{if(e.target===iosDialog){const r=iosDialog.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)iosDialog.close();}});

(()=>{
 const appOrigin='https://app.kinnect.io.vn',link=document.querySelector('[data-session-link]'),frame=document.createElement('iframe');
 frame.hidden=true;frame.tabIndex=-1;frame.title='Kiểm tra phiên Kinnect';frame.src=appOrigin+'/?website-session=1';
 const reveal=()=>document.getElementById('kinnect-boot')?.remove();let timeout=setTimeout(reveal,3500);
 const check=()=>frame.contentWindow?.postMessage({type:'kinnect:check-session'},appOrigin);
 window.addEventListener('message',event=>{
  if(event.origin!==appOrigin||event.source!==frame.contentWindow||event.data?.type!=='kinnect:session-status'||typeof event.data.authenticated!=='boolean')return;
  clearTimeout(timeout);
  if(link){link.textContent=event.data.authenticated?'Mở Kinnect':'Đăng nhập';link.href=appOrigin+(event.data.authenticated?'/':'/?s=login');}
  if(event.data.authenticated)location.replace(appOrigin+'/?s=feed');else reveal();
 });
 frame.addEventListener('load',check);window.addEventListener('focus',check);window.addEventListener('pageshow',check);document.addEventListener('visibilitychange',()=>{if(!document.hidden)check();});frame.onerror=reveal;document.body.append(frame);
})();
