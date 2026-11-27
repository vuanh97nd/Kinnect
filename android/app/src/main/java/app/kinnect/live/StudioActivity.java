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
 * - Chế độ Ảnh / Video (/ Tin 15 giây), vuốt ngang trên khung hình để đổi bộ
 * lọc.
 * - 16 bộ lọc có ảnh xem trước + độ đậm, làm đẹp 5 mức, 11 sticker theo khuôn
 * mặt (FxEngine).
 * - Hẹn giờ, lưới, đèn, tỉ lệ khung, nhạc nền; chụp xong có màn xem lại để lưu
 * / đăng bài / đăng tin.
 * Mọi khung hình được vẽ lại bằng Canvas nên hiệu ứng nằm luôn trong ảnh và
 * video.
 */
public final class StudioActivity extends Activity implements Choreographer.FrameCallback {
  static final String EXTRA_VIDEO = "video", EXTRA_STORY = "story", EXTRA_PHOTO = "photo", EXTRA_IMAGE = "image",
      EXTRA_ACTION = "action", EXTRA_MODE = "mode";
  private static final int W = 720, H = 1280, FW = 540, FH = 960, PW = 1080, PH = 1920;
  private static final int ACCENT = 0xff7652e8, PINK = 0xffff4f9a;
  private static final int GCAM_AMBER = 0xfffdd663, GCAM_RED = WebDesign.LIVE_RED, GCAM_PILL = 0xbf18181d,
      GCAM_BTN = 0xff28282d;

  private final FxEngine fx = new FxEngine();
  {
    fx.beautyOn = false;
  }
  private FrameLayout root, stage, panelHost, reviewLayer;
  private TextureView camera;
  private SurfaceView preview;
  private TextView timer, musicLabel, faceStatus, filterToast, countdown;
  private ShutterView shutter;
  private LinearLayout modeTabs, rail, zoomBar, creativeBar, studioTopBar, bottomBar;
  private FocusRingView focusRing;
  private View flipButton;
  private GridOverlay gridOverlay;
  private android.app.Dialog musicDialog;
  private volatile CameraDevice device;
  private volatile CameraCaptureSession session;
  private volatile CaptureRequest.Builder previewRequest;
  private volatile Surface previewSurface;
  private final Object cameraLock = new Object();
  private final java.util.concurrent.atomic.AtomicInteger cameraGeneration = new java.util.concurrent.atomic.AtomicInteger(0);
  private volatile boolean openingCamera = false, loadingStill = false;
  private volatile Thread muxThread;
  private HandlerThread cameraThread;
  private Handler cameraHandler;
  private final Handler ui = new Handler(Looper.getMainLooper());
  private boolean front = true, recording = false, previewReady = false, torch = false, grid = false, story = false,
      busy = false;
  private String mode = "video", panel = "";
  private int limitSeconds = 0, timerSeconds = 0, ratio = 0; // 0: 9:16 · 1: 3:4 · 2: 1:1
  private Bitmap frame, still, stillFull, reviewBitmap, galleryThumbBitmap;
  private MediaRecorder recorder;
  private Surface recorderSurface;
  private boolean hardwareRecorder = true;
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
  private boolean savingPhoto;
  private volatile boolean isResumedActive = false;
  private ProgressDialog muxProgress;

  private int dp(float n) {
    return Math.round(n * getResources().getDisplayMetrics().density * WebDesign.UI_SCALE);
  }

  private GradientDrawable round(int color, float radius) {
    GradientDrawable g = new GradientDrawable();
    g.setColor(color);
    g.setCornerRadius(dp(radius));
    return g;
  }

  private TextView text(String s, float size, int color, boolean bold) {
    TextView t = new KinnectText(this);
    t.setText(s);
    t.setTextSize(size);
    t.setTextColor(color);
    if (bold)
      t.setTypeface(Typeface.DEFAULT_BOLD);
    t.setShadowLayer(dp(3), 0, dp(1), 0x99000000);
    return t;
  }

  private ImageView icon(String name, int color) {
    ImageView v = new ImageView(this);
    int id = WebIcons.resolve(this, name);
    if (id != 0) {
      android.graphics.drawable.Drawable d = WebIcons.load(this, name);
      d.setTint(color);
      v.setImageDrawable(d);
    }
    return v;
  }

  private int statusBarHeight() {
    int resId = getResources().getIdentifier("status_bar_height", "dimen", "android");
    int fromRes = resId > 0 ? getResources().getDimensionPixelSize(resId) : 0;
    return Math.max(fromRes, dp(24));
  }

