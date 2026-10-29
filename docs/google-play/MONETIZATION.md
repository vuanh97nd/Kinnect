# Cửa hàng Kinnect và Studio Pro — 1.2.0 (102)

Sản phẩm một lần, không tiêu hao: `kinnect_style_aurora`, `kinnect_style_ocean`, `kinnect_style_sunset`, `kinnect_studio_pro`. Ba phong cách áp dụng khung avatar và màu hội thoại. Studio Pro cung cấp ba mẫu Aurora, Travel, Cinema trong trình sửa video Android. Bản web cho xem thử và áp dụng phong cách đã sở hữu. Giá 29.000/149.000 VND trong bản giới thiệu là dự kiến; giá thanh toán chỉ lấy từ Google Play.

## Mở bán

1. Hoàn tất tài khoản Play Console, xác minh và thiết lập hồ sơ người bán. Hồ sơ hiện còn chờ giải quyết hỗ trợ đăng ký.
2. Tạo bốn one-time products đúng ID, kích hoạt purchase options/offers và giá, tải AAB lên nhánh kiểm thử. Không đổi SKU sau khi có giao dịch.
3. Bật Android Publisher API và cấp tài khoản dịch vụ quyền xem đơn hàng, quản lý giao dịch cần thiết cho ứng dụng này. Lưu JSON khóa ở đường dẫn riêng ngoài Git.
4. Tạo `billing.env` trên máy chủ với PLAY_STORE_ENABLED=true, PLAY_SERVICE_ACCOUNT_FILE=đường dẫn JSON riêng, PLAY_PURCHASE_TOKEN_KEY=khóa ngẫu nhiên 32 byte biểu diễn bằng 64 ký tự hex. Không đưa các giá trị vào mã nguồn, hồ sơ phát hành hoặc ảnh chụp. Sao lưu khóa mã hóa cùng dữ liệu; thay khóa cần di chuyển mã hóa token trước.
5. Khởi động lại máy chủ. Kiểm thử bằng license tester: mua thành công, hủy, pending, mất mạng, mua trùng, khôi phục, đổi tài khoản, hoàn tiền, xóa tài khoản. Chỉ mở production sau kiểm thử thật; chưa có bằng chứng giao dịch thật trong bản bàn giao này.

Server xác minh trạng thái và sản phẩm từ Google, ràng buộc obfuscated account ID, acknowledge trước khi cấp quyền. Token lưu mã hóa AES-GCM. Client không tự cấp quyền. Kiểm tra lại khi truy cập sau một giờ; quyền hết hiệu lực khi quá 24 giờ chưa xác minh lại. Chưa tích hợp RTDN, do đó thu hồi sau hoàn tiền không tức thời. Xóa tài khoản xóa dữ liệu mua trên Kinnect, không tự hoàn tiền hay xóa lịch sử Google.

Bản Google Play dùng Billing Library 9.1.0 và không có trình cài APK bên ngoài. Bản tải trực tiếp 1.0.10 không có checkout; không dẫn tới thanh toán ngoài. Không có thuê bao, boost, quà tặng hay ví tiền trong đợt này.

## Bằng chứng

101 kiểm thử backend đạt; kiểm tra manifest, chữ ký và thư viện 16 KB đạt; LanguageAudit và PlayPolicyAudit đạt trên Android 16 giả lập. VI/EN đạt kiểm tra căn giữa ở 320 dp với font 130%. Web cửa hàng không tràn ở 320/390/1366 px. Chưa xác minh trên điện thoại thật và chưa được Google phê duyệt.
