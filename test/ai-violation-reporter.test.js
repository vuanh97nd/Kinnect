import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import {
  ensureViolationAndReputationTables,
  getReputationInfo,
  deductReputation,
  restoreReputation,
  analyzeAccountViolation,
  recordViolationAndDeductPoints,
  evaluateImageContentPolicy,
  moderateAvatarUpload,
  moderateVideoUpload,
  getAccountViolationDossier
} from '../lib/ai-violation-reporter.js';

function setupTestDb() {
  const db = new DatabaseSync(':memory:');
  db.exec(`
    CREATE TABLE users(
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      salt TEXT NOT NULL,
      name TEXT NOT NULL,
      bio TEXT NOT NULL DEFAULT '',
      interests TEXT NOT NULL DEFAULT '[]',
      birth_date TEXT NOT NULL,
      discoverable INTEGER NOT NULL DEFAULT 1,
      dm_mode TEXT NOT NULL DEFAULT 'everyone',
      avatar BLOB,
      avatar_type TEXT,
      avatar_updated_at INTEGER,
      suspended INTEGER NOT NULL DEFAULT 0,
      created INTEGER NOT NULL
    );
    CREATE TABLE sessions(token TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), expires INTEGER NOT NULL);
    CREATE TABLE shorts(id TEXT PRIMARY KEY, user_id TEXT NOT NULL, caption TEXT, hidden INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
    CREATE TABLE posts(id TEXT PRIMARY KEY, user_id TEXT NOT NULL, body TEXT, hidden INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
  `);
  ensureViolationAndReputationTables(db);
  return db;
}

test('Reputation System: starts with 100 points, correctly classifies tiers', () => {
  const db = setupTestDb();
  const now = Date.now();
  db.prepare("INSERT INTO users(id, username, password, salt, name, birth_date, created) VALUES('u1', 'user_good', 'pwd', 'salt', 'Người Dùng Tốt', '2000-01-01', ?)").run(now);

  const rep = getReputationInfo(db, 'u1');
  assert.equal(rep.score, 100);
  assert.equal(rep.tier, 'excellent');
  assert.equal(rep.canGoLive, true);
  assert.equal(rep.canPost, true);
  assert.equal(rep.isSuspended, false);
});

test('Reputation System: deducts points, records log, updates tier', () => {
  const db = setupTestDb();
  const now = Date.now();
  db.prepare("INSERT INTO users(id, username, password, salt, name, birth_date, created) VALUES('u2', 'user_warned', 'pwd', 'salt', 'Cảnh Báo', '2000-01-01', ?)").run(now);

  const r1 = deductReputation(db, {
    userId: 'u2',
    points: 15,
    reason: 'Ảnh đại diện phản cảm lần 1'
  });
  assert.equal(r1.previousScore, 100);
  assert.equal(r1.deductedPoints, 15);
  assert.equal(r1.remainingScore, 85);

  const repAfter = getReputationInfo(db, 'u2');
  assert.equal(repAfter.score, 85);
  assert.equal(repAfter.tier, 'good');

  // Deduct further down to warning tier (60 points)
  deductReputation(db, { userId: 'u2', points: 25, reason: 'Video đăng tải có dấu hiệu bạo lực' });
  const repWarn = getReputationInfo(db, 'u2');
  assert.equal(repWarn.score, 60);
  assert.equal(repWarn.tier, 'warning');
});

test('Reputation System: auto-suspends account if score drops below 30', () => {
  const db = setupTestDb();
  const now = Date.now();
  db.prepare("INSERT INTO users(id, username, password, salt, name, birth_date, created) VALUES('u3', 'user_bad', 'pwd', 'salt', 'Xấu Tính', '2000-01-01', ?)").run(now);
  db.prepare("INSERT INTO sessions VALUES('token123', 'u3', ?)").run(now + 86400000);

  // Heavy deduction: -75 points
  const r = deductReputation(db, {
    userId: 'u3',
    points: 75,
    reason: 'Lừa đảo nạp xu nghiêm trọng'
  });
  assert.equal(r.remainingScore, 25);
  assert.equal(r.suspended, true);

  // Verify DB state
  const u = db.prepare('SELECT suspended, reputation_score FROM users WHERE id=?').get('u3');
  assert.equal(u.suspended, 1);
  assert.equal(u.reputation_score, 25);

  // Verify sessions wiped
  const s = db.prepare('SELECT COUNT(*) n FROM sessions WHERE user_id=?').get('u3');
  assert.equal(s.n, 0);
});

test('AI Violation Analysis: clearly extracts reason, evidence and severity', () => {
  const v = analyzeAccountViolation({
    content: 'Tao sẽ chém chết cả nhà mày đồ con hoang',
    targetType: 'post',
    targetId: 'p1',
    userId: 'u1',
    username: 'killer'
  });

  assert.equal(v.violationType, 'violence');
  assert.equal(v.severity, 'critical');
  assert.equal(v.penaltyPoints, 25);
  assert.match(v.aiReason, /đe dọa bạo lực thể xác/);
  assert.match(v.aiEvidence, /chém chết/);
});

