package app.kinnect.live;

import android.graphics.*;
import android.media.FaceDetector;
import java.nio.ByteBuffer;
import java.util.concurrent.*;
import org.webrtc.*;

/**
 * Bộ lọc màu và sticker bám khuôn mặt cho phát trực tiếp. Xử lý thẳng trên khung I420
 * (xoay về chiều đứng, chỉnh màu ở kênh Y/U/V, trộn lớp sticker) để không phải đổi sang RGB.
 */
final class LiveEffects implements VideoProcessor {
  static final String[][] FILTERS = { { "none", "Gốc" }, { "warm", "Ấm" }, { "cool", "Mát" }, { "bright", "Sáng da" }, { "mono", "Đen trắng" }, { "vintage", "Hoài cổ" } };
  static final String[][] STICKERS = { { "none", "Không sticker", "" }, { "glasses", "Kính", "😎" }, { "hearts", "Tim", "💖" }, { "crown", "Vương miện", "👑" }, { "cat", "Mèo", "🐱" }, { "sparkle", "Lấp lánh", "✨" } };
  volatile String filter = "none", sticker = "none";
  private VideoSink sink;
  private final ExecutorService worker = Executors.newSingleThreadExecutor();
  private volatile boolean detecting;
  private volatile float[] face;
  private int frames, missed;
  private Bitmap overlay;
  private int[] pixels;
  private final Paint emoji = new Paint(Paint.ANTI_ALIAS_FLAG);

  LiveEffects() { emoji.setTextAlign(Paint.Align.CENTER); }

  @Override public void setSink(VideoSink sink) { this.sink = sink; }
  @Override public void onCapturerStarted(boolean success) {}
  @Override public void onCapturerStopped() {}

  void close() { worker.shutdownNow(); }

  @Override
  public void onFrameCaptured(VideoFrame frame) {
    VideoSink out = sink;
    if (out == null) return;
    if (filter.equals("none") && sticker.equals("none")) { out.onFrame(frame); return; }
    VideoFrame.I420Buffer src = frame.getBuffer().toI420();
    try {
      int rotation = frame.getRotation();
      int w = src.getWidth(), h = src.getHeight();
      int ow = rotation % 180 == 0 ? w : h, oh = rotation % 180 == 0 ? h : w;
      JavaI420Buffer dst = JavaI420Buffer.allocate(ow, oh);
      YuvHelper.I420Rotate(src.getDataY(), src.getStrideY(), src.getDataU(), src.getStrideU(), src.getDataV(), src.getStrideV(),
        dst.getDataY(), dst.getStrideY(), dst.getDataU(), dst.getStrideU(), dst.getDataV(), dst.getStrideV(), w, h, rotation);
      colour(dst);
      frames++;
      if (!sticker.equals("none")) {
        if (frames % 6 == 0 && !detecting) detect(dst);
        if (face != null) stickers(dst);
      }
      VideoFrame next = new VideoFrame(dst, 0, frame.getTimestampNs());
      out.onFrame(next);
      next.release();
    } finally {
      src.release();
    }
  }

  // Chỉnh màu trong miền YUV: độ sáng ở Y, sắc độ ở U (xanh lam) / V (đỏ).
  private void colour(JavaI420Buffer b) {
    String f = filter;
    if (f.equals("none")) return;
    int yAdd = 0, uAdd = 0, vAdd = 0;
    float yMul = 1, cMul = 1;
    if (f.equals("warm")) { uAdd = -8; vAdd = 10; }
    else if (f.equals("cool")) { uAdd = 10; vAdd = -6; }
    else if (f.equals("bright")) { yMul = 1.06f; yAdd = 14; cMul = 0.95f; }
    else if (f.equals("mono")) cMul = 0;
    else if (f.equals("vintage")) { cMul = 0.55f; uAdd = -10; vAdd = 8; yAdd = 6; }
    if (yMul != 1 || yAdd != 0) plane(b.getDataY(), b.getStrideY(), b.getWidth(), b.getHeight(), yMul, yAdd, false);
    int cw = (b.getWidth() + 1) / 2, ch = (b.getHeight() + 1) / 2;
    plane(b.getDataU(), b.getStrideU(), cw, ch, cMul, uAdd, true);
    plane(b.getDataV(), b.getStrideV(), cw, ch, cMul, vAdd, true);
  }

  private static void plane(ByteBuffer p, int stride, int w, int h, float mul, int add, boolean chroma) {
    int[] lut = new int[256];
    for (int i = 0; i < 256; i++) {
      float v = chroma ? (i - 128) * mul + 128 + add : i * mul + add;
      lut[i] = Math.max(0, Math.min(255, Math.round(v)));
    }
    for (int y = 0; y < h; y++) {
      int row = y * stride;
      for (int x = 0; x < w; x++) p.put(row + x, (byte) lut[p.get(row + x) & 255]);
    }
  }

