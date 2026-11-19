package app.kinnect.live;

import android.graphics.*;
import android.text.*;
import java.util.*;

/** Draws one frame of an EditorProject: background, clips with transitions, then layers. */
final class EditorRender {
  static final String[][] TRANSITIONS = {
    {"none",I18n.t("Không")},{"fade",I18n.t("Mờ dần")},{"black",I18n.t("Qua đen")},{"white",I18n.t("Lóe sáng")},{"slideLeft",I18n.t("Trượt trái")},{"slideRight",I18n.t("Trượt phải")},
    {"push",I18n.t("Đẩy lên")},{"zoomIn",I18n.t("Phóng to")},{"zoomOut",I18n.t("Thu nhỏ")},{"wipe",I18n.t("Quét ngang")},{"circle",I18n.t("Vòng tròn")},{"blur",I18n.t("Nhòe")},{"spin","Xoay"}};
  static final String[][] ANIMATIONS = {{"none",I18n.t("Không")},{"fade",I18n.t("Mờ dần")},{"pop",I18n.t("Bật lên")},{"slide",I18n.t("Trượt lên")},{"zoom",I18n.t("Thu phóng")},{"wipe",I18n.t("Quét")},{"type",I18n.t("Đánh máy")}};
  static final String[][] STYLES = {{"stroke",I18n.t("Viền đen")},{"plain",I18n.t("Bóng đổ")},{"box",I18n.t("Nền tối")},{"label",I18n.t("Nhãn màu")},{"neon","Neon"}};
  static final String[][] FONTS = {{"sans-serif",I18n.t("Mặc định")},{"sans-serif-black",I18n.t("Đậm")},{"sans-serif-condensed",I18n.t("Hẹp")},{"serif",I18n.t("Có chân")},{"monospace",I18n.t("Máy chữ")},{"casual",I18n.t("Viết tay")},{"cursive",I18n.t("Nghệ thuật")}};

  /** A clip frame ready to draw: the decoded picture plus face info for beauty effects. */
  static final class Frame { Bitmap bitmap; float[] face; }

  private final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
  private final TextPaint text = new TextPaint(Paint.ANTI_ALIAS_FLAG);
  private Bitmap layerA, layerB, blurSmall;
  /** Screen-space bounds of each layer drawn in the last frame, for touch selection on the preview. */
  final Map<Integer, RectF> bounds = new HashMap<>();
  final Map<Integer, Float> angles = new HashMap<>();

