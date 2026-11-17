#!/usr/bin/env bash
# run-jvm-tests.sh — chạy các audit thuần JVM trong android/test (KHÔNG cần emulator).
#
# Nhóm này có `public static void main(String[])` và chỉ kiểm tra logic thuần:
# cache mã hoá, sampling ảnh, policy, version, config... Chạy được trên runner Linux
# nên dùng làm gate CI.
#
# 33 lớp `extends Instrumentation` KHÔNG chạy ở đây — chúng cần emulator/thiết bị thật.
#
# Dùng: bash scripts/run-jvm-tests.sh
# Exit: 0 = mọi test chạy được đều PASS · 1 = có test FAIL · 2 = lỗi môi trường

set -uo pipefail
cd "$(dirname "$0")/.."

JAVA_BIN="${JAVA_BIN:-java}"
if ! command -v "$JAVA_BIN" >/dev/null 2>&1; then
  if [ -x "work/android-tools/jdk/jdk-21.0.8+9/bin/java" ]; then
    JAVA_BIN="work/android-tools/jdk/jdk-21.0.8+9/bin/java"
  else
    echo "Không tìm thấy java. Đặt JAVA_BIN=... hoặc cài JDK 21." >&2
    exit 2
  fi
fi

# Toolchain: layout CI (/tmp/kinnect-android-tools) hoặc layout local (work/android-tools).
if [ -n "${KINNECT_TOOLS:-}" ] && [ -d "$KINNECT_TOOLS/android/android-15" ]; then
  ROOT="$KINNECT_TOOLS"
  TOOLS="$KINNECT_TOOLS/android/android-15"
  PLATFORM="$KINNECT_TOOLS/android/android-35-ext15/android.jar"
  ECJ="$KINNECT_TOOLS/ecj.jar"
else
  ROOT="work/android-tools"
  TOOLS="$ROOT"
  PLATFORM="$ROOT/platform/android-35-ext15/android.jar"
  ECJ="$ROOT/ecj.jar"
fi

# core-lambda-stubs.jar bắt buộc có trên bootclasspath, nếu không ECJ báo
# "java.lang.invoke.LambdaMetafactory cannot be resolved".
LAMBDA="$(find "$ROOT" -name core-lambda-stubs.jar 2>/dev/null | head -1)"
if [ -z "$LAMBDA" ]; then
  LAMBDA="$(find "$TOOLS" -name core-lambda-stubs.jar 2>/dev/null | head -1)"
fi

for f in "$PLATFORM" "$ECJ" "$LAMBDA"; do
  [ -n "$f" ] && [ -f "$f" ] || { echo "Thiếu file toolchain: ${f:-core-lambda-stubs.jar}" >&2; exit 2; }
done

OUT="android/build/jvm-tests"
rm -rf "$OUT"; mkdir -p "$OUT"

# Classpath phụ: WebRTC + jar mạng đã tải (okhttp, billing...).
EXTRA_CP=""
[ -f "$ROOT/deps/webrtc/classes.jar" ] && EXTRA_CP="$ROOT/deps/webrtc/classes.jar"
if [ -f work/play-tools/dependencies/dependencies.json ]; then
  NETWORK_CP="$(python3 - <<'PY'
import json
try:
    d = json.load(open('work/play-tools/dependencies/dependencies.json'))
    print(';'.join(x['file'].replace('\\', '/') for x in d))
except Exception:
    print('')
PY
)"
  [ -n "$NETWORK_CP" ] && EXTRA_CP="${EXTRA_CP:+$EXTRA_CP;}$NETWORK_CP"
fi

TESTS="AppCacheTest LiveSwipePolicyTest MediaImageLoaderTest MediaTypeTest NativeMediaStreamTest PcmMixerTest ReleaseVersionTest ServerConfigTest VideoFeedPolicyTest YuvBeautyTest"

TEST_FILES=()
for t in $TESTS; do
  [ -f "android/test/$t.java" ] && TEST_FILES+=("android/test/$t.java")
done
if [ ${#TEST_FILES[@]} -eq 0 ]; then
  echo "Không tìm thấy file test nào trong android/test." >&2
  exit 2
fi

echo "== Biên dịch app + ${#TEST_FILES[@]} audit thuần JVM =="
COMPILE_LOG="$OUT/compile.log"
# ECJ trên Windows dùng ';' làm separator; dùng đường dẫn tương đối để tránh
# dấu ':' trong ổ đĩa bị hiểu nhầm là separator.
"$JAVA_BIN" -jar "$ECJ" -1.8 -proc:none -nowarn \
  -bootclasspath "$PLATFORM;$LAMBDA" \
  -classpath "${EXTRA_CP:-$PLATFORM}" \
  -d "$OUT" android/app/src/main/java/app/kinnect/live/*.java "${TEST_FILES[@]}" >"$COMPILE_LOG" 2>&1

if ! ls "$OUT"/app/kinnect/live/*Test.class >/dev/null 2>&1; then
  echo "Biên dịch thất bại — không sinh được class test. 20 dòng cuối:" >&2
  tail -20 "$COMPILE_LOG" >&2
  exit 2
fi
if grep -q "problems (" "$COMPILE_LOG"; then
  echo "  (có cảnh báo biên dịch — xem $COMPILE_LOG)"
fi

pass=0; fail=0; skip=0; failed_names=()
for t in $TESTS; do
  [ -f "android/test/$t.java" ] || continue
  if [ ! -f "$OUT/app/kinnect/live/$t.class" ]; then
    skip=$((skip+1)); printf '  SKIP  %s (không biên dịch được — cần Android runtime)\n' "$t"
    continue
  fi
  log="$OUT/$t.log"
  "$JAVA_BIN" -cp "$OUT${EXTRA_CP:+;$EXTRA_CP}" "app.kinnect.live.$t" >"$log" 2>&1
  code=$?
  if [ $code -eq 0 ]; then
    pass=$((pass+1)); printf '  PASS  %s\n' "$t"
  elif grep -qE "NoClassDefFoundError: android|ClassNotFoundException: android" "$log"; then
    skip=$((skip+1)); printf '  SKIP  %s (cần runtime Android)\n' "$t"
  else
    fail=$((fail+1)); failed_names+=("$t")
    printf '  FAIL  %s\n' "$t"
    tail -n 6 "$log" | sed 's/^/        /'
  fi
done

echo
echo "== Kết quả: $pass pass, $fail fail, $skip skip =="
if [ "$fail" -gt 0 ]; then
  echo "Test thất bại: ${failed_names[*]}" >&2
  exit 1
fi
if [ "$pass" -eq 0 ]; then
  echo "Không test nào chạy được — coi như lỗi cấu hình." >&2
  exit 2
fi
echo "OK"
