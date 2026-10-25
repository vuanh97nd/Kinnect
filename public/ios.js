const isStandalone = () => window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone;
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const dialog = document.createElement('dialog');
dialog.className = 'ios-help';
dialog.setAttribute('aria-labelledby', 'ios-install-title');
dialog.innerHTML = "<button class=\"ios-help-close\" aria-label=\"Đóng hướng dẫn\">×</button><p class=\"eyebrow\">KINNECT TRÊN iPHONE &amp; iPAD</p><h2 id=\"ios-install-title\">Cài Kinnect trên iPhone</h2><section class=\"ios-profile-install\" aria-labelledby=\"ios-profile-heading\"><h3 id=\"ios-profile-heading\">Cài biểu tượng Kinnect có logo</h3><p>Đang dùng máy tính? Dùng camera iPhone quét mã QR bên dưới. Đang dùng iPhone? Mở bằng Safari và bấm Tải hồ sơ Kinnect.</p><img class=\"ios-profile-qr\" src=\"/kinnect-ios-install-qr.png\" width=\"410\" height=\"410\" alt=\"Mã QR tải hồ sơ biểu tượng Kinnect trên iPhone\"><a class=\"ios-profile-download\" href=\"/Kinnect.mobileconfig\">Tải hồ sơ Kinnect</a><ol><li>Trong Safari trên iPhone, chọn <b>Cho phép</b> tải hồ sơ.</li><li>Mở <b>Cài đặt → Hồ sơ đã tải về → Cài đặt</b>. Nếu chưa thấy, vào <b>Cài đặt chung → VPN &amp; Quản lý thiết bị → Kinnect</b>.</li><li>Xác nhận cài đặt rồi trở về màn hình chính.</li></ol><p class=\"ios-profile-note\">Hồ sơ chỉ chứa một Web Clip Kinnect với logo nhúng sẵn. iOS sẽ hiển thị cảnh báo hồ sơ chưa ký. Đây là cách cài thay thế khi Safari hiện chữ K thường.</p></section><details class=\"ios-icon-help\"><summary>Thêm trực tiếp từ Safari</summary><p>Mở app.kinnect.io.vn bằng Safari trên iPhone, chọn <b>Chia sẻ → Thêm vào màn hình chính</b>. Bật <b>Mở dưới dạng ứng dụng web</b> nếu có, rồi chọn Thêm. Nếu hình xem trước chỉ hiện chữ K thường, có thể dùng cách cài hồ sơ có logo phía trên.</p></details>";
dialog.insertAdjacentHTML('beforeend', '<details class="ios-icon-help"><summary>Nếu biểu tượng chỉ hiện chữ K thường</summary><p>Biểu tượng tự động có thể chưa được Safari chọn đúng trên máy này. Có thể dùng Phím tắt để tự chọn logo:</p><ol><li>Mở <a href="/kinnect-ios-180-v7.png" target="_blank" rel="noopener">logo Kinnect</a>, nhấn giữ ảnh và chọn Lưu vào Ảnh.</li><li>Mở ứng dụng Phím tắt, tạo phím tắt với tác vụ <b>Mở URL</b> và địa chỉ <b>https://app.kinnect.io.vn</b>.</li><li>Chọn <b>Thêm vào màn hình chính</b>, chạm biểu tượng → <b>Chọn ảnh</b>, chọn logo vừa lưu, đặt tên Kinnect rồi bấm Thêm.</li></ol><p>Cách này tạo lối tắt mở Kinnect trong Safari. Đây là cách tạm thời, không sửa bộ chọn icon tự động của Safari.</p></details>');

document.body.append(dialog);
window.addEventListener("kinnect-install-ios",()=>{if(!dialog.open)dialog.showModal();});
dialog.querySelector('button').onclick = () => dialog.close();
dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
const help = document.createElement('button');
help.type = 'button'; help.className = 'ios-help-trigger'; help.textContent = 'Cài Kinnect cho iOS'; help.onclick = () => dialog.showModal();
document.querySelector('#auth .auth-panel')?.append(help); help.hidden = /Android/i.test(navigator.userAgent);
if (isIOS && !isStandalone()) {
  const banner = document.createElement('aside'); banner.className = 'ios-install-banner';
  const text = document.createElement('span'); text.textContent = 'Thêm Kinnect vào màn hình chính';
  const install = document.createElement('button'); install.textContent = 'Cách thêm'; install.onclick = () => dialog.showModal();
  const close = document.createElement('button'); close.className = 'dismiss-install'; close.textContent = '×'; close.setAttribute('aria-label','Ẩn gợi ý cài đặt'); close.onclick = () => banner.remove();
  banner.append(text,install,close);document.body.prepend(banner);
}
const iconPaths = {admin:'M12 3l8 3v6c0 5-8 9-8 9s-8-4-8-9V6z M9 12l2 2 4-4',feed:'M4 4h16v16H4z M8 9h8 M8 13h8 M8 17h5',discover:'M12 3l3 6 6 3-6 3-3 6-3-6-6-3 6-3z',inbox:'M4 4h16v12H9l-5 4z M8 9h8',live:'M3 6h12v12H3z M15 10l6-4v12l-6-4',notifications:'M6 16V10a6 6 0 0112 0v6l2 2H4z M10 21h4',profile:'M16 7a4 4 0 11-8 0 4 4 0 018 0z M4 21a8 8 0 0116 0',shorts:'M7 3h10a2 2 0 012 2v14a2 2 0 01-2 2H7a2 2 0 01-2-2V5a2 2 0 012-2z M10 9l5 3-5 3z'};
for(const button of document.querySelectorAll('#app [data-tab]')) {
  const addIcon = () => { const existing=button.querySelector('svg');if(existing){existing.classList.add('tab-icon');return;}if(!iconPaths[button.dataset.tab])return; const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.classList.add('tab-icon');svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('aria-hidden','true');svg.innerHTML='<path d="'+iconPaths[button.dataset.tab]+'" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>';button.prepend(svg); };
  addIcon();new MutationObserver(addIcon).observe(button,{childList:true});
}
const offline = document.createElement('div'); offline.className='offline-strip';offline.setAttribute('role','status');offline.textContent='Bạn đang ngoại tuyến. Kết nối lại Internet để tiếp tục dùng Kinnect.';document.body.append(offline);
function network(){offline.hidden=navigator.onLine;}
window.addEventListener('online',network);window.addEventListener('offline',network);network();
if('serviceWorker' in navigator && window.isSecureContext) navigator.serviceWorker.register('/sw.js').catch(error=>console.info('Kinnect web app:',error.message));

