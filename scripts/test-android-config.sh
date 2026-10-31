#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
KINNECT_TOOLS="${KINNECT_TOOLS:-/workspace/toolchains}"
mkdir -p android/build/config-tests
for test in ServerConfig ReleaseVersion VideoFeedPolicy; do
  extra=""
  if [ "$test" = "ServerConfig" ]; then extra="android/app/src/main/java/app/kinnect/live/I18n.java"; fi
  java -jar "$KINNECT_TOOLS/ecj.jar" -1.8 -proc:none -encoding UTF-8 -bootclasspath "$KINNECT_TOOLS/android/android-35-ext15/android.jar" -d android/build/config-tests "android/app/src/main/java/app/kinnect/live/$test.java" "android/test/${test}Test.java" $extra
  java -cp android/build/config-tests "app.kinnect.live.${test}Test"
done
