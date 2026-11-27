package app.kinnect.live;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.view.ViewParent;
import android.view.ViewTreeObserver;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import org.json.JSONArray;

/**
 * Shared progressive batch binder for scrollable lists so long feeds/notifications
 * avoid single-frame inflation spikes on initial open.
 */
final class WindowedListBinder {
  interface SliceRenderer { void renderSlice(int start, int end); }
  interface ValidCheck { boolean isValid(); }

  private static final int TAG_BATCH_TOKEN = 0x7f0f0043;
  private static final int TAG_SCROLL_CLEANUP = 0x7f0f0044;
  private static final Handler MAIN_HANDLER = new Handler(Looper.getMainLooper());

  private WindowedListBinder() {}

  static void clearPending(LinearLayout container) {
    if (container == null) return;
    container.setTag(TAG_BATCH_TOKEN, null);
    Object cleanup = container.getTag(TAG_SCROLL_CLEANUP);
    if (cleanup instanceof Runnable) ((Runnable) cleanup).run();
    container.setTag(TAG_SCROLL_CLEANUP, null);
  }

  static void bind(
    final Activity activity,
    final LinearLayout container,
    final JSONArray items,
    final int batchSize,
    final int triggerPx,
    final ValidCheck validCheck,
    final SliceRenderer renderer
  ) {
    if (activity == null || container == null || items == null || items.length() == 0 || renderer == null) return;
    clearPending(container);
    final int total = items.length();
    final int firstBatch = Math.min(Math.max(1, batchSize), total);
    renderer.renderSlice(0, firstBatch);
    if (total <= firstBatch) return;

    final Object token = new Object();
    container.setTag(TAG_BATCH_TOKEN, token);
    final int[] nextIdx = { firstBatch };
    ScrollView hostScroll = findAncestorScrollView(container);

    if (hostScroll == null) {
      final Runnable[] pump = new Runnable[1];
      pump[0] = () -> {
        if (activity.isDestroyed() || (validCheck != null && !validCheck.isValid()) || token != container.getTag(TAG_BATCH_TOKEN)) return;
        int end = Math.min(total, nextIdx[0] + batchSize);
        renderer.renderSlice(nextIdx[0], end);
        nextIdx[0] = end;
        if (nextIdx[0] < total) MAIN_HANDLER.postDelayed(pump[0], 40);
      };
      MAIN_HANDLER.postDelayed(pump[0], 40);
      return;
    }

    final ScrollView scroll = hostScroll;
    final ViewTreeObserver.OnScrollChangedListener[] listenerRef = new ViewTreeObserver.OnScrollChangedListener[1];
    final Runnable detach = () -> {
      if (listenerRef[0] != null) {
        ViewTreeObserver vto = scroll.getViewTreeObserver();
        if (vto.isAlive()) vto.removeOnScrollChangedListener(listenerRef[0]);
        listenerRef[0] = null;
      }
    };
    final Runnable appendMore = () -> {
      if (activity.isDestroyed() || (validCheck != null && !validCheck.isValid()) || token != container.getTag(TAG_BATCH_TOKEN) || !container.isAttachedToWindow()) {
        detach.run();
        return;
      }
      int triggerY = scroll.getScrollY() + scroll.getHeight() + triggerPx;
      if (nextIdx[0] < total && triggerY >= bottomInScroll(scroll, container)) {
        int end = Math.min(total, nextIdx[0] + batchSize);
        renderer.renderSlice(nextIdx[0], end);
        nextIdx[0] = end;
        if (nextIdx[0] >= total) {
          detach.run();
          if (container.getTag(TAG_SCROLL_CLEANUP) == detach) container.setTag(TAG_SCROLL_CLEANUP, null);
        }
      }
    };
    listenerRef[0] = appendMore::run;
    container.setTag(TAG_SCROLL_CLEANUP, detach);
    scroll.getViewTreeObserver().addOnScrollChangedListener(listenerRef[0]);
    scroll.post(appendMore);
  }

  private static int bottomInScroll(ScrollView scroll, LinearLayout container) {
    int bottom = container.getBottom();
    ViewParent parent = container.getParent();
    while (parent instanceof android.view.View && parent != scroll) {
      android.view.View v = (android.view.View) parent;
      bottom += v.getTop();
      parent = v.getParent();
    }
    return bottom;
  }

  private static ScrollView findAncestorScrollView(LinearLayout container) {
    ViewParent parent = container.getParent();
    for (int hops = 0; hops < 3 && parent != null; hops++) {
      if (parent instanceof ScrollView) return (ScrollView) parent;
      parent = parent.getParent();
    }
    return null;
  }
}
