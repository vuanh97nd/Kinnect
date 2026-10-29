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
  private boolean host, joined, ready, previewing;
  private LiveEffects previewLook;
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

  private TextView text(String s, int size, int color) { TextView v = new KinnectText(this); v.setText(s); v.setTextSize(size); v.setTextColor(color); return v; }

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
    setTheme(getResources().getIdentifier(dark?"Kinnect.App.Dark":"Kinnect.App.Light","style",getPackageName()));
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
      ensurePrivacy(()->socket = new NativeSocket(origin, this));
    });
    audio = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
    previousMode = audio.getMode();
    previousSpeaker = audio.isSpeakerphoneOn();
  }

  private void ensurePrivacy(Runnable ready){NativeApi.shared.call("GET","/api/me/privacy-consent",null,(data,error,statusCode)->{if(isFinishing()||isDestroyed())return;if(error!=null){status.setText(error);return;}if(data.optBoolean("accepted")){ready.run();return;}new Sheet(this).setTitle(I18n.t("Thông báo sử dụng dữ liệu")).setMessage(I18n.t(data.optString("notice"))).setPositiveButton(I18n.t("Tôi đồng ý"),(d,w)->NativeApi.shared.call("POST","/api/me/privacy-consent",NativeSocket.json("accepted",true,"version",data.optString("version")),(accepted,failure,code)->{if(failure==null)ready.run();else status.setText(failure);})).setNegativeButton(I18n.t("Để sau"),(d,w)->finish()).show();});}

  // Sảnh giống web: danh sách buổi live dạng thẻ dọc; phát live bằng nút nổi.
  private void lobby() {
    LinearLayout bar = row();
    bar.setBackgroundColor(CARD);
    bar.setElevation(dp(1));
    bar.setPadding(dp(6), 0, dp(16), 0);
    ImageView back = icon("back", TEXT);
    back.setPadding(dp(10), dp(10), dp(10), dp(10));
    back.setContentDescription(I18n.t("Quay lại"));
    back.setOnClickListener(v -> finish());
    bar.addView(back, new LinearLayout.LayoutParams(dp(44), dp(44)));
    TextView brand = text(I18n.t("Trực tiếp"), 19, TEXT);
    brand.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    brand.setPadding(dp(4), 0, dp(8), 0);
    bar.addView(brand);
    View dot = new View(this);
    dot.setBackground(round(0xfffe2c55, 99));
    bar.addView(dot, new LinearLayout.LayoutParams(dp(8), dp(8)));
    bar.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    ImageView refresh = icon("rotate_ccw", TEXT);
    refresh.setPadding(dp(10), dp(10), dp(10), dp(10));
    refresh.setContentDescription(I18n.t("Làm mới"));
    refresh.setOnClickListener(v -> renderRooms());
    bar.addView(refresh, new LinearLayout.LayoutParams(dp(44), dp(44)));
    root.addView(bar, new LinearLayout.LayoutParams(-1, dp(56)));

    FrameLayout stage = host?new FrameLayout(this):new ViewerStage();
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    LinearLayout c = column();
    c.setPadding(dp(14), dp(14), dp(14), dp(96));
    scroll.addView(c);
    stage.addView(scroll, new FrameLayout.LayoutParams(-1, -1));
    status = text(I18n.t("Đang kết nối…"), 14, MUTED);
    status.setGravity(Gravity.CENTER);
    status.setPadding(0, dp(140), 0, 0);
    c.addView(status, new LinearLayout.LayoutParams(-1, -2));
    rooms = column();
    rooms.setGravity(Gravity.CENTER);
    c.addView(rooms, new LinearLayout.LayoutParams(-1, 0, 1));

    LinearLayout fab = row();
    fab.setGravity(Gravity.CENTER);
    fab.setPadding(dp(20), 0, dp(22), 0);
    GradientDrawable fg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xfffe2c55, 0xffff4f9a });
    fg.setCornerRadius(dp(99));
    fab.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff), fg, null));
    fab.setElevation(dp(8));
    fab.addView(icon("radio", 0xffffffff), new LinearLayout.LayoutParams(dp(20), dp(20)));
    TextView fl = text(I18n.t("Phát live"), 15, 0xffffffff);
    fl.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    fl.setPadding(dp(8), 0, 0, 0);
    fab.addView(fl);
    fab.setContentDescription(I18n.t("Phát trực tiếp"));
    fab.setOnClickListener(v -> askTitleAndHost());
    FrameLayout.LayoutParams fp = new FrameLayout.LayoutParams(-2, dp(52), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    fp.bottomMargin = dp(20);
    stage.addView(fab, fp);
    root.addView(stage, new LinearLayout.LayoutParams(-1, 0, 1));
  }

  private void askTitleAndHost() { prepareHost(); }

  private String topicText = "";

  private void renderRooms() {
    if (rooms == null) return;
    rooms.removeAllViews();
    boolean any = lastRooms != null && lastRooms.length() > 0;
    if (!ready || any) {
      status.setText(ready ? I18n.t("Đang mở buổi live…") : I18n.t("Đang kết nối…"));
      status.setVisibility(View.VISIBLE);
      return;
    }
    status.setVisibility(View.GONE);
    LinearLayout empty = column();
    empty.setGravity(Gravity.CENTER);
    empty.setPadding(dp(16), dp(24), dp(16), dp(24));
    FrameLayout bubble = new FrameLayout(this);
    bubble.setBackground(round(WebDesign.SOFT[WebTheme.isDark(this) ? 1 : 0], 99));
    bubble.addView(icon("radio", ACCENT), new FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER));
    empty.addView(bubble, new LinearLayout.LayoutParams(dp(72), dp(72)));
    TextView t = text(I18n.t("Chưa có buổi live"), 18, TEXT);
    t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    t.setGravity(Gravity.CENTER);
    t.setPadding(0, dp(16), 0, dp(4));
    empty.addView(t,new LinearLayout.LayoutParams(-1,-2));
    TextView subtitle=text(I18n.t("Hãy là người mở màn!"),14,MUTED);
    subtitle.setGravity(Gravity.CENTER);
    empty.addView(subtitle,new LinearLayout.LayoutParams(-1,-2));
    rooms.addView(empty, new LinearLayout.LayoutParams(-1, -2));
  }

  /** Local preview only: no create/join/signaling until the explicit start button. */
  private TextView previewBadge(){
    TextView badge=text(I18n.t("Xem trước · Chưa phát sóng"),12,0xffffffff);
    badge.setGravity(Gravity.CENTER);badge.setSingleLine(false);badge.setMinHeight(dp(36));
    badge.setPadding(dp(12),dp(8),dp(12),dp(8));badge.setBackground(round(0x88000000,18));
    return badge;
  }
  private void showHostPreview(){
    if(previewing||joined)return;previewing=true;host=false;if(rtc!=null){rtc.close();rtc=null;}
    root.removeAllViews();root.setBackgroundColor(0xff111017);FrameLayout stage=new FrameLayout(this);root.addView(stage,new LinearLayout.LayoutParams(-1,0,1));SurfaceViewRenderer display=new SurfaceViewRenderer(this);stage.addView(display,new FrameLayout.LayoutParams(-1,-1));
    TextView close=text(I18n.t("×"),30,0xffffffff);close.setGravity(Gravity.CENTER);close.setContentDescription(I18n.t("Đóng camera chuẩn bị Live"));close.setOnClickListener(v->finish());FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.TOP|Gravity.START);cp.setMargins(dp(12),dp(8),0,0);stage.addView(close,cp);
    TextView badge=previewBadge();FrameLayout.LayoutParams bp=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);bp.setMargins(dp(64),dp(16),dp(64),0);stage.addView(badge,bp);
    LinearLayout controls=column();controls.setPadding(dp(16),dp(10),dp(16),dp(16));controls.setBackgroundColor(0xff18151f);root.addView(controls,new LinearLayout.LayoutParams(-1,-2));
    EditText title=field(I18n.t("Tiêu đề buổi Live"));title.setText(topicText);title.setTextColor(0xffffffff);title.setHintTextColor(0xffaaa3b7);title.setBackground(round(0xff302a3d,14));title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});controls.addView(title,new LinearLayout.LayoutParams(-1,dp(48)));
    LinearLayout actions=row();final boolean[] mic={true};actions.addView(sideButton("flip",I18n.t("Lật camera"),()->{if(rtc!=null)rtc.flip();}),new LinearLayout.LayoutParams(0,-2,1));actions.addView(sideButton("wand",I18n.t("Làm đẹp"),this::effectsMenu),new LinearLayout.LayoutParams(0,-2,1));actions.addView(sideButton("mic","Micro",()->{mic[0]=!mic[0];badge.setText(mic[0]?I18n.t("Xem trước · Mic sẽ bật khi phát"):I18n.t("Xem trước · Mic sẽ tắt khi phát"));}),new LinearLayout.LayoutParams(0,-2,1));controls.addView(actions);
    TextView start=pill(I18n.t("Bắt đầu Live"),true,()->{});start.setEnabled(false);start.setAlpha(.45f);controls.addView(start,new LinearLayout.LayoutParams(-1,dp(52)));status=text(I18n.t("Đang mở camera…"),12,0xffc9bfd7);status.setGravity(Gravity.CENTER);status.setPadding(0,dp(10),0,dp(4));controls.addView(status,new LinearLayout.LayoutParams(-1,-2));
    try{rtc=new NativeRtc(this,config,display,null,new NativeRtc.Events(){public void signal(String peer,JSONObject payload){}public void status(String text){status.setText(text);}});final NativeRtc previewRtc=rtc;display.addFrameListener(new org.webrtc.EglRenderer.FrameListener(){private boolean received;public void onFrame(android.graphics.Bitmap bitmap){if(bitmap!=null)bitmap.recycle();if(received)return;received=true;runOnUiThread(()->{if(!previewing||rtc!=previewRtc||isFinishing()||isDestroyed())return;status.setText(I18n.t("Camera đã sẵn sàng · Chưa phát sóng"));start.setEnabled(true);start.setAlpha(1);});}},0f);rtc.media(this,true);rtc.microphone(false);start.setOnClickListener(v->{if(!previewing||!ready||joining)return;topicText=title.getText().toString().trim();start.setEnabled(false);previewLook=rtc.effects();rtc.close();rtc=null;previewing=false;host=true;joining=true;pendingHostMic=mic[0];socket.send(NativeSocket.json("type","create","title",topicText));});}
    catch(Exception error){if(rtc!=null){rtc.close();rtc=null;}status.setText(I18n.t("Không mở được camera. Kiểm tra quyền camera/micro rồi mở lại."));}
  }
  private boolean pendingHostMic=true;
  private final class ViewerStage extends FrameLayout {
    float downX,downY;boolean eligible,drag;ViewerStage(){super(LiveActivity.this);}
    @Override public boolean onInterceptTouchEvent(MotionEvent e){if(e.getActionMasked()==MotionEvent.ACTION_DOWN){downX=e.getX();downY=e.getY();eligible=downY>dp(100)&&downY<getHeight()-dp(160);drag=false;if(chatScroll!=null){android.graphics.Rect bounds=new android.graphics.Rect();chatScroll.getGlobalVisibleRect(bounds);if(bounds.contains((int)e.getRawX(),(int)e.getRawY()))eligible=false;}}if(e.getActionMasked()==MotionEvent.ACTION_MOVE&&LiveSwipePolicy.direction(e.getX()-downX,e.getY()-downY,dp(60),eligible)!=0){drag=true;return true;}return super.onInterceptTouchEvent(e);}
    @Override public boolean onTouchEvent(MotionEvent e){if(e.getActionMasked()==MotionEvent.ACTION_UP&&drag){int direction=LiveSwipePolicy.direction(e.getX()-downX,e.getY()-downY,dp(60),eligible);if(direction!=0)switchLive(direction);drag=false;return true;}if(e.getActionMasked()==MotionEvent.ACTION_CANCEL)drag=false;return eligible||super.onTouchEvent(e);}
  }

  private void prepareHost() {
    if (socket == null || !ready) { Toast.makeText(this, I18n.t("Đang kết nối máy chủ, thử lại sau giây lát."), Toast.LENGTH_SHORT).show(); return; }
    if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED || checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      requestPermissions(new String[] { Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO }, 301);
      return;
    }
    showHostPreview();
  }

  public void onRequestPermissionsResult(int code, String[] p, int[] grants) {
    super.onRequestPermissionsResult(code, p, grants);
    if (code == 301) {
      if (grants.length == 2 && grants[0] == 0 && grants[1] == 0) prepareHost();
      else { status.setText(I18n.t("Cần quyền camera và micro để phát trực tiếp.")); status.setVisibility(View.VISIBLE); }
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
    if (type.equals("rooms")) { lastRooms = m.optJSONArray("rooms"); if (!joined && !previewing) { renderRooms(); autoJoin(); } }
    if (type.equals("joined")) { joined = true; joining = false; showRoom(m); }
    if (type.equals("peer") && rtc != null) rtc.offer(m.optString("id"));
    if (type.equals("signal") && rtc != null) rtc.signal(m.optString("from"), m);
    if (type.equals("peer-left") && rtc != null) rtc.remove(m.optString("id"));
    if(type.equals("count")&&viewers!=null){viewers.setText(String.valueOf(m.optInt("viewers")));renderAudience(m.optJSONArray("users"));}
    if(type.equals("viewer-joined")&&m.optJSONObject("user")!=null)showArrival(m.optJSONObject("user").optString("name"));
    if(type.equals("live-reaction"))showReaction(m.optString("kind"),m.optString("name"));
    if (type.equals("chat") && chat != null) addChat(m.optString("name"), m.optString("text"));
    if (type.equals("room-ended") || type.equals("ended")) { if (host) { Toast.makeText(this, I18n.t("Buổi trực tiếp đã kết thúc."), Toast.LENGTH_LONG).show(); finish(); } else roomEnded(); }
    if (type.equals("error")) { if(host&&!joined){host=false;joining=false;previewing=false;showHostPreview();status.setText(m.optString("message",I18n.t("Chưa bắt đầu được Live. Hãy thử lại.")));return;}joining=false;if(liveStage!=null){liveStage.setTranslationY(0);liveStage.setAlpha(1);}status.setText(m.optString("message")); status.setVisibility(View.VISIBLE); }
  }

  private TextView viewers,arrival;
  private LinearLayout audience;
  private FrameLayout reactionLayer;
  private long lastReaction;private boolean fullFrame=true;
  private void renderAudience(JSONArray users){if(audience==null)return;audience.removeAllViews();if(users==null)return;for(int n=0;n<users.length();n++){JSONObject u=users.optJSONObject(n);if(u==null)continue;String name=u.optString("name","K");FrameLayout avatar=new FrameLayout(this);avatar.setBackground(round(0xaa6c47e0,99));avatar.setClipToOutline(true);TextView initial=text(name.isEmpty()?"K":name.substring(0,1).toUpperCase(),11,0xffffffff);initial.setGravity(Gravity.CENTER);avatar.addView(initial,new FrameLayout.LayoutParams(-1,-1));String url=u.optString("avatar");if(url.startsWith("/api/users/"))NativeApi.shared.image(url,bytes->{if(isDestroyed()||bytes==null)return;android.graphics.Bitmap bitmap=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(bitmap!=null){ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setImageBitmap(bitmap);avatar.addView(image,new FrameLayout.LayoutParams(-1,-1));}});avatar.setContentDescription(name);avatar.setOnClickListener(v->Toast.makeText(this,name,Toast.LENGTH_SHORT).show());LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(dp(28),dp(28));at.leftMargin=dp(5);audience.addView(avatar,at);}}
  private void showArrival(String name){if(arrival==null)return;arrival.removeCallbacks(clearArrival);arrival.setText(name+" "+I18n.t("vừa tham gia"));arrival.setVisibility(View.VISIBLE);arrival.setAlpha(0);arrival.animate().alpha(1).setDuration(180).start();arrival.postDelayed(clearArrival,3500);}
  private final Runnable clearArrival=()->{if(arrival!=null)arrival.setVisibility(View.GONE);};
  private void sendReaction(String kind){if(socket==null||System.currentTimeMillis()-lastReaction<400)return;lastReaction=System.currentTimeMillis();socket.send(NativeSocket.json("type","live-reaction","kind",kind));}
  private void gifts(){new Sheet(this).setTitle(I18n.t("Quà tặng miễn phí")).setItems(new String[]{"🌹 "+I18n.t("Hoa hồng"),"⭐ "+I18n.t("Ngôi sao"),"👑 "+I18n.t("Vương miện")},(d,n)->sendReaction(new String[]{"rose","star","crown"}[n])).setNegativeButton(I18n.t("Đóng"),null).show();}
  private void showReaction(String kind,String name){if(reactionLayer==null||reactionLayer.getChildCount()>20)return;String glyph=kind.equals("rose")?"🌹":kind.equals("star")?"⭐":kind.equals("crown")?"👑":"♥";TextView heart=text(glyph,kind.equals("heart")?30:42,0xffff4f91);heart.setGravity(Gravity.CENTER);FrameLayout layer=reactionLayer;FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(dp(64),dp(72),Gravity.RIGHT|Gravity.BOTTOM);at.rightMargin=dp(10+(int)(Math.random()*55));at.bottomMargin=dp(90);layer.addView(heart,at);heart.animate().translationY(-dp(210+(int)(Math.random()*120))).translationX(-dp((int)(Math.random()*70))).rotation((float)(Math.random()*35-17)).alpha(0).setDuration(2000).withEndAction(()->layer.removeView(heart)).start();if(!kind.equals("heart")&&chat!=null)addChat(name,I18n.t("đã gửi")+" "+glyph);}

  private ScrollView chatScroll;
  private boolean joining;
  private String currentRoom = "";
  private FrameLayout liveStage;
  private long swipeAt;

  private void autoJoin() {
    if (previewing || joined || joining || host || socket == null || !ready || lastRooms == null || lastRooms.length() == 0) return;
    if (getIntent().getBooleanExtra(EXTRA_HOST, false)) return;
    JSONObject first = lastRooms.optJSONObject(0);
    if (first == null) return;
    joining = true;
    socket.send(NativeSocket.json("type", "join", "room", first.optString("id")));
  }

  private int roomIndex(String id) {
    for (int i = 0; lastRooms != null && i < lastRooms.length(); i++) if (lastRooms.optJSONObject(i)!=null && lastRooms.optJSONObject(i).optString("id").equals(id)) return i;
    return -1;
  }

  private void switchLive(final int direction) {
    if (host || previewing || socket==null || !ready || System.currentTimeMillis() - swipeAt < 900 || joining) return;
    int index = roomIndex(currentRoom);
    final JSONObject next = lastRooms == null ? null : lastRooms.optJSONObject(index + direction);
    if (index < 0 || next == null) { Toast.makeText(this, direction > 0 ? I18n.t("Bạn đã xem đến buổi live cuối.") : I18n.t("Đây là buổi live đầu tiên."), Toast.LENGTH_SHORT).show(); return; }
    swipeAt = System.currentTimeMillis();
    joining = true;
    final View stage = liveStage;
    Runnable go = () -> {
      if(isFinishing()||isDestroyed()||socket==null||!ready)return;
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
    Toast.makeText(this, I18n.t("Buổi live đã kết thúc."), Toast.LENGTH_SHORT).show();
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
    TextView t = new KinnectText(this);
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
      TextView hint = text(I18n.t("Vuốt lên để xem live khác"), 12, 0xccffffff);
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
    reactionLayer=new FrameLayout(this);stage.addView(reactionLayer,new FrameLayout.LayoutParams(-1,-1));

    LinearLayout center = column();
    center.setGravity(Gravity.CENTER_HORIZONTAL);
    center.addView(icon("radio", 0xa6ffffff), new LinearLayout.LayoutParams(dp(34), dp(34)));
    status = text(host ? I18n.t("Bạn đang phát trực tiếp") : I18n.t("Đang kết nối buổi live…"), 12, 0xa6ffffff);
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
    viewers = text(String.valueOf(room.optInt("viewers")), 11, 0xffffffff);
    viewers.setGravity(Gravity.CENTER);viewers.setIncludeFontPadding(false);viewers.setSingleLine(true);
    viewers.setPadding(dp(7), 0, 0, 0);
    meta.setBaselineAligned(false);meta.addView(icon("eye",0xffffffff),new LinearLayout.LayoutParams(dp(12),dp(12)));meta.addView(viewers);
    LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(-2, -2);
    mp.topMargin = dp(3);
    who.addView(meta, mp);
    chip.addView(who,new LinearLayout.LayoutParams(0,-2,1));
    heading.addView(chip, new LinearLayout.LayoutParams(0, -2,1));
    heading.addView(new View(this),new LinearLayout.LayoutParams(dp(12),1));
    FrameLayout close = new FrameLayout(this);
    close.setBackground(round(0x7016121e, 99));
    close.addView(icon("close", 0xffffffff), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    close.setContentDescription(host ? I18n.t("Kết thúc live") : I18n.t("Rời live"));
    close.setOnClickListener(v -> { if (socket != null) socket.send(NativeSocket.json("type", "leave")); finish(); });
    heading.addView(close, new LinearLayout.LayoutParams(dp(40), dp(40)));
    FrameLayout.LayoutParams hp = new FrameLayout.LayoutParams(-1, -2, Gravity.TOP);
    hp.setMargins(dp(12), dp(12), dp(12), 0);
    stage.addView(heading, hp);
    HorizontalScrollView audienceScroll=new HorizontalScrollView(this);audienceScroll.setHorizontalScrollBarEnabled(false);audience=row();audienceScroll.addView(audience);FrameLayout.LayoutParams audienceAt=new FrameLayout.LayoutParams(-1,dp(30),Gravity.TOP);audienceAt.setMargins(dp(12),dp(68),dp(56),0);stage.addView(audienceScroll,audienceAt);
    arrival=text("",12,0xffffffff);arrival.setPadding(dp(12),dp(7),dp(12),dp(7));arrival.setBackground(round(0xbb6c47e0,18));arrival.setSingleLine(true);arrival.setEllipsize(android.text.TextUtils.TruncateAt.END);arrival.setVisibility(View.GONE);FrameLayout.LayoutParams arrivalAt=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.LEFT);arrivalAt.setMargins(dp(14),0,dp(90),dp(235));stage.addView(arrival,arrivalAt);

    TextView title = text(room.optString("title"), 13, 0xffffffff);
    title.setShadowLayer(4, 0, 1, 0xff000000);
    title.setLineSpacing(0, 1.2f);
    FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-1, -2, Gravity.TOP);
    tp.setMargins(dp(16), dp(108), dp(24), 0);title.setMaxLines(2);title.setEllipsize(android.text.TextUtils.TruncateAt.END);
    if(!room.optString("title").isEmpty()&&!room.optString("title").equals("Trò chuyện cùng Kinnect"))stage.addView(title,tp);

    LinearLayout side = column();
    side.setGravity(Gravity.CENTER_HORIZONTAL);
    side.setBackground(round(0x6616121e,24));
    final String hostId = m.optString("hostUserId",room.optString("hostId"));
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
      badge.setContentDescription(following[0] ? I18n.t("Huỷ theo dõi") : I18n.t("Theo dõi"));
      badge.setOnClickListener(v -> NativeApi.shared.call(following[0] ? "DELETE" : "POST", "/api/users/" + hostId + "/follow", new JSONObject(), (d, e, s) -> {
        if (e != null || isDestroyed()) return;
        following[0] = !following[0];
        GradientDrawable nb = round(following[0] ? ACCENT : 0xfffe2c55, 99);
        nb.setStroke(dp(2), 0xffffffff);
        badge.setBackground(nb);
        android.graphics.drawable.Drawable di = WebIcons.load(this, following[0] ? "check" : "plus");
        di.setTint(0xffffffff);
        plus.setImageDrawable(di);
        badge.setContentDescription(following[0] ? I18n.t("Huỷ theo dõi") : I18n.t("Theo dõi"));
      }));
      author.addView(badge, new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL));
      LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(dp(52), dp(63));
      ap.bottomMargin = dp(6);
      side.addView(author, ap);
    }
    final String roomId = room.optString("id");
    if(!host&&!hostId.isEmpty()){
      side.addView(sideButton("flag",I18n.t("Báo cáo buổi live"),()->{EditText reason=field(I18n.t("Mô tả vi phạm; không gửi lại ảnh CSAM"));new Sheet(this).setTitle(I18n.t("Báo cáo buổi live")).setMessage(I18n.t("Có nguy cơ trẻ em? Ghi rõ CSAE/CSAM và nơi xảy ra. Không tải lại hoặc phát tán nội dung vi phạm.")).setView(reason).setPositiveButton(I18n.t("Gửi báo cáo"),(d,w)->{String details=reason.getText().toString().trim();if(details.length()<5){Toast.makeText(this,I18n.t("Mô tả ít nhất 5 ký tự."),Toast.LENGTH_SHORT).show();return;}NativeApi.shared.call("POST","/api/reports",NativeSocket.json("targetType","user","targetId",hostId,"reason","[Livestream "+roomId+"] "+details),(answer,error,code)->Toast.makeText(this,error==null?I18n.t("Đã gửi báo cáo."):error,Toast.LENGTH_SHORT).show());}).setNegativeButton(I18n.t("Hủy"),null).show();}));
      side.addView(sideButton("shield_check",I18n.t("Chặn người phát"),()->new Sheet(this).setTitle(I18n.t("Chặn người phát?")).setMessage(I18n.t("Bạn sẽ rời buổi live và không còn thấy người này trong nội dung được hỗ trợ.")).setPositiveButton(I18n.t("Chặn"),(d,w)->NativeApi.shared.call("POST","/api/users/"+hostId+"/block",new JSONObject(),(answer,error,code)->{if(error==null)finish();else Toast.makeText(this,error,Toast.LENGTH_SHORT).show();})).setNegativeButton(I18n.t("Hủy"),null).show()));
    }
    side.addView(sideButton("send", I18n.t("Chia sẻ"), () -> {
      try { startActivity(android.content.Intent.createChooser(new android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT, ServerConfig.DEFAULT_ORIGIN + "/?s=live&room=" + roomId), I18n.t("Chia sẻ buổi live"))); } catch (Exception ignored) {}
    }));
    if (host) {
      final boolean[] mic = { true }, cam = { true };
      side.addView(sideButton("settings",I18n.t("Công cụ"),()->new Sheet(this).setTitle(I18n.t("Công cụ Live")).setItems(new String[]{I18n.t("Bật / tắt micro"),I18n.t("Bật / tắt camera"),I18n.t("Đổi camera"),I18n.t("Hiệu ứng Live"),I18n.t("Khung hình: toàn cảnh / lấp đầy")},(d,n)->{if(rtc==null)return;if(n==0){mic[0]=!mic[0];rtc.microphone(mic[0]);}if(n==1){cam[0]=!cam[0];rtc.camera(cam[0]);}if(n==2)rtc.flip();if(n==3)effectsMenu();if(n==4){fullFrame=!fullFrame;rtc.framing(fullFrame);}}).show()));
    } else {
      final boolean[] muted = { false };
      side.addView(sideButton("sound", I18n.t("Âm thanh"), () -> {
        muted[0] = !muted[0];
        audio.adjustStreamVolume(android.media.AudioManager.STREAM_VOICE_CALL, muted[0] ? android.media.AudioManager.ADJUST_MUTE : android.media.AudioManager.ADJUST_UNMUTE, 0);
        Toast.makeText(this, muted[0] ? I18n.t("Đã tắt tiếng") : I18n.t("Đã bật tiếng"), Toast.LENGTH_SHORT).show();
      }));
    }
    side.addView(sideButton("heart",I18n.t("Thả tim"),()->sendReaction("heart")));
    side.addView(sideButton("gift",I18n.t("Tặng quà"),this::gifts));
    FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(dp(56), -2, Gravity.END | Gravity.BOTTOM);
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
    input.setHint(I18n.t("Nói điều gì đó…"));
    input.setTextColor(0xffffffff);
    input.setHintTextColor(0xaaffffff);
    input.setTextSize(14);
    input.setSingleLine(true);
    input.setBackground(null);
    input.setPadding(0, 0, dp(8), 0);
    bar.addView(input, new LinearLayout.LayoutParams(0, -1, 1));
    FrameLayout send = new FrameLayout(this);
    send.addView(icon("send_horizontal", 0xffffffff), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    send.setContentDescription(I18n.t("Gửi bình luận live"));
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
      rtc.media(this, true);rtc.microphone(pendingHostMic);if(previewLook!=null&&rtc.effects()!=null){LiveEffects f=rtc.effects();f.filter=previewLook.filter;f.sticker=previewLook.sticker;f.beautyOn=previewLook.beautyOn;f.smooth=previewLook.smooth;f.blemish=previewLook.blemish;f.eyes=previewLook.eyes;f.lips=previewLook.lips;previewLook=null;}
      status.setText(I18n.t("Bạn đang phát trực tiếp"));
      ((View) status.getParent()).postDelayed(hideStatus, 2500);
    } catch (Exception e) {
      if (attempt < 3) { status.setText(I18n.t("Đang mở camera…")); new Handler(Looper.getMainLooper()).postDelayed(() -> startHostMedia(attempt + 1), 700); return; }
      Toast.makeText(this, I18n.t("Không mở được camera/micro. Hãy kiểm tra quyền rồi thử lại."), Toast.LENGTH_LONG).show();
      if (socket != null) socket.send(NativeSocket.json("type", "leave"));
      finish();
    }
  }

  private LinearLayout sideButton(String iconName, String label, Runnable click) {
    LinearLayout b = column();
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    b.setPadding(0,dp(6),0,dp(6));
    ImageView i = icon(iconName, 0xffffffff);
    i.setElevation(dp(2));
    b.addView(i,new LinearLayout.LayoutParams(dp(22),dp(22)));
    TextView t = text(label, 12, 0xffffffff);
    t.setShadowLayer(4, 0, 1, 0xff000000);
    t.setGravity(Gravity.CENTER);
    t.setMaxLines(2);t.setTextSize(10);t.setIncludeFontPadding(false);
    t.setPadding(dp(2),dp(3),dp(2),0);
    b.addView(t);
    b.setContentDescription(label);
    b.setOnClickListener(v -> click.run());
    return b;
  }

  public void closed() {
    if (isFinishing()) return;
    ready = false;
    status.setText(I18n.t("Đã mất kết nối. Hãy mở lại mục Trực tiếp."));
    status.setVisibility(View.VISIBLE);
    if (rtc != null) { rtc.close(); rtc = null; }
  }

  protected void onStop() { super.onStop(); if (joined || previewing) finish(); }

  protected void onDestroy() {
    if (socket != null) socket.close();
    if (rtc != null) rtc.close();
    if (audio != null) { audio.setMode(previousMode); audio.setSpeakerphoneOn(previousSpeaker); }
    super.onDestroy();
  }

  private void effectsMenu() {
    final LiveEffects fx = rtc == null ? null : rtc.effects();
    if (fx == null) return;
    LinearLayout body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);
    LinearLayout tabs=new LinearLayout(this);FrameLayout host=new FrameLayout(this);android.widget.ScrollView scroll=new android.widget.ScrollView(this);scroll.addView(host);
    Runnable changed=()->{};
    EffectControls.Target target=EffectControls.forLive(fx);
    for(String[] tab:new String[][]{{"beauty","✨ Làm đẹp"},{"sticker","🕶 Hiệu ứng"},{"filter","◈ Màu"}}){TextView button=new KinnectText(this);button.setText(I18n.t(tab[1]));button.setTextSize(12);button.setGravity(Gravity.CENTER);button.setPadding(0,dp(14),0,dp(14));button.setTextColor(WebTheme.isDark(this)?0xfff6f1ff:0xff271f38);button.setOnClickListener(v->{host.removeAllViews();host.addView(EffectControls.panel(this,tab[0],target,changed));});tabs.addView(button,new LinearLayout.LayoutParams(0,-2,1));}
    body.addView(tabs);body.addView(scroll,new LinearLayout.LayoutParams(-1,Math.min(dp(360),getResources().getDisplayMetrics().heightPixels/2)));host.addView(EffectControls.panel(this,"beauty",target,changed));
    new Sheet(this).setTitle(I18n.t("Hiệu ứng Live")).setView(body).setPositiveButton("Xong",null).show();
  }
}
