package app.kinnect.live;

import android.content.Context;
import android.graphics.*;
import android.view.*;
import android.widget.ScrollView;

/**
 * Con quay làm mới kéo xuống theo chuẩn Google Material 3 Pull-to-Refresh Indicator.
 */
final class PullRefreshScrollView extends ScrollView {
  interface Listener { void refresh(Runnable complete); boolean enabled(); }
  private Listener listener;
  private float startX, startY, pull;
  private boolean top, dragging, busy;
  private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

  PullRefreshScrollView(Context c) { super(c); setOverScrollMode(OVER_SCROLL_NEVER); }
  void setRefreshListener(Listener l) { listener = l; }
  void refreshNow() {
    if (busy || listener == null || !listener.enabled()) return;
    busy = true;
    invalidate();
    listener.refresh(() -> post(() -> { busy = false; invalidate(); }));
  }

  private float dp(float n) { return n * getResources().getDisplayMetrics().density; }

  @Override
  public boolean onInterceptTouchEvent(MotionEvent e) {
    if (e.getActionMasked() == MotionEvent.ACTION_DOWN) {
      startY = e.getY();
      startX = e.getX();
      top = !canScrollVertically(-1);
      dragging = false;
    }
    if (e.getActionMasked() == MotionEvent.ACTION_MOVE && top && !busy && listener != null && listener.enabled() && e.getY() - startY > dp(16) && e.getY() - startY > Math.abs(e.getX() - startX) * 1.3f) {
      dragging = true;
      return true;
    }
    return super.onInterceptTouchEvent(e);
  }

  @Override
  public boolean onTouchEvent(MotionEvent e) {
    if (e.getActionMasked() == MotionEvent.ACTION_DOWN) {
      startY = e.getY();
      startX = e.getX();
      top = !canScrollVertically(-1);
    }
    if (!dragging && e.getActionMasked() == MotionEvent.ACTION_MOVE && top && !busy && listener != null && listener.enabled() && e.getY() - startY > dp(16) && e.getY() - startY > Math.abs(e.getX() - startX) * 1.3f) {
      dragging = true;
      MotionEvent cancel = MotionEvent.obtain(e);
      cancel.setAction(MotionEvent.ACTION_CANCEL);
      super.onTouchEvent(cancel);
      cancel.recycle();
    }
    if (!dragging) return super.onTouchEvent(e);
    if (e.getActionMasked() == MotionEvent.ACTION_MOVE) {
      pull = Math.max(0, Math.min(dp(88), (e.getY() - startY) * .6f));
      invalidate();
      return true;
    }
    if (e.getActionMasked() == MotionEvent.ACTION_UP || e.getActionMasked() == MotionEvent.ACTION_CANCEL) {
      boolean trigger = e.getActionMasked() == MotionEvent.ACTION_UP && pull >= dp(48);
      dragging = false;
      pull = 0;
      if (trigger && !busy && listener != null) {
        busy = true;
        announceForAccessibility(I18n.t("Đang làm mới…"));
        listener.refresh(() -> post(() -> { busy = false; invalidate(); }));
      }
      invalidate();
      return true;
    }
    return true;
  }

  @Override
  protected void dispatchDraw(Canvas c) {
    super.dispatchDraw(c);
    if (!busy && pull <= 0) return;
    boolean dark = WebTheme.isDark(getContext());
    float x = getWidth() / 2f, y = getScrollY() + dp(30) + Math.min(pull, dp(28));
    // Đổ bóng nhẹ chuẩn Material 3 Surface Container
    paint.setStyle(Paint.Style.FILL);
    paint.setColor(0x18000000);
    c.drawCircle(x, y + dp(1.5f), dp(20), paint);
    paint.setColor(dark ? 0xff2b2936 : 0xfff3edf7);
    c.drawCircle(x, y, dp(19.5f), paint);
    paint.setStyle(Paint.Style.STROKE);
    paint.setStrokeWidth(dp(1));
    paint.setColor(dark ? 0x33ffffff : 0x227c5cff);
    c.drawCircle(x, y, dp(19.5f), paint);
    paint.setColor(dark ? 0xffa78bfa : 0xff6c47e0);
    paint.setStrokeWidth(dp(2.4f));
    paint.setStrokeCap(Paint.Cap.ROUND);
    float angle = busy ? (android.os.SystemClock.uptimeMillis() % 850) * .42f : Math.min(270, pull / dp(48) * 270);
    c.drawArc(x - dp(9.5f), y - dp(9.5f), x + dp(9.5f), y + dp(9.5f), angle, 255, false, paint);
    if (busy) postInvalidateDelayed(20);
  }

  @Override
  protected void onDetachedFromWindow() {
    busy = false;
    dragging = false;
    super.onDetachedFromWindow();
  }
}
