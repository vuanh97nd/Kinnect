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
 * Màn hình cuộc gọi đến toàn màn hình theo chuẩn Google Pixel Call Screen
 * (Material 3 Expressive).
 */
public final class IncomingCallActivity extends Activity {
  private static IncomingCallActivity showing;
  private boolean uiBuilt;
  private Dialog quickReplySheet;
  private final java.util.List<Animator> animators = new java.util.ArrayList<>();

  static boolean isShowing() {
    return showing != null && !showing.isFinishing() && !showing.isDestroyed();
  }

  static void finishIfShowing() {
    if (showing != null)
      showing.finish();
  }

  @Override
  protected void attachBaseContext(android.content.Context base) {
    super.attachBaseContext(I18n.localized(base));
  }

  private int dp(float v) {
    return Math.round(v * getResources().getDisplayMetrics().density);
  }

  @Override
  protected void onCreate(Bundle state) {
    super.onCreate(state);
    if (Build.VERSION.SDK_INT >= 27) {
      setShowWhenLocked(true);
      setTurnScreenOn(true);
    }
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
        | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        | WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
    getWindow().setStatusBarColor(Color.TRANSPARENT);
    getWindow().setNavigationBarColor(Color.TRANSPARENT);
    getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
    final boolean isDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (isDebug && getIntent() != null && getIntent().getBooleanExtra("ui_review_fixture", false)) {
      NativeApi.enableFixture(this, true);
    }
    JSONObject m = KinnectService.pendingIncoming;
    if (m == null && getIntent() != null) {
      String extraPayload = getIntent().getStringExtra("callPayload");
      if (extraPayload != null && !extraPayload.isEmpty()) {
        try {
          NativeCallEnds.initialize(this);
          JSONObject parsed = new JSONObject(extraPayload);
          String cid = parsed.optString("callId");
          if (cid.isEmpty() || !NativeCallEnds.contains(cid)) {
            m = parsed;
            KinnectService.pendingIncoming = m;
            KinnectService.start(this);
          }
        } catch (Exception ignored) {
        }
      }
    }
    if (m == null && isDebug && NativeApi.isFixtureEnabled()) {
      try {
        m = new JSONObject(
            "{\"callId\":\"call_qa_01\",\"from\":{\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\"},\"mode\":\"video\"}");
        KinnectService.pendingIncoming = m;
      } catch (Exception ignored) {
      }
    }
    if (m == null) {
      finish();
      return;
    }
    showing = this;
    if ("accept".equals(getIntent().getAction())) {
      accept();
      return;
    }
    build(m);
  }

  @Override
  protected void onNewIntent(Intent i) {
    super.onNewIntent(i);
    if (i == null)
      return;
    setIntent(i);
    if ("accept".equals(i.getAction())) {
      accept();
      return;
    }
    String extraPayload = i.getStringExtra("callPayload");
    if (extraPayload != null && !extraPayload.isEmpty()) {
      try {
        NativeCallEnds.initialize(this);
        JSONObject parsed = new JSONObject(extraPayload);
        String cid = parsed.optString("callId");
        if (cid.isEmpty() || !NativeCallEnds.contains(cid)) {
          KinnectService.pendingIncoming = parsed;
          for (Animator a : animators)
            a.cancel();
          animators.clear();
          build(parsed);
        }
      } catch (Exception ignored) {
      }
    }
  }

