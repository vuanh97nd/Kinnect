# Khóa upload và chữ ký app

- Khóa **upload** cục bộ nằm trong `work/play-signing/upload.jks`; mật khẩu ở tệp riêng cùng thư mục. Cả thư mục bị loại khỏi Git, ZIP mã nguồn và bộ tệp công khai. Không gửi private key/mật khẩu qua chat, email hoặc GitHub.
- Public upload certificate: `dist/google-play/upload-certificate.pem`. Đây không phải private key.
- `build-play-windows.py` dùng lại khóa upload hiện có. Chỉ cho phép tạo lần đầu với `--initialize-upload-key`; không tự tạo khóa thay thế trên máy mới.
- Sao lưu khóa và mật khẩu vào nơi bảo mật trước khi chuyển máy. Khóa upload và **app signing key** của Google Play là hai vai trò khác nhau.

## Giữ khả năng cập nhật từ APK website

Chứng chỉ ký APK website hiện có SHA-256:

`d8809c1e21f00ccf96984b37123d3d916d2e103bfa1dc2032043f47bb3b9988d`

Nếu Play App Signing dùng một app-signing key khác, Google Play không thể cập nhật đè lên bản website đang cài cùng package. Chủ ứng dụng cần chọn luồng **nhập khóa ký hiện có** trong Play Console, làm theo PEPK/công cụ và khóa mã hóa do Google cung cấp. Không nhầm khóa upload mới với khóa ký APK website.

Không tự thay khóa ký website, không đổi package hoặc gỡ app của người dùng để “sửa” lỗi chữ ký. Nếu quyết định chuyển chữ ký/package, cần kế hoạch di chuyển và thông báo riêng.
