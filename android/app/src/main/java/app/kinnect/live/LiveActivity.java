package app.kinnect.live;

import android.Manifest;
import android.app.*;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.view.*;
import android.widget.*;
import org.json.*;
import org.webrtc.SurfaceViewRenderer;

/** Sảnh live, phát và xem trực tiếp, trò chuyện trong phòng — giao diện theo bản web. Không dùng WebView. */
public final class LiveActivity extends Activity implements NativeSocket.Events {
  static final String EXTRA_ROOM = "room";
  static final String EXTRA_HOST = "host";
  private LinearLayout root, rooms, chat;
  private TextView status;
  private NativeSocket socket;
  private NativeRtc rtc;
  private JSONObject config;
  private boolean host, joined, ready;
  private EditText topic, filter;
  private JSONArray lastRooms;
  private android.media.AudioManager audio;
  private int previousMode;
  private boolean previousSpeaker;
  private int BG, CARD, TEXT, MUTED, ACCENT, SOFT, LINE;

  private int dp(int n) { return Math.round(n * getResources().getDisplayMetrics().density); }

  private LinearLayout column() { LinearLayout c = new LinearLayout(this); c.setOrientation(LinearLayout.VERTICAL); return c; }

  private LinearLayout row() { LinearLayout c = new LinearLayout(this); c.setGravity(Gravity.CENTER_VERTICAL); return c; }

