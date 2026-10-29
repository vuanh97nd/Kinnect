package app.kinnect.live;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;

/** Lưu lỗi văng app để lần mở sau người dùng xem và sao chép gửi lại. */
final class CrashLog {
  private static boolean installed;

  static void install(Context context) {
    if (installed) return;
    installed = true;
    final Context app = context.getApplicationContext();
    final Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
    Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
      try {
        java.io.StringWriter out = new java.io.StringWriter();
        error.printStackTrace(new java.io.PrintWriter(out));
        String version = "";
        try { version = app.getPackageManager().getPackageInfo(app.getPackageName(), 0).versionName; } catch (Exception ignored) {}
        String text = "Kinnect " + version + " · Android " + android.os.Build.VERSION.RELEASE + " · " + android.os.Build.MODEL + "\n" + out;
        app.getSharedPreferences("kinnect_crash", 0).edit().putString("last", text.length() > 6000 ? text.substring(0, 6000) : text).commit();
      } catch (Throwable ignored) {}
      if (previous != null) previous.uncaughtException(thread, error);
    });
  }

  static void record(Context context, Throwable error) {
    try {
      java.io.StringWriter out = new java.io.StringWriter();
      error.printStackTrace(new java.io.PrintWriter(out));
      String text = "Lỗi hiển thị (không văng app) · Android " + android.os.Build.VERSION.RELEASE + "\n" + out;
      context.getSharedPreferences("kinnect_crash", 0).edit().putString("last", text.length() > 6000 ? text.substring(0, 6000) : text).apply();
    } catch (Throwable ignored) {}
  }

  static void showPending(final Activity activity) {
    final String text = activity.getSharedPreferences("kinnect_crash", 0).getString("last", null);
    if (text == null) return;
    activity.getSharedPreferences("kinnect_crash", 0).edit().remove("last").apply();
    new Sheet(activity).setTitle(I18n.t("Kinnect vừa gặp lỗi")).setMessage(text.length() > 900 ? text.substring(0, 900) + "…" : text)
      .setPositiveButton(I18n.t("Sao chép lỗi"), (d, w) -> {
        ClipboardManager clip = (ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE);
        if (clip != null) clip.setPrimaryClip(ClipData.newPlainText("Lỗi Kinnect", text));
        android.widget.Toast.makeText(activity, I18n.t("Đã sao chép, hãy dán gửi cho đội Kinnect."), android.widget.Toast.LENGTH_LONG).show();
      })
      .setNegativeButton(I18n.t("Đóng"), null).show();
  }
}
