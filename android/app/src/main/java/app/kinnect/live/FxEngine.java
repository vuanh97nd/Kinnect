package app.kinnect.live;

import android.graphics.*;

/**
 * Bộ hiệu ứng camera của Kinnect: bộ lọc màu (có độ đậm), làm đẹp (mịn da, sáng da, gọn mặt,
 * mắt to, má hồng) và sticker theo khuôn mặt. Dùng chung cho xem trước, quay video và chụp ảnh.
 * Bộ lọc và sticker do Kinnect tự thiết kế (ma trận màu, hình vẽ, emoji hệ thống).
 */
final class FxEngine {
  // id, tên hiển thị
  static final String[][] FILTERS = {
    { "none", "Gốc" }, { "clear", "Trong trẻo" }, { "milk", "Sữa" }, { "peach", "Hồng đào" },
    { "warm", "Ấm áp" }, { "cool", "Mát lạnh" }, { "film", "Phim cũ" }, { "mono", "Đen trắng" },
    { "noir", "Tương phản" }, { "vivid", "Rực rỡ" }, { "sunset", "Hoàng hôn" }, { "candy", "Kẹo ngọt" },
    { "mint", "Bạc hà" }, { "dream", "Mộng mơ" }, { "retro", "Retro" }, { "city", "Thành phố" },
  };
  // id, tên, biểu tượng
  static final String[][] STICKERS = {
    { "none", "Không", "🚫" }, { "glasses", "Kính râm", "🕶" }, { "bunny", "Tai thỏ", "🐰" }, { "cat", "Tai mèo", "🐱" },
    { "dog", "Cún con", "🐶" }, { "crown", "Vương miện", "👑" }, { "flowers", "Vòng hoa", "🌸" }, { "bow", "Nơ xinh", "🎀" },
    { "freckles", "Tàn nhang", "🤎" }, { "hearts", "Tim bay", "💕" }, { "sparkle", "Lấp lánh", "✨" }, { "stars", "Sao xoay", "⭐" },
  };
  static final String[][] BEAUTY = { { "smooth", "Mịn da" }, { "whiten", "Sáng da" }, { "slim", "Gọn mặt" }, { "eyes", "Mắt to" }, { "blush", "Má hồng" } };

  String filter = "none", sticker = "none";
  float intensity = 1f;
  float smooth = 0.5f, whiten = 0.3f, slim = 0.2f, eyes = 0.2f, blush = 0f;
  boolean beautyOn = true, auto = false;
  /** Cân sáng tự động do AI tính: hệ số và độ lệch cho kênh sáng. */
  float autoGain = 1f, autoOffset = 0f;

  FxEngine copy() {
    FxEngine e = new FxEngine();
    e.filter = filter; e.sticker = sticker; e.intensity = intensity;
    e.smooth = smooth; e.whiten = whiten; e.slim = slim; e.eyes = eyes; e.blush = blush;
    e.beautyOn = beautyOn; e.auto = auto; e.autoGain = autoGain; e.autoOffset = autoOffset;
    return e;
  }

