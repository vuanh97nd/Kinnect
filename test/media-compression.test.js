import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../server.js';
import { resolveFfmpegPath } from '../lib/media-compression.js';
import { mp4Duration } from '../lib/shorts.js';

const execFileAsync = promisify(execFile);

async function makeLargePng(ffmpegPath, width = 2000, height = 1400, noise = 6) {
  const dir = await mkdtemp(join(tmpdir(), 'kinnect-test-img-'));
  try {
    const out = join(dir, 'sample.png');
    await execFileAsync(ffmpegPath, [
      '-v', 'error', '-y',
      '-f', 'lavfi', '-i', `testsrc2=size=${width}x${height}:duration=1,noise=alls=${noise}:allf=t`,
      '-frames:v', '1',
      out,
    ], { timeout: 20000, windowsHide: true });
    return await readFile(out);
  } finally {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}

async function makeHeavyMp4(ffmpegPath, width = 1920, height = 1080, seconds = 2) {
  const dir = await mkdtemp(join(tmpdir(), 'kinnect-test-vid-'));
  try {
    const out = join(dir, 'heavy.mp4');
    await execFileAsync(ffmpegPath, [
      '-v', 'error', '-y',
      '-f', 'lavfi', '-i', `testsrc2=size=${width}x${height}:rate=60:duration=${seconds},noise=alls=6:allf=t`,
      '-f', 'lavfi', '-i', `sine=frequency=440:duration=${seconds}`,
      '-c:v', 'libx264', '-preset', 'ultrafast', '-b:v', '8000k', '-maxrate', '8000k', '-bufsize', '16000k', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-b:a', '192k',
      '-movflags', '+faststart',
      out,
    ], { timeout: 30000, windowsHide: true });
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
  assert.equal(r.status, 200, 'register failed');
  const cookie = r.headers.get('set-cookie').split(';')[0];
  const body = await r.json();
  return { cookie, user: body.user };
}

test('Option B media compression shrinks uploaded images and videos across endpoints', async (t) => {
  const ffmpegPath = resolveFfmpegPath();
  if (!ffmpegPath) {
    t.skip('ffmpeg binary not available on this host');
    return;
  }

  const app = createApp({
    mediaCompression: {
      enabled: true,
      ffmpegPath,
      minVideoBytes: 64 * 1024,
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
  const alice = await registerUser(origin, 'compress_alice', 'Alice');
  const bob = await registerUser(origin, 'compress_bob', 'Bob');
  const headers = { Cookie: alice.cookie, Origin: origin, 'Content-Type': 'application/json' };

  // 1. Large PNG image -> Post, Private Photo, Direct Chat
  const bigPng = await makeLargePng(ffmpegPath, 1800, 1200, 4);
  assert.ok(bigPng.length > 500 * 1024 && bigPng.length < 4 * 1024 * 1024, `expected large PNG 500KB..4MB, got ${bigPng.length}`);
  const bigPngDataUrl = 'data:image/png;base64,' + bigPng.toString('base64');

  const postImgRes = await fetch(origin + '/api/posts', {
    method: 'POST',
    headers,
    body: JSON.stringify({ body: 'Compressed post image', media: bigPngDataUrl }),
  });
  assert.equal(postImgRes.status, 201);
  const postImg = await postImgRes.json();
  const postRow = app.social.db.prepare('SELECT type, data FROM post_media WHERE post_id=?').get(postImg.id);
  assert.equal(postRow.type, 'image/jpeg');
  assert.ok(postRow.data.length < bigPng.length * 0.4, `post image should shrink significantly (${bigPng.length} -> ${postRow.data.length})`);

  const privRes = await fetch(origin + '/api/me/private-photos', {
    method: 'POST',
    headers,
    body: JSON.stringify({ data: bigPngDataUrl }),
  });
  assert.equal(privRes.status, 201);
  const privRow = app.social.db.prepare('SELECT type, data FROM private_photos WHERE user_id=?').get(alice.user.id);
  assert.equal(privRow.type, 'image/jpeg');
  assert.ok(privRow.data.length < bigPng.length * 0.4, `private photo should shrink (${bigPng.length} -> ${privRow.data.length})`);

  const chatImgRes = await fetch(origin + '/api/users/' + bob.user.id + '/messages', {
    method: 'POST',
    headers,
    body: JSON.stringify({ body: 'Here is a photo', attachment: { name: 'big-shot.png', data: bigPngDataUrl } }),
  });
  assert.equal(chatImgRes.status, 201);
  const chatImgBody = await chatImgRes.json();
  const chatImgRow = app.social.db.prepare("SELECT name, type, data FROM chat_attachments WHERE kind='direct' AND message_id=?").get(chatImgBody.message.id);
  assert.equal(chatImgRow.type, 'image/jpeg');
  assert.equal(chatImgRow.name, 'big-shot.jpg');
  assert.ok(chatImgRow.data.length < bigPng.length * 0.4, `chat image should shrink (${bigPng.length} -> ${chatImgRow.data.length})`);

  // 2. Avatar (< 1 MB input PNG) -> compressed to <= 512px JPEG
  const avatarPng = await makeLargePng(ffmpegPath, 640, 640, 3);
  assert.ok(avatarPng.length > 100 * 1024 && avatarPng.length < 1024 * 1024, `avatar fixture must be 100KB..1MB, got ${avatarPng.length}`);
  const avatarRes = await fetch(origin + '/api/me/avatar', {
    method: 'POST',
    headers,
    body: JSON.stringify({ data: 'data:image/png;base64,' + avatarPng.toString('base64') }),
  });
  assert.equal(avatarRes.status, 200);
  const userRow = app.social.db.prepare('SELECT avatar, avatar_type FROM users WHERE id=?').get(alice.user.id);
  assert.equal(userRow.avatar_type, 'image/jpeg');
  assert.ok(userRow.avatar.length < avatarPng.length * 0.35, `avatar should shrink (${avatarPng.length} -> ${userRow.avatar.length})`);

  // 3. Heavy 1080p 60fps MP4 -> Shorts, Post Video, Chat Video (async background queue)
  const heavyMp4 = await makeHeavyMp4(ffmpegPath, 1920, 1080, 2);
  assert.ok(heavyMp4.length > 500 * 1024, `expected heavy MP4 > 500KB, got ${heavyMp4.length}`);
  const heavyMp4DataUrl = 'data:video/mp4;base64,' + heavyMp4.toString('base64');

  const shortRes = await fetch(origin + '/api/shorts', {
    method: 'POST',
    headers,
    body: JSON.stringify({ caption: 'Heavy short', data: heavyMp4DataUrl }),
  });
  assert.equal(shortRes.status, 201);
  const shortBody = await shortRes.json();

  const postVidRes = await fetch(origin + '/api/posts', {
    method: 'POST',
    headers,
    body: JSON.stringify({ body: 'Heavy post video', media: heavyMp4DataUrl }),
  });
  assert.equal(postVidRes.status, 201);
  const postVidBody = await postVidRes.json();

  const chatVidRes = await fetch(origin + '/api/users/' + bob.user.id + '/messages', {
    method: 'POST',
    headers,
    body: JSON.stringify({ body: 'Heavy chat clip', attachment: { name: 'clip.mp4', data: heavyMp4DataUrl } }),
  });
  assert.equal(chatVidRes.status, 201);
  const chatVidBody = await chatVidRes.json();

  // Wait for background video compression queue to finish all 3 jobs.
  await app.social.mediaCompressor.drain();

  const shortRow = app.social.db.prepare('SELECT data FROM shorts WHERE id=?').get(shortBody.id);
  assert.ok(shortRow.data.length < heavyMp4.length * 0.6, `short video should compress (${heavyMp4.length} -> ${shortRow.data.length})`);
  assert.ok(mp4Duration(Buffer.from(shortRow.data)) > 0);

  const postVidRow = app.social.db.prepare('SELECT type, data FROM post_media WHERE post_id=?').get(postVidBody.id);
  assert.equal(postVidRow.type, 'video/mp4');
  assert.ok(postVidRow.data.length < heavyMp4.length * 0.6, `post video should compress (${heavyMp4.length} -> ${postVidRow.data.length})`);
  assert.ok(mp4Duration(Buffer.from(postVidRow.data)) > 0);

  const chatVidRow = app.social.db.prepare("SELECT type, data FROM chat_attachments WHERE kind='direct' AND message_id=?").get(chatVidBody.message.id);
  assert.equal(chatVidRow.type, 'video/mp4');
  assert.ok(chatVidRow.data.length < heavyMp4.length * 0.55, `chat video should compress (${heavyMp4.length} -> ${chatVidRow.data.length})`);
  assert.ok(mp4Duration(Buffer.from(chatVidRow.data)) > 0);

  // Verify compressed video is still streamable via HTTP GET.
  const streamRes = await fetch(origin + '/api/shorts/' + shortBody.id + '/video', { headers: { Cookie: alice.cookie } });
  assert.equal(streamRes.status, 200);
  const servedBytes = Buffer.from(await streamRes.arrayBuffer());
  assert.equal(servedBytes.length, shortRow.data.length);

  // 4. Synthetic/corrupt PNG falls back gracefully without failing upload.
  const fakePng = Buffer.alloc(64 * 1024);
  Buffer.from('89504e470d0a1a0a', 'hex').copy(fakePng);
  const fakeRes = await fetch(origin + '/api/posts', {
    method: 'POST',
    headers,
    body: JSON.stringify({ body: 'Fallback test', media: 'data:image/png;base64,' + fakePng.toString('base64') }),
  });
  assert.equal(fakeRes.status, 201);
  const fakeBody = await fakeRes.json();
  const fakeRow = app.social.db.prepare('SELECT type, data FROM post_media WHERE post_id=?').get(fakeBody.id);
  assert.equal(fakeRow.type, 'image/png');
  assert.deepEqual(Buffer.from(fakeRow.data), fakePng);

  const st = app.social.mediaCompressor.status();
  assert.equal(st.enabled, true);
  assert.equal(st.imagesCompressed, 4);
  assert.equal(st.videosCompressed, 3);
  assert.ok(st.bytesSaved > 0);
});
