package app.kinnect.live;

import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import java.io.File;
import java.net.HttpURLConnection;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Release variant: compile-time interface only. No QA fixtures, sample media, or transport hooks. */
public final class QaRuntime {
  private QaRuntime() {}

  public static boolean armReviewFixture(Context context, Intent intent) { return false; }
  public static boolean wantsSessionRegression(Intent intent) { return false; }
  public static boolean wantsWebRtcSelfTest(Context context, Intent intent) { return false; }
  public static void runWebRtcSelfTest(Context context) {}
  public static boolean wantsLoopbackWipe(Intent intent, NativeApi api) { return false; }
  public static boolean wantsFixtureRoom(Context context, Intent intent) { return false; }
  public static void pinFromIntent(Context context, Intent intent, NativeApi api) {}
  public static void applyTransportIntent(Context context, Intent intent, NativeApi api, Runnable onRestored) {}
  public static void applyTheme(Context context, Intent intent) {}
  public static void sessionRegression(Boolean pass) {}
  public static void explicitLogout(int status, boolean failed) {}
  public static void uiSay(Context context, String text) {}
  public static void shortsPlaying(int index, String id, int pos, boolean muted) {}
  public static void shortsPause(int pos) {}
  public static void shortsStart(int pos) {}
  public static void passwordEmptyCurrent(String error, int count) {}
  public static void passwordShort(String error, int count) {}
  public static void passwordMismatch(String error, int count) {}
  public static void passwordPassed() {}

  public static String syntheticSessionCookie() { return ""; }
  public static String syntheticDeviceCookie() { return ""; }
  public static JSONObject regressionUser() throws JSONException { throw new JSONException("unavailable"); }
  public static JSONObject staleUser() throws JSONException { throw new JSONException("unavailable"); }
  public static JSONObject reviewUser() throws JSONException { throw new JSONException("unavailable"); }
  public static JSONObject feedStory() throws JSONException { throw new JSONException("unavailable"); }
  public static JSONObject shortCommentsItem() throws JSONException { throw new JSONException("unavailable"); }
  public static JSONObject chatDirectUser() throws JSONException { throw new JSONException("unavailable"); }
  public static JSONObject chatGroup() throws JSONException { throw new JSONException("unavailable"); }
  public static JSONObject chatMenuUser() throws JSONException { throw new JSONException("unavailable"); }
  public static JSONObject incomingCall() throws JSONException { return null; }
  public static JSONObject liveFixtureWelcome() throws JSONException { return null; }
  public static JSONArray liveFixtureRooms() throws JSONException { return null; }
  public static void liveFixtureEntered() {}
  public static String liveFixtureStatusText() { return null; }
  public static boolean fixtureMusicPreview(Context context, android.media.MediaPlayer player, String url) { return false; }
  public static void musicPreviewStop(Context context, boolean wasPlaying) {}

  public static synchronized boolean enableFixture(Context context, boolean enable) { return false; }
  public static boolean isFixtureEnabled() { return false; }
  public static synchronized void resetFixtureState(Context context) {}
  public static synchronized JSONObject fixtureUser(Context context) { return new JSONObject(); }
  public static File fixtureVideo(Context context) { return null; }
  public static byte[] fixtureThumbnail(Context context) { return null; }

  public static boolean intercept(NativeApi api, String method, String path, JSONObject data, NativeApi.Result callback, Handler main) { return false; }

  public static void onAttempt(String method, String path, int counter) {}
  public static void onBeforeExec(String path, String origin) {}
  public static void onInsideExec(String path) {}
  public static String transportBlock(String method, String path, String server) { return null; }
  public static void onLoopbackOpen(String method, String path, String server, String session, boolean hasSnapshot) {}
  public static void decorate(HttpURLConnection connection, String server) {}
  public static int readTimeout(String method) { return "GET".equals(method) ? 12000 : 600000; }
  public static void onHttp(String method, String path, String server, int status, boolean via304) {}
  public static void onTimeout(String method, String path, String server, Exception timeout) {}
  public static void onException(String method, String path, String server, Exception caught) {}

  public static boolean debugOffline() { return false; }
  public static boolean isDebugPrimaryPair(String origin) { return false; }
  public static boolean isDebugFallback(String server) { return false; }
  public static String failoverTarget(String failed, String origin) { return null; }
  public static void onFailover(NativeApi api) {}
  public static boolean suppressProbe() { return false; }
  public static boolean hasDebugFallback() { return false; }
  public static String debugProbeOrigin(String currentOrigin) { return null; }
  public static boolean probeAllowsSwitchback() { return true; }
  public static String pinnedOrigin() { return null; }
  public static synchronized boolean pinLoopback(NativeApi api, Context context, String originUrl, String certSha256) { return false; }
  public static synchronized boolean pinFailover(NativeApi api, Context context, String primaryUrl, String fallbackUrl, String certSha256) { return false; }
  public static synchronized void applyFlags(Boolean forcePrimaryFailure, Boolean offline) {}
  public static void logSavedPrimary(NativeApi api) {}
  public static synchronized boolean switchBack(NativeApi api) { return false; }
  public static void onTransientClear(NativeApi api) {}
  public static void onSessionWiped(NativeApi api) {}
  public static boolean savedPrimary(NativeApi api) { return false; }
  public static boolean forceFailover(NativeApi api) { return false; }
  public static void forgetDevice(NativeApi api) {}
  public static String loopbackOrigin() { return null; }
  public static String fallbackOrigin() { return null; }
}
