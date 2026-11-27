package app.kinnect.live;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;

public final class KinnectApplication extends android.app.Application {
  private int startedCount = 0;

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
    registerActivityLifecycleCallbacks(new ActivityLifecycleCallbacks() {
      @Override public void onActivityCreated(Activity activity, Bundle savedInstanceState) {}
      @Override public void onActivityStarted(Activity activity) {
        if (activity instanceof IncomingCallActivity) return;
        int prev = startedCount++;
        if (prev == 0) KinnectService.sendVisibility(true);
      }
      @Override public void onActivityResumed(Activity activity) {}
      @Override public void onActivityPaused(Activity activity) {}
      @Override public void onActivityStopped(Activity activity) {
        if (activity instanceof IncomingCallActivity) return;
        if (startedCount > 0) startedCount--;
        if (startedCount == 0 && !activity.isChangingConfigurations()) {
          KinnectService.sendVisibility(false);
        }
      }
      @Override public void onActivitySaveInstanceState(Activity activity, Bundle outState) {}
      @Override public void onActivityDestroyed(Activity activity) {}
    });
    if (!NativeApi.shared.cookieFor(NativeApi.shared.origin()).isEmpty()) {
      KinnectService.start(this);
    }
  }
}
