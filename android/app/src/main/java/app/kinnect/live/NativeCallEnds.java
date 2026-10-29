package app.kinnect.live;
import android.content.Context;import org.json.*;import java.util.*;
/** Remember a terminal action through brief network loss; never revive a locally ended call. */
final class NativeCallEnds {
 private static final Map<String,JSONObject> ended=new LinkedHashMap<>();private static Context context;
 static synchronized void initialize(Context c){context=c.getApplicationContext();if(!ended.isEmpty())return;try{JSONArray rows=new JSONArray(context.getSharedPreferences("call_terminal",0).getString("pending","[]"));for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i);ended.put(key(row.getJSONObject("payload")),row);}}catch(Exception ignored){}clean();}
 private static String scope(){return Integer.toHexString(NativeApi.shared.cookieFor(ServerConfig.DEFAULT_ORIGIN).hashCode());}
 private static String key(JSONObject m){return m.optString("callId",m.optString("requestId"));}
 private static void save(){if(context!=null)context.getSharedPreferences("call_terminal",0).edit().putString("pending",new JSONArray(ended.values()).toString()).apply();}
 private static void clean(){long now=System.currentTimeMillis();Iterator<JSONObject> iterator=ended.values().iterator();while(iterator.hasNext())if(iterator.next().optLong("until")<=now)iterator.remove();}
 static synchronized void mark(JSONObject message){clean();String key=key(message);if(key.isEmpty())return;ended.put(key,NativeSocket.json("payload",message,"until",System.currentTimeMillis()+60000,"scope",scope()));while(ended.size()>24)ended.remove(ended.keySet().iterator().next());save();}
 static synchronized boolean contains(String id){if(id==null||id.isEmpty())return false;clean();for(JSONObject row:ended.values())if(row.optString("scope").equals(scope())){JSONObject m=row.optJSONObject("payload");if(m!=null&&(id.equals(m.optString("callId"))||id.equals(m.optString("requestId"))))return true;}return false;}
 static synchronized java.util.List<JSONObject> pending(){clean();List<JSONObject> rows=new ArrayList<>();for(JSONObject row:ended.values())if(!row.optBoolean("ack")&&row.optString("scope").equals(scope()))rows.add(row.optJSONObject("payload"));return rows;}
 static synchronized void acknowledged(JSONObject m){String id=m.optString("callId"),request=m.optString("requestId");Iterator<JSONObject> iterator=ended.values().iterator();while(iterator.hasNext()){JSONObject row=iterator.next(),payload=row.optJSONObject("payload");if(payload!=null&&(id.equals(payload.optString("callId"))&&!id.isEmpty()||request.equals(payload.optString("requestId"))&&!request.isEmpty())){ // Keep a local tombstone while dropping the pending delivery.
 try{row.put("ack",true);}catch(JSONException ignored){}}}save();}
 static synchronized void clear(){ended.clear();save();}
}
