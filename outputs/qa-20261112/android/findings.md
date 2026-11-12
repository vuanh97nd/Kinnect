# Findings & Parity Review — Android Kinnect (2026-11-13)

- **Người thực hiện:** Antigravity IDE (phụ trách `android/`)
- **Đối tượng:** Mã nguồn Android native (`app.kinnect.live`)
- **Mức bằng chứng:** Static source analysis, contract verification & build toolchain check.

---

## 1. Bảng tổng hợp phát hiện (Findings Table)

| ID | Mức | Màn / Thành phần | Hiện trạng phát hiện | Giải pháp / Trạng thái |
|---|---|---|---|---|
| **AND-001** | P1 | Top bar & Account navigation | Chạm vào avatar (`meMenu`) không có trạng thái toggle rõ ràng, dễ bị lẫn lộn giữa tab hiện tại và menu tài khoản. | **Đã sửa trong dirty edit** `MainActivity.java`: thêm `headerActive = "account"` toggle, đóng mở linh hoạt và viền `ACCENT` cho avatar. |
| **AND-002** | P1 | Studio / Music Picker | Tìm kiếm nhạc không chuẩn hóa tiếng Việt có dấu, thiếu loading indicator khi gọi `/api/music`, thiếu nút thử lại khi lỗi mạng. | **Đã sửa trong dirty edit** `StudioActivity.java`: chuẩn hóa chuỗi `LiveGamePicker.normalized`, thêm Spinner, hiển thị thời lượng `%d:%02d`, nút thử lại khi fail. |
| **AND-003** | P2 | Live Room (`LiveActivity.java`) | Tên file trong tài liệu cũ bị nhầm thành `LiveRoomActivity.java`. Parity drawer quà tặng Android có âm thanh SoundPool nhưng iOS chưa đồng bộ file WAV. | **Đã chuẩn hóa** trong `ui-baseline.md`. Đề xuất giữ nguyên WAV engine/fanfare hiện có trên Android. |
| **AND-004** | P2 | Typography & Sheet Dialogs | Nguy cơ chữ quá to gây tràn lề trên màn hình nhỏ (< 360dp) nếu không có trần giới hạn. | `ApprovedTypography.java` đã áp đặt trần `sheet:title` (max 22sp), `Button` (max 15sp), `EditText` (max 16sp). Cần kiểm thử runtime fontScale 1.3. |
| **AND-005** | P2 | Mua gói Store & Wallet | Android dùng `StoreActivity.java` gọi `/api/store/packages/buy` và `/apply` đúng hợp đồng backend. (Phát hiện bên iOS `StoreView.swift` gọi nhầm `/api/store/buy` gây 404). | Đã thông báo trong baseline để Cursor đồng bộ sang endpoint `/api/store/packages/buy`. |

---

## 2. Bảng đối chiếu Parity Android ↔ iOS

| Mục kiểm tra | Android (Mã nguồn) | iOS (Tình trạng) | Trạng thái Parity |
|---|---|---|---|
| 5 Tab dưới | `feed`, `discover`, `create`, `shorts`, `live` | `feed`, `discover`, `create`, `video`, `live` | Khớp cấu trúc (iOS dùng `video` cho Shorts) |
| 5 Nút thanh trên | `notifications`, `store`, `friends`, `inbox`, `account` | `notifications`, `store`, `friends`, `messages`, `profile` | Khớp cấu trúc |
| Phản ứng bài viết | 6 phản ứng (like, love, haha, wow, sad, angry) | Cursor đã bổ sung long-press 6 reactions | Khớp |
| Hợp đồng đổi mật khẩu | `POST /api/me/password` (`current` + `next`) | Cursor đã sửa body khớp Android | Khớp |
| Âm thanh quà tặng Live | SoundPool với 20+ file WAV trong `assets/gifts/` | iOS chưa có audio playback cho quà tặng | Lệch (iOS cần bổ sung audio) |
| Module Admin trong app | `CoinGrantActivity.java`, `EconomyAdminActivity.java` | iOS chưa triển khai màn hình Admin | Lệch (iOS chờ triển khai) |

---

## 3. Khuyến nghị & Bước tiếp theo

1. Cursor tiếp tục đối chiếu các giá trị màu hex trong `KinnectTheme.swift` với `WebDesign.java` đã công bố ở `ui-baseline.md`.
2. Kiểm tra compile Android APK cục bộ thông qua `scripts/build-apk-windows.py` để bảo đảm không có lỗi gãy mã nguồn.
3. Kích hoạt workflow `.github/workflows/android-qa-emulator.yml` trên runner hỗ trợ KVM để lấy ảnh chụp thực tế.
