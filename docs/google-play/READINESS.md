# Kinnect Google Play — bản chuẩn bị 1.1.1 / build 101

Đơn vị hiển thị/liên hệ do chủ ứng dụng cung cấp: **Mr Ánh — anhvn53@wru.vn**.

## Tệp và quy trình

- AAB để tải lên **Internal testing**: `dist/google-play/Kinnect-1.1.1-play.aab`.
- APK sinh từ AAB dành cho QA: `dist/google-play/Kinnect-1.1.1-play-test.apk`. Không đưa APK này lên nút tải website; chữ ký upload khác chữ ký APK website.
- Kiểm tra máy: `dist/google-play/artifact-checks.json` và các tệp SHA-256 bên cạnh.
- Play overlay: `android/app/src/play/AndroidManifest.xml`; package `app.kinnect.live`, target API 36, min API 26. Manifest chính vẫn phục vụ kênh APK website.
- Công cụ: `python scripts/prepare-play-tools.py`, `python scripts/prepare-play-dependencies.py`, `python scripts/build-play-windows.py`, `python scripts/check-play-artifact.py`.
- Cần toolchain Android/JDK nền đã được chuẩn bị tại `work/android-tools`. Các tệp tải về được kiểm checksum. Không tải private key từ GitHub.

## Những việc đã thực hiện trong mã

- Tách kênh Play, không đóng gói trình cài APK/provider/quyền cài gói ngoài. Kiểm tra cập nhật mở Google Play.
- Bỏ quyền đọc rộng ảnh/video, quyền bỏ tối ưu pin, quyền truy cập DND và quyền không dùng trong biến thể Play; chọn tệp qua bộ chọn hệ thống. Camera/micro được hỏi theo hành động gọi/quay.
- Đồng bộ tin nhắn nền là tùy chọn người dùng, có thông báo và nút Dừng. Mục đích là tiếp tục tin nhắn giữa web và điện thoại; khai báo FGS remoteMessaging phải phản ánh đúng tính năng này. Khi tắt, không cam kết nhận cuộc gọi/tin nhắn liên tục ở nền.
- Xóa tài khoản trong app và ngoài app; xóa dữ liệu hoạt động, thu hồi phiên/ghi nhớ, xóa nội dung gửi và chuyển chủ nhóm có thành viên khác. Không thay bằng đình chỉ tài khoản.
- Xác nhận sử dụng dữ liệu trước khi đăng/gửi nội dung; nhận báo cáo và xóa tài khoản vẫn khả dụng khi chưa đồng ý. AI hỗ trợ mặc định tắt, bật sau xác nhận riêng và có thể rút lại.
- Chính sách quyền riêng tư, quy tắc/điều khoản, CSAE/CSAM và liên hệ dùng chung giữa website và native. Báo cáo tin nhắn AI dùng chính báo cáo tin nhắn trong app.
- Dọn mã khôi phục hết hạn/phiên hết hạn; yêu cầu khôi phục tối đa 90 ngày. Các bản sao lưu nhận diện được trong `data/backups` được dọn sau 30 ngày. Các bản sao lưu thủ công ở nơi khác phải được chủ vận hành đưa vào cùng chính sách; không được khôi phục tài khoản đã xóa.
- Nâng OkHttp lên 4.12.0, Okio JVM 3.6.0 và Kotlin 1.9.10; tra cứu OSV không trả cảnh báo cho các phiên bản đó tại thời điểm kiểm tra. NPM production audit không có cảnh báo. Đây không phải chứng nhận không còn lỗ hổng.
- Đóng gói thông báo giấy phép thư viện/font; minh họa onboarding của Play dùng ảnh mặc đầy đủ, có nhãn minh họa.

## Bằng chứng đã kiểm tra

- 97 kiểm thử backend/AI/Worker đạt, gồm xóa thật/rollback/chống yêu cầu khác nguồn, đồng ý dữ liệu, rút lựa chọn AI và giới hạn lưu dữ liệu.
- Trình duyệt mobile/PC: luồng đồng ý dữ liệu, hủy/đồng ý, trang xóa ngoài app, xác nhận sai/đúng, thu hồi phiên; streaming AI không trùng tin.
- Android 16 emulator, `getconf PAGE_SIZE=16384`: cài APK sinh từ AAB, target 36, release không debuggable, không có installer/quyền bị loại; ảnh onboarding đọc được; WebRTC factory nạp native library; chính sách và xóa tài khoản hiển thị đúng.
- Kiểm tra thêm font scale 1.3 trên màn hình 840×1920; thông báo đồng ý dài cuộn tới nút hành động.
- `bundletool validate`, ký AAB, sinh APK bằng bundletool, căn chỉnh ZIP và ELF 64-bit 16 KB đã đạt. Cảnh báo certificate tự ký của jarsigner là bình thường với khóa Android, không cần chứng chỉ CA web.

## Bắt buộc hoàn tất trong Play Console — không được tự xác nhận thay chủ ứng dụng

