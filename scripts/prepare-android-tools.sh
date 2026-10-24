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
