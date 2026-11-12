package app.kinnect.live;

import android.Manifest;
import android.animation.*;
import android.app.*;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.hardware.camera2.*;
import android.media.*;
import android.net.Uri;
import android.os.*;
import android.provider.MediaStore;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/**
 * Kinnect Camera: chụp ảnh và quay clip ngắn trong một màn.
 * - Chế độ Ảnh / Video (/ Tin 15 giây), vuốt ngang trên khung hình để đổi bộ lọc.
 * - 16 bộ lọc có ảnh xem trước + độ đậm, làm đẹp 5 mức, 11 sticker theo khuôn mặt (FxEngine).
 * - Hẹn giờ, lưới, đèn, tỉ lệ khung, nhạc nền; chụp xong có màn xem lại để lưu / đăng bài / đăng tin.
 * Mọi khung hình được vẽ lại bằng Canvas nên hiệu ứng nằm luôn trong ảnh và video.
 */
public final class StudioActivity extends Activity implements Choreographer.FrameCallback {
  static final String EXTRA_VIDEO = "video", EXTRA_STORY = "story", EXTRA_PHOTO = "photo", EXTRA_IMAGE = "image", EXTRA_ACTION = "action", EXTRA_MODE = "mode";
  private static final int W = 720, H = 1280, FW = 540, FH = 960, PW = 1080, PH = 1920;
  private static final int ACCENT = 0xff7652e8, PINK = 0xffff4f9a;
  private static final int GCAM_AMBER = 0xfffdd663, GCAM_RED = 0xffee2b2b, GCAM_PILL = 0x9918181d, GCAM_BTN = 0xff28282d;

  private final FxEngine fx = new FxEngine();
  private FrameLayout root, stage, panelHost, reviewLayer;
  private TextureView camera;
  private SurfaceView preview;
  private TextView timer, musicLabel, faceStatus, filterToast, countdown;
  private ShutterView shutter;
  private LinearLayout modeTabs, rail, zoomBar, creativeBar;
  private FocusRingView focusRing;
  private View flipButton;
  private GridOverlay gridOverlay;
  private CameraDevice device;
  private CameraCaptureSession session;
  private CaptureRequest.Builder previewRequest;
  private HandlerThread cameraThread;
  private Handler cameraHandler;
  private final Handler ui = new Handler(Looper.getMainLooper());
  private boolean front = true, recording = false, previewReady = false, torch = false, grid = false, story = false, busy = false;
  private String mode = "video", panel = "";
  private int limitSeconds = 0, timerSeconds = 0, ratio = 0; // 0: 9:16 · 1: 3:4 · 2: 1:1
  private Bitmap frame, still, stillFull;
  private MediaRecorder recorder;
  private Surface recorderSurface;
  private File output;
  private long startedAt;
  private int frameCount;
  private final ExecutorService worker = Executors.newSingleThreadExecutor();
  private volatile boolean detecting;
  private volatile float[] face;
  private int missed;
  private MediaPlayer music;
  private String musicUrl;
  private Uri musicLocal;
  private final NativeApi api = NativeApi.shared;
  private Bitmap thumb;
  private final List<ImageView> filterThumbs = new ArrayList<>();
  private File capturedPhoto;
  private boolean photoProEdited;

  private int dp(float n) { return Math.round(n * getResources().getDisplayMetrics().density * WebDesign.UI_SCALE); }

  private GradientDrawable round(int color, float radius) { GradientDrawable g = new GradientDrawable(); g.setColor(color); g.setCornerRadius(dp(radius)); return g; }

  private TextView text(String s, float size, int color, boolean bold) {
    TextView t = new KinnectText(this);
    t.setText(s);
    t.setTextSize(size);
    t.setTextColor(color);
    if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
    t.setShadowLayer(dp(3), 0, dp(1), 0x99000000);
    return t;
  }

  private ImageView icon(String name, int color) {
    ImageView v = new ImageView(this);
    int id = WebIcons.resolve(this, name);
    if (id != 0) { android.graphics.drawable.Drawable d = WebIcons.load(this, name); d.setTint(color); v.setImageDrawable(d); }
    return v;
  }

  // ======================= Giao diện =======================
  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().setStatusBarColor(0xff000000);
    getWindow().setNavigationBarColor(0xff000000);
    story = getIntent().getBooleanExtra(EXTRA_STORY, false);
    String startMode = getIntent().getStringExtra(EXTRA_MODE);
    if (startMode != null) mode = startMode;
    if (story) { mode = "video"; limitSeconds = 0; }
    root = new FrameLayout(this);
    root.setBackgroundColor(0xff000000);
    setContentView(root);
    root.setOnApplyWindowInsetsListener((v, i) -> { v.setPadding(0, i.getSystemWindowInsetTop(), 0, i.getSystemWindowInsetBottom()); return i; });
    if (getIntent().getBooleanExtra("open_music", false)) root.postDelayed(this::chooseMusic, 400);