  void draw(Canvas out, EditorProject p, float t, Map<Integer, Frame> frames, Map<String, Bitmap> images, int tick, boolean editing) {
    int w = out.getWidth(), h = out.getHeight(); bounds.clear(); angles.clear();
    if (layerA == null || layerA.getWidth() != w || layerA.getHeight() != h) {
      if (layerA != null) { layerA.recycle(); layerB.recycle(); }
      layerA = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888); layerB = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
    }
    float[] starts = p.starts(); int current = p.clipAt(t);
    if (current < 0) { out.drawColor(Color.BLACK); return; }
    EditorProject.Clip in = p.clips.get(current); float overlap = p.overlap(current);
    float progress = overlap > 0 ? (t - starts[current]) / overlap : 1;
    EditorProject.Clip from = progress < 1 && current > 0 ? p.clips.get(current - 1) : null;
    background(out, p, frames.get(in.id));
    if (from == null) { clip(layerA, in, t - starts[current], frames.get(in.id), tick); composite(out, layerA, 255); }
    else {
      clip(layerA, from, t - starts[current - 1], frames.get(from.id), tick);
      clip(layerB, in, t - starts[current], frames.get(in.id), tick);
      transition(out, in.transition, Math.max(0, Math.min(1, progress)), layerA, layerB);
    }
    for (EditorProject.Layer l : p.layers) if (t >= l.start && t < l.start + l.length) layer(out, l, t - l.start, images, editing);
  }

  private void background(Canvas out, EditorProject p, Frame f) {
    String b = p.background;
    if (b.equals("white")) out.drawColor(Color.WHITE);
    else if (b.startsWith("#")) { try { out.drawColor(Color.parseColor(b)); } catch (Exception e) { out.drawColor(Color.BLACK); } }
    else if (b.equals("blur") && f != null && f.bitmap != null && !f.bitmap.isRecycled()) {
      // Cheap blur: shrink to a few dozen pixels, then stretch back with filtering.
      int sw = Math.max(4, out.getWidth() / 24), sh = Math.max(4, out.getHeight() / 24);
      if (blurSmall == null || blurSmall.getWidth() != sw || blurSmall.getHeight() != sh) { if (blurSmall != null) blurSmall.recycle(); blurSmall = Bitmap.createBitmap(sw, sh, Bitmap.Config.ARGB_8888); }
      Canvas c = new Canvas(blurSmall); float k = Math.max(sw / (float) f.bitmap.getWidth(), sh / (float) f.bitmap.getHeight());
      c.save(); c.translate(sw / 2f, sh / 2f); c.scale(k, k); c.drawBitmap(f.bitmap, -f.bitmap.getWidth() / 2f, -f.bitmap.getHeight() / 2f, paint); c.restore();
      out.drawBitmap(blurSmall, null, new Rect(0, 0, out.getWidth(), out.getHeight()), paint); out.drawColor(0x66000000);
    } else out.drawColor(Color.BLACK);
  }

  private void clip(Bitmap target, EditorProject.Clip c, float local, Frame f, int tick) {
    target.eraseColor(Color.TRANSPARENT);
    if (f == null || f.bitmap == null || f.bitmap.isRecycled()) return;
    float[] pose = c.pose(local); FxEngine fx = c.fx;
    fx.clearBackground = true; fx.text = ""; fx.keyframed = false; fx.zoom = pose[EditorProject.SCALE];
    fx.panX = pose[EditorProject.X] - .5f; fx.panY = pose[EditorProject.Y] - .5f; fx.rotation = c.turn + pose[EditorProject.ROTATION];
    fx.timeSeconds = local; fx.projectSeconds = c.length();
    Canvas canvas = new Canvas(target); fx.render(canvas, f.bitmap, f.face, tick);
    if (pose[EditorProject.OPACITY] < .999f) canvas.drawColor(Color.argb(Math.round((1 - pose[EditorProject.OPACITY]) * 255), 0, 0, 0), PorterDuff.Mode.DST_OUT);
  }

  private void composite(Canvas out, Bitmap b, int alpha) { paint.setAlpha(alpha); out.drawBitmap(b, 0, 0, paint); paint.setAlpha(255); }

  void transition(Canvas out, String kind, float u, Bitmap a, Bitmap b) {
    int w = out.getWidth(), h = out.getHeight(); float e = u * u * (3 - 2 * u);
    switch (kind) {
      case "black": case "white": {
        int color = kind.equals("black") ? Color.BLACK : Color.WHITE;
        if (u < .5f) { composite(out, a, 255); out.drawColor(Color.argb(Math.round(u * 2 * 255), Color.red(color), Color.green(color), Color.blue(color))); }
        else { out.drawColor(color); composite(out, b, Math.round((u - .5f) * 2 * 255)); }
        break; }
      case "slideLeft": case "slideRight": { float dir = kind.equals("slideLeft") ? -1 : 1;
        out.save(); out.translate(dir * e * w, 0); composite(out, a, 255); out.restore();
        out.save(); out.translate(-dir * (1 - e) * w, 0); composite(out, b, 255); out.restore(); break; }
      case "push": out.save(); out.translate(0, -e * h); composite(out, a, 255); out.restore(); out.save(); out.translate(0, (1 - e) * h); composite(out, b, 255); out.restore(); break;
      case "zoomIn": out.save(); out.scale(1 + e * .6f, 1 + e * .6f, w / 2f, h / 2f); composite(out, a, Math.round((1 - e) * 255)); out.restore();
        out.save(); out.scale(.7f + .3f * e, .7f + .3f * e, w / 2f, h / 2f); composite(out, b, Math.round(e * 255)); out.restore(); break;
      case "zoomOut": out.save(); out.scale(1 - e * .4f, 1 - e * .4f, w / 2f, h / 2f); composite(out, a, Math.round((1 - e) * 255)); out.restore();
        out.save(); out.scale(1.5f - .5f * e, 1.5f - .5f * e, w / 2f, h / 2f); composite(out, b, Math.round(e * 255)); out.restore(); break;
      case "wipe": composite(out, a, 255); out.save(); out.clipRect(0, 0, e * w, h); composite(out, b, 255); out.restore(); break;
      case "circle": { composite(out, a, 255); Path path = new Path(); path.addCircle(w / 2f, h / 2f, e * (float) Math.hypot(w, h) / 2, Path.Direction.CW);
        out.save(); out.clipPath(path); composite(out, b, 255); out.restore(); break; }
      case "blur": { float k = 1 - Math.abs(u - .5f) * 2; int div = 1 + Math.round(k * 20);
        Bitmap src = u < .5f ? a : b; Bitmap small = Bitmap.createScaledBitmap(src, Math.max(2, w / div), Math.max(2, h / div), true);
        out.drawBitmap(small, null, new Rect(0, 0, w, h), paint); small.recycle(); break; }
      case "spin": out.save(); out.rotate(e * 180, w / 2f, h / 2f); out.scale(1 - e * .5f, 1 - e * .5f, w / 2f, h / 2f); composite(out, a, Math.round((1 - e) * 255)); out.restore();
        out.save(); out.rotate((e - 1) * 180, w / 2f, h / 2f); out.scale(.5f + e * .5f, .5f + e * .5f, w / 2f, h / 2f); composite(out, b, Math.round(e * 255)); out.restore(); break;
      default: composite(out, a, 255); composite(out, b, Math.round(e * 255));
    }
  }

  private static float easeOutBack(float u) { float c = 1.7f; float v = u - 1; return 1 + (c + 1) * v * v * v + c * v * v; }

  private void layer(Canvas out, EditorProject.Layer l, float local, Map<String, Bitmap> images, boolean editing) {
    int w = out.getWidth(), h = out.getHeight(); float[] pose = l.pose(local);
    float d = Math.min(l.animLength, l.length / 2);
    float pin = d > 0 && !l.animIn.equals("none") && local < d ? local / d : 1, pout = d > 0 && !l.animOut.equals("none") && local > l.length - d ? (l.length - local) / d : 1;
    float alpha = pose[EditorProject.OPACITY], scale = pose[EditorProject.SCALE], dy = 0, reveal = 1, chars = 1;
    float[] ps = { pin, pout }; String[] kinds = { l.animIn, l.animOut };
    for (int i = 0; i < 2; i++) {
      float u = Math.max(0, Math.min(1, ps[i])); if (u >= 1) continue;
      switch (kinds[i]) {
        case "fade": alpha *= u; break;
        case "pop": scale *= .4f + .6f * easeOutBack(u); alpha *= Math.min(1, u * 2); break;
        case "slide": dy += (1 - u) * h * .06f * (i == 0 ? 1 : -1); alpha *= u; break;
        case "zoom": scale *= 1 + (1 - u) * .6f; alpha *= u; break;
        case "wipe": reveal = Math.min(reveal, u); break;
        case "type": if (i == 0) chars = u; else alpha *= u; break;
      }
    }
    if (alpha <= .001f) return;
    float cx = pose[EditorProject.X] * w, cy = pose[EditorProject.Y] * h + dy, angle = pose[EditorProject.ROTATION];
    int save = out.saveLayerAlpha(0, 0, w, h, Math.round(Math.min(1, alpha) * 255));
    out.translate(cx, cy); out.rotate(angle); out.scale(scale, scale);
    RectF box;
    if (l.kind.equals("image")) {
      Bitmap b = l.image == null ? null : images.get(l.image.getAbsolutePath());
      if (b == null || b.isRecycled()) { out.restoreToCount(save); return; }
      float bw = w * .5f, bh = bw * b.getHeight() / b.getWidth();
      box = new RectF(-bw / 2, -bh / 2, bw / 2, bh / 2);
      if (reveal < 1) out.clipRect(box.left, box.top, box.left + box.width() * reveal, box.bottom);
      out.drawBitmap(b, null, box, paint);
    } else {
      String value = l.text; if (chars < 1) value = value.substring(0, Math.round(value.length() * chars));
      box = drawText(out, l, value, w, reveal);
    }
    out.restoreToCount(save);
    if (box != null) {
      float s = scale; RectF screen = new RectF(cx + box.left * s, cy + box.top * s, cx + box.right * s, cy + box.bottom * s);
      bounds.put(l.id, screen); angles.put(l.id, angle);
    }
  }

  /** Text centred on the origin; returns its box (unscaled). */
  private RectF drawText(Canvas c, EditorProject.Layer l, String value, int w, float reveal) {
    boolean sticker = l.kind.equals("sticker");
    text.reset(); text.setAntiAlias(true); text.setTextSize(Math.max(8, w * (sticker ? l.size * 2.4f : l.size)));
    text.setTypeface(Typeface.create(l.font, l.font.equals("sans-serif") ? Typeface.BOLD : Typeface.NORMAL));
    Layout.Alignment align = l.align.equals("left") ? Layout.Alignment.ALIGN_NORMAL : l.align.equals("right") ? Layout.Alignment.ALIGN_OPPOSITE : Layout.Alignment.ALIGN_CENTER;
    int max = Math.round(w * .86f); CharSequence shown = value.isEmpty() ? " " : value;
    StaticLayout measure = StaticLayout.Builder.obtain(shown, 0, shown.length(), text, max).setAlignment(align).build();
    float width = 0; for (int i = 0; i < measure.getLineCount(); i++) width = Math.max(width, measure.getLineWidth(i));
    int lw = Math.max(1, (int) Math.ceil(width)); float pad = text.getTextSize() * .32f;
    StaticLayout layout = StaticLayout.Builder.obtain(shown, 0, shown.length(), text, lw).setAlignment(align).build();
    float bw = lw, bh = layout.getHeight();
    RectF box = new RectF(-bw / 2 - pad, -bh / 2 - pad * .6f, bw / 2 + pad, bh / 2 + pad * .6f);
    if (reveal < 1) c.clipRect(box.left, box.top, box.left + box.width() * reveal, box.bottom);
    String style = sticker ? "plain" : l.style;
    if (style.equals("box") || style.equals("label")) {
      Paint bg = new Paint(Paint.ANTI_ALIAS_FLAG); bg.setColor(style.equals("box") ? 0xb3000000 : l.color);
      c.drawRoundRect(box, pad * .8f, pad * .8f, bg);
    }
    c.save(); c.translate(-bw / 2, -bh / 2);
    int fill = style.equals("label") ? (luma(l.color) > 150 ? Color.BLACK : Color.WHITE) : style.equals("neon") ? Color.WHITE : l.color;
    if (style.equals("stroke")) {
      text.setStyle(Paint.Style.STROKE); text.setStrokeWidth(text.getTextSize() * .14f); text.setStrokeJoin(Paint.Join.ROUND); text.setColor(Color.BLACK);
      layout.draw(c); text.setStyle(Paint.Style.FILL);
    }
    if (style.equals("plain")) text.setShadowLayer(text.getTextSize() * .12f, 0, text.getTextSize() * .05f, 0xb3000000);
    if (style.equals("neon")) text.setShadowLayer(text.getTextSize() * .45f, 0, 0, l.color);
    text.setColor(fill); layout.draw(c); text.clearShadowLayer();
    c.restore();
    return box;
  }

  private static int luma(int c) { return (Color.red(c) * 299 + Color.green(c) * 587 + Color.blue(c) * 114) / 1000; }
}
