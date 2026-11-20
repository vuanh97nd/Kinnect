package app.kinnect.live;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import java.io.InputStream;

/** Welcome/Intro showcase custom views extracted from MainActivity without changing layout or rendering. */
final class WelcomeShowcaseViews {
  private WelcomeShowcaseViews() {}

  interface Host {
    int card();
    int text();
    int muted();
    int accent();
    int soft();
    int pink();
    int white();
    int primarySoft();
    int introTabOverride();
    void clearIntroTabOverride();
  }

  static class WelcomeScene extends View {
    final Host host;
    final Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
    final RectF rect = new RectF();
    Canvas canvas;

    WelcomeScene(Context context, Host host) {
      super(context);
      this.host = host;
      setLayerType(View.LAYER_TYPE_SOFTWARE, null);
    }

    void box(float x, float y, float w, float h, float radius, int color) {
      pen.setStyle(Paint.Style.FILL);
      pen.setShader(null);
      pen.setColor(color);
      rect.set(x, y, x + w, y + h);
      canvas.drawRoundRect(rect, radius, radius, pen);
    }

    void word(String text, float x, float y, float size, int color, boolean bold) {
      pen.setShader(null);
      pen.setColor(color);
      pen.setTypeface(ApprovedTypography.font(getContext(), bold ? Typeface.BOLD : Typeface.NORMAL));
      pen.setTextSize(size);
      canvas.drawText(text, x, y, pen);
    }

    void circle(float x, float y, float r, int color) {
      pen.setShader(null);
      pen.setColor(color);
      canvas.drawCircle(x, y, r, pen);
    }

    @Override
    protected void onDraw(Canvas c) {
      super.onDraw(c);
      canvas = c;
      float scale = Math.min(getWidth() / 380f, getHeight() / 310f);
      int saved = c.save();
      c.translate((getWidth() - 380 * scale) / 2, (getHeight() - 310 * scale) / 2);
      c.scale(scale, scale);
      circle(198, 150, 132, host.primarySoft());
      circle(312, 73, 25, (host.pink() & 0xffffff) | 0x18000000);
      circle(56, 235, 20, host.primarySoft());
      c.save();
      c.rotate(-7, 124, 151);
      pen.setShadowLayer(13, 0, 7, 0x1c2a154a);
      box(46, 39, 164, 231, 23, host.card());
      pen.clearShadowLayer();
      pen.setShader(new LinearGradient(62, 55, 195, 175, new int[] { 0xff8b5cf6, 0xffec4899 }, null, Shader.TileMode.CLAMP));
      rect.set(56, 49, 200, 177);
      c.drawRoundRect(rect, 17, 17, pen);
      pen.setShader(null);
      circle(128, 100, 22, 0xffeadcff);
      box(87, 128, 82, 46, 30, 0xffeadcff);
      word("HỒ SƠ MINH HỌA", 65, 195, 8, host.muted(), true);
      word("Là chính bạn", 65, 217, 16, host.text(), true);
      box(65, 232, 62, 20, 10, host.primarySoft());
      word("Âm nhạc", 73, 246, 9, host.accent(), true);
      box(134, 232, 55, 20, 10, host.soft());
      word("Du lịch", 142, 246, 9, host.muted(), true);
      c.restore();
      c.save();
      c.rotate(8, 261, 126);
      pen.setShadowLayer(12, 0, 6, 0x242a154a);
      box(208, 42, 126, 180, 20, 0xff30204b);
      pen.clearShadowLayer();
      box(218, 52, 106, 160, 14, 0xff4c2b70);
      circle(269, 116, 34, 0xff714096);
      pen.setColor(host.white());
      Path triangle = new Path();
      triangle.moveTo(261, 101);
      triangle.lineTo(261, 130);
      triangle.lineTo(283, 115);
      triangle.close();
      c.drawPath(triangle, pen);
      word("VIDEO", 229, 78, 10, 0xffeadcff, true);
      word("Chất riêng của bạn", 228, 188, 9, host.white(), true);
      c.restore();
      pen.setShadowLayer(10, 0, 5, 0x202a154a);
      box(140, 226, 209, 57, 17, host.card());
      pen.clearShadowLayer();
      circle(165, 255, 14, host.primarySoft());
      word("K", 160, 261, 15, host.accent(), true);
      word("Bắt đầu bằng lời chào", 188, 250, 12, host.text(), true);
      word("Nhắn tin · Gọi thoại · Video", 188, 267, 9, host.muted(), false);
      box(20, 190, 91, 30, 15, host.card());
      circle(35, 205, 4, 0xff10b981);
      word("LIVE", 47, 210, 11, host.text(), true);
      word("MINH HỌA TÍNH NĂNG", 126, 308, 8, host.muted(), false);
      c.restoreToCount(saved);
    }
  }

