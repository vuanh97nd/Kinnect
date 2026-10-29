# Bản kiểm tra Kinnect — 26/10/2026

## Thay đổi hoàn thiện

- Cache PWA v26 chứa đủ stylesheet đang dùng, bốn module social, camera/calls và script giao diện. Trang mất mạng có cùng tokens/theme/polish.
- Khi trình duyệt báo mất mạng, SW dùng cache ngay; nếu mạng lỗi bất ngờ, vẫn có fallback. Không cache API tài khoản, tin nhắn hay nội dung thành viên.
- Đăng ký service worker theo URL phiên bản v26 và bỏ cache khi cập nhật để tránh nhận SW cũ từ CDN.
- Autostart và launcher chạy tay dùng chung `scripts/windows-startup.vbs`, cùng tunnel config. Script ép PORT=3000, kiểm tra server/Node/tunnel/config trước khi dừng tiến trình cũ, tạo data nếu chưa có.
- Shortcut `Startup/Kinnect.lnk` đã trỏ đúng script và working directory trên máy hiện tại.

## Kiểm tra autostart

Có thể chạy trên Windows: `cscript //nologo scripts/windows-startup.vbs --check`. Chế độ này chỉ kiểm tra điều kiện khởi động, không dừng server.

Sandbox không cho cscript đọc thiết lập Windows Script Host (Access is denied), nên không ghi nhận preflight runtime là pass. Chưa reboot Windows trong phiên này. Cần kiểm tra lần đăng nhập Windows tiếp theo để xác nhận toàn bộ autostart trên máy thật.

## Kiểm tra giao diện và tính năng

Mở https://app.kinnect.io.vn/?ui=20261026-v26 để lấy trang có phiên bản CSS/JS mới. Nếu tab cũ vẫn giữ giao diện trước đó, nhấn Ctrl+F5.

Kiểm tra header pill/hover, vòng avatar, toast 2,5 giây, glow nút hoàn thiện hồ sơ, card hai lớp bóng; sau đó thử popup thông báo/tài khoản, Back/Forward, chat/tệp/typing, đăng bài/video, gọi thoại/video và live.

Mất mạng chỉ hiển thị trang hướng dẫn kết nối lại; không hiển thị nội dung riêng tư đã tải trước. Khi online, nhấn Thử kết nối lại để quay về app.

OAuth Google/Facebook đã có code và test provider giả; đăng nhập thật cần chủ tài khoản điền client ID/secret trong oauth.env theo docs/dang-nhap-google-facebook.md. TURN giữ Hugging Face.

## Kết quả kiểm thử trước push

- Unit: 46/46 pass.
- E2E: 97/97 pass, không retry, không skip; bật KINNECT_MEDIA_E2E=1, gồm offline, polish và nhận hình WebRTC.
- Node, cloudflared, tunnel config và server.js đều tồn tại ở vị trí startup đang dùng.
- Bản công khai trả 200 cho HTML và SW v26; ios.js đăng ký URL worker mới; tokens/polish nằm trong precache.
- Không reboot máy, không tự bật OAuth khi chưa có khóa. Không commit oauth.env, turn.env hoặc mail.env.
