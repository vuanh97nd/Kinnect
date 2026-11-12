# Android UI Baseline & Cross-Platform Parity Standard — Kinnect (2026-11-13)

Tài liệu chuẩn hóa giao diện và hành vi dành cho Antigravity (Android) và Cursor (iOS).  
Căn cứ: Mã nguồn Android `app.kinnect.live` (`MainActivity.java`, `WebDesign.java`, `ApprovedTypography.java`, `WebIcons.java`, `CommerceUi.java`) và iOS `KinnectTheme.swift`.

---

## 1. Design Tokens dùng chung (Unified Design Tokens)

### 1.1 Bảng màu (Color Palette: Light & Dark)

| Token | Light Hex | Dark Hex | Vai trò / Ý nghĩa | iOS Tương đương |
|---|---|---|---|---|
| `BG` | `#f6f5fa` | `#151419` | Nền chính của ứng dụng | `KinnectTheme.background` |
| `CARD` | `#ffffff` | `#222128` | Nền thẻ, card, header, bottom bar | `KinnectTheme.surface` |
| `WASH` / `ELEVATED` | `#f4f1fa` | `#2c2833` | Nền container phụ, item unselected | `KinnectTheme.surfaceElevated` |
| `TEXT` / `INK` | `#1f1d2b` | `#f1eff7` | Chữ chính (Primary text) | `KinnectTheme.textPrimary` |
| `MUTED` | `#6a6478` | `#b1aabd` | Chữ phụ, placeholder, timestamp | `KinnectTheme.textSecondary` |
| `LINE` / `BORDER` | `#e4e0ec` | `#38333f` | Đường kẻ, viền phân cách | `KinnectTheme.border` / `line` |
| `ACCENT` / `PURPLE` | `#6c47e0` | `#7652e8` | Màu thương hiệu chính, nút CTA | `KinnectTheme.accent` (`#7c3aed`) |
| `PRIMARY_SOFT` | `#f1ecff` | `#332a48` | Nền mềm cho pill/badge được chọn | `KinnectTheme.accentSoft` |
| `DANGER` | `#c2365a` | `#d56579` | Báo lỗi, xóa, hủy | `KinnectTheme.danger` |
| `SUCCESS` / `ONLINE`| `#1f7a4d` / `#2e9e66` | `#75c89c` / `#40ae78` | Thành công, trạng thái trực tuyến | `KinnectTheme.success` / `online` |

> **Quy tắc Parity màu sắc:** Cả hai nền tảng bắt buộc tôn trọng theme máy (System) hoặc cấu hình trong Tài khoản → Giao diện (Sáng / Tối / Theo hệ thống). Không hardcode nền tối ở Light mode.

---

### 1.2 Phân cấp chữ (Typography Scale)

*Chuẩn hóa theo `WebDesign.java` và `ApprovedTypography.java`, loại bỏ hoàn toàn chữ quá to (> 24sp ở body hoặc > 28sp ở display) gây vỡ layout trên màn hình nhỏ:*

| Vai trò | Size (sp/pt) | Weight | Sử dụng cho | Giới hạn trần (Sheet/Dialog) |
|---|---|---|---|---|
| `DISPLAY` | 24 - 26 | Bold (700) | Tiêu đề chào đón, splash, hero | Max 28 |
| `TITLE` | 20 - 22 | Bold / Semibold | Header trang, tiêu đề sheet, tên profile | Max 22 (`sheet:title`) |
| `SECTION` | 16 - 17 | Semibold (600) | Tiêu đề khối (Nhóm, Cài đặt, Danh sách) | Max 20 (`sheet:heading`) |
| `BODY` | 15 | Regular (400) | Nội dung bài viết, comment, tin nhắn | Max 15 |
| `LABEL` / `BUTTON`| 14 - 15 | Medium (500) | Nút bấm, tab label, input text | Max 15 (`Button`), 16 (`Input`) |
| `META` / `CAPTION`| 12 - 13 | Regular (400) | Thời gian, lượt thích, gợi ý nhỏ | Max 13 |

