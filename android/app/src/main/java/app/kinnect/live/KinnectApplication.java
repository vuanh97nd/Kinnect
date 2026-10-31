package app.kinnect.live;
import android.content.Context;
import android.content.res.Configuration;

public final class KinnectApplication extends android.app.Application {
  // Giảm nhẹ cỡ chữ toàn app (đồng bộ với tỉ lệ dp UI_SCALE) để hiển thị nhiều nội dung hơn.
  @Override protected void attachBaseContext(Context base) {
    Configuration config = new Configuration(base.getResources().getConfiguration());
    config.fontScale = config.fontScale * WebDesign.UI_SCALE;
    super.attachBaseContext(base.createConfigurationContext(config));
  }
  @Override public void onCreate(){super.onCreate();I18n.initialize(this);}
}
