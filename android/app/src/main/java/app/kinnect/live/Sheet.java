package app.kinnect.live;

import android.app.Dialog;
import android.content.Context;
import android.content.DialogInterface;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.view.*;
import android.widget.*;

/**
 * Bảng trượt từ dưới lên theo chuẩn Google Material 3 Modal Bottom Sheet (bo góc 28dp,
 * thanh kéo 32x4dp, nút hành động dạng viên thuốc 999dp, kiểu chữ Google Sans / Roboto Medium).
 * Giữ cùng kiểu gọi với AlertDialog.Builder để dùng thay thế trực tiếp.
 */
final class Sheet {
  private final Context context;
  private CharSequence title, message, positive, negative, neutral;
  private DialogInterface.OnClickListener onPositive, onNegative, onNeutral, onItem;
  private DialogInterface.OnCancelListener onCancel;
  private CharSequence[] items;
  private String[] itemIcons;
  private String itemIcon;
  private boolean[] checked;
  private DialogInterface.OnMultiChoiceClickListener onCheck;
  private View view;
  private boolean cancelable = true;
  private boolean autoDismissPositive = true;
  private boolean autoDismissNegative = true;
  private final boolean dark;
  private final int bg, ink, muted, soft, line, accent, accentInk, dangerColor;
  private static int activeSheetCount = 0;
  private static final java.util.WeakHashMap<android.app.Activity, java.util.Set<Dialog>> activitySheets = new java.util.WeakHashMap<>();
  private static boolean lifecycleRegistered = false;

  static boolean hasOpenSheet() { return activeSheetCount > 0; }

  private static void trackForActivity(android.app.Activity act, Dialog dialog) {
    if (act == null || dialog == null) return;
    if (!lifecycleRegistered && act.getApplication() != null) {
      lifecycleRegistered = true;
      act.getApplication().registerActivityLifecycleCallbacks(new android.app.Application.ActivityLifecycleCallbacks() {
        @Override public void onActivityCreated(android.app.Activity a, android.os.Bundle b) {}
        @Override public void onActivityStarted(android.app.Activity a) {}
        @Override public void onActivityResumed(android.app.Activity a) {}
        @Override public void onActivityPaused(android.app.Activity a) {}
        @Override public void onActivityStopped(android.app.Activity a) {}
        @Override public void onActivitySaveInstanceState(android.app.Activity a, android.os.Bundle b) {}
        @Override public void onActivityDestroyed(android.app.Activity a) {
          java.util.Set<Dialog> open = activitySheets.remove(a);
          if (open != null) {
            for (Dialog d : new java.util.ArrayList<>(open)) {
              try { if (d != null && d.isShowing()) d.dismiss(); } catch (Exception ignored) {}
            }
          }
        }
      });
    }
    java.util.Set<Dialog> open = activitySheets.get(act);
    if (open == null) {
      open = new java.util.LinkedHashSet<>();
      activitySheets.put(act, open);
    }
    open.add(dialog);
  }

  private static void untrackForActivity(android.app.Activity act, Dialog dialog) {
    if (act == null || dialog == null) return;
    java.util.Set<Dialog> open = activitySheets.get(act);
    if (open != null) {
      open.remove(dialog);
      if (open.isEmpty()) activitySheets.remove(act);
    }
  }

  Sheet(Context context) {
    this.context = context;
    dark = WebTheme.isDark(context);
    int variant = dark ? 1 : 0;
    bg = WebDesign.CARD[variant]; ink = WebDesign.INK[variant]; muted = WebDesign.MUTED_STRICT[variant];
    soft = WebDesign.WASH[variant]; line = WebDesign.LINE[variant];
    accent = WebDesign.PURPLE[variant]; accentInk = WebDesign.PURPLE_TEXT_STRICT[variant]; dangerColor = WebDesign.DANGER[variant];
  }

