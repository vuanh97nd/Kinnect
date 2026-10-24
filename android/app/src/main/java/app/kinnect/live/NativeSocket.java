package app.kinnect.live;
import android.os.*;
import java.util.concurrent.TimeUnit;
import okhttp3.*;
import org.json.*;
/** Authenticated native WebSocket. No browser or JavaScript runtime. */
public final class NativeSocket extends WebSocketListener {
 public interface Events { void event(JSONObject value); void closed(); }
 private final Events events; private final Handler main=new Handler(Looper.getMainLooper());
 private final OkHttpClient client=new OkHttpClient.Builder().pingInterval(25,TimeUnit.SECONDS).build();
 private WebSocket socket; private volatile boolean closed;
 public NativeSocket(String origin,Events events){this.events=events;socket=client.newWebSocket(new Request.Builder().url(origin.replaceFirst("https:","wss:")+"/").header("Origin",origin).header("Cookie",NativeApi.shared.cookieFor(origin)).build(),this);}
 public void send(JSONObject value){if(!closed&&socket!=null)socket.send(value.toString());}
 @Override public void onMessage(WebSocket ws,String text){try{JSONObject value=new JSONObject(text);main.post(()->{if(!closed)events.event(value);});}catch(JSONException ignored){}}
 @Override public void onFailure(WebSocket ws,Throwable error,Response response){main.post(()->{if(!closed)events.closed();});}
 @Override public void onClosed(WebSocket ws,int code,String reason){main.post(()->{if(!closed)events.closed();});}
 public void close(){closed=true;if(socket!=null)socket.close(1000,"Leaving");client.dispatcher().executorService().shutdown();client.connectionPool().evictAll();}
 public static JSONObject json(Object... values){JSONObject out=new JSONObject();try{for(int i=0;i<values.length;i+=2)out.put(values[i].toString(),values[i+1]);}catch(JSONException e){throw new IllegalArgumentException(e);}return out;}
}
