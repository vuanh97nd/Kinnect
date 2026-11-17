# Giải trình quyền `SYSTEM_ALERT_WINDOW` (Play Console)

**Cập nhật:** 2026-11-17 · **Áp dụng cho:** `app.kinnect.live` (bản Play, `android/play-release`)

## 1. Quyền được yêu cầu

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
```

## 2. Tính năng sử dụng

**Bình luận nổi khi phát live (floating live comments)** — `GameCommentOverlay.java`, kích hoạt từ `LiveActivity.requestGameProjection()` (`requestCode 324`) và bật/tắt trong `LiveSetupSheet` (checkbox "Bình luận nổi").

Khi người dùng phát live ở chế độ chơi game / chia sẻ màn hình, app không thể hiển thị bình luận trong cửa sổ của chính nó (người dùng đã chuyển sang app game). Overlay cho phép hiển thị một panel nhỏ, kéo được, chứa bình luận và ô trả lời, nằm trên app khác.

## 3. Vì sao không có lựa chọn thay thế tương đương

| Phương án | Vì sao không dùng |
|---|---|
| Picture-in-Picture | Chỉ hỗ trợ một cửa sổ video, không render được danh sách bình luận tương tác + ô nhập liệu |
| Notification | Không đủ không gian, không cuộn được, không trả lời nhanh |
| Vẽ trong cửa sổ app | Không hiển thị được khi người dùng đã rời app sang game |
| `MediaProjection` + vẽ đè | Cần quyền chia sẻ màn hình, độ trễ cao, không nhận được touch |

## 4. Luồng xin quyền trong app (đúng chuẩn Play)

1. Quyền **chỉ được xin khi người dùng chủ động bật** checkbox "Bình luận nổi" trong sheet thiết lập live.
2. Trước khi mở Settings hệ thống, app **không** yêu cầu quyền ở bất kỳ luồng nào khác (không xin lúc khởi động, không xin khi đăng nhập).
3. Nếu người dùng từ chối: app hiển thị thông báo *"Chưa bật bình luận nổi; vẫn có thể phát game."* và **tiếp tục phát bình thường** — không chặn tính năng chính.
4. Kiểm tra lại bằng `Settings.canDrawOverlays(this)` trước mỗi lần hiển thị overlay; không có quyền thì không tạo cửa sổ.

## 5. Phạm vi dữ liệu

Overlay chỉ hiển thị bình luận của phòng live hiện tại mà người dùng đang phát. Không đọc nội dung app khác, không chụp màn hình, không ghi lại thao tác người dùng.

## 6. Cam kết

Quyền này không dùng cho mục đích quảng cáo, không hiển thị nội dung ngoài ngữ cảnh live của chính người dùng, và có thể gỡ bỏ bất kỳ lúc nào bằng cách tắt checkbox trong app hoặc thu hồi trong Settings hệ thống.
