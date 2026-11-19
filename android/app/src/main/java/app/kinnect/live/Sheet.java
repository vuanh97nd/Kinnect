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
  private CharSequence[] items;
  private String[] itemIcons;
  private String itemIcon;
  private boolean[] checked;
  private DialogInterface.OnMultiChoiceClickListener onCheck;
  private View view;
  private boolean cancelable = true;
  private final int bg, ink, muted, soft, line, accent, dangerColor;

  Sheet(Context context) {
    this.context = context;
    boolean dark = WebTheme.isDark(context);
    int variant = dark ? 1 : 0;
    bg = WebDesign.CARD[variant]; ink = WebDesign.INK[variant]; muted = WebDesign.MUTED[variant];
    soft = WebDesign.WASH[variant]; line = WebDesign.LINE[variant];
    accent = WebDesign.PURPLE[variant]; dangerColor = WebDesign.DANGER[variant];
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
      if (view instanceof EditText) styleInput((EditText) view);
      if (view instanceof ViewGroup) for (int i = 0; i < ((ViewGroup) view).getChildCount(); i++) {
        View c = ((ViewGroup) view).getChildAt(i);
        if (c instanceof EditText) styleInput((EditText) c);
        else if (c instanceof TextView && !(c instanceof Button)) ((TextView) c).setTextColor(ink);
      }
      if (view.getParent() != null) ((ViewGroup) view.getParent()).removeView(view);
      if (!(view instanceof EditText)) view.setPadding(0, view.getPaddingTop(), 0, view.getPaddingBottom());
      box.addView(view);
    }
    if (items != null) {
      ScrollView scroll = new ScrollView(context);
      LinearLayout list = new LinearLayout(context);
      list.setOrientation(LinearLayout.VERTICAL);
      scroll.addView(list);
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
        boolean danger = label.startsWith("Delete") || label.startsWith("Block") || label.startsWith("Log out") || label.startsWith("Unsend") || label.startsWith("Leave") || label.startsWith("Xoá") || label.startsWith("Xóa") || label.startsWith("Chặn") || label.startsWith("Đăng xuất") || label.startsWith("Thu hồi") || label.startsWith("Rời");
        if (checked != null) {
          final CheckBox box2 = new CheckBox(context);
          box2.setChecked(checked[i]);
          box2.setClickable(false);
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
            icon.setColorFilter(danger ? dangerColor : accent);
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
      int max = context.getResources().getDisplayMetrics().heightPixels * 6 / 10;
      box.addView(scroll, new LinearLayout.LayoutParams(-1, Math.min(max, items.length * dp(60))));
    }
    LinearLayout buttons = new LinearLayout(context);
    buttons.setPadding(0, dp(16), 0, 0);
    if (neutral != null) buttons.addView(button(dialog, neutral, onNeutral, DialogInterface.BUTTON_NEUTRAL, false), weight());
    if (negative != null) buttons.addView(button(dialog, negative, onNegative, DialogInterface.BUTTON_NEGATIVE, false), weight());
    if (positive != null) buttons.addView(button(dialog, positive, onPositive, DialogInterface.BUTTON_POSITIVE, true), weight());
    ScrollView outer = new ScrollView(context);
    outer.setFillViewport(false);
    outer.addView(box);
    LinearLayout surface = new LinearLayout(context);
    surface.setOrientation(LinearLayout.VERTICAL);
    surface.setBackground(shape.getConstantState().newDrawable().mutate());
    surface.addView(outer, new LinearLayout.LayoutParams(-1, 0, 1));
    if (buttons.getChildCount() > 0) {
      buttons.setPadding(dp(16), dp(6), dp(16), dp(18));
      surface.addView(buttons, new LinearLayout.LayoutParams(-1, -2));
    }
    dialog.setContentView(surface);
    dialog.show();
    Window w = dialog.getWindow();
    if (w != null) {
      w.setBackgroundDrawable(new ColorDrawable(0));
      int width = Math.min(context.getResources().getDisplayMetrics().widthPixels, dp(560));
      int spec = View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY);
      box.measure(spec, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
      buttons.measure(spec, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
      int height = Math.min(context.getResources().getDisplayMetrics().heightPixels * 9 / 10, box.getMeasuredHeight() + (buttons.getChildCount() > 0 ? buttons.getMeasuredHeight() : 0) + dp(24));
      w.setLayout(width, height);
      ApprovedTypography.sheet(w.getDecorView());
      w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.48f);
      w.setWindowAnimations(android.R.style.Animation_InputMethod);
      w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
      w.getDecorView().setOnApplyWindowInsetsListener((v, insets) -> {
        if (android.os.Build.VERSION.SDK_INT >= 30) {
          android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
          surface.setPadding(bars.left, 0, bars.right, Math.max(dp(12), bars.bottom));
        } else {
          surface.setPadding(insets.getSystemWindowInsetLeft(), 0, insets.getSystemWindowInsetRight(), Math.max(dp(12), insets.getSystemWindowInsetBottom()));
        }
        return insets;
      });
      w.getDecorView().requestApplyInsets();
    }
    return dialog;
  }

  private LinearLayout.LayoutParams weight() {
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
    p.setMargins(dp(5), 0, dp(5), 0);
    return p;
  }

  private void styleInput(EditText e) {
    e.setTextColor(ink);
    e.setHintTextColor(muted);
    GradientDrawable field = round(soft, 14);
    field.setStroke(dp(1), line);
    e.setBackground(field);
    e.setTextSize(14);
    e.setPadding(dp(14), dp(13), dp(14), dp(13));
    if (e.getParent() == null || e.getParent() instanceof LinearLayout) {
      LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
      p.bottomMargin = dp(8);
      e.setLayoutParams(p);
    }
  }

  private Button button(Dialog dialog, CharSequence label, DialogInterface.OnClickListener l, int which, boolean primary) {
    Button b = new KinnectButton(context);
    b.setText(label);
    b.setAllCaps(false);
    b.setMinHeight(dp(46));
    b.setPadding(dp(14), dp(10), dp(14), dp(10));
    b.setTextSize(14);
    b.setTypeface(ApprovedTypography.font(context, Typeface.BOLD));
    b.setStateListAnimator(null);
    android.content.res.ColorStateList ripple = android.content.res.ColorStateList.valueOf(primary ? 0x33ffffff : ((accent & 0x00ffffff) | 0x22000000));
    boolean danger = label.toString().startsWith("Delete") || label.toString().startsWith("Block") || label.toString().startsWith("Log out") || label.toString().startsWith("Unsend") || label.toString().startsWith("Xoá") || label.toString().startsWith("Xóa") || label.toString().startsWith("Chặn") || label.toString().startsWith("Đăng xuất") || label.toString().startsWith("Thu hồi");
    if (primary) {
      b.setBackground(new android.graphics.drawable.RippleDrawable(ripple, round(danger ? dangerColor : accent, 999), null));
      b.setTextColor(0xffffffff);
    } else {
      GradientDrawable g = round(soft, 999);
      g.setStroke(dp(1), line);
      b.setBackground(new android.graphics.drawable.RippleDrawable(ripple, g, null));
      b.setTextColor(ink);
    }
    b.setOnClickListener(v -> { dialog.dismiss(); if (l != null) l.onClick(dialog, which); });
    return b;
  }
}
