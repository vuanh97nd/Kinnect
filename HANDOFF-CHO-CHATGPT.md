# Handoff cho ChatGPT — tiếp tục công việc Kinnect

> Người bàn giao: Claude Opus 4.7. Ngày: 2026-10-26. Commit điểm xuất phát: `84d6fbd`.
> Nhánh: `feature/social-core`.

## Bối cảnh
Dự án **Kinnect** là mạng xã hội Vietnamese (feed, reels, stories, live, messenger,
WebRTC call, nhóm, hồ sơ, admin). Server Node + ws, SQLite, Cloudflare tunnel. Phiên
làm việc trước đã làm:
- P0 hạ tầng: thống nhất cổng 3000, kill-before-start, gỡ xung đột autostart.
- P1 client: dedupe API GET (giảm `/api/notifications` ×5 → ×1), fix bell → openNotificationCenter popup, Service Worker không bị tiêm `?v=XXX`.
- Design system v2 mới: `public/tokens.css` + `public/polish.css` — tokens, header, button, toast, skeleton, card, call panel, live, chips.
- E2E stability: Playwright chromium installed, retries, timeouts, 10+ spec sửa.
- Unit test: 40/40 pass.
- Commit `84d6fbd` chứa tất cả. Còn LẠI trong working tree là công việc uncommitted của người dùng (từ trước phiên này).

## Việc còn lại (ưu tiên giảm dần)

### 1. [BLOCKER] `public/social.js` chưa commit — có hai lớp thay đổi chồng lên nhau
File này đang có:
- (a) Công việc uncommitted của người dùng từ TRƯỚC phiên: không rõ scope, diff ~1200 dòng.
- (b) Chỉnh sửa của Claude trong phiên: dedupe `api()` GET, `openNotificationCenter`, toast 2.5s, `meBtn` luôn mở popup.

**Yêu cầu**: Người dùng cần review file, tách commit riêng cho (a) rồi commit (b). Hoặc
chạy `git diff public/social.js` để xem toàn bộ và chốt. 4 thay đổi của (b) có thể tìm bằng grep:
- `inFlightGets`
- `openNotificationCenter`
- `noticeTimer = setTimeout(... 2500)`
- `meBtn.onclick = () =>` (bỏ nhánh desktop → navigate("account"))

### 2. [E2E] 30 test fail cần xử lý theo nhóm
Các test chưa pass trong lần chạy đầy đủ cuối cùng (xem `data/e2e-final.log` nếu còn,
hoặc chạy lại `npx playwright test`). Có 3 nhóm:

**Nhóm A — Test cần cập nhật theo UI mới** (an toàn, sửa test):
- `e2e/header-content-routing.spec.js`, `e2e/header-message-hub.spec.js`,
  `e2e/profile-settings-layout.spec.js` (biến thể 1280), `e2e/chat-files.spec.js`,
  `e2e/cross-screen-links.spec.js`, `e2e/following-videos.spec.js`,
  `e2e/live-swipe.spec.js`, `e2e/reel-fullscreen.spec.js`, `e2e/reels.spec.js`,
  `e2e/realtime-notifications.spec.js`.
- Pattern phổ biến: aria-label đã đổi (ví dụ "Tài khoản" → "Tài khoản của tôi"),
  back-button bị ẩn trên desktop ≥1000px nên `boundingBox()` null, badge `#friends-count`
  trả `●` thay vì `+1`, hoặc notification-center chuyển sang popup `#notification-center`
  khi click bell.
- Cách xử: chạy từng spec `--retries=0`, đọc Error, sửa selector/giá trị kỳ vọng.

**Nhóm B — WebRTC trong headless chromium**:
- `e2e/video-call.spec.js`, `e2e/message-actions.spec.js` (video call), `e2e/messaging.spec.js` (private video call).
- Vấn đề: `chromium_headless_shell` không chạy đủ WebRTC. Phải dùng Chromium đầy đủ:
  `npx playwright install chromium` (đã làm) + trong `playwright.config.js` set
  `channel: "chromium"` HOẶC chạy `headless: false`. Thử lại trên máy có GUI để xác nhận.

**Nhóm C — Phụ thuộc dữ liệu seed thực**:
- `e2e/social.spec.js` (một số test), `e2e/live-swipe.spec.js`.
- Cần dọn dữ liệu test hoặc inject fixture.

### 3. [POLISH UI] Sâu hơn (sau khi test ổn)
Đã làm nông: feed card / profile / call panel / live. Cần đánh bóng:
- **Màn hồ sơ (profile edit)**: viewport desktop, bố cục ảnh bìa + avatar + tab chưa gọn.
- **Studio quay video (`camera.js`)**: UI shutter / timeline chưa đồng bộ với design system mới.
- **Live stage**: badge/controls đã có polish, chat panel cần review ở mobile landscape.
- **Dark theme**: kiểm tra bóng + contrast ở `tokens.css` (đã có override) — đọ với Figma nếu có.

### 4. [FEATURE] Audit & bật
- **OAuth Google/Facebook**: code có, chưa cấu hình. Tạo `oauth.env` theo `oauth.env.example`.
  Khi có provider, UI tự hiện nút (`social.js:352-357`).
- **TURN**: `turn.env` dùng token HuggingFace mỏng manh. Chuyển sang Cloudflare Calls hoặc coturn tự dựng.
- **Nội dung video seed**: các reel có watermark TikTok/kenh14 (bản quyền). Người dùng
  bảo "để nguyên" trong phiên này, nhưng trước khi production cần thay.

### 5. [CODE] Refactor
- `public/social.js` 2.486 dòng — nên tách feed/messenger/profile/discover thành module riêng.
- `lib/social.js` 1.240 dòng — tương tự tách theo domain.
- CSS: `theme.css` 2.572 + `compact.css` 1.081 + nhiều file nhỏ — gom về tokens.

## Quy ước phiên này
- Commit messages: tiếng Việt + prefix `chore/fix/feat/style/test` theo semantic.
- End commit message:
  ```
  Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
  ```
  (hoặc model đang dùng).
- Nhánh: `feature/social-core`. Chưa đẩy up (không `git push` trừ khi người dùng yêu cầu).

## Chạy dự án
```bash
# Khởi động chính (autostart Windows gọi file này):
wscript "scripts\windows-startup.vbs"   # cổng 3000, tunnel https://app.kinnect.io.vn

# Dừng:
stop-kinnect.cmd

# Test:
node --test                              # unit (40/40 nên pass)
npx playwright test                      # e2e full
npx playwright test e2e/<file>.spec.js --retries=0 --reporter=line   # debug 1 spec

# Dev:
set PORT=3000 && node server.js
```

## File giao
- Báo cáo rà soát ban đầu: `RA-SOAT-KINNECT-2026-10-26.md`
- Handoff này: `HANDOFF-CHO-CHATGPT.md`
- Commit điểm xuất phát: `git show 84d6fbd`
