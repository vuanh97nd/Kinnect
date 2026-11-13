import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server.js';

async function fixture(t) {
  const app = createApp({ dbPath: ':memory:', allowEmailDelivery: false, authLimit: 500 });
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    for (const ws of app.wss.clients) ws.terminate();
    await new Promise(resolve => app.wss.close(resolve));
    app.server.closeAllConnections();
    await new Promise(resolve => app.server.close(resolve));
    app.social.close();
  });
  const origin = `http://127.0.0.1:${app.server.address().port}`;
  async function request(path, { cookie, method = 'GET', body } = {}) {
    const response = await fetch(origin + path, { method,
      headers: { Origin: origin, ...(cookie ? { Cookie: cookie } : {}),
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, body: await response.json(), cookie: response.headers.get('set-cookie')?.split(';')[0] };
  }
  async function register(username, role = 'member') {
    const result = await request('/api/register', { method: 'POST', body: {
      username, name: username, password: 'local-test-password', agree18: true, acceptPrivacyNotice: true,
    } });
    assert.equal(result.status, 200);
    if (role === 'admin') app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(result.body.user.id);
    return { ...result.body.user, cookie: result.cookie };
  }
  async function resetRequest(username) {
    const response = await request('/api/password-reset', { method: 'POST', body: {
      username, contact: 'local-only@example.invalid', note: 'isolated native admin contract',
    } });
    assert.equal(response.status, 200);
  }
  return { app, request, register, resetRequest };
}

test('native admin operations: overview/reset/activity role gates and payloads', async t => {
  const { request, register, resetRequest } = await fixture(t);
  const admin = await register('ops_admin', 'admin'), member = await register('ops_member');
  await resetRequest(member.username);
  for (const path of ['/api/admin/overview', '/api/admin/activity', '/api/admin/password-resets']) {
    assert.equal((await request(path)).status, 401);
    assert.equal((await request(path, { cookie: member.cookie })).status, 403);
  }
  const overview = await request('/api/admin/overview', { cookie: admin.cookie });
  assert.equal(overview.status, 200);
  assert.equal(overview.body.users, 2);
  assert.equal(overview.body.pendingResets, 1);
  assert.equal(overview.body.suspended, 0);
  assert.equal(overview.body.openReports, 0);
  const list = await request('/api/admin/password-resets', { cookie: admin.cookie });
  assert.equal(list.status, 200);
  assert.equal(list.body.requests[0].username, member.username);
  assert.equal(list.body.requests[0].user_id, member.id);
  assert.equal(list.body.requests[0].status, 'open');
  assert.equal('temporaryPassword' in list.body.requests[0], false);
  const activity = await request('/api/admin/activity', { cookie: admin.cookie });
  assert.equal(activity.status, 200);
  assert.deepEqual(activity.body.entries, []);
});

test('native admin reset: revokes target sessions, changes password and records audit', async t => {
  const { request, register, resetRequest } = await fixture(t);
  const admin = await register('reset_admin', 'admin'), target = await register('reset_target');
  await resetRequest(target.username);
  const list = await request('/api/admin/password-resets', { cookie: admin.cookie });
  const id = list.body.requests[0].id;
  const path = `/api/admin/password-resets/${id}/reset`;
  assert.equal((await request(path, { cookie: target.cookie, method: 'POST', body: {} })).status, 403);
  const done = await request(path, { cookie: admin.cookie, method: 'POST', body: {} });
  assert.equal(done.status, 200);
  assert.equal(done.body.ok, true);
  assert.equal(done.body.username, target.username);
  assert.equal(typeof done.body.temporaryPassword, 'string');
  assert.equal(done.body.temporaryPassword.length, 10);
  assert.equal((await request('/api/me', { cookie: target.cookie })).status, 401);
  assert.equal((await request('/api/login', { method: 'POST', body: {
    username: target.username, password: 'local-test-password',
  } })).status, 401);
  assert.equal((await request('/api/login', { method: 'POST', body: {
    username: target.username, password: done.body.temporaryPassword,
  } })).status, 200);
  const after = await request('/api/admin/password-resets', { cookie: admin.cookie });
  assert.equal(after.body.requests[0].status, 'done');
  assert.equal('temporaryPassword' in after.body.requests[0], false);
  const activity = await request('/api/admin/activity', { cookie: admin.cookie });
  assert.equal(activity.body.entries[0].action, `reset-password:${admin.id}`);
  assert.equal(activity.body.entries[0].actorUsername, admin.username);
  assert.equal(activity.body.entries[0].target, target.id);
});

test('native admin dismiss: unknown account request can be dismissed without password mutation', async t => {
  const { app, request, register, resetRequest } = await fixture(t);
  const admin = await register('dismiss_admin', 'admin');
  await resetRequest('missing_target');
  const list = await request('/api/admin/password-resets', { cookie: admin.cookie });
  const id = list.body.requests[0].id;
  assert.equal(list.body.requests[0].user_id, null);
  assert.equal((await request(`/api/admin/password-resets/${id}/reset`, { cookie: admin.cookie, method: 'POST', body: {} })).status, 404);
  const before = app.social.db.prepare('SELECT password FROM users WHERE id=?').get(admin.id).password;
  const dismissed = await request(`/api/admin/password-resets/${id}/dismiss`, { cookie: admin.cookie, method: 'POST', body: {} });
  assert.equal(dismissed.status, 200);
  assert.equal(dismissed.body.ok, true);
  const after = await request('/api/admin/password-resets', { cookie: admin.cookie });
  assert.equal(after.body.requests[0].status, 'dismissed');
  assert.equal(app.social.db.prepare('SELECT password FROM users WHERE id=?').get(admin.id).password, before);
});
