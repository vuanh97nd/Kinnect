package app.kinnect.live;

import java.io.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

/** Bounded, atomic account-scoped cache. Metadata encryption is supplied by Android Keystore. */
final class AppCache {
  interface Codec { byte[] encode(String key,byte[] data)throws Exception; byte[] decode(String key,byte[] data)throws Exception; }
  private final File directory;private final Codec codec;private final long budget;
  private static final int MAX_PREFIX_CHARS=96;
  private final Set<String> trackedKeys=new HashSet<>();
  static final long WEEK=7L*86400000;
  AppCache(File directory,Codec codec,long budget){this.directory=directory;this.codec=codec;this.budget=budget;directory.mkdirs();}
  private String label(String scope,String key){return scope+"\n"+key;}
  private static String sha256Hex(String value)throws Exception{byte[] digest=MessageDigest.getInstance("SHA-256").digest(value.getBytes("UTF-8"));StringBuilder name=new StringBuilder(64);for(byte b:digest)name.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return name.toString();}
  private static String scopeTag(String scope)throws Exception{return sha256Hex(scope==null?"":scope).substring(0,16);}
  private static String encodeKey(String key)throws Exception{
    byte[] utf8=(key==null?"":key).getBytes("UTF-8");
    StringBuilder out=new StringBuilder(Math.min(MAX_PREFIX_CHARS,utf8.length*2));
    for(byte raw:utf8){
      int b=raw&255;
      if((b>='0'&&b<='9')||(b>='A'&&b<='Z')||(b>='a'&&b<='z'))out.append((char)b);
      else out.append(String.format(java.util.Locale.ROOT,"_%02x",b));
    }
    return out.toString();
  }
  private static String truncatePrefix(String encoded){return encoded.length()<=MAX_PREFIX_CHARS?encoded:encoded.substring(0,MAX_PREFIX_CHARS);}
  private static boolean isCacheFile(String name){return name!=null&&name.matches("([0-9a-f]{16}-[A-Za-z0-9_]*-)?[0-9a-f]{64}\\.(bin|mp4)");}
  private File file(String scope,String key)throws Exception{String full=sha256Hex(label(scope,key));String prefix=scopeTag(scope)+"-"+truncatePrefix(encodeKey(key))+"-";return new File(directory,prefix+full+(key.startsWith("video:")?".mp4":".bin"));}
  synchronized File video(String scope,String key){try{File f=file(scope,"video:"+key);return valid(f,WEEK)?f:null;}catch(Exception e){return null;}}
  private boolean valid(File f,long age){return f.isFile()&&f.length()>0&&f.length()<=40L*1024*1024&&System.currentTimeMillis()-f.lastModified()<=age;}
  synchronized byte[] get(String scope,String key,long age){try{File f=file(scope,key);if(!valid(f,age))return null;trackedKeys.add(key);byte[] bytes=Files.readAllBytes(f.toPath());return key.startsWith("video:")?bytes:codec.decode(label(scope,key),bytes);}catch(Exception e){return null;}}
  synchronized void put(String scope,String key,byte[] data){
    if(data==null||data.length==0||data.length>(key.startsWith("video:")?32*1024*1024:3*1024*1024))return;
    File temp=null;try{byte[] stored=key.startsWith("video:")?data:codec.encode(label(scope,key),data);File destination=file(scope,key);temp=File.createTempFile("write-",".tmp",directory);try(FileOutputStream out=new FileOutputStream(temp)){out.write(stored);out.getFD().sync();}Files.move(temp.toPath(),destination.toPath(),StandardCopyOption.REPLACE_EXISTING);trackedKeys.add(key);trim();}catch(Exception ignored){}finally{if(temp!=null)temp.delete();}
  }
  synchronized void remove(String scope,String key){try{File f=file(scope,key);if(f.exists())f.delete();}catch(Exception ignored){}trackedKeys.remove(key);}
  private static boolean matchesKeyPrefix(String key,String keyPrefix){
    if(!key.startsWith(keyPrefix))return false;
    if(key.length()==keyPrefix.length())return true;
    char last=keyPrefix.charAt(keyPrefix.length()-1);
    if(last=='/'||last=='?'||last==':')return true;
    char next=key.charAt(keyPrefix.length());
    return next=='/'||next=='?';
  }
  synchronized void removeByPrefix(String scope,String keyPrefix){
    if(keyPrefix==null||keyPrefix.isEmpty())return;
    remove(scope,keyPrefix);
    List<String> matched=new ArrayList<>();
    for(String k:trackedKeys)if(matchesKeyPrefix(k,keyPrefix))matched.add(k);
    for(String k:matched)remove(scope,k);
    try{
      String encodedPrefix=encodeKey(keyPrefix);
      final String tag=scopeTag(scope)+"-";
      if(encodedPrefix.length()<=MAX_PREFIX_CHARS){
        final String filePrefix=tag+encodedPrefix;
        char last=keyPrefix.charAt(keyPrefix.length()-1);
        final boolean openBoundary=(last=='/'||last=='?'||last==':');
        File[] files=directory.listFiles((d,name)->{
          if(!isCacheFile(name)||!name.startsWith(filePrefix))return false;
          if(openBoundary)return true;
          String rest=name.substring(filePrefix.length());
          return rest.startsWith("-")||rest.startsWith("_2f")||rest.startsWith("_3f");
        });
        if(files!=null)for(File f:files)f.delete();
      }else{
        final String truncatedFilePrefix=tag+truncatePrefix(encodedPrefix)+"-";
        File[] files=directory.listFiles((d,name)->isCacheFile(name)&&name.startsWith(truncatedFilePrefix));
        if(files!=null)for(File f:files)f.delete();
      }
    }catch(Exception ignored){}
  }
  private void trim(){File[] files=directory.listFiles((d,name)->isCacheFile(name));if(files==null)return;Arrays.sort(files,Comparator.comparingLong(File::lastModified));long media=0,metadata=0;for(File f:files)if(f.getName().endsWith(".mp4"))media+=f.length();else metadata+=f.length();for(File f:files){boolean video=f.getName().endsWith(".mp4");if(video?media<=budget*3/4:metadata<=budget/4)continue;long size=f.length();if(f.delete()){if(video)media-=size;else metadata-=size;}}}
  synchronized void clear(){trackedKeys.clear();File[] files=directory.listFiles((d,name)->isCacheFile(name)||name.startsWith("write-")&&name.endsWith(".tmp"));if(files!=null)for(File f:files)f.delete();}
}
