const CACHE = 'kinnect-static-v16';
self.addEventListener('message', event => { if(event.data === 'SKIP_WAITING') self.skipWaiting(); });
const STATIC = ['/style.css','/social.css','/ios.css','/theme.css','/app-ui.css','/social.js','/app.js','/ios.js','/onboarding.js','/auth-preview.jpg','/kinnect-icon.png','/kinnect-icon-192.png','/apple-touch-icon.png','/kinnect-mark.svg','/offline.html'];
self.addEventListener('install', event => { event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(STATIC).then(() => self.skipWaiting()))); });
self.addEventListener('activate', event => { event.waitUntil(self.clients.claim().then(() => caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('kinnect-static-') && key !== CACHE).map(key => caches.delete(key)))))); });
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return;
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match('/offline.html')));
  } else if (STATIC.includes(url.pathname)) {
    event.respondWith(fetch(event.request).then(response => {
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
