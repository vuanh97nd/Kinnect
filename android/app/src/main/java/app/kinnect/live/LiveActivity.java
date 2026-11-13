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
  private boolean cameraSetup,setupStarted;private boolean creationEntry;private String liveMode="chat",gameTitle="";private boolean choosingMode,externalPicker,projectionPrompt,gameSound=true,screenPaused,gameSession;
  private LiveGameService gameService;private ServiceConnection gameConnection;private View screenCover;
  private static final int GLIVE_BG = 0xff0a0a0c;
  private static final int GLIVE_SURFACE = 0xff141418;
  private static final int GLIVE_PILL = 0xa618181d;
  private static final int GLIVE_BTN = 0xff28282d;
  private static final int GLIVE_RED = 0xffee2b2b;
  private static final int GLIVE_AMBER = 0xfffdd663;
  private static final int GLIVE_BLUE = 0xffa8c7fa;

  private TextView modeLabel(String mode){return text(I18n.t(modeName(mode)),12,0xffffffff);}
  private String modeName(String mode){return mode.equals("game")?"Chơi game":"Trò chuyện";}
  private String modeIcon(String mode){return mode.equals("game")?"gamepad":"video";}
  private void chooseMode(){if(!cameraSetup){startActivity(new Intent(this,StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE,"live"));finish();return;}creationEntry=true;if(ready)prepareHost();else preparationWaiting();}
  private LinearLayout preparationModes(EditText title){
    LinearLayout modes=row();modes.setTag("live:preparation-modes");
    modes.setPadding(dp(3),dp(3),dp(3),dp(3));
    modes.setBackground(roundStroke(GLIVE_BTN,999,0x22ffffff));
    LinearLayout.LayoutParams modesLp=new LinearLayout.LayoutParams(-1,dp(40));
    modesLp.topMargin=dp(8);modesLp.bottomMargin=dp(8);
    modes.setLayoutParams(modesLp);
    for(String mode:new String[]{"chat","game"}){
      boolean active = mode.equals(liveMode);
      TextView chip=text(I18n.t(modeName(mode)),12,active?0xff111114:0xffd8d4e2);
      chip.setSingleLine(true);
      chip.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
      chip.setGravity(Gravity.CENTER_VERTICAL);chip.setMinHeight(dp(34));chip.setPadding(dp(12),0,dp(12),0);
      chip.setBackground(active ? round(GLIVE_AMBER, 999) : null);
      android.graphics.drawable.Drawable d=WebIcons.load(this,modeIcon(mode));d.setTint(chip.getCurrentTextColor());d.setBounds(0,0,dp(16),dp(16));
      chip.setCompoundDrawablesRelative(d,null,null,null);chip.setCompoundDrawablePadding(dp(6));
      chip.setOnClickListener(v->{if(mode.equals(liveMode)||joining||gameSession||projectionPrompt)return;if(title!=null)topicText=title.getText().toString().trim();liveMode=mode;previewing=false;if(rtc!=null){rtc.close();rtc=null;}if(ready)prepareHost();else preparationWaiting();});
      LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(0,-1,1);modes.addView(chip,at);
    }
    return modes;
  }
  private void preparationWaiting(){
    root.removeAllViews();rooms=null;root.setBackgroundColor(GLIVE_BG);
    LinearLayout bar=row();bar.setPadding(dp(10),dp(8),dp(14),dp(8));
    bar.addView(liveAction("x","Thoát",this::finish),new LinearLayout.LayoutParams(dp(42),dp(42)));
    TextView title=text(I18n.t("Chuẩn bị Live"),18,0xffffffff);title.setTypeface(null,Typeface.BOLD);title.setPadding(dp(12),0,0,0);bar.addView(title);
    root.addView(bar);
    if(!cameraSetup)root.addView(preparationModes(null));
    status=text(I18n.t("Đang kết nối…"),14,0xffb8b3c6);status.setGravity(Gravity.CENTER);
    root.addView(status,new LinearLayout.LayoutParams(-1,0,1));
  }
  private void createHostRoom(){if(socket==null||!ready||joining||joined)return;previewing=false;host=true;joining=true;sendLive("create","multiGuest",true,"liveModes",true,"liveMode",liveMode,"gameTitle",gameTitle,"title",topicText,"comments",liveMode.equals("game")?true:gameComments);}

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
    GradientDrawable d = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { GLIVE_RED, 0xffd92648 });
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
    int variant = dark ? 1 : 0;
    BG = WebDesign.BG[variant]; CARD = WebDesign.CARD[variant]; TEXT = WebDesign.INK[variant];
    MUTED = WebDesign.MUTED[variant]; ACCENT = WebDesign.PURPLE[variant]; SOFT = WebDesign.WASH[variant]; LINE = WebDesign.LINE[variant];
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    if (!dark) getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    root = column();
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener((v, i) -> { if(Build.VERSION.SDK_INT>=30){android.graphics.Insets bars=i.getInsets(android.view.WindowInsets.Type.systemBars());android.graphics.Insets keyboard=i.getInsets(android.view.WindowInsets.Type.ime());v.setPadding(bars.left,bars.top,bars.right,Math.max(bars.bottom,keyboard.bottom));}else v.setPadding(0,i.getSystemWindowInsetTop(),0,i.getSystemWindowInsetBottom()); return i; });
    setContentView(root);giftExperience=new LiveGiftExperience(this,this::sendGift);
    if(getIntent().getBooleanExtra("show_gifts",false))root.postDelayed(this::gifts,600);
    cameraSetup=getIntent().getBooleanExtra("cameraSetup",false);if(cameraSetup){liveMode="game".equals(getIntent().getStringExtra("liveMode"))?"game":"chat";gameTitle=getIntent().getStringExtra("gameTitle");if(gameTitle==null)gameTitle="";topicText=getIntent().getStringExtra("title");if(topicText==null)topicText="";pendingHostMic=getIntent().getBooleanExtra("mic",true);gameSound=getIntent().getBooleanExtra("sound",true);gameComments=getIntent().getBooleanExtra("comments",false);}
    creationEntry=getIntent().getBooleanExtra(EXTRA_HOST,false);if(creationEntry)preparationWaiting();else lobby();
    String origin = ServerConfig.DEFAULT_ORIGIN;
    NativeApi.shared.call("GET", "/api/call-config", null, (data, error, code) -> {
      if (isFinishing() || isDestroyed()) return;
      if (error != null) { if(cameraSetup){liveToast("Máy chủ phản hồi chậm. Hãy thử lại.");finish();}else status.setText(error); return; }
      config = data;
      ensurePrivacy(()->socket = new NativeSocket(origin, this));
    });
    if(cameraSetup)new Handler(Looper.getMainLooper()).postDelayed(()->{if(!isFinishing()&&!isDestroyed()&&!joined&&!projectionPrompt){liveToast("Máy chủ phản hồi chậm. Hãy thử lại.");stopGameSession();finish();}},30000);
    audio = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
    previousMode = audio.getMode();
    previousSpeaker = audio.isSpeakerphoneOn();
  }

  private void ensurePrivacy(Runnable ready){NativeApi.shared.call("GET","/api/me/privacy-consent",null,(data,error,statusCode)->{if(isFinishing()||isDestroyed())return;if(error!=null){status.setText(error);return;}if(data.optBoolean("accepted")){ready.run();return;}new Sheet(this).setTitle(I18n.t("Thông báo sử dụng dữ liệu")).setMessage(I18n.t(data.optString("notice"))).setPositiveButton(I18n.t("Tôi đồng ý"),(d,w)->NativeApi.shared.call("POST","/api/me/privacy-consent",NativeSocket.json("accepted",true,"version",data.optString("version")),(accepted,failure,code)->{if(failure==null)ready.run();else status.setText(failure);})).setNegativeButton(I18n.t("Để sau"),(d,w)->finish()).show();});}

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
    bar.addView(back, new LinearLayout.LayoutParams(dp(36), dp(36)));
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
    ImageView refresh = icon("rotate_ccw", TEXT);
    refresh.setPadding(dp(8), dp(8), dp(8), dp(8));
    refresh.setBackground(round(SOFT, 999));
    refresh.setContentDescription(I18n.t("Làm mới"));
    refresh.setOnClickListener(v -> renderRooms());
    bar.addView(refresh, new LinearLayout.LayoutParams(dp(36), dp(36)));
    root.addView(bar, new LinearLayout.LayoutParams(-1, dp(54)));

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
    c.addView(rooms, new LinearLayout.LayoutParams(-1, -2));

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
    footer.addView(fab,new LinearLayout.LayoutParams(-2,dp(44)));
    root.addView(footer,new LinearLayout.LayoutParams(-1,-2));
  }

  private void askTitleAndHost() { chooseMode(); }

  private String topicText = "";

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
      tile.setOnClickListener(v->{if(!joining&&ready){joining=true;sendLive("join","room",room.optString("id"),"multiGuest",true,"liveModes",true);}});
      LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(-1,-2);at.bottomMargin=dp(10);rooms.addView(tile,at);
    }
    status.setVisibility(View.GONE);if(count>0)return;
    status.setVisibility(View.GONE);
    LinearLayout empty = column();
    empty.setGravity(Gravity.CENTER);
    empty.setPadding(dp(24), dp(32), dp(24), dp(32));
    empty.setBackground(roundStroke(CARD, 24, LINE));
    FrameLayout outerRing = new FrameLayout(this);
    outerRing.setBackground(round(SOFT, 999));
    FrameLayout bubble = new FrameLayout(this);
    bubble.setBackground(round(0x22ee2b2b, 999));
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
    root.removeAllViews();root.setBackgroundColor(GLIVE_BG);
    FrameLayout stage=new FrameLayout(this);stage.setBackground(round(0xff000000,24));stage.setClipToOutline(true);
    LinearLayout.LayoutParams stageLp=new LinearLayout.LayoutParams(-1,0,1);stageLp.setMargins(dp(6),dp(6),dp(6),0);
    root.addView(stage,stageLp);
    SurfaceViewRenderer display=new SurfaceViewRenderer(this);localLive=display;stage.addView(display,new FrameLayout.LayoutParams(-1,-1));
    TextView close=text(I18n.t("×"),26,0xffffffff);close.setGravity(Gravity.CENTER);close.setBackground(roundStroke(GLIVE_PILL,999,0x28ffffff));close.setContentDescription(I18n.t("Đóng camera chuẩn bị Live"));close.setOnClickListener(v->finish());FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(dp(42),dp(42),Gravity.TOP|Gravity.START);cp.setMargins(dp(12),dp(12),0,0);stage.addView(close,cp);
    TextView badge=previewBadge();FrameLayout.LayoutParams bp=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);bp.setMargins(dp(60),dp(14),dp(60),0);stage.addView(badge,bp);
    LinearLayout controls=column();controls.setPadding(dp(16),dp(14),dp(16),dp(16));
    GradientDrawable deckBg=new GradientDrawable();deckBg.setColor(GLIVE_SURFACE);float r=dp(24);deckBg.setCornerRadii(new float[]{r,r,r,r,0,0,0,0});controls.setBackground(deckBg);
    root.addView(controls,new LinearLayout.LayoutParams(-1,-2));
    EditText title=field(I18n.t("Tiêu đề buổi Live"));title.setText(topicText);title.setTextSize(13);title.setTextColor(0xffffffff);title.setHintTextColor(0xff9e9aa8);title.setBackground(roundStroke(GLIVE_BTN,12,0x22ffffff));title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});controls.addView(title,new LinearLayout.LayoutParams(-1,dp(42)));
    controls.addView(preparationModes(title));
    LinearLayout actions=row();actions.setPadding(0,dp(2),0,dp(6));final boolean[] mic={true};actions.addView(sideButton("flip",I18n.t("Lật camera"),()->{if(rtc!=null)rtc.flip();}),new LinearLayout.LayoutParams(0,-2,1));actions.addView(sideButton("wand",I18n.t("Làm đẹp"),this::effectsMenu),new LinearLayout.LayoutParams(0,-2,1));actions.addView(sideButton("mic","Micro",()->{mic[0]=!mic[0];badge.setText("●  "+(mic[0]?I18n.t("Xem trước · Mic sẽ bật khi phát"):I18n.t("Xem trước · Mic sẽ tắt khi phát")));}),new LinearLayout.LayoutParams(0,-2,1));controls.addView(actions);
    TextView start=pill(I18n.t("Bắt đầu Live"),true,()->{});start.setTextSize(13);start.setEnabled(false);start.setAlpha(.45f);controls.addView(start,new LinearLayout.LayoutParams(-1,dp(44)));status=text(I18n.t("Đang mở camera…"),12,0xffb8b3c6);status.setGravity(Gravity.CENTER);status.setPadding(0,dp(8),0,dp(2));controls.addView(status,new LinearLayout.LayoutParams(-1,-2));
    try{rtc=new NativeRtc(this,config,display,null,new NativeRtc.Events(){public void signal(String peer,JSONObject payload){}public void status(String text){status.setText(text);}},false);final NativeRtc previewRtc=rtc;display.addFrameListener(new org.webrtc.EglRenderer.FrameListener(){private boolean received;public void onFrame(android.graphics.Bitmap bitmap){if(bitmap!=null)bitmap.recycle();if(received)return;received=true;runOnUiThread(()->{if(!previewing||rtc!=previewRtc||isFinishing()||isDestroyed())return;status.setText(I18n.t("Camera đã sẵn sàng · Chưa phát sóng"));start.setEnabled(true);start.setAlpha(1);});}},0f);rtc.media(this,true);rtc.microphone(false);start.setOnClickListener(v->{if(!previewing||!ready||joining)return;topicText=title.getText().toString().trim();start.setEnabled(false);previewLook=rtc.effects();carryPreview=true;pendingHostMic=mic[0];rtc.microphone(pendingHostMic);createHostRoom();});}
    catch(Exception error){if(rtc!=null){rtc.close();rtc=null;}status.setText(I18n.t("Không mở được camera. Kiểm tra quyền camera/micro rồi mở lại."));}
  }
  private LiveGamePicker gamePicker;private boolean gameComments=true;private boolean roomComments=true;private boolean pendingHostMic=true;
  private void showGamePreview(){
    previewing=true;host=false;if(rtc!=null){rtc.close();rtc=null;}root.removeAllViews();root.setBackgroundColor(BG);
    ScrollView scroll=new ScrollView(this);LinearLayout body=column();body.setPadding(dp(20),dp(16),dp(20),dp(24));scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,-1));
    ImageView back=icon("x",TEXT);back.setPadding(dp(10),dp(10),dp(10),dp(10));back.setContentDescription(I18n.t("Thoát"));back.setBackground(roundStroke(SOFT,999,LINE));back.setOnClickListener(v->finish());body.addView(back,new LinearLayout.LayoutParams(dp(42),dp(42)));
    FrameLayout gameBadge=new FrameLayout(this);gameBadge.setBackground(round(SOFT,999));gameBadge.addView(icon("gamepad",GLIVE_RED),new FrameLayout.LayoutParams(dp(34),dp(34),Gravity.CENTER));LinearLayout.LayoutParams art=new LinearLayout.LayoutParams(dp(68),dp(68));art.gravity=Gravity.CENTER;art.setMargins(0,dp(20),0,dp(14));body.addView(gameBadge,art);
    TextView heading=text(I18n.t("Chơi game trực tiếp"),22,TEXT);heading.setTypeface(null,Typeface.BOLD);heading.setGravity(Gravity.CENTER);body.addView(heading);
    TextView hint=text(I18n.t("Chọn một ứng dụng game trong hộp thoại Android. Màn hình chỉ được phát sau khi bạn đồng ý."),14,MUTED);hint.setGravity(Gravity.CENTER);hint.setPadding(0,dp(8),0,dp(16));body.addView(hint);
    EditText title=field(I18n.t("Tiêu đề buổi Live"));title.setText(topicText);title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});body.addView(title,new LinearLayout.LayoutParams(-1,dp(50)));body.addView(preparationModes(title));
    EditText name=field(I18n.t("Chọn game"));name.setText(gameTitle);name.setFocusable(false);name.setCursorVisible(false);name.setKeyListener(null);name.setFocusable(false);name.setFocusableInTouchMode(false);name.setShowSoftInputOnFocus(false);name.setContentDescription(I18n.t("Chọn game"));name.setOnClickListener(v->{if(gamePicker!=null)gamePicker.close();gamePicker=new LiveGamePicker(this,gameTitle,value->{gameTitle=value;name.setText(value);});gamePicker.show();});name.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(60)});LinearLayout.LayoutParams np=new LinearLayout.LayoutParams(-1,dp(50));np.topMargin=dp(10);body.addView(name,np);
    CheckBox mic=new CheckBox(this);mic.setTypeface(ApprovedTypography.font(this,0));mic.setTextColor(TEXT);mic.setText(I18n.t("Bật micro bình luận"));mic.setChecked(pendingHostMic);body.addView(mic);
    CheckBox sound=new CheckBox(this);sound.setTypeface(ApprovedTypography.font(this,0));sound.setTextColor(TEXT);sound.setText(I18n.t("Phát tiếng game nếu được ứng dụng cho phép"));sound.setChecked(gameSound&&Build.VERSION.SDK_INT>=29);sound.setEnabled(Build.VERSION.SDK_INT>=29);body.addView(sound);
    CheckBox comments=new CheckBox(this);comments.setTypeface(ApprovedTypography.font(this,0));comments.setTextColor(TEXT);comments.setText(I18n.t("Bình luận nổi khi chơi game"));comments.setChecked(gameComments);comments.setOnCheckedChangeListener((b,on)->gameComments=on);body.addView(comments);
    TextView privacy=text(I18n.t("Nên chọn chia sẻ một ứng dụng và bật Không làm phiền. Khi chia sẻ toàn màn hình, nội dung và thông báo khác có thể xuất hiện."),12,MUTED);privacy.setPadding(dp(12),dp(10),dp(12),dp(10));privacy.setBackground(roundStroke(SOFT,14,LINE));LinearLayout.LayoutParams plp=new LinearLayout.LayoutParams(-1,-2);plp.setMargins(0,dp(10),0,dp(16));body.addView(privacy,plp);
    TextView start=pill(I18n.t("Chọn màn hình & Bắt đầu Live"),true,()->{topicText=title.getText().toString().trim();gameTitle=name.getText().toString().trim();pendingHostMic=mic.isChecked();gameSound=sound.isChecked();requestGameProjection();});start.setMinHeight(dp(54));start.setPadding(dp(14),dp(12),dp(14),dp(12));body.addView(start,new LinearLayout.LayoutParams(-1,-2));
    status=text(I18n.t("Chưa phát sóng · Camera không bật"),12,MUTED);status.setGravity(Gravity.CENTER);status.setPadding(0,dp(14),0,0);body.addView(status);
  }
  private void requestGameProjection(){if(projectionPrompt||gameSession||joining||!ready)return;if(gameComments&&!android.provider.Settings.canDrawOverlays(this)){projectionPrompt=true;try{startActivityForResult(new Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,android.net.Uri.parse("package:"+getPackageName())),324);}catch(Exception e){projectionPrompt=false;gameComments=false;liveToast("Chưa bật bình luận nổi; vẫn có thể phát game.");if(cameraSetup)requestGameProjection();}return;}projectionPrompt=true;try{MediaProjectionManager manager=(MediaProjectionManager)getSystemService(MEDIA_PROJECTION_SERVICE);Intent capture=cameraSetup&&Build.VERSION.SDK_INT>=34?manager.createScreenCaptureIntent(android.media.projection.MediaProjectionConfig.createConfigForDefaultDisplay()):manager.createScreenCaptureIntent();startActivityForResult(capture,323);}catch(Exception e){projectionPrompt=false;liveToast("Không mở được quyền chia sẻ màn hình.");if(cameraSetup)finish();}}
  @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);externalPicker=false;if(request==324){projectionPrompt=false;if(cameraSetup){gameComments=android.provider.Settings.canDrawOverlays(this);requestGameProjection();}else liveToast(android.provider.Settings.canDrawOverlays(this)?"Đã bật bình luận nổi. Bấm bắt đầu Live.":"Chưa cấp quyền bình luận nổi. Có thể tắt lựa chọn này để phát.");return;}if(request!=323)return;projectionPrompt=false;if(result!=RESULT_OK||data==null){if(cameraSetup){liveToast("Đã hủy chia sẻ · Chưa phát sóng");finish();}else status.setText(I18n.t("Đã hủy chia sẻ · Chưa phát sóng"));return;}if(!ready||isFinishing()){liveToast("Mất kết nối; hãy chọn chia sẻ lại.");return;}startGameSession(data);}
  private void startGameSession(Intent permission){
    gameConnection=new ServiceConnection(){public void onServiceConnected(ComponentName name,IBinder binder){if(isFinishing()||isDestroyed())return;try{gameService=((LiveGameService.SessionBinder)binder).service();gameService.attach(new LiveGameService.Controls(){public void reply(String text){if(joined&&ready)sendLive("chat","text",text);else liveToast("Chưa kết nối để gửi bình luận.");}public void stop(){sendLive("leave");stopGameSession();finish();}public void pause(){toggleScreenPause();}public void mic(){liveMic=!liveMic;if(rtc!=null)rtc.microphone(liveMic);syncGameVisibility();}});
      gameSession=true;screenPaused=false;gameControllerVisible=true;localLive=null;rtc=new NativeRtc(LiveActivity.this,config,null,null,new NativeRtc.Events(){public void signal(String peer,JSONObject value){}public void status(String value){liveToast(value);}},true);
      rtc.screen(LiveActivity.this,permission,()->{sendLive("leave");stopGameSession();finish();},gameSound);syncGameVisibility();rtc.microphone(pendingHostMic);liveMic=pendingHostMic;carryPreview=true;createHostRoom();
    }catch(Exception e){if(rtc!=null){rtc.close();rtc=null;}stopGameSession();joining=false;previewing=false;if(cameraSetup){liveToast("Không chia sẻ được màn hình. Hãy thử lại.");finish();return;}showGamePreview();status.setText(I18n.t("Không chia sẻ được màn hình. Hãy cấp quyền lại."));}}
    public void onServiceDisconnected(ComponentName name){if(gameSession){gameSession=false;sendLive("leave");finish();}}};
    if(!bindService(new Intent(this,LiveGameService.class),gameConnection,Context.BIND_AUTO_CREATE)){gameConnection=null;liveToast("Không khởi động được Live game.");}
  }
  private void stopGameSession(){gameSession=false;LiveGameService service=gameService;gameService=null;if(service!=null)service.detach();ServiceConnection connection=gameConnection;gameConnection=null;if(connection!=null)try{unbindService(connection);}catch(Exception ignored){}if(liveMode.equals("game")&&rtc!=null){NativeRtc old=rtc;rtc=null;old.close();}}
  private void syncGameVisibility(){if(!gameSession||rtc==null)return;boolean hold=screenPaused||gameControllerVisible;if(screenCover!=null&&host)screenCover.setVisibility(hold?View.VISIBLE:View.GONE);rtc.screenPaused(hold);if(joined&&ready)sendLive("live-game-state","paused",hold);if(gameService!=null)gameService.flags(hold,!liveMic);}
  private void toggleScreenPause(){if(!gameSession||rtc==null)return;screenPaused=!screenPaused;syncGameVisibility();}
  private void openGameApp(){if(!gameSession)return;Intent game=LiveGameLaunch.intent(this,gameTitle);if(game==null){liveToast("Không tìm thấy game trên máy.");sendLive("leave");stopGameSession();finish();return;}try{startActivity(game);}catch(Exception e){liveToast("Không mở được game. Chưa phát tiếp.");sendLive("leave");stopGameSession();finish();}}
  private void mountGame(FrameLayout stage){
    LinearLayout cover=column();cover.setGravity(Gravity.CENTER);cover.setPadding(dp(30),dp(30),dp(30),dp(30));cover.setBackgroundColor(GLIVE_BG);
    FrameLayout shieldWell=new FrameLayout(this);shieldWell.setBackground(roundStroke(GLIVE_BTN,999,0x28ffffff));shieldWell.addView(icon("gamepad",GLIVE_AMBER),new FrameLayout.LayoutParams(dp(28),dp(28),Gravity.CENTER));
    LinearLayout.LayoutParams swLp=new LinearLayout.LayoutParams(dp(64),dp(64));swLp.bottomMargin=dp(16);cover.addView(shieldWell,swLp);
    TextView coverText=text(I18n.t(host?"Màn hình điều khiển · Không phát phần này":"Chủ phòng đang tạm che màn hình"),16,0xffffffff);coverText.setTypeface(null,Typeface.BOLD);coverText.setGravity(Gravity.CENTER);cover.addView(coverText);
    if(host){TextView open=text(I18n.t("Mở game"),15,0xff111114);open.setTypeface(null,Typeface.BOLD);open.setGravity(Gravity.CENTER);open.setMinHeight(dp(48));open.setPadding(dp(28),dp(12),dp(28),dp(12));open.setBackground(round(GLIVE_AMBER,999));open.setOnClickListener(v->openGameApp());LinearLayout.LayoutParams button=new LinearLayout.LayoutParams(-2,-2);button.topMargin=dp(20);cover.addView(open,button);}
    cover.setVisibility(host?View.VISIBLE:View.GONE);screenCover=cover;FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-1,-1);stage.addView(cover,1,cp);
    TextView mode=text(I18n.t("Chơi game")+(roomInfo.optString("gameTitle").isEmpty()?"":" · "+roomInfo.optString("gameTitle"))+(host?" · "+I18n.t("Điều khiển"):""),13,0xffffffff);mode.setTypeface(null,Typeface.BOLD);mode.setMinHeight(dp(44));mode.setPadding(dp(14),dp(10),dp(14),dp(10));mode.setBackground(roundStroke(GLIVE_PILL,999,0x33fdd663));android.graphics.drawable.Drawable modeGlyph=WebIcons.load(this,"gamepad");modeGlyph.setTint(0xffffffff);modeGlyph.setBounds(0,0,dp(16),dp(16));mode.setCompoundDrawablesRelative(modeGlyph,null,null,null);mode.setCompoundDrawablePadding(dp(6));if(host)mode.setOnClickListener(v->new Sheet(this).setTitle(I18n.t("Live game")).setItemIcons(new String[]{"gamepad","shield_check","mic","log_out"}).setItems(new String[]{I18n.t("Mở game"),I18n.t(screenPaused?"Tiếp tục chia sẻ":"Tạm che màn hình"),I18n.t(liveMic?"Tắt mic":"Bật mic"),I18n.t("Kết thúc Live")},(d,n)->{if(n==0)openGameApp();if(n==1)toggleScreenPause();if(n==2){liveMic=!liveMic;if(rtc!=null)rtc.microphone(liveMic);syncGameVisibility();}if(n==3)confirmLeave();}).setNegativeButton(I18n.t("Quay lại"),null).show());FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.START);at.setMargins(dp(12),dp(96),dp(12),0);stage.addView(mode,at);
  }
  private final class ViewerStage extends VerticalMediaStage {
    ViewerStage(){super(LiveActivity.this,direction->{if(host||!liveRole.equals("viewer"))return false;return switchLive(direction);});}
  }

  private void prepareHost() {
    if (socket == null || !ready) { Toast.makeText(this, I18n.t("Đang kết nối máy chủ, thử lại sau giây lát."), Toast.LENGTH_SHORT).show(); return; }
    if ((!liveMode.equals("game")&&checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) || checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
      requestPermissions(liveMode.equals("game")?new String[]{Manifest.permission.RECORD_AUDIO}:new String[] { Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO }, 301);
      return;
    }
    if(cameraSetup){startCameraSetup();return;}showHostPreview();
  }

  private void startCameraSetup(){
    if(setupStarted||joining||joined)return;setupStarted=true;
    if(liveMode.equals("game")){if(LiveGameLaunch.intent(this,gameTitle)==null){liveToast("Không tìm thấy game trên máy.");finish();return;}requestGameProjection();return;}
    previewing=true;root.removeAllViews();FrameLayout stage=new FrameLayout(this);root.addView(stage,new LinearLayout.LayoutParams(-1,0,1));SurfaceViewRenderer display=new SurfaceViewRenderer(this);localLive=display;stage.addView(display,new FrameLayout.LayoutParams(-1,-1));status=text(I18n.t("Đang bắt đầu Live…"),14,TEXT);root.addView(status);
    try{rtc=new NativeRtc(this,config,display,null,new NativeRtc.Events(){public void signal(String peer,JSONObject value){}public void status(String value){status.setText(value);}},false);final NativeRtc owner=rtc;display.addFrameListener(new org.webrtc.EglRenderer.FrameListener(){boolean once;public void onFrame(android.graphics.Bitmap bitmap){if(bitmap!=null)bitmap.recycle();if(once)return;once=true;runOnUiThread(()->{if(isFinishing()||rtc!=owner||!ready)return;carryPreview=true;rtc.microphone(pendingHostMic);createHostRoom();});}},0f);rtc.media(this,true,getIntent().getBooleanExtra("front",true));LiveEffects look=rtc.effects();look.filter=getIntent().getStringExtra("filter")==null?"none":getIntent().getStringExtra("filter");look.sticker=getIntent().getStringExtra("sticker")==null?"none":getIntent().getStringExtra("sticker");look.beautyOn=getIntent().getBooleanExtra("beauty",false);look.smooth=getIntent().getFloatExtra("smooth",.5f);look.blemish=getIntent().getFloatExtra("blemish",.4f);look.eyes=getIntent().getFloatExtra("eyes",.2f);look.lips=getIntent().getFloatExtra("lips",0);rtc.microphone(false);}catch(Exception e){liveToast("Không mở được camera. Hãy thử lại.");finish();}
  }

  public void onRequestPermissionsResult(int code, String[] p, int[] grants) {
    super.onRequestPermissionsResult(code, p, grants);
    if(code==302){boolean allowed=grants.length>0;for(int grant:grants)allowed&=grant==0;if(allowed)acceptGuest();else liveToast("Cần quyền micro/camera để lên Live.");return;}
    if (code == 301) {
      boolean allowed=grants.length>0;for(int grant:grants)allowed&=grant==0;if (allowed) prepareHost();
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
      if (room != null && !joined) { host = false; socket.send(NativeSocket.json("type", "join", "multiGuest", true, "liveModes",true,"room", room)); getIntent().removeExtra(EXTRA_ROOM); }
      if (getIntent().getBooleanExtra(EXTRA_HOST, false) && !joined) { getIntent().removeExtra(EXTRA_HOST); askTitleAndHost(); }
    }
    if (type.equals("rooms")) { lastRooms = m.optJSONArray("rooms"); if (!joined && !previewing) { renderRooms();if(!creationEntry)autoJoin(); } }
    if (type.equals("joined")) { joined = true; joining = false; showRoom(m);if(gameSession){syncGameVisibility();if(cameraSetup)openGameApp();} }
    if(type.equals("viewers")){JSONArray users=m.optJSONArray("users");String[] names=new String[users==null?0:users.length()];for(int i=0;i<names.length;i++)names[i]=users.optJSONObject(i).optString("name");Sheet sheet=new Sheet(this).setTitle(I18n.t("Người đang xem")).setNegativeButton(I18n.t("Đóng"),null);if(names.length>0)sheet.setItemIcon("user_round").setItems(names,(d,n)->{});else sheet.setMessage(I18n.t("Chưa có người xem"));sheet.show();return;}
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
    if(type.equals("live-gift-receipt")||type.equals("live-gift-error")){if(giftExperience!=null)giftExperience.receipt(m);if(type.equals("live-gift-error"))liveToast(m.optString("message"));return;}
    if(type.equals("live-gift-ranking")||type.equals("live-gift-goal")){roomRanking=m;if(type.equals("live-gift-ranking")&&rankingRequested){rankingRequested=false;showGiftRanking(m);}return;}
    if(type.equals("live-reaction")&&currentRoom.equals(m.optString("room"))){if(m.optJSONObject("ranking")!=null)roomRanking=m.optJSONObject("ranking");showReactionEvent(m);}
    if (type.equals("chat")){if(chat!=null)addChat(m.optString("name"),m.optString("text"));if(gameService!=null)gameService.comment(m.optString("name"),m.optString("text"));}
    if (type.equals("room-ended") || type.equals("ended")) { if (host) { Toast.makeText(this, I18n.t("Buổi trực tiếp đã kết thúc."), Toast.LENGTH_LONG).show(); finish(); } else roomEnded(); }
    if (type.equals("error")) { if(host&&!joined){if(cameraSetup){liveToast(m.optString("message","Không bắt đầu được Live."));stopGameSession();finish();return;}stopGameSession();host=false;joining=false;previewing=false;showHostPreview();status.setText(m.optString("message",I18n.t("Chưa bắt đầu được Live. Hãy thử lại.")));return;}joining=false;if(liveStage!=null){liveStage.setTranslationY(0);liveStage.setAlpha(1);}status.setText(m.optString("message")); status.setVisibility(View.VISIBLE); }
  }

  private TextView viewers,arrival,giftBanner,comboButton,topSender;
  private JSONObject roomRanking;private boolean rankingRequested;private int localComboStreak=1;
  private LinearLayout audience;
  private FrameLayout reactionLayer;private LiveGiftExperience giftExperience;private long lastGift;
  private long lastReaction;private boolean fullFrame=true;
  private void renderAudience(JSONArray users){if(audience==null)return;audience.removeAllViews();if(users==null)return;for(int n=0;n<users.length();n++){JSONObject u=users.optJSONObject(n);if(u==null)continue;String name=u.optString("name","K");FrameLayout avatar=new FrameLayout(this);avatar.setBackground(roundStroke(GLIVE_BTN,99,0x33ffffff));avatar.setClipToOutline(true);TextView initial=text(name.isEmpty()?"K":name.substring(0,1).toUpperCase(),11,0xffffffff);initial.setTypeface(null,Typeface.BOLD);initial.setGravity(Gravity.CENTER);avatar.addView(initial,new FrameLayout.LayoutParams(-1,-1));String url=u.optString("avatar");if(url.startsWith("/api/users/"))NativeApi.shared.image(url,bytes->{if(isDestroyed()||bytes==null)return;android.graphics.Bitmap bitmap=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(bitmap!=null){ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setImageBitmap(bitmap);avatar.addView(image,new FrameLayout.LayoutParams(-1,-1));}});avatar.setContentDescription(name);avatar.setOnClickListener(v->Toast.makeText(this,name,Toast.LENGTH_SHORT).show());LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(dp(28),dp(28));at.leftMargin=dp(5);audience.addView(avatar,at);}}
  private void showArrival(String name){if(arrival==null)return;arrival.removeCallbacks(clearArrival);arrival.setText("●  "+name+" "+I18n.t("vừa tham gia"));arrival.setVisibility(View.VISIBLE);arrival.setAlpha(0);arrival.animate().alpha(1).setDuration(180).start();arrival.postDelayed(clearArrival,3500);}
 private void updateTopSender(String name,long coins){if(topSender==null||name==null||name.isEmpty())return;topSender.removeCallbacks(hideTopSender);topSender.setText(name+" · "+coins+" "+I18n.t("xu"));topSender.setVisibility(View.VISIBLE);topSender.setAlpha(0);topSender.animate().alpha(1).setDuration(180).start();topSender.postDelayed(hideTopSender,8000);}
 private final Runnable hideTopSender=()->{if(topSender!=null)topSender.setVisibility(View.GONE);};
  private final Runnable clearArrival=()->{if(arrival!=null)arrival.setVisibility(View.GONE);};
  private final Runnable clearGiftBanner=()->{if(giftBanner!=null)giftBanner.setVisibility(View.GONE);};
  private final Runnable clearComboButton=()->{if(comboButton!=null)comboButton.setVisibility(View.GONE);localComboStreak=1;};
  private void sendFreeHeart(){long now=System.currentTimeMillis();if(socket==null||!joined)return;if(now-lastReaction<350)return;lastReaction=now;socket.send(NativeSocket.json("type","live-reaction","kind","heart","free",true));}
  private void sendGift(String kind){long now=System.currentTimeMillis();if(socket==null||!joined)return;boolean isCombo=giftExperience!=null&&!giftExperience.comboId().isEmpty();if(now-lastGift<(isCombo?360:1200))return;lastGift=now;int qty=giftExperience==null?1:giftExperience.quantity();String cid=giftExperience==null?"":giftExperience.comboId(),tid=giftExperience==null?"":giftExperience.targetId();socket.send(NativeSocket.json("type","live-reaction","kind",kind,"giftId",kind,"isGift",true,"quantity",qty,"comboId",cid,"targetUserId",tid,"requestId",java.util.UUID.randomUUID().toString(),"priceVersion",giftExperience==null?0:giftExperience.version()));if(giftExperience!=null&&giftExperience.isComboable(kind)&&comboButton!=null){comboButton.removeCallbacks(clearComboButton);comboButton.setText("Combo x"+(++localComboStreak));comboButton.setVisibility(View.VISIBLE);comboButton.setOnClickListener(v->sendGift(kind));comboButton.postDelayed(clearComboButton,3500);}}
  private void sendReaction(String kind){if("heart".equals(kind))sendFreeHeart();else sendGift(kind);}
  private void gifts(){if(giftExperience!=null){localComboStreak=1;giftExperience.open();}}

  private void showReactionEvent(JSONObject m){boolean isFree=m.optBoolean("free",false)||(!m.has("giftId")&&"heart".equals(m.optString("kind")));String kind=m.optString("giftId",m.optString("kind")),name=m.optString("name");int qty=Math.max(1,m.optInt("quantity",1)),combo=Math.max(1,m.optInt("comboCount",1));String recipient=m.optString("recipientName");if(!isFree&&LiveGiftExperience.name(kind)!=null&&giftBanner!=null){giftBanner.removeCallbacks(clearGiftBanner);String text="🎁 "+name+" "+I18n.t("đã gửi")+" "+(recipient.isEmpty()?"":recipient+": ")+I18n.t(LiveGiftExperience.name(kind))+(qty>1?" x"+qty:"")+(combo>1?" · Combo x"+combo:"");giftBanner.setText(text);giftBanner.setVisibility(View.VISIBLE);giftBanner.setAlpha(0);giftBanner.animate().alpha(1).setDuration(180).start();giftBanner.postDelayed(clearGiftBanner,3500);}JSONObject ranking=m.optJSONObject("ranking");if(ranking!=null){JSONArray top=ranking.optJSONArray("topSenders");if(top!=null&&top.length()>0){JSONObject leader=top.optJSONObject(0);if(leader!=null)updateTopSender(leader.optString("name"),leader.optLong("coins"));}}showReaction(kind,name,combo,isFree);}
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
    socket.send(NativeSocket.json("type", "join", "multiGuest", true, "liveModes",true,"room", first.optString("id")));
  }

  private int roomIndex(String id) {
    for (int i = 0; lastRooms != null && i < lastRooms.length(); i++) if (lastRooms.optJSONObject(i)!=null && lastRooms.optJSONObject(i).optString("id").equals(id)) return i;
    return -1;
  }

  private int liveEnter;
  private boolean switchLive(final int direction) {
    if (host || liveRole.equals("guest") || previewing || socket==null || !ready || System.currentTimeMillis() - swipeAt < 400 || joining) return false;
    JSONArray available=viewingRooms();int index=-1;for(int i=0;i<available.length();i++)if(available.optJSONObject(i).optString("id").equals(currentRoom))index=i;
    final JSONObject next=available.optJSONObject(index+direction);
    if (index < 0 || next == null) { Toast.makeText(this, direction > 0 ? I18n.t("Bạn đã xem đến buổi live cuối.") : I18n.t("Đây là buổi live đầu tiên."), Toast.LENGTH_SHORT).show(); return false; }
    swipeAt = System.currentTimeMillis();
    joining = true;
    final View stage = liveStage;
    Runnable go = () -> {
      if(isFinishing()||isDestroyed()||socket==null||!ready)return;
      socket.send(NativeSocket.json("type", "leave"));
      if (rtc != null) { rtc.close(); rtc = null; }
      joined = false;
      socket.send(NativeSocket.json("type", "join", "multiGuest", true, "liveModes",true,"room", next.optString("id")));
    };
    liveEnter=direction;if(stage instanceof VerticalMediaStage)((VerticalMediaStage)stage).exit(direction,go);else go.run();return true;
  }

  private void roomEnded() {
    clearPendingGuest();pendingInvitation=null;
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
    t.setBackground(roundStroke(0x88141418, 16, 0x16ffffff));
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
  private void sendLive(String type,Object... values){if(socket==null)return;JSONObject message=NativeSocket.json("type",type);try{for(int i=0;i<values.length;i+=2)message.put(values[i].toString(),values[i+1]);}catch(JSONException ignored){}socket.send(message);}
  private void confirmLeave(){if(host)new Sheet(this).setTitle(I18n.t("Kết thúc Live?")).setPositiveButton(I18n.t("Kết thúc"),(d,w)->{sendLive("leave");finish();}).setNegativeButton(I18n.t("Ở lại"),null).show();else{sendLive("leave");finish();}}
  private void showRoom(JSONObject m){
    String nextMode=m.optJSONObject("room")==null?"chat":m.optJSONObject("room").optString("liveMode","chat");liveMode=nextMode.equals("game")?"game":"chat";
    if(!carryPreview||!host){if(rtc!=null){rtc.close();rtc=null;}localLive=null;}carryPreview=false;liveState=null;liveTray=null;openTray="";guestRequested=false;guestUsers=new JSONArray();guestRequests=new JSONArray();
    liveGuestsSupported=m.optBoolean("multiGuest");roomInfo=m.optJSONObject("room")==null?new JSONObject():m.optJSONObject("room");roomComments=roomInfo.optBoolean("comments",true);screenCover=null;currentRoom=roomInfo.optString("id");liveRole=host?"host":"viewer";
    root.removeAllViews();root.setBackgroundColor(GLIVE_BG);getWindow().setStatusBarColor(GLIVE_BG);getWindow().setNavigationBarColor(GLIVE_BG);getWindow().getDecorView().setSystemUiVisibility(0);
    FrameLayout stage=host?new FrameLayout(this):new ViewerStage();liveStage=stage;root.addView(stage,new LinearLayout.LayoutParams(-1,0,1));if(liveEnter!=0){VerticalMediaStage.enter(stage,liveEnter);liveEnter=0;}
    liveBoard=new LiveBoard();stage.addView(liveBoard,new FrameLayout.LayoutParams(-1,-1));stage.addView(new StoreLiveDecoration(this,roomInfo.optString("liveDecoration")),new FrameLayout.LayoutParams(-1,-1));
    View shade=new View(this);shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x99060608,0x00000000,0x00000000,0xd608080b}));stage.addView(shade,new FrameLayout.LayoutParams(-1,-1));
    reactionLayer=new FrameLayout(this);stage.addView(reactionLayer,new FrameLayout.LayoutParams(-1,-1));
    LinearLayout heading=row();heading.setGravity(Gravity.CENTER_VERTICAL);
    LinearLayout identity=row();identity.setPadding(dp(4),dp(4),dp(11),dp(4));identity.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));
    FrameLayout face=liveAvatar(roomInfo.optString("host",I18n.t("Bạn")),roomInfo.optString("avatar"),30);identity.addView(face,new LinearLayout.LayoutParams(dp(30),dp(30)));
    LinearLayout copy=column();copy.setPadding(dp(8),0,0,0);TextView name=text(roomInfo.optString("host",I18n.t("Bạn")),12,0xffffffff);name.setSingleLine(true);name.setEllipsize(android.text.TextUtils.TruncateAt.END);name.setTypeface(null,Typeface.BOLD);name.setMaxWidth(dp(150));copy.addView(name,new LinearLayout.LayoutParams(-2,-2));
    TextView tag=text("● LIVE · "+I18n.t(modeName(liveMode))+(roomInfo.optString("hostMembership").isEmpty()?"":roomInfo.optString("hostMembership").equals("member_creator")?" · Creator":" · Plus"),8,0xffffffff);tag.setSingleLine(true);tag.setEllipsize(android.text.TextUtils.TruncateAt.END);tag.setTypeface(null,Typeface.BOLD);tag.setPadding(dp(6),dp(1),dp(6),dp(1));tag.setBackground(round(GLIVE_RED,6));copy.addView(tag,new LinearLayout.LayoutParams(-2,-2));identity.addView(copy,new LinearLayout.LayoutParams(-2,-2));heading.addView(identity,new LinearLayout.LayoutParams(-2,-2));heading.addView(new View(this),new LinearLayout.LayoutParams(0,dp(1),1));
    HorizontalScrollView avs=new HorizontalScrollView(this);avs.setHorizontalScrollBarEnabled(false);audience=row();avs.addView(audience);LinearLayout.LayoutParams avp=new LinearLayout.LayoutParams(dp(68),dp(30));avp.leftMargin=dp(6);heading.addView(avs,avp);
    LinearLayout count=row();count.setGravity(Gravity.CENTER);count.setPadding(dp(9),0,dp(9),0);count.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));count.addView(icon("eye",0xfff1f3f4),new LinearLayout.LayoutParams(dp(13),dp(13)));viewers=text(String.valueOf(roomInfo.optInt("viewers")),11,0xfff1f3f4);viewers.setTypeface(null,Typeface.BOLD);viewers.setSingleLine(true);viewers.setIncludeFontPadding(false);viewers.setPadding(dp(4),0,dp(1),0);count.addView(viewers);count.setOnClickListener(v->sendLive("viewers"));LinearLayout.LayoutParams countLp=new LinearLayout.LayoutParams(-2,dp(34));countLp.leftMargin=dp(4);countLp.rightMargin=dp(6);heading.addView(count,countLp);
    heading.addView(liveAction("x",host?"Kết thúc Live":"Rời Live",this::confirmLeave),new LinearLayout.LayoutParams(dp(34),dp(34)));
    FrameLayout.LayoutParams hp=new FrameLayout.LayoutParams(-1,dp(52),Gravity.TOP);hp.setMargins(dp(12),dp(10),dp(12),0);stage.addView(heading,hp);
    if(!roomInfo.optString("title").isEmpty()){TextView title=text(roomInfo.optString("title"),12,0xeeffffff);title.setTypeface(null,Typeface.BOLD);title.setMaxLines(1);title.setEllipsize(android.text.TextUtils.TruncateAt.END);FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);at.setMargins(dp(16),dp(66),dp(16),0);stage.addView(title,at);}topSender=text("",11,0xffeee8cc);topSender.setTypeface(null,Typeface.BOLD);topSender.setPadding(dp(10),dp(5),dp(12),dp(5));topSender.setBackground(roundStroke(0xd8a16207,99,0x66fde68a));android.graphics.drawable.Drawable crownGlyph=WebIcons.load(this,"crown");crownGlyph.setTint(0xffffe08a);crownGlyph.setBounds(0,0,dp(14),dp(14));topSender.setCompoundDrawablesRelative(crownGlyph,null,null,null);topSender.setCompoundDrawablePadding(dp(5));topSender.setVisibility(View.GONE);FrameLayout.LayoutParams tsAt=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.START);tsAt.setMargins(dp(12),dp(108),dp(12),0);stage.addView(topSender,tsAt);
    status=text(I18n.t("Đang kết nối…"),11,0xffe8eaed);status.setGravity(Gravity.CENTER);status.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));status.setPadding(dp(14),dp(8),dp(14),dp(8));FrameLayout.LayoutParams st=new FrameLayout.LayoutParams(-2,-2,host&&liveMode.equals("game")?Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL:Gravity.CENTER);if(host&&liveMode.equals("game"))st.bottomMargin=dp(72);stage.addView(status,st);hideStatus=()->status.setVisibility(View.GONE);
    arrival=text("",11,0xffffffff);arrival.setTypeface(null,Typeface.BOLD);arrival.setPadding(dp(12),dp(6),dp(12),dp(6));arrival.setBackground(roundStroke(GLIVE_PILL,99,0x28ffffff));arrival.setMaxLines(1);arrival.setEllipsize(android.text.TextUtils.TruncateAt.END);arrival.setVisibility(View.GONE);FrameLayout.LayoutParams arrivalAt=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.START);arrivalAt.setMargins(dp(12),0,dp(70),dp(190));stage.addView(arrival,arrivalAt);
    giftBanner=text("",11,0xfffde68a);giftBanner.setTypeface(null,Typeface.BOLD);giftBanner.setPadding(dp(12),dp(6),dp(12),dp(6));giftBanner.setBackground(roundStroke(0xd82e1065,99,0x66f59e0b));giftBanner.setMaxLines(1);giftBanner.setEllipsize(android.text.TextUtils.TruncateAt.END);giftBanner.setVisibility(View.GONE);FrameLayout.LayoutParams giftAt=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.START);giftAt.setMargins(dp(12),0,dp(70),dp(222));stage.addView(giftBanner,giftAt);
    comboButton=text("Combo",12,0xffffffff);android.graphics.drawable.Drawable comboGlyph=WebIcons.load(this,"sparkles");comboGlyph.setTint(0xffffffff);comboGlyph.setBounds(0,0,dp(14),dp(14));comboButton.setCompoundDrawablesRelative(comboGlyph,null,null,null);comboButton.setCompoundDrawablePadding(dp(6));comboButton.setTypeface(null,Typeface.BOLD);comboButton.setGravity(Gravity.CENTER);comboButton.setPadding(dp(14),dp(8),dp(14),dp(8));comboButton.setBackground(roundStroke(0xe67c3aed,99,0x88fde68a));comboButton.setVisibility(View.GONE);FrameLayout.LayoutParams comboAt=new FrameLayout.LayoutParams(-2,dp(38),Gravity.BOTTOM|Gravity.END);comboAt.setMargins(0,0,dp(12),dp(172));stage.addView(comboButton,comboAt);
    chatScroll=new ScrollView(this);chatScroll.setVerticalScrollBarEnabled(false);chatScroll.setVerticalFadingEdgeEnabled(true);chatScroll.setFadingEdgeLength(dp(18));chat=column();chatScroll.addView(chat);FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-1,dp(120),Gravity.BOTTOM);cp.setMargins(dp(12),0,dp(64),dp(74));stage.addView(chatScroll,cp);
    JSONArray history=m.optJSONArray("history");for(int i=0;history!=null&&i<history.length();i++){JSONObject item=history.optJSONObject(i);if(item!=null)addChat(item.optString("name"),item.optString("text"));}
    LinearLayout side=column();liveSide=side;side.setGravity(Gravity.CENTER_HORIZONTAL);side.addView(liveAction("heart","Thả tim",this::sendFreeHeart),new LinearLayout.LayoutParams(dp(46),dp(46)));LinearLayout.LayoutParams gap=new LinearLayout.LayoutParams(dp(46),dp(46));gap.topMargin=dp(10);side.addView(liveAction("send","Chia sẻ",this::shareLive),gap);FrameLayout.LayoutParams sp=new FrameLayout.LayoutParams(dp(46),-2,Gravity.BOTTOM|Gravity.END);sp.setMargins(0,0,dp(12),dp(86));stage.addView(side,sp);
    LinearLayout dock=row();dock.setGravity(Gravity.CENTER_VERTICAL);final EditText input=new KinnectInput(this);input.setHint(I18n.t("Bình luận…"));input.setTextSize(13);input.setTextColor(0xffffffff);input.setHintTextColor(0x99ffffff);input.setSingleLine(true);input.setPadding(dp(14),0,dp(12),0);input.setBackground(roundStroke(GLIVE_PILL,99,0x26ffffff));input.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEND);if(!host&&!roomComments){input.setEnabled(false);input.setHint(I18n.t("Bình luận đã tắt"));input.setAlpha(.55f);}dock.addView(input,new LinearLayout.LayoutParams(0,dp(38),1));input.setOnEditorActionListener((v,a,e)->{String value=input.getText().toString().trim();if(!value.isEmpty()){sendLive("chat","text",value);input.setText("");}return true;});
    FrameLayout guests=liveAction("users_round",host?"Khách mời":"Lên Live",this::openGuests);guestAction=text("",8,0xffffffff);guestAction.setTypeface(null,Typeface.BOLD);guestAction.setGravity(Gravity.CENTER);guestAction.setBackground(round(GLIVE_RED,99));guestAction.setVisibility(View.GONE);FrameLayout.LayoutParams badgeAt=new FrameLayout.LayoutParams(dp(15),dp(15),Gravity.TOP|Gravity.END);guests.addView(guestAction,badgeAt);
    for(FrameLayout action:new FrameLayout[]{guests,liveAction("gift","Tặng quà",this::gifts),liveAction("sliders_horizontal","Công cụ",this::liveTools)}){LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(38),dp(38));lp.leftMargin=dp(6);dock.addView(action,lp);}
    dock.setPadding(dp(6),dp(5),dp(6),dp(5));dock.setBackground(roundStroke(0xcc141418,999,0x26ffffff));FrameLayout.LayoutParams dockLp=new FrameLayout.LayoutParams(-1,dp(56),Gravity.BOTTOM);dockLp.setMargins(dp(10),0,dp(10),dp(10));stage.addView(dock,dockLp);
    if(liveMode.equals("game")){mountGame(stage);}
    audio.setMode(android.media.AudioManager.MODE_IN_COMMUNICATION);audio.setSpeakerphoneOn(true);
    if(!liveGuestsSupported&&config!=null){String publisher=host?socketId:m.optString("host","legacy-host");JSONObject person=NativeSocket.json("id",publisher,"name",roomInfo.optString("host"),"userId",roomInfo.optString("hostId"),"role","host","mode","video");applyLiveStage(NativeSocket.json("room",currentRoom,"selfId",socketId,"role",host?"host":"viewer","revision",0,"layout","panel","participants",new JSONArray().put(person),"peers",new JSONArray()));}
  }
  private FrameLayout liveAvatar(String name,String path,int size){FrameLayout frame=new FrameLayout(this);frame.setBackground(roundStroke(GLIVE_BTN,99,0x33ffffff));frame.setClipToOutline(true);TextView initial=text(name.isEmpty()?"K":name.substring(0,1).toUpperCase(),Math.max(10,size/3),0xffffffff);initial.setTypeface(null,Typeface.BOLD);initial.setGravity(Gravity.CENTER);frame.addView(initial,new FrameLayout.LayoutParams(-1,-1));if(path.startsWith("/api/users/"))NativeApi.shared.image(path,bytes->{if(isDestroyed()||bytes==null)return;android.graphics.Bitmap bitmap=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(bitmap!=null){ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setImageBitmap(bitmap);frame.addView(image,new FrameLayout.LayoutParams(-1,-1));}});return frame;}
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
    if(publishing&&pendingGuestRtc!=null){rtc=pendingGuestRtc;localLive=pendingGuestLocal;pendingGuestRtc=null;pendingGuestLocal=null;}
    liveBoard.removeAllViews();liveBoard.layout=state.optString("layout","panel");if(rtc==null){localLive=publishing?new SurfaceViewRenderer(this):null;rtc=new NativeRtc(this,config,localLive,null,new NativeRtc.Events(){public void status(String value){status.setText(value);status.setVisibility(View.VISIBLE);status.removeCallbacks(hideStatus);status.postDelayed(hideStatus,2500);}public void signal(String peer,JSONObject value){try{value.put("type","signal");value.put("to",peer);if(liveState!=null)value.put("revision",liveState.optInt("revision"));socket.send(value);}catch(JSONException ignored){}}},false);if(publishing)try{rtc.media(this,!state.optString("mode").equals("audio"));rtc.microphone(host?pendingHostMic:true);liveMic=host?pendingHostMic:true;liveCam=true;if(previewLook!=null&&rtc.effects()!=null){LiveEffects fx=rtc.effects();fx.filter=previewLook.filter;fx.sticker=previewLook.sticker;fx.beautyOn=previewLook.beautyOn;fx.smooth=previewLook.smooth;fx.blemish=previewLook.blemish;fx.eyes=previewLook.eyes;fx.lips=previewLook.lips;previewLook=null;}}catch(Exception error){liveToast("Không mở được camera/micro.");if(host){sendLive("leave");finish();}else sendLive("live-guest-leave");return;}}
    rtc.events(new NativeRtc.Events(){public void status(String value){status.setText(value);status.setVisibility(View.VISIBLE);status.removeCallbacks(hideStatus);status.postDelayed(hideStatus,2500);}public void signal(String peer,JSONObject value){try{value.put("type","signal");value.put("to",peer);if(liveState!=null)value.put("revision",liveState.optInt("revision"));socket.send(value);}catch(JSONException ignored){}}});
    JSONArray people=state.optJSONArray("participants");if(giftExperience!=null)giftExperience.setTargets(people,roomInfo.optString("hostId"),roomInfo.optString("host"));for(int i=0;people!=null&&i<people.length();i++){JSONObject person=people.optJSONObject(i);if(person==null)continue;FrameLayout tile=new FrameLayout(this);tile.setBackground(roundStroke(GLIVE_SURFACE,18,0x22ffffff));tile.setClipToOutline(true);String id=person.optString("id");boolean self=id.equals(state.optString("selfId"));boolean video=!person.optString("mode").equals("audio");if(video){SurfaceViewRenderer display=self?localLive:new SurfaceViewRenderer(this);if(display!=null){if(display.getParent()instanceof ViewGroup)((ViewGroup)display.getParent()).removeView(display);tile.addView(display,new FrameLayout.LayoutParams(-1,-1));if(!self)rtc.bindLive(id,display);}}else{FrameLayout avatar=liveAvatar(person.optString("name"),person.optString("avatar"),56);tile.addView(avatar,new FrameLayout.LayoutParams(dp(56),dp(56),Gravity.CENTER));}
      TextView label=text(person.optString("name")+(self?" · "+I18n.t("Bạn"):""),10,0xffffffff);label.setTypeface(null,Typeface.BOLD);label.setSingleLine(true);label.setEllipsize(android.text.TextUtils.TruncateAt.END);label.setPadding(dp(8),dp(4),dp(8),dp(4));label.setBackground(roundStroke(GLIVE_PILL,99,0x22ffffff));FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.START);lp.setMargins(dp(8),0,dp(8),dp(8));tile.addView(label,lp);liveBoard.addView(tile);}
    rtc.playback(!livePlaybackMuted);liveBoard.requestLayout();JSONArray peers=state.optJSONArray("peers");for(int i=0;peers!=null&&i<peers.length();i++){JSONObject peer=peers.optJSONObject(i);if(peer!=null&&peer.optBoolean("offer"))rtc.offer(peer.optString("id"));}status.setVisibility(View.GONE);
  }
  private void shareLive(){try{startActivity(android.content.Intent.createChooser(new android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT,ServerConfig.DEFAULT_ORIGIN+"/?s=live&room="+currentRoom),I18n.t("Chia sẻ buổi live")));}catch(Exception ignored){}}
  private HorizontalScrollView liveTray;private String openTray="";
  private void liveTools(){toggleLiveTray("tools");}
  private void requestGiftRanking(){rankingRequested=true;if(socket!=null&&joined)sendLive("live-gift-ranking");else showGiftRanking(roomRanking!=null?roomRanking:new JSONObject());}
  private void showGiftRanking(JSONObject data){if(data==null)data=new JSONObject();CommerceUi ui=new CommerceUi(this);LinearLayout body=ui.col();body.setPadding(ui.dp(4),0,ui.dp(4),ui.dp(8));JSONObject goal=data.optJSONObject("goal");if(goal!=null){LinearLayout gbox=ui.section();gbox.addView(ui.text(goal.optString("title",I18n.t("Mục tiêu quà Live")),15,ui.ink,true));ui.add(gbox,ui.text(goal.optLong("progressCoins")+" / "+goal.optLong("targetCoins")+" "+I18n.t("xu"),13,ui.purple,true),4);ui.add(body,gbox,8);}if(host){ui.add(body,ui.action(goal!=null?"Đổi mục tiêu quà":"Đặt mục tiêu quà","crown",()->{EditText t=field(I18n.t("Số xu mục tiêu (50 - 100000)"));t.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);new Sheet(this).setTitle(I18n.t("Mục tiêu quà Live")).setView(t).setPositiveButton(I18n.t("Lưu"),(d,w)->{long target=0;try{target=Long.parseLong(t.getText().toString().trim());}catch(Exception ignored){}sendLive("live-gift-goal","title",I18n.t("Mục tiêu quà Live"),"targetCoins",target);}).setNeutralButton(I18n.t("Xóa"),(d,w)->sendLive("live-gift-goal","targetCoins",0)).setNegativeButton(I18n.t("Hủy"),null).show();}),8);}ui.add(body,ui.text(I18n.t("Tổng quà trong phòng")+": "+data.optLong("totalGifts")+" · "+data.optLong("totalCoins")+" "+I18n.t("xu"),13,ui.muted,false),10);JSONArray top=data.optJSONArray("topSenders");if(top==null||top.length()==0)ui.add(body,ui.empty("gift","Chưa có quà trong phòng"),12);else for(int i=0;i<top.length();i++){JSONObject s=top.optJSONObject(i);if(s==null)continue;LinearLayout row=ui.row();row.setPadding(0,ui.dp(8),0,ui.dp(8));row.addView(ui.badge("#"+(i+1)));TextView n=ui.text(s.optString("name"),14,ui.ink,true);n.setPadding(ui.dp(10),0,ui.dp(8),0);row.addView(n,new LinearLayout.LayoutParams(0,-2,1));row.addView(ui.text(s.optLong("coins")+" "+I18n.t("xu"),13,ui.purple,true));body.addView(row);}ScrollView sc=new ScrollView(this);sc.addView(body);new Sheet(this).setTitle(I18n.t("Bảng quà Live")).setView(sc).setNegativeButton(I18n.t("Đóng"),null).show();}
  private void toggleLiveTray(String value){if(liveStage==null)return;if(liveTray!=null){liveStage.removeView(liveTray);liveTray=null;}if(openTray.equals(value)){openTray="";if(chatScroll!=null)chatScroll.setVisibility(View.VISIBLE);if(liveSide!=null)liveSide.setVisibility(View.VISIBLE);return;}openTray=value;if(chatScroll!=null)chatScroll.setVisibility(View.INVISIBLE);if(liveSide!=null)liveSide.setVisibility(View.INVISIBLE);if(arrival!=null)arrival.setVisibility(View.GONE);android.view.inputmethod.InputMethodManager keyboard=(android.view.inputmethod.InputMethodManager)getSystemService(INPUT_METHOD_SERVICE);keyboard.hideSoftInputFromWindow(root.getWindowToken(),0);liveTray=new HorizontalScrollView(this);liveTray.setHorizontalScrollBarEnabled(false);liveTray.setBackground(roundStroke(0xf018181d,20,0x26ffffff));LinearLayout items=row();items.setPadding(dp(8),dp(6),dp(8),dp(6));liveTray.addView(items);
    {if(host&&liveMode.equals("game")){trayTool(items,"gamepad","Tạm che",this::toggleScreenPause);trayTool(items,"monitor","Mở game",this::openGameApp);}if(!liveRole.equals("viewer")){trayTool(items,liveMic?"mic":"mic",liveMic?"Tắt mic":"Bật mic",()->{liveMic=!liveMic;rtc.microphone(liveMic);refreshTools();});if(!liveMode.equals("game")&&(host||liveState==null||!liveState.optString("mode").equals("audio"))){trayTool(items,liveCam?"camera":"camera_off",liveCam?"Tắt camera":"Bật camera",()->{liveCam=!liveCam;rtc.camera(liveCam);refreshTools();});trayTool(items,"switch_camera","Đổi camera",()->rtc.flip());trayTool(items,"sparkles","Hiệu ứng",this::effectsMenu);}}if(host){trayTool(items,"grid","Lưới",()->sendLive("live-layout","layout","grid"));trayTool(items,"users_round","Chủ phòng lớn",()->sendLive("live-layout","layout","panel"));}else{trayTool(items,"flag","Báo cáo",this::reportLive);trayTool(items,"shield_check","Chặn",this::blockLive);trayTool(items,"user_plus",roomInfo.optBoolean("following")?"Bỏ theo dõi":"Theo dõi",this::followLive);trayTool(items,"volume_2",livePlaybackMuted?"Bật tiếng":"Tắt tiếng",()->{livePlaybackMuted=!livePlaybackMuted;if(rtc!=null)rtc.playback(!livePlaybackMuted);refreshTools();});}trayTool(items,"crown","Bảng quà",this::requestGiftRanking);trayTool(items,"send","Chia sẻ",this::shareLive);}
    FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-1,dp(82),Gravity.BOTTOM);at.setMargins(dp(12),0,dp(12),dp(60));liveStage.addView(liveTray,at);liveTray.setAlpha(0);liveTray.setTranslationY(dp(12));liveTray.animate().alpha(1).translationY(0).setDuration(180).start();
  }
  private void refreshTools(){openTray="";toggleLiveTray("tools");}
  private void trayTool(LinearLayout row,String glyph,String name,Runnable action){LinearLayout tile=column();tile.setGravity(Gravity.CENTER);FrameLayout circle=new FrameLayout(this);circle.setBackground(round(GLIVE_BTN,99));circle.addView(icon(glyph,0xfff1f3f4),new FrameLayout.LayoutParams(dp(18),dp(18),Gravity.CENTER));tile.addView(circle,new LinearLayout.LayoutParams(dp(34),dp(34)));TextView label=text(I18n.t(name),10,0xffe8eaed);label.setGravity(Gravity.CENTER);label.setMaxLines(2);label.setEllipsize(android.text.TextUtils.TruncateAt.END);label.setPadding(dp(2),dp(4),dp(2),0);tile.addView(label,new LinearLayout.LayoutParams(-1,-2));tile.setContentDescription(I18n.t(name));tile.setOnClickListener(v->action.run());row.addView(tile,new LinearLayout.LayoutParams(dp(64),dp(68)));}
  private void blockLive(){new Sheet(this).setTitle(I18n.t("Chặn người phát?")).setPositiveButton(I18n.t("Chặn"),(d,w)->NativeApi.shared.call("POST","/api/users/"+roomInfo.optString("hostId")+"/block",new JSONObject(),(data,error,code)->{if(error==null)finish();else liveToast(error);})).setNegativeButton(I18n.t("Hủy"),null).show();}
  private void followLive(){boolean following=roomInfo.optBoolean("following");NativeApi.shared.call(following?"DELETE":"POST","/api/users/"+roomInfo.optString("hostId")+"/follow",new JSONObject(),(data,error,code)->{if(isDestroyed())return;if(error!=null){liveToast(error);return;}try{roomInfo.put("following",!following);}catch(JSONException ignored){}refreshTools();});}
  private void reportLive(){EditText reason=field(I18n.t("Mô tả vi phạm; không gửi lại ảnh CSAM"));new Sheet(this).setTitle(I18n.t("Báo cáo buổi live")).setView(reason).setPositiveButton(I18n.t("Gửi báo cáo"),(d,w)->{String value=reason.getText().toString().trim();if(value.length()<5){liveToast("Mô tả ít nhất 5 ký tự.");return;}NativeApi.shared.call("POST","/api/reports",NativeSocket.json("targetType","user","targetId",roomInfo.optString("hostId"),"reason","[Live "+currentRoom+"] "+value),(data,error,code)->liveToast(error==null?"Đã gửi báo cáo.":error));}).setNegativeButton(I18n.t("Hủy"),null).show();}
  private void openGuests(){if(!liveGuestsSupported){liveToast("Cần cập nhật máy chủ để dùng khách mời.");return;}if(host){sendLive("live-guest-list");return;}if(liveRole.equals("guest")){new Sheet(this).setTitle(I18n.t("Bạn đang lên Live")).setItemIcons(new String[]{"log_out"}).setItems(new String[]{I18n.t("Rời ghế khách")},(d,n)->sendLive("live-guest-leave")).show();return;}if(guestRequested){new Sheet(this).setTitle(I18n.t("Đang chờ chủ phòng duyệt")).setPositiveButton(I18n.t("Hủy yêu cầu"),(d,w)->sendLive("live-guest-cancel")).setNegativeButton(I18n.t("Đóng"),null).show();return;}new Sheet(this).setTitle(I18n.t("Xin lên Live")).setMessage(I18n.t("Camera và micro chỉ bật sau khi bạn đồng ý lên Live.")).setItemIcons(new String[]{"video","mic"}).setItems(new String[]{I18n.t("Tham gia bằng video"),I18n.t("Chỉ âm thanh")},(d,n)->sendLive("live-guest-request","mode",n==0?"video":"audio")).show();}
  private void guestManagement(){if(!host)return;if(guestSheet!=null)guestSheet.dismiss();LinearLayout body=column();body.setPadding(dp(4),0,dp(4),0);TextView hint=text(I18n.t("Mời người đang xem · Tối đa 3 khách"),12,MUTED);hint.setGravity(Gravity.CENTER);body.addView(hint);for(int i=0;i<guestRequests.length();i++){JSONObject u=guestRequests.optJSONObject(i);if(u!=null)guestRow(body,u,true);}for(int i=0;i<guestUsers.length();i++){JSONObject u=guestUsers.optJSONObject(i);if(u!=null)guestRow(body,u,false);}if(guestUsers.length()==0&&guestRequests.length()==0){TextView empty=text(I18n.t("Chưa có người xem để mời"),14,MUTED);empty.setPadding(dp(8),dp(24),dp(8),dp(24));empty.setGravity(Gravity.CENTER);body.addView(empty);}ScrollView scroll=new ScrollView(this);scroll.addView(body);guestSheet=new Sheet(this).setTitle(I18n.t("Khách mời")).setView(scroll).setNegativeButton(I18n.t("Đóng"),null).show();}
  private void guestRow(LinearLayout body,JSONObject u,boolean request){LinearLayout line=row();line.setPadding(0,dp(8),0,dp(8));line.addView(liveAvatar(u.optString("name"),u.optString("avatar"),36),new LinearLayout.LayoutParams(dp(36),dp(36)));TextView name=text(u.optString("name"),13,TEXT);name.setMaxLines(2);name.setPadding(dp(8),0,dp(4),0);line.addView(name,new LinearLayout.LayoutParams(0,-2,1));String label=request?"Duyệt":u.optBoolean("onStage")?"Gỡ":"Mời";TextView action=pill(I18n.t(label),true,()->{sendLive(request?"live-guest-approve":u.optBoolean("onStage")?"live-guest-remove":"live-guest-invite","to",u.optString("id"));if(guestSheet!=null)guestSheet.dismiss();});action.setTextSize(12);line.addView(action,new LinearLayout.LayoutParams(dp(66),dp(36)));if(request){TextView no=text("×",24,MUTED);no.setGravity(Gravity.CENTER);no.setContentDescription(I18n.t("Từ chối"));no.setOnClickListener(v->{sendLive("live-guest-decline","to",u.optString("id"));if(guestSheet!=null)guestSheet.dismiss();});line.addView(no,new LinearLayout.LayoutParams(dp(36),dp(36)));}body.addView(line);}
  private void invitation(JSONObject message){if(!currentRoom.equals(message.optString("room")))return;pendingInvitation=message;if(invitationSheet!=null)invitationSheet.dismiss();invitationSheet=new Sheet(this).setTitle(I18n.t("Mời lên Live")).setMessage(message.optJSONObject("from").optString("name")+" · "+I18n.t("Mời bạn trò chuyện cùng")).setItemIcons(new String[]{"video","mic"}).setItems(new String[]{I18n.t("Tham gia bằng video"),I18n.t("Chỉ âm thanh")},(d,n)->{inviteMode=n==0?"video":"audio";acceptGuest();}).setNegativeButton(I18n.t("Từ chối"),(d,w)->{if(pendingInvitation!=null)sendLive("live-guest-answer","token",pendingInvitation.optString("token"),"accept",false);pendingInvitation=null;}).show();}
  private void clearPendingGuest(){if(pendingGuestRtc!=null){pendingGuestRtc.close();pendingGuestRtc=null;pendingGuestLocal=null;}}
  private void acceptGuest(){if(!joined||socket==null||!ready){clearPendingGuest();return;}if(pendingInvitation==null||pendingInvitation.optLong("expiresAt")<System.currentTimeMillis()){pendingInvitation=null;liveToast("Lời mời đã hết hạn.");return;}if(checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED||inviteMode.equals("video")&&checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){requestPermissions(inviteMode.equals("video")?new String[]{Manifest.permission.CAMERA,Manifest.permission.RECORD_AUDIO}:new String[]{Manifest.permission.RECORD_AUDIO},302);return;}try{clearPendingGuest();pendingGuestLocal=new SurfaceViewRenderer(this);pendingGuestRtc=new NativeRtc(this,config,pendingGuestLocal,null,new NativeRtc.Events(){public void signal(String peer,JSONObject value){}public void status(String value){}},false);pendingGuestRtc.media(this,inviteMode.equals("video"));}catch(Exception error){clearPendingGuest();sendLive("live-guest-answer","token",pendingInvitation.optString("token"),"accept",false);pendingInvitation=null;liveToast("Không mở được camera/micro.");return;}sendLive("live-guest-answer","token",pendingInvitation.optString("token"),"accept",true,"mode",inviteMode);pendingInvitation=null;}

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
    stopGameSession();ready = false;clearPendingGuest();pendingInvitation=null;
    status.setText(I18n.t("Đã mất kết nối. Hãy mở lại mục Trực tiếp."));
    status.setVisibility(View.VISIBLE);
    if (rtc != null) { rtc.close(); rtc = null; }
  }

  protected void onStop() { super.onStop();if(gameSession){gameControllerVisible=false;syncGameVisibility();}if(giftExperience!=null)giftExperience.stopVisuals();if(gameSession&&gameService!=null&&gameComments)gameService.overlayVisible(true); if ((joined || previewing) && !gameSession&&gameConnection==null&&!projectionPrompt&&!externalPicker&&!isChangingConfigurations()) finish(); }
  @Override protected void onResume(){super.onResume();gameControllerVisible=true;syncGameVisibility();externalPicker=false;if(gameService!=null)gameService.overlayVisible(false);if(getIntent().getBooleanExtra("show_gifts",false))root.postDelayed(this::gifts,800);}
  @Override public void onBackPressed(){if(joined){confirmLeave();return;}super.onBackPressed();}

  protected void onDestroy() {
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
    LinearLayout body=new LinearLayout(this);body.setOrientation(LinearLayout.VERTICAL);
    LinearLayout tabs=new LinearLayout(this);FrameLayout host=new FrameLayout(this);android.widget.ScrollView scroll=new android.widget.ScrollView(this);scroll.addView(host);
    Runnable changed=()->{};
    EffectControls.Target target=EffectControls.forLive(fx);
    for(String[] tab:new String[][]{{"beauty","Làm đẹp"},{"sticker","Hiệu ứng"},{"filter","Màu"}}){TextView button=new KinnectText(this);button.setText(I18n.t(tab[1]));android.graphics.drawable.Drawable tabIcon=EditorIcons.drawable(this,tab[0],WebTheme.isDark(this)?0xffc7b5ff:0xff7652dc);if(tabIcon!=null){tabIcon.setBounds(0,0,dp(20),dp(20));button.setCompoundDrawables(null,tabIcon,null,null);button.setCompoundDrawablePadding(dp(5));}button.setTextSize(12);button.setGravity(Gravity.CENTER);button.setPadding(0,dp(14),0,dp(14));button.setTextColor(WebTheme.isDark(this)?0xfff6f1ff:0xff271f38);button.setOnClickListener(v->{host.removeAllViews();host.addView(EffectControls.panel(this,tab[0],target,changed));});tabs.addView(button,new LinearLayout.LayoutParams(0,-2,1));}
    body.addView(tabs);body.addView(scroll,new LinearLayout.LayoutParams(-1,Math.min(dp(360),getResources().getDisplayMetrics().heightPixels/2)));host.addView(EffectControls.panel(this,"beauty",target,changed));
    new Sheet(this).setTitle(I18n.t("Hiệu ứng Live")).setView(body).setPositiveButton("Xong",null).show();
  }
}
