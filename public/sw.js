const CACHE = 'kinnect-static-v15';
self.addEventListener('message', event => { if(event.data === 'SKIP_WAITING') self.skipWaiting(); });
const STATIC = ['/style.css','/social.css','/ios.css','/theme.css','/app-ui.css','/social.js','/app.js','/ios.js','/onboarding.js','/auth-preview.jpg','/kinnect-icon.png','/kinnect-icon-192.png','/apple-touch-icon.png','/kinnect-mark.svg','/offline.html'];
self.addEventListener('install', event => { event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(STATIC))); });
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
