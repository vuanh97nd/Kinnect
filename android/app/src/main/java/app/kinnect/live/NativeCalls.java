package app.kinnect.live;
import android.Manifest;
import android.app.*;
import android.content.pm.PackageManager;
import android.os.*;
import android.view.*;
import android.widget.*;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.*;
import org.json.*;
import org.webrtc.SurfaceViewRenderer;
/** Foreground audio/video calls, interoperable with the web signaling protocol. */
final class NativeCalls implements NativeSocket.Events {
 private final Activity activity;private final Handler handler=new Handler(Looper.getMainLooper());
 private Dialog dialog;private LinearLayout root;private TextView status;private SurfaceViewRenderer local,remote;private NativeRtc rtc;
 private String id,requestId,mode;private boolean incoming,ready,accepted,closed;private Runnable permission;
 private android.media.AudioManager audio;private int previousMode;private boolean previousSpeaker;
 private android.media.MediaPlayer ring;
 NativeCalls(Activity activity,String origin){this.activity=activity;KinnectService.start(activity);KinnectService.listen(this);handler.post(this::checkPending);}
 void checkPending(){JSONObject m=KinnectService.pendingIncoming;if(m==null)return;if(dialog==null)event(m);if(KinnectService.pendingAccept&&dialog!=null&&incoming&&!accepted&&id!=null&&id.equals(m.optString("callId"))){KinnectService.pendingAccept=false;accept();}}
 private void accept(){stopRing();if(incomingBar!=null)incomingBar.setVisibility(View.GONE);if(controls!=null)controls.setVisibility(View.VISIBLE);if(status!=null)status.setText(I18n.t("Đang kết nối…"));KinnectService.cancelCallNotification(activity);permissions(()->media(()->{accepted=true;KinnectService.pendingIncoming=null;KinnectService.send(NativeSocket.json("type","call-accept","callId",id));status.setText(I18n.t("Đang kết nối…"));}));}
 private void startRing(){if(!KinnectService.appVisible)return;try{ring=android.media.MediaPlayer.create(activity,KinnectService.res(activity,"raw","kinnect_ring"));ring.setLooping(true);ring.start();}catch(RuntimeException ignored){}android.os.Vibrator v=(android.os.Vibrator)activity.getSystemService(Activity.VIBRATOR_SERVICE);if(v!=null)v.vibrate(android.os.VibrationEffect.createWaveform(KinnectService.CALL_VIBRATE,1));}
 private void stopRing(){if(ring!=null){try{ring.stop();}catch(RuntimeException ignored){}ring.release();ring=null;}android.os.Vibrator v=(android.os.Vibrator)activity.getSystemService(Activity.VIBRATOR_SERVICE);if(v!=null)v.cancel();}
 private TextView text(String value,int size){TextView v=new TextView(activity);v.setText(value);v.setTextColor(0xfff6f0ff);v.setTextSize(size);v.setPadding(16,12,16,12);return v;}
 private Button button(String value,Runnable task){Button b=new Button(activity);b.setText(value);b.setAllCaps(false);b.setOnClickListener(v->task.run());return b;}
 private void toast(String value){Toast.makeText(activity,value,Toast.LENGTH_LONG).show();}
 void start(JSONObject person,String mode){if(!ready){toast(I18n.t("Đang kết nối dịch vụ cuộc gọi. Thử lại sau giây lát."));return;}if(dialog!=null){toast(I18n.t("Bạn đang có cuộc gọi."));return;}this.mode=mode;incoming=false;open(person);permissions(()->media(()->{requestId=java.util.UUID.randomUUID().toString();KinnectService.send(NativeSocket.json("type","call-start","to",person.optString("id"),"mode",mode,"requestId",requestId));status.setText(I18n.t("Đang gọi…"));}));}
 private View controls,incomingBar;private long connectedAt;private boolean speaker;
 private int dp(float v){return Math.round(v*activity.getResources().getDisplayMetrics().density);}
 private GradientDrawable oval(int color){GradientDrawable g=new GradientDrawable();g.setShape(GradientDrawable.OVAL);g.setColor(color);return g;}
 private ImageView glyph(String name,int color){ImageView i=new ImageView(activity);i.setImageDrawable(WebIcons.load(activity,name));i.setColorFilter(color);return i;}
 /** Round control with caption, styled like a phone dialer. */
 private LinearLayout control(String icon,String label,int size,int fill,Runnable task){LinearLayout c=new LinearLayout(activity);c.setOrientation(1);c.setGravity(Gravity.CENTER_HORIZONTAL);FrameLayout b=new FrameLayout(activity);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x55ffffff),oval(fill),null));b.addView(glyph(icon,0xffffffff),new FrameLayout.LayoutParams(dp(size*.42f),dp(size*.42f),Gravity.CENTER));b.setOnClickListener(v->task.run());c.addView(b,new LinearLayout.LayoutParams(dp(size),dp(size)));TextView t=new TextView(activity);t.setText(label);t.setTextSize(12);t.setTextColor(0xe6ffffff);t.setPadding(0,dp(10),0,0);t.setSingleLine(true);t.setGravity(Gravity.CENTER);c.addView(t,new LinearLayout.LayoutParams(-2,-2));return c;}
 /** Highlighted = solid white with dark glyph (speaker on, mic muted, camera off). */
 private void toggle(LinearLayout c,boolean on){FrameLayout b=(FrameLayout)c.getChildAt(0);b.setBackground(new RippleDrawable(ColorStateList.valueOf(0x55888888),oval(on?0xffffffff:0x33ffffff),null));((ImageView)b.getChildAt(0)).setColorFilter(on?0xff1b1240:0xffffffff);}
 private void open(JSONObject person){String name=person==null?"Kinnect":person.optString("name","Kinnect");boolean video=!mode.equals("audio");
  dialog=new Dialog(activity,android.R.style.Theme_Material_NoActionBar_Fullscreen);Window w=dialog.getWindow();w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON|WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED|WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);w.setNavigationBarColor(0xff000000);
  FrameLayout stage=new FrameLayout(activity);stage.setBackground(video?new ColorDrawable(0xff0b0b10):new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0xff2a1a63,0xff1b1240,0xff0d0a1f}));
  remote=new SurfaceViewRenderer(activity);local=new SurfaceViewRenderer(activity);remote.setZOrderMediaOverlay(true);
  LinearLayout info=new LinearLayout(activity);info.setOrientation(1);info.setGravity(Gravity.CENTER_HORIZONTAL);
  TextView title=new TextView(activity);title.setText(name);title.setTextColor(0xffffffff);title.setTypeface(Typeface.DEFAULT_BOLD);title.setGravity(Gravity.CENTER);title.setSingleLine(true);title.setEllipsize(android.text.TextUtils.TruncateAt.END);
  status=new TextView(activity);status.setText(incoming?(video?I18n.t("Cuộc gọi video đến…"):I18n.t("Cuộc gọi thoại đến…")):I18n.t("Đang chuẩn bị…"));status.setTextColor(0xffd8d0ff);status.setTextSize(15);status.setGravity(Gravity.CENTER);status.setPadding(0,dp(6),0,0);
  if(video){stage.addView(remote,new FrameLayout.LayoutParams(-1,-1));
   View top=new View(activity);top.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0xcc000000,0x00000000}));stage.addView(top,new FrameLayout.LayoutParams(-1,dp(170),Gravity.TOP));
   View bottom=new View(activity);bottom.setBackground(new GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP,new int[]{0xdd000000,0x00000000}));stage.addView(bottom,new FrameLayout.LayoutParams(-1,dp(300),Gravity.BOTTOM));
   FrameLayout pip=new FrameLayout(activity);GradientDrawable pg=new GradientDrawable();pg.setCornerRadius(dp(16));pg.setColor(0xff1d1b2a);pg.setStroke(dp(1),0x55ffffff);pip.setBackground(pg);pip.setClipToOutline(true);pip.setElevation(dp(6));local.setZOrderMediaOverlay(true);pip.addView(local,new FrameLayout.LayoutParams(-1,-1));
   FrameLayout.LayoutParams pp=new FrameLayout.LayoutParams(dp(108),dp(156),Gravity.TOP|Gravity.END);pp.setMargins(0,dp(110),dp(16),0);stage.addView(pip,pp);
   title.setTextSize(22);info.addView(title);info.addView(status);FrameLayout.LayoutParams ip=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);ip.setMargins(dp(24),dp(44),dp(24),0);stage.addView(info,ip);}
  else{FrameLayout halo=new FrameLayout(activity);int size=dp(210);
   for(int k=0;k<3;k++){View ring=new View(activity);ring.setBackground(oval(0x337c5cff));halo.addView(ring,new FrameLayout.LayoutParams(size,size,Gravity.CENTER));for(android.animation.ObjectAnimator o:new android.animation.ObjectAnimator[]{android.animation.ObjectAnimator.ofFloat(ring,"scaleX",.55f,1f),android.animation.ObjectAnimator.ofFloat(ring,"scaleY",.55f,1f),android.animation.ObjectAnimator.ofFloat(ring,"alpha",.9f,0f)}){o.setRepeatCount(android.animation.ValueAnimator.INFINITE);o.setDuration(1800);o.setStartDelay(k*600L);o.start();}}
   TextView av=new TextView(activity);av.setText(name.isEmpty()?"K":name.substring(0,1).toUpperCase());av.setTextSize(46);av.setTextColor(0xffffffff);av.setTypeface(Typeface.DEFAULT_BOLD);av.setGravity(Gravity.CENTER);GradientDrawable ag=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{0xff9b7bff,0xff6a3df0});ag.setShape(GradientDrawable.OVAL);ag.setStroke(dp(3),0x66ffffff);av.setBackground(ag);halo.addView(av,new FrameLayout.LayoutParams(dp(112),dp(112),Gravity.CENTER));
   info.addView(halo,new LinearLayout.LayoutParams(size,size));title.setTextSize(28);title.setPadding(0,dp(18),0,0);info.addView(title);info.addView(status);
   FrameLayout.LayoutParams ip=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);ip.setMargins(dp(24),dp(110),dp(24),0);stage.addView(info,ip);
   TextView brand=new TextView(activity);brand.setText("KINNECT");brand.setLetterSpacing(.3f);brand.setTextSize(12);brand.setTextColor(0xffb9a8ff);brand.setTypeface(Typeface.DEFAULT_BOLD);FrameLayout.LayoutParams bp=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);bp.topMargin=dp(52);stage.addView(brand,bp);}
  final boolean[] mic={true},cam={true};
  LinearLayout bar=new LinearLayout(activity);bar.setOrientation(1);bar.setGravity(Gravity.CENTER_HORIZONTAL);
  LinearLayout row=new LinearLayout(activity);row.setGravity(Gravity.CENTER);
  final LinearLayout[] spk=new LinearLayout[1],micB=new LinearLayout[1],camB=new LinearLayout[1];
  speaker=video;spk[0]=control("volume_2","Loa ngoài",video?56:62,0x33ffffff,()->{speaker=!speaker;if(audio!=null)audio.setSpeakerphoneOn(speaker);toggle(spk[0],speaker);});toggle(spk[0],speaker);
  micB[0]=control("mic","Micro",video?56:62,0x33ffffff,()->{if(rtc==null)return;mic[0]=!mic[0];rtc.microphone(mic[0]);toggle(micB[0],!mic[0]);});
  LinearLayout endB=control("phone_off","Kết thúc",68,0xffff3b4f,()->end(true));
  if(video){camB[0]=control("video","Camera",56,0x33ffffff,()->{if(rtc==null)return;cam[0]=!cam[0];rtc.camera(cam[0]);toggle(camB[0],!cam[0]);});
   row.addView(control("switch_camera","Đổi camera",56,0x33ffffff,()->{if(rtc!=null)rtc.flip();}),new LinearLayout.LayoutParams(0,-2,1));row.addView(camB[0],new LinearLayout.LayoutParams(0,-2,1));row.addView(micB[0],new LinearLayout.LayoutParams(0,-2,1));row.addView(spk[0],new LinearLayout.LayoutParams(0,-2,1));
   bar.addView(row,new LinearLayout.LayoutParams(-1,-2));LinearLayout.LayoutParams ep=new LinearLayout.LayoutParams(-2,-2);ep.topMargin=dp(26);bar.addView(endB,ep);}
  else{row.setGravity(Gravity.CENTER_VERTICAL);row.addView(spk[0],new LinearLayout.LayoutParams(0,-2,1));row.addView(endB,new LinearLayout.LayoutParams(0,-2,1));row.addView(micB[0],new LinearLayout.LayoutParams(0,-2,1));bar.addView(row,new LinearLayout.LayoutParams(-1,-2));}
  controls=bar;
  LinearLayout inc=new LinearLayout(activity);inc.setGravity(Gravity.CENTER);
  inc.addView(control("phone_off","Từ chối",74,0xffff3b4f,()->end(true)),new LinearLayout.LayoutParams(0,-2,1));
  LinearLayout ok=control(video?"video":"phone","Trả lời",74,0xff22c55e,this::accept);inc.addView(ok,new LinearLayout.LayoutParams(0,-2,1));
  
  incomingBar=inc;
  FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM);cp.setMargins(dp(16),0,dp(16),dp(72));
  stage.addView(bar,cp);stage.addView(inc,new FrameLayout.LayoutParams(cp));bar.setElevation(dp(24));inc.setElevation(dp(24));
  bar.setVisibility(incoming?View.GONE:View.VISIBLE);inc.setVisibility(incoming?View.VISIBLE:View.GONE);
  stage.setOnApplyWindowInsetsListener((v,i)->{((FrameLayout.LayoutParams)bar.getLayoutParams()).bottomMargin=i.getSystemWindowInsetBottom()+dp(56);((FrameLayout.LayoutParams)inc.getLayoutParams()).bottomMargin=i.getSystemWindowInsetBottom()+dp(72);bar.requestLayout();inc.requestLayout();return i;});
  if(video)stage.setOnClickListener(v->{if(accepted&&controls!=null)controls.animate().alpha(controls.getAlpha()>.5f?0f:1f).setDuration(180).start();});
  dialog.setContentView(stage);dialog.setOnCancelListener(d->end(true));dialog.show();if(incoming)startRing();
  handler.postDelayed(()->{if(dialog!=null&&!accepted){toast(I18n.t("Cuộc gọi quá thời gian chờ."));end(true);}},50000);}
 private final Runnable clock=new Runnable(){public void run(){if(dialog==null||connectedAt==0)return;long s=(System.currentTimeMillis()-connectedAt)/1000;status.setText(String.format(java.util.Locale.ROOT,"%02d:%02d",s/60,s%60));handler.postDelayed(this,1000);}};
 private void showStatus(String value){if(status==null)return;if("Đã kết nối".equals(value)){if(connectedAt==0){connectedAt=System.currentTimeMillis();handler.post(clock);}return;}if(connectedAt==0)status.setText(value);}
 private void permissions(Runnable task){boolean camera=mode.equals("audio")||activity.checkSelfPermission(Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED;boolean mic=activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED;if(camera&&mic){task.run();return;}permission=task;activity.requestPermissions(mode.equals("audio")?new String[]{Manifest.permission.RECORD_AUDIO}:new String[]{Manifest.permission.RECORD_AUDIO,Manifest.permission.CAMERA},901);}
 void permissionsResult(int[] grants){Runnable task=permission;permission=null;for(int grant:grants)if(grant!=PackageManager.PERMISSION_GRANTED){toast(I18n.t("Cần cấp quyền để bắt đầu cuộc gọi."));end(true);return;}if(grants.length>0&&task!=null&&dialog!=null)task.run();else end(true);}
 private void media(Runnable done){if(rtc!=null){done.run();return;}final Dialog generation=dialog;NativeApi.shared.call("GET","/api/call-config",null,(config,error,code)->{if(dialog!=generation||closed||dialog==null)return;if(error!=null){toast(error);end(true);return;}try{rtc=new NativeRtc(activity,config,local,remote,new NativeRtc.Events(){public void status(String value){showStatus(value);}public void signal(String peer,JSONObject payload){try{payload.put("type","call-signal");payload.put("callId",id);KinnectService.send(payload);}catch(JSONException ignored){}}});rtc.media(activity,!mode.equals("audio"));audio=(android.media.AudioManager)activity.getSystemService(Activity.AUDIO_SERVICE);previousMode=audio.getMode();previousSpeaker=audio.isSpeakerphoneOn();audio.setMode(android.media.AudioManager.MODE_IN_COMMUNICATION);audio.setSpeakerphoneOn(!mode.equals("audio"));done.run();}catch(Exception e){toast(I18n.t("Không mở được camera/micro."));end(true);}});}
 public void event(JSONObject m){String type=m.optString("type");if(type.equals("welcome")){ready=true;return;}if(type.equals("call-incoming")){if(dialog!=null){KinnectService.send(NativeSocket.json("type","call-decline","callId",m.optString("callId")));return;}id=m.optString("callId");mode=m.optString("mode","video");incoming=true;accepted=false;open(m.optJSONObject("from"));return;}if(type.equals("call-ringing")){if(dialog!=null&&m.optString("requestId").equals(requestId)){id=m.optString("callId");status.setText(I18n.t("Đang đổ chuông…"));}else KinnectService.send(NativeSocket.json("type","call-end","callId",m.optString("callId")));return;}if(type.equals("call-ended")&&dialog!=null&&((id!=null&&id.equals(m.optString("callId")))||(requestId!=null&&requestId.equals(m.optString("requestId"))))){String reason=m.optString("reason");toast(reason.equals("busy")?I18n.t("Người này đang bận."):reason.equals("unavailable")?I18n.t("Người này chưa sẵn sàng nhận cuộc gọi."):I18n.t("Cuộc gọi đã kết thúc."));end(false);return;}if(dialog==null||id==null||!id.equals(m.optString("callId")))return;if(type.equals("call-accepted")&&rtc!=null){accepted=true;status.setText(I18n.t("Đang kết nối…"));if(!incoming)rtc.offer("call");handler.postDelayed(()->{if(dialog!=null&&rtc!=null&&status.getText().toString().equals("Đang kết nối…")){toast(I18n.t("Chưa kết nối được media. Vui lòng thử mạng khác."));end(true);}},35000);}if(type.equals("call-signal")&&rtc!=null)rtc.signal("call",m);}
 public void closed(){ready=false;if(dialog!=null){toast(I18n.t("Mất kết nối cuộc gọi."));end(false);}}
 private void end(boolean notify){stopRing();if(incoming&&id!=null&&KinnectService.pendingIncoming!=null&&id.equals(KinnectService.pendingIncoming.optString("callId")))KinnectService.clearCall();if(notify&&id!=null)KinnectService.send(NativeSocket.json("type",incoming&&!accepted?"call-decline":"call-end","callId",id));handler.removeCallbacksAndMessages(null);permission=null;Dialog old=dialog;dialog=null;if(old!=null)old.dismiss();if(rtc!=null){rtc.close();rtc=null;}if(audio!=null){audio.setMode(previousMode);audio.setSpeakerphoneOn(previousSpeaker);audio=null;}id=null;requestId=null;accepted=false;connectedAt=0;controls=null;incomingBar=null;}
 void close(){closed=true;JSONObject ringing=dialog!=null&&incoming&&!accepted?KinnectService.pendingIncoming:null;end(ringing==null);if(ringing!=null){KinnectService.pendingIncoming=ringing;KinnectService.ringAgain();}KinnectService.unlisten(this);}
}