  static final class PhoneFeatureShowcase extends WelcomeScene {
    final Drawable miniLogo;
    final String[] tabs = { "Bảng tin", "Khám phá", "Video", "Live" };
    long clock = SystemClock.uptimeMillis();
    int manual = 1;
    Bitmap demoPhoto;
    final Bitmap[] demoPeople = new Bitmap[4];

    PhoneFeatureShowcase(Context context, Host host) {
      super(context, host);
      miniLogo = context.getResources().getDrawable(context.getResources().getIdentifier("kinnect_logo", "drawable", context.getPackageName()));
      setClickable(true);
      setContentDescription(I18n.t("Xem trước Bảng tin, Khám phá, Tạo nội dung, Video và Live"));
    }

    int currentActive() {
      int ov = host.introTabOverride();
      if (ov >= 0 && ov < 4) return ov;
      boolean animate = ValueAnimator.areAnimatorsEnabled();
      return (manual + (animate ? (int) ((SystemClock.uptimeMillis() - clock) / 1500) : 0)) % 4;
    }

    void selectPreview(int index) {
      host.clearIntroTabOverride();
      manual = index;
      clock = SystemClock.uptimeMillis();
      invalidate();
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
      if (event.getAction() == MotionEvent.ACTION_DOWN) return true;
      if (event.getAction() != MotionEvent.ACTION_UP) return true;
      performClick();
      float scale = Math.min(getWidth() / 330f, getHeight() / 450f);
      if (scale <= 0) return true;
      float x = (event.getX() - (getWidth() - 380 * scale) / 2) / scale;
      float y = (event.getY() - (getHeight() - 450 * scale) / 2) / scale;
      if (y >= 374 && y <= 416 && x >= 96 && x <= 284) {
        int tab = Math.max(0, Math.min(4, (int) ((x - 100) / 36)));
        if (tab == 2) selectPreview((currentActive() + 1) % 4);
        else selectPreview(tab < 2 ? tab : tab - 1);
        return true;
      }
      if (x >= 96 && x <= 284 && y >= 19 && y < 374) {
        selectPreview((currentActive() + 1) % 4);
      }
      return true;
    }

    @Override
    public boolean performClick() {
      super.performClick();
      return true;
    }

    void iphoneStatus() {
      int text = host.text();
      for (int i = 0; i < 4; i++) box(236 + i * 3.2f, 35.5f - (i + 1) * 1.7f, 2.2f, (i + 1) * 1.7f, .6f, text);
      pen.setColor(text);
      pen.setStyle(Paint.Style.STROKE);
      pen.setStrokeWidth(1.3f);
      canvas.drawArc(new RectF(250, 28.5f, 260, 38.5f), 222, 96, false, pen);
      canvas.drawArc(new RectF(252.3f, 30.8f, 257.7f, 36.2f), 222, 96, false, pen);
      pen.setStyle(Paint.Style.FILL);
      circle(255f, 35.3f, .85f, text);
      pen.setStyle(Paint.Style.STROKE);
      pen.setStrokeWidth(.85f);
      canvas.drawRoundRect(new RectF(263, 28.8f, 275.5f, 35.2f), 1.6f, 1.6f, pen);
      pen.setStyle(Paint.Style.FILL);
      box(264.3f, 30.1f, 9.6f, 3.8f, .6f, text);
      box(276.4f, 30.9f, 1.1f, 2.3f, .4f, text);
    }

    @Override
    public void onWindowFocusChanged(boolean focused) {
      super.onWindowFocusChanged(focused);
      if (focused) invalidate();
    }

    @Override
    protected void onAttachedToWindow() {
      super.onAttachedToWindow();
      invalidate();
    }

    void glyph(Drawable icon, float x, float y, int size, int color) {
      if (icon != miniLogo) icon.setTint(color);
      icon.setBounds((int) x, (int) y, (int) x + size, (int) y + size);
      icon.draw(canvas);
    }

