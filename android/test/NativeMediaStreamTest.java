package app.kinnect.live;
import java.io.*;import java.nio.file.*;import java.util.*;
import android.content.*;import android.net.Uri;
public class NativeMediaStreamTest {
 static final class OneShot extends ContentResolver {
  byte[] data;int opens,closes;boolean deny;
  OneShot(byte[] data){this.data=data;}
  public InputStream openInputStream(Uri uri)throws FileNotFoundException {
   if(deny)throw new SecurityException("read grant revoked");
   if(++opens>1)throw new FileNotFoundException("one-shot provider cannot reopen URI");
   return new ByteArrayInputStream(data){public void close()throws IOException{closes++;super.close();}};
  }
 }
 static void check(boolean c,String m){if(!c)throw new AssertionError(m);}
 public static void main(String[]args)throws Exception {
  byte[] mp4=Files.readAllBytes(Paths.get("test/fixtures/short.mp4"));
  OneShot provider=new OneShot(mp4);NativeMedia.Prepared result=NativeMedia.read(new Context(provider),Uri.parse("content://cloud/download-without-extension"),true);
  check(provider.opens==1,"MP4 URI must be opened once, without retriever or MIME gate");check(provider.closes==1,"Input must be closed");
  check(result.video()&&result.type.equals("video/mp4"),"Canonical MP4 type");check(Arrays.equals(mp4,result.bytes),"Keep complete file unchanged");
  check(result.dataUrl().equals("data:video/mp4;base64,"+java.util.Base64.getEncoder().encodeToString(mp4)),"Exact web-compatible API payload");
  OneShot image=new OneShot(new byte[]{(byte)255,(byte)216,(byte)255,0});NativeMedia.Prepared photo=NativeMedia.read(new Context(image),Uri.parse("content://cloud/wrong-mime"),false);
  check(photo.type.equals("image/jpeg")&&!photo.video(),"Identify JPEG bytes despite unusable MIME");
  OneShot empty=new OneShot(new byte[0]);boolean rejected=false;try{NativeMedia.read(new Context(empty),Uri.parse("content://cloud/empty"),true);}catch(IOException expected){rejected=true;}check(rejected&&empty.closes==1,"Reject empty file and close stream");
  OneShot denied=new OneShot(mp4);denied.deny=true;rejected=false;try{NativeMedia.read(new Context(denied),Uri.parse("content://cloud/denied"),true);}catch(SecurityException expected){rejected=true;}check(rejected,"Keep permission error distinct from format error");
  System.out.println("NativeMediaStream: actual MP4 with one-shot URI, unusable MIME, exact payload, JPEG, empty and denied URI passed (JVM provider stubs; not device remux).");
 }
}
