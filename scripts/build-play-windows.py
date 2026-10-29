"""Build a source-reproducible API 36 Play AAB and validate it with bundletool.
Local upload credentials are created outside version control, never in source/logs.
"""
from pathlib import Path
import subprocess,json,os,zipfile,shutil,hashlib,secrets,argparse,xml.etree.ElementTree as E
args=argparse.ArgumentParser();args.add_argument('--initialize-upload-key',action='store_true');options=args.parse_args()
r=Path(__file__).resolve().parents[1];os.chdir(r);tools=r/'work/android-tools';jdk=next((tools/'jdk').glob('jdk-*'))/'bin';cfg=json.loads((r/'work/play-tools/tools.json').read_text());aapt=Path(cfg['aapt2']);bt=Path(cfg['buildTools']);platform=Path(cfg['platform']);bundle=Path(cfg['bundletool']);w=r/'android/build/play';w.mkdir(exist_ok=True);out=r/'dist/google-play';out.mkdir(parents=True,exist_ok=True)
def run(*args,env=None):subprocess.run([str(a) for a in args],check=True,env=env,cwd=r)
run('python',r/'scripts/sync-android-languages.py')
ns='{http://schemas.android.com/apk/res/android}';E.register_namespace('android',ns[1:-1]);m=E.parse(r/'android/app/src/main/AndroidManifest.xml');root=m.getroot();overlay=E.parse(r/'android/app/src/play/AndroidManifest.xml').getroot();root.set(ns+'versionCode',overlay.get(ns+'versionCode'));root.set(ns+'versionName',overlay.get(ns+'versionName'));root.find('uses-sdk').set(ns+'targetSdkVersion',overlay.find('uses-sdk').get(ns+'targetSdkVersion'))
remove={'REQUEST_INSTALL_PACKAGES','REQUEST_IGNORE_BATTERY_OPTIMIZATIONS','READ_MEDIA_IMAGES','READ_MEDIA_VIDEO','READ_MEDIA_VISUAL_USER_SELECTED','READ_EXTERNAL_STORAGE','ACCESS_NOTIFICATION_POLICY','DISABLE_KEYGUARD','TURN_SCREEN_ON','RECEIVE_BOOT_COMPLETED','FOREGROUND_SERVICE_PHONE_CALL','FOREGROUND_SERVICE_MICROPHONE','FOREGROUND_SERVICE_CAMERA'}
for p in list(root.findall('uses-permission')):
 if p.get(ns+'name','').split('.')[-1] in remove:root.remove(p)
app=root.find('application');app.set(ns+'debuggable','false');app.set(ns+'allowBackup','false')
for child in list(app):
 if child.get(ns+'name') in ['.ApkUpdateActivity','.ApkUpdateProvider']:app.remove(child)
 if child.get(ns+'name')=='.CallActionReceiver':
  child.set(ns+'exported','false')
  for intent in child.findall('intent-filter'):child.remove(intent)
manifest=w/'AndroidManifest.xml';m.write(manifest,encoding='utf-8',xml_declaration=True)
generated=w/'generated/app/kinnect/live';generated.mkdir(parents=True,exist_ok=True)
(generated/'Distribution.java').write_text('package app.kinnect.live; public final class Distribution { public static final boolean PLAY=true; private Distribution(){} }')
(generated/'ApkUpdates.java').write_text('''package app.kinnect.live;
import android.app.Activity;import android.content.Intent;import android.net.Uri;
public final class ApkUpdates { public static void check(Activity activity){try{activity.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse("market://details?id="+activity.getPackageName())).setPackage("com.android.vending"));}catch(Exception ignored){activity.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse("https://play.google.com/store/apps/details?id="+activity.getPackageName())));}}}
''')
for folder in ['classes','dex']:
 path=(w/folder).resolve()
 if not path.is_relative_to(w.resolve()):raise RuntimeError('Unexpected build path')
 if path.exists():shutil.rmtree(path)
 path.mkdir()
