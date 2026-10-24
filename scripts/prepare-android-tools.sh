#!/usr/bin/env bash
set -euo pipefail
KINNECT_TOOLS="${KINNECT_TOOLS:-/workspace/toolchains}"
mkdir -p "$KINNECT_TOOLS/android"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
fetch_verified() {
  local url="$1" expected="$2" destination="$3"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 2 --output "$destination" "$url"
  echo "$expected  $destination" | sha256sum --check --status
}
# SHA-256 pinned from archives previously verified against Google's repository
# metadata / Maven's published checksum. Never disable verification on mismatch.
fetch_verified 'https://dl.google.com/android/repository/platform-35-ext15_r01.zip' 'a93712aedd4f851d9cf1f7281f7c4fe5581ce03a9df37ffc8c53a487eadf311f' "$work_dir/platform.zip"
fetch_verified 'https://dl.google.com/android/repository/build-tools_r35_linux.zip' 'bd3a4966912eb8b30ed0d00b0cda6b6543b949d5ffe00bea54c04c81e1561d88' "$work_dir/build-tools.zip"
fetch_verified 'https://repo.maven.apache.org/maven2/org/eclipse/jdt/ecj/3.39.0/ecj-3.39.0.jar' '01f5a92ac19bb2b3bf85e295a68f2c73c264369109158b566ce9b490af982948' "$work_dir/ecj.jar"
unzip -oq "$work_dir/platform.zip" -d "$KINNECT_TOOLS/android"
unzip -oq "$work_dir/build-tools.zip" -d "$KINNECT_TOOLS/android"
cp "$work_dir/ecj.jar" "$KINNECT_TOOLS/ecj.jar"
chmod +x "$KINNECT_TOOLS/android/android-15/"{aapt,aapt2,d8,apksigner,zipalign}
echo 'Android toolchain downloaded and checksums verified.'

# Native media and signaling libraries, pinned by SHA-256.
mkdir -p "$KINNECT_TOOLS/deps/webrtc"
fetch_verified 'https://repo.maven.apache.org/maven2/io/github/webrtc-sdk/android/144.7559.09/android-144.7559.09.aar' '34cf91dd7497e5fe88adb76ba29ccae35db42dd6614ce548b79ce037b6d634d5' "$KINNECT_TOOLS/deps/webrtc.aar"
fetch_verified 'https://repo.maven.apache.org/maven2/com/squareup/okhttp3/okhttp/3.12.13/okhttp-3.12.13.jar' '508234e024ef7e270ab1a6d5b356f5b98e786511239ca986d684fd1e2cf7bc82' "$KINNECT_TOOLS/deps/okhttp.jar"
fetch_verified 'https://repo.maven.apache.org/maven2/com/squareup/okio/okio/1.17.2/okio-1.17.2.jar' 'f80ce42d2ffac47ad4c47e1d6f980d604d247ceb1a886705cf4581ab0c9fe2b8' "$KINNECT_TOOLS/deps/okio.jar"
unzip -oq "$KINNECT_TOOLS/deps/webrtc.aar" -d "$KINNECT_TOOLS/deps/webrtc"
