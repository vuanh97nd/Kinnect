package app.kinnect.live;

import android.app.Activity;
import java.text.Normalizer;
import java.util.Locale;

/** Google Play flavor stub: preserves pure-string normalization while disabling Live Game picker UI. */
final class LiveGamePicker {
 interface Selected { void choose(String title); }
 static final String[][] GAMES = {};
 static String normalized(String value) {
  if (value == null) return "";
  return Normalizer.normalize(value, Normalizer.Form.NFD).replaceAll("\\p{M}+", "").replace('đ', 'd').replace('Đ', 'D').toLowerCase(Locale.ROOT).trim();
 }
 static boolean matches(String[] game, String query) { return false; }
 LiveGamePicker(Activity activity, String current, Selected chosen) {}
 void show() {}
 void close() {}
}
