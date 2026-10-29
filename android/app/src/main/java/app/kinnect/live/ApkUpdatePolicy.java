package app.kinnect.live;

import java.net.URL;
import java.util.Locale;

/** Trust boundaries for the public Kinnect update channel. */
public final class ApkUpdatePolicy {
  public static boolean releaseUrl(String value) {
    try { URL u=new URL(value);return "https".equals(u.getProtocol())&&u.getPort()==-1&&u.getUserInfo()==null&&"github.com".equals(u.getHost())&&u.getPath().startsWith("/vuanh97nd/Kinnect/releases/download/")&&u.getPath().endsWith(".apk"); } catch(Exception e){return false;}
  }
  public static boolean downloadUrl(String value) {
    if(releaseUrl(value))return true;
    try { URL u=new URL(value);return "https".equals(u.getProtocol())&&u.getPort()==-1&&u.getUserInfo()==null&&"release-assets.githubusercontent.com".equals(u.getHost()); }catch(Exception e){return false;}
  }
  public static String digest(String value){String s=value==null?"":value.toLowerCase(Locale.ROOT);if(s.startsWith("sha256:"))s=s.substring(7);if(!s.matches("[a-f0-9]{64}"))throw new IllegalArgumentException("Bản cập nhật chưa có mã SHA-256 hợp lệ.");return s;}
  public static boolean validSize(long size){return size>0&&size<=300L*1024*1024;}
}
