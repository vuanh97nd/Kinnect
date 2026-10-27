const CACHE = 'kinnect-static-v30-call-27b';
self.addEventListener('message', event => { if(event.data === 'SKIP_WAITING') self.skipWaiting(); });
const STATIC = ['/v2.css','/v2.js','/v2-icons.js','/camera.js','/kinnect-icon-192.png','/apple-touch-icon.png','/offline.html'];
// Cài đặt từng tệp riêng để một tệp lỗi không làm hỏng toàn bộ việc đăng ký SW.
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(async cache => {
    await Promise.all(STATIC.map(async url => {
      try { await cache.add(url); } catch (e) { /* bỏ qua tệp lỗi lẻ, không chặn cài đặt */ }
    }));
    await self.skipWaiting();
  }));
});
self.addEventListener('activate', event => { event.waitUntil(self.clients.claim().then(() => caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('kinnect-static-') && key !== CACHE).map(key => caches.delete(key)))))); });
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;
  if (event.request.mode === 'navigate') {
    const offlinePage = () => caches.match('/offline.html');
    event.respondWith(self.navigator.onLine === false
      ? offlinePage()
      : fetch(event.request, { cache: "no-store" }).catch(offlinePage));
  } else if (STATIC.includes(url.pathname)) {
    if (self.navigator.onLine === false) {
      event.respondWith(caches.match(url.pathname).then(response => response || Response.error()));
      return;
    }
    event.respondWith(fetch(event.request, { cache: "no-store" }).then(response => {
      if (response.ok) { const copy = response.clone(); event.waitUntil(caches.open(CACHE).then(cache => cache.put(url.pathname, copy))); }
      return response;
    }).catch(() => caches.match(url.pathname)));
  }
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || '/', self.location.origin);
  if (target.origin !== self.location.origin) return;
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async windows => {
    const windowClient = windows.find(client => new URL(client.url).origin === target.origin && !new URL(client.url).searchParams.has('website-session'));
    if (windowClient) { await windowClient.navigate(target.href); return windowClient.focus(); }
    return clients.openWindow(target.href);
  }));
});
