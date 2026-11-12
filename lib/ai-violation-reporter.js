import { randomUUID } from 'node:crypto';

/**
 * AI Violation Reporter, Reputation & Moderation System for Kinnect
 * Báo rõ nội dung vi phạm, trừ điểm uy tín thành viên, kiểm duyệt avatar & video khi đăng tải.
 */

export const VIOLATION_TYPES = Object.freeze({
  harassment: { name: 'Quấy rối & Xúc phạm danh dự', defaultSeverity: 'medium', defaultPenalty: 5 },
  scam: { name: 'Lừa đảo & Trục lợi tiền tệ/xu', defaultSeverity: 'high', defaultPenalty: 10 },
  hate_speech: { name: 'Phát ngôn thù ghét & Kích động', defaultSeverity: 'high', defaultPenalty: 10 },
  explicit_content: { name: 'Nội dung khiêu dâm & Nhạy cảm 18+', defaultSeverity: 'medium', defaultPenalty: 5 },
  violence: { name: 'Đe dọa bạo lực & An toàn tính mạng', defaultSeverity: 'critical', defaultPenalty: 25 },
  csam_csae: { name: 'Xâm hại & An toàn trẻ vị thành niên', defaultSeverity: 'critical', defaultPenalty: 50 },
  spam: { name: 'Tin nhắn rác & Quảng cáo cờ bạc', defaultSeverity: 'low', defaultPenalty: 2 },
  impersonation: { name: 'Mạo danh người khác / Quản trị viên', defaultSeverity: 'medium', defaultPenalty: 5 },
  avatar_violation: { name: 'Ảnh đại diện nhạy cảm / Không phù hợp', defaultSeverity: 'medium', defaultPenalty: 3 },
  video_violation: { name: 'Video chứa hình ảnh nhạy cảm / Không phù hợp', defaultSeverity: 'medium', defaultPenalty: 5 }
});

export const PENALTY_POINTS = Object.freeze({
  low: 2,        // Spam, tin rác, liên kết quảng cáo nhẹ: -2 điểm
  medium: 5,     // Quấy rối nhẹ, video/bài viết nhạy cảm: -5 điểm
  high: 10,      // Lừa đảo, ngôn từ thù ghét: -10 điểm
  critical: 25   // Bạo lực nguy cấp, đe dọa tính mạng: -25 điểm (CSAM xử lý nghiêm: 50)
});

export function ensureViolationAndReputationTables(db) {
  // 1. Ensure reputation_score and role column on users
  try {
    const cols = db.prepare('PRAGMA table_info(users)').all();
    if (!cols.some(c => c.name === 'reputation_score')) {
      db.exec('ALTER TABLE users ADD COLUMN reputation_score INTEGER NOT NULL DEFAULT 100');
    }
    if (!cols.some(c => c.name === 'role')) {
      db.exec("ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'");
    }
  } catch {}

  // 2. Account Violations table
  db.exec(`
    CREATE TABLE IF NOT EXISTS account_violations (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      username TEXT NOT NULL,
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      violation_type TEXT NOT NULL,
      severity TEXT NOT NULL DEFAULT 'medium',
      deducted_points INTEGER NOT NULL DEFAULT 0,
      ai_reason TEXT NOT NULL,
      ai_evidence TEXT NOT NULL,
      ai_confidence REAL NOT NULL DEFAULT 0.9,
      status TEXT NOT NULL DEFAULT 'confirmed',
      action_taken TEXT NOT NULL DEFAULT 'warning',
      created INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS account_violations_user ON account_violations(user_id, created DESC);
    CREATE INDEX IF NOT EXISTS account_violations_created ON account_violations(created DESC);

    CREATE TABLE IF NOT EXISTS reputation_logs (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      username TEXT NOT NULL,
      points_delta INTEGER NOT NULL,
      points_after INTEGER NOT NULL,
      reason TEXT NOT NULL,
      violation_id TEXT,
      actor TEXT NOT NULL DEFAULT 'Kinnect AI',
      created INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS reputation_logs_user ON reputation_logs(user_id, created DESC);
  `);
}

/**
 * Lấy thông tin điểm uy tín và hạn mức tính năng của thành viên
 */
