package app.kinnect.live;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.drawable.Drawable;
import android.view.MotionEvent;
import android.view.View;

/** Stateless text, color, touch, and vector-glyph helpers extracted from MainActivity. */
final class MainActivityHelpers {
  private MainActivityHelpers() {}

  static int mentionIndex(String text, String username) {
    if (text == null || username == null || username.isEmpty()) return -1;
    String token = "@" + username;
    for (int at = text.indexOf(token); at >= 0; at = text.indexOf(token, at + token.length())) {
      int end = at + token.length();
      char before = at == 0 ? ' ' : text.charAt(at - 1);
      boolean start = at == 0 || Character.isWhitespace(before) || before == '(' || before == '[' || before == '{';
      boolean finish = end == text.length() || !(Character.isLetterOrDigit(text.charAt(end)) || "_.-".indexOf(text.charAt(end)) >= 0);
      if (start && finish) return at;
    }
    return -1;
  }

  /** Decode HTML entities up to 4 passes for double-encoded server payloads. */
  static String decodeEntities(String s) {
    if (s == null || s.indexOf('&') < 0) return s;
    java.util.regex.Pattern p = java.util.regex.Pattern.compile("&#(\\d+);|&#[xX]([0-9a-fA-F]+);|&(amp|lt|gt|quot|apos|nbsp);");
    String out = s;
    for (int pass = 0; pass < 4 && out.indexOf('&') >= 0; pass++) {
      java.util.regex.Matcher m = p.matcher(out);
      StringBuffer next = new StringBuffer();
      boolean changed = false;
      while (m.find()) {
        String rep;
        if (m.group(1) != null || m.group(2) != null) {
          int cp = 0;
          try {
            cp = m.group(1) != null ? Integer.parseInt(m.group(1)) : Integer.parseInt(m.group(2), 16);
          } catch (NumberFormatException ignored) {}
          rep = Character.isValidCodePoint(cp) ? new String(Character.toChars(cp)) : m.group();
        } else {
          String n = m.group(3);
          rep = n.equals("amp") ? "&" : n.equals("lt") ? "<" : n.equals("gt") ? ">" : n.equals("quot") ? "\"" : n.equals("apos") ? "'" : "\u00a0";
        }
        m.appendReplacement(next, java.util.regex.Matcher.quoteReplacement(rep));
        changed = true;
      }
      if (!changed) break;
      m.appendTail(next);
      out = next.toString();
    }
    return out;
  }

  /** Blend two ARGB colors while preserving opaque alpha. */
  static int mixColor(int a, int b, float t) {
    float u = 1f - t;
    return 0xff000000
      | (Math.round(((a >> 16) & 0xff) * u + ((b >> 16) & 0xff) * t) << 16)
      | (Math.round(((a >> 8) & 0xff) * u + ((b >> 8) & 0xff) * t) << 8)
      | Math.round((a & 0xff) * u + (b & 0xff) * t);
  }

  /** Subtle press scale feedback on action buttons without consuming click events. */
  static void installTactile(View v) {
    v.setOnTouchListener((view, event) -> {
      switch (event.getActionMasked()) {
        case MotionEvent.ACTION_DOWN:
          view.animate().scaleX(0.96f).scaleY(0.96f).setDuration(WebDesign.MOTION_FAST).start();
          break;
        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_CANCEL:
          view.animate().scaleX(1f).scaleY(1f).setDuration(WebDesign.MOTION_BASE).start();
          break;
      }
      return false;
    });
  }

  /** Scalable icon drawable backed by WebIcons for settings, groups, and chat actions. */
  static final class SettingsGlyphDrawable extends Drawable {
    private final Context context;
    private final String kind;
    private final Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final int tint;
    private final int back;

    SettingsGlyphDrawable(Context context, String kind, int tint, int back) {
      this.context = context;
      this.kind = kind;
      this.tint = tint;
      this.back = back;
    }

    @Override
    public void draw(Canvas canvas) {
      Drawable d = WebIcons.load(context, kind);
      d.setTint(tint);
      d.setBounds(getBounds());
      d.draw(canvas);
    }

    @Override
    public void setAlpha(int alpha) {
      pen.setAlpha(alpha);
      invalidateSelf();
    }

    @Override
    public void setColorFilter(ColorFilter filter) {
      pen.setColorFilter(filter);
      invalidateSelf();
    }

    @Override
    public int getOpacity() {
      return PixelFormat.TRANSLUCENT;
    }
  }
}
