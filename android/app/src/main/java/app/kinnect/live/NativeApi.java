package app.kinnect.live;

import android.os.Handler;
import android.os.Looper;
import java.io.*;
import java.net.*;
import java.util.concurrent.*;
import org.json.JSONObject;

/**
 * HTTPS API client. Session cookie stays in process memory, never in
 * source/logs.
 */
public final class NativeApi {

  public static final NativeApi shared = new NativeApi();
  private final ExecutorService executor = Executors.newFixedThreadPool(3);
  private final Handler main = new Handler(Looper.getMainLooper());

  private static final class Snapshot {
    final String etag, body;

    Snapshot(String e, String b) {
      etag = e;
      body = b;
    }
  }

  private final java.util.Map<String, Snapshot> snapshots = java.util.Collections
      .synchronizedMap(new java.util.LinkedHashMap<String, Snapshot>() {
        protected boolean removeEldestEntry(java.util.Map.Entry<String, Snapshot> e) {
          return size() > 32;
        }
      });
  private final java.util.Map<String, String> memoryJsonCache = java.util.Collections
      .synchronizedMap(new java.util.LinkedHashMap<String, String>(64, 0.75f, true) {
        protected boolean removeEldestEntry(java.util.Map.Entry<String, String> e) {
          return size() > 64;
        }
      });
  private volatile int epoch = 0;
  private volatile boolean persistSession = true;
  public volatile int apiDispatchCount = 0;
  private SessionStore sessions;

  public void setPersistSession(boolean persist) {
    persistSession = persist;
  }
  private AppCache diskCache;
  private android.content.Context appContext;
  private final ExecutorService mediaCacheExecutor = Executors.newSingleThreadExecutor();
  private final java.util.Set<String> warming = java.util.Collections.synchronizedSet(new java.util.HashSet<>());

  public synchronized void initialize(android.content.Context context, String server) {
    if (sessions != null && diskCache != null)
      return;
    appContext = context.getApplicationContext();
    sessions = new SessionStore(context);
    diskCache = new AppCache(new File(appContext.getCacheDir(), "kinnect-v2"), new AppCache.Codec() {
      public byte[] encode(String key, byte[] data) throws Exception {
        return sessions.sealCache(key, data);
      }

      public byte[] decode(String key, byte[] data) throws Exception {
        return sessions.openCache(key, data);
      }
    }, 128L * 1024 * 1024);
    configure(server);
    cookie = sessions.load(origin);
    device = sessions.loadDevice(origin);
  }

  private String cacheScope() {
    return origin + "\n" + cookie;
  }

  private boolean cacheable(String path) {
    String p = path.split("\\?", 2)[0];
    return java.util.Arrays
        .asList("/api/me", "/api/posts", "/api/stories", "/api/discover", "/api/shorts", "/api/conversations",
            "/api/groups", "/api/notifications", "/api/friends", "/api/friend-requests", "/api/friend-suggestions",
            "/api/store", "/api/wallet", "/api/live/gifts", "/api/music")
        .contains(p) || p.matches("/api/users/[^/]+(?:/messages)?") || p.matches("/api/groups/[^/]+(?:/messages)?")
        || p.matches("/api/(?:posts|shorts)/[^/]+/comments");
  }

  public JSONObject cachedGet(String path) {
    if (cookie.isEmpty() || !cacheable(path))
      return null;
    String scope = cacheScope();
    String memKey = scope + "\njson:" + path;
    String mem = memoryJsonCache.get(memKey);
    if (mem != null) {
      try {
        JSONObject value = new JSONObject(mem);
        value.put("cached", true);
        return value;
      } catch (Exception ignored) {
        memoryJsonCache.remove(memKey);
      }
    }
    if (diskCache == null)
      return null;
    byte[] bytes = diskCache.get(scope, "json:" + path, AppCache.WEEK);
    try {
      if (bytes == null)
        return null;
      String jsonStr = new String(bytes, "UTF-8");
      memoryJsonCache.put(memKey, jsonStr);
      JSONObject value = new JSONObject(jsonStr);
      value.put("cached", true);
      return value;
    } catch (Exception e) {
      return null;
    }
  }

  public byte[] cachedImage(String path) {
    return diskCache == null || cookie.isEmpty() ? null : diskCache.get(cacheScope(), "image:" + path, AppCache.WEEK);
  }

  public void cacheImageBytes(String path, byte[] bytes) {
    if (diskCache != null && !cookie.isEmpty() && path != null && !path.isEmpty() && bytes != null && bytes.length > 0)
      diskCache.put(cacheScope(), "image:" + path, bytes);
  }

  public synchronized void clearSnapshots() {
    snapshots.clear();
    memoryJsonCache.clear();
  }

  /**
   * Remove GET ETag snapshots matching origin + prefix so next GET fetches fresh
   * data while keeping stale-while-revalidate display cache intact.
   */
  public synchronized void clearEtagSnapshot(String prefix) {
    if (prefix == null || prefix.isEmpty())
      return;
    String target = origin + prefix;
    synchronized (snapshots) {
      java.util.Iterator<String> it = snapshots.keySet().iterator();
      while (it.hasNext()) {
        String k = it.next();
        int colon = k.indexOf(':');
        String url = colon >= 0 ? k.substring(colon + 1) : k;
        if (url.startsWith(target))
          it.remove();
      }
    }
  }

  /**
   * Remove GET etag snapshots and cached JSON entries matching origin + prefix.
   */
  public synchronized void clearGetSnapshot(String prefix) {
    if (prefix == null || prefix.isEmpty())
      return;
    clearEtagSnapshot(prefix);
    if (!cookie.isEmpty()) {
      String scope = cacheScope();
      String memPrefix = scope + "\njson:" + prefix;
      synchronized (memoryJsonCache) {
        java.util.Iterator<String> it = memoryJsonCache.keySet().iterator();
        while (it.hasNext()) {
          String k = it.next();
          if (k.startsWith(memPrefix)
              || ("/api/posts".equals(prefix) && k.equals(scope + "\njson:/api/posts?limit=25")))
            it.remove();
        }
      }
      if (diskCache != null) {
        diskCache.removeByPrefix(scope, "json:" + prefix);
        if ("/api/posts".equals(prefix))
          diskCache.remove(scope, "json:/api/posts?limit=25");
      }
    }
  }

  private synchronized void invalidateForMutation(String path) {
    if (path == null || path.isEmpty())
      return;
    String clean = path.split("\\?", 2)[0];
    if (clean.endsWith("/block") || clean.equals("/api/me/avatar") || clean.equals("/api/me/cover")
        || clean.endsWith("/avatar")) {
      snapshots.clear();
      memoryJsonCache.clear();
      if (diskCache != null)
        diskCache.clear();
      return;
    }
    // Use ETag-only invalidation for stale-while-revalidate screens (chat, inbox,
    // feed, shorts, profile)
    // so reopening them renders cached content instantaneously while still fetching
    // fresh updates from server.
    if (clean.startsWith("/api/posts")) {
      clearEtagSnapshot("/api/posts");
      clearEtagSnapshot("/api/posts?limit=25");
      if (clean.contains("/comments"))
        clearEtagSnapshot(clean.replaceFirst("/comments/.*", "/comments"));
    }
    if (clean.startsWith("/api/shorts")) {
      clearEtagSnapshot("/api/shorts");
      if (clean.contains("/comments"))
        clearEtagSnapshot(clean.replaceFirst("/comments/.*", "/comments"));
    }
    if (clean.startsWith("/api/me")) {
      clearGetSnapshot("/api/me");
    }
    if (clean.matches("/api/users/[^/]+/messages.*")) {
      clearEtagSnapshot(clean);
      clearEtagSnapshot("/api/conversations");
    }
    if (clean.matches("/api/groups/[^/]+/messages.*")) {
      clearEtagSnapshot(clean);
      clearEtagSnapshot("/api/groups");
      clearEtagSnapshot("/api/conversations");
    }
    if (clean.startsWith("/api/chat-messages/")) {
      clearEtagSnapshot("/api/users/");
      clearEtagSnapshot("/api/groups/");
      clearEtagSnapshot("/api/conversations");
      clearEtagSnapshot("/api/groups");
    }
    if (clean.startsWith("/api/notifications")) {
      clearEtagSnapshot("/api/notifications");
    }
    if (clean.contains("/friend-request") || clean.startsWith("/api/friends") || clean.endsWith("/friendship")) {
      clearEtagSnapshot("/api/friends");
      clearEtagSnapshot("/api/friend-requests");
      clearEtagSnapshot("/api/friend-suggestions");
      clearEtagSnapshot("/api/discover");
      if (clean.startsWith("/api/users/")) {
        clearEtagSnapshot(clean.replaceFirst("/friendship$", ""));
      }
    }
    if (clean.startsWith("/api/groups")) {
      clearEtagSnapshot("/api/groups");
      clearEtagSnapshot("/api/conversations");
      clearEtagSnapshot(clean);
    }
    if (clean.startsWith("/api/stories")) {
      clearGetSnapshot("/api/stories");
    }
    if (clean.startsWith("/api/store")) {
      clearEtagSnapshot("/api/store");
      clearEtagSnapshot("/api/wallet");
      clearEtagSnapshot("/api/me");
    }
    if (clean.startsWith("/api/wallet")) {
      clearEtagSnapshot("/api/wallet");
      clearEtagSnapshot("/api/store");
      clearEtagSnapshot("/api/me");
    }
  }

  public File cachedVideo(String path) {
    if (fixtureEnabled && appContext != null) {
      File fixtureFile = new File(appContext.getCacheDir(), "fixture_short.mp4");
      if (!fixtureFile.exists() || fixtureFile.length() == 0) {
        try (java.io.InputStream in = appContext.getAssets().open("short_sample.mp4");
            java.io.FileOutputStream out = new java.io.FileOutputStream(fixtureFile)) {
          byte[] buf = new byte[8192];
          int r;
          while ((r = in.read(buf)) != -1)
            out.write(buf, 0, r);
        } catch (Exception ignored) {
        }
      }
      if (fixtureFile.exists() && fixtureFile.length() > 0)
        return fixtureFile;
    }
    return diskCache == null || cookie.isEmpty() ? null : diskCache.video(cacheScope(), path);
  }

