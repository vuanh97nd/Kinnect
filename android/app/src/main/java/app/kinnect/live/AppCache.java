package app.kinnect.live;

import java.io.*;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;

/** Bounded, atomic account-scoped cache. Metadata encryption is supplied by Android Keystore. */
final class AppCache {
  interface Codec { byte[] encode(String key,byte[] data)throws Exception; byte[] decode(String key,byte[] data)throws Exception; }
  private final File directory;private final Codec codec;private final long budget;
  static final long WEEK=7L*86400000;
  AppCache(File directory,Codec codec,long budget){this.directory=directory;this.codec=codec;this.budget=budget;directory.mkdirs();}
  private String label(String scope,String key){return scope+"\n"+key;}
  private File file(String scope,String key)throws Exception{byte[] digest=MessageDigest.getInstance("SHA-256").digest(label(scope,key).getBytes("UTF-8"));StringBuilder name=new StringBuilder();for(byte b:digest)name.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return new File(directory,name+(key.startsWith("video:")?".mp4":".bin"));}
  synchronized File video(String scope,String key){try{File f=file(scope,"video:"+key);return valid(f,WEEK)?f:null;}catch(Exception e){return null;}}
  private boolean valid(File f,long age){return f.isFile()&&f.length()>0&&f.length()<=40L*1024*1024&&System.currentTimeMillis()-f.lastModified()<=age;}
  synchronized byte[] get(String scope,String key,long age){try{File f=file(scope,key);if(!valid(f,age))return null;byte[] bytes=Files.readAllBytes(f.toPath());return key.startsWith("video:")?bytes:codec.decode(label(scope,key),bytes);}catch(Exception e){return null;}}
  synchronized void put(String scope,String key,byte[] data){
    if(data==null||data.length==0||data.length>(key.startsWith("video:")?32*1024*1024:3*1024*1024))return;
    File temp=null;try{byte[] stored=key.startsWith("video:")?data:codec.encode(label(scope,key),data);File destination=file(scope,key);temp=File.createTempFile("write-",".tmp",directory);try(FileOutputStream out=new FileOutputStream(temp)){out.write(stored);out.getFD().sync();}Files.move(temp.toPath(),destination.toPath(),StandardCopyOption.REPLACE_EXISTING);trim();}catch(Exception ignored){}finally{if(temp!=null)temp.delete();}
  }
  private void trim(){File[] files=directory.listFiles((d,name)->name.matches("[0-9a-f]{64}\\.(bin|mp4)"));if(files==null)return;Arrays.sort(files,Comparator.comparingLong(File::lastModified));long media=0,metadata=0;for(File f:files)if(f.getName().endsWith(".mp4"))media+=f.length();else metadata+=f.length();for(File f:files){boolean video=f.getName().endsWith(".mp4");if(video?media<=budget*3/4:metadata<=budget/4)continue;long size=f.length();if(f.delete()){if(video)media-=size;else metadata-=size;}}}
  synchronized void clear(){File[] files=directory.listFiles((d,name)->name.matches("[0-9a-f]{64}\\.(bin|mp4)")||name.startsWith("write-")&&name.endsWith(".tmp"));if(files!=null)for(File f:files)f.delete();}
}
