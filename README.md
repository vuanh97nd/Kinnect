# Kinnect 0.3.0 — Android native + Node.js trên Windows

Tên app **Kinnect**, package `app.kinnect.live`, Android 8+, APK versionCode 5. Màn hình đăng nhập/đăng ký, khám phá, hồ sơ, bảng tin, DM, thông báo, quản trị và video ngắn là Android Views native gọi API HTTPS. Riêng module livestream vẫn WebRTC trong WebView; video live qua Internet chưa có TURN/SFU và chưa xác nhận hoạt động. Đây là bản alpha, chưa phải đầy đủ/ngang chất lượng HeeSay hoặc TikTok.

[Nguồn tham khảo và giấy phép](docs/research-and-roadmap.md) · [Ghi chú 0.3.0](docs/releases/v0.3.0.md). Không sao chép thương hiệu/giao diện/mã HeeSay; chưa tìm được mã nguồn chính thức có bằng chứng.

## Cập nhật máy chủ Windows trước khi cài APK mới

Backend 0.2 không có API quản trị, tìm quanh đây và video ngắn. **Cần cập nhật backend 0.3 và khởi động lại**, không chỉ cài APK. Cài Node >=22.13, khuyến nghị Node 24 LTS. Không cần máy chủ database riêng.

1. Dừng Node.js bằng Ctrl+C. Giữ dữ liệu/thay đổi riêng. Sao lưu toàn bộ DATA_DIR khi mọi tiến trình ghi SQLite đã dừng, gồm .sqlite/WAL/SHM nếu có. Không sao chép riêng file .sqlite đang ghi WAL.
2. Chạy PowerShell trong thư mục checkout:

```powershell
git status --short
git fetch origin
git switch feature/social-core
git pull --ff-only origin feature/social-core
npm ci
npm test
$env:SECURE_COOKIES = '1'
# Nếu trước đây dùng DATA_DIR tùy chỉnh, phải giữ đúng giá trị đó.
npm start
```

Nếu chưa clone: `git clone --branch feature/social-core https://github.com/vuanh97nd/Kinnect.git`, sau đó `Set-Location Kinnect`. Không reset thay đổi riêng nếu Git báo xung đột.

Ở PowerShell thứ hai:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

Cần thấy `ok: True` và `version: 0.3.0`. Cổng mặc định 3000, biến PORT có thể đổi. DATA_DIR mặc định `data` tương đối với thư mục chạy; có thể đặt `$env:DATA_DIR = 'C:\KinnectData'` trước khi chạy. Chưa dùng dotenv; file .env không tự nạp. SECURE_COOKIES=1 cho HTTPS/Tunnel, bỏ biến khi chỉ thử bằng trình duyệt HTTP localhost.

## SQLite và migration

Tự tạo/nâng schema bằng cách thêm cột/bảng, giữ users/password/session và dữ liệu 0.2. Schema hiện tại 5, có role, vị trí gần đúng tùy chọn, quà miễn phí và video ngắn/likes/comments. Video BLOB và ảnh nằm trong cùng SQLite nên cần tính dung lượng backup. Phòng live/tin chat trong phòng vẫn tạm thời. Không commit DATA_DIR, SQLite, cookie, khóa ký hoặc token.

Để khôi phục, dừng server/CLI và khôi phục toàn bộ DATA_DIR đã sao lưu. Chưa có backup tự động hoặc diễn tập khôi phục trên Windows. Chủ máy có thể đọc dữ liệu SQLite; chưa có mã hóa đầu cuối/database. Session HttpOnly/SameSite=Strict, hết hạn sau 7 ngày; mật khẩu scrypt + salt. App native hiện giữ cookie trong RAM, nên khi tiến trình app bị hủy có thể phải đăng nhập lại.

## Kết nối điện thoại

Máy chủ mặc định của APK vẫn là `https://estimated-drink-beta-alerts.trycloudflare.com`. Đây là **Quick Tunnel tạm thời**, không phải hostname cố định. Máy Windows và Node/Tunnel phải hoạt động, không sleep. Cài cloudflared theo tài liệu Cloudflare, chạy ở terminal khác:

