# Phân chia mới — 2026-10-30

Quyết định mới thay thế cấu hình D1 identity trước đó:
- D1 kinnect-chat: hội thoại riêng/nhóm, thành viên, nội dung tin nhắn, receipt delivered/seen.
- PostgreSQL: tài khoản/password hash/salt, hồ sơ, phiên đăng nhập, ví xu và giao dịch.
- PC/R2: tệp ảnh/video; D1 chỉ giữ khóa tham chiếu attachment.

Đã tạo D1 và schema nền; chưa có Worker công khai, backend adapter, migration hay dữ liệu thật. Server vẫn SQLite.
kinnect-identity đang trống và không được dùng; không xóa database khi chưa có yêu cầu.

Trước production cần kiểm tra xác thực/suspended/blocked với nguồn PostgreSQL, quyền thành viên trên mọi lần đọc/ghi, thu hồi/quyền lịch sử khi rời nhóm, direct_pair chuẩn hóa và giới hạn đúng hai người.
Server tạo timestamp nhận tin; receipt chuyển đơn điệu, seen ngụ ý delivered; UNIQUE sender/nonce chống gửi lại trùng. D1 batch cần bảo đảm ghi message/receipt/thay đổi nhóm nguyên tử.
reply_to phải thuộc cùng hội thoại; kiểm tra app vì FK một mình chưa bảo đảm điều này. Không tin user ID/timestamp do client tự khai.
Cần chuyển cả reactions, pin, attachment, mute, unread và quyền riêng tư/xóa dữ liệu đang có trước khi chuyển hoàn toàn.
Dùng phân trang cursor theo created_at/id; không full scan toàn bộ chat.
Khi D1 lỗi không tự ghi sang SQLite/PostgreSQL riêng vì sẽ phân nhánh dữ liệu.
Giới hạn đọc/ghi D1 Free áp dụng cho tài khoản; các chỉ mục/receipt cũng tiêu tốn quota. Chưa đo dung lượng hoặc tải thực tế.

Áp dụng: npx wrangler d1 migrations apply kinnect-chat --remote --config cloud-chat/wrangler.jsonc
