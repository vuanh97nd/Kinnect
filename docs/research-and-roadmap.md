# Nguồn tham khảo và phạm vi Kinnect

Ngày kiểm tra: 2026-10-24. Kinnect dùng thương hiệu, biểu tượng và giao diện riêng. Không sao chép mã, hình ảnh hoặc giao diện HeeSay.

## HeeSay: kết quả có thể xác minh

- Đã truy vấn [GitHub search: heesay](https://github.com/search?q=heesay&type=repositories). Tại thời điểm kiểm tra chỉ có một kết quả: [IKONIXPortal/Heesay](https://github.com/IKONIXPortal/Heesay).
- Đã đọc trang repo và index.html: nội dung là **IKONIX Portal**, gồm HTML và JSON. Không tìm thấy bằng chứng từ nhà phát hành liên kết repo này với mã nguồn Android HeeSay chính thức. Không coi tên repo là bằng chứng về tính chính thức.
- Tệp LICENSE ở đường dẫn chuẩn trả về 404; không thấy khai báo giấy phép trên trang repo. Chưa xác định được giấy phép cho phép tái sử dụng: **không lấy mã từ repo này**. Điều này không khẳng định mọi tệp đều không có điều khoản riêng.
- Tìm thêm `blued android` trả nhiều kết quả Bluetooth/BlueDroid không liên quan, không xác định được mã ứng dụng chính thức.
- Truy cập `www.heesay.com`, Google Play và App Store bị HTTP proxy từ chối 403. **Chưa hoàn tất khảo sát tính năng hiện hành từ nguồn chính thức**; không khẳng định tìm thấy mã nguồn chính thức và không khẳng định tính năng Kinnect dưới đây đã được xác minh là tính năng HeeSay.

Các nhóm tài khoản, hồ sơ, khám phá, theo dõi, chat, bảng tin, live, quà tặng và thông báo là phạm vi sản phẩm người dùng yêu cầu. Khi truy cập được các nguồn chính thức, cần xác nhận website/listing thuộc nhà phát hành, ghi phiên bản/ngày và nguồn cho từng tính năng trước khi so sánh.

## Repo tham khảo và giấy phép

| Repo | Giấy phép kiểm tra | Sử dụng hiện tại |
| --- | --- | --- |
| [LiveKit](https://github.com/livekit/livekit), [LICENSE](https://github.com/livekit/livekit/blob/master/LICENSE) | Apache 2.0, đã đọc từ raw.githubusercontent.com | Ứng viên SFU tự lưu trữ giai đoạn sau; chưa tích hợp, không chép mã. Không phải mã HeeSay. |
| [Mastodon](https://github.com/mastodon/mastodon), [LICENSE](https://github.com/mastodon/mastodon/blob/main/LICENSE) | GNU AGPL v3, đã đọc từ raw.githubusercontent.com | Tham khảo hệ thống xã hội; chưa tích hợp, không chép mã. Cần rà nghĩa vụ AGPL nếu tái sử dụng. Không phải mã HeeSay. |
| [ws](https://github.com/websockets/ws), [LICENSE](https://github.com/websockets/ws/blob/master/LICENSE) | MIT, metadata và LICENSE của gói cài đặt | Thư viện WebSocket đang dùng, khóa phiên bản trong package-lock.json. |
| [Playwright](https://github.com/microsoft/playwright), [LICENSE](https://github.com/microsoft/playwright/blob/main/LICENSE) | Apache 2.0, LICENSE của gói cài đặt | Công cụ kiểm thử trình duyệt, không phải mã ứng dụng tham khảo. |

Không có dịch vụ trả phí được tạo, không thanh toán hoặc quà tặng quy đổi tiền thật.

## Giai đoạn 1 — phần cốt lõi đã triển khai

- Đăng ký/đăng nhập username, scrypt + salt, cookie HttpOnly SameSite=Strict, session lưu SQLite và đăng xuất vô hiệu hóa session.
- Kiểm tra ngày sinh hợp lệ và tự khai từ 18 tuổi, đồng ý quy tắc. Không công khai ngày sinh, chưa xác minh tuổi/danh tính.
- Hồ sơ tên/bio/sở thích, một ảnh PNG/JPEG/WebP tối đa 1 MB lưu SQLite. Chỉ kiểm tra chữ ký định dạng cơ bản, chưa chuẩn hóa hoặc quét nội dung ảnh.
- Khám phá xếp theo số sở thích trùng, tìm tên/sở thích; thuật toán xác định, không phải AI. Không dùng GPS.
- Theo dõi; chat mặc định chỉ khi cùng theo dõi. Tùy chọn nhận tin từ mọi thành viên.
- Chat riêng lưu bền, hộp thư, thông báo trong app. Cập nhật chat mỗi 4 giây, thông báo mỗi 15 giây; chưa push Android, chưa mã hóa đầu cuối.
- Bảng tin văn bản cho thành viên hoặc người theo dõi, xóa bài của mình; chưa ảnh bài viết, bình luận hoặc lượt thích.
- Ẩn khỏi khám phá; chặn/bỏ chặn hai chiều, xóa quan hệ theo dõi, lọc bảng tin/thông báo, ngăn chat. Chặn host khiến viewer rời phòng; live chat lọc những người chặn nhau.
- Báo cáo tài khoản/bài/tin nhắn/người phát. CLI cục bộ xem báo cáo, ẩn/hiện bài, đình chỉ/khôi phục tài khoản, đóng báo cáo và audit log. Chưa kiểm duyệt tự động/24 giờ.
- Live yêu cầu đăng nhập, lấy tên từ tài khoản, kiểm tra session; vẫn P2P tối đa 6 người xem và chưa STUN/TURN/SFU.
- Android WebView có màn hình chọn HTTPS server; không phải Kotlin/Compose native.

## Giai đoạn 2 — video Internet và Android

- Tích hợp TURN với credentials ngắn hạn hoặc LiveKit SFU tự lưu trữ; đánh giá upload, NAT/IP, TLS và tài nguyên máy Windows.
- Kiểm thử hai điện thoại thật trên hai mạng: video/audio, xoay màn hình, mất mạng, reconnect và ra nền.
- Chuyển Android sang Gradle/Android Studio để build Windows; script hiện dùng toolchain Linux cục bộ.
- Phân trang, trạng thái giao nhận và push notifications nếu hạ tầng được chấp thuận.

## Giai đoạn 3 — quà tặng thử nghiệm và quản trị

- Quà tặng miễn phí chỉ là hiệu ứng/đếm tương tác, có hạn mức chống spam; chưa triển khai. Không thanh toán, mua xu hoặc rút tiền.
- Album ảnh, bình luận, nhóm, quyền riêng tư chi tiết và quản trị báo cáo có phân quyền.
- Khôi phục mật khẩu, xóa/xuất dữ liệu, quản lý session, thời hạn lưu dữ liệu và sao lưu/khôi phục đã diễn tập.
- Quy trình xác minh tuổi và xử lý quấy rối/nội dung nhạy cảm. Cổng tự khai chưa đủ cho vận hành công khai.

## Kiểm chứng

Integration tests kiểm tra 18+, auth/CSRF, quyền DM/bài viết, chặn/báo cáo, SQLite sau mở lại, ảnh, session đình chỉ/đăng xuất, live và giới hạn phòng. Playwright kiểm tra luồng hai tài khoản ở viewport điện thoại trên Chromium. Chưa kiểm thử APK trên Android thật hoặc video Internet; không tuyên bố ngang tính năng/chất lượng HeeSay.

### Kết quả chẩn đoán media trong cloud

Đã chạy kiểm tra nhận khung hình bằng camera giả: host có videoWidth=1280 và readyState=4, hai phía có offer/answer, nhưng viewer videoWidth=0, ICE còn `new`; kiểm tra này **thất bại**. Kiểm tra chính sách Chromium tại `/etc/chromium/policies/managed/misc.json` xác nhận `WebRtcIPHandling=disable_non_proxied_udp`. Bản app chưa có TURN, nên môi trường này không cung cấp đường truyền P2P cần thiết. Không sửa/vô hiệu hóa chính sách mạng để làm test đạt.

Kiểm tra khung hình được giữ nguyên assertion và tách thành test opt-in `KINNECT_MEDIA_E2E=1`; mặc định **skipped**, không tính là media đã đạt. Test browser riêng xác minh camera giả phía host, phòng/chat/điều khiển và dừng live khi ra nền, không giả làm test nhận video. Cần chạy test frames trên hạ tầng cho phép hoặc với TURN sau giai đoạn 2. Chưa khẳng định code media hết lỗi hoặc đã chạy trên điện thoại thật.

### Phụ thuộc bảo mật

`npm audit` phát hiện ws 8.18.3 của bản nền nằm trong GHSA-58qx-3vcg-4xpx và GHSA-96hv-2xvq-fx4p. Đã đọc advisory, nâng lên ws 8.22.0 (bản vá tương ứng từ 8.20.1/8.21.0), khóa trong package-lock.json và chạy lại kiểm thử. Audit toàn bộ dependency/devDependency sau nâng cấp báo 0 lỗ hổng đã biết tại thời điểm chạy; đây không phải chứng nhận không có lỗi bảo mật.

## Cập nhật tiến độ 0.3.0

Phần mô tả 0.2 ở trên là lịch sử. 0.3 đã chuyển màn hình xã hội sang Android Views native; riêng Live còn WebView/WebRTC. Đăng ký mới dùng xác nhận 18+ không nhập ngày sinh, mật khẩu >=6. Có role admin/API quản trị và CLI promote tài khoản có sẵn, vị trí gần đúng tự nguyện/khám phá quanh đây, quà miễn phí và video ngắn MP4 với thích/bình luận/báo cáo. Chi tiết giới hạn, vận hành, quyền riêng tư và cập nhật Windows ở README và release notes 0.3.0. Chưa có kiểm thử native trên thiết bị/emulator, TURN/SFU, push hoặc trình dựng video. Kết quả khảo sát HeeSay chính thức vẫn chưa hoàn tất do các miền bị chặn; không suy diễn các tính năng đã làm thành bằng chứng tương đương HeeSay.
