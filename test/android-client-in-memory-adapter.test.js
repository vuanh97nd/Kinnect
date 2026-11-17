import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server.js';

/**
 * CONTRACT / ADAPTER test (Node HTTP client transport adapter against isolated createApp(':memory:')).
 * NOT full Android NativeApi runtime transport; Android emulator-to-local loopback requires a debug origin
 * override + `adb reverse` setup. Zero production DB/accounts or live SMTP touched.
 */
test('CONTRACT/ADAPTER: dmMode allowed/blocked parties, session revocation, and password change invalidation', async () => {
  const app = createApp({ authLimit: 200 });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const base = 'http://127.0.0.1:' + app.server.address().port;

  const req = async (cookie, path, method = 'GET', data = undefined) => {
    const res = await fetch(base + '/api' + path, {
      method,
      headers: {
        ...(cookie ? { cookie } : {}),
        ...(!['GET', 'HEAD'].includes(method) ? { 'content-type': 'application/json' } : {})
      },
      body: data !== undefined ? JSON.stringify(data) : undefined
    });
    const setCookie = res.headers.get('set-cookie')?.split(';')[0] || null;
    let body = null;
    try { body = await res.json(); } catch {}
    return { status: res.status, body, cookie: setCookie };
  };

  try {
    // 1. Disposable in-memory accounts
    const userA = await req(null, '/register', 'POST', {
      username: 'qa_adapter_a', name: 'QA A', password: 'password123', agree18: true, acceptPrivacyNotice: true
    });
    const userB = await req(null, '/register', 'POST', {
      username: 'qa_adapter_b', name: 'QA B', password: 'password123', agree18: true, acceptPrivacyNotice: true
    });
    assert.equal(userA.status, 200);
    assert.equal(userB.status, 200);
    const aid = userA.body.user.id;
    const bid = userB.body.user.id;

    // 2. dmMode: friends blocks non-friend DM (403), allows after friend accept (201)
    assert.equal((await req(userB.cookie, '/me', 'PATCH', { dmMode: 'friends' })).status, 200);
    assert.equal((await req(userB.cookie, '/me')).body.user.dmMode, 'friends');
    assert.equal((await req(userA.cookie, `/users/${bid}/messages`, 'POST', { body: 'blocked_non_friend' })).status, 403);

    assert.ok([200, 201].includes((await req(userA.cookie, `/users/${bid}/friend-request`, 'POST', {})).status));
    assert.equal((await req(userB.cookie, `/users/${aid}/friend-request/respond`, 'POST', { action: 'accept' })).status, 200);
    assert.equal((await req(userA.cookie, `/users/${bid}/messages`, 'POST', { body: 'allowed_friend' })).status, 201);

    // Toggle back to everyone and verify persistence on fresh GET /api/me
    assert.equal((await req(userB.cookie, '/me', 'PATCH', { dmMode: 'everyone' })).status, 200);
    assert.equal((await req(userB.cookie, '/me')).body.user.dmMode, 'everyone');

    // 3. Session revocation: second login creates revocable other session; current session protected (400)
    const userAOther = await req(null, '/login', 'POST', { username: 'qa_adapter_a', password: 'password123' });
    assert.equal(userAOther.status, 200);
    const sessionsRes = await req(userA.cookie, '/me/sessions');
    assert.equal(sessionsRes.status, 200);
    assert.equal(sessionsRes.body.sessions.length, 2);
    const currentSess = sessionsRes.body.sessions.find((s) => s.current);
    const otherSess = sessionsRes.body.sessions.find((s) => !s.current);
    assert.ok(currentSess && otherSess);
    assert.equal((await req(userA.cookie, `/me/sessions/${currentSess.id}`, 'DELETE')).status, 400);
    assert.equal((await req(userB.cookie, `/me/sessions/${otherSess.id}`, 'DELETE')).status, 404);
    assert.equal((await req(userA.cookie, `/me/sessions/${otherSess.id}`, 'DELETE')).status, 200);
    assert.equal((await req(userAOther.cookie, '/me')).status, 401);
    assert.equal((await req(userA.cookie, '/me')).status, 200);

    // 4. Password change (/api/me/password {current, next}): invalidates old password & other sessions
    const userASecond = await req(null, '/login', 'POST', { username: 'qa_adapter_a', password: 'password123' });
    assert.equal(userASecond.status, 200);
    const chg = await req(userA.cookie, '/me/password', 'POST', { current: 'password123', next: 'newpass456' });
    assert.equal(chg.status, 200);
    assert.equal((await req(null, '/login', 'POST', { username: 'qa_adapter_a', password: 'password123' })).status, 401);
    assert.equal((await req(null, '/login', 'POST', { username: 'qa_adapter_a', password: 'newpass456' })).status, 200);
    assert.equal((await req(userASecond.cookie, '/me')).status, 401);
  } finally {
    for (const ws of app.wss.clients) ws.terminate();
    app.wss.close();
    app.server.closeAllConnections();
    await new Promise((r) => app.server.close(r));
    app.social.close();
  }
});
