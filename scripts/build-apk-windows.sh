#!/usr/bin/env bash
# Local Windows build using work/android-tools. Usage: bash scripts/build-apk-windows.sh 0.8.9
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$1"
T=work/android-tools; B=$T/build-tools/android-15; P=$T/platform/android-35-ext15/android.jar; D=$T/deps
export JAVA_HOME="$PWD/$T/jdk/jdk-21.0.8+9"; export PATH="$JAVA_HOME/bin:$PATH"
rm -rf android/build; mkdir -p android/build/classes android/build/dex dist
$B/aapt2.exe compile --dir android/app/src/main/res -o android/build/resources.zip
$B/aapt2.exe link android/build/resources.zip -I $P --manifest android/app/src/main/AndroidManifest.xml -o android/build/unsigned.apk
java -jar $T/ecj.jar -1.8 -encoding UTF-8 -proc:none -nowarn -bootclasspath "$P;$B/core-lambda-stubs.jar" -classpath "$D/webrtc/classes.jar;$D/okhttp.jar;$D/okio.jar" -d android/build/classes android/app/src/main/java/app/kinnect/live/*.java
find android/build/classes -name '*.class' > android/build/classes.list
cmd //c "$(cygpath -w $B/d8.bat) --min-api 26 --lib $(cygpath -w $P) --output android\\build\\dex @android\\build\\classes.list $(cygpath -w $D/webrtc/classes.jar) $(cygpath -w $D/okhttp.jar) $(cygpath -w $D/okio.jar)"
python - "$D/webrtc" <<'PY'
import sys,zipfile,pathlib,glob
root=pathlib.Path(sys.argv[1])
with zipfile.ZipFile('android/build/unsigned.apk','a') as out:
 for f in sorted(glob.glob('android/build/dex/classes*.dex')): out.write(f,pathlib.Path(f).name)
 for path in (root/'jni').rglob('*.so'): out.write(path,'lib/'+path.relative_to(root/'jni').as_posix(),compress_type=zipfile.ZIP_STORED)
PY
$B/zipalign.exe -P 16 -f 4 android/build/unsigned.apk android/build/aligned.apk
cmd //c "$(cygpath -w $B/apksigner.bat) sign --ks android\\debug.keystore --ks-pass pass:android --key-pass pass:android --out dist\\Kinnect-$VERSION-native.apk android\\build\\aligned.apk"
cmd //c "$(cygpath -w $B/apksigner.bat) verify --print-certs dist\\Kinnect-$VERSION-native.apk" | grep SHA-256
(cd dist && sha256sum "Kinnect-$VERSION-native.apk" > "Kinnect-$VERSION-native.apk.sha256")
