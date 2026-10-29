package app.kinnect.live;

import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.net.*;
import java.security.MessageDigest;
import java.util.*;

/** User-initiated download, verification, and Android installer; never a browser. */
public final class ApkUpdateActivity extends Activity {
 private static final int SOURCES=831,INSTALL=832;
 private final Handler main=new Handler(Looper.getMainLooper());
 private volatile boolean cancelled;
 private ProgressBar bar; private TextView status; private File ready;
 public static void open(Activity from,String version,String url,String digest,long size){
  from.startActivity(new Intent(from,ApkUpdateActivity.class).putExtra("version",version).putExtra("url",url).putExtra("digest",digest).putExtra("size",size));
 }
 private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
 @Override public void onCreate(Bundle state){super.onCreate(state);setTitle(I18n.t("Cập nhật Kinnect"));
  LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setPadding(dp(24),dp(40),dp(24),dp(24));root.setGravity(Gravity.CENTER);root.setBackgroundColor(0xfff6f5fa);
  ImageView logo=new ImageView(this);logo.setImageResource(getResources().getIdentifier("kinnect_logo","drawable",getPackageName()));root.addView(logo,new LinearLayout.LayoutParams(dp(72),dp(72)));
  TextView title=new TextView(this);title.setText(I18n.t("Cập nhật Kinnect ")+getIntent().getStringExtra("version"));title.setTextSize(22);title.setTextColor(0xff271b3d);title.setGravity(Gravity.CENTER);title.setPadding(0,dp(20),0,dp(20));root.addView(title);
  status=new TextView(this);status.setGravity(Gravity.CENTER);status.setTextColor(0xff625674);status.setText(I18n.t("Đang chuẩn bị tải…"));root.addView(status);
  bar=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);bar.setMax(100);LinearLayout.LayoutParams row=new LinearLayout.LayoutParams(-1,dp(24));row.topMargin=dp(20);root.addView(bar,row);
  Button cancel=new Button(this);cancel.setText(I18n.t("Huỷ cập nhật"));cancel.setOnClickListener(v->finish());root.addView(cancel);setContentView(root);
  new Thread(this::download,"kinnect-apk-download").start();
 }
 private HttpURLConnection connect(String url)throws Exception{
  for(int redirects=0;redirects<6;redirects++){
   if(!ApkUpdatePolicy.downloadUrl(url))throw new IOException(I18n.t("Địa chỉ tải APK không hợp lệ."));
   HttpURLConnection c=(HttpURLConnection)new URL(url).openConnection();c.setInstanceFollowRedirects(false);c.setConnectTimeout(15000);c.setReadTimeout(30000);c.setRequestProperty("User-Agent","Kinnect-Android-Updater");int code=c.getResponseCode();
   if(code==200)return c;
   if(code==301||code==302||code==303||code==307||code==308){String target=c.getHeaderField("Location");c.disconnect();if(target==null)throw new IOException(I18n.t("Thiếu địa chỉ tải."));url=new URL(new URL(url),target).toExternalForm();continue;}
   c.disconnect();throw new IOException(I18n.t("Máy chủ tải trả lỗi ")+code+".");
  }throw new IOException(I18n.t("Quá nhiều chuyển hướng tải APK."));
 }
 private void download(){File part=new File(getCacheDir(),"kinnect-update.part");HttpURLConnection connection=null;
  try{
   Intent request=getIntent();String url=request.getStringExtra("url"),expected=ApkUpdatePolicy.digest(request.getStringExtra("digest"));long expectedSize=request.getLongExtra("size",0);
   if(!ApkUpdatePolicy.releaseUrl(url)||!ApkUpdatePolicy.validSize(expectedSize))throw new IOException(I18n.t("Thông tin bản cập nhật không hợp lệ."));
   if(getCacheDir().getUsableSpace()<expectedSize*2+10*1024*1024)throw new IOException(I18n.t("Chưa đủ bộ nhớ trống để cập nhật."));
   connection=connect(url);long advertised=connection.getContentLengthLong();if(advertised>0&&advertised!=expectedSize)throw new IOException(I18n.t("Dung lượng tải không khớp bản phát hành."));
   MessageDigest sha=MessageDigest.getInstance("SHA-256");long total=0;int previous=-1;
   try(InputStream in=connection.getInputStream();OutputStream out=new FileOutputStream(part)){
    byte[] buffer=new byte[65536];int count;while((count=in.read(buffer))!=-1){if(cancelled)throw new InterruptedIOException();total+=count;if(total>expectedSize)throw new IOException(I18n.t("APK vượt dung lượng đã xác minh."));out.write(buffer,0,count);sha.update(buffer,0,count);int percent=(int)(total*100/expectedSize);if(percent!=previous){previous=percent;main.post(()->{if(!cancelled){bar.setProgress(percent);status.setText(I18n.t("Đang tải APK: ")+percent+"%");}});}}
   }
   if(total!=expectedSize)throw new IOException(I18n.t("Tệp tải chưa hoàn tất. Vui lòng thử lại."));StringBuilder actual=new StringBuilder();for(byte value:sha.digest())actual.append(String.format(Locale.ROOT,"%02x",value&255));if(!expected.equals(actual.toString()))throw new IOException(I18n.t("Mã SHA-256 không khớp. Đã chặn cài đặt."));
   PackageManager pm=getPackageManager();PackageInfo candidate=pm.getPackageArchiveInfo(part.getAbsolutePath(),PackageManager.GET_SIGNATURES),installed=pm.getPackageInfo(getPackageName(),PackageManager.GET_SIGNATURES);
   if(candidate==null||!getPackageName().equals(candidate.packageName)||candidate.versionCode<=installed.versionCode||ReleaseVersion.compare(candidate.versionName,installed.versionName)<=0||ReleaseVersion.compare(candidate.versionName,getIntent().getStringExtra("version"))!=0)throw new IOException(I18n.t("APK không đúng ứng dụng hoặc không phải bản mới hơn."));
   if(candidate.signatures==null||installed.signatures==null||!new HashSet<android.content.pm.Signature>(Arrays.asList(candidate.signatures)).equals(new HashSet<android.content.pm.Signature>(Arrays.asList(installed.signatures))))throw new IOException(I18n.t("Chữ ký APK không khớp bản Kinnect đang cài."));
   if(cancelled)throw new InterruptedIOException();ready=ApkUpdateProvider.file(this);if(ready.exists()&&!ready.delete())throw new IOException(I18n.t("Không thể thay tệp cập nhật cũ."));if(!part.renameTo(ready))throw new IOException(I18n.t("Không thể lưu APK."));main.post(()->{if(!cancelled)install();});
  }catch(Exception failure){part.delete();main.post(()->{if(!cancelled){status.setText(I18n.t("Chưa thể cập nhật"));new Sheet(this).setTitle(I18n.t("Cập nhật chưa hoàn tất")).setMessage(failure.getMessage()==null?I18n.t("Vui lòng kiểm tra mạng rồi thử lại."):failure.getMessage()).setPositiveButton(I18n.t("Đóng"),(d,w)->finish()).show();}});
  }finally{if(connection!=null)connection.disconnect();}
 }
 private void install(){
  if(ready==null||!ready.isFile()){finish();return;}status.setText(I18n.t("Đã tải và xác minh APK. Đang mở trình cài đặt Android…"));
  if(!getPackageManager().canRequestPackageInstalls()){
   new Sheet(this).setTitle(I18n.t("Cho phép Kinnect cập nhật")).setMessage(I18n.t("Android cần bạn bật ‘Cho phép từ nguồn này’ cho Kinnect. Sau đó quay lại để tiếp tục cài bản cập nhật.")).setPositiveButton(I18n.t("Mở cài đặt"),(d,w)->{try{startActivityForResult(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+getPackageName())),SOURCES);}catch(Exception e){status.setText(I18n.t("Không mở được cài đặt cấp quyền. Vui lòng thử lại."));}}).setNegativeButton(I18n.t("Để sau"),(d,w)->finish()).show();return;
  }
  try{Uri uri=Uri.parse("content://"+getPackageName()+".updates/update.apk");Intent installer=new Intent(Intent.ACTION_INSTALL_PACKAGE).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION).putExtra(Intent.EXTRA_RETURN_RESULT,true);startActivityForResult(installer,INSTALL);}catch(Exception e){new Sheet(this).setMessage(I18n.t("Không mở được trình cài đặt Android. APK đã được tải và xác minh.")).setPositiveButton(I18n.t("Đóng"),(d,w)->finish()).show();}
 }
 @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==SOURCES){if(getPackageManager().canRequestPackageInstalls())install();else{status.setText(I18n.t("Chưa có quyền cài cập nhật. Bạn có thể thử lại từ Cài đặt Kinnect."));}}else if(request==INSTALL){Toast.makeText(this,result==RESULT_OK?I18n.t("Đã cập nhật Kinnect"):I18n.t("Bạn chưa cài bản cập nhật."),Toast.LENGTH_LONG).show();finish();}}
 @Override protected void onDestroy(){cancelled=true;main.removeCallbacksAndMessages(null);super.onDestroy();}
}
