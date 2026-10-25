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

  private GradientDrawable gradient(int r) { GradientDrawable d = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6d4aff, 0xffff4f9a }); d.setCornerRadius(dp(r)); return d; }

  private TextView text(String s, int size, int color) { TextView v = new TextView(this); v.setText(s); v.setTextSize(size); v.setTextColor(color); return v; }

  private ImageView icon(String name, int color) {
    ImageView v = new ImageView(this);
    int id = getResources().getIdentifier("ic_" + name, "drawable", getPackageName());
    if (id != 0) { android.graphics.drawable.Drawable d = getDrawable(id).mutate(); d.setTint(color); v.setImageDrawable(d); }
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
    boolean dark = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
    setTheme(dark ? android.R.style.Theme_Material_NoActionBar : android.R.style.Theme_Material_Light_NoActionBar);
    super.onCreate(state);
    BG = dark ? 0xff18191a : 0xfff0f2f5; CARD = dark ? 0xff242526 : 0xffffffff; TEXT = dark ? 0xffe4e6eb : 0xff1c1e21;
    MUTED = dark ? 0xffb0b3b8 : 0xff65676b; ACCENT = dark ? 0xff8b6dff : 0xff6d4aff; SOFT = dark ? 0xff3a3b3c : 0xfff2f3f5; LINE = dark ? 0xff3a3b3c : 0xffe4e6eb;
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    if (!dark) getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    root = column();
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener((v, i) -> { v.setPadding(0, i.getSystemWindowInsetTop(), 0, i.getSystemWindowInsetBottom()); return i; });
    setContentView(root);
    lobby();
    String origin = ServerConfig.resolve(getSharedPreferences("kinnect_settings", 0).getString("server", null));
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

  // Sảnh giống web: "Trực tiếp", ô chủ đề + Phát trực tiếp, danh sách đang trực tiếp có tìm kiếm.
  private void lobby() {
    LinearLayout bar = row();
    bar.setBackgroundColor(CARD);
    bar.setPadding(dp(6), 0, dp(12), 0);
    ImageView back = icon("back", TEXT);
    back.setPadding(dp(10), dp(10), dp(10), dp(10));
    back.setContentDescription("Quay lại");
    back.setOnClickListener(v -> finish());
    bar.addView(back, new LinearLayout.LayoutParams(dp(44), dp(44)));
    TextView brand = text("Kinnect", 20, ACCENT);
    brand.setTypeface(null, Typeface.BOLD);
    bar.addView(brand);
    root.addView(bar, new LinearLayout.LayoutParams(-1, dp(56)));
    ScrollView scroll = new ScrollView(this);
    LinearLayout c = column();
    c.setPadding(dp(14), dp(12), dp(14), dp(20));
    scroll.addView(c);
    root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    TextView title = text("Trực tiếp", 26, TEXT);
    title.setTypeface(null, Typeface.BOLD);
    c.addView(title);
    LinearLayout card = row();
    card.setPadding(dp(10), dp(10), dp(10), dp(10));
    card.setBackground(round(CARD, 18));
    topic = field("Bạn muốn chia sẻ điều gì?");
    card.addView(topic, new LinearLayout.LayoutParams(0, dp(50), 1));
    TextView go = pill("Phát trực tiếp", true, this::prepareHost);
    LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(-2, dp(50));
    gp.leftMargin = dp(8);
    card.addView(go, gp);
    LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(-1, -2);
    cp.setMargins(0, dp(14), 0, dp(18));
    c.addView(card, cp);
    LinearLayout head = row();
    View dot = new View(this);
    dot.setBackground(round(0xffff4f9a, 99));
    head.addView(dot, new LinearLayout.LayoutParams(dp(10), dp(10)));
    TextView live = text("  Đang trực tiếp", 18, TEXT);
    live.setTypeface(null, Typeface.BOLD);
    head.addView(live);
    c.addView(head);
    filter = field("Tìm buổi trực tiếp...");
    filter.setBackground(round(CARD, 999));
    LinearLayout.LayoutParams fp = new LinearLayout.LayoutParams(-1, dp(46));
    fp.setMargins(0, dp(10), 0, dp(10));
    c.addView(filter, fp);
    filter.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int b, int d) {}
      public void onTextChanged(CharSequence s, int a, int b, int d) {}
      public void afterTextChanged(android.text.Editable s) { renderRooms(); }
    });
    status = text("Đang kết nối…", 14, MUTED);
    c.addView(status);
    rooms = column();
    c.addView(rooms);
  }

  private void renderRooms() {
    if (rooms == null) return;
    rooms.removeAllViews();
    String q = filter == null ? "" : filter.getText().toString().trim().toLowerCase();
    int shown = 0;
    for (int i = 0; lastRooms != null && i < lastRooms.length(); i++) {
      final JSONObject room = lastRooms.optJSONObject(i);
      if (!q.isEmpty() && !(room.optString("title") + " " + room.optString("host")).toLowerCase().contains(q)) continue;
      shown++;
      LinearLayout r = row();
      r.setPadding(dp(12), dp(12), dp(12), dp(12));
      r.setBackground(round(CARD, 16));
      FrameLayout thumb = new FrameLayout(this);
      thumb.setBackground(gradient(12));
      TextView badge = text("LIVE", 10, 0xffffffff);
      badge.setTypeface(null, Typeface.BOLD);
      badge.setPadding(dp(5), dp(1), dp(5), dp(1));
      badge.setBackground(round(0xffe0245e, 4));
      FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.START);
      bp.setMargins(dp(5), dp(5), 0, 0);
      thumb.addView(badge, bp);
      thumb.addView(icon("live", 0xffffffff), new FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER));
      r.addView(thumb, new LinearLayout.LayoutParams(dp(72), dp(72)));
      LinearLayout t = column();
      t.setPadding(dp(12), 0, 0, 0);
      TextView name = text(room.optString("title"), 16, TEXT);
      name.setTypeface(null, Typeface.BOLD);
      t.addView(name);
      t.addView(text(room.optString("host") + " · " + room.optInt("viewers") + " đang xem", 13, MUTED));
      r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
      r.setOnClickListener(v -> { host = false; socket.send(NativeSocket.json("type", "join", "room", room.optString("id"))); });
      LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
      p.bottomMargin = dp(8);
      rooms.addView(r, p);
    }
    status.setText(!ready ? "Đang kết nối…" : shown == 0 ? "Chưa có ai lên sóng. Hãy mở đầu cuộc trò chuyện!" : "");
    status.setVisibility(status.getText().length() == 0 ? View.GONE : View.VISIBLE);
  }

  private void prepareHost() {
    if (socket == null || !ready) { Toast.makeText(this, "Đang kết nối máy chủ, thử lại sau giây lát.", Toast.LENGTH_SHORT).show(); return; }
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      requestPermissions(new String[] { Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO }, 301);
      return;
    }
    String t = topic == null ? "" : topic.getText().toString().trim();
    if (t.isEmpty()) { topic.setError("Nhập chủ đề buổi live"); return; }
    host = true;
    socket.send(NativeSocket.json("type", "create", "title", t));
  }

  public void onRequestPermissionsResult(int code, String[] p, int[] grants) {
    super.onRequestPermissionsResult(code, p, grants);
    if (code == 301) {
      if (grants.length == 2 && grants[0] == 0 && grants[1] == 0) prepareHost();
      else status.setText("Cần quyền camera và micro để phát trực tiếp.");
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
    }
    if (type.equals("rooms") && !joined) { lastRooms = m.optJSONArray("rooms"); renderRooms(); }
    if (type.equals("joined")) { joined = true; showRoom(m); }
    if (type.equals("peer") && rtc != null) rtc.offer(m.optString("id"));
    if (type.equals("signal") && rtc != null) rtc.signal(m.optString("from"), m);
    if (type.equals("peer-left") && rtc != null) rtc.remove(m.optString("id"));
    if (type.equals("count") && viewers != null) viewers.setText("👁 " + m.optInt("viewers"));
    if (type.equals("chat") && chat != null) addChat(m.optString("name"), m.optString("text"));
    if (type.equals("room-ended")) { Toast.makeText(this, "Buổi trực tiếp đã kết thúc.", Toast.LENGTH_LONG).show(); finish(); }
    if (type.equals("error")) { status.setText(m.optString("message")); status.setVisibility(View.VISIBLE); }
  }

  private TextView viewers;
  private ScrollView chatScroll;

  private void addChat(String name, String body) {
    TextView t = new TextView(this);
    android.text.SpannableStringBuilder sb = new android.text.SpannableStringBuilder(name + "  ");
    sb.setSpan(new android.text.style.StyleSpan(Typeface.BOLD), 0, name.length(), 0);
    sb.append(body);
    t.setText(sb);
    t.setTextColor(0xffffffff);
    t.setTextSize(14);
    t.setShadowLayer(4, 0, 1, 0xcc000000);
    t.setPadding(dp(10), dp(5), dp(10), dp(5));
    t.setBackground(round(0x55000000, 14));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, -2);
    p.topMargin = dp(4);
    chat.addView(t, p);
    while (chat.getChildCount() > 40) chat.removeViewAt(0);
    chatScroll.post(() -> chatScroll.fullScroll(View.FOCUS_DOWN));
  }

  // Phòng live: video toàn màn, thông tin phía trên, chat nổi phía dưới, ô bình luận bo tròn.
  private void showRoom(JSONObject m) {
    root.removeAllViews();
    root.setBackgroundColor(0xff000000);
    getWindow().setStatusBarColor(0xff000000);
    getWindow().setNavigationBarColor(0xff000000);
    getWindow().getDecorView().setSystemUiVisibility(0);
    FrameLayout stage = new FrameLayout(this);
    root.addView(stage, new LinearLayout.LayoutParams(-1, 0, 1));
    SurfaceViewRenderer display = new SurfaceViewRenderer(this);
    stage.addView(display, new FrameLayout.LayoutParams(-1, -1));
    LinearLayout top = row();
    top.setPadding(dp(12), dp(10), dp(12), dp(10));
    LinearLayout info = column();
    TextView title = text(m.optJSONObject("room").optString("title"), 16, 0xffffffff);
    title.setTypeface(null, Typeface.BOLD);
    title.setShadowLayer(4, 0, 1, 0xcc000000);
    info.addView(title);
    status = text(host ? "Đang chuẩn bị camera…" : "Đang kết nối…", 12, 0xddffffff);
    status.setShadowLayer(4, 0, 1, 0xcc000000);
    info.addView(status);
    top.addView(info, new LinearLayout.LayoutParams(0, -2, 1));
    TextView liveTag = text("LIVE", 12, 0xffffffff);
    liveTag.setTypeface(null, Typeface.BOLD);
    liveTag.setPadding(dp(8), dp(3), dp(8), dp(3));
    liveTag.setBackground(round(0xffe0245e, 6));
    top.addView(liveTag);
    viewers = text("👁 0", 12, 0xffffffff);
    viewers.setPadding(dp(8), dp(3), dp(8), dp(3));
    viewers.setBackground(round(0x66000000, 6));
    LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(-2, -2);
    vp.leftMargin = dp(6);
    top.addView(viewers, vp);
    top.addView(new View(this), new LinearLayout.LayoutParams(dp(6), 1));
    ImageView close = icon("close", 0xffffffff);
    close.setPadding(dp(8), dp(8), dp(8), dp(8));
    close.setContentDescription(host ? "Kết thúc trực tiếp" : "Rời phòng");
    close.setBackground(round(0x66000000, 999));
    close.setOnClickListener(v -> finish());
    top.addView(close, new LinearLayout.LayoutParams(dp(40), dp(40)));
    stage.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    chatScroll = new ScrollView(this);
    chatScroll.setVerticalScrollBarEnabled(false);
    chat = column();
    chat.setPadding(dp(12), 0, dp(80), dp(8));
    chatScroll.addView(chat);
    stage.addView(chatScroll, new FrameLayout.LayoutParams(-1, dp(230), Gravity.BOTTOM));
    rtc = new NativeRtc(this, config, host ? display : null, host ? null : display, new NativeRtc.Events() {
      public void status(String s) { status.setText(s); }
      public void signal(String peer, JSONObject payload) { try { payload.put("type", "signal"); payload.put("to", peer); socket.send(payload); } catch (JSONException ignored) {} }
    });
    audio.setMode(android.media.AudioManager.MODE_IN_COMMUNICATION);
    audio.setSpeakerphoneOn(true);
    if (host) {
      try { rtc.media(this, true); status.setText("Đang phát trực tiếp"); }
      catch (Exception e) { status.setText("Không mở được camera/micro."); socket.send(NativeSocket.json("type", "leave")); finish(); return; }
      LinearLayout side = column();
      side.setGravity(Gravity.CENTER_HORIZONTAL);
      final boolean[] mic = { true }, cam = { true };
      side.addView(sideButton("sound", "Micro", () -> { mic[0] = !mic[0]; rtc.microphone(mic[0]); status.setText(mic[0] ? "Micro đang bật" : "Micro đã tắt"); }));
      side.addView(sideButton("video", "Camera", () -> { cam[0] = !cam[0]; rtc.camera(cam[0]); status.setText(cam[0] ? "Camera đang bật" : "Camera đã tắt"); }));
      side.addView(sideButton("flip", "Đổi cam", () -> rtc.flip()));
      side.addView(sideButton("discover", "Hiệu ứng", this::effectsMenu));
      FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(dp(68), -2, Gravity.END | Gravity.CENTER_VERTICAL);
      stage.addView(side, sp);
    }
    LinearLayout bar = row();
    bar.setPadding(dp(10), dp(8), dp(10), dp(10));
    final EditText input = new EditText(this);
    input.setHint("Viết bình luận…");
    input.setTextColor(0xffffffff);
    input.setHintTextColor(0xaaffffff);
    input.setSingleLine(true);
    input.setPadding(dp(16), 0, dp(16), 0);
    input.setBackground(round(0x33ffffff, 999));
    bar.addView(input, new LinearLayout.LayoutParams(0, dp(44), 1));
    FrameLayout send = new FrameLayout(this);
    send.setBackground(gradient(999));
    send.addView(icon("send", 0xffffffff), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    send.setOnClickListener(v -> { String value = input.getText().toString().trim(); if (value.isEmpty()) return; socket.send(NativeSocket.json("type", "chat", "text", value)); input.setText(""); });
    LinearLayout.LayoutParams sp2 = new LinearLayout.LayoutParams(dp(48), dp(44));
    sp2.leftMargin = dp(8);
    bar.addView(send, sp2);
    root.addView(bar);
  }

  private LinearLayout sideButton(String iconName, String label, Runnable click) {
    LinearLayout b = column();
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    b.setPadding(0, dp(8), 0, dp(4));
    FrameLayout circle = new FrameLayout(this);
    circle.setBackground(round(0x66000000, 999));
    circle.addView(icon(iconName, 0xffffffff), new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
    b.addView(circle, new LinearLayout.LayoutParams(dp(46), dp(46)));
    TextView t = text(label, 11, 0xffffffff);
    t.setShadowLayer(4, 0, 1, 0xcc000000);
    t.setGravity(Gravity.CENTER);
    b.addView(t);
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
