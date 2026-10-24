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
      epoch++;
    }
    origin = next;
  }

  public String cookieFor(String server) {
    return server.equals(origin) ? cookie : "";
  }

  public synchronized void clear() {
    cookie = "";
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
        connection.setReadTimeout(15000);
        connection.setRequestMethod(method);
        connection.setRequestProperty("Accept", "application/json");
        connection.setRequestProperty("Origin", server);
        if (!session.isEmpty()) connection.setRequestProperty(
          "Cookie",
          session
        );
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
        String responseCookie = connection.getHeaderField("Set-Cookie");
        synchronized (this) {
          if (
            responseCookie != null &&
            responseCookie.startsWith("kinnect_session=") &&
            server.equals(origin) &&
            revision == epoch
          ) cookie = responseCookie.split(";", 2)[0];
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
    executor.execute(() -> {
      byte[] bytes = null;
      HttpURLConnection c = null;
      try {
        if (
          !path.startsWith("/api/users/") ||
          !path.endsWith("/avatar") ||
          path.contains("..")
        ) throw new IOException();
        c = (HttpURLConnection) new URL(server + path).openConnection();
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(10000);
        c.setReadTimeout(10000);
        c.setRequestProperty("Cookie", session);
        if (c.getResponseCode() == 200) bytes = read(
          c.getInputStream(),
          1100000
        );
      } catch (Exception ignored) {
      } finally {
        if (c != null) c.disconnect();
      }
      final byte[] result = bytes;
      main.post(() -> callback.done(result));
    });
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
