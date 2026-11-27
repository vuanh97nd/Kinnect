package app.kinnect.live;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Log;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import org.json.JSONObject;
import java.util.Map;

/**
 * Firebase Cloud Messaging (FCM) Service for Kinnect Android.
 * - Automatically registers/refreshes the device FCM token with POST
 * /api/devices/push ({kind:"fcm", token}).
 * - Wakes up the app and displays high-priority notifications / incoming call
 * screens even when closed or in Doze mode.
 */
public final class KinnectFirebaseMessagingService extends FirebaseMessagingService {
  private static final String TAG = "KinnectFCM";
  private static final String PREF_NAME = "kinnect_fcm";
  private static final String KEY_TOKEN = "fcm_token";

  public static void syncTokenWithServer(Context context) {
    if (context == null || NativeApi.isFixtureEnabled())
      return;
    final Context appCtx = context.getApplicationContext();
    try {
      FirebaseMessaging.getInstance().getToken().addOnCompleteListener(task -> {
        if (!task.isSuccessful()) {
          Log.w(TAG, "Fetching FCM registration token failed", task.getException());
          return;
        }
        String token = task.getResult();
        if (token != null && !token.trim().isEmpty()) {
          registerTokenOnServer(appCtx, token.trim());
        }
      });
    } catch (Throwable t) {
      Log.w(TAG, "FirebaseMessaging not initialized yet: " + t.getMessage());
    }
  }

  public static void registerTokenOnServer(Context context, String token) {
    if (context == null || token == null || token.trim().isEmpty())
      return;
    final String clean = token.trim();
    SharedPreferences prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
    prefs.edit().putString(KEY_TOKEN, clean).apply();

    NativeApi.shared.initialize(context, ServerConfig.DEFAULT_ORIGIN);
    if (NativeApi.shared.cookieFor(NativeApi.shared.origin()).isEmpty())
      return;

    try {
      JSONObject body = new JSONObject();
      body.put("kind", "fcm");
      body.put("token", clean);
      NativeApi.shared.call("POST", "/api/devices/push", body, (data, error, status) -> {
        if (status >= 200 && status < 300) {
          Log.i(TAG, "FCM token registered with Kinnect server.");
        } else {
          Log.w(TAG, "FCM token registration returned HTTP " + status);
        }
      });
    } catch (Exception e) {
      Log.w(TAG, "Failed to register FCM token: " + e.getMessage());
    }
  }

  public static void unregisterTokenFromServer(Context context) {
    unregisterTokenFromServer(context, null);
  }

  public static void unregisterTokenFromServer(Context context, Runnable done) {
    if (context == null) {
      if (done != null)
        done.run();
      return;
    }
    SharedPreferences prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
    String token = prefs.getString(KEY_TOKEN, "");
    if (token == null || token.isEmpty()) {
      if (done != null)
        done.run();
      return;
    }
    try {
      JSONObject body = new JSONObject();
      body.put("kind", "fcm");
      body.put("token", token);
      NativeApi.shared.call("DELETE", "/api/devices/push", body, (data, error, status) -> {
        if (done != null)
          done.run();
      });
    } catch (Exception ignored) {
      if (done != null)
        done.run();
    }
  }

  @Override
  public void onNewToken(String token) {
    super.onNewToken(token);
    registerTokenOnServer(getApplicationContext(), token);
  }

