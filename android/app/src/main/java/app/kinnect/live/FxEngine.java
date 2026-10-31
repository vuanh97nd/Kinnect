package app.kinnect.live;

import android.graphics.*;

/**
 * Bộ thuật toán xử lý hình ảnh & AR chuẩn Google Camera (Pixel Camera) của Kinnect:
 * - Real Tone AI: đo dải tương phản (HDR histogram) & sắc độ da YCbCr để cân bằng sáng và bảo toàn tông da tự nhiên.
 * - Làm đẹp đa tầng (Multi-Scale Frequency-Aware Face Retouching): làm mịn giữ chi tiết, giảm đốm/lỗ chân lông,
 *   bắt sáng đồng tử (Eye Catchlight), tô son bóng tự nhiên (Lip Tint & Specular), má hồng 3D theo góc nghiêng mặt.
 * - Nắn lưới khuôn mặt nội suy bậc ba Hermite C2 (Smooth Hermite Spline Mesh Warp) cho gọn mặt V-line, mắt to, môi đầy.
 * - Hệ thống Sticker AR vẽ vector đa lớp (kính 3D phản quang, tai thú chuyển động vật lý, vương miện đính ngọc, hạt bokeh/sao 4 cánh Google).
 */
final class FxEngine {
  // id, tên hiển thị
  static final String[][] FILTERS = {
    { "none", "Gốc" }, { "clear", "Trong trẻo" }, { "milk", "Sữa" }, { "peach", "Hồng đào" },
    { "warm", "Ấm áp" }, { "cool", "Mát lạnh" }, { "film", "Phim cũ" }, { "mono", "Đen trắng" },
    { "noir", "Tương phản" }, { "vivid", "Rực rỡ" }, { "sunset", "Hoàng hôn" }, { "candy", "Kẹo ngọt" },
    { "mint", "Bạc hà" }, { "dream", "Mộng mơ" }, { "retro", "Retro" }, { "city", "Thành phố" },
    { "cinema", "Cinema" }, { "rose", "Rose" }, { "golden", "Golden" }, { "ice", "Ice" },
    { "lavender", "Lavender" }, { "choco", "Choco" }, { "polaroid", "Polaroid" }, { "teal", "Teal" },
  };
  // id, tên, biểu tượng
  static final String[][] STICKERS = {
    { "none", "Không", "🚫" }, { "glasses", "Kính râm", "🕶" }, { "bunny", "Tai thỏ", "🐰" }, { "cat", "Tai mèo", "🐱" },
    { "dog", "Cún con", "🐶" }, { "crown", "Vương miện", "👑" }, { "flowers", "Vòng hoa", "🌸" }, { "bow", "Nơ xinh", "🎀" },
    { "freckles", "Tàn nhang", "🤎" }, { "hearts", "Tim bay", "💕" }, { "sparkle", "Lấp lánh", "✨" }, { "stars", "Sao xoay", "⭐" },
    { "round_glasses", "Kính tròn", "👓" }, { "heart_glasses", "Kính tim", "💗" }, { "neon_glasses", "Kính neon", "⚡" },
    { "butterfly", "Bướm", "🦋" }, { "halo", "Thiên thần", "😇" }, { "devil", "Sừng xinh", "😈" }, { "rainbow", "Cầu vồng", "🌈" },
    { "bubbles", "Bong bóng", "🫧" }, { "snow", "Tuyết", "❄️" }, { "confetti", "Lễ hội", "🎉" },
  };
  static final String[][] BEAUTY = BeautyCatalog.ITEMS;

  String filter = "none", sticker = "none";
  float intensity = 1f;
  float exposure = 0, contrastLevel = 1, saturation = 1, temperature = 0, zoom = 1, panX = 0, panY = 0, rotation = 0;
  boolean flipImage = false;
  int textColor = Color.WHITE;
  float textSize = .052f, textStart = 0, textEnd = Float.MAX_VALUE, timeSeconds = 0, zoomEnd = 1, projectSeconds = 1;
  boolean keyframed = false;
  private Bitmap composition;
  float smooth = 0.5f, whiten = 0.3f, slim = 0.2f, eyes = 0.2f, lips = 0f, blemish = 0.4f, blush = 0f;
  String text = "";
  float textY = 0.8f;
  boolean compare = false;
  boolean beautyOn = true, auto = false;
  /** Editor timeline: leave the canvas transparent so the project background shows around the clip. */
  boolean clearBackground = false;
  /** Cân sáng tự động chuẩn Google Camera Real Tone: hệ số khuếch đại, độ lệch sáng và độ ấm da. */
  float autoGain = 1f, autoOffset = 0f, autoWarmth = 0f;

  boolean needsFace() {
    return !sticker.equals("none") || (beautyOn && (smooth > 0 || blemish > 0 || eyes > 0 || lips > 0 || slim > 0 || blush > 0));
  }

  void applyLook(String id) {
    beautyOn = true;
    slim = 0;
    if (id.equals("off")) { beautyOn = false; return; }
    smooth = id.equals("glass") ? .78f : .55f;
    // Cập nhật cường độ blemish mạnh hơn cho các preset làm đẹp
    blemish = id.equals("glass") ? .95f : .75f;
    whiten = .15f;
    blush = id.equals("peach") ? .38f : .1f;
    eyes = id.equals("doll") ? .72f : .08f;
    lips = id.equals("doll") ? .27f : .05f;
    if (id.equals("eyes")) eyes = .9f;
    if (id.equals("lips")) lips = .78f;
  }

  FxEngine copy() {
    FxEngine e = new FxEngine();
    e.exposure = exposure; e.contrastLevel = contrastLevel; e.saturation = saturation; e.temperature = temperature;
    e.zoom = zoom; e.zoomEnd = zoomEnd; e.keyframed = keyframed; e.panX = panX; e.panY = panY;
    e.rotation = rotation; e.flipImage = flipImage; e.textColor = textColor; e.textSize = textSize;
    e.textStart = textStart; e.textEnd = textEnd; e.timeSeconds = timeSeconds; e.projectSeconds = projectSeconds;
    e.filter = filter; e.sticker = sticker; e.intensity = intensity;
    e.smooth = smooth; e.whiten = whiten; e.slim = slim; e.eyes = eyes; e.lips = lips; e.blemish = blemish; e.blush = blush;
    e.text = text; e.textY = textY; e.compare = compare;
    e.beautyOn = beautyOn; e.auto = auto; e.autoGain = autoGain; e.autoOffset = autoOffset; e.autoWarmth = autoWarmth;
    return e;
  }