export function getReputationInfo(db, userId) {
  ensureViolationAndReputationTables(db);
  const u = db.prepare('SELECT id, username, name, suspended, reputation_score FROM users WHERE id=?').get(userId);
  if (!u) return null;

  const score = Number.isInteger(u.reputation_score) ? u.reputation_score : 100;
  let tier = 'excellent';
  let tierLabel = 'Rất tốt (Chuẩn mực 90-100)';
  let tierColor = '#10B981';

  if (score >= 90) {
    tier = 'excellent';
    tierLabel = 'Chuẩn mực (90–100 điểm)';
    tierColor = '#10B981';
  } else if (score >= 70) {
    tier = 'good';
    tierLabel = 'Khá (Cảnh báo nhẹ 70–89 điểm)';
    tierColor = '#F59E0B';
  } else if (score >= 50) {
    tier = 'warning';
    tierLabel = 'Hạn chế tính năng (50–69 điểm)';
    tierColor = '#F97316';
  } else {
    tier = 'restricted';
    tierLabel = 'Nguy hiểm / Bị tạm khóa (<50 điểm)';
    tierColor = '#EF4444';
  }

  const logs = db.prepare('SELECT * FROM reputation_logs WHERE user_id=? ORDER BY created DESC LIMIT 20').all(userId);

  return {
    userId: u.id,
    username: u.username,
    name: u.name,
    score,
    tier,
    tierLabel,
    tierColor,
    canGoLive: score >= 50 && u.suspended === 0,
    canPost: score >= 30 && u.suspended === 0,
    canComment: score >= 30 && u.suspended === 0,
    isSuspended: u.suspended === 1 || score < 30,
    logs
  };
}

/**
 * Trừ điểm uy tín của thành viên kèm lý do rõ ràng từ AI
 */
