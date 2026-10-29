"""Build the Play store variant with Google's Billing SDK and Android manifest merger."""
from pathlib import Path
import hashlib,json,urllib.request,zipfile,subprocess,os,shutil,xml.etree.ElementTree as E
r=Path(__file__).resolve().parents[1];os.chdir(r);work=r/'work/play-gradle';work.mkdir(exist_ok=True)
version='8.13';archive=work/f'gradle-{version}-bin.zip';url=f'https://downloads.gradle.org/distributions/gradle-{version}-bin.zip'
expected=urllib.request.urlopen(url+'.sha256',timeout=30).read().decode().strip()
if not archive.exists():
 with urllib.request.urlopen(url,timeout=60)as source,archive.open('wb')as dest:shutil.copyfileobj(source,dest)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==expected,'Gradle checksum mismatch'
if not (work/f'gradle-{version}').exists():
 with zipfile.ZipFile(archive)as z:z.extractall(work)
cfg=json.loads((r/'work/play-tools/tools.json').read_text());sdk=work/'sdk';sdk.mkdir(exist_ok=True)
for source,target in [(Path(cfg['platform']).parent,sdk/'platforms/android-36'),(Path(cfg['buildTools']),sdk/'build-tools/36.0.0')]:
 if not target.exists():shutil.copytree(source,target)
generated=r/'android/build/play-gradle';generated.mkdir(parents=True,exist_ok=True);src=generated/'java/app/kinnect/live';src.mkdir(parents=True,exist_ok=True)
excluded={'Distribution.java','ApkUpdateActivity.java','ApkUpdateProvider.java','ApkUpdatePolicy.java','ApkUpdates.java'}
for p in (r/'android/app/src/main/java/app/kinnect/live').glob('*.java'):
 if p.name not in excluded:shutil.copy2(p,src/p.name)
for p in (r/'android/app/src/play/java/app/kinnect/live').glob('*.java'):shutil.copy2(p,src/p.name)
(src/'ApkUpdates.java').write_text('package app.kinnect.live; public final class ApkUpdates {public static void check(android.app.Activity a){try{a.startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW,android.net.Uri.parse("market://details?id="+a.getPackageName())).setPackage("com.android.vending"));}catch(Exception ignored){}}}')
ns='{http://schemas.android.com/apk/res/android}';E.register_namespace('android',ns[1:-1]);tree=E.parse(r/'android/app/src/main/AndroidManifest.xml');manifest=tree.getroot();manifest.attrib.pop('package',None);manifest.set(ns+'versionCode','103');manifest.set(ns+'versionName','1.2.1');manifest.find('uses-sdk').set(ns+'targetSdkVersion','36')
for permission in list(manifest.findall('uses-permission')):
 if permission.get(ns+'name','').split('.')[-1] in {'REQUEST_INSTALL_PACKAGES','REQUEST_IGNORE_BATTERY_OPTIMIZATIONS','READ_MEDIA_IMAGES','READ_MEDIA_VIDEO','READ_MEDIA_VISUAL_USER_SELECTED','READ_EXTERNAL_STORAGE','ACCESS_NOTIFICATION_POLICY','DISABLE_KEYGUARD','TURN_SCREEN_ON','RECEIVE_BOOT_COMPLETED','FOREGROUND_SERVICE_PHONE_CALL','FOREGROUND_SERVICE_MICROPHONE','FOREGROUND_SERVICE_CAMERA'}:manifest.remove(permission)
app=manifest.find('application');app.attrib.pop(ns+'debuggable',None)
for child in list(app):
 if child.get(ns+'name')in ['.ApkUpdateActivity','.ApkUpdateProvider']:app.remove(child)
 if child.get(ns+'name')=='.CallActionReceiver':
  child.set(ns+'exported','false')
  for intent in list(child.findall('intent-filter')):child.remove(intent)
tree.write(generated/'AndroidManifest.xml',encoding='utf8',xml_declaration=True)
assets=generated/'assets';assets.mkdir(exist_ok=True)
for name in ['welcome-profile.png','welcome-profile-1.png','welcome-profile-2.png','welcome-profile-3.png']:shutil.copy2(r/'public'/name,assets/name)
(r/'android/play-release/local.properties').write_text('sdk.dir='+sdk.as_posix()+'\n')
env=os.environ.copy();env['JAVA_HOME']=str(next((r/'work/android-tools/jdk').glob('jdk-*')));env['KINNECT_PLAY_PASS']=(r/'work/play-signing/store-password.txt').read_text();env['GRADLE_USER_HOME']=str(work/'cache')
subprocess.run(['python',str(r/'scripts/sync-android-languages.py')],check=True)
gradle=work/f'gradle-{version}/bin/gradle.bat';subprocess.run([str(gradle),'--no-daemon','-p',str(r/'android/play-release'),'bundleRelease'],env=env,check=True)
out=r/'dist/google-play';aab=out/'Kinnect-1.2.1-play.aab';shutil.copy2(r/'android/play-release/build/outputs/bundle/release/KinnectPlay-release.aab',aab)
jdk=Path(env['JAVA_HOME'])/'bin';apks=work/'universal.apks';subprocess.run([str(jdk/'java.exe'),'-jar',cfg['bundletool'],'build-apks','--bundle='+str(aab),'--output='+str(apks),'--overwrite','--mode=universal','--ks='+str(r/'work/play-signing/upload.jks'),'--ks-key-alias=kinnect-upload','--ks-pass=file:'+str(r/'work/play-signing/store-password.txt'),'--key-pass=file:'+str(r/'work/play-signing/store-password.txt')],check=True)
with zipfile.ZipFile(apks)as z:(out/'Kinnect-1.2.1-play-test.apk').write_bytes(z.read('universal.apk'))
for p in [aab,out/'Kinnect-1.2.1-play-test.apk']:p.with_suffix(p.suffix+'.sha256').write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n')
print('Billing-enabled Play AAB:',aab)