    Bitmap decodeAssetThumbnail(String assetName) {
      try (InputStream stream = getContext().getAssets().open(assetName)) {
        byte[] bytes = NativeApi.read(stream, 8 * 1024 * 1024);
        return MediaImageLoader.decodeSampledBitmap(bytes, 320);
      } catch (Exception ignored) {
        return null;
      }
    }

    void photo(float x, float y, float w, float h, float topRadius, float bottomRadius) {
      if (demoPhoto == null) demoPhoto = decodeAssetThumbnail("welcome-profile.png");
      if (demoPhoto == null) return;
      int saved = canvas.save();
      Path clip = new Path();
      float[] radii = { topRadius, topRadius, topRadius, topRadius, bottomRadius, bottomRadius, bottomRadius, bottomRadius };
      clip.addRoundRect(new RectF(x, y, x + w, y + h), radii, Path.Direction.CW);
      canvas.clipPath(clip);
      box(x, y, w, h, 0, host.soft());
      float ratio = Math.max(w / demoPhoto.getWidth(), h / demoPhoto.getHeight());
      float rw = demoPhoto.getWidth() * ratio;
      float rh = demoPhoto.getHeight() * ratio;
      pen.setFilterBitmap(true);
      canvas.drawBitmap(demoPhoto, null, new RectF(x + (w - rw) / 2f, y, x + (w + rw) / 2f, y + rh), pen);
      canvas.restoreToCount(saved);
    }

    void photo(float x, float y, float w, float h, float radius) {
      photo(x, y, w, h, radius, radius);
    }

    void personPhoto(int index, float x, float y, float w, float h, float topRadius, float bottomRadius) {
      if (demoPeople[index] == null) demoPeople[index] = decodeAssetThumbnail(index == 0 ? "welcome-profile.png" : "welcome-profile-" + index + ".png");
      Bitmap previous = demoPhoto;
      demoPhoto = demoPeople[index];
      photo(x, y, w, h, topRadius, bottomRadius);
      demoPhoto = previous;
    }

    void filledHeart(float x, float y, float s, int color) {
      Path p = new Path();
      float cx = x + s / 2f;
      p.moveTo(cx, y + s * 0.88f);
      p.cubicTo(x + s * 0.12f, y + s * 0.62f, x + s * 0.03f, y + s * 0.42f, x + s * 0.03f, y + s * 0.28f);
      p.cubicTo(x + s * 0.03f, y + s * 0.11f, x + s * 0.17f, y + s * 0.02f, x + s * 0.31f, y + s * 0.02f);
      p.cubicTo(x + s * 0.41f, y + s * 0.02f, x + s * 0.48f, y + s * 0.08f, cx, y + s * 0.15f);
      p.cubicTo(x + s * 0.52f, y + s * 0.08f, x + s * 0.59f, y + s * 0.02f, x + s * 0.69f, y + s * 0.02f);
      p.cubicTo(x + s * 0.83f, y + s * 0.02f, x + s * 0.97f, y + s * 0.11f, x + s * 0.97f, y + s * 0.28f);
      p.cubicTo(x + s * 0.97f, y + s * 0.42f, x + s * 0.88f, y + s * 0.62f, cx, y + s * 0.88f);
      p.close();
      pen.setStyle(Paint.Style.FILL);
      pen.setShader(null);
      pen.setColor(color);
      canvas.drawPath(p, pen);
    }

    void filledBubble(float x, float y, float s, int color) {
      pen.setStyle(Paint.Style.FILL);
      pen.setShader(null);
      pen.setColor(color);
      canvas.drawOval(new RectF(x, y + s * 0.06f, x + s * 0.96f, y + s * 0.82f), pen);
      Path tail = new Path();
      tail.moveTo(x + s * 0.18f, y + s * 0.68f);
      tail.lineTo(x + s * 0.06f, y + s * 0.94f);
      tail.lineTo(x + s * 0.42f, y + s * 0.76f);
      tail.close();
      canvas.drawPath(tail, pen);
    }

    void playRectangleGlyph(float cx, float cy, int color) {
      pen.setStyle(Paint.Style.STROKE);
      pen.setStrokeWidth(1.35f);
      pen.setShader(null);
      pen.setColor(color);
      canvas.drawRoundRect(new RectF(cx - 7.5f, cy - 5.3f, cx + 7.5f, cy + 5.3f), 2.3f, 2.3f, pen);
      pen.setStyle(Paint.Style.FILL);
      Path tri = new Path();
      tri.moveTo(cx - 2.1f, cy - 2.6f);
      tri.lineTo(cx - 2.1f, cy + 2.6f);
      tri.lineTo(cx + 2.8f, cy);
      tri.close();
      canvas.drawPath(tri, pen);
    }

