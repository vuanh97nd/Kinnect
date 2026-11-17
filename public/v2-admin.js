// Lazy-loaded Admin & AI Settings screens for Kinnect Web v2.

export function renderAiSettingsScreen({ aiSettings, aiSettingsError, esc, ic, btn }) {
  if (!aiSettings) {
    return '<section class="panel settings-section"><h2>Cấu hình AI</h2><p role="status">' + esc(aiSettingsError || "Chưa tải cấu hình.") + "</p>" + btn("Thử lại", "refresh-cw", "ai-reload", "secondary") + "</section>";
  }
  const c = aiSettings.credentials;
  const cfg = aiSettings.config;
  const field = (label, name, value = "", secret = false) =>
    '<label class="v2-field">' + label + '<input name="' + name + '" type="' + (secret ? "password" : "text") + '" value="' + esc(value) + '" autocomplete="' + (name === "password" ? "current-password" : secret ? "new-password" : "off") + '"></label>';
  return '<section class="panel settings-section"><h2>' + ic("shield-check") + " Cloudflare · NVIDIA dự phòng</h2><p>Khóa chỉ lưu trên máy chủ. Để trống khóa để giữ cấu hình hiện tại.</p><form data-ai-credentials class=\"settings-section\">"
    + field("URL Worker Cloudflare", "workerUrl", c.workerUrl)
    + field("Khóa kết nối Worker" + (c.tokenSaved ? " · Đã lưu" : ""), "token", "", true)
    + field("Khóa NVIDIA" + (c.nvidiaKeySaved ? " · Đã lưu" : ""), "nvidiaKey", "", true)
    + field("Model NVIDIA hỗ trợ", "nvidiaModel", c.nvidiaModel)
    + field("Model NVIDIA đọc ảnh", "nvidiaVisionModel", c.nvidiaVisionModel)
    + '<label><input name="fallbackEnabled" type="checkbox" ' + (c.fallbackEnabled ? "checked" : "") + "> Tự chuyển NVIDIA khi Cloudflare lỗi</label>"
    + field("Mật khẩu quản trị để lưu", "password", "", true)
    + '<button class="primary" type="submit">Lưu cấu hình kết nối</button><p role="status"></p></form><div class="row">'
    + [["cloudflare", "Kiểm tra Cloudflare"], ["nvidia", "Kiểm tra NVIDIA"], ["fallback", "Kiểm tra dự phòng"]].map(([key, label]) => btn(label, "refresh-cw", "ai-test", "secondary", key)).join("")
    + '</div><form data-ai-features class="settings-section">'
    + [["support", "AI trả lời hỗ trợ"], ["moderation", "AI cảnh báo nội dung vi phạm"]].map(([key, label]) => '<label><input type="checkbox" name="' + key + '" ' + (cfg[key] ? "checked" : "") + "> " + label + "</label>").join("")
    + '<p>AI cảnh báo để quản trị viên xem xét, không tự xử phạt. Kiểm duyệt video dùng khung hình mẫu, không kiểm tra âm thanh.</p><button class="primary" type="submit">Lưu bật/tắt AI</button><p role="status"></p></form><p>Đang chờ: '
    + Number(cfg.queue || 0) + " · Lỗi: " + Number(cfg.failed || 0) + ". Xem cảnh báo tại Báo cáo.</p></section>";
}

