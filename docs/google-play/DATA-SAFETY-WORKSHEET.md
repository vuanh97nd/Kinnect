# Bảng đối chiếu Data safety — chưa phải tờ khai đã gửi

Phải xác nhận trên đúng AAB và hệ thống vận hành tại thời điểm gửi. “Thu thập” bao gồm dữ liệu gửi từ app lên máy chủ của chính chủ ứng dụng; không chỉ SDK bên thứ ba.

| Nhóm cần đối chiếu trong Console | Dữ liệu thực tế | Lựa chọn / mục đích |
|---|---|---|
| Personal info / Name, User IDs | Tên hiển thị, username, account ID | Tài khoản và hoạt động app; một số trường bắt buộc |
| Personal info / Email, Phone, Other personal info | Email OAuth/khôi phục; thông tin liên hệ hỗ trợ có thể gồm số điện thoại do người dùng nhập; tuổi, thành phố, giới, xu hướng, nghề nghiệp/trường học | Các trường bổ sung tự nguyện; tài khoản, hỗ trợ, hồ sơ công khai theo lựa chọn |
| Health information / Other personal info — đối chiếu định nghĩa hiện hành | Chiều cao/cân nặng do người dùng tự điền | Lọc/hiển thị hồ sơ, không chẩn đoán, không Health Connect. Không bỏ qua chỉ vì app không phải ứng dụng y tế |
| Approximate location | Vị trí từ ACCESS_COARSE_LOCATION khi bật quanh đây | Tùy chọn; tìm gần; có tắt/xóa; không background location |
| Photos and videos | Avatar/cover, ảnh/bài/video/tin, tệp gửi trong chat | Tùy chọn; chức năng app và kiểm duyệt; quyền chọn từng tệp |
| Audio files / Voice or sound recordings | Tin nhắn âm thanh; dữ liệu mic cuộc gọi/live | Tùy chọn; truyền cuộc gọi/live thời gian thực; tin âm thanh được lưu theo tin nhắn |
| Messages / Other in-app messages | Tin nhắn riêng/nhóm, trò chuyện live, hỗ trợ | Chức năng giao tiếp; hỗ trợ AI chỉ sau opt-in riêng |
| App activity / Other user-generated content, App interactions | Bài viết, bình luận, lượt thích/theo dõi, báo cáo, lựa chọn đồng ý | Chức năng app và phòng chống lạm dụng |
| Device or other IDs | Cookie phiên, mã thiết bị để ghi nhớ tài khoản, endpoint web push ở bản web | Bảo mật/duy trì đăng nhập. Không Advertising ID, không bán dữ liệu quảng cáo |
| Diagnostics | Mã lỗi và dữ liệu chẩn đoán do chức năng báo lỗi/crash tạo ra | Kiểm tra đúng log được tải lên; không đánh có SDK phân tích nếu thực tế không có |

## Chia sẻ và nhà cung cấp

- Hosting/Cloudflare, Workers AI/NVIDIA, Google/Facebook OAuth và hạ tầng cuộc gọi phải được đối chiếu cùng điều khoản xử lý dữ liệu. Không mặc định tất cả thuộc ngoại lệ “service provider” khi chưa xác nhận quan hệ/giới hạn sử dụng.
- Với dữ liệu do người dùng chủ động công khai/gửi cho thành viên khác, đọc đúng ngoại lệ của biểu mẫu; ngoại lệ “sharing” không tự loại nghĩa vụ khai “collection”.
- Không hứa không lưu phía nhà cung cấp AI khi chưa xác minh điều khoản. Nếu nhà cung cấp/khóa API chỉ cho phép thử nghiệm hoặc không phù hợp dữ liệu cá nhân, tắt dịch vụ đó trước Production.
- Không có SDK quảng cáo, bán dữ liệu, danh bạ, SMS hoặc lịch sử cuộc gọi hệ thống trong bản này.

## Kiểm soát/bảo mật

- Truyền bằng HTTPS; không có mã hóa đầu cuối cho tin nhắn.
- Có xóa tài khoản trong app và URL ngoài app; xử lý dữ liệu đang hoạt động ngay khi yêu cầu thành công. Backup cần quản lý theo thời hạn và quy trình phục hồi đã công bố.
- Đối chiếu khai báo với Privacy Policy; không tự khẳng định đã điền/được duyệt khi chưa thao tác Console.