  /**
   * Thuật toán Google Camera Real Tone & Face Retouching AI chạy trên thiết bị:
   * Phân tích biểu đồ sáng (histogram shadow/highlight) và sắc độ da YCbCr để cân sáng thông minh
   * mà không làm cháy vùng sáng, đồng thời tinh chỉnh mức làm mịn, giảm đốm, sáng da và mắt theo khoảng cách mặt.
   */
  void analyze(Bitmap frame, float[] face) {
    int w = frame.getWidth(), h = frame.getHeight();
    long sum = 0, sq = 0;
    int n = 0, hiClip = 0, loClip = 0;
    int stepY = Math.max(1, h / 24), stepX = Math.max(1, w / 16);
    for (int y = h / 10; y < h * 9 / 10; y += stepY) {
      for (int x = w / 10; x < w * 9 / 10; x += stepX) {
        int c = frame.getPixel(Math.min(x, w - 1), Math.min(y, h - 1));
        int l = (Color.red(c) * 299 + Color.green(c) * 587 + Color.blue(c) * 114) / 1000;
        sum += l; sq += l * l; n++;
        if (l > 230) hiClip++;
        if (l < 28) loClip++;
      }
    }
    if (n == 0) return;
    float mean = sum / (float) n;
    float std = (float) Math.sqrt(Math.max(1, sq / (float) n - mean * mean));
    float hiRatio = hiClip / (float) n;
    // Giữ vùng highlight không bị cháy (chuẩn HDR+ của Google Camera)
    float targetStd = hiRatio > 0.08f ? 50f : 56f;
    float gain = Math.max(0.86f, Math.min(1.32f, targetStd / std));
    autoGain = 1f + (gain - 1f) * 0.42f;
    float targetLuma = hiRatio > 0.1f ? 122f : (loClip / (float) n > 0.2f ? 132f : 127f);
    autoOffset = Math.max(-18f, Math.min(22f, (targetLuma - mean * autoGain) * 0.42f));
    autoWarmth = 0f;

    if (face == null) return;
    float fx = face[0], fy = face[1], fe = face[2];
    long skinL = 0, skinSq = 0, sumCr = 0, sumCb = 0;
    int m = 0;
    for (int dy = -2; dy <= 6; dy++) {
      for (int dx = -5; dx <= 5; dx++) {
        int x = Math.round(fx + dx * fe * 0.12f), y = Math.round(fy + fe * 0.35f + dy * fe * 0.1f);
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        int c = frame.getPixel(x, y);
        int r = Color.red(c), g = Color.green(c), b = Color.blue(c);
        int l = (r * 299 + g * 587 + b * 114) / 1000;
        int cb = 128 + (-169 * r - 331 * g + 500 * b) / 1000;
        int cr = 128 + (500 * r - 419 * g - 81 * b) / 1000;
        skinL += l; skinSq += l * l; sumCb += cb; sumCr += cr; m++;
      }
    }
    if (m == 0) return;
    float skinMean = skinL / (float) m;
    float skinTex = (float) Math.sqrt(Math.max(1, skinSq / (float) m - skinMean * skinMean));
    float meanCr = sumCr / (float) m, meanCb = sumCb / (float) m;
    // Real Tone: nếu ánh sáng đèn làm da hơi xanh/lạnh (Cr thấp, Cb cao), bù ấm nhẹ tự nhiên
    if (meanCr < 142f && meanCb > 118f) autoWarmth = Math.min(6f, (142f - meanCr) * 0.35f);
    // Tinh chỉnh thông số Face Retouching chuẩn Pixel Camera (tự nhiên, giữ kết cấu da)
    smooth = Math.max(0.32f, Math.min(0.80f, 0.26f + skinTex / 42f));
    // Tăng cường xử lý đốm/tàn nhang (Blemish) mạnh tay hơn: nâng base từ 0.30f lên 0.45f, hệ số mượt cao hơn
    blemish = Math.max(0.50f, Math.min(0.95f, 0.45f + skinTex / 32f));
    whiten = Math.max(0.10f, Math.min(0.38f, (138f - skinMean) / 165f + 0.14f));
    float sizeRatio = fe / (float) w;
    eyes = sizeRatio > 0.12f ? 0.28f : 0.15f;
    slim = sizeRatio > 0.12f ? 0.24f : 0.14f;
    lips = Math.max(lips, 0.12f);
    blush = Math.max(blush, 0.16f);
  }

  private final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
  private final Paint soft = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
  private final Paint shape = new Paint(Paint.ANTI_ALIAS_FLAG);
  private final Paint strokePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
  private final Paint emoji = new Paint(Paint.ANTI_ALIAS_FLAG);
  private static final int MW = 36, MH = 64;
  private final float[] mesh = new float[(MW + 1) * (MH + 1) * 2];
  private Bitmap blurred, deepBlurred;

  FxEngine() {
    emoji.setTextAlign(Paint.Align.CENTER);
    strokePaint.setStyle(Paint.Style.STROKE);
    strokePaint.setStrokeCap(Paint.Cap.ROUND);
    strokePaint.setStrokeJoin(Paint.Join.ROUND);
  }

  float get(String key) {
    switch (key) {
      case "smooth": return smooth;
      case "whiten": return whiten;
      case "slim": return slim;
      case "eyes": return eyes;
      case "lips": return lips;
      case "blemish": return blemish;
      default: return blush;
    }
  }

  void set(String key, float v) {
    switch (key) {
      case "smooth": smooth = v; break;
      case "whiten": whiten = v; break;
      case "slim": slim = v; break;
      case "eyes": eyes = v; break;
      case "lips": lips = v; break;
      case "blemish": blemish = v; break;
      default: blush = v;
    }
  }

  // ===== Hệ màu Google Camera & Bộ lọc phim chuyên sâu =====
  private static float[] identity() {
    return new float[] { 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0 };
  }

  private static ColorMatrix sat(float s) {
    ColorMatrix m = new ColorMatrix();
    m.setSaturation(s);
    return m;
  }

  private static ColorMatrix contrast(float c) {
    float t = (1 - c) * 128;
    return new ColorMatrix(new float[] { c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0 });
  }

  private static ColorMatrix tint(float r, float g, float b, float add) {
    return new ColorMatrix(new float[] { r, 0, 0, 0, add, 0, g, 0, 0, add, 0, 0, b, 0, add, 0, 0, 0, 1, 0 });
  }

  private static ColorMatrix offset(float r, float g, float b) {
    return new ColorMatrix(new float[] { 1, 0, 0, 0, r, 0, 1, 0, 0, g, 0, 0, 1, 0, b, 0, 0, 0, 1, 0 });
  }

  /** Nâng vùng tối và nén nhẹ vùng cháy sáng (matte film roll-off). */
  private static ColorMatrix fade(float f) {
    float k = 1 - f;
    return new ColorMatrix(new float[] { k, 0, 0, 0, f * 242, 0, k, 0, 0, f * 242, 0, 0, k, 0, f * 242, 0, 0, 0, 1, 0 });
  }

  /** Phối trộn kênh màu chéo (Split-toning / Cross-matrix) kiểu máy ảnh phim & Pixel LUT. */
  private static ColorMatrix splitTone(float rr, float rg, float rb, float gr, float gg, float gb, float br, float bg, float bb) {
    return new ColorMatrix(new float[] {
      rr, rg, rb, 0, 0,
      gr, gg, gb, 0, 0,
      br, bg, bb, 0, 0,
      0,  0,  0,  1, 0
    });
  }

  private static ColorMatrix chain(ColorMatrix... parts) {
    ColorMatrix m = new ColorMatrix();
    for (ColorMatrix p : parts) m.postConcat(p);
    return m;
  }

