# Kinnect Live — bản thử nghiệm Android + Node.js

APK Android dùng WebView để chạy giao diện livestream từ máy chủ của bạn. Đây là ứng dụng Android thử nghiệm có thể cài đặt, chưa phải giao diện Kotlin/Compose native. Android 8 trở lên, cần Android System WebView cập nhật. Bản debug không dành cho Google Play.

## Chạy máy chủ trên máy tính cá nhân

Cài Node.js 22 hoặc mới hơn, tải mã nguồn này về máy và mở terminal tại thư mục chứa package.json:

```sh
npm ci
npm test
npm start
```

Máy chủ mặc định cổng 3000, có thể đổi bằng biến PORT. Kiểm tra `http://localhost:3000/health` trả về `{"ok":true}`. Không tắt máy, không để máy sleep; cần Internet liên tục nếu có người dùng bên ngoài. Sau khi khởi động lại máy, phải chạy lại Node.js.

Để APK truy cập, đặt máy chủ sau địa chỉ HTTPS hợp lệ. Có thể dùng Cloudflare Tunnel trỏ đến `http://localhost:3000`; với cloudflared đã cài từ nguồn chính thức, lệnh thử nghiệm là:

```sh
cloudflared tunnel --url http://localhost:3000
```

Địa chỉ tunnel thử nghiệm có thể thay đổi, không có cam kết hoạt động liên tục. Giữ cả Node.js và cloudflared chạy. APK chỉ chấp nhận HTTPS; không tắt kiểm tra chứng chỉ. Khi dùng reverse proxy, giữ Host/Origin nhất quán và hỗ trợ WebSocket.

## Cài APK

Tệp build: `dist/kinnect-live-debug.apk`. Chuyển sang điện thoại, cho phép cài từ nguồn bạn tin cậy rồi cài. Mở Kinnect Live, nhập địa chỉ HTTPS của máy chủ, nhập tên và chủ đề, bấm Bắt đầu livestream; cho phép camera và micro. Trên điện thoại thứ hai, dùng cùng máy chủ, nhập tên rồi chọn Vào xem. Người xem không cần cấp camera/micro. Khi ứng dụng ra nền, nó ngắt kết nối và dừng camera để bảo vệ riêng tư.

## Phạm vi đã có

- Tạo, liệt kê, tham gia và kết thúc phòng livestream.
- Chat realtime, bật/tắt camera và micro, thông báo số người xem.
- WebRTC P2P, tối đa 6 người xem/phòng. Mỗi người xem dùng một luồng upload của người phát.
- Signaling giới hạn trong phòng, kiểm tra Origin, giới hạn kích thước và tần suất thông điệp; nội dung chat hiển thị dạng văn bản.

## Giới hạn cần biết

**Chưa sẵn sàng mở cho cộng đồng công khai.** Chưa có tài khoản, cơ sở dữ liệu, chặn/báo cáo, xác minh tuổi, kiểm duyệt hoặc ghi hình. Phòng và chat nằm trong RAM, mất khi Node.js khởi động lại. Chỉ thử nghiệm với người tin cậy; ai có địa chỉ máy chủ đều có thể vào.

**Video qua Internet chưa được bảo đảm.** Bản này dùng ICE host candidates, chưa cấu hình STUN/TURN hoặc SFU. HTTPS tunnel chỉ đưa web/chat/signaling ra Internet, không chuyển tiếp video WebRTC. Video giữa các mạng/NAT có thể không kết nối; cần bổ sung TURN và kiểm thử hai điện thoại trên hai mạng, hoặc chuyển sang LiveKit/SFU trước khi triển khai thực tế. Ngay cả cùng mạng, cần kiểm tra khả năng kết nối trực tiếp của thiết bị. Không gọi đây là livestream Internet hoàn chỉnh.

Chưa chạy emulator hoặc kiểm thử camera/micro trên điện thoại thật trong môi trường build. Kiểm thử tự động xác minh HTTP, vòng đời phòng, chat, signaling, giới hạn người xem và từ chối Origin ngoài máy chủ; không xác minh hình/âm thanh thực tế.

## Build lại APK trong môi trường hiện tại

```sh
bash scripts/build-apk.sh
```

