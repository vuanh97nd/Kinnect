import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { generateKeyPairSync } from 'node:crypto';
import { createApp } from '../server.js';
import { createFirebasePush, isValidFcmToken } from '../lib/firebase-push.js';

async function startApp() {
  const app = createApp({ dbPath: ':memory:' });
  app.server.listen(0, '127.0.0.1');
  await once(app.server, 'listening');
  const url = `http://127.0.0.1:${app.server.address().port}`;
  return {
    ...app,
    url,
    async stop() {
      for (const ws of app.wss.clients) ws.terminate();
      await new Promise(r => app.wss.close(r));
      await new Promise(r => app.server.close(r));
      app.social.close();
    }
  };
}

async function apiReq(app, path, { cookie, method = 'GET', body } = {}) {
  const r = await fetch(app.url + '/api' + path, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(cookie ? { Cookie: cookie } : {})
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  return {
    status: r.status,
    body: await r.json(),
    cookie: r.headers.get('set-cookie')?.split(';')[0]
  };
}

async function register(app, username) {
  const r = await apiReq(app, '/register', {
    method: 'POST',
    body: {
      username,
      password: 'strong-fcm-test-password',
      name: username,
      agree18: true,
      acceptPrivacyNotice: true
    }
  });
  assert.equal(r.status, 200);
  return { id: r.body.user.id, cookie: r.cookie, username };
}

test('POST & DELETE /api/devices/push accepts Android FCM tokens, preserves case, and transfers token on account switch', async t => {
  const app = await startApp();
  t.after(() => app.stop());

  const u1 = await register(app, 'fcm_user_one');
  const u2 = await register(app, 'fcm_user_two');

  const fcmToken = 'fcmToken_AbC123:APA91bHun4MxP5egoKMwt2KZFBaFUH-1RYqx_ExampleValidToken12345';
  assert.equal(isValidFcmToken(fcmToken), true);

  // Register on u1
  const r1 = await apiReq(app, '/devices/push', {
    cookie: u1.cookie,
    method: 'POST',
    body: { kind: 'fcm', token: fcmToken }
  });
  assert.equal(r1.status, 200);

  // Verify stored verbatim with exact case
  const row1 = app.social.db.prepare("SELECT user_id, kind, token FROM push_devices WHERE kind='fcm'").all();
  assert.equal(row1.length, 1);
  assert.equal(row1[0].user_id, u1.id);
  assert.equal(row1[0].token, fcmToken);

  // Switch account on same device -> transfers ownership to u2
  const r2 = await apiReq(app, '/devices/push', {
    cookie: u2.cookie,
    method: 'POST',
    body: { kind: 'fcm', token: fcmToken }
  });
  assert.equal(r2.status, 200);
  const row2 = app.social.db.prepare("SELECT user_id, token FROM push_devices WHERE kind='fcm'").all();
  assert.equal(row2.length, 1);
  assert.equal(row2[0].user_id, u2.id);

  // Delete unregisters
  const r3 = await apiReq(app, '/devices/push', {
    cookie: u2.cookie,
    method: 'DELETE',
    body: { kind: 'fcm', token: fcmToken }
  });
  assert.equal(r3.status, 200);
  assert.equal(app.social.db.prepare("SELECT COUNT(*) AS n FROM push_devices WHERE kind='fcm'").get().n, 0);
});

test('createFirebasePush signs RS256 OAuth2 JWT, sends FCM HTTP v1 notification, and prunes UNREGISTERED tokens', async t => {
  const app = await startApp();
  t.after(() => app.stop());

  const u1 = await register(app, 'fcm_target_user');
  const validToken = 'dValidAndroidToken:APA91bExample1234567890_ValidTokenValueABCDEF';
  const deadToken = 'dDeadAndroidToken:APA91bExample1234567890_UnregisteredTokenXYZ';

  app.social.db.prepare('INSERT INTO push_devices(user_id, kind, token, updated) VALUES(?,?,?,?)').run(u1.id, 'fcm', validToken, Date.now());
  app.social.db.prepare('INSERT INTO push_devices(user_id, kind, token, updated) VALUES(?,?,?,?)').run(u1.id, 'fcm', deadToken, Date.now());

  const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();

  let oauthCalls = 0;
  const fcmCalls = [];

  const fcm = createFirebasePush({
    social: app.social,
    env: {
      FCM_ENABLED: 'true',
      FCM_PROJECT_ID: 'kinnect-android-prod',
      FCM_CLIENT_EMAIL: 'firebase-adminsdk@kinnect-android-prod.iam.gserviceaccount.com',
      FCM_PRIVATE_KEY: pem
    },
    fetchImpl: async (url, opts) => {
      if (String(url).includes('oauth2.googleapis.com/token')) {
        oauthCalls++;
        assert.match(String(opts.body), /grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer/);
        return Response.json({ access_token: 'mock-google-oauth-token', expires_in: 3600 });
      }
      if (String(url).includes('fcm.googleapis.com/v1/projects/kinnect-android-prod/messages:send')) {
        assert.equal(opts.headers.Authorization, 'Bearer mock-google-oauth-token');
        const payload = JSON.parse(opts.body);
        fcmCalls.push(payload.message);
        if (payload.message.token === deadToken) {
          return Response.json(
            { error: { code: 404, status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } },
            { status: 404 }
          );
        }
        return Response.json({ name: 'projects/kinnect-android-prod/messages/0:12345' });
      }
      throw new Error('Unexpected fetch URL: ' + url);
    }
  });

  assert.equal(fcm.enabled(), true);
  assert.equal(fcm.has(u1.id), true);

  const results = await fcm.notifyTest(u1.id);
  assert.equal(oauthCalls, 1);
  assert.equal(fcmCalls.length, 2);
  assert.equal(results.filter(r => r.ok).length, 1);

  // Dead UNREGISTERED token must be automatically pruned from SQLite push_devices
  const remaining = app.social.db.prepare("SELECT token FROM push_devices WHERE user_id=? AND kind='fcm'").all(u1.id);
  assert.equal(remaining.length, 1);
  assert.equal(remaining[0].token, validToken);

  // Second call reuses cached OAuth2 access token (oauthCalls stays 1)
  await fcm.deliver(u1.id, { title: 'Test 2', body: 'Hello Android', data: { type: 'notification', kind: 'message' } });
  assert.equal(oauthCalls, 1);
});
