package app.kinnect.live;

import android.Manifest;
import android.app.*;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.hardware.camera2.*;
import android.media.*;
import android.net.Uri;
import android.graphics.BitmapFactory;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.io.File;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/**
 * Kinnect Studio: quay video ngắn bằng Camera2, bộ lọc màu, sticker bám khuôn mặt
 * (android.media.FaceDetector) và nhạc nền. Mọi khung hình được vẽ lại trên Canvas rồi
 * đưa vào MediaRecorder (VIDEO_SOURCE_SURFACE), nên hiệu ứng nằm luôn trong video.
 */
public final class StudioActivity extends Activity implements Choreographer.FrameCallback {
  static final String EXTRA_VIDEO = "video", EXTRA_STORY = "story", EXTRA_PHOTO = "photo";
  private boolean story;
  private Bitmap photo;
  private static final int W = 720, H = 1280, FW = 540, FH = 960;
  private static final String[][] FILTERS = {
    { "none", "Gốc" }, { "warm", "Ấm" }, { "cool", "Mát" }, { "bright", "Sáng da" },
    { "vivid", "Rực rỡ" }, { "mono", "Đen trắng" }, { "vintage", "Hoài cổ" },
  };
  private static final String[][] STICKERS = {
    { "none", "Không", "" }, { "glasses", "Kính", "😎" }, { "hearts", "Tim", "😍" },
    { "crown", "Vương miện", "👑" }, { "cat", "Mèo", "🐱" }, { "sparkle", "Lấp lánh", "✨" },
  };

  private FrameLayout root;
  private TextureView camera;
  private SurfaceView preview;
  private TextView timer, musicLabel, faceStatus;
  private Button shutter, modeButton;
  private LinearLayout chips;
  private CameraDevice device;
  private CameraCaptureSession session;
  private HandlerThread cameraThread;
  private Handler cameraHandler;
  private boolean front = true, recording = false, previewReady = false;
  private String filter = "none", sticker = "none";
  private int limitSeconds = 60;
  private Bitmap frame;
  private final Paint framePaint = new Paint(Paint.FILTER_BITMAP_FLAG);
  private final Paint emoji = new Paint(Paint.ANTI_ALIAS_FLAG);
  private MediaRecorder recorder;
  private Surface recorderSurface;
  private File output;
  private long startedAt;
  private int frameCount;
  private final ExecutorService faceWorker = Executors.newSingleThreadExecutor();
  private volatile boolean detecting;
  private volatile float[] face; // x, y (giữa hai mắt), khoảng cách mắt, góc nghiêng (độ) — toạ độ khung FW×FH
  private int missed;
  private MediaPlayer music;
  private String musicUrl;
  private Uri musicLocal;
  private final NativeApi api = NativeApi.shared;

  private int dp(int n) {
    return Math.round(n * getResources().getDisplayMetrics().density);
  }

  private Button pill(String text, Runnable click) {
    Button b = new Button(this);
    b.setText(text);
    b.setAllCaps(false);
    b.setTextColor(0xffffffff);
    b.setTextSize(13);
    GradientDrawable bg = new GradientDrawable();
    bg.setColor(0x66000000);
    bg.setCornerRadius(dp(999));
    b.setBackground(bg);
    b.setPadding(dp(14), 0, dp(14), 0);
    b.setMinWidth(0);
    b.setMinimumWidth(0);
    b.setOnClickListener(v -> click.run());
    return b;
  }

  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().setStatusBarColor(0xff000000);
    getWindow().setNavigationBarColor(0xff000000);
    emoji.setTextAlign(Paint.Align.CENTER);
    root = new FrameLayout(this);
    root.setBackgroundColor(0xff000000);
    setContentView(root);
    camera = new TextureView(this);
    preview = new SurfaceView(this);
    FrameLayout stage = new FrameLayout(this);
    stage.addView(camera, new FrameLayout.LayoutParams(-1, -1));
    stage.addView(preview, new FrameLayout.LayoutParams(-1, -1));
    int width = getResources().getDisplayMetrics().widthPixels;
    FrameLayout.LayoutParams stageParams = new FrameLayout.LayoutParams(width, width * 16 / 9, Gravity.CENTER);
    root.addView(stage, stageParams);
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

