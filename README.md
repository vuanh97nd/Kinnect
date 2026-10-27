# Kinnect

[**Tải APK Android 0.9.3**](https://github.com/vuanh97nd/Kinnect/releases/download/v0.9.3/Kinnect-0.9.3-native.apk) · [Web mobile](https://app.kinnect.io.vn/)

Bản thử nghiệm **0.9.3**, versionCode **30**. Bỏ giới hạn 60 giây và giới hạn dung lượng 5/12 MB riêng trong luồng đăng ảnh/video. Camera mặc định quay đến khi bấm dừng.

[Mã nguồn v0.9.3](https://github.com/vuanh97nd/Kinnect/tree/v0.9.3) · [Ghi chú phát hành](https://github.com/vuanh97nd/Kinnect/releases/tag/v0.9.3)

Android 8+, package `app.kinnect.live`, giao diện Android Views native. Cài APK lên bản cũ để nâng cấp với cùng chứng chỉ ký.

Đã build, xác minh chữ ký và kiểm tra API nhận, lưu nguyên vẹn media 13 MB với metadata video 125 giây. Chưa nghiệm thu thao tác/phát video trên điện thoại thật. Kích thước thực tế phụ thuộc bộ nhớ thiết bị, máy chủ và đường truyền; API máy chủ cần cập nhật cùng tag để nhận video trên 60 giây.

## Chạy source

Checkout tag `v0.9.3`. Backend Node.js >=22.13: `npm ci`, `npm start`. Giữ DATA_DIR và cấu hình máy chủ hiện có khi cập nhật; không đưa database, keystore, token hoặc khóa OAuth lên GitHub.

Build Windows: `python scripts/build-apk-windows.py` sau khi chuẩn bị toolchain theo script. Build Linux: `scripts/prepare-android-tools.sh`, `scripts/build-apk.sh`. Giữ khóa ký cũ khi nâng cấp.

SHA-256 APK: `68fa993be1755a80ea06095994f5526028c7e06d61ccd9cda4207780c99a43bb`
