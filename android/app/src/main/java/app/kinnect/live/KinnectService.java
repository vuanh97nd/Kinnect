package app.kinnect.live;
import android.app.*;
import android.content.*;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.*;
import org.json.*;
import java.util.*;
/** Keeps one authenticated socket alive while active; FCM handles background/closed wakeups with zero pinned notifications. */
public final class KinnectService extends Service implements NativeSocket.Events {
 static final String CH_CALL="kinnect_calls_v2",CH_MSG="kinnect_messages_v1";
 static final int ID_CALL=2;
 static final long[] CALL_VIBRATE={0,700,350,700,350,1200,900},MSG_VIBRATE={0,90,80,160};
 static final String ACTION_TOKEN=UUID.randomUUID().toString();
 private static KinnectService instance;private static final List<NativeSocket.Events> listeners=new java.util.concurrent.CopyOnWriteArrayList<>();
 static JSONObject pendingIncoming;static boolean pendingAccept;static volatile boolean appVisible;
 private NativeSocket socket;private boolean ready;private final Handler main=new Handler(Looper.getMainLooper());private long retry=1000;private android.net.ConnectivityManager.NetworkCallback networkCallback;
 static void start(Context c){if(c==null)return;try{c.startService(new Intent(c,KinnectService.class));}catch(RuntimeException ignored){}}
 static void stop(Context c){if(c==null)return;if(NativeApi.shared.cookieFor(NativeApi.shared.origin()).isEmpty())NativeCallEnds.clear();try{c.stopService(new Intent(c,KinnectService.class));}catch(RuntimeException ignored){}}
 static void listen(NativeSocket.Events e){if(!listeners.contains(e))listeners.add(e);if(instance!=null&&instance.ready)e.event(NativeSocket.json("type","welcome"));}
 static void unlisten(NativeSocket.Events e){listeners.remove(e);}
 static void send(JSONObject m){String type=m.optString("type");boolean terminal=type.equals("call-end")||type.equals("call-decline")||type.equals("call-cancel");if(terminal)NativeCallEnds.mark(m);if(instance!=null&&instance.socket!=null&&(!terminal||instance.ready))instance.socket.send(m);}
 static int res(Context c,String type,String name){return c.getResources().getIdentifier(name,type,c.getPackageName());}
 static Uri sound(Context c,String name){return Uri.parse("android.resource://"+c.getPackageName()+"/raw/"+name);}
 static void channels(Context c){NotificationManager nm=c.getSystemService(NotificationManager.class);if(nm==null)return;
  NotificationChannel call=new NotificationChannel(CH_CALL,I18n.t("Cuộc gọi đến"),NotificationManager.IMPORTANCE_HIGH);call.setDescription(I18n.t("Cuộc gọi thoại và video Kinnect"));call.setSound(sound(c,"kinnect_ring"),new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());call.enableVibration(true);call.setVibrationPattern(CALL_VIBRATE);call.enableLights(true);call.setLightColor(0xff7c5cff);call.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);call.setBypassDnd(!Distribution.PLAY);nm.createNotificationChannel(call);
  NotificationChannel msg=new NotificationChannel(CH_MSG,I18n.t("Tin nhắn và thông báo"),NotificationManager.IMPORTANCE_HIGH);msg.setSound(sound(c,"kinnect_notify"),new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());msg.enableVibration(true);msg.setVibrationPattern(MSG_VIBRATE);msg.enableLights(true);msg.setLightColor(0xff7c5cff);msg.setShowBadge(true);nm.createNotificationChannel(msg);
  try{nm.cancel(1);nm.deleteNotificationChannel("kinnect_background_v1");}catch(RuntimeException ignored){}}
 @Override public void onCreate(){super.onCreate();instance=this;channels(this);NativeApi.shared.initialize(this,ServerConfig.DEFAULT_ORIGIN);NativeCallEnds.initialize(this);main.postDelayed(poll,45000);try{networkCallback=new android.net.ConnectivityManager.NetworkCallback(){public void onAvailable(android.net.Network network){main.post(()->{if(instance==KinnectService.this&&!ready){if(socket!=null){socket.close();socket=null;}connect();}});}};getSystemService(android.net.ConnectivityManager.class).registerDefaultNetworkCallback(networkCallback);}catch(RuntimeException ignored){} }
 @Override public int onStartCommand(Intent intent,int flags,int id){
  if(NativeApi.shared.cookieFor(NativeApi.shared.origin()).isEmpty()){stopSelf();return START_NOT_STICKY;}
  KinnectFirebaseMessagingService.syncTokenWithServer(this);
  if(pendingIncoming!=null&&!appVisible)showIncomingCall(this,pendingIncoming);
  if(socket==null)connect();return START_NOT_STICKY;}
 private void connect(){socket=new NativeSocket(NativeApi.shared.origin(),this);}
 // Dự phòng khi socket lỡ sự kiện (mạng chập chờn, Doze): hỏi lại máy chủ mỗi 45 giây.
 private final Runnable poll=new Runnable(){public void run(){if(instance!=KinnectService.this)return;fetchNotifications();main.postDelayed(this,45000);}};
 @Override public void event(JSONObject m){String type=m.optString("type");
  if(type.equals("welcome")){ready=true;retry=1000;for(JSONObject terminal:NativeCallEnds.pending())socket.send(terminal);fetchNotifications();}
  if(type.equals("call-ended"))NativeCallEnds.acknowledged(m);
  if(type.equals("call-incoming")&&NativeCallEnds.contains(m.optString("callId")))return;
  if(type.equals("call-incoming")){pendingIncoming=m;pendingAccept=false;if(!appVisible)showIncomingCall(this,m);}
  if(type.equals("call-ended")&&pendingIncoming!=null&&pendingIncoming.optString("callId").equals(m.optString("callId")))clearCall();
  if(type.equals("call-accepted")&&pendingIncoming!=null&&pendingIncoming.optString("callId").equals(m.optString("callId"))){pendingIncoming=null;cancelCallNotification(this);}
  if(type.equals("notifications-changed")||type.equals("notification"))fetchNotifications();
  for(NativeSocket.Events e:new ArrayList<>(listeners))e.event(m);}
 @Override public void closed(){ready=false;if(socket!=null){NativeSocket s=socket;socket=null;s.close();}for(NativeSocket.Events e:new ArrayList<>(listeners))e.closed();main.postDelayed(()->{if(instance==this&&socket==null&&!NativeApi.shared.cookieFor(NativeApi.shared.origin()).isEmpty())connect();},retry);retry=Math.min(retry*2,4000);}
 static void ringAgain(){if(instance!=null&&pendingIncoming!=null&&!appVisible)showIncomingCall(instance,pendingIncoming);}
 static void clearCall(){pendingIncoming=null;pendingAccept=false;if(instance!=null)cancelCallNotification(instance);IncomingCallActivity.finishIfShowing();}
 static void cancelCallNotification(Context c){if(c==null)return;NotificationManager nm=c.getSystemService(NotificationManager.class);if(nm!=null)nm.cancel(ID_CALL);}
 /** Hiển thị thông báo cuộc gọi đến ưu tiên cao + tự bật màn hình toàn màn hình ngay cả khi app tắt hoặc màn hình khóa. */
 static void showIncomingCall(Context rawCtx,JSONObject m){if(rawCtx==null||m==null)return;Context c=rawCtx.getApplicationContext();channels(c);
  JSONObject from=m.optJSONObject("from");String name=from==null?"Kinnect":from.optString("name","Kinnect");boolean video=!"audio".equals(m.optString("mode"));
  Intent full=new Intent(c,IncomingCallActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_NO_USER_ACTION);
  PendingIntent fullPi=PendingIntent.getActivity(c,1,full,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
  PendingIntent accept=PendingIntent.getActivity(c,2,new Intent(c,IncomingCallActivity.class).setAction("accept").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
  PendingIntent decline=PendingIntent.getBroadcast(c,3,new Intent(c,CallActionReceiver.class).setAction("decline").putExtra("token",ACTION_TOKEN),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
  Notification.Builder b=new Notification.Builder(c,CH_CALL).setSmallIcon(video?res(c,"drawable","ic_web_video"):res(c,"drawable","ic_web_phone")).setContentTitle(name).setContentText(video?I18n.t("Cuộc gọi video đến"):I18n.t("Cuộc gọi thoại đến")).setCategory(Notification.CATEGORY_CALL).setPriority(Notification.PRIORITY_MAX).setOngoing(true).setAutoCancel(false).setColor(0xff7c5cff).setColorized(true).setFullScreenIntent(fullPi,true).setContentIntent(fullPi).setTimeoutAfter(50000).setVisibility(Notification.VISIBILITY_PUBLIC);
  if(Build.VERSION.SDK_INT>=31){b.setStyle(Notification.CallStyle.forIncomingCall(new Person.Builder().setName(name).setImportant(true).build(),decline,accept));}
  else{b.addAction(new Notification.Action.Builder(null,I18n.t("Từ chối"),decline).build());b.addAction(new Notification.Action.Builder(null,I18n.t("Trả lời"),accept).build());}
  Notification n=b.build();n.flags|=Notification.FLAG_INSISTENT;
  NotificationManager nm=c.getSystemService(NotificationManager.class);if(nm!=null)nm.notify(ID_CALL,n);
  wakeAndLaunch(c);}
 /** Bật sáng màn hình và mở màn hình cuộc gọi đến toàn màn hình, kể cả khi khóa máy hoặc đang ở app khác. */
 @SuppressWarnings("deprecation") private static void wakeAndLaunch(Context c){try{PowerManager pm=(PowerManager)c.getSystemService(POWER_SERVICE);if(pm!=null)pm.newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK|PowerManager.ACQUIRE_CAUSES_WAKEUP|PowerManager.ON_AFTER_RELEASE,"kinnect:call").acquire(15000);}catch(RuntimeException ignored){}try{c.startActivity(new Intent(c,IncomingCallActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_NO_USER_ACTION));}catch(RuntimeException ignored){}}
 private void fetchNotifications(){NativeApi.shared.call("GET","/api/notifications",null,(data,error,status)->{if(data==null)return;JSONArray rows=data.optJSONArray("notifications");SharedPreferences p=getSharedPreferences("native_notify",0);long last=p.getLong("last",0),max=last;
  if(last==0){for(int i=0;rows!=null&&i<rows.length();i++)max=Math.max(max,rows.optJSONObject(i).optLong("created"));p.edit().putLong("last",Math.max(max,1)).apply();return;}
  for(int i=0;rows!=null&&i<rows.length();i++){JSONObject n=rows.optJSONObject(i);long at=n.optLong("created");if(n.optInt("seen")!=0||at<=last)continue;max=Math.max(max,at);if(!n.optBoolean("muted"))post(n);}
  p.edit().putLong("last",max).apply();});}
 private void post(JSONObject n){JSONObject actor=n.optJSONObject("actor");String who=actor==null?"Kinnect":actor.optString("name","Kinnect");
  Intent open=new Intent(this,MainActivity.class).putExtra("notification",n.toString()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP);
  String kind=n.optString("kind"),preview=n.optString("preview","").trim();boolean chat=kind.contains("message");
  // Tin nhắn: gộp theo người gửi (như Messenger); còn lại: mỗi thông báo một popup.
  int id=100+((chat?"chat:"+(actor==null?"":actor.optString("id"))+(n.optString("kind").equals("group_message")?n.optString("ref"):""):n.optString("id")).hashCode()&0xffff);
  String line=chat?(preview.isEmpty()?text(kind):preview):text(kind)+(preview.isEmpty()?"":": “"+preview+"”");
  Notification.Builder b=new Notification.Builder(this,CH_MSG).setSmallIcon(res(this,"drawable",chat?"ic_web_message_circle":"ic_web_bell")).setSubText("Kinnect").setContentTitle(who).setContentText(line).setStyle(new Notification.BigTextStyle().bigText(line)).setAutoCancel(true).setPriority(Notification.PRIORITY_HIGH).setColor(0xff7c5cff).setWhen(n.optLong("created",System.currentTimeMillis())).setShowWhen(true).setVisibility(Notification.VISIBILITY_PRIVATE).setCategory(chat?Notification.CATEGORY_MESSAGE:Notification.CATEGORY_SOCIAL).setGroup(chat?"kinnect_chat":"kinnect_social").setContentIntent(PendingIntent.getActivity(this,id,open,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT));
  if(chat){android.app.Notification.MessagingStyle ms=new Notification.MessagingStyle(new Person.Builder().setName(I18n.t("Bạn")).build());Person from=new Person.Builder().setName(who).build();
   ms.addMessage(line,n.optLong("created",System.currentTimeMillis()),from);if("group_message".equals(kind))ms.setGroupConversation(true);b.setStyle(ms);}
  getSystemService(NotificationManager.class).notify(id,b.build());
  String avatar=actor==null?"":actor.optString("avatar","");
  if(avatar.startsWith("/api/users/"))NativeApi.shared.image(avatar,bytes->{if(bytes==null)return;try{android.graphics.Bitmap bitmap=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(bitmap!=null){android.graphics.Bitmap round=circle(bitmap);b.setLargeIcon(round);if(chat){android.app.Notification.MessagingStyle ms=new Notification.MessagingStyle(new Person.Builder().setName(I18n.t("Bạn")).build());Person from=new Person.Builder().setName(who).setIcon(android.graphics.drawable.Icon.createWithBitmap(round)).build();ms.addMessage(line,n.optLong("created",System.currentTimeMillis()),from);if("group_message".equals(kind))ms.setGroupConversation(true);b.setStyle(ms);}getSystemService(NotificationManager.class).notify(id,b.setOnlyAlertOnce(true).build());}}catch(RuntimeException ignored){}});}

 private static android.graphics.Bitmap circle(android.graphics.Bitmap src){int s=Math.min(src.getWidth(),src.getHeight());android.graphics.Bitmap out=android.graphics.Bitmap.createBitmap(s,s,android.graphics.Bitmap.Config.ARGB_8888);android.graphics.Canvas c=new android.graphics.Canvas(out);android.graphics.Paint p=new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);c.drawCircle(s/2f,s/2f,s/2f,p);p.setXfermode(new android.graphics.PorterDuffXfermode(android.graphics.PorterDuff.Mode.SRC_IN));c.drawBitmap(src,(s-src.getWidth())/2f,(s-src.getHeight())/2f,p);return out;}
 private static String text(String kind){switch(kind){case "message":return I18n.t("đã gửi cho bạn một tin nhắn");case "group_message":return I18n.t("đã nhắn trong nhóm");case "missed_call":return I18n.t("Cuộc gọi nhỡ");case "like":return I18n.t("đã thích bài viết của bạn");case "comment":return I18n.t("đã bình luận bài viết của bạn");case "comment_reply":return I18n.t("đã trả lời bình luận của bạn");case "short_like":return I18n.t("đã thích video của bạn");case "short_comment":return I18n.t("đã bình luận video của bạn");case "friend_request":return I18n.t("đã gửi lời mời kết bạn");case "friend_accept":case "friend_accepted":return I18n.t("đã chấp nhận lời mời kết bạn");case "follow":return I18n.t("đã bắt đầu theo dõi bạn");case "gift":return I18n.t("đã gửi quà cho bạn");case "private_request":return I18n.t("muốn xem ảnh riêng tư của bạn");case "private_granted":return I18n.t("đã cho bạn xem ảnh riêng tư");case "private_revoked":return I18n.t("đã thu hồi quyền xem ảnh riêng tư");default:return I18n.t("có thông báo mới");}}
 @Override public void onDestroy(){if(instance==this)instance=null;if(networkCallback!=null)try{getSystemService(android.net.ConnectivityManager.class).unregisterNetworkCallback(networkCallback);}catch(RuntimeException ignored){}main.removeCallbacksAndMessages(null);if(socket!=null){NativeSocket s=socket;socket=null;s.close();}super.onDestroy();}
 @Override public IBinder onBind(Intent i){return null;}
}