deps=tools/'deps';jars=[deps/'webrtc/classes.jar']+[Path(d['file']) for d in json.loads((r/'work/play-tools/dependencies/dependencies.json').read_text())];excluded={'Distribution.java','ApkUpdates.java','ApkUpdateActivity.java','ApkUpdateProvider.java','ApkUpdatePolicy.java'};sources=[p for p in (r/'android/app/src/main/java/app/kinnect/live').glob('*.java') if p.name not in excluded]+list(generated.glob('*.java'))
run(aapt,'compile','--dir',r/'android/app/src/main/res','-o',w/'resources.zip');run(aapt,'link','--proto-format','--auto-add-overlay','-R',w/'resources.zip','-I',platform,'--manifest',manifest,'-o',w/'resources.apk')
run(jdk/'java.exe','-jar',tools/'ecj.jar','-1.8','-encoding','UTF-8','-proc:none','-warn:none','-bootclasspath',str(platform)+';'+str(bt/'core-lambda-stubs.jar'),'-classpath',';'.join(map(str,jars)),'-d',w/'classes',*sources)
listing=w/'classes.list';listing.write_text('\n'.join(str(p.resolve())for p in (w/'classes').rglob('*.class')));run(jdk/'java.exe','-cp',bt/'lib/d8.jar','com.android.tools.r8.D8','--min-api','26','--lib',platform,'--output',w/'dex','@'+str(listing),*jars)
with zipfile.ZipFile(w/'base.zip','w',zipfile.ZIP_DEFLATED) as z:
 with zipfile.ZipFile(w/'resources.apk') as linked:
  for info in linked.infolist():z.writestr('manifest/AndroidManifest.xml' if info.filename=='AndroidManifest.xml' else info.filename,linked.read(info.filename))
 for p in (w/'dex').glob('*.dex'):z.write(p,'dex/'+p.name)
 for p in (deps/'webrtc/jni').rglob('*.so'):z.write(p,'lib/'+p.relative_to(deps/'webrtc/jni').as_posix())
 for i,name in enumerate(['welcome-profile.png','welcome-profile-1.png','welcome-profile-2.png','welcome-profile-3.png']):z.write(r/'website/dist/people'/('2.jpg' if i%2==0 else '1.jpg'),'assets/'+name)
 # Assets used by onboarding must be complete in the source build.
 assets=r/'android/app/src/main/assets'
 if assets.exists():
  for p in assets.rglob('*'):
   if p.is_file():z.write(p,'assets/'+p.relative_to(assets).as_posix())
unsigned=w/'unsigned.aab'
if unsigned.exists():unsigned.unlink()
run(jdk/'java.exe','-jar',bundle,'build-bundle','--modules='+str(w/'base.zip'),'--output='+str(unsigned))
# A dedicated upload key is separate from the existing website APK signing key.
private=r/'work/play-signing';private.mkdir(exist_ok=True);key=private/'upload.jks';password=private/'store-password.txt'
if not key.exists():
 if not options.initialize_upload_key:raise RuntimeError('Upload key absent. Restore the existing key, or explicitly initialize once with --initialize-upload-key.')
 password.write_text(secrets.token_urlsafe(40),encoding='utf8');env=os.environ.copy();env['KINNECT_PLAY_PASS']=password.read_text()
 run(jdk/'keytool.exe','-genkeypair','-keystore',key,'-storetype','JKS','-storepass:env','KINNECT_PLAY_PASS','-keypass:env','KINNECT_PLAY_PASS','-alias','kinnect-upload','-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=Mr Anh,OU=Kinnect,O=Kinnect',env=env)
env=os.environ.copy();env['KINNECT_PLAY_PASS']=password.read_text();aab=out/'Kinnect-1.1.1-play.aab';shutil.copy2(unsigned,aab)
run(jdk/'jarsigner.exe','-keystore',key,'-storepass:env','KINNECT_PLAY_PASS','-keypass:env','KINNECT_PLAY_PASS',aab,'kinnect-upload',env=env)
run(jdk/'java.exe','-jar',bundle,'validate','--bundle='+str(aab));run(jdk/'jarsigner.exe','-verify',aab)
apks=w/'universal.apks'
if apks.exists():apks.unlink()
run(jdk/'java.exe','-jar',bundle,'build-apks','--bundle='+str(aab),'--output='+str(apks),'--mode=universal','--ks='+str(key),'--ks-key-alias=kinnect-upload','--ks-pass=file:'+str(password),'--key-pass=file:'+str(password))
with zipfile.ZipFile(apks) as z:(out/'Kinnect-1.1.1-play-test.apk').write_bytes(z.read('universal.apk'))
run(bt/'zipalign.exe','-c','-P','16','4',out/'Kinnect-1.1.1-play-test.apk')
for p in [aab,out/'Kinnect-1.1.1-play-test.apk']:p.with_suffix(p.suffix+'.sha256').write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n')
run(jdk/'keytool.exe','-exportcert','-rfc','-keystore',key,'-storepass:env','KINNECT_PLAY_PASS','-alias','kinnect-upload','-file',out/'upload-certificate.pem',env=env)
print('Play bundle built and validated. Store-private signing material remains in work/play-signing.')
