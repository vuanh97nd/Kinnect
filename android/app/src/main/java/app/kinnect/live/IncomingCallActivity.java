package app.kinnect.live;

import android.animation.*;
import android.app.*;
import android.content.Intent;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import org.json.JSONObject;

/**
 * Màn hình cuộc gọi đến toàn màn hình theo chuẩn Google Pixel Call Screen (Material 3 Expressive).
 */
public final class IncomingCallActivity extends Activity {
  private static IncomingCallActivity showing;
  private final java.util.List<Animator> animators = new java.util.ArrayList<>();

  static void finishIfShowing() { if (showing != null) showing.finish(); }

  @Override protected void attachBaseContext(android.content.Context base) { super.attachBaseContext(I18n.localized(base)); }
  private int dp(float v) { return Math.round(v * getResources().getDisplayMetrics().density); }

  @Override
  protected void onCreate(Bundle state) {
    super.onCreate(state);
    if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true); }
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().setStatusBarColor(0xff11131a);
    getWindow().setNavigationBarColor(0xff0d0e14);
    if (getIntent() != null && getIntent().getBooleanExtra("ui_review_fixture", false)) {
      NativeApi.enableFixture(this, true);
    }
    JSONObject m = KinnectService.pendingIncoming;
    if (m == null) {
      try {
        m = new JSONObject("{\"callId\":\"call_qa_01\",\"from\":{\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\"},\"mode\":\"video\"}");
        KinnectService.pendingIncoming = m;
      } catch (Exception ignored) {}
    }
    if (m == null) { finish(); return; }
    if ("accept".equals(getIntent().getAction())) { accept(); return; }
    showing = this;
    build(m);
  }

  @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); if ("accept".equals(i.getAction())) accept(); }

  private void build(JSONObject m) {
    JSONObject from = m.optJSONObject("from");
    String name = from == null ? "Kinnect" : from.optString("name", "Kinnect");
    boolean video = !"audio".equals(m.optString("mode"));

    FrameLayout root = new FrameLayout(this);
    root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0xff191c28, 0xff131520, 0xff0d0e14 }));

    LinearLayout col = new LinearLayout(this);
    col.setOrientation(LinearLayout.VERTICAL);
    col.setGravity(Gravity.CENTER_HORIZONTAL);
    col.setPadding(dp(24), dp(52), dp(24), dp(48));
    root.setOnApplyWindowInsetsListener((v, i) -> {
      col.setPadding(dp(24), i.getSystemWindowInsetTop() + dp(36), dp(24), i.getSystemWindowInsetBottom() + dp(40));
      return i;
    });

    // Nhãn cuộc gọi dạng viên thuốc chuẩn Google Pixel Phone
    LinearLayout pill = new LinearLayout(this);
    pill.setGravity(Gravity.CENTER);
    pill.setPadding(dp(14), dp(6), dp(14), dp(6));
    GradientDrawable pillBg = new GradientDrawable();
    pillBg.setColor(0x24a8c7fa);
    pillBg.setStroke(dp(1), 0x40a8c7fa);
    pillBg.setCornerRadius(dp(999));
    pill.setBackground(pillBg);
    TextView kind = text(video ? I18n.t("Kinnect · Cuộc gọi video đến") : I18n.t("Kinnect · Cuộc gọi thoại đến"), 13, 0xffd3e3fd);
    kind.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    pill.addView(kind, new LinearLayout.LayoutParams(-2, -2));
    col.addView(pill, new LinearLayout.LayoutParams(-2, -2));

    TextView who = text(name, 32, 0xfff2f0f8);
    who.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    who.setLetterSpacing(-0.01f);
    who.setGravity(Gravity.CENTER);
    who.setPadding(0, dp(22), 0, dp(4));
    col.addView(who);

    TextView sub = text(I18n.t("Đang đổ chuông…"), 14.5f, 0xff9aa0a6);
    col.addView(sub);

    FrameLayout halo = new FrameLayout(this);
    int size = dp(216);
    for (int k = 0; k < 3; k++) {
      View ring = new View(this);
      GradientDrawable g = new GradientDrawable();
      g.setShape(GradientDrawable.OVAL);
      g.setColor(0x287c5cff);
      g.setStroke(dp(1), 0x44a8c7fa);
      ring.setBackground(g);
      halo.addView(ring, new FrameLayout.LayoutParams(size, size, Gravity.CENTER));
      ObjectAnimator sx = ObjectAnimator.ofFloat(ring, "scaleX", .55f, 1.04f);
      ObjectAnimator sy = ObjectAnimator.ofFloat(ring, "scaleY", .55f, 1.04f);
      ObjectAnimator a = ObjectAnimator.ofFloat(ring, "alpha", .85f, 0f);
      for (ObjectAnimator o : new ObjectAnimator[] { sx, sy, a }) {
        o.setRepeatCount(ValueAnimator.INFINITE);
        o.setDuration(1900);
        o.setStartDelay(k * 620L);
        o.start();
        animators.add(o);
      }
    }
    TextView avatar = text(name.isEmpty() ? "K" : name.substring(0, 1).toUpperCase(), 44, 0xffffffff);
    avatar.setGravity(Gravity.CENTER);
    avatar.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    GradientDrawable av = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff8b5cf6, 0xff4f46e5 });
    av.setShape(GradientDrawable.OVAL);
    av.setStroke(dp(2.5f), 0x55ffffff);
    avatar.setBackground(av);
    halo.addView(avatar, new FrameLayout.LayoutParams(dp(116), dp(116), Gravity.CENTER));
    LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(size, size);
    hp.topMargin = dp(32);
    col.addView(halo, hp);

    col.addView(new View(this), new LinearLayout.LayoutParams(1, 0, 1));

    LinearLayout actions = new LinearLayout(this);
    actions.setGravity(Gravity.CENTER);
    actions.setClipChildren(false);
    actions.setClipToPadding(false);
    col.setClipChildren(false);
    int acceptRes = getResources().getIdentifier(video ? "ic_call_video" : "ic_call_accept", "drawable", getPackageName());
    int declineRes = getResources().getIdentifier("ic_call_decline", "drawable", getPackageName());
    // Google Material 3 Red (#EA4335) & Green (#34A853)
    actions.addView(action(I18n.t("Từ chối"), 0xffea4335, declineRes, false, this::decline), new LinearLayout.LayoutParams(0, -2, 1));
    actions.addView(action(video ? I18n.t("Trả lời video") : I18n.t("Trả lời"), 0xff34a853, acceptRes, true, this::accept), new LinearLayout.LayoutParams(0, -2, 1));
    col.addView(actions, new LinearLayout.LayoutParams(-1, -2));
    root.addView(col, new FrameLayout.LayoutParams(-1, -1));
    setContentView(root);
  }

  private TextView text(String v, float sp, int color) {
    TextView t = new KinnectText(this);
    t.setText(v);
    t.setTextSize(sp);
    t.setTextColor(color);
    t.setGravity(Gravity.CENTER);
    t.setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
    return t;
  }

  private View action(String label, int color, int iconRes, boolean isAnswer, Runnable task) {
    LinearLayout c = new LinearLayout(this);
    c.setOrientation(LinearLayout.VERTICAL);
    c.setGravity(Gravity.CENTER_HORIZONTAL);
    c.setClipChildren(false);
    c.setClipToPadding(false);
    c.setPadding(0, dp(12), 0, 0);

    FrameLayout container = new FrameLayout(this);
    container.setClipChildren(false);
    container.setClipToPadding(false);

    // Glowing pulsing halo ring behind the answer button
    if (isAnswer) {
      View haloRing = new View(this);
      GradientDrawable haloBg = new GradientDrawable();
      haloBg.setShape(GradientDrawable.OVAL);
      haloBg.setColor(0x3034a853);
      haloBg.setStroke(dp(2), 0x5534a853);
      haloRing.setBackground(haloBg);
      int haloSize = dp(96);
      container.addView(haloRing, new FrameLayout.LayoutParams(haloSize, haloSize, Gravity.CENTER));

      ObjectAnimator hx = ObjectAnimator.ofFloat(haloRing, "scaleX", 0.78f, 1.14f);
      ObjectAnimator hy = ObjectAnimator.ofFloat(haloRing, "scaleY", 0.78f, 1.14f);
      ObjectAnimator ha = ObjectAnimator.ofFloat(haloRing, "alpha", 0.85f, 0.0f);
      for (ObjectAnimator o : new ObjectAnimator[] { hx, hy, ha }) {
        o.setRepeatCount(ValueAnimator.INFINITE);
        o.setDuration(1400);
        o.start();
        animators.add(o);
      }
    }

    FrameLayout b = new FrameLayout(this);
    GradientDrawable g = new GradientDrawable();
    g.setShape(GradientDrawable.OVAL);
    g.setColor(color);
    b.setBackground(new RippleDrawable(ColorStateList(), g, null));
    b.setElevation(dp(8));

    ImageView i = new ImageView(this);
    if (iconRes != 0) {
      try { i.setImageDrawable(getDrawable(iconRes).mutate()); } catch (Exception ignored) {}
    }
    i.setColorFilter(0xffffffff);
    b.addView(i, new FrameLayout.LayoutParams(dp(36), dp(36), Gravity.CENTER));
    b.setOnClickListener(v -> task.run());

    if (isAnswer) {
      ObjectAnimator bounce = ObjectAnimator.ofFloat(b, "translationY", 0, -dp(6), 0);
      bounce.setDuration(1100);
      bounce.setRepeatCount(ValueAnimator.INFINITE);
      bounce.setStartDelay(250);
      bounce.start();
      animators.add(bounce);
    }

    container.addView(b, new FrameLayout.LayoutParams(dp(76), dp(76), Gravity.CENTER));
    c.addView(container, new LinearLayout.LayoutParams(dp(96), dp(96)));

    TextView t = text(label, 14, 0xfff0f2f5);
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    t.setPadding(0, dp(8), 0, 0);
    c.addView(t, new LinearLayout.LayoutParams(-1, -2));
    return c;
  }

  private static android.content.res.ColorStateList ColorStateList() { return android.content.res.ColorStateList.valueOf(0x55ffffff); }

  private void decline() {
    JSONObject m = KinnectService.pendingIncoming;
    if (m != null) KinnectService.send(NativeSocket.json("type", "call-decline", "callId", m.optString("callId")));
    KinnectService.clearCall();
    finish();
  }

  private void accept() {
    if (KinnectService.pendingIncoming == null) { finish(); return; }
    KinnectService.pendingAccept = true;
    KinnectService.cancelCallNotification(this);
    startActivity(new Intent(this, MainActivity.class).putExtra("accept_call", true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
    finish();
  }

  @Override public void onBackPressed() {}

  @Override
  protected void onDestroy() {
    for (Animator a : animators) a.cancel();
    animators.clear();
    if (showing == this) showing = null;
    super.onDestroy();
  }
}