    // Khung ngắm chuẩn Google Camera: bo góc 24dp trên nền đen tuyệt đối
    stage = new FrameLayout(this);
    stage.setClipToOutline(true);
    stage.setBackground(round(0xff111111, 24));
    camera = new TextureView(this);
    preview = new SurfaceView(this);
    stage.addView(camera, new FrameLayout.LayoutParams(-1, -1));
    stage.addView(preview, new FrameLayout.LayoutParams(-1, -1));
    gridOverlay = new GridOverlay(this);
    stage.addView(gridOverlay, new FrameLayout.LayoutParams(-1, -1));
    focusRing = new FocusRingView(this);
    stage.addView(focusRing, new FrameLayout.LayoutParams(-1, -1));
    int width = getResources().getDisplayMetrics().widthPixels;
    FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(width, width * 16 / 9, Gravity.TOP);
    sp.topMargin = dp(4);
    root.addView(stage, sp);
    camera.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
      public void onSurfaceTextureAvailable(SurfaceTexture s, int w, int h) { openCamera(); }
      public void onSurfaceTextureSizeChanged(SurfaceTexture s, int w, int h) {}
      public boolean onSurfaceTextureDestroyed(SurfaceTexture s) { return true; }
      public void onSurfaceTextureUpdated(SurfaceTexture s) {}
    });
    preview.getHolder().addCallback(new SurfaceHolder.Callback() {
      public void surfaceCreated(SurfaceHolder h) { previewReady = true; }
      public void surfaceChanged(SurfaceHolder h, int f, int w, int hh) {}
      public void surfaceDestroyed(SurfaceHolder h) { previewReady = false; }
    });
    // Vuốt ngang để đổi bộ lọc, chạm hai lần để đổi camera, chạm 1 lần để lấy nét kiểu Google Camera
    final GestureDetector gestures = new GestureDetector(this, new GestureDetector.SimpleOnGestureListener() {
      public boolean onDown(MotionEvent e) { return true; }
      public boolean onFling(MotionEvent a, MotionEvent b, float vx, float vy) {
        if (Math.abs(vx) < Math.abs(vy) || Math.abs(b.getX() - a.getX()) < dp(40)) return false;
        stepFilter(vx < 0 ? 1 : -1);
        return true;
      }
      public boolean onDoubleTap(MotionEvent e) { flip(); return true; }
      public boolean onSingleTapConfirmed(MotionEvent e) {
        if (!panel.isEmpty()) { showPanel(""); return true; }
        triggerTapFocus(e.getX(), e.getY());
        return true;
      }
    });
    final ScaleGestureDetector pinch = new ScaleGestureDetector(this, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
      public boolean onScale(ScaleGestureDetector d) { if (still == null) setZoom(zoom * d.getScaleFactor()); return true; }
    });
    stage.setOnTouchListener((v, e) -> { pinch.onTouchEvent(e); if (!pinch.isInProgress() && e.getPointerCount() == 1) gestures.onTouchEvent(e); return true; });

    // Thanh cài đặt nhanh trên cùng chuẩn Google Camera: Đóng · Nhạc nền · Cài đặt nhanh (Flash, Hẹn giờ, Lưới, Tỉ lệ)
    LinearLayout top = new LinearLayout(this);
    top.setGravity(Gravity.CENTER_VERTICAL);
    top.setPadding(dp(12), dp(12), dp(12), dp(20));
    top.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x99000000, 0x00000000 }));
    ImageView close = icon("close", 0xffffffff);
    close.setPadding(dp(10), dp(10), dp(10), dp(10));
    GradientDrawable closeBg = round(GCAM_PILL, 999);
    closeBg.setStroke(dp(1), 0x22ffffff);
    close.setBackground(closeBg);
    close.setContentDescription(I18n.t("Đóng"));
    close.setOnClickListener(v -> finishCancelled());
    top.addView(close, new LinearLayout.LayoutParams(dp(40), dp(40)));
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    musicLabel = text(I18n.t("Thêm nhạc"), 13, 0xffffffff, true);
    musicLabel.setGravity(Gravity.CENTER);
    musicLabel.setPadding(dp(12), 0, dp(14), 0);
    GradientDrawable musicBg = round(GCAM_PILL, 999);
    musicBg.setStroke(dp(1), 0x26ffffff);
    musicLabel.setBackground(musicBg);
    musicLabel.setCompoundDrawablesRelativeWithIntrinsicBounds(tinted("music"), null, null, null);
    musicLabel.setCompoundDrawablePadding(dp(6));
    musicLabel.setSingleLine(true);
    musicLabel.setEllipsize(android.text.TextUtils.TruncateAt.END);
    musicLabel.setMaxWidth(dp(170));
    musicLabel.setOnClickListener(v -> chooseMusic());
    top.addView(musicLabel, new LinearLayout.LayoutParams(-2, dp(36)));
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));

    // Thanh công cụ nhanh kiểu Google Camera (Flash, Timer, Grid, Ratio/Duration) nằm gọn trên thanh đỉnh
    rail = new LinearLayout(this);
    rail.setOrientation(LinearLayout.HORIZONTAL);
    rail.setGravity(Gravity.CENTER_VERTICAL);
    rail.setPadding(dp(4), dp(3), dp(4), dp(3));
    GradientDrawable railBg = round(GCAM_PILL, 999);
    railBg.setStroke(dp(1), 0x22ffffff);
    rail.setBackground(railBg);
    top.addView(rail, new LinearLayout.LayoutParams(-2, dp(40)));
    stage.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    buildRail();

    faceStatus = text("", 13, 0xffffffff, false);
    FrameLayout.LayoutParams fs = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    fs.topMargin = dp(68);
    stage.addView(faceStatus, fs);
    filterToast = text("", 22, 0xffffffff, true);
    filterToast.setPadding(dp(18), dp(8), dp(18), dp(8));
    filterToast.setBackground(round(0x99141418, 999));
    filterToast.setAlpha(0);
    stage.addView(filterToast, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    countdown = text("", 92, GCAM_AMBER, true);
    countdown.setVisibility(View.GONE);
    stage.addView(countdown, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    timer = text("", 13, 0xffffffff, true);
    timer.setLetterSpacing(0.04f);
    timer.setPadding(dp(14), dp(6), dp(14), dp(6));
    timer.setVisibility(View.GONE);
    GradientDrawable timerBg = round(GCAM_RED, 999);
    timerBg.setStroke(dp(1), 0x44ffffff);
    timer.setBackground(timerBg);
    FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    tp.topMargin = dp(16);
    stage.addView(timer, tp);

    // Vùng dưới chuẩn Google Camera: Cụm Zoom (1x/2x/4x) · Công cụ sáng tạo · Hàng nút chụp 3 cột · Thanh chuyển chế độ dạng viên thuốc
    LinearLayout bottom = new LinearLayout(this);
    bottom.setOrientation(LinearLayout.VERTICAL);
    bottom.setGravity(Gravity.CENTER_HORIZONTAL);
    bottom.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, new int[] { 0xf5000000, 0xcc000000, 0x00000000 }));
    bottom.setPadding(0, dp(16), 0, dp(12));

    // Cụm nút thu phóng chuẩn Google Camera (1× · 2× · 4×)
    zoomBar = new LinearLayout(this);
    zoomBar.setGravity(Gravity.CENTER);
    zoomBar.setPadding(dp(4), dp(4), dp(4), dp(4));
    GradientDrawable zb = round(GCAM_PILL, 999);
    zb.setStroke(dp(1), 0x26ffffff);
    zoomBar.setBackground(zb);
    LinearLayout.LayoutParams zlp = new LinearLayout.LayoutParams(-2, -2);
    zlp.bottomMargin = dp(10);
    bottom.addView(zoomBar, zlp);
    renderZoomBar();

    panelHost = new FrameLayout(this);
    bottom.addView(panelHost, new LinearLayout.LayoutParams(-1, -2));

    // Thanh công cụ sáng tạo gọn nhẹ (Bộ lọc · Làm đẹp · Sticker)
    creativeBar = new LinearLayout(this);
    creativeBar.setGravity(Gravity.CENTER);
    creativeBar.setPadding(dp(12), dp(2), dp(12), dp(8));
    bottom.addView(creativeBar, new LinearLayout.LayoutParams(-1, -2));
    renderCreativeBar();

    // Hàng nút chụp chính 3 cột chuẩn Google Camera: Thư viện (trái) · Nút chụp/quay lớn (giữa) · Đổi camera (phải)
    LinearLayout actions = new LinearLayout(this);
    actions.setGravity(Gravity.CENTER_VERTICAL);
    actions.setPadding(dp(28), dp(4), dp(28), dp(10));
    galleryAction = buildGalleryWell();
    LinearLayout leftSlot = new LinearLayout(this);
    leftSlot.setGravity(Gravity.CENTER);
    leftSlot.addView(galleryAction);
    actions.addView(leftSlot, new LinearLayout.LayoutParams(0, -2, 1));

    shutter = new ShutterView(this);
    shutter.setContentDescription(I18n.t("Chụp hoặc quay"));
    shutter.setOnClickListener(v -> onShutter());
    actions.addView(shutter, new LinearLayout.LayoutParams(dp(84), dp(84)));

    flipButton = buildFlipButton();
    LinearLayout rightSlot = new LinearLayout(this);
    rightSlot.setGravity(Gravity.CENTER);
    rightSlot.addView(flipButton);
    actions.addView(rightSlot, new LinearLayout.LayoutParams(0, -2, 1));
    bottom.addView(actions, new LinearLayout.LayoutParams(-1, -2));

    // Thanh chuyển chế độ dạng viên thuốc (Material 3 Pill Carousel) ở đáy màn hình như Google Camera
    modeTabs = new LinearLayout(this);
    modeTabs.setGravity(Gravity.CENTER);
    modeTabs.setPadding(dp(16), dp(2), dp(16), dp(2));
    bottom.addView(modeTabs, new LinearLayout.LayoutParams(-1, -2));
    renderModes();
    root.addView(bottom, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));

    reviewLayer = new FrameLayout(this);
    reviewLayer.setBackgroundColor(0xff000000);
    reviewLayer.setVisibility(View.GONE);
    root.addView(reviewLayer, new FrameLayout.LayoutParams(-1, -1));

    frame = Bitmap.createBitmap(FW, FH, Bitmap.Config.ARGB_8888);
    thumb = Bitmap.createBitmap(90, 120, Bitmap.Config.ARGB_8888);
    String photoUri = getIntent().getStringExtra(EXTRA_PHOTO);
    if (photoUri != null) loadStill(Uri.parse(photoUri), story ? "video" : "photo");
    String reviewUri=getIntent().getStringExtra("review_video");if(reviewUri!=null)showVideoReview(Uri.parse(reviewUri));
    if (still == null) ensurePermissions();
  }

  private void ensurePermissions() {
    List<String> need = new ArrayList<>();
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) need.add(Manifest.permission.CAMERA);
    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) need.add(Manifest.permission.RECORD_AUDIO);
    if (!need.isEmpty()) requestPermissions(need.toArray(new String[0]), 401);
  }

  private ImageView galleryThumbView;

  private View buildGalleryWell() {
    FrameLayout well = new FrameLayout(this);
    GradientDrawable bg = round(GCAM_BTN, 999);
    bg.setStroke(dp(2), 0x55ffffff);
    well.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff), bg, null));
    well.setClipToOutline(true);
    galleryThumbView = new ImageView(this);
    galleryThumbView.setScaleType(ImageView.ScaleType.CENTER_CROP);
    galleryThumbView.setVisibility(View.GONE);
    well.addView(galleryThumbView, new FrameLayout.LayoutParams(-1, -1));
    ImageView glyph = icon("image", 0xffffffff);
    well.addView(glyph, new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
    well.setContentDescription(I18n.t("Thư viện"));
    well.setOnClickListener(v -> openGallery());
    well.setLayoutParams(new LinearLayout.LayoutParams(dp(52), dp(52)));
    return well;
  }

  private View buildFlipButton() {
    FrameLayout btn = new FrameLayout(this);
    GradientDrawable bg = round(GCAM_BTN, 999);
    bg.setStroke(dp(1), 0x28ffffff);
    btn.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff), bg, null));
    final ImageView glyph = icon("flip", 0xffffffff);
    btn.addView(glyph, new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
    btn.setContentDescription(I18n.t("Lật"));
    btn.setOnClickListener(v -> {
      if (recording || still != null) return;
      glyph.animate().rotationBy(180f).setDuration(260).start();
      flip();
    });
    btn.setLayoutParams(new LinearLayout.LayoutParams(dp(52), dp(52)));
    return btn;
  }

  private void renderZoomBar() {
    if (zoomBar == null) return;
    zoomBar.setVisibility(still != null || mode.equals("live") ? View.GONE : View.VISIBLE);
    zoomBar.removeAllViews();
    float[] stops = { 1f, 2f, 4f };
    int activeIdx = zoom < 1.6f ? 0 : zoom < 3.2f ? 1 : 2;
    for (int i = 0; i < stops.length; i++) {
      final float target = stops[i];
      boolean on = i == activeIdx;
      TextView chip = text(on ? (Math.abs(zoom - Math.round(zoom)) < 0.08f ? Math.round(zoom) + "×" : String.format(Locale.US, "%.1f×", zoom)) : Math.round(target) + "", on ? 12 : 11, on ? 0xff111114 : 0xd9ffffff, true);
      chip.setShadowLayer(0, 0, 0, 0);
      chip.setGravity(Gravity.CENTER);
      chip.setBackground(round(on ? GCAM_AMBER : 0x00000000, 999));
      int size = dp(on ? 34 : 30);
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(size, size);
      if (i > 0) lp.leftMargin = dp(4);
      chip.setOnClickListener(v -> animateZoomTo(target));
      zoomBar.addView(chip, lp);
    }
  }

  private void animateZoomTo(float target) {
    if (still != null) return;
    ValueAnimator anim = ValueAnimator.ofFloat(zoom, target);
    anim.setDuration(200);
    anim.addUpdateListener(a -> setZoom((Float) a.getAnimatedValue(), false));
    anim.start();
    showFilterName(String.format(Locale.US, "%.0f×", target));
  }

  private void renderCreativeBar() {
    if (creativeBar == null) return;
    creativeBar.setVisibility(recording ? View.INVISIBLE : View.VISIBLE);
    creativeBar.removeAllViews();
    boolean filterActive = !fx.filter.equals("none") || panel.equals("filter");
    boolean beautyActive = fx.beautyOn || panel.equals("beauty");
    boolean stickerActive = !fx.sticker.equals("none") || panel.equals("sticker");
    creativeBar.addView(creativePill("palette", I18n.t("Bộ lọc"), panel.equals("filter"), filterActive, () -> showPanel(panel.equals("filter") ? "" : "filter")));
    creativeBar.addView(creativePill("wand", I18n.t("Làm đẹp"), panel.equals("beauty"), beautyActive, () -> showPanel(panel.equals("beauty") ? "" : "beauty")));
    creativeBar.addView(creativePill("smile", "Sticker", panel.equals("sticker"), stickerActive, () -> showPanel(panel.equals("sticker") ? "" : "sticker")));
  }

  private LinearLayout creativePill(String iconName, String label, boolean open, boolean active, Runnable click) {
    LinearLayout pill = new LinearLayout(this);
    pill.setGravity(Gravity.CENTER);
    pill.setPadding(dp(12), dp(6), dp(12), dp(6));
    GradientDrawable bg = round(open ? GCAM_AMBER : GCAM_PILL, 999);
    bg.setStroke(dp(1), open ? GCAM_AMBER : active ? 0x88fdd663 : 0x26ffffff);
    pill.setBackground(bg);
    int fg = open ? 0xff111114 : active ? GCAM_AMBER : 0xffffffff;
    ImageView ic = icon(iconName, fg);
    pill.addView(ic, new LinearLayout.LayoutParams(dp(16), dp(16)));
    TextView t = text(label, 12, fg, true);
    if (open) t.setShadowLayer(0, 0, 0, 0);
    t.setPadding(dp(6), 0, 0, 0);
    pill.addView(t);
    pill.setContentDescription(label);
    pill.setOnClickListener(v -> click.run());
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, dp(34));
    lp.setMargins(dp(4), 0, dp(4), 0);
    pill.setLayoutParams(lp);
    return pill;
  }

  private void buildRail() {
    rail.removeAllViews();
    if (still == null) rail.addView(railButton(torch ? "flash" : "flash_off", torch ? I18n.t("Đèn: bật") : I18n.t("Đèn"), torch, () -> { torch = !torch; applyTorch(); buildRail(); }));
    if (!mode.equals("live")) rail.addView(railButton("timer", timerSeconds == 0 ? I18n.t("Hẹn giờ") : timerSeconds + "s", timerSeconds > 0, () -> { timerSeconds = timerSeconds == 0 ? 3 : timerSeconds == 3 ? 10 : 0; buildRail(); }));
    if (!mode.equals("live")) rail.addView(railButton("grid", grid ? I18n.t("Lưới: bật") : I18n.t("Lưới"), grid, () -> { grid = !grid; gridOverlay.setGrid(grid); buildRail(); }));
    if (mode.equals("photo")) rail.addView(railBadgeButton(ratio == 0 ? "9:16" : ratio == 1 ? "3:4" : "1:1", ratio != 0, () -> { ratio = (ratio + 1) % 3; gridOverlay.setRatio(ratio); buildRail(); }));
    if (mode.equals("video") && !story) rail.addView(railBadgeButton(limitSeconds == 0 ? "∞" : limitSeconds + "s", limitSeconds > 0, () -> { limitSeconds = limitSeconds == 0 ? 15 : limitSeconds == 15 ? 30 : limitSeconds == 30 ? 60 : 0; buildRail(); }));
  }

  private View railButton(String iconName, String label, boolean active, Runnable click) {
    FrameLayout b = new FrameLayout(this);
    b.setBackground(round(active ? 0x33fdd663 : 0x00000000, 999));
    ImageView i = icon(iconName, active ? GCAM_AMBER : 0xffffffff);
    b.addView(i, new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    if (iconName.equals("timer") && timerSeconds > 0) {
      TextView badge = text(timerSeconds + "s", 9, GCAM_AMBER, true);
      badge.setShadowLayer(0, 0, 0, 0);
      FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.END);
      bp.rightMargin = dp(2);
      b.addView(badge, bp);
    }
    b.setContentDescription(label);
    b.setOnClickListener(v -> { if (!recording) click.run(); });
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(34), dp(34));
    lp.setMargins(dp(1), 0, dp(1), 0);
    b.setLayoutParams(lp);
    return b;
  }

  private View railBadgeButton(String badgeText, boolean active, Runnable click) {
    TextView b = text(badgeText, 11, active ? 0xff111114 : 0xffffffff, true);
    if (active) b.setShadowLayer(0, 0, 0, 0);
    b.setGravity(Gravity.CENTER);
    b.setPadding(dp(8), 0, dp(8), 0);
    b.setBackground(round(active ? GCAM_AMBER : 0x22ffffff, 999));
    b.setContentDescription(badgeText);
    b.setOnClickListener(v -> { if (!recording) click.run(); });
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, dp(28));
    lp.setMargins(dp(2), 0, dp(2), 0);
    b.setLayoutParams(lp);
    return b;
  }

  private View galleryAction;private LiveSetupSheet liveSetup;
  private void showLiveSetup(){if(liveSetup==null)liveSetup=new LiveSetupSheet(this,front,fx);liveSetup.front(front);liveSetup.show();}

  private void renderModes() {
    if(musicLabel!=null)musicLabel.setVisibility(mode.equals("live")?View.GONE:View.VISIBLE);
    if(galleryAction!=null)galleryAction.setVisibility(mode.equals("live")?View.INVISIBLE:View.VISIBLE);
    if(shutter!=null)shutter.setContentDescription(I18n.t(mode.equals("live")?"Thiết lập Live":"Chụp hoặc quay"));
    renderZoomBar();
    modeTabs.removeAllViews();
    String[][] modes = story ? new String[][] { { "video", "TIN 15 GIÂY" } } : new String[][] { { "photo", "ẢNH" }, { "video", "VIDEO" }, { "live", "LIVE" } };
    for (final String[] m : modes) {
      boolean on = m[0].equals(mode);
      boolean isLive = m[0].equals("live");
      LinearLayout cell = new LinearLayout(this);
      cell.setOrientation(LinearLayout.VERTICAL);
      cell.setGravity(Gravity.CENTER);
      cell.setPadding(dp(6), dp(2), dp(6), dp(2));
      TextView t = text(m[1], 12.5f, on ? (isLive ? 0xffffffff : 0xff111114) : (isLive ? 0xffff6b88 : 0xb3ffffff), true);
      if (on && !isLive) t.setShadowLayer(0, 0, 0, 0);
      t.setLetterSpacing(0.06f);
      t.setGravity(Gravity.CENTER);
      t.setSingleLine(true);
      t.setPadding(dp(18), dp(6), dp(18), dp(6));
      t.setBackground(round(on ? (isLive ? 0xffff3b5c : 0xffffffff) : 0x00000000, 999));
      cell.addView(t, new LinearLayout.LayoutParams(-2, dp(34)));
      cell.setOnClickListener(v -> { if (m[0].equals("live")) { if (!recording && !busy) { mode="live"; renderModes(); buildRail(); gridOverlay.setRatio(0); showLiveSetup(); } return; } if (!recording && !busy) { mode = m[0]; renderModes(); buildRail(); shutter.setMode(mode); gridOverlay.setRatio(mode.equals("photo") ? ratio : 0); } });
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
      lp.setMargins(dp(4), 0, dp(4), 0);
      modeTabs.addView(cell, lp);
    }
    if (shutter != null) shutter.setMode(mode);
  }

  // ======================= Bảng hiệu ứng chuẩn Google Camera (Material 3 Dark Surface + Pixel Amber) =======================
  private void showPanel(String which) {
    panel = which;
    panelHost.removeAllViews();
    filterThumbs.clear();
    if (!which.isEmpty()) {
      GradientDrawable card = round(0xe61b1b20, 24);
      card.setStroke(dp(1), 0x24ffffff);
      panelHost.setBackground(card);
      LinearLayout.LayoutParams plp = (LinearLayout.LayoutParams) panelHost.getLayoutParams();
      plp.setMargins(dp(12), 0, dp(12), dp(8));
      panelHost.setLayoutParams(plp);
      panelHost.setPadding(0, dp(10), 0, dp(8));
    } else {
      panelHost.setBackground(null);
      panelHost.setPadding(0, 0, 0, 0);
    }
    if (which.equals("filter")) panelHost.addView(filterPanel());
    if (which.equals("beauty")) panelHost.addView(beautyPanel());
    if (which.equals("sticker")) panelHost.addView(stickerPanel());
    renderCreativeBar();
  }

  private SeekBar slider(int value, SeekBar.OnSeekBarChangeListener l) {
    SeekBar s = new SeekBar(this);
    s.setMax(100);
    s.setProgress(value);
    s.setThumbTintList(android.content.res.ColorStateList.valueOf(GCAM_AMBER));
    s.setProgressTintList(android.content.res.ColorStateList.valueOf(GCAM_AMBER));
    s.setProgressBackgroundTintList(android.content.res.ColorStateList.valueOf(0x38ffffff));
    s.setOnSeekBarChangeListener(l);
    return s;
  }

  private abstract static class Slide implements SeekBar.OnSeekBarChangeListener {
    public void onStartTrackingTouch(SeekBar s) {}
    public void onStopTrackingTouch(SeekBar s) {}
  }

  private View filterPanel() {
    LinearLayout box = new LinearLayout(this);
    box.setOrientation(LinearLayout.VERTICAL);
    final TextView pct = text(Math.round(fx.intensity * 100) + "%", 11.5f, GCAM_AMBER, true);
    pct.setShadowLayer(0, 0, 0, 0);
    pct.setGravity(Gravity.END);
    LinearLayout sl = new LinearLayout(this);
    sl.setGravity(Gravity.CENTER_VERTICAL);
    sl.setPadding(dp(18), dp(2), dp(18), dp(4));
    TextView lbl = text(I18n.t("Độ đậm"), 12, 0xffe6e1e5, true);
    lbl.setShadowLayer(0, 0, 0, 0);
    sl.addView(lbl, new LinearLayout.LayoutParams(dp(64), -2));
    sl.addView(slider(Math.round(fx.intensity * 100), new Slide() {
      public void onProgressChanged(SeekBar s, int v, boolean u) { fx.intensity = v / 100f; pct.setText(v + "%"); }
    }), new LinearLayout.LayoutParams(0, -2, 1));
    sl.addView(pct, new LinearLayout.LayoutParams(dp(38), -2));
    if (!fx.filter.equals("none")) box.addView(sl);
    HorizontalScrollView hs = new HorizontalScrollView(this);
    hs.setHorizontalScrollBarEnabled(false);
    LinearLayout row = new LinearLayout(this);
    row.setPadding(dp(10), dp(6), dp(10), dp(4));
    for (final String[] f : FxEngine.FILTERS) {
      boolean on = fx.filter.equals(f[0]);
      LinearLayout cell = new LinearLayout(this);
      cell.setOrientation(LinearLayout.VERTICAL);
      cell.setGravity(Gravity.CENTER_HORIZONTAL);
      cell.setPadding(dp(4), 0, dp(4), 0);
      FrameLayout pic = new FrameLayout(this);
      GradientDrawable ring = round(0x00000000, 16);
      ring.setStroke(dp(on ? 2 : 1), on ? GCAM_AMBER : 0x26ffffff);
      pic.setBackground(ring);
      pic.setPadding(dp(2), dp(2), dp(2), dp(2));
      ImageView img = new ImageView(this);
      img.setScaleType(ImageView.ScaleType.CENTER_CROP);
      img.setClipToOutline(true);
      img.setBackground(round(0xff2b2b33, 14));
      img.setImageBitmap(thumb);
      img.setColorFilter(new ColorMatrixColorFilter(FxEngine.filterMatrix(f[0])));
      img.setTag(f[0]);
      filterThumbs.add(img);
      pic.addView(img, new FrameLayout.LayoutParams(dp(56), dp(72)));
      cell.addView(pic);
      TextView t = text(f[1], 11, on ? GCAM_AMBER : 0xd9ffffff, on);
      if (on) t.setShadowLayer(0, 0, 0, 0);
      t.setPadding(0, dp(5), 0, 0);
      cell.addView(t);
      cell.setOnClickListener(v -> { fx.filter = f[0]; showFilterName(f[1]); showPanel("filter"); });
      row.addView(cell);
    }
    hs.addView(row);
    box.addView(hs);
    refreshThumb();
    return box;
  }

  private String beautyKey = "smooth";

  private View beautyPanel() {
    LinearLayout box = new LinearLayout(this);
    box.setOrientation(LinearLayout.VERTICAL);
    final TextView pct = text(Math.round(fx.get(beautyKey) * 100) + "", 12, GCAM_AMBER, true);
    pct.setShadowLayer(0, 0, 0, 0);
    pct.setGravity(Gravity.END);
    LinearLayout sl = new LinearLayout(this);
    sl.setGravity(Gravity.CENTER_VERTICAL);
    sl.setPadding(dp(18), dp(2), dp(18), dp(2));
    String name = "";
    for (String[] b : FxEngine.BEAUTY) if (b[0].equals(beautyKey)) name = b[1];
    TextView nameTv = text(name, 12, 0xffe6e1e5, true);
    nameTv.setShadowLayer(0, 0, 0, 0);
    sl.addView(nameTv, new LinearLayout.LayoutParams(dp(72), -2));
    sl.addView(slider(Math.round(fx.get(beautyKey) * 100), new Slide() {
      public void onProgressChanged(SeekBar s, int v, boolean u) { fx.set(beautyKey, v / 100f); pct.setText(String.valueOf(v)); }
    }), new LinearLayout.LayoutParams(0, -2, 1));
    sl.addView(pct, new LinearLayout.LayoutParams(dp(32), -2));
    box.addView(sl);
    LinearLayout row = new LinearLayout(this);
    row.setGravity(Gravity.CENTER);
    row.setPadding(dp(8), dp(8), dp(8), dp(6));
    row.addView(beautyChip("beauty", fx.auto ? I18n.t("AI: bật") : "Real Tone AI", fx.auto, () -> {
      fx.auto = !fx.auto;
      if (fx.auto) { fx.beautyOn = true; fx.analyze(frame, face); showFilterName(face == null ? I18n.t("AI: tự cân sáng") : I18n.t("AI làm đẹp")); }
      showPanel("beauty");
    }), new LinearLayout.LayoutParams(0, -2, 1));
    final LinearLayout off = beautyChip("none", fx.beautyOn ? I18n.t("Tắt") : I18n.t("Đã tắt"), !fx.beautyOn, () -> { fx.beautyOn = !fx.beautyOn; showPanel("beauty"); });
    row.addView(off, new LinearLayout.LayoutParams(0, -2, 1));
    for (final String[] item : BeautyCatalog.ITEMS) {
      final String key = item[0];
      row.addView(beautyChip(item[2], item[1], fx.beautyOn && key.equals(beautyKey), () -> { beautyKey = key; fx.beautyOn = true; showPanel("beauty"); }), new LinearLayout.LayoutParams(0, -2, 1));
    }
    for (int i = 0; i < row.getChildCount(); i++) row.getChildAt(i).setLayoutParams(new LinearLayout.LayoutParams(dp(68), -2));
    HorizontalScrollView beautyScroll = new HorizontalScrollView(this);
    beautyScroll.setHorizontalScrollBarEnabled(false);
    beautyScroll.addView(row);
    box.addView(beautyScroll);
    TextView reset = text(I18n.t("Khôi phục mặc định"), 11, 0xb3ffffff, true);
    reset.setShadowLayer(0, 0, 0, 0);
    reset.setGravity(Gravity.CENTER);
    reset.setPadding(dp(12), dp(3), dp(12), dp(5));
    reset.setOnClickListener(v -> { fx.smooth = 0.5f; fx.whiten = 0.3f; fx.slim = 0.2f; fx.eyes = 0.2f; fx.blush = 0f; fx.lips = 0; fx.blemish = .4f; fx.beautyOn = true; showPanel("beauty"); });
    box.addView(reset);
    return box;
  }

  private LinearLayout beautyChip(String glyph, String label, boolean on, Runnable click) {
    LinearLayout c = new LinearLayout(this);
    c.setOrientation(LinearLayout.VERTICAL);
    c.setGravity(Gravity.CENTER_HORIZONTAL);
    FrameLayout g = new FrameLayout(this);
    GradientDrawable ring = round(on ? 0x2efdd663 : 0x16ffffff, 999);
    ring.setStroke(dp(on ? 2 : 1), on ? GCAM_AMBER : 0x38ffffff);
    g.setBackground(ring);
    ImageView mark = new ImageView(this);
    mark.setImageDrawable(EditorIcons.drawable(this, glyph, on ? GCAM_AMBER : 0xffffffff));
    g.addView(mark, new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    c.addView(g, new LinearLayout.LayoutParams(dp(40), dp(40)));
    TextView t = text(label, 10.5f, on ? GCAM_AMBER : 0xd9ffffff, on);
    if (on) t.setShadowLayer(0, 0, 0, 0);
    t.setGravity(Gravity.CENTER);
    t.setSingleLine(true);
    t.setEllipsize(android.text.TextUtils.TruncateAt.END);
    t.setPadding(0, dp(5), 0, 0);
    c.addView(t, new LinearLayout.LayoutParams(-1, -2));
    c.setOnClickListener(v -> click.run());
    return c;
  }

  private View stickerPanel() {
    GridLayout gridView = new GridLayout(this);
    gridView.setColumnCount(6);
    gridView.setPadding(dp(8), dp(4), dp(8), dp(6));
    int size = (getResources().getDisplayMetrics().widthPixels - dp(40)) / 6;
    for (final String[] s : FxEngine.STICKERS) {
      boolean on = fx.sticker.equals(s[0]);
      LinearLayout cell = new LinearLayout(this);
      cell.setOrientation(LinearLayout.VERTICAL);
      cell.setGravity(Gravity.CENTER);
      FrameLayout g = new FrameLayout(this);
      GradientDrawable ring = round(on ? 0x2efdd663 : 0x14ffffff, 14);
      ring.setStroke(dp(on ? 2 : 1), on ? GCAM_AMBER : 0x33ffffff);
      g.setBackground(ring);
      ImageView mark = new ImageView(this);
      mark.setImageDrawable(EditorIcons.drawable(this, s[0].equals("none") ? "none" : "fx_" + s[0], on ? GCAM_AMBER : 0xffffffff));
      g.addView(mark, new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
      cell.addView(g, new LinearLayout.LayoutParams(dp(40), dp(40)));
      TextView t = text(s[1], 9.5f, on ? GCAM_AMBER : 0xd9ffffff, on);
      if (on) t.setShadowLayer(0, 0, 0, 0);
      t.setGravity(Gravity.CENTER);
      t.setSingleLine(true);
      t.setEllipsize(android.text.TextUtils.TruncateAt.END);
      t.setPadding(0, dp(4), 0, 0);
      cell.addView(t, new LinearLayout.LayoutParams(-1, -2));
      cell.setOnClickListener(v -> {
        fx.sticker = s[0];
        if (!s[0].equals("none") && face == null) faceStatus.setText(I18n.t("Đưa khuôn mặt vào khung hình"));
        showPanel("sticker");
      });
      GridLayout.LayoutParams lp = new GridLayout.LayoutParams();
      lp.width = size;
      lp.height = -2;
      lp.setMargins(0, dp(2), 0, dp(4));
      gridView.addView(cell, lp);
    }
    return gridView;
  }

  private void stepFilter(int dir) {
    int i = 0;
    for (int k = 0; k < FxEngine.FILTERS.length; k++) if (FxEngine.FILTERS[k][0].equals(fx.filter)) i = k;
    i = (i + dir + FxEngine.FILTERS.length) % FxEngine.FILTERS.length;
    fx.filter = FxEngine.FILTERS[i][0];
    showFilterName(FxEngine.FILTERS[i][1]);
    if (panel.equals("filter")) showPanel("filter");
  }

  private void showFilterName(String name) {
    filterToast.setText(name);
    filterToast.animate().cancel();
    filterToast.setAlpha(1f);
    filterToast.setScaleX(0.9f);
    filterToast.setScaleY(0.9f);
    filterToast.animate().scaleX(1f).scaleY(1f).setDuration(180).withEndAction(() -> filterToast.animate().alpha(0).setStartDelay(650).setDuration(350)).start();
  }

  private void refreshThumb() {
    Canvas c = new Canvas(thumb);
    Rect srcRect = new Rect(FW / 6, FH / 8, FW * 5 / 6, FH * 7 / 8);
    c.drawBitmap(frame, srcRect, new Rect(0, 0, thumb.getWidth(), thumb.getHeight()), new Paint(Paint.FILTER_BITMAP_FLAG));
    for (ImageView v : filterThumbs) v.invalidate();
  }

  // ======================= Camera =======================
  @Override
  public void onRequestPermissionsResult(int code, String[] p, int[] r) {
    super.onRequestPermissionsResult(code, p, r);
    if (code == 401 && checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) openCamera();
    else if (code == 401 && still == null) {
      Toast.makeText(this, I18n.t("Cần quyền camera để chụp và quay."), Toast.LENGTH_LONG).show();
      finishCancelled();
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    if(mode.equals("live")&&liveSetup==null)root.post(this::showLiveSetup);
    Choreographer.getInstance().postFrameCallback(this);
    if (camera.isAvailable()&&reviewedVideo==null) openCamera();if(reviewVideo!=null)reviewVideo.start();
  }

  @Override
  protected void onPause() {
    if (recording) stopRecording();
    Choreographer.getInstance().removeFrameCallback(this);
    closeCamera();
    if (music != null) music.pause();if(reviewVideo!=null)reviewVideo.pause();
    super.onPause();
  }

  @Override
  protected void onDestroy() {
    if(liveSetup!=null)liveSetup.close();
    if(reviewVideo!=null){reviewVideo.stopPlayback();reviewVideo=null;}worker.shutdownNow();
    if (music != null) { music.release(); music = null; }
    if (cameraThread != null) { cameraThread.quitSafely(); cameraThread = null; cameraHandler = null; }
    super.onDestroy();
  }

  private void flip() {
    if (recording || still != null) return;
    front = !front;
    torch = false;
    closeCamera();
    openCamera();
    buildRail();
  }

  private void openCamera() {
    if (still != null || device != null || !camera.isAvailable()) return;
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return;
    try {
      if (cameraThread == null) {
        cameraThread = new HandlerThread("kinnect-camera");
        cameraThread.start();
        cameraHandler = new Handler(cameraThread.getLooper());
      }
      CameraManager manager = (CameraManager) getSystemService(CAMERA_SERVICE);
      String chosen = null;
      for (String id : manager.getCameraIdList()) {
        Integer facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING);
        if (facing != null && facing == (front ? CameraCharacteristics.LENS_FACING_FRONT : CameraCharacteristics.LENS_FACING_BACK)) { chosen = id; break; }
      }
      if (chosen == null) chosen = manager.getCameraIdList()[0];
      characteristics = manager.getCameraCharacteristics(chosen);
      // Kích thước 16:9 lớn nhất ≤ 1920×1080: khi xoay dọc vừa khít khung 9:16, giữ trọn góc rộng của cảm biến.
      bufferW = 1920; bufferH = 1080;
      android.hardware.camera2.params.StreamConfigurationMap map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
      if (map != null) {
        android.util.Size best = null;
        for (android.util.Size sz : map.getOutputSizes(SurfaceTexture.class)) {
          if (sz.getWidth() * 9 != sz.getHeight() * 16 || sz.getWidth() > 1920) continue;
          if (best == null || sz.getWidth() > best.getWidth()) best = sz;
        }
        if (best != null) { bufferW = best.getWidth(); bufferH = best.getHeight(); }
      }
      zoom = 1f;
      manager.openCamera(chosen, new CameraDevice.StateCallback() {
        public void onOpened(CameraDevice d) { device = d; startPreview(); }
        public void onDisconnected(CameraDevice d) { d.close(); device = null; }
        public void onError(CameraDevice d, int e) { d.close(); device = null; ui.post(() -> faceStatus.setText(I18n.t("Không mở được camera."))); }
      }, cameraHandler);
    } catch (Exception e) {
      faceStatus.setText(I18n.t("Không mở được camera."));
    }
  }

  private void startPreview() {
    try {
      SurfaceTexture texture = camera.getSurfaceTexture();
      texture.setDefaultBufferSize(bufferW, bufferH);
      final Surface surface = new Surface(texture);
      // TEMPLATE_PREVIEW + tắt chống rung: tránh máy tự cắt khung (bị "zoom gần") khi vừa mở camera.
      previewRequest = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
      previewRequest.addTarget(surface);
      previewRequest.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
      previewRequest.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF);
      previewRequest.set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE, CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_ON);
      applyZoomTo(previewRequest);
      device.createCaptureSession(Collections.singletonList(surface), new CameraCaptureSession.StateCallback() {
        public void onConfigured(CameraCaptureSession s) { session = s; applyTorch(); }
        public void onConfigureFailed(CameraCaptureSession s) {}
      }, cameraHandler);
    } catch (Exception e) {
      ui.post(() -> faceStatus.setText(I18n.t("Không mở được camera.")));
    }
  }

  private CameraCharacteristics characteristics;
  private int bufferW = 1920, bufferH = 1080;
  private float zoom = 1f;

  /** Zoom bằng vùng cắt cảm biến (chụm 2 ngón); 1× = toàn bộ cảm biến. */
  private void applyZoomTo(CaptureRequest.Builder b) {
    if (characteristics == null) return;
    Rect active = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
    if (active == null) return;
    int cw = Math.round(active.width() / zoom), ch = Math.round(active.height() / zoom);
    int left = active.left + (active.width() - cw) / 2, top = active.top + (active.height() - ch) / 2;
    b.set(CaptureRequest.SCALER_CROP_REGION, new Rect(left, top, left + cw, top + ch));
  }

  private void setZoom(float value) {
    setZoom(value, true);
  }

  private void setZoom(float value, boolean toast) {
    Float max = characteristics == null ? null : characteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM);
    zoom = Math.max(1f, Math.min(max == null ? 4f : Math.min(max, 8f), value));
    if (previewRequest != null && session != null) {
      applyZoomTo(previewRequest);
      try { session.setRepeatingRequest(previewRequest.build(), null, cameraHandler); } catch (Exception ignored) {}
    }
    renderZoomBar();
    if (toast) showFilterName(String.format(java.util.Locale.US, I18n.t("%.1f×"), zoom));
  }

  private void triggerTapFocus(float x, float y) {
    if (focusRing != null) focusRing.showAt(x, y);
    if (still != null || characteristics == null || previewRequest == null || session == null) return;
    try {
      Rect active = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
      if (active != null && stage.getWidth() > 0 && stage.getHeight() > 0) {
        int cx = Math.max(active.left, Math.min(active.right, active.left + Math.round((x / stage.getWidth()) * active.width())));
        int cy = Math.max(active.top, Math.min(active.bottom, active.top + Math.round((y / stage.getHeight()) * active.height())));
        int half = Math.max(60, Math.min(active.width(), active.height()) / 12);
        Rect region = new Rect(Math.max(active.left, cx - half), Math.max(active.top, cy - half), Math.min(active.right, cx + half), Math.min(active.bottom, cy + half));
        android.hardware.camera2.params.MeteringRectangle[] rects = { new android.hardware.camera2.params.MeteringRectangle(region, 800) };
        Integer maxAf = characteristics.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF);
        if (maxAf != null && maxAf > 0) previewRequest.set(CaptureRequest.CONTROL_AF_REGIONS, rects);
        Integer maxAe = characteristics.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE);
        if (maxAe != null && maxAe > 0) previewRequest.set(CaptureRequest.CONTROL_AE_REGIONS, rects);
        session.setRepeatingRequest(previewRequest.build(), null, cameraHandler);
      }
    } catch (Exception ignored) {}
  }

  private void applyTorch() {
    if (session == null || previewRequest == null) return;
    try {
      previewRequest.set(CaptureRequest.FLASH_MODE, torch && !front ? CaptureRequest.FLASH_MODE_TORCH : CaptureRequest.FLASH_MODE_OFF);
      session.setRepeatingRequest(previewRequest.build(), null, cameraHandler);
    } catch (Exception ignored) {}
  }

  private void closeCamera() {
    if (session != null) { session.close(); session = null; }
    if (device != null) { device.close(); device = null; }
  }

  /** Ảnh có sẵn làm nguồn (chỉnh ảnh, hoặc tin ảnh kèm nhạc). */
  private void loadStill(Uri uri, String startMode) {
    try {
      BitmapFactory.Options o = new BitmapFactory.Options();
      o.inJustDecodeBounds = true;
      try (InputStream in = getContentResolver().openInputStream(uri)) {
        BitmapFactory.decodeStream(in, null, o);
      }
      o.inSampleSize = Math.max(1, Math.min(o.outWidth / PW, o.outHeight / PH));
      o.inJustDecodeBounds = false;
      Bitmap src;
      try (InputStream in = getContentResolver().openInputStream(uri)) {
        src = BitmapFactory.decodeStream(in, null, o);
      }
      if (src == null) throw new java.io.IOException("Decode failed");
      stillFull = Bitmap.createBitmap(PW, PH, Bitmap.Config.ARGB_8888);
      Canvas c = new Canvas(stillFull);
      c.drawColor(0xff000000);
      float scale = Math.max(PW / (float) src.getWidth(), PH / (float) src.getHeight());
      float w = src.getWidth() * scale, h = src.getHeight() * scale;
      c.drawBitmap(src, null, new RectF((PW - w) / 2, (PH - h) / 2, (PW + w) / 2, (PH + h) / 2), new Paint(Paint.FILTER_BITMAP_FLAG));
      src.recycle();
      new Canvas(frame).drawBitmap(stillFull, null, new Rect(0, 0, FW, FH), new Paint(Paint.FILTER_BITMAP_FLAG));
      still = frame;
      front = false;
      closeCamera();
      mode = startMode;
      renderModes();
      buildRail();
      face = null;
    } catch (Exception e) {
      Toast.makeText(this, I18n.t("Không mở được ảnh."), Toast.LENGTH_LONG).show();
    }
  }

  private void openGallery() {
    if(recording)return;
    boolean video=mode.equals("video");Intent pick=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(video?"video/*":"image/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    try{startActivityForResult(pick,video?404:403);}catch(Exception e){Toast.makeText(this,I18n.t("Không mở được thư viện."),Toast.LENGTH_SHORT).show();}
  }

  private void openPhotoPro(Uri uri){Intent intent=new Intent(this,PhotoEditActivity.class).setData(uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);intent.setClipData(android.content.ClipData.newRawUri("photo",uri));startActivityForResult(intent,406);}

  // ======================= Vẽ từng khung hình =======================
  private boolean hardwarePreview = true;

  @Override
  public void doFrame(long nanos) {
    Choreographer.getInstance().postFrameCallback(this);
    if (still == null) {
      if (!camera.isAvailable() || device == null) return;
      camera.getBitmap(frame);
    }
    frameCount++;
    boolean needFace = fx.needsFace();
    if (needFace && frameCount % 4 == 0 && !detecting) detectFace();
    if (panel.equals("filter") && frameCount % 45 == 0) refreshThumb();
    if (fx.auto && frameCount % 30 == 0) fx.analyze(frame, face);
    if (previewReady) {
      Canvas c = null;
      try {
        if (hardwarePreview) {
          try { c = preview.getHolder().getSurface().lockHardwareCanvas(); }
          catch (Exception e) { hardwarePreview = false; c = null; }
        }
        if (c == null && !hardwarePreview) c = preview.getHolder().lockCanvas();
        if (c != null) fx.render(c, frame, face, frameCount);
      } catch (Exception ignored) {
      } finally {
        if (c != null) try { if (hardwarePreview) preview.getHolder().getSurface().unlockCanvasAndPost(c); else preview.getHolder().unlockCanvasAndPost(c); } catch (Exception ignored) {}
      }
    }
    if (recording && recorderSurface != null) {
      try {
        Canvas c = recorderSurface.lockHardwareCanvas();
        try { fx.render(c, frame, face, frameCount); } finally { recorderSurface.unlockCanvasAndPost(c); }
      } catch (Exception ignored) {}
      float elapsed = (SystemClock.elapsedRealtime() - startedAt) / 1000f;
      shutter.setProgress(limitSeconds > 0 ? elapsed / limitSeconds : (elapsed % 60) / 60f);
      int sec = (int) elapsed;
      String cur = String.format(Locale.US, "%02d:%02d", sec / 60, sec % 60);
      String lim = limitSeconds > 0 ? String.format(Locale.US, " / %02d:%02d", limitSeconds / 60, limitSeconds % 60) : "";
      timer.setText("●  " + cur + lim);
      if (limitSeconds > 0 && elapsed >= limitSeconds) stopRecording();
    }
  }

  private void detectFace() {
    detecting = true;
    final Bitmap small = Bitmap.createScaledBitmap(frame, FW / 2, FH / 2, true).copy(Bitmap.Config.RGB_565, false);
    worker.execute(() -> {
      try {
        FaceDetector.Face[] found = new FaceDetector.Face[1];
        int n = new FaceDetector(small.getWidth(), small.getHeight(), 1).findFaces(small, found);
        float[] next = null;
        if (n > 0 && found[0] != null && found[0].confidence() >= 0.3f) {
          PointF mid = new PointF();
          found[0].getMidPoint(mid);
          next = new float[] { mid.x * 2, mid.y * 2, found[0].eyesDistance() * 2, found[0].pose(FaceDetector.Face.EULER_Z) };
        }
        final float[] result = next;
        ui.post(() -> {
          if (result == null) {
            if (++missed >= 5) { face = null; if (!fx.sticker.equals("none")) faceStatus.setText(I18n.t("Đưa khuôn mặt vào khung hình")); }
            return;
          }
          missed = 0;
          float[] old = face;
          if (old != null) for (int i = 0; i < 4; i++) result[i] = old[i] * 0.45f + result[i] * 0.55f;
          face = result;
          faceStatus.setText("");
        });
      } catch (Exception ignored) {
      } finally {
        small.recycle();
        detecting = false;
      }
    });
  }

  // ======================= Chụp / quay =======================
  private void onShutter() {
    if(mode.equals("live")){showLiveSetup();return;}
    if (busy) return;
    if (recording) { stopRecording(); return; }
    if (timerSeconds > 0) countdownThen(timerSeconds, this::shoot);
    else shoot();
  }

  private void shoot() {
    if (mode.equals("photo")) capturePhoto();
    else startRecording();
  }

  private void countdownThen(final int seconds, final Runnable then) {
    busy = true;
    countdown.setVisibility(View.VISIBLE);
    final int[] left = { seconds };
    Runnable tick = new Runnable() {
      public void run() {
        if (isFinishing()) return;
        if (left[0] == 0) { countdown.setVisibility(View.GONE); busy = false; then.run(); return; }
        countdown.setText(String.valueOf(left[0]));
        countdown.setScaleX(1.4f);
        countdown.setScaleY(1.4f);
        countdown.setAlpha(1f);
        countdown.animate().scaleX(1f).scaleY(1f).alpha(0.6f).setDuration(800).start();
        left[0]--;
        ui.postDelayed(this, 1000);
      }
    };
    tick.run();
  }

  private void capturePhoto() {
    busy = true;
    // Hiệu ứng nháy trắng (đèn màn hình khi dùng camera trước)
    final View flash = new View(this);
    flash.setBackgroundColor(0xffffffff);
    stage.addView(flash, new FrameLayout.LayoutParams(-1, -1));
    flash.setAlpha(front && torch ? 1f : 0.85f);
    flash.animate().alpha(0).setDuration(350).withEndAction(() -> stage.removeView(flash)).start();
    final Bitmap src;
    final float[] f = face == null ? null : face.clone();
    if (still != null) src = stillFull;
    else src = camera.getBitmap(PW, PH);
    if (src == null) { busy = false; return; }
    final float scale = src.getWidth() / (float) FW;
    worker.execute(() -> {
      try {
        Bitmap out = Bitmap.createBitmap(PW, PH, Bitmap.Config.ARGB_8888);
        float[] sf = f == null ? null : new float[] { f[0] * scale, f[1] * scale, f[2] * scale, f[3] };
        fx.copy().render(new Canvas(out), src, sf, frameCount);
        Bitmap cropped = crop(out);
        File file = new File(getCacheDir(), "kinnect-photo-" + System.currentTimeMillis() + ".jpg");
        try (FileOutputStream os = new FileOutputStream(file)) { cropped.compress(Bitmap.CompressFormat.JPEG, 90, os); }
        final Bitmap shown = cropped;
        ui.post(() -> { busy = false; capturedPhoto = file; showReview(shown); });
      } catch (Exception e) {
        ui.post(() -> { busy = false; Toast.makeText(this, I18n.t("Không chụp được ảnh."), Toast.LENGTH_SHORT).show(); });
      }
    });
  }

  private Bitmap crop(Bitmap b) {
    if (ratio == 0) return b;
    int w = b.getWidth(), h = ratio == 1 ? w * 4 / 3 : w;
    return Bitmap.createBitmap(b, 0, (b.getHeight() - h) / 2, w, h);
  }

  // Màn xem lại sau khi chụp chuẩn Google Camera / Pixel Photos: lưu vào máy · đăng bài · đăng tin · chụp lại
  private void showReview(Bitmap photo) {
    if (galleryThumbView != null && photo != null) {
      galleryThumbView.setImageBitmap(photo);
      galleryThumbView.setVisibility(View.VISIBLE);
    }
    reviewLayer.removeAllViews();
    reviewLayer.setVisibility(View.VISIBLE);
    reviewLayer.setBackgroundColor(0xff000000);
    ImageView img = new ImageView(this);
    img.setScaleType(ImageView.ScaleType.FIT_CENTER);
    img.setImageBitmap(photo);
    reviewLayer.addView(img, new FrameLayout.LayoutParams(-1, -1));

    GradientDrawable proBg = round(GCAM_PILL, 999);
    proBg.setStroke(dp(1), 0x44fdd663);
    TextView pro = text(I18n.t("Studio Pro"), 13, GCAM_AMBER, true);
    pro.setPadding(dp(14), dp(8), dp(14), dp(8));
    pro.setMinHeight(dp(44));
    pro.setGravity(Gravity.CENTER);
    pro.setBackground(proBg);
    android.graphics.drawable.Drawable spk = tinted("sparkles");
    spk.setTint(GCAM_AMBER);
    pro.setCompoundDrawablesRelativeWithIntrinsicBounds(spk, null, null, null);
    pro.setCompoundDrawablePadding(dp(6));
    pro.setOnClickListener(v -> { if (capturedPhoto != null) openPhotoPro(Uri.fromFile(capturedPhoto)); });

    LinearLayout top = new LinearLayout(this);
    top.setGravity(Gravity.TOP);
    top.setPadding(dp(12), dp(14), dp(14), dp(16));
    top.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x99000000, 0x00000000 }));
    ImageView back = icon("back", 0xffffffff);
    back.setPadding(dp(10), dp(10), dp(10), dp(10));
    GradientDrawable backBg = round(GCAM_PILL, 999);
    backBg.setStroke(dp(1), 0x26ffffff);
    back.setBackground(backBg);
    back.setContentDescription(I18n.t("Chụp lại"));
    back.setOnClickListener(v -> reviewLayer.setVisibility(View.GONE));
    top.addView(back, new LinearLayout.LayoutParams(dp(42), dp(42)));
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));

    final TextView save = text(I18n.t("  Lưu vào máy"), 13.5f, 0xffffffff, true);
    save.setGravity(Gravity.CENTER);
    save.setMinHeight(dp(44));
    save.setPadding(dp(14), dp(8), dp(16), dp(8));
    GradientDrawable saveBg = round(GCAM_PILL, 999);
    saveBg.setStroke(dp(1), 0x28ffffff);
    save.setBackground(saveBg);
    save.setCompoundDrawablesRelativeWithIntrinsicBounds(tinted("download"), null, null, null);
    save.setOnClickListener(v -> {
      if (saveToGallery(capturedPhoto)) {
        save.setText(I18n.t("  Đã lưu"));
        save.setTextColor(GCAM_AMBER);
        android.graphics.drawable.Drawable chk = tinted("check");
        chk.setTint(GCAM_AMBER);
        save.setCompoundDrawablesRelativeWithIntrinsicBounds(chk, null, null, null);
      }
    });
    LinearLayout reviewActions = new LinearLayout(this);
    reviewActions.setOrientation(LinearLayout.VERTICAL);
    reviewActions.setGravity(Gravity.END);
    reviewActions.addView(save, new LinearLayout.LayoutParams(-2, -2));
    LinearLayout.LayoutParams proAt = new LinearLayout.LayoutParams(-2, -2);
    proAt.topMargin = dp(10);
    reviewActions.addView(pro, proAt);
    top.addView(reviewActions, new LinearLayout.LayoutParams(-2, -2));
    reviewLayer.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));

    LinearLayout bar = new LinearLayout(this);
    bar.setGravity(Gravity.CENTER);
    bar.setPadding(dp(16), dp(16), dp(16), dp(22));
    bar.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, new int[] { 0xe6000000, 0x99000000, 0x00000000 }));
    TextView again = text(I18n.t("Chụp lại"), 14.5f, 0xffffffff, true);
    again.setGravity(Gravity.CENTER);
    GradientDrawable againBg = round(GCAM_BTN, 999);
    againBg.setStroke(dp(1), 0x28ffffff);
    again.setBackground(againBg);
    again.setOnClickListener(v -> reviewLayer.setVisibility(View.GONE));
    bar.addView(again, new LinearLayout.LayoutParams(0, dp(50), 1));
    TextView storyBtn = text(I18n.t("Đăng tin"), 14.5f, 0xffffffff, true);
    storyBtn.setGravity(Gravity.CENTER);
    GradientDrawable storyBg = round(GCAM_BTN, 999);
    storyBg.setStroke(dp(1), 0x28ffffff);
    storyBtn.setBackground(storyBg);
    storyBtn.setOnClickListener(v -> deliverPhoto("story"));
    LinearLayout.LayoutParams mid = new LinearLayout.LayoutParams(0, dp(50), 1);
    mid.setMargins(dp(10), 0, dp(10), 0);
    bar.addView(storyBtn, mid);
    TextView post = text(I18n.t("Đăng bài"), 14.5f, 0xff111114, true);
    post.setShadowLayer(0, 0, 0, 0);
    post.setGravity(Gravity.CENTER);
    post.setBackground(round(0xffffffff, 999));
    post.setOnClickListener(v -> deliverPhoto("post"));
    bar.addView(post, new LinearLayout.LayoutParams(0, dp(50), 1));
    reviewLayer.addView(bar, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
  }

  private android.graphics.drawable.Drawable tinted(String name) {
    int id = WebIcons.resolve(this, name);
    android.graphics.drawable.Drawable d = WebIcons.load(this, name);
    d.setTint(0xffffffff);
    d.setBounds(0, 0, dp(18), dp(18));
    return d;
  }

  private boolean saveToGallery(File file) {
    if (file == null) return false;
    try {
      ContentValues v = new ContentValues();
      v.put(MediaStore.Images.Media.DISPLAY_NAME, "Kinnect_" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date()) + ".jpg");
      v.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
      if (Build.VERSION.SDK_INT >= 29) v.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Kinnect");
      Uri uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
      if (uri == null) throw new java.io.IOException("MediaStore insert returned null");
      try (OutputStream os = getContentResolver().openOutputStream(uri); InputStream in = new FileInputStream(file)) {
        if (os == null) throw new java.io.IOException("OutputStream null");
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
      }
      Toast.makeText(this, I18n.t("Đã lưu vào Ảnh › Kinnect"), Toast.LENGTH_SHORT).show();
      return true;
    } catch (Exception e) {
      Toast.makeText(this, I18n.t("Không lưu được ảnh vào máy."), Toast.LENGTH_SHORT).show();
      return false;
    }
  }

  private void deliverPhoto(String action) {
    Intent result = new Intent();
    result.putExtra(EXTRA_IMAGE, capturedPhoto.getAbsolutePath());
    result.putExtra("photoProEdited",photoProEdited);
    result.putExtra(EXTRA_ACTION, action);
    setResult(RESULT_OK, result);
    finish();
  }

  private void startRecording() {
    if (device == null && still == null) return;
    boolean withMusic = musicUrl != null || musicLocal != null;
    boolean mic = !withMusic && checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    try {
      output = new File(getCacheDir(), "kinnect-" + System.currentTimeMillis() + ".mp4");
      recorder = new MediaRecorder();
      if (mic) recorder.setAudioSource(MediaRecorder.AudioSource.CAMCORDER);
      recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE);
      recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
      recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264);
      if (mic) {
        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
        recorder.setAudioEncodingBitRate(96000);
        recorder.setAudioSamplingRate(44100);
      }
      recorder.setVideoSize(W, H);
      recorder.setVideoFrameRate(30);
      recorder.setVideoEncodingBitRate(limitSeconds <= 30 ? 2400000 : 1300000);
      recorder.setOutputFile(output.getAbsolutePath());
      
      recorder.prepare();
      recorderSurface = recorder.getSurface();
      recorder.start();
      recording = true;
      startedAt = SystemClock.elapsedRealtime();
      shutter.setRecording(true);
      timer.setVisibility(View.VISIBLE);
      rail.setVisibility(View.INVISIBLE);
      modeTabs.setVisibility(View.INVISIBLE);
      if (creativeBar != null) creativeBar.setVisibility(View.INVISIBLE);
      if (flipButton != null) flipButton.setVisibility(View.INVISIBLE);
      if (galleryAction != null) galleryAction.setVisibility(View.INVISIBLE);
      if (musicLabel != null) musicLabel.setVisibility(View.INVISIBLE);
      showPanel("");
      if (music != null) { music.seekTo(0); music.start(); }
    } catch (Exception e) {
      releaseRecorder();
      Toast.makeText(this, I18n.t("Không bắt đầu quay được trên máy này."), Toast.LENGTH_LONG).show();
    }
  }

  private void stopRecording() {
    if (!recording) return;
    recording = false;
    long length = SystemClock.elapsedRealtime() - startedAt;
    boolean ok = true;
    try { recorder.stop(); } catch (Exception e) { ok = false; }
    releaseRecorder();
    if (music != null) music.pause();
    if (!ok || length < 1000) { Toast.makeText(this, I18n.t("Video quá ngắn, hãy quay lâu hơn."), Toast.LENGTH_SHORT).show(); return; }
    if (musicUrl == null && musicLocal == null) { done(output); return; }
    final ProgressDialog progress = ProgressDialog.show(this, "Kinnect", "Đang ghép nhạc nền…", true, false);
    final File video = output;
    new Thread(() -> {
      File mixed = new File(getCacheDir(), "kinnect-mix-" + System.currentTimeMillis() + ".mp4");
      String error = null;
      try { MusicMuxer.mux(this, video, musicUrl, musicLocal, api.jar(), mixed); } catch (Exception e) { error = "Không ghép được nhạc. Video sẽ không có nhạc nền."; }
      final String message = error;
      ui.post(() -> {
        progress.dismiss();
        if (message != null) Toast.makeText(this, message, Toast.LENGTH_LONG).show();
        done(message == null ? mixed : video);
      });
    }, "kinnect-mux").start();
  }

  private void releaseRecorder() {
    if (recorder != null) { recorder.release(); recorder = null; }
    recorderSurface = null;
    shutter.setRecording(false);
    shutter.setProgress(0);
    timer.setVisibility(View.GONE);
    rail.setVisibility(View.VISIBLE);
    modeTabs.setVisibility(View.VISIBLE);
    if (creativeBar != null) creativeBar.setVisibility(View.VISIBLE);
    if (flipButton != null) flipButton.setVisibility(View.VISIBLE);
    if (galleryAction != null) galleryAction.setVisibility(mode.equals("live") ? View.INVISIBLE : View.VISIBLE);
    if (musicLabel != null) musicLabel.setVisibility(mode.equals("live") ? View.GONE : View.VISIBLE);
  }

  private Uri reviewedVideo;private VideoView reviewVideo;private boolean videoProEdited;
  private void done(File file){videoProEdited=false;showVideoReview(Uri.fromFile(file));}
  private void openVideoPro(Uri uri){if(reviewVideo!=null)reviewVideo.pause();Intent editor=new Intent(this,MediaEditActivity.class).setData(uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);editor.setClipData(android.content.ClipData.newRawUri("video",uri));startActivityForResult(editor,408);}
  private void showVideoReview(Uri uri){
    closeCamera();reviewedVideo=uri;if(reviewVideo!=null)reviewVideo.stopPlayback();reviewLayer.removeAllViews();reviewLayer.setVisibility(View.VISIBLE);reviewLayer.setBackgroundColor(0xff000000);reviewVideo=new VideoView(this);reviewVideo.setVideoURI(uri);reviewVideo.setOnPreparedListener(player->{player.setLooping(true);reviewVideo.start();});reviewLayer.addView(reviewVideo,new FrameLayout.LayoutParams(-1,-1,Gravity.CENTER));
    final TextView playBadge = text("❚❚", 18, 0xffffffff, true);
    playBadge.setGravity(Gravity.CENTER);
    playBadge.setBackground(round(GCAM_PILL, 999));
    playBadge.setAlpha(0f);
    reviewLayer.addView(playBadge, new FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER));
    reviewVideo.setOnTouchListener((v, e) -> {
      if (e.getActionMasked() == MotionEvent.ACTION_UP) {
        if (reviewVideo.isPlaying()) { reviewVideo.pause(); playBadge.setText("▶"); playBadge.animate().alpha(1f).setDuration(150).start(); }
        else { reviewVideo.start(); playBadge.setText("❚❚"); playBadge.animate().alpha(0f).setDuration(250).start(); }
      }
      return true;
    });
    GradientDrawable proBg = round(GCAM_PILL, 999);
    proBg.setStroke(dp(1), 0x44fdd663);
    TextView pro=text(I18n.t("Studio Pro"),13,GCAM_AMBER,true);pro.setPadding(dp(14),0,dp(14),0);pro.setGravity(Gravity.CENTER);pro.setBackground(proBg);android.graphics.drawable.Drawable spk=tinted("sparkles");spk.setTint(GCAM_AMBER);pro.setCompoundDrawablesRelativeWithIntrinsicBounds(spk,null,null,null);pro.setCompoundDrawablePadding(dp(6));pro.setOnClickListener(v->openVideoPro(reviewedVideo));FrameLayout.LayoutParams pp=new FrameLayout.LayoutParams(-2,dp(44),Gravity.TOP|Gravity.END);pp.setMargins(0,dp(52),dp(14),0);reviewLayer.addView(pro,pp);
    ImageView back=icon("back",0xffffffff);back.setPadding(dp(10),dp(10),dp(10),dp(10));GradientDrawable backBg=round(GCAM_PILL,999);backBg.setStroke(dp(1),0x28ffffff);back.setBackground(backBg);back.setContentDescription(I18n.t("Quay lại"));back.setOnClickListener(v->dismissVideoReview());FrameLayout.LayoutParams bp=new FrameLayout.LayoutParams(dp(44),dp(44),Gravity.TOP|Gravity.START);bp.setMargins(dp(12),dp(12),0,0);reviewLayer.addView(back,bp);
    LinearLayout bar=new LinearLayout(this);bar.setPadding(dp(16),dp(16),dp(16),dp(22));bar.setGravity(Gravity.CENTER);bar.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, new int[] { 0xe6000000, 0x99000000, 0x00000000 }));GradientDrawable againBg=round(GCAM_BTN,999);againBg.setStroke(dp(1),0x28ffffff);TextView again=text(I18n.t("Quay lại"),14.5f,0xffffffff,true);again.setGravity(Gravity.CENTER);again.setBackground(againBg);again.setOnClickListener(v->dismissVideoReview());bar.addView(again,new LinearLayout.LayoutParams(0,dp(50),1));TextView next=text(I18n.t("Tiếp tục"),14.5f,0xff111114,true);next.setShadowLayer(0,0,0,0);next.setGravity(Gravity.CENTER);next.setBackground(round(0xffffffff,999));next.setOnClickListener(v->deliverReviewedVideo());LinearLayout.LayoutParams np=new LinearLayout.LayoutParams(0,dp(50),1);np.leftMargin=dp(12);bar.addView(next,np);reviewLayer.addView(bar,new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM));
  }
  private void dismissVideoReview(){if(reviewVideo!=null){reviewVideo.stopPlayback();reviewVideo=null;}reviewedVideo=null;reviewLayer.setVisibility(View.GONE);if(camera.isAvailable())openCamera();}
  private void deliverReviewedVideo(){if(reviewedVideo==null)return;Intent result=new Intent().setData(reviewedVideo).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);result.setClipData(android.content.ClipData.newRawUri("video",reviewedVideo));result.putExtra(EXTRA_STORY,story);result.putExtra("videoProEdited",videoProEdited);if("file".equals(reviewedVideo.getScheme())){result.putExtra(EXTRA_VIDEO,reviewedVideo.getPath());setResult(RESULT_OK,result);}else setResult(RESULT_FIRST_USER,result);finish();}
  private void finishCancelled() {
    setResult(RESULT_CANCELED);
    finish();
  }

  @Override
  public void onBackPressed() {
    if (reviewLayer.getVisibility() == View.VISIBLE) { if(reviewedVideo!=null)dismissVideoReview();else reviewLayer.setVisibility(View.GONE);return; }
    if (!panel.isEmpty()) { showPanel(""); return; }
    finishCancelled();
  }

  // ======================= Nhạc nền =======================
  // Chọn nhạc kiểu Facebook: bảng gần toàn màn, tìm kiếm, tab Thư viện / Nhạc của bạn, nghe thử, "Dùng bài này".
  private MediaPlayer previewPlayer;

  private void chooseMusic() {
    if (recording) return;
    final android.app.Dialog dialog = new android.app.Dialog(this);
    dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
    final boolean dark = WebTheme.isDark(this);
    final int variant = dark ? 1 : 0;
    final int bg = WebDesign.CARD[variant], ink = WebDesign.INK[variant], muted = WebDesign.MUTED[variant], soft = WebDesign.WASH[variant], on = WebDesign.SOFT[variant];
    LinearLayout sheet = new LinearLayout(this);
    sheet.setOrientation(LinearLayout.VERTICAL);
    GradientDrawable shape = new GradientDrawable();
    shape.setColor(bg);
    float r = dp(22);
    shape.setCornerRadii(new float[] { r, r, r, r, 0, 0, 0, 0 });
    sheet.setBackground(shape);
    View grip = new View(this);
    grip.setBackground(round(dark ? 0xff4a4b4d : 0xffd0d3d8, 99));
    LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(dp(40), dp(5));
    gp.gravity = Gravity.CENTER_HORIZONTAL;
    gp.topMargin = dp(8);
    sheet.addView(grip, gp);
    LinearLayout head = new LinearLayout(this);
    head.setGravity(Gravity.CENTER_VERTICAL);
    head.setPadding(dp(10), dp(4), dp(10), dp(4));
    ImageView close = icon("close", ink);
    close.setPadding(dp(9), dp(9), dp(9), dp(9));
    close.setBackground(round(soft, 999));
    close.setOnClickListener(v -> dialog.dismiss());
    head.addView(close, new LinearLayout.LayoutParams(dp(38), dp(38)));
    TextView title = plain(I18n.t("Âm nhạc"), 17, ink, true);
    title.setGravity(Gravity.CENTER);
    head.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    TextView off = plain(musicUrl != null || musicLocal != null ? I18n.t("Bỏ nhạc") : "", 13, 0xffe0245e, true);
    off.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
    off.setOnClickListener(v -> { setMusic(null, null, null); dialog.dismiss(); });
    head.addView(off, new LinearLayout.LayoutParams(dp(60), -2));
    sheet.addView(head);
    LinearLayout search = new LinearLayout(this);
    search.setGravity(Gravity.CENTER_VERTICAL);
    search.setPadding(dp(14), 0, dp(14), 0);
    search.setBackground(round(soft, 999));
    search.addView(icon("search", muted), new LinearLayout.LayoutParams(dp(18), dp(18)));
    final EditText query = new KinnectInput(this);
    query.setHint(I18n.t("Tìm bài hát hoặc nghệ sĩ"));
    query.setHintTextColor(muted);
    query.setTextColor(ink);
    query.setTextSize(15);
    query.setBackground(null);
    query.setSingleLine(true);
    search.addView(query, new LinearLayout.LayoutParams(0, -2, 1));
    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, dp(42));
    sp.setMargins(dp(14), dp(6), dp(14), dp(4));
    sheet.addView(search, sp);
    final LinearLayout tabs = new LinearLayout(this);
    tabs.setPadding(dp(14), dp(6), dp(14), dp(6));
    sheet.addView(tabs);
    final ScrollView scroll = new ScrollView(this);
    final LinearLayout list = new LinearLayout(this);
    list.setOrientation(LinearLayout.VERTICAL);
    list.setPadding(dp(6), 0, dp(6), dp(8));
    scroll.addView(list);
    sheet.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    final View barDivider = new View(this);
    barDivider.setBackgroundColor(soft);
    barDivider.setVisibility(View.GONE);
    sheet.addView(barDivider, new LinearLayout.LayoutParams(-1, dp(1)));
    final LinearLayout bar = new LinearLayout(this);
    bar.setOrientation(LinearLayout.HORIZONTAL);
    bar.setGravity(Gravity.CENTER_VERTICAL);
    bar.setPadding(dp(16), dp(10), dp(16), dp(14));
    bar.setBackgroundColor(bg);
    bar.setVisibility(View.GONE);
    final TextView nowTitle = plain("", 15, ink, true), nowSub = plain("", 12, muted, false);
    LinearLayout now = new LinearLayout(this);
    now.setOrientation(LinearLayout.VERTICAL);
    now.addView(nowTitle);
    now.addView(nowSub);
    bar.addView(now, new LinearLayout.LayoutParams(0, -2, 1));
    TextView use = plain(I18n.t("Dùng bài này"), 15, 0xffffffff, true);
    use.setGravity(Gravity.CENTER);
    use.setPadding(dp(20), 0, dp(20), 0);
    GradientDrawable ug = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6c47e0, PINK });
    ug.setCornerRadius(dp(999));
    use.setBackground(ug);
    bar.addView(use, new LinearLayout.LayoutParams(-2, dp(44)));
    sheet.addView(bar, new LinearLayout.LayoutParams(-1, -2));
    final JSONArray[] tracks = { new JSONArray() };
    final boolean[] loading = { true };
    final String[] loadError = { null };
    final String[] tab = { "lib" }, picked = { null, null, null }, playing = { null };
    final int[] shown = { 60 };
    final Runnable[] render = new Runnable[1];
    final Runnable[] loadMusicList = new Runnable[1];
    final Runnable drawTabs = new Runnable() {
      public void run() {
        tabs.removeAllViews();
        for (final String[] t : new String[][] { { "lib", "Thư viện" }, { "own", "Nhạc của bạn" } }) {
          boolean active = t[0].equals(tab[0]);
          TextView b = plain(t[1], 14, active ? 0xff6c47e0 : ink, true);
          b.setPadding(dp(14), dp(7), dp(14), dp(7));
          b.setBackground(round(active ? (dark ? 0xff332a48 : 0xffe7e1ff) : soft, 999));
          b.setOnClickListener(v -> { tab[0] = t[0]; shown[0] = 60; run(); render[0].run(); });
          LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
          lp.rightMargin = dp(6);
          tabs.addView(b, lp);
        }
      }
    };
    final java.util.function.Consumer<String[]> choose = t -> {
      picked[0] = t[0]; picked[1] = t[1]; picked[2] = t[2];
      nowTitle.setText(t[1]);
      nowSub.setText(t[2].isEmpty() ? I18n.t("Nhạc của bạn") : t[2]);
      barDivider.setVisibility(View.VISIBLE);
      bar.setVisibility(View.VISIBLE);
    };
    render[0] = () -> {
      list.removeAllViews();
      String rawQ = query.getText().toString().trim();
      String nq = LiveGamePicker.normalized(rawQ);
      if (tab[0].equals("own")) {
        LinearLayout up = new LinearLayout(this);
        up.setGravity(Gravity.CENTER_VERTICAL);
        up.setPadding(dp(8), dp(8), dp(8), dp(8));
        TextView art = plain("＋", 26, 0xff6c47e0, true);
        art.setGravity(Gravity.CENTER);
        art.setBackground(round(dark ? 0xff332a48 : 0xffe7e1ff, 10));
        up.addView(art, new LinearLayout.LayoutParams(dp(52), dp(52)));
        LinearLayout meta = new LinearLayout(this);
        meta.setOrientation(LinearLayout.VERTICAL);
        meta.setPadding(dp(12), 0, 0, 0);
        meta.addView(plain(I18n.t("Chọn nhạc trong máy"), 15, ink, true));
        meta.addView(plain(I18n.t("MP3, M4A… chỉ dùng cho video của bạn"), 12, muted, false));
        up.addView(meta);
        up.setOnClickListener(v -> {
          dialog.dismiss();
          Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
          pick.addCategory(Intent.CATEGORY_OPENABLE);
          pick.setType("audio/*");
          try { startActivityForResult(pick, 402); } catch (Exception e) { Toast.makeText(this, I18n.t("Không mở được trình chọn nhạc."), Toast.LENGTH_SHORT).show(); }
        });
        list.addView(up);
        return;
      }
      if (loading[0]) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(0, dp(40), 0, dp(40));
        ProgressBar pb = new ProgressBar(this);
        box.addView(pb, new LinearLayout.LayoutParams(dp(36), dp(36)));
        TextView t = plain(I18n.t("Đang tải thư viện nhạc…"), 14, muted, false);
        t.setPadding(0, dp(12), 0, 0);
        box.addView(t);
        list.addView(box, new LinearLayout.LayoutParams(-1, -2));
        return;
      }
      if (loadError[0] != null && tracks[0].length() == 0) {
        LinearLayout errBox = new LinearLayout(this);
        errBox.setOrientation(LinearLayout.VERTICAL);
        errBox.setGravity(Gravity.CENTER);
        errBox.setPadding(0, dp(40), 0, dp(40));
        TextView et = plain(loadError[0], 14, muted, false);
        errBox.addView(et);
        TextView retry = plain(I18n.t("Thử lại"), 14, 0xff6c47e0, true);
        retry.setPadding(dp(18), dp(8), dp(18), dp(8));
        retry.setBackground(round(soft, 999));
        retry.setOnClickListener(v -> loadMusicList[0].run());
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-2, -2);
        rp.topMargin = dp(12);
        errBox.addView(retry, rp);
        list.addView(errBox, new LinearLayout.LayoutParams(-1, -2));
        return;
      }
      int count = 0, total = 0;
      for (int i = 0; i < tracks[0].length(); i++) {
        final JSONObject t = tracks[0].optJSONObject(i);
        if (t == null) continue;
        String name = t.optString("title"), artist = t.optString("artist");
        if (!nq.isEmpty()) {
          String normTarget = LiveGamePicker.normalized(name + " " + artist);
          boolean matches = true;
          for (String word : nq.split("\\s+")) {
            if (!word.isEmpty() && !normTarget.contains(word)) { matches = false; break; }
          }
          if (!matches) continue;
        }
        total++;
        if (count >= shown[0]) continue;
        count++;
        final String url = api.origin() + t.optString("url");
        boolean sel = url.equals(picked[0]);
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(8), dp(8), dp(8), dp(8));
        row.setBackground(round(sel ? on : 0x00000000, 14));
        float hue = Math.abs(name.hashCode()) % 360;
        FrameLayout art = new FrameLayout(this);
        GradientDrawable ag = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { Color.HSVToColor(new float[] { hue, 0.65f, 0.85f }), Color.HSVToColor(new float[] { (hue + 50) % 360, 0.75f, 0.6f }) });
        ag.setCornerRadius(dp(12));
        art.setBackground(ag);
        ImageView note = icon("music", 0xffffffff);
        art.addView(note, new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
        row.addView(art, new LinearLayout.LayoutParams(dp(50), dp(50)));
        LinearLayout meta = new LinearLayout(this);
        meta.setOrientation(LinearLayout.VERTICAL);
        meta.setPadding(dp(12), 0, dp(8), 0);
        TextView tt = plain(name, 15, ink, true);
        tt.setSingleLine(true);
        tt.setEllipsize(android.text.TextUtils.TruncateAt.END);
        meta.addView(tt);
        int durSec = t.optInt("duration", 0);
        String durStr = durSec > 0 ? String.format(Locale.ROOT, " · %d:%02d", durSec / 60, durSec % 60) : "";
        TextView st = plain((artist.isEmpty() ? I18n.t("Thư viện Kinnect") : artist) + durStr, 12, muted, false);
        st.setSingleLine(true);
        st.setEllipsize(android.text.TextUtils.TruncateAt.END);
        meta.addView(st);
        row.addView(meta, new LinearLayout.LayoutParams(0, -2, 1));
        FrameLayout play = new FrameLayout(this);
        play.setBackground(round(sel ? 0xff6c47e0 : soft, 999));
        ImageView glyph = icon(url.equals(playing[0]) ? "pause" : "play", sel ? 0xffffffff : ink);
        play.addView(glyph, new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
        row.addView(play, new LinearLayout.LayoutParams(dp(38), dp(38)));
        final String[] entry = { url, name, artist };
        View.OnClickListener tap = v -> {
          if (url.equals(playing[0])) { stopPreview(); playing[0] = null; render[0].run(); return; }
          playPreview(url);
          playing[0] = url;
          choose.accept(entry);
          render[0].run();
        };
        row.setOnClickListener(tap);
        play.setOnClickListener(tap);
        list.addView(row);
      }
      if (total == 0) {
        TextView e = plain(nq.isEmpty() ? I18n.t("Thư viện chưa có bài nào.") : I18n.t("Không tìm thấy bài phù hợp."), 14, muted, false);
        e.setGravity(Gravity.CENTER);
        e.setPadding(0, dp(30), 0, dp(30));
        list.addView(e, new LinearLayout.LayoutParams(-1, -2));
      }
      if (total > shown[0]) {
        TextView more = plain(I18n.t("Xem thêm (") + (total - shown[0]) + I18n.t(" bài)"), 14, ink, true);
        more.setGravity(Gravity.CENTER);
        more.setPadding(dp(18), dp(8), dp(18), dp(8));
        more.setBackground(round(soft, 999));
        more.setOnClickListener(v -> { shown[0] += 60; render[0].run(); });
        LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(-2, -2);
        mp.gravity = Gravity.CENTER_HORIZONTAL;
        mp.setMargins(0, dp(8), 0, dp(8));
        list.addView(more, mp);
      }
    };
    loadMusicList[0] = () -> {
      loading[0] = true;
      loadError[0] = null;
      render[0].run();
      api.call("GET", "/api/music", null, (data, error, status) -> {
        if (isFinishing()) return;
        loading[0] = false;
        JSONArray list2 = data == null ? null : data.optJSONArray("tracks");
        if (list2 != null) {
          tracks[0] = list2;
          loadError[0] = null;
        } else {
          loadError[0] = error != null && !error.isEmpty() ? error : I18n.t("Không thể tải nhạc từ máy chủ.");
        }
        render[0].run();
      });
    };
    query.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence a, int b, int c, int d) {}
      public void onTextChanged(CharSequence a, int b, int c, int d) {}
      public void afterTextChanged(android.text.Editable e) { shown[0] = 60; render[0].run(); }
    });
    use.setOnClickListener(v -> { if (picked[0] != null) setMusic(picked[0], null, picked[1]); dialog.dismiss(); });
    dialog.setOnDismissListener(x -> stopPreview());
    drawTabs.run();
    dialog.setContentView(sheet);
    Window w = dialog.getWindow();
    if (w != null) {
      w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(0));
      ApprovedTypography.sheet(w.getDecorView());
      w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.5f);
      w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    }
    dialog.setOnShowListener(d -> {
      Window win = dialog.getWindow();
      if (win != null) {
        win.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, Math.round(getResources().getDisplayMetrics().heightPixels * 0.86f));
        win.setGravity(Gravity.BOTTOM);
      }
    });
    dialog.show();
    if (dialog.getWindow() != null) {
      dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, Math.round(getResources().getDisplayMetrics().heightPixels * 0.86f));
      dialog.getWindow().setGravity(Gravity.BOTTOM);
    }
    if (music != null) music.pause();
    loadMusicList[0].run();
  }

  private TextView plain(String s, float size, int color, boolean bold) {
    TextView t = new KinnectText(this);
    t.setText(s);
    t.setTextSize(size);
    t.setTextColor(color);
    if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
    return t;
  }

  private void playPreview(String url) {
    stopPreview();
    try {
      previewPlayer = new MediaPlayer();
      Map<String, String> headers = new HashMap<>();
      headers.put("Cookie", api.jar());
      previewPlayer.setDataSource(this, Uri.parse(url), headers);
      previewPlayer.setOnPreparedListener(MediaPlayer::start);
      previewPlayer.prepareAsync();
    } catch (Exception ignored) {}
  }

  private void stopPreview() {
    if (previewPlayer != null) { try { previewPlayer.release(); } catch (Exception ignored) {} previewPlayer = null; }
  }

  @Override
  protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (result != RESULT_OK || data == null || data.getData() == null) return;
    if(request==407){openVideoPro(data.getData());return;}
    if(request==408){videoProEdited=true;showVideoReview(data.getData());return;}
    if(request==405){openPhotoPro(data.getData());return;}
    if(request==406){final String path=data.getStringExtra(EXTRA_IMAGE);if(path==null)return;final File edited=new File(path);worker.execute(()->{try{Bitmap shown=PhotoRenderer.decode(edited,1280);ui.post(()->{capturedPhoto=edited;photoProEdited=true;showReview(shown);});}catch(Exception|OutOfMemoryError e){ui.post(()->Toast.makeText(this,I18n.t("Không mở được ảnh."),Toast.LENGTH_SHORT).show());}});return;}
    if(request==403)photoProEdited=false;
    if (request == 402) setMusic(null, data.getData(), "Nhạc của bạn");
    if (request == 403) {final Uri selected=data.getData();worker.execute(()->{try{File local=File.createTempFile("gallery-photo-",".img",getCacheDir());try(InputStream in=getContentResolver().openInputStream(selected);OutputStream out=new FileOutputStream(local)){byte[] buffer=new byte[32768];long bytes=0;for(int n;(n=in.read(buffer))!=-1;){bytes+=n;if(bytes>64L*1024*1024)throw new IOException("large");out.write(buffer,0,n);}}Bitmap shown=PhotoRenderer.decode(local,1280);ui.post(()->{if(isFinishing()||isDestroyed())return;capturedPhoto=local;photoProEdited=false;showReview(shown);});}catch(Exception|OutOfMemoryError e){ui.post(()->Toast.makeText(this,I18n.t("Không mở được ảnh."),Toast.LENGTH_SHORT).show());}});}
    if (request == 404) {videoProEdited=false;try{getContentResolver().takePersistableUriPermission(data.getData(),data.getFlags()&Intent.FLAG_GRANT_READ_URI_PERMISSION);}catch(SecurityException ignored){}showVideoReview(data.getData());}
  }

  private void setMusic(String url, Uri local, String title) {
    if (music != null) { music.release(); music = null; }
    musicUrl = url;
    musicLocal = local;
    musicLabel.setText(title == null ? I18n.t("Thêm nhạc") : title.replaceAll("\\s+", " ").trim());
    musicLabel.setTextColor(title == null ? 0xffffffff : GCAM_AMBER);
    if (url == null && local == null) return;
    try {
      music = new MediaPlayer();
      music.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());
      if (url != null) {
        Map<String, String> headers = new HashMap<>();
        headers.put("Cookie", api.jar());
        music.setDataSource(this, Uri.parse(url), headers);
      } else music.setDataSource(this, local);
      music.setLooping(true);
      music.setOnPreparedListener(p -> { if (!recording) p.start(); });
      music.setOnErrorListener((p, w, e) -> { Toast.makeText(this, I18n.t("Không phát được bài nhạc này."), Toast.LENGTH_SHORT).show(); return true; });
      music.prepareAsync();
    } catch (Exception e) {
      Toast.makeText(this, I18n.t("Không phát được bài nhạc này."), Toast.LENGTH_SHORT).show();
      musicUrl = null;
      musicLocal = null;
    }
  }

  // ======================= Các view vẽ tay chuẩn Google Camera =======================
  /** Vòng lấy nét cảm ứng chuẩn Google Camera (Pixel Camera Focus & Exposure Ring). */
  static final class FocusRingView extends View {
    private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    private float fx = -1, fy = -1, scale = 1f, alpha = 0f;
    private ValueAnimator anim;
    private final Runnable fadeOut = () -> animateAlpha(0f, 280);

    FocusRingView(android.content.Context c) { super(c); }

    void showAt(float x, float y) {
      fx = x;
      fy = y;
      removeCallbacks(fadeOut);
      if (anim != null) anim.cancel();
      anim = ValueAnimator.ofFloat(1.35f, 1.0f);
      anim.setDuration(220);
      alpha = 1f;
      anim.addUpdateListener(a -> {
        scale = (Float) a.getAnimatedValue();
        invalidate();
      });
      anim.start();
      postDelayed(fadeOut, 1100);
    }

    private void animateAlpha(float target, long duration) {
      if (anim != null) anim.cancel();
      anim = ValueAnimator.ofFloat(alpha, target);
      anim.setDuration(duration);
      anim.addUpdateListener(a -> {
        alpha = (Float) a.getAnimatedValue();
        invalidate();
      });
      anim.start();
    }

    @Override
    protected void onDraw(Canvas c) {
      if (alpha <= 0.01f || fx < 0 || fy < 0) return;
      float density = getResources().getDisplayMetrics().density;
      float r = 34f * density * scale;
      int a = Math.round(alpha * 255);
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeWidth(2f * density);
      p.setColor((a << 24) | 0xfffdd663);
      c.drawCircle(fx, fy, r, p);
      // 4 vạch chia bên trong vòng lấy nét kiểu Google Camera
      float tick = 5f * density;
      c.drawLine(fx - r, fy, fx - r + tick, fy, p);
      c.drawLine(fx + r - tick, fy, fx + r, fy, p);
      c.drawLine(fx, fy - r, fx, fy - r + tick, p);
      c.drawLine(fx, fy + r - tick, fx, fy + r, p);
      p.setStyle(Paint.Style.FILL);
      p.setColor(((a / 3) << 24) | 0xfffdd663);
      c.drawCircle(fx, fy, 3.5f * density, p);
      // Thanh trượt phơi sáng mặt trời (Google Camera Sun Exposure Indicator) cạnh vòng lấy nét
      float sx = fx + r + 16f * density < getWidth() - 20f * density ? fx + r + 16f * density : fx - r - 16f * density;
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeWidth(1.5f * density);
      p.setColor(((a * 2 / 3) << 24) | 0xfffdd663);
      c.drawLine(sx, fy - 24f * density, sx, fy - 7f * density, p);
      c.drawLine(sx, fy + 7f * density, sx, fy + 24f * density, p);
      p.setStyle(Paint.Style.FILL);
      p.setColor((a << 24) | 0xfffdd663);
      c.drawCircle(sx, fy, 3.2f * density, p);
      for (int i = 0; i < 8; i++) {
        double ang = i * Math.PI / 4.0;
        float x1 = sx + (float) Math.cos(ang) * 4.8f * density, y1 = fy + (float) Math.sin(ang) * 4.8f * density;
        float x2 = sx + (float) Math.cos(ang) * 6.8f * density, y2 = fy + (float) Math.sin(ang) * 6.8f * density;
        c.drawLine(x1, y1, x2, y2, p);
      }
    }
  }

  /** Nút chụp chuẩn Google Camera: Ảnh = vành trắng sắc nét + đĩa trắng lớn; Video = vành trắng + tâm đỏ Pixel (#EE2B2B), khi quay chuyển thành hình vuông bo góc. */
  static final class ShutterView extends View {
    private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    private String mode = "video";
    private boolean rec;
    private float progress;

    ShutterView(android.content.Context c) { super(c); }

    void setMode(String m) { mode = m; invalidate(); }

    void setRecording(boolean r) { rec = r; invalidate(); }

    void setProgress(float v) { progress = Math.max(0, Math.min(1, v)); invalidate(); }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
      int a = e.getActionMasked();
      if (a == MotionEvent.ACTION_DOWN) animate().scaleX(0.91f).scaleY(0.91f).setDuration(90).start();
      else if (a == MotionEvent.ACTION_UP || a == MotionEvent.ACTION_CANCEL) animate().scaleX(1f).scaleY(1f).setDuration(140).start();
      return super.onTouchEvent(e);
    }

    @Override
    protected void onDraw(Canvas c) {
      float w = getWidth(), h = getHeight(), cx = w / 2f, cy = h / 2f, r = Math.min(w, h) / 2f;
      float density = getResources().getDisplayMetrics().density;
      float ringStroke = 3.5f * density;
      float ringRadius = r - ringStroke;

      // Nền tối nhẹ giữa vành ngoài và nhân nút chụp kiểu Google Camera
      p.setStyle(Paint.Style.FILL);
      p.setColor(0x44000000);
      c.drawCircle(cx, cy, ringRadius, p);

      // Vành ngoài màu trắng chuẩn Google Camera
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeWidth(ringStroke);
      p.setColor(rec ? 0x55ffffff : 0xffffffff);
      c.drawCircle(cx, cy, ringRadius, p);

      if (rec) {
        p.setStrokeCap(Paint.Cap.ROUND);
        p.setColor(GCAM_RED);
        RectF arc = new RectF(cx - ringRadius, cy - ringRadius, cx + ringRadius, cy + ringRadius);
        c.drawArc(arc, -90, 360 * progress, false, p);
      }

      p.setStyle(Paint.Style.FILL);
      if (mode.equals("photo")) {
        p.setColor(0xffffffff);
        c.drawCircle(cx, cy, r * 0.77f, p);
      } else if (rec) {
        p.setColor(GCAM_RED);
        float s = r * 0.34f;
        c.drawRoundRect(new RectF(cx - s, cy - s, cx + s, cy + s), 8f * density, 8f * density, p);
      } else if (mode.equals("live")) {
        p.setColor(0xffff3b5c);
        c.drawCircle(cx, cy, r * 0.64f, p);
      } else {
        p.setColor(0xffffffff);
        c.drawCircle(cx, cy, r * 0.77f, p);
        p.setColor(GCAM_RED);
        c.drawCircle(cx, cy, r * 0.34f, p);
      }
    }
  }

  /** Lưới 3×3 kèm tâm ngắm cân bằng (+) chuẩn Google Camera và vùng che khi chọn tỉ lệ 3:4 hoặc 1:1. */
  static final class GridOverlay extends View {
    private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    private boolean grid;
    private int ratio;

    GridOverlay(android.content.Context c) { super(c); }

    void setGrid(boolean g) { grid = g; invalidate(); }

    void setRatio(int r) { ratio = r; invalidate(); }

    @Override
    protected void onDraw(Canvas c) {
      float w = getWidth(), h = getHeight(), top = 0, bottom = h;
      float density = getResources().getDisplayMetrics().density;
      if (ratio > 0) {
        float fh = ratio == 1 ? w * 4f / 3f : w;
        top = (h - fh) / 2f;
        bottom = top + fh;
        p.setStyle(Paint.Style.FILL);
        p.setColor(0xd9000000);
        c.drawRect(0, 0, w, top, p);
        c.drawRect(0, bottom, w, h, p);
      }
      if (!grid) return;
      p.setStyle(Paint.Style.STROKE);
      p.setColor(0x66ffffff);
      p.setStrokeWidth(1f * density);
      for (int i = 1; i < 3; i++) {
        c.drawLine(w * i / 3f, top, w * i / 3f, bottom, p);
        c.drawLine(0, top + (bottom - top) * i / 3f, w, top + (bottom - top) * i / 3f, p);
      }
      // Tâm ngắm cân bằng (+) ở giữa khung hình kiểu Google Camera
      float cx = w / 2f, cy = (top + bottom) / 2f, cross = 10f * density;
      p.setColor(0x99fdd663);
      p.setStrokeWidth(1.5f * density);
      c.drawLine(cx - cross, cy, cx + cross, cy, p);
      c.drawLine(cx, cy - cross, cx, cy + cross, p);
      p.setColor(0x44ffffff);
      c.drawCircle(cx, cy, 18f * density, p);
    }
  }
}
