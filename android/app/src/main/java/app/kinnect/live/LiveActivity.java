package app.kinnect.live;

import android.Manifest;
import android.content.*;import android.media.projection.MediaProjectionManager;
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
  private boolean gameControllerVisible=true;
  private boolean cameraSetup,setupStarted;private boolean creationEntry;private String liveMode="chat",gameTitle="";private boolean choosingMode,externalPicker,projectionPrompt,permissionPrompt,privacyPrompt,gameSound=true,screenPaused,gameSession;
  private boolean liveFront=true,rebindCarriedLocal;
  private LiveGameService gameService;private ServiceConnection gameConnection;private View screenCover;
  private final Handler liveHandler = new Handler(Looper.getMainLooper());
  private static final int GLIVE_BG = 0xff0a0a0c;
  private static final int GLIVE_SURFACE = 0xff141418;
  private static final int GLIVE_PILL = 0xbf18181d;
  private static final int GLIVE_BTN = 0xff28282d;
  private static final int GLIVE_RED = WebDesign.LIVE_RED;
  private static final int GLIVE_AMBER = 0xfffdd663;
  private static final int GLIVE_BLUE = 0xffa8c7fa;

  private TextView modeLabel(String mode){return text(I18n.t(modeName(mode)),12,0xffffffff);}
  private String modeName(String mode){return mode.equals("game")?"Chơi game":"Trò chuyện";}
  private String modeIcon(String mode){return mode.equals("game")?"gamepad":"video";}
  private void chooseMode(){if(!cameraSetup){startActivity(new Intent(this,StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE,"live"));finish();return;}creationEntry=true;if(ready)prepareHost();else preparationWaiting();}
  private boolean isGameLiveSupported(){if(Distribution.PLAY)return false;try{return getPackageManager().resolveService(new Intent(this,LiveGameService.class),0)!=null;}catch(Exception e){return false;}}
  private LinearLayout preparationModes(EditText title){
    LinearLayout modes=row();modes.setTag("live:preparation-modes");
    modes.setPadding(dp(3),dp(3),dp(3),dp(3));
    modes.setBackground(roundStroke(GLIVE_BTN,999,0x22ffffff));
    LinearLayout.LayoutParams modesLp=new LinearLayout.LayoutParams(-1,-2);
    modesLp.topMargin=dp(8);modesLp.bottomMargin=dp(8);
    modes.setLayoutParams(modesLp);
    String[] availableModes = isGameLiveSupported() ? new String[]{"chat","game"} : new String[]{"chat"};
    if(!isGameLiveSupported()&&"game".equals(liveMode))liveMode="chat";
    for(String mode:availableModes){
      boolean active = mode.equals(liveMode);
      TextView chip=text(I18n.t(modeName(mode)),12,active?0xff111114:0xffd8d4e2);
      chip.setSingleLine(true);
      chip.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
      chip.setGravity(Gravity.CENTER);chip.setMinHeight(UiMetrics.dpRaw(this,48));chip.setPadding(dp(12),0,dp(12),0);
      chip.setBackground(active ? round(GLIVE_AMBER, 999) : null);
      android.graphics.drawable.Drawable d=WebIcons.load(this,modeIcon(mode));d.setTint(chip.getCurrentTextColor());d.setBounds(0,0,dp(16),dp(16));
      chip.setCompoundDrawablesRelative(d,null,null,null);chip.setCompoundDrawablePadding(dp(6));
      chip.setOnClickListener(v->{if(mode.equals(liveMode)||joining||gameSession||projectionPrompt)return;if(title!=null)topicText=title.getText().toString().trim();liveMode=mode;previewing=false;if(rtc!=null){rtc.close();rtc=null;}if(ready)prepareHost();else preparationWaiting();});
      LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(0,UiMetrics.dpRaw(this,48),1);modes.addView(chip,at);
      UiMetrics.enforceMinTouchTarget(chip,48);
    }
    return modes;
  }
  private void applyDarkSystemBars(){getWindow().setStatusBarColor(GLIVE_BG);getWindow().setNavigationBarColor(GLIVE_BG);getWindow().getDecorView().setSystemUiVisibility(0);}
  private void preparationWaiting(){
    root.removeAllViews();rooms=null;root.setBackgroundColor(GLIVE_BG);applyDarkSystemBars();
    LinearLayout bar=row();bar.setPadding(dp(10),dp(8),dp(14),dp(8));
    int raw48=UiMetrics.dpRaw(this,48);
    FrameLayout closeBtn=liveAction("x","Thoát",this::finish);
    bar.addView(closeBtn,new LinearLayout.LayoutParams(raw48,raw48));
    UiMetrics.enforceMinTouchTarget(closeBtn,48);
    TextView title=text(I18n.t("Chuẩn bị Live"),18,0xffffffff);title.setTypeface(null,Typeface.BOLD);title.setPadding(dp(12),0,0,0);bar.addView(title);
    root.addView(bar);
    if(!cameraSetup)root.addView(preparationModes(null));
    status=text(I18n.t("Đang kết nối…"),14,0xffb8b3c6);status.setGravity(Gravity.CENTER);
    root.addView(status,new LinearLayout.LayoutParams(-1,0,1));
  }
  private void createHostRoom(){if(socket==null||!ready||joining||joined)return;previewing=false;host=true;joining=true;if(!sendLive("create","multiGuest",true,"liveModes",true,"liveMode",liveMode,"gameTitle",gameTitle,"topic",liveTopic,"title",topicText,"comments",liveMode.equals("game")?true:gameComments)){joining=false;host=false;}}

  private LiveEffects previewLook;
  private EditText topic, filter;
  private JSONArray lastRooms;
  private android.media.AudioManager audio;
  private int previousMode;
  private boolean previousSpeaker;
  private int BG, CARD, TEXT, MUTED, ACCENT, SOFT, LINE;

  private int dp(int n) { return Math.round(n * getResources().getDisplayMetrics().density * WebDesign.UI_SCALE); }

  private LinearLayout column() { LinearLayout c = new LinearLayout(this); c.setOrientation(LinearLayout.VERTICAL); return c; }

  private LinearLayout row() { LinearLayout c = new LinearLayout(this); c.setGravity(Gravity.CENTER_VERTICAL); return c; }

  private GradientDrawable round(int color, int r) { GradientDrawable d = new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(r)); return d; }

  private GradientDrawable roundStroke(int color, int r, int strokeColor) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(r));
    d.setStroke(dp(1), strokeColor);
    return d;
  }

  private GradientDrawable gradient(int r) {
    GradientDrawable d = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { GLIVE_RED, 0xffb91c1c });
    d.setCornerRadius(dp(r));
    return d;
  }

  private TextView text(String s, int size, int color) { TextView v = new KinnectText(this); v.setText(s); v.setTextSize(size); v.setTextColor(color); return v; }

  private ImageView icon(String name, int color) {
    ImageView v = new ImageView(this);
    int id = WebIcons.resolve(this, name);
    if (id != 0) { android.graphics.drawable.Drawable d = WebIcons.load(this, name); d.setTint(color); v.setImageDrawable(d); }
    return v;
  }

  private TextView pill(String label, boolean primary, Runnable click) {
    TextView b = text(label, 14, primary ? 0xffffffff : TEXT);
    b.setTypeface(null, Typeface.BOLD);
    b.setGravity(Gravity.CENTER);
    b.setPadding(dp(18), 0, dp(18), 0);
    b.setBackground(primary ? round(GLIVE_RED, 999) : roundStroke(SOFT, 999, LINE));
    b.setOnClickListener(v -> click.run());
    return b;
  }

  private EditText field(String hint) {
    EditText e = new KinnectInput(this);
    e.setHint(hint);
    e.setTextColor(TEXT);
    e.setHintTextColor(MUTED);
    e.setTextSize(15);
    e.setSingleLine(true);
    e.setPadding(dp(16), 0, dp(16), 0);
    e.setBackground(roundStroke(SOFT, 16, LINE));
    return e;
  }

  @Override
  public void onCreate(Bundle state) {
    boolean dark = WebTheme.isDark(this);
    setTheme(getResources().getIdentifier(dark?"Kinnect.App.Dark":"Kinnect.App.Light","style",getPackageName()));
    super.onCreate(state);
    CrashLog.install(this);
    boolean isDebugCreate = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (isDebugCreate && getIntent() != null && getIntent().getBooleanExtra("ui_review_fixture", false)) {
      NativeApi.enableFixture(this, true);
      if (getIntent().hasExtra("empty_live"))
        NativeApi.setFixtureEmptyLive(this, getIntent().getBooleanExtra("empty_live", false));
    }
    int variant = dark ? 1 : 0;
    BG = WebDesign.BG[variant]; CARD = WebDesign.CARD[variant]; TEXT = WebDesign.INK[variant];
    MUTED = WebDesign.MUTED_STRICT[variant]; ACCENT = WebDesign.PURPLE[variant]; SOFT = WebDesign.WASH[variant]; LINE = WebDesign.LINE[variant];
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    if (!dark) getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    root = column();
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener((v, i) -> { if(Build.VERSION.SDK_INT>=30){android.graphics.Insets bars=i.getInsets(android.view.WindowInsets.Type.systemBars());android.graphics.Insets keyboard=i.getInsets(android.view.WindowInsets.Type.ime());v.setPadding(bars.left,bars.top,bars.right,Math.max(bars.bottom,keyboard.bottom));}else v.setPadding(0,i.getSystemWindowInsetTop(),0,i.getSystemWindowInsetBottom()); return i; });
    setContentView(root);giftExperience=new LiveGiftExperience(this,this::sendGift);
    audio = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
    if (audio != null) {
      previousMode = audio.getMode();
      previousSpeaker = audio.isSpeakerphoneOn();
    }
    cameraSetup=getIntent().getBooleanExtra("cameraSetup",false);if(cameraSetup){liveMode="game".equals(getIntent().getStringExtra("liveMode"))&&isGameLiveSupported()?"game":"chat";gameTitle=getIntent().getStringExtra("gameTitle");if(gameTitle==null)gameTitle="";liveTopic=getIntent().getStringExtra("topic");if(liveTopic==null)liveTopic="";topicText=getIntent().getStringExtra("title");if(topicText==null)topicText="";liveFront=getIntent().getBooleanExtra("front",true);pendingHostMic=getIntent().getBooleanExtra("mic",true);gameSound=getIntent().getBooleanExtra("sound",true);gameComments=getIntent().getBooleanExtra("comments",true);}
    creationEntry=getIntent().getBooleanExtra(EXTRA_HOST,false);
    boolean isDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    boolean fixtureRoom = isDebug && NativeApi.isFixtureEnabled() && getIntent() != null && getIntent().getBooleanExtra("fixture_joined_room", false);
    if(creationEntry)preparationWaiting();
    else if (fixtureRoom) {
      try {
        JSONObject mockWelcome = new JSONObject(
            "{\"multiGuest\":false,\"room\":{\"id\":\"fixture_room_1\",\"title\":\"Giao lưu âm nhạc cuối tuần\",\"host\":\"Lê Hoàng Nam\",\"hostId\":\"u2\",\"liveMode\":\"chat\",\"viewers\":64,\"comments\":true},\"history\":[{\"name\":\"Trần Thanh Trúc\",\"text\":\"Âm thanh hôm nay trong và hay quá!\"},{\"name\":\"Linh Nhi\",\"text\":\"Chào cả nhà, cuối tuần vui vẻ nhé!\"}]}");
        joined = true;
        showRoom(mockWelcome);
        if (status != null) status.setVisibility(View.GONE);
      } catch (Exception ignored) {}
      return;
    }
    else {
      lobby();
      if (isDebug && NativeApi.isFixtureEnabled()) {
        ready = true;
        try {
          boolean emptyLive = NativeApi.isFixtureEmptyLive()
              || (getIntent() != null && getIntent().getBooleanExtra("empty_live", false));
          lastRooms = emptyLive ? new JSONArray()
              : new JSONArray("[{\"id\":\"room_1\",\"title\":\"Giao lưu âm nhạc cuối tuần\",\"host\":\"Lê Hoàng Nam\",\"liveMode\":\"chat\",\"hostId\":\"u2\",\"viewers\":64},{\"id\":\"room_2\",\"title\":\"Trò chuyện nghệ thuật & thiết kế\",\"host\":\"Trần Thanh Trúc\",\"liveMode\":\"chat\",\"hostId\":\"u3\",\"viewers\":42}]");
          renderRooms();
        } catch (Exception ignored) {}
      }
    }
    NativeApi.shared.initialize(this, ServerConfig.DEFAULT_ORIGIN);
    NativeApi.shared.call("GET", "/api/call-config", null, null, (data, error, code) -> {
      if (isFinishing() || isDestroyed()) return;
      if (error != null) { if(cameraSetup)preparationFailed("Máy chủ phản hồi chậm. Hãy thử lại.");else if(status!=null)status.setText(error); return; }
      config = data;
      ensurePrivacy(()->socket = new NativeSocket(NativeApi.shared.origin(), this));
    }, () -> {
      if (isFinishing() || isDestroyed()) return;
      String err = I18n.t("Phiên đã thay đổi, vui lòng thử lại.");
      if (cameraSetup) preparationFailed(err);
      else if (status != null) status.setText(err);
    });
    if(cameraSetup)liveHandler.postDelayed(()->{if(!isFinishing()&&!isDestroyed()&&!joined&&!projectionPrompt&&!permissionPrompt&&!privacyPrompt){preparationFailed("Máy chủ phản hồi chậm. Hãy thử lại.");}},30000);
  }

  private void preparationFailed(String message){String msg=(message!=null&&!message.trim().isEmpty())?message:"Máy chủ phản hồi chậm. Hãy thử lại.";liveToast(msg);stopGameSession();finish();}

  private void ensurePrivacy(Runnable ready){Runnable dropped=()->{if(isFinishing()||isDestroyed())return;String err=I18n.t("Phiên đã thay đổi, vui lòng thử lại.");if(cameraSetup)preparationFailed(err);else if(status!=null)status.setText(err);};NativeApi.shared.call("GET","/api/me/privacy-consent",null,null,(data,error,statusCode)->{if(isFinishing()||isDestroyed())return;if(error!=null||data==null){String err=error!=null?error:I18n.t("Máy chủ phản hồi chậm. Hãy thử lại.");if(cameraSetup)preparationFailed(err);else if(status!=null)status.setText(err);return;}if(data.optBoolean("accepted")){ready.run();return;}privacyPrompt=true;new Sheet(this).setTitle(I18n.t("Thông báo sử dụng dữ liệu")).setMessage(I18n.t(data.optString("notice"))).setPositiveButton(I18n.t("Tôi đồng ý"),(d,w)->{privacyPrompt=false;NativeApi.shared.call("POST","/api/me/privacy-consent",NativeSocket.json("accepted",true,"version",data.optString("version")),null,(accepted,failure,code)->{if(isFinishing()||isDestroyed())return;if(failure==null)ready.run();else if(cameraSetup)preparationFailed(failure);else if(status!=null)status.setText(failure);},dropped);}).setNegativeButton(I18n.t("Để sau"),(d,w)->{privacyPrompt=false;finish();}).setOnCancelListener(d->{privacyPrompt=false;finish();}).show();},dropped);}

  // Sảnh chuẩn Google Material 3 / YouTube Live: thanh tiêu đề tối giản, danh sách thẻ trực tiếp sắc nét, nút Phát live dạng Extended FAB.
  private void lobby() {
    LinearLayout bar = row();
    bar.setBackgroundColor(CARD);
    bar.setElevation(dp(1));
    bar.setPadding(dp(10), 0, dp(12), 0);
    ImageView back = icon("back", TEXT);
    back.setPadding(dp(8), dp(8), dp(8), dp(8));
    back.setBackground(round(SOFT, 999));
    back.setContentDescription(I18n.t("Quay lại"));
    back.setOnClickListener(v -> finish());
    back.setLayoutParams(new LinearLayout.LayoutParams(dp(36), dp(36)));
    bar.addView(UiMetrics.wrapMinTouchTarget(this, back, 48));
    TextView brand = text(I18n.t("Trực tiếp"), 18, TEXT);
    brand.setTypeface(null, Typeface.BOLD);
    brand.setPadding(dp(10), 0, dp(8), 0);
    bar.addView(brand);
    TextView liveBadge = text("● LIVE", 9, 0xffffffff);
    liveBadge.setTypeface(null, Typeface.BOLD);
    liveBadge.setPadding(dp(7), dp(2), dp(7), dp(2));
    liveBadge.setBackground(round(GLIVE_RED, 999));
    bar.addView(liveBadge, new LinearLayout.LayoutParams(-2, -2));
    bar.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    ImageView refresh = icon("refresh_cw", TEXT);
    refresh.setPadding(dp(8), dp(8), dp(8), dp(8));
    refresh.setBackground(round(SOFT, 999));
    refresh.setContentDescription(I18n.t("Làm mới"));
    refresh.setOnClickListener(v -> renderRooms());
    refresh.setLayoutParams(new LinearLayout.LayoutParams(dp(36), dp(36)));
    bar.addView(UiMetrics.wrapMinTouchTarget(this, refresh, 48));
    root.addView(bar, new LinearLayout.LayoutParams(-1, UiMetrics.dpRaw(this, 56)));

    FrameLayout stage = host?new FrameLayout(this):new ViewerStage();
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    LinearLayout c = column();
    c.setPadding(dp(16), dp(14), dp(16), dp(14));
    scroll.addView(c);
    stage.addView(scroll, new FrameLayout.LayoutParams(-1, -1));
    status = text(I18n.t("Đang kết nối…"), 14, MUTED);
    status.setGravity(Gravity.CENTER);
    status.setPadding(0, dp(12), 0, dp(12));
    c.addView(status, new LinearLayout.LayoutParams(-1, -2));
    rooms = column();
    rooms.setGravity(Gravity.CENTER);
    c.addView(rooms, new LinearLayout.LayoutParams(-1, 0, 1));

    LinearLayout fab = row();
    fab.setGravity(Gravity.CENTER);
    fab.setPadding(dp(18), 0, dp(20), 0);
    GradientDrawable fg = roundStroke(GLIVE_RED, 999, 0x26ffffff);
    fab.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff), fg, null));
    fab.setElevation(dp(4));
    fab.addView(icon("radio", 0xffffffff), new LinearLayout.LayoutParams(dp(17), dp(17)));
    TextView fl = text(I18n.t("Phát live"), 13, 0xffffffff);
    fl.setTypeface(null, Typeface.BOLD);
    fl.setPadding(dp(8), 0, 0, 0);
    fab.addView(fl);
    fab.setContentDescription(I18n.t("Phát trực tiếp"));
    fab.setOnClickListener(v -> askTitleAndHost());
    root.addView(stage, new LinearLayout.LayoutParams(-1, 0, 1));
    LinearLayout footer=row();
    footer.setGravity(Gravity.CENTER);
    footer.setPadding(dp(16),dp(8),dp(16),dp(12));
    footer.addView(fab,new LinearLayout.LayoutParams(-2,UiMetrics.dpRaw(this,48)));
    UiMetrics.enforceMinTouchTarget(fab,48);
    lobbyFooter = footer;
    root.addView(footer,new LinearLayout.LayoutParams(-1,-2));
  }

  private LinearLayout lobbyFooter;

  private void askTitleAndHost() { chooseMode(); }

  private String topicText = "", liveTopic = "";

  private JSONArray viewingRooms(){return lastRooms==null?new JSONArray():lastRooms;}
  private void renderRooms() {
    if (rooms == null) return;
    rooms.removeAllViews();
    if(!ready){status.setText(I18n.t("Đang kết nối…"));status.setVisibility(View.VISIBLE);return;}
    int count=0;
    for(int i=0;lastRooms!=null&&i<lastRooms.length();i++){
      JSONObject room=lastRooms.optJSONObject(i);if(room==null)continue;count++;
      LinearLayout tile=row();tile.setPadding(dp(14),dp(14),dp(14),dp(14));
      tile.setBackground(roundStroke(CARD,20,LINE));
      FrameLayout iconWell = new FrameLayout(this);
      iconWell.setBackground(round(SOFT, 999));
      iconWell.addView(icon(modeIcon(room.optString("liveMode","chat")),GLIVE_RED),new FrameLayout.LayoutParams(dp(22),dp(22),Gravity.CENTER));
      tile.addView(iconWell,new LinearLayout.LayoutParams(dp(46),dp(46)));
      LinearLayout copy=column();copy.setPadding(dp(14),0,dp(8),0);
      TextView title=text(room.optString("title").isEmpty()?room.optString("host"):room.optString("title"),15,TEXT);
      title.setTypeface(null,Typeface.BOLD);title.setMaxLines(2);copy.addView(title);
      TextView sub=text(I18n.t(modeName(room.optString("liveMode","chat")))+" · "+room.optString("host")+" · "+room.optInt("viewers")+" "+I18n.t("người xem"),12,MUTED);
      sub.setPadding(0,dp(3),0,0);copy.addView(sub);
      tile.addView(copy,new LinearLayout.LayoutParams(0,-2,1));
      TextView liveChip=text("LIVE",10,0xffffffff);liveChip.setTypeface(null,Typeface.BOLD);liveChip.setPadding(dp(8),dp(4),dp(8),dp(4));liveChip.setBackground(round(GLIVE_RED,999));
      tile.addView(liveChip,new LinearLayout.LayoutParams(-2,-2));
      tile.setOnClickListener(v->{if(!joining&&!joined&&ready){joining=true;if(!sendLive("join","room",room.optString("id"),"multiGuest",true,"liveModes",true))joining=false;}});
      LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(-1,-2);at.bottomMargin=dp(10);rooms.addView(tile,at);
      UiMetrics.enforceMinTouchTarget(tile,48);
    }
    status.setVisibility(View.GONE);
    if(count>0){rooms.setGravity(Gravity.TOP|Gravity.CENTER_HORIZONTAL);if(lobbyFooter!=null)lobbyFooter.setVisibility(View.VISIBLE);return;}
    rooms.setGravity(Gravity.CENTER);
    if(lobbyFooter!=null)lobbyFooter.setVisibility(View.GONE);
    LinearLayout empty = column();
    empty.setGravity(Gravity.CENTER);
    empty.setPadding(dp(24), dp(30), dp(24), dp(28));
    empty.setBackground(roundStroke(CARD, 24, LINE));
    FrameLayout outerRing = new FrameLayout(this);
    outerRing.setBackground(round(SOFT, 999));
    FrameLayout bubble = new FrameLayout(this);
    bubble.setBackground(round(0x22d61f26, 999));
    bubble.addView(icon("radio", GLIVE_RED), new FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER));
    outerRing.addView(bubble, new FrameLayout.LayoutParams(dp(56), dp(56), Gravity.CENTER));
    empty.addView(outerRing, new LinearLayout.LayoutParams(dp(76), dp(76)));
    TextView t = text(I18n.t("Chưa có buổi live"), 18, TEXT);
    t.setTypeface(null, Typeface.BOLD);
    t.setGravity(Gravity.CENTER);
    t.setPadding(0, dp(16), 0, dp(4));
    empty.addView(t,new LinearLayout.LayoutParams(-1,-2));
    TextView subtitle=text(I18n.t("Hãy là người mở màn!"),14,MUTED);
    subtitle.setGravity(Gravity.CENTER);
    empty.addView(subtitle,new LinearLayout.LayoutParams(-1,-2));
    LinearLayout emptyCta = row();
    emptyCta.setGravity(Gravity.CENTER);
    emptyCta.setPadding(dp(20), 0, dp(22), 0);
    GradientDrawable ctaBg = roundStroke(GLIVE_RED, 999, 0x26ffffff);
    emptyCta.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff), ctaBg, null));
    emptyCta.setElevation(dp(3));
    emptyCta.addView(icon("radio", 0xffffffff), new LinearLayout.LayoutParams(dp(17), dp(17)));
    TextView ctaLabel = text(I18n.t("Phát live"), 13, 0xffffffff);
    ctaLabel.setTypeface(null, Typeface.BOLD);
    ctaLabel.setPadding(dp(8), 0, 0, 0);
    emptyCta.addView(ctaLabel);
    emptyCta.setContentDescription(I18n.t("Phát trực tiếp"));
    emptyCta.setOnClickListener(v -> askTitleAndHost());
    LinearLayout.LayoutParams ctaLp = new LinearLayout.LayoutParams(-2, UiMetrics.dpRaw(this, 48));
    ctaLp.topMargin = dp(20);
    empty.addView(emptyCta, ctaLp);
    UiMetrics.enforceMinTouchTarget(emptyCta, 48);
    rooms.addView(empty, new LinearLayout.LayoutParams(-1, -2));
  }

  /** Local preview only: no create/join/signaling until the explicit start button. */
  @Override public void startActivityForResult(Intent intent,int request){if(request==321||request==322)externalPicker=true;super.startActivityForResult(intent,request);}
  private TextView previewBadge(){
    TextView badge=text("●  " + I18n.t("Xem trước · Chưa phát sóng"),12,GLIVE_AMBER);
    badge.setTypeface(null, Typeface.BOLD);
    badge.setGravity(Gravity.CENTER);badge.setSingleLine(false);badge.setMinHeight(dp(36));
    badge.setPadding(dp(14),dp(7),dp(14),dp(7));badge.setBackground(roundStroke(GLIVE_PILL,999,0x33fdd663));
    return badge;
  }
  private void showHostPreview(){
    if(previewing||joined)return;if(liveMode.equals("game")){showGamePreview();return;}previewing=true;host=false;if(rtc!=null){rtc.close();rtc=null;}
    root.removeAllViews();root.setBackgroundColor(GLIVE_BG);applyDarkSystemBars();
    FrameLayout stage=new FrameLayout(this);stage.setBackground(round(0xff000000,24));stage.setClipToOutline(true);
    LinearLayout.LayoutParams stageLp=new LinearLayout.LayoutParams(-1,0,1);stageLp.setMargins(dp(6),dp(6),dp(6),0);
    root.addView(stage,stageLp);
    SurfaceViewRenderer display=new SurfaceViewRenderer(this);localLive=display;stage.addView(display,new FrameLayout.LayoutParams(-1,-1));
    TextView close=text(I18n.t("×"),26,0xffffffff);close.setGravity(Gravity.CENTER);close.setBackground(roundStroke(GLIVE_PILL,999,0x28ffffff));close.setContentDescription(I18n.t("Đóng camera chuẩn bị Live"));close.setOnClickListener(v->finish());FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(dp(42),dp(42),Gravity.TOP|Gravity.START);cp.setMargins(dp(12),dp(12),0,0);close.setLayoutParams(cp);stage.addView(UiMetrics.wrapMinTouchTarget(this,close,48));
    TextView badge=previewBadge();FrameLayout.LayoutParams bp=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);bp.setMargins(dp(64),dp(14),dp(64),0);stage.addView(badge,bp);
    LinearLayout controls=column();controls.setPadding(dp(16),dp(14),dp(16),dp(16));
    GradientDrawable deckBg=new GradientDrawable();deckBg.setColor(GLIVE_SURFACE);float r=dp(24);deckBg.setCornerRadii(new float[]{r,r,r,r,0,0,0,0});controls.setBackground(deckBg);
    root.addView(controls,new LinearLayout.LayoutParams(-1,-2));
    EditText title=field(I18n.t("Tiêu đề buổi Live"));title.setText(topicText);title.setTextSize(13);title.setGravity(Gravity.CENTER_VERTICAL);title.setTextColor(0xffffffff);title.setHintTextColor(0xffb8b3c6);title.setBackground(roundStroke(GLIVE_BTN,12,0x22ffffff));title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});controls.addView(title,new LinearLayout.LayoutParams(-1,UiMetrics.dpRaw(this,48)));UiMetrics.enforceMinTouchTarget(title,48);
    controls.addView(preparationModes(title));
    LinearLayout actions=row();actions.setPadding(0,dp(2),0,dp(6));final boolean[] mic={true};
    LinearLayout flipBtn=sideButton("flip",I18n.t("Lật camera"),()->{if(rtc!=null)rtc.flip();});actions.addView(flipBtn,new LinearLayout.LayoutParams(0,-2,1));UiMetrics.enforceMinTouchTarget(flipBtn,48);
    LinearLayout beautyBtn=sideButton("wand",I18n.t("Làm đẹp"),this::effectsMenu);actions.addView(beautyBtn,new LinearLayout.LayoutParams(0,-2,1));UiMetrics.enforceMinTouchTarget(beautyBtn,48);
    final LinearLayout[] micBtnRef={null};
    Runnable togglePreviewMic=()->{mic[0]=!mic[0];badge.setText("●  "+(mic[0]?I18n.t("Xem trước · Mic sẽ bật khi phát"):I18n.t("Xem trước · Mic sẽ tắt khi phát")));if(micBtnRef[0]!=null){micBtnRef[0].setAlpha(1f);micBtnRef[0].setContentDescription(I18n.t(mic[0]?"Tắt micro":"Bật micro"));if(micBtnRef[0].getChildCount()>0&&micBtnRef[0].getChildAt(0) instanceof FrameLayout){FrameLayout circle=(FrameLayout)micBtnRef[0].getChildAt(0);circle.setBackground(roundStroke(mic[0]?GLIVE_BTN:GLIVE_RED,99,0x22ffffff));if(circle.getChildCount()>0&&circle.getChildAt(0) instanceof ImageView){String micGlyph=mic[0]?"mic":(WebIcons.resolve(this,"mic_off")!=0?"mic_off":"mic");int gid=WebIcons.resolve(this,micGlyph);if(gid!=0){android.graphics.drawable.Drawable gd=WebIcons.load(this,micGlyph);gd.setTint(0xfff1f3f4);((ImageView)circle.getChildAt(0)).setImageDrawable(gd);}}}if(micBtnRef[0].getChildCount()>1&&micBtnRef[0].getChildAt(1) instanceof TextView)((TextView)micBtnRef[0].getChildAt(1)).setText(I18n.t(mic[0]?"Mic: Bật":"Mic: Tắt"));}};
    LinearLayout micBtn=sideButton("mic",I18n.t("Mic: Bật"),togglePreviewMic);micBtn.setContentDescription(I18n.t("Tắt micro"));micBtnRef[0]=micBtn;actions.addView(micBtn,new LinearLayout.LayoutParams(0,-2,1));UiMetrics.enforceMinTouchTarget(micBtn,48);controls.addView(actions);
    TextView start=pill(I18n.t("Bắt đầu Live"),true,()->{});start.setTextSize(13);start.setEnabled(false);start.setAlpha(1f);start.setBackground(roundStroke(GLIVE_BTN,999,0x33ffffff));start.setTextColor(0xffb8b3c6);controls.addView(start,new LinearLayout.LayoutParams(-1,UiMetrics.dpRaw(this,48)));UiMetrics.enforceMinTouchTarget(start,48);status=text(I18n.t("Đang mở camera…"),12,0xffb8b3c6);status.setGravity(Gravity.CENTER);status.setPadding(0,dp(8),0,dp(2));controls.addView(status,new LinearLayout.LayoutParams(-1,-2));
    try{rtc=new NativeRtc(this,config,display,null,new NativeRtc.Events(){public void signal(String peer,JSONObject payload){}public void status(String text){status.setText(text);}public void cameraFacing(boolean isFront){liveFront=isFront;}},false);final NativeRtc previewRtc=rtc;display.addFrameListener(new org.webrtc.EglRenderer.FrameListener(){private boolean received;public void onFrame(android.graphics.Bitmap bitmap){if(bitmap!=null)bitmap.recycle();if(received)return;received=true;runOnUiThread(()->{if(!previewing||rtc!=previewRtc||isFinishing()||isDestroyed())return;status.setText(I18n.t("Camera đã sẵn sàng · Chưa phát sóng"));start.setEnabled(true);start.setAlpha(1f);start.setBackground(round(GLIVE_RED,999));start.setTextColor(0xffffffff);});}},0f);rtc.media(this,true,liveFront);rtc.microphone(false);start.setOnClickListener(v->{if(!previewing||!ready||joining)return;topicText=title.getText().toString().trim();start.setEnabled(false);previewLook=rtc.effects();carryPreview=true;pendingHostMic=mic[0];rtc.microphone(pendingHostMic);createHostRoom();});}
    catch(Exception error){if(rtc!=null){rtc.close();rtc=null;}status.setText(I18n.t("Không mở được camera. Kiểm tra quyền camera/micro rồi mở lại."));}
  }
  private LiveGamePicker gamePicker;private boolean gameComments=true;private boolean roomComments=true;private boolean pendingHostMic=true;
  private void showGamePreview(){
    previewing=true;host=false;if(rtc!=null){rtc.close();rtc=null;}root.removeAllViews();root.setBackgroundColor(BG);
    ScrollView scroll=new ScrollView(this);LinearLayout body=column();body.setPadding(dp(20),dp(16),dp(20),dp(24));scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,-1));
    ImageView back=icon("x",TEXT);back.setPadding(dp(10),dp(10),dp(10),dp(10));back.setContentDescription(I18n.t("Thoát"));back.setBackground(roundStroke(SOFT,999,LINE));back.setOnClickListener(v->finish());back.setLayoutParams(new LinearLayout.LayoutParams(dp(42),dp(42)));body.addView(UiMetrics.wrapMinTouchTarget(this,back,48));
    FrameLayout gameBadge=new FrameLayout(this);gameBadge.setBackground(round(SOFT,999));gameBadge.addView(icon("gamepad",GLIVE_RED),new FrameLayout.LayoutParams(dp(34),dp(34),Gravity.CENTER));LinearLayout.LayoutParams art=new LinearLayout.LayoutParams(dp(68),dp(68));art.gravity=Gravity.CENTER;art.setMargins(0,dp(20),0,dp(14));body.addView(gameBadge,art);
    TextView heading=text(I18n.t("Chơi game trực tiếp"),22,TEXT);heading.setTypeface(null,Typeface.BOLD);heading.setGravity(Gravity.CENTER);body.addView(heading);
    TextView hint=text(I18n.t("Chọn một ứng dụng game trong hộp thoại Android. Màn hình chỉ được phát sau khi bạn đồng ý."),14,MUTED);hint.setGravity(Gravity.CENTER);hint.setPadding(0,dp(8),0,dp(16));body.addView(hint);
    EditText title=field(I18n.t("Tiêu đề buổi Live"));title.setText(topicText);title.setGravity(Gravity.CENTER_VERTICAL);title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});body.addView(title,new LinearLayout.LayoutParams(-1,UiMetrics.dpRaw(this,50)));UiMetrics.enforceMinTouchTarget(title,48);body.addView(preparationModes(title));
    EditText name=field(I18n.t("Chọn game"));name.setText(gameTitle);name.setGravity(Gravity.CENTER_VERTICAL);name.setFocusable(false);name.setCursorVisible(false);name.setKeyListener(null);name.setFocusable(false);name.setFocusableInTouchMode(false);name.setShowSoftInputOnFocus(false);name.setContentDescription(I18n.t("Chọn game"));name.setOnClickListener(v->{if(gamePicker!=null)gamePicker.close();gamePicker=new LiveGamePicker(this,gameTitle,value->{gameTitle=value;name.setText(value);});gamePicker.show();});name.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(60)});LinearLayout.LayoutParams np=new LinearLayout.LayoutParams(-1,UiMetrics.dpRaw(this,50));np.topMargin=dp(10);body.addView(name,np);UiMetrics.enforceMinTouchTarget(name,48);
    CheckBox mic=new CheckBox(this);mic.setTypeface(ApprovedTypography.font(this,0));mic.setTextColor(TEXT);mic.setText(I18n.t("Bật micro bình luận"));mic.setChecked(pendingHostMic);body.addView(mic);UiMetrics.enforceMinTouchTarget(mic,48);
    CheckBox sound=new CheckBox(this);sound.setTypeface(ApprovedTypography.font(this,0));sound.setTextColor(TEXT);sound.setText(I18n.t("Phát tiếng game nếu được ứng dụng cho phép"));sound.setChecked(gameSound&&Build.VERSION.SDK_INT>=29);sound.setEnabled(Build.VERSION.SDK_INT>=29);body.addView(sound);UiMetrics.enforceMinTouchTarget(sound,48);
    CheckBox comments=new CheckBox(this);comments.setTypeface(ApprovedTypography.font(this,0));comments.setTextColor(TEXT);comments.setText(I18n.t("Bình luận nổi khi chơi game"));comments.setChecked(gameComments);comments.setOnCheckedChangeListener((b,on)->gameComments=on);body.addView(comments);UiMetrics.enforceMinTouchTarget(comments,48);
    TextView privacy=text(I18n.t("Nên chọn chia sẻ một ứng dụng và bật Không làm phiền. Khi chia sẻ toàn màn hình, nội dung và thông báo khác có thể xuất hiện."),12,MUTED);privacy.setPadding(dp(12),dp(10),dp(12),dp(10));privacy.setBackground(roundStroke(SOFT,14,LINE));LinearLayout.LayoutParams plp=new LinearLayout.LayoutParams(-1,-2);plp.setMargins(0,dp(10),0,dp(16));body.addView(privacy,plp);
    TextView start=pill(I18n.t("Chọn màn hình & Bắt đầu Live"),true,()->{topicText=title.getText().toString().trim();gameTitle=name.getText().toString().trim();pendingHostMic=mic.isChecked();gameSound=sound.isChecked();requestGameProjection();});start.setMinHeight(UiMetrics.dpRaw(this,52));start.setPadding(dp(14),dp(12),dp(14),dp(12));body.addView(start,new LinearLayout.LayoutParams(-1,-2));UiMetrics.enforceMinTouchTarget(start,48);
    status=text(I18n.t("Chưa phát sóng · Camera không bật"),12,MUTED);status.setGravity(Gravity.CENTER);status.setPadding(0,dp(14),0,0);body.addView(status);
  }
  private void requestGameProjection(){if(projectionPrompt||gameSession||joining||!ready)return;if(gameComments&&!android.provider.Settings.canDrawOverlays(this)){projectionPrompt=true;try{startActivityForResult(new Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,android.net.Uri.parse("package:"+getPackageName())),324);}catch(Exception e){projectionPrompt=false;gameComments=false;liveToast("Chưa bật bình luận nổi; vẫn có thể phát game.");if(cameraSetup)requestGameProjection();}return;}projectionPrompt=true;try{MediaProjectionManager manager=(MediaProjectionManager)getSystemService(MEDIA_PROJECTION_SERVICE);Intent capture=cameraSetup&&Build.VERSION.SDK_INT>=34?manager.createScreenCaptureIntent(android.media.projection.MediaProjectionConfig.createConfigForDefaultDisplay()):manager.createScreenCaptureIntent();startActivityForResult(capture,323);}catch(Exception e){projectionPrompt=false;liveToast("Không mở được quyền chia sẻ màn hình.");if(cameraSetup)finish();}}
  @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);externalPicker=false;if(request==324){projectionPrompt=false;if(cameraSetup){gameComments=android.provider.Settings.canDrawOverlays(this);requestGameProjection();}else liveToast(android.provider.Settings.canDrawOverlays(this)?"Đã bật bình luận nổi. Bấm bắt đầu Live.":"Chưa cấp quyền bình luận nổi. Có thể tắt lựa chọn này để phát.");return;}if(request!=323)return;projectionPrompt=false;if(result!=RESULT_OK||data==null){if(cameraSetup){liveToast("Đã hủy chia sẻ · Chưa phát sóng");finish();}else status.setText(I18n.t("Đã hủy chia sẻ · Chưa phát sóng"));return;}if(!ready||isFinishing()){liveToast("Mất kết nối; hãy chọn chia sẻ lại.");return;}startGameSession(data);}
  private void startGameSession(Intent permission){
    Intent serviceIntent=new Intent(this,LiveGameService.class).setAction(LiveGameService.START);
    try{if(Build.VERSION.SDK_INT>=26)startForegroundService(serviceIntent);else startService(serviceIntent);}catch(Exception e){liveToast("Không khởi động được Live game.");if(cameraSetup)finish();return;}
    gameConnection=new ServiceConnection(){public void onServiceConnected(ComponentName name,IBinder binder){if(isFinishing()||isDestroyed()){try{unbindService(this);}catch(Exception ignored){}try{stopService(new Intent(LiveActivity.this,LiveGameService.class));}catch(Exception ignored){}return;}try{gameService=((LiveGameService.SessionBinder)binder).service();boolean fgOk=gameService.attach(new LiveGameService.Controls(){public void reply(String text){if(joined&&ready)sendLive("chat","text",text);else liveToast("Chưa kết nối để gửi bình luận.");}public void stop(){sendLive("leave");stopGameSession();finish();}public void pause(){toggleScreenPause();}public void mic(){liveMic=!liveMic;if(rtc!=null)rtc.microphone(liveMic);syncGameVisibility();}});
      if(!fgOk){throw new IllegalStateException("startForeground failed");}
      gameSession=true;screenPaused=false;gameControllerVisible=true;localLive=null;rtc=new NativeRtc(LiveActivity.this,config,null,null,new NativeRtc.Events(){public void signal(String peer,JSONObject value){}public void status(String value){liveToast(value);}},true);
      rtc.screen(LiveActivity.this,permission,()->{sendLive("leave");stopGameSession();finish();},gameSound);syncGameVisibility();rtc.microphone(pendingHostMic);liveMic=pendingHostMic;carryPreview=true;createHostRoom();
    }catch(Exception e){if(rtc!=null){rtc.close();rtc=null;}stopGameSession();joining=false;previewing=false;if(cameraSetup){liveToast("Không chia sẻ được màn hình. Hãy thử lại.");finish();return;}showGamePreview();status.setText(I18n.t("Không chia sẻ được màn hình. Hãy cấp quyền lại."));}}
    public void onServiceDisconnected(ComponentName name){if(gameSession){gameSession=false;sendLive("leave");finish();}}};
    if(!bindService(new Intent(this,LiveGameService.class),gameConnection,Context.BIND_AUTO_CREATE)){gameConnection=null;try{stopService(new Intent(this,LiveGameService.class));}catch(Exception ignored){}liveToast("Không khởi động được Live game.");if(cameraSetup)finish();}
  }
  private void stopGameSession(){gameSession=false;LiveGameService service=gameService;gameService=null;if(service!=null)service.detach();ServiceConnection connection=gameConnection;gameConnection=null;if(connection!=null)try{unbindService(connection);}catch(Exception ignored){}try{stopService(new Intent(this,LiveGameService.class));}catch(Exception ignored){}if(liveMode.equals("game")&&rtc!=null){NativeRtc old=rtc;rtc=null;old.close();}}
  private void syncGameVisibility(){if(!gameSession||rtc==null)return;boolean hold=screenPaused||gameControllerVisible;if(screenCover!=null&&host)screenCover.setVisibility(hold?View.VISIBLE:View.GONE);rtc.screenPaused(hold);if(joined&&ready)sendLive("live-game-state","paused",hold);if(gameService!=null)gameService.flags(hold,!liveMic);}
  private void toggleScreenPause(){if(!gameSession||rtc==null)return;screenPaused=!screenPaused;syncGameVisibility();}
  private void openGameApp(){if(!gameSession)return;Intent game=LiveGameLaunch.intent(this,gameTitle);if(game==null){liveToast("Không tìm thấy game trên máy.");sendLive("leave");stopGameSession();finish();return;}try{startActivity(game);}catch(Exception e){liveToast("Không mở được game. Chưa phát tiếp.");sendLive("leave");stopGameSession();finish();}}
  private void mountGame(FrameLayout stage){
    LinearLayout cover=column();cover.setGravity(Gravity.CENTER);cover.setPadding(dp(30),dp(30),dp(30),dp(30));cover.setBackgroundColor(GLIVE_BG);
    FrameLayout shieldWell=new FrameLayout(this);shieldWell.setBackground(roundStroke(GLIVE_BTN,999,0x28ffffff));shieldWell.addView(icon("gamepad",GLIVE_AMBER),new FrameLayout.LayoutParams(dp(28),dp(28),Gravity.CENTER));
    LinearLayout.LayoutParams swLp=new LinearLayout.LayoutParams(dp(64),dp(64));swLp.bottomMargin=dp(16);cover.addView(shieldWell,swLp);
    TextView coverText=text(I18n.t(host?"Màn hình điều khiển · Không phát phần này":"Chủ phòng đang tạm che màn hình"),16,0xffffffff);coverText.setTypeface(null,Typeface.BOLD);coverText.setGravity(Gravity.CENTER);cover.addView(coverText);
    if(host){TextView open=text(I18n.t("Mở game"),15,0xff111114);open.setTypeface(null,Typeface.BOLD);open.setGravity(Gravity.CENTER);open.setMinHeight(UiMetrics.dpRaw(this,48));open.setPadding(dp(28),dp(12),dp(28),dp(12));open.setBackground(round(GLIVE_AMBER,999));open.setOnClickListener(v->openGameApp());LinearLayout.LayoutParams button=new LinearLayout.LayoutParams(-2,-2);button.topMargin=dp(20);cover.addView(open,button);UiMetrics.enforceMinTouchTarget(open,48);}
    cover.setVisibility(host?View.VISIBLE:View.GONE);screenCover=cover;FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-1,-1);stage.addView(cover,1,cp);
    TextView mode=text(I18n.t("Chơi game")+(roomInfo.optString("gameTitle").isEmpty()?"":" · "+roomInfo.optString("gameTitle"))+(host?" · "+I18n.t("Điều khiển"):""),13,0xffffffff);mode.setTypeface(null,Typeface.BOLD);mode.setGravity(Gravity.CENTER_VERTICAL);mode.setMinHeight(UiMetrics.dpRaw(this,48));mode.setPadding(dp(14),dp(10),dp(14),dp(10));mode.setBackground(roundStroke(GLIVE_PILL,999,0x33fdd663));android.graphics.drawable.Drawable modeGlyph=WebIcons.load(this,"gamepad");modeGlyph.setTint(0xffffffff);modeGlyph.setBounds(0,0,dp(16),dp(16));mode.setCompoundDrawablesRelative(modeGlyph,null,null,null);mode.setCompoundDrawablePadding(dp(6));if(host)mode.setOnClickListener(v->new Sheet(this).setTitle(I18n.t("Live game")).setItemIcons(new String[]{"gamepad","shield_check","mic","log_out"}).setItems(new String[]{I18n.t("Mở game"),I18n.t(screenPaused?"Tiếp tục chia sẻ":"Tạm che màn hình"),I18n.t(liveMic?"Tắt mic":"Bật mic"),I18n.t("Kết thúc Live")},(d,n)->{if(n==0)openGameApp();if(n==1)toggleScreenPause();if(n==2){liveMic=!liveMic;if(rtc!=null)rtc.microphone(liveMic);syncGameVisibility();}if(n==3)confirmLeave();}).setNegativeButton(I18n.t("Quay lại"),null).show());FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.START);at.setMargins(dp(12),UiMetrics.dpRaw(this,104),dp(12),0);stage.addView(mode,at);if(host)UiMetrics.enforceMinTouchTarget(mode,48);
  }
  private final class ViewerStage extends VerticalMediaStage {
    ViewerStage(){super(LiveActivity.this,direction->{if(host||!liveRole.equals("viewer"))return false;return switchLive(direction);});}
  }

  private void prepareHost() {
    if (socket == null || !ready) { Toast.makeText(this, I18n.t("Đang kết nối máy chủ, thử lại sau giây lát."), Toast.LENGTH_SHORT).show(); return; }
    if ((!liveMode.equals("game")&&checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) || checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      permissionPrompt = true;
      requestPermissions(liveMode.equals("game")?new String[]{Manifest.permission.RECORD_AUDIO}:new String[] { Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO }, 301);
      return;
    }
    if(cameraSetup){startCameraSetup();return;}showHostPreview();
  }

  private void startCameraSetup(){
    if(setupStarted||joining||joined)return;setupStarted=true;
    if(liveMode.equals("game")){if(LiveGameLaunch.intent(this,gameTitle)==null){liveToast("Không tìm thấy game trên máy.");finish();return;}requestGameProjection();return;}
    previewing=true;root.removeAllViews();root.setBackgroundColor(GLIVE_BG);applyDarkSystemBars();
    FrameLayout stage=new FrameLayout(this);root.addView(stage,new LinearLayout.LayoutParams(-1,0,1));
    final SurfaceViewRenderer[] displayHolder={null};
    FrameLayout closeBtn=liveAction("x","Thoát",this::finish);
    int raw48=UiMetrics.dpRaw(this,48);
    FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(raw48,raw48,Gravity.TOP|Gravity.START);
    cp.setMargins(dp(12),dp(12),0,0);
    stage.addView(closeBtn,cp);
    UiMetrics.enforceMinTouchTarget(closeBtn,48);
    status=text(I18n.t("Đang bắt đầu Live…"),13,0xffe8eaed);
    status.setGravity(Gravity.CENTER);
    status.setPadding(dp(16),dp(9),dp(16),dp(9));
    status.setBackground(roundStroke(GLIVE_PILL,99,0x24ffffff));
    FrameLayout.LayoutParams sp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);
    sp.setMargins(dp(20),0,dp(20),dp(36));
    stage.addView(status,sp);
    openSetupCamera(stage,displayHolder,0);
  }

  private void openSetupCamera(final FrameLayout stage,final SurfaceViewRenderer[] displayHolder,final int attempt){
    if(isFinishing()||isDestroyed()||joining||joined)return;
    if(rtc!=null){rtc.close();rtc=null;}
    if(displayHolder[0]!=null&&displayHolder[0].getParent() instanceof ViewGroup){((ViewGroup)displayHolder[0].getParent()).removeView(displayHolder[0]);}
    SurfaceViewRenderer display=new SurfaceViewRenderer(this);
    displayHolder[0]=display;localLive=display;
    stage.addView(display,0,new FrameLayout.LayoutParams(-1,-1));
    final boolean[] finishedAttempt={false};
    try{
      rtc=new NativeRtc(this,config,display,null,new NativeRtc.Events(){public void signal(String peer,JSONObject value){}public void status(String value){if(status!=null)status.setText(value);}public void cameraFacing(boolean isFront){liveFront=isFront;}},false);
      final NativeRtc owner=rtc;
      final Runnable[] goLiveRef=new Runnable[1];
      final Runnable fallbackGoLive=()->goLiveRef[0].run();
      goLiveRef[0]=()->{
        if(finishedAttempt[0]||isFinishing()||isDestroyed()||rtc!=owner||joining||joined)return;
        if(!ready){liveHandler.postDelayed(goLiveRef[0],250);return;}
        liveHandler.removeCallbacks(fallbackGoLive);
        finishedAttempt[0]=true;carryPreview=true;liveMic=pendingHostMic;rtc.microphone(pendingHostMic);createHostRoom();
      };
      final Runnable retryOrFail=()->{
        liveHandler.removeCallbacks(fallbackGoLive);
        if(finishedAttempt[0]||isFinishing()||isDestroyed()||rtc!=owner)return;
        finishedAttempt[0]=true;
        if(attempt<4){if(status!=null)status.setText(I18n.t("Đang mở camera…"));liveHandler.postDelayed(()->openSetupCamera(stage,displayHolder,attempt+1),400);return;}
        if(rtc!=null){rtc.close();rtc=null;}
        liveToast("Không mở được camera. Hãy thử lại.");finish();
      };
      rtc.setCameraCallbacks(goLiveRef[0],retryOrFail);
      display.addFrameListener(new org.webrtc.EglRenderer.FrameListener(){boolean once;public void onFrame(android.graphics.Bitmap bitmap){if(bitmap!=null)bitmap.recycle();if(once)return;once=true;runOnUiThread(goLiveRef[0]);}},0f);
      rtc.media(this,true,liveFront);
      LiveEffects look=rtc.effects();
      if(look!=null){
        look.filter=getIntent().getStringExtra("filter")==null?"none":getIntent().getStringExtra("filter");
        look.sticker=getIntent().getStringExtra("sticker")==null?"none":getIntent().getStringExtra("sticker");
        look.beautyOn=getIntent().getBooleanExtra("beauty",false);
        look.smooth=getIntent().getFloatExtra("smooth",.5f);
        look.blemish=getIntent().getFloatExtra("blemish",.4f);
        look.eyes=getIntent().getFloatExtra("eyes",.2f);
        look.lips=getIntent().getFloatExtra("lips",0);
      }
      rtc.microphone(false);
      liveHandler.postDelayed(fallbackGoLive,3500);
    }catch(Exception e){
      finishedAttempt[0]=true;
      if(rtc!=null){rtc.close();rtc=null;}
      if(attempt<4){liveHandler.postDelayed(()->openSetupCamera(stage,displayHolder,attempt+1),400);return;}
      liveToast("Không mở được camera. Hãy thử lại.");finish();
    }
  }

  public void onRequestPermissionsResult(int code, String[] p, int[] grants) {
    super.onRequestPermissionsResult(code, p, grants);
    permissionPrompt = false;
    if(code==302){boolean allowed=grants.length>0;for(int grant:grants)allowed&=grant==0;if(allowed)acceptGuest();else liveToast("Cần quyền micro/camera để lên Live.");return;}
    if (code == 301) {
      boolean allowed=grants.length>0;for(int grant:grants)allowed&=grant==0;if (allowed) prepareHost();
      else if (cameraSetup) { liveToast("Cần quyền camera và micro để phát trực tiếp."); finish(); }
      else { status.setText(I18n.t("Cần quyền camera và micro để phát trực tiếp.")); status.setVisibility(View.VISIBLE); }
    }
  }

  public void event(JSONObject m) {
    String type = m.optString("type");
    if (type.equals("welcome")) {if(giftExperience!=null)giftExperience.configure(m.optJSONObject("liveGifts"));
      ready = true;socketId=m.optString("id");
      if(!creationEntry)renderRooms();
      // Mở từ tab "Trực tiếp": vào thẳng phòng đã chọn.
      String room = getIntent().getStringExtra(EXTRA_ROOM);
      if (room != null && !joined && !joining) { host = false; joining = true; if (!sendLive("join", "multiGuest", true, "liveModes", true, "room", room)) joining = false; getIntent().removeExtra(EXTRA_ROOM); }
      if (getIntent().getBooleanExtra(EXTRA_HOST, false) && !joined) { getIntent().removeExtra(EXTRA_HOST); askTitleAndHost(); }
    }
    if (type.equals("rooms")) { lastRooms = m.optJSONArray("rooms"); if (!joined && !previewing) { renderRooms();if(!creationEntry)autoJoin(); } }
    if (type.equals("joined")) { joined = true; joining = false; showRoom(m);if(gameSession){syncGameVisibility();if(cameraSetup)openGameApp();} }
    if(type.equals("viewers")){JSONArray users=m.optJSONArray("users");java.util.List<String> nameList=new java.util.ArrayList<>();for(int i=0;users!=null&&i<users.length();i++){JSONObject u=users.optJSONObject(i);if(u!=null)nameList.add(u.optString("name"));}String[] names=nameList.toArray(new String[0]);Sheet sheet=new Sheet(this).setTitle(I18n.t("Người đang xem")).setNegativeButton(I18n.t("Đóng"),null);if(names.length>0)sheet.setItemIcon("user_round").setItems(names,(d,n)->{});else sheet.setMessage(I18n.t("Chưa có người xem"));sheet.show();return;}
    if(type.equals("live-mode-state")){if(!currentRoom.equals(m.optString("room")))return;if(screenCover!=null)screenCover.setVisibility((host&&gameSession?screenPaused||gameControllerVisible:m.optBoolean("screenPaused"))?View.VISIBLE:View.GONE);return;}
    if(type.equals("live-mode-error")){liveToast(m.optString("message"));return;}
    if(type.equals("live-stage")){applyLiveStage(m);return;}
    if(type.equals("live-guest-invitation")){invitation(m);return;}
    if(type.equals("live-guest-state")){guestRequests=m.optJSONArray("requests")==null?new JSONArray():m.optJSONArray("requests");if(guestAction!=null){guestAction.setText(String.valueOf(guestRequests.length()));guestAction.setVisibility(guestRequests.length()>0?View.VISIBLE:View.GONE);}return;}
    if(type.equals("live-guest-list")){guestUsers=m.optJSONArray("users")==null?new JSONArray():m.optJSONArray("users");guestManagement();return;}
    if(type.equals("live-guest-requested")){guestRequested=true;liveToast("Đã gửi yêu cầu lên Live");return;}
    if(type.equals("live-guest-cancelled")||type.equals("live-guest-declined")){guestRequested=false;liveToast(type.equals("live-guest-declined")?"Chủ phòng đã từ chối yêu cầu":"Đã hủy yêu cầu");return;}
    if(type.equals("live-guest-error")){clearPendingGuest();liveToast(m.optString("message"));return;}
    if (type.equals("peer") && rtc != null) rtc.offer(m.optString("id"));
    if (type.equals("signal") && rtc != null && (liveState==null||m.optInt("revision")==0||m.optInt("revision")==liveState.optInt("revision"))) rtc.signal(m.optString("from"), m);
    if (type.equals("peer-left") && rtc != null) rtc.remove(m.optString("id"));
    if(type.equals("count")&&viewers!=null){viewers.setText(String.valueOf(m.optInt("viewers")));if(gameService!=null)gameService.viewers(m.optInt("viewers"));renderAudience(m.optJSONArray("users"));}
    if(type.equals("viewer-joined")&&m.optJSONObject("user")!=null)showArrival(m.optJSONObject("user").optString("name"));
    if(type.equals("live-gift-receipt")||type.equals("live-gift-error")){if(giftExperience!=null)giftExperience.receipt(m);if(type.equals("live-gift-error")){pendingComboGift="";activeComboGift="";localComboStreak=1;if(comboButton!=null)comboButton.setVisibility(View.GONE);liveToast(m.optString("message"));}else{String confirmedKind=m.optString("giftId",pendingComboGift);pendingComboGift="";if(giftExperience!=null&&!confirmedKind.isEmpty()&&giftExperience.isComboable(confirmedKind)&&comboButton!=null){int serverCombo=m.optInt("comboCount",0);if(serverCombo>0){activeComboGift=confirmedKind;localComboStreak=serverCombo;}else if(confirmedKind.equals(activeComboGift))localComboStreak++;else{activeComboGift=confirmedKind;localComboStreak=1;}if(openTray.isEmpty()){comboButton.removeCallbacks(clearComboButton);comboButton.setText("Combo x"+localComboStreak);comboButton.setVisibility(View.VISIBLE);final String comboKind=confirmedKind;comboButton.setOnClickListener(v->sendGift(comboKind,1,true));comboButton.postDelayed(clearComboButton,4500);}}}return;}
    if(type.equals("live-gift-ranking")||type.equals("live-gift-goal")){roomRanking=m;if(type.equals("live-gift-ranking")&&rankingRequested){rankingRequested=false;showGiftRanking(m);}return;}
    if(type.equals("live-reaction")&&currentRoom.equals(m.optString("room"))){if(m.optJSONObject("ranking")!=null)roomRanking=m.optJSONObject("ranking");showReactionEvent(m);}
    if (type.equals("chat")){if(chat!=null)addChat(m.optString("name"),m.optString("text"));if(gameService!=null)gameService.comment(m.optString("name"),m.optString("text"));}
    if (type.equals("room-ended") || type.equals("ended")) { if (host) { Toast.makeText(this, I18n.t("Buổi trực tiếp đã kết thúc."), Toast.LENGTH_LONG).show(); finish(); } else roomEnded(); }
    if (type.equals("error")) { if(host&&!joined){if(cameraSetup){liveToast(m.optString("message","Không bắt đầu được Live."));stopGameSession();finish();return;}stopGameSession();host=false;joining=false;previewing=false;showHostPreview();status.setText(m.optString("message",I18n.t("Chưa bắt đầu được Live. Hãy thử lại.")));return;}joining=false;if(liveStage instanceof VerticalMediaStage)((VerticalMediaStage)liveStage).prepare();else if(liveStage!=null){liveStage.setTranslationY(0);liveStage.setAlpha(1);}status.setText(m.optString("message")); status.setVisibility(View.VISIBLE); }
  }

  private TextView viewers,arrival,giftBanner,comboButton,topSender;
  private JSONObject roomRanking;private boolean rankingRequested;private int localComboStreak=1;private String activeComboGift="",pendingComboGift="";
  private LinearLayout audience;
  private FrameLayout reactionLayer;private LiveGiftExperience giftExperience;private long lastGift;
  private long lastReaction;private boolean fullFrame=true;
  private void renderAudience(JSONArray users){if(audience==null)return;audience.removeAllViews();boolean narrow=getResources().getDisplayMetrics().widthPixels<Math.round(400*getResources().getDisplayMetrics().density);int maxShown=narrow?2:3,avSize=dp(narrow?26:28);int shown=0;for(int n=0;users!=null&&n<users.length()&&shown<maxShown;n++){JSONObject u=users.optJSONObject(n);if(u==null)continue;shown++;String name=u.optString("name","K");FrameLayout avatar=new FrameLayout(this);avatar.setBackground(roundStroke(GLIVE_BTN,99,0x33ffffff));avatar.setClipToOutline(true);TextView initial=text(name.isEmpty()?"K":name.substring(0,1).toUpperCase(),11,0xffffffff);initial.setTypeface(null,Typeface.BOLD);initial.setGravity(Gravity.CENTER);avatar.addView(initial,new FrameLayout.LayoutParams(-1,-1));String url=u.optString("avatar");if(url.startsWith("/api/users/")){ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);avatar.addView(image,new FrameLayout.LayoutParams(-1,-1));MediaImageLoader.displayImage(this,NativeApi.shared,url,image,128,()->!isDestroyed());}avatar.setContentDescription(name);avatar.setOnClickListener(v->Toast.makeText(this,name,Toast.LENGTH_SHORT).show());LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(avSize,avSize);avatar.setLayoutParams(at);audience.addView(UiMetrics.wrapMinTouchTarget(this,avatar,48));}if(audience.getParent() instanceof View)((View)audience.getParent()).setVisibility(shown>0?View.VISIBLE:View.GONE);}
  private void showArrival(String name){if(arrival==null)return;arrival.removeCallbacks(clearArrival);arrival.setText("●  "+name+" "+I18n.t("vừa tham gia"));arrival.setVisibility(View.VISIBLE);arrival.setAlpha(0);arrival.animate().alpha(1).setDuration(180).start();arrival.postDelayed(clearArrival,3500);}
 private void updateTopSender(String name,long coins){if(topSender==null||name==null||name.isEmpty())return;topSender.removeCallbacks(hideTopSender);topSender.setText(name+" · "+coins+" "+I18n.t("xu"));topSender.setVisibility(View.VISIBLE);topSender.setAlpha(0);topSender.animate().alpha(1).setDuration(180).start();topSender.postDelayed(hideTopSender,8000);}
 private final Runnable hideTopSender=()->{if(topSender!=null)topSender.setVisibility(View.GONE);};
  private final Runnable clearArrival=()->{if(arrival!=null)arrival.setVisibility(View.GONE);};
  private final Runnable clearGiftBanner=()->{if(giftBanner!=null)giftBanner.setVisibility(View.GONE);};
  private final Runnable clearComboButton=()->{if(comboButton!=null)comboButton.setVisibility(View.GONE);localComboStreak=1;activeComboGift="";pendingComboGift="";};
  private void sendFreeHeart(){long now=System.currentTimeMillis();if(socket==null||!joined)return;if(now-lastReaction<350)return;lastReaction=now;socket.send(NativeSocket.json("type","live-reaction","kind","heart","free",true));}
  private void sendGift(String kind){sendGift(kind,giftExperience==null?1:giftExperience.quantity(),false);}
  private void sendGift(final String kind,final int qty,boolean fromCombo){long now=System.currentTimeMillis();if(socket==null||!joined)return;boolean isCombo=giftExperience!=null&&!giftExperience.comboId().isEmpty();if(now-lastGift<(isCombo?360:1200))return;if(giftExperience!=null){if(!giftExperience.canAfford(kind,qty)){liveToast("Chưa đủ xu tặng quà.");if(comboButton!=null)comboButton.setVisibility(View.GONE);localComboStreak=1;activeComboGift="";pendingComboGift="";return;}long price=giftExperience.effectivePrice(kind,qty);if(fromCombo&&price>=1000){String giftName=LiveGiftExperience.name(kind);String targetName=giftExperience.targetName();new Sheet(this).setTitle(I18n.t("Tặng quà đắt tiền?")).setMessage(I18n.t(giftName==null?kind:giftName)+" x"+qty+" · "+giftExperience.formatNumber(price)+" "+I18n.t("xu")+(targetName.isEmpty()?"":" · "+targetName)).setPositiveButton(I18n.t("Tặng"),(d,w)->dispatchGift(kind,qty)).setNegativeButton(I18n.t("Huỷ"),null).show();return;}}dispatchGift(kind,qty);}
  private void dispatchGift(String kind,int qty){if(socket==null||!joined)return;lastGift=System.currentTimeMillis();String cid=giftExperience==null?"":giftExperience.ensureComboId(kind),tid=giftExperience==null?"":giftExperience.targetId();pendingComboGift=(giftExperience!=null&&giftExperience.isComboable(kind))?kind:"";socket.send(NativeSocket.json("type","live-reaction","kind",kind,"giftId",kind,"isGift",true,"quantity",qty,"comboId",cid,"targetUserId",tid,"requestId",java.util.UUID.randomUUID().toString(),"priceVersion",giftExperience==null?0:giftExperience.version()));}
  private void sendReaction(String kind){if("heart".equals(kind))sendFreeHeart();else sendGift(kind);}
  private void gifts(){if(giftExperience!=null){localComboStreak=1;activeComboGift="";pendingComboGift="";giftExperience.open();}}

  private void showReactionEvent(JSONObject m){boolean isFree=m.optBoolean("free",false)||(!m.has("giftId")&&"heart".equals(m.optString("kind")));String kind=m.optString("giftId",m.optString("kind")),name=m.optString("name");int qty=Math.max(1,m.optInt("quantity",1)),combo=Math.max(1,m.optInt("comboCount",1));String recipient=m.optString("recipientName");if(!isFree&&LiveGiftExperience.name(kind)!=null&&giftBanner!=null&&openTray.isEmpty()){giftBanner.removeCallbacks(clearGiftBanner);String text="🎁 "+name+" "+I18n.t("đã gửi")+" "+(recipient.isEmpty()?"":recipient+": ")+I18n.t(LiveGiftExperience.name(kind))+(qty>1?" x"+qty:"")+(combo>1?" · Combo x"+combo:"");giftBanner.setText(text);giftBanner.setVisibility(View.VISIBLE);giftBanner.setAlpha(0);giftBanner.animate().alpha(1).setDuration(180).start();giftBanner.postDelayed(clearGiftBanner,3500);}JSONObject ranking=m.optJSONObject("ranking");if(ranking!=null){JSONArray top=ranking.optJSONArray("topSenders");if(top!=null&&top.length()>0){JSONObject leader=top.optJSONObject(0);if(leader!=null)updateTopSender(leader.optString("name"),leader.optLong("coins"));}}showReaction(kind,name,combo,isFree);}
  private void showReaction(String kind,String name,int combo,boolean isFree){if(!isFree&&LiveGiftExperience.name(kind)!=null){if(giftExperience!=null){if(reactionLayer!=null&&reactionLayer.isShown())giftExperience.show(reactionLayer,kind,name,combo,!livePlaybackMuted);else giftExperience.soundOnly(kind,!livePlaybackMuted);}String note=I18n.t("đã gửi")+" "+I18n.t(LiveGiftExperience.name(kind));if(chat!=null)addChat(name,note);if(gameService!=null)gameService.comment(name,note);return;}if(reactionLayer==null||reactionLayer.getChildCount()>20)return;String glyph=kind.equals("rose")?"🌹":kind.equals("star")?"⭐":kind.equals("crown")?"👑":"♥";TextView heart=text(glyph,kind.equals("heart")?30:42,0xffff4f91);heart.setGravity(Gravity.CENTER);FrameLayout layer=reactionLayer;FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(dp(64),dp(72),Gravity.RIGHT|Gravity.BOTTOM);at.rightMargin=dp(10+(int)(Math.random()*55));at.bottomMargin=dp(90);layer.addView(heart,at);heart.animate().translationY(-dp(210+(int)(Math.random()*120))).translationX(-dp((int)(Math.random()*70))).rotation((float)(Math.random()*35-17)).alpha(0).setDuration(2000).withEndAction(()->layer.removeView(heart)).start();if(!kind.equals("heart")&&chat!=null)addChat(name,I18n.t("đã gửi")+" "+glyph);}

  private ScrollView chatScroll;
  private boolean joining;
  private String currentRoom = "";
  private FrameLayout liveStage;
  private long swipeAt;

  private void autoJoin() {
    if (creationEntry || choosingMode || previewing || joined || joining || host || socket == null || !ready || lastRooms == null || lastRooms.length() == 0) return;
    if (getIntent().getBooleanExtra(EXTRA_HOST, false)) return;
    JSONObject first = viewingRooms().optJSONObject(0);
    if (first == null) return;
    joining = true;
    if (!sendLive("join", "multiGuest", true, "liveModes", true, "room", first.optString("id"))) joining = false;
  }

  private int roomIndex(String id) {
    for (int i = 0; lastRooms != null && i < lastRooms.length(); i++) if (lastRooms.optJSONObject(i)!=null && lastRooms.optJSONObject(i).optString("id").equals(id)) return i;
    return -1;
  }

  private int liveEnter;
  private boolean switchLive(final int direction) {
    if (host || liveRole.equals("guest") || previewing || socket==null || !ready || System.currentTimeMillis() - swipeAt < 400 || joining) return false;
    JSONArray available=viewingRooms();int index=-1;for(int i=0;i<available.length();i++){JSONObject item=available.optJSONObject(i);if(item!=null&&item.optString("id").equals(currentRoom)){index=i;break;}}
    final JSONObject next=available.optJSONObject(index+direction);
    if (index < 0 || next == null) { Toast.makeText(this, direction > 0 ? I18n.t("Bạn đã xem đến buổi live cuối.") : I18n.t("Đây là buổi live đầu tiên."), Toast.LENGTH_SHORT).show(); return false; }
    swipeAt = System.currentTimeMillis();
    joining = true;
    final View stage = liveStage;
    Runnable go = () -> {
      if(isFinishing()||isDestroyed()||socket==null||!ready){joining=false;if(stage instanceof VerticalMediaStage)((VerticalMediaStage)stage).prepare();return;}
      socket.send(NativeSocket.json("type", "leave"));
      if (rtc != null) { rtc.close(); rtc = null; }
      joined = false;
      if(!sendLive("join", "multiGuest", true, "liveModes", true, "room", next.optString("id"))){joining=false;if(stage instanceof VerticalMediaStage)((VerticalMediaStage)stage).prepare();}
    };
    liveEnter=direction;if(stage instanceof VerticalMediaStage)((VerticalMediaStage)stage).exit(direction,go);else go.run();return true;
  }

  private void roomEnded() {
    clearPendingGuest();pendingInvitation=null;
    if (rtc != null) { rtc.close(); rtc = null; }
    if (audio != null) {
      audio.setMode(previousMode);
      audio.setSpeakerphoneOn(previousSpeaker);
    }
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
    if(!creationEntry)autoJoin();
  }

  private void addChat(String name, String body) {
    TextView t = new KinnectText(this);
    android.text.SpannableStringBuilder sb = new android.text.SpannableStringBuilder(name + "  ");
    sb.setSpan(new android.text.style.StyleSpan(Typeface.BOLD), 0, name.length(), 0);
    sb.setSpan(new android.text.style.ForegroundColorSpan(GLIVE_BLUE), 0, name.length(), 0);
    sb.append(body);
    t.setText(sb);
    t.setTextColor(0xfff1f3f4);
    t.setTextSize(12);
    t.setLineSpacing(0, 1.3f);
    t.setPadding(dp(11), dp(6), dp(11), dp(6));
    t.setBackground(roundStroke(0xbf141418, 16, 0x16ffffff));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, -2);
    p.topMargin = dp(4);
    chat.addView(t, p);
    while (chat.getChildCount() > 40) chat.removeViewAt(0);
    chatScroll.post(() -> chatScroll.fullScroll(View.FOCUS_DOWN));
  }

  // Phòng live theo chuẩn Google Live (YouTube Live / Google Meet): video toàn màn, pill thông tin mờ, bảng lưới bo tròn.

  private JSONObject roomInfo=new JSONObject(),liveState,pendingInvitation;
  private JSONArray guestUsers=new JSONArray(),guestRequests=new JSONArray();
  private String liveRole="viewer",inviteMode="video",socketId="";private boolean liveGuestsSupported;
  private SurfaceViewRenderer localLive,pendingGuestLocal;private NativeRtc pendingGuestRtc;private boolean carryPreview;
  private LiveBoard liveBoard;
  private TextView guestAction;private LinearLayout liveSide;
  private boolean guestRequested,liveMic=true,liveCam=true,livePlaybackMuted;
  private Dialog guestSheet,invitationSheet;

  private FrameLayout liveAction(String glyph,String label,Runnable action){
    FrameLayout button=new FrameLayout(this);button.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));
    button.addView(icon(glyph,0xfff1f3f4),new FrameLayout.LayoutParams(dp(18),dp(18),Gravity.CENTER));
    button.setContentDescription(I18n.t(label));button.setOnClickListener(v->action.run());return button;
  }
  private void liveToast(String value){Toast.makeText(this,I18n.t(value),Toast.LENGTH_SHORT).show();}
  private boolean sendLive(String type,Object... values){if(socket==null||!ready)return false;JSONObject message=NativeSocket.json("type",type);try{for(int i=0;i<values.length;i+=2)message.put(values[i].toString(),values[i+1]);}catch(JSONException ignored){}socket.send(message);return true;}
  private void confirmLeave(){if(host)new Sheet(this).setTitle(I18n.t("Kết thúc Live?")).setMessage(I18n.t("Buổi phát trực tiếp sẽ dừng ngay với tất cả người xem.")).setPositiveButton(I18n.t("Kết thúc"),(d,w)->{if(joined)sendLive("leave");finish();}).setNegativeButton(I18n.t("Ở lại"),null).show();else{if(joined)sendLive("leave");finish();}}
  private void showRoom(JSONObject m){
    String nextMode=m.optJSONObject("room")==null?"chat":m.optJSONObject("room").optString("liveMode","chat");liveMode=nextMode.equals("game")?"game":"chat";
    rebindCarriedLocal=carryPreview&&host&&!liveMode.equals("game");
    if(!carryPreview||!host){if(rtc!=null){rtc.close();rtc=null;}localLive=null;}carryPreview=false;liveState=null;liveTray=null;openTray="";guestRequested=false;guestUsers=new JSONArray();guestRequests=new JSONArray();
    liveGuestsSupported=m.optBoolean("multiGuest");roomInfo=m.optJSONObject("room")==null?new JSONObject():m.optJSONObject("room");roomComments=roomInfo.optBoolean("comments",true);screenCover=null;currentRoom=roomInfo.optString("id");liveRole=host?"host":"viewer";
    root.removeAllViews();root.setBackgroundColor(GLIVE_BG);applyDarkSystemBars();
    FrameLayout stage=host?new FrameLayout(this):new ViewerStage();liveStage=stage;root.addView(stage,new LinearLayout.LayoutParams(-1,0,1));if(liveEnter!=0){VerticalMediaStage.enter(stage,liveEnter);liveEnter=0;}
    liveBoard=new LiveBoard();stage.addView(liveBoard,new FrameLayout.LayoutParams(-1,-1));stage.addView(new StoreLiveDecoration(this,roomInfo.optString("liveDecoration")),new FrameLayout.LayoutParams(-1,-1));
    View shade=new View(this);shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x99060608,0x00000000,0x00000000,0xd608080b}));stage.addView(shade,new FrameLayout.LayoutParams(-1,-1));
    reactionLayer=new FrameLayout(this);stage.addView(reactionLayer,new FrameLayout.LayoutParams(-1,-1));
    LinearLayout heading=row();heading.setGravity(Gravity.CENTER_VERTICAL);
    LinearLayout identity=row();identity.setPadding(dp(4),dp(4),dp(12),dp(4));identity.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));
    FrameLayout face=liveAvatar(roomInfo.optString("host",I18n.t("Bạn")),roomInfo.optString("avatar"),30);identity.addView(face,new LinearLayout.LayoutParams(dp(30),dp(30)));
    LinearLayout copy=column();copy.setPadding(dp(8),0,0,0);TextView name=text(roomInfo.optString("host",I18n.t("Bạn")),12,0xffffffff);name.setSingleLine(true);name.setEllipsize(android.text.TextUtils.TruncateAt.END);name.setTypeface(null,Typeface.BOLD);copy.addView(name,new LinearLayout.LayoutParams(-2,-2));
    TextView tag=text("● LIVE · "+I18n.t(modeName(liveMode))+(roomInfo.optString("hostMembership").isEmpty()?"":roomInfo.optString("hostMembership").equals("member_creator")?" · Creator":" · Plus"),8,0xffffffff);tag.setSingleLine(true);tag.setEllipsize(android.text.TextUtils.TruncateAt.END);tag.setTypeface(null,Typeface.BOLD);tag.setPadding(dp(6),dp(1),dp(6),dp(1));tag.setBackground(round(GLIVE_RED,6));copy.addView(tag,new LinearLayout.LayoutParams(-2,-2));identity.addView(copy,new LinearLayout.LayoutParams(-2,-2));
    FrameLayout hostWrap=new FrameLayout(this);hostWrap.addView(identity,new FrameLayout.LayoutParams(-2,-2,Gravity.START|Gravity.CENTER_VERTICAL));heading.addView(hostWrap,new LinearLayout.LayoutParams(0,-2,1));
    HorizontalScrollView avs=new HorizontalScrollView(this);avs.setHorizontalScrollBarEnabled(false);avs.setVisibility(View.GONE);audience=row();avs.addView(audience);LinearLayout.LayoutParams avp=new LinearLayout.LayoutParams(-2,UiMetrics.dpRaw(this,48));avp.leftMargin=dp(4);heading.addView(avs,avp);
    LinearLayout count=row();count.setGravity(Gravity.CENTER);count.setPadding(dp(9),0,dp(9),0);count.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));count.addView(icon("eye",0xfff1f3f4),new LinearLayout.LayoutParams(dp(13),dp(13)));viewers=text(String.valueOf(roomInfo.optInt("viewers")),11,0xfff1f3f4);viewers.setTypeface(null,Typeface.BOLD);viewers.setSingleLine(true);viewers.setIncludeFontPadding(false);viewers.setPadding(dp(4),0,dp(1),0);count.addView(viewers);count.setContentDescription(I18n.t("Người đang xem"));count.setOnClickListener(v->sendLive("viewers"));LinearLayout.LayoutParams countLp=new LinearLayout.LayoutParams(-2,dp(34));countLp.leftMargin=dp(2);countLp.rightMargin=dp(2);count.setLayoutParams(countLp);heading.addView(UiMetrics.wrapMinTouchTarget(this,count,48));
    FrameLayout closeRoomBtn=liveAction("x",host?"Kết thúc Live":"Rời Live",this::confirmLeave);closeRoomBtn.setLayoutParams(new LinearLayout.LayoutParams(dp(34),dp(34)));heading.addView(UiMetrics.wrapMinTouchTarget(this,closeRoomBtn,48));
    FrameLayout.LayoutParams hp=new FrameLayout.LayoutParams(-1,UiMetrics.dpRaw(this,52),Gravity.TOP);hp.setMargins(dp(12),dp(10),dp(12),0);stage.addView(heading,hp);
    if(!roomInfo.optString("title").isEmpty()){TextView title=text(roomInfo.optString("title"),12,0xffffffff);title.setTypeface(null,Typeface.BOLD);title.setMaxLines(1);title.setEllipsize(android.text.TextUtils.TruncateAt.END);FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);at.setMargins(dp(16),UiMetrics.dpRaw(this,68),dp(16),0);stage.addView(title,at);}topSender=text("",11,0xffffffff);topSender.setTypeface(null,Typeface.BOLD);topSender.setPadding(dp(10),dp(5),dp(12),dp(5));topSender.setBackground(roundStroke(0xe678350f,99,0x66fde68a));android.graphics.drawable.Drawable crownGlyph=WebIcons.load(this,"crown");crownGlyph.setTint(0xffffe08a);crownGlyph.setBounds(0,0,dp(14),dp(14));topSender.setCompoundDrawablesRelative(crownGlyph,null,null,null);topSender.setCompoundDrawablePadding(dp(5));topSender.setVisibility(View.GONE);FrameLayout.LayoutParams tsAt=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.START);tsAt.setMargins(dp(12),UiMetrics.dpRaw(this,liveMode.equals("game")?156:114),dp(12),0);stage.addView(topSender,tsAt);
    status=text(I18n.t("Đang kết nối…"),11,0xffe8eaed);status.setGravity(Gravity.CENTER);status.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));status.setPadding(dp(14),dp(8),dp(14),dp(8));FrameLayout.LayoutParams st=new FrameLayout.LayoutParams(-2,-2,host&&liveMode.equals("game")?Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL:Gravity.CENTER);if(host&&liveMode.equals("game"))st.bottomMargin=UiMetrics.dpRaw(this,80);stage.addView(status,st);hideStatus=()->status.setVisibility(View.GONE);
    arrival=text("",11,0xffffffff);arrival.setTypeface(null,Typeface.BOLD);arrival.setPadding(dp(12),dp(6),dp(12),dp(6));arrival.setBackground(roundStroke(GLIVE_PILL,99,0x28ffffff));arrival.setMaxLines(1);arrival.setEllipsize(android.text.TextUtils.TruncateAt.END);arrival.setVisibility(View.GONE);FrameLayout.LayoutParams arrivalAt=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.START);arrivalAt.setMargins(dp(12),0,dp(70),UiMetrics.dpRaw(this,200));stage.addView(arrival,arrivalAt);
    giftBanner=text("",11,0xfffde68a);giftBanner.setTypeface(null,Typeface.BOLD);giftBanner.setPadding(dp(12),dp(6),dp(12),dp(6));giftBanner.setBackground(roundStroke(0xd82e1065,99,0x66f59e0b));giftBanner.setMaxLines(1);giftBanner.setEllipsize(android.text.TextUtils.TruncateAt.END);giftBanner.setVisibility(View.GONE);FrameLayout.LayoutParams giftAt=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.START);giftAt.setMargins(dp(12),0,dp(70),UiMetrics.dpRaw(this,232));stage.addView(giftBanner,giftAt);
    comboButton=text("Combo",12,0xffffffff);android.graphics.drawable.Drawable comboGlyph=WebIcons.load(this,"sparkles");comboGlyph.setTint(0xffffffff);comboGlyph.setBounds(0,0,dp(14),dp(14));comboButton.setCompoundDrawablesRelative(comboGlyph,null,null,null);comboButton.setCompoundDrawablePadding(dp(6));comboButton.setTypeface(null,Typeface.BOLD);comboButton.setGravity(Gravity.CENTER);comboButton.setPadding(dp(14),dp(8),dp(14),dp(8));comboButton.setBackground(roundStroke(0xe67c3aed,99,0x88fde68a));comboButton.setVisibility(View.GONE);FrameLayout.LayoutParams comboAt=new FrameLayout.LayoutParams(-2,UiMetrics.dpRaw(this,48),Gravity.BOTTOM|Gravity.END);comboAt.setMargins(0,0,dp(12),UiMetrics.dpRaw(this,208));stage.addView(comboButton,comboAt);UiMetrics.enforceMinTouchTarget(comboButton,48);
    chatScroll=new ScrollView(this);chatScroll.setVerticalScrollBarEnabled(false);chatScroll.setVerticalFadingEdgeEnabled(true);chatScroll.setFadingEdgeLength(dp(18));chat=column();chatScroll.addView(chat);FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-1,dp(120),Gravity.BOTTOM);cp.setMargins(dp(12),0,UiMetrics.dpRaw(this,68),UiMetrics.dpRaw(this,82));stage.addView(chatScroll,cp);
    JSONArray history=m.optJSONArray("history");for(int i=0;history!=null&&i<history.length();i++){JSONObject item=history.optJSONObject(i);if(item!=null)addChat(item.optString("name"),item.optString("text"));}
    LinearLayout side=column();liveSide=side;side.setGravity(Gravity.CENTER_HORIZONTAL);
    FrameLayout topSideBtn=(host&&!liveMode.equals("game"))?liveAction("switch_camera","Đổi camera",()->{if(rtc!=null)rtc.flip();}):liveAction("heart","Thả tim",this::sendFreeHeart);
    topSideBtn.setLayoutParams(new LinearLayout.LayoutParams(dp(44),dp(44)));side.addView(UiMetrics.wrapMinTouchTarget(this,topSideBtn,48));
    FrameLayout shareSideBtn=liveAction("share_2","Chia sẻ",this::shareLive);LinearLayout.LayoutParams gap=new LinearLayout.LayoutParams(dp(44),dp(44));gap.topMargin=dp(4);shareSideBtn.setLayoutParams(gap);side.addView(UiMetrics.wrapMinTouchTarget(this,shareSideBtn,48));
    FrameLayout.LayoutParams sp=new FrameLayout.LayoutParams(UiMetrics.dpRaw(this,48),-2,Gravity.BOTTOM|Gravity.END);sp.setMargins(0,0,dp(12),UiMetrics.dpRaw(this,88));stage.addView(side,sp);
    LinearLayout dock=row();dock.setGravity(Gravity.CENTER_VERTICAL);final EditText input=new KinnectInput(this);input.setHint(I18n.t("Bình luận…"));input.setTextSize(13);input.setGravity(Gravity.CENTER_VERTICAL);input.setTextColor(0xffffffff);input.setHintTextColor(0xffb8b3c6);input.setSingleLine(true);input.setPadding(dp(14),0,dp(12),0);input.setBackground(roundStroke(GLIVE_PILL,99,0x26ffffff));input.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEND);boolean chatDisabled=!host&&!roomComments;if(chatDisabled){input.setEnabled(false);input.setHint(I18n.t("Bình luận đã tắt"));input.setAlpha(1f);input.setHintTextColor(0xffb8b3c6);input.setBackground(roundStroke(GLIVE_BTN,99,0x33ffffff));}
    final Runnable sendChat=()->{if(!input.isEnabled())return;String value=input.getText().toString().trim();if(!value.isEmpty()){if(joined&&sendLive("chat","text",value))input.setText("");else liveToast("Chưa kết nối tới phòng Live, vui lòng thử lại.");}};
    dock.addView(input,new LinearLayout.LayoutParams(0,UiMetrics.dpRaw(this,48),1));UiMetrics.enforceMinTouchTarget(input,48);input.setOnEditorActionListener((v,a,e)->{if(e==null||e.getAction()==android.view.KeyEvent.ACTION_UP)sendChat.run();return true;});
    final FrameLayout sendBtn=liveAction("send_horizontal","Gửi",sendChat);if(chatDisabled){sendBtn.setEnabled(false);sendBtn.setAlpha(1f);sendBtn.setBackground(roundStroke(GLIVE_BTN,99,0x22ffffff));if(sendBtn.getChildCount()>0&&sendBtn.getChildAt(0) instanceof ImageView){((ImageView)sendBtn.getChildAt(0)).setColorFilter(0xffb8b3c6);}}else{input.addTextChangedListener(new android.text.TextWatcher(){public void beforeTextChanged(CharSequence s,int st,int c,int a){}public void onTextChanged(CharSequence s,int st,int b,int c){}public void afterTextChanged(android.text.Editable s){boolean has=s!=null&&s.toString().trim().length()>0;sendBtn.setBackground(has?round(WebDesign.PURPLE_HERO[0],99):roundStroke(GLIVE_PILL,99,0x22ffffff));}});}
    sendBtn.setLayoutParams(new LinearLayout.LayoutParams(dp(38),dp(38)));dock.addView(UiMetrics.wrapMinTouchTarget(this,sendBtn,48));
    FrameLayout guests=liveAction("users_round",host?"Khách mời":"Lên Live",this::openGuests);guestAction=text("",8,0xffffffff);guestAction.setTypeface(null,Typeface.BOLD);guestAction.setGravity(Gravity.CENTER);guestAction.setBackground(round(GLIVE_RED,99));guestAction.setVisibility(View.GONE);FrameLayout.LayoutParams badgeAt=new FrameLayout.LayoutParams(dp(15),dp(15),Gravity.TOP|Gravity.END);guests.addView(guestAction,badgeAt);
    FrameLayout thirdAction;
    if(host&&!liveMode.equals("game")){thirdAction=liveAction("sparkles","Hiệu ứng",this::effectsMenu);}else{thirdAction=liveAction("gift","Tặng quà",this::gifts);if(!host){GradientDrawable giftBg=new GradientDrawable(GradientDrawable.Orientation.TL_BR,WebDesign.WALLET_HERO_GRADIENT);giftBg.setCornerRadius(dp(99));thirdAction.setBackground(giftBg);}}
    for(FrameLayout action:new FrameLayout[]{guests,thirdAction,liveAction("sliders_horizontal","Công cụ",this::liveTools)}){action.setLayoutParams(new LinearLayout.LayoutParams(dp(38),dp(38)));dock.addView(UiMetrics.wrapMinTouchTarget(this,action,48));}
    dock.setPadding(dp(6),dp(5),dp(6),dp(5));dock.setBackground(roundStroke(0xcc141418,999,0x26ffffff));FrameLayout.LayoutParams dockLp=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);dockLp.setMargins(dp(10),0,dp(10),dp(10));stage.addView(dock,dockLp);
    if(liveMode.equals("game")){mountGame(stage);}
    if(audio!=null){audio.setMode(android.media.AudioManager.MODE_IN_COMMUNICATION);audio.setSpeakerphoneOn(true);}
    if(!liveGuestsSupported&&config!=null){String publisher=host?socketId:m.optString("host","legacy-host");JSONObject person=NativeSocket.json("id",publisher,"name",roomInfo.optString("host"),"userId",roomInfo.optString("hostId"),"role","host","mode","video");applyLiveStage(NativeSocket.json("room",currentRoom,"selfId",socketId,"role",host?"host":"viewer","revision",0,"layout","panel","participants",new JSONArray().put(person),"peers",new JSONArray()));}
  }
  private FrameLayout liveAvatar(String name,String path,int size){FrameLayout frame=new FrameLayout(this);frame.setBackground(roundStroke(GLIVE_BTN,99,0x33ffffff));frame.setClipToOutline(true);TextView initial=text(name.isEmpty()?"K":name.substring(0,1).toUpperCase(),Math.max(10,size/3),0xffffffff);initial.setTypeface(null,Typeface.BOLD);initial.setGravity(Gravity.CENTER);frame.addView(initial,new FrameLayout.LayoutParams(-1,-1));if(path.startsWith("/api/users/")){ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);frame.addView(image,new FrameLayout.LayoutParams(-1,-1));MediaImageLoader.displayImage(this,NativeApi.shared,path,image,Math.max(128,dp(size)*2),()->!isDestroyed());}return frame;}
  private final class LiveBoard extends ViewGroup {
    String layout="panel";LiveBoard(){super(LiveActivity.this);setBackgroundColor(GLIVE_BG);}
    protected void onMeasure(int w,int h){int width=MeasureSpec.getSize(w),height=MeasureSpec.getSize(h);setMeasuredDimension(width,height);for(int i=0;i<getChildCount();i++){android.graphics.Rect r=tile(i,width,height);getChildAt(i).measure(MeasureSpec.makeMeasureSpec(r.width(),MeasureSpec.EXACTLY),MeasureSpec.makeMeasureSpec(r.height(),MeasureSpec.EXACTLY));}}
    private android.graphics.Rect tile(int i,int w,int h){int n=getChildCount();if(n<=1)return new android.graphics.Rect(0,0,w,h);int top=dp(92),bottom=Math.max(top+dp(120),h-dp(226)),gap=dp(6),left=dp(8),width=w-dp(16);if(layout.equals("panel")){int main=width*62/100;if(i==0)return new android.graphics.Rect(left,top,left+main-gap,bottom);int slot=(bottom-top)/(n-1),y=top+(i-1)*slot;return new android.graphics.Rect(left+main, y,w-left, i==n-1?bottom:y+slot-gap);}int columns=2,rows=(n+1)/2,cw=(width-gap)/columns,ch=(bottom-top-gap*(rows-1))/rows,x=left+(i%2)*(cw+gap),y=top+(i/2)*(ch+gap);return new android.graphics.Rect(x,y,x+cw,y+ch);}
    protected void onLayout(boolean c,int l,int t,int r,int b){for(int i=0;i<getChildCount();i++){android.graphics.Rect at=tile(i,r-l,b-t);getChildAt(i).layout(at.left,at.top,at.right,at.bottom);}}
  }
  private void applyLiveStage(JSONObject state){
    if(!currentRoom.equals(state.optString("room"))||liveBoard==null)return;
    if(liveState!=null&&state.optInt("revision")==liveState.optInt("revision")){liveState=state;guestRequested=state.optBoolean("requested");liveBoard.layout=state.optString("layout","panel");liveBoard.requestLayout();return;}
    String role=state.optString("role","viewer");boolean publishing=!role.equals("viewer"),changed=!role.equals(liveRole);liveRole=role;host=role.equals("host");liveState=state;guestRequested=state.optBoolean("requested");
    if(rtc!=null&&(changed||!publishing&&localLive!=null)){rtc.close();rtc=null;localLive=null;}else if(rtc!=null)rtc.resetLivePeers();
    if(publishing&&pendingGuestRtc!=null){rtc=pendingGuestRtc;localLive=pendingGuestLocal;pendingGuestRtc=null;pendingGuestLocal=null;rebindCarriedLocal=false;liveMic=true;liveCam=!state.optString("mode").equals("audio");}
    if(rebindCarriedLocal){rebindCarriedLocal=false;if(rtc!=null&&!liveMode.equals("game")){SurfaceViewRenderer rebound=rtc.attachLocal(this);if(rebound!=null)localLive=rebound;}}
    liveBoard.removeAllViews();liveBoard.layout=state.optString("layout","panel");if(rtc==null){localLive=publishing?new SurfaceViewRenderer(this):null;rtc=new NativeRtc(this,config,localLive,null,new NativeRtc.Events(){public void status(String value){status.setText(value);status.setVisibility(View.VISIBLE);status.removeCallbacks(hideStatus);status.postDelayed(hideStatus,2500);}public void signal(String peer,JSONObject value){try{value.put("type","signal");value.put("to",peer);if(liveState!=null)value.put("revision",liveState.optInt("revision"));socket.send(value);}catch(JSONException ignored){}}public void cameraFacing(boolean isFront){liveFront=isFront;}},false);if(publishing)try{rtc.media(this,!state.optString("mode").equals("audio"),liveFront);rtc.microphone(host?pendingHostMic:true);liveMic=host?pendingHostMic:true;liveCam=true;if(previewLook!=null&&rtc.effects()!=null){LiveEffects fx=rtc.effects();fx.filter=previewLook.filter;fx.sticker=previewLook.sticker;fx.beautyOn=previewLook.beautyOn;fx.smooth=previewLook.smooth;fx.blemish=previewLook.blemish;fx.eyes=previewLook.eyes;fx.lips=previewLook.lips;previewLook=null;}}catch(Exception error){liveToast("Không mở được camera/micro.");if(host){if(joined)sendLive("leave");finish();}else sendLive("live-guest-leave");return;}}
    rtc.setCameraCallbacks(null,null);
    rtc.events(new NativeRtc.Events(){public void status(String value){status.setText(value);status.setVisibility(View.VISIBLE);status.removeCallbacks(hideStatus);status.postDelayed(hideStatus,2500);}public void signal(String peer,JSONObject value){try{value.put("type","signal");value.put("to",peer);if(liveState!=null)value.put("revision",liveState.optInt("revision"));socket.send(value);}catch(JSONException ignored){}}public void cameraFacing(boolean isFront){liveFront=isFront;}});
    JSONArray people=state.optJSONArray("participants");if(giftExperience!=null)giftExperience.setTargets(people,roomInfo.optString("hostId"),roomInfo.optString("host"));for(int i=0;people!=null&&i<people.length();i++){JSONObject person=people.optJSONObject(i);if(person==null)continue;FrameLayout tile=new FrameLayout(this);tile.setBackground(roundStroke(GLIVE_SURFACE,18,0x22ffffff));tile.setClipToOutline(true);String id=person.optString("id");boolean self=id.equals(state.optString("selfId"));boolean video=!person.optString("mode").equals("audio");if(video){if(self&&(localLive==null||localLive.getParent()!=null)&&rtc!=null&&!liveMode.equals("game")){SurfaceViewRenderer rebound=rtc.attachLocal(this);if(rebound!=null)localLive=rebound;}SurfaceViewRenderer display=self?localLive:new SurfaceViewRenderer(this);if(display!=null){if(display.getParent()instanceof ViewGroup)((ViewGroup)display.getParent()).removeView(display);tile.addView(display,new FrameLayout.LayoutParams(-1,-1));if(!self)rtc.bindLive(id,display,!liveMode.equals("game"));}}else{FrameLayout avatar=liveAvatar(person.optString("name"),person.optString("avatar"),56);tile.addView(avatar,new FrameLayout.LayoutParams(dp(56),dp(56),Gravity.CENTER));}
      if(people.length()>1){TextView label=text(person.optString("name")+(self?" · "+I18n.t("Bạn"):""),10,0xffffffff);label.setTypeface(null,Typeface.BOLD);label.setSingleLine(true);label.setEllipsize(android.text.TextUtils.TruncateAt.END);label.setPadding(dp(8),dp(4),dp(8),dp(4));label.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.START);lp.setMargins(dp(8),0,dp(8),dp(8));tile.addView(label,lp);}liveBoard.addView(tile);}
    rtc.playback(!livePlaybackMuted);liveBoard.requestLayout();JSONArray peers=state.optJSONArray("peers");for(int i=0;peers!=null&&i<peers.length();i++){JSONObject peer=peers.optJSONObject(i);if(peer!=null&&peer.optBoolean("offer"))rtc.offer(peer.optString("id"));}status.setVisibility(View.GONE);
  }
  private void shareLive(){try{externalPicker=true;startActivity(android.content.Intent.createChooser(new android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT,ServerConfig.DEFAULT_ORIGIN+"/share/live/"+currentRoom),I18n.t("Chia sẻ buổi live")));}catch(Exception ignored){externalPicker=false;}}
  private HorizontalScrollView liveTray;private String openTray="";
  private void liveTools(){toggleLiveTray("tools");}
  private void requestGiftRanking(){rankingRequested=true;if(socket!=null&&joined)sendLive("live-gift-ranking");else showGiftRanking(roomRanking!=null?roomRanking:new JSONObject());}
  private void showGiftRanking(JSONObject data){if(data==null)data=new JSONObject();CommerceUi ui=new CommerceUi(this);LinearLayout body=ui.col();body.setPadding(ui.dp(4),0,ui.dp(4),ui.dp(8));JSONObject goal=data.optJSONObject("goal");if(goal!=null){LinearLayout gbox=ui.section();gbox.addView(ui.text(goal.optString("title",I18n.t("Mục tiêu quà Live")),15,ui.ink,true));ui.add(gbox,ui.text(goal.optLong("progressCoins")+" / "+goal.optLong("targetCoins")+" "+I18n.t("xu"),13,ui.purpleText,true),4);ui.add(body,gbox,8);}if(host){ui.add(body,ui.action(goal!=null?"Đổi mục tiêu quà":"Đặt mục tiêu quà","crown",()->{EditText t=field(I18n.t("Số xu mục tiêu (50 - 100000)"));t.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);new Sheet(this).setTitle(I18n.t("Mục tiêu quà Live")).setView(t).setPositiveButton(I18n.t("Lưu"),(d,w)->{long target=0;try{target=Long.parseLong(t.getText().toString().trim());}catch(Exception ignored){}sendLive("live-gift-goal","title",I18n.t("Mục tiêu quà Live"),"targetCoins",target);}).setNeutralButton(I18n.t("Xóa"),(d,w)->sendLive("live-gift-goal","targetCoins",0)).setNegativeButton(I18n.t("Hủy"),null).show();}),8);}ui.add(body,ui.text(I18n.t("Tổng quà trong phòng")+": "+data.optLong("totalGifts")+" · "+data.optLong("totalCoins")+" "+I18n.t("xu"),13,ui.mutedStrict,false),10);JSONArray top=data.optJSONArray("topSenders");if(top==null||top.length()==0)ui.add(body,ui.empty("gift","Chưa có quà trong phòng"),12);else for(int i=0;i<top.length();i++){JSONObject s=top.optJSONObject(i);if(s==null)continue;LinearLayout row=ui.row();row.setPadding(0,ui.dp(8),0,ui.dp(8));row.addView(ui.badge("#"+(i+1)));TextView n=ui.text(s.optString("name"),14,ui.ink,true);n.setPadding(ui.dp(10),0,ui.dp(8),0);row.addView(n,new LinearLayout.LayoutParams(0,-2,1));row.addView(ui.text(s.optLong("coins")+" "+I18n.t("xu"),13,ui.purpleText,true));body.addView(row);}ScrollView sc=new ScrollView(this);sc.addView(body);new Sheet(this).setTitle(I18n.t("Bảng quà Live")).setView(sc).setNegativeButton(I18n.t("Đóng"),null).show();}
  private void toggleLiveTray(String value){if(liveStage==null)return;if(liveTray!=null){liveStage.removeView(liveTray);liveTray=null;}if(openTray.equals(value)){openTray="";if(chatScroll!=null)chatScroll.setVisibility(View.VISIBLE);if(liveSide!=null)liveSide.setVisibility(View.VISIBLE);return;}openTray=value;if(chatScroll!=null)chatScroll.setVisibility(View.INVISIBLE);if(liveSide!=null)liveSide.setVisibility(View.INVISIBLE);if(arrival!=null)arrival.setVisibility(View.GONE);if(comboButton!=null)comboButton.setVisibility(View.GONE);if(giftBanner!=null)giftBanner.setVisibility(View.GONE);android.view.inputmethod.InputMethodManager keyboard=(android.view.inputmethod.InputMethodManager)getSystemService(INPUT_METHOD_SERVICE);if(keyboard!=null)keyboard.hideSoftInputFromWindow(root.getWindowToken(),0);liveTray=new HorizontalScrollView(this);liveTray.setHorizontalScrollBarEnabled(false);liveTray.setHorizontalFadingEdgeEnabled(true);liveTray.setFadingEdgeLength(dp(24));liveTray.setBackground(roundStroke(0xf018181d,20,0x26ffffff));LinearLayout items=row();items.setPadding(dp(8),dp(8),dp(12),dp(6));liveTray.addView(items);
    {if(host&&liveMode.equals("game")){trayTool(items,"gamepad","Tạm che",this::toggleScreenPause);trayTool(items,"monitor","Mở game",this::openGameApp);}if(!liveRole.equals("viewer")){String micGlyph=liveMic?"mic":(WebIcons.resolve(this,"mic_off")!=0?"mic_off":"mic");trayTool(items,micGlyph,liveMic?"Tắt mic":"Bật mic",liveMic?GLIVE_BTN:GLIVE_RED,()->{if(rtc==null)return;liveMic=!liveMic;rtc.microphone(liveMic);refreshTools();});if(!liveMode.equals("game")&&(host||liveState==null||!liveState.optString("mode").equals("audio"))){trayTool(items,liveCam?"camera":"camera_off",liveCam?"Tắt cam":"Bật cam",liveCam?GLIVE_BTN:GLIVE_RED,()->{if(rtc==null)return;liveCam=!liveCam;rtc.camera(liveCam);refreshTools();});trayTool(items,"switch_camera","Đổi cam",()->{if(rtc!=null)rtc.flip();});trayTool(items,"sparkles","Hiệu ứng",this::effectsMenu);}}if(host){trayTool(items,"grid","Lưới",()->sendLive("live-layout","layout","grid"));trayTool(items,"users_round","Chủ lớn",()->sendLive("live-layout","layout","panel"));}else{trayTool(items,"radio","Phát live",()->{if(joined)sendLive("leave");if(rtc!=null){rtc.close();rtc=null;}joined=false;chooseMode();});trayTool(items,"flag","Báo cáo",this::reportLive);trayTool(items,"shield_check","Chặn",this::blockLive);trayTool(items,"user_plus",roomInfo.optBoolean("following")?"Bỏ theo dõi":"Theo dõi",this::followLive);trayTool(items,"volume_2",livePlaybackMuted?"Bật tiếng":"Tắt tiếng",()->{livePlaybackMuted=!livePlaybackMuted;if(rtc!=null)rtc.playback(!livePlaybackMuted);refreshTools();});}trayTool(items,"crown","Bảng quà",this::requestGiftRanking);trayTool(items,"share_2","Chia sẻ",this::shareLive);}
    FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);at.setMargins(dp(12),0,dp(12),UiMetrics.dpRaw(this,78));liveStage.addView(liveTray,at);liveTray.setAlpha(0);liveTray.setTranslationY(dp(12));liveTray.animate().alpha(1).translationY(0).setDuration(180).start();
  }
  private void refreshTools(){openTray="";toggleLiveTray("tools");}
  private void trayTool(LinearLayout row,String glyph,String name,Runnable action){trayTool(row,glyph,name,GLIVE_BTN,action);}
  private void trayTool(LinearLayout row,String glyph,String name,int bgColor,Runnable action){LinearLayout tile=column();tile.setGravity(Gravity.TOP|Gravity.CENTER_HORIZONTAL);tile.setPadding(0,dp(4),0,dp(4));FrameLayout circle=new FrameLayout(this);circle.setBackground(round(bgColor,99));circle.addView(icon(glyph,0xfff1f3f4),new FrameLayout.LayoutParams(dp(18),dp(18),Gravity.CENTER));tile.addView(circle,new LinearLayout.LayoutParams(dp(36),dp(36)));TextView label=text(I18n.t(name),10,0xffe8eaed);label.setGravity(Gravity.CENTER);label.setSingleLine(true);label.setEllipsize(android.text.TextUtils.TruncateAt.END);label.setPadding(dp(2),dp(5),dp(2),0);tile.addView(label,new LinearLayout.LayoutParams(-1,-2));tile.setContentDescription(I18n.t(name));tile.setOnClickListener(v->action.run());row.addView(tile,new LinearLayout.LayoutParams(Math.max(UiMetrics.dpRaw(this,48),dp(66)),-2));UiMetrics.enforceMinTouchTarget(tile,48);}
  private void blockLive(){new Sheet(this).setTitle(I18n.t("Chặn người phát?")).setPositiveButton(I18n.t("Chặn"),(d,w)->NativeApi.shared.call("POST","/api/users/"+roomInfo.optString("hostId")+"/block",new JSONObject(),(data,error,code)->{if(error==null)finish();else liveToast(error);})).setNegativeButton(I18n.t("Hủy"),null).show();}
  private void followLive(){boolean following=roomInfo.optBoolean("following");NativeApi.shared.call(following?"DELETE":"POST","/api/users/"+roomInfo.optString("hostId")+"/follow",new JSONObject(),(data,error,code)->{if(isDestroyed())return;if(error!=null){liveToast(error);return;}try{roomInfo.put("following",!following);}catch(JSONException ignored){}refreshTools();});}
  private void reportLive(){EditText reason=field(I18n.t("Mô tả vi phạm; không gửi lại hình ảnh nhạy cảm"));new Sheet(this).setTitle(I18n.t("Báo cáo buổi live")).setView(reason).setPositiveButton(I18n.t("Gửi báo cáo"),(d,w)->{String value=reason.getText().toString().trim();if(value.length()<5){liveToast("Mô tả ít nhất 5 ký tự.");return;}NativeApi.shared.call("POST","/api/reports",NativeSocket.json("targetType","user","targetId",roomInfo.optString("hostId"),"reason","[Live "+currentRoom+"] "+value),(data,error,code)->liveToast(error==null?"Đã gửi báo cáo.":error));}).setNegativeButton(I18n.t("Hủy"),null).show();}
  private void openGuests(){if(!liveGuestsSupported){liveToast("Cần cập nhật máy chủ để dùng khách mời.");return;}if(host){sendLive("live-guest-list");return;}if(liveRole.equals("guest")){new Sheet(this).setTitle(I18n.t("Bạn đang lên Live")).setItemIcons(new String[]{"log_out"}).setItems(new String[]{I18n.t("Rời ghế khách")},(d,n)->sendLive("live-guest-leave")).show();return;}if(guestRequested){new Sheet(this).setTitle(I18n.t("Đang chờ chủ phòng duyệt")).setPositiveButton(I18n.t("Hủy yêu cầu"),(d,w)->sendLive("live-guest-cancel")).setNegativeButton(I18n.t("Đóng"),null).show();return;}new Sheet(this).setTitle(I18n.t("Xin lên Live")).setMessage(I18n.t("Camera và micro chỉ bật sau khi bạn đồng ý lên Live.")).setItemIcons(new String[]{"video","mic"}).setItems(new String[]{I18n.t("Tham gia bằng video"),I18n.t("Chỉ âm thanh")},(d,n)->sendLive("live-guest-request","mode",n==0?"video":"audio")).show();}
  private void guestManagement(){if(!host)return;if(guestSheet!=null)guestSheet.dismiss();LinearLayout body=column();body.setPadding(dp(4),0,dp(4),0);TextView hint=text(I18n.t("Mời người đang xem · Tối đa 3 khách"),12,MUTED);hint.setGravity(Gravity.CENTER);body.addView(hint);for(int i=0;i<guestRequests.length();i++){JSONObject u=guestRequests.optJSONObject(i);if(u!=null)guestRow(body,u,true);}for(int i=0;i<guestUsers.length();i++){JSONObject u=guestUsers.optJSONObject(i);if(u!=null)guestRow(body,u,false);}if(guestUsers.length()==0&&guestRequests.length()==0){TextView empty=text(I18n.t("Chưa có người xem để mời"),14,MUTED);empty.setPadding(dp(8),dp(24),dp(8),dp(24));empty.setGravity(Gravity.CENTER);body.addView(empty);}ScrollView scroll=new ScrollView(this);scroll.addView(body);guestSheet=new Sheet(this).setTitle(I18n.t("Khách mời")).setView(scroll).setNegativeButton(I18n.t("Đóng"),null).show();}
  private void guestRow(LinearLayout body,JSONObject u,boolean request){LinearLayout line=row();line.setPadding(0,dp(8),0,dp(8));line.addView(liveAvatar(u.optString("name"),u.optString("avatar"),36),new LinearLayout.LayoutParams(dp(36),dp(36)));TextView name=text(u.optString("name"),13,TEXT);name.setMaxLines(2);name.setPadding(dp(8),0,dp(4),0);line.addView(name,new LinearLayout.LayoutParams(0,-2,1));String label=request?"Duyệt":u.optBoolean("onStage")?"Gỡ":"Mời";TextView action=pill(I18n.t(label),true,()->{sendLive(request?"live-guest-approve":u.optBoolean("onStage")?"live-guest-remove":"live-guest-invite","to",u.optString("id"));if(guestSheet!=null)guestSheet.dismiss();});action.setTextSize(12);action.setGravity(Gravity.CENTER);line.addView(action,new LinearLayout.LayoutParams(Math.max(UiMetrics.dpRaw(this,48),dp(66)),UiMetrics.dpRaw(this,48)));UiMetrics.enforceMinTouchTarget(action,48);if(request){TextView no=text("×",24,MUTED);no.setGravity(Gravity.CENTER);no.setContentDescription(I18n.t("Từ chối"));no.setOnClickListener(v->{sendLive("live-guest-decline","to",u.optString("id"));if(guestSheet!=null)guestSheet.dismiss();});no.setLayoutParams(new LinearLayout.LayoutParams(dp(36),dp(36)));line.addView(UiMetrics.wrapMinTouchTarget(this,no,48));}body.addView(line);}
  private void invitation(JSONObject message){if(!currentRoom.equals(message.optString("room")))return;pendingInvitation=message;if(invitationSheet!=null)invitationSheet.dismiss();JSONObject fromObj=message.optJSONObject("from");String fromName=fromObj==null?I18n.t("Chủ phòng"):fromObj.optString("name",I18n.t("Chủ phòng"));invitationSheet=new Sheet(this).setTitle(I18n.t("Mời lên Live")).setMessage(fromName+" · "+I18n.t("Mời bạn trò chuyện cùng")).setItemIcons(new String[]{"video","mic"}).setItems(new String[]{I18n.t("Tham gia bằng video"),I18n.t("Chỉ âm thanh")},(d,n)->{inviteMode=n==0?"video":"audio";acceptGuest();}).setNegativeButton(I18n.t("Từ chối"),(d,w)->{if(pendingInvitation!=null)sendLive("live-guest-answer","token",pendingInvitation.optString("token"),"accept",false);pendingInvitation=null;}).show();}
  private void clearPendingGuest(){if(pendingGuestRtc!=null){pendingGuestRtc.close();pendingGuestRtc=null;pendingGuestLocal=null;}}
  private void acceptGuest(){if(!joined||socket==null||!ready){clearPendingGuest();return;}if(pendingInvitation==null||pendingInvitation.optLong("expiresAt")<System.currentTimeMillis()){pendingInvitation=null;liveToast("Lời mời đã hết hạn.");return;}if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED||inviteMode.equals("video")&&checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){permissionPrompt=true;requestPermissions(inviteMode.equals("video")?new String[]{Manifest.permission.CAMERA,Manifest.permission.RECORD_AUDIO}:new String[]{Manifest.permission.RECORD_AUDIO},302);return;}try{clearPendingGuest();pendingGuestLocal=new SurfaceViewRenderer(this);pendingGuestRtc=new NativeRtc(this,config,pendingGuestLocal,null,new NativeRtc.Events(){public void signal(String peer,JSONObject value){}public void status(String value){}},false);pendingGuestRtc.media(this,inviteMode.equals("video"));}catch(Exception error){clearPendingGuest();sendLive("live-guest-answer","token",pendingInvitation.optString("token"),"accept",false);pendingInvitation=null;liveToast("Không mở được camera/micro.");return;}sendLive("live-guest-answer","token",pendingInvitation.optString("token"),"accept",true,"mode",inviteMode);pendingInvitation=null;}

  private Runnable hideStatus = () -> {};

  // Camera có thể còn bị màn quay video giữ trong giây lát: thử lại vài lần trước khi báo lỗi.
  private void startHostMedia(final int attempt) {
    if (rtc == null || isFinishing()) return;
    try {
      rtc.media(this, true);rtc.microphone(pendingHostMic);if(previewLook!=null&&rtc.effects()!=null){LiveEffects f=rtc.effects();f.filter=previewLook.filter;f.sticker=previewLook.sticker;f.beautyOn=previewLook.beautyOn;f.smooth=previewLook.smooth;f.blemish=previewLook.blemish;f.eyes=previewLook.eyes;f.lips=previewLook.lips;previewLook=null;}
      status.setText(I18n.t("Bạn đang phát trực tiếp"));
      ((View) status.getParent()).postDelayed(hideStatus, 2500);
    } catch (Exception e) {
      if (attempt < 3) { status.setText(I18n.t("Đang mở camera…")); liveHandler.postDelayed(() -> startHostMedia(attempt + 1), 700); return; }
      Toast.makeText(this, I18n.t("Không mở được camera/micro. Hãy kiểm tra quyền rồi thử lại."), Toast.LENGTH_LONG).show();
      if (socket != null) socket.send(NativeSocket.json("type", "leave"));
      finish();
    }
  }

  private LinearLayout sideButton(String iconName, String label, Runnable click) {
    LinearLayout b = column();
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    b.setPadding(0,dp(4),0,dp(4));
    FrameLayout circle = new FrameLayout(this);
    circle.setBackground(roundStroke(GLIVE_BTN, 99, 0x22ffffff));
    ImageView i = icon(iconName, 0xfff1f3f4);
    circle.addView(i, new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    b.addView(circle, new LinearLayout.LayoutParams(dp(36), dp(36)));
    TextView t = text(label, 10, 0xffe8eaed);
    t.setTypeface(null, android.graphics.Typeface.BOLD);
    t.setGravity(Gravity.CENTER);
    t.setMaxLines(2);t.setIncludeFontPadding(false);
    t.setEllipsize(android.text.TextUtils.TruncateAt.END);
    t.setPadding(dp(2),dp(3),dp(2),0);
    b.addView(t);
    b.setContentDescription(label);
    b.setOnClickListener(v -> click.run());
    return b;
  }

  public void closed() {
    if(cameraSetup&&!isFinishing()){liveToast("Kết nối Live bị gián đoạn. Hãy thử lại.");stopGameSession();finish();return;}
    if (isFinishing()) return;
    stopGameSession();ready = false;joined = false;joining = false;clearPendingGuest();pendingInvitation=null;
    if(liveStage instanceof VerticalMediaStage)((VerticalMediaStage)liveStage).prepare();
    if(status!=null){
      status.setText(I18n.t("Đã mất kết nối. Hãy mở lại mục Trực tiếp."));
      status.setVisibility(View.VISIBLE);
    }
    if (rtc != null) { rtc.close(); rtc = null; }
    if (audio != null) { audio.setMode(previousMode); audio.setSpeakerphoneOn(previousSpeaker); }
  }

  protected void onStop() { super.onStop();if(gameSession){gameControllerVisible=false;syncGameVisibility();}if(giftExperience!=null)giftExperience.stopVisuals();if(gameSession&&gameService!=null&&gameComments)gameService.overlayVisible(true); if ((joined || previewing) && !gameSession&&gameConnection==null&&!projectionPrompt&&!permissionPrompt&&!externalPicker&&!isChangingConfigurations()) { if(joined){sendLive("leave");if(host)Toast.makeText(this,I18n.t("Buổi Live đã kết thúc vì rời ứng dụng."),Toast.LENGTH_LONG).show();} finish(); } }
  @Override protected void onResume(){super.onResume();gameControllerVisible=true;syncGameVisibility();externalPicker=false;permissionPrompt=false;if(gameService!=null)gameService.overlayVisible(false);if(getIntent()!=null&&getIntent().getBooleanExtra("show_gifts",false)){getIntent().removeExtra("show_gifts");root.postDelayed(this::gifts,800);}}
  @Override public void onBackPressed(){if(joined){confirmLeave();return;}super.onBackPressed();}

  protected void onDestroy() {
    liveHandler.removeCallbacksAndMessages(null);
    if(guestSheet!=null){try{guestSheet.dismiss();}catch(Exception ignored){}guestSheet=null;}
    if(invitationSheet!=null){try{invitationSheet.dismiss();}catch(Exception ignored){}invitationSheet=null;}
    if(giftExperience!=null)giftExperience.close();
    if(gamePicker!=null)gamePicker.close();
    stopGameSession();clearPendingGuest();
    if (socket != null) socket.close();
    if (rtc != null) rtc.close();
    if (audio != null) { audio.setMode(previousMode); audio.setSpeakerphoneOn(previousSpeaker); }
    super.onDestroy();
  }

  private void effectsMenu() {
    final LiveEffects fx = rtc == null ? null : rtc.effects();
    if (fx == null) return;
    boolean dark = WebTheme.isDark(this);
    int activeColor = dark ? GLIVE_AMBER : WebDesign.PURPLE_INK[0];
    int idleColor = dark ? 0xffb8b3c6 : WebDesign.MUTED_STRICT[0];
    int activeBg = dark ? 0x26fdd663 : 0x185b3fd6;
    LinearLayout body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);
    LinearLayout tabs=new LinearLayout(this);tabs.setPadding(dp(4),0,dp(4),dp(4));FrameLayout host=new FrameLayout(this);android.widget.ScrollView scroll=new android.widget.ScrollView(this);scroll.addView(host);
    Runnable changed=()->{};
    EffectControls.Target target=EffectControls.forLive(fx);
    final String[][] tabSpecs=new String[][]{{"beauty","Làm đẹp"},{"sticker","Hiệu ứng"},{"filter","Màu"}};
    final TextView[] tabBtns=new TextView[tabSpecs.length];
    final String[] activeTab={"beauty"};
    Runnable syncTabs=()->{
      for(int i=0;i<tabSpecs.length;i++){
        boolean on=tabSpecs[i][0].equals(activeTab[0]);
        TextView btn=tabBtns[i];
        int fg=on?activeColor:idleColor;
        android.graphics.drawable.Drawable ic=EditorIcons.drawable(this,tabSpecs[i][0],fg);
        if(ic!=null){ic.setBounds(0,0,dp(20),dp(20));btn.setCompoundDrawables(null,ic,null,null);}
        btn.setTextColor(fg);
        btn.setTypeface(null,on?Typeface.BOLD:Typeface.NORMAL);
        btn.setBackground(on?round(activeBg,14):null);
      }
    };
    for(int i=0;i<tabSpecs.length;i++){
      final String[] tab=tabSpecs[i];
      TextView button=new KinnectText(this);
      button.setText(I18n.t(tab[1]));
      button.setCompoundDrawablePadding(dp(5));
      button.setTextSize(12);
      button.setGravity(Gravity.CENTER);
      button.setPadding(0,dp(10),0,dp(10));
      button.setOnClickListener(v->{activeTab[0]=tab[0];syncTabs.run();host.removeAllViews();host.addView(EffectControls.panel(this,tab[0],target,changed));});
      tabBtns[i]=button;
      tabs.addView(button,new LinearLayout.LayoutParams(0,-2,1));
      UiMetrics.enforceMinTouchTarget(button,48);
    }
    syncTabs.run();
    body.addView(tabs);body.addView(scroll,new LinearLayout.LayoutParams(-1,Math.min(dp(360),getResources().getDisplayMetrics().heightPixels/2)));host.addView(EffectControls.panel(this,"beauty",target,changed));
    new Sheet(this).setTitle(I18n.t("Hiệu ứng Live")).setView(body).setPositiveButton(I18n.t("Xong"),null).show();
  }
}