> **Chống vỡ chữ (Dynamic Type & Accessibility):**
> - Không hardcode một chiều cao cố định cho text container chứa nội dung người dùng (user-generated content).
> - Sử dụng `singleLine="true"` kết hợp `ellipsize="end"` cho tiêu đề một dòng (Tên bài hát, tên nhóm, username).
> - Giữ vùng chạm (touch target) tối thiểu 44x44dp / pt cho mọi icon và nút.

---

### 1.3 Khoảng cách & Bo góc (Spacing & Radii)

| Token | Giá trị | Ứng dụng |
|---|---|---|
| `RADIUS_SM` | 8dp / pt | Tag, pill nhỏ, avatar phụ |
| `RADIUS_MD` | 16dp / pt | Input box, item row, thumbnail |
| `RADIUS_CARD` | 24dp / pt | Card bài viết, modal dialog, panel |
| `RADIUS_PILL` | 999dp / pt | Nút CTA tròn, avatar tròn, badge |
| `CONTROL_HEIGHT` | 44 - 48dp / pt | Chiều cao chuẩn cho Button, Input field |
| `TOPBAR_HEIGHT` | 56 - 64dp / pt | Chiều cao thanh điều hướng trên |
| `BOTTOMBAR_HEIGHT`| 60 - 64dp / pt | Chiều cao thanh 5 tab dưới |

---

## 2. Ma trận điều hướng & cấu trúc màn hình (Navigation Parity)

### 2.1 Thanh trên (Top Bar) — 5 thành phần theo thứ tự:
1. **Thông báo (`notifications`):** Icon `bell` (`ic_approved_bell`). Mở danh sách thông báo.
2. **Cửa hàng (`store`):** Icon / nút "Cửa hàng". Mở màn hình gói mua & vật phẩm.
3. **Bạn bè (`friends`):** Icon `users_round`. Mở màn hình danh sách bạn bè & lời mời kết bạn.
4. **Tin nhắn (`inbox`):** Icon `message_circle`. Mở hộp thư đến & cuộc trò chuyện.
5. **Tài khoản (`account`):** Avatar người dùng (bo tròn, hiển thị viền ACCENT khi active). Toggle mở Menu tài khoản.

### 2.2 Thanh dưới (Bottom Bar) — 5 tab theo thứ tự:
1. **Bảng tin (`feed`):** Icon `house`. Danh sách bài đăng, story 24h, reaction 6 icon, bình luận phân cấp.
2. **Khám phá (`discover`):** Icon `compass`. Tìm kiếm, gợi ý xung quanh, bộ lọc theo vị trí.
3. **Tạo (`create`):** Icon `camera` / nút nổi ở giữa. Mở Camera Studio (chụp, quay, chọn nhạc, edit, đăng bài/story/shorts).
4. **Shorts (`shorts`):** Icon `clapperboard`. Video dọc toàn màn hình, cuộn chuyển video, tim, bình luận, chia sẻ.
5. **Trực tiếp (`live`):** Icon `radio`. Danh sách phòng live & nút phát trực tiếp (Live Setup Sheet: mode `chat` hoặc `game`).

---

## 3. Chi tiết hiện trạng Android & Đề xuất chỉnh sửa (Android Baseline & Fixes)

### 3.1 Bảng tin (Feed) & Bình luận
- **Hiện trạng:**
  - Hỗ trợ story bar trên đầu, danh sách bài viết đa ảnh/video.
  - Phản ứng 6 icon: `like`, `love`, `haha`, `wow`, `sad`, `angry`.
  - Bình luận đa cấp: reply vào bình luận con tự động quy về root ancestor để bảo đảm tương thích contract `/api/social/comments`.
- **Đề xuất chỉnh sửa:**
  - Chuẩn hóa padding lề card bài viết từ 16dp, bo góc 24dp đồng nhất.
  - Sửa cỡ chữ tên tác giả: 15sp Bold, timestamp: 12sp MUTED.
  - Emoji picker ở sheet bình luận: cuộn ngang mượt mà khi màn hình hẹp (320dp - 360dp) để không bị cắt xén icon.

