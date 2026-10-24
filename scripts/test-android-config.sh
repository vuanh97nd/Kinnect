#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
KINNECT_TOOLS="${KINNECT_TOOLS:-/workspace/toolchains}"
mkdir -p android/build/config-tests
java -jar "$KINNECT_TOOLS/ecj.jar" -1.8 -proc:none -bootclasspath "$KINNECT_TOOLS/android/android-35-ext15/android.jar" -d android/build/config-tests android/app/src/main/java/app/kinnect/live/ServerConfig.java android/test/ServerConfigTest.java
java -cp android/build/config-tests app.kinnect.live.ServerConfigTest