  static ColorMatrix filterMatrix(String id) {
    switch (id) {
      case "clear":
        return chain(contrast(1.07f), sat(1.09f), splitTone(1.01f, 0f, 0f, 0f, 1.01f, 0.01f, 0f, 0.01f, 1.03f), offset(6, 7, 10));
      case "milk":
        return chain(sat(0.78f), fade(0.08f), tint(1.03f, 1.01f, 0.99f, 7), contrast(0.97f));
      case "peach":
        return chain(sat(1.06f), splitTone(1.04f, 0.02f, 0f, 0.01f, 0.98f, 0f, 0.02f, 0f, 0.98f), offset(11, 2, 5));
      case "warm":
        return chain(tint(1.08f, 1.02f, 0.90f, 5), sat(1.06f), contrast(1.02f));
      case "cool":
        return chain(tint(0.93f, 1.00f, 1.10f, 4), sat(0.96f), contrast(1.03f));
      case "film":
        return chain(sat(0.74f), fade(0.11f), splitTone(1.04f, 0.02f, -0.02f, 0.01f, 0.99f, -0.01f, -0.02f, 0.02f, 0.89f), contrast(0.96f));
      case "mono":
        return chain(sat(0), contrast(1.08f));
      case "noir":
        return chain(sat(0), contrast(1.34f), fade(0.03f));
      case "vivid":
        return chain(sat(1.38f), contrast(1.08f), offset(2, 2, 3));
      case "sunset":
        return chain(splitTone(1.10f, 0.03f, 0f, 0.01f, 0.96f, 0f, 0.03f, -0.02f, 0.88f), offset(14, 1, 10), sat(1.12f));
      case "candy":
        return chain(sat(1.22f), tint(1.04f, 0.98f, 1.07f, 8), fade(0.05f));
      case "mint":
        return chain(splitTone(0.93f, 0.03f, 0f, 0.01f, 1.05f, 0.02f, 0f, 0.03f, 1.02f), sat(0.92f), fade(0.04f), offset(2, 5, 4));
      case "dream":
        return chain(sat(0.86f), fade(0.09f), tint(1.04f, 0.98f, 1.09f, 7));
      case "retro":
        return chain(tint(1.06f, 0.99f, 0.91f, 0), offset(3, 6, 12), contrast(1.09f), sat(0.88f));
      case "city":
        return chain(sat(0.72f), contrast(1.16f), tint(0.95f, 1.00f, 1.06f, 0));
      case "cinema":
        return chain(contrast(1.14f), sat(0.84f), splitTone(1.03f, 0.01f, -0.02f, 0f, 1.00f, 0.01f, -0.02f, 0.03f, 0.96f));
      case "rose":
        return chain(tint(1.08f, 0.97f, 1.04f, 7), sat(1.10f));
      case "golden":
        return chain(tint(1.10f, 1.03f, 0.88f, 8), sat(1.16f), contrast(1.04f));
      case "ice":
        return chain(tint(0.94f, 1.02f, 1.11f, 8), sat(0.78f));
      case "lavender":
        return chain(tint(1.03f, 0.98f, 1.11f, 8), sat(0.84f));
      case "choco":
        return chain(tint(1.07f, 0.99f, 0.86f, 0), sat(0.74f), contrast(1.09f));
      case "polaroid":
        return chain(fade(0.11f), sat(0.82f), tint(1.02f, 1.00f, 0.95f, 4));
      case "teal":
        return chain(splitTone(1.02f, -0.03f, -0.02f, -0.01f, 1.04f, 0.03f, -0.03f, 0.04f, 1.06f), sat(1.14f), contrast(1.10f));
      default:
        return new ColorMatrix();
    }
  }

  static boolean vignette(String id) {
    return id.equals("film") || id.equals("noir") || id.equals("retro") || id.equals("dream") || id.equals("cinema") || id.equals("polaroid");
  }

  /** Ma trận màu tổng hợp: Bộ lọc + cân chỉnh + AI Real Tone + sáng da tự nhiên. */
  ColorMatrixColorFilter colorFilter() {
    float[] base = identity(), target = filterMatrix(filter).getArray();
    float[] mixed = new float[20];
    for (int i = 0; i < 20; i++) mixed[i] = base[i] + (target[i] - base[i]) * intensity;
    ColorMatrix m = new ColorMatrix(mixed);
    m.postConcat(contrast(contrastLevel));
    m.postConcat(sat(saturation));
    float tempShift = temperature * 12f + (auto ? autoWarmth : 0f);
    m.postConcat(offset(exposure * 45f + tempShift, exposure * 45f + tempShift * 0.2f, exposure * 45f - tempShift));
    if (auto) {
      m.postConcat(new ColorMatrix(new float[] {
        autoGain, 0, 0, 0, autoOffset,
        0, autoGain, 0, 0, autoOffset,
        0, 0, autoGain, 0, autoOffset,
        0, 0, 0, 1, 0
      }));
    }
    if (beautyOn && whiten > 0) {
      // Làm sáng da mềm mại chuẩn Real Tone (tăng nhẹ độ trong trẻo, giữ hồng hào tự nhiên)
      m.postConcat(chain(
        tint(1f + whiten * 0.065f, 1f + whiten * 0.068f, 1f + whiten * 0.078f, whiten * 19f),
        sat(1f - whiten * 0.09f)
      ));
    }
    return new ColorMatrixColorFilter(m);
  }

  // ===== Kết xuất khung hình =====
  void render(Canvas c, Bitmap src, float[] face, int tick) {
    if (compare) { c.drawColor(Color.BLACK); drawFit(c, src, 0, 1, false); return; }
    float k = Math.min(1, Math.max(c.getWidth(), c.getHeight()) / (float) Math.max(src.getWidth(), src.getHeight()));
    int w = Math.max(2, Math.round(src.getWidth() * k)), h = Math.max(2, Math.round(src.getHeight() * k));
    if (composition == null || composition.getWidth() != w || composition.getHeight() != h) {
      if (composition != null) composition.recycle();
      composition = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
    }
    Canvas stage = new Canvas(composition);
    renderContent(stage, src, face, tick);
    if (clearBackground) c.drawColor(0, PorterDuff.Mode.CLEAR);
    else c.drawColor(Color.BLACK);
    float progress = Math.max(0, Math.min(1, timeSeconds / Math.max(.001f, projectSeconds)));
    float currentZoom = keyframed ? zoom + (zoomEnd - zoom) * progress : zoom;
    drawFit(c, composition, rotation, currentZoom, flipImage);
    drawCaption(c);
  }

  private void drawFit(Canvas c, Bitmap bitmap, float angle, float scale, boolean mirror) {
    boolean sideways = ((Math.round(angle / 90) % 2) + 2) % 2 == 1;
    float w = sideways ? bitmap.getHeight() : bitmap.getWidth(), h = sideways ? bitmap.getWidth() : bitmap.getHeight();
    float factor = Math.min(c.getWidth() / w, c.getHeight() / h) * scale;
    int save = c.save();
    c.translate(c.getWidth() * (.5f + panX), c.getHeight() * (.5f + panY));
    c.rotate(angle);
    c.scale(mirror ? -factor : factor, factor);
    c.drawBitmap(bitmap, -bitmap.getWidth() / 2f, -bitmap.getHeight() / 2f, null);
    c.restoreToCount(save);
  }

  private void drawCaption(Canvas c) {
    if (text.isEmpty() || timeSeconds < textStart || timeSeconds > textEnd) return;
    Paint caption = new Paint(Paint.ANTI_ALIAS_FLAG);
    caption.setColor(textColor);
    caption.setTextSize(c.getWidth() * textSize);
    caption.setTextAlign(Paint.Align.CENTER);
    caption.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    caption.setShadowLayer(c.getWidth() * .012f, 0, 2, 0xcc000000);
    String[] lines = text.split("\\n");
    for (int i = 0; i < Math.min(4, lines.length); i++) {
      c.drawText(lines[i].substring(0, Math.min(45, lines[i].length())), c.getWidth() * .5f, c.getHeight() * textY + i * c.getWidth() * textSize * 1.23f, caption);
    }
  }