  private void build(JSONObject m) {
    uiBuilt = true;
    JSONObject from = m.optJSONObject("from");
    String name = from == null ? "Kinnect" : from.optString("name", "Kinnect");
    boolean video = !"audio".equals(m.optString("mode"));

    FrameLayout root = new FrameLayout(this);
    root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
        new int[] { 0xff191c28, 0xff131520, 0xff0d0e14 }));

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
    TextView kind = text(video ? I18n.t("Kinnect · Cuộc gọi video đến") : I18n.t("Kinnect · Cuộc gọi thoại đến"), 13,
        0xffd3e3fd);
    kind.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    pill.addView(kind, new LinearLayout.LayoutParams(-2, -2));
    col.addView(pill, new LinearLayout.LayoutParams(-2, -2));

    TextView who = text(name, 32, 0xfff2f0f8);
    who.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    who.setLetterSpacing(-0.01f);
    who.setGravity(Gravity.CENTER);
    who.setMaxLines(2);
    who.setEllipsize(android.text.TextUtils.TruncateAt.END);
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
    GradientDrawable av = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
        new int[] { 0xff6d28d9, 0xff4f46e5 });
    av.setShape(GradientDrawable.OVAL);
    av.setStroke(dp(2.5f), 0x55ffffff);
    avatar.setBackground(av);
    halo.addView(avatar, new FrameLayout.LayoutParams(dp(116), dp(116), Gravity.CENTER));
    LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(size, size);
    hp.topMargin = dp(32);
    col.addView(halo, hp);

    col.addView(new View(this), new LinearLayout.LayoutParams(1, 0, 1));

    LinearLayout secondaryRow = new LinearLayout(this);
    secondaryRow.setGravity(Gravity.CENTER);
    int availSecondaryW = Math.max(UiMetrics.dpRaw(this, 240),
        getResources().getDisplayMetrics().widthPixels - dp(48));
    int pillMaxTextW = video
        ? Math.max(UiMetrics.dpRaw(this, 48), (availSecondaryW - dp(12)) / 2 - dp(58))
        : Math.max(UiMetrics.dpRaw(this, 96), availSecondaryW - dp(58));
    String msgGlyph = WebIcons.resolve(this, "message_circle") != 0 ? "message_circle" : "message_square";
    LinearLayout msgBtn = secondaryPill(msgGlyph, I18n.t("Nhắn tin"), pillMaxTextW, () -> openQuickReply(m));
    LinearLayout.LayoutParams msgLp = new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48));
    if (video) {
      msgLp.rightMargin = dp(12);
      secondaryRow.addView(msgBtn, msgLp);
      UiMetrics.enforceMinTouchTarget(msgBtn, 48);
      msgBtn.setMinimumWidth(UiMetrics.dpRaw(this, 96));
      String audioGlyph = WebIcons.resolve(this, "phone") != 0 ? "phone" : "ic_call_phone";
      LinearLayout audioBtn = secondaryPill(audioGlyph, I18n.t("Chỉ âm thanh"), pillMaxTextW, this::acceptAudioOnly);
      LinearLayout.LayoutParams audioLp = new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48));
      secondaryRow.addView(audioBtn, audioLp);
      UiMetrics.enforceMinTouchTarget(audioBtn, 48);
      audioBtn.setMinimumWidth(UiMetrics.dpRaw(this, 96));
    } else {
      secondaryRow.addView(msgBtn, msgLp);
      UiMetrics.enforceMinTouchTarget(msgBtn, 48);
      msgBtn.setMinimumWidth(UiMetrics.dpRaw(this, 96));
    }
    LinearLayout.LayoutParams secLp = new LinearLayout.LayoutParams(-1, -2);
    secLp.bottomMargin = dp(18);
    col.addView(secondaryRow, secLp);

    LinearLayout actions = new LinearLayout(this);
    actions.setGravity(Gravity.CENTER);
    actions.setClipChildren(false);
    actions.setClipToPadding(false);
    col.setClipChildren(false);
    int acceptRes = getResources().getIdentifier(video ? "ic_call_video" : "ic_call_accept", "drawable",
        getPackageName());
    int declineRes = getResources().getIdentifier("ic_call_decline", "drawable", getPackageName());
    actions.addView(action(I18n.t("Từ chối"), WebDesign.LIVE_RED, declineRes, false, this::decline),
        new LinearLayout.LayoutParams(0, -2, 1));
    actions.addView(
        action(video ? I18n.t("Trả lời video") : I18n.t("Trả lời"), WebDesign.ONLINE_STRICT[0], acceptRes, true,
            this::accept),
        new LinearLayout.LayoutParams(0, -2, 1));
    col.addView(actions, new LinearLayout.LayoutParams(-1, -2));
    root.addView(col, new FrameLayout.LayoutParams(-1, -1));
    setContentView(root);
  }

  private LinearLayout secondaryPill(String iconName, String label, int maxTextWidth, Runnable onClick) {
    LinearLayout pill = new LinearLayout(this);
    pill.setGravity(Gravity.CENTER);
    pill.setPadding(dp(14), dp(8), dp(14), dp(8));
    pill.setMinimumWidth(UiMetrics.dpRaw(this, 96));
    pill.setMinimumHeight(UiMetrics.dpRaw(this, 48));
    GradientDrawable bg = new GradientDrawable();
    bg.setColor(0x24ffffff);
    bg.setStroke(dp(1), 0x33ffffff);
    bg.setCornerRadius(dp(16));
    pill.setBackground(new RippleDrawable(android.content.res.ColorStateList.valueOf(0x44ffffff), bg, null));
    Drawable iconDrawable = WebIcons.resolve(this, iconName) != 0
        ? WebIcons.load(this, iconName)
        : EditorIcons.drawable(this, iconName, 0xfff8f7fc);
    if (iconDrawable != null) {
      Drawable tinted = iconDrawable.mutate();
      tinted.setTint(0xfff8f7fc);
      ImageView ic = new ImageView(this);
      ic.setImageDrawable(tinted);
      pill.addView(ic, new LinearLayout.LayoutParams(dp(20), dp(20)));
    }
    TextView tv = text(label, 12.5f, 0xfff8f7fc);
    tv.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
    tv.setSingleLine(true);
    tv.setEllipsize(android.text.TextUtils.TruncateAt.END);
    tv.setMaxWidth(maxTextWidth);
    LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(-2, -2);
    tlp.leftMargin = dp(8);
    pill.addView(tv, tlp);
    pill.setContentDescription(label);
    pill.setOnClickListener(v -> onClick.run());
    return pill;
  }

  private void openQuickReply(JSONObject m) {
    if (isFinishing() || isDestroyed())
      return;
    if (quickReplySheet != null && quickReplySheet.isShowing()) {
      try {
        quickReplySheet.dismiss();
      } catch (Exception ignored) {
      }
    }
    final String[] presets = new String[] {
        I18n.t("Tôi sẽ gọi lại sau."),
        I18n.t("Đang bận, nhắn tin nhé!"),
        I18n.t("Tôi đang trong cuộc họp.")
    };
    final JSONObject fromObj = m != null ? m.optJSONObject("from") : null;
    final String peerId = fromObj != null ? fromObj.optString("id") : "";
    String sheetIcon = WebIcons.resolve(this, "message_circle") != 0 ? "message_circle" : "message_square";
    quickReplySheet = new Sheet(this)
        .setTitle(I18n.t("Trả lời nhanh"))
        .setItemIcon(sheetIcon)
        .setItems(presets, (d, idx) -> {
          if (idx < 0 || idx >= presets.length)
            return;
          final String msgText = presets[idx];
          if (!peerId.isEmpty() && !NativeApi.isFixtureEnabled()) {
            NativeApi.shared.initialize(getApplicationContext(), ServerConfig.DEFAULT_ORIGIN);
            NativeApi.shared.call("POST", "/api/users/" + peerId + "/messages",
                NativeSocket.json("body", msgText, "text", msgText,
                    "requestId", java.util.UUID.randomUUID().toString()),
                (res, err, status) -> {
                });
          }
          Toast.makeText(IncomingCallActivity.this, I18n.t("Đã gửi tin nhắn nhanh."), Toast.LENGTH_SHORT).show();
          decline();
        })
        .setNegativeButton(I18n.t("Hủy"), null)
        .show();
  }

  private void acceptAudioOnly() {
    if (KinnectService.pendingIncoming != null) {
      try {
        KinnectService.pendingIncoming.put("mode", "audio");
      } catch (Exception ignored) {
      }
    }
    accept();
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
      haloBg.setColor(0x30187a4b);
      haloBg.setStroke(dp(2), 0x55187a4b);
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
      try {
        i.setImageDrawable(getDrawable(iconRes).mutate());
      } catch (Exception ignored) {
      }
    }
    i.setColorFilter(0xffffffff);
    b.addView(i, new FrameLayout.LayoutParams(dp(36), dp(36), Gravity.CENTER));
    b.setContentDescription(label);
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
    UiMetrics.enforceMinTouchTarget(b);
    c.addView(container, new LinearLayout.LayoutParams(dp(96), dp(96)));

    TextView t = text(label, 14, 0xfff0f2f5);
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    t.setPadding(0, dp(8), 0, 0);
    t.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
    c.addView(t, new LinearLayout.LayoutParams(-1, -2));
    return c;
  }

  private static android.content.res.ColorStateList ColorStateList() {
    return android.content.res.ColorStateList.valueOf(0x55ffffff);
  }

  private void decline() {
    JSONObject m = KinnectService.pendingIncoming;
    String callId = m != null ? m.optString("callId") : "";
    if (!callId.isEmpty())
      KinnectService.declineCall(this, callId);
    KinnectService.cancelCallNotification(this);
    KinnectService.clearCall(this);
    finish();
  }

  private void accept() {
    if (KinnectService.pendingIncoming == null) {
      finish();
      return;
    }
    KinnectService.markPendingAccept(true);
    final Runnable launchMain = () -> {
      KinnectService.cancelCallNotification(IncomingCallActivity.this);
      startActivity(new Intent(IncomingCallActivity.this, MainActivity.class).putExtra("accept_call", true)
          .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
      finish();
    };
    if (Build.VERSION.SDK_INT >= 26) {
      try {
        KeyguardManager km = (KeyguardManager) getSystemService(KEYGUARD_SERVICE);
        if (km != null && km.isKeyguardLocked()) {
          km.requestDismissKeyguard(this, new KeyguardManager.KeyguardDismissCallback() {
            @Override
            public void onDismissSucceeded() {
              launchMain.run();
            }

            @Override
            public void onDismissError() {
              KinnectService.markPendingAccept(false);
              runOnUiThread(() -> {
                if (isFinishing() || isDestroyed())
                  return;
                JSONObject pending = KinnectService.pendingIncoming;
                if (pending == null)
                  finish();
                else if (!uiBuilt)
                  build(pending);
              });
            }

            @Override
            public void onDismissCancelled() {
              KinnectService.markPendingAccept(false);
              runOnUiThread(() -> {
                if (isFinishing() || isDestroyed())
                  return;
                JSONObject pending = KinnectService.pendingIncoming;
                if (pending == null)
                  finish();
                else if (!uiBuilt)
                  build(pending);
              });
            }
          });
          return;
        }
      } catch (Exception ignored) {
      }
    }
    launchMain.run();
  }

  @Override
  public void onBackPressed() {
  }

  @Override
  protected void onDestroy() {
    if (quickReplySheet != null) {
      try {
        if (quickReplySheet.isShowing())
          quickReplySheet.dismiss();
      } catch (Exception ignored) {
      }
      quickReplySheet = null;
    }
    for (Animator a : animators)
      a.cancel();
    animators.clear();
    if (showing == this)
      showing = null;
    super.onDestroy();
  }
}
