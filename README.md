# Kinnect 0.2 — cộng đồng, kết bạn và livestream thử nghiệm

Node.js tự chạy trên Windows, SQLite lưu bền, Android WebView kết nối HTTPS. Dùng thương hiệu/thiết kế riêng. [Nghiên cứu nguồn và lộ trình](docs/research-and-roadmap.md) ghi rõ nguồn nào đã xác minh, giấy phép, tiến độ và phần còn thiếu.

## Chạy trên Windows (PowerShell)

Cài Git và **Node.js LTS >=22.13** có `node:sqlite` (khuyến nghị Node 24 LTS). Không cần cài máy chủ database riêng.

```powershell
git clone --branch feature/social-core https://github.com/vuanh97nd/Kinnect.git
Set-Location Kinnect
npm ci
npm test
npm start
```

Nếu đã clone, giữ thay đổi riêng trước khi `git fetch origin` rồi checkout nhánh/commit bàn giao. Không reset thay đổi của người dùng. Lệnh `npm ci`, `npm test`, `npm start` và cổng 3000 giữ tương thích quy trình trước; WebSocket hiện yêu cầu đăng nhập, không còn chế độ live ẩn danh.

Kiểm tra ở PowerShell thứ hai:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

Kết quả mong đợi `ok: True`. Mở `http://localhost:3000`, đăng ký tài khoản người từ 18 tuổi. Không có tài khoản mặc định hoặc mật khẩu quản trị cài sẵn.

## Dữ liệu và cấu hình

`npm start` tự tạo **data/kinnect.sqlite** cùng file WAL/SHM nếu có. Hồ sơ/ảnh, hash mật khẩu, session, theo dõi, chặn, bài, DM, thông báo, báo cáo và audit lưu ở đây, còn nguyên sau restart. Phòng live và tin chat trong phòng là tạm thời. Thư mục data và khóa ký bị Git bỏ qua.

Ví dụ PowerShell, đặt trước `npm start`:

```powershell
$env:PORT = '3000'
$env:DATA_DIR = 'C:\KinnectData'
# Đặt 1 khi truy cập qua HTTPS/Tunnel. Để unset cho thử trình duyệt localhost HTTP.
$env:SECURE_COOKIES = '1'
npm start
```

`DATA_DIR` mặc định là `data` tương đối với thư mục chạy. Không đặt trong thư mục public hoặc commit vào Git. Chưa dùng dotenv; tạo file .env không tự nạp cấu hình. Session hết hạn sau 7 ngày. `SECURE_COOKIES=1` thêm Secure vào cookie HttpOnly/SameSite=Strict; dùng khi đưa app qua HTTPS. Giữ máy tính có mạng, không sleep và giữ Node.js/Tunnel chạy. Máy tắt thì dịch vụ dừng.

**Sao lưu:** dừng Node.js và công cụ moderation, sao chép toàn bộ DATA_DIR sang nơi riêng tư rồi khởi động lại. Khi khôi phục, dừng tiến trình và khôi phục toàn bộ thư mục cùng nhau. Không copy riêng file .sqlite trong lúc đang ghi WAL. Chưa có backup tự động hoặc diễn tập khôi phục; cần chủ máy chủ bảo vệ ổ đĩa và bản sao. Ngày sinh, DM và ảnh là dữ liệu riêng tư có thể được chủ máy chủ truy cập; chưa có mã hóa đầu cuối hoặc mã hóa database.

## Kết nối APK tới máy chủ Windows

Cài cloudflared từ tài liệu chính thức của Cloudflare và chạy ở PowerShell thứ hai:

```powershell
cloudflared tunnel --url http://localhost:3000
```

Trong APK, nhập URL **https://...trycloudflare.com** được in ra rồi chọn **Vào Kinnect**. URL lưu trên điện thoại bằng SharedPreferences; đổi bằng **Đổi máy chủ / Ngắt kết nối**. Không sửa URL trong Java, không đưa URL kèm mật khẩu/token vào repo. Không dùng localhost của máy Windows làm URL trên điện thoại. APK chỉ nhận HTTPS với chứng chỉ hợp lệ; không tắt xác minh TLS.

Frontend tự dùng WSS cùng origin. Reverse proxy phải hỗ trợ WebSocket và Host/Origin nhất quán; không bỏ kiểm tra Origin để né lỗi. Tunnel thử nghiệm có thể đổi URL và không cam kết uptime. **Tunnel không chuyển tiếp video WebRTC**: video khác mạng còn cần TURN/SFU. Chỉ dùng nhóm thử nghiệm tin cậy.

## Luồng dùng thử