```powershell
cloudflared tunnel --url http://localhost:3000
```

Nếu URL thay đổi, trong Kinnect mở **Cài đặt → Đổi máy chủ** và nhập URL HTTPS mới. Đổi origin sẽ đăng xuất phiên native; không đưa token/password vào URL. Không dùng localhost của Windows trên điện thoại. Giữ TLS verification, Host/Origin và WebSocket đúng. Tunnel chỉ chuyển web/API/signaling, không thay thế TURN/SFU cho livestream.

## Đăng ký và thành viên xung quanh

- Nút **Tạo tài khoản**, password tối thiểu **6 ký tự**, không bắt buộc chữ hoa/số/ký tự đặc biệt; tối đa 128 ký tự.
- Bắt buộc chọn **Tôi xác nhận mình đủ 18 tuổi**. Không yêu cầu/thu ngày sinh ở đăng ký mới. Đây là tự xác nhận, không xác minh danh tính. Cột ngày sinh cũ giữ tương thích, không công khai, không thêm ngày giả.
- Sau đăng nhập mở Khám phá. Chưa cấp vị trí: gợi ý sở thích, không tạo khoảng cách giả.
- **Bật danh sách xung quanh** yêu cầu đồng ý và quyền Android vị trí gần đúng; không xin FINE_LOCATION. Nếu không lấy được fix thì báo rõ và vẫn dùng khám phá sở thích.
- Server làm tròn tọa độ theo ô 0.05 độ (khoảng 5 km theo vĩ độ), chỉ trả dải khoảng cách (<5, 5–20, 20–50, 50–100 km), không trả tọa độ người khác. Dữ liệu còn hiệu lực 24 giờ, được xóa khi có API request sau hết hạn. Tắt/xóa ngay trong Hồ sơ.
- Chỉ hiện thành viên đồng ý chia sẻ vị trí, cho phép khám phá, không bị chặn/đình chỉ. Danh sách hiện xét tối đa 500 tài khoản gần đây, trả tối đa 50; chưa là dịch vụ geo quy mô lớn. Làm tròn không bảo đảm chống mọi suy luận vị trí; không chia sẻ nếu không thoải mái.

## Tài khoản quản trị viên

Không có username/mật khẩu mặc định, không tự tạo mật khẩu chung. Đăng ký tài khoản thật trong app, rồi **chủ máy Windows** mở PowerShell tại repo với cùng DATA_DIR và chạy:

```powershell
npm run admin -- promote ten_dang_nhap
```

Thay `ten_dang_nhap` bằng username đã đăng ký (chữ thường). Nếu không thấy tài khoản, kiểm tra DATA_DIR, không tạo database mới để thay thế database đang dùng. Mở lại Hồ sơ/đăng nhập lại: có **Quản trị viên · Quản lý cộng đồng**. Web UI cũng có tab Quản trị cho admin. API kiểm tra role phía server; tài khoản thường không tự cấp quyền được.

Có thể xem báo cáo/nội dung được báo cáo, ẩn/hiện bài/video, đình chỉ/khôi phục thành viên, đóng báo cáo. Không có quyền đọc toàn bộ DM tùy ý; quản trị chỉ nhận nội dung tin nhắn được báo cáo. Audit lưu SQLite. Không đình chỉ admin qua API; không hạ quyền admin cuối cùng. Để hạ quyền cục bộ: `npm run admin -- demote ten_dang_nhap` khi có admin khác.

CLI moderation cũ vẫn dùng được:

```powershell
npm run moderate -- reports
npm run moderate -- hide-post POST_ID
npm run moderate -- hide-short SHORT_ID
npm run moderate -- suspend-user USER_ID
npm run moderate -- close-report REPORT_ID
```

Có show-post/show-short/restore-user. Không công khai đầu ra báo cáo hoặc dữ liệu SQLite. Kiểm duyệt thủ công, chưa có đội 24/24 hoặc kiểm duyệt tự động.

