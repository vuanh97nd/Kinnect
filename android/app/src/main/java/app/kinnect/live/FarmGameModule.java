package app.kinnect.live;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;

/** Manages the optional standalone farm game module and hands over the signed-in session. */
final class FarmGameModule {
  static final String PACKAGE = "app.kinnect.farm";
  static final String ACTIVITY = "app.kinnect.live.FarmActivity";
  static final String DOWNLOAD_PATH = "/download/farm-game";

  private FarmGameModule() { }

  static boolean installed(Context context) {
    try {
      context.getPackageManager().getPackageInfo(PACKAGE, 0);
      return true;
    } catch (PackageManager.NameNotFoundException missing) {
      return false;
    }
  }

  static void open(Activity activity) {
    if (installed(activity)) {
      launch(activity);
      return;
    }
    if (NativeApi.shared.jar().isEmpty()) {
      new Sheet(activity).setTitle(I18n.t("Nông trại 3D"))
        .setMessage(I18n.t("Hãy đăng nhập Kinnect trước khi tải module nông trại."))
        .setPositiveButton(I18n.t("Đóng"), null).show();
      return;
    }
    new Sheet(activity).setTitle(I18n.t("Nông trại 3D"))
      .setMessage(I18n.t("Nông trại là một module trò chơi riêng. Tải module về máy để chơi ở màn hình ngang. Sau khi cài, bạn có thể mở nông trại từ Kinnect hoặc từ biểu tượng riêng."))
      .setPositiveButton(I18n.t("Tải module"), (dialog, which) -> download(activity))
      .setNegativeButton(I18n.t("Để sau"), null).show();
  }

  static void launch(Activity activity) {
    Intent intent = new Intent();
    intent.setClassName(PACKAGE, ACTIVITY);
    intent.putExtra("origin", NativeApi.shared.origin());
    intent.putExtra("session", NativeApi.shared.jar());
    intent.putExtra("language", I18n.current());
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    try {
      activity.startActivity(intent);
    } catch (RuntimeException missing) {
      new Sheet(activity).setMessage(I18n.t("Chưa mở được module nông trại. Hãy cài lại module."))
        .setPositiveButton(I18n.t("Đóng"), null).show();
    }
  }

  private static void download(Activity activity) {
    FarmGameDownloadActivity.open(activity, NativeApi.shared.origin() + DOWNLOAD_PATH);
  }
}
