const faqs = document.querySelectorAll('.faq details');
faqs.forEach(detail => detail.addEventListener('toggle', () => {
  if (detail.open) faqs.forEach(other => { if (other !== detail) other.open = false; });
}));
const dialog = document.createElement('dialog');
dialog.className = 'ios-sheet';
dialog.setAttribute('aria-labelledby', 'ios-title');
dialog.innerHTML = '<button class="close-dialog" aria-label="Đóng hướng dẫn">×</button><div class="eyebrow">KINNECT FOR iPHONE & iPAD</div><h2 id="ios-title">Một chạm. Vào Kinnect.</h2><p>Không cần tải APK. Mở Kinnect bằng Safari và thêm vào màn hình chính như một ứng dụng web.</p><ol><li>Chạm <b>Mở bản web iOS</b> bên dưới.</li><li>Trong Safari, chọn <b>Chia sẻ</b> (hình vuông có mũi tên hướng lên).</li><li>Chọn <b>Thêm vào MH chính</b>, bật <b>Mở dưới dạng ứng dụng web</b> nếu có, rồi chọn <b>Thêm</b>.</li></ol><p>Bản thử nghiệm cần kết nối Internet. Camera và micro chỉ được dùng sau khi bạn cấp quyền.</p><a class="button dark" href="https://app.kinnect.io.vn" target="_blank" rel="noopener">Mở bản web iOS ↗</a>';
document.body.append(dialog);
dialog.querySelector('.close-dialog').onclick = () => dialog.close();
dialog.addEventListener('click', event => { if (event.target === dialog) dialog.close(); });
const iosButton = document.createElement('button');
iosButton.className = 'ios-install-link';
iosButton.textContent = 'Dùng iPhone? Thêm Kinnect ra màn hình chính ↗';
iosButton.onclick = () => dialog.showModal();
document.querySelector('.download-note').after(iosButton);

// Nhận diện thiết bị: tô nổi nút tải phù hợp, nút iPhone mở hướng dẫn, thanh tải app cố định trên điện thoại.
(() => {
  const ua = navigator.userAgent;
  const ios = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const android = /Android/i.test(ua);
  const platform = ios ? 'ios' : android ? 'android' : 'desktop';
  const pick = document.querySelector('.get-btn[data-platform="' + platform + '"]');
  if (pick) pick.classList.add('recommended');
  const iosBtn = document.querySelector('.get-btn[data-platform="ios"]');
  if (iosBtn) iosBtn.onclick = () => dialog.showModal();
  if (platform !== 'desktop') document.querySelector('.get-qr')?.remove();
  const bar = document.querySelector('.sticky-get');
  const hero = document.getElementById('get-app');
  if (bar && hero && platform !== 'desktop') {
    bar.hidden = false;
    const btn = bar.querySelector('.sticky-btn');
    if (platform === 'ios') { btn.textContent = 'Dùng ngay'; btn.onclick = (e) => { e.preventDefault(); dialog.showModal(); }; }
    else { btn.href = pick.href; btn.target = '_blank'; btn.rel = 'noopener'; }
    new IntersectionObserver(([e]) => bar.classList.toggle('show', !e.isIntersecting)).observe(hero);
  }
})();
