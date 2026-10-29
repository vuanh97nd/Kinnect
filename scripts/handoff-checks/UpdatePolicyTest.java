import java.util.*;
import app.kinnect.live.*;
public class UpdatePolicyTest {
 static void require(boolean ok){if(!ok)throw new AssertionError();}
 public static void main(String[] args){String good="https://github.com/vuanh97nd/Kinnect/releases/download/v1.0.3/Kinnect-1.0.3-native.apk";
 require(ApkUpdatePolicy.releaseUrl(good));require(ApkUpdatePolicy.downloadUrl("https://release-assets.githubusercontent.com/path?token=example"));
 for(String url:new String[]{good.replace("https:","http:"),good.replace("github.com/","github.com.evil.test/"),good.replace("/vuanh97nd/","/other/"),"file:///tmp/update.apk","https://user:password@github.com/vuanh97nd/Kinnect/releases/download/v1/a.apk"})require(!ApkUpdatePolicy.downloadUrl(url));
 require(ApkUpdatePolicy.digest("sha256:"+String.join("",Collections.nCopies(64,"a"))).length()==64);try{ApkUpdatePolicy.digest("");throw new AssertionError();}catch(IllegalArgumentException expected){}
 require(!ApkUpdatePolicy.validSize(0));require(!ApkUpdatePolicy.validSize(301L*1024*1024));require(ApkUpdatePolicy.validSize(59212909));require(ReleaseVersion.compare("v1.0.3","1.0.2")>0);System.out.println("PASS: approved release/download hosts, TLS-only redirects, invalid digest rejection, size limits and version ordering");}
}
