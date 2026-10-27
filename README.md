# Kinnect

[**Tải APK Android mới nhất**](https://github.com/vuanh97nd/Kinnect/releases/latest) · [Web mobile](https://app.kinnect.io.vn/)

Bản mới nhất: **0.8.5 — Android thử nghiệm**. Tải file `Kinnect-0.8.5-native.apk` ở Assets của release; file `.sha256` dùng để kiểm tra tính toàn vẹn. Chưa nghiệm thu thao tác/giao diện trên điện thoại thật.

[Mã nguồn đúng bản v0.8.5](https://github.com/vuanh97nd/Kinnect/tree/v0.8.5) · [Ghi chú phát hành](https://github.com/vuanh97nd/Kinnect/releases/tag/v0.8.5)

Ứng dụng Android dùng Android Views native, package `app.kinnect.live`, Android 8+, target SDK 35. Có tài khoản, bảng tin, tin 24 giờ, khám phá, bạn bè, chat/nhóm/tệp, video ngắn, hồ sơ và quyền riêng tư. Đăng nhập Google/Facebook hoạt động khi máy chủ đã cấu hình nhà cung cấp.

## Bản 0.8.5

Giữ cấu trúc chức năng của web mobile và ưu tiên biểu tượng. Sửa giữ bản nháp/gửi lỗi, vị trí theo lựa chọn, nhóm, bình luận và đích thông báo; bổ sung trường hồ sơ/quyền ẩn từng mục, khôi phục bằng mã email, tải tệp và người xem tin. Mã Live được giữ nguyên so với trước đợt rà soát.

Đã qua 57 kiểm tra backend, 9 luồng web tham chiếu, 6 kiểm tra cấu trúc APK, parser của 185 đường vẽ, build và chữ ký. Các kiểm tra này không thay thế nghiệm thu native trên thiết bị thật. Một số phần @, thẻ album trong chat, quản trị nâng cao và push khi app đóng còn cần hoàn thiện.

## Chạy source của bản phát hành

Checkout tag `v0.8.5` trước khi xem/build phiên bản này. Nhánh `main` có thể chưa chứa toàn bộ source phát hành; tag liên kết ở trên là mốc đúng bản APK.

Backend Node.js >=22.13: `npm ci`, sau đó `npm start`. Database và cấu hình tài khoản/máy chủ không nằm trong APK. Giữ và sao lưu DATA_DIR đang dùng trước khi cập nhật máy chủ.

Build native trên Windows: `python scripts/build-apk-windows.py`, sau khi chuẩn bị toolchain Android theo script/tài liệu trong tag. Build Linux dùng `scripts/prepare-android-tools.sh` và `scripts/build-apk.sh`. Giữ khóa ký hiện có để Android nhận bản nâng cấp; không đưa keystore, token, cấu hình OAuth/email hoặc database lên GitHub.

APK hiện được ký cho thử nghiệm và chưa dành cho Google Play. Mã nguồn, bản build và ghi chú chi tiết được gắn với từng tag trong Releases.
