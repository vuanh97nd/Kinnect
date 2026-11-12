import { randomUUID } from 'node:crypto';

/**
 * AI Smart Workload & Ticket Dispatcher for Kinnect Multi-Portal Architecture
 * Portals & Teams:
 * - admin (https://admin.kinnect.io.vn): Toàn quyền, quản lý nhân sự, bảo mật & khẩn cấp cấp cao
 * - support (https://hotro.kinnect.io.vn): Hỗ trợ khách hàng, giải đáp, kiểm duyệt nội dung & tài khoản
 * - operations (https://kythuat.kinnect.io.vn): Bộ phận kỹ thuật, lỗi app (crash/lag/video/audio/device)
 * - finance (https://taichinh.kinnect.io.vn): Bộ phận tài chính, tra cứu xu, đối soát giao dịch, gói cước
 */

export const TEAMS = Object.freeze(['admin', 'support', 'operations', 'finance']);
export const PRIORITIES = Object.freeze(['low', 'normal', 'high', 'urgent']);

export const TEAM_NAMES = Object.freeze({
  admin: 'Admin cấp cao nhất (admin.kinnect.io.vn)',
  support: 'Hỗ trợ khách hàng & Kiểm duyệt (hotro.kinnect.io.vn)',
  operations: 'Bộ phận kỹ thuật & Hệ thống (kythuat.kinnect.io.vn)',
  finance: 'Bộ phận tài chính & Đối soát (taichinh.kinnect.io.vn)'
});

// Semantic intent keywords & patterns
const OPERATIONS_PATTERNS = [
  /\b(crash|văng|thoát ứng dụng|force close|sập app)\b/i,
  /\b(đen màn hình|đơ|lag|giật|treo|đứng hình|không phản hồi)\b/i,
  /\b(mic|micro|âm thanh|loa|rè|không nghe thấy|mất tiếng)\b/i,
  /\b(camera|máy ảnh|không bật camera|lật cam|filter|hiệu ứng)\b/i,
  /\b(webrtc|sfu|livestream|phòng live|rớt live|mất kết nối|kết nối máy chủ|socket)\b/i,
  /\b(thông báo|push notification|fcm|apns|không nhận được chuông)\b/i,
  /\b(video ngắn|shorts|tải video|xuất video|render video|curves|hsl)\b/i,
  /\b(phiên bản|cập nhật|apk|ios|android|xcode|simulator|build|lỗi cài đặt)\b/i
];

const FINANCE_PATTERNS = [
  /\b(xu|coin|kinnect xu|số dư xu|mất xu|trừ xu|tiền xu)\b/i,
  /\b(nạp xu|mua xu|chuyển khoản|quét mã|ngân hàng|chưa nhận được xu)\b/i,
  /\b(bị trừ tiền|trừ 2 lần|thanh toán không nhận xu|lỗi thanh toán)\b/i,
  /\b(gói cước|gói phong cách|gói live|bộ quà|gói quà|hội viên|studio pro)\b/i,
  /\b(neon|aurora|galaxy|ice|ruby|forest|paper|ember|chill|gaming|spotlight)\b/i,
  /\b(ví kinnect|ví của tôi|đối soát|sao kê|giao dịch|lịch sử nạp|hoàn xu|rút xu)\b/i
];

const SUPPORT_PATTERNS = [
  /\b(quấy rối|xúc phạm|chửi bới|đe dọa|làm phiền|tin nhắn rác|spam)\b/i,
  /\b(tài khoản giả mạo|mạo danh|avatar phản cảm|ảnh nhạy cảm|khiêu dâm)\b/i,
  /\b(bài viết|bình luận xấu|vi phạm cộng đồng|tiêu chuẩn cộng đồng|lừa đảo)\b/i,
  /\b(quên mật khẩu|khôi phục tài khoản|đổi số điện thoại|đổi email|đổi tên)\b/i,
  /\b(hướng dẫn|cách dùng|làm sao để|hỏi về tính năng|tìm bạn|quanh đây)\b/i,
  /\b(bị khóa|khóa tài khoản|đình chỉ|mở khóa nick|khiếu nại khóa nick)\b/i
];

const ADMIN_CRITICAL_PATTERNS = [
  /\b(csam|csae|trẻ em|xâm hại trẻ em|ấu dâm)\b/i,
  /\b(tự tử|nguy hiểm tính mạng|bạo lực nguy cấp|khủng bố)\b/i,
  /\b(công an|pháp luật|trát tòa|yêu cầu pháp lý|luật sư)\b/i,
  /\b(tấn công|hack|lỗ hổng bảo mật|sql injection|ddos|lộ dữ liệu|rò rỉ dữ liệu)\b/i,
  /\b(tố cáo nhân viên|khiếu nại nhân sự|quản trị viên vi phạm)\b/i
];

