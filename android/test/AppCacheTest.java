package app.kinnect.live;
import java.io.*;import java.nio.file.*;import java.nio.file.attribute.*;import java.util.*;import javax.crypto.*;import javax.crypto.spec.*;
public final class AppCacheTest {
 static void check(boolean value){if(!value)throw new AssertionError();}
 public static void main(String[] args)throws Exception{
  File dir=Files.createTempDirectory("kinnect-cache-test-").toFile();final byte[] key=new byte[32];new java.security.SecureRandom().nextBytes(key);
  AppCache.Codec codec=new AppCache.Codec(){public byte[] encode(String label,byte[] data)throws Exception{Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES"));c.updateAAD(label.getBytes("UTF-8"));byte[] body=c.doFinal(data),iv=c.getIV(),out=new byte[12+body.length];System.arraycopy(iv,0,out,0,12);System.arraycopy(body,0,out,12,body.length);return out;}public byte[] decode(String label,byte[] data)throws Exception{Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,Arrays.copyOf(data,12)));c.updateAAD(label.getBytes("UTF-8"));return c.doFinal(data,12,data.length-12);}};
  AppCache cache=new AppCache(dir,codec,4096);byte[] privateMessage="Tin nhắn riêng tư".getBytes("UTF-8");cache.put("account-a","json:/api/messages",privateMessage);
  check(Arrays.equals(privateMessage,new AppCache(dir,codec,4096).get("account-a","json:/api/messages",AppCache.WEEK)));check(cache.get("account-b","json:/api/messages",AppCache.WEEK)==null);
  File encrypted=dir.listFiles()[0];check(!new String(Files.readAllBytes(encrypted.toPath()),"UTF-8").contains("Tin nhắn"));
  byte[] corrupted=Files.readAllBytes(encrypted.toPath());corrupted[corrupted.length-1]^=1;Files.write(encrypted.toPath(),corrupted);check(cache.get("account-a","json:/api/messages",AppCache.WEEK)==null);
  cache.put("account-a","json:/api/messages",privateMessage);Files.setLastModifiedTime(encrypted.toPath(),FileTime.fromMillis(System.currentTimeMillis()-AppCache.WEEK-1000));check(cache.get("account-a","json:/api/messages",AppCache.WEEK)==null);
  for(int i=0;i<20;i++)cache.put("account-a","json:"+i,new byte[100]);long bytes=0;for(File f:dir.listFiles())bytes+=f.length();check(bytes<=1024);
  cache.put("account-a","video:/clip",new byte[1500]);check(cache.video("account-a","/clip")!=null);check(cache.video("account-b","/clip")==null);
  cache.clear();check(dir.listFiles().length==0);dir.delete();
  long boundary=java.time.Instant.parse("2026-10-30T17:00:00Z").toEpochMilli();check(RegistrationBadge.today(boundary,boundary+1000));check(!RegistrationBadge.today(boundary-1,boundary+1000));check(!RegistrationBadge.today(boundary+2000,boundary+1000));
  System.out.println("PASS encrypted cache restart, account isolation, tamper rejection, expiry, budgets, logout and Vietnam-day badge");
 }
}