## Video ngắn

Tab Video native: quay qua ứng dụng camera hệ thống hoặc chọn MP4, thêm caption, upload, vuốt/chọn video trước/sau, âm thanh bật/tắt, thích, bình luận và báo cáo. Chủ bài xóa được video; admin ẩn/hiện video. Khi rời màn hình, playback dừng; khi app ra nền, video tạm dừng.

Giới hạn alpha: MP4 có metadata mvhd đọc được, >0 và <=60 giây, <=12 MB; tối đa 10 uploads/ngày/người; kho tối đa 500 MB, hai upload đang xử lý đồng thời. Server kiểm tra size/duration/container, **không transcoding, không quét toàn bộ codec/nội dung**; khuyến nghị H.264/AAC, thiết bị có thể không hỗ trợ một số MP4. Không có bộ dựng/cắt video, nhạc bản quyền, hiệu ứng làm đẹp hoặc thuật toán như TikTok. Feed xếp mới trước, tối đa 50. Có HTTP Range/HEAD cho player. Chỉ thành viên đăng nhập được xem; chặn/đình chỉ/ẩn có hiệu lực ở API. File đã tải/cache trên thiết bị không thể thu hồi.

Video lưu BLOB SQLite phù hợp thử nghiệm nhỏ; chưa có CDN/chuyển mã/stream adaptive. Không đăng nội dung bất hợp pháp hoặc hình ảnh người khác khi chưa có quyền. Fixture test/fixtures/short.mp4 là video màu tổng hợp 1 giây tạo bằng ffmpeg, không chứa người dùng hoặc nội dung bên thứ ba.

## Các chức năng xã hội và live

Hồ sơ/bio/sở thích/avatar <=1 MB; theo dõi, DM mặc định cùng theo dõi; bảng tin văn bản public cho thành viên hoặc followers; chặn/báo cáo; thông báo trong app. DM polling mỗi 4 giây khi mở chat, chưa push Android. Chưa có khôi phục password/xóa-xuất tài khoản/album hoặc bình luận bảng tin.

Live còn module WebView/WebRTC, tối đa 6 viewer, camera dừng khi ra nền. Có ba quà **miễn phí thử nghiệm**, giới hạn 5 quà/phút; lưu sự kiện và count, không có xu mua bằng tiền, thanh toán hoặc rút tiền. Video Internet chưa có TURN/SFU, không tuyên bố đã hoạt động.

## Kiểm thử và build

```powershell
npm test
npx playwright install chromium
npm run test:e2e
```

Backend tests dùng RAM/thư mục tạm, gồm auth/password/18+, RBAC, CLI promote, moderation, block/privacy, vị trí, SQLite restart, gifts, MP4 validation/range/comments/likes. Browser tests dùng camera giả và fixture MP4, không phải kiểm thử native Android. Kiểm tra media WebRTC mặc định skipped do cloud Chromium cấm non-proxied UDP; chạy opt-in KINNECT_MEDIA_E2E=1 ở hạ tầng phù hợp sau khi có TURN. Không vô hiệu hóa policy.

Linux CI/build có Java 21, curl, unzip, zip, sha256sum:

```sh
bash scripts/prepare-android-tools.sh
bash scripts/test-android-config.sh
bash scripts/build-apk.sh
```

KINNECT_TOOLS chọn thư mục ghi được. Toolchain download có checksum pin. Output dist/kinnect-live-debug.apk. Chưa có Gradle/Android Studio project hoặc emulator trong phiên này; **chưa kiểm thử picker, vị trí, video và layout native trên điện thoại thật**. APK ký debug cho thử nghiệm, không dùng Play Store. Workflow tag v* phát hành APK/SHA-256 lên GitHub Releases, khóa debug tạo tạm không commit/upload. Chữ ký có thể đổi giữa các CI release: gỡ bản cũ có thể mất cookie/URL cục bộ, không xóa tài khoản trên server; chỉ gỡ sau khi lưu thông tin đăng nhập.