  // ======================= Giao diện =======================
  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().setStatusBarColor(0xff000000);
    getWindow().setNavigationBarColor(0xff000000);
    final boolean isDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (isDebug && getIntent() != null && getIntent().getBooleanExtra("ui_review_fixture", false)) {
      NativeApi.enableFixture(this, true);
    }
    story = getIntent().getBooleanExtra(EXTRA_STORY, false);
    String startMode = getIntent().getStringExtra(EXTRA_MODE);
    if (startMode != null)
      mode = startMode;
    if (story) {
      mode = "video";
      limitSeconds = 15;
    }
    root = new FrameLayout(this);
    root.setBackgroundColor(0xff000000);
    final int minTopInset = statusBarHeight();
    root.setPadding(0, minTopInset, 0, 0);
    setContentView(root);
    root.setOnApplyWindowInsetsListener((v, i) -> {
      if (Build.VERSION.SDK_INT >= 30) {
        android.graphics.Insets insets = i.getInsets(
            WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
        android.graphics.Insets ignored = i.getInsetsIgnoringVisibility(
            WindowInsets.Type.statusBars() | WindowInsets.Type.displayCutout());
        int topInset = Math.max(Math.max(insets.top, ignored.top), minTopInset);
        v.setPadding(insets.left, topInset, insets.right, insets.bottom);
      } else {
        int topInset = Math.max(i.getSystemWindowInsetTop(), minTopInset);
        v.setPadding(i.getSystemWindowInsetLeft(), topInset,
            i.getSystemWindowInsetRight(), i.getSystemWindowInsetBottom());
      }
      return i;
    });
    if (isDebug && NativeApi.isFixtureEnabled() && getIntent() != null
        && getIntent().getBooleanExtra("open_music", false)) {
      getIntent().removeExtra("open_music");
      root.postDelayed(this::chooseMusic, 400);
    }

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
    int height = getResources().getDisplayMetrics().heightPixels;
    int stageH = Math.min(width * 16 / 9, Math.max(dp(240), height - dp(8)));
    FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(width, stageH, Gravity.TOP);
    sp.topMargin = dp(4);
    root.addView(stage, sp);
    root.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or2, ob) -> {
      int availW = Math.max(1, (r - l) - v.getPaddingLeft() - v.getPaddingRight());
      int availH = Math.max(1, (b - t) - v.getPaddingTop() - v.getPaddingBottom() - dp(8));
      int desiredH = Math.min(availW * 16 / 9, availH);
      ViewGroup.LayoutParams lp = stage.getLayoutParams();
      if (lp != null && (lp.width != availW || lp.height != desiredH)) {
        lp.width = availW;
        lp.height = desiredH;
        stage.setLayoutParams(lp);
      }
    });
    camera.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
      public void onSurfaceTextureAvailable(SurfaceTexture s, int w, int h) {
        openCamera();
      }

      public void onSurfaceTextureSizeChanged(SurfaceTexture s, int w, int h) {
      }

      public boolean onSurfaceTextureDestroyed(SurfaceTexture s) {
        closeCamera();
        return true;
      }

      public void onSurfaceTextureUpdated(SurfaceTexture s) {
      }
    });
    preview.getHolder().addCallback(new SurfaceHolder.Callback() {
      public void surfaceCreated(SurfaceHolder h) {
        previewReady = true;
      }

      public void surfaceChanged(SurfaceHolder h, int f, int w, int hh) {
      }

      public void surfaceDestroyed(SurfaceHolder h) {
        previewReady = false;
      }
    });
    // Vuốt ngang để đổi bộ lọc, chạm hai lần để đổi camera, chạm 1 lần để lấy nét
    // kiểu Google Camera
    final GestureDetector gestures = new GestureDetector(this, new GestureDetector.SimpleOnGestureListener() {
      public boolean onDown(MotionEvent e) {
        return true;
      }

      public boolean onFling(MotionEvent a, MotionEvent b, float vx, float vy) {
        if (Math.abs(vx) < Math.abs(vy) || Math.abs(b.getX() - a.getX()) < dp(40))
          return false;
        stepFilter(vx < 0 ? 1 : -1);
        return true;
      }

      public boolean onDoubleTap(MotionEvent e) {
        flip();
        return true;
      }

      public boolean onSingleTapConfirmed(MotionEvent e) {
        if (!panel.isEmpty()) {
          showPanel("");
          return true;
        }
        triggerTapFocus(e.getX(), e.getY());
        return true;
      }
    });
    final ScaleGestureDetector pinch = new ScaleGestureDetector(this,
        new ScaleGestureDetector.SimpleOnScaleGestureListener() {
          public boolean onScale(ScaleGestureDetector d) {
            if (still == null)
              setZoom(zoom * d.getScaleFactor());
            return true;
          }
        });
    stage.setOnTouchListener((v, e) -> {
      pinch.onTouchEvent(e);
      if (!pinch.isInProgress() && e.getPointerCount() == 1)
        gestures.onTouchEvent(e);
      return true;
    });

    // Thanh cài đặt nhanh trên cùng chuẩn Google Camera: Đóng · Nhạc nền · Cài đặt
    // nhanh (Flash, Hẹn giờ, Lưới, Tỉ lệ)
    LinearLayout top = studioTopBar = new LinearLayout(this);
    top.setGravity(Gravity.CENTER_VERTICAL);
    top.setPadding(dp(8), dp(12), dp(8), dp(20));
    top.setBackground(
        new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x99000000, 0x00000000 }));
    ImageView close = icon("close", 0xffffffff);
    close.setPadding(dp(10), dp(10), dp(10), dp(10));
    GradientDrawable closeBg = round(GCAM_PILL, 999);
    closeBg.setStroke(dp(1), 0x22ffffff);
    close.setBackground(closeBg);
    close.setContentDescription(I18n.t("Đóng"));
    close.setOnClickListener(v -> requestCloseStudio());
    close.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    top.addView(UiMetrics.wrapMinTouchTarget(this, close, 48));
    FrameLayout musicWrap = new FrameLayout(this);
    musicLabel = text(I18n.t("Thêm nhạc"), 13, 0xffffffff, true);
    musicLabel.setGravity(Gravity.CENTER);
    musicLabel.setPadding(dp(10), 0, dp(12), 0);
    GradientDrawable musicBg = round(GCAM_PILL, 999);
    musicBg.setStroke(dp(1), 0x26ffffff);
    musicLabel.setBackground(musicBg);
    musicLabel.setCompoundDrawablesRelativeWithIntrinsicBounds(tinted("music"), null, null, null);
    musicLabel.setCompoundDrawablePadding(dp(5));
    musicLabel.setSingleLine(true);
    musicLabel.setEllipsize(android.text.TextUtils.TruncateAt.END);
    musicLabel.setMinimumWidth(UiMetrics.dpRaw(this, 48));
    musicLabel.setMaxWidth(dp(156));
    musicLabel.setOnClickListener(v -> chooseMusic());
    FrameLayout.LayoutParams mlp = new FrameLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48), Gravity.CENTER);
    mlp.leftMargin = dp(4);
    mlp.rightMargin = dp(4);
    musicWrap.addView(musicLabel, mlp);
    UiMetrics.enforceMinTouchTarget(musicLabel, 48);
    top.addView(musicWrap, new LinearLayout.LayoutParams(0, UiMetrics.dpRaw(this, 48), 1f));

    // Thanh công cụ nhanh kiểu Google Camera (Flash, Timer, Grid, Ratio/Duration)
    // nằm gọn trên thanh đỉnh
    rail = new LinearLayout(this);
    rail.setOrientation(LinearLayout.HORIZONTAL);
    rail.setGravity(Gravity.CENTER_VERTICAL);
    rail.setPadding(dp(2), 0, dp(2), 0);
    GradientDrawable railBg = round(GCAM_PILL, 999);
    railBg.setStroke(dp(1), 0x22ffffff);
    rail.setBackground(railBg);
    top.addView(rail, new LinearLayout.LayoutParams(-2, -2));
    stage.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    buildRail();

    faceStatus = text("", 13, 0xffffffff, false);
    FrameLayout.LayoutParams fs = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    fs.topMargin = UiMetrics.dpRaw(this, 80);
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

    // Vùng dưới chuẩn Google Camera: Cụm Zoom (1x/2x/4x) · Công cụ sáng tạo · Hàng
    // nút chụp 3 cột · Thanh chuyển chế độ dạng viên thuốc
    LinearLayout bottom = bottomBar = new LinearLayout(this);
    bottom.setOrientation(LinearLayout.VERTICAL);
    bottom.setGravity(Gravity.CENTER_HORIZONTAL);
    bottom.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP,
        new int[] { 0xf5000000, 0xcc000000, 0x00000000 }));
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

    // Hàng nút chụp chính 3 cột chuẩn Google Camera: Thư viện (trái) · Nút
    // chụp/quay lớn (giữa) · Đổi camera (phải)
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

    // Thanh chuyển chế độ dạng viên thuốc (Material 3 Pill Carousel) ở đáy màn hình
    // như Google Camera
    modeTabs = new LinearLayout(this);
    modeTabs.setGravity(Gravity.CENTER);
    modeTabs.setPadding(dp(16), dp(2), dp(16), dp(2));
    bottom.addView(modeTabs, new LinearLayout.LayoutParams(-1, -2));
    renderModes();
    root.addView(bottom, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));

    reviewLayer = new FrameLayout(this);
    reviewLayer.setBackgroundColor(0xff000000);
    reviewLayer.setClickable(true);
    reviewLayer.setFocusable(true);
    reviewLayer.setVisibility(View.GONE);
    root.addView(reviewLayer, new FrameLayout.LayoutParams(-1, -1));

    frame = Bitmap.createBitmap(FW, FH, Bitmap.Config.ARGB_8888);
    thumb = Bitmap.createBitmap(90, 120, Bitmap.Config.ARGB_8888);
    String photoUri = getIntent().getStringExtra(EXTRA_PHOTO);
    if (photoUri != null)
      loadStill(Uri.parse(photoUri), story ? "video" : "photo");
    String reviewUri = getIntent().getStringExtra("review_video");
    if (reviewUri != null)
      showVideoReview(Uri.parse(reviewUri));
    if (still == null && photoUri == null)
      ensurePermissions();
    if (isDebug && NativeApi.isFixtureEnabled() && getIntent() != null) {
      final String openPanel = getIntent().getStringExtra("open_panel");
      if (openPanel != null && ("filter".equals(openPanel) || "beauty".equals(openPanel) || "sticker".equals(openPanel))) {
        getIntent().removeExtra("open_panel");
        root.postDelayed(() -> {
          if (!isFinishing() && !isDestroyed() && reviewLayer.getVisibility() != View.VISIBLE)
            showPanel(openPanel);
        }, 650);
      }
      if (getIntent().getBooleanExtra("open_edit", false)) {
        getIntent().removeExtra("open_edit");
        root.postDelayed(this::openFixturePhotoReview, 650);
      }
    }
  }

  private void ensurePermissions() {
    List<String> need = new ArrayList<>();
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
      need.add(Manifest.permission.CAMERA);
    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
      need.add(Manifest.permission.RECORD_AUDIO);
    if (!need.isEmpty())
      requestPermissions(need.toArray(new String[0]), 401);
  }

  private ImageView galleryThumbView;

  private View buildGalleryWell() {
    FrameLayout well = new FrameLayout(this);
    GradientDrawable bg = round(GCAM_BTN, 999);
    bg.setStroke(dp(2), 0x55ffffff);
    well.setBackground(
        new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff), bg, null));
    well.setClipToOutline(true);
    galleryThumbView = new ImageView(this);
    galleryThumbView.setScaleType(ImageView.ScaleType.CENTER_CROP);
    galleryThumbView.setVisibility(View.GONE);
    well.addView(galleryThumbView, new FrameLayout.LayoutParams(-1, -1));
    ImageView glyph = icon("image", 0xffffffff);
    well.addView(glyph, new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
    well.setContentDescription(I18n.t("Thư viện"));
    well.setOnClickListener(v -> openGallery());
    int raw52 = Math.max(UiMetrics.dpRaw(this, 48), dp(52));
    well.setLayoutParams(new LinearLayout.LayoutParams(raw52, raw52));
    UiMetrics.enforceMinTouchTarget(well, 48);
    return well;
  }

  private View buildFlipButton() {
    FrameLayout btn = new FrameLayout(this);
    GradientDrawable bg = round(GCAM_BTN, 999);
    bg.setStroke(dp(1), 0x28ffffff);
    btn.setBackground(
        new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff), bg, null));
    final ImageView glyph = icon("flip", 0xffffffff);
    btn.addView(glyph, new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
    btn.setContentDescription(I18n.t("Lật"));
    btn.setOnClickListener(v -> {
      if (recording || still != null)
        return;
      glyph.animate().rotationBy(180f).setDuration(260).start();
      flip();
    });
    int raw52 = Math.max(UiMetrics.dpRaw(this, 48), dp(52));
    btn.setLayoutParams(new LinearLayout.LayoutParams(raw52, raw52));
    UiMetrics.enforceMinTouchTarget(btn, 48);
    return btn;
  }

  private void renderZoomBar() {
    if (zoomBar == null)
      return;
    zoomBar.setVisibility(still != null || mode.equals("live") ? View.GONE : View.VISIBLE);
    zoomBar.setPadding(dp(2), 0, dp(2), 0);
    zoomBar.removeAllViews();
    float[] stops = { 1f, 2f, 4f };
    int activeIdx = zoom < 1.6f ? 0 : zoom < 3.2f ? 1 : 2;
    for (int i = 0; i < stops.length; i++) {
      final float target = stops[i];
      boolean on = i == activeIdx;
      TextView chip = text(
          on ? (Math.abs(zoom - Math.round(zoom)) < 0.08f ? Math.round(zoom) + "×"
              : String.format(Locale.US, "%.1f×", zoom)) : Math.round(target) + "",
          on ? 12 : 11, on ? 0xff111114 : 0xd9ffffff, true);
      chip.setShadowLayer(0, 0, 0, 0);
      chip.setGravity(Gravity.CENTER);
      chip.setBackground(round(on ? GCAM_AMBER : 0x00000000, 999));
      int size = dp(on ? 34 : 30);
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(size, size);
      chip.setLayoutParams(lp);
      chip.setOnClickListener(v -> animateZoomTo(target));
      zoomBar.addView(UiMetrics.wrapMinTouchTarget(this, chip, 48));
    }
  }

  private void animateZoomTo(float target) {
    if (still != null)
      return;
    ValueAnimator anim = ValueAnimator.ofFloat(zoom, target);
    anim.setDuration(200);
    anim.addUpdateListener(a -> setZoom((Float) a.getAnimatedValue(), false));
    anim.start();
    showFilterName(String.format(Locale.US, "%.0f×", target));
  }

  private void renderCreativeBar() {
    if (creativeBar == null)
      return;
    creativeBar.setVisibility(recording ? View.INVISIBLE : View.VISIBLE);
    creativeBar.removeAllViews();
    boolean filterActive = !fx.filter.equals("none") || panel.equals("filter");
    boolean beautyActive = fx.beautyOn || panel.equals("beauty");
    boolean stickerActive = !fx.sticker.equals("none") || panel.equals("sticker");
    creativeBar.addView(creativePill("palette", I18n.t("Bộ lọc"), panel.equals("filter"), filterActive,
        () -> showPanel(panel.equals("filter") ? "" : "filter")));
    creativeBar.addView(creativePill("wand", I18n.t("Làm đẹp"), panel.equals("beauty"), beautyActive,
        () -> showPanel(panel.equals("beauty") ? "" : "beauty")));
    creativeBar.addView(creativePill("smile", "Sticker", panel.equals("sticker"), stickerActive,
        () -> showPanel(panel.equals("sticker") ? "" : "sticker")));
  }

  private View creativePill(String iconName, String label, boolean open, boolean active, Runnable click) {
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
    if (open)
      t.setShadowLayer(0, 0, 0, 0);
    t.setPadding(dp(6), 0, 0, 0);
    pill.addView(t);
    pill.setContentDescription(label);
    pill.setOnClickListener(v -> click.run());
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, dp(34));
    lp.setMargins(dp(4), 0, dp(4), 0);
    pill.setLayoutParams(lp);
    return UiMetrics.wrapMinTouchTarget(this, pill, 48);
  }

  private void buildRail() {
    rail.removeAllViews();
    if (still == null)
      rail.addView(railButton(torch ? "flash" : "flash_off", torch ? I18n.t("Đèn: bật") : I18n.t("Đèn"), torch, () -> {
        torch = !torch;
        applyTorch();
        buildRail();
      }));
    if (!mode.equals("live"))
      rail.addView(
          railButton("timer", timerSeconds == 0 ? I18n.t("Hẹn giờ") : timerSeconds + "s", timerSeconds > 0, () -> {
            timerSeconds = timerSeconds == 0 ? 3 : timerSeconds == 3 ? 10 : 0;
            buildRail();
          }));
    if (!mode.equals("live"))
      rail.addView(railButton("grid", grid ? I18n.t("Lưới: bật") : I18n.t("Lưới"), grid, () -> {
        grid = !grid;
        gridOverlay.setGrid(grid);
        buildRail();
      }));
    if (mode.equals("photo"))
      rail.addView(railBadgeButton(ratio == 0 ? "9:16" : ratio == 1 ? "3:4" : "1:1", ratio != 0, () -> {
        ratio = (ratio + 1) % 3;
        gridOverlay.setRatio(ratio);
        buildRail();
      }));
    if (mode.equals("video") && !story)
      rail.addView(railBadgeButton(limitSeconds == 0 ? "∞" : limitSeconds + "s", limitSeconds > 0, () -> {
        limitSeconds = limitSeconds == 0 ? 15 : limitSeconds == 15 ? 30 : limitSeconds == 30 ? 60 : 0;
        buildRail();
      }));
    if (musicLabel != null) {
      int railCount = Math.max(1, rail.getChildCount());
      int availForMusic = getResources().getDisplayMetrics().widthPixels
          - dp(16) - UiMetrics.dpRaw(this, 48) - dp(4)
          - railCount * UiMetrics.dpRaw(this, 48) - dp(8);
      int cap = dp(railCount >= 3 ? 156 : 185);
      musicLabel.setMaxWidth(Math.max(UiMetrics.dpRaw(this, 48), Math.min(cap, availForMusic)));
    }
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
    b.setOnClickListener(v -> {
      if (!recording)
        click.run();
    });
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(34), dp(34));
    b.setLayoutParams(lp);
    return UiMetrics.wrapMinTouchTarget(this, b, 48);
  }

  private View railBadgeButton(String badgeText, boolean active, Runnable click) {
    TextView b = text(badgeText, 11, active ? 0xff111114 : 0xffffffff, true);
    if (active)
      b.setShadowLayer(0, 0, 0, 0);
    b.setGravity(Gravity.CENTER);
    b.setPadding(dp(8), 0, dp(8), 0);
    b.setBackground(round(active ? GCAM_AMBER : 0x00000000, 999));
    b.setContentDescription(badgeText);
    b.setOnClickListener(v -> {
      if (!recording)
        click.run();
    });
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, dp(28));
    b.setLayoutParams(lp);
    return UiMetrics.wrapMinTouchTarget(this, b, 48);
  }

  private View galleryAction;
  private LiveSetupSheet liveSetup;
  private final Runnable autoLiveSetup = () -> {
    if (!isResumedActive || isFinishing() || isDestroyed())
      return;
    if (!mode.equals("live") || liveSetup != null)
      return;
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
      return;
    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
      return;
    showLiveSetup();
  };

  private void showLiveSetup() {
    if (liveSetup == null)
      liveSetup = new LiveSetupSheet(this, front, fx);
    liveSetup.front(front);
    liveSetup.show();
  }

  void flipCameraForLiveSetup() {
    if (recording || busy) return;
    flip();
    if (liveSetup != null) liveSetup.front(front);
  }

  void openBeautyForLiveSetup() {
    if (recording || busy) return;
    if (liveSetup != null) {
      liveSetup.close();
      liveSetup = null;
    }
    showPanel("beauty");
  }

  void releaseForLiveHandoff() {
    isResumedActive = false;
    ui.removeCallbacksAndMessages(null);
    if (root != null)
      root.removeCallbacks(autoLiveSetup);
    Choreographer.getInstance().removeFrameCallback(this);
    closeCamera();
    stopPreview();
    if (music != null) {
      try {
        music.pause();
      } catch (Exception ignored) {
      }
    }
    setResult(RESULT_CANCELED);
  }

  private void renderModes() {
    if (musicLabel != null)
      musicLabel.setVisibility(mode.equals("live") ? View.GONE : View.VISIBLE);
    if (galleryAction != null)
      galleryAction.setVisibility(mode.equals("live") ? View.INVISIBLE : View.VISIBLE);
    if (shutter != null)
      shutter.setContentDescription(I18n.t(mode.equals("live") ? "Thiết lập Live" : "Chụp hoặc quay"));
    renderZoomBar();
    modeTabs.removeAllViews();
    String[][] modes = story ? new String[][] { { "video", "TIN 15 GIÂY" } }
        : new String[][] { { "photo", "ẢNH" }, { "video", "VIDEO" }, { "live", "LIVE" } };
    for (final String[] m : modes) {
      boolean on = m[0].equals(mode);
      boolean isLive = m[0].equals("live");
      LinearLayout cell = new LinearLayout(this);
      cell.setOrientation(LinearLayout.VERTICAL);
      cell.setGravity(Gravity.CENTER);
      cell.setPadding(dp(6), dp(2), dp(6), dp(2));
      TextView t = text(m[1], 12.5f, on ? (isLive ? 0xffffffff : 0xff111114) : (isLive ? 0xffff6b88 : 0xb3ffffff),
          true);
      if (on && !isLive)
        t.setShadowLayer(0, 0, 0, 0);
      t.setLetterSpacing(0.06f);
      t.setGravity(Gravity.CENTER);
      t.setSingleLine(true);
      t.setPadding(dp(18), dp(6), dp(18), dp(6));
      t.setBackground(round(on ? (isLive ? WebDesign.LIVE_RED : 0xffffffff) : 0x00000000, 999));
      cell.addView(t, new LinearLayout.LayoutParams(-2, dp(34)));
      cell.setOnClickListener(v -> {
        if (m[0].equals("live")) {
          if (!recording && !busy) {
            mode = "live";
            renderModes();
            buildRail();
            gridOverlay.setRatio(0);
            showLiveSetup();
          }
          return;
        }
        if (!recording && !busy) {
          mode = m[0];
          renderModes();
          buildRail();
          shutter.setMode(mode);
          gridOverlay.setRatio(mode.equals("photo") ? ratio : 0);
        }
      });
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
      lp.setMargins(dp(4), 0, dp(4), 0);
      modeTabs.addView(cell, lp);
      UiMetrics.enforceMinTouchTarget(cell, 48);
    }
    if (shutter != null)
      shutter.setMode(mode);
  }

  // ======================= Bảng hiệu ứng chuẩn Google Camera (Material 3 Dark
  // Surface + Pixel Amber) =======================
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
    if (which.equals("filter"))
      panelHost.addView(filterPanel());
    if (which.equals("beauty"))
      panelHost.addView(beautyPanel());
    if (which.equals("sticker"))
      panelHost.addView(stickerPanel());
    renderCreativeBar();
  }

  private SeekBar slider(int value, SeekBar.OnSeekBarChangeListener l) {
    SeekBar s = new SeekBar(this);
    s.setMax(100);
    s.setProgress(value);
    s.setThumbTintList(android.content.res.ColorStateList.valueOf(GCAM_AMBER));
    s.setProgressTintList(android.content.res.ColorStateList.valueOf(GCAM_AMBER));
    s.setProgressBackgroundTintList(android.content.res.ColorStateList.valueOf(0x38ffffff));
    s.setMinimumHeight(UiMetrics.dpRaw(this, 48));
    s.setOnSeekBarChangeListener(l);
    return s;
  }

  private abstract static class Slide implements SeekBar.OnSeekBarChangeListener {
    public void onStartTrackingTouch(SeekBar s) {
    }

    public void onStopTrackingTouch(SeekBar s) {
    }
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
    SeekBar filterSlider = slider(Math.round(fx.intensity * 100), new Slide() {
      public void onProgressChanged(SeekBar s, int v, boolean u) {
        fx.intensity = v / 100f;
        pct.setText(v + "%");
      }
    });
    sl.addView(filterSlider, new LinearLayout.LayoutParams(0, -2, 1));
    UiMetrics.enforceMinTouchTarget(filterSlider, 48);
    sl.addView(pct, new LinearLayout.LayoutParams(dp(38), -2));
    if (!fx.filter.equals("none"))
      box.addView(sl);
    HorizontalScrollView hs = new HorizontalScrollView(this);
    hs.setHorizontalScrollBarEnabled(false);
    LinearLayout row = new LinearLayout(this);
    int rowPad = dp(10);
    row.setPadding(rowPad, dp(6), rowPad, dp(4));
    int hsW = getResources().getDisplayMetrics().widthPixels - dp(24);
    int avail = Math.max(UiMetrics.dpRaw(this, 240), hsW - rowPad);
    int nCols = Math.max(4, avail / UiMetrics.dpRaw(this, 62));
    int cellW = Math.max(UiMetrics.dpRaw(this, 48), (avail + nCols - 1) / nCols);
    for (final String[] f : FxEngine.FILTERS) {
      boolean on = fx.filter.equals(f[0]);
      LinearLayout cell = new LinearLayout(this);
      cell.setOrientation(LinearLayout.VERTICAL);
      cell.setGravity(Gravity.CENTER_HORIZONTAL);
      cell.setPadding(dp(2), 0, dp(2), 0);
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
      if (on)
        t.setShadowLayer(0, 0, 0, 0);
      t.setSingleLine(true);
      t.setEllipsize(android.text.TextUtils.TruncateAt.END);
      t.setPadding(0, dp(5), 0, 0);
      cell.addView(t);
      cell.setOnClickListener(v -> {
        fx.filter = f[0];
        showFilterName(f[1]);
        showPanel("filter");
      });
      row.addView(cell, new LinearLayout.LayoutParams(cellW, -2));
      UiMetrics.enforceMinTouchTarget(cell, 48);
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
    for (String[] b : FxEngine.BEAUTY)
      if (b[0].equals(beautyKey))
        name = b[1];
    TextView nameTv = text(name, 12, 0xffe6e1e5, true);
    nameTv.setShadowLayer(0, 0, 0, 0);
    sl.addView(nameTv, new LinearLayout.LayoutParams(dp(72), -2));
    SeekBar beautySlider = slider(Math.round(fx.get(beautyKey) * 100), new Slide() {
      public void onProgressChanged(SeekBar s, int v, boolean u) {
        if (u)
          fx.beautyOn = true;
        fx.set(beautyKey, v / 100f);
        pct.setText(String.valueOf(v));
      }
    });
    sl.addView(beautySlider, new LinearLayout.LayoutParams(0, -2, 1));
    UiMetrics.enforceMinTouchTarget(beautySlider, 48);
    sl.addView(pct, new LinearLayout.LayoutParams(dp(32), -2));
    box.addView(sl);
    LinearLayout row = new LinearLayout(this);
    row.setGravity(Gravity.CENTER);
    row.setPadding(dp(8), dp(8), dp(8), dp(6));
    row.addView(beautyChip("beauty", fx.auto ? I18n.t("AI: bật") : "Real Tone AI", fx.auto, () -> {
      fx.auto = !fx.auto;
      if (fx.auto) {
        fx.beautyOn = true;
        fx.analyze(frame, face);
        showFilterName(face == null ? I18n.t("AI: tự cân sáng") : I18n.t("AI làm đẹp"));
      }
      showPanel("beauty");
    }), new LinearLayout.LayoutParams(0, -2, 1));
    final LinearLayout off = beautyChip("none", fx.beautyOn ? I18n.t("Tắt") : I18n.t("Đã tắt"), !fx.beautyOn, () -> {
      fx.beautyOn = !fx.beautyOn;
      showPanel("beauty");
    });
    row.addView(off, new LinearLayout.LayoutParams(0, -2, 1));
    for (final String[] item : BeautyCatalog.ITEMS) {
      final String key = item[0];
      row.addView(beautyChip(item[2], item[1], fx.beautyOn && key.equals(beautyKey), () -> {
        beautyKey = key;
        fx.beautyOn = true;
        showPanel("beauty");
      }), new LinearLayout.LayoutParams(0, -2, 1));
    }
    int chipAvail = Math.max(UiMetrics.dpRaw(this, 240),
        getResources().getDisplayMetrics().widthPixels - dp(24) - dp(8));
    int chipCols = Math.max(4, chipAvail / UiMetrics.dpRaw(this, 60));
    int chipW = Math.max(UiMetrics.dpRaw(this, 48), (chipAvail + chipCols - 1) / chipCols);
    for (int i = 0; i < row.getChildCount(); i++) {
      View ch = row.getChildAt(i);
      ch.setLayoutParams(new LinearLayout.LayoutParams(chipW, -2));
      UiMetrics.enforceMinTouchTarget(ch, 48);
    }
    HorizontalScrollView beautyScroll = new HorizontalScrollView(this);
    beautyScroll.setHorizontalScrollBarEnabled(false);
    beautyScroll.addView(row);
    box.addView(beautyScroll);
    TextView reset = text(I18n.t("Khôi phục mặc định"), 11, 0xb3ffffff, true);
    reset.setShadowLayer(0, 0, 0, 0);
    reset.setGravity(Gravity.CENTER);
    reset.setPadding(dp(14), dp(8), dp(14), dp(8));
    reset.setOnClickListener(v -> {
      fx.smooth = 0.5f;
      fx.whiten = 0.3f;
      fx.slim = 0.2f;
      fx.eyes = 0.2f;
      fx.blush = 0f;
      fx.lips = 0;
      fx.blemish = .4f;
      fx.beautyOn = true;
      showPanel("beauty");
    });
    LinearLayout.LayoutParams rlp = new LinearLayout.LayoutParams(-2, -2);
    rlp.gravity = Gravity.CENTER_HORIZONTAL;
    box.addView(reset, rlp);
    UiMetrics.enforceMinTouchTarget(reset, 48);
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
    if (on)
      t.setShadowLayer(0, 0, 0, 0);
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
      mark.setImageDrawable(
          EditorIcons.drawable(this, s[0].equals("none") ? "none" : "fx_" + s[0], on ? GCAM_AMBER : 0xffffffff));
      g.addView(mark, new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
      cell.addView(g, new LinearLayout.LayoutParams(dp(40), dp(40)));
      TextView t = text(s[1], 9.5f, on ? GCAM_AMBER : 0xd9ffffff, on);
      if (on)
        t.setShadowLayer(0, 0, 0, 0);
      t.setGravity(Gravity.CENTER);
      t.setSingleLine(true);
      t.setEllipsize(android.text.TextUtils.TruncateAt.END);
      t.setPadding(0, dp(4), 0, 0);
      cell.addView(t, new LinearLayout.LayoutParams(-1, -2));
      cell.setOnClickListener(v -> {
        fx.sticker = s[0];
        if (!s[0].equals("none") && face == null)
          faceStatus.setText(I18n.t("Đưa khuôn mặt vào khung hình"));
        showPanel("sticker");
      });
      GridLayout.LayoutParams lp = new GridLayout.LayoutParams();
      lp.width = size;
      lp.height = -2;
      lp.setMargins(0, dp(2), 0, dp(4));
      gridView.addView(cell, lp);
      UiMetrics.enforceMinTouchTarget(cell, 48);
    }
    final int maxStickerH = Math.min(UiMetrics.dpRaw(this, 256),
        getResources().getDisplayMetrics().heightPixels / 3);
    ScrollView sc = new ScrollView(this) {
      @Override
      protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(maxStickerH, MeasureSpec.AT_MOST));
      }
    };
    sc.setVerticalScrollBarEnabled(false);
    sc.addView(gridView);
    return sc;
  }

  private void stepFilter(int dir) {
    int i = 0;
    for (int k = 0; k < FxEngine.FILTERS.length; k++)
      if (FxEngine.FILTERS[k][0].equals(fx.filter))
        i = k;
    i = (i + dir + FxEngine.FILTERS.length) % FxEngine.FILTERS.length;
    fx.filter = FxEngine.FILTERS[i][0];
    showFilterName(FxEngine.FILTERS[i][1]);
    if (panel.equals("filter"))
      showPanel("filter");
  }

  private void showFilterName(String name) {
    filterToast.setText(name);
    filterToast.animate().cancel();
    filterToast.setAlpha(1f);
    filterToast.setScaleX(0.9f);
    filterToast.setScaleY(0.9f);
    filterToast.animate().scaleX(1f).scaleY(1f).setDuration(180)
        .withEndAction(() -> filterToast.animate().alpha(0).setStartDelay(650).setDuration(350)).start();
  }

  private void refreshThumb() {
    Canvas c = new Canvas(thumb);
    Rect srcRect = new Rect(FW / 6, FH / 8, FW * 5 / 6, FH * 7 / 8);
    c.drawBitmap(frame, srcRect, new Rect(0, 0, thumb.getWidth(), thumb.getHeight()),
        new Paint(Paint.FILTER_BITMAP_FLAG));
    for (ImageView v : filterThumbs)
      v.invalidate();
  }

  // ======================= Camera =======================
  @Override
  public void onRequestPermissionsResult(int code, String[] p, int[] r) {
    super.onRequestPermissionsResult(code, p, r);
    if (code == 401 && checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
      if (mode.equals("live")
          && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
        Toast.makeText(this, I18n.t("Cần quyền camera và micro để phát trực tiếp."), Toast.LENGTH_LONG).show();
        finishCancelled();
        return;
      }
      if (isResumedActive && camera != null && camera.isAvailable() && reviewedVideo == null
          && (reviewLayer == null || reviewLayer.getVisibility() != View.VISIBLE)) {
        openCamera();
      }
      if (mode.equals("live") && liveSetup == null && root != null) {
        root.removeCallbacks(autoLiveSetup);
        root.postDelayed(autoLiveSetup, 250);
      }
    } else if (code == 401 && still == null && !loadingStill) {
      Toast.makeText(this, I18n.t(
          mode.equals("live") ? "Cần quyền camera và micro để phát trực tiếp." : "Cần quyền camera để chụp và quay."),
          Toast.LENGTH_LONG).show();
      finishCancelled();
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    isResumedActive = true;
    if (mode.equals("live") && liveSetup == null) {
      root.removeCallbacks(autoLiveSetup);
      root.postDelayed(autoLiveSetup, 350);
    }
    final boolean isDebugResume = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (isDebugResume && NativeApi.isFixtureEnabled() && getIntent() != null
        && getIntent().getBooleanExtra("open_music", false)
        && (musicDialog == null || !musicDialog.isShowing())) {
      getIntent().removeExtra("open_music");
      root.postDelayed(this::chooseMusic, 600);
    }
    boolean inReview = reviewLayer != null && reviewLayer.getVisibility() == View.VISIBLE;
    Choreographer.getInstance().removeFrameCallback(this);
    if (!inReview) {
      Choreographer.getInstance().postFrameCallback(this);
    }
    if (camera.isAvailable() && reviewedVideo == null && !inReview)
      openCamera();
    if (reviewVideo != null)
      reviewVideo.start();
  }

  @Override
  protected void onPause() {
    isResumedActive = false;
    if (root != null)
      root.removeCallbacks(autoLiveSetup);
    ui.removeCallbacksAndMessages(null);
    busy = false;
    if (countdown != null)
      countdown.setVisibility(View.GONE);
    if (recording)
      stopRecording(true);
    Choreographer.getInstance().removeFrameCallback(this);
    closeCamera();
    stopPreview();
    if (music != null)
      try {
        music.pause();
      } catch (Exception ignored) {
      }
    if (reviewVideo != null)
      try {
        reviewVideo.pause();
      } catch (Exception ignored) {
      }
    super.onPause();
  }

  @Override
  protected void onDestroy() {
    isResumedActive = false;
    ui.removeCallbacksAndMessages(null);
    Choreographer.getInstance().removeFrameCallback(this);
    if (muxProgress != null) {
      try {
        if (muxProgress.isShowing())
          muxProgress.dismiss();
      } catch (Exception ignored) {
      }
      muxProgress = null;
    }
    if (musicDialog != null) {
      try {
        if (musicDialog.isShowing())
          musicDialog.dismiss();
      } catch (Exception ignored) {
      }
      musicDialog = null;
    }
    if (liveSetup != null)
      liveSetup.close();
    stopPreview();
    if (reviewVideo != null) {
      reviewVideo.stopPlayback();
      reviewVideo = null;
    }
    Thread mt = muxThread;
    muxThread = null;
    if (mt != null) {
      mt.interrupt();
    }
    worker.shutdownNow();
    if (music != null) {
      music.release();
      music = null;
    }
    closeCamera();
    if (cameraThread != null) {
      cameraThread.quitSafely();
      cameraThread = null;
      cameraHandler = null;
    }
    for (ImageView iv : filterThumbs)
      iv.setImageDrawable(null);
    filterThumbs.clear();
    if (galleryThumbView != null)
      galleryThumbView.setImageDrawable(null);
    if (reviewLayer != null)
      reviewLayer.removeAllViews();
    still = null;
    final Bitmap[] oldBitmaps = new Bitmap[] { frame, thumb, stillFull, reviewBitmap, galleryThumbBitmap };
    final FxEngine oldFx = fx;
    frame = null;
    thumb = null;
    stillFull = null;
    reviewBitmap = null;
    galleryThumbBitmap = null;
    final Runnable releaseShared = () -> {
      if (oldFx != null)
        oldFx.release();
      for (Bitmap b : oldBitmaps) {
        if (b != null && !b.isRecycled())
          b.recycle();
      }
    };
    if (worker.isTerminated()) {
      releaseShared.run();
    } else {
      Thread cleanup = new Thread(() -> {
        try {
          worker.awaitTermination(1500, TimeUnit.MILLISECONDS);
        } catch (InterruptedException ignored) {
        }
        releaseShared.run();
      }, "kinnect-studio-cleanup");
      cleanup.setDaemon(true);
      cleanup.start();
    }
    super.onDestroy();
  }

  private void flip() {
    if (recording || still != null || loadingStill)
      return;
    front = !front;
    if (liveSetup != null)
      liveSetup.front(front);
    torch = false;
    closeCamera();
    if (isResumedActive && camera != null && camera.isAvailable())
      openCamera();
    buildRail();
  }

  private void openCamera() {
    if (still != null || loadingStill || !isResumedActive || isFinishing() || isDestroyed()
        || camera == null || !camera.isAvailable())
      return;
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
      return;
    final int gen;
    final Handler handler;
    synchronized (cameraLock) {
      if (device != null || openingCamera)
        return;
      openingCamera = true;
      gen = cameraGeneration.incrementAndGet();
      if (cameraThread == null) {
        cameraThread = new HandlerThread("kinnect-camera");
        cameraThread.start();
        cameraHandler = new Handler(cameraThread.getLooper());
      }
      handler = cameraHandler;
    }
    try {
      CameraManager manager = (CameraManager) getSystemService(CAMERA_SERVICE);
      String[] cameraIds = manager != null ? manager.getCameraIdList() : new String[0];
      if (cameraIds.length == 0) {
        synchronized (cameraLock) {
          if (gen == cameraGeneration.get())
            openingCamera = false;
        }
        faceStatus.setText(I18n.t("Không tìm thấy camera."));
        return;
      }
      String chosen = null;
      for (String id : cameraIds) {
        Integer facing = manager.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING);
        if (facing != null
            && facing == (front ? CameraCharacteristics.LENS_FACING_FRONT : CameraCharacteristics.LENS_FACING_BACK)) {
          chosen = id;
          break;
        }
      }
      if (chosen == null)
        chosen = cameraIds[0];
      characteristics = manager.getCameraCharacteristics(chosen);
      // Chọn kích thước hỗ trợ sát tỉ lệ 16:9 nhất ≤ 1920 để không rơi về 1920×1080 không được hỗ trợ.
      android.hardware.camera2.params.StreamConfigurationMap map = characteristics
          .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
      android.util.Size[] sizes = map != null ? map.getOutputSizes(SurfaceTexture.class) : null;
      if (sizes != null && sizes.length > 0) {
        android.util.Size bestExact = null, bestNear = null;
        double bestDiff = Double.MAX_VALUE;
        double targetAspect = 16.0 / 9.0;
        for (android.util.Size sz : sizes) {
          if (Math.max(sz.getWidth(), sz.getHeight()) > 1920)
            continue;
          if (sz.getWidth() * 9 == sz.getHeight() * 16) {
            if (bestExact == null || sz.getWidth() > bestExact.getWidth())
              bestExact = sz;
          }
          double aspect = sz.getHeight() > 0 ? (double) sz.getWidth() / sz.getHeight() : 0;
          double diff = Math.abs(aspect - targetAspect);
          if (bestNear == null || diff < bestDiff - 0.02
              || (Math.abs(diff - bestDiff) <= 0.02
                  && (long) sz.getWidth() * sz.getHeight() > (long) bestNear.getWidth() * bestNear.getHeight())) {
            bestNear = sz;
            bestDiff = diff;
          }
        }
        android.util.Size picked = bestExact != null ? bestExact : (bestNear != null ? bestNear : sizes[0]);
        bufferW = picked.getWidth();
        bufferH = picked.getHeight();
      }
      zoom = 1f;
      manager.openCamera(chosen, new CameraDevice.StateCallback() {
        public void onOpened(CameraDevice d) {
          synchronized (cameraLock) {
            if (gen == cameraGeneration.get())
              openingCamera = false;
            if (gen != cameraGeneration.get() || !isResumedActive || isFinishing() || isDestroyed()
                || still != null || loadingStill) {
              try {
                d.close();
              } catch (Exception ignored) {
              }
              return;
            }
            if (device != null && device != d) {
              try {
                device.close();
              } catch (Exception ignored) {
              }
            }
            device = d;
          }
          startPreview(d, gen);
        }

        public void onDisconnected(CameraDevice d) {
          boolean shouldClose = false;
          synchronized (cameraLock) {
            if (gen == cameraGeneration.get())
              openingCamera = false;
            if (device == d)
              shouldClose = true;
          }
          if (shouldClose)
            closeCamera();
          else
            try {
              d.close();
            } catch (Exception ignored) {
            }
        }

        public void onError(CameraDevice d, int e) {
          boolean shouldClose = false;
          synchronized (cameraLock) {
            if (gen == cameraGeneration.get())
              openingCamera = false;
            if (device == d)
              shouldClose = true;
          }
          if (shouldClose)
            closeCamera();
          else
            try {
              d.close();
            } catch (Exception ignored) {
            }
          ui.post(() -> {
            if (!isFinishing() && !isDestroyed() && faceStatus != null)
              faceStatus.setText(I18n.t("Không mở được camera."));
          });
        }
      }, handler);
    } catch (Exception e) {
      synchronized (cameraLock) {
        if (gen == cameraGeneration.get())
          openingCamera = false;
      }
      ui.post(() -> {
        if (!isFinishing() && !isDestroyed() && faceStatus != null)
          faceStatus.setText(I18n.t("Không mở được camera."));
      });
    }
  }

  private void startPreview(final CameraDevice d, final int gen) {
    try {
      final Surface surface;
      final Handler handler;
      synchronized (cameraLock) {
        SurfaceTexture texture = camera != null ? camera.getSurfaceTexture() : null;
        if (texture == null || d == null || device != d || gen != cameraGeneration.get()
            || !isResumedActive || isFinishing() || isDestroyed())
          return;
        texture.setDefaultBufferSize(bufferW, bufferH);
        Surface oldSurface = previewSurface;
        previewSurface = null;
        if (oldSurface != null) {
          try {
            oldSurface.release();
          } catch (Exception ignored) {
          }
        }
        surface = new Surface(texture);
        previewSurface = surface;
        // TEMPLATE_PREVIEW + tắt chống rung: tránh máy tự cắt khung (bị "zoom gần") khi
        // vừa mở camera.
        CaptureRequest.Builder req = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
        req.addTarget(surface);
        req.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
        req.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
            CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF);
        req.set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
            CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_ON);
        applyZoomTo(req);
        previewRequest = req;
        handler = cameraHandler;
      }
      d.createCaptureSession(Collections.singletonList(surface), new CameraCaptureSession.StateCallback() {
        public void onConfigured(CameraCaptureSession s) {
          synchronized (cameraLock) {
            if (gen != cameraGeneration.get() || !isResumedActive || device == null || device != d
                || isFinishing() || isDestroyed()) {
              try {
                s.close();
              } catch (Exception ignored) {
              }
              return;
            }
            if (session != null && session != s) {
              try {
                session.close();
              } catch (Exception ignored) {
              }
            }
            session = s;
          }
          applyTorch();
        }

        public void onConfigureFailed(CameraCaptureSession s) {
          try {
            s.close();
          } catch (Exception ignored) {
          }
          if (gen != cameraGeneration.get())
            return;
          ui.post(() -> {
            if (gen == cameraGeneration.get() && isResumedActive && !isFinishing() && !isDestroyed() && faceStatus != null)
              faceStatus.setText(I18n.t("Không cấu hình được camera."));
          });
        }
      }, handler);
    } catch (Exception e) {
      if (gen != cameraGeneration.get())
        return;
      ui.post(() -> {
        if (gen == cameraGeneration.get() && isResumedActive && !isFinishing() && !isDestroyed() && faceStatus != null)
          faceStatus.setText(I18n.t("Không mở được camera."));
      });
    }
  }

  private volatile CameraCharacteristics characteristics;
  private int bufferW = 1920, bufferH = 1080;
  private float zoom = 1f;

  /** Zoom bằng vùng cắt cảm biến (chụm 2 ngón); 1× = toàn bộ cảm biến. */
  private void applyZoomTo(CaptureRequest.Builder b) {
    CameraCharacteristics chInfo = characteristics;
    if (chInfo == null)
      return;
    Rect active = chInfo.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
    if (active == null)
      return;
    int cw = Math.round(active.width() / zoom), ch = Math.round(active.height() / zoom);
    int left = active.left + (active.width() - cw) / 2, top = active.top + (active.height() - ch) / 2;
    b.set(CaptureRequest.SCALER_CROP_REGION, new Rect(left, top, left + cw, top + ch));
  }

  private void setZoom(float value) {
    setZoom(value, true);
  }

  private void setZoom(float value, boolean toast) {
    CameraCharacteristics chInfo = characteristics;
    Float max = chInfo == null ? null
        : chInfo.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM);
    zoom = Math.max(1f, Math.min(max == null ? 4f : Math.min(max, 8f), value));
    CaptureRequest.Builder req = previewRequest;
    CameraCaptureSession s = session;
    if (req != null && s != null) {
      applyZoomTo(req);
      try {
        s.setRepeatingRequest(req.build(), null, cameraHandler);
      } catch (Exception ignored) {
      }
    }
    renderZoomBar();
    if (toast)
      showFilterName(String.format(java.util.Locale.US, I18n.t("%.1f×"), zoom));
  }

  private void triggerTapFocus(float x, float y) {
    if (focusRing != null)
      focusRing.showAt(x, y);
    CameraCharacteristics chInfo = characteristics;
    CaptureRequest.Builder req = previewRequest;
    CameraCaptureSession s = session;
    if (still != null || chInfo == null || req == null || s == null)
      return;
    try {
      Rect active = chInfo.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
      if (active != null && stage.getWidth() > 0 && stage.getHeight() > 0) {
        float nx = Math.max(0f, Math.min(1f, x / stage.getWidth()));
        float ny = Math.max(0f, Math.min(1f, y / stage.getHeight()));
        if (front)
          nx = 1f - nx;
        Integer orientObj = chInfo.get(CameraCharacteristics.SENSOR_ORIENTATION);
        int orient = orientObj != null ? ((orientObj % 360) + 360) % 360 : 90;
        float sx, sy;
        if (orient == 90) {
          sx = ny;
          sy = 1f - nx;
        } else if (orient == 180) {
          sx = 1f - nx;
          sy = 1f - ny;
        } else if (orient == 270) {
          sx = 1f - ny;
          sy = nx;
        } else {
          sx = nx;
          sy = ny;
        }
        int cw = Math.max(1, Math.round(active.width() / zoom));
        int ch = Math.max(1, Math.round(active.height() / zoom));
        int cropLeft = active.left + (active.width() - cw) / 2;
        int cropTop = active.top + (active.height() - ch) / 2;
        int cropRight = cropLeft + cw;
        int cropBottom = cropTop + ch;
        int cx = Math.max(cropLeft, Math.min(cropRight, cropLeft + Math.round(sx * cw)));
        int cy = Math.max(cropTop, Math.min(cropBottom, cropTop + Math.round(sy * ch)));
        int half = Math.max(60, Math.min(cw, ch) / 12);
        Rect region = new Rect(Math.max(cropLeft, cx - half), Math.max(cropTop, cy - half),
            Math.min(cropRight, cx + half), Math.min(cropBottom, cy + half));
        android.hardware.camera2.params.MeteringRectangle[] rects = {
            new android.hardware.camera2.params.MeteringRectangle(region, 800) };
        Integer maxAf = chInfo.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AF);
        if (maxAf != null && maxAf > 0)
          req.set(CaptureRequest.CONTROL_AF_REGIONS, rects);
        Integer maxAe = chInfo.get(CameraCharacteristics.CONTROL_MAX_REGIONS_AE);
        if (maxAe != null && maxAe > 0)
          req.set(CaptureRequest.CONTROL_AE_REGIONS, rects);
        s.setRepeatingRequest(req.build(), null, cameraHandler);
      }
    } catch (Exception ignored) {
    }
  }

  private void applyTorch() {
    CameraCaptureSession s = session;
    CaptureRequest.Builder req = previewRequest;
    if (s == null || req == null)
      return;
    try {
      req.set(CaptureRequest.FLASH_MODE,
          torch && !front ? CaptureRequest.FLASH_MODE_TORCH : CaptureRequest.FLASH_MODE_OFF);
      s.setRepeatingRequest(req.build(), null, cameraHandler);
    } catch (Exception ignored) {
    }
  }

  private void closeCamera() {
    final CameraCaptureSession s;
    final CameraDevice d;
    final Surface ps;
    synchronized (cameraLock) {
      cameraGeneration.incrementAndGet();
      openingCamera = false;
      s = session;
      session = null;
      d = device;
      device = null;
      previewRequest = null;
      ps = previewSurface;
      previewSurface = null;
    }
    if (s != null) {
      try {
        s.close();
      } catch (Exception ignored) {
      }
    }
    if (d != null) {
      try {
        d.close();
      } catch (Exception ignored) {
      }
    }
    if (ps != null) {
      try {
        ps.release();
      } catch (Exception ignored) {
      }
    }
  }

  /** Ảnh có sẵn làm nguồn (chỉnh ảnh, hoặc tin ảnh kèm nhạc). */
  private void loadStill(final Uri uri, final String startMode) {
    loadingStill = true;
    closeCamera();
    try {
      worker.execute(() -> {
        Bitmap src = null;
        Bitmap full = null;
        try {
          BitmapFactory.Options o = new BitmapFactory.Options();
          o.inJustDecodeBounds = true;
          try (InputStream in = getContentResolver().openInputStream(uri)) {
            if (in == null)
              throw new java.io.IOException("Null input stream");
            BitmapFactory.decodeStream(in, null, o);
          }
          if (o.outWidth <= 0 || o.outHeight <= 0)
            throw new java.io.IOException("Invalid image bounds");
          int sampleSize = 1;
          int maxSide = Math.max(o.outWidth, o.outHeight);
          int targetMax = Math.max(PW, PH);
          while ((maxSide / sampleSize) > targetMax * 2
              || ((long) (o.outWidth / sampleSize) * (o.outHeight / sampleSize)) > 8_500_000L) {
            sampleSize *= 2;
          }
          o.inSampleSize = sampleSize;
          o.inJustDecodeBounds = false;
          try (InputStream in = getContentResolver().openInputStream(uri)) {
            if (in == null)
              throw new java.io.IOException("Null input stream");
            src = BitmapFactory.decodeStream(in, null, o);
          }
          if (src == null)
            throw new java.io.IOException("Decode failed");
          Matrix exifMatrix = new Matrix();
          try (InputStream exifIn = getContentResolver().openInputStream(uri)) {
            if (exifIn != null) {
              int orientation = new ExifInterface(exifIn).getAttributeInt(ExifInterface.TAG_ORIENTATION,
                  ExifInterface.ORIENTATION_NORMAL);
              switch (orientation) {
                case ExifInterface.ORIENTATION_FLIP_HORIZONTAL:
                  exifMatrix.postScale(-1, 1);
                  break;
                case ExifInterface.ORIENTATION_ROTATE_180:
                  exifMatrix.postRotate(180);
                  break;
                case ExifInterface.ORIENTATION_FLIP_VERTICAL:
                  exifMatrix.postScale(1, -1);
                  break;
                case ExifInterface.ORIENTATION_TRANSPOSE:
                  exifMatrix.postRotate(90);
                  exifMatrix.postScale(-1, 1);
                  break;
                case ExifInterface.ORIENTATION_ROTATE_90:
                  exifMatrix.postRotate(90);
                  break;
                case ExifInterface.ORIENTATION_TRANSVERSE:
                  exifMatrix.postRotate(270);
                  exifMatrix.postScale(-1, 1);
                  break;
                case ExifInterface.ORIENTATION_ROTATE_270:
                  exifMatrix.postRotate(270);
                  break;
                default:
                  break;
              }
            }
          } catch (Exception ignored) {
          }
          if (!exifMatrix.isIdentity()) {
            Bitmap rotated = Bitmap.createBitmap(src, 0, 0, src.getWidth(), src.getHeight(), exifMatrix, true);
            if (rotated != src) {
              src.recycle();
              src = rotated;
            }
          }
          full = Bitmap.createBitmap(PW, PH, Bitmap.Config.ARGB_8888);
          Canvas c = new Canvas(full);
          c.drawColor(0xff000000);
          float scale = Math.max(PW / (float) src.getWidth(), PH / (float) src.getHeight());
          float w = src.getWidth() * scale, h = src.getHeight() * scale;
          c.drawBitmap(src, null, new RectF((PW - w) / 2, (PH - h) / 2, (PW + w) / 2, (PH + h) / 2),
              new Paint(Paint.FILTER_BITMAP_FLAG));
          src.recycle();
          src = null;
          final Bitmap loadedFull = full;
          full = null;
          ui.post(() -> {
            loadingStill = false;
            if (isFinishing() || isDestroyed() || frame == null || frame.isRecycled()) {
              if (!loadedFull.isRecycled())
                loadedFull.recycle();
              return;
            }
            if (stillFull != null && !stillFull.isRecycled())
              stillFull.recycle();
            stillFull = loadedFull;
            new Canvas(frame).drawBitmap(stillFull, null, new Rect(0, 0, FW, FH), new Paint(Paint.FILTER_BITMAP_FLAG));
            still = frame;
            front = false;
            closeCamera();
            mode = startMode;
            renderModes();
            buildRail();
            face = null;
          });
        } catch (Exception | OutOfMemoryError e) {
          if (src != null && !src.isRecycled())
            src.recycle();
          if (full != null && !full.isRecycled())
            full.recycle();
          ui.post(() -> {
            loadingStill = false;
            if (!isFinishing() && !isDestroyed()) {
              Toast.makeText(this, I18n.t("Không mở được ảnh."), Toast.LENGTH_LONG).show();
              if (still == null && camera != null && camera.isAvailable() && isResumedActive)
                openCamera();
            }
          });
        }
      });
    } catch (RejectedExecutionException ignored) {
      loadingStill = false;
    }
  }

  private void openGallery() {
    if (recording)
      return;
    boolean video = mode.equals("video");
    Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
        .setType(video ? "video/*" : "image/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    try {
      startActivityForResult(pick, video ? 404 : 403);
    } catch (Exception e) {
      Toast.makeText(this, I18n.t("Không mở được thư viện."), Toast.LENGTH_SHORT).show();
    }
  }

  private void openPhotoPro(Uri uri) {
    if (uri == null) return;
    Intent intent = new Intent(this, PhotoEditActivity.class);
    if ("file".equals(uri.getScheme())) {
      if (uri.getPath() == null) return;
      intent.putExtra(EXTRA_IMAGE, uri.getPath());
    } else {
      intent.setData(uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
      intent.setClipData(android.content.ClipData.newRawUri("photo", uri));
    }
    startActivityForResult(intent, 406);
  }

  // ======================= Vẽ từng khung hình =======================
  private boolean hardwarePreview = true;

  @Override
  public void doFrame(long nanos) {
    if (isFinishing() || isDestroyed() || frame == null || frame.isRecycled())
      return;
    if (reviewLayer != null && reviewLayer.getVisibility() == View.VISIBLE)
      return;
    Choreographer.getInstance().postFrameCallback(this);
    if (still == null) {
      if (!camera.isAvailable() || device == null)
        return;
      camera.getBitmap(frame);
    }
    frameCount++;
    boolean needFace = fx.needsFace();
    if (needFace && frameCount % 4 == 0 && !detecting)
      detectFace();
    if (panel.equals("filter") && frameCount % 45 == 0)
      refreshThumb();
    if (fx.auto && frameCount % 30 == 0)
      fx.analyze(frame, face);
    if (previewReady) {
      Canvas c = null;
      try {
        if (hardwarePreview) {
          try {
            c = preview.getHolder().getSurface().lockHardwareCanvas();
          } catch (Exception e) {
            hardwarePreview = false;
            c = null;
          }
        }
        if (c == null && !hardwarePreview)
          c = preview.getHolder().lockCanvas();
        if (c != null)
          fx.render(c, frame, face, frameCount);
      } catch (Exception ignored) {
      } finally {
        if (c != null)
          try {
            if (hardwarePreview)
              preview.getHolder().getSurface().unlockCanvasAndPost(c);
            else
              preview.getHolder().unlockCanvasAndPost(c);
          } catch (Exception ignored) {
          }
      }
    }
    if (recording && recorderSurface != null) {
      Canvas c = null;
      try {
        if (hardwareRecorder) {
          try {
            c = recorderSurface.lockHardwareCanvas();
          } catch (Exception e) {
            hardwareRecorder = false;
            c = null;
          }
        }
        if (c == null && !hardwareRecorder)
          c = recorderSurface.lockCanvas(null);
        if (c != null)
          fx.render(c, frame, face, frameCount);
      } catch (Exception ignored) {
      } finally {
        if (c != null)
          try {
            recorderSurface.unlockCanvasAndPost(c);
          } catch (Exception ignored) {
          }
      }
      float elapsed = (SystemClock.elapsedRealtime() - startedAt) / 1000f;
      shutter.setProgress(limitSeconds > 0 ? elapsed / limitSeconds : (elapsed % 60) / 60f);
      int sec = (int) elapsed;
      String cur = String.format(Locale.US, "%02d:%02d", sec / 60, sec % 60);
      String lim = limitSeconds > 0 ? String.format(Locale.US, " / %02d:%02d", limitSeconds / 60, limitSeconds % 60)
          : "";
      timer.setText("●  " + cur + lim);
      if (limitSeconds > 0 && elapsed >= limitSeconds)
        stopRecording();
    }
  }

  private void detectFace() {
    if (frame == null || frame.isRecycled() || worker.isShutdown())
      return;
    detecting = true;
    Bitmap scaled = null;
    final Bitmap small;
    try {
      scaled = Bitmap.createScaledBitmap(frame, FW / 2, FH / 2, true);
      small = scaled.copy(Bitmap.Config.RGB_565, false);
    } catch (Throwable t) {
      if (scaled != null && scaled != frame)
        scaled.recycle();
      detecting = false;
      return;
    }
    if (scaled != null && scaled != frame && scaled != small)
      scaled.recycle();
    if (small == null) {
      detecting = false;
      return;
    }
    try {
      worker.execute(() -> {
        try {
          FaceDetector.Face[] found = new FaceDetector.Face[1];
          int n = new FaceDetector(small.getWidth(), small.getHeight(), 1).findFaces(small, found);
          float[] next = null;
          if (n > 0 && found[0] != null && found[0].confidence() >= 0.3f) {
            PointF mid = new PointF();
            found[0].getMidPoint(mid);
            next = new float[] { mid.x * 2, mid.y * 2, found[0].eyesDistance() * 2,
                found[0].pose(FaceDetector.Face.EULER_Z) };
          }
          final float[] result = next;
          ui.post(() -> {
            if (isFinishing() || isDestroyed())
              return;
            if (result == null) {
              if (++missed >= 5) {
                face = null;
                if (!fx.sticker.equals("none") && faceStatus != null)
                  faceStatus.setText(I18n.t("Đưa khuôn mặt vào khung hình"));
              }
              return;
            }
            missed = 0;
            float[] old = face;
            if (old != null)
              for (int i = 0; i < 4; i++)
                result[i] = old[i] * 0.45f + result[i] * 0.55f;
            face = result;
            if (faceStatus != null)
              faceStatus.setText("");
          });
        } catch (Exception ignored) {
        } finally {
          small.recycle();
          detecting = false;
        }
      });
    } catch (RejectedExecutionException ignored) {
      small.recycle();
      detecting = false;
    }
  }

  // ======================= Chụp / quay =======================
  private void onShutter() {
    if (mode.equals("live")) {
      showLiveSetup();
      return;
    }
    if (busy)
      return;
    if (recording) {
      stopRecording();
      return;
    }
    if (timerSeconds > 0)
      countdownThen(timerSeconds, this::shoot);
    else
      shoot();
  }

  private void shoot() {
    if (mode.equals("photo"))
      capturePhoto();
    else
      startRecording();
  }

  private void countdownThen(final int seconds, final Runnable then) {
    busy = true;
    countdown.setVisibility(View.VISIBLE);
    final int[] left = { seconds };
    Runnable tick = new Runnable() {
      public void run() {
        if (!isResumedActive || isFinishing() || isDestroyed()) {
          countdown.setVisibility(View.GONE);
          busy = false;
          return;
        }
        if (left[0] == 0) {
          countdown.setVisibility(View.GONE);
          busy = false;
          then.run();
          return;
        }
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

  private void openFixturePhotoReview() {
    boolean isDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (!isDebug || !NativeApi.isFixtureEnabled() || isFinishing() || isDestroyed())
      return;
    if (reviewLayer != null && reviewLayer.getVisibility() == View.VISIBLE)
      return;
    Bitmap src = (camera != null && camera.isAvailable()) ? camera.getBitmap(PW, PH) : null;
    if (src == null) {
      src = Bitmap.createBitmap(PW, PH, Bitmap.Config.ARGB_8888);
      Canvas bg = new Canvas(src);
      Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
      p.setShader(new LinearGradient(0, 0, PW, PH, new int[] { 0xff2b1e4a, 0xff5b3fd6, 0xffd946c4 }, null,
          Shader.TileMode.CLAMP));
      bg.drawRect(0, 0, PW, PH, p);
    }
    Bitmap out = Bitmap.createBitmap(PW, PH, Bitmap.Config.ARGB_8888);
    FxEngine fxCopy = fx.copy();
    try {
      fxCopy.render(new Canvas(out), src, null, frameCount);
      Bitmap cropped = crop(out);
      if (cropped != out && !out.isRecycled())
        out.recycle();
      File file = new File(getCacheDir(), "kinnect-photo-fixture-" + System.currentTimeMillis() + ".jpg");
      try (FileOutputStream os = new FileOutputStream(file)) {
        cropped.compress(Bitmap.CompressFormat.JPEG, 90, os);
      }
      if (capturedPhoto != null && !capturedPhoto.equals(file) && !savingPhoto)
        deleteIfCacheFile(capturedPhoto);
      capturedPhoto = file;
      showReview(cropped);
    } catch (Exception ignored) {
      if (!out.isRecycled())
        out.recycle();
    } finally {
      fxCopy.release();
      if (!src.isRecycled())
        src.recycle();
    }
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
    if (still != null)
      src = stillFull;
    else
      src = camera.getBitmap(PW, PH);
    if (src == null) {
      busy = false;
      return;
    }
    final float scale = src.getWidth() / (float) FW;
    try {
      worker.execute(() -> {
        Bitmap out = null;
        FxEngine fxCopy = fx.copy();
        try {
          out = Bitmap.createBitmap(PW, PH, Bitmap.Config.ARGB_8888);
          float[] sf = f == null ? null : new float[] { f[0] * scale, f[1] * scale, f[2] * scale, f[3] };
          fxCopy.render(new Canvas(out), src, sf, frameCount);
          Bitmap cropped = crop(out);
          if (cropped != out && !out.isRecycled())
            out.recycle();
          File file = new File(getCacheDir(), "kinnect-photo-" + System.currentTimeMillis() + ".jpg");
          try (FileOutputStream os = new FileOutputStream(file)) {
            cropped.compress(Bitmap.CompressFormat.JPEG, 90, os);
          }
          final Bitmap shown = cropped;
          ui.post(() -> {
            busy = false;
            if (isFinishing() || isDestroyed()) {
              if (shown != null && !shown.isRecycled())
                shown.recycle();
              file.delete();
              return;
            }
            if (capturedPhoto != null && !capturedPhoto.equals(file) && !savingPhoto)
              deleteIfCacheFile(capturedPhoto);
            capturedPhoto = file;
            showReview(shown);
          });
        } catch (Exception | OutOfMemoryError e) {
          if (out != null && !out.isRecycled())
            out.recycle();
          ui.post(() -> {
            busy = false;
            if (!isFinishing() && !isDestroyed())
              Toast.makeText(this, I18n.t("Không chụp được ảnh."), Toast.LENGTH_SHORT).show();
          });
        } finally {
          fxCopy.release();
          if (src != stillFull && src != frame && !src.isRecycled())
            src.recycle();
        }
      });
    } catch (RejectedExecutionException ignored) {
      busy = false;
      if (src != stillFull && src != frame && !src.isRecycled())
        src.recycle();
    }
  }

  private Bitmap crop(Bitmap b) {
    if (ratio == 0)
      return b;
    int w = b.getWidth(), h = ratio == 1 ? w * 4 / 3 : w;
    return Bitmap.createBitmap(b, 0, (b.getHeight() - h) / 2, w, h);
  }

  // Màn xem lại sau khi chụp chuẩn Google Camera / Pixel Photos: lưu vào máy ·
  // đăng bài · đăng tin · chụp lại
  private void showReview(Bitmap photo) {
    Choreographer.getInstance().removeFrameCallback(this);
    closeCamera();
    if (preview != null)
      preview.setVisibility(View.GONE);
    if (studioTopBar != null)
      studioTopBar.setVisibility(View.INVISIBLE);
    if (bottomBar != null)
      bottomBar.setVisibility(View.INVISIBLE);
    if (galleryThumbView != null && photo != null && !photo.isRecycled()) {
      try {
        Bitmap nextThumb = Bitmap.createScaledBitmap(photo, 128, 128, true);
        Bitmap oldThumb = galleryThumbBitmap;
        galleryThumbBitmap = nextThumb;
        galleryThumbView.setImageBitmap(nextThumb);
        galleryThumbView.setVisibility(View.VISIBLE);
        if (oldThumb != null && oldThumb != nextThumb && !oldThumb.isRecycled())
          oldThumb.recycle();
      } catch (Throwable ignored) {
      }
    }
    Bitmap oldReview = reviewBitmap;
    reviewBitmap = photo;
    reviewLayer.removeAllViews();
    if (oldReview != null && oldReview != photo && !oldReview.isRecycled())
      oldReview.recycle();
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
    pro.setMinHeight(UiMetrics.dpRaw(this, 48));
    pro.setGravity(Gravity.CENTER);
    pro.setBackground(proBg);
    android.graphics.drawable.Drawable spk = tinted("sparkles");
    spk.setTint(GCAM_AMBER);
    pro.setCompoundDrawablesRelativeWithIntrinsicBounds(spk, null, null, null);
    pro.setCompoundDrawablePadding(dp(6));
    pro.setOnClickListener(v -> {
      if (capturedPhoto != null)
        openPhotoPro(Uri.fromFile(capturedPhoto));
    });

    LinearLayout top = new LinearLayout(this);
    top.setGravity(Gravity.TOP);
    top.setPadding(dp(12), dp(14), dp(14), dp(16));
    top.setBackground(
        new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x99000000, 0x00000000 }));
    ImageView back = icon("back", 0xffffffff);
    back.setPadding(dp(10), dp(10), dp(10), dp(10));
    GradientDrawable backBg = round(GCAM_PILL, 999);
    backBg.setStroke(dp(1), 0x26ffffff);
    back.setBackground(backBg);
    back.setContentDescription(I18n.t("Chụp lại"));
    back.setOnClickListener(v -> dismissPhotoReview());
    back.setLayoutParams(new LinearLayout.LayoutParams(dp(42), dp(42)));
    top.addView(UiMetrics.wrapMinTouchTarget(this, back, 48));
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));

    final TextView save = text(I18n.t("  Lưu vào máy"), 13.5f, 0xffffffff, true);
    save.setGravity(Gravity.CENTER);
    save.setMinHeight(UiMetrics.dpRaw(this, 48));
    save.setPadding(dp(14), dp(8), dp(16), dp(8));
    GradientDrawable saveBg = round(GCAM_PILL, 999);
    saveBg.setStroke(dp(1), 0x28ffffff);
    save.setBackground(saveBg);
    save.setCompoundDrawablesRelativeWithIntrinsicBounds(tinted("download"), null, null, null);
    final boolean[] savedToGallery = { false };
    save.setOnClickListener(v -> {
      if (savedToGallery[0] || savingPhoto || capturedPhoto == null)
        return;
      final File targetFile = capturedPhoto;
      savingPhoto = true;
      save.setEnabled(false);
      save.setTextColor(0xffe2dfec);
      saveToGallery(targetFile, ok -> {
        savingPhoto = false;
        if (isFinishing() || isDestroyed())
          return;
        save.setAlpha(1f);
        if (ok) {
          savedToGallery[0] = true;
          save.setText(I18n.t("  Đã lưu"));
          save.setTextColor(GCAM_AMBER);
          android.graphics.drawable.Drawable chk = tinted("check");
          chk.setTint(GCAM_AMBER);
          save.setCompoundDrawablesRelativeWithIntrinsicBounds(chk, null, null, null);
        } else {
          save.setTextColor(0xffffffff);
          save.setEnabled(true);
        }
      });
    });
    LinearLayout reviewActions = new LinearLayout(this);
    reviewActions.setOrientation(LinearLayout.VERTICAL);
    reviewActions.setGravity(Gravity.END);
    reviewActions.addView(save, new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48)));
    UiMetrics.enforceMinTouchTarget(save, 48);
    LinearLayout.LayoutParams proAt = new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48));
    proAt.topMargin = Math.max(22, UiMetrics.dpRaw(this, 12));
    reviewActions.addView(pro, proAt);
    UiMetrics.enforceMinTouchTarget(pro, 48);
    top.addView(reviewActions, new LinearLayout.LayoutParams(-2, -2));
    reviewLayer.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));

    LinearLayout bar = new LinearLayout(this);
    bar.setGravity(Gravity.CENTER);
    bar.setPadding(dp(16), dp(16), dp(16), dp(22));
    bar.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP,
        new int[] { 0xe6000000, 0x99000000, 0x00000000 }));
    int raw50 = UiMetrics.dpRaw(this, 50);
    TextView again = text(I18n.t("Chụp lại"), 14.5f, 0xffffffff, true);
    again.setGravity(Gravity.CENTER);
    GradientDrawable againBg = round(GCAM_BTN, 999);
    againBg.setStroke(dp(1), 0x28ffffff);
    again.setBackground(againBg);
    again.setOnClickListener(v -> dismissPhotoReview());
    bar.addView(again, new LinearLayout.LayoutParams(0, raw50, 1));
    UiMetrics.enforceMinTouchTarget(again, 48);
    TextView storyBtn = text(I18n.t("Đăng tin"), 14.5f, 0xffffffff, true);
    storyBtn.setGravity(Gravity.CENTER);
    GradientDrawable storyBg = round(GCAM_BTN, 999);
    storyBg.setStroke(dp(1), 0x28ffffff);
    storyBtn.setBackground(storyBg);
    storyBtn.setOnClickListener(v -> deliverPhoto("story"));
    LinearLayout.LayoutParams mid = new LinearLayout.LayoutParams(0, raw50, 1);
    mid.setMargins(dp(10), 0, dp(10), 0);
    bar.addView(storyBtn, mid);
    UiMetrics.enforceMinTouchTarget(storyBtn, 48);
    TextView post = text(I18n.t("Đăng bài"), 14.5f, 0xff111114, true);
    post.setShadowLayer(0, 0, 0, 0);
    post.setGravity(Gravity.CENTER);
    post.setBackground(round(0xffffffff, 999));
    post.setOnClickListener(v -> deliverPhoto("post"));
    bar.addView(post, new LinearLayout.LayoutParams(0, raw50, 1));
    UiMetrics.enforceMinTouchTarget(post, 48);
    reviewLayer.addView(bar, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
  }

  private void dismissPhotoReview() {
    File oldPhoto = capturedPhoto;
    capturedPhoto = null;
    photoProEdited = false;
    if (oldPhoto != null && !savingPhoto && oldPhoto.getParentFile() != null
        && oldPhoto.getParentFile().equals(getCacheDir())) {
      oldPhoto.delete();
    }
    reviewLayer.removeAllViews();
    reviewLayer.setVisibility(View.GONE);
    Bitmap oldReview = reviewBitmap;
    reviewBitmap = null;
    if (oldReview != null && !oldReview.isRecycled())
      oldReview.recycle();
    if (preview != null)
      preview.setVisibility(View.VISIBLE);
    if (studioTopBar != null)
      studioTopBar.setVisibility(View.VISIBLE);
    if (bottomBar != null)
      bottomBar.setVisibility(View.VISIBLE);
    if (isResumedActive && !isFinishing() && !isDestroyed()) {
      Choreographer.getInstance().removeFrameCallback(this);
      Choreographer.getInstance().postFrameCallback(this);
    }
    if (still == null && camera != null && camera.isAvailable())
      openCamera();
  }

  private android.graphics.drawable.Drawable tinted(String name) {
    int id = WebIcons.resolve(this, name);
    android.graphics.drawable.Drawable d = WebIcons.load(this, name);
    d.setTint(0xffffffff);
    d.setBounds(0, 0, dp(18), dp(18));
    return d;
  }

  private void saveToGallery(final File file, final java.util.function.Consumer<Boolean> done) {
    if (file == null || !file.exists()) {
      done.accept(false);
      return;
    }
    try {
      worker.execute(() -> {
        boolean ok = false;
        Uri uri = null;
        try {
          ContentValues v = new ContentValues();
          v.put(MediaStore.Images.Media.DISPLAY_NAME,
              "Kinnect_" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date()) + ".jpg");
          v.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
          if (Build.VERSION.SDK_INT >= 29) {
            v.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Kinnect");
            v.put(MediaStore.Images.Media.IS_PENDING, 1);
          }
          uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
          if (uri == null)
            throw new java.io.IOException("MediaStore insert returned null");
          try (OutputStream os = getContentResolver().openOutputStream(uri); InputStream in = new FileInputStream(file)) {
            if (os == null)
              throw new java.io.IOException("OutputStream null");
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0)
              os.write(buf, 0, n);
          }
          if (Build.VERSION.SDK_INT >= 29) {
            ContentValues ready = new ContentValues();
            ready.put(MediaStore.Images.Media.IS_PENDING, 0);
            getContentResolver().update(uri, ready, null, null);
          }
          ok = true;
        } catch (Exception ignored) {
          ok = false;
          if (uri != null) {
            try {
              getContentResolver().delete(uri, null, null);
            } catch (Exception ignoredDelete) {
            }
          }
        }
        final boolean saved = ok;
        ui.post(() -> {
          done.accept(saved);
          if (!isFinishing() && !isDestroyed()) {
            Toast.makeText(this, I18n.t(saved ? "Đã lưu vào Ảnh › Kinnect" : "Không lưu được ảnh vào máy."),
                Toast.LENGTH_SHORT).show();
          }
        });
      });
    } catch (RejectedExecutionException ignored) {
      done.accept(false);
    }
  }

  private void deliverPhoto(String action) {
    Intent result = new Intent();
    result.putExtra(EXTRA_IMAGE, capturedPhoto.getAbsolutePath());
    result.putExtra("photoProEdited", photoProEdited);
    result.putExtra(EXTRA_ACTION, action);
    setResult(RESULT_OK, result);
    finish();
  }

  private void startRecording() {
    if (device == null && still == null)
      return;
    boolean withMusic = musicUrl != null || musicLocal != null;
    boolean mic = !withMusic
        && checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    try {
      if (output != null) {
        deleteIfCacheFile(output);
        output = null;
      }
      output = new File(getCacheDir(), "kinnect-" + System.currentTimeMillis() + ".mp4");
      recorder = new MediaRecorder();
      if (mic)
        recorder.setAudioSource(MediaRecorder.AudioSource.CAMCORDER);
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
      recorder.setVideoEncodingBitRate(limitSeconds > 0 && limitSeconds <= 30 ? 2400000 : 1300000);
      recorder.setMaxDuration(180_000);
      recorder.setMaxFileSize(40L * 1024L * 1024L);
      recorder.setOnInfoListener((mr, what, extra) -> {
        if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED
            || what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) {
          ui.post(() -> {
            if (recording && !isFinishing() && !isDestroyed())
              stopRecording();
          });
        }
      });
      recorder.setOutputFile(output.getAbsolutePath());

      recorder.prepare();
      recorderSurface = recorder.getSurface();
      hardwareRecorder = true;
      recorder.start();
      recording = true;
      startedAt = SystemClock.elapsedRealtime();
      shutter.setRecording(true);
      timer.setVisibility(View.VISIBLE);
      rail.setVisibility(View.INVISIBLE);
      modeTabs.setVisibility(View.INVISIBLE);
      if (creativeBar != null)
        creativeBar.setVisibility(View.INVISIBLE);
      if (flipButton != null)
        flipButton.setVisibility(View.INVISIBLE);
      if (galleryAction != null)
        galleryAction.setVisibility(View.INVISIBLE);
      if (musicLabel != null)
        musicLabel.setVisibility(View.INVISIBLE);
      showPanel("");
      if (music != null) {
        music.seekTo(0);
        music.start();
      }
    } catch (Exception e) {
      releaseRecorder();
      Toast.makeText(this, I18n.t("Không bắt đầu quay được trên máy này."), Toast.LENGTH_LONG).show();
    }
  }

  private void stopRecording() {
    stopRecording(false);
  }

  private void stopRecording(final boolean fromPause) {
    if (!recording)
      return;
    recording = false;
    long length = SystemClock.elapsedRealtime() - startedAt;
    boolean ok = true;
    try {
      recorder.stop();
    } catch (Exception e) {
      ok = false;
    }
    releaseRecorder();
    if (music != null)
      try {
        music.pause();
      } catch (Exception ignored) {
      }
    if (!ok || length < 1000) {
      if (output != null) {
        output.delete();
        output = null;
      }
      if (!fromPause && isResumedActive)
        Toast.makeText(this, I18n.t("Video quá ngắn, hãy quay lâu hơn."), Toast.LENGTH_SHORT).show();
      return;
    }
    if (musicUrl == null && musicLocal == null) {
      done(output);
      return;
    }
    if (!fromPause && isResumedActive && !isFinishing() && !isDestroyed()) {
      muxProgress = ProgressDialog.show(this, "Kinnect", I18n.t("Đang ghép nhạc nền…"), true, false);
    }
    final File video = output;
    Thread prevMux = muxThread;
    if (prevMux != null) prevMux.interrupt();
    final Thread currentMux = new Thread(() -> {
      File mixed = new File(getCacheDir(), "kinnect-mix-" + System.currentTimeMillis() + ".mp4");
      String error = null;
      try {
        MusicMuxer.mux(this, video, musicUrl, musicLocal, api.jar(), mixed);
      } catch (Exception e) {
        error = I18n.t("Không ghép được nhạc. Video sẽ không có nhạc nền.");
        if (mixed.exists())
          mixed.delete();
      } finally {
        if (muxThread == Thread.currentThread())
          muxThread = null;
      }
      final String message = error;
      ui.post(() -> {
        if (muxProgress != null) {
          try {
            if (muxProgress.isShowing())
              muxProgress.dismiss();
          } catch (Exception ignored) {
          }
          muxProgress = null;
        }
        if (isFinishing() || isDestroyed()) {
          if (mixed.exists())
            mixed.delete();
          return;
        }
        if (message != null) {
          if (isResumedActive)
            Toast.makeText(this, message, Toast.LENGTH_LONG).show();
          done(video);
        } else {
          if (video != null && !video.equals(mixed) && video.exists())
            video.delete();
          output = mixed;
          done(mixed);
        }
      });
    }, "kinnect-mux");
    muxThread = currentMux;
    currentMux.start();
  }

  private void releaseRecorder() {
    if (recorder != null) {
      recorder.release();
      recorder = null;
    }
    if (recorderSurface != null) {
      try {
        recorderSurface.release();
      } catch (Exception ignored) {
      }
      recorderSurface = null;
    }
    shutter.setRecording(false);
    shutter.setProgress(0);
    timer.setVisibility(View.GONE);
    rail.setVisibility(View.VISIBLE);
    modeTabs.setVisibility(View.VISIBLE);
    if (creativeBar != null)
      creativeBar.setVisibility(View.VISIBLE);
    if (flipButton != null)
      flipButton.setVisibility(View.VISIBLE);
    if (galleryAction != null)
      galleryAction.setVisibility(mode.equals("live") ? View.INVISIBLE : View.VISIBLE);
    if (musicLabel != null)
      musicLabel.setVisibility(mode.equals("live") ? View.GONE : View.VISIBLE);
  }

  private Uri reviewedVideo;
  private VideoView reviewVideo;
  private boolean videoProEdited;

  private void done(File file) {
    videoProEdited = false;
    showVideoReview(Uri.fromFile(file));
  }

  private void openVideoPro(Uri uri) {
    if (uri == null) return;
    if (reviewVideo != null)
      reviewVideo.pause();
    Intent editor = new Intent(this, MediaEditActivity.class);
    if ("file".equals(uri.getScheme())) {
      if (uri.getPath() == null) return;
      editor.putExtra(EXTRA_VIDEO, uri.getPath());
    } else {
      editor.setData(uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
      editor.setClipData(android.content.ClipData.newRawUri("video", uri));
    }
    startActivityForResult(editor, 408);
  }

  private void showVideoReview(Uri uri) {
    Choreographer.getInstance().removeFrameCallback(this);
    closeCamera();
    if (preview != null)
      preview.setVisibility(View.GONE);
    if (studioTopBar != null)
      studioTopBar.setVisibility(View.INVISIBLE);
    if (bottomBar != null)
      bottomBar.setVisibility(View.INVISIBLE);
    reviewedVideo = uri;
    if (reviewVideo != null)
      reviewVideo.stopPlayback();
    reviewLayer.removeAllViews();
    reviewLayer.setVisibility(View.VISIBLE);
    reviewLayer.setBackgroundColor(0xff000000);
    reviewVideo = new VideoView(this);
    reviewVideo.setVideoURI(uri);
    reviewVideo.setOnPreparedListener(player -> {
      player.setLooping(true);
      if (isResumedActive && reviewVideo != null)
        reviewVideo.start();
    });
    reviewVideo.setOnErrorListener((mp, what, extra) -> {
      if (!isFinishing() && !isDestroyed())
        Toast.makeText(this, I18n.t("Không phát được video này."), Toast.LENGTH_SHORT).show();
      return true;
    });
    reviewLayer.addView(reviewVideo, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
    final TextView playBadge = text("❚❚", 18, 0xffffffff, true);
    playBadge.setGravity(Gravity.CENTER);
    playBadge.setBackground(round(GCAM_PILL, 999));
    playBadge.setAlpha(0f);
    reviewLayer.addView(playBadge, new FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER));
    reviewVideo.setOnTouchListener((v, e) -> {
      if (e.getActionMasked() == MotionEvent.ACTION_UP) {
        if (reviewVideo.isPlaying()) {
          reviewVideo.pause();
          playBadge.setText("▶");
          playBadge.animate().alpha(1f).setDuration(150).start();
        } else {
          reviewVideo.start();
          playBadge.setText("❚❚");
          playBadge.animate().alpha(0f).setDuration(250).start();
        }
      }
      return true;
    });
    GradientDrawable proBg = round(GCAM_PILL, 999);
    proBg.setStroke(dp(1), 0x44fdd663);
    TextView pro = text(I18n.t("Studio Pro"), 13, GCAM_AMBER, true);
    pro.setPadding(dp(14), 0, dp(14), 0);
    pro.setGravity(Gravity.CENTER);
    pro.setBackground(proBg);
    android.graphics.drawable.Drawable spk = tinted("sparkles");
    spk.setTint(GCAM_AMBER);
    pro.setCompoundDrawablesRelativeWithIntrinsicBounds(spk, null, null, null);
    pro.setCompoundDrawablePadding(dp(6));
    pro.setOnClickListener(v -> openVideoPro(reviewedVideo));
    FrameLayout.LayoutParams pp = new FrameLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48), Gravity.TOP | Gravity.END);
    pp.setMargins(0, UiMetrics.dpRaw(this, 56), dp(14), 0);
    reviewLayer.addView(pro, pp);
    UiMetrics.enforceMinTouchTarget(pro, 48);
    ImageView back = icon("back", 0xffffffff);
    back.setPadding(dp(10), dp(10), dp(10), dp(10));
    GradientDrawable backBg = round(GCAM_PILL, 999);
    backBg.setStroke(dp(1), 0x28ffffff);
    back.setBackground(backBg);
    back.setContentDescription(I18n.t("Quay lại"));
    back.setOnClickListener(v -> dismissVideoReview());
    FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP | Gravity.START);
    bp.setMargins(dp(12), dp(12), 0, 0);
    back.setLayoutParams(bp);
    reviewLayer.addView(UiMetrics.wrapMinTouchTarget(this, back, 48));
    LinearLayout bar = new LinearLayout(this);
    bar.setPadding(dp(16), dp(16), dp(16), dp(22));
    bar.setGravity(Gravity.CENTER);
    bar.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP,
        new int[] { 0xe6000000, 0x99000000, 0x00000000 }));
    int raw50 = UiMetrics.dpRaw(this, 50);
    GradientDrawable againBg = round(GCAM_BTN, 999);
    againBg.setStroke(dp(1), 0x28ffffff);
    TextView again = text(I18n.t("Quay lại"), 14.5f, 0xffffffff, true);
    again.setGravity(Gravity.CENTER);
    again.setBackground(againBg);
    again.setOnClickListener(v -> dismissVideoReview());
    bar.addView(again, new LinearLayout.LayoutParams(0, raw50, 1));
    UiMetrics.enforceMinTouchTarget(again, 48);
    TextView next = text(I18n.t("Tiếp tục"), 14.5f, 0xff111114, true);
    next.setShadowLayer(0, 0, 0, 0);
    next.setGravity(Gravity.CENTER);
    next.setBackground(round(0xffffffff, 999));
    next.setOnClickListener(v -> deliverReviewedVideo());
    LinearLayout.LayoutParams np = new LinearLayout.LayoutParams(0, raw50, 1);
    np.leftMargin = dp(12);
    bar.addView(next, np);
    UiMetrics.enforceMinTouchTarget(next, 48);
    reviewLayer.addView(bar, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
  }

  private void dismissVideoReview() {
    if (reviewVideo != null) {
      reviewVideo.stopPlayback();
      reviewVideo = null;
    }
    if (reviewedVideo != null && "file".equals(reviewedVideo.getScheme()) && reviewedVideo.getPath() != null) {
      File revFile = new File(reviewedVideo.getPath());
      if (revFile.getParentFile() != null && revFile.getParentFile().equals(getCacheDir()))
        revFile.delete();
    }
    if (output != null) {
      if (output.exists())
        output.delete();
      output = null;
    }
    reviewedVideo = null;
    videoProEdited = false;
    reviewLayer.removeAllViews();
    reviewLayer.setVisibility(View.GONE);
    if (preview != null)
      preview.setVisibility(View.VISIBLE);
    if (studioTopBar != null)
      studioTopBar.setVisibility(View.VISIBLE);
    if (bottomBar != null)
      bottomBar.setVisibility(View.VISIBLE);
    if (isResumedActive && !isFinishing() && !isDestroyed()) {
      Choreographer.getInstance().removeFrameCallback(this);
      Choreographer.getInstance().postFrameCallback(this);
    }
    if (still == null && camera != null && camera.isAvailable())
      openCamera();
  }

  private void deliverReviewedVideo() {
    if (reviewedVideo == null)
      return;
    File deliveredFile = "file".equals(reviewedVideo.getScheme()) && reviewedVideo.getPath() != null
        ? new File(reviewedVideo.getPath()) : null;
    if (output != null && !output.equals(deliveredFile)) {
      deleteIfCacheFile(output);
      output = null;
    }
    Intent result = new Intent();
    result.putExtra(EXTRA_STORY, story);
    result.putExtra("videoProEdited", videoProEdited);
    if ("file".equals(reviewedVideo.getScheme())) {
      result.putExtra(EXTRA_VIDEO, reviewedVideo.getPath());
      setResult(RESULT_OK, result);
    } else {
      result.setData(reviewedVideo).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
      result.setClipData(android.content.ClipData.newRawUri("video", reviewedVideo));
      setResult(RESULT_FIRST_USER, result);
    }
    finish();
  }

  private void requestCloseStudio() {
    if (recording || still != null || capturedPhoto != null
        || (output != null && output.exists() && output.length() > 0)) {
      new Sheet(this)
          .setTitle(I18n.t("Thoát không lưu?"))
          .setMessage(I18n.t("Ảnh hoặc đoạn video vừa quay sẽ bị hủy nếu bạn thoát lúc này."))
          .setPositiveButton(I18n.t("Xóa & thoát"), (d, w) -> finishCancelled())
          .setNegativeButton(I18n.t("Ở lại"), null)
          .show();
      return;
    }
    finishCancelled();
  }

  private void deleteIfCacheFile(File f) {
    if (f == null)
      return;
    try {
      File parent = f.getParentFile();
      if (parent != null && parent.equals(getCacheDir()) && f.exists())
        f.delete();
    } catch (Exception ignored) {
    }
  }

  private void finishCancelled() {
    if (capturedPhoto != null && !savingPhoto) {
      deleteIfCacheFile(capturedPhoto);
      capturedPhoto = null;
    }
    if (output != null) {
      deleteIfCacheFile(output);
      output = null;
    }
    if (reviewedVideo != null && "file".equals(reviewedVideo.getScheme()) && reviewedVideo.getPath() != null) {
      deleteIfCacheFile(new File(reviewedVideo.getPath()));
      reviewedVideo = null;
    }
    setResult(RESULT_CANCELED);
    finish();
  }

  @Override
  public void onBackPressed() {
    if (reviewLayer.getVisibility() == View.VISIBLE) {
      if (reviewedVideo != null)
        dismissVideoReview();
      else
        dismissPhotoReview();
      return;
    }
    if (!panel.isEmpty()) {
      showPanel("");
      return;
    }
    requestCloseStudio();
  }

  // ======================= Nhạc nền =======================
  // Chọn nhạc kiểu Facebook: bảng gần toàn màn, tìm kiếm, tab Thư viện / Nhạc của
  // bạn, nghe thử, "Dùng bài này".
  private MediaPlayer previewPlayer;

  private void chooseMusic() {
    if (recording || (musicDialog != null && musicDialog.isShowing()))
      return;
    final android.app.Dialog dialog = new android.app.Dialog(this);
    musicDialog = dialog;
    dialog.setCanceledOnTouchOutside(false);
    dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
    final boolean dark = WebTheme.isDark(this);
    final int variant = dark ? 1 : 0;
    final int bg = WebDesign.CARD[variant], ink = WebDesign.INK[variant], muted = WebDesign.MUTED_STRICT[variant],
        soft = WebDesign.WASH[variant], on = WebDesign.SOFT[variant];
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
    FrameLayout head = new FrameLayout(this);
    head.setPadding(dp(12), dp(6), dp(12), dp(6));
    ImageView close = icon("close", ink);
    close.setPadding(dp(9), dp(9), dp(9), dp(9));
    close.setBackground(round(soft, 999));
    close.setContentDescription(I18n.t("Đóng"));
    close.setOnClickListener(v -> dialog.dismiss());
    close.setLayoutParams(new FrameLayout.LayoutParams(dp(38), dp(38), Gravity.START | Gravity.CENTER_VERTICAL));
    head.addView(UiMetrics.wrapMinTouchTarget(this, close, 48));
    TextView title = plain(I18n.t("Âm nhạc"), 17, ink, true);
    title.setGravity(Gravity.CENTER);
    head.addView(title, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    if (musicUrl != null || musicLocal != null) {
      TextView off = plain(I18n.t("Bỏ nhạc"), 13, WebDesign.DANGER[variant], true);
      off.setGravity(Gravity.CENTER);
      off.setPadding(dp(12), dp(8), dp(8), dp(8));
      off.setOnClickListener(v -> {
        setMusic(null, null, null);
        dialog.dismiss();
      });
      head.addView(off, new FrameLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48), Gravity.END | Gravity.CENTER_VERTICAL));
      UiMetrics.enforceMinTouchTarget(off, 48);
    }
    sheet.addView(head, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout search = new LinearLayout(this);
    search.setGravity(Gravity.CENTER_VERTICAL);
    search.setPadding(dp(14), 0, dp(14), 0);
    search.setBackground(round(soft, 999));
    search.addView(icon("search", muted), new LinearLayout.LayoutParams(dp(18), dp(18)));
    final EditText query = new KinnectInput(this);
    query.setHint(I18n.t("Tìm bài hát hoặc nghệ sĩ"));
    query.setHintTextColor(muted);
    query.setTextColor(ink);
    query.setTextSize(14);
    query.setBackground(null);
    query.setSingleLine(true);
    query.setGravity(Gravity.CENTER_VERTICAL);
    query.setPadding(dp(8), dp(4), dp(8), dp(4));
    search.addView(query, new LinearLayout.LayoutParams(0, -1, 1));
    UiMetrics.enforceMinTouchTarget(query, 48);
    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, UiMetrics.dpRaw(this, 48));
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
    GradientDrawable ug = new GradientDrawable(GradientDrawable.Orientation.TL_BR, WebDesign.WALLET_HERO_GRADIENT);
    ug.setCornerRadius(dp(999));
    use.setBackground(ug);
    bar.addView(use, new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48)));
    UiMetrics.enforceMinTouchTarget(use, 48);
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
          TextView b = plain(I18n.t(t[1]), 14, active ? 0xffffffff : ink, true);
          b.setGravity(Gravity.CENTER);
          b.setPadding(dp(16), dp(8), dp(16), dp(8));
          if (active) {
            GradientDrawable activeTabBg = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                WebDesign.HERO_GRADIENT);
            activeTabBg.setCornerRadius(dp(999));
            b.setBackground(activeTabBg);
          } else {
            b.setBackground(round(soft, 999));
          }
          b.setOnClickListener(v -> {
            tab[0] = t[0];
            shown[0] = 60;
            run();
            render[0].run();
          });
          LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(StudioActivity.this, 48));
          lp.rightMargin = dp(8);
          tabs.addView(b, lp);
          UiMetrics.enforceMinTouchTarget(b, 48);
        }
      }
    };
    final java.util.function.Consumer<String[]> choose = t -> {
      picked[0] = t[0];
      picked[1] = t[1];
      picked[2] = t[2];
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
        TextView art = plain("＋", 26, dark ? WebDesign.STORE_DARK_PREVIEW_TEXT : WebDesign.PURPLE_INK[0], true);
        art.setGravity(Gravity.CENTER);
        art.setBackground(round(dark ? WebDesign.SOFT[1] : WebDesign.SOFT[0], 10));
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
          try {
            startActivityForResult(pick, 402);
          } catch (Exception e) {
            Toast.makeText(this, I18n.t("Không mở được trình chọn nhạc."), Toast.LENGTH_SHORT).show();
          }
        });
        list.addView(up);
        UiMetrics.enforceMinTouchTarget(up, 48);
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
        TextView retry = plain(I18n.t("Thử lại"), 14, WebDesign.PURPLE_TEXT_STRICT[variant], true);
        retry.setGravity(Gravity.CENTER);
        retry.setPadding(dp(18), dp(8), dp(18), dp(8));
        retry.setBackground(round(soft, 999));
        retry.setOnClickListener(v -> loadMusicList[0].run());
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48));
        rp.topMargin = dp(12);
        errBox.addView(retry, rp);
        UiMetrics.enforceMinTouchTarget(retry, 48);
        list.addView(errBox, new LinearLayout.LayoutParams(-1, -2));
        return;
      }
      int count = 0, total = 0;
      for (int i = 0; i < tracks[0].length(); i++) {
        final JSONObject t = tracks[0].optJSONObject(i);
        if (t == null)
          continue;
        String name = t.optString("title"), artist = t.optString("artist");
        if (!nq.isEmpty()) {
          String normTarget = LiveGamePicker.normalized(name + " " + artist);
          boolean matches = true;
          for (String word : nq.split("\\s+")) {
            if (!word.isEmpty() && !normTarget.contains(word)) {
              matches = false;
              break;
            }
          }
          if (!matches)
            continue;
        }
        total++;
        if (count >= shown[0])
          continue;
        count++;
        final String url = api.origin() + t.optString("url");
        boolean sel = url.equals(picked[0]);
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(8), dp(8), dp(8), dp(8));
        row.setBackground(round(sel ? on : 0x00000000, 14));
        float hue = Math.abs(name.hashCode()) % 360;
        FrameLayout art = new FrameLayout(this);
        GradientDrawable ag = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
            new int[] { Color.HSVToColor(new float[] { hue, 0.65f, 0.85f }),
                Color.HSVToColor(new float[] { (hue + 50) % 360, 0.75f, 0.6f }) });
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
        play.setBackground(round(sel ? WebDesign.PURPLE_HERO[0] : soft, 999));
        play.setContentDescription(url.equals(playing[0]) ? I18n.t("Tạm dừng nhạc") : I18n.t("Nghe thử nhạc"));
        ImageView glyph = icon(url.equals(playing[0]) ? "pause" : "play", sel ? 0xffffffff : ink);
        play.addView(glyph, new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
        final String[] entry = { url, name, artist };
        View.OnClickListener tap = v -> {
          if (url.equals(playing[0])) {
            stopPreview();
            playing[0] = null;
            render[0].run();
            return;
          }
          playPreview(url);
          playing[0] = url;
          choose.accept(entry);
          render[0].run();
        };
        row.setOnClickListener(tap);
        play.setOnClickListener(tap);
        play.setLayoutParams(new LinearLayout.LayoutParams(dp(38), dp(38)));
        row.addView(UiMetrics.wrapMinTouchTarget(this, play, 48));
        list.addView(row);
        UiMetrics.enforceMinTouchTarget(row, 48);
      }
      if (total == 0) {
        TextView e = plain(nq.isEmpty() ? I18n.t("Thư viện chưa có bài nào.") : I18n.t("Không tìm thấy bài phù hợp."),
            14, muted, false);
        e.setGravity(Gravity.CENTER);
        e.setPadding(0, dp(30), 0, dp(30));
        list.addView(e, new LinearLayout.LayoutParams(-1, -2));
      }
      if (total > shown[0]) {
        TextView more = plain(I18n.t("Xem thêm (") + (total - shown[0]) + I18n.t(" bài)"), 14, ink, true);
        more.setGravity(Gravity.CENTER);
        more.setPadding(dp(18), dp(8), dp(18), dp(8));
        more.setBackground(round(soft, 999));
        more.setOnClickListener(v -> {
          shown[0] += 60;
          render[0].run();
        });
        LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48));
        mp.gravity = Gravity.CENTER_HORIZONTAL;
        mp.setMargins(0, dp(8), 0, dp(8));
        list.addView(more, mp);
        UiMetrics.enforceMinTouchTarget(more, 48);
      }
    };
    loadMusicList[0] = () -> {
      loading[0] = true;
      loadError[0] = null;
      render[0].run();
      api.call("GET", "/api/music", null, null, (data, error, status) -> {
        if (isFinishing() || isDestroyed())
          return;
        loading[0] = false;
        JSONArray list2 = data == null ? null : data.optJSONArray("tracks");
        if (list2 != null) {
          tracks[0] = list2;
          loadError[0] = null;
        } else {
          loadError[0] = error != null && !error.isEmpty() ? error : I18n.t("Không thể tải nhạc từ máy chủ.");
        }
        render[0].run();
      }, () -> {
        if (isFinishing() || isDestroyed())
          return;
        loading[0] = false;
        loadError[0] = I18n.t("Phiên đã thay đổi, vui lòng thử lại.");
        render[0].run();
      });
    };
    query.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence a, int b, int c, int d) {
      }

      public void onTextChanged(CharSequence a, int b, int c, int d) {
      }

      public void afterTextChanged(android.text.Editable e) {
        shown[0] = 60;
        render[0].run();
      }
    });
    use.setOnClickListener(v -> {
      if (picked[0] != null)
        setMusic(picked[0], null, picked[1]);
      dialog.dismiss();
    });
    dialog.setOnDismissListener(x -> {
      stopPreview();
      if (musicDialog == dialog)
        musicDialog = null;
      if (studioTopBar != null)
        studioTopBar.setVisibility(View.VISIBLE);
    });
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
        win.setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
            Math.round(getResources().getDisplayMetrics().heightPixels * 0.86f));
        win.setGravity(Gravity.BOTTOM);
      }
    });
    dialog.show();
    if (studioTopBar != null)
      studioTopBar.setVisibility(View.INVISIBLE);
    if (dialog.getWindow() != null) {
      dialog.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
          Math.round(getResources().getDisplayMetrics().heightPixels * 0.86f));
      dialog.getWindow().setGravity(Gravity.BOTTOM);
    }
    if (music != null)
      music.pause();
    loadMusicList[0].run();
  }

  private TextView plain(String s, float size, int color, boolean bold) {
    TextView t = new KinnectText(this);
    t.setText(s);
    t.setTextSize(size);
    t.setTextColor(color);
    if (bold)
      t.setTypeface(Typeface.DEFAULT_BOLD);
    return t;
  }

  private void playPreview(String url) {
    stopPreview();
    try {
      previewPlayer = new MediaPlayer();
      boolean isDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
      if (isDebug && NativeApi.isFixtureEnabled() && url != null && url.contains("/music/")) {
        final String assetPath = url.contains("m1") ? "gifts/aurora.wav"
            : url.contains("m2") ? "gifts/butterfly.wav"
                : url.contains("m3") ? "gifts/lotus.wav"
                    : "gifts/star.wav";
        java.io.File cacheFile = new java.io.File(getCacheDir(), "qa_preview_" + assetPath.replace("/", "_"));
        try (java.io.InputStream in = getAssets().open(assetPath);
            java.io.OutputStream out = new java.io.FileOutputStream(cacheFile)) {
          byte[] buf = new byte[8192];
          int n;
          while ((n = in.read(buf)) != -1)
            out.write(buf, 0, n);
        }
        previewPlayer.setDataSource(cacheFile.getAbsolutePath());
        previewPlayer.setLooping(true);
        previewPlayer.setOnPreparedListener(mp -> {
          mp.start();
          android.util.Log.i("KinnectQA",
              "MUSIC_PREVIEW_PLAY: url=" + url + " asset=" + assetPath + " isPlaying=" + mp.isPlaying());
        });
        previewPlayer.prepareAsync();
        return;
      }
      Map<String, String> headers = new HashMap<>();
      headers.put("Cookie", api.jar());
      previewPlayer.setDataSource(this, Uri.parse(url), headers);
      previewPlayer.setOnPreparedListener(MediaPlayer::start);
      previewPlayer.prepareAsync();
    } catch (Exception ignored) {
    }
  }

  private void stopPreview() {
    if (previewPlayer != null) {
      boolean isDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
      boolean wasPlaying = false;
      try {
        wasPlaying = previewPlayer.isPlaying();
      } catch (Exception ignored) {
      }
      if (isDebug && NativeApi.isFixtureEnabled()) {
        android.util.Log.i("KinnectQA", "MUSIC_PREVIEW_STOP: wasPlaying=" + wasPlaying);
      }
      try {
        previewPlayer.release();
      } catch (Exception ignored) {
      }
      previewPlayer = null;
    }
  }

  private File copyGalleryPhotoToCache(Uri uri) throws IOException {
    String mime = getContentResolver().getType(uri);
    String ext = "image/png".equalsIgnoreCase(mime) ? ".png"
        : "image/webp".equalsIgnoreCase(mime) ? ".webp"
            : ".jpg";
    File local = File.createTempFile("gallery-photo-", ext, getCacheDir());
    boolean ok = false;
    try (InputStream in = getContentResolver().openInputStream(uri);
        OutputStream out = new FileOutputStream(local)) {
      if (in == null)
        throw new IOException("null stream");
      byte[] buffer = new byte[32768];
      long bytes = 0;
      for (int n; (n = in.read(buffer)) != -1;) {
        bytes += n;
        if (bytes > 64L * 1024 * 1024)
          throw new IOException("large");
        out.write(buffer, 0, n);
      }
      ok = true;
    } finally {
      if (!ok)
        local.delete();
    }
    return local;
  }

  @Override
  protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (result != RESULT_OK || data == null)
      return;
    if (request == 408) {
      String videoPath = data.getStringExtra(EXTRA_VIDEO);
      Uri editedVideo = (videoPath != null && !videoPath.isEmpty())
          ? Uri.fromFile(new File(videoPath))
          : data.getData();
      if (editedVideo == null)
        return;
      File editedFile = "file".equals(editedVideo.getScheme()) && editedVideo.getPath() != null
          ? new File(editedVideo.getPath()) : null;
      if (output != null && !output.equals(editedFile)) {
        deleteIfCacheFile(output);
        output = null;
      }
      if (reviewedVideo != null && !reviewedVideo.equals(editedVideo)
          && "file".equals(reviewedVideo.getScheme()) && reviewedVideo.getPath() != null) {
        File prevReviewed = new File(reviewedVideo.getPath());
        if (!prevReviewed.equals(editedFile))
          deleteIfCacheFile(prevReviewed);
      }
      if (editedFile != null)
        output = editedFile;
      videoProEdited = true;
      showVideoReview(editedVideo);
      return;
    }
    if (request == 406) {
      String path = data.getStringExtra(EXTRA_IMAGE);
      final Uri fallbackUri = data.getData();
      if ((path == null || path.isEmpty()) && fallbackUri != null && "file".equals(fallbackUri.getScheme()))
        path = fallbackUri.getPath();
      if ((path == null || path.isEmpty()) && fallbackUri == null)
        return;
      final String resolvedPath = path;
      try {
        worker.execute(() -> {
          try {
            File edited;
            if (resolvedPath != null && !resolvedPath.isEmpty()) {
              edited = new File(resolvedPath);
            } else {
              edited = File.createTempFile("edited-photo-", ".jpg", getCacheDir());
              try (InputStream in = getContentResolver().openInputStream(fallbackUri);
                  OutputStream out = new FileOutputStream(edited)) {
                if (in == null)
                  throw new IOException("null stream");
                byte[] buffer = new byte[32768];
                for (int n; (n = in.read(buffer)) != -1;)
                  out.write(buffer, 0, n);
              }
            }
            Bitmap shown = PhotoRenderer.decode(edited, 1280);
            final File finalEdited = edited;
            ui.post(() -> {
              if (isFinishing() || isDestroyed()) {
                if (shown != null && !shown.isRecycled())
                  shown.recycle();
                return;
              }
              if (capturedPhoto != null && !capturedPhoto.equals(finalEdited) && !savingPhoto)
                deleteIfCacheFile(capturedPhoto);
              capturedPhoto = finalEdited;
              photoProEdited = true;
              showReview(shown);
            });
          } catch (Exception | OutOfMemoryError e) {
            ui.post(() -> {
              if (!isFinishing() && !isDestroyed())
                Toast.makeText(this, I18n.t("Không mở được ảnh."), Toast.LENGTH_SHORT).show();
            });
          }
        });
      } catch (RejectedExecutionException ignored) {
      }
      return;
    }
    if (data.getData() == null)
      return;
    if (request == 407) {
      openVideoPro(data.getData());
      return;
    }
    if (request == 405) {
      openPhotoPro(data.getData());
      return;
    }
    if (request == 403)
      photoProEdited = false;
    if (request == 402)
      setMusic(null, data.getData(), "Nhạc của bạn");
    if (request == 403) {
      final Uri selected = data.getData();
      try {
        worker.execute(() -> {
          try {
            File local = copyGalleryPhotoToCache(selected);
            Bitmap shown = PhotoRenderer.decode(local, 1280);
            ui.post(() -> {
              if (isFinishing() || isDestroyed()) {
                if (shown != null && !shown.isRecycled())
                  shown.recycle();
                local.delete();
                return;
              }
              if (capturedPhoto != null && !capturedPhoto.equals(local) && !savingPhoto)
                deleteIfCacheFile(capturedPhoto);
              capturedPhoto = local;
              photoProEdited = false;
              showReview(shown);
            });
          } catch (Exception | OutOfMemoryError e) {
            ui.post(() -> {
              if (!isFinishing() && !isDestroyed())
                Toast.makeText(this, I18n.t("Không mở được ảnh."), Toast.LENGTH_SHORT).show();
            });
          }
        });
      } catch (RejectedExecutionException ignored) {
      }
    }
    if (request == 404) {
      videoProEdited = false;
      try {
        getContentResolver().takePersistableUriPermission(data.getData(),
            data.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION);
      } catch (SecurityException ignored) {
      }
      showVideoReview(data.getData());
    }
  }

  private void setMusic(String url, Uri local, String title) {
    if (music != null) {
      music.release();
      music = null;
    }
    musicUrl = url;
    musicLocal = local;
    musicLabel.setText(title == null ? I18n.t("Thêm nhạc") : title.replaceAll("\\s+", " ").trim());
    musicLabel.setTextColor(title == null ? 0xffffffff : GCAM_AMBER);
    if (url == null && local == null)
      return;
    try {
      music = new MediaPlayer();
      music.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
          .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());
      if (url != null) {
        Map<String, String> headers = new HashMap<>();
        headers.put("Cookie", api.jar());
        music.setDataSource(this, Uri.parse(url), headers);
      } else
        music.setDataSource(this, local);
      music.setLooping(true);
      music.setOnPreparedListener(p -> {
        if (!recording)
          p.start();
      });
      music.setOnErrorListener((p, w, e) -> {
        Toast.makeText(this, I18n.t("Không phát được bài nhạc này."), Toast.LENGTH_SHORT).show();
        return true;
      });
      music.prepareAsync();
    } catch (Exception e) {
      Toast.makeText(this, I18n.t("Không phát được bài nhạc này."), Toast.LENGTH_SHORT).show();
      musicUrl = null;
      musicLocal = null;
    }
  }

  // ======================= Các view vẽ tay chuẩn Google Camera
  // =======================
  /**
   * Vòng lấy nét cảm ứng chuẩn Google Camera (Pixel Camera Focus & Exposure
   * Ring).
   */
  static final class FocusRingView extends View {
    private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    private float fx = -1, fy = -1, scale = 1f, alpha = 0f;
    private ValueAnimator anim;
    private final Runnable fadeOut = () -> animateAlpha(0f, 280);

    FocusRingView(android.content.Context c) {
      super(c);
    }

    void showAt(float x, float y) {
      fx = x;
      fy = y;
      removeCallbacks(fadeOut);
      if (anim != null)
        anim.cancel();
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
      if (anim != null)
        anim.cancel();
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
      if (alpha <= 0.01f || fx < 0 || fy < 0)
        return;
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
      // Thanh trượt phơi sáng mặt trời (Google Camera Sun Exposure Indicator) cạnh
      // vòng lấy nét
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

  /**
   * Nút chụp chuẩn Google Camera: Ảnh = vành trắng sắc nét + đĩa trắng lớn; Video
   * = vành trắng + tâm đỏ Pixel (#EE2B2B), khi quay chuyển thành hình vuông bo
   * góc.
   */
  static final class ShutterView extends View {
    private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    private String mode = "video";
    private boolean rec;
    private float progress;

    ShutterView(android.content.Context c) {
      super(c);
    }

    void setMode(String m) {
      mode = m;
      invalidate();
    }

    void setRecording(boolean r) {
      rec = r;
      invalidate();
    }

    void setProgress(float v) {
      progress = Math.max(0, Math.min(1, v));
      invalidate();
    }

    @Override
    public boolean onTouchEvent(MotionEvent e) {
      int a = e.getActionMasked();
      if (a == MotionEvent.ACTION_DOWN)
        animate().scaleX(0.91f).scaleY(0.91f).setDuration(90).start();
      else if (a == MotionEvent.ACTION_UP || a == MotionEvent.ACTION_CANCEL)
        animate().scaleX(1f).scaleY(1f).setDuration(140).start();
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
        p.setColor(WebDesign.LIVE_RED);
        c.drawCircle(cx, cy, r * 0.64f, p);
      } else {
        p.setColor(0xffffffff);
        c.drawCircle(cx, cy, r * 0.77f, p);
        p.setColor(GCAM_RED);
        c.drawCircle(cx, cy, r * 0.34f, p);
      }
    }
  }

  /**
   * Lưới 3×3 kèm tâm ngắm cân bằng (+) chuẩn Google Camera và vùng che khi chọn
   * tỉ lệ 3:4 hoặc 1:1.
   */
  static final class GridOverlay extends View {
    private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    private boolean grid;
    private int ratio;

    GridOverlay(android.content.Context c) {
      super(c);
    }

    void setGrid(boolean g) {
      grid = g;
      invalidate();
    }

    void setRatio(int r) {
      ratio = r;
      invalidate();
    }

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
      if (!grid)
        return;
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
