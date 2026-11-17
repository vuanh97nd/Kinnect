# Báo cáo Chụp thử Giao diện Thực tế Kinnect iOS Native (`dist/ios-ui-review`)

- **Capture Scope**: `matrix`
- **Git SHA**: `92b9cef39563719a35091eb342327c118c1d7dfc`
- **Version / Build**: `1.2.12` / `124`
- **Xcode & SDK**: `Xcode 16.4 | Build version 16F6`
- **Thiết bị iPhone chuẩn**: `iPhone 16 Pro` (`com.apple.CoreSimulator.SimRuntime.iOS-18-5`)
- **Thiết bị iPhone kiểm tra màn hình nhỏ**: `iPhone 16e`
- **Thiết bị iPad**: `iPad Pro 11-inch (M4)`
- **Chế độ dữ liệu**: `--ui-review-screen` (`UIReviewFixture` tách biệt hoàn toàn, gắn nhãn `[Fixture UI]`, không chạm dữ liệu production, không lộ token/mật khẩu, không gọi người thật/phát live thật/mua hàng thật).

## Danh sách ảnh chụp PNG thực tế từ `xcrun simctl io screenshot`

- `14-compact-iphone-auth-welcome-dark.png` — **Màn hình nhỏ: Chào mừng Tab 1 Khám phá (Dark)** (`iPhone 16e`)
- `14-compact-iphone-feed.png` — **Màn hình nhỏ: Bảng tin & Tab bar 5 tab 26pt** (`iPhone 16e`)
- `15-compact-iphone-chat-detail.png` — **Màn hình nhỏ: Chi tiết Chat & hàng trạng thái dưới** (`iPhone 16e`)
- `16-compact-iphone-wallet.png` — **Màn hình nhỏ: Ví & Cửa hàng không cắt số dư / Nạp xu** (`iPhone 16e`)
- `16b-compact-iphone-dynamictype-max.png` — **Màn hình nhỏ: Dynamic Type kích thước tối đa Accessibility 5** (`iPhone 16e`)
- `16e-compact-iphone-friends.png` — **Màn hình nhỏ: Bạn bè không cắt tên dài với nút tác vụ hàng dưới** (`iPhone 16e`)
- `17-ipad-feed-splitview.png` — **iPad NavigationSplitView: Sidebar + Bảng tin** (`iPad Pro 11-inch (M4)`)
- `18-ipad-chat-detail.png` — **iPad NavigationSplitView: Danh sách Hội thoại (trái) + Chi tiết Chat (phải)** (`iPad Pro 11-inch (M4)`)
- `18b-ipad-dynamictype-max.png` — **iPad: NavigationSplitView với Dynamic Type tối đa Accessibility 5** (`iPad Pro 11-inch (M4)`)

## Rà soát Giao diện & Giới hạn
- **Bộ 40 icon vector (`KinnectIcons.swift`)**: Hiển thị sắc nét bằng SwiftUI `Path` native ở kích thước 24pt (26pt trên thanh tab), nét `2.05` khi chọn và `1.65` khi thường.
- **Nút gọi thoại / gọi video / menu (`...`)**: Nền trong suốt hoàn toàn, vùng chạm 44×44pt.
- **Màn hình Chat (`05-iphone-chat-detail-dark.png`)**: Nội dung tin nhắn nằm trên; giờ, icon `seen`, `reaction`, và `more` (`...`) nằm chung một hàng bên dưới.
- **Màn hình Camera & Studio (`11` & `12`)**: Khi chưa có media (`11`), ẩn toàn bộ trường chỉnh sửa Studio; chỉ sau khi có ảnh/video (`12`) mới hiện bảng Studio và nút `Lưu` tách thành cụm riêng không đè nút chính.
- **Màn hình Phòng Live (`10`)**: Luồng cuộn thống nhất, không có thanh lọc `Tất cả / Trò chuyện / Chơi game` ở đầu trang.
- **Màn hình Ví & Cửa hàng (`09` & `16`)**: Dùng chung icon `coin` có chữ `K` bên trong, phân biệt bằng nhãn chữ và có `.minimumScaleFactor(0.75)` chống cắt số.
- **Lưu ý Light Mode (`13-iphone-feed-light.png`)**: Ứng dụng Kinnect sử dụng bảng màu tối đặc trưng (`KinnectTheme.background = #0E0B18`, `surface = #181326`) nên ngay cả khi hệ thống chuyển sang Light Mode, nền và chữ vẫn giữ độ tương phản chuẩn của chủ đề tím đêm Kinnect.
- **Giới hạn Simulator**: Camera vật lý, PushKit APNs VoIP token thật và cuộc gọi WebRTC P2P với người thật không kích hoạt trong phiên chụp tự động trên Simulator để đảm bảo an toàn production.