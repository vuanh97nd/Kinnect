package app.kinnect.live;

import android.content.Context;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

/**
 * Số đo thanh tiêu đề và vùng chạm vật lý, đồng bộ với design/tokens.json (v2.0),
 * WebDesign.java và ios/Kinnect/Theme/KinnectTheme.swift.
 * Tỷ lệ icon : khoảng cách : lề = 20 : 12 : 16.
 *
 * Vùng chạm tương tác dùng dpRaw(...) (không nhân WebDesign.UI_SCALE).
 */
final class UiMetrics {
  private UiMetrics() {}

  /** Chiều cao thanh tiêu đề (dp). */
  static final int HEADER_HEIGHT = 56;
  /** Lề ngang hai bên (dp). */
  static final int HEADER_SIDE_PADDING = 16;
  /** Cỡ icon nhìn (dp). */
  static final int HEADER_ICON_SIZE = 20;
  /** Khoảng cách giữa các icon (dp). */
  static final int HEADER_ICON_GAP = 12;
  /** Số hành động tối đa bên phải; vượt thì gom vào menu. */
  static final int HEADER_MAX_TRAILING_ACTIONS = 3;
  /** Vùng chạm tối thiểu trên Android (Material). iOS dùng 44. */
  static final int TOUCH_TARGET_MIN = 48;

  /**
   * Đổi dp sang pixel vật lý theo mật độ màn hình, KHÔNG nhân WebDesign.UI_SCALE.
   */
  static int dpRaw(Context context, int dp) {
    if (context == null || context.getResources() == null
        || context.getResources().getDisplayMetrics() == null) {
      return dp;
    }
    return Math.round(dp * context.getResources().getDisplayMetrics().density);
  }

  /** Bảo đảm view tương tác đạt tối thiểu TOUCH_TARGET_MIN (48dp) vật lý. */
  static void enforceMinTouchTarget(View interactiveView) {
    enforceMinTouchTarget(interactiveView, TOUCH_TARGET_MIN);
  }

  /**
   * Bảo đảm view tương tác đạt tối thiểu Math.max(TOUCH_TARGET_MIN, minDp) vật lý
   * qua minimumWidth/minimumHeight và kẹp LayoutParams dương nhỏ hơn ngưỡng.
   */
  static void enforceMinTouchTarget(View interactiveView, int minDp) {
    if (interactiveView == null) {
      return;
    }
    int minPx = dpRaw(interactiveView.getContext(), Math.max(TOUCH_TARGET_MIN, minDp));
    interactiveView.setMinimumWidth(minPx);
    interactiveView.setMinimumHeight(minPx);
    ViewGroup.LayoutParams lp = interactiveView.getLayoutParams();
    if (lp != null) {
      boolean changed = false;
      if (lp.width > 0 && lp.width < minPx) {
        lp.width = minPx;
        changed = true;
      }
      if (lp.height > 0 && lp.height < minPx) {
        lp.height = minPx;
        changed = true;
      }
      if (changed) {
        interactiveView.setLayoutParams(lp);
      }
    }
  }

  /** Bọc view nhỏ trong FrameLayout đạt tối thiểu TOUCH_TARGET_MIN (48dp) vật lý. */
  static FrameLayout wrapMinTouchTarget(Context context, View child) {
    return wrapMinTouchTarget(context, child, TOUCH_TARGET_MIN);
  }

  /**
   * Bọc view nhỏ trong FrameLayout đạt tối thiểu Math.max(TOUCH_TARGET_MIN, minDp) vật lý,
   * giữ nguyên vị trí trong parent và chuyển tương tác sang wrapper mà không ẩn child khỏi cây a11y.
   */
  static FrameLayout wrapMinTouchTarget(Context context, View child, int minDp) {
    if (child == null) {
      return null;
    }
    Context ctx = context != null ? context : child.getContext();
    if (ctx == null) {
      return null;
    }
    int minPx = dpRaw(ctx, Math.max(TOUCH_TARGET_MIN, minDp));
    FrameLayout wrapper = new FrameLayout(ctx);
    wrapper.setMinimumWidth(minPx);
    wrapper.setMinimumHeight(minPx);

    ViewGroup.LayoutParams origLp = child.getLayoutParams();
    int childW = (origLp != null && origLp.width > 0)
        ? origLp.width : ViewGroup.LayoutParams.WRAP_CONTENT;
    int childH = (origLp != null && origLp.height > 0)
        ? origLp.height : ViewGroup.LayoutParams.WRAP_CONTENT;

    ViewGroup parent = (child.getParent() instanceof ViewGroup)
        ? (ViewGroup) child.getParent() : null;
    if (parent != null) {
      int index = parent.indexOfChild(child);
      parent.removeViewAt(index);
      if (origLp != null) {
        if (origLp.width > 0 && origLp.width < minPx) {
          origLp.width = minPx;
        }
        if (origLp.height > 0 && origLp.height < minPx) {
          origLp.height = minPx;
        }
        parent.addView(wrapper, index, origLp);
      } else {
        wrapper.setLayoutParams(new ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        parent.addView(wrapper, index);
      }
    } else if (origLp != null) {
      if (origLp.width > 0 && origLp.width < minPx) {
        origLp.width = minPx;
      }
      if (origLp.height > 0 && origLp.height < minPx) {
        origLp.height = minPx;
      }
      wrapper.setLayoutParams(origLp);
    } else {
      wrapper.setLayoutParams(new ViewGroup.LayoutParams(
          ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
    }

    wrapper.addView(child, new FrameLayout.LayoutParams(childW, childH, Gravity.CENTER));

    if (child.isClickable()) {
      wrapper.setClickable(true);
      wrapper.setFocusable(child.isFocusable());
      wrapper.setEnabled(child.isEnabled());
      wrapper.setOnClickListener(v -> {
        if (child.isEnabled()) {
          child.performClick();
        }
      });
      child.setClickable(false);
      child.setFocusable(false);
    }
    if (child.isLongClickable()) {
      wrapper.setLongClickable(true);
      wrapper.setOnLongClickListener(v -> child.isEnabled() && child.performLongClick());
      child.setLongClickable(false);
    }
    if (child.getContentDescription() != null && wrapper.getContentDescription() == null) {
      wrapper.setContentDescription(child.getContentDescription());
    }

    return wrapper;
  }
}