  Sheet setTitle(CharSequence t) { title = t; return this; }
  Sheet setMessage(CharSequence m) { message = m; return this; }
  Sheet setView(View v) { view = v; return this; }
  Sheet setItems(CharSequence[] list, DialogInterface.OnClickListener l) { items = list; onItem = l; return this; }
  Sheet setItemIcon(String icon) { itemIcon = icon; return this; }
  Sheet setItemIcons(String[] icons) { itemIcons = icons; return this; }
  Sheet setMultiChoiceItems(CharSequence[] list, boolean[] state, DialogInterface.OnMultiChoiceClickListener l) { items = list; checked = state; onCheck = l; return this; }
  Sheet setPositiveButton(CharSequence t, DialogInterface.OnClickListener l) { positive = t; onPositive = l; return this; }
  Sheet setNegativeButton(CharSequence t, DialogInterface.OnClickListener l) { negative = t; onNegative = l; return this; }
  Sheet setNeutralButton(CharSequence t, DialogInterface.OnClickListener l) { neutral = t; onNeutral = l; return this; }
  Sheet setCancelable(boolean value) { cancelable = value; return this; }
  Sheet setAutoDismissPositive(boolean value) { autoDismissPositive = value; return this; }
  Sheet setAutoDismissNegative(boolean value) { autoDismissNegative = value; return this; }
  Sheet setOnCancelListener(DialogInterface.OnCancelListener l) { onCancel = l; return this; }

  static Button positiveButton(DialogInterface dialog) {
    if (dialog instanceof Dialog) {
      View v = ((Dialog) dialog).findViewById(android.R.id.button1);
      if (v instanceof Button) return (Button) v;
    }
    return null;
  }

  private int dp(int n) { return Math.round(n * context.getResources().getDisplayMetrics().density); }

