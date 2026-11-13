package app.kinnect.live;

import android.os.Handler;
import android.os.Looper;
import java.io.*;
import java.net.*;
import java.util.concurrent.*;
import org.json.JSONObject;

/** HTTPS API client. Session cookie stays in process memory, never in source/logs. */
public final class NativeApi {

  public static final NativeApi shared = new NativeApi();
  private final ExecutorService executor = Executors.newFixedThreadPool(3);
  private final Handler main = new Handler(Looper.getMainLooper());
  private static final class Snapshot{final String etag,body;Snapshot(String e,String b){etag=e;body=b;}}
  private final java.util.Map<String,Snapshot> snapshots=java.util.Collections.synchronizedMap(new java.util.LinkedHashMap<String,Snapshot>(){protected boolean removeEldestEntry(java.util.Map.Entry<String,Snapshot> e){return size()>32;}});
  private volatile int epoch = 0;
  public volatile int apiDispatchCount = 0;
  private SessionStore sessions;
  private AppCache diskCache;private android.content.Context appContext;
  private final ExecutorService mediaCacheExecutor=Executors.newSingleThreadExecutor();
  private final java.util.Set<String> warming=java.util.Collections.synchronizedSet(new java.util.HashSet<>());
  public synchronized void initialize(android.content.Context context,String server){appContext=context.getApplicationContext();sessions=new SessionStore(context);diskCache=new AppCache(new File(appContext.getCacheDir(),"kinnect-v2"),new AppCache.Codec(){public byte[] encode(String key,byte[] data)throws Exception{return sessions.sealCache(key,data);}public byte[] decode(String key,byte[] data)throws Exception{return sessions.openCache(key,data);}},128L*1024*1024);configure(server);cookie=sessions.load(origin);device=sessions.loadDevice(origin);if(cookie.isEmpty()&&origin.equals(ServerConfig.DEFAULT_ORIGIN)){String previous=sessions.load("https://app.kinnect.io.vn");if(!previous.isEmpty()){cookie=previous;sessions.save(origin,cookie);}}if(cookie.isEmpty()){String migrated=sessions.migrate(origin);if(!migrated.isEmpty())cookie=migrated;}}
  private String cacheScope(){return origin+"\n"+cookie;}
  private boolean cacheable(String path){String p=path.split("\\?",2)[0];return java.util.Arrays.asList("/api/me","/api/posts","/api/discover","/api/shorts","/api/conversations","/api/groups","/api/notifications","/api/friends","/api/friend-requests","/api/friend-suggestions").contains(p)||p.matches("/api/users/[^/]+(?:/messages)?")||p.matches("/api/groups/[^/]+(?:/messages)?");}
  public JSONObject cachedGet(String path){if(diskCache==null||cookie.isEmpty()||!cacheable(path))return null;byte[] bytes=diskCache.get(cacheScope(),"json:"+path,AppCache.WEEK);try{if(bytes==null)return null;JSONObject value=new JSONObject(new String(bytes,"UTF-8"));value.put("cached",true);return value;}catch(Exception e){return null;}}
  public byte[] cachedImage(String path){return diskCache==null||cookie.isEmpty()?null:diskCache.get(cacheScope(),"image:"+path,AppCache.WEEK);}
  public File cachedVideo(String path){
    if(fixtureEnabled&&appContext!=null){
      File fixtureFile=new File(appContext.getCacheDir(),"fixture_short.mp4");
      if(!fixtureFile.exists()||fixtureFile.length()==0){
        try(java.io.InputStream in=appContext.getAssets().open("short_sample.mp4");java.io.FileOutputStream out=new java.io.FileOutputStream(fixtureFile)){
          byte[] buf=new byte[8192];int r;while((r=in.read(buf))!=-1)out.write(buf,0,r);
        }catch(Exception ignored){}
      }
      if(fixtureFile.exists()&&fixtureFile.length()>0)return fixtureFile;
    }
    return diskCache==null||cookie.isEmpty()?null:diskCache.video(cacheScope(),path);
  }
  public byte[] cachedThumbnail(String path){
    if(fixtureEnabled&&appContext!=null){
      File fixtureFile=cachedVideo(path);
      if(fixtureFile!=null&&fixtureFile.exists()){
        android.media.MediaMetadataRetriever retriever=new android.media.MediaMetadataRetriever();
        try{
          retriever.setDataSource(fixtureFile.getAbsolutePath());
          android.graphics.Bitmap frame=android.os.Build.VERSION.SDK_INT>=27?retriever.getScaledFrameAtTime(0,android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,360,640):null;
          if(frame!=null){
            ByteArrayOutputStream out=new ByteArrayOutputStream();
            frame.compress(android.graphics.Bitmap.CompressFormat.JPEG,85,out);
            frame.recycle();
            return out.toByteArray();
          }
        }catch(Exception ignored){}finally{try{retriever.release();}catch(Exception ignored){}}
      }
    }
    return diskCache==null||cookie.isEmpty()?null:diskCache.get(cacheScope(),"thumb:"+path,AppCache.WEEK);
  }
  public void cacheThumbnail(String path,byte[] bytes){if(diskCache!=null&&!cookie.isEmpty())diskCache.put(cacheScope(),"thumb:"+path,bytes);}
  public void warmVideo(String path){
    if(fixtureEnabled||diskCache==null||cookie.isEmpty()||!path.matches("/api/shorts/[^/]+/video")||cachedVideo(path)!=null)return;
    android.net.ConnectivityManager cm=(android.net.ConnectivityManager)appContext.getSystemService(android.content.Context.CONNECTIVITY_SERVICE);android.net.NetworkCapabilities capabilities=cm==null?null:cm.getNetworkCapabilities(cm.getActiveNetwork());if(capabilities==null||!capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI))return;
    final String scope=cacheScope(),server=origin,jar=jar(),key=scope+path;final int revision=epoch;if(!warming.add(key))return;
    mediaCacheExecutor.execute(()->{HttpURLConnection c=null;try{if(revision!=epoch)return;c=(HttpURLConnection)new URL(server+path).openConnection();c.setConnectTimeout(8000);c.setReadTimeout(15000);c.setInstanceFollowRedirects(false);c.setRequestProperty("Cookie",jar);if(c.getResponseCode()==200&&String.valueOf(c.getContentType()).startsWith("video/")&&c.getContentLengthLong()<=32L*1024*1024){byte[] bytes=read(c.getInputStream(),32*1024*1024);if(revision==epoch){diskCache.put(scope,"video:"+path,bytes);File local=diskCache.video(scope,path);if(local!=null){android.media.MediaMetadataRetriever retriever=new android.media.MediaMetadataRetriever();try{retriever.setDataSource(local.getAbsolutePath());android.graphics.Bitmap frame=android.os.Build.VERSION.SDK_INT>=27?retriever.getScaledFrameAtTime(0,android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,240,384):null;if(frame!=null){ByteArrayOutputStream out=new ByteArrayOutputStream();frame.compress(android.graphics.Bitmap.CompressFormat.JPEG,80,out);frame.recycle();if(revision==epoch)diskCache.put(scope,"thumb:"+path,out.toByteArray());}}finally{retriever.release();}}}}}catch(Exception|OutOfMemoryError ignored){}finally{if(c!=null)c.disconnect();warming.remove(key);}});
  }
  private volatile String device = "";
  private static String join(String a, String b) { return a.isEmpty() ? b : b.isEmpty() ? a : a + "; " + b; }
  /** Cookie header for media players (session + remembered device). */
  public String jar() { return join(cookie, device); }
  public String origin() { return origin; }
  private volatile String origin = ServerConfig.DEFAULT_ORIGIN,
    cookie = "";

  public interface Result {
    void done(JSONObject data, String error, int status);
  }

  public interface Bytes {
    void done(byte[] bytes);
  }

  public synchronized void configure(String value) {
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

  /** Adopt the session handed over by the Kinnect hub to the standalone game module. */
  public synchronized void adopt(String server, String cookieHeader) {
    configure(server);
    if (cookieHeader == null || cookieHeader.isEmpty()) return;
    for (String part : cookieHeader.split(";")) {
      String value = part.trim();
      if (value.startsWith("kinnect_session=")) cookie = value;
      else if (value.startsWith("kinnect_device=")) device = value;
    }
    if (sessions != null) {
      if (!cookie.isEmpty()) sessions.save(origin, cookie);
      if (!device.isEmpty()) sessions.saveDevice(origin, device);
    }
    epoch++;
    snapshots.clear();
  }

  public synchronized void clear() {
    if(diskCache!=null)diskCache.clear();
    cookie = "";
    if(sessions!=null)sessions.wipe();
    epoch++;snapshots.clear();
  }

  private static volatile boolean fixtureEnabled = false;
  public static synchronized boolean enableFixture(android.content.Context context, boolean enable) {
    if (!enable) {
      fixtureEnabled = false;
      return false;
    }
    if (context == null) return false;
    boolean isDebug = (context.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    if (!isDebug) {
      fixtureEnabled = false;
      return false;
    }
    fixtureEnabled = true;
    return true;
  }
  public static boolean isFixtureEnabled() {
    if (!fixtureEnabled) {
      java.io.File flag = new java.io.File("/data/local/tmp/kinnect_fixture");
      if (flag.exists()) fixtureEnabled = true;
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

  private FixtureResult offlineFixture(String method, String path, JSONObject data) {
    String cleanPath = path.split("\\?", 2)[0];
    long nowTime = System.currentTimeMillis();
    long postTime = nowTime - 3600000L;
    try {
      if ("GET".equals(method) && "/api/me".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"user\":{\"id\":\"usr_qa_review\",\"username\":\"minhanh\",\"name\":\"Minh Anh\",\"role\":\"user\",\"coins\":1200,\"bio\":\"Kinnect QA Review\",\"followersCount\":128,\"followingCount\":64,\"showActivity\":true}}"), null, 200);
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
        return new FixtureResult(new JSONObject("{\"user\":{\"id\":\"usr_qa_review\",\"name\":\"Minh Anh\",\"bio\":\"Kinnect QA Review\"}}"), null, 200);
      }
      if ("GET".equals(method) && "/api/me/sessions".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"sessions\":[{\"id\":\"sess_1\",\"label\":\"Pixel 6 · Android 14\",\"current\":true,\"expires\":\"2026-12-01T00:00:00Z\"}]}"), null, 200);
      }
      if ("GET".equals(method) && "/api/stories".equals(cleanPath)) {
        return new FixtureResult(new JSONObject("{\"stories\":[{\"id\":\"st_1\",\"body\":\"Khoảnh khắc cuối tuần cùng Kinnect!\",\"created\":" + postTime + ",\"mediaUrl\":\"/story.jpg\",\"user\":{\"id\":\"usr_story\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\"},\"author\":{\"id\":\"usr_story\",\"name\":\"Linh Nhi\",\"username\":\"linhnhi\"}}]}"), null, 200);
      }
      if ("GET".equals(method) && ("/api/posts".equals(cleanPath) || cleanPath.startsWith("/api/posts?"))) {
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
        if (path.contains("khong_tim_thay")) {
          return new FixtureResult(new JSONObject("{\"users\":[],\"total\":0}"), null, 200);
        }
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

  public interface Progress { void sent(long bytes,long total); }
  public void call(String method,String path,JSONObject data,Result callback){call(method,path,data,null,callback);}
  public void call(
    String method,
    String path,
    JSONObject data,
    Progress progress,
    Result callback
  ) {
    apiDispatchCount++;
    android.util.Log.i("KinnectQA", "API_TRANSPORT_ATTEMPT: method=" + method + " path=" + path + " counter=" + apiDispatchCount);
    if (fixtureEnabled) {
      FixtureResult fr = offlineFixture(method, path, data);
      main.post(() -> callback.done(fr.data, fr.error, fr.status));
      return;
    }
    final String primaryServer = origin,
      primarySession = cookie;
    final int primaryRevision = epoch;
    final String snapshotKey=primaryRevision+":"+primaryServer+path;final Snapshot snapshot=method.equals("GET")?snapshots.get(snapshotKey):null;
    if(method.equals("GET")&&appContext!=null){android.net.ConnectivityManager cm=(android.net.ConnectivityManager)appContext.getSystemService(android.content.Context.CONNECTIVITY_SERVICE);if(cm!=null&&cm.getActiveNetwork()==null){JSONObject saved=cachedGet(path);if(saved!=null){main.post(()->{if(primaryRevision==epoch&&primaryServer.equals(origin))callback.done(saved,null,200);});return;}}}
    maybeProbePrimary();
    activeRequests.incrementAndGet();
    executor.execute(() -> {
      String server = primaryServer, session = primarySession;
      int revision = primaryRevision;
      boolean failedOver = false;
      JSONObject result = null;
      String error = null;
      int status = 0;
      int deliveryRevision=revision;
      Exception failure = null;
      for (;;) {
      result = null; error = null; status = 0; failure = null; deliveryRevision = revision;
      HttpURLConnection connection = null;
      try {
        if (
          !path.startsWith("/api/") || path.contains("..")
        ) throw new IOException(I18n.t("API không hợp lệ."));
        connection = (HttpURLConnection) new URL(
          server + path
        ).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(8000);
        connection.setReadTimeout(method.equals("GET")?12000:600000);
        connection.setRequestMethod(method);
        connection.setRequestProperty("Accept", "application/json");if(snapshot!=null)connection.setRequestProperty("If-None-Match",snapshot.etag);
        connection.setRequestProperty("Origin", server);
        String jar = join(session, device);
        if (!jar.isEmpty()) connection.setRequestProperty("Cookie", jar);
        if (data != null) {
          connection.setDoOutput(true);
          connection.setRequestProperty(
            "Content-Type",
            "application/json; charset=utf-8"
          );
          byte[] payload = data.toString().getBytes("UTF-8");
          connection.setFixedLengthStreamingMode(payload.length);
          try (OutputStream out = connection.getOutputStream()) {
            long last=0;
            for(int offset=0;offset<payload.length;){int count=Math.min(65536,payload.length-offset);out.write(payload,offset,count);offset+=count;long now=System.currentTimeMillis();if(progress!=null&&(now-last>=100||offset==payload.length)){final int sent=offset;main.post(()->progress.sent(sent,payload.length));last=now;}}
            out.flush();
          }
        }
        status = connection.getResponseCode();
        java.util.List<String> setCookies = connection.getHeaderFields().get("Set-Cookie");
        boolean sessionChanged=false;
        synchronized (this) {
          for (int i = 0; setCookies != null && i < setCookies.size(); i++) {
            String responseCookie = setCookies.get(i);
            if (responseCookie == null || !server.equals(origin) || revision != epoch) continue;
            if(responseCookie.startsWith("kinnect_session=")){String next=responseCookie.split(";",2)[0];if(next.equals("kinnect_session="))next="";sessionChanged|=!cookie.equals(next);cookie=next;if(sessions!=null)sessions.save(origin,cookie);}
            if (responseCookie.startsWith("kinnect_device=")) {device = responseCookie.split(";", 2)[0];if(sessions!=null)sessions.saveDevice(origin,device);}
          }
        }
        synchronized(this){if(sessionChanged&&server.equals(origin)&&revision==epoch){epoch++;deliveryRevision=epoch;}}
        boolean unchanged=status==304&&snapshot!=null;if(unchanged)status=200;
        InputStream input =
          status >= 200 && status < 300
            ? connection.getInputStream()
            : connection.getErrorStream();
        String response=unchanged?snapshot.body:input==null?"{}":new String(read(input,2000000),"UTF-8");
        try { result = new JSONObject(response); }
        catch (org.json.JSONException invalid) {
          if (status >= 200 && status < 300) throw new IOException(I18n.t("Máy chủ trả về dữ liệu không hợp lệ."));
          result = new JSONObject();
        }
        if(method.equals("GET")&&status==200&&response.length()<262144&&connection.getHeaderField("ETag")!=null&&revision==epoch)snapshots.put(snapshotKey,new Snapshot(connection.getHeaderField("ETag"),response));
        if (status < 200 || status >= 300) error = status >= 500 ? httpFailure(status) : result.optString("error", httpFailure(status));
        if(method.equals("GET")&&status==200&&diskCache!=null&&!session.isEmpty()&&cacheable(path))diskCache.put(server+"\n"+session,"json:"+path,response.getBytes("UTF-8"));
        if(method.equals("GET")&&(status==401||status==403)&&diskCache!=null)diskCache.clear();
        if(!method.equals("GET")&&status>=200&&status<300&&(path.endsWith("/block")||path.equals("/api/me/avatar"))&&diskCache!=null)diskCache.clear();
      } catch (OutOfMemoryError oom) {
        error = I18n.t("Thiết bị không đủ bộ nhớ để chuẩn bị tệp tải lên.");
      } catch (java.net.SocketTimeoutException timeout) {
        failure = timeout;
        error = I18n.t(progress != null ? "Kết nối tải lên hết thời gian chờ. Kiểm tra mạng rồi thử lại." : "Kết nối chậm, vui lòng thử lại.");
      } catch (Exception caught) {
        failure = caught;
        error = status >= 200 && status < 300 ? I18n.t("Máy chủ trả về dữ liệu không hợp lệ.") : status > 0 ? httpFailure(status) : I18n.t("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.");
      } finally {
        if (connection != null) connection.disconnect();
      }
      if (error != null && !failedOver && shouldFailover(method, status, failure) && failoverFrom(server)) {
        failedOver = true; server = origin; session = cookie; revision = epoch; continue;
      }
      break;
      }
      if(error!=null&&(status==0||status>=500)&&method.equals("GET")&&server.equals(origin)&&revision==epoch){JSONObject cached=cachedGet(path);if(cached!=null){result=cached;error=null;status=200;}}
      final JSONObject answer = result;
      final String message = error;
      final int code = status;
      final int acceptedRevision=deliveryRevision;
      final String deliveredServer=server;
      main.post(() -> {try{if(epoch==acceptedRevision&&deliveredServer.equals(origin))callback.done(answer,message,code);}finally{activeRequests.decrementAndGet();}});
    });
  }

  /** Chỉ chuyển sang máy chủ dự phòng khi lỗi mạng/tunnel — không phát lại yêu cầu đã tới máy chủ. */
  private boolean shouldFailover(String method,int status,Exception failure){
    if(!origin.equals(ServerConfig.DEFAULT_ORIGIN))return false;
    boolean tunnel=status>=520&&status<=530;
    boolean connect=status==0&&(failure instanceof java.net.ConnectException||failure instanceof java.net.UnknownHostException||failure instanceof java.net.NoRouteToHostException);
    if(method.equals("GET")||method.equals("HEAD"))return status==0||tunnel||status==502||status==504;
    return connect||tunnel;
  }

  private synchronized boolean failoverFrom(String failed){
    if(!failed.equals(origin)||!ServerConfig.DEFAULT_ORIGIN.equals(origin))return false;
    String next=ServerConfig.FALLBACK_ORIGIN;
    if(next.isEmpty()||next.equals(failed))return false;
    if(appContext!=null){android.net.ConnectivityManager cm=(android.net.ConnectivityManager)appContext.getSystemService(android.content.Context.CONNECTIVITY_SERVICE);if(cm!=null&&cm.getActiveNetwork()==null)return false;}
    origin=next;epoch++;snapshots.clear();
    cookie=sessions==null?"":sessions.load(next);
    device=sessions==null?"":sessions.loadDevice(next);
    return true;
  }

  /** Khi đang ở máy chủ dự phòng: thăm dò PC mỗi phút, tự quay lại khi PC hoạt động trở lại. */
  private volatile long lastPrimaryProbe=0;
  private final java.util.concurrent.atomic.AtomicInteger activeRequests=new java.util.concurrent.atomic.AtomicInteger(0);
  private void maybeProbePrimary(){
    if(fixtureEnabled||!origin.equals(ServerConfig.FALLBACK_ORIGIN))return;
    if(activeRequests.get()>0)return;
    long now=System.currentTimeMillis();
    if(now-lastPrimaryProbe<60000)return;
    lastPrimaryProbe=now;
    mediaCacheExecutor.execute(()->{HttpURLConnection c=null;try{c=(HttpURLConnection)new URL(ServerConfig.DEFAULT_ORIGIN+"/api/me").openConnection();c.setConnectTimeout(3000);c.setReadTimeout(3000);c.setInstanceFollowRedirects(false);if(c.getResponseCode()>0)switchBackToPrimary();}catch(Exception ignored){}finally{if(c!=null)c.disconnect();}});
  }

  private synchronized void switchBackToPrimary(){
    if(!origin.equals(ServerConfig.FALLBACK_ORIGIN)||activeRequests.get()>0)return;
    origin=ServerConfig.DEFAULT_ORIGIN;epoch++;snapshots.clear();
    cookie=sessions==null?"":sessions.load(origin);
    device=sessions==null?"":sessions.loadDevice(origin);
  }

  private static String httpFailure(int status) {
    if (status == 408 || status == 504) return I18n.t("Kết nối chậm, vui lòng thử lại.");
    if (status >= 500) return I18n.t("Máy chủ đang tạm gián đoạn. Vui lòng thử lại sau.");
    if (status == 413) return I18n.t("Máy chủ hoặc đường truyền từ chối kích thước tải lên (HTTP 413).");
    if (status == 401) return I18n.t("Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.");
    if (status == 429) return I18n.t("Máy chủ đang bận hoặc cần chờ trước lần đăng tiếp theo (HTTP 429).");
    return I18n.t("Máy chủ chưa nhận được yêu cầu (HTTP ") + status + ").";
  }

  public void image(String path, Bytes callback) {
    final String server = origin,
      session = cookie;
    final int revision = epoch;final String scope=cacheScope();
    executor.execute(() -> {
      byte[] bytes = null;
      HttpURLConnection c = null;
      try {
        if (
          !(path.startsWith("/api/users/") || path.startsWith("/api/posts/") || path.startsWith("/api/chat-attachments/") || path.startsWith("/api/private-photos/") || path.startsWith("/api/shorts/") || path.startsWith("/music/")) ||
          path.contains("..")
        ) throw new IOException();
        c = (HttpURLConnection) new URL(server + path).openConnection();
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(10000);
        c.setReadTimeout(10000);
        c.setRequestProperty("Cookie", join(session, device));
        int status=c.getResponseCode();
        if (status == 200) {bytes = read(c.getInputStream(),path.endsWith("/avatar") ? 1100000 : 30000000);if(diskCache!=null&&String.valueOf(c.getContentType()).startsWith("image/")&&!path.startsWith("/api/private-photos/")&&!path.startsWith("/api/chat-attachments/")&&revision==epoch)diskCache.put(scope,"image:"+path,bytes);}
        else if(status>=500&&diskCache!=null)bytes=diskCache.get(scope,"image:"+path,AppCache.WEEK);
      } catch (Exception ignored) {
        if(diskCache!=null&&revision==epoch)bytes=diskCache.get(scope,"image:"+path,AppCache.WEEK);
      } finally {
        if (c != null) c.disconnect();
      }
      final byte[] result = bytes;
      main.post(() -> { if (epoch == revision && origin.equals(server)) callback.done(result); });
    });
  }

  /** Ảnh từ trang tin tức (chỉ HTTPS, tối đa 3 MB, không gửi cookie). */
  public void remote(String url, Bytes callback) {
    executor.execute(() -> {
      byte[] bytes = null;
      HttpURLConnection c = null;
      try {
        if (!url.startsWith("https://")) throw new IOException();
        c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(10000);
        if (c.getResponseCode() == 200) bytes = read(c.getInputStream(), 3000000);
      } catch (Exception ignored) {
      } finally {
        if (c != null) c.disconnect();
      }
      final byte[] result = bytes;
      main.post(() -> callback.done(result));
    });
  }

  /** Read a selected media file without a fixed app-level size limit. */
  public static byte[] readAll(InputStream input) throws IOException {
    try (InputStream in=input; ByteArrayOutputStream out=new ByteArrayOutputStream()) {
      byte[] buffer=new byte[65536]; int count;
      while((count=in.read(buffer))!=-1) out.write(buffer,0,count);
      return out.toByteArray();
    }
  }

  public static byte[] read(InputStream input, int maximum) throws IOException {
    try (
      InputStream in = input;
      ByteArrayOutputStream out = new ByteArrayOutputStream()
    ) {
      byte[] buffer = new byte[8192];
      int count;
      while ((count = in.read(buffer)) != -1) {
        if (out.size() + count > maximum) throw new IOException(
          I18n.t("Dữ liệu quá lớn.")
        );
        out.write(buffer, 0, count);
      }
      return out.toByteArray();
    }
  }
}