### 3.2 Khám phá (Discover)
- **Hiện trạng:**
  - Ô tìm kiếm với debounced query; danh sách user gợi ý với nút Kết bạn / Theo dõi.
- **Đề xuất chỉnh sửa:**
  - Ô tìm kiếm bo góc 999 (pill), chiều cao 44dp, icon kính lúp trái, icon xóa phải khi có text.
  - Trạng thái rỗng (Empty state): icon minh họa gọn gàng, tiêu đề 16sp, mô tả 13sp MUTED.

### 3.3 Studio / Camera (`StudioActivity.java`)
- **Hiện trạng:**
  - Đã tích hợp chọn nhạc (`/api/music`) với normalized search, loading spinner, error retry và duration (`%d:%02d`).
  - Giao diện chọn ảnh/quay video, gắn nhạc nền, preview.
- **Đề xuất chỉnh sửa:**
  - Nút đóng và nút hoàn tất ở thanh Studio giữ kích thước 44dp, padding an toàn tránh chạm tai thỏ/camera cut-out.

### 3.4 Video ngắn (Shorts)
- **Hiện trạng:**
  - Chơi video thật (VerticalMediaStage), cuộn dọc chuyển bài.
  - Nút tim, comment, chia sẻ, âm thanh (mute/unmute) bên phải.
- **Đề xuất chỉnh sửa:**
  - Tiêu đề và caption bài viết giới hạn max 3 dòng, chạm để mở rộng (read more).

### 3.5 Phòng Live (`LiveActivity.java`) & Quà tặng (`LiveGiftExperience.java`)
- **Mã nguồn thực tế:** `LiveActivity.java` (không phải `LiveRoomActivity`), kết hợp `LiveSetupSheet.java`, `LiveGameLaunch.java`, `LiveGiftExperience.java`.
- **Hiện trạng:**
  - SoundPool âm thanh cho từng loại quà (WAV riêng trong `assets/gifts/`).
  - Drawer quà tặng với số lượng combo (1, 2, 5, 10, 50).
  - Game comment overlay (`GameCommentOverlay.java`).
- **Đề xuất chỉnh sửa (Chưa nghiệm thu runtime - cần chụp ảnh xác thực):**
  - Khớp giao diện gift drawer giữa Android và iOS (iOS cần cập nhật âm thanh & tier quà tương đương).

### 3.6 Tài khoản & Cài đặt (`MainActivity.java:meMenu()`)
- **Hiện trạng:**
  - Thứ tự menu: Sửa hồ sơ, Giao diện, Bảo mật & Đăng nhập, Thông báo, Quyền riêng tư, Ngôn ngữ, Trợ giúp, Đăng xuất.
  - Nếu `role=admin`: Hiện thêm mục Quản trị kinh tế & Quà, Tặng xu.
- **Đề xuất chỉnh sửa:**
  - Thống nhất các nhãn tiếng Việt / tiếng Anh và icon tương ứng giữa hai nền tảng.

---

## 4. Hướng dẫn đối chiếu dành cho Cursor (iOS)

1. **Token màu:** Vui lòng sử dụng đúng mã hex từ Bảng màu mục 1.1 trong `KinnectTheme.swift` để màu sắc hai bên trùng khớp 100%.
2. **Cỡ chữ:** Áp dụng scale mục 1.2: tiêu đề màn hình max 22pt, heading khối 16-17pt, body 15pt, caption 12-13pt.
3. **Endpoint hợp đồng:**
   - Mua gói store: Gọi `POST /api/store/packages/buy` (body `productId` hoặc `packageId`).
   - Áp trang trí: Gọi `POST /api/store/packages/apply`.
   - Đổi mật khẩu: Gọi `POST /api/me/password` (body `current` và `next`).
4. **Phản hồi:** Sau khi rà soát, Cursor cập nhật báo cáo vào `outputs/qa-20261112/ios/`.
