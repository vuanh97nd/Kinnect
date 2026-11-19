#!/usr/bin/env bash
# Đóng gói Kinnect Farm (debug APK).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK="${ANDROID_SDK_ROOT:-$ROOT/toolchains/android-sdk}"
BT="$SDK/build-tools/35.0.0"
PLATFORM="$SDK/platforms/android-35/android.jar"
AAPT2="$BT/aapt2"
D8="$BT/d8"
ZIPALIGN="$BT/zipalign"
APKSIGNER="$BT/apksigner"

if [[ ! -x "$AAPT2" || ! -f "$PLATFORM" ]]; then
  echo "Thiếu Android SDK tại $SDK. Cài platforms;android-35 và build-tools;35.0.0 trước." >&2
  exit 1
fi

WWW="$ROOT/farm/www"
ASSETS="$ROOT/farm/android/app/src/main/assets"
RES="$ROOT/farm/android/app/src/main/res"
MANIFEST="$ROOT/farm/android/app/src/main/AndroidManifest.xml"
JAVA_SRC="$ROOT/farm/android/app/src/main/java/app/kinnect/farm/MainActivity.java"
BUILD="$ROOT/farm/android/build"
DIST="$ROOT/dist"

rm -rf "$BUILD" "$ASSETS"
mkdir -p "$ASSETS" "$BUILD/classes" "$BUILD/dex" "$BUILD/compiled" "$DIST"

# Đồng bộ web game vào assets (toàn bộ chuỗi UI tiếng Việt).
cp -a "$WWW/." "$ASSETS/"

echo "→ Biên dịch tài nguyên"
"$AAPT2" compile --dir "$RES" -o "$BUILD/compiled/"
mapfile -t FLATS < <(find "$BUILD/compiled" -name '*.flat' | sort)
"$AAPT2" link \
  -I "$PLATFORM" \
  --manifest "$MANIFEST" \
  -A "$ASSETS" \
  -o "$BUILD/unsigned.apk" \
  "${FLATS[@]}"

echo "→ Biên dịch Java"
mkdir -p "$BUILD/classes"
javac --release 8 \
  -classpath "$PLATFORM" \
  -d "$BUILD/classes" \
  "$JAVA_SRC"

echo "→ Dex"
find "$BUILD/classes" -name '*.class' > "$BUILD/classes.list"
"$D8" --min-api 26 --lib "$PLATFORM" --output "$BUILD/dex" @"$BUILD/classes.list"
(
  cd "$BUILD/dex"
  zip -q -u ../unsigned.apk classes.dex
)

echo "→ Zipalign + ký debug"
"$ZIPALIGN" -f 4 "$BUILD/unsigned.apk" "$BUILD/aligned.apk"
KS="$ROOT/farm/android/debug.keystore"
if [[ ! -f "$KS" ]]; then
  keytool -genkeypair \
    -keystore "$KS" \
    -storepass android -keypass android \
    -alias androiddebugkey \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname 'CN=Kinnect Farm Debug,O=Kinnect,C=VN'
fi
OUT="$DIST/KinnectFarm-0.1.0-debug.apk"
"$APKSIGNER" sign \
  --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out "$OUT" "$BUILD/aligned.apk"
"$APKSIGNER" verify --verbose "$OUT"

echo "✓ Xong: $OUT"
ls -lh "$OUT"