test('Image Moderation Policy: body showcase / gym / bikini is allowed, sensitive is penalized, private is never banned', () => {
  // 1. Ảnh khoe body / gym / bikini: Cho phép
  const p1 = evaluateImageContentPolicy({
    caption: 'Hôm nay đi tập gym khoe body sáu múi săn chắc!',
    aiResult: { decision: 'allow' }
  });
  assert.equal(p1.allowed, true);
  assert.equal(p1.isViolation, false);

  const p2 = evaluateImageContentPolicy({
    caption: 'Tắm biển diện bikini khoe dáng mùa hè',
    aiResult: { decision: 'review', reason: 'hở hang' } // AI hiểu nhầm nhưng vì là bikini nên được phép
  });
  assert.equal(p2.allowed, true);
  assert.equal(p2.isViolation, false);

  // 2. Ảnh riêng tư: Tuyệt đối không cấm
  const pPrivate = evaluateImageContentPolicy({
    isPrivate: true,
    caption: 'Ảnh riêng tư trong tin nhắn'
  });
  assert.equal(pPrivate.allowed, true);
  assert.equal(pPrivate.isViolation, false);
  assert.equal(pPrivate.isPrivate, true);

  // 3. Ảnh nhạy cảm thực sự: Bị gắn cờ vi phạm
  const pSensitive = evaluateImageContentPolicy({
    caption: 'Lộ clip sex khiêu dâm lộ vùng kín',
    aiResult: { decision: 'review', reason: 'Nội dung khiêu dâm 18+' }
  });
  assert.equal(pSensitive.allowed, false);
  assert.equal(pSensitive.isViolation, true);
});

test('Avatar Moderation: rejects violating avatar, deducts mild points and resets avatar', () => {
  const db = setupTestDb();
  const now = Date.now();
  const dummyAvatar = Buffer.from('fake_image_data');
  db.prepare("INSERT INTO users(id, username, password, salt, name, birth_date, avatar, avatar_type, created) VALUES('u4', 'user_avatar', 'pwd', 'salt', 'Avatar Test', '2000-01-01', ?, 'image/jpeg', ?)").run(dummyAvatar, now);

  // Thử ảnh khoe body làm avatar -> Được duyệt!
  const resGym = moderateAvatarUpload(db, {
    userId: 'u4',
    mimeType: 'image/jpeg',
    imageBase64: 'dummy',
    caption: 'Ảnh tập gym khoe body'
  });
  assert.equal(resGym.approved, true);

  // Thử ảnh nhạy cảm 18+ thực sự -> Bị từ chối và chỉ trừ ít điểm (-3 điểm)
  const res = moderateAvatarUpload(db, {
    userId: 'u4',
    mimeType: 'image/jpeg',
    imageBase64: 'dummy',
    aiResult: {
      decision: 'review',
      reason: 'Hình ảnh hở hang khiêu dâm 18+ lộ vùng kín',
      evidence: 'Phát hiện hình ảnh lộ bộ phận nhạy cảm.'
    }
  });

  assert.equal(res.approved, false);
  assert.equal(res.deductedPoints, 3); // Trừ ít điểm: 3 điểm
  assert.equal(res.remainingScore, 97); // 100 - 3 = 97

  // Avatar should be reset in DB
  const u = db.prepare('SELECT avatar, avatar_type, reputation_score FROM users WHERE id=?').get('u4');
  assert.equal(u.avatar, null);
  assert.equal(u.avatar_type, null);
  assert.equal(u.reputation_score, 97);
});

test('Video Moderation: hides violating video, deducts mild points and records violation dossier', () => {
  const db = setupTestDb();
  const now = Date.now();
  db.prepare("INSERT INTO users(id, username, password, salt, name, birth_date, created) VALUES('u5', 'video_creator', 'pwd', 'salt', 'Video Test', '2000-01-01', ?)").run(now);
  db.prepare("INSERT INTO shorts(id, user_id, caption, hidden, created) VALUES('s1', 'u5', 'Link nhận thưởng shopee nhập otp nhận xu lậu', 0, ?)").run(now);

  const res = moderateVideoUpload(db, {
    userId: 'u5',
    videoId: 's1',
    videoType: 'short',
    caption: 'Link nhận thưởng shopee nhập otp nhận xu lậu'
  });

  assert.equal(res.approved, false);
  assert.equal(res.deductedPoints, 5); // Trừ ít điểm: 5 điểm
  assert.equal(res.remainingScore, 95); // 100 - 5 = 95

  // Video must be hidden
  const s = db.prepare('SELECT hidden FROM shorts WHERE id=?').get('s1');
  assert.equal(s.hidden, 1);

  // Dossier must show violation
  const dossier = getAccountViolationDossier(db, 'u5');
  assert.equal(dossier.totalViolations, 1);
  assert.equal(dossier.violations[0].violation_type, 'video_violation');
  assert.match(dossier.violations[0].ai_reason, /lừa đảo người dùng khác/i);
});