/**
 * AI Classifies any ticket or report into team, priority and recommended actions
 */
export function classifyTicket({ subject = '', description = '', member = '', category = '' }) {
  const fullText = `${subject} ${description} ${category}`.toLowerCase();
  
  // 1. Check Admin Critical triggers first
  for (const pat of ADMIN_CRITICAL_PATTERNS) {
    if (pat.test(fullText)) {
      return {
        team: 'admin',
        priority: 'urgent',
        recommendedTeam: 'admin',
        recommendedPriority: 'urgent',
        slaTargetMinutes: 15,
        confidence: 0.98,
        reason: 'Phát hiện sự cố an toàn đặc biệt nghiêm trọng / bảo mật / pháp lý yêu cầu Admin xử lý trực tiếp.',
        summary: `[Khẩn cấp] ${subject.slice(0, 80)}`,
        suggestedAction: 'Admin cấp cao kiểm tra và xử lý ngay lập tức theo quy trình khẩn cấp.',
        tags: ['urgent', 'admin-escalation', 'security-safety']
      };
    }
  }

  // 2. Score other departments
  let opScore = 0, finScore = 0, supScore = 0;
  for (const pat of OPERATIONS_PATTERNS) if (pat.test(fullText)) opScore += 2;
  for (const pat of FINANCE_PATTERNS) if (pat.test(fullText)) finScore += 2;
  for (const pat of SUPPORT_PATTERNS) if (pat.test(fullText)) supScore += 2;

  // Category hints
  if (category === 'technical' || category === 'bug') opScore += 5;
  if (category === 'finance' || category === 'billing' || category === 'coin') finScore += 5;
  if (category === 'support' || category === 'account' || category === 'report') supScore += 5;

  let team = 'support';
  let reason = 'Yêu cầu hỗ trợ người dùng và chăm sóc cộng đồng.';
  let suggestedAction = 'Bộ phận Hỗ trợ kiểm tra phản hồi cho thành viên và hướng dẫn xử lý.';
  let tags = ['support'];

  if (finScore > opScore && finScore > supScore) {
    team = 'finance';
    reason = 'Liên quan đến giao dịch xu, gói cước, số dư ví hoặc thanh toán đối soát.';
    suggestedAction = 'Bộ phận Tài chính tra cứu sổ cái giao dịch, kiểm tra mã đối soát và đối chiếu số dư xu.';
    tags = ['finance', 'coins', 'ledger'];
  } else if (opScore >= finScore && opScore > supScore) {
    team = 'operations';
    reason = 'Liên quan đến sự cố kỹ thuật, trải nghiệm ứng dụng, camera/mic, crash hoặc kết nối.';
    suggestedAction = 'Bộ phận Kỹ thuật kiểm tra log thiết bị, luồng WebRTC/SFU và tái hiện lỗi.';
    tags = ['operations', 'bug', 'system'];
  } else {
    team = 'support';
    tags = ['support', 'customer-care'];
  }

  // 3. Priority determination
  let priority = 'normal';
  if (/\b(nghiêm trọng|khẩn cấp|sập|mất sạch|không vào được|bị lừa đảo|tấn công)\b/i.test(fullText)) {
    priority = 'high';
  } else if (/\b(hàng loạt|toàn bộ|tất cả người dùng|sập live|mất tiền triệu)\b/i.test(fullText)) {
    priority = 'urgent';
  } else if (/\b(góp ý|ý kiến|thêm tính năng|tham khảo|hỏi vui)\b/i.test(fullText)) {
    priority = 'low';
  }

  // Generate concise Vietnamese summary
  const cleanSubj = subject.trim() || 'Yêu cầu từ ứng dụng';
  const summary = `[${team.toUpperCase()}] ${cleanSubj.slice(0, 80)}`;
  const slaTargetMinutes = priority === 'urgent' ? 15 : priority === 'high' ? 60 : priority === 'low' ? 240 : 120;

  return {
    team,
    priority,
    recommendedTeam: team,
    recommendedPriority: priority,
    slaTargetMinutes,
    confidence: Math.min(0.95, 0.75 + 0.05 * Math.max(opScore, finScore, supScore)),
    reason,
    summary,
    suggestedAction,
    tags
  };
}