Script dùng SDK Android 35, Build Tools 35.0.0 và Eclipse ECJ 3.39.0 tại `/workspace/toolchains`. Các gói đã được kiểm tra checksum với metadata từ Google/Maven khi tải. Không phụ thuộc Gradle. `KINNECT_TOOLS` có thể trỏ sang thư mục khác có cùng cấu trúc. Debug keystore được sinh cục bộ và bị Git bỏ qua; cần giữ nó nếu muốn cài bản cập nhật lên APK debug đã cài trước đó. Không dùng khóa debug để phát hành.

## Tiện ích khám phá và hướng phát triển

Đã có tìm phòng theo chủ đề/tên người phát, sắp xếp phòng mới hoặc đông người xem và nhớ tên hiển thị trên thiết bị (có thể xóa bằng cách xóa dữ liệu ứng dụng/trình duyệt).

Các tính năng dưới đây CHƯA triển khai: gợi ý bạn theo sở thích và mức độ tương tác; kiểm duyệt nội dung và báo cáo; phát hiện spam/tài khoản giả; phụ đề trực tiếp; thông báo người bạn theo dõi lên sóng. Cần hoàn thiện tài khoản, cơ sở dữ liệu, quyền riêng tư, hệ thống báo cáo và hạ tầng video trước khi tích hợp AI hoặc phát hành công khai.

## Bàn giao cho Codex trên Windows

Repo chứa backend Node.js và mã Android tại `android/app/src/main`. APK, thư viện node_modules, Android SDK và khóa ký không được đưa lên GitHub.

### Lấy mã và chạy backend (PowerShell)

Cài Git và Node.js LTS 22 trở lên. Trong PowerShell:

```powershell
git clone --branch main https://github.com/vuanh97nd/Kinnect.git
Set-Location Kinnect
npm ci
npm test
npm start
```

Nếu đã clone repo, kiểm tra và giữ lại các thay đổi riêng trước khi chạy `git fetch origin` và checkout nhánh/commit bàn giao. Không reset hoặc xóa thay đổi của người dùng.

Mở một cửa sổ PowerShell khác để kiểm tra:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

Kết quả mong đợi: `ok` bằng `True`. Để đổi cổng trước khi chạy máy chủ:

```powershell
$env:PORT = '3000'
npm start
```

Máy chủ không dùng file `.env` và chưa có cơ sở dữ liệu. Chỉ biến môi trường `PORT` được đọc. Không thêm token, khóa ký hoặc thông tin đăng nhập vào mã nguồn.

### URL máy chủ trong APK

1. Chạy Node.js trên Windows bằng `npm start`.
2. Cài cloudflared theo hướng dẫn chính thức của Cloudflare, rồi chạy `cloudflared tunnel --url http://localhost:3000` trong cửa sổ thứ hai.
3. Trong Kinnect Live, nhập URL HTTPS mà tunnel trả về vào ô máy chủ, rồi bấm **Vào Kinnect Live**. URL được lưu trong SharedPreferences trên điện thoại, không được commit vào repo.
4. Khi URL tunnel thay đổi, chọn **Đổi máy chủ / Ngắt kết nối** rồi nhập URL mới. Không dùng `localhost` của máy Windows làm URL trên điện thoại.

Không cần sửa URL trong mã Java. `MainActivity.java` kiểm tra HTTPS và giới hạn điều hướng/cấp camera theo origin đã chọn. Frontend tự suy ra URL WebSocket từ cùng origin của trang: HTTPS tương ứng WSS. Reverse proxy phải hỗ trợ WebSocket và giữ Host/Origin nhất quán; không bỏ kiểm tra Origin để xử lý lỗi cấu hình proxy.

### Trạng thái build Android để Codex tiếp tục

Đã build và kiểm tra chữ ký APK trong môi trường Linux bằng `scripts/build-apk.sh`. Script hiện phụ thuộc toolchain cục bộ ở `/workspace/toolchains`, không được commit; không chạy trực tiếp trong PowerShell và chưa có dự án Gradle/Gradle Wrapper. Để build trên Windows, Codex cần thiết lập Android SDK + build tools và trình biên dịch Java tương ứng hoặc chuyển mã Android hiện có sang dự án Gradle/Android Studio. Không giả định toolchain Linux tồn tại sau khi clone GitHub. Không có khóa release trong repo; khóa debug tiêu chuẩn được tạo cục bộ bởi script build.

Kiểm thử đã chạy trên Linux: hai integration tests của backend, kiểm tra cú pháp frontend, build APK và xác minh chữ ký. Windows, điện thoại thật và luồng video qua Internet chưa được kiểm thử.