    void screen(int index) {
      int card = host.card();
      int text = host.text();
      int muted = host.muted();
      int accent = host.accent();
      int soft = host.soft();
      int white = host.white();
      box(96, 19, 188, 409, 27, card);
      word("9:41", 109, 34.5f, 8.2f, text, true);
      iphoneStatus();
      glyph(miniLogo, 104, 48, 18, white);
      word("Kinnect", 126, 61.5f, 13.5f, accent, true);
      glyph(WebIcons.load(getContext(), "bell"), 239, 50, 12, text);
      photo(258, 48, 16, 16, 8);
      word(I18n.t(tabs[index]), 105, 79, 8.2f, muted, false);
      if (index == 0) {
        circle(120, 104, 13.5f, soft);
        glyph(WebIcons.load(getContext(), "plus"), 113, 97, 14, accent);
        String storyCta = I18n.t("Tạo tin");
        pen.setTextSize(6.8f);
        pen.setTypeface(ApprovedTypography.font(getContext(), Typeface.NORMAL));
        word(storyCta, 120 - pen.measureText(storyCta) / 2f, 126, 6.8f, muted, false);
        pen.setStyle(Paint.Style.STROKE);
        pen.setStrokeWidth(1.5f);
        pen.setColor(accent);
        canvas.drawCircle(156, 104, 15f, pen);
        pen.setStyle(Paint.Style.FILL);
        personPhoto(0, 143, 91, 26, 26, 13, 13);
        String authorShort = "Minh Anh";
        pen.setTextSize(6.8f);
        word(authorShort, 156 - pen.measureText(authorShort) / 2f, 126, 6.8f, muted, false);
        box(104, 135, 172, 25, 8, soft);
        personPhoto(0, 109, 138.5f, 18, 18, 9, 9);
        word(I18n.t("Bạn đang nghĩ gì?"), 133, 150.5f, 7.8f, muted, false);
        box(104, 167, 172, 199, 10, soft);
        personPhoto(0, 111, 174, 20, 20, 10, 10);
        word("Minh Anh · 27", 136, 182.5f, 8.2f, text, true);
        word(I18n.t("Hồ sơ minh họa"), 136, 192.5f, 6.8f, muted, false);
        word(I18n.t("Tập luyện mỗi ngày"), 111, 206.5f, 8f, text, false);
        personPhoto(0, 111, 213, 158, 125, 7, 7);
        filledHeart(113, 346, 12, 0xffec4899);
        filledBubble(136, 346, 12, muted);
        glyph(WebIcons.load(getContext(), "forward"), 159, 345, 13, muted);
      } else if (index == 1) {
        box(104, 89, 172, 22, 7, soft);
        word(I18n.t("Dành cho bạn"), 112, 102.5f, 7.5f, accent, true);
        String followTab = I18n.t("Đang theo dõi");
        pen.setTextSize(7.5f);
        pen.setTypeface(ApprovedTypography.font(getContext(), Typeface.BOLD));
        word(followTab, 268 - pen.measureText(followTab), 102.5f, 7.5f, text, true);
        box(104, 117, 172, 22, 7, soft);
        glyph(WebIcons.load(getContext(), "search"), 110, 123, 10, muted);
        word(I18n.t("Tên đăng nhập"), 124, 131, 7.8f, muted, false);
        String[] people = { "Minh Anh, 27", "Gia Huy, 28", "Hoàng Nam, 30", "Quang Minh, 26" };
        for (int i = 0; i < 4; i++) {
          float px = 104 + (i % 2) * 90;
          float py = 147 + (i / 2) * 112;
          box(px, py, 82, 104, 8, soft);
          personPhoto(i, px, py, 82, 83, 8, 0);
          pen.setTextSize(7.4f);
          pen.setTypeface(ApprovedTypography.font(getContext(), Typeface.BOLD));
          float labelX = px + (82 - pen.measureText(people[i])) / 2f;
          word(people[i], labelX, py + 96, 7.4f, text, true);
        }
      } else if (index == 2) {
        personPhoto(1, 104, 89, 172, 279, 10, 10);
        int scrim = canvas.save();
        Path clip = new Path();
        clip.addRoundRect(new RectF(104, 89, 276, 368), 10, 10, Path.Direction.CW);
        canvas.clipPath(clip);
        pen.setStyle(Paint.Style.FILL);
        pen.setShader(new LinearGradient(0, 318, 0, 368, 0x00000000, 0x78000000, Shader.TileMode.CLAMP));
        canvas.drawRect(104, 318, 276, 368, pen);
        pen.setShader(null);
        canvas.restoreToCount(scrim);
        word("@minhanh_demo", 112, 358, 8.5f, white, true);
      } else {
        personPhoto(2, 104, 89, 172, 279, 10, 10);
        box(111, 97, 34, 16, 8, 0xffdb2777);
        pen.setTextSize(7.2f);
        pen.setTypeface(ApprovedTypography.font(getContext(), Typeface.BOLD));
        float liveW = pen.measureText("LIVE");
        word("LIVE", 111 + (34 - liveW) / 2f, 107.8f, 7.2f, white, true);
      }
    }

