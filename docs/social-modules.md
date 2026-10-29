# Các module giao diện social

`public/social.js` giữ bootstrap, phiên đăng nhập, điều hướng/history, header popup, notifications, settings/admin và video viewer. File giảm từ 2.486 xuống 1.734 dòng.

Bốn factory nhận `socialContext`, trả các hàm giao diện cho entry point:

- `social-feed.js`: stories, composer, post cards, news và feed.
- `social-discover.js`: thẻ thành viên, danh tính, bộ lọc khám phá và sự kiện bật vị trí.
- `social-profile.js`: field/presets, connections, private album và trang hồ sơ.
- `social-messenger.js`: inbox/sidebar, recipient/group picker, message actions, attachments, typing và direct/group chat.

Context dùng getter để đọc trạng thái hiện tại sau mỗi lần đăng nhập hoặc chuyển trang, không chụp lại `me`/navigation revision khi khởi tạo module. Chỉ các trạng thái cần thay đổi được cấp setter: người dùng, mục feed/discover, vị trí và các callback refresh/cleanup. Tác vụ bất đồng bộ tiếp tục kiểm tra navigation revision như trước.

Các factory chỉ khai báo hàm; entry point khởi tạo chúng trước lần gọi API `/me` và render đầu tiên. Dependency vòng giữa giao diện profile/chat/feed đi qua context, tránh import vòng giữa module.

Server whitelist bốn URL JavaScript mới. Service worker cache thêm chúng và tăng phiên bản cache. Khi thêm module mới, cập nhật cả whitelist server và danh sách static của SW.

Các phần chưa tách: video viewer, notifications, settings/admin và bootstrap. `lib/social.js` và CSS chưa được refactor theo domain trong phiên này. `public/live.css` vẫn chứa bản nhúng của `calls.css`/`messenger.css`; đây là phần trùng lặp nên dọn trong một thay đổi riêng có kiểm tra layout.