export function renderAdminScreen(ctx) {
  const { s, adminState, esc, ic, btn, person, tabs, ago, emptyState, childHeading } = ctx;
  if (s.me.role !== "admin") return emptyState("shield-check", "Không có quyền quản trị", "Chỉ tài khoản quản trị được mở mục này.");
  const a = adminState;
  let body = "";
  if (a.tab === "Người dùng") {
    body = `<form data-admin-search class="v2-search"><input data-admin-query aria-label="Tìm tài khoản" value="${esc(a.query)}" placeholder="Tên hoặc username"><button type="submit" class="icon" aria-label="Tìm tài khoản">${ic("search")}</button></form>`
      + a.users.map((u) => `<article class="v2-friend-row">${person(u, "@" + esc(u.username) + " · " + (u.role === "admin" ? "Quản trị viên" : u.suspended ? "Đã đình chỉ" : "Thành viên"))}${u.role !== "admin" ? btn(u.suspended ? "Khôi phục" : "Đình chỉ", "shield-check", "admin-user", "secondary", (u.suspended ? "restore-user:" : "suspend-user:") + u.id) : ""}</article>`).join("");
  }
  if (a.tab === "Báo cáo") {
    body = a.reports.map((r) => `<article class="panel settings-section"><h2>${esc(r.target_type)} · ${esc(r.status)}</h2><p>${esc(r.reason)}</p><p class="body-copy">${esc(r.subject?.body || r.subject?.username || "")}</p><div class="row">${r.status === "open" ? btn("Đóng báo cáo", "check", "admin-moderate", "secondary", "close-report:" + r.id) : ""}${["post", "short"].includes(r.target_type) && !r.subject?.hidden ? btn("Ẩn nội dung", "eye-off", "admin-moderate", "secondary", "hide-" + r.target_type + ":" + r.target_id) : ""}${["message", "group_message"].includes(r.target_type) ? btn("Gỡ nội dung tin nhắn", "eye-off", "admin-moderate", "secondary", "hide-" + r.target_type + ":" + r.target_id) : ""}${r.subject?.userId ? btn("Đình chỉ tài khoản", "shield-check", "admin-moderate", "secondary", "suspend-user:" + r.subject.userId) : ""}</div></article>`).join("") || emptyState("shield-check", "Chưa có báo cáo", "Báo cáo mới sẽ hiển thị tại đây.");
  }
  if (a.tab === "Yêu cầu mật khẩu") {
    body = (a.temporary ? `<div class="panel"><h2>Mật khẩu tạm</h2><p>${esc(a.temporary)}</p><small>Chỉ cung cấp cho đúng chủ tài khoản. Không lưu lại trên thiết bị dùng chung.</small>${btn("Ẩn mật khẩu", "eye-off", "admin-hide-secret", "secondary")}</div>` : "")
      + a.requests.map((r) => `<article class="panel settings-section"><h2>@${esc(r.username)}</h2><p>${esc(r.contact)}</p><p class="body-copy">${esc(r.note)}</p><small>${esc(r.status)} · ${ago(r.created)}</small>${r.status === "open" ? '<div class="row">' + (r.user_id ? btn("Cấp mật khẩu tạm", "key-round", "admin-reset", "primary", r.id) : "") + btn("Đóng yêu cầu", "x", "admin-dismiss", "secondary", r.id) + "</div>" : ""}</article>`).join("");
  }
  if (a.tab === "Nhật ký") {
    body = a.activity.map((e) => `<article class="v2-friend-row"><div><strong>${esc(e.action)}</strong><p class="body-copy">${esc(e.username || e.target)} · ${ago(e.created)}</p></div></article>`).join("");
  }
  if (a.tab === "Thư viện nhạc") {
    body = `<form data-admin-music class="panel settings-section"><h2>Thêm âm thanh</h2><label class="v2-field">Tên bài<input name="title" required maxlength="80"></label><label class="v2-field">Nghệ sĩ<input name="artist" required maxlength="60"></label><label class="v2-field">Giấy phép<input name="license" required maxlength="80"></label><label class="v2-field">Nguồn<input name="source" maxlength="300"></label><label class="v2-field">Tệp MP3 / M4A<input name="file" type="file" accept="audio/mpeg,audio/mp4,audio/x-m4a" required></label><label><input name="rights" type="checkbox" required> Tôi có quyền sử dụng và chia sẻ âm thanh này.</label><button class="primary" type="submit">Thêm âm thanh</button></form>`
      + a.music.map((m) => `<article class="v2-friend-row"><div><strong>${esc(m.title)}</strong><small>${esc(m.artist)}</small><audio src="${esc(m.url)}" controls preload="none"></audio></div>${btn("Xoá âm thanh", "trash-2", "admin-delete-music", "icon", m.file)}</article>`).join("");
  }
  if (a.tab === "Cấu hình AI") {
    body = renderAiSettingsScreen(ctx);
  }
  return childHeading("Quản trị")
    + `<div class="row admin-summary"><span>${a.overview.users || 0} Tài khoản</span><span>${a.overview.pendingResets || 0} Yêu cầu chờ</span><span>${a.overview.openReports || 0} Báo cáo chờ</span></div>`
    + tabs(["Yêu cầu mật khẩu", "Người dùng", "Báo cáo", "Thư viện nhạc", "Nhật ký", "Cấu hình AI"], a.tab, "admin-tab")
    + `<div class="stack">${body || emptyState("shield-check", "Chưa có dữ liệu", "Dữ liệu mới sẽ hiển thị tại đây.")}</div>`;
}
