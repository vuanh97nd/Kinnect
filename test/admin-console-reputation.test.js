import http from 'node:http';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server.js';
import { recordViolationAndDeductPoints } from '../lib/ai-violation-reporter.js';

const HOSTS = {
  admin: 'admin.kinnect.io.vn',
  support: 'hotro.kinnect.io.vn',
  operations: 'kythuat.kinnect.io.vn',
  finance: 'taichinh.kinnect.io.vn',
};
const ROOT_PASSWORD = 'reputation-root-test-only-2026!';
const STAFF_PASSWORD = 'reputation-staff-test-only-2026!';

async function setup(t) {
  const app = createApp({ authLimit: 100 });
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  const base = 'http://127.0.0.1:' + app.server.address().port;

  t.after(async () => {
    for (const socket of app.wss.clients) socket.terminate();
    app.wss.close();
    app.server.closeAllConnections();
    await new Promise(resolve => app.server.close(resolve));
    app.social.close();
  });

  async function call(path, { portal = 'admin', method = 'GET', data, cookie } = {}) {
    const host = HOSTS[portal] || portal;
    const payload = data === undefined ? null : JSON.stringify(data);
    return new Promise((resolve, reject) => {
      const req = http.request(
        base + (path.startsWith('/admin') ? path : '/api/console/' + path),
        {
          method,
          headers: {
            Host: host,
            ...(cookie ? { Cookie: cookie } : {}),
            ...(payload === null
              ? {}
              : { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }),
            ...(method === 'POST' ? { Origin: 'https://' + host } : {}),
          },
        },
        res => {
          const chunks = [];
          res.on('data', chunk => chunks.push(chunk));
          res.on('end', () => {
            const text = Buffer.concat(chunks).toString();
            resolve({
              status: res.statusCode,
              body: res.headers['content-type']?.includes('application/json')
                ? JSON.parse(text)
                : text,
              cookie: res.headers['set-cookie']?.[0]?.split(';')[0],
              headers: res.headers,
            });
          });
        }
      );
      req.on('error', reject);
      req.end(payload);
    });
  }

  async function register(username) {
    const response = await fetch(base + '/api/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username,
        password: ROOT_PASSWORD,
        name: 'Member ' + username,
        agree18: true,
        acceptPrivacyNotice: true,
        acceptTerms: true,
      }),
    });
    assert.equal(response.status, 200);
    return (await response.json()).user;
  }

  const admin = await register('rep_admin');
  const user1 = await register('rep_user1');
  const user2 = await register('rep_user2');
  app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(admin.id);

  async function login(portal, username, password = STAFF_PASSWORD) {
    return call('login', { portal, method: 'POST', data: { username, password } });
  }

  const rootLogin = await login('admin', admin.username, ROOT_PASSWORD);
  assert.equal(rootLogin.status, 200);
  const rootCookie = rootLogin.cookie;

  const staff = {};
  for (const team of ['support', 'operations', 'finance']) {
    const username = 'rep_' + team;
    const made = await call('team', {
      method: 'POST',
      cookie: rootCookie,
      data: { action: 'create', username, name: 'Nhân sự ' + team, team },
    });
    assert.equal(made.status, 200);
    const first = await login(team, username, made.body.temporaryPassword);
    assert.equal(first.status, 200);
    const changed = await call('password', {
      portal: team,
      method: 'POST',
      cookie: first.cookie,
      data: { current: made.body.temporaryPassword, password: STAFF_PASSWORD },
    });
    assert.equal(changed.status, 200);
    const next = await login(team, username);
    assert.equal(next.status, 200);
    staff[team] = { username, id: next.body.user.id, cookie: next.cookie };
  }

  return { ...app, call, login, admin, user1, user2, rootCookie, staff };
}

test('reputation overview returns tier distributions, policy comparisons, and access control', async t => {
  const a = await setup(t);

  // Admin access
  const adminRes = await a.call('reputation/overview', { portal: 'admin', cookie: a.rootCookie });
  assert.equal(adminRes.status, 200);
  assert.equal(typeof adminRes.body.tiers.excellent, 'number');
  assert(Array.isArray(adminRes.body.policy));
  assert(adminRes.body.policy.some(p => p.case.includes('Avatar') && p.new === '-3 điểm'));
  assert(adminRes.body.policy.some(p => p.case.includes('18+') && p.new === '-5 điểm'));
  assert(adminRes.body.policy.some(p => p.case.includes('body') && p.new.includes('0 điểm')));

  // Support access
  const supportRes = await a.call('reputation/overview', { portal: 'support', cookie: a.staff.support.cookie });
  assert.equal(supportRes.status, 200);

  // Operations and Finance denied
  const opsRes = await a.call('reputation/overview', { portal: 'operations', cookie: a.staff.operations.cookie });
  assert.equal(opsRes.status, 403);

  const finRes = await a.call('reputation/overview', { portal: 'finance', cookie: a.staff.finance.cookie });
  assert.equal(finRes.status, 403);
});

test('reputation dossier, deduction, and restoration with audit trail', async t => {
  const a = await setup(t);

  // Initial user reputation is 100
  const initialDossier = await a.call('reputation/user/' + a.user1.id, { portal: 'admin', cookie: a.rootCookie });
  assert.equal(initialDossier.status, 200);
  assert.equal(initialDossier.body.reputation.score, 100);
  assert.equal(initialDossier.body.reputation.tier, 'excellent');
  assert.equal(initialDossier.body.reputation.canGoLive, true);

  // Deduct 15 points
  const deduct = await a.call('reputation/adjust', {
    portal: 'support',
    cookie: a.staff.support.cookie,
    method: 'POST',
    data: {
      userId: a.user1.id,
      action: 'deduct',
      points: 15,
      reason: 'Đăng tải video có nội dung xúc phạm sau khi đã nhắc nhở',
    },
  });
  assert.equal(deduct.status, 200);
  assert.equal(deduct.body.result.remainingScore, 85);
  assert.equal(deduct.body.dossier.reputation.score, 85);
  assert.equal(deduct.body.dossier.reputation.tier, 'good');

  // Audit log has record
  const auditDeduct = a.social.db.prepare('SELECT * FROM console_audit WHERE action=? AND target=?').get('reputation-deduct', a.user1.id);
  assert(auditDeduct);
  assert.equal(auditDeduct.actor, a.staff.support.username);

  // Restore 10 points
  const restore = await a.call('reputation/adjust', {
    portal: 'admin',
    cookie: a.rootCookie,
    method: 'POST',
    data: {
      userId: a.user1.id,
      action: 'restore',
      points: 10,
      reason: 'Xác minh khiếu nại thành công, hoàn trả điểm uy tín',
    },
  });
  assert.equal(restore.status, 200);
  assert.equal(restore.body.result.remainingScore, 95);
  assert.equal(restore.body.dossier.reputation.score, 95);
  assert.equal(restore.body.dossier.reputation.tier, 'excellent');

  // Verify users list includes reputation_score
  const usersList = await a.call('users', { portal: 'admin', cookie: a.rootCookie });
  assert.equal(usersList.status, 200);
  const foundUser1 = usersList.body.users.find(u => u.id === a.user1.id);
  assert(foundUser1);
  assert.equal(foundUser1.reputation_score, 95);
});

