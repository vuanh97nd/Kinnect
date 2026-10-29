package app.kinnect.live;
import android.app.*;import android.content.*;import android.content.pm.ServiceInfo;import android.os.*;

/** Foreground lifetime for screen sharing; never restarts or reuses a projection token. */
public final class LiveGameService extends Service {
 static final String STOP="live.game.stop",PAUSE="live.game.pause",MIC="live.game.mic";
 interface Controls{void stop();void pause();void mic();}
 private Controls controls;private boolean paused,muted;
 final class SessionBinder extends Binder{LiveGameService service(){return LiveGameService.this;}}
 private final SessionBinder binder=new SessionBinder();
 public IBinder onBind(Intent intent){return binder;}
 public void onCreate(){super.onCreate();NotificationManager manager=getSystemService(NotificationManager.class);manager.createNotificationChannel(new NotificationChannel("live_game","Kinnect Live",NotificationManager.IMPORTANCE_LOW));}
 void attach(Controls value){controls=value;refresh();}
 void flags(boolean pause,boolean mute){paused=pause;muted=mute;refresh();}
 private PendingIntent action(String type,int id){return PendingIntent.getService(this,id,new Intent(this,LiveGameService.class).setAction(type),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);}
 private void refresh(){Intent open=new Intent(this,LiveActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP|Intent.FLAG_ACTIVITY_CLEAR_TOP);PendingIntent content=PendingIntent.getActivity(this,802,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);Notification notification=new Notification.Builder(this,"live_game").setSmallIcon(android.R.drawable.presence_video_online).setContentTitle(I18n.t("Kinnect · Chơi game trực tiếp")).setContentText(I18n.t(paused?"Đã tạm che màn hình":"Đang chia sẻ màn hình · Chạm để về phòng Live")).setContentIntent(content).setOngoing(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE).addAction(new Notification.Action.Builder(null,I18n.t(muted?"Bật mic":"Tắt mic"),action(MIC,803)).build()).addAction(new Notification.Action.Builder(null,I18n.t(paused?"Tiếp tục":"Tạm che"),action(PAUSE,804)).build()).addAction(new Notification.Action.Builder(null,I18n.t("Kết thúc"),action(STOP,805)).build()).build();int type=ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION;if(Build.VERSION.SDK_INT>=30)type|=ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE;if(Build.VERSION.SDK_INT>=29)startForeground(802,notification,type);else startForeground(802,notification);}
 public int onStartCommand(Intent intent,int flags,int id){if(controls==null){stopSelf();return START_NOT_STICKY;}String action=intent==null?"":intent.getAction();if(STOP.equals(action))controls.stop();else if(PAUSE.equals(action))controls.pause();else if(MIC.equals(action))controls.mic();return START_NOT_STICKY;}
 void detach(){controls=null;stopForeground(true);stopSelf();}
 public void onTaskRemoved(Intent root){if(controls!=null)controls.stop();stopSelf();}
 public void onDestroy(){Controls c=controls;controls=null;if(c!=null)c.stop();super.onDestroy();}
}
