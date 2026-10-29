"""Build the native Android APK with verified toolchain prepared in work/android-tools."""
from pathlib import Path
import subprocess,zipfile,os,hashlib,shutil
root=Path(__file__).resolve().parent.parent
os.chdir(root)
tools=root/'work/android-tools';jdk=next((tools/'jdk').glob('jdk-*'))/'bin';build=tools/'build-tools/android-15';platform=tools/'platform/android-35-ext15/android.jar';deps=tools/'deps'
import re
version=re.search(r'versionName="([^"]+)"',Path('android/app/src/main/AndroidManifest.xml').read_text(encoding='utf-8')).group(1)
def run(*args):subprocess.run([str(a) for a in args],check=True)
for folder in ['android/build/native-store/classes','android/build/native-store/dex']:
 target=(root/folder).resolve()
 if not target.is_relative_to((root/'android/build').resolve()):raise ValueError('Build path escapes android/build')
 if target.exists():shutil.rmtree(target)
 target.mkdir(parents=True)
Path('dist').mkdir(exist_ok=True)
run('python','scripts/sync-android-languages.py')
run(build/'aapt2.exe','compile','--dir','android/app/src/main/res','-o','android/build/resources.zip')
run(build/'aapt2.exe','link','--auto-add-overlay','-R','android/build/resources.zip','-I',platform,'--manifest','android/app/src/main/AndroidManifest.xml','-o','android/build/unsigned.apk')
jars=[deps/'webrtc/classes.jar']+[Path(d['file']) for d in __import__('json').loads((root/'work/play-tools/dependencies/dependencies.json').read_text())]
run(jdk/'java.exe','-jar',tools/'ecj.jar','-1.8','-encoding','UTF-8','-proc:none','-warn:none','-bootclasspath',str(platform)+';'+str(build/'core-lambda-stubs.jar'),'-classpath',';'.join(map(str,jars)),'-d','android/build/native-store/classes',*Path('android/app/src/main/java/app/kinnect/live').glob('*.java'))
classes=Path('android/build/native-store/classes.list');classes.write_text('\n'.join(str(p.resolve()) for p in Path('android/build/native-store/classes').rglob('*.class')))
run(jdk/'java.exe','-cp',build/'lib/d8.jar','com.android.tools.r8.D8','--min-api','26','--lib',platform,'--output','android/build/native-store/dex','@'+str(classes),*jars)
with zipfile.ZipFile('android/build/unsigned.apk','a') as out:
 for name in ['welcome-profile.png','welcome-profile-1.png','welcome-profile-2.png','welcome-profile-3.png']:
  source=root/'public'/name
  if not source.is_file():raise FileNotFoundError('Missing intro image: '+name)
  out.write(source,'assets/'+name)
 for p in Path('android/app/src/main/assets').rglob('*'):
  if p.is_file():out.write(p,'assets/'+p.relative_to('android/app/src/main/assets').as_posix())
 for p in Path('android/build/native-store/dex').glob('*.dex'):out.write(p,p.name)
 for p in (deps/'webrtc/jni').rglob('*.so'):out.write(p,'lib/'+p.relative_to(deps/'webrtc/jni').as_posix(),compress_type=zipfile.ZIP_STORED)
run(build/'zipalign.exe','-P','16','-f','4','android/build/unsigned.apk','android/build/aligned.apk')
if not Path('android/debug.keystore').exists():run(jdk/'keytool.exe','-genkeypair','-keystore','android/debug.keystore','-storepass','android','-keypass','android','-alias','androiddebugkey','-keyalg','RSA','-keysize','2048','-validity','10000','-dname','CN=Kinnect Testing,O=Kinnect,C=VN')
run(jdk/'java.exe','-jar',build/'lib/apksigner.jar','sign','--ks','android/debug.keystore','--ks-pass','pass:android','--key-pass','pass:android','--out',f'dist/Kinnect-{version}-native.apk','android/build/aligned.apk')
run(jdk/'java.exe','-jar',build/'lib/apksigner.jar','verify','--verbose','--print-certs',f'dist/Kinnect-{version}-native.apk')
p=Path(f'dist/Kinnect-{version}-native.apk');Path(str(p)+'.sha256').write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n')
print('Native APK:',p.resolve())