  // Nhận diện khuôn mặt trên ảnh xám nửa độ phân giải (android.media.FaceDetector, chạy nền).
  private void detect(JavaI420Buffer b) {
    final int w = (b.getWidth() / 2) & ~1, h = b.getHeight() / 2;
    final int[] gray = new int[w * h];
    ByteBuffer y = b.getDataY();
    int stride = b.getStrideY();
    for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) {
      int v = y.get(r * 2 * stride + c * 2) & 255;
      gray[r * w + c] = 0xff000000 | (v << 16) | (v << 8) | v;
    }
    detecting = true;
    worker.execute(() -> {
      try {
        Bitmap bmp = Bitmap.createBitmap(gray, w, h, Bitmap.Config.RGB_565);
        FaceDetector.Face[] found = new FaceDetector.Face[1];
        int n = new FaceDetector(w, h, 1).findFaces(bmp, found);
        bmp.recycle();
        if (n > 0 && found[0] != null && found[0].confidence() >= 0.3f) {
          PointF mid = new PointF();
          found[0].getMidPoint(mid);
          float[] next = { mid.x * 2, mid.y * 2, found[0].eyesDistance() * 2, found[0].pose(FaceDetector.Face.EULER_Z) };
          float[] old = face;
          if (old != null) for (int i = 0; i < 4; i++) next[i] = old[i] * 0.4f + next[i] * 0.6f;
          face = next;
          missed = 0;
        } else if (++missed >= 4) face = null;
      } catch (Exception ignored) {
      } finally {
        detecting = false;
      }
    });
  }

  // Vẽ sticker lên lớp trong suốt rồi trộn vào khung I420.
  private void stickers(JavaI420Buffer b) {
    int w = b.getWidth(), h = b.getHeight();
    if (overlay == null || overlay.getWidth() != w || overlay.getHeight() != h) {
      overlay = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
      pixels = new int[w * h];
    }
    overlay.eraseColor(0);
    Canvas c = new Canvas(overlay);
    float[] f = face;
    String s = sticker, glyph = "";
    for (String[] it : STICKERS) if (it[0].equals(s)) glyph = it[2];
    float x = f[0], y = f[1], eyes = f[2];
    c.rotate(f[3], x, y);
    if (s.equals("glasses")) { emoji.setTextSize(eyes * 2.3f); c.drawText("🕶", x, y + eyes * 0.45f, emoji); }
    else if (s.equals("crown")) { emoji.setTextSize(eyes * 2.4f); c.drawText(glyph, x, y - eyes * 1.5f, emoji); }
    else if (s.equals("cat")) { emoji.setTextSize(eyes * 1.4f); c.drawText(glyph, x - eyes * 1.3f, y - eyes * 1.4f, emoji); c.drawText(glyph, x + eyes * 1.3f, y - eyes * 1.4f, emoji); }
    else {
      int count = s.equals("hearts") ? 5 : 6;
      emoji.setTextSize(eyes * (s.equals("hearts") ? 1.1f : 0.9f));
      for (int i = 0; i < count; i++) {
        double a = frames / (s.equals("hearts") ? 12.0 : 20.0) + i * Math.PI * 2 / count;
        c.drawText(glyph, x + (float) Math.cos(a) * eyes * 2.4f, y + (float) Math.sin(a) * eyes * 2.6f, emoji);
      }
    }
    overlay.getPixels(pixels, 0, w, 0, 0, w, h);
    ByteBuffer Y = b.getDataY(), U = b.getDataU(), V = b.getDataV();
    int sy = b.getStrideY(), su = b.getStrideU(), sv = b.getStrideV();
    for (int r = 0; r < h; r++) {
      for (int col = 0; col < w; col++) {
        int p = pixels[r * w + col], a = p >>> 24;
        if (a == 0) continue;
        int R = (p >> 16) & 255, G = (p >> 8) & 255, B = p & 255;
        int yv = (66 * R + 129 * G + 25 * B + 128 >> 8) + 16;
        int yi = r * sy + col;
        Y.put(yi, (byte) (((Y.get(yi) & 255) * (255 - a) + yv * a) / 255));
        if ((r & 1) == 0 && (col & 1) == 0) {
          int uv = (-38 * R - 74 * G + 112 * B + 128 >> 8) + 128, vv = (112 * R - 94 * G - 18 * B + 128 >> 8) + 128;
          int ui = (r / 2) * su + col / 2, vi = (r / 2) * sv + col / 2;
          U.put(ui, (byte) (((U.get(ui) & 255) * (255 - a) + uv * a) / 255));
          V.put(vi, (byte) (((V.get(vi) & 255) * (255 - a) + vv * a) / 255));
        }
      }
    }
  }
}
