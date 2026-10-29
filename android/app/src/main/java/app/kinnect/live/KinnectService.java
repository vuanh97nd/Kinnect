package app.kinnect.live;
import android.app.*;
import android.content.*;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.*;
import org.json.*;
import java.util.*;
/** Keeps one authenticated socket alive in the background; posts Kinnect call/message notifications. */
public final class KinnectService extends Service implements NativeSocket.Events {
 static final String CH_CALL="kinnect_calls_v1",CH_MSG="kinnect_messages_v1",CH_BG="kinnect_background_v1";
 static final int ID_BG=1,ID_CALL=2;
 static final long[] CALL_VIBRATE={0,700,350,700,350,1200,900},MSG_VIBRATE={0,90,80,160};
 private static KinnectService instance;private static final List<NativeSocket.Events> listeners=new ArrayList<>();
 static JSONObject pendingIncoming;static boolean pendingAccept;static volatile boolean appVisible;
 private NativeSocket socket;private boolean ready;private final Handler main=new Handler(Looper.getMainLooper());private long retry=3000;
 static void start(Context c){try{Intent i=new Intent(c,KinnectService.class);if(Build.VERSION.SDK_INT>=26&&(!Distribution.PLAY||c.getSharedPreferences("play_privacy",0).getBoolean("background_messages",false)))c.startForegroundService(i);else c.startService(i);}catch(RuntimeException blocked){}}
 static void stop(Context c){c.stopService(new Intent(c,KinnectService.class));}
 static void listen(NativeSocket.Events e){if(!listeners.contains(e))listeners.add(e);if(instance!=null&&instance.ready)e.event(NativeSocket.json("type","welcome"));}
 static void unlisten(NativeSocket.Events e){listeners.remove(e);}
 static void send(JSONObject m){if(instance!=null&&instance.socket!=null)instance.socket.send(m);}
 static int res(Context c,String type,String name){return c.getResources().getIdentifier(name,type,c.getPackageName());}
 static Uri sound(Context c,String name){return Uri.parse("android.resource://"+c.getPackageName()+"/raw/"+name);}
 static void channels(Context c){NotificationManager nm=c.getSystemService(NotificationManager.class);
  NotificationChannel call=new NotificationChannel(CH_CALL,"Cuộc gọi đến",NotificationManager.IMPORTANCE_HIGH);call.setDescription("Cuộc gọi thoại và video Kinnect");call.setSound(sound(c,"kinnect_ring"),new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());call.enableVibration(true);call.setVibrationPattern(CALL_VIBRATE);call.enableLights(true);call.setLightColor(0xff7c5cff);call.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);call.setBypassDnd(!Distribution.PLAY);nm.createNotificationChannel(call);
  NotificationChannel msg=new NotificationChannel(CH_MSG,"Tin nhắn và thông báo",NotificationManager.IMPORTANCE_HIGH);msg.setSound(sound(c,"kinnect_notify"),new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());msg.enableVibration(true);msg.setVibrationPattern(MSG_VIBRATE);msg.enableLights(true);msg.setLightColor(0xff7c5cff);msg.setShowBadge(true);nm.createNotificationChannel(msg);
  NotificationChannel bg=new NotificationChannel(CH_BG,"Hoạt động nền",NotificationManager.IMPORTANCE_MIN);bg.setDescription("Giữ kết nối để nhận cuộc gọi và tin nhắn");bg.setShowBadge(false);bg.setSound(null,null);nm.createNotificationChannel(bg);}
 @Override public void onCreate(){super.onCreate();instance=this;channels(this);NativeApi.shared.initialize(this,ServerConfig.DEFAULT_ORIGIN);main.postDelayed(poll,45000);}
 @Override public int onStartCommand(Intent intent,int flags,int id){
  Intent open=new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
  Notification.Builder backgroundBuilder=new Notification.Builder(this,CH_BG).setSmallIcon(res(this,"drawable","ic_web_bell")).setContentTitle("Kinnect đang hoạt động").setContentText(Distribution.PLAY?"Đồng bộ tin nhắn giữa web và điện thoại":"Sẵn sàng nhận cuộc gọi và tin nhắn").setOngoing(true).setColor(0xff7c5cff).setContentIntent(PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_IMMUTABLE));
  if(Distribution.PLAY)backgroundBuilder.addAction(android.R.drawable.ic_media_pause,"Dừng đồng bộ",PendingIntent.getBroadcast(this,8,new Intent(this,CallActionReceiver.class).setAction("stop-sync"),PendingIntent.FLAG_IMMUTABLE));
  Notification n=backgroundBuilder.build();
  if(Distribution.PLAY&&!getSharedPreferences("play_privacy",0).getBoolean("background_messages",false)){if(socket==null)connect();return START_NOT_STICKY;}
  try{if(Build.VERSION.SDK_INT>=34)startForeground(ID_BG,n,android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING);else startForeground(ID_BG,n);}catch(RuntimeException blocked){stopSelf();return START_NOT_STICKY;}
  if(NativeApi.shared.cookieFor(ServerConfig.DEFAULT_ORIGIN).isEmpty()){stopSelf();return START_NOT_STICKY;}
  if(socket==null)connect();return START_STICKY;}
 private void connect(){socket=new NativeSocket(ServerConfig.DEFAULT_ORIGIN,this);}
 // Dự phòng khi socket lỡ sự kiện (mạng chập chờn, Doze): hỏi lại máy chủ mỗi 45 giây.
 private final Runnable poll=new Runnable(){public void run(){if(instance!=KinnectService.this)return;fetchNotifications();main.postDelayed(this,45000);}};
 @Override public void event(JSONObject m){String type=m.optString("type");
  if(type.equals("welcome")){ready=true;retry=3000;fetchNotifications();}
  if(type.equals("call-incoming")){pendingIncoming=m;pendingAccept=false;if(!appVisible)ringNotification(m);}
  if(type.equals("call-ended")&&pendingIncoming!=null&&pendingIncoming.optString("callId").equals(m.optString("callId")))clearCall();
  if(type.equals("call-accepted")&&pendingIncoming!=null&&pendingIncoming.optString("callId").equals(m.optString("callId"))){pendingIncoming=null;cancelCallNotification(this);}
  if(type.equals("notifications-changed"))fetchNotifications();
  for(NativeSocket.Events e:new ArrayList<>(listeners))e.event(m);}
 @Override public void closed(){ready=false;if(socket!=null){NativeSocket s=socket;socket=null;s.close();}for(NativeSocket.Events e:new ArrayList<>(listeners))e.closed();main.postDelayed(()->{if(instance==this&&socket==null&&!NativeApi.shared.cookieFor(ServerConfig.DEFAULT_ORIGIN).isEmpty())connect();},retry);retry=Math.min(retry*2,60000);}
 static void ringAgain(){if(instance!=null&&pendingIncoming!=null&&!appVisible)instance.ringNotification(pendingIncoming);}
 static void clearCall(){pendingIncoming=null;pendingAccept=false;if(instance!=null)cancelCallNotification(instance);IncomingCallActivity.finishIfShowing();}
 static void cancelCallNotification(Context c){c.getSystemService(NotificationManager.class).cancel(ID_CALL);}
 private void ringNotification(JSONObject m){JSONObject from=m.optJSONObject("from");String name=from==null?"Kinnect":from.optString("name","Kinnect");boolean video=!"audio".equals(m.optString("mode"));
  Intent full=new Intent(this,IncomingCallActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_NO_USER_ACTION);
  PendingIntent fullPi=PendingIntent.getActivity(this,1,full,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
  PendingIntent accept=PendingIntent.getActivity(this,2,new Intent(this,IncomingCallActivity.class).setAction("accept").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
  PendingIntent decline=PendingIntent.getBroadcast(this,3,new Intent(this,CallActionReceiver.class).setAction("decline"),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
  Notification.Builder b=new Notification.Builder(this,CH_CALL).setSmallIcon(video?res(this,"drawable","ic_web_video"):res(this,"drawable","ic_web_phone")).setContentTitle(name).setContentText(video?"Cuộc gọi video đến":"Cuộc gọi thoại đến").setCategory(Notification.CATEGORY_CALL).setOngoing(true).setAutoCancel(false).setColor(0xff7c5cff).setColorized(true).setFullScreenIntent(fullPi,true).setContentIntent(fullPi).setTimeoutAfter(50000).setVisibility(Notification.VISIBILITY_PUBLIC);
  if(Build.VERSION.SDK_INT>=31){b.setStyle(Notification.CallStyle.forIncomingCall(new Person.Builder().setName(name).setImportant(true).build(),decline,accept));}
  else{b.addAction(new Notification.Action.Builder(null,"Từ chối",decline).build());b.addAction(new Notification.Action.Builder(null,"Trả lời",accept).build());}
  Notification n=b.build();n.flags|=Notification.FLAG_INSISTENT;
  getSystemService(NotificationManager.class).notify(ID_CALL,n);wake();}
 /** Bật sáng màn hình khi có cuộc gọi, kể cả lúc máy đang tắt màn hình/khóa. */
 @SuppressWarnings("deprecation") private void wake(){PowerManager pm=(PowerManager)getSystemService(POWER_SERVICE);boolean asleep=!pm.isInteractive();try{pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK|PowerManager.ACQUIRE_CAUSES_WAKEUP|PowerManager.ON_AFTER_RELEASE,"kinnect:call").acquire(15000);}catch(RuntimeException ignored){}if(asleep)try{startActivity(new Intent(this,IncomingCallActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));}catch(RuntimeException ignored){}}
 private void fetchNotifications(){NativeApi.shared.call("GET","/api/notifications",null,(data,error,status)->{if(data==null)return;JSONArray rows=data.optJSONArray("notifications");SharedPreferences p=getSharedPreferences("native_notify",0);long last=p.getLong("last",0),max=last;
  if(last==0){for(int i=0;rows!=null&&i<rows.length();i++)max=Math.max(max,rows.optJSONObject(i).optLong("created"));p.edit().putLong("last",Math.max(max,1)).apply();return;}
  for(int i=0;rows!=null&&i<rows.length();i++){JSONObject n=rows.optJSONObject(i);long at=n.optLong("created");if(n.optInt("seen")!=0||at<=last)continue;max=Math.max(max,at);if(!n.optBoolean("muted"))post(n);}
  p.edit().putLong("last",max).apply();});}
 private void post(JSONObject n){JSONObject actor=n.optJSONObject("actor");String who=actor==null?"Kinnect":actor.optString("name","Kinnect");
  Intent open=new Intent(this,MainActivity.class).putExtra("notification",n.toString()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP);
  String kind=n.optString("kind"),preview=n.optString("preview","").trim();boolean chat=kind.contains("message");
  // Tin nhắn: gộp theo người gửi (như Messenger); còn lại: mỗi thông báo một popup.
  int id=100+((chat?"chat:"+n.optString("actor")+n.optString("ref"):n.optString("id")).hashCode()&0xffff);
  String line=chat?(preview.isEmpty()?text(kind):preview):text(kind)+(preview.isEmpty()?"":": “"+preview+"”");
  Notification.Builder b=new Notification.Builder(this,CH_MSG).setSmallIcon(res(this,"drawable",chat?"ic_web_message_circle":"ic_web_bell")).setContentTitle(who).setContentText(line).setStyle(new Notification.BigTextStyle().bigText(line)).setAutoCancel(true).setColor(0xff7c5cff).setWhen(n.optLong("created",System.currentTimeMillis())).setShowWhen(true).setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(chat?Notification.CATEGORY_MESSAGE:Notification.CATEGORY_SOCIAL).setGroup(chat?"kinnect_chat":"kinnect_social").setContentIntent(PendingIntent.getActivity(this,id,open,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT));
  if(chat){android.app.Notification.MessagingStyle ms=new Notification.MessagingStyle(new Person.Builder().setName("Bạn").build());Person from=new Person.Builder().setName(who).build();
   ms.addMessage(line,n.optLong("created",System.currentTimeMillis()),from);if("group_message".equals(kind))ms.setGroupConversation(true);b.setStyle(ms);}
  getSystemService(NotificationManager.class).notify(id,b.build());
  String avatar=actor==null?"":actor.optString("avatar","");
  if(!avatar.isEmpty())new Thread(()->{try{String u=avatar.startsWith("http")?avatar:ServerConfig.DEFAULT_ORIGIN+avatar;java.io.InputStream in=new java.net.URL(u).openStream();android.graphics.Bitmap bm=android.graphics.BitmapFactory.decodeStream(in);in.close();
   if(bm!=null){b.setLargeIcon(circle(bm));getSystemService(NotificationManager.class).notify(id,b.setOnlyAlertOnce(true).build());}}catch(Exception ignored){}}).start();}
 private static android.graphics.Bitmap circle(android.graphics.Bitmap src){int s=Math.min(src.getWidth(),src.getHeight());android.graphics.Bitmap out=android.graphics.Bitmap.createBitmap(s,s,android.graphics.Bitmap.Config.ARGB_8888);android.graphics.Canvas c=new android.graphics.Canvas(out);android.graphics.Paint p=new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);c.drawCircle(s/2f,s/2f,s/2f,p);p.setXfermode(new android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN));c.drawBitmap(src,(s-src.getWidth())/2f,(s-src.getHeight())/2f,p);return out;}
 private static String text(String kind){switch(kind){case "message":return "đã gửi cho bạn một tin nhắn";case "group_message":return "đã nhắn trong nhóm";case "missed_call":return "Cuộc gọi nhỡ";case "like":return "đã thích bài viết của bạn";case "comment":return "đã bình luận bài viết của bạn";case "comment_reply":return "đã trả lời bình luận của bạn";case "short_like":return "đã thích video của bạn";case "short_comment":return "đã bình luận video của bạn";case "friend_request":return "đã gửi lời mời kết bạn";case "friend_accept":case "friend_accepted":return "đã chấp nhận lời mời kết bạn";case "follow":return "đã bắt đầu theo dõi bạn";case "gift":return "đã gửi quà cho bạn";case "private_request":return "muốn xem ảnh riêng tư của bạn";case "private_granted":return "đã cho bạn xem ảnh riêng tư";case "private_revoked":return "đã thu hồi quyền xem ảnh riêng tư";default:return "có thông báo mới";}}
 @Override public void onDestroy(){if(instance==this)instance=null;main.removeCallbacksAndMessages(null);if(socket!=null){NativeSocket s=socket;socket=null;s.close();}super.onDestroy();}
 @Override public IBinder onBind(Intent i){return null;}
}
