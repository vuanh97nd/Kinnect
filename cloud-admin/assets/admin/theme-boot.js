/* Áp dụng giao diện sáng/tối TRƯỚC khi trình duyệt vẽ trang.
   Tệp rời (không nhúng) để không bị CSP `script-src 'self'` chặn. */
(function () {
  try {
    var saved = localStorage.getItem('kinnect:theme');
    var dark = saved === 'dark' ||
      (!saved && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', dark ? '#100e18' : '#5a2fc0');
  } catch (e) {
    document.documentElement.setAttribute('data-theme', 'light');
  }
})();
