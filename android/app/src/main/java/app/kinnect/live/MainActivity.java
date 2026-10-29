package app.kinnect.live;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.location.*;
import android.os.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import java.net.URLEncoder;
import java.util.*;
import org.json.*;

/** Native Android social client. All application screens use Android views. */
public class MainActivity extends Activity {
  @Override protected void attachBaseContext(android.content.Context base) { super.attachBaseContext(I18n.localized(base)); }


  private final NativeApi api = NativeApi.shared;
  private final Handler handler = new Handler(Looper.getMainLooper());
  private final Handler startupHandler = new Handler(Looper.getMainLooper());
  private android.animation.ObjectAnimator splashAnimator;
  private final List<VideoView> mediaVideos = new ArrayList<>(), resumeVideos = new ArrayList<>();
  private LinearLayout root, content, toolbar, bottom;
  private TextView notice;
  private JSONObject me, chatUser;
  private JSONArray shortRows;
  private int shortIndex = 0;
  private VideoView shortVideo;
  private android.media.MediaPlayer shortPlayer;
  private boolean shortMuted = false,
    postingVideo = false;
  private String tab = "feed";
  private Runnable currentPage;
  private void refreshPage() { if (currentPage != null) currentPage.run(); else navigate(tab); }
  private int screen = 0;
  private boolean stopped = false;
  private Runnable poll, resumeStory;
  static final class CallPlaybackGate {
    private final Set<String> calls=new HashSet<>();
    void update(String type,String id){if(id==null||id.isEmpty())return;if(type.equals("call-incoming")||type.equals("call-ringing")||type.equals("call-accepted"))calls.add(id);else if(type.equals("call-ended"))calls.remove(id);}
    boolean blocked(){return !calls.isEmpty();}
    void clear(){calls.clear();}
  }
  static final class ChatTextPolicy {
    static int mentionIndex(String text,String username){
      if(text==null||username==null||username.isEmpty())return -1;
      String token="@"+username;
      for(int at=text.indexOf(token);at>=0;at=text.indexOf(token,at+token.length())){
        int end=at+token.length();char before=at==0?' ':text.charAt(at-1);
        boolean start=at==0||Character.isWhitespace(before)||before=='('||before=='['||before=='{';
        boolean finish=end==text.length()||!(Character.isLetterOrDigit(text.charAt(end))||"_.-".indexOf(text.charAt(end))>=0);
        if(start&&finish)return at;
      }
      return -1;
    }
  }
  private final CallPlaybackGate mediaCallGate=new CallPlaybackGate();
  private boolean mediaCallBlocked,mediaCallListening;
  private final NativeSocket.Events mediaCallEvents=new NativeSocket.Events(){
    public void event(JSONObject event){String type=event.optString("type");if(type.equals("ai-stream")){receiveAIStream(event);return;}mediaCallGate.update(type,event.optString("callId"));mediaCallBlocked=mediaCallGate.blocked();if(mediaCallBlocked)pauseForCall();}
    public void closed(){aiDrafts.clear();paintAIStream();mediaCallGate.clear();mediaCallBlocked=false;}
  };
  private void pauseForCall(){
    if(shortVideo!=null)try{shortVideo.pause();}catch(RuntimeException ignored){}
    for(VideoView video:mediaVideos)try{video.pause();}catch(RuntimeException ignored){}
    resumeVideos.clear();
  }
  private NativeCalls calls;
  private void ensureCalls(){if(me!=null&&!mediaCallListening){mediaCallListening=true;KinnectService.listen(mediaCallEvents);}if(KinnectService.pendingIncoming!=null){mediaCallGate.update("call-incoming",KinnectService.pendingIncoming.optString("callId"));mediaCallBlocked=mediaCallGate.blocked();pauseForCall();}if(me!=null&&calls==null){calls=new NativeCalls(this,server());setupBackground();}}
  // Một lần: xin đủ quyền thông báo/cuộc gọi, cho phép toàn màn hình và chạy nền.
  private void setupBackground(){if(Distribution.PLAY){if(Build.VERSION.SDK_INT>=33&&checkSelfPermission("android.permission.POST_NOTIFICATIONS")!=PackageManager.PERMISSION_GRANTED)requestPermissions(new String[]{"android.permission.POST_NOTIFICATIONS"},950);return;}android.content.SharedPreferences p=getSharedPreferences("native_setup",0);if(p.getBoolean("asked_v1",false)){backgroundExtras(false);return;}p.edit().putBoolean("asked_v1",true).apply();java.util.ArrayList<String> want=new java.util.ArrayList<>();if(Build.VERSION.SDK_INT>=33)want.add("android.permission.POST_NOTIFICATIONS");want.add(Manifest.permission.RECORD_AUDIO);want.add(Manifest.permission.CAMERA);if(Build.VERSION.SDK_INT>=31)want.add("android.permission.BLUETOOTH_CONNECT");java.util.ArrayList<String> missing=new java.util.ArrayList<>();for(String w:want)if(checkSelfPermission(w)!=PackageManager.PERMISSION_GRANTED)missing.add(w);if(missing.isEmpty())backgroundExtras(true);else requestPermissions(missing.toArray(new String[0]),950);}
  private void backgroundExtras(boolean prompt){if(Distribution.PLAY)return;try{if(Build.VERSION.SDK_INT>=34&&!getSystemService(android.app.NotificationManager.class).canUseFullScreenIntent()){if(prompt)new AlertDialog.Builder(this).setTitle(I18n.t("Cuộc gọi toàn màn hình")).setMessage(I18n.t("Cho phép Kinnect hiện cuộc gọi đến toàn màn hình, kể cả khi khóa máy.")).setPositiveButton(I18n.t("Cho phép"),(d,w)->{try{startActivity(new Intent("android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT",android.net.Uri.parse("package:"+getPackageName())));}catch(RuntimeException ignored){}}).setNegativeButton(I18n.t("Để sau"),(d,w)->battery()).show();else battery();return;}}catch(RuntimeException ignored){}if(prompt)battery();}
  private void battery(){android.os.PowerManager pm=(android.os.PowerManager)getSystemService(POWER_SERVICE);if(pm!=null&&!pm.isIgnoringBatteryOptimizations(getPackageName()))try{startActivity(new Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,android.net.Uri.parse("package:"+getPackageName())));}catch(RuntimeException ignored){}}
  private void handleExtras(Intent intent){if(intent==null||me==null)return;String destination=intent.getStringExtra("commerce_destination");if(destination!=null){intent.removeExtra("commerce_destination");if(destination.equals("account"))meMenu();else if(destination.equals("notifications"))notifications();else if(destination.equals("friends"))friendsScreen("friends");else if(destination.equals("create"))chooseVideo();else navigate(destination);}if(intent.getBooleanExtra("accept_call",false)){intent.removeExtra("accept_call");ensureCalls();if(calls!=null)calls.checkPending();}String n=intent.getStringExtra("notification");if(n!=null){intent.removeExtra("notification");try{openNotification(new JSONObject(n));}catch(JSONException ignored){}}}
  private LocationListener locationListener;
  // Màu lấy từ public/theme.css để app và web mobile trông giống nhau; tự theo chế độ sáng/tối của máy.
  private int BG, CARD, TEXT, MUTED, ACCENT, SOFT, LINE, PRIMARY_SOFT;
  private static final int PINK = 0xffff4f9a, WHITE = 0xffffffff;

  private void palette() {
    boolean dark = WebTheme.isDark(this);
    int variant = dark ? 1 : 0;
    BG = WebDesign.BG[variant]; CARD = WebDesign.CARD[variant]; TEXT = WebDesign.INK[variant];
    MUTED = WebDesign.MUTED[variant]; ACCENT = WebDesign.PURPLE[variant]; SOFT = WebDesign.WASH[variant];
    LINE = WebDesign.LINE[variant]; PRIMARY_SOFT = WebDesign.SOFT[variant];
  }

  private GradientDrawable gradient(int radius) {
    GradientDrawable d = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { ACCENT, ACCENT });
    d.setCornerRadius(dp(radius));
    return d;
  }

  private interface Done {
    void accept(JSONObject data);
  }

  @Override
  public void onCreate(Bundle state) {
    boolean night = WebTheme.isDark(this);
    setTheme(night ? android.R.style.Theme_Material_NoActionBar : android.R.style.Theme_Material_Light_NoActionBar);
    super.onCreate(state);
    CrashLog.install(this);
    palette();
    api.initialize(this,server());
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    if (!WebTheme.isDark(this))
      getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    splash();
    final long shownAt = System.currentTimeMillis();
    final boolean hasSession = !api.cookieFor(server()).isEmpty();
    if (hasSession) api.call("GET", "/api/me", null, (data, error, status) -> {
      if (isDestroyed()) return;
      long wait = Math.max(0, 450 - (System.currentTimeMillis() - shownAt));
      startupHandler.postDelayed(() -> {
        if (isDestroyed() || isFinishing()) return;
        JSONObject user = data == null ? null : data.optJSONObject("user");
        if (error == null && user != null) { me = user; navigate("feed"); handleExtras(getIntent()); }
        else auth(false);
        handleLink(getIntent());
        CrashLog.showPending(this);
      }, wait);
    });
    else startupHandler.postDelayed(() -> { if (!isDestroyed() && !isFinishing()) { intro(); handleLink(getIntent()); CrashLog.showPending(this); } }, 700);
  }

  private void splash() {
    FrameLayout s = new FrameLayout(this);
    s.setBackgroundColor(BG);
    LinearLayout c = column();
    c.setGravity(Gravity.CENTER_HORIZONTAL);
    ImageView logo = new ImageView(this);
    logo.setImageResource(getResources().getIdentifier("kinnect_logo", "drawable", getPackageName()));
    logo.setElevation(dp(10));
    c.addView(logo, new LinearLayout.LayoutParams(dp(96), dp(96)));
    TextView name = label("Kinnect", 26, ACCENT);
    name.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    name.setPadding(0, dp(18), 0, dp(18));
    c.addView(name);
    FrameLayout rings=new FrameLayout(this);for(int i=0;i<2;i++){View ring=new View(this);GradientDrawable outline=background(0x00000000,99);outline.setStroke(dp(2),i==0?ACCENT:PINK);ring.setBackground(outline);FrameLayout.LayoutParams rp=new FrameLayout.LayoutParams(dp(20),dp(20),Gravity.CENTER);rings.addView(ring,rp);ring.setTranslationX(dp(i==0?-16:16));ring.animate().translationX(dp(i==0?-5:5)).setDuration(400).start();}LinearLayout.LayoutParams space=new LinearLayout.LayoutParams(-1,dp(42));space.topMargin=dp(18);c.addView(rings,space);
    s.addView(c, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    setContentView(s);
    getWindow().setStatusBarColor(BG);
    getWindow().setNavigationBarColor(BG);
  }

  private String server() {
    return ServerConfig.DEFAULT_ORIGIN;
  }

  private int dp(int n) {
    return Math.round(n * getResources().getDisplayMetrics().density);
  }

  private GradientDrawable background(int color, int radius) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    return d;
  }

  private android.graphics.drawable.Drawable pressable(int color, int radius) {
    GradientDrawable mask = background(0xff000000, radius);
    return new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf((ACCENT & 0x00ffffff) | 0x33000000), background(color, radius), mask);
  }

  private TextView label(String text, int size, int color) {
    TextView v = new TextView(this);
    v.setText(text);
    v.setTextColor(color);
    v.setTextSize(size);
    v.setIncludeFontPadding(false);
    v.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
    if (size <= 16) v.setLineSpacing(dp(3), 1f);
    v.setLetterSpacing(size >= 20 ? -0.01f : 0f);
    v.setPadding(0, dp(5), 0, dp(5));
    return v;
  }

  private LinearLayout column() {
    LinearLayout v = new LinearLayout(this);
    v.setOrientation(LinearLayout.VERTICAL);
    return v;
  }

  private LinearLayout row() {
    LinearLayout v = new LinearLayout(this);
    v.setOrientation(LinearLayout.HORIZONTAL);
    v.setGravity(Gravity.CENTER_VERTICAL);
    return v;
  }

  private Button button(String text, Runnable action) {
    Button b = new Button(this);
    b.setText(text);
    b.setTextColor(TEXT);
    b.setTextSize(WebDesign.LABEL);
    b.setIncludeFontPadding(false);
    b.setMinHeight(dp(WebDesign.CONTROL));
    b.setMinimumHeight(dp(WebDesign.CONTROL));
    b.setAllCaps(false);
    b.setStateListAnimator(null);
    b.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    b.setTextSize(14);
    b.setBackground(pressable(SOFT, 12));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, dp(46));
    p.setMargins(0, dp(6), 0, dp(4));
    b.setLayoutParams(p);
    b.setOnClickListener(v -> action.run());
    return b;
  }

  private Button primary(String text, Runnable action) {
    Button b = button(text, action);
    b.setTextColor(WHITE);
    b.setBackground(pressable(ACCENT, 12));
    b.setElevation(dp(2));
    return b;
  }

  private EditText input(
    LinearLayout parent,
    String hint,
    String value,
    boolean multiline
  ) {
    EditText v = new EditText(this);
    v.setHint(hint);
    v.setContentDescription(hint);
    v.setText(value);
    v.setTextColor(TEXT);
    v.setHintTextColor(MUTED);
    v.setTextSize(15);
    v.setSingleLine(!multiline);
    v.setPadding(dp(14), dp(12), dp(14), dp(12));
    GradientDrawable idle = background(CARD, 12);
    idle.setStroke(dp(1), LINE);
    GradientDrawable focused = background(CARD, 12);
    focused.setStroke(dp(2), ACCENT);
    android.graphics.drawable.StateListDrawable states = new android.graphics.drawable.StateListDrawable();
    states.addState(new int[] { android.R.attr.state_focused }, focused);
    states.addState(new int[0], idle);
    v.setBackground(states);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
      -1,
      multiline ? dp(96) : dp(46)
    );
    p.setMargins(0, dp(7), 0, dp(10));
    parent.addView(v, p);
    return v;
  }

  private LinearLayout card() {
    LinearLayout v = column();
    v.setPadding(dp(16), dp(16), dp(16), dp(16));
    GradientDrawable cardBg = background(CARD, WebDesign.CARD_RADIUS);
    cardBg.setStroke(1, LINE);
    v.setBackground(cardBg);
    v.setElevation(dp(1));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.setMargins(0, dp(7), 0, dp(7));
    content.addView(v, p);
    return v;
  }

  private boolean onTabRoot = false;
  private LinearLayout headActions;
  private TextView inboxBadge, bellBadge, friendsBadge;
  private int friendsCount;
  private int inboxCount, bellCount;
  private long badgesAt;
  private String badgeAccount = "";
  private String pendingDownload = "";
  private long noticeWatermark = System.currentTimeMillis();
  private final Handler notificationHandler = new Handler(Looper.getMainLooper());
  private final Runnable notificationPoll = new Runnable() { public void run() { if (!stopped) { refreshBadges(); notificationHandler.postDelayed(this, 20000); } } };

  private void shell(String title, boolean navigation) {
    onTabRoot = false;
    if (splashAnimator != null) { splashAnimator.cancel(); splashAnimator = null; }
    for (VideoView video : mediaVideos) { try { video.stopPlayback(); } catch (RuntimeException ignored) {} }
    mediaVideos.clear(); resumeVideos.clear();
    stopShort();
    stopLocation();
    screen++;
    preparingPostMedia = false;
    handler.removeCallbacksAndMessages(null);
    poll = null;
    resumeStory = null;
    chatUser = null;
    chatReload = null;
    profileEditorAvatar = null;
    root = column();
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener((v, insets) -> {
      v.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
      return insets;
    });
    setContentView(root);
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    // Thanh trên giống web: logo · Live · Tin nhắn · Thông báo · tài khoản
    toolbar = row();
    toolbar.setPadding(dp(12), 0, dp(10), 0);
    toolbar.setBackgroundColor(CARD);
    toolbar.setElevation(dp(1));
    ImageView logo = new ImageView(this);
    logo.setImageResource(getResources().getIdentifier("kinnect_logo", "drawable", getPackageName()));
    logo.setClipToOutline(true);
    logo.setBackground(background(CARD, 10));
    toolbar.addView(logo, new LinearLayout.LayoutParams(dp(34), dp(34)));
    TextView brand = label("Kinnect", 20, ACCENT);
    brand.setTypeface(Typeface.create("sans-serif-black", Typeface.NORMAL));
    brand.setLetterSpacing(-0.03f);
    brand.setTextColor(ACCENT);
    brand.setPadding(dp(8), 0, 0, 0);
    toolbar.addView(brand, new LinearLayout.LayoutParams(0, -2, 1));
    if (me != null && navigation) {
      toolbar.addView(topIcon("bell", I18n.t("Thông báo"), headerActive.equals("bell"), () -> notifications(), "bell"));
      toolbar.addView(topIcon("users_round", I18n.t("Bạn bè"), headerActive.equals("friends"), () -> friendsScreen(friendsCount > 0 ? "incoming" : "friends"), "friends"));
      toolbar.addView(topIcon("message_square", I18n.t("Tin nhắn"), headerActive.equals("inbox"), () -> navigate("inbox"), "inbox"));
      ImageView meButton = new ImageView(this);
      meButton.setScaleType(ImageView.ScaleType.CENTER_CROP);
      GradientDrawable round = new GradientDrawable();
      round.setShape(GradientDrawable.OVAL);
      round.setColor(PRIMARY_SOFT);
      meButton.setBackground(round);
      meButton.setClipToOutline(true);
      meButton.setImageBitmap(initials(me, dp(38)));
      loadAvatarInto(me, meButton);
      meButton.setContentDescription(I18n.t("Tài khoản"));
      meButton.setOnClickListener(v -> meMenu());
      LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(dp(38), dp(38));
      mp.setMargins(dp(6), 0, 0, 0);
      toolbar.addView(meButton, mp);
      refreshBadges();
    } else if (me == null) {
      ImageView settings = icon("settings", 22, MUTED);
      settings.setPadding(dp(10), dp(10), dp(10), dp(10));
      settings.setContentDescription(I18n.t("Cài đặt"));
      settings.setOnClickListener(v -> settings());
      toolbar.addView(settings, new LinearLayout.LayoutParams(dp(44), dp(44)));
    }
    root.addView(toolbar, new LinearLayout.LayoutParams(-1, dp(WebDesign.HEADER)));
    if(calls!=null)root.post(()->{if(calls!=null)calls.attachReturn(root);});
    headerActive = "";
    View line = new View(this);
    line.setBackgroundColor(LINE);
    root.addView(line, new LinearLayout.LayoutParams(-1, 1));
    notice = label("", 12, ACCENT);
    notice.setPadding(dp(16), 0, dp(16), 0);
    notice.setVisibility(View.GONE);
    root.addView(notice);
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    content = column();
    content.setPadding(dp(16), dp(14), dp(16), dp(24));
    scroll.addView(content);
    LinearLayout.LayoutParams viewport = new LinearLayout.LayoutParams(Math.min(getResources().getDisplayMetrics().widthPixels, dp(720)), 0, 1);
    viewport.gravity = Gravity.CENTER_HORIZONTAL;
    root.addView(scroll, viewport);
    headActions = null;
    if (navigation && me != null && !title.isEmpty()) {
      LinearLayout head = row();
      TextView heading = label(title, 17, TEXT);
      heading.setTypeface(null, Typeface.BOLD);
      head.addView(heading, new LinearLayout.LayoutParams(0, -2, 1));
      headActions = row();
      head.addView(headActions);
      LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(-1, -2);
      hp.bottomMargin = dp(6);
      content.addView(head, hp);
    }
    if (navigation) {
      View top = new View(this);
      top.setBackgroundColor(LINE);
      root.addView(top, new LinearLayout.LayoutParams(-1, 1));
      bottom = row();
      bottom.setBackgroundColor(CARD);
      String[][] items = { { "feed", "house", "Bảng tin" }, { "discover", "compass", "Khám phá" }, { "create", "plus", "Tạo" }, { "shorts", "clapperboard", "Video" }, { "live", "radio", "Live" } };
      for (final String[] it : items) {
        if (it[0].equals("create")) {
          FrameLayout holder = new FrameLayout(this);
          FrameLayout plus = new FrameLayout(this);
          GradientDrawable plusBg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { ACCENT, PINK });
          plusBg.setCornerRadius(dp(99));
          plus.setBackground(plusBg);
          plus.setElevation(dp(4));
          plus.addView(icon("plus", 24, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
          plus.setContentDescription(I18n.t("Tạo nội dung"));
          plus.setTooltipText(I18n.t("Tạo nội dung"));
          plus.setOnClickListener(v -> chooseVideo());
          holder.addView(plus, new FrameLayout.LayoutParams(dp(44), dp(44), Gravity.CENTER));
          bottom.addView(holder, new LinearLayout.LayoutParams(0, dp(62), 1));
          continue;
        }
        boolean active = tab.equals(it[0]);
        LinearLayout b = column();
        b.setGravity(Gravity.CENTER);
        FrameLayout pill = new FrameLayout(this);
        if (active) pill.setBackground(background(PRIMARY_SOFT, 99));
        pill.addView(icon(it[1], 20, active ? ACCENT : MUTED), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
        b.addView(pill, new LinearLayout.LayoutParams(dp(50), dp(28)));
        TextView t = label(I18n.t(it[2]), 11, active ? ACCENT : MUTED);
        t.setPadding(0, dp(2), 0, 0);
        t.setGravity(Gravity.CENTER);
        t.setSingleLine(true);
        t.setEllipsize(android.text.TextUtils.TruncateAt.END);
        t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
        b.addView(t);
        b.setContentDescription(I18n.t(it[2]));
        b.setSelected(active);
        b.setFocusable(true);
        b.setTooltipText(I18n.t(it[2]));
        b.setBackground(pressable(CARD, 14));
        b.setOnClickListener(v -> navigate(it[0]));
        bottom.addView(b, new LinearLayout.LayoutParams(0, dp(62), 1));
      }
      root.addView(bottom);
    }
  }

  private ImageView icon(String name, int size, int color) {
    ImageView v = new ImageView(this);
    int id = WebIcons.resolve(this, name);
    if (id != 0) {
      android.graphics.drawable.Drawable d = WebIcons.load(this, name);
      d.setTint(color);
      v.setImageDrawable(d);
    }
    v.setScaleType(ImageView.ScaleType.FIT_CENTER);
    return v;
  }

  private FrameLayout topIcon(String name, String label, boolean active, Runnable action, String badgeKey) {
    FrameLayout f = new FrameLayout(this);
    ImageView i = icon(name, 20, active ? ACCENT : TEXT);
    f.addView(i, new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    f.setBackground(pressable(active ? PRIMARY_SOFT : CARD, 99));
    if (badgeKey != null) {
      TextView badge = label("", 1, WHITE);
      GradientDrawable bd = background(ACCENT, 99);
      bd.setStroke(dp(2), CARD);
      badge.setBackground(bd);
      badge.setVisibility(View.GONE);
      FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(dp(10), dp(10), Gravity.TOP | Gravity.END);
      bp.setMargins(0, dp(9), dp(8), 0);
      f.addView(badge, bp);
      if (badgeKey.equals("inbox")) inboxBadge = badge; else if (badgeKey.equals("friends")) friendsBadge = badge; else bellBadge = badge;
      showBadge(badge, badgeKey.equals("inbox") ? inboxCount : badgeKey.equals("friends") ? friendsCount : bellCount);
    }
    f.setContentDescription(label);
    f.setOnClickListener(v -> action.run());
    f.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    return f;
  }

  private void showBadge(TextView badge, int count) {
    if (badge == null) return;
    badge.setText("");
    badge.setContentDescription(count > 0 ? count + I18n.t(" mục chưa xem") : null);
    badge.setVisibility(count > 0 ? View.VISIBLE : View.GONE);
  }

  private void refreshBadges() {
    if (me == null) return;
    final String accountId = me.optString("id");
    if (!badgeAccount.equals(accountId)) { badgeAccount = accountId; badgesAt = 0; inboxCount = 0; bellCount = 0; noticeWatermark = System.currentTimeMillis(); }
    if (System.currentTimeMillis() - badgesAt < 10000) return;
    badgesAt = System.currentTimeMillis();
    api.call("GET", "/api/notifications", null, (d, e, s) -> {
      if (e != null || d == null || me == null || !accountId.equals(me.optString("id"))) return;
      JSONArray rows = d.optJSONArray("notifications");
      int inbox = 0, bell = 0, friends = 0;
      long watermark = noticeWatermark;
      JSONObject newest = null;
      for (int i = 0; rows != null && i < rows.length(); i++) {
        JSONObject n = rows.optJSONObject(i);
        if (n.optInt("seen") != 0) continue;
        String k = n.optString("kind");
        if (n.optLong("created") > watermark) { watermark = n.optLong("created"); newest = n; }
        if (k.equals("message") || k.equals("group_message")) inbox++; else bell++;
      }
      noticeWatermark = watermark;
      if (newest != null && !stopped && getSharedPreferences("kinnect_notifications", 0).getBoolean("enabled", true)) {
        String kind = newest.optString("kind");
        String preference = kind.equals("message") || kind.equals("group_message") ? "messages" : kind.startsWith("friend_") ? "friends" : "posts";
        if (getSharedPreferences("kinnect_notifications", 0).getBoolean(preference, true)) {
          JSONObject actor = newest.optJSONObject("actor");
          say((actor == null ? "Kinnect" : actor.optString("name")) + noticeText(kind));
        }
      }
      inboxCount = inbox;
      bellCount = bell;
      friends = d.optBoolean("friendRequestsPending") ? 1 : 0;
      friendsCount = friends;
      showBadge(inboxBadge, inbox);
      showBadge(bellBadge, bell);
      showBadge(friendsBadge, friends);
    });
  }

  private void loadAvatarInto(JSONObject u, final ImageView image) {
    String path = u == null ? "" : u.optString("avatar", "");
    if (path.isEmpty() || path.equals("null")) return;
    if(path.startsWith("data:image/")){try{byte[] bytes=android.util.Base64.decode(path.substring(path.indexOf(',')+1),android.util.Base64.DEFAULT);image.setImageBitmap(BitmapFactory.decodeByteArray(bytes,0,bytes.length));}catch(Exception ignored){}return;}
    api.image(path, bytes -> {
      if (bytes == null || isDestroyed()) return;
      Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
      if (b != null) image.setImageBitmap(b);
    });
  }

  // Chip kiểu web: viền mảnh, nền trắng; đang chọn → nền tím nhạt chữ tím (soft) hoặc tím đặc (solid)
  private TextView webChip(String text, boolean active, boolean solid, Runnable action) {
    TextView t = label(text, 14, active ? (solid ? WHITE : ACCENT) : TEXT);
    t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
    t.setGravity(Gravity.CENTER);
    t.setPadding(dp(16), 0, dp(16), 0);
    GradientDrawable g = background(active ? (solid ? ACCENT : PRIMARY_SOFT) : CARD, 999);
    if (!active) g.setStroke(1, LINE);
    t.setBackground(g);
    t.setOnClickListener(v -> action.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, dp(38));
    p.setMargins(0, dp(4), dp(8), dp(4));
    t.setLayoutParams(p);
    return t;
  }

  private View hscroll(LinearLayout row) {
    HorizontalScrollView s = new HorizontalScrollView(this);
    s.setHorizontalScrollBarEnabled(false);
    s.addView(row);
    return s;
  }

  private TextView sectionLabel(String text) {
    TextView t = label(text, WebDesign.SECTION, TEXT);
    t.setTypeface(null, Typeface.BOLD);
    t.setPadding(dp(4), dp(14), 0, dp(6));
    return t;
  }

  private View divider() {
    View v = new View(this);
    v.setBackgroundColor(LINE);
    v.setLayoutParams(new LinearLayout.LayoutParams(-1, 1));
    return v;
  }


  private void accountHeader(String title, Runnable back) {
    shell("", true);
    subBack = back;
    LinearLayout heading = row();
    FrameLayout arrow = new FrameLayout(this);
    arrow.addView(icon("back", 20, TEXT), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    arrow.setContentDescription(I18n.t("Quay lại"));
    arrow.setOnClickListener(v -> back.run());
    heading.addView(arrow, new LinearLayout.LayoutParams(dp(36), dp(40)));
    TextView text = label(title, 17, TEXT);
    text.setTypeface(null, Typeface.BOLD);
    heading.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    content.addView(heading);
  }

  private View accountRow(String glyph, String title, String subtitle, Runnable action) {
    LinearLayout row = row();
    row.setPadding(dp(4), dp(12), dp(4), dp(12));
    FrameLayout badge = new FrameLayout(this);
    badge.setBackground(background(PRIMARY_SOFT, 12));
    badge.addView(icon(glyph, 20, ACCENT), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    row.addView(badge, new LinearLayout.LayoutParams(dp(36), dp(36)));
    LinearLayout text = column();
    text.setPadding(dp(12), 0, dp(8), 0);
    text.addView(label(title, WebDesign.LABEL, TEXT));
    if (subtitle != null && !subtitle.isEmpty()) text.addView(label(subtitle, WebDesign.META, MUTED));
    row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    row.addView(icon("chevron-right", 18, MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
    row.setOnClickListener(v -> action.run());
    return row;
  }

  private boolean storeReturning;
  private void openStore(){storeReturning=true;startActivity(new Intent(this,StoreActivity.class));}
  private void meMenu() {
    remember("account", () -> meMenu());
    shell(I18n.t("Tài khoản"), true);
    LinearLayout profile = row();
    profile.setPadding(dp(16), dp(16), dp(14), dp(16));
    GradientDrawable pg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { PRIMARY_SOFT, CARD });
    pg.setCornerRadius(dp(16));
    pg.setStroke(dp(1), LINE);
    profile.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf((ACCENT & 0x00ffffff) | 0x22000000), pg, null));
    avatar(me, profile, 52);
    LinearLayout text = column();
    text.setPadding(dp(14), 0, 0, 0);
    TextView n = label(me.optString("name"), 17, TEXT);
    n.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    text.addView(n);
    text.addView(label("@" + me.optString("username"), 13, MUTED));
    profile.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    profile.addView(icon("chevron_right", 18, MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
    profile.setContentDescription(I18n.t("Trang cá nhân"));
    profile.setOnClickListener(v -> navigate("profile"));
    LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(-1, -2);
    pp.bottomMargin = dp(14);
    content.addView(profile, pp);

    if (me.optString("role").equals("admin")) {
      LinearLayout admin = settingsGroup();
      groupRow(admin, "shield_check", I18n.t("Bảng quản trị"), false, () -> admin());
    }
    LinearLayout main = settingsGroup();
    groupRow(main,"wallet",I18n.t("Ví Kinnect"),false,()->startActivity(new Intent(this,WalletActivity.class)));
    groupRow(main,"shopping_bag",I18n.t("Cửa hàng Kinnect"),false,()->openStore());
    groupRow(main, "settings", I18n.t("Cài đặt và quyền riêng tư"), false, () -> settings());
    groupRow(main, "shield_check", I18n.t("Bảo mật và đăng nhập"), false, () -> securityScreen());
    groupRow(main, "bell", I18n.t("Cài đặt thông báo"), false, () -> nativeNotificationSettings());
    groupRow(main, "moon", I18n.t("Giao diện"), false, () -> appearanceScreen());
    groupRow(main, "circle_help", I18n.t("Trợ giúp và hỗ trợ"), false, () -> helpScreen());
    groupRow(main, "about_info", I18n.t("Giới thiệu Kinnect"), false, this::aboutScreen);
    LinearLayout end = settingsGroup();
    groupRow(end, "key_round", I18n.t("Đổi mật khẩu"), false, () -> changePassword());
    groupRow(end, "log_out", I18n.t("Đăng xuất"), true, () -> confirm(I18n.t("Đăng xuất khỏi Kinnect?"), () -> request("POST", "/api/logout", json(), data -> {
      if (calls != null) { calls.close(); calls = null; }
      KinnectService.stop(this);
      api.clear(); mediaCallGate.clear();mediaCallBlocked=false;me = null; intro();
    })));
    TextView foot = label(I18n.t("Kinnect · Kết nối theo cách của bạn."), 12, MUTED);
    foot.setGravity(Gravity.CENTER);
    foot.setPadding(0, dp(8), 0, 0);
    content.addView(foot, new LinearLayout.LayoutParams(-1, -2));
  }

  private LinearLayout settingsGroup() {
    LinearLayout g = column();
    g.setPadding(dp(4), dp(4), dp(4), dp(4));
    GradientDrawable bg = background(CARD, 16);
    bg.setStroke(dp(1), LINE);
    g.setBackground(bg);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.bottomMargin = dp(12);
    content.addView(g, p);
    return g;
  }

  private FrameLayout settingsIcon(String name, int tint) {
    FrameLayout tile = new FrameLayout(this);
    tile.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
    tile.setBackground(background((tint & 0x00ffffff) | 0x1f000000, 12));
    ImageView image = new ImageView(this);
    if (name.equals("group_three") || name.equals("menu_lines") || name.equals("about_info") || name.equals("bell_ring") || name.equals("user_search") || name.equals("distance_pins") || name.equals("activity_status") || name.equals("image_lock") || name.equals("user_block") || name.equals("post_heart") || name.equals("location_off")) {
      image.setImageDrawable(new SettingsGlyph(name, tint, Color.rgb((Color.red(tint)*31+Color.red(CARD)*224)/255,(Color.green(tint)*31+Color.green(CARD)*224)/255,(Color.blue(tint)*31+Color.blue(CARD)*224)/255)));
    } else { android.graphics.drawable.Drawable drawable=WebIcons.load(this,name); drawable.setTint(tint); image.setImageDrawable(drawable); }
    tile.addView(image,new FrameLayout.LayoutParams(dp(24),dp(24),Gravity.CENTER));
    return tile;
  }

  /** Crisp scalable paths: no emoji fonts or bitmap scaling. Same 24-unit grid and rounded 1.8-unit stroke. */
  private static final class SettingsGlyph extends android.graphics.drawable.Drawable {
    private final String kind; private final Paint pen=new Paint(Paint.ANTI_ALIAS_FLAG); private final int tint, back;
    SettingsGlyph(String kind,int tint,int back){this.kind=kind;this.tint=tint;this.back=back;}
    private void line(Canvas c,float x,float y,float ex,float ey){c.drawLine(x,y,ex,ey,pen);}
    private void pin(Canvas c,float x,float y){Path p=new Path();p.moveTo(x,y+7);p.cubicTo(x-1,y+5,x-3,y+3,x-3,y+1);p.cubicTo(x-3,y-3,x+3,y-3,x+3,y+1);p.cubicTo(x+3,y+3,x+1,y+5,x,y+7);c.drawPath(p,pen);c.drawCircle(x,y+.5f,.65f,pen);}
    private void person(Canvas c){c.drawCircle(9,6,3,pen);Path p=new Path();p.moveTo(3,19);p.cubicTo(3,11,15,11,15,19);c.drawPath(p,pen);}
    private void badge(Canvas c){pen.setStyle(Paint.Style.FILL);pen.setColor(back);c.drawCircle(17.5f,17.5f,6,pen);pen.setStyle(Paint.Style.STROKE);pen.setColor(tint);}
    public void draw(Canvas canvas){
      Rect b=getBounds();int save=canvas.save();canvas.translate(b.left,b.top);canvas.scale(b.width()/24f,b.height()/24f);
      pen.setColor(tint);pen.setStyle(Paint.Style.STROKE);pen.setStrokeWidth(1.8f);pen.setStrokeCap(Paint.Cap.ROUND);pen.setStrokeJoin(Paint.Join.ROUND);
      if(kind.equals("group_three")){pen.setStrokeWidth(1.65f);canvas.drawCircle(12,6.5f,2.6f,pen);canvas.drawCircle(4.5f,9,2,pen);canvas.drawCircle(19.5f,9,2,pen);Path bodies=new Path();bodies.moveTo(1.5f,19);bodies.lineTo(1.5f,17);bodies.cubicTo(1.5f,13,5,12.5f,7,15);bodies.moveTo(22.5f,19);bodies.lineTo(22.5f,17);bodies.cubicTo(22.5f,13,19,12.5f,17,15);bodies.moveTo(7.5f,21);bodies.lineTo(7.5f,17);bodies.cubicTo(7.5f,11.5f,16.5f,11.5f,16.5f,17);bodies.lineTo(16.5f,21);canvas.drawPath(bodies,pen);}
      else if(kind.equals("menu_lines")){line(canvas,4,6,20,6);line(canvas,4,12,20,12);line(canvas,4,18,20,18);}
      else if(kind.equals("about_info")){canvas.drawCircle(12,12,9,pen);line(canvas,12,10.5f,12,17);pen.setStyle(Paint.Style.FILL);canvas.drawCircle(12,7,1,pen);}
      else if(kind.equals("bell_ring")){Path bell=new Path();bell.moveTo(5,17);bell.lineTo(7,14);bell.lineTo(7,9);bell.cubicTo(7,2,17,2,17,9);bell.lineTo(17,14);bell.lineTo(19,17);bell.close();canvas.drawPath(bell,pen);Path clapper=new Path();clapper.moveTo(10,20);clapper.quadTo(12,22,14,20);canvas.drawPath(clapper,pen);line(canvas,3,6,2,9);line(canvas,21,6,22,9);}
      else if(kind.equals("user_search")){person(canvas);badge(canvas);canvas.drawCircle(16.5f,16.5f,3.5f,pen);line(canvas,19,19,22,22);}
      else if(kind.equals("distance_pins")){pin(canvas,5,5);pin(canvas,19,5);line(canvas,4,19,6,19);line(canvas,10,19,12,19);line(canvas,16,19,18,19);line(canvas,3,17,3,21);line(canvas,21,17,21,21);}
      else if(kind.equals("activity_status")){canvas.drawCircle(12,12,8,pen);pen.setStyle(Paint.Style.FILL);canvas.drawCircle(12,12,3,pen);pen.setColor(back);canvas.drawCircle(18,6,4,pen);pen.setColor(tint);canvas.drawCircle(18,6,2.5f,pen);}
      else if(kind.equals("image_lock")){canvas.drawRoundRect(3,3,21,21,3,3,pen);canvas.drawCircle(8,8,1.5f,pen);Path p=new Path();p.moveTo(4,17);p.lineTo(10,11);p.lineTo(14,15);canvas.drawPath(p,pen);badge(canvas);canvas.drawRoundRect(13,16,22,22,1.3f,1.3f,pen);Path lock=new Path();lock.moveTo(15,16);lock.lineTo(15,14);lock.cubicTo(15,10.5f,20,10.5f,20,14);lock.lineTo(20,16);canvas.drawPath(lock,pen);}
      else if(kind.equals("user_block")){person(canvas);badge(canvas);canvas.drawCircle(17.5f,17.5f,4.5f,pen);line(canvas,14.3f,20.7f,20.7f,14.3f);}
      else if(kind.equals("post_heart")){canvas.drawRoundRect(3,3,21,21,2,2,pen);line(canvas,7,8,17,8);line(canvas,7,12,12,12);badge(canvas);Path heart=new Path();heart.moveTo(17.5f,21.5f);heart.cubicTo(9,16,14,11,17.5f,15);heart.cubicTo(21,11,26,16,17.5f,21.5f);canvas.drawPath(heart,pen);}
      else if(kind.equals("location_off")){Path p=new Path();p.moveTo(12,22);p.cubicTo(9,18,5,14,5,9);p.cubicTo(5,-.5f,19,-.5f,19,9);p.cubicTo(19,14,15,18,12,22);canvas.drawPath(p,pen);canvas.drawCircle(12,9,2.5f,pen);line(canvas,2,2,22,22);}
      canvas.restoreToCount(save);
    }
    public void setAlpha(int alpha){pen.setAlpha(alpha);invalidateSelf();}
    public void setColorFilter(ColorFilter filter){pen.setColorFilter(filter);invalidateSelf();}
    public int getOpacity(){return PixelFormat.TRANSLUCENT;}
  }

  private void groupRow(LinearLayout group, String iconName, String title, boolean danger, Runnable action) {
    if (group.getChildCount() > 0) {
      View line = new View(this);
      line.setBackgroundColor(LINE);
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, 1);
      lp.setMargins(dp(60), 0, dp(12), 0);
      group.addView(line, lp);
    }
    int tint = danger ? WebDesign.DANGER[WebTheme.isDark(this) ? 1 : 0] : ACCENT;
    LinearLayout r = row();
    r.setPadding(dp(10), 0, dp(12), 0);
    r.setBackground(pressable(CARD, 12));
    r.addView(settingsIcon(iconName,tint),new LinearLayout.LayoutParams(dp(38),dp(38)));
    TextView t = label(title, 14, danger ? tint : TEXT);
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    t.setPadding(dp(12), 0, 0, 0);
    r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
    if (!danger) r.addView(icon("chevron_right", 16, MUTED), new LinearLayout.LayoutParams(dp(16), dp(16)));
    r.setContentDescription(title);
    r.setOnClickListener(v -> action.run());
    r.setMinimumHeight(dp(56));
    r.setPadding(dp(10),dp(8),dp(12),dp(8));
    group.addView(r, new LinearLayout.LayoutParams(-1, -2));
  }

  private void appearanceScreen() {
    accountHeader(I18n.t("Giao diện"), () -> meMenu());
    String selected = getSharedPreferences("kinnect_settings", 0).getString("theme", "auto");
    String[][] choices = { { "auto", "monitor", "Theo hệ thống" }, { "light", "sun", "Sáng" }, { "dark", "moon", "Tối" } };
    LinearLayout list = settingsGroup();
    for (final String[] choice : choices) groupRow(list, selected.equals(choice[0]) ? "circle_check" : choice[1], choice[2], false, () -> {
      getSharedPreferences("kinnect_settings", 0).edit().putString("theme", choice[0]).apply();
      recreate();
    });
  }


  private void securityScreen() {
    accountHeader(I18n.t("Bảo mật và đăng nhập"), () -> meMenu());
    LinearLayout panel = settingsGroup();
    groupRow(panel, "key_round", I18n.t("Đổi mật khẩu"), false, () -> changePassword());
    groupRow(panel, "mail", I18n.t("Email khôi phục"), false, () -> recoveryEmailScreen());
    groupRow(panel, "monitor", I18n.t("Thiết bị đăng nhập"), false, () -> sessionsScreen());
    groupRow(panel, "circle_help", I18n.t("Hỗ trợ tài khoản và khôi phục"), false, () -> openPublicPage("support"));
  }


  private void sessionsScreen() {
    accountHeader(I18n.t("Thiết bị đăng nhập"), () -> securityScreen());
    content.addView(label(I18n.t("Thu hồi phiên để đăng xuất thiết bị khác và huỷ đăng nhập nhanh của thiết bị đó."), 14, MUTED));
    request("GET", "/api/me/sessions", null, data -> {
      JSONArray sessions = data.optJSONArray("sessions");
      for (int i = 0; sessions != null && i < sessions.length(); i++) {
        JSONObject session = sessions.optJSONObject(i);
        LinearLayout panel = card();
        panel.addView(label(session.optString("label"), 14, TEXT));
        panel.addView(label(session.optBoolean("current") ? I18n.t("Thiết bị hiện tại") : I18n.t("Hết hạn ") + new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()).format(new Date(session.optLong("expires"))), 12, MUTED));
        if (!session.optBoolean("current")) panel.addView(button(I18n.t("Đăng xuất thiết bị"), () -> confirm(I18n.t("Đăng xuất thiết bị này?"), () -> request("DELETE", "/api/me/sessions/" + session.optString("id"), json(), d -> sessionsScreen()))));
      }
    });
  }

  private void recoveryEmailScreen() {
    accountHeader(I18n.t("Email khôi phục"), () -> securityScreen());
    request("GET", "/api/recovery/email", null, data -> {
      LinearLayout panel = card();
      panel.addView(label(data.isNull("email") ? I18n.t("Chưa xác minh email khôi phục.") : I18n.t("Email đã xác minh: ") + data.optString("email"), 14, MUTED));
      panel.addView(fieldLabel(I18n.t("Email khôi phục")));
      EditText email = input(panel, "Email", "", false);
      email.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
      panel.addView(fieldLabel(I18n.t("Mật khẩu hiện tại")));
      EditText password = input(panel, I18n.t("Mật khẩu hiện tại"), "", false);
      password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
      panel.addView(primary(I18n.t("Gửi mã xác minh"), () -> request("POST", "/api/recovery/email/start", json("email", email.getText().toString(), "password", password.getText().toString()), result -> {
        panel.removeAllViews();
        panel.addView(label(I18n.t("Nhập mã xác minh trong email của bạn."), 14, TEXT));
        EditText code = input(panel, I18n.t("Mã xác minh"), "", false);
        code.setInputType(InputType.TYPE_CLASS_NUMBER);
        panel.addView(primary(I18n.t("Xác minh"), () -> request("POST", "/api/recovery/email/verify", json("challengeId", result.optString("challengeId"), "code", code.getText().toString()), verified -> { say(I18n.t("Đã xác minh email.")); recoveryEmailScreen(); })));
      })));
    });
  }

  private void nativeNotificationSettings() {
    accountHeader(I18n.t("Cài đặt thông báo"), () -> meMenu());
    LinearLayout panel = settingsGroup();
    for (final String[] choice : new String[][] { { "enabled", "Hiện thông báo", "bell_ring" }, { "messages", "Tin nhắn", "message_square" }, { "friends", "Lời mời kết bạn", "user_plus" }, { "posts", "Bài viết và tương tác", "post_heart" } }) {
      if (panel.getChildCount() > 0) {
        View line = new View(this);
        line.setBackgroundColor(LINE);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, 1);
        lp.setMargins(dp(60), 0, dp(12), 0);
        panel.addView(line, lp);
      }
      LinearLayout r = row();
      r.setPadding(dp(10), dp(8), dp(8), dp(8));
      r.setMinimumHeight(dp(64));
      r.addView(settingsIcon(choice[2], ACCENT),new LinearLayout.LayoutParams(dp(38),dp(38)));
      TextView t = label(I18n.t(choice[1]), 15, TEXT);
      t.setPadding(dp(12),0,dp(8),0);
      t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
      r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
      final Switch toggle = new Switch(this);
      toggle.setThumbTintList(new android.content.res.ColorStateList(new int[][] { { android.R.attr.state_checked }, {} }, new int[] { ACCENT, 0xffffffff }));
      toggle.setTrackTintList(new android.content.res.ColorStateList(new int[][] { { android.R.attr.state_checked }, {} }, new int[] { (ACCENT & 0x00ffffff) | 0x66000000, LINE }));
      toggle.setContentDescription(I18n.t(choice[1]));
      toggle.setChecked(getSharedPreferences("kinnect_notifications", 0).getBoolean(choice[0], true));
      toggle.setOnCheckedChangeListener((view, checked) -> getSharedPreferences("kinnect_notifications", 0).edit().putBoolean(choice[0], checked).apply());
      toggle.setMinimumWidth(dp(48));toggle.setMinimumHeight(dp(48));
      r.addView(toggle,new LinearLayout.LayoutParams(-2,-2));
      r.setOnClickListener(v -> toggle.toggle());
      panel.addView(r, new LinearLayout.LayoutParams(-1, -2));
    }
  }


  private void openPublicPage(String page) {
    try { startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://kinnect.io.vn/" + page))); }
    catch (Exception error) { say(I18n.t("Chưa mở được trang hỗ trợ.")); }
  }

  private String installedVersion(){
    try{android.content.pm.PackageInfo info=getPackageManager().getPackageInfo(getPackageName(),0);return info.versionName;}
    catch(android.content.pm.PackageManager.NameNotFoundException error){return "Chưa đọc được phiên bản";}
  }

  private void settingsDetailRow(LinearLayout group,String glyph,String title,String subtitle,Runnable action){
    groupRow(group,glyph,title,false,action);
    LinearLayout row=(LinearLayout)group.getChildAt(group.getChildCount()-1);
    TextView heading=(TextView)row.getChildAt(1);row.removeView(heading);heading.setPadding(0,0,0,0);
    LinearLayout labels=column();labels.setPadding(dp(12),0,dp(8),0);labels.addView(heading,new LinearLayout.LayoutParams(-1,-2));
    TextView detail=label(subtitle,12,MUTED);detail.setPadding(0,dp(3),0,0);labels.addView(detail);
    row.addView(labels,1,new LinearLayout.LayoutParams(0,-2,1));row.setMinimumHeight(dp(68));row.setContentDescription(title+". "+subtitle);
  }

  private void aboutInfoRow(LinearLayout group,String glyph,String title,String value){
    if(group.getChildCount()>0){View line=new View(this);line.setBackgroundColor(LINE);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,1);lp.setMargins(dp(60),0,dp(12),0);group.addView(line,lp);}
    LinearLayout r=row();r.setPadding(dp(10),dp(10),dp(12),dp(10));r.setMinimumHeight(dp(68));
    r.addView(settingsIcon(glyph,ACCENT),new LinearLayout.LayoutParams(dp(38),dp(38)));
    LinearLayout labels=column();labels.setPadding(dp(12),0,0,0);labels.addView(label(title,12,MUTED));
    TextView data=label(value,15,TEXT);data.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));data.setTextIsSelectable(true);labels.addView(data);
    r.addView(labels,new LinearLayout.LayoutParams(0,-2,1));group.addView(r,new LinearLayout.LayoutParams(-1,-2));
  }

  private void aboutScreen(){
    accountHeader(I18n.t("Giới thiệu Kinnect"),this::meMenu);
    LinearLayout brand=column();brand.setGravity(Gravity.CENTER_HORIZONTAL);brand.setPadding(dp(16),dp(20),dp(16),dp(24));
    ImageView logo=new ImageView(this);logo.setImageDrawable(getApplicationInfo().loadIcon(getPackageManager()));logo.setContentDescription("Logo Kinnect");
    brand.addView(logo,new LinearLayout.LayoutParams(dp(72),dp(72)));
    TextView name=label("Kinnect",22,ACCENT);name.setGravity(Gravity.CENTER);name.setTypeface(null,Typeface.BOLD);name.setPadding(0,dp(12),0,dp(6));brand.addView(name,new LinearLayout.LayoutParams(-1,-2));
    TextView slogan=label(I18n.t("Kết nối theo cách của bạn."),13,MUTED);slogan.setGravity(Gravity.CENTER);brand.addView(slogan);
    content.addView(brand,new LinearLayout.LayoutParams(-1,-2));
    LinearLayout details=settingsGroup();
    aboutInfoRow(details,"user_round",I18n.t("Tác giả"),I18n.t("Vũ Ngọc Ánh"));
    LinearLayout links=settingsGroup();
    groupRow(links,"globe",I18n.t("Về Kinnect"),false,()->nativeDocument("index"));
    settingsDetailRow(links,"download",I18n.t("Kiểm tra cập nhật"),I18n.t("Đang dùng ")+installedVersion(),()->ApkUpdates.check(this));
  }

  private void nativeDocument(String page){nativeDocument(page,this::aboutScreen);}
  private void nativeDocument(String page,Runnable back){
    String title="Thông tin Kinnect";String[][] rows=new String[0][];
    if(page.equals("index")){title="Về Kinnect";rows=new String[][]{
      {"h1","Kết nối đúng gu. Sống đúng mình."},
      {"p","Một lời chào, một người cùng tần số, một nơi để bạn thoải mái là chính mình. Kinnect là không gian kết bạn, trò chuyện và chia sẻ dành cho cộng đồng LGBT."},
      {"p","Android 8+ · iPhone qua Safari · Máy tính qua trình duyệt"},
      {"p","Tính năng"},
      {"h2","Ít ngại ngùng. Nhiều đồng điệu."},
      {"h3","Gặp người cùng gu"},
      {"p","Khám phá hồ sơ, sở thích và người quanh đây để tìm điểm chung bắt đầu câu chuyện."},
      {"h3","Trò chuyện thật gần"},
      {"p","Nhắn tin riêng, tạo nhóm, gọi thoại và video, xem ai đã đọc tin nhắn của bạn."},
      {"h3","Chia sẻ khoảnh khắc"},
      {"p","Bài viết, tin 24 giờ, video ngắn và livestream để cộng đồng hiểu bạn hơn."},
      {"p","Cộng đồng"},
      {"h2","Mọi sắc màu đều có chỗ riêng."},
      {"p","Không cần một phiên bản hoàn hảo để bắt đầu. Chỉ cần bạn, những điều bạn thích và một chút tò mò về người ở phía bên kia."},
      {"h3","Kết nối theo cách của bạn"},
      {"p","Chọn sở thích, viết giới thiệu và tự quyết định có xuất hiện trong Khám phá hay không."},
      {"h3","Ranh giới được tôn trọng"},
      {"p","Tùy chọn nhận tin nhắn, ảnh riêng tư cần cấp quyền, chặn và báo cáo dễ dàng."},
      {"h3","Bắt đầu từ sự tử tế"},
      {"p","Tôn trọng danh tính, quyền riêng tư và sự đồng thuận của nhau."},
      {"p","Hỏi đáp"},
      {"h2","Những điều cần biết trước lời chào đầu tiên."},
      {"p","Kinnect hướng đến người từ 18 tuổi thuộc cộng đồng LGBT và những người tôn trọng sự đa dạng. Mọi kết nối cần sự đồng thuận và tôn trọng lẫn nhau."},
      {"p","Kinnect đang ở giai đoạn thử nghiệm. Bạn có thể dùng bản web trên máy tính và iPhone, hoặc cài bản Android qua trang phát hành GitHub khi có bản sẵn sàng. Ứng dụng chưa phát hành chính thức trên Google Play. Xem trang Hỗ trợ để biết cách cài và cập nhật."},
      {"p","Hồ sơ, bài viết và tin nhắn riêng được lưu tại máy chủ Kinnect do chủ dự án vận hành. Hiện chưa có mã hóa đầu cuối. Bạn có thể điều chỉnh quyền xuất hiện trong Khám phá và quyền nhận tin nhắn trong Hồ sơ."},
      {"p","Có. Bạn có thể chặn hoặc báo cáo từ hồ sơ, mục Khám phá và các nội dung được hỗ trợ. Báo cáo được xử lý thủ công; bản thử nghiệm chưa có đội kiểm duyệt liên tục 24/7."},
      {"p","Chưa. Phòng live và chat đã có trong bản thử nghiệm, nhưng video giữa các mạng khác nhau vẫn cần bổ sung hạ tầng chuyển tiếp và kiểm thử trên thiết bị thật."},
      {"h2","Lời chào tiếp theo bắt đầu từ đây."},
      {"p","Mang theo sự tò mò. Còn lời chào, để mình bắt đầu."},
      {"p","Bản thử nghiệm · Android, iPhone và máy tính · Dành cho người từ 18 tuổi"}
    };}
    if(page.equals("privacy")||page.equals("community")||page.equals("child-safety")){title=PolicyText.title(page);rows=PolicyText.rows(page);}
    accountHeader(I18n.t(title),back);
    LinearLayout panel=null;
    for(String[] part:rows){
      boolean heading=part[0].startsWith("h");
      if(heading||panel==null){panel=card();panel.setPadding(dp(16),dp(12),dp(16),dp(12));}
      TextView text=label(I18n.t(part[1]),heading?17:14,heading?TEXT:MUTED);
      if(heading)text.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));
      else{text.setLineSpacing(dp(4),1.1f);text.setTextIsSelectable(true);}
      panel.addView(text,new LinearLayout.LayoutParams(-1,-2));
    }
  }

  private void helpScreen() {
    accountHeader(I18n.t("Trợ giúp và hỗ trợ"), () -> meMenu());
    LinearLayout panel = settingsGroup();
    groupRow(panel, "flag", I18n.t("Báo sự cố"), false, () -> report("app", me.optString("id")));
    groupRow(panel, "message_square", I18n.t("Trung tâm hỗ trợ"), false, () -> request("GET","/api/support",null,data->{JSONObject contact=data.optJSONObject("user");if(contact!=null)chat(contact);else new Sheet(this).setTitle(I18n.t("Hỗ trợ Kinnect")).setMessage(I18n.t("Liên hệ riêng Mr Ánh: anhvn53@wru.vn. Không gửi mật khẩu hoặc OTP.")).setPositiveButton(I18n.t("Đóng"),null).show();}));
    groupRow(panel, "shield_check", I18n.t("Chính sách quyền riêng tư"), false, () -> nativeDocument("privacy",this::helpScreen));
    groupRow(panel, "users_round", I18n.t("Quy tắc cộng đồng"), false, () -> nativeDocument("community",this::helpScreen));
    groupRow(panel,"shield_check",I18n.t("An toàn trẻ em"),false,()->nativeDocument("child-safety",this::helpScreen));
    groupRow(panel,"file_text",I18n.t("Giấy phép phần mềm"),false,()->showSoftwareLicenses());
    panel.addView(label(I18n.t("Mr Ánh · Hỗ trợ và quyền riêng tư: anhvn53@wru.vn"),12,MUTED));
  }


  private void showSoftwareLicenses(){accountHeader(I18n.t("Giấy phép phần mềm"),()->helpScreen());LinearLayout panel=card();try{java.io.InputStream stream=getAssets().open("THIRD_PARTY_NOTICES.txt");String licenses=new String(NativeApi.read(stream,300000),"UTF-8");stream.close();TextView content=label(licenses,12,TEXT);content.setTextIsSelectable(true);panel.addView(content);}catch(Exception error){panel.addView(label("Xem https://app.kinnect.io.vn/third-party-notices.txt",14,TEXT));}}

  // Thông báo ngắn dạng "toast" nổi giống web (không chiếm chỗ trên màn).
  private void say(String text) {
    text=I18n.t(text);
    if (notice != null) notice.setText(text);
    if (text == null || text.trim().isEmpty()) return;
    final ViewGroup host = findViewById(android.R.id.content);
    if (host == null) { Toast.makeText(this, text, Toast.LENGTH_SHORT).show(); return; }
    if (toastView != null) host.removeView(toastView);
    String lower = text.toLowerCase(Locale.ROOT);
    boolean error = lower.startsWith("không") || lower.contains("lỗi") || lower.startsWith("cần") || lower.startsWith("vui lòng") || lower.contains("chưa") || lower.startsWith("nhập") || lower.contains("tối thiểu");
    boolean ok = lower.startsWith("đã");
    int tint = error ? WebDesign.DANGER[WebTheme.isDark(this) ? 1 : 0] : ACCENT;
    LinearLayout pill = row();
    pill.setPadding(dp(12), dp(10), dp(16), dp(10));
    GradientDrawable bg = background(CARD, 16);
    bg.setStroke(dp(1), LINE);
    pill.setBackground(bg);
    pill.setElevation(dp(12));
    FrameLayout mark = new FrameLayout(this);
    mark.setBackground(background((tint & 0x00ffffff) | 0x1f000000, 99));
    mark.addView(icon(ok ? "check" : error ? "circle_help" : "bell", 16, tint), new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
    pill.addView(mark, new LinearLayout.LayoutParams(dp(30), dp(30)));
    TextView msg = label(text, 14, TEXT);
    msg.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    msg.setPadding(dp(10), 0, 0, 0);
    msg.setMaxLines(3);
    pill.addView(msg, new LinearLayout.LayoutParams(-2, -2));
    FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    android.view.WindowInsets insets = host.getRootWindowInsets();
    lp.topMargin = (insets == null ? dp(24) : insets.getSystemWindowInsetTop()) + dp(64);
    lp.leftMargin = dp(16);
    lp.rightMargin = dp(16);
    host.addView(pill, lp);
    toastView = pill;
    pill.setAlpha(0f);
    pill.setTranslationY(-dp(16));
    pill.animate().alpha(1f).translationY(0).setDuration(200).start();
    final View shown = pill;
    pill.setOnClickListener(v -> v.animate().alpha(0f).setDuration(150).withEndAction(() -> host.removeView(v)).start());
    pill.postDelayed(() -> { if (shown.getParent() != null) shown.animate().alpha(0f).translationY(-dp(12)).setDuration(220).withEndAction(() -> { host.removeView(shown); if (toastView == shown) toastView = null; }).start(); }, error ? 3200 : 2400);
  }

  private View toastView;

  private JSONObject json(Object... values) {
    JSONObject obj = new JSONObject();
    try {
      for (int i = 0; i < values.length; i += 2) obj.put(
        String.valueOf(values[i]),
        values[i + 1]
      );
    } catch (JSONException e) {
      throw new IllegalArgumentException(e);
    }
    return obj;
  }

  private String encode(String v) {
    try {
      return URLEncoder.encode(v, "UTF-8");
    } catch (Exception e) {
      return "";
    }
  }

  private void request(String method, String path, JSONObject data, Done done) {
    request(method, path, data, done, () -> {});
  }

  private void request(String method, String path, JSONObject data, Done done, Runnable finished) {
    final int generation = screen;
    final UploadProgress upload=data!=null&&(data.optString("media").startsWith("data:")||data.optString("data").startsWith("data:"))?new UploadProgress(this):null;
    api.call(method, path, data, upload, (answer, error, status) -> {
      if(upload!=null)upload.close();
      if (isFinishing() || isDestroyed() || generation != screen) return;
      try {
        if (error != null) {
          if(status==428&&answer!=null&&!answer.optString("version").isEmpty()){
            new Sheet(this).setTitle(I18n.t("Thông báo sử dụng dữ liệu")).setMessage(I18n.t(error)).setPositiveButton(I18n.t("Tôi đồng ý"),(dialog,which)->request("POST","/api/me/privacy-consent",json("accepted",true,"version",answer.optString("version")),accepted->request(method,path,data,done,finished))).setNegativeButton(I18n.t("Để sau"),null).show();return;
          }
          if (status == 401 && me != null) {
            me = null;
            api.clear();
            auth(false);
          }
          say(error);
          return;
        }
        done.accept(answer);
      } catch (RuntimeException failure) {
        CrashLog.record(this, failure);
        say(I18n.t("Không hiển thị được nội dung. Hãy thử lại."));
      } finally {
        finished.run();
      }
    });
  }

  // Keep the draft until the server confirms it; a second tap cannot duplicate a pending send.
  private void submitText(EditText input, View send, String path, JSONObject payload, Done sent) {
    if (!send.isEnabled()) return;
    final String draft = input.getText().toString();
    if (draft.trim().isEmpty()) return;
    send.setEnabled(false);
    send.setAlpha(0.5f);
    request("POST", path, payload, data -> {
      if (input.getText().toString().equals(draft)) input.setText("");
      sent.accept(data);
    }, () -> { send.setEnabled(true); send.setAlpha(1f); });
  }

  private void auth(boolean register) {
    subBack = null;
    shell("", false);
    toolbar.setVisibility(View.GONE);
    if (root.getChildCount() > 1) root.getChildAt(1).setVisibility(View.GONE);
    root.setBackgroundColor(BG);
    getWindow().setStatusBarColor(BG);
    getWindow().setNavigationBarColor(BG);
    content.setPadding(0, 0, 0, dp(24));
    content.addView(authHero(), new LinearLayout.LayoutParams(-1, dp(88)));
    LinearLayout body = column();
    body.setPadding(dp(20), dp(10), dp(20), 0);
    content.addView(body);

    LinearLayout home = row();
    home.addView(icon("arrow_left", 18, TEXT), new LinearLayout.LayoutParams(dp(18), dp(18)));
    TextView homeText = label(I18n.t("Trang chủ"), 14, TEXT);
    homeText.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    homeText.setPadding(dp(8), 0, 0, 0);
    home.addView(homeText);
    home.setPadding(0, dp(8), dp(12), dp(8));
    home.setContentDescription(I18n.t("Về trang giới thiệu"));
    home.setOnClickListener(v -> { introPage = 0; intro(); });
    body.addView(home, new LinearLayout.LayoutParams(-2, -2));
    body.addView(button(I18n.t("Tiếng Việt / English"),()->languageMenu()));

    TextView title = label(register ? I18n.t("Bắt đầu kết nối của bạn.") : I18n.t("Chào bạn trở lại!"), 27, TEXT);
    title.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    title.setPadding(0, dp(10), 0, dp(2));
    body.addView(title);
    TextView caption=welcomeText(register?I18n.t("Tạo tài khoản để chia sẻ và gặp người cùng tần số."):I18n.t("Đăng nhập để tiếp tục những kết nối của bạn."),14,MUTED,false);caption.setPadding(0,dp(6),0,dp(14));body.addView(caption);

    final LinearLayout extras = column();
    LinearLayout saved = content;
    content = extras;
    authExtras(register);
    content = saved;

    final EditText username = authField(body, "user_round", I18n.t("Tên đăng nhập"), false);
    username.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
    username.setTypeface(Typeface.DEFAULT);
    final EditText name = register ? authField(body, "pencil", I18n.t("Tên hiển thị"), false) : null;
    final EditText password = authField(body, "lock_keyhole", I18n.t("Mật khẩu (từ 6 ký tự)"), true);

    final CheckBox agree = new CheckBox(this);
    final CheckBox remember = new CheckBox(this);
    remember.setChecked(true);
    LinearLayout options = row();
    CheckBox box = register ? agree : remember;
    box.setText(register ? I18n.t("Tôi đủ 18 tuổi và đồng ý Quy tắc cộng đồng") : I18n.t("Ghi nhớ"));
    box.setTextColor(TEXT);
    box.setTextSize(13);
    if(register)box.setMaxLines(3);
    box.setButtonTintList(android.content.res.ColorStateList.valueOf(ACCENT));
    options.addView(box, new LinearLayout.LayoutParams(0, -2, 1));
    if (!register) {
      TextView forgotLink = label(I18n.t("Quên mật khẩu?"), 13, ACCENT);
      forgotLink.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
      forgotLink.setPadding(dp(8), dp(10), 0, dp(10));
      forgotLink.setOnClickListener(v -> forgot());
      options.addView(forgotLink);
    }
    body.addView(options, new LinearLayout.LayoutParams(-1, -2));

    final LinearLayout submit = authButton(register ? "user_plus" : "log_in", register ? I18n.t("Tạo tài khoản") : I18n.t("Đăng nhập"), true);
    submit.setOnClickListener(v -> {
      if (username.length() == 0) { say(I18n.t("Nhập tên đăng nhập.")); return; }
      if (password.length() < 6) { say(I18n.t("Mật khẩu tối thiểu 6 ký tự.")); return; }
      if (register && !agree.isChecked()) { say(I18n.t("Vui lòng xác nhận bạn đủ 18 tuổi.")); return; }
      submit.setEnabled(false);
      submit.setAlpha(0.7f);
      final int generation = screen;
      api.call("POST", register ? "/api/register" : "/api/login",
        json("username", username.getText().toString().trim(), "password", password.getText().toString(), "name", name == null ? "" : name.getText().toString(), "agree18", agree.isChecked(), "remember", register || remember.isChecked()),
        (data, error, status) -> {
          if (generation != screen || isDestroyed()) return;
          submit.setEnabled(true);
          submit.setAlpha(1f);
          password.setText("");
          if (error != null) { say(error); return; }
          me = data.optJSONObject("user");
          navigate("feed");
        });
    });
    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, dp(50));
    sp.topMargin = dp(8);
    body.addView(submit, sp);
    body.addView(extras);

    body.addView(textDivider(register ? I18n.t("Đã có tài khoản?") : I18n.t("Mới đến Kinnect?")));
    LinearLayout swap = authButton(register ? "log_in" : "user_plus", register ? I18n.t("Đăng nhập") : I18n.t("Tạo tài khoản mới"), false);
    swap.setOnClickListener(v -> auth(!register));
    body.addView(swap, new LinearLayout.LayoutParams(-1, dp(50)));

    TextView terms = label(I18n.t("Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng."), 12, MUTED);
    terms.setGravity(Gravity.CENTER);
    terms.setPadding(dp(8), dp(16), dp(8), 0);
    terms.setOnClickListener(v -> { try { startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://kinnect.io.vn/community"))); } catch (Exception ignored) {} });
    body.addView(terms);
  }

  private View authHero() {
    LinearLayout hero=welcomeBrand();hero.setPadding(dp(22),dp(20),dp(22),dp(10));hero.setBackgroundColor(BG);TextView tagline=welcomeText(I18n.t("Sống đúng mình."),12,MUTED,false);hero.addView(tagline);return hero;
  }

  private android.graphics.drawable.Drawable outlined(int color, int radius) {
    android.graphics.drawable.Drawable d = pressable(color, radius);
    ((GradientDrawable) ((android.graphics.drawable.RippleDrawable) d).getDrawable(0)).setStroke(dp(1), LINE);
    return d;
  }

  private EditText authField(LinearLayout parent, String iconName, String hint, boolean secret) {
    final LinearLayout box = row();
    box.setPadding(dp(14), 0, dp(6), 0);
    GradientDrawable idle = background(CARD, 14);
    idle.setStroke(dp(1), LINE);
    box.setBackground(idle);
    box.addView(icon(iconName, 18, MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
    final EditText e = new EditText(this);
    e.setHint(hint);
    e.setContentDescription(hint);
    e.setHintTextColor(MUTED);
    e.setTextColor(TEXT);
    e.setTextSize(15);
    e.setSingleLine(true);
    e.setBackground(null);
    e.setPadding(dp(10), 0, dp(8), 0);
    e.setTypeface(Typeface.DEFAULT);
    box.addView(e, new LinearLayout.LayoutParams(0, -1, 1));
    if (secret) {
      e.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
      e.setTypeface(Typeface.DEFAULT);
      final FrameLayout eye = new FrameLayout(this);
      final ImageView eyeIcon = icon("eye", 19, MUTED);
      eye.addView(eyeIcon, new FrameLayout.LayoutParams(dp(19), dp(19), Gravity.CENTER));
      eye.setContentDescription(I18n.t("Hiện mật khẩu"));
      eye.setBackground(pressable(CARD, 99));
      eye.setOnClickListener(v -> {
        boolean hidden = (e.getInputType() & InputType.TYPE_TEXT_VARIATION_PASSWORD) == InputType.TYPE_TEXT_VARIATION_PASSWORD;
        e.setInputType(InputType.TYPE_CLASS_TEXT | (hidden ? InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD : InputType.TYPE_TEXT_VARIATION_PASSWORD));
        e.setTypeface(Typeface.DEFAULT);
        e.setSelection(e.length());
        android.graphics.drawable.Drawable d = WebIcons.load(this, hidden ? "eye_off" : "eye");
        d.setTint(MUTED);
        eyeIcon.setImageDrawable(d);
        eye.setContentDescription(hidden ? I18n.t("Ẩn mật khẩu") : I18n.t("Hiện mật khẩu"));
      });
      box.addView(eye, new LinearLayout.LayoutParams(dp(40), dp(40)));
    }
    e.setOnFocusChangeListener((v, focused) -> {
      GradientDrawable s = background(CARD, 14);
      s.setStroke(dp(focused ? 2 : 1), focused ? ACCENT : LINE);
      box.setBackground(s);
    });
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, dp(52));
    p.setMargins(0, dp(6), 0, dp(6));
    parent.addView(box, p);
    return e;
  }

  private LinearLayout authButton(String iconName, String text, boolean filled) {
    LinearLayout b = row();
    b.setGravity(Gravity.CENTER);
    if (filled) { b.setBackground(pressable(ACCENT, 14)); b.setElevation(dp(2)); }
    else b.setBackground(outlined(CARD, 14));
    int color = filled ? WHITE : TEXT;
    if (iconName != null) b.addView(icon(iconName, 16, color), new LinearLayout.LayoutParams(dp(16), dp(16)));
    TextView t = label(text, 14, color);
    t.setSingleLine(true);t.setGravity(Gravity.CENTER);
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    t.setPadding(iconName == null ? 0 : dp(8), 0, 0, 0);
    b.addView(t);
    b.setContentDescription(text);
    b.setClickable(true);
    return b;
  }

  private View textDivider(String text) {
    LinearLayout r = row();
    r.setPadding(0, dp(16), 0, dp(12));
    View l1 = new View(this);
    l1.setBackgroundColor(LINE);
    r.addView(l1, new LinearLayout.LayoutParams(0, 1, 1));
    TextView t = label(text, 12, MUTED);
    t.setPadding(dp(10), 0, dp(10), 0);
    r.addView(t);
    View l2 = new View(this);
    l2.setBackgroundColor(LINE);
    r.addView(l2, new LinearLayout.LayoutParams(0, 1, 1));
    return r;
  }

  private TextView fieldLabel(String text) {
    TextView t = label(text, 14, TEXT);
    t.setTypeface(null, Typeface.BOLD);
    t.setPadding(0, dp(10), 0, 0);
    return t;
  }

  private String headerActive = "";

  private void navigate(String next) {
    headerActive = next.equals("inbox") ? "inbox" : "";
    history.clear();
    subBack = null;
    currentPage = () -> navigate(next);
    currentKey = "tab:" + next;
    ensureCalls();
    activity();
    tab = next;
    shell(
      next.equals("inbox")
          ? I18n.t("Tin nhắn")
          : "",
      true
    );
    onTabRoot = true;
    if (next.equals("shorts")) shorts();
    if (next.equals("discover")) discover();
    if (next.equals("feed")) feed();
    if (next.equals("inbox")) inbox();
    if (next.equals("profile")) profile();
    if (next.equals("live")) { startActivity(new Intent(this, LiveActivity.class)); tab = "feed"; feed(); }
  }

  private ImageView avatar(JSONObject u, LinearLayout parent, int size) {
    ImageView image = new ImageView(this);
    image.setScaleType(ImageView.ScaleType.CENTER_CROP);
    GradientDrawable round = new GradientDrawable();
    round.setShape(GradientDrawable.OVAL);
    round.setColor(PRIMARY_SOFT);
    int styleColor=StoreStyle.color(u.optString("storeStyle"));if(styleColor!=0){round.setStroke(dp(3),styleColor);image.setPadding(dp(3),dp(3),dp(3),dp(3));}
    image.setBackground(round);
    image.setClipToOutline(true);
    image.setImageBitmap(u.has("members")?groupSample(u.optString("avatarPreset","violet"),dp(size)):initials(u, dp(size)));
    image.setContentDescription(I18n.t("Ảnh của ") + u.optString("name"));
    parent.addView(image, new LinearLayout.LayoutParams(dp(size), dp(size)));
    String path = u.optString("avatar", "");
    if(path.startsWith("data:image/")){loadAvatarInto(u,image);return image;}
    if (!path.isEmpty() && !path.equals("null")) api.image(path, bytes -> {
      if (bytes != null && !isDestroyed() && image.isAttachedToWindow()) {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(bytes, 0, bytes.length, o);
        o.inSampleSize = Math.max(1, Math.max(o.outWidth, o.outHeight) / 512);
        o.inJustDecodeBounds = false;
        Bitmap bitmap = BitmapFactory.decodeByteArray(
          bytes,
          0,
          bytes.length,
          o
        );
        if (bitmap != null) image.setImageBitmap(bitmap);
      }
    });
    return image;
  }


  // Ảnh đại diện mặc định như web: vòng tròn chuyển sắc theo người dùng + chữ cái đầu.
  private Bitmap initials(JSONObject u, int px) {
    px = Math.max(16, px);
    Bitmap b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
    Canvas c = new Canvas(b);
    boolean dark = WebTheme.isDark(this);
    boolean you = u != null && me != null && u.optString("id").equals(me.optString("id")) && !u.optString("id").isEmpty();
    Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    p.setColor(you ? (dark ? 0xff483020 : 0xfff8e6d8) : PRIMARY_SOFT);
    c.drawOval(0, 0, px, px, p);
    p.setColor(you ? (dark ? 0xffefc39f : 0xff9a562b) : ACCENT);
    p.setTextAlign(Paint.Align.CENTER);
    p.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    String name = u == null ? "?" : u.optString("name", u.optString("username", "?")).trim();
    StringBuilder letters = new StringBuilder();
    for (String w : name.split("\\s+")) if (!w.isEmpty()) letters.append(w.substring(0, 1));
    String text = letters.length() == 0 ? "?" : letters.substring(Math.max(0, letters.length() - 2)).toUpperCase(Locale.ROOT);
    p.setTextSize(px * (text.length() > 1 ? 0.34f : 0.4f));
    Paint.FontMetrics fm = p.getFontMetrics();
    c.drawText(text, px / 2f, px / 2f - (fm.ascent + fm.descent) / 2f, p);
    return b;
  }


  private void discover() {
    final boolean hasLocation = me != null && me.optBoolean("hasLocation");
    String[][] sorts = { { "interests", "Dành cho bạn" }, { "near", "Quanh đây" }, { "following", "Đang theo dõi" } };
    LinearLayout seg = row();
    seg.setPadding(dp(4), dp(4), dp(4), dp(4));
    seg.setBackground(background(SOFT, 14));
    for (final String[] item : sorts) {
      boolean active = discoverSort.equals(item[0]);
      TextView t = label(I18n.t(item[1]), 13, active ? ACCENT : TEXT);
      t.setTypeface(Typeface.create(active ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
      t.setGravity(Gravity.CENTER);
      t.setSingleLine(true);
      if (active) { t.setBackground(background(CARD, 11)); t.setElevation(dp(1)); }
      else t.setBackground(pressable(SOFT, 11));
      t.setOnClickListener(v -> {
        discoverSort = item[0]; nearScrollY=0;
        if (item[0].equals("near") && !hasLocation) { silentLocate = false; requestLocation(); return; }
        navigate("discover");
      });
      seg.addView(t, new LinearLayout.LayoutParams(0, dp(38), 1));
    }
    content.addView(seg, new LinearLayout.LayoutParams(-1, -2));

    LinearLayout searchBox = row();
    searchBox.setPadding(dp(14), 0, dp(10), 0);
    GradientDrawable sb = background(CARD, 14);
    sb.setStroke(dp(1), LINE);
    searchBox.setBackground(sb);
    searchBox.addView(icon("search", 18, MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
    final EditText search = new EditText(this);
    search.setHint(I18n.t("Tên hoặc @username"));search.setText(nearQuery);
    search.setContentDescription(I18n.t("Tìm thành viên"));
    search.setTextColor(TEXT);
    search.setHintTextColor(MUTED);
    search.setTextSize(15);
    search.setSingleLine(true);
    search.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH);
    search.setBackground(null);
    search.setPadding(dp(10), 0, 0, 0);
    searchBox.addView(search, new LinearLayout.LayoutParams(0, -1, 1));
    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, dp(48));
    sp.topMargin = dp(10);
    content.addView(searchBox, sp);

    final boolean nearby = hasLocation && discoverSort.equals("near");
    search.setOnEditorActionListener((v, a, e) -> { loadPeople(search.getText().toString(), nearby); return true; });
    LinearLayout quick=row();
    quick.setPadding(0,dp(12),0,dp(12));
    String[] titles={"Tuổi","Cân nặng","Chiều cao","Giới tính",""};String[] keys={"age","weight","height","gender",""};float[] weights={.8f,1.2f,1.25f,1.1f};
    for(int i=0;i<5;i++){
      final String key=keys[i];boolean selected=i==0?nearMinAge>0||nearMaxAge>0:i==1?nearMinWeight>0||nearMaxWeight>0:i==2?nearMinHeight>0||nearMaxHeight>0:i==3?!nearGender.isEmpty():nearOnline||nearRecent||!nearOrientation.isEmpty()||!nearCommunityRole.isEmpty()||!nearIntent.isEmpty();
      LinearLayout button=row();button.setGravity(Gravity.CENTER);button.setPadding(dp(3),0,dp(3),0);button.setBackground(pressable(selected?PRIMARY_SOFT:SOFT,10));
      if(i==4){button.addView(icon("sliders_horizontal",20,selected?ACCENT:MUTED),new LinearLayout.LayoutParams(dp(20),dp(20)));}else{TextView caption=label(I18n.t(titles[i]),12,selected?ACCENT:TEXT);caption.setGravity(Gravity.CENTER);caption.setPadding(0,0,0,0);caption.setSingleLine(true);caption.setAutoSizeTextTypeUniformWithConfiguration(9,12,1,android.util.TypedValue.COMPLEX_UNIT_SP);button.addView(caption,new LinearLayout.LayoutParams(-1,-1));}
      button.setContentDescription((i==4?I18n.t("Bộ lọc tổng hợp"):titles[i])+(selected?I18n.t(" · Đang chọn"):""));button.setSelected(selected);button.setOnClickListener(v->nearFilters(key));LinearLayout.LayoutParams bp=i==4?new LinearLayout.LayoutParams(dp(44),dp(44)):new LinearLayout.LayoutParams(0,dp(44),weights[i]);if(i>0)bp.leftMargin=dp(4);quick.addView(button,bp);
    }
    content.addView(quick,new LinearLayout.LayoutParams(-1,-2));
    if(discoverSort.equals("near")&&!hasLocation){TextView enable=label(I18n.t("Bật vị trí để xem thành viên quanh đây"),14,MUTED);enable.setOnClickListener(v->requestLocation());content.addView(enable);return;}
    loadPeople(nearQuery, nearby);
  }

  private LinearLayout people;

  private void loadPeople(String query, boolean nearby) {
    if(!nearQuery.equals(query))nearScrollY=0;nearQuery=query;
    if (people != null && people.getParent() == content) content.removeView(people);
    people = column();
    content.addView(people);
    final LinearLayout list = people;
    final String requestedTab=discoverSort;
    String filters="&minWeight="+nearMinWeight+"&maxWeight="+nearMaxWeight+"&minHeight="+nearMinHeight+"&maxHeight="+nearMaxHeight+"&orientation="+encode(nearOrientation)+"&communityRole="+encode(nearCommunityRole)+"&gender="+encode(nearGender)+"&minAge="+nearMinAge+"&maxAge="+nearMaxAge+"&intent="+encode(nearIntent)+(nearRecent?"&recent=1":"");
    String sort=nearOnline?"active":requestedTab.equals("near")?"new":"interests";
    request("GET","/api/discover?q="+encode(query)+(nearby?"&nearby=1&radius="+discoverRadius:"")+filters+"&sort="+sort+(requestedTab.equals("following")?"&following=1":""),null,data->{
      if(people!=list||!discoverSort.equals(requestedTab))return;
      boolean filtered=nearMinWeight>0||nearMaxWeight>0||nearMinHeight>0||nearMaxHeight>0||nearOnline||!nearOrientation.isEmpty()||!nearCommunityRole.isEmpty()||!nearGender.isEmpty()||nearMinAge>0||nearMaxAge>0||!nearIntent.isEmpty()||nearRecent;
      if(filtered&&data.optInt("filterVersion")<2){list.addView(label(I18n.t("Máy chủ cần cập nhật để áp dụng bộ lọc. Các kết quả chưa lọc sẽ không hiển thị."),14,MUTED));return;}
      JSONArray users = data.optJSONArray("users");
      if (users == null || users.length() == 0) {
        list.addView(discoveryEmptyState(), new LinearLayout.LayoutParams(-1, -2));
        return;
      }
      LinearLayout line = null;
      for (int i = 0; i < users.length(); i++) {
        if (i % 3 == 0) { line = row(); line.setGravity(Gravity.TOP); list.addView(line); }
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, -2, 1);
        p.setMargins(i % 3 == 0 ? 0 : dp(4), 0, i % 3 == 2 ? 0 : dp(4), dp(8));
        line.addView(nearTile(users.optJSONObject(i)), p);
      }
      for(int pad=users.length()%3;pad>0&&pad<3;pad++){LinearLayout.LayoutParams emptyCell=new LinearLayout.LayoutParams(0,1,1);emptyCell.setMargins(dp(4),0,pad==2?0:dp(4),dp(8));line.addView(new View(this),emptyCell);}
      list.post(()->{if(people==list&&content.getParent() instanceof ScrollView)((ScrollView)content.getParent()).scrollTo(0,nearScrollY);});
    });
  }

  private String nearQuery="",nearGender="",nearOrientation="",nearCommunityRole="",nearIntent="";private boolean nearOnline,nearRecent;private int nearMinAge,nearMaxAge,nearMinWeight,nearMaxWeight,nearMinHeight,nearMaxHeight,nearScrollY;
  private View discoveryEmptyState() {
        LinearLayout empty = column();
        empty.setGravity(Gravity.CENTER_HORIZONTAL);
        empty.setPadding(dp(20), dp(36), dp(20), dp(28));
        GradientDrawable eb = background(CARD, WebDesign.CARD_RADIUS);
        eb.setStroke(dp(1), LINE);
        empty.setBackground(eb);
        FrameLayout bubble = new FrameLayout(this);
        bubble.setBackground(background(PRIMARY_SOFT, 99));
        bubble.addView(icon("users_round", 28, ACCENT), new FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER));
        empty.addView(bubble, new LinearLayout.LayoutParams(dp(64), dp(64)));
        TextView t = label(discoverSort.equals("following") ? I18n.t("Chưa theo dõi ai") : I18n.t("Chưa tìm thấy ai"), 17, TEXT);
        t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        t.setGravity(Gravity.CENTER);
        t.setPadding(0, dp(14), 0, dp(2));
        empty.addView(t);
        TextView s = label(discoverSort.equals("following") ? I18n.t("Khám phá và theo dõi những người bạn quan tâm.") : I18n.t("Thử tên hoặc @username khác."), 13, MUTED);
        s.setGravity(Gravity.CENTER);
        empty.addView(s, new LinearLayout.LayoutParams(-1, -2));
        LinearLayout all = authButton("users_round", I18n.t("Xem tất cả"), false);
        all.setPadding(dp(16), 0, dp(16), 0);
        all.setOnClickListener(v -> { discoverSort = "interests"; navigate("discover"); });
        LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(-2, dp(44));
        ap.topMargin = dp(18);
        empty.addView(all, ap);
        return empty;
  }

  private final class SquarePeopleTile extends FrameLayout {
    SquarePeopleTile(){super(MainActivity.this);}
    @Override protected void onMeasure(int widthSpec,int heightSpec){int side=View.MeasureSpec.getSize(widthSpec);super.onMeasure(widthSpec,View.MeasureSpec.makeMeasureSpec(side,View.MeasureSpec.EXACTLY));}
  }
  private View nearTile(JSONObject u){FrameLayout tile=new SquarePeopleTile();tile.setBackground(background(SOFT,8));tile.setClipToOutline(true);ImageView photo=new ImageView(this);photo.setScaleType(ImageView.ScaleType.CENTER_CROP);tile.addView(photo,new FrameLayout.LayoutParams(-1,-1));String path=u.optString("avatar","");if(!path.isEmpty()&&!path.equals("null"))loadAvatarInto(u,photo);else{photo.setImageDrawable(WebIcons.load(this,"user_round"));photo.setImageTintList(android.content.res.ColorStateList.valueOf(MUTED));photo.setPadding(dp(20),dp(20),dp(20),dp(20));}
    View shade=new View(this);shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x00000000,0xbb000000}));FrameLayout.LayoutParams shadow=new FrameLayout.LayoutParams(-1,dp(54),Gravity.BOTTOM);tile.addView(shade,shadow);LinearLayout meta=column();meta.setPadding(dp(6),0,dp(6),dp(5));String distance=u.optString("distanceLabel","");if(!distance.isEmpty()&&!distance.equals("null")){TextView km=label(distance,11,WHITE);km.setPadding(0,0,0,0);meta.addView(km);}TextView name=label(u.optString("name"),12,WHITE);name.setSingleLine(true);name.setAutoSizeTextTypeUniformWithConfiguration(12,19,1,android.util.TypedValue.COMPLEX_UNIT_SP);name.setEllipsize(android.text.TextUtils.TruncateAt.END);name.setPadding(0,0,0,0);meta.addView(name);tile.addView(meta,new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM));if(u.optBoolean("isActive")){View online=new View(this);online.setBackground(background(0xff24d74d,99));FrameLayout.LayoutParams dot=new FrameLayout.LayoutParams(dp(8),dp(8),Gravity.TOP|Gravity.START);dot.setMargins(dp(7),dp(7),0,0);tile.addView(online,dot);}tile.setContentDescription(I18n.t("Xem hồ sơ ")+u.optString("name")+(distance.isEmpty()?"":" · "+distance));tile.setOnClickListener(v->{if(content.getParent() instanceof ScrollView)nearScrollY=((ScrollView)content.getParent()).getScrollY();person(u);});return tile;}

  private void nearFilters(){nearFilters("");}
  private EditText[] filterRange(LinearLayout form,String title,String unit,int min,int max){form.addView(label(title+" ("+unit+")",14,TEXT));LinearLayout pair=row();form.addView(pair);LinearLayout left=column(),right=column();pair.addView(left,new LinearLayout.LayoutParams(0,-2,1));LinearLayout.LayoutParams rp=new LinearLayout.LayoutParams(0,-2,1);rp.leftMargin=dp(10);pair.addView(right,rp);EditText low=input(left,I18n.t("Từ"),min==0?"":String.valueOf(min),false),high=input(right,I18n.t("Đến"),max==0?"":String.valueOf(max),false);low.setInputType(2);high.setInputType(2);return new EditText[]{low,high};}
  private int[] readFilterRange(EditText[] fields,int minimum,int maximum){int low=fields[0].length()==0?0:Integer.parseInt(fields[0].getText().toString()),high=fields[1].length()==0?0:Integer.parseInt(fields[1].getText().toString());if(low!=0&&(low<minimum||low>maximum)||high!=0&&(high<minimum||high>maximum)||low>0&&high>0&&low>high)throw new IllegalArgumentException();return new int[]{low,high};}
  private Spinner filterChoice(LinearLayout form,String title,String[] choices,String selected){form.addView(label(title,14,TEXT));Spinner field=new Spinner(this);field.setAdapter(new ArrayAdapter<String>(this,android.R.layout.simple_spinner_dropdown_item,choices){
@Override public View getView(int position,View view,ViewGroup parent){TextView text=(TextView)super.getView(position,view,parent);text.setText(I18n.t(getItem(position)));return text;}
@Override public View getDropDownView(int position,View view,ViewGroup parent){TextView text=(TextView)super.getDropDownView(position,view,parent);text.setText(I18n.t(getItem(position)));return text;}
});for(int i=0;i<choices.length;i++)if(choices[i].equals(selected))field.setSelection(i);form.addView(field);return field;}
  private void nearFilters(final String only){
    boolean all=only.isEmpty();LinearLayout form=column();
    final EditText[] ages=all||only.equals("age")?filterRange(form,I18n.t("Tuổi"),"18–99",nearMinAge,nearMaxAge):null;
    final EditText[] weights=all||only.equals("weight")?filterRange(form,I18n.t("Cân nặng"),"kg",nearMinWeight,nearMaxWeight):null;
    final EditText[] heights=all||only.equals("height")?filterRange(form,I18n.t("Chiều cao"),"cm",nearMinHeight,nearMaxHeight):null;
    String[] genders={"Tất cả","Nam","Nữ","Nam chuyển giới","Nữ chuyển giới","Phi nhị nguyên","Linh hoạt giới","Vô giới","Khác"};
    final Spinner gender=all||only.equals("gender")?filterChoice(form,I18n.t("Giới tính"),genders,nearGender):null;
    String[] orientations={"Tất cả","Gay / Đồng tính nam","Lesbian / Đồng tính nữ","Song tính / Bisexual","Toàn tính / Pansexual","Vô tính / Asexual","Dị tính","Queer","Á tính / Demisexual","Đang tìm hiểu","Khác"};
    final Spinner orientation=all?filterChoice(form,I18n.t("Xu hướng tính dục"),orientations,nearOrientation):null;
    String[] roles={"Tất cả","Top","Bottom","Vers","Vers Top","Vers Bottom","Side","Femme","Masc / Butch","Androgynous","Stem","Đang tìm hiểu","Khác"};final Spinner community=all?filterChoice(form,I18n.t("Vai trò tự mô tả"),roles,nearCommunityRole):null;
    String[] intents={"Tất cả","Trò chuyện","Kết bạn","Hẹn hò"};final Spinner intent=all?filterChoice(form,I18n.t("Mục đích kết nối"),intents,nearIntent):null;
    CheckBox online=new CheckBox(this);online.setText(I18n.t("Đang online"));online.setChecked(nearOnline);CheckBox recent=new CheckBox(this);recent.setText(I18n.t("Hoạt động gần đây"));recent.setChecked(nearRecent);if(all){form.addView(online);form.addView(recent);}
    final int[] radii={1,5,10,25,50};final Spinner radius=all&&discoverSort.equals("near")?filterChoice(form,I18n.t("Bán kính"),new String[]{"1 km","5 km","10 km","25 km","50 km"},discoverRadius+" km"):null;
    String title=only.equals("age")?"Lọc theo tuổi":only.equals("weight")?"Lọc theo cân nặng":only.equals("height")?"Lọc theo chiều cao":only.equals("gender")?"Lọc theo giới tính":"Bộ lọc thành viên";
    final Sheet builder=new Sheet(this).setTitle(I18n.t(title)).setView(form).setNegativeButton(I18n.t("Hủy"),null).setNeutralButton(I18n.t("Đặt lại"),(d,index)->{if(all||only.equals("age"))nearMinAge=nearMaxAge=0;if(all||only.equals("weight"))nearMinWeight=nearMaxWeight=0;if(all||only.equals("height"))nearMinHeight=nearMaxHeight=0;if(all||only.equals("gender"))nearGender="";if(all){nearOrientation=nearCommunityRole=nearIntent="";nearOnline=nearRecent=false;discoverRadius=5;}nearScrollY=0;navigate("discover");});
    final android.app.Dialog[] dialog={null};form.addView(primary(I18n.t("Áp dụng"),()->{try{
      int[] age=ages==null?null:readFilterRange(ages,18,99),weight=weights==null?null:readFilterRange(weights,20,400),height=heights==null?null:readFilterRange(heights,80,250);
      if(age!=null){nearMinAge=age[0];nearMaxAge=age[1];}if(weight!=null){nearMinWeight=weight[0];nearMaxWeight=weight[1];}if(height!=null){nearMinHeight=height[0];nearMaxHeight=height[1];}if(gender!=null)nearGender=gender.getSelectedItemPosition()==0?"":genders[gender.getSelectedItemPosition()];
      if(all){nearOrientation=orientation.getSelectedItemPosition()==0?"":orientations[orientation.getSelectedItemPosition()];nearCommunityRole=community.getSelectedItemPosition()==0?"":roles[community.getSelectedItemPosition()];nearIntent=intent.getSelectedItemPosition()==0?"":intents[intent.getSelectedItemPosition()];nearOnline=online.isChecked();nearRecent=recent.isChecked();if(radius!=null)discoverRadius=radii[radius.getSelectedItemPosition()];}
      if(dialog[0]!=null)dialog[0].dismiss();nearScrollY=0;navigate("discover");
    }catch(IllegalArgumentException error){say(I18n.t("Nhập khoảng hợp lệ: tuổi 18–99, cân nặng 20–400 kg, chiều cao 80–250 cm. Giá trị Từ không lớn hơn Đến."));}}));dialog[0]=builder.show();
  }

  private LinearLayout personTile(final JSONObject u) {
    LinearLayout c = column();
    c.setGravity(Gravity.CENTER_HORIZONTAL);
    c.setPadding(dp(6), dp(14), dp(6), dp(10));
    c.setBackground(outlined(CARD, 16));
    c.setOnClickListener(v -> person(u));
    c.setContentDescription(I18n.t("Xem hồ sơ ") + u.optString("name"));
    LinearLayout photo = row();
    photo.setGravity(Gravity.CENTER);
    avatar(u, photo, 52);
    c.addView(photo, new LinearLayout.LayoutParams(-1, dp(56)));
    TextView name = label(u.optString("name"), 13, TEXT);
    name.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    name.setGravity(Gravity.CENTER);
    name.setSingleLine(true);
    name.setEllipsize(android.text.TextUtils.TruncateAt.END);
    name.setPadding(0, dp(8), 0, 0);
    c.addView(name, new LinearLayout.LayoutParams(-1, -2));
    TextView username = label("@" + u.optString("username"), 11, MUTED);
    username.setSingleLine(true);
    username.setEllipsize(android.text.TextUtils.TruncateAt.END);
    username.setGravity(Gravity.CENTER);
    username.setPadding(0, 0, 0, dp(8));
    c.addView(username, new LinearLayout.LayoutParams(-1, -2));
    String distance = u.optString("distanceLabel", "");
    if (!distance.isEmpty() && !distance.equals("null")) {
      LinearLayout km = row();
      km.setGravity(Gravity.CENTER);
      km.setPadding(dp(8), dp(2), dp(8), dp(2));
      km.setBackground(background(PRIMARY_SOFT, 99));
      km.addView(icon("map_pin", 11, ACCENT), new LinearLayout.LayoutParams(dp(11), dp(11)));
      TextView kt = label(distance, 11, ACCENT);
      kt.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
      kt.setPadding(dp(3), 0, 0, 0);
      km.addView(kt);
      LinearLayout.LayoutParams kp = new LinearLayout.LayoutParams(-2, -2);
      kp.gravity = Gravity.CENTER_HORIZONTAL;
      kp.bottomMargin = dp(8);
      c.addView(km, kp);
    }
    LinearLayout actions = row();
    actions.setGravity(Gravity.CENTER);
    String state = u.optString("friendship");
    if (state.equals("friends")) actions.addView(roundAction("message", I18n.t("Nhắn tin"), true, () -> chat(u)));
    else if (state.equals("incoming")) actions.addView(roundAction("check", I18n.t("Chấp nhận kết bạn"), true, () -> request("POST", "/api/users/" + u.optString("id") + "/friend-request/respond", json("action", "accept"), d -> navigate("discover"))));
    else actions.addView(roundAction(state.equals("outgoing") ? "user_check" : "user_plus", state.equals("outgoing") ? I18n.t("Huỷ lời mời") : I18n.t("Kết bạn"), !state.equals("outgoing"), () -> request(state.equals("outgoing") ? "DELETE" : "POST", "/api/users/" + u.optString("id") + "/friend-request", json(), d -> navigate("discover"))));
    actions.addView(roundAction("arrow_up_right", I18n.t("Xem hồ sơ"), false, () -> person(u)));
    c.addView(actions, new LinearLayout.LayoutParams(-1, dp(36)));
    return c;
  }

  private View roundAction(String iconName, String description, boolean filled, Runnable action) {
    FrameLayout f = new FrameLayout(this);
    f.setBackground(filled ? pressable(ACCENT, 99) : outlined(SOFT, 99));
    f.addView(icon(iconName, 16, filled ? WHITE : TEXT), new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
    f.setContentDescription(description);
    f.setOnClickListener(v -> action.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(dp(34), dp(34));
    p.setMargins(dp(3), 0, dp(3), 0);
    f.setLayoutParams(p);
    return f;
  }

  private TextView tag(String text, int color) {
    TextView t = label(text, 10, color);
    t.setTypeface(null, Typeface.BOLD);
    t.setPadding(dp(7), dp(2), dp(7), dp(2));
    t.setBackground(background(0xf2ffffff, 99));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, -2);
    p.rightMargin = dp(4);
    t.setLayoutParams(p);
    return t;
  }

  private String join(JSONArray values) {
    List<String> parts = new ArrayList<>();
    if (values != null) for (int i = 0; i < values.length(); i++) parts.add(
      values.optString(i)
    );
    return android.text.TextUtils.join(" · ", parts);
  }

  private void person(final JSONObject u) {
    remember("person:" + u.optString("id"), () -> person(u));
    shell("", true);
    profileCard(u, u.optString("id").equals(me == null ? "" : me.optString("id")));
    profileSections(u);
  }

  private void confirm(String message, Runnable yes) {
    new Sheet(this)
      .setMessage(message)
      .setPositiveButton(I18n.t("Xác nhận"), (d, w) -> yes.run())
      .setNegativeButton(I18n.t("Hủy"), null)
      .show();
  }

  private void report(String type,String id){
    String[] reasons={"An toàn trẻ em · CSAE/CSAM","Quấy rối hoặc bắt nạt","Thù ghét hoặc phân biệt đối xử","Giả mạo tài khoản","Lừa đảo hoặc spam","Nội dung tình dục không phù hợp","Bạo lực hoặc nguy hiểm","Vấn đề khác"};
    new Sheet(this).setTitle(I18n.t("Báo cáo")).setItemIcons(new String[]{"shield_check","flag","shield_check","user_round","mail","eye_off","flag","circle_help"}).setItems(I18n.items(reasons),(d,index)->reportDetails(type,id,reasons[index])).setNegativeButton(I18n.t("Hủy"),null).show();
  }
  private void reportDetails(String type, String id,String category) {
    EditText reason = new EditText(this);
    reason.setHint(I18n.t("Bổ sung chi tiết (tùy chọn)"));
    new Sheet(this)
      .setTitle(category)
      .setView(reason)
      .setPositiveButton(I18n.t("Gửi"), (dialog, w) ->
        request(
          "POST",
          "/api/reports",
          json(
            "targetType",
            type,
            "targetId",
            id,
            "reason",
            category+": "+reason.getText().toString()
          ),
          data -> say(I18n.t("Đã gửi báo cáo để quản trị viên xem xét."))
        )
      )
      .setNegativeButton(I18n.t("Hủy"), null)
      .show();
  }


  private void feed() {
    if(me!=null&&me.optBoolean("isNew"))profileCompletion();
    stories();
    // Ô đăng bài: avatar + "… ơi, bạn đang nghĩ gì?" như web
    LinearLayout composer = card();
    composer.setPadding(dp(12), dp(12), dp(12), dp(12));
    LinearLayout r = row();
    avatar(me, r, 38);
    TextView pill = label(I18n.t("Bạn đang nghĩ gì?"), 13, MUTED);
    pill.setSingleLine(true);
    pill.setGravity(Gravity.CENTER_VERTICAL);
    pill.setPadding(dp(16), 0, dp(12), 0);
    pill.setBackground(background(SOFT, 999));
    LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(0, dp(44), 1);
    pp.leftMargin = dp(10);
    r.addView(pill, pp);
    composer.addView(r);
    composer.setOnClickListener(v -> composePost());
    pill.setOnClickListener(v -> composePost());
    final LinearLayout list = column();
    content.addView(list);
    request("GET", "/api/posts", null, data -> {
      LinearLayout saved = content;
      content = list;
      posts(data.optJSONArray("posts"), "Chưa có bài viết. Hãy là người đầu tiên chia sẻ.");
      content = saved;

    });
  }

  private void composePost() {
    remember("compose", () -> composePost());
    shell("", false);
    toolbar.setVisibility(View.GONE);
    if (root.getChildCount() > 1) root.getChildAt(1).setVisibility(View.GONE);
    pendingMedia = null;
    preparingPostMedia = false;
    content.setPadding(0, 0, 0, dp(24));

    LinearLayout head = row();
    head.setPadding(dp(6), 0, dp(12), 0);
    head.setBackgroundColor(CARD);
    head.setElevation(dp(1));
    FrameLayout back = new FrameLayout(this);
    back.setBackground(pressable(CARD, 99));
    back.addView(icon("close", 22, TEXT), new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
    back.setContentDescription(I18n.t("Quay lại"));
    back.setOnClickListener(v -> navigate("feed"));
    head.addView(back, new LinearLayout.LayoutParams(dp(80), dp(44)));
    TextView title = label(I18n.t("Bài viết mới"), 18, TEXT);
    title.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    title.setPadding(0, 0, 0, 0);title.setGravity(Gravity.CENTER);
    head.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    final LinearLayout post = authButton(null, I18n.t("Đăng"), true);
    post.setPadding(dp(10), 0, dp(10), 0);
    head.addView(post, new LinearLayout.LayoutParams(dp(80), dp(40)));
    root.addView(head,0,new LinearLayout.LayoutParams(-1,dp(WebDesign.HEADER)));

    LinearLayout body = column();
    body.setPadding(dp(16), dp(16), dp(16), 0);
    content.addView(body);

    LinearLayout who = row();
    avatar(me, who, 44);
    LinearLayout t = column();
    t.setPadding(dp(12), 0, 0, 0);
    TextView n = label(me.optString("name"), 15, TEXT);
    n.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    t.addView(n);
    final String[] visibility = { "public" };
    final LinearLayout vis = row();
    vis.setPadding(dp(8), dp(3), dp(8), dp(3));
    vis.setBackground(outlined(SOFT, 99));
    final ImageView visIcon = icon("globe", 13, TEXT);
    vis.addView(visIcon, new LinearLayout.LayoutParams(dp(13), dp(13)));
    final TextView visText = label(I18n.t("Mọi thành viên"), 12, TEXT);
    visText.setPadding(dp(5), 0, dp(3), 0);
    vis.addView(visText);
    vis.addView(icon("chevron_down", 13, MUTED), new LinearLayout.LayoutParams(dp(13), dp(13)));
    vis.setContentDescription(I18n.t("Ai có thể xem"));
    vis.setOnClickListener(v -> new Sheet(this).setTitle(I18n.t("Ai có thể xem?")).setItemIcons(new String[]{"globe","users_round"}).setItems(new String[] { I18n.t("Mọi thành viên"), I18n.t("Người theo dõi") }, (d, w) -> {
      visibility[0] = w == 0 ? "public" : "followers";
      visText.setText(w == 0 ? I18n.t("Mọi thành viên") : I18n.t("Người theo dõi"));
      android.graphics.drawable.Drawable di = WebIcons.load(this, w == 0 ? "globe" : "users_round");
      di.setTint(TEXT);
      visIcon.setImageDrawable(di);
    }).show());
    LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(-2, -2);
    vp.topMargin = dp(4);

    who.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
    body.addView(who);body.addView(vis,vp);

    final EditText text = new EditText(this);
    text.setHint(I18n.t("Bạn đang nghĩ gì?"));
    text.setTextSize(18);
    text.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(2000) });
    text.setTextColor(TEXT);
    text.setHintTextColor(MUTED);
    text.setBackground(null);
    text.setGravity(Gravity.TOP);
    text.setMinHeight(dp(160));
    text.setPadding(0, dp(16), 0, dp(8));
    body.addView(text, new LinearLayout.LayoutParams(-1, -2));

    composePreview = column();
    body.addView(composePreview, new LinearLayout.LayoutParams(-1, -2));

    LinearLayout tools = row();
    tools.setPadding(dp(8), 0, dp(8), 0);
    tools.setBackground(outlined(CARD, 16));
    tools.setGravity(Gravity.CENTER);
    tools.addView(composeTool("image", 0xff22a565, I18n.t("Thêm ảnh"), () -> { attachButton = null; pickFile(300, "image/*"); }));
    tools.addView(composeTool("video", 0xffe0245e, I18n.t("Thêm video"), () -> { attachButton = null; pickFile(300, "video/*"); }));
    tools.addView(composeTool("camera", ACCENT, I18n.t("Chụp hoặc quay"), () -> startActivityForResult(new Intent(this, StudioActivity.class), 203)));
    LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(-2, dp(56));
    tp.gravity=Gravity.CENTER_HORIZONTAL;tp.setMargins(dp(16),dp(8),dp(16),dp(12));
    root.addView(tools,tp);

    post.setOnClickListener(v -> {
      if (!post.isEnabled()) return;
      if (preparingPostMedia) { say(I18n.t("Đang chuẩn bị ảnh/video, vui lòng chờ.")); return; }
      if (text.getText().toString().trim().isEmpty() && pendingMedia == null) { say(I18n.t("Viết nội dung hoặc chọn ảnh/video.")); return; }
      post.setEnabled(false);
      post.setAlpha(0.7f);
      if (pendingMedia != null) say(I18n.t("Đang tải lên…"));
      JSONObject payload = json("body", text.getText().toString(), "visibility", visibility[0]);
      if (pendingMedia != null) try { payload.put("media", pendingMedia); } catch (JSONException ignored) {}
      request("POST", "/api/posts", payload, d -> { pendingMedia = null; say(I18n.t("Đã đăng bài viết")); navigate("feed"); }, () -> { post.setEnabled(true); post.setAlpha(1f); });
    });
    text.requestFocus();
  }

  private LinearLayout composePreview;

  private View composeTool(String iconName, int color, String description, Runnable action) {
    FrameLayout f = new FrameLayout(this);
    f.setBackground(pressable(CARD, 99));
    f.addView(icon(iconName, 20, color), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    f.setContentDescription(description);
    f.setOnClickListener(v -> action.run());
    f.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    return f;
  }

  private interface IndexPick { void pick(int index); }

  // Nút gạt nhiều lựa chọn giống tabs() của web: nền xám nhạt, mục đang chọn là viên trắng chữ tím.
  private void segmented(LinearLayout into, String[] labels, int selected, IndexPick pick) {
    into.setPadding(dp(4), dp(4), dp(4), dp(4));
    into.setBackground(background(SOFT, 14));
    for (int i = 0; i < labels.length; i++) {
      final int index = i;
      boolean on = i == selected;
      TextView tab = label(I18n.t(labels[i]), 13, on ? ACCENT : TEXT);
      tab.setTypeface(Typeface.create(on ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
      tab.setGravity(Gravity.CENTER);
      tab.setSingleLine(true);
      if (on) { tab.setBackground(background(CARD, 11)); tab.setElevation(dp(1)); }
      else tab.setBackground(pressable(SOFT, 11));
      tab.setOnClickListener(v -> pick.pick(index));
      into.addView(tab, new LinearLayout.LayoutParams(0, dp(38), 1));
    }
  }

  private EditText searchField(LinearLayout parent, String hint) {
    LinearLayout box = row();
    box.setPadding(dp(14), 0, dp(10), 0);
    GradientDrawable sb = background(CARD, 14);
    sb.setStroke(dp(1), LINE);
    box.setBackground(sb);
    box.addView(icon("search", 18, MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
    EditText e = new EditText(this);
    e.setHint(hint);
    e.setContentDescription(hint);
    e.setTextColor(TEXT);
    e.setHintTextColor(MUTED);
    e.setTextSize(15);
    e.setSingleLine(true);
    e.setBackground(null);
    e.setPadding(dp(10), 0, 0, 0);
    box.addView(e, new LinearLayout.LayoutParams(0, -1, 1));
    parent.addView(box, new LinearLayout.LayoutParams(-1, dp(48)));
    return e;
  }

  private void inbox() {
    if (headActions != null) headActions.addView(roundAction("message_square_plus", I18n.t("Tạo nhóm"), false, () -> createGroup()));
    final EditText search = searchField(content, I18n.t("Tìm cuộc trò chuyện…"));
    final LinearLayout filters = row();
    LinearLayout.LayoutParams fp = new LinearLayout.LayoutParams(-1, -2);
    fp.topMargin = dp(10);
    content.addView(filters, fp);
    final LinearLayout list = column();
    GradientDrawable g = background(CARD, 16);
    g.setStroke(1, LINE);
    list.setBackground(g);
    list.setPadding(0, dp(4), 0, dp(4));
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.topMargin = dp(8);
    content.addView(list, lp);
    final List<JSONObject> rows = new ArrayList<>();
    final boolean[] unreadOnly = { false };
    final Runnable render = () -> {
      list.removeAllViews();
      String q = search.getText().toString().trim().toLowerCase(Locale.ROOT);
      int shown = 0;
      for (final JSONObject item : rows) {
        boolean group = item.has("members");
        String name = group ? item.optString("name") : item.optString("name");
        if (!q.isEmpty() && !name.toLowerCase(Locale.ROOT).contains(q)) continue;
        if (unreadOnly[0] && item.optInt("unread") == 0) continue;
        JSONObject last = item.optJSONObject("last");
        String sub = last == null ? (group ? item.optJSONArray("members").length() + " thành viên" : "@" + item.optString("username")) : (last.optBoolean("mine") ? "Bạn: " : group ? last.optString("name") + ": " : "") + last.optString("body");
        conversationRow(list, item, group ? item.optString("name") : name, sub, last == null ? "" : ago(last.optLong("created")), item.optInt("unread"), !group && item.optBoolean("isActive"), item.optBoolean("pinned"), () -> { if (group) groupChat(item); else chat(item); });
        shown++;
      }
      if (shown == 0) {
        TextView empty = label(unreadOnly[0] ? I18n.t("Không có tin nhắn chưa đọc.") : I18n.t("Chưa có cuộc trò chuyện. Hãy tìm một người bạn ở Khám phá."), 14, MUTED);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(dp(16), dp(28), dp(16), dp(28));
        list.addView(empty);
      }
    };
    final Runnable[] drawFilters = new Runnable[1];
    drawFilters[0] = () -> {
      filters.removeAllViews();
      segmented(filters, new String[] { "Tất cả", "Chưa đọc" }, unreadOnly[0] ? 1 : 0, i -> { unreadOnly[0] = i == 1; drawFilters[0].run(); render.run(); });
    };
    drawFilters[0].run();
    search.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
      public void onTextChanged(CharSequence s, int a, int b, int c) {}
      public void afterTextChanged(android.text.Editable s) { render.run(); }
    });
    request("GET", "/api/conversations", null, data -> {
      conversationUsers = data.optJSONArray("users");
      for (int i = 0; conversationUsers != null && i < conversationUsers.length(); i++) rows.add(conversationUsers.optJSONObject(i));
      request("GET", "/api/groups", null, g2 -> {
        JSONArray groups = g2.optJSONArray("groups");
        for (int i = 0; groups != null && i < groups.length(); i++) rows.add(groups.optJSONObject(i));
        Collections.sort(rows, (a, b) -> {
          if (a.optBoolean("pinned") != b.optBoolean("pinned")) return a.optBoolean("pinned") ? -1 : 1;
          long ta = a.optJSONObject("last") == null ? a.optLong("created") : a.optJSONObject("last").optLong("created");
          long tb = b.optJSONObject("last") == null ? b.optLong("created") : b.optJSONObject("last").optLong("created");
          return Long.compare(tb, ta);
        });
        render.run();
      });
    });
  }

  private void conversationRow(LinearLayout parent, JSONObject u, String title, String subtitle, String time, int unread, boolean online, boolean pinned, Runnable open) {
    LinearLayout r = row();
    r.setPadding(dp(12), dp(10), dp(12), dp(10));
    FrameLayout face = new FrameLayout(this);
    if (u != null) {
      LinearLayout h = new LinearLayout(this);
      avatar(u, h, 50);
      face.addView(h);
    } else {
      FrameLayout g = new FrameLayout(this);
      GradientDrawable o = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { ACCENT, ACCENT });
      o.setShape(GradientDrawable.OVAL);
      g.setBackground(o);
      ImageView groupGlyph=new ImageView(this);groupGlyph.setImageDrawable(new SettingsGlyph("group_three",WHITE,ACCENT));g.addView(groupGlyph,new FrameLayout.LayoutParams(dp(28),dp(28),Gravity.CENTER));
      face.addView(g, new FrameLayout.LayoutParams(dp(50), dp(50)));
    }
    if (online) {
      View dot = new View(this);
      GradientDrawable d = new GradientDrawable();
      d.setShape(GradientDrawable.OVAL);
      d.setColor(0xff22c55e);
      d.setStroke(dp(2), CARD);
      dot.setBackground(d);
      face.addView(dot, new FrameLayout.LayoutParams(dp(14), dp(14), Gravity.BOTTOM | Gravity.END));
    }
    r.addView(face, new LinearLayout.LayoutParams(dp(50), dp(50)));
    LinearLayout t = column();
    t.setPadding(dp(12), 0, dp(8), 0);
    TextView n = label((pinned ? "📌 " : "") + title, 16, TEXT);
    n.setTypeface(null, Typeface.BOLD);
    n.setSingleLine(true);
    n.setPadding(0, 0, 0, 0);
    TextView s2 = label(subtitle, 14, unread > 0 ? TEXT : MUTED);
    s2.setTypeface(null, unread > 0 ? Typeface.BOLD : Typeface.NORMAL);
    s2.setSingleLine(true);
    s2.setEllipsize(android.text.TextUtils.TruncateAt.END);
    s2.setPadding(0, dp(2), 0, 0);
    t.addView(n);
    t.addView(s2);
    r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
    LinearLayout right = column();
    right.setGravity(Gravity.END);
    right.addView(label(time, 11, MUTED));
    if (unread > 0) {
      TextView badge = label(String.valueOf(unread), 11, WHITE);
      badge.setGravity(Gravity.CENTER);
      badge.setTypeface(null, Typeface.BOLD);
      badge.setPadding(dp(6), 0, dp(6), 0);
      badge.setMinWidth(dp(20));
      badge.setBackground(background(0xfff23663, 99));
      right.addView(badge, new LinearLayout.LayoutParams(-2, dp(20)));
    }
    r.addView(right);
    ImageView overflow=icon("more",22,MUTED);overflow.setPadding(dp(8),dp(8),dp(8),dp(8));overflow.setContentDescription(I18n.t("Tùy chọn hội thoại"));overflow.setOnClickListener(v->conversationMenu(u.has("members")?"group":"direct",u.optString("id"),title,true));
    r.addView(overflow,new LinearLayout.LayoutParams(dp(40),dp(40)));

    r.setOnClickListener(v -> open.run());
    parent.addView(r);
  }


  private String lastMessages = "";
  private LinearLayout aiChatList; private ScrollView aiChatScroll; private String aiChatSender=""; private Runnable aiChatReload;
  private final java.util.Map<String,JSONObject> aiDrafts=new java.util.HashMap<>();
  private void receiveAIStream(JSONObject event){
    String id=event.optString("id");if(event.optBoolean("done"))aiDrafts.remove(id);else aiDrafts.put(id,event);
    paintAIStream();if(event.optBoolean("done")&&aiChatSender.equals(event.optString("sender"))&&aiChatList!=null&&aiChatList.isAttachedToWindow()&&aiChatReload!=null)aiChatReload.run();
  }
  private void paintAIStream(){
    if(aiChatList==null||!aiChatList.isAttachedToWindow())return;
    boolean bottom=aiChatList.getHeight()-aiChatScroll.getScrollY()-aiChatScroll.getHeight()<dp(64);
    for(int i=aiChatList.getChildCount()-1;i>=0;i--)if("ai-stream".equals(aiChatList.getChildAt(i).getTag()))aiChatList.removeViewAt(i);
    for(JSONObject draft:aiDrafts.values())if(aiChatSender.equals(draft.optString("sender"))){
      TextView text=label(draft.optString("body"),15,TEXT);text.setTag("ai-stream");text.setPadding(dp(12),dp(10),dp(12),dp(10));text.setBackground(background(CARD,14));
      LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-2,-2);lp.rightMargin=dp(48);lp.topMargin=dp(4);aiChatList.addView(text,lp);
    }
    if(bottom)aiChatScroll.post(()->aiChatScroll.fullScroll(View.FOCUS_DOWN));
  }


  private void profile() {
    request("GET", "/api/me", null, data -> {
      me = data.optJSONObject("user");
      profileCompletion();
      profileCard(me, true);
      profileSections(me);
    });
  }

  // Native rendering of the web profile: cover, left identity, actions, bio and statistics.
  private void profileCard(final JSONObject user, final boolean self) {
    LinearLayout panel = card();
    panel.setPadding(0, 0, 0, dp(14));
    panel.setClipChildren(false);
    FrameLayout cover = new FrameLayout(this);
    ImageView image = new ImageView(this);
    image.setScaleType(ImageView.ScaleType.CENTER_CROP);
    image.setBackground(new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, new int[] { PRIMARY_SOFT, SOFT }));
    cover.addView(image, new FrameLayout.LayoutParams(-1, -1));
    if (!user.optString("cover").isEmpty() && !user.isNull("cover")) loadImage(user.optString("cover"), image);
    if (self) {
      FrameLayout edit = new FrameLayout(this);
      edit.setBackground(background(0x66000000, 99));
      edit.addView(icon("camera", 18, WHITE), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
      edit.setContentDescription(I18n.t("Đổi ảnh bìa"));
      edit.setOnClickListener(v -> pickFile(306, "image/*"));
      FrameLayout.LayoutParams at = new FrameLayout.LayoutParams(dp(36), dp(36), Gravity.TOP | Gravity.END);
      at.setMargins(0, dp(8), dp(8), 0);
      cover.addView(edit, at);
    }
    panel.addView(cover, new LinearLayout.LayoutParams(-1, dp(116)));
    LinearLayout identity = row();
    identity.setGravity(Gravity.BOTTOM);
    identity.setPadding(dp(5), 0, dp(5), 0);
    LinearLayout holder = row();
    holder.setPadding(dp(4), dp(4), dp(4), dp(4));
    holder.setBackground(background(CARD, 99));
    ImageView face = avatar(user, holder, 72);
    if (self) face.setOnClickListener(v -> pickAvatar());
    identity.addView(holder, new LinearLayout.LayoutParams(dp(80), dp(80)));
    LinearLayout name = column();
    name.setPadding(dp(10), dp(28), 0, dp(3));
    TextView title = label(user.optString("name"), 17, TEXT);
    title.setTypeface(null, Typeface.BOLD);
    name.addView(title);
    name.addView(label("@" + user.optString("username"), 12, MUTED));
    identity.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
    LinearLayout.LayoutParams identityAt = new LinearLayout.LayoutParams(-1, -2);
    identityAt.topMargin = -dp(28);
    panel.addView(identity, identityAt);
    LinearLayout actions = row();
    actions.setPadding(dp(5), dp(13), dp(5), 0);
    if (self) {
      LinearLayout edit = authButton("pencil", I18n.t("Chỉnh sửa hồ sơ"), true);
      edit.setOnClickListener(v -> editProfile());
      actions.addView(edit, new LinearLayout.LayoutParams(-1, dp(44)));
    } else {
      String friendship = user.optString("friendship");
      String friendLabel = friendship.equals("friends") ? "Bạn bè" : friendship.equals("outgoing") ? "Đã gửi" : friendship.equals("incoming") ? "Chấp nhận" : "Kết bạn";
      LinearLayout friend = authButton(friendship.equals("friends") || friendship.equals("outgoing") ? "user_check" : "user_plus", friendLabel, !friendship.equals("friends") && !friendship.equals("outgoing"));
      friend.setContentDescription(friendship.equals("outgoing") ? I18n.t("Đã gửi lời mời kết bạn. Nhấn để huỷ lời mời") : friendLabel);
      friend.setOnClickListener(v -> profileFriendAction(user));
      actions.addView(friend, new LinearLayout.LayoutParams(0, dp(44), 1));
      LinearLayout message = authButton("message_square", I18n.t("Nhắn tin"), false);
      message.setOnClickListener(v -> chat(user));
      LinearLayout.LayoutParams gap = new LinearLayout.LayoutParams(0, dp(44), 1); gap.leftMargin = dp(8);
      actions.addView(message, gap);
      View more = roundAction("ellipsis", I18n.t("Tuỳ chọn hồ sơ"), false, () -> profileOptions(user));
      LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(dp(44), dp(44)); mp.leftMargin = dp(8);
      more.setLayoutParams(mp);
      actions.addView(more);
    }
    panel.addView(actions);
    if (!user.optString("bio").isEmpty()) {
      TextView bio = label(user.optString("bio"), 13, MUTED);
      bio.setPadding(dp(5), dp(12), dp(5), dp(8)); bio.setLineSpacing(0, 1.6f);
      panel.addView(bio);
    }
    if (user.optJSONArray("interests") != null && user.optJSONArray("interests").length() > 0) panel.addView(label(join(user.optJSONArray("interests")), 12, ACCENT));
    stats(user, panel);
  }

  private void loadImage(String path, ImageView target) {
    final int generation = screen;
    api.image(path, bytes -> {
      if (bytes == null || isDestroyed() || screen != generation) return;
      BitmapFactory.Options options = new BitmapFactory.Options(); options.inJustDecodeBounds = true;
      BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
      options.inSampleSize = Math.max(1, Math.max(options.outWidth, options.outHeight) / 1280); options.inJustDecodeBounds = false;
      Bitmap bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
      if (bitmap != null) target.setImageBitmap(bitmap);
    });
  }

  private void followProfile(JSONObject user) {
    request(user.optBoolean("following") ? "DELETE" : "POST", "/api/users/" + user.optString("id") + "/follow", json(), result -> person(result.optJSONObject("user")));
  }

  private void profileFriendResult(JSONObject user, JSONObject result) {
    JSONObject fresh = result.optJSONObject("user");
    if (fresh != null) { person(fresh); return; }
    try { user.put("friendship", result.optString("status", user.optString("friendship"))); if (result.optString("status").equals("friends")) user.put("following", true); } catch (JSONException ignored) {}
    person(user);
  }

  private void profileFriendAction(final JSONObject user) {
    String state = user.optString("friendship");
    String endpoint = "/api/users/" + user.optString("id") + "/friend-request";
    if (state.equals("friends")) { profileOptions(user); return; }
    if (state.equals("incoming")) { request("POST", endpoint + "/respond", json("action", "accept"), d -> profileFriendResult(user, d)); return; }
    if (state.equals("outgoing")) { confirm(I18n.t("Huỷ lời mời kết bạn?"), () -> request("DELETE", endpoint, json(), d -> profileFriendResult(user, d))); return; }
    request("POST", endpoint, json(), d -> profileFriendResult(user, d));
  }

  private void profileOptions(final JSONObject user) {
    String state = user.optString("friendship");
    List<String> labels = new ArrayList<>(); List<Runnable> actions = new ArrayList<>();
    labels.add(user.optBoolean("following") ? "Bỏ theo dõi" : "Theo dõi"); actions.add(() -> followProfile(user));
    if (state.equals("incoming")) {
      labels.add(I18n.t("Từ chối lời mời")); actions.add(() -> request("POST", "/api/users/" + user.optString("id") + "/friend-request/respond", json("action", "decline"), d -> profileFriendResult(user, d)));
    } else if (state.equals("friends")) {
      labels.add(I18n.t("Huỷ kết bạn")); actions.add(() -> confirm(I18n.t("Huỷ kết bạn với ") + user.optString("name") + "?", () -> request("DELETE", "/api/users/" + user.optString("id") + "/friendship", json(), d -> profileFriendResult(user, d))));
    } else if (state.equals("outgoing")) {
      labels.add(I18n.t("Huỷ lời mời")); actions.add(() -> profileFriendAction(user));
    }
    labels.add(I18n.t("Báo cáo hồ sơ")); actions.add(() -> report("user", user.optString("id")));
    labels.add(I18n.t("Chặn tài khoản")); actions.add(() -> confirm(I18n.t("Chặn ") + user.optString("name") + "?", () -> request("POST", "/api/users/" + user.optString("id") + "/block", json(), d -> navigate("discover"))));
    List<String> icons=new ArrayList<>();for(String item:labels)icons.add(item.contains("Báo cáo")?"flag":item.contains("Chặn")?"user_block":item.contains("theo dõi")||item.equals("Theo dõi")?"heart": "users_round");
    chatActionSheet(I18n.t("Tùy chọn hồ sơ"),icons,labels,actions);
  }

  private View profileAbout(final JSONObject source) {
    JSONObject user;try{user=new JSONObject(source.toString());}catch(Exception ignored){user=json();}
    JSONObject visibility=user.optJSONObject("profileVisibility");
    for(String key:new String[]{"bio","age","city","height","weight","occupation","school","gender","orientation","communityRole","pronouns","relationshipRole","lookingFor","interests"})if(visibility!=null&&!visibility.optBoolean(key,true))user.remove(key);
    if(user.has("identityPublic")&&!user.optBoolean("identityPublic"))for(String key:new String[]{"gender","orientation","communityRole","pronouns","relationshipRole"})user.remove(key);
    LinearLayout panel=column();panel.setBackground(outlined(CARD,16));panel.setPadding(dp(16),dp(16),dp(16),dp(16));
    LinearLayout heading=row();TextView title=label(I18n.t("Giới thiệu"),18,TEXT);title.setTypeface(null,Typeface.BOLD);heading.addView(title,new LinearLayout.LayoutParams(0,-2,1));heading.addView(icon("globe",14,MUTED),new LinearLayout.LayoutParams(dp(14),dp(14)));TextView publicLabel=label(I18n.t("Công khai"),12,MUTED);publicLabel.setPadding(dp(5),0,0,0);heading.addView(publicLabel);panel.addView(heading);
    boolean filled=false;String bio=user.optString("bio").trim();
    if(!bio.isEmpty()){TextView caption=label(I18n.t("Tiểu sử"),12,MUTED);caption.setPadding(0,dp(18),0,dp(6));panel.addView(caption);TextView text=label(bio,14,TEXT);text.setLineSpacing(0,1.3f);panel.addView(text);filled=true;}
    String[][] fields={{"age","Tuổi"," tuổi"},{"city","Nơi sống",""},{"height","Chiều cao"," cm"},{"weight","Cân nặng"," kg"},{"occupation","Nghề nghiệp",""},{"school","Trường học",""},{"gender","Bản dạng giới",""},{"orientation","Xu hướng",""},{"communityRole","Vai trò cộng đồng",""},{"pronouns","Cách xưng hô",""},{"relationshipRole","Tình trạng quan hệ",""},{"lookingFor","Mong muốn",""}};
    for(String[] field:fields){String value=user.isNull(field[0])?"":user.optString(field[0]).trim();if(value.isEmpty()||value.equals("0"))continue;LinearLayout item=column();item.setPadding(0,dp(12),0,dp(12));item.addView(label(I18n.t(field[1]),12,MUTED));TextView text=label((java.util.Arrays.asList("gender","orientation","communityRole","pronouns","relationshipRole","lookingFor").contains(field[0])?I18n.t(value):value)+I18n.t(field[2]),14,TEXT);text.setPadding(0,dp(5),0,0);item.addView(text);panel.addView(item);panel.addView(divider());filled=true;}
    JSONArray interests=user.optJSONArray("interests");if(interests!=null&&interests.length()>0){TextView caption=label(I18n.t("Sở thích"),12,MUTED);caption.setPadding(0,dp(18),0,dp(6));panel.addView(caption);LinearLayout chips=row();panel.addView(chips);int used=0,available=getResources().getDisplayMetrics().widthPixels-dp(80);
      for(int i=0;i<interests.length();i++){TextView text=label(interests.optString(i),13,ACCENT);text.setPadding(dp(10),dp(7),dp(10),dp(7));text.setBackground(background(PRIMARY_SOFT,10));text.setMaxWidth(available);text.measure(View.MeasureSpec.makeMeasureSpec(available,View.MeasureSpec.AT_MOST),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));int width=text.getMeasuredWidth()+dp(6);if(used>0&&used+width>available){chips=row();panel.addView(chips);used=0;}LinearLayout.LayoutParams chipAt=new LinearLayout.LayoutParams(-2,-2);chipAt.rightMargin=dp(6);chipAt.bottomMargin=dp(6);chips.addView(text,chipAt);used+=width;}filled=true;}
    boolean own=me!=null&&user.optString("id").equals(me.optString("id"));
    if(!filled)panel.addView(emptyBlock("user",I18n.t("Chưa có thông tin công khai"),own?I18n.t("Cập nhật hồ sơ để mọi người hiểu bạn hơn."):I18n.t("Thành viên này chưa chia sẻ thông tin giới thiệu.")));
    if(user.optLong("joinedAt")>0){TextView joined=label(I18n.t("Tham gia Kinnect từ ")+new java.text.SimpleDateFormat("MM/yyyy",java.util.Locale.getDefault()).format(new java.util.Date(user.optLong("joinedAt"))),12,MUTED);joined.setPadding(0,dp(18),0,dp(12));panel.addView(joined);}
    if(own)panel.addView(button(I18n.t("Chỉnh sửa hồ sơ"),()->editProfile()));return panel;
  }

  private void profileSections(final JSONObject user) {
    final LinearLayout controls = row(), list = column();
    final String[] tabs = { "Giới thiệu", "Bài viết", "Album ảnh", "Video" };
    final int[] selected = { 1 }, generation = { 0 };
    final int ownerScreen = screen;
    final Runnable[] render = new Runnable[1];
    render[0] = () -> {
      final int revision = ++generation[0];
      // Keep the tab views mounted: removing the focused tab resets ScrollView focus/position.
      // Size to actual posts/empty state; a full viewport here adds a blank screen below the profile.
      list.setMinimumHeight(0);
      list.removeAllViews();
      for(int i=0;i<controls.getChildCount();i++) {
        TextView item=(TextView)controls.getChildAt(i);boolean active=i==selected[0];
        item.setTextColor(active?ACCENT:TEXT);item.setTypeface(Typeface.create(active?"sans-serif-medium":"sans-serif",Typeface.NORMAL));
        item.setBackground(active?background(CARD,11):pressable(SOFT,11));item.setElevation(active?dp(1):0);item.setSelected(active);
      }
      final int current = selected[0];
      if(current==0){list.addView(profileAbout(user));return;}
      request("GET", current == 3 ? "/api/shorts?user=" + user.optString("id") : "/api/posts?user=" + user.optString("id"), null, data -> {
        if (current != selected[0] || revision != generation[0] || ownerScreen != screen || !list.isAttachedToWindow()) return;
        if (current == 3) {
          final JSONArray videos = data.optJSONArray("shorts");
          if (videos == null || videos.length() == 0) { list.addView(emptyBlock("clapperboard", I18n.t("Chưa có video"), I18n.t("Video ngắn sẽ hiển thị tại đây."))); return; }
          LinearLayout line = null;
          for (int i = 0; i < videos.length(); i++) {
            final int index = i;
            if (i % 3 == 0) { line = row(); list.addView(line); }
            FrameLayout tile = new FrameLayout(this);
            GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff42355d, 0xff1d1929 });
            g.setCornerRadius(dp(12));
            tile.setBackground(g);
            tile.addView(icon("play", 26, WHITE), new FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER));
            TextView dur = label(Math.round(videos.optJSONObject(i).optDouble("duration")) + "s", 11, WHITE);
            FrameLayout.LayoutParams dp2 = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.START);
            dp2.setMargins(dp(8), 0, 0, dp(6));
            tile.addView(dur, dp2);
            tile.setContentDescription("Xem video " + (i + 1));
            tile.setOnClickListener(v -> { shortsFollowing = false; shortRows = videos; showShort(index); });
            int w = (getResources().getDisplayMetrics().widthPixels - dp(48)) / 3;
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, w * 16 / 10, 1);
            lp.setMargins(i % 3 == 0 ? 0 : dp(3), dp(3), i % 3 == 2 ? 0 : dp(3), dp(3));
            line.addView(tile, lp);
          }
          for (int pad = videos.length() % 3; pad > 0 && pad < 3; pad++) line.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
        } else if (current == 2) {
          List<JSONObject> photos = new ArrayList<>(); JSONArray posts = data.optJSONArray("posts");
          for (int i = 0; posts != null && i < posts.length(); i++) { JSONObject media = posts.optJSONObject(i).optJSONObject("media"); if (media != null && media.optString("kind").equals("image")) photos.add(media); }
          final boolean own = user.optString("id").equals(me.optString("id"));
          LinearLayout privateRow = row();
          privateRow.setPadding(dp(12), 0, dp(12), 0);
          privateRow.setBackground(outlined(CARD, 14));
          FrameLayout lock = new FrameLayout(this);
          lock.setBackground(background(PRIMARY_SOFT, 10));
          lock.addView(icon("lock_keyhole", 18, ACCENT), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
          privateRow.addView(lock, new LinearLayout.LayoutParams(dp(36), dp(36)));
          TextView pl = label(own ? I18n.t("Ảnh riêng tư") : I18n.t("Album riêng tư"), 15, TEXT);
          pl.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
          pl.setPadding(dp(12), 0, 0, 0);
          privateRow.addView(pl, new LinearLayout.LayoutParams(0, -2, 1));
          privateRow.addView(icon("chevron_right", 17, MUTED), new LinearLayout.LayoutParams(dp(17), dp(17)));
          privateRow.setOnClickListener(v -> privateAlbum(user));
          LinearLayout.LayoutParams pr = new LinearLayout.LayoutParams(-1, dp(56));
          pr.bottomMargin = dp(10);
          list.addView(privateRow, pr);
          if (photos.isEmpty()) { list.addView(emptyBlock("image", I18n.t("Chưa có ảnh"), I18n.t("Ảnh đã đăng sẽ hiển thị tại đây."))); return; }
          LinearLayout line = null;
          int w = (getResources().getDisplayMetrics().widthPixels - dp(48)) / 3;
          for (int i = 0; i < photos.size(); i++) {
            if (i % 3 == 0) { line = row(); list.addView(line); }
            ImageView img = new ImageView(this);
            img.setScaleType(ImageView.ScaleType.CENTER_CROP);
            img.setBackground(background(SOFT, 12));
            img.setClipToOutline(true);
            loadImage(photos.get(i).optString("url"), img);
            final JSONObject photo = photos.get(i);
            img.setOnClickListener(v -> openPhoto(photo.optString("url"), () -> person(user)));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, w, 1);
            lp.setMargins(i % 3 == 0 ? 0 : dp(3), dp(3), i % 3 == 2 ? 0 : dp(3), dp(3));
            line.addView(img, lp);
          }
          for (int pad = photos.size() % 3; pad > 0 && pad < 3; pad++) line.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
        } else { LinearLayout saved = content; content = list; posts(data.optJSONArray("posts"), "Chưa có bài viết."); content = saved; }
      });
    };
    LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(-1, -2);
    cp.setMargins(0, dp(6), 0, dp(10));
    segmented(controls, tabs, selected[0], i -> { if(selected[0]==i)return;selected[0] = i; render[0].run(); });
    HorizontalScrollView tabScroll=new HorizontalScrollView(this);tabScroll.setHorizontalScrollBarEnabled(false);tabScroll.setFillViewport(true);
    for(int i=0;i<controls.getChildCount();i++){TextView tab=(TextView)controls.getChildAt(i);tab.setMinWidth(dp(82));tab.setPadding(dp(10),0,dp(10),0);tab.setLayoutParams(new LinearLayout.LayoutParams(-2,dp(38)));}
    tabScroll.addView(controls,new HorizontalScrollView.LayoutParams(-1,-2));content.addView(tabScroll,cp);content.addView(list);render[0].run();
  }

  private void privateAlbum(final JSONObject owner) {
    accountHeader(I18n.t("Ảnh riêng tư"), () -> person(owner));
    final boolean mine = owner.optString("id").equals(me.optString("id"));
    request("GET", "/api/users/" + owner.optString("id") + "/private", null, data -> {
      String status = data.optString("status");
      content.addView(label(I18n.t("Chỉ người được cấp quyền"), 13, MUTED));
      if (mine) content.addView(button(I18n.t("Thêm ảnh"), () -> pickFile(308, "image/*")));
      if (!status.equals("owner") && !status.equals("granted")) {
        content.addView(label(status.equals("pending") ? I18n.t("Yêu cầu của bạn đang chờ chủ album duyệt.") : I18n.t("Gửi yêu cầu để chủ album cấp quyền xem ảnh."), 14, MUTED));
        Button ask = primary(status.equals("pending") ? I18n.t("Đang chờ duyệt") : I18n.t("Yêu cầu xem ảnh"), () -> request("POST", "/api/users/" + owner.optString("id") + "/private/request", json(), result -> privateAlbum(owner)));
        ask.setEnabled(!status.equals("pending")); content.addView(ask); return;
      }
      JSONArray photos = data.optJSONArray("photos");
      if (photos == null || photos.length() == 0) content.addView(label(I18n.t("Album chưa có ảnh"), 14, MUTED));
      for (int i = 0; photos != null && i < photos.length(); i++) {
        final JSONObject photo = photos.optJSONObject(i);
        LinearLayout panel = card(); ImageView image = new ImageView(this);
        image.setAdjustViewBounds(true); image.setScaleType(ImageView.ScaleType.FIT_CENTER);
        panel.addView(image, new LinearLayout.LayoutParams(-1, -2)); loadImage(photo.optString("url"), image);
        if (mine) panel.addView(button(I18n.t("Xoá ảnh"), () -> confirm(I18n.t("Xoá ảnh riêng tư này?"), () -> request("DELETE", "/api/me/private-photos/" + photo.optString("id"), json(), result -> privateAlbum(owner)))));
      }
      if (mine) request("GET", "/api/me/private/requests", null, result -> {
        content.addView(sectionLabel(I18n.t("Quyền truy cập"))); JSONArray requests = result.optJSONArray("requests");
        for (int i = 0; requests != null && i < requests.length(); i++) {
          JSONObject entry = requests.optJSONObject(i), user = entry.optJSONObject("user");
          LinearLayout panel = card(); panel.addView(label(user.optString("name"), 14, TEXT));
          for (String action : entry.optString("status").equals("pending") ? new String[] { "grant", "deny" } : new String[] { "revoke" }) panel.addView(button(action.equals("grant") ? I18n.t("Đồng ý") : action.equals("deny") ? I18n.t("Từ chối") : I18n.t("Thu hồi"), () -> request("POST", "/api/me/private/requests/" + user.optString("id"), json("action", action), changed -> privateAlbum(owner))));
        }
        if (requests == null || requests.length() == 0) content.addView(label(I18n.t("Chưa có yêu cầu xem ảnh."), 14, MUTED));
      });
    });
  }

  private ImageView profileEditorAvatar;

  private void editProfile() {
    remember("edit-profile", () -> editProfile());
    accountHeader(I18n.t("Chỉnh sửa hồ sơ"), () -> navigate("profile"));
    request("GET", "/api/me", null, data -> {
      me = data.optJSONObject("user");
      final JSONObject visibility = json();
      JSONObject current = me.optJSONObject("profileVisibility");
      for (String key : new String[] { "bio", "age", "gender", "orientation", "communityRole", "pronouns", "relationshipRole", "lookingFor", "city", "interests", "height", "weight", "occupation", "school" }) {
        boolean identity = Arrays.asList("gender", "orientation", "communityRole", "pronouns", "relationshipRole").contains(key);
        boolean shared = current == null || current.optBoolean(key, true);
        if (identity && !me.optBoolean("identityPublic") && !me.optString(key).isEmpty()) shared = false;
        try { visibility.put(key, shared); } catch (JSONException ignored) {}
      }
      final Map<String, EditText> fields = new LinkedHashMap<>();
      LinearLayout media = row();
      profileEditorAvatar = avatar(me, media, 48);
      media.addView(roundAction("camera", I18n.t("Đổi ảnh đại diện"), false, () -> pickAvatar()));
      media.addView(roundAction("image", I18n.t("Đổi ảnh bìa"), false, () -> pickFile(306, "image/*")));
      media.addView(roundAction("eye", I18n.t("Xem trước hồ sơ công khai"), false, () -> previewProfile(fields, visibility)));
      content.addView(media);
      content.addView(label(I18n.t("Chạm 🌐 / 🔒 để chọn thông tin công khai."), 12, MUTED));
      LinearLayout basic = profileEditorGroup("user_round", I18n.t("Thông tin cơ bản"), true);
      fields.put("name", profileEditorField(basic, "name", I18n.t("Tên hiển thị"), visibility, null, 60, false));
      fields.put("birthDate", profileEditorField(basic, "birthDate", I18n.t("Ngày sinh"), visibility, null, 10, false));
      basic.addView(label(I18n.t("Ngày sinh chỉ bạn xem; biểu tượng 🌐 cho phép hiện tuổi."), 12, MUTED));
      LinearLayout about = profileEditorGroup("pen_line", I18n.t("Giới thiệu và sở thích"), true);
      fields.put("bio", profileEditorField(about, "bio", I18n.t("Giới thiệu"), visibility, null, 500, true));
      fields.put("interests", profileEditorField(about, "interests", I18n.t("Sở thích"), visibility, null, 320, false));
      addProfileTags(about, fields.get("interests"), new String[] { "Nhiếp ảnh", "Du lịch", "Âm nhạc", "Đọc sách", "Thể thao", "Ẩm thực", "Phim ảnh", "Công nghệ", "Nghệ thuật", "Thiên nhiên", "Game", "Thú cưng" }, 10);
      LinearLayout identity = profileEditorGroup("user_round", I18n.t("Bản thân và cách xưng hô"), false);
      fields.put("gender", profileEditorField(identity, "gender", I18n.t("Bản dạng giới"), visibility, new String[] { "Nam", "Nữ", "Nam chuyển giới", "Nữ chuyển giới", "Phi nhị nguyên", "Linh hoạt giới", "Vô giới", "Đang tìm hiểu", "Khác" }, 60, false));
      fields.put("height",profileEditorField(identity,"height",I18n.t("Chiều cao (cm)"),visibility,null,3,false));fields.get("height").setInputType(2);
      fields.put("weight",profileEditorField(identity,"weight",I18n.t("Cân nặng (kg)"),visibility,null,3,false));fields.get("weight").setInputType(2);
      fields.put("orientation", profileEditorField(identity, "orientation", I18n.t("Xu hướng tính dục"), visibility, new String[] { "Dị tính", "Gay / Đồng tính nam", "Lesbian / Đồng tính nữ", "Song tính / Bisexual", "Toàn tính / Pansexual", "Vô tính / Asexual", "Queer", "Á tính / Demisexual", "Đang tìm hiểu", "Khác" }, 60, false));
      fields.put("communityRole", profileEditorField(identity,"communityRole",I18n.t("Vai trò tự mô tả (tùy chọn)"),visibility,new String[]{"Top","Bottom","Vers","Vers Top","Vers Bottom","Side","Femme","Masc / Butch","Androgynous","Stem","Đang tìm hiểu","Khác"},60,false));
      fields.put("pronouns", profileEditorField(identity, "pronouns", I18n.t("Cách xưng hô"), visibility, new String[] { "Anh", "Chị", "Em", "Bạn", "Họ / They" }, 30, false));
      LinearLayout connection = profileEditorGroup("users_round", I18n.t("Kết nối và cuộc sống"), false);
      fields.put("relationshipRole", profileEditorField(connection, "relationshipRole", I18n.t("Tình trạng quan hệ"), visibility, new String[] { "Độc thân", "Đang tìm hiểu", "Đang trong mối quan hệ", "Đã kết hôn", "Mối quan hệ mở" }, 40, false));
      fields.put("lookingFor", profileEditorField(connection, "lookingFor", I18n.t("Mong muốn kết nối"), visibility, null, 300, false));
      addProfileTags(connection, fields.get("lookingFor"), new String[] { "Kết bạn", "Trò chuyện", "Hẹn hò", "Mối quan hệ nghiêm túc", "Cùng sở thích" }, 20);
      fields.put("city", profileEditorField(connection, "city", I18n.t("Nơi sống"), visibility, null, 80, false));
      fields.put("occupation", profileEditorField(connection, "occupation", I18n.t("Nghề nghiệp"), visibility, null, 100, false));
      fields.put("school", profileEditorField(connection, "school", I18n.t("Trường học"), visibility, null, 100, false));
      final LinearLayout save = authButton("check", I18n.t("Lưu"), true);
      save.setOnClickListener(v -> {
        if (!save.isEnabled()) return;
        if (fields.get("name").getText().toString().trim().isEmpty()) { fields.get("name").setError(I18n.t("Nhập tên hiển thị")); return; }
        JSONObject payload = json("identityPublic", true, "profileVisibility", visibility);
        for (Map.Entry<String, EditText> entry : fields.entrySet()) try {
          String value = entry.getValue().getTag() instanceof ProfileValue ? ((ProfileValue)entry.getValue().getTag()).value : entry.getValue().getText().toString().trim();
          if (entry.getKey().equals("interests")) {
            JSONArray tags = new JSONArray();
            for (String tag : value.split(",")) if (!tag.trim().isEmpty()) tags.put(tag.trim());
            payload.put("interests", tags);
          } else payload.put(entry.getKey(), value);
        } catch (JSONException ignored) {}
        save.setEnabled(false); save.setAlpha(0.5f);
        request("PATCH", "/api/me", payload, result -> { me = result.optJSONObject("user"); say(I18n.t("Đã lưu hồ sơ")); navigate("profile"); }, () -> { save.setEnabled(true); save.setAlpha(1f); });
      });
      LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, dp(48)); sp.topMargin = dp(14);
      content.addView(save, sp);
    });
  }

  private LinearLayout profileEditorGroup(String iconName, String title, boolean expanded) {
    LinearLayout group = card();
    LinearLayout head = row(), body = column();
    head.addView(icon(iconName, 20, ACCENT), new LinearLayout.LayoutParams(dp(20), dp(20)));
    TextView caption = label(title, 15, TEXT); caption.setTypeface(null, Typeface.BOLD); caption.setPadding(dp(10), 0, 0, 0); caption.setGravity(Gravity.CENTER_VERTICAL); caption.setSingleLine(true); caption.setEllipsize(android.text.TextUtils.TruncateAt.END);
    head.addView(caption, new LinearLayout.LayoutParams(0, dp(44), 1));
    final ImageView arrow = icon(expanded ? "chevron_up" : "chevron_down", 18, MUTED);
    head.addView(arrow, new LinearLayout.LayoutParams(dp(18), dp(18)));
    body.setVisibility(expanded ? View.VISIBLE : View.GONE);
    head.setContentDescription(title + (expanded ? I18n.t(" · Thu gọn") : I18n.t(" · Mở rộng")));
    head.setBackground(pressable(CARD, 10));
    head.setOnClickListener(v -> {
      boolean open = body.getVisibility() != View.VISIBLE;
      body.setVisibility(open ? View.VISIBLE : View.GONE);
      android.graphics.drawable.Drawable d = WebIcons.load(this, open ? "chevron_up" : "chevron_down"); d.setTint(MUTED); arrow.setImageDrawable(d);
      head.setContentDescription(title + (open ? I18n.t(" · Thu gọn") : I18n.t(" · Mở rộng")));
    });
    group.addView(head); group.addView(body);
    return body;
  }

  private static final class ProfileValue { final String value; ProfileValue(String value){this.value=value;} }
  private void setProfileChoice(EditText field,String value){field.setTag(new ProfileValue(value));field.setText(I18n.t(value));}
  private EditText profileEditorField(LinearLayout into, String key, String title, JSONObject visibility, String[] choices, int maximum, boolean multiline) {
    LinearLayout head = row();
    TextView name = label(title, 13, MUTED); head.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
    String value = (key.equals("height")||key.equals("weight"))&&me.isNull(key)?"":key.equals("interests") ? join(me.optJSONArray("interests")).replace(" · ", ", ") : me.optString(key);
    final EditText field = input(into, title, value, multiline);
    field.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(maximum) });
    if(choices!=null){setProfileChoice(field,value);field.setFocusable(false);field.setOnClickListener(v->new Sheet(this).setTitle(I18n.t(title)).setItems(I18n.items(choices),(d,w)->setProfileChoice(field,choices[w])).setNeutralButton(I18n.t("Để trống"),(d,w)->setProfileChoice(field,"")).show());}
    if (choices != null) head.addView(roundAction("chevron_down", I18n.t("Chọn ") + title.toLowerCase(Locale.ROOT), false, () -> {
      String[] labels = new String[choices.length + 1]; labels[0] = "Không muốn tiết lộ";
      System.arraycopy(choices, 0, labels, 1, choices.length);
      new Sheet(this).setTitle(I18n.t(title)).setItems(I18n.items(labels), (d, w) -> setProfileChoice(field,w == 0 ? "" : choices[w - 1])).show();
    }));
    if (!key.equals("name")) {
      final String sharedKey = key.equals("birthDate") ? "age" : key;
      FrameLayout toggle = new FrameLayout(this);
      final Runnable draw = () -> {
        boolean shared = visibility.optBoolean(sharedKey, true);
        toggle.removeAllViews(); toggle.addView(icon(shared ? "globe" : "lock_keyhole", 18, shared ? ACCENT : MUTED), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
        toggle.setContentDescription((shared ? I18n.t("Ẩn ") : I18n.t("Công khai ")) + (key.equals("birthDate") ? I18n.t("tuổi") : title.toLowerCase(Locale.ROOT)));
        toggle.setTooltipText(shared ? I18n.t("Đang công khai") : I18n.t("Chỉ mình tôi"));
      };
      draw.run(); toggle.setBackground(pressable(CARD, 99));
      toggle.setOnClickListener(v -> { try { visibility.put(sharedKey, !visibility.optBoolean(sharedKey, true)); } catch (JSONException ignored) {} draw.run(); });
      head.addView(toggle, new LinearLayout.LayoutParams(dp(44), dp(44)));
    }
    int at = into.indexOfChild(field); into.addView(head, at);
    if (key.equals("birthDate")) {
      field.setHint("YYYY-MM-DD"); field.setFocusable(false);
      field.setOnClickListener(v -> {
        final Calendar date = Calendar.getInstance(); date.add(Calendar.YEAR, -18);
        try { String[] parts = field.getText().toString().split("-"); if (parts.length == 3) date.set(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]) - 1, Integer.parseInt(parts[2])); } catch (Exception ignored) {}
        DatePickerDialog picker = new DatePickerDialog(this, (d, year, month, day) -> field.setText(String.format(Locale.ROOT, "%04d-%02d-%02d", year, month + 1, day)), date.get(Calendar.YEAR), date.get(Calendar.MONTH), date.get(Calendar.DAY_OF_MONTH));
        Calendar latest = Calendar.getInstance(); latest.add(Calendar.YEAR, -18); picker.getDatePicker().setMaxDate(latest.getTimeInMillis());
        picker.setButton(DialogInterface.BUTTON_NEUTRAL, "Để trống", (d, w) -> field.setText("")); picker.show();
      });
    }
    return field;
  }

  private void addProfileTags(LinearLayout into, EditText field, String[] choices, int maximum) {
    final LinearLayout chips = row(); into.addView(hscroll(chips));
    final Runnable[] render = new Runnable[1];
    render[0] = () -> {
      chips.removeAllViews();
      Set<String> values = new LinkedHashSet<>();
      for (String value : field.getText().toString().split(",")) if (!value.trim().isEmpty()) values.add(value.trim().toLowerCase(Locale.ROOT));
      for (String choice : choices) chips.addView(webChip(choice, values.contains(choice.toLowerCase(Locale.ROOT)), false, () -> {
        String value = choice.toLowerCase(Locale.ROOT);
        if (values.contains(value)) values.remove(value);
        else { if (values.size() >= maximum) { say(I18n.t("Tối đa ") + maximum + I18n.t(" lựa chọn")); return; } values.add(value); }
        field.setText(android.text.TextUtils.join(", ", values));
      }));
    };
    field.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
      public void onTextChanged(CharSequence s, int a, int b, int c) {}
      public void afterTextChanged(android.text.Editable s) { render[0].run(); }
    });
    render[0].run();
  }

  private void previewProfile(Map<String, EditText> fields, JSONObject visibility) {
    LinearLayout preview = column();
    avatar(me, preview, 64);
    for (Map.Entry<String, EditText> entry : fields.entrySet()) {
      String key = entry.getKey(), value = entry.getValue().getText().toString().trim();
      if (key.equals("birthDate")) {
        if (!visibility.optBoolean("age", true) || value.isEmpty()) continue;
        try {
          java.text.SimpleDateFormat format = new java.text.SimpleDateFormat("yyyy-MM-dd", Locale.ROOT); format.setLenient(false);
          Calendar birth = Calendar.getInstance(), today = Calendar.getInstance(); birth.setTime(format.parse(value));
          int age = today.get(Calendar.YEAR) - birth.get(Calendar.YEAR);
          if (today.get(Calendar.MONTH) < birth.get(Calendar.MONTH) || (today.get(Calendar.MONTH) == birth.get(Calendar.MONTH) && today.get(Calendar.DAY_OF_MONTH) < birth.get(Calendar.DAY_OF_MONTH))) age--;
          value = age + " tuổi";
        } catch (Exception ignored) { continue; }
      } else if (!key.equals("name") && !visibility.optBoolean(key, true)) continue;
      if (!value.isEmpty()) preview.addView(label(value, key.equals("name") ? 18 : 14, key.equals("name") ? TEXT : MUTED));
    }
    ScrollView scroll = new ScrollView(this); scroll.addView(preview);
    scroll.setLayoutParams(new LinearLayout.LayoutParams(-1, Math.min(dp(420), getResources().getDisplayMetrics().heightPixels / 2)));
    new Sheet(this).setTitle(I18n.t("Hồ sơ công khai · Xem trước")).setView(scroll).setNegativeButton(I18n.t("Đóng"), null).show();
  }
  private void blocks() {
    shell(I18n.t("Người đã chặn"), true);
    request("GET", "/api/blocks", null, data -> {
      JSONArray users = data.optJSONArray("users");
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        content.addView(
          button(I18n.t("Bỏ chặn ") + u.optString("name"), () ->
            request(
              "DELETE",
              "/api/users/" + u.optString("id") + "/block",
              json(),
              d -> blocks()
            )
          )
        );
      }
      if (users == null || users.length() == 0) content.addView(
        label(I18n.t("Bạn chưa chặn ai."), 16, MUTED)
      );
    });
  }

  private void notifications() {
    remember("notifications", () -> notifications());
    headerActive = "bell";
    badgesAt = 0;
    shell(I18n.t("Thông báo"), true);
    if (headActions != null) headActions.addView(roundAction("check", I18n.t("Đánh dấu tất cả đã đọc"), false, () -> request("POST", "/api/notifications", json(), d -> { bellCount = 0; badgesAt = 0; notifications(); })));
    request("GET", "/api/notifications", null, data -> {
      JSONArray rows = data.optJSONArray("notifications");
      for (int i = 0; rows != null && i < rows.length(); i++) {
        final JSONObject n = rows.optJSONObject(i), u = n.optJSONObject("actor");
        LinearLayout r = row();
        r.setPadding(dp(12), dp(10), dp(12), dp(10));
        r.setBackground(background(n.optInt("seen") == 0 ? PRIMARY_SOFT : CARD, 14));
        avatar(u, r, 46);
        LinearLayout t = column();
        t.setPadding(dp(12), 0, dp(8), 0);
        TextView line = new TextView(this);
        android.text.SpannableStringBuilder sb = new android.text.SpannableStringBuilder(u.optString("name"));
        sb.setSpan(new android.text.style.StyleSpan(Typeface.BOLD), 0, sb.length(), 0);
        sb.append(noticeText(n.optString("kind")));
        line.setText(sb);
        line.setTextColor(TEXT);
        line.setTextSize(15);
        t.addView(line);
        t.addView(label(ago(n.optLong("created")), 12, n.optInt("seen") == 0 ? ACCENT : MUTED));
        r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
        if (n.optInt("seen") == 0) {
          View dot = new View(this);
          dot.setBackground(background(ACCENT, 99));
          r.addView(dot, new LinearLayout.LayoutParams(dp(10), dp(10)));
        }
        r.setOnClickListener(v -> {
          if (n.optInt("seen") == 0) try { api.call("POST", "/api/notifications", new JSONObject().put("ids", new JSONArray().put(n.optString("id"))), (d, e, s) -> {}); } catch (JSONException ignored) {}
          badgesAt = 0;
          openNotification(n);
        });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        content.addView(r, p);
      }
      if (rows == null || rows.length() == 0) {
        content.addView(emptyBlock("bell",I18n.t("Chưa có thông báo mới"),I18n.t("Thông báo mới sẽ hiển thị tại đây.")));
      }
    });
  }

  private void openNotification(JSONObject notification) {
    String kind = notification.optString("kind"), ref = notification.optString("ref");
    JSONObject actor = notification.optJSONObject("actor");
    if (kind.equals("message") || kind.equals("missed_call")) { chat(actor); return; }
    if (kind.equals("group_message")) { request("GET", "/api/groups/" + encode(ref), null, data -> groupChat(data.optJSONObject("group"))); return; }
    if (kind.equals("like") || kind.equals("comment") || kind.equals("comment_reply")) { postDetail(ref, notification.isNull("commentId") ? "" : notification.optString("commentId")); return; }
    if (kind.equals("short_like") || kind.equals("short_comment")) {
      request("GET", "/api/shorts?video=" + encode(ref), null, data -> {
        shortRows = data.optJSONArray("shorts"); shortsFollowing = false;
        int index = -1;
        for (int i = 0; shortRows != null && i < shortRows.length(); i++) if (ref.equals(shortRows.optJSONObject(i).optString("id"))) { index = i; break; }
        if (index < 0) { say(I18n.t("Video không còn khả dụng")); return; }
        showShort(index);
        if (kind.equals("short_comment")) shortComments(shortRows.optJSONObject(index));
      });
      return;
    }
    if (kind.startsWith("private_")) { privateAlbum(kind.equals("private_request") ? me : json("id", ref)); return; }
    if (kind.equals("friend_request")) { friendsScreen("incoming"); return; }
    if (kind.equals("friend_accept") || kind.equals("friend_accepted")) { friendsScreen("friends"); return; }
    if (actor != null) person(actor);
  }

  private void postDetail(String id, String commentId) {
    remember("post:" + id, () -> postDetail(id, commentId));
    accountHeader(I18n.t("Bài viết"), () -> notifications());
    request("GET", "/api/posts?post=" + encode(id), null, data -> {
      JSONArray rows = data.optJSONArray("posts");
      if (rows == null || rows.length() == 0) { content.addView(emptyBlock("newspaper", I18n.t("Bài viết không còn khả dụng"), "")); return; }
      postCard(rows.optJSONObject(0), commentId);
    });
  }

  private EditText aiField(LinearLayout into,String title,String value,boolean secret){into.addView(label(title,13,TEXT));EditText field=input(into,title,value,false);field.setSaveEnabled(false);if(secret){field.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD);if(android.os.Build.VERSION.SDK_INT>=26)field.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);}return field;}
  private void adminAI(){
    accountHeader(I18n.t("Trợ lý AI và kiểm duyệt"),()->admin());if(me==null||!me.optString("role").equals("admin")){content.addView(label(I18n.t("Chỉ quản trị viên được cấu hình AI."),14,MUTED));return;}
    final LinearLayout page=content;final TextView state=label(I18n.t("Đang tải cấu hình AI…"),14,MUTED);page.addView(state);final boolean[] loaded={false};request("GET","/api/admin/ai",null,data->{JSONObject config=data.optJSONObject("config"),credentials=data.optJSONObject("credentials");if(config==null||credentials==null)return;loaded[0]=true;state.setText(config.optBoolean("ready")?I18n.t("Cloudflare · Đã có cấu hình"):I18n.t("Cloudflare · Chưa có cấu hình"));
      page.addView(label(I18n.t("Cloudflare chính · NVIDIA dự phòng"),18,TEXT));page.addView(label(I18n.t("Khóa chỉ lưu tại máy chủ Kinnect. Để trống để giữ khóa đã lưu."),13,MUTED));
      LinearLayout form=card();page.addView(form);final EditText url=aiField(form,"URL Worker Cloudflare",credentials.optString("workerUrl"),false),token=aiField(form,credentials.optBoolean("tokenSaved")?"Khóa Worker · Đã lưu":"Khóa kết nối Worker","",true),key=aiField(form,credentials.optBoolean("nvidiaKeySaved")?"Khóa NVIDIA · Đã lưu":"Khóa NVIDIA API","",true),model=aiField(form,"Model NVIDIA văn bản",credentials.optString("nvidiaModel"),false),vision=aiField(form,"Model NVIDIA ảnh (tùy chọn)",credentials.optString("nvidiaVisionModel"),false);
      final CheckBox fallback=new CheckBox(this);fallback.setText(I18n.t("Tự chuyển NVIDIA khi Cloudflare lỗi"));fallback.setTextColor(TEXT);fallback.setChecked(credentials.optBoolean("fallbackEnabled"));form.addView(fallback);final EditText password=aiField(form,"Mật khẩu quản trị để lưu","",true);
      final TextView feedback=label("",13,MUTED);form.addView(feedback);final View[] saving={null};saving[0]=primary(I18n.t("Lưu kết nối AI"),()->{if(password.getText().toString().isEmpty()){feedback.setText(I18n.t("Nhập mật khẩu quản trị để lưu cấu hình."));return;}saving[0].setEnabled(false);JSONObject payload=json("workerUrl",url.getText().toString().trim(),"token",token.getText().toString().trim(),"nvidiaKey",key.getText().toString().trim(),"nvidiaModel",model.getText().toString().trim(),"nvidiaVisionModel",vision.getText().toString().trim(),"fallbackEnabled",fallback.isChecked(),"password",password.getText().toString());request("PATCH","/api/admin/ai/credentials",payload,d->{feedback.setText(I18n.t("Đã lưu kết nối AI trên máy chủ."));},()->{token.setText("");key.setText("");password.setText("");saving[0].setEnabled(true);});});form.addView(saving[0]);
      String[][] providers={{"cloudflare","Kiểm tra Cloudflare"},{"nvidia","Kiểm tra NVIDIA"},{"fallback","Kiểm tra chuyển dự phòng"}};for(final String[] provider:providers){final View[] test={null};test[0]=button(provider[1],()->{test[0].setEnabled(false);feedback.setText(I18n.t("Đang kiểm tra…"));request("POST","/api/admin/ai/test",json("provider",provider[0]),d->feedback.setText(d.optString("message")+" · "+d.optString("provider")),()->test[0].setEnabled(true));});form.addView(test[0]);}
      CheckBox support=new CheckBox(this);support.setText(I18n.t("AI tự trả lời từ tài khoản quản trị"));support.setTextColor(TEXT);support.setChecked(config.optInt("support")==1);page.addView(support);CheckBox moderation=new CheckBox(this);moderation.setText(I18n.t("AI kiểm duyệt và báo quản trị viên"));moderation.setTextColor(TEXT);moderation.setChecked(config.optInt("moderation")==1);page.addView(moderation);page.addView(label(I18n.t("AI cảnh báo để admin xử lý. Kiểm duyệt video/Live dùng khung hình lấy mẫu, không kiểm tra âm thanh."),13,MUTED));final View[] toggle={null};toggle[0]=primary(I18n.t("Lưu bật/tắt AI"),()->{toggle[0].setEnabled(false);request("PATCH","/api/admin/ai",json("support",support.isChecked(),"moderation",moderation.isChecked(),"adminId",me.optString("id")),d->{say(I18n.t("Đã lưu bật/tắt AI"));adminAI();},()->toggle[0].setEnabled(true));});page.addView(toggle[0]);page.addView(label(I18n.t("Hàng chờ: ")+config.optInt("queue")+I18n.t(" · Lỗi: ")+config.optInt("failed"),14,MUTED));
    },()->{if(!loaded[0]){state.setText(I18n.t("Chưa tải được cấu hình. Nếu báo không tìm thấy API, máy chủ Kinnect cần cập nhật và khởi động lại."));page.addView(button(I18n.t("Thử lại"),()->adminAI()));}});
  }

  private void admin() {
    shell(I18n.t("Quản trị Kinnect"), true);
    content.addView(primary(I18n.t("Trợ lý AI và kiểm duyệt"),()->adminAI()));
    content.addView(label(I18n.t("Báo cáo và tài khoản"), 16, TEXT));
    adminResets();
    adminMusic();
    request("GET", "/api/admin/reports", null, data -> {
      JSONArray reports = data.optJSONArray("reports");
      if (reports == null || reports.length() == 0) content.addView(
        label(I18n.t("Chưa có báo cáo."), 15, MUTED)
      );
      for (int i = 0; reports != null && i < reports.length(); i++) {
        JSONObject r = reports.optJSONObject(i),
          subject = r.optJSONObject("subject");
        LinearLayout c = card();
        c.addView(
          label(
            r.optString("target_type") + " · " + r.optString("status"),
            16,
            ACCENT
          )
        );
        c.addView(label(r.optString("reason"), 16, TEXT));
        if (subject != null) {
          c.addView(
            label(
              subject.optString("body", subject.optString("username")),
              14,
              MUTED
            )
          );
          if (r.optString("target_type").equals("short")) c.addView(
            button(
              subject.optBoolean("hidden") ? I18n.t("Hiện video") : I18n.t("Ẩn video"),
              () ->
                moderate(
                  subject.optBoolean("hidden") ? "show-short" : "hide-short",
                  r.optString("target_id")
                )
            )
          );
          if (r.optString("target_type").equals("post")) c.addView(
            button(subject.optBoolean("hidden") ? I18n.t("Hiện bài") : I18n.t("Ẩn bài"), () ->
              moderate(
                subject.optBoolean("hidden") ? "show-post" : "hide-post",
                r.optString("target_id")
              )
            )
          );
          if(r.optString("target_type").equals("message")||r.optString("target_type").equals("group_message"))c.addView(button(I18n.t("Gỡ nội dung tin nhắn"),()->moderate("hide-"+r.optString("target_type"),r.optString("target_id"))));
          c.addView(
            button(I18n.t("Đình chỉ tài khoản"), () ->
              moderate("suspend-user", subject.optString("userId"))
            )
          );
        }
        if (r.optString("status").equals("open")) c.addView(
          button(I18n.t("Đóng báo cáo"), () ->
            moderate("close-report", r.optString("id"))
          )
        );
      }
    });
    request("GET", "/api/admin/users", null, data -> {
      JSONArray users = data.optJSONArray("users");
      content.addView(label(I18n.t("Thành viên gần đây"), 16, TEXT));
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        LinearLayout c = card();
        c.addView(
          label(u.optString("username") + " · " + u.optString("role"), 16, TEXT)
        );
        if (!u.optString("role").equals("admin")) c.addView(
          button(u.optInt("suspended") == 1 ? I18n.t("Khôi phục") : I18n.t("Đình chỉ"), () ->
            moderate(
              u.optInt("suspended") == 1 ? "restore-user" : "suspend-user",
              u.optString("id")
            )
          )
        );
      }
    });
  }

  private void moderate(String action, String target) {
    confirm(I18n.t("Xác nhận thao tác quản trị?"), () ->
      request(
        "POST",
        "/api/admin/moderate",
        json("action", action, "target", target),
        d -> admin()
      )
    );
  }

  private void live() {
    content.addView(label(I18n.t("Trực tiếp cùng Kinnect"), 20, TEXT));
    content.addView(label(I18n.t("Camera, micro, video và trò chuyện được xử lý bằng WebRTC native trên Android."),15,MUTED));
    content.addView(primary(I18n.t("Mở phòng trực tiếp"), () -> startActivity(new Intent(this, LiveActivity.class))));
  }

  private void languageMenu() {
    new Sheet(this).setTitle(I18n.t("Ngôn ngữ ứng dụng"))
      .setItems(new String[]{"Tiếng Việt","English",I18n.t("Theo hệ thống")},(dialog,index)->{
        I18n.select(this,new String[]{"vi","en","system"}[index]);recreate();
      }).setNegativeButton(I18n.t("Đóng"),null).show();
  }

  private void settings() {
    if (me == null) { auth(false); return; }
    accountHeader(I18n.t("Cài đặt & riêng tư"), () -> meMenu());
    groupTitle("globe", I18n.t("Ngôn ngữ"));
    groupRow(settingsGroup(),"globe",I18n.current().equals("en")?"English":I18n.t("Tiếng Việt"),false,()->languageMenu());
    groupTitle("user_round", I18n.t("Thông tin cá nhân"));
    LinearLayout personal = settingsGroup();
    groupRow(personal, "pencil", me.optString("name") + I18n.t(" · chỉnh sửa hồ sơ"), false, () -> editProfile());
    groupTitle("shield_check", I18n.t("Quyền riêng tư"));
    LinearLayout privacy = settingsGroup();
    privacyToggle(privacy, "discoverable", I18n.t("Cho phép tìm thấy tôi"), I18n.t("Xuất hiện trong Khám phá và Bạn bè quanh đây"));
    privacyToggle(privacy, "showDistance", I18n.t("Hiển thị khoảng cách"), I18n.t("Chỉ hiện khoảng cách gần đúng"));
    privacyToggle(privacy, "showActivity", I18n.t("Trạng thái hoạt động"), I18n.t("Cho người khác biết khi bạn đang online"));
    groupRow(privacy, "message_square", I18n.t("Ai có thể nhắn tin · ") + (me.optString("dmMode").equals("everyone") ? I18n.t("Mọi thành viên") : I18n.t("Bạn bè")), false, () -> new Sheet(this).setTitle(I18n.t("Ai có thể nhắn tin")).setItems(new String[] { I18n.t("Mọi thành viên"), I18n.t("Bạn bè") }, (d, w) -> request("PATCH", "/api/me", json("dmMode", w == 0 ? "everyone" : "friends"), r -> { me = r.optJSONObject("user"); settings(); })).show());
    if(Distribution.PLAY){
      groupTitle("message_square",I18n.t("Đồng bộ giữa các thiết bị"));LinearLayout sync=settingsGroup();android.content.SharedPreferences preferences=getSharedPreferences("play_privacy",0);Switch toggle=new Switch(this);toggle.setText(I18n.t("Đồng bộ tin nhắn nền"));toggle.setTextSize(14);toggle.setTextColor(TEXT);toggle.setChecked(preferences.getBoolean("background_messages",false));sync.addView(toggle);sync.addView(label(I18n.t("Tùy chọn giữ thông báo đang hoạt động để tiếp tục đồng bộ tin nhắn giữa web và điện thoại. Có thể tắt bất cứ lúc nào; khi tắt, Android có thể ngừng kết nối nền."),12,MUTED));toggle.setOnCheckedChangeListener((button,enabled)->{preferences.edit().putBoolean("background_messages",enabled).apply();KinnectService.stop(this);KinnectService.start(this);});
    }
    groupTitle("lock_keyhole", I18n.t("Quyền truy cập"));
    LinearLayout access = settingsGroup();
    groupRow(access, "image_lock", I18n.t("Ảnh riêng tư"), false, () -> privateAlbum(me));
    groupRow(access, "user_block", I18n.t("Tài khoản đã chặn"), false, () -> blocks());
    groupRow(access, "location_off", I18n.t("Tắt tìm quanh đây"), false, () -> request("PATCH", "/api/me/location", json("enabled", false), result -> { me = result.optJSONObject("user"); say(I18n.t("Đã tắt tìm quanh đây")); settings(); }));
    TextView note = label(I18n.t("Vị trí chỉ cập nhật khi bạn chọn tìm quanh đây."), 12, MUTED);
    note.setPadding(dp(6), 0, dp(6), 0);
    content.addView(note);
    groupTitle("user_round", I18n.t("Quản lý tài khoản"));LinearLayout account=settingsGroup();groupRow(account,"trash",I18n.t("Xóa tài khoản và dữ liệu"),false,()->deleteAccountScreen());
  }

  private void deleteAccountScreen(){
    accountHeader(I18n.t("Xóa tài khoản"),()->settings());LinearLayout panel=card();panel.addView(label(I18n.t("Xóa vĩnh viễn"),20,TEXT));panel.addView(label(I18n.t("Hồ sơ, ảnh, bài viết, video, tin nhắn và dữ liệu gắn với tài khoản sẽ bị xóa khỏi hệ thống đang hoạt động. Tất cả phiên đăng nhập bị thu hồi. Nội dung của bạn trong nhóm cũng bị xóa; nhóm có thành viên khác được chuyển chủ sở hữu. Không thể khôi phục sau khi hoàn tất."),14,MUTED));
    panel.addView(label(I18n.t("Nhập lại tên đăng nhập: @")+me.optString("username"),13,TEXT));EditText username=new EditText(this);username.setSingleLine(true);username.setTextSize(16);panel.addView(username,new LinearLayout.LayoutParams(-1,dp(52)));
    panel.addView(label(I18n.t("Mật khẩu (nếu phiên đăng nhập đã cũ)"),13,TEXT));EditText password=new EditText(this);password.setSingleLine(true);password.setTextSize(16);password.setInputType(129);panel.addView(password,new LinearLayout.LayoutParams(-1,dp(52)));
    Button remove=primary(I18n.t("Xóa vĩnh viễn tài khoản và dữ liệu"),()->{if(!username.getText().toString().equals(me.optString("username"))){say(I18n.t("Nhập đúng tên đăng nhập để xác nhận."));return;}confirm(I18n.t("Bạn chắc chắn xóa vĩnh viễn? Không thể khôi phục dữ liệu."),()->request("DELETE","/api/me/account-deletion",json("confirmUsername",username.getText().toString(),"password",password.getText().toString(),"confirmDelete",true),result->{KinnectService.stop(this);if(calls!=null){calls=null;}api.clear();me=null;auth(false);say(I18n.t("Đã xóa tài khoản và dữ liệu."));}));});panel.addView(remove);
    panel.addView(label(I18n.t("Hỗ trợ riêng tư: anhvn53@wru.vn · Không gửi mật khẩu hoặc OTP."),12,MUTED));
  }

  private void groupTitle(String iconName, String title) {
    LinearLayout r = row();
    r.setPadding(dp(4), dp(10), 0, dp(8));
    r.addView(icon(iconName, 17, ACCENT), new LinearLayout.LayoutParams(dp(17), dp(17)));
    TextView t = label(title, 15, TEXT);
    t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    t.setPadding(dp(8), 0, 0, 0);
    r.addView(t);
    content.addView(r);
  }

  private void privacyToggle(LinearLayout parent, String key, String title, String subtitle) {
    if (parent.getChildCount() > 0) {
      View line = new View(this);
      line.setBackgroundColor(LINE);
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, 1);
      lp.setMargins(dp(60), 0, dp(12), 0);
      parent.addView(line, lp);
    }
    LinearLayout row = row();
    row.setPadding(dp(10), dp(10), dp(8), dp(10));
    row.setMinimumHeight(dp(76));
    String glyph=key.equals("discoverable")?"user_search":key.equals("showDistance")?"distance_pins":"activity_status";
    row.addView(settingsIcon(glyph,ACCENT),new LinearLayout.LayoutParams(dp(38),dp(38)));
    LinearLayout text = column();
    text.setPadding(dp(12),0,dp(8),0);
    TextView t = label(title, 15, TEXT);
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    text.addView(t);
    text.addView(label(subtitle, 12, MUTED));
    row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    final Switch check = new Switch(this);
    android.content.res.ColorStateList thumb = new android.content.res.ColorStateList(new int[][] { { android.R.attr.state_checked }, {} }, new int[] { ACCENT, 0xffffffff });
    android.content.res.ColorStateList track = new android.content.res.ColorStateList(new int[][] { { android.R.attr.state_checked }, {} }, new int[] { (ACCENT & 0x00ffffff) | 0x66000000, LINE });
    check.setThumbTintList(thumb);
    check.setTrackTintList(track);
    check.setContentDescription(title);
    check.setChecked(me.optBoolean(key, true));
    final boolean[] pending = { false };
    final int generation = screen;
    check.setOnCheckedChangeListener((view, selected) -> {
      if (pending[0]) return;
      final boolean previous = me.optBoolean(key, true);
      pending[0] = true; check.setEnabled(false);
      api.call("PATCH", "/api/me", json(key, selected), (result, error, status) -> {
        if (generation != screen || isDestroyed()) return;
        if (error != null || result == null || result.optJSONObject("user") == null) { pending[0] = true; check.setChecked(previous); say(error == null ? I18n.t("Chưa lưu được cài đặt.") : error); }
        else me = result.optJSONObject("user");
        pending[0] = false; check.setEnabled(true);
      });
    });
    check.setMinimumWidth(dp(48));check.setMinimumHeight(dp(48));
    row.addView(check,new LinearLayout.LayoutParams(-2,-2));
    row.setOnClickListener(v -> {if(check.isEnabled())check.toggle();});
    parent.addView(row, new LinearLayout.LayoutParams(-1, -2));
  }


  private void friendsScreen(final String selected) {
    remember("friends", () -> friendsScreen(selected));
    headerActive = "friends";
    shell(I18n.t("Bạn bè"), true);
    final String[] keys = { "friends", "incoming", "outgoing" };
    final String[] names = { "Bạn bè", "Lời mời", "Đã gửi" };
    int index = Arrays.asList(keys).indexOf(selected);
    LinearLayout tabs = row();
    segmented(tabs, names, Math.max(0, index), i -> friendsScreen(keys[i]));
    content.addView(tabs, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout gap = new LinearLayout(this);
    content.addView(gap, new LinearLayout.LayoutParams(-1, dp(10)));
    final EditText search = searchField(content, I18n.t("Tên hoặc @username"));
    final LinearLayout list = column();
    content.addView(list, new LinearLayout.LayoutParams(-1, -2));
    final JSONArray[] loaded = { null }, suggested = { null };
    final Runnable render = () -> {
      list.removeAllViews();
      JSONArray users = loaded[0];
      String q = search.getText().toString().trim().toLowerCase(Locale.ROOT).replaceFirst("^@", "");
      List<JSONObject> rows = new ArrayList<>();
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        if (q.isEmpty() || (u.optString("name") + " " + u.optString("username")).toLowerCase(Locale.ROOT).contains(q)) rows.add(u);
      }
      if (rows.isEmpty()) {
        list.addView(emptyBlock("users_round", q.isEmpty() ? I18n.t("Chưa có ") + names[Math.max(0, Arrays.asList(keys).indexOf(selected))].toLowerCase(Locale.ROOT) : I18n.t("Không tìm thấy bạn bè"), q.isEmpty() ? I18n.t("Lời mời và kết nối mới sẽ hiển thị tại đây.") : I18n.t("Bạn có thể tìm thêm thành viên trong Khám phá.")));
      } else if (selected.equals("friends")) {
        List<JSONObject> online = new ArrayList<>(), offline = new ArrayList<>();
        for (JSONObject u : rows) (u.optBoolean("isActive") && u.optBoolean("activityShared", true) ? online : offline).add(u);
        friendSection(list, I18n.t("Đang trực tuyến"), online, selected);
        friendSection(list, I18n.t("Ngoại tuyến"), offline, selected);
      } else friendSection(list, names[Arrays.asList(keys).indexOf(selected)], rows, selected);
      if (selected.equals("friends")) {
        List<JSONObject> suggestions = new ArrayList<>();
        for (int i = 0; suggested[0] != null && i < suggested[0].length() && suggestions.size() < 6; i++) {
          JSONObject u = suggested[0].optJSONObject(i);
          if (q.isEmpty() || (u.optString("name") + " " + u.optString("username")).toLowerCase(Locale.ROOT).contains(q)) suggestions.add(u);
        }
        if (!suggestions.isEmpty()) friendSection(list, I18n.t("Gợi ý kết bạn"), suggestions, "suggestion");
      }
    };
    search.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
      public void onTextChanged(CharSequence s, int a, int b, int c) {}
      public void afterTextChanged(android.text.Editable s) { render.run(); }
    });
    request("GET", selected.equals("friends") ? "/api/friends" : "/api/friend-requests", null, data -> {
      loaded[0] = data.optJSONArray(selected.equals("friends") ? "users" : selected);
      render.run();
    });
    if (selected.equals("friends")) request("GET", "/api/friend-suggestions", null, data -> {
      suggested[0] = data.optJSONArray("users");
      if (loaded[0] != null) render.run();
    });
  }

  private void friendSection(LinearLayout list, String title, List<JSONObject> users, final String kind) {
    if (users.isEmpty()) return;
    LinearLayout head = row();
    head.setPadding(dp(4), dp(18), 0, dp(8));
    TextView h = label(title, 16, TEXT);
    h.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    head.addView(h);
    TextView n = label(" " + users.size(), 13, MUTED);
    head.addView(n);
    list.addView(head);
    LinearLayout group = column();
    group.setPadding(dp(4), dp(4), dp(4), dp(4));
    group.setBackground(outlined(CARD, 16));
    for (final JSONObject u : users) {
      if (group.getChildCount() > 0) {
        View line = new View(this);
        line.setBackgroundColor(LINE);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, 1);
        lp.setMargins(dp(64), 0, dp(10), 0);
        group.addView(line, lp);
      }
      LinearLayout r = row();
      r.setPadding(dp(10), dp(10), dp(8), dp(10));
      r.setBackground(pressable(CARD, 12));
      avatar(u, r, 44);
      LinearLayout who = column();
      who.setPadding(dp(12), 0, dp(8), 0);
      TextView name = label(u.optString("name"), 15, TEXT);
      name.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
      name.setSingleLine(true);
      name.setEllipsize(android.text.TextUtils.TruncateAt.END);
      who.addView(name);
      boolean active = u.optBoolean("isActive") && u.optBoolean("activityShared", true);
      TextView sub = label("@" + u.optString("username") + " · " + (active ? I18n.t("Đang hoạt động") : I18n.t("Ngoại tuyến")), 12, active ? 0xff2e9e66 : MUTED);
      sub.setSingleLine(true);
      sub.setEllipsize(android.text.TextUtils.TruncateAt.END);
      who.addView(sub);
      r.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
      String id = u.optString("id");
      if (kind.equals("friends")) r.addView(roundAction("message_square", I18n.t("Nhắn tin"), true, () -> chat(u)));
      else if (kind.equals("incoming")) {
        r.addView(roundAction("check", I18n.t("Chấp nhận"), true, () -> request("POST", "/api/users/" + id + "/friend-request/respond", json("action", "accept"), d -> { say(I18n.t("Đã chấp nhận kết bạn")); friendsScreen("incoming"); })));
        r.addView(roundAction("x", I18n.t("Từ chối"), false, () -> request("POST", "/api/users/" + id + "/friend-request/respond", json("action", "decline"), d -> friendsScreen("incoming"))));
      } else if (kind.equals("outgoing")) r.addView(roundAction("user_check", I18n.t("Huỷ lời mời"), false, () -> request("DELETE", "/api/users/" + id + "/friend-request", json(), d -> friendsScreen("outgoing"))));
      else r.addView(roundAction("user_plus", I18n.t("Kết bạn"), true, () -> request("POST", "/api/users/" + id + "/friend-request", json(), d -> { say(I18n.t("Đã gửi lời mời kết bạn")); friendsScreen("friends"); })));
      r.setOnClickListener(v -> person(u));
      group.addView(r, new LinearLayout.LayoutParams(-1, -2));
    }
    list.addView(group, new LinearLayout.LayoutParams(-1, -2));
  }

  private View emptyBlock(String iconName, String title, String text) {
    LinearLayout empty = column();
    empty.setGravity(Gravity.CENTER_HORIZONTAL);
    empty.setPadding(dp(20), dp(32), dp(20), dp(28));
    empty.setBackground(outlined(CARD, 16));
    FrameLayout bubble = new FrameLayout(this);
    bubble.setBackground(background(PRIMARY_SOFT, 99));
    bubble.addView(icon(iconName, 24, ACCENT), new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
    empty.addView(bubble, new LinearLayout.LayoutParams(dp(56), dp(56)));
    TextView t = label(title, 15, TEXT);
    t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    t.setGravity(Gravity.CENTER);
    t.setPadding(0, dp(14), 0, dp(2));
    empty.addView(t);
    TextView s = label(text, 13, MUTED);
    s.setGravity(Gravity.CENTER);
    empty.addView(s);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.topMargin = dp(14);
    empty.setLayoutParams(p);
    return empty;
  }

  private void stopShort() {
    if (shortVideo != null) {
      shortVideo.stopPlayback();
      shortVideo = null;
      shortPlayer = null;
    }
  }

  private String shortsTab = "for";

  // Trang Video: nền đen toàn màn, thanh tab trong suốt nổi phía trên (Trực tiếp · Đề xuất · Đang theo dõi).
  private FrameLayout reelStage() {
    ScrollView scroll = (ScrollView) content.getParent();
    int at = root.indexOfChild(scroll);
    root.removeView(scroll);
    FrameLayout stage = new FrameLayout(this);
    stage.setBackgroundColor(0xff000000);
    root.addView(stage, at, new LinearLayout.LayoutParams(-1, 0, 1));
    return stage;
  }

  private void downloadShort(JSONObject video) {
    pendingDownload = video.optString("video");
    Intent save = new Intent(Intent.ACTION_CREATE_DOCUMENT);
    save.addCategory(Intent.CATEGORY_OPENABLE); save.setType("video/mp4");
    save.putExtra(Intent.EXTRA_TITLE, "Kinnect-" + video.optString("id") + ".mp4");
    try { startActivityForResult(save, 309); } catch (Exception error) { pendingDownload = ""; say(I18n.t("Chưa mở được trình lưu video.")); }
  }

  private int findShort(String id) {
    for (int i = 0; shortRows != null && i < shortRows.length(); i++) if (shortRows.optJSONObject(i).optString("id").equals(id)) return i;
    return shortIndex;
  }

  private JSONArray orderedShorts(JSONArray source) {
    if (source == null || shortsFollowing) return source;
    List<JSONObject> rows = new ArrayList<>();
    for (int i = 0; i < source.length(); i++) if (source.optJSONObject(i) != null) rows.add(source.optJSONObject(i));
    Collections.sort(rows, (a, b) -> VideoFeedPolicy.compare(a.optLong("likes"), a.optLong("comments"), a.optLong("created"), a.optString("id"), b.optLong("likes"), b.optLong("comments"), b.optLong("created"), b.optString("id")));
    return new JSONArray(rows);
  }

  private void shorts() {
    shortsFollowing = shortsTab.equals("following");
    final FrameLayout stage = reelStage();
    final TextView loading = label(I18n.t("Đang tải video…"), 14, 0x99ffffff);
    stage.addView(loading, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    stage.addView(reelTabs(), new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    request("GET", shortsFollowing ? "/api/shorts?feed=following" : "/api/shorts", null, data -> {
      shortRows = orderedShorts(data.optJSONArray("shorts"));
      if (shortRows == null || shortRows.length() == 0) {
        stage.removeView(loading);
        LinearLayout empty = column();
        empty.setGravity(Gravity.CENTER_HORIZONTAL);
        FrameLayout bubble = new FrameLayout(this);
        bubble.setBackground(background(0x26ffffff, 99));
        bubble.addView(icon("clapperboard", 30, WHITE), new FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER));
        empty.addView(bubble, new LinearLayout.LayoutParams(dp(72), dp(72)));
        TextView t = label(shortsFollowing ? I18n.t("Chưa có video từ người bạn theo dõi") : I18n.t("Chưa có video"), 16, WHITE);
        t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        t.setGravity(Gravity.CENTER);
        t.setPadding(0, dp(16), 0, dp(16));
        empty.addView(t);
        LinearLayout b = authButton("video", "Quay video", true);
        b.setPadding(dp(20), 0, dp(20), 0);
        b.setOnClickListener(v -> chooseVideo());
        empty.addView(b, new LinearLayout.LayoutParams(-2, dp(46)));
        stage.addView(empty, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
        return;
      }
      showShort(0);
    });
  }

  // Tab "Trực tiếp": lưới các buổi đang live, chạm để vào xem ngay.
  private FrameLayout liveCard(final JSONObject room) {
    FrameLayout c = new FrameLayout(this);
    float hue = Math.abs(room.optString("hostId").hashCode()) % 360;
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { Color.HSVToColor(new float[] { hue, 0.65f, 0.6f }), Color.HSVToColor(new float[] { (hue + 50) % 360, 0.75f, 0.3f }) });
    g.setCornerRadius(dp(16));
    c.setBackground(g);
    c.setClipToOutline(true);
    LinearLayout center = column();
    center.setGravity(Gravity.CENTER_HORIZONTAL);
    FrameLayout ring = new FrameLayout(this);
    GradientDrawable rg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xffff3b5c, PINK });
    rg.setShape(GradientDrawable.OVAL);
    ring.setBackground(rg);
    ring.setPadding(dp(3), dp(3), dp(3), dp(3));
    LinearLayout holder = new LinearLayout(this);
    JSONObject host = json("id", room.optString("hostId"), "name", room.optString("host"), "avatar", room.isNull("avatar") ? "" : room.optString("avatar"));
    avatar(host, holder, 74);
    ring.addView(holder);
    center.addView(ring);
    FrameLayout.LayoutParams cp = new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER);
    cp.bottomMargin = dp(30);
    c.addView(center, cp);
    LinearLayout badges = row();
    TextView live = label("LIVE", 11, WHITE);
    live.setTypeface(null, Typeface.BOLD);
    live.setPadding(dp(7), dp(2), dp(7), dp(2));
    live.setBackground(background(0xffff3b5c, 6));
    badges.addView(live);
    TextView viewers = label("  👁 " + room.optInt("viewers") + "  ", 11, WHITE);
    viewers.setBackground(background(0x66000000, 6));
    LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(-2, -2);
    vp.leftMargin = dp(6);
    badges.addView(viewers, vp);
    FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.START);
    bp.setMargins(dp(8), dp(8), 0, 0);
    c.addView(badges, bp);
    LinearLayout info = column();
    info.setPadding(dp(10), dp(24), dp(10), dp(10));
    info.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x00000000, 0xbb000000 }));
    TextView title = label(room.optString("title"), 14, WHITE);
    title.setTypeface(null, Typeface.BOLD);
    title.setMaxLines(2);
    title.setEllipsize(android.text.TextUtils.TruncateAt.END);
    info.addView(title);
    info.addView(label(room.optString("host"), 12, 0xccffffff));
    c.addView(info, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
    c.setOnClickListener(v -> {
      Intent i = new Intent(this, LiveActivity.class);
      i.putExtra(LiveActivity.EXTRA_ROOM, room.optString("id"));
      startActivity(i);
    });
    return c;
  }

  private int shortEnter = 0;

  private void showShort(int index) {
    if (shortRows == null || shortRows.length() == 0) return;
    shortIndex = VideoFeedPolicy.index(index, shortRows.length(), !shortsFollowing);
    shell(I18n.t("Video ngắn"), true);
    final JSONObject item = shortRows.optJSONObject(shortIndex), author = item.optJSONObject("author");
    // Video dọc toàn màn hình như web: nền đen, nút bên phải, tên + chú thích ở dưới.
    ScrollView scroll = (ScrollView) content.getParent();
    int at = root.indexOfChild(scroll);
    root.removeView(scroll);
    FrameLayout stage = new FrameLayout(this);
    stage.setBackgroundColor(0xff000000);
    root.addView(stage, at, new LinearLayout.LayoutParams(-1, 0, 1));
    shortVideo = new VideoView(this);
    final VideoView playerView = shortVideo;
    stage.addView(shortVideo, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
    Map<String, String> headers = new HashMap<>();
    headers.put("Cookie", api.jar());
    shortVideo.setVideoURI(android.net.Uri.parse(server() + item.optString("video")), headers);
    shortVideo.setOnPreparedListener(player -> {
      if (stopped || shortVideo != playerView) return;
      shortPlayer = player;
      player.setLooping(true);
      player.setVolume(shortMuted ? 0 : 1, shortMuted ? 0 : 1);
      if(!mediaCallBlocked)shortVideo.start();
    });
    shortVideo.setOnErrorListener((player, what, extra) -> { say(I18n.t("Không phát được video.")); return true; });
    if (shortEnter != 0) {
      final int from = shortEnter;
      shortEnter = 0;
      stage.post(() -> { stage.setTranslationY(from * stage.getHeight()); stage.animate().translationY(0).setDuration(260).setInterpolator(new android.view.animation.DecelerateInterpolator()).start(); });
    }
    final float[] y = { 0 };
    final boolean[] dragging = { false };
    stage.setOnTouchListener((view, event) -> {
      float dy = event.getRawY() - y[0];
      switch (event.getActionMasked()) {
        case MotionEvent.ACTION_DOWN: y[0] = event.getRawY(); dragging[0] = false; stage.animate().cancel(); break;
        case MotionEvent.ACTION_MOVE:
          if (Math.abs(dy) > dp(8)) dragging[0] = true;
          if (dragging[0]) stage.setTranslationY(dy);
          break;
        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_CANCEL:
          if (dragging[0] && Math.abs(dy) > dp(90)) {
            final int dir = dy < 0 ? 1 : -1;
            stage.animate().translationY(-dir * stage.getHeight()).setDuration(200).setInterpolator(new android.view.animation.AccelerateInterpolator()).withEndAction(() -> { shortEnter = dir; showShort(shortIndex + dir); }).start();
          } else if (dragging[0]) {
            stage.animate().translationY(0).setDuration(180).start();
          } else if (event.getActionMasked() == MotionEvent.ACTION_UP && shortVideo != null) {
            if (shortVideo.isPlaying()) shortVideo.pause(); else if(!mediaCallBlocked)shortVideo.start();
          }
          break;
      }
      return true;
    });
    // Cột nút bên phải
    LinearLayout side = column();
    side.setGravity(Gravity.CENTER_HORIZONTAL);

    FrameLayout authorTile=new FrameLayout(this);LinearLayout faceHolder=column();ImageView face=avatar(author,faceHolder,46);FrameLayout.LayoutParams faceSpace=new FrameLayout.LayoutParams(dp(46),dp(46),Gravity.TOP|Gravity.CENTER_HORIZONTAL);authorTile.addView(faceHolder,faceSpace);face.setOnClickListener(v->person(author));boolean own=author.optString("id").equals(me.optString("id"));
    if(!own){FrameLayout follow=new FrameLayout(this);FrameLayout mark=new FrameLayout(this);ImageView symbol=icon(author.optBoolean("following")?"check":"plus",15,WHITE);mark.setBackground(background(author.optBoolean("following")?ACCENT:PINK,99));mark.addView(symbol,new FrameLayout.LayoutParams(dp(15),dp(15),Gravity.CENTER));follow.addView(mark,new FrameLayout.LayoutParams(dp(25),dp(25),Gravity.CENTER));follow.setContentDescription(author.optBoolean("following")?I18n.t("Bỏ theo dõi tác giả"):I18n.t("Theo dõi tác giả"));follow.setOnClickListener(v->{follow.setEnabled(false);request(author.optBoolean("following")?"DELETE":"POST","/api/users/"+author.optString("id")+"/follow",json(),result->{JSONObject updated=result.optJSONObject("user");boolean followed=updated!=null?updated.optBoolean("following"):!author.optBoolean("following");try{author.put("following",followed);for(int i=0;shortRows!=null&&i<shortRows.length();i++){JSONObject who=shortRows.optJSONObject(i).optJSONObject("author");if(who!=null&&who.optString("id").equals(author.optString("id")))who.put("following",followed);}}catch(JSONException ignored){}symbol.setImageDrawable(WebIcons.load(this,followed?"check":"plus"));symbol.setImageTintList(android.content.res.ColorStateList.valueOf(WHITE));mark.setBackground(background(followed?ACCENT:PINK,99));follow.setContentDescription(followed?I18n.t("Bỏ theo dõi tác giả"):I18n.t("Theo dõi tác giả"));say(followed?I18n.t("Đã theo dõi"):I18n.t("Đã bỏ theo dõi"));},()->follow.setEnabled(true));});authorTile.addView(follow,new FrameLayout.LayoutParams(dp(44),dp(44),Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL));}
    side.addView(authorTile,new LinearLayout.LayoutParams(dp(54),dp(own?54:74)));
    final LinearLayout love=reelButton("heart",String.valueOf(item.optInt("likes")),item.optBoolean("liked")?PINK:WHITE,()->{});love.setContentDescription(item.optBoolean("liked")?I18n.t("Bỏ thích video"):I18n.t("Thích video"));love.setOnClickListener(v->{final boolean previous=item.optBoolean("liked");love.setEnabled(false);request(previous?"DELETE":"POST","/api/shorts/"+item.optString("id")+"/like",json(),result->{boolean liked=result.has("liked")?result.optBoolean("liked"):!previous;int count=result.has("likes")?result.optInt("likes"):Math.max(0,item.optInt("likes")+(liked==previous?0:liked?1:-1));try{item.put("liked",liked);item.put("likes",count);}catch(JSONException ignored){}((ImageView)love.getChildAt(0)).setImageTintList(android.content.res.ColorStateList.valueOf(liked?PINK:WHITE));((TextView)love.getChildAt(1)).setText(String.valueOf(count));love.setContentDescription(liked?I18n.t("Bỏ thích video"):I18n.t("Thích video"));},()->love.setEnabled(true));});side.addView(love);
    side.addView(reelButton("comment", item.has("comments") ? String.valueOf(item.optInt("comments")) : "0", WHITE, () -> shortComments(item)));
    side.addView(reelButton("share", I18n.t("Chia sẻ"), WHITE, () -> {
      Intent send = new Intent(Intent.ACTION_SEND);
      send.setType("text/plain");
      send.putExtra(Intent.EXTRA_TEXT, "Xem video của @" + author.optString("username") + " trên Kinnect: https://app.kinnect.io.vn/?video=" + item.optString("id"));
      try { startActivity(Intent.createChooser(send, I18n.t("Chia sẻ video"))); } catch (Exception ignored) {}
    }));
    side.addView(reelButton("download", I18n.t("Tải video"), WHITE, () -> downloadShort(item)));
    side.addView(reelButton(shortMuted ? "mute" : "sound", I18n.t("Âm thanh"), WHITE, () -> {
      shortMuted = !shortMuted;
      if (shortPlayer != null) shortPlayer.setVolume(shortMuted ? 0 : 1, shortMuted ? 0 : 1);
      showShort(shortIndex);
    }));
    final boolean mine = item.optString("user_id").equals(me.optString("id"));
    side.addView(reelButton("more", mine ? I18n.t("Thêm") : I18n.t("Báo cáo"), WHITE, () -> new Sheet(this).setItems(new String[] { mine ? I18n.t("Xoá video của tôi") : I18n.t("Báo cáo video"), I18n.t("Xem hồ sơ"), I18n.t("Đóng") }, (d, w) -> {
      if (w == 0) { if (mine) confirm(I18n.t("Xoá video?"), () -> request("DELETE", "/api/shorts/" + item.optString("id"), json(), r -> navigate("shorts"))); else report("short", item.optString("id")); }
      if (w == 1) person(author);
    }).show()));
    ScrollView actionRail = new ScrollView(this);
    actionRail.setVerticalScrollBarEnabled(false);
    actionRail.setFillViewport(true);
    side.setGravity(Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    actionRail.addView(side);
    FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(dp(64), -1, Gravity.END);
    sp.topMargin = dp(64); sp.bottomMargin = dp(65);
    stage.addView(actionRail, sp);
    stage.addView(reelTabs(), new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    // Tên + chú thích
    LinearLayout meta = column();
    TextView name = label("@" + author.optString("username"), 13, WHITE);
    name.setTypeface(null, Typeface.BOLD);
    name.setShadowLayer(4, 0, 1, 0xaa000000);
    meta.addView(name);
    if (!item.optString("caption").isEmpty()) {
      TextView cap = label(item.optString("caption"), 13, WHITE);
      cap.setShadowLayer(4, 0, 1, 0xaa000000);
      meta.addView(cap);
    }

    FrameLayout.LayoutParams mp = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
    mp.setMargins(dp(14), 0, dp(84), dp(18));
    stage.addView(meta, mp);
  }

  private TextView reelTab(String text, boolean active, Runnable click) {
    TextView t = label(text, 16, active ? WHITE : 0x99ffffff);
    t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
    t.setPadding(dp(12), dp(6), dp(12), dp(6));
    t.setShadowLayer(4, 0, 1, 0xaa000000);
    t.setOnClickListener(v -> click.run());
    return t;
  }

  private LinearLayout reelButton(String iconName, String caption, int color, Runnable click) {
    LinearLayout box = column();
    box.setGravity(Gravity.CENTER_HORIZONTAL);
    box.setPadding(0, dp(3), 0, 0);
    box.setMinimumHeight(dp(44));
    ImageView i = icon(iconName, 24, color);
    i.setElevation(dp(2));
    box.addView(i, new LinearLayout.LayoutParams(dp(24), dp(24)));
    TextView text = label(caption, 11, WHITE);
    text.setTypeface(null, Typeface.BOLD);
    text.setShadowLayer(4, 0, 1, 0xaa000000);
    text.setGravity(Gravity.CENTER);
    text.setPadding(0, dp(2), 0, 0);
    box.addView(text);
    box.setContentDescription(caption);
    box.setOnClickListener(v -> click.run());
    return box;
  }

  // Thanh tab trắng phía trên video như web: Trực tiếp · Đề xuất · Đang theo dõi
  // Thanh tab trong suốt nổi trên video: chữ trắng có bóng, gạch chân trắng ở tab đang chọn.
  private LinearLayout reelTabs() {
    LinearLayout bar = row();
    bar.setGravity(Gravity.CENTER);
    bar.setPadding(0, dp(6), 0, dp(14));
    bar.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x66000000, 0x00000000 }));
    String[][] items = { { "for", "Đề xuất" }, { "following", "Đang theo dõi" } };
    for (final String[] it : items) {
      boolean active = it[0].equals(shortsTab);
      LinearLayout cell = column();
      cell.setGravity(Gravity.CENTER_HORIZONTAL);
      cell.setPadding(dp(12), 0, dp(12), 0);
      TextView t = label((it[0].equals("live") ? "● " : "") + it[1], 14, active ? WHITE : 0xb3ffffff);
      t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
      t.setGravity(Gravity.CENTER);
      t.setShadowLayer(dp(3), 0, dp(1), 0xaa000000);
      t.setPadding(0, 0, 0, 0);
      t.setSingleLine(true);
      cell.addView(t, new LinearLayout.LayoutParams(-1, -2));
      View line = new View(this);
      line.setBackground(background(active ? WHITE : 0x00000000, 99));
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(24), dp(3));
      lp.topMargin = dp(5);
      cell.addView(line, lp);
      cell.setOnClickListener(v -> { shortsTab = it[0]; navigate("shorts"); });
      bar.addView(cell, new LinearLayout.LayoutParams(0, dp(44), 1));
    }
    return bar;
  }

  // Bình luận video kiểu TikTok: bảng trượt từ dưới, "N bình luận", tim bên phải, trả lời thu gọn, hàng emoji nhanh.
  private void shortComments(final JSONObject item) {
    final android.app.Dialog dialog = new android.app.Dialog(this);
    dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
    final String base = "/api/shorts/" + item.optString("id") + "/comments";
    LinearLayout sheet = column();
    GradientDrawable shape = new GradientDrawable();
    shape.setColor(CARD);
    float r = dp(18);
    shape.setCornerRadii(new float[] { r, r, r, r, 0, 0, 0, 0 });
    sheet.setBackground(shape);
    LinearLayout head = row();
    head.setPadding(dp(12), dp(10), dp(6), dp(4));
    head.addView(new View(this), new LinearLayout.LayoutParams(dp(40), 1));
    final TextView title = label(I18n.t("Bình luận"), 15, TEXT);
    title.setTypeface(null, Typeface.BOLD);
    title.setGravity(Gravity.CENTER);
    head.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    ImageView close = icon("close", 22, TEXT);
    close.setPadding(dp(9), dp(9), dp(9), dp(9));
    close.setContentDescription(I18n.t("Đóng bình luận"));
    close.setOnClickListener(v -> dialog.dismiss());
    head.addView(close, new LinearLayout.LayoutParams(dp(40), dp(40)));
    sheet.addView(head);
    final ScrollView scroll = new ScrollView(this);
    final LinearLayout list = column();
    list.setPadding(dp(16), dp(4), dp(16), dp(8));
    scroll.addView(list);
    sheet.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    sheet.addView(divider());
    final EditText input = new EditText(this);
    LinearLayout emojis = row();
    emojis.setPadding(dp(8), dp(6), dp(8), 0);
    for (final String e : new String[] { "😍", "😂", "🔥", "👏", "🥰", "😮", "😢", "💜" }) {
      TextView t = label(e, 22, TEXT);
      t.setGravity(Gravity.CENTER);
      t.setOnClickListener(v -> { input.append(e); input.requestFocus(); });
      emojis.addView(t, new LinearLayout.LayoutParams(0, dp(40), 1));
    }
    sheet.addView(emojis);
    final TextView replying = label("", 12, MUTED);
    replying.setPadding(dp(16), 0, dp(16), 0);
    replying.setVisibility(View.GONE);
    sheet.addView(replying);
    LinearLayout bar = row();
    bar.setPadding(dp(12), dp(6), dp(12), dp(12));
    avatar(me, bar, 34);
    input.setHint(I18n.t("Thêm bình luận..."));
    input.setContentDescription(I18n.t("Viết bình luận video"));
    input.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(500) });
    input.setTextColor(TEXT);
    input.setHintTextColor(MUTED);
    input.setTextSize(15);
    input.setSingleLine(true);
    input.setPadding(dp(16), 0, dp(16), 0);
    input.setBackground(background(SOFT, 999));
    LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(0, dp(42), 1);
    ip.setMargins(dp(10), 0, dp(8), 0);
    bar.addView(input, ip);
    FrameLayout send = new FrameLayout(this);
    send.setBackground(background(ACCENT, 999));
    send.addView(icon("send", 18, WHITE), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    send.setContentDescription(I18n.t("Gửi bình luận"));
    bar.addView(send, new LinearLayout.LayoutParams(dp(42), dp(42)));
    sheet.addView(bar);
    final String[] parent = { null };
    final Runnable[] load = new Runnable[1];
    load[0] = () -> request("GET", base, null, d -> {
      JSONArray all = d.optJSONArray("comments");
      int n = all == null ? 0 : all.length();
      title.setText(n + I18n.t(" bình luận"));
      list.removeAllViews();
      if (n == 0) {
        TextView empty = label(I18n.t("Chưa có bình luận nào\nHãy là người đầu tiên bình luận!"), 14, MUTED);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(0, dp(40), 0, dp(40));
        list.addView(empty);
        return;
      }
      for (int i = 0; i < n; i++) {
        final JSONObject c = all.optJSONObject(i);
        if (!c.isNull("parentId") && !c.optString("parentId").isEmpty()) continue;
        list.addView(reelComment(c, false, base, load[0], () -> {
          parent[0] = c.optString("id");
          replying.setText(I18n.t("Đang trả lời ") + c.optJSONObject("author").optString("name") + I18n.t(" · chạm để huỷ"));
          replying.setVisibility(View.VISIBLE);
          input.requestFocus();
        }));
        final List<JSONObject> kids = new ArrayList<>();
        for (int k = 0; k < n; k++) if (all.optJSONObject(k).optString("parentId").equals(c.optString("id"))) kids.add(all.optJSONObject(k));
        if (kids.isEmpty()) continue;
        final LinearLayout box = column();
        box.setPadding(dp(44), 0, 0, 0);
        box.setVisibility(View.GONE);
        for (final JSONObject k : kids) box.addView(reelComment(k, true, base, load[0], () -> {
          parent[0] = c.optString("id");
          replying.setText(I18n.t("Đang trả lời ") + k.optJSONObject("author").optString("name") + I18n.t(" · chạm để huỷ"));
          replying.setVisibility(View.VISIBLE);
          input.requestFocus();
        }));
        final TextView more = label("——  Xem " + kids.size() + I18n.t(" câu trả lời"), 12, MUTED);
        more.setTypeface(null, Typeface.BOLD);
        more.setPadding(dp(44), dp(2), 0, dp(8));
        more.setOnClickListener(v -> {
          boolean open = box.getVisibility() == View.VISIBLE;
          box.setVisibility(open ? View.GONE : View.VISIBLE);
          more.setText(open ? "——  Xem " + kids.size() + I18n.t(" câu trả lời") : I18n.t("——  Ẩn câu trả lời"));
        });
        list.addView(box);
        list.addView(more);
      }
    });
    replying.setOnClickListener(v -> { parent[0] = null; replying.setVisibility(View.GONE); });
    send.setOnClickListener(v -> {
      String text = input.getText().toString().trim();
      if (text.isEmpty()) return;
      JSONObject payload = json("body", text);
      if (parent[0] != null) try { payload.put("parentId", parent[0]); } catch (JSONException ignored) {}
      submitText(input, send, base, payload, x -> {
        if (input.length() == 0) { parent[0] = null; replying.setVisibility(View.GONE); }
        load[0].run();
      });
    });
    dialog.setContentView(sheet);
    Window w = dialog.getWindow();
    if (w != null) {
      w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(0));
      w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, Math.round(getResources().getDisplayMetrics().heightPixels * 0.62f));
      w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.25f);
      w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    }
    dialog.setOnDismissListener(x -> request("GET", shortsFollowing ? "/api/shorts?feed=following" : "/api/shorts", null, res -> { if (res.optJSONArray("shorts") != null) shortRows = orderedShorts(res.optJSONArray("shorts")); }));
    dialog.show();
    load[0].run();
  }

  private LinearLayout reelComment(final JSONObject c, boolean reply, final String base, final Runnable reload, final Runnable onReply) {
    LinearLayout r = row();
    r.setGravity(Gravity.TOP);
    r.setPadding(0, dp(8), 0, dp(8));
    avatar(c.optJSONObject("author"), r, reply ? 26 : 34);
    LinearLayout body = column();
    body.setPadding(dp(10), 0, dp(6), 0);
    TextView name = label(c.optJSONObject("author").optString("name"), 13, MUTED);
    name.setTypeface(null, Typeface.BOLD);
    name.setPadding(0, 0, 0, 0);
    body.addView(name);
    TextView text = label(c.optString("body"), 15, TEXT);
    text.setPadding(0, dp(2), 0, dp(4));
    body.addView(text);
    LinearLayout meta = row();
    meta.addView(label(ago(c.optLong("created")), 12, MUTED));
    TextView rep = label(I18n.t("     Trả lời"), 12, MUTED);
    rep.setTypeface(null, Typeface.BOLD);
    rep.setOnClickListener(v -> onReply.run());
    meta.addView(rep);
    body.addView(meta);
    r.addView(body, new LinearLayout.LayoutParams(0, -2, 1));
    int total = 0;
    JSONObject counts = c.optJSONObject("reactions");
    if (counts != null) for (String[] x : REACTIONS) total += counts.optInt(x[0]);
    final boolean liked = !c.isNull("myReaction") && !c.optString("myReaction").isEmpty();
    LinearLayout like = column();
    like.setGravity(Gravity.CENTER_HORIZONTAL);
    like.addView(icon("heart", 18, liked ? 0xfffe2c55 : MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
    TextView count = label(total > 0 ? String.valueOf(total) : "", 11, liked ? 0xfffe2c55 : MUTED);
    count.setPadding(0, dp(2), 0, 0);
    count.setGravity(Gravity.CENTER);
    like.addView(count);
    like.setContentDescription(liked ? I18n.t("Bỏ thích bình luận") : I18n.t("Thích bình luận"));
    like.setOnClickListener(v -> request("POST", base + "/" + c.optString("id") + "/reaction", json("reaction", liked ? JSONObject.NULL : "love"), x -> reload.run()));
    r.setOnLongClickListener(v -> { commentOptions(c, base, reload); return true; });
    r.addView(like, new LinearLayout.LayoutParams(dp(36), -2));
    return r;
  }

  private void chooseVideo() {
    if (postingVideo) {
      say(I18n.t("Đang tải video, vui lòng chờ."));
      return;
    }
    startActivityForResult(new Intent(this, StudioActivity.class), 203);
  }

  private void captureVideo() {
    Intent capture = new Intent(
      android.provider.MediaStore.ACTION_VIDEO_CAPTURE
    );
    capture.putExtra(android.provider.MediaStore.EXTRA_DURATION_LIMIT, 60);
    capture.putExtra(android.provider.MediaStore.EXTRA_VIDEO_QUALITY, 0);
    try {
      startActivityForResult(capture, 201);
    } catch (Exception e) {
      say(I18n.t("Không mở được camera quay video."));
    }
  }

  private void reviewMedia(android.net.Uri uri,int requestCode) {
    Intent editor=new Intent(this,MediaEditActivity.class).setData(uri);editor.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);editor.setClipData(android.content.ClipData.newRawUri("media",uri));startActivityForResult(editor,requestCode);
  }
  private void uploadVideo(android.net.Uri uri) { reviewMedia(uri,212); }
  private void uploadVideoNow(android.net.Uri uri) {
    EditText caption = new EditText(this);
    caption.setHint(I18n.t("Viết chú thích cho video"));
    new Sheet(this)
      .setTitle(I18n.t("Đăng video"))
      .setView(caption)
      .setPositiveButton(I18n.t("Đăng"), (dialog, which) -> {
        postingVideo = true;
        say(I18n.t("Đang đọc và tải video…"));
        final int generation = screen;
        String text = caption.getText().toString();
        new Thread(() -> {
          try {
            NativeMedia.Prepared selected = NativeMedia.read(this, uri, true);
            JSONObject payload = json(
              "data",
              selected.dataUrl(),
              "caption",
              text
            );
            final UploadProgress upload=new UploadProgress(this);
            api.call(
              "POST",
              "/api/shorts",
              payload,
              upload,
              (result, error, status) -> {
                upload.close();
                postingVideo = false;
                if (isDestroyed() || generation != screen) return;
                if (error != null) say(error);
                else {
                  navigate("shorts");
                  say(I18n.t("Đã đăng video."));
                }
              }
            );
          } catch (OutOfMemoryError e) {
            runOnUiThread(() -> { postingVideo = false; if (generation == screen) say(I18n.t("Thiết bị không đủ bộ nhớ để chuẩn bị video này.")); });
          } catch (Exception e) {
            final String reason = mediaFailure(e);
            runOnUiThread(() -> { postingVideo = false; if (generation == screen) say(reason); });
          }
        }).start();
      })
      .setNegativeButton(I18n.t("Hủy"), null)
      .show();
  }

  private void pickAvatar() {
    Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    intent.addCategory(Intent.CATEGORY_OPENABLE);
    intent.setType("image/*");
    intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
      "image/png",
      "image/jpeg",
      "image/webp",
    });
    try {
      startActivityForResult(intent, 100);
    } catch (Exception e) {
      say(I18n.t("Không mở được trình chọn ảnh."));
    }
  }

  @Override
  protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if(request==309){if(result==RESULT_OK&&data!=null&&data.getData()!=null&&photoGroup!=null){final JSONObject g=photoGroup;try{request("POST","/api/groups/"+g.optString("id")+"/avatar",json("data",dataUrl(data.getData(),1024*1024,null)),d->groupChat(d.optJSONObject("group")));}catch(Exception error){say(I18n.t("Chọn ảnh PNG/JPEG/WebP nhỏ hơn 1 MB."));}}photoGroup=null;return;}

    if (result == RESULT_OK && data != null && data.getData() != null) {
      try { getContentResolver().takePersistableUriPermission(data.getData(), data.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION); }
      catch (SecurityException ignored) {}
    }

    if (request >= 210 && request <= 212) {
      if(result==RESULT_OK && data!=null && data.getData()!=null){if(request==212)uploadVideoNow(data.getData());else preparePostMedia(request==211?304:300,data.getData());}
      return;
    }
    if (request == 309) {
      final String path = pendingDownload; pendingDownload = "";
      if (result != RESULT_OK || data == null || data.getData() == null || path.isEmpty()) return;
      final android.net.Uri destination = data.getData();
      api.image(path, bytes -> {
        if (bytes == null) { say(I18n.t("Chưa tải được tệp. Vui lòng thử lại.")); return; }
        new Thread(() -> {
          boolean saved = false;
          try (java.io.OutputStream out = getContentResolver().openOutputStream(destination)) { if (out != null) { out.write(bytes); saved = true; } }
          catch (Exception error) {}
          final boolean success = saved;
          runOnUiThread(() -> say(success ? I18n.t("Đã lưu tệp.") : I18n.t("Không lưu được tệp.")));
        }, "kinnect-download").start();
      });
      return;
    }
    if ((request == 203 || request == 204) && result == RESULT_OK && data != null && data.getStringExtra(StudioActivity.EXTRA_IMAGE) != null) {
      final java.io.File file = new java.io.File(data.getStringExtra(StudioActivity.EXTRA_IMAGE));
      final String action = data.getStringExtra(StudioActivity.EXTRA_ACTION);
      if ("story".equals(action)) reviewMedia(android.net.Uri.fromFile(file),211);
      else { composePost(); reviewMedia(android.net.Uri.fromFile(file),210); }
      return;
    }
    if ((request == 203 || request == 204) && result == RESULT_FIRST_USER && data != null && data.getData() != null) {
      if (request == 204) reviewMedia(data.getData(),211); else uploadVideo(data.getData());
      return;
    }
    if ((request == 203 || request == 204) && result == RESULT_OK && data != null && data.getBooleanExtra(StudioActivity.EXTRA_STORY, false)) {
      reviewMedia(android.net.Uri.fromFile(new java.io.File(data.getStringExtra(StudioActivity.EXTRA_VIDEO))),211);
      return;
    }
    if (request == 307 && result == RESULT_OK && data != null && data.getData() != null) {
      Intent studio = new Intent(this, StudioActivity.class);
      studio.putExtra(StudioActivity.EXTRA_STORY, true);
      studio.putExtra(StudioActivity.EXTRA_PHOTO, data.getData().toString());
      studio.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
      studio.setData(data.getData());
      startActivityForResult(studio, 204);
      return;
    }
    if (request == 204 && result == RESULT_FIRST_USER) { pickFile(304, "image/*|video/*"); return; }
    if (request == 203 && result == RESULT_OK && data != null && data.getStringExtra(StudioActivity.EXTRA_VIDEO) != null) {
      uploadVideo(android.net.Uri.fromFile(new java.io.File(data.getStringExtra(StudioActivity.EXTRA_VIDEO))));
      return;
    }
    if (request == 203 && result == RESULT_FIRST_USER) {
      Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
      pick.addCategory(Intent.CATEGORY_OPENABLE);
      pick.setType("video/*");
      try { startActivityForResult(pick, 200); } catch (Exception e) { say(I18n.t("Không mở được trình chọn video.")); }
      return;
    }
    if ((request >= 300 && request <= 306) || request == 308) {
      if (result == RESULT_OK && data != null && data.getData() != null) picked(request, data.getData());
      return;
    }
    if (
      (request == 200 || request == 201) &&
      result == RESULT_OK &&
      data != null &&
      data.getData() != null
    ) {
      uploadVideo(data.getData());
      return;
    }
    if (
      request == 100 &&
      result == RESULT_OK &&
      data != null &&
      data.getData() != null
    ) {
      try {
        byte[] image = NativeApi.read(
          getContentResolver().openInputStream(data.getData()),
          1024 * 1024
        );
        String type = getContentResolver().getType(data.getData());
        if (
          !Arrays.asList("image/png", "image/jpeg", "image/webp").contains(type)
        ) {
          say(I18n.t("Chọn ảnh PNG/JPEG/WebP."));
          return;
        }
        request(
          "POST",
          "/api/me/avatar",
          json(
            "data",
            "data:" +
              type +
              ";base64," +
              android.util.Base64.encodeToString(
                image,
                android.util.Base64.NO_WRAP
              )
          ),
          d -> { if (profileEditorAvatar != null && profileEditorAvatar.isAttachedToWindow()) request("GET", "/api/me", null, updated -> { me = updated.optJSONObject("user"); loadAvatarInto(me, profileEditorAvatar); say(I18n.t("Đã đổi ảnh đại diện")); }); else navigate("profile"); }
        );
      } catch (Exception e) {
        say(I18n.t("Chọn ảnh nhỏ hơn 1 MB."));
      }
    }
  }

  private void stopLocation() {
    if (locationListener != null) {
      try {
        ((LocationManager) getSystemService(LOCATION_SERVICE)).removeUpdates(
          locationListener
        );
      } catch (SecurityException ignored) {}
      locationListener = null;
    }
  }

  private boolean silentLocate = false;

  private void requestLocation() {
    if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) { locate(); return; }
    new Sheet(this)
      .setTitle(I18n.t("Tìm thành viên xung quanh"))
      .setMessage(
        I18n.t("Chỉ dùng vị trí gần đúng, lưu theo ô khoảng 5 km trong tối đa 24 giờ hiệu lực; không công khai tọa độ. Bạn có thể tắt và xóa ở Hồ sơ.")
      )
      .setPositiveButton(I18n.t("Đồng ý"), (d, w) -> {
        if (
          checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) !=
          PackageManager.PERMISSION_GRANTED
        ) requestPermissions(
          new String[] { Manifest.permission.ACCESS_COARSE_LOCATION },
          101
        );
        else locate();
      })
      .setNegativeButton(I18n.t("Hủy"), null)
      .show();
  }

  // Lấy vị trí: dùng vị trí gần nhất trong 30 phút, nếu không có thì hỏi đồng thời mạng / GPS / fused,
  // nguồn nào trả về trước thì dùng. Máy chủ chỉ lưu ô ~5 km, không lưu toạ độ chính xác.
  private void locate() {
    try {
      final LocationManager manager = (LocationManager) getSystemService(LOCATION_SERVICE);
      Location best = null;
      for (String name : manager.getProviders(true)) {
        Location last = manager.getLastKnownLocation(name);
        if (last != null && System.currentTimeMillis() - last.getTime() < 1800000 && (best == null || last.getTime() > best.getTime())) best = last;
      }
      if (best != null) { sendLocation(best); return; }
      List<String> sources = new ArrayList<>();
      for (String name : new String[] { "fused", LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER })
        if (manager.getAllProviders().contains(name) && manager.isProviderEnabled(name)) sources.add(name);
      if (sources.isEmpty()) {
        if (!silentLocate) say(I18n.t("Hãy bật Vị trí trên điện thoại rồi thử lại."));
        silentLocate = false;
        return;
      }
      stopLocation();
      locationListener = new LocationListener() {
        public void onLocationChanged(Location value) {
          if (locationListener != this) return;
          manager.removeUpdates(this);
          locationListener = null;
          sendLocation(value);
        }
        public void onProviderEnabled(String p) {}
        public void onProviderDisabled(String p) {}
        public void onStatusChanged(String p, int s, Bundle b) {}
      };
      for (String name : sources) {
        try { manager.requestLocationUpdates(name, 0, 0, locationListener, Looper.getMainLooper()); } catch (Exception ignored) {}
      }
      if (!silentLocate) say(I18n.t("Đang lấy vị trí gần đúng…"));
      final LocationListener waiting = locationListener;
      handler.postDelayed(() -> {
        if (locationListener == waiting && waiting != null) {
          manager.removeUpdates(waiting);
          locationListener = null;
          if (!silentLocate) say(I18n.t("Chưa lấy được vị trí. Hãy ra chỗ thoáng hoặc bật Wi‑Fi rồi thử lại."));
          silentLocate = false;
        }
      }, 25000);
    } catch (SecurityException e) {
      say(I18n.t("Chưa được cấp quyền vị trí."));
    }
  }

  private void sendLocation(Location location) {
    request(
      "PATCH",
      "/api/me/location",
      json(
        "enabled",
        true,
        "latitude",
        location.getLatitude(),
        "longitude",
        location.getLongitude()
      ),
      d -> {
        boolean had = me != null && me.optBoolean("hasLocation");
        me = d.optJSONObject("user");
        boolean quiet = silentLocate;
        silentLocate = false;
        if (!quiet || (!had && tab.equals("discover") && onTabRoot)) navigate("discover");
        else say("");
      }
    );
  }

  @Override
  public void onRequestPermissionsResult(
    int code,
    String[] permissions,
    int[] results
  ) {
    super.onRequestPermissionsResult(code, permissions, results);
    if(code==901){if(calls!=null)calls.permissionsResult(results);return;}
    if(code==950){backgroundExtras(true);return;}
    if (code == 102) {
      if (
        results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED
      ) captureVideo();
      else say(I18n.t("Cần quyền camera để quay video."));
      return;
    }
    if (
      code == 101 &&
      results.length > 0 &&
      results[0] == PackageManager.PERMISSION_GRANTED
    ) locate();
    else if (code == 101) say(
      I18n.t("Bạn vẫn có thể tìm bạn theo sở thích khi không cấp vị trí.")
    );
  }

  @Override
  protected void onStop() {
    super.onStop();
    KinnectService.appVisible=false;

    if (shortVideo != null) shortVideo.pause();
    resumeVideos.clear();
    for (VideoView video : mediaVideos) if (video.isPlaying()) { resumeVideos.add(video); video.pause(); }
    stopped = true;
    notificationHandler.removeCallbacksAndMessages(null);
    handler.removeCallbacksAndMessages(null);
    if (locationListener != null) {
      try {
        ((LocationManager) getSystemService(LOCATION_SERVICE)).removeUpdates(
          locationListener
        );
      } catch (SecurityException ignored) {}
      locationListener = null;
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    stopped = false;
    if(storeReturning&&me!=null){storeReturning=false;api.call("GET","/api/me",null,(data,error,status)->{if(error==null&&data!=null&&!isDestroyed()){me=data.optJSONObject("user");refreshPage();}});}
    KinnectService.appVisible = true;
    notificationHandler.removeCallbacksAndMessages(null);
    notificationHandler.post(notificationPoll);
    ensureCalls();
    if (calls != null) {calls.checkPending();if(root!=null)calls.attachReturn(root);}
    for (VideoView video : resumeVideos) if (video.isAttachedToWindow()) if(!mediaCallBlocked)video.start();
    resumeVideos.clear();
    if (resumeStory != null) resumeStory.run();
    if (poll != null) handler.postDelayed(poll, 4000);
  }

  @Override
  protected void onDestroy() {
    if(mediaCallListening)KinnectService.unlisten(mediaCallEvents);
    startupHandler.removeCallbacksAndMessages(null);
    if (splashAnimator != null) splashAnimator.cancel();
    for (VideoView video : mediaVideos) { try { video.stopPlayback(); } catch (RuntimeException ignored) {} }
    mediaVideos.clear(); resumeVideos.clear();
    stopShort();
    if(calls!=null){calls.close();calls=null;}
    super.onDestroy();
  }

  private final ArrayDeque<Runnable> history = new ArrayDeque<>();
  private boolean goingBack;
  private Runnable subBack;

  // Ghi nhớ màn đang mở để nút Back quay về đúng màn trước.
  private String currentKey = "";

  private void remember(String key, Runnable page) {
    if (!goingBack && currentPage != null && !key.equals(currentKey)) { history.push(currentPage); while (history.size() > 30) history.removeLast(); }
    goingBack = false;
    currentKey = key;
    currentPage = page;
    subBack = null;
  }

  @Override
  public void onBackPressed() {
    if (subBack != null) { Runnable r = subBack; subBack = null; r.run(); return; }
    if (me != null && !history.isEmpty()) { goingBack = true; Runnable previous = history.pop(); previous.run(); goingBack = false; return; }
    if (me != null && (!onTabRoot || !tab.equals("feed"))) {
      navigate(onTabRoot ? "feed" : tab);
      return;
    }
    super.onBackPressed();
  }


  // ===================== Bổ sung cho bản Android đầy đủ =====================
  private int discoverRadius = 5;
  private String discoverSort = "interests", attachTarget = "";
  private String pendingMedia;
  private Button attachButton;
  private JSONArray conversationUsers;
  private JSONObject pendingStoryMedia;
  private static final String[][] REACTIONS = { { "like", "👍" }, { "love", "❤️" }, { "haha", "😆" }, { "wow", "😮" }, { "sad", "😢" }, { "angry", "😡" } };

  private interface ReactionPick { void pick(int index); }

  // Thanh cảm xúc kiểu Facebook: viên nổi phía trên nút, biểu tượng lớn bật lên lần lượt.
  private void reactionBar(View anchor, final ReactionPick pick) {
    final LinearLayout bar = row();
    bar.setPadding(dp(8), dp(6), dp(8), dp(6));
    GradientDrawable bg = background(CARD, 99);
    bg.setStroke(dp(1), LINE);
    bar.setBackground(bg);
    bar.setElevation(dp(10));
    final android.widget.PopupWindow popup = new android.widget.PopupWindow(bar, -2, -2, true);
    popup.setOutsideTouchable(true);
    popup.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(0));
    popup.setElevation(dp(10));
    for (int i = 0; i < REACTIONS.length; i++) {
      final int index = i;
      TextView e = new TextView(this);
      e.setText(REACTIONS[i][1]);
      e.setTextSize(28);
      e.setGravity(Gravity.CENTER);
      e.setContentDescription(new String[] { I18n.t("Thích"), I18n.t("Yêu thích"), "Haha", "Wow", I18n.t("Buồn"), I18n.t("Phẫn nộ") }[i]);
      e.setScaleX(0f);
      e.setScaleY(0f);
      e.animate().scaleX(1f).scaleY(1f).setStartDelay(30L * i).setDuration(180).setInterpolator(new android.view.animation.OvershootInterpolator(2.2f)).start();
      e.setOnTouchListener((v, ev) -> {
        if (ev.getActionMasked() == MotionEvent.ACTION_DOWN) v.animate().scaleX(1.35f).scaleY(1.35f).translationY(-dp(8)).setDuration(120).start();
        if (ev.getActionMasked() == MotionEvent.ACTION_CANCEL) v.animate().scaleX(1f).scaleY(1f).translationY(0).setDuration(120).start();
        return false;
      });
      e.setOnClickListener(v -> { popup.dismiss(); pick.pick(index); });
      bar.addView(e, new LinearLayout.LayoutParams(dp(46), dp(48)));
    }
    bar.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED);
    View host = anchor != null && anchor.isAttachedToWindow() ? anchor : root;
    int[] at = new int[2];
    host.getLocationInWindow(at);
    int width = bar.getMeasuredWidth(), screen = getResources().getDisplayMetrics().widthPixels;
    int x = anchor == null ? (screen - width) / 2 : Math.max(dp(8), Math.min(screen - width - dp(8), at[0]));
    int y = anchor == null ? getResources().getDisplayMetrics().heightPixels / 2 : Math.max(dp(40), at[1] - bar.getMeasuredHeight() - dp(8));
    popup.showAtLocation(root, Gravity.TOP | Gravity.START, x, y);
    try { if (anchor != null) anchor.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS); } catch (Exception ignored) {}
  }

  private Button chip(String text, boolean active, Runnable action) {
    Button b = new Button(this);
    b.setText(text);
    b.setAllCaps(false);
    b.setTextSize(13);
    b.setTextColor(active ? ACCENT : TEXT);
    b.setTypeface(Typeface.create(active ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
    b.setStateListAnimator(null);
    android.graphics.drawable.Drawable chipBg = pressable(active ? PRIMARY_SOFT : CARD, 999);
    if (!active && chipBg instanceof android.graphics.drawable.RippleDrawable) ((GradientDrawable) ((android.graphics.drawable.RippleDrawable) chipBg).getDrawable(0)).setStroke(1, LINE);
    b.setBackground(chipBg);
    b.setPadding(dp(14), 0, dp(14), 0);
    b.setMinWidth(0);
    b.setMinimumWidth(0);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, dp(38));
    p.setMargins(0, dp(6), dp(8), dp(6));
    b.setLayoutParams(p);
    b.setOnClickListener(v -> action.run());
    return b;
  }

  private String ago(long time) {
    long s = Math.max(0, (System.currentTimeMillis() - time) / 1000);
    if (s < 60) return "vừa xong";
    if (s < 3600) return (s / 60) + " phút";
    if (s < 86400) return (s / 3600) + " giờ";
    if (s < 7 * 86400) return (s / 86400) + " ngày";
    return new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()).format(new Date(time));
  }

  private String noticeText(String kind) {
    if (kind.equals("follow")) return " đã theo dõi bạn";
    if (kind.equals("friend_request")) return " đã gửi lời mời kết bạn";
    if (kind.equals("friend_accept") || kind.equals("friend_accepted")) return " đã chấp nhận lời mời kết bạn";
    if (kind.equals("comment_reply")) return " đã trả lời bình luận của bạn";
    if (kind.equals("missed_call")) return " đã gọi nhỡ cho bạn";
    if (kind.equals("like")) return " đã bày tỏ cảm xúc về bài viết của bạn";
    if (kind.equals("comment")) return " đã bình luận bài viết của bạn";
    if (kind.equals("gift")) return " đã gửi quà miễn phí";
    if (kind.equals("private_request")) return " đã yêu cầu xem ảnh riêng tư";
    if (kind.equals("private_granted")) return " đã cấp quyền xem ảnh riêng tư";
    if (kind.equals("private_revoked")) return " đã thu hồi quyền xem ảnh riêng tư";
    if (kind.equals("group_message")) return " đã nhắn trong nhóm";
    if (kind.equals("short_like")) return " đã thích video của bạn";
    if (kind.equals("short_comment")) return " đã bình luận video của bạn";
    return " đã gửi tin nhắn";
  }

  // ----- Màn giới thiệu (hiện mỗi lần mở app khi chưa đăng nhập)
  private int introPage = 0;


  private TextView welcomeText(String text,int size,int color,boolean bold){TextView v=label(text,size,color);v.setPadding(0,0,0,0);v.setLineSpacing(dp(3),1f);if(bold)v.setTypeface(Typeface.create("sans-serif",Typeface.BOLD));return v;}
  private LinearLayout welcomeBrand(){LinearLayout brand=row();brand.setBaselineAligned(false);ImageView logo=new ImageView(this);logo.setImageResource(getResources().getIdentifier("kinnect_logo","drawable",getPackageName()));logo.setScaleType(ImageView.ScaleType.FIT_CENTER);brand.addView(logo,new LinearLayout.LayoutParams(dp(34),dp(34)));TextView name=welcomeText("Kinnect",19,ACCENT,true);name.setPadding(dp(9),0,0,0);name.setSingleLine(true);name.setAutoSizeTextTypeUniformWithConfiguration(12,19,1,android.util.TypedValue.COMPLEX_UNIT_SP);name.setEllipsize(android.text.TextUtils.TruncateAt.END);brand.addView(name,new LinearLayout.LayoutParams(0,-2,1));return brand;}
  private void welcomeFeature(String glyph,String title,String description,int color){
    LinearLayout panel=column();panel.setPadding(dp(18),dp(19),dp(18),dp(19));panel.setBackground(outlined(CARD,20));LinearLayout line=row();FrameLayout bubble=new FrameLayout(this);bubble.setBackground(background((color&0x00ffffff)|0x18000000,14));bubble.addView(icon(glyph,23,color),new FrameLayout.LayoutParams(dp(23),dp(23),Gravity.CENTER));line.addView(bubble,new LinearLayout.LayoutParams(dp(46),dp(46)));LinearLayout words=column();words.setPadding(dp(13),0,0,0);words.addView(welcomeText(title,17,TEXT,true));TextView detail=welcomeText(description,14,MUTED,false);detail.setPadding(0,dp(6),0,0);words.addView(detail);line.addView(words,new LinearLayout.LayoutParams(0,-2,1));panel.addView(line);LinearLayout.LayoutParams space=new LinearLayout.LayoutParams(-1,-2);space.topMargin=dp(10);content.addView(panel,space);
  }

  private void intro() {
    shell("",false);root.removeAllViews();root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{PRIMARY_SOFT,BG,BG}));getWindow().setStatusBarColor(PRIMARY_SOFT);getWindow().setNavigationBarColor(BG);content=column();content.setPadding(dp(22),dp(10),dp(22),dp(12));root.addView(content,new LinearLayout.LayoutParams(-1,-1));
    LinearLayout brand=welcomeBrand();TextView language=welcomeText("VI / EN",12,TEXT,true);language.setPadding(dp(8),0,dp(8),0);language.setGravity(Gravity.CENTER);language.setSingleLine(true);language.setIncludeFontPadding(false);language.setMinWidth(dp(56));language.setContentDescription(I18n.t("Ngôn ngữ ứng dụng"));language.setOnClickListener(v->languageMenu());brand.addView(language,new LinearLayout.LayoutParams(-2,dp(44)));TextView login=welcomeText(I18n.t("Đăng nhập"),14,WHITE,true);login.setGravity(Gravity.CENTER);login.setPadding(dp(12),0,dp(12),0);login.setBackground(pressable(ACCENT,12));login.setOnClickListener(v->auth(false));brand.addView(login,new LinearLayout.LayoutParams(-2,dp(44)));content.addView(brand,new LinearLayout.LayoutParams(-1,dp(48)));
    TextView headline=welcomeText(I18n.t("Kết nối đúng gu.\nSống đúng mình."),29,TEXT,true);headline.setGravity(Gravity.CENTER);headline.setPadding(0,dp(13),0,dp(4));headline.setMaxLines(2);headline.setAutoSizeTextTypeUniformWithConfiguration(22,29,1,android.util.TypedValue.COMPLEX_UNIT_SP);content.addView(headline,new LinearLayout.LayoutParams(-1,dp(92)));
    View showcase=new PhoneFeatureShowcase();showcase.setContentDescription(I18n.t("Điện thoại minh họa luân phiên các tính năng Bảng tin, Khám phá, Video và Live. Chạm để chuyển tính năng."));content.addView(showcase,new LinearLayout.LayoutParams(-1,0,1));
    LinearLayout start=authButton(null,I18n.t("Bắt đầu kết nối"),true);start.setOnClickListener(v->auth(true));content.addView(start,new LinearLayout.LayoutParams(-1,dp(52)));TextView note=welcomeText(I18n.t("Dành cho người từ 18 tuổi · Minh họa tính năng"),11,MUTED,false);note.setGravity(Gravity.CENTER);note.setPadding(0,dp(10),0,0);content.addView(note,new LinearLayout.LayoutParams(-1,dp(30)));
  }
  private final class PhoneFeatureShowcase extends WelcomeScene {
    final android.graphics.drawable.Drawable[] glyphs={WebIcons.load(MainActivity.this,"newspaper"),WebIcons.load(MainActivity.this,"compass"),WebIcons.load(MainActivity.this,"clapperboard"),WebIcons.load(MainActivity.this,"radio")};
    final android.graphics.drawable.Drawable miniLogo=getResources().getDrawable(getResources().getIdentifier("kinnect_logo","drawable",getPackageName()));
    final String[] tabs={"Bảng tin","Khám phá","Video","Live"};long clock=android.os.SystemClock.uptimeMillis();int manual=0;
    PhoneFeatureShowcase(){super();setClickable(true);setContentDescription(I18n.t("Xem trước Bảng tin, Khám phá, Tạo nội dung, Video và Live"));}
    void selectPreview(int index){manual=index;clock=android.os.SystemClock.uptimeMillis();invalidate();}
    void previewCreate(){new Sheet(MainActivity.this).setTitle(I18n.t("Tạo nội dung · Đăng nhập để tiếp tục")).setItemIcons(new String[]{"newspaper","clapperboard","radio"}).setItems(new String[]{I18n.t("Đăng bài viết"),I18n.t("Quay / đăng video"),I18n.t("Mở phòng trực tiếp")},(d,which)->auth(false)).setNegativeButton(I18n.t("Đóng"),null).show();}
    @Override public boolean onTouchEvent(android.view.MotionEvent event){if(event.getAction()==android.view.MotionEvent.ACTION_DOWN)return true;if(event.getAction()!=android.view.MotionEvent.ACTION_UP)return true;performClick();float scale=Math.min(getWidth()/330f,getHeight()/450f);if(scale<=0)return true;float x=(event.getX()-(getWidth()-380*scale)/2)/scale,y=(event.getY()-(getHeight()-450*scale)/2)/scale;if(y>=378&&y<=415&&x>=100&&x<280){int tab=(int)((x-100)/36);if(tab==2)previewCreate();else selectPreview(tab<2?tab:tab-1);return true;}if(x<100||x>280)return true;int active=(manual+(android.animation.ValueAnimator.areAnimatorsEnabled()?(int)((android.os.SystemClock.uptimeMillis()-clock)/1500):0))%4;if(active==0&&y>=140&&y<=172||active==2&&y>200&&x>244||active==3&&y>=127&&y<=154)auth(false);return true;}
    @Override public boolean performClick(){super.performClick();return true;}
    void iphoneStatus(){for(int i=0;i<4;i++)box(234+i*3.3f,37-(i+1)*1.8f,2.4f,(i+1)*1.8f,.7f,TEXT);pen.setColor(TEXT);pen.setStyle(Paint.Style.STROKE);pen.setStrokeWidth(1.4f);canvas.drawArc(new RectF(249,29,260,40),222,96,false,pen);canvas.drawArc(new RectF(251.5f,31.5f,257.5f,37.5f),222,96,false,pen);pen.setStyle(Paint.Style.FILL);circle(254.5f,36.3f,.9f,TEXT);pen.setStyle(Paint.Style.STROKE);pen.setStrokeWidth(.8f);canvas.drawRoundRect(new RectF(263,29,276,36),1.6f,1.6f,pen);pen.setStyle(Paint.Style.FILL);box(264.4f,30.4f,9.9f,4.2f,.7f,TEXT);box(277,31.2f,1.1f,2.8f,.4f,TEXT);}

    @Override public void onWindowFocusChanged(boolean focused){super.onWindowFocusChanged(focused);if(focused)invalidate();}
    @Override protected void onAttachedToWindow(){super.onAttachedToWindow();invalidate();}
    void glyph(android.graphics.drawable.Drawable icon,float x,float y,int size,int color){if(icon!=miniLogo)icon.setTint(color);icon.setBounds((int)x,(int)y,(int)x+size,(int)y+size);icon.draw(canvas);}
    void centered(String text,float y,float size,int color,boolean bold){pen.setTextSize(size);pen.setTypeface(Typeface.create("sans-serif",bold?Typeface.BOLD:Typeface.NORMAL));word(text,(380-pen.measureText(text))/2,y,size,color,bold);}
    android.graphics.Bitmap demoPhoto;
    void photo(float x,float y,float w,float h,float radius){if(demoPhoto==null){try(java.io.InputStream stream=getAssets().open("welcome-profile.png")){demoPhoto=android.graphics.BitmapFactory.decodeStream(stream);}catch(Exception ignored){return;}}if(demoPhoto==null)return;int saved=canvas.save();Path clip=new Path();clip.addRoundRect(new RectF(x,y,x+w,y+h),radius,radius,Path.Direction.CW);canvas.clipPath(clip);box(x,y,w,h,radius,SOFT);float ratio=w>100?Math.min(w/demoPhoto.getWidth(),h/demoPhoto.getHeight()):Math.max(w/demoPhoto.getWidth(),h/demoPhoto.getHeight());float rw=demoPhoto.getWidth()*ratio,rh=demoPhoto.getHeight()*ratio;float offset=w<=100?0:(h-rh)/2;canvas.drawBitmap(demoPhoto,null,new RectF(x+(w-rw)/2,y+offset,x+(w+rw)/2,y+offset+rh),pen);canvas.restoreToCount(saved);}
    final android.graphics.Bitmap[] demoPeople=new android.graphics.Bitmap[4];
    void personPhoto(int index,float x,float y,float w,float h){if(demoPeople[index]==null){try(java.io.InputStream stream=getAssets().open(index==0?"welcome-profile.png":"welcome-profile-"+index+".png")){demoPeople[index]=android.graphics.BitmapFactory.decodeStream(stream);}catch(Exception ignored){return;}}android.graphics.Bitmap previous=demoPhoto;demoPhoto=demoPeople[index];photo(x,y,w,h,8);demoPhoto=previous;}
    void screen(int index){
      box(95,18,190,409,27,CARD);word("9:41",108,39,8,TEXT,true);iphoneStatus();glyph(miniLogo,103,54,19,WHITE);word("Kinnect",128,69,14,ACCENT,true);glyph(WebIcons.load(MainActivity.this,"bell"),237,56,13,MUTED);photo(258,54,17,17,8);word(tabs[index]+" · Hồ sơ mẫu",108,86,8,MUTED,false);
      if(index==0){circle(122,108,14,PRIMARY_SOFT);glyph(WebIcons.load(MainActivity.this,"plus"),115,101,14,ACCENT);word("Tạo tin",110,130,7,MUTED,false);photo(145,94,28,28,14);word("Minh Anh",143,130,7,MUTED,false);box(103,140,174,32,10,SOFT);photo(108,145,21,21,10);word("Bạn đang nghĩ gì?",137,158,8,MUTED,false);photo(107,184,21,21,10);word("Minh Anh · 27",134,193,9,TEXT,true);word("Hồ sơ minh họa",134,204,7,MUTED,false);word("Tập luyện mỗi ngày",107,220,9,TEXT,false);photo(103,229,174,119,9);glyph(WebIcons.load(MainActivity.this,"heart"),108,359,13,PINK);glyph(WebIcons.load(MainActivity.this,"message_circle"),139,359,13,MUTED);glyph(WebIcons.load(MainActivity.this,"share_2"),170,359,13,MUTED);}
      else if(index==1){box(102,95,176,24,8,SOFT);word("Dành cho bạn",107,110,7,ACCENT,true);word("Quanh đây",171,110,7,MUTED,false);word("Đang theo dõi",218,110,7,MUTED,false);box(102,126,176,24,8,SOFT);glyph(WebIcons.load(MainActivity.this,"search"),108,133,10,MUTED);word("Tên hoặc @username",124,142,8,MUTED,false);String[] filters={"Tuổi","Cân nặng","Chiều cao","Giới tính"};for(int i=0;i<4;i++){box(102+i*37,157,35,21,6,SOFT);word(filters[i],105+i*37,170,6,TEXT,false);}glyph(WebIcons.load(MainActivity.this,"sliders_horizontal"),257,162,13,MUTED);String[] people={"Minh Anh, 27","Gia Huy, 28","Hoàng Nam, 30","Quang Minh, 26"};for(int i=0;i<4;i++){float px=103+(i%2)*89,py=187+(i/2)*96;box(px,py,85,91,8,SOFT);personPhoto(i,px,py,85,71);pen.setTextSize(7);pen.setTypeface(Typeface.create("sans-serif",Typeface.BOLD));float labelX=px+(85-pen.measureText(people[i]))/2;word(people[i],labelX,py+84,7,TEXT,true);}}
      else if(index==2){box(100,94,180,282,12,0xff111116);photo(100,94,180,282,12);box(103,98,174,24,8,0xaa111116);word("Đề xuất",143,114,9,WHITE,true);word("Đang theo dõi",194,114,8,WHITE,false);photo(253,218,18,18,9);circle(262,240,6,ACCENT);word("+",259,244,9,WHITE,true);glyph(WebIcons.load(MainActivity.this,"heart"),255,260,14,WHITE);glyph(WebIcons.load(MainActivity.this,"message_circle"),255,291,14,WHITE);glyph(WebIcons.load(MainActivity.this,"share_2"),255,322,14,WHITE);box(103,331,141,40,8,0xaa111116);word("@minhanh_demo",111,346,9,WHITE,true);word("Video minh họa",111,362,8,WHITE,false);}
      else{box(101,96,178,280,12,0xff17151e);photo(101,96,178,280,12);box(108,103,40,17,6,PINK);word("LIVE",117,115,8,WHITE,true);box(151,103,68,17,6,0xaa17151e);word("Minh họa",163,115,8,WHITE,false);box(107,309,166,60,10,0xbb17151e);word("Minh Anh đang trực tiếp",114,328,10,WHITE,true);word("Chào mừng đến với Kinnect",114,345,8,WHITE,false);glyph(WebIcons.load(MainActivity.this,"heart"),251,349,14,PINK);}
    }
    void previewNavigation(int index){String[] names={"Bảng tin","Khám phá","","Video","Live"};String[] icons={"house","compass","plus","clapperboard","radio"};for(int i=0;i<5;i++){float center=118+i*36;boolean selected=i==(index<2?index:index+1);if(i==2){box(center-13,381,26,26,8,ACCENT);glyph(WebIcons.load(MainActivity.this,"plus"),center-7,387,14,WHITE);}else{glyph(WebIcons.load(MainActivity.this,icons[i]),center-7,387,14,selected?ACCENT:MUTED);pen.setTextSize(7);pen.setTypeface(Typeface.create("sans-serif",Typeface.NORMAL));float left=center-pen.measureText(names[i])/2;word(names[i],left,411,7,selected?ACCENT:MUTED,false);}}}
    void ripple(long elapsed,boolean animate){if(!animate){circle(190,220,145,PRIMARY_SOFT);return;}for(int i=0;i<3;i++){float phase=((elapsed+i*500)%1500)/1500f;float radius=48+phase*142;int alpha=(int)(65*(1-phase));pen.setStyle(Paint.Style.STROKE);pen.setStrokeWidth(1.3f);pen.setColor((alpha<<24)|(ACCENT&0xffffff));canvas.drawCircle(190,220,radius,pen);}pen.setStyle(Paint.Style.FILL);}
    @Override protected void onDraw(Canvas c){canvas=c;float scale=Math.min(getWidth()/330f,getHeight()/450f);if(scale<=0)return;int save=c.save();c.translate((getWidth()-380*scale)/2,(getHeight()-450*scale)/2);c.scale(scale,scale);long elapsed=android.os.SystemClock.uptimeMillis()-clock;boolean animate=android.animation.ValueAnimator.areAnimatorsEnabled();int index=(manual+(animate?(int)(elapsed/1500):0))%4;float phase=animate?(elapsed%1500)/1500f:0;
      ripple(elapsed,animate);c.save();pen.setShadowLayer(16,0,8,0x30271b43);box(89,12,202,423,34,0xffa5a7ae);pen.clearShadowLayer();box(91,14,198,419,32,0xff111116);box(86,91,3,18,1,0xff8b8e98);box(86,124,3,32,1,0xff8b8e98);box(86,166,3,32,1,0xff8b8e98);box(291,134,3,48,1,0xff8b8e98);screen(index);if(phase>.84f){int layer=c.saveLayerAlpha(95,18,285,427,(int)((phase-.84f)/.16f*255));screen((index+1)%4);c.restoreToCount(layer);}previewNavigation(index);box(172,27,36,11,6,0xff111116);circle(201,32,2,0xff26354b);box(165,418,50,3,2,0xff383840);c.restore();c.restoreToCount(save);if(animate&&isShown()&&hasWindowFocus())postInvalidateDelayed(33);
    }
  }
  private class WelcomeScene extends View {
    final Paint pen=new Paint(Paint.ANTI_ALIAS_FLAG);final RectF rect=new RectF();Canvas canvas;
    WelcomeScene(){super(MainActivity.this);setLayerType(View.LAYER_TYPE_SOFTWARE,null);}
    void box(float x,float y,float w,float h,float radius,int color){pen.setStyle(Paint.Style.FILL);pen.setShader(null);pen.setColor(color);rect.set(x,y,x+w,y+h);canvas.drawRoundRect(rect,radius,radius,pen);}
    void word(String text,float x,float y,float size,int color,boolean bold){pen.setShader(null);pen.setColor(color);pen.setTypeface(Typeface.create("sans-serif",bold?Typeface.BOLD:Typeface.NORMAL));pen.setTextSize(size);canvas.drawText(text,x,y,pen);}
    void circle(float x,float y,float r,int color){pen.setShader(null);pen.setColor(color);canvas.drawCircle(x,y,r,pen);}
    @Override protected void onDraw(Canvas c){super.onDraw(c);canvas=c;float scale=Math.min(getWidth()/380f,getHeight()/310f);int saved=c.save();c.translate((getWidth()-380*scale)/2,(getHeight()-310*scale)/2);c.scale(scale,scale);
      circle(198,150,132,PRIMARY_SOFT);circle(312,73,25,(PINK&0xffffff)|0x18000000);circle(56,235,20,PRIMARY_SOFT);
      c.save();c.rotate(-7,124,151);pen.setShadowLayer(13,0,7,0x1c2a154a);box(46,39,164,231,23,CARD);pen.clearShadowLayer();
      pen.setShader(new android.graphics.LinearGradient(62,55,195,175,new int[]{0xff8b5cf6,0xffec4899},null,android.graphics.Shader.TileMode.CLAMP));rect.set(56,49,200,177);c.drawRoundRect(rect,17,17,pen);pen.setShader(null);
      circle(128,100,22,0xffeadcff);box(87,128,82,46,30,0xffeadcff);word("HỒ SƠ MINH HỌA",65,195,8,MUTED,true);word("Là chính bạn",65,217,16,TEXT,true);box(65,232,62,20,10,PRIMARY_SOFT);word("Âm nhạc",73,246,9,ACCENT,true);box(134,232,55,20,10,SOFT);word("Du lịch",142,246,9,MUTED,true);c.restore();
      c.save();c.rotate(8,261,126);pen.setShadowLayer(12,0,6,0x242a154a);box(208,42,126,180,20,0xff30204b);pen.clearShadowLayer();box(218,52,106,160,14,0xff4c2b70);circle(269,116,34,0xff714096);pen.setColor(WHITE);Path triangle=new Path();triangle.moveTo(261,101);triangle.lineTo(261,130);triangle.lineTo(283,115);triangle.close();c.drawPath(triangle,pen);word("VIDEO",229,78,10,0xffeadcff,true);word("Chất riêng của bạn",228,188,9,WHITE,true);c.restore();
      pen.setShadowLayer(10,0,5,0x202a154a);box(140,226,209,57,17,CARD);pen.clearShadowLayer();circle(165,255,14,PRIMARY_SOFT);word("K",160,261,15,ACCENT,true);word("Bắt đầu bằng lời chào",188,250,12,TEXT,true);word("Nhắn tin · Gọi thoại · Video",188,267,9,MUTED,false);
      box(20,190,91,30,15,CARD);circle(35,205,4,0xff10b981);word("LIVE",47,210,11,TEXT,true);word("MINH HỌA TÍNH NĂNG",126,308,8,MUTED,false);c.restoreToCount(saved);
    }
  }

  // ----- Đăng nhập nhanh trên thiết bị này + Google/Facebook
  private void authExtras(boolean register) {
    final int generation = screen;
    final LinearLayout recent = column();
    final LinearLayout providersBox = column();
    content.addView(recent);
    content.addView(providersBox);
    if (!register) api.call("GET", "/api/remembered", null, (data, error, status) -> {
      JSONArray accounts = data == null ? null : data.optJSONArray("accounts");
      if (accounts == null || accounts.length() == 0 || isDestroyed() || generation != screen) return;
      for (int i = 0; i < accounts.length(); i++) {
        final JSONObject a = accounts.optJSONObject(i);
        LinearLayout r = row();
        r.setPadding(dp(12), dp(10), dp(6), dp(10));
        r.setBackground(outlined(CARD, 14));
        avatar(a, r, 40);
        LinearLayout t = column();
        t.setPadding(dp(12), 0, 0, 0);
        TextView n = label(a.optString("name"), 15, TEXT);
        n.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        t.addView(n);
        t.addView(label("@" + a.optString("username"), 12, MUTED));
        r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
        FrameLayout go = new FrameLayout(this);
        go.addView(icon("log_in", 18, ACCENT), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
        r.addView(go, new LinearLayout.LayoutParams(dp(36), dp(36)));
        FrameLayout remove = new FrameLayout(this);
        remove.addView(icon("x", 16, MUTED), new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
        remove.setBackground(pressable(CARD, 99));
        remove.setContentDescription(I18n.t("Gỡ tài khoản khỏi thiết bị"));
        remove.setOnClickListener(v -> api.call("DELETE", "/api/remembered/" + a.optString("id"), json(), (d, e, s) -> { if (generation == screen && !isDestroyed()) { if (e != null) say(e); else auth(false); } }));
        r.addView(remove, new LinearLayout.LayoutParams(dp(36), dp(36)));
        r.setContentDescription(I18n.t("Đăng nhập nhanh ") + a.optString("name"));
        r.setOnClickListener(v -> api.call("POST", "/api/remembered/login", json("userId", a.optString("id")), (d, e, s) -> {
          if (generation != screen || isDestroyed()) return;
          if (e != null) { say(e); return; }
          me = d.optJSONObject("user");
          navigate("feed");
        }));
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(10), 0, 0);
        recent.addView(r, p);
      }
    });
    api.call("GET", "/api/oauth/providers", null, (data, error, status) -> {
      JSONArray providers = data == null ? null : data.optJSONArray("providers");
      if (providers == null || providers.length() == 0 || isDestroyed() || generation != screen) return;
      LinearLayout buttons = row();
      for (int i = 0; i < providers.length(); i++) {
        final String provider = providers.optString(i);
        boolean google = provider.equals("google");
        LinearLayout b = row();
        b.setGravity(Gravity.CENTER);
        b.setBackground(outlined(CARD, 14));
        ImageView mark = new ImageView(this);
        mark.setImageResource(getResources().getIdentifier(google ? "ic_brand_google" : "ic_brand_facebook", "drawable", getPackageName()));
        b.addView(mark, new LinearLayout.LayoutParams(dp(22), dp(22)));
        TextView t = label(google ? "Google" : "Facebook", 14, TEXT);
        t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        t.setPadding(dp(10), 0, 0, 0);
        b.addView(t);
        b.setContentDescription(I18n.t("Tiếp tục với ") + (google ? "Google" : "Facebook"));
        b.setOnClickListener(v -> {
          try { startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(server() + "/api/oauth/" + provider + "/start?client=android"))); }
          catch (Exception e) { say(I18n.t("Không mở được trình duyệt.")); }
        });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, dp(50), 1);
        if (i > 0) p.leftMargin = dp(10);
        buttons.addView(b, p);
      }
      LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(-1, -2);
      bp.topMargin = dp(14);
      providersBox.addView(buttons, bp);
      providersBox.addView(textDivider(I18n.t("hoặc")));
    });
  }

  @Override
  protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    handleLink(intent);
    handleExtras(intent);
  }

  private void handleLink(Intent intent) {
    android.net.Uri uri = intent == null ? null : intent.getData();
    if (uri == null || !"kinnect".equals(uri.getScheme()) || !"oauth".equals(uri.getHost())) return;
    String code = uri.getQueryParameter("code"), ticket = uri.getQueryParameter("ticket"), error = uri.getQueryParameter("error");
    if (error != null) { auth(false); say(I18n.t("Đăng nhập chưa hoàn tất. Hãy thử lại.")); return; }
    if (code != null) api.call("POST", "/api/oauth/app-session", json("code", code), (d, e, s) -> {
      if (e != null) { auth(false); say(e); return; }
      me = d.optJSONObject("user");
      navigate("feed");
    });
    if (ticket != null) oauthComplete(ticket);
  }

  private void oauthComplete(String ticket) {
    api.call("GET", "/api/oauth/pending?ticket=" + encode(ticket), null, (d, e, s) -> {
      if (e != null) { auth(false); say(e); return; }
      shell(I18n.t("Hoàn tất đăng ký"), false);
      content.addView(label(I18n.t("Chào ") + d.optString("name") + I18n.t("! Chọn tên đăng nhập cho Kinnect."), 16, TEXT));
      EditText username = input(content, I18n.t("Tên đăng nhập"), d.optString("suggestedUsername"), false);
      CheckBox agree = new CheckBox(this);
      agree.setText(I18n.t("Tôi xác nhận mình đủ 18 tuổi và tôn trọng quy tắc cộng đồng."));
      agree.setTextColor(MUTED);
      content.addView(agree);
      content.addView(primary(I18n.t("Bắt đầu"), () -> api.call("POST", "/api/oauth/complete", json("ticket", ticket, "username", username.getText().toString(), "agree18", agree.isChecked()), (r, err, st) -> {
        if (err != null) { say(err); return; }
        me = r.optJSONObject("user");
        navigate("feed");
      })));
    });
  }

  // ----- Quên / đổi mật khẩu
  private void forgot() {
    shell("", false);
    subBack = () -> auth(false);
    content.addView(label(I18n.t("Khôi phục tài khoản"), WebDesign.TITLE, TEXT));
    final EditText identifier = input(content, I18n.t("Tên đăng nhập hoặc email khôi phục"), "", false);
    identifier.setSingleLine(true);
    final LinearLayout verification = column();
    verification.setVisibility(View.GONE);
    final EditText code = input(verification, I18n.t("Mã xác minh"), "", false);
    code.setInputType(InputType.TYPE_CLASS_NUMBER);
    code.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(6) });
    final EditText password = input(verification, I18n.t("Mật khẩu mới"), "", false);
    password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
    password.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(128) });
    final String[] challenge = { "" };
    final Button send = primary(I18n.t("Gửi mã"), () -> {});
    send.setOnClickListener(v -> {
      if (!send.isEnabled()) return;
      if (identifier.getText().toString().trim().isEmpty()) { identifier.setError(I18n.t("Nhập tên đăng nhập hoặc email")); return; }
      send.setEnabled(false);
      request("POST", "/api/recovery/reset/start", json("identifier", identifier.getText().toString().trim().toLowerCase(Locale.ROOT)), result -> {
        challenge[0] = result.optString("challengeId"); verification.setVisibility(View.VISIBLE); send.setText(I18n.t("Gửi lại mã"));
        identifier.setEnabled(false); say(result.optString("message")); code.requestFocus();
      }, () -> send.setEnabled(true));
    });
    content.addView(send); content.addView(verification);
    final Button reset = primary(I18n.t("Đặt lại mật khẩu"), () -> {});
    verification.addView(reset);
    reset.setOnClickListener(v -> {
      if (!reset.isEnabled()) return;
      if (code.length() != 6) { code.setError(I18n.t("Nhập mã 6 chữ số")); return; }
      if (password.length() < 6) { password.setError(I18n.t("Mật khẩu cần ít nhất 6 ký tự")); return; }
      reset.setEnabled(false);
      request("POST", "/api/recovery/reset/finish", json("challengeId", challenge[0], "code", code.getText().toString(), "password", password.getText().toString()), result -> {
        auth(false); say(result.optString("message", I18n.t("Đã đặt lại mật khẩu")));
      }, () -> reset.setEnabled(true));
    });
    content.addView(button(I18n.t("Dùng tài khoản khác"), () -> forgot()));
    content.addView(button(I18n.t("Nhờ quản trị viên hỗ trợ"), () -> forgotSupport()));
    content.addView(button(I18n.t("Về đăng nhập"), () -> auth(false)));
  }

  private void forgotSupport() {
    shell(I18n.t("Quên mật khẩu"), false);
    subBack = () -> forgot();
    content.addView(label(I18n.t("Để lại thông tin liên hệ, quản trị viên sẽ cấp mật khẩu tạm cho bạn."), 15, MUTED));
    EditText username = input(content, I18n.t("Tên đăng nhập"), "", false),
      contact = input(content, I18n.t("Email, số điện thoại hoặc Zalo"), "", false),
      note = input(content, I18n.t("Ghi chú (không bắt buộc)"), "", true);
    content.addView(primary(I18n.t("Gửi yêu cầu"), () -> request("POST", "/api/password-reset", json("username", username.getText().toString(), "contact", contact.getText().toString(), "note", note.getText().toString()), d -> {
      content.removeAllViews();
      content.addView(label("✓ " + d.optString("message"), 17, TEXT));
      content.addView(primary(I18n.t("Về đăng nhập"), () -> auth(false)));
    })));
    content.addView(button(I18n.t("Quay lại"), () -> auth(false)));
  }

  private void changePassword() {
    if (me == null) return;
    LinearLayout box = column();
    box.setPadding(dp(20), dp(8), dp(20), 0);
    EditText current = new EditText(this), next = new EditText(this);
    current.setHint(I18n.t("Mật khẩu hiện tại"));
    next.setHint(I18n.t("Mật khẩu mới (tối thiểu 6 ký tự)"));
    current.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
    next.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
    box.addView(current);
    box.addView(next);
    new Sheet(this).setTitle(I18n.t("Đổi mật khẩu")).setView(box).setPositiveButton(I18n.t("Lưu"), (d, w) ->
      api.call("POST", "/api/me/password", json("current", current.getText().toString(), "next", next.getText().toString()), (r, e, s) ->
        Toast.makeText(this, e != null ? e : I18n.t("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất."), Toast.LENGTH_LONG).show())
    ).setNegativeButton(I18n.t("Hủy"), null).show();
  }

  // ----- Hồ sơ: số liệu, người theo dõi, bài viết
  private void stats(JSONObject u, LinearLayout parent) {
    final LinearLayout r = row();
    r.setPadding(0, dp(10), 0, dp(10));
    parent.addView(r);
    request("GET", "/api/users/" + u.optString("id") + "/stats", null, d -> {
      String[][] items = { { String.valueOf(d.optInt("posts")), "bài viết", "" }, { String.valueOf(d.optInt("followers")), "người theo dõi", "followers" }, { String.valueOf(d.optInt("following")), "đang theo dõi", "following" } };
      for (final String[] it : items) {
        LinearLayout c = column();
        c.setGravity(Gravity.CENTER);
        TextView n = label(it[0], 18, TEXT);
        n.setTypeface(null, Typeface.BOLD);
        n.setGravity(Gravity.CENTER);
        n.setPadding(0, 0, 0, 0);
        TextView l = label(I18n.t(it[1]), 11, MUTED);
        l.setGravity(Gravity.CENTER);
        l.setPadding(0, 0, 0, 0);
        c.addView(n);
        c.addView(l);
        if (!it[2].isEmpty()) c.setOnClickListener(v -> connections(u, it[2], it[1].substring(0, 1).toUpperCase(Locale.ROOT) + it[1].substring(1)));
        r.addView(c, new LinearLayout.LayoutParams(0, -2, 1));
      }
    });
  }

  private void connections(JSONObject u, String kind, String title) {
    shell(title, true);
    request("GET", "/api/users/" + u.optString("id") + "/" + kind, null, d -> {
      JSONArray users = d.optJSONArray("users");
      if (users == null || users.length() == 0) content.addView(label(I18n.t("Chưa có ai."), 15, MUTED));
      for (int i = 0; users != null && i < users.length(); i++) {
        final JSONObject p = users.optJSONObject(i);
        inboxRow(content, p, p.optString("name"), "@" + p.optString("username"), 0, () -> person(p));
      }
    });
  }

  private void userPosts(JSONObject u) {
    shell(u.optString("name"), true);
    request("GET", "/api/posts?user=" + u.optString("id"), null, d -> posts(d.optJSONArray("posts"), "Chưa có bài viết."));
  }

  // ----- Danh sách bài viết dùng chung
  private void posts(JSONArray posts, String empty) {
    if (posts == null || posts.length() == 0) content.addView(emptyBlock("newspaper",I18n.t("Chưa có bài viết"),empty.contains(I18n.t("đầu tiên"))?I18n.t("Hãy là người đầu tiên chia sẻ."):I18n.t("Bài viết sẽ hiển thị tại đây.")));
    for (int i = 0; posts != null && i < posts.length(); i++) postCard(posts.optJSONObject(i));
  }

  private void postCard(final JSONObject p) {
    postCard(p, "");
  }

  private void postCard(final JSONObject p, final String commentFocus) {
    if (getSharedPreferences("kinnect_feed", 0).getStringSet("hidden:" + me.optString("id"), Collections.emptySet()).contains(p.optString("id"))) {
      LinearLayout hidden = card(); hidden.addView(label(I18n.t("Đã ẩn bài viết"), 13, MUTED));
      hidden.addView(button(I18n.t("Hoàn tác"), () -> {
        Set<String> ids = new HashSet<>(getSharedPreferences("kinnect_feed", 0).getStringSet("hidden:" + me.optString("id"), Collections.emptySet()));
        ids.remove(p.optString("id")); getSharedPreferences("kinnect_feed", 0).edit().putStringSet("hidden:" + me.optString("id"), ids).apply(); refreshPage();
      }));
      return;
    }
    final JSONObject author = p.optJSONObject("author");
    final boolean mine = p.optString("user_id").equals(me.optString("id"));
    LinearLayout c = card();
    c.setPadding(dp(14), dp(12), dp(14), dp(4));
    LinearLayout head = row();
    avatar(author, head, 40);
    LinearLayout who = column();
    who.setPadding(dp(10), 0, 0, 0);
    TextView name = label(author.optString("name"), 15, TEXT);
    name.setTypeface(null, Typeface.BOLD);
    name.setPadding(0, 0, 0, 0);
    who.addView(name);
    LinearLayout meta = row();
    meta.addView(label(ago(p.optLong("created")) + " · ", 12, MUTED));
    meta.addView(icon(p.optString("visibility").equals("followers") ? "profile" : "globe", 12, MUTED), new LinearLayout.LayoutParams(dp(12), dp(12)));
    meta.addView(label(p.optString("visibility").equals("followers") ? I18n.t(" Người theo dõi") : I18n.t(" Mọi thành viên"), 12, MUTED));
    who.addView(meta);
    head.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
    who.setOnClickListener(v -> person(author));
    ImageView more = icon("more", 22, MUTED);
    more.setPadding(dp(8), dp(8), dp(8), dp(8));
    more.setContentDescription(I18n.t("Thêm thao tác"));
    more.setOnClickListener(v -> postOptions(p, mine, c));
    head.addView(more, new LinearLayout.LayoutParams(dp(40), dp(40)));
    c.addView(head);
    if (!p.optString("body").isEmpty()) {
      TextView body = label(p.optString("body"), 14, TEXT);
      body.setPadding(0, dp(8), 0, dp(4));
      body.setLineSpacing(0, 1.6f);
      c.addView(body);
    }
    JSONObject media = p.optJSONObject("media");
    if (media != null) mediaView(media, c);
    LinearLayout stats = row();
    stats.setPadding(0, dp(10), 0, dp(10));
    final TextView reactSummary = label(reactionSummary(p), 13, MUTED);
    reactSummary.setOnClickListener(v -> { if (p.optInt("likes") > 0) reactorsSheet(p.optString("id")); });
    reactSummary.setContentDescription(I18n.t("Xem ai đã bày tỏ cảm xúc"));
    stats.addView(reactSummary, new LinearLayout.LayoutParams(0, -2, 1));
    final TextView commentCount = label(p.optInt("comments") + I18n.t(" bình luận"), 13, MUTED);
    stats.addView(commentCount);
    c.addView(stats);
    c.addView(divider());
    LinearLayout actions = row();
    String mineReaction = p.isNull("myReaction") ? "" : p.optString("myReaction");
    String glyph = null;
    for (String[] r : REACTIONS) if (r[0].equals(mineReaction)) glyph = r[1];
    final LinearLayout react = actionButton(glyph == null ? "smile" : null, glyph, glyph == null ? I18n.t("Cảm xúc") : reactionName(mineReaction), !mineReaction.isEmpty());
    react.setTag(reactSummary);
    react.setOnClickListener(v -> request(p.optBoolean("liked") ? "DELETE" : "POST", "/api/posts/" + p.optString("id") + "/like", p.optBoolean("liked") ? json() : json("reaction", "like"), d -> refreshReaction(p, react, d)));
    react.setOnLongClickListener(v -> {
      reactionBar(v, w ->
        request("POST", "/api/posts/" + p.optString("id") + "/like", json("reaction", REACTIONS[w][0]), r -> refreshReaction(p, react, r)));
      return true;
    });
    actions.addView(react, new LinearLayout.LayoutParams(0, dp(44), 1));
    LinearLayout comment = actionButton("comment", null, I18n.t("Bình luận"), false);
    final LinearLayout thread = column();
    thread.setVisibility(View.GONE);
    thread.setTag(commentCount);
    final View.OnClickListener toggleComments = v -> {
      boolean open = thread.getVisibility() == View.VISIBLE;
      thread.setVisibility(open ? View.GONE : View.VISIBLE);
      if (!open) inlineComments(p, thread, true);
    };
    comment.setOnClickListener(toggleComments);
    commentCount.setOnClickListener(toggleComments);
    commentCount.setContentDescription(I18n.t("Xem bình luận"));
    actions.addView(comment, new LinearLayout.LayoutParams(0, dp(44), 1));
    LinearLayout share = actionButton("send", null, I18n.t("Chia sẻ"), false);
    share.setOnClickListener(v -> sharePost(p));
    actions.addView(share, new LinearLayout.LayoutParams(0, dp(44), 1));
    for(int i=0;i<actions.getChildCount();i++){LinearLayout action=(LinearLayout)actions.getChildAt(i);View caption=action.getChildAt(action.getChildCount()-1);if(caption instanceof TextView)((TextView)caption).setTextSize(12);}
    LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(-1, -2);
    ap.setMargins(0, dp(4), 0, dp(4));
    c.addView(actions, ap);
    c.addView(thread);
    if (!commentFocus.isEmpty()) { thread.setVisibility(View.VISIBLE); inlineComments(p, thread, false, commentFocus); }
  }

  private String reactionName(String key) {
    switch (key) {
      case "love": return "Yêu thích";
      case "haha": return "Haha";
      case "wow": return "Wow";
      case "sad": return "Buồn";
      case "angry": return "Phẫn nộ";
      default: return "Thích";
    }
  }

  private String reactionSummary(JSONObject p) {
    StringBuilder glyphs = new StringBuilder();
    JSONObject counts = p.optJSONObject("reactions");
    int shown = 0;
    for (String[] r : REACTIONS) if (counts != null && counts.optInt(r[0]) > 0 && shown < 3) { glyphs.append(r[1]); shown++; }
    return (glyphs.length() > 0 ? glyphs + " " : "") + p.optInt("likes") + " cảm xúc";
  }

  // Danh sách người thả cảm xúc như web: tab Tất cả + từng loại.
  private void reactorsSheet(final String postId) {
    request("GET", "/api/posts/" + postId + "/reactions", null, data -> {
      final JSONArray users = data.optJSONArray("users");
      if (users == null || users.length() == 0) return;
      final LinearLayout box = column();
      final LinearLayout tabs = row();
      final LinearLayout list = column();
      final Map<String, Integer> counts = new LinkedHashMap<>();
      for (int i = 0; i < users.length(); i++) { String k = users.optJSONObject(i).optString("reaction"); counts.put(k, counts.containsKey(k) ? counts.get(k) + 1 : 1); }
      final List<String> keys = new ArrayList<>();
      keys.add("all");
      keys.addAll(counts.keySet());
      final Runnable[] render = new Runnable[1];
      final String[] selected = { "all" };
      render[0] = () -> {
        tabs.removeAllViews();
        for (final String k : keys) {
          String glyph = "";
          for (String[] r : REACTIONS) if (r[0].equals(k)) glyph = r[1];
          boolean on = selected[0].equals(k);
          TextView tab = label(k.equals("all") ? I18n.t("Tất cả ") + users.length() : glyph + " " + counts.get(k), 14, on ? ACCENT : MUTED);
          tab.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
          tab.setPadding(dp(12), dp(10), dp(12), dp(10));
          if (on) tab.setBackground(background(PRIMARY_SOFT, 99));
          tab.setOnClickListener(v -> { selected[0] = k; render[0].run(); });
          tabs.addView(tab);
        }
        list.removeAllViews();
        for (int i = 0; i < users.length(); i++) {
          final JSONObject u = users.optJSONObject(i);
          if (!selected[0].equals("all") && !selected[0].equals(u.optString("reaction"))) continue;
          LinearLayout r = row();
          r.setPadding(dp(4), dp(8), dp(4), dp(8));
          FrameLayout face = new FrameLayout(this);
          LinearLayout holder = new LinearLayout(this);
          avatar(u, holder, 42);
          face.addView(holder);
          String glyph = "";
          for (String[] x : REACTIONS) if (x[0].equals(u.optString("reaction"))) glyph = x[1];
          TextView mark = label(glyph, 13, TEXT);
          mark.setPadding(dp(1), dp(1), dp(1), dp(1));
          mark.setBackground(background(CARD, 99));
          face.addView(mark, new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.END));
          r.addView(face, new LinearLayout.LayoutParams(dp(48), dp(46)));
          LinearLayout who = column();
          who.setPadding(dp(10), 0, 0, 0);
          TextView n = label(u.optString("name"), 15, TEXT);
          n.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
          who.addView(n);
          who.addView(label("@" + u.optString("username"), 12, MUTED));
          r.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
          r.setOnClickListener(v -> person(u));
          list.addView(r);
        }
      };
      render[0].run();
      box.addView(hscroll(tabs));
      ScrollView scroll = new ScrollView(this);
      scroll.addView(list);
      box.addView(scroll, new LinearLayout.LayoutParams(-1, Math.min(getResources().getDisplayMetrics().heightPixels / 2, dp(64) * users.length() + dp(16))));
      new Sheet(this).setTitle(I18n.t("Cảm xúc")).setView(box).show();
    });
  }

  private void postOptions(final JSONObject post, boolean mine, final LinearLayout card) {
    List<String> labels = new ArrayList<>();
    List<Runnable> actions = new ArrayList<>();
    if (mine) {
      labels.add(I18n.t("Chỉnh sửa bài viết"));
      actions.add(() -> {
        LinearLayout form = column();
        EditText body = input(form, I18n.t("Bạn đang nghĩ gì?"), post.optString("body"), true);
        new Sheet(this).setTitle(I18n.t("Chỉnh sửa bài viết")).setView(form).setPositiveButton(I18n.t("Lưu"), (d, w) -> request("PATCH", "/api/posts/" + post.optString("id"), json("body", body.getText().toString()), result -> refreshPage())).setNegativeButton(I18n.t("Huỷ"), null).show();
      });
      labels.add(I18n.t("Thay đổi đối tượng xem"));
      actions.add(() -> new Sheet(this).setTitle(I18n.t("Ai có thể xem bài viết?")).setItemIcons(new String[]{"globe","users_round"}).setItems(new String[] { I18n.t("Mọi thành viên"), I18n.t("Người theo dõi") }, (d, w) -> request("PATCH", "/api/posts/" + post.optString("id"), json("visibility", w == 0 ? "public" : "followers"), result -> refreshPage())).show());
    }
    labels.add(I18n.t("Ẩn bài viết"));
    actions.add(() -> {
      Set<String> hidden = new HashSet<>(getSharedPreferences("kinnect_feed", 0).getStringSet("hidden:" + me.optString("id"), Collections.emptySet()));
      hidden.add(post.optString("id"));
      getSharedPreferences("kinnect_feed", 0).edit().putStringSet("hidden:" + me.optString("id"), hidden).apply();
      card.removeAllViews();
      card.addView(label(I18n.t("Đã ẩn bài viết"), 13, MUTED));
      card.addView(button(I18n.t("Hoàn tác"), () -> {
        hidden.remove(post.optString("id"));
        getSharedPreferences("kinnect_feed", 0).edit().putStringSet("hidden:" + me.optString("id"), hidden).apply();
        refreshPage();
      }));
    });
    labels.add(mine ? I18n.t("Xoá bài viết") : I18n.t("Báo cáo bài viết"));
    actions.add(() -> { if (mine) confirm(I18n.t("Xoá bài viết?"), () -> request("DELETE", "/api/posts/" + post.optString("id"), json(), result -> refreshPage())); else report("post", post.optString("id")); });
    new Sheet(this).setTitle(I18n.t("Tùy chọn bài viết")).setItems(labels.toArray(new String[0]),(dialog,index)->actions.get(index).run()).show();
  }

  private void sharePost(final JSONObject post) {
    final String url = "https://app.kinnect.io.vn/?s=postDetail&post=" + post.optString("id");
    new Sheet(this).setTitle(I18n.t("Chia sẻ bài viết")).setItems(new String[] { I18n.t("Gửi cho bạn bè"), I18n.t("Sao chép liên kết"), I18n.t("Chia sẻ qua ứng dụng khác") }, (dialog, choice) -> {
      if (choice == 1) {
        ((android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("Kinnect", url));
        say(I18n.t("Đã sao chép liên kết."));
      } else if (choice == 2) {
        Intent send = new Intent(Intent.ACTION_SEND); send.setType("text/plain"); send.putExtra(Intent.EXTRA_TEXT, url);
        startActivity(Intent.createChooser(send, I18n.t("Chia sẻ bài viết")));
      } else request("GET", "/api/friends", null, data -> {
        JSONArray users = data.optJSONArray("users");
        if (users == null || users.length() == 0) { say(I18n.t("Bạn chưa có bạn bè để chia sẻ.")); return; }
        String[] names = new String[users.length()];
        for (int i = 0; i < names.length; i++) names[i] = users.optJSONObject(i).optString("name");
        new Sheet(this).setTitle(I18n.t("Gửi cho bạn bè")).setItems(names, (d, w) -> request("POST", "/api/users/" + users.optJSONObject(w).optString("id") + "/messages", json("body", url), result -> say(I18n.t("Đã chia sẻ bài viết.")))).show();
      });
    }).show();
  }

  private LinearLayout actionButton(String iconName, String emoji, String text, boolean active) {
    LinearLayout b = row();
    b.setGravity(Gravity.CENTER);
    if (emoji != null && iconName == null) {
      TextView e = label(emoji, 17, TEXT);
      e.setPadding(0, 0, 0, 0);
      b.addView(e);
    } else {
      ImageView i = icon(iconName, 20, TEXT);
      b.addView(i, new LinearLayout.LayoutParams(dp(20), dp(20)));
    }
    TextView t = label(text, 14, active ? ACCENT : TEXT);
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    t.setPadding(dp(8), 0, 0, 0);
    b.addView(t);
    b.setBackground(pressable(active ? PRIMARY_SOFT : CARD, 12));
    b.setContentDescription(text);
    return b;
  }

  private void refreshReaction(JSONObject p, LinearLayout react, JSONObject d) {
    try {
      p.put("liked", d.optBoolean("liked"));
      p.put("likes", d.optInt("likes"));
      p.put("myReaction", d.isNull("myReaction") ? "" : d.optString("myReaction"));
      if (d.optJSONObject("reactions") != null) p.put("reactions", d.optJSONObject("reactions"));
    } catch (JSONException ignored) {}
    String key = p.optString("myReaction");
    String glyph = null;
    for (String[] r : REACTIONS) if (r[0].equals(key)) glyph = r[1];
    boolean on = glyph != null;
    react.removeAllViews();
    LinearLayout fresh = actionButton(on ? null : "smile", glyph, on ? reactionName(key) : I18n.t("Cảm xúc"), on);
    while (fresh.getChildCount() > 0) { View v = fresh.getChildAt(0); fresh.removeViewAt(0); react.addView(v); }
    react.setBackground(fresh.getBackground());
    react.setContentDescription(fresh.getContentDescription());
    if (react.getTag() instanceof TextView) ((TextView) react.getTag()).setText(reactionSummary(p));
  }


  private void postComments(final JSONObject p) {
    remember("comments:" + p.optString("id"), () -> postComments(p));
    shell(I18n.t("Bình luận"), true);
    comments("/api/posts/" + p.optString("id"), () -> postComments(p), () -> navigate("feed"), "Quay lại bảng tin");
  }

  // ----- Ảnh / video trong bài viết, tin, tin nhắn
  private void mediaView(JSONObject media, LinearLayout parent) {
    String url = media.optString("url");
    if (media.optString("kind").equals("video")) {
      final VideoView video = new VideoView(this);
      mediaVideos.add(video);
      Map<String, String> headers = new HashMap<>();
      headers.put("Cookie", api.jar());
      video.setVideoURI(android.net.Uri.parse(server() + url), headers);
      video.setOnPreparedListener(mp -> { mp.setLooping(true); video.seekTo(1); });
      video.setOnClickListener(v -> { if (video.isPlaying()) video.pause(); else if(!mediaCallBlocked)video.start(); });
      MediaController controls = new MediaController(this);
      controls.setAnchorView(video); video.setMediaController(controls);
      video.setContentDescription(I18n.t("Video · Phát, tạm dừng và tua"));
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, dp(360));
      lp.setMargins(0, dp(8), 0, dp(4));
      parent.addView(video, lp);
      return;
    }
    final ImageView image = new ImageView(this);
    image.setAdjustViewBounds(true);
    image.setScaleType(ImageView.ScaleType.FIT_CENTER);
    image.setBackground(background(SOFT, 14));
    image.setClipToOutline(true);
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.setMargins(0, dp(8), 0, dp(4));
    parent.addView(image, lp);
    final Runnable back = currentPage == null ? () -> navigate(tab) : currentPage;
    image.setContentDescription(I18n.t("Xem ảnh đầy đủ"));
    image.setOnClickListener(v -> openPhoto(url, back));
    api.image(url, bytes -> {
      if (bytes == null || isDestroyed()) return;
      BitmapFactory.Options o = new BitmapFactory.Options();
      o.inJustDecodeBounds = true;
      BitmapFactory.decodeByteArray(bytes, 0, bytes.length, o);
      o.inSampleSize = Math.max(1, Math.max(o.outWidth, o.outHeight) / 1280);
      o.inJustDecodeBounds = false;
      Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, o);
      if (b != null) image.setImageBitmap(b);
    });
  }

  private void openPhoto(String url, final Runnable back) {
    remember("photo:" + url, () -> openPhoto(url, back));
    shell("", false);
    toolbar.setVisibility(View.GONE);
    if (root.getChildCount() > 1) root.getChildAt(1).setVisibility(View.GONE);
    root.setBackgroundColor(0xff000000);
    getWindow().setStatusBarColor(0xff000000);
    getWindow().setNavigationBarColor(0xff000000);
    content.setPadding(0, 0, 0, 0);
    FrameLayout stage = new FrameLayout(this);
    ImageView image = new ImageView(this);
    image.setScaleType(ImageView.ScaleType.FIT_CENTER);
    stage.addView(image, new FrameLayout.LayoutParams(-1, -1));
    loadImage(url, image);
    FrameLayout close = new FrameLayout(this);
    close.setBackground(background(0x66000000, 99));
    close.addView(icon("x", 20, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    close.setContentDescription(I18n.t("Đóng"));
    close.setOnClickListener(v -> back.run());
    FrameLayout.LayoutParams cp = new FrameLayout.LayoutParams(dp(40), dp(40), Gravity.TOP | Gravity.START);
    cp.setMargins(dp(12), dp(12), 0, 0);
    stage.addView(close, cp);
    content.addView(stage, new LinearLayout.LayoutParams(-1, getResources().getDisplayMetrics().heightPixels - dp(60)));
  }

  private void openAttachment(JSONObject file) {
    if (file.optString("kind").equals("image") || file.optString("kind").equals("video")) {
      final Runnable back = currentPage == null ? () -> navigate("inbox") : currentPage;
      remember("attachment:" + file.optString("url"), () -> openAttachment(file));
      shell(file.optString("name"), true);
      subBack = back;
      mediaView(file, content);
      content.addView(button(I18n.t("Quay lại"), () -> back.run()));
      return;
    }
    pendingDownload = file.optString("url");
    Intent save = new Intent(Intent.ACTION_CREATE_DOCUMENT);
    save.addCategory(Intent.CATEGORY_OPENABLE);
    String type = file.optString("type", "application/octet-stream");
    save.setType(type.isEmpty() ? "application/octet-stream" : type);
    save.putExtra(Intent.EXTRA_TITLE, file.optString("name", "Kinnect-file"));
    try { startActivityForResult(save, 309); }
    catch (Exception error) { pendingDownload = ""; say(I18n.t("Chưa mở được trình lưu tệp.")); }
  }
  // ----- Tin 24 giờ
  private void stories() {
    final LinearLayout strip = row();
    strip.setGravity(Gravity.TOP);
    strip.setPadding(0, dp(6), 0, dp(6));
    strip.addView(storyBubble(me, "Tạo tin", true, () -> createStory()));
    LinearLayout storyCard = card();
    storyCard.setPadding(dp(12), dp(10), dp(12), dp(10));
    storyCard.addView(hscroll(strip));
    request("GET", "/api/stories", null, d -> {
      final JSONArray stories = d.optJSONArray("stories");
      Set<String> authors = new HashSet<>();
      for (int i = 0; stories != null && i < stories.length(); i++) {
        if (!authors.add(stories.optJSONObject(i).optJSONObject("author").optString("id"))) continue;
        final int index = i;
        JSONObject st = stories.optJSONObject(i);
        strip.addView(storyBubble(st.optJSONObject("author"), st.optJSONObject("author").optString("name"), false, () -> story(stories, index)));
      }
    });
  }

  private LinearLayout storyBubble(JSONObject u, String caption, boolean mine, Runnable open) {
    LinearLayout b = column();
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    FrameLayout ring = new FrameLayout(this);
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { ACCENT, ACCENT });
    g.setShape(GradientDrawable.OVAL);
    ring.setBackground(g);
    FrameLayout inner = new FrameLayout(this);
    GradientDrawable w = new GradientDrawable();
    w.setShape(GradientDrawable.OVAL);
    w.setColor(CARD);
    inner.setBackground(w);
    LinearLayout holder = new LinearLayout(this);
    avatar(u, holder, 50);
    inner.addView(holder, new FrameLayout.LayoutParams(dp(50), dp(50), Gravity.CENTER));
    ring.addView(inner, new FrameLayout.LayoutParams(dp(54), dp(54), Gravity.CENTER));
    FrameLayout bubbleBox = new FrameLayout(this);
    bubbleBox.addView(ring, new FrameLayout.LayoutParams(dp(60), dp(60), Gravity.CENTER));
    if (mine) {
      FrameLayout plus = new FrameLayout(this);
      GradientDrawable pb = background(ACCENT, 99);
      pb.setStroke(dp(2), CARD);
      plus.setBackground(pb);
      plus.addView(icon("plus", 12, WHITE), new FrameLayout.LayoutParams(dp(12), dp(12), Gravity.CENTER));
      bubbleBox.addView(plus, new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.BOTTOM | Gravity.END));
    }
    b.addView(bubbleBox, new LinearLayout.LayoutParams(dp(62), dp(62)));
    TextView t = label(caption, 12, mine ? ACCENT : TEXT);
    t.setSingleLine(true);
    t.setEllipsize(android.text.TextUtils.TruncateAt.END);
    t.setGravity(Gravity.CENTER);
    t.setPadding(0, dp(6), 0, 0);
    b.addView(t, new LinearLayout.LayoutParams(dp(70), -2));
    b.setOnClickListener(v -> open.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(dp(70), -2);
    p.rightMargin = dp(10);
    b.setLayoutParams(p);
    return b;
  }

  // Xem tin toàn màn: thanh tiến trình, avatar · tên · thời gian, chạm trái/phải để chuyển, tự chuyển sau 6 giây.
  private void story(final JSONArray stories, final int index) {
    if (index < 0) { story(stories, 0); return; }
    if (index >= stories.length()) { navigate("feed"); return; }
    final JSONObject st = stories.optJSONObject(index);
    shell("", false);
    root.removeAllViews();
    root.setBackgroundColor(0xff000000);
    getWindow().setStatusBarColor(0xff000000);
    getWindow().setNavigationBarColor(0xff000000);
    getWindow().getDecorView().setSystemUiVisibility(0);
    FrameLayout stage = new FrameLayout(this);
    root.addView(stage, new LinearLayout.LayoutParams(-1, 0, 1));
    JSONObject media = st.optJSONObject("media");
    final int generation = screen;
    final VideoView[] storyPlayer = { null };
    final boolean[] paused = { false };
    long duration = 6000;
    if (media != null && media.optString("kind").equals("video")) {
      final VideoView video = new VideoView(this);
      mediaVideos.add(video);
      storyPlayer[0] = video;
      Map<String, String> headers = new HashMap<>();
      headers.put("Cookie", api.jar());
      video.setVideoURI(android.net.Uri.parse(server() + media.optString("url")), headers);
      video.setOnPreparedListener(mp -> {
        if (generation != screen) return;
        if (stopped) resumeVideos.add(video);
        else if (!paused[0]) if(!mediaCallBlocked)video.start();
      });
      video.setOnCompletionListener(mp -> { if (generation == screen && !stopped && !paused[0]) story(stories, index + 1); });
      stage.addView(video, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
      duration = 0;
    } else if (media != null) {
      final ImageView img = new ImageView(this);
      img.setScaleType(ImageView.ScaleType.FIT_CENTER);
      stage.addView(img, new FrameLayout.LayoutParams(-1, -1));
      api.image(media.optString("url"), bytes -> { if (bytes != null && generation == screen) { Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length); if (b != null) img.setImageBitmap(b); } });
    } else {
      stage.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { ACCENT, ACCENT }));
    }
    if (!st.optString("body").isEmpty()) {
      TextView body = label(st.optString("body"), media == null ? 26 : 17, WHITE);
      body.setTypeface(null, Typeface.BOLD);
      body.setGravity(Gravity.CENTER);
      body.setShadowLayer(6, 0, 1, 0xcc000000);
      body.setPadding(dp(24), dp(10), dp(24), dp(10));
      if (media != null) body.setBackground(background(0x55000000, 14));
      FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-2, -2, media == null ? Gravity.CENTER : Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
      bp.setMargins(dp(20), 0, dp(20), dp(60));
      stage.addView(body, bp);
    }
    // Chạm nửa trái: tin trước · nửa phải: tin sau
    View left = new View(this), right = new View(this);
    left.setOnClickListener(v -> story(stories, index - 1));
    right.setOnClickListener(v -> story(stories, index + 1));
    LinearLayout taps = row();
    taps.addView(left, new LinearLayout.LayoutParams(0, -1, 1));
    taps.addView(right, new LinearLayout.LayoutParams(0, -1, 2));
    stage.addView(taps, new FrameLayout.LayoutParams(-1, -1));
    LinearLayout top = column();
    top.setPadding(dp(10), dp(8), dp(10), 0);
    LinearLayout bars = row();
    for (int i = 0; i < stories.length(); i++) {
      View bar = new View(this);
      bar.setBackground(background(i < index ? WHITE : i == index ? 0xddffffff : 0x55ffffff, 99));
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(3), 1);
      lp.setMargins(dp(2), 0, dp(2), 0);
      bars.addView(bar, lp);
    }
    top.addView(bars);
    LinearLayout who = row();
    who.setPadding(0, dp(10), 0, 0);
    JSONObject author = st.optJSONObject("author");
    avatar(author, who, 36);
    TextView name = label("  " + author.optString("name"), 15, WHITE);
    name.setTypeface(null, Typeface.BOLD);
    name.setShadowLayer(4, 0, 1, 0xcc000000);
    who.addView(name);
    TextView when = label("  " + ago(st.optLong("created")), 13, 0xccffffff);
    when.setShadowLayer(4, 0, 1, 0xcc000000);
    who.addView(when, new LinearLayout.LayoutParams(0, -2, 1));
    ImageView close = icon("close", 26, WHITE);
    close.setPadding(dp(8), dp(8), dp(8), dp(8));
    close.setContentDescription(I18n.t("Đóng tin"));
    close.setOnClickListener(v -> navigate("feed"));
    who.addView(close, new LinearLayout.LayoutParams(dp(44), dp(44)));
    top.addView(who);
    stage.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    final long interval = duration;
    final Runnable advance = () -> { if (generation == screen && !stopped && !paused[0]) story(stories, index + 1); };
    if (interval > 0) {
      resumeStory = () -> { if (generation == screen && !paused[0] && !mediaCallBlocked) { handler.removeCallbacks(advance); handler.postDelayed(advance, interval); } };
      resumeStory.run();
    }
    if (!author.optString("id").equals(me.optString("id"))) {
      request("POST", "/api/stories/" + st.optString("id") + "/view", json(), ignored -> {});
    } else {
      LinearLayout viewers = row(); viewers.setPadding(dp(12), 0, dp(12), 0);
      viewers.setBackground(background(0x77000000, 99));
      viewers.addView(icon("eye", 20, WHITE), new LinearLayout.LayoutParams(dp(20), dp(20)));
      final TextView count = label(" " + st.optInt("viewCount"), 13, WHITE); viewers.addView(count);
      viewers.setContentDescription(I18n.t("Xem người đã xem tin"));
      viewers.setOnClickListener(v -> {
        paused[0] = true; handler.removeCallbacks(advance);
        if (storyPlayer[0] != null) storyPlayer[0].pause();
        final Runnable resume = () -> {
          paused[0] = false;
          if (generation != screen || stopped) return;
          if (storyPlayer[0] != null) if(!mediaCallBlocked)storyPlayer[0].start();
          else if (resumeStory != null) resumeStory.run();
        };
        final boolean[] opened = { false };
        request("GET", "/api/stories/" + st.optString("id") + "/viewers", null, result -> {
          JSONArray users = result.optJSONArray("viewers");
          count.setText(" " + result.optInt("count"));
          LinearLayout list = column();
          final Dialog[] dialog = { null };
          for (int i = 0; users != null && i < users.length(); i++) {
            final JSONObject u = users.optJSONObject(i);
            LinearLayout row = row(); row.setPadding(dp(4), dp(6), dp(4), dp(6));
            avatar(u, row, 40);
            TextView name2 = label(u.optString("name"), 14, TEXT); name2.setPadding(dp(10), 0, 0, 0);
            row.addView(name2, new LinearLayout.LayoutParams(0, -2, 1));
            row.setOnClickListener(view -> { dialog[0].dismiss(); person(u); }); list.addView(row);
          }
          if (users == null || users.length() == 0) list.addView(label(I18n.t("Chưa có người xem"), 14, MUTED));
          ScrollView scroll = new ScrollView(this); scroll.addView(list);
          scroll.setLayoutParams(new LinearLayout.LayoutParams(-1, Math.min(dp(360), Math.max(dp(56), (users == null ? 0 : users.length()) * dp(56)))));
          dialog[0] = new Sheet(this).setTitle(I18n.t("Người xem tin")).setView(scroll).setNegativeButton(I18n.t("Đóng"), null).show();
          opened[0] = true; dialog[0].setOnDismissListener(ignored -> resume.run());
        }, () -> { if (!opened[0]) resume.run(); });
      });
      FrameLayout.LayoutParams vp = new FrameLayout.LayoutParams(-2, dp(44), Gravity.BOTTOM | Gravity.START);
      vp.setMargins(dp(16), 0, 0, dp(12)); stage.addView(viewers, vp);
    }
  }

  // ----- Tin tức
  private void inboxRow(LinearLayout parent, JSONObject u, String title, String subtitle, int unread, Runnable open) {
    LinearLayout r = row();
    r.setPadding(dp(12), dp(10), dp(12), dp(10));
    r.setBackground(background(CARD, 16));
    if (u != null) avatar(u, r, 46);
    else {
      FrameLayout g = new FrameLayout(this);
      g.setBackground(background(PRIMARY_SOFT, 99));
      g.addView(icon("users_round", 22, ACCENT), new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
      r.addView(g, new LinearLayout.LayoutParams(dp(46), dp(46)));
    }
    LinearLayout t = column();
    t.setPadding(dp(12), 0, 0, 0);
    TextView n = label(title, 14, TEXT);
    n.setTypeface(null, unread > 0 ? Typeface.BOLD : Typeface.NORMAL);
    n.setSingleLine(true);
    TextView s2 = label(subtitle, 13, unread > 0 ? TEXT : MUTED);
    s2.setSingleLine(true);
    s2.setEllipsize(android.text.TextUtils.TruncateAt.END);
    t.addView(n);
    t.addView(s2);
    r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
    if (unread > 0) {
      TextView badge = label(String.valueOf(unread), 11, 0xffffffff);
      badge.setGravity(Gravity.CENTER);
      badge.setPadding(dp(7), 0, dp(7), 0);
      badge.setBackground(background(0xfff23663, 99));
      r.addView(badge, new LinearLayout.LayoutParams(-2, dp(22)));
    }
    r.setOnClickListener(v -> open.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.setMargins(0, dp(4), 0, dp(4));
    parent.addView(r, p);
  }

  private void createGroup() {
    request("GET", "/api/friends", null, data -> {
      final JSONArray users = new JSONArray();
      Set<String> seen = new HashSet<>();
      for (JSONArray set : new JSONArray[] { data.optJSONArray("users"), conversationUsers }) {
        for (int i = 0; set != null && i < set.length(); i++) {
          JSONObject user = set.optJSONObject(i);
          if (user != null && seen.add(user.optString("id"))) users.put(user);
        }
      }
      if (users.length() == 0) { say(I18n.t("Kết bạn hoặc bắt đầu một cuộc trò chuyện để tạo nhóm.")); return; }
      chooseGroupMembers(users);
    });
  }

  private void chooseGroupMembers(final JSONArray users) {
    final String[] names = new String[users.length()];
    final boolean[] chosen = new boolean[users.length()];
    for (int i = 0; i < names.length; i++) names[i] = users.optJSONObject(i).optString("name");
    final EditText name = new EditText(this);
    styleChatName(name);name.setHint(I18n.t("Tên nhóm"));
    new Sheet(this).setTitle(I18n.t("Chọn thành viên")).setMultiChoiceItems(names, chosen, (d, w, c) -> chosen[w] = c)
      .setPositiveButton(I18n.t("Tiếp"), (d, w) -> new Sheet(this).setTitle(I18n.t("Tên nhóm")).setView(chatNameWrap(name)).setPositiveButton(I18n.t("Tạo nhóm"), (d2, w2) -> {
        JSONArray ids = new JSONArray();
        for (int i = 0; i < chosen.length; i++) if (chosen[i]) ids.put(users.optJSONObject(i).optString("id"));
        request("POST", "/api/groups", json("name", name.getText().toString(), "members", ids), r -> groupChat(r.optJSONObject("group")));
      }).setNegativeButton(I18n.t("Hủy"), null).show())
      .setNegativeButton(I18n.t("Hủy"), null).show();
  }



  // ----- Chọn tệp: 300 ảnh/video bài viết · 303 tệp tin nhắn · 304 tin 24h · 305 nhạc (quản trị)
  private void pickFile(int code, String types) {
    Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    pick.addCategory(Intent.CATEGORY_OPENABLE);
    if (types.contains("|")) {
      pick.setType("*/*");
      pick.putExtra(Intent.EXTRA_MIME_TYPES, new String[] { "image/*", "video/*" });
    } else pick.setType(types);
    try { startActivityForResult(pick, code); } catch (Exception e) { say(I18n.t("Không mở được trình chọn tệp.")); }
  }

  private boolean preparingPostMedia = false;
  private static String mediaFailure(Exception error) {
    if (error instanceof SecurityException) return I18n.t("Không có quyền đọc tệp. Hãy chọn lại video từ Thư viện hoặc Tệp trên máy.");
    String message = error.getMessage();
    return message == null || message.trim().isEmpty() ? I18n.t("Không đọc được tệp đã chọn. Hãy tải tệp về máy và chọn lại.") : message;
  }

  private void preparePostMedia(final int code, final android.net.Uri uri) {
    if (preparingPostMedia) { say(I18n.t("Đang chuẩn bị ảnh/video, vui lòng chờ.")); return; }
    preparingPostMedia = true;
    final int generation = screen;
    say(I18n.t("Đang chuẩn bị ảnh/video…"));
    new Thread(() -> {
      try {
        final NativeMedia.Prepared selected = NativeMedia.read(this, uri, false);
        final String media = selected.dataUrl();
        final Bitmap preview;
        if (selected.video()) preview = null;
        else {
          BitmapFactory.Options options = new BitmapFactory.Options(); options.inJustDecodeBounds = true;
          BitmapFactory.decodeByteArray(selected.bytes, 0, selected.bytes.length, options);
          options.inSampleSize = 1;
          while (Math.max(options.outWidth, options.outHeight) / options.inSampleSize > 1080) options.inSampleSize *= 2;
          options.inJustDecodeBounds = false;
          preview = BitmapFactory.decodeByteArray(selected.bytes, 0, selected.bytes.length, options);
        }
        runOnUiThread(() -> {
          if (generation != screen || isDestroyed()) { if (preview != null) preview.recycle(); return; }
          preparingPostMedia = false;
          if (code == 300) {
            pendingMedia = media;
            if (attachButton != null) attachButton.setText(selected.video() ? I18n.t("✓ Đã chọn video") : I18n.t("✓ Đã chọn ảnh"));
            composeAttached(preview, selected.video());
          } else {
            EditText caption = new EditText(this); caption.setHint(I18n.t("Viết gì đó cho tin (không bắt buộc)"));
            new Sheet(this).setTitle(I18n.t("Đăng tin 24 giờ")).setView(caption).setPositiveButton(I18n.t("Đăng"), (d,w) -> {
              say(I18n.t("Đang đăng tin…"));
              request("POST", "/api/stories", json("body", caption.getText().toString(), "media", media), r -> { say(I18n.t("Đã đăng tin.")); navigate("feed"); });
            }).setNegativeButton(I18n.t("Hủy"), null).show();
          }
        });
      } catch (OutOfMemoryError error) {
        runOnUiThread(() -> { if (generation == screen) { preparingPostMedia = false; say(I18n.t("Thiết bị không đủ bộ nhớ để chuẩn bị tệp này.")); } });
      } catch (Exception error) {
        final String reason = mediaFailure(error);
        runOnUiThread(() -> { if (generation == screen) { preparingPostMedia = false; say(reason); } });
      }
    }, "kinnect-prepare-media").start();
  }

  private String dataUrl(android.net.Uri uri, int max, String forcedType) throws Exception {
    byte[] bytes = NativeApi.read(getContentResolver().openInputStream(uri), max);
    String type = forcedType != null ? forcedType : getContentResolver().getType(uri);
    if (type == null) type = "application/octet-stream";
    return "data:" + type + ";base64," + android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP);
  }

  private String fileName(android.net.Uri uri) {
    try (android.database.Cursor c = getContentResolver().query(uri, new String[] { android.provider.OpenableColumns.DISPLAY_NAME }, null, null, null)) {
      if (c != null && c.moveToFirst()) return c.getString(0);
    } catch (Exception ignored) {}
    return "tep-dinh-kem";
  }

  private void picked(int code, android.net.Uri uri) {
    String type = getContentResolver().getType(uri);
    boolean video = "video/mp4".equals(type);
    try {
      if (code == 300 || code == 304) { reviewMedia(uri,code==304?211:210); return; }
      if (code == 303) {
        JSONObject file = json("name", fileName(uri), "data", dataUrl(uri, 20 * 1024 * 1024, null));
        say(I18n.t("Đang gửi tệp…"));
        final String target = attachTarget;
        request("POST", target, json("body", "", "attachment", file), d -> {
          say(I18n.t("Đã gửi tệp."));
          if (chatReload != null) chatReload.run();
          else navigate("inbox");
        });
        return;
      }
      if (code == 308) {
        if (!Arrays.asList("image/png", "image/jpeg", "image/webp").contains(type)) { say(I18n.t("Chọn ảnh PNG/JPEG/WebP.")); return; }
        request("POST", "/api/me/private-photos", json("data", dataUrl(uri, 4 * 1024 * 1024, null)), result -> privateAlbum(me));
        return;
      }
      if (code == 305) uploadMusic(uri);
      if (code == 306) {
        if (!Arrays.asList("image/png", "image/jpeg", "image/webp").contains(type)) { say(I18n.t("Chọn ảnh PNG/JPEG/WebP.")); return; }
        request("POST", "/api/me/cover", json("data", dataUrl(uri, 3 * 1024 * 1024, null)), d -> { say(I18n.t("Đã đổi ảnh bìa.")); if (profileEditorAvatar == null || !profileEditorAvatar.isAttachedToWindow()) navigate("profile"); });
      }
    } catch (Exception e) {
      say(code == 308 ? I18n.t("Không tải được ảnh riêng tư.") : code == 303 ? I18n.t("Không gửi được tệp.") : I18n.t("Máy chủ chưa nhận được tệp media."));
    }
  }

  // ----- Quản trị: yêu cầu quên mật khẩu và thư viện nhạc
  private void adminResets() {
    final LinearLayout box = column();
    content.addView(box);
    request("GET", "/api/admin/password-resets", null, d -> {
      JSONArray rows = d.optJSONArray("requests");
      box.addView(label(I18n.t("Yêu cầu quên mật khẩu"), 18, TEXT));
      int open = 0;
      for (int i = 0; rows != null && i < rows.length(); i++) {
        final JSONObject r = rows.optJSONObject(i);
        if (!r.optString("status").equals("open")) continue;
        open++;
        LinearLayout c = column();
        c.setPadding(dp(14), dp(12), dp(14), dp(12));
        c.setBackground(background(CARD, 16));
        c.addView(label("@" + r.optString("username") + (r.isNull("user_id") ? I18n.t(" · không tồn tại") : ""), 16, TEXT));
        c.addView(label(I18n.t("Liên hệ: ") + r.optString("contact") + (r.optString("note").isEmpty() ? "" : "\n" + r.optString("note")), 13, MUTED));
        LinearLayout acts = row();
        if (!r.isNull("user_id")) acts.addView(chip("Cấp mật khẩu tạm", true, () -> confirm(I18n.t("Cấp mật khẩu tạm cho @") + r.optString("username") + "?", () ->
          request("POST", "/api/admin/password-resets/" + r.optString("id") + "/reset", json(), x ->
            new Sheet(this).setTitle(I18n.t("Mật khẩu tạm")).setMessage("@" + x.optString("username") + ": " + x.optString("temporaryPassword") + I18n.t("\n\nGửi riêng cho người dùng và nhắc họ đổi mật khẩu ngay.")).setPositiveButton("Xong", (dd, ww) -> admin()).show()))));
        acts.addView(chip("Bỏ qua", false, () -> request("POST", "/api/admin/password-resets/" + r.optString("id") + "/dismiss", json(), x -> admin())));
        c.addView(acts);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        box.addView(c, p);
      }
      if (open == 0) box.addView(label(I18n.t("Không có yêu cầu mới."), 14, MUTED));
    });
  }

  private android.media.MediaPlayer adminPlayer;

  private void adminMusic() {
    final LinearLayout box = column();
    content.addView(box);
    api.call("GET", "/api/music", null, (d, e, s) -> {
      if (isDestroyed()) return;
      box.addView(label(I18n.t("Thư viện nhạc"), 18, TEXT));
      JSONArray tracks = d == null ? null : d.optJSONArray("tracks");
      if (tracks == null || tracks.length() == 0) box.addView(label(I18n.t("Chưa có bài nào."), 14, MUTED));
      for (int i = 0; tracks != null && i < tracks.length(); i++) {
        final JSONObject t = tracks.optJSONObject(i);
        LinearLayout r = row();
        r.setPadding(dp(10), dp(6), dp(10), dp(6));
        r.setBackground(background(CARD, 14));
        r.addView(chip("▶", false, () -> {
          try {
            if (adminPlayer != null) adminPlayer.release();
            adminPlayer = new android.media.MediaPlayer();
            Map<String, String> headers = new HashMap<>();
            headers.put("Cookie", api.jar());
            adminPlayer.setDataSource(this, android.net.Uri.parse(server() + t.optString("url")), headers);
            adminPlayer.setOnPreparedListener(mp -> mp.start());
            adminPlayer.prepareAsync();
          } catch (Exception ex) { say(I18n.t("Không phát được bài này.")); }
        }));
        LinearLayout tx = column();
        tx.setPadding(dp(8), 0, 0, 0);
        tx.addView(label(t.optString("title"), 15, TEXT));
        tx.addView(label(t.optString("artist") + " · " + t.optString("license"), 11, MUTED));
        r.addView(tx, new LinearLayout.LayoutParams(0, -2, 1));
        r.addView(chip("Xoá", false, () -> confirm(I18n.t("Xoá bài “") + t.optString("title") + I18n.t("” khỏi thư viện?"), () -> request("DELETE", "/api/music", json("file", t.optString("file")), x -> admin()))));
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        box.addView(r, p);
      }
      box.addView(button(I18n.t("＋ Tải bài nhạc lên (MP3/M4A ≤15 MB)"), () -> pickFile(305, "audio/*")));
    });
  }

  private void uploadMusic(final android.net.Uri uri) throws Exception {
    String name = fileName(uri);
    boolean m4a = name.toLowerCase(Locale.ROOT).endsWith(".m4a");
    final String data = dataUrl(uri, 15 * 1024 * 1024, m4a ? "audio/mp4" : "audio/mpeg");
    LinearLayout box = column();
    box.setPadding(dp(20), dp(8), dp(20), 0);
    final EditText title = new EditText(this), artist = new EditText(this), license = new EditText(this), source = new EditText(this);
    title.setHint(I18n.t("Tên bài"));
    title.setText(name.replaceAll("\\.[^.]+$", ""));
    artist.setHint(I18n.t("Nghệ sĩ"));
    license.setHint(I18n.t("Giấy phép (vd: CC0, CC BY 4.0, tự sáng tác)"));
    source.setHint(I18n.t("Link nguồn (không bắt buộc)"));
    final CheckBox rights = new CheckBox(this);
    rights.setText(I18n.t("Tôi có quyền dùng và chia sẻ bài này trên Kinnect."));
    box.addView(title);
    box.addView(artist);
    box.addView(license);
    box.addView(source);
    box.addView(rights);
    new Sheet(this).setTitle(I18n.t("Thêm bài vào thư viện")).setView(box).setPositiveButton(I18n.t("Tải lên"), (d, w) -> {
      say(I18n.t("Đang tải nhạc lên…"));
      request("POST", "/api/music", json("data", data, "title", title.getText().toString(), "artist", artist.getText().toString(), "license", license.getText().toString(), "source", source.getText().toString(), "rights", rights.isChecked()), r -> { say(I18n.t("Đã thêm bài vào thư viện nhạc.")); admin(); });
    }).setNegativeButton(I18n.t("Hủy"), null).show();
  }


  // ===================== Tin nhắn, nhóm, bình luận nâng cao =====================
  private boolean shortsFollowing = false;
  private long lastActivity = 0;

  private void activity() {
    if (me == null || System.currentTimeMillis() - lastActivity < 60000) return;
    lastActivity = System.currentTimeMillis();
    api.call("POST", "/api/me/activity", json(), (d, e, s) -> {});
  }

  private String[] reactionGlyphs() {
    String[] names = new String[REACTIONS.length];
    for (int i = 0; i < names.length; i++) names[i] = REACTIONS[i][1];
    return names;
  }

  private void forwardMessage(final String source, final JSONObject message) {
    request("GET", "/api/conversations", null, conversations -> request("GET", "/api/groups", null, groups -> request("GET", "/api/friends", null, friends -> {
      final List<String> names = new ArrayList<>(), paths = new ArrayList<>();
      final Set<String> seen = new HashSet<>();
      JSONArray[] sets = { conversations.optJSONArray("users"), groups.optJSONArray("groups"), friends.optJSONArray("users") };
      for (int k = 0; k < sets.length; k++) for (int i = 0; sets[k] != null && i < sets[k].length(); i++) {
        JSONObject target = sets[k].optJSONObject(i);
        if (target == null) continue;
        String path = k == 1 ? "/api/groups/" + target.optString("id") + "/messages" : "/api/users/" + target.optString("id") + "/messages";
        if (seen.add(path)) { names.add((k == 1 ? "Nhóm · " : "") + target.optString("name")); paths.add(path); }
      }
      if (names.isEmpty()) { say(I18n.t("Chưa có bạn bè hoặc hội thoại để chuyển tiếp.")); return; }
      new Sheet(this).setTitle(I18n.t("Chuyển tiếp tin nhắn")).setItems(names.toArray(new String[0]), (dialog, index) -> {
        // Re-read the source so recalled/deleted messages cannot be forwarded from stale UI.
        request("GET", source, null, data -> {
          JSONArray rows = data.optJSONArray("messages");
          JSONObject current = null;
          for (int i = 0; rows != null && i < rows.length(); i++) if (rows.optJSONObject(i).optString("id").equals(message.optString("id"))) current = rows.optJSONObject(i);
          if (current == null || current.optBoolean("recalled")) { say(I18n.t("Tin nhắn không còn khả dụng để chuyển tiếp.")); return; }
          final JSONObject payload = json("body", current.optString("body"));
          final JSONObject file = current.optJSONObject("attachment");
          Runnable send = () -> request("POST", paths.get(index), payload, sent -> say(I18n.t("Đã chuyển tiếp đến ") + names.get(index)));
          if (file == null) { send.run(); return; }
          final int generation = screen;
          api.image(file.optString("url"), bytes -> {
            if (generation != screen || isDestroyed()) return;
            if (bytes == null || bytes.length > 20 * 1024 * 1024) { say(I18n.t("Không tải được tệp hoặc tệp vượt quá 20 MB.")); return; }
            try { payload.put("attachment", json("name", file.optString("name"), "data", "data:" + file.optString("type", "application/octet-stream") + ";base64," + android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP))); }
            catch (JSONException error) { say(I18n.t("Không thể chuẩn bị tệp đính kèm.")); return; }
            send.run();
          });
        });
      }).setNegativeButton(I18n.t("Đóng"), null).show();
    })));
  }

  private View messageTool(String iconName, String description, int color, Runnable action) {
    FrameLayout control = new FrameLayout(this);
    control.addView(icon(iconName, 16, color), new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
    control.setContentDescription(description);
    control.setOnClickListener(v -> action.run());
    control.setLayoutParams(new LinearLayout.LayoutParams(dp(32), dp(32)));
    return control;
  }

  private void messageMenu(final String kind, final JSONObject m, boolean own, final Runnable refresh) {
    if (m.optBoolean("recalled")) {
      new Sheet(this).setItems(new String[] { I18n.t("Xoá ở phía bạn") }, (d, w) -> request("DELETE", "/api/chat-messages/" + kind + "/" + m.optString("id"), json(), r -> refresh.run())).show();
      return;
    }
    final String base = "/api/chat-messages/" + kind + "/" + m.optString("id");
    final List<String> labels = new ArrayList<>();
    final List<Runnable> actions = new ArrayList<>();
    labels.add(I18n.t("Thả cảm xúc"));
    actions.add(() -> reactionBar(null, w ->
      request("POST", base + "/reaction", json("reaction", REACTIONS[w][0]), r -> refresh.run())));
    labels.add(m.optBoolean("pinned") ? "Bỏ ghim tin nhắn" : "Ghim tin nhắn");
    actions.add(() -> request(m.optBoolean("pinned") ? "DELETE" : "POST", base + "/pin", json(), r -> refresh.run()));
    if (own) {
      labels.add(I18n.t("Thu hồi với mọi người"));
      actions.add(() -> confirm(I18n.t("Thu hồi tin nhắn này?"), () -> request("POST", base + "/recall", json(), r -> refresh.run())));
    }
    labels.add(I18n.t("Xoá ở phía bạn"));
    actions.add(() -> request("DELETE", base, json(), r -> refresh.run()));
    if (!own) {
      labels.add(I18n.t("Báo cáo tin nhắn"));
      actions.add(() -> report(kind.equals("group")?"group_message":"message", m.optString("id")));
    }
    JSONObject reactions = m.optJSONObject("reactions");
    String title = null;
    if (reactions != null && reactions.length() > 0) {
      StringBuilder b = new StringBuilder();
      for (String[] r : REACTIONS) if (reactions.optInt(r[0]) > 0) b.append(r[1]).append(" ").append(reactions.optInt(r[0])).append("  ");
      title = b.toString().trim();
    }
    new Sheet(this).setTitle(I18n.t(title)).setItems(labels.toArray(new String[0]), (d, w) -> actions.get(w).run()).show();
  }

  private View chatNameWrap(EditText input){FrameLayout outer=new FrameLayout(this),inner=new FrameLayout(this);inner.addView(input,new FrameLayout.LayoutParams(-1,-2));outer.addView(inner,new FrameLayout.LayoutParams(-1,-2));return outer;}
  private void styleChatName(EditText input){
    input.setTextSize(15);input.setTextColor(TEXT);input.setHintTextColor(MUTED);input.setSingleLine(true);input.setGravity(Gravity.CENTER_VERTICAL);
    input.setPadding(dp(16),dp(12),dp(16),dp(12));input.setMinimumHeight(dp(50));input.setBackground(outlined(CARD,14));
  }

  private void chatActionSheet(String title,List<String> icons,List<String> labels,List<Runnable> actions){
    new Sheet(this).setTitle(I18n.t(title)).setItemIcons(icons.toArray(new String[0])).setItems(labels.toArray(new String[0]),(dialog,index)->actions.get(index).run()).show();
  }

  private void conversationMenu(String kind,String id,String name){conversationMenu(kind,id,name,false);}
  private void conversationMenu(final String kind,final String id,final String name,final boolean outside){
    final String prefs="/api/chat-preferences/"+kind+"/"+id;
    request("GET",prefs,null,p->{
      boolean muted=p.optBoolean("muted"),pinned=p.optBoolean("pinned");
      List<String> icons=new ArrayList<>(),labels=new ArrayList<>();List<Runnable> actions=new ArrayList<>();
      if(outside){icons.add("mail");labels.add(I18n.t("Đánh dấu chưa đọc"));actions.add(()->request("POST",prefs,json("unread",true),r->navigate("inbox")));}
      icons.add("pin");labels.add(pinned?I18n.t("Bỏ ghim"):I18n.t("Ghim hội thoại"));actions.add(()->request("POST",prefs,json("pinned",!pinned),r->{if(outside)navigate("inbox");else say(pinned?I18n.t("Đã bỏ ghim"):I18n.t("Đã ghim"));}));
      icons.add("bell");labels.add(muted?I18n.t("Bật thông báo"):I18n.t("Tắt thông báo"));actions.add(()->request("POST",prefs,json("muted",!muted),r->{if(outside)navigate("inbox");else say(muted?I18n.t("Đã bật thông báo"):I18n.t("Đã tắt thông báo"));}));
      icons.add("eye_off");labels.add(I18n.t("Ẩn hội thoại"));actions.add(()->request("POST",prefs,json("hidden",true),r->navigate("inbox")));
      icons.add("trash");labels.add(I18n.t("Xóa hội thoại ở phía bạn"));actions.add(()->confirm(I18n.t("Xóa lịch sử ở phía bạn? Người khác vẫn giữ tin nhắn của họ."),()->request("DELETE",kind.equals("direct")?"/api/users/"+id+"/messages":"/api/groups/"+id+"/messages",json(),r->navigate("inbox"))));
      chatActionSheet(name,icons,labels,actions);
    });
  }


  private JSONObject photoGroup;
  private Bitmap groupSample(String preset,int size){
    int[] colors=preset.equals("ocean")?new int[]{0xff0284c7,0xff22d3ee}:preset.equals("sunset")?new int[]{0xfff97316,0xffec4899}:preset.equals("forest")?new int[]{0xff059669,0xff84cc16}:new int[]{0xff7c3aed,0xffc084fc};
    Bitmap bitmap=Bitmap.createBitmap(size,size,Bitmap.Config.ARGB_8888);android.graphics.Canvas c=new android.graphics.Canvas(bitmap);android.graphics.Paint paint=new android.graphics.Paint(3);paint.setShader(new android.graphics.LinearGradient(0,0,size,size,colors,null,android.graphics.Shader.TileMode.CLAMP));c.drawCircle(size/2f,size/2f,size/2f,paint);SettingsGlyph glyph=new SettingsGlyph("group_three",WHITE,colors[0]);glyph.setBounds(size/5,size/5,size*4/5,size*4/5);glyph.draw(c);return bitmap;
  }
  private void groupPhotoOptions(final JSONObject g){
    LinearLayout choices=column();String[] presets={"violet","ocean","sunset","forest"},names={"Tím kết nối","Biển xanh","Hoàng hôn","Rừng xanh"};
    final android.app.Dialog[] photoDialog={null};final Sheet sheet=new Sheet(this).setTitle(I18n.t("Ảnh đại diện nhóm"));
    for(int i=0;i<presets.length;i++){final String preset=presets[i];LinearLayout item=row();ImageView preview=new ImageView(this);preview.setImageBitmap(groupSample(preset,dp(52)));item.addView(preview,new LinearLayout.LayoutParams(dp(52),dp(52)));TextView title=label(I18n.t(names[i]),15,TEXT);title.setPadding(dp(12),0,0,0);item.addView(title);item.setPadding(dp(8),dp(8),dp(8),dp(8));item.setOnClickListener(v->{if(photoDialog[0]!=null)photoDialog[0].dismiss();request("POST","/api/groups/"+g.optString("id")+"/avatar",json("preset",preset),d->groupChat(d.optJSONObject("group")));});choices.addView(item);}
    choices.addView(primary(I18n.t("Chọn ảnh từ thư viện"),()->{if(photoDialog[0]!=null)photoDialog[0].dismiss();photoGroup=g;pickFile(309,"image/*");}));photoDialog[0]=sheet.setView(choices).setNegativeButton(I18n.t("Đóng"),null).show();
  }
  private void profileCompletion(){
    if(me==null||getSharedPreferences("kinnect_profile",0).getBoolean("completion_dismissed:"+me.optString("id"),false))return;
    String[] keys={"avatar","bio","city","interests","lookingFor"},titles={"Ảnh đại diện","Giới thiệu","Khu vực","Sở thích","Mục đích kết nối"};int done=0;List<String> missing=new ArrayList<>();
    for(int i=0;i<keys.length;i++){Object value=me.opt(keys[i]);boolean filled=value instanceof JSONArray?((JSONArray)value).length()>0:value!=null&&value!=JSONObject.NULL&&!value.toString().trim().isEmpty();if(filled)done++;else missing.add(titles[i]);}
    if(done==keys.length)return;final LinearLayout panel=card();LinearLayout heading=row();TextView caption=label(I18n.t("Hoàn thiện hồ sơ · ")+done*100/keys.length+"%",16,TEXT);heading.addView(caption,new LinearLayout.LayoutParams(0,-2,1));FrameLayout close=new FrameLayout(this);close.setBackground(pressable(CARD,99));close.addView(icon("close",18,MUTED),new FrameLayout.LayoutParams(dp(18),dp(18),Gravity.CENTER));close.setContentDescription(I18n.t("Đóng gợi ý hoàn thiện hồ sơ"));close.setOnClickListener(v->{getSharedPreferences("kinnect_profile",0).edit().putBoolean("completion_dismissed:"+me.optString("id"),true).apply();if(panel.getParent() instanceof ViewGroup)((ViewGroup)panel.getParent()).removeView(panel);});heading.addView(close,new LinearLayout.LayoutParams(dp(44),dp(44)));panel.addView(heading);ProgressBar progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setMax(keys.length);progress.setProgress(done);progress.setProgressTintList(android.content.res.ColorStateList.valueOf(ACCENT));panel.addView(progress,new LinearLayout.LayoutParams(-1,dp(12)));panel.addView(label(I18n.t("Bổ sung: ")+android.text.TextUtils.join(", ",missing),13,MUTED));panel.addView(primary(I18n.t("Hoàn thiện hồ sơ"),()->editProfile()));
  }

  private JSONObject currentGroup;
  private void directChatMenu(JSONObject user){
    List<String> icons=new ArrayList<>(Arrays.asList("user_round","settings","flag","user_block"));
    List<String> labels=new ArrayList<>(Arrays.asList("Xem hồ sơ","Cài đặt hội thoại","Báo cáo tài khoản","Chặn tài khoản"));
    List<Runnable> actions=new ArrayList<>();actions.add(()->person(user));actions.add(()->conversationMenu("direct",user.optString("id"),user.optString("name")));actions.add(()->report("user",user.optString("id")));actions.add(()->confirm(I18n.t("Chặn ")+user.optString("name")+"?",()->request("POST","/api/users/"+user.optString("id")+"/block",json(),r->navigate("inbox"))));chatActionSheet(user.optString("name"),icons,labels,actions);
  }

  private String groupRole(JSONObject group,JSONObject member){return member.optString("id").equals(group.optString("owner"))?"owner":member.optString("groupRole","member");}
  private boolean groupManager(JSONObject g){if(g.optString("owner").equals(me.optString("id")))return true;JSONArray members=g.optJSONArray("members");for(int i=0;members!=null&&i<members.length();i++)if(members.optJSONObject(i).optString("id").equals(me.optString("id")))return groupRole(g,members.optJSONObject(i)).equals("deputy");return false;}
  private void groupMembers(final JSONObject g){
    accountHeader(I18n.t("Thành viên · ")+g.optString("name"),()->groupChat(g));JSONArray members=g.optJSONArray("members");
    for(int i=0;members!=null&&i<members.length();i++){final JSONObject member=members.optJSONObject(i);String role=groupRole(g,member);inboxRow(content,member,member.optString("name"),role.equals("owner")?"Trưởng nhóm":role.equals("deputy")?"Phó nhóm":"Thành viên",0,()->groupMemberActions(g,member));}
  }
  private void groupMemberActions(final JSONObject g,final JSONObject member){
    boolean owner=g.optString("owner").equals(me.optString("id")),self=member.optString("id").equals(me.optString("id"));String role=groupRole(g,member);
    List<String> icons=new ArrayList<>(),labels=new ArrayList<>();List<Runnable> actions=new ArrayList<>();icons.add("user_round");labels.add(I18n.t("Xem hồ sơ"));actions.add(()->person(member));
    if(owner&&!self){icons.add("shield_check");labels.add(role.equals("deputy")?"Bỏ vai trò phó nhóm":"Bổ nhiệm phó nhóm");actions.add(()->confirm(I18n.t("Thay đổi vai trò của ")+member.optString("name")+"?",()->request("PATCH","/api/groups/"+g.optString("id")+"/roles",json("userId",member.optString("id"),"role",role.equals("deputy")?"member":"deputy"),r->groupMembers(r.optJSONObject("group")))));
      icons.add("user_check");labels.add(I18n.t("Chuyển quyền trưởng nhóm"));actions.add(()->confirm(I18n.t("Chuyển quyền trưởng nhóm cho ")+member.optString("name")+"?",()->request("PATCH","/api/groups/"+g.optString("id")+"/roles",json("userId",member.optString("id"),"role","owner"),r->groupMembers(r.optJSONObject("group")))));}
    if(!self&&!role.equals("owner")&&(owner||groupManager(g)&&!role.equals("deputy"))){icons.add("user_block");labels.add(I18n.t("Xóa khỏi nhóm"));actions.add(()->confirm(I18n.t("Xóa ")+member.optString("name")+I18n.t(" khỏi nhóm?"),()->request("DELETE","/api/groups/"+g.optString("id")+"/members",json("userId",member.optString("id")),r->groupMembers(r.optJSONObject("group")))));}
    chatActionSheet(member.optString("name"),icons,labels,actions);
  }
  private void groupMenu(JSONObject stale){request("GET","/api/groups/"+stale.optString("id"),null,data->{final JSONObject g=data.optJSONObject("group");final String id=g.optString("id");
    List<String> icons=new ArrayList<>(),labels=new ArrayList<>();List<Runnable> actions=new ArrayList<>();
    icons.add("group_three");labels.add(I18n.t("Thành viên và vai trò"));actions.add(()->groupMembers(g));
    if(groupManager(g)){
      icons.add("camera");labels.add(I18n.t("Đổi ảnh nhóm"));actions.add(()->groupPhotoOptions(g));
      icons.add("pencil");labels.add(I18n.t("Đổi tên nhóm"));actions.add(()->{EditText name=new EditText(this);styleChatName(name);name.setText(g.optString("name"));new Sheet(this).setTitle(I18n.t("Tên nhóm")).setView(chatNameWrap(name)).setPositiveButton(I18n.t("Lưu"),(d,w)->request("PATCH","/api/groups/"+id,json("name",name.getText().toString()),r->groupChat(r.optJSONObject("group")))).setNegativeButton(I18n.t("Hủy"),null).show();});
      icons.add("user_plus");labels.add(I18n.t("Thêm thành viên"));actions.add(()->request("GET","/api/friends",null,d->{JSONArray users=d.optJSONArray("users");if(users==null||users.length()==0){say(I18n.t("Chưa có bạn bè để thêm."));return;}String[] names=new String[users.length()];boolean[] chosen=new boolean[users.length()];for(int i=0;i<names.length;i++)names[i]=users.optJSONObject(i).optString("name");new Sheet(this).setTitle(I18n.t("Thêm thành viên")).setMultiChoiceItems(names,chosen,(dialog,index,checked)->chosen[index]=checked).setPositiveButton(I18n.t("Thêm"),(dialog,index)->{JSONArray ids=new JSONArray();for(int i=0;i<chosen.length;i++)if(chosen[i])ids.put(users.optJSONObject(i).optString("id"));request("POST","/api/groups/"+id+"/members",json("members",ids),r->groupChat(r.optJSONObject("group")));}).setNegativeButton(I18n.t("Hủy"),null).show();}));
    }
    icons.add("settings");labels.add(I18n.t("Cài đặt hội thoại"));actions.add(()->conversationMenu("group",id,g.optString("name")));
    icons.add("log_out");labels.add(I18n.t("Rời nhóm"));actions.add(()->confirm(I18n.t("Rời nhóm? Nếu bạn là trưởng nhóm, quyền sẽ chuyển cho phó nhóm hoặc thành viên tiếp theo."),()->request("POST","/api/groups/"+id+"/leave",json(),r->navigate("inbox"))));
    chatActionSheet(g.optString("name"),icons,labels,actions);
  });}

  // Bình luận dạng chuỗi: trả lời, cảm xúc, báo cáo — dùng cho bài viết và video ngắn
  private String replyTo = null;

  private void comments(final String base, final Runnable reload, Runnable back, String backLabel) {
    final LinearLayout list = column();
    content.addView(list);
    final TextView replying = label("", 12, ACCENT);
    content.addView(replying);
    final EditText value = input(content, I18n.t("Viết bình luận…"), "", false);
    content.addView(primary(I18n.t("Gửi"), () -> {
      JSONObject payload = json("body", value.getText().toString());
      if (replyTo != null) try { payload.put("parentId", replyTo); } catch (JSONException ignored) {}
      request("POST", base + "/comments", payload, d -> { replyTo = null; reload.run(); });
    }));
    content.addView(button(backLabel, () -> { replyTo = null; back.run(); }));
    request("GET", base + "/comments", null, d -> {
      JSONArray all = d.optJSONArray("comments");
      if (all == null || all.length() == 0) { list.addView(label(I18n.t("Chưa có bình luận. Hãy là người đầu tiên."), 14, MUTED)); return; }
      for (int i = 0; i < all.length(); i++) {
        JSONObject cm = all.optJSONObject(i);
        if (cm.isNull("parentId") || cm.optString("parentId").isEmpty()) {
          commentRow(base, cm, list, 0, reload, replying, value);
          for (int j = 0; j < all.length(); j++) {
            JSONObject child = all.optJSONObject(j);
            if (child.optString("parentId").equals(cm.optString("id"))) commentRow(base, child, list, 1, reload, replying, value);
          }
        }
      }
    });
  }

  private void commentRow(final String base, final JSONObject cm, LinearLayout list, int depth, final Runnable reload, final TextView replying, final EditText value) {
    LinearLayout r = row();
    r.setPadding(dp(depth * 36), dp(6), 0, dp(2));
    r.setGravity(Gravity.TOP);
    avatar(cm.optJSONObject("author"), r, depth == 0 ? 34 : 28);
    LinearLayout t = column();
    LinearLayout bubble = column();
    bubble.setPadding(dp(12), dp(8), dp(12), dp(8));
    bubble.setBackground(background(CARD, 14));
    bubble.addView(label(cm.optJSONObject("author").optString("name"), 12, ACCENT));
    bubble.addView(label(cm.optString("body"), 15, TEXT));
    t.addView(bubble);
    LinearLayout meta = row();
    String mine = cm.isNull("myReaction") ? "" : cm.optString("myReaction");
    int total = 0;
    JSONObject counts = cm.optJSONObject("reactions");
    if (counts != null) for (String[] x : REACTIONS) total += counts.optInt(x[0]);
    String glyph = "Thích";
    for (String[] x : REACTIONS) if (x[0].equals(mine)) glyph = x[1];
    TextView like = label(ago(cm.optLong("created")) + "   " + glyph + (total > 0 ? " " + total : ""), 12, mine.isEmpty() ? MUTED : ACCENT);
    like.setOnClickListener(v -> request("POST", base + "/comments/" + cm.optString("id") + "/reaction", mine.isEmpty() ? json("reaction", "like") : json("reaction", JSONObject.NULL), x -> reload.run()));
    like.setOnLongClickListener(v -> {
      reactionBar(v, w -> request("POST", base + "/comments/" + cm.optString("id") + "/reaction", json("reaction", REACTIONS[w][0]), x -> reload.run()));
      return true;
    });
    meta.addView(like);
    TextView reply = label(I18n.t("   Trả lời"), 12, MUTED);
    final String parent = cm.isNull("parentId") || cm.optString("parentId").isEmpty() ? cm.optString("id") : cm.optString("parentId");
    reply.setOnClickListener(v -> {
      replyTo = parent;
      replying.setText(I18n.t("Đang trả lời ") + cm.optJSONObject("author").optString("name") + I18n.t(" · chạm để huỷ"));
      replying.setOnClickListener(x -> { replyTo = null; replying.setText(""); });
      value.requestFocus();
    });
    meta.addView(reply);
    TextView rep = label(I18n.t("   Báo cáo"), 12, MUTED);
    rep.setOnClickListener(v -> report("comment", cm.optString("id")));
    meta.addView(rep);
    t.addView(meta);
    LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(0, -2, 1);
    tp.setMargins(dp(8), 0, 0, 0);
    r.addView(t, tp);
    list.addView(r);
  }

  private Runnable chatReload;

  private void chat(final JSONObject u) {
    currentGroup=null;
    remember("chat:" + u.optString("id"), () -> chat(u));
    headerActive = "inbox";
    final String path = "/api/users/" + u.optString("id") + "/messages";
    chatScreen(u, u.optString("name"), u.optBoolean("isActive") ? "Đang hoạt động" : "@" + u.optString("username"), path, false, () -> directChatMenu(u), () -> chat(u));
    chatUser = u;
  }

  private void groupChat(final JSONObject g) {
    currentGroup=g;
    remember("group:" + g.optString("id"), () -> groupChat(g));
    JSONArray members = g.optJSONArray("members");
    chatScreen(null, g.optString("name"), (members == null ? 0 : members.length()) + " thành viên", "/api/groups/" + g.optString("id") + "/messages", true, () -> groupMenu(g), () -> groupChat(g));
  }

  // Khung chat toàn màn giống web: đầu trang (quay lại, avatar, gọi), tin nhắn dạng bong bóng, ô nhập bo tròn.
  private void chatScreen(final JSONObject u, String title, String subtitle, final String path, final boolean group, final Runnable more, final Runnable reopen) {
    shell("", true);
    chatReload = reopen;
    toolbar.setVisibility(View.GONE);
    if (bottom != null) bottom.setVisibility(View.GONE);
    ScrollView scroll = (ScrollView) content.getParent();
    int at = root.indexOfChild(scroll);
    root.removeView(scroll);
    LinearLayout box = column();
    box.setBackgroundColor(CARD);
    root.addView(box, at, new LinearLayout.LayoutParams(-1, 0, 1));
    LinearLayout head = row();
    head.setPadding(dp(6), dp(8), dp(8), dp(8));
    ImageView back = icon("back", 24, TEXT);
    back.setPadding(dp(8), dp(8), dp(8), dp(8));
    back.setContentDescription(I18n.t("Quay lại"));
    back.setOnClickListener(v -> navigate("inbox"));
    head.addView(back, new LinearLayout.LayoutParams(dp(42), dp(42)));
    if (u != null || group && currentGroup!=null) avatar(u!=null?u:currentGroup, head, 36);
    else {
      FrameLayout g = new FrameLayout(this);
      GradientDrawable o = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { ACCENT, ACCENT });
      o.setShape(GradientDrawable.OVAL);
      g.setBackground(o);
      ImageView groupGlyph=new ImageView(this);groupGlyph.setImageDrawable(new SettingsGlyph("group_three",WHITE,ACCENT));g.addView(groupGlyph,new FrameLayout.LayoutParams(dp(28),dp(28),Gravity.CENTER));
      head.addView(g, new LinearLayout.LayoutParams(dp(42), dp(42)));
    }
    LinearLayout who = column();
    who.setPadding(dp(10), 0, 0, 0);
    TextView n = label(title, 14, TEXT);
    n.setTypeface(null, Typeface.BOLD);
    n.setSingleLine(true);
    n.setPadding(0, 0, 0, 0);
    who.addView(n);
    TextView st = label(subtitle, 12, MUTED);
    st.setPadding(0, 0, 0, 0);
    who.addView(st);
    if (u != null) who.setOnClickListener(v -> person(u));
    head.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
    if (u != null) {
      head.addView(softIconButton("call", I18n.t("Gọi thoại"), () -> { ensureCalls(); calls.start(u, "audio"); }));
      head.addView(softIconButton("video", I18n.t("Gọi video"), () -> { ensureCalls(); calls.start(u, "video"); }));
    }
    head.addView(chatHeaderButton("menu_lines","Thông tin và tùy chọn hội thoại",more));
    box.addView(head);
    box.addView(divider());
    final ScrollView msgScroll = new ScrollView(this);
    msgScroll.setBackgroundColor(BG == 0xfff6f5fa ? 0xfff7f8fa : BG);
    final LinearLayout list = column();
    list.setPadding(dp(12), dp(10), dp(12), dp(10));
    msgScroll.addView(list);
    aiChatList=list;aiChatScroll=msgScroll;aiChatSender=!group&&u!=null?u.optString("id"):"";ensureCalls();
    box.addView(msgScroll, new LinearLayout.LayoutParams(-1, 0, 1));
    box.addView(divider());
    LinearLayout bar = row();
    bar.setPadding(dp(8), dp(8), dp(10), dp(8));
    ImageView clip = icon("attach", 22, ACCENT);
    clip.setPadding(dp(9), dp(9), dp(9), dp(9));
    clip.setContentDescription(I18n.t("Đính kèm"));
    clip.setOnClickListener(v -> { attachTarget = path; pickFile(303, "*/*"); });
    bar.addView(clip, new LinearLayout.LayoutParams(dp(42), dp(42)));
    final EditText input = new EditText(this);
    input.setHint(I18n.t("Nhắn tin..."));
    input.setContentDescription(I18n.t("Tin nhắn"));
    input.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(2000) });
    input.setTextColor(TEXT);
    input.setHintTextColor(MUTED);
    input.setTextSize(15);
    input.setPadding(dp(16),dp(10),dp(16),dp(10));
    input.setGravity(Gravity.CENTER_VERTICAL);
    input.setBackground(background(SOFT, 999));
    input.setSingleLine(true);
    LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(0, dp(44), 1);
    ip.setMargins(dp(4), 0, dp(8), 0);
    bar.addView(input, ip);
    if(group&&currentGroup!=null)installMentions(input,currentGroup);
    FrameLayout send = new FrameLayout(this);
    send.setBackground(background(ACCENT, 999));
    send.addView(icon("send", 20, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    send.setContentDescription(I18n.t("Gửi"));
    final Runnable load = () -> loadChat(path, list, msgScroll, group, u);
    send.setOnClickListener(v -> {
      String text = input.getText().toString().trim();
      if (text.isEmpty()) return;
      submitText(input, send, path, json("body", text,"mentions",group?mentionIds(text,currentGroup):new JSONArray()), d -> { lastMessages = ""; load.run(); });
    });
    bar.addView(send, new LinearLayout.LayoutParams(dp(46), dp(46)));
    box.addView(bar);
    lastMessages = "";
    aiChatReload=load;
    load.run();
    final int generation = screen;
    poll = () -> {
      if (!stopped && generation == screen) {
        load.run();
        handler.postDelayed(poll, 4000);
      }
    };
    handler.postDelayed(poll, 4000);
  }

  private FrameLayout chatHeaderButton(String glyph,String description,Runnable action){
    FrameLayout button=new FrameLayout(this);button.setBackground(background(PRIMARY_SOFT,12));ImageView image=new ImageView(this);
    if(glyph.equals("menu_lines"))image.setImageDrawable(new SettingsGlyph("menu_lines",ACCENT,PRIMARY_SOFT));else image.setImageDrawable(WebIcons.load(this,glyph));image.setImageTintList(android.content.res.ColorStateList.valueOf(ACCENT));
    button.addView(image,new FrameLayout.LayoutParams(dp(22),dp(22),Gravity.CENTER));button.setContentDescription(description);button.setOnClickListener(v->action.run());LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(dp(44),dp(44));p.leftMargin=dp(6);button.setLayoutParams(p);return button;
  }
  private JSONArray mentionIds(String body,JSONObject group){JSONArray ids=new JSONArray(),members=group==null?null:group.optJSONArray("members");for(int i=0;members!=null&&i<members.length();i++){JSONObject u=members.optJSONObject(i);if(!u.optString("id").equals(me.optString("id"))&&ChatTextPolicy.mentionIndex(body,u.optString("username"))>=0)ids.put(u.optString("id"));}return ids;}
  private void installMentions(final EditText input,final JSONObject group){
    final ListPopupWindow popup=new ListPopupWindow(this);popup.setAnchorView(input);popup.setModal(false);popup.setHeight(dp(180));
    final List<JSONObject> matches=new ArrayList<>();final int[] token={-1};
    popup.setOnItemClickListener((parent,view,index,id)->{if(index>=matches.size()||token[0]<0)return;String text=input.getText().toString();int cursor=input.getSelectionStart();if(cursor<token[0])return;String replacement="@"+matches.get(index).optString("username")+" ";input.getText().replace(token[0],cursor,replacement);popup.dismiss();input.requestFocus();});
    input.addTextChangedListener(new android.text.TextWatcher(){public void beforeTextChanged(CharSequence t,int start,int count,int after){}public void onTextChanged(CharSequence t,int start,int before,int count){}public void afterTextChanged(android.text.Editable editable){
      int cursor=input.getSelectionStart();String text=editable.toString();int at=cursor<0?-1:text.lastIndexOf('@',Math.max(0,cursor-1));
      if(at<0||at>0&&!Character.isWhitespace(text.charAt(at-1))||text.substring(at+1,Math.max(at+1,cursor)).contains(" ")){popup.dismiss();return;}
      String query=text.substring(at+1,cursor).toLowerCase(Locale.ROOT);matches.clear();List<String> labels=new ArrayList<>();JSONArray members=group.optJSONArray("members");
      for(int i=0;members!=null&&i<members.length();i++){JSONObject u=members.optJSONObject(i);if(u.optString("id").equals(me.optString("id")))continue;if((u.optString("name")+" "+u.optString("username")).toLowerCase(Locale.ROOT).contains(query)){matches.add(u);labels.add(u.optString("name")+" · @"+u.optString("username"));}}
      token[0]=at;if(labels.isEmpty()){popup.dismiss();return;}popup.setWidth(Math.max(dp(200),input.getWidth()));popup.setAdapter(new ArrayAdapter<String>(MainActivity.this,android.R.layout.simple_list_item_1,labels));popup.show();
    }});
    input.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener(){public void onViewAttachedToWindow(View v){}public void onViewDetachedFromWindow(View v){popup.dismiss();}});
  }

  private FrameLayout softIconButton(String name, String label, Runnable action) {
    FrameLayout f = new FrameLayout(this);
    f.setBackground(background(PRIMARY_SOFT, 12));
    f.addView(icon(name, 22, ACCENT), new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
    f.setContentDescription(label);
    f.setOnClickListener(v -> action.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(dp(44), dp(44));
    p.leftMargin = dp(6);
    f.setLayoutParams(p);
    return f;
  }

  private void loadChat(final String path, final LinearLayout list, final ScrollView scroll, final boolean group, final JSONObject other) {
    if (Boolean.TRUE.equals(list.getTag())) return;
    list.setTag(Boolean.TRUE);
    request("GET", path, null, data -> {
      JSONArray messages = data.optJSONArray("messages");
      String signature = (messages == null ? "" : messages.toString())+data.optString("aiSupport");
      if (signature.equals(lastMessages) && list.getChildCount() > 0) return;
      final boolean followBottom = lastMessages.isEmpty() || list.getHeight() - scroll.getScrollY() - scroll.getHeight() < dp(64);
      final int previousY = scroll.getScrollY();
      lastMessages = signature;
      list.removeAllViews();
      JSONObject aiInfo=data.optJSONObject("aiSupport");if(!group&&aiInfo!=null&&aiInfo.optBoolean("available")){
        boolean enabled=aiInfo.optString("consent").equals("enabled");TextView info=label(enabled?I18n.t("Trợ lý AI đã bật."):I18n.t("Trợ lý AI đang tắt. Bạn vẫn có thể nhắn quản trị viên."),12,MUTED);list.addView(info);
        list.addView(button(enabled?I18n.t("Tắt AI"):I18n.t("Bật trợ lý AI"),()->{Runnable apply=()->request("POST","/api/me/ai-consent",json("enabled",!enabled),r->{lastMessages="";loadChat(path,list,scroll,group,other);});if(enabled)apply.run();else confirm(I18n.t("Bật trợ lý AI? Nội dung bạn gửi và tối đa 6 tin nhắn liên quan được gửi tới Cloudflare, hoặc NVIDIA khi dự phòng, để tạo câu trả lời. Không gửi mật khẩu, OTP hoặc dữ liệu nhạy cảm. Bạn có thể tắt AI bất cứ lúc nào và tiếp tục nhắn quản trị viên."),apply);}));
      }
      String lastDay = "";
      java.text.SimpleDateFormat day = new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()), clock = new java.text.SimpleDateFormat("HH:mm", Locale.getDefault());
      String today = day.format(new Date());
      if (messages == null || messages.length() == 0) {
        LinearLayout hello = column();
        hello.setGravity(Gravity.CENTER_HORIZONTAL);
        hello.setPadding(0, dp(60), 0, 0);
        FrameLayout bubble = new FrameLayout(this);
        bubble.setBackground(background(PRIMARY_SOFT, 99));
        bubble.addView(icon("message_circle", 26, ACCENT), new FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER));
        hello.addView(bubble, new LinearLayout.LayoutParams(dp(60), dp(60)));
        TextView ht = label(I18n.t("Hãy gửi lời chào đầu tiên!"), 15, MUTED);
        ht.setPadding(0, dp(12), 0, 0);
        ht.setGravity(Gravity.CENTER);
        hello.addView(ht,new LinearLayout.LayoutParams(-1,-2));
        list.addView(hello, new LinearLayout.LayoutParams(-1, -2));
      }
      for (int i = 0; messages != null && i < messages.length(); i++) {
        final JSONObject m = messages.optJSONObject(i);
        final boolean own = m.optString("sender").equals(me.optString("id"));
        Date at = new Date(m.optLong("created"));
        String d = day.format(at);
        if (!d.equals(lastDay)) {
          lastDay = d;
          TextView sep = label(d.equals(today) ? I18n.t("Hôm nay") : d, 11, MUTED);
          sep.setPadding(dp(10), dp(3), dp(10), dp(3));
          sep.setBackground(background(SOFT, 999));
          LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-2, -2);
          sp.gravity = Gravity.CENTER_HORIZONTAL;
          sp.setMargins(0, dp(10), 0, dp(10));
          list.addView(sep, sp);
        }
        LinearLayout bubble = column();
        bubble.setPadding(dp(14), dp(9), dp(14), dp(7));
        GradientDrawable shape = background(own ? (StoreStyle.chatColor(me.optString("storeStyle"))!=0?StoreStyle.chatColor(me.optString("storeStyle")):ACCENT) : CARD, 18);
        if (!own) shape.setStroke(1, LINE);
        bubble.setBackground(shape);
        if (group && !own) {
          TextView author = label(m.optJSONObject("author") == null ? "" : m.optJSONObject("author").optString("name"), 12, ACCENT);
          author.setTypeface(null, Typeface.BOLD);
          author.setPadding(0, 0, 0, 0);
          JSONObject authorData=m.optJSONObject("author");if(authorData!=null){String role=authorData.optString("groupRole");if(role.equals("owner")||role.equals("deputy"))author.setText(author.getText()+" · "+(role.equals("owner")?I18n.t("Trưởng nhóm"):I18n.t("Phó nhóm")));}
          bubble.addView(author);
        }
        final JSONObject file = m.optJSONObject("attachment");
        if (!m.optBoolean("recalled") && file != null && file.optString("kind").equals("image")) mediaView(file, bubble);
        else if (!m.optBoolean("recalled") && file != null) {
          TextView f = label("📎 " + file.optString("name"), 15, own ? WHITE : TEXT);
          f.setOnClickListener(v -> openAttachment(file));
          bubble.addView(f);
        }
        String body = m.optBoolean("recalled") ? "Tin nhắn đã được thu hồi" : m.optString("body");
        if (!body.isEmpty()) {
          TextView t = label(body, 15, own ? WHITE : TEXT);
          t.setPadding(0, 0, 0, 0);
          if(group&&!m.optBoolean("recalled")){android.text.SpannableString rich=new android.text.SpannableString(body);JSONArray mentions=m.optJSONArray("mentions");for(int j=0;mentions!=null&&j<mentions.length();j++){JSONObject mentioned=mentions.optJSONObject(j);String token="@"+mentioned.optString("username");int start=ChatTextPolicy.mentionIndex(body,mentioned.optString("username"));if(start>=0){rich.setSpan(new android.text.style.StyleSpan(Typeface.BOLD),start,start+token.length(),0);final JSONObject target=mentioned;rich.setSpan(new android.text.style.ClickableSpan(){public void onClick(View view){person(target);}public void updateDrawState(android.text.TextPaint paint){paint.setColor(own?WHITE:ACCENT);paint.setUnderlineText(true);}},start,start+token.length(),0);}}t.setText(rich);if(mentions!=null&&mentions.length()>0)t.setMovementMethod(android.text.method.LinkMovementMethod.getInstance());}
          if (m.optBoolean("recalled")) t.setTypeface(null, Typeface.ITALIC);
          bubble.addView(t);
        }
        JSONObject reactions = m.optJSONObject("reactions");
        StringBuilder rx = new StringBuilder();
        for (String[] r : REACTIONS) if (reactions != null && reactions.optInt(r[0]) > 0) rx.append(r[1]);
        TextView time = label(clock.format(at) + (m.optBoolean("pinned") ? "  📌" : "") + (rx.length() > 0 ? "  " + rx : ""), 10, own ? 0xccffffff : MUTED);
        time.setPadding(0, dp(2), 0, 0);
        bubble.addView(time);
        JSONObject receipt = m.optJSONObject("receipt");
        if (own && !m.optBoolean("recalled")) {
          boolean seen = receipt != null && (receipt.optLong("seenAt") > 0 || receipt.optInt("seenCount") > 0);
          boolean delivered = seen || (receipt != null && (receipt.optLong("deliveredAt") > 0 || receipt.optInt("deliveredCount") > 0));
          TextView state = label(seen ? "✓✓" : delivered ? "✓✓" : "✓", 11, own ? WHITE : ACCENT);
          state.setAlpha(seen ? 1f : 0.55f);
          state.setContentDescription(seen ? I18n.t("Đã xem") : delivered ? I18n.t("Đã nhận") : I18n.t("Đã gửi")); state.setTooltipText(String.valueOf(state.getContentDescription()));
          bubble.addView(state);
        }
        final String base = "/api/chat-messages/" + (group ? "group" : "direct") + "/" + m.optString("id");
        final Runnable refresh = () -> { lastMessages = ""; loadChat(path, list, scroll, group, other); };
        LinearLayout tools = row();
        int toolColor = own ? 0xddffffff : MUTED;
        if (!m.optBoolean("recalled")) {
          tools.addView(messageTool("smile", I18n.t("Cảm xúc tin nhắn"), toolColor, () -> reactionBar(null, w -> request("POST", base + "/reaction", json("reaction", REACTIONS[w][0]), result -> refresh.run()))));
          tools.addView(messageTool("forward", I18n.t("Chuyển tiếp tin nhắn"), toolColor, () -> forwardMessage(path, m)));
          if (own) tools.addView(messageTool("recall", I18n.t("Thu hồi với mọi người"), toolColor, () -> confirm(I18n.t("Thu hồi tin nhắn này?"), () -> request("POST", base + "/recall", json(), result -> refresh.run()))));
        }
        tools.addView(messageTool("trash", I18n.t("Xoá tin nhắn ở phía bạn"), toolColor, () -> request("DELETE", base, json(), result -> refresh.run())));
        bubble.addView(tools);
        bubble.setOnLongClickListener(v -> { messageMenu(group ? "group" : "direct", m, own, () -> { lastMessages = ""; loadChat(path, list, scroll, group, other); }); return true; });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, -2);
        p.gravity = own ? Gravity.END : Gravity.START;
        p.setMargins(own ? dp(48) : 0, dp(3), own ? 0 : dp(48), dp(3));
        list.addView(bubble, p);
      }
      paintAIStream();
      scroll.post(() -> { if (followBottom) scroll.fullScroll(View.FOCUS_DOWN); else scroll.scrollTo(0, previousY); });
    }, () -> list.setTag(Boolean.FALSE));
  }

  // Bình luận mở ngay dưới bài viết như web: bong bóng xám, "Thích · Trả lời · thời gian", ô "Viết bình luận…".
  private void inlineComments(final JSONObject p, final LinearLayout thread, final boolean focus) {
    inlineComments(p, thread, focus, "");
  }

  private void inlineComments(final JSONObject p, final LinearLayout thread, final boolean focus, final String commentFocus) {
    thread.removeAllViews();
    thread.addView(divider());
    final LinearLayout list = column();
    list.setPadding(0, dp(6), 0, 0);
    thread.addView(list);
    final String base = "/api/posts/" + p.optString("id") + "/comments";
    final String[] parent = { null };
    final TextView replying = label("", 12, MUTED);
    replying.setVisibility(View.GONE);
    LinearLayout bar = row();
    bar.setPadding(0, dp(6), 0, dp(10));
    avatar(me, bar, 32);
    final EditText input = new EditText(this);
    input.setHint(I18n.t("Viết bình luận..."));
    input.setContentDescription(I18n.t("Viết bình luận"));
    input.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(1000) });
    input.setTextColor(TEXT);
    input.setHintTextColor(MUTED);
    input.setTextSize(15);
    input.setSingleLine(true);
    input.setPadding(dp(14), 0, dp(14), 0);
    input.setBackground(background(SOFT, 999));
    LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(0, dp(40), 1);
    ip.setMargins(dp(8), 0, dp(4), 0);
    bar.addView(input, ip);
    ImageView send = icon("send", 22, ACCENT);
    send.setPadding(dp(8), dp(8), dp(8), dp(8));
    send.setContentDescription(I18n.t("Gửi bình luận"));
    bar.addView(send, new LinearLayout.LayoutParams(dp(40), dp(40)));
    thread.addView(replying);
    thread.addView(bar);
    replying.setOnClickListener(v -> { parent[0] = null; replying.setVisibility(View.GONE); input.setHint(I18n.t("Viết bình luận...")); });
    final Runnable[] load = new Runnable[1];
    load[0] = () -> request("GET", base, null, d -> {
      JSONArray all = d.optJSONArray("comments");
      int count = all == null ? 0 : all.length();
      try { p.put("comments", count); } catch (JSONException ignored) {}
      if (thread.getTag() instanceof TextView) ((TextView) thread.getTag()).setText(count + I18n.t(" bình luận"));
      list.removeAllViews();
      for (int i = 0; all != null && i < all.length(); i++) {
        final JSONObject c = all.optJSONObject(i);
        if (!c.isNull("parentId") && !c.optString("parentId").isEmpty()) continue;
        list.addView(feedComment(c, false, base, load[0], () -> {
          parent[0] = c.optString("id");
          replying.setText(I18n.t("Đang trả lời ") + c.optJSONObject("author").optString("name") + I18n.t(" · chạm để huỷ"));
          replying.setVisibility(View.VISIBLE);
          input.setHint(I18n.t("Trả lời ") + c.optJSONObject("author").optString("name") + "...");
          input.requestFocus();
        }));
        for (int k = 0; k < all.length(); k++) {
          final JSONObject child = all.optJSONObject(k);
          if (!child.optString("parentId").equals(c.optString("id"))) continue;
          list.addView(feedComment(child, true, base, load[0], () -> {
            parent[0] = c.optString("id");
            replying.setText(I18n.t("Đang trả lời ") + child.optJSONObject("author").optString("name") + I18n.t(" · chạm để huỷ"));
            replying.setVisibility(View.VISIBLE);
            input.requestFocus();
          }));
        }
      }
      if (!commentFocus.isEmpty()) {
        final View target = list.findViewWithTag(commentFocus);
        if (target != null) { target.setBackground(background(PRIMARY_SOFT, 12)); target.post(() -> target.requestRectangleOnScreen(new Rect(0, 0, target.getWidth(), target.getHeight()), true)); }
      }
    });
    send.setOnClickListener(v -> {
      String text = input.getText().toString().trim();
      if (text.isEmpty()) return;
      JSONObject payload = json("body", text);
      if (parent[0] != null) try { payload.put("parentId", parent[0]); } catch (JSONException ignored) {}
      submitText(input, send, base, payload, x -> {
        if (input.length() == 0) { parent[0] = null; replying.setVisibility(View.GONE); input.setHint(I18n.t("Viết bình luận...")); }
        load[0].run();
      });
    });
    load[0].run();
    if (focus) input.requestFocus();
  }

  private LinearLayout feedComment(final JSONObject c, boolean reply, final String base, final Runnable reload, final Runnable onReply) {
    LinearLayout r = row();
    r.setTag(c.optString("id"));
    r.setGravity(Gravity.TOP);
    r.setPadding(reply ? dp(40) : 0, dp(4), 0, dp(4));
    avatar(c.optJSONObject("author"), r, reply ? 26 : 32);
    LinearLayout col = column();
    LinearLayout bubble = column();
    bubble.setPadding(dp(12), dp(7), dp(12), dp(8));
    bubble.setBackground(background(SOFT, 16));
    TextView name = label(c.optJSONObject("author").optString("name"), 13, TEXT);
    name.setTypeface(null, Typeface.BOLD);
    name.setPadding(0, 0, 0, 0);
    bubble.addView(name);
    TextView text = label(c.optString("body"), 15, TEXT);
    text.setPadding(0, dp(1), 0, 0);
    bubble.addView(text);
    col.addView(bubble, new LinearLayout.LayoutParams(-2, -2));
    LinearLayout meta = row();
    meta.setPadding(dp(10), dp(2), 0, 0);
    String mine = c.isNull("myReaction") ? "" : c.optString("myReaction");
    String likeText = "Thích";
    for (String[] x : REACTIONS) if (x[0].equals(mine)) likeText = x[1] + " Thích";
    TextView like = label(likeText, 12, mine.isEmpty() ? MUTED : ACCENT);
    like.setTypeface(null, Typeface.BOLD);
    like.setOnClickListener(v -> request("POST", base + "/" + c.optString("id") + "/reaction", mine.isEmpty() ? json("reaction", "like") : json("reaction", JSONObject.NULL), x -> reload.run()));
    like.setOnLongClickListener(v -> {
      reactionBar(v, w -> request("POST", base + "/" + c.optString("id") + "/reaction", json("reaction", REACTIONS[w][0]), x -> reload.run()));
      return true;
    });
    meta.addView(like);
    TextView rep = label(I18n.t("     Trả lời"), 12, MUTED);
    rep.setTypeface(null, Typeface.BOLD);
    rep.setOnClickListener(v -> onReply.run());
    meta.addView(rep);
    meta.addView(label("     " + ago(c.optLong("created")), 12, MUTED));
    int total = 0;
    JSONObject counts = c.optJSONObject("reactions");
    StringBuilder glyphs = new StringBuilder();
    if (counts != null) for (String[] x : REACTIONS) if (counts.optInt(x[0]) > 0) { total += counts.optInt(x[0]); glyphs.append(x[1]); }
    if (total > 0) meta.addView(label("     " + glyphs + " " + total, 12, MUTED));
    col.addView(meta);
    LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(0, -2, 1);
    cp.leftMargin = dp(8);
    r.addView(col, cp);
    r.setOnLongClickListener(v -> { commentOptions(c, base, reload); return true; });
    return r;
  }


  // Tạo tin giống web: bảng trượt từ dưới với hai ô lớn "Quay tin" và "Ảnh kèm nhạc".
  private void commentOptions(JSONObject comment, String base, Runnable reload) {
    JSONObject author = comment.optJSONObject("author");
    if (author == null || !author.optString("id").equals(me.optString("id"))) { report("comment", comment.optString("id")); return; }
    final String path = base + "/" + comment.optString("id");
    new Sheet(this).setItems(new String[] { I18n.t("Chỉnh sửa"), I18n.t("Xoá bình luận") }, (dialog, choice) -> {
      if (choice == 1) { confirm(I18n.t("Xoá bình luận này?"), () -> request("DELETE", path, json(), data -> reload.run())); return; }
      LinearLayout form = column();
      final Dialog[] editor = { null };
      EditText text = input(form, I18n.t("Bình luận"), comment.optString("body"), true);
      final Button save = primary(I18n.t("Lưu"), () -> {});
      save.setOnClickListener(v -> {
        if (!save.isEnabled()) return;
        if (text.getText().toString().trim().isEmpty()) { text.setError(I18n.t("Nhập bình luận")); return; }
        save.setEnabled(false);
        request("PATCH", path, json("body", text.getText().toString()), data -> { editor[0].dismiss(); say(I18n.t("Đã lưu bình luận")); reload.run(); }, () -> save.setEnabled(true));
      });
      form.addView(save);
      editor[0] = new Sheet(this).setTitle(I18n.t("Chỉnh sửa bình luận")).setView(form).setNegativeButton(I18n.t("Đóng"), null).show();
    }).show();
  }

  private void createStory() {
    final android.app.Dialog dialog = new android.app.Dialog(this);
    dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
    LinearLayout sheet = column();
    sheet.setPadding(dp(16), dp(10), dp(16), dp(18));
    GradientDrawable shape = new GradientDrawable();
    shape.setColor(CARD);
    float r = dp(22);
    shape.setCornerRadii(new float[] { r, r, r, r, 0, 0, 0, 0 });
    sheet.setBackground(shape);
    View grip = new View(this);
    grip.setBackground(background(LINE, 99));
    LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(dp(40), dp(5));
    gp.gravity = Gravity.CENTER_HORIZONTAL;
    sheet.addView(grip, gp);
    TextView title = label(I18n.t("Tạo tin"), 17, TEXT);
    title.setTypeface(null, Typeface.BOLD);
    title.setGravity(Gravity.CENTER);
    title.setPadding(0, dp(10), 0, dp(12));
    sheet.addView(title);
    LinearLayout tiles = row();
    tiles.addView(storyTile("video", "Quay tin", I18n.t("Camera · Nhạc · Hiệu ứng"), 0xff8354ef, 0xffd94cae, () -> {
      dialog.dismiss();
      Intent studio = new Intent(this, StudioActivity.class);
      studio.putExtra(StudioActivity.EXTRA_STORY, true);
      startActivityForResult(studio, 204);
    }), new LinearLayout.LayoutParams(0, dp(210), 1));
    LinearLayout.LayoutParams second = new LinearLayout.LayoutParams(0, dp(210), 1);
    second.leftMargin = dp(12);
    tiles.addView(storyTile("image", I18n.t("Ảnh kèm nhạc"), I18n.t("Chọn ảnh · thêm bài hát"), 0xff397be9, 0xff724ee5, () -> {
      dialog.dismiss();
      pickFile(307, "image/*");
    }), second);
    sheet.addView(tiles);
    TextView note = label(I18n.t("Tin hiển thị 24 giờ cho những người theo dõi bạn."), 12, MUTED);
    note.setGravity(Gravity.CENTER);
    note.setPadding(0, dp(12), 0, 0);
    sheet.addView(note);
    dialog.setContentView(sheet);
    Window w = dialog.getWindow();
    if (w != null) {
      w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(0));
      w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
      w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.45f);
    }
    dialog.show();
  }

  private LinearLayout storyTile(String iconName, String title, String sub, int from, int to, Runnable click) {
    LinearLayout t = column();
    t.setGravity(Gravity.CENTER);
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { from, to });
    g.setCornerRadius(dp(18));
    t.setBackground(g);
    FrameLayout circle = new FrameLayout(this);
    circle.setBackground(background(0x33ffffff, 999));
    circle.addView(icon(iconName, 30, WHITE), new FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER));
    t.addView(circle, new LinearLayout.LayoutParams(dp(60), dp(60)));
    TextView a = label(title, 16, WHITE);
    a.setTypeface(null, Typeface.BOLD);
    a.setGravity(Gravity.CENTER);
    a.setPadding(0, dp(12), 0, 0);
    t.addView(a);
    TextView b = label(sub, 12, 0xe6ffffff);
    b.setGravity(Gravity.CENTER);
    b.setPadding(dp(8), 0, dp(8), 0);
    t.addView(b);
    t.setOnClickListener(v -> click.run());
    return t;
  }

  private void postStoryVideo(final java.io.File video) {
    final EditText caption = new EditText(this);
    caption.setHint(I18n.t("Viết gì đó cho tin (không bắt buộc)"));
    new Sheet(this).setTitle(I18n.t("Đăng tin 24 giờ")).setView(caption).setPositiveButton(I18n.t("Chia sẻ tin"), (d, w) -> {
      say(I18n.t("Đang đăng tin…"));
      final String text = caption.getText().toString();
      new Thread(() -> {
        try {
          byte[] bytes = NativeApi.readAll(new java.io.FileInputStream(video));
          final String media = "data:video/mp4;base64," + android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP);
          runOnUiThread(() -> request("POST", "/api/stories", json("body", text, "media", media), r -> { say(I18n.t("Đã đăng tin, hiển thị 24 giờ.")); navigate("feed"); }));
        } catch (Exception e) {
          runOnUiThread(() -> say(I18n.t("Không đọc được video. Vui lòng chọn tệp khác.")));
        }
      }).start();
    }).setNegativeButton(I18n.t("Huỷ"), null).show();
  }


  // Ảnh vừa chụp hiện ngay trong ô tạo bài viết
  private void showComposePreview(java.io.File file) {
    BitmapFactory.Options o = new BitmapFactory.Options();
    o.inSampleSize = 2;
    composeAttached(BitmapFactory.decodeFile(file.getAbsolutePath(), o), false);
  }

  private BitmapFactory.Options sampled(android.net.Uri uri) {
    BitmapFactory.Options o = new BitmapFactory.Options();
    o.inJustDecodeBounds = true;
    try { BitmapFactory.decodeStream(getContentResolver().openInputStream(uri), null, o); } catch (Exception ignored) {}
    o.inSampleSize = Math.max(1, Math.max(o.outWidth, o.outHeight) / 1280);
    o.inJustDecodeBounds = false;
    return o;
  }

  private void composeAttached(Bitmap image, boolean video) {
    if (composePreview == null || !composePreview.isAttachedToWindow()) return;
    composePreview.removeAllViews();
    FrameLayout box = new FrameLayout(this);
    if (image != null) {
      ImageView img = new ImageView(this);
      img.setAdjustViewBounds(true);
      img.setScaleType(ImageView.ScaleType.CENTER_CROP);
      img.setImageBitmap(image);
      img.setBackground(background(SOFT, 16));
      img.setClipToOutline(true);
      box.addView(img, new FrameLayout.LayoutParams(-1, dp(260)));
    } else {
      LinearLayout card = row();
      card.setPadding(dp(14), 0, dp(14), 0);
      card.setBackground(background(PRIMARY_SOFT, 16));
      card.addView(icon("video", 22, ACCENT), new LinearLayout.LayoutParams(dp(22), dp(22)));
      TextView l = label(video ? I18n.t("Video đã chọn") : I18n.t("Tệp đã chọn"), 14, TEXT);
      l.setPadding(dp(10), 0, 0, 0);
      card.addView(l);
      box.addView(card, new FrameLayout.LayoutParams(-1, dp(64)));
    }
    FrameLayout remove = new FrameLayout(this);
    remove.setBackground(background(0x99000000, 99));
    remove.addView(icon("x", 16, WHITE), new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
    remove.setContentDescription(I18n.t("Gỡ tệp"));
    remove.setOnClickListener(v -> { pendingMedia = null; composePreview.removeAllViews(); });
    FrameLayout.LayoutParams rp = new FrameLayout.LayoutParams(dp(32), dp(32), Gravity.TOP | Gravity.END);
    rp.setMargins(0, dp(8), dp(8), 0);
    box.addView(remove, rp);
    LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(-1, -2);
    bp.topMargin = dp(8);
    composePreview.addView(box, bp);
  }


}
