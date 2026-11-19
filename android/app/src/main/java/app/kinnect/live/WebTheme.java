package app.kinnect.live;
final class WebTheme {
  static boolean isDark(android.content.Context context) {
    String theme = context.getSharedPreferences("kinnect_settings", 0).getString("theme", "auto");
    return "dark".equals(theme) || (!"light".equals(theme) && (context.getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES);
  }
}