  /**
   * "AI làm đẹp" chạy trên máy: đo độ sáng/độ tương phản của khung hình và vùng da mặt,
   * rồi tự đặt mức cân sáng, mịn da, sáng da, mắt, gọn mặt cho phù hợp. Không gửi ảnh đi đâu.
   */
  void analyze(Bitmap frame, float[] face) {
    int w = frame.getWidth(), h = frame.getHeight();
    long sum = 0, sq = 0;
    int n = 0;
    for (int y = h / 10; y < h; y += h / 24) for (int x = w / 10; x < w; x += w / 16) {
      int c = frame.getPixel(Math.min(x, w - 1), Math.min(y, h - 1));
      int l = (Color.red(c) * 299 + Color.green(c) * 587 + Color.blue(c) * 114) / 1000;
      sum += l; sq += l * l; n++;
    }
    float mean = sum / (float) n, std = (float) Math.sqrt(Math.max(1, sq / (float) n - mean * mean));
    // Kéo độ sáng trung bình về ~128 và độ tương phản về ~55, có giới hạn để không quá tay.
    float gain = Math.max(0.85f, Math.min(1.35f, 55f / std));
    autoGain = 1 + (gain - 1) * 0.4f;
    autoOffset = Math.max(-20, Math.min(24, (125 - mean * autoGain) * 0.4f));
    if (face == null) return;
    float fx = face[0], fy = face[1], fe = face[2];
    long skin = 0, skinSq = 0;
    int m = 0;
    for (int dy = -2; dy <= 6; dy++) for (int dx = -5; dx <= 5; dx++) {
      int x = Math.round(fx + dx * fe * 0.12f), y = Math.round(fy + fe * 0.35f + dy * fe * 0.1f);
      if (x < 0 || y < 0 || x >= w || y >= h) continue;
      int c = frame.getPixel(x, y);
      int l = (Color.red(c) * 299 + Color.green(c) * 587 + Color.blue(c) * 114) / 1000;
      skin += l; skinSq += l * l; m++;
    }
    if (m == 0) return;
    float skinMean = skin / (float) m, skinTex = (float) Math.sqrt(Math.max(1, skinSq / (float) m - skinMean * skinMean));
    // Da sần/nhiều chi tiết → mịn hơn; da tối → sáng hơn; mặt xa máy → giảm biến dạng.
    smooth = Math.max(0.3f, Math.min(0.85f, 0.25f + skinTex / 40f));
    whiten = Math.max(0.1f, Math.min(0.4f, (140 - skinMean) / 160f + 0.15f));
    float sizeRatio = fe / w;
    eyes = sizeRatio > 0.12f ? 0.3f : 0.15f;
    slim = sizeRatio > 0.12f ? 0.3f : 0.15f;
    blush = Math.max(blush, 0.15f);
  }

  private final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
  private final Paint soft = new Paint(Paint.FILTER_BITMAP_FLAG);
  private final Paint shape = new Paint(Paint.ANTI_ALIAS_FLAG);
  private final Paint emoji = new Paint(Paint.ANTI_ALIAS_FLAG);
  private static final int MW = 36, MH = 64;
  private final float[] mesh = new float[(MW + 1) * (MH + 1) * 2];
  private Bitmap blurred;

  FxEngine() { emoji.setTextAlign(Paint.Align.CENTER); }

  float get(String key) {
    switch (key) {
      case "smooth": return smooth;
      case "whiten": return whiten;
      case "slim": return slim;
      case "eyes": return eyes;
      default: return blush;
    }
  }

  void set(String key, float v) {
    switch (key) {
      case "smooth": smooth = v; break;
      case "whiten": whiten = v; break;
      case "slim": slim = v; break;
      case "eyes": eyes = v; break;
      default: blush = v;
    }
  }

  // ===== Màu =====
  private static float[] identity() { return new float[] { 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0 }; }

  private static ColorMatrix sat(float s) { ColorMatrix m = new ColorMatrix(); m.setSaturation(s); return m; }

  private static ColorMatrix contrast(float c) { float t = (1 - c) * 128; return new ColorMatrix(new float[] { c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0 }); }

  private static ColorMatrix tint(float r, float g, float b, float add) { return new ColorMatrix(new float[] { r, 0, 0, 0, add, 0, g, 0, 0, add, 0, 0, b, 0, add, 0, 0, 0, 1, 0 }); }

  private static ColorMatrix offset(float r, float g, float b) { return new ColorMatrix(new float[] { 1, 0, 0, 0, r, 0, 1, 0, 0, g, 0, 0, 1, 0, b, 0, 0, 0, 1, 0 }); }

  /** Nâng vùng tối (giả lập phim nhạt màu). */
  private static ColorMatrix fade(float f) { float k = 1 - f; return new ColorMatrix(new float[] { k, 0, 0, 0, f * 255, 0, k, 0, 0, f * 255, 0, 0, k, 0, f * 255, 0, 0, 0, 1, 0 }); }

