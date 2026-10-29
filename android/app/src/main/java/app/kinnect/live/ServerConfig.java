package app.kinnect.live;

import java.net.URI;

/** Public bootstrap URL only. Never put credentials in this class. */
public final class ServerConfig {

  public static final String DEFAULT_ORIGIN =
    "https://app.kinnect.io.vn";

  private ServerConfig() {}

  public static String normalize(String value) {
    try {
      URI uri = new URI(value.trim());
      if (
        !"https".equalsIgnoreCase(uri.getScheme()) ||
        uri.getHost() == null ||
        uri.getRawUserInfo() != null ||
        uri.getRawQuery() != null ||
        uri.getRawFragment() != null ||
        uri.getPort() == 0 ||
        uri.getPort() > 65535 ||
        !(uri.getRawPath().isEmpty() || "/".equals(uri.getRawPath()))
      ) {
        throw new IllegalArgumentException();
      }
      String host = uri.getHost().toLowerCase(java.util.Locale.ROOT);
      int port = uri.getPort();
      return "https://" + host + (port == -1 || port == 443 ? "" : ":" + port);
    } catch (Exception error) {
      throw new IllegalArgumentException(
        I18n.t("Nhập địa chỉ HTTPS hợp lệ, không kèm đường dẫn hoặc mật khẩu.")
      );
    }
  }

  public static String resolve(String saved) {
    if (saved == null || saved.trim().isEmpty()) return DEFAULT_ORIGIN;
    try {
      return normalize(saved);
    } catch (IllegalArgumentException error) {
      return DEFAULT_ORIGIN;
    }
  }
}
