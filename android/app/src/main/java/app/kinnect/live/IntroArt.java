package app.kinnect.live;

import android.content.Context;
import android.graphics.*;
import android.view.View;

/** Hình minh hoạ màn chào mừng giống bản web: logo K giữa hai vòng quỹ đạo, avatar và nhãn nổi. */
final class IntroArt extends View {
  private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
  private final android.graphics.drawable.Drawable logo;
  private final int page;
  private static final String[] LETTERS = { "M", "T", "Q", "H", "L" };
  private static final int[][] COLORS = { { 0xffb04cff, 0xffe055c8 }, { 0xffff5f6d, 0xffd9466f }, { 0xff4f7dff, 0xff6d4aff }, { 0xfff7b733, 0xffef6f6c }, { 0xffff5fb0, 0xffb04cff } };
  private static final double[] ANGLES = { -90, -30, 40, 145, 210 };
  private static final String[][] CHIPS = {
    { "👋 Xin chào!", "● 2,1K đang online", "♥ Cùng gu" },
    { "📝 Bài viết mới", "♥ 128", "💬 24" },
    { "▶ Video ngắn", "♥ 1,2K", "🎵 Nhạc nền" },
    { "📍 Quanh đây", "💜 Hợp gu", "✨ Mới" },
    { "🔒 Riêng tư", "● Live", "🛡 An toàn" },
  };

  IntroArt(Context context, int page) {
    super(context);
    this.page = Math.max(0, Math.min(page, CHIPS.length - 1));
    logo = getResources().getDrawable(getResources().getIdentifier("kinnect_logo", "drawable", context.getPackageName()));
    setContentDescription("Minh hoạ Kinnect");
  }

  private float dp(float v) {
    return v * getResources().getDisplayMetrics().density;
  }

  @Override
  protected void onDraw(Canvas c) {
    float cx = getWidth() / 2f, cy = getHeight() / 2f, r = Math.min(cx, cy) * 0.86f;
    paint.setStyle(Paint.Style.STROKE);
    paint.setStrokeWidth(dp(1.5f));
    paint.setPathEffect(new DashPathEffect(new float[] { dp(4), dp(5) }, 0));
    paint.setColor(0x66ff6fae);
    c.drawCircle(cx, cy, r, paint);
    paint.setColor(0x558b6dff);
    c.drawCircle(cx, cy, r * 0.68f, paint);
    paint.setPathEffect(null);
    paint.setStyle(Paint.Style.FILL);
    // Logo giữa có viền trắng mờ và bóng
    float s = r * 0.62f;
    RectF box = new RectF(cx - s / 2, cy - s / 2, cx + s / 2, cy + s / 2);
    paint.setColor(0x55ffffff);
    c.drawRoundRect(new RectF(box.left - dp(5), box.top - dp(5), box.right + dp(5), box.bottom + dp(5)), s * 0.27f, s * 0.27f, paint);
    if (logo != null) {
      logo.setBounds(Math.round(box.left), Math.round(box.top), Math.round(box.right), Math.round(box.bottom));
      logo.draw(c);
    }
    // Avatar trên quỹ đạo
    float a = r * 0.2f;
    for (int i = 0; i < LETTERS.length; i++) {
      double rad = Math.toRadians(ANGLES[i] + page * 14);
      float x = cx + (float) Math.cos(rad) * (i % 2 == 0 ? r : r * 0.82f), y = cy + (float) Math.sin(rad) * (i % 2 == 0 ? r : r * 0.82f);
      paint.setShader(null);
      paint.setColor(0xffffffff);
      c.drawCircle(x, y, a + dp(3), paint);
      paint.setShader(new LinearGradient(x - a, y - a, x + a, y + a, COLORS[i][0], COLORS[i][1], Shader.TileMode.CLAMP));
      c.drawCircle(x, y, a, paint);
      paint.setShader(null);
      paint.setColor(0xffffffff);
      paint.setTextAlign(Paint.Align.CENTER);
      paint.setTextSize(a * 0.85f);
      paint.setFakeBoldText(true);
      c.drawText(LETTERS[i], x, y + a * 0.3f, paint);
    }
    // Nhãn nổi màu trắng
    String[] chips = CHIPS[page];
    float[][] spots = { { cx - r * 0.62f, cy - r * 0.82f }, { cx + r * 0.62f, cy + r * 0.05f }, { cx, cy + r * 0.98f } };
    paint.setTextSize(dp(12.5f));
    for (int i = 0; i < chips.length; i++) {
      float w = paint.measureText(chips[i]) + dp(24), h = dp(32);
      float x = Math.max(w / 2 + dp(4), Math.min(getWidth() - w / 2 - dp(4), spots[i][0])), y = spots[i][1];
      paint.setColor(0xffffffff);
      c.drawRoundRect(new RectF(x - w / 2, y - h / 2, x + w / 2, y + h / 2), h / 2, h / 2, paint);
      paint.setColor(i == 2 ? 0xffff4f9a : 0xff1c1e21);
      String t = chips[i];
      if (t.startsWith("● ")) {
        paint.setColor(0xff22c55e);
        float tw = paint.measureText(t);
        c.drawCircle(x - tw / 2 + dp(3), y, dp(4), paint);
        paint.setColor(0xff1c1e21);
        t = "   " + t.substring(2);
      }
      c.drawText(t, x, y + dp(4.5f), paint);
    }
    paint.setFakeBoldText(false);
  }
}
