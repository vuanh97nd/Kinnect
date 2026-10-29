"""Download pinned tools from Google/GitHub and verify each checksum."""
from pathlib import Path
import urllib.request,hashlib,zipfile,json
root=Path(__file__).resolve().parents[1];out=root/'work/play-tools';out.mkdir(parents=True,exist_ok=True)
def download(name,url,digest,algorithm='sha256'):
 p=out/name
 if not p.exists():
  with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Kinnect-Play-build'}),timeout=60) as source,p.open('wb') as dest:
   while data:=source.read(1024*1024):dest.write(data)
 if hashlib.new(algorithm,p.read_bytes()).hexdigest()!=digest:raise RuntimeError('Checksum mismatch: '+name)
 return p
for name,url,sha in [('platform36.zip','https://dl.google.com/android/repository/platform-36_r02.zip','2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576'),('build-tools36.zip','https://dl.google.com/android/repository/build-tools_r36_windows.zip','f16ccffd34de8790dede813a6c7d8e2c11a27b50')]:
 p=download(name,url,sha,'sha1');target=out/name.removesuffix('.zip');target.mkdir(exist_ok=True)
 with zipfile.ZipFile(p) as z:z.extractall(target)
version='9.5.0-16666295';url=f'https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/{version}/aapt2-{version}-windows.jar';sha=urllib.request.urlopen(url+'.sha1',timeout=30).read().decode().strip();p=download('aapt2.jar',url,sha,'sha1');target=out/'aapt2';target.mkdir(exist_ok=True)
with zipfile.ZipFile(p) as z:z.extractall(target)
download('bundletool.jar','https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar','a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29')
(out/'tools.json').write_text(json.dumps({'platform':str(next((out/'platform36').rglob('android.jar'))),'buildTools':str(next((out/'build-tools36').rglob('zipalign.exe')).parent),'aapt2':str(out/'aapt2/aapt2.exe'),'bundletool':str(out/'bundletool.jar')},indent=2))
print('Verified SDK 36, Build Tools 36, AAPT2 and bundletool ready')