1. Xác minh tài khoản nhà phát triển bằng tên pháp lý và quốc gia thật. Chưa có thông tin về loại tài khoản (cá nhân/tổ chức), quốc gia hoặc trạng thái xác minh. Không dùng “Mr Ánh” để thay thế giấy tờ pháp lý khi Console yêu cầu.
2. Chọn đúng Social/Dating theo chức năng chính, khai đối tượng **18+**, dùng công cụ Console chặn trẻ vị thành niên khi thuộc phạm vi. Hoàn thành IARC bằng nội dung thực tế, không tự đặt nhãn xếp hạng trước khi trả lời bảng hỏi.
3. Nhập URL quyền riêng tư, xóa tài khoản và CSAE/CSAM trong `CONSOLE-FIELDS.md`; chỉ xác nhận child-safety khi Mr Ánh thực sự vận hành quy trình báo cáo và là đầu mối liên hệ.
4. Hoàn thành Data safety theo `DATA-SAFETY-WORKSHEET.md`, đối chiếu cả máy chủ, OAuth, AI, SDK và mã định danh thiết bị ghi nhớ. Chia sẻ công khai do người dùng chủ động vẫn phải đối chiếu đúng biểu mẫu, không đánh “không thu thập”.
5. Khai foreground service remoteMessaging và full-screen intent cho cuộc gọi, cung cấp video tính năng thực tế. Cần nhận kết quả xét duyệt quyền từ Google; mã và tài liệu không thay thế quyết định này.
6. Thiết lập Play App Signing và khóa upload. Nếu muốn nâng cấp từ APK website đã cài, phải giữ chữ ký app tương thích bằng luồng nhập khóa hiện có; không tùy tiện để Google tạo một app-signing key khác. Xem `SIGNING.md`.
7. Cấp tài khoản reviewer thường, không phải admin, truy cập được toàn bộ chức năng cần đánh giá; không bắt reviewer liên hệ email để mở khóa chức năng. Giữ thông tin đăng nhập riêng trong App access, không đưa lên GitHub.
8. Tải AAB lên Internal testing, chạy Pre-launch report và sửa lỗi phát sinh. Nếu tài khoản cá nhân thuộc diện áp dụng, chạy closed testing tối thiểu 12 người liên tục 14 ngày rồi xin quyền Production.
9. Kiểm tra gọi thoại/video, nhận cuộc gọi khóa màn hình, từ chối quyền, chuyển Wi-Fi/4G, livestream dài, xóa tài khoản OAuth và phục hồi mạng trên điện thoại thật. Kiểm thử emulator/JNI không chứng minh các trường hợp này đã đạt.
10. Chủ vận hành xác nhận quyền sử dụng media/nhạc, điều khoản nhà cung cấp AI, quản lý backup và tiếp nhận email thật. Không phát hành khi máy chủ phụ thuộc vào việc máy cá nhân còn bật/mạng ổn định mà chưa có phương án vận hành.

Không có quy trình kỹ thuật nào bảo đảm 100% không bị từ chối. Trạng thái hiện tại là **ứng viên để kiểm thử trên Play**, không phải chứng nhận được Google phê duyệt.

## Yêu cầu xóa khi tài khoản không đăng nhập được

Trang xóa ngoài app cung cấp kênh email riêng. Chủ vận hành xác minh quyền sở hữu, dừng server rồi dùng `node scripts/delete-account-owner.mjs --username USERNAME` để xem dry run; chỉ thực thi khi có yêu cầu đã xác minh bằng `--execute --confirm USERNAME --verified-request PRIVATE_REFERENCE`. Khởi động lại server sau thao tác để đóng socket/cuộc gọi cũ. Không dùng đình chỉ như thay thế cho xóa; không yêu cầu người dùng gửi mật khẩu/OTP qua email.

## Bộ bàn giao cuối

AAB 1.1.1 (101), target API 36; kiểm tra runtime Android 16 với PAGE_SIZE=16384. 97 kiểm thử Node đạt. Đã tạo tài khoản reviewer thường; thông tin riêng tại work/play-reviewer/APP-ACCESS-PRIVATE.txt, không nằm trong Git hoặc ZIP công khai. Ảnh chụp thật 1080×1920: hồ sơ, cài đặt và quyền riêng tư. Chưa tải lên Play Console, chưa có Pre-launch report hoặc kiểm thử máy thật.

## English trong ứng dụng

Bản Play 1.1.1 / 101 và APK 1.0.9 / 74 có Tiếng Việt, English và Theo hệ thống. Đổi ở màn chào (VI / EN), đăng nhập hoặc Cài đặt & riêng tư → Ngôn ngữ. Lựa chọn lưu trên thiết bị; ngôn ngữ hệ thống ngoài tiếng Việt dùng English. Bộ dịch 1.332 mục nằm tại android/i18n/en.json; chạy scripts/sync-android-languages.py để kiểm tra và tạo asset. Không dịch nội dung bài viết/tin nhắn/tên tự nhập. Giá trị hồ sơ/bộ lọc được giữ nguyên khi dịch nhãn.

Đã kiểm tra hai ngôn ngữ trên Android 16 16KB: đăng nhập, cài đặt, xóa tài khoản, lưu lựa chọn, dữ liệu người dùng và giá trị hồ sơ. Play policy audit tiếp tục đạt. Chưa kiểm thử điện thoại thật hoặc nộp Play Console; tài khoản nhà phát triển đang chờ Google hỗ trợ đối soát phí đăng ký.
