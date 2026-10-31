package app.kinnect.live;

/** Play builds receive updates through Google Play. */
public final class ApkUpdates {
  private ApkUpdates() {}

  public static void check(android.app.Activity activity) {
    String id = activity.getPackageName();
    try {
      activity.startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW,
        android.net.Uri.parse("market://details?id=" + id)).setPackage("com.android.vending"));
    } catch (android.content.ActivityNotFoundException unavailable) {
      activity.startActivity(new android.content.Intent(android.content.Intent.ACTION_VIEW,
        android.net.Uri.parse("https://play.google.com/store/apps/details?id=" + id)));
    }
  }
}
