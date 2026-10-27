package app.kinnect.live;
import java.nio.file.*;
import java.util.*;
public final class MediaTypeTest {
 private static void check(boolean ok,String message){if(!ok)throw new AssertionError(message);}
 public static void main(String[] args)throws Exception{
  byte[] actual=Files.readAllBytes(Paths.get("test/fixtures/short.mp4"));
  check("video/mp4".equals(MediaType.sniff(actual)),"Real MP4 fixture must be identified by content");
  byte[] quicktime=Arrays.copyOf(actual,64);quicktime[8]='q';quicktime[9]='t';quicktime[10]=' ';quicktime[11]=' ';
  check(MediaType.quickTime(quicktime),"QuickTime must be normalized, not merely renamed");
  byte[] heif=Arrays.copyOf(actual,64);heif[8]='h';heif[9]='e';heif[10]='i';heif[11]='c';
  check("image/heif".equals(MediaType.sniff(heif)),"HEIF shares ftyp but is not video");
  check("image/jpeg".equals(MediaType.sniff(new byte[]{(byte)255,(byte)216,(byte)255})),"JPEG signature");
  check("image/png".equals(MediaType.sniff(new byte[]{(byte)137,80,78,71,13,10,26,10})),"PNG signature");
  check(MediaType.sniff(new byte[]{1,2,3})==null,"Unknown bytes cannot be relabeled MP4");
  System.out.println("MediaType: real MP4, MOV, HEIF, images and invalid content passed.");
 }
}
