# Kết quả tiếp quản và review Kinnect — 26/10/2026

Nhánh: `feature/social-core`. Điểm xuất phát của phiên này: `e9e8e70`, sau commit nền `84d6fbd` và commit riêng bốn chỉnh sửa Claude.

## Kết quả

Đã review 47 mục trong working tree ban đầu, lưu thành 5 commit theo chủ đề. Có 46 tệp thay đổi nội dung; `scripts/e2e-server.js` chỉ bị Git đánh dấu do chuẩn hóa dòng, không có diff nội dung cần commit. Đối chiếu snapshot trước khi sửa xác nhận không bỏ sót tệp gốc trong các commit.

Sau đó hoàn thiện nhóm UI E2E, audit OAuth/TURN, sửa các lỗi thực tế và tách `public/social.js` thành bốn module. Working tree sạch sau các commit code. Không push Git.

## Commit lưu công việc có sẵn

| Commit | Chủ đề |
|---|---|
| `50029a1` | Backend: OTP, quản trị, realtime, call history, TURN |
| `2eca148` | Giao diện cuộc gọi/live và tín hiệu realtime |
| `7ae1643` | Điều hướng, hộp thư, hồ sơ, video và CSS |
| `2d5bd93` | Các thay đổi E2E có sẵn |
| `e9239cd` | Báo cáo và bàn giao Claude |

## Commit hoàn thiện sau review

| Commit | Nội dung |
|---|---|
| `3458345` | OAuth timeout, Facebook Authorization header, unit test OAuth/TURN, preflight và hướng dẫn |
| `102e6fd` | Livestream dùng TURN, tín hiệu tuần tự, preview 4:3, recovery timer và nút kết thúc mobile |
| `20f3256` | UI selectors, popup, badge, fixture, upload theo ID, header Android, browser test |
| `d1cb610` | Bốn module social, whitelist server và service worker cache |

## Phát hiện và cách xử lý

- Test cũ chờ màn thông báo/hồ sơ trong khi header mở popup; test message hub chờ thành phần đã bỏ. Cập nhật assertion theo hành vi hiện tại và vẫn kiểm tra điều hướng, khung nội dung/header.
- Badge bạn bè là dấu chấm, không phải `+1`; sửa test realtime, giữ tình huống request chồng nhau.
- Username fixture video vượt 30 ký tự làm đăng ký thất bại và upload trả 401. Rút ngắn tên, kiểm tra đăng ký thành công trước upload.
- Preview hộp thư và bubble cùng chứa câu chào khiến selector mơ hồ. Scope selector vào log chat.
- Feed đề xuất không đảm bảo video mới luôn đứng đầu. Kiểm tra video upload theo ID trả về thay vì vị trí.
- Chromium headless shell không phát được MP4/H.264 trong môi trường Windows này. Playwright ưu tiên Chrome đã cài trên Windows và dùng Chromium đầy đủ ở môi trường khác; vẫn hỗ trợ biến override.
- Header Android cao 60 px nhưng offset nội dung chỉ 57 px. Sửa min-height mobile để khớp offset và safe area.
- Camera tự xem bị `video { min-height:240px }` kéo méo. Đặt min-height và kích thước 4:3 rõ ràng.
- Timer phục hồi cuộc gọi đã clear nhưng chưa gán null. Đặt lại để lần mất kết nối sau vẫn có thời hạn xử lý.
- TURN Hugging Face đã cấu hình và đang cấp credentials. Giữ nguyên provider/token, thêm test cache, dedup, backup và phản hồi lỗi.
- Livestream trước đó tạo peer với `iceServers: []`. Kết nối cùng `/api/call-config`, xử lý SDP/ICE tuần tự theo peer, kiểm tra revision khi hủy/rời phòng.
- Test media mới tìm ra lớp chat mobile chặn nút kết thúc livestream. Nâng controls lên trên lớp chat; thao tác click và nhận hình thật đã pass.
- OAuth đã có luồng Google/Facebook. Thêm timeout provider, chuyển Facebook access token khỏi URL sang Authorization header, kiểm thử state/session bằng provider giả. Chưa thể xác nhận đăng nhập provider thật trước khi chủ tài khoản tạo app và điền khóa.

## Kiểm chứng

- `node --test`: **46/46 pass**; gồm 5 test TURN mới và 1 test Facebook OAuth mới.
- Toàn bộ E2E: **92 pass, 0 fail, 1 skip** trong 2,2 phút, không retry.
- Chạy riêng test media vốn opt-in với `KINNECT_MEDIA_E2E=1`: **1/1 pass**. Tổng cộng cả 93 test khác nhau đều đã pass qua hai lượt chạy.
- Test mới `live-turn.spec.js`: kiểm tra cấu hình TURN tới host/viewer và video thật qua WebRTC cục bộ.
- Gọi dịch vụ Hugging Face thật: trả ICE có một cấu hình relay TURN hợp lệ. Không in token/username/password ra log.
- Kiểm tra cú pháp các module và `git diff --check`: đạt.