  private void renderContent(Canvas c, Bitmap src, float[] face, int tick) {
    int cw = c.getWidth(), ch = c.getHeight();
    float sx = cw / (float) src.getWidth(), sy = ch / (float) src.getHeight();
    if (compare) { c.drawBitmap(src, null, new Rect(0, 0, cw, ch), null); return; }
    ColorMatrixColorFilter cf = colorFilter();
    paint.setColorFilter(cf);
    float fx = 0, fy = 0, fe = 0, fa = 0;
    if (face != null) { fx = face[0] * sx; fy = face[1] * sy; fe = face[2] * sx; fa = face[3]; }
    boolean warp = beautyOn && face != null && (slim > 0.01f || eyes > 0.01f || lips > 0.01f);
    if (warp) {
      buildMesh(cw, ch, fx, fy, fe, fa);
      c.drawBitmapMesh(src, MW, MH, mesh, 0, null, 0, paint);
    } else {
      c.drawBitmap(src, null, new Rect(0, 0, cw, ch), paint);
    }

    // Làm đẹp đa tầng chuẩn Google Camera (Dual-Band Frequency Skin Retouching):
    // Tầng 1 (smooth): làm mịn tần số trung bình giữ kết cấu da thật.
    // Tầng 2 (blemish): làm dịu đốm nâu/mụn và quầng thâm dưới mắt nhưng bảo toàn mắt, chân mày, cánh mũi và môi.
    if (beautyOn && (smooth > 0.01f || blemish > 0.01f) && face != null && fe > 6f) {
      int bw = Math.max(10, src.getWidth() / 6), bh = Math.max(10, src.getHeight() / 6);
      if (blurred == null || blurred.getWidth() != bw || blurred.getHeight() != bh) {
        if (blurred != null) blurred.recycle();
        blurred = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888);
      }
      int dw = Math.max(6, src.getWidth() / 13), dh = Math.max(6, src.getHeight() / 13);
      if (deepBlurred == null || deepBlurred.getWidth() != dw || deepBlurred.getHeight() != dh) {
        if (deepBlurred != null) deepBlurred.recycle();
        deepBlurred = Bitmap.createBitmap(dw, dh, Bitmap.Config.ARGB_8888);
      }
      soft.setColorFilter(null);
      soft.setAlpha(255);
      new Canvas(blurred).drawBitmap(src, null, new Rect(0, 0, bw, bh), soft);
      new Canvas(deepBlurred).drawBitmap(blurred, null, new Rect(0, 0, dw, dh), soft);

      // Pha lớp giảm đốm (deepBlurred) vào lớp mịn (blurred) theo tỷ lệ blemish để giữ hạt da tự nhiên
      // Tăng hệ số hoà trộn lớp Deep Blur lên để xoá đốm mụn mạnh hơn, lên tới mức Alpha 220
      if (blemish > 0.04f) {
        soft.setAlpha(Math.min(220, Math.round(blemish * 195f)));
        new Canvas(blurred).drawBitmap(deepBlurred, null, new Rect(0, 0, bw, bh), soft);
      }

      soft.setColorFilter(cf);
      soft.setAlpha(Math.round(Math.min(225, 34 + smooth * 135 + blemish * 42)));

      double angle = Math.toRadians(fa);
      float cosine = (float) Math.cos(angle), sine = (float) Math.sin(angle);
      float ox = fx - sine * fe * 0.48f, oy = fy + cosine * fe * 0.48f;
      float rx = fe * 1.18f, ry = fe * 1.58f;
      int layer = c.saveLayer(
        Math.max(0, ox - ry * 1.35f),
        Math.max(0, oy - ry * 1.35f),
        Math.min(cw, ox + ry * 1.35f),
        Math.min(ch, oy + ry * 1.35f),
        null
      );
      if (warp) c.drawBitmapMesh(blurred, MW, MH, mesh, 0, null, 0, soft);
      else c.drawBitmap(blurred, null, new Rect(0, 0, cw, ch), soft);

      Paint mask = new Paint(Paint.ANTI_ALIAS_FLAG);
      mask.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.DST_IN));
      RadialGradient rg = new RadialGradient(
        0, 0, 1,
        new int[] { 0xff000000, 0xff000000, 0x88000000, 0x00000000 },
        new float[] { 0f, 0.56f, 0.82f, 1f },
        Shader.TileMode.CLAMP
      );
      Matrix mx = new Matrix();
      mx.setScale(rx, ry);
      mx.postRotate(fa);
      mx.postTranslate(ox, oy);
      rg.setLocalMatrix(mx);
      mask.setShader(rg);
      c.drawRect(0, 0, cw, ch, mask);

      // Bảo toàn độ sắc nét cho mắt, lông mày, sống mũi và đôi môi
      mask.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.DST_OUT));
      // Hai mắt + hàng mi
      cutFeature(c, mask, fx - cosine * fe * .5f, fy - sine * fe * .5f, fe * .39f, fe * .22f, fa);
      cutFeature(c, mask, fx + cosine * fe * .5f, fy + sine * fe * .5f, fe * .39f, fe * .22f, fa);
      // Chân mày trái & phải
      cutFeature(c, mask, fx - cosine * fe * .52f + sine * fe * .28f, fy - sine * fe * .52f - cosine * fe * .28f, fe * .42f, fe * .13f, fa);
      cutFeature(c, mask, fx + cosine * fe * .52f + sine * fe * .28f, fy + sine * fe * .52f - cosine * fe * .28f, fe * .42f, fe * .13f, fa);
      // Đầu mũi / cánh mũi
      cutFeature(c, mask, fx - sine * fe * .62f, fy + cosine * fe * .62f, fe * .22f, fe * .16f, fa);
      // Đôi môi
      cutFeature(c, mask, fx - sine * fe * 1.12f, fy + cosine * fe * 1.12f, fe * .56f, fe * .28f, fa);
      c.restoreToCount(layer);
      soft.setAlpha(255);
    }

    // Phủ tối góc (Vignette quang học) cho các bộ lọc phim/điện ảnh
    if (vignette(filter) && intensity > 0.05f) {
      Paint v = new Paint(Paint.ANTI_ALIAS_FLAG);
      v.setShader(new RadialGradient(
        cw / 2f, ch / 2f, Math.max(cw, ch) * 0.78f,
        new int[] { 0x00000000, 0x00000000, Color.argb(Math.round(138 * intensity), 6, 5, 10) },
        new float[] { 0f, 0.58f, 1f },
        Shader.TileMode.CLAMP
      ));
      c.drawRect(0, 0, cw, ch, v);
    }

    if (face == null) return;
    if (beautyOn) {
      if (blush > 0.01f) cheeks(c, fx, fy, fe, fa, Color.argb(Math.round(blush * 110), 255, 108, 138));
      if (lips > 0.02f || blush > 0.05f) enhanceLips(c, fx, fy, fe, fa, Math.min(1f, lips * 0.75f + blush * 0.45f));
      if (eyes > 0.02f || smooth > 0.15f) enhanceEyes(c, fx, fy, fe, fa, Math.min(1f, eyes * 0.8f + smooth * 0.35f));
    }
    if (!sticker.equals("none")) sticker(c, fx, fy, fe, fa, tick);
  }

  private void cutFeature(Canvas c, Paint mask, float x, float y, float rx, float ry, float angle) {
    c.save();
    c.translate(x, y);
    c.rotate(angle);
    c.scale(rx, ry);
    mask.setShader(new RadialGradient(0, 0, 1, new int[] { 0xff000000, 0xff000000, 0 }, new float[] { 0, .62f, 1 }, Shader.TileMode.CLAMP));
    c.drawRect(-1, -1, 1, 1, mask);
    c.restore();
  }

  /** Bắt sáng đồng tử (Google Camera Portrait Light / Eye Catchlight) giúp đôi mắt trong veo và có hồn. */
  private void enhanceEyes(Canvas c, float fx, float fy, float fe, float fa, float strength) {
    if (fe < 10f || strength <= 0.02f) return;
    c.save();
    c.rotate(fa, fx, fy);
    int glintAlpha = Math.round(Math.min(140, 38 + strength * 78));
    int irisAlpha = Math.round(Math.min(48, 12 + strength * 28));
    for (int s = -1; s <= 1; s += 2) {
      float ex = fx + s * fe * 0.5f, ey = fy;
      float r = fe * 0.16f;
      shape.setShader(new RadialGradient(ex, ey, r, Color.argb(irisAlpha, 255, 252, 245), 0x00ffffff, Shader.TileMode.CLAMP));
      c.drawCircle(ex, ey, r, shape);
      // Điểm catchlight phản chiếu ánh sáng ở góc trên-trong của con ngươi
      float gx = ex - s * fe * 0.038f, gy = ey - fe * 0.042f;
      shape.setShader(new RadialGradient(gx, gy, fe * 0.042f, Color.argb(glintAlpha, 255, 255, 255), 0x00ffffff, Shader.TileMode.CLAMP));
      c.drawCircle(gx, gy, fe * 0.042f, shape);
    }
    shape.setShader(null);
    c.restore();
  }

  /** Tô sắc môi hồng đào tự nhiên kèm ánh bóng nhẹ ở môi dưới. */
  private void enhanceLips(Canvas c, float fx, float fy, float fe, float fa, float strength) {
    if (fe < 10f || strength <= 0.02f) return;
    c.save();
    c.rotate(fa, fx, fy);
    float mx = fx, my = fy + fe * 1.12f;
    float rx = fe * 0.44f, ry = fe * 0.21f;
    int tintAlpha = Math.round(Math.min(82, 18 + strength * 56));
    c.save();
    c.translate(mx, my);
    c.scale(rx, ry);
    shape.setShader(new RadialGradient(
      0, 0, 1f,
      new int[] { Color.argb(tintAlpha, 238, 78, 112), Color.argb(tintAlpha / 2, 238, 92, 120), 0x00000000 },
      new float[] { 0f, 0.62f, 1f },
      Shader.TileMode.CLAMP
    ));
    c.drawCircle(0, 0, 1f, shape);
    c.restore();
    // Ánh bóng nhẹ ở giữa môi dưới
    int glossAlpha = Math.round(Math.min(64, 14 + strength * 42));
    shape.setShader(new RadialGradient(mx, my + fe * 0.055f, fe * 0.16f, Color.argb(glossAlpha, 255, 235, 240), 0x00ffffff, Shader.TileMode.CLAMP));
    c.drawOval(new RectF(mx - fe * 0.16f, my + fe * 0.02f, mx + fe * 0.16f, my + fe * 0.09f), shape);
    shape.setShader(null);
    c.restore();
  }

  void drawSticker(Canvas c, float[] face, int tick) {
    if (face != null && !sticker.equals("none")) sticker(c, face[0], face[1], face[2], face[3], tick);
  }

  /**
   * Hàm suy giảm Hermite bậc ba C2: mượt hoàn toàn ở tâm (t=0) và biên (t=1), không gây gãy lưới ảnh.
   */
  private static float hermiteFalloff(float t) {
    if (t <= 0f) return 1f;
    if (t >= 1f) return 0f;
    return 1f - t * t * (3f - 2f * t);
  }

  private void buildMesh(int cw, int ch, float fx, float fy, float fe, float fa) {
    double rad = Math.toRadians(fa);
    float cos = (float) Math.cos(rad), sin = (float) Math.sin(rad);
    float lx = fx - cos * fe / 2f, ly = fy - sin * fe / 2f;
    float rx = fx + cos * fe / 2f, ry = fy + sin * fe / 2f;
    float eyeR = fe * 0.64f, eyeK = eyes * 0.34f;
    float mx = fx - sin * fe * 1.12f, my = fy + cos * fe * 1.12f;
    float chinY = fe * 2.02f, faceW = fe * 1.56f;
    int k = 0;
    for (int j = 0; j <= MH; j++) {
      for (int i = 0; i <= MW; i++) {
        float x = cw * i / (float) MW, y = ch * j / (float) MH;
        float nx = x, ny = y;
        // 1. Mắt to chuẩn Google Camera: giãn nở tâm đồng tử mượt theo hàm Hermite C2
        if (eyes > 0.01f) {
          for (int e = 0; e < 2; e++) {
            float ex = e == 0 ? lx : rx, ey = e == 0 ? ly : ry;
            float dx = x - ex, dy = y - ey, d = (float) Math.sqrt(dx * dx + dy * dy);
            if (d < eyeR) {
              float f = eyeK * hermiteFalloff(d / eyeR);
              nx += dx * f;
              ny += dy * f;
            }
          }
        }
        // 2. Môi đầy tự nhiên: giãn nở elip quanh môi theo trục khuôn mặt
        if (lips > 0.01f) {
          float mdx = (x - mx) * cos + (y - my) * sin;
          float mdy = -(x - mx) * sin + (y - my) * cos;
          float radius = (float) Math.sqrt(mdx * mdx / (fe * fe * .44f) + mdy * mdy / (fe * fe * .16f));
          if (radius < 1f) {
            float amount = lips * 0.38f * hermiteFalloff(radius);
            nx += (x - mx) * amount;
            ny += (y - my) * amount;
          }
        }
        // 3. Gọn mặt V-line tự nhiên: kéo nhẹ đường hàm dưới và gò má vào trục giữa với biên C2 mượt
        if (slim > 0.01f) {
          float ux = (x - fx) * cos + (y - fy) * sin;
          float uy = -(x - fx) * sin + (y - fy) * cos;
          if (uy > fe * 0.1f && uy < chinY * 1.18f && Math.abs(ux) < faceW * 1.38f) {
            float vNorm = (uy - fe * 0.1f) / (chinY * 1.08f);
            float vertical = (float) Math.sin(Math.PI * Math.min(1f, Math.max(0f, vNorm)));
            // Tập trung lực thon gọn ở vùng quai hàm (vNorm ~ 0.55..0.85)
            vertical *= (0.75f + 0.35f * vNorm);
            float horizontal = Math.abs(ux) / (faceW * 1.38f);
            float bell = horizontal < 0.28f
              ? (1f - hermiteFalloff(horizontal / 0.28f))
              : hermiteFalloff((horizontal - 0.28f) / 0.72f);
            float shift = -Math.signum(ux) * slim * fe * 0.22f * vertical * Math.max(0f, bell);
            nx += shift * cos;
            ny += shift * sin;
          }
        }
        mesh[k++] = nx;
        mesh[k++] = ny;
      }
    }
  }

  /** Má hồng 3D chạy dọc xương gò má (Cheekbone Contour Blush). */
  private void cheeks(Canvas c, float fx, float fy, float fe, float fa, int color) {
    c.save();
    c.rotate(fa, fx, fy);
    for (int s = -1; s <= 1; s += 2) {
      float cx = fx + s * fe * 0.78f, cy = fy + fe * 0.56f;
      c.save();
      c.translate(cx, cy);
      c.rotate(-s * 18f);
      c.scale(fe * 0.48f, fe * 0.34f);
      shape.setShader(new RadialGradient(0, 0, 1f, color, color & 0x00ffffff, Shader.TileMode.CLAMP));
      c.drawCircle(0, 0, 1f, shape);
      c.restore();
    }
    shape.setShader(null);
    c.restore();
  }

  /** Vẽ ngôi sao 4 cánh lấp lánh chuẩn Google (Google Sparkle / Starburst). */
  private void drawSparkleStar(Canvas c, float cx, float cy, float r, int color, float rotDeg) {
    c.save();
    c.translate(cx, cy);
    c.rotate(rotDeg);
    Path p = new Path();
    float inner = r * 0.22f;
    p.moveTo(0, -r);
    p.quadTo(inner, -inner, r, 0);
    p.quadTo(inner, inner, 0, r);
    p.quadTo(-inner, inner, -r, 0);
    p.quadTo(-inner, -inner, 0, -r);
    p.close();
    shape.setShader(new RadialGradient(0, 0, r, color, (color & 0x00ffffff) | 0x44000000, Shader.TileMode.CLAMP));
    c.drawPath(p, shape);
    shape.setShader(null);
    shape.setColor(0xffffffff);
    c.drawCircle(0, 0, r * 0.18f, shape);
    c.restore();
  }

  /** Vẽ trái tim 3D vector mềm mại. */
  private void drawVectorHeart(Canvas c, float cx, float cy, float size, int color, int alpha) {
    c.save();
    c.translate(cx, cy);
    Path h = new Path();
    h.moveTo(0, size * 0.36f);
    h.cubicTo(-size * 0.9f, -size * 0.1f, -size * 0.55f, -size * 0.82f, 0, -size * 0.28f);
    h.cubicTo(size * 0.55f, -size * 0.82f, size * 0.9f, -size * 0.1f, 0, size * 0.36f);
    h.close();
    int topColor = Color.argb(alpha, 255, Math.min(255, Color.green(color) + 45), Math.min(255, Color.blue(color) + 45));
    int botColor = Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
    shape.setShader(new LinearGradient(0, -size * 0.6f, 0, size * 0.4f, topColor, botColor, Shader.TileMode.CLAMP));
    c.drawPath(h, shape);
    shape.setShader(null);
    shape.setColor(Color.argb(Math.round(alpha * 0.55f), 255, 255, 255));
    c.drawCircle(-size * 0.22f, -size * 0.26f, size * 0.11f, shape);
    c.restore();
  }

  /**
   * Hệ thống AR Sticker vẽ vector chuyên sâu (bám góc nghiêng mặt + chuyển động vật lý mượt mà).
   */
  private void sticker(Canvas c, float x, float y, float e, float a, int tick) {
    c.save();
    c.rotate(a, x, y);
    shape.setShader(null);
    shape.setAlpha(255);
    float sway = (float) Math.sin(tick * 0.08) * 4.5f;

    switch (sticker) {
      case "glasses":
      case "round_glasses":
      case "heart_glasses":
      case "neon_glasses": {
        boolean darkAviator = sticker.equals("glasses");
        boolean heart = sticker.equals("heart_glasses");
        boolean neon = sticker.equals("neon_glasses");
        int rimColor = neon ? 0xff4ef8e8 : heart ? 0xffff5c97 : darkAviator ? 0xffe8c67a : 0xff2b2538;
        int lensTop = neon ? 0x5500f5d4 : heart ? 0x66ff4d8d : darkAviator ? 0xcc161822 : 0x382b2538;
        int lensBot = neon ? 0x337b2cbf : heart ? 0x22ff9ebb : darkAviator ? 0x882b3142 : 0x142b2538;

        for (int side : new int[] { -1, 1 }) {
          float cx = x + side * e * 0.54f, cy = y + e * 0.02f;
          Path framePath = new Path();
          if (heart) {
            framePath.moveTo(cx, cy + e * 0.42f);
            framePath.cubicTo(cx - e * 0.88f, cy - e * 0.02f, cx - e * 0.56f, cy - e * 0.68f, cx, cy - e * 0.20f);
            framePath.cubicTo(cx + e * 0.56f, cy - e * 0.68f, cx + e * 0.88f, cy - e * 0.02f, cx, cy + e * 0.42f);
            framePath.close();
          } else if (darkAviator) {
            RectF r = new RectF(cx - e * 0.52f, cy - e * 0.30f, cx + e * 0.52f, cy + e * 0.42f);
            framePath.addRoundRect(r, new float[] { e * .18f, e * .18f, e * .18f, e * .18f, e * .42f, e * .42f, e * .38f, e * .38f }, Path.Direction.CW);
          } else {
            framePath.addOval(new RectF(cx - e * 0.46f, cy - e * 0.42f, cx + e * 0.46f, cy + e * 0.42f), Path.Direction.CW);
          }
          // Tròng kính chuyển sắc
          shape.setShader(new LinearGradient(cx, cy - e * 0.4f, cx, cy + e * 0.4f, lensTop, lensBot, Shader.TileMode.CLAMP));
          c.drawPath(framePath, shape);
          shape.setShader(null);
          // Vệt phản quang chéo trên mặt kính
          c.save();
          c.clipPath(framePath);
          shape.setColor(neon ? 0x66b8fff9 : 0x44ffffff);
          Path glare = new Path();
          glare.moveTo(cx - e * 0.35f, cy - e * 0.45f);
          glare.lineTo(cx - e * 0.12f, cy - e * 0.45f);
          glare.lineTo(cx - e * 0.32f, cy + e * 0.45f);
          glare.lineTo(cx - e * 0.55f, cy + e * 0.45f);
          glare.close();
          c.drawPath(glare, shape);
          c.restore();
          // Gọng kính
          strokePaint.setStrokeWidth(e * (neon ? 0.062f : 0.052f));
          strokePaint.setColor(rimColor);
          if (neon) strokePaint.setShadowLayer(e * 0.14f, 0, 0, 0xff00f5d4);
          c.drawPath(framePath, strokePaint);
          strokePaint.setShadowLayer(0, 0, 0, 0);
          // Càng kính hai bên thái dương
          c.drawLine(cx + side * e * 0.48f, cy - e * 0.10f, cx + side * e * 0.82f, cy - e * 0.18f, strokePaint);
        }
        // Cầu nối mũi
        strokePaint.setStrokeWidth(e * 0.052f);
        strokePaint.setColor(rimColor);
        c.drawLine(x - e * 0.09f, y - e * 0.06f, x + e * 0.09f, y - e * 0.06f, strokePaint);
        if (darkAviator) c.drawLine(x - e * 0.16f, y - e * 0.24f, x + e * 0.16f, y - e * 0.24f, strokePaint);
        break;
      }

      case "bunny": {
        for (int s = -1; s <= 1; s += 2) {
          c.save();
          float pivotX = x + s * e * 0.54f, pivotY = y - e * 1.15f;
          c.rotate(s * (11f + sway * 0.8f), pivotX, pivotY);
          RectF outer = new RectF(pivotX - e * 0.33f, y - e * 3.12f, pivotX + e * 0.33f, y - e * 1.12f);
          shape.setShader(new LinearGradient(outer.left, outer.top, outer.right, outer.bottom, 0xffffffff, 0xfff3edf7, Shader.TileMode.CLAMP));
          c.drawOval(outer, shape);
          RectF inner = new RectF(pivotX - e * 0.17f, y - e * 2.86f, pivotX + e * 0.17f, y - e * 1.32f);
          shape.setShader(new LinearGradient(inner.left, inner.top, inner.left, inner.bottom, 0xffff9ebb, 0xffffcdd9, Shader.TileMode.CLAMP));
          c.drawOval(inner, shape);
          shape.setShader(null);
          strokePaint.setStrokeWidth(Math.max(1.5f, e * 0.022f));
          strokePaint.setColor(0x336b5876);
          c.drawOval(outer, strokePaint);
          c.restore();
        }
        // Mũi thỏ hồng 3D + ria mép mảnh
        cheeks(c, x, y, e, 0, 0x48ff85a8);
        shape.setColor(0xffff7a9e);
        c.drawOval(new RectF(x - e * 0.13f, y + e * 0.58f, x + e * 0.13f, y + e * 0.74f), shape);
        shape.setColor(0x99ffffff);
        c.drawCircle(x - e * 0.04f, y + e * 0.63f, e * 0.03f, shape);
        strokePaint.setStrokeWidth(Math.max(2f, e * 0.025f));
        strokePaint.setColor(0x99ffffff);
        for (int s = -1; s <= 1; s += 2) {
          c.drawLine(x + s * e * 0.22f, y + e * 0.68f, x + s * e * 0.72f, y + e * 0.62f, strokePaint);
          c.drawLine(x + s * e * 0.22f, y + e * 0.74f, x + s * e * 0.70f, y + e * 0.76f, strokePaint);
        }
        break;
      }

      case "cat":
      case "dog": {
        boolean cat = sticker.equals("cat");
        for (int s = -1; s <= 1; s += 2) {
          float bx = x + s * e * 0.84f, by = y - e * 1.22f;
          c.save();
          c.rotate(s * sway * 0.6f, bx, by);
          if (cat) {
            Path ear = new Path();
            ear.moveTo(bx - e * 0.46f, by + e * 0.05f);
            ear.quadTo(bx - s * e * 0.15f, by - e * 0.85f, bx + s * e * 0.12f, by - e * 0.98f);
            ear.quadTo(bx + s * e * 0.35f, by - e * 0.55f, bx + e * 0.46f, by + e * 0.05f);
            ear.close();
            shape.setShader(new LinearGradient(bx, by - e, bx, by, 0xff2b2738, 0xff464058, Shader.TileMode.CLAMP));
            c.drawPath(ear, shape);
            Path inner = new Path();
            inner.moveTo(bx - e * 0.26f, by - e * 0.02f);
            inner.lineTo(bx + s * e * 0.09f, by - e * 0.68f);
            inner.lineTo(bx + e * 0.26f, by - e * 0.02f);
            inner.close();
            shape.setShader(new LinearGradient(bx, by - e * 0.7f, bx, by, 0xffff8fab, 0xffffc4d6, Shader.TileMode.CLAMP));
            c.drawPath(inner, shape);
            shape.setShader(null);
          } else {
            c.rotate(s * 24f, bx, by);
            RectF drop = new RectF(bx - e * 0.32f, by - e * 0.38f, bx + e * 0.32f, by + e * 0.92f);
            shape.setShader(new LinearGradient(drop.left, drop.top, drop.right, drop.bottom, 0xffa6734e, 0xff784d30, Shader.TileMode.CLAMP));
            c.drawOval(drop, shape);
            shape.setShader(null);
          }
          c.restore();
        }
        shape.setColor(cat ? 0xffff80a0 : 0xff3b281e);
        c.drawOval(new RectF(x - e * (cat ? 0.13f : 0.21f), y + e * 0.55f, x + e * (cat ? 0.13f : 0.21f), y + e * (cat ? 0.69f : 0.79f)), shape);
        shape.setColor(0x88ffffff);
        c.drawCircle(x - e * 0.05f, y + e * 0.60f, e * 0.032f, shape);
        if (cat) {
          strokePaint.setColor(0xdd2b2738);
          strokePaint.setStrokeWidth(Math.max(2f, e * 0.03f));
          for (int s = -1; s <= 1; s += 2) {
            for (int w = -1; w <= 1; w++) {
              c.drawLine(x + s * e * 0.26f, y + e * 0.68f, x + s * e * 0.94f, y + e * (0.61f + w * 0.12f), strokePaint);
            }
          }
        } else {
          // Lưỡi cún hồng đung đưa nhẹ
          RectF tongue = new RectF(x - e * 0.14f, y + e * 0.96f, x + e * 0.14f, y + e * 1.34f);
          shape.setShader(new LinearGradient(x, tongue.top, x, tongue.bottom, 0xffff5d84, 0xffff8fab, Shader.TileMode.CLAMP));
          c.drawOval(tongue, shape);
          shape.setShader(null);
          strokePaint.setColor(0x55b83256);
          strokePaint.setStrokeWidth(Math.max(1.5f, e * 0.02f));
          c.drawLine(x, y + e * 0.98f, x, y + e * 1.24f, strokePaint);
        }
        break;
      }

      case "crown": {
        float cy = y - e * 1.35f, cw = e * 0.98f, ch = e * 0.72f;
        Path crown = new Path();
        crown.moveTo(x - cw * 0.82f, cy);
        crown.lineTo(x - cw * 0.92f, cy - ch * 0.82f);
        crown.lineTo(x - cw * 0.44f, cy - ch * 0.34f);
        crown.lineTo(x, cy - ch * 1.05f);
        crown.lineTo(x + cw * 0.44f, cy - ch * 0.34f);
        crown.lineTo(x + cw * 0.92f, cy - ch * 0.82f);
        crown.lineTo(x + cw * 0.82f, cy);
        crown.close();
        shape.setShader(new LinearGradient(x - cw, cy - ch, x + cw, cy, 0xffffe57f, 0xfff59e0b, Shader.TileMode.CLAMP));
        c.drawPath(crown, shape);
        shape.setShader(null);
        strokePaint.setColor(0xffb45309);
        strokePaint.setStrokeWidth(Math.max(2f, e * 0.035f));
        c.drawPath(crown, strokePaint);
        // Ngọc đính trên vương miện
        shape.setColor(0xfff43f5e);
        c.drawCircle(x, cy - ch * 0.38f, e * 0.09f, shape);
        shape.setColor(0xff38bdf8);
        c.drawCircle(x - cw * 0.46f, cy - ch * 0.18f, e * 0.065f, shape);
        c.drawCircle(x + cw * 0.46f, cy - ch * 0.18f, e * 0.065f, shape);
        drawSparkleStar(c, x, cy - ch * 1.12f, e * 0.18f, 0xfffff7cc, tick * 3f);
        break;
      }

      case "halo": {
        float hy = y - e * 1.62f + (float) Math.sin(tick * 0.07) * e * 0.06f;
        RectF ring = new RectF(x - e * 0.95f, hy - e * 0.22f, x + e * 0.95f, hy + e * 0.22f);
        strokePaint.setStyle(Paint.Style.STROKE);
        strokePaint.setStrokeWidth(e * 0.16f);
        strokePaint.setColor(0x55fde047);
        c.drawOval(ring, strokePaint);
        strokePaint.setStrokeWidth(e * 0.085f);
        strokePaint.setColor(0xfffef08a);
        c.drawOval(ring, strokePaint);
        drawSparkleStar(c, x - e * 0.82f, hy, e * 0.15f, 0xfffef08a, tick * 2f);
        drawSparkleStar(c, x + e * 0.82f, hy - e * 0.05f, e * 0.12f, 0xffffffff, -tick * 2f);
        break;
      }

      case "devil": {
        for (int s = -1; s <= 1; s += 2) {
          Path horn = new Path();
          float bx = x + s * e * 0.68f, by = y - e * 1.15f;
          horn.moveTo(bx - s * e * 0.22f, by);
          horn.quadTo(bx + s * e * 0.48f, by - e * 0.45f, bx + s * e * 0.28f, by - e * 0.95f);
          horn.quadTo(bx - s * e * 0.05f, by - e * 0.52f, bx + s * e * 0.18f, by + e * 0.05f);
          horn.close();
          shape.setShader(new LinearGradient(bx, by - e, bx, by, 0xffff2a55, 0xff880e28, Shader.TileMode.CLAMP));
          c.drawPath(horn, shape);
          shape.setShader(null);
        }
        break;
      }

      case "rainbow": {
        int[] cols = { 0xccef4444, 0xccf97316, 0xcceab308, 0xcc22c55e, 0xcc3b82f6, 0xcca855f7 };
        strokePaint.setStyle(Paint.Style.STROKE);
        strokePaint.setStrokeWidth(e * 0.065f);
        for (int i = 0; i < cols.length; i++) {
          float r = e * (1.42f - i * 0.065f);
          strokePaint.setColor(cols[i]);
          c.drawArc(new RectF(x - r, y - e * 0.55f - r, x + r, y - e * 0.55f + r), 200, 140, false, strokePaint);
        }
        break;
      }

      case "flowers": {
        int[] petalCols = { 0xffff8fab, 0xffffd166, 0xffff758f, 0xffc77dff, 0xffff8fab, 0xffffd166, 0xffff758f };
        for (int i = 0; i < 7; i++) {
          double t = Math.PI * (0.12 + 0.76 * i / 6.0);
          float fx2 = x - (float) Math.cos(t) * e * 1.26f;
          float fy2 = y - e * 0.98f - (float) Math.sin(t) * e * 0.52f;
          float pr = e * 0.14f;
          shape.setColor(petalCols[i]);
          for (int p = 0; p < 5; p++) {
            double ang = p * Math.PI * 2 / 5.0 + tick * 0.02;
            c.drawCircle(fx2 + (float) Math.cos(ang) * pr * 0.85f, fy2 + (float) Math.sin(ang) * pr * 0.85f, pr * 0.68f, shape);
          }
          shape.setColor(0xfffff3b0);
          c.drawCircle(fx2, fy2, pr * 0.52f, shape);
        }
        break;
      }

      case "bow": {
        float bx = x + e * 0.88f, by = y - e * 1.24f;
        c.save();
        c.translate(bx, by);
        c.rotate(16f + sway * 0.5f);
        for (int s = -1; s <= 1; s += 2) {
          Path loop = new Path();
          loop.moveTo(0, 0);
          loop.cubicTo(s * e * 0.55f, -e * 0.42f, s * e * 0.62f, e * 0.36f, 0, e * 0.08f);
          loop.close();
          shape.setShader(new LinearGradient(0, -e * 0.3f, s * e * 0.5f, e * 0.3f, 0xffff4d88, 0xffff85ad, Shader.TileMode.CLAMP));
          c.drawPath(loop, shape);
        }
        shape.setShader(null);
        shape.setColor(0xffe01e5a);
        c.drawRoundRect(new RectF(-e * 0.11f, -e * 0.12f, e * 0.11f, e * 0.14f), e * 0.05f, e * 0.05f, shape);
        c.restore();
        break;
      }

      case "freckles": {
        cheeks(c, x, y, e, 0, 0x52ff7597);
        shape.setColor(0x8872422d);
        java.util.Random r = new java.util.Random(7);
        for (int s = -1; s <= 1; s += 2) {
          for (int i = 0; i < 10; i++) {
            float px = x + s * e * (0.36f + r.nextFloat() * 0.52f);
            float py = y + e * (0.46f + r.nextFloat() * 0.32f);
            c.drawCircle(px, py, Math.max(1.4f, e * (0.020f + r.nextFloat() * 0.018f)), shape);
          }
        }
        break;
      }

      case "hearts": {
        int[] hCols = { 0xffff4d79, 0xffff7597, 0xfff43f5e, 0xffec4899, 0xffff85a1, 0xfffb7185 };
        for (int i = 0; i < 6; i++) {
          float phase = ((tick * 0.013f) + i / 6f) % 1f;
          float px = x + (float) Math.sin(i * 1.7 + tick * 0.05) * e * 1.55f;
          float py = y - e * 0.5f - phase * e * 2.85f;
          int alpha = Math.round(255 * (1f - phase) * Math.min(1f, phase * 4f));
          drawVectorHeart(c, px, py, e * (0.28f + (i % 3) * 0.06f), hCols[i], alpha);
        }
        break;
      }

      case "sparkle": {
        int[] sCols = { 0xfffef08a, 0xffffffff, 0xffbae6fd, 0xfffde047, 0xfffbcfe8, 0xffffffff, 0xfffef08a };
        for (int i = 0; i < 7; i++) {
          double t = i * Math.PI * 2 / 7.0 + tick / 28.0;
          float pulse = 0.55f + 0.45f * (float) Math.abs(Math.sin(tick / 7.0 + i * 1.1));
          float px = x + (float) Math.cos(t) * e * 2.15f;
          float py = y + e * 0.2f + (float) Math.sin(t) * e * 2.45f;
          drawSparkleStar(c, px, py, e * 0.28f * pulse, sCols[i], (float) (tick * 2.5 + i * 25));
        }
        break;
      }

      case "stars": {
        for (int i = 0; i < 6; i++) {
          double t = i * Math.PI * 2 / 6.0 + tick / 16.0;
          float px = x + (float) Math.cos(t) * e * 1.32f;
          float py = y - e * 1.48f + (float) Math.sin(t) * e * 0.34f;
          drawSparkleStar(c, px, py, e * 0.22f, i % 2 == 0 ? 0xfffde047 : 0xffffffff, (float) (tick * 4 + i * 30));
        }
        break;
      }

      case "bubbles": {
        for (int i = 0; i < 7; i++) {
          double t = tick / 28.0 + i * Math.PI * 2 / 7.0;
          float bx = x + (float) Math.cos(t) * e * 2.05f;
          float by = y + e * 0.25f + (float) Math.sin(t) * e * 2.35f;
          float br = e * (0.22f + (i % 3) * 0.07f);
          shape.setShader(new RadialGradient(bx - br * 0.3f, by - br * 0.3f, br * 1.3f,
            new int[] { 0x66ffffff, 0x337dd3fc, 0x55f472b6 }, new float[] { 0f, 0.65f, 1f }, Shader.TileMode.CLAMP));
          c.drawCircle(bx, by, br, shape);
          shape.setShader(null);
          strokePaint.setStrokeWidth(Math.max(1.5f, e * 0.02f));
          strokePaint.setColor(0x88ffffff);
          c.drawCircle(bx, by, br, strokePaint);
          shape.setColor(0xccffffff);
          c.drawCircle(bx - br * 0.34f, by - br * 0.34f, br * 0.18f, shape);
        }
        break;
      }

      case "butterfly": {
        int[] bCols = { 0xff60a5fa, 0xfff472b6, 0xffc084fc, 0xff34d399, 0xfffbbf24 };
        for (int i = 0; i < 5; i++) {
          double t = tick / 26.0 + i * Math.PI * 2 / 5.0;
          float bx = x + (float) Math.cos(t) * e * 1.95f;
          float by = y - e * 0.1f + (float) Math.sin(t * 1.3) * e * 1.85f;
          float flap = 0.55f + 0.45f * (float) Math.abs(Math.sin(tick * 0.22 + i));
          c.save();
          c.translate(bx, by);
          c.rotate((float) Math.toDegrees(Math.sin(t)) * 0.35f);
          shape.setColor(bCols[i]);
          for (int s = -1; s <= 1; s += 2) {
            c.save();
            c.scale(s * flap, 1f);
            c.drawOval(new RectF(0, -e * 0.22f, e * 0.28f, e * 0.04f), shape);
            c.drawOval(new RectF(0, -e * 0.02f, e * 0.22f, e * 0.20f), shape);
            c.restore();
          }
          c.restore();
        }
        break;
      }

      case "snow": {
        strokePaint.setColor(0xddffffff);
        strokePaint.setStrokeWidth(Math.max(1.8f, e * 0.025f));
        for (int i = 0; i < 7; i++) {
          double t = tick / 26.0 + i * Math.PI * 2 / 7.0;
          float sx2 = x + (float) Math.cos(t) * e * 2.1f;
          float sy2 = y + e * 0.25f + (float) Math.sin(t) * e * 2.4f;
          float sr = e * 0.19f;
          c.save();
          c.translate(sx2, sy2);
          c.rotate(tick * 1.5f + i * 25f);
          for (int k = 0; k < 3; k++) {
            c.rotate(60f);
            c.drawLine(-sr, 0, sr, 0, strokePaint);
          }
          c.restore();
        }
        break;
      }

      case "confetti": {
        int[] cCols = { 0xfff43f5e, 0xfffacc15, 0xff22c55e, 0xff38bdf8, 0xffa855f7, 0xfff97316, 0xffec4899 };
        for (int i = 0; i < 9; i++) {
          double t = tick / 22.0 + i * Math.PI * 2 / 9.0;
          float cx = x + (float) Math.cos(t) * e * 2.15f;
          float cy = y + e * 0.2f + (float) Math.sin(t) * e * 2.45f;
          c.save();
          c.translate(cx, cy);
          c.rotate(tick * 5f + i * 40f);
          shape.setColor(cCols[i % cCols.length]);
          c.drawRoundRect(new RectF(-e * 0.12f, -e * 0.055f, e * 0.12f, e * 0.055f), e * 0.02f, e * 0.02f, shape);
          c.restore();
        }
        break;
      }
    }
    c.restore();
  }
}
