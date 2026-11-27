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
  @Override
  protected void attachBaseContext(android.content.Context base) {
    super.attachBaseContext(I18n.localized(base));
  }

  private final NativeApi api = NativeApi.shared;
  private final Handler handler = new Handler(Looper.getMainLooper());
  private final Handler startupHandler = new Handler(Looper.getMainLooper());
  private android.animation.AnimatorSet splashAnimator;
  private int introTabOverride = -1;
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

  private void refreshPage() {
    if (currentPage != null)
      currentPage.run();
    else
      navigate(tab);
  }

  private int screen = 0;
  private boolean stopped = false;
  private Runnable poll, resumeStory;

  static final class CallPlaybackGate {
    private final Set<String> calls = new HashSet<>();

    void update(String type, String id) {
      if (id == null || id.isEmpty())
        return;
      if (type.equals("call-incoming") || type.equals("call-ringing") || type.equals("call-accepted"))
        calls.add(id);
      else if (type.equals("call-ended"))
        calls.remove(id);
    }

    boolean blocked() {
      return !calls.isEmpty();
    }

    void clear() {
      calls.clear();
    }
  }

  static final class ChatTextPolicy {
    static int mentionIndex(String text, String username) {
      if (text == null || username == null || username.isEmpty())
        return -1;
      String token = "@" + username;
      for (int at = text.indexOf(token); at >= 0; at = text.indexOf(token, at + token.length())) {
        int end = at + token.length();
        char before = at == 0 ? ' ' : text.charAt(at - 1);
        boolean start = at == 0 || Character.isWhitespace(before) || before == '(' || before == '[' || before == '{';
        boolean finish = end == text.length()
            || !(Character.isLetterOrDigit(text.charAt(end)) || "_.-".indexOf(text.charAt(end)) >= 0);
        if (start && finish)
          return at;
      }
      return -1;
    }
  }

  private final CallPlaybackGate mediaCallGate = new CallPlaybackGate();
  private boolean mediaCallBlocked, mediaCallListening;
  private final NativeSocket.Events mediaCallEvents=new NativeSocket.Events(){public void event(JSONObject event){String type=event.optString("type");if(type.equals("ai-stream")){receiveAIStream(event);return;}if(type.equals("notifications-changed")||type.equals("conversations-changed")){handler.post(()->{if(stopped||isFinishing()||isDestroyed())return;if(aiChatReload!=null&&aiChatList!=null&&aiChatList.isAttachedToWindow()){aiChatReload.run();}else if("inbox".equals(tab)&&currentPage!=null){currentPage.run();}});return;}mediaCallGate.update(type,event.optString("callId"));mediaCallBlocked=mediaCallGate.blocked();if(mediaCallBlocked)pauseForCall();}

  public void closed(){aiDrafts.clear();paintAIStream();mediaCallGate.clear();mediaCallBlocked=false;}};

  private void pauseForCall() {
    if (shortVideo != null)
      try {
        shortVideo.pause();
      } catch (RuntimeException ignored) {
      }
    for (VideoView video : mediaVideos)
      try {
        video.pause();
      } catch (RuntimeException ignored) {
      }
    resumeVideos.clear();
  }

  private NativeCalls calls;

  private void onUserSignedIn(JSONObject user) {
    me = user;
    if (NativeApi.isFixtureEnabled())
      return;
    KinnectService.start(this);
    KinnectFirebaseMessagingService.syncTokenWithServer(this);
    ensureCalls();
  }

  private void ensureCalls() {
    if (NativeApi.isFixtureEnabled())
      return;
    if (me != null && !mediaCallListening) {
      mediaCallListening = true;
      KinnectService.listen(mediaCallEvents);
    }
    if (KinnectService.pendingIncoming != null) {
      mediaCallGate.update("call-incoming", KinnectService.pendingIncoming.optString("callId"));
      mediaCallBlocked = mediaCallGate.blocked();
      pauseForCall();
    }
    if (me != null && calls == null) {
      calls = new NativeCalls(this, server());
      setupBackground();
    }
  }

  // Một lần: xin đủ quyền thông báo/cuộc gọi, cho phép toàn màn hình và chạy nền.
  private void setupBackground() {
    if (NativeApi.isFixtureEnabled())
      return;
    if (Distribution.PLAY) {
      if (Build.VERSION.SDK_INT >= 33
          && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED)
        requestPermissions(new String[] { "android.permission.POST_NOTIFICATIONS" }, 950);
      android.content.SharedPreferences pp = getSharedPreferences("native_setup", 0);
      if (!pp.getBoolean("asked_fsi_v1", false)) {
        pp.edit().putBoolean("asked_fsi_v1", true).apply();
        backgroundExtras(true);
      }
      return;
    }
    android.content.SharedPreferences p = getSharedPreferences("native_setup", 0);
    if (p.getBoolean("asked_v1", false)) {
      backgroundExtras(false);
      return;
    }
    p.edit().putBoolean("asked_v1", true).apply();
    java.util.ArrayList<String> want = new java.util.ArrayList<>();
    if (Build.VERSION.SDK_INT >= 33)
      want.add("android.permission.POST_NOTIFICATIONS");
    want.add(Manifest.permission.RECORD_AUDIO);
    want.add(Manifest.permission.CAMERA);
    if (Build.VERSION.SDK_INT >= 31)
      want.add("android.permission.BLUETOOTH_CONNECT");
    java.util.ArrayList<String> missing = new java.util.ArrayList<>();
    for (String w : want)
      if (checkSelfPermission(w) != PackageManager.PERMISSION_GRANTED)
        missing.add(w);
    if (missing.isEmpty())
      backgroundExtras(true);
    else
      requestPermissions(missing.toArray(new String[0]), 950);
  }

  private void backgroundExtras(boolean prompt) {
    try {
      if (Build.VERSION.SDK_INT >= 34
          && !getSystemService(android.app.NotificationManager.class).canUseFullScreenIntent()) {
        if (prompt)
          new Sheet(this).setTitle(I18n.t("Cuộc gọi toàn màn hình"))
              .setMessage(I18n.t("Cho phép Kinnect hiện cuộc gọi đến toàn màn hình, kể cả khi khóa máy."))
              .setPositiveButton(I18n.t("Cho phép"), (d, w) -> {
                try {
                  startActivity(new Intent("android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT",
                      android.net.Uri.parse("package:" + getPackageName())));
                } catch (RuntimeException ignored) {
                }
              }).setNegativeButton(I18n.t("Để sau"), (d, w) -> {
                if (!Distribution.PLAY)
                  battery();
              }).show();
        else if (!Distribution.PLAY)
          battery();
        return;
      }
    } catch (RuntimeException ignored) {
    }
    if (prompt && !Distribution.PLAY)
      battery();
  }

  private void battery() {
    android.os.PowerManager pm = (android.os.PowerManager) getSystemService(POWER_SERVICE);
    if (pm != null && pm.isIgnoringBatteryOptimizations(getPackageName())) {
      say(I18n.t("Đã cho phép chạy ngầm không giới hạn pin."));
      return;
    }
    try {
      startActivity(new Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
          android.net.Uri.parse("package:" + getPackageName())));
    } catch (RuntimeException ignored) {
    }
  }

  private void openAutostartSettings() {
    String m = Build.MANUFACTURER.toLowerCase(java.util.Locale.ROOT);
    Intent i = new Intent();
    try {
      if (m.contains("xiaomi") || m.contains("redmi") || m.contains("poco")) {
        i.setComponent(
            new ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"));
      } else if (m.contains("oppo") || m.contains("realme")) {
        try {
          i.setComponent(new ComponentName("com.coloros.safecenter",
              "com.coloros.safecenter.permission.startup.StartupAppListActivity"));
        } catch (Exception e) {
          i.setComponent(new ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"));
        }
      } else if (m.contains("vivo")) {
        try {
          i.setComponent(new ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"));
        } catch (Exception e) {
          i.setComponent(new ComponentName("com.vivo.permissionmanager",
              "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"));
        }
      } else if (m.contains("huawei") || m.contains("honor")) {
        i.setComponent(new ComponentName("com.huawei.systemmanager",
            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"));
      } else if (m.contains("samsung")) {
        i.setComponent(
            new ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity"));
      } else {
        i = new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            android.net.Uri.parse("package:" + getPackageName()));
      }
      i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      startActivity(i);
    } catch (Exception fallback) {
      try {
        startActivity(new Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            android.net.Uri.parse("package:" + getPackageName())).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
      } catch (Exception ignored) {
      }
    }
  }

  private void handleExtras(Intent intent) {
    if (intent == null)
      return;
    boolean isDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (intent.hasExtra("app_language")) {
      String lang = intent.getStringExtra("app_language");
      if ("vi".equals(lang) || "en".equals(lang))
        try {
          I18n.select(this, lang);
        } catch (Exception ignored) {
        }
    }
    if(isDebug && intent.getBooleanExtra("ui_review_fixture",false)) {
      if (intent.getBooleanExtra("reset_fixture_state", false))
        NativeApi.resetFixtureState(this);
      NativeApi.enableFixture(this, true);
      if (me == null)
        try {
          me = NativeApi.shared.fixtureUser(this);
          onUserSignedIn(me);
        } catch (Exception ignored) {
        }
    }
    final boolean allowDebugRoutes = isDebug && NativeApi.isFixtureEnabled();
    String destination = intent.getStringExtra("commerce_destination");
    if (destination != null) {
      intent.removeExtra("commerce_destination");
      if (destination.equals("splash")) {
        splash();
        return;
      }
      if (destination.equals("intro") || destination.equals("welcome")) {
        introTabOverride = allowDebugRoutes ? intent.getIntExtra("welcome_tab", -1) : -1;
        intro();
        return;
      }
      if (destination.equals("login") || destination.equals("auth_login")) {
        auth(false);
        return;
      }
      if (destination.equals("register") || destination.equals("auth_register")) {
        auth(true);
        return;
      }
      if (destination.equals("forgot") || destination.equals("auth_forgot")) {
        forgot();
        return;
      }
      if (me == null && allowDebugRoutes) {
        try {
          me = NativeApi.shared.fixtureUser(this);
          if (me == null)
            me = new JSONObject(
                "{\"id\":\"u1\",\"username\":\"minhanh\",\"name\":\"Nguyễn Minh Anh\",\"role\":\"user\",\"coins\":12500,\"bio\":\"Kinnect QA Review\",\"followersCount\":128,\"followingCount\":64}");
          onUserSignedIn(me);
        } catch (Exception ignored) {
        }
      }
      if (me != null) {
        if (destination.equals("feed") || destination.equals("feed_home") || destination.equals("feed_dark")
            || destination.equals("feed_font13") || destination.equals("feed_narrow")) {
          navigate("feed");
        } else if (destination.equals("discover") || destination.equals("discover_search")) {
          nearQuery = "";
          navigate("discover");
        } else if (destination.equals("shorts") || destination.equals("shorts_player")) {
          navigate("shorts");
        } else if (destination.equals("inbox") || destination.equals("inbox_list")) {
          navigate("inbox");
        } else if (destination.equals("friends") || destination.equals("friends_list")) {
          headerActive = "";
          friendsScreen("friends");
        } else if (destination.equals("friend_requests") || destination.equals("friends_requests")) {
          headerActive = "";
          friendsScreen("incoming");
        } else if (destination.equals("profile") || destination.equals("profile_main")) {
          navigate("profile");
        } else if (destination.equals("profile_edit")) {
          editProfile();
        } else if (destination.equals("profile_albums")) {
          tab = "profile";
          headerActive = "";
          shell("", true);
          onTabRoot = true;
          profile(2);
        } else if (destination.equals("account") || destination.equals("account_menu")
            || destination.equals("account_dark") || destination.equals("account_font13")) {
          headerActive = "";
          meMenu();
        } else if (destination.equals("appearance_settings")) {
          appearanceScreen();
        } else if (destination.equals("password") || destination.equals("security_password")) {
          changePassword();
        } else if (destination.equals("sessions_devices")) {
          sessionsScreen();
        } else if (destination.equals("notifications") || destination.equals("notifications_screen")) {
          notifications();
        } else if (destination.equals("notifications_settings")) {
          nativeNotificationSettings();
        } else if (destination.equals("privacy_settings")) {
          settings();
        } else if (destination.equals("language") || destination.equals("language_settings")) {
          languageMenu();
        } else if (destination.equals("help_support")) {
          helpScreen();
        } else if (destination.equals("about_screen")) {
          aboutScreen();
        } else if (destination.equals("delete_account_confirm")) {
          deleteAccountScreen();
        } else if (destination.equals("wallet_main")) {
          startActivity(new Intent(this, WalletActivity.class));
        } else if (destination.equals("store") || destination.equals("store_packages")) {
          startActivity(new Intent(this, StoreActivity.class));
        } else if (destination.equals("live") || destination.equals("live_list")) {
          if (allowDebugRoutes)
            NativeApi.setFixtureEmptyLive(this, false);
          navigate("live");
        } else if (destination.equals("create")) {
          openCreateMenu();
        } else if (destination.equals("settings")) {
          settings();
        } else if (allowDebugRoutes) {
          if (destination.equals("feed_story")) {
            navigate("feed");
            try {
              JSONObject s = new JSONObject();
              s.put("id", "st_1");
              s.put("body", "Chào ngày mới đầy năng lượng cùng Kinnect! ✨");
              s.put("created", System.currentTimeMillis() - 3600000L);
              JSONObject a = new JSONObject();
              a.put("id", "u4");
              a.put("name", "Linh Nhi");
              a.put("username", "linhnhi");
              s.put("author", a);
              JSONArray arr = new JSONArray();
              arr.put(s);
              story(arr, 0);
            } catch (Exception ignored) {
            }
          } else if (destination.equals("feed_post_detail")) {
            postDetail("post_1", null);
          } else if (destination.equals("feed_comments") || destination.equals("comments_narrow")) {
            accountHeader(I18n.t("Bình luận"), () -> navigate("feed"), false);
            comments("/api/posts/post_1", () -> {
            }, () -> navigate("feed"), "Bảng tin");
          } else if (destination.equals("feed_reactions")) {
            postDetail("post_1", null);
            reactorsSheet("post_1");
          } else if (destination.equals("discover_results")) {
            nearQuery = "cà phê";
            navigate("discover");
          } else if (destination.equals("discover_empty")) {
            nearQuery = "___khong_tim_thay___";
            navigate("discover");
          } else if (destination.equals("shorts_comments")) {
            navigate("shorts");
            try {
              shortComments(new JSONObject(
                  "{\"id\":\"s1\",\"title\":\"Khoảnh khắc cuộc sống\",\"author\":{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\"},\"comments\":2}"));
            } catch (Exception ignored) {
            }
          } else if (destination.equals("chat_direct")) {
            try {
              chat(new JSONObject(
                  "{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\",\"isActive\":true}"));
            } catch (Exception ignored) {
            }
          } else if (destination.equals("chat_group")) {
            try {
              groupChat(new JSONObject(
                  "{\"id\":\"g1\",\"name\":\"Nhóm Thiết Kế Kinnect\",\"members\":[{\"id\":\"u1\",\"name\":\"Nguyễn Minh Anh\",\"username\":\"minhanh\"},{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\"},{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\"},{\"id\":\"u4\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\"}]}"));
            } catch (Exception ignored) {
            }
          } else if (destination.equals("chat_menu")) {
            try {
              JSONObject mockUser = new JSONObject(
                  "{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\"}");
              chat(mockUser);
              directChatMenu(mockUser);
            } catch (Exception ignored) {
            }
          } else if (destination.equals("message_menu")) {
            try {
              JSONObject mockUser = new JSONObject(
                  "{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\",\"isActive\":true}");
              chat(mockUser);
              messageMenu("direct", new JSONObject(
                  "{\"id\":\"m_1\",\"sender\":\"u3\",\"body\":\"Chào bạn, rất vui được làm quen!\"}"), false,
                  "/api/users/u3/messages", () -> {
                  });
            } catch (Exception ignored) {
            }
          } else if (destination.equals("report_sheet") || destination.equals("ugc_report")) {
            navigate("feed");
            report("user", "u2");
          } else if (destination.equals("live_empty")) {
            NativeApi.setFixtureEmptyLive(this, intent.getBooleanExtra("empty_live", true));
            navigate("live");
          } else if (destination.equals("live_setup_sheet")) {
            startActivity(new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "live"));
          } else if (destination.equals("live_room")) {
            startActivity(new Intent(this, LiveActivity.class).putExtra("fixture_joined_room", true));
          } else if (destination.equals("live_gifts_drawer")) {
            startActivity(
                new Intent(this, LiveActivity.class).putExtra("fixture_joined_room", true).putExtra("show_gifts", true));
          } else if (destination.equals("call_incoming")) {
            try {
              KinnectService.pendingIncoming = new JSONObject(
                  "{\"callId\":\"call_qa_01\",\"from\":{\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\"},\"mode\":\"video\"}");
              startActivity(new Intent(this, IncomingCallActivity.class));
            } catch (Exception ignored) {
            }
          } else if (destination.equals("studio_camera") || destination.equals("studio_photo")) {
            startActivity(new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "photo"));
          } else if (destination.equals("studio_video")) {
            startActivity(new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "video"));
          } else if (destination.equals("studio_edit")) {
            startActivity(new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "photo")
                .putExtra("open_edit", true));
          } else if (destination.equals("studio_effects")) {
            startActivity(new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "photo")
                .putExtra("open_panel", "filter"));
          } else if (destination.equals("studio_music_picker")) {
            startActivity(new Intent(this, StudioActivity.class).putExtra("open_music", true));
          } else if (!destination.isEmpty()) {
            navigate(destination);
          } else {
            navigate("feed");
          }
        } else {
          navigate("feed");
        }
      }
    }
    if (intent.getBooleanExtra("accept_call", false)) {
      intent.removeExtra("accept_call");
      if (Build.VERSION.SDK_INT >= 27) {
        setShowWhenLocked(true);
        setTurnScreenOn(true);
      }
      getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
          | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
      ensureCalls();
      if (calls != null)
        calls.checkPending();
    }
    String n = intent.getStringExtra("notification");
    if (n != null) {
      intent.removeExtra("notification");
      try {
        openNotification(new JSONObject(n));
      } catch (JSONException ignored) {
      }
    } else {
      String fcmKind = intent.getStringExtra("kind");
      if (fcmKind != null && !fcmKind.isEmpty()) {
        JSONObject fcmNotif = new JSONObject();
        try {
          fcmNotif.put("kind", fcmKind);
          String actorId = intent.getStringExtra("actorId");
          String ref = intent.getStringExtra("ref");
          String commentId = intent.getStringExtra("commentId");
          String notifId = intent.getStringExtra("notificationId");
          if (actorId != null)
            fcmNotif.put("actorId", actorId);
          if (ref != null)
            fcmNotif.put("ref", ref);
          if (commentId != null)
            fcmNotif.put("commentId", commentId);
          if (notifId != null)
            fcmNotif.put("id", notifId);
        } catch (JSONException ignored) {
        }
        intent.removeExtra("kind");
        intent.removeExtra("actorId");
        intent.removeExtra("ref");
        intent.removeExtra("commentId");
        intent.removeExtra("notificationId");
        openNotification(fcmNotif);
      }
    }
  }

  private LocationListener locationListener;
  // Màu lấy từ public/theme.css để app và web mobile trông giống nhau; tự theo
  // chế độ sáng/tối của máy.
  private int BG, CARD, TEXT, MUTED, ACCENT, ACCENT_TEXT, SOFT, LINE, PRIMARY_SOFT;
  private static final int PINK = 0xffff4f9a, WHITE = 0xffffffff;

  private void palette() {
    boolean dark = WebTheme.isDark(this);
    int variant = dark ? 1 : 0;
    BG = WebDesign.BG[variant];
    CARD = WebDesign.CARD[variant];
    TEXT = WebDesign.INK[variant];
    MUTED = WebDesign.MUTED_STRICT[variant];
    ACCENT = WebDesign.PURPLE[variant];
    ACCENT_TEXT = WebDesign.PURPLE_TEXT_STRICT[variant];
    SOFT = WebDesign.WASH[variant];
    LINE = WebDesign.LINE[variant];
    PRIMARY_SOFT = WebDesign.SOFT[variant];
  }

  private GradientDrawable gradient(int radius) {
    GradientDrawable d = new GradientDrawable(GradientDrawable.Orientation.TL_BR, WebDesign.HERO_GRADIENT);
    d.setCornerRadius(dp(radius));
    return d;
  }

  private interface Done {
    void accept(JSONObject data);
  }

  @Override
  public void onCreate(Bundle state) {
    boolean night = WebTheme.isDark(this);
    int themeId = getResources().getIdentifier(night ? "Kinnect.App.Dark" : "Kinnect.App.Light", "style",
        getPackageName());
    setTheme(themeId != 0 ? themeId
        : (night ? android.R.style.Theme_Material_NoActionBar : android.R.style.Theme_Material_Light_NoActionBar));
    super.onCreate(state);
    CrashLog.install(this);
    if (Build.VERSION.SDK_INT >= 33)
      getOnBackInvokedDispatcher()
          .registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::handleBack);
    palette();
    boolean isDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (isDebug && getIntent() != null && getIntent().hasExtra("qa_local_loopback_origin")) {
      api.pinDebugLoopback(this, getIntent().getStringExtra("qa_local_loopback_origin"),
          getIntent().getStringExtra("qa_local_loopback_cert_sha256"));
    }
    api.initialize(this, server());
    if (isDebug && getIntent() != null && getIntent().getBooleanExtra("qa_local_loopback_wipe", false)
        && api.pinnedDebugLoopbackOrigin() != null) {
      clearClientSessionCaches();
    }
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    getWindow().getDecorView().setSystemUiVisibility(
        WebTheme.isDark(this) ? 0 : (View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR));
    splash();
    if (isDebug && getIntent() != null && getIntent().getBooleanExtra("ui_review_fixture", false)) {
      if (getIntent().getBooleanExtra("reset_fixture_state", false)) {
        NativeApi.resetFixtureState(this);
      }
      NativeApi.enableFixture(this, true);
      try {
        me = NativeApi.shared.fixtureUser(this);
        onUserSignedIn(me);
        handleExtras(getIntent());
        return;
      } catch (Exception ignored) {
      }
    }
    final long shownAt = System.currentTimeMillis();
    final boolean hasSession = !api.cookieFor(server()).isEmpty()
        || !api.cookieFor(ServerConfig.DEFAULT_ORIGIN).isEmpty();
    if (hasSession) {
      if (api.pinnedDebugLoopbackOrigin() == null)
        KinnectService.start(this);
      api.call("GET", "/api/me", null, (data, error, status) -> {
        if (isDestroyed())
          return;
        long wait = Math.max(0, 450 - (System.currentTimeMillis() - shownAt));
        startupHandler.postDelayed(() -> {
          if (isDestroyed() || isFinishing())
            return;
          JSONObject user = data == null ? null : data.optJSONObject("user");
          if (error == null && user != null) {
            onUserSignedIn(user);
            navigate("feed");
            handleExtras(getIntent());
          } else
            auth(false);
          handleLink(getIntent());
        }, wait);
      });
    } else {
      if (getIntent() != null && getIntent().hasExtra("commerce_destination")) {
        handleExtras(getIntent());
      } else {
        startupHandler.postDelayed(() -> {
          if (!isDestroyed() && !isFinishing()) {
            intro();
            handleLink(getIntent());
          }
        }, 700);
      }
    }
  }

  private void splash() {
    if (splashAnimator != null) {
      splashAnimator.cancel();
      splashAnimator = null;
    }
    float density = getResources().getDisplayMetrics().density;
    int logoPx = Math.round(96f * density);
    final float logoRadius = 22f * density;
    int gapPx = Math.round(18f * density);
    int ringPx = Math.round(22f * density);
    int ringStroke = Math.max(2, Math.round(2.5f * density));
    int ringsWidth = Math.round(96f * density);
    int ringsHeight = Math.round(36f * density);
    float spread = 9f * density;
    float overlap = 5f * density;

    FrameLayout s = new FrameLayout(this);
    s.setClipChildren(false);
    s.setClipToPadding(false);
    s.setBackgroundColor(BG);

    LinearLayout c = column();
    c.setGravity(Gravity.CENTER_HORIZONTAL);
    c.setClipChildren(false);
    c.setClipToPadding(false);

    ImageView logo = new ImageView(this);
    logo.setImageResource(getResources().getIdentifier("kinnect_logo", "drawable", getPackageName()));
    logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
    logo.setElevation(Math.round(12f * density));
    logo.setOutlineProvider(new android.view.ViewOutlineProvider() {
      @Override
      public void getOutline(View view, android.graphics.Outline outline) {
        outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), logoRadius);
      }
    });
    LinearLayout.LayoutParams logoLp = new LinearLayout.LayoutParams(logoPx, logoPx);
    logoLp.gravity = Gravity.CENTER_HORIZONTAL;
    c.addView(logo, logoLp);

    TextView name = label("Kinnect", 26, ACCENT_TEXT);
    name.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 30f);
    name.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    name.setIncludeFontPadding(false);
    name.setSingleLine(true);
    name.setGravity(Gravity.CENTER);
    LinearLayout.LayoutParams nameLp = new LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,
        LinearLayout.LayoutParams.WRAP_CONTENT);
    nameLp.gravity = Gravity.CENTER_HORIZONTAL;
    nameLp.topMargin = gapPx;
    c.addView(name, nameLp);

    FrameLayout rings = new FrameLayout(this);
    rings.setClipChildren(false);
    rings.setClipToPadding(false);
    View[] ringViews = new View[2];
    int[] ringColors = { ACCENT_TEXT, 0xffed45aa };
    boolean animate = android.animation.ValueAnimator.areAnimatorsEnabled();
    for (int i = 0; i < 2; i++) {
      View ring = new View(this);
      GradientDrawable outline = new GradientDrawable();
      outline.setShape(GradientDrawable.OVAL);
      outline.setColor(0x00000000);
      outline.setStroke(ringStroke, ringColors[i]);
      ring.setBackground(outline);
      float initialOffset = animate ? (i == 0 ? -spread : spread) : (i == 0 ? -overlap : overlap);
      ring.setTranslationX(initialOffset);
      FrameLayout.LayoutParams rp = new FrameLayout.LayoutParams(ringPx, ringPx, Gravity.CENTER);
      rings.addView(ring, rp);
      ringViews[i] = ring;
    }
    LinearLayout.LayoutParams space = new LinearLayout.LayoutParams(ringsWidth, ringsHeight);
    space.gravity = Gravity.CENTER_HORIZONTAL;
    space.topMargin = gapPx;
    c.addView(rings, space);

    s.addView(c, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT,
        FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER));
    setContentView(s);
    getWindow().setStatusBarColor(BG);
    getWindow().setNavigationBarColor(BG);

    if (animate) {
      android.view.animation.Interpolator ease = new android.view.animation.AccelerateDecelerateInterpolator();
      android.animation.ObjectAnimator pulseX = android.animation.ObjectAnimator.ofFloat(logo, View.SCALE_X, 1f, 1.05f);
      android.animation.ObjectAnimator pulseY = android.animation.ObjectAnimator.ofFloat(logo, View.SCALE_Y, 1f, 1.05f);
      android.animation.ObjectAnimator move0 = android.animation.ObjectAnimator.ofFloat(ringViews[0],
          View.TRANSLATION_X, -spread, -overlap);
      android.animation.ObjectAnimator move1 = android.animation.ObjectAnimator.ofFloat(ringViews[1],
          View.TRANSLATION_X, spread, overlap);
      for (android.animation.ObjectAnimator anim : new android.animation.ObjectAnimator[] { pulseX, pulseY, move0,
          move1 }) {
        anim.setDuration(600);
        anim.setInterpolator(ease);
        anim.setRepeatCount(android.animation.ValueAnimator.INFINITE);
        anim.setRepeatMode(android.animation.ValueAnimator.REVERSE);
      }
      splashAnimator = new android.animation.AnimatorSet();
      splashAnimator.playTogether(pulseX, pulseY, move0, move1);
      splashAnimator.start();
    }
  }

  private String server() {
    String pinned = api.pinnedDebugLoopbackOrigin();
    return pinned != null ? pinned : ServerConfig.DEFAULT_ORIGIN;
  }

  private int dp(int n) {
    return Math.round(n * getResources().getDisplayMetrics().density * WebDesign.UI_SCALE);
  }

  private GradientDrawable background(int color, int radius) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    return d;
  }

  private android.graphics.drawable.Drawable pressable(int color, int radius) {
    GradientDrawable mask = background(0xff000000, radius);
    return new android.graphics.drawable.RippleDrawable(
        android.content.res.ColorStateList.valueOf((ACCENT & 0x00ffffff) | 0x33000000), background(color, radius),
        mask);
  }

  // Giải mã entity HTML (&#127752;, &amp;…) mà server trả về trong nội dung bài
  // viết/tin nhắn.
  // Lặp tối đa 4 lần vì server đôi khi mã hoá 2 lớp (vd &amp;#127752;).
  private String decodeEntities(String s) {
    if (s == null || s.indexOf('&') < 0)
      return s;
    java.util.regex.Pattern p = java.util.regex.Pattern
        .compile("&#(\\d+);|&#[xX]([0-9a-fA-F]+);|&(amp|lt|gt|quot|apos|nbsp);");
    String out = s;
    for (int pass = 0; pass < 4 && out.indexOf('&') >= 0; pass++) {
      java.util.regex.Matcher m = p.matcher(out);
      StringBuffer next = new StringBuffer();
      boolean changed = false;
      while (m.find()) {
        String rep;
        if (m.group(1) != null || m.group(2) != null) {
          int cp = 0;
          try {
            cp = m.group(1) != null ? Integer.parseInt(m.group(1)) : Integer.parseInt(m.group(2), 16);
          } catch (NumberFormatException ignored) {
          }
          rep = Character.isValidCodePoint(cp) ? new String(Character.toChars(cp)) : m.group();
        } else {
          String n = m.group(3);
          rep = n.equals("amp") ? "&"
              : n.equals("lt") ? "<" : n.equals("gt") ? ">" : n.equals("quot") ? "\"" : n.equals("apos") ? "'" : " ";
        }
        m.appendReplacement(next, java.util.regex.Matcher.quoteReplacement(rep));
        changed = true;
      }
      if (!changed)
        break;
      m.appendTail(next);
      out = next.toString();
    }
    return out;
  }

  private TextView label(String text, int size, int color) {
    TextView v = new KinnectText(this);
    v.setText(decodeEntities(text));
    v.setTextColor(color);
    v.setTextSize(size);
    v.setIncludeFontPadding(false);
    v.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
    if (size <= 16)
      v.setLineSpacing(dp(3), 1f);
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
    int min48 = UiMetrics.dpRaw(this, 48);
    Button b = new KinnectButton(this);
    b.setText(text);
    b.setTextColor(TEXT);
    b.setTextSize(WebDesign.LABEL);
    b.setIncludeFontPadding(false);
    b.setGravity(Gravity.CENTER);
    b.setMinHeight(min48);
    b.setMinimumHeight(min48);
    b.setMinimumWidth(min48);
    b.setAllCaps(false);
    b.setStateListAnimator(null);
    b.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
    b.setTextSize(14);
    GradientDrawable tonal = background(SOFT, 99); // Nút dạng Pill theo M3
    b.setBackground(new android.graphics.drawable.RippleDrawable(
        android.content.res.ColorStateList.valueOf((ACCENT & 0x00ffffff) | 0x28000000),
        tonal,
        background(0xff000000, 99)));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, min48);
    p.setMargins(0, dp(6), 0, dp(4));
    b.setLayoutParams(p);
    b.setOnClickListener(v -> action.run());
    UiMetrics.enforceMinTouchTarget(b, 48);
    return b;
  }

  private Button primary(String text, Runnable action) {
    Button b = button(text, action);
    b.setTextColor(WHITE);
    b.setBackground(new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(0x33ffffff),
        brandGradient(99), null));
    b.setElevation(dp(0));
    tactile(b);
    return b;
  }

  /**
   * Trộn hai màu để tạo gradient thương hiệu nhưng vẫn giữ tương phản chữ trắng ≥
   * 4.5:1.
   */
  private int mix(int a, int b, float t) {
    float u = 1f - t;
    return 0xff000000
        | (Math.round(((a >> 16) & 0xff) * u + ((b >> 16) & 0xff) * t) << 16)
        | (Math.round(((a >> 8) & 0xff) * u + ((b >> 8) & 0xff) * t) << 8)
        | Math.round((a & 0xff) * u + (b & 0xff) * t);
  }

  private GradientDrawable brandGradient(int radius) {
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, WebDesign.HERO_GRADIENT);
    g.setCornerRadius(dp(radius));
    return g;
  }

  /**
   * Phản hồi chạm nhẹ (scale) cho CTA/nút hành động — không chặn sự kiện click.
   */
  private void tactile(View v) {
    v.setOnTouchListener((view, event) -> {
      switch (event.getActionMasked()) {
        case android.view.MotionEvent.ACTION_DOWN:
          view.animate().scaleX(0.96f).scaleY(0.96f).setDuration(WebDesign.MOTION_FAST).start();
          break;
        case android.view.MotionEvent.ACTION_UP:
        case android.view.MotionEvent.ACTION_CANCEL:
          view.animate().scaleX(1f).scaleY(1f).setDuration(WebDesign.MOTION_BASE).start();
          break;
      }
      return false;
    });
  }

  private EditText input(
      LinearLayout parent,
      String hint,
      String value,
      boolean multiline) {
    EditText v = new KinnectInput(this);
    v.setHint(hint);
    v.setContentDescription(hint);
    v.setText(value);
    v.setTextColor(TEXT);
    v.setHintTextColor(MUTED);
    v.setTextSize(15);
    v.setSingleLine(!multiline);
    v.setPadding(dp(16), dp(16), dp(16), dp(16)); // Tăng padding
    GradientDrawable idle = background(CARD, 16); // M3 góc rộng hơn
    idle.setStroke(dp(1), LINE);
    GradientDrawable focused = background(CARD, 16);
    focused.setStroke(dp(2), ACCENT);
    android.graphics.drawable.StateListDrawable states = new android.graphics.drawable.StateListDrawable();
    states.addState(new int[] { android.R.attr.state_focused }, focused);
    states.addState(new int[0], idle);
    v.setBackground(states);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
        -1,
        multiline ? dp(112) : Math.max(dp(56), UiMetrics.dpRaw(this, 48))
    );
    p.setMargins(0, dp(8), 0, dp(12));
    parent.addView(v, p);
    UiMetrics.enforceMinTouchTarget(v, 48);
    return v;
  }

  private LinearLayout card() {
    LinearLayout v = column();
    v.setPadding(dp(20), dp(20), dp(20), dp(20)); // Padding to hơn
    GradientDrawable cardBg = background(CARD, WebDesign.CARD_RADIUS);
    cardBg.setStroke(1, LINE); // Nền M3 cũng mỏng
    v.setBackground(cardBg);
    v.setElevation(dp(2)); // Nổi nhẹ (Surface Container Low/High)
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.setMargins(0, dp(8), 0, dp(8));
    content.addView(v, p);
    return v;
  }

  private boolean onTabRoot = false;
  private boolean inAccountSubPage = false;
  private LinearLayout headActions;
  private TextView inboxBadge, bellBadge, friendsBadge;
  private int friendsCount;
  private int inboxCount, bellCount;
  private long badgesAt;
  private String badgeAccount = "";
  private String pendingDownload = "";
  private long noticeWatermark = System.currentTimeMillis();
  private final Handler notificationHandler = new Handler(Looper.getMainLooper());
  private final Runnable notificationPoll=new Runnable(){public void run(){if(!stopped){refreshBadges();notificationHandler.postDelayed(this,20000);}}};

  private void installChatKeyboard(EditText input, ScrollView messages) {
    input.setTag("chat-compose");
    input.setOnFocusChangeListener((v, has) -> {
      if (has)
        messages.post(() -> messages.fullScroll(View.FOCUS_DOWN));
    });
    messages.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, oright, ob) -> {
      if (input.hasFocus() && b - t < ob - ot)
        messages.post(() -> messages.fullScroll(View.FOCUS_DOWN));
    });
  }

  private void revealKeyboardFocus() {
    View focused = getCurrentFocus();
    if (!(focused instanceof EditText))
      return;
    if ("chat-compose".equals(focused.getTag()) && aiChatScroll != null && aiChatScroll.isAttachedToWindow())
      aiChatScroll.post(() -> aiChatScroll.fullScroll(View.FOCUS_DOWN));
    else
      focused.requestRectangleOnScreen(
          new android.graphics.Rect(0, -dp(90), focused.getWidth(), focused.getHeight() + dp(12)), true);
  }

  private interface RefreshLoader {
    void run(Runnable complete);
  }

  private RefreshLoader feedRefresh, peopleRefresh;
  private boolean shortRefreshing;
  private PullRefreshScrollView retainedFeed;
  private LinearLayout retainedFeedContent;
  private RefreshLoader retainedFeedRefresh;
  private final ArrayList<VideoView> retainedFeedVideos = new ArrayList<>();

  private void shell(String title, boolean navigation) {
    if (feedRefresh != null && content != null && content.getParent() instanceof ScrollView)
      feedScrollY = ((ScrollView) content.getParent()).getScrollY();
    if (feedRefresh != null && feedRows != null && content != null
        && content.getParent() instanceof PullRefreshScrollView) {
      retainedFeed = (PullRefreshScrollView) content.getParent();
      retainedFeedContent = content;
      retainedFeedRefresh = feedRefresh;
      retainedFeedVideos.clear();
      retainedFeedVideos.addAll(mediaVideos);
      if (retainedFeed.getParent() instanceof ViewGroup)
        ((ViewGroup) retainedFeed.getParent()).removeView(retainedFeed);
    }
    feedRefresh = null;
    peopleRefresh = null;
    shortRefreshing = false;
    reelViewport = null;
    onTabRoot = false;
    inAccountSubPage = false;
    if (splashAnimator != null) {
      splashAnimator.cancel();
      splashAnimator = null;
    }
    for (VideoView video : mediaVideos) {
      try {
        if (retainedFeedVideos.contains(video))
          video.pause();
        else
          video.stopPlayback();
      } catch (RuntimeException ignored) {
      }
    }
    mediaVideos.clear();
    resumeVideos.clear();
    stopShort();
    stopLocation();
    screen++;
    preparingPostMedia = false;
    handler.removeCallbacksAndMessages(null);
    poll = null;
    resumeStory = null;
    chatUser = null;
    chatReload = null;
    aiChatReload = null;
    aiChatList = null;
    aiChatScroll = null;
    aiChatSender = "";
    feedLoadingMore = false;
    profileEditorAvatar = null;
    toolbarAvatar = null;
    if (!"store".equals(headerActive))
      closeStoreUi();
    root = column();
    bottom = null;
    root.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
      if (r - l != or - ol || b - t != ob - ot)
        adaptShell();
    });
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener((v, insets) -> {
      if (Build.VERSION.SDK_INT >= 30) {
        android.graphics.Insets bars = insets.getInsets(android.view.WindowInsets.Type.systemBars());
        android.graphics.Insets keyboard = insets.getInsets(android.view.WindowInsets.Type.ime());
        v.setPadding(bars.left, bars.top, bars.right, Math.max(bars.bottom, keyboard.bottom));
        if (keyboard.bottom > bars.bottom)
          v.post(this::revealKeyboardFocus);
      } else
        v.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
      return insets;
    });
    setContentView(root);
    root.setAlpha(0f);
    root.setTranslationY(dp(10));
    root.setTranslationX(dp(navBack != 0 ? -14 : 0));
    root.animate().alpha(1f).translationY(0f).translationX(0f).setDuration(WebDesign.MOTION_BASE)
        .setInterpolator(new android.view.animation.DecelerateInterpolator()).start();
    navBack = 0;
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    getWindow().getDecorView().setSystemUiVisibility(
        WebTheme.isDark(this) ? 0 : (View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR));
    // Thanh trên giống web: logo · Live · Tin nhắn · Thông báo · tài khoản
    toolbar = row();
    toolbar.setPadding(dp(14), 0, dp(8), 0); // Thu nhỏ lề phải, dịch cụm biểu tượng sang phải
    toolbar.setBackgroundColor(CARD);
    toolbar.setElevation(dp(2)); // Drop shadow nhẹ ở Top App Bar
    ImageView logo = new ImageView(this);
    logo.setImageResource(getResources().getIdentifier("kinnect_logo", "drawable", getPackageName()));
    logo.setClipToOutline(true);
    logo.setBackground(background(CARD, 12));
    toolbar.addView(logo, new LinearLayout.LayoutParams(dp(40), dp(40))); // Logo to hơn
    toolbar.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    int raw48 = UiMetrics.dpRaw(this, 48);
    if (me != null && navigation) {
      toolbar.addView(
          topIcon("bell", I18n.t("Thông báo"), "bell".equals(headerActive), this::toggleNotifications, "bell"));
      toolbar.addView(topIcon("store", I18n.t("Cửa hàng"), "store".equals(headerActive), this::toggleStore, null));
      toolbar.addView(topIcon("users_round", I18n.t("Bạn bè"), "friends".equals(headerActive), () -> {
        if ("friends".equals(headerActive)) {
          headerActive = "";
          navigate(tab.isEmpty() ? "feed" : tab);
        } else {
          friendsScreen(friendsCount > 0 ? "incoming" : "friends");
        }
      }, "friends"));
      toolbar.addView(topIcon("message_square", I18n.t("Tin nhắn"), "inbox".equals(headerActive), () -> {
        if ("inbox".equals(headerActive)) {
          headerActive = "";
          navigate("feed");
        } else {
          navigate("inbox");
        }
      }, "inbox"));
      FrameLayout meHolder = new FrameLayout(this);
      boolean meActive = "account".equals(headerActive);
      meHolder.setBackground(pressable(meActive ? PRIMARY_SOFT : CARD, 99));
      ImageView meButton = new ImageView(this);
      meButton.setScaleType(ImageView.ScaleType.CENTER_CROP);
      GradientDrawable round = new GradientDrawable();
      round.setShape(GradientDrawable.OVAL);
      round.setColor(PRIMARY_SOFT);
      if (meActive) {
        round.setStroke(dp(2), ACCENT);
      }
      meButton.setBackground(round);
      meButton.setClipToOutline(true);
      meButton.setImageBitmap(initials(me, dp(40)));
      toolbarAvatar = meButton;
      loadAvatarInto(me, meButton);
      meHolder.addView(meButton, new FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER));
      meHolder.setContentDescription(I18n.t("Tài khoản"));
      meHolder.setOnClickListener(v -> meMenu());
      LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(raw48, raw48);
      toolbar.addView(meHolder, mp);
      UiMetrics.enforceMinTouchTarget(meHolder, 48);
      refreshBadges();
    } else if (me == null) {
      ImageView settings = icon("settings", 22, MUTED);
      settings.setPadding(dp(10), dp(10), dp(10), dp(10));
      settings.setContentDescription(I18n.t("Cài đặt"));
      settings.setOnClickListener(v -> settings());
      toolbar.addView(settings, new LinearLayout.LayoutParams(raw48, raw48));
      UiMetrics.enforceMinTouchTarget(settings, 48);
    }
    root.addView(toolbar, new LinearLayout.LayoutParams(-1, UiMetrics.dpRaw(this, UiMetrics.HEADER_HEIGHT)));
    if (calls != null)
      root.post(() -> {
        if (calls != null)
          calls.attachReturn(root);
      });
    View line = new View(this);
    line.setBackgroundColor(LINE);
    root.addView(line, new LinearLayout.LayoutParams(-1, 1));
    notice = label("", 12, ACCENT_TEXT);
    notice.setPadding(dp(16), 0, dp(16), 0);
    notice.setVisibility(View.GONE);
    root.addView(notice);
    PullRefreshScrollView scroll = new PullRefreshScrollView(this);
    scroll.setRefreshListener(new PullRefreshScrollView.Listener() {
      public boolean enabled() {
        return feedRefresh != null || peopleRefresh != null;
      }

      public void refresh(Runnable complete) {
        if (peopleRefresh != null)
          peopleRefresh.run(complete);
        else if (feedRefresh != null)
          feedRefresh.run(complete);
        else
          complete.run();
      }
    });
    scroll.setFillViewport(true);
    content = column();
    content.setPadding(dp(16), dp(14), dp(16), dp(64));
    scroll.addView(content);
    LinearLayout.LayoutParams viewport = new LinearLayout.LayoutParams(
        Math.min(getResources().getDisplayMetrics().widthPixels, dp(720)), 0, 1);
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
      bottom.setPadding(dp(4), dp(2), dp(4), dp(2));
      String[][] items = { { "feed", "house", "Bảng tin" }, { "discover", "compass", "Khám phá" },
          { "create", "plus", "Tạo" }, { "shorts", "clapperboard", "Video" }, { "live", "radio", "Live" } };
      for (final String[] it : items) {
        if (it[0].equals("create")) {
          FrameLayout holder = new FrameLayout(this);
          FrameLayout plus = new FrameLayout(this);
          GradientDrawable plusBg = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
              WebDesign.HERO_GRADIENT);
          plusBg.setCornerRadius(dp(16)); // Google Material 3 squircle FAB
          plus.setBackground(plusBg);
          plus.setElevation(dp(4));
          plus.addView(icon("plus", 22, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
          plus.setContentDescription(I18n.t("Tạo nội dung"));
          plus.setTooltipText(I18n.t("Tạo nội dung"));
          plus.setOnClickListener(v -> openCreateMenu());
          plus.setLayoutParams(new FrameLayout.LayoutParams(dp(46), dp(40)));
          FrameLayout plusWrap = UiMetrics.wrapMinTouchTarget(this, plus, 48);
          tactile(plusWrap);
          holder.addView(plusWrap, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
          bottom.addView(holder, new LinearLayout.LayoutParams(0, Math.max(dp(64), raw48), 1));
          continue;
        }
        boolean active = headerActive.isEmpty() && tab.equals(it[0]);
        LinearLayout b = column();
        b.setGravity(Gravity.CENTER);
        FrameLayout pill = new FrameLayout(this);
        if (active)
          pill.setBackground(background(PRIMARY_SOFT, 99)); // Dạng pill chuẩn Pixel
        pill.addView(icon(it[1], 24, active ? ACCENT_TEXT : MUTED),
            new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER)); // Tăng size icon cho dễ nhìn
        b.addView(pill, new LinearLayout.LayoutParams(dp(64), dp(32)));
        TextView t = label(I18n.t(it[2]), 12, active ? ACCENT_TEXT : MUTED);
        t.setPadding(dp(2), dp(4), dp(2), 0);
        t.setGravity(Gravity.CENTER);
        t.setSingleLine(true);
        t.setMaxLines(1);
        t.setAutoSizeTextTypeUniformWithConfiguration(9, 12, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
        t.setEllipsize(android.text.TextUtils.TruncateAt.END);
        t.setTypeface(Typeface.create("sans-serif-medium", active ? Typeface.BOLD : Typeface.NORMAL));
        b.addView(t, new LinearLayout.LayoutParams(-1, -2));
        b.setContentDescription(I18n.t(it[2]));
        b.setSelected(active);
        b.setFocusable(true);
        b.setTooltipText(I18n.t(it[2]));
        b.setBackground(pressable(CARD, 16));
        b.setOnClickListener(v -> selectNavigation(it[0]));
        bottom.addView(b, new LinearLayout.LayoutParams(0, Math.max(dp(68), raw48), 1));
        UiMetrics.enforceMinTouchTarget(b, 48);
      }
      root.addView(bottom);
    }
  }

  // Relayout existing views so rotation keeps drafts, scroll positions and
  // playback.
  private void adaptShell() {
    if (root == null || toolbar == null || toolbar.getParent() != root)
      return;
    boolean compact = root.getWidth() > root.getHeight();
    if (toolbar.getVisibility() == View.VISIBLE) {
      ViewGroup.LayoutParams hp = toolbar.getLayoutParams();
      int headerHeight = UiMetrics.dpRaw(this, compact ? 48 : UiMetrics.HEADER_HEIGHT);
      if (hp.height != headerHeight) {
        hp.height = headerHeight;
        toolbar.setLayoutParams(hp);
      }
    }
    int available = root.getWidth() - root.getPaddingLeft() - root.getPaddingRight();
    for (int i = 0; i < root.getChildCount(); i++) {
      View child = root.getChildAt(i);
      if (!(child instanceof ScrollView))
        continue;
      LinearLayout.LayoutParams vp = (LinearLayout.LayoutParams) child.getLayoutParams();
      int width = Math.min(available, dp(compact ? 1120 : 720));
      if (width > 0 && vp.width != width) {
        vp.width = width;
        child.setLayoutParams(vp);
      }
    }
    if (bottom == null || bottom.getParent() != root || bottom.getVisibility() != View.VISIBLE)
      return;
    for (int i = 0; i < bottom.getChildCount(); i++) {
      View child = bottom.getChildAt(i);
      ViewGroup.LayoutParams lp = child.getLayoutParams();
      int height = compact ? UiMetrics.dpRaw(this, 48) : Math.max(dp(68), UiMetrics.dpRaw(this, 48));
      if (lp.height != height) {
        lp.height = height;
        child.setLayoutParams(lp);
      }
      if (child instanceof LinearLayout) {
        LinearLayout cell = (LinearLayout) child;
        int orientation = compact ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL;
        if (cell.getOrientation() != orientation)
          cell.setOrientation(orientation);
        if (cell.getChildCount() > 1 && cell.getChildAt(1) instanceof TextView) {
          TextView caption = (TextView) cell.getChildAt(1);
          caption.setPadding(compact ? dp(4) : dp(2), compact ? 0 : dp(4), compact ? dp(2) : dp(2), 0);
          caption.setGravity(compact ? Gravity.START | Gravity.CENTER_VERTICAL : Gravity.CENTER);
          LinearLayout.LayoutParams capLp = (LinearLayout.LayoutParams) caption.getLayoutParams();
          int targetCapW = compact ? 0 : -1;
          float targetWeight = compact ? 1f : 0f;
          if (capLp.width != targetCapW || capLp.weight != targetWeight) {
            capLp.width = targetCapW;
            capLp.weight = targetWeight;
            caption.setLayoutParams(capLp);
          }
          ViewGroup.LayoutParams pill = cell.getChildAt(0).getLayoutParams();
          int width = dp(compact ? 40 : 64);
          if (pill.width != width) {
            pill.width = width;
            cell.getChildAt(0).setLayoutParams(pill);
          }
        }
      }
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
    int raw48 = UiMetrics.dpRaw(this, 48);
    FrameLayout f = new FrameLayout(this);
    ImageView i = icon(name, 22, active ? ACCENT_TEXT : TEXT);
    f.addView(i, new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
    f.setBackground(pressable(active ? PRIMARY_SOFT : CARD, 99));
    if (badgeKey != null) {
      TextView badge = label("", 1, WHITE);
      GradientDrawable bd = background(WebDesign.DANGER[WebTheme.isDark(this) ? 1 : 0], 99);
      bd.setStroke(dp(2), CARD);
      badge.setBackground(bd);
      badge.setVisibility(View.GONE);
      FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(dp(10), dp(10), Gravity.TOP | Gravity.END);
      bp.setMargins(0, dp(6), dp(6), 0);
      f.addView(badge, bp);
      if (badgeKey.equals("inbox"))
        inboxBadge = badge;
      else if (badgeKey.equals("friends"))
        friendsBadge = badge;
      else
        bellBadge = badge;
      showBadge(badge, badgeKey.equals("inbox") ? inboxCount : badgeKey.equals("friends") ? friendsCount : bellCount);
    }
    f.setContentDescription(label);
    f.setOnClickListener(v -> action.run());
    f.setLayoutParams(new LinearLayout.LayoutParams(raw48, raw48));
    UiMetrics.enforceMinTouchTarget(f, 48);
    return f;
  }

  private void showBadge(TextView badge, int count) {
    if (badge == null)
      return;
    badge.setText("");
    badge.setContentDescription(count > 0 ? count + I18n.t(" mục chưa xem") : null);
    badge.setVisibility(count > 0 ? View.VISIBLE : View.GONE);
  }

  private void refreshBadges() {
    if (me == null)
      return;
    final String accountId = me.optString("id");
    if (!badgeAccount.equals(accountId)) {
      badgeAccount = accountId;
      badgesAt = 0;
      inboxCount = 0;
      bellCount = 0;
      noticeWatermark = System.currentTimeMillis();
    }
    if (System.currentTimeMillis() - badgesAt < 10000)
      return;
    badgesAt = System.currentTimeMillis();
    api.call("GET", "/api/notifications", null, (d, e, s) -> {
      if (e != null || d == null || me == null || !accountId.equals(me.optString("id")))
        return;
      JSONArray rows = d.optJSONArray("notifications");
      int inbox = 0, bell = 0, friends = 0;
      long watermark = noticeWatermark;
      JSONObject newest = null;
      for (int i = 0; rows != null && i < rows.length(); i++) {
        JSONObject n = rows.optJSONObject(i);
        if (n.optInt("seen") != 0)
          continue;
        String k = n.optString("kind");
        if (n.optLong("created") > watermark) {
          watermark = n.optLong("created");
          newest = n;
        }
        if (k.equals("message") || k.equals("group_message"))
          inbox++;
        else
          bell++;
      }
      noticeWatermark = watermark;
      if (newest != null && !stopped && getSharedPreferences("kinnect_notifications", 0).getBoolean("enabled", true)) {
        String kind = newest.optString("kind");
        String preference = kind.equals("message") || kind.equals("group_message") ? "messages"
            : kind.startsWith("friend_") ? "friends" : "posts";
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

  private final android.util.LruCache<String, Bitmap> avatarCache=new android.util.LruCache<String,Bitmap>(4096){protected int sizeOf(String key,Bitmap value){return Math.max(1,value.getAllocationByteCount()/1024);}};
  private int avatarRevision;
  private final java.util.WeakHashMap<ImageView, String> avatarViews = new java.util.WeakHashMap<>();
  private ImageView toolbarAvatar;

  private void clearInMemorySessionCaches() {
    avatarCache.evictAll();
    MediaImageLoader.clear();
    clearRetainedFeed();
    feedRows = null;
  }

  private void clearClientSessionCaches() {
    api.clear();
    clearInMemorySessionCaches();
  }

  private void handleUnauthorized() {
    me = null;
    if (api.isOriginSwitchAuthRequired()) {
      api.clearTransientSession();
      clearInMemorySessionCaches();
    } else {
      clearClientSessionCaches();
    }
    auth(false);
  }

  private Bitmap decodeAvatarBitmap(byte[] bytes) {
    return MediaImageLoader.decodeSampledBitmap(bytes, 256);
  }

  private String resolvedAvatarPath(JSONObject u) {
    if (u == null)
      return "";
    String uid = u.optString("id");
    if (me != null && !uid.isEmpty() && uid.equals(me.optString("id"))) {
      String myAvatar = me.optString("avatar", "");
      if (!myAvatar.isEmpty() && !"null".equals(myAvatar))
        return myAvatar;
    }
    String path = u.optString("avatar", "");
    return "null".equals(path) ? "" : path;
  }

  private void applyUpdatedAvatar(JSONObject updated, byte[] uploadedBytes) {
    if (updated == null)
      return;
    me = updated;
    avatarRevision++;
    avatarCache.evictAll();
    MediaImageLoader.clear();
    api.clearSnapshots();
    clearRetainedFeed();
    feedRows = null;
    String newPath = updated.optString("avatar", "");
    if ("null".equals(newPath))
      newPath = "";
    Bitmap decoded = uploadedBytes != null ? decodeAvatarBitmap(uploadedBytes) : null;
    if (decoded != null && !newPath.isEmpty()) {
      avatarCache.put(api.origin() + ":" + newPath, decoded);
      api.cacheImageBytes(newPath, uploadedBytes);
    }
    String myId = me.optString("id");
    java.util.Set<ImageView> refreshed = java.util.Collections.newSetFromMap(new java.util.IdentityHashMap<>());
    for (java.util.Map.Entry<ImageView, String> binding : new java.util.ArrayList<>(avatarViews.entrySet())) {
      ImageView view = binding.getKey();
      if (view == null || !myId.equals(binding.getValue()))
        continue;
      if (view.isAttachedToWindow() || view == toolbarAvatar || view == profileEditorAvatar) {
        refreshed.add(view);
        if (decoded != null)
          view.setImageBitmap(decoded);
        else
          loadAvatarInto(me, view);
      }
    }
    if (toolbarAvatar != null && !refreshed.contains(toolbarAvatar)) {
      if (decoded != null) {
        avatarViews.put(toolbarAvatar, myId);
        toolbarAvatar.setImageBitmap(decoded);
      } else
        loadAvatarInto(me, toolbarAvatar);
    }
    if (profileEditorAvatar != null && profileEditorAvatar.isAttachedToWindow()
        && !refreshed.contains(profileEditorAvatar)) {
      if (decoded != null) {
        avatarViews.put(profileEditorAvatar, myId);
        profileEditorAvatar.setImageBitmap(decoded);
      } else
        loadAvatarInto(me, profileEditorAvatar);
    }
  }

  private static final int TAG_AVATAR_KEY = 0x7f0f0041;

  private void loadAvatarInto(JSONObject u, final ImageView image) {
    if (u != null)
      avatarViews.put(image, u.optString("id"));
    String path = resolvedAvatarPath(u);
    if (path.isEmpty())
      return;
    final String cacheKey = api.origin() + ":" + path;
    final int revision = avatarRevision;
    image.setTag(TAG_AVATAR_KEY, cacheKey);
    Bitmap cached = avatarCache.get(cacheKey);
    if (cached != null) {
      image.setImageBitmap(cached);
      return;
    }
    byte[] saved = api.cachedImage(path);
    if (saved != null) {
      MediaImageLoader.decodeAsync(saved, 256, b -> {
        if (b != null && !isDestroyed() && revision == avatarRevision) {
          avatarCache.put(cacheKey, b);
          if (cacheKey.equals(image.getTag(TAG_AVATAR_KEY)))
            image.setImageBitmap(b);
        }
      });
    }
    if (path.startsWith("data:image/")) {
      try {
        byte[] bytes = android.util.Base64.decode(path.substring(path.indexOf(',') + 1), android.util.Base64.DEFAULT);
        MediaImageLoader.decodeAsync(bytes, 256, b -> {
          if (b != null && !isDestroyed() && cacheKey.equals(image.getTag(TAG_AVATAR_KEY)))
            image.setImageBitmap(b);
        });
      } catch (Exception ignored) {
      }
      return;
    }
    api.image(path, bytes -> {
      if (bytes == null || isDestroyed() || revision != avatarRevision)
        return;
      MediaImageLoader.decodeAsync(bytes, 256, b -> {
        if (b != null && !isDestroyed() && revision == avatarRevision) {
          avatarCache.put(cacheKey, b);
          if (cacheKey.equals(image.getTag(TAG_AVATAR_KEY)))
            image.setImageBitmap(b);
        }
      });
    });
  }

  // Chip kiểu web: viền mảnh, nền trắng; đang chọn → nền tím nhạt chữ tím (soft)
  // hoặc tím đặc (solid)
  private TextView webChip(String text, boolean active, boolean solid, Runnable action) {
    int raw48 = UiMetrics.dpRaw(this, 48);
    TextView t = label(text, 15, active ? (solid ? WHITE : ACCENT_TEXT) : TEXT); // Font 15
    t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
    t.setGravity(Gravity.CENTER);
    t.setPadding(dp(20), 0, dp(20), 0); // Padding cho chuẩn
    GradientDrawable g = background(active ? (solid ? ACCENT : PRIMARY_SOFT) : CARD, 999);
    if (!active)
      g.setStroke(dp(1), LINE); // stroke 1dp
    t.setBackground(g);
    t.setMinWidth(raw48);
    t.setMinHeight(raw48);
    t.setOnClickListener(v -> action.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, raw48);
    p.setMargins(0, dp(4), dp(8), dp(4));
    t.setLayoutParams(p);
    UiMetrics.enforceMinTouchTarget(t, 48);
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

  private void installSubHeader(String title, Runnable back, boolean keepBottom) {
    if (toolbar != null)
      toolbar.setVisibility(View.GONE);
    if (root.getChildCount() > 1)
      root.getChildAt(1).setVisibility(View.GONE);
    if (!keepBottom && bottom != null) {
      int bi = root.indexOfChild(bottom);
      if (bi > 0)
        root.getChildAt(bi - 1).setVisibility(View.GONE);
      bottom.setVisibility(View.GONE);
    }
    int raw48 = UiMetrics.dpRaw(this, 48);
    LinearLayout heading = row();
    heading.setPadding(dp(6), 0, dp(12), 0);
    heading.setBackgroundColor(CARD);
    heading.setElevation(dp(2));
    FrameLayout arrow = new FrameLayout(this);
    arrow.setBackground(pressable(CARD, 99));
    arrow.addView(icon("back", 20, TEXT), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    arrow.setContentDescription(I18n.t("Quay lại"));
    arrow.setOnClickListener(v -> back.run());
    heading.addView(arrow, new LinearLayout.LayoutParams(raw48, raw48));
    UiMetrics.enforceMinTouchTarget(arrow, 48);
    TextView text = label(title, 18, TEXT);
    text.setTypeface(null, Typeface.BOLD);
    text.setSingleLine(true);
    text.setEllipsize(android.text.TextUtils.TruncateAt.END);
    text.setPadding(dp(6), 0, dp(8), 0);
    heading.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    headActions = row();
    heading.addView(headActions);
    root.addView(heading, 0, new LinearLayout.LayoutParams(-1, UiMetrics.dpRaw(this, UiMetrics.HEADER_HEIGHT)));
  }

  private void accountPage(String title, Runnable back) {
    accountPage(title, back, true);
  }

  private void accountPage(String title, Runnable back, boolean keepBottom) {
    shell("", true);
    inAccountSubPage = true;
    installSubHeader(title, back, keepBottom);
    subBack = back;
  }

  private void accountHeader(String title, Runnable back) {
    accountHeader(title, back, false);
  }

  private void accountHeader(String title, Runnable back, boolean keepBottom) {
    shell("", true);
    installSubHeader(title, back, keepBottom);
    subBack = back;
  }

  private View accountRow(String glyph, String title, String subtitle, Runnable action) {
    int raw48 = UiMetrics.dpRaw(this, 48);
    LinearLayout row = row();
    row.setMinimumHeight(raw48);
    row.setPadding(dp(8), dp(14), dp(8), dp(14));
    FrameLayout badge = new FrameLayout(this);
    badge.setBackground(background(PRIMARY_SOFT, 99)); // Badge dạng tròn 99dp
    badge.addView(icon(glyph, 24, ACCENT_TEXT), new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
    row.addView(badge, new LinearLayout.LayoutParams(dp(40), dp(40)));
    LinearLayout text = column();
    text.setPadding(dp(16), 0, dp(8), 0);
    TextView labelTitle = label(title, WebDesign.LABEL, TEXT);
    labelTitle.setSingleLine(true);
    labelTitle.setEllipsize(android.text.TextUtils.TruncateAt.END);
    text.addView(labelTitle);
    if (subtitle != null && !subtitle.isEmpty()) {
      TextView labelSub = label(subtitle, WebDesign.META, MUTED);
      labelSub.setSingleLine(true);
      labelSub.setEllipsize(android.text.TextUtils.TruncateAt.END);
      text.addView(labelSub);
    }
    row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    row.addView(icon("chevron_right", 20, MUTED), new LinearLayout.LayoutParams(dp(20), dp(20)));
    row.setOnClickListener(v -> action.run());
    row.setBackground(pressable(CARD, 16)); // Thêm background pressable cho row
    UiMetrics.enforceMinTouchTarget(row, 48);
    return row;
  }

  private boolean storeReturning;
  private StoreUi currentStoreUi;

  private void closeStoreUi() {
    if (currentStoreUi != null) {
      try {
        currentStoreUi.close();
      } catch (Exception ignored) {
      }
      currentStoreUi = null;
    }
  }

  private void toggleStore() {
    if ("store".equals(headerActive)) {
      headerActive = "";
      closeStoreUi();
      navigate(tab.isEmpty() || tab.equals("store") ? "feed" : tab);
    } else {
      openStore();
    }
  }

  private void storeScreen() {
    headerActive = "store";
    remember("store", this::storeScreen);
    closeStoreUi();
    shell(I18n.t("Cửa hàng"), true);
    currentStoreUi = new StoreUi(this, content, headActions,
        () -> api.call("GET", "/api/me", null, (data, error, status) -> {
          if (error == null && data != null && !isDestroyed() && me != null) {
            JSONObject fresh = data.optJSONObject("user");
            if (fresh != null)
              me = fresh;
          }
        }));
  }

  private void openStore() {
    storeScreen();
  }

  private void meMenu() {
    if ("account".equals(headerActive) && !inAccountSubPage) {
      headerActive = "";
      navigate(tab.isEmpty() ? "feed" : tab);
      return;
    }
    openMeMenu();
  }

  private void openMeMenu() {
    headerActive = "account";
    remember("account", this::openMeMenu);
    shell(I18n.t("Tài khoản"), true);
    LinearLayout profile = row();
    profile.setPadding(dp(14), dp(12), dp(14), dp(12));
    GradientDrawable pg = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { PRIMARY_SOFT, CARD });
    pg.setCornerRadius(dp(24));
    pg.setStroke(dp(1), LINE);
    profile.setBackground(new android.graphics.drawable.RippleDrawable(
        android.content.res.ColorStateList.valueOf((ACCENT & 0x00ffffff) | 0x22000000), pg, null));
    avatar(me, profile, 56);
    LinearLayout text = column();
    text.setPadding(dp(16), 0, 0, 0);
    TextView n = label(me.optString("name"), 20, TEXT);
    n.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    text.addView(n);
    text.addView(label("@" + me.optString("username"), 14, MUTED));
    profile.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    profile.addView(icon("chevron_right", 24, MUTED), new LinearLayout.LayoutParams(dp(24), dp(24)));
    profile.setContentDescription(I18n.t("Trang cá nhân"));
    profile.setOnClickListener(v -> navigate("profile"));
    LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(-1, -2);
    pp.bottomMargin = dp(6);
    content.addView(profile, pp);

    if (me.optString("role").equals("admin")) {
      LinearLayout admin = settingsGroup();
      groupRow(admin, "shield_check", I18n.t("Bảng quản trị"), false, () -> admin());
    }
    LinearLayout main = settingsGroup();
    groupRow(main, "store", I18n.t("Cửa hàng Kinnect"), false, this::openStore);
    groupRow(main, "wallet", I18n.t("Ví Kinnect"), false, () -> startActivity(new Intent(this, WalletActivity.class)));
    groupRow(main, "bookmark", I18n.t("Bài viết đã lưu"), false, this::bookmarksScreen);
    groupRow(main, "settings", I18n.t("Cài đặt và quyền riêng tư"), false, () -> settings());
    groupRow(main, "shield_check", I18n.t("Bảo mật và đăng nhập"), false, () -> securityScreen());
    groupRow(main, "bell", I18n.t("Cài đặt thông báo"), false, () -> nativeNotificationSettings());
    groupRow(main, "moon", I18n.t("Giao diện"), false, () -> appearanceScreen());
    groupRow(main, "circle_help", I18n.t("Trợ giúp và hỗ trợ"), false, () -> helpScreen());
    groupRow(main, "about_info", I18n.t("Giới thiệu Kinnect"), false, this::aboutScreen);
    LinearLayout end = settingsGroup();
    groupRow(end, "key_round", I18n.t("Đổi mật khẩu"), false, () -> changePassword());
    groupRow(end, "log_out", I18n.t("Đăng xuất"), true,
        () -> confirm(I18n.t("Đăng xuất khỏi Kinnect?"), I18n.t("Đăng xuất"), () -> {
          KinnectFirebaseMessagingService.unregisterTokenFromServer(this, () -> {
            if (isDestroyed())
              return;
            request("POST", "/api/logout", json(), data -> {
              if (calls != null) {
                calls.close();
                calls = null;
              }
              KinnectService.stop(this);
              clearClientSessionCaches();
              mediaCallGate.clear();
              mediaCallBlocked = false;
              me = null;
              intro();
            });
          });
        }));
    TextView foot = label(I18n.t("Kinnect · Kết nối theo cách của bạn."), 12, MUTED);
    foot.setGravity(Gravity.CENTER);
    foot.setPadding(0, dp(8), 0, dp(12));
    content.addView(foot, new LinearLayout.LayoutParams(-1, -2));
    content.setPadding(content.getPaddingLeft(), content.getPaddingTop(), content.getPaddingRight(), dp(16));
  }

  private void bookmarksScreen() {
    remember("bookmarks", this::bookmarksScreen);
    accountPage(I18n.t("Bài viết đã lưu"), this::openMeMenu);
    final TextView loading = label(I18n.t("Đang tải bài viết đã lưu…"), 14, MUTED);
    loading.setPadding(dp(8), dp(16), dp(8), dp(16));
    content.addView(loading);
    request("GET", "/api/bookmarks", null, data -> {
      content.removeView(loading);
      JSONArray posts = data.optJSONArray("posts");
      if (posts == null || posts.length() == 0) {
        TextView empty = label(
            I18n.t("Bạn chưa lưu bài viết nào. Bấm biểu tượng đánh dấu trên bài viết bất kỳ để xem lại tại đây."), 14,
            MUTED);
        empty.setPadding(dp(8), dp(20), dp(8), dp(20));
        content.addView(empty);
        return;
      }
      for (int i = 0; i < posts.length(); i++) {
        JSONObject p = posts.optJSONObject(i);
        if (p != null)
          postCard(p);
      }
    });
  }

  private void gamesScreen() {
    remember("games", () -> gamesScreen());
    accountPage(I18n.t("Trò chơi"), this::openMeMenu);
    LinearLayout hero = column();
    hero.setPadding(dp(20), dp(18), dp(20), dp(18));
    hero.setBackground(brandGradient(24));
    TextView heroTitle = label(I18n.t("Chơi cùng người cùng gu"), 20, WHITE);
    heroTitle.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    hero.addView(heroTitle);
    TextView heroSub = label(I18n.t("Ghép cặp, chơi nhanh và nhận xu may mắn"), 13, 0xd9ffffff);
    heroSub.setPadding(0, dp(4), 0, dp(12));
    hero.addView(heroSub);
    TextView badge = label(I18n.t("Đang phát triển · Sắp ra mắt"), 12, WHITE);
    badge.setTypeface(null, Typeface.BOLD);
    badge.setPadding(dp(10), dp(4), dp(10), dp(4));
    badge.setBackground(background(0x33ffffff, 99));
    hero.addView(badge, new LinearLayout.LayoutParams(-2, -2));
    LinearLayout.LayoutParams heroLp = new LinearLayout.LayoutParams(-1, -2);
    heroLp.bottomMargin = dp(8);
    content.addView(hero, heroLp);

    TextView notice = label(
        I18n.t("Các mini-game tương tác dưới đây đang trong giai đoạn hoàn thiện cuối và sẽ tự động mở khi sẵn sàng."),
        13, MUTED);
    notice.setPadding(dp(6), dp(4), dp(6), dp(10));
    content.addView(notice);

    groupTitle("gamepad", I18n.t("Chơi nhanh 1-1 (Sắp mở)"));
    LinearLayout quick = settingsGroup();
    addGame(quick, "circle_help", "Đoán số", "1 đấu 1 · Sắp ra mắt",
        "Mỗi người chọn một số từ 1 đến 99, lần lượt đoán số của đối thủ.", true);
    addGame(quick, "circle_check", "Caro 5", "1 đấu 1 · Sắp ra mắt",
        "Xếp đủ 5 quân liên tiếp trên bàn 15x15 để chiến thắng.", true);
    addGame(quick, "users_round", "Oẳn tù tì", "1 đấu 1 · Sắp ra mắt", "Chọn kéo, búa hoặc bao trong 3 hiệp nhanh.",
        false);

    groupTitle("users_round", I18n.t("Phòng nhóm & Live (Sắp mở)"));
    LinearLayout rooms = settingsGroup();
    addGame(rooms, "sparkles", "Lô tô & Vòng quay", "2-8 người · Sắp ra mắt",
        "Quay số vui vẻ cùng bạn bè trong phòng nhóm.", true);
    addGame(rooms, "radio", "Đấu trí & Bingo Live", "Trong Live · Sắp ra mắt",
        "Trả lời câu hỏi nhanh ngay trên sóng trực tiếp.", false);
  }

  private void addGame(LinearLayout group, String glyph, String title, String subtitle, String detail,
      boolean divider) {
    LinearLayout row = row();
    row.setPadding(dp(12), dp(12), dp(12), dp(12));
    row.setAlpha(0.78f);
    row.addView(settingsIcon(glyph, MUTED), new LinearLayout.LayoutParams(dp(38), dp(38)));
    LinearLayout text = column();
    text.setPadding(dp(12), 0, dp(8), 0);
    TextView t = label(I18n.t(title) + " · " + I18n.t("Sắp ra mắt"), 14, TEXT);
    t.setTypeface(null, Typeface.BOLD);
    text.addView(t);
    text.addView(label(I18n.t(detail), 12, MUTED));
    row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    group.addView(row, new LinearLayout.LayoutParams(-1, -2));
    if (divider)
      group.addView(divider());
  }

  private LinearLayout settingsGroup() {
    LinearLayout g = column();
    g.setPadding(dp(4), dp(2), dp(4), dp(2));
    GradientDrawable bg = background(CARD, WebDesign.CARD_RADIUS);
    bg.setStroke(dp(1), LINE);
    g.setBackground(bg);
    g.setElevation(dp(2)); // Bóng nhẹ cho Group theo M3
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.bottomMargin = dp(8);
    content.addView(g, p);
    return g;
  }

  private FrameLayout settingsIcon(String name, int tint) {
    FrameLayout tile = new FrameLayout(this);
    tile.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
    ImageView image = new ImageView(this);
    image.setImageDrawable(new FlowIconDrawable(WebIcons.load(this, name), name));
    tile.addView(image, new FrameLayout.LayoutParams(-1, -1));
    return tile;
  }

  /**
   * Crisp scalable paths: no emoji fonts or bitmap scaling. Same 24-unit grid and
   * rounded 1.8-unit stroke.
   */
  private final class SettingsGlyph extends android.graphics.drawable.Drawable {
    private final String kind;
    private final int tint;

    SettingsGlyph(String kind, int tint, int back) {
      this.kind = kind;
      this.tint = tint;
    }

    public void draw(Canvas canvas) {
      android.graphics.drawable.Drawable d = WebIcons.load(MainActivity.this, kind);
      d.setTint(tint);
      d.setBounds(getBounds());
      d.draw(canvas);
    }

    public void setAlpha(int alpha) {
      invalidateSelf();
    }

    public void setColorFilter(ColorFilter filter) {
      invalidateSelf();
    }

    public int getOpacity() {
      return PixelFormat.TRANSLUCENT;
    }
  }

  private void groupRow(LinearLayout group, String iconName, String title, boolean danger, Runnable action) {
    if (group.getChildCount() > 0) {
      View line = new View(this);
      line.setBackgroundColor(LINE);
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, 1);
      lp.setMargins(dp(60), 0, dp(16), 0); // Tăng margin đường kẻ
      group.addView(line, lp);
    }
    int tint = danger ? WebDesign.DANGER[WebTheme.isDark(this) ? 1 : 0] : ACCENT_TEXT;
    int minH = Math.max(dp(50), UiMetrics.dpRaw(this, 48));
    LinearLayout r = row();
    r.setMinimumHeight(minH);
    r.setPadding(dp(14), dp(5), dp(14), dp(5));
    r.setBackground(pressable(CARD, 24)); // Góc bo 24 theo M3
    r.addView(settingsIcon(iconName, tint), new LinearLayout.LayoutParams(dp(36), dp(36)));
    TextView t = label(title, 15, danger ? tint : TEXT); // Chữ to hơn
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    t.setPadding(dp(14), 0, 0, 0); // M3 text padding
    t.setSingleLine(true);
    t.setEllipsize(android.text.TextUtils.TruncateAt.END);
    r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
    if (!danger)
      r.addView(icon("chevron_right", 20, MUTED), new LinearLayout.LayoutParams(dp(20), dp(20))); // Chevron to hơn
    r.setContentDescription(title);
    r.setOnClickListener(v -> action.run());
    group.addView(r, new LinearLayout.LayoutParams(-1, -2));
    UiMetrics.enforceMinTouchTarget(r, 48);
  }

  private void appearanceScreen() {
    accountPage(I18n.t("Giao diện"), this::openMeMenu);
    String selected = getSharedPreferences("kinnect_settings", 0).getString("theme", "auto");
    String[][] choices = { { "auto", "monitor", "Theo hệ thống" }, { "light", "sun", "Sáng" },
        { "dark", "moon", "Tối" } };
    LinearLayout list = settingsGroup();
    for (final String[] choice : choices)
      groupRow(list, selected.equals(choice[0]) ? "circle_check" : choice[1], choice[2], false, () -> {
        getSharedPreferences("kinnect_settings", 0).edit().putString("theme", choice[0]).apply();
        recreate();
      });
  }

  private void securityScreen() {
    accountPage(I18n.t("Bảo mật và đăng nhập"), this::openMeMenu);
    LinearLayout panel = settingsGroup();
    groupRow(panel, "key_round", I18n.t("Đổi mật khẩu"), false, () -> changePassword());
    groupRow(panel, "shield_check", I18n.t("Xác thực 2 bước (2FA)"), false, () -> openTwoFactorDialog());
    groupRow(panel, "mail", I18n.t("Email khôi phục"), false, () -> recoveryEmailScreen());
    groupRow(panel, "monitor", I18n.t("Thiết bị đăng nhập"), false, () -> sessionsScreen());
    groupRow(panel, "circle_help", I18n.t("Hỗ trợ tài khoản và khôi phục"), false, () -> openPublicPage("support"));
  }

  private void showBackupCodesSheet(JSONArray codes, String title, Runnable afterDone) {
    StringBuilder sb = new StringBuilder();
    for (int i = 0; codes != null && i < codes.length(); i++) {
      if (i > 0)
        sb.append("\n");
      sb.append(codes.optString(i));
    }
    final String joined = sb.toString();
    LinearLayout box = column();
    box.setPadding(dp(4), dp(4), dp(4), dp(4));
    box.addView(label(
        I18n.t("Lưu lại các mã dự phòng này ở nơi an toàn. Mỗi mã chỉ dùng được một lần khi mất ứng dụng xác thực."),
        13, MUTED));
    TextView codeView = label(joined.isEmpty() ? I18n.t("Không có mã dự phòng.") : joined, 15, TEXT);
    codeView.setTypeface(Typeface.MONOSPACE);
    codeView.setTextIsSelectable(true);
    codeView.setPadding(dp(12), dp(10), dp(12), dp(10));
    codeView.setBackground(background(SOFT, 12));
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.topMargin = dp(8);
    box.addView(codeView, lp);
    if (!joined.isEmpty()) {
      box.addView(button(I18n.t("Sao chép mã dự phòng"), () -> {
        android.content.ClipboardManager cm = (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
        if (cm != null)
          cm.setPrimaryClip(ClipData.newPlainText("Kinnect 2FA Backup Codes", joined));
        say(I18n.t("Đã sao chép mã dự phòng."));
      }));
    }
    new Sheet(this).setTitle(title).setView(box)
        .setPositiveButton(I18n.t("Xong"), (d, w) -> {
          if (afterDone != null)
            afterDone.run();
        })
        .show();
  }

  private void openTwoFactorDialog() {
    request("GET", "/api/me/2fa", null, data -> {
      final boolean enabled = data.optBoolean("enabled");
      final boolean pending = data.optBoolean("pending");
      final int remaining = data.optInt("recoveryRemaining", 0);
      LinearLayout box = column();
      box.setPadding(dp(4), dp(4), dp(4), dp(4));
      box.addView(label(enabled
          ? I18n.t("Trạng thái: Đang bật · Còn ") + remaining + I18n.t(" mã dự phòng")
          : (pending ? I18n.t("Trạng thái: Đang chờ nhập mã 6 chữ số để hoàn tất kích hoạt.")
              : I18n.t("Trạng thái: Chưa bật xác thực 2 bước (TOTP).")),
          14, enabled ? ACCENT_TEXT : MUTED));
      final android.app.Dialog[] mainDlg = { null };
      if (!enabled) {
        if (pending) {
          box.addView(primary(I18n.t("Nhập mã 6 số để hoàn tất"), () -> {
            if (mainDlg[0] != null)
              mainDlg[0].dismiss();
            LinearLayout pendBox = column();
            EditText codeInput = new KinnectInput(this);
            styleChatName(codeInput);
            codeInput.setHint(I18n.t("Mã xác thực 6 chữ số"));
            codeInput.setInputType(InputType.TYPE_CLASS_NUMBER);
            pendBox.addView(chatNameWrap(codeInput));
            new Sheet(this).setTitle(I18n.t("Kích hoạt 2FA")).setView(pendBox)
                .setAutoDismissPositive(false)
                .setPositiveButton(I18n.t("Kích hoạt"), (d2, w2) -> {
                  String code = codeInput.getText().toString().trim();
                  if (code.length() < 6) {
                    say(I18n.t("Nhập mã xác thực 6 chữ số."));
                    return;
                  }
                  request("POST", "/api/me/2fa/enable", json("code", code), enabledRes -> {
                    d2.dismiss();
                    say(I18n.t("Đã bật xác thực 2 bước (2FA)."));
                    openTwoFactorDialog();
                  });
                })
                .setNegativeButton(I18n.t("Huỷ"), null).show();
          }));
        }
        box.addView(button(pending ? I18n.t("Tạo khóa 2FA mới") : I18n.t("Thiết lập 2FA"), () -> {
          if (mainDlg[0] != null)
            mainDlg[0].dismiss();
          final boolean hasPwd = me == null || me.optBoolean("hasPassword", true);
          LinearLayout pwForm = column();
          EditText pwInput = new KinnectInput(this);
          if (hasPwd) {
            pwForm.addView(label(I18n.t("Nhập mật khẩu hiện tại để khởi tạo khóa 2FA."), 13, MUTED));
            styleChatName(pwInput);
            pwInput.setHint(I18n.t("Mật khẩu hiện tại"));
            pwInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
            pwForm.addView(chatNameWrap(pwInput));
          } else {
            pwForm.addView(label(I18n.t("Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây)."), 13, MUTED));
          }
          final boolean[] setupBusy = { false };
          new Sheet(this).setTitle(I18n.t("Thiết lập 2FA")).setView(pwForm)
            .setAutoDismissPositive(false)
            .setPositiveButton(I18n.t("Tiếp tục"), (d, w) -> {
              if (setupBusy[0]) return;
              String pw = hasPwd ? pwInput.getText().toString() : "";
              if (hasPwd && pw.isEmpty()) { say(I18n.t("Nhập mật khẩu hiện tại.")); return; }
              setupBusy[0] = true;
              request("POST", "/api/me/2fa/setup", json("password", pw), setup -> {
                try { d.dismiss(); } catch (Exception ignored) {}
                final String secret = setup.optString("secret");
                final String otpauthUri = setup.optString("otpauthUri");
                final JSONArray backupCodes = setup.optJSONArray("backupCodes");
                LinearLayout step2 = column();
                step2.addView(label(I18n.t("Thêm khóa bí mật này vào Google Authenticator / Authy rồi nhập mã 6 chữ số để kích hoạt:"), 13, MUTED));
                TextView secretTv = label(secret, 15, TEXT);
                secretTv.setTypeface(Typeface.MONOSPACE);
                secretTv.setTextIsSelectable(true);
                secretTv.setPadding(dp(10), dp(8), dp(10), dp(8));
                secretTv.setBackground(background(SOFT, 10));
                step2.addView(secretTv);
                step2.addView(button(I18n.t("Sao chép khóa bí mật"), () -> {
                  android.content.ClipboardManager cm = (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                  if (cm != null) cm.setPrimaryClip(ClipData.newPlainText("Kinnect 2FA Secret", secret));
                  say(I18n.t("Đã sao chép khóa bí mật."));
                }));
                if (!otpauthUri.isEmpty()) {
                  TextView uriTv = label(otpauthUri, 11, MUTED);
                  uriTv.setTextIsSelectable(true);
                  uriTv.setPadding(0, dp(4), 0, dp(4));
                  step2.addView(uriTv);
                  step2.addView(button(I18n.t("Sao chép liên kết OTPAuth"), () -> {
                    android.content.ClipboardManager cm = (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                    if (cm != null) cm.setPrimaryClip(ClipData.newPlainText("Kinnect 2FA URI", otpauthUri));
                    say(I18n.t("Đã sao chép liên kết OTPAuth."));
                  }));
                }
                EditText codeInput = new KinnectInput(this);
                styleChatName(codeInput);
                codeInput.setHint(I18n.t("Mã xác thực 6 chữ số"));
                codeInput.setInputType(InputType.TYPE_CLASS_NUMBER);
                step2.addView(chatNameWrap(codeInput));
                ScrollView sc = new ScrollView(this);
                sc.addView(step2);
                new Sheet(this).setTitle(I18n.t("Kích hoạt 2FA")).setView(sc)
                    .setAutoDismissPositive(false)
                    .setPositiveButton(I18n.t("Kích hoạt"), (d2, w2) -> {
                      String code = codeInput.getText().toString().trim();
                      if (code.length() < 6) {
                        say(I18n.t("Nhập mã xác thực 6 chữ số."));
                        return;
                      }
                      request("POST", "/api/me/2fa/enable", json("code", code), enabledRes -> {
                        d2.dismiss();
                        say(I18n.t("Đã bật xác thực 2 bước (2FA)."));
                        showBackupCodesSheet(backupCodes, I18n.t("Mã dự phòng 2FA"), () -> openTwoFactorDialog());
                      });
                    })
                    .setNegativeButton(I18n.t("Huỷ"), null).show();
              }, () -> setupBusy[0] = false);
            })
            .setNegativeButton(I18n.t("Huỷ"), null).show();
        }));
      } else {
        box.addView(button(I18n.t("Tạo lại mã dự phòng"), () -> {
          if (mainDlg[0] != null)
            mainDlg[0].dismiss();
          final boolean hasPwd = me == null || me.optBoolean("hasPassword", true);
          LinearLayout form = column();
          EditText pwInput = new KinnectInput(this);
          if (hasPwd) {
            styleChatName(pwInput);
            pwInput.setHint(I18n.t("Mật khẩu hiện tại"));
            pwInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
            form.addView(chatNameWrap(pwInput));
          } else {
            form.addView(label(I18n.t("Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây)."), 13, MUTED));
          }
          EditText codeInput = new KinnectInput(this);
          styleChatName(codeInput);
          codeInput.setHint(I18n.t("Mã 6 số từ ứng dụng xác thực"));
          form.addView(chatNameWrap(codeInput));
          final boolean[] regenBusy = { false };
          new Sheet(this).setTitle(I18n.t("Tạo lại mã dự phòng")).setView(form)
            .setAutoDismissPositive(false)
            .setPositiveButton(I18n.t("Tạo mã mới"), (d, w) -> {
              if (regenBusy[0]) return;
              String pw = hasPwd ? pwInput.getText().toString() : "", code = codeInput.getText().toString().trim();
              if ((hasPwd && pw.isEmpty()) || code.isEmpty()) { say(I18n.t(hasPwd ? "Nhập đầy đủ mật khẩu và mã xác thực." : "Nhập mã xác thực 6 chữ số.")); return; }
              regenBusy[0] = true;
              request("POST", "/api/me/2fa/recovery", json("password", pw, "code", code), res -> {
                try { d.dismiss(); } catch (Exception ignored) {}
                say(I18n.t("Đã tạo bộ mã dự phòng mới."));
                showBackupCodesSheet(res.optJSONArray("backupCodes"), I18n.t("Mã dự phòng mới"), () -> openTwoFactorDialog());
              }, () -> regenBusy[0] = false);
            })
            .setNegativeButton(I18n.t("Huỷ"), null).show();
        }));
        box.addView(button(I18n.t("Tắt 2FA"), () -> {
          if (mainDlg[0] != null)
            mainDlg[0].dismiss();
          final boolean hasPwd = me == null || me.optBoolean("hasPassword", true);
          LinearLayout form = column();
          EditText pwInput = new KinnectInput(this);
          if (hasPwd) {
            styleChatName(pwInput);
            pwInput.setHint(I18n.t("Mật khẩu hiện tại"));
            pwInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
            form.addView(chatNameWrap(pwInput));
          } else {
            form.addView(label(I18n.t("Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây)."), 13, MUTED));
          }
          EditText codeInput = new KinnectInput(this);
          styleChatName(codeInput);
          codeInput.setHint(I18n.t("Mã 6 số hoặc mã dự phòng"));
          form.addView(chatNameWrap(codeInput));
          final boolean[] disableBusy = { false };
          new Sheet(this).setTitle(I18n.t("Tắt xác thực 2 bước")).setView(form)
            .setAutoDismissPositive(false)
            .setPositiveButton(I18n.t("Tắt 2FA"), (d, w) -> {
              if (disableBusy[0]) return;
              String pw = hasPwd ? pwInput.getText().toString() : "", code = codeInput.getText().toString().trim();
              if ((hasPwd && pw.isEmpty()) || code.isEmpty()) { say(I18n.t(hasPwd ? "Nhập đầy đủ mật khẩu và mã xác thực." : "Nhập mã xác thực 6 chữ số.")); return; }
              disableBusy[0] = true;
              request("POST", "/api/me/2fa/disable", json("password", pw, "code", code), res -> {
                try { d.dismiss(); } catch (Exception ignored) {}
                say(I18n.t("Đã tắt xác thực 2 bước."));
                openTwoFactorDialog();
              }, () -> disableBusy[0] = false);
            })
            .setNegativeButton(I18n.t("Huỷ"), null).show();
        }));
      }
      mainDlg[0] = new Sheet(this).setTitle(I18n.t("Xác thực 2 bước (2FA)")).setView(box)
          .setNegativeButton(I18n.t("Đóng"), null).show();
    });
  }

  private void sessionsScreen() {
    accountPage(I18n.t("Thiết bị đăng nhập"), () -> securityScreen());
    content.addView(
        label(I18n.t("Thu hồi phiên để đăng xuất thiết bị khác và huỷ đăng nhập nhanh của thiết bị đó."), 14, MUTED));
    final int generation = screen;
    final TextView loadingView = label(I18n.t("Đang tải thiết bị đăng nhập..."), 13, MUTED);
    content.addView(loadingView);
    api.call("GET", "/api/me/sessions", null, (data, error, status) -> {
      if (isFinishing() || isDestroyed() || generation != screen)
        return;
      content.removeView(loadingView);
      if (error != null || data == null) {
        if (status == 401 && me != null) {
          handleUnauthorized();
          say(error != null && !error.isEmpty() ? error : I18n.t("Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại."));
          return;
        }
        String msg = error != null && !error.isEmpty() ? error : I18n.t("Chưa tải được danh sách thiết bị.");
        say(msg);
        LinearLayout errCard = card();
        errCard.addView(label(msg, 14, TEXT));
        errCard.addView(button(I18n.t("Thử lại"), () -> sessionsScreen()));
        return;
      }
      JSONArray sessions = data.optJSONArray("sessions");
      int onlineCol = WebDesign.ONLINE_STRICT[WebTheme.isDark(this) ? 1 : 0];
      for (int i = 0; sessions != null && i < sessions.length(); i++) {
        JSONObject session = sessions.optJSONObject(i);
        boolean isCurrent = session.optBoolean("current");
        String lbl = session.optString("label");
        boolean mobileDevice = lbl.toLowerCase(Locale.ROOT).contains("android")
            || lbl.toLowerCase(Locale.ROOT).contains("iphone")
            || "android".equals(session.optString("deviceType"));
        LinearLayout panel = card();
        LinearLayout topRow = row();
        FrameLayout devBadge = new FrameLayout(this);
        devBadge.setBackground(background(PRIMARY_SOFT, 12));
        devBadge.addView(icon(mobileDevice ? "smartphone" : "monitor", 20, ACCENT_TEXT),
            new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
        topRow.addView(devBadge, new LinearLayout.LayoutParams(dp(40), dp(40)));
        LinearLayout infoCol = column();
        infoCol.setPadding(dp(12), 0, dp(8), 0);
        TextView devTitle = label(lbl, 15, TEXT);
        devTitle.setTypeface(null, Typeface.BOLD);
        infoCol.addView(devTitle);
        String expLabel;
        if (isCurrent) {
          expLabel = "● " + I18n.t("Thiết bị hiện tại");
        } else {
          long expMs = session.optLong("expires", 0L);
          String formattedDate = expMs > 0
              ? new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()).format(new Date(expMs))
              : session.optString("expires").split("T")[0];
          expLabel = I18n.t("Hết hạn ") + formattedDate;
        }
        TextView subTv = label(expLabel, 12, isCurrent ? onlineCol : MUTED);
        if (isCurrent)
          subTv.setTypeface(null, Typeface.BOLD);
        infoCol.addView(subTv);
        topRow.addView(infoCol, new LinearLayout.LayoutParams(0, -2, 1));
        panel.addView(topRow);
        if (!isCurrent)
          panel.addView(button(I18n.t("Đăng xuất thiết bị"), () -> confirm(I18n.t("Đăng xuất thiết bị này?"),
              () -> request("DELETE", "/api/me/sessions/" + session.optString("id"), json(), d -> sessionsScreen()))));
      }
    });
  }

  private void recoveryEmailScreen() {
    accountPage(I18n.t("Email khôi phục"), () -> securityScreen());
    request("GET", "/api/recovery/email", null, data -> {
      LinearLayout panel = card();
      panel.addView(label(data.isNull("email") ? I18n.t("Chưa xác minh email khôi phục.")
          : I18n.t("Email đã xác minh: ") + data.optString("email"), 14, MUTED));
      final boolean hasPwd = me == null || me.optBoolean("hasPassword", true);
      panel.addView(fieldLabel(I18n.t("Email khôi phục")));
      EditText email = input(panel, "Email", "", false);
      email.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
      final EditText password;
      if (hasPwd) {
        panel.addView(fieldLabel(I18n.t("Mật khẩu hiện tại")));
        password = input(panel, I18n.t("Mật khẩu hiện tại"), "", false);
        password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
      } else {
        password = null;
        panel
            .addView(label(I18n.t("Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây)."), 13, MUTED));
      }
      final Button[] sendCodeBtn = { null };
      sendCodeBtn[0] = primary(I18n.t("Gửi mã xác minh"), () -> {
        if (!sendCodeBtn[0].isEnabled())
          return;
        sendCodeBtn[0].setEnabled(false);
        sendCodeBtn[0].setAlpha(0.5f);
        request("POST", "/api/recovery/email/start", json("email", email.getText().toString().trim(), "password",
            password == null ? "" : password.getText().toString()), result -> {
              panel.removeAllViews();
              panel.addView(label(I18n.t("Nhập mã xác minh trong email của bạn."), 14, TEXT));
              EditText code = input(panel, I18n.t("Mã xác minh"), "", false);
              code.setInputType(InputType.TYPE_CLASS_NUMBER);
              final Button[] verifyBtn = { null };
              verifyBtn[0] = primary(I18n.t("Xác minh"), () -> {
                if (!verifyBtn[0].isEnabled())
                  return;
                verifyBtn[0].setEnabled(false);
                verifyBtn[0].setAlpha(0.5f);
                request("POST", "/api/recovery/email/verify",
                    json("challengeId", result.optString("challengeId"), "code", code.getText().toString().trim()),
                    verified -> {
                      say(I18n.t("Đã xác minh email."));
                      recoveryEmailScreen();
                    }, () -> {
                      verifyBtn[0].setEnabled(true);
                      verifyBtn[0].setAlpha(1f);
                    });
              });
              panel.addView(verifyBtn[0]);
            }, () -> {
              sendCodeBtn[0].setEnabled(true);
              sendCodeBtn[0].setAlpha(1f);
            });
      });
      panel.addView(sendCodeBtn[0]);
    });
  }

  private void nativeNotificationSettings() {
    accountPage(I18n.t("Cài đặt thông báo"), this::openMeMenu);
    LinearLayout panel = settingsGroup();
    for (final String[] choice : new String[][] { { "enabled", "Hiện thông báo", "bell_ring" },
        { "messages", "Tin nhắn", "message_square" }, { "friends", "Lời mời kết bạn", "user_plus" },
        { "posts", "Bài viết và tương tác", "post_heart" } }) {
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
      r.addView(settingsIcon(choice[2], ACCENT), new LinearLayout.LayoutParams(dp(38), dp(38)));
      TextView t = label(I18n.t(choice[1]), 15, TEXT);
      t.setPadding(dp(12), 0, dp(8), 0);
      t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
      r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
      final Switch toggle = new Switch(this);
      toggle.setThumbTintList(new android.content.res.ColorStateList(
          new int[][] { { android.R.attr.state_checked }, {} }, new int[] { ACCENT, 0xffffffff }));
      toggle
          .setTrackTintList(new android.content.res.ColorStateList(new int[][] { { android.R.attr.state_checked }, {} },
              new int[] { (ACCENT & 0x00ffffff) | 0x66000000, LINE }));
      toggle.setContentDescription(I18n.t(choice[1]));
      toggle.setChecked(getSharedPreferences("kinnect_notifications", 0).getBoolean(choice[0], true));
      toggle.setOnCheckedChangeListener((view, checked) -> getSharedPreferences("kinnect_notifications", 0).edit()
          .putBoolean(choice[0], checked).apply());
      int raw48 = UiMetrics.dpRaw(this, 48);
      toggle.setMinimumWidth(raw48);
      toggle.setMinimumHeight(raw48);
      r.addView(toggle, new LinearLayout.LayoutParams(-2, -2));
      UiMetrics.enforceMinTouchTarget(toggle, 48);
      r.setOnClickListener(v -> toggle.toggle());
      panel.addView(r, new LinearLayout.LayoutParams(-1, -2));
      UiMetrics.enforceMinTouchTarget(r, 48);
    }
  }

  private void openPublicPage(String page) {
    try {
      startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://kinnect.io.vn/" + page)));
    } catch (Exception error) {
      say(I18n.t("Chưa mở được trang hỗ trợ."));
    }
  }

  private String installedVersion() {
    try {
      android.content.pm.PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
      return info.versionName;
    } catch (android.content.pm.PackageManager.NameNotFoundException error) {
      return "Chưa đọc được phiên bản";
    }
  }

  private void settingsDetailRow(LinearLayout group, String glyph, String title, String subtitle, Runnable action) {
    groupRow(group, glyph, title, false, action);
    LinearLayout row = (LinearLayout) group.getChildAt(group.getChildCount() - 1);
    TextView heading = (TextView) row.getChildAt(1);
    row.removeView(heading);
    heading.setPadding(0, 0, 0, 0);
    LinearLayout labels = column();
    labels.setPadding(dp(12), 0, dp(8), 0);
    labels.addView(heading, new LinearLayout.LayoutParams(-1, -2));
    TextView detail = label(subtitle, 12, MUTED);
    detail.setPadding(0, dp(3), 0, 0);
    labels.addView(detail);
    row.addView(labels, 1, new LinearLayout.LayoutParams(0, -2, 1));
    row.setMinimumHeight(dp(68));
    row.setContentDescription(title + ". " + subtitle);
  }

  private void aboutScreen() {
    accountPage(I18n.t("Giới thiệu Kinnect"), this::openMeMenu);
    LinearLayout brand = column();
    brand.setGravity(Gravity.CENTER_HORIZONTAL);
    brand.setPadding(dp(16), dp(20), dp(16), dp(24));
    ImageView logo = new ImageView(this);
    logo.setImageDrawable(getApplicationInfo().loadIcon(getPackageManager()));
    logo.setContentDescription("Logo Kinnect");
    brand.addView(logo, new LinearLayout.LayoutParams(dp(72), dp(72)));
    TextView name = label("Kinnect", 22, ACCENT_TEXT);
    name.setGravity(Gravity.CENTER);
    name.setTypeface(null, Typeface.BOLD);
    name.setPadding(0, dp(12), 0, dp(6));
    brand.addView(name, new LinearLayout.LayoutParams(-1, -2));
    TextView slogan = label(I18n.t("Kết nối theo cách của bạn."), 13, MUTED);
    slogan.setGravity(Gravity.CENTER);
    brand.addView(slogan);
    content.addView(brand, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout links = settingsGroup();
    groupRow(links, "globe", I18n.t("Về Kinnect"), false, () -> nativeDocument("index"));
    settingsDetailRow(links, "download", I18n.t("Kiểm tra cập nhật"), I18n.t("Đang dùng ") + installedVersion(),
        () -> ApkUpdates.check(this));
  }

  private void nativeDocument(String page) {
    nativeDocument(page, this::aboutScreen);
  }

  private void nativeDocument(String page, Runnable back) {
    String title = PolicyText.title(page);
    String[][] rows = PolicyText.rows(page);
    accountPage(I18n.t(title), back);
    LinearLayout panel = null;
    for (String[] part : rows) {
      boolean heading = part[0].startsWith("h");
      if (heading || panel == null) {
        panel = card();
        panel.setPadding(dp(16), dp(12), dp(16), dp(12));
      }
      TextView text = label(I18n.t(part[1]), heading ? 17 : 14, heading ? TEXT : MUTED);
      if (heading)
        text.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
      else {
        text.setLineSpacing(dp(4), 1.1f);
        text.setTextIsSelectable(true);
      }
      panel.addView(text, new LinearLayout.LayoutParams(-1, -2));
    }
  }

  private void helpScreen() {
    accountPage(I18n.t("Trợ giúp và hỗ trợ"), this::openMeMenu);
    LinearLayout panel = settingsGroup();
    groupRow(panel, "flag", I18n.t("Báo sự cố"), false, () -> report("app", me.optString("id")));
    groupRow(panel, "message_square", I18n.t("Trung tâm hỗ trợ"), false,
        () -> request("GET", "/api/support", null, data -> {
          JSONObject contact = data.optJSONObject("user");
          if (contact != null)
            chat(contact);
          else
            new Sheet(this).setTitle(I18n.t("Hỗ trợ Kinnect"))
                .setMessage(I18n.t("Liên hệ riêng Mr Ánh: anhvn53@wru.vn. Không gửi mật khẩu hoặc OTP."))
                .setPositiveButton(I18n.t("Đóng"), null).show();
        }));
    groupRow(panel, "shield_check", I18n.t("Chính sách quyền riêng tư"), false,
        () -> nativeDocument("privacy", this::helpScreen));
    groupRow(panel, "users_round", I18n.t("Quy tắc cộng đồng"), false,
        () -> nativeDocument("community", this::helpScreen));
    groupRow(panel, "shield_check", I18n.t("An toàn trẻ em"), false,
        () -> nativeDocument("child-safety", this::helpScreen));
    groupRow(panel, "file_text", I18n.t("Giấy phép phần mềm"), false, () -> showSoftwareLicenses());
    panel.addView(label(I18n.t("Mr Ánh · Hỗ trợ và quyền riêng tư: anhvn53@wru.vn"), 12, MUTED));
  }

  private void showSoftwareLicenses() {
    accountPage(I18n.t("Giấy phép phần mềm"), () -> helpScreen());
    LinearLayout panel = card();
    try {
      java.io.InputStream stream = getAssets().open("THIRD_PARTY_NOTICES.txt");
      String licenses = new String(NativeApi.read(stream, 300000), "UTF-8");
      stream.close();
      TextView content = label(licenses, 12, TEXT);
      content.setTextIsSelectable(true);
      panel.addView(content);
    } catch (Exception error) {
      panel.addView(label("Xem https://app.kinnect.io.vn/third-party-notices.txt", 14, TEXT));
    }
  }

  // Thông báo ngắn dạng "toast" nổi giống web (không chiếm chỗ trên màn).
  private void say(String text) {
    if (SuccessEffects.message(this, text))
      return;
    text = I18n.t(text);
    if (notice != null)
      notice.setText(text);
    if (text == null || text.trim().isEmpty())
      return;
    if ((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
      android.util.Log.i("KinnectQA", "UI_SAY: " + text.replace('\n', ' '));
    }
    long toastNow = android.os.SystemClock.elapsedRealtime();
    if (text.equals(lastToastMessage) && toastNow - lastToastAt < 6000)
      return;
    lastToastMessage = text;
    lastToastAt = toastNow;
    final ViewGroup host = findViewById(android.R.id.content);
    if (host == null) {
      Toast.makeText(this, text, Toast.LENGTH_SHORT).show();
      return;
    }
    if (toastView != null)
      host.removeView(toastView);
    String lower = text.toLowerCase(Locale.ROOT);
    boolean error = lower.startsWith("không") || lower.contains("lỗi") || lower.startsWith("cần")
        || lower.startsWith("vui lòng") || lower.contains("chưa") || lower.startsWith("nhập")
        || lower.contains("tối thiểu");
    boolean ok = lower.startsWith("đã");
    // Thông báo nổi kiểu Google Material 3 Pill Toast / Snackbar
    int tint = error ? WebDesign.DANGER[WebTheme.isDark(this) ? 1 : 0]
        : ok ? WebDesign.SUCCESS[WebTheme.isDark(this) ? 1 : 0] : ACCENT;
    LinearLayout pill = row();
    pill.setPadding(dp(16), dp(12), dp(20), dp(12)); // Tăng padding
    GradientDrawable bg = background(CARD, 999); // Hình pill chuẩn
    bg.setStroke(dp(1), (tint & 0x00ffffff) | 0x38000000);
    pill.setBackground(bg);
    pill.setElevation(dp(8)); // Đổ bóng nhẹ hơn
    FrameLayout mark = new FrameLayout(this);
    mark.setBackground(background(tint, 999)); // Chấm đặc mầu
    mark.addView(icon(ok ? "check" : error ? "circle_help" : "bell", 16, WHITE),
        new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
    pill.addView(mark, new LinearLayout.LayoutParams(dp(28), dp(28))); // Chấm biểu tượng tròn
    TextView msg = label(text, 14, TEXT);
    msg.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    msg.setPadding(dp(12), 0, 0, 0);
    msg.setMaxLines(3);
    pill.addView(msg, new LinearLayout.LayoutParams(-2, -2));
    FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    android.view.WindowInsets insets = host.getRootWindowInsets();
    // Material You Snackbar thường ở phía dưới (hoặc đỉnh tuỳ trường hợp), đặt cách
    // đáy
    lp.bottomMargin = (insets == null ? dp(24) : Math.max(insets.getSystemWindowInsetBottom(), dp(24))) + dp(80);
    lp.leftMargin = dp(16);
    lp.rightMargin = dp(16);
    host.addView(pill, lp);
    toastView = pill;
    pill.setAlpha(0f);
    pill.setTranslationY(dp(16)); // Slide up
    pill.animate().alpha(1f).translationY(0).setDuration(250)
        .setInterpolator(new android.view.animation.DecelerateInterpolator()).start();
    final View shown = pill;
    pill.setOnClickListener(
        v -> v.animate().alpha(0f).setDuration(150).withEndAction(() -> host.removeView(v)).start());
    pill.postDelayed(() -> {
      if (shown.getParent() != null)
        shown.animate().alpha(0f).translationY(dp(12)).setDuration(220).withEndAction(() -> {
          host.removeView(shown);
          if (toastView == shown)
            toastView = null;
        }).start();
    }, error ? 3500 : 2500);
  }

  private View toastView;
  private String lastToastMessage = "";
  private long lastToastAt;

  private JSONObject json(Object... values) {
    JSONObject obj = new JSONObject();
    try {
      for (int i = 0; i < values.length; i += 2)
        obj.put(
            String.valueOf(values[i]),
            values[i + 1]);
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
    request(method, path, data, done, () -> {
    });
  }

  private void request(String method, String path, JSONObject data, Done done, Runnable finished) {
    final int generation = screen;
    final UploadProgress upload = data != null
        && (data.optString("media").startsWith("data:") || data.optString("data").startsWith("data:"))
            ? new UploadProgress(this)
            : null;
    api.call(method, path, data, upload, (answer, error, status) -> {
      if (upload != null)
        upload.close();
      if (isFinishing() || isDestroyed() || generation != screen) {
        finished.run();
        return;
      }
      try {
        if (error != null) {
          if (status == 428 && answer != null && !answer.optString("version").isEmpty()) {
            new Sheet(this).setTitle(I18n.t("Thông báo sử dụng dữ liệu")).setMessage(I18n.t(error))
                .setPositiveButton(I18n.t("Tôi đồng ý"),
                    (dialog, which) -> request("POST", "/api/me/privacy-consent",
                        json("accepted", true, "version", answer.optString("version")),
                        accepted -> request(method, path, data, done, finished)))
                .setNegativeButton(I18n.t("Để sau"), null).show();
            return;
          }
          boolean isPasswordVerify = path != null
              && (path.startsWith("/api/me/2fa/") || path.equals("/api/recovery/email/start")
                  || path.equals("/api/admin/ai/credentials") || path.equals("/api/me/password"));
          if (status == 401 && me != null && !isPasswordVerify) {
            handleUnauthorized();
          }
          say(error);
          return;
        }
        if (answer != null && answer.optBoolean("offline"))
          say(I18n.t("Đang dùng dự phòng · Đăng nhập và nhắn tin vẫn hoạt động."));
        else if (answer != null && answer.optBoolean("cached"))
          say(I18n.t("Đang xem nội dung đã lưu trên máy."));
        done.accept(answer);
      } catch (RuntimeException failure) {
        CrashLog.record(this, failure);
        say(I18n.t("Không hiển thị được nội dung. Hãy thử lại."));
      } finally {
        finished.run();
      }
    });
  }

  // Keep the draft until the server confirms it; a second tap cannot duplicate a
  // pending send.
  private void cachedRequest(String path, Done done, Runnable finished) {
    JSONObject saved = api.cachedGet(path);
    String before = "";
    if (saved != null) {
      try {
        saved.remove("cached");
        before = saved.toString();
        saved.put("cached", true);
        done.accept(saved);
      } catch (JSONException | RuntimeException failure) {
        if (failure instanceof RuntimeException)
          CrashLog.record(this, failure);
      }
    }
    final String signature = before;
    request("GET", path, null, data -> {
      JSONObject comparison;
      try {
        comparison = new JSONObject(data.toString());
        comparison.remove("cached");
      } catch (JSONException e) {
        return;
      }
      if (!signature.equals(comparison.toString()))
        done.accept(data);
    }, finished);
  }

  private final java.util.WeakHashMap<EditText, String[]> messageRequests = new java.util.WeakHashMap<>();

  private void submitText(EditText input, View send, String path, JSONObject payload, Done sent) {
    if (!send.isEnabled())
      return;
    final String draft = input.getText().toString();
    if (draft.trim().isEmpty())
      return;
    if (path.endsWith("/messages")) {
      String[] previous = messageRequests.get(input);
      String signature = path + "\n" + payload.toString();
      if (previous == null || !previous[0].equals(signature)) {
        previous = new String[] { signature, java.util.UUID.randomUUID().toString() };
        messageRequests.put(input, previous);
      }
      try {
        payload.put("requestId", previous[1]);
      } catch (JSONException invalid) {
        return;
      }
    }
    send.setEnabled(false);
    send.setAlpha(0.5f);
    request("POST", path, payload, data -> {
      if (input.getText().toString().equals(draft))
        input.setText("");
      messageRequests.remove(input);
      sent.accept(data);
    }, () -> {
      send.setEnabled(true);
      send.setAlpha(1f);
    });
  }

  private void auth(boolean register) {
    clearRetainedFeed();
    feedRows = null;
    feedScrollY = 0;
    subBack = null;
    shell("", false);
    toolbar.setVisibility(View.GONE);
    if (root.getChildCount() > 1)
      root.getChildAt(1).setVisibility(View.GONE);
    root.setBackgroundColor(BG);
    getWindow().setStatusBarColor(BG);
    getWindow().setNavigationBarColor(BG);
    content.setPadding(0, 0, 0, dp(24));
    content.addView(authHero(), new LinearLayout.LayoutParams(-1, dp(88)));
    LinearLayout body = column();
    body.setPadding(dp(20), dp(10), dp(20), 0);
    content.addView(body);

    LinearLayout topNav = row();
    LinearLayout home = row();
    home.setGravity(Gravity.CENTER_VERTICAL);
    home.addView(icon("arrow_left", 18, TEXT), new LinearLayout.LayoutParams(dp(18), dp(18)));
    TextView homeText = label(I18n.t("Trang chủ"), 14, TEXT);
    homeText.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    homeText.setPadding(dp(8), 0, 0, 0);
    home.addView(homeText);
    home.setPadding(0, dp(8), dp(12), dp(8));
    home.setContentDescription(I18n.t("Về trang giới thiệu"));
    home.setOnClickListener(v -> {
      introPage = 0;
      intro();
    });
    topNav.addView(home, new LinearLayout.LayoutParams(0, -2, 1));
    UiMetrics.enforceMinTouchTarget(home, 48);
    LinearLayout langChip = row();
    langChip.setGravity(Gravity.CENTER);
    langChip.setPadding(dp(10), dp(6), dp(10), dp(6));
    langChip.setBackground(outlined(CARD, 99));
    langChip.addView(icon("globe", 14, ACCENT_TEXT), new LinearLayout.LayoutParams(dp(14), dp(14)));
    TextView langLabel = label(I18n.current().equals("en") ? "EN" : "VI", 12, TEXT);
    langLabel.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    langLabel.setPadding(dp(5), 0, 0, 0);
    langChip.addView(langLabel);
    langChip.setContentDescription(I18n.t("Tiếng Việt / English"));
    langChip.setOnClickListener(v -> languageMenu());
    topNav.addView(UiMetrics.wrapMinTouchTarget(this, langChip, 48), new LinearLayout.LayoutParams(-2, -2));
    body.addView(topNav, new LinearLayout.LayoutParams(-1, -2));

    TextView title = label(register ? I18n.t("Bắt đầu kết nối của bạn.") : I18n.t("Chào bạn trở lại!"), 27, TEXT);
    title.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    title.setPadding(0, dp(10), 0, dp(2));
    body.addView(title);
    TextView caption = welcomeText(register ? I18n.t("Tạo tài khoản để chia sẻ và gặp người cùng tần số.")
        : I18n.t("Đăng nhập để tiếp tục những kết nối của bạn."), 14, MUTED, false);
    caption.setPadding(0, dp(6), 0, dp(14));
    body.addView(caption);

    final LinearLayout extras = column();
    LinearLayout saved = content;
    content = extras;
    authExtras(register);
    content = saved;
    body.addView(extras);

    final EditText name = register ? authField(body, "pencil", I18n.t("Tên hiển thị"), false) : null;
    final EditText username = authField(body, "user_round", I18n.t("Tên đăng nhập"), false);
    username.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
    username.setTypeface(ApprovedTypography.font(this, Typeface.NORMAL));
    final EditText password = authField(body, "lock_keyhole", I18n.t("Mật khẩu (từ 6 ký tự)"), true);

    final CheckBox agree = new CheckBox(this);
    final CheckBox privacyAgree = new CheckBox(this);
    final CheckBox remember = new CheckBox(this);
    remember.setChecked(true);
    LinearLayout options = row();
    options.setGravity(Gravity.CENTER_VERTICAL);
    CheckBox box = register ? agree : remember;
    box.setText(register ? I18n.t("Tôi đủ 18 tuổi và đồng ý Quy tắc cộng đồng") : I18n.t("Ghi nhớ"));
    box.setTextColor(TEXT);
    box.setTextSize(13);
    if (register)
      box.setMaxLines(3);
    box.setButtonTintList(android.content.res.ColorStateList.valueOf(ACCENT));
    options.addView(box, new LinearLayout.LayoutParams(0, -2, 1));
    UiMetrics.enforceMinTouchTarget(box, 48);
    if (!register) {
      TextView forgotLink = label(I18n.t("Quên mật khẩu?"), 13, ACCENT_TEXT);
      forgotLink.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
      forgotLink.setGravity(Gravity.CENTER_VERTICAL);
      forgotLink.setPadding(dp(8), dp(10), 0, dp(10));
      forgotLink.setOnClickListener(v -> forgot());
      options.addView(forgotLink);
      UiMetrics.enforceMinTouchTarget(forgotLink, 48);
    }
    body.addView(options, new LinearLayout.LayoutParams(-1, -2));

    if (register) {
      LinearLayout privacyRow = row();
      privacyRow.setGravity(Gravity.CENTER_VERTICAL);
      privacyAgree.setText(I18n.t("Tôi đồng ý Chính sách quyền riêng tư & Điều khoản"));
      privacyAgree.setTextColor(TEXT);
      privacyAgree.setTextSize(13);
      privacyAgree.setMaxLines(2);
      privacyAgree.setButtonTintList(android.content.res.ColorStateList.valueOf(ACCENT));
      privacyRow.addView(privacyAgree, new LinearLayout.LayoutParams(0, -2, 1));
      UiMetrics.enforceMinTouchTarget(privacyAgree, 48);
      TextView policyLink = label(I18n.t("Xem chính sách"), 12, ACCENT_TEXT);
      policyLink.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
      policyLink.setGravity(Gravity.CENTER_VERTICAL);
      policyLink.setPadding(dp(8), dp(8), 0, dp(8));
      policyLink.setOnClickListener(v -> nativeDocument("privacy", () -> auth(true)));
      privacyRow.addView(policyLink);
      UiMetrics.enforceMinTouchTarget(policyLink, 48);
      body.addView(privacyRow, new LinearLayout.LayoutParams(-1, -2));
    }

    final LinearLayout submit = authButton(register ? "user_plus" : "log_in",
        register ? I18n.t("Tạo tài khoản") : I18n.t("Đăng nhập"), true);
    submit.setOnClickListener(v -> {
      if (username.length() == 0) {
        say(I18n.t("Nhập tên đăng nhập."));
        return;
      }
      if (password.length() < 6) {
        say(I18n.t("Mật khẩu tối thiểu 6 ký tự."));
        return;
      }
      if (register && !agree.isChecked()) {
        say(I18n.t("Vui lòng xác nhận bạn đủ 18 tuổi."));
        return;
      }
      if (register && !privacyAgree.isChecked()) {
        say(I18n.t("Vui lòng đồng ý Chính sách quyền riêng tư."));
        return;
      }
      submit.setEnabled(false);
      submit.setAlpha(0.7f);
      final int generation = screen;
      final String loginUser = username.getText().toString().trim();
      final String loginPass = password.getText().toString();
      final boolean loginRemember = register || remember.isChecked();
      api.call("POST", register ? "/api/register" : "/api/login",
          json("username", loginUser, "password", loginPass, "name", name == null ? "" : name.getText().toString(),
              "agree18", agree.isChecked(), "agreePrivacy", !register || privacyAgree.isChecked(),
              "remember", loginRemember),
          (data, error, status) -> {
            if (generation != screen || isDestroyed())
              return;
            submit.setEnabled(true);
            submit.setAlpha(1f);
            if (!register && isTwoFactorRequired(status, data, error)) {
              promptTwoFactorAction(generation, "/api/login",
                  json("username", loginUser, "password", loginPass, "remember", loginRemember), password, null);
              return;
            }
            if (error != null) {
              password.setText("");
              say(error);
              return;
            }
            password.setText("");
            onUserSignedIn(data.optJSONObject("user"));
            navigate("feed");
          });
    });
    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, Math.max(dp(50), UiMetrics.dpRaw(this, 48)));
    sp.topMargin = dp(8);
    body.addView(submit, sp);

    if (register) {
      LinearLayout inlineSwap = row();
      inlineSwap.setGravity(Gravity.CENTER);
      LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(-1, -2);
      ip.topMargin = dp(12);
      TextView already = label(I18n.t("Đã có tài khoản?"), 13, MUTED);
      inlineSwap.addView(already);
      TextView loginNow = label(I18n.t("Đăng nhập ngay"), 13, ACCENT_TEXT);
      loginNow.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
      loginNow.setGravity(Gravity.CENTER);
      loginNow.setPadding(dp(6), dp(8), dp(6), dp(8));
      loginNow.setOnClickListener(v -> auth(false));
      inlineSwap.addView(loginNow);
      UiMetrics.enforceMinTouchTarget(loginNow, 48);
      body.addView(inlineSwap, ip);
    } else {
      body.addView(textDivider(I18n.t("Mới đến Kinnect?")));
      LinearLayout swap = authButton("user_plus", I18n.t("Tạo tài khoản mới"), false);
      swap.setOnClickListener(v -> auth(true));
      body.addView(swap, new LinearLayout.LayoutParams(-1, Math.max(dp(50), UiMetrics.dpRaw(this, 48))));

      TextView terms = label(I18n.t("Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng."), 12, MUTED);
      terms.setGravity(Gravity.CENTER);
      terms.setPadding(dp(8), dp(12), dp(8), dp(8));
      terms.setOnClickListener(v -> {
        try {
          startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://kinnect.io.vn/community")));
        } catch (Exception ignored) {
        }
      });
      body.addView(terms, new LinearLayout.LayoutParams(-1, -2));
      UiMetrics.enforceMinTouchTarget(terms, 48);
    }
  }

  private static boolean isTwoFactorRequired(int status, JSONObject data, String error) {
    return status == 403 && ((data != null && data.optBoolean("requires2fa"))
        || (error != null && (error.contains("2 lớp") || error.contains("2 bước") || error.contains("2FA"))));
  }

  private void promptTwoFactorAction(final int generation, final String endpoint, final JSONObject basePayload,
      final EditText passwordField, final String errorMessage) {
    if (generation != screen || isDestroyed())
      return;
    LinearLayout wrap = column();
    if (errorMessage != null && !errorMessage.isEmpty()) {
      LinearLayout errBox = column();
      TextView errTv = label(errorMessage, 13, WebDesign.DANGER[WebTheme.isDark(this) ? 1 : 0]);
      errTv.setPadding(dp(4), 0, dp(4), dp(8));
      errBox.addView(errTv);
      wrap.addView(errBox);
    }
    EditText otpInput = new KinnectInput(this);
    styleChatName(otpInput);
    otpInput.setHint(I18n.t("Mã 6 số hoặc mã dự phòng"));
    wrap.addView(chatNameWrap(otpInput));
    new Sheet(this).setTitle(I18n.t("Xác thực 2 lớp (2FA)")).setView(wrap)
        .setPositiveButton(I18n.t("Xác nhận"), (d, w) -> {
          String code = otpInput.getText().toString().trim();
          if (code.isEmpty()) {
            promptTwoFactorAction(generation, endpoint, basePayload, passwordField, I18n.t("Nhập mã xác thực 2 lớp."));
            return;
          }
          JSONObject payload;
          try {
            payload = new JSONObject(basePayload.toString());
            payload.put("totpCode", code);
          } catch (JSONException ignored) {
            payload = json("totpCode", code);
          }
          api.call("POST", endpoint, payload, (d2, e2, s2) -> {
            if (generation != screen || isDestroyed())
              return;
            if (e2 != null) {
              if (s2 == 401 || s2 == 403 || s2 == 400) {
                promptTwoFactorAction(generation, endpoint, basePayload, passwordField, e2);
              } else {
                say(e2);
              }
              return;
            }
            if (passwordField != null)
              passwordField.setText("");
            onUserSignedIn(d2.optJSONObject("user"));
            navigate("feed");
          });
        })
        .setNegativeButton(I18n.t("Huỷ"), null).show();
  }

  private View authHero() {
    LinearLayout hero = welcomeBrand();
    hero.setPadding(dp(22), dp(20), dp(22), dp(10));
    hero.setBackgroundColor(BG);
    TextView tagline = welcomeText(I18n.t("Sống đúng mình."), 12, MUTED, false);
    hero.addView(tagline);
    return hero;
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
    final EditText e = new KinnectInput(this);
    e.setHint(hint);
    e.setContentDescription(hint);
    e.setHintTextColor(MUTED);
    e.setTextColor(TEXT);
    e.setTextSize(15);
    e.setSingleLine(true);
    e.setBackground(null);
    e.setPadding(dp(10), 0, dp(8), 0);
    e.setTypeface(ApprovedTypography.font(this, Typeface.NORMAL));
    box.addView(e, new LinearLayout.LayoutParams(0, -1, 1));
    if (secret) {
      e.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
      e.setTypeface(ApprovedTypography.font(this, Typeface.NORMAL));
      final FrameLayout eye = new FrameLayout(this);
      final ImageView eyeIcon = icon("eye", 19, MUTED);
      eye.addView(eyeIcon, new FrameLayout.LayoutParams(dp(19), dp(19), Gravity.CENTER));
      eye.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
      eye.setContentDescription(I18n.t("Hiện mật khẩu"));
      eye.setBackground(pressable(CARD, 99));
      eye.setClickable(true);
      eye.setFocusable(true);
      final FrameLayout eyeWrap = UiMetrics.wrapMinTouchTarget(this, eye, 48);
      eyeWrap.setOnClickListener(v -> {
        boolean hidden = (e.getInputType()
            & InputType.TYPE_TEXT_VARIATION_PASSWORD) == InputType.TYPE_TEXT_VARIATION_PASSWORD;
        e.setInputType(InputType.TYPE_CLASS_TEXT
            | (hidden ? InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD : InputType.TYPE_TEXT_VARIATION_PASSWORD));
        e.setTypeface(ApprovedTypography.font(this, Typeface.NORMAL));
        e.setSelection(e.length());
        android.graphics.drawable.Drawable d = WebIcons.load(this, hidden ? "eye_off" : "eye");
        d.setTint(MUTED);
        eyeIcon.setImageDrawable(d);
        String desc = hidden ? I18n.t("Ẩn mật khẩu") : I18n.t("Hiện mật khẩu");
        eye.setContentDescription(desc);
        eyeWrap.setContentDescription(desc);
      });
      box.addView(eyeWrap);
    }
    e.setOnFocusChangeListener((v, focused) -> {
      GradientDrawable s = background(CARD, 14);
      s.setStroke(dp(focused ? 2 : 1), focused ? ACCENT : LINE);
      box.setBackground(s);
    });
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, Math.max(dp(52), UiMetrics.dpRaw(this, 48)));
    p.setMargins(0, dp(6), 0, dp(6));
    parent.addView(box, p);
    UiMetrics.enforceMinTouchTarget(e, 48);
    return e;
  }

  private LinearLayout authButton(String iconName, String text, boolean filled) {
    LinearLayout b = row();
    b.setGravity(Gravity.CENTER);
    b.setPadding(dp(8), 0, dp(8), 0);
    b.setMinimumHeight(UiMetrics.dpRaw(this, 48));
    b.setMinimumWidth(UiMetrics.dpRaw(this, 48));
    if (filled) {
      b.setBackground(new android.graphics.drawable.RippleDrawable(
          android.content.res.ColorStateList.valueOf(0x33ffffff), gradient(14), null));
      b.setElevation(dp(3));
    } else
      b.setBackground(outlined(CARD, 14));
    int color = filled ? WHITE : TEXT;
    if (iconName != null)
      b.addView(icon(iconName, 16, color), new LinearLayout.LayoutParams(dp(16), dp(16)));
    TextView t = label(text, 14, color);
    t.setSingleLine(true);
    t.setMaxLines(1);
    t.setEllipsize(android.text.TextUtils.TruncateAt.END);
    t.setAutoSizeTextTypeUniformWithConfiguration(10, 14, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
    t.setGravity(Gravity.CENTER);
    t.setTypeface(Typeface.create("sans-serif-medium", filled ? Typeface.BOLD : Typeface.NORMAL));
    t.setPadding(iconName == null ? 0 : dp(6), 0, 0, 0);
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

  private long lastFeedTap;
  private JSONArray feedRows;
  private int feedScrollY;
  /**
   * Set by a post mutation so the next real GET /api/posts drops its etag
   * snapshot at dispatch.
   */
  private boolean postsGetSnapshotStale;

  private void selectNavigation(String next) {
    if (next.equals("feed") && tab.equals("feed") && onTabRoot && feedRefresh != null) {
      if (content.getParent() instanceof PullRefreshScrollView) {
        PullRefreshScrollView scroll = (PullRefreshScrollView) content.getParent();
        feedScrollY = 0;
        scroll.smoothScrollTo(0, 0);
        scroll.refreshNow();
      }
      return;
    }
    navigate(next);
  }

  private void navigate(String next) {
    headerActive = next.equals("inbox") ? "inbox" : "";
    history.clear();
    subBack = null;
    currentPage = () -> navigate(next);
    currentKey = "tab:" + next;
    if (!NativeApi.isFixtureEnabled()) {
      ensureCalls();
      activity();
    }
    tab = next;
    shell(
        next.equals("inbox")
            ? I18n.t("Tin nhắn")
            : "",
        true);
    onTabRoot = true;
    if (next.equals("shorts"))
      shorts();
    if (next.equals("discover"))
      discover();
    if (next.equals("feed"))
      feed();
    if (next.equals("inbox"))
      inbox();
    if (next.equals("profile"))
      profile();
    if (next.equals("profile_albums"))
      profile(2);
    if (next.equals("live"))
      live();
  }

  private ImageView avatar(JSONObject u, LinearLayout parent, int size) {
    ImageView image = new ImageView(this);
    image.setScaleType(ImageView.ScaleType.CENTER_CROP);
    GradientDrawable round = new GradientDrawable();
    round.setShape(GradientDrawable.OVAL);
    round.setColor(PRIMARY_SOFT);
    int styleColor = StoreStyle.color(u.optString("storeStyle"));
    image.setBackground(round);
    StoreStyle.badge(image, u.optString("storeMembership"));
    if (styleColor != 0) {
      GradientDrawable border = new GradientDrawable();
      border.setShape(GradientDrawable.OVAL);
      border.setColor(android.graphics.Color.TRANSPARENT);
      border.setStroke(dp(2), styleColor);
      android.graphics.drawable.Drawable badge = image.getForeground();
      image.setForeground(badge == null ? border
          : new android.graphics.drawable.LayerDrawable(new android.graphics.drawable.Drawable[] { border, badge }));
    }
    image.setClipToOutline(true);
    image.setImageBitmap(
        u.has("members") ? groupSample(u.optString("avatarPreset", "violet"), dp(size)) : initials(u, dp(size)));
    image.setContentDescription(I18n.t("Ảnh của ") + u.optString("name"));
    parent.addView(image, new LinearLayout.LayoutParams(dp(size), dp(size)));
    loadAvatarInto(u, image);
    return image;
  }

  // Ảnh đại diện mặc định như web: vòng tròn chuyển sắc theo người dùng + chữ cái
  // đầu.
  private Bitmap initials(JSONObject u, int px) {
    px = Math.max(16, px);
    Bitmap b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
    Canvas c = new Canvas(b);
    boolean dark = WebTheme.isDark(this);
    boolean you = u != null && me != null && u.optString("id").equals(me.optString("id"))
        && !u.optString("id").isEmpty();
    Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    p.setColor(you ? (dark ? 0xff483020 : 0xfff8e6d8) : PRIMARY_SOFT);
    c.drawOval(0, 0, px, px, p);
    p.setColor(you ? (dark ? 0xffefc39f : 0xff9a562b) : ACCENT_TEXT);
    p.setTextAlign(Paint.Align.CENTER);
    p.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
    String name = u == null ? "?" : u.optString("name", u.optString("username", "?")).trim();
    StringBuilder letters = new StringBuilder();
    for (String w : name.split("\\s+"))
      if (!w.isEmpty())
        letters.append(w.substring(0, 1));
    String text = letters.length() == 0 ? "?"
        : letters.substring(Math.max(0, letters.length() - 2)).toUpperCase(Locale.ROOT);
    p.setTextSize(px * (text.length() > 1 ? 0.34f : 0.4f));
    Paint.FontMetrics fm = p.getFontMetrics();
    c.drawText(text, px / 2f, px / 2f - (fm.ascent + fm.descent) / 2f, p);
    return b;
  }

  private void discover() {
    if (nearQuery == null)
      nearQuery = "";
    renderPeopleSearch();
  }

  private void refreshPeopleSearch() {
    navigate("discover");
  }

  private void renderPeopleSearch() {
    final boolean hasLocation = me != null && me.optBoolean("hasLocation");
    final int raw48 = UiMetrics.dpRaw(this, 48);
    String[][] sorts = { { "interests", "Dành cho bạn" }, { "near", "Quanh đây" }, { "following", "Đang theo dõi" } };
    LinearLayout seg = row();
    seg.setPadding(dp(4), dp(4), dp(4), dp(4));
    seg.setBackground(background(SOFT, 14));
    for (final String[] item : sorts) {
      boolean active = discoverSort.equals(item[0]);
      TextView t = label(I18n.t(item[1]), 13, active ? ACCENT_TEXT : TEXT);
      t.setTypeface(Typeface.create(active ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
      t.setGravity(Gravity.CENTER);
      t.setSingleLine(false);
      t.setMaxLines(2);
      t.setIncludeFontPadding(false);
      t.setPadding(dp(3), 0, dp(3), 0);
      if (active) {
        t.setBackground(background(CARD, 11));
        t.setElevation(dp(1));
      } else
        t.setBackground(pressable(SOFT, 11));
      t.setOnClickListener(v -> {
        discoverSort = item[0];
        nearScrollY = 0;
        navigate("discover");
      });
      seg.addView(t, new LinearLayout.LayoutParams(0, Math.max(dp(48), raw48), 1));
      UiMetrics.enforceMinTouchTarget(t, 48);
    }
    content.addView(seg, new LinearLayout.LayoutParams(-1, -2));

    final boolean nearby = discoverSort.equals("near") && hasLocation;
    LinearLayout searchBox = row();
    searchBox.setGravity(Gravity.CENTER_VERTICAL);
    searchBox.setPadding(dp(12), 0, dp(4), 0);
    GradientDrawable sb = background(SOFT, 14);
    sb.setStroke(dp(1), LINE);
    searchBox.setBackground(sb);
    searchBox.addView(icon("search", 16, MUTED), new LinearLayout.LayoutParams(dp(16), dp(16)));
    final EditText searchInput = new KinnectInput(this);
    searchInput.setHint(I18n.t("Tìm theo tên hoặc @username…"));
    searchInput.setText(nearQuery);
    searchInput.setTextSize(14);
    searchInput.setTextColor(TEXT);
    searchInput.setHintTextColor(MUTED);
    searchInput.setSingleLine(true);
    searchInput.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH);
    searchInput.setBackground(null);
    searchInput.setPadding(dp(8), 0, dp(4), 0);
    searchBox.addView(searchInput, new LinearLayout.LayoutParams(0, -1, 1));
    UiMetrics.enforceMinTouchTarget(searchInput, 48);
    final FrameLayout clearSearch = new FrameLayout(this);
    clearSearch.setBackground(pressable(SOFT, 99));
    clearSearch.addView(icon("close", 14, MUTED), new FrameLayout.LayoutParams(dp(14), dp(14), Gravity.CENTER));
    clearSearch.setLayoutParams(new LinearLayout.LayoutParams(dp(34), dp(34)));
    clearSearch.setContentDescription(I18n.t("Xóa tìm kiếm"));
    clearSearch.setOnClickListener(v -> {
      nearQuery = "";
      searchInput.setText("");
      navigate("discover");
    });
    final View clearWrap = UiMetrics.wrapMinTouchTarget(this, clearSearch, 48);
    clearWrap.setVisibility(nearQuery.trim().isEmpty() ? View.GONE : View.VISIBLE);
    searchBox.addView(clearWrap);
    searchInput.setOnEditorActionListener((v, actionId, event) -> {
      if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH
          || (event != null && event.getKeyCode() == android.view.KeyEvent.KEYCODE_ENTER
              && event.getAction() == android.view.KeyEvent.ACTION_UP)) {
        nearScrollY = 0;
        nearQuery = searchInput.getText().toString().trim();
        clearWrap.setVisibility(nearQuery.isEmpty() ? View.GONE : View.VISIBLE);
        loadPeople(nearQuery, nearby);
        return true;
      }
      return false;
    });
    LinearLayout.LayoutParams sbp = new LinearLayout.LayoutParams(-1, Math.max(dp(48), raw48));
    sbp.topMargin = dp(10);
    content.addView(searchBox, sbp);

    peopleRefresh = complete -> {
      if (discoverSort.equals("near") && (me == null || !me.optBoolean("hasLocation"))) {
        complete.run();
        return;
      }
      nearScrollY = 0;
      loadPeople(nearQuery, nearby, complete, true);
    };
    LinearLayout quick = row();
    quick.setPadding(0, dp(10), 0, dp(12));
    String[] titles = { "Tuổi", "Cân nặng", "Chiều cao", "Giới tính", "" };
    String[] keys = { "age", "weight", "height", "gender", "" };
    float[] weights = { .8f, 1.2f, 1.25f, 1.1f };
    for (int i = 0; i < 5; i++) {
      final String key = keys[i];
      boolean selected = i == 0 ? nearMinAge > 0 || nearMaxAge > 0
          : i == 1 ? nearMinWeight > 0 || nearMaxWeight > 0
              : i == 2 ? nearMinHeight > 0 || nearMaxHeight > 0
                  : i == 3 ? !nearGender.isEmpty()
                      : nearOnline || nearRecent || !nearOrientation.isEmpty() || !nearCommunityRole.isEmpty()
                          || !nearIntent.isEmpty();
      LinearLayout button = row();
      button.setGravity(Gravity.CENTER);
      button.setPadding(dp(3), 0, dp(3), 0);
      button.setBackground(pressable(selected ? PRIMARY_SOFT : SOFT, 10));
      if (i == 4) {
        button.addView(icon("sliders_horizontal", 20, selected ? ACCENT_TEXT : MUTED),
            new LinearLayout.LayoutParams(dp(20), dp(20)));
      } else {
        TextView caption = label(I18n.t(titles[i]), 12, selected ? ACCENT_TEXT : TEXT);
        caption.setGravity(Gravity.CENTER);
        caption.setPadding(0, 0, 0, 0);
        caption.setSingleLine(false);
        caption.setMaxLines(2);
        caption.setIncludeFontPadding(false);
        caption.setAutoSizeTextTypeUniformWithConfiguration(9, 12, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
        button.addView(caption, new LinearLayout.LayoutParams(-1, -1));
      }
      button.setContentDescription(
          (i == 4 ? I18n.t("Bộ lọc tổng hợp") : titles[i]) + (selected ? I18n.t(" · Đang chọn") : ""));
      button.setSelected(selected);
      button.setOnClickListener(v -> nearFilters(key));
      LinearLayout.LayoutParams bp = i == 4 ? new LinearLayout.LayoutParams(raw48, raw48)
          : new LinearLayout.LayoutParams(0, raw48, weights[i]);
      if (i > 0)
        bp.leftMargin = dp(4);
      quick.addView(button, bp);
      UiMetrics.enforceMinTouchTarget(button, 48);
    }
    content.addView(quick, new LinearLayout.LayoutParams(-1, -2));
    if (discoverSort.equals("near") && !hasLocation) {
      content
          .addView(emptyBlock("map_pin", I18n.t("Khám phá quanh bạn"), I18n.t("Bật vị trí để tìm thành viên ở gần.")));
      content.addView(primary(I18n.t("Bật vị trí"), () -> requestLocation()));
      return;
    }
    loadPeople(nearQuery, nearby);
  }

  private LinearLayout people;

  private void loadPeople(String query, boolean nearby) {
    loadPeople(query, nearby, () -> {
    }, false);
  }

  private void loadPeople(String query, boolean nearby, Runnable complete, boolean refreshing) {
    if (!nearQuery.equals(query))
      nearScrollY = 0;
    nearQuery = query;
    if (people != null && people.getParent() == content)
      content.removeView(people);
    people = column();
    content.addView(people);
    final LinearLayout list = people;
    final String requestedTab = discoverSort;
    String filters = "&minWeight=" + nearMinWeight + "&maxWeight=" + nearMaxWeight + "&minHeight=" + nearMinHeight
        + "&maxHeight=" + nearMaxHeight + "&orientation=" + encode(nearOrientation) + "&communityRole="
        + encode(nearCommunityRole) + "&gender=" + encode(nearGender) + "&minAge=" + nearMinAge + "&maxAge="
        + nearMaxAge + "&intent=" + encode(nearIntent) + (nearRecent ? "&recent=1" : "");
    String sort = nearOnline ? "active" : requestedTab.equals("near") ? "new" : "interests";
    String path = "/api/discover?q=" + encode(query) + (nearby ? "&nearby=1&radius=" + discoverRadius : "") + filters
        + "&sort=" + sort + (requestedTab.equals("following") ? "&following=1" : "");
    Done render = data -> {
      if (people != list || !discoverSort.equals(requestedTab))
        return;
      list.removeAllViews();
      boolean filtered = nearMinWeight > 0 || nearMaxWeight > 0 || nearMinHeight > 0 || nearMaxHeight > 0 || nearOnline
          || !nearOrientation.isEmpty() || !nearCommunityRole.isEmpty() || !nearGender.isEmpty() || nearMinAge > 0
          || nearMaxAge > 0 || !nearIntent.isEmpty() || nearRecent;
      if (filtered && data.optInt("filterVersion") < 2) {
        list.addView(label(I18n.t("Máy chủ cần cập nhật để áp dụng bộ lọc. Các kết quả chưa lọc sẽ không hiển thị."),
            14, MUTED));
        return;
      }
      JSONArray users = data.optJSONArray("users");
      if (users == null || users.length() == 0) {
        list.addView(discoveryEmptyState(), new LinearLayout.LayoutParams(-1, -2));
        return;
      }
      if (!query.trim().isEmpty()) {
        LinearLayout summary = row();
        summary.setGravity(Gravity.CENTER_VERTICAL);
        summary.setPadding(0, dp(2), 0, dp(10));
        TextView count = label(String.format(Locale.US, I18n.t("%d kết quả cho '%s'"), users.length(), query.trim()), 13,
            MUTED);
        summary.addView(count, new LinearLayout.LayoutParams(0, -2, 1));
        TextView showAll = label(I18n.t("Xem tất cả"), 12, ACCENT_TEXT);
        showAll.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        showAll.setGravity(Gravity.CENTER);
        showAll.setPadding(dp(10), dp(6), dp(10), dp(6));
        showAll.setBackground(pressable(PRIMARY_SOFT, 99));
        showAll.setOnClickListener(v -> {
          nearQuery = "";
          navigate("discover");
        });
        summary.addView(showAll, new LinearLayout.LayoutParams(-2, -2));
        UiMetrics.enforceMinTouchTarget(showAll, 48);
        list.addView(summary, new LinearLayout.LayoutParams(-1, -2));
      }
      WindowedListBinder.clearPending(list);
      AdaptivePeopleGrid grid = new AdaptivePeopleGrid();
      list.addView(grid, new LinearLayout.LayoutParams(-1, -2));
      WindowedListBinder.bind(this, list, users, 18, dp(800), () -> people == list && discoverSort.equals(requestedTab),
          (start, end) -> {
            MediaImageLoader.prefetchUsers(api, users, start, Math.min(9, users.length() - start), 256);
            for (int i = start; i < end; i++)
              grid.addView(nearTile(users.optJSONObject(i)));
          });
      list.post(() -> {
        if (people == list && content.getParent() instanceof ScrollView)
          ((ScrollView) content.getParent()).scrollTo(0, nearScrollY);
      });
    };
    if (refreshing)
      request("GET", path, null, render, complete);
    else
      cachedRequest(path, render, complete);
  }

  private String nearQuery = "", nearGender = "", nearOrientation = "", nearCommunityRole = "", nearIntent = "";
  private boolean nearOnline, nearRecent;
  private int nearMinAge, nearMaxAge, nearMinWeight, nearMaxWeight, nearMinHeight, nearMaxHeight, nearScrollY;

  private View discoveryEmptyState() {
    LinearLayout empty = column();
    empty.setGravity(Gravity.CENTER_HORIZONTAL);
    empty.setPadding(dp(20), dp(36), dp(20), dp(28));
    GradientDrawable eb = background(CARD, WebDesign.CARD_RADIUS);
    eb.setStroke(dp(1), LINE);
    empty.setBackground(eb);
    FrameLayout bubble = new FrameLayout(this);
    bubble.setBackground(background(PRIMARY_SOFT, 99));
    bubble.addView(icon("users_round", 28, ACCENT_TEXT), new FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER));
    empty.addView(bubble, new LinearLayout.LayoutParams(dp(64), dp(64)));
    TextView t = label(discoverSort.equals("following") ? I18n.t("Chưa theo dõi ai") : I18n.t("Chưa tìm thấy ai"), 17,
        TEXT);
    t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    t.setGravity(Gravity.CENTER);
    t.setPadding(0, dp(14), 0, dp(2));
    empty.addView(t);
    TextView s = label(discoverSort.equals("following") ? I18n.t("Khám phá và theo dõi những người bạn quan tâm.")
        : discoverSort.equals("near") ? I18n.t("Thử mở rộng bán kính hoặc điều chỉnh bộ lọc.")
            : I18n.t("Thử điều chỉnh bộ lọc để tìm thêm thành viên."),
        13, MUTED);
    s.setGravity(Gravity.CENTER);
    empty.addView(s, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout all = authButton("users_round", I18n.t("Xem tất cả"), true);
    all.setPadding(dp(18), 0, dp(18), 0);
    all.setOnClickListener(v -> {
      nearQuery = "";
      discoverSort = "interests";
      navigate("discover");
    });
    LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(-2, Math.max(dp(44), UiMetrics.dpRaw(this, 48)));
    ap.topMargin = dp(18);
    empty.addView(all, ap);
    return empty;
  }

  private final class AdaptivePeopleGrid extends ViewGroup {
    private int columns = 3, cell, gap;

    AdaptivePeopleGrid() {
      super(MainActivity.this);
      gap = dp(8);
    }

    @Override
    protected ViewGroup.LayoutParams generateDefaultLayoutParams() {
      return new ViewGroup.LayoutParams(-2, -2);
    }

    @Override
    protected void onMeasure(int widthSpec, int heightSpec) {
      int width = MeasureSpec.getSize(widthSpec);
      columns = Math.max(3, Math.min(6, (width + gap) / (dp(128) + gap)));
      cell = Math.max(0, (width - gap * (columns - 1)) / columns);
      int exact = MeasureSpec.makeMeasureSpec(cell, MeasureSpec.EXACTLY);
      for (int i = 0; i < getChildCount(); i++)
        getChildAt(i).measure(exact, exact);
      int rows = (getChildCount() + columns - 1) / columns;
      setMeasuredDimension(width, rows == 0 ? 0 : rows * (cell + gap));
    }

    @Override
    protected void onLayout(boolean changed, int l, int t, int r, int b) {
      for (int i = 0; i < getChildCount(); i++) {
        int x = (i % columns) * (cell + gap), y = (i / columns) * (cell + gap);
        getChildAt(i).layout(x, y, x + cell, y + cell);
      }
    }
  }

  private final class SquarePeopleTile extends FrameLayout {
    SquarePeopleTile() {
      super(MainActivity.this);
    }

    @Override
    protected void onMeasure(int widthSpec, int heightSpec) {
      int side = View.MeasureSpec.getSize(widthSpec);
      super.onMeasure(widthSpec, View.MeasureSpec.makeMeasureSpec(side, View.MeasureSpec.EXACTLY));
    }
  }

  private View nearTile(JSONObject u) {
    FrameLayout tile = new SquarePeopleTile();
    tile.setBackground(background(SOFT, 14));
    tile.setClipToOutline(true);
    ImageView photo = new ImageView(this);
    String path = u.optString("avatar", "");
    if (!path.isEmpty() && !path.equals("null")) {
      photo.setScaleType(ImageView.ScaleType.CENTER_CROP);
      loadAvatarInto(u, photo);
    } else {
      photo.setScaleType(ImageView.ScaleType.FIT_CENTER);
      photo.setImageDrawable(WebIcons.load(this, "user_round"));
      photo.setImageTintList(android.content.res.ColorStateList.valueOf(MUTED));
      photo.setPadding(dp(20), dp(20), dp(20), dp(20));
    }
    tile.addView(photo, new FrameLayout.LayoutParams(-1, -1));
    if (RegistrationBadge.today(u.optLong("joinedAt"), System.currentTimeMillis())) {
      TextView badge = label(I18n.t("Mới"), 10, WHITE);
      badge.setPadding(dp(7), dp(3), dp(7), dp(3));
      badge.setBackground(background(ACCENT, 99));
      badge.setContentDescription(I18n.t("Đăng ký hôm nay"));
      FrameLayout.LayoutParams at = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.END);
      at.setMargins(dp(5), dp(5), dp(5), 0);
      tile.addView(badge, at);
    }
    View shade = new View(this);
    shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, WebDesign.SCRIM_BOTTOM));
    FrameLayout.LayoutParams shadow = new FrameLayout.LayoutParams(-1, dp(68), Gravity.BOTTOM);
    tile.addView(shade, shadow);
    LinearLayout meta = column();
    meta.setPadding(dp(8), 0, dp(8), dp(6));
    double distKm = u.optDouble("distanceKm", -1);
    String distance = u.optString("distanceLabel", "").trim();
    if (distance.isEmpty() || distance.equals("null")) {
      if (distKm >= 0)
        distance = distKm < 0.1 ? "< 100 m" : String.format(Locale.US, "%.1f km", distKm);
      else {
        String city = u.optString("city", "").trim();
        if (!city.isEmpty() && !city.equals("null"))
          distance = city;
      }
    }
    if (!distance.isEmpty()) {
      LinearLayout distRow = row();
      distRow.setGravity(Gravity.CENTER_VERTICAL);
      ImageView pin = new ImageView(this);
      pin.setImageDrawable(WebIcons.load(this, "map_pin"));
      pin.setImageTintList(android.content.res.ColorStateList.valueOf(0xddffffff));
      distRow.addView(pin, new LinearLayout.LayoutParams(dp(10), dp(10)));
      TextView km = label(distance, 11, 0xf2ffffff);
      km.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
      km.setPadding(dp(3), 0, 0, dp(1));
      distRow.addView(km);
      meta.addView(distRow);
    }
    TextView name = label(u.optString("name"), 13, WHITE);
    name.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
    name.setSingleLine(true);
    name.setAutoSizeTextTypeUniformWithConfiguration(11, 14, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
    name.setEllipsize(android.text.TextUtils.TruncateAt.END);
    name.setPadding(0, 0, 0, 0);
    meta.addView(name);
    tile.addView(meta, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
    boolean isOnline = u.optBoolean("isActive") && u.optBoolean("showActivity", true);
    if (isOnline) {
      View online = new View(this);
      GradientDrawable dotBg = background(WebDesign.ONLINE_STRICT[WebTheme.isDark(this) ? 1 : 0], 99);
      dotBg.setStroke(dp(2), CARD);
      online.setBackground(dotBg);
      FrameLayout.LayoutParams dot = new FrameLayout.LayoutParams(dp(10), dp(10), Gravity.TOP | Gravity.START);
      dot.setMargins(dp(7), dp(7), 0, 0);
      tile.addView(online, dot);
    }
    tile.setContentDescription(
        I18n.t("Xem hồ sơ ") + u.optString("name") + (distance.isEmpty() ? "" : " · " + distance));
    tile.setOnClickListener(v -> {
      if (content.getParent() instanceof ScrollView)
        nearScrollY = ((ScrollView) content.getParent()).getScrollY();
      person(u);
    });
    return tile;
  }

  private void nearFilters() {
    nearFilters("");
  }

  private EditText[] filterRange(LinearLayout form, String title, String unit, int min, int max) {
    form.addView(label(title + " (" + unit + ")", 14, TEXT));
    LinearLayout pair = row();
    form.addView(pair);
    LinearLayout left = column(), right = column();
    pair.addView(left, new LinearLayout.LayoutParams(0, -2, 1));
    LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(0, -2, 1);
    rp.leftMargin = dp(10);
    pair.addView(right, rp);
    EditText low = input(left, I18n.t("Từ"), min == 0 ? "" : String.valueOf(min), false),
        high = input(right, I18n.t("Đến"), max == 0 ? "" : String.valueOf(max), false);
    low.setInputType(2);
    high.setInputType(2);
    return new EditText[] { low, high };
  }

  private int[] readFilterRange(EditText[] fields, int minimum, int maximum) {
    int low = fields[0].length() == 0 ? 0 : Integer.parseInt(fields[0].getText().toString()),
        high = fields[1].length() == 0 ? 0 : Integer.parseInt(fields[1].getText().toString());
    if (low != 0 && (low < minimum || low > maximum) || high != 0 && (high < minimum || high > maximum)
        || low > 0 && high > 0 && low > high)
      throw new IllegalArgumentException();
    return new int[] { low, high };
  }

  private Spinner filterChoice(LinearLayout form, String title, String[] choices, String selected) {
    form.addView(label(title, 14, TEXT));
    Spinner field = new Spinner(this);
    field.setAdapter(new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, choices) {
      @Override
      public View getView(int position, View view, ViewGroup parent) {
        TextView text = (TextView) super.getView(position, view, parent);
        text.setText(I18n.t(getItem(position)));
        return text;
      }

      @Override
      public View getDropDownView(int position, View view, ViewGroup parent) {
        TextView text = (TextView) super.getDropDownView(position, view, parent);
        text.setText(I18n.t(getItem(position)));
        return text;
      }
    });
    for (int i = 0; i < choices.length; i++)
      if (choices[i].equals(selected))
        field.setSelection(i);
    form.addView(field);
    return field;
  }

  private void nearFilters(final String only) {
    boolean all = only.isEmpty();
    LinearLayout form = column();
    final EditText[] ages = all || only.equals("age")
        ? filterRange(form, I18n.t("Tuổi"), "18–99", nearMinAge, nearMaxAge)
        : null;
    final EditText[] weights = all || only.equals("weight")
        ? filterRange(form, I18n.t("Cân nặng"), "kg", nearMinWeight, nearMaxWeight)
        : null;
    final EditText[] heights = all || only.equals("height")
        ? filterRange(form, I18n.t("Chiều cao"), "cm", nearMinHeight, nearMaxHeight)
        : null;
    String[] genders = { "Tất cả", "Nam", "Nữ", "Nam chuyển giới", "Nữ chuyển giới", "Phi nhị nguyên", "Linh hoạt giới",
        "Vô giới", "Khác" };
    final Spinner gender = all || only.equals("gender") ? filterChoice(form, I18n.t("Giới tính"), genders, nearGender)
        : null;
    String[] orientations = { "Tất cả", "Gay / Đồng tính nam", "Lesbian / Đồng tính nữ", "Song tính / Bisexual",
        "Toàn tính / Pansexual", "Vô tính / Asexual", "Dị tính", "Queer", "Á tính / Demisexual", "Đang tìm hiểu",
        "Khác" };
    final Spinner orientation = all ? filterChoice(form, I18n.t("Xu hướng tính dục"), orientations, nearOrientation)
        : null;
    String[] roles = { "Tất cả", "Top", "Bottom", "Vers", "Vers Top", "Vers Bottom", "Side", "Femme", "Masc / Butch",
        "Androgynous", "Stem", "Đang tìm hiểu", "Khác" };
    final Spinner community = all ? filterChoice(form, I18n.t("Vai trò tự mô tả"), roles, nearCommunityRole) : null;
    String[] intents = { "Tất cả", "Trò chuyện", "Kết bạn", "Hẹn hò" };
    final Spinner intent = all ? filterChoice(form, I18n.t("Mục đích kết nối"), intents, nearIntent) : null;
    CheckBox online = new CheckBox(this);
    online.setText(I18n.t("Đang online"));
    online.setChecked(nearOnline);
    CheckBox recent = new CheckBox(this);
    recent.setText(I18n.t("Hoạt động gần đây"));
    recent.setChecked(nearRecent);
    if (all) {
      form.addView(online);
      form.addView(recent);
    }
    final int[] radii = { 1, 5, 10, 25, 50 };
    final Spinner radius = all && discoverSort.equals("near") ? filterChoice(form, I18n.t("Bán kính"),
        new String[] { "1 km", "5 km", "10 km", "25 km", "50 km" }, discoverRadius + " km") : null;
    String title = only.equals("age") ? "Lọc theo tuổi"
        : only.equals("weight") ? "Lọc theo cân nặng"
            : only.equals("height") ? "Lọc theo chiều cao"
                : only.equals("gender") ? "Lọc theo giới tính" : "Bộ lọc thành viên";
    final Sheet builder = new Sheet(this).setTitle(I18n.t(title)).setView(form).setNegativeButton(I18n.t("Hủy"), null)
        .setNeutralButton(I18n.t("Đặt lại"), (d, index) -> {
          if (all || only.equals("age"))
            nearMinAge = nearMaxAge = 0;
          if (all || only.equals("weight"))
            nearMinWeight = nearMaxWeight = 0;
          if (all || only.equals("height"))
            nearMinHeight = nearMaxHeight = 0;
          if (all || only.equals("gender"))
            nearGender = "";
          if (all) {
            nearOrientation = nearCommunityRole = nearIntent = "";
            nearOnline = nearRecent = false;
            discoverRadius = 5;
          }
          nearScrollY = 0;
          refreshPeopleSearch();
        });
    final android.app.Dialog[] dialog = { null };
    form.addView(primary(I18n.t("Áp dụng"), () -> {
      try {
        int[] age = ages == null ? null : readFilterRange(ages, 18, 99),
            weight = weights == null ? null : readFilterRange(weights, 20, 400),
            height = heights == null ? null : readFilterRange(heights, 80, 250);
        if (age != null) {
          nearMinAge = age[0];
          nearMaxAge = age[1];
        }
        if (weight != null) {
          nearMinWeight = weight[0];
          nearMaxWeight = weight[1];
        }
        if (height != null) {
          nearMinHeight = height[0];
          nearMaxHeight = height[1];
        }
        if (gender != null)
          nearGender = gender.getSelectedItemPosition() == 0 ? "" : genders[gender.getSelectedItemPosition()];
        if (all) {
          nearOrientation = orientation.getSelectedItemPosition() == 0 ? ""
              : orientations[orientation.getSelectedItemPosition()];
          nearCommunityRole = community.getSelectedItemPosition() == 0 ? ""
              : roles[community.getSelectedItemPosition()];
          nearIntent = intent.getSelectedItemPosition() == 0 ? "" : intents[intent.getSelectedItemPosition()];
          nearOnline = online.isChecked();
          nearRecent = recent.isChecked();
          if (radius != null)
            discoverRadius = radii[radius.getSelectedItemPosition()];
        }
        if (dialog[0] != null)
          dialog[0].dismiss();
        nearScrollY = 0;
        refreshPeopleSearch();
      } catch (IllegalArgumentException error) {
        say(I18n.t(
            "Nhập khoảng hợp lệ: tuổi 18–99, cân nặng 20–400 kg, chiều cao 80–250 cm. Giá trị Từ không lớn hơn Đến."));
      }
    }));
    dialog[0] = builder.show();
  }

  private LinearLayout personTile(final JSONObject u) {
    LinearLayout c = column();
    c.setGravity(Gravity.CENTER_HORIZONTAL);
    c.setPadding(dp(8), dp(16), dp(8), dp(10));
    GradientDrawable tileBg = background(CARD, 20);
    tileBg.setStroke(dp(1), LINE);
    c.setBackground(tileBg);
    c.setElevation(dp(2));
    tactile(c);
    c.setOnClickListener(v -> person(u));
    c.setContentDescription(I18n.t("Xem hồ sơ ") + u.optString("name"));
    FrameLayout photo = new FrameLayout(this);
    LinearLayout holder = new LinearLayout(this);
    holder.setGravity(Gravity.CENTER);
    avatar(u, holder, 64);
    photo.addView(holder, new FrameLayout.LayoutParams(dp(64), dp(64), Gravity.CENTER));
    if (u.optBoolean("isActive")) {
      View online = new View(this);
      GradientDrawable dotBg = background(WebDesign.ONLINE_STRICT[WebTheme.isDark(this) ? 1 : 0], 99);
      dotBg.setStroke(dp(2), CARD);
      online.setBackground(dotBg);
      photo.addView(online, new FrameLayout.LayoutParams(dp(14), dp(14), Gravity.BOTTOM | Gravity.END));
    }
    c.addView(photo, new LinearLayout.LayoutParams(-1, dp(68)));
    TextView name = label(u.optString("name"), 14, TEXT);
    name.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
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
      km.addView(icon("map_pin", 11, ACCENT_TEXT), new LinearLayout.LayoutParams(dp(11), dp(11)));
      TextView kt = label(distance, 11, ACCENT_TEXT);
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
    if (state.equals("friends"))
      actions.addView(roundAction("message", I18n.t("Nhắn tin"), true, () -> chat(u)));
    else if (state.equals("incoming"))
      actions.addView(roundAction("check", I18n.t("Chấp nhận kết bạn"), true,
          () -> request("POST", "/api/users/" + u.optString("id") + "/friend-request/respond", json("action", "accept"),
              d -> navigate("discover"))));
    else
      actions.addView(roundAction(state.equals("outgoing") ? "user_check" : "user_plus",
          state.equals("outgoing") ? I18n.t("Huỷ lời mời") : I18n.t("Kết bạn"), !state.equals("outgoing"),
          () -> request(state.equals("outgoing") ? "DELETE" : "POST",
              "/api/users/" + u.optString("id") + "/friend-request", json(), d -> navigate("discover"))));
    actions.addView(roundAction("arrow_up_right", I18n.t("Xem hồ sơ"), false, () -> person(u)));
    c.addView(actions, new LinearLayout.LayoutParams(-1, UiMetrics.dpRaw(this, 48)));
    return c;
  }

  private View roundAction(String iconName, String description, boolean filled, Runnable action) {
    FrameLayout f = new FrameLayout(this);
    f.setBackground(filled ? pressable(ACCENT, 99) : outlined(SOFT, 99));
    f.addView(icon(iconName, 16, filled ? WHITE : TEXT), new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
    f.setContentDescription(description);
    f.setOnClickListener(v -> {
      if (!v.isEnabled())
        return;
      v.setEnabled(false);
      v.postDelayed(() -> v.setEnabled(true), 700);
      action.run();
    });
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(dp(34), dp(34));
    p.setMargins(dp(2), 0, dp(2), 0);
    f.setLayoutParams(p);
    return UiMetrics.wrapMinTouchTarget(this, f, 48);
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
    if (values != null)
      for (int i = 0; i < values.length(); i++)
        parts.add(
            values.optString(i));
    return android.text.TextUtils.join(" · ", parts);
  }

  private void person(final JSONObject u) {
    remember("person:" + u.optString("id"), () -> person(u));
    shell("", true);
    profileCard(u, u.optString("id").equals(me == null ? "" : me.optString("id")));
    profileSections(u);
  }

  private void confirm(String message, Runnable yes) {
    confirm(message, I18n.t("Xác nhận"), yes);
  }

  private void confirm(String message, String positiveLabel, Runnable yes) {
    new Sheet(this)
        .setMessage(message)
        .setPositiveButton(positiveLabel, (d, w) -> yes.run())
        .setNegativeButton(I18n.t("Hủy"), null)
        .show();
  }

  private void report(String type, String id) {
    final String[] reasons = { "An toàn trẻ em", "Quấy rối hoặc bắt nạt", "Thù ghét hoặc phân biệt đối xử",
        "Giả mạo tài khoản", "Lừa đảo hoặc spam", "Nội dung tình dục không phù hợp", "Bạo lực hoặc nguy hiểm",
        "Vấn đề khác" };
    final String[] icons = { "shield_check", "flag", "shield_check", "user_round", "mail", "eye_off", "flag",
        "circle_help" };
    final int[] selected = { 0 };
    final LinearLayout[] rows = new LinearLayout[reasons.length];
    final ImageView[] checks = new ImageView[reasons.length];
    final int raw48 = UiMetrics.dpRaw(this, 48);

    LinearLayout body = column();
    for (int i = 0; i < reasons.length; i++) {
      final int idx = i;
      LinearLayout item = row();
      item.setGravity(Gravity.CENTER_VERTICAL);
      item.setPadding(dp(12), dp(8), dp(12), dp(8));
      item.setBackground(pressable(i == 0 ? PRIMARY_SOFT : SOFT, 12));
      item.addView(icon(icons[i], 18, i == 0 ? ACCENT_TEXT : MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
      TextView t = label(I18n.t(reasons[i]), 14, TEXT);
      t.setPadding(dp(10), 0, dp(8), 0);
      item.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
      ImageView check = icon("check", 16, ACCENT_TEXT);
      check.setVisibility(i == 0 ? View.VISIBLE : View.INVISIBLE);
      item.addView(check, new LinearLayout.LayoutParams(dp(16), dp(16)));
      LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(-1, -2);
      ip.bottomMargin = dp(6);
      body.addView(item, ip);
      UiMetrics.enforceMinTouchTarget(item, 48);
      rows[i] = item;
      checks[i] = check;
      item.setOnClickListener(v -> {
        selected[0] = idx;
        for (int j = 0; j < rows.length; j++) {
          boolean active = j == idx;
          rows[j].setBackground(pressable(active ? PRIMARY_SOFT : SOFT, 12));
          checks[j].setVisibility(active ? View.VISIBLE : View.INVISIBLE);
        }
      });
    }

    final EditText detail = new KinnectInput(this);
    detail.setHint(I18n.t("Bổ sung chi tiết (tùy chọn)"));
    detail.setTextColor(TEXT);
    detail.setHintTextColor(MUTED);
    detail.setTextSize(14);
    detail.setBackground(outlined(CARD, 12));
    detail.setPadding(dp(12), dp(10), dp(12), dp(10));
    LinearLayout.LayoutParams dpBox = new LinearLayout.LayoutParams(-1, -2);
    dpBox.topMargin = dp(6);
    dpBox.bottomMargin = dp(8);
    body.addView(detail, dpBox);
    UiMetrics.enforceMinTouchTarget(detail, 48);

    final android.widget.Switch blockSwitch = "user".equals(type) ? new android.widget.Switch(this) : null;
    if (blockSwitch != null) {
      LinearLayout blockRow = row();
      blockRow.setGravity(Gravity.CENTER_VERTICAL);
      blockRow.setPadding(dp(12), dp(4), dp(12), dp(4));
      blockRow.setMinimumHeight(raw48);
      blockRow.setBackground(outlined(CARD, 12));
      TextView blockText = label(I18n.t("Đồng thời chặn người dùng này"), 14, TEXT);
      blockRow.addView(blockText, new LinearLayout.LayoutParams(0, -2, 1));
      blockSwitch.setChecked(false);
      blockSwitch.setMinimumWidth(raw48);
      blockSwitch.setMinimumHeight(raw48);
      blockRow.addView(blockSwitch, new LinearLayout.LayoutParams(-2, raw48));
      UiMetrics.enforceMinTouchTarget(blockSwitch, 48);
      blockRow.setOnClickListener(v -> blockSwitch.toggle());
      body.addView(blockRow, new LinearLayout.LayoutParams(-1, -2));
      UiMetrics.enforceMinTouchTarget(blockRow, 48);
    }

    ScrollView scroll = new ScrollView(this);
    scroll.addView(body);
    new Sheet(this)
        .setTitle(I18n.t("Báo cáo vi phạm"))
        .setView(scroll)
        .setPositiveButton(I18n.t("Gửi báo cáo"), (dialog, w) -> {
          String category = reasons[selected[0]];
          String extra = detail.getText().toString().trim();
          request(
              "POST",
              "/api/reports",
              json("targetType", type, "targetId", id, "reason",
                  extra.isEmpty() ? category : category + ": " + extra),
              data -> {
                if (blockSwitch != null && blockSwitch.isChecked())
                  request("POST", "/api/users/" + id + "/block", json(), ignored -> {});
                say(I18n.t("Đã gửi báo cáo để quản trị viên xem xét."));
              });
        })
        .setNegativeButton(I18n.t("Hủy"), null)
        .show();
  }

  private void clearRetainedFeed() {
    for (VideoView video : retainedFeedVideos)
      try {
        video.stopPlayback();
      } catch (RuntimeException ignored) {
      }
    retainedFeedVideos.clear();
    retainedFeed = null;
    retainedFeedContent = null;
    retainedFeedRefresh = null;
  }

  private void feed() {
    if (feedRows != null && retainedFeed != null) {
      View placeholder = (View) content.getParent();
      ViewGroup host = (ViewGroup) placeholder.getParent();
      int index = host.indexOfChild(placeholder);
      ViewGroup.LayoutParams params = placeholder.getLayoutParams();
      host.removeView(placeholder);
      content = retainedFeedContent;
      feedRefresh = retainedFeedRefresh;
      host.addView(retainedFeed, index, params);
      mediaVideos.addAll(retainedFeedVideos);
      retainedFeedVideos.clear();
      retainedFeed = null;
      retainedFeedContent = null;
      retainedFeedRefresh = null;
      return;
    }
    clearRetainedFeed();
    if (me != null && me.optBoolean("isNew"))
      profileCompletion();
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
    LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(0, Math.max(dp(44), UiMetrics.dpRaw(this, 48)), 1);
    pp.leftMargin = dp(10);
    r.addView(pill, pp);
    UiMetrics.enforceMinTouchTarget(pill, 48);
    composer.addView(r);
    composer.setOnClickListener(v -> composePost());
    pill.setOnClickListener(v -> composePost());
    final LinearLayout list = column();
    content.addView(list);
    final boolean memoryFeed = feedRows != null;
    if (feedRows == null) {
      JSONObject saved = api.cachedGet("/api/posts?limit=25");
      if (saved != null) {
        feedRows = saved.optJSONArray("posts");
        feedHasMore = saved.optBoolean("hasMore");
        feedNextCursor = saved.optLong("nextCursor", 0);
      }
    }
    if (feedRows != null) {
      LinearLayout saved = content;
      content = list;
      try {
        posts(feedRows, "Chưa có bài viết.");
        if (feedHasMore && feedNextCursor > 0) {
          Button moreBtn = button(I18n.t("Xem thêm bài viết"), () -> loadMoreFeedPosts(list));
          moreBtn.setTag("feed:load-more");
          list.addView(moreBtn);
        }
      } finally {
        content = saved;
      }
      final ScrollView scroll = (ScrollView) content.getParent();
      scroll.post(() -> scroll.scrollTo(0, feedScrollY));
    }
    final String[] signature = { feedRows == null ? "" : feedRows.toString() };
    final boolean[] fetching = { false };
    final boolean[] refreshAgain = { false };
    final RefreshLoader[] activeFeedRefresh = new RefreshLoader[1];
    activeFeedRefresh[0] = complete -> {
      if (fetching[0]) {
        refreshAgain[0] = true;
        complete.run();
        return;
      }
      fetching[0] = true;
      if (postsGetSnapshotStale) {
        postsGetSnapshotStale = false;
        api.clearGetSnapshot("/api/posts?limit=25");
      }
      request("GET", "/api/posts?limit=25", null, data -> {
        JSONArray posts = data.optJSONArray("posts");
        if (posts == null)
          return;
        feedHasMore = data.optBoolean("hasMore");
        feedNextCursor = data.optLong("nextCursor", 0);
        if (posts.toString().equals(signature[0])) {
          feedRows = posts;
          View lastChild = list.getChildCount() > 0 ? list.getChildAt(list.getChildCount() - 1) : null;
          boolean hasMoreBtn = lastChild != null && "feed:load-more".equals(lastChild.getTag());
          if (feedHasMore && feedNextCursor > 0 && !hasMoreBtn) {
            Button moreBtn = button(I18n.t("Xem thêm bài viết"), () -> loadMoreFeedPosts(list));
            moreBtn.setTag("feed:load-more");
            list.addView(moreBtn);
          } else if ((!feedHasMore || feedNextCursor <= 0) && hasMoreBtn) {
            list.removeView(lastChild);
          }
          return;
        }
        signature[0] = posts.toString();
        feedRows = posts;
        WindowedListBinder.clearPending(list);
        MediaImageLoader.prefetchPosts(api, posts, 0, Math.min(8, posts.length()), 1280);
        LinearLayout next = column();
        java.util.Set<String> existing = new java.util.HashSet<>();
        for (int i = 0; i < list.getChildCount(); i++)
          if (list.getChildAt(i).getTag() instanceof String)
            existing.add((String) list.getChildAt(i).getTag());
        LinearLayout saved = content;
        content = next;
        try {
          if (posts.length() == 0)
            posts(posts, "Chưa có bài viết.");
          for (int i = 0; i < posts.length(); i++) {
            JSONObject post = posts.optJSONObject(i);
            String key = "post:" + post.optString("id") + ":" + post.toString();
            if (existing.contains(key)) {
              View placeholder = new View(this);
              placeholder.setTag(key);
              next.addView(placeholder);
            } else
              postCard(post);
          }
          if (feedHasMore && feedNextCursor > 0) {
            Button moreBtn = button(I18n.t("Xem thêm bài viết"), () -> loadMoreFeedPosts(list));
            moreBtn.setTag("feed:load-more");
            next.addView(moreBtn);
          }
        } finally {
          content = saved;
        }
        reconcileChatRows(list, next);
      }, () -> {
        fetching[0] = false;
        boolean again = refreshAgain[0];
        refreshAgain[0] = false;
        complete.run();
        // Armed only while a GET is in flight, then cleared here. A failed GET does not
        // arm it, so this is one retry, not a loop.
        if (again && feedRefresh == activeFeedRefresh[0])
          feedRefresh.run(() -> {
          });
      });
    };
    feedRefresh = activeFeedRefresh[0];
    if (!memoryFeed)
      feedRefresh.run(() -> {
      });
  }

  private void composePost() {
    remember("compose", () -> composePost());
    shell("", false);
    toolbar.setVisibility(View.GONE);
    if (root.getChildCount() > 1)
      root.getChildAt(1).setVisibility(View.GONE);
    pendingMedia = null;
    preparingPostMedia = false;
    content.setPadding(0, 0, 0, dp(24));

    LinearLayout head = row();
    head.setPadding(dp(6), 0, dp(12), 0);
    head.setBackgroundColor(CARD);
    head.setElevation(dp(1));
    final int raw48 = UiMetrics.dpRaw(this, 48);
    FrameLayout back = new FrameLayout(this);
    back.setBackground(pressable(CARD, 99));
    FrameLayout.LayoutParams closeLp = new FrameLayout.LayoutParams(dp(22), dp(22),
        Gravity.START | Gravity.CENTER_VERTICAL);
    closeLp.leftMargin = dp(10);
    back.addView(icon("close", 22, TEXT), closeLp);
    back.setContentDescription(I18n.t("Quay lại"));
    back.setOnClickListener(v -> navigate("feed"));
    head.addView(back, new LinearLayout.LayoutParams(dp(80), raw48));
    UiMetrics.enforceMinTouchTarget(back, 48);
    TextView title = label(I18n.t("Bài viết mới"), 18, TEXT);
    title.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    title.setPadding(0, 0, 0, 0);
    title.setGravity(Gravity.CENTER);
    head.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    final LinearLayout post = authButton(null, I18n.t("Đăng"), true);
    post.setPadding(dp(10), 0, dp(10), 0);
    head.addView(post, new LinearLayout.LayoutParams(dp(80), raw48));
    root.addView(head, 0, new LinearLayout.LayoutParams(-1, UiMetrics.dpRaw(this, UiMetrics.HEADER_HEIGHT)));

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
    vis.setOnClickListener(
        v -> new Sheet(this).setTitle(I18n.t("Ai có thể xem?")).setItemIcons(new String[] { "globe", "users_round" })
            .setItems(new String[] { I18n.t("Mọi thành viên"), I18n.t("Người theo dõi") }, (d, w) -> {
              visibility[0] = w == 0 ? "public" : "followers";
              visText.setText(w == 0 ? I18n.t("Mọi thành viên") : I18n.t("Người theo dõi"));
              android.graphics.drawable.Drawable di = WebIcons.load(this, w == 0 ? "globe" : "users_round");
              di.setTint(TEXT);
              visIcon.setImageDrawable(di);
            }).show());
    LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(-2, -2);
    vp.topMargin = dp(4);

    who.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
    body.addView(who);
    body.addView(vis, vp);
    UiMetrics.enforceMinTouchTarget(vis, 48);

    final EditText text = new KinnectInput(this);
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
    tools.addView(composeTool("image", 0xff22a565, I18n.t("Thêm ảnh"), () -> {
      attachButton = null;
      pickFile(300, "image/*");
    }));
    tools.addView(composeTool("video", 0xffe0245e, I18n.t("Thêm video"), () -> {
      attachButton = null;
      pickFile(300, "video/*");
    }));
    tools.addView(composeTool("camera", ACCENT, I18n.t("Chụp hoặc quay"),
        () -> startActivityForResult(new Intent(this, StudioActivity.class), 203)));
    LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(-2, dp(56));
    tp.gravity = Gravity.CENTER_HORIZONTAL;
    tp.setMargins(dp(16), dp(8), dp(16), dp(12));
    root.addView(tools, tp);

    post.setOnClickListener(v -> {
      if (!post.isEnabled())
        return;
      if (preparingPostMedia) {
        say(I18n.t("Đang chuẩn bị ảnh/video, vui lòng chờ."));
        return;
      }
      if (text.getText().toString().trim().isEmpty() && pendingMedia == null) {
        say(I18n.t("Viết nội dung hoặc chọn ảnh/video."));
        return;
      }
      post.setEnabled(false);
      post.setAlpha(0.7f);
      if (pendingMedia != null)
        say(I18n.t("Đang tải lên…"));
      JSONObject payload = json("body", text.getText().toString(), "visibility", visibility[0]);
      if (pendingMedia != null)
        try {
          payload.put("media", pendingMedia);
        } catch (JSONException ignored) {
        }
      request("POST", "/api/posts", payload, d -> {
        pendingMedia = null;
        clearRetainedFeed();
        feedRows = null;
        feedScrollY = 0;
        say(I18n.t("Đã đăng bài viết"));
        navigate("feed");
      }, () -> {
        post.setEnabled(true);
        post.setAlpha(1f);
      });
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
    return UiMetrics.wrapMinTouchTarget(this, f, 48);
  }

  private interface IndexPick {
    void pick(int index);
  }

  // Nút gạt nhiều lựa chọn giống tabs() của web: nền xám nhạt, mục đang chọn là
  // viên trắng chữ tím.
  private void segmented(LinearLayout into, String[] labels, int selected, IndexPick pick) {
    into.setPadding(dp(4), dp(4), dp(4), dp(4));
    into.setBackground(background(SOFT, 14));
    int raw48 = UiMetrics.dpRaw(this, 48);
    for (int i = 0; i < labels.length; i++) {
      final int index = i;
      boolean on = i == selected;
      TextView tab = label(I18n.t(labels[i]), 13, on ? ACCENT_TEXT : TEXT);
      tab.setTypeface(Typeface.create(on ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
      tab.setGravity(Gravity.CENTER);
      tab.setSingleLine(false);
      tab.setMaxLines(2);
      tab.setIncludeFontPadding(false);
      tab.setPadding(dp(3), 0, dp(3), 0);
      if (on) {
        tab.setBackground(background(CARD, 11));
        tab.setElevation(dp(1));
      } else
        tab.setBackground(pressable(SOFT, 11));
      tab.setOnClickListener(v -> pick.pick(index));
      into.addView(tab, new LinearLayout.LayoutParams(0, Math.max(dp(48), raw48), 1));
      UiMetrics.enforceMinTouchTarget(tab, 48);
    }
  }

  private EditText searchField(LinearLayout parent, String hint) {
    LinearLayout box = row();
    box.setPadding(dp(14), 0, dp(10), 0);
    GradientDrawable sb = background(CARD, 14);
    sb.setStroke(dp(1), LINE);
    box.setBackground(sb);
    box.addView(icon("search", 18, MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
    EditText e = new KinnectInput(this);
    e.setHint(hint);
    e.setContentDescription(hint);
    e.setTextColor(TEXT);
    e.setHintTextColor(MUTED);
    e.setTextSize(15);
    e.setSingleLine(true);
    e.setBackground(null);
    e.setPadding(dp(10), 0, 0, 0);
    box.addView(e, new LinearLayout.LayoutParams(0, -1, 1));
    parent.addView(box, new LinearLayout.LayoutParams(-1, Math.max(dp(48), UiMetrics.dpRaw(this, 48))));
    UiMetrics.enforceMinTouchTarget(e, 48);
    return e;
  }

  private void inboxNewOptions() {
    Sheet sheet = new Sheet(this).setTitle(I18n.t("Tin nhắn mới"));
    LinearLayout form = column();
    form.setPadding(dp(16), dp(8), dp(16), dp(16));

    LinearLayout directOpt = row();
    directOpt.setPadding(dp(14), dp(14), dp(14), dp(14));
    directOpt.setBackground(pressable(SOFT, 14));
    directOpt.setGravity(Gravity.CENTER_VERTICAL);
    ImageView directIcon = new ImageView(this);
    directIcon.setImageDrawable(WebIcons.load(this, "message_square"));
    directIcon.setImageTintList(android.content.res.ColorStateList.valueOf(ACCENT_TEXT));
    directOpt.addView(directIcon, new LinearLayout.LayoutParams(dp(22), dp(22)));
    LinearLayout dt = column();
    dt.setPadding(dp(12), 0, 0, 0);
    TextView d1 = label(I18n.t("Tin nhắn mới"), 15, TEXT);
    d1.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
    dt.addView(d1);
    dt.addView(label(I18n.t("Nhắn tin trực tiếp với bạn bè"), 12, MUTED));
    directOpt.addView(dt, new LinearLayout.LayoutParams(0, -2, 1));
    form.addView(directOpt);

    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, -2);
    sp.topMargin = dp(8);
    LinearLayout groupOpt = row();
    groupOpt.setPadding(dp(14), dp(14), dp(14), dp(14));
    groupOpt.setBackground(pressable(SOFT, 14));
    groupOpt.setGravity(Gravity.CENTER_VERTICAL);
    ImageView groupIcon = new ImageView(this);
    groupIcon.setImageDrawable(WebIcons.load(this, "users_round"));
    groupIcon.setImageTintList(android.content.res.ColorStateList.valueOf(ACCENT_TEXT));
    groupOpt.addView(groupIcon, new LinearLayout.LayoutParams(dp(22), dp(22)));
    LinearLayout gt = column();
    gt.setPadding(dp(12), 0, 0, 0);
    TextView g1 = label(I18n.t("Tạo nhóm mới"), 15, TEXT);
    g1.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
    gt.addView(g1);
    gt.addView(label(I18n.t("Tạo nhóm trò chuyện nhiều người"), 12, MUTED));
    groupOpt.addView(gt, new LinearLayout.LayoutParams(0, -2, 1));
    form.addView(groupOpt, sp);

    android.app.Dialog dialog = sheet.setView(form).setNegativeButton(I18n.t("Đóng"), null).show();
    directOpt.setOnClickListener(v -> {
      dialog.dismiss();
      newDirectChat();
    });
    groupOpt.setOnClickListener(v -> {
      dialog.dismiss();
      createGroup();
    });
  }

  private void newDirectChat() {
    request("GET", "/api/friends", null, data -> {
      final List<JSONObject> friends = new ArrayList<>();
      JSONArray users = data == null ? null : data.optJSONArray("users");
      Set<String> seen = new HashSet<>();
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        if (u != null && seen.add(u.optString("id")))
          friends.add(u);
      }
      if (friends.isEmpty()) {
        say(I18n.t("Chưa có bạn bè để nhắn tin. Hãy tìm bạn ở Khám phá!"));
        return;
      }
      Sheet picker = new Sheet(this).setTitle(I18n.t("Chọn bạn bè"));
      LinearLayout container = column();
      container.setPadding(0, 0, 0, dp(4));

      // Ô tìm kiếm bạn bè
      EditText searchInput = new KinnectInput(this);
      searchInput.setHint(I18n.t("Tìm bạn bè để nhắn tin…"));
      searchInput.setTextSize(14);
      searchInput.setTextColor(TEXT);
      searchInput.setHintTextColor(MUTED);
      searchInput.setBackground(background(SOFT, 12));
      searchInput.setPadding(dp(14), dp(10), dp(14), dp(10));
      searchInput.setSingleLine(true);
      LinearLayout.LayoutParams sip = new LinearLayout.LayoutParams(-1, Math.max(dp(44), UiMetrics.dpRaw(this, 48)));
      sip.bottomMargin = dp(10);
      container.addView(searchInput, sip);
      UiMetrics.enforceMinTouchTarget(searchInput, 48);

      LinearLayout list = column();
      list.setPadding(0, 0, 0, dp(8));

      final android.app.Dialog[] dialogRef = new android.app.Dialog[1];
      final List<View> rowViews = new ArrayList<>();

      for (JSONObject friend : friends) {
        LinearLayout row = row();
        row.setPadding(dp(12), dp(10), dp(12), dp(10));
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setBackground(pressable(SOFT, 12));
        avatar(friend, row, 44);
        LinearLayout text = column();
        text.setPadding(dp(12), 0, 0, 0);
        String friendName = friend.optString("name");
        String username = friend.optString("username");
        TextView name = label(friendName, 15, TEXT);
        name.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
        text.addView(name);
        text.addView(label("@" + username, 12, MUTED));
        row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
        row.setOnClickListener(v -> {
          if (dialogRef[0] != null)
            dialogRef[0].dismiss();
          chat(friend);
        });
        row.setTag(friendName.toLowerCase() + " " + username.toLowerCase());
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
        rp.bottomMargin = dp(6);
        list.addView(row, rp);
        rowViews.add(row);
      }

      final TextView emptyHint = label(I18n.t("Không tìm thấy bạn bè phù hợp"), 14, MUTED);
      emptyHint.setGravity(Gravity.CENTER);
      emptyHint.setPadding(0, dp(28), 0, dp(28));
      emptyHint.setVisibility(View.GONE);
      list.addView(emptyHint);

      searchInput.addTextChangedListener(new android.text.TextWatcher() {
        public void beforeTextChanged(CharSequence s, int start, int count, int after) {
        }

        public void onTextChanged(CharSequence s, int start, int before, int count) {
        }

        public void afterTextChanged(android.text.Editable s) {
          String q = s == null ? "" : s.toString().trim().toLowerCase();
          int visibleCount = 0;
          for (View r : rowViews) {
            String tag = (String) r.getTag();
            boolean match = q.isEmpty() || (tag != null && tag.contains(q));
            r.setVisibility(match ? View.VISIBLE : View.GONE);
            if (match)
              visibleCount++;
          }
          emptyHint.setVisibility(visibleCount == 0 ? View.VISIBLE : View.GONE);
        }
      });

      ScrollView scroll = new ScrollView(this);
      scroll.addView(list);
      int maxH = getResources().getDisplayMetrics().heightPixels * 6 / 10;
      int targetH = Math.min(maxH, Math.max(friends.size() * dp(64) + dp(12), dp(280)));
      container.addView(scroll, new LinearLayout.LayoutParams(-1, targetH));

      dialogRef[0] = picker.setView(container).setNegativeButton(I18n.t("Hủy"), null).show();
    });
  }

  private void inbox() {
    if (headActions != null)
      headActions.addView(roundAction("plus", I18n.t("Tin nhắn mới"), false, this::inboxNewOptions));
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
        if (!q.isEmpty() && !name.toLowerCase(Locale.ROOT).contains(q))
          continue;
        if (unreadOnly[0] && item.optInt("unread") == 0)
          continue;
        JSONObject last = item.optJSONObject("last");
        String sub = last == null
            ? (group ? item.optJSONArray("members").length() + " thành viên" : "@" + item.optString("username"))
            : (last.optBoolean("mine") ? "Bạn: " : group ? last.optString("name") + ": " : "") + last.optString("body");
        conversationRow(list, item, group ? item.optString("name") : name, sub,
            last == null ? "" : ago(last.optLong("created")), item.optInt("unread"),
            !group && item.optBoolean("isActive"), item.optBoolean("pinned"), () -> {
              if (group)
                groupChat(item);
              else
                chat(item);
            });
        shown++;
      }
      if (shown == 0) {
        TextView empty = label(unreadOnly[0] ? I18n.t("Không có tin nhắn chưa đọc.")
            : I18n.t("Chưa có cuộc trò chuyện. Hãy tìm một người bạn ở Khám phá."), 14, MUTED);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(dp(16), dp(28), dp(16), dp(28));
        list.addView(empty);
      }
    };
    final Runnable[] drawFilters = new Runnable[1];
    drawFilters[0] = () -> {
      filters.removeAllViews();
      segmented(filters, new String[] { "Tất cả", "Chưa đọc" }, unreadOnly[0] ? 1 : 0, i -> {
        unreadOnly[0] = i == 1;
        drawFilters[0].run();
        render.run();
      });
    };
    drawFilters[0].run();
    search.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int b, int c) {
      }

      public void onTextChanged(CharSequence s, int a, int b, int c) {
      }

      public void afterTextChanged(android.text.Editable s) {
        render.run();
      }
    });
    final List<JSONObject> directRows = new ArrayList<>();
    final List<JSONObject> groupRows = new ArrayList<>();
    final String[] lastInboxSig = { "" };
    final Runnable sortAndRender = () -> {
      rows.clear();
      rows.addAll(directRows);
      rows.addAll(groupRows);
      Collections.sort(rows, (a, b) -> {
        if (a.optBoolean("pinned") != b.optBoolean("pinned"))
          return a.optBoolean("pinned") ? -1 : 1;
        long ta = a.optJSONObject("last") == null ? a.optLong("created") : a.optJSONObject("last").optLong("created");
        long tb = b.optJSONObject("last") == null ? b.optLong("created") : b.optJSONObject("last").optLong("created");
        return Long.compare(tb, ta);
      });
      StringBuilder sig = new StringBuilder();
      for (JSONObject r : rows) {
        JSONObject l = r.optJSONObject("last");
        sig.append(r.optString("id")).append('|')
            .append(r.optString("name")).append('|')
            .append(r.optInt("unread")).append('|')
            .append(r.optBoolean("pinned")).append('|')
            .append(r.optBoolean("isActive")).append('|')
            .append(l == null ? "" : l.optString("id") + ":" + l.optString("body") + ":" + l.optLong("created"))
            .append('\n');
      }
      String nextSig = sig.toString();
      if (nextSig.equals(lastInboxSig[0]) && list.getChildCount() > 0)
        return;
      lastInboxSig[0] = nextSig;
      render.run();
    };
    JSONObject cachedConv = api.cachedGet("/api/conversations");
    JSONArray cachedUsers = cachedConv == null ? null : cachedConv.optJSONArray("users");
    for (int i = 0; cachedUsers != null && i < cachedUsers.length(); i++) {
      JSONObject cu = cachedUsers.optJSONObject(i);
      if (cu != null)
        directRows.add(cu);
    }
    JSONObject cachedGrp = api.cachedGet("/api/groups");
    JSONArray cachedGroups = cachedGrp == null ? null : cachedGrp.optJSONArray("groups");
    for (int i = 0; cachedGroups != null && i < cachedGroups.length(); i++) {
      JSONObject cg = cachedGroups.optJSONObject(i);
      if (cg != null)
        groupRows.add(cg);
    }
    if (!directRows.isEmpty() || !groupRows.isEmpty())
      sortAndRender.run();
    request("GET", "/api/conversations", null, data -> {
      directRows.clear();
      conversationUsers = data.optJSONArray("users");
      for (int i = 0; conversationUsers != null && i < conversationUsers.length(); i++) {
        JSONObject cu = conversationUsers.optJSONObject(i);
        if (cu != null)
          directRows.add(cu);
      }
      sortAndRender.run();
    });
    request("GET", "/api/groups", null, g2 -> {
      groupRows.clear();
      JSONArray groups = g2.optJSONArray("groups");
      for (int i = 0; groups != null && i < groups.length(); i++) {
        JSONObject grp = groups.optJSONObject(i);
        if (grp != null)
          groupRows.add(grp);
      }
      sortAndRender.run();
    });
  }

  private void conversationRow(LinearLayout parent, JSONObject u, String title, String subtitle, String time,
      int unread, boolean online, boolean pinned, Runnable open) {
    LinearLayout r = row();
    r.setPadding(dp(12), dp(10), dp(12), dp(10));
    FrameLayout face = new FrameLayout(this);
    if (u != null) {
      LinearLayout h = new LinearLayout(this);
      avatar(u, h, 50);
      face.addView(h);
    } else {
      FrameLayout g = new FrameLayout(this);
      GradientDrawable o = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { ACCENT, 0xffd946c4 });
      o.setShape(GradientDrawable.OVAL);
      g.setBackground(o);
      ImageView groupGlyph = new ImageView(this);
      groupGlyph.setImageDrawable(new SettingsGlyph("group_three", WHITE, ACCENT));
      g.addView(groupGlyph, new FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER));
      face.addView(g, new LinearLayout.LayoutParams(dp(50), dp(50)));
    }
    if (online) {
      View dot = new View(this);
      GradientDrawable d = new GradientDrawable();
      d.setShape(GradientDrawable.OVAL);
      d.setColor(WebDesign.ONLINE_STRICT[WebTheme.isDark(this) ? 1 : 0]);
      d.setStroke(dp(2), CARD);
      dot.setBackground(d);
      face.addView(dot, new FrameLayout.LayoutParams(dp(14), dp(14), Gravity.BOTTOM | Gravity.END));
    }
    r.addView(face, new LinearLayout.LayoutParams(dp(50), dp(50)));
    LinearLayout t = column();
    t.setPadding(dp(12), 0, dp(8), 0);
    TextView n = label(title, 16, TEXT);
    n.setTypeface(null, Typeface.BOLD);
    n.setSingleLine(true);
    n.setEllipsize(android.text.TextUtils.TruncateAt.END);
    n.setPadding(0, 0, 0, 0);
    if (pinned) {
      android.graphics.drawable.Drawable pinDrawable = WebIcons.load(this, "pin");
      pinDrawable.setTint(ACCENT_TEXT);
      pinDrawable.setBounds(0, 0, dp(14), dp(14));
      n.setCompoundDrawables(pinDrawable, null, null, null);
      n.setCompoundDrawablePadding(dp(5));
    }
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
    right.setPadding(dp(6), 0, dp(2), 0);
    TextView timeView = label(time, 11, MUTED);
    timeView.setSingleLine(true);
    timeView.setPadding(0, 0, 0, dp(2));
    right.addView(timeView, new LinearLayout.LayoutParams(-2, -2));
    if (unread > 0) {
      TextView badge = label(String.valueOf(unread), 11, WHITE);
      badge.setGravity(Gravity.CENTER);
      badge.setTypeface(null, Typeface.BOLD);
      badge.setPadding(dp(6), 0, dp(6), 0);
      badge.setMinWidth(dp(20));
      badge.setBackground(background(WebDesign.LIVE_RED, 99));
      right.addView(badge, new LinearLayout.LayoutParams(-2, dp(20)));
    }
    r.addView(right, new LinearLayout.LayoutParams(-2, -2));
    ImageView overflow = icon("more", 20, MUTED);
    overflow.setPadding(dp(6), dp(6), dp(6), dp(6));
    overflow.setContentDescription(I18n.t("Tùy chọn hội thoại"));
    overflow.setOnClickListener(
        v -> conversationMenu(u.has("members") ? "group" : "direct", u.optString("id"), title, true));
    overflow.setLayoutParams(new LinearLayout.LayoutParams(dp(34), dp(34)));
    r.addView(UiMetrics.wrapMinTouchTarget(this, overflow, 48));

    r.setOnClickListener(v -> open.run());
    parent.addView(r);
  }

  private String lastMessages = "";
  private LinearLayout aiChatList;
  private ScrollView aiChatScroll;
  private String aiChatSender = "";
  private Runnable aiChatReload;
  private final java.util.Map<String, JSONObject> aiDrafts = new java.util.HashMap<>();

  private void receiveAIStream(JSONObject event) {
    String id = event.optString("id");
    if (event.optBoolean("done"))
      aiDrafts.remove(id);
    else
      aiDrafts.put(id, event);
    paintAIStream();
    if (event.optBoolean("done") && aiChatSender.equals(event.optString("sender")) && aiChatList != null
        && aiChatList.isAttachedToWindow() && aiChatReload != null)
      aiChatReload.run();
  }

  private void paintAIStream() {
    if (aiChatList == null || !aiChatList.isAttachedToWindow())
      return;
    boolean bottom = aiChatList.getHeight() - aiChatScroll.getScrollY() - aiChatScroll.getHeight() < dp(64);
    for (int i = aiChatList.getChildCount() - 1; i >= 0; i--)
      if ("ai-stream".equals(aiChatList.getChildAt(i).getTag()))
        aiChatList.removeViewAt(i);
    for (JSONObject draft : aiDrafts.values())
      if (aiChatSender.equals(draft.optString("sender"))) {
        TextView text = label(draft.optString("body"), 15, TEXT);
        text.setTag("ai-stream");
        text.setPadding(dp(12), dp(10), dp(12), dp(10));
        text.setBackground(background(CARD, 14));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
        lp.rightMargin = dp(48);
        lp.topMargin = dp(4);
        aiChatList.addView(text, lp);
      }
    if (bottom)
      aiChatScroll.post(() -> aiChatScroll.fullScroll(View.FOCUS_DOWN));
  }

  private View loadingState(String message) {
    LinearLayout state = column();
    state.setPadding(dp(16), dp(18), dp(16), dp(16));
    for (int i = 0; i < 4; i++) {
      View line = new View(this);
      line.setBackground(background(SOFT, 8));
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(i == 3 ? dp(170) : -1, dp(12));
      lp.topMargin = dp(10);
      state.addView(line, lp);
    }
    TextView caption = label(message, 12, MUTED);
    caption.setGravity(Gravity.CENTER);
    caption.setPadding(0, dp(12), 0, 0);
    state.addView(caption);
    android.animation.ObjectAnimator pulse = android.animation.ObjectAnimator.ofFloat(state, View.ALPHA, 0.45f, 1f);
    pulse.setDuration(900);
    pulse.setRepeatMode(android.animation.ValueAnimator.REVERSE);
    pulse.setRepeatCount(android.animation.ValueAnimator.INFINITE);
    pulse.start();
    state.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
      public void onViewAttachedToWindow(View v) {
      }

      public void onViewDetachedFromWindow(View v) {
        pulse.cancel();
      }
    });
    state.setTag("loading");
    return state;
  }

  private void profile() {
    profile(0);
  }

  private void profile(final int initialTab) {
    final LinearLayout page = content;
    final int ownerScreen = screen;
    JSONObject cachedResp = api.cachedGet("/api/me");
    JSONObject initial = cachedResp != null && cachedResp.optJSONObject("user") != null
        ? cachedResp.optJSONObject("user")
        : me;
    final boolean[] painted = { false };
    final View loading = initial == null ? loadingState(I18n.t("Đang tải hồ sơ…")) : null;
    if (initial != null) {
      me = initial;
      profileCard(me, true);
      profileSections(me, initialTab);
      painted[0] = true;
    } else {
      page.addView(loading);
    }
    final String initialSig = initial == null ? "" : initial.toString();
    request("GET", "/api/me", null, data -> {
      if (ownerScreen != screen || !page.isAttachedToWindow())
        return;
      JSONObject fresh = data.optJSONObject("user");
      if (fresh == null)
        return;
      String prevAvatar = me == null ? "" : me.optString("avatar", "");
      if (!prevAvatar.equals(fresh.optString("avatar", "")))
        applyUpdatedAvatar(fresh, null);
      else
        me = fresh;
      if (loading != null && loading.getParent() == page)
        page.removeView(loading);
      if (!painted[0] || !fresh.toString().equals(initialSig)) {
        page.removeAllViews();
        profileCard(me, true);
        profileSections(me, initialTab);
        painted[0] = true;
      }
    }, () -> {
      if (!painted[0] && loading != null && loading.getParent() == page) {
        page.removeView(loading);
        page.addView(button(I18n.t("Tải lại hồ sơ"), () -> navigate("profile")));
      }
    });
  }

  // Native rendering of the web profile: cover, left identity, actions, bio and
  // statistics.
  private void profileCard(final JSONObject user, final boolean self) {
    LinearLayout panel = card();
    panel.setPadding(0, 0, 0, dp(14));
    panel.setClipChildren(false);
    FrameLayout cover = new FrameLayout(this);
    ImageView image = new ImageView(this);
    image.setScaleType(ImageView.ScaleType.CENTER_CROP);
    image
        .setBackground(new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, new int[] { PRIMARY_SOFT, SOFT }));
    cover.addView(image, new FrameLayout.LayoutParams(-1, -1));
    if (!user.optString("cover").isEmpty() && !user.isNull("cover"))
      loadImage(user.optString("cover"), image);
    View coverShade = new View(this);
    coverShade.setBackground(
        new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x00000000, 0x55000000 }));
    cover.addView(coverShade, new FrameLayout.LayoutParams(-1, -1));
    if (self) {
      FrameLayout edit = new FrameLayout(this);
      edit.setBackground(background(0x66000000, 99));
      edit.addView(icon("camera", 18, WHITE), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
      edit.setContentDescription(I18n.t("Đổi ảnh bìa"));
      edit.setOnClickListener(v -> pickFile(306, "image/*"));
      edit.setLayoutParams(new FrameLayout.LayoutParams(dp(36), dp(36)));
      View editWrap = UiMetrics.wrapMinTouchTarget(this, edit, 48);
      FrameLayout.LayoutParams at = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.END);
      at.setMargins(0, dp(4), dp(4), 0);
      cover.addView(editWrap, at);
    }
    panel.addView(cover, new LinearLayout.LayoutParams(-1, dp(120)));
    LinearLayout identity = row();
    identity.setGravity(Gravity.BOTTOM);
    identity.setPadding(dp(14), 0, dp(14), 0);
    LinearLayout holder = row();
    holder.setPadding(dp(4), dp(4), dp(4), dp(4));
    holder.setBackground(background(CARD, 99));
    ImageView face = avatar(user, holder, 88);
    if (self)
      face.setOnClickListener(v -> pickAvatar());
    identity.addView(holder, new LinearLayout.LayoutParams(dp(96), dp(96)));
    LinearLayout name = column();
    name.setPadding(dp(12), dp(28), 0, dp(3));
    TextView title = label(user.optString("name"), 20, TEXT);
    title.setTypeface(null, Typeface.BOLD);
    name.addView(title);
    name.addView(label("@" + user.optString("username"), 12, MUTED));
    identity.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
    LinearLayout.LayoutParams identityAt = new LinearLayout.LayoutParams(-1, -2);
    identityAt.topMargin = -dp(28);
    panel.addView(identity, identityAt);
    LinearLayout actions = row();
    actions.setGravity(Gravity.CENTER_VERTICAL);
    actions.setPadding(dp(14), dp(13), dp(14), 0);
    int btnH = Math.max(dp(44), UiMetrics.dpRaw(this, 48));
    if (self) {
      LinearLayout edit = authButton("pencil", I18n.t("Chỉnh sửa hồ sơ"), true);
      edit.setOnClickListener(v -> editProfile());
      actions.addView(edit, new LinearLayout.LayoutParams(-1, btnH));
    } else {
      String friendship = user.optString("friendship");
      String friendLabel = friendship.equals("friends") ? "Bạn bè"
          : friendship.equals("outgoing") ? "Đã gửi" : friendship.equals("incoming") ? "Chấp nhận" : "Kết bạn";
      LinearLayout friend = authButton(
          friendship.equals("friends") || friendship.equals("outgoing") ? "user_check" : "user_plus", friendLabel,
          !friendship.equals("friends") && !friendship.equals("outgoing"));
      friend.setContentDescription(
          friendship.equals("outgoing") ? I18n.t("Đã gửi lời mời kết bạn. Nhấn để huỷ lời mời") : friendLabel);
      friend.setOnClickListener(v -> profileFriendAction(user));
      actions.addView(friend, new LinearLayout.LayoutParams(0, btnH, 1));
      LinearLayout message = authButton("message_square", I18n.t("Nhắn tin"), false);
      message.setOnClickListener(v -> chat(user));
      LinearLayout.LayoutParams gap = new LinearLayout.LayoutParams(0, btnH, 1);
      gap.leftMargin = dp(8);
      actions.addView(message, gap);
      View more = roundAction("ellipsis", I18n.t("Tuỳ chọn hồ sơ"), false, () -> profileOptions(user));
      LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(UiMetrics.dpRaw(this, 48), UiMetrics.dpRaw(this, 48));
      mp.leftMargin = dp(8);
      more.setLayoutParams(mp);
      actions.addView(more);
    }
    panel.addView(actions);
    if (!user.optString("bio").isEmpty()) {
      TextView bio = label(user.optString("bio"), 13, MUTED);
      bio.setPadding(dp(14), dp(12), dp(14), dp(8));
      bio.setLineSpacing(0, 1.6f);
      panel.addView(bio);
    }
    stats(user, panel);
  }

  private void loadImage(String path, ImageView target) {
    final int generation = screen;
    MediaImageLoader.displayImage(this, api, path, target, 1280, () -> screen == generation);
  }

  private void followProfile(JSONObject user) {
    request(user.optBoolean("following") ? "DELETE" : "POST", "/api/users/" + user.optString("id") + "/follow", json(),
        result -> person(result.optJSONObject("user")));
  }

  private void profileFriendResult(JSONObject user, JSONObject result) {
    JSONObject fresh = result.optJSONObject("user");
    if (fresh != null) {
      person(fresh);
      return;
    }
    try {
      user.put("friendship", result.optString("status", user.optString("friendship")));
      if (result.optString("status").equals("friends"))
        user.put("following", true);
    } catch (JSONException ignored) {
    }
    person(user);
  }

  private void profileFriendAction(final JSONObject user) {
    String state = user.optString("friendship");
    String endpoint = "/api/users/" + user.optString("id") + "/friend-request";
    if (state.equals("friends")) {
      profileOptions(user);
      return;
    }
    if (state.equals("incoming")) {
      request("POST", endpoint + "/respond", json("action", "accept"), d -> profileFriendResult(user, d));
      return;
    }
    if (state.equals("outgoing")) {
      confirm(I18n.t("Huỷ lời mời kết bạn?"),
          () -> request("DELETE", endpoint, json(), d -> profileFriendResult(user, d)));
      return;
    }
    request("POST", endpoint, json(), d -> profileFriendResult(user, d));
  }

  private void profileOptions(final JSONObject user) {
    String state = user.optString("friendship");
    List<String> labels = new ArrayList<>(), icons = new ArrayList<>();
    List<Runnable> actions = new ArrayList<>();
    icons.add("heart");
    labels.add(I18n.t(user.optBoolean("following") ? "Bỏ theo dõi" : "Theo dõi"));
    actions.add(() -> followProfile(user));
    if (state.equals("incoming")) {
      icons.add("x");
      labels.add(I18n.t("Từ chối lời mời"));
      actions.add(() -> request("POST", "/api/users/" + user.optString("id") + "/friend-request/respond",
          json("action", "decline"), d -> profileFriendResult(user, d)));
    } else if (state.equals("friends")) {
      icons.add("users_round");
      labels.add(I18n.t("Hủy kết bạn"));
      actions.add(() -> confirm(I18n.t("Hủy kết bạn với ") + user.optString("name") + "?", I18n.t("Hủy kết bạn"),
          () -> request("DELETE", "/api/users/" + user.optString("id") + "/friendship", json(),
              d -> profileFriendResult(user, d))));
    } else if (state.equals("outgoing")) {
      icons.add("users_round");
      labels.add(I18n.t("Hủy lời mời"));
      actions.add(() -> profileFriendAction(user));
    }
    icons.add("flag");
    labels.add(I18n.t("Báo cáo hồ sơ"));
    actions.add(() -> report("user", user.optString("id")));
    icons.add("user_block");
    labels.add(I18n.t("Chặn tài khoản"));
    actions.add(() -> confirm(I18n.t("Chặn ") + user.optString("name") + "?", I18n.t("Chặn"),
        () -> request("POST", "/api/users/" + user.optString("id") + "/block", json(), d -> navigate("discover"))));
    chatActionSheet(I18n.t("Tùy chọn hồ sơ"), icons, labels, actions);
  }

  private View profileAbout(final JSONObject source) {
    JSONObject user;
    try {
      user = new JSONObject(source.toString());
    } catch (Exception ignored) {
      user = json();
    }
    JSONObject visibility = user.optJSONObject("profileVisibility");
    for (String key : new String[] { "bio", "age", "city", "height", "weight", "occupation", "school", "gender",
        "orientation", "communityRole", "pronouns", "relationshipRole", "lookingFor", "interests" })
      if (visibility != null && !visibility.optBoolean(key, true))
        user.remove(key);
    if (user.has("identityPublic") && !user.optBoolean("identityPublic"))
      for (String key : new String[] { "gender", "orientation", "communityRole", "pronouns", "relationshipRole" })
        user.remove(key);
    LinearLayout panel = column();
    panel.setBackground(outlined(CARD, 16));
    panel.setPadding(dp(16), dp(16), dp(16), dp(16));
    LinearLayout heading = row();
    TextView title = label(I18n.t("Giới thiệu"), 18, TEXT);
    title.setTypeface(null, Typeface.BOLD);
    heading.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    heading.addView(icon("globe", 14, MUTED), new LinearLayout.LayoutParams(dp(14), dp(14)));
    TextView publicLabel = label(I18n.t("Công khai"), 12, MUTED);
    publicLabel.setPadding(dp(5), 0, 0, 0);
    heading.addView(publicLabel);
    panel.addView(heading);
    boolean filled = false;
    String bio = user.optString("bio").trim();
    if (!bio.isEmpty()) {
      TextView caption = label(I18n.t("Tiểu sử"), 12, MUTED);
      caption.setPadding(0, dp(18), 0, dp(6));
      panel.addView(caption);
      TextView text = label(bio, 14, TEXT);
      text.setLineSpacing(0, 1.3f);
      panel.addView(text);
      filled = true;
    }
    String[][] fields = { { "age", "Tuổi", " tuổi" }, { "city", "Nơi sống", "" }, { "height", "Chiều cao", " cm" },
        { "weight", "Cân nặng", " kg" }, { "occupation", "Nghề nghiệp", "" }, { "school", "Trường học", "" },
        { "gender", "Bản dạng giới", "" }, { "orientation", "Xu hướng", "" },
        { "communityRole", "Vai trò cộng đồng", "" }, { "pronouns", "Cách xưng hô", "" },
        { "relationshipRole", "Tình trạng quan hệ", "" }, { "lookingFor", "Mong muốn", "" } };
    for (String[] field : fields) {
      String value = user.isNull(field[0]) ? "" : user.optString(field[0]).trim();
      if (value.isEmpty() || value.equals("0"))
        continue;
      LinearLayout item = column();
      item.setPadding(0, dp(12), 0, dp(12));
      item.addView(label(I18n.t(field[1]), 12, MUTED));
      TextView text = label((java.util.Arrays
          .asList("gender", "orientation", "communityRole", "pronouns", "relationshipRole", "lookingFor")
          .contains(field[0]) ? I18n.t(value) : value) + I18n.t(field[2]), 14, TEXT);
      text.setPadding(0, dp(5), 0, 0);
      item.addView(text);
      panel.addView(item);
      panel.addView(divider());
      filled = true;
    }
    JSONArray interests = user.optJSONArray("interests");
    if (interests != null && interests.length() > 0) {
      TextView caption = label(I18n.t("Sở thích"), 12, MUTED);
      caption.setPadding(0, dp(18), 0, dp(6));
      panel.addView(caption);
      LinearLayout chips = row();
      panel.addView(chips);
      int used = 0, available = getResources().getDisplayMetrics().widthPixels - dp(80);
      for (int i = 0; i < interests.length(); i++) {
        TextView text = label(interests.optString(i), 13, ACCENT_TEXT);
        text.setPadding(dp(10), dp(7), dp(10), dp(7));
        text.setBackground(background(PRIMARY_SOFT, 10));
        text.setMaxWidth(available);
        text.measure(View.MeasureSpec.makeMeasureSpec(available, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
        int width = text.getMeasuredWidth() + dp(6);
        if (used > 0 && used + width > available) {
          chips = row();
          panel.addView(chips);
          used = 0;
        }
        LinearLayout.LayoutParams chipAt = new LinearLayout.LayoutParams(-2, -2);
        chipAt.rightMargin = dp(6);
        chipAt.bottomMargin = dp(6);
        chips.addView(text, chipAt);
        used += width;
      }
      filled = true;
    }
    boolean own = me != null && user.optString("id").equals(me.optString("id"));
    if (!filled)
      panel.addView(emptyBlock("user", I18n.t("Chưa có thông tin công khai"),
          own ? I18n.t("Cập nhật hồ sơ để mọi người hiểu bạn hơn.")
              : I18n.t("Thành viên này chưa chia sẻ thông tin giới thiệu.")));
    if (user.optLong("joinedAt") > 0) {
      TextView joined = label(
          I18n.t("Tham gia Kinnect từ ") + new java.text.SimpleDateFormat("MM/yyyy", java.util.Locale.getDefault())
              .format(new java.util.Date(user.optLong("joinedAt"))),
          12, MUTED);
      joined.setPadding(0, dp(18), 0, dp(12));
      panel.addView(joined);
    }
    return panel;
  }

  private final java.util.concurrent.ExecutorService previewLoader = java.util.concurrent.Executors
      .newFixedThreadPool(2);
  private final android.util.LruCache<String, Bitmap> videoPreviews=new android.util.LruCache<String,Bitmap>(4096){protected int sizeOf(String key,Bitmap value){return Math.max(1,value.getAllocationByteCount()/1024);}};

  private void loadVideoPreview(JSONObject video, ImageView target) {
    if (video == null)
      return;
    String path = video.optString("video");
    if (!path.startsWith("/") || path.startsWith("//"))
      return;
    final String origin = api.origin(), key = origin + path;
    final int generation = screen;
    Bitmap cached = videoPreviews.get(key);
    if (cached != null) {
      target.setImageBitmap(cached);
      return;
    }
    byte[] saved = api.cachedThumbnail(path);
    if (saved != null) {
      MediaImageLoader.decodeAsync(saved, 384, bitmap -> {
        if (bitmap != null && !isDestroyed() && screen == generation && target.isAttachedToWindow()) {
          target.setImageBitmap(bitmap);
          videoPreviews.put(key, bitmap);
        }
      });
      return;
    }
    final java.io.File local = api.cachedVideo(path);
    if (video.optBoolean("offline") && local == null)
      return;
    final java.util.Map<String, String> headers = new java.util.HashMap<>();
    headers.put("Cookie", api.jar());
    previewLoader.execute(() -> {
      if (isDestroyed() || screen != generation)
        return;
      android.media.MediaMetadataRetriever retriever = new android.media.MediaMetadataRetriever();
      Bitmap frame = null;
      try {
        if (local != null)
          retriever.setDataSource(local.getAbsolutePath());
        else
          retriever.setDataSource(origin + path, headers);
        if (android.os.Build.VERSION.SDK_INT >= 27)
          frame = retriever.getScaledFrameAtTime(0, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 240, 384);
        else {
          Bitmap original = retriever.getFrameAtTime(0, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC);
          if (original != null) {
            float scale = Math.min(1f, Math.min(240f / original.getWidth(), 384f / original.getHeight()));
            frame = Bitmap.createScaledBitmap(original, Math.max(1, Math.round(original.getWidth() * scale)),
                Math.max(1, Math.round(original.getHeight() * scale)), true);
            if (frame != original)
              original.recycle();
          }
        }
      } catch (Exception ignored) {
      } finally {
        try {
          retriever.release();
        } catch (Exception ignored) {
        }
      }
      final Bitmap result = frame;
      if (result == null)
        return;
      if (screen == generation && !isDestroyed()) {
        java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
        result.compress(Bitmap.CompressFormat.JPEG, 82, bytes);
        api.cacheThumbnail(path, bytes.toByteArray());
      }
      videoPreviews.put(key, result);
      handler.post(() -> {
        if (!isDestroyed() && screen == generation && target.isAttachedToWindow())
          target.setImageBitmap(result);
      });
    });
  }

  private void profileSections(final JSONObject user) {
    profileSections(user, 0);
  }

  private void profileSections(final JSONObject user, final int initialTab) {
    final LinearLayout controls = row(), list = column();
    final String[] tabs = { "Giới thiệu", "Bài viết", "Album ảnh", "Video" };
    final int[] selected = { (initialTab >= 0 && initialTab < tabs.length) ? initialTab : 0 }, generation = { 0 };
    final int ownerScreen = screen;
    final Runnable[] render = new Runnable[1];
    render[0] = () -> {
      final int revision = ++generation[0];
      // Keep the tab views mounted: removing the focused tab resets ScrollView
      // focus/position.
      // Size to actual posts/empty state; a full viewport here adds a blank screen
      // below the profile.
      list.setMinimumHeight(0);
      list.removeAllViews();
      for (int i = 0; i < controls.getChildCount(); i++) {
        TextView item = (TextView) controls.getChildAt(i);
        boolean active = i == selected[0];
        item.setTextColor(active ? ACCENT_TEXT : TEXT);
        item.setTypeface(Typeface.create(active ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
        item.setBackground(active ? background(CARD, 11) : pressable(SOFT, 11));
        item.setElevation(active ? dp(1) : 0);
        item.setSelected(active);
      }
      final int current = selected[0];
      if (current == 0) {
        list.addView(profileAbout(user));
        return;
      }
      final String sectionPath = current == 3 ? "/api/shorts?user=" + user.optString("id")
          : "/api/posts?user=" + user.optString("id");
      final View loading = api.cachedGet(sectionPath) == null ? loadingState(I18n.t("Đang tải…")) : null;
      if (loading != null)
        list.addView(loading);
      cachedRequest(sectionPath, data -> {
        if (current != selected[0] || revision != generation[0] || ownerScreen != screen || !list.isAttachedToWindow())
          return;
        list.removeAllViews();
        if (current == 3) {
          final JSONArray videos = data.optJSONArray("shorts");
          if (videos == null || videos.length() == 0) {
            list.addView(
                emptyBlock("clapperboard", I18n.t("Chưa có video"), I18n.t("Video ngắn sẽ hiển thị tại đây.")));
            return;
          }
          LinearLayout line = null;
          for (int i = 0; i < videos.length(); i++) {
            final int index = i;
            if (i % 3 == 0) {
              line = row();
              list.addView(line);
            }
            FrameLayout tile = new FrameLayout(this);
            GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
                new int[] { 0xff42355d, 0xff1d1929 });
            g.setCornerRadius(dp(12));
            tile.setBackground(g);
            tile.setClipToOutline(true);
            ImageView preview = new ImageView(this);
            preview.setScaleType(ImageView.ScaleType.CENTER_CROP);
            tile.addView(preview, new FrameLayout.LayoutParams(-1, -1));
            loadVideoPreview(videos.optJSONObject(i), preview);
            tile.addView(icon("play", 26, WHITE), new FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER));
            TextView dur = label(Math.round(videos.optJSONObject(i).optDouble("duration")) + "s", 11, WHITE);
            FrameLayout.LayoutParams dp2 = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.START);
            dp2.setMargins(dp(8), 0, 0, dp(6));
            tile.addView(dur, dp2);
            tile.setContentDescription("Xem video " + (i + 1));
            tile.setOnClickListener(v -> {
              shortsFollowing = false;
              shortRows = videos;
              showShort(index);
            });
            int w = (getResources().getDisplayMetrics().widthPixels - dp(48)) / 3;
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, w * 16 / 10, 1);
            lp.setMargins(i % 3 == 0 ? 0 : dp(3), dp(3), i % 3 == 2 ? 0 : dp(3), dp(3));
            line.addView(tile, lp);
          }
          for (int pad = videos.length() % 3; pad > 0 && pad < 3; pad++)
            line.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
        } else if (current == 2) {
          List<JSONObject> photos = new ArrayList<>();
          JSONArray posts = data.optJSONArray("posts");
          for (int i = 0; posts != null && i < posts.length(); i++) {
            JSONObject media = posts.optJSONObject(i).optJSONObject("media");
            if (media != null && media.optString("kind").equals("image"))
              photos.add(media);
          }
          final boolean own = user.optString("id").equals(me.optString("id"));
          LinearLayout privateRow = row();
          privateRow.setGravity(Gravity.CENTER_VERTICAL);
          privateRow.setPadding(dp(12), 0, dp(12), 0);
          privateRow.setBackground(outlined(CARD, 14));
          FrameLayout lock = new FrameLayout(this);
          lock.setBackground(background(PRIMARY_SOFT, 10));
          lock.addView(icon("lock_keyhole", 18, ACCENT_TEXT),
              new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
          privateRow.addView(lock, new LinearLayout.LayoutParams(dp(36), dp(36)));
          TextView pl = label(own ? I18n.t("Ảnh riêng tư") : I18n.t("Album riêng tư"), 15, TEXT);
          pl.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
          pl.setPadding(dp(12), 0, 0, 0);
          privateRow.addView(pl, new LinearLayout.LayoutParams(0, -2, 1));
          privateRow.addView(icon("chevron_right", 17, MUTED), new LinearLayout.LayoutParams(dp(17), dp(17)));
          privateRow.setOnClickListener(v -> privateAlbum(user));
          LinearLayout.LayoutParams pr = new LinearLayout.LayoutParams(-1, Math.max(dp(56), UiMetrics.dpRaw(this, 48)));
          pr.bottomMargin = dp(10);
          list.addView(privateRow, pr);
          UiMetrics.enforceMinTouchTarget(privateRow, 48);
          list.addView(sectionLabel(I18n.t("Ảnh công khai")));
          if (photos.isEmpty()) {
            list.addView(emptyBlock("image", I18n.t("Chưa có ảnh"), I18n.t("Ảnh đã đăng sẽ hiển thị tại đây.")));
            return;
          }
          LinearLayout line = null;
          int w = (getResources().getDisplayMetrics().widthPixels - dp(48)) / 3;
          for (int i = 0; i < photos.size(); i++) {
            if (i % 3 == 0) {
              line = row();
              list.addView(line);
            }
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
          for (int pad = photos.size() % 3; pad > 0 && pad < 3; pad++)
            line.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
        } else {
          LinearLayout saved = content;
          content = list;
          posts(data.optJSONArray("posts"), "Chưa có bài viết.");
          content = saved;
        }
      }, () -> {
        if (loading != null && loading.getParent() == list) {
          list.removeView(loading);
          list.addView(button(I18n.t("Thử tải lại"), () -> render[0].run()));
        }
      });
    };
    LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(-1, -2);
    cp.setMargins(0, dp(6), 0, dp(10));
    segmented(controls, tabs, selected[0], i -> {
      if (selected[0] == i)
        return;
      selected[0] = i;
      render[0].run();
    });
    for (int i = 0; i < controls.getChildCount(); i++) {
      TextView tab = (TextView) controls.getChildAt(i);
      tab.setPadding(dp(6), 0, dp(6), 0);
      tab.setSingleLine(true);
      tab.setLayoutParams(new LinearLayout.LayoutParams(0, Math.max(dp(38), UiMetrics.dpRaw(this, 48)), 1));
      UiMetrics.enforceMinTouchTarget(tab, 48);
    }
    content.addView(controls, cp);
    content.addView(list);
    render[0].run();
  }

  private void privateAlbum(final JSONObject owner) {
    final boolean mine = owner.optString("id").equals(me.optString("id"));
    accountHeader(I18n.t("Ảnh riêng tư"), () -> person(owner), false);
    request("GET", "/api/users/" + owner.optString("id") + "/private", null, data -> {
      String status = data.optString("status");
      TextView note = label(I18n.t("Chỉ người được cấp quyền mới xem được ảnh trong album này."), 13, MUTED);
      note.setPadding(0, dp(2), 0, dp(10));
      content.addView(note);
      if (mine)
        content.addView(primary(I18n.t("Thêm ảnh riêng tư"), () -> pickFile(308, "image/*")));
      if (!status.equals("owner") && !status.equals("granted")) {
        content.addView(label(status.equals("pending") ? I18n.t("Yêu cầu của bạn đang chờ chủ album duyệt.")
            : I18n.t("Gửi yêu cầu để chủ album cấp quyền xem ảnh."), 14, MUTED));
        Button ask = primary(status.equals("pending") ? I18n.t("Đang chờ duyệt") : I18n.t("Yêu cầu xem ảnh"),
            () -> request("POST", "/api/users/" + owner.optString("id") + "/private/request", json(),
                result -> privateAlbum(owner)));
        ask.setEnabled(!status.equals("pending"));
        content.addView(ask);
        return;
      }
      JSONArray photos = data.optJSONArray("photos");
      if (photos == null || photos.length() == 0) {
        content.addView(emptyBlock("image", I18n.t("Album chưa có ảnh"),
            I18n.t("Ảnh riêng tư bạn tải lên sẽ hiển thị dạng lưới tại đây.")));
      } else {
        LinearLayout grid = column();
        LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(-1, -2);
        gp.topMargin = dp(12);
        content.addView(grid, gp);
        int side = (getResources().getDisplayMetrics().widthPixels - dp(48)) / 3;
        LinearLayout line = null;
        for (int i = 0; i < photos.length(); i++) {
          if (i % 3 == 0) {
            line = row();
            grid.addView(line);
          }
          final JSONObject photo = photos.optJSONObject(i);
          FrameLayout tile = new FrameLayout(this);
          GradientDrawable tileBg = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
              new int[] { 0xff3b2369, 0xff1e1633 });
          tileBg.setCornerRadius(dp(12));
          tile.setBackground(tileBg);
          tile.setClipToOutline(true);
          ImageView image = new ImageView(this);
          image.setScaleType(ImageView.ScaleType.CENTER_CROP);
          tile.addView(image, new FrameLayout.LayoutParams(-1, -1));
          String url = photo.optString("url");
          if (!url.isEmpty())
            loadImage(url, image);
          tile.setOnClickListener(v -> {
            if (!url.isEmpty())
              openPhoto(url, () -> privateAlbum(owner));
          });
          if (mine) {
            FrameLayout del = new FrameLayout(this);
            del.setBackground(background(0xaa0d0e14, 99));
            del.addView(icon("trash", 15, WHITE), new FrameLayout.LayoutParams(dp(15), dp(15), Gravity.CENTER));
            del.setContentDescription(I18n.t("Xoá ảnh"));
            del.setOnClickListener(v -> confirm(I18n.t("Xoá ảnh riêng tư này?"), () -> request("DELETE",
                "/api/me/private-photos/" + photo.optString("id"), json(), result -> privateAlbum(owner))));
            del.setLayoutParams(new FrameLayout.LayoutParams(dp(28), dp(28)));
            FrameLayout.LayoutParams dpDel = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.END);
            dpDel.setMargins(0, dp(2), dp(2), 0);
            tile.addView(UiMetrics.wrapMinTouchTarget(this, del, 48), dpDel);
          }
          LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, side, 1);
          lp.setMargins(i % 3 == 0 ? 0 : dp(3), dp(3), i % 3 == 2 ? 0 : dp(3), dp(3));
          line.addView(tile, lp);
        }
        for (int pad = photos.length() % 3; pad > 0 && pad < 3; pad++)
          line.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
      }
      if (mine)
        request("GET", "/api/me/private/requests", null, result -> {
          content.addView(sectionLabel(I18n.t("Quyền truy cập")));
          JSONArray requests = result.optJSONArray("requests");
          for (int i = 0; requests != null && i < requests.length(); i++) {
            JSONObject entry = requests.optJSONObject(i), user = entry.optJSONObject("user");
            LinearLayout panel = card();
            panel.addView(label(user.optString("name"), 14, TEXT));
            for (String action : entry.optString("status").equals("pending") ? new String[] { "grant", "deny" }
                : new String[] { "revoke" })
              panel.addView(button(
                  action.equals("grant") ? I18n.t("Đồng ý")
                      : action.equals("deny") ? I18n.t("Từ chối") : I18n.t("Thu hồi"),
                  () -> request("POST", "/api/me/private/requests/" + user.optString("id"), json("action", action),
                      changed -> privateAlbum(owner))));
          }
          if (requests == null || requests.length() == 0)
            content.addView(label(I18n.t("Chưa có yêu cầu xem ảnh."), 14, MUTED));
        });
    });
  }

  private ImageView profileEditorAvatar;

  private void editProfile() {
    remember("edit-profile", () -> editProfile());
    accountPage(I18n.t("Chỉnh sửa hồ sơ"), () -> navigate("profile"), false);
    request("GET", "/api/me", null, data -> {
      JSONObject fresh = data.optJSONObject("user");
      if (fresh != null) {
        String prevAvatar = me == null ? "" : me.optString("avatar", "");
        if (!prevAvatar.equals(fresh.optString("avatar", "")))
          applyUpdatedAvatar(fresh, null);
        else
          me = fresh;
      }
      final JSONObject visibility = json();
      JSONObject current = me.optJSONObject("profileVisibility");
      for (String key : new String[] { "bio", "age", "gender", "orientation", "communityRole", "pronouns",
          "relationshipRole", "lookingFor", "city", "interests", "height", "weight", "occupation", "school" }) {
        boolean identity = Arrays.asList("gender", "orientation", "communityRole", "pronouns", "relationshipRole")
            .contains(key);
        boolean shared = current == null || current.optBoolean(key, true);
        if (identity && !me.optBoolean("identityPublic") && !me.optString(key).isEmpty())
          shared = false;
        try {
          visibility.put(key, shared);
        } catch (JSONException ignored) {
        }
      }
      final Map<String, EditText> fields = new LinkedHashMap<>();
      LinearLayout media = row();
      profileEditorAvatar = avatar(me, media, 48);
      media.addView(roundAction("camera", I18n.t("Đổi ảnh đại diện"), false, () -> pickAvatar()));
      media.addView(roundAction("image", I18n.t("Đổi ảnh bìa"), false, () -> pickFile(306, "image/*")));
      media.addView(
          roundAction("eye", I18n.t("Xem trước hồ sơ công khai"), false, () -> previewProfile(fields, visibility)));
      content.addView(media);
      LinearLayout visHint = row();
      visHint.setGravity(Gravity.CENTER_VERTICAL);
      visHint.setPadding(0, dp(8), 0, dp(4));
      visHint.addView(icon("globe", 15, ACCENT_TEXT), new LinearLayout.LayoutParams(dp(15), dp(15)));
      ImageView lockHint = icon("lock_keyhole", 15, MUTED);
      LinearLayout.LayoutParams lhp = new LinearLayout.LayoutParams(dp(15), dp(15));
      lhp.leftMargin = dp(4);
      visHint.addView(lockHint, lhp);
      TextView visHintText = label(I18n.t("Chạm biểu tượng công khai hoặc khóa để chọn thông tin hiển thị."), 12, MUTED);
      visHintText.setPadding(dp(8), 0, 0, 0);
      visHint.addView(visHintText, new LinearLayout.LayoutParams(0, -2, 1));
      content.addView(visHint, new LinearLayout.LayoutParams(-1, -2));
      LinearLayout basic = profileEditorGroup("user_round", I18n.t("Thông tin cơ bản"), true);
      fields.put("name", profileEditorField(basic, "name", I18n.t("Tên hiển thị"), visibility, null, 60, false));
      fields.put("birthDate", profileEditorField(basic, "birthDate", I18n.t("Ngày sinh"), visibility, null, 10, false));
      basic.addView(label(I18n.t("Ngày sinh chỉ bạn xem; biểu tượng công khai cho phép hiện tuổi."), 12, MUTED));
      LinearLayout about = profileEditorGroup("pen_line", I18n.t("Giới thiệu và sở thích"), true);
      fields.put("bio", profileEditorField(about, "bio", I18n.t("Giới thiệu"), visibility, null, 500, true));
      fields.put("interests", profileEditorField(about, "interests", I18n.t("Sở thích"), visibility, null, 320, false));
      addProfileTags(about, fields.get("interests"), new String[] { "Nhiếp ảnh", "Du lịch", "Âm nhạc", "Đọc sách",
          "Thể thao", "Ẩm thực", "Phim ảnh", "Công nghệ", "Nghệ thuật", "Thiên nhiên", "Game", "Thú cưng" }, 10);
      LinearLayout identity = profileEditorGroup("user_round", I18n.t("Bản thân và cách xưng hô"), false);
      fields.put("gender",
          profileEditorField(
              identity, "gender", I18n.t("Bản dạng giới"), visibility, new String[] { "Nam", "Nữ", "Nam chuyển giới",
                  "Nữ chuyển giới", "Phi nhị nguyên", "Linh hoạt giới", "Vô giới", "Đang tìm hiểu", "Khác" },
              60, false));
      fields.put("height",
          profileEditorField(identity, "height", I18n.t("Chiều cao (cm)"), visibility, null, 3, false));
      fields.get("height").setInputType(2);
      fields.put("weight", profileEditorField(identity, "weight", I18n.t("Cân nặng (kg)"), visibility, null, 3, false));
      fields.get("weight").setInputType(2);
      fields.put("orientation", profileEditorField(identity, "orientation", I18n.t("Xu hướng tính dục"), visibility,
          new String[] { "Dị tính", "Gay / Đồng tính nam", "Lesbian / Đồng tính nữ", "Song tính / Bisexual",
              "Toàn tính / Pansexual", "Vô tính / Asexual", "Queer", "Á tính / Demisexual", "Đang tìm hiểu", "Khác" },
          60, false));
      fields.put("communityRole",
          profileEditorField(identity, "communityRole", I18n.t("Vai trò tự mô tả (tùy chọn)"), visibility,
              new String[] { "Top", "Bottom", "Vers", "Vers Top", "Vers Bottom", "Side", "Femme", "Masc / Butch",
                  "Androgynous", "Stem", "Đang tìm hiểu", "Khác" },
              60, false));
      fields.put("pronouns", profileEditorField(identity, "pronouns", I18n.t("Cách xưng hô"), visibility,
          new String[] { "Anh", "Chị", "Em", "Bạn", "Họ / They" }, 30, false));
      LinearLayout connection = profileEditorGroup("users_round", I18n.t("Kết nối và cuộc sống"), false);
      fields.put("relationshipRole",
          profileEditorField(connection, "relationshipRole", I18n.t("Tình trạng quan hệ"), visibility,
              new String[] { "Độc thân", "Đang tìm hiểu", "Đang trong mối quan hệ", "Đã kết hôn", "Mối quan hệ mở" },
              40, false));
      fields.put("lookingFor",
          profileEditorField(connection, "lookingFor", I18n.t("Mong muốn kết nối"), visibility, null, 300, false));
      addProfileTags(connection, fields.get("lookingFor"),
          new String[] { "Kết bạn", "Trò chuyện", "Hẹn hò", "Mối quan hệ nghiêm túc", "Cùng sở thích" }, 20);
      fields.put("city", profileEditorField(connection, "city", I18n.t("Nơi sống"), visibility, null, 80, false));
      fields.put("occupation",
          profileEditorField(connection, "occupation", I18n.t("Nghề nghiệp"), visibility, null, 100, false));
      fields.put("school",
          profileEditorField(connection, "school", I18n.t("Trường học"), visibility, null, 100, false));
      final LinearLayout save = authButton("check", I18n.t("Lưu"), true);
      save.setOnClickListener(v -> {
        if (!save.isEnabled())
          return;
        if (fields.get("name").getText().toString().trim().isEmpty()) {
          fields.get("name").setError(I18n.t("Nhập tên hiển thị"));
          return;
        }
        JSONObject payload = json("identityPublic", true, "profileVisibility", visibility);
        for (Map.Entry<String, EditText> entry : fields.entrySet())
          try {
            String value = entry.getValue().getTag() instanceof ProfileValue
                ? ((ProfileValue) entry.getValue().getTag()).value
                : entry.getValue().getText().toString().trim();
            if (entry.getKey().equals("interests")) {
              JSONArray tags = new JSONArray();
              for (String tag : value.split(","))
                if (!tag.trim().isEmpty())
                  tags.put(tag.trim());
              payload.put("interests", tags);
            } else
              payload.put(entry.getKey(), value);
          } catch (JSONException ignored) {
          }
        save.setEnabled(false);
        save.setAlpha(0.5f);
        request("PATCH", "/api/me", payload, result -> {
          me = result.optJSONObject("user");
          say(I18n.t("Đã lưu hồ sơ"));
          navigate("profile");
        }, () -> {
          save.setEnabled(true);
          save.setAlpha(1f);
        });
      });
      LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, Math.max(dp(48), UiMetrics.dpRaw(this, 48)));
      sp.topMargin = dp(14);
      content.addView(save, sp);
    });
  }

  private LinearLayout profileEditorGroup(String iconName, String title, boolean expanded) {
    LinearLayout group = card();
    LinearLayout head = row(), body = column();
    head.setGravity(Gravity.CENTER_VERTICAL);
    head.addView(icon(iconName, 20, ACCENT_TEXT), new LinearLayout.LayoutParams(dp(20), dp(20)));
    TextView caption = label(title, 15, TEXT);
    caption.setTypeface(null, Typeface.BOLD);
    caption.setPadding(dp(10), 0, 0, 0);
    caption.setGravity(Gravity.CENTER_VERTICAL);
    caption.setSingleLine(false);
    caption.setMaxLines(2);
    caption.setIncludeFontPadding(false);
    caption.setEllipsize(android.text.TextUtils.TruncateAt.END);
    head.addView(caption, new LinearLayout.LayoutParams(0, Math.max(dp(44), UiMetrics.dpRaw(this, 48)), 1));
    final ImageView arrow = icon(expanded ? "chevron_up" : "chevron_down", 18, MUTED);
    head.addView(arrow, new LinearLayout.LayoutParams(dp(18), dp(18)));
    body.setVisibility(expanded ? View.VISIBLE : View.GONE);
    head.setContentDescription(title + (expanded ? I18n.t(" · Thu gọn") : I18n.t(" · Mở rộng")));
    head.setBackground(pressable(CARD, 10));
    head.setOnClickListener(v -> {
      boolean open = body.getVisibility() != View.VISIBLE;
      body.setVisibility(open ? View.VISIBLE : View.GONE);
      android.graphics.drawable.Drawable d = WebIcons.load(this, open ? "chevron_up" : "chevron_down");
      d.setTint(MUTED);
      arrow.setImageDrawable(d);
      head.setContentDescription(title + (open ? I18n.t(" · Thu gọn") : I18n.t(" · Mở rộng")));
    });
    group.addView(head);
    UiMetrics.enforceMinTouchTarget(head, 48);
    group.addView(body);
    return body;
  }

  private static final class ProfileValue {
    final String value;

    ProfileValue(String value) {
      this.value = value;
    }
  }

  private void setProfileChoice(EditText field, String value) {
    field.setTag(new ProfileValue(value));
    field.setText(I18n.t(value));
  }

  private EditText profileEditorField(LinearLayout into, String key, String title, JSONObject visibility,
      String[] choices, int maximum, boolean multiline) {
    LinearLayout head = row();
    head.setGravity(Gravity.CENTER_VERTICAL);
    TextView name = label(title, 13, MUTED);
    head.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
    String value = (key.equals("height") || key.equals("weight")) && me.isNull(key) ? ""
        : key.equals("interests") ? join(me.optJSONArray("interests")).replace(" · ", ", ") : me.optString(key);
    final EditText field = input(into, title, value, multiline);
    field.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(maximum) });
    if (choices != null) {
      setProfileChoice(field, value);
      field.setFocusable(false);
      field.setOnClickListener(v -> new Sheet(this).setTitle(I18n.t(title)).setItemIcon("circle_check")
          .setItems(I18n.items(choices), (d, w) -> setProfileChoice(field, choices[w]))
          .setNeutralButton(I18n.t("Để trống"), (d, w) -> setProfileChoice(field, "")).show());
    }
    if (choices != null)
      head.addView(roundAction("chevron_down", I18n.t("Chọn ") + title.toLowerCase(Locale.ROOT), false, () -> {
        String[] labels = new String[choices.length + 1];
        labels[0] = "Không muốn tiết lộ";
        System.arraycopy(choices, 0, labels, 1, choices.length);
        new Sheet(this).setTitle(I18n.t(title)).setItemIcon("circle_check")
            .setItems(I18n.items(labels), (d, w) -> setProfileChoice(field, w == 0 ? "" : choices[w - 1])).show();
      }));
    if (!key.equals("name")) {
      final String sharedKey = key.equals("birthDate") ? "age" : key;
      FrameLayout toggle = new FrameLayout(this);
      final Runnable draw = () -> {
        boolean shared = visibility.optBoolean(sharedKey, true);
        toggle.removeAllViews();
        toggle.addView(icon(shared ? "globe" : "lock_keyhole", 18, shared ? ACCENT_TEXT : MUTED),
            new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
        toggle.setContentDescription((shared ? I18n.t("Ẩn ") : I18n.t("Công khai "))
            + (key.equals("birthDate") ? I18n.t("tuổi") : title.toLowerCase(Locale.ROOT)));
        toggle.setTooltipText(shared ? I18n.t("Đang công khai") : I18n.t("Chỉ mình tôi"));
      };
      draw.run();
      toggle.setBackground(pressable(CARD, 99));
      toggle.setOnClickListener(v -> {
        try {
          visibility.put(sharedKey, !visibility.optBoolean(sharedKey, true));
        } catch (JSONException ignored) {
        }
        draw.run();
      });
      toggle.setLayoutParams(new LinearLayout.LayoutParams(dp(44), dp(44)));
      head.addView(UiMetrics.wrapMinTouchTarget(this, toggle, 48));
    }
    int at = into.indexOfChild(field);
    into.addView(head, at);
    if (key.equals("birthDate")) {
      field.setHint("YYYY-MM-DD");
      field.setFocusable(false);
      field.setOnClickListener(v -> {
        final Calendar date = Calendar.getInstance();
        date.add(Calendar.YEAR, -18);
        try {
          String[] parts = field.getText().toString().split("-");
          if (parts.length == 3)
            date.set(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]) - 1, Integer.parseInt(parts[2]));
        } catch (Exception ignored) {
        }
        DatePickerDialog picker = new DatePickerDialog(this,
            (d, year, month, day) -> field.setText(String.format(Locale.ROOT, "%04d-%02d-%02d", year, month + 1, day)),
            date.get(Calendar.YEAR), date.get(Calendar.MONTH), date.get(Calendar.DAY_OF_MONTH));
        Calendar latest = Calendar.getInstance();
        latest.add(Calendar.YEAR, -18);
        picker.getDatePicker().setMaxDate(latest.getTimeInMillis());
        picker.setButton(DialogInterface.BUTTON_NEUTRAL, "Để trống", (d, w) -> field.setText(""));
        picker.show();
      });
    }
    return field;
  }

  private void addProfileTags(LinearLayout into, EditText field, String[] choices, int maximum) {
    final LinearLayout chips = row();
    into.addView(hscroll(chips));
    final Runnable[] render = new Runnable[1];
    render[0] = () -> {
      chips.removeAllViews();
      Set<String> values = new LinkedHashSet<>();
      for (String value : field.getText().toString().split(","))
        if (!value.trim().isEmpty())
          values.add(value.trim().toLowerCase(Locale.ROOT));
      for (String choice : choices)
        chips.addView(webChip(choice, values.contains(choice.toLowerCase(Locale.ROOT)), false, () -> {
          String value = choice.toLowerCase(Locale.ROOT);
          if (values.contains(value))
            values.remove(value);
          else {
            if (values.size() >= maximum) {
              say(I18n.t("Tối đa ") + maximum + I18n.t(" lựa chọn"));
              return;
            }
            values.add(value);
          }
          field.setText(android.text.TextUtils.join(", ", values));
        }));
    };
    field.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int b, int c) {
      }

      public void onTextChanged(CharSequence s, int a, int b, int c) {
      }

      public void afterTextChanged(android.text.Editable s) {
        render[0].run();
      }
    });
    render[0].run();
  }

  private void previewProfile(Map<String, EditText> fields, JSONObject visibility) {
    LinearLayout preview = column();
    avatar(me, preview, 64);
    for (Map.Entry<String, EditText> entry : fields.entrySet()) {
      String key = entry.getKey(), value = entry.getValue().getText().toString().trim();
      if (key.equals("birthDate")) {
        if (!visibility.optBoolean("age", true) || value.isEmpty())
          continue;
        try {
          java.text.SimpleDateFormat format = new java.text.SimpleDateFormat("yyyy-MM-dd", Locale.ROOT);
          format.setLenient(false);
          Calendar birth = Calendar.getInstance(), today = Calendar.getInstance();
          birth.setTime(format.parse(value));
          int age = today.get(Calendar.YEAR) - birth.get(Calendar.YEAR);
          if (today.get(Calendar.MONTH) < birth.get(Calendar.MONTH)
              || (today.get(Calendar.MONTH) == birth.get(Calendar.MONTH)
                  && today.get(Calendar.DAY_OF_MONTH) < birth.get(Calendar.DAY_OF_MONTH)))
            age--;
          value = age + " tuổi";
        } catch (Exception ignored) {
          continue;
        }
      } else if (!key.equals("name") && !visibility.optBoolean(key, true))
        continue;
      if (!value.isEmpty())
        preview.addView(label(value, key.equals("name") ? 18 : 14, key.equals("name") ? TEXT : MUTED));
    }
    ScrollView scroll = new ScrollView(this);
    scroll.addView(preview);
    scroll.setLayoutParams(
        new LinearLayout.LayoutParams(-1, Math.min(dp(420), getResources().getDisplayMetrics().heightPixels / 2)));
    new Sheet(this).setTitle(I18n.t("Hồ sơ công khai · Xem trước")).setView(scroll)
        .setNegativeButton(I18n.t("Đóng"), null).show();
  }

  private void blocks() {
    accountHeader(I18n.t("Người đã chặn"), () -> settings(), false);
    request("GET", "/api/blocks", null, data -> {
      JSONArray users = data.optJSONArray("users");
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        content.addView(
            button(I18n.t("Bỏ chặn ") + u.optString("name"), () -> request(
                "DELETE",
                "/api/users/" + u.optString("id") + "/block",
                json(),
                d -> blocks())));
      }
      if (users == null || users.length() == 0)
        content.addView(
            label(I18n.t("Bạn chưa chặn ai."), 16, MUTED));
    });
  }

  private void toggleNotifications() {
    if ("bell".equals(headerActive)) {
      headerActive = "";
      navigate(tab.isEmpty() ? "feed" : tab);
    } else {
      notificationsScreen();
    }
  }

  private void notifications() {
    notificationsScreen();
  }

  private void notificationsScreen() {
    headerActive = "bell";
    remember("notifications", this::notificationsScreen);
    badgesAt = 0;
    shell(I18n.t("Thông báo"), true);
    if (headActions != null)
      headActions.addView(roundAction("check", I18n.t("Đánh dấu tất cả đã đọc"), false,
          () -> request("POST", "/api/notifications", json("scope", "social"), d -> {
            bellCount = 0;
            badgesAt = 0;
            notificationsScreen();
          })));
    if (bellCount > 0) {
      LinearLayout summaryRow = row();
      summaryRow.setGravity(Gravity.CENTER_VERTICAL);
      summaryRow.setPadding(0, dp(2), 0, dp(8));
      TextView unreadBadge = label(bellCount + " " + I18n.t("chưa đọc"), 12, ACCENT_TEXT);
      unreadBadge.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
      unreadBadge.setPadding(dp(10), dp(4), dp(10), dp(4));
      unreadBadge.setBackground(background(PRIMARY_SOFT, 99));
      summaryRow.addView(unreadBadge, new LinearLayout.LayoutParams(-2, -2));
      content.addView(summaryRow, new LinearLayout.LayoutParams(-1, -2));
    }
    final LinearLayout notices = column();
    content.addView(notices);
    final int expectedScreen = screen;
    cachedRequest("/api/notifications", data -> {
      WindowedListBinder.clearPending(notices);
      notices.removeAllViews();
      final JSONArray rows = data.optJSONArray("notifications");
      if (rows == null || rows.length() == 0) {
        notices
            .addView(emptyBlock("bell", I18n.t("Chưa có thông báo mới"), I18n.t("Thông báo mới sẽ hiển thị tại đây.")));
        return;
      }
      WindowedListBinder.bind(this, notices, rows, 16, dp(800), () -> screen == expectedScreen, (start, end) -> {
        for (int i = start; i < end; i++) {
          final JSONObject n = rows.optJSONObject(i), u = n == null ? null : n.optJSONObject("actor");
          if (n == null || n.optString("kind").equals("message") || n.optString("kind").equals("group_message"))
            continue;
          LinearLayout r = row();
          r.setPadding(dp(12), dp(10), dp(12), dp(10));
          r.setBackground(background(n.optInt("seen") == 0 ? PRIMARY_SOFT : CARD, 14));
          LinearLayout avWrap = row();
          avWrap.setPadding(dp(2), dp(2), dp(2), dp(2));
          GradientDrawable avRing = background(CARD, 99);
          avRing.setStroke(dp(1), LINE);
          avWrap.setBackground(avRing);
          avatar(u, avWrap, 44);
          r.addView(avWrap, new LinearLayout.LayoutParams(dp(48), dp(48)));
          LinearLayout t = column();
          t.setPadding(dp(12), 0, dp(8), 0);
          TextView line = new KinnectText(this);
          android.text.SpannableStringBuilder sb = new android.text.SpannableStringBuilder(
              u == null ? "" : u.optString("name"));
          sb.setSpan(new android.text.style.StyleSpan(Typeface.BOLD), 0, sb.length(), 0);
          sb.append(noticeText(n.optString("kind")));
          line.setText(sb);
          line.setTextColor(TEXT);
          line.setTextSize(15);
          t.addView(line);
          t.addView(label(ago(n.optLong("created")), 12, n.optInt("seen") == 0 ? ACCENT_TEXT : MUTED));
          r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
          if (n.optInt("seen") == 0) {
            View dot = new View(this);
            dot.setBackground(background(ACCENT, 99));
            r.addView(dot, new LinearLayout.LayoutParams(dp(10), dp(10)));
          }
          r.setOnClickListener(v -> {
            if (n.optInt("seen") == 0)
              try {
                api.call("POST", "/api/notifications",
                    new JSONObject().put("ids", new JSONArray().put(n.optString("id"))), (d, e, s) -> {
                    });
              } catch (JSONException ignored) {
              }
            badgesAt = 0;
            openNotification(n);
          });
          LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
          p.setMargins(0, dp(4), 0, dp(4));
          notices.addView(r, p);
          UiMetrics.enforceMinTouchTarget(r, 48);
        }
      });
    }, () -> {
    });
  }

  private void openNotification(JSONObject notification) {
    if (notification == null)
      return;
    String kind = notification.optString("kind"), ref = notification.optString("ref");
    JSONObject actor = notification.optJSONObject("actor");
    String actorId = actor != null ? actor.optString("id") : notification.optString("actorId");
    if (kind.equals("message") || kind.equals("missed_call")) {
      if (actor != null && !actor.optString("id").isEmpty()) {
        chat(actor);
        return;
      }
      if (!actorId.isEmpty()) {
        final int generation = screen;
        api.call("GET", "/api/users/" + encode(actorId), null, (data, error, status) -> {
          if (isFinishing() || isDestroyed() || generation != screen)
            return;
          JSONObject user = data == null ? null : data.optJSONObject("user");
          if (user != null && !user.optString("id").isEmpty())
            chat(user);
          else
            navigate("inbox");
        });
        return;
      }
      navigate("inbox");
      return;
    }
    if (kind.equals("group_message")) {
      if (ref.isEmpty()) {
        navigate("inbox");
        return;
      }
      request("GET", "/api/groups/" + encode(ref), null, data -> {
        JSONObject g = data == null ? null : data.optJSONObject("group");
        if (g != null)
          groupChat(g);
        else
          navigate("inbox");
      });
      return;
    }
    if ((kind.equals("like") || kind.equals("comment") || kind.equals("comment_reply") || kind.equals("share"))
        && !ref.isEmpty()) {
      postDetail(ref, notification.isNull("commentId") ? "" : notification.optString("commentId"));
      return;
    }
    if (kind.equals("short_like") || kind.equals("short_comment")) {
      request("GET", "/api/shorts?video=" + encode(ref), null, data -> {
        shortRows = data.optJSONArray("shorts");
        shortsFollowing = false;
        int index = -1;
        for (int i = 0; shortRows != null && i < shortRows.length(); i++)
          if (ref.equals(shortRows.optJSONObject(i).optString("id"))) {
            index = i;
            break;
          }
        if (index < 0) {
          say(I18n.t("Video không còn khả dụng"));
          return;
        }
        showShort(index);
        if (kind.equals("short_comment"))
          shortComments(shortRows.optJSONObject(index));
      });
      return;
    }
    if (kind.startsWith("private_")) {
      privateAlbum(kind.equals("private_request") ? me : json("id", ref));
      return;
    }
    if (kind.equals("friend_request")) {
      friendsScreen("incoming");
      return;
    }
    if (kind.equals("friend_accept") || kind.equals("friend_accepted")) {
      friendsScreen("friends");
      return;
    }
    if (actor != null && !actor.optString("id").isEmpty()) {
      person(actor);
      return;
    }
    if (!actorId.isEmpty()) {
      final int generation = screen;
      api.call("GET", "/api/users/" + encode(actorId), null, (data, error, status) -> {
        if (isFinishing() || isDestroyed() || generation != screen)
          return;
        JSONObject user = data == null ? null : data.optJSONObject("user");
        if (user != null && !user.optString("id").isEmpty())
          person(user);
        else
          navigate("inbox");
      });
    }
  }

  private void postDetail(String id, String commentId) {
    remember("post:" + id, () -> postDetail(id, commentId));
    accountHeader(I18n.t("Bài viết"), () -> notifications());
    request("GET", "/api/posts?post=" + encode(id), null, data -> {
      JSONArray rows = data.optJSONArray("posts");
      if (rows == null || rows.length() == 0) {
        content.addView(emptyBlock("newspaper", I18n.t("Bài viết không còn khả dụng"), ""));
        return;
      }
      postCard(rows.optJSONObject(0), commentId == null ? "" : commentId);
    });
  }

  private EditText aiField(LinearLayout into, String title, String value, boolean secret) {
    into.addView(label(title, 13, TEXT));
    EditText field = input(into, title, value, false);
    field.setSaveEnabled(false);
    if (secret) {
      field.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
      if (android.os.Build.VERSION.SDK_INT >= 26)
        field.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
    }
    return field;
  }

  private void adminAI() {
    accountPage(I18n.t("Trợ lý AI và kiểm duyệt"), () -> admin());
    if (me == null || !me.optString("role").equals("admin")) {
      content.addView(label(I18n.t("Chỉ quản trị viên được cấu hình AI."), 14, MUTED));
      return;
    }
    final LinearLayout page = content;
    final TextView state = label(I18n.t("Đang tải cấu hình AI…"), 14, MUTED);
    page.addView(state);
    final boolean[] loaded = { false };
    request("GET", "/api/admin/ai", null, data -> {
      JSONObject config = data.optJSONObject("config"), credentials = data.optJSONObject("credentials");
      if (config == null || credentials == null)
        return;
      loaded[0] = true;
      state.setText(
          config.optBoolean("ready") ? I18n.t("Cloudflare · Đã có cấu hình") : I18n.t("Cloudflare · Chưa có cấu hình"));
      page.addView(label(I18n.t("Cloudflare chính · NVIDIA dự phòng"), 18, TEXT));
      page.addView(label(I18n.t("Khóa chỉ lưu tại máy chủ Kinnect. Để trống để giữ khóa đã lưu."), 13, MUTED));
      LinearLayout form = card();
      final EditText url = aiField(form, "URL Worker Cloudflare", credentials.optString("workerUrl"), false),
          token = aiField(form, credentials.optBoolean("tokenSaved") ? "Khóa Worker · Đã lưu" : "Khóa kết nối Worker",
              "", true),
          key = aiField(form, credentials.optBoolean("nvidiaKeySaved") ? "Khóa NVIDIA · Đã lưu" : "Khóa NVIDIA API", "",
              true),
          model = aiField(form, "Model NVIDIA văn bản", credentials.optString("nvidiaModel"), false),
          vision = aiField(form, "Model NVIDIA ảnh (tùy chọn)", credentials.optString("nvidiaVisionModel"), false);
      final CheckBox fallback = new CheckBox(this);
      fallback.setText(I18n.t("Tự chuyển NVIDIA khi Cloudflare lỗi"));
      fallback.setTextColor(TEXT);
      fallback.setChecked(credentials.optBoolean("fallbackEnabled"));
      form.addView(fallback);
      final EditText password = aiField(form, "Mật khẩu quản trị để lưu", "", true);
      final TextView feedback = label("", 13, MUTED);
      form.addView(feedback);
      final View[] saving = { null };
      saving[0] = primary(I18n.t("Lưu kết nối AI"), () -> {
        if (password.getText().toString().isEmpty()) {
          feedback.setText(I18n.t("Nhập mật khẩu quản trị để lưu cấu hình."));
          return;
        }
        saving[0].setEnabled(false);
        JSONObject payload = json("workerUrl", url.getText().toString().trim(), "token",
            token.getText().toString().trim(), "nvidiaKey", key.getText().toString().trim(), "nvidiaModel",
            model.getText().toString().trim(), "nvidiaVisionModel", vision.getText().toString().trim(),
            "fallbackEnabled", fallback.isChecked(), "password", password.getText().toString());
        request("PATCH", "/api/admin/ai/credentials", payload, d -> {
          feedback.setText(I18n.t("Đã lưu kết nối AI trên máy chủ."));
        }, () -> {
          token.setText("");
          key.setText("");
          password.setText("");
          saving[0].setEnabled(true);
        });
      });
      form.addView(saving[0]);
      String[][] providers = { { "cloudflare", "Kiểm tra Cloudflare" }, { "nvidia", "Kiểm tra NVIDIA" },
          { "fallback", "Kiểm tra chuyển dự phòng" } };
      for (final String[] provider : providers) {
        final View[] test = { null };
        test[0] = button(provider[1], () -> {
          test[0].setEnabled(false);
          feedback.setText(I18n.t("Đang kiểm tra…"));
          request("POST", "/api/admin/ai/test", json("provider", provider[0]),
              d -> feedback.setText(d.optString("message") + " · " + d.optString("provider")),
              () -> test[0].setEnabled(true));
        });
        form.addView(test[0]);
      }
      CheckBox support = new CheckBox(this);
      support.setText(I18n.t("AI tự trả lời từ tài khoản quản trị"));
      support.setTextColor(TEXT);
      support.setChecked(config.optInt("support") == 1);
      page.addView(support);
      CheckBox moderation = new CheckBox(this);
      moderation.setText(I18n.t("AI kiểm duyệt và báo quản trị viên"));
      moderation.setTextColor(TEXT);
      moderation.setChecked(config.optInt("moderation") == 1);
      page.addView(moderation);
      page.addView(label(
          I18n.t("AI cảnh báo để admin xử lý. Kiểm duyệt video/Live dùng khung hình lấy mẫu, không kiểm tra âm thanh."),
          13, MUTED));
      final View[] toggle = { null };
      toggle[0] = primary(I18n.t("Lưu bật/tắt AI"), () -> {
        toggle[0].setEnabled(false);
        request("PATCH", "/api/admin/ai",
            json("support", support.isChecked(), "moderation", moderation.isChecked(), "adminId", me.optString("id")),
            d -> {
              say(I18n.t("Đã lưu bật/tắt AI"));
              adminAI();
            }, () -> toggle[0].setEnabled(true));
      });
      page.addView(toggle[0]);
      page.addView(label(I18n.t("Hàng chờ: ") + config.optInt("queue") + I18n.t(" · Lỗi: ") + config.optInt("failed"),
          14, MUTED));
    }, () -> {
      if (!loaded[0]) {
        state.setText(I18n
            .t("Chưa tải được cấu hình. Nếu báo không tìm thấy API, máy chủ Kinnect cần cập nhật và khởi động lại."));
        page.addView(button(I18n.t("Thử lại"), () -> adminAI()));
      }
    });
  }

  private void admin() {
    shell(I18n.t("Quản trị Kinnect"), true);
    content.addView(
        primary(I18n.t("Kinh tế & Quà Live"), () -> startActivity(new Intent(this, EconomyAdminActivity.class))));
    content.addView(primary(I18n.t("Trợ lý AI và kiểm duyệt"), () -> adminAI()));
    content.addView(label(I18n.t("Báo cáo và tài khoản"), 16, TEXT));
    adminResets();
    adminMusic();
    request("GET", "/api/admin/reports", null, data -> {
      JSONArray reports = data.optJSONArray("reports");
      if (reports == null || reports.length() == 0)
        content.addView(
            label(I18n.t("Chưa có báo cáo."), 15, MUTED));
      for (int i = 0; reports != null && i < reports.length(); i++) {
        JSONObject r = reports.optJSONObject(i),
            subject = r.optJSONObject("subject");
        LinearLayout c = card();
        c.addView(
            label(
                r.optString("target_type") + " · " + r.optString("status"),
                16,
                ACCENT));
        c.addView(label(r.optString("reason"), 16, TEXT));
        if (subject != null) {
          c.addView(
              label(
                  subject.optString("body", subject.optString("username")),
                  14,
                  MUTED));
          if (r.optString("target_type").equals("short"))
            c.addView(
                button(
                    subject.optBoolean("hidden") ? I18n.t("Hiện video") : I18n.t("Ẩn video"),
                    () -> moderate(
                        subject.optBoolean("hidden") ? "show-short" : "hide-short",
                        r.optString("target_id"))));
          if (r.optString("target_type").equals("post"))
            c.addView(
                button(subject.optBoolean("hidden") ? I18n.t("Hiện bài") : I18n.t("Ẩn bài"), () -> moderate(
                    subject.optBoolean("hidden") ? "show-post" : "hide-post",
                    r.optString("target_id"))));
          if (r.optString("target_type").equals("message") || r.optString("target_type").equals("group_message"))
            c.addView(button(I18n.t("Gỡ nội dung tin nhắn"),
                () -> moderate("hide-" + r.optString("target_type"), r.optString("target_id"))));
          c.addView(
              button(I18n.t("Đình chỉ tài khoản"), () -> moderate("suspend-user", subject.optString("userId"))));
        }
        if (r.optString("status").equals("open"))
          c.addView(
              button(I18n.t("Đóng báo cáo"), () -> moderate("close-report", r.optString("id"))));
      }
    });
    request("GET", "/api/admin/users", null, data -> {
      JSONArray users = data.optJSONArray("users");
      content.addView(label(I18n.t("Thành viên gần đây"), 16, TEXT));
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        LinearLayout c = card();
        c.addView(
            label(u.optString("username") + " · " + u.optString("role"), 16, TEXT));
        if (!u.optString("role").equals("admin"))
          c.addView(
              button(u.optInt("suspended") == 1 ? I18n.t("Khôi phục") : I18n.t("Đình chỉ"), () -> moderate(
                  u.optInt("suspended") == 1 ? "restore-user" : "suspend-user",
                  u.optString("id"))));
      }
    });
  }

  private void moderate(String action, String target) {
    confirm(I18n.t("Xác nhận thao tác quản trị?"), () -> request(
        "POST",
        "/api/admin/moderate",
        json("action", action, "target", target),
        d -> admin()));
  }

  private void live() {
    final int ownerScreen = screen;
    final int raw48 = UiMetrics.dpRaw(this, 48);
    LinearLayout top = row();
    top.setGravity(Gravity.CENTER_VERTICAL);
    top.setPadding(0, dp(2), 0, dp(12));

    LinearLayout titleCol = column();
    TextView livePill = label("● LIVE", 10, WHITE);
    livePill.setTypeface(null, Typeface.BOLD);
    livePill.setSingleLine(true);
    livePill.setPadding(dp(8), dp(3), dp(8), dp(3));
    livePill.setBackground(background(WebDesign.LIVE_RED, 99));
    LinearLayout.LayoutParams lpp = new LinearLayout.LayoutParams(-2, -2);
    lpp.bottomMargin = dp(4);
    titleCol.addView(livePill, lpp);
    TextView h1 = label(I18n.t("Trực tiếp"), 20, TEXT);
    h1.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
    h1.setSingleLine(true);
    h1.setMaxLines(1);
    h1.setAutoSizeTextTypeUniformWithConfiguration(14, 20, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
    h1.setEllipsize(android.text.TextUtils.TruncateAt.END);
    h1.setPadding(0, 0, 0, dp(2));
    titleCol.addView(h1, new LinearLayout.LayoutParams(-1, -2));
    titleCol.addView(label(I18n.t("Phòng phát sóng đang diễn ra"), 13, MUTED));
    top.addView(titleCol, new LinearLayout.LayoutParams(0, -2, 1));

    LinearLayout refreshBtn = row();
    refreshBtn.setGravity(Gravity.CENTER);
    refreshBtn.setBackground(outlined(CARD, 99));
    refreshBtn.addView(icon("rotate_ccw", 18, TEXT), new LinearLayout.LayoutParams(dp(18), dp(18)));
    refreshBtn.setContentDescription(I18n.t("Làm mới"));
    refreshBtn.setOnClickListener(v -> navigate("live"));
    refreshBtn.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    top.addView(UiMetrics.wrapMinTouchTarget(this, refreshBtn, 48));

    LinearLayout goLive = row();
    goLive.setGravity(Gravity.CENTER);
    goLive.setPadding(dp(12), 0, dp(12), 0);
    goLive.setBackground(pressable(WebDesign.LIVE_RED, 99));
    goLive.addView(icon("video", 16, WHITE), new LinearLayout.LayoutParams(dp(16), dp(16)));
    TextView goLabel = label(I18n.t("Phát live"), 13, WHITE);
    goLabel.setSingleLine(true);
    goLabel.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    goLabel.setPadding(dp(6), 0, 0, 0);
    goLive.addView(goLabel);
    goLive.setContentDescription(I18n.t("Phát trực tiếp"));
    goLive.setOnClickListener(
        v -> startActivity(new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "live")));
    LinearLayout.LayoutParams glp = new LinearLayout.LayoutParams(-2, raw48);
    glp.leftMargin = dp(6);
    top.addView(goLive, glp);
    UiMetrics.enforceMinTouchTarget(goLive, 48);

    content.addView(top, new LinearLayout.LayoutParams(-1, -2));

    final LinearLayout body = column();
    content.addView(body, new LinearLayout.LayoutParams(-1, -2));
    final View loading = loadingState(I18n.t("Đang tải phòng trực tiếp…"));
    body.addView(loading);
    cachedRequest("/api/live", data -> {
      if (ownerScreen != screen || isDestroyed() || !body.isAttachedToWindow())
        return;
      body.removeAllViews();
      JSONArray rooms = data == null ? null : data.optJSONArray("rooms");
      if (rooms == null || rooms.length() == 0) {
        LinearLayout empty = column();
        empty.setGravity(Gravity.CENTER_HORIZONTAL);
        empty.setPadding(dp(20), dp(36), dp(20), dp(28));
        empty.setBackground(outlined(CARD, WebDesign.CARD_RADIUS));
        FrameLayout bubble = new FrameLayout(this);
        bubble.setBackground(background(0x22d61f26, 99));
        bubble.addView(icon("radio", 28, WebDesign.LIVE_RED),
            new FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER));
        empty.addView(bubble, new LinearLayout.LayoutParams(dp(64), dp(64)));
        TextView t = label(I18n.t("Chưa có buổi live"), 17, TEXT);
        t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        t.setGravity(Gravity.CENTER);
        t.setPadding(0, dp(14), 0, dp(4));
        empty.addView(t);
        TextView s = label(I18n.t("Hãy là người mở màn!"), 13, MUTED);
        s.setGravity(Gravity.CENTER);
        empty.addView(s, new LinearLayout.LayoutParams(-1, -2));
        LinearLayout startLive = row();
        startLive.setGravity(Gravity.CENTER);
        startLive.setPadding(dp(20), 0, dp(20), 0);
        startLive.setBackground(pressable(WebDesign.LIVE_RED, 14));
        startLive.addView(icon("video", 16, WHITE), new LinearLayout.LayoutParams(dp(16), dp(16)));
        TextView st = label(I18n.t("Phát live"), 14, WHITE);
        st.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        st.setPadding(dp(8), 0, 0, 0);
        startLive.addView(st);
        startLive.setContentDescription(I18n.t("Phát trực tiếp"));
        startLive.setOnClickListener(
            v -> startActivity(new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "live")));
        LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(-2, raw48);
        slp.topMargin = dp(18);
        empty.addView(startLive, slp);
        UiMetrics.enforceMinTouchTarget(startLive, 48);
        body.addView(empty, new LinearLayout.LayoutParams(-1, -2));
        return;
      }
      LinearLayout rowPair = null;
      for (int i = 0; i < rooms.length(); i++) {
        if (i % 2 == 0) {
          rowPair = row();
          rowPair.setGravity(Gravity.TOP);
          LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
          if (i > 0)
            rp.topMargin = dp(10);
          body.addView(rowPair, rp);
        }
        FrameLayout card = liveCard(rooms.optJSONObject(i));
        LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(0, -2, 1);
        cp.setMargins(i % 2 == 0 ? 0 : dp(5), 0, i % 2 == 1 ? 0 : dp(5), 0);
        rowPair.addView(card, cp);
      }
      if (rooms.length() % 2 == 1 && rowPair != null) {
        LinearLayout.LayoutParams pad = new LinearLayout.LayoutParams(0, 1, 1);
        pad.leftMargin = dp(5);
        rowPair.addView(new View(this), pad);
      }
    }, () -> {
      if (ownerScreen != screen || isDestroyed())
        return;
      if (loading.getParent() == body) {
        body.removeView(loading);
        body.addView(button(I18n.t("Thử tải lại"), () -> navigate("live")));
      }
    });
  }

  private void languageMenu() {
    new Sheet(this).setTitle(I18n.t("Ngôn ngữ ứng dụng")).setItemIcons(new String[] { "globe", "globe", "settings" })
        .setItems(new String[] { "Tiếng Việt", "English", I18n.t("Theo hệ thống") }, (dialog, index) -> {
          I18n.select(this, new String[] { "vi", "en", "system" }[index]);
          recreate();
        }).setNegativeButton(I18n.t("Đóng"), null).show();
  }

  private void settings() {
    if (me == null) {
      auth(false);
      return;
    }
    accountPage(I18n.t("Cài đặt & riêng tư"), this::openMeMenu, false);
    groupTitle("globe", I18n.t("Ngôn ngữ"));
    groupRow(settingsGroup(), "globe", I18n.current().equals("en") ? "English" : I18n.t("Tiếng Việt"), false,
        () -> languageMenu());
    groupTitle("user_round", I18n.t("Thông tin cá nhân"));
    LinearLayout personal = settingsGroup();
    groupRow(personal, "pencil", me.optString("name") + I18n.t(" · chỉnh sửa hồ sơ"), false, () -> editProfile());
    groupTitle("shield_check", I18n.t("Quyền riêng tư"));
    LinearLayout privacy = settingsGroup();
    privacyToggle(privacy, "discoverable", I18n.t("Cho phép tìm thấy tôi"),
        I18n.t("Xuất hiện trong Khám phá và Quanh đây"));
    privacyToggle(privacy, "showDistance", I18n.t("Hiển thị khoảng cách"), I18n.t("Chỉ hiện khoảng cách gần đúng"));
    privacyToggle(privacy, "showActivity", I18n.t("Trạng thái hoạt động"),
        I18n.t("Cho người khác biết khi bạn đang online"));
    groupRow(privacy, "message_square",
        I18n.t("Ai có thể nhắn tin · ")
            + (me.optString("dmMode").equals("everyone") ? I18n.t("Mọi thành viên") : I18n.t("Bạn bè")),
        false,
        () -> new Sheet(this).setTitle(I18n.t("Ai có thể nhắn tin"))
            .setItemIcons(new String[] { "globe", "users_round" })
            .setItems(new String[] { I18n.t("Mọi thành viên"), I18n.t("Bạn bè") },
                (d, w) -> request("PATCH", "/api/me", json("dmMode", w == 0 ? "everyone" : "friends"), r -> {
                  me = r.optJSONObject("user");
                  settings();
                }))
            .show());
    if (Distribution.PLAY) {
      groupTitle("bell", I18n.t("Đồng bộ giữa các thiết bị"));
      LinearLayout bgPlay = settingsGroup();
      privacyToggle(bgPlay, "backgroundSync", I18n.t("Đồng bộ tin nhắn nền"),
          I18n.t("Nhận tin nhắn và thông báo khi tắt ứng dụng"));
    } else {
      groupTitle("bell", I18n.t("Thông báo & hoạt động nền"));
      LinearLayout bgSettings = settingsGroup();
      groupRow(bgSettings, "bell", I18n.t("Tự khởi chạy khi mở máy (Autostart)"), false, () -> openAutostartSettings());
      groupRow(bgSettings, "shield_check", I18n.t("Không giới hạn pin (Chạy ngầm)"), false, () -> battery());
    }
    groupTitle("lock_keyhole", I18n.t("Quyền truy cập"));
    LinearLayout access = settingsGroup();
    groupRow(access, "image_lock", I18n.t("Ảnh riêng tư"), false, () -> privateAlbum(me));
    groupRow(access, "user_block", I18n.t("Tài khoản đã chặn"), false, () -> blocks());
    groupRow(access, "shield_check", I18n.t("Chính sách quyền riêng tư"), false,
        () -> nativeDocument("privacy", () -> settings()));
    groupRow(access, "location_off", I18n.t("Tắt tìm quanh đây"), false,
        () -> request("PATCH", "/api/me/location", json("enabled", false), result -> {
          me = result.optJSONObject("user");
          say(I18n.t("Đã tắt tìm quanh đây"));
          settings();
        }));
    TextView note = label(I18n.t("Vị trí chỉ cập nhật khi bạn chọn tìm quanh đây."), 12, MUTED);
    note.setPadding(dp(6), 0, dp(6), 0);
    content.addView(note);
    groupTitle("user_round", I18n.t("Quản lý tài khoản"));
    LinearLayout account = settingsGroup();
    groupRow(account, "trash", I18n.t("Xóa tài khoản và dữ liệu"), false, () -> deleteAccountScreen());
    content.setPadding(content.getPaddingLeft(), content.getPaddingTop(), content.getPaddingRight(), dp(32));
  }

  private void deleteAccountScreen() {
    accountPage(I18n.t("Xóa tài khoản"), () -> settings(), false);
    final LinearLayout panel = card();
    panel.addView(label(I18n.t("Xóa vĩnh viễn"), 20, TEXT));
    panel.addView(label(I18n.t(
        "Hồ sơ, ảnh, bài viết, video, tin nhắn và dữ liệu gắn với tài khoản sẽ bị xóa khỏi hệ thống đang hoạt động. Tất cả phiên đăng nhập bị thu hồi. Nội dung của bạn trong nhóm cũng bị xóa; nhóm có thành viên khác được chuyển chủ sở hữu. Không thể khôi phục sau khi hoàn tất."),
        14, MUTED));
    panel.addView(label(I18n.t("Nhập tên đăng nhập để xác nhận (không cần @): ") + me.optString("username"), 13, TEXT));
    final EditText username = new KinnectInput(this);
    username.setHint(me.optString("username"));
    username.setHintTextColor(MUTED);
    username.setTextColor(TEXT);
    username.setSingleLine(true);
    username.setTextSize(16);
    username.setBackground(outlined(CARD, 12));
    username.setPadding(dp(12), dp(8), dp(12), dp(8));
    panel.addView(username, new LinearLayout.LayoutParams(-1, Math.max(dp(52), UiMetrics.dpRaw(this, 48))));
    UiMetrics.enforceMinTouchTarget(username, 48);
    final LinearLayout pwWrap = column();
    pwWrap.addView(label(I18n.t("Mật khẩu xác thực lại"), 13, TEXT));
    final LinearLayout pwBox = row();
    pwBox.setGravity(Gravity.CENTER_VERTICAL);
    pwBox.setBackground(outlined(CARD, 12));
    pwBox.setPadding(dp(12), 0, dp(4), 0);
    final EditText password = new KinnectInput(this);
    password.setSingleLine(true);
    password.setTextColor(TEXT);
    password.setHintTextColor(MUTED);
    password.setTextSize(16);
    password.setBackground(null);
    password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
    pwBox.addView(password, new LinearLayout.LayoutParams(0, -1, 1));
    UiMetrics.enforceMinTouchTarget(password, 48);
    final FrameLayout pwEye = new FrameLayout(this);
    final ImageView pwEyeIcon = icon("eye", 18, MUTED);
    pwEye.addView(pwEyeIcon, new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    pwEye.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    pwEye.setBackground(pressable(CARD, 99));
    pwEye.setContentDescription(I18n.t("Hiện mật khẩu"));
    pwEye.setClickable(true);
    pwEye.setFocusable(true);
    final FrameLayout pwEyeWrap = UiMetrics.wrapMinTouchTarget(this, pwEye, 48);
    pwEyeWrap.setOnClickListener(v -> {
      boolean hidden = (password.getInputType()
          & InputType.TYPE_TEXT_VARIATION_PASSWORD) == InputType.TYPE_TEXT_VARIATION_PASSWORD;
      password.setInputType(InputType.TYPE_CLASS_TEXT
          | (hidden ? InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD : InputType.TYPE_TEXT_VARIATION_PASSWORD));
      password.setSelection(password.length());
      android.graphics.drawable.Drawable d = WebIcons.load(this, hidden ? "eye_off" : "eye");
      d.setTint(MUTED);
      pwEyeIcon.setImageDrawable(d);
      String desc = hidden ? I18n.t("Ẩn mật khẩu") : I18n.t("Hiện mật khẩu");
      pwEye.setContentDescription(desc);
      pwEyeWrap.setContentDescription(desc);
    });
    pwBox.addView(pwEyeWrap);
    pwWrap.addView(pwBox, new LinearLayout.LayoutParams(-1, Math.max(dp(52), UiMetrics.dpRaw(this, 48))));
    panel.addView(pwWrap);
    final LinearLayout oauthWrap = column();
    oauthWrap.setVisibility(View.GONE);
    panel.addView(oauthWrap);
    request("GET", "/api/me/account-deletion", null, info -> {
      boolean reqPw = info.optBoolean("requiresPassword", true);
      pwWrap.setVisibility(reqPw ? View.VISIBLE : View.GONE);
      JSONArray providers = info.optJSONArray("oauthProviders");
      if (reqPw && providers != null && providers.length() > 0) {
        oauthWrap.removeAllViews();
        oauthWrap.setVisibility(View.VISIBLE);
        oauthWrap.addView(label(I18n.t(
            "Nếu tài khoản của bạn đăng nhập bằng Google/Facebook không có mật khẩu riêng, bấm bên dưới để xác thực lại và xóa ngay:"),
            12, MUTED));
        oauthWrap.addView(button(I18n.t("Xác thực & Xóa qua Google / Facebook"), () -> {
          try {
            startActivity(
                new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(ServerConfig.DEFAULT_ORIGIN + "/delete-account")));
          } catch (Exception ignored) {
          }
        }));
      }
    });
    Button remove = primary(I18n.t("Xóa vĩnh viễn tài khoản và dữ liệu"), () -> {
      final String entered = username.getText().toString().trim().replaceFirst("^@", "");
      if (!entered.equals(me.optString("username"))) {
        say(I18n.t("Nhập đúng tên đăng nhập để xác nhận."));
        return;
      }
      confirm(I18n.t("Bạn chắc chắn xóa vĩnh viễn? Không thể khôi phục dữ liệu."), () -> {
        JSONObject payload = json("confirmUsername", entered, "confirmDelete", true);
        String pwVal = password.getText().toString();
        if (!pwVal.isEmpty()) {
          try {
            payload.put("password", pwVal);
          } catch (JSONException ignored) {
          }
        }
        request("DELETE", "/api/me/account-deletion", payload, result -> {
          KinnectService.stop(this);
          if (calls != null) {
            calls.close();
            calls = null;
          }
          clearClientSessionCaches();
          me = null;
          auth(false);
          say(I18n.t("Đã xóa tài khoản và dữ liệu."));
        });
      });
    });
    panel.addView(remove);
    panel.addView(label(I18n.t("Hỗ trợ riêng tư: anhvn53@wru.vn · Không gửi mật khẩu hoặc OTP."), 12, MUTED));
  }

  private void groupTitle(String iconName, String title) {
    LinearLayout r = row();
    r.setPadding(dp(4), dp(10), 0, dp(8));
    r.addView(icon(iconName, 17, ACCENT_TEXT), new LinearLayout.LayoutParams(dp(17), dp(17)));
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
    row.setMinimumHeight(Math.max(dp(76), UiMetrics.dpRaw(this, 48)));
    String glyph = key.equals("discoverable") ? "user_search"
        : key.equals("showDistance") ? "distance_pins"
            : key.equals("backgroundSync") ? "bell" : "activity_status";
    row.addView(settingsIcon(glyph, ACCENT_TEXT), new LinearLayout.LayoutParams(dp(38), dp(38)));
    LinearLayout text = column();
    text.setPadding(dp(12), 0, dp(8), 0);
    TextView t = label(title, 15, TEXT);
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    text.addView(t);
    text.addView(label(subtitle, 12, MUTED));
    row.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
    final Switch check = new Switch(this);
    android.content.res.ColorStateList thumb = new android.content.res.ColorStateList(
        new int[][] { { android.R.attr.state_checked }, {} }, new int[] { ACCENT, 0xffffffff });
    android.content.res.ColorStateList track = new android.content.res.ColorStateList(
        new int[][] { { android.R.attr.state_checked }, {} }, new int[] { (ACCENT & 0x00ffffff) | 0x66000000, LINE });
    check.setThumbTintList(thumb);
    check.setTrackTintList(track);
    check.setContentDescription(title);
    check.setChecked(me.optBoolean(key, true));
    final boolean[] pending = { false };
    final int generation = screen;
    check.setOnCheckedChangeListener((view, selected) -> {
      if (pending[0])
        return;
      final boolean previous = me.optBoolean(key, true);
      pending[0] = true;
      check.setEnabled(false);
      api.call("PATCH", "/api/me", json(key, selected), (result, error, status) -> {
        if (generation != screen || isDestroyed())
          return;
        if (error != null || result == null || result.optJSONObject("user") == null) {
          pending[0] = true;
          check.setChecked(previous);
          say(error == null ? I18n.t("Chưa lưu được cài đặt.") : error);
        } else
          me = result.optJSONObject("user");
        pending[0] = false;
        check.setEnabled(true);
      });
    });
    check.setMinimumWidth(UiMetrics.dpRaw(this, 48));
    check.setMinimumHeight(UiMetrics.dpRaw(this, 48));
    row.addView(check, new LinearLayout.LayoutParams(-2, -2));
    row.setOnClickListener(v -> {
      if (check.isEnabled())
        check.toggle();
    });
    parent.addView(row, new LinearLayout.LayoutParams(-1, -2));
    UiMetrics.enforceMinTouchTarget(row, 48);
  }

  private void friendsScreen(final String selectedRaw) {
    final String selected = (selectedRaw == null || selectedRaw.isEmpty()) ? "friends" : selectedRaw;
    remember("friends", () -> friendsScreen(selected));
    headerActive = "friends";
    shell(I18n.t("Bạn bè"), true);
    final int generation = screen;
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
    final JSONArray[] loaded = { null }, suggested = { null }, discoverResults = { null };
    final Handler searchHandler = new Handler(Looper.getMainLooper());
    final Runnable render = () -> {
      list.removeAllViews();
      String rawQ = search.getText().toString().trim();
      String q = rawQ.toLowerCase(Locale.ROOT).replaceFirst("^@", "");
      String normQ = LiveGamePicker.normalized(q);
      List<JSONObject> myFriends = new ArrayList<>();
      Set<String> friendIds = new HashSet<>();
      JSONArray users = loaded[0];
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        if (u == null)
          continue;
        friendIds.add(u.optString("id"));
        if (normQ.isEmpty()) {
          myFriends.add(u);
        } else {
          String name = u.optString("name", "");
          String username = u.optString("username", "");
          String normTarget = LiveGamePicker.normalized(name + " " + username + " @" + username);
          if (normTarget.contains(normQ) || (name + " " + username).toLowerCase(Locale.ROOT).contains(q)) {
            myFriends.add(u);
          }
        }
      }
      if (normQ.isEmpty()) {
        if (myFriends.isEmpty()) {
          list.addView(emptyBlock("users_round",
              I18n.t("Chưa có ") + names[Math.max(0, Arrays.asList(keys).indexOf(selected))].toLowerCase(Locale.ROOT),
              I18n.t("Lời mời và kết nối mới sẽ hiển thị tại đây.")));
        } else if (selected.equals("friends")) {
          List<JSONObject> online = new ArrayList<>(), offline = new ArrayList<>();
          for (JSONObject u : myFriends)
            (u.optBoolean("isActive") && u.optBoolean("activityShared", true) ? online : offline).add(u);
          friendSection(list, I18n.t("Đang trực tuyến"), online, selected, selected);
          friendSection(list, I18n.t("Ngoại tuyến"), offline, selected, selected);
        } else
          friendSection(list, names[Arrays.asList(keys).indexOf(selected)], myFriends, selected, selected);
        if (selected.equals("friends")) {
          List<JSONObject> suggestions = new ArrayList<>();
          for (int i = 0; suggested[0] != null && i < suggested[0].length() && suggestions.size() < 6; i++) {
            JSONObject u = suggested[0].optJSONObject(i);
            if (u != null)
              suggestions.add(u);
          }
          if (!suggestions.isEmpty())
            friendSection(list, I18n.t("Gợi ý kết bạn"), suggestions, "suggestion", selected);
        }
      } else {
        if (!myFriends.isEmpty()) {
          if (selected.equals("friends"))
            friendSection(list, I18n.t("Bạn bè của bạn"), myFriends, selected, selected);
          else
            friendSection(list, names[Arrays.asList(keys).indexOf(selected)], myFriends, selected, selected);
        }
        if (selected.equals("friends")) {
          List<JSONObject> otherPeople = new ArrayList<>();
          String myId = me != null ? me.optString("id") : "";
          for (int i = 0; discoverResults[0] != null && i < discoverResults[0].length(); i++) {
            JSONObject u = discoverResults[0].optJSONObject(i);
            if (u == null)
              continue;
            String uid = u.optString("id");
            if (uid.equals(myId) || friendIds.contains(uid))
              continue;
            otherPeople.add(u);
          }
          if (!otherPeople.isEmpty()) {
            friendSection(list, I18n.t("Mọi người trên Kinnect"), otherPeople, "discover", selected);
          }
          if (myFriends.isEmpty() && otherPeople.isEmpty()) {
            if (discoverResults[0] != null) {
              list.addView(emptyBlock("users_round", I18n.t("Không tìm thấy kết quả"),
                  I18n.t("Không có thành viên nào khớp với \"") + rawQ + "\"."));
            } else {
              LinearLayout loading = row();
              loading.setGravity(Gravity.CENTER);
              loading.setPadding(0, dp(24), 0, dp(16));
              loading.addView(label(I18n.t("Đang tìm kiếm trên Kinnect…"), 14, MUTED));
              list.addView(loading);
            }
          }
        } else if (myFriends.isEmpty()) {
          list.addView(emptyBlock("users_round", I18n.t("Không tìm thấy"), I18n.t("Thử tìm kiếm với từ khóa khác.")));
        }
      }
    };
    final Runnable doSearch = () -> {
      final String rawQ = search.getText().toString().trim();
      final String q = rawQ.toLowerCase(Locale.ROOT).replaceFirst("^@", "");
      if (q.length() >= 1 && selected.equals("friends")) {
        request("GET", "/api/discover?q=" + encode(q), null, data -> {
          if (generation != screen || isDestroyed())
            return;
          String activeQ = search.getText().toString().trim().toLowerCase(Locale.ROOT).replaceFirst("^@", "");
          if (!activeQ.equals(q))
            return;
          discoverResults[0] = data == null ? null : data.optJSONArray("users");
          render.run();
        });
      } else {
        discoverResults[0] = null;
      }
    };
    search.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int b, int c) {
      }

      public void onTextChanged(CharSequence s, int a, int b, int c) {
      }

      public void afterTextChanged(android.text.Editable s) {
        render.run();
        searchHandler.removeCallbacksAndMessages(null);
        searchHandler.postDelayed(() -> {
          if (generation != screen || isDestroyed())
            return;
          doSearch.run();
        }, 250);
      }
    });
    search.setOnEditorActionListener((v, actionId, event) -> {
      searchHandler.removeCallbacksAndMessages(null);
      doSearch.run();
      return false;
    });
    cachedRequest(selected.equals("friends") ? "/api/friends" : "/api/friend-requests", data -> {
      JSONArray rawList = data == null ? null
          : data.optJSONArray(selected.equals("friends") ? "users" : selected);
      if (rawList == null && data != null && !selected.equals("friends") && "incoming".equals(selected))
        rawList = data.optJSONArray("requests");
      JSONArray normalized = new JSONArray();
      for (int i = 0; rawList != null && i < rawList.length(); i++) {
        JSONObject entry = rawList.optJSONObject(i);
        if (entry == null)
          continue;
        String dir = entry.optString("direction", entry.optString("type", ""));
        if (!selected.equals("friends") && !dir.isEmpty() && !dir.equals(selected))
          continue;
        JSONObject u = entry.has("user") && entry.optJSONObject("user") != null ? entry.optJSONObject("user") : entry;
        if (!u.has("friendship") || u.optString("friendship").isEmpty()) {
          try {
            JSONObject copy = new JSONObject(u.toString());
            copy.put("friendship", selected.equals("friends") ? "friends" : selected);
            u = copy;
          } catch (JSONException ignored) {
          }
        }
        normalized.put(u);
      }
      loaded[0] = normalized;
      render.run();
    }, () -> {
    });
    if (selected.equals("friends"))
      cachedRequest("/api/friend-suggestions", data -> {
        suggested[0] = data.optJSONArray("users");
        if (loaded[0] != null)
          render.run();
      }, () -> {
      });
  }

  private void friendSection(LinearLayout list, String title, List<JSONObject> users, final String kind,
      final String selected) {
    if (users.isEmpty())
      return;
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
      TextView sub = label(
          "@" + u.optString("username") + " · " + (active ? I18n.t("Đang hoạt động") : I18n.t("Ngoại tuyến")), 12,
          active ? WebDesign.ONLINE_STRICT[WebTheme.isDark(this) ? 1 : 0] : MUTED);
      sub.setSingleLine(false);
      sub.setMaxLines(2);
      sub.setEllipsize(android.text.TextUtils.TruncateAt.END);
      who.addView(sub);
      r.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
      String id = u.optString("id");
      String fs = u.optString("friendship", "none");
      if (kind.equals("friends") || fs.equals("friends"))
        r.addView(roundAction("message_square", I18n.t("Nhắn tin"), true, () -> chat(u)));
      else if (kind.equals("incoming") || fs.equals("incoming")) {
        r.addView(roundAction("check", I18n.t("Chấp nhận"), true,
            () -> request("POST", "/api/users/" + id + "/friend-request/respond", json("action", "accept"), d -> {
              say(I18n.t("Đã chấp nhận kết bạn"));
              friendsScreen(selected);
            })));
        r.addView(roundAction("x", I18n.t("Từ chối"), false,
            () -> request("POST", "/api/users/" + id + "/friend-request/respond", json("action", "decline"), d -> {
              say(I18n.t("Đã từ chối lời mời"));
              friendsScreen(selected);
            })));
      } else if (kind.equals("outgoing") || fs.equals("outgoing"))
        r.addView(roundAction("user_check", I18n.t("Hủy lời mời"), false,
            () -> request("DELETE", "/api/users/" + id + "/friend-request", json(), d -> {
              say(I18n.t("Đã hủy lời mời kết bạn"));
              friendsScreen(selected);
            })));
      else
        r.addView(roundAction("user_plus", I18n.t("Kết bạn"), true,
            () -> request("POST", "/api/users/" + id + "/friend-request", json(), d -> {
              say(I18n.t("Đã gửi lời mời kết bạn"));
              try {
                u.put("friendship", "outgoing");
              } catch (JSONException ignored) {
              }
              friendsScreen(selected);
            })));
      r.setOnClickListener(v -> person(u));
      group.addView(r, new LinearLayout.LayoutParams(-1, -2));
      UiMetrics.enforceMinTouchTarget(r, 48);
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
    bubble.addView(icon(iconName, 24, ACCENT_TEXT), new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
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

  // Trang Video: nền đen toàn màn, thanh tab trong suốt nổi phía trên (Trực tiếp
  // · Đề xuất · Đang theo dõi).
  private FrameLayout reelStage() {
    stopShort();
    if (reelViewport != null && reelViewport.getParent() == root) {
      reelViewport.prepare();
      reelViewport.removeAllViews();
      return reelViewport;
    }
    ScrollView scroll = (ScrollView) content.getParent();
    int at = root.indexOfChild(scroll);
    root.removeView(scroll);
    reelViewport = new VerticalMediaStage(this, direction -> {
      if (direction < 0 && shortIndex == 0) {
        reelViewport.settle();
        refreshVideos(reelViewport);
        return true;
      }
      if (shortRows == null || shortRows.length() == 0)
        return false;
      final int next = VideoFeedPolicy.index(shortIndex + direction, shortRows.length(), !shortsFollowing);
      if (next == shortIndex)
        return false;
      reelViewport.exit(direction, () -> {
        shortEnter = direction;
        showShort(next);
      });
      return true;
    });
    reelViewport.setRefreshAction(() -> refreshVideos(reelViewport));
    reelViewport.setBackgroundColor(0xff000000);
    root.addView(reelViewport, at, new LinearLayout.LayoutParams(-1, 0, 1));
    return reelViewport;
  }

  private void downloadShort(JSONObject video) {
    pendingDownload = video.optString("video");
    Intent save = new Intent(Intent.ACTION_CREATE_DOCUMENT);
    save.addCategory(Intent.CATEGORY_OPENABLE);
    save.setType("video/mp4");
    save.putExtra(Intent.EXTRA_TITLE, "Kinnect-" + video.optString("id") + ".mp4");
    try {
      startActivityForResult(save, 309);
    } catch (Exception error) {
      pendingDownload = "";
      say(I18n.t("Chưa mở được trình lưu video."));
    }
  }

  private void downloadAudio(JSONObject video) {
    pendingDownload = video.optString("video");
    Intent save = new Intent(Intent.ACTION_CREATE_DOCUMENT);
    save.addCategory(Intent.CATEGORY_OPENABLE);
    save.setType("audio/mp4");
    save.putExtra(Intent.EXTRA_TITLE, "Kinnect-Audio-" + video.optString("id") + ".m4a");
    try {
      startActivityForResult(save, 309);
    } catch (Exception error) {
      pendingDownload = "";
      say(I18n.t("Chưa mở được trình lưu âm thanh."));
    }
  }

  private int findShort(String id) {
    for (int i = 0; shortRows != null && i < shortRows.length(); i++)
      if (shortRows.optJSONObject(i).optString("id").equals(id))
        return i;
    return shortIndex;
  }

  private JSONArray orderedShorts(JSONArray source) {
    if (source == null || shortsFollowing)
      return source;
    List<JSONObject> rows = new ArrayList<>();
    for (int i = 0; i < source.length(); i++)
      if (source.optJSONObject(i) != null)
        rows.add(source.optJSONObject(i));
    Collections.sort(rows,
        (a, b) -> VideoFeedPolicy.compare(a.optLong("likes"), a.optLong("comments"), a.optLong("created"),
            a.optString("id"), b.optLong("likes"), b.optLong("comments"), b.optLong("created"), b.optString("id")));
    return new JSONArray(rows);
  }

  private void refreshVideos(FrameLayout stage) {
    if (shortRefreshing)
      return;
    shortRefreshing = true;
    ProgressBar progress = new ProgressBar(this);
    FrameLayout.LayoutParams at = new FrameLayout.LayoutParams(dp(36), dp(36), Gravity.TOP | Gravity.CENTER_HORIZONTAL);
    at.topMargin = dp(64);
    stage.addView(progress, at);
    request("GET", shortsFollowing ? "/api/shorts?feed=following" : "/api/shorts", null, data -> {
      JSONArray updated = orderedShorts(data.optJSONArray("shorts"));
      if (updated == null)
        return;
      if (shortRows != null && shortRows.toString().equals(updated.toString()))
        return;
      shortRows = updated;
      if (updated.length() > 0)
        showShort(0);
      else
        shorts();
    }, () -> {
      shortRefreshing = false;
      stage.removeView(progress);
    });
  }

  private void shorts() {
    shortsFollowing = shortsTab.equals("following");
    final FrameLayout stage = reelStage();

    final TextView loading = label(I18n.t("Đang tải video…"), 14, 0x99ffffff);
    stage.addView(loading, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    stage.addView(reelTabs(), new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    cachedRequest(shortsFollowing ? "/api/shorts?feed=following" : "/api/shorts", data -> {
      shortRows = orderedShorts(data.optJSONArray("shorts"));
      if (shortRows == null || shortRows.length() == 0) {
        stage.removeView(loading);
        LinearLayout empty = column();
        empty.setGravity(Gravity.CENTER_HORIZONTAL);
        FrameLayout bubble = new FrameLayout(this);
        bubble.setBackground(background(0x26ffffff, 99));
        bubble.addView(icon("clapperboard", 30, WHITE), new FrameLayout.LayoutParams(dp(30), dp(30), Gravity.CENTER));
        empty.addView(bubble, new LinearLayout.LayoutParams(dp(72), dp(72)));
        TextView t = label(shortsFollowing ? I18n.t("Chưa có video từ người bạn theo dõi") : I18n.t("Chưa có video"),
            16, WHITE);
        t.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
        t.setGravity(Gravity.CENTER);
        t.setPadding(0, dp(16), 0, dp(16));
        empty.addView(t);
        LinearLayout b = authButton("video", "Quay video", true);
        b.setPadding(dp(20), 0, dp(20), 0);
        b.setOnClickListener(v -> chooseVideo());
        empty.addView(b, new LinearLayout.LayoutParams(-2, Math.max(dp(46), UiMetrics.dpRaw(this, 48))));
        stage.addView(empty, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
        return;
      }
      showShort(0);
    }, () -> {
    });
  }

  // Tab "Trực tiếp": lưới các buổi đang live chuẩn Google / YouTube Live, chạm để
  // vào xem ngay.
  private FrameLayout liveCard(final JSONObject room) {
    FrameLayout c = new FrameLayout(this);
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
        new int[] { 0xff2b1848, 0xff161028 });
    g.setCornerRadius(dp(20));
    g.setStroke(Math.max(1, dp(1)), 0x22ffffff);
    c.setBackground(g);
    c.setClipToOutline(true);

    LinearLayout col = column();
    col.setMinimumHeight(dp(220));

    LinearLayout badges = row();
    badges.setPadding(dp(10), dp(10), dp(10), dp(8));
    TextView live = label("● LIVE", 10, WHITE);
    live.setTypeface(null, Typeface.BOLD);
    live.setPadding(dp(8), dp(3), dp(8), dp(3));
    live.setBackground(background(WebDesign.LIVE_RED, 99));
    badges.addView(live);
    LinearLayout viewers = row();
    viewers.setGravity(Gravity.CENTER_VERTICAL);
    viewers.setPadding(dp(8), dp(3), dp(8), dp(3));
    viewers.setBackground(background(0x88141418, 99));
    viewers.addView(icon("eye", 12, WHITE), new LinearLayout.LayoutParams(dp(12), dp(12)));
    TextView viewerCount = label(" " + room.optInt("viewers"), 10, WHITE);
    viewerCount.setTypeface(null, Typeface.BOLD);
    viewerCount.setPadding(0, 0, 0, 0);
    viewers.addView(viewerCount);
    LinearLayout.LayoutParams vp = new LinearLayout.LayoutParams(-2, -2);
    vp.leftMargin = dp(6);
    badges.addView(viewers, vp);
    col.addView(badges, new LinearLayout.LayoutParams(-1, -2));

    LinearLayout center = column();
    center.setGravity(Gravity.CENTER);
    center.setMinimumHeight(dp(92));
    center.setPadding(dp(10), dp(6), dp(10), dp(8));
    FrameLayout ring = new FrameLayout(this);
    GradientDrawable rg = new GradientDrawable();
    rg.setShape(GradientDrawable.OVAL);
    rg.setColor(0x22d61f26);
    rg.setStroke(dp(2), WebDesign.LIVE_RED);
    ring.setBackground(rg);
    ring.setPadding(dp(4), dp(4), dp(4), dp(4));
    LinearLayout holder = new LinearLayout(this);
    JSONObject host = json("id", room.optString("hostId"), "name", room.optString("host"), "avatar",
        room.isNull("avatar") ? "" : room.optString("avatar"));
    avatar(host, holder, 68);
    ring.addView(holder, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    center.addView(ring, new LinearLayout.LayoutParams(-2, -2));
    col.addView(center, new LinearLayout.LayoutParams(-1, -2));

    LinearLayout info = column();
    info.setPadding(dp(12), dp(14), dp(12), dp(12));
    info.setBackground(
        new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, WebDesign.SCRIM_BOTTOM));
    String mode = room.optString("liveMode", "chat");
    TextView modeTag = label(I18n.t(mode.equals("game") ? "Chơi game" : "Trò chuyện"), 10, 0xfffdd663);
    modeTag.setTypeface(null, Typeface.BOLD);
    info.addView(modeTag);
    TextView title = label(room.optString("title"), 14, WHITE);
    title.setTypeface(null, Typeface.BOLD);
    title.setMaxLines(2);
    title.setEllipsize(android.text.TextUtils.TruncateAt.END);
    title.setPadding(0, dp(2), 0, dp(2));
    info.addView(title);
    info.addView(label(room.optString("host"), 12, 0xffe5e7eb));
    col.addView(info, new LinearLayout.LayoutParams(-1, -2));

    c.addView(col, new FrameLayout.LayoutParams(-1, -2));
    c.setOnClickListener(v -> {
      Intent i = new Intent(this, LiveActivity.class);
      i.putExtra(LiveActivity.EXTRA_ROOM, room.optString("id"));
      startActivity(i);
    });
    return c;
  }

  private int shortEnter = 0;
  private VerticalMediaStage reelViewport;

  private void showShort(int index) {
    if (shortRows == null || shortRows.length() == 0)
      return;
    shortIndex = VideoFeedPolicy.index(index, shortRows.length(), !shortsFollowing);
    if (reelViewport == null || reelViewport.getParent() != root)
      shell(I18n.t("Video ngắn"), true);
    final JSONObject item = shortRows.optJSONObject(shortIndex);
    if (item == null) {
      say(I18n.t("Video không khả dụng."));
      return;
    }
    JSONObject rawAuthor = item.optJSONObject("author");
    final JSONObject author = rawAuthor == null ? new JSONObject() : rawAuthor;
    // Keep the app shell stable while changing only the media stage.
    FrameLayout stage = reelStage();
    shortVideo = new VideoView(this);
    final VideoView playerView = shortVideo;
    stage.addView(shortVideo, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
    Map<String, String> headers = new HashMap<>();
    headers.put("Cookie", api.jar());
    final String videoPath = item.optString("video");
    final boolean hasVideo = !videoPath.isEmpty();
    final java.io.File savedVideo = api.cachedVideo(videoPath);
    FrameLayout preview = new FrameLayout(this);
    ImageView poster = new ImageView(this);
    poster.setScaleType(ImageView.ScaleType.FIT_CENTER);
    preview.addView(poster, new FrameLayout.LayoutParams(-1, -1));
    byte[] thumbnail = api.cachedThumbnail(videoPath);
    if (thumbnail != null)
      MediaImageLoader.decodeAsync(thumbnail, 640, bmp -> {
        if (bmp != null && !isDestroyed() && shortVideo == playerView)
          poster.setImageBitmap(bmp);
      });
    TextView unavailable = label(I18n.t("Video chưa lưu trên máy · Chờ máy chủ hoạt động lại"), 13, WHITE);
    unavailable.setGravity(Gravity.CENTER);
    unavailable.setPadding(dp(30), dp(12), dp(70), dp(12));
    unavailable.setBackgroundColor(0x99000000);
    unavailable.setVisibility(View.GONE);
    preview.addView(unavailable, new FrameLayout.LayoutParams(-1, -2, Gravity.CENTER));
    stage.addView(preview, new FrameLayout.LayoutParams(-1, -1));
    if (savedVideo != null)
      shortVideo.setVideoURI(android.net.Uri.fromFile(savedVideo));
    else if (hasVideo && !item.optBoolean("offline"))
      shortVideo.setVideoURI(android.net.Uri.parse(server() + videoPath), headers);
    else
      unavailable.setVisibility(View.VISIBLE);
    shortVideo.setOnPreparedListener(player -> {
      if (stopped || shortVideo != playerView)
        return;
      shortPlayer = player;
      preview.setVisibility(View.GONE);
      api.warmVideo(videoPath);
      player.setLooping(true);
      player.setVolume(shortMuted ? 0 : 1, shortMuted ? 0 : 1);
      if (!mediaCallBlocked)
        shortVideo.start();
      android.util.Log.i("KinnectQA", "SHORTS_EVENT: action=playing index=" + shortIndex + " id=" + item.optString("id")
          + " pos=" + shortVideo.getCurrentPosition() + " muted=" + shortMuted);
    });
    shortVideo.setOnErrorListener((player, what, extra) -> {
      preview.setVisibility(View.VISIBLE);
      unavailable.setVisibility(View.VISIBLE);
      return true;
    });
    if (shortEnter != 0) {
      int direction = shortEnter;
      shortEnter = 0;
      VerticalMediaStage.enter(stage, direction);
    }
    final FrameLayout pauseBadge = new FrameLayout(this);
    GradientDrawable pauseBg = background(0x88141418, 999);
    pauseBg.setStroke(dp(1), 0x33ffffff);
    pauseBadge.setBackground(pauseBg);
    pauseBadge.addView(icon("play", 28, WHITE), new FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER));
    pauseBadge.setVisibility(View.GONE);
    stage.addView(pauseBadge, new FrameLayout.LayoutParams(dp(64), dp(64), Gravity.CENTER));
    stage.setOnClickListener(v -> {
      if (shortVideo != null) {
        if (shortVideo.isPlaying()) {
          shortVideo.pause();
          android.util.Log.i("KinnectQA",
              "SHORTS_EVENT: action=pause pos=" + shortVideo.getCurrentPosition() + " isPlaying=false");
          pauseBadge.setAlpha(0f);
          pauseBadge.setScaleX(0.85f);
          pauseBadge.setScaleY(0.85f);
          pauseBadge.setVisibility(View.VISIBLE);
          pauseBadge.animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(150).start();
        } else if (!mediaCallBlocked) {
          shortVideo.start();
          android.util.Log.i("KinnectQA",
              "SHORTS_EVENT: action=start pos=" + shortVideo.getCurrentPosition() + " isPlaying=true");
          pauseBadge.animate().alpha(0f).setDuration(120).withEndAction(() -> pauseBadge.setVisibility(View.GONE))
              .start();
        }
      }
    });
    // Cột nút bên phải
    LinearLayout side = column();
    side.setGravity(Gravity.CENTER_HORIZONTAL);

    final int raw48 = UiMetrics.dpRaw(this, 48);
    final LinearLayout authorTile = column();
    authorTile.setGravity(Gravity.CENTER_HORIZONTAL);
    LinearLayout faceHolder = column();
    faceHolder.setGravity(Gravity.CENTER);
    avatar(author, faceHolder, 46);
    faceHolder.setContentDescription(I18n.t("Ảnh của ") + author.optString("name"));
    faceHolder.setOnClickListener(v -> person(author));
    authorTile.addView(faceHolder, new LinearLayout.LayoutParams(raw48, raw48));
    boolean own = author.optString("id").equals(me.optString("id"));
    final FrameLayout mark = !own ? new FrameLayout(this) : null;
    if (!own) {
      FrameLayout follow = new FrameLayout(this);
      ImageView symbol = icon(author.optBoolean("following") ? "check" : "plus", 15, WHITE);
      mark.setBackground(background(author.optBoolean("following") ? ACCENT : PINK, 99));
      mark.addView(symbol, new FrameLayout.LayoutParams(dp(15), dp(15), Gravity.CENTER));
      FrameLayout.LayoutParams markLp = new FrameLayout.LayoutParams(dp(25), dp(25),
          Gravity.TOP | Gravity.CENTER_HORIZONTAL);
      markLp.topMargin = dp(2);
      follow.addView(mark, markLp);
      follow.setContentDescription(
          author.optBoolean("following") ? I18n.t("Bỏ theo dõi tác giả") : I18n.t("Theo dõi tác giả"));
      follow.setOnClickListener(v -> {
        follow.setEnabled(false);
        request(author.optBoolean("following") ? "DELETE" : "POST", "/api/users/" + author.optString("id") + "/follow",
            json(), result -> {
              JSONObject updated = result.optJSONObject("user");
              boolean followed = updated != null ? updated.optBoolean("following") : !author.optBoolean("following");
              try {
                author.put("following", followed);
                for (int i = 0; shortRows != null && i < shortRows.length(); i++) {
                  JSONObject who = shortRows.optJSONObject(i).optJSONObject("author");
                  if (who != null && who.optString("id").equals(author.optString("id")))
                    who.put("following", followed);
                }
              } catch (JSONException ignored) {
              }
              symbol.setImageDrawable(WebIcons.load(this, followed ? "check" : "plus"));
              symbol.setImageTintList(android.content.res.ColorStateList.valueOf(WHITE));
              mark.setBackground(background(followed ? ACCENT : PINK, 99));
              follow.setContentDescription(followed ? I18n.t("Bỏ theo dõi tác giả") : I18n.t("Theo dõi tác giả"));
              say(followed ? I18n.t("Đã theo dõi") : I18n.t("Đã bỏ theo dõi"));
            }, () -> follow.setEnabled(true));
      });
      authorTile.addView(follow, new LinearLayout.LayoutParams(raw48, raw48));
    }
    side.addView(authorTile, new LinearLayout.LayoutParams(dp(54), -2));
    final LinearLayout love = reelButton("heart", String.valueOf(item.optInt("likes")),
        item.optBoolean("liked") ? PINK : WHITE, () -> {
        });
    love.setContentDescription(item.optBoolean("liked") ? I18n.t("Bỏ thích video") : I18n.t("Thích video"));
    love.setOnClickListener(v -> {
      final boolean previous = item.optBoolean("liked");
      love.setEnabled(false);
      request(previous ? "DELETE" : "POST", "/api/shorts/" + item.optString("id") + "/like", json(), result -> {
        boolean liked = result.has("liked") ? result.optBoolean("liked") : !previous;
        int count = result.has("likes") ? result.optInt("likes")
            : Math.max(0, item.optInt("likes") + (liked == previous ? 0 : liked ? 1 : -1));
        try {
          item.put("liked", liked);
          item.put("likes", count);
        } catch (JSONException ignored) {
        }
        ((ImageView) love.getChildAt(0))
            .setImageTintList(android.content.res.ColorStateList.valueOf(liked ? PINK : WHITE));
        ((TextView) love.getChildAt(1)).setText(String.valueOf(count));
        love.setContentDescription(liked ? I18n.t("Bỏ thích video") : I18n.t("Thích video"));
      }, () -> love.setEnabled(true));
    });
    side.addView(love);
    side.addView(reelButton("comment", item.has("comments") ? String.valueOf(item.optInt("comments")) : "0", WHITE,
        () -> shortComments(item), I18n.t("Bình luận")));
    side.addView(reelButton("share", "", WHITE, () -> {
      Intent send = new Intent(Intent.ACTION_SEND);
      send.setType("text/plain");
      send.putExtra(Intent.EXTRA_TEXT, "Xem video của @" + author.optString("username")
          + " trên Kinnect: https://app.kinnect.io.vn/share/short/" + item.optString("id"));
      try {
        startActivity(Intent.createChooser(send, I18n.t("Chia sẻ video")));
      } catch (Exception ignored) {
      }
    }, I18n.t("Chia sẻ video")));
    // Nút âm thanh nằm trong shortOptions (Tùy chọn) — cột bên phải chỉ giữ icon +
    // số như TikTok.
    side.addView(reelButton("more", "", WHITE, () -> shortOptions(item), I18n.t("Tùy chọn video")));
    ScrollView actionRail = new ScrollView(this);
    actionRail.setVerticalScrollBarEnabled(false);
    actionRail.setFillViewport(true);
    side.setGravity(Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    actionRail.addView(side);
    FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(dp(64), -1, Gravity.END);
    sp.topMargin = dp(64);
    sp.bottomMargin = dp(65);
    stage.addView(actionRail, sp);
    stage.addView(reelTabs(), new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    // Tên + chú thích với lớp phủ gradient đáy sắc nét
    View bottomScrim = new View(this);
    bottomScrim.setBackground(
        new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x00000000, 0xcc000000 }));
    stage.addView(bottomScrim, new FrameLayout.LayoutParams(-1, dp(190), Gravity.BOTTOM));
    LinearLayout meta = column();
    TextView name = label("@" + author.optString("username"), 14, WHITE);
    name.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    name.setShadowLayer(4, 0, 1, 0xaa000000);
    meta.addView(name);
    if (!item.optString("caption").isEmpty()) {
      TextView cap = label(item.optString("caption"), 13, WHITE);
      cap.setLineSpacing(0, 1.25f);
      cap.setPadding(0, dp(4), 0, 0);
      cap.setShadowLayer(4, 0, 1, 0xaa000000);
      meta.addView(cap);
    }

    FrameLayout.LayoutParams mp = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
    mp.setMargins(dp(14), 0, dp(76), dp(26));
    stage.addView(meta, mp);
    actionRail.bringToFront();
    stage.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
      int width = r - l, height = b - t;
      boolean compact = width > height;
      // A short viewport cannot hold the portrait rail. All actions stay visible
      // in one bottom row; never rebuild the VideoView during a resize.
      side.setOrientation(compact ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
      side.setGravity(compact ? Gravity.CENTER_VERTICAL : Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
      authorTile.setOrientation(compact ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
      authorTile.setGravity(compact ? Gravity.CENTER_VERTICAL : Gravity.CENTER_HORIZONTAL);
      if (mark != null && mark.getLayoutParams() instanceof FrameLayout.LayoutParams) {
        FrameLayout.LayoutParams ml = (FrameLayout.LayoutParams) mark.getLayoutParams();
        int targetG = compact ? Gravity.CENTER : (Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        int targetTop = compact ? 0 : dp(2);
        if (ml.gravity != targetG || ml.topMargin != targetTop) {
          ml.gravity = targetG;
          ml.topMargin = targetTop;
          mark.setLayoutParams(ml);
        }
      }
      FrameLayout.LayoutParams rail = (FrameLayout.LayoutParams) actionRail.getLayoutParams();
      int railWidth = compact ? Math.min(width - dp(16), (own ? raw48 : raw48 * 2) + dp(264)) : dp(64);
      int railHeight = compact ? dp(76) : -1;
      int top = compact ? 0 : dp(56), bottomMargin = compact ? dp(6) : dp(16);
      if (rail.width != railWidth || rail.height != railHeight || rail.topMargin != top
          || rail.bottomMargin != bottomMargin) {
        rail.width = railWidth;
        rail.height = railHeight;
        rail.gravity = Gravity.END | Gravity.BOTTOM;
        rail.topMargin = top;
        rail.bottomMargin = bottomMargin;
        rail.rightMargin = compact ? dp(8) : 0;
        actionRail.setLayoutParams(rail);
      }
      for (int n = 0; n < side.getChildCount(); n++) {
        View action = side.getChildAt(n);
        LinearLayout.LayoutParams cell = (LinearLayout.LayoutParams) action.getLayoutParams();
        int cw = compact ? (n == 0 ? (own ? raw48 : raw48 * 2) : dp(64)) : dp(64);
        if (cell.width != cw) {
          cell.width = cw;
          action.setLayoutParams(cell);
        }
        if (n > 0 && action instanceof LinearLayout) {
          LinearLayout box = (LinearLayout) action;
          // Nút icon-only (chia sẻ / tùy chọn) không có TextView số bên dưới.
          if (box.getChildCount() > 1 && box.getChildAt(1) instanceof TextView) {
            TextView caption = (TextView) box.getChildAt(1);
            caption.setSingleLine(compact);
            caption.setEllipsize(android.text.TextUtils.TruncateAt.END);
          }
        }
      }
      FrameLayout.LayoutParams details = (FrameLayout.LayoutParams) meta.getLayoutParams();
      int right = compact ? dp(326) : dp(84);
      if (details.rightMargin != right) {
        details.rightMargin = right;
        details.bottomMargin = dp(12);
        meta.setLayoutParams(details);
      }
    });
  }

  private TextView reelTab(String text, boolean active, Runnable click) {
    TextView t = label(text, 16, WHITE);
    t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
    t.setPadding(dp(12), dp(6), dp(12), dp(6));
    t.setShadowLayer(4, 0, 1, 0xaa000000);
    t.setOnClickListener(v -> click.run());
    return t;
  }

  private LinearLayout reelButton(String iconName, String caption, int color, Runnable click) {
    return reelButton(iconName, caption, color, click, caption);
  }

  /** Cột nút kiểu TikTok: icon tròn, chỉ hiện số bên dưới (không hiện chữ). */
  private LinearLayout reelButton(String iconName, String caption, int color, Runnable click, String a11yLabel) {
    LinearLayout box = column();
    box.setGravity(Gravity.CENTER_HORIZONTAL);
    box.setPadding(0, dp(8), 0, dp(3));
    box.setMinimumHeight(dp(56));
    ImageView i = icon(iconName, 25, color);
    GradientDrawable orb = background(0xa617171c, 999);
    orb.setStroke(dp(1), 0x33ffffff);
    i.setBackground(orb);
    i.setPadding(dp(10), dp(10), dp(10), dp(10));
    i.setElevation(dp(3));
    box.addView(i, new LinearLayout.LayoutParams(dp(46), dp(46)));
    // Chỉ giữ lại dòng số (lượt thích / bình luận). Các nhãn chữ "Chia sẻ",
    // "Tùy chọn video" được bỏ để đồng bộ với iOS; vẫn để contentDescription cho
    // TalkBack.
    if (caption != null && caption.matches("\\d+")) {
      TextView text = label(caption, 12, WHITE);
      text.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
      text.setShadowLayer(4, 0, 1, 0xaa000000);
      text.setGravity(Gravity.CENTER);
      text.setPadding(dp(3), dp(2), dp(3), dp(2));
      box.addView(text);
    }
    box.setContentDescription(a11yLabel == null || a11yLabel.isEmpty() ? iconName : a11yLabel);
    box.setTooltipText(box.getContentDescription());
    box.setOnClickListener(v -> click.run());
    tactile(box);
    return box;
  }

  // Thanh tab trắng phía trên video như web: Trực tiếp · Đề xuất · Đang theo dõi
  // Thanh tab trong suốt nổi trên video: chữ trắng có bóng, gạch chân trắng ở tab
  // đang chọn.
  private LinearLayout reelTabs() {
    LinearLayout bar = row();
    bar.setGravity(Gravity.CENTER);
    bar.setPadding(0, dp(10), 0, dp(14));
    bar.setBackground(
        new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x99000000, 0x00000000 }));
    String[][] items = { { "for", "Đề xuất" }, { "following", "Đang theo dõi" } };
    for (final String[] it : items) {
      boolean active = it[0].equals(shortsTab);
      LinearLayout cell = column();
      cell.setGravity(Gravity.CENTER_HORIZONTAL);
      cell.setPadding(dp(12), 0, dp(12), 0);
      TextView t = label((it[0].equals("live") ? "● " : "") + it[1], 14, WHITE);
      t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
      t.setGravity(Gravity.CENTER);
      t.setShadowLayer(dp(3), 0, dp(1), 0xaa000000);
      t.setPadding(0, 0, 0, 0);
      t.setSingleLine(true);
      cell.addView(t, new LinearLayout.LayoutParams(-1, -2));
      View line = new View(this);
      line.setBackground(background(active ? WHITE : 0x00000000, 99));
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(28), dp(3));
      lp.topMargin = dp(6);
      cell.addView(line, lp);
      cell.setOnClickListener(v -> {
        shortsTab = it[0];
        navigate("shorts");
      });
      bar.addView(cell, new LinearLayout.LayoutParams(0, Math.max(dp(44), UiMetrics.dpRaw(this, 48)), 1));
      UiMetrics.enforceMinTouchTarget(cell, 48);
    }
    return bar;
  }

  private android.app.Dialog shortOptions(final JSONObject item) {
    final boolean mine = item.optString("user_id").equals(me.optString("id"));
    final android.app.Dialog[] dialog = new android.app.Dialog[1];

    LinearLayout container = column();
    container.setPadding(0, dp(8), 0, dp(16));

    HorizontalScrollView scroll1 = new HorizontalScrollView(this);
    scroll1.setHorizontalScrollBarEnabled(false);
    LinearLayout row1 = row();
    row1.setPadding(dp(16), 0, dp(16), 0);

    Runnable close = () -> {
      if (dialog[0] != null)
        dialog[0].dismiss();
    };

    row1.addView(tiktokOptionBtn("download", I18n.t("Lưu video"), () -> {
      close.run();
      downloadShort(item);
    }));
    row1.addView(tiktokOptionBtn("music", I18n.t("Âm thanh"), () -> {
      close.run();
      downloadAudio(item);
    }));
    row1.addView(
        tiktokOptionBtn(shortMuted ? "mute" : "sound", shortMuted ? I18n.t("Bật âm") : I18n.t("Tắt âm"), () -> {
          close.run();
          shortMuted = !shortMuted;
          if (shortPlayer != null)
            shortPlayer.setVolume(shortMuted ? 0 : 1, shortMuted ? 0 : 1);
          showShort(shortIndex);
        }));
    row1.addView(tiktokOptionBtn(mine ? "trash" : "flag", mine ? I18n.t("Xoá") : I18n.t("Báo cáo"), () -> {
      close.run();
      if (mine)
        confirm(I18n.t("Xoá video?"),
            () -> request("DELETE", "/api/shorts/" + item.optString("id"), json(), r -> navigate("shorts")));
      else
        report("short", item.optString("id"));
    }));
    row1.addView(tiktokOptionBtn("user_round", I18n.t("Hồ sơ"), () -> {
      close.run();
      person(item.optJSONObject("author"));
    }));

    scroll1.addView(row1);
    container.addView(scroll1);

    dialog[0] = new Sheet(this).setTitle(I18n.t("Tùy chọn")).setView(container).show();
    return dialog[0];
  }

  private LinearLayout tiktokOptionBtn(String iconName, String labelText, Runnable action) {
    LinearLayout btn = column();
    btn.setGravity(Gravity.CENTER);
    btn.setPadding(0, 0, dp(16), 0);

    FrameLayout circle = new FrameLayout(this);
    circle.setBackground(background(SOFT, 99));
    circle.addView(icon(iconName, 24, TEXT), new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
    btn.addView(circle, new LinearLayout.LayoutParams(dp(54), dp(54)));

    TextView t = label(labelText, 12, TEXT);
    t.setSingleLine(true);
    t.setEllipsize(android.text.TextUtils.TruncateAt.END);
    t.setGravity(Gravity.CENTER);
    btn.addView(t, new LinearLayout.LayoutParams(dp(68), -2));

    btn.setOnClickListener(v -> action.run());
    return btn;
  }

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
    close.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    head.addView(UiMetrics.wrapMinTouchTarget(this, close, 48));
    sheet.addView(head);
    final ScrollView scroll = new ScrollView(this);
    final LinearLayout list = column();
    list.setPadding(dp(16), dp(4), dp(16), dp(8));
    scroll.addView(list);
    sheet.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    sheet.addView(divider());
    final EditText input = new KinnectInput(this);
    final int raw48 = UiMetrics.dpRaw(this, 48);
    HorizontalScrollView emojiScroll = new HorizontalScrollView(this);
    emojiScroll.setHorizontalScrollBarEnabled(false);
    LinearLayout emojis = row();
    emojis.setPadding(dp(6), dp(6), dp(6), dp(2));
    int emojiWash = 0xff1c1726;
    final String[] shortEmojis = new String[] { "😍", "😂", "🔥", "👏", "🥰", "😮", "😢", "💜" };
    for (int idx = 0; idx < shortEmojis.length; idx++) {
      final String e = shortEmojis[idx];
      TextView t = label(e, 20, WHITE);
      t.setGravity(Gravity.CENTER);
      t.setBackground(pressable(emojiWash, 99));
      t.setPadding(0, 0, 0, 0);
      t.setOnClickListener(v -> {
        input.append(e);
        input.requestFocus();
      });
      LinearLayout.LayoutParams ep = new LinearLayout.LayoutParams(raw48, raw48);
      ep.rightMargin = (idx < shortEmojis.length - 1) ? dp(2) : 0;
      emojis.addView(t, ep);
      UiMetrics.enforceMinTouchTarget(t, 48);
    }
    emojiScroll.addView(emojis);
    sheet.addView(emojiScroll);
    final TextView replying = label("", 12, MUTED);
    replying.setPadding(dp(16), 0, dp(16), 0);
    replying.setVisibility(View.GONE);
    sheet.addView(replying);
    LinearLayout bar = row();
    bar.setGravity(Gravity.CENTER_VERTICAL);
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
    LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(0, Math.max(dp(42), raw48), 1);
    ip.setMargins(dp(10), 0, dp(8), 0);
    bar.addView(input, ip);
    UiMetrics.enforceMinTouchTarget(input, 48);
    FrameLayout send = new FrameLayout(this);
    send.setBackground(background(ACCENT, 999));
    send.addView(icon("send", 18, WHITE), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    send.setContentDescription(I18n.t("Gửi bình luận"));
    bar.addView(send, new LinearLayout.LayoutParams(Math.max(dp(42), raw48), Math.max(dp(42), raw48)));
    sheet.addView(bar);
    final String[] parent = { null };
    final Runnable[] load = new Runnable[1];
    load[0] = () -> cachedRequest(base, d -> {
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
        if (c == null || (!c.isNull("parentId") && !c.optString("parentId").isEmpty()))
          continue;
        list.addView(reelComment(c, false, base, load[0], () -> {
          parent[0] = c.optString("id");
          JSONObject ca = c.optJSONObject("author");
          replying
              .setText(I18n.t("Đang trả lời ") + (ca == null ? "" : ca.optString("name")) + I18n.t(" · chạm để huỷ"));
          replying.setVisibility(View.VISIBLE);
          input.requestFocus();
        }));
        final List<JSONObject> kids = new ArrayList<>();
        for (int k = 0; k < n; k++) {
          JSONObject ko = all.optJSONObject(k);
          if (ko != null && ko.optString("parentId").equals(c.optString("id")))
            kids.add(ko);
        }
        if (kids.isEmpty())
          continue;
        final LinearLayout box = column();
        box.setPadding(dp(44), 0, 0, 0);
        box.setVisibility(View.GONE);
        for (final JSONObject k : kids)
          box.addView(reelComment(k, true, base, load[0], () -> {
            parent[0] = c.optString("id");
            JSONObject ka = k.optJSONObject("author");
            replying
                .setText(I18n.t("Đang trả lời ") + (ka == null ? "" : ka.optString("name")) + I18n.t(" · chạm để huỷ"));
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
        UiMetrics.enforceMinTouchTarget(more, 48);
      }
    }, () -> {
    });
    replying.setOnClickListener(v -> {
      parent[0] = null;
      replying.setVisibility(View.GONE);
    });
    send.setOnClickListener(v -> {
      String text = input.getText().toString().trim();
      if (text.isEmpty())
        return;
      JSONObject payload = json("body", text);
      if (parent[0] != null)
        try {
          payload.put("parentId", parent[0]);
        } catch (JSONException ignored) {
        }
      submitText(input, send, base, payload, x -> {
        if (input.length() == 0) {
          parent[0] = null;
          replying.setVisibility(View.GONE);
        }
        load[0].run();
      });
    });
    dialog.setContentView(sheet);
    Window w = dialog.getWindow();
    if (w != null) {
      w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(0));
      w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT,
          Math.round(getResources().getDisplayMetrics().heightPixels * 0.62f));
      ApprovedTypography.sheet(w.getDecorView());
      w.setGravity(Gravity.BOTTOM);
      w.setDimAmount(0.25f);
      w.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    }
    dialog.setOnDismissListener(
        x -> request("GET", shortsFollowing ? "/api/shorts?feed=following" : "/api/shorts", null, res -> {
          if (res.optJSONArray("shorts") != null)
            shortRows = orderedShorts(res.optJSONArray("shorts"));
        }));
    dialog.show();
    load[0].run();
  }

  private LinearLayout reelComment(final JSONObject c, boolean reply, final String base, final Runnable reload,
      final Runnable onReply) {
    LinearLayout r = row();
    r.setGravity(Gravity.TOP);
    r.setPadding(0, dp(8), 0, dp(8));
    avatar(c.optJSONObject("author"), r, reply ? 26 : 34);
    LinearLayout body = column();
    body.setPadding(dp(10), 0, dp(6), 0);
    JSONObject ra = c.optJSONObject("author");
    TextView name = label(ra == null ? "" : ra.optString("name"), 13, MUTED);
    name.setTypeface(null, Typeface.BOLD);
    name.setPadding(0, 0, 0, 0);
    body.addView(name);
    TextView text = label(c.optString("body"), 15, TEXT);
    text.setPadding(0, dp(2), 0, dp(4));
    body.addView(text);
    LinearLayout meta = row();
    meta.setGravity(Gravity.CENTER_VERTICAL);
    meta.addView(label(ago(c.optLong("created")), 12, MUTED));
    TextView rep = label(I18n.t("Trả lời"), 12, MUTED);
    rep.setTypeface(null, Typeface.BOLD);
    rep.setGravity(Gravity.CENTER);
    rep.setPadding(dp(12), dp(8), dp(12), dp(8));
    rep.setOnClickListener(v -> onReply.run());
    meta.addView(rep);
    UiMetrics.enforceMinTouchTarget(rep, 48);
    body.addView(meta);
    r.addView(body, new LinearLayout.LayoutParams(0, -2, 1));
    int total = 0;
    JSONObject counts = c.optJSONObject("reactions");
    if (counts != null)
      for (String[] x : REACTIONS)
        total += counts.optInt(x[0]);
    final boolean liked = !c.isNull("myReaction") && !c.optString("myReaction").isEmpty();
    LinearLayout like = column();
    like.setGravity(Gravity.CENTER);
    like.addView(icon("heart", 18, liked ? 0xfffe2c55 : MUTED), new LinearLayout.LayoutParams(dp(18), dp(18)));
    TextView count = label(total > 0 ? String.valueOf(total) : "", 11, liked ? 0xfffe2c55 : MUTED);
    count.setPadding(0, dp(2), 0, 0);
    count.setGravity(Gravity.CENTER);
    like.addView(count);
    like.setContentDescription(liked ? I18n.t("Bỏ thích bình luận") : I18n.t("Thích bình luận"));
    like.setOnClickListener(v -> request("POST", base + "/" + c.optString("id") + "/reaction",
        json("reaction", liked ? JSONObject.NULL : "love"), x -> reload.run()));
    r.setOnLongClickListener(v -> {
      commentOptions(c, base, reload);
      return true;
    });
    r.addView(like, new LinearLayout.LayoutParams(Math.max(dp(36), UiMetrics.dpRaw(this, 48)), -2));
    UiMetrics.enforceMinTouchTarget(like, 48);
    return r;
  }

  private void openCreateMenu() {
    if (me == null) {
      auth(false);
      return;
    }
    startActivityForResult(new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "photo"), 203);
  }

  private void chooseVideo() {
    if (postingVideo) {
      say(I18n.t("Đang tải video, vui lòng chờ."));
      return;
    }
    pickFile(216, "video/*");
  }

  private void captureVideo() {
    Intent capture = new Intent(
        android.provider.MediaStore.ACTION_VIDEO_CAPTURE);
    capture.putExtra(android.provider.MediaStore.EXTRA_DURATION_LIMIT, 60);
    capture.putExtra(android.provider.MediaStore.EXTRA_VIDEO_QUALITY, 0);
    try {
      startActivityForResult(capture, 201);
    } catch (Exception e) {
      say(I18n.t("Không mở được camera quay video."));
    }
  }

  private void reviewMedia(android.net.Uri uri, int requestCode) {
    Intent editor = new Intent(this, MediaEditActivity.class).setData(uri);
    editor.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    editor.setClipData(android.content.ClipData.newRawUri("media", uri));
    startActivityForResult(editor, requestCode);
  }

  private android.app.Dialog uploadVideo(android.net.Uri uri) {
    LinearLayout view = column();
    VideoView preview = new VideoView(this);
    preview.setVideoURI(uri);
    preview.setOnPreparedListener(player -> {
      player.setLooping(true);
      player.setVolume(0, 0);
      preview.start();
    });
    FrameLayout previewBox = new FrameLayout(this);
    previewBox.setBackground(background(0xff100d19, 14));
    previewBox.setClipToOutline(true);
    previewBox.addView(preview, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
    view.addView(previewBox, new LinearLayout.LayoutParams(-1, dp(200)));
    TextView hint = label(I18n.t("Studio Pro để chỉnh sửa · Tiếp tục để đăng cơ bản"), 12, MUTED);
    hint.setGravity(Gravity.CENTER);
    hint.setPadding(0, dp(10), 0, 0);
    view.addView(hint);
    android.app.Dialog choice = new Sheet(this).setTitle(I18n.t("Hoàn thiện video")).setView(view)
        .setPositiveButton("Studio Pro", (dialog, which) -> reviewMedia(uri, 212))
        .setNegativeButton(I18n.t("Tiếp tục"), (dialog, which) -> uploadVideoNow(uri)).show();
    choice.setOnDismissListener(dialog -> preview.stopPlayback());
    return choice;
  }

  private android.app.Dialog uploadVideoNow(android.net.Uri uri) {
    EditText caption = new KinnectInput(this);
    caption.setHint(I18n.t("Viết chú thích cho video"));
    LinearLayout captionBox = column();
    captionBox.setPadding(0, dp(8), 0, dp(4));
    captionBox.addView(caption);
    return new Sheet(this)
        .setTitle(I18n.t("Đăng video"))
        .setView(captionBox)
        .setPositiveButton(I18n.t("Đăng"), (dialog, which) -> {
          postingVideo = true;
          say(I18n.t("Đang đọc và tải video…"));
          final int generation = screen;
          String text = caption.getText().toString();
          new Thread(() -> {
            try {
              NativeMedia.Prepared selected = NativeMedia.read(this, uri, true);
              final JSONObject payload = json(
                  "data",
                  selected.dataUrl(),
                  "caption",
                  text);
              runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || generation != screen) {
                  postingVideo = false;
                  return;
                }
                request("POST", "/api/shorts", payload, result -> {
                  navigate("shorts");
                  say(I18n.t("Đã đăng video."));
                }, () -> postingVideo = false);
              });
            } catch (OutOfMemoryError e) {
              runOnUiThread(() -> {
                postingVideo = false;
                if (generation == screen)
                  say(I18n.t("Thiết bị không đủ bộ nhớ để chuẩn bị video này."));
              });
            } catch (Exception e) {
              final String reason = mediaFailure(e);
              runOnUiThread(() -> {
                postingVideo = false;
                if (generation == screen)
                  say(reason);
              });
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
    if (request == 319) {
      if (result == RESULT_OK && data != null && data.getData() != null && photoGroup != null) {
        final JSONObject g = photoGroup;
        final android.net.Uri uri = data.getData();
        final int generation = screen;
        say(I18n.t("Đang chuẩn bị ảnh nhóm…"));
        new Thread(() -> {
          try {
            final CompressedImage img = compressImageForUpload(uri, 1080, 920 * 1024);
            runOnUiThread(() -> {
              if (isFinishing() || isDestroyed() || generation != screen)
                return;
              request("POST", "/api/groups/" + g.optString("id") + "/avatar", json("data", img.dataUrl),
                  d -> groupChat(d.optJSONObject("group")));
            });
          } catch (Exception | OutOfMemoryError error) {
            runOnUiThread(() -> {
              if (!isDestroyed())
                say(I18n.t("Chọn ảnh PNG/JPEG/WebP nhỏ hơn 1 MB."));
            });
          }
        }, "kinnect-group-avatar").start();
      }
      photoGroup = null;
      return;
    }

    if (request == 701 && result == RESULT_OK && data != null && data.getData() != null) {
      startActivity(new Intent(this, PhotoEditActivity.class).setData(data.getData())
          .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION));
      return;
    }
    if (request == 700 && result == RESULT_OK && data != null && data.getData() != null) {
      startActivity(new Intent(this, MediaEditActivity.class).setData(data.getData())
          .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION).putExtra("store_pro", true));
      return;
    }

    if (result == RESULT_OK && data != null && data.getData() != null) {
      try {
        getContentResolver().takePersistableUriPermission(data.getData(),
            data.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION);
      } catch (SecurityException ignored) {
      }
    }

    if (request == 216) {
      if (result == RESULT_OK && data != null && data.getData() != null) {
        Intent studio = new Intent(this, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "video")
            .putExtra("review_video", data.getData().toString()).setData(data.getData())
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        studio.setClipData(android.content.ClipData.newRawUri("video", data.getData()));
        startActivityForResult(studio, 203);
      }
      return;
    }
    if (request == 215) {
      if (result == RESULT_OK && data != null && data.getData() != null)
        reviewMedia(data.getData(), 212);
      return;
    }
    if (request == 213) {
      if (result == RESULT_OK && data != null && data.getData() != null) {
        android.net.Uri uri = data.getData();
        Intent editor = new Intent(this, PhotoEditActivity.class).setData(uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        editor.setClipData(android.content.ClipData.newRawUri("photo", uri));
        startActivityForResult(editor, 214);
      }
      return;
    }
    if (request == 214) {
      if (result == RESULT_OK && data != null && data.getData() != null) {
        composePost();
        preparePostMedia(300, data.getData());
      }
      return;
    }
    if (request >= 210 && request <= 212) {
      if (result == RESULT_OK && data != null && data.getData() != null) {
        if (request == 212)
          uploadVideoNow(data.getData());
        else
          preparePostMedia(request == 211 ? 304 : 300, data.getData());
      }
      return;
    }
    if (request == 309) {
      final String path = pendingDownload;
      pendingDownload = "";
      if (result != RESULT_OK || data == null || data.getData() == null || path.isEmpty())
        return;
      final android.net.Uri destination = data.getData();
      api.image(path, bytes -> {
        if (bytes == null) {
          say(I18n.t("Chưa tải được tệp. Vui lòng thử lại."));
          return;
        }
        new Thread(() -> {
          boolean saved = false;
          try (java.io.OutputStream out = getContentResolver().openOutputStream(destination)) {
            if (out != null) {
              out.write(bytes);
              saved = true;
            }
          } catch (Exception error) {
          }
          final boolean success = saved;
          runOnUiThread(() -> say(success ? I18n.t("Đã lưu tệp.") : I18n.t("Không lưu được tệp.")));
        }, "kinnect-download").start();
      });
      return;
    }
    if ((request == 203 || request == 204) && result == RESULT_OK && data != null
        && data.getStringExtra(StudioActivity.EXTRA_IMAGE) != null) {
      final java.io.File file = new java.io.File(data.getStringExtra(StudioActivity.EXTRA_IMAGE));
      final String action = data.getStringExtra(StudioActivity.EXTRA_ACTION);
      if ("story".equals(action))
        reviewMedia(android.net.Uri.fromFile(file), 211);
      else {
        composePost();
        if (data.getBooleanExtra("photoProEdited", false))
          preparePostMedia(300, android.net.Uri.fromFile(file));
        else
          reviewMedia(android.net.Uri.fromFile(file), 210);
      }
      return;
    }
    if ((request == 203 || request == 204) && result == RESULT_FIRST_USER && data != null && data.getData() != null) {
      if (request == 204)
        reviewMedia(data.getData(), 211);
      else
        uploadVideoNow(data.getData());
      return;
    }
    if ((request == 203 || request == 204) && result == RESULT_OK && data != null
        && data.getBooleanExtra(StudioActivity.EXTRA_STORY, false)) {
      reviewMedia(android.net.Uri.fromFile(new java.io.File(data.getStringExtra(StudioActivity.EXTRA_VIDEO))), 211);
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
    if (request == 204 && result == RESULT_FIRST_USER) {
      pickFile(304, "image/*|video/*");
      return;
    }
    if (request == 203 && result == RESULT_OK && data != null
        && data.getStringExtra(StudioActivity.EXTRA_VIDEO) != null) {
      uploadVideoNow(android.net.Uri.fromFile(new java.io.File(data.getStringExtra(StudioActivity.EXTRA_VIDEO))));
      return;
    }
    if (request == 203 && result == RESULT_FIRST_USER) {
      Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
      pick.addCategory(Intent.CATEGORY_OPENABLE);
      pick.setType("video/*");
      try {
        startActivityForResult(pick, 200);
      } catch (Exception e) {
        say(I18n.t("Không mở được trình chọn video."));
      }
      return;
    }
    if ((request >= 300 && request <= 306) || request == 308) {
      if (result == RESULT_OK && data != null && data.getData() != null)
        picked(request, data.getData());
      return;
    }
    if ((request == 200 || request == 201) &&
        result == RESULT_OK &&
        data != null &&
        data.getData() != null) {
      uploadVideoNow(data.getData());
      return;
    }
    if (request == 100 &&
        result == RESULT_OK &&
        data != null &&
        data.getData() != null) {
      final android.net.Uri uri = data.getData();
      String type = getContentResolver().getType(uri);
      if (type != null && !type.startsWith("image/")) {
        say(I18n.t("Chọn ảnh PNG/JPEG/WebP."));
        return;
      }
      final int generation = screen;
      avatarUploadInFlight = true;
      say(I18n.t("Đang chuẩn bị ảnh đại diện…"));
      new Thread(() -> {
        try {
          final CompressedImage compressed = compressImageForUpload(uri, 1080, 920 * 1024);
          runOnUiThread(() -> {
            if (isFinishing() || isDestroyed() || generation != screen) {
              avatarUploadInFlight = false;
              return;
            }
            request(
                "POST",
                "/api/me/avatar",
                json("data", compressed.dataUrl),
                d -> {
                  JSONObject updated = d.optJSONObject("user");
                  if (updated == null) {
                    say(I18n.t("Không tải được hồ sơ mới. Vui lòng thử lại."));
                    return;
                  }
                  lastAvatarMutationAt = System.currentTimeMillis();
                  applyUpdatedAvatar(updated, compressed.bytes);
                  if (profileEditorAvatar == null || !profileEditorAvatar.isAttachedToWindow())
                    navigate("profile");
                  say(I18n.t("Đã đổi ảnh đại diện"));
                },
                () -> avatarUploadInFlight = false);
          });
        } catch (Exception | OutOfMemoryError e) {
          runOnUiThread(() -> {
            avatarUploadInFlight = false;
            if (!isDestroyed())
              say(I18n.t("Chọn ảnh nhỏ hơn 1 MB."));
          });
        }
      }, "kinnect-avatar-upload").start();
    }
  }

  private void stopLocation() {
    if (locationListener != null) {
      try {
        ((LocationManager) getSystemService(LOCATION_SERVICE)).removeUpdates(
            locationListener);
      } catch (SecurityException ignored) {
      }
      locationListener = null;
    }
  }

  private boolean silentLocate = false;

  private void requestLocation() {
    if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
      locate();
      return;
    }
    new Sheet(this)
        .setTitle(I18n.t("Tìm thành viên xung quanh"))
        .setMessage(
            I18n.t(
                "Chỉ dùng vị trí gần đúng, lưu theo ô khoảng 5 km trong tối đa 24 giờ hiệu lực; không công khai tọa độ. Bạn có thể tắt và xóa ở Hồ sơ."))
        .setPositiveButton(I18n.t("Đồng ý"), (d, w) -> {
          if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(
                new String[] { Manifest.permission.ACCESS_COARSE_LOCATION },
                101);
          else
            locate();
        })
        .setNegativeButton(I18n.t("Hủy"), null)
        .show();
  }

  // Lấy vị trí: dùng vị trí gần nhất trong 30 phút, nếu không có thì hỏi đồng
  // thời mạng / GPS / fused,
  // nguồn nào trả về trước thì dùng. Máy chủ chỉ lưu ô ~5 km, không lưu toạ độ
  // chính xác.
  private void locate() {
    try {
      final LocationManager manager = (LocationManager) getSystemService(LOCATION_SERVICE);
      Location best = null;
      for (String name : manager.getProviders(true)) {
        Location last = manager.getLastKnownLocation(name);
        if (last != null && System.currentTimeMillis() - last.getTime() < 1800000
            && (best == null || last.getTime() > best.getTime()))
          best = last;
      }
      if (best != null) {
        sendLocation(best);
        return;
      }
      List<String> sources = new ArrayList<>();
      for (String name : new String[] { "fused", LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER })
        if (manager.getAllProviders().contains(name) && manager.isProviderEnabled(name))
          sources.add(name);
      if (sources.isEmpty()) {
        if (!silentLocate)
          say(I18n.t("Hãy bật Vị trí trên điện thoại rồi thử lại."));
        silentLocate = false;
        return;
      }
      stopLocation();
      locationListener = new LocationListener() {
        public void onLocationChanged(Location value) {
          if (locationListener != this)
            return;
          manager.removeUpdates(this);
          locationListener = null;
          sendLocation(value);
        }

        public void onProviderEnabled(String p) {
        }

        public void onProviderDisabled(String p) {
        }

        public void onStatusChanged(String p, int s, Bundle b) {
        }
      };
      for (String name : sources) {
        try {
          manager.requestLocationUpdates(name, 0, 0, locationListener, Looper.getMainLooper());
        } catch (Exception ignored) {
        }
      }
      if (!silentLocate)
        say(I18n.t("Đang lấy vị trí gần đúng…"));
      final LocationListener waiting = locationListener;
      handler.postDelayed(() -> {
        if (locationListener == waiting && waiting != null) {
          manager.removeUpdates(waiting);
          locationListener = null;
          if (!silentLocate)
            say(I18n.t("Chưa lấy được vị trí. Hãy ra chỗ thoáng hoặc bật Wi‑Fi rồi thử lại."));
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
            location.getLongitude()),
        d -> {
          boolean had = me != null && me.optBoolean("hasLocation");
          me = d.optJSONObject("user");
          boolean quiet = silentLocate;
          silentLocate = false;
          if (!quiet || (!had && tab.equals("discover") && onTabRoot))
            refreshPeopleSearch();
          else
            say("");
        });
  }

  private Runnable groupCallPermissionTask;

  @Override
  public void onRequestPermissionsResult(
      int code,
      String[] permissions,
      int[] results) {
    super.onRequestPermissionsResult(code, permissions, results);
    if (code == 901) {
      if (calls != null)
        calls.permissionsResult(results);
      return;
    }
    if (code == 902) {
      Runnable task = groupCallPermissionTask;
      groupCallPermissionTask = null;
      for (int r : results)
        if (r != PackageManager.PERMISSION_GRANTED) {
          say(I18n.t("Cần cấp quyền micro/camera để tham gia cuộc gọi nhóm."));
          return;
        }
      if (results.length > 0 && task != null)
        task.run();
      return;
    }
    if (code == 950) {
      backgroundExtras(true);
      return;
    }
    if (code == 102) {
      if (results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED)
        captureVideo();
      else
        say(I18n.t("Cần quyền camera để quay video."));
      return;
    }
    if (code == 101 &&
        results.length > 0 &&
        results[0] == PackageManager.PERMISSION_GRANTED)
      locate();
    else if (code == 101)
      say(
          I18n.t("Bạn vẫn có thể tìm bạn theo sở thích khi không cấp vị trí."));
  }

  @Override
  protected void onUserLeaveHint() {
    super.onUserLeaveHint();
    if (calls != null)
      calls.enterPip();
  }

  @Override
  public void onPictureInPictureModeChanged(boolean pip, android.content.res.Configuration config) {
    super.onPictureInPictureModeChanged(pip, config);
    if (!pip && calls != null)
      calls.restorePip();
  }

  private boolean leftForeground = false;
  private boolean avatarUploadInFlight = false;
  private long lastAvatarMutationAt = 0;

  private void stopAdminPlayer() {
    if (adminPlayer != null) {
      try {
        if (adminPlayer.isPlaying())
          adminPlayer.stop();
      } catch (Exception ignored) {
      }
      try {
        adminPlayer.release();
      } catch (Exception ignored) {
      }
      adminPlayer = null;
    }
  }

  @Override
  protected void onStop() {
    super.onStop();
    leftForeground = true;
    KinnectService.appVisible = false;

    stopAdminPlayer();
    if (shortVideo != null)
      shortVideo.pause();
    resumeVideos.clear();
    for (VideoView video : mediaVideos)
      if (video.isPlaying()) {
        resumeVideos.add(video);
        video.pause();
      }
    stopped = true;
    notificationHandler.removeCallbacksAndMessages(null);
    handler.removeCallbacksAndMessages(null);
    if (locationListener != null) {
      try {
        ((LocationManager) getSystemService(LOCATION_SERVICE)).removeUpdates(
            locationListener);
      } catch (SecurityException ignored) {
      }
      locationListener = null;
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    stopped = false;
    boolean shouldSyncMe = (storeReturning || leftForeground) && me != null && !NativeApi.isFixtureEnabled();
    leftForeground = false;
    if (shouldSyncMe) {
      storeReturning = false;
      final long resumeEpoch = avatarRevision;
      api.call("GET", "/api/me", null, (data, error, status) -> {
        if (error == null && data != null && !isDestroyed() && me != null) {
          if (avatarUploadInFlight || resumeEpoch != avatarRevision
              || System.currentTimeMillis() - lastAvatarMutationAt < 5000)
            return;
          JSONObject fresh = data.optJSONObject("user");
          boolean styleChanged = fresh != null && !fresh.optString("storeStyle").equals(me.optString("storeStyle"));
          boolean avatarChanged = fresh != null && !fresh.optString("avatar", "").equals(me.optString("avatar", ""));
          if (avatarChanged)
            applyUpdatedAvatar(fresh, null);
          else if (fresh != null)
            me = fresh;
          if (styleChanged)
            refreshPage();
        }
      });
    }
    KinnectService.appVisible = true;
    if (!NativeApi.isFixtureEnabled()) {
      notificationHandler.removeCallbacksAndMessages(null);
      notificationHandler.post(notificationPoll);
      ensureCalls();
      if (calls != null) {
        calls.checkPending();
        if (root != null)
          calls.attachReturn(root);
      }
    }
    for (VideoView video : resumeVideos)
      if (video.isAttachedToWindow())
        if (!mediaCallBlocked)
          video.start();
    resumeVideos.clear();
    if (resumeStory != null)
      resumeStory.run();
    if (poll != null) {
      handler.removeCallbacks(poll);
      handler.postDelayed(poll, 4000);
    }
  }

  @Override
  protected void onDestroy() {
    closeStoreUi();
    stopAdminPlayer();
    clearRetainedFeed();
    if (groupPollsDialog != null && groupPollsDialog.isShowing()) {
      try {
        groupPollsDialog.dismiss();
      } catch (Exception ignored) {
      }
      groupPollsDialog = null;
    }
    if (groupCallDialog != null && groupCallDialog.isShowing()) {
      try {
        groupCallDialog.dismiss();
      } catch (Exception ignored) {
      }
      groupCallDialog = null;
    }
    handler.removeCallbacksAndMessages(null);
    notificationHandler.removeCallbacksAndMessages(null);
    previewLoader.shutdownNow();
    if (mediaCallListening)
      KinnectService.unlisten(mediaCallEvents);
    startupHandler.removeCallbacksAndMessages(null);
    if (splashAnimator != null)
      splashAnimator.cancel();
    for (VideoView video : mediaVideos) {
      try {
        video.stopPlayback();
      } catch (RuntimeException ignored) {
      }
    }
    mediaVideos.clear();
    resumeVideos.clear();
    stopShort();
    if (calls != null) {
      calls.close();
      calls = null;
    }
    super.onDestroy();
  }

  private final ArrayDeque<Runnable> history = new ArrayDeque<>();
  private boolean goingBack;
  private Runnable subBack;

  // Ghi nhớ màn đang mở để nút Back quay về đúng màn trước.
  private String currentKey = "";
  private int navBack = 0;

  private void remember(String key, Runnable page) {
    if (!goingBack && currentPage != null && !key.equals(currentKey)) {
      history.push(currentPage);
      while (history.size() > 30)
        history.removeLast();
    }
    goingBack = false;
    currentKey = key;
    currentPage = page;
    subBack = null;
  }

  @Override
  public void onBackPressed() {
    handleBack();
  }

  private void handleBack() {
    if (subBack != null) {
      navBack = 1;
      Runnable r = subBack;
      subBack = null;
      r.run();
      return;
    }
    if (me != null && !history.isEmpty()) {
      navBack = 1;
      goingBack = true;
      Runnable previous = history.pop();
      previous.run();
      goingBack = false;
      return;
    }
    if (me != null && (!onTabRoot || !tab.equals("feed"))) {
      navBack = 1;
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
  private static final String[][] REACTIONS = { { "like", "👍" }, { "love", "❤️" }, { "haha", "😆" }, { "wow", "😮" },
      { "sad", "😢" }, { "angry", "😡" } };

  private interface ReactionPick {
    void pick(int index);
  }

  // Thanh cảm xúc kiểu Facebook: viên nổi phía trên nút, biểu tượng lớn bật lên
  // lần lượt.
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
    int raw48 = UiMetrics.dpRaw(this, 48);
    for (int i = 0; i < REACTIONS.length; i++) {
      final int index = i;
      ImageView e = new ImageView(this);
      String[] artwork = { "1f44d", "2764", "1f602", "1f62e", "1f622", "1f621" };
      int resource = getResources().getIdentifier("emoji_noto_" + artwork[i], "drawable", getPackageName());
      e.setImageResource(resource);
      e.setScaleType(ImageView.ScaleType.FIT_CENTER);
      e.setPadding(dp(7), dp(8), dp(7), dp(8));
      e.setContentDescription(
          new String[] { I18n.t("Thích"), I18n.t("Yêu thích"), "Haha", "Wow", I18n.t("Buồn"), I18n.t("Phẫn nộ") }[i]);
      e.setScaleX(.85f);
      e.setScaleY(.85f);
      e.post(() -> e.animate().scaleX(1f).scaleY(1f).setStartDelay(30L * index).setDuration(180)
          .setInterpolator(new android.view.animation.OvershootInterpolator(2.2f)).start());
      e.setOnTouchListener((v, ev) -> {
        if (ev.getActionMasked() == MotionEvent.ACTION_DOWN)
          v.animate().scaleX(1.35f).scaleY(1.35f).translationY(-dp(8)).setDuration(120).start();
        if (ev.getActionMasked() == MotionEvent.ACTION_CANCEL)
          v.animate().scaleX(1f).scaleY(1f).translationY(0).setDuration(120).start();
        return false;
      });
      e.setOnClickListener(v -> {
        popup.dismiss();
        pick.pick(index);
      });
      bar.addView(e, new LinearLayout.LayoutParams(raw48, raw48));
      UiMetrics.enforceMinTouchTarget(e, 48);
    }
    bar.measure(View.MeasureSpec.UNSPECIFIED, View.MeasureSpec.UNSPECIFIED);
    View host = anchor != null && anchor.isAttachedToWindow() ? anchor : root;
    int[] at = new int[2];
    host.getLocationInWindow(at);
    int width = bar.getMeasuredWidth(), screen = getResources().getDisplayMetrics().widthPixels;
    int x = anchor == null ? (screen - width) / 2 : Math.max(dp(8), Math.min(screen - width - dp(8), at[0]));
    int y = anchor == null ? getResources().getDisplayMetrics().heightPixels / 2
        : Math.max(dp(40), at[1] - bar.getMeasuredHeight() - dp(8));
    popup.showAtLocation(root, Gravity.TOP | Gravity.START, x, y);
    try {
      if (anchor != null)
        anchor.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS);
    } catch (Exception ignored) {
    }
  }

  private Button chip(String text, boolean active, Runnable action) {
    Button b = new KinnectButton(this);
    b.setText(text);
    b.setAllCaps(false);
    b.setTextSize(13);
    b.setTextColor(active ? ACCENT_TEXT : TEXT);
    b.setTypeface(Typeface.create(active ? "sans-serif-medium" : "sans-serif", Typeface.NORMAL));
    b.setStateListAnimator(null);
    android.graphics.drawable.Drawable chipBg = pressable(active ? PRIMARY_SOFT : CARD, 999);
    if (!active && chipBg instanceof android.graphics.drawable.RippleDrawable)
      ((GradientDrawable) ((android.graphics.drawable.RippleDrawable) chipBg).getDrawable(0)).setStroke(1, LINE);
    b.setBackground(chipBg);
    b.setPadding(dp(14), 0, dp(14), 0);
    b.setMinWidth(0);
    b.setMinimumWidth(UiMetrics.dpRaw(this, 48));
    b.setMinHeight(UiMetrics.dpRaw(this, 48));
    b.setMinimumHeight(UiMetrics.dpRaw(this, 48));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, Math.max(dp(38), UiMetrics.dpRaw(this, 48)));
    p.setMargins(0, dp(4), dp(8), dp(4));
    b.setLayoutParams(p);
    b.setOnClickListener(v -> action.run());
    UiMetrics.enforceMinTouchTarget(b, 48);
    return b;
  }

  private String ago(long time) {
    if (time <= 0)
      return "v\u1eeba xong";
    long s = Math.max(0, (System.currentTimeMillis() - time) / 1000);
    if (s < 60)
      return "vừa xong";
    if (s < 3600)
      return (s / 60) + " phút";
    if (s < 86400)
      return (s / 3600) + " giờ";
    if (s < 7 * 86400)
      return (s / 86400) + " ngày";
    return new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()).format(new Date(time));
  }

  private String noticeText(String kind) {
    if (kind.equals("follow"))
      return " đã theo dõi bạn";
    if (kind.equals("friend_request"))
      return " đã gửi lời mời kết bạn";
    if (kind.equals("friend_accept") || kind.equals("friend_accepted"))
      return " đã chấp nhận lời mời kết bạn";
    if (kind.equals("comment_reply"))
      return " đã trả lời bình luận của bạn";
    if (kind.equals("missed_call"))
      return " đã gọi nhỡ cho bạn";
    if (kind.equals("like"))
      return " đã bày tỏ cảm xúc về bài viết của bạn";
    if (kind.equals("comment"))
      return " đã bình luận bài viết của bạn";
    if (kind.equals("gift"))
      return " đã gửi quà miễn phí";
    if (kind.equals("private_request"))
      return " đã yêu cầu xem ảnh riêng tư";
    if (kind.equals("private_granted"))
      return " đã cấp quyền xem ảnh riêng tư";
    if (kind.equals("private_revoked"))
      return " đã thu hồi quyền xem ảnh riêng tư";
    if (kind.equals("group_message"))
      return " đã nhắn trong nhóm";
    if (kind.equals("short_like"))
      return " đã thích video của bạn";
    if (kind.equals("short_comment"))
      return " đã bình luận video của bạn";
    return " đã gửi tin nhắn";
  }

  // ----- Màn giới thiệu (hiện mỗi lần mở app khi chưa đăng nhập)
  private int introPage = 0;

  private TextView welcomeText(String text, int size, int color, boolean bold) {
    TextView v = label(text, size, color);
    v.setPadding(0, 0, 0, 0);
    v.setLineSpacing(dp(3), 1f);
    if (bold)
      v.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    return v;
  }

  private LinearLayout welcomeBrand() {
    LinearLayout brand = row();
    brand.setBaselineAligned(false);
    brand.setGravity(Gravity.CENTER_VERTICAL);
    ImageView logo = new ImageView(this);
    logo.setImageResource(getResources().getIdentifier("kinnect_logo", "drawable", getPackageName()));
    logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
    final float iconRadius = dp(8);
    logo.setOutlineProvider(new android.view.ViewOutlineProvider() {
      @Override
      public void getOutline(View view, android.graphics.Outline outline) {
        outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), iconRadius);
      }
    });
    logo.setClipToOutline(true);
    brand.addView(logo, new LinearLayout.LayoutParams(dp(34), dp(34)));
    TextView name = welcomeText("Kinnect", 20, ACCENT_TEXT, true);
    name.setPadding(dp(9), 0, 0, 0);
    name.setSingleLine(true);
    brand.addView(name, new LinearLayout.LayoutParams(-2, -2));
    brand.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    return brand;
  }

  private void welcomeFeature(String glyph, String title, String description, int color) {
    LinearLayout panel = column();
    panel.setPadding(dp(18), dp(19), dp(18), dp(19));
    panel.setBackground(outlined(CARD, 20));
    LinearLayout line = row();
    FrameLayout bubble = new FrameLayout(this);
    bubble.setBackground(background((color & 0x00ffffff) | 0x18000000, 14));
    bubble.addView(icon(glyph, 23, color), new FrameLayout.LayoutParams(dp(23), dp(23), Gravity.CENTER));
    line.addView(bubble, new LinearLayout.LayoutParams(dp(46), dp(46)));
    LinearLayout words = column();
    words.setPadding(dp(13), 0, 0, 0);
    words.addView(welcomeText(title, 17, TEXT, true));
    TextView detail = welcomeText(description, 14, MUTED, false);
    detail.setPadding(0, dp(6), 0, 0);
    words.addView(detail);
    line.addView(words, new LinearLayout.LayoutParams(0, -2, 1));
    panel.addView(line);
    LinearLayout.LayoutParams space = new LinearLayout.LayoutParams(-1, -2);
    space.topMargin = dp(10);
    content.addView(panel, space);
  }

  private String installedVersionBuild() {
    try {
      android.content.pm.PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
      long code = Build.VERSION.SDK_INT >= 28 ? info.getLongVersionCode() : info.versionCode;
      return "Kinnect Android v" + info.versionName + " (Build " + code + ")";
    } catch (android.content.pm.PackageManager.NameNotFoundException error) {
      return "Kinnect Android";
    }
  }

  private void intro() {
    shell("", false);
    root.removeAllViews();
    root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { SOFT, BG, BG }));
    getWindow().setStatusBarColor(SOFT);
    getWindow().setNavigationBarColor(BG);
    content = column();
    content.setPadding(dp(22), dp(12), dp(22), dp(10));
    root.addView(content, new LinearLayout.LayoutParams(-1, -1));

    LinearLayout brand = welcomeBrand();
    int raw48 = UiMetrics.dpRaw(this, 48);
    TextView language = welcomeText("VI / EN", 13, TEXT, true);
    language.setPadding(dp(10), 0, dp(10), 0);
    language.setGravity(Gravity.CENTER);
    language.setSingleLine(true);
    language.setIncludeFontPadding(false);
    language.setMinWidth(dp(56));
    language.setBackground(pressable(0x00000000, 10));
    language.setContentDescription(I18n.t("Ngôn ngữ ứng dụng"));
    language.setOnClickListener(v -> languageMenu());
    brand.addView(language, new LinearLayout.LayoutParams(-2, Math.max(dp(40), raw48)));
    UiMetrics.enforceMinTouchTarget(language, 48);

    View spacer = new View(this);
    brand.addView(spacer, new LinearLayout.LayoutParams(dp(6), 1));

    TextView login = welcomeText(I18n.t("Đăng nhập"), 14, WHITE, true);
    login.setGravity(Gravity.CENTER);
    login.setPadding(dp(16), 0, dp(16), 0);
    login.setSingleLine(true);
    login.setIncludeFontPadding(false);
    login.setBackground(pressable(ACCENT, 12));
    login.setOnClickListener(v -> auth(false));
    brand.addView(login, new LinearLayout.LayoutParams(-2, Math.max(dp(40), raw48)));
    UiMetrics.enforceMinTouchTarget(login, 48);
    content.addView(brand, new LinearLayout.LayoutParams(-1, Math.max(dp(44), raw48)));

    TextView headline = welcomeText(I18n.t("Kết nối đúng gu.\nSống đúng mình."), 28, TEXT, true);
    headline.setGravity(Gravity.CENTER);
    headline.setPadding(0, dp(14), 0, dp(6));
    headline.setLineSpacing(dp(2), 1f);
    headline.setMaxLines(2);
    headline.setAutoSizeTextTypeUniformWithConfiguration(22, 28, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
    content.addView(headline, new LinearLayout.LayoutParams(-1, -2));

    View showcase = new PhoneFeatureShowcase();
    showcase.setContentDescription(I18n.t(
        "Điện thoại minh họa luân phiên các tính năng Bảng tin, Khám phá, Video và Live. Chạm để chuyển tính năng."));
    content.addView(showcase, new LinearLayout.LayoutParams(-1, 0, 1));

    LinearLayout start = authButton(null, I18n.t("Bắt đầu kết nối"), true);
    if (start.getChildCount() > 0 && start.getChildAt(0) instanceof TextView) {
      TextView startLabel = (TextView) start.getChildAt(0);
      startLabel.setTextSize(16);
      startLabel.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    }
    start.setOnClickListener(v -> auth(true));
    LinearLayout.LayoutParams startLp = new LinearLayout.LayoutParams(-1, Math.max(dp(52), raw48));
    startLp.topMargin = dp(6);
    content.addView(start, startLp);

    TextView note = welcomeText(I18n.t("Dành cho người từ 18 tuổi · Minh họa tính năng"), 12, MUTED, false);
    note.setGravity(Gravity.CENTER);
    note.setPadding(0, dp(8), 0, 0);
    content.addView(note, new LinearLayout.LayoutParams(-1, -2));

    TextView version = welcomeText(installedVersionBuild(), 11, MUTED, false);
    version.setGravity(Gravity.CENTER);
    version.setPadding(0, dp(2), 0, 0);
    content.addView(version, new LinearLayout.LayoutParams(-1, -2));
  }

  private final class PhoneFeatureShowcase extends WelcomeScene {
    final android.graphics.drawable.Drawable miniLogo = getResources()
        .getDrawable(getResources().getIdentifier("kinnect_logo", "drawable", getPackageName()));
    final String[] tabs = { "Bảng tin", "Khám phá", "Video", "Live" };
    long clock = android.os.SystemClock.uptimeMillis();
    int manual = 1;

    PhoneFeatureShowcase() {
      super();
      setClickable(true);
      setContentDescription(I18n.t("Xem trước Bảng tin, Khám phá, Tạo nội dung, Video và Live"));
    }

    int currentActive() {
      if (introTabOverride >= 0 && introTabOverride < 4)
        return introTabOverride;
      boolean animate = android.animation.ValueAnimator.areAnimatorsEnabled();
      return (manual + (animate ? (int) ((android.os.SystemClock.uptimeMillis() - clock) / 1500) : 0)) % 4;
    }

    void selectPreview(int index) {
      introTabOverride = -1;
      manual = index;
      clock = android.os.SystemClock.uptimeMillis();
      invalidate();
    }

    @Override
    public boolean onTouchEvent(android.view.MotionEvent event) {
      if (event.getAction() == android.view.MotionEvent.ACTION_DOWN)
        return true;
      if (event.getAction() != android.view.MotionEvent.ACTION_UP)
        return true;
      performClick();
      float scale = Math.min(getWidth() / 330f, getHeight() / 450f);
      if (scale <= 0)
        return true;
      float x = (event.getX() - (getWidth() - 380 * scale) / 2) / scale,
          y = (event.getY() - (getHeight() - 450 * scale) / 2) / scale;
      if (y >= 374 && y <= 416 && x >= 96 && x <= 284) {
        int tab = Math.max(0, Math.min(4, (int) ((x - 100) / 36)));
        if (tab == 2)
          selectPreview((currentActive() + 1) % 4);
        else
          selectPreview(tab < 2 ? tab : tab - 1);
        return true;
      }
      if (x >= 96 && x <= 284 && y >= 19 && y < 374) {
        selectPreview((currentActive() + 1) % 4);
      }
      return true;
    }

    @Override
    public boolean performClick() {
      super.performClick();
      return true;
    }

    void iphoneStatus() {
      for (int i = 0; i < 4; i++)
        box(236 + i * 3.2f, 35.5f - (i + 1) * 1.7f, 2.2f, (i + 1) * 1.7f, .6f, TEXT);
      pen.setColor(TEXT);
      pen.setStyle(Paint.Style.STROKE);
      pen.setStrokeWidth(1.3f);
      canvas.drawArc(new RectF(250, 28.5f, 260, 38.5f), 222, 96, false, pen);
      canvas.drawArc(new RectF(252.3f, 30.8f, 257.7f, 36.2f), 222, 96, false, pen);
      pen.setStyle(Paint.Style.FILL);
      circle(255f, 35.3f, .85f, TEXT);
      pen.setStyle(Paint.Style.STROKE);
      pen.setStrokeWidth(.85f);
      canvas.drawRoundRect(new RectF(263, 28.8f, 275.5f, 35.2f), 1.6f, 1.6f, pen);
      pen.setStyle(Paint.Style.FILL);
      box(264.3f, 30.1f, 9.6f, 3.8f, .6f, TEXT);
      box(276.4f, 30.9f, 1.1f, 2.3f, .4f, TEXT);
    }

    @Override
    public void onWindowFocusChanged(boolean focused) {
      super.onWindowFocusChanged(focused);
      if (focused)
        invalidate();
    }

    @Override
    protected void onAttachedToWindow() {
      super.onAttachedToWindow();
      invalidate();
    }

    void glyph(android.graphics.drawable.Drawable icon, float x, float y, int size, int color) {
      if (icon != miniLogo)
        icon.setTint(color);
      icon.setBounds((int) x, (int) y, (int) x + size, (int) y + size);
      icon.draw(canvas);
    }

    android.graphics.Bitmap demoPhoto;

    android.graphics.Bitmap decodeAssetThumbnail(String assetName) {
      try (java.io.InputStream stream = getAssets().open(assetName)) {
        byte[] bytes = NativeApi.read(stream, 8 * 1024 * 1024);
        return MediaImageLoader.decodeSampledBitmap(bytes, 320);
      } catch (Exception ignored) {
        return null;
      }
    }

    void photo(float x, float y, float w, float h, float topRadius, float bottomRadius) {
      if (demoPhoto == null)
        demoPhoto = decodeAssetThumbnail("welcome-profile.png");
      if (demoPhoto == null)
        return;
      int saved = canvas.save();
      Path clip = new Path();
      float[] radii = { topRadius, topRadius, topRadius, topRadius, bottomRadius, bottomRadius, bottomRadius,
          bottomRadius };
      clip.addRoundRect(new RectF(x, y, x + w, y + h), radii, Path.Direction.CW);
      canvas.clipPath(clip);
      box(x, y, w, h, 0, SOFT);
      float ratio = Math.max(w / demoPhoto.getWidth(), h / demoPhoto.getHeight());
      float rw = demoPhoto.getWidth() * ratio, rh = demoPhoto.getHeight() * ratio;
      pen.setFilterBitmap(true);
      canvas.drawBitmap(demoPhoto, null, new RectF(x + (w - rw) / 2f, y, x + (w + rw) / 2f, y + rh), pen);
      canvas.restoreToCount(saved);
    }

    void photo(float x, float y, float w, float h, float radius) {
      photo(x, y, w, h, radius, radius);
    }

    final android.graphics.Bitmap[] demoPeople = new android.graphics.Bitmap[4];

    void personPhoto(int index, float x, float y, float w, float h, float topRadius, float bottomRadius) {
      if (demoPeople[index] == null)
        demoPeople[index] = decodeAssetThumbnail(
            index == 0 ? "welcome-profile.png" : "welcome-profile-" + index + ".png");
      android.graphics.Bitmap previous = demoPhoto;
      demoPhoto = demoPeople[index];
      photo(x, y, w, h, topRadius, bottomRadius);
      demoPhoto = previous;
    }

    void filledHeart(float x, float y, float s, int color) {
      Path p = new Path();
      float cx = x + s / 2f;
      p.moveTo(cx, y + s * 0.88f);
      p.cubicTo(x + s * 0.12f, y + s * 0.62f, x + s * 0.03f, y + s * 0.42f, x + s * 0.03f, y + s * 0.28f);
      p.cubicTo(x + s * 0.03f, y + s * 0.11f, x + s * 0.17f, y + s * 0.02f, x + s * 0.31f, y + s * 0.02f);
      p.cubicTo(x + s * 0.41f, y + s * 0.02f, x + s * 0.48f, y + s * 0.08f, cx, y + s * 0.15f);
      p.cubicTo(x + s * 0.52f, y + s * 0.08f, x + s * 0.59f, y + s * 0.02f, x + s * 0.69f, y + s * 0.02f);
      p.cubicTo(x + s * 0.83f, y + s * 0.02f, x + s * 0.97f, y + s * 0.11f, x + s * 0.97f, y + s * 0.28f);
      p.cubicTo(x + s * 0.97f, y + s * 0.42f, x + s * 0.88f, y + s * 0.62f, cx, y + s * 0.88f);
      p.close();
      pen.setStyle(Paint.Style.FILL);
      pen.setShader(null);
      pen.setColor(color);
      canvas.drawPath(p, pen);
    }

    void filledBubble(float x, float y, float s, int color) {
      pen.setStyle(Paint.Style.FILL);
      pen.setShader(null);
      pen.setColor(color);
      canvas.drawOval(new RectF(x, y + s * 0.06f, x + s * 0.96f, y + s * 0.82f), pen);
      Path tail = new Path();
      tail.moveTo(x + s * 0.18f, y + s * 0.68f);
      tail.lineTo(x + s * 0.06f, y + s * 0.94f);
      tail.lineTo(x + s * 0.42f, y + s * 0.76f);
      tail.close();
      canvas.drawPath(tail, pen);
    }

    void playRectangleGlyph(float cx, float cy, int color) {
      pen.setStyle(Paint.Style.STROKE);
      pen.setStrokeWidth(1.35f);
      pen.setShader(null);
      pen.setColor(color);
      canvas.drawRoundRect(new RectF(cx - 7.5f, cy - 5.3f, cx + 7.5f, cy + 5.3f), 2.3f, 2.3f, pen);
      pen.setStyle(Paint.Style.FILL);
      Path tri = new Path();
      tri.moveTo(cx - 2.1f, cy - 2.6f);
      tri.lineTo(cx - 2.1f, cy + 2.6f);
      tri.lineTo(cx + 2.8f, cy);
      tri.close();
      canvas.drawPath(tri, pen);
    }

    void screen(int index) {
      box(96, 19, 188, 409, 27, CARD);
      word("9:41", 109, 34.5f, 8.2f, TEXT, true);
      iphoneStatus();
      glyph(miniLogo, 104, 48, 18, WHITE);
      word("Kinnect", 126, 61.5f, 13.5f, ACCENT, true);
      glyph(WebIcons.load(MainActivity.this, "bell"), 239, 50, 12, TEXT);
      photo(258, 48, 16, 16, 8);
      word(I18n.t(tabs[index]), 105, 79, 8.2f, MUTED, false);
      if (index == 0) {
        circle(120, 104, 13.5f, SOFT);
        glyph(WebIcons.load(MainActivity.this, "plus"), 113, 97, 14, ACCENT);
        String storyCta = I18n.t("Tạo tin");
        pen.setTextSize(6.8f);
        pen.setTypeface(ApprovedTypography.font(MainActivity.this, Typeface.NORMAL));
        word(storyCta, 120 - pen.measureText(storyCta) / 2f, 126, 6.8f, MUTED, false);
        pen.setStyle(Paint.Style.STROKE);
        pen.setStrokeWidth(1.5f);
        pen.setColor(ACCENT);
        canvas.drawCircle(156, 104, 15f, pen);
        pen.setStyle(Paint.Style.FILL);
        personPhoto(0, 143, 91, 26, 26, 13, 13);
        String authorShort = "Minh Anh";
        pen.setTextSize(6.8f);
        word(authorShort, 156 - pen.measureText(authorShort) / 2f, 126, 6.8f, MUTED, false);
        box(104, 135, 172, 25, 8, SOFT);
        personPhoto(0, 109, 138.5f, 18, 18, 9, 9);
        word(I18n.t("Bạn đang nghĩ gì?"), 133, 150.5f, 7.8f, MUTED, false);
        box(104, 167, 172, 199, 10, SOFT);
        personPhoto(0, 111, 174, 20, 20, 10, 10);
        word("Minh Anh · 27", 136, 182.5f, 8.2f, TEXT, true);
        word(I18n.t("Hồ sơ minh họa"), 136, 192.5f, 6.8f, MUTED, false);
        word(I18n.t("Tập luyện mỗi ngày"), 111, 206.5f, 8f, TEXT, false);
        personPhoto(0, 111, 213, 158, 125, 7, 7);
        filledHeart(113, 346, 12, 0xffec4899);
        filledBubble(136, 346, 12, MUTED);
        glyph(WebIcons.load(MainActivity.this, "forward"), 159, 345, 13, MUTED);
      } else if (index == 1) {
        box(104, 89, 172, 22, 7, SOFT);
        word(I18n.t("Dành cho bạn"), 112, 102.5f, 7.5f, ACCENT, true);
        String followTab = I18n.t("Đang theo dõi");
        pen.setTextSize(7.5f);
        pen.setTypeface(ApprovedTypography.font(MainActivity.this, Typeface.BOLD));
        word(followTab, 268 - pen.measureText(followTab), 102.5f, 7.5f, TEXT, true);
        box(104, 117, 172, 22, 7, SOFT);
        glyph(WebIcons.load(MainActivity.this, "search"), 110, 123, 10, MUTED);
        word(I18n.t("Tên đăng nhập"), 124, 131, 7.8f, MUTED, false);
        String[] people = { "Minh Anh, 27", "Gia Huy, 28", "Hoàng Nam, 30", "Quang Minh, 26" };
        for (int i = 0; i < 4; i++) {
          float px = 104 + (i % 2) * 90, py = 147 + (i / 2) * 112;
          box(px, py, 82, 104, 8, SOFT);
          personPhoto(i, px, py, 82, 83, 8, 0);
          pen.setTextSize(7.4f);
          pen.setTypeface(ApprovedTypography.font(MainActivity.this, Typeface.BOLD));
          float labelX = px + (82 - pen.measureText(people[i])) / 2f;
          word(people[i], labelX, py + 96, 7.4f, TEXT, true);
        }
      } else if (index == 2) {
        personPhoto(1, 104, 89, 172, 279, 10, 10);
        int scrim = canvas.save();
        Path clip = new Path();
        clip.addRoundRect(new RectF(104, 89, 276, 368), 10, 10, Path.Direction.CW);
        canvas.clipPath(clip);
        pen.setStyle(Paint.Style.FILL);
        pen.setShader(new android.graphics.LinearGradient(0, 318, 0, 368, 0x00000000, 0x78000000,
            android.graphics.Shader.TileMode.CLAMP));
        canvas.drawRect(104, 318, 276, 368, pen);
        pen.setShader(null);
        canvas.restoreToCount(scrim);
        word("@minhanh_demo", 112, 358, 8.5f, WHITE, true);
      } else {
        personPhoto(2, 104, 89, 172, 279, 10, 10);
        box(111, 97, 34, 16, 8, 0xffdb2777);
        pen.setTextSize(7.2f);
        pen.setTypeface(ApprovedTypography.font(MainActivity.this, Typeface.BOLD));
        float liveW = pen.measureText("LIVE");
        word("LIVE", 111 + (34 - liveW) / 2f, 107.8f, 7.2f, WHITE, true);
      }
    }

    void previewNavigation(int index) {
      String[] names = { "Bảng tin", "Khám phá", "", "Video", "Live" };
      String[] icons = { "house", "compass", "plus", "", "radio" };
      for (int i = 0; i < 5; i++) {
        float center = 118 + i * 36;
        boolean selected = i == (index < 2 ? index : index + 1);
        int ink = selected ? ACCENT : MUTED;
        if (i == 2) {
          box(center - 13.5f, 379, 27, 27, 9, ACCENT);
          glyph(WebIcons.load(MainActivity.this, "plus"), center - 7, 385.5f, 14, WHITE);
        } else {
          if (i == 3)
            playRectangleGlyph(center, 392.5f, ink);
          else
            glyph(WebIcons.load(MainActivity.this, icons[i]), center - 7, 385.5f, 14, ink);
          String tabLabel = I18n.t(names[i]);
          pen.setTextSize(6.7f);
          pen.setTypeface(ApprovedTypography.font(MainActivity.this, Typeface.NORMAL));
          word(tabLabel, center - pen.measureText(tabLabel) / 2f, 410, 6.7f, ink, false);
        }
      }
    }

    void concentricRings() {
      pen.setStyle(Paint.Style.STROKE);
      pen.setStrokeWidth(1f);
      pen.setShader(null);
      pen.setColor((0x1e << 24) | (ACCENT & 0xffffff));
      for (int r : new int[] { 140, 170, 200 })
        canvas.drawCircle(190, 224, r, pen);
      pen.setStyle(Paint.Style.FILL);
    }

    @Override
    protected void onDraw(Canvas c) {
      canvas = c;
      float scale = Math.min(getWidth() / 330f, getHeight() / 450f);
      if (scale <= 0)
        return;
      int save = c.save();
      c.translate((getWidth() - 380 * scale) / 2f, (getHeight() - 450 * scale) / 2f);
      c.scale(scale, scale);
      long elapsed = android.os.SystemClock.uptimeMillis() - clock;
      boolean animate = introTabOverride < 0 && android.animation.ValueAnimator.areAnimatorsEnabled();
      int index = currentActive();
      float phase = animate ? (elapsed % 1500) / 1500f : 0f;
      concentricRings();
      c.save();
      pen.setShadowLayer(16, 0, 8, 0x30000000);
      box(89, 12, 202, 423, 34, 0xffa6a6ad);
      pen.clearShadowLayer();
      box(91, 14, 198, 419, 32, 0xff000000);
      int screenClip = c.save();
      Path inner = new Path();
      inner.addRoundRect(new RectF(96, 19, 284, 428), 27, 27, Path.Direction.CW);
      c.clipPath(inner);
      screen(index);
      if (phase > .80f) {
        int alpha = (int) ((phase - .80f) / .20f * 255);
        int layer = c.saveLayerAlpha(96, 19, 284, 376, alpha);
        screen((index + 1) % 4);
        c.restoreToCount(layer);
      }
      previewNavigation(index);
      box(172, 25, 36, 10, 5, 0xff000000);
      int barColor = WebTheme.isDark(MainActivity.this) ? 0x55ffffff : 0xff1f1d2b;
      box(164, 418, 52, 3, 1.5f, barColor);
      c.restoreToCount(screenClip);
      c.restore();
      c.restoreToCount(save);
      if (animate && isShown() && hasWindowFocus())
        postInvalidateDelayed(33);
    }
  }

  private class WelcomeScene extends View {
    final Paint pen = new Paint(Paint.ANTI_ALIAS_FLAG);
    final RectF rect = new RectF();
    Canvas canvas;

    WelcomeScene() {
      super(MainActivity.this);
      setLayerType(View.LAYER_TYPE_SOFTWARE, null);
    }

    void box(float x, float y, float w, float h, float radius, int color) {
      pen.setStyle(Paint.Style.FILL);
      pen.setShader(null);
      pen.setColor(color);
      rect.set(x, y, x + w, y + h);
      canvas.drawRoundRect(rect, radius, radius, pen);
    }

    void word(String text, float x, float y, float size, int color, boolean bold) {
      pen.setShader(null);
      pen.setColor(color);
      pen.setTypeface(ApprovedTypography.font(MainActivity.this, bold ? Typeface.BOLD : Typeface.NORMAL));
      pen.setTextSize(size);
      canvas.drawText(text, x, y, pen);
    }

    void circle(float x, float y, float r, int color) {
      pen.setShader(null);
      pen.setColor(color);
      canvas.drawCircle(x, y, r, pen);
    }

    @Override
    protected void onDraw(Canvas c) {
      super.onDraw(c);
      canvas = c;
      float scale = Math.min(getWidth() / 380f, getHeight() / 310f);
      int saved = c.save();
      c.translate((getWidth() - 380 * scale) / 2, (getHeight() - 310 * scale) / 2);
      c.scale(scale, scale);
      circle(198, 150, 132, PRIMARY_SOFT);
      circle(312, 73, 25, (PINK & 0xffffff) | 0x18000000);
      circle(56, 235, 20, PRIMARY_SOFT);
      c.save();
      c.rotate(-7, 124, 151);
      pen.setShadowLayer(13, 0, 7, 0x1c2a154a);
      box(46, 39, 164, 231, 23, CARD);
      pen.clearShadowLayer();
      pen.setShader(new android.graphics.LinearGradient(62, 55, 195, 175, new int[] { 0xff8b5cf6, 0xffec4899 }, null,
          android.graphics.Shader.TileMode.CLAMP));
      rect.set(56, 49, 200, 177);
      c.drawRoundRect(rect, 17, 17, pen);
      pen.setShader(null);
      circle(128, 100, 22, 0xffeadcff);
      box(87, 128, 82, 46, 30, 0xffeadcff);
      word(I18n.t("HỒ SƠ MINH HỌA"), 65, 195, 8, MUTED, true);
      word(I18n.t("Là chính bạn"), 65, 217, 16, TEXT, true);
      box(65, 232, 62, 20, 10, PRIMARY_SOFT);
      word(I18n.t("Âm nhạc"), 73, 246, 9, ACCENT, true);
      box(134, 232, 55, 20, 10, SOFT);
      word(I18n.t("Du lịch"), 142, 246, 9, MUTED, true);
      c.restore();
      c.save();
      c.rotate(8, 261, 126);
      pen.setShadowLayer(12, 0, 6, 0x242a154a);
      box(208, 42, 126, 180, 20, 0xff30204b);
      pen.clearShadowLayer();
      box(218, 52, 106, 160, 14, 0xff4c2b70);
      circle(269, 116, 34, 0xff714096);
      pen.setColor(WHITE);
      Path triangle = new Path();
      triangle.moveTo(261, 101);
      triangle.lineTo(261, 130);
      triangle.lineTo(283, 115);
      triangle.close();
      c.drawPath(triangle, pen);
      word("VIDEO", 229, 78, 10, 0xffeadcff, true);
      word(I18n.t("Chất riêng của bạn"), 228, 188, 9, WHITE, true);
      c.restore();
      pen.setShadowLayer(10, 0, 5, 0x202a154a);
      box(140, 226, 209, 57, 17, CARD);
      pen.clearShadowLayer();
      circle(165, 255, 14, PRIMARY_SOFT);
      word("K", 160, 261, 15, ACCENT, true);
      word(I18n.t("Bắt đầu bằng lời chào"), 188, 250, 12, TEXT, true);
      word(I18n.t("Nhắn tin · Gọi thoại · Video"), 188, 267, 9, MUTED, false);
      box(20, 190, 91, 30, 15, CARD);
      circle(35, 205, 4, 0xff10b981);
      word("LIVE", 47, 210, 11, TEXT, true);
      word(I18n.t("MINH HỌA TÍNH NĂNG"), 126, 308, 8, MUTED, false);
      c.restoreToCount(saved);
    }
  }

  // ----- Đăng nhập nhanh trên thiết bị này + Google/Facebook
  private void authExtras(boolean register) {
    final int generation = screen;
    final LinearLayout recent = column();
    final LinearLayout providersBox = column();
    content.addView(recent);
    content.addView(providersBox);
    if (!register)
      api.call("GET", "/api/remembered", null, (data, error, status) -> {
        JSONArray accounts = data == null ? null : data.optJSONArray("accounts");
        if (accounts == null || accounts.length() == 0 || isDestroyed() || generation != screen)
          return;
        for (int i = 0; i < accounts.length(); i++) {
          final JSONObject a = accounts.optJSONObject(i);
          LinearLayout r = row();
          r.setPadding(dp(12), dp(8), dp(6), dp(8));
          r.setBackground(outlined(CARD, 14));
          avatar(a, r, 34);
          LinearLayout t = column();
          t.setPadding(dp(10), 0, dp(4), 0);
          TextView n = label(a.optString("name"), 14, TEXT);
          n.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
          n.setSingleLine(true);
          n.setEllipsize(android.text.TextUtils.TruncateAt.END);
          t.addView(n);
          TextView u = label("@" + a.optString("username"), 12, MUTED);
          u.setSingleLine(true);
          u.setEllipsize(android.text.TextUtils.TruncateAt.END);
          t.addView(u);
          r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
          FrameLayout go = new FrameLayout(this);
          go.addView(icon("log_in", 16, ACCENT_TEXT), new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
          r.addView(go, new LinearLayout.LayoutParams(dp(30), dp(30)));
          FrameLayout remove = new FrameLayout(this);
          remove.addView(icon("x", 14, MUTED), new FrameLayout.LayoutParams(dp(14), dp(14), Gravity.CENTER));
          remove.setBackground(pressable(SOFT, 99));
          remove.setContentDescription(I18n.t("Gỡ tài khoản khỏi thiết bị"));
          remove
              .setOnClickListener(v -> api.call("DELETE", "/api/remembered/" + a.optString("id"), json(), (d, e, s) -> {
                if (generation == screen && !isDestroyed()) {
                  if (e != null)
                    say(e);
                  else
                    auth(false);
                }
              }));
          remove.setLayoutParams(new LinearLayout.LayoutParams(dp(30), dp(30)));
          r.addView(UiMetrics.wrapMinTouchTarget(this, remove, 48));
          r.setContentDescription(I18n.t("Đăng nhập nhanh ") + a.optString("name"));
          r.setOnClickListener(v -> {
            final String uid = a.optString("id");
            api.call("POST", "/api/remembered/login", json("userId", uid), (d, e, s) -> {
              if (generation != screen || isDestroyed())
                return;
              if (isTwoFactorRequired(s, d, e)) {
                promptTwoFactorAction(generation, "/api/remembered/login", json("userId", uid), null, null);
                return;
              }
              if (e != null) {
                say(e);
                return;
              }
              onUserSignedIn(d.optJSONObject("user"));
              navigate("feed");
            });
          });
          LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
          p.setMargins(0, dp(8), 0, 0);
          recent.addView(r, p);
          UiMetrics.enforceMinTouchTarget(r, 48);
        }
      });
    api.call("GET", "/api/oauth/providers", null, (data, error, status) -> {
      JSONArray providers = data == null ? null : data.optJSONArray("providers");
      if (providers == null || providers.length() == 0 || isDestroyed() || generation != screen)
        return;
      LinearLayout buttons = row();
      for (int i = 0; i < providers.length(); i++) {
        final String provider = providers.optString(i);
        boolean google = provider.equals("google");
        LinearLayout b = row();
        b.setGravity(Gravity.CENTER);
        b.setBackground(outlined(CARD, 99));
        ImageView mark = new ImageView(this);
        mark.setImageResource(getResources().getIdentifier(google ? "ic_brand_google" : "ic_brand_facebook", "drawable",
            getPackageName()));
        b.addView(mark, new LinearLayout.LayoutParams(dp(24), dp(24)));
        TextView t = label(google ? "Google" : "Facebook", 15, TEXT);
        t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        t.setPadding(dp(12), 0, 0, 0);
        b.addView(t);
        b.setContentDescription(I18n.t("Tiếp tục với ") + (google ? "Google" : "Facebook"));
        b.setOnClickListener(v -> {
          try {
            startActivity(new Intent(Intent.ACTION_VIEW,
                android.net.Uri.parse(server() + "/api/oauth/" + provider + "/start?client=android")));
          } catch (Exception e) {
            say(I18n.t("Không mở được trình duyệt."));
          }
        });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, dp(56), 1);
        if (i > 0)
          p.leftMargin = dp(12);
        buttons.addView(b, p);
      }
      LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(-1, -2);
      bp.bottomMargin = dp(16);
      providersBox.addView(buttons, bp);
      providersBox.addView(textDivider(I18n.t("hoặc tiếp tục với mật khẩu")));
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
    if (uri == null || !"kinnect".equals(uri.getScheme()) || !"oauth".equals(uri.getHost()))
      return;
    String code = uri.getQueryParameter("code"), ticket = uri.getQueryParameter("ticket"),
        error = uri.getQueryParameter("error");
    if (error != null) {
      auth(false);
      // Báo rõ nguyên nhân để dễ xử lý: huỷ, hết hạn phiên OAuth, nhà cung cấp từ
      // chối, tài khoản bị khoá.
      String message = error.equals("cancelled") ? I18n.t("Bạn đã huỷ đăng nhập.")
          : error.equals("state") ? I18n.t("Phiên đăng nhập đã hết hạn. Hãy thử lại.")
              : error.equals("suspended") ? I18n.t("Tài khoản đang bị tạm khoá.")
                  : error.equals("provider")
                      ? I18n.t("Google/Facebook từ chối đổi mã đăng nhập. Kiểm tra cấu hình OAuth trên máy chủ.")
                      : I18n.t("Đăng nhập chưa hoàn tất. Hãy thử lại.");
      say(message);
      return;
    }
    if (code != null) {
      final int oauthGen = screen;
      if ("1".equals(uri.getQueryParameter("requires2fa"))) {
        promptTwoFactorAction(oauthGen, "/api/oauth/app-session", json("code", code), null, null);
        return;
      }
      api.call("POST", "/api/oauth/app-session", json("code", code), (d, e, s) -> {
        if (isFinishing() || isDestroyed())
          return;
        if (isTwoFactorRequired(s, d, e)) {
          promptTwoFactorAction(screen, "/api/oauth/app-session", json("code", code), null, null);
          return;
        }
        if (e != null) {
          auth(false);
          say(e);
          return;
        }
        onUserSignedIn(d.optJSONObject("user"));
        navigate("feed");
      });
    }
    if (ticket != null)
      oauthComplete(ticket);
  }

  private void oauthComplete(String ticket) {
    api.call("GET", "/api/oauth/pending?ticket=" + encode(ticket), null, (d, e, s) -> {
      if (e != null) {
        auth(false);
        say(e);
        return;
      }
      shell(I18n.t("Hoàn tất đăng ký"), false);
      content.addView(
          label(I18n.t("Chào ") + d.optString("name") + I18n.t("! Chọn tên đăng nhập cho Kinnect."), 16, TEXT));
      EditText username = input(content, I18n.t("Tên đăng nhập"), d.optString("suggestedUsername"), false);
      CheckBox agree = new CheckBox(this);
      agree.setText(I18n.t("Tôi xác nhận mình đủ 18 tuổi và tôn trọng quy tắc cộng đồng."));
      agree.setTextColor(MUTED);
      content.addView(agree);
      content.addView(primary(I18n.t("Bắt đầu"),
          () -> api.call("POST", "/api/oauth/complete",
              json("ticket", ticket, "username", username.getText().toString(), "agree18", agree.isChecked()),
              (r, err, st) -> {
                if (err != null) {
                  say(err);
                  return;
                }
                onUserSignedIn(r.optJSONObject("user"));
                navigate("feed");
              })));
    });
  }

  // ----- Quên / đổi mật khẩu
  private void forgot() {
    shell("", false);
    toolbar.setVisibility(View.GONE);
    if (root.getChildCount() > 1)
      root.getChildAt(1).setVisibility(View.GONE);
    subBack = () -> auth(false);
    LinearLayout topNav = row();
    topNav.setGravity(Gravity.CENTER_VERTICAL);
    topNav.setPadding(0, dp(4), 0, dp(10));
    LinearLayout backRow = row();
    backRow.setGravity(Gravity.CENTER_VERTICAL);
    backRow.addView(icon("arrow_left", 18, TEXT), new LinearLayout.LayoutParams(dp(18), dp(18)));
    TextView backText = label(I18n.t("Quay lại"), 14, TEXT);
    backText.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    backText.setPadding(dp(8), 0, 0, 0);
    backRow.addView(backText);
    backRow.setPadding(0, dp(8), dp(12), dp(8));
    backRow.setContentDescription(I18n.t("Quay lại đăng nhập"));
    backRow.setOnClickListener(v -> auth(false));
    topNav.addView(backRow, new LinearLayout.LayoutParams(0, -2, 1));
    UiMetrics.enforceMinTouchTarget(backRow, 48);
    LinearLayout langChip = row();
    langChip.setGravity(Gravity.CENTER);
    langChip.setPadding(dp(10), dp(6), dp(10), dp(6));
    langChip.setBackground(outlined(CARD, 99));
    langChip.addView(icon("globe", 14, ACCENT_TEXT), new LinearLayout.LayoutParams(dp(14), dp(14)));
    TextView langLabel = label(I18n.current().equals("en") ? "EN" : "VI", 12, TEXT);
    langLabel.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    langLabel.setPadding(dp(5), 0, 0, 0);
    langChip.addView(langLabel);
    langChip.setContentDescription(I18n.t("Tiếng Việt / English"));
    langChip.setOnClickListener(v -> languageMenu());
    topNav.addView(UiMetrics.wrapMinTouchTarget(this, langChip, 48), new LinearLayout.LayoutParams(-2, -2));
    content.addView(topNav, new LinearLayout.LayoutParams(-1, -2));

    content.addView(label(I18n.t("Quên mật khẩu"), WebDesign.TITLE, TEXT));
    TextView sub = label(I18n.t("Chúng tôi sẽ gửi mã xác minh hoặc hướng dẫn tới email khôi phục của bạn."), 14, MUTED);
    sub.setPadding(0, dp(4), 0, dp(12));
    content.addView(sub);
    final EditText identifier = authField(content, "user_round", I18n.t("Tên đăng nhập hoặc email"), false);
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
    final Button send = primary(I18n.t("Gửi mã qua email"), () -> {
    });
    send.setOnClickListener(v -> {
      if (!send.isEnabled())
        return;
      if (identifier.getText().toString().trim().isEmpty()) {
        identifier.setError(I18n.t("Nhập tên đăng nhập hoặc email"));
        return;
      }
      send.setEnabled(false);
      request("POST", "/api/recovery/reset/start",
          json("identifier", identifier.getText().toString().trim().toLowerCase(Locale.ROOT)), result -> {
            challenge[0] = result.optString("challengeId");
            verification.setVisibility(View.VISIBLE);
            send.setText(I18n.t("Gửi lại mã"));
            identifier.setEnabled(false);
            say(result.optString("message"));
            code.requestFocus();
          }, () -> send.setEnabled(true));
    });
    content.addView(send);
    content.addView(verification);
    final Button reset = primary(I18n.t("Đặt lại mật khẩu"), () -> {
    });
    verification.addView(reset);
    reset.setOnClickListener(v -> {
      if (!reset.isEnabled())
        return;
      if (code.length() != 6) {
        code.setError(I18n.t("Nhập mã 6 chữ số"));
        return;
      }
      if (password.length() < 6) {
        password.setError(I18n.t("Mật khẩu cần ít nhất 6 ký tự"));
        return;
      }
      reset.setEnabled(false);
      request("POST", "/api/recovery/reset/finish", json("challengeId", challenge[0], "code", code.getText().toString(),
          "password", password.getText().toString()), result -> {
            auth(false);
            say(result.optString("message", I18n.t("Đã đặt lại mật khẩu")));
          }, () -> reset.setEnabled(true));
    });
    TextView supportLink = label(I18n.t("Nhờ quản trị viên hỗ trợ"), 14, ACCENT_TEXT);
    supportLink.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
    supportLink.setGravity(Gravity.CENTER);
    supportLink.setPadding(dp(12), dp(12), dp(12), dp(12));
    supportLink.setOnClickListener(v -> forgotSupport());
    LinearLayout.LayoutParams supLp = new LinearLayout.LayoutParams(-1, -2);
    supLp.topMargin = dp(8);
    content.addView(supportLink, supLp);
    UiMetrics.enforceMinTouchTarget(supportLink, 48);
  }

  private void forgotSupport() {
    shell(I18n.t("Quên mật khẩu"), false);
    subBack = () -> forgot();
    content.addView(label(I18n.t("Để lại thông tin liên hệ, quản trị viên sẽ cấp mật khẩu tạm cho bạn."), 15, MUTED));
    EditText username = input(content, I18n.t("Tên đăng nhập"), "", false),
        contact = input(content, I18n.t("Email, số điện thoại hoặc Zalo"), "", false),
        note = input(content, I18n.t("Ghi chú (không bắt buộc)"), "", true);
    content.addView(primary(I18n.t("Gửi yêu cầu"),
        () -> request("POST", "/api/password-reset", json("username", username.getText().toString(), "contact",
            contact.getText().toString(), "note", note.getText().toString()), d -> {
              content.removeAllViews();
              content.addView(label("✓ " + d.optString("message"), 17, TEXT));
              content.addView(primary(I18n.t("Về đăng nhập"), () -> auth(false)));
            })));
    content.addView(button(I18n.t("Quay lại"), () -> auth(false)));
  }

  private void changePassword() {
    if (me == null)
      return;
    LinearLayout box = column();
    box.setPadding(dp(20), dp(8), dp(20), 0);
    final boolean hasPwd = me == null || me.optBoolean("hasPassword", true);
    final EditText current;
    if (hasPwd) {
      box.addView(label(I18n.t("Mật khẩu hiện tại"), 12, MUTED));
      current = authField(box, "lock_keyhole", I18n.t("Mật khẩu hiện tại"), true);
    } else {
      current = new KinnectInput(this);
      LinearLayout.LayoutParams nlp = new LinearLayout.LayoutParams(-1, -2);
      nlp.bottomMargin = dp(8);
      box.addView(label(I18n.t("Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây)."), 13, MUTED),
          nlp);
    }
    box.addView(label(I18n.t("Mật khẩu mới"), 12, MUTED));
    final EditText next = authField(box, "lock_keyhole", I18n.t("Mật khẩu mới (tối thiểu 6 ký tự)"), true);
    box.addView(label(I18n.t("Nhập lại mật khẩu mới"), 12, MUTED));
    final EditText retype = authField(box, "lock_keyhole", I18n.t("Nhập lại mật khẩu mới"), true);
    final TextView inlineErr = label("", 13, WebDesign.DANGER[WebTheme.isDark(this) ? 1 : 0]);
    inlineErr.setVisibility(View.GONE);
    box.addView(inlineErr);
    final boolean[] savingPw = { false };
    new Sheet(this).setTitle(I18n.t(hasPwd ? "Đổi mật khẩu" : "Đặt mật khẩu")).setView(box)
        .setAutoDismissPositive(false).setPositiveButton(I18n.t("Lưu"), (d, w) -> {
          if (savingPw[0])
            return;
          String cVal = hasPwd && current.getText() != null ? current.getText().toString() : "";
          String nVal = next.getText() == null ? "" : next.getText().toString();
          String rVal = retype.getText() == null ? "" : retype.getText().toString();
          boolean qaDebug = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
          if (hasPwd && cVal.isEmpty()) {
            String msg = I18n.t("Vui lòng nhập mật khẩu hiện tại.");
            if (qaDebug)
              android.util.Log.i("KinnectQA", "PASSWORD_VALIDATION: branch=empty_current error='" + msg
                  + "' api_dispatched=false api_dispatch_count=" + NativeApi.shared.apiDispatchCount);
            inlineErr.setText(msg);
            inlineErr.setVisibility(View.VISIBLE);
            say(msg);
            return;
          }
          if (nVal.length() < 6) {
            String msg = I18n.t("Mật khẩu mới phải có ít nhất 6 ký tự.");
            if (qaDebug)
              android.util.Log.i("KinnectQA", "PASSWORD_VALIDATION: branch=short_new_password error='" + msg
                  + "' api_dispatched=false api_dispatch_count=" + NativeApi.shared.apiDispatchCount);
            inlineErr.setText(msg);
            inlineErr.setVisibility(View.VISIBLE);
            say(msg);
            return;
          }
          if (!nVal.equals(rVal)) {
            String msg = I18n.t("Mật khẩu nhập lại không khớp.");
            if (qaDebug)
              android.util.Log.i("KinnectQA", "PASSWORD_VALIDATION: branch=mismatch error='" + msg
                  + "' api_dispatched=false api_dispatch_count=" + NativeApi.shared.apiDispatchCount);
            inlineErr.setText(msg);
            inlineErr.setVisibility(View.VISIBLE);
            say(msg);
            return;
          }
          inlineErr.setVisibility(View.GONE);
          savingPw[0] = true;
          if (qaDebug)
            android.util.Log.i("KinnectQA", "PASSWORD_VALIDATION: branch=passed api_dispatched=true");
          api.call("POST", "/api/me/password", json("current", cVal, "next", nVal), null, (r, e, s) -> {
            savingPw[0] = false;
            if (isFinishing() || isDestroyed())
              return;
            if (e != null) {
              String errText = I18n.t(e);
              inlineErr.setText(errText);
              inlineErr.setVisibility(View.VISIBLE);
              say(errText);
              return;
            }
            try {
              if (me != null)
                me.put("hasPassword", true);
            } catch (Exception ignored) {
            }
            try {
              d.dismiss();
            } catch (Exception ignored) {
            }
            say(I18n.t("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất."));
          }, () -> savingPw[0] = false);
        }).setNegativeButton(I18n.t("Hủy"), null).show();
  }

  // ----- Hồ sơ: số liệu, người theo dõi, bài viết
  private void stats(JSONObject u, LinearLayout parent) {
    final LinearLayout r = row();
    r.setPadding(dp(14), dp(10), dp(14), dp(10));
    parent.addView(r);
    request("GET", "/api/users/" + u.optString("id") + "/stats", null, d -> {
      String[][] items = { { String.valueOf(d.optInt("posts")), "bài viết", "" },
          { String.valueOf(d.optInt("followers")), "người theo dõi", "followers" },
          { String.valueOf(d.optInt("following")), "đang theo dõi", "following" } };
      for (final String[] it : items) {
        LinearLayout c = column();
        c.setGravity(Gravity.CENTER);
        c.setPadding(dp(10), dp(8), dp(10), dp(8));
        c.setBackground(background(SOFT, 16));
        TextView n = label(it[0], 18, TEXT);
        n.setTypeface(null, Typeface.BOLD);
        n.setGravity(Gravity.CENTER);
        n.setPadding(0, 0, 0, 0);
        TextView l = label(I18n.t(it[1]), 11, MUTED);
        l.setGravity(Gravity.CENTER);
        l.setPadding(0, 0, 0, 0);
        c.addView(n);
        c.addView(l);
        if (!it[2].isEmpty())
          c.setOnClickListener(
              v -> connections(u, it[2], it[1].substring(0, 1).toUpperCase(Locale.ROOT) + it[1].substring(1)));
        r.addView(c, new LinearLayout.LayoutParams(0, -2, 1));
        if (!it[2].isEmpty())
          UiMetrics.enforceMinTouchTarget(c, 48);
        else
          c.setMinimumHeight(UiMetrics.dpRaw(this, 48));
      }
    });
  }

  private void connections(JSONObject u, String kind, String title) {
    shell(title, true);
    request("GET", "/api/users/" + u.optString("id") + "/" + kind, null, d -> {
      JSONArray users = d.optJSONArray("users");
      if (users == null || users.length() == 0)
        content.addView(label(I18n.t("Chưa có ai."), 15, MUTED));
      for (int i = 0; users != null && i < users.length(); i++) {
        final JSONObject p = users.optJSONObject(i);
        inboxRow(content, p, p.optString("name"), "@" + p.optString("username"), 0, () -> person(p));
      }
    });
  }

  private void userPosts(JSONObject u) {
    shell(u.optString("name"), true);
    request("GET", "/api/posts?user=" + u.optString("id"), null,
        d -> posts(d.optJSONArray("posts"), "Chưa có bài viết."));
  }

  // ----- Danh sách bài viết dùng chung (nạp theo cửa sổ hiển thị + prefetch ảnh)
  private static final int FEED_WINDOW_BATCH = 10;

  private void posts(final JSONArray posts, String empty) {
    final LinearLayout targetContainer = content;
    if (posts == null || posts.length() == 0) {
      targetContainer.addView(emptyBlock("newspaper", I18n.t("Chưa có bài viết"),
          empty.contains(I18n.t("đầu tiên")) ? I18n.t("Hãy là người đầu tiên chia sẻ.")
              : I18n.t("Bài viết sẽ hiển thị tại đây.")));
      return;
    }
    final int expectedScreen = screen;
    WindowedListBinder.bind(this, targetContainer, posts, FEED_WINDOW_BATCH, dp(900), () -> screen == expectedScreen,
        (start, end) -> {
          MediaImageLoader.prefetchPosts(api, posts, start, Math.min(8, posts.length() - start), 1280);
          renderPostSlice(targetContainer, posts, start, end);
        });
  }

  private void renderPostSlice(LinearLayout targetContainer, JSONArray posts, int start, int end) {
    LinearLayout savedContent = content;
    content = targetContainer;
    int startIndex = targetContainer.getChildCount();
    try {
      for (int i = start; i < end; i++)
        postCard(posts.optJSONObject(i));
      for (int i = startIndex; i < targetContainer.getChildCount(); i++) {
        View card = targetContainer.getChildAt(i);
        card.setAlpha(0f);
        card.setTranslationY(dp(14));
        card.animate().alpha(1f).translationY(0f).setDuration(WebDesign.MOTION_BASE)
            .setStartDelay(Math.min(220, (i - startIndex) * 35L)).start();
      }
    } finally {
      content = savedContent;
    }
  }

  private void postCard(final JSONObject p) {
    postCard(p, "");
  }

  private void postCard(final JSONObject p, final String commentFocus) {
    if (getSharedPreferences("kinnect_feed", 0).getStringSet("hidden:" + me.optString("id"), Collections.emptySet())
        .contains(p.optString("id"))) {
      LinearLayout hidden = card();
      hidden.addView(label(I18n.t("Đã ẩn bài viết"), 13, MUTED));
      hidden.addView(button(I18n.t("Hoàn tác"), () -> {
        Set<String> ids = new HashSet<>(getSharedPreferences("kinnect_feed", 0)
            .getStringSet("hidden:" + me.optString("id"), Collections.emptySet()));
        ids.remove(p.optString("id"));
        getSharedPreferences("kinnect_feed", 0).edit().putStringSet("hidden:" + me.optString("id"), ids).apply();
        refreshPage();
      }));
      return;
    }
    final JSONObject author = p.optJSONObject("author");
    final boolean mine = p.optString("user_id").equals(me.optString("id"));
    LinearLayout c = card();
    c.setTag("post:" + p.optString("id") + ":" + p.toString());
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
    meta.addView(icon(p.optString("visibility").equals("followers") ? "profile" : "globe", 12, MUTED),
        new LinearLayout.LayoutParams(dp(12), dp(12)));
    meta.addView(
        label(p.optString("visibility").equals("followers") ? I18n.t(" Người theo dõi") : I18n.t(" Mọi thành viên"), 12,
            MUTED));
    who.addView(meta);
    who.setGravity(Gravity.CENTER_VERTICAL);
    head.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
    who.setOnClickListener(v -> person(author));
    UiMetrics.enforceMinTouchTarget(who, 48);
    ImageView more = icon("more", 22, MUTED);
    more.setPadding(dp(8), dp(8), dp(8), dp(8));
    more.setContentDescription(I18n.t("Thêm thao tác"));
    more.setOnClickListener(v -> postOptions(p, mine, c));
    more.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    head.addView(UiMetrics.wrapMinTouchTarget(this, more, 48));
    c.addView(head);
    if (!p.optString("body").isEmpty()) {
      TextView body = label(p.optString("body"), 14, TEXT);
      body.setPadding(0, dp(8), 0, dp(4));
      body.setLineSpacing(0, 1.6f);
      c.addView(body);
    }
    JSONArray mediaItems = p.optJSONArray("mediaItems");
    JSONObject media = p.optJSONObject("media");
    if (mediaItems != null && mediaItems.length() > 1) {
      LinearLayout albumRow = row();
      for (int mi = 0; mi < mediaItems.length(); mi++) {
        JSONObject item = mediaItems.optJSONObject(mi);
        if (item == null)
          continue;
        LinearLayout tile = column();
        mediaView(item, tile);
        LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(dp(220), -2);
        tp.rightMargin = dp(8);
        albumRow.addView(tile, tp);
      }
      c.addView(hscroll(albumRow));
    } else if (media != null) {
      if (media.optBoolean("offline")) {
        LinearLayout offline = row();
        offline.setPadding(dp(12), dp(14), dp(12), dp(14));
        offline.setBackground(background(SOFT, 12));
        offline.addView(icon("image", 20, MUTED), new LinearLayout.LayoutParams(dp(20), dp(20)));
        TextView hint = label(I18n.t("Ảnh/video tạm ngoại tuyến"), 12, MUTED);
        hint.setPadding(dp(10), 0, 0, 0);
        offline.addView(hint, new LinearLayout.LayoutParams(0, -2, 1));
        c.addView(offline);
      } else
        mediaView(media, c);
    }
    JSONObject sharedPost = p.optJSONObject("sharedPost");
    if (sharedPost != null) {
      LinearLayout quote = column();
      quote.setPadding(dp(12), dp(10), dp(12), dp(10));
      quote.setBackground(outlined(SOFT, 12));
      JSONObject sa = sharedPost.optJSONObject("author");
      TextView sn = label((sa == null ? "" : sa.optString("name")) + " · " + ago(sharedPost.optLong("created")), 12,
          MUTED);
      sn.setTypeface(null, Typeface.BOLD);
      quote.addView(sn);
      if (!sharedPost.optString("body").isEmpty())
        quote.addView(label(sharedPost.optString("body"), 13, TEXT));
      JSONObject sm = sharedPost.optJSONObject("media");
      if (sm != null && !sm.optBoolean("offline"))
        mediaView(sm, quote);
      LinearLayout.LayoutParams qp = new LinearLayout.LayoutParams(-1, -2);
      qp.topMargin = dp(6);
      c.addView(quote, qp);
    }
    LinearLayout stats = row();
    stats.setPadding(0, dp(10), 0, dp(10));
    final TextView reactSummary = label(reactionSummary(p), 13, MUTED);
    reactSummary.setGravity(Gravity.CENTER_VERTICAL);
    reactSummary.setOnClickListener(v -> {
      if (p.optInt("likes") > 0)
        reactorsSheet(p.optString("id"));
    });
    reactSummary.setContentDescription(I18n.t("Xem ai đã bày tỏ cảm xúc"));
    stats.addView(reactSummary, new LinearLayout.LayoutParams(0, -2, 1));
    UiMetrics.enforceMinTouchTarget(reactSummary, 48);
    int sharesCount = p.optInt("shares", 0);
    final TextView commentCount = label(
        p.optInt("comments") + I18n.t(" bình luận") + (sharesCount > 0 ? " · " + sharesCount + I18n.t(" chia sẻ") : ""),
        13, MUTED);
    commentCount.setGravity(Gravity.CENTER_VERTICAL);
    stats.addView(commentCount);
    UiMetrics.enforceMinTouchTarget(commentCount, 48);
    c.addView(stats);
    c.addView(divider());
    LinearLayout actions = row();
    String mineReaction = p.isNull("myReaction") ? "" : p.optString("myReaction");
    String glyph = null;
    for (String[] r : REACTIONS)
      if (r[0].equals(mineReaction))
        glyph = r[1];
    final LinearLayout react = actionButton(glyph == null ? "smile" : null, glyph,
        glyph == null ? I18n.t("Cảm xúc") : reactionName(mineReaction), !mineReaction.isEmpty());
    react.setTag(reactSummary);
    react.setOnClickListener(
        v -> request(p.optBoolean("liked") ? "DELETE" : "POST", "/api/posts/" + p.optString("id") + "/like",
            p.optBoolean("liked") ? json() : json("reaction", "like"), d -> refreshReaction(p, react, d)));
    react.setOnLongClickListener(v -> {
      reactionBar(v, w -> request("POST", "/api/posts/" + p.optString("id") + "/like",
          json("reaction", REACTIONS[w][0]), r -> refreshReaction(p, react, r)));
      return true;
    });
    int actH = Math.max(dp(44), UiMetrics.dpRaw(this, 48));
    actions.addView(react, new LinearLayout.LayoutParams(0, actH, 1));
    LinearLayout comment = actionButton("comment", null, I18n.t("Bình luận"), false);
    final LinearLayout thread = column();
    thread.setVisibility(View.GONE);
    thread.setTag(commentCount);
    final View.OnClickListener toggleComments = v -> {
      boolean open = thread.getVisibility() == View.VISIBLE;
      thread.setVisibility(open ? View.GONE : View.VISIBLE);
      if (!open)
        inlineComments(p, thread, true);
    };
    comment.setOnClickListener(toggleComments);
    commentCount.setOnClickListener(toggleComments);
    commentCount.setContentDescription(I18n.t("Xem bình luận"));
    actions.addView(comment, new LinearLayout.LayoutParams(0, actH, 1));
    LinearLayout share = actionButton("send", null, I18n.t("Chia sẻ"), false);
    share.setOnClickListener(v -> sharePost(p));
    actions.addView(share, new LinearLayout.LayoutParams(0, actH, 1));
    for (int i = 0; i < actions.getChildCount(); i++) {
      LinearLayout action = (LinearLayout) actions.getChildAt(i);
      View caption = action.getChildAt(action.getChildCount() - 1);
      if (caption instanceof TextView)
        ((TextView) caption).setTextSize(12);
    }
    LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(-1, -2);
    ap.setMargins(0, dp(4), 0, dp(4));
    c.addView(actions, ap);
    c.addView(thread);
    if (commentFocus != null && !commentFocus.isEmpty()) {
      thread.setVisibility(View.VISIBLE);
      inlineComments(p, thread, false, commentFocus);
    }
  }

  private String reactionName(String key) {
    switch (key) {
      case "love":
        return "Yêu thích";
      case "haha":
        return "Haha";
      case "wow":
        return "Wow";
      case "sad":
        return "Buồn";
      case "angry":
        return "Phẫn nộ";
      default:
        return "Thích";
    }
  }

  private String reactionSummary(JSONObject p) {
    StringBuilder glyphs = new StringBuilder();
    JSONObject counts = p.optJSONObject("reactions");
    int shown = 0;
    for (String[] r : REACTIONS)
      if (counts != null && counts.optInt(r[0]) > 0 && shown < 3) {
        glyphs.append(r[1]);
        shown++;
      }
    return (glyphs.length() > 0 ? glyphs + " " : "") + p.optInt("likes") + " cảm xúc";
  }

  // Danh sách người thả cảm xúc như web: tab Tất cả + từng loại.
  private void reactorsSheet(final String postId) {
    request("GET", "/api/posts/" + postId + "/reactions", null, data -> {
      final JSONArray users = data.optJSONArray("users");
      if (users == null || users.length() == 0)
        return;
      final LinearLayout box = column();
      final LinearLayout tabs = row();
      final LinearLayout list = column();
      final Map<String, Integer> counts = new LinkedHashMap<>();
      for (int i = 0; i < users.length(); i++) {
        String k = users.optJSONObject(i).optString("reaction");
        counts.put(k, counts.containsKey(k) ? counts.get(k) + 1 : 1);
      }
      final List<String> keys = new ArrayList<>();
      keys.add("all");
      keys.addAll(counts.keySet());
      final Runnable[] render = new Runnable[1];
      final String[] selected = { "all" };
      render[0] = () -> {
        tabs.removeAllViews();
        for (final String k : keys) {
          String glyph = "";
          for (String[] r : REACTIONS)
            if (r[0].equals(k))
              glyph = r[1];
          boolean on = selected[0].equals(k);
          TextView tab = label(k.equals("all") ? I18n.t("Tất cả ") + users.length() : glyph + " " + counts.get(k), 14,
              on ? ACCENT_TEXT : MUTED);
          tab.setGravity(Gravity.CENTER);
          tab.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
          tab.setPadding(dp(12), dp(10), dp(12), dp(10));
          if (on)
            tab.setBackground(background(PRIMARY_SOFT, 99));
          tab.setOnClickListener(v -> {
            selected[0] = k;
            render[0].run();
          });
          tabs.addView(tab);
          UiMetrics.enforceMinTouchTarget(tab, 48);
        }
        list.removeAllViews();
        for (int i = 0; i < users.length(); i++) {
          final JSONObject u = users.optJSONObject(i);
          if (!selected[0].equals("all") && !selected[0].equals(u.optString("reaction")))
            continue;
          LinearLayout r = row();
          r.setPadding(dp(4), dp(8), dp(4), dp(8));
          FrameLayout face = new FrameLayout(this);
          LinearLayout holder = new LinearLayout(this);
          avatar(u, holder, 42);
          face.addView(holder);
          String glyph = "";
          for (String[] x : REACTIONS)
            if (x[0].equals(u.optString("reaction")))
              glyph = x[1];
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
      box.addView(scroll, new LinearLayout.LayoutParams(-1,
          Math.min(getResources().getDisplayMetrics().heightPixels / 2, dp(64) * users.length() + dp(16))));
      new Sheet(this).setTitle(I18n.t("Cảm xúc")).setView(box).show();
    });
  }

  private void refreshAfterPostMutation() {
    clearRetainedFeed();
    feedRows = null;
    postsGetSnapshotStale = true;
    api.clearGetSnapshot("/api/posts?limit=25");
    if (feedRefresh != null)
      feedRefresh.run(() -> {
      });
    else
      refreshPage();
  }

  private android.app.Dialog postOptions(final JSONObject post, boolean mine, final LinearLayout card) {
    List<String> labels = new ArrayList<>(), icons = new ArrayList<>();
    List<Runnable> actions = new ArrayList<>();
    if (mine) {
      icons.add("pencil");
      labels.add(I18n.t("Chỉnh sửa bài viết"));
      actions.add(() -> {
        LinearLayout form = column();
        EditText body = input(form, I18n.t("Bạn đang nghĩ gì?"), post.optString("body"), true);
        new Sheet(this).setTitle(I18n.t("Chỉnh sửa bài viết")).setView(form)
            .setPositiveButton(I18n.t("Lưu"),
                (d, w) -> request("PATCH", "/api/posts/" + post.optString("id"),
                    json("body", body.getText().toString()), result -> refreshAfterPostMutation()))
            .setNegativeButton(I18n.t("Huỷ"), null).show();
      });
      icons.add("globe");
      labels.add(I18n.t("Thay đổi đối tượng xem"));
      actions.add(() -> new Sheet(this)
          .setTitle(I18n.t("Ai có thể xem bài viết?")).setItemIcons(
              new String[] { "globe", "users_round" })
          .setItems(new String[] { I18n.t("Mọi thành viên"), I18n.t("Người theo dõi") },
              (d, w) -> request("PATCH", "/api/posts/" + post.optString("id"),
                  json("visibility", w == 0 ? "public" : "followers"), result -> refreshAfterPostMutation()))
          .show());
    }
    boolean isBookmarked = post.optBoolean("bookmarked", false);
    icons.add("bookmark");
    labels.add(isBookmarked ? I18n.t("Bỏ lưu bài viết") : I18n.t("Lưu bài viết"));
    actions.add(() -> request(isBookmarked ? "DELETE" : "POST", "/api/posts/" + post.optString("id") + "/bookmark",
        isBookmarked ? null : json(), r -> {
          try {
            post.put("bookmarked", r.optBoolean("bookmarked"));
          } catch (JSONException ignored) {
          }
          say(r.optBoolean("bookmarked") ? I18n.t("Đã lưu bài viết") : I18n.t("Đã bỏ lưu bài viết"));
          refreshAfterPostMutation();
        }));
    icons.add("eye_off");
    labels.add(I18n.t("Ẩn bài viết"));
    actions.add(() -> {
      Set<String> hidden = new HashSet<>(
          getSharedPreferences("kinnect_feed", 0).getStringSet("hidden:" + me.optString("id"), Collections.emptySet()));
      hidden.add(post.optString("id"));
      getSharedPreferences("kinnect_feed", 0).edit().putStringSet("hidden:" + me.optString("id"), hidden).apply();
      clearRetainedFeed();
      card.removeAllViews();
      card.addView(label(I18n.t("Đã ẩn bài viết"), 13, MUTED));
      card.addView(button(I18n.t("Hoàn tác"), () -> {
        hidden.remove(post.optString("id"));
        getSharedPreferences("kinnect_feed", 0).edit().putStringSet("hidden:" + me.optString("id"), hidden).apply();
        refreshPage();
      }));
    });
    icons.add(mine ? "trash" : "flag");
    labels.add(mine ? I18n.t("Xoá bài viết") : I18n.t("Báo cáo bài viết"));
    actions.add(() -> {
      if (mine)
        confirm(I18n.t("Xoá bài viết?"), () -> request("DELETE", "/api/posts/" + post.optString("id"), json(),
            result -> refreshAfterPostMutation()));
      else
        report("post", post.optString("id"));
    });
    return new Sheet(this).setTitle(I18n.t("Tùy chọn bài viết")).setItemIcons(icons.toArray(new String[0]))
        .setItems(labels.toArray(new String[0]), (dialog, index) -> actions.get(index).run()).show();
  }

  private void sharePost(final JSONObject post) {
    final String url = "https://app.kinnect.io.vn/share/post/" + post.optString("id");
    new Sheet(this).setTitle(I18n.t("Chia sẻ bài viết"))
        .setItemIcons(new String[] { "send", "user_round", "copy", "share_2" })
        .setItems(new String[] { I18n.t("Chia sẻ lên bảng tin"), I18n.t("Gửi cho bạn bè"), I18n.t("Sao chép liên kết"),
            I18n.t("Chia sẻ qua ứng dụng khác") }, (dialog, choice) -> {
              if (choice == 0) {
                LinearLayout form = column();
                EditText cap = input(form, I18n.t("Viết cảm nghĩ của bạn…"), "", true);
                new Sheet(this).setTitle(I18n.t("Chia sẻ lên bảng tin")).setView(form)
                    .setPositiveButton(I18n.t("Chia sẻ"),
                        (d, w) -> request("POST", "/api/posts/" + post.optString("id") + "/share",
                            json("body", cap.getText().toString().trim()), r -> {
                              say(I18n.t("Đã chia sẻ bài viết lên bảng tin."));
                              refreshAfterPostMutation();
                            }))
                    .setNegativeButton(I18n.t("Huỷ"), null).show();
              } else if (choice == 2) {
                ((android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE))
                    .setPrimaryClip(ClipData.newPlainText("Kinnect", url));
                say(I18n.t("Đã sao chép liên kết."));
              } else if (choice == 3) {
                Intent send = new Intent(Intent.ACTION_SEND);
                send.setType("text/plain");
                send.putExtra(Intent.EXTRA_TEXT, url);
                startActivity(Intent.createChooser(send, I18n.t("Chia sẻ bài viết")));
              } else
                request("GET", "/api/friends", null, data -> {
                  JSONArray users = data.optJSONArray("users");
                  if (users == null || users.length() == 0) {
                    say(I18n.t("Bạn chưa có bạn bè để chia sẻ."));
                    return;
                  }
                  String[] names = new String[users.length()];
                  for (int i = 0; i < names.length; i++)
                    names[i] = users.optJSONObject(i).optString("name");
                  new Sheet(this).setTitle(I18n.t("Gửi cho bạn bè")).setItemIcon("user_round")
                      .setItems(names,
                          (d, w) -> request("POST",
                              "/api/users/" + users.optJSONObject(w).optString("id") + "/messages", json("body", url),
                              result -> say(I18n.t("Đã chia sẻ bài viết."))))
                      .show();
                });
            })
        .show();
  }

  private LinearLayout actionButton(String iconName, String emoji, String text, boolean active) {
    LinearLayout b = row();
    b.setGravity(Gravity.CENTER);
    if (emoji != null && iconName == null) {
      String code = Integer.toHexString(emoji.codePointAt(0));
      if ("1f606".equals(code))
        code = "1f602";
      int resource = getResources().getIdentifier("emoji_noto_" + code, "drawable", getPackageName());
      if (resource != 0) {
        ImageView e = new ImageView(this);
        e.setImageResource(resource);
        e.setScaleType(ImageView.ScaleType.FIT_CENTER);
        b.addView(e, new LinearLayout.LayoutParams(dp(20), dp(20)));
      } else {
        TextView e = label(emoji, 17, TEXT);
        e.setPadding(0, 0, 0, 0);
        b.addView(e, new LinearLayout.LayoutParams(dp(24), dp(24)));
      }
    } else {
      ImageView i = icon(iconName, 20, active ? ACCENT_TEXT : TEXT);
      b.addView(i, new LinearLayout.LayoutParams(dp(20), dp(20)));
    }
    TextView t = label(text, 14, active ? ACCENT_TEXT : TEXT);
    t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
    t.setPadding(dp(8), 0, 0, 0);
    b.addView(t);
    b.setMinimumHeight(UiMetrics.dpRaw(this, 48));
    b.setBackground(pressable(active ? PRIMARY_SOFT : CARD, 12));
    b.setContentDescription(text);
    tactile(b);
    return b;
  }

  private void refreshReaction(JSONObject p, LinearLayout react, JSONObject d) {
    try {
      p.put("liked", d.optBoolean("liked"));
      p.put("likes", d.optInt("likes"));
      p.put("myReaction", d.isNull("myReaction") ? "" : d.optString("myReaction"));
      if (d.optJSONObject("reactions") != null)
        p.put("reactions", d.optJSONObject("reactions"));
    } catch (JSONException ignored) {
    }
    String key = p.optString("myReaction");
    String glyph = null;
    for (String[] r : REACTIONS)
      if (r[0].equals(key))
        glyph = r[1];
    boolean on = glyph != null;
    react.removeAllViews();
    LinearLayout fresh = actionButton(on ? null : "smile", glyph, on ? reactionName(key) : I18n.t("Cảm xúc"), on);
    if (on && android.animation.ValueAnimator.areAnimatorsEnabled()) {
      react.setScaleX(0.8f);
      react.setScaleY(0.8f);
      react.animate().scaleX(1.12f).scaleY(1.12f).setDuration(120)
          .withEndAction(() -> react.animate().scaleX(1f).scaleY(1f).setDuration(140).start()).start();
    }
    while (fresh.getChildCount() > 0) {
      View v = fresh.getChildAt(0);
      fresh.removeViewAt(0);
      react.addView(v);
    }
    react.setBackground(fresh.getBackground());
    react.setContentDescription(fresh.getContentDescription());
    if (react.getTag() instanceof TextView)
      ((TextView) react.getTag()).setText(reactionSummary(p));
  }

  private void postComments(final JSONObject p) {
    remember("comments:" + p.optString("id"), () -> postComments(p));
    accountHeader(I18n.t("Bình luận"), () -> navigate("feed"), false);
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
      video.setOnPreparedListener(mp -> {
        mp.setLooping(true);
        video.seekTo(1);
      });
      video.setOnClickListener(v -> {
        if (video.isPlaying())
          video.pause();
        else if (!mediaCallBlocked)
          video.start();
      });
      MediaController controls = new MediaController(this);
      controls.setAnchorView(video);
      video.setMediaController(controls);
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
    final int generation = screen;
    MediaImageLoader.displayImage(this, api, url, image, 1280, () -> screen == generation);
  }

  private void openPhoto(String url, final Runnable back) {
    remember("photo:" + url, () -> openPhoto(url, back));
    shell("", false);
    toolbar.setVisibility(View.GONE);
    if (root.getChildCount() > 1)
      root.getChildAt(1).setVisibility(View.GONE);
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
    close.setBackground(background(0xbf141418, 99));
    close.addView(icon("x", 20, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    close.setContentDescription(I18n.t("Đóng"));
    close.setOnClickListener(v -> back.run());
    close.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    FrameLayout closeWrap = UiMetrics.wrapMinTouchTarget(this, close, 48);
    FrameLayout.LayoutParams cp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.START);
    cp.setMargins(dp(12), dp(12), 0, 0);
    stage.addView(closeWrap, cp);
    content.addView(stage, new LinearLayout.LayoutParams(-1, getResources().getDisplayMetrics().heightPixels - dp(60)));
  }

  private void openAttachment(JSONObject file) {
    if (file.optString("kind").equals("image") || file.optString("kind").equals("video")) {
      final Runnable back = currentPage == null ? () -> navigate("inbox") : currentPage;
      remember("attachment:" + file.optString("url"), () -> openAttachment(file));
      accountHeader(file.optString("name"), back, false);
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
    try {
      startActivityForResult(save, 309);
    } catch (Exception error) {
      pendingDownload = "";
      say(I18n.t("Chưa mở được trình lưu tệp."));
    }
  }

  // ----- Tin 24 giờ
  private void stories() {
    final LinearLayout strip = row();
    strip.setGravity(Gravity.TOP);
    strip.setPadding(dp(2), dp(6), dp(2), dp(10));
    strip.addView(storyBubble(me, "Tạo tin", true, () -> createStory()));
    View scroller = hscroll(strip);
    content.addView(scroller, new LinearLayout.LayoutParams(-1, -2));
    cachedRequest("/api/stories", d -> {
      while (strip.getChildCount() > 1)
        strip.removeViewAt(strip.getChildCount() - 1);
      final JSONArray stories = d.optJSONArray("stories");
      Set<String> authors = new HashSet<>();
      for (int i = 0; stories != null && i < stories.length(); i++) {
        JSONObject st = stories.optJSONObject(i);
        JSONObject auth = st == null ? null : st.optJSONObject("author");
        if (st == null || auth == null || !authors.add(auth.optString("id")))
          continue;
        final int index = i;
        strip.addView(storyBubble(auth, auth.optString("name"), false, () -> story(stories, index)));
      }
    }, () -> {
    });
  }

  private LinearLayout storyBubble(JSONObject u, String caption, boolean mine, Runnable open) {
    LinearLayout b = column();
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    FrameLayout ring = new FrameLayout(this);
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
        mine ? new int[] { LINE, LINE } : new int[] { ACCENT, PINK });
    g.setShape(GradientDrawable.OVAL);
    ring.setBackground(g);
    FrameLayout inner = new FrameLayout(this);
    GradientDrawable w = new GradientDrawable();
    w.setShape(GradientDrawable.OVAL);
    w.setColor(CARD);
    inner.setBackground(w);
    LinearLayout holder = new LinearLayout(this);
    ImageView storyAvatar = avatar(u, holder, 52);
    storyAvatar.setForeground(null);
    inner.addView(holder, new FrameLayout.LayoutParams(dp(52), dp(52), Gravity.CENTER));
    ring.addView(inner, new FrameLayout.LayoutParams(dp(57), dp(57), Gravity.CENTER));
    FrameLayout bubbleBox = new FrameLayout(this);
    bubbleBox.addView(ring, new FrameLayout.LayoutParams(dp(62), dp(62), Gravity.CENTER));
    if (mine) {
      FrameLayout plus = new FrameLayout(this);
      GradientDrawable pb = background(ACCENT, 99);
      pb.setStroke(dp(2), CARD);
      plus.setBackground(pb);
      plus.addView(icon("plus", 12, WHITE), new FrameLayout.LayoutParams(dp(12), dp(12), Gravity.CENTER));
      bubbleBox.addView(plus, new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.BOTTOM | Gravity.END));
    }
    b.addView(bubbleBox, new LinearLayout.LayoutParams(dp(62), dp(62)));
    TextView t = label(caption, 12, mine ? ACCENT_TEXT : TEXT);
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

  // Xem tin toàn màn: thanh tiến trình, avatar · tên · thời gian, chạm trái/phải
  // để chuyển, tự chuyển sau 6 giây.
  private void story(final JSONArray stories, final int index) {
    if (index < 0) {
      story(stories, 0);
      return;
    }
    if (index >= stories.length()) {
      navigate("feed");
      return;
    }
    final JSONObject st = stories.optJSONObject(index);
    shell("", false);
    root.removeAllViews();
    root.setOnApplyWindowInsetsListener(null);
    root.setPadding(0, 0, 0, 0);
    root.setBackgroundColor(0xff000000);
    getWindow().setStatusBarColor(Color.TRANSPARENT);
    getWindow().setNavigationBarColor(0xff000000);
    getWindow().getDecorView()
        .setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);
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
        if (generation != screen)
          return;
        if (stopped)
          resumeVideos.add(video);
        else if (!paused[0])
          if (!mediaCallBlocked)
            video.start();
      });
      video.setOnCompletionListener(mp -> {
        if (generation == screen && !stopped && !paused[0])
          story(stories, index + 1);
      });
      stage.addView(video, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
      duration = 0;
    } else if (media != null) {
      final ImageView img = new ImageView(this);
      img.setScaleType(ImageView.ScaleType.FIT_CENTER);
      stage.addView(img, new FrameLayout.LayoutParams(-1, -1));
      MediaImageLoader.displayImage(this, api, media.optString("url"), img, 1440, () -> screen == generation);
    } else {
      stage.setBackground(
          new GradientDrawable(GradientDrawable.Orientation.TL_BR, WebDesign.PURPLE_HERO));
    }
    if (!st.optString("body").isEmpty()) {
      TextView body = label(st.optString("body"), media == null ? 26 : 17, WHITE);
      body.setTypeface(null, Typeface.BOLD);
      body.setGravity(Gravity.CENTER);
      body.setShadowLayer(4, 0, 1, 0x66000000);
      body.setPadding(dp(24), dp(10), dp(24), dp(10));
      body.setBackground(background(media != null ? 0xbf141418 : 0x77141418, 14));
      FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-2, -2,
          media == null ? Gravity.CENTER : Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
      bp.setMargins(dp(20), 0, dp(20), dp(80));
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
    top.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
        new int[] { 0xcc141418, 0xb3141418, 0x00000000 }));
    top.setPadding(dp(10), dp(36), dp(10), dp(16));
    stage.setOnApplyWindowInsetsListener((v, i) -> {
      top.setPadding(dp(10), i.getSystemWindowInsetTop() + dp(10), dp(10), dp(16));
      return i;
    });
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
    TextView when = label("  " + ago(st.optLong("created")), 13, WHITE);
    when.setShadowLayer(4, 0, 1, 0xcc000000);
    who.addView(when, new LinearLayout.LayoutParams(0, -2, 1));
    FrameLayout close = new FrameLayout(this);
    close.setBackground(background(0xbf141418, 99));
    close.addView(icon("close", 22, WHITE), new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
    close.setContentDescription(I18n.t("Đóng tin"));
    close.setOnClickListener(v -> navigate("feed"));
    close.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    who.addView(UiMetrics.wrapMinTouchTarget(this, close, 48));
    top.addView(who);
    stage.addView(top, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
    final long interval = duration;
    final Runnable advance = () -> {
      if (generation == screen && !stopped && !paused[0])
        story(stories, index + 1);
    };
    if (interval > 0) {
      resumeStory = () -> {
        if (generation == screen && !paused[0] && !mediaCallBlocked) {
          handler.removeCallbacks(advance);
          handler.postDelayed(advance, interval);
        }
      };
      resumeStory.run();
    }
    if (!author.optString("id").equals(me.optString("id"))) {
      request("POST", "/api/stories/" + st.optString("id") + "/view", json(), ignored -> {
      });
      LinearLayout storyActions = row();
      storyActions.setGravity(Gravity.CENTER_VERTICAL);
      storyActions.setPadding(dp(12), dp(8), dp(12), dp(14));
      storyActions.setBackground(
          new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x00000000, 0xbf141418 }));
      TextView replyPill = label(I18n.t("Gửi tin nhắn…"), 14, WHITE);
      replyPill.setGravity(Gravity.CENTER_VERTICAL);
      replyPill.setPadding(dp(16), 0, dp(16), 0);
      GradientDrawable pillBg = background(0xbf141418, 999);
      pillBg.setStroke(dp(1), 0x88ffffff);
      replyPill.setBackground(pillBg);
      replyPill.setOnClickListener(v -> {
        paused[0] = true;
        handler.removeCallbacks(advance);
        EditText replyInput = new KinnectInput(this);
        replyInput.setHint(I18n.t("Trả lời tin của ") + author.optString("name"));
        styleChatName(replyInput);
        Dialog dlg = new Sheet(this).setTitle(I18n.t("Trả lời tin")).setView(chatNameWrap(replyInput))
            .setPositiveButton(I18n.t("Gửi"), (d, w) -> {
              String msg = replyInput.getText().toString().trim();
              if (!msg.isEmpty())
                request("POST", "/api/users/" + author.optString("id") + "/messages",
                    json("body", msg), r -> say(I18n.t("Đã gửi phản hồi tin.")));
            })
            .setNegativeButton(I18n.t("Hủy"), null).show();
        dlg.setOnDismissListener(ignored -> {
          paused[0] = false;
          if (resumeStory != null)
            resumeStory.run();
        });
      });
      storyActions.addView(replyPill, new LinearLayout.LayoutParams(0, Math.max(dp(44), UiMetrics.dpRaw(this, 48)), 1));
      UiMetrics.enforceMinTouchTarget(replyPill, 48);
      for (final String reactEm : new String[] { "❤️", "🔥", "👏" }) {
        TextView re = label(reactEm, 20, WHITE);
        re.setGravity(Gravity.CENTER);
        re.setBackground(pressable(0xbf141418, 99));
        re.setPadding(0, 0, 0, 0);
        re.setContentDescription(I18n.t("Thả cảm xúc ") + reactEm);
        re.setOnClickListener(v -> {
          request("POST", "/api/users/" + author.optString("id") + "/messages", json("body", reactEm),
              r -> say(I18n.t("Đã thả cảm xúc ") + reactEm));
        });
        LinearLayout.LayoutParams rep = new LinearLayout.LayoutParams(UiMetrics.dpRaw(this, 48),
            UiMetrics.dpRaw(this, 48));
        rep.leftMargin = dp(6);
        storyActions.addView(re, rep);
        UiMetrics.enforceMinTouchTarget(re, 48);
      }
      FrameLayout moreStory = new FrameLayout(this);
      moreStory.setBackground(pressable(0xbf141418, 99));
      moreStory.addView(icon("more", 20, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
      moreStory.setContentDescription(I18n.t("Tùy chọn"));
      moreStory.setOnClickListener(v -> report("story", st.optString("id")));
      moreStory.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
      storyActions.addView(UiMetrics.wrapMinTouchTarget(this, moreStory, 48));
      stage.addView(storyActions, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
    } else {
      LinearLayout viewers = row();
      viewers.setPadding(dp(12), 0, dp(12), 0);
      viewers.setBackground(background(0xbf141418, 99));
      viewers.addView(icon("eye", 20, WHITE), new LinearLayout.LayoutParams(dp(20), dp(20)));
      final TextView count = label(" " + st.optInt("viewCount"), 13, WHITE);
      viewers.addView(count);
      viewers.setContentDescription(I18n.t("Xem người đã xem tin"));
      viewers.setOnClickListener(v -> {
        paused[0] = true;
        handler.removeCallbacks(advance);
        if (storyPlayer[0] != null)
          storyPlayer[0].pause();
        final Runnable resume = () -> {
          paused[0] = false;
          if (generation != screen || stopped)
            return;
          if (storyPlayer[0] != null) {
            if (!mediaCallBlocked)
              storyPlayer[0].start();
          } else if (resumeStory != null) {
            resumeStory.run();
          }
        };
        final boolean[] opened = { false };
        request("GET", "/api/stories/" + st.optString("id") + "/viewers", null, result -> {
          JSONArray users = result.optJSONArray("viewers");
          count.setText(" " + result.optInt("count"));
          LinearLayout list = column();
          final Dialog[] dialog = { null };
          for (int i = 0; users != null && i < users.length(); i++) {
            final JSONObject u = users.optJSONObject(i);
            LinearLayout row = row();
            row.setPadding(dp(4), dp(6), dp(4), dp(6));
            avatar(u, row, 40);
            TextView name2 = label(u.optString("name"), 14, TEXT);
            name2.setPadding(dp(10), 0, 0, 0);
            row.addView(name2, new LinearLayout.LayoutParams(0, -2, 1));
            row.setOnClickListener(view -> {
              dialog[0].dismiss();
              person(u);
            });
            list.addView(row);
            UiMetrics.enforceMinTouchTarget(row, 48);
          }
          if (users == null || users.length() == 0)
            list.addView(label(I18n.t("Chưa có người xem"), 14, MUTED));
          ScrollView scroll = new ScrollView(this);
          scroll.addView(list);
          scroll.setLayoutParams(new LinearLayout.LayoutParams(-1,
              Math.min(dp(360), Math.max(dp(56), (users == null ? 0 : users.length()) * dp(56)))));
          dialog[0] = new Sheet(this).setTitle(I18n.t("Người xem tin")).setView(scroll)
              .setNegativeButton(I18n.t("Đóng"), null).show();
          opened[0] = true;
          dialog[0].setOnDismissListener(ignored -> resume.run());
        }, () -> {
          if (!opened[0])
            resume.run();
        });
      });
      FrameLayout.LayoutParams vp = new FrameLayout.LayoutParams(-2, Math.max(dp(44), UiMetrics.dpRaw(this, 48)),
          Gravity.BOTTOM | Gravity.START);
      vp.setMargins(dp(16), 0, 0, dp(12));
      stage.addView(viewers, vp);
      UiMetrics.enforceMinTouchTarget(viewers, 48);
    }
  }

  // ----- Tin tức
  private void inboxRow(LinearLayout parent, JSONObject u, String title, String subtitle, int unread, Runnable open) {
    LinearLayout r = row();
    r.setPadding(dp(12), dp(10), dp(12), dp(10));
    r.setBackground(background(CARD, 16));
    if (u != null)
      avatar(u, r, 46);
    else {
      FrameLayout g = new FrameLayout(this);
      g.setBackground(background(PRIMARY_SOFT, 99));
      g.addView(icon("users_round", 22, ACCENT_TEXT), new FrameLayout.LayoutParams(dp(22), dp(22), Gravity.CENTER));
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
      badge.setBackground(background(WebDesign.LIVE_RED, 99));
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
          if (user != null && seen.add(user.optString("id")))
            users.put(user);
        }
      }
      if (users.length() == 0) {
        say(I18n.t("Kết bạn hoặc bắt đầu một cuộc trò chuyện để tạo nhóm."));
        return;
      }
      chooseGroupMembers(users);
    });
  }

  private void chooseGroupMembers(final JSONArray users) {
    final String[] names = new String[users.length()];
    final boolean[] chosen = new boolean[users.length()];
    for (int i = 0; i < names.length; i++)
      names[i] = users.optJSONObject(i).optString("name");
    final EditText name = new KinnectInput(this);
    styleChatName(name);
    name.setHint(I18n.t("Tên nhóm"));
    new Sheet(this).setTitle(I18n.t("Chọn thành viên")).setMultiChoiceItems(names, chosen, (d, w, c) -> chosen[w] = c)
        .setPositiveButton(I18n.t("Tiếp"), (d, w) -> new Sheet(this).setTitle(I18n.t("Tên nhóm"))
            .setView(chatNameWrap(name)).setPositiveButton(I18n.t("Tạo nhóm"), (d2, w2) -> {
              JSONArray ids = new JSONArray();
              for (int i = 0; i < chosen.length; i++)
                if (chosen[i])
                  ids.put(users.optJSONObject(i).optString("id"));
              request("POST", "/api/groups", json("name", name.getText().toString(), "members", ids),
                  r -> groupChat(r.optJSONObject("group")));
            }).setNegativeButton(I18n.t("Hủy"), null).show())
        .setNegativeButton(I18n.t("Hủy"), null).show();
  }

  // ----- Chọn tệp: 300 ảnh/video bài viết · 303 tệp tin nhắn · 304 tin 24h · 305
  // nhạc (quản trị)
  private void pickFile(int code, String types) {
    Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    pick.addCategory(Intent.CATEGORY_OPENABLE);
    if (types.contains("|")) {
      pick.setType("*/*");
      pick.putExtra(Intent.EXTRA_MIME_TYPES, new String[] { "image/*", "video/*" });
    } else
      pick.setType(types);
    try {
      startActivityForResult(pick, code);
    } catch (Exception e) {
      say(I18n.t("Không mở được trình chọn tệp."));
    }
  }

  private boolean preparingPostMedia = false;

  private static String mediaFailure(Exception error) {
    if (error instanceof SecurityException)
      return I18n.t("Không có quyền đọc tệp. Hãy chọn lại video từ Thư viện hoặc Tệp trên máy.");
    String message = error.getMessage();
    return message == null || message.trim().isEmpty()
        ? I18n.t("Không đọc được tệp đã chọn. Hãy tải tệp về máy và chọn lại.")
        : message;
  }

  private void preparePostMedia(final int code, final android.net.Uri uri) {
    if (preparingPostMedia) {
      say(I18n.t("Đang chuẩn bị ảnh/video, vui lòng chờ."));
      return;
    }
    preparingPostMedia = true;
    final int generation = screen;
    say(I18n.t("Đang chuẩn bị ảnh/video…"));
    new Thread(() -> {
      try {
        final NativeMedia.Prepared selected = NativeMedia.read(this, uri, false);
        final String media = selected.dataUrl();
        final Bitmap preview;
        if (selected.video())
          preview = null;
        else {
          BitmapFactory.Options options = new BitmapFactory.Options();
          options.inJustDecodeBounds = true;
          BitmapFactory.decodeByteArray(selected.bytes, 0, selected.bytes.length, options);
          options.inSampleSize = 1;
          while (Math.max(options.outWidth, options.outHeight) / options.inSampleSize > 1080)
            options.inSampleSize *= 2;
          options.inJustDecodeBounds = false;
          preview = BitmapFactory.decodeByteArray(selected.bytes, 0, selected.bytes.length, options);
        }
        runOnUiThread(() -> {
          if (generation != screen || isDestroyed()) {
            if (preview != null)
              preview.recycle();
            return;
          }
          preparingPostMedia = false;
          if (code == 300) {
            pendingMedia = media;
            if (attachButton != null)
              attachButton.setText(selected.video() ? I18n.t("✓ Đã chọn video") : I18n.t("✓ Đã chọn ảnh"));
            composeAttached(preview, selected.video());
          } else {
            EditText caption = new KinnectInput(this);
            caption.setHint(I18n.t("Viết gì đó cho tin (không bắt buộc)"));
            new Sheet(this).setTitle(I18n.t("Đăng tin 24 giờ")).setView(caption)
                .setPositiveButton(I18n.t("Đăng"), (d, w) -> {
                  say(I18n.t("Đang đăng tin…"));
                  request("POST", "/api/stories", json("body", caption.getText().toString(), "media", media), r -> {
                    say(I18n.t("Đã đăng tin."));
                    navigate("feed");
                  });
                }).setNegativeButton(I18n.t("Hủy"), null).show();
          }
        });
      } catch (OutOfMemoryError error) {
        runOnUiThread(() -> {
          if (generation == screen) {
            preparingPostMedia = false;
            say(I18n.t("Thiết bị không đủ bộ nhớ để chuẩn bị tệp này."));
          }
        });
      } catch (Exception error) {
        final String reason = mediaFailure(error);
        runOnUiThread(() -> {
          if (generation == screen) {
            preparingPostMedia = false;
            say(reason);
          }
        });
      }
    }, "kinnect-prepare-media").start();
  }

  private static final class CompressedImage {
    final byte[] bytes;
    final String dataUrl;

    CompressedImage(byte[] bytes, String dataUrl) {
      this.bytes = bytes;
      this.dataUrl = dataUrl;
    }
  }

  private CompressedImage compressImageForUpload(android.net.Uri uri, int maxSide, int maxBytes) throws Exception {
    String type = getContentResolver().getType(uri);
    byte[] raw = NativeApi.read(getContentResolver().openInputStream(uri), 20 * 1024 * 1024);
    if (raw == null || raw.length == 0)
      throw new java.io.IOException("Empty image");
    if (raw.length <= maxBytes && Arrays.asList("image/png", "image/jpeg", "image/webp").contains(type)) {
      BitmapFactory.Options bounds = new BitmapFactory.Options();
      bounds.inJustDecodeBounds = true;
      BitmapFactory.decodeByteArray(raw, 0, raw.length, bounds);
      if (bounds.outWidth > 0 && bounds.outHeight > 0 && Math.max(bounds.outWidth, bounds.outHeight) <= maxSide) {
        return new CompressedImage(raw,
            "data:" + type + ";base64," + android.util.Base64.encodeToString(raw, android.util.Base64.NO_WRAP));
      }
    }
    BitmapFactory.Options o = new BitmapFactory.Options();
    o.inJustDecodeBounds = true;
    BitmapFactory.decodeByteArray(raw, 0, raw.length, o);
    if (o.outWidth <= 0 || o.outHeight <= 0)
      throw new java.io.IOException("Invalid image");
    o.inSampleSize = 1;
    while (Math.max(o.outWidth, o.outHeight) / o.inSampleSize > maxSide * 2) {
      o.inSampleSize *= 2;
    }
    o.inJustDecodeBounds = false;
    Bitmap decoded = BitmapFactory.decodeByteArray(raw, 0, raw.length, o);
    if (decoded == null)
      throw new java.io.IOException("Decode failed");
    try {
      if (Build.VERSION.SDK_INT >= 24) {
        android.media.ExifInterface exif = new android.media.ExifInterface(new java.io.ByteArrayInputStream(raw));
        int orient = exif.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION,
            android.media.ExifInterface.ORIENTATION_NORMAL);
        Matrix m = new Matrix();
        if (orient == android.media.ExifInterface.ORIENTATION_ROTATE_90)
          m.postRotate(90);
        else if (orient == android.media.ExifInterface.ORIENTATION_ROTATE_180)
          m.postRotate(180);
        else if (orient == android.media.ExifInterface.ORIENTATION_ROTATE_270)
          m.postRotate(270);
        if (!m.isIdentity()) {
          Bitmap rot = Bitmap.createBitmap(decoded, 0, 0, decoded.getWidth(), decoded.getHeight(), m, true);
          if (rot != decoded) {
            decoded.recycle();
            decoded = rot;
          }
        }
      }
    } catch (Exception ignored) {
    }
    int w = decoded.getWidth(), h = decoded.getHeight();
    if (Math.max(w, h) > maxSide) {
      float scale = maxSide / (float) Math.max(w, h);
      int nw = Math.max(1, Math.round(w * scale)), nh = Math.max(1, Math.round(h * scale));
      Bitmap scaled = Bitmap.createScaledBitmap(decoded, nw, nh, true);
      if (scaled != decoded) {
        decoded.recycle();
        decoded = scaled;
      }
    }
    java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
    int quality = 88;
    decoded.compress(Bitmap.CompressFormat.JPEG, quality, baos);
    while (baos.size() > maxBytes && quality > 36) {
      baos.reset();
      quality -= 10;
      decoded.compress(Bitmap.CompressFormat.JPEG, quality, baos);
    }
    decoded.recycle();
    byte[] outBytes = baos.toByteArray();
    if (outBytes.length > maxBytes)
      throw new java.io.IOException("Image too large");
    return new CompressedImage(outBytes,
        "data:image/jpeg;base64," + android.util.Base64.encodeToString(outBytes, android.util.Base64.NO_WRAP));
  }

  private String dataUrl(android.net.Uri uri, int max, String forcedType) throws Exception {
    byte[] bytes = NativeApi.read(getContentResolver().openInputStream(uri), max);
    String type = forcedType != null ? forcedType : getContentResolver().getType(uri);
    if (type == null)
      type = "application/octet-stream";
    return "data:" + type + ";base64," + android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP);
  }

  private String fileName(android.net.Uri uri) {
    try (android.database.Cursor c = getContentResolver().query(uri,
        new String[] { android.provider.OpenableColumns.DISPLAY_NAME }, null, null, null)) {
      if (c != null && c.moveToFirst())
        return c.getString(0);
    } catch (Exception ignored) {
    }
    return "tep-dinh-kem";
  }

  private void picked(final int code, final android.net.Uri uri) {
    final String type = getContentResolver().getType(uri);
    try {
      if (code == 300 || code == 304) {
        reviewMedia(uri, code == 304 ? 211 : 210);
        return;
      }
      if (code == 303) {
        final String name = fileName(uri);
        final String target = attachTarget;
        final int generation = screen;
        say(I18n.t("Đang chuẩn bị và gửi tệp…"));
        new Thread(() -> {
          try {
            final String encoded = dataUrl(uri, 20 * 1024 * 1024, null);
            final JSONObject file = json("name", name, "data", encoded);
            runOnUiThread(() -> {
              if (isFinishing() || isDestroyed() || generation != screen)
                return;
              request("POST", target, json("body", "", "attachment", file), d -> {
                say(I18n.t("Đã gửi tệp."));
                if (chatReload != null)
                  chatReload.run();
                else
                  navigate("inbox");
              });
            });
          } catch (Exception | OutOfMemoryError e) {
            runOnUiThread(() -> {
              if (!isDestroyed())
                say(I18n.t("Không gửi được tệp (tối đa 20 MB)."));
            });
          }
        }, "kinnect-chat-attach").start();
        return;
      }
      if (code == 308) {
        if (type != null && !type.startsWith("image/")) {
          say(I18n.t("Chọn ảnh PNG/JPEG/WebP."));
          return;
        }
        final int generation = screen;
        say(I18n.t("Đang tải ảnh riêng tư…"));
        new Thread(() -> {
          try {
            final CompressedImage img = compressImageForUpload(uri, 1920, 3800 * 1024);
            runOnUiThread(() -> {
              if (isFinishing() || isDestroyed() || generation != screen)
                return;
              request("POST", "/api/me/private-photos", json("data", img.dataUrl), result -> privateAlbum(me));
            });
          } catch (Exception | OutOfMemoryError e) {
            runOnUiThread(() -> {
              if (!isDestroyed())
                say(I18n.t("Không tải được ảnh riêng tư."));
            });
          }
        }, "kinnect-private-photo").start();
        return;
      }
      if (code == 305) {
        uploadMusic(uri);
        return;
      }
      if (code == 306 || code == 302) {
        if (type != null && !type.startsWith("image/")) {
          say(I18n.t("Chọn ảnh PNG/JPEG/WebP."));
          return;
        }
        final int generation = screen;
        say(I18n.t("Đang chuẩn bị ảnh bìa…"));
        new Thread(() -> {
          try {
            final CompressedImage img = compressImageForUpload(uri, 1280, 920 * 1024);
            runOnUiThread(() -> {
              if (isFinishing() || isDestroyed() || generation != screen)
                return;
              request("POST", "/api/me/cover", json("data", img.dataUrl), d -> {
                say(I18n.t("Đã đổi ảnh bìa."));
                if (profileEditorAvatar == null || !profileEditorAvatar.isAttachedToWindow())
                  navigate("profile");
              });
            });
          } catch (Exception | OutOfMemoryError e) {
            runOnUiThread(() -> {
              if (!isDestroyed())
                say(I18n.t("Máy chủ chưa nhận được ảnh bìa."));
            });
          }
        }, "kinnect-cover-upload").start();
      }
    } catch (Exception e) {
      say(code == 308 ? I18n.t("Không tải được ảnh riêng tư.")
          : code == 303 ? I18n.t("Không gửi được tệp.") : I18n.t("Máy chủ chưa nhận được tệp media."));
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
        if (!r.optString("status").equals("open"))
          continue;
        open++;
        LinearLayout c = column();
        c.setPadding(dp(14), dp(12), dp(14), dp(12));
        c.setBackground(background(CARD, 16));
        c.addView(
            label("@" + r.optString("username") + (r.isNull("user_id") ? I18n.t(" · không tồn tại") : ""), 16, TEXT));
        c.addView(label(I18n.t("Liên hệ: ") + r.optString("contact")
            + (r.optString("note").isEmpty() ? "" : "\n" + r.optString("note")), 13, MUTED));
        LinearLayout acts = row();
        if (!r.isNull("user_id"))
          acts.addView(chip("Cấp mật khẩu tạm", true,
              () -> confirm(I18n.t("Cấp mật khẩu tạm cho @") + r.optString("username") + "?",
                  () -> request("POST", "/api/admin/password-resets/" + r.optString("id") + "/reset", json(),
                      x -> new Sheet(this).setTitle(I18n.t("Mật khẩu tạm"))
                          .setMessage("@" + x.optString("username") + ": " + x.optString("temporaryPassword")
                              + I18n.t("\n\nGửi riêng cho người dùng và nhắc họ đổi mật khẩu ngay."))
                          .setPositiveButton("Xong", (dd, ww) -> admin()).show()))));
        acts.addView(chip("Bỏ qua", false, () -> request("POST",
            "/api/admin/password-resets/" + r.optString("id") + "/dismiss", json(), x -> admin())));
        c.addView(acts);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        box.addView(c, p);
      }
      if (open == 0)
        box.addView(label(I18n.t("Không có yêu cầu mới."), 14, MUTED));
    });
  }

  private android.media.MediaPlayer adminPlayer;

  private void adminMusic() {
    final LinearLayout box = column();
    content.addView(box);
    api.call("GET", "/api/music", null, (d, e, s) -> {
      if (isDestroyed())
        return;
      box.addView(label(I18n.t("Thư viện nhạc"), 18, TEXT));
      JSONArray tracks = d == null ? null : d.optJSONArray("tracks");
      if (tracks == null || tracks.length() == 0)
        box.addView(label(I18n.t("Chưa có bài nào."), 14, MUTED));
      for (int i = 0; tracks != null && i < tracks.length(); i++) {
        final JSONObject t = tracks.optJSONObject(i);
        LinearLayout r = row();
        r.setPadding(dp(10), dp(6), dp(10), dp(6));
        r.setBackground(background(CARD, 14));
        r.addView(chip("▶ " + I18n.t("Nghe"), false, () -> {
          try {
            if (adminPlayer != null)
              adminPlayer.release();
            adminPlayer = new android.media.MediaPlayer();
            Map<String, String> headers = new HashMap<>();
            headers.put("Cookie", api.jar());
            adminPlayer.setDataSource(this, android.net.Uri.parse(server() + t.optString("url")), headers);
            adminPlayer.setOnPreparedListener(mp -> mp.start());
            adminPlayer.prepareAsync();
          } catch (Exception ex) {
            say(I18n.t("Không phát được bài này."));
          }
        }));
        LinearLayout tx = column();
        tx.setPadding(dp(8), 0, 0, 0);
        tx.addView(label(t.optString("title"), 15, TEXT));
        tx.addView(label(t.optString("artist") + " · " + t.optString("license"), 11, MUTED));
        r.addView(tx, new LinearLayout.LayoutParams(0, -2, 1));
        r.addView(
            chip("Xoá", false, () -> confirm(I18n.t("Xoá bài “") + t.optString("title") + I18n.t("” khỏi thư viện?"),
                () -> request("DELETE", "/api/music", json("file", t.optString("file")), x -> admin()))));
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        box.addView(r, p);
      }
      box.addView(button(I18n.t("＋ Tải bài nhạc lên (MP3/M4A ≤15 MB)"), () -> pickFile(305, "audio/*")));
    });
  }

  private void uploadMusic(final android.net.Uri uri) throws Exception {
    final String name = fileName(uri);
    final boolean m4a = name.toLowerCase(Locale.ROOT).endsWith(".m4a");
    LinearLayout box = column();
    box.setPadding(dp(20), dp(8), dp(20), 0);
    final EditText title = new KinnectInput(this), artist = new KinnectInput(this), license = new KinnectInput(this),
        source = new KinnectInput(this);
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
    new Sheet(this).setTitle(I18n.t("Thêm bài vào thư viện")).setView(box)
        .setPositiveButton(I18n.t("Tải lên"), (d, w) -> {
          say(I18n.t("Đang tải nhạc lên…"));
          final String titleText = title.getText().toString();
          final String artistText = artist.getText().toString();
          final String licenseText = license.getText().toString();
          final String sourceText = source.getText().toString();
          final boolean rightsChecked = rights.isChecked();
          final int generation = screen;
          new Thread(() -> {
            try {
              final String data = dataUrl(uri, 15 * 1024 * 1024, m4a ? "audio/mp4" : "audio/mpeg");
              runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || generation != screen)
                  return;
                request("POST", "/api/music", json("data", data, "title", titleText, "artist", artistText, "license",
                    licenseText, "source", sourceText, "rights", rightsChecked), r -> {
                      say(I18n.t("Đã thêm bài vào thư viện nhạc."));
                      admin();
                    });
              });
            } catch (Exception | OutOfMemoryError e) {
              runOnUiThread(() -> {
                if (!isDestroyed())
                  say(I18n.t("Chọn tệp âm thanh MP3/M4A nhỏ hơn 15 MB."));
              });
            }
          }, "kinnect-music-upload").start();
        }).setNegativeButton(I18n.t("Hủy"), null).show();
  }

  // ===================== Tin nhắn, nhóm, bình luận nâng cao
  // =====================
  private boolean shortsFollowing = false;
  private long lastActivity = 0;

  private void activity() {
    if (me == null || System.currentTimeMillis() - lastActivity < 60000)
      return;
    lastActivity = System.currentTimeMillis();
    api.call("POST", "/api/me/activity", json(), (d, e, s) -> {
    });
  }

  private String[] reactionGlyphs() {
    String[] names = new String[REACTIONS.length];
    for (int i = 0; i < names.length; i++)
      names[i] = REACTIONS[i][1];
    return names;
  }

  private void forwardMessage(final String source, final JSONObject message) {
    request("GET", "/api/conversations", null,
        conversations -> request("GET", "/api/groups", null, groups -> request("GET", "/api/friends", null, friends -> {
          final List<String> names = new ArrayList<>(), paths = new ArrayList<>();
          final Set<String> seen = new HashSet<>();
          JSONArray[] sets = { conversations.optJSONArray("users"), groups.optJSONArray("groups"),
              friends.optJSONArray("users") };
          for (int k = 0; k < sets.length; k++)
            for (int i = 0; sets[k] != null && i < sets[k].length(); i++) {
              JSONObject target = sets[k].optJSONObject(i);
              if (target == null)
                continue;
              String path = k == 1 ? "/api/groups/" + target.optString("id") + "/messages"
                  : "/api/users/" + target.optString("id") + "/messages";
              if (seen.add(path)) {
                names.add((k == 1 ? "Nhóm · " : "") + target.optString("name"));
                paths.add(path);
              }
            }
          if (names.isEmpty()) {
            say(I18n.t("Chưa có bạn bè hoặc hội thoại để chuyển tiếp."));
            return;
          }
          new Sheet(this).setTitle(I18n.t("Chuyển tiếp tin nhắn")).setItemIcon("user_round")
              .setItems(names.toArray(new String[0]), (dialog, index) -> {
                // Re-read the source so recalled/deleted messages cannot be forwarded from
                // stale UI.
                String verifyPath = source;
                long msgCreated = message.optLong("created", 0);
                if (msgCreated > 0 && !chatOlderMessages.isEmpty()) {
                  verifyPath = source + (source.contains("?") ? "&" : "?") + "limit=100&before=" + (msgCreated + 1);
                }
                request("GET", verifyPath, null, data -> {
                  JSONArray rows = data.optJSONArray("messages");
                  JSONObject current = null;
                  String targetId = message.optString("id");
                  for (int i = 0; rows != null && i < rows.length(); i++) {
                    JSONObject r = rows.optJSONObject(i);
                    if (r != null && r.optString("id").equals(targetId)) {
                      current = r;
                      break;
                    }
                  }
                  if (current == null) {
                    for (JSONObject om : chatOlderMessages) {
                      if (om != null && om.optString("id").equals(targetId)) {
                        current = om;
                        break;
                      }
                    }
                  }
                  if (current == null || current.optBoolean("recalled")) {
                    say(I18n.t("Tin nhắn không còn khả dụng để chuyển tiếp."));
                    return;
                  }
                  final JSONObject payload = json("body", current.optString("body"));
                  final JSONObject file = current.optJSONObject("attachment");
                  Runnable send = () -> request("POST", paths.get(index), payload,
                      sent -> say(I18n.t("Đã chuyển tiếp đến ") + names.get(index)));
                  if (file == null) {
                    send.run();
                    return;
                  }
                  final int generation = screen;
                  api.image(file.optString("url"), bytes -> {
                    if (generation != screen || isDestroyed())
                      return;
                    if (bytes == null || bytes.length > 20 * 1024 * 1024) {
                      say(I18n.t("Không tải được tệp hoặc tệp vượt quá 20 MB."));
                      return;
                    }
                    try {
                      payload.put("attachment",
                          json("name", file.optString("name"), "data",
                              "data:" + file.optString("type", "application/octet-stream") + ";base64,"
                                  + android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)));
                    } catch (JSONException error) {
                      say(I18n.t("Không thể chuẩn bị tệp đính kèm."));
                      return;
                    }
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
    control.setLayoutParams(new LinearLayout.LayoutParams(dp(30), dp(28)));
    return UiMetrics.wrapMinTouchTarget(this, control, 48);
  }

  private android.app.Dialog messageMenu(final String kind, final JSONObject m, boolean own, final String sourcePath,
      final Runnable refresh) {
    if (m.optBoolean("recalled")) {
      return new Sheet(this).setTitle(I18n.t("Tùy chọn tin nhắn")).setItemIcons(new String[] { "trash" })
          .setItems(new String[] { I18n.t("Xoá ở phía bạn") }, (d, w) -> request("DELETE",
              "/api/chat-messages/" + kind + "/" + m.optString("id"), json(), r -> refresh.run()))
          .show();
    }
    final String base = "/api/chat-messages/" + kind + "/" + m.optString("id");
    final List<String> labels = new ArrayList<>(), icons = new ArrayList<>();
    final List<Runnable> actions = new ArrayList<>();
    icons.add("pin");
    labels.add(I18n.t(m.optBoolean("pinned") ? "Bỏ ghim tin nhắn" : "Ghim tin nhắn"));
    actions.add(() -> request(m.optBoolean("pinned") ? "DELETE" : "POST", base + "/pin", json(), r -> refresh.run()));
    icons.add("forward");
    labels.add(I18n.t("Chuyển tiếp tin nhắn"));
    actions.add(() -> forwardMessage(sourcePath, m));
    if (own && !m.optString("body").trim().isEmpty()) {
      icons.add("pencil");
      labels.add(I18n.t("Chỉnh sửa tin nhắn"));
      actions.add(() -> {
        EditText editInput = new KinnectInput(this);
        styleChatName(editInput);
        editInput.setSingleLine(false);
        editInput.setText(decodeEntities(m.optString("body")));
        new Sheet(this).setTitle(I18n.t("Chỉnh sửa tin nhắn")).setView(chatNameWrap(editInput))
            .setAutoDismissPositive(false)
            .setPositiveButton(I18n.t("Lưu"), (d, w) -> {
              String clean = editInput.getText().toString().trim();
              if (clean.isEmpty()) {
                say(I18n.t("Nhập nội dung tin nhắn."));
                return;
              }
              try {
                d.dismiss();
              } catch (Exception ignored) {
              }
              request("PATCH", base, json("body", clean), r -> {
                say(I18n.t("Đã chỉnh sửa tin nhắn"));
                refresh.run();
              });
            })
            .setNegativeButton(I18n.t("Hủy"), null).show();
      });
    }
    if (own) {
      icons.add("recall");
      labels.add(I18n.t("Thu hồi với mọi người"));
      actions.add(() -> confirm(I18n.t("Thu hồi tin nhắn này?"), I18n.t("Thu hồi"),
          () -> request("POST", base + "/recall", json(), r -> refresh.run())));
    }
    icons.add("trash");
    labels.add(I18n.t("Xoá ở phía bạn"));
    actions.add(() -> request("DELETE", base, json(), r -> refresh.run()));
    if (!own) {
      icons.add("flag");
      labels.add(I18n.t("Báo cáo tin nhắn"));
      actions.add(() -> report(kind.equals("group") ? "group_message" : "message", m.optString("id")));
    }
    JSONObject reactions = m.optJSONObject("reactions");
    String title = null;
    if (reactions != null && reactions.length() > 0) {
      StringBuilder b = new StringBuilder();
      for (String[] r : REACTIONS)
        if (reactions.optInt(r[0]) > 0)
          b.append(r[1]).append(" ").append(reactions.optInt(r[0])).append("  ");
      title = b.toString().trim();
    }
    return new Sheet(this).setTitle(title == null ? I18n.t("Tùy chọn tin nhắn") : I18n.t(title))
        .setItemIcons(icons.toArray(new String[0]))
        .setItems(labels.toArray(new String[0]), (d, w) -> actions.get(w).run()).show();
  }

  private View chatNameWrap(EditText input) {
    FrameLayout outer = new FrameLayout(this), inner = new FrameLayout(this);
    inner.addView(input, new FrameLayout.LayoutParams(-1, -2));
    outer.addView(inner, new FrameLayout.LayoutParams(-1, -2));
    return outer;
  }

  private void styleChatName(EditText input) {
    input.setTextSize(15);
    input.setTextColor(TEXT);
    input.setHintTextColor(MUTED);
    input.setSingleLine(true);
    input.setGravity(Gravity.CENTER_VERTICAL);
    input.setPadding(dp(16), dp(12), dp(16), dp(12));
    input.setMinimumHeight(dp(50));
    input.setBackground(outlined(CARD, 14));
  }

  private android.app.Dialog chatActionSheet(String title, List<String> icons, List<String> labels,
      List<Runnable> actions) {
    return chatActionSheet(title, icons, labels, actions, null);
  }

  private android.app.Dialog chatActionSheet(String title, List<String> icons, List<String> labels,
      List<Runnable> actions, final Runnable back) {
    android.app.Dialog sheet = new Sheet(this).setTitle(I18n.t(title)).setItemIcons(icons.toArray(new String[0]))
        .setItems(I18n.items(labels.toArray(new String[0])), (dialog, index) -> actions.get(index).run())
        .setNegativeButton(I18n.t("Quay lại"), (dialog, which) -> {
          if (back != null)
            back.run();
        }).show();
    sheet.setOnCancelListener(dialog -> {
      if (back != null)
        back.run();
    });
    return sheet;
  }

  private void conversationMenu(String kind, String id, String name) {
    conversationMenu(kind, id, name, false);
  }

  private void conversationMenu(final String kind, final String id, final String name, final boolean outside) {
    final String prefs = "/api/chat-preferences/" + kind + "/" + id;
    request("GET", prefs, null, p -> {
      boolean muted = p.optBoolean("muted"), pinned = p.optBoolean("pinned");
      List<String> icons = new ArrayList<>(), labels = new ArrayList<>();
      List<Runnable> actions = new ArrayList<>();
      if (outside) {
        icons.add("mail");
        labels.add(I18n.t("Đánh dấu chưa đọc"));
        actions.add(() -> request("POST", prefs, json("unread", true), r -> navigate("inbox")));
      }
      icons.add("pin");
      labels.add(pinned ? I18n.t("Bỏ ghim") : I18n.t("Ghim hội thoại"));
      actions.add(() -> request("POST", prefs, json("pinned", !pinned), r -> {
        if (outside)
          navigate("inbox");
        else
          say(pinned ? I18n.t("Đã bỏ ghim") : I18n.t("Đã ghim"));
      }));
      icons.add("bell");
      labels.add(muted ? I18n.t("Bật thông báo") : I18n.t("Tắt thông báo"));
      actions.add(() -> request("POST", prefs, json("muted", !muted), r -> {
        if (outside)
          navigate("inbox");
        else
          say(muted ? I18n.t("Đã bật thông báo") : I18n.t("Đã tắt thông báo"));
      }));
      icons.add("eye_off");
      labels.add(I18n.t("Ẩn hội thoại"));
      actions.add(() -> request("POST", prefs, json("hidden", true), r -> navigate("inbox")));
      icons.add("trash");
      labels.add(I18n.t("Xóa hội thoại ở phía bạn"));
      actions.add(() -> confirm(I18n.t("Xóa lịch sử ở phía bạn? Người khác vẫn giữ tin nhắn của họ."), I18n.t("Xóa"),
          () -> request("DELETE",
              kind.equals("direct") ? "/api/users/" + id + "/messages" : "/api/groups/" + id + "/messages", json(),
              r -> navigate("inbox"))));
      final JSONObject parentGroup = currentGroup, parentUser = chatUser;
      Runnable back = outside ? null
          : kind.equals("group") && parentGroup != null ? () -> groupMenu(parentGroup)
              : parentUser != null ? () -> directChatMenu(parentUser) : null;
      chatActionSheet(I18n.t("Cài đặt hội thoại"), icons, labels, actions, back);
    });
  }

  private JSONObject photoGroup;

  private Bitmap groupSample(String preset, int size) {
    int[] colors = preset.equals("ocean") ? new int[] { 0xff0284c7, 0xff22d3ee }
        : preset.equals("sunset") ? new int[] { 0xfff97316, 0xffec4899 }
            : preset.equals("forest") ? new int[] { 0xff059669, 0xff84cc16 } : new int[] { 0xff7c3aed, 0xffc084fc };
    Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
    android.graphics.Canvas c = new android.graphics.Canvas(bitmap);
    android.graphics.Paint paint = new android.graphics.Paint(3);
    paint.setShader(
        new android.graphics.LinearGradient(0, 0, size, size, colors, null, android.graphics.Shader.TileMode.CLAMP));
    c.drawCircle(size / 2f, size / 2f, size / 2f, paint);
    SettingsGlyph glyph = new SettingsGlyph("group_three", WHITE, colors[0]);
    glyph.setBounds(size / 5, size / 5, size * 4 / 5, size * 4 / 5);
    glyph.draw(c);
    return bitmap;
  }

  private void groupPhotoOptions(final JSONObject g) {
    LinearLayout choices = column();
    String[] presets = { "violet", "ocean", "sunset", "forest" },
        names = { "Tím kết nối", "Biển xanh", "Hoàng hôn", "Rừng xanh" };
    final android.app.Dialog[] photoDialog = { null };
    final Sheet sheet = new Sheet(this).setTitle(I18n.t("Ảnh đại diện nhóm"));
    for (int i = 0; i < presets.length; i++) {
      final String preset = presets[i];
      LinearLayout item = row();
      ImageView preview = new ImageView(this);
      preview.setImageBitmap(groupSample(preset, dp(52)));
      item.addView(preview, new LinearLayout.LayoutParams(dp(52), dp(52)));
      TextView title = label(I18n.t(names[i]), 15, TEXT);
      title.setPadding(dp(12), 0, 0, 0);
      item.addView(title);
      item.setPadding(dp(8), dp(8), dp(8), dp(8));
      item.setOnClickListener(v -> {
        if (photoDialog[0] != null)
          photoDialog[0].dismiss();
        request("POST", "/api/groups/" + g.optString("id") + "/avatar", json("preset", preset),
            d -> groupChat(d.optJSONObject("group")));
      });
      choices.addView(item);
    }
    choices.addView(primary(I18n.t("Chọn ảnh từ thư viện"), () -> {
      if (photoDialog[0] != null)
        photoDialog[0].dismiss();
      photoGroup = g;
      pickFile(319, "image/*");
    }));
    photoDialog[0] = sheet.setView(choices).setNegativeButton(I18n.t("Quay lại"), (d, w) -> groupMenu(g)).show();
  }

  private void profileCompletion() {
    if (me == null
        || getSharedPreferences("kinnect_profile", 0).getBoolean("completion_dismissed:" + me.optString("id"), false))
      return;
    String[] keys = { "avatar", "bio", "city", "interests", "lookingFor" },
        titles = { "Ảnh đại diện", "Giới thiệu", "Khu vực", "Sở thích", "Mục đích kết nối" };
    int done = 0;
    List<String> missing = new ArrayList<>();
    for (int i = 0; i < keys.length; i++) {
      Object value = me.opt(keys[i]);
      boolean filled = value instanceof JSONArray ? ((JSONArray) value).length() > 0
          : value != null && value != JSONObject.NULL && !value.toString().trim().isEmpty();
      if (filled)
        done++;
      else
        missing.add(titles[i]);
    }
    if (done == keys.length)
      return;
    final LinearLayout panel = card();
    panel.setPadding(dp(12), dp(5), dp(6), dp(5));
    LinearLayout heading = row();
    heading.setGravity(Gravity.CENTER_VERTICAL);
    TextView caption = label(I18n.t("Hoàn thiện hồ sơ"), 13, TEXT);
    caption.setSingleLine(true);
    caption.setEllipsize(android.text.TextUtils.TruncateAt.END);
    heading.addView(caption, new LinearLayout.LayoutParams(0, -2, 1));
    TextView percent = label(done * 100 / keys.length + "%", 13, ACCENT_TEXT);
    percent.setPadding(dp(6), 0, dp(4), 0);
    heading.addView(percent);
    FrameLayout edit = new FrameLayout(this);
    edit.addView(icon("pencil", 18, ACCENT_TEXT), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    edit.setBackground(pressable(PRIMARY_SOFT, 99));
    edit.setContentDescription(I18n.t("Hoàn thiện hồ sơ"));
    edit.setOnClickListener(v -> editProfile());
    edit.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    heading.addView(UiMetrics.wrapMinTouchTarget(this, edit, 48));
    FrameLayout close = new FrameLayout(this);
    close.addView(icon("close", 17, MUTED), new FrameLayout.LayoutParams(dp(17), dp(17), Gravity.CENTER));
    close.setContentDescription(I18n.t("Đóng gợi ý hoàn thiện hồ sơ"));
    close.setOnClickListener(v -> {
      getSharedPreferences("kinnect_profile", 0).edit().putBoolean("completion_dismissed:" + me.optString("id"), true)
          .apply();
      if (panel.getParent() instanceof ViewGroup)
        ((ViewGroup) panel.getParent()).removeView(panel);
    });
    close.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    heading.addView(UiMetrics.wrapMinTouchTarget(this, close, 48));
    panel.addView(heading);
  }

  private JSONObject currentGroup;

  private void directChatMenu(JSONObject user) {
    List<String> icons = new ArrayList<>(Arrays.asList("search", "user_round", "settings", "flag", "user_block"));
    List<String> labels = new ArrayList<>(Arrays.asList(I18n.t("Tìm tin nhắn"), I18n.t("Xem hồ sơ"),
        I18n.t("Cài đặt hội thoại"), I18n.t("Báo cáo tài khoản"), I18n.t("Chặn tài khoản")));
    List<Runnable> actions = new ArrayList<>();
    actions.add(() -> openChatSearch("/api/users/" + user.optString("id") + "/messages"));
    actions.add(() -> person(user));
    actions.add(() -> conversationMenu("direct", user.optString("id"), user.optString("name")));
    actions.add(() -> report("user", user.optString("id")));
    actions.add(() -> confirm(I18n.t("Chặn ") + user.optString("name") + "?", I18n.t("Chặn"),
        () -> request("POST", "/api/users/" + user.optString("id") + "/block", json(), r -> navigate("inbox"))));
    chatActionSheet(user.optString("name"), icons, labels, actions);
  }

  private String groupRole(JSONObject group, JSONObject member) {
    return member.optString("id").equals(group.optString("owner")) ? "owner" : member.optString("groupRole", "member");
  }

  private boolean groupManager(JSONObject g) {
    if (g.optString("owner").equals(me.optString("id")))
      return true;
    JSONArray members = g.optJSONArray("members");
    for (int i = 0; members != null && i < members.length(); i++)
      if (members.optJSONObject(i).optString("id").equals(me.optString("id")))
        return groupRole(g, members.optJSONObject(i)).equals("deputy");
    return false;
  }

  private void groupMembers(final JSONObject g) {
    accountHeader(I18n.t("Thành viên · ") + g.optString("name"), () -> groupChat(g), false);
    JSONArray members = g.optJSONArray("members");
    for (int i = 0; members != null && i < members.length(); i++) {
      final JSONObject member = members.optJSONObject(i);
      String role = groupRole(g, member);
      inboxRow(content, member, member.optString("name"),
          role.equals("owner") ? "Trưởng nhóm" : role.equals("deputy") ? "Phó nhóm" : "Thành viên", 0,
          () -> groupMemberActions(g, member));
    }
  }

  private void groupMemberActions(final JSONObject g, final JSONObject member) {
    boolean owner = g.optString("owner").equals(me.optString("id")),
        self = member.optString("id").equals(me.optString("id"));
    String role = groupRole(g, member);
    List<String> icons = new ArrayList<>(), labels = new ArrayList<>();
    List<Runnable> actions = new ArrayList<>();
    icons.add("user_round");
    labels.add(I18n.t("Xem hồ sơ"));
    actions.add(() -> person(member));
    if (owner && !self) {
      icons.add("shield_check");
      labels.add(role.equals("deputy") ? "Bỏ vai trò phó nhóm" : "Bổ nhiệm phó nhóm");
      actions.add(() -> confirm(I18n.t("Thay đổi vai trò của ") + member.optString("name") + "?",
          () -> request("PATCH", "/api/groups/" + g.optString("id") + "/roles",
              json("userId", member.optString("id"), "role", role.equals("deputy") ? "member" : "deputy"),
              r -> groupMembers(r.optJSONObject("group")))));
      icons.add("user_check");
      labels.add(I18n.t("Chuyển quyền trưởng nhóm"));
      actions.add(() -> confirm(I18n.t("Chuyển quyền trưởng nhóm cho ") + member.optString("name") + "?",
          () -> request("PATCH", "/api/groups/" + g.optString("id") + "/roles",
              json("userId", member.optString("id"), "role", "owner"), r -> groupMembers(r.optJSONObject("group")))));
    }
    if (!self && !role.equals("owner") && (owner || groupManager(g) && !role.equals("deputy"))) {
      icons.add("user_block");
      labels.add(I18n.t("Xóa khỏi nhóm"));
      actions.add(() -> confirm(I18n.t("Xóa ") + member.optString("name") + I18n.t(" khỏi nhóm?"), I18n.t("Xóa"),
          () -> request("DELETE", "/api/groups/" + g.optString("id") + "/members",
              json("userId", member.optString("id")), r -> groupMembers(r.optJSONObject("group")))));
    }
    chatActionSheet(member.optString("name"), icons, labels, actions);
  }

  private void groupMenu(JSONObject stale) {
    request("GET", "/api/groups/" + stale.optString("id"), null, data -> {
      final JSONObject g = data.optJSONObject("group");
      final String id = g.optString("id");
      List<String> icons = new ArrayList<>(), labels = new ArrayList<>();
      List<Runnable> actions = new ArrayList<>();
      icons.add("search");
      labels.add(I18n.t("Tìm tin nhắn"));
      actions.add(() -> openChatSearch("/api/groups/" + id + "/messages"));
      icons.add("call");
      labels.add(I18n.t("Gọi thoại nhóm"));
      actions.add(() -> openGroupCallDialog(g, "audio"));
      icons.add("video");
      labels.add(I18n.t("Gọi video nhóm"));
      actions.add(() -> openGroupCallDialog(g, "video"));
      icons.add("group_three");
      labels.add(I18n.t("Thành viên và vai trò"));
      actions.add(() -> groupMembers(g));
      icons.add("check");
      labels.add(I18n.t("Bình chọn nhóm"));
      actions.add(() -> openGroupPolls(g));
      if (groupManager(g)) {
        icons.add("camera");
        labels.add(I18n.t("Đổi ảnh nhóm"));
        actions.add(() -> groupPhotoOptions(g));
        icons.add("pencil");
        labels.add(I18n.t("Đổi tên nhóm"));
        actions.add(() -> {
          EditText name = new KinnectInput(this);
          styleChatName(name);
          name.setText(g.optString("name"));
          new Sheet(this).setTitle(I18n.t("Tên nhóm")).setView(chatNameWrap(name))
              .setPositiveButton(I18n.t("Lưu"),
                  (d, w) -> request("PATCH", "/api/groups/" + id, json("name", name.getText().toString()),
                      r -> groupChat(r.optJSONObject("group"))))
              .setNegativeButton(I18n.t("Quay lại"), (d, w) -> groupMenu(g)).show();
        });
        icons.add("user_plus");
        labels.add(I18n.t("Thêm thành viên"));
        actions.add(() -> request("GET", "/api/friends", null, d -> {
          JSONArray users = d.optJSONArray("users");
          if (users == null || users.length() == 0) {
            say(I18n.t("Chưa có bạn bè để thêm."));
            return;
          }
          String[] names = new String[users.length()];
          boolean[] chosen = new boolean[users.length()];
          for (int i = 0; i < names.length; i++)
            names[i] = users.optJSONObject(i).optString("name");
          new Sheet(this).setTitle(I18n.t("Thêm thành viên"))
              .setMultiChoiceItems(names, chosen, (dialog, index, checked) -> chosen[index] = checked)
              .setPositiveButton(I18n.t("Thêm"), (dialog, index) -> {
                JSONArray ids = new JSONArray();
                for (int i = 0; i < chosen.length; i++)
                  if (chosen[i])
                    ids.put(users.optJSONObject(i).optString("id"));
                request("POST", "/api/groups/" + id + "/members", json("members", ids),
                    r -> groupChat(r.optJSONObject("group")));
              }).setNegativeButton(I18n.t("Quay lại"), (dialog, index) -> groupMenu(g)).show();
        }));
      }
      icons.add("settings");
      labels.add(I18n.t("Cài đặt hội thoại"));
      actions.add(() -> conversationMenu("group", id, g.optString("name")));
      icons.add("log_out");
      labels.add(I18n.t("Rời nhóm"));
      actions.add(() -> confirm(
          I18n.t("Rời nhóm? Nếu bạn là trưởng nhóm, quyền sẽ chuyển cho phó nhóm hoặc thành viên tiếp theo."),
          I18n.t("Rời nhóm"), () -> request("POST", "/api/groups/" + id + "/leave", json(), r -> navigate("inbox"))));
      chatActionSheet(g.optString("name"), icons, labels, actions);
    });
  }

  private void openGroupCallDialog(final JSONObject g, final String requestedMode) {
    if (g == null)
      return;
    final String gid = g.optString("id");
    final String mode = "video".equals(requestedMode) ? "video" : "audio";
    request("GET", "/api/groups/" + encode(gid) + "/call", null, state -> {
      final boolean active = state.optBoolean("active");
      final JSONArray initialParticipants = state.optJSONArray("participants");
      final LinearLayout box = column();
      box.setPadding(dp(4), dp(4), dp(4), dp(4));
      final TextView statusTv = label(active
          ? I18n.t("Đang có cuộc gọi nhóm (") + (initialParticipants == null ? 0 : initialParticipants.length())
              + I18n.t(" người tham gia)")
          : I18n.t("Chưa có cuộc gọi nào đang diễn ra trong nhóm."), 14, active ? ACCENT : MUTED);
      box.addView(statusTv);

      final HorizontalScrollView videoScroll = new HorizontalScrollView(this);
      videoScroll.setHorizontalScrollBarEnabled(false);
      videoScroll.setVisibility(View.GONE);
      final LinearLayout videoGrid = row();
      videoGrid.setPadding(0, dp(6), 0, dp(6));
      videoScroll.addView(videoGrid);
      box.addView(videoScroll);

      final LinearLayout participantsBox = column();
      participantsBox.setPadding(0, dp(8), 0, dp(8));
      box.addView(participantsBox);
      final Runnable[] renderParticipants = new Runnable[1];
      final JSONArray[] currentList = { initialParticipants };
      renderParticipants[0] = () -> {
        participantsBox.removeAllViews();
        JSONArray arr = currentList[0];
        if (arr == null || arr.length() == 0)
          return;
        for (int i = 0; i < arr.length(); i++) {
          JSONObject p = arr.optJSONObject(i);
          if (p == null)
            continue;
          String pLine = "• " + p.optString("name", p.optString("username"))
              + (p.optBoolean("video") ? " (Video)" : " (Thoại)")
              + (p.optBoolean("muted") ? " · 🔇" : "");
          participantsBox.addView(label(pLine, 13, TEXT));
        }
      };
      renderParticipants[0].run();

      final boolean[] joinedCall = { false };
      final boolean[] micMuted = { false };
      final boolean[] videoEnabled = { "video".equals(mode) };
      final boolean[] speakerOn = { "video".equals(mode) };
      final NativeRtc[] groupRtc = { null };
      final org.webrtc.SurfaceViewRenderer[] localRenderer = { null };
      final Map<String, org.webrtc.SurfaceViewRenderer> peerRenderers = new LinkedHashMap<>();
      final Map<String, View> peerTiles = new LinkedHashMap<>();
      final android.media.AudioManager audioMgr = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
      final int[] prevAudioMode = { audioMgr != null ? audioMgr.getMode() : android.media.AudioManager.MODE_NORMAL };
      final boolean[] prevSpeaker = { audioMgr != null && audioMgr.isSpeakerphoneOn() };
      final boolean[] audioConfigured = { false };

      final LinearLayout mediaControls = row();
      mediaControls.setVisibility(View.GONE);
      mediaControls.setPadding(0, dp(6), 0, dp(6));
      final Button[] micBtn = { null }, spkBtn = { null }, camBtn = { null };
      micBtn[0] = button(I18n.t("Tắt mic"), () -> {
        micMuted[0] = !micMuted[0];
        if (groupRtc[0] != null)
          groupRtc[0].microphone(!micMuted[0]);
        micBtn[0].setText(micMuted[0] ? I18n.t("Bật mic") : I18n.t("Tắt mic"));
        KinnectService.send(NativeSocket.json("type", "group-call-media", "groupId", gid, "muted", micMuted[0], "video",
            videoEnabled[0]));
      });
      spkBtn[0] = button(speakerOn[0] ? I18n.t("Loa ngoài: Bật") : I18n.t("Loa ngoài: Tắt"), () -> {
        speakerOn[0] = !speakerOn[0];
        if (audioMgr != null)
          audioMgr.setSpeakerphoneOn(speakerOn[0]);
        spkBtn[0].setText(speakerOn[0] ? I18n.t("Loa ngoài: Bật") : I18n.t("Loa ngoài: Tắt"));
      });
      LinearLayout.LayoutParams ctrlLp1 = new LinearLayout.LayoutParams(0, -2, 1);
      ctrlLp1.rightMargin = dp(4);
      mediaControls.addView(micBtn[0], ctrlLp1);
      LinearLayout.LayoutParams ctrlLp2 = new LinearLayout.LayoutParams(0, -2, 1);
      mediaControls.addView(spkBtn[0], ctrlLp2);
      if ("video".equals(mode)) {
        ctrlLp2.rightMargin = dp(4);
        camBtn[0] = button(I18n.t("Tắt camera"), () -> {
          videoEnabled[0] = !videoEnabled[0];
          if (groupRtc[0] != null)
            groupRtc[0].camera(videoEnabled[0]);
          camBtn[0].setText(videoEnabled[0] ? I18n.t("Tắt camera") : I18n.t("Bật camera"));
          KinnectService.send(NativeSocket.json("type", "group-call-media", "groupId", gid, "muted", micMuted[0],
              "video", videoEnabled[0]));
        });
        mediaControls.addView(camBtn[0], new LinearLayout.LayoutParams(0, -2, 1));
      }
      box.addView(mediaControls);

      final Runnable cleanupGroupMedia = () -> {
        peerRenderers.clear();
        peerTiles.clear();
        videoGrid.removeAllViews();
        videoScroll.setVisibility(View.GONE);
        mediaControls.setVisibility(View.GONE);
        localRenderer[0] = null;
        if (groupRtc[0] != null) {
          NativeRtc oldRtc = groupRtc[0];
          groupRtc[0] = null;
          try {
            oldRtc.close();
          } catch (Exception ignored) {
          }
        }
        if (audioConfigured[0] && audioMgr != null) {
          audioConfigured[0] = false;
          try {
            audioMgr.setMode(prevAudioMode[0]);
            audioMgr.setSpeakerphoneOn(prevSpeaker[0]);
          } catch (Exception ignored) {
          }
        }
      };

      final java.util.function.Consumer<String> ensurePeerVideoTile = peerId -> {
        if (!"video".equals(mode) || groupRtc[0] == null || peerId == null || peerId.isEmpty()
            || peerRenderers.containsKey(peerId))
          return;
        org.webrtc.SurfaceViewRenderer remoteView = new org.webrtc.SurfaceViewRenderer(MainActivity.this);
        FrameLayout tile = new FrameLayout(MainActivity.this);
        tile.setBackground(background(0xff141418, 12));
        tile.setClipToOutline(true);
        tile.addView(remoteView, new FrameLayout.LayoutParams(-1, -1));
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(dp(110), dp(148));
        tlp.rightMargin = dp(6);
        videoGrid.addView(tile, tlp);
        videoScroll.setVisibility(View.VISIBLE);
        peerRenderers.put(peerId, remoteView);
        peerTiles.put(peerId, tile);
        groupRtc[0].bindLive(peerId, remoteView);
      };

      final android.app.Dialog[] dlgRef = { null };
      final boolean[] joiningCall = { false };
      final boolean[] pendingGroupJoin = { false };
      final Runnable resizeGroupSheet = () -> {
        android.app.Dialog d = dlgRef[0];
        if (d == null || d.getWindow() == null || isFinishing() || isDestroyed())
          return;
        Window w = d.getWindow();
        w.getDecorView().post(() -> {
          if (d == null || !d.isShowing() || d.getWindow() == null)
            return;
          View contentRoot = w.getDecorView().findViewById(android.R.id.content);
          View surface = contentRoot instanceof ViewGroup && ((ViewGroup) contentRoot).getChildCount() > 0
              ? ((ViewGroup) contentRoot).getChildAt(0)
              : null;
          if (!(surface instanceof ViewGroup) || ((ViewGroup) surface).getChildCount() == 0)
            return;
          View outer = ((ViewGroup) surface).getChildAt(0);
          View sheetBox = outer instanceof ViewGroup && ((ViewGroup) outer).getChildCount() > 0
              ? ((ViewGroup) outer).getChildAt(0)
              : outer;
          int rawDp560 = Math.round(560 * getResources().getDisplayMetrics().density);
          int width = Math.min(getResources().getDisplayMetrics().widthPixels, rawDp560);
          int spec = View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY);
          sheetBox.measure(spec, View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED));
          int buttonsH = ((ViewGroup) surface).getChildCount() > 1
              ? ((ViewGroup) surface).getChildAt(1).getMeasuredHeight()
              : 0;
          int extra = Math.round(24 * getResources().getDisplayMetrics().density);
          int maxH = getResources().getDisplayMetrics().heightPixels * 9 / 10;
          w.setLayout(width, Math.min(maxH, sheetBox.getMeasuredHeight() + buttonsH + extra));
        });
      };

      final NativeSocket.Events listener = new NativeSocket.Events() {
        @Override
        public void event(JSONObject ev) {
          String t = ev.optString("type");
          if ("welcome".equals(t)) {
            handler.post(() -> {
              if (pendingGroupJoin[0] && groupRtc[0] != null && !joinedCall[0] && dlgRef[0] != null
                  && dlgRef[0].isShowing()) {
                pendingGroupJoin[0] = false;
                KinnectService.send(NativeSocket.json("type", "group-call-join", "groupId", gid, "mode", mode));
              }
            });
            return;
          }
          if (!gid.equals(ev.optString("groupId")))
            return;
          handler.post(() -> {
            if (isFinishing() || isDestroyed())
              return;
            if ("group-call-joined".equals(t) || "group-call-state".equals(t)) {
              JSONArray pArr = ev.optJSONArray("participants");
              currentList[0] = pArr;
              if ("group-call-joined".equals(t)) {
                joiningCall[0] = false;
                pendingGroupJoin[0] = false;
                joinedCall[0] = true;
                mediaControls.setVisibility(View.VISIBLE);
                resizeGroupSheet.run();
                JSONArray peers = ev.optJSONArray("peers");
                if (groupRtc[0] != null && peers != null) {
                  for (int i = 0; i < peers.length(); i++) {
                    String peerId = peers.optString(i);
                    if (!peerId.isEmpty()) {
                      ensurePeerVideoTile.accept(peerId);
                      groupRtc[0].offer(peerId);
                    }
                  }
                }
              }
              int count = pArr == null ? 0 : pArr.length();
              statusTv.setText(joinedCall[0]
                  ? I18n.t("Đã tham gia cuộc gọi nhóm · ") + count + I18n.t(" người")
                  : (count > 0 ? I18n.t("Đang có cuộc gọi nhóm (") + count + I18n.t(" người tham gia)")
                      : I18n.t("Cuộc gọi nhóm đã kết thúc.")));
              renderParticipants[0].run();
            } else if ("group-call-peer-joined".equals(t)) {
              String peerId = ev.optString("peerId");
              ensurePeerVideoTile.accept(peerId);
              resizeGroupSheet.run();
            } else if ("group-call-peer-left".equals(t)) {
              String peerId = ev.optString("peerId");
              View tile = peerTiles.remove(peerId);
              peerRenderers.remove(peerId);
              if (tile != null)
                videoGrid.removeView(tile);
              if (groupRtc[0] != null && !peerId.isEmpty())
                groupRtc[0].remove(peerId);
            } else if ("group-call-signal".equals(t)) {
              String fromPeer = ev.optString("from");
              if (groupRtc[0] != null && !fromPeer.isEmpty()) {
                ensurePeerVideoTile.accept(fromPeer);
                groupRtc[0].signal(fromPeer, ev);
              }
            } else if ("group-call-error".equals(t)) {
              joiningCall[0] = false;
              pendingGroupJoin[0] = false;
              joinedCall[0] = false;
              cleanupGroupMedia.run();
              String errMsg = ev.optString("message", I18n.t("Không thể tham gia cuộc gọi nhóm."));
              statusTv.setText(errMsg);
              say(errMsg);
              resizeGroupSheet.run();
            } else if ("group-call-ended".equals(t)) {
              joiningCall[0] = false;
              pendingGroupJoin[0] = false;
              joinedCall[0] = false;
              cleanupGroupMedia.run();
              statusTv.setText(I18n.t("Đã rời cuộc gọi nhóm."));
              resizeGroupSheet.run();
            }
          });
        }

        @Override
        public void closed() {
          handler.post(() -> {
            if (isFinishing() || isDestroyed())
              return;
            if (joinedCall[0] || joiningCall[0]) {
              joiningCall[0] = false;
              pendingGroupJoin[0] = false;
              joinedCall[0] = false;
              cleanupGroupMedia.run();
              statusTv.setText(I18n.t("Mất kết nối cuộc gọi nhóm. Hãy tham gia lại."));
              resizeGroupSheet.run();
            }
          });
        }
      };
      ensureCalls();
      KinnectService.listen(listener);
      final Runnable startJoinMedia = () -> {
        if (joinedCall[0] || joiningCall[0])
          return;
        joiningCall[0] = true;
        ensureCalls();
        statusTv.setText(I18n.t("Đang kết nối cuộc gọi nhóm…"));
        api.call("GET", "/api/call-config", null, (cfg, err, code) -> {
          if (isFinishing() || isDestroyed() || dlgRef[0] == null || !dlgRef[0].isShowing()) {
            joiningCall[0] = false;
            return;
          }
          if (err != null || cfg == null) {
            joiningCall[0] = false;
            statusTv.setText(err != null ? err : I18n.t("Không kết nối được máy chủ cuộc gọi."));
            say(err != null ? err : I18n.t("Không kết nối được máy chủ cuộc gọi."));
            return;
          }
          cleanupGroupMedia.run();
          try {
            if ("video".equals(mode)) {
              localRenderer[0] = new org.webrtc.SurfaceViewRenderer(MainActivity.this);
              FrameLayout selfTile = new FrameLayout(MainActivity.this);
              selfTile.setBackground(background(0xff141418, 12));
              selfTile.setClipToOutline(true);
              selfTile.addView(localRenderer[0], new FrameLayout.LayoutParams(-1, -1));
              LinearLayout.LayoutParams slp = new LinearLayout.LayoutParams(dp(110), dp(148));
              slp.rightMargin = dp(6);
              videoGrid.addView(selfTile, slp);
              videoScroll.setVisibility(View.VISIBLE);
            }
            groupRtc[0] = new NativeRtc(MainActivity.this, cfg, localRenderer[0], null, new NativeRtc.Events() {
              @Override
              public void signal(String peer, JSONObject value) {
                try {
                  value.put("type", "group-call-signal");
                  value.put("groupId", gid);
                  value.put("to", peer);
                  KinnectService.send(value);
                } catch (JSONException ignored) {
                }
              }

              @Override
              public void status(String message) {
              }
            });
            groupRtc[0].media(MainActivity.this, "video".equals(mode));
            if (audioMgr != null) {
              prevAudioMode[0] = audioMgr.getMode();
              prevSpeaker[0] = audioMgr.isSpeakerphoneOn();
              audioMgr.setMode(android.media.AudioManager.MODE_IN_COMMUNICATION);
              audioMgr.setSpeakerphoneOn(speakerOn[0]);
              audioConfigured[0] = true;
            }
            mediaControls.setVisibility(View.VISIBLE);
            resizeGroupSheet.run();
            if (KinnectService.isReady()) {
              pendingGroupJoin[0] = false;
              KinnectService.send(NativeSocket.json("type", "group-call-join", "groupId", gid, "mode", mode));
            } else {
              pendingGroupJoin[0] = true;
              KinnectService.start(MainActivity.this);
            }
          } catch (Exception e) {
            joiningCall[0] = false;
            pendingGroupJoin[0] = false;
            cleanupGroupMedia.run();
            say(I18n.t("Không mở được micro/camera cho cuộc gọi nhóm."));
          }
        });
      };
      final Button joinBtn = primary(active
          ? ("video".equals(mode) ? I18n.t("Tham gia gọi video") : I18n.t("Tham gia gọi thoại"))
          : ("video".equals(mode) ? I18n.t("Bắt đầu gọi video nhóm") : I18n.t("Bắt đầu gọi thoại nhóm")), () -> {
            if (joinedCall[0] || joiningCall[0])
              return;
            boolean hasMic = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
            boolean hasCam = !"video".equals(mode)
                || checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
            if (hasMic && hasCam) {
              startJoinMedia.run();
            } else {
              groupCallPermissionTask = startJoinMedia;
              requestPermissions("video".equals(mode)
                  ? new String[] { Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA }
                  : new String[] { Manifest.permission.RECORD_AUDIO }, 902);
            }
          });
      box.addView(joinBtn);
      final Button leaveBtn = button(I18n.t("Rời cuộc gọi nhóm"), () -> {
        joiningCall[0] = false;
        pendingGroupJoin[0] = false;
        cleanupGroupMedia.run();
        if (joinedCall[0]) {
          KinnectService.send(NativeSocket.json("type", "group-call-leave", "groupId", gid));
          joinedCall[0] = false;
        }
        if (dlgRef[0] != null)
          dlgRef[0].dismiss();
      });
      box.addView(leaveBtn);
      android.app.Dialog dlg = new Sheet(this)
          .setTitle(
              ("video".equals(mode) ? I18n.t("Gọi video nhóm · ") : I18n.t("Gọi thoại nhóm · ")) + g.optString("name"))
          .setView(box)
          .setNegativeButton(I18n.t("Đóng"), null)
          .show();
      dlgRef[0] = dlg;
      groupCallDialog = dlg;
      dlg.setOnDismissListener(x -> {
        joiningCall[0] = false;
        pendingGroupJoin[0] = false;
        if (groupCallDialog == dlg)
          groupCallDialog = null;
        KinnectService.unlisten(listener);
        cleanupGroupMedia.run();
        if (joinedCall[0]) {
          KinnectService.send(NativeSocket.json("type", "group-call-leave", "groupId", gid));
          joinedCall[0] = false;
        }
      });
    });
  }

  private android.app.Dialog groupCallDialog;
  private android.app.Dialog groupPollsDialog;

  private void openGroupPolls(final JSONObject g) {
    final String gid = g.optString("id");
    request("GET", "/api/groups/" + gid + "/polls", null, data -> {
      JSONArray polls = data.optJSONArray("polls");
      LinearLayout box = column();
      box.setPadding(dp(4), dp(4), dp(4), dp(4));
      if (polls == null || polls.length() == 0) {
        box.addView(label(I18n.t("Nhóm chưa có bình chọn nào."), 14, MUTED));
      } else {
        final String myId = me == null ? "" : me.optString("id");
        final boolean isManager = groupManager(g);
        for (int i = 0; i < polls.length(); i++) {
          final JSONObject poll = polls.optJSONObject(i);
          if (poll == null)
            continue;
          final boolean isMultiple = poll.optBoolean("multiple");
          final boolean isClosed = poll.optBoolean("closed");
          final String pollId = poll.optString("id");
          final JSONArray myOptionIds = poll.optJSONArray("myOptionIds");
          LinearLayout pCard = column();
          pCard.setPadding(dp(10), dp(10), dp(10), dp(10));
          pCard.setBackground(background(SOFT, 12));
          TextView q = label(poll.optString("question") + (isClosed ? " · Đã đóng" : ""), 14, TEXT);
          q.setTypeface(null, Typeface.BOLD);
          pCard.addView(q);
          pCard.addView(
              label(poll.optInt("totalVoters") + I18n.t(" người chọn") + (isMultiple ? I18n.t(" · Chọn nhiều") : ""),
                  12, MUTED));
          final JSONArray opts = poll.optJSONArray("options");
          for (int j = 0; opts != null && j < opts.length(); j++) {
            final JSONObject opt = opts.optJSONObject(j);
            if (opt == null)
              continue;
            final boolean voted = opt.optBoolean("voted");
            final String optId = opt.optString("id");
            TextView optBtn = label((voted ? "✓ " : "○ ") + opt.optString("label") + " (" + opt.optInt("votes") + ")",
                13, voted ? ACCENT_TEXT : TEXT);
            optBtn.setGravity(Gravity.CENTER_VERTICAL);
            optBtn.setPadding(dp(8), dp(7), dp(8), dp(7));
            if (!isClosed) {
              optBtn.setOnClickListener(v -> {
                JSONArray next = new JSONArray();
                if (isMultiple) {
                  Set<String> chosen = new LinkedHashSet<>();
                  if (myOptionIds != null) {
                    for (int k = 0; k < myOptionIds.length(); k++) {
                      String existingId = myOptionIds.optString(k);
                      if (!existingId.isEmpty())
                        chosen.add(existingId);
                    }
                  } else {
                    for (int k = 0; k < opts.length(); k++) {
                      JSONObject candidate = opts.optJSONObject(k);
                      if (candidate != null && candidate.optBoolean("voted"))
                        chosen.add(candidate.optString("id"));
                    }
                  }
                  if (chosen.contains(optId))
                    chosen.remove(optId);
                  else
                    chosen.add(optId);
                  for (String cid : chosen)
                    next.put(cid);
                } else {
                  if (!voted)
                    next.put(optId);
                }
                request("POST", "/api/groups/" + gid + "/polls/" + pollId + "/vote", json("optionIds", next),
                    r -> openGroupPolls(g));
              });
            }
            pCard.addView(optBtn, new LinearLayout.LayoutParams(-1, -2));
            if (!isClosed)
              UiMetrics.enforceMinTouchTarget(optBtn, 48);
          }
          if (isManager || poll.optString("creatorId").equals(myId)) {
            LinearLayout manageRow = row();
            manageRow.setPadding(0, dp(6), 0, 0);
            if (!isClosed) {
              TextView closeBtn = label(I18n.t("Đóng bình chọn"), 12, ACCENT_TEXT);
              closeBtn.setTypeface(null, Typeface.BOLD);
              closeBtn.setGravity(Gravity.CENTER_VERTICAL);
              closeBtn.setPadding(dp(8), dp(6), dp(12), dp(6));
              closeBtn.setOnClickListener(v -> confirm(I18n.t("Đóng bình chọn này?"),
                  () -> request("POST", "/api/groups/" + gid + "/polls/" + pollId + "/close", json(), r -> {
                    say(I18n.t("Đã đóng bình chọn."));
                    openGroupPolls(g);
                  })));
              manageRow.addView(closeBtn);
              UiMetrics.enforceMinTouchTarget(closeBtn, 48);
            }
            TextView delBtn = label(I18n.t("Xóa bình chọn"), 12, WebDesign.DANGER[WebTheme.isDark(this) ? 1 : 0]);
            delBtn.setTypeface(null, Typeface.BOLD);
            delBtn.setGravity(Gravity.CENTER_VERTICAL);
            delBtn.setPadding(dp(8), dp(6), dp(8), dp(6));
            delBtn.setOnClickListener(v -> confirm(I18n.t("Xóa bình chọn này?"),
                () -> request("DELETE", "/api/groups/" + gid + "/polls/" + pollId, json(), r -> {
                  say(I18n.t("Đã xóa bình chọn."));
                  openGroupPolls(g);
                })));
            manageRow.addView(delBtn);
            UiMetrics.enforceMinTouchTarget(delBtn, 48);
            pCard.addView(manageRow);
          }
          LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
          lp.bottomMargin = dp(8);
          box.addView(pCard, lp);
        }
      }
      box.addView(primary(I18n.t("+ Tạo bình chọn mới"), () -> {
        LinearLayout form = column();
        EditText qInput = new KinnectInput(this);
        styleChatName(qInput);
        qInput.setHint(I18n.t("Câu hỏi bình chọn"));
        EditText oInput = new KinnectInput(this);
        styleChatName(oInput);
        oInput.setSingleLine(false);
        oInput.setHint(I18n.t("Mỗi dòng 1 lựa chọn (2–10 mục)"));
        final CheckBox multiCheck = new CheckBox(this);
        multiCheck.setText(I18n.t("Cho phép chọn nhiều đáp án"));
        multiCheck.setTextColor(TEXT);
        multiCheck.setButtonTintList(android.content.res.ColorStateList.valueOf(ACCENT));
        form.addView(qInput);
        LinearLayout.LayoutParams op = new LinearLayout.LayoutParams(-1, -2);
        op.topMargin = dp(8);
        form.addView(oInput, op);
        LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(-1, -2);
        mp.topMargin = dp(6);
        form.addView(multiCheck, mp);
        new Sheet(this).setTitle(I18n.t("Tạo bình chọn nhóm")).setView(form)
            .setPositiveButton(I18n.t("Đăng"), (d, w) -> {
              String qText = qInput.getText().toString().trim();
              JSONArray optArr = new JSONArray();
              for (String line : oInput.getText().toString().split("\\r?\\n")) {
                String clean = line.trim();
                if (!clean.isEmpty())
                  optArr.put(clean);
              }
              if (qText.isEmpty() || optArr.length() < 2) {
                say(I18n.t("Nhập câu hỏi và ít nhất 2 lựa chọn."));
                return;
              }
              request("POST", "/api/groups/" + gid + "/polls",
                  json("question", qText, "options", optArr, "multiple", multiCheck.isChecked()), r -> {
                    say(I18n.t("Đã tạo bình chọn nhóm"));
                    openGroupPolls(g);
                  });
            })
            .setNegativeButton(I18n.t("Huỷ"), null).show();
      }));
      ScrollView sc = new ScrollView(this);
      sc.addView(box);
      if (groupPollsDialog != null && groupPollsDialog.isShowing()) {
        try {
          groupPollsDialog.dismiss();
        } catch (Exception ignored) {
        }
      }
      groupPollsDialog = new Sheet(this).setTitle(I18n.t("Bình chọn · ") + g.optString("name")).setView(sc)
          .setNegativeButton(I18n.t("Đóng"), null).show();
    });
  }

  // Bình luận dạng chuỗi: trả lời, cảm xúc, báo cáo — dùng cho bài viết và video
  // ngắn
  private String replyTo = null;

  private void comments(final String base, final Runnable reload, Runnable back, String backLabel) {
    final LinearLayout list = column();
    list.setPadding(0, 0, 0, dp(16));
    content.addView(list);
    final TextView replying = label("", 12, ACCENT_TEXT);
    replying.setPadding(dp(14), dp(6), dp(14), dp(2));
    replying.setVisibility(View.GONE);
    final int raw48 = UiMetrics.dpRaw(this, 48);
    final EditText value = new EditText(this);
    value.setHint(I18n.t("Viết bình luận…"));
    value.setHintTextColor(MUTED);
    value.setTextColor(TEXT);
    value.setTextSize(14);
    value.setSingleLine(false);
    value.setMaxLines(4);
    value.setMinHeight(raw48);
    value.setPadding(dp(14), dp(10), dp(14), dp(10));
    value.setBackground(background(SOFT, 22));
    // Ghim thanh nhập bình luận + dải emoji nhanh ở đáy màn hình (đồng bộ Shorts
    // Comments)
    LinearLayout dock = column();
    dock.setBackgroundColor(CARD);
    dock.addView(divider());
    dock.addView(replying, new LinearLayout.LayoutParams(-1, -2));
    HorizontalScrollView emojiScroll = new HorizontalScrollView(this);
    emojiScroll.setHorizontalScrollBarEnabled(false);
    LinearLayout emojis = row();
    emojis.setPadding(dp(6), dp(6), dp(6), dp(4));
    int emojiWash = 0xff1c1726;
    final String[] commentEmojis = new String[] { "❤️", "😂", "🔥", "👏", "🥰", "😮", "😢", "💜" };
    for (int idx = 0; idx < commentEmojis.length; idx++) {
      final String em = commentEmojis[idx];
      TextView et = label(em, 20, WHITE);
      et.setGravity(Gravity.CENTER);
      et.setBackground(pressable(emojiWash, 99));
      et.setPadding(0, 0, 0, 0);
      et.setOnClickListener(v -> {
        value.append(em);
        value.setSelection(value.length());
      });
      LinearLayout.LayoutParams ep = new LinearLayout.LayoutParams(raw48, raw48);
      ep.rightMargin = (idx < commentEmojis.length - 1) ? dp(2) : 0;
      emojis.addView(et, ep);
      UiMetrics.enforceMinTouchTarget(et, 48);
    }
    emojiScroll.addView(emojis);
    dock.addView(emojiScroll, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout bar = row();
    bar.setGravity(Gravity.CENTER_VERTICAL);
    bar.setPadding(dp(12), dp(4), dp(12), dp(10));
    bar.addView(value, new LinearLayout.LayoutParams(0, -2, 1));
    UiMetrics.enforceMinTouchTarget(value, 48);
    FrameLayout send = new FrameLayout(this);
    send.setBackground(gradient(99));
    send.addView(icon("send", 18, WHITE), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    send.setContentDescription(I18n.t("Gửi bình luận"));
    send.setOnClickListener(v -> {
      String bodyText = value.getText().toString().trim();
      if (bodyText.isEmpty())
        return;
      JSONObject payload = json("body", bodyText);
      if (replyTo != null)
        try {
          payload.put("parentId", replyTo);
        } catch (JSONException ignored) {
        }
      request("POST", base + "/comments", payload, d -> {
        replyTo = null;
        value.setText("");
        replying.setVisibility(View.GONE);
        reload.run();
      });
    });
    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(Math.max(dp(42), raw48), Math.max(dp(42), raw48));
    sp.leftMargin = dp(8);
    bar.addView(send, sp);
    dock.addView(bar, new LinearLayout.LayoutParams(-1, -2));
    int insertAt = bottom != null ? root.indexOfChild(bottom) : root.getChildCount();
    if (insertAt < 0)
      insertAt = root.getChildCount();
    root.addView(dock, insertAt, new LinearLayout.LayoutParams(-1, -2));
    request("GET", base + "/comments", null, d -> {
      JSONArray all = d.optJSONArray("comments");
      if (all == null || all.length() == 0) {
        list.addView(label(I18n.t("Chưa có bình luận. Hãy là người đầu tiên."), 14, MUTED));
        return;
      }
      for (int i = 0; i < all.length(); i++) {
        JSONObject cm = all.optJSONObject(i);
        if (cm.isNull("parentId") || cm.optString("parentId").isEmpty()) {
          commentRow(base, cm, list, 0, reload, replying, value);
          for (int j = 0; j < all.length(); j++) {
            JSONObject child = all.optJSONObject(j);
            if (child.optString("parentId").equals(cm.optString("id")))
              commentRow(base, child, list, 1, reload, replying, value);
          }
        }
      }
    });
  }

  private void commentRow(final String base, final JSONObject cm, LinearLayout list, int depth, final Runnable reload,
      final TextView replying, final EditText value) {
    LinearLayout r = row();
    r.setPadding(dp(depth * 36), dp(6), 0, dp(2));
    r.setGravity(Gravity.TOP);
    avatar(cm.optJSONObject("author"), r, depth == 0 ? 34 : 28);
    LinearLayout t = column();
    LinearLayout bubble = column();
    bubble.setPadding(dp(12), dp(8), dp(12), dp(8));
    bubble.setBackground(background(CARD, 14));
    JSONObject cma = cm.optJSONObject("author");
    bubble.addView(label(cma == null ? "" : cma.optString("name"), 12, ACCENT_TEXT));
    bubble.addView(label(cm.optString("body"), 15, TEXT));
    t.addView(bubble);
    LinearLayout meta = row();
    meta.setGravity(Gravity.CENTER_VERTICAL);
    String mine = cm.isNull("myReaction") ? "" : cm.optString("myReaction");
    int total = 0;
    JSONObject counts = cm.optJSONObject("reactions");
    if (counts != null)
      for (String[] x : REACTIONS)
        total += counts.optInt(x[0]);
    String glyph = "Thích";
    for (String[] x : REACTIONS)
      if (x[0].equals(mine))
        glyph = x[1];
    TextView like = label(ago(cm.optLong("created")) + "   " + glyph + (total > 0 ? " " + total : ""), 12,
        mine.isEmpty() ? MUTED : ACCENT_TEXT);
    like.setGravity(Gravity.CENTER_VERTICAL);
    like.setPadding(0, dp(8), dp(8), dp(8));
    like.setOnClickListener(v -> request("POST", base + "/comments/" + cm.optString("id") + "/reaction",
        mine.isEmpty() ? json("reaction", "like") : json("reaction", JSONObject.NULL), x -> reload.run()));
    like.setOnLongClickListener(v -> {
      reactionBar(v, w -> request("POST", base + "/comments/" + cm.optString("id") + "/reaction",
          json("reaction", REACTIONS[w][0]), x -> reload.run()));
      return true;
    });
    meta.addView(like);
    UiMetrics.enforceMinTouchTarget(like, 48);
    TextView reply = label(I18n.t("Trả lời"), 12, MUTED);
    reply.setGravity(Gravity.CENTER);
    reply.setPadding(dp(10), dp(8), dp(10), dp(8));
    final String parent = cm.isNull("parentId") || cm.optString("parentId").isEmpty() ? cm.optString("id")
        : cm.optString("parentId");
    reply.setOnClickListener(v -> {
      replyTo = parent;
      replying.setVisibility(View.VISIBLE);
      replying.setText(I18n.t("Đang trả lời ") + (cma == null ? "" : cma.optString("name")) + I18n.t(" · chạm để huỷ"));
      replying.setOnClickListener(x -> {
        replyTo = null;
        replying.setText("");
        replying.setVisibility(View.GONE);
      });
      value.requestFocus();
    });
    meta.addView(reply);
    UiMetrics.enforceMinTouchTarget(reply, 48);
    TextView rep = label(I18n.t("Báo cáo"), 12, MUTED);
    rep.setGravity(Gravity.CENTER);
    rep.setPadding(dp(10), dp(8), dp(10), dp(8));
    rep.setOnClickListener(v -> report("comment", cm.optString("id")));
    meta.addView(rep);
    UiMetrics.enforceMinTouchTarget(rep, 48);
    t.addView(meta);
    LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(0, -2, 1);
    tp.setMargins(dp(8), 0, 0, 0);
    r.addView(t, tp);
    list.addView(r);
  }

  private Runnable chatReload;
  private boolean chatPendingReload = false;
  private boolean chatInitialScroll = true;
  private boolean chatForceScrollBottom = false;
  private boolean feedHasMore = false;
  private boolean feedLoadingMore = false;
  private long feedNextCursor = 0;
  private JSONObject chatReplyTarget = null;
  private LinearLayout chatReplyBanner = null;
  private EditText chatActiveInput = null;
  private boolean chatHasMore = false;
  private long chatNextCursor = 0;
  private List<JSONObject> chatOlderMessages = new ArrayList<>();

  private void loadMoreFeedPosts(final LinearLayout list) {
    if (!feedHasMore || feedNextCursor <= 0 || feedLoadingMore)
      return;
    final long cursor = feedNextCursor;
    final int generation = screen;
    feedLoadingMore = true;
    request("GET", "/api/posts?limit=25&before=" + cursor, null, data -> {
      if (isFinishing() || isDestroyed() || generation != screen || !list.isAttachedToWindow())
        return;
      JSONArray more = data.optJSONArray("posts");
      feedHasMore = data.optBoolean("hasMore");
      feedNextCursor = data.optLong("nextCursor", 0);
      if (list.getChildCount() > 0 && "feed:load-more".equals(list.getChildAt(list.getChildCount() - 1).getTag())) {
        list.removeViewAt(list.getChildCount() - 1);
      }
      if (more == null || more.length() == 0)
        return;
      Set<String> seenIds = new HashSet<>();
      if (feedRows != null) {
        for (int i = 0; i < feedRows.length(); i++) {
          JSONObject existing = feedRows.optJSONObject(i);
          if (existing != null)
            seenIds.add(existing.optString("id"));
        }
      }
      LinearLayout saved = content;
      content = list;
      try {
        for (int i = 0; i < more.length(); i++) {
          JSONObject item = more.optJSONObject(i);
          if (item == null || seenIds.contains(item.optString("id")))
            continue;
          seenIds.add(item.optString("id"));
          if (feedRows != null)
            feedRows.put(item);
          postCard(item);
        }
        if (feedHasMore && feedNextCursor > 0) {
          Button moreBtn = button(I18n.t("Xem thêm bài viết"), () -> loadMoreFeedPosts(list));
          moreBtn.setTag("feed:load-more");
          list.addView(moreBtn);
        }
      } finally {
        content = saved;
      }
    }, () -> {
      feedLoadingMore = false;
    });
  }

  private void updateChatReplyBanner() {
    if (chatReplyBanner == null)
      return;
    chatReplyBanner.removeAllViews();
    if (chatReplyTarget == null) {
      chatReplyBanner.setVisibility(View.GONE);
      return;
    }
    chatReplyBanner.setVisibility(View.VISIBLE);
    JSONObject author = chatReplyTarget.optJSONObject("author");
    String who = author != null ? author.optString("name")
        : (chatReplyTarget.optString("sender").equals(me.optString("id")) ? I18n.t("Bạn") : "");
    String preview = chatReplyTarget.optString("body");
    if (preview.isEmpty())
      preview = I18n.t("Tệp đính kèm");
    LinearLayout col = column();
    TextView h = label(I18n.t("Đang trả lời ") + who, 11, ACCENT_TEXT);
    h.setTypeface(null, Typeface.BOLD);
    col.addView(h);
    TextView b = label(preview, 12, MUTED);
    b.setSingleLine(true);
    b.setEllipsize(android.text.TextUtils.TruncateAt.END);
    col.addView(b);
    chatReplyBanner.addView(col, new LinearLayout.LayoutParams(0, -2, 1));
    ImageView cancel = icon("close", 18, MUTED);
    cancel.setPadding(dp(8), dp(8), dp(8), dp(8));
    cancel.setContentDescription(I18n.t("Hủy trả lời"));
    cancel.setOnClickListener(v -> {
      chatReplyTarget = null;
      updateChatReplyBanner();
    });
    cancel.setLayoutParams(new LinearLayout.LayoutParams(dp(34), dp(34)));
    chatReplyBanner.addView(UiMetrics.wrapMinTouchTarget(this, cancel, 48));
  }

  private void openChatSearch(final String path) {
    LinearLayout form = column();
    final EditText q = searchField(form, I18n.t("Tìm tin nhắn trong hội thoại…"));
    final LinearLayout results = column();
    results.setPadding(0, dp(10), 0, 0);
    form.addView(results);
    Runnable runSearch = () -> {
      String query = q.getText().toString().trim();
      results.removeAllViews();
      if (query.isEmpty())
        return;
      results.addView(label(I18n.t("Đang tìm…"), 13, MUTED));
      request("GET", path + "/search?q=" + encode(query) + "&limit=30", null, data -> {
        results.removeAllViews();
        JSONArray msgs = data.optJSONArray("messages");
        if (msgs == null || msgs.length() == 0) {
          results.addView(label(I18n.t("Không tìm thấy tin nhắn."), 13, MUTED));
          return;
        }
        for (int i = 0; i < msgs.length(); i++) {
          JSONObject m = msgs.optJSONObject(i);
          LinearLayout rowBox = column();
          rowBox.setPadding(dp(10), dp(8), dp(10), dp(8));
          rowBox.setBackground(background(SOFT, 10));
          JSONObject a = m.optJSONObject("author");
          String who = a != null ? a.optString("name")
              : (m.optString("sender").equals(me.optString("id")) ? I18n.t("Bạn") : "");
          TextView t1 = label(who + " · " + ago(m.optLong("created")), 11, MUTED);
          rowBox.addView(t1);
          rowBox.addView(label(m.optString("body"), 13, TEXT));
          LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
          lp.bottomMargin = dp(6);
          results.addView(rowBox, lp);
        }
      });
    };
    form.addView(button(I18n.t("Tìm kiếm"), runSearch));
    new Sheet(this).setTitle(I18n.t("Tìm tin nhắn")).setView(form).setNegativeButton(I18n.t("Đóng"), null).show();
  }

  private void chat(final JSONObject u) {
    currentGroup = null;
    remember("chat:" + u.optString("id"), () -> chat(u));
    headerActive = "inbox";
    final String path = "/api/users/" + u.optString("id") + "/messages";
    chatScreen(u, u.optString("name"), u.optBoolean("isActive") ? "Đang hoạt động" : "@" + u.optString("username"),
        path, false, () -> directChatMenu(u), () -> chat(u));
    chatUser = u;
  }

  private void groupChat(final JSONObject g) {
    currentGroup = g;
    remember("group:" + g.optString("id"), () -> groupChat(g));
    JSONArray members = g.optJSONArray("members");
    chatScreen(null, g.optString("name"), (members == null ? 0 : members.length()) + " thành viên",
        "/api/groups/" + g.optString("id") + "/messages", true, () -> groupMenu(g), () -> groupChat(g));
  }

  // Khung chat toàn màn giống web: đầu trang (quay lại, avatar, gọi), tin nhắn
  // dạng bong bóng, ô nhập bo tròn.
  private void chatScreen(final JSONObject u, String title, String subtitle, final String path, final boolean group,
      final Runnable more, final Runnable reopen) {
    shell("", true);
    chatReload = reopen;
    toolbar.setVisibility(View.GONE);
    if (bottom != null)
      bottom.setVisibility(View.GONE);
    ScrollView scroll = (ScrollView) content.getParent();
    int at = root.indexOfChild(scroll);
    root.removeView(scroll);
    LinearLayout box = column();
    box.setBackgroundColor(CARD);
    root.addView(box, at, new LinearLayout.LayoutParams(-1, 0, 1));
    LinearLayout head = row();
    head.setGravity(Gravity.CENTER_VERTICAL);
    head.setPadding(dp(2), dp(6), dp(2), dp(6));
    ImageView back = icon("back", 24, TEXT);
    back.setPadding(dp(8), dp(8), dp(8), dp(8));
    back.setContentDescription(I18n.t("Quay lại"));
    back.setOnClickListener(v -> navigate("inbox"));
    back.setLayoutParams(new LinearLayout.LayoutParams(dp(42), dp(42)));
    head.addView(UiMetrics.wrapMinTouchTarget(this, back, 48));
    if (u != null || group && currentGroup != null)
      avatar(u != null ? u : currentGroup, head, 36);
    else {
      FrameLayout g = new FrameLayout(this);
      GradientDrawable o = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { ACCENT, 0xffd946c4 });
      o.setShape(GradientDrawable.OVAL);
      g.setBackground(o);
      ImageView groupGlyph = new ImageView(this);
      groupGlyph.setImageDrawable(new SettingsGlyph("group_three", WHITE, ACCENT));
      g.addView(groupGlyph, new FrameLayout.LayoutParams(dp(28), dp(28), Gravity.CENTER));
      head.addView(g, new LinearLayout.LayoutParams(dp(42), dp(42)));
    }
    LinearLayout who = column();
    who.setGravity(Gravity.CENTER_VERTICAL);
    who.setPadding(dp(6), 0, dp(2), 0);
    TextView n = label(title, 14, TEXT);
    n.setTypeface(null, Typeface.BOLD);
    n.setSingleLine(false);
    n.setMaxLines(2);
    n.setEllipsize(android.text.TextUtils.TruncateAt.END);
    n.setPadding(0, 0, 0, 0);
    who.addView(n);
    boolean isOnlineSub = "Đang hoạt động".equals(subtitle);
    TextView st = label(isOnlineSub ? "● " + I18n.t("Đang hoạt động") : subtitle, 12,
        isOnlineSub ? WebDesign.ONLINE_STRICT[WebTheme.isDark(this) ? 1 : 0] : MUTED);
    st.setSingleLine(true);
    st.setEllipsize(android.text.TextUtils.TruncateAt.END);
    st.setPadding(0, 0, 0, 0);
    who.addView(st);
    if (u != null)
      who.setOnClickListener(v -> person(u));
    head.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
    if (u != null)
      UiMetrics.enforceMinTouchTarget(who, 48);
    if (u != null) {
      head.addView(softIconButton("call", I18n.t("Gọi thoại"), () -> {
        ensureCalls();
        calls.start(u, "audio");
      }));
      head.addView(softIconButton("video", I18n.t("Gọi video"), () -> {
        ensureCalls();
        calls.start(u, "video");
      }));
    } else if (group && currentGroup != null) {
      final JSONObject grpForCall = currentGroup;
      head.addView(softIconButton("call", I18n.t("Gọi thoại nhóm"), () -> openGroupCallDialog(grpForCall, "audio")));
      head.addView(softIconButton("video", I18n.t("Gọi video nhóm"), () -> openGroupCallDialog(grpForCall, "video")));
    }
    head.addView(chatHeaderButton("menu_lines", "Thông tin và tùy chọn hội thoại", more));
    box.addView(head);
    box.addView(divider());
    chatReplyTarget = null;
    chatOlderMessages = new ArrayList<>();
    chatHasMore = false;
    chatNextCursor = 0;
    chatPendingReload = false;
    chatInitialScroll = true;
    chatForceScrollBottom = false;
    final ScrollView msgScroll = new ScrollView(this);
    msgScroll.setBackgroundColor(BG == 0xfff6f5fa ? 0xfff7f8fa : BG);
    final LinearLayout list = column();
    list.setPadding(dp(12), dp(10), dp(12), dp(10));
    msgScroll.addView(list);
    aiChatList = list;
    aiChatScroll = msgScroll;
    aiChatSender = !group && u != null ? u.optString("id") : "";
    ensureCalls();
    box.addView(msgScroll, new LinearLayout.LayoutParams(-1, 0, 1));
    box.addView(divider());
    chatReplyBanner = row();
    chatReplyBanner.setPadding(dp(12), dp(6), dp(8), dp(6));
    chatReplyBanner.setBackgroundColor(SOFT);
    chatReplyBanner.setVisibility(View.GONE);
    box.addView(chatReplyBanner, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout bar = row();
    bar.setGravity(Gravity.CENTER_VERTICAL);
    bar.setPadding(dp(4), dp(6), dp(8), dp(6));
    ImageView clip = icon("attach", 22, ACCENT_TEXT);
    clip.setPadding(dp(9), dp(9), dp(9), dp(9));
    clip.setContentDescription(I18n.t("Đính kèm"));
    clip.setOnClickListener(v -> {
      attachTarget = path;
      pickFile(303, "*/*");
    });
    clip.setLayoutParams(new LinearLayout.LayoutParams(dp(40), dp(40)));
    bar.addView(UiMetrics.wrapMinTouchTarget(this, clip, 48));
    final EditText input = new KinnectInput(this);
    if (group && currentGroup != null) {
      TextView mentionBtn = label("@", 16, ACCENT_TEXT);
      mentionBtn.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
      mentionBtn.setGravity(Gravity.CENTER);
      mentionBtn.setPadding(0, 0, 0, 0);
      mentionBtn.setBackground(pressable(PRIMARY_SOFT, 99));
      mentionBtn.setContentDescription(I18n.t("Nhắc thành viên"));
      mentionBtn.setOnClickListener(v -> {
        String cur = input.getText().toString();
        if (!cur.endsWith("@"))
          input.append(cur.isEmpty() || cur.endsWith(" ") ? "@" : " @");
        input.setSelection(input.length());
        input.requestFocus();
      });
      mentionBtn.setLayoutParams(new LinearLayout.LayoutParams(dp(36), dp(36)));
      bar.addView(UiMetrics.wrapMinTouchTarget(this, mentionBtn, 48));
    }
    input.setHint(I18n.t("Nhắn tin..."));
    input.setContentDescription(I18n.t("Tin nhắn"));
    installChatKeyboard(input, msgScroll);
    input.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(2000) });
    input.setTextColor(TEXT);
    input.setHintTextColor(MUTED);
    input.setTextSize(15);
    input.setPadding(dp(16), dp(10), dp(16), dp(10));
    input.setGravity(Gravity.CENTER_VERTICAL);
    input.setBackground(background(SOFT, 999));
    input.setSingleLine(true);
    int raw48 = UiMetrics.dpRaw(this, 48);
    LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(0, Math.max(dp(44), raw48), 1);
    ip.setMargins(dp(2), 0, dp(6), 0);
    bar.addView(input, ip);
    UiMetrics.enforceMinTouchTarget(input, 48);
    if (group && currentGroup != null)
      installMentions(input, currentGroup);
    FrameLayout send = new FrameLayout(this);
    send.setBackground(new android.graphics.drawable.RippleDrawable(
        android.content.res.ColorStateList.valueOf(0x33ffffff), brandGradient(999), null));
    send.addView(icon("send", 20, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    send.setContentDescription(I18n.t("Gửi"));
    final Runnable load = () -> loadChat(path, list, msgScroll, group, u);
    chatActiveInput = input;
    send.setOnClickListener(v -> {
      String text = input.getText().toString().trim();
      if (text.isEmpty())
        return;
      JSONObject bodyJson = json("body", text, "mentions", group ? mentionIds(text, currentGroup) : new JSONArray());
      if (chatReplyTarget != null)
        try {
          bodyJson.put("replyToId", chatReplyTarget.optString("id"));
        } catch (JSONException ignored) {
        }
      submitText(input, send, path, bodyJson, d -> {
        chatReplyTarget = null;
        updateChatReplyBanner();
        chatForceScrollBottom = true;
        lastMessages = "";
        load.run();
      });
    });
    tactile(send);
    bar.addView(send, new LinearLayout.LayoutParams(Math.max(dp(46), raw48), Math.max(dp(46), raw48)));
    box.addView(bar);
    lastMessages = "";
    aiChatReload = load;
    if (api.cachedGet(path) == null)
      list.addView(loadingState(I18n.t("Đang tải tin nhắn…")));
    load.run();
    final int generation = screen;
    if (poll != null)
      handler.removeCallbacks(poll);
    poll = () -> {
      if (!stopped && generation == screen) {
        load.run();
        handler.postDelayed(poll, 4000);
      }
    };
    handler.postDelayed(poll, 4000);
  }

  private View chatHeaderButton(String glyph, String description, Runnable action) {
    FrameLayout button = new FrameLayout(this);
    button.setBackground(pressable(PRIMARY_SOFT, 99));
    ImageView image = new ImageView(this);
    if (glyph.equals("menu_lines"))
      image.setImageDrawable(new SettingsGlyph("menu_lines", ACCENT_TEXT, PRIMARY_SOFT));
    else
      image.setImageDrawable(WebIcons.load(this, glyph));
    image.setImageTintList(android.content.res.ColorStateList.valueOf(ACCENT_TEXT));
    button.addView(image, new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    button.setContentDescription(description);
    button.setOnClickListener(v -> action.run());
    button.setLayoutParams(new LinearLayout.LayoutParams(dp(36), dp(36)));
    return UiMetrics.wrapMinTouchTarget(this, button, 48);
  }

  private JSONArray mentionIds(String body, JSONObject group) {
    JSONArray ids = new JSONArray(), members = group == null ? null : group.optJSONArray("members");
    for (int i = 0; members != null && i < members.length(); i++) {
      JSONObject u = members.optJSONObject(i);
      if (!u.optString("id").equals(me.optString("id"))
          && ChatTextPolicy.mentionIndex(body, u.optString("username")) >= 0)
        ids.put(u.optString("id"));
    }
    return ids;
  }

  private void installMentions(final EditText input, final JSONObject group) {
    final ListPopupWindow popup = new ListPopupWindow(this);
    popup.setAnchorView(input);
    popup.setModal(false);
    popup.setHeight(dp(180));
    final List<JSONObject> matches = new ArrayList<>();
    final int[] token = { -1 };
    popup.setOnItemClickListener((parent, view, index, id) -> {
      if (index >= matches.size() || token[0] < 0)
        return;
      String text = input.getText().toString();
      int cursor = input.getSelectionStart();
      if (cursor < token[0])
        return;
      String replacement = "@" + matches.get(index).optString("username") + " ";
      input.getText().replace(token[0], cursor, replacement);
      popup.dismiss();
      input.requestFocus();
    });
    input.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence t, int start, int count, int after) {
      }

      public void onTextChanged(CharSequence t, int start, int before, int count) {
      }

      public void afterTextChanged(android.text.Editable editable) {
        int cursor = input.getSelectionStart();
        String text = editable.toString();
        int at = cursor < 0 ? -1 : text.lastIndexOf('@', Math.max(0, cursor - 1));
        if (at < 0 || at > 0 && !Character.isWhitespace(text.charAt(at - 1))
            || text.substring(at + 1, Math.max(at + 1, cursor)).contains(" ")) {
          popup.dismiss();
          return;
        }
        String query = text.substring(at + 1, cursor).toLowerCase(Locale.ROOT);
        matches.clear();
        List<String> labels = new ArrayList<>();
        JSONArray members = group.optJSONArray("members");
        for (int i = 0; members != null && i < members.length(); i++) {
          JSONObject u = members.optJSONObject(i);
          if (u.optString("id").equals(me.optString("id")))
            continue;
          if ((u.optString("name") + " " + u.optString("username")).toLowerCase(Locale.ROOT).contains(query)) {
            matches.add(u);
            labels.add(u.optString("name") + " · @" + u.optString("username"));
          }
        }
        token[0] = at;
        if (labels.isEmpty()) {
          popup.dismiss();
          return;
        }
        popup.setWidth(Math.max(dp(200), input.getWidth()));
        popup.setAdapter(new ArrayAdapter<String>(MainActivity.this, android.R.layout.simple_list_item_1, labels));
        popup.show();
      }
    });
    input.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
      public void onViewAttachedToWindow(View v) {
      }

      public void onViewDetachedFromWindow(View v) {
        popup.dismiss();
      }
    });
  }

  private View softIconButton(String name, String label, Runnable action) {
    FrameLayout f = new FrameLayout(this);
    f.setBackground(pressable(PRIMARY_SOFT, 99));
    f.addView(icon(name, 18, ACCENT_TEXT), new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
    f.setContentDescription(label);
    f.setOnClickListener(v -> action.run());
    f.setLayoutParams(new LinearLayout.LayoutParams(dp(36), dp(36)));
    return UiMetrics.wrapMinTouchTarget(this, f, 48);
  }

  private LinearLayout messageFooter(final JSONObject m, final boolean own, String clock, final boolean group,
      final String path, final Runnable refresh) {
    LinearLayout footer = row();
    footer.setGravity(Gravity.CENTER_VERTICAL);
    footer.setTag("message:footer");
    String status = "";
    JSONObject receipt = m.optJSONObject("receipt");
    boolean seen = receipt != null && (receipt.optLong("seenAt") > 0 || receipt.optInt("seenCount") > 0);
    boolean delivered = seen
        || (receipt != null && (receipt.optLong("deliveredAt") > 0 || receipt.optInt("deliveredCount") > 0));
    if (own && !m.optBoolean("recalled"))
      status = seen ? I18n.t("Đã xem") : delivered ? I18n.t("Đã nhận") : I18n.t("Đã gửi");
    JSONObject reactions = m.optJSONObject("reactions");
    StringBuilder rx = new StringBuilder();
    for (String[] reaction : REACTIONS)
      if (reactions != null && reactions.optInt(reaction[0]) > 0)
        rx.append(reaction[1]);
    TextView time = label(clock, 11, own ? WHITE : MUTED);
    time.setPadding(0, 0, dp(5), 0);
    time.setSingleLine(true);
    time.setContentDescription(clock + (m.optBoolean("pinned") ? " · " + I18n.t("Ghim tin nhắn") : ""));
    footer.addView(time);
    int toolColor = own ? WHITE : MUTED;
    if (!status.isEmpty()) {
      FrameLayout receiptIcon = new FrameLayout(this);
      receiptIcon.addView(icon(seen ? "eye" : "check", 13, toolColor),
          new FrameLayout.LayoutParams(dp(13), dp(13), Gravity.CENTER));
      receiptIcon.setAlpha(seen ? 1f : .6f);
      receiptIcon.setContentDescription(status);
      receiptIcon.setTooltipText(status);
      footer.addView(receiptIcon, new LinearLayout.LayoutParams(dp(20), dp(24)));
    }
    final String base = "/api/chat-messages/" + (group ? "group" : "direct") + "/" + m.optString("id");
    LinearLayout tools = row();
    if (!m.optBoolean("recalled")) {
      tools.addView(messageTool("comment", I18n.t("Trả lời tin nhắn"), toolColor, () -> {
        chatReplyTarget = m;
        updateChatReplyBanner();
        if (chatActiveInput != null)
          chatActiveInput.requestFocus();
      }));
      View reaction = messageTool("smile", I18n.t("Cảm xúc tin nhắn"), toolColor, () -> reactionBar(null,
          w -> request("POST", base + "/reaction",
              json("reaction", REACTIONS[w][0].equals(m.optString("myReaction")) ? JSONObject.NULL : REACTIONS[w][0]),
              result -> refresh.run())));
      if (rx.length() > 0) {
        reaction.setContentDescription(I18n.t("Cảm xúc tin nhắn") + ": " + rx);
        reaction.setTooltipText(String.valueOf(reaction.getContentDescription()));
      }
      tools.addView(reaction);
    }
    tools.addView(messageTool("more", I18n.t("Tùy chọn tin nhắn"), toolColor,
        () -> messageMenu(group ? "group" : "direct", m, own, path, refresh)));
    footer.addView(tools);
    return footer;
  }

  private void reconcileChatRows(LinearLayout current, LinearLayout next) {
    java.util.Map<String, View> reusable = new java.util.HashMap<>();
    for (int i = 0; i < current.getChildCount(); i++) {
      View child = current.getChildAt(i);
      Object key = child.getTag();
      if (key instanceof String && (((String) key).startsWith("message:") || ((String) key).startsWith("post:")))
        reusable.put((String) key, child);
    }
    java.util.ArrayList<View> wanted = new java.util.ArrayList<>();
    while (next.getChildCount() > 0) {
      View child = next.getChildAt(0);
      next.removeViewAt(0);
      View retained = child.getTag() instanceof String ? reusable.get((String) child.getTag()) : null;
      wanted.add(retained == null ? child : retained);
    }
    for (int i = current.getChildCount() - 1; i >= 0; i--)
      if (!wanted.contains(current.getChildAt(i)))
        current.removeViewAt(i);
    for (int i = 0; i < wanted.size(); i++) {
      View child = wanted.get(i);
      if (i < current.getChildCount() && current.getChildAt(i) == child)
        continue;
      if (child.getParent() == current)
        current.removeView(child);
      current.addView(child, i);
    }
  }

  private void loadChat(final String path, final LinearLayout list, final ScrollView scroll, final boolean group,
      final JSONObject other) {
    if (Boolean.TRUE.equals(list.getTag())) {
      chatPendingReload = true;
      return;
    }
    chatPendingReload = false;
    list.setTag(Boolean.TRUE);
    cachedRequest(path, data -> {
      JSONArray rawMessages = data.optJSONArray("messages");
      if (rawMessages == null)
        return;
      if (chatOlderMessages.isEmpty()) {
        chatHasMore = data.optBoolean("hasMore");
        chatNextCursor = data.optLong("nextCursor", 0);
      }
      JSONArray messages = new JSONArray();
      Set<String> seenMsgIds = new HashSet<>();
      for (JSONObject om : chatOlderMessages) {
        if (seenMsgIds.add(om.optString("id")))
          messages.put(om);
      }
      for (int i = 0; i < rawMessages.length(); i++) {
        JSONObject rm = rawMessages.optJSONObject(i);
        if (rm != null && seenMsgIds.add(rm.optString("id")))
          messages.put(rm);
      }
      String signature = messages.toString() + data.optString("aiSupport") + "|" + chatHasMore + "|" + chatNextCursor;
      if (signature.equals(lastMessages) && list.getChildCount() > 0)
        return;
      final boolean nearBottom = list.getHeight() <= scroll.getHeight()
          || (list.getHeight() - scroll.getScrollY() - scroll.getHeight() < dp(64));
      final boolean followBottom = chatInitialScroll || chatForceScrollBottom || nearBottom;
      final int previousY = scroll.getScrollY();
      chatInitialScroll = false;
      chatForceScrollBottom = false;
      lastMessages = signature;
      LinearLayout nextList = column();
      if (chatHasMore && chatNextCursor > 0) {
        final long beforeCursor = chatNextCursor;
        nextList.addView(button(I18n.t("Xem tin nhắn cũ hơn"),
            () -> request("GET", path + "?limit=50&before=" + beforeCursor, null, olderData -> {
              JSONArray older = olderData.optJSONArray("messages");
              chatHasMore = olderData.optBoolean("hasMore");
              chatNextCursor = olderData.optLong("nextCursor", 0);
              if (older != null && older.length() > 0) {
                List<JSONObject> merged = new ArrayList<>();
                for (int oi = 0; oi < older.length(); oi++)
                  merged.add(older.optJSONObject(oi));
                merged.addAll(chatOlderMessages);
                chatOlderMessages = merged;
                lastMessages = "";
                loadChat(path, list, scroll, group, other);
              }
            })));
      }
      JSONObject aiInfo = data.optJSONObject("aiSupport");
      if (!group && aiInfo != null && aiInfo.optBoolean("available")) {
        boolean enabled = aiInfo.optString("consent").equals("enabled");
        TextView info = label(
            enabled ? I18n.t("Trợ lý AI đã bật.") : I18n.t("Trợ lý AI đang tắt. Bạn vẫn có thể nhắn quản trị viên."),
            12, MUTED);
        nextList.addView(info);
        nextList.addView(button(enabled ? I18n.t("Tắt AI") : I18n.t("Bật trợ lý AI"), () -> {
          Runnable apply = () -> request("POST", "/api/me/ai-consent", json("enabled", !enabled), r -> {
            lastMessages = "";
            loadChat(path, list, scroll, group, other);
          });
          if (enabled)
            apply.run();
          else
            confirm(I18n.t(
                "Bật trợ lý AI? Nội dung bạn gửi và tối đa 6 tin nhắn liên quan được gửi tới Cloudflare, hoặc NVIDIA khi dự phòng, để tạo câu trả lời. Không gửi mật khẩu, OTP hoặc dữ liệu nhạy cảm. Bạn có thể tắt AI bất cứ lúc nào và tiếp tục nhắn quản trị viên."),
                apply);
        }));
      }
      String lastDay = "";
      java.text.SimpleDateFormat day = new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()),
          clock = new java.text.SimpleDateFormat("HH:mm", Locale.getDefault());
      String today = day.format(new Date());
      if (messages == null || messages.length() == 0) {
        LinearLayout hello = column();
        hello.setGravity(Gravity.CENTER_HORIZONTAL);
        hello.setPadding(0, dp(60), 0, 0);
        FrameLayout bubble = new FrameLayout(this);
        bubble.setBackground(background(PRIMARY_SOFT, 99));
        bubble.addView(icon("message_circle", 26, ACCENT_TEXT),
            new FrameLayout.LayoutParams(dp(26), dp(26), Gravity.CENTER));
        hello.addView(bubble, new LinearLayout.LayoutParams(dp(60), dp(60)));
        TextView ht = label(I18n.t("Hãy gửi lời chào đầu tiên!"), 15, MUTED);
        ht.setPadding(0, dp(12), 0, 0);
        ht.setGravity(Gravity.CENTER);
        hello.addView(ht, new LinearLayout.LayoutParams(-1, -2));
        nextList.addView(hello, new LinearLayout.LayoutParams(-1, -2));
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
          nextList.addView(sep, sp);
        }
        LinearLayout bubble = column();
        bubble.setPadding(dp(14), dp(9), dp(14), dp(7));
        GradientDrawable shape = background(own
            ? (StoreStyle.chatColor(me.optString("storeStyle")) != 0 ? StoreStyle.chatColor(me.optString("storeStyle"))
                : ACCENT)
            : CARD, 18);
        if (!own)
          shape.setStroke(1, LINE);
        bubble.setBackground(shape);
        if (group && !own) {
          TextView author = label(m.optJSONObject("author") == null ? "" : m.optJSONObject("author").optString("name"),
              12, ACCENT_TEXT);
          author.setTypeface(null, Typeface.BOLD);
          author.setPadding(0, 0, 0, 0);
          JSONObject authorData = m.optJSONObject("author");
          if (authorData != null) {
            String role = authorData.optString("groupRole");
            if (role.equals("owner") || role.equals("deputy"))
              author.setText(
                  author.getText() + " · " + (role.equals("owner") ? I18n.t("Trưởng nhóm") : I18n.t("Phó nhóm")));
          }
          bubble.addView(author);
        }
        JSONObject replyTo = m.optJSONObject("replyTo");
        if (!m.optBoolean("recalled") && replyTo != null) {
          LinearLayout qBox = column();
          qBox.setPadding(dp(8), dp(5), dp(8), dp(5));
          qBox.setBackground(background(own ? 0x44000000 : SOFT, 10));
          TextView qAuthor = label(replyTo.optString("senderName", I18n.t("Tin nhắn")), 11, own ? WHITE : ACCENT_TEXT);
          qAuthor.setTypeface(null, Typeface.BOLD);
          qBox.addView(qAuthor);
          String qBody = replyTo.optString("body");
          if (qBody.isEmpty())
            qBody = I18n.t("Tệp đính kèm");
          TextView qText = label(qBody, 12, own ? WHITE : MUTED);
          qText.setSingleLine(true);
          qText.setEllipsize(android.text.TextUtils.TruncateAt.END);
          qBox.addView(qText);
          LinearLayout.LayoutParams qp = new LinearLayout.LayoutParams(-2, -2);
          qp.bottomMargin = dp(4);
          bubble.addView(qBox, qp);
        }
        final JSONObject file = m.optJSONObject("attachment");
        if (!m.optBoolean("recalled") && file != null && file.optString("kind").equals("image"))
          mediaView(file, bubble);
        else if (!m.optBoolean("recalled") && file != null) {
          LinearLayout fileCard = row();
          fileCard.setGravity(Gravity.CENTER_VERTICAL);
          fileCard.setPadding(dp(10), dp(8), dp(12), dp(8));
          fileCard.setBackground(pressable(own ? 0x44000000 : SOFT, 12));
          FrameLayout fileBadge = new FrameLayout(this);
          fileBadge.setBackground(background(own ? 0x55000000 : PRIMARY_SOFT, 10));
          fileBadge.addView(icon("attach", 18, own ? WHITE : ACCENT_TEXT),
              new FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER));
          fileCard.addView(fileBadge, new LinearLayout.LayoutParams(dp(34), dp(34)));
          LinearLayout fileMeta = column();
          fileMeta.setPadding(dp(10), 0, 0, 0);
          TextView fname = label(file.optString("name"), 14, own ? WHITE : TEXT);
          fname.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
          fname.setSingleLine(true);
          fname.setEllipsize(android.text.TextUtils.TruncateAt.END);
          fileMeta.addView(fname);
          fileMeta.addView(label(I18n.t("Nhấn để mở / tải xuống"), 11, own ? WHITE : MUTED));
          fileCard.addView(fileMeta, new LinearLayout.LayoutParams(-2, -2));
          fileCard.setOnClickListener(v -> openAttachment(file));
          LinearLayout.LayoutParams fp = new LinearLayout.LayoutParams(-2,
              Math.max(dp(48), UiMetrics.dpRaw(this, 48)));
          fp.bottomMargin = dp(4);
          bubble.addView(fileCard, fp);
          UiMetrics.enforceMinTouchTarget(fileCard, 48);
        }
        String body = m.optBoolean("recalled") ? "Tin nhắn đã được thu hồi" : decodeEntities(m.optString("body"));
        if (!body.isEmpty()) {
          TextView t = label(body, 15, own ? WHITE : TEXT);
          t.setPadding(0, 0, 0, 0);
          if (group && !m.optBoolean("recalled")) {
            android.text.SpannableString rich = new android.text.SpannableString(body);
            JSONArray mentions = m.optJSONArray("mentions");
            for (int j = 0; mentions != null && j < mentions.length(); j++) {
              JSONObject mentioned = mentions.optJSONObject(j);
              String token = "@" + mentioned.optString("username");
              int start = ChatTextPolicy.mentionIndex(body, mentioned.optString("username"));
              if (start >= 0) {
                rich.setSpan(new android.text.style.StyleSpan(Typeface.BOLD), start, start + token.length(), 0);
                final JSONObject target = mentioned;
                rich.setSpan(new android.text.style.ClickableSpan() {
                  public void onClick(View view) {
                    person(target);
                  }

                  public void updateDrawState(android.text.TextPaint paint) {
                    paint.setColor(own ? WHITE : ACCENT_TEXT);
                    paint.setUnderlineText(true);
                  }
                }, start, start + token.length(), 0);
              }
            }
            t.setText(rich);
            if (mentions != null && mentions.length() > 0)
              t.setMovementMethod(android.text.method.LinkMovementMethod.getInstance());
          }
          if (m.optBoolean("recalled"))
            t.setTypeface(null, Typeface.ITALIC);
          bubble.addView(t);
        }
        final Runnable refresh = () -> {
          lastMessages = "";
          loadChat(path, list, scroll, group, other);
        };
        String stamp = clock.format(at) + (m.optLong("editedAt", 0) > 0 ? " · Đã sửa" : "");
        bubble.addView(messageFooter(m, own, stamp, group, path, refresh));
        bubble.setOnLongClickListener(v -> {
          messageMenu(group ? "group" : "direct", m, own, path, () -> {
            lastMessages = "";
            loadChat(path, list, scroll, group, other);
          });
          return true;
        });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, -2);
        p.gravity = own ? Gravity.END : Gravity.START;
        p.setMargins(own ? dp(48) : 0, dp(3), own ? 0 : dp(48), dp(3));
        bubble.setTag("message:" + m.optString("id") + ":" + m.toString());
        nextList.addView(bubble, p);
      }
      reconcileChatRows(list, nextList);
      paintAIStream();
      if (followBottom) {
        scroll.getViewTreeObserver().addOnPreDrawListener(new android.view.ViewTreeObserver.OnPreDrawListener() {

  public boolean onPreDraw() {
    scroll.getViewTreeObserver().removeOnPreDrawListener(this);
    int bottomY = Math.max(0, list.getHeight() - scroll.getHeight());
    scroll.scrollTo(0, bottomY);
    return true;
  }});scroll.post(()->scroll.scrollTo(0,Math.max(0,list.getHeight()-scroll.getHeight())));}else{scroll.post(()->scroll.scrollTo(0,previousY));}},()->{list.setTag(Boolean.FALSE);

  View loading = list.findViewWithTag("loading");if(loading!=null)
  {
    list.removeView(loading);
    list.addView(button(I18n.t("Tải lại tin nhắn"), () -> {
      list.removeAllViews();
      list.addView(loadingState(I18n.t("Đang tải tin nhắn…")));
      loadChat(path, list, scroll, group, other);
    }));
  }if(chatPendingReload&&list.isAttachedToWindow())
  {
    chatPendingReload = false;
    loadChat(path, list, scroll, group, other);
  }
  });}

  // Bình luận mở ngay dưới bài viết như web: bong bóng xám, "Thích · Trả lời ·
  // thời gian", ô "Viết bình luận…".
  private void inlineComments(final JSONObject p, final LinearLayout thread, final boolean focus) {
    inlineComments(p, thread, focus, "");
  }

  private void inlineComments(final JSONObject p, final LinearLayout thread, final boolean focus,
      final String commentFocus) {
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
    bar.setGravity(Gravity.CENTER_VERTICAL);
    bar.setPadding(0, dp(6), 0, dp(10));
    avatar(me, bar, 32);
    final EditText input = new KinnectInput(this);
    input.setHint(I18n.t("Viết bình luận..."));
    input.setContentDescription(I18n.t("Viết bình luận"));
    input.setFilters(new android.text.InputFilter[] { new android.text.InputFilter.LengthFilter(1000) });
    input.setTextColor(TEXT);
    input.setHintTextColor(MUTED);
    input.setTextSize(15);
    input.setSingleLine(true);
    input.setPadding(dp(14), 0, dp(14), 0);
    input.setBackground(background(SOFT, 999));
    LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(0, Math.max(dp(40), UiMetrics.dpRaw(this, 48)), 1);
    ip.setMargins(dp(8), 0, dp(4), 0);
    bar.addView(input, ip);
    UiMetrics.enforceMinTouchTarget(input, 48);
    ImageView send = icon("send", 22, ACCENT_TEXT);
    send.setPadding(dp(10), dp(10), dp(10), dp(10));
    send.setContentDescription(I18n.t("Gửi bình luận"));
    int raw48 = UiMetrics.dpRaw(this, 48);
    bar.addView(send, new LinearLayout.LayoutParams(raw48, raw48));
    UiMetrics.enforceMinTouchTarget(send, 48);
    thread.addView(replying);
    thread.addView(bar);
    replying.setOnClickListener(v -> {
      parent[0] = null;
      replying.setVisibility(View.GONE);
      input.setHint(I18n.t("Viết bình luận..."));
    });
    final Runnable[] load = new Runnable[1];
    load[0] = () -> cachedRequest(base, d -> {
      JSONArray all = d.optJSONArray("comments");
      int count = all == null ? 0 : all.length();
      try {
        p.put("comments", count);
      } catch (JSONException ignored) {
      }
      if (thread.getTag() instanceof TextView)
        ((TextView) thread.getTag()).setText(count + I18n.t(" bình luận"));
      list.removeAllViews();
      for (int i = 0; all != null && i < all.length(); i++) {
        final JSONObject c = all.optJSONObject(i);
        if (c == null || (!c.isNull("parentId") && !c.optString("parentId").isEmpty()))
          continue;
        list.addView(feedComment(c, false, base, load[0], () -> {
          parent[0] = c.optString("id");
          JSONObject ca = c.optJSONObject("author");
          String cname = ca == null ? "" : ca.optString("name");
          replying.setText(I18n.t("Đang trả lời ") + cname + I18n.t(" · chạm để huỷ"));
          replying.setVisibility(View.VISIBLE);
          input.setHint(I18n.t("Trả lời ") + cname + "...");
          input.requestFocus();
        }));
        for (int k = 0; k < all.length(); k++) {
          final JSONObject child = all.optJSONObject(k);
          if (child == null || !child.optString("parentId").equals(c.optString("id")))
            continue;
          list.addView(feedComment(child, true, base, load[0], () -> {
            parent[0] = c.optString("id");
            JSONObject cha = child.optJSONObject("author");
            replying.setText(
                I18n.t("Đang trả lời ") + (cha == null ? "" : cha.optString("name")) + I18n.t(" · chạm để huỷ"));
            replying.setVisibility(View.VISIBLE);
            input.requestFocus();
          }));
        }
      }
      if (!commentFocus.isEmpty()) {
        final View target = list.findViewWithTag(commentFocus);
        if (target != null) {
          target.setBackground(background(PRIMARY_SOFT, 12));
          target
              .post(() -> target.requestRectangleOnScreen(new Rect(0, 0, target.getWidth(), target.getHeight()), true));
        }
      }
    }, () -> {
    });
    send.setOnClickListener(v -> {
      String text = input.getText().toString().trim();
      if (text.isEmpty())
        return;
      JSONObject payload = json("body", text);
      if (parent[0] != null)
        try {
          payload.put("parentId", parent[0]);
        } catch (JSONException ignored) {
        }
      submitText(input, send, base, payload, x -> {
        if (input.length() == 0) {
          parent[0] = null;
          replying.setVisibility(View.GONE);
          input.setHint(I18n.t("Viết bình luận..."));
        }
        load[0].run();
      });
    });
    load[0].run();
    if (focus)
      input.requestFocus();
  }

  private LinearLayout feedComment(final JSONObject c, boolean reply, final String base, final Runnable reload,
      final Runnable onReply) {
    LinearLayout r = row();
    r.setTag(c.optString("id"));
    r.setGravity(Gravity.TOP);
    r.setPadding(reply ? dp(40) : 0, dp(4), 0, dp(4));
    avatar(c.optJSONObject("author"), r, reply ? 26 : 32);
    LinearLayout col = column();
    LinearLayout bubble = column();
    bubble.setPadding(dp(12), dp(7), dp(12), dp(8));
    bubble.setBackground(background(SOFT, 16));
    JSONObject fa = c.optJSONObject("author");
    TextView name = label(fa == null ? "" : fa.optString("name"), 13, TEXT);
    name.setTypeface(null, Typeface.BOLD);
    name.setPadding(0, 0, 0, 0);
    bubble.addView(name);
    TextView text = label(c.optString("body"), 15, TEXT);
    text.setPadding(0, dp(1), 0, 0);
    bubble.addView(text);
    col.addView(bubble, new LinearLayout.LayoutParams(-2, -2));
    LinearLayout meta = row();
    meta.setGravity(Gravity.CENTER_VERTICAL);
    meta.setPadding(dp(10), dp(2), 0, 0);
    String mine = c.isNull("myReaction") ? "" : c.optString("myReaction");
    String likeText = "Thích";
    for (String[] x : REACTIONS)
      if (x[0].equals(mine))
        likeText = x[1] + " Thích";
    TextView like = label(likeText, 12, mine.isEmpty() ? MUTED : ACCENT_TEXT);
    like.setTypeface(null, Typeface.BOLD);
    like.setGravity(Gravity.CENTER_VERTICAL);
    like.setPadding(dp(4), dp(8), dp(8), dp(8));
    like.setOnClickListener(v -> request("POST", base + "/" + c.optString("id") + "/reaction",
        mine.isEmpty() ? json("reaction", "like") : json("reaction", JSONObject.NULL), x -> reload.run()));
    like.setOnLongClickListener(v -> {
      reactionBar(v, w -> request("POST", base + "/" + c.optString("id") + "/reaction",
          json("reaction", REACTIONS[w][0]), x -> reload.run()));
      return true;
    });
    meta.addView(like);
    UiMetrics.enforceMinTouchTarget(like, 48);
    TextView rep = label(I18n.t("Trả lời"), 12, MUTED);
    rep.setTypeface(null, Typeface.BOLD);
    rep.setGravity(Gravity.CENTER);
    rep.setPadding(dp(8), dp(8), dp(8), dp(8));
    rep.setOnClickListener(v -> onReply.run());
    meta.addView(rep);
    UiMetrics.enforceMinTouchTarget(rep, 48);
    meta.addView(label("   " + ago(c.optLong("created")), 12, MUTED));
    int total = 0;
    JSONObject counts = c.optJSONObject("reactions");
    StringBuilder glyphs = new StringBuilder();
    if (counts != null)
      for (String[] x : REACTIONS)
        if (counts.optInt(x[0]) > 0) {
          total += counts.optInt(x[0]);
          glyphs.append(x[1]);
        }
    if (total > 0)
      meta.addView(label("     " + glyphs + " " + total, 12, MUTED));
    col.addView(meta);
    LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(0, -2, 1);
    cp.leftMargin = dp(8);
    r.addView(col, cp);
    r.setOnLongClickListener(v -> {
      commentOptions(c, base, reload);
      return true;
    });
    return r;
  }

  // Tạo tin giống web: bảng trượt từ dưới với hai ô lớn "Quay tin" và "Ảnh kèm
  // nhạc".
  private void commentOptions(JSONObject comment, String base, Runnable reload) {
    if (comment == null)
      return;
    final String cid = comment.optString("id").trim();
    if (cid.isEmpty())
      return;
    JSONObject author = comment.optJSONObject("author");
    if (author == null || !author.optString("id").equals(me.optString("id"))) {
      report("comment", cid);
      return;
    }
    final String path = base + "/" + cid;
    new Sheet(this).setItemIcons(new String[] { "pencil", "trash" })
        .setItems(new String[] { I18n.t("Chỉnh sửa"), I18n.t("Xoá bình luận") }, (dialog, choice) -> {
          if (choice == 1) {
            confirm(I18n.t("Xoá bình luận này?"), () -> request("DELETE", path, json(), data -> reload.run()));
            return;
          }
          LinearLayout form = column();
          final Dialog[] editor = { null };
          EditText text = input(form, I18n.t("Bình luận"), comment.optString("body"), true);
          final Button save = primary(I18n.t("Lưu"), () -> {
          });
          save.setOnClickListener(v -> {
            if (!save.isEnabled())
              return;
            if (text.getText().toString().trim().isEmpty()) {
              text.setError(I18n.t("Nhập bình luận"));
              return;
            }
            save.setEnabled(false);
            request("PATCH", path, json("body", text.getText().toString()), data -> {
              editor[0].dismiss();
              say(I18n.t("Đã lưu bình luận"));
              reload.run();
            }, () -> save.setEnabled(true));
          });
          form.addView(save);
          editor[0] = new Sheet(this).setTitle(I18n.t("Chỉnh sửa bình luận")).setView(form)
              .setNegativeButton(I18n.t("Đóng"), null).show();
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
    tiles.addView(
        storyTile("video", I18n.t("Quay tin"), I18n.t("Camera · Nhạc · Hiệu ứng"), 0xff8354ef, 0xffd94cae, () -> {
          dialog.dismiss();
          Intent studio = new Intent(this, StudioActivity.class);
          studio.putExtra(StudioActivity.EXTRA_STORY, true);
          startActivityForResult(studio, 204);
        }), new LinearLayout.LayoutParams(0, dp(210), 1));
    LinearLayout.LayoutParams second = new LinearLayout.LayoutParams(0, dp(210), 1);
    second.leftMargin = dp(12);
    tiles.addView(
        storyTile("image", I18n.t("Ảnh kèm nhạc"), I18n.t("Chọn ảnh · thêm bài hát"), 0xff397be9, 0xff724ee5, () -> {
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
      ApprovedTypography.sheet(w.getDecorView());
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
    TextView a = label(I18n.t(title), 16, WHITE);
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
    final EditText caption = new KinnectInput(this);
    caption.setHint(I18n.t("Viết gì đó cho tin (không bắt buộc)"));
    new Sheet(this).setTitle(I18n.t("Đăng tin 24 giờ")).setView(caption).setAutoDismissPositive(false)
        .setPositiveButton(I18n.t("Chia sẻ tin"), (d, w) -> {
          if (video == null || !video.exists()) {
            say(I18n.t("Không đọc được video. Vui lòng chọn tệp khác."));
            return;
          }
          if (video.length() > 25L * 1024L * 1024L) {
            say(I18n.t("Video quá lớn để đăng tin (tối đa 25 MB)."));
            return;
          }
          try {
            d.dismiss();
          } catch (Exception ignored) {
          }
          say(I18n.t("Đang đăng tin…"));
          final String text = caption.getText().toString();
          new Thread(() -> {
            try {
              byte[] bytes = NativeApi.readAll(new java.io.FileInputStream(video));
              final String media = "data:video/mp4;base64,"
                  + android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP);
              runOnUiThread(() -> request("POST", "/api/stories", json("body", text, "media", media), r -> {
                say(I18n.t("Đã đăng tin, hiển thị 24 giờ."));
                navigate("feed");
              }));
            } catch (OutOfMemoryError oom) {
              runOnUiThread(() -> say(I18n.t("Thiết bị không đủ bộ nhớ để chuẩn bị tệp tải lên.")));
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
    try (java.io.InputStream in = getContentResolver().openInputStream(uri)) {
      BitmapFactory.decodeStream(in, null, o);
    } catch (Exception ignored) {
    }
    o.inSampleSize = Math.max(1, Math.max(o.outWidth, o.outHeight) / 1280);
    o.inJustDecodeBounds = false;
    return o;
  }

  private void composeAttached(Bitmap image, boolean video) {
    if (composePreview == null || !composePreview.isAttachedToWindow())
      return;
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
      card.addView(icon("video", 22, ACCENT_TEXT), new LinearLayout.LayoutParams(dp(22), dp(22)));
      TextView l = label(video ? I18n.t("Video đã chọn") : I18n.t("Tệp đã chọn"), 14, TEXT);
      l.setPadding(dp(10), 0, 0, 0);
      card.addView(l);
      box.addView(card, new FrameLayout.LayoutParams(-1, dp(64)));
    }
    FrameLayout remove = new FrameLayout(this);
    remove.setBackground(background(0x99000000, 99));
    remove.addView(icon("x", 16, WHITE), new FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER));
    remove.setContentDescription(I18n.t("Gỡ tệp"));
    remove.setOnClickListener(v -> {
      pendingMedia = null;
      composePreview.removeAllViews();
    });
    remove.setLayoutParams(new FrameLayout.LayoutParams(dp(32), dp(32)));
    FrameLayout.LayoutParams rp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.END);
    rp.setMargins(0, dp(4), dp(4), 0);
    box.addView(UiMetrics.wrapMinTouchTarget(this, remove, 48), rp);
    LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(-1, -2);
    bp.topMargin = dp(8);
    composePreview.addView(box, bp);
  }

}
