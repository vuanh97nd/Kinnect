package app.kinnect.live;

import android.app.Dialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.view.*;
import android.widget.*;

/**
 * Bảng trượt từ dưới lên theo phong cách Kinnect (bo góc, màu theme web) thay cho AlertDialog mặc định.
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
  private final int bg, ink, muted, soft, line;

  Sheet(Context context) {
    this.context = context;
    boolean dark = WebTheme.isDark(context);
    int variant = dark ? 1 : 0;
    bg = WebDesign.CARD[variant]; ink = WebDesign.INK[variant]; muted = WebDesign.MUTED[variant];
    soft = WebDesign.WASH[variant]; line = WebDesign.LINE[variant];
  }

  Sheet setTitle(CharSequence t) { title = t; return this; }
  Sheet setMessage(CharSequence m) { message = m; return this; }
  Sheet setView(View v) { view = v; return this; }
  Sheet setItems(CharSequence[] list, DialogInterface.OnClickListener l) { items = list; onItem = l; return this; }
  Sheet setItemIcon(String icon) { itemIcon=icon; return this; }
  Sheet setItemIcons(String[] icons) { itemIcons = icons; return this; }
  Sheet setMultiChoiceItems(CharSequence[] list, boolean[] state, DialogInterface.OnMultiChoiceClickListener l) { items = list; checked = state; onCheck = l; return this; }
  Sheet setPositiveButton(CharSequence t, DialogInterface.OnClickListener l) { positive = t; onPositive = l; return this; }
  Sheet setNegativeButton(CharSequence t, DialogInterface.OnClickListener l) { negative = t; onNegative = l; return this; }
  Sheet setNeutralButton(CharSequence t, DialogInterface.OnClickListener l) { neutral = t; onNeutral = l; return this; }
  Sheet setCancelable(boolean ignored) { return this; }

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
    if (bold) t.setTypeface(null, Typeface.BOLD);
    return t;
  }

  Dialog show() {
    final Dialog dialog = new Dialog(context);
    dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
    LinearLayout box = new LinearLayout(context);
    box.setOrientation(LinearLayout.VERTICAL);
    box.setPadding(dp(20), dp(10), dp(20), dp(20));
    GradientDrawable shape = new GradientDrawable();
    shape.setColor(bg);
    float r = dp(26);
    shape.setCornerRadii(new float[] { r, r, r, r, 0, 0, 0, 0 });
    box.setBackground(shape);
    // Thanh kéo nhỏ ở đầu như bottom sheet
    View grip = new View(context);
    grip.setBackground(round(line, 99));
    LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(dp(36), dp(4));
    gp.gravity = Gravity.CENTER_HORIZONTAL;
    gp.bottomMargin = dp(14);
    box.addView(grip, gp);
    if (title != null && title.length() > 0) {
      TextView t = text(title, 16, ink, true);
      t.setTag("sheet:title");t.setPadding(0, dp(2), 0, dp(8));
      box.addView(t);
    }
    if (message != null) {
      TextView m = text(message, 13, muted, false);
      m.setPadding(0, 0, 0, dp(14));
      m.setLineSpacing(0, 1.3f);
      box.addView(m);
    }
    if (view != null) {
      if (view instanceof EditText) styleInput((EditText) view);
      if (view instanceof ViewGroup) for (int i = 0; i < ((ViewGroup) view).getChildCount(); i++) {
        View c = ((ViewGroup) view).getChildAt(i);
        if (c instanceof EditText) styleInput((EditText) c);
        else if (c instanceof TextView) ((TextView) c).setTextColor(ink);
      }
      if (view.getParent() != null) ((ViewGroup) view.getParent()).removeView(view);
      if(!(view instanceof EditText))view.setPadding(0, view.getPaddingTop(), 0, view.getPaddingBottom());
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
        row.setPadding(dp(14), dp(12), dp(14), dp(12));
        row.setMinimumHeight(dp(54));
        row.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x226c47e0), round(bg, 12), round(0xff000000, 12)));
        String label = String.valueOf(items[i]);
        boolean danger = label.startsWith("Delete") || label.startsWith("Block") || label.startsWith("Log out") || label.startsWith("Unsend") || label.startsWith("Leave") || label.startsWith("Xoá") || label.startsWith("Xóa") || label.startsWith("Chặn") || label.startsWith("Đăng xuất") || label.startsWith("Thu hồi") || label.startsWith("Rời");
        if (checked != null) {
          final CheckBox box2 = new CheckBox(context);
          box2.setChecked(checked[i]);
          box2.setClickable(false);
          row.addView(box2);
          row.setOnClickListener(v -> { checked[index] = !checked[index]; box2.setChecked(checked[index]); if (onCheck != null) onCheck.onClick(dialog, index, checked[index]); });
        } else row.setOnClickListener(v -> { dialog.dismiss(); if (onItem != null) onItem.onClick(dialog, index); });
        TextView t = text(label, 13, danger ? 0xffe0245e : ink, false);
        if (checked == null || itemIcons != null || itemIcon != null) {
          String glyph=itemIcons!=null&&i<itemIcons.length?itemIcons[i]:itemIcon!=null?itemIcon:"circle_check";
          int iconId = WebIcons.resolve(context,glyph);
          android.graphics.drawable.Drawable artwork=iconId!=0?WebIcons.load(context,glyph):EditorIcons.drawable(context,glyph,ink);
          if (artwork != null) {
            ImageView icon = new ImageView(context);
            icon.setImageDrawable(artwork);
            icon.setColorFilter(danger ? 0xffe0245e : ink);
            LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(dp(21), dp(21));
            ip.rightMargin = dp(14);
            row.addView(icon, ip);
          }
        }
        t.setTypeface(ApprovedTypography.font(context,Typeface.NORMAL));
        row.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
        if (i > 0) {
          View sep = new View(context);
          sep.setBackgroundColor(line);
          LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, 1);
          sp.setMargins(dp(14), 0, dp(14), 0);
          list.addView(sep, sp);
        }
        list.addView(row, new LinearLayout.LayoutParams(-1, -2));
      }
      int max = context.getResources().getDisplayMetrics().heightPixels * 6 / 10;
      box.addView(scroll, new LinearLayout.LayoutParams(-1, Math.min(max, items.length * dp(56))));
    }
    LinearLayout buttons = new LinearLayout(context);
    buttons.setPadding(0, dp(12), 0, 0);
    if (neutral != null) buttons.addView(button(dialog, neutral, onNeutral, DialogInterface.BUTTON_NEUTRAL, false), weight());
    if (negative != null) buttons.addView(button(dialog, negative, onNegative, DialogInterface.BUTTON_NEGATIVE, false), weight());
    if (positive != null) buttons.addView(button(dialog, positive, onPositive, DialogInterface.BUTTON_POSITIVE, true), weight());
    if (buttons.getChildCount() > 0) box.addView(buttons);
    ScrollView outer=new ScrollView(context);outer.setFillViewport(false);outer.addView(box);dialog.setContentView(outer);
    dialog.show();
    Window w = dialog.getWindow();
    if (w != null) {
      w.setBackgroundDrawable(new ColorDrawable(0));
      w.setLayout(Math.min(context.getResources().getDisplayMetrics().widthPixels, dp(560)), ViewGroup.LayoutParams.WRAP_CONTENT);
      ApprovedTypography.sheet(w.getDecorView());w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.5f);
      w.setWindowAnimations(android.R.style.Animation_InputMethod);
      w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
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
    GradientDrawable field = round(bg, 14);
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
    b.setMinHeight(dp(50));
    b.setPadding(dp(10),dp(12),dp(10),dp(12));
    b.setTextSize(15);
    b.setTypeface(ApprovedTypography.font(context,Typeface.BOLD));
    b.setStateListAnimator(null);
    android.content.res.ColorStateList ripple = android.content.res.ColorStateList.valueOf(primary ? 0x33ffffff : 0x226c47e0);
    boolean danger = label.toString().startsWith("Delete") || label.toString().startsWith("Block") || label.toString().startsWith("Log out") || label.toString().startsWith("Unsend") || label.toString().startsWith("Xoá") || label.toString().startsWith("Xóa") || label.toString().startsWith("Chặn") || label.toString().startsWith("Đăng xuất") || label.toString().startsWith("Thu hồi");
    if (primary) {
      b.setBackground(new android.graphics.drawable.RippleDrawable(ripple, round(danger ? 0xffe0245e : 0xff6c47e0, 14), null));
      b.setTextColor(0xffffffff);
    } else {
      GradientDrawable g = round(bg, 14);
      g.setStroke(dp(1), line);
      b.setBackground(new android.graphics.drawable.RippleDrawable(ripple, g, null));
      b.setTextColor(ink);
    }
    b.setOnClickListener(v -> { dialog.dismiss(); if (l != null) l.onClick(dialog, which); });
    return b;
  }
}
