# Báo cáo Chụp thử Giao diện Thực tế Kinnect iOS Native (`dist/ios-ui-review`)

- **Capture Scope**: `light`
- **Git SHA**: `cf588f5753b73f5644619a915cb1b84ccaa8436f`
- **Version / Build**: `1.2.12` / `124`
- **Xcode & SDK**: `Xcode 16.4 | Build version 16F6`
- **Thiết bị iPhone chuẩn**: `iPhone 16 Pro` (`com.apple.CoreSimulator.SimRuntime.iOS-18-5`)
- **Thiết bị iPhone kiểm tra màn hình nhỏ**: `iPhone 16e`
- **Thiết bị iPad**: `iPad Pro 11-inch (M4)`
- **Chế độ dữ liệu**: `--ui-review-screen` (`UIReviewFixture` tách biệt hoàn toàn, gắn nhãn `[Fixture UI]`, không chạm dữ liệu production, không lộ token/mật khẩu, không gọi người thật/phát live thật/mua hàng thật).

## Danh sách ảnh chụp PNG thực tế từ `xcrun simctl io screenshot`

- `light-01-iphone-auth-welcome-dark.png` — **Chào mừng Tab 1: Khám phá (Discover VI) — Standard iPhone · Light mode** (`iPhone 16 Pro`)
- `light-01b-iphone-auth-login-dark.png` — **Đăng nhập chính tiếng Việt trống (Dark) · Light mode** (`iPhone 16 Pro`)
- `light-04-iphone-messages-list-dark.png` — **Danh sách Tin nhắn & Nhóm (Dark) · Light mode** (`iPhone 16 Pro`)
- `light-05-iphone-chat-detail-dark.png` — **Chi tiết Chat: nội dung trên, giờ+seen+reaction+more dưới · Light mode** (`iPhone 16 Pro`)
- `light-06-iphone-profile-dark.png` — **Hồ sơ cá nhân & Chẩn đoán PushKit (Dark) · Light mode** (`iPhone 16 Pro`)
- `light-09-iphone-wallet-store-dark.png` — **Ví & Cửa hàng: Tách Xu mua & Xu tặng, Số dư và Lịch sử · Light mode** (`iPhone 16 Pro`)
- `light-10-iphone-live-stream-dark.png` — **Phòng Live: Luồng vuốt xem trực tiếp · Light mode** (`iPhone 16 Pro`)
- `light-13-iphone-feed-light.png` — **Bảng tin chế độ Light mode · Light mode** (`iPhone 16 Pro`)
- `welcome-autocycle-demo.mp4` — **Video thực tế luân phiên 4 màn hình chào mừng (1.5s/chu kỳ, >=2 chu kỳ đầy đủ) trên iPhone 16 Pro** (`iPhone 16 Pro`)
- `kinnect-comprehensive-features-test.mp4` — **Video thực tế kiểm thử toàn bộ 10 chức năng trên iPhone 16 Pro theo yêu cầu** (`iPhone 16 Pro`)

## Rà soát Giao diện & Giới hạn
- **Bộ 40 icon vector (`KinnectIcons.swift`)**: Hiển thị sắc nét bằng SwiftUI `Path` native ở kích thước 24pt (26pt trên thanh tab), nét `2.05` khi chọn và `1.65` khi thường.
- **Nút gọi thoại / gọi video / menu (`...`)**: Nền trong suốt hoàn toàn, vùng chạm 44×44pt.
- **Màn hình Chat (`05-iphone-chat-detail-dark.png`)**: Nội dung tin nhắn nằm trên; giờ, icon `seen`, `reaction`, và `more` (`...`) nằm chung một hàng bên dưới.
- **Màn hình Camera & Studio (`11` & `12`)**: Khi chưa có media (`11`), ẩn toàn bộ trường chỉnh sửa Studio; chỉ sau khi có ảnh/video (`12`) mới hiện bảng Studio và nút `Lưu` tách thành cụm riêng không đè nút chính.
- **Màn hình Phòng Live (`10`)**: Luồng cuộn thống nhất, không có thanh lọc `Tất cả / Trò chuyện / Chơi game` ở đầu trang.
- **Màn hình Ví & Cửa hàng (`09` & `16`)**: Dùng chung icon `coin` có chữ `K` bên trong, phân biệt bằng nhãn chữ và có `.minimumScaleFactor(0.75)` chống cắt số.
- **Lưu ý Light Mode (`13-iphone-feed-light.png`)**: Ứng dụng Kinnect sử dụng bảng màu tối đặc trưng (`KinnectTheme.background = #0E0B18`, `surface = #181326`) nên ngay cả khi hệ thống chuyển sang Light Mode, nền và chữ vẫn giữ độ tương phản chuẩn của chủ đề tím đêm Kinnect.
- **Giới hạn Simulator**: Camera vật lý, PushKit APNs VoIP token thật và cuộc gọi WebRTC P2P với người thật không kích hoạt trong phiên chụp tự động trên Simulator để đảm bảo an toàn production.