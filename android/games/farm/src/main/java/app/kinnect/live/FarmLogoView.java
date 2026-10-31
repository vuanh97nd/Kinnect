package app.kinnect.live;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.os.SystemClock;
import android.view.View;

/** Game emblem used by the farm launch screen: a low-poly farm badge inside a slowly turning ring. */
final class FarmLogoView extends View {
  private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
  private final Path path = new Path();
  private final RectF badge = new RectF();
  private long startedAt;
  private boolean attached;

  FarmLogoView(Context context) {
    super(context);
    setContentDescription(I18n.t("Logo Nông trại Kinnect"));
  }

  @Override protected void onAttachedToWindow() {
    super.onAttachedToWindow();
    startedAt = SystemClock.uptimeMillis();
    attached = true;
    postInvalidateOnAnimation();
  }

  @Override protected void onDetachedFromWindow() {
    attached = false;
    super.onDetachedFromWindow();
  }

  @Override protected void onDraw(Canvas canvas) {
    super.onDraw(canvas);
    float width = getWidth(), height = getHeight();
    if (width <= 0 || height <= 0) return;
    float cx = width / 2f, cy = height / 2f;
    float radius = Math.min(width, height) * 0.30f;
    float time = (SystemClock.uptimeMillis() - startedAt) / 1000f;

    paint.setStyle(Paint.Style.FILL);
    paint.setShader(new RadialGradient(cx, cy, radius * 1.7f,
      new int[]{0x553fd18a, 0x003fd18a}, new float[]{0.35f, 1f}, Shader.TileMode.CLAMP));
    canvas.drawCircle(cx, cy, radius * 1.7f, paint);
    paint.setShader(null);

    for (int i = 0; i < 12; i++) {
      double angle = time * 0.55 + i * Math.PI * 2 / 12;
      float x = cx + (float) Math.cos(angle) * radius * 1.38f;
      float y = cy + (float) Math.sin(angle) * radius * 1.38f;
      int alpha = 70 + (int) (120 * Math.max(0, Math.sin(angle)));
      paint.setColor((alpha << 24) | 0xf0c766);
      canvas.drawCircle(x, y, radius * (i % 3 == 0 ? 0.045f : 0.03f), paint);
    }

    float size = radius * 1.15f;
    badge.set(cx - size, cy - size, cx + size, cy + size);
    float corner = size * 0.36f;
    paint.setColor(0x33ffffff);
    RectF halo = new RectF(badge.left - size * 0.04f, badge.top - size * 0.04f, badge.right + size * 0.04f, badge.bottom + size * 0.04f);
    canvas.drawRoundRect(halo, corner + size * 0.04f, corner + size * 0.04f, paint);

    int save = canvas.save();
    path.reset();
    path.addRoundRect(badge, corner, corner, Path.Direction.CW);
    canvas.clipPath(path);
    paint.setShader(new LinearGradient(0, badge.top, 0, badge.bottom,
      0xfff8d67a, 0xff2f8f5a, Shader.TileMode.CLAMP));
    canvas.drawRect(badge, paint);
    paint.setShader(null);

    paint.setColor(0xfffff1b8);
    canvas.drawCircle(badge.left + size * 1.33f, badge.top + size * 0.62f, size * 0.2f, paint);
    paint.setColor(0x33fff1b8);
    canvas.drawCircle(badge.left + size * 1.33f, badge.top + size * 0.62f, size * 0.34f, paint);

    path.reset();
    path.moveTo(badge.left, badge.bottom);
    path.lineTo(badge.left, badge.top + size * 1.12f);
    path.quadTo(cx, badge.top + size * 0.62f, badge.right, badge.top + size * 1.04f);
    path.lineTo(badge.right, badge.bottom);
    path.close();
    paint.setColor(0xff3f9e62);
    canvas.drawPath(path, paint);

    path.reset();
    path.moveTo(badge.left, badge.bottom);
    path.lineTo(badge.left, badge.bottom - size * 0.52f);
    path.quadTo(cx - size * 0.1f, badge.bottom - size * 0.95f, badge.right, badge.bottom - size * 0.42f);
    path.lineTo(badge.right, badge.bottom);
    path.close();
    paint.setColor(0xff2b7f4e);
    canvas.drawPath(path, paint);

    float barnWidth = size * 0.52f, barnHeight = size * 0.38f;
    float barnLeft = cx - barnWidth / 2f;
    float barnTop = badge.bottom - size * 0.72f;
    paint.setColor(0xfff3e3c3);
    canvas.drawRect(barnLeft, barnTop, barnLeft + barnWidth, barnTop + barnHeight, paint);
    path.reset();
    path.moveTo(barnLeft - size * 0.07f, barnTop + 1f);
    path.lineTo(cx, barnTop - size * 0.28f);
    path.lineTo(barnLeft + barnWidth + size * 0.07f, barnTop + 1f);
    path.close();
    paint.setColor(0xffc2563f);
    canvas.drawPath(path, paint);
    paint.setColor(0xff6b3d2b);
    canvas.drawRect(cx - barnWidth * 0.12f, barnTop + barnHeight * 0.42f, cx + barnWidth * 0.12f, barnTop + barnHeight, paint);
    paint.setColor(0xffeee0c4);
    canvas.drawRect(cx - barnWidth * 0.35f, barnTop + barnHeight * 0.18f, cx - barnWidth * 0.2f, barnTop + barnHeight * 0.36f, paint);

    paint.setColor(0xffeaffd8);
    paint.setStyle(Paint.Style.STROKE);
    paint.setStrokeWidth(size * 0.035f);
    canvas.drawLine(cx + size * 0.62f, badge.bottom - size * 0.18f, cx + size * 0.62f, badge.bottom - size * 0.5f, paint);
    paint.setStyle(Paint.Style.FILL);
    path.reset();
    path.moveTo(cx + size * 0.62f, badge.bottom - size * 0.44f);
    path.quadTo(cx + size * 0.78f, badge.bottom - size * 0.58f, cx + size * 0.84f, badge.bottom - size * 0.42f);
    path.quadTo(cx + size * 0.74f, badge.bottom - size * 0.32f, cx + size * 0.62f, badge.bottom - size * 0.44f);
    path.close();
    paint.setColor(0xffb8ff8e);
    canvas.drawPath(path, paint);
    path.reset();
    path.moveTo(cx + size * 0.62f, badge.bottom - size * 0.34f);
    path.quadTo(cx + size * 0.46f, badge.bottom - size * 0.48f, cx + size * 0.42f, badge.bottom - size * 0.3f);
    path.quadTo(cx + size * 0.52f, badge.bottom - size * 0.22f, cx + size * 0.62f, badge.bottom - size * 0.34f);
    path.close();
    canvas.drawPath(path, paint);
    canvas.restoreToCount(save);

    paint.setStyle(Paint.Style.STROKE);
    paint.setStrokeWidth(Math.max(1f, size * 0.018f));
    paint.setColor(0x99ffffff);
    canvas.drawRoundRect(badge, corner, corner, paint);
    paint.setStyle(Paint.Style.FILL);

    if (attached) postInvalidateOnAnimation();
  }
}
