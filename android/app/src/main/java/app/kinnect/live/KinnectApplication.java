package app.kinnect.live;

import android.content.Context;

public final class KinnectApplication extends android.app.Application {
  // KHÔNG ghi đè fontScale của người dùng.
  // Trước đây: config.fontScale = config.fontScale * WebDesign.UI_SCALE (0.9f) → người đã tăng
  // cỡ chữ trong Settings hệ thống (vì lý do thị lực) bị app thu nhỏ lại 10%, đồng thời mọi
  // kích thước thiết kế bị lệch so với bản thiết kế. Tỉ lệ UI_SCALE chỉ dùng cho khoảng cách
  // (dp), không dùng cho cỡ chữ.
  @Override protected void attachBaseContext(Context base) {
    super.attachBaseContext(base);
  }

  @Override public void onCreate(){
    super.onCreate();
    I18n.initialize(this);
    NativeApi.shared.initialize(this, ServerConfig.DEFAULT_ORIGIN);
    if (!NativeApi.shared.cookieFor(ServerConfig.DEFAULT_ORIGIN).isEmpty()) {
      KinnectService.start(this);
    }
  }
}
