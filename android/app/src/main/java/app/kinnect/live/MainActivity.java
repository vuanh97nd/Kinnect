package app.kinnect.live;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.*;
import java.util.ArrayList;
import java.util.List;

/** Thin Android client for the self-hosted Kinnect Live web application. */
public class MainActivity extends Activity {
    private WebView web;
    private String trustedOrigin;
    private PermissionRequest pending;
    private LinearLayout root;
    private TextView status;

    @Override public void onCreate(Bundle state) { super.onCreate(state); showSetup(); }
    private void showSetup() {
        destroyWeb();
        root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setPadding(dp(24),dp(40),dp(24),dp(24));root.setBackgroundColor(Color.rgb(20,19,41));
        setContentView(root);
        ImageView mark=new ImageView(this);mark.setImageResource(getResources().getIdentifier("kinnect_icon","drawable",getPackageName()));LinearLayout.LayoutParams logoParams=new LinearLayout.LayoutParams(dp(88),dp(88));logoParams.bottomMargin=dp(20);root.addView(mark,logoParams);
        TextView tag=new TextView(this);tag.setText("KẾT NỐI · CHIA SẺ · LÀ CHÍNH MÌNH");tag.setTextSize(10);tag.setLetterSpacing(0.12f);tag.setTextColor(Color.rgb(114,229,199));root.addView(tag);
        TextView title=new TextView(this);title.setText("Kinnect Live");title.setTextSize(36);title.setTypeface(Typeface.DEFAULT,Typeface.BOLD);title.setPadding(0,dp(12),0,0);title.setTextColor(Color.WHITE);root.addView(title);
        TextView help=new TextView(this);help.setText("Kết nối đến máy chủ Node.js của bạn. Nhập địa chỉ HTTPS công khai, ví dụ địa chỉ Cloudflare Tunnel.\n\nBản thử nghiệm livestream cho nhóm nhỏ; chưa có đăng nhập hoặc kiểm duyệt. Chỉ dùng máy chủ bạn tin cậy.");help.setTextSize(15);help.setLineSpacing(dp(5),1);help.setTextColor(Color.rgb(191,181,214));help.setPadding(0,24,0,24);root.addView(help);
        EditText url=new EditText(this);url.setSingleLine(true);url.setTextColor(Color.WHITE);url.setHintTextColor(Color.GRAY);url.setHint("https://may-chu-cua-ban.example");url.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_URI);url.setText(getPreferences(0).getString("server",""));url.setTextSize(16);url.setPadding(dp(16),dp(12),dp(16),dp(12));url.setBackground(card(Color.rgb(34,29,54),14));root.addView(url);
        Button connect=new Button(this);connect.setText("Vào Kinnect Live  →");connect.setAllCaps(false);connect.setTextSize(16);connect.setTextColor(Color.rgb(29,18,51));connect.setBackground(card(Color.rgb(180,154,255),14));LinearLayout.LayoutParams buttonParams=new LinearLayout.LayoutParams(-1,dp(56));buttonParams.topMargin=dp(20);root.addView(connect,buttonParams);
        status=new TextView(this);status.setTextColor(Color.LTGRAY);root.addView(status);
        connect.setOnClickListener(v->{
            try {
                Uri uri=Uri.parse(url.getText().toString().trim());
                if(!"https".equalsIgnoreCase(uri.getScheme())||uri.getHost()==null||uri.getUserInfo()!=null||uri.getQuery()!=null||uri.getFragment()!=null||(!"".equals(uri.getPath())&&!"/".equals(uri.getPath())))throw new IllegalArgumentException();
                trustedOrigin=origin(uri);getPreferences(0).edit().putString("server",trustedOrigin).apply();openServer();
            } catch(Exception e){status.setText("Nhập địa chỉ HTTPS hợp lệ, không kèm đường dẫn hoặc mật khẩu.");}
        });
    }
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private GradientDrawable card(int color,int radius){GradientDrawable bg=new GradientDrawable();bg.setColor(color);bg.setCornerRadius(dp(radius));return bg;}
    private String origin(Uri uri){int port=uri.getPort();return "https://"+uri.getHost().toLowerCase(java.util.Locale.ROOT)+(port==-1||port==443?"":":"+port);}
    private boolean trusted(Uri uri){return "https".equalsIgnoreCase(uri.getScheme())&&trustedOrigin!=null&&trustedOrigin.equals(origin(uri));}
    private void openServer(){
        root.removeAllViews();Button settings=new Button(this);settings.setText("Đổi máy chủ / Ngắt kết nối");settings.setOnClickListener(v->showSetup());root.addView(settings);
        web=new WebView(this);root.addView(web,new LinearLayout.LayoutParams(-1,0,1));
        web.getSettings().setJavaScriptEnabled(true);web.getSettings().setDomStorageEnabled(true);web.getSettings().setMediaPlaybackRequiresUserGesture(false);web.getSettings().setAllowFileAccess(false);web.getSettings().setAllowContentAccess(false);web.getSettings().setMixedContentMode(android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView w,WebResourceRequest request){return !trusted(request.getUrl());}
            @Override public void onReceivedError(WebView w,WebResourceRequest request,android.webkit.WebResourceError error){if(request.isForMainFrame())Toast.makeText(MainActivity.this,"Không kết nối được máy chủ. Kiểm tra Node.js, mạng và địa chỉ HTTPS.",Toast.LENGTH_LONG).show();}
        });
        web.setWebChromeClient(new WebChromeClient(){
            @Override public void onPermissionRequest(PermissionRequest request){runOnUiThread(()->{
                if(!trusted(request.getOrigin())){request.deny();return;}
                if(pending!=null){request.deny();return;}
                pending=request;List<String> permissions=new ArrayList<>();
                for(String resource:request.getResources()){
                    if(PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource))permissions.add(Manifest.permission.CAMERA);
                    if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource))permissions.add(Manifest.permission.RECORD_AUDIO);
                }
                List<String> missing=new ArrayList<>();for(String p:permissions)if(checkSelfPermission(p)!=PackageManager.PERMISSION_GRANTED)missing.add(p);
                if(missing.isEmpty())grantMedia();else requestPermissions(missing.toArray(new String[0]),7);
            });}
            @Override public void onPermissionRequestCanceled(PermissionRequest request){if(pending==request)pending=null;}
        });
        web.loadUrl(trustedOrigin+"/");
    }
    private void grantMedia(){
        if(pending==null)return;
        List<String> allowed=new ArrayList<>();for(String resource:pending.getResources()){
            if(PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource)&&checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)allowed.add(resource);
            if(PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resource)&&checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)allowed.add(resource);
        }
        if(allowed.isEmpty())pending.deny();else pending.grant(allowed.toArray(new String[0]));pending=null;
    }
    @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] results){super.onRequestPermissionsResult(requestCode,permissions,results);if(requestCode==7)grantMedia();}
    private void destroyWeb(){if(pending!=null){pending.deny();pending=null;}if(web!=null){web.loadUrl("about:blank");web.stopLoading();web.destroy();web=null;}}
    @Override protected void onStop(){super.onStop();if(web!=null){destroyWeb();showSetup();Toast.makeText(this,"Đã ngắt livestream khi ứng dụng rời màn hình.",Toast.LENGTH_SHORT).show();}}
    @Override protected void onDestroy(){destroyWeb();super.onDestroy();}
    @Override public void onBackPressed(){if(web!=null)new AlertDialog.Builder(this).setMessage("Ngắt kết nối và rời livestream?").setPositiveButton("Rời phòng",(d,w)->showSetup()).setNegativeButton("Ở lại",null).show();else super.onBackPressed();}
}
