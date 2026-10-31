package app.kinnect.live;

import android.content.Context;

/** Keep bounded diagnostics locally; never interrupt startup with a crash popup. */
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

}
