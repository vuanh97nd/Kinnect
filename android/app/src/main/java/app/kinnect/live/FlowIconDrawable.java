package app.kinnect.live;

import android.graphics.*;
import android.graphics.drawable.Drawable;

/**
 * Biểu tượng danh mục theo chuẩn Google Material 3 Expressive Tonal Container:
 * Nền squircle bo tròn mềm mại với dải màu Google Material 3, viền sáng tinh tế và icon sắc nét.
 */
final class FlowIconDrawable extends Drawable {
  private final Drawable glyph;
  private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
  private final int top, bottom;
  private int alpha = 255;

  FlowIconDrawable(Drawable drawable, String name) {
    glyph = drawable.mutate();
    int[] colors = palette(name);
    top = colors[0];
    bottom = colors[1];
    glyph.setTint(Color.WHITE);
  }

  static int[] palette(String name) {
    String n = name.toLowerCase();
    if (n.contains("trash") || n.contains("block") || n.contains("log_out") || (n.contains("off") && n.contains("location"))) {
      return new int[] { 0xffea4335, 0xffc5221f }; // Google Red 500 -> 700
    }
    if (n.contains("heart") || n.contains("live") || n.contains("radio")) {
      return new int[] { 0xffe91e63, 0xffc2185b }; // Material Pink
    }
    if (n.contains("message") || n.contains("inbox") || n.contains("phone") || n.contains("call")) {
      return new int[] { 0xff1e8e3e, 0xff137333 }; // Google Green 600 -> 700
    }
    if (n.contains("wallet") || n.contains("shopping") || n.contains("gift")) {
      return new int[] { 0xfff9ab00, 0xffe37400 }; // Google Amber/Orange
    }
    if (n.contains("video") || n.contains("clapper") || n.contains("image")) {
      return new int[] { 0xffff6d00, 0xffe65100 }; // Deep Coral
    }
    if (n.contains("compass") || n.contains("shield") || n.contains("lock") || n.contains("location") || n.contains("distance") || n.contains("globe")) {
      return new int[] { 0xff1a73e8, 0xff174ea6 }; // Google Blue 600 -> 800
    }
    return new int[] { 0xff7c5cff, 0xff5e35b1 }; // Kinnect Google Violet
  }

  @Override
  public void draw(Canvas canvas) {
    Rect b = getBounds();
    float radius = b.width() * 0.34f; // Google Material 3 squircle radius
    paint.setAlpha(alpha);
    paint.setStyle(Paint.Style.FILL);
    paint.setShader(new LinearGradient(b.left, b.top, b.right, b.bottom, top, bottom, Shader.TileMode.CLAMP));
    canvas.drawRoundRect(new RectF(b), radius, radius, paint);
    paint.setShader(null);
    paint.setColor(Color.WHITE);
    paint.setAlpha(Math.round(alpha * 0.24f));
    paint.setStyle(Paint.Style.STROKE);
    paint.setStrokeWidth(Math.max(1f, b.width() / 36f));
    RectF rim = new RectF(b);
    rim.inset(1f, 1f);
    canvas.drawRoundRect(rim, radius - 1f, radius - 1f, paint);
    paint.setStyle(Paint.Style.FILL);
    int inset = Math.round(b.width() * 0.23f);
    glyph.setBounds(b.left + inset, b.top + inset, b.right - inset, b.bottom - inset);
    glyph.draw(canvas);
  }

  @Override public void setAlpha(int a) { alpha = a; glyph.setAlpha(a); invalidateSelf(); }
  @Override public void setColorFilter(ColorFilter f) { glyph.setColorFilter(f); invalidateSelf(); }
  @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
  @Override public int getIntrinsicWidth() { return 38; }
  @Override public int getIntrinsicHeight() { return 38; }
}
