# Bàn giao Kinnect 1.0.4 cho phiên đám mây — 29/10/2026

Đọc phần này trước. Các ghi chú từ 26/10 ở phía dưới là lịch sử, không phải trạng thái hiện tại.

## Điểm bắt đầu
- Nhánh bàn giao: `handoff/kinnect-1.0.4-cloud`. Đây là ảnh chụp mã nguồn đang chạy ở Windows; không phải mọi thay đổi so với main đều được viết trong cùng một lượt sửa.
- App/server: thư mục gốc. Trang giới thiệu `kinnect.io.vn`: `website/`; cấu hình static assets `website/wrangler.jsonc`.
- APK mới: **1.0.4, versionCode 69**. SHA-256: `a26553be2fab98b96dea38b490113725ffc91b5f46ad9232335aa950c250f2d0`.
- Chứng thư ký cần giữ: `d8809c1e21f00ccf96984b37123d3d916d2e103bfa1dc2032043f47bb3b9988d`.
- Khóa ký, database, tệp .env, credential Cloudflare/GitHub và dữ liệu tài khoản không nằm trong bàn giao.

## Hành vi và giới hạn phạm vi
- Giữ bố cục/màu hiện có; chỉ sửa những lỗi đã xác định. Logo chuẩn là K trắng nền chuyển sắc tím–hồng `public/kinnect-icon-192.png`, giống từng byte với `res/drawable/kinnect_icon.png` trong APK đã ký.
- Web entry: `public/index.html`, `v2.html`, `v2.js`, `v2.css`. PC giữ màn đăng nhập cũ dạng tường chân dung; mobile có cuộn khi màn hình thấp/bàn phím mở.
- Khởi động web đồng bộ splash native: logo 96px, Kinnect, “Kết nối theo cách của bạn.”, hai vòng tím–hồng.
- Trang giới thiệu mobile nằm trong iframe `website/dist/native-welcome.html`. `native-fit.js` phải chạy trước JS demo lớn. Chỉ hiện mô hình sau khi tính xong kích thước; mô hình đã giảm 10%. Khi sửa, đổi mã phiên bản ở iframe, CSS và JS: tài nguyên static có cache 24 giờ.
- Bốn ảnh demo Khám phá trước đây bị thiếu; đã có `welcome-profile*.png` trong public và website/dist. Không xóa các ảnh này khỏi APK assets.
- 1.0.3 bổ sung cập nhật trong app: Cài đặt → Kiểm tra cập nhật → Đồng ý cập nhật → tải trong Kinnect, hiện tiến độ, kiểm SHA-256/package/version/chứng thư → trình cài đặt Android. Không dùng Chrome để tải. Android vẫn yêu cầu cấp quyền nguồn cài và xác nhận cài đặt khi cần.
- 1.0.4 căn giữa tiêu đề/mô tả “Chưa theo dõi ai”, dùng chung `discoveryEmptyState()`. Web loại bỏ CSS cũ ép `discover-people` thành flex một cột; ảnh hồ sơ vuông tối đa 144px, bố trí theo hàng.

## Kiểm tra đã làm
- Xem `docs/cloud-handoff/artifact.json` và ảnh QA cùng thư mục. Không gọi 26 ảnh APK là kiểm thử toàn bộ luồng ứng dụng.
- Android: biên dịch; apktool đóng gói trên APK 1.0.3 để giữ nguyên phần khác; kiểm version/package/chữ ký; xác nhận assets, thư viện native và logo giữ nguyên; kiểm toàn bộ lớp app được tham chiếu đã đóng gói.
- Máy ảo Android 14: 13 trạng thái × 2 cấu hình màn hình/font. Thành phần empty-state được kiểm bằng instrumentation trong APK thật; các trang tài khoản dùng đối tượng người dùng mẫu trong bộ nhớ, không dùng database/tài khoản thật.
- Web: 7 màn × 6 chiều rộng = 42 trường hợp; kiểm tràn ngang/chữ tiêu đề, giới hạn ảnh, giữ lưới nhiều cột và căn giữa empty-state. Không thay thế việc duyệt ảnh mọi màn hình có dữ liệu thật.
- Updater: kiểm URL nguồn/redirect HTTPS, checksum sai/thiếu, giới hạn dung lượng, thứ tự phiên bản. Chưa nghiệm thu trọn luồng tải–cài trên điện thoại vật lý.

