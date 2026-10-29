package app.kinnect.live;

public final class KinnectApplication extends android.app.Application {
  @Override public void onCreate(){super.onCreate();I18n.initialize(this);}
}