    // Thanh trên: đóng · nhạc nền · đổi camera
    LinearLayout top = new LinearLayout(this);
    top.setGravity(Gravity.CENTER_VERTICAL);
    top.setPadding(dp(12), dp(12), dp(12), 0);
    Button close = pill("✕", this::finishCancelled);
    close.setContentDescription("Đóng");
    top.addView(close, new LinearLayout.LayoutParams(dp(44), dp(44)));
    musicLabel = pill("🎵 Nhạc nền", this::chooseMusic);
    musicLabel.setSingleLine(true);
    musicLabel.setEllipsize(android.text.TextUtils.TruncateAt.END);
    LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(0, dp(40), 1);
    mp.setMargins(dp(10), 0, dp(10), 0);
    top.addView(musicLabel, mp);
    Button flip = pill("⟲", () -> {
      if (recording) return;
      front = !front;
      closeCamera();
      openCamera();
    });
    flip.setContentDescription("Đổi camera");
    top.addView(flip, new LinearLayout.LayoutParams(dp(44), dp(44)));
    root.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));

    faceStatus = new TextView(this);
    faceStatus.setTextColor(0xffffffff);
    faceStatus.setTextSize(13);
    faceStatus.setShadowLayer(4, 0, 1, 0xaa000000);
    FrameLayout.LayoutParams fs = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    fs.topMargin = dp(66);
    root.addView(faceStatus, fs);

    // Thanh dưới: hiệu ứng · thời lượng · nút quay · thư viện
    LinearLayout bottom = new LinearLayout(this);
    bottom.setOrientation(LinearLayout.VERTICAL);
    bottom.setPadding(0, 0, 0, dp(18));
    HorizontalScrollView scroller = new HorizontalScrollView(this);
    scroller.setHorizontalScrollBarEnabled(false);
    chips = new LinearLayout(this);
    chips.setPadding(dp(10), 0, dp(10), 0);
    scroller.addView(chips);
    bottom.addView(scroller, new LinearLayout.LayoutParams(-1, dp(46)));
    renderChips();
    timer = new TextView(this);
    timer.setTextColor(0xffffffff);
    timer.setGravity(Gravity.CENTER);
    timer.setTextSize(14);
    timer.setShadowLayer(4, 0, 1, 0xaa000000);
    bottom.addView(timer, new LinearLayout.LayoutParams(-1, dp(26)));
    LinearLayout actions = new LinearLayout(this);
    actions.setGravity(Gravity.CENTER);
    Button gallery = pill("Thư viện", () -> {
      if (recording) return;
      setResult(RESULT_FIRST_USER);
      finish();
    });
    actions.addView(gallery, new LinearLayout.LayoutParams(dp(96), dp(44)));
    shutter = new Button(this);
    GradientDrawable ring = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff8b5cf6, 0xffff4f9a });
    ring.setShape(GradientDrawable.OVAL);
    ring.setStroke(dp(5), 0xffffffff);
    shutter.setBackground(ring);
    shutter.setContentDescription("Bắt đầu quay");
    shutter.setOnClickListener(v -> { if (recording) stopRecording(); else startRecording(); });
    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(dp(78), dp(78));
    sp.setMargins(dp(26), 0, dp(26), 0);
    actions.addView(shutter, sp);
    modeButton = pill("60 giây", () -> {
      if (recording) return;
      limitSeconds = limitSeconds == 60 ? 15 : 60;
      modeButton.setText(limitSeconds + " giây");
    });
    actions.addView(modeButton, new LinearLayout.LayoutParams(dp(96), dp(44)));
    bottom.addView(actions);
    root.addView(bottom, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
    frame = Bitmap.createBitmap(FW, FH, Bitmap.Config.ARGB_8888);
    story = getIntent().getBooleanExtra(EXTRA_STORY, false);
    String photoUri = getIntent().getStringExtra(EXTRA_PHOTO);
    if (story) { limitSeconds = 15; modeButton.setText("15 giây"); modeButton.setEnabled(false); }
    if (photoUri != null) {
      // Ảnh làm nền: cắt vừa khung dọc, áp bộ lọc/sticker/nhạc rồi ghi thành video 15 giây.
      try {
        Bitmap src = BitmapFactory.decodeStream(getContentResolver().openInputStream(Uri.parse(photoUri)));
        Canvas c = new Canvas(frame);
        float scale = Math.max(FW / (float) src.getWidth(), FH / (float) src.getHeight());
        float w = src.getWidth() * scale, h = src.getHeight() * scale;
        c.drawBitmap(src, null, new RectF((FW - w) / 2, (FH - h) / 2, (FW + w) / 2, (FH + h) / 2), new Paint(Paint.FILTER_BITMAP_FLAG));
        photo = frame;
        front = false;
      } catch (Exception e) {
        Toast.makeText(this, "Không mở được ảnh.", Toast.LENGTH_LONG).show();
        finishCancelled();
        return;
      }
    }
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
      || checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED)
      requestPermissions(new String[] { Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO }, 401);
  }

  private void renderChips() {
    chips.removeAllViews();
    for (final String[] f : FILTERS) chips.addView(chip(f[1], filter.equals(f[0]), () -> { filter = f[0]; renderChips(); }));
    for (final String[] s : STICKERS) {
      if (s[0].equals("none")) continue;
      chips.addView(chip(s[2] + " " + s[1], sticker.equals(s[0]), () -> {
        sticker = sticker.equals(s[0]) ? "none" : s[0];
        face = null;
        faceStatus.setText(sticker.equals("none") ? "" : "Đưa khuôn mặt vào khung hình");
        renderChips();
      }));
    }
  }

  private Button chip(String text, boolean active, Runnable click) {
    Button b = pill(text, click);
    GradientDrawable bg = new GradientDrawable();
    bg.setCornerRadius(dp(999));
    bg.setColor(active ? 0xffffffff : 0x66000000);
    b.setBackground(bg);
    b.setTextColor(active ? 0xff1c1530 : 0xffffffff);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, dp(38));
    p.setMargins(dp(4), dp(4), dp(4), dp(4));
    b.setLayoutParams(p);
    return b;
  }

  @Override
  public void onRequestPermissionsResult(int code, String[] p, int[] r) {
    super.onRequestPermissionsResult(code, p, r);
    if (code == 401 && r.length > 0 && r[0] == PackageManager.PERMISSION_GRANTED) openCamera();
    else if (code == 401) {
      Toast.makeText(this, "Cần quyền camera và micro để quay video.", Toast.LENGTH_LONG).show();
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
    faceWorker.shutdownNow();
    if (music != null) { music.release(); music = null; }
    super.onDestroy();
  }

  private void openCamera() {
    if (photo != null || device != null || !camera.isAvailable()) return;
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
      manager.openCamera(chosen, new CameraDevice.StateCallback() {
        public void onOpened(CameraDevice d) { device = d; startPreview(); }
        public void onDisconnected(CameraDevice d) { d.close(); device = null; }
        public void onError(CameraDevice d, int e) { d.close(); device = null; runOnUiThread(() -> faceStatus.setText("Không mở được camera.")); }
      }, cameraHandler);
    } catch (Exception e) {
      faceStatus.setText("Không mở được camera.");
    }
  }

  private void startPreview() {
    try {
      SurfaceTexture texture = camera.getSurfaceTexture();
      texture.setDefaultBufferSize(1280, 720);
      final Surface surface = new Surface(texture);
      final CaptureRequest.Builder request = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD);
      request.addTarget(surface);
      device.createCaptureSession(Collections.singletonList(surface), new CameraCaptureSession.StateCallback() {
        public void onConfigured(CameraCaptureSession s) {
          session = s;
          try { s.setRepeatingRequest(request.build(), null, cameraHandler); } catch (Exception ignored) {}
        }
        public void onConfigureFailed(CameraCaptureSession s) {}
      }, cameraHandler);
    } catch (Exception e) {
      runOnUiThread(() -> faceStatus.setText("Không mở được camera."));
    }
  }

  private void closeCamera() {
    if (session != null) { session.close(); session = null; }
    if (device != null) { device.close(); device = null; }
  }

  // ===== Vẽ từng khung hình =====
  @Override
  public void doFrame(long nanos) {
    Choreographer.getInstance().postFrameCallback(this);
    if (photo == null) {
      if (!camera.isAvailable() || device == null) return;
      camera.getBitmap(frame);
    }
    frameCount++;
    if (!sticker.equals("none") && frameCount % 5 == 0 && !detecting) detectFace();
    if (previewReady) {
      Canvas c = null;
      try {
        c = preview.getHolder().lockCanvas();
        if (c != null) draw(c);
      } catch (Exception ignored) {
      } finally {
        if (c != null) try { preview.getHolder().unlockCanvasAndPost(c); } catch (Exception ignored) {}
      }
    }
    if (recording && recorderSurface != null) {
      try {
        Canvas c = recorderSurface.lockHardwareCanvas();
        try { draw(c); } finally { recorderSurface.unlockCanvasAndPost(c); }
      } catch (Exception ignored) {}
      long seconds = (SystemClock.elapsedRealtime() - startedAt) / 1000;
      timer.setText("● " + seconds + " / " + limitSeconds + " giây");
      if (seconds >= limitSeconds) stopRecording();
    }
  }

  private void draw(Canvas c) {
    float sx = c.getWidth() / (float) FW, sy = c.getHeight() / (float) FH;
    framePaint.setColorFilter(colorFilter());
    c.drawBitmap(frame, null, new Rect(0, 0, c.getWidth(), c.getHeight()), framePaint);
    float[] f = face;
    if (f == null || sticker.equals("none")) return;
    String glyph = "";
    for (String[] s : STICKERS) if (s[0].equals(sticker)) glyph = s[2];
    float x = f[0] * sx, y = f[1] * sy, eyes = f[2] * sx;
    c.save();
    c.rotate(f[3], x, y);
    if (sticker.equals("glasses")) { emoji.setTextSize(eyes * 2.3f); c.drawText("🕶", x, y + eyes * 0.45f, emoji); }
    else if (sticker.equals("crown")) { emoji.setTextSize(eyes * 2.4f); c.drawText(glyph, x, y - eyes * 1.5f, emoji); }
    else if (sticker.equals("cat")) {
      emoji.setTextSize(eyes * 1.4f);
      c.drawText(glyph, x - eyes * 1.3f, y - eyes * 1.4f, emoji);
      c.drawText(glyph, x + eyes * 1.3f, y - eyes * 1.4f, emoji);
    } else if (sticker.equals("hearts")) {
      emoji.setTextSize(eyes * 1.1f);
      for (int i = 0; i < 5; i++) {
        double a = (frameCount / 12.0) + i * Math.PI * 2 / 5;
        c.drawText("💖", x + (float) Math.cos(a) * eyes * 2.2f, y - eyes * 0.3f + (float) Math.sin(a) * eyes * 2.4f, emoji);
      }
    } else if (sticker.equals("sparkle")) {
      emoji.setTextSize(eyes * 0.9f);
      for (int i = 0; i < 6; i++) {
        double a = i * Math.PI / 3 + frameCount / 20.0;
        c.drawText(glyph, x + (float) Math.cos(a) * eyes * 2.6f, y + (float) Math.sin(a) * eyes * 3f, emoji);
      }
    }
    c.restore();
  }

  private ColorMatrixColorFilter colorFilter() {
    ColorMatrix m = new ColorMatrix();
    if (filter.equals("mono")) m.setSaturation(0);
    else if (filter.equals("vivid")) m.setSaturation(1.5f);
    else if (filter.equals("warm")) m.set(new float[] { 1.1f, 0, 0, 0, 12, 0, 1.02f, 0, 0, 4, 0, 0, 0.88f, 0, 0, 0, 0, 0, 1, 0 });
    else if (filter.equals("cool")) m.set(new float[] { 0.9f, 0, 0, 0, 0, 0, 1.0f, 0, 0, 4, 0, 0, 1.12f, 0, 12, 0, 0, 0, 1, 0 });
    else if (filter.equals("bright")) m.set(new float[] { 1.08f, 0, 0, 0, 18, 0, 1.06f, 0, 0, 16, 0, 0, 1.05f, 0, 16, 0, 0, 0, 1, 0 });
    else if (filter.equals("vintage")) {
      m.setSaturation(0.55f);
      ColorMatrix tint = new ColorMatrix(new float[] { 1, 0, 0, 0, 20, 0, 0.95f, 0, 0, 8, 0, 0, 0.8f, 0, 0, 0, 0, 0, 1, 0 });
      m.postConcat(tint);
    } else return null;
    return new ColorMatrixColorFilter(m);
  }

  private void detectFace() {
    detecting = true;
    final Bitmap small = Bitmap.createScaledBitmap(frame, FW / 2, FH / 2, true).copy(Bitmap.Config.RGB_565, false);
    faceWorker.execute(() -> {
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
        runOnUiThread(() -> {
          if (result == null) {
            if (++missed >= 4) { face = null; faceStatus.setText("Đưa khuôn mặt vào khung hình"); }
            return;
          }
          missed = 0;
          float[] old = face;
          if (old != null) for (int i = 0; i < 4; i++) result[i] = old[i] * 0.4f + result[i] * 0.6f;
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

  // ===== Quay video =====
  private void startRecording() {
    if (device == null && photo == null) return;
    boolean withMusic = musicUrl != null || musicLocal != null;
    try {
      output = new File(getCacheDir(), "kinnect-" + System.currentTimeMillis() + ".mp4");
      recorder = new MediaRecorder();
      if (!withMusic) recorder.setAudioSource(MediaRecorder.AudioSource.CAMCORDER);
      recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE);
      recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
      recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264);
      if (!withMusic) {
        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
        recorder.setAudioEncodingBitRate(96000);
        recorder.setAudioSamplingRate(44100);
      }
      recorder.setVideoSize(W, H);
      recorder.setVideoFrameRate(30);
      // ≤12 MB cho 60 giây: ~1.3 Mbps hình + 96 kbps tiếng.
      recorder.setVideoEncodingBitRate(1300000);
      recorder.setMaxFileSize(11L * 1024 * 1024);
      recorder.setOutputFile(output.getAbsolutePath());
      recorder.setOnInfoListener((r, what, extra) -> { if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) runOnUiThread(this::stopRecording); });
      recorder.prepare();
      recorderSurface = recorder.getSurface();
      recorder.start();
      recording = true;
      startedAt = SystemClock.elapsedRealtime();
      shutter.setContentDescription("Dừng quay");
      ((GradientDrawable) shutter.getBackground()).setColor(0xffff4f6d);
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
    timer.setText("");
    if (!ok || length < 1000) {
      Toast.makeText(this, "Video quá ngắn, hãy giữ quay lâu hơn.", Toast.LENGTH_SHORT).show();
      return;
    }
    if (musicUrl == null && musicLocal == null) { done(output); return; }
    final ProgressDialog progress = ProgressDialog.show(this, "Kinnect Studio", "Đang ghép nhạc nền…", true, false);
    final File video = output;
    new Thread(() -> {
      File mixed = new File(getCacheDir(), "kinnect-mix-" + System.currentTimeMillis() + ".mp4");
      String error = null;
      try {
        MusicMuxer.mux(this, video, musicUrl, musicLocal, api.jar(), mixed);
      } catch (Exception e) {
        error = "Không ghép được nhạc. Video sẽ không có nhạc nền.";
      }
      final String message = error;
      runOnUiThread(() -> {
        progress.dismiss();
        if (message != null) Toast.makeText(this, message, Toast.LENGTH_LONG).show();
        done(message == null ? mixed : video);
      });
    }, "kinnect-mux").start();
  }

  private void releaseRecorder() {
    if (recorder != null) { recorder.release(); recorder = null; }
    recorderSurface = null;
    ((GradientDrawable) shutter.getBackground()).setColor(0);
    shutter.setBackground(shutter.getBackground());
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

  // ===== Nhạc nền =====
  private void chooseMusic() {
    if (recording) return;
    api.call("GET", "/api/music", null, (data, error, status) -> {
      if (isFinishing()) return;
      final JSONArray tracks = data == null ? null : data.optJSONArray("tracks");
      int count = tracks == null ? 0 : tracks.length();
      final String[] names = new String[count + 2];
      names[0] = "Không dùng nhạc";
      for (int i = 0; i < count; i++) {
        JSONObject t = tracks.optJSONObject(i);
        names[i + 1] = "♪ " + t.optString("title") + (t.optString("artist").isEmpty() ? "" : " · " + t.optString("artist"));
      }
      names[count + 1] = "📁 Nhạc của bạn";
      new Sheet(this).setTitle("Nhạc nền").setItems(names, (d, which) -> {
        if (which == 0) setMusic(null, null, null);
        else if (which == names.length - 1) {
          Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
          pick.addCategory(Intent.CATEGORY_OPENABLE);
          pick.setType("audio/*");
          try { startActivityForResult(pick, 402); } catch (Exception e) { Toast.makeText(this, "Không mở được trình chọn nhạc.", Toast.LENGTH_SHORT).show(); }
        } else {
          JSONObject t = tracks.optJSONObject(which - 1);
          setMusic(api.origin() + t.optString("url"), null, t.optString("title"));
        }
      }).show();
    });
  }

  @Override
  protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (request == 402 && result == RESULT_OK && data != null && data.getData() != null) setMusic(null, data.getData(), "Nhạc của bạn");
  }

  private void setMusic(String url, Uri local, String title) {
    if (music != null) { music.release(); music = null; }
    musicUrl = url;
    musicLocal = local;
    musicLabel.setText(title == null ? "🎵 Nhạc nền" : "🎵 " + title);
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
      music.setOnPreparedListener(p -> { if (!recording) { p.start(); } });
      music.setOnErrorListener((p, w, e) -> { Toast.makeText(this, "Không phát được bài nhạc này.", Toast.LENGTH_SHORT).show(); return true; });
      music.prepareAsync();
    } catch (Exception e) {
      Toast.makeText(this, "Không phát được bài nhạc này.", Toast.LENGTH_SHORT).show();
      musicUrl = null;
      musicLocal = null;
    }
  }
}
