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
    epoch++;
  }

  public void call(
    String method,
    String path,
    JSONObject data,
    Result callback
  ) {
    final String server = origin,
      session = cookie;
    final int revision = epoch;
    executor.execute(() -> {
      JSONObject result = null;
      String error = null;
      int status = 0;
      HttpURLConnection connection = null;
      try {
        if (
          !path.startsWith("/api/") || path.contains("..")
        ) throw new IOException("API không hợp lệ.");
        connection = (HttpURLConnection) new URL(
          server + path
        ).openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(600000);
        connection.setRequestMethod(method);
        connection.setRequestProperty("Accept", "application/json");
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
          try (OutputStream out = connection.getOutputStream()) {
            out.write(payload);
          }
        }
        status = connection.getResponseCode();
        java.util.List<String> setCookies = connection.getHeaderFields().get("Set-Cookie");
        synchronized (this) {
          for (int i = 0; setCookies != null && i < setCookies.size(); i++) {
            String responseCookie = setCookies.get(i);
            if (responseCookie == null || !server.equals(origin) || revision != epoch) continue;
            if (responseCookie.startsWith("kinnect_session=")) {cookie = responseCookie.split(";", 2)[0];if(cookie.equals("kinnect_session="))cookie="";if(sessions!=null)sessions.save(origin,cookie);}
            if (responseCookie.startsWith("kinnect_device=")) {device = responseCookie.split(";", 2)[0];if(sessions!=null)sessions.saveDevice(origin,device);}
          }
        }
        InputStream input =
          status >= 200 && status < 300
            ? connection.getInputStream()
            : connection.getErrorStream();
        result = new JSONObject(
          input == null ? "{}" : new String(read(input, 2000000), "UTF-8")
        );
        if (status < 200 || status >= 300) error = result.optString(
          "error",
          "Không thể kết nối. HTTP " + status
        );
      } catch (Exception failure) {
        error =
          "Không kết nối được máy chủ. Kiểm tra mạng hoặc đổi URL trong Cài đặt.";
      } finally {
        if (connection != null) connection.disconnect();
      }
      final JSONObject answer = result;
      final String message = error;
      final int code = status;
      main.post(() -> callback.done(answer, message, code));
    });
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
          "Dữ liệu quá lớn."
        );
        out.write(buffer, 0, count);
      }
      return out.toByteArray();
    }
  }
}

