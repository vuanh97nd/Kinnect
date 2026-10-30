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
  private boolean cameraSetup,setupStarted;private boolean creationEntry;private String liveMode="chat",gameTitle="";private boolean choosingMode,externalPicker,projectionPrompt,gameSound=true,screenPaused,gameSession;
  private LiveGameService gameService;private ServiceConnection gameConnection;private View screenCover;
  private TextView modeLabel(String mode){return text(I18n.t(modeName(mode)),12,0xffffffff);}
  private String modeName(String mode){return mode.equals("game")?"Chơi game":"Trò chuyện";}
  private String modeIcon(String mode){return mode.equals("game")?"gamepad":"video";}
  private void chooseMode(){if(!cameraSetup){startActivity(new Intent(this,StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE,"live"));finish();return;}creationEntry=true;if(ready)prepareHost();else preparationWaiting();}
  private LinearLayout preparationModes(EditText title){LinearLayout modes=row();modes.setTag("live:preparation-modes");modes.setPadding(dp(4),dp(6),dp(4),dp(6));for(String mode:new String[]{"chat","game"}){TextView chip=text(I18n.t(modeName(mode)),13,mode.equals(liveMode)?0xffffffff:0xffd8cbed);chip.setGravity(Gravity.CENTER);chip.setMinHeight(dp(48));chip.setPadding(dp(8),dp(8),dp(8),dp(8));chip.setBackground(round(mode.equals(liveMode)?ACCENT:0xff302a3d,14));android.graphics.drawable.Drawable d=WebIcons.load(this,modeIcon(mode));d.setTint(chip.getCurrentTextColor());d.setBounds(0,0,dp(20),dp(20));chip.setCompoundDrawables(null,d,null,null);chip.setCompoundDrawablePadding(dp(6));chip.setOnClickListener(v->{if(mode.equals(liveMode)||joining||gameSession||projectionPrompt)return;if(title!=null)topicText=title.getText().toString().trim();liveMode=mode;previewing=false;if(rtc!=null){rtc.close();rtc=null;}if(ready)prepareHost();else preparationWaiting();});LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(0,-2,1);at.setMargins(dp(4),0,dp(4),0);modes.addView(chip,at);}return modes;}
  private void preparationWaiting(){root.removeAllViews();rooms=null;root.setBackgroundColor(0xff111017);LinearLayout bar=row();bar.addView(liveAction("x","Thoát",this::finish),new LinearLayout.LayoutParams(dp(48),dp(48)));TextView title=text(I18n.t("Chuẩn bị Live"),18,0xffffffff);title.setPadding(dp(10),0,0,0);bar.addView(title);root.addView(bar);if(!cameraSetup)root.addView(preparationModes(null));status=text(I18n.t("Đang kết nối…"),14,0xffd8cbed);status.setGravity(Gravity.CENTER);root.addView(status,new LinearLayout.LayoutParams(-1,0,1));}
  private void createHostRoom(){if(socket==null||!ready||joining||joined)return;previewing=false;host=true;joining=true;sendLive("create","multiGuest",true,"liveModes",true,"liveMode",liveMode,"gameTitle",gameTitle,"title",topicText);}

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
    EditText e = new KinnectInput(this);
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
    root.setOnApplyWindowInsetsListener((v, i) -> { if(Build.VERSION.SDK_INT>=30){android.graphics.Insets bars=i.getInsets(android.view.WindowInsets.Type.systemBars());android.graphics.Insets keyboard=i.getInsets(android.view.WindowInsets.Type.ime());v.setPadding(bars.left,bars.top,bars.right,Math.max(bars.bottom,keyboard.bottom));}else v.setPadding(0,i.getSystemWindowInsetTop(),0,i.getSystemWindowInsetBottom()); return i; });
    setContentView(root);
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

  private void askTitleAndHost() { chooseMode(); }

  private String topicText = "";

  private JSONArray viewingRooms(){return lastRooms==null?new JSONArray():lastRooms;}
  private void renderRooms() {
    if (rooms == null) return;
    rooms.removeAllViews();
    if(!ready){status.setText(I18n.t("Đang kết nối…"));status.setVisibility(View.VISIBLE);return;}
    int count=0;for(int i=0;lastRooms!=null&&i<lastRooms.length();i++){JSONObject room=lastRooms.optJSONObject(i);if(room==null)continue;count++;LinearLayout tile=row();tile.setPadding(dp(14),dp(14),dp(14),dp(14));tile.setBackground(round(CARD,18));tile.addView(icon(modeIcon(room.optString("liveMode","chat")),ACCENT),new LinearLayout.LayoutParams(dp(30),dp(30)));LinearLayout copy=column();copy.setPadding(dp(12),0,0,0);TextView title=text(room.optString("title").isEmpty()?room.optString("host"):room.optString("title"),15,TEXT);title.setMaxLines(2);copy.addView(title);copy.addView(text(I18n.t(modeName(room.optString("liveMode","chat")))+" · "+room.optString("host")+" · "+room.optInt("viewers")+" "+I18n.t("người xem"),11,MUTED));tile.addView(copy,new LinearLayout.LayoutParams(0,-2,1));tile.setOnClickListener(v->{if(!joining&&ready){joining=true;sendLive("join","room",room.optString("id"),"multiGuest",true,"liveModes",true);}});LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(-1,-2);at.bottomMargin=dp(10);rooms.addView(tile,at);}
    status.setVisibility(View.GONE);if(count>0)return;
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
  @Override public void startActivityForResult(Intent intent,int request){if(request==321||request==322)externalPicker=true;super.startActivityForResult(intent,request);}
  private TextView previewBadge(){
    TextView badge=text(I18n.t("Xem trước · Chưa phát sóng"),12,0xffffffff);
    badge.setGravity(Gravity.CENTER);badge.setSingleLine(false);badge.setMinHeight(dp(36));
    badge.setPadding(dp(12),dp(8),dp(12),dp(8));badge.setBackground(round(0x88000000,18));
    return badge;
  }
  private void showHostPreview(){
    if(previewing||joined)return;if(liveMode.equals("game")){showGamePreview();return;}previewing=true;host=false;if(rtc!=null){rtc.close();rtc=null;}
    root.removeAllViews();root.setBackgroundColor(0xff111017);FrameLayout stage=new FrameLayout(this);root.addView(stage,new LinearLayout.LayoutParams(-1,0,1));SurfaceViewRenderer display=new SurfaceViewRenderer(this);localLive=display;stage.addView(display,new FrameLayout.LayoutParams(-1,-1));
    TextView close=text(I18n.t("×"),30,0xffffffff);close.setGravity(Gravity.CENTER);close.setBackground(round(0x88000000,99));close.setContentDescription(I18n.t("Đóng camera chuẩn bị Live"));close.setOnClickListener(v->finish());FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.TOP|Gravity.START);cp.setMargins(dp(12),dp(8),0,0);stage.addView(close,cp);
    TextView badge=previewBadge();FrameLayout.LayoutParams bp=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);bp.setMargins(dp(64),dp(16),dp(64),0);stage.addView(badge,bp);
    LinearLayout controls=column();controls.setPadding(dp(16),dp(10),dp(16),dp(16));controls.setBackgroundColor(0xff18151f);root.addView(controls,new LinearLayout.LayoutParams(-1,-2));
    EditText title=field(I18n.t("Tiêu đề buổi Live"));title.setText(topicText);title.setTextColor(0xffffffff);title.setHintTextColor(0xffaaa3b7);title.setBackground(round(0xff302a3d,14));title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});controls.addView(title,new LinearLayout.LayoutParams(-1,dp(48)));
    controls.addView(preparationModes(title));
    LinearLayout actions=row();final boolean[] mic={true};actions.addView(sideButton("flip",I18n.t("Lật camera"),()->{if(rtc!=null)rtc.flip();}),new LinearLayout.LayoutParams(0,-2,1));actions.addView(sideButton("wand",I18n.t("Làm đẹp"),this::effectsMenu),new LinearLayout.LayoutParams(0,-2,1));actions.addView(sideButton("mic","Micro",()->{mic[0]=!mic[0];badge.setText(mic[0]?I18n.t("Xem trước · Mic sẽ bật khi phát"):I18n.t("Xem trước · Mic sẽ tắt khi phát"));}),new LinearLayout.LayoutParams(0,-2,1));controls.addView(actions);
    TextView start=pill(I18n.t("Bắt đầu Live"),true,()->{});start.setEnabled(false);start.setAlpha(.45f);controls.addView(start,new LinearLayout.LayoutParams(-1,dp(52)));status=text(I18n.t("Đang mở camera…"),12,0xffc9bfd7);status.setGravity(Gravity.CENTER);status.setPadding(0,dp(10),0,dp(4));controls.addView(status,new LinearLayout.LayoutParams(-1,-2));
    try{rtc=new NativeRtc(this,config,display,null,new NativeRtc.Events(){public void signal(String peer,JSONObject payload){}public void status(String text){status.setText(text);}},false);final NativeRtc previewRtc=rtc;display.addFrameListener(new org.webrtc.EglRenderer.FrameListener(){private boolean received;public void onFrame(android.graphics.Bitmap bitmap){if(bitmap!=null)bitmap.recycle();if(received)return;received=true;runOnUiThread(()->{if(!previewing||rtc!=previewRtc||isFinishing()||isDestroyed())return;status.setText(I18n.t("Camera đã sẵn sàng · Chưa phát sóng"));start.setEnabled(true);start.setAlpha(1);});}},0f);rtc.media(this,true);rtc.microphone(false);start.setOnClickListener(v->{if(!previewing||!ready||joining)return;topicText=title.getText().toString().trim();start.setEnabled(false);previewLook=rtc.effects();carryPreview=true;pendingHostMic=mic[0];rtc.microphone(pendingHostMic);createHostRoom();});}
    catch(Exception error){if(rtc!=null){rtc.close();rtc=null;}status.setText(I18n.t("Không mở được camera. Kiểm tra quyền camera/micro rồi mở lại."));}
  }
  private LiveGamePicker gamePicker;private boolean gameComments=true;private boolean pendingHostMic=true;
  private void showGamePreview(){
    previewing=true;host=false;if(rtc!=null){rtc.close();rtc=null;}root.removeAllViews();root.setBackgroundColor(BG);
    ScrollView scroll=new ScrollView(this);LinearLayout body=column();body.setPadding(dp(20),dp(16),dp(20),dp(24));scroll.addView(body);root.addView(scroll,new LinearLayout.LayoutParams(-1,-1));
    ImageView back=icon("x",TEXT);back.setPadding(dp(10),dp(10),dp(10),dp(10));back.setContentDescription(I18n.t("Thoát"));back.setBackground(round(SOFT,99));back.setOnClickListener(v->finish());body.addView(back,new LinearLayout.LayoutParams(dp(44),dp(44)));
    ImageView game=icon("gamepad",ACCENT);LinearLayout.LayoutParams art=new LinearLayout.LayoutParams(dp(60),dp(60));art.gravity=Gravity.CENTER;art.setMargins(0,dp(28),0,dp(18));body.addView(game,art);
    TextView heading=text(I18n.t("Chơi game trực tiếp"),22,TEXT);heading.setTypeface(null,Typeface.BOLD);body.addView(heading);
    TextView hint=text(I18n.t("Chọn một ứng dụng game trong hộp thoại Android. Màn hình chỉ được phát sau khi bạn đồng ý."),14,MUTED);hint.setPadding(0,dp(12),0,dp(18));body.addView(hint);
    EditText title=field(I18n.t("Tiêu đề buổi Live"));title.setText(topicText);title.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(80)});body.addView(title,new LinearLayout.LayoutParams(-1,dp(50)));body.addView(preparationModes(title));
    EditText name=field(I18n.t("Chọn game"));name.setText(gameTitle);name.setFocusable(false);name.setCursorVisible(false);name.setKeyListener(null);name.setFocusable(false);name.setFocusableInTouchMode(false);name.setShowSoftInputOnFocus(false);name.setContentDescription(I18n.t("Chọn game"));name.setOnClickListener(v->{if(gamePicker!=null)gamePicker.close();gamePicker=new LiveGamePicker(this,gameTitle,value->{gameTitle=value;name.setText(value);});gamePicker.show();});name.setFilters(new android.text.InputFilter[]{new android.text.InputFilter.LengthFilter(60)});LinearLayout.LayoutParams np=new LinearLayout.LayoutParams(-1,dp(50));np.topMargin=dp(12);body.addView(name,np);
    CheckBox mic=new CheckBox(this);mic.setTypeface(ApprovedTypography.font(this,0));mic.setTextColor(TEXT);mic.setText(I18n.t("Bật micro bình luận"));mic.setChecked(pendingHostMic);body.addView(mic);
    CheckBox sound=new CheckBox(this);sound.setTypeface(ApprovedTypography.font(this,0));sound.setTextColor(TEXT);sound.setText(I18n.t("Phát tiếng game nếu được ứng dụng cho phép"));sound.setChecked(gameSound&&Build.VERSION.SDK_INT>=29);sound.setEnabled(Build.VERSION.SDK_INT>=29);body.addView(sound);
    CheckBox comments=new CheckBox(this);comments.setTypeface(ApprovedTypography.font(this,0));comments.setTextColor(TEXT);comments.setText(I18n.t("Bình luận nổi khi chơi game"));comments.setChecked(gameComments);comments.setOnCheckedChangeListener((b,on)->gameComments=on);body.addView(comments);
    TextView privacy=text(I18n.t("Nên chọn chia sẻ một ứng dụng và bật Không làm phiền. Khi chia sẻ toàn màn hình, nội dung và thông báo khác có thể xuất hiện."),12,MUTED);privacy.setPadding(0,dp(12),0,dp(16));body.addView(privacy);
    TextView start=pill(I18n.t("Chọn màn hình & Bắt đầu Live"),true,()->{topicText=title.getText().toString().trim();gameTitle=name.getText().toString().trim();pendingHostMic=mic.isChecked();gameSound=sound.isChecked();requestGameProjection();});start.setMinHeight(dp(56));start.setPadding(dp(12),dp(12),dp(12),dp(12));body.addView(start,new LinearLayout.LayoutParams(-1,-2));
    status=text(I18n.t("Chưa phát sóng · Camera không bật"),12,MUTED);status.setPadding(0,dp(16),0,0);body.addView(status);
  }
  private void requestGameProjection(){if(projectionPrompt||gameSession||joining||!ready)return;if(gameComments&&!android.provider.Settings.canDrawOverlays(this)){projectionPrompt=true;try{startActivityForResult(new Intent(android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,android.net.Uri.parse("package:"+getPackageName())),324);}catch(Exception e){projectionPrompt=false;gameComments=false;liveToast("Chưa bật bình luận nổi; vẫn có thể phát game.");if(cameraSetup)requestGameProjection();}return;}projectionPrompt=true;try{MediaProjectionManager manager=(MediaProjectionManager)getSystemService(MEDIA_PROJECTION_SERVICE);Intent capture=cameraSetup&&Build.VERSION.SDK_INT>=34?manager.createScreenCaptureIntent(android.media.projection.MediaProjectionConfig.createConfigForDefaultDisplay()):manager.createScreenCaptureIntent();startActivityForResult(capture,323);}catch(Exception e){projectionPrompt=false;liveToast("Không mở được quyền chia sẻ màn hình.");if(cameraSetup)finish();}}
  @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);externalPicker=false;if(request==324){projectionPrompt=false;if(cameraSetup){gameComments=android.provider.Settings.canDrawOverlays(this);requestGameProjection();}else liveToast(android.provider.Settings.canDrawOverlays(this)?"Đã bật bình luận nổi. Bấm bắt đầu Live.":"Chưa cấp quyền bình luận nổi. Có thể tắt lựa chọn này để phát.");return;}if(request!=323)return;projectionPrompt=false;if(result!=RESULT_OK||data==null){if(cameraSetup){liveToast("Đã hủy chia sẻ · Chưa phát sóng");finish();}else status.setText(I18n.t("Đã hủy chia sẻ · Chưa phát sóng"));return;}if(!ready||isFinishing()){liveToast("Mất kết nối; hãy chọn chia sẻ lại.");return;}startGameSession(data);}
  private void startGameSession(Intent permission){
    gameConnection=new ServiceConnection(){public void onServiceConnected(ComponentName name,IBinder binder){if(isFinishing()||isDestroyed())return;try{gameService=((LiveGameService.SessionBinder)binder).service();gameService.attach(new LiveGameService.Controls(){public void reply(String text){if(joined&&ready)sendLive("chat","text",text);else liveToast("Chưa kết nối để gửi bình luận.");}public void stop(){sendLive("leave");stopGameSession();finish();}public void pause(){toggleScreenPause();}public void mic(){liveMic=!liveMic;if(rtc!=null)rtc.microphone(liveMic);if(gameService!=null)gameService.flags(screenPaused,!liveMic);}});
      gameSession=true;screenPaused=false;SurfaceViewRenderer display=new SurfaceViewRenderer(LiveActivity.this);localLive=display;rtc=new NativeRtc(LiveActivity.this,config,display,null,new NativeRtc.Events(){public void signal(String peer,JSONObject value){}public void status(String value){liveToast(value);}},true);
      rtc.screen(LiveActivity.this,permission,()->{sendLive("leave");stopGameSession();finish();},gameSound);rtc.microphone(pendingHostMic);liveMic=pendingHostMic;carryPreview=true;createHostRoom();
    }catch(Exception e){if(rtc!=null){rtc.close();rtc=null;}stopGameSession();joining=false;previewing=false;if(cameraSetup){liveToast("Không chia sẻ được màn hình. Hãy thử lại.");finish();return;}showGamePreview();status.setText(I18n.t("Không chia sẻ được màn hình. Hãy cấp quyền lại."));}}
    public void onServiceDisconnected(ComponentName name){if(gameSession){gameSession=false;sendLive("leave");finish();}}};
    if(!bindService(new Intent(this,LiveGameService.class),gameConnection,Context.BIND_AUTO_CREATE)){gameConnection=null;liveToast("Không khởi động được Live game.");}
  }
  private void stopGameSession(){gameSession=false;LiveGameService service=gameService;gameService=null;if(service!=null)service.detach();ServiceConnection connection=gameConnection;gameConnection=null;if(connection!=null)try{unbindService(connection);}catch(Exception ignored){}if(liveMode.equals("game")&&rtc!=null){NativeRtc old=rtc;rtc=null;old.close();}}
  private void toggleScreenPause(){if(!gameSession||rtc==null)return;screenPaused=!screenPaused;rtc.screenPaused(screenPaused);sendLive("live-game-state","paused",screenPaused);if(gameService!=null)gameService.flags(screenPaused,!liveMic);}
  private void openGameApp(){if(!gameSession)return;Intent game=LiveGameLaunch.intent(this,gameTitle);if(game==null){liveToast("Không tìm thấy game trên máy.");sendLive("leave");stopGameSession();finish();return;}try{startActivity(game);}catch(Exception e){liveToast("Không mở được game. Chưa phát tiếp.");sendLive("leave");stopGameSession();finish();}}
  private void mountGame(FrameLayout stage){
    TextView cover=text(I18n.t("Chủ phòng đang tạm che màn hình"),18,0xffffffff);cover.setGravity(Gravity.CENTER);cover.setPadding(dp(30),dp(30),dp(30),dp(30));cover.setBackgroundColor(0xff15101f);cover.setVisibility(View.GONE);screenCover=cover;FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-1,-1);stage.addView(cover,1,cp);
    TextView mode=text(I18n.t("Chơi game")+(roomInfo.optString("gameTitle").isEmpty()?"":" · "+roomInfo.optString("gameTitle"))+(host?" · "+I18n.t("Điều khiển"):""),13,0xffffffff);mode.setMinHeight(dp(46));mode.setPadding(dp(12),dp(10),dp(12),dp(10));mode.setBackground(round(0xb32b213d,14));if(host)mode.setOnClickListener(v->new Sheet(this).setTitle(I18n.t("Live game")).setItemIcons(new String[]{"gamepad","shield_check","mic","log_out"}).setItems(new String[]{I18n.t("Mở game"),I18n.t(screenPaused?"Tiếp tục chia sẻ":"Tạm che màn hình"),I18n.t(liveMic?"Tắt mic":"Bật mic"),I18n.t("Kết thúc Live")},(d,n)->{if(n==0)openGameApp();if(n==1)toggleScreenPause();if(n==2){liveMic=!liveMic;if(rtc!=null)rtc.microphone(liveMic);if(gameService!=null)gameService.flags(screenPaused,!liveMic);}if(n==3)confirmLeave();}).setNegativeButton(I18n.t("Quay lại"),null).show());FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);at.setMargins(dp(10),dp(94),dp(10),0);stage.addView(mode,at);
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
    if (type.equals("welcome")) {
      ready = true;socketId=m.optString("id");
      if(!creationEntry)renderRooms();
      // Mở từ tab "Trực tiếp": vào thẳng phòng đã chọn.
      String room = getIntent().getStringExtra(EXTRA_ROOM);
      if (room != null && !joined) { host = false; socket.send(NativeSocket.json("type", "join", "multiGuest", true, "liveModes",true,"room", room)); getIntent().removeExtra(EXTRA_ROOM); }
      if (getIntent().getBooleanExtra(EXTRA_HOST, false) && !joined) { getIntent().removeExtra(EXTRA_HOST); askTitleAndHost(); }
    }
    if (type.equals("rooms")) { lastRooms = m.optJSONArray("rooms"); if (!joined && !previewing) { renderRooms();if(!creationEntry)autoJoin(); } }
    if (type.equals("joined")) { joined = true; joining = false; showRoom(m);if(cameraSetup&&gameSession)openGameApp(); }
    if(type.equals("viewers")){JSONArray users=m.optJSONArray("users");String[] names=new String[users==null?0:users.length()];for(int i=0;i<names.length;i++)names[i]=users.optJSONObject(i).optString("name");Sheet sheet=new Sheet(this).setTitle(I18n.t("Người đang xem")).setNegativeButton(I18n.t("Đóng"),null);if(names.length>0)sheet.setItemIcon("user_round").setItems(names,(d,n)->{});else sheet.setMessage(I18n.t("Chưa có người xem"));sheet.show();return;}
    if(type.equals("live-mode-state")){if(!currentRoom.equals(m.optString("room")))return;if(screenCover!=null)screenCover.setVisibility(m.optBoolean("screenPaused")?View.VISIBLE:View.GONE);return;}
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
    if(type.equals("live-reaction"))showReaction(m.optString("kind"),m.optString("name"));
    if (type.equals("chat")){if(chat!=null)addChat(m.optString("name"),m.optString("text"));if(gameService!=null)gameService.comment(m.optString("name"),m.optString("text"));}
    if (type.equals("room-ended") || type.equals("ended")) { if (host) { Toast.makeText(this, I18n.t("Buổi trực tiếp đã kết thúc."), Toast.LENGTH_LONG).show(); finish(); } else roomEnded(); }
    if (type.equals("error")) { if(host&&!joined){if(cameraSetup){liveToast(m.optString("message","Không bắt đầu được Live."));stopGameSession();finish();return;}stopGameSession();host=false;joining=false;previewing=false;showHostPreview();status.setText(m.optString("message",I18n.t("Chưa bắt đầu được Live. Hãy thử lại.")));return;}joining=false;if(liveStage!=null){liveStage.setTranslationY(0);liveStage.setAlpha(1);}status.setText(m.optString("message")); status.setVisibility(View.VISIBLE); }
  }

  private TextView viewers,arrival;
  private LinearLayout audience;
  private FrameLayout reactionLayer;
  private long lastReaction;private boolean fullFrame=true;
  private void renderAudience(JSONArray users){if(audience==null)return;audience.removeAllViews();if(users==null)return;for(int n=0;n<users.length();n++){JSONObject u=users.optJSONObject(n);if(u==null)continue;String name=u.optString("name","K");FrameLayout avatar=new FrameLayout(this);avatar.setBackground(round(0xaa6c47e0,99));avatar.setClipToOutline(true);TextView initial=text(name.isEmpty()?"K":name.substring(0,1).toUpperCase(),11,0xffffffff);initial.setGravity(Gravity.CENTER);avatar.addView(initial,new FrameLayout.LayoutParams(-1,-1));String url=u.optString("avatar");if(url.startsWith("/api/users/"))NativeApi.shared.image(url,bytes->{if(isDestroyed()||bytes==null)return;android.graphics.Bitmap bitmap=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(bitmap!=null){ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setImageBitmap(bitmap);avatar.addView(image,new FrameLayout.LayoutParams(-1,-1));}});avatar.setContentDescription(name);avatar.setOnClickListener(v->Toast.makeText(this,name,Toast.LENGTH_SHORT).show());LinearLayout.LayoutParams at=new LinearLayout.LayoutParams(dp(28),dp(28));at.leftMargin=dp(5);audience.addView(avatar,at);}}
  private void showArrival(String name){if(arrival==null)return;arrival.removeCallbacks(clearArrival);arrival.setText(name+" "+I18n.t("vừa tham gia"));arrival.setVisibility(View.VISIBLE);arrival.setAlpha(0);arrival.animate().alpha(1).setDuration(180).start();arrival.postDelayed(clearArrival,3500);}
  private final Runnable clearArrival=()->{if(arrival!=null)arrival.setVisibility(View.GONE);};
  private void sendReaction(String kind){if(socket==null||System.currentTimeMillis()-lastReaction<400)return;lastReaction=System.currentTimeMillis();socket.send(NativeSocket.json("type","live-reaction","kind",kind));}
  private void gifts(){toggleLiveTray("gifts");}

  private void showReaction(String kind,String name){if(reactionLayer==null||reactionLayer.getChildCount()>20)return;String glyph=kind.equals("rose")?"🌹":kind.equals("star")?"⭐":kind.equals("crown")?"👑":"♥";TextView heart=text(glyph,kind.equals("heart")?30:42,0xffff4f91);heart.setGravity(Gravity.CENTER);FrameLayout layer=reactionLayer;FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(dp(64),dp(72),Gravity.RIGHT|Gravity.BOTTOM);at.rightMargin=dp(10+(int)(Math.random()*55));at.bottomMargin=dp(90);layer.addView(heart,at);heart.animate().translationY(-dp(210+(int)(Math.random()*120))).translationX(-dp((int)(Math.random()*70))).rotation((float)(Math.random()*35-17)).alpha(0).setDuration(2000).withEndAction(()->layer.removeView(heart)).start();if(!kind.equals("heart")&&chat!=null)addChat(name,I18n.t("đã gửi")+" "+glyph);}

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

  private JSONObject roomInfo=new JSONObject(),liveState,pendingInvitation;
  private JSONArray guestUsers=new JSONArray(),guestRequests=new JSONArray();
  private String liveRole="viewer",inviteMode="video",socketId="";private boolean liveGuestsSupported;
  private SurfaceViewRenderer localLive,pendingGuestLocal;private NativeRtc pendingGuestRtc;private boolean carryPreview;
  private LiveBoard liveBoard;
  private TextView guestAction;private LinearLayout liveSide;
  private boolean guestRequested,liveMic=true,liveCam=true,livePlaybackMuted;
  private Dialog guestSheet,invitationSheet;

  private FrameLayout liveAction(String glyph,String label,Runnable action){
    FrameLayout button=new FrameLayout(this);button.setBackground(round(0x38231e35,99));
    button.addView(icon(glyph,0xffffffff),new FrameLayout.LayoutParams(dp(22),dp(22),Gravity.CENTER));
    button.setContentDescription(I18n.t(label));button.setOnClickListener(v->action.run());return button;
  }
  private void liveToast(String value){Toast.makeText(this,I18n.t(value),Toast.LENGTH_SHORT).show();}
  private void sendLive(String type,Object... values){if(socket==null)return;JSONObject message=NativeSocket.json("type",type);try{for(int i=0;i<values.length;i+=2)message.put(values[i].toString(),values[i+1]);}catch(JSONException ignored){}socket.send(message);}
  private void confirmLeave(){if(host)new Sheet(this).setTitle(I18n.t("Kết thúc Live?")).setPositiveButton(I18n.t("Kết thúc"),(d,w)->{sendLive("leave");finish();}).setNegativeButton(I18n.t("Ở lại"),null).show();else{sendLive("leave");finish();}}
  private void showRoom(JSONObject m){
    String nextMode=m.optJSONObject("room")==null?"chat":m.optJSONObject("room").optString("liveMode","chat");liveMode=nextMode.equals("game")?"game":"chat";
    if(!carryPreview||!host){if(rtc!=null){rtc.close();rtc=null;}localLive=null;}carryPreview=false;liveState=null;liveTray=null;openTray="";guestRequested=false;guestUsers=new JSONArray();guestRequests=new JSONArray();
    liveGuestsSupported=m.optBoolean("multiGuest");roomInfo=m.optJSONObject("room")==null?new JSONObject():m.optJSONObject("room");screenCover=null;currentRoom=roomInfo.optString("id");liveRole=host?"host":"viewer";
    root.removeAllViews();root.setBackgroundColor(0xff0d0b13);getWindow().setStatusBarColor(0xff0d0b13);getWindow().setNavigationBarColor(0xff0d0b13);getWindow().getDecorView().setSystemUiVisibility(0);
    FrameLayout stage=host?new FrameLayout(this):new ViewerStage();liveStage=stage;root.addView(stage,new LinearLayout.LayoutParams(-1,0,1));if(liveEnter!=0){VerticalMediaStage.enter(stage,liveEnter);liveEnter=0;}
    liveBoard=new LiveBoard();stage.addView(liveBoard,new FrameLayout.LayoutParams(-1,-1));
    View shade=new View(this);shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x8807060d,0x00000000,0x00000000,0xc90b0812}));stage.addView(shade,new FrameLayout.LayoutParams(-1,-1));
    reactionLayer=new FrameLayout(this);stage.addView(reactionLayer,new FrameLayout.LayoutParams(-1,-1));
    LinearLayout heading=row();heading.setGravity(Gravity.CENTER_VERTICAL);
    LinearLayout identity=row();identity.setPadding(dp(4),dp(4),dp(10),dp(4));identity.setBackground(round(0x66231c32,28));
    FrameLayout face=liveAvatar(roomInfo.optString("host",I18n.t("Bạn")),roomInfo.optString("avatar"),30);identity.addView(face,new LinearLayout.LayoutParams(dp(30),dp(30)));
    LinearLayout copy=column();copy.setPadding(dp(7),0,0,0);TextView name=text(roomInfo.optString("host",I18n.t("Bạn")),12,0xffffffff);name.setSingleLine(true);name.setEllipsize(android.text.TextUtils.TruncateAt.END);name.setTypeface(null,Typeface.BOLD);copy.addView(name,new LinearLayout.LayoutParams(-1,-2));
    TextView tag=text("LIVE · "+I18n.t(modeName(liveMode)),8,0xffffffff);tag.setSingleLine(true);tag.setEllipsize(android.text.TextUtils.TruncateAt.END);tag.setTypeface(null,Typeface.BOLD);tag.setPadding(dp(5),dp(1),dp(5),dp(1));tag.setBackground(round(0xfff33667,4));copy.addView(tag,new LinearLayout.LayoutParams(-2,-2));identity.addView(copy,new LinearLayout.LayoutParams(0,-2,1));heading.addView(identity,new LinearLayout.LayoutParams(0,-2,1));
    HorizontalScrollView avs=new HorizontalScrollView(this);avs.setHorizontalScrollBarEnabled(false);audience=row();avs.addView(audience);LinearLayout.LayoutParams avp=new LinearLayout.LayoutParams(dp(70),dp(30));avp.leftMargin=dp(4);heading.addView(avs,avp);
    LinearLayout count=row();count.setGravity(Gravity.CENTER);count.addView(icon("eye",0xffffffff),new LinearLayout.LayoutParams(dp(12),dp(12)));viewers=text(String.valueOf(roomInfo.optInt("viewers")),10,0xffffffff);viewers.setSingleLine(true);viewers.setIncludeFontPadding(false);viewers.setPadding(dp(3),0,dp(3),0);count.addView(viewers);count.setOnClickListener(v->sendLive("viewers"));heading.addView(count,new LinearLayout.LayoutParams(-2,dp(36)));
    heading.addView(liveAction("x",host?"Kết thúc Live":"Rời Live",this::confirmLeave),new LinearLayout.LayoutParams(dp(36),dp(36)));
    FrameLayout.LayoutParams hp=new FrameLayout.LayoutParams(-1,dp(58),Gravity.TOP);hp.setMargins(dp(10),dp(8),dp(10),0);stage.addView(heading,hp);
    if(!roomInfo.optString("title").isEmpty()){TextView title=text(roomInfo.optString("title"),11,0xeeffffff);title.setMaxLines(1);title.setEllipsize(android.text.TextUtils.TruncateAt.END);FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);at.setMargins(dp(14),dp(70),dp(14),0);stage.addView(title,at);}
    status=text(I18n.t("Đang kết nối…"),11,0xffd8cfea);status.setGravity(Gravity.CENTER);status.setBackground(round(0x66231c32,12));status.setPadding(dp(10),dp(7),dp(10),dp(7));FrameLayout.LayoutParams st=new FrameLayout.LayoutParams(-2,-2,Gravity.CENTER);stage.addView(status,st);hideStatus=()->status.setVisibility(View.GONE);
    arrival=text("",11,0xffffffff);arrival.setPadding(dp(10),dp(6),dp(10),dp(6));arrival.setBackground(round(0xaa6c47e0,18));arrival.setMaxLines(1);arrival.setEllipsize(android.text.TextUtils.TruncateAt.END);arrival.setVisibility(View.GONE);FrameLayout.LayoutParams arrivalAt=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.START);arrivalAt.setMargins(dp(12),0,dp(70),dp(194));stage.addView(arrival,arrivalAt);
    chatScroll=new ScrollView(this);chatScroll.setVerticalScrollBarEnabled(false);chatScroll.setVerticalFadingEdgeEnabled(true);chatScroll.setFadingEdgeLength(dp(18));chat=column();chatScroll.addView(chat);FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-1,dp(118),Gravity.BOTTOM);cp.setMargins(dp(10),0,dp(66),dp(68));stage.addView(chatScroll,cp);
    JSONArray history=m.optJSONArray("history");for(int i=0;history!=null&&i<history.length();i++){JSONObject item=history.optJSONObject(i);if(item!=null)addChat(item.optString("name"),item.optString("text"));}
    LinearLayout side=column();liveSide=side;side.setGravity(Gravity.CENTER_HORIZONTAL);side.addView(liveAction("heart","Thả tim",()->sendReaction("heart")),new LinearLayout.LayoutParams(dp(44),dp(44)));LinearLayout.LayoutParams gap=new LinearLayout.LayoutParams(dp(44),dp(44));gap.topMargin=dp(10);side.addView(liveAction("send","Chia sẻ",this::shareLive),gap);FrameLayout.LayoutParams sp=new FrameLayout.LayoutParams(dp(44),-2,Gravity.BOTTOM|Gravity.END);sp.setMargins(0,0,dp(10),dp(86));stage.addView(side,sp);
    LinearLayout dock=row();dock.setGravity(Gravity.CENTER_VERTICAL);final EditText input=new KinnectInput(this);input.setHint(I18n.t("Bình luận…"));input.setTextSize(13);input.setTextColor(0xffffffff);input.setHintTextColor(0xbbffffff);input.setSingleLine(true);input.setPadding(dp(12),0,dp(8),0);input.setBackground(round(0x352f283d,24));input.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEND);dock.addView(input,new LinearLayout.LayoutParams(0,dp(42),1));input.setOnEditorActionListener((v,a,e)->{String value=input.getText().toString().trim();if(!value.isEmpty()){sendLive("chat","text",value);input.setText("");}return true;});
    FrameLayout guests=liveAction("users_round",host?"Khách mời":"Lên Live",this::openGuests);guestAction=text("",8,0xffffffff);guestAction.setGravity(Gravity.CENTER);guestAction.setBackground(round(0xfff33667,99));guestAction.setVisibility(View.GONE);FrameLayout.LayoutParams badgeAt=new FrameLayout.LayoutParams(dp(15),dp(15),Gravity.TOP|Gravity.END);guests.addView(guestAction,badgeAt);
    for(FrameLayout action:new FrameLayout[]{guests,liveAction("gift","Tặng quà",this::gifts),liveAction("sliders_horizontal","Công cụ",this::liveTools)}){LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(42),dp(44));lp.leftMargin=dp(4);dock.addView(action,lp);}
    FrameLayout.LayoutParams dp=new FrameLayout.LayoutParams(-1,dp(48),Gravity.BOTTOM);dp.setMargins(dp(10),0,dp(10),dp(10));stage.addView(dock,dp);
    if(liveMode.equals("game")){mountGame(stage);}
    audio.setMode(android.media.AudioManager.MODE_IN_COMMUNICATION);audio.setSpeakerphoneOn(true);
    if(!liveGuestsSupported&&config!=null){String publisher=host?socketId:m.optString("host","legacy-host");JSONObject person=NativeSocket.json("id",publisher,"name",roomInfo.optString("host"),"userId",roomInfo.optString("hostId"),"role","host","mode","video");applyLiveStage(NativeSocket.json("room",currentRoom,"selfId",socketId,"role",host?"host":"viewer","revision",0,"layout","panel","participants",new JSONArray().put(person),"peers",new JSONArray()));}
  }
  private FrameLayout liveAvatar(String name,String path,int size){FrameLayout frame=new FrameLayout(this);frame.setBackground(round(0xff7353ba,99));frame.setClipToOutline(true);TextView initial=text(name.isEmpty()?"K":name.substring(0,1).toUpperCase(),Math.max(10,size/3),0xffffffff);initial.setGravity(Gravity.CENTER);frame.addView(initial,new FrameLayout.LayoutParams(-1,-1));if(path.startsWith("/api/users/"))NativeApi.shared.image(path,bytes->{if(isDestroyed()||bytes==null)return;android.graphics.Bitmap bitmap=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(bitmap!=null){ImageView image=new ImageView(this);image.setScaleType(ImageView.ScaleType.CENTER_CROP);image.setImageBitmap(bitmap);frame.addView(image,new FrameLayout.LayoutParams(-1,-1));}});return frame;}
  private final class LiveBoard extends ViewGroup {
    String layout="panel";LiveBoard(){super(LiveActivity.this);setBackgroundColor(0xff100d19);}
    protected void onMeasure(int w,int h){int width=MeasureSpec.getSize(w),height=MeasureSpec.getSize(h);setMeasuredDimension(width,height);for(int i=0;i<getChildCount();i++){android.graphics.Rect r=tile(i,width,height);getChildAt(i).measure(MeasureSpec.makeMeasureSpec(r.width(),MeasureSpec.EXACTLY),MeasureSpec.makeMeasureSpec(r.height(),MeasureSpec.EXACTLY));}}
    private android.graphics.Rect tile(int i,int w,int h){int n=getChildCount();if(n<=1)return new android.graphics.Rect(0,0,w,h);int top=dp(92),bottom=Math.max(top+dp(120),h-dp(226)),gap=dp(4),left=dp(8),width=w-dp(16);if(layout.equals("panel")){int main=width*62/100;if(i==0)return new android.graphics.Rect(left,top,left+main-gap,bottom);int slot=(bottom-top)/(n-1),y=top+(i-1)*slot;return new android.graphics.Rect(left+main, y,w-left, i==n-1?bottom:y+slot-gap);}int columns=2,rows=(n+1)/2,cw=(width-gap)/columns,ch=(bottom-top-gap*(rows-1))/rows,x=left+(i%2)*(cw+gap),y=top+(i/2)*(ch+gap);return new android.graphics.Rect(x,y,x+cw,y+ch);}
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
    JSONArray people=state.optJSONArray("participants");for(int i=0;people!=null&&i<people.length();i++){JSONObject person=people.optJSONObject(i);if(person==null)continue;FrameLayout tile=new FrameLayout(this);tile.setBackground(round(0xff221b33,14));tile.setClipToOutline(true);String id=person.optString("id");boolean self=id.equals(state.optString("selfId"));boolean video=!person.optString("mode").equals("audio");if(video){SurfaceViewRenderer display=self?localLive:new SurfaceViewRenderer(this);if(display!=null){if(display.getParent()instanceof ViewGroup)((ViewGroup)display.getParent()).removeView(display);tile.addView(display,new FrameLayout.LayoutParams(-1,-1));if(!self)rtc.bindLive(id,display);}}else{FrameLayout avatar=liveAvatar(person.optString("name"),person.optString("avatar"),56);tile.addView(avatar,new FrameLayout.LayoutParams(dp(56),dp(56),Gravity.CENTER));}
      TextView label=text(person.optString("name")+(self?" · "+I18n.t("Bạn"):""),10,0xffffffff);label.setSingleLine(true);label.setEllipsize(android.text.TextUtils.TruncateAt.END);label.setPadding(dp(7),dp(4),dp(7),dp(4));label.setBackground(round(0x88201a2c,9));FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);lp.setMargins(dp(5),0,dp(5),dp(5));tile.addView(label,lp);liveBoard.addView(tile);}
    rtc.playback(!livePlaybackMuted);liveBoard.requestLayout();JSONArray peers=state.optJSONArray("peers");for(int i=0;peers!=null&&i<peers.length();i++){JSONObject peer=peers.optJSONObject(i);if(peer!=null&&peer.optBoolean("offer"))rtc.offer(peer.optString("id"));}status.setVisibility(View.GONE);
  }
  private void shareLive(){try{startActivity(android.content.Intent.createChooser(new android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain").putExtra(android.content.Intent.EXTRA_TEXT,ServerConfig.DEFAULT_ORIGIN+"/?s=live&room="+currentRoom),I18n.t("Chia sẻ buổi live")));}catch(Exception ignored){}}
  private HorizontalScrollView liveTray;private String openTray="";
  private void liveTools(){toggleLiveTray("tools");}
  private void toggleLiveTray(String value){if(liveStage==null)return;if(liveTray!=null){liveStage.removeView(liveTray);liveTray=null;}if(openTray.equals(value)){openTray="";if(chatScroll!=null)chatScroll.setVisibility(View.VISIBLE);if(liveSide!=null)liveSide.setVisibility(View.VISIBLE);return;}openTray=value;if(chatScroll!=null)chatScroll.setVisibility(View.INVISIBLE);if(liveSide!=null)liveSide.setVisibility(View.INVISIBLE);if(arrival!=null)arrival.setVisibility(View.GONE);android.view.inputmethod.InputMethodManager keyboard=(android.view.inputmethod.InputMethodManager)getSystemService(INPUT_METHOD_SERVICE);keyboard.hideSoftInputFromWindow(root.getWindowToken(),0);liveTray=new HorizontalScrollView(this);liveTray.setHorizontalScrollBarEnabled(false);liveTray.setBackground(round(0xf2231c31,22));LinearLayout items=row();items.setPadding(dp(8),dp(8),dp(8),dp(8));liveTray.addView(items);
    if(value.equals("gifts")){for(String[] gift:new String[][]{{"rose","🌹","Hoa hồng"},{"star","⭐","Ngôi sao"},{"crown","👑","Vương miện"}}){LinearLayout tile=column();tile.setGravity(Gravity.CENTER);TextView art=text(gift[1],30,0xffffffff);art.setGravity(Gravity.CENTER);tile.addView(art);TextView name=text(I18n.t(gift[2]),10,0xffffffff);name.setGravity(Gravity.CENTER);tile.addView(name);TextView free=text(I18n.t("Miễn phí"),9,0xffc6b4ec);free.setGravity(Gravity.CENTER);tile.addView(free);tile.setOnClickListener(v->sendReaction(gift[0]));items.addView(tile,new LinearLayout.LayoutParams(dp(86),dp(84)));}}
    else{if(host&&liveMode.equals("game")){trayTool(items,"gamepad","Tạm che",this::toggleScreenPause);trayTool(items,"monitor","Mở game",this::openGameApp);}if(!liveRole.equals("viewer")){trayTool(items,liveMic?"mic":"mic",liveMic?"Tắt mic":"Bật mic",()->{liveMic=!liveMic;rtc.microphone(liveMic);refreshTools();});if(!liveMode.equals("game")&&(host||liveState==null||!liveState.optString("mode").equals("audio"))){trayTool(items,liveCam?"camera":"camera_off",liveCam?"Tắt camera":"Bật camera",()->{liveCam=!liveCam;rtc.camera(liveCam);refreshTools();});trayTool(items,"switch_camera","Đổi camera",()->rtc.flip());trayTool(items,"sparkles","Hiệu ứng",this::effectsMenu);}}if(host){trayTool(items,"grid","Lưới",()->sendLive("live-layout","layout","grid"));trayTool(items,"users_round","Chủ phòng lớn",()->sendLive("live-layout","layout","panel"));}else{trayTool(items,"flag","Báo cáo",this::reportLive);trayTool(items,"shield_check","Chặn",this::blockLive);trayTool(items,"user_plus",roomInfo.optBoolean("following")?"Bỏ theo dõi":"Theo dõi",this::followLive);trayTool(items,"volume_2",livePlaybackMuted?"Bật tiếng":"Tắt tiếng",()->{livePlaybackMuted=!livePlaybackMuted;if(rtc!=null)rtc.playback(!livePlaybackMuted);refreshTools();});}trayTool(items,"send","Chia sẻ",this::shareLive);}
    FrameLayout.LayoutParams at=new FrameLayout.LayoutParams(-1,dp(value.equals("gifts")?104:96),Gravity.BOTTOM);at.setMargins(dp(10),0,dp(10),dp(66));liveStage.addView(liveTray,at);liveTray.setAlpha(0);liveTray.setTranslationY(dp(12));liveTray.animate().alpha(1).translationY(0).setDuration(180).start();
  }
  private void refreshTools(){openTray="";toggleLiveTray("tools");}
  private void trayTool(LinearLayout row,String glyph,String name,Runnable action){LinearLayout tile=column();tile.setGravity(Gravity.CENTER);tile.addView(icon(glyph,0xffffffff),new LinearLayout.LayoutParams(dp(24),dp(24)));TextView label=text(I18n.t(name),10,0xffffffff);label.setGravity(Gravity.CENTER);label.setMaxLines(2);label.setPadding(dp(2),dp(6),dp(2),0);tile.addView(label,new LinearLayout.LayoutParams(-1,-2));tile.setContentDescription(I18n.t(name));tile.setOnClickListener(v->action.run());row.addView(tile,new LinearLayout.LayoutParams(dp(70),dp(76)));}
  private void blockLive(){new Sheet(this).setTitle(I18n.t("Chặn người phát?")).setPositiveButton(I18n.t("Chặn"),(d,w)->NativeApi.shared.call("POST","/api/users/"+roomInfo.optString("hostId")+"/block",new JSONObject(),(data,error,code)->{if(error==null)finish();else liveToast(error);})).setNegativeButton(I18n.t("Hủy"),null).show();}
  private void followLive(){boolean following=roomInfo.optBoolean("following");NativeApi.shared.call(following?"DELETE":"POST","/api/users/"+roomInfo.optString("hostId")+"/follow",new JSONObject(),(data,error,code)->{if(isDestroyed())return;if(error!=null){liveToast(error);return;}try{roomInfo.put("following",!following);}catch(JSONException ignored){}refreshTools();});}
  private void reportLive(){EditText reason=field(I18n.t("Mô tả vi phạm; không gửi lại ảnh CSAM"));new Sheet(this).setTitle(I18n.t("Báo cáo buổi live")).setView(reason).setPositiveButton(I18n.t("Gửi báo cáo"),(d,w)->{String value=reason.getText().toString().trim();if(value.length()<5){liveToast("Mô tả ít nhất 5 ký tự.");return;}NativeApi.shared.call("POST","/api/reports",NativeSocket.json("targetType","user","targetId",roomInfo.optString("hostId"),"reason","[Live "+currentRoom+"] "+value),(data,error,code)->liveToast(error==null?"Đã gửi báo cáo.":error));}).setNegativeButton(I18n.t("Hủy"),null).show();}
  private void openGuests(){if(!liveGuestsSupported){liveToast("Cần cập nhật máy chủ để dùng khách mời.");return;}if(host){sendLive("live-guest-list");return;}if(liveRole.equals("guest")){new Sheet(this).setTitle(I18n.t("Bạn đang lên Live")).setItemIcons(new String[]{"log_out"}).setItems(new String[]{I18n.t("Rời ghế khách")},(d,n)->sendLive("live-guest-leave")).show();return;}if(guestRequested){new Sheet(this).setTitle(I18n.t("Đang chờ chủ phòng duyệt")).setPositiveButton(I18n.t("Hủy yêu cầu"),(d,w)->sendLive("live-guest-cancel")).setNegativeButton(I18n.t("Đóng"),null).show();return;}new Sheet(this).setTitle(I18n.t("Xin lên Live")).setMessage(I18n.t("Camera và micro chỉ bật sau khi bạn đồng ý lên Live.")).setItemIcons(new String[]{"video","mic"}).setItems(new String[]{I18n.t("Tham gia bằng video"),I18n.t("Chỉ âm thanh")},(d,n)->sendLive("live-guest-request","mode",n==0?"video":"audio")).show();}
  private void guestManagement(){if(!host)return;if(guestSheet!=null)guestSheet.dismiss();LinearLayout body=column();body.setPadding(dp(4),0,dp(4),0);TextView hint=text(I18n.t("Mời người đang xem · Tối đa 3 khách"),12,MUTED);hint.setGravity(Gravity.CENTER);body.addView(hint);for(int i=0;i<guestRequests.length();i++){JSONObject u=guestRequests.optJSONObject(i);if(u!=null)guestRow(body,u,true);}for(int i=0;i<guestUsers.length();i++){JSONObject u=guestUsers.optJSONObject(i);if(u!=null)guestRow(body,u,false);}if(guestUsers.length()==0&&guestRequests.length()==0){TextView empty=text(I18n.t("Chưa có người xem để mời"),14,MUTED);empty.setPadding(dp(8),dp(24),dp(8),dp(24));empty.setGravity(Gravity.CENTER);body.addView(empty);}ScrollView scroll=new ScrollView(this);scroll.addView(body);guestSheet=new Sheet(this).setTitle(I18n.t("Khách mời")).setView(scroll).setNegativeButton(I18n.t("Đóng"),null).show();}
  private void guestRow(LinearLayout body,JSONObject u,boolean request){LinearLayout line=row();line.setPadding(0,dp(8),0,dp(8));line.addView(liveAvatar(u.optString("name"),u.optString("avatar"),36),new LinearLayout.LayoutParams(dp(36),dp(36)));TextView name=text(u.optString("name"),13,TEXT);name.setMaxLines(2);name.setPadding(dp(8),0,dp(4),0);line.addView(name,new LinearLayout.LayoutParams(0,-2,1));String label=request?"Duyệt":u.optBoolean("onStage")?"Gỡ":"Mời";TextView action=pill(I18n.t(label),true,()->{sendLive(request?"live-guest-approve":u.optBoolean("onStage")?"live-guest-remove":"live-guest-invite","to",u.optString("id"));if(guestSheet!=null)guestSheet.dismiss();});action.setTextSize(12);line.addView(action,new LinearLayout.LayoutParams(dp(66),dp(40)));if(request){TextView no=text("×",24,MUTED);no.setGravity(Gravity.CENTER);no.setContentDescription(I18n.t("Từ chối"));no.setOnClickListener(v->{sendLive("live-guest-decline","to",u.optString("id"));if(guestSheet!=null)guestSheet.dismiss();});line.addView(no,new LinearLayout.LayoutParams(dp(36),dp(40)));}body.addView(line);}
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
    if(cameraSetup&&!isFinishing()){liveToast("Kết nối Live bị gián đoạn. Hãy thử lại.");stopGameSession();finish();return;}
    if (isFinishing()) return;
    stopGameSession();ready = false;clearPendingGuest();pendingInvitation=null;
    status.setText(I18n.t("Đã mất kết nối. Hãy mở lại mục Trực tiếp."));
    status.setVisibility(View.VISIBLE);
    if (rtc != null) { rtc.close(); rtc = null; }
  }

  protected void onStop() { super.onStop();if(gameSession&&gameService!=null&&gameComments)gameService.overlayVisible(true); if ((joined || previewing) && !gameSession&&gameConnection==null&&!projectionPrompt&&!externalPicker&&!isChangingConfigurations()) finish(); }
  @Override protected void onResume(){super.onResume();externalPicker=false;if(gameService!=null)gameService.overlayVisible(false);}
  @Override public void onBackPressed(){if(joined){confirmLeave();return;}super.onBackPressed();}

  protected void onDestroy() {
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
