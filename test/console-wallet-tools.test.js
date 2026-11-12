import http from 'node:http';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../server.js';
import { createWallet } from '../lib/wallet.js';

const HOSTS = {
  admin: 'admin.kinnect.io.vn',
  support: 'hotro.kinnect.io.vn',
  operations: 'kythuat.kinnect.io.vn',
  finance: 'taichinh.kinnect.io.vn',
};
const ROOT_PASSWORD = 'wallet-root-test-only-2026!';
const STAFF_PASSWORD = 'wallet-staff-test-only-2026!';

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
        name: 'User ' + username,
        agree18: true,
        acceptPrivacyNotice: true,
        acceptTerms: true,
      }),
    });
    assert.equal(response.status, 200);
    return (await response.json()).user;
  }

  const admin = await register('wallet_admin');
  const user1 = await register('wallet_user1');
  const user2 = await register('wallet_user2');
  app.social.db.prepare("UPDATE users SET role='admin' WHERE id=?").run(admin.id);

  async function login(portal, username, password = STAFF_PASSWORD) {
    return call('login', { portal, method: 'POST', data: { username, password } });
  }

  const rootLogin = await login('admin', admin.username, ROOT_PASSWORD);
  assert.equal(rootLogin.status, 200);
  const rootCookie = rootLogin.cookie;

  const staff = {};
  for (const team of ['support', 'operations', 'finance']) {
    const username = 'wallet_' + team;
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

  const wallet = createWallet({ db: app.social.db });

  return { ...app, call, login, admin, user1, user2, rootCookie, staff, wallet };
}

test('wallet-tools static assets are served securely with correct content-types', async t => {
  const a = await setup(t);
  const js = await a.call('/admin/wallet-tools.js', { portal: 'admin' });
  assert.equal(js.status, 200);
  assert.match(js.headers['content-type'], /javascript/);
  assert.match(js.body, /renderWalletTools/);

  const css = await a.call('/admin/wallet-tools.css', { portal: 'admin' });
  assert.equal(css.status, 200);
  assert.match(css.headers['content-type'], /text\/css/);
  assert.match(css.body, /\.wallet-tools/);
});

test('role and permission matrix: admin and finance access, support and operations denied', async t => {
  const a = await setup(t);

  // Admin has access
  const adminList = await a.call('wallet-tools', { portal: 'admin', cookie: a.rootCookie });
  assert.equal(adminList.status, 200);
  assert.equal(adminList.body.canApprove, true);

  // Finance has access
  const financeList = await a.call('wallet-tools', { portal: 'finance', cookie: a.staff.finance.cookie });
  assert.equal(financeList.status, 200);
  assert.equal(financeList.body.canApprove, false);

  // Support denied
  const supportList = await a.call('wallet-tools', { portal: 'support', cookie: a.staff.support.cookie });
  assert.equal(supportList.status, 403);

  // Operations denied
  const opsList = await a.call('wallet-tools', { portal: 'operations', cookie: a.staff.operations.cookie });
  assert.equal(opsList.status, 403);

  // Finance cannot create promotional gift
  const financeGift = await a.call('wallet-tools/preview', {
    portal: 'finance',
    cookie: a.staff.finance.cookie,
    method: 'POST',
    data: {
      kind: 'gift',
      title: 'Quà khuyến mại',
      coins: 100,
      all: false,
      userIds: [a.user1.id],
      reason: 'Lý do tặng quà cho thành viên',
    },
  });
  assert.equal(financeGift.status, 403);

  // Finance cannot confirm or reject
  const financeConfirm = await a.call('wallet-tools/confirm', {
    portal: 'finance',
    cookie: a.staff.finance.cookie,
    method: 'POST',
    data: { id: 'dummy-id' },
  });
  assert.equal(financeConfirm.status, 403);

  const financeReject = await a.call('wallet-tools/reject', {
    portal: 'finance',
    cookie: a.staff.finance.cookie,
    method: 'POST',
    data: { id: 'dummy-id', reason: 'Không đồng ý' },
  });
  assert.equal(financeReject.status, 403);
});

test('promotional coin gift: admin creates preview, approves, idempotent, no money deposit booked', async t => {
  const a = await setup(t);

  const initialPurchased = a.wallet.purchasedBalance(a.user1.id);
  const initialTrial = a.wallet.trialBalance(a.user1.id);

  // Preview promo gift
  const preview = await a.call('wallet-tools/preview', {
    portal: 'admin',
    cookie: a.rootCookie,
    method: 'POST',
    data: {
      kind: 'gift',
      title: 'Quà tặng chào mừng',
      coins: 500,
      all: false,
      userIds: [a.user1.id],
      reason: 'Tặng xu trải nghiệm sự kiện chào đón thành viên mới',
    },
  });
  assert.equal(preview.status, 200);
  const opId = preview.body.operation.id;
  assert(opId);
  assert.equal(preview.body.operation.state, 'pending');
  assert.equal(preview.body.operation.totalCoins, 500);

  // Coins not yet added in preview
  assert.equal(a.wallet.trialBalance(a.user1.id), initialTrial);

  // Admin confirms gift
  const confirm = await a.call('wallet-tools/confirm', {
    portal: 'admin',
    cookie: a.rootCookie,
    method: 'POST',
    data: { id: opId },
  });
  assert.equal(confirm.status, 200);
  assert.equal(confirm.body.duplicate, false);
  assert.equal(confirm.body.operation.state, 'done');

  // Trial balance increased by 500
  assert.equal(a.wallet.trialBalance(a.user1.id), initialTrial + 500);
  // Purchased balance unchanged (not recorded as purchased coins!)
  assert.equal(a.wallet.purchasedBalance(a.user1.id), initialPurchased);

  // Ledger entry verify net_vnd is 0
  const entry = a.social.db.prepare('SELECT * FROM wallet_entries WHERE reference=?').get('console-gift:' + opId);
  assert(entry);
  assert.equal(entry.kind, 'admin_trial');
  assert.equal(entry.net_vnd, 0);
  assert.equal(entry.creator_vnd, 0);
  assert.equal(entry.platform_vnd, 0);
  assert.equal(entry.coins, 500);

  // Confirming again returns duplicate: true, does not double add
  const retryConfirm = await a.call('wallet-tools/confirm', {
    portal: 'admin',
    cookie: a.rootCookie,
    method: 'POST',
    data: { id: opId },
  });
  assert.equal(retryConfirm.status, 200);
  assert.equal(retryConfirm.body.duplicate, true);
  assert.equal(a.wallet.trialBalance(a.user1.id), initialTrial + 500);

  // Audit log has records
  const audits = a.social.db.prepare('SELECT * FROM console_audit WHERE target=?').all(opId);
  assert(audits.some(x => x.action === 'wallet-preview:gift'));
  assert(audits.some(x => x.action === 'wallet-confirm'));
});

