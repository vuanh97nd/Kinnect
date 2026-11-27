package app.kinnect.live;
import android.content.*;
import android.os.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.json.JSONObject;
/** Handles incoming call notification "decline" action without launching UI. */
public final class CallActionReceiver extends BroadcastReceiver {
 @Override public void onReceive(Context c,Intent i){if(i==null)return;
  if("decline".equals(i.getAction())){
   String token=i.getStringExtra("token");
   if(token==null||(!KinnectService.ACTION_TOKEN.equals(token)&&!KinnectService.actionToken(c).equals(token)))return;
   JSONObject m=KinnectService.pendingIncoming;
   String callId=m!=null?m.optString("callId"):i.getStringExtra("callId");
   KinnectService.cancelCallNotification(c);
   KinnectService.clearCall(c);
   if(callId!=null&&!callId.isEmpty()){
    final PendingResult pending=goAsync();
    final AtomicBoolean done=new AtomicBoolean(false);
    final Runnable finishOnce=()->{if(done.compareAndSet(false,true))try{pending.finish();}catch(Exception ignored){}};
    new Handler(Looper.getMainLooper()).postDelayed(finishOnce,7000);
    KinnectService.declineCall(c,callId,finishOnce);
   }
  }
 }
}
