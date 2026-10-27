# Kinnect

[**Tải APK Android mới nhất**](https://github.com/vuanh97nd/Kinnect/releases/latest) · [Web mobile](https://app.kinnect.io.vn/)

Bản mới nhất: **0.8.6 — Android thử nghiệm**. Tải file `Kinnect-0.8.6-native.apk` ở Assets của release; file `.sha256` dùng để kiểm tra tính toàn vẹn. Chưa nghiệm thu thao tác/giao diện trên điện thoại thật.

[Mã nguồn đúng bản v0.8.6](https://github.com/vuanh97nd/Kinnect/tree/v0.8.6) · [Ghi chú phát hành](https://github.com/vuanh97nd/Kinnect/releases/tag/v0.8.6)

Ứng dụng Android dùng Android Views native, package `app.kinnect.live`, Android 8+, target SDK 35. Có tài khoản, bảng tin, tin 24 giờ, khám phá, bạn bè, chat/nhóm/tệp, video ngắn, hồ sơ và quyền riêng tư. Đăng nhập Google/Facebook hoạt động khi máy chủ đã cấu hình nhà cung cấp.

## Bản 0.8.6

Khôi phục nhãn Bảng tin, Khám phá, Video, Live khi chuyển mục. Giảm nhẹ các tiêu đề lớn sau đăng nhập và dùng đúng icon web hiện tại. Giữ nguyên chức năng và mã Live.

Đã build, xác minh chữ ký và đối chiếu 83 icon với web. Chưa nghiệm thu trên điện thoại thật. Xem ghi chú phát hành về giới hạn kiểm tra theme và các chức năng còn cần hoàn thiện từ bản trước.

## Chạy source của bản phát hành

Checkout tag `v0.8.6` trước khi xem/build phiên bản này. Nhánh `main` có thể chưa chứa toàn bộ source phát hành; tag liên kết ở trên là mốc đúng bản APK.

Backend Node.js >=22.13: `npm ci`, sau đó `npm start`. Database và cấu hình tài khoản/máy chủ không nằm trong APK. Giữ và sao lưu DATA_DIR đang dùng trước khi cập nhật máy chủ.

Build native trên Windows: `python scripts/build-apk-windows.py`, sau khi chuẩn bị toolchain Android theo script/tài liệu trong tag. Build Linux dùng `scripts/prepare-android-tools.sh` và `scripts/build-apk.sh`. Giữ khóa ký hiện có để Android nhận bản nâng cấp; không đưa keystore, token, cấu hình OAuth/email hoặc database lên GitHub.

APK hiện được ký cho thử nghiệm và chưa dành cho Google Play. Mã nguồn, bản build và ghi chú chi tiết được gắn với từng tag trong Releases.