1. Đăng ký username/mật khẩu, nhập ngày sinh hợp lệ và đồng ý 18+/quy tắc. Cổng tự khai không xác minh danh tính.
2. Mở Hồ sơ, lưu giới thiệu, sở thích (phân cách dấu phẩy), ảnh <=1 MB và quyền nhận DM/hiện trong khám phá.
3. Tạo tài khoản thứ hai trên thiết bị/trình duyệt riêng, tìm nhau ở Khám phá; hai bên Theo dõi để mở chat mặc định.
4. Gửi DM; đăng bài cho thành viên hoặc chỉ người theo dõi; xem thông báo trong ứng dụng.
5. Chặn/báo cáo từ Khám phá, báo cáo bài/tin nhắn. Xem/bỏ chặn tại Hồ sơ. Người bị chặn không thể liên hệ và không xuất hiện trên bảng tin/khám phá.
6. Vào Live, cấp camera/micro để phát; viewer không cần cấp quyền camera. Tối đa 6 viewer/phòng. Camera dừng khi app ra nền.

Thông báo trong app chưa phải push Android. Chat riêng cập nhật mỗi 4 giây, thông báo mỗi 15 giây. Chưa mã hóa đầu cuối, khôi phục mật khẩu, xóa/xuất tài khoản, quà tặng, thanh toán, album, bình luận hoặc xác minh tuổi nâng cao.

## Xử lý báo cáo trên máy chủ

Chạy tại thư mục repo, với cùng DATA_DIR của server. CLI chỉ dành cho người quản lý máy; không có endpoint admin công khai hoặc admin password mặc định.

```powershell
npm run moderate -- reports
npm run moderate -- hide-post POST_ID
npm run moderate -- suspend-user USER_ID
npm run moderate -- close-report REPORT_ID
```

Có `show-post POST_ID`, `restore-user USER_ID`. Thay ID bằng ID thực từ báo cáo. Audit log lưu trong SQLite. Suspend vô hiệu session; websocket bị từ chối khi gửi tiếp/có thay đổi hoặc broadcast, người dùng bị ẩn khỏi truy vấn xã hội. Đây là công cụ xử lý thủ công, không tự quyết định tính đúng sai của báo cáo và không cung cấp đội kiểm duyệt 24/24. Không công khai đầu ra báo cáo vì có nội dung người dùng.

## Kiểm thử

```powershell
npm test
# Cài browser cho kiểm thử tùy chọn (một lần, cần mạng):
npx playwright install chromium
npm run test:e2e
```

Integration tests dùng SQLite trong RAM/thư mục tạm, không ghi đè data thật. Playwright khởi động backend RAM ở cổng 3210, chạy Chromium viewport điện thoại với hai tài khoản thử nghiệm. Không cần camera thật cho test này; không xác minh video. Nếu đã có Chromium hệ thống, có thể đặt `PLAYWRIGHT_CHROMIUM_EXECUTABLE` trỏ tới executable; môi trường Linux hiện tại dùng `/usr/bin/chromium`.

## Android / build APK

Mã tại android/app/src/main. APK Android 8+, package `app.kinnect.live`, phiên bản 0.2.0, vẫn WebView chứ không phải Compose native. Cần Android System WebView cập nhật.

Trong môi trường Linux đã chuẩn bị toolchain:

```sh
bash scripts/build-apk.sh
```

Tệp xuất `dist/kinnect-live-debug.apk`; không commit APK/khóa ký. Script dùng SDK 35, Build Tools 35.0.0 và ECJ 3.39.0 ở `/workspace/toolchains` (có thể đổi KINNECT_TOOLS). Các gói đã kiểm tra checksum khi tải; thư mục toolchain không nằm trong repo. Chưa có Gradle/Gradle Wrapper: **không chạy script trực tiếp bằng PowerShell**, Codex Windows cần chuẩn hóa Android Studio/Gradle hoặc dựng toolchain tương đương. Khóa debug tiêu chuẩn sinh cục bộ, không phải khóa phát hành; giữ nó riêng nếu cần cài bản cập nhật debug. Không dùng để phát hành Play.

Đã kiểm thử backend/browser và build/chữ ký APK trên Linux; chưa chạy Windows hoặc Android thật trong phiên này. Không tạo dịch vụ trả phí hoặc tích hợp thanh toán. Trước khi công khai cần TURN/SFU, kiểm thử thiết bị, chính sách dữ liệu/tuổi, quy trình xử lý nội dung và vận hành bảo mật.

### Kiểm thử video riêng

Chromium cloud hiện có chính sách `WebRtcIPHandling=disable_non_proxied_udp`. Lần thử nhận khung hình đã thất bại dù host mở camera giả và có offer/answer; chưa có TURN để chuyển tiếp. Test nhận video vì thế tách riêng và mặc định skipped, không được tính là pass. Test browser mặc định chỉ xác minh luồng xã hội, camera giả phía host, chat/phòng và dừng live khi ra nền. Khi có mạng hỗ trợ/TURN đã tích hợp, bật kiểm tra video:

```powershell
$env:KINNECT_MEDIA_E2E = '1'
npm run test:e2e
```

Không vô hiệu hóa chính sách mạng để làm test đạt. Android đã thêm trình chọn ảnh hệ thống cho avatar, nhưng picker/quyền/lifecycle vẫn cần kiểm thử trên thiết bị thật.