  private GradientDrawable round(int color, int radius) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    return d;
  }

  private TextView text(CharSequence s, int size, int color, boolean bold) {
    TextView t = new KinnectText(context);
    t.setText(s);
    t.setTextSize(size);
    t.setIncludeFontPadding(false);
    t.setTextColor(color);
    t.setTypeface(ApprovedTypography.font(context, bold ? Typeface.BOLD : Typeface.NORMAL));
    return t;
  }

  Dialog show() {
    final Dialog dialog = new Dialog(context);
    dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
    dialog.setCancelable(cancelable);
    dialog.setCanceledOnTouchOutside(cancelable);
    LinearLayout box = new LinearLayout(context);
    box.setOrientation(LinearLayout.VERTICAL);
    box.setPadding(dp(24), dp(16), dp(24), dp(24));
    GradientDrawable shape = new GradientDrawable();
    shape.setColor(bg);
    float r = dp(28); // Standard M3 modal sheet corner radius
    shape.setCornerRadii(new float[] { r, r, r, r, 0, 0, 0, 0 });
    box.setBackground(shape);
    // Thanh kéo chuẩn Google Material 3 Bottom Sheet (32dp x 4dp)
    View grip = new View(context);
    grip.setBackground(round(line, 99));
    LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(dp(32), dp(4));
    gp.gravity = Gravity.CENTER_HORIZONTAL;
    gp.bottomMargin = dp(22);
    box.addView(grip, gp);
    if (title != null && title.length() > 0) {
      TextView t = text(title, 22, ink, false); // M3 Title is often regular/medium, not strictly bold, and larger
      t.setTag("sheet:title");
      t.setLetterSpacing(-0.01f);
      t.setPadding(0, dp(2), 0, dp(12));
      box.addView(t);
    }
    if (message != null) {
      boolean standalone = title == null || title.length() == 0;
      TextView m = text(message, standalone ? 16 : 14, standalone ? ink : muted, standalone);
      if (standalone) m.setTag("sheet:title");
      m.setPadding(0, standalone ? dp(2) : 0, 0, dp(20));
      m.setLineSpacing(0, 1.38f);
      box.addView(m);
    }
    if (view != null) {
      if (view instanceof EditText) styleInputIfUnstyled((EditText) view);
      if (view instanceof ViewGroup) for (int i = 0; i < ((ViewGroup) view).getChildCount(); i++) {
        View c = ((ViewGroup) view).getChildAt(i);
        if (c instanceof EditText) styleInputIfUnstyled((EditText) c);
      }
      if (view.getParent() != null) ((ViewGroup) view.getParent()).removeView(view);
      if (!(view instanceof EditText)) view.setPadding(0, view.getPaddingTop(), 0, view.getPaddingBottom());
      box.addView(view);
    }
    if (items != null) {
      LinearLayout list = new LinearLayout(context);
      list.setOrientation(LinearLayout.VERTICAL);
      for (int i = 0; i < items.length; i++) {
        final int index = i;
        LinearLayout row = new LinearLayout(context);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(16), dp(16), dp(16), dp(16));
        row.setMinimumHeight(dp(56));
        row.setBackground(new android.graphics.drawable.RippleDrawable(
          android.content.res.ColorStateList.valueOf((accent & 0x00ffffff) | 0x22000000),
          round(bg, 99), // M3 list items in dialogs sometimes are pill-shaped or rounded
          round(0xff000000, 99)
        ));
        String label = String.valueOf(items[i]);
        boolean danger = isDangerLabel(label);
        if (checked != null) {
          final CheckBox box2 = new CheckBox(context);
          box2.setChecked(checked[i]);
          box2.setClickable(false);
          box2.setButtonTintList(new android.content.res.ColorStateList(
            new int[][] { new int[] { android.R.attr.state_checked }, new int[] {} },
            new int[] { accentInk, muted }
          ));
          row.addView(box2);
          row.setOnClickListener(v -> {
            checked[index] = !checked[index];
            box2.setChecked(checked[index]);
            if (onCheck != null) onCheck.onClick(dialog, index, checked[index]);
          });
        } else {
          row.setOnClickListener(v -> {
            dialog.dismiss();
            if (onItem != null) onItem.onClick(dialog, index);
          });
        }
        TextView t = text(label, 15, danger ? dangerColor : ink, false);
        if (checked == null || itemIcons != null || itemIcon != null) {
          String glyph = itemIcons != null && i < itemIcons.length ? itemIcons[i] : itemIcon != null ? itemIcon : "circle_check";
          int iconId = WebIcons.resolve(context, glyph);
          android.graphics.drawable.Drawable artwork = iconId != 0 ? WebIcons.load(context, glyph) : EditorIcons.drawable(context, glyph, ink);
          if (artwork != null) {
            ImageView icon = new ImageView(context);
            icon.setImageDrawable(artwork);
            icon.setColorFilter(danger ? dangerColor : accentInk);
            LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(dp(20), dp(20));
            ip.rightMargin = dp(14);
            row.addView(icon, ip);
          }
        }
        t.setTypeface(ApprovedTypography.font(context, Typeface.NORMAL));
        row.addView(t, new LinearLayout.LayoutParams(0, -2, 1));

        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
        rp.bottomMargin = dp(4); // M3 padding
        list.addView(row, rp);
      }
      box.addView(list, new LinearLayout.LayoutParams(-1, -2));
    }
    LinearLayout buttons = new LinearLayout(context);
    buttons.setPadding(0, dp(16), 0, 0);
    if (neutral != null) buttons.addView(button(dialog, neutral, onNeutral, DialogInterface.BUTTON_NEUTRAL, false), weight());
    if (negative != null) buttons.addView(button(dialog, negative, onNegative, DialogInterface.BUTTON_NEGATIVE, false), weight());
    if (positive != null) buttons.addView(button(dialog, positive, onPositive, DialogInterface.BUTTON_POSITIVE, true), weight());
    ScrollView outer = new ScrollView(context) {
      private float downY;
      private int lastDir = 1;
      @Override public boolean onInterceptTouchEvent(MotionEvent ev) {
        int action = ev.getActionMasked();
        if (action == MotionEvent.ACTION_DOWN) {
          downY = ev.getY();
        } else if (action == MotionEvent.ACTION_MOVE) {
          float y = ev.getY();
          if (y != downY) {
            lastDir = y < downY ? 1 : -1;
            downY = y;
          }
          if (hasScrollableChild(this, ev.getRawX(), ev.getRawY(), lastDir)) return false;
        }
        return super.onInterceptTouchEvent(ev);
      }
    };
    outer.setNestedScrollingEnabled(true);
    outer.setFillViewport(false);
    outer.addView(box, new ViewGroup.LayoutParams(-1, -2));
    final LinearLayout surface = new LinearLayout(context) {
      @Override
      protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int screenH = context.getResources().getDisplayMetrics().heightPixels;
        int maxTotal = screenH * 9 / 10;
        int hMode = MeasureSpec.getMode(heightMeasureSpec);
        int hSize = MeasureSpec.getSize(heightMeasureSpec);
        int limit = (hMode == MeasureSpec.UNSPECIFIED || hSize <= 0) ? maxTotal : Math.min(hSize, maxTotal);
        int wSize = MeasureSpec.getSize(widthMeasureSpec);
        int innerW = Math.max(0, wSize - getPaddingLeft() - getPaddingRight());
        int childWSpec = MeasureSpec.makeMeasureSpec(innerW, MeasureSpec.EXACTLY);
        int padV = getPaddingTop() + getPaddingBottom();
        int buttonsH = 0;
        View buttonsChild = getChildCount() > 1 ? getChildAt(1) : null;
        if (buttonsChild != null && buttonsChild.getVisibility() != GONE) {
          buttonsChild.measure(childWSpec, MeasureSpec.makeMeasureSpec(Math.max(0, limit - padV), MeasureSpec.AT_MOST));
          buttonsH = buttonsChild.getMeasuredHeight();
        }
        View outerChild = getChildCount() > 0 ? getChildAt(0) : null;
        int outerH = 0;
        if (outerChild != null && outerChild.getVisibility() != GONE) {
          int availOuter = Math.max(0, limit - padV - buttonsH);
          outerChild.measure(childWSpec, MeasureSpec.makeMeasureSpec(availOuter, MeasureSpec.AT_MOST));
          outerH = outerChild.getMeasuredHeight();
        }
        int totalH = Math.min(limit, padV + outerH + buttonsH);
        setMeasuredDimension(resolveSize(wSize, widthMeasureSpec), hMode == MeasureSpec.EXACTLY ? hSize : totalH);
      }
    };
    surface.setOrientation(LinearLayout.VERTICAL);
    surface.setBackground(shape.getConstantState().newDrawable().mutate());
    surface.setPadding(0, 0, 0, dp(12));
    surface.addView(outer, new LinearLayout.LayoutParams(-1, -2));
    if (buttons.getChildCount() > 0) {
      buttons.setPadding(dp(16), dp(6), dp(16), dp(18));
      surface.addView(buttons, new LinearLayout.LayoutParams(-1, -2));
    }
    android.content.Context unwrap = context;
    while (unwrap instanceof android.content.ContextWrapper && !(unwrap instanceof android.app.Activity)) {
      unwrap = ((android.content.ContextWrapper) unwrap).getBaseContext();
    }
    final android.app.Activity hostActivity = (unwrap instanceof android.app.Activity) ? (android.app.Activity) unwrap : null;
    surface.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
      @Override public void onViewAttachedToWindow(View v) { activeSheetCount++; }
      @Override public void onViewDetachedFromWindow(View v) {
        activeSheetCount = Math.max(0, activeSheetCount - 1);
        untrackForActivity(hostActivity, dialog);
      }
    });
    dialog.setContentView(surface);
    if (onCancel != null) dialog.setOnCancelListener(onCancel);
    if (hostActivity != null && (hostActivity.isFinishing() || hostActivity.isDestroyed())) {
      return dialog;
    }
    Window w = dialog.getWindow();
    final int width = Math.min(context.getResources().getDisplayMetrics().widthPixels, dp(560));
    if (w != null) {
      w.setBackgroundDrawable(new ColorDrawable(0));
      w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.48f);
      w.setWindowAnimations(android.R.style.Animation_InputMethod);
      w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    }
    try {
      dialog.show();
    } catch (RuntimeException badToken) {
      return dialog;
    }
    trackForActivity(hostActivity, dialog);
    if (w != null) {
      w.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
      ApprovedTypography.sheet(w.getDecorView());
      w.getDecorView().setOnApplyWindowInsetsListener((v, insets) -> {
        int leftInset, rightInset, sysBottom, imeBottom;
        if (android.os.Build.VERSION.SDK_INT >= 30) {
          android.graphics.Insets sys = insets.getInsets(WindowInsets.Type.systemBars());
          android.graphics.Insets ime = insets.getInsets(WindowInsets.Type.ime());
          leftInset = sys.left;
          rightInset = sys.right;
          sysBottom = sys.bottom;
          imeBottom = ime.bottom;
        } else {
          leftInset = insets.getSystemWindowInsetLeft();
          rightInset = insets.getSystemWindowInsetRight();
          sysBottom = insets.getSystemWindowInsetBottom();
          imeBottom = 0;
        }
        int neededBottom = (imeBottom > sysBottom) ? dp(12) : Math.max(dp(12), sysBottom);
        if (w.getAttributes() != null && w.getAttributes().height > 0) {
          w.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
        }
        surface.setPadding(leftInset, 0, rightInset, neededBottom);
        return insets;
      });
      w.getDecorView().requestApplyInsets();
    }
    return dialog;
  }

  private static boolean hasScrollableChild(ViewGroup parent, float rawX, float rawY, int dir) {
    int[] loc = new int[2];
    for (int i = parent.getChildCount() - 1; i >= 0; i--) {
      View child = parent.getChildAt(i);
      if (child.getVisibility() != View.VISIBLE) continue;
      child.getLocationOnScreen(loc);
      if (rawX < loc[0] || rawX > loc[0] + child.getWidth() || rawY < loc[1] || rawY > loc[1] + child.getHeight()) continue;
      if ((child instanceof ScrollView || child instanceof AbsListView) && child.canScrollVertically(dir)) return true;
      if (child instanceof ViewGroup && hasScrollableChild((ViewGroup) child, rawX, rawY, dir)) return true;
    }
    return false;
  }

  private LinearLayout.LayoutParams weight() {
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
    p.setMargins(dp(5), 0, dp(5), 0);
    return p;
  }

  private void styleInputIfUnstyled(EditText e) {
    android.graphics.drawable.Drawable bgDraw = e.getBackground();
    if (bgDraw instanceof android.graphics.drawable.RippleDrawable
        || bgDraw instanceof android.graphics.drawable.StateListDrawable
        || bgDraw instanceof GradientDrawable) {
      return;
    }
    styleInput(e);
  }

  private void styleInput(EditText e) {
    e.setTextColor(ink);
    e.setHintTextColor(muted);
    GradientDrawable field = round(soft, 14);
    field.setStroke(dp(1), line);
    e.setBackground(field);
    e.setTextSize(14);
    e.setPadding(dp(14), dp(13), dp(14), dp(13));
    int min = UiMetrics.dpRaw(context, 48);
    e.setMinHeight(min);
    e.setMinimumHeight(min);
    if (e.getParent() == null || e.getParent() instanceof LinearLayout) {
      LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
      p.bottomMargin = dp(8);
      e.setLayoutParams(p);
    }
    UiMetrics.enforceMinTouchTarget(e, 48);
  }

  private static boolean isDangerLabel(CharSequence raw) {
    String s = raw == null ? "" : raw.toString().trim();
    return s.startsWith("Delete") || s.startsWith("Block") || s.startsWith("Log out") || s.startsWith("Unsend")
        || s.startsWith("Leave") || s.startsWith("Unfriend") || s.startsWith("Discard")
        || s.startsWith("End ") || s.equals("End")
        || s.startsWith("Xoá") || s.startsWith("Xóa") || s.startsWith("Chặn") || s.startsWith("Đăng xuất")
        || s.startsWith("Thu hồi") || s.startsWith("Rời") || s.startsWith("Kết thúc")
        || s.startsWith("Huỷ kết bạn") || s.startsWith("Hủy kết bạn");
  }

  private Button button(Dialog dialog, CharSequence label, DialogInterface.OnClickListener l, int which, boolean primary) {
    Button b = new KinnectButton(context);
    if (which == DialogInterface.BUTTON_POSITIVE) b.setId(android.R.id.button1);
    else if (which == DialogInterface.BUTTON_NEGATIVE) b.setId(android.R.id.button2);
    else if (which == DialogInterface.BUTTON_NEUTRAL) b.setId(android.R.id.button3);
    b.setText(label);
    b.setAllCaps(false);
    int min = UiMetrics.dpRaw(context, 48);
    b.setMinHeight(min);
    b.setMinimumHeight(min);
    b.setMinWidth(min);
    b.setMinimumWidth(min);
    b.setGravity(Gravity.CENTER);
    b.setPadding(dp(14), dp(10), dp(14), dp(10));
    b.setTextSize(14);
    b.setTypeface(ApprovedTypography.font(context, Typeface.BOLD));
    b.setStateListAnimator(null);
    android.content.res.ColorStateList ripple = android.content.res.ColorStateList.valueOf(primary ? 0x33ffffff : ((accent & 0x00ffffff) | 0x22000000));
    boolean danger = isDangerLabel(label);
    if (primary) {
      int primaryFill = danger ? (dark ? 0xffb82547 : dangerColor) : (dark ? WebDesign.PURPLE[0] : accent);
      b.setBackground(new android.graphics.drawable.RippleDrawable(ripple, round(primaryFill, 999), null));
      b.setTextColor(0xffffffff);
    } else {
      GradientDrawable g = round(soft, 999);
      g.setStroke(dp(1), line);
      b.setBackground(new android.graphics.drawable.RippleDrawable(ripple, g, null));
      b.setTextColor(ink);
    }
    b.setOnClickListener(v -> {
      boolean autoDismiss = (which == DialogInterface.BUTTON_POSITIVE && autoDismissPositive)
          || (which == DialogInterface.BUTTON_NEGATIVE && autoDismissNegative)
          || (which != DialogInterface.BUTTON_POSITIVE && which != DialogInterface.BUTTON_NEGATIVE);
      if (autoDismiss) dialog.dismiss();
      if (l != null) l.onClick(dialog, which);
    });
    return b;
  }
}