  private static ColorMatrix chain(ColorMatrix... parts) { ColorMatrix m = new ColorMatrix(); for (ColorMatrix p : parts) m.postConcat(p); return m; }

  static ColorMatrix filterMatrix(String id) {
    switch (id) {
      case "clear": return chain(contrast(1.08f), sat(1.08f), offset(10, 10, 12));
      case "milk": return chain(sat(0.75f), fade(0.08f), tint(1.03f, 1.0f, 0.97f, 8));
      case "peach": return chain(sat(1.05f), tint(1.06f, 0.98f, 1.0f, 6), offset(14, 0, 6));
      case "warm": return chain(tint(1.1f, 1.02f, 0.88f, 6), sat(1.05f));
      case "cool": return chain(tint(0.92f, 1.0f, 1.12f, 4), sat(0.95f));
      case "film": return chain(sat(0.7f), fade(0.12f), tint(1.06f, 1.0f, 0.86f, 0), contrast(0.95f));
      case "mono": return sat(0);
      case "noir": return chain(sat(0), contrast(1.35f));
      case "vivid": return chain(sat(1.45f), contrast(1.08f));
      case "sunset": return chain(tint(1.12f, 0.96f, 0.86f, 0), offset(18, 0, 14), sat(1.1f));
      case "candy": return chain(sat(1.25f), tint(1.04f, 0.97f, 1.08f, 10), fade(0.05f));
      case "mint": return chain(tint(0.92f, 1.06f, 1.02f, 6), sat(0.9f), fade(0.05f));
      case "dream": return chain(sat(0.85f), fade(0.1f), tint(1.04f, 0.98f, 1.1f, 8));
      case "retro": return chain(tint(1.08f, 0.98f, 0.9f, 0), offset(0, 6, 14), contrast(1.1f), sat(0.9f));
      case "city": return chain(sat(0.7f), contrast(1.15f), tint(0.95f, 1.0f, 1.06f, 0));
      default: return new ColorMatrix();
    }
  }

  static boolean vignette(String id) { return id.equals("film") || id.equals("noir") || id.equals("retro") || id.equals("dream"); }

  /** Ma trận cuối cùng: bộ lọc pha theo độ đậm + sáng da. */
  ColorMatrixColorFilter colorFilter() {
    float[] base = identity(), target = filterMatrix(filter).getArray();
    float[] mixed = new float[20];
    for (int i = 0; i < 20; i++) mixed[i] = base[i] + (target[i] - base[i]) * intensity;
    ColorMatrix m = new ColorMatrix(mixed);
    if (auto) m.postConcat(new ColorMatrix(new float[] { autoGain, 0, 0, 0, autoOffset, 0, autoGain, 0, 0, autoOffset, 0, 0, autoGain, 0, autoOffset, 0, 0, 0, 1, 0 }));
    if (beautyOn && whiten > 0) m.postConcat(chain(tint(1 + whiten * 0.06f, 1 + whiten * 0.07f, 1 + whiten * 0.08f, whiten * 22), sat(1 - whiten * 0.12f)));
    return new ColorMatrixColorFilter(m);
  }