  public byte[] cachedThumbnail(String path) {
    if (fixtureEnabled && appContext != null) {
      File fixtureFile = cachedVideo(path);
      if (fixtureFile != null && fixtureFile.exists()) {
        android.media.MediaMetadataRetriever retriever = new android.media.MediaMetadataRetriever();
        try {
          retriever.setDataSource(fixtureFile.getAbsolutePath());
          android.graphics.Bitmap frame = android.os.Build.VERSION.SDK_INT >= 27
              ? retriever.getScaledFrameAtTime(0, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 360, 640)
              : null;
          if (frame != null) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out);
            frame.recycle();
            return out.toByteArray();
          }
        } catch (Exception ignored) {
        } finally {
          try {
            retriever.release();
          } catch (Exception ignored) {
          }
        }
      }
    }
    return diskCache == null || cookie.isEmpty() ? null : diskCache.get(cacheScope(), "thumb:" + path, AppCache.WEEK);
  }

  public void cacheThumbnail(String path, byte[] bytes) {
    if (diskCache != null && !cookie.isEmpty())
      diskCache.put(cacheScope(), "thumb:" + path, bytes);
  }

  public void warmVideo(String path) {
    if (fixtureEnabled || diskCache == null || cookie.isEmpty() || !path.matches("/api/shorts/[^/]+/video")
        || cachedVideo(path) != null)
      return;
    android.net.ConnectivityManager cm = (android.net.ConnectivityManager) appContext
        .getSystemService(android.content.Context.CONNECTIVITY_SERVICE);
    android.net.NetworkCapabilities capabilities = cm == null ? null : cm.getNetworkCapabilities(cm.getActiveNetwork());
    if (capabilities == null || !capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI))
      return;
    final String scope = cacheScope(), server = origin, jar = jar(), key = scope + path;
    final int revision = epoch;
    if (!warming.add(key))
      return;
    mediaCacheExecutor.execute(() -> {
      HttpURLConnection c = null;
      try {
        if (revision != epoch)
          return;
        c = (HttpURLConnection) new URL(server + path).openConnection();
        c.setConnectTimeout(8000);
        c.setReadTimeout(15000);
        c.setInstanceFollowRedirects(false);
        c.setRequestProperty("Cookie", jar);
        if (c.getResponseCode() == 200 && String.valueOf(c.getContentType()).startsWith("video/")
            && c.getContentLengthLong() <= 32L * 1024 * 1024) {
          byte[] bytes = read(c.getInputStream(), 32 * 1024 * 1024);
          if (revision == epoch) {
            diskCache.put(scope, "video:" + path, bytes);
            File local = diskCache.video(scope, path);
            if (local != null) {
              android.media.MediaMetadataRetriever retriever = new android.media.MediaMetadataRetriever();
              try {
                retriever.setDataSource(local.getAbsolutePath());
                android.graphics.Bitmap frame = android.os.Build.VERSION.SDK_INT >= 27
                    ? retriever.getScaledFrameAtTime(0, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 240,
                        384)
                    : null;
                if (frame != null) {
                  ByteArrayOutputStream out = new ByteArrayOutputStream();
                  frame.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, out);
                  frame.recycle();
                  if (revision == epoch)
                    diskCache.put(scope, "thumb:" + path, out.toByteArray());
                }
              } finally {
                retriever.release();
              }
            }
          }
        }
      } catch (Exception | OutOfMemoryError ignored) {
      } finally {
        if (c != null)
          c.disconnect();
        warming.remove(key);
      }
    });
  }

  private volatile String device = "";

  private static String join(String a, String b) {
    return a.isEmpty() ? b : b.isEmpty() ? a : a + "; " + b;
  }

  /** Cookie header for media players (session + remembered device). */
  public String jar() {
    return join(cookie, device);
  }

  public String origin() {
    return origin;
  }

  private volatile String origin = ServerConfig.DEFAULT_ORIGIN,
      cookie = "";
  private volatile boolean originSwitchAuthRequired = false;
  private volatile String debugLoopbackOrigin = null;
  private volatile javax.net.ssl.SSLSocketFactory debugLoopbackSslFactory = null;

  public String pinnedDebugLoopbackOrigin() {
    return debugLoopbackOrigin;
  }

  public synchronized boolean pinDebugLoopback(android.content.Context context, String originUrl, String certSha256) {
    if (context == null || originUrl == null || certSha256 == null)
      return false;
    boolean isDebug = (context.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (!isDebug)
      return false;
    if (!originUrl.matches("^https://(10\\.0\\.2\\.2|127\\.0\\.0\\.1):\\d{1,5}$")
        || !certSha256.matches("^[0-9a-fA-F]{64}$"))
      return false;
    final String expectedSha = certSha256.toLowerCase(java.util.Locale.ROOT);
    try {
      javax.net.ssl.TrustManager[] tms = new javax.net.ssl.TrustManager[] {
          new javax.net.ssl.X509TrustManager() {
            public java.security.cert.X509Certificate[] getAcceptedIssuers() {
              return new java.security.cert.X509Certificate[0];
            }

            public void checkClientTrusted(java.security.cert.X509Certificate[] chain, String authType) {
            }

            public void checkServerTrusted(java.security.cert.X509Certificate[] chain, String authType)
                throws java.security.cert.CertificateException {
              if (chain == null || chain.length == 0)
                throw new java.security.cert.CertificateException("Empty cert chain");
              try {
                byte[] digest = java.security.MessageDigest.getInstance("SHA-256").digest(chain[0].getEncoded());
                StringBuilder sb = new StringBuilder();
                for (byte b : digest)
                  sb.append(String.format(java.util.Locale.ROOT, "%02x", b));
                if (!expectedSha.equals(sb.toString()))
                  throw new java.security.cert.CertificateException("Pin mismatch");
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
      fixtureEmptyLive = false;
      configure(originUrl);
      android.util.Log.i("KinnectQA", "DEBUG_LOOPBACK_PINNED: origin=" + originUrl);
      return true;
    } catch (Exception e) {
      return false;
    }
  }

  public interface Result {
    void done(JSONObject data, String error, int status);
  }

  public interface Bytes {
    void done(byte[] bytes);
  }

  public synchronized void configure(String value) {
    if (debugLoopbackOrigin != null) {
      origin = debugLoopbackOrigin;
      return;
    }
    String next = ServerConfig.normalize(value);
    if (!next.equals(origin)) {
      cookie = "";
      device = "";
      epoch++;
    }
    origin = next;
  }

  public String cookieFor(String server) {
    return server.equals(origin) ? cookie : "";
  }

  /**
   * Adopt the session handed over by the Kinnect hub to the standalone game
   * module.
   */
  public synchronized void adopt(String server, String cookieHeader) {
    configure(server);
    if (cookieHeader == null || cookieHeader.isEmpty())
      return;
    for (String part : cookieHeader.split(";")) {
      String value = part.trim();
      if (value.startsWith("kinnect_session="))
        cookie = value;
      else if (value.startsWith("kinnect_device="))
        device = value;
    }
    if (sessions != null) {
      if (!cookie.isEmpty())
        sessions.save(origin, cookie);
      if (!device.isEmpty())
        sessions.saveDevice(origin, device);
    }
    epoch++;
    snapshots.clear();
  }

  public synchronized boolean isOriginSwitchAuthRequired() {
    return originSwitchAuthRequired || (ServerConfig.FALLBACK_ORIGIN.equals(origin) && cookie.isEmpty());
  }

  public synchronized void clearTransientSession() {
    cookie = "";
    device = "";
    originSwitchAuthRequired = false;
    epoch++;
    snapshots.clear();
    memoryJsonCache.clear();
  }

  public synchronized void clear() {
    if (diskCache != null)
      diskCache.clear();
    cookie = "";
    device = "";
    persistSession = true;
    originSwitchAuthRequired = false;
    if (sessions != null)
      sessions.wipe();
    epoch++;
    snapshots.clear();
    memoryJsonCache.clear();
  }

  private static volatile boolean fixtureEnabled = false;
  private static volatile boolean fixtureEmptyLive = false;

  public static synchronized boolean enableFixture(android.content.Context context, boolean enable) {
    if (!enable) {
      fixtureEnabled = false;
      fixtureEmptyLive = false;
      return false;
    }
    if (context == null)
      return false;
    boolean isDebug = (context.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (!isDebug) {
      fixtureEnabled = false;
      return false;
    }
    if (shared != null && shared.appContext == null)
      shared.appContext = context.getApplicationContext();
    fixtureEnabled = true;
    return true;
  }

  public static synchronized void setFixtureEmptyLive(android.content.Context context, boolean empty) {
    if (!empty || context == null) {
      fixtureEmptyLive = false;
      return;
    }
    boolean isDebug = (context.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    fixtureEmptyLive = isDebug && fixtureEnabled;
  }

  public static boolean isFixtureEmptyLive() {
    return isFixtureEnabled() && fixtureEmptyLive;
  }

  public static boolean isFixtureEnabled() {
    if (shared != null && shared.debugLoopbackOrigin != null)
      return false;
    if (!fixtureEnabled && shared != null && shared.appContext != null
        && (shared.appContext.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
      java.io.File flag = new java.io.File("/data/local/tmp/kinnect_fixture");
      if (flag.exists())
        fixtureEnabled = true;
    }
    return fixtureEnabled;
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

  private static final String FIXTURE_PREFS = "kinnect_qa_fixture_state";
  private static final String FIXTURE_USER_DEFAULT = "{\"id\":\"u1\",\"username\":\"minhanh\",\"name\":\"Nguyễn Minh Anh\",\"role\":\"user\",\"coins\":12500,\"purchasedCoins\":8500,\"giftedCoins\":4000,\"trialCoins\":4000,\"bio\":\"Nhiếp ảnh đường phố · TP.HCM\",\"followersCount\":128,\"followingCount\":64,\"discoverable\":true,\"showDistance\":true,\"showActivity\":true,\"dmMode\":\"friends\"}";

  public static synchronized void resetFixtureState(android.content.Context context) {
    if (context == null)
      return;
    boolean isDebug = (context.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (!isDebug)
      return;
    fixtureEmptyLive = false;
    context.getSharedPreferences(FIXTURE_PREFS, android.content.Context.MODE_PRIVATE).edit().clear().commit();
  }

  public synchronized JSONObject fixtureUser(android.content.Context context) {
    android.content.Context ctx = context != null ? context.getApplicationContext() : appContext;
    if (!fixtureEnabled || ctx == null) {
      return null;
    }
    boolean isDebug = (ctx.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (!isDebug) {
      return null;
    }
    String saved = ctx.getSharedPreferences(FIXTURE_PREFS, android.content.Context.MODE_PRIVATE).getString("user_json",
        null);
    try {
      return new JSONObject(saved != null && !saved.isEmpty() ? saved : FIXTURE_USER_DEFAULT);
    } catch (Exception e) {
      try {
        return new JSONObject(FIXTURE_USER_DEFAULT);
      } catch (Exception ignored) {
        return new JSONObject();
      }
    }
  }

  private synchronized JSONObject mergeFixtureUser(JSONObject patch) {
    JSONObject u = fixtureUser(appContext);
    if (u == null) {
      return null;
    }
    if (patch != null && fixtureEnabled && appContext != null) {
      boolean isDebug = (appContext.getApplicationInfo().flags
          & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
      if (isDebug) {
        java.util.Iterator<String> keys = patch.keys();
        while (keys.hasNext()) {
          String k = keys.next();
          try {
            u.put(k, patch.get(k));
          } catch (Exception ignored) {
          }
        }
        appContext.getSharedPreferences(FIXTURE_PREFS, android.content.Context.MODE_PRIVATE)
            .edit().putString("user_json", u.toString()).commit();
      }
    }
    return u;
  }

  private FixtureResult offlineFixture(String method, String path, JSONObject data) {
    String cleanPath = path.split("\\?", 2)[0];
    long nowTime = System.currentTimeMillis();
    long postTime = nowTime - 3600000L;
    try {
      if ("GET".equals(method) && "/api/me".equals(cleanPath)) {
        JSONObject fu = fixtureUser(appContext);
        if (fu == null) {
          return new FixtureResult(null, I18n.t("Không thể tải dữ liệu lúc này."), 403);
        }
        JSONObject wrap = new JSONObject();
        wrap.put("user", fu);
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
        JSONObject mu = mergeFixtureUser(data);
        if (mu == null) {
          return new FixtureResult(null, I18n.t("Không thể tải dữ liệu lúc này."), 403);
        }
        JSONObject wrap = new JSONObject();
        wrap.put("user", mu);
        return new FixtureResult(wrap, null, 200);
      }
      if ("GET".equals(method) && "/api/me/sessions".equals(cleanPath)) {
        long expPrimary = nowTime + 30L * 86400000L;
        long expSecondary = nowTime + 14L * 86400000L;
        return new FixtureResult(new JSONObject(
            "{\"sessions\":[{\"id\":\"sess_1\",\"label\":\"Pixel 6 · Android 14\",\"deviceType\":\"android\",\"current\":true,\"expires\":"
                + expPrimary
                + "},{\"id\":\"sess_2\",\"label\":\"Kinnect Web · Chrome Windows\",\"deviceType\":\"web\",\"current\":false,\"expires\":"
                + expSecondary + "}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/stories".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"stories\":[{\"id\":\"st_1\",\"body\":\"Khoảnh khắc cuối tuần cùng Kinnect!\",\"created\":" + postTime
                + ",\"mediaUrl\":\"/story.jpg\",\"user\":{\"id\":\"u4\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\",\"avatar\":\"/api/users/u4/avatar\"},\"author\":{\"id\":\"u4\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\",\"avatar\":\"/api/users/u4/avatar\"}},{\"id\":\"st_2\",\"body\":\"Hoàng hôn tuyệt đẹp!\",\"created\":"
                + (postTime - 1800000L)
                + ",\"media\":{\"kind\":\"image\",\"url\":\"/api/posts/post_1/media\"},\"user\":{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\",\"avatar\":\"/api/users/u2/avatar\"},\"author\":{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\",\"avatar\":\"/api/users/u2/avatar\"}},{\"id\":\"st_3\",\"body\":\"Cà phê sáng thứ bảy ☕\",\"created\":"
                + (postTime - 3600000L)
                + ",\"user\":{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\",\"avatar\":\"/api/users/u3/avatar\"},\"author\":{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\",\"avatar\":\"/api/users/u3/avatar\"}}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/posts".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"posts\":[{\"id\":\"post_1\",\"body\":\"Chào mừng bạn đến với Kinnect! Trải nghiệm kết nối sống đúng mình.\",\"content\":\"Chào mừng bạn đến với Kinnect! Trải nghiệm kết nối sống đúng mình.\",\"created\":"
                + postTime
                + ",\"createdAt\":\"2026-11-13T00:00:00Z\",\"user_id\":\"u1\",\"visibility\":\"public\",\"author\":{\"id\":\"u1\",\"name\":\"Nguyễn Minh Anh\",\"username\":\"minhanh\",\"avatar\":\"/api/users/u1/avatar\"},\"media\":{\"kind\":\"image\",\"url\":\"/api/posts/post_1/media\"},\"likes\":15,\"comments\":2,\"reactionsCount\":15,\"reactions\":{\"love\":10,\"like\":3,\"haha\":2},\"myReaction\":\"love\"}]}"),
            null, 200);
      }
      if ("POST".equals(method) && cleanPath.matches("/api/posts/[^/]+/reaction")) {
        return new FixtureResult(new JSONObject("{\"success\":true,\"myReaction\":\"love\",\"reactionsCount\":25}"),
            null, 200);
      }
      if ("GET".equals(method) && (cleanPath.matches("/api/posts/[^/]+/comments")
          || cleanPath.matches("/api/posts/[^/]+/comments/comments") || cleanPath.matches("/api/shorts/[^/]+/comments")
          || cleanPath.matches("/api/shorts/[^/]+/comments/comments"))) {
        return new FixtureResult(new JSONObject(
            "{\"comments\":[{\"id\":\"c_1\",\"body\":\"Chào mừng bạn gia nhập!\",\"content\":\"Chào mừng bạn gia nhập!\",\"author\":{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\"},\"created\":"
                + (nowTime - 1800000L)
                + ",\"createdAt\":\"2026-11-13T00:05:00Z\",\"likes\":2,\"myReaction\":null},{\"id\":\"c_2\",\"parentId\":\"c_1\",\"body\":\"Cảm ơn Hoàng Nam nhé!\",\"content\":\"Cảm ơn Hoàng Nam nhé!\",\"author\":{\"id\":\"u1\",\"name\":\"Nguyễn Minh Anh\",\"username\":\"minhanh\"},\"created\":"
                + (nowTime - 900000L)
                + ",\"createdAt\":\"2026-11-13T00:20:00Z\",\"likes\":1,\"myReaction\":\"love\"}]}"),
            null, 200);
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
        return new FixtureResult(new JSONObject("{\"success\":true,\"reactionsCount\":25,\"myReaction\":\"like\"}"),
            null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/posts/[^/]+/reactions")) {
        return new FixtureResult(new JSONObject(
            "{\"users\":[{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\",\"reaction\":\"love\"},{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\",\"reaction\":\"like\"}]}"),
            null, 200);
      }
      if ("POST".equals(method) && (cleanPath.matches("/api/posts/[^/]+/comments")
          || cleanPath.matches("/api/posts/[^/]+/comments/comments") || cleanPath.matches("/api/shorts/[^/]+/comments")
          || cleanPath.matches("/api/shorts/[^/]+/comments/comments"))) {
        return new FixtureResult(new JSONObject(
            "{\"comment\":{\"id\":\"c_new\",\"body\":\"Cảm ơn mọi người!\",\"content\":\"Cảm ơn mọi người!\",\"author\":{\"id\":\"u1\",\"name\":\"Nguyễn Minh Anh\",\"username\":\"minhanh\"},\"created\":"
                + nowTime + ",\"createdAt\":\"2026-11-13T00:10:00Z\"}}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/discover".equals(cleanPath)) {
        if (path.contains("khong_tim_thay")) {
          return new FixtureResult(new JSONObject("{\"users\":[],\"total\":0}"), null, 200);
        }
        if (path.contains("c%C3%A0+ph%C3%AA") || path.contains("c%C3%A0%20ph%C3%AA") || path.contains("cà phê")) {
          return new FixtureResult(new JSONObject(
              "{\"users\":[{\"id\":\"u4\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\",\"avatar\":\"/api/users/u4/avatar\",\"distanceKm\":1.4,\"bio\":\"Cà phê sáng & nhiếp ảnh đường phố\"},{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\",\"avatar\":\"/api/users/u2/avatar\",\"distanceKm\":1.8,\"bio\":\"Nhiếp ảnh & Cà phê sáng\"}]}"),
              null, 200);
        }
        return new FixtureResult(new JSONObject(
            "{\"users\":[{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\",\"avatar\":\"/api/users/u2/avatar\",\"distanceKm\":1.8,\"bio\":\"Nhiếp ảnh & Sáng tạo nội dung\"},{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\",\"avatar\":\"/api/users/u3/avatar\",\"distanceKm\":2.4,\"bio\":\"Yêu âm nhạc & Du lịch\"},{\"id\":\"u4\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\",\"avatar\":\"/api/users/u4/avatar\",\"distanceKm\":3.1,\"bio\":\"Thiết kế & Khám phá\"}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/shorts".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"shorts\":[{\"id\":\"s1\",\"title\":\"Khoảnh khắc cuộc sống\",\"video\":\"/api/shorts/s1/video\",\"author\":{\"id\":\"u1\",\"name\":\"Nguyễn Minh Anh\",\"username\":\"minhanh\"},\"likes\":89,\"comments\":2},{\"id\":\"s2\",\"title\":\"Giai điệu kết nối\",\"video\":\"/api/shorts/s2/video\",\"author\":{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\"},\"likes\":142,\"comments\":2}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/conversations".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"users\":[{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\",\"isActive\":true,\"unread\":1,\"last\":{\"body\":\"Hẹn gặp bạn cuối tuần này nhé!\",\"created\":"
                + (nowTime - 900000L)
                + ",\"mine\":false}}],\"conversations\":[{\"id\":\"c1\",\"title\":\"Trần Thanh Trúc\",\"lastMessage\":\"Hẹn gặp bạn cuối tuần này nhé!\",\"updatedAt\":\"2026-11-13T00:00:00Z\",\"unread\":1}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/groups".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"groups\":[{\"id\":\"g1\",\"name\":\"Nhóm Thiết Kế Kinnect\",\"members\":[{\"id\":\"u1\"},{\"id\":\"u2\"},{\"id\":\"u3\"}],\"unread\":0,\"last\":{\"body\":\"Chào mừng mọi người đến Nhóm Thiết Kế Kinnect!\",\"created\":"
                + (nowTime - 1800000L) + ",\"name\":\"Lê Hoàng Nam\",\"mine\":false}}]}"),
            null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/users/[^/]+/messages")) {
        return new FixtureResult(new JSONObject(
            "{\"messages\":[{\"id\":\"m_1\",\"sender\":\"u3\",\"body\":\"Chào bạn, rất vui được làm quen!\",\"created\":"
                + (nowTime - 3600000L)
                + ",\"createdAt\":\"2026-11-13T00:00:00Z\"},{\"id\":\"m_2\",\"sender\":\"u1\",\"body\":\"Chào Thanh Trúc nhé!\",\"created\":"
                + (nowTime - 3540000L) + ",\"createdAt\":\"2026-11-13T00:01:00Z\"}]}"),
            null, 200);
      }
      if ("GET".equals(method) && cleanPath.matches("/api/groups/[^/]+/messages")) {
        return new FixtureResult(new JSONObject(
            "{\"messages\":[{\"id\":\"gm_1\",\"sender\":\"u2\",\"body\":\"Chào mừng mọi người đến Nhóm Thiết Kế Kinnect!\",\"created\":"
                + (nowTime - 3600000L) + ",\"createdAt\":\"2026-11-13T00:00:00Z\"}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/friends".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"users\":[{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\",\"bio\":\"Nhiếp ảnh & Sáng tạo nội dung\"},{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\",\"bio\":\"Yêu âm nhạc & Du lịch\"}],\"friends\":[{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\"},{\"id\":\"u3\",\"name\":\"Trần Thanh Trúc\",\"username\":\"thanhtruc\"}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/friend-suggestions".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"users\":[{\"id\":\"u4\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\",\"bio\":\"Nhà thiết kế trải nghiệm\"}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/friend-requests".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"requests\":[{\"id\":\"fr_1\",\"user\":{\"id\":\"u4\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\"},\"createdAt\":\"2026-11-13T00:00:00Z\"}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/notifications".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"notifications\":[{\"id\":\"n1\",\"kind\":\"like\",\"created\":"
            + (nowTime - 7200000L)
            + ",\"createdAt\":\"2026-11-13T00:00:00Z\",\"seen\":0,\"actor\":{\"id\":\"u2\",\"name\":\"Lê Hoàng Nam\",\"username\":\"hoangnam\"}}]}"),
            null, 200);
      }
      if ("POST".equals(method) && "/api/notifications".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"success\":true}"), null, 200);
      }
      if ("GET".equals(method) && "/api/store".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"packages\":[{\"id\":\"style_neon\",\"kind\":\"style\",\"slot\":\"style\",\"tier\":\"rare\",\"name\":\"Neon\",\"priceCoins\":300,\"colors\":[\"#7c3aed\",\"#06b6d4\"],\"period\":\"Vĩnh viễn\",\"description\":\"Khung avatar và màu bong bóng hội thoại.\",\"available\":true,\"referenceVnd\":30000},{\"id\":\"style_aurora\",\"kind\":\"style\",\"slot\":\"style\",\"tier\":\"epic\",\"name\":\"Cực quang\",\"priceCoins\":500,\"colors\":[\"#8b5cf6\",\"#ec4899\"],\"period\":\"Vĩnh viễn\",\"description\":\"Khung avatar và màu bong bóng hội thoại.\",\"available\":true,\"referenceVnd\":50000},{\"id\":\"style_galaxy\",\"kind\":\"style\",\"slot\":\"style\",\"tier\":\"legendary\",\"name\":\"Galaxy\",\"priceCoins\":800,\"colors\":[\"#312e81\",\"#a855f7\"],\"period\":\"Vĩnh viễn\",\"description\":\"Khung avatar và màu bong bóng hội thoại.\",\"available\":true,\"referenceVnd\":80000},{\"id\":\"style_ice\",\"kind\":\"style\",\"slot\":\"style\",\"tier\":\"epic\",\"name\":\"Băng hà\",\"priceCoins\":600,\"colors\":[\"#38bdf8\",\"#e0f2fe\"],\"period\":\"Vĩnh viễn\",\"description\":\"Khung avatar và màu bong bóng hội thoại.\",\"available\":true,\"referenceVnd\":60000},{\"id\":\"style_ruby\",\"kind\":\"style\",\"slot\":\"style\",\"tier\":\"epic\",\"name\":\"Hồng ngọc\",\"priceCoins\":650,\"colors\":[\"#be123c\",\"#fb7185\"],\"period\":\"Vĩnh viễn\",\"description\":\"Khung avatar và màu bong bóng hội thoại.\",\"available\":true,\"referenceVnd\":65000},{\"id\":\"style_forest\",\"kind\":\"style\",\"slot\":\"style\",\"tier\":\"rare\",\"name\":\"Rừng thẳm\",\"priceCoins\":350,\"colors\":[\"#047857\",\"#a3e635\"],\"period\":\"Vĩnh viễn\",\"description\":\"Khung avatar và màu bong bóng hội thoại.\",\"available\":true,\"referenceVnd\":35000},{\"id\":\"style_paper\",\"kind\":\"style\",\"slot\":\"style\",\"tier\":\"rare\",\"name\":\"Giấy mỹ thuật\",\"priceCoins\":300,\"colors\":[\"#d6d3d1\",\"#57534e\"],\"period\":\"Vĩnh viễn\",\"description\":\"Khung avatar và màu bong bóng hội thoại.\",\"available\":true,\"referenceVnd\":30000},{\"id\":\"style_ember\",\"kind\":\"style\",\"slot\":\"style\",\"tier\":\"legendary\",\"name\":\"Lửa trại\",\"priceCoins\":900,\"colors\":[\"#f59e0b\",\"#dc2626\"],\"period\":\"Vĩnh viễn\",\"description\":\"Khung avatar và màu bong bóng hội thoại.\",\"available\":true,\"referenceVnd\":90000},{\"id\":\"live_chill\",\"kind\":\"live\",\"slot\":\"live_theme\",\"tier\":\"rare\",\"name\":\"Chill\",\"priceCoins\":500,\"colors\":[\"#0d9488\",\"#38bdf8\"],\"period\":\"Vĩnh viễn\",\"description\":\"Bộ trang trí phòng Live. Không bao gồm quyền phát Live Game.\",\"available\":true,\"referenceVnd\":50000},{\"id\":\"live_gaming\",\"kind\":\"live\",\"slot\":\"live_theme\",\"tier\":\"epic\",\"name\":\"Gaming\",\"priceCoins\":800,\"colors\":[\"#4f46e5\",\"#f43f5e\"],\"period\":\"Vĩnh viễn\",\"description\":\"Bộ trang trí phòng Live. Không bao gồm quyền phát Live Game.\",\"available\":true,\"referenceVnd\":80000},{\"id\":\"live_spotlight\",\"kind\":\"live\",\"slot\":\"live_theme\",\"tier\":\"legendary\",\"name\":\"Spotlight\",\"priceCoins\":1200,\"colors\":[\"#a16207\",\"#fbbf24\"],\"period\":\"Vĩnh viễn\",\"description\":\"Bộ trang trí phòng Live. Không bao gồm quyền phát Live Game.\",\"available\":true,\"referenceVnd\":120000},{\"id\":\"live_game_30\",\"kind\":\"live\",\"slot\":\"live_pass\",\"tier\":\"epic\",\"name\":\"Live Game\",\"priceCoins\":490,\"days\":30,\"period\":\"30 ngày\",\"colors\":[\"#6d28d9\",\"#db2777\"],\"description\":\"Phát màn hình game, bình luận nổi và trả lời bình luận. Live trò chuyện và xem Live luôn miễn phí.\",\"available\":true,\"referenceVnd\":49000},{\"id\":\"gift_love\",\"kind\":\"gifts\",\"slot\":\"inventory\",\"tier\":\"rare\",\"contents\":[[\"rose\",6]],\"name\":\"Yêu thương\",\"priceCoins\":300,\"colors\":[\"#db2777\",\"#fb7185\"],\"period\":\"Bộ quà\",\"description\":\"Bộ quà có sẵn trong kho, tiêu hao khi gửi Live.\",\"available\":true,\"referenceVnd\":30000},{\"id\":\"gift_speed\",\"kind\":\"gifts\",\"slot\":\"inventory\",\"tier\":\"epic\",\"contents\":[[\"car\",1],[\"star\",2]],\"name\":\"Tốc độ\",\"priceCoins\":1000,\"colors\":[\"#2563eb\",\"#06b6d4\"],\"period\":\"Bộ quà\",\"description\":\"Bộ quà có sẵn trong kho, tiêu hao khi gửi Live.\",\"available\":true,\"referenceVnd\":100000},{\"id\":\"gift_royal\",\"kind\":\"gifts\",\"slot\":\"inventory\",\"tier\":\"legendary\",\"contents\":[[\"castle\",1]],\"name\":\"Hoàng gia\",\"priceCoins\":2000,\"colors\":[\"#7e22ce\",\"#eab308\"],\"period\":\"Bộ quà\",\"description\":\"Bộ quà có sẵn trong kho, tiêu hao khi gửi Live.\",\"available\":true,\"referenceVnd\":200000},{\"id\":\"member_plus\",\"kind\":\"member\",\"slot\":\"badge\",\"tier\":\"rare\",\"name\":\"Plus\",\"priceCoins\":490,\"days\":30,\"colors\":[\"#4338ca\",\"#a78bfa\"],\"period\":\"30 ngày\",\"description\":\"Huy hiệu thành viên trên hồ sơ và phòng Live.\",\"available\":true,\"referenceVnd\":49000},{\"id\":\"member_creator\",\"kind\":\"member\",\"slot\":\"badge\",\"tier\":\"legendary\",\"name\":\"Creator\",\"priceCoins\":990,\"days\":30,\"colors\":[\"#c026d3\",\"#fb923c\"],\"period\":\"30 ngày\",\"description\":\"Huy hiệu thành viên trên hồ sơ và phòng Live.\",\"available\":true,\"referenceVnd\":99000},{\"id\":\"studio_video_7\",\"kind\":\"studio\",\"line\":\"video\",\"slot\":\"studio\",\"tier\":\"common\",\"name\":\"Studio Video Pro\",\"priceCoins\":190,\"days\":7,\"period\":\"7 ngày\",\"colors\":[\"#7c3aed\",\"#c026d3\"],\"description\":\"Chỉnh video và mẫu dựng nâng cao trong Studio. Không tự gia hạn hay tự trừ xu.\",\"available\":true,\"referenceVnd\":19000},{\"id\":\"studio_video_30\",\"kind\":\"studio\",\"line\":\"video\",\"slot\":\"studio\",\"tier\":\"rare\",\"name\":\"Studio Video Pro\",\"priceCoins\":490,\"days\":30,\"period\":\"1 tháng\",\"colors\":[\"#7c3aed\",\"#c026d3\"],\"description\":\"Chỉnh video và mẫu dựng nâng cao trong Studio. Không tự gia hạn hay tự trừ xu.\",\"available\":true,\"referenceVnd\":49000},{\"id\":\"studio_video_180\",\"kind\":\"studio\",\"line\":\"video\",\"slot\":\"studio\",\"tier\":\"epic\",\"name\":\"Studio Video Pro\",\"priceCoins\":2190,\"days\":180,\"period\":\"6 tháng\",\"colors\":[\"#7c3aed\",\"#c026d3\"],\"description\":\"Chỉnh video và mẫu dựng nâng cao trong Studio. Không tự gia hạn hay tự trừ xu.\",\"available\":true,\"referenceVnd\":219000},{\"id\":\"studio_video_365\",\"kind\":\"studio\",\"line\":\"video\",\"slot\":\"studio\",\"tier\":\"legendary\",\"name\":\"Studio Video Pro\",\"priceCoins\":3990,\"days\":365,\"period\":\"1 năm\",\"colors\":[\"#7c3aed\",\"#c026d3\"],\"description\":\"Chỉnh video và mẫu dựng nâng cao trong Studio. Không tự gia hạn hay tự trừ xu.\",\"available\":true,\"referenceVnd\":399000},{\"id\":\"studio_photo_7\",\"kind\":\"studio\",\"line\":\"photo\",\"slot\":\"studio\",\"tier\":\"common\",\"name\":\"Studio Ảnh Pro\",\"priceCoins\":190,\"days\":7,\"period\":\"7 ngày\",\"colors\":[\"#db2777\",\"#f97316\"],\"description\":\"Chỉnh ảnh nâng cao trong Studio. Không tự gia hạn hay tự trừ xu.\",\"available\":true,\"referenceVnd\":19000},{\"id\":\"studio_photo_30\",\"kind\":\"studio\",\"line\":\"photo\",\"slot\":\"studio\",\"tier\":\"rare\",\"name\":\"Studio Ảnh Pro\",\"priceCoins\":490,\"days\":30,\"period\":\"1 tháng\",\"colors\":[\"#db2777\",\"#f97316\"],\"description\":\"Chỉnh ảnh nâng cao trong Studio. Không tự gia hạn hay tự trừ xu.\",\"available\":true,\"referenceVnd\":49000},{\"id\":\"studio_photo_180\",\"kind\":\"studio\",\"line\":\"photo\",\"slot\":\"studio\",\"tier\":\"epic\",\"name\":\"Studio Ảnh Pro\",\"priceCoins\":2190,\"days\":180,\"period\":\"6 tháng\",\"colors\":[\"#db2777\",\"#f97316\"],\"description\":\"Chỉnh ảnh nâng cao trong Studio. Không tự gia hạn hay tự trừ xu.\",\"available\":true,\"referenceVnd\":219000},{\"id\":\"studio_photo_365\",\"kind\":\"studio\",\"line\":\"photo\",\"slot\":\"studio\",\"tier\":\"legendary\",\"name\":\"Studio Ảnh Pro\",\"priceCoins\":3990,\"days\":365,\"period\":\"1 năm\",\"colors\":[\"#db2777\",\"#f97316\"],\"description\":\"Chỉnh ảnh nâng cao trong Studio. Không tự gia hạn hay tự trừ xu.\",\"available\":true,\"referenceVnd\":399000}],\"products\":[{\"id\":\"kinnect_style_aurora\",\"kind\":\"style\",\"name\":\"Aurora\",\"description\":\"Khung ảnh tím hồng và màu hội thoại Aurora.\",\"descriptionEn\":\"Purple-pink profile frame and Aurora conversation colors.\",\"colors\":[\"#8b5cf6\",\"#ec4899\"],\"referenceVnd\":29000},{\"id\":\"kinnect_style_ocean\",\"kind\":\"style\",\"name\":\"Ocean\",\"description\":\"Khung ảnh xanh biển và màu hội thoại Ocean.\",\"descriptionEn\":\"Blue profile frame and Ocean conversation colors.\",\"colors\":[\"#0284c7\",\"#14b8a6\"],\"referenceVnd\":29000},{\"id\":\"kinnect_style_sunset\",\"kind\":\"style\",\"name\":\"Sunset\",\"description\":\"Khung ảnh hoàng hôn và màu hội thoại Sunset.\",\"descriptionEn\":\"Sunset profile frame and conversation colors.\",\"colors\":[\"#f97316\",\"#db2777\"],\"referenceVnd\":29000},{\"id\":\"kinnect_studio_pro\",\"kind\":\"studio\",\"name\":\"Studio Pro\",\"description\":\"Ba mẫu dựng video Aurora, Travel, Cinema và trình sửa ảnh nâng cao: lớp ảnh/chữ, mặt nạ, Curves/HSL, lưu nháp và xuất ảnh. Mua một lần, dùng trên tài khoản này.\",\"descriptionEn\":\"Aurora, Travel and Cinema video templates plus advanced photo editing: layers, masks, Curves/HSL, drafts and image export. One-time purchase for this account.\",\"colors\":[\"#7c3aed\",\"#c026d3\"],\"referenceVnd\":149000}],\"trialCoins\":4000,\"purchasedCoins\":8500,\"giftedCoins\":4000,\"coins\":12500,\"balance\":12500,\"trialPackagePurchases\":true,\"studioProFree\":false,\"studioProPermanent\":false,\"ownedPackages\":[\"style_aurora\"],\"owned\":[\"style_aurora\"],\"appearance\":\"style_aurora\",\"liveTheme\":\"\",\"membership\":\"\",\"giftInventory\":[],\"packageExpiries\":{},\"liveGameUntil\":0,\"studioProUntil\":0,\"studioVideoUntil\":0,\"studioPhotoUntil\":0,\"billingReady\":false,\"accountId\":\"u1\"}"),
            null, 200);
      }
      if ("POST".equals(method) && "/api/store/packages/buy".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"success\":true,\"packageId\":\"style_aurora\",\"purchasedCoins\":8500,\"giftedCoins\":3500,\"trialCoins\":3500,\"balance\":12000}"),
            null, 200);
      }
      if ("POST".equals(method) && "/api/store/packages/apply".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"success\":true,\"applied\":\"style_aurora\"}"), null, 200);
      }
      if ("POST".equals(method) && ("/api/store/style".equals(cleanPath) || "/api/profile/theme".equals(cleanPath))) {
        return new FixtureResult(new JSONObject("{\"ok\":true,\"appearance\":\"style_aurora\"}"), null, 200);
      }
      if ("POST".equals(method) && "/api/reports".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"success\":true,\"id\":\"rep_1\"}"), null, 200);
      }
      if ("GET".equals(method)
          && ("/api/commerce/catalog".equals(cleanPath) || "/api/studio/catalog".equals(cleanPath))) {
        return new FixtureResult(new JSONObject(
            "{\"accountId\":\"u1\",\"studioProFree\":true,\"studioProPermanent\":true,\"owned\":[\"kinnect_studio_pro\"]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/music".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"tracks\":[{\"id\":\"m1\",\"title\":\"Giai điệu kết nối\",\"artist\":\"Kinnect Audio\",\"duration\":185,\"url\":\"/music/m1.mp3\"},{\"id\":\"m2\",\"title\":\"Nắng sớm thành phố\",\"artist\":\"Nguyễn Minh Anh feat. Lê Hoàng Nam\",\"duration\":210,\"url\":\"/music/m2.mp3\"},{\"id\":\"m3\",\"title\":\"Khoảnh khắc thanh xuân\",\"artist\":\"Kinnect Vibes\",\"duration\":195,\"url\":\"/music/m3.mp3\"},{\"id\":\"m4\",\"title\":\"Nhịp đập cuộc sống\",\"artist\":\"Trần Thanh Trúc\",\"duration\":240,\"url\":\"/music/m4.mp3\"}]}"),
            null, 200);
      }
      if ("GET".equals(method) && ("/api/live".equals(cleanPath) || "/api/live/rooms".equals(cleanPath))) {
        if (fixtureEmptyLive) {
          return new FixtureResult(new JSONObject("{\"rooms\":[]}"), null, 200);
        }
        return new FixtureResult(new JSONObject(
            "{\"rooms\":[{\"id\":\"room_1\",\"title\":\"Giao lưu âm nhạc cuối tuần\",\"host\":\"Lê Hoàng Nam\",\"liveMode\":\"chat\",\"hostId\":\"u2\",\"viewers\":64},{\"id\":\"room_2\",\"title\":\"Trò chuyện nghệ thuật & thiết kế\",\"host\":\"Trần Thanh Trúc\",\"liveMode\":\"chat\",\"hostId\":\"u3\",\"viewers\":42}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/live/gifts".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"enabled\":true,\"free\":false,\"experience\":true,\"version\":1,\"vndPerCoin\":100,\"signupBonusCoins\":2000,\"unlimitedCoins\":false,\"balance\":4000,\"quantities\":[1,5,10,99],\"inventory\":[],\"items\":[{\"id\":\"rose\",\"name\":\"Hoa hồng\",\"legacy\":\"rose\",\"tier\":\"small\",\"comboable\":true,\"costCoins\":50},{\"id\":\"heart\",\"name\":\"Trái tim\",\"legacy\":\"heart\",\"tier\":\"small\",\"comboable\":true,\"costCoins\":50},{\"id\":\"coffee\",\"name\":\"Cà phê\",\"legacy\":\"star\",\"tier\":\"small\",\"comboable\":true,\"costCoins\":100},{\"id\":\"love_gun\",\"name\":\"Súng tình yêu\",\"legacy\":\"star\",\"tier\":\"medium\",\"comboable\":true,\"costCoins\":150},{\"id\":\"fireworks\",\"name\":\"Pháo hoa\",\"legacy\":\"star\",\"tier\":\"medium\",\"comboable\":true,\"costCoins\":200},{\"id\":\"star\",\"name\":\"Sao pha lê\",\"legacy\":\"star\",\"tier\":\"small\",\"comboable\":true,\"costCoins\":100},{\"id\":\"crown\",\"name\":\"Vương miện\",\"legacy\":\"crown\",\"tier\":\"medium\",\"comboable\":true,\"costCoins\":200},{\"id\":\"diamond\",\"name\":\"Kim cương\",\"legacy\":\"crown\",\"tier\":\"medium\",\"comboable\":true,\"costCoins\":500},{\"id\":\"car\",\"name\":\"Siêu xe\",\"legacy\":\"crown\",\"tier\":\"large\",\"comboable\":true,\"costCoins\":800},{\"id\":\"sports_car\",\"name\":\"Siêu xe thể thao\",\"legacy\":\"crown\",\"tier\":\"large\",\"comboable\":true,\"costCoins\":1000},{\"id\":\"yacht\",\"name\":\"Du thuyền\",\"legacy\":\"crown\",\"tier\":\"large\",\"comboable\":false,\"costCoins\":1200},{\"id\":\"castle\",\"name\":\"Lâu đài\",\"legacy\":\"crown\",\"tier\":\"legendary\",\"comboable\":false,\"costCoins\":2000},{\"id\":\"aurora\",\"name\":\"Cực quang\",\"legacy\":\"star\",\"tier\":\"medium\",\"comboable\":true,\"costCoins\":300},{\"id\":\"meteor\",\"name\":\"Sao băng\",\"legacy\":\"star\",\"tier\":\"medium\",\"comboable\":true,\"costCoins\":400},{\"id\":\"butterfly\",\"name\":\"Bướm mộng\",\"legacy\":\"star\",\"tier\":\"small\",\"comboable\":true,\"costCoins\":150},{\"id\":\"lotus\",\"name\":\"Sen ánh sáng\",\"legacy\":\"rose\",\"tier\":\"medium\",\"comboable\":true,\"costCoins\":250}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/wallet".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"balance\":12500,\"coins\":12500,\"purchasedCoins\":8500,\"giftedCoins\":4000,\"trialCoins\":4000,\"withdrawableVnd\":0,\"earningsVnd\":0,\"giftedGiftValueCoins\":0,\"vndPerCoin\":100,\"coinPacks\":[{\"id\":\"coins_100\",\"coins\":100,\"referenceVnd\":10000},{\"id\":\"coins_500\",\"coins\":500,\"referenceVnd\":50000},{\"id\":\"coins_1000\",\"coins\":1000,\"referenceVnd\":100000},{\"id\":\"coins_2000\",\"coins\":2000,\"referenceVnd\":200000},{\"id\":\"coins_5000\",\"coins\":5000,\"referenceVnd\":500000},{\"id\":\"coins_10000\",\"coins\":10000,\"referenceVnd\":1000000}],\"entries\":[{\"id\":\"w_1\",\"kind\":\"coin_purchase\",\"category\":\"topup\",\"title\":\"Nạp xu\",\"subtitle\":\"Xu mua\",\"coins\":8500,\"created\":1762941600000},{\"id\":\"w_2\",\"kind\":\"signup_trial\",\"category\":\"grant\",\"title\":\"Xu chào mừng\",\"subtitle\":\"Xu tặng\",\"coins\":4000,\"created\":1762941600000}]}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/call-config".equals(cleanPath)) {
        return new FixtureResult(
            new JSONObject(
                "{\"iceServers\":[{\"urls\":\"stun:stun.l.google.com:19302\"}],\"token\":\"mock_rtc_token\"}"),
            null, 200);
      }
      if ("GET".equals(method) && "/api/support".equals(cleanPath)) {
        return new FixtureResult(
            new JSONObject("{\"user\":{\"id\":\"usr_support\",\"name\":\"Kinnect Support\",\"username\":\"support\"}}"),
            null, 200);
      }
      if ("GET".equals(method) && cleanPath.endsWith("/private")) {
        return new FixtureResult(
            new JSONObject("{\"status\":\"owner\",\"photos\":[{\"id\":\"p_1\",\"url\":\"/private_1.jpg\"}]}"), null,
            200);
      }
      if ("GET".equals(method) && "/api/me/private/requests".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"requests\":[]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/me/account-deletion".equals(cleanPath)) {
        return new FixtureResult(new JSONObject(
            "{\"requiresPassword\":true,\"username\":\"minhanh\",\"permanent\":true,\"oauthProviders\":[],\"twoFactorEnabled\":false}"),
            null, 200);
      }
      if ("DELETE".equals(method) && "/api/me/account-deletion".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"ok\":true,\"deleted\":true}"), null, 200);
      }
      JSONObject notFound = new JSONObject();
      try {
        notFound.put("error", "Fixture endpoint not mapped: " + method + " " + cleanPath);
      } catch (Exception ignored) {
      }
      return new FixtureResult(notFound, I18n.t("Không thể tải dữ liệu lúc này."), 404);
    } catch (Exception e) {
      JSONObject err = new JSONObject();
      try {
        err.put("error", "Fixture error: " + e.getMessage());
      } catch (Exception ignored) {
      }
      return new FixtureResult(err, e.getMessage(), 500);
    }
  }

  public interface Progress {
    void sent(long bytes, long total);
  }

  public void call(String method, String path, JSONObject data, Result callback) {
    call(method, path, data, null, callback, null);
  }

  public void call(
      String method,
      String path,
      JSONObject data,
      Progress progress,
      Result callback) {
    call(method, path, data, progress, callback, null);
  }

  public void call(
      String method,
      String path,
      JSONObject data,
      Progress progress,
      Result callback,
      Runnable onDropped) {
    apiDispatchCount++;
    if (appContext != null
        && (appContext.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
      android.util.Log.i("KinnectQA", "API_TRANSPORT_ATTEMPT: method=" + method + " path=" + path + " counter="
          + apiDispatchCount + " fixture=" + fixtureEnabled);
    }
    if (fixtureEnabled) {
      FixtureResult fr = offlineFixture(method, path, data);
      main.post(() -> callback.done(fr.data, fr.error, fr.status));
      return;
    }
    final String primaryServer = origin,
        primarySession = cookie;
    final int primaryRevision = epoch;
    final String snapshotKey = primaryRevision + ":" + primaryServer + path;
    final Snapshot snapshot = method.equals("GET") ? snapshots.get(snapshotKey) : null;
    if (method.equals("GET") && appContext != null) {
      android.net.ConnectivityManager cm = (android.net.ConnectivityManager) appContext
          .getSystemService(android.content.Context.CONNECTIVITY_SERVICE);
      if (cm != null && cm.getActiveNetwork() == null) {
        JSONObject saved = cachedGet(path);
        if (saved != null) {
          main.post(() -> {
            if (primaryRevision == epoch && primaryServer.equals(origin))
              callback.done(saved, null, 200);
            else if (onDropped != null)
              onDropped.run();
          });
          return;
        }
      }
    }
    activeRequests.incrementAndGet();
    executor.execute(() -> {
      String server = primaryServer, session = primarySession;
      int revision = primaryRevision;
      boolean failedOver = false;
      JSONObject result = null;
      String error = null;
      int status = 0;
      int deliveryRevision = revision;
      Exception failure = null;
      for (;;) {
        result = null;
        error = null;
        status = 0;
        failure = null;
        deliveryRevision = revision;
        HttpURLConnection connection = null;
        try {
          if (!path.startsWith("/api/") || path.contains(".."))
            throw new IOException(I18n.t("API không hợp lệ."));
          if (debugLoopbackOrigin != null) {
            android.util.Log.i("KinnectQA", "DEBUG_LOOPBACK_OPEN: server=" + server + " path=" + path + " match="
                + server.equals(debugLoopbackOrigin));
          }
          connection = (HttpURLConnection) new URL(
              server + path).openConnection();
          if (connection instanceof javax.net.ssl.HttpsURLConnection && debugLoopbackSslFactory != null
              && server.equals(debugLoopbackOrigin)) {
            javax.net.ssl.HttpsURLConnection httpsConn = (javax.net.ssl.HttpsURLConnection) connection;
            httpsConn.setSSLSocketFactory(debugLoopbackSslFactory);
            httpsConn.setHostnameVerifier(
                (hostname, sslSession) -> "10.0.2.2".equals(hostname) || "127.0.0.1".equals(hostname));
          }
          connection.setInstanceFollowRedirects(false);
          connection.setConnectTimeout(8000);
          boolean shortPost = "/api/push/decline".equals(path) || "/api/push/unregister".equals(path)
              || "/api/logout".equals(path) || "/api/devices/push".equals(path);
          connection.setReadTimeout(shortPost ? 6000 : method.equals("GET") ? 12000 : 600000);
          connection.setRequestMethod(method);
          connection.setRequestProperty("Accept", "application/json");
          if (snapshot != null)
            connection.setRequestProperty("If-None-Match", snapshot.etag);
          connection.setRequestProperty("Origin", server);
          String jar = join(session, device);
          if (!jar.isEmpty())
            connection.setRequestProperty("Cookie", jar);
          if (data != null) {
            connection.setDoOutput(true);
            connection.setRequestProperty(
                "Content-Type",
                "application/json; charset=utf-8");
            byte[] payload = data.toString().getBytes("UTF-8");
            connection.setFixedLengthStreamingMode(payload.length);
            try (OutputStream out = connection.getOutputStream()) {
              long last = 0;
              for (int offset = 0; offset < payload.length;) {
                int count = Math.min(65536, payload.length - offset);
                out.write(payload, offset, count);
                offset += count;
                long now = System.currentTimeMillis();
                if (progress != null && (now - last >= 100 || offset == payload.length)) {
                  final int sent = offset;
                  main.post(() -> progress.sent(sent, payload.length));
                  last = now;
                }
              }
              out.flush();
            }
          }
          status = connection.getResponseCode();
          java.util.List<String> setCookies = connection.getHeaderFields().get("Set-Cookie");
          boolean sessionChanged = false;
          synchronized (this) {
            for (int i = 0; setCookies != null && i < setCookies.size(); i++) {
              String responseCookie = setCookies.get(i);
              if (responseCookie == null || !server.equals(origin) || revision != epoch)
                continue;
              if (responseCookie.startsWith("kinnect_session=")) {
                String next = responseCookie.split(";", 2)[0];
                if (next.equals("kinnect_session="))
                  next = "";
                sessionChanged |= !cookie.equals(next);
                cookie = next;
                if (!next.isEmpty())
                  originSwitchAuthRequired = false;
                if (sessions != null && !ServerConfig.FALLBACK_ORIGIN.equals(origin))
                  sessions.save(origin, persistSession ? cookie : "");
              }
              if (responseCookie.startsWith("kinnect_device=")) {
                String nextDevice = responseCookie.split(";", 2)[0];
                if (nextDevice.equals("kinnect_device="))
                  nextDevice = "";
                device = nextDevice;
                if (sessions != null && !ServerConfig.FALLBACK_ORIGIN.equals(origin))
                  sessions.saveDevice(origin, device);
              }
            }
          }
          synchronized (this) {
            if (sessionChanged && server.equals(origin) && revision == epoch) {
              epoch++;
              deliveryRevision = epoch;
            }
          }
          boolean unchanged = status == 304 && snapshot != null;
          if (unchanged)
            status = 200;
          InputStream input = status >= 200 && status < 300
              ? connection.getInputStream()
              : connection.getErrorStream();
          String response = unchanged ? snapshot.body
              : input == null ? "{}" : new String(read(input, 2000000), "UTF-8");
          try {
            result = new JSONObject(response);
          } catch (org.json.JSONException invalid) {
            if (status >= 200 && status < 300)
              throw new IOException(I18n.t("Máy chủ trả về dữ liệu không hợp lệ."));
            result = new JSONObject();
          }
          if (method.equals("GET") && status == 200 && response.length() < 262144
              && connection.getHeaderField("ETag") != null && revision == epoch)
            snapshots.put(snapshotKey, new Snapshot(connection.getHeaderField("ETag"), response));
          boolean originSwitch401 = status == 401
              && (originSwitchAuthRequired || (ServerConfig.FALLBACK_ORIGIN.equals(server) && session.isEmpty()));
          boolean fallbackForbidden = status == 403 && ServerConfig.FALLBACK_ORIGIN.equals(server);
          if (status < 200 || status >= 300)
            error = originSwitch401
                ? I18n.t(ServerConfig.FALLBACK_ORIGIN.equals(server)
                    ? "Đang dùng máy chủ dự phòng. Vui lòng đăng nhập lại trên máy chủ này."
                    : "Phiên đăng nhập chưa có trên máy chủ này. Vui lòng đăng nhập lại.")
                : (status >= 500 ? httpFailure(status) : result.optString("error", httpFailure(status)));
          if (method.equals("GET") && status == 200 && !session.isEmpty() && cacheable(path) && revision == epoch) {
            String scopeKey = server + "\n" + session;
            memoryJsonCache.put(scopeKey + "\njson:" + path, response);
            if (diskCache != null)
              diskCache.put(scopeKey, "json:" + path, response.getBytes("UTF-8"));
          }
          if (method.equals("GET") && status == 401 && diskCache != null && !originSwitch401) {
            memoryJsonCache.clear();
            diskCache.clear();
          }
          if (!method.equals("GET") && status >= 200 && status < 300) {
            invalidateForMutation(path);
          }
        } catch (OutOfMemoryError oom) {
          error = I18n.t("Thiết bị không đủ bộ nhớ để chuẩn bị tệp tải lên.");
        } catch (java.net.SocketTimeoutException timeout) {
          if (debugLoopbackOrigin != null && server.equals(debugLoopbackOrigin)) {
            android.util.Log.w("KinnectQA",
                "DEBUG_LOOPBACK_TIMEOUT: " + method + " " + path + " -> " + timeout.getMessage());
          }
          failure = timeout;
          error = I18n.t(progress != null ? "Kết nối tải lên hết thời gian chờ. Kiểm tra mạng rồi thử lại."
              : "Kết nối chậm, vui lòng thử lại.");
        } catch (Exception caught) {
          if (debugLoopbackOrigin != null && server.equals(debugLoopbackOrigin)) {
            android.util.Log.w("KinnectQA", "DEBUG_LOOPBACK_EXC: " + method + " " + path + " -> "
                + caught.getClass().getName() + ": " + caught.getMessage());
          }
          failure = caught;
          error = status >= 200 && status < 300 ? I18n.t("Máy chủ trả về dữ liệu không hợp lệ.")
              : status > 0 ? httpFailure(status) : I18n.t("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.");
        } finally {
          if (connection != null)
            connection.disconnect();
        }
        if (error != null && !failedOver && shouldFailover(method, status, failure) && failoverFrom(server)) {
          failedOver = true;
          server = origin;
          session = cookie;
          revision = epoch;
          continue;
        }
        break;
      }
      boolean fallbackNoSession401 = status == 401 && ServerConfig.FALLBACK_ORIGIN.equals(server)
          && (session == null || session.isEmpty());
      if (error != null && (status == 0 || status >= 500 || fallbackNoSession401) && method.equals("GET")
          && server.equals(origin) && revision == epoch) {
        JSONObject cached = cachedGet(path);
        if (cached == null && fallbackNoSession401 && sessions != null && diskCache != null) {
          String primaryCookie = sessions.load(ServerConfig.DEFAULT_ORIGIN);
          if (!primaryCookie.isEmpty() && cacheable(path)) {
            String pScope = ServerConfig.DEFAULT_ORIGIN + "\n" + primaryCookie;
            String mem = memoryJsonCache.get(pScope + "\njson:" + path);
            if (mem != null) {
              try {
                cached = new JSONObject(mem);
                cached.put("cached", true);
              } catch (Exception ignored) {
              }
            }
            if (cached == null) {
              byte[] raw = diskCache.get(pScope, "json:" + path, AppCache.WEEK);
              if (raw != null) {
                try {
                  cached = new JSONObject(new String(raw, "UTF-8"));
                  cached.put("cached", true);
                } catch (Exception ignored) {
                }
              }
            }
          }
        }
        if (cached != null) {
          result = cached;
          error = null;
          status = 200;
        }
      }
      final JSONObject answer = result;
      final String message = error;
      final int code = status;
      final int acceptedRevision = deliveryRevision;
      final String deliveredServer = server;
      final boolean alwaysDeliver = "/api/push/decline".equals(path) || "/api/push/unregister".equals(path)
          || "/api/devices/push".equals(path) || "/api/logout".equals(path);
      main.post(() -> {
        try {
          if (alwaysDeliver || (epoch == acceptedRevision && deliveredServer.equals(origin)))
            callback.done(answer, message, code);
          else if (onDropped != null)
            onDropped.run();
          else if (progress != null || !method.equals("GET"))
            callback.done(null, I18n.t("Phiên đã thay đổi, vui lòng thử lại."), 0);
        } finally {
          if (activeRequests.decrementAndGet() == 0)
            maybeProbePrimary();
        }
      });
    });
  }

  /**
   * Chỉ chuyển sang máy chủ dự phòng khi lỗi mạng/tunnel — không phát lại yêu cầu
   * đã tới máy chủ.
   */
  private boolean shouldFailover(String method, int status, Exception failure) {
    if (!origin.equals(ServerConfig.DEFAULT_ORIGIN))
      return false;
    boolean tunnel = status >= 520 && status <= 530;
    boolean preOriginTunnel = status == 521 || status == 522 || status == 523 || status == 530;
    boolean connect = status == 0 && (failure instanceof java.net.ConnectException
        || failure instanceof java.net.UnknownHostException || failure instanceof java.net.NoRouteToHostException);
    if (method.equals("GET") || method.equals("HEAD"))
      return status == 0 || tunnel || status == 502 || status == 504;
    return connect || preOriginTunnel;
  }

  private synchronized boolean failoverFrom(String failed) {
    if (!failed.equals(origin) || !ServerConfig.DEFAULT_ORIGIN.equals(origin))
      return false;
    String next = ServerConfig.FALLBACK_ORIGIN;
    if (next.isEmpty() || next.equals(failed))
      return false;
    if (appContext != null) {
      android.net.ConnectivityManager cm = (android.net.ConnectivityManager) appContext
          .getSystemService(android.content.Context.CONNECTIVITY_SERVICE);
      if (cm != null && cm.getActiveNetwork() == null)
        return false;
    }
    origin = next;
    epoch++;
    snapshots.clear();
    // Do not transfer or reuse primary session/device cookies across origins.
    cookie = "";
    device = "";
    originSwitchAuthRequired = true;
    return true;
  }

  /**
   * Khi đang ở máy chủ dự phòng: thăm dò PC mỗi phút, tự quay lại khi PC hoạt
   * động trở lại.
   */
  private volatile long lastPrimaryProbe = 0;
  private final java.util.concurrent.atomic.AtomicInteger activeRequests = new java.util.concurrent.atomic.AtomicInteger(
      0);

  private void maybeProbePrimary() {
    if (fixtureEnabled || !origin.equals(ServerConfig.FALLBACK_ORIGIN))
      return;
    if (activeRequests.get() > 0)
      return;
    long now = System.currentTimeMillis();
    synchronized (this) {
      if (!origin.equals(ServerConfig.FALLBACK_ORIGIN) || now - lastPrimaryProbe < 60000)
        return;
      lastPrimaryProbe = now;
    }
    mediaCacheExecutor.execute(() -> {
      HttpURLConnection c = null;
      try {
        c = (HttpURLConnection) new URL(ServerConfig.DEFAULT_ORIGIN + "/health").openConnection();
        c.setConnectTimeout(3000);
        c.setReadTimeout(3000);
        c.setInstanceFollowRedirects(false);
        int probeCode = c.getResponseCode();
        if (probeCode >= 200 && probeCode < 300)
          switchBackToPrimary();
      } catch (Exception ignored) {
      } finally {
        if (c != null)
          c.disconnect();
      }
    });
  }

  private synchronized void switchBackToPrimary() {
    if (!origin.equals(ServerConfig.FALLBACK_ORIGIN))
      return;
    origin = ServerConfig.DEFAULT_ORIGIN;
    epoch++;
    snapshots.clear();
    cookie = sessions == null ? "" : sessions.load(origin);
    device = sessions == null ? "" : sessions.loadDevice(origin);
    originSwitchAuthRequired = cookie.isEmpty();
  }

  private static String httpFailure(int status) {
    if (status == 408 || status == 504)
      return I18n.t("Kết nối chậm, vui lòng thử lại.");
    if (status >= 500)
      return I18n.t("Máy chủ đang tạm gián đoạn. Vui lòng thử lại sau.");
    if (status == 413)
      return I18n.t("Máy chủ hoặc đường truyền từ chối kích thước tải lên (HTTP 413).");
    if (status == 401)
      return I18n.t("Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.");
    if (status == 429)
      return I18n.t("Máy chủ đang bận hoặc cần chờ trước lần đăng tiếp theo (HTTP 429).");
    return I18n.t("Máy chủ chưa nhận được yêu cầu (HTTP ") + status + ").";
  }

  public interface DownloadCallback {
    void done(boolean ok);
  }

  private static boolean allowedMediaPath(String path) {
    return path != null && !path.contains("..") && (path.startsWith("/api/users/") || path.startsWith("/api/posts/")
        || path.startsWith("/api/chat-attachments/") || path.startsWith("/api/private-photos/")
        || path.startsWith("/api/shorts/") || path.startsWith("/music/"));
  }

  /** Stream large authenticated media directly to an OutputStream (up to 100 MB). */
  public void downloadToStream(String path, java.util.concurrent.Callable<OutputStream> opener,
      DownloadCallback callback) {
    final String server = origin, session = cookie, dev = device;
    final int revision = epoch;
    executor.execute(() -> {
      boolean ok = false;
      HttpURLConnection c = null;
      try {
        if (!allowedMediaPath(path) || opener == null)
          throw new IOException();
        c = (HttpURLConnection) new URL(server + path).openConnection();
        if (c instanceof javax.net.ssl.HttpsURLConnection && debugLoopbackSslFactory != null
            && server.equals(debugLoopbackOrigin)) {
          javax.net.ssl.HttpsURLConnection httpsConn = (javax.net.ssl.HttpsURLConnection) c;
          httpsConn.setSSLSocketFactory(debugLoopbackSslFactory);
          httpsConn.setHostnameVerifier(
              (hostname, sslSession) -> "10.0.2.2".equals(hostname) || "127.0.0.1".equals(hostname));
        }
        c.setUseCaches(false);
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(15000);
        c.setReadTimeout(60000);
        c.setRequestProperty("Cookie", join(session, dev));
        if (c.getResponseCode() == 200) {
          try (InputStream in = c.getInputStream(); OutputStream out = opener.call()) {
            if (out != null) {
              byte[] buffer = new byte[65536];
              long total = 0;
              long maxBytes = 100L * 1024 * 1024;
              int count;
              while ((count = in.read(buffer)) != -1) {
                total += count;
                if (total > maxBytes)
                  throw new IOException(I18n.t("Dữ liệu quá lớn."));
                out.write(buffer, 0, count);
              }
              out.flush();
              ok = true;
            }
          }
        }
      } catch (Exception | OutOfMemoryError ignored) {
        ok = false;
      } finally {
        if (c != null)
          c.disconnect();
      }
      final boolean success = ok;
      main.post(() -> {
        if (callback != null)
          callback.done(success && epoch == revision && origin.equals(server));
      });
    });
  }

  private byte[] fixtureImageBytes(String path) {
    if (!fixtureEnabled || appContext == null || path == null || path.isEmpty())
      return null;
    boolean isDebug = (appContext.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (!isDebug)
      return null;
    String assetName;
    if (path.contains("private_1") || path.contains("/u1/"))
      assetName = "welcome-profile.png";
    else if (path.contains("story") || path.contains("/u4/") || path.contains("linhnhi"))
      assetName = "welcome-profile-2.png";
    else if (path.contains("/u2/") || path.contains("hoangnam") || path.contains("post_1"))
      assetName = "welcome-profile-1.png";
    else if (path.contains("/u3/") || path.contains("thanhtruc"))
      assetName = "welcome-profile-3.png";
    else {
      String[] pool = { "welcome-profile.png", "welcome-profile-1.png", "welcome-profile-2.png",
          "welcome-profile-3.png" };
      assetName = pool[Math.abs(path.hashCode()) % pool.length];
    }
    try (InputStream in = appContext.getAssets().open(assetName)) {
      return readAll(in);
    } catch (Exception ignored) {
      return null;
    }
  }

  public void image(String path, Bytes callback) {
    final String server = origin,
        session = cookie;
    final int revision = epoch;
    final String scope = cacheScope();
    executor.execute(() -> {
      if (fixtureEnabled) {
        final byte[] fixtureBytes = fixtureImageBytes(path);
        main.post(() -> {
          if (epoch == revision && origin.equals(server))
            callback.done(fixtureBytes);
        });
        return;
      }
      byte[] bytes = null;
      HttpURLConnection c = null;
      try {
        if (!allowedMediaPath(path))
          throw new IOException();
        boolean largeMedia = path.startsWith("/api/shorts/") || path.startsWith("/api/chat-attachments/")
            || path.startsWith("/music/");
        c = (HttpURLConnection) new URL(server + path).openConnection();
        if (c instanceof javax.net.ssl.HttpsURLConnection && debugLoopbackSslFactory != null
            && server.equals(debugLoopbackOrigin)) {
          javax.net.ssl.HttpsURLConnection httpsConn = (javax.net.ssl.HttpsURLConnection) c;
          httpsConn.setSSLSocketFactory(debugLoopbackSslFactory);
          httpsConn.setHostnameVerifier(
              (hostname, sslSession) -> "10.0.2.2".equals(hostname) || "127.0.0.1".equals(hostname));
        }
        c.setUseCaches(false);
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(15000);
        c.setReadTimeout(largeMedia ? 60000 : 30000);
        c.setRequestProperty("Cookie", join(session, device));
        if (path.contains("/avatar"))
          c.setRequestProperty("Cache-Control", "no-cache");
        int status = c.getResponseCode();
        if (status == 200) {
          int cap = path.endsWith("/avatar") ? 1100000 : 64 * 1024 * 1024;
          bytes = read(c.getInputStream(), cap);
          if (diskCache != null && String.valueOf(c.getContentType()).startsWith("image/")
              && !path.startsWith("/api/private-photos/") && revision == epoch)
            diskCache.put(scope, "image:" + path, bytes);
        } else if (status >= 500 && diskCache != null)
          bytes = diskCache.get(scope, "image:" + path, AppCache.WEEK);
      } catch (Exception | OutOfMemoryError ignored) {
        if (diskCache != null && revision == epoch)
          bytes = diskCache.get(scope, "image:" + path, AppCache.WEEK);
      } finally {
        if (c != null)
          c.disconnect();
      }
      final byte[] result = bytes;
      main.post(() -> {
        if (epoch == revision && origin.equals(server))
          callback.done(result);
      });
    });
  }

  /** Ảnh từ trang tin tức (chỉ HTTPS, tối đa 3 MB, không gửi cookie). */
  public void remote(String url, Bytes callback) {
    executor.execute(() -> {
      byte[] bytes = null;
      HttpURLConnection c = null;
      try {
        if (!url.startsWith("https://"))
          throw new IOException();
        c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(10000);
        if (c.getResponseCode() == 200)
          bytes = read(c.getInputStream(), 3000000);
      } catch (Exception ignored) {
      } finally {
        if (c != null)
          c.disconnect();
      }
      final byte[] result = bytes;
      main.post(() -> callback.done(result));
    });
  }

  /** Read a selected media file without a fixed app-level size limit. */
  public static byte[] readAll(InputStream input) throws IOException {
    try (InputStream in = input; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
      byte[] buffer = new byte[65536];
      int count;
      while ((count = in.read(buffer)) != -1)
        out.write(buffer, 0, count);
      return out.toByteArray();
    }
  }

  public static byte[] read(InputStream input, int maximum) throws IOException {
    try (
        InputStream in = input;
        ByteArrayOutputStream out = new ByteArrayOutputStream()) {
      byte[] buffer = new byte[8192];
      int count;
      while ((count = in.read(buffer)) != -1) {
        if (out.size() + count > maximum)
          throw new IOException(
              I18n.t("Dữ liệu quá lớn."));
        out.write(buffer, 0, count);
      }
      return out.toByteArray();
    }
  }
}