export function deductReputation(db, {
  userId,
  points,
  reason,
  violationId = null,
  actor = 'Kinnect AI'
}) {
  ensureViolationAndReputationTables(db);
  const u = db.prepare('SELECT id, username, suspended, role, reputation_score FROM users WHERE id=?').get(userId);
  if (!u) throw new Error('Không tìm thấy tài khoản.');

  // Quy tắc nghiệp vụ cấp cao: Tài khoản Quản trị viên (Admin) KHÔNG BAO GIỜ bị trừ điểm uy tín hay tạm khóa
  if (u.role === 'admin') {
    return {
      userId,
      username: u.username,
      pointsDeducted: 0,
      oldScore: 100,
      newScore: 100,
      remainingScore: 100,
      tier: 'excellent',
      tierLabel: 'Quản trị viên (Admin)',
      tierColor: '#7548DE',
      suspended: false,
      skippedAdmin: true,
      reason: 'Tài khoản Quản trị viên (Admin) được miễn trừ hoàn toàn khỏi chế tài trừ điểm uy tín.'
    };
  }

  const currentScore = Number.isInteger(u.reputation_score) ? u.reputation_score : 100;
  const deducted = Math.max(1, Math.min(100, Math.round(points)));
  const newScore = Math.max(0, currentScore - deducted);
  const now = Date.now();
  const logId = randomUUID();

  db.exec('BEGIN IMMEDIATE');
  try {
    // Nếu điểm rơi xuống dưới 30, tự động tạm đình chỉ tài khoản
    const shouldSuspend = newScore < 30;
    if (shouldSuspend && u.suspended === 0) {
      db.prepare('UPDATE users SET suspended=1, reputation_score=? WHERE id=?').run(newScore, userId);
      db.prepare('DELETE FROM sessions WHERE user_id=?').run(userId);
    } else {
      db.prepare('UPDATE users SET reputation_score=? WHERE id=?').run(newScore, userId);
    }

    db.prepare(`
      INSERT INTO reputation_logs(id, user_id, username, points_delta, points_after, reason, violation_id, actor, created)
      VALUES(?,?,?,?,?,?,?,?,?)
    `).run(logId, userId, u.username, -deducted, newScore, reason, violationId, actor, now);

    db.exec('COMMIT');

    return {
      userId,
      username: u.username,
      previousScore: currentScore,
      deductedPoints: deducted,
      remainingScore: newScore,
      suspended: shouldSuspend,
      logId
    };
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

/**
 * Khôi phục / Cộng lại điểm uy tín (cho Admin hoặc sau khi giải quyết khiếu nại)
 */
export function restoreReputation(db, {
  userId,
  points,
  reason,
  actor = 'Quản trị viên'
}) {
  ensureViolationAndReputationTables(db);
  const u = db.prepare('SELECT id, username, suspended, reputation_score FROM users WHERE id=?').get(userId);
  if (!u) throw new Error('Không tìm thấy tài khoản.');

  const currentScore = Number.isInteger(u.reputation_score) ? u.reputation_score : 100;
  const added = Math.max(1, Math.min(100, Math.round(points)));
  const newScore = Math.min(100, currentScore + added);
  const now = Date.now();
  const logId = randomUUID();

  db.exec('BEGIN IMMEDIATE');
  try {
    // Nếu trước đó bị khóa vì điểm thấp và nay hồi phục >= 50 -> mở khóa
    const shouldRestore = u.suspended === 1 && newScore >= 50;
    if (shouldRestore) {
      db.prepare('UPDATE users SET suspended=0, reputation_score=? WHERE id=?').run(newScore, userId);
    } else {
      db.prepare('UPDATE users SET reputation_score=? WHERE id=?').run(newScore, userId);
    }

    db.prepare(`
      INSERT INTO reputation_logs(id, user_id, username, points_delta, points_after, reason, violation_id, actor, created)
      VALUES(?,?,?,?,?,?,?,?,?)
    `).run(logId, userId, u.username, added, newScore, reason, null, actor, now);

    db.exec('COMMIT');

    return {
      userId,
      username: u.username,
      previousScore: currentScore,
      addedPoints: added,
      remainingScore: newScore,
      restored: shouldRestore,
      logId
    };
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

/**
 * AI Phân tích chi tiết câu từ, hình ảnh để báo rõ nội dung vi phạm
 * Tuân thủ chính sách:
 * - Ảnh khoe body, gym, cơ bắp, bikini, đồ bơi: HOÀN TOÀN HỢP LỆ (không sao, không phạt).
 * - Ảnh nhạy cảm (18+, khiêu dâm thô tục): TRỪ ÍT ĐIỂM (-5 điểm).
 * - Ảnh riêng tư: TUYỆT ĐỐI KHÔNG CẤM.
 */
export function analyzeAccountViolation({
  content = '',
  targetType = 'post',
  targetId = '',
  userId = '',
  username = '',
  contextNote = '',
  isPrivate = false
}) {
  // Ảnh riêng tư không được cấm
  if (isPrivate || targetType === 'private' || targetType === 'dm') {
    return {
      userId,
      username,
      targetType,
      targetId,
      violationType: 'none',
      severity: 'none',
      penaltyPoints: 0,
      aiReason: 'Nội dung riêng tư được bảo vệ, không thuộc diện kiểm duyệt công khai.',
      aiEvidence: '',
      aiConfidence: 1.0,
      actionTaken: 'allow',
      status: 'approved'
    };
  }

  const text = `${content} ${contextNote}`.toLowerCase();

  let violationType = 'harassment';
  let severity = 'medium';
  let penaltyPoints = 5;
  let aiReason = 'Nội dung có dấu hiệu vi phạm chuẩn mực ứng xử văn minh của cộng đồng Kinnect.';
  let aiEvidence = content.slice(0, 300) || 'Dấu hiệu vi phạm từ hành vi hoặc báo cáo.';
  let confidence = 0.88;
  let actionTaken = 'warning';

  if (/\b(csam|csae|ấu dâm|trẻ em khiêu dâm|xâm hại trẻ)\b/i.test(text)) {
    violationType = 'csam_csae';
    severity = 'critical';
    penaltyPoints = 50;
    confidence = 0.99;
    actionTaken = 'permanently_banned';
    aiReason = 'Phát hiện nội dung xâm hại nghiêm trọng an toàn trẻ vị thành niên (CSAM/CSAE). Hành vi bị cấm tuyệt đối theo pháp luật và tiêu chuẩn quốc tế.';
    aiEvidence = `Nội dung chứa từ khóa đặc biệt nguy hiểm: "${content.slice(0, 200)}"`;
  } else if (/\b(giết|chém|bắn chết|cho ăn đòn|đốt nhà|thuê giang hồ|tự tử|chết đi)\b/i.test(text)) {
    violationType = 'violence';
    severity = 'critical';
    penaltyPoints = 25;
    confidence = 0.95;
    actionTaken = 'temporary_suspended';
    aiReason = 'Nội dung chứa phát ngôn đe dọa bạo lực thể xác, xâm hại tính mạng hoặc cổ xúy hành vi nguy hiểm.';
    aiEvidence = `Trích đoạn đe dọa bạo lực: "${content.slice(0, 200)}"`;
  } else if (/\b(nạp xu lậu|hack xu|cho xu miễn phí|nhập otp|gửi mật khẩu|chuyển tiền gấp|nhận thưởng shopee|link nhận quà)\b/i.test(text)) {
    violationType = 'scam';
    severity = 'high';
    penaltyPoints = 10;
    confidence = 0.94;
    actionTaken = 'temporary_suspended';
    aiReason = 'Tài khoản có hành vi lừa đảo người dùng khác, dụ dỗ cung cấp mã xác thực OTP/mật khẩu hoặc trục lợi giao dịch ví xu Kinnect.';
    aiEvidence = `Dấu hiệu gian lận trục lợi: "${content.slice(0, 200)}"`;
  } else if (/\b(gái gọi|lộ clip|phim sex|khiêu dâm|chat sex|bán dâm|gạ tình|show hàng|lộ vùng kín|lộ hàng)\b/i.test(text)) {
    // Ảnh khoe body, gym, fitness, bikini, đồ bơi -> HOÀN TOÀN HỢP LỆ
    const isBodyPhysique = /\b(khoe body|gym|fitness|cơ bắp|sáu múi|6 múi|bikini|đồ bơi|áo tắm|tắm biển|thời trang|dáng đẹp|sexy|workout|physique|bodybuilding|body fit|khoe dáng|không áo|shirtless)\b/i.test(text);
    const isExplicitSensitive = /\b(gái gọi|phim sex|bán dâm|khiêu dâm|lộ vùng kín|lộ hàng|chat sex)\b/i.test(text);

    if (isBodyPhysique && !isExplicitSensitive) {
      return {
        userId,
        username,
        targetType,
        targetId,
        violationType: 'none',
        severity: 'none',
        penaltyPoints: 0,
        aiReason: 'Ảnh khoe body / thể hình / đồ bơi hợp lệ theo Tiêu chuẩn Cộng đồng Kinnect.',
        aiEvidence: '',
        aiConfidence: 0.92,
        actionTaken: 'allow',
        status: 'approved'
      };
    }

    violationType = 'explicit_content';
    severity = 'medium';
    penaltyPoints = 5;
    confidence = 0.93;
    actionTaken = 'content_hidden';
    aiReason = 'Nội dung chia sẻ hình ảnh nhạy cảm hoặc câu từ khiêu dâm thô tục, vi phạm quy định về nội dung lành mạnh của Kinnect.';
    aiEvidence = `Trích đoạn từ ngữ hoặc hình ảnh nhạy cảm: "${content.slice(0, 200)}"`;
  } else if (/\b(bắc kỳ|nam kỳ|kỳ thị|mọi miên|lũ xúc vật|đồ mọi rợ)\b/i.test(text)) {
    violationType = 'hate_speech';
    severity = 'high';
    penaltyPoints = 10;
    confidence = 0.91;
    actionTaken = 'content_hidden';
    aiReason = 'Phát ngôn có tính chất miệt thị, thù ghét vùng miền, sắc tộc hoặc kích động mâu thuẫn cộng đồng.';
    aiEvidence = `Phát ngôn kích động: "${content.slice(0, 200)}"`;
  } else if (/\b(tài xỉu|nổ hũ|kubet|thabet|cá độ|bắn cá đổi thưởng|game bài|nhà cái uy tín)\b/i.test(text)) {
    violationType = 'spam';
    severity = 'low';
    penaltyPoints = 2;
    confidence = 0.96;
    actionTaken = 'content_hidden';
    aiReason = 'Phát tán tin nhắn rác, quảng cáo cờ bạc, cá cược trực tuyến trái phép.';
    aiEvidence = `Nội dung quảng cáo cá cược: "${content.slice(0, 200)}"`;
  } else {
    violationType = 'harassment';
    severity = 'medium';
    penaltyPoints = 5;
    confidence = 0.85;
    actionTaken = 'warning';
    aiReason = 'Nội dung xúc phạm danh dự, công kích cá nhân hoặc quấy rối thành viên khác trong cộng đồng.';
    aiEvidence = `Nội dung bị báo cáo: "${content.slice(0, 200)}"`;
  }

  return {
    userId,
    username,
    targetType,
    targetId,
    violationType,
    violationName: VIOLATION_TYPES[violationType]?.name || violationType,
    severity,
    penaltyPoints,
    aiReason,
    aiEvidence,
    aiConfidence: confidence,
    actionTaken,
    status: 'confirmed'
  };
}

/**
 * Ghi nhận vi phạm vào cơ sở dữ liệu VÀ tự động trừ điểm uy tín thành viên
 */
export function recordViolationAndDeductPoints(db, violationData) {
  ensureViolationAndReputationTables(db);
  const id = randomUUID();
  const now = Date.now();

  // Kiểm tra nếu là Admin: không phạt điểm và không khóa
  const userRole = db.prepare('SELECT role FROM users WHERE id=?').get(violationData.userId)?.role;
  const isSuperAdmin = userRole === 'admin';
  const penalty = isSuperAdmin ? 0 : (violationData.penaltyPoints || PENALTY_POINTS[violationData.severity] || 10);

  // 1. Trừ điểm uy tín (bỏ qua nếu là Admin)
  const rep = deductReputation(db, {
    userId: violationData.userId,
    points: penalty,
    reason: isSuperAdmin ? `[Admin Miễn trừ] ${violationData.aiReason.slice(0, 150)}` : `[AI Phạt vi phạm] ${violationData.aiReason.slice(0, 150)}`,
    violationId: id,
    actor: 'Kinnect AI'
  });

  // 2. Ghi bản ghi vi phạm
  db.prepare(`
    INSERT INTO account_violations(
      id, user_id, username, target_type, target_id, violation_type,
      severity, deducted_points, ai_reason, ai_evidence, ai_confidence, status, action_taken, created
    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)
  `).run(
    id, violationData.userId, violationData.username || rep.username,
    violationData.targetType || 'post', violationData.targetId || id,
    violationData.violationType || 'harassment', violationData.severity || 'medium',
    penalty, violationData.aiReason, violationData.aiEvidence,
    violationData.aiConfidence || 0.9, 'confirmed', violationData.actionTaken || 'warning', now
  );

  return {
    violationId: id,
    deductedPoints: penalty,
    remainingScore: rep.remainingScore,
    suspended: rep.suspended,
    violation: {
      id,
      ...violationData,
      deducted_points: penalty,
      created: now
    }
  };
}

/**
 * ĐÁNH GIÁ CHÍNH SÁCH HÌNH ẢNH & VIDEO KINNECT:
 * 1. Ảnh riêng tư: TUYỆT ĐỐI KHÔNG CẤM, không trừ điểm (tin nhắn riêng tư, bài viết cá nhân riêng tư).
 * 2. Ảnh khoe body: Tập gym, thể hình, 6 múi, bikini, đồ bơi, khoe dáng quyến rũ HOÀN TOÀN HỢP LỆ (KHÔNG SAO).
 * 3. Ảnh nhạy cảm: Lộ bộ phận sinh dục, quan hệ tình dục, khiêu dâm thô tục 18+ công khai -> BỊ TRỪ ÍT ĐIỂM (-3 điểm avatar, -5 điểm video).
 */
export function evaluateImageContentPolicy({
  aiResult = null,
  caption = '',
  isPrivate = false,
  context = ''
}) {
  // 1. Ảnh riêng tư không được cấm
  if (isPrivate || context === 'private' || context === 'dm') {
    return {
      allowed: true,
      isViolation: false,
      isPrivate: true,
      reason: 'Ảnh riêng tư không thuộc phạm vi kiểm duyệt công khai và không bị cấm.'
    };
  }

  const text = `${caption} ${aiResult?.reason || ''} ${aiResult?.evidence || ''}`.toLowerCase();

  // 2. Nhận diện ảnh khoe body / gym / fitness / bikini / đồ bơi / cơ bắp
  const isBodyPhysique = /\b(khoe body|gym|fitness|cơ bắp|sáu múi|6 múi|bikini|đồ bơi|áo tắm|tắm biển|thời trang|dáng đẹp|sexy|workout|physique|bodybuilding|body fit|khoe dáng|không áo|shirtless)\b/i.test(text);

  // 3. Nhận diện ảnh nhạy cảm thực sự (18+, khiêu dâm, lộ bộ phận sinh dục, quan hệ tình dục)
  const isExplicitSensitive = /\b(lộ hàng|lộ vùng kín|lộ bộ phận sinh dục|lộ núm|khiêu dâm|phim sex|chat sex|bán dâm|gạ tình|giao cấu|quan hệ tình dục|nude 100%|full nude|genitals)\b/i.test(text);

  // Nếu là ảnh khoe body và không lộ bộ phận sinh dục/khiêu dâm thô tục -> HOÀN TOÀN HỢP LỆ (KHÔNG SAO)
  if (isBodyPhysique && !isExplicitSensitive) {
    return {
      allowed: true,
      isViolation: false,
      isBodyShowcase: true,
      reason: 'Ảnh khoe body / thể hình / đồ bơi hợp lệ theo Tiêu chuẩn Cộng đồng Kinnect.'
    };
  }

  // Nếu AI gắn cờ vi phạm hoặc phát hiện nhạy cảm thực sự
  if (isExplicitSensitive || aiResult?.decision === 'review' || aiResult?.violation) {
    // Nếu AI báo review nhưng do hiểu nhầm ảnh thể hình khoe dáng lành mạnh -> bỏ qua
    if (isBodyPhysique && !isExplicitSensitive) {
      return {
        allowed: true,
        isViolation: false,
        isBodyShowcase: true,
        reason: 'Ảnh khoe body / thể hình lành mạnh được phép trên Kinnect.'
      };
    }

    return {
      allowed: false,
      isViolation: true,
      isSensitive: true,
      reason: aiResult?.reason || 'Ảnh nhạy cảm vi phạm quy chuẩn nội dung văn minh (khiêu dâm / lộ bộ phận nhạy cảm).',
      evidence: aiResult?.evidence || 'Phát hiện nội dung nhạy cảm qua nhận diện thị giác AI.'
    };
  }

  return {
    allowed: true,
    isViolation: false,
    reason: 'Hình ảnh hợp lệ.'
  };
}

/**
 * KIỂM DUYỆT ẢNH AVATAR BẰNG AI KHI ĐĂNG TẢI
 * - Ảnh khoe body, gym, bikini: HỢP LỆ (không sao).
 * - Ảnh riêng tư: Không bị cấm.
 * - Ảnh nhạy cảm: Trừ ít điểm (-3 điểm) và reset avatar về mặc định.
 */
export function moderateAvatarUpload(db, { userId, mimeType, imageBase64, aiResult = null, caption = '', isPrivate = false }) {
  ensureViolationAndReputationTables(db);
  const u = db.prepare('SELECT id, username, name FROM users WHERE id=?').get(userId);
  if (!u) throw new Error('Không tìm thấy tài khoản.');

  // Ảnh riêng tư không được cấm
  if (isPrivate) {
    return { approved: true, isPrivate: true };
  }

  const evalRes = evaluateImageContentPolicy({ aiResult, caption, isPrivate });

  if (evalRes.isViolation) {
    // Trừ ít điểm: chỉ trừ 3 điểm đối với avatar nhạy cảm
    const penalty = 3;
    const vRes = recordViolationAndDeductPoints(db, {
      userId,
      username: u.username,
      targetType: 'avatar',
      targetId: userId,
      violationType: 'avatar_violation',
      severity: 'medium',
      penaltyPoints: penalty,
      aiReason: `Ảnh đại diện nhạy cảm: ${evalRes.reason}`,
      aiEvidence: evalRes.evidence || 'Phát hiện hình ảnh nhạy cảm qua nhận diện thị giác AI.',
      actionTaken: 'avatar_reset'
    });

    // Reset avatar về mặc định
    db.prepare('UPDATE users SET avatar=NULL, avatar_type=NULL, avatar_updated_at=? WHERE id=?').run(Date.now(), userId);

    return {
      approved: false,
      reason: `Ảnh đại diện nhạy cảm đã bị gỡ (-${penalty} điểm uy tín). Ảnh khoe body/fitness hợp lệ, nhưng ảnh nhạy cảm/khiêu dâm không dùng làm avatar công khai.`,
      deductedPoints: penalty,
      remainingScore: vRes.remainingScore,
      violationId: vRes.violationId
    };
  }

  return { approved: true, note: evalRes.reason };
}

/**
 * KIỂM DUYỆT VIDEO (SHORTS & POST VIDEO) BẰNG AI KHI ĐĂNG TẢI
 * - Video khoe body, gym, bikini: HỢP LỆ (không sao).
 * - Video riêng tư: Không bị cấm.
 * - Video nhạy cảm: Trừ ít điểm (-5 điểm) và ẩn video.
 */
export function moderateVideoUpload(db, { userId, videoId, videoType = 'short', caption = '', aiResult = null, isPrivate = false }) {
  ensureViolationAndReputationTables(db);
  const u = db.prepare('SELECT id, username, name FROM users WHERE id=?').get(userId);
  if (!u) throw new Error('Không tìm thấy tài khoản.');

  // Video riêng tư không được cấm
  if (isPrivate) {
    return { approved: true, isPrivate: true };
  }

  const evalRes = evaluateImageContentPolicy({ aiResult, caption, isPrivate });
  let isViolation = evalRes.isViolation;
  let reason = evalRes.reason;
  let evidence = evalRes.evidence;

  // Also check caption for hate/scam/violence
  if (!isViolation && caption) {
    const check = analyzeAccountViolation({
      content: caption,
      targetType: videoType,
      targetId: videoId,
      userId,
      username: u.username
    });
    if (['csam_csae', 'violence', 'scam'].includes(check.violationType)) {
      isViolation = true;
      reason = check.aiReason;
      evidence = check.aiEvidence;
    }
  }

  if (isViolation) {
    // Trừ ít điểm: 5 điểm cho video nhạy cảm
    const penalty = 5;
    const vRes = recordViolationAndDeductPoints(db, {
      userId,
      username: u.username,
      targetType: videoType,
      targetId: videoId,
      violationType: 'video_violation',
      severity: 'medium',
      penaltyPoints: penalty,
      aiReason: `Video đăng tải nhạy cảm: ${reason}`,
      aiEvidence: evidence || 'Khung hình video phát hiện nội dung nhạy cảm.',
      actionTaken: 'content_hidden'
    });

    // Hide video immediately
    if (videoType === 'short') {
      db.prepare('UPDATE shorts SET hidden=1 WHERE id=?').run(videoId);
    } else {
      db.prepare('UPDATE posts SET hidden=1 WHERE id=?').run(videoId);
    }

    return {
      approved: false,
      reason: `Video của bạn đã bị AI ẩn do nội dung nhạy cảm (-${penalty} điểm uy tín): ${reason}`,
      deductedPoints: penalty,
      remainingScore: vRes.remainingScore,
      violationId: vRes.violationId
    };
  }

  return { approved: true, note: evalRes.reason };
}

/**
 * Lấy toàn bộ hồ sơ vi phạm và lịch sử điểm uy tín của một tài khoản
 */
export function getAccountViolationDossier(db, userId) {
  ensureViolationAndReputationTables(db);
  const rep = getReputationInfo(db, userId);
  if (!rep) return null;

  const violations = db.prepare('SELECT * FROM account_violations WHERE user_id=? ORDER BY created DESC').all(userId);

  return {
    reputation: rep,
    totalViolations: violations.length,
    violations: violations.map(v => ({
      ...v,
      violationName: VIOLATION_TYPES[v.violation_type]?.name || v.violation_type
    }))
  };
}
