import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../server.js';
import { resolveFfmpegPath } from '../lib/media-compression.js';

const execFileAsync = promisify(execFile);

async function makeSampleMp4(ffmpegPath, seconds = 2) {
  const dir = await mkdtemp(join(tmpdir(), 'kinnect-p1-vid-'));
  try {
    const out = join(dir, 'clip.mp4');
    await execFileAsync(ffmpegPath, [
      '-v', 'error', '-y',
      '-f', 'lavfi', '-i', `testsrc2=size=960x540:rate=30:duration=${seconds}`,
      '-f', 'lavfi', '-i', `sine=frequency=440:duration=${seconds}`,
      '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '24', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '96k',
      '-movflags', '+faststart',
      out,
    ], { timeout: 25000, windowsHide: true });
    return await readFile(out);
  } finally {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

async function makeSamplePng(ffmpegPath) {
  const dir = await mkdtemp(join(tmpdir(), 'kinnect-p1-img-'));
  try {
    const out = join(dir, 'img.png');
    await execFileAsync(ffmpegPath, [
      '-v', 'error', '-y',
      '-f', 'lavfi', '-i', 'testsrc2=size=640x480:duration=1',
      '-frames:v', '1',
      out,
    ], { timeout: 15000, windowsHide: true });
    return await readFile(out);
  } finally {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
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

test('Phase 1: media ETag/304 caching, cursor pagination, and automatic video thumbnails', async (t) => {
  const ffmpegPath = resolveFfmpegPath();
  if (!ffmpegPath) {
    t.skip('ffmpeg binary not available on this host');
    return;
  }

  const app = createApp({
    authLimit: 200,
    mediaCompression: {
      enabled: true,
      ffmpegPath,
      minVideoBytes: 512 * 1024, // Keep small clip fast while still verifying thumbnail generation
    },
  });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  t.after(async () => {
    for (const ws of app.wss.clients) ws.terminate();
    await new Promise((r) => app.wss.close(r));
    app.server.closeAllConnections();
    await new Promise((r) => app.server.close(r));
    app.social.close();
  });

  const origin = 'http://127.0.0.1:' + app.server.address().port;
  const alice = await registerUser(origin, 'p1_alice', 'Alice');
  const bob = await registerUser(origin, 'p1_bob', 'Bob');
  const aHeaders = { Cookie: alice.cookie, Origin: origin, 'Content-Type': 'application/json' };
  const bHeaders = { Cookie: bob.cookie, Origin: origin, 'Content-Type': 'application/json' };

  const png = await makeSamplePng(ffmpegPath);
  const pngUrl = 'data:image/png;base64,' + png.toString('base64');
  const mp4 = await makeSampleMp4(ffmpegPath, 2);
  const mp4Url = 'data:video/mp4;base64,' + mp4.toString('base64');

  // --- 1. Media Caching + ETag 304 ---
  const avRes = await fetch(origin + '/api/me/avatar', { method: 'POST', headers: aHeaders, body: JSON.stringify({ data: pngUrl }) });
  assert.equal(avRes.status, 200);
  const avUser = (await avRes.json()).user;
  assert.ok(avUser.avatar && avUser.avatar.includes('?v='));

  const avGet1 = await fetch(origin + avUser.avatar, { headers: { Cookie: alice.cookie } });
  assert.equal(avGet1.status, 200);
  assert.match(avGet1.headers.get('cache-control'), /^private, max-age=3600, must-revalidate$/);
  const avEtag = avGet1.headers.get('etag');
  assert.ok(avEtag);
  const avGet304 = await fetch(origin + avUser.avatar, { headers: { Cookie: alice.cookie, 'If-None-Match': avEtag } });
  assert.equal(avGet304.status, 304);
  assert.equal(await avGet304.text(), '');

  // Private photo MUST still stay private, no-store!
  const privRes = await fetch(origin + '/api/me/private-photos', { method: 'POST', headers: aHeaders, body: JSON.stringify({ data: pngUrl }) });
  assert.equal(privRes.status, 201);
  const privUrl = (await privRes.json()).photos[0].url;
  const privGet = await fetch(origin + privUrl, { headers: { Cookie: alice.cookie } });
  assert.equal(privGet.status, 200);
  assert.equal(privGet.headers.get('cache-control'), 'private, no-store');

  // Chat attachment ETag + 304 + security headers
  const chatAttRes = await fetch(origin + '/api/users/' + bob.user.id + '/messages', {
    method: 'POST',
    headers: aHeaders,
    body: JSON.stringify({ body: 'photo', attachment: { name: 'test.png', data: pngUrl } }),
  });
  assert.equal(chatAttRes.status, 201);
  const chatList = await (await fetch(origin + '/api/users/' + bob.user.id + '/messages', { headers: { Cookie: alice.cookie } })).json();
  const attUrl = chatList.messages[0].attachment.url;
  const attGet1 = await fetch(origin + attUrl, { headers: { Cookie: alice.cookie } });
  assert.equal(attGet1.status, 200);
  assert.match(attGet1.headers.get('cache-control'), /^private, max-age=120, must-revalidate$/);
  assert.equal(attGet1.headers.get('content-security-policy'), "default-src 'none'; sandbox");
  const attGet304 = await fetch(origin + attUrl, { headers: { Cookie: alice.cookie, 'If-None-Match': attGet1.headers.get('etag') } });
  assert.equal(attGet304.status, 304);

  // --- 2. Cursor Pagination: Direct Chat ---
  for (let i = 1; i <= 4; i++) {
    const mr = await fetch(origin + '/api/users/' + bob.user.id + '/messages', {
      method: 'POST',
      headers: aHeaders,
      body: JSON.stringify({ body: 'dm-' + i }),
    });
    assert.equal(mr.status, 201);
  }
  const dmP1 = await (await fetch(origin + '/api/users/' + bob.user.id + '/messages?limit=2', { headers: { Cookie: alice.cookie } })).json();
  assert.equal(dmP1.messages.length, 2);
  assert.deepEqual(dmP1.messages.map((m) => m.body), ['dm-3', 'dm-4']);
  assert.equal(dmP1.hasMore, true);
  assert.ok(dmP1.nextCursor > 0);

  const dmP2 = await (await fetch(origin + `/api/users/${bob.user.id}/messages?limit=2&before=${dmP1.nextCursor}`, { headers: { Cookie: alice.cookie } })).json();
  assert.equal(dmP2.messages.length, 2);
  assert.deepEqual(dmP2.messages.map((m) => m.body), ['dm-1', 'dm-2']);
  assert.equal(dmP2.hasMore, true);

  const dmP3 = await (await fetch(origin + `/api/users/${bob.user.id}/messages?limit=2&before=${dmP2.nextCursor}`, { headers: { Cookie: alice.cookie } })).json();
  assert.equal(dmP3.messages.length, 1);
  assert.equal(dmP3.messages[0].body, 'photo');
  assert.equal(dmP3.hasMore, false);
  assert.equal(dmP3.nextCursor, null);

  // --- 3. Cursor Pagination: Group Chat ---
  const grpRes = await fetch(origin + '/api/groups', {
    method: 'POST',
    headers: aHeaders,
    body: JSON.stringify({ name: 'Paging Group', members: [bob.user.id] }),
  });
  assert.equal(grpRes.status, 201);
  const groupId = (await grpRes.json()).group.id;
  for (let i = 1; i <= 5; i++) {
    const gr = await fetch(origin + `/api/groups/${groupId}/messages`, {
      method: 'POST',
      headers: aHeaders,
      body: JSON.stringify({ body: 'grp-' + i }),
    });
    assert.equal(gr.status, 201);
  }
  const gP1 = await (await fetch(origin + `/api/groups/${groupId}/messages?limit=2`, { headers: { Cookie: bob.cookie } })).json();
  assert.deepEqual(gP1.messages.map((m) => m.body), ['grp-4', 'grp-5']);
  assert.equal(gP1.hasMore, true);
  const gP2 = await (await fetch(origin + `/api/groups/${groupId}/messages?limit=2&before=${gP1.nextCursor}`, { headers: { Cookie: bob.cookie } })).json();
  assert.deepEqual(gP2.messages.map((m) => m.body), ['grp-2', 'grp-3']);
  assert.equal(gP2.hasMore, true);
  const gP3 = await (await fetch(origin + `/api/groups/${groupId}/messages?limit=2&before=${gP2.nextCursor}`, { headers: { Cookie: bob.cookie } })).json();
  assert.deepEqual(gP3.messages.map((m) => m.body), ['grp-1']);
  assert.equal(gP3.hasMore, false);

  // --- 4. Cursor Pagination: Posts Feed + Video Thumbnail ---
  // Note: avatar upload created 1 post already; add 3 more posts (last one with video).
  const createdPostIds = [];
  for (let i = 1; i <= 2; i++) {
    await new Promise((r) => setTimeout(r, 5));
    const pr = await fetch(origin + '/api/posts', { method: 'POST', headers: aHeaders, body: JSON.stringify({ body: 'post-' + i }) });
    assert.equal(pr.status, 201);
    createdPostIds.push((await pr.json()).id);
  }
  await new Promise((r) => setTimeout(r, 5));
  const vidPostRes = await fetch(origin + '/api/posts', {
    method: 'POST',
    headers: aHeaders,
    body: JSON.stringify({ body: 'post-video', media: mp4Url }),
  });
  assert.equal(vidPostRes.status, 201);
  const vidPostId = (await vidPostRes.json()).id;

  // --- 5. Shorts Pagination + Automatic Video Thumbnails ---
  const shortIds = [];
  for (let i = 1; i <= 3; i++) {
    await new Promise((r) => setTimeout(r, 5));
    const sr = await fetch(origin + '/api/shorts', {
      method: 'POST',
      headers: aHeaders,
      body: JSON.stringify({ caption: 'short-' + i, data: mp4Url }),
    });
    assert.equal(sr.status, 201);
    shortIds.push((await sr.json()).id);
  }

  // Wait for background video worker to generate thumbnails.
  await app.social.mediaCompressor.drain();

  const postsP1 = await (await fetch(origin + '/api/posts?limit=2', { headers: { Cookie: bob.cookie } })).json();
  assert.equal(postsP1.posts.length, 2);
  assert.equal(postsP1.hasMore, true);
  assert.ok(postsP1.nextCursor > 0);
  const vidPostItem = postsP1.posts.find((p) => p.id === vidPostId);
  assert.ok(vidPostItem?.media?.thumbnail, 'video post should expose thumbnail URL');
  assert.equal(vidPostItem.media.thumbnail, `/api/posts/${vidPostId}/thumbnail`);

  const postsP2 = await (await fetch(origin + `/api/posts?limit=2&before=${postsP1.nextCursor}`, { headers: { Cookie: bob.cookie } })).json();
  assert.equal(postsP2.posts.length, 2);
  assert.equal(postsP2.hasMore, false);

  // Post media & thumbnail caching (also test guest access on public post!)
  const pMedia1 = await fetch(origin + `/api/posts/${vidPostId}/media`);
  assert.equal(pMedia1.status, 200);
  assert.match(pMedia1.headers.get('cache-control'), /^private, max-age=300, must-revalidate$/);
  const pMedia304 = await fetch(origin + `/api/posts/${vidPostId}/media`, { headers: { 'If-None-Match': pMedia1.headers.get('etag') } });
  assert.equal(pMedia304.status, 304);

  const pThumb1 = await fetch(origin + `/api/posts/${vidPostId}/thumbnail`);
  assert.equal(pThumb1.status, 200);
  assert.equal(pThumb1.headers.get('content-type'), 'image/jpeg');
  assert.match(pThumb1.headers.get('cache-control'), /^private, max-age=600, must-revalidate$/);
  const pThumbBytes = Buffer.from(await pThumb1.arrayBuffer());
  assert.equal(pThumbBytes[0], 0xff);
  assert.equal(pThumbBytes[1], 0xd8);
  const pThumb304 = await fetch(origin + `/api/posts/${vidPostId}/thumbnail`, { headers: { 'If-None-Match': pThumb1.headers.get('etag') } });
  assert.equal(pThumb304.status, 304);

  // Shorts pagination + thumbnail endpoint + ETag/304
  const shortsP1 = await (await fetch(origin + '/api/shorts?limit=2&offset=0', { headers: { Cookie: bob.cookie } })).json();
  assert.equal(shortsP1.shorts.length, 2);
  assert.equal(shortsP1.hasMore, true);
  assert.equal(shortsP1.nextOffset, 2);
  assert.equal(shortsP1.shorts[0].thumbnail, `/api/shorts/${shortsP1.shorts[0].id}/thumbnail`);

  const shortsP2 = await (await fetch(origin + '/api/shorts?limit=2&offset=2', { headers: { Cookie: bob.cookie } })).json();
  assert.equal(shortsP2.shorts.length, 1);
  assert.equal(shortsP2.hasMore, false);
  assert.equal(shortsP2.nextOffset, null);

  const sThumb1 = await fetch(origin + `/api/shorts/${shortIds[0]}/thumbnail`);
  assert.equal(sThumb1.status, 200);
  assert.equal(sThumb1.headers.get('content-type'), 'image/jpeg');
  const sThumb304 = await fetch(origin + `/api/shorts/${shortIds[0]}/thumbnail`, { headers: { 'If-None-Match': sThumb1.headers.get('etag') } });
  assert.equal(sThumb304.status, 304);

  const sVid1 = await fetch(origin + `/api/shorts/${shortIds[0]}/video`);
  assert.equal(sVid1.status, 200);
  assert.match(sVid1.headers.get('cache-control'), /^private, max-age=600, must-revalidate$/);
  const sVid304 = await fetch(origin + `/api/shorts/${shortIds[0]}/video`, { headers: { 'If-None-Match': sVid1.headers.get('etag') } });
  assert.equal(sVid304.status, 304);

  // Delete cleans up thumbnails cleanly
  assert.equal((await fetch(origin + `/api/posts/${vidPostId}`, { method: 'DELETE', headers: aHeaders })).status, 200);
  assert.equal(app.social.db.prepare("SELECT 1 FROM media_thumbnails WHERE kind='post' AND target_id=?").get(vidPostId), undefined);
  assert.equal((await fetch(origin + `/api/shorts/${shortIds[0]}`, { method: 'DELETE', headers: aHeaders })).status, 200);
  assert.equal(app.social.db.prepare("SELECT 1 FROM media_thumbnails WHERE kind='short' AND target_id=?").get(shortIds[0]), undefined);

  assert.ok(app.social.mediaCompressor.status().thumbnailsGenerated >= 4);
});
