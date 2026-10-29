from pathlib import Path
import json,subprocess,xml.etree.ElementTree as E,zipfile,struct,hashlib
r=Path(__file__).resolve().parents[1];jdk=next((r/'work/android-tools/jdk').glob('jdk-*'))/'bin';cfg=json.loads((r/'work/play-tools/tools.json').read_text());out=r/'dist/google-play';aab=out/'Kinnect-1.2.1-play.aab';apk=out/'Kinnect-1.2.1-play-test.apk'
raw=subprocess.run([str(jdk/'java.exe'),'-jar',cfg['bundletool'],'dump','manifest','--bundle='+str(aab),'--module=base'],text=True,capture_output=True,check=True).stdout;root=E.fromstring(raw);ns='{http://schemas.android.com/apk/res/android}';assert root.find('uses-sdk').get(ns+'targetSdkVersion')=='36';assert root.get('package')=='app.kinnect.live';assert root.find('application').get(ns+'debuggable','false')=='false';assert root.find('application').get(ns+'usesCleartextTraffic')=='false'
permissions={p.get(ns+'name')for p in root.findall('uses-permission')};forbidden={'REQUEST_INSTALL_PACKAGES','READ_MEDIA_IMAGES','READ_MEDIA_VIDEO','READ_EXTERNAL_STORAGE','REQUEST_IGNORE_BATTERY_OPTIMIZATIONS','ACCESS_NOTIFICATION_POLICY'};assert not any(p.split('.')[-1] in forbidden for p in permissions)
components=[x.get(ns+'name','')for x in root.find('application')];assert not any('ApkUpdateActivity'in x or 'ApkUpdateProvider'in x for x in components)
assert 'com.android.vending.BILLING' in permissions
elf=[]
with zipfile.ZipFile(apk) as z:
 dex=b''.join(z.read(n)for n in z.namelist()if n.endswith('.dex'));assert b'ApkUpdateActivity'not in dex and b'ApkUpdateProvider'not in dex;assert b'market://details?id='in dex
 for n in z.namelist():
  if not n.endswith('.so')or not any(abi in n for abi in ['arm64-v8a','x86_64']):continue
  d=z.read(n);end='<' if d[5]==1 else '>';off=struct.unpack_from(end+'Q',d,32)[0];size,count=struct.unpack_from(end+'HH',d,54);align=[]
  for i in range(count):
   at=off+i*size
   if struct.unpack_from(end+'I',d,at)[0]==1:align.append(struct.unpack_from(end+'Q',d,at+48)[0])
  assert align and min(align)>=16384,n;elf.append({'library':n,'loadAlignments':align})
subprocess.run([str(Path(cfg['buildTools'])/'zipalign.exe'),'-c','-P','16','4',str(apk)],check=True)
report={'version':root.get(ns+'versionName'),'versionCode':int(root.get(ns+'versionCode')),'package':'app.kinnect.live','targetSdk':36,'minSdk':26,'debuggable':False,'externalApkInstallerIncluded':False,'forbiddenPermissionsAbsent':True,'elf64':elf,'aabSha256':hashlib.sha256(aab.read_bytes()).hexdigest(),'qaApkSha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'requiresPlayConsoleReview':True}
(out/'artifact-checks.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
