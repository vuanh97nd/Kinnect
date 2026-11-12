import http from 'node:http';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server.js';

const HOSTS = {
  admin: 'admin.kinnect.io.vn',
  support: 'hotro.kinnect.io.vn',
  operations: 'kythuat.kinnect.io.vn',
  finance: 'taichinh.kinnect.io.vn'
};
const ROOT_PASSWORD = 'messaging-root-test-2026!';
const STAFF_PASSWORD = 'messaging-staff-test-2026!';

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
    const host = HOSTS[portal];
    const payload = data === undefined ? null : JSON.stringify(data);
    return new Promise((resolve, reject) => {
      const req = http.request(base + '/api/console/' + path, {
        method,
        headers: {
          Host: host,
          ...(cookie ? { Cookie: cookie } : {}),
          ...(payload === null ? {} : { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }),
          ...(method === 'POST' ? { Origin: 'https://' + host } : {})
        }
      }, res => {
        const chunks = [];
        res.on('data', chunk => chunks.push(chunk));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString();
          resolve({
            status: res.statusCode,
            body: text ? JSON.parse(text) : {},
            cookie: res.headers['set-cookie']?.[0]?.split(';')[0]
          });
        });
      });
      req.on('error', reject);
      req.end(payload);
    });
  }

  async function register(username) {
    const res = await fetch(base + '/api/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username,
        password: ROOT_PASSWORD,
        name: username,
        agree18: true,
        acceptPrivacyNotice: true,
        acceptTerms: true
      })
    });
    assert.equal(res.status, 200);
    return (await res.json()).user;
  }

  const admin = await register('msg_admin');
  app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(admin.id);

  async function login(portal, username, password = STAFF_PASSWORD) {
    return call('login', { portal, method: 'POST', data: { username, password } });
  }

  const rootCookie = (await login('admin', admin.username, ROOT_PASSWORD)).cookie;
  assert(rootCookie);

  const staff = {};
  for (const team of ['support', 'operations', 'finance']) {
    const username = 'msg_' + team;
    const made = await call('team', {
      method: 'POST',
      cookie: rootCookie,
      data: { action: 'create', username, name: 'Nhân viên ' + team, team }
    });
    assert.equal(made.status, 200);

    const first = await login(team, username, made.body.temporaryPassword);
    assert.equal(first.status, 200);
    const changed = await call('password', {
      portal: team,
      method: 'POST',
      cookie: first.cookie,
      data: { current: made.body.temporaryPassword, password: STAFF_PASSWORD }
    });
    assert.equal(changed.status, 200);

    const next = await login(team, username);
    assert.equal(next.status, 200);
    staff[team] = { username, id: next.body.user.id, cookie: next.cookie };
  }

  return { ...app, call, login, admin, rootCookie, staff };
}

test('inter-department messaging and AI assistant endpoints operate with full isolation', async t => {
  const env = await setup(t);

  // 1. Support sends an announcement to 'all' channel
  const postAll = await env.call('messages', {
    portal: 'support',
    method: 'POST',
    cookie: env.staff.support.cookie,
    data: { channel: 'all', content: 'Thông báo: Có lượng lớn yêu cầu nạp xu MoMo cần đối soát.' }
  });
  assert.equal(postAll.status, 201);
  assert.equal(postAll.body.ok, true);
  assert.equal(postAll.body.message.sender_team, 'support');

  // 2. Finance reads 'all' channel and receives the message
  const getFinance = await env.call('messages?channel=all', {
    portal: 'finance',
    cookie: env.staff.finance.cookie
  });
  assert.equal(getFinance.status, 200);
  assert.equal(getFinance.body.messages.length, 1);
  assert.match(getFinance.body.messages[0].content, /lượng lớn yêu cầu nạp xu/);

  // 3. Support and Finance can exchange in 'support-finance' channel
  const postSupFin = await env.call('messages', {
    portal: 'finance',
    method: 'POST',
    cookie: env.staff.finance.cookie,
    data: { channel: 'support-finance', content: 'Đã nhận thông tin, đang đối soát 5 giao dịch MoMo.' }
  });
  assert.equal(postSupFin.status, 201);

  // 4. Operations cannot access 'support-finance' channel (denied)
  const getOpDenied = await env.call('messages?channel=support-finance', {
    portal: 'operations',
    cookie: env.staff.operations.cookie
  });
  assert.equal(getOpDenied.status, 403);

  // 5. AI Analyze endpoint
  const aiAnalysis = await env.call('ai/analyze', {
    portal: 'support',
    method: 'POST',
    cookie: env.staff.support.cookie,
    data: {
      subject: 'Lỗi nạp xu MoMo thành công nhưng chưa nhận được coin',
      description: 'Tôi vừa chuyển khoản 50k qua MoMo lúc 15h mà ví vẫn 0 xu.',
      member: 'user123'
    }
  });
  assert.equal(aiAnalysis.status, 200);
  assert.equal(aiAnalysis.body.analysis.suggestedTeam, 'finance');
  assert.ok(aiAnalysis.body.analysis.autoResponse);

  // 6. AI Smart Reply endpoint
  const aiReply = await env.call('ai/smart-reply', {
    portal: 'finance',
    method: 'POST',
    cookie: env.staff.finance.cookie,
    data: { type: 'coin_compensated', member: 'user123' }
  });
  assert.equal(aiReply.status, 200);
  assert.match(aiReply.body.reply, /bù đúng số xu/);
});

