package app.kinnect.live;

import java.nio.ByteBuffer;

/**
 * Biến dạng elip nghịch đảo mượt C2 (Smooth Hermite Radial Inverse Warp) dùng chung cho kênh sáng Y và kênh màu U/V.
 */
final class YuvBeauty {
  static void warpPlane(ByteBuffer target, int stride, int width, int height, byte[] source, float cx, float cy, float rx, float ry, float amount) {
    if (amount <= .01f || rx <= 0f || ry <= 0f) return;
    int x0 = Math.max(0, (int) (cx - rx)), x1 = Math.min(width - 1, (int) (cx + rx));
    int y0 = Math.max(0, (int) (cy - ry)), y1 = Math.min(height - 1, (int) (cy + ry));
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        float dx = x - cx, dy = y - cy;
        float r = dx * dx / (rx * rx) + dy * dy / (ry * ry);
        if (r >= 1f) continue;
        // Hàm suy giảm Hermite bậc ba giúp ranh giới vùng mắt/môi mượt tự nhiên không bị răng cưa
        float u = 1f - r;
        float falloff = u * u * (1.25f - 0.25f * u);
        float scale = 1f - amount * 0.32f * falloff;
        int sx = Math.max(0, Math.min(width - 1, Math.round(cx + dx * scale)));
        int sy = Math.max(0, Math.min(height - 1, Math.round(cy + dy * scale)));
        target.put(y * stride + x, source[sy * stride + sx]);
      }
    }
  }
}
