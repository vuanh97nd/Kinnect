package app.kinnect.live;
import android.content.*;
import org.json.JSONObject;
/** Handles incoming call notification "decline" action without launching UI. */
public final class CallActionReceiver extends BroadcastReceiver {
 @Override public void onReceive(Context c,Intent i){if(i==null)return;
  if("decline".equals(i.getAction())){if(!KinnectService.ACTION_TOKEN.equals(i.getStringExtra("token")))return;JSONObject m=KinnectService.pendingIncoming;if(m!=null)KinnectService.send(NativeSocket.json("type","call-decline","callId",m.optString("callId")));KinnectService.clearCall();}
 }
}
