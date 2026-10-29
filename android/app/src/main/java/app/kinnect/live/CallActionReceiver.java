package app.kinnect.live;
import android.content.*;
import org.json.JSONObject;
/** Notification "decline" button and BOOT_COMPLETED: no UI needed. */
public final class CallActionReceiver extends BroadcastReceiver {
 @Override public void onReceive(Context c,Intent i){String a=i.getAction();
  if(Distribution.PLAY&&"stop-sync".equals(a)){c.getSharedPreferences("play_privacy",0).edit().putBoolean("background_messages",false).apply();KinnectService.stop(c);return;}
  if("decline".equals(a)){JSONObject m=KinnectService.pendingIncoming;if(m!=null)KinnectService.send(NativeSocket.json("type","call-decline","callId",m.optString("callId")));KinnectService.clearCall();return;}
  if(Intent.ACTION_BOOT_COMPLETED.equals(a)||Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)||"android.intent.action.QUICKBOOT_POWERON".equals(a)){NativeApi.shared.initialize(c,ServerConfig.DEFAULT_ORIGIN);if(!NativeApi.shared.cookieFor(ServerConfig.DEFAULT_ORIGIN).isEmpty())KinnectService.start(c);}}
}