  private GradientDrawable round(int color, int r) { GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(r)); return d; }

  private GradientDrawable gradient(int r) { GradientDrawable d = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6c47e0, 0xff6c47e0 }); d.setCornerRadius(dp(r)); return d; }

  private TextView text(String s, int size, int color) { TextView v = new TextView(this); v.setText(s); v.setTextSize(size); v.setTextColor(color); return v; }

  private ImageView icon(String name, int color) {
    ImageView v = new ImageView(this);
    int id = WebIcons.resolve(this, name);
    if (id != 0) { android.graphics.drawable.Drawable d = WebIcons.load(this, name); d.setTint(color); v.setImageDrawable(d); }
    return v;
  }

  private TextView pill(String label, boolean primary, Runnable click) {
    TextView b = text(label, 15, primary ? 0xffffffff : TEXT);
    b.setTypeface(null, Typeface.BOLD);
    b.setGravity(Gravity.CENTER);
    b.setPadding(dp(16), 0, dp(16), 0);
    b.setBackground(primary ? gradient(14) : round(SOFT, 14));
    b.setOnClickListener(v -> click.run());
    return b;
  }

  private EditText field(String hint) {
    EditText e = new EditText(this);
    e.setHint(hint);
    e.setTextColor(TEXT);
    e.setHintTextColor(MUTED);
    e.setTextSize(15);
    e.setSingleLine(true);
    e.setPadding(dp(16), 0, dp(16), 0);
    e.setBackground(round(SOFT, 14));
    return e;
  }

  @Override
  public void onCreate(Bundle state) {
    boolean dark = WebTheme.isDark(this);
    setTheme(dark ? android.R.style.Theme_Material_NoActionBar : android.R.style.Theme_Material_Light_NoActionBar);
    super.onCreate(state);
    CrashLog.install(this);
    int variant = dark ? 1 : 0;
    BG = WebDesign.BG[variant]; CARD = WebDesign.CARD[variant]; TEXT = WebDesign.INK[variant];
    MUTED = WebDesign.MUTED[variant]; ACCENT = WebDesign.PURPLE[variant]; SOFT = WebDesign.WASH[variant]; LINE = WebDesign.LINE[variant];
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    if (!dark) getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    root = column();
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener((v, i) -> { v.setPadding(0, i.getSystemWindowInsetTop(), 0, i.getSystemWindowInsetBottom()); return i; });
    setContentView(root);
    lobby();
    String origin = ServerConfig.DEFAULT_ORIGIN;
    NativeApi.shared.call("GET", "/api/call-config", null, (data, error, code) -> {
      if (isFinishing() || isDestroyed()) return;
      if (error != null) { status.setText(error); return; }
      config = data;
      socket = new NativeSocket(origin, this);
    });
    audio = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
    previousMode = audio.getMode();
    previousSpeaker = audio.isSpeakerphoneOn();
  }

  // Sảnh giống web: danh sách buổi live dạng thẻ dọc; phát live bằng nút nổi.
  private void lobby() {
    LinearLayout bar = row();
    bar.setBackgroundColor(CARD);
    bar.setElevation(dp(1));
    bar.setPadding(dp(6), 0, dp(16), 0);
    ImageView back = icon("back", TEXT);
    back.setPadding(dp(10), dp(10), dp(10), dp(10));
    back.setContentDescription("Quay lại");
    back.setOnClickListener(v -> finish());
    bar.addView(back, new LinearLayout.LayoutParams(dp(44), dp(44)));
    TextView brand = text("Trực tiếp", 19, TEXT);
    brand.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    brand.setPadding(dp(4), 0, dp(8), 0);
    bar.addView(brand);
    View dot = new View(this);
    dot.setBackground(round(0xfffe2c55, 99));
    bar.addView(dot, new LinearLayout.LayoutParams(dp(8), dp(8)));
    bar.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    ImageView refresh = icon("rotate_ccw", TEXT);
    refresh.setPadding(dp(10), dp(10), dp(10), dp(10));
    refresh.setContentDescription("Làm mới");
    refresh.setOnClickListener(v -> renderRooms());
    bar.addView(refresh, new LinearLayout.LayoutParams(dp(44), dp(44)));
    root.addView(bar, new LinearLayout.LayoutParams(-1, dp(56)));

    FrameLayout stage = new FrameLayout(this);
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    LinearLayout c = column();
    c.setPadding(dp(14), dp(14), dp(14), dp(96));
    scroll.addView(c);
    stage.addView(scroll, new FrameLayout.LayoutParams(-1, -1));
    status = text("Đang kết nối…", 14, MUTED);
    status.setGravity(Gravity.CENTER);
    status.setPadding(0, dp(140), 0, 0);
    c.addView(status, new LinearLayout.LayoutParams(-1, -2));
    rooms = column();
    c.addView(rooms, new LinearLayout.LayoutParams(-1, -2));

    LinearLayout fab = row();
    fab.setGravity(Gravity.CENTER);
    fab.setPadding(dp(20), 0, dp(22), 0);
    GradientDrawable fg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xfffe2c55, 0xffff4f9a });
    fg.setCornerRadius(dp(99));
    fab.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff), fg, null));
    fab.setElevation(dp(8));
    fab.addView(icon("radio", 0xffffffff), new LinearLayout.LayoutParams(dp(20), dp(20)));
    TextView fl = text("Phát live", 15, 0xffffffff);
    fl.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    fl.setPadding(dp(8), 0, 0, 0);
    fab.addView(fl);
    fab.setContentDescription("Phát trực tiếp");
    fab.setOnClickListener(v -> askTitleAndHost());
    FrameLayout.LayoutParams fp = new FrameLayout.LayoutParams(-2, dp(52), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    fp.bottomMargin = dp(20);
    stage.addView(fab, fp);
    root.addView(stage, new LinearLayout.LayoutParams(-1, 0, 1));
  }

  private void askTitleAndHost() {
    if (isFinishing() || isDestroyed()) return;
    if (socket == null || !ready) { Toast.makeText(this, "Đang kết nối, thử lại sau giây lát.", Toast.LENGTH_SHORT).show(); return; }
    final EditText input = new EditText(this);
    input.setHint("Chủ đề buổi live");
    input.setSingleLine(true);
    input.setTextColor(TEXT);
    input.setHintTextColor(MUTED);
    input.setPadding(dp(14), dp(12), dp(14), dp(12));
    GradientDrawable ib = round(CARD, 14);
    ib.setStroke(dp(1), LINE);
    input.setBackground(ib);
    FrameLayout wrap = new FrameLayout(this);
    wrap.setPadding(dp(4), dp(4), dp(4), 0);
    wrap.addView(input, new FrameLayout.LayoutParams(-1, dp(50)));
    new Sheet(this).setTitle("Phát trực tiếp").setView(wrap).setPositiveButton("Lên sóng", (d, w) -> {
      String t = input.getText().toString().trim();
      topicText = t.isEmpty() ? "Trò chuyện cùng Kinnect" : t;
      prepareHost();
    }).setNegativeButton("Huỷ", null).show();
  }

  private String topicText = "";

  private void renderRooms() {
    if (rooms == null) return;
    rooms.removeAllViews();
    boolean any = lastRooms != null && lastRooms.length() > 0;
    if (!ready || any) {
      status.setText(ready ? "Đang mở buổi live…" : "Đang kết nối…");
      status.setVisibility(View.VISIBLE);
      return;
    }
    status.setVisibility(View.GONE);
    LinearLayout empty = column();
    empty.setGravity(Gravity.CENTER_HORIZONTAL);
    empty.setPadding(dp(20), dp(110), dp(20), 0);
    FrameLayout bubble = new FrameLayout(this);
    bubble.setBackground(round(WebDesign.SOFT[WebTheme.isDark(this) ? 1 : 0], 99));
    bubble.addView(icon("radio", ACCENT), new FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER));
    empty.addView(bubble, new LinearLayout.LayoutParams(dp(72), dp(72)));
    TextView t = text("Chưa có buổi live", 18, TEXT);
    t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    t.setPadding(0, dp(16), 0, dp(4));
    empty.addView(t);
    empty.addView(text("Hãy là người mở màn!", 14, MUTED));
    rooms.addView(empty, new LinearLayout.LayoutParams(-1, -2));
  }

  private void prepareHost() {
    if (socket == null || !ready) { Toast.makeText(this, "Đang kết nối máy chủ, thử lại sau giây lát.", Toast.LENGTH_SHORT).show(); return; }
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      requestPermissions(new String[] { Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO }, 301);
      return;
    }
    host = true;
    socket.send(NativeSocket.json("type", "create", "title", topicText.isEmpty() ? "Trò chuyện cùng Kinnect" : topicText));
  }

  public void onRequestPermissionsResult(int code, String[] p, int[] grants) {
    super.onRequestPermissionsResult(code, p, grants);
    if (code == 301) {
      if (grants.length == 2 && grants[0] == 0 && grants[1] == 0) prepareHost();
      else { status.setText("Cần quyền camera và micro để phát trực tiếp."); status.setVisibility(View.VISIBLE); }
    }
  }

  public void event(JSONObject m) {
    String type = m.optString("type");
    if (type.equals("welcome")) {
      ready = true;
      renderRooms();
      // Mở từ tab "Trực tiếp": vào thẳng phòng đã chọn.
      String room = getIntent().getStringExtra(EXTRA_ROOM);
      if (room != null && !joined) { host = false; socket.send(NativeSocket.json("type", "join", "room", room)); getIntent().removeExtra(EXTRA_ROOM); }
      if (getIntent().getBooleanExtra(EXTRA_HOST, false) && !joined) { getIntent().removeExtra(EXTRA_HOST); askTitleAndHost(); }
    }
    if (type.equals("rooms")) { lastRooms = m.optJSONArray("rooms"); if (!joined) { renderRooms(); autoJoin(); } }
    if (type.equals("joined")) { joined = true; joining = false; showRoom(m); }
    if (type.equals("peer") && rtc != null) rtc.offer(m.optString("id"));
    if (type.equals("signal") && rtc != null) rtc.signal(m.optString("from"), m);
    if (type.equals("peer-left") && rtc != null) rtc.remove(m.optString("id"));
    if (type.equals("count") && viewers != null) viewers.setText(m.optInt("viewers") + " đang xem");
    if (type.equals("chat") && chat != null) addChat(m.optString("name"), m.optString("text"));
    if (type.equals("room-ended") || type.equals("ended")) { if (host) { Toast.makeText(this, "Buổi trực tiếp đã kết thúc.", Toast.LENGTH_LONG).show(); finish(); } else roomEnded(); }
    if (type.equals("error")) { status.setText(m.optString("message")); status.setVisibility(View.VISIBLE); }
  }

  private TextView viewers;
  private ScrollView chatScroll;
  private boolean joining;
  private String currentRoom = "";
  private FrameLayout liveStage;
  private long swipeAt;

  private void autoJoin() {
    if (joined || joining || host || socket == null || !ready || lastRooms == null || lastRooms.length() == 0) return;
    if (getIntent().getBooleanExtra(EXTRA_HOST, false)) return;
    JSONObject first = lastRooms.optJSONObject(0);
    if (first == null) return;
    joining = true;
    socket.send(NativeSocket.json("type", "join", "room", first.optString("id")));
  }

  private int roomIndex(String id) {
    for (int i = 0; lastRooms != null && i < lastRooms.length(); i++) if (lastRooms.optJSONObject(i).optString("id").equals(id)) return i;
    return -1;
  }

  private void switchLive(final int direction) {
    if (System.currentTimeMillis() - swipeAt < 900 || joining) return;
    int index = roomIndex(currentRoom);
    final JSONObject next = lastRooms == null ? null : lastRooms.optJSONObject(index + direction);
    if (index < 0 || next == null) { Toast.makeText(this, direction > 0 ? "Bạn đã xem đến buổi live cuối." : "Đây là buổi live đầu tiên.", Toast.LENGTH_SHORT).show(); return; }
    swipeAt = System.currentTimeMillis();
    joining = true;
    final View stage = liveStage;
    Runnable go = () -> {
      socket.send(NativeSocket.json("type", "leave"));
      if (rtc != null) { rtc.close(); rtc = null; }
      joined = false;
      socket.send(NativeSocket.json("type", "join", "room", next.optString("id")));
    };
    if (stage == null) { go.run(); return; }
    stage.animate().translationY(-direction * stage.getHeight()).alpha(0.4f).setDuration(220).withEndAction(go).start();
  }

  private void roomEnded() {
    if (rtc != null) { rtc.close(); rtc = null; }
    joined = false;
    int index = roomIndex(currentRoom);
    if (lastRooms != null && index >= 0) {
      JSONArray rest = new JSONArray();
      for (int i = 0; i < lastRooms.length(); i++) if (i != index) rest.put(lastRooms.optJSONObject(i));
      lastRooms = rest;
    }
    Toast.makeText(this, "Buổi live đã kết thúc.", Toast.LENGTH_SHORT).show();
    root.removeAllViews();
    boolean dark = WebTheme.isDark(this);
    root.setBackgroundColor(BG);
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    if (!dark) getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    lobby();
    renderRooms();
    autoJoin();
  }

  private void addChat(String name, String body) {
    TextView t = new TextView(this);
    android.text.SpannableStringBuilder sb = new android.text.SpannableStringBuilder(name + "  ");
    sb.setSpan(new android.text.style.StyleSpan(Typeface.BOLD), 0, name.length(), 0);
    sb.setSpan(new android.text.style.ForegroundColorSpan(0xffd6c7ff), 0, name.length(), 0);
    sb.append(body);
    t.setText(sb);
    t.setTextColor(0xffffffff);
    t.setTextSize(12);
    t.setLineSpacing(0, 1.3f);
    t.setPadding(dp(9), dp(5), dp(9), dp(5));
    t.setBackground(round(0x5516121e, 10));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, -2);
    p.topMargin = dp(4);
    chat.addView(t, p);
    while (chat.getChildCount() > 40) chat.removeViewAt(0);
    chatScroll.post(() -> chatScroll.fullScroll(View.FOCUS_DOWN));
  }

  // Phòng live giống web (live-immersive): video toàn màn, thẻ chủ live, cột thao tác bên phải, chat nổi.
  private void showRoom(JSONObject m) {
    root.removeAllViews();
    root.setBackgroundColor(0xff000000);
    getWindow().setStatusBarColor(0xff000000);
    getWindow().setNavigationBarColor(0xff000000);
    getWindow().getDecorView().setSystemUiVisibility(0);
    final JSONObject room = m.optJSONObject("room") == null ? new JSONObject() : m.optJSONObject("room");
    FrameLayout stage = new FrameLayout(this);
    root.addView(stage, new LinearLayout.LayoutParams(-1, 0, 1));
    currentRoom = m.optJSONObject("room") == null ? "" : m.optJSONObject("room").optString("id");
    liveStage = stage;
    if (!host) {
      final GestureDetector swipe = new GestureDetector(this, new GestureDetector.SimpleOnGestureListener() {
        public boolean onDown(MotionEvent e) { return true; }
        public boolean onFling(MotionEvent a, MotionEvent b, float vx, float vy) {
          if (a == null || b == null) return false;
          float dy = b.getY() - a.getY();
          if (Math.abs(dy) > dp(70) && Math.abs(vy) > Math.abs(vx)) { switchLive(dy < 0 ? 1 : -1); return true; }
          return false;
        }
      });
      stage.setOnTouchListener((v, e) -> swipe.onTouchEvent(e));
      TextView hint = text("Vuốt lên để xem live khác", 12, 0xccffffff);
      hint.setShadowLayer(4, 0, 1, 0xcc000000);
      hint.setGravity(Gravity.CENTER);
      FrameLayout.LayoutParams hp = new FrameLayout.LayoutParams(-1, -2, Gravity.CENTER);
      stage.addView(hint, hp);
      hint.animate().alpha(0f).setStartDelay(2500).setDuration(600).start();
    }
    SurfaceViewRenderer display = new SurfaceViewRenderer(this);
    stage.addView(display, new FrameLayout.LayoutParams(-1, -1));
    View shade = new View(this);
    shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x66000000, 0x00000000, 0x00000000, 0x88000000 }));
    stage.addView(shade, new FrameLayout.LayoutParams(-1, -1));

    LinearLayout center = column();
    center.setGravity(Gravity.CENTER_HORIZONTAL);
    center.addView(icon("radio", 0xa6ffffff), new LinearLayout.LayoutParams(dp(34), dp(34)));
    status = text(host ? "Bạn đang phát trực tiếp" : "Đang kết nối buổi live…", 12, 0xa6ffffff);
    status.setGravity(Gravity.CENTER);
    status.setPadding(0, dp(12), 0, 0);
    center.addView(status);
    final LinearLayout statusBox = center;
    stage.addView(center, new FrameLayout.LayoutParams(-1, -2, Gravity.CENTER));

    String hostName = room.optString("host", host ? "Bạn" : "Chủ buổi live");
    LinearLayout heading = row();
    LinearLayout chip = row();
    chip.setPadding(dp(5), dp(5), dp(12), dp(5));
    chip.setBackground(round(0x7016121e, 28));
    TextView hav = text(hostName.isEmpty() ? "K" : hostName.substring(0, 1).toUpperCase(), 13, 0xffffffff);
    hav.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    hav.setGravity(Gravity.CENTER);
    GradientDrawable ring = round(0xff6c47e0, 99);
    ring.setStroke(dp(1), 0x88ffffff);
    hav.setBackground(ring);
    chip.addView(hav, new LinearLayout.LayoutParams(dp(35), dp(35)));
    LinearLayout who = column();
    who.setPadding(dp(8), 0, 0, 0);
    TextView hn = text(hostName, 12, 0xffffffff);
    hn.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    hn.setSingleLine(true);
    hn.setEllipsize(android.text.TextUtils.TruncateAt.END);
    who.addView(hn);
    LinearLayout meta = row();
    TextView pillTag = text("LIVE", 8, 0xffffffff);
    pillTag.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    pillTag.setPadding(dp(4), dp(1), dp(4), dp(1));
    pillTag.setBackground(round(0xfffe2c55, 3));
    meta.addView(pillTag);
    viewers = text(room.optInt("viewers") + " đang xem", 10, 0xffffffff);
    viewers.setPadding(dp(7), 0, 0, 0);
    meta.addView(viewers);
    LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(-2, -2);
    mp.topMargin = dp(3);
    who.addView(meta, mp);
    chip.addView(who);
    heading.addView(chip, new LinearLayout.LayoutParams(-2, dp(46)));
    heading.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    FrameLayout close = new FrameLayout(this);
    close.setBackground(round(0x7016121e, 99));
    close.addView(icon("close", 0xffffffff), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    close.setContentDescription(host ? "Kết thúc live" : "Rời live");
    close.setOnClickListener(v -> { if (socket != null) socket.send(NativeSocket.json("type", "leave")); finish(); });
    heading.addView(close, new LinearLayout.LayoutParams(dp(34), dp(34)));
    FrameLayout.LayoutParams hp = new FrameLayout.LayoutParams(-1, -2, Gravity.TOP);
    hp.setMargins(dp(12), dp(12), dp(12), 0);
    stage.addView(heading, hp);
    TextView title = text(room.optString("title"), 13, 0xffffffff);
    title.setShadowLayer(4, 0, 1, 0xff000000);
    title.setLineSpacing(0, 1.2f);
    FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-1, -2, Gravity.TOP);
    tp.setMargins(dp(16), dp(70), dp(70), 0);
    stage.addView(title, tp);

    LinearLayout side = column();
    side.setGravity(Gravity.CENTER_HORIZONTAL);
    final String hostId = room.optString("hostId");
    if (!host && !hostId.isEmpty()) {
      FrameLayout author = new FrameLayout(this);
      TextView big = text(hostName.isEmpty() ? "K" : hostName.substring(0, 1).toUpperCase(), 18, 0xffffffff);
      big.setGravity(Gravity.CENTER);
      GradientDrawable br = round(0xff6c47e0, 99);
      br.setStroke(dp(2), 0xffffffff);
      big.setBackground(br);
      author.addView(big, new FrameLayout.LayoutParams(dp(50), dp(50), Gravity.TOP | Gravity.CENTER_HORIZONTAL));
      final boolean[] following = { room.optBoolean("following") };
      final FrameLayout badge = new FrameLayout(this);
      GradientDrawable bb = round(following[0] ? ACCENT : 0xfffe2c55, 99);
      bb.setStroke(dp(2), 0xffffffff);
      badge.setBackground(bb);
      final ImageView plus = icon(following[0] ? "check" : "plus", 0xffffffff);
      badge.addView(plus, new FrameLayout.LayoutParams(dp(12), dp(12), Gravity.CENTER));
      badge.setContentDescription(following[0] ? "Huỷ theo dõi" : "Theo dõi");
      badge.setOnClickListener(v -> NativeApi.shared.call(following[0] ? "DELETE" : "POST", "/api/users/" + hostId + "/follow", new JSONObject(), (d, e, s) -> {
        if (e != null || isDestroyed()) return;
        following[0] = !following[0];
        GradientDrawable nb = round(following[0] ? ACCENT : 0xfffe2c55, 99);
        nb.setStroke(dp(2), 0xffffffff);
        badge.setBackground(nb);
        android.graphics.drawable.Drawable di = WebIcons.load(this, following[0] ? "check" : "plus");
        di.setTint(0xffffffff);
        plus.setImageDrawable(di);
        badge.setContentDescription(following[0] ? "Huỷ theo dõi" : "Theo dõi");
      }));
      author.addView(badge, new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL));
      LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(dp(52), dp(63));
      ap.bottomMargin = dp(6);
      side.addView(author, ap);
    }
    final String roomId = room.optString("id");
    side.addView(sideButton("send", "Chia sẻ", () -> {
      try { startActivity(android.content.Intent.createChooser(new android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT, ServerConfig.DEFAULT_ORIGIN + "/?s=live&room=" + roomId), "Chia sẻ buổi live")); } catch (Exception ignored) {}
    }));
    if (host) {
      final boolean[] mic = { true }, cam = { true };
      side.addView(sideButton("mic", "Tắt mic", () -> { mic[0] = !mic[0]; rtc.microphone(mic[0]); status.setText(mic[0] ? "Micro đang bật" : "Micro đã tắt"); }));
      side.addView(sideButton("camera", "Tắt camera", () -> { cam[0] = !cam[0]; rtc.camera(cam[0]); status.setText(cam[0] ? "Camera đang bật" : "Camera đã tắt"); }));
      side.addView(sideButton("flip", "Đổi cam", () -> rtc.flip()));
      side.addView(sideButton("wand", "Hiệu ứng", this::effectsMenu));
    } else {
      final boolean[] muted = { false };
      side.addView(sideButton("sound", "Âm thanh", () -> {
        muted[0] = !muted[0];
        audio.adjustStreamVolume(android.media.AudioManager.STREAM_VOICE_CALL, muted[0] ? android.media.AudioManager.ADJUST_MUTE : android.media.AudioManager.ADJUST_UNMUTE, 0);
        Toast.makeText(this, muted[0] ? "Đã tắt tiếng" : "Đã bật tiếng", Toast.LENGTH_SHORT).show();
      }));
    }
    FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(dp(60), -2, Gravity.END | Gravity.BOTTOM);
    sp.setMargins(0, 0, dp(6), dp(76));
    stage.addView(side, sp);

    chatScroll = new ScrollView(this);
    chatScroll.setVerticalScrollBarEnabled(false);
    chatScroll.setVerticalFadingEdgeEnabled(true);
    chatScroll.setFadingEdgeLength(dp(24));
    chat = column();
    chatScroll.addView(chat);
    FrameLayout.LayoutParams cp = new FrameLayout.LayoutParams(-1, dp(130), Gravity.BOTTOM);
    cp.setMargins(dp(14), 0, dp(74), dp(72));
    stage.addView(chatScroll, cp);

    LinearLayout bar = row();
    bar.setPadding(dp(14), 0, dp(10), 0);
    bar.setBackground(round(0x33ffffff, 999));
    final EditText input = new EditText(this);
    input.setHint("Nói điều gì đó…");
    input.setTextColor(0xffffffff);
    input.setHintTextColor(0xaaffffff);
    input.setTextSize(14);
    input.setSingleLine(true);
    input.setBackground(null);
    input.setPadding(0, 0, dp(8), 0);
    bar.addView(input, new LinearLayout.LayoutParams(0, -1, 1));
    FrameLayout send = new FrameLayout(this);
    send.addView(icon("send_horizontal", 0xffffffff), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    send.setContentDescription("Gửi bình luận live");
    Runnable post = () -> { String value = input.getText().toString().trim(); if (value.isEmpty()) return; socket.send(NativeSocket.json("type", "chat", "text", value)); input.setText(""); };
    send.setOnClickListener(v -> post.run());
    input.setOnEditorActionListener((v, a, e) -> { post.run(); return true; });
    bar.addView(send, new LinearLayout.LayoutParams(dp(40), dp(40)));
    FrameLayout.LayoutParams barp = new FrameLayout.LayoutParams(-1, dp(46), Gravity.BOTTOM);
    barp.setMargins(dp(14), 0, dp(14), dp(14));
    stage.addView(bar, barp);

    rtc = new NativeRtc(this, config, host ? display : null, host ? null : display, new NativeRtc.Events() {
      public void status(String s) {
        status.setText(s);
        statusBox.setVisibility(View.VISIBLE);
        statusBox.removeCallbacks(hideStatus);
        statusBox.postDelayed(hideStatus, 3000);
      }
      public void signal(String peer, JSONObject payload) { try { payload.put("type", "signal"); payload.put("to", peer); socket.send(payload); } catch (JSONException ignored) {} }
    });
    hideStatus = () -> statusBox.setVisibility(View.GONE);
    audio.setMode(android.media.AudioManager.MODE_IN_COMMUNICATION);
    audio.setSpeakerphoneOn(true);
    if (host) {
      startHostMedia(0);
    }
  }

  private Runnable hideStatus = () -> {};

  // Camera có thể còn bị màn quay video giữ trong giây lát: thử lại vài lần trước khi báo lỗi.
  private void startHostMedia(final int attempt) {
    if (rtc == null || isFinishing()) return;
    try {
      rtc.media(this, true);
      status.setText("Bạn đang phát trực tiếp");
      ((View) status.getParent()).postDelayed(hideStatus, 2500);
    } catch (Exception e) {
      if (attempt < 3) { status.setText("Đang mở camera…"); new Handler(Looper.getMainLooper()).postDelayed(() -> startHostMedia(attempt + 1), 700); return; }
      Toast.makeText(this, "Không mở được camera/micro. Hãy kiểm tra quyền rồi thử lại.", Toast.LENGTH_LONG).show();
      if (socket != null) socket.send(NativeSocket.json("type", "leave"));
      finish();
    }
  }

  private LinearLayout sideButton(String iconName, String label, Runnable click) {
    LinearLayout b = column();
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    b.setPadding(0, dp(4), 0, dp(8));
    ImageView i = icon(iconName, 0xffffffff);
    i.setElevation(dp(2));
    b.addView(i, new LinearLayout.LayoutParams(dp(26), dp(26)));
    TextView t = text(label, 10, 0xffffffff);
    t.setShadowLayer(4, 0, 1, 0xff000000);
    t.setGravity(Gravity.CENTER);
    t.setSingleLine(true);
    t.setPadding(0, dp(5), 0, 0);
    b.addView(t);
    b.setContentDescription(label);
    b.setOnClickListener(v -> click.run());
    return b;
  }

  public void closed() {
    if (isFinishing()) return;
    ready = false;
    status.setText("Đã mất kết nối. Hãy mở lại mục Trực tiếp.");
    status.setVisibility(View.VISIBLE);
    if (rtc != null) { rtc.close(); rtc = null; }
  }

  protected void onStop() { super.onStop(); if (joined) finish(); }

  protected void onDestroy() {
    if (socket != null) socket.close();
    if (rtc != null) rtc.close();
    if (audio != null) { audio.setMode(previousMode); audio.setSpeakerphoneOn(previousSpeaker); }
    super.onDestroy();
  }

  private void effectsMenu() {
    final LiveEffects fx = rtc == null ? null : rtc.effects();
    if (fx == null) return;
    String[] items = new String[LiveEffects.FILTERS.length + LiveEffects.STICKERS.length];
    int k = 0;
    for (String[] f : LiveEffects.FILTERS) items[k++] = (fx.filter.equals(f[0]) ? "✓ " : "") + "Bộ lọc: " + f[1];
    for (String[] s : LiveEffects.STICKERS) items[k++] = (fx.sticker.equals(s[0]) ? "✓ " : "") + (s[2].isEmpty() ? "" : s[2] + " ") + s[1];
    new Sheet(this).setTitle("Hiệu ứng live").setItems(items, (d, w) -> {
      if (w < LiveEffects.FILTERS.length) fx.filter = LiveEffects.FILTERS[w][0];
      else fx.sticker = LiveEffects.STICKERS[w - LiveEffects.FILTERS.length][0];
      status.setText(fx.sticker.equals("none") ? "Đã áp dụng hiệu ứng" : "Đưa khuôn mặt vào khung hình");
    }).show();
  }
}
