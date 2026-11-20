package app.kinnect.live;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.os.Handler;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import javax.net.ssl.HttpsURLConnection;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Debug/QA fixture payloads, sample media, and isolated loopback transport hooks. */
public final class QaRuntime {
  private static final String TAG = "KinnectQA";
  private static final String FIXTURE_PREFS = "kinnect_qa_fixture_state";
  private static final String FIXTURE_USER_DEFAULT = "{\"id\":\"usr_qa_review\",\"username\":\"minhanh\",\"name\":\"Minh Anh\",\"role\":\"user\",\"coins\":1200,\"bio\":\"Kinnect QA Review\",\"followersCount\":128,\"followingCount\":64,\"discoverable\":true,\"showDistance\":true,\"showActivity\":true,\"dmMode\":\"friends\"}";
  private static volatile boolean fixtureEnabled = false;
  private static volatile String debugLoopbackOrigin = null;
  private static volatile String debugFallbackOrigin = null;
  private static volatile boolean debugForcePrimaryConnectFailure = false;
  private static volatile boolean debugOffline = false;
  private static volatile javax.net.ssl.SSLSocketFactory debugLoopbackSslFactory = null;

  private QaRuntime() {}

  private static boolean debuggable(Context context) {
    return context != null && (context.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
  }

  public static boolean armReviewFixture(Context context, Intent intent) {
    if (!debuggable(context) || intent == null || !intent.getBooleanExtra("ui_review_fixture", false)) return false;
    if (intent.getBooleanExtra("reset_fixture_state", false)) resetFixtureState(context);
    enableFixture(context, true);
    return true;
  }

  public static boolean wantsSessionRegression(Intent intent) {
    return intent != null && intent.getBooleanExtra("qa_session_regression", false);
  }

  public static boolean wantsLoopbackWipe(Intent intent, NativeApi api) {
    return intent != null && intent.getBooleanExtra("qa_local_loopback_wipe", false) && api != null && pinnedOrigin() != null;
  }

  public static boolean wantsFixtureRoom(Context context, Intent intent) {
    return debuggable(context) && isFixtureEnabled() && intent != null && intent.getBooleanExtra("fixture_joined_room", false);
  }

  public static void pinFromIntent(Context context, Intent intent, NativeApi api) {
    if (!debuggable(context) || intent == null || api == null || !intent.hasExtra("qa_local_loopback_origin")) return;
    String fallback = intent.getStringExtra("qa_local_loopback_fallback");
    if (fallback != null && !fallback.isEmpty()) pinFailover(api, context, intent.getStringExtra("qa_local_loopback_origin"), fallback, intent.getStringExtra("qa_local_loopback_cert_sha256"));
    else pinLoopback(api, context, intent.getStringExtra("qa_local_loopback_origin"), intent.getStringExtra("qa_local_loopback_cert_sha256"));
  }

  public static void applyTransportIntent(Context context, Intent intent, NativeApi api, Runnable onRestored) {
    if (!debuggable(context) || intent == null || api == null || pinnedOrigin() == null) return;
    if (intent.hasExtra("qa_force_primary_failure") || intent.hasExtra("qa_debug_offline")) {
      applyFlags(
        intent.hasExtra("qa_force_primary_failure") ? Boolean.valueOf(intent.getBooleanExtra("qa_force_primary_failure", false)) : null,
        intent.hasExtra("qa_debug_offline") ? Boolean.valueOf(intent.getBooleanExtra("qa_debug_offline", false)) : null
      );
    }
    if (intent.getBooleanExtra("qa_log_session", false)) logSavedPrimary(api);
    if (intent.getBooleanExtra("qa_switchback", false)) {
      boolean restored = switchBack(api);
      if (restored && onRestored != null) onRestored.run();
    }
  }

  public static void applyTheme(Context context, Intent intent) {
    if (!debuggable(context) || intent == null) return;
    String theme = intent.getStringExtra("qa_theme");
    if ("light".equals(theme) || "dark".equals(theme) || "auto".equals(theme)) {
      context.getSharedPreferences("kinnect_settings", 0).edit().putString("theme", theme).commit();
    }
  }

  public static boolean wantsWebRtcSelfTest(Context context, Intent intent) {
    return debuggable(context) && intent != null && intent.getBooleanExtra("qa_webrtc_selftest", false);
  }

  public static void runWebRtcSelfTest(Context context) {
    if (debuggable(context)) QaWebRtcSelfTest.run(context);
  }

  public static void sessionRegression(Boolean pass) {
    if (pass == null) Log.i(TAG, "QA_SESSION_REGRESSION_ERROR");
    else Log.i(TAG, pass.booleanValue() ? "QA_SESSION_REGRESSION_PASS" : "QA_SESSION_REGRESSION_FAIL");
  }

  public static void explicitLogout(int status, boolean failed) {
    Log.i(TAG, "DEBUG_EXPLICIT_LOGOUT: status=" + status + " failed=" + failed);
  }

  public static void uiSay(Context context, String text) {
    if (!debuggable(context) || text == null) return;
    Log.i(TAG, "UI_SAY: " + text.replace('\n', ' '));
  }

  public static void shortsPlaying(int index, String id, int pos, boolean muted) {
    Log.i(TAG, "SHORTS_EVENT: action=playing index=" + index + " id=" + id + " pos=" + pos + " muted=" + muted);
  }

  public static void shortsPause(int pos) {
    Log.i(TAG, "SHORTS_EVENT: action=pause pos=" + pos + " isPlaying=false");
  }

  public static void shortsStart(int pos) {
    Log.i(TAG, "SHORTS_EVENT: action=start pos=" + pos + " isPlaying=true");
  }

  public static void passwordEmptyCurrent(String error, int count) {
    Log.i(TAG, "PASSWORD_VALIDATION: branch=empty_current error='" + error + "' api_dispatched=false api_dispatch_count=" + count);
  }

  public static void passwordShort(String error, int count) {
    Log.i(TAG, "PASSWORD_VALIDATION: branch=short_new_password error='" + error + "' api_dispatched=false api_dispatch_count=" + count);
  }

  public static void passwordMismatch(String error, int count) {
    Log.i(TAG, "PASSWORD_VALIDATION: branch=mismatch error='" + error + "' api_dispatched=false api_dispatch_count=" + count);
  }

  public static void passwordPassed() {
    Log.i(TAG, "PASSWORD_VALIDATION: branch=passed api_dispatched=true");
  }

  public static String syntheticSessionCookie() { return "kinnect_session=qa_synthetic_not_a_real_login"; }
  public static String syntheticDeviceCookie() { return "kinnect_device=qa_synthetic_device"; }
  public static JSONObject regressionUser() throws JSONException { return new JSONObject("{\"id\":\"qa\"}"); }
  public static JSONObject staleUser() throws JSONException { return new JSONObject("{\"id\":\"stale\"}"); }
  public static JSONObject reviewUser() throws JSONException { return new JSONObject(FIXTURE_USER_DEFAULT); }

  public static JSONObject feedStory() throws JSONException {
    JSONObject s = new JSONObject();
    s.put("id", "st_1");
    s.put("body", "Chào ngày mới đầy năng lượng cùng Kinnect! ✨");
    s.put("created", System.currentTimeMillis() - 3600000L);
    JSONObject a = new JSONObject();
    a.put("id", "usr_story");
    a.put("name", "Linh Nhi");
    a.put("username", "linhnhi");
    s.put("author", a);
    return s;
  }

  public static JSONObject shortCommentsItem() throws JSONException {
    return new JSONObject("{\"id\":\"s1\",\"title\":\"Khoảnh khắc cuộc sống\",\"author\":{\"id\":\"usr_qa_review\",\"name\":\"Minh Anh\"},\"comments\":12}");
  }

  public static JSONObject chatDirectUser() throws JSONException {
    return new JSONObject("{\"id\":\"usr_chat_mock\",\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\",\"isActive\":true}");
  }

  public static JSONObject chatGroup() throws JSONException {
    return new JSONObject("{\"id\":\"grp_mock\",\"name\":\"Nhóm Âm Nhạc\",\"members\":[{},{},{}]}");
  }

  public static JSONObject chatMenuUser() throws JSONException {
    return new JSONObject("{\"id\":\"usr_chat_mock\",\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\"}");
  }

  public static JSONObject incomingCall() throws JSONException {
    if (!isFixtureEnabled()) return null;
    return new JSONObject("{\"callId\":\"call_qa_01\",\"from\":{\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\"},\"mode\":\"video\"}");
  }

  public static JSONObject liveFixtureWelcome() throws JSONException {
    return new JSONObject("{\"multiGuest\":false,\"room\":{\"id\":\"fixture_room_1\",\"title\":\"Phòng Live QA Fixture\",\"host\":\"Minh Anh\",\"hostId\":\"usr_qa_review\",\"liveMode\":\"chat\",\"viewers\":42,\"comments\":true}}");
  }

  public static JSONArray liveFixtureRooms() throws JSONException {
    return new JSONArray("[{\"id\":\"room_1\",\"title\":\"Giao lưu âm nhạc cuối tuần\",\"host\":\"Minh Anh\",\"liveMode\":\"chat\",\"hostId\":\"usr_qa_review\",\"viewers\":42}]");
  }

  public static void liveFixtureEntered() {
    Log.i(TAG, "LIVE_FIXTURE_ROOM_STATE: entered FIXTURE_ROOM_STATE (not a real WS-joined room)");
  }

  public static String liveFixtureStatusText() { return "FIXTURE_ROOM_STATE · Mô phỏng phòng Live"; }

  public static boolean fixtureMusicPreview(Context context, android.media.MediaPlayer player, String url) {
    if (!debuggable(context) || !isFixtureEnabled() || player == null || url == null || !url.contains("/music/")) return false;
    final String assetPath = url.contains("m1") ? "gifts/aurora.wav"
      : url.contains("m2") ? "gifts/butterfly.wav"
      : url.contains("m3") ? "gifts/lotus.wav"
      : "gifts/star.wav";
    try {
      File cacheFile = new File(context.getCacheDir(), "qa_preview_" + assetPath.replace("/", "_"));
      try (InputStream in = context.getAssets().open(assetPath); FileOutputStream out = new FileOutputStream(cacheFile)) {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) != -1) out.write(buf, 0, n);
      }
      player.setDataSource(cacheFile.getAbsolutePath());
      player.setLooping(true);
      player.setOnPreparedListener(mp -> {
        mp.start();
        Log.i(TAG, "MUSIC_PREVIEW_PLAY: url=" + url + " asset=" + assetPath + " isPlaying=" + mp.isPlaying());
      });
      player.prepareAsync();
    } catch (Exception ignored) {}
    return true;
  }

  public static void musicPreviewStop(Context context, boolean wasPlaying) {
    if (debuggable(context) && isFixtureEnabled()) Log.i(TAG, "MUSIC_PREVIEW_STOP: wasPlaying=" + wasPlaying);
  }

  public static synchronized boolean enableFixture(Context context, boolean enable) {
    if (!enable) {
      fixtureEnabled = false;
      return false;
    }
    if (!debuggable(context)) {
      fixtureEnabled = false;
      return false;
    }
    fixtureEnabled = true;
    return true;
  }

  public static boolean isFixtureEnabled() {
    if (debugLoopbackOrigin != null) return false;
    if (!fixtureEnabled) {
      File flag = new File("/data/local/tmp/kinnect_fixture");
      if (flag.exists()) fixtureEnabled = true;
    }
    return fixtureEnabled;
  }

  public static synchronized void resetFixtureState(Context context) {
    if (!debuggable(context)) return;
    context.getSharedPreferences(FIXTURE_PREFS, Context.MODE_PRIVATE).edit().clear().commit();
  }

  public static synchronized JSONObject fixtureUser(Context context) {
    if (!fixtureEnabled || !debuggable(context)) {
      try { return new JSONObject(FIXTURE_USER_DEFAULT); } catch (Exception e) { return new JSONObject(); }
    }
    String saved = context.getSharedPreferences(FIXTURE_PREFS, Context.MODE_PRIVATE).getString("user_json", null);
    try {
      return new JSONObject(saved != null && !saved.isEmpty() ? saved : FIXTURE_USER_DEFAULT);
    } catch (Exception e) {
      try { return new JSONObject(FIXTURE_USER_DEFAULT); } catch (Exception ignored) { return new JSONObject(); }
    }
  }

  private static synchronized JSONObject mergeFixtureUser(Context context, JSONObject patch) {
    JSONObject u = fixtureUser(context);
    if (patch != null && fixtureEnabled && debuggable(context)) {
      java.util.Iterator<String> keys = patch.keys();
      while (keys.hasNext()) {
        String k = keys.next();
        try { u.put(k, patch.get(k)); } catch (Exception ignored) {}
      }
      context.getSharedPreferences(FIXTURE_PREFS, Context.MODE_PRIVATE).edit().putString("user_json", u.toString()).commit();
    }
    return u;
  }

  public static File fixtureVideo(Context context) {
    if (!fixtureEnabled || context == null) return null;
    File fixtureFile = new File(context.getCacheDir(), "fixture_short.mp4");
    if (!fixtureFile.exists() || fixtureFile.length() == 0) {
      try (InputStream in = context.getAssets().open("short_sample.mp4"); FileOutputStream out = new FileOutputStream(fixtureFile)) {
        byte[] buf = new byte[8192];
        int r;
        while ((r = in.read(buf)) != -1) out.write(buf, 0, r);
      } catch (Exception ignored) {}
    }
    return fixtureFile.exists() && fixtureFile.length() > 0 ? fixtureFile : null;
  }

  public static byte[] fixtureThumbnail(Context context) {
    File fixtureFile = fixtureVideo(context);
    if (fixtureFile == null) return null;
    android.media.MediaMetadataRetriever retriever = new android.media.MediaMetadataRetriever();
    try {
      retriever.setDataSource(fixtureFile.getAbsolutePath());
      android.graphics.Bitmap frame = android.os.Build.VERSION.SDK_INT >= 27
        ? retriever.getScaledFrameAtTime(0, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 360, 640)
        : null;
      if (frame == null) return null;
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out);
      frame.recycle();
      return out.toByteArray();
    } catch (Exception ignored) {
      return null;
    } finally {
      try { retriever.release(); } catch (Exception ignored) {}
    }
  }

  private static final class FixtureResult {
    final JSONObject data;
    final String error;
    final int status;
    FixtureResult(JSONObject data, String error, int status) {
      this.data = data;
      this.error = error;
      this.status = status;
    }
  }

  public static boolean intercept(NativeApi api, String method, String path, JSONObject data, NativeApi.Result callback, Handler main) {
    if (!isFixtureEnabled()) return false;
    FixtureResult fr = offlineFixture(api == null ? null : api.context(), method, path, data);
    if (main != null && callback != null) main.post(() -> callback.done(fr.data, fr.error, fr.status));
    return true;
  }

  private static FixtureResult offlineFixture(Context appContext, String method, String path, JSONObject data) {
    String cleanPath = path.split("\\?", 2)[0];
    long nowTime = System.currentTimeMillis();
    long postTime = nowTime - 3600000L;
    try {
      if ("GET".equals(method) && "/api/me".equals(cleanPath)) {
        JSONObject wrap = new JSONObject();
        wrap.put("user", fixtureUser(appContext));
        return new FixtureResult(wrap, null, 200);
      }
      if ("POST".equals(method) && "/api/me/password".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"message\":\"Đã đổi mật khẩu thành công\"}"), null, 200);
      }
      if ("GET".equals(method) && "/api/me/privacy-consent".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"accepted\":true}"), null, 200);
      }
      if ("POST".equals(method) && "/api/me/privacy-consent".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"success\":true}"), null, 200);
      }
      if ("PATCH".equals(method) && "/api/me".equals(cleanPath)) {
        JSONObject wrap = new JSONObject();
        wrap.put("user", mergeFixtureUser(appContext, data));
        return new FixtureResult(wrap, null, 200);
      }
      if ("GET".equals(method) && "/api/me/sessions".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"sessions\":[{\"id\":\"sess_1\",\"label\":\"Pixel 6 · Android 14\",\"current\":true,\"expires\":\"2026-12-01T00:00:00Z\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/stories".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"stories\":[{\"id\":\"st_1\",\"body\":\"Khoảnh khắc cuối tuần cùng Kinnect!\",\"created\":" + postTime + ",\"mediaUrl\":\"/story.jpg\",\"user\":{\"id\":\"usr_story\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\"},\"author\":{\"id\":\"usr_story\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\"}}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/posts".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"posts\":[{\"id\":\"post_1\",\"body\":\"Chào mừng bạn đến với Kinnect! Trải nghiệm kết nối sống đúng mình.\",\"content\":\"Chào mừng bạn đến với Kinnect! Trải nghiệm kết nối sống đúng mình.\",\"created\":" + postTime + ",\"createdAt\":\"2026-11-13T00:00:00Z\",\"user_id\":\"usr_qa_review\",\"visibility\":\"public\",\"author\":{\"id\":\"usr_qa_review\",\"name\":\"Minh Anh\",\"username\":\"minhanh\"},\"likes\":15,\"comments\":4,\"reactionsCount\":24,\"myReaction\":\"love\"}]}"), null, 200);
      }
      if ("POST".equals(method) && cleanPath.matches("/api/posts/[^/]+/reaction")) {
        return new FixtureResult(new JSONObject("{\"success\":true,\"myReaction\":\"love\",\"reactionsCount\":25}"), null, 200);
      }
      if ("GET".equals(method) && (cleanPath.matches("/api/posts/[^/]+/comments") || cleanPath.matches("/api/posts/[^/]+/comments/comments") || cleanPath.matches("/api/shorts/[^/]+/comments") || cleanPath.matches("/api/shorts/[^/]+/comments/comments"))) {
        return new FixtureResult(new JSONObject("{\"comments\":[{\"id\":\"c_1\",\"body\":\"Chào mừng bạn gia nhập!\",\"content\":\"Chào mừng bạn gia nhập!\",\"author\":{\"id\":\"u2\",\"name\":\"Hoàng Nam\",\"username\":\"nam_h\"},\"created\":" + (nowTime - 1800000L) + ",\"createdAt\":\"2026-11-13T00:05:00Z\",\"likes\":2,\"myReaction\":null},{\"id\":\"c_2\",\"parentId\":\"c_1\",\"body\":\"Cảm ơn Hoàng Nam nhé!\",\"content\":\"Cảm ơn Hoàng Nam nhé!\",\"author\":{\"id\":\"usr_qa_review\",\"name\":\"Minh Anh\",\"username\":\"minhanh\"},\"created\":" + (nowTime - 900000L) + ",\"createdAt\":\"2026-11-13T00:20:00Z\",\"likes\":1,\"myReaction\":\"love\"}]}"), null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/users/[^/]+/stats")) {
        return new FixtureResult(new JSONObject("{\"posts\":12,\"followers\":128,\"following\":64}"), null, 200);
      }
      if ("POST".equals(method) && cleanPath.matches("/api/stories/[^/]+/view")) {
        return new FixtureResult(new JSONObject("{\"success\":true}"), null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/users/[^/]+/followers")) {
        return new FixtureResult(new JSONObject("{\"users\":[]}"), null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/users/[^/]+/following")) {
        return new FixtureResult(new JSONObject("{\"users\":[]}"), null, 200);
      }
      if ("POST".equals(method) && cleanPath.matches("/api/users/[^/]+/follow")) {
        return new FixtureResult(new JSONObject("{\"success\":true}"), null, 200);
      }
      if ("POST".equals(method) && cleanPath.matches("/api/posts/[^/]+/like")) {
        return new FixtureResult(new JSONObject("{\"success\":true,\"reactionsCount\":25,\"myReaction\":\"like\"}"), null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/posts/[^/]+/reactions")) {
        return new FixtureResult(new JSONObject("{\"users\":[{\"id\":\"u2\",\"name\":\"Hoàng Nam\",\"username\":\"nam_h\",\"reaction\":\"love\"},{\"id\":\"u3\",\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\",\"reaction\":\"like\"}]}"), null, 200);
      }
      if ("POST".equals(method) && (cleanPath.matches("/api/posts/[^/]+/comments") || cleanPath.matches("/api/posts/[^/]+/comments/comments") || cleanPath.matches("/api/shorts/[^/]+/comments") || cleanPath.matches("/api/shorts/[^/]+/comments/comments"))) {
        return new FixtureResult(new JSONObject("{\"comment\":{\"id\":\"c_new\",\"body\":\"Cảm ơn mọi người!\",\"content\":\"Cảm ơn mọi người!\",\"author\":{\"id\":\"usr_qa_review\",\"name\":\"Minh Anh\",\"username\":\"minhanh\"},\"created\":" + nowTime + ",\"createdAt\":\"2026-11-13T00:10:00Z\"}}"), null, 200);
      }
      if ("GET".equals(method) && "/api/discover".equals(cleanPath)) {
        if (path.contains("khong_tim_thay")) return new FixtureResult(new JSONObject("{\"users\":[],\"total\":0}"), null, 200);
        if (path.contains("c%C3%A0+ph%C3%AA") || path.contains("c%C3%A0%20ph%C3%AA") || path.contains("cà phê")) {
          return new FixtureResult(new JSONObject("{\"users\":[{\"id\":\"u4\",\"name\":\"Kinnect Coffee & Book\",\"username\":\"cafe_kinnect\",\"bio\":\"Không gian cà phê & kết nối bạn bè\"},{\"id\":\"u2\",\"name\":\"Hoàng Nam\",\"username\":\"nam_h\",\"bio\":\"Nhiếp ảnh & Cà phê sáng\"}]}"), null, 200);
        }
        return new FixtureResult(new JSONObject("{\"users\":[{\"id\":\"u1\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\",\"bio\":\"Yêu đời, thích khám phá\"},{\"id\":\"u2\",\"name\":\"Hoàng Nam\",\"username\":\"nam_h\",\"bio\":\"Nhiếp ảnh & Sáng tạo nội dung\"},{\"id\":\"u3\",\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\",\"bio\":\"Yêu âm nhạc & Du lịch\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/shorts".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"shorts\":[{\"id\":\"s1\",\"title\":\"Khoảnh khắc cuộc sống\",\"video\":\"/api/shorts/s1/video\",\"author\":{\"id\":\"usr_qa_review\",\"name\":\"Minh Anh\",\"username\":\"minhanh\"},\"likes\":89,\"comments\":12},{\"id\":\"s2\",\"title\":\"Giai điệu kết nối\",\"video\":\"/api/shorts/s2/video\",\"author\":{\"id\":\"u2\",\"name\":\"Hoàng Nam\",\"username\":\"nam_h\"},\"likes\":142,\"comments\":25}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/conversations".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"users\":[{\"id\":\"u3\",\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\",\"isActive\":true,\"unread\":1,\"last\":{\"body\":\"Hẹn gặp bạn cuối tuần này nhé!\",\"created\":" + (nowTime - 900000L) + ",\"mine\":false}}],\"conversations\":[{\"id\":\"c1\",\"title\":\"Bảo Ngọc\",\"lastMessage\":\"Hẹn gặp bạn cuối tuần này nhé!\",\"updatedAt\":\"2026-11-13T00:00:00Z\",\"unread\":1}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/groups".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"groups\":[{\"id\":\"g1\",\"name\":\"Cộng đồng Nhiếp ảnh Kinnect\",\"members\":[{\"id\":\"usr_qa_review\"},{\"id\":\"u2\"},{\"id\":\"u3\"}],\"unread\":0,\"last\":{\"body\":\"Chào mừng mọi người đến nhóm âm nhạc!\",\"created\":" + (nowTime - 1800000L) + ",\"name\":\"Hoàng Nam\",\"mine\":false}}]}"), null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/users/[^/]+/messages")) {
        return new FixtureResult(new JSONObject("{\"messages\":[{\"id\":\"m_1\",\"sender\":\"u3\",\"body\":\"Chào bạn, rất vui được làm quen!\",\"created\":" + (nowTime - 3600000L) + ",\"createdAt\":\"2026-11-13T00:00:00Z\"},{\"id\":\"m_2\",\"sender\":\"usr_qa_review\",\"body\":\"Chào Bảo Ngọc nhé!\",\"created\":" + (nowTime - 3540000L) + ",\"createdAt\":\"2026-11-13T00:01:00Z\"}]}"), null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/groups/[^/]+/messages")) {
        return new FixtureResult(new JSONObject("{\"messages\":[{\"id\":\"gm_1\",\"sender\":\"u2\",\"body\":\"Chào mừng mọi người đến nhóm âm nhạc!\",\"created\":" + (nowTime - 3600000L) + ",\"createdAt\":\"2026-11-13T00:00:00Z\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/friends".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"users\":[{\"id\":\"f1\",\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\",\"bio\":\"Yêu âm nhạc & Du lịch\"},{\"id\":\"f2\",\"name\":\"Hoàng Nam\",\"username\":\"nam_h\",\"bio\":\"Nhiếp ảnh & Sáng tạo nội dung\"}],\"friends\":[{\"id\":\"f1\",\"name\":\"Bảo Ngọc\",\"username\":\"baongoc\"},{\"id\":\"f2\",\"name\":\"Hoàng Nam\",\"username\":\"nam_h\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/friend-suggestions".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"users\":[{\"id\":\"u4\",\"name\":\"Khánh Linh\",\"username\":\"linh_k\",\"bio\":\"Nhà thiết kế trải nghiệm\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/friend-requests".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"requests\":[{\"id\":\"fr_1\",\"user\":{\"id\":\"u4\",\"name\":\"Khánh Linh\",\"username\":\"linh_k\"},\"createdAt\":\"2026-11-13T00:00:00Z\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/notifications".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"notifications\":[{\"id\":\"n1\",\"kind\":\"like\",\"created\":" + (nowTime - 7200000L) + ",\"createdAt\":\"2026-11-13T00:00:00Z\",\"seen\":0,\"actor\":{\"id\":\"u2\",\"name\":\"Hoàng Nam\",\"username\":\"nam_h\"}}]}"), null, 200);
      }
      if ("POST".equals(method) && "/api/notifications".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"success\":true}"), null, 200);
      }
      if ("GET".equals(method) && "/api/store".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"packages\":[{\"id\":\"pkg_aurora\",\"name\":\"Phong cách Cực quang\",\"kind\":\"style\",\"tier\":\"featured\",\"priceCoins\":200,\"description\":\"Hiệu ứng viền hồ sơ phát sáng cực quang huyền ảo\"},{\"id\":\"pkg_neon\",\"name\":\"Phong cách Neon Tím\",\"kind\":\"style\",\"tier\":\"popular\",\"priceCoins\":350,\"description\":\"Đổi màu giao diện chủ đạo sang tông Neon Cyberpunk\"},{\"id\":\"pkg_studio_pro\",\"name\":\"Kinnect Studio Pro\",\"kind\":\"studio\",\"line\":\"video\",\"tier\":\"pro\",\"priceCoins\":500,\"description\":\"Quay video không giới hạn, mở khóa 24 bộ lọc điện ảnh\"}],\"products\":[{\"id\":\"prod_badge_vip\",\"name\":\"Huy hiệu VIP Kinnect\",\"kind\":\"style\",\"priceCoins\":150,\"description\":\"Huy hiệu nổi bật bên cạnh tên hiển thị\"}],\"coins\":1200,\"balance\":1200,\"ownedPackages\":[\"pkg_aurora\"],\"owned\":[]}"), null, 200);
      }
      if ("POST".equals(method) && "/api/store/packages/buy".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"success\":true,\"packageId\":\"pkg_aurora\",\"balance\":1000}"), null, 200);
      }
      if ("POST".equals(method) && "/api/store/packages/apply".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"success\":true,\"applied\":\"pkg_aurora\"}"), null, 200);
      }
      if ("GET".equals(method) && ("/api/commerce/catalog".equals(cleanPath) || "/api/studio/catalog".equals(cleanPath))) {
        return new FixtureResult(new JSONObject("{\"accountId\":\"usr_qa_review\",\"studioProFree\":true,\"studioProPermanent\":true,\"owned\":[\"kinnect_studio_pro\"]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/music".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"tracks\":[{\"id\":\"m1\",\"title\":\"Giai điệu kết nối\",\"artist\":\"Kinnect Audio\",\"duration\":185,\"url\":\"/music/m1.mp3\"},{\"id\":\"m2\",\"title\":\"Nắng sớm thành phố\",\"artist\":\"Minh Anh feat. Nam\",\"duration\":210,\"url\":\"/music/m2.mp3\"},{\"id\":\"m3\",\"title\":\"Khoảnh khắc thanh xuân\",\"artist\":\"Kinnect Vibes\",\"duration\":195,\"url\":\"/music/m3.mp3\"},{\"id\":\"m4\",\"title\":\"Nhịp đập cuộc sống\",\"artist\":\"Bảo Ngọc\",\"duration\":240,\"url\":\"/music/m4.mp3\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/live".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"rooms\":[{\"id\":\"room_1\",\"title\":\"Giao lưu âm nhạc cuối tuần\",\"host\":\"Minh Anh\",\"liveMode\":\"chat\",\"hostId\":\"usr_qa_review\",\"viewers\":42}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/live/gifts".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"enabled\":true,\"experience\":true,\"balance\":1200,\"version\":1,\"inventory\":[],\"items\":[{\"id\":\"rose\",\"costCoins\":10,\"tier\":\"small\",\"comboable\":true},{\"id\":\"star\",\"costCoins\":50,\"tier\":\"small\",\"comboable\":true},{\"id\":\"crown\",\"costCoins\":500,\"tier\":\"medium\",\"comboable\":true},{\"id\":\"castle\",\"costCoins\":2000,\"tier\":\"legendary\",\"comboable\":false}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/wallet".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"balance\":1200,\"diamonds\":450,\"currency\":\"VND\",\"records\":[{\"id\":\"w_1\",\"title\":\"Nạp xu\",\"amount\":500,\"created\":\"2026-11-12T10:00:00Z\",\"type\":\"topup\",\"category\":\"topup\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/call-config".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"iceServers\":[{\"urls\":\"stun:stun.l.google.com:19302\"}],\"token\":\"mock_rtc_token\"}"), null, 200);
      }
      if ("GET".equals(method) && "/api/support".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"user\":{\"id\":\"usr_support\",\"name\":\"Kinnect Support\",\"username\":\"support\"}}"), null, 200);
      }
      if ("GET".equals(method) && cleanPath.endsWith("/private")) {
        return new FixtureResult(new JSONObject("{\"status\":\"owner\",\"photos\":[{\"id\":\"p_1\",\"url\":\"/private_1.jpg\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/me/private/requests".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"requests\":[]}"), null, 200);
      }
      JSONObject notFound = new JSONObject();
      try { notFound.put("error", "Fixture endpoint not mapped: " + method + " " + cleanPath); } catch (Exception ignored) {}
      return new FixtureResult(notFound, "Fixture unmapped endpoint", 404);
    } catch (Exception e) {
      JSONObject err = new JSONObject();
      try { err.put("error", "Fixture error: " + e.getMessage()); } catch (Exception ignored) {}
      return new FixtureResult(err, e.getMessage(), 500);
    }
  }

  public static void onAttempt(String method, String path, int counter) {
    Log.i(TAG, "API_TRANSPORT_ATTEMPT: method=" + method + " path=" + path + " counter=" + counter + " fixture=" + fixtureEnabled);
  }

  public static void onBeforeExec(String path, String origin) {
    Log.i(TAG, "BEFORE_EXEC: " + path + " origin=" + origin);
  }

  public static void onInsideExec(String path) {
    Log.i(TAG, "INSIDE_EXEC: " + path);
  }

  public static String transportBlock(String method, String path, String server) {
    if (debugLoopbackOrigin != null && (debugOffline || (debugForcePrimaryConnectFailure && server != null && server.equals(debugLoopbackOrigin)))) {
      String why = debugOffline ? "qa-debug-offline" : "qa-debug-primary-failure";
      Log.w(TAG, "DEBUG_TRANSPORT_BLOCK: " + why + " " + method + " " + path.split("\\?", 2)[0]);
      return why;
    }
    return null;
  }

  private static boolean debugPinnedHost(String server) {
    return server != null && (server.equals(debugLoopbackOrigin) || (debugFallbackOrigin != null && server.equals(debugFallbackOrigin)));
  }

  public static void onLoopbackOpen(String method, String path, String server, String session, boolean hasSnapshot) {
    if (debugLoopbackOrigin == null) return;
    boolean hasSession = session != null && session.startsWith("kinnect_session=") && session.length() > "kinnect_session=".length();
    String role = server != null && server.equals(debugLoopbackOrigin) ? "primary" : (debugFallbackOrigin != null && server != null && server.equals(debugFallbackOrigin) ? "fallback" : "other");
    Log.i(TAG, "DEBUG_LOOPBACK_OPEN: role=" + role + " method=" + method + " path=" + path.split("\\?", 2)[0] + " hasSession=" + hasSession + " match=" + debugPinnedHost(server));
    if ("GET".equals(method)) Log.i(TAG, "DEBUG_GET_ETAG: path=" + path.split("\\?", 2)[0] + " ifNoneMatch=" + hasSnapshot);
  }

  public static void decorate(HttpURLConnection connection, String server) {
    if (!(connection instanceof HttpsURLConnection) || debugLoopbackSslFactory == null || !debugPinnedHost(server)) return;
    HttpsURLConnection https = (HttpsURLConnection) connection;
    https.setSSLSocketFactory(debugLoopbackSslFactory);
    https.setHostnameVerifier((hostname, sslSession) -> "10.0.2.2".equals(hostname) || "127.0.0.1".equals(hostname));
  }

  public static int readTimeout(String method) {
    if ("GET".equals(method)) return debugLoopbackOrigin != null ? 30000 : 12000;
    return 600000;
  }

  public static void onHttp(String method, String path, String server, int status, boolean via304) {
    if (debugLoopbackOrigin == null) return;
    String role = server != null && server.equals(debugLoopbackOrigin) ? "primary" : (debugFallbackOrigin != null && server != null && server.equals(debugFallbackOrigin) ? "fallback" : "other");
    Log.i(TAG, "DEBUG_HTTP: role=" + role + " " + method + " " + path.split("\\?", 2)[0] + " status=" + status + " via304=" + via304);
  }

  public static void onTimeout(String method, String path, String server, Exception timeout) {
    if (debugLoopbackOrigin != null && server != null && server.equals(debugLoopbackOrigin)) {
      Log.w(TAG, "DEBUG_LOOPBACK_TIMEOUT: " + method + " " + path + " -> " + (timeout == null ? "" : timeout.getMessage()));
    }
  }

  public static void onException(String method, String path, String server, Exception caught) {
    if (debugLoopbackOrigin != null && server != null && server.equals(debugLoopbackOrigin) && caught != null) {
      Log.w(TAG, "DEBUG_LOOPBACK_EXC: " + method + " " + path + " -> " + caught.getClass().getName() + ": " + caught.getMessage());
    }
  }

  public static boolean debugOffline() { return debugOffline; }

  public static boolean isDebugPrimaryPair(String origin) {
    return debugFallbackOrigin != null && origin != null && origin.equals(debugLoopbackOrigin);
  }

  public static boolean isDebugFallback(String server) {
    return debugFallbackOrigin != null && debugFallbackOrigin.equals(server);
  }

  public static String failoverTarget(String failed, String origin) {
    if (debugFallbackOrigin != null && failed != null && failed.equals(debugLoopbackOrigin) && origin != null && origin.equals(debugLoopbackOrigin)) return debugFallbackOrigin;
    return null;
  }

  public static void onFailover(NativeApi api) {
    boolean savedPrimary = api != null && debugLoopbackOrigin != null && !api.storedSession(debugLoopbackOrigin).isEmpty();
    Log.i(TAG, "DEBUG_FAILOVER: to=fallback cookieCleared=true primarySaved=" + savedPrimary);
  }

  public static boolean suppressProbe() {
    return fixtureEnabled || debugOffline || debugForcePrimaryConnectFailure;
  }

  public static boolean hasDebugFallback() { return debugFallbackOrigin != null; }

  public static String debugProbeOrigin(String currentOrigin) {
    if (debugFallbackOrigin == null || currentOrigin == null || !currentOrigin.equals(debugFallbackOrigin)) return null;
    return debugLoopbackOrigin;
  }

  public static boolean probeAllowsSwitchback() {
    return !debugForcePrimaryConnectFailure && !debugOffline;
  }

  public static String pinnedOrigin() { return debugLoopbackOrigin; }

  public static synchronized boolean pinLoopback(NativeApi api, Context context, String originUrl, String certSha256) {
    if (api == null || !debuggable(context) || originUrl == null || certSha256 == null) return false;
    if (!originUrl.matches("^https://(10\\.0\\.2\\.2|127\\.0\\.0\\.1):\\d{1,5}$") || !certSha256.matches("^[0-9a-fA-F]{64}$")) return false;
    final String expectedSha = certSha256.toLowerCase(java.util.Locale.ROOT);
    try {
      javax.net.ssl.TrustManager[] tms = new javax.net.ssl.TrustManager[] {
        new javax.net.ssl.X509TrustManager() {
          public java.security.cert.X509Certificate[] getAcceptedIssuers() { return new java.security.cert.X509Certificate[0]; }
          public void checkClientTrusted(java.security.cert.X509Certificate[] chain, String authType) {}
          public void checkServerTrusted(java.security.cert.X509Certificate[] chain, String authType) throws java.security.cert.CertificateException {
            if (chain == null || chain.length == 0) throw new java.security.cert.CertificateException("Empty cert chain");
            try {
              byte[] digest = java.security.MessageDigest.getInstance("SHA-256").digest(chain[0].getEncoded());
              StringBuilder sb = new StringBuilder();
              for (byte b : digest) sb.append(String.format(java.util.Locale.ROOT, "%02x", b));
              if (!expectedSha.equals(sb.toString())) throw new java.security.cert.CertificateException("Pin mismatch");
            } catch (java.security.NoSuchAlgorithmException e) {
              throw new java.security.cert.CertificateException(e);
            }
          }
        }
      };
      javax.net.ssl.SSLContext sc = javax.net.ssl.SSLContext.getInstance("TLS");
      sc.init(null, tms, new java.security.SecureRandom());
      debugLoopbackSslFactory = sc.getSocketFactory();
      debugLoopbackOrigin = originUrl;
      fixtureEnabled = false;
      api.configure(originUrl);
      Log.i(TAG, "DEBUG_LOOPBACK_PINNED: origin=" + originUrl);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  public static synchronized boolean pinFailover(NativeApi api, Context context, String primaryUrl, String fallbackUrl, String certSha256) {
    if (primaryUrl == null || fallbackUrl == null || primaryUrl.equals(fallbackUrl)) return false;
    if (!fallbackUrl.matches("^https://(10\\.0\\.2\\.2|127\\.0\\.0\\.1):\\d{1,5}$")) return false;
    if (!pinLoopback(api, context, primaryUrl, certSha256)) return false;
    debugFallbackOrigin = fallbackUrl;
    Log.i(TAG, "DEBUG_FAILOVER_PINNED: primary=" + primaryUrl + " fallback=" + fallbackUrl);
    return true;
  }

  public static synchronized void applyFlags(Boolean forcePrimaryFailure, Boolean offline) {
    if (debugLoopbackOrigin == null) return;
    if (forcePrimaryFailure != null) debugForcePrimaryConnectFailure = forcePrimaryFailure.booleanValue();
    if (offline != null) debugOffline = offline.booleanValue();
    Log.i(TAG, "DEBUG_TRANSPORT_FLAGS: primaryFailure=" + debugForcePrimaryConnectFailure + " offline=" + debugOffline);
  }

  public static void logSavedPrimary(NativeApi api) {
    if (debugLoopbackOrigin == null || api == null) return;
    String origin = api.activeOrigin();
    String role = origin.equals(debugLoopbackOrigin) ? "primary" : (debugFallbackOrigin != null && origin.equals(debugFallbackOrigin) ? "fallback" : "other");
    Log.i(TAG, "DEBUG_PRIMARY_SAVED: " + !api.storedSession(debugLoopbackOrigin).isEmpty() + " originRole=" + role);
  }

  public static synchronized boolean switchBack(NativeApi api) {
    if (debugFallbackOrigin == null || api == null) return false;
    debugForcePrimaryConnectFailure = false;
    debugOffline = false;
    api.switchBackToPrimary();
    Log.i(TAG, "DEBUG_SWITCHBACK: hasSession=" + !api.activeCookie().isEmpty());
    return !api.activeCookie().isEmpty();
  }

  public static void onTransientClear(NativeApi api) {
    if (debugLoopbackOrigin != null && api != null) Log.i(TAG, "DEBUG_TRANSIENT_CLEAR: primarySaved=" + !api.storedSession(debugLoopbackOrigin).isEmpty());
  }

  public static void onSessionWiped(NativeApi api) {
    if (debugLoopbackOrigin != null) Log.i(TAG, "DEBUG_SESSION_WIPED");
  }

  public static boolean savedPrimary(NativeApi api) {
    return debugLoopbackOrigin != null && api != null && !api.storedSession(debugLoopbackOrigin).isEmpty();
  }

  public static boolean forceFailover(NativeApi api) {
    if (debugLoopbackOrigin == null || debugFallbackOrigin == null || api == null) return false;
    if (!api.activeOrigin().equals(debugLoopbackOrigin)) return false;
    return api.failoverFrom(debugLoopbackOrigin);
  }

  public static void forgetDevice(NativeApi api) {
    if (debugLoopbackOrigin == null || api == null) return;
    api.clearRememberedDevice();
  }

  public static String loopbackOrigin() { return debugLoopbackOrigin; }
  public static String fallbackOrigin() { return debugFallbackOrigin; }
}
