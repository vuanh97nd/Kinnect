#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
KINNECT_TOOLS="${KINNECT_TOOLS:-/workspace/toolchains}"
TOOLS="$KINNECT_TOOLS/android/android-15"
PLATFORM="$KINNECT_TOOLS/android/android-35-ext15/android.jar"
mkdir -p android/build/classes android/build/dex dist
"$TOOLS/aapt2" compile --dir android/app/src/main/res -o android/build/resources.zip
"$TOOLS/aapt2" link -R android/build/resources.zip -I "$PLATFORM" --manifest android/app/src/main/AndroidManifest.xml -o android/build/unsigned.apk
java -jar "$KINNECT_TOOLS/ecj.jar" -1.8 -proc:none -bootclasspath "$PLATFORM:$TOOLS/core-lambda-stubs.jar" -d android/build/classes android/app/src/main/java/app/kinnect/live/*.java
find android/build/classes -name '*.class' -print > android/build/classes.list
"$TOOLS/d8" --min-api 26 --lib "$PLATFORM" --output android/build/dex @android/build/classes.list
(cd android/build/dex && zip -q -u ../unsigned.apk classes.dex)
"$TOOLS/zipalign" -f 4 android/build/unsigned.apk android/build/aligned.apk
# Local testing key only. Keep it outside version control; never use for Play releases.
if [ ! -f android/debug.keystore ]; then
 keytool -genkeypair -keystore android/debug.keystore -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Kinnect Debug,O=Development,C=VN'
fi
"$TOOLS/apksigner" sign --ks android/debug.keystore --ks-pass pass:android --key-pass pass:android --out dist/kinnect-live-debug.apk android/build/aligned.apk
"$TOOLS/apksigner" verify --verbose dist/kinnect-live-debug.apk