const navigation=document.querySelector('#app>nav');
const updateTabs=()=>{navigation.style.setProperty('--tab-count',[...navigation.querySelectorAll('button')].filter(button=>!button.hidden&&getComputedStyle(button).display!=='none').length);};
window.addEventListener('resize',updateTabs);window.addEventListener('kinnect-logged-in',updateTabs);
new MutationObserver(updateTabs).observe(navigation,{subtree:true,attributes:true,attributeFilter:['hidden']});updateTabs();

const APK_URL='https://github.com/vuanh97nd/Kinnect/releases';
const ua=navigator.userAgent;
const isAndroid=/Android/i.test(ua);
const inAndroidApp=isAndroid&&(/; wv\)/.test(ua)||new URL(location.href).searchParams.get('view')==='live');
const isDesktop=!isIOS&&!isAndroid&&!window.matchMedia('(pointer:coarse)').matches;
document.documentElement.dataset.platform=isIOS?'ios':isAndroid?'android':isDesktop?'desktop':'other';
let androidDismissed=false;try{androidDismissed=localStorage.getItem('kinnect-android-banner')==='off';}catch{}
if(isAndroid&&!inAndroidApp&&!isStandalone()&&!androidDismissed){
  const banner=document.createElement('aside');banner.className='ios-install-banner android-banner';
  const text=document.createElement('span');text.textContent='Kinnect cho Android · Tải app để nhận thông báo và dùng mượt hơn.';
  const get=document.createElement('a');get.className='banner-cta';get.href=APK_URL;get.target='_blank';get.rel='noopener';get.textContent='Tải app';
  const close=document.createElement('button');close.className='dismiss-install';close.textContent='×';close.setAttribute('aria-label','Ẩn gợi ý tải app');
  close.onclick=()=>{banner.remove();try{localStorage.setItem('kinnect-android-banner','off');}catch{}};
  banner.append(text,get,close);document.body.prepend(banner);
}
const platforms=document.createElement('section');platforms.className='platforms';platforms.setAttribute('aria-label','Dùng Kinnect trên thiết bị khác');
platforms.innerHTML='<h3>Dùng Kinnect ở mọi nơi</h3><a class="platform" target="_blank" rel="noopener"><b>Android</b><small>Tải file APK</small></a><button type="button" class="platform"><b>iPhone / iPad</b><small>Thêm vào màn hình chính</small></button><p class="platform-note"></p>';
platforms.querySelector('a').href=APK_URL;
platforms.querySelector('button').onclick=()=>dialog.showModal();
platforms.querySelector('.platform-note').textContent=isDesktop?'Bạn đang dùng bản web trên máy tính. Mở '+location.host+' trên điện thoại để cài app.':isIOS?'Bạn đang dùng iPhone/iPad.':isAndroid?'Bạn đang dùng Android.':'';
if(!inAndroidApp){const rail=document.getElementById('rail');if(rail){const keep=()=>{if(!rail.querySelector('.platforms'))rail.append(platforms);};new MutationObserver(keep).observe(rail,{childList:true});keep();}}
for(const copy of document.querySelectorAll('#auth .platforms')){copy.querySelector('button').onclick=()=>dialog.showModal();}

// Install prompts belong to the login screen; keep them out of authenticated app layout.
const installAppRoot=document.getElementById('app');
const syncInstallPrompts=()=>{for(const banner of document.querySelectorAll('.ios-install-banner'))banner.hidden=!!installAppRoot&&!installAppRoot.hidden;};
if(installAppRoot)new MutationObserver(syncInstallPrompts).observe(installAppRoot,{attributes:true,attributeFilter:['hidden']});
syncInstallPrompts();
