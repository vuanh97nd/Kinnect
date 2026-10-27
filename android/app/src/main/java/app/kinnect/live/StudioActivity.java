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

  private final FxEngine fx = new FxEngine();
  private FrameLayout root, stage, panelHost, reviewLayer;
  private TextureView camera;
  private SurfaceView preview;
  private TextView timer, musicLabel, faceStatus, filterToast, countdown;
  private ShutterView shutter;
  private LinearLayout modeTabs, rail;
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

  private int dp(float n) { return Math.round(n * getResources().getDisplayMetrics().density); }

  private GradientDrawable round(int color, float radius) { GradientDrawable g = new GradientDrawable(); g.setColor(color); g.setCornerRadius(dp(radius)); return g; }

  private TextView text(String s, float size, int color, boolean bold) {
    TextView t = new TextView(this);
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

    // Khung hình 9:16 ở giữa, bo góc như các app máy ảnh hiện đại
    stage = new FrameLayout(this);
    stage.setClipToOutline(true);
    stage.setBackground(round(0xff111111, 20));
    camera = new TextureView(this);
    preview = new SurfaceView(this);
    stage.addView(camera, new FrameLayout.LayoutParams(-1, -1));
    stage.addView(preview, new FrameLayout.LayoutParams(-1, -1));
    gridOverlay = new GridOverlay(this);
    stage.addView(gridOverlay, new FrameLayout.LayoutParams(-1, -1));
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
    // Vuốt ngang để đổi bộ lọc, chạm hai lần để đổi camera
    final GestureDetector gestures = new GestureDetector(this, new GestureDetector.SimpleOnGestureListener() {
      public boolean onDown(MotionEvent e) { return true; }
      public boolean onFling(MotionEvent a, MotionEvent b, float vx, float vy) {
        if (Math.abs(vx) < Math.abs(vy) || Math.abs(b.getX() - a.getX()) < dp(40)) return false;
        stepFilter(vx < 0 ? 1 : -1);
        return true;
      }
      public boolean onDoubleTap(MotionEvent e) { flip(); return true; }
      public boolean onSingleTapUp(MotionEvent e) { if (!panel.isEmpty()) showPanel(""); return true; }
    });
    final ScaleGestureDetector pinch = new ScaleGestureDetector(this, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
      public boolean onScale(ScaleGestureDetector d) { if (still == null) setZoom(zoom * d.getScaleFactor()); return true; }
    });
    stage.setOnTouchListener((v, e) -> { pinch.onTouchEvent(e); if (!pinch.isInProgress() && e.getPointerCount() == 1) gestures.onTouchEvent(e); return true; });

    // Thanh trên: đóng · nhạc nền
    LinearLayout top = new LinearLayout(this);
    top.setGravity(Gravity.CENTER_VERTICAL);
    top.setPadding(dp(10), dp(14), dp(10), dp(24));
    top.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x88000000, 0x00000000 }));
    ImageView close = icon("close", 0xffffffff);
    close.setPadding(dp(9), dp(9), dp(9), dp(9));
    close.setContentDescription("Đóng");
    close.setOnClickListener(v -> finishCancelled());
    top.addView(close, new LinearLayout.LayoutParams(dp(42), dp(42)));
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    musicLabel = text("🎵  Thêm nhạc", 14, 0xffffffff, true);
    musicLabel.setGravity(Gravity.CENTER);
    musicLabel.setPadding(dp(16), 0, dp(16), 0);
    musicLabel.setBackground(round(0x55000000, 999));
    musicLabel.setSingleLine(true);
    musicLabel.setEllipsize(android.text.TextUtils.TruncateAt.END);
    musicLabel.setMaxWidth(dp(220));
    musicLabel.setOnClickListener(v -> chooseMusic());
    top.addView(musicLabel, new LinearLayout.LayoutParams(-2, dp(38)));
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    top.addView(new View(this), new LinearLayout.LayoutParams(dp(42), 1));
    stage.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));

    // Thanh công cụ dọc bên phải
    rail = new LinearLayout(this);
    rail.setOrientation(LinearLayout.VERTICAL);
    rail.setGravity(Gravity.CENTER_HORIZONTAL);
    FrameLayout.LayoutParams rp = new FrameLayout.LayoutParams(dp(58), -2, Gravity.END | Gravity.TOP);
    rp.topMargin = dp(70);
    rp.rightMargin = dp(8);
    rail.setPadding(0, dp(6), 0, dp(6));
    rail.setBackground(round(0x40000000, 999));
    stage.addView(rail, rp);
    buildRail();

    faceStatus = text("", 13, 0xffffffff, false);
    FrameLayout.LayoutParams fs = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    fs.topMargin = dp(72);
    stage.addView(faceStatus, fs);
    filterToast = text("", 30, 0xffffffff, true);
    filterToast.setAlpha(0);
    stage.addView(filterToast, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    countdown = text("", 96, 0xffffffff, true);
    countdown.setVisibility(View.GONE);
    stage.addView(countdown, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    timer = text("", 14, 0xffffffff, true);
    timer.setPadding(dp(12), dp(4), dp(12), dp(4));
    timer.setVisibility(View.GONE);
    timer.setBackground(round(0xccff3b5c, 999));
    FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    tp.topMargin = dp(66);
    stage.addView(timer, tp);

    // Vùng dưới: bảng hiệu ứng · hàng nút · chế độ
    LinearLayout bottom = new LinearLayout(this);
    bottom.setOrientation(LinearLayout.VERTICAL);
    bottom.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, new int[] { 0xee000000, 0x99000000, 0x00000000 }));
    bottom.setPadding(0, dp(30), 0, dp(10));
    panelHost = new FrameLayout(this);
    bottom.addView(panelHost, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout actions = new LinearLayout(this);
    actions.setGravity(Gravity.CENTER);
    actions.setPadding(dp(8), dp(8), dp(8), dp(4));
    actions.addView(roundAction("image", "Thư viện", this::openGallery), new LinearLayout.LayoutParams(0, -2, 1));
    actions.addView(roundAction("smile", "Sticker", () -> showPanel(panel.equals("sticker") ? "" : "sticker")), new LinearLayout.LayoutParams(0, -2, 1));
    shutter = new ShutterView(this);
    shutter.setContentDescription("Chụp hoặc quay");
    shutter.setOnClickListener(v -> onShutter());
    actions.addView(shutter, new LinearLayout.LayoutParams(dp(84), dp(84)));
    actions.addView(roundAction("wand", "Làm đẹp", () -> showPanel(panel.equals("beauty") ? "" : "beauty")), new LinearLayout.LayoutParams(0, -2, 1));
    actions.addView(roundAction("palette", "Bộ lọc", () -> showPanel(panel.equals("filter") ? "" : "filter")), new LinearLayout.LayoutParams(0, -2, 1));
    modeTabs = new LinearLayout(this);
    modeTabs.setGravity(Gravity.CENTER);
    modeTabs.setPadding(0, dp(2), 0, dp(4));
    bottom.addView(modeTabs, new LinearLayout.LayoutParams(-1, -2));
    bottom.addView(actions);
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
    if (still == null) ensurePermissions();
  }

  private void ensurePermissions() {
    List<String> need = new ArrayList<>();
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) need.add(Manifest.permission.CAMERA);
    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) need.add(Manifest.permission.RECORD_AUDIO);
    if (!need.isEmpty()) requestPermissions(need.toArray(new String[0]), 401);
  }

  private LinearLayout roundAction(String iconName, String label, Runnable click) {
    LinearLayout b = new LinearLayout(this);
    b.setOrientation(LinearLayout.VERTICAL);
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    FrameLayout circle = new FrameLayout(this);
    circle.setBackground(round(0x33ffffff, 999));
    circle.addView(icon(iconName, 0xffffffff), new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
    b.addView(circle, new LinearLayout.LayoutParams(dp(46), dp(46)));
    TextView t = text(label, 11, 0xffffffff, true);
    t.setPadding(0, dp(4), 0, 0);
    t.setGravity(Gravity.CENTER);
    b.addView(t, new LinearLayout.LayoutParams(-1, -2));
    b.setContentDescription(label);
    b.setOnClickListener(v -> click.run());
    return b;
  }

  private void buildRail() {
    rail.removeAllViews();
    rail.addView(railButton("flip", "Lật", this::flip));
    if (still == null) rail.addView(railButton(torch ? "flash" : "flash_off", torch ? "Đèn: bật" : "Đèn", () -> { torch = !torch; applyTorch(); buildRail(); }));
    rail.addView(railButton("timer", timerSeconds == 0 ? "Hẹn giờ" : timerSeconds + " giây", () -> { timerSeconds = timerSeconds == 0 ? 3 : timerSeconds == 3 ? 10 : 0; buildRail(); }));
    rail.addView(railButton("grid", grid ? "Lưới: bật" : "Lưới", () -> { grid = !grid; gridOverlay.setGrid(grid); buildRail(); }));
    if (mode.equals("photo")) rail.addView(railButton("ratio", ratio == 0 ? "9:16" : ratio == 1 ? "3:4" : "1:1", () -> { ratio = (ratio + 1) % 3; gridOverlay.setRatio(ratio); buildRail(); }));
    if (mode.equals("video") && !story) rail.addView(railButton("timer", (limitSeconds == 0 ? "∞" : limitSeconds + "s"), () -> { limitSeconds = limitSeconds == 0 ? 15 : limitSeconds == 15 ? 30 : limitSeconds == 30 ? 60 : 0; buildRail(); }));
  }

  private LinearLayout railButton(String iconName, String label, Runnable click) {
    LinearLayout b = new LinearLayout(this);
    b.setOrientation(LinearLayout.VERTICAL);
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    b.setPadding(0, dp(6), 0, dp(6));
    ImageView i = icon(iconName, 0xffffffff);
    i.setElevation(dp(2));
    b.addView(i, new LinearLayout.LayoutParams(dp(26), dp(26)));
    TextView t = text(label, 10, 0xffffffff, true);
    t.setGravity(Gravity.CENTER);
    b.addView(t);
    b.setContentDescription(label);
    b.setOnClickListener(v -> { if (!recording) click.run(); });
    return b;
  }

  private void renderModes() {
    modeTabs.removeAllViews();
    String[][] modes = story ? new String[][] { { "video", "TIN 15 GIÂY" } } : new String[][] { { "photo", "ẢNH" }, { "video", "VIDEO" }, { "live", "LIVE" } };
    for (final String[] m : modes) {
      boolean on = m[0].equals(mode);
      LinearLayout cell = new LinearLayout(this);
      cell.setOrientation(LinearLayout.VERTICAL);
      cell.setGravity(Gravity.CENTER_HORIZONTAL);
      cell.setPadding(dp(18), 0, dp(18), 0);
      TextView t = text(m[1], 13, on ? 0xffffffff : 0x99ffffff, true);
      t.setLetterSpacing(0.08f);
      t.setGravity(Gravity.CENTER);
      t.setSingleLine(true);
      cell.addView(t, new LinearLayout.LayoutParams(-1, -2));
      View dot = new View(this);
      dot.setBackground(round(on ? 0xffffffff : 0x00000000, 99));
      LinearLayout.LayoutParams dp5 = new LinearLayout.LayoutParams(dp(5), dp(5));
      dp5.topMargin = dp(4);
      cell.addView(dot, dp5);
      if (m[0].equals("live")) t.setTextColor(0xffff5c7c);
      cell.setOnClickListener(v -> { if (m[0].equals("live")) { if (!recording && !busy) { closeCamera(); startActivity(new android.content.Intent(this, LiveActivity.class).putExtra(LiveActivity.EXTRA_HOST, true)); finish(); } return; } if (!recording && !busy) { mode = m[0]; renderModes(); buildRail(); shutter.setMode(mode); gridOverlay.setRatio(mode.equals("photo") ? ratio : 0); } });
      modeTabs.addView(cell, new LinearLayout.LayoutParams(dp(story ? 140 : 84), -2));
    }
    if (shutter != null) shutter.setMode(mode);
  }

  // ======================= Bảng hiệu ứng =======================
  private void showPanel(String which) {
    panel = which;
    panelHost.removeAllViews();
    filterThumbs.clear();
    if (which.equals("filter")) panelHost.addView(filterPanel());
    if (which.equals("beauty")) panelHost.addView(beautyPanel());
    if (which.equals("sticker")) panelHost.addView(stickerPanel());
  }

  private SeekBar slider(int value, SeekBar.OnSeekBarChangeListener l) {
    SeekBar s = new SeekBar(this);
    s.setMax(100);
    s.setProgress(value);
    s.getProgressDrawable().setTint(0xffffffff);
    s.getThumb().setTint(0xffffffff);
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
    final TextView pct = text(Math.round(fx.intensity * 100) + "", 12, 0xffffffff, true);
    LinearLayout sl = new LinearLayout(this);
    sl.setGravity(Gravity.CENTER_VERTICAL);
    sl.setPadding(dp(20), 0, dp(20), 0);
    sl.addView(text("Độ đậm", 12, 0xffffffff, true));
    sl.addView(slider(Math.round(fx.intensity * 100), new Slide() {
      public void onProgressChanged(SeekBar s, int v, boolean u) { fx.intensity = v / 100f; pct.setText(String.valueOf(v)); }
    }), new LinearLayout.LayoutParams(0, -2, 1));
    sl.addView(pct, new LinearLayout.LayoutParams(dp(30), -2));
    if (!fx.filter.equals("none")) box.addView(sl);
    HorizontalScrollView hs = new HorizontalScrollView(this);
    hs.setHorizontalScrollBarEnabled(false);
    LinearLayout row = new LinearLayout(this);
    row.setPadding(dp(10), dp(6), dp(10), dp(6));
    for (final String[] f : FxEngine.FILTERS) {
      boolean on = fx.filter.equals(f[0]);
      LinearLayout cell = new LinearLayout(this);
      cell.setOrientation(LinearLayout.VERTICAL);
      cell.setGravity(Gravity.CENTER_HORIZONTAL);
      cell.setPadding(dp(4), 0, dp(4), 0);
      FrameLayout pic = new FrameLayout(this);
      pic.setBackground(round(on ? 0xffffffff : 0x00000000, 14));
      pic.setPadding(dp(2), dp(2), dp(2), dp(2));
      ImageView img = new ImageView(this);
      img.setScaleType(ImageView.ScaleType.CENTER_CROP);
      img.setClipToOutline(true);
      img.setBackground(round(0xff333333, 12));
      img.setImageBitmap(thumb);
      img.setColorFilter(new ColorMatrixColorFilter(FxEngine.filterMatrix(f[0])));
      img.setTag(f[0]);
      filterThumbs.add(img);
      pic.addView(img, new FrameLayout.LayoutParams(dp(58), dp(76)));
      cell.addView(pic);
      TextView t = text(f[1], 11, on ? 0xffffffff : 0xccffffff, on);
      t.setPadding(0, dp(4), 0, 0);
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
    final TextView pct = text(Math.round(fx.get(beautyKey) * 100) + "", 12, 0xffffffff, true);
    LinearLayout sl = new LinearLayout(this);
    sl.setGravity(Gravity.CENTER_VERTICAL);
    sl.setPadding(dp(20), 0, dp(20), 0);
    String name = "";
    for (String[] b : FxEngine.BEAUTY) if (b[0].equals(beautyKey)) name = b[1];
    sl.addView(text(name, 12, 0xffffffff, true), new LinearLayout.LayoutParams(dp(64), -2));
    sl.addView(slider(Math.round(fx.get(beautyKey) * 100), new Slide() {
      public void onProgressChanged(SeekBar s, int v, boolean u) { fx.set(beautyKey, v / 100f); pct.setText(String.valueOf(v)); }
    }), new LinearLayout.LayoutParams(0, -2, 1));
    sl.addView(pct, new LinearLayout.LayoutParams(dp(30), -2));
    box.addView(sl);
    LinearLayout row = new LinearLayout(this);
    row.setGravity(Gravity.CENTER);
    row.setPadding(dp(6), dp(8), dp(6), dp(6));
    String[] glyph = { "✨", "☀️", "💎", "👁", "🌸" };
    row.addView(beautyChip("🤖", fx.auto ? "AI: bật" : "AI", fx.auto, () -> {
      fx.auto = !fx.auto;
      if (fx.auto) { fx.beautyOn = true; fx.analyze(frame, face); showFilterName(face == null ? "AI: tự cân sáng" : "AI làm đẹp"); }
      showPanel("beauty");
    }), new LinearLayout.LayoutParams(0, -2, 1));
    final LinearLayout off = beautyChip("⭕", fx.beautyOn ? "Tắt" : "Đã tắt", !fx.beautyOn, () -> { fx.beautyOn = !fx.beautyOn; showPanel("beauty"); });
    row.addView(off, new LinearLayout.LayoutParams(0, -2, 1));
    for (int i = 0; i < FxEngine.BEAUTY.length; i++) {
      final String key = FxEngine.BEAUTY[i][0];
      row.addView(beautyChip(glyph[i], FxEngine.BEAUTY[i][1], fx.beautyOn && key.equals(beautyKey), () -> { beautyKey = key; fx.beautyOn = true; showPanel("beauty"); }), new LinearLayout.LayoutParams(0, -2, 1));
    }
    box.addView(row);
    TextView reset = text("Khôi phục mặc định", 11, 0xccffffff, false);
    reset.setGravity(Gravity.CENTER);
    reset.setPadding(0, 0, 0, dp(4));
    reset.setOnClickListener(v -> { fx.smooth = 0.5f; fx.whiten = 0.3f; fx.slim = 0.2f; fx.eyes = 0.2f; fx.blush = 0f; fx.beautyOn = true; showPanel("beauty"); });
    box.addView(reset);
    return box;
  }

  private LinearLayout beautyChip(String glyph, String label, boolean on, Runnable click) {
    LinearLayout c = new LinearLayout(this);
    c.setOrientation(LinearLayout.VERTICAL);
    c.setGravity(Gravity.CENTER_HORIZONTAL);
    TextView g = new TextView(this);
    g.setText(glyph);
    g.setTextSize(20);
    g.setGravity(Gravity.CENTER);
    GradientDrawable bg = round(on ? 0xffffffff : 0x33ffffff, 999);
    g.setBackground(bg);
    c.addView(g, new LinearLayout.LayoutParams(dp(44), dp(44)));
    TextView t = text(label, 10, on ? 0xffffffff : 0xccffffff, on);
    t.setPadding(0, dp(4), 0, 0);
    c.addView(t);
    c.setOnClickListener(v -> click.run());
    return c;
  }

  private View stickerPanel() {
    GridLayout gridView = new GridLayout(this);
    gridView.setColumnCount(6);
    gridView.setPadding(dp(8), dp(4), dp(8), dp(6));
    int size = (getResources().getDisplayMetrics().widthPixels - dp(16)) / 6;
    for (final String[] s : FxEngine.STICKERS) {
      boolean on = fx.sticker.equals(s[0]);
      LinearLayout cell = new LinearLayout(this);
      cell.setOrientation(LinearLayout.VERTICAL);
      cell.setGravity(Gravity.CENTER);
      TextView g = new TextView(this);
      g.setText(s[2]);
      g.setTextSize(24);
      g.setGravity(Gravity.CENTER);
      g.setBackground(round(on ? 0x55ffffff : 0x1affffff, 14));
      cell.addView(g, new LinearLayout.LayoutParams(size - dp(10), size - dp(10)));
      TextView t = text(s[1], 9, 0xddffffff, on);
      t.setGravity(Gravity.CENTER);
      t.setSingleLine(true);
      cell.addView(t);
      cell.setOnClickListener(v -> {
        fx.sticker = s[0];
        if (!s[0].equals("none") && face == null) faceStatus.setText("Đưa khuôn mặt vào khung hình");
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
      Toast.makeText(this, "Cần quyền camera để chụp và quay.", Toast.LENGTH_LONG).show();
      finishCancelled();
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    Choreographer.getInstance().postFrameCallback(this);
    if (camera.isAvailable()) openCamera();
  }

  @Override
  protected void onPause() {
    if (recording) stopRecording();
    Choreographer.getInstance().removeFrameCallback(this);
    closeCamera();
    if (music != null) music.pause();
    super.onPause();
  }

  @Override
  protected void onDestroy() {
    worker.shutdownNow();
    if (music != null) { music.release(); music = null; }
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
        public void onError(CameraDevice d, int e) { d.close(); device = null; ui.post(() -> faceStatus.setText("Không mở được camera.")); }
      }, cameraHandler);
    } catch (Exception e) {
      faceStatus.setText("Không mở được camera.");
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
      ui.post(() -> faceStatus.setText("Không mở được camera."));
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
    Float max = characteristics == null ? null : characteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM);
    zoom = Math.max(1f, Math.min(max == null ? 4f : Math.min(max, 8f), value));
    if (previewRequest != null && session != null) {
      applyZoomTo(previewRequest);
      try { session.setRepeatingRequest(previewRequest.build(), null, cameraHandler); } catch (Exception ignored) {}
    }
    showFilterName(String.format(java.util.Locale.US, "%.1f×", zoom));
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
      BitmapFactory.decodeStream(getContentResolver().openInputStream(uri), null, o);
      o.inSampleSize = Math.max(1, Math.min(o.outWidth / PW, o.outHeight / PH));
      o.inJustDecodeBounds = false;
      Bitmap src = BitmapFactory.decodeStream(getContentResolver().openInputStream(uri), null, o);
      stillFull = Bitmap.createBitmap(PW, PH, Bitmap.Config.ARGB_8888);
      Canvas c = new Canvas(stillFull);
      c.drawColor(0xff000000);
      float scale = Math.max(PW / (float) src.getWidth(), PH / (float) src.getHeight());
      float w = src.getWidth() * scale, h = src.getHeight() * scale;
      c.drawBitmap(src, null, new RectF((PW - w) / 2, (PH - h) / 2, (PW + w) / 2, (PH + h) / 2), new Paint(Paint.FILTER_BITMAP_FLAG));
      new Canvas(frame).drawBitmap(stillFull, null, new Rect(0, 0, FW, FH), new Paint(Paint.FILTER_BITMAP_FLAG));
      still = frame;
      front = false;
      closeCamera();
      mode = startMode;
      renderModes();
      buildRail();
      face = null;
    } catch (Exception e) {
      Toast.makeText(this, "Không mở được ảnh.", Toast.LENGTH_LONG).show();
    }
  }

  private void openGallery() {
    if (recording) return;
    new Sheet(this).setTitle("Thư viện").setItems(new String[] { "🖼  Chỉnh ảnh từ máy", "🎬  Đăng video có sẵn (MP4)" }, (d, w) -> {
      Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
      pick.addCategory(Intent.CATEGORY_OPENABLE);
      pick.setType(w == 0 ? "image/*" : "video/mp4");
      try { startActivityForResult(pick, w == 0 ? 403 : 404); } catch (Exception e) { Toast.makeText(this, "Không mở được thư viện.", Toast.LENGTH_SHORT).show(); }
    }).show();
  }

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
    boolean needFace = !fx.sticker.equals("none") || (fx.beautyOn && (fx.smooth > 0 || fx.slim > 0 || fx.eyes > 0 || fx.blush > 0));
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
      timer.setText("● " + (int) elapsed + "s" + (limitSeconds > 0 ? " / " + limitSeconds + "s" : ""));
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
            if (++missed >= 5) { face = null; if (!fx.sticker.equals("none")) faceStatus.setText("Đưa khuôn mặt vào khung hình"); }
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
        ui.post(() -> { busy = false; Toast.makeText(this, "Không chụp được ảnh.", Toast.LENGTH_SHORT).show(); });
      }
    });
  }

  private Bitmap crop(Bitmap b) {
    if (ratio == 0) return b;
    int w = b.getWidth(), h = ratio == 1 ? w * 4 / 3 : w;
    return Bitmap.createBitmap(b, 0, (b.getHeight() - h) / 2, w, h);
  }

  // Màn xem lại sau khi chụp: lưu vào máy · đăng bài · đăng tin · chụp lại
  private void showReview(Bitmap photo) {
    reviewLayer.removeAllViews();
    reviewLayer.setVisibility(View.VISIBLE);
    ImageView img = new ImageView(this);
    img.setScaleType(ImageView.ScaleType.FIT_CENTER);
    img.setImageBitmap(photo);
    reviewLayer.addView(img, new FrameLayout.LayoutParams(-1, -1));
    LinearLayout top = new LinearLayout(this);
    top.setGravity(Gravity.CENTER_VERTICAL);
    top.setPadding(dp(10), dp(14), dp(14), dp(10));
    ImageView back = icon("back", 0xffffffff);
    back.setPadding(dp(9), dp(9), dp(9), dp(9));
    back.setContentDescription("Chụp lại");
    back.setOnClickListener(v -> reviewLayer.setVisibility(View.GONE));
    top.addView(back, new LinearLayout.LayoutParams(dp(42), dp(42)));
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    final TextView save = text("  Lưu vào máy", 14, 0xffffffff, true);
    save.setGravity(Gravity.CENTER);
    save.setPadding(dp(14), 0, dp(16), 0);
    save.setBackground(round(0x55000000, 999));
    save.setCompoundDrawablesRelativeWithIntrinsicBounds(tinted("download"), null, null, null);
    save.setOnClickListener(v -> {
      if (saveToGallery(capturedPhoto)) { save.setText("  Đã lưu"); save.setCompoundDrawablesRelativeWithIntrinsicBounds(tinted("check"), null, null, null); }
    });
    top.addView(save, new LinearLayout.LayoutParams(-2, dp(40)));
    reviewLayer.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    LinearLayout bar = new LinearLayout(this);
    bar.setGravity(Gravity.CENTER);
    bar.setPadding(dp(16), dp(12), dp(16), dp(22));
    bar.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, new int[] { 0xcc000000, 0x00000000 }));
    TextView again = text("Chụp lại", 15, 0xffffffff, true);
    again.setGravity(Gravity.CENTER);
    again.setBackground(round(0x33ffffff, 999));
    again.setOnClickListener(v -> reviewLayer.setVisibility(View.GONE));
    bar.addView(again, new LinearLayout.LayoutParams(0, dp(50), 1));
    TextView storyBtn = text("Đăng tin", 15, 0xffffffff, true);
    storyBtn.setGravity(Gravity.CENTER);
    storyBtn.setBackground(round(0x33ffffff, 999));
    storyBtn.setOnClickListener(v -> deliverPhoto("story"));
    LinearLayout.LayoutParams mid = new LinearLayout.LayoutParams(0, dp(50), 1);
    mid.setMargins(dp(10), 0, dp(10), 0);
    bar.addView(storyBtn, mid);
    TextView post = text("Đăng bài", 15, 0xffffffff, true);
    post.setGravity(Gravity.CENTER);
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6c47e0, PINK });
    g.setCornerRadius(dp(999));
    post.setBackground(g);
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
    try {
      ContentValues v = new ContentValues();
      v.put(MediaStore.Images.Media.DISPLAY_NAME, "Kinnect_" + new java.text.SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date()) + ".jpg");
      v.put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg");
      if (Build.VERSION.SDK_INT >= 29) v.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Kinnect");
      Uri uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
      try (OutputStream os = getContentResolver().openOutputStream(uri); InputStream in = new FileInputStream(file)) {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
      }
      Toast.makeText(this, "Đã lưu vào Ảnh › Kinnect", Toast.LENGTH_SHORT).show();
      return true;
    } catch (Exception e) {
      Toast.makeText(this, "Không lưu được ảnh vào máy.", Toast.LENGTH_SHORT).show();
      return false;
    }
  }

  private void deliverPhoto(String action) {
    Intent result = new Intent();
    result.putExtra(EXTRA_IMAGE, capturedPhoto.getAbsolutePath());
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
      showPanel("");
      if (music != null) { music.seekTo(0); music.start(); }
    } catch (Exception e) {
      releaseRecorder();
      Toast.makeText(this, "Không bắt đầu quay được trên máy này.", Toast.LENGTH_LONG).show();
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
    if (!ok || length < 1000) { Toast.makeText(this, "Video quá ngắn, hãy quay lâu hơn.", Toast.LENGTH_SHORT).show(); return; }
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
  }

  private void done(File file) {
    Intent result = new Intent();
    result.putExtra(EXTRA_VIDEO, file.getAbsolutePath());
    result.putExtra(EXTRA_STORY, story);
    setResult(RESULT_OK, result);
    finish();
  }

  private void finishCancelled() {
    setResult(RESULT_CANCELED);
    finish();
  }

  @Override
  public void onBackPressed() {
    if (reviewLayer.getVisibility() == View.VISIBLE) { reviewLayer.setVisibility(View.GONE); return; }
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
    TextView title = plain("Âm nhạc", 17, ink, true);
    title.setGravity(Gravity.CENTER);
    head.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    TextView off = plain(musicUrl != null || musicLocal != null ? "Bỏ nhạc" : "", 13, 0xffe0245e, true);
    off.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
    off.setOnClickListener(v -> { setMusic(null, null, null); dialog.dismiss(); });
    head.addView(off, new LinearLayout.LayoutParams(dp(60), -2));
    sheet.addView(head);
    LinearLayout search = new LinearLayout(this);
    search.setGravity(Gravity.CENTER_VERTICAL);
    search.setPadding(dp(14), 0, dp(14), 0);
    search.setBackground(round(soft, 999));
    search.addView(icon("search", muted), new LinearLayout.LayoutParams(dp(18), dp(18)));
    final EditText query = new EditText(this);
    query.setHint("Tìm bài hát hoặc nghệ sĩ");
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
    final LinearLayout bar = new LinearLayout(this);
    bar.setGravity(Gravity.CENTER_VERTICAL);
    bar.setPadding(dp(14), dp(10), dp(14), dp(14));
    bar.setVisibility(View.GONE);
    final TextView nowTitle = plain("", 15, ink, true), nowSub = plain("", 12, muted, false);
    LinearLayout now = new LinearLayout(this);
    now.setOrientation(LinearLayout.VERTICAL);
    now.addView(nowTitle);
    now.addView(nowSub);
    bar.addView(now, new LinearLayout.LayoutParams(0, -2, 1));
    TextView use = plain("Dùng bài này", 15, 0xffffffff, true);
    use.setGravity(Gravity.CENTER);
    use.setPadding(dp(20), 0, dp(20), 0);
    GradientDrawable ug = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6c47e0, PINK });
    ug.setCornerRadius(dp(999));
    use.setBackground(ug);
    bar.addView(use, new LinearLayout.LayoutParams(-2, dp(44)));
    sheet.addView(bar);
    final JSONArray[] tracks = { new JSONArray() };
    final String[] tab = { "lib" }, picked = { null, null, null }, playing = { null };
    final int[] shown = { 60 };
    final Runnable[] render = new Runnable[1];
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
      nowSub.setText(t[2].isEmpty() ? "Nhạc của bạn" : t[2]);
      bar.setVisibility(View.VISIBLE);
    };
    render[0] = () -> {
      list.removeAllViews();
      String q = query.getText().toString().trim().toLowerCase(Locale.ROOT);
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
        meta.addView(plain("Chọn nhạc trong máy", 15, ink, true));
        meta.addView(plain("MP3, M4A… chỉ dùng cho video của bạn", 12, muted, false));
        up.addView(meta);
        up.setOnClickListener(v -> {
          dialog.dismiss();
          Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
          pick.addCategory(Intent.CATEGORY_OPENABLE);
          pick.setType("audio/*");
          try { startActivityForResult(pick, 402); } catch (Exception e) { Toast.makeText(this, "Không mở được trình chọn nhạc.", Toast.LENGTH_SHORT).show(); }
        });
        list.addView(up);
        return;
      }
      int count = 0, total = 0;
      for (int i = 0; i < tracks[0].length(); i++) {
        final JSONObject t = tracks[0].optJSONObject(i);
        String name = t.optString("title"), artist = t.optString("artist");
        if (!q.isEmpty() && !(name + " " + artist).toLowerCase(Locale.ROOT).contains(q)) continue;
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
        TextView art = plain("♪", 22, 0xffffffff, true);
        art.setGravity(Gravity.CENTER);
        GradientDrawable ag = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { Color.HSVToColor(new float[] { hue, 0.65f, 0.85f }), Color.HSVToColor(new float[] { (hue + 50) % 360, 0.75f, 0.6f }) });
        ag.setCornerRadius(dp(10));
        art.setBackground(ag);
        row.addView(art, new LinearLayout.LayoutParams(dp(52), dp(52)));
        LinearLayout meta = new LinearLayout(this);
        meta.setOrientation(LinearLayout.VERTICAL);
        meta.setPadding(dp(12), 0, dp(8), 0);
        TextView tt = plain(name, 15, ink, true);
        tt.setSingleLine(true);
        tt.setEllipsize(android.text.TextUtils.TruncateAt.END);
        meta.addView(tt);
        TextView st = plain(artist.isEmpty() ? "Thư viện Kinnect" : artist, 12, muted, false);
        st.setSingleLine(true);
        st.setEllipsize(android.text.TextUtils.TruncateAt.END);
        meta.addView(st);
        row.addView(meta, new LinearLayout.LayoutParams(0, -2, 1));
        FrameLayout play = new FrameLayout(this);
        play.setBackground(round(sel ? 0xff6c47e0 : soft, 999));
        TextView glyph = plain(url.equals(playing[0]) ? "❚❚" : "▶", 13, sel ? 0xffffffff : ink, true);
        glyph.setGravity(Gravity.CENTER);
        play.addView(glyph, new FrameLayout.LayoutParams(-1, -1));
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
        TextView e = plain(q.isEmpty() ? "Thư viện chưa có bài nào." : "Không tìm thấy bài phù hợp.", 14, muted, false);
        e.setGravity(Gravity.CENTER);
        e.setPadding(0, dp(30), 0, dp(30));
        list.addView(e, new LinearLayout.LayoutParams(-1, -2));
      }
      if (total > shown[0]) {
        TextView more = plain("Xem thêm (" + (total - shown[0]) + " bài)", 14, ink, true);
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
    query.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence a, int b, int c, int d) {}
      public void onTextChanged(CharSequence a, int b, int c, int d) {}
      public void afterTextChanged(android.text.Editable e) { shown[0] = 60; render[0].run(); }
    });
    use.setOnClickListener(v -> { if (picked[0] != null) setMusic(picked[0], null, picked[1]); dialog.dismiss(); });
    dialog.setOnDismissListener(x -> stopPreview());
    drawTabs.run();
    render[0].run();
    dialog.setContentView(sheet);
    Window w = dialog.getWindow();
    if (w != null) {
      w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(0));
      w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, Math.round(getResources().getDisplayMetrics().heightPixels * 0.86f));
      w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.5f);
      w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    }
    dialog.show();
    if (music != null) music.pause();
    api.call("GET", "/api/music", null, (data, error, status) -> {
      if (isFinishing()) return;
      JSONArray list2 = data == null ? null : data.optJSONArray("tracks");
      if (list2 != null) tracks[0] = list2;
      render[0].run();
    });
  }

  private TextView plain(String s, float size, int color, boolean bold) {
    TextView t = new TextView(this);
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
    if (request == 402) setMusic(null, data.getData(), "Nhạc của bạn");
    if (request == 403) loadStill(data.getData(), "photo");
    if (request == 404) {
      Intent r = new Intent();
      r.setData(data.getData());
      r.putExtra(EXTRA_ACTION, "pick-video");
      setResult(RESULT_FIRST_USER, r);
      finish();
    }
  }

  private void setMusic(String url, Uri local, String title) {
    if (music != null) { music.release(); music = null; }
    musicUrl = url;
    musicLocal = local;
    musicLabel.setText(title == null ? "🎵  Thêm nhạc" : "🎵  " + title.replaceAll("\\s+", " ").trim());
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
      music.setOnErrorListener((p, w, e) -> { Toast.makeText(this, "Không phát được bài nhạc này.", Toast.LENGTH_SHORT).show(); return true; });
      music.prepareAsync();
    } catch (Exception e) {
      Toast.makeText(this, "Không phát được bài nhạc này.", Toast.LENGTH_SHORT).show();
      musicUrl = null;
      musicLocal = null;
    }
  }

  // ======================= Các view vẽ tay =======================
  /** Nút chụp: chế độ Ảnh = vòng trắng; Video = lõi đỏ, khi quay thu thành ô vuông và có vòng tiến trình. */
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
    protected void onDraw(Canvas c) {
      float w = getWidth(), h = getHeight(), cx = w / 2, cy = h / 2, r = Math.min(w, h) / 2;
      float stroke = r * 0.12f;
      p.setStyle(Paint.Style.STROKE);
      p.setStrokeWidth(stroke);
      p.setColor(0x66ffffff);
      c.drawCircle(cx, cy, r - stroke / 2, p);
      if (rec) {
        p.setShader(new SweepGradient(cx, cy, new int[] { 0xff7652e8, 0xffff4f9a, 0xff7652e8 }, null));
        c.drawArc(new RectF(stroke / 2, stroke / 2, w - stroke / 2, h - stroke / 2), -90, 360 * progress, false, p);
        p.setShader(null);
      } else if (mode.equals("photo")) {
        p.setColor(0xffffffff);
        c.drawCircle(cx, cy, r - stroke / 2, p);
      }
      p.setStyle(Paint.Style.FILL);
      if (mode.equals("photo")) {
        p.setColor(0xffffffff);
        c.drawCircle(cx, cy, r * 0.72f, p);
      } else if (rec) {
        p.setColor(0xffff3b5c);
        float s = r * 0.36f;
        c.drawRoundRect(new RectF(cx - s, cy - s, cx + s, cy + s), s * 0.3f, s * 0.3f, p);
      } else {
        p.setShader(new LinearGradient(0, 0, w, h, 0xffff4d6d, 0xffff3b8f, Shader.TileMode.CLAMP));
        c.drawCircle(cx, cy, r * 0.7f, p);
        p.setShader(null);
      }
    }
  }

  /** Lưới 3×3 và vùng che khi chọn tỉ lệ 3:4 hoặc 1:1. */
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
      if (ratio > 0) {
        float fh = ratio == 1 ? w * 4 / 3 : w;
        top = (h - fh) / 2;
        bottom = top + fh;
        p.setColor(0xcc000000);
        c.drawRect(0, 0, w, top, p);
        c.drawRect(0, bottom, w, h, p);
      }
      if (!grid) return;
      p.setColor(0x80ffffff);
      p.setStrokeWidth(1.5f);
      for (int i = 1; i < 3; i++) {
        c.drawLine(w * i / 3, top, w * i / 3, bottom, p);
        c.drawLine(0, top + (bottom - top) * i / 3, w, top + (bottom - top) * i / 3, p);
      }
    }
  }
}