/**
 * Finds the least busy active staff member for a specific team
 */
export function findBestAssignee(db, team) {
  if (team === 'admin') return null; // Admin tasks stay unassigned or picked manually
  try {
    const activeStaff = db.prepare('SELECT id, username, name, team FROM console_staff WHERE team = ? AND suspended = 0 ORDER BY created ASC').all(team);
    if (!activeStaff.length) return null;

    // Count open/in_progress tickets for each staff member
    const counts = db.prepare("SELECT assignee, count(*) AS open_count FROM console_tickets WHERE team = ? AND status IN ('open', 'in_progress') GROUP BY assignee").all(team);
    const countMap = new Map();
    for (const r of counts) if (r.assignee) countMap.set(r.assignee, r.open_count);

    // Pick staff with lowest open count
    let best = activeStaff[0];
    let minLoad = countMap.get(best.id) || 0;

    for (let i = 1; i < activeStaff.length; i++) {
      const s = activeStaff[i];
      const load = countMap.get(s.id) || 0;
      if (load < minLoad) {
        best = s;
        minLoad = load;
      }
    }

    return {
      id: best.id,
      username: best.username,
      name: best.name,
      team: best.team,
      currentLoad: minLoad
    };
  } catch {
    return null;
  }
}

/**
 * Creates and automatically dispatches a ticket using AI
 */
export function dispatchTicketWithAI(db, {
  subject,
  description,
  member = '',
  category = '',
  reporter = 'app_user',
  actorName = 'Thành viên Kinnect',
  preferredTeam = null,
  preferredPriority = null
}) {
  const classification = classifyTicket({ subject, description, member, category });
  const finalTeam = preferredTeam && TEAMS.includes(preferredTeam) ? preferredTeam : classification.team;
  const finalPriority = preferredPriority && PRIORITIES.includes(preferredPriority) ? preferredPriority : classification.priority;
  
  const suggestedStaff = findBestAssignee(db, finalTeam);
  const assigneeId = suggestedStaff ? suggestedStaff.id : null;
  const now = Date.now();
  const ticketId = randomUUID();

  db.exec('BEGIN IMMEDIATE');
  try {
    db.prepare(`
      INSERT INTO console_tickets(id, subject, description, priority, team, member, assignee, status, version, created_by, created, updated)
      VALUES(?,?,?,?,?,?,?,?,1,?,?,?)
    `).run(ticketId, subject.slice(0, 180), description.slice(0, 6000), finalPriority, finalTeam, member.slice(0, 100), assigneeId, 'open', reporter, now, now);

    // Associate ticket with team
    db.prepare('INSERT OR IGNORE INTO console_ticket_teams(ticket_id, team) VALUES(?,?)').run(ticketId, finalTeam);
    if (finalTeam !== 'admin') {
      db.prepare('INSERT OR IGNORE INTO console_ticket_teams(ticket_id, team) VALUES(?,?)').run(ticketId, 'admin');
    }

    // Insert AI Dispatch Event
    const eventId = randomUUID();
    const eventMessage = `[AI Điều Phối Tự Động]\nPhân loại vào: ${TEAM_NAMES[finalTeam] || finalTeam}\nMức ưu tiên: ${finalPriority.toUpperCase()}\nLý do: ${classification.reason}\nKhuyến nghị: ${classification.suggestedAction}${suggestedStaff ? `\nĐã chỉ định nhân viên xử lý: @${suggestedStaff.username} (${suggestedStaff.name})` : '\nChưa có nhân sự trực tiếp, phiếu đang ở hàng chờ chung của nhóm.'}`;
    
    db.prepare(`
      INSERT INTO console_ticket_events(id, ticket_id, actor, actor_name, actor_team, action, message, before_json, after_json, created)
      VALUES(?,?,?,?,?,?,?,?,?,?)
    `).run(
      eventId,
      ticketId,
      'kinnect_ai',
      'Kinnect AI Điều Phối',
      'ai',
      'ai_triage',
      eventMessage,
      null,
      JSON.stringify({
        id: ticketId,
        team: finalTeam,
        priority: finalPriority,
        assignee: assigneeId,
        classification
      }),
      now
    );

    db.exec('COMMIT');

    const createdTicket = db.prepare('SELECT * FROM console_tickets WHERE id=?').get(ticketId);
    return {
      ticket: {
        ...createdTicket,
        assigneeUsername: suggestedStaff?.username || null,
        assigneeName: suggestedStaff?.name || null
      },
      classification,
      assignedStaff: suggestedStaff
    };
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}
