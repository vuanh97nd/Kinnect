package app.kinnect.live;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.*;
import android.media.*;
import android.net.Uri;
import android.os.*;
import android.text.TextUtils;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;

/**
 * CapCut-style editor: multi-clip timeline with transitions, keyframes, text/sticker/image/caption
 * layers, music and voice-over tracks. Preview and export share one renderer; export records the
 * rendered frames in real time and mixes every audio source offline afterwards.
 */
public final class MediaEditActivity extends Activity implements Choreographer.FrameCallback, TimelineView.Host {
  private static final int PICK_MUSIC = 10, SAVE = 11, PICK_CLIPS = 20, PICK_IMAGE = 21, MIC = 30;
  private static final int BG = 0xff0f0d15, PANEL = 0xff1a1724, CARD = 0xff272233, ACCENT = 0xff7c5cff, INK = 0xfff4f1fa, MUTED = 0xffa79fb8;

  private final ExecutorService worker = Executors.newSingleThreadExecutor(), loader = Executors.newSingleThreadExecutor(), faces = Executors.newSingleThreadExecutor();
  private EditorProject project = new EditorProject();
  private final ArrayDeque<EditorProject> undo = new ArrayDeque<>(), redo = new ArrayDeque<>();
  private String selKind; private int selId;
  private float playhead; private boolean playing; private long lastNanos, lastDraw;
  private boolean dirty, busy, closed, delivered, saveRequested;
  private File input, saveFile;
  private final Map<String, Bitmap> photos = new ConcurrentHashMap<>(), images = new ConcurrentHashMap<>();
  private final Map<String, Bitmap[]> thumbs = new ConcurrentHashMap<>();
  private final Map<Integer, float[]> faceOf = new ConcurrentHashMap<>();
  private volatile boolean detecting; private int tick;
  private final EditorRender render = new EditorRender();
  private Bitmap previewFrame;

  private FrameLayout stage; private SurfaceView preview; private TimelineView timeline;
  private TextView timeText, hint, qualityChip; private ImageView playButton, keyButton, undoButton, redoButton;
  private LinearLayout tools, sheet, sheetBody; private TextView sheetTitle; private HorizontalScrollView toolScroll;
  private FrameLayout exportCover; private TextView exportText; private ProgressBar exportBar;
  private final Runnable hideHint = () -> { if (hint != null) hint.animate().alpha(0).setDuration(250); };

  /** Two hidden decoders so the next clip is ready before a cut and both can play during a transition. */
  private final class Deck {
    TextureView view; Surface surface; MediaPlayer player; int clipId = -1; File file; boolean prepared, seeking; long pendingSeek = -1; Bitmap frame; float speed = 1;
  }
  private final Deck[] decks = { new Deck(), new Deck() };
  private static final class TrackPlayer { MediaPlayer mp; File file; boolean prepared; }
  private final Map<Integer, TrackPlayer> trackPlayers = new HashMap<>();

  // Export
  private MediaRecorder recorder; private Surface recordSurface; private File rendered; private Bitmap exportFrame;
  private boolean exporting, armed; private long exportStart, armWait, lastPost; private int exportGeneration; private Future<?> task;
  // Voice-over
  private MediaRecorder mic; private File micFile; private float micStart; private long micStarted; private boolean micRecording; private TextView micTimer; private View micButton;
  private AutoCaptions captions;

  private int dp(float x) { return Math.round(x * getResources().getDisplayMetrics().density); }

