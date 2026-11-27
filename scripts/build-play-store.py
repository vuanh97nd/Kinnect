"""Build the Play store variant with Google's Billing SDK and Android manifest merger."""
from pathlib import Path
import hashlib,json,re,urllib.request,zipfile,subprocess,os,shutil,xml.etree.ElementTree as E
r=Path(__file__).resolve().parents[1];os.chdir(r);subprocess.run(['python',str(r/'scripts/build-native-icon-family.py')],check=True);work=r/'work/play-gradle';work.mkdir(exist_ok=True)
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
gradle_cfg=(r/'android/play-release/build.gradle').read_text(encoding='utf8')
vc_m=re.search(r"versionCode\s+(\d+)",gradle_cfg)
vn_m=re.search(r"versionName\s+['\"]([^'\"]+)['\"]",gradle_cfg)
assert vc_m and vn_m,'Missing versionCode/versionName in android/play-release/build.gradle'
version_code,version_name=vc_m.group(1),vn_m.group(1)
bd_m=re.search(r'layout\.buildDirectory\s*=\s*file\("\$\{repo\}/([^"]+)"\)',gradle_cfg)
build_dir=r/(bd_m.group(1) if bd_m else 'android/build/play-fcm-b141')
generated=r/'android/build/play-gradle';generated.mkdir(parents=True,exist_ok=True)
ns='{http://schemas.android.com/apk/res/android}';E.register_namespace('android',ns[1:-1]);tree=E.parse(r/'android/app/src/main/AndroidManifest.xml');manifest=tree.getroot();manifest.attrib.pop('package',None);manifest.set(ns+'versionCode',version_code);manifest.set(ns+'versionName',version_name);manifest.find('uses-sdk').set(ns+'targetSdkVersion','36')
for permission in list(manifest.findall('uses-permission')):
 if permission.get(ns+'name','').split('.')[-1] in {'REQUEST_INSTALL_PACKAGES','REQUEST_IGNORE_BATTERY_OPTIMIZATIONS','READ_MEDIA_IMAGES','READ_MEDIA_VIDEO','READ_MEDIA_VISUAL_USER_SELECTED','READ_EXTERNAL_STORAGE','ACCESS_NOTIFICATION_POLICY','DISABLE_KEYGUARD','TURN_SCREEN_ON','RECEIVE_BOOT_COMPLETED','FOREGROUND_SERVICE','FOREGROUND_SERVICE_PHONE_CALL','FOREGROUND_SERVICE_MICROPHONE','FOREGROUND_SERVICE_CAMERA','FOREGROUND_SERVICE_MEDIA_PROJECTION','SYSTEM_ALERT_WINDOW','MANAGE_OWN_CALLS'}:manifest.remove(permission)
for q in list(manifest.findall('queries')):
 for intent in list(q.findall('intent')):q.remove(intent)
 for pkg in list(q.findall('package')):
  if pkg.get(ns+'name')=='app.kinnect.audit':q.remove(pkg)
app=manifest.find('application');app.attrib.pop(ns+'debuggable',None);app.attrib.pop(ns+'extractNativeLibs',None)
for child in list(app):
 if child.get(ns+'name')in ['.ApkUpdateActivity','.ApkUpdateProvider','.FarmGameDownloadActivity','.FarmGameProvider','.LiveGameService']:app.remove(child)
 if child.get(ns+'name')=='.CallActionReceiver':
  child.set(ns+'exported','false')
  for intent in list(child.findall('intent-filter')):child.remove(intent)
tree.write(generated/'AndroidManifest.xml',encoding='utf8',xml_declaration=True)
(r/'android/play-release/local.properties').write_text('sdk.dir='+sdk.as_posix()+'\n')
env=os.environ.copy();env['JAVA_HOME']=str(next((r/'work/android-tools/jdk').glob('jdk-*')));env['KINNECT_PLAY_PASS']=(r/'work/play-signing/store-password.txt').read_text(encoding='utf8').strip();env['GRADLE_USER_HOME']=str(work/'cache')
upload_ks=r/'work/play-signing/upload.jks'
if upload_ks.exists():env['KINNECT_PLAY_KEYSTORE']=str(upload_ks)
subprocess.run(['python',str(r/'scripts/sync-android-languages.py')],check=True)
gradle=work/f'gradle-{version}/bin/gradle.bat';subprocess.run([str(gradle),'--no-daemon','-p',str(r/'android/play-release'),'bundlePlayRelease'],env=env,check=True)
out=r/'dist/google-play';out.mkdir(parents=True,exist_ok=True);aab=out/f'Kinnect-{version_name}-play.aab'
built_aab=next((build_dir/'outputs/bundle/playRelease').glob('*.aab'))
shutil.copy2(built_aab,aab)
jdk=Path(env['JAVA_HOME'])/'bin';apks=work/'universal.apks';subprocess.run([str(jdk/'java.exe'),'-jar',cfg['bundletool'],'build-apks','--bundle='+str(aab),'--output='+str(apks),'--overwrite','--mode=universal','--ks='+str(r/'work/play-signing/upload.jks'),'--ks-key-alias=kinnect-upload','--ks-pass=file:'+str(r/'work/play-signing/store-password.txt'),'--key-pass=file:'+str(r/'work/play-signing/store-password.txt')],check=True)
with zipfile.ZipFile(apks)as z:(out/f'Kinnect-{version_name}-play-test.apk').write_bytes(z.read('universal.apk'))
for p in [aab,out/f'Kinnect-{version_name}-play-test.apk']:p.with_suffix(p.suffix+'.sha256').write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n')
print('Billing-enabled Play AAB:',aab)
