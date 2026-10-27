const CACHE = 'kinnect-static-v31-push';
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

// ---- Web Push: cuộc gọi đổ chuông + thông báo chi tiết khi Kinnect đang đóng ----
const ringing = new Map(); // callId -> true while the call is still ringing
const RING = [900, 400, 900, 400, 900, 1200];
const wait = ms => new Promise(r => setTimeout(r, ms));
async function visibleClient() {
  const list = await clients.matchAll({ type: 'window', includeUncontrolled: true });
  return list.find(c => c.visibilityState === 'visible');
}
async function ringCall(d) {
  const video = d.mode !== 'audio', title = d.from?.name || 'Kinnect';
  const options = {
    body: video ? '📹 Cuộc gọi video đến · Chạm để trả lời' : '📞 Cuộc gọi thoại đến · Chạm để trả lời',
    icon: d.icon || '/kinnect-icon-192.png', badge: '/kinnect-icon-192.png', tag: 'kinnect-call-' + d.callId,
    requireInteraction: true, renotify: true, silent: false, vibrate: RING,
    actions: [{ action: 'accept', title: video ? 'Trả lời video' : 'Trả lời' }, { action: 'decline', title: 'Từ chối' }],
    data: { url: '/?call=' + encodeURIComponent(d.callId), callId: d.callId, call: true },
  };
  ringing.set(d.callId, true);
  // Nhắc lại thông báo vài giây một lần để tạo hiệu ứng đổ chuông (tối đa ~40 giây).
  const until = (d.at || Date.now()) + 40000;
  for (let i = 0; ringing.get(d.callId) && Date.now() < until; i++) {
    await self.registration.showNotification(title, options);
    if (i === 0) broadcast({ type: 'push-call', callId: d.callId });
    await wait(i === 0 ? 5000 : 4000);
  }
}
async function endCall(d) {
  ringing.delete(d.callId);
  const open = await self.registration.getNotifications({ tag: 'kinnect-call-' + d.callId });
  open.forEach(n => n.close());
  if (d.reason === 'answered' || d.reason === 'declined') {
    // Safari yêu cầu mỗi push phải hiện thông báo: hiện bản tóm tắt im lặng rồi đóng.
    const n = await self.registration.showNotification('Kinnect', { body: d.reason === 'answered' ? 'Cuộc gọi đã được trả lời' : 'Đã từ chối cuộc gọi', tag: 'kinnect-call-done', silent: true, icon: '/kinnect-icon-192.png' });
    setTimeout(() => self.registration.getNotifications({ tag: 'kinnect-call-done' }).then(l => l.forEach(x => x.close())), 3000);
    return n;
  }
  return self.registration.showNotification(d.from?.name || 'Kinnect', {
    body: d.mode === 'audio' ? 'Cuộc gọi thoại nhỡ' : 'Cuộc gọi video nhỡ', icon: d.icon || '/kinnect-icon-192.png', badge: '/kinnect-icon-192.png',
    tag: 'kinnect-missed-' + d.callId, data: { url: d.from ? '/?chat=' + encodeURIComponent(d.from.id) : '/' },
  });
}
async function broadcast(message) { (await clients.matchAll({ type: 'window', includeUncontrolled: true })).forEach(c => c.postMessage(message)); }
self.addEventListener('push', event => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch {}
  event.waitUntil((async () => {
    if (d.type === 'call') return ringCall(d);
    if (d.type === 'call-ended') return endCall(d);
    if (d.type === 'notification') {
      const chat = d.kind === 'message' || d.kind === 'group_message';
      return self.registration.showNotification(d.title || 'Kinnect', {
        body: d.body || 'Có thông báo mới', icon: d.icon || '/kinnect-icon-192.png', badge: '/kinnect-icon-192.png', tag: d.tag || 'kinnect',
        renotify: true, timestamp: d.created || Date.now(), vibrate: chat ? [200, 100, 200] : [150],
        actions: chat ? [{ action: 'open', title: 'Trả lời' }] : [], data: { url: d.url || '/' },
      });
    }
    return self.registration.showNotification('Kinnect', { body: 'Có hoạt động mới trên Kinnect', icon: '/kinnect-icon-192.png', tag: 'kinnect' });
  })());
});
self.addEventListener('notificationclose', event => { const id = event.notification.data?.callId; if (id) ringing.delete(id); });
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const data = event.notification.data || {};
  if (data.callId) ringing.delete(data.callId);
  if (data.call && event.action === 'decline') {
    event.waitUntil(fetch('/api/push/decline', { method: 'POST', credentials: 'include', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ callId: data.callId }) }).catch(() => {}));
    return;
  }
  const target = new URL((data.url || '/') + (data.call && event.action === 'accept' ? '&answer=1' : ''), self.location.origin);
  if (target.origin !== self.location.origin) return;
  event.waitUntil(clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async windows => {
    const windowClient = windows.find(client => new URL(client.url).origin === target.origin && !new URL(client.url).searchParams.has('website-session'));
    if (windowClient) { await windowClient.navigate(target.href); return windowClient.focus(); }
    return clients.openWindow(target.href);
  }));
});
