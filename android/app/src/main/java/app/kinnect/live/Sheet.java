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
  private boolean[] checked;
  private DialogInterface.OnMultiChoiceClickListener onCheck;
  private View view;
  private final int bg, ink, muted, soft, line;

  Sheet(Context context) {
    this.context = context;
    boolean dark = (context.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
    bg = dark ? 0xff242526 : 0xffffffff;
    ink = dark ? 0xffe4e6eb : 0xff1c1e21;
    muted = dark ? 0xffb0b3b8 : 0xff65676b;
    soft = dark ? 0xff3a3b3c : 0xfff2f3f5;
    line = dark ? 0xff3a3b3c : 0xffe4e6eb;
  }

  Sheet setTitle(CharSequence t) { title = t; return this; }
  Sheet setMessage(CharSequence m) { message = m; return this; }
  Sheet setView(View v) { view = v; return this; }
  Sheet setItems(CharSequence[] list, DialogInterface.OnClickListener l) { items = list; onItem = l; return this; }
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
    TextView t = new TextView(context);
    t.setText(s);
    t.setTextSize(size);
    t.setTextColor(color);
    if (bold) t.setTypeface(null, Typeface.BOLD);
    return t;
  }

  Dialog show() {
    final Dialog dialog = new Dialog(context);
    dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
    LinearLayout box = new LinearLayout(context);
    box.setOrientation(LinearLayout.VERTICAL);
    box.setPadding(dp(18), dp(10), dp(18), dp(18));
    GradientDrawable shape = new GradientDrawable();
    shape.setColor(bg);
    float r = dp(22);
    shape.setCornerRadii(new float[] { r, r, r, r, 0, 0, 0, 0 });
    box.setBackground(shape);
    // Thanh kéo nhỏ ở đầu như bottom sheet
    View grip = new View(context);
    grip.setBackground(round(line, 99));
    LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(dp(40), dp(5));
    gp.gravity = Gravity.CENTER_HORIZONTAL;
    gp.bottomMargin = dp(10);
    box.addView(grip, gp);
    if (title != null && title.length() > 0) {
      TextView t = text(title, 18, ink, true);
      t.setPadding(0, dp(4), 0, dp(6));
      box.addView(t);
    }
    if (message != null) {
      TextView m = text(message, 15, muted, false);
      m.setPadding(0, 0, 0, dp(10));
      m.setLineSpacing(0, 1.15f);
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
      view.setPadding(0, view.getPaddingTop(), 0, view.getPaddingBottom());
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
        row.setPadding(dp(14), 0, dp(14), 0);
        row.setBackground(round(soft, 14));
        String label = String.valueOf(items[i]);
        boolean danger = label.startsWith("Xoá") || label.startsWith("Xóa") || label.startsWith("Chặn") || label.startsWith("Đăng xuất") || label.startsWith("Thu hồi") || label.startsWith("Rời");
        if (checked != null) {
          final CheckBox box2 = new CheckBox(context);
          box2.setChecked(checked[i]);
          box2.setClickable(false);
          row.addView(box2);
          row.setOnClickListener(v -> { checked[index] = !checked[index]; box2.setChecked(checked[index]); if (onCheck != null) onCheck.onClick(dialog, index, checked[index]); });
        } else row.setOnClickListener(v -> { dialog.dismiss(); if (onItem != null) onItem.onClick(dialog, index); });
        TextView t = text(label, 16, danger ? 0xffe0245e : ink, false);
        row.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, dp(50));
        rp.bottomMargin = dp(6);
        list.addView(row, rp);
      }
      int max = context.getResources().getDisplayMetrics().heightPixels * 6 / 10;
      box.addView(scroll, new LinearLayout.LayoutParams(-1, Math.min(max, items.length * dp(56))));
    }
    LinearLayout buttons = new LinearLayout(context);
    buttons.setPadding(0, dp(8), 0, 0);
    if (neutral != null) buttons.addView(button(dialog, neutral, onNeutral, DialogInterface.BUTTON_NEUTRAL, false), weight());
    if (negative != null) buttons.addView(button(dialog, negative, onNegative, DialogInterface.BUTTON_NEGATIVE, false), weight());
    if (positive != null) buttons.addView(button(dialog, positive, onPositive, DialogInterface.BUTTON_POSITIVE, true), weight());
    if (buttons.getChildCount() > 0) box.addView(buttons);
    dialog.setContentView(box);
    Window w = dialog.getWindow();
    if (w != null) {
      w.setBackgroundDrawable(new ColorDrawable(0));
      w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
      w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.45f);
      w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    }
    dialog.show();
    return dialog;
  }

  private LinearLayout.LayoutParams weight() {
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, dp(48), 1);
    p.setMargins(dp(4), 0, dp(4), 0);
    return p;
  }

  private void styleInput(EditText e) {
    e.setTextColor(ink);
    e.setHintTextColor(muted);
    e.setBackground(round(soft, 12));
    e.setPadding(dp(14), dp(12), dp(14), dp(12));
    ViewGroup.MarginLayoutParams p = new ViewGroup.MarginLayoutParams(-1, -2);
    p.bottomMargin = dp(8);
    e.setLayoutParams(new LinearLayout.LayoutParams(p));
  }

  private Button button(Dialog dialog, CharSequence label, DialogInterface.OnClickListener l, int which, boolean primary) {
    Button b = new Button(context);
    b.setText(label);
    b.setAllCaps(false);
    b.setTextSize(15);
    b.setTypeface(null, Typeface.BOLD);
    b.setStateListAnimator(null);
    if (primary) {
      GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6d4aff, 0xffff4f9a });
      g.setCornerRadius(dp(12));
      b.setBackground(g);
      b.setTextColor(0xffffffff);
    } else {
      b.setBackground(round(soft, 12));
      b.setTextColor(ink);
    }
    b.setOnClickListener(v -> { dialog.dismiss(); if (l != null) l.onClick(dialog, which); });
    return b;
  }
}
