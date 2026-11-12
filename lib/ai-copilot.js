/**
 * Kinnect AI Smart Copilot & Workload Intelligence
 * Thiết kế tinh gọn: Ít chữ, chuẩn xác, tự động hóa các thao tác xử lý công việc.
 */

export const INTENT_KEYWORDS = {
  finance: ['xu', 'coin', 'nạp', 'mua xu', 'chuyển khoản', 'bù xu', 'tiền', 'thanh toán', 'sao kê', 'gói cước', 'đối soát', 'giao dịch'],
  support: ['quấy rối', 'chửi', 'xúc phạm', 'mật khẩu', 'quên mk', 'khóa nick', 'đình chỉ', 'mở khóa', 'báo cáo', 'uy tín', 'spam', 'lừa đảo'],
  operations: ['lag', 'đơ', 'crash', 'văng app', 'đen màn hình', 'mic', 'camera', 'webrtc', 'sfu', 'live', 'máy chủ', 'server', 'lỗi app', 'không vào được']
};

/**
 * 1. AI Phân tích nhanh vé/yêu cầu thành 2 dòng ngắn gọn + Gợi ý thao tác 1 chạm
 */
export function analyzeTicketWithAI({ subject = '', description = '', member = '', team = 'support', priority = 'normal' }) {
  const text = `${subject} ${description}`.toLowerCase();
  
  // Xác định bộ phận phù hợp
  let suggestedTeam = team;
  let finHits = INTENT_KEYWORDS.finance.filter(k => text.includes(k)).length;
  let opHits = INTENT_KEYWORDS.operations.filter(k => text.includes(k)).length;
  let supHits = INTENT_KEYWORDS.support.filter(k => text.includes(k)).length;

  if (finHits > opHits && finHits > supHits) suggestedTeam = 'finance';
  else if (opHits > finHits && opHits > supHits) suggestedTeam = 'operations';
  else if (supHits > 0) suggestedTeam = 'support';

  // Xác định mức khẩn cấp
  let suggestedPriority = priority;
  if (/nghiêm trọng|khẩn cấp|sập|mất sạch|tấn công|bị lừa|đe dọa/.test(text)) suggestedPriority = 'urgent';
  else if (/chưa nhận được|lỗi thanh toán|treo|không thể/.test(text)) suggestedPriority = 'high';

  // Tóm tắt ngắn gọn 1-2 dòng
  let summary = '';
  let actionSuggestion = '';
  let autoResponse = '';

  if (suggestedTeam === 'finance') {
    summary = `Vấn đề số dư / nạp xu của thành viên ${member || 'khách hàng'}. Cần đối soát sổ cái.`;
    actionSuggestion = 'Kiểm tra mã giao dịch trong Sổ cái & bấm "Tặng/Bù xu" nếu hợp lệ.';
    autoResponse = `Kinnect đã đối soát giao dịch nạp xu của bạn. Bộ phận Tài chính đã cập nhật số dư chính xác. Vui lòng kiểm tra lại ví của bạn nhé!`;
  } else if (suggestedTeam === 'operations') {
    summary = `Sự cố kỹ thuật / kết nối ứng dụng hoặc thiết bị người dùng.`;
    actionSuggestion = 'Kiểm tra nhật ký máy chủ và hướng dẫn cập nhật ứng dụng mới nhất.';
    autoResponse = `Bộ phận Kỹ thuật Kinnect đã kiểm tra và khắc phục sự cố kết nối. Bạn vui lòng khởi động lại app hoặc cập nhật phiên bản mới nhất nhé!`;
  } else {
    summary = `Yêu cầu hỗ trợ tài khoản / phản ánh vi phạm chuẩn mực cộng đồng.`;
    actionSuggestion = 'Kiểm tra Hồ sơ 360° & điều chỉnh điểm uy tín hoặc mở khóa tài khoản.';
    autoResponse = `Chào bạn, Kinnect đã tiếp nhận và giải quyết yêu cầu của bạn. Tài khoản và quyền lợi của bạn đã được đảm bảo đầy đủ. Chúc bạn có trải nghiệm vui vẻ!`;
  }

  return {
    summary,
    suggestedTeam,
    suggestedPriority,
    actionSuggestion,
    autoResponse,
    confidence: 0.95
  };
}

/**
 * 2. AI Soạn phản hồi thông minh theo ngữ cảnh
 */
export function generateSmartReply({ type = 'resolved', customNote = '', member = '' }) {
  const tag = member ? ` @${member.replace(/^@/, '')}` : '';
  switch (type) {
    case 'resolved':
      return `Chào bạn${tag}, Kinnect đã kiểm tra và xử lý hoàn tất yêu cầu của bạn. Mọi tính năng và số dư tài khoản đã hoạt động bình thường. Cảm ơn bạn đã đồng hành cùng Kinnect!`;
    case 'waiting_info':
      return `Chào bạn${tag}, Kinnect đã tiếp nhận yêu cầu. Bạn vui lòng cung cấp thêm thông tin (ảnh chụp màn hình hoặc mã giao dịch) để đội ngũ hỗ trợ nhanh nhất nhé!`;
    case 'reputation_restored':
      return `Chào bạn${tag}, sau khi rà soát, Kinnect xác nhận nội dung của bạn hợp lệ và đã khôi phục đầy đủ điểm uy tín (100/100đ). Cảm ơn bạn đã giữ gìn cộng đồng văn minh!`;
    case 'coin_compensated':
      return `Chào bạn${tag}, bộ phận Tài chính đã hoàn tất đối soát và bù đúng số xu vào ví Kinnect của bạn. Bạn hãy mở mục Ví để kiểm tra nhé!`;
    default:
      return customNote || `Kinnect đã xử lý xong yêu cầu. Cảm ơn bạn!`;
  }
}

/**
 * 3. AI Tóm tắt báo cáo tổng quan ngày làm việc / ca trực
 */
export function generateBriefSummary({ tickets = {}, reports = 0, resets = 0, pendingWallet = 0 }) {
  const openCount = (tickets.open || 0) + (tickets.in_progress || 0);
  const urgentCount = tickets.urgent || 0;
  
  let statusEmoji = '🟢';
  let statusText = 'Hệ thống vận hành ổn định.';
  if (urgentCount > 0) {
    statusEmoji = '🔴';
    statusText = `Có ${urgentCount} việc khẩn cấp cần giải quyết ngay!`;
  } else if (openCount > 5) {
    statusEmoji = '🟡';
    statusText = `Có ${openCount} việc đang chờ các bộ phận xử lý.`;
  }

  return {
    headline: `${statusEmoji} ${statusText}`,
    highlights: [
      `Phiếu chờ xử lý: ${openCount}`,
      `Báo cáo vi phạm: ${reports}`,
      `Yêu cầu cấp lại MK: ${resets}`,
      `Đề nghị bù xu chờ duyệt: ${pendingWallet}`
    ]
  };
}