  // ===== Vẽ =====
  /**
   * Vẽ một khung hình đã xử lý lên canvas.
   * @param face toạ độ trong ảnh nguồn: x, y (giữa hai mắt), khoảng cách mắt, góc nghiêng (độ); có thể null.
   */
  void render(Canvas c, Bitmap src, float[] face, int tick) {
    int cw = c.getWidth(), ch = c.getHeight();
    float sx = cw / (float) src.getWidth(), sy = ch / (float) src.getHeight();
    ColorMatrixColorFilter cf = colorFilter();
    paint.setColorFilter(cf);
    float fx = 0, fy = 0, fe = 0, fa = 0;
    if (face != null) { fx = face[0] * sx; fy = face[1] * sy; fe = face[2] * sx; fa = face[3]; }
    boolean warp = beautyOn && face != null && (slim > 0.01f || eyes > 0.01f);
    if (warp) {
      buildMesh(cw, ch, fx, fy, fe, fa);
      c.drawBitmapMesh(src, MW, MH, mesh, 0, null, 0, paint);
    } else c.drawBitmap(src, null, new Rect(0, 0, cw, ch), paint);
    // Mịn da: lớp mờ chỉ trong vùng khuôn mặt (không làm nhoè phông nền).
    if (beautyOn && smooth > 0.01f && face != null) {
      int bw = Math.max(8, src.getWidth() / 7), bh = Math.max(8, src.getHeight() / 7);
      if (blurred == null || blurred.getWidth() != bw || blurred.getHeight() != bh) blurred = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888);
      new Canvas(blurred).drawBitmap(src, null, new Rect(0, 0, bw, bh), soft);
      soft.setColorFilter(cf);
      soft.setAlpha(Math.round(40 + smooth * 150));
      // Lớp mịn chỉ phủ vùng da mặt, mờ dần ra viền (mặt nạ chuyển sắc hình bầu dục) để không lộ ranh giới.
      float ox = fx, oy = fy + fe * 0.55f, rx = fe * 1.15f, ry = fe * 1.55f;
      RectF bounds = new RectF(ox - rx * 1.2f, oy - ry * 1.2f, ox + rx * 1.2f, oy + ry * 1.2f);
      int layer = c.saveLayer(0, 0, cw, ch, null);
      if (warp) c.drawBitmapMesh(blurred, MW, MH, mesh, 0, null, 0, soft);
      else c.drawBitmap(blurred, null, new Rect(0, 0, cw, ch), soft);
      Paint mask = new Paint(Paint.ANTI_ALIAS_FLAG);
      mask.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.DST_IN));
      RadialGradient rg = new RadialGradient(0, 0, 1, new int[] { 0xff000000, 0xff000000, 0x00000000 }, new float[] { 0, 0.6f, 1 }, Shader.TileMode.CLAMP);
      Matrix mx = new Matrix();
      mx.setScale(rx, ry);
      mx.postRotate(fa);
      mx.postTranslate(ox, oy);
      rg.setLocalMatrix(mx);
      mask.setShader(rg);
      c.drawRect(0, 0, cw, ch, mask);
      c.restoreToCount(layer);
      soft.setAlpha(255);
    }
    if (vignette(filter) && intensity > 0.05f) {
      Paint v = new Paint();
      v.setShader(new RadialGradient(cw / 2f, ch / 2f, Math.max(cw, ch) * 0.75f, new int[] { 0x00000000, 0x00000000, Color.argb(Math.round(150 * intensity), 0, 0, 0) }, new float[] { 0, 0.55f, 1 }, Shader.TileMode.CLAMP));
      c.drawRect(0, 0, cw, ch, v);
    }
    if (face == null) return;
    if (beautyOn && blush > 0.01f) cheeks(c, fx, fy, fe, fa, Color.argb(Math.round(blush * 120), 255, 105, 140));
    if (!sticker.equals("none")) sticker(c, fx, fy, fe, fa, tick);
  }

  private void buildMesh(int cw, int ch, float fx, float fy, float fe, float fa) {
    double rad = Math.toRadians(fa);
    float cos = (float) Math.cos(rad), sin = (float) Math.sin(rad);
    float lx = fx - cos * fe / 2, ly = fy - sin * fe / 2, rx = fx + cos * fe / 2, ry = fy + sin * fe / 2;
    float eyeR = fe * 0.62f, eyeK = eyes * 0.32f;
    float chinY = fe * 2.0f, faceW = fe * 1.55f;
    int k = 0;
    for (int j = 0; j <= MH; j++) {
      for (int i = 0; i <= MW; i++) {
        float x = cw * i / (float) MW, y = ch * j / (float) MH;
        float nx = x, ny = y;
        // Mắt to: đẩy các điểm quanh mắt ra ngoài (phóng to vùng mắt).
        for (int e = 0; e < 2; e++) {
          float ex = e == 0 ? lx : rx, ey = e == 0 ? ly : ry;
          float dx = x - ex, dy = y - ey, d = (float) Math.sqrt(dx * dx + dy * dy);
          if (d < eyeR) { float f = eyeK * (1 - (d / eyeR) * (d / eyeR)); nx += dx * f; ny += dy * f; }
        }
        // Gọn mặt: kéo hai bên má/cằm vào giữa (toạ độ theo trục khuôn mặt).
        float ux = (x - fx) * cos + (y - fy) * sin, uy = -(x - fx) * sin + (y - fy) * cos;
        if (uy > 0 && uy < chinY * 1.15f && Math.abs(ux) < faceW * 1.35f) {
          float vertical = (float) Math.sin(Math.PI * Math.min(1, uy / (chinY * 1.15f)));
          float horizontal = Math.abs(ux) / (faceW * 1.35f);
          float bell = horizontal < 0.25f ? horizontal / 0.25f : (1 - horizontal) / 0.75f;
          float shift = -Math.signum(ux) * slim * fe * 0.22f * vertical * Math.max(0, bell);
          nx += shift * cos;
          ny += shift * sin;
        }
        mesh[k++] = nx;
        mesh[k++] = ny;
      }
    }
  }

  private void cheeks(Canvas c, float fx, float fy, float fe, float fa, int color) {
    c.save();
    c.rotate(fa, fx, fy);
    for (int s = -1; s <= 1; s += 2) {
      float cx = fx + s * fe * 0.82f, cy = fy + fe * 0.82f, r = fe * 0.42f;
      shape.setShader(new RadialGradient(cx, cy, r, color, color & 0x00ffffff, Shader.TileMode.CLAMP));
      c.drawCircle(cx, cy, r, shape);
    }
    shape.setShader(null);
    c.restore();
  }

  private void sticker(Canvas c, float x, float y, float e, float a, int tick) {
    c.save();
    c.rotate(a, x, y);
    shape.setShader(null);
    switch (sticker) {
      case "glasses":
        emoji.setTextSize(e * 2.3f);
        c.drawText("🕶", x, y + e * 0.45f, emoji);
        break;
      case "crown":
        emoji.setTextSize(e * 2.2f);
        c.drawText("👑", x, y - e * 1.35f, emoji);
        break;
      case "bunny":
        for (int s = -1; s <= 1; s += 2) {
          c.save();
          c.rotate(s * 12, x + s * e * 0.55f, y - e * 1.2f);
          shape.setColor(0xfffdfdfd);
          c.drawOval(new RectF(x + s * e * 0.55f - e * 0.32f, y - e * 3.1f, x + s * e * 0.55f + e * 0.32f, y - e * 1.15f), shape);
          shape.setColor(0xffffb6c9);
          c.drawOval(new RectF(x + s * e * 0.55f - e * 0.16f, y - e * 2.85f, x + s * e * 0.55f + e * 0.16f, y - e * 1.35f), shape);
          c.restore();
        }
        shape.setColor(0xffff8fab);
        c.drawOval(new RectF(x - e * 0.13f, y + e * 0.62f, x + e * 0.13f, y + e * 0.78f), shape);
        break;
      case "cat":
      case "dog":
        boolean cat = sticker.equals("cat");
        for (int s = -1; s <= 1; s += 2) {
          Path ear = new Path();
          float bx = x + s * e * 0.85f, by = y - e * 1.25f;
          if (cat) {
            ear.moveTo(bx - e * 0.45f, by); ear.lineTo(bx + s * e * 0.1f, by - e * 0.95f); ear.lineTo(bx + e * 0.45f, by); ear.close();
            shape.setColor(0xff3d3a4a); c.drawPath(ear, shape);
            Path inner = new Path();
            inner.moveTo(bx - e * 0.25f, by - e * 0.05f); inner.lineTo(bx + s * e * 0.08f, by - e * 0.65f); inner.lineTo(bx + e * 0.25f, by - e * 0.05f); inner.close();
            shape.setColor(0xffffa3b8); c.drawPath(inner, shape);
          } else {
            shape.setColor(0xff9a6b4a);
            c.save(); c.rotate(s * 25, bx, by);
            c.drawOval(new RectF(bx - e * 0.3f, by - e * 0.4f, bx + e * 0.3f, by + e * 0.9f), shape);
            c.restore();
          }
        }
        shape.setColor(cat ? 0xffff8fab : 0xff3a2a20);
        c.drawOval(new RectF(x - e * (cat ? 0.12f : 0.22f), y + e * 0.55f, x + e * (cat ? 0.12f : 0.22f), y + e * (cat ? 0.68f : 0.8f)), shape);
        if (cat) {
          shape.setColor(0xcc3d3a4a);
          shape.setStrokeWidth(Math.max(2, e * 0.03f));
          for (int s = -1; s <= 1; s += 2) for (int w = -1; w <= 1; w++) c.drawLine(x + s * e * 0.25f, y + e * 0.7f, x + s * e * 0.95f, y + e * (0.62f + w * 0.12f), shape);
        } else {
          shape.setColor(0xffff6f91);
          c.drawOval(new RectF(x - e * 0.14f, y + e * 0.95f, x + e * 0.14f, y + e * 1.35f), shape);
        }
        break;
      case "flowers": {
        String[] f = { "🌸", "🌼", "🌺", "🌷", "🌸", "🌼", "🌺" };
        emoji.setTextSize(e * 0.62f);
        for (int i = 0; i < f.length; i++) {
          double t = Math.PI * (0.12 + 0.76 * i / (f.length - 1));
          c.drawText(f[i], x - (float) Math.cos(t) * e * 1.35f, y - e * 0.95f - (float) Math.sin(t) * e * 0.55f, emoji);
        }
        break;
      }
      case "bow":
        emoji.setTextSize(e * 1.3f);
        c.drawText("🎀", x + e * 0.95f, y - e * 1.2f, emoji);
        break;
      case "freckles":
        shape.setColor(0x996b3f2a);
        java.util.Random r = new java.util.Random(7);
        for (int s = -1; s <= 1; s += 2) for (int i = 0; i < 9; i++) {
          float px = x + s * e * (0.45f + r.nextFloat() * 0.45f), py = y + e * (0.55f + r.nextFloat() * 0.35f);
          c.drawCircle(px, py, Math.max(1.5f, e * (0.025f + r.nextFloat() * 0.02f)), shape);
        }
        cheeks(c, x, y, e, 0, 0x55ff7f9e);
        break;
      case "hearts":
        emoji.setTextSize(e * 0.8f);
        for (int i = 0; i < 6; i++) {
          float phase = ((tick * 0.012f) + i / 6f) % 1f;
          float px = x + (float) Math.sin(i * 1.7 + tick * 0.05) * e * 1.6f;
          float py = y - e * 0.6f - phase * e * 3f;
          emoji.setAlpha(Math.round(255 * (1 - phase)));
          c.drawText("💕", px, py, emoji);
        }
        emoji.setAlpha(255);
        break;
      case "sparkle":
        emoji.setTextSize(e * 0.7f);
        for (int i = 0; i < 6; i++) {
          double t = i * Math.PI / 3 + tick / 25.0;
          emoji.setAlpha(150 + (int) (105 * Math.abs(Math.sin(tick / 8.0 + i))));
          c.drawText("✨", x + (float) Math.cos(t) * e * 2.4f, y + e * 0.3f + (float) Math.sin(t) * e * 2.8f, emoji);
        }
        emoji.setAlpha(255);
        break;
      case "stars":
        emoji.setTextSize(e * 0.55f);
        for (int i = 0; i < 5; i++) {
          double t = i * Math.PI * 2 / 5 + tick / 15.0;
          c.drawText("⭐", x + (float) Math.cos(t) * e * 1.3f, y - e * 1.5f + (float) Math.sin(t) * e * 0.35f, emoji);
        }
        break;
    }
    c.restore();
  }
}