## Chạy và build trong phiên đám mây
1. `npm ci`; dùng Node >=22.13 (node:sqlite).
2. `npm test`. Có các E2E lịch sử dùng selector cũ và đường dẫn Windows; đừng kết luận toàn bộ suite đã pass.
3. Để audit responsive: `npx playwright install chromium`; `PLAYWRIGHT_CHANNEL=chromium node scripts/handoff-checks/web-layout-audit.mjs` (script hỗ trợ Chromium trên Linux). Script dùng database tạm trong bộ nhớ. Không chạy test vào dữ liệu thật.
4. Android Linux: `bash scripts/prepare-android-tools.sh`, `bash scripts/test-android-config.sh`, rồi `bash scripts/build-apk.sh`. Toolchain Linux và khóa ký phải được cung cấp đúng. Không tạo khóa ngẫu nhiên để thay APK đang dùng.
5. Windows đã dùng `python scripts/build-apk-windows.py`. Bản phát hành chính xác 1.0.4 được tạo bằng cách thay nhóm MainActivity trong baseline 1.0.3, giữ nguyên updater/tài nguyên. Script đóng gói đã dùng nằm ở `scripts/handoff-checks/package-layout-update-windows.py` (cần baseline APK 1.0.3 trong dist và biến `KINNECT_APKTOOL_JAR`; khóa ký được cấp riêng). Script đóng gói đã dùng nằm ở `scripts/handoff-checks/package-layout-update-windows.py` (cần baseline APK 1.0.3 trong dist và biến `KINNECT_APKTOOL_JAR`; khóa ký được cấp riêng). Script đóng gói đã dùng nằm ở `scripts/handoff-checks/package-layout-update-windows.py` (cần baseline APK 1.0.3 trong dist và biến `KINNECT_APKTOOL_JAR`; khóa ký được cấp riêng). Không tự ghi đè APK release đã kiểm bằng APK build khác chỉ vì cùng versionName.
6. Site: `python3 website/build.py`; CSS/JS/ảnh trong website/dist là đầu vào cần giữ. Xem diff trước deploy để tránh làm mất iframe mobile hoặc mã cache-bust. Build đã bổ sung giữ iframe mobile và tự gắn hash cho native HTML/CSS/JS. Cloudflare project: `odd-disk-3093`.

Unit test mới nhất: 79 bài, 78 đạt, 1 lỗi ở private call signaling (HTTP 503 trong cấu hình kiểm thử). Xem `docs/cloud-handoff/unit-test-summary.txt`. Không coi toàn bộ suite đã đạt.

## Việc tiếp theo cần phiên đám mây làm
- Tiếp tục rà căn chữ bằng ảnh và dữ liệu dài, trạng thái trống/đầy, font lớn; đặc biệt các luồng có mạng, hồ sơ, tin nhắn, Live/video/camera chưa được kiểm hết trong đợt QA này.
- Kiểm thử cập nhật 1.0.3 → 1.0.4 trên Android vật lý: từ chối/cấp quyền nguồn cài, quay lại app, mất mạng, huỷ tải, checksum/chứng thư sai, xác nhận cài, dữ liệu giữ nguyên. Không coi cài trên emulator là nghiệm thu thiết bị thật.
- Thống nhất build Linux với bản phát hành và kiểm khóa ký CI trước khi tự động phát hành. Quy trình GitHub hiện bảo vệ APK đã upload thủ công khỏi bị build khác ghi đè.
- Tách/refactor CSS cũ có !important sau khi có baseline ảnh; không đổi toàn bộ layout/màu trong lúc xử lý lỗi căn chữ.

---
# Lịch sử bàn giao cũ (26/10/2026)

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
