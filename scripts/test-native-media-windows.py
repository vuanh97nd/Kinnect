"""Run the actual APK media classes with JVM document-provider stubs.
This checks MP4 byte handling and API payloads, not Android codec/remux behavior.
"""
from pathlib import Path
import subprocess,sys,os
root=Path(__file__).resolve().parent.parent
os.chdir(root)
subprocess.run([sys.executable,"scripts/build-apk-windows.py"],check=True)
tools=root/"work/android-tools"
jdk=next((tools/"jdk").glob("jdk-*"))/"bin"
jar=tools/"platform/android-35-ext15/android.jar"
out=root/"android/build/media-tests"
out.mkdir(parents=True,exist_ok=True)
cp=str(root/"android/build/classes")+";"+str(jar)
sources=list((root/"android/test/provider-stubs").rglob("*.java"))+[root/"android/test/NativeMediaStreamTest.java",root/"android/test/MediaTypeTest.java"]
subprocess.run([str(jdk/"javac.exe"),"-encoding","UTF-8","-cp",cp,"-d",str(out),*map(str,sources)],check=True)
for test in ["MediaTypeTest","NativeMediaStreamTest"]:
 subprocess.run([str(jdk/"java.exe"),"-cp",str(out)+";"+cp,"app.kinnect.live."+test],check=True)
