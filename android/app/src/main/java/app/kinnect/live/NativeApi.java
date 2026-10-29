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
  private SessionStore sessions;
  public synchronized void initialize(android.content.Context context,String server){sessions=new SessionStore(context);configure(server);cookie=sessions.load(origin);device=sessions.loadDevice(origin);}
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

  public synchronized void clear() {
    cookie = "";
    if(sessions!=null)sessions.save(origin, "");
    epoch++;snapshots.clear();
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
    final String server = origin,
      session = cookie;
    final int revision = epoch;
    final String snapshotKey=revision+":"+server+path;final Snapshot snapshot=method.equals("GET")?snapshots.get(snapshotKey):null;
    executor.execute(() -> {
      JSONObject result = null;
      String error = null;
      int status = 0;
      int deliveryRevision=revision;
      HttpURLConnection connection = null;
      try {
        if (
          !path.startsWith("/api/") || path.contains("..")
        ) throw new IOException(I18n.t("API không hợp lệ."));
        connection = (HttpURLConnection) new URL(
          server + path
        ).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(method.equals("GET")?20000:600000);
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
      } catch (OutOfMemoryError failure) {
        error = I18n.t("Thiết bị không đủ bộ nhớ để chuẩn bị tệp tải lên.");
      } catch (java.net.SocketTimeoutException failure) {
        error = I18n.t(progress != null ? "Kết nối tải lên hết thời gian chờ. Kiểm tra mạng rồi thử lại." : "Kết nối chậm, vui lòng thử lại.");
      } catch (Exception failure) {
        error = status >= 200 && status < 300 ? I18n.t("Máy chủ trả về dữ liệu không hợp lệ.") : status > 0 ? httpFailure(status) : I18n.t("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.");
      } finally {
        if (connection != null) connection.disconnect();
      }
      final JSONObject answer = result;
      final String message = error;
      final int code = status;
      final int acceptedRevision=deliveryRevision;
      main.post(() -> {if(epoch==acceptedRevision&&server.equals(origin))callback.done(answer,message,code);});
    });
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
    final int revision = epoch;
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
        if (c.getResponseCode() == 200) bytes = read(
          c.getInputStream(),
          path.endsWith("/avatar") ? 1100000 : 30000000
        );
      } catch (Exception ignored) {
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

