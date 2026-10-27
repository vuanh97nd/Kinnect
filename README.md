# Kinnect

[**Tải APK Android 0.9.4**](https://github.com/vuanh97nd/Kinnect/releases/download/v0.9.4/Kinnect-0.9.4-native.apk) · [Web mobile](https://app.kinnect.io.vn/)

Bản thử nghiệm **0.9.4**, versionCode **31**. Sửa APK báo nhầm “chọn MP4” với video MP4: nhận dạng nội dung, đọc tệp một lần, bỏ cổng kiểm tra metadata Android và giữ quyền đọc URI từ Thư viện.

[Mã nguồn v0.9.4](https://github.com/vuanh97nd/Kinnect/tree/v0.9.4) · [Ghi chú phát hành](https://github.com/vuanh97nd/Kinnect/releases/tag/v0.9.4)

Android 8+, package `app.kinnect.live`. Cài đè bản cũ để nâng cấp với cùng chứng chỉ ký. Giữ bỏ giới hạn 60 giây và 5/12 MB riêng từ 0.9.3; kích thước thực tế còn phụ thuộc bộ nhớ và hạ tầng mạng.

Đã build, xác minh chữ ký, kiểm tra tệp MP4 thật với URI/MIME giả lập JVM và các luồng API media. Chưa nghiệm thu trên điện thoại thật; chuyển container/codec ngoài MP4 phụ thuộc hỗ trợ Android.

## Chạy source

Checkout tag `v0.9.4`. Backend Node.js >=22.13: `npm ci`, `npm start`. Giữ DATA_DIR và cấu hình máy chủ khi cập nhật.

Build Windows: `python scripts/build-apk-windows.py`. Kiểm tra media Windows: `python scripts/test-native-media-windows.py` (JVM document-provider stubs, không phải giả lập Android). Build Linux: `scripts/prepare-android-tools.sh`, `scripts/build-apk.sh`. Giữ khóa ký cũ và không đưa khóa/token/database lên GitHub.

SHA-256 APK: `b3adf52fe27c5b9ee12d2e7d2f81f03fabdc2e98fa300fb7d1b6eb358ffbd9d4`