  @Override
  public void onMessageReceived(RemoteMessage remoteMessage) {
    super.onMessageReceived(remoteMessage);
    Context ctx = getApplicationContext();
    KinnectService.channels(ctx);

    Map<String, String> data = remoteMessage.getData();
    String type = data != null ? data.get("type") : null;

    if ("call".equals(type)) {
      try {
        NativeApi.shared.initialize(ctx, ServerConfig.DEFAULT_ORIGIN);
        NativeCallEnds.initialize(ctx);
        if (NativeApi.shared.cookieFor(NativeApi.shared.origin()).isEmpty())
          return;
        String callId = data.get("callId") != null ? data.get("callId") : "";
        if (!callId.isEmpty() && NativeCallEnds.contains(callId))
          return;
        JSONObject callPayload = new JSONObject();
        callPayload.put("type", "call-incoming");
        callPayload.put("callId", callId);
        callPayload.put("mode", data.get("mode") != null ? data.get("mode") : "audio");
        JSONObject from = new JSONObject();
        from.put("id", data.get("callerId") != null ? data.get("callerId") : "");
        from.put("name", data.get("callerName") != null ? data.get("callerName") : "Kinnect");
        callPayload.put("from", from);
        new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
          boolean sameCall = KinnectService.pendingIncoming != null
              && callId.equals(KinnectService.pendingIncoming.optString("callId"));
          if (KinnectService.pendingIncoming != null && !sameCall && KinnectService.isPendingAcceptFresh())
            return;
          KinnectService.pendingIncoming = callPayload;
          if (!sameCall)
            KinnectService.markPendingAccept(false);
          if (!KinnectService.appVisible) {
            KinnectService.showIncomingCall(ctx, callPayload);
          }
          try {
            ctx.startService(new Intent(ctx, KinnectService.class).putExtra("skipRing", true));
          } catch (RuntimeException ignored) {}
        });
      } catch (Exception e) {
        Log.w(TAG, "Failed to handle FCM incoming call: " + e.getMessage());
      }
      return;
    }

    if ("call-ended".equals(type)) {
      NativeCallEnds.initialize(ctx);
      final String endedCallId = data != null && data.get("callId") != null ? data.get("callId") : "";
      if (!endedCallId.isEmpty()) {
        NativeCallEnds.mark(NativeSocket.json("type", "call-ended", "callId", endedCallId));
      }
      new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
        JSONObject pending = KinnectService.pendingIncoming;
        if (endedCallId.isEmpty() || pending == null
            || endedCallId.equals(pending.optString("callId"))) {
          KinnectService.clearCall(ctx);
        }
      });
      return;
    }

    NativeApi.shared.initialize(ctx, ServerConfig.DEFAULT_ORIGIN);
    if (NativeApi.shared.cookieFor(NativeApi.shared.origin()).isEmpty())
      return;
    if (KinnectService.appVisible || KinnectService.isReady())
      return;

    String title = "Kinnect";
    String body = "Bạn có thông báo mới trên Kinnect.";
    if (remoteMessage.getNotification() != null) {
      if (remoteMessage.getNotification().getTitle() != null)
        title = remoteMessage.getNotification().getTitle();
      if (remoteMessage.getNotification().getBody() != null)
        body = remoteMessage.getNotification().getBody();
    } else if (data != null) {
      if (data.get("title") != null)
        title = data.get("title");
      if (data.get("body") != null)
        body = data.get("body");
    }

    String kind = data != null && data.get("kind") != null ? data.get("kind") : "notification";
    boolean isChat = kind.contains("message");
    Intent open = new Intent(ctx, MainActivity.class)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    if (data != null && !data.isEmpty()) {
      try {
        open.putExtra("notification", new JSONObject(data).toString());
      } catch (Exception ignored) {
      }
    }

    String actorId = data != null && data.get("actorId") != null ? data.get("actorId") : "";
    String ref = data != null && data.get("ref") != null ? data.get("ref") : "";
    String nId = data != null && data.get("notificationId") != null ? data.get("notificationId") : (title + body + kind);
    int notifId = 100 + ((isChat ? "chat:" + actorId + ("group_message".equals(kind) ? ref : "") : nId).hashCode() & 0xffff);
    PendingIntent pi = PendingIntent.getActivity(
        ctx,
        notifId,
        open,
        PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

    Notification.Builder builder = new Notification.Builder(ctx, KinnectService.CH_MSG)
        .setSmallIcon(KinnectService.res(ctx, "drawable", isChat ? "ic_web_message_circle" : "ic_web_bell"))
        .setSubText("Kinnect")
        .setContentTitle(title)
        .setContentText(body)
        .setStyle(new Notification.BigTextStyle().bigText(body))
        .setAutoCancel(true)
        .setPriority(Notification.PRIORITY_HIGH)
        .setColor(0xff7c5cff)
        .setShowWhen(true)
        .setCategory(isChat ? Notification.CATEGORY_MESSAGE : Notification.CATEGORY_SOCIAL)
        .setContentIntent(pi);

    NotificationManager nm = ctx.getSystemService(NotificationManager.class);
    if (nm != null) {
      nm.notify(notifId, builder.build());
    }
  }
}