  @Override public void onCreate(Bundle state) {
    super.onCreate(state);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); getWindow().setStatusBarColor(BG); getWindow().setNavigationBarColor(BG);
    build();
    Uri uri = getIntent().getData(); if (uri == null) { finish(); return; }
    showHint(I18n.t("Đang mở…"), 0);
    loader.execute(() -> {
      try {
        File f = copyIn(uri, "kinnect-edit-input-"); input = f; EditorProject.Clip clip = probe(f);
        runOnUiThread(() -> { if (closed) return; project.clips.add(clip); afterClipsChanged(); thumbnails(clip); showHint(clip.video ? "Video · " + TimelineView.clock(clip.length()) : I18n.t("Ảnh · ") + clip.width + I18n.t("×") + clip.height, 1600); });
      } catch (Exception | OutOfMemoryError error) { runOnUiThread(() -> failure(I18n.t("Không mở được nội dung: ") + error.getMessage())); }
    });
    Choreographer.getInstance().postFrameCallback(this);
  }

  // ---------- Loading media ----------
  private File copyIn(Uri uri, String prefix) throws IOException {
    File f = File.createTempFile(prefix, ".media", getCacheDir());
    try (InputStream in = getContentResolver().openInputStream(uri); OutputStream out = new FileOutputStream(f)) {
      if (in == null) throw new IOException(I18n.t("Không đọc được tệp.")); byte[] b = new byte[65536]; int n;
      while ((n = in.read(b)) != -1) { if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException(); out.write(b, 0, n); }
    }
    return f;
  }

  private static Bitmap decodePhoto(File f, int maxSide) throws IOException {
    BitmapFactory.Options o = new BitmapFactory.Options(); o.inJustDecodeBounds = true; BitmapFactory.decodeFile(f.getPath(), o);
    if (o.outWidth <= 0 || o.outHeight <= 0) return null;
    o.inJustDecodeBounds = false; o.inSampleSize = 1; while (Math.max(o.outWidth, o.outHeight) / o.inSampleSize > maxSide) o.inSampleSize *= 2;
    Bitmap bmp = BitmapFactory.decodeFile(f.getPath(), o); if (bmp == null) throw new IOException(I18n.t("Không mở được ảnh."));
    int orientation = new ExifInterface(f.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1); Matrix m = new Matrix();
    if (orientation == 3) m.postRotate(180); else if (orientation == 6) m.postRotate(90); else if (orientation == 8) m.postRotate(270);
    else if (orientation == 2) m.postScale(-1, 1); else if (orientation == 4) m.postScale(1, -1);
    else if (orientation == 5) { m.postRotate(90); m.postScale(-1, 1); } else if (orientation == 7) { m.postRotate(270); m.postScale(-1, 1); }
    if (!m.isIdentity()) { Bitmap rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.getWidth(), bmp.getHeight(), m, true); if (rotated != bmp) bmp.recycle(); bmp = rotated; }
    return bmp;
  }

  /** Reads size/duration; photos are decoded once and kept for preview and export. */
  private EditorProject.Clip probe(File f) throws Exception {
    EditorProject.Clip c = new EditorProject.Clip(); c.file = f; c.fx.beautyOn = false;
    Bitmap photo = decodePhoto(f, 2048);
    if (photo != null) { photos.put(f.getAbsolutePath(), photo); c.video = false; c.width = photo.getWidth(); c.height = photo.getHeight(); c.source = 3600; c.in = 0; c.out = 3; return c; }
    MediaMetadataRetriever r = new MediaMetadataRetriever();
    try {
      r.setDataSource(f.getPath());
      int w = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)), h = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT));
      int rot = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)); long ms = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION));
      if (w <= 0 || h <= 0 || ms <= 0) throw new IOException(I18n.t("Tệp không phải ảnh hoặc video được hỗ trợ."));
      if (rot % 180 != 0) { int t = w; w = h; h = t; }
      c.video = true; c.width = w; c.height = h; c.source = ms / 1000f; c.in = 0; c.out = c.source;
      c.hasAudio = "yes".equals(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO));
      return c;
    } finally { try { r.release(); } catch (Exception ignored) {} }
  }
  private static int parse(String v) { try { return v == null ? 0 : Integer.parseInt(v.trim()); } catch (NumberFormatException e) { return 0; } }

  private void thumbnails(EditorProject.Clip clip) {
    final File file = clip.file; final boolean video = clip.video; final float source = clip.source; final int height = dp(54);
    if (thumbs.containsKey(file.getAbsolutePath())) return;
    loader.execute(() -> {
      try {
        if (!video) { Bitmap p = photos.get(file.getAbsolutePath()); if (p == null) return; thumbs.put(file.getAbsolutePath(), new Bitmap[] { Bitmap.createScaledBitmap(p, Math.max(2, height * p.getWidth() / p.getHeight()), height, true) }); }
        else {
          MediaMetadataRetriever r = new MediaMetadataRetriever();
          try {
            r.setDataSource(file.getPath()); int n = Math.max(4, Math.min(30, Math.round(source))); Bitmap[] out = new Bitmap[n];
            for (int i = 0; i < n && !closed; i++) {
              long at = (long) (source * 1e6 * (i + .5f) / n); Bitmap raw = Build.VERSION.SDK_INT >= 27 ? r.getScaledFrameAtTime(at, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, height * 2, height * 2) : r.getFrameAtTime(at, MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
              if (raw == null) continue; out[i] = Bitmap.createScaledBitmap(raw, Math.max(2, height * raw.getWidth() / raw.getHeight()), height, true); if (out[i] != raw) raw.recycle();
              for (int k = 0; k < n; k++) if (out[k] == null) out[k] = out[i];
              thumbs.put(file.getAbsolutePath(), out.clone()); if (timeline != null) timeline.postInvalidate();
            }
          } finally { try { r.release(); } catch (Exception ignored) {} }
        }
        if (timeline != null) timeline.postInvalidate();
      } catch (Exception | OutOfMemoryError ignored) {}
    });
  }

  private void failure(String message) {
    if (closed) return; busy = false;
    new AlertDialog.Builder(this).setMessage(message).setPositiveButton(I18n.t("Dùng bản gốc"), (d, w) -> { if (input != null) deliver(input); else finish(); }).setNegativeButton(I18n.t("Đóng"), (d, w) -> finish()).show();
  }

  // ---------- Layout ----------
  private Drawable editorIcon(String name, int tint) {
    return EditorIcons.drawable(this,name,tint);
  }

  private ImageView iconButton(String name, String description, Runnable action) {
    ImageView b = new ImageView(this); b.setImageDrawable(editorIcon(name, INK)); b.setContentDescription(description); b.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
    b.setPadding(dp(11), dp(11), dp(11), dp(11)); b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffffff), null, oval()));
    b.setOnClickListener(v -> { if (!busy) action.run(); }); return b;
  }

  private static ShapeDrawable oval() { return new ShapeDrawable(new android.graphics.drawable.shapes.OvalShape()); }
  private GradientDrawable rounded(int color, float radius) { GradientDrawable g = new GradientDrawable(); g.setColor(color); g.setCornerRadius(dp(radius)); return g; }

  private TextView label(String text, float size, int color) { TextView t = new KinnectText(this); t.setText(text); t.setTextSize(size); t.setTextColor(color); return t; }

  private boolean proApplied;private EditorProject proBefore;
  private void build() {
    LinearLayout root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(BG); setContentView(root);
    root.setOnApplyWindowInsetsListener((v, insets) -> { v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom()); return insets; });
    root.requestApplyInsets();

    LinearLayout top = new LinearLayout(this); top.setGravity(Gravity.CENTER_VERTICAL); top.setPadding(dp(4), 0, dp(10), 0);
    top.addView(iconButton("close",I18n.t("Thoát"),this::requestExit),new LinearLayout.LayoutParams(dp(46),dp(46)));
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    qualityChip = label("1080p", 13, INK); qualityChip.setTypeface(Typeface.DEFAULT_BOLD); qualityChip.setGravity(Gravity.CENTER); qualityChip.setPadding(dp(12), 0, dp(12), 0);
    qualityChip.setCompoundDrawablesRelative(null, null, small(editorIcon("chevron_down", MUTED), 14), null); qualityChip.setCompoundDrawablePadding(dp(4));
    qualityChip.setBackground(rounded(CARD, 16)); qualityChip.setOnClickListener(v -> { if (!busy) qualitySheet(); });
    top.addView(qualityChip, new LinearLayout.LayoutParams(-2, dp(32)));
    top.addView(iconButton("save", I18n.t("Lưu về máy"), () -> export(true)), new LinearLayout.LayoutParams(dp(46), dp(46)));
    TextView post = label(I18n.t("Đăng"), 14, Color.WHITE); post.setTypeface(Typeface.DEFAULT_BOLD); post.setGravity(Gravity.CENTER); post.setPadding(dp(16), 0, dp(16), 0);
    post.setBackground(new RippleDrawable(ColorStateList.valueOf(0x44ffffff), rounded(ACCENT, 17), null)); post.setOnClickListener(v -> { if (!busy) export(false); });
    LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(-2, dp(34)); pp.leftMargin = dp(4); top.addView(post, pp);
    root.addView(top, new LinearLayout.LayoutParams(-1, dp(52)));

    stage = new FrameLayout(this); stage.setBackgroundColor(0xff050408); root.addView(stage, new LinearLayout.LayoutParams(-1, 0, 1));
    for (Deck d : decks) {
      d.view = new TextureView(this); d.view.setAlpha(.01f); stage.addView(d.view, new FrameLayout.LayoutParams(2, 2));
      d.view.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
        public void onSurfaceTextureAvailable(SurfaceTexture s, int w, int h) {} public void onSurfaceTextureSizeChanged(SurfaceTexture s, int w, int h) {}
        public boolean onSurfaceTextureDestroyed(SurfaceTexture s) { return true; } public void onSurfaceTextureUpdated(SurfaceTexture s) {}
      });
    }
    preview = new SurfaceView(this); stage.addView(preview, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
    stage.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> fit());
    preview.setOnTouchListener(this::previewTouch);
    hint = label("", 12, Color.WHITE); hint.setPadding(dp(12), dp(6), dp(12), dp(6)); hint.setBackground(rounded(0xcc000000, 14)); hint.setAlpha(0);
    FrameLayout.LayoutParams hp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL); hp.topMargin = dp(10); stage.addView(hint, hp);
    exportCover = new FrameLayout(this); exportCover.setBackgroundColor(0xcc0f0d15); exportCover.setVisibility(View.GONE); exportCover.setClickable(true);
    LinearLayout ex = new LinearLayout(this); ex.setOrientation(LinearLayout.VERTICAL); ex.setGravity(Gravity.CENTER);
    exportText = label(I18n.t("Đang xuất…"), 15, INK); exportText.setTypeface(Typeface.DEFAULT_BOLD); exportText.setGravity(Gravity.CENTER); ex.addView(exportText);
    exportBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal); exportBar.setMax(100); exportBar.setProgressTintList(ColorStateList.valueOf(ACCENT));
    LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(dp(220), dp(10)); bp.topMargin = dp(12); ex.addView(exportBar, bp);
    TextView keep = label(I18n.t("Giữ màn hình mở cho đến khi xong"), 12, MUTED); keep.setPadding(0, dp(10), 0, dp(14)); ex.addView(keep);
    TextView cancel = label(I18n.t("Hủy"), 14, INK); cancel.setGravity(Gravity.CENTER); cancel.setBackground(rounded(CARD, 18)); cancel.setOnClickListener(v -> cancelExport(I18n.t("Đã hủy xuất.")));
    ex.addView(cancel, new LinearLayout.LayoutParams(dp(110), dp(38)));
    exportCover.addView(ex, new FrameLayout.LayoutParams(-1, -1)); stage.addView(exportCover, new FrameLayout.LayoutParams(-1, -1));

    LinearLayout controls = new LinearLayout(this); controls.setGravity(Gravity.CENTER_VERTICAL); controls.setPadding(dp(12), 0, dp(6), 0);
    timeText = label("00:00 / 00:00", 12, INK); timeText.setTypeface(Typeface.MONOSPACE); controls.addView(timeText, new LinearLayout.LayoutParams(0, -2, 1));
    playButton = iconButton("play", I18n.t("Phát hoặc tạm dừng"), this::togglePlay); controls.addView(playButton, new LinearLayout.LayoutParams(dp(44), dp(44)));
    LinearLayout right = new LinearLayout(this); right.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
    keyButton = iconButton("keyframe", I18n.t("Thêm hoặc xóa khung hình chính"), this::toggleKey); right.addView(keyButton, new LinearLayout.LayoutParams(dp(40), dp(40)));
    undoButton = iconButton("undo", I18n.t("Hoàn tác"), () -> history(false)); right.addView(undoButton, new LinearLayout.LayoutParams(dp(40), dp(40)));
    redoButton = iconButton("redo", I18n.t("Làm lại"), () -> history(true)); right.addView(redoButton, new LinearLayout.LayoutParams(dp(40), dp(40)));
    ImageView compare = iconButton("compare", I18n.t("Giữ để xem bản gốc"), () -> {});
    compare.setOnTouchListener((v, e) -> { boolean down = e.getActionMasked() == MotionEvent.ACTION_DOWN || e.getActionMasked() == MotionEvent.ACTION_MOVE; for (EditorProject.Clip c : project.clips) c.fx.compare = down && !busy; if (e.getActionMasked() == MotionEvent.ACTION_UP) v.performClick(); return true; });
    right.addView(compare, new LinearLayout.LayoutParams(dp(40), dp(40)));
    controls.addView(right, new LinearLayout.LayoutParams(0, -2, 1));
    root.addView(controls, new LinearLayout.LayoutParams(-1, dp(46)));

    timeline = new TimelineView(this, this);
    ScrollView lanes = new ScrollView(this); lanes.setVerticalScrollBarEnabled(false); lanes.setBackgroundColor(0xff15121d); lanes.addView(timeline, new FrameLayout.LayoutParams(-1, -2));
    root.addView(lanes, new LinearLayout.LayoutParams(-1, dp(178)));

    sheet = new LinearLayout(this); sheet.setOrientation(LinearLayout.VERTICAL); sheet.setBackgroundColor(PANEL); sheet.setVisibility(View.GONE);
    LinearLayout head = new LinearLayout(this); head.setGravity(Gravity.CENTER_VERTICAL); head.setPadding(dp(16), 0, dp(4), 0);
    sheetTitle = label("", 15, INK); sheetTitle.setTypeface(Typeface.DEFAULT_BOLD); head.addView(sheetTitle, new LinearLayout.LayoutParams(0, -2, 1));
    head.addView(iconButton("check", "Xong", this::closeSheet), new LinearLayout.LayoutParams(dp(46), dp(46)));
    sheet.addView(head, new LinearLayout.LayoutParams(-1, dp(46)));
    ScrollView body = new ScrollView(this); sheetBody = new LinearLayout(this); sheetBody.setOrientation(LinearLayout.VERTICAL); sheetBody.setPadding(dp(16), 0, dp(16), dp(14));
    body.addView(sheetBody); sheet.addView(body, new LinearLayout.LayoutParams(-1, 0, 1));
    root.addView(sheet, new LinearLayout.LayoutParams(-1, dp(270)));

    tools = new LinearLayout(this); tools.setGravity(Gravity.CENTER_VERTICAL); tools.setPadding(dp(4), 0, dp(4), 0);
    toolScroll = new HorizontalScrollView(this); toolScroll.setHorizontalScrollBarEnabled(false); toolScroll.setBackgroundColor(PANEL); toolScroll.addView(tools);
    root.addView(toolScroll, new LinearLayout.LayoutParams(-1, dp(72)));
    refreshTools();
  }

  private Drawable small(Drawable d, int size) { if (d != null) d.setBounds(0, 0, dp(size), dp(size)); return d; }

  private void fit() {
    if (preview == null || stage.getWidth() == 0) return; float ratio = project.outputAspect();
    int h = Math.min(stage.getHeight(), Math.round(stage.getWidth() / ratio)), w = Math.round(h * ratio);
    FrameLayout.LayoutParams old = (FrameLayout.LayoutParams) preview.getLayoutParams();
    if (old.width != w || old.height != h) preview.setLayoutParams(new FrameLayout.LayoutParams(w, h, Gravity.CENTER));
  }

  private void showHint(String text, long ms) {
    hint.removeCallbacks(hideHint); hint.setText(text); hint.animate().cancel(); hint.setAlpha(1); if (ms > 0) hint.postDelayed(hideHint, ms);
  }

  // ---------- Toolbar ----------
  private View tool(String iconName, String text, boolean active, Runnable action) {
    LinearLayout item = new LinearLayout(this); item.setOrientation(LinearLayout.VERTICAL); item.setGravity(Gravity.CENTER);
    item.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22ffffff), null, rounded(Color.WHITE, 12)));
    ImageView image = new ImageView(this); image.setImageDrawable(editorIcon(iconName, active ? ACCENT : INK)); item.addView(image, new LinearLayout.LayoutParams(dp(21), dp(21)));
    TextView name = label(text, 10.5f, active ? ACCENT : 0xffd9d3e6); name.setGravity(Gravity.CENTER); name.setSingleLine(true); name.setEllipsize(TextUtils.TruncateAt.END);
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2); lp.topMargin = dp(5); item.addView(name, lp);
    item.setContentDescription(text); item.setOnClickListener(v -> { if (!busy) action.run(); });
    tools.addView(item, new LinearLayout.LayoutParams(dp(66), dp(64)));
    return item;
  }

  private void divider() { View v = new View(this); v.setBackgroundColor(0x33ffffff); LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(1), dp(34)); lp.leftMargin = lp.rightMargin = dp(4); tools.addView(v, lp); }

  private void refreshTools() {
    if (tools == null) return; tools.removeAllViews();
    EditorProject.Clip clip = "clip".equals(selKind) ? project.clip(selId) : null; EditorProject.Layer layer = "layer".equals(selKind) ? project.layer(selId) : null; EditorProject.Track track = "track".equals(selKind) ? project.track(selId) : null;
    if (clip == null && layer == null && track == null) { selKind = null;
      tool("cut", I18n.t("Chỉnh sửa"), false, () -> { int i = project.clipAt(playhead); if (i >= 0) select("clip", project.clips.get(i).id); });
      tool("music", I18n.t("Âm thanh"), false, this::audioSheet);
      tool("text", I18n.t("Chữ"), false, this::addText);
      tool("sticker", I18n.t("Nhãn dán"), false, this::stickerSheet);
      tool("layer", I18n.t("Lớp phủ"), false, () -> pick(PICK_IMAGE, "image/*", false));
      tool("caption", I18n.t("Phụ đề tự động"), false, this::captionSheet);
      tool("filter", I18n.t("Bộ lọc"), false, () -> onCurrentClip(() -> fxSheet("filter")));
      tool("color", I18n.t("Điều chỉnh"), false, () -> onCurrentClip(this::adjustSheet));
      tool("beauty", I18n.t("Làm đẹp"), false, () -> onCurrentClip(() -> fxSheet("beauty")));
      tool("format", I18n.t("Tỉ lệ"), false, this::formatSheet);
      tool("background", I18n.t("Nền"), false, this::backgroundSheet);
      tool("add", I18n.t("Thêm clip"), false, this::addClip);
    } else {
      tool("back", I18n.t("Quay lại"), false, () -> select(null, 0)); divider();
      if (clip != null) {
        tool("split", I18n.t("Tách"), false, this::split);
        tool("speed", I18n.t("Tốc độ"), clip.speed != 1, this::speedSheet);
        tool("volume", I18n.t("Âm lượng"), clip.volume != 1, this::volumeSheet);
        tool("move", I18n.t("Vị trí"), !clip.keys.isEmpty(), this::transformSheet);
        tool("rotate", "Xoay", clip.turn != 0, () -> { remember(); clip.turn = (clip.turn + 90) % 360; showHint("Xoay " + clip.turn + "°", 1000); });
        tool("flip", I18n.t("Lật"), clip.fx.flipImage, () -> { remember(); clip.fx.flipImage = !clip.fx.flipImage; refreshTools(); });
        tool("filter", I18n.t("Bộ lọc"), !clip.fx.filter.equals("none"), () -> fxSheet("filter"));
        tool("color", I18n.t("Điều chỉnh"), false, this::adjustSheet);
        tool("beauty", I18n.t("Làm đẹp"), clip.fx.beautyOn, () -> fxSheet("beauty"));
        tool("sticker", I18n.t("Hiệu ứng mặt"), !clip.fx.sticker.equals("none"), () -> fxSheet("sticker"));
        tool("transition", I18n.t("Chuyển cảnh"), false, () -> { int i = project.indexOf(clip.id); transitionSheet(i + 1 < project.clips.size() ? i + 1 : i); });
        tool("move_left", I18n.t("Dời trước"), false, () -> reorder(-1));
        tool("move_right", I18n.t("Dời sau"), false, () -> reorder(1));
        tool("duplicate", I18n.t("Nhân bản"), false, this::duplicate);
        tool("delete", I18n.t("Xóa"), false, this::delete);
      } else if (layer != null) {
        boolean words = layer.kind.equals("text") || layer.kind.equals("caption");
        if (words) { tool("text", I18n.t("Sửa chữ"), false, () -> editText(layer, false)); tool("font", I18n.t("Kiểu chữ"), false, this::styleSheet); }
        tool("animation", I18n.t("Hoạt ảnh"), !layer.animIn.equals("none") || !layer.animOut.equals("none"), this::animationSheet);
        tool("move", I18n.t("Vị trí"), !layer.keys.isEmpty(), this::transformSheet);
        tool("split", I18n.t("Tách"), false, this::split);
        tool("duplicate", I18n.t("Nhân bản"), false, this::duplicate);
        tool("delete", I18n.t("Xóa"), false, this::delete);
      } else {
        tool("volume", I18n.t("Âm lượng"), track.gain != 1, this::volumeSheet);
        tool("fade", I18n.t("Mờ dần"), track.fadeIn > 0 || track.fadeOut > 0, this::fadeSheet);
        tool("split", I18n.t("Tách"), false, this::split);
        tool("duplicate", I18n.t("Nhân bản"), false, this::duplicate);
        tool("delete", I18n.t("Xóa"), false, this::delete);
      }
    }
    tool("sparkles","Studio Pro",proApplied,this::proTemplates);
    updateButtons();
  }

  private void proTemplates(){
    NativeApi.shared.call("GET","/api/store",null,(catalog,error,status)->{if(closed)return;if(error!=null){showHint(error,2200);return;}boolean owned=catalog.optBoolean("studioProFree");org.json.JSONArray ids=catalog.optJSONArray("owned");for(int i=0;ids!=null&&i<ids.length();i++)if(ids.optString(i).equals("kinnect_studio_pro"))owned=true;
      if(!owned){new Sheet(this).setTitle("Studio Pro").setMessage(I18n.t("Ba mẫu dựng video Aurora, Travel và Cinema. Các công cụ chỉnh sửa hiện có vẫn miễn phí.")).setPositiveButton(I18n.t("Xem cửa hàng"),(d,w)->startActivity(new Intent(this,StoreActivity.class))).setNegativeButton(I18n.t("Đóng"),null).show();return;}
      new Sheet(this).setTitle("Studio Pro").setItemIcons(new String[]{"wand","map_pin","clapperboard","trash"}).setItems(new String[]{"Aurora","Travel","Cinema",I18n.t("Gỡ mẫu Pro")},(d,index)->{if(project.clips.isEmpty())return;if(index==3){if(proBefore!=null){remember();project=proBefore.copy();proBefore=null;proApplied=false;afterClipsChanged();}return;}if(proBefore==null)proBefore=project.copy();remember();proApplied=true;for(EditorProject.Clip clip:project.clips){clip.fx.filter=index==0?"lavender":index==1?"golden":"cinema";clip.fx.intensity=index==0?.78f:index==1?.65f:.85f;clip.transition=index==0?"fade":index==1?"slideLeft":"black";clip.transitionLength=index==2?.35f:.5f;clip.fx.contrastLevel=index==2?1.12f:1.04f;clip.fx.saturation=index==1?1.12f:1f;}afterClipsChanged();showHint(I18n.t("Đã áp dụng mẫu Studio Pro."),1800);}).show();
    });
  }

  private void onCurrentClip(Runnable then) { int i = project.clipAt(playhead); if (i < 0) return; select("clip", project.clips.get(i).id); then.run(); }

  private void updateButtons() {
    if (undoButton == null) return;
    undoButton.setAlpha(undo.isEmpty() ? .35f : 1); redoButton.setAlpha(redo.isEmpty() ? .35f : 1);
    EditorProject.Item item = selectedItem(); float local = localTime(); boolean onKey = item != null && item.keyAt(local) != null;
    keyButton.setVisibility(item != null ? View.VISIBLE : View.INVISIBLE); keyButton.setImageDrawable(editorIcon("keyframe", onKey ? 0xffffd45c : INK));
    playButton.setImageDrawable(editorIcon(playing ? "pause" : "play", INK));
    if (qualityChip != null) qualityChip.setText(project.exportSide + "p");
  }

  // ---------- Selection & history ----------
  @Override public EditorProject project() { return project; }
  @Override public float playhead() { return playhead; }
  @Override public String selectedKind() { return selKind; }
  @Override public int selectedId() { return selId; }
  @Override public Bitmap[] thumbs(EditorProject.Clip clip) { return thumbs.get(clip.file.getAbsolutePath()); }
  @Override public void addClip() { pick(PICK_CLIPS, "*/*", true); }
  @Override public void transition(int clipIndex) { if (clipIndex > 0 && clipIndex < project.clips.size()) { select("clip", project.clips.get(clipIndex).id); transitionSheet(clipIndex); } }
  @Override public void beginChange() { remember(); }
  @Override public void changed() { dirty = true; timeline.invalidate(); updateButtons(); }
  @Override public void scrub(float t, boolean done) { if (playing) { playing = false; } playhead = Math.max(0, Math.min(project.duration(), t)); updateTime(); updateButtons(); }

  @Override public void select(String kind, int id) {
    selKind = kind; selId = id; closeSheet(); refreshTools(); timeline.invalidate();
    // Move the playhead inside the item so edits and keyframes apply where the user is looking.
    EditorProject.Item item = selectedItem();
    if (item instanceof EditorProject.Layer) { EditorProject.Layer l = (EditorProject.Layer) item; if (playhead < l.start || playhead > l.start + l.length) scrub(l.start + .01f, true); }
    else if (item instanceof EditorProject.Clip) { int i = project.indexOf(id); float s = project.starts()[i]; if (playhead < s || playhead > s + ((EditorProject.Clip) item).length()) scrub(s + .01f, true); }
    else if ("track".equals(kind)) { EditorProject.Track t = project.track(id); if (t != null && (playhead < t.start || playhead > t.start + t.length)) scrub(t.start + .01f, true); }
  }

  private EditorProject.Item selectedItem() { return "clip".equals(selKind) ? project.clip(selId) : "layer".equals(selKind) ? project.layer(selId) : null; }
  private float localTime() {
    if ("clip".equals(selKind)) { int i = project.indexOf(selId); if (i < 0) return 0; return Math.max(0, Math.min(project.clips.get(i).length(), playhead - project.starts()[i])); }
    if ("layer".equals(selKind)) { EditorProject.Layer l = project.layer(selId); if (l == null) return 0; return Math.max(0, Math.min(l.length, playhead - l.start)); }
    return 0;
  }

  private void remember() { undo.addLast(project.copy()); if (undo.size() > 60) undo.removeFirst(); redo.clear(); dirty = true; updateButtons(); }

  private void history(boolean forward) {
    ArrayDeque<EditorProject> from = forward ? redo : undo, to = forward ? undo : redo; if (from.isEmpty()) return;
    to.addLast(project.copy()); project = from.removeLast(); dirty = true;
    if (selectedItem() == null && !("track".equals(selKind) && project.track(selId) != null)) selKind = null;
    playhead = Math.min(playhead, project.duration()); closeSheet(); afterClipsChanged(); showHint(forward ? I18n.t("Làm lại") : I18n.t("Hoàn tác"), 800);
  }

  private void afterClipsChanged() { fit(); refreshTools(); timeline.requestLayout(); timeline.invalidate(); updateTime(); }

  private void updateTime() { if (timeText != null) timeText.setText(TimelineView.clock(playhead) + " / " + TimelineView.clock(project.duration())); }

  private void togglePlay() {
    if (project.clips.isEmpty()) return;
    if (!playing && playhead >= project.duration() - .05f) playhead = 0;
    playing = !playing; updateButtons();
  }

  private void toggleKey() {
    EditorProject.Item item = selectedItem(); if (item == null) return; remember(); float local = localTime(); EditorProject.Key k = item.keyAt(local);
    if (k != null) { item.keys.remove(k); showHint(I18n.t("Đã xóa khung hình chính"), 1000); }
    else { item.addKey(local); showHint(item.keys.size() == 1 ? I18n.t("Đã thêm khung hình chính. Dời đầu phát rồi chỉnh vị trí/kích thước để tạo chuyển động") : I18n.t("Đã thêm khung hình chính"), item.keys.size() == 1 ? 3200 : 1000); }
    refreshTools(); timeline.invalidate();
  }

  // ---------- Sheets ----------
  private LinearLayout openSheet(String title) {
    sheetTitle.setText(title); sheetBody.removeAllViews(); sheet.setVisibility(View.VISIBLE); toolScroll.setVisibility(View.GONE); return sheetBody;
  }
  private void closeSheet() { if (micRecording) stopMic(); if (sheet == null) return; sheet.setVisibility(View.GONE); toolScroll.setVisibility(View.VISIBLE); refreshTools(); }

  private TextView section(LinearLayout box, String text) { TextView t = label(text, 12, MUTED); t.setPadding(0, dp(10), 0, dp(6)); box.addView(t); return t; }
  private TextView note(LinearLayout box, String text) { TextView t = label(text, 12, MUTED); t.setPadding(0, dp(8), 0, dp(4)); t.setLineSpacing(dp(2), 1); box.addView(t); return t; }

  interface Change { void set(float v); }
  interface Format { String show(float v); }

  private void slider(LinearLayout box, String title, float min, float max, float value, Format format, Change change) {
    LinearLayout row = new LinearLayout(this); row.setGravity(Gravity.CENTER_VERTICAL);
    TextView name = label(title, 13, INK); row.addView(name, new LinearLayout.LayoutParams(dp(86), -2));
    SeekBar bar = new SeekBar(this); bar.setMax(1000); bar.setProgress(Math.round((value - min) / (max - min) * 1000)); bar.setContentDescription(title);
    bar.setProgressTintList(ColorStateList.valueOf(ACCENT)); bar.setThumbTintList(ColorStateList.valueOf(Color.WHITE)); bar.setProgressBackgroundTintList(ColorStateList.valueOf(0x55ffffff));
    TextView shown = label(format.show(value), 12, MUTED); shown.setGravity(Gravity.END);
    bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
      public void onProgressChanged(SeekBar b, int p, boolean user) { if (!user) return; float v = min + (max - min) * p / 1000f; change.set(v); shown.setText(format.show(v)); dirty = true; timeline.invalidate(); }
      public void onStartTrackingTouch(SeekBar b) { remember(); playing = false; updateButtons(); }
      public void onStopTrackingTouch(SeekBar b) { refreshKeyButton(); }
    });
    row.addView(bar, new LinearLayout.LayoutParams(0, dp(40), 1)); row.addView(shown, new LinearLayout.LayoutParams(dp(50), -2)); box.addView(row);
  }
  private void refreshKeyButton() { updateButtons(); timeline.invalidate(); }

  private static Format percent() { return v -> Math.round(v * 100) + "%"; }
  private static Format seconds() { return v -> String.format(Locale.US, "%.1fs", v); }
  private static Format degrees() { return v -> Math.round(v) + "°"; }

  interface Pick { void pick(String id); }

  /** A horizontally scrolling row of choice chips; the chosen one is filled with the accent colour. */
  private void chips(LinearLayout box, String title, String[][] items, String current, Pick pick) {
    if (title != null) section(box, title);
    HorizontalScrollView scroll = new HorizontalScrollView(this); scroll.setHorizontalScrollBarEnabled(false); LinearLayout row = new LinearLayout(this);
    for (String[] item : items) {
      TextView chip = label(I18n.t(item[1]), 13, INK); chip.setGravity(Gravity.CENTER); chip.setPadding(dp(14), 0, dp(14), 0); chip.setTag(item[0]);
      chip.setBackground(rounded(item[0].equals(current) ? ACCENT : CARD, 16));
      chip.setOnClickListener(v -> { remember(); pick.pick(item[0]); for (int i = 0; i < row.getChildCount(); i++) row.getChildAt(i).setBackground(rounded(row.getChildAt(i) == v ? ACCENT : CARD, 16)); timeline.invalidate(); });
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, dp(34)); lp.rightMargin = dp(8); row.addView(chip, lp);
    }
    scroll.addView(row); box.addView(scroll);
  }

  private void swatches(LinearLayout box, int current, Change pick) {
    int[] colors = { Color.WHITE, Color.BLACK, 0xffffd45c, 0xffff8a3d, 0xffff4d6d, 0xffff6fd8, 0xffb388ff, 0xff7c5cff, 0xff4da3ff, 0xff38d9c8, 0xff5ee07a, 0xffd7f75b };
    HorizontalScrollView scroll = new HorizontalScrollView(this); scroll.setHorizontalScrollBarEnabled(false); LinearLayout row = new LinearLayout(this);
    for (int color : colors) {
      View dot = new View(this); GradientDrawable g = new GradientDrawable(); g.setShape(GradientDrawable.OVAL); g.setColor(color); g.setStroke(dp(color == current ? 3 : 1), color == current ? ACCENT : 0x55ffffff); dot.setBackground(g);
      dot.setContentDescription(I18n.t("Màu")); dot.setOnClickListener(v -> { remember(); pick.set(color); for (int i = 0; i < row.getChildCount(); i++) { GradientDrawable d = (GradientDrawable) row.getChildAt(i).getBackground(); d.setStroke(dp(row.getChildAt(i) == v ? 3 : 1), row.getChildAt(i) == v ? ACCENT : 0x55ffffff); } timeline.invalidate(); });
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(32), dp(32)); lp.rightMargin = dp(10); row.addView(dot, lp);
    }
    scroll.addView(row); box.addView(scroll);
  }

  private TextView action(LinearLayout box, String iconName, String text, Runnable run) {
    TextView b = label(text, 14, INK); b.setGravity(Gravity.CENTER_VERTICAL); b.setPadding(dp(14), 0, dp(14), 0); b.setCompoundDrawablesRelative(small(editorIcon(iconName, INK), 20), null, null, null);
    b.setCompoundDrawablePadding(dp(10)); b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffffff), rounded(CARD, 12), null)); b.setOnClickListener(v -> { if (!busy) run.run(); });
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, dp(46)); lp.topMargin = dp(8); box.addView(b, lp); return b;
  }

  private void qualitySheet() {
    LinearLayout box = openSheet(I18n.t("Chất lượng xuất"));
    chips(box, I18n.t("Độ phân giải"), new String[][] { { "480", "480p" }, { "720", "720p" }, { "1080", "1080p" } }, String.valueOf(project.exportSide), id -> { project.exportSide = Integer.parseInt(id); updateButtons(); });
    note(box, I18n.t("Video xuất ở 30 khung hình/giây, H.264 + âm thanh AAC. 1080p sắc nét nhất nhưng tệp lớn hơn."));
  }

  private void formatSheet() {
    LinearLayout box = openSheet(I18n.t("Tỉ lệ khung hình"));
    chips(box, null, new String[][] { { "0", I18n.t("Gốc") }, { "0.5625", "9:16" }, { "1", "1:1" }, { "0.8", "4:5" }, { "0.75", "3:4" }, { "1.777778", "16:9" }, { "1.333333", "4:3" }, { "2.35", "2.35:1" } },
      project.aspect == 0 ? "0" : trim(project.aspect), id -> { project.aspect = Float.parseFloat(id); fit(); });
    note(box, I18n.t("9:16 cho Shorts/Story, 1:1 và 4:5 cho bảng tin. Phần trống được lấp bằng nền (xem mục Nền)."));
  }
  private static String trim(float v) { for (String s : new String[] { "0.5625", "1", "0.8", "0.75", "1.777778", "1.333333", "2.35" }) if (Math.abs(Float.parseFloat(s) - v) < .001f) return s; return String.valueOf(v); }

  private void backgroundSheet() {
    LinearLayout box = openSheet(I18n.t("Nền"));
    chips(box, I18n.t("Kiểu nền"), new String[][] { { "blur", I18n.t("Mờ ảo") }, { "black", I18n.t("Đen") }, { "white", I18n.t("Trắng") } }, project.background.startsWith("#") ? "" : project.background, id -> project.background = id);
    section(box, I18n.t("Màu nền")); swatches(box, project.background.startsWith("#") ? Color.parseColor(project.background) : 0, v -> project.background = String.format("#%06X", ((int) v) & 0xffffff));
    note(box, I18n.t("Nền hiện ra khi khung hình khác tỉ lệ video hoặc khi thu nhỏ clip."));
  }

  private void speedSheet() {
    EditorProject.Clip c = project.clip(selId); if (c == null) return; LinearLayout box = openSheet(I18n.t("Tốc độ"));
    chips(box, null, new String[][] { { "0.25", I18n.t("0.25×") }, { "0.5", I18n.t("0.5×") }, { "0.75", I18n.t("0.75×") }, { "1", I18n.t("1×") }, { "1.5", I18n.t("1.5×") }, { "2", I18n.t("2×") }, { "3", I18n.t("3×") }, { "4", I18n.t("4×") } }, String.valueOf(c.speed).replaceAll("\\.0$", ""), id -> { c.speed = Float.parseFloat(id); afterClipsChanged(); });
    slider(box, I18n.t("Tùy chỉnh"), .1f, 4, c.speed, v -> String.format(Locale.US, "%.2f×", v), v -> { c.speed = Math.round(v * 20) / 20f; updateTime(); });
    note(box, c.video ? I18n.t("Thời lượng clip: ") + TimelineView.clock(c.length()) + I18n.t(". Âm thanh gốc đổi cao độ theo tốc độ.") : I18n.t("Với ảnh, kéo hai đầu clip trên dòng thời gian để đổi thời lượng."));
  }

  private void volumeSheet() {
    if ("track".equals(selKind)) { EditorProject.Track t = project.track(selId); if (t == null) return; LinearLayout box = openSheet(I18n.t("Âm lượng"));
      slider(box, I18n.t("Âm lượng"), 0, 2, t.gain, percent(), v -> t.gain = v); return; }
    EditorProject.Clip c = project.clip(selId); if (c == null) return; LinearLayout box = openSheet(I18n.t("Âm lượng clip"));
    if (!c.video || !c.hasAudio) { note(box, I18n.t("Clip này không có âm thanh.")); return; }
    slider(box, I18n.t("Âm lượng"), 0, 2, c.volume, percent(), v -> c.volume = v);
    action(box, c.volume == 0 ? "volume" : "mute", c.volume == 0 ? I18n.t("Bật tiếng clip") : I18n.t("Tắt tiếng clip"), () -> { remember(); c.volume = c.volume == 0 ? 1 : 0; volumeSheet(); });
    note(box, I18n.t("Trên 100% chỉ nghe rõ trong video đã xuất."));
  }

  private void fadeSheet() {
    EditorProject.Track t = project.track(selId); if (t == null) return; LinearLayout box = openSheet(I18n.t("Mờ dần"));
    slider(box, I18n.t("Mờ vào"), 0, Math.min(5, t.length / 2), t.fadeIn, seconds(), v -> t.fadeIn = v);
    slider(box, I18n.t("Mờ ra"), 0, Math.min(5, t.length / 2), t.fadeOut, seconds(), v -> t.fadeOut = v);
  }

  private void transformSheet() {
    EditorProject.Item item = selectedItem(); if (item == null) return; boolean isClip = item instanceof EditorProject.Clip;
    LinearLayout box = openSheet(isClip ? I18n.t("Vị trí clip") : I18n.t("Vị trí lớp")); float[] pose = item.pose(localTime());
    slider(box, I18n.t("Kích thước"), isClip ? .3f : .1f, 4, pose[EditorProject.SCALE], percent(), v -> item.edit(localTime(), EditorProject.SCALE, v));
    slider(box, "Ngang", 0, 1, pose[EditorProject.X], v -> Math.round((v - .5f) * 200) + "", v -> item.edit(localTime(), EditorProject.X, v));
    slider(box, I18n.t("Dọc"), 0, 1, pose[EditorProject.Y], v -> Math.round((v - .5f) * 200) + "", v -> item.edit(localTime(), EditorProject.Y, v));
    slider(box, "Xoay", -180, 180, pose[EditorProject.ROTATION], degrees(), v -> item.edit(localTime(), EditorProject.ROTATION, Math.round(v)));
    slider(box, I18n.t("Độ mờ"), 0, 1, pose[EditorProject.OPACITY], percent(), v -> item.edit(localTime(), EditorProject.OPACITY, v));
    boolean smooth = item.keys.isEmpty() || item.keys.get(0).smooth;
    chips(box, I18n.t("Chuyển động giữa khung hình chính"), new String[][] { { "smooth", I18n.t("Mượt (ease)") }, { "linear", I18n.t("Đều") } }, smooth ? "smooth" : "linear", id -> { for (EditorProject.Key k : item.keys) k.smooth = id.equals("smooth"); });
    action(box, "reset", I18n.t("Đặt lại vị trí và xóa khung hình chính"), () -> { remember(); item.keys.clear(); item.x = item.y = .5f; if (!isClip) item.y = ((EditorProject.Layer) item).kind.equals("caption") ? .82f : .5f; item.scale = 1; item.rotation = 0; item.opacity = 1; transformSheet(); });
    note(box, item.keys.isEmpty() ? I18n.t("Mẹo: bấm ◆ ở thanh phát để thêm khung hình chính, dời đầu phát, rồi chỉnh để tạo chuyển động. Có thể kéo/chụm trực tiếp trên khung xem trước.") : I18n.t("Đã có ") + item.keys.size() + I18n.t(" khung hình chính: mọi thay đổi được ghi vào khung hình chính tại đầu phát."));
  }

  private void adjustSheet() {
    EditorProject.Clip c = project.clip(selId); if (c == null) return; LinearLayout box = openSheet(I18n.t("Điều chỉnh"));
    slider(box, I18n.t("Độ sáng"), -1, 1, c.fx.exposure, v -> Math.round(v * 100) + "", v -> c.fx.exposure = v);
    slider(box, I18n.t("Tương phản"), .5f, 2, c.fx.contrastLevel, percent(), v -> c.fx.contrastLevel = v);
    slider(box, I18n.t("Bão hòa"), 0, 2, c.fx.saturation, percent(), v -> c.fx.saturation = v);
    slider(box, I18n.t("Nhiệt độ"), -1, 1, c.fx.temperature, v -> Math.round(v * 100) + "", v -> c.fx.temperature = v);
    slider(box, I18n.t("Độ đậm lọc"), 0, 1, c.fx.intensity, percent(), v -> c.fx.intensity = v);
    action(box, "reset", I18n.t("Đặt lại"), () -> { remember(); c.fx.exposure = 0; c.fx.contrastLevel = 1; c.fx.saturation = 1; c.fx.temperature = 0; c.fx.intensity = 1; adjustSheet(); });
    applyAll(box, c);
  }

  private void applyAll(LinearLayout box, EditorProject.Clip c) {
    if (project.clips.size() < 2) return;
    action(box, "duplicate", I18n.t("Áp dụng cho tất cả clip"), () -> { remember(); for (EditorProject.Clip o : project.clips) if (o != c) { boolean flip = o.fx.flipImage; o.fx = c.fx.copy(); o.fx.flipImage = flip; } showHint(I18n.t("Đã áp dụng cho ") + project.clips.size() + " clip", 1200); });
  }

  private void fxSheet(String kind) {
    EditorProject.Clip c = project.clip(selId); if (c == null) return;
    LinearLayout box = openSheet(kind.equals("beauty") ? I18n.t("Làm đẹp") : kind.equals("filter") ? I18n.t("Bộ lọc") : I18n.t("Hiệu ứng khuôn mặt"));
    EffectControls.Target base = EffectControls.forEditor(c.fx);
    EffectControls.Target target = new EffectControls.Target() {
      public String filter() { return base.filter(); } public String sticker() { return base.sticker(); } public boolean beauty() { return base.beauty(); }
      public float value(String k) { return base.value(k); } public String[][] filters() { return base.filters(); }
      public void filter(String id) { remember(); base.filter(id); } public void sticker(String id) { remember(); base.sticker(id); } public void look(String id) { remember(); base.look(id); }
      public void beginEdit() { remember(); } public void value(String k, float v) { base.value(k, v); dirty = true; }
    };
    box.addView(EffectControls.panel(this, kind, target, () -> {}));
    if (kind.equals("beauty")) action(box, c.fx.beautyOn ? "none" : "beauty", c.fx.beautyOn ? I18n.t("Tắt làm đẹp") : I18n.t("Bật làm đẹp"), () -> { remember(); c.fx.beautyOn = !c.fx.beautyOn; fxSheet(kind); });
    if (kind.equals("beauty") || kind.equals("sticker")) note(box, I18n.t("Làm đẹp và hiệu ứng mặt cần nhìn rõ khuôn mặt; xử lý ngay trên máy."));
    applyAll(box, c);
  }

  private void transitionSheet(int index) {
    if (index <= 0 || index >= project.clips.size()) { showHint(I18n.t("Cần ít nhất 2 clip để thêm chuyển cảnh"), 1600); return; }
    EditorProject.Clip c = project.clips.get(index); LinearLayout box = openSheet(I18n.t("Chuyển cảnh · clip ") + index + " → " + (index + 1));
    GridLayout grid = new GridLayout(this); grid.setColumnCount(4); int cell = (getResources().getDisplayMetrics().widthPixels - dp(32)) / 4;
    for (String[] item : EditorRender.TRANSITIONS) {
      LinearLayout tile = new LinearLayout(this); tile.setOrientation(LinearLayout.VERTICAL); tile.setGravity(Gravity.CENTER_HORIZONTAL); tile.setPadding(dp(4), dp(6), dp(4), dp(6));
      TransitionPreview demo = new TransitionPreview(this, item[0]); GradientDrawable frame = rounded(CARD, 10); if (item[0].equals(c.transition)) frame.setStroke(dp(2), ACCENT); demo.setBackground(frame); demo.setClipToOutline(true);
      tile.addView(demo, new LinearLayout.LayoutParams(cell - dp(14), (cell - dp(14)) * 3 / 4));
      TextView name = label(I18n.t(item[1]), 11, item[0].equals(c.transition) ? ACCENT : INK); name.setGravity(Gravity.CENTER); name.setPadding(0, dp(4), 0, 0); tile.addView(name);
      tile.setOnClickListener(v -> { remember(); c.transition = item[0]; afterClipsChanged(); scrub(project.starts()[index] - .3f, true); playing = true; transitionSheet(index); });
      grid.addView(tile, new GridLayout.LayoutParams(new ViewGroup.LayoutParams(cell, -2)));
    }
    box.addView(grid);
    if (!c.transition.equals("none")) slider(box, I18n.t("Thời lượng"), .2f, 2, c.transitionLength, seconds(), v -> { c.transitionLength = v; updateTime(); });
    action(box, "duplicate", I18n.t("Áp dụng cho tất cả chỗ nối"), () -> { remember(); for (int i = 1; i < project.clips.size(); i++) { project.clips.get(i).transition = c.transition; project.clips.get(i).transitionLength = c.transitionLength; } afterClipsChanged(); showHint(I18n.t("Đã áp dụng cho mọi chỗ nối"), 1200); });
  }

  /** Small looping demo of a transition, drawn with the real renderer. */
  private final class TransitionPreview extends View {
    private final String kind; private Bitmap a, b, out; private final EditorRender demo = new EditorRender();
    TransitionPreview(Context c, String kind) { super(c); this.kind = kind; }
    @Override protected void onDraw(Canvas canvas) {
      int w = getWidth(), h = getHeight(); if (w <= 0 || h <= 0) return;
      if (a == null || a.getWidth() != w) { a = card(w, h, 0xff5b3df5, 0xffb388ff, "A"); b = card(w, h, 0xffff7a45, 0xffffd45c, "B"); out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888); }
      long t = SystemClock.uptimeMillis() % 1800; float u = Math.max(0, Math.min(1, (t - 300) / 1000f));
      Canvas c = new Canvas(out); c.drawColor(Color.BLACK); demo.transition(c, kind, u, a, b); canvas.drawBitmap(out, 0, 0, null); postInvalidateOnAnimation();
    }
    private Bitmap card(int w, int h, int from, int to, String text) {
      Bitmap bm = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888); Canvas c = new Canvas(bm); Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
      p.setShader(new LinearGradient(0, 0, w, h, from, to, Shader.TileMode.CLAMP)); c.drawRect(0, 0, w, h, p); p.setShader(null);
      p.setColor(Color.WHITE); p.setTextSize(h * .42f); p.setTextAlign(Paint.Align.CENTER); p.setTypeface(Typeface.DEFAULT_BOLD); c.drawText(text, w / 2f, h * .64f, p); return bm;
    }
  }

  // ---------- Layers ----------
  private EditorProject.Layer newLayer(String kind, float length) {
    EditorProject.Layer l = new EditorProject.Layer(); l.kind = kind; l.start = Math.max(0, Math.min(playhead, Math.max(0, project.duration() - .5f)));
    l.length = Math.max(.5f, Math.min(length, Math.max(1, project.duration() - l.start))); return l;
  }

  private void addText() { EditorProject.Layer l = newLayer("text", 3); l.text = ""; l.style = "stroke"; editText(l, true); }

  private void editText(EditorProject.Layer layer, boolean adding) {
    EditText field = new KinnectInput(this); field.setText(layer.text); field.setHint(I18n.t("Nhập chữ")); field.setSelection(field.getText().length()); field.setMinLines(2); field.setMaxLines(6);
    FrameLayout wrap = new FrameLayout(this); wrap.setPadding(dp(20), dp(8), dp(20), 0); wrap.addView(field);
    AlertDialog dialog = new AlertDialog.Builder(this).setTitle(adding ? I18n.t("Thêm chữ") : I18n.t("Sửa chữ")).setView(wrap)
      .setPositiveButton("Xong", (d, w) -> {
        String value = field.getText().toString().trim(); if (value.isEmpty()) return;
        remember(); layer.text = value; if (adding) { project.layers.add(layer); select("layer", layer.id); } else refreshTools(); timeline.requestLayout(); timeline.invalidate();
      }).setNegativeButton(I18n.t("Hủy"), null).create();
    dialog.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE); dialog.show(); field.requestFocus();
  }

  private void styleSheet() {
    EditorProject.Layer l = project.layer(selId); if (l == null) return; LinearLayout box = openSheet(l.kind.equals("caption") ? I18n.t("Kiểu phụ đề") : I18n.t("Kiểu chữ"));
    boolean caption = l.kind.equals("caption");
    final List<EditorProject.Layer> targets = new ArrayList<>(); if (caption) { for (EditorProject.Layer o : project.layers) if (o.kind.equals("caption")) targets.add(o); } else targets.add(l);
    chips(box, I18n.t("Kiểu"), EditorRender.STYLES, l.style, id -> { for (EditorProject.Layer o : targets) o.style = id; });
    section(box, I18n.t("Màu")); swatches(box, l.color, v -> { for (EditorProject.Layer o : targets) o.color = (int) v; });
    chips(box, I18n.t("Phông chữ"), EditorRender.FONTS, l.font, id -> { for (EditorProject.Layer o : targets) o.font = id; });
    chips(box, I18n.t("Căn lề"), new String[][] { { "left", I18n.t("Trái") }, { "center", I18n.t("Giữa") }, { "right", I18n.t("Phải") } }, l.align, id -> { for (EditorProject.Layer o : targets) o.align = id; });
    slider(box, I18n.t("Cỡ chữ"), .025f, .16f, l.size, v -> Math.round(v * 1000) + "", v -> { for (EditorProject.Layer o : targets) o.size = v; });
    if (caption) note(box, I18n.t("Thay đổi áp dụng cho tất cả ") + targets.size() + I18n.t(" dòng phụ đề."));
  }

  private void animationSheet() {
    EditorProject.Layer l = project.layer(selId); if (l == null) return; LinearLayout box = openSheet(I18n.t("Hoạt ảnh"));
    boolean words = !l.kind.equals("image");
    List<String[]> ins = new ArrayList<>(); for (String[] a : EditorRender.ANIMATIONS) if (words || !a[0].equals("type")) ins.add(a);
    List<String[]> outs = new ArrayList<>(); for (String[] a : EditorRender.ANIMATIONS) if (!a[0].equals("type")) outs.add(a);
    chips(box, I18n.t("Vào"), ins.toArray(new String[0][]), l.animIn, id -> l.animIn = id);
    chips(box, "Ra", outs.toArray(new String[0][]), l.animOut, id -> l.animOut = id);
    slider(box, I18n.t("Thời lượng"), .1f, 1.5f, l.animLength, seconds(), v -> l.animLength = v);
  }

  private static final String[][] STICKERS = {
    { "Cảm xúc", "😀 😂 🥰 😍 😎 🤩 😭 😱 🥳 😴 🤔 🙃 😇 🤗 😡 🤯" },
    { "Yêu thương", "❤️ 💖 💕 💘 💝 💌 😘 💋 🌹 💐 🫶 💯" },
    { "Trang trí", "✨ ⭐ 🌟 💫 🔥 🎉 🎊 🎈 🎁 👑 💎 🌈 ☀️ 🌙 ⚡ 🎶" },
    { "Cử chỉ", "👍 👏 🙌 🙏 ✌️ 🤞 👌 💪 👀 👉 👈 ☝️" },
    { "Đồ vật", "📸 🎬 🎤 🎧 ☕ 🍰 🍕 🍜 🧋 🏖️ ✈️ 🚗" },
    { "Động vật", "🐶 🐱 🐰 🐻 🐼 🦊 🐥 🦋 🐠 🦄" } };

  private void stickerSheet() {
    LinearLayout box = openSheet(I18n.t("Nhãn dán"));
    int cell = (getResources().getDisplayMetrics().widthPixels - dp(32)) / 6;
    for (String[] group : STICKERS) {
      section(box, group[0]); GridLayout grid = new GridLayout(this); grid.setColumnCount(6);
      for (String emoji : group[1].split(" ")) {
        TextView t = label(emoji, 26, Color.WHITE); t.setGravity(Gravity.CENTER); t.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffffff), null, rounded(Color.WHITE, 10)));
        t.setOnClickListener(v -> { remember(); EditorProject.Layer l = newLayer("sticker", 3); l.text = emoji; l.animIn = "pop"; project.layers.add(l); select("layer", l.id); showHint(I18n.t("Kéo nhãn dán trên khung xem trước để đặt vị trí"), 1800); });
        grid.addView(t, new GridLayout.LayoutParams(new ViewGroup.LayoutParams(cell, dp(48))));
      }
      box.addView(grid);
    }
  }

  // ---------- Audio ----------
  private void audioSheet() {
    LinearLayout box = openSheet(I18n.t("Âm thanh"));
    action(box, "music", I18n.t("Thêm nhạc từ máy"), () -> pick(PICK_MUSIC, "audio/*", false));
    action(box, "voice", I18n.t("Ghi âm lồng tiếng"), this::voiceSheet);
    boolean muted = true; for (EditorProject.Clip c : project.clips) if (c.video && c.hasAudio && c.volume > 0) muted = false;
    final boolean allMuted = muted;
    action(box, allMuted ? "volume" : "mute", allMuted ? I18n.t("Bật tiếng gốc mọi clip") : I18n.t("Tắt tiếng gốc mọi clip"), () -> { remember(); for (EditorProject.Clip c : project.clips) c.volume = allMuted ? 1 : 0; audioSheet(); timeline.invalidate(); });
    note(box, I18n.t("Chạm vào dải nhạc trên dòng thời gian để chỉnh âm lượng, mờ dần, tách; giữ để kéo đổi vị trí."));
  }

  private void voiceSheet() {
    LinearLayout box = openSheet(I18n.t("Ghi âm lồng tiếng")); box.setGravity(Gravity.CENTER_HORIZONTAL);
    micTimer = label(I18n.t("Bấm để ghi âm từ ") + TimelineView.clock(playhead), 13, MUTED); micTimer.setGravity(Gravity.CENTER); micTimer.setPadding(0, dp(12), 0, dp(14)); box.addView(micTimer, new LinearLayout.LayoutParams(-1, -2));
    FrameLayout ring = new FrameLayout(this); GradientDrawable outer = new GradientDrawable(); outer.setShape(GradientDrawable.OVAL); outer.setStroke(dp(3), Color.WHITE); ring.setBackground(outer);
    View dot = new View(this); GradientDrawable inner = new GradientDrawable(); inner.setShape(GradientDrawable.OVAL); inner.setColor(0xffff3b55); dot.setBackground(inner);
    ring.addView(dot, new FrameLayout.LayoutParams(dp(54), dp(54), Gravity.CENTER)); micButton = dot; ring.setContentDescription(I18n.t("Bắt đầu hoặc dừng ghi âm"));
    ring.setOnClickListener(v -> { if (micRecording) stopMic(); else startMic(); });
    box.addView(ring, new LinearLayout.LayoutParams(dp(72), dp(72)));
    note(box, I18n.t("Video phát (tắt tiếng gốc) trong lúc bạn nói để khớp lời. Nên dùng tai nghe.")).setGravity(Gravity.CENTER);
  }

  private void startMic() {
    if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) { requestPermissions(new String[] { Manifest.permission.RECORD_AUDIO }, MIC); return; }
    try {
      micFile = File.createTempFile("kinnect-voice-", ".m4a", getCacheDir()); mic = new MediaRecorder();
      mic.setAudioSource(MediaRecorder.AudioSource.MIC); mic.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4); mic.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
      mic.setAudioSamplingRate(44100); mic.setAudioEncodingBitRate(128000); mic.setAudioChannels(1); mic.setOutputFile(micFile.getPath()); mic.prepare(); mic.start();
      micRecording = true; micStart = playhead; micStarted = SystemClock.elapsedRealtime(); if (playhead >= project.duration() - .05f) micStart = playhead; playing = playhead < project.duration() - .05f; updateButtons();
      if (micButton != null) { micButton.animate().scaleX(.55f).scaleY(.55f).setDuration(160); ((GradientDrawable) micButton.getBackground()).setCornerRadius(dp(8)); ((GradientDrawable) micButton.getBackground()).setShape(GradientDrawable.RECTANGLE); }
    } catch (Exception e) { if (mic != null) { mic.release(); mic = null; } micRecording = false; showHint(I18n.t("Không mở được micro."), 1800); }
  }

  private void stopMic() {
    if (!micRecording) return; micRecording = false; playing = false; updateButtons(); long ms = SystemClock.elapsedRealtime() - micStarted;
    try { mic.stop(); } catch (Exception e) { ms = 0; } mic.release(); mic = null;
    if (micButton != null) { GradientDrawable g = (GradientDrawable) micButton.getBackground(); g.setShape(GradientDrawable.OVAL); micButton.animate().scaleX(1).scaleY(1).setDuration(160); }
    if (ms < 400) { if (micFile != null) micFile.delete(); showHint(I18n.t("Bản ghi quá ngắn."), 1400); return; }
    remember(); EditorProject.Track t = new EditorProject.Track(); t.kind = "voice"; t.file = micFile; t.start = micStart; t.length = t.source = ms / 1000f;
    int n = 0; for (EditorProject.Track o : project.tracks) if (o.kind.equals("voice")) n++; t.name = String.valueOf(n + 1);
    project.tracks.add(t); timeline.requestLayout(); timeline.invalidate(); showHint(I18n.t("Đã thêm bản ghi âm ") + TimelineView.clock(t.length), 1500);
    if (micTimer != null) micTimer.setText(I18n.t("Bấm để ghi tiếp từ ") + TimelineView.clock(playhead));
  }

  @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
    super.onRequestPermissionsResult(request, permissions, results);
    if (request == MIC) { if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED) startMic(); else showHint(I18n.t("Cần quyền micro để ghi âm."), 2000); }
  }

  // ---------- Captions ----------
  private String captionLanguage = "vi-VN"; private boolean replaceCaptions = true;

  private void captionSheet() {
    LinearLayout box = openSheet(I18n.t("Phụ đề tự động"));
    if (!AutoCaptions.supported(this)) {
      note(box, Build.VERSION.SDK_INT < 33 ? I18n.t("Phụ đề tự động trên máy cần Android 13 trở lên.") : I18n.t("Máy chưa có dịch vụ nhận dạng giọng nói ngoại tuyến. Hãy cài/ cập nhật ứng dụng Google và gói Nhận dạng giọng nói (Cài đặt › Hệ thống › Ngôn ngữ › Nhận dạng giọng nói trên thiết bị)."));
      return;
    }
    chips(box, I18n.t("Ngôn ngữ trong video"), new String[][] { { "vi-VN", I18n.t("Tiếng Việt") }, { "en-US", "English" } }, captionLanguage, id -> captionLanguage = id);
    chips(box, I18n.t("Phụ đề cũ"), new String[][] { { "replace", I18n.t("Thay thế") }, { "keep", I18n.t("Giữ lại") } }, replaceCaptions ? "replace" : "keep", id -> replaceCaptions = id.equals("replace"));
    final TextView status = note(box, I18n.t("Nhận dạng chạy hoàn toàn trên máy, không gửi âm thanh đi đâu, không tốn phí. Lần đầu Android có thể cần tải gói ngôn ngữ."));
    action(box, "caption", I18n.t("Tạo phụ đề"), () -> makeCaptions(status));
  }

  private void makeCaptions(TextView status) {
    final List<EditorAudio.Source> sources = new ArrayList<>(); float[] starts = project.starts();
    for (int i = 0; i < project.clips.size(); i++) { EditorProject.Clip c = project.clips.get(i); if (!c.video || !c.hasAudio || c.volume <= 0) continue; EditorAudio.Source s = new EditorAudio.Source(); s.file = c.file; s.start = starts[i]; s.length = c.length(); s.in = c.in; s.rate = c.speed; sources.add(s); }
    for (EditorProject.Track t : project.tracks) if (t.kind.equals("voice")) { EditorAudio.Source s = new EditorAudio.Source(); s.file = t.file; s.start = t.start; s.length = t.length; s.in = t.in; s.gain = 1; sources.add(s); }
    if (sources.isEmpty()) { status.setText(I18n.t("Không có giọng nói: các clip đều tắt tiếng hoặc không có âm thanh.")); return; }
    busy = true; playing = false; status.setText(I18n.t("Đang chuẩn bị âm thanh…")); final long ms = (long) (project.duration() * 1000); final String language = captionLanguage;
    task = worker.submit(() -> {
      try {
        short[] pcm = EditorAudio.speech(this, sources, ms, AutoCaptions.RATE);
        runOnUiThread(() -> {
          if (closed) return; captions = new AutoCaptions();
          captions.run(this, pcm, language, new AutoCaptions.Listener() {
            public void progress(int done, int total) { status.setText(I18n.t("Đang nhận dạng giọng nói… ") + done + "/" + total); }
            public void finished(List<float[]> times, List<String> lines, String error) {
              busy = false; captions = null;
              if (lines.isEmpty()) { status.setText(error); return; }
              remember(); EditorProject.Layer style = null;
              for (Iterator<EditorProject.Layer> it = project.layers.iterator(); it.hasNext();) { EditorProject.Layer l = it.next(); if (!l.kind.equals("caption")) continue; if (style == null) style = l; if (replaceCaptions) it.remove(); }
              for (int i = 0; i < lines.size(); i++) {
                EditorProject.Layer l = new EditorProject.Layer(); l.kind = "caption"; l.text = lines.get(i); l.start = times.get(i)[0]; l.length = Math.max(.4f, times.get(i)[1] - times.get(i)[0]);
                l.y = .82f; l.size = .052f; l.style = "stroke"; l.animIn = "none"; l.animOut = "none";
                if (style != null) { l.style = style.style; l.color = style.color; l.font = style.font; l.size = style.size; l.y = style.y; l.x = style.x; }
                project.layers.add(l);
              }
              timeline.requestLayout(); timeline.invalidate();
              status.setText(I18n.t("Đã tạo ") + lines.size() + I18n.t(" dòng phụ đề.") + (error != null ? " " + error : "") + I18n.t(" Chạm vào một dòng để sửa chữ hoặc kiểu."));
            }
          });
        });
      } catch (Exception | OutOfMemoryError e) { runOnUiThread(() -> { busy = false; status.setText(I18n.t("Không đọc được âm thanh của video.")); }); }
    });
  }

  // ---------- Clip operations ----------
  private void split() {
    if ("clip".equals(selKind)) {
      int i = project.indexOf(selId); if (i < 0) return; EditorProject.Clip c = project.clips.get(i); float local = playhead - project.starts()[i];
      if (local < .1f || local > c.length() - .1f) { showHint(I18n.t("Đặt đầu phát vào giữa clip để tách"), 1500); return; }
      remember(); EditorProject.Clip b = c.copy(); b.id = EditorProject.newId(); float cut = c.in + local * c.speed;
      c.out = cut; b.in = cut; b.transition = "none"; trimKeys(c, b, local); project.clips.add(i + 1, b); select("clip", b.id);
    } else if ("layer".equals(selKind)) {
      EditorProject.Layer l = project.layer(selId); if (l == null) return; float local = playhead - l.start;
      if (local < .1f || local > l.length - .1f) { showHint(I18n.t("Đặt đầu phát vào giữa lớp để tách"), 1500); return; }
      remember(); EditorProject.Layer b = l.copy(); b.id = EditorProject.newId(); b.start = playhead; b.length = l.length - local; l.length = local; trimKeys(l, b, local);
      project.layers.add(project.layers.indexOf(l) + 1, b); select("layer", b.id);
    } else if ("track".equals(selKind)) {
      EditorProject.Track t = project.track(selId); if (t == null) return; float local = playhead - t.start;
      if (local < .1f || local > t.length - .1f) { showHint(I18n.t("Đặt đầu phát vào giữa đoạn âm thanh để tách"), 1500); return; }
      remember(); EditorProject.Track b = t.copy(); b.id = EditorProject.newId(); b.start = playhead; b.in = t.in + local; b.length = t.length - local; b.fadeIn = 0; t.length = local; t.fadeOut = 0;
      project.tracks.add(b); select("track", b.id);
    }
    timeline.requestLayout(); showHint(I18n.t("Đã tách"), 900);
  }

  private static void trimKeys(EditorProject.Item a, EditorProject.Item b, float local) {
    for (Iterator<EditorProject.Key> it = a.keys.iterator(); it.hasNext();) if (it.next().t > local + .001f) it.remove();
    for (Iterator<EditorProject.Key> it = b.keys.iterator(); it.hasNext();) { EditorProject.Key k = it.next(); k.t -= local; if (k.t < -.001f) it.remove(); }
  }

  private void duplicate() {
    remember();
    if ("clip".equals(selKind)) { int i = project.indexOf(selId); if (i < 0) return; EditorProject.Clip b = project.clips.get(i).copy(); b.id = EditorProject.newId(); project.clips.add(i + 1, b); select("clip", b.id); }
    else if ("layer".equals(selKind)) { EditorProject.Layer l = project.layer(selId); if (l == null) return; EditorProject.Layer b = l.copy(); b.id = EditorProject.newId(); b.start = l.start + l.length; project.layers.add(b); select("layer", b.id); }
    else if ("track".equals(selKind)) { EditorProject.Track t = project.track(selId); if (t == null) return; EditorProject.Track b = t.copy(); b.id = EditorProject.newId(); b.start = t.start + t.length; project.tracks.add(b); select("track", b.id); }
    afterClipsChanged(); showHint(I18n.t("Đã nhân bản"), 900);
  }

  private void delete() {
    if ("clip".equals(selKind)) { if (project.clips.size() == 1) { showHint(I18n.t("Video cần ít nhất một clip"), 1500); return; } remember(); project.clips.remove(project.clip(selId)); }
    else if ("layer".equals(selKind)) { remember(); project.layers.remove(project.layer(selId)); }
    else if ("track".equals(selKind)) { remember(); project.tracks.remove(project.track(selId)); }
    selKind = null; playhead = Math.min(playhead, project.duration()); afterClipsChanged(); showHint(I18n.t("Đã xóa"), 900);
  }

  private void reorder(int by) {
    int i = project.indexOf(selId), j = i + by; if (i < 0 || j < 0 || j >= project.clips.size()) return;
    remember(); Collections.swap(project.clips, i, j); project.clips.get(0).transition = "none"; afterClipsChanged(); scrub(project.starts()[j] + .01f, true);
  }

  // ---------- Picking files ----------
  private void pick(int request, String type, boolean multiple) {
    Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(type);
    if (request == PICK_CLIPS) pick.putExtra(Intent.EXTRA_MIME_TYPES, new String[] { "image/*", "video/*" });
    if (multiple) pick.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
    startActivityForResult(pick, request);
  }

  @Override protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (request == SAVE) { saved(result, data); return; }
    if (result != RESULT_OK || data == null) return;
    final List<Uri> uris = new ArrayList<>();
    if (data.getClipData() != null) for (int i = 0; i < data.getClipData().getItemCount(); i++) uris.add(data.getClipData().getItemAt(i).getUri());
    else if (data.getData() != null) uris.add(data.getData());
    if (uris.isEmpty()) return;
    showHint(I18n.t("Đang thêm…"), 0);
    loader.execute(() -> {
      try {
        if (request == PICK_CLIPS) {
          List<EditorProject.Clip> added = new ArrayList<>(); for (Uri u : uris) added.add(probe(copyIn(u, "kinnect-edit-clip-")));
          runOnUiThread(() -> { if (closed) return; remember(); int at = Math.max(0, project.clipAt(playhead)) + 1; at = Math.min(at, project.clips.size()); project.clips.addAll(at, added);
            for (EditorProject.Clip c : added) thumbnails(c); afterClipsChanged(); scrub(project.starts()[at] + .01f, true); showHint(I18n.t("Đã thêm ") + added.size() + " clip", 1300); });
        } else if (request == PICK_MUSIC) {
          File f = copyIn(uris.get(0), "kinnect-music-"); MediaMetadataRetriever r = new MediaMetadataRetriever(); long ms; String title;
          try { r.setDataSource(f.getPath()); ms = parse(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)); title = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE); } finally { try { r.release(); } catch (Exception ignored) {} }
          if (ms <= 0) throw new IOException(I18n.t("Tệp không có âm thanh."));
          final String name = title != null && !title.trim().isEmpty() ? title.trim() : displayName(uris.get(0)); final long length = ms;
          runOnUiThread(() -> { if (closed) return; remember(); EditorProject.Track t = new EditorProject.Track(); t.kind = "music"; t.file = f; t.name = name; t.source = length / 1000f;
            t.start = Math.max(0, Math.min(playhead, project.duration() - .5f)); t.length = Math.min(t.source, Math.max(1, project.duration() - t.start)); t.gain = .7f; t.fadeOut = Math.min(1.5f, t.length / 4);
            project.tracks.add(t); select("track", t.id); timeline.requestLayout(); showHint(I18n.t("Đã thêm nhạc"), 1200); });
        } else if (request == PICK_IMAGE) {
          File f = copyIn(uris.get(0), "kinnect-overlay-"); Bitmap b = decodePhoto(f, 1280); if (b == null) throw new IOException(I18n.t("Không phải ảnh."));
          images.put(f.getAbsolutePath(), b);
          runOnUiThread(() -> { if (closed) return; remember(); EditorProject.Layer l = newLayer("image", 5); l.image = f; l.scale = .8f; project.layers.add(l); select("layer", l.id); showHint(I18n.t("Kéo, chụm hai ngón để đặt lớp phủ"), 1600); });
        }
      } catch (Exception | OutOfMemoryError e) { runOnUiThread(() -> showHint(I18n.t("Không thêm được: ") + e.getMessage(), 2200)); }
    });
  }

  private String displayName(Uri uri) {
    try (android.database.Cursor c = getContentResolver().query(uri, new String[] { android.provider.OpenableColumns.DISPLAY_NAME }, null, null, null)) {
      if (c != null && c.moveToFirst()) { String n = c.getString(0); int dot = n.lastIndexOf('.'); return dot > 0 ? n.substring(0, dot) : n; }
    } catch (Exception ignored) {}
    return "";
  }

  // ---------- Preview gestures ----------
  private float g0x, g0y, gDist, gAngle; private float[] gPose; private boolean gMoved, gTwo;

  private boolean previewTouch(View v, MotionEvent e) {
    if (busy || previewFrame == null) return false;
    float k = previewFrame.getWidth() / (float) Math.max(1, v.getWidth());
    switch (e.getActionMasked()) {
      case MotionEvent.ACTION_DOWN: {
        gMoved = false; gTwo = false; g0x = e.getX(); g0y = e.getY();
        Integer hit = null; for (EditorProject.Layer l : project.layers) { RectF b = render.bounds.get(l.id); if (b != null && b.contains(e.getX() * k, e.getY() * k)) hit = l.id; }
        if (hit != null && !("layer".equals(selKind) && selId == hit)) select("layer", hit);
        EditorProject.Item item = selectedItem(); gPose = item == null ? null : item.pose(localTime());
        if (item != null) { remember(); playing = false; updateButtons(); }
        return true; }
      case MotionEvent.ACTION_POINTER_DOWN:
        if (e.getPointerCount() == 2 && gPose != null) { gTwo = true; gDist = spacing(e); gAngle = angle(e); EditorProject.Item item = selectedItem(); if (item != null) gPose = item.pose(localTime()); g0x = (e.getX(0) + e.getX(1)) / 2; g0y = (e.getY(0) + e.getY(1)) / 2; }
        return true;
      case MotionEvent.ACTION_MOVE: {
        EditorProject.Item item = selectedItem(); if (item == null || gPose == null) return true; float local = localTime();
        float cx = gTwo && e.getPointerCount() >= 2 ? (e.getX(0) + e.getX(1)) / 2 : e.getX(), cy = gTwo && e.getPointerCount() >= 2 ? (e.getY(0) + e.getY(1)) / 2 : e.getY();
        if (Math.abs(cx - g0x) > dp(4) || Math.abs(cy - g0y) > dp(4)) gMoved = true; if (!gMoved && !gTwo) return true;
        float nx = gPose[EditorProject.X] + (cx - g0x) / v.getWidth(), ny = gPose[EditorProject.Y] + (cy - g0y) / v.getHeight();
        // Snap to the centre lines, like CapCut's guides.
        if (Math.abs(nx - .5f) < .015f) nx = .5f; if (Math.abs(ny - .5f) < .015f) ny = .5f;
        item.edit(local, EditorProject.X, nx); item.edit(local, EditorProject.Y, ny);
        if (gTwo && e.getPointerCount() >= 2 && gDist > 0) {
          item.edit(local, EditorProject.SCALE, Math.max(.1f, Math.min(6, gPose[EditorProject.SCALE] * spacing(e) / gDist)));
          float rot = gPose[EditorProject.ROTATION] + angle(e) - gAngle; float snap = Math.round(rot / 90f) * 90f; if (Math.abs(rot - snap) < 4) rot = snap;
          item.edit(local, EditorProject.ROTATION, rot);
        }
        dirty = true; return true; }
      case MotionEvent.ACTION_UP:
        if (!gMoved && !gTwo) {
          boolean hitLayer = false; for (RectF b : render.bounds.values()) if (b.contains(e.getX() * k, e.getY() * k)) hitLayer = true;
          if (!hitLayer) { if (selKind != null) select(null, 0); else togglePlay(); }
          if (gPose != null && !gMoved) { undo.pollLast(); updateButtons(); }
        }
        gPose = null; timeline.invalidate(); updateButtons(); return true;
      case MotionEvent.ACTION_CANCEL: gPose = null; return true;
    }
    return true;
  }
  private static float spacing(MotionEvent e) { return (float) Math.hypot(e.getX(0) - e.getX(1), e.getY(0) - e.getY(1)); }
  private static float angle(MotionEvent e) { return (float) Math.toDegrees(Math.atan2(e.getY(1) - e.getY(0), e.getX(1) - e.getX(0))); }

  // ---------- Playback engine ----------
  private Deck deckFor(EditorProject.Clip c, boolean create, Set<Integer> keep) {
    for (Deck d : decks) if (d.clipId == c.id && c.file.equals(d.file)) return d;
    if (!create) return null;
    for (Deck d : decks) if (!keep.contains(d.clipId)) { return load(d, c) ? d : null; }
    return null;
  }

  private boolean load(Deck d, EditorProject.Clip c) {
    if (d.surface == null) { if (!d.view.isAvailable()) return false; d.surface = new Surface(d.view.getSurfaceTexture()); }
    if (d.player != null) { d.player.release(); d.player = null; }
    d.clipId = c.id; d.file = c.file; d.prepared = false; d.seeking = false; d.pendingSeek = -1; d.speed = 1;
    try {
      final MediaPlayer mp = new MediaPlayer(); d.player = mp; mp.setDataSource(c.file.getPath()); mp.setSurface(d.surface); mp.setVolume(0, 0);
      mp.setOnPreparedListener(p -> { if (d.player == p) d.prepared = true; });
      mp.setOnSeekCompleteListener(p -> { if (d.player != p) return; d.seeking = false; if (d.pendingSeek >= 0) { long s = d.pendingSeek; d.pendingSeek = -1; seek(d, s); } });
      mp.setOnErrorListener((p, a, b) -> { if (d.player == p) { d.prepared = false; d.clipId = -1; } return true; });
      mp.prepareAsync(); return true;
    } catch (Exception e) { d.clipId = -1; return false; }
  }

  private void seek(Deck d, long ms) { if (!d.prepared) return; if (d.seeking) { d.pendingSeek = ms; return; } d.seeking = true; d.player.seekTo(ms, MediaPlayer.SEEK_CLOSEST); }

  /** Indices of the clips visible at t: the current clip, and the previous one while a transition runs. */
  private int[] activeClips(float t) {
    int cur = project.clipAt(t); if (cur < 0) return new int[0];
    float s = project.starts()[cur]; if (cur > 0 && t < s + project.overlap(cur)) return new int[] { cur - 1, cur };
    return new int[] { cur };
  }

  private void syncDecks(float t, boolean run) {
    int[] active = activeClips(t); float[] starts = project.starts(); Set<Integer> keep = new HashSet<>();
    for (int i : active) keep.add(project.clips.get(i).id);
    for (int idx = 0; idx < active.length; idx++) {
      int i = active[idx]; EditorProject.Clip c = project.clips.get(i); if (!c.video) continue;
      Deck d = deckFor(c, true, keep); if (d == null || !d.prepared) continue;
      float local = t - starts[i]; long expected = (long) ((c.in + local * c.speed) * 1000);
      float weight = 1; if (active.length == 2) { float u = Math.max(0, Math.min(1, (t - starts[active[1]]) / Math.max(.01f, project.overlap(active[1])))); weight = idx == 0 ? 1 - u : u; }
      float vol = exporting || micRecording || !c.hasAudio ? 0 : Math.min(1, c.volume) * weight; d.player.setVolume(vol, vol);
      try {
        if (run) {
          if (!d.player.isPlaying()) { seek(d, expected); d.player.start(); if (d.speed != c.speed) { d.player.setPlaybackParams(new PlaybackParams().setSpeed(c.speed).setPitch(1)); d.speed = c.speed; } }
          else { if (d.speed != c.speed) { d.player.setPlaybackParams(new PlaybackParams().setSpeed(c.speed).setPitch(1)); d.speed = c.speed; } if (!d.seeking && Math.abs(d.player.getCurrentPosition() - expected) > 400) seek(d, expected); }
        } else {
          if (d.player.isPlaying()) d.player.pause();
          if (!d.seeking && Math.abs(d.player.getCurrentPosition() - expected) > 45) seek(d, expected);
        }
      } catch (IllegalStateException ignored) {}
    }
    // Preload the next video clip so the cut has no gap.
    int last = active.length == 0 ? -1 : active[active.length - 1];
    if (last >= 0 && last + 1 < project.clips.size()) {
      EditorProject.Clip next = project.clips.get(last + 1);
      if (next.video && starts[last + 1] - t < 2.5f) { Deck d = deckFor(next, true, keep); if (d != null && d.prepared && !d.player.isPlaying() && !d.seeking && Math.abs(d.player.getCurrentPosition() - next.in * 1000) > 60) seek(d, (long) (next.in * 1000)); keep.add(next.id); }
    }
    for (Deck d : decks) if (d.player != null && d.prepared && !keep.contains(d.clipId)) { try { if (d.player.isPlaying()) d.player.pause(); } catch (IllegalStateException ignored) {} }
  }

  private void syncTracks(float t, boolean run) {
    Set<Integer> alive = new HashSet<>();
    for (EditorProject.Track tr : project.tracks) {
      alive.add(tr.id); TrackPlayer p = trackPlayers.get(tr.id);
      if (p == null || !p.file.equals(tr.file)) {
        if (p != null) p.mp.release(); final TrackPlayer np = new TrackPlayer(); np.file = tr.file; np.mp = new MediaPlayer(); trackPlayers.put(tr.id, np);
        try { np.mp.setDataSource(tr.file.getPath()); np.mp.setOnPreparedListener(m -> np.prepared = true); np.mp.prepareAsync(); } catch (Exception ignored) {}
        continue;
      }
      if (!p.prepared) continue;
      float local = t - tr.start; boolean on = run && local >= 0 && local < tr.length && !exporting && !(micRecording && tr.kind.equals("voice"));
      try {
        if (on) {
          float g = tr.gain; if (tr.fadeIn > 0) g *= Math.min(1, local / tr.fadeIn); if (tr.fadeOut > 0) g *= Math.min(1, (tr.length - local) / tr.fadeOut); g = Math.min(1, g); p.mp.setVolume(g, g);
          long expected = (long) ((tr.in + local) * 1000);
          if (!p.mp.isPlaying()) { p.mp.seekTo((int) expected); p.mp.start(); } else if (Math.abs(p.mp.getCurrentPosition() - expected) > 300) p.mp.seekTo((int) expected);
        } else if (p.mp.isPlaying()) p.mp.pause();
      } catch (IllegalStateException ignored) {}
    }
    for (Iterator<Map.Entry<Integer, TrackPlayer>> it = trackPlayers.entrySet().iterator(); it.hasNext();) { Map.Entry<Integer, TrackPlayer> en = it.next(); if (!alive.contains(en.getKey())) { en.getValue().mp.release(); it.remove(); } }
  }

  private Map<Integer, EditorRender.Frame> frames(float t, int maxSide) {
    Map<Integer, EditorRender.Frame> out = new HashMap<>(); int[] active = activeClips(t);
    for (int i : active) {
      EditorProject.Clip c = project.clips.get(i); EditorRender.Frame f = new EditorRender.Frame(); f.face = faceOf.get(c.id);
      if (c.video) {
        Deck d = deckFor(c, false, Collections.emptySet()); if (d == null || !d.prepared || !d.view.isAvailable()) continue;
        float k = Math.min(1, maxSide / (float) Math.max(c.width, c.height)); int w = Math.max(2, Math.round(c.width * k)), h = Math.max(2, Math.round(c.height * k));
        if (d.frame == null || d.frame.getWidth() != w || d.frame.getHeight() != h) { if (d.frame != null) d.frame.recycle(); d.frame = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888); }
        d.view.getBitmap(d.frame); f.bitmap = d.frame;
      } else f.bitmap = photos.get(c.file.getAbsolutePath());
      if (f.bitmap != null) out.put(c.id, f);
    }
    if (active.length > 0 && tick % 6 == 0 && !detecting) { EditorProject.Clip c = project.clips.get(active[active.length - 1]); EditorRender.Frame f = out.get(c.id); if (f != null && c.fx.needsFace()) detect(c.id, f.bitmap); }
    return out;
  }

  private void detect(int clipId, Bitmap source) {
    if (closed || faces.isShutdown()) return; detecting = true; int w = 320, h = Math.max(2, source.getHeight() * w / source.getWidth());
    Bitmap scaled = Bitmap.createScaledBitmap(source, w, h, true); final Bitmap small = scaled.copy(Bitmap.Config.RGB_565, false); if (scaled != source) scaled.recycle(); final float scale = source.getWidth() / (float) w;
    try {
      faces.execute(() -> {
        try { FaceDetector.Face[] found = new FaceDetector.Face[1]; int count = new FaceDetector(320, small.getHeight(), 1).findFaces(small, found);
          if (count > 0 && found[0].confidence() >= .3f) { PointF mid = new PointF(); found[0].getMidPoint(mid); faceOf.put(clipId, new float[] { mid.x * scale, mid.y * scale, found[0].eyesDistance() * scale, found[0].pose(FaceDetector.Face.EULER_Z) }); }
          else faceOf.remove(clipId);
        } finally { small.recycle(); detecting = false; }
      });
    } catch (RejectedExecutionException stopped) { small.recycle(); detecting = false; }
  }

  @Override public void doFrame(long now) {
    if (closed) return; Choreographer.getInstance().postFrameCallback(this); tick++;
    float dt = lastNanos == 0 ? 0 : Math.min(.1f, (now - lastNanos) / 1e9f); lastNanos = now;
    if (project.clips.isEmpty()) return; float duration = project.duration();
    if (micRecording && micTimer != null && tick % 6 == 0) micTimer.setText(I18n.t("● Đang ghi ") + TimelineView.clock((SystemClock.elapsedRealtime() - micStarted) / 1000f) + I18n.t(" · bấm để dừng"));
    if (exporting) { exportFrame(duration); return; }
    if (playing) { playhead += dt; if (playhead >= duration) { playhead = duration; playing = false; updateButtons(); } }
    syncDecks(playhead, playing); syncTracks(playhead, playing);
    long ms = SystemClock.uptimeMillis(); if (ms - lastDraw < 30) return; lastDraw = ms;
    if (!preview.getHolder().getSurface().isValid() || preview.getWidth() <= 0) return;
    float k = Math.min(1, 720f / Math.max(preview.getWidth(), preview.getHeight())); int w = Math.max(2, Math.round(preview.getWidth() * k)), h = Math.max(2, Math.round(preview.getHeight() * k));
    if (previewFrame == null || previewFrame.getWidth() != w || previewFrame.getHeight() != h) { if (previewFrame != null) previewFrame.recycle(); previewFrame = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888); }
    render.draw(new Canvas(previewFrame), project, playhead, frames(playhead, 720), images, tick, true);
    Canvas c = null;
    try {
      c = preview.getHolder().lockCanvas(); if (c == null) return;
      c.drawBitmap(previewFrame, null, new Rect(0, 0, c.getWidth(), c.getHeight()), null); selectionOverlay(c, c.getWidth() / (float) w);
    } catch (Exception ignored) {} finally { if (c != null) preview.getHolder().unlockCanvasAndPost(c); }
    if (playing || tick % 8 == 0) { timeline.invalidate(); updateTime(); }
  }

  private final Paint guide = new Paint(Paint.ANTI_ALIAS_FLAG);
  private void selectionOverlay(Canvas c, float k) {
    if (!"layer".equals(selKind)) return; RectF b = render.bounds.get(selId); if (b == null) return; Float a = render.angles.get(selId);
    guide.setStyle(Paint.Style.STROKE); guide.setStrokeWidth(dp(1.5f)); guide.setColor(Color.WHITE);
    c.save(); c.scale(k, k); c.rotate(a == null ? 0 : a, b.centerX(), b.centerY()); c.drawRect(b, guide);
    guide.setStyle(Paint.Style.FILL); for (float[] p : new float[][] { { b.left, b.top }, { b.right, b.top }, { b.left, b.bottom }, { b.right, b.bottom } }) c.drawCircle(p[0], p[1], dp(4) / k, guide);
    c.restore();
    if (gPose != null && gMoved) { guide.setColor(0x88ffd45c); guide.setStrokeWidth(dp(1)); EditorProject.Item item = selectedItem(); if (item != null) { float[] p = item.pose(localTime()); if (p[0] == .5f) c.drawLine(c.getWidth() / 2f, 0, c.getWidth() / 2f, c.getHeight(), guide); if (p[1] == .5f) c.drawLine(0, c.getHeight() / 2f, c.getWidth(), c.getHeight() / 2f, guide); } }
  }

  @Override public void onBackPressed() {
    if (exporting) { cancelExport(I18n.t("Đã hủy xuất.")); return; }
    if (captions != null) { captions.cancel(); captions = null; busy = false; }
    if (sheet.getVisibility() == View.VISIBLE) { closeSheet(); return; }
    if (selKind != null) { select(null, 0); return; }
    requestExit();
  }

  private void requestExit(){if(exporting){cancelExport(I18n.t("Đã hủy xuất."));return;}new Sheet(this).setTitle(I18n.t("Thoát Studio Pro?")).setMessage(I18n.t("Thoát không lưu sẽ bỏ chỉnh sửa video hiện tại. Video gốc vẫn được giữ nguyên.")).setPositiveButton(I18n.t("Thoát không lưu"),(d,w)->{if(captions!=null){captions.cancel();captions=null;}if(micRecording)stopMic();setResult(RESULT_CANCELED);finish();}).setNegativeButton(I18n.t("Tiếp tục chỉnh sửa"),null).show();}

  // ---------- Export ----------
  private void export(boolean save) {
    if(proApplied){NativeApi.shared.call("GET","/api/store",null,(catalog,error,status)->{if(closed)return;boolean owned=catalog!=null&&catalog.optBoolean("studioProFree");org.json.JSONArray ids=catalog==null?null:catalog.optJSONArray("owned");for(int i=0;ids!=null&&i<ids.length();i++)if(ids.optString(i).equals("kinnect_studio_pro"))owned=true;if(error!=null||!owned){showHint(I18n.t("Cần xác minh quyền Studio Pro trước khi xuất. Bạn có thể gỡ mẫu Pro để dùng công cụ miễn phí."),3000);return;}exportReady(save);});return;}
    exportReady(save);
  }
  private void exportReady(boolean save) {
    if (busy || project.clips.isEmpty()) return; saveRequested = save; closeSheet(); playing = false; updateButtons();
    EditorProject.Clip only = project.clips.size() == 1 ? project.clips.get(0) : null;
    if (!dirty && only != null && only.file.equals(input)) { deliver(input); return; }
    if (project.still()) { exportStill(); return; }
    startExport();
  }

  private void exportStill() {
    busy = true;
    try {
      EditorProject.Clip c = project.clips.get(0); Bitmap photo = photos.get(c.file.getAbsolutePath()); if (photo == null) throw new IOException(I18n.t("Ảnh chưa sẵn sàng."));
      EditorProject copy = project.copy(); float t = c.length() / 2; for (EditorProject.Layer l : copy.layers) { l.start = 0; l.length = c.length(); l.animIn = l.animOut = "none"; }
      float ratio = project.outputAspect(); int side = Math.max(photo.getWidth(), photo.getHeight()); int w = ratio >= 1 ? side : Math.round(side * ratio), h = ratio >= 1 ? Math.round(side / ratio) : side;
      Bitmap output = Bitmap.createBitmap(Math.max(2, w), Math.max(2, h), Bitmap.Config.ARGB_8888);
      Map<Integer, EditorRender.Frame> frames = new HashMap<>(); EditorRender.Frame f = new EditorRender.Frame(); f.bitmap = photo; f.face = faceOf.get(c.id); frames.put(copy.clips.get(0).id, f);
      new EditorRender().draw(new Canvas(output), copy, t, frames, images, tick, false);
      File file = File.createTempFile("kinnect-edited-", ".jpg", getCacheDir()); try (OutputStream out = new FileOutputStream(file)) { output.compress(Bitmap.CompressFormat.JPEG, 94, out); } output.recycle();
      deliver(file);
    } catch (Exception | OutOfMemoryError error) { busy = false; showHint(I18n.t("Không xuất được ảnh. Hãy thử lại."), 2000); }
  }

  private void startExport() {
    try {
      busy = true; float ratio = project.outputAspect(); int side = project.exportSide;
      // The short side gets the chosen resolution (1080p = 1080×1920 for 9:16).
      int w, h; if (ratio < 1) { w = side & ~1; h = Math.round(side / ratio) & ~1; } else { h = side & ~1; w = Math.round(side * ratio) & ~1; }
      rendered = File.createTempFile("kinnect-effects-", ".mp4", getCacheDir()); recorder = new MediaRecorder();
      recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE); recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4); recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264);
      recorder.setVideoSize(w, h); recorder.setVideoFrameRate(30); recorder.setVideoEncodingBitRate(side >= 1080 ? 10_000_000 : side >= 720 ? 6_000_000 : 3_000_000);
      recorder.setOutputFile(rendered.getPath()); recorder.prepare(); recordSurface = recorder.getSurface();
      if (exportFrame != null) exportFrame.recycle(); exportFrame = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
      exporting = true; armed = false; armWait = SystemClock.elapsedRealtime(); playhead = 0; exportGeneration++;
      exportCover.setVisibility(View.VISIBLE); exportBar.setProgress(0); exportText.setText(I18n.t("Đang chuẩn bị…"));
    } catch (Exception error) { cancelExport(I18n.t("Không xuất được video: ") + error.getMessage()); }
  }

  private void exportFrame(float duration) {
    if (!armed) {
      syncDecks(0, false); EditorProject.Clip first = project.clips.get(0); Deck d = first.video ? deckFor(first, false, Collections.emptySet()) : null;
      boolean ready = !first.video || d != null && d.prepared && !d.seeking;
      if (!ready && SystemClock.elapsedRealtime() - armWait < 5000) return;
      try { recorder.start(); } catch (Exception e) { cancelExport(I18n.t("Không khởi động được bộ xuất video.")); return; }
      armed = true; exportStart = SystemClock.elapsedRealtime(); lastPost = 0;
    }
    playhead = Math.min(duration, (SystemClock.elapsedRealtime() - exportStart) / 1000f);
    syncDecks(playhead, true);
    long ms = SystemClock.elapsedRealtime();
    if (ms - lastPost >= 33 || playhead >= duration) {
      lastPost = ms; render.draw(new Canvas(exportFrame), project, playhead, frames(playhead, Math.min(1920, Math.max(exportFrame.getWidth(), exportFrame.getHeight()))), images, tick, false);
      try { Canvas c = recordSurface.lockHardwareCanvas(); try { c.drawBitmap(exportFrame, 0, 0, null); } finally { recordSurface.unlockCanvasAndPost(c); } }
      catch (Exception error) { cancelExport(I18n.t("Không xuất được hiệu ứng trên thiết bị này.")); return; }
      if (preview.getHolder().getSurface().isValid()) { Canvas c = null; try { c = preview.getHolder().lockCanvas(); if (c != null) c.drawBitmap(exportFrame, null, new Rect(0, 0, c.getWidth(), c.getHeight()), null); } catch (Exception ignored) {} finally { if (c != null) preview.getHolder().unlockCanvasAndPost(c); } }
      int pct = Math.round(playhead / Math.max(.01f, duration) * 90); exportBar.setProgress(pct); exportText.setText(I18n.t("Đang xuất ") + pct + "%"); timeline.invalidate(); updateTime();
    }
    if (playhead >= duration) finishExport();
  }

  private void finishExport() {
    exporting = false; armed = false;
    try { recorder.stop(); recorder.release(); recorder = null; recordSurface.release(); recordSurface = null; } catch (Exception e) { cancelExport(I18n.t("Video chưa hoàn tất. Hãy thử lại.")); return; }
    syncDecks(playhead, false); exportText.setText(I18n.t("Đang ghép âm thanh…")); exportBar.setProgress(92);
    final List<EditorAudio.Source> sources = new ArrayList<>(); float[] starts = project.starts();
    for (int i = 0; i < project.clips.size(); i++) {
      EditorProject.Clip c = project.clips.get(i); if (!c.video || !c.hasAudio || c.volume <= 0) continue;
      EditorAudio.Source s = new EditorAudio.Source(); s.file = c.file; s.start = starts[i]; s.length = c.length(); s.in = c.in; s.rate = c.speed; s.gain = c.volume;
      s.fadeIn = project.overlap(i); s.fadeOut = i + 1 < project.clips.size() ? project.overlap(i + 1) : 0; sources.add(s);
    }
    for (EditorProject.Track t : project.tracks) { EditorAudio.Source s = new EditorAudio.Source(); s.file = t.file; s.start = t.start; s.length = Math.min(t.length, project.duration() - t.start); s.in = t.in; s.gain = t.gain; s.fadeIn = t.fadeIn; s.fadeOut = t.fadeOut; if (s.length > 0) sources.add(s); }
    final long ms = (long) (project.duration() * 1000); final int generation = exportGeneration; final File video = rendered;
    task = worker.submit(() -> {
      try {
        File output = File.createTempFile("kinnect-edited-", ".mp4", getCacheDir()); EditorAudio.timeline(this, video, sources, ms, output);
        runOnUiThread(() -> { if (!closed && generation == exportGeneration) { exportCover.setVisibility(View.GONE); deliver(output); } else output.delete(); });
      } catch (Exception e) { runOnUiThread(() -> { if (!closed && generation == exportGeneration) cancelExport(I18n.t("Không ghép được âm thanh: ") + e.getMessage()); }); }
    });
  }

  private void cancelExport(String message) {
    exportGeneration++; exporting = false; armed = false; busy = false; if (task != null) task.cancel(true);
    if (recorder != null) { try { recorder.stop(); } catch (Exception ignored) {} recorder.release(); recorder = null; }
    if (recordSurface != null) { recordSurface.release(); recordSurface = null; }
    exportCover.setVisibility(View.GONE); playing = false; updateButtons(); showHint(message, 2200);
  }

  private void deliver(File file) {
    if (saveRequested) {
      saveFile = file; busy = false;
      try {
        byte[] header = new byte[32]; try (InputStream in = new FileInputStream(file)) { in.read(header); } String mime = MediaType.sniff(header); if (mime == null) mime = project.still() ? "image/jpeg" : "video/mp4";
        Intent save = new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(mime).putExtra(Intent.EXTRA_TITLE, "Kinnect-" + System.currentTimeMillis() + (mime.equals("video/mp4") ? ".mp4" : mime.equals("image/png") ? ".png" : mime.equals("image/webp") ? ".webp" : ".jpg"));
        startActivityForResult(save, SAVE);
      } catch (Exception error) { showHint(I18n.t("Không mở được nơi lưu tệp."), 1800); saveRequested = false; }
      return;
    }
    delivered = file == input; Intent result = new Intent().setData(Uri.fromFile(file)); result.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION); setResult(RESULT_OK, result); finish();
  }

  private void saved(int result, Intent data) {
    saveRequested = false;
    if (result != RESULT_OK || data == null || data.getData() == null || saveFile == null) { showHint(I18n.t("Đã hủy lưu. Bạn có thể chỉnh tiếp."), 1600); return; }
    final Uri destination = data.getData(); final File file = saveFile; busy = true; showHint(I18n.t("Đang lưu…"), 0);
    task = worker.submit(() -> {
      try (InputStream in = new FileInputStream(file); OutputStream out = getContentResolver().openOutputStream(destination)) {
        if (out == null) throw new IOException(I18n.t("Không mở được nơi lưu.")); byte[] buffer = new byte[65536]; int n; while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
        runOnUiThread(() -> { busy = false; showHint(I18n.t("✓ Đã lưu về máy"), 1600); });
      } catch (Exception error) { runOnUiThread(() -> { busy = false; showHint(I18n.t("Không lưu được tệp. Hãy thử lại."), 1800); }); }
    });
  }

  @Override protected void onPause() {
    super.onPause(); if (exporting) cancelExport(I18n.t("Xuất bị gián đoạn. Hãy giữ màn hình mở và thử lại.")); if (micRecording) stopMic();
    playing = false; updateButtons(); syncDecks(playhead, false); syncTracks(playhead, false);
  }

  @Override protected void onDestroy() {
    closed = true; Choreographer.getInstance().removeFrameCallback(this); if (task != null) task.cancel(true); if (captions != null) captions.cancel();
    worker.shutdownNow(); loader.shutdownNow(); faces.shutdownNow();
    for (Deck d : decks) { if (d.player != null) d.player.release(); if (d.surface != null) d.surface.release(); }
    for (TrackPlayer p : trackPlayers.values()) p.mp.release();
    if (mic != null) { try { mic.stop(); } catch (Exception ignored) {} mic.release(); }
    if (recorder != null) { try { recorder.stop(); } catch (Exception ignored) {} recorder.release(); }
    if (recordSurface != null) recordSurface.release();
    if (rendered != null) rendered.delete();
    // Clean up copies the result does not point at.
    Set<File> files = new HashSet<>(); for (EditorProject.Clip c : project.clips) files.add(c.file);
    for (File f : files) if (!(delivered && f.equals(input))) f.delete();
    super.onDestroy();
  }
}
