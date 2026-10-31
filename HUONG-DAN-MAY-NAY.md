# Kinnect 0.3 trên máy này

Đang dùng nhánh feature/social-core với giao diện web sau đăng nhập đã cập nhật.
15 kiểm thử backend đạt trên Windows.

URL điện thoại hiện tại: https://app.kinnect.io.vn
Máy chủ và tunnel phải tiếp tục chạy. Tên miền app cố định, kết nối qua Cloudflare Tunnel.

Chạy lại backend: mở start-kinnect.cmd, giữ cửa sổ mở.
Chạy app và tunnel ẩn: mở start-kinnect-hidden.vbs. start-tunnel.cmd chỉ dùng khi cần tạo Quick Tunnel tạm thời.
Dừng bằng Ctrl+C trong mỗi cửa sổ chạy.
SECURE_COOKIES=1 dùng cho HTTPS; đăng nhập qua URL HTTPS ở trên.
Dữ liệu lưu trong data/kinnect.sqlite; không xóa thư mục data.
Video qua Internet vẫn cần TURN/SFU và kiểm thử thiết bị thật.

Website giới thiệu: https://kinnect.io.vn/
Web iOS: https://app.kinnect.io.vn/
