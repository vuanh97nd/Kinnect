# Module game Nông trại Kinnect

Thư mục này là một ứng dụng Android riêng cho game Nông trại. Game không nằm trong APK Kinnect chính; app chính tải module khi người dùng muốn chơi.

## Cấu trúc

- `build.gradle`: module application `:farm-game`, applicationId `app.kinnect.farm`. Nguồn dùng chung của Kinnect được lấy từ `android/app/src/main/java` và `android/app/src/play/java`; tài nguyên lấy từ `android/app/src/main/res`. Chỉ mã game nằm trong `src/main/java/app/kinnect/live`.
- `src/main/AndroidManifest.xml`: app độc lập, biểu tượng riêng, mở thẳng vào `FarmActivity` ở màn hình ngang.
- Mã game: `FarmActivity`, `Farm3DView`, `FarmLogoView`.
- App chính: `FarmGameModule` quản lý trạng thái, `FarmGameDownloadActivity` tải APK, `FarmGameProvider` cấp tệp cho trình cài đặt Android.

## Tải và cài

1. Người dùng mở mục Trò chơi, chọn Nông trại.
2. Nếu module chưa cài, app chính hiện bảng giới thiệu và nút Tải module.
3. APK được tải từ `GET /download/farm-game` của máy chủ Kinnect và kiểm tra:
   - đúng package `app.kinnect.farm`;
   - cùng chữ ký với app Kinnect đang cài;
   - phiên bản mới hơn bản đã cài nếu có.
4. Trình cài đặt Android mở ra; sau khi cài, game tự mở.

APK đặt trong `dist/FarmGame-<phiên bản>.apk` khi phát hành. Route máy chủ chọn bản mới nhất.

## Phiên đăng nhập

App chính truyền `origin` và cookie `kinnect_session` qua Intent. `NativeApi.adopt` lưu phiên vào SessionStore của game, nên lần mở sau từ biểu tượng Nông trại vẫn dùng được phiên đã lưu. Khi phiên hết hạn, mở lại game từ Kinnect để chuyển phiên mới. Không có mật khẩu nào được ghi vào Intent hay log.

## Build

Trong Android Studio, project `android/play-release` đã include `:farm-game`:

```
gradlew :farm-game:assembleDebug
```

APK ở `android/build/farm-game/outputs/apk/debug/`. Bản phát hành dùng cùng khóa ký với Kinnect để app chính kiểm tra chữ ký.

## Lưu ý phân phối

Cài APK trực tiếp phù hợp bản APK/GitHub. Bản phát hành qua Google Play cần chuyển sang Play Feature Delivery hoặc phát hành module như một app riêng trên Play; không dùng cơ chế tải APK trực tiếp trong bản Play.
