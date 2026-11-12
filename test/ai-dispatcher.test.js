import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { classifyTicket, findBestAssignee, dispatchTicketWithAI } from '../lib/ai-dispatcher.js';
import { createConsoleTickets } from '../lib/console-tickets.js';

function setupTestDb() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    CREATE TABLE IF NOT EXISTS console_staff(
      id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
      password TEXT NOT NULL, salt TEXT NOT NULL, suspended INTEGER NOT NULL DEFAULT 0,
      must_change INTEGER NOT NULL DEFAULT 1, created INTEGER NOT NULL, team TEXT NOT NULL DEFAULT 'support'
    );
  `);
  createConsoleTickets(db);
  return db;
}

test('AI Dispatcher: correctly classifies technical issues into operations', () => {
  const r1 = classifyTicket({
    subject: 'Lỗi văng ứng dụng khi mở camera phòng live',
    description: 'Em dùng iPhone 16 Pro bị crash văng ra ngoài khi bật camera phòng live.'
  });
  assert.equal(r1.team, 'operations');
  assert.equal(r1.priority, 'normal');

  const r2 = classifyTicket({
    subject: 'Màn hình đen và mất tiếng micro',
    description: 'Cuộc gọi thoại WebRTC bị đứng hình và micro không thu được tiếng.'
  });
  assert.equal(r2.team, 'operations');
});

test('AI Dispatcher: correctly classifies coin and package issues into finance', () => {
  const r1 = classifyTicket({
    subject: 'Đã trừ tiền ngân hàng nhưng chưa nhận được 500 xu',
    description: 'Tôi nạp qua chuyển khoản mã QR từ 10 phút trước nhưng số dư ví Kinnect vẫn 0 xu.'
  });
  assert.equal(r1.team, 'finance');

  const r2 = classifyTicket({
    subject: 'Lỗi mua gói phong cách Neon 300 xu',
    description: 'Bấm đổi gói Neon bị trừ 2 lần xu trong sổ cái ví.'
  });
  assert.equal(r2.team, 'finance');
});

test('AI Dispatcher: correctly classifies user reports & account help into support', () => {
  const r1 = classifyTicket({
    subject: 'Bị tài khoản lạ quấy rối và xúc phạm trong tin nhắn',
    description: 'Tài khoản @baduser liên tục gửi tin nhắn thô tục và đe dọa.'
  });
  assert.equal(r1.team, 'support');

  const r2 = classifyTicket({
    subject: 'Xin hỗ trợ quên mật khẩu',
    description: 'Tôi không thể đăng nhập lại nick cũ, xin cấp lại mật khẩu.'
  });
  assert.equal(r2.team, 'support');
});

test('AI Dispatcher: escalates critical safety and security issues directly to admin with urgent priority', () => {
  const r1 = classifyTicket({
    subject: 'Phát hiện nội dung CSAM an toàn trẻ em',
    description: 'Có tài khoản chia sẻ hình ảnh nguy hại trẻ vị thành niên.'
  });
  assert.equal(r1.team, 'admin');
  assert.equal(r1.priority, 'urgent');

  const r2 = classifyTicket({
    subject: 'Cảnh báo tấn công SQL injection và rò rỉ dữ liệu',
    description: 'Có IP lạ quét cổng máy chủ và khai thác lỗ hổng bảo mật.'
  });
  assert.equal(r2.team, 'admin');
  assert.equal(r2.priority, 'urgent');
});

test('AI Dispatcher: balances workload among active staff', () => {
  const db = setupTestDb();
  const now = Date.now();
  db.prepare("INSERT INTO console_staff VALUES('s1', 'tech_an', 'An Kỹ Thuật', 'pwd', 'salt', 0, 0, ?, 'operations')").run(now);
  db.prepare("INSERT INTO console_staff VALUES('s2', 'tech_binh', 'Bình Kỹ Thuật', 'pwd', 'salt', 0, 0, ?, 'operations')").run(now);

  // Both have 0 load, should pick the first one
  let best = findBestAssignee(db, 'operations');
  assert.equal(best.username, 'tech_an');

  // Give tech_an 2 open tickets
  db.prepare("INSERT INTO console_tickets VALUES('t1', 'Subj 1', 'Desc', 'normal', 'operations', '', 's1', 'open', 1, 'user', ?, ?)").run(now, now);
  db.prepare("INSERT INTO console_tickets VALUES('t2', 'Subj 2', 'Desc', 'normal', 'operations', '', 's1', 'in_progress', 1, 'user', ?, ?)").run(now, now);

  // Now tech_binh has 0 tickets, tech_an has 2 -> should assign tech_binh
  best = findBestAssignee(db, 'operations');
  assert.equal(best.username, 'tech_binh');
});

test('AI Dispatcher: dispatchTicketWithAI creates ticket, assigns staff and records immutable audit event', () => {
  const db = setupTestDb();
  const now = Date.now();
  db.prepare("INSERT INTO console_staff VALUES('f1', 'fin_hoa', 'Hoa Kế Toán', 'pwd', 'salt', 0, 0, ?, 'finance')").run(now);

  const res = dispatchTicketWithAI(db, {
    subject: 'Khiếu nại chưa nhận được xu sau khi nạp tiền',
    description: 'Tôi nạp 50.000đ để mua gói Cực quang nhưng ví chưa có xu.',
    member: 'user_123',
    reporter: 'user_123'
  });

  assert.equal(res.ticket.team, 'finance');
  assert.equal(res.ticket.assignee, 'f1');
  assert.equal(res.assignedStaff.username, 'fin_hoa');

  // Verify ticket in DB
  const saved = db.prepare('SELECT * FROM console_tickets WHERE id=?').get(res.ticket.id);
  assert.equal(saved.subject, 'Khiếu nại chưa nhận được xu sau khi nạp tiền');
  assert.equal(saved.status, 'open');

  // Verify event recorded
  const events = db.prepare('SELECT * FROM console_ticket_events WHERE ticket_id=?').all(res.ticket.id);
  assert.equal(events.length, 1);
  assert.equal(events[0].actor, 'kinnect_ai');
  assert.equal(events[0].action, 'ai_triage');
  assert.match(events[0].message, /Bộ phận tài chính/);
});