test('paid correction workflow: finance proposes, admin approves, deduplicated against prior tx', async t => {
  const a = await setup(t);

  const initialPurchased = a.wallet.purchasedBalance(a.user2.id);
  const txRef = 'bank-tx-20261109-001';

  // Finance drafts proposal
  const draft = await a.call('wallet-tools/preview', {
    portal: 'finance',
    cookie: a.staff.finance.cookie,
    method: 'POST',
    data: {
      kind: 'paid_correction',
      title: 'Bù xu giao dịch chuyển khoản lỗi',
      coins: 1000,
      all: false,
      userIds: [a.user2.id],
      reference: txRef,
      reason: 'Khách chuyển khoản đúng nội dung nhưng cổng thanh toán bị timeout',
    },
  });
  assert.equal(draft.status, 200);
  const opId = draft.body.operation.id;
  assert.equal(draft.body.operation.reference, txRef);

  // Cannot create second proposal for the same reference while first is pending
  const dupDraft = await a.call('wallet-tools/preview', {
    portal: 'finance',
    cookie: a.staff.finance.cookie,
    method: 'POST',
    data: {
      kind: 'paid_correction',
      title: 'Đề nghị trùng',
      coins: 1000,
      all: false,
      userIds: [a.user2.id],
      reference: txRef,
      reason: 'Thử gửi trùng mã giao dịch xem có bị chặn không',
    },
  });
  assert.equal(dupDraft.status, 409);

  // Admin confirms the correction
  const confirm = await a.call('wallet-tools/confirm', {
    portal: 'admin',
    cookie: a.rootCookie,
    method: 'POST',
    data: { id: opId },
  });
  assert.equal(confirm.status, 200);
  assert.equal(confirm.body.duplicate, false);

  // Purchased balance increased (counts as purchased coins for the customer)
  assert.equal(a.wallet.purchasedBalance(a.user2.id), initialPurchased + 1000);

  // But net_vnd is 0 (does not inflate recorded payment revenue)
  const entry = a.social.db.prepare('SELECT * FROM wallet_entries WHERE reference=?').get('console-paid:' + txRef);
  assert(entry);
  assert.equal(entry.kind, 'coin_purchase');
  assert.equal(entry.net_vnd, 0);

  // Attempting to propose the same reference even after completion is blocked
  const postDraft = await a.call('wallet-tools/preview', {
    portal: 'finance',
    cookie: a.staff.finance.cookie,
    method: 'POST',
    data: {
      kind: 'paid_correction',
      title: 'Đề nghị sau hoàn tất',
      coins: 500,
      all: false,
      userIds: [a.user2.id],
      reference: txRef,
      reason: 'Cố tình lập lại mã đã duyệt',
    },
  });
  assert.equal(postDraft.status, 409);

  // Re-confirm is idempotent
  const repeatConfirm = await a.call('wallet-tools/confirm', {
    portal: 'admin',
    cookie: a.rootCookie,
    method: 'POST',
    data: { id: opId },
  });
  assert.equal(repeatConfirm.status, 200);
  assert.equal(repeatConfirm.body.duplicate, true);
  assert.equal(a.wallet.purchasedBalance(a.user2.id), initialPurchased + 1000);
});

test('paid correction rejection: admin rejects with reason, state immutable', async t => {
  const a = await setup(t);

  const txRef = 'bank-tx-reject-002';
  const draft = await a.call('wallet-tools/preview', {
    portal: 'finance',
    cookie: a.staff.finance.cookie,
    method: 'POST',
    data: {
      kind: 'paid_correction',
      title: 'Đề nghị bù nghi vấn',
      coins: 2000,
      all: false,
      userIds: [a.user1.id],
      reference: txRef,
      reason: 'Khách khiếu nại nhưng sao kê ngân hàng chưa khớp tiền về',
    },
  });
  assert.equal(draft.status, 200);
  const opId = draft.body.operation.id;

  // Admin rejects
  const rejected = await a.call('wallet-tools/reject', {
    portal: 'admin',
    cookie: a.rootCookie,
    method: 'POST',
    data: { id: opId, reason: 'Chưa thấy tiền vào tài khoản công ty' },
  });
  assert.equal(rejected.status, 200);
  assert.equal(rejected.body.operation.state, 'rejected');
  assert.equal(rejected.body.operation.rejectionReason, 'Chưa thấy tiền vào tài khoản công ty');

  // Cannot confirm rejected operation
  const tryConfirm = await a.call('wallet-tools/confirm', {
    portal: 'admin',
    cookie: a.rootCookie,
    method: 'POST',
    data: { id: opId },
  });
  assert.equal(tryConfirm.status, 409);
});
