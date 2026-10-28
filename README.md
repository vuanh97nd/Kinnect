# Kinnect

[**Tải APK Android 0.9.5**](https://github.com/vuanh97nd/Kinnect/releases/latest) · [Trang chủ](https://kinnect.io.vn/) · [Web mobile](https://app.kinnect.io.vn/)

**0.9.5 — Android thử nghiệm.** Chỉnh ảnh/video trước khi đăng: timeline, cắt đoạn, tốc độ, chữ, nhạc, làm đẹp và hiệu ứng. Có lưu riêng về máy, tiếp tục đăng và tiến độ tải lên. Live có điều khiển làm đẹp.

Tải `Kinnect-0.9.5-native.apk` trong Assets. [Ghi chú và giới hạn kiểm thử](https://github.com/vuanh97nd/Kinnect/releases/tag/v0.9.5) · [Mã nguồn bản phát hành](https://github.com/vuanh97nd/Kinnect/tree/v0.9.5).

Chưa nghiệm thu trên Android thật. Video có hiệu ứng được xuất theo thời gian thực; chức năng dựng một clip, chưa gồm ghép nhiều clip/chuyển cảnh. Ứng dụng Android Views native, Android 8+, package `app.kinnect.live`. Giữ chứng chỉ ký cùng các bản trước.

Web và backend: Node.js, chạy `npm install` và `npm start`. Build Android bằng `python scripts/build-apk-windows.py` sau khi chuẩn bị toolchain. Không đưa dữ liệu người dùng, khóa ký, cookie hoặc thông tin đăng nhập vào repository.