E2E được chạy bằng Playwright với Chrome trên Windows, server in-memory cùng tham số authLimit=200. Sandbox gây treo ở phần dừng webServer do Playwright quản lý; dùng wrapper trong `work/` để tự mở/đóng cùng createApp, giữ nguyên testDir, use/browser, test cases và assertions. Wrapper không đưa vào commit sản phẩm. Test media cục bộ không chứng minh media đã đi qua relay khi hai thiết bị ở hai mạng Internet khác nhau.

## OAuth: phần bạn cần làm

File `oauth.env` đã được tạo từ mẫu nếu chưa có; không ghi đè file tồn tại. Google/Facebook hiện chưa có đủ khóa. Làm Google trước: tạo Web OAuth client trong Google Auth Platform, thêm test user, nhập callback `https://app.kinnect.io.vn/api/oauth/google/callback`, lưu ID/secret trực tiếp trong file. Facebook dùng callback `https://app.kinnect.io.vn/api/oauth/facebook/callback` và tài khoản có vai trò test của app.

Xem `docs/dang-nhap-google-facebook.md`. Chạy `node scripts/check-auth-call-config.js --turn` để báo trạng thái cấu hình mà không tiết lộ secret. Nút đăng nhập hiện ra chưa đủ chứng minh cấu hình provider hoạt động; cần thử trọn luồng bằng tài khoản của bạn.

## Refactor

`public/social.js`: **2.486 → 1.734 dòng**. Tách feed, discover, profile, messenger; state phiên và navigation vẫn do entry point quản lý. Context dùng getter/setter để module đọc trạng thái hiện tại. Server whitelist và cache SW đã cập nhật. Xem `docs/social-modules.md`.

Chưa tách `lib/social.js` hay dọn CSS toàn dự án. `live.css` vẫn chứa bản nhúng `calls.css`/`messenger.css`; nên gom nguồn CSS trong một thay đổi riêng có kiểm tra layout.

## Runtime

Người dùng đã cho phép khởi động lại và chạy `start-kinnect-hidden.vbs` trực tiếp trên Windows. Đã xác minh server cổng 3000 trả 200 cho `/health` và cả bốn module mới. Qua `https://app.kinnect.io.vn`, health và các module cũng trả 200; phản hồi 404 cũ ở hai module đã hết cache Cloudflare. Server đã áp dụng code mới. Không thay đổi token TURN, không push Git.

## Danh mục 47 mục đã review

| Tệp | Nhóm commit / ghi chú |
|---|---|
| `.gitignore` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `BAO-CAO-PHIEN-2026-10-26.md` | e9239cd — Báo cáo và bàn giao Claude |
| `HANDOFF-CHO-CHATGPT.md` | e9239cd — Báo cáo và bàn giao Claude |
| `e2e/chat-keyboard.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/cross-screen-links.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/dialog-back.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/following-videos.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/header-content-routing.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/header-message-hub.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/header-popups.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/inbox-hold.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/live-design.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/live-swipe.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/message-overflow.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/messenger-layout.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/navigation-history.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/profile-completion.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/realtime-notifications.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/reel-fullscreen.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/reels.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/session.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/social.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/story-music.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `e2e/video-upload.spec.js` | 2d5bd93 — Các thay đổi E2E có sẵn |
| `lib/call-config.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `lib/calls.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `lib/mailer.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `lib/private-photos.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `lib/recovery.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `lib/social.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `lib/typing.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `public/app.js` | 2eca148 — Giao diện cuộc gọi/live và tín hiệu realtime |
| `public/calls.css` | 2eca148 — Giao diện cuộc gọi/live và tín hiệu realtime |
| `public/calls.js` | 2eca148 — Giao diện cuộc gọi/live và tín hiệu realtime |
| `public/camera.js` | 7ae1643 — Điều hướng, hộp thư, hồ sơ, video và CSS |
| `public/compact.css` | 7ae1643 — Điều hướng, hộp thư, hồ sơ, video và CSS |
| `public/desktop.css` | 7ae1643 — Điều hướng, hộp thư, hồ sơ, video và CSS |
| `public/live-ui.js` | 2eca148 — Giao diện cuộc gọi/live và tín hiệu realtime |
| `public/live.css` | 2eca148 — Giao diện cuộc gọi/live và tín hiệu realtime |
| `public/messenger.css` | 7ae1643 — Điều hướng, hộp thư, hồ sơ, video và CSS |
| `public/onboarding.js` | 7ae1643 — Điều hướng, hộp thư, hồ sơ, video và CSS |
| `public/social.js` | 7ae1643 — Điều hướng, hộp thư, hồ sơ, video và CSS |
| `public/theme.css` | 7ae1643 — Điều hướng, hộp thư, hồ sơ, video và CSS |
| `scripts/e2e-server.js` |  — Không có diff nội dung; chỉ chuẩn hóa dòng |
| `test/recovery.test.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `test/social.test.js` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
| `turn.env.example` | 50029a1 — Backend: OTP, quản trị, realtime, call history, TURN |