    void previewNavigation(int index) {
      String[] names = { "Bảng tin", "Khám phá", "", "Video", "Live" };
      String[] icons = { "house", "compass", "plus", "", "radio" };
      for (int i = 0; i < 5; i++) {
        float center = 118 + i * 36;
        boolean selected = i == (index < 2 ? index : index + 1);
        int ink = selected ? host.accent() : host.muted();
        if (i == 2) {
          box(center - 13.5f, 379, 27, 27, 9, host.accent());
          glyph(WebIcons.load(getContext(), "plus"), center - 7, 385.5f, 14, host.white());
        } else {
          if (i == 3) playRectangleGlyph(center, 392.5f, ink);
          else glyph(WebIcons.load(getContext(), icons[i]), center - 7, 385.5f, 14, ink);
          String tabLabel = I18n.t(names[i]);
          pen.setTextSize(6.7f);
          pen.setTypeface(ApprovedTypography.font(getContext(), Typeface.NORMAL));
          word(tabLabel, center - pen.measureText(tabLabel) / 2f, 410, 6.7f, ink, false);
        }
      }
    }

    void concentricRings() {
      pen.setStyle(Paint.Style.STROKE);
      pen.setStrokeWidth(1f);
      pen.setShader(null);
      pen.setColor((0x1e << 24) | (host.accent() & 0xffffff));
      for (int r : new int[] { 140, 170, 200 }) canvas.drawCircle(190, 224, r, pen);
      pen.setStyle(Paint.Style.FILL);
    }

    @Override
    protected void onDraw(Canvas c) {
      canvas = c;
      float scale = Math.min(getWidth() / 330f, getHeight() / 450f);
      if (scale <= 0) return;
      int save = c.save();
      c.translate((getWidth() - 380 * scale) / 2f, (getHeight() - 450 * scale) / 2f);
      c.scale(scale, scale);
      long elapsed = SystemClock.uptimeMillis() - clock;
      boolean animate = host.introTabOverride() < 0 && ValueAnimator.areAnimatorsEnabled();
      int index = currentActive();
      float phase = animate ? (elapsed % 1500) / 1500f : 0f;
      concentricRings();
      c.save();
      pen.setShadowLayer(16, 0, 8, 0x30000000);
      box(89, 12, 202, 423, 34, 0xffa6a6ad);
      pen.clearShadowLayer();
      box(91, 14, 198, 419, 32, 0xff000000);
      int screenClip = c.save();
      Path inner = new Path();
      inner.addRoundRect(new RectF(96, 19, 284, 428), 27, 27, Path.Direction.CW);
      c.clipPath(inner);
      screen(index);
      if (phase > .80f) {
        int alpha = (int) ((phase - .80f) / .20f * 255);
        int layer = c.saveLayerAlpha(96, 19, 284, 376, alpha);
        screen((index + 1) % 4);
        c.restoreToCount(layer);
      }
      previewNavigation(index);
      box(172, 25, 36, 10, 5, 0xff000000);
      int barColor = WebTheme.isDark(getContext()) ? 0x55ffffff : 0xff1f1d2b;
      box(164, 418, 52, 3, 1.5f, barColor);
      c.restoreToCount(screenClip);
      c.restore();
      c.restoreToCount(save);
      if (animate && isShown() && hasWindowFocus()) postInvalidateDelayed(33);
    }
  }
}
