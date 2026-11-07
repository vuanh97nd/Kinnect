# Kinnect Farm (bản APK thử nghiệm)

Nông trại 3D cổ điển (prototype WebView) — **tiếng Việt toàn bộ UI**.

## Chơi trên trình duyệt

```bash
cd farm/www
python3 -m http.server 8765
# Mở http://127.0.0.1:8765
```

## Build APK debug

Cần Android SDK (`platforms;android-35`, `build-tools;35.0.0`) tại `toolchains/android-sdk` hoặc `$ANDROID_SDK_ROOT`.

```bash
./scripts/build-farm-apk.sh
```

Ra file: `dist/KinnectFarm-0.1.0-debug.apk`  
Package: `app.kinnect.farm` (tách với Kinnect Live).

Cài: `adb install -r dist/KinnectFarm-0.1.0-debug.apk`

## Đã khóa theo concept

- Splash: logo **Kinnect** → **Kinnect Farm**
- Look cổ điển, ấm, analog
- Thiết kế online-shaped + stub làng khi chưa có máy chủ
- Mạng Kinnect (dây cây tương thích), Chợ Đêm, thung lũng, sổ tay
