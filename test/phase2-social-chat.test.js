import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server.js';

function tinyPng(tag = 1) {
  const b = Buffer.alloc(64, tag);
  Buffer.from('89504e470d0a1a0a', 'hex').copy(b);
  return 'data:image/png;base64,' + b.toString('base64');
}

async function registerUser(origin, username, name) {
  const r = await fetch(origin + '/api/register', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      username,
      name,
      password: 'test-password-strong',
      birthDate: '1994-05-10',
      agree18: true,
      acceptPrivacyNotice: true,
    }),
  });
  assert.equal(r.status, 200);
  const cookie = r.headers.get('set-cookie').split(';')[0];
  const body = await r.json();
  return { cookie, user: body.user };
}

test('Phase 2: chat reply/quote, message & post/hashtag search, multi-photo albums, bookmarks, and share/repost', async (t) => {
  const app = createApp({ authLimit: 300 });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  t.after(async () => {
    for (const ws of app.wss.clients) ws.terminate();
    await new Promise((r) => app.wss.close(r));
    app.server.closeAllConnections();
    await new Promise((r) => app.server.close(r));
    app.social.close();
  });

  const origin = 'http://127.0.0.1:' + app.server.address().port;
  const alice = await registerUser(origin, 'p2_alice', 'Alice');
  const bob = await registerUser(origin, 'p2_bob', 'Bob');
  const carol = await registerUser(origin, 'p2_carol', 'Carol');
  const aH = { Cookie: alice.cookie, Origin: origin, 'Content-Type': 'application/json' };
  const bH = { Cookie: bob.cookie, Origin: origin, 'Content-Type': 'application/json' };
  const cH = { Cookie: carol.cookie, Origin: origin, 'Content-Type': 'application/json' };

  // --- 1. Direct Chat Reply/Quote + Recall redaction + Message Search ---
  const m1Res = await fetch(origin + `/api/users/${bob.user.id}/messages`, {
    method: 'POST', headers: aH,
    body: JSON.stringify({ body: 'Tối nay đi cà phê Sài Gòn nhé!' }),
  });
  assert.equal(m1Res.status, 201);
  const m1 = (await m1Res.json()).message;

  // Cross-conversation reply must be rejected
  const badReply = await fetch(origin + `/api/users/${carol.user.id}/messages`, {
    method: 'POST', headers: aH,
    body: JSON.stringify({ body: 'spoof reply', replyToId: m1.id }),
  });
  assert.equal(badReply.status, 400);

  const m2Res = await fetch(origin + `/api/users/${alice.user.id}/messages`, {
    method: 'POST', headers: bH,
    body: JSON.stringify({ body: 'Chốt kèo luôn!', replyToId: m1.id }),
  });
  assert.equal(m2Res.status, 201);
  const m2 = (await m2Res.json()).message;
  assert.equal(m2.replyTo.id, m1.id);
  assert.equal(m2.replyTo.senderName, 'Alice');
  assert.match(m2.replyTo.body, /cà phê Sài Gòn/);

  // Diacritic-insensitive direct message search
  const dmSearch = await (await fetch(origin + `/api/users/${bob.user.id}/messages/search?q=ca+phe+sai+gon`, { headers: { Cookie: alice.cookie } })).json();
  assert.equal(dmSearch.messages.length, 1);
  assert.equal(dmSearch.messages[0].id, m1.id);

  // Recalling quoted message redacts quote preview
  assert.equal((await fetch(origin + `/api/chat-messages/direct/${m1.id}/recall`, { method: 'POST', headers: aH })).status, 200);
  const dmAfterRecall = await (await fetch(origin + `/api/users/${alice.user.id}/messages`, { headers: { Cookie: bob.cookie } })).json();
  const quoted = dmAfterRecall.messages.find((x) => x.id === m2.id);
  assert.equal(quoted.replyTo.recalled, true);
  assert.equal(quoted.replyTo.body, 'Tin nhắn đã được thu hồi');

  // --- 2. Group Chat Reply/Quote + Group Search + Global Message Search ---
  const gRes = await fetch(origin + '/api/groups', {
    method: 'POST', headers: aH,
    body: JSON.stringify({ name: 'Team Kinnect', members: [bob.user.id] }),
  });
  assert.equal(gRes.status, 201);
  const groupId = (await gRes.json()).group.id;

  const gm1 = (await (await fetch(origin + `/api/groups/${groupId}/messages`, {
    method: 'POST', headers: aH,
    body: JSON.stringify({ body: 'Lịch họp cuối tuần tại Hà Nội' }),
  })).json()).message;

  const gm2 = (await (await fetch(origin + `/api/groups/${groupId}/messages`, {
    method: 'POST', headers: bH,
    body: JSON.stringify({ body: 'Ok mình tham gia!', replyToId: gm1.id }),
  })).json()).message;
  assert.equal(gm2.replyTo.id, gm1.id);
  assert.match(gm2.replyTo.body, /Hà Nội/);

  const gSearch = await (await fetch(origin + `/api/groups/${groupId}/messages/search?q=ha+noi`, { headers: { Cookie: bob.cookie } })).json();
  assert.equal(gSearch.messages.length, 1);
  assert.equal(gSearch.messages[0].id, gm1.id);

  const globalSearch = await (await fetch(origin + '/api/messages/search?q=chot+keo', { headers: { Cookie: alice.cookie } })).json();
  assert.equal(globalSearch.results.length, 1);
  assert.equal(globalSearch.results[0].kind, 'direct');
  assert.equal(globalSearch.results[0].message.id, m2.id);

  // Carol is NOT in the group, so global search must NOT leak group messages
  const carolSearch = await (await fetch(origin + '/api/messages/search?q=ha+noi', { headers: { Cookie: carol.cookie } })).json();
  assert.equal(carolSearch.results.length, 0);

  // --- 3. Multi-Photo Album Posts (1..10 images) ---
  const tooMany = await fetch(origin + '/api/posts', {
    method: 'POST', headers: aH,
    body: JSON.stringify({ body: 'Too many', mediaItems: Array.from({ length: 11 }, (_, i) => tinyPng(i + 1)) }),
  });
  assert.equal(tooMany.status, 400);

  const albumRes = await fetch(origin + '/api/posts', {
    method: 'POST', headers: aH,
    body: JSON.stringify({
      body: 'Chuyến đi Đà Lạt tuyệt vời #DaLat #Kinnect_2026',
      mediaItems: [tinyPng(10), tinyPng(20), tinyPng(30)],
    }),
  });
  assert.equal(albumRes.status, 201);
  const albumId = (await albumRes.json()).id;

  // Private followers-only post with hashtag (Carol does not follow Alice)
  const privatePostRes = await fetch(origin + '/api/posts', {
    method: 'POST', headers: aH,
    body: JSON.stringify({ body: 'Bí mật riêng #DaLat #SecretTag', visibility: 'followers' }),
  });
  assert.equal(privatePostRes.status, 201);
  const privatePostId = (await privatePostRes.json()).id;

  const feedRes = await (await fetch(origin + `/api/posts?post=${albumId}`, { headers: { Cookie: bob.cookie } })).json();
  const albumPost = feedRes.posts[0];
  assert.equal(albumPost.media.url, `/api/posts/${albumId}/media`);
  assert.equal(albumPost.mediaItems.length, 3);
  assert.deepEqual(albumPost.hashtags.sort(), ['dalat', 'kinnect_2026']);

  // Fetch 2nd album photo (works with ETag + 304!)
  const item2Res = await fetch(origin + albumPost.mediaItems[1].url, { headers: { Cookie: bob.cookie } });
  assert.equal(item2Res.status, 200);
  const item2Etag = item2Res.headers.get('etag');
  assert.ok(item2Etag);
  const item2304 = await fetch(origin + albumPost.mediaItems[1].url, { headers: { Cookie: bob.cookie, 'If-None-Match': item2Etag } });
  assert.equal(item2304.status, 304);

  // --- 4. Post Search, Hashtags & Trending ---
  const searchPosts = await (await fetch(origin + '/api/search/posts?q=da+lat', { headers: { Cookie: carol.cookie } })).json();
  assert.equal(searchPosts.posts.length, 1);
  assert.equal(searchPosts.posts[0].id, albumId);

  const tagSearch = await (await fetch(origin + '/api/posts?tag=kinnect_2026', { headers: { Cookie: carol.cookie } })).json();
  assert.equal(tagSearch.posts.length, 1);
  assert.equal(tagSearch.posts[0].id, albumId);

  const trending = await (await fetch(origin + '/api/hashtags/trending', { headers: { Cookie: carol.cookie } })).json();
  assert.ok(trending.hashtags.some((h) => h.tag === 'dalat' && h.count === 1));
  assert.ok(!trending.hashtags.some((h) => h.tag === 'secrettag'), 'followers-only hashtag must not leak to non-followers');

  // --- 5. Bookmarks ---
  assert.equal((await fetch(origin + `/api/posts/${albumId}/bookmark`, { method: 'POST', headers: bH })).status, 200);
  const bmList = await (await fetch(origin + '/api/bookmarks', { headers: { Cookie: bob.cookie } })).json();
  assert.equal(bmList.posts.length, 1);
  assert.equal(bmList.posts[0].id, albumId);
  assert.equal(bmList.posts[0].bookmarked, true);

  assert.equal((await fetch(origin + `/api/posts/${albumId}/bookmark`, { method: 'DELETE', headers: bH })).status, 200);
  const bmAfter = await (await fetch(origin + '/api/bookmarks', { headers: { Cookie: bob.cookie } })).json();
  assert.equal(bmAfter.posts.length, 0);

  // --- 6. Share / Repost ---
  // Cannot share followers-only private post
  assert.equal((await fetch(origin + `/api/posts/${privatePostId}/share`, { method: 'POST', headers: aH, body: JSON.stringify({ body: 'try share private' }) })).status, 403);

  const shareRes = await fetch(origin + `/api/posts/${albumId}/share`, {
    method: 'POST', headers: bH,
    body: JSON.stringify({ body: 'Đẹp quá mọi người ơi #DaLat' }),
  });
  assert.equal(shareRes.status, 201);
  const shareBody = await shareRes.json();
  assert.equal(shareBody.post.sharedPost.id, albumId);
  assert.equal(shareBody.post.sharedPost.mediaItems.length, 3);

  // Original post now shows shares = 1
  const origReload = await (await fetch(origin + `/api/posts?post=${albumId}`, { headers: { Cookie: bob.cookie } })).json();
  assert.equal(origReload.posts[0].shares, 1);

  // Alice received a share notification
  const aliceNotifs = await (await fetch(origin + '/api/notifications', { headers: { Cookie: alice.cookie } })).json();
  assert.ok(aliceNotifs.notifications.some((n) => n.kind === 'share' && n.ref === shareBody.id));
});
