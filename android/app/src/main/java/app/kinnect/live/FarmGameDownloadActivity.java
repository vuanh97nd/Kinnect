package app.kinnect.live;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InterruptedIOException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Arrays;
import java.util.HashSet;

/** Downloads, verifies and installs the standalone farm game module. */
public final class FarmGameDownloadActivity extends Activity {
  private static final int SOURCES = 841, INSTALL = 842;
  private static final String GAME_PACKAGE = "app.kinnect.farm";
  private final Handler main = new Handler(Looper.getMainLooper());
  private volatile boolean cancelled;
  private ProgressBar bar;
  private TextView status;
  private File ready;

  public static void open(Activity from, String url) {
    from.startActivity(new Intent(from, FarmGameDownloadActivity.class).putExtra("url", url));
  }

  private int dp(int value) {
    return Math.round(value * getResources().getDisplayMetrics().density);
  }

  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    setTitle(I18n.t("Tải module Nông trại"));
    LinearLayout root = new LinearLayout(this);
    root.setOrientation(LinearLayout.VERTICAL);
    root.setPadding(dp(24), dp(36), dp(24), dp(24));
    root.setGravity(Gravity.CENTER);
    root.setBackgroundColor(0xfff6f5fa);
    ImageView logo = new ImageView(this);
    logo.setImageResource(getResources().getIdentifier("kinnect_logo", "drawable", getPackageName()));
    root.addView(logo, new LinearLayout.LayoutParams(dp(72), dp(72)));
    TextView title = new KinnectText(this);
    title.setText(I18n.t("Module Nông trại 3D"));
    title.setTextSize(22);
    title.setTextColor(0xff271b3d);
    title.setGravity(Gravity.CENTER);
    title.setPadding(0, dp(18), 0, dp(16));
    root.addView(title);
    status = new KinnectText(this);
    status.setGravity(Gravity.CENTER);
    status.setTextColor(0xff625674);
    status.setText(I18n.t("Đang chuẩn bị tải module…"));
    root.addView(status);
    bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
    bar.setMax(100);
    LinearLayout.LayoutParams barParams = new LinearLayout.LayoutParams(-1, dp(24));
    barParams.topMargin = dp(20);
    root.addView(bar, barParams);
    Button cancel = new KinnectButton(this);
    cancel.setText(I18n.t("Huỷ tải module"));
    cancel.setOnClickListener(v -> finish());
    root.addView(cancel);
    setContentView(root);
    new Thread(this::download, "farm-game-download").start();
  }

  private boolean validUrl(String value) {
    try {
      URL url = new URL(value);
      URL origin = new URL(NativeApi.shared.origin());
      return "https".equals(url.getProtocol()) && url.getPort() == -1 && url.getUserInfo() == null
        && url.getHost().equalsIgnoreCase(origin.getHost())
        && "/download/farm-game".equals(url.getPath()) && url.getQuery() == null;
    } catch (Exception invalid) {
      return false;
    }
  }

  private HttpURLConnection connect(String value) throws Exception {
    if (!validUrl(value)) throw new IOException(I18n.t("Địa chỉ tải module không hợp lệ."));
    HttpURLConnection connection = (HttpURLConnection) new URL(value).openConnection();
    connection.setInstanceFollowRedirects(false);
    connection.setConnectTimeout(15000);
    connection.setReadTimeout(30000);
    connection.setRequestProperty("User-Agent", "Kinnect-Android-FarmModule");
    int code = connection.getResponseCode();
    if (code != 200) {
      connection.disconnect();
      throw new IOException(I18n.t("Máy chủ tải trả lỗi ") + code + ".");
    }
    return connection;
  }

  private void download() {
    File part = new File(getCacheDir(), "farm-game.part");
    HttpURLConnection connection = null;
    try {
      String url = getIntent().getStringExtra("url");
      connection = connect(url);
      long expectedSize = connection.getContentLengthLong();
      if (expectedSize > 300L * 1024 * 1024) throw new IOException(I18n.t("Module vượt dung lượng cho phép."));
      if (expectedSize > 0 && getCacheDir().getUsableSpace() < expectedSize * 2 + 10L * 1024 * 1024) {
        throw new IOException(I18n.t("Chưa đủ bộ nhớ trống để tải module."));
      }
      long total = 0;
      int previous = -1;
      try (InputStream in = connection.getInputStream(); FileOutputStream out = new FileOutputStream(part)) {
        byte[] buffer = new byte[65536];
        int count;
        while ((count = in.read(buffer)) != -1) {
          if (cancelled) throw new InterruptedIOException();
          total += count;
          if (total > 300L * 1024 * 1024) throw new IOException(I18n.t("Module vượt dung lượng cho phép."));
          out.write(buffer, 0, count);
          if (expectedSize > 0) {
            int percent = (int) (total * 100 / expectedSize);
            if (percent != previous) {
              previous = percent;
              main.post(() -> {
                if (!cancelled) {
                  bar.setProgress(percent);
                  status.setText(I18n.t("Đang tải module: ") + percent + "%");
                }
              });
            }
          }
        }
      }
      if (expectedSize > 0 && total != expectedSize) throw new IOException(I18n.t("Tệp tải chưa hoàn tất. Vui lòng thử lại."));
      PackageManager pm = getPackageManager();
      PackageInfo candidate = pm.getPackageArchiveInfo(part.getAbsolutePath(), PackageManager.GET_SIGNATURES);
      PackageInfo hub = pm.getPackageInfo(getPackageName(), PackageManager.GET_SIGNATURES);
      if (candidate == null || !GAME_PACKAGE.equals(candidate.packageName)
        || candidate.signatures == null || hub.signatures == null
        || !new HashSet<android.content.pm.Signature>(Arrays.asList(candidate.signatures))
          .equals(new HashSet<android.content.pm.Signature>(Arrays.asList(hub.signatures)))) {
        throw new IOException(I18n.t("Tệp tải không đúng module Nông trại hoặc không cùng chữ ký với Kinnect."));
      }
      try {
        PackageInfo installed = pm.getPackageInfo(GAME_PACKAGE, 0);
        if (candidate.versionCode <= installed.versionCode) throw new IOException(I18n.t("Module đã ở bản mới nhất."));
      } catch (PackageManager.NameNotFoundException firstInstall) { }
      if (cancelled) throw new InterruptedIOException();
      ready = FarmGameProvider.file(this);
      if (ready.exists() && !ready.delete()) throw new IOException(I18n.t("Không thể thay tệp module cũ."));
      if (!part.renameTo(ready)) throw new IOException(I18n.t("Không thể lưu module."));
      main.post(() -> { if (!cancelled) install(); });
    } catch (Exception failure) {
      part.delete();
      main.post(() -> {
        if (cancelled) return;
        status.setText(I18n.t("Chưa tải được module"));
        new Sheet(this).setTitle(I18n.t("Tải module chưa hoàn tất"))
          .setMessage(failure.getMessage() == null ? I18n.t("Vui lòng kiểm tra mạng rồi thử lại.") : failure.getMessage())
          .setPositiveButton(I18n.t("Đóng"), (dialog, which) -> finish()).show();
      });
    } finally {
      if (connection != null) connection.disconnect();
    }
  }

  private void install() {
    if (ready == null || !ready.isFile()) { finish(); return; }
    status.setText(I18n.t("Đã tải module. Đang mở trình cài đặt Android…"));
    if (!getPackageManager().canRequestPackageInstalls()) {
      new Sheet(this).setTitle(I18n.t("Cho phép Kinnect cài module"))
        .setMessage(I18n.t("Android cần bạn bật ‘Cho phép từ nguồn này’ cho Kinnect để cài module Nông trại."))
        .setPositiveButton(I18n.t("Mở cài đặt"), (dialog, which) -> {
          try {
            startActivityForResult(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
              Uri.parse("package:" + getPackageName())), SOURCES);
          } catch (Exception failure) {
            status.setText(I18n.t("Không mở được cài đặt cấp quyền."));
          }
        })
        .setNegativeButton(I18n.t("Để sau"), (dialog, which) -> finish()).show();
      return;
    }
    try {
      Uri uri = Uri.parse("content://" + getPackageName() + ".farmgame/farm-game.apk");
      Intent installer = new Intent(Intent.ACTION_INSTALL_PACKAGE)
        .setDataAndType(uri, "application/vnd.android.package-archive")
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        .putExtra(Intent.EXTRA_RETURN_RESULT, true);
      startActivityForResult(installer, INSTALL);
    } catch (Exception failure) {
      new Sheet(this).setMessage(I18n.t("Không mở được trình cài đặt Android. Module đã được tải."))
        .setPositiveButton(I18n.t("Đóng"), (dialog, which) -> finish()).show();
    }
  }

  @Override protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (request == SOURCES) {
      if (getPackageManager().canRequestPackageInstalls()) install();
      else status.setText(I18n.t("Chưa có quyền cài module. Bạn có thể thử lại từ Cài đặt Kinnect."));
    } else if (request == INSTALL) {
      if (result == RESULT_OK) {
        Toast.makeText(this, I18n.t("Đã cài module Nông trại"), Toast.LENGTH_SHORT).show();
        FarmGameModule.launch(this);
      } else {
        Toast.makeText(this, I18n.t("Bạn chưa cài module Nông trại"), Toast.LENGTH_SHORT).show();
      }
      finish();
    }
  }

  @Override protected void onDestroy() {
    cancelled = true;
    main.removeCallbacksAndMessages(null);
    super.onDestroy();
  }
}
