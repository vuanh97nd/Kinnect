package app.kinnect.live;
import android.app.*;import android.widget.*;import org.json.*;
final class LiveGamePass {
 static void ensure(Activity a,Runnable ready){NativeApi.shared.initialize(a,ServerConfig.DEFAULT_ORIGIN);NativeApi.shared.call("GET","/api/store",null,(state,error,status)->{if(a.isFinishing()||a.isDestroyed())return;if(error!=null){Toast.makeText(a,I18n.t("Chưa kiểm tra được gói Live Game. Hãy thử lại."),Toast.LENGTH_SHORT).show();return;}if(state.optLong("liveGameUntil")>System.currentTimeMillis()){ready.run();return;}JSONArray plans=state.optJSONArray("packages");for(int i=0;plans!=null&&i<plans.length();i++){JSONObject p=plans.optJSONObject(i);if(p!=null&&p.optString("id").equals("live_game_30")){PackagePurchase.buy(a,p,state,null,ready);return;}}});}
}
