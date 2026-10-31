from pathlib import Path
import subprocess, shutil, zipfile, re, os
r=Path(__file__).resolve().parents[2]; w=r/'work/layout-update-104'; w.mkdir(exist_ok=True)
tools=r/'work/android-tools'; java=next((tools/'jdk').glob('jdk-*'))/'bin/java.exe'; jar=Path(os.environ['KINNECT_APKTOOL_JAR'])
def run(*args):subprocess.run([str(a) for a in args],check=True)
run(java,'-jar',jar,'d','-f','-o',w/'base',r/'dist/Kinnect-1.0.3-native.apk')
run(java,'-jar',jar,'d','-f','--no-res','-o',w/'updated',r/'dist/Kinnect-1.0.4-native.apk')
old=next((w/'base').rglob('ApkUpdates.smali')).parent; new=next((w/'updated').rglob('ApkUpdates.smali')).parent
for prefix in ['MainActivity']:
 for p in old.glob(prefix+'*.smali'):p.unlink()
 for p in new.glob(prefix+'*.smali'):shutil.copy2(p,old/p.name)
p=w/'base/apktool.yml';s=p.read_text(encoding='utf8');s=re.sub(r'versionCode:.*','versionCode: 69',s);s=re.sub(r'versionName:.*','versionName: 1.0.4',s);p.write_text(s,encoding='utf8')
run(java,'-jar',jar,'b',w/'base','-o',w/'unsigned.apk')
with zipfile.ZipFile(w/'unsigned.apk') as rebuilt,zipfile.ZipFile(r/'dist/Kinnect-1.0.3-native.apk') as original,zipfile.ZipFile(w/'preserved-icon.apk','w') as outzip:
 for info in rebuilt.infolist():outzip.writestr(info,original.read(info.filename) if info.filename=='res/drawable/kinnect_icon.png' else rebuilt.read(info.filename))
bt=tools/'build-tools/android-15';run(bt/'zipalign.exe','-P','16','-f','4',w/'preserved-icon.apk',w/'aligned.apk');out=r/'dist/Kinnect-1.0.4-native.apk';run(java,'-jar',bt/'lib/apksigner.jar','sign','--ks',r/'android/debug.keystore','--ks-pass','pass:android','--key-pass','pass:android','--out',out,w/'aligned.apk');run(java,'-jar',bt/'lib/apksigner.jar','verify','--print-certs',out)
import hashlib
out.with_suffix('.apk.sha256').write_text(hashlib.sha256(out.read_bytes()).hexdigest()+'  '+out.name+'\n')
print('Built update on the exact 1.0.3 package baseline')
