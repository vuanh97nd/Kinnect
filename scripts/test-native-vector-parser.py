"""Exercise exported vector paths with the pinned AndroidX parser on the host JVM.
Path drawing methods are no-ops; AndroidX's actual parser and argument indexing run.
This checks parsing, not visual rendering or an Activity/device startup.
"""
from pathlib import Path
import argparse, hashlib, re, subprocess, urllib.request, xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parent.parent
PIN = '5c86afb33905d66b89a29ce66362859bc48651e5'
HASH = 'fd50db445c4cb4a2e1d1f2f672df428fd3d57af822d1fea717277c431a5a787f'
URL = 'https://raw.githubusercontent.com/androidx/androidx/'+PIN+'/core/core/src/main/java/androidx/core/graphics/PathParser.java'
parser = argparse.ArgumentParser()
parser.add_argument('--java', default='java')
parser.add_argument('--javac', default='javac')
parser.add_argument('--baseline-ref')
parser.add_argument('--expect-invalid', action='store_true')
args = parser.parse_args()
work = ROOT/'android/build/vector-parser-tests'
work.mkdir(parents=True, exist_ok=True)
cache = work/'PathParser.original.java'
if not cache.exists(): cache.write_bytes(urllib.request.urlopen(URL, timeout=30).read())
raw = cache.read_bytes()
assert hashlib.sha256(raw).hexdigest() == HASH, 'AndroidX parser checksum mismatch'
source = raw.decode('utf-8')
source = re.sub(r'^import (?:static )?(?:androidx.annotation|org.jspecify.annotations).*;\s*$', '', source, flags=re.M)
source = re.sub(r'@(?:NonNull|Nullable)\b', '', source)
source = source.replace('@RestrictTo(LIBRARY_GROUP_PREFIX)', '')
(work/'PathParser.java').write_text(source, encoding='utf-8')
methods = ['moveTo','rMoveTo','lineTo','rLineTo','quadTo','rQuadTo','cubicTo','rCubicTo']
(work/'Path.java').write_text('package android.graphics; public class Path { public void close() {} '+''.join('public void '+name+'(float... args) {}' for name in methods)+' }', encoding='utf-8')
(work/'Log.java').write_text('package android.util; public class Log { public static int w(String tag,String message) { return 0; } }', encoding='utf-8')
(work/'VectorProbe.java').write_text('''import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import androidx.core.graphics.PathParser;
public class VectorProbe {
 public static void main(String[] args) throws Exception {
  int count=0, failures=0;
  for(String line:Files.readAllLines(Paths.get(args[0]),StandardCharsets.UTF_8)) {
   String[] entry=line.split("\\t",2); count++;
   try { PathParser.createPathFromPathData(entry[1]); }
   catch(RuntimeException error) { failures++; if(failures<=5)System.out.println(entry[0]+": "+error.getClass().getSimpleName()+" "+error.getMessage()); }
  }
  System.out.println("paths="+count+" failures="+failures);
  if(args.length>1 && args[1].equals("expect-invalid")) { if(failures==0)throw new AssertionError("Baseline unexpectedly passed"); }
  else if(failures!=0)throw new AssertionError("Invalid Android vector paths: "+failures);
 }
}''', encoding='utf-8')
records=[]
ns='{http://schemas.android.com/apk/res/android}'
for icon in sorted((ROOT/'android/app/src/main/res/drawable').glob('*.xml')):
 raw = subprocess.check_output(['git','show',args.baseline_ref+':'+icon.relative_to(ROOT).as_posix()],cwd=ROOT) if args.baseline_ref else icon.read_bytes()
 for node in ET.fromstring(raw).iter('path'): records.append(icon.name+'\t'+node.get(ns+'pathData').replace('\n',' '))
(work/'paths.txt').write_text('\n'.join(records), encoding='utf-8')
classes=work/'classes'
classes.mkdir(exist_ok=True)
subprocess.run([args.javac,'-encoding','UTF-8','-d',str(classes),*[str(work/name) for name in ['Path.java','Log.java','PathParser.java','VectorProbe.java']]],check=True)
command=[args.java,'-cp',str(classes),'VectorProbe',str(work/'paths.txt')]
if args.expect_invalid: command.append('expect-invalid')
subprocess.run(command, check=True)
