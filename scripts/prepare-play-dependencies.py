from pathlib import Path
import urllib.request,hashlib,json
r=Path(__file__).resolve().parents[1];out=r/'work/play-tools/dependencies';out.mkdir(parents=True,exist_ok=True)
items=[('com.squareup.okhttp3','okhttp','4.12.0'),('com.squareup.okio','okio-jvm','3.6.0'),('org.jetbrains.kotlin','kotlin-stdlib','1.9.10'),('org.jetbrains.kotlin','kotlin-stdlib-common','1.9.10'),('org.jetbrains.kotlin','kotlin-stdlib-jdk7','1.9.10'),('org.jetbrains.kotlin','kotlin-stdlib-jdk8','1.9.10'),('org.jetbrains','annotations','13.0')];records=[]
for group,artifact,version in items:
 name=artifact+'-'+version+'.jar';url='https://repo.maven.apache.org/maven2/'+group.replace('.','/')+'/'+artifact+'/'+version+'/'+name
 expected=urllib.request.urlopen(url+'.sha1',timeout=30).read().decode().strip();path=out/name
 if not path.exists():path.write_bytes(urllib.request.urlopen(url,timeout=60).read())
 data=path.read_bytes()
 if hashlib.sha1(data).hexdigest()!=expected:raise RuntimeError('Dependency checksum mismatch: '+name)
 records.append({'package':group+':'+artifact,'version':version,'file':str(path),'sha256':hashlib.sha256(data).hexdigest(),'source':url})
(out/'dependencies.json').write_text(json.dumps(records,indent=2)+'\n');print('Verified',len(records),'Play JVM dependencies; legacy vulnerable OkHttp/Okio excluded')
