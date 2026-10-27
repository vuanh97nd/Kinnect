package app.kinnect.live;
import android.animation.*;
import android.app.*;
import android.content.Intent;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import org.json.JSONObject;
/** Full-screen incoming call over the lock screen, like a phone call. */
public final class IncomingCallActivity extends Activity {
 private static IncomingCallActivity showing;
 static void finishIfShowing(){if(showing!=null)showing.finish();}
 private int dp(float v){return Math.round(v*getResources().getDisplayMetrics().density);}
 @Override protected void onCreate(Bundle state){super.onCreate(state);
  if(Build.VERSION.SDK_INT>=27){setShowWhenLocked(true);setTurnScreenOn(true);}
  getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED|WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON|WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
  getWindow().setStatusBarColor(0xff1b1240);getWindow().setNavigationBarColor(0xff0d0a1f);
  JSONObject m=KinnectService.pendingIncoming;if(m==null){finish();return;}
  if("accept".equals(getIntent().getAction())){accept();return;}
  showing=this;build(m);}
 @Override protected void onNewIntent(Intent i){super.onNewIntent(i);if("accept".equals(i.getAction()))accept();}
 private void build(JSONObject m){JSONObject from=m.optJSONObject("from");String name=from==null?"Kinnect":from.optString("name","Kinnect");boolean video=!"audio".equals(m.optString("mode"));
  FrameLayout root=new FrameLayout(this);root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0xff2a1a63,0xff1b1240,0xff0d0a1f}));
  LinearLayout col=new LinearLayout(this);col.setOrientation(LinearLayout.VERTICAL);col.setGravity(Gravity.CENTER_HORIZONTAL);col.setPadding(dp(24),dp(56),dp(24),dp(48));
  root.setOnApplyWindowInsetsListener((v,i)->{col.setPadding(dp(24),i.getSystemWindowInsetTop()+dp(40),dp(24),i.getSystemWindowInsetBottom()+dp(40));return i;});
  TextView brand=text("KINNECT",13,0xffb9a8ff);brand.setLetterSpacing(.3f);brand.setTypeface(Typeface.DEFAULT_BOLD);col.addView(brand);
  TextView kind=text(video?"Cuộc gọi video đến…":"Cuộc gọi thoại đến…",16,0xffd8d0ff);kind.setPadding(0,dp(8),0,0);col.addView(kind);
  FrameLayout halo=new FrameLayout(this);int size=dp(220);
  for(int k=0;k<3;k++){View ring=new View(this);GradientDrawable g=new GradientDrawable();g.setShape(GradientDrawable.OVAL);g.setColor(0x337c5cff);ring.setBackground(g);halo.addView(ring,new FrameLayout.LayoutParams(size,size,Gravity.CENTER));
   ObjectAnimator sx=ObjectAnimator.ofFloat(ring,"scaleX",.55f,1f),sy=ObjectAnimator.ofFloat(ring,"scaleY",.55f,1f),a=ObjectAnimator.ofFloat(ring,"alpha",.9f,0f);
   for(ObjectAnimator o:new ObjectAnimator[]{sx,sy,a}){o.setRepeatCount(ValueAnimator.INFINITE);o.setDuration(1800);o.setStartDelay(k*600L);o.start();}}
  TextView avatar=text(name.isEmpty()?"K":name.substring(0,1).toUpperCase(),48,0xffffffff);avatar.setGravity(Gravity.CENTER);avatar.setTypeface(Typeface.DEFAULT_BOLD);
  GradientDrawable av=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{0xff9b7bff,0xff6a3df0});av.setShape(GradientDrawable.OVAL);av.setStroke(dp(3),0x66ffffff);avatar.setBackground(av);
  halo.addView(avatar,new FrameLayout.LayoutParams(dp(116),dp(116),Gravity.CENTER));
  LinearLayout.LayoutParams hp=new LinearLayout.LayoutParams(size,size);hp.topMargin=dp(48);col.addView(halo,hp);
  TextView who=text(name,30,0xffffffff);who.setTypeface(Typeface.DEFAULT_BOLD);who.setGravity(Gravity.CENTER);who.setPadding(0,dp(20),0,0);col.addView(who);
  col.addView(new View(this),new LinearLayout.LayoutParams(1,0,1));
  LinearLayout actions=new LinearLayout(this);actions.setGravity(Gravity.CENTER);actions.setClipChildren(false);actions.setClipToPadding(false);col.setClipChildren(false);
  actions.addView(action("Từ chối",0xffff4d5e,"phone_off","phone",true,this::decline),new LinearLayout.LayoutParams(0,-2,1));
  actions.addView(action(video?"Trả lời video":"Trả lời",0xff22c55e,video?"video":"phone",null,false,this::accept),new LinearLayout.LayoutParams(0,-2,1));
  col.addView(actions,new LinearLayout.LayoutParams(-1,-2));
  root.addView(col,new FrameLayout.LayoutParams(-1,-1));setContentView(root);}
 private TextView text(String v,float sp,int color){TextView t=new TextView(this);t.setText(v);t.setTextSize(sp);t.setTextColor(color);t.setGravity(Gravity.CENTER);t.setLayoutParams(new LinearLayout.LayoutParams(-1,-2));return t;}
 private View action(String label,int color,String icon,String fallback,boolean tilt,Runnable task){LinearLayout c=new LinearLayout(this);c.setOrientation(LinearLayout.VERTICAL);c.setGravity(Gravity.CENTER_HORIZONTAL);c.setClipChildren(false);c.setClipToPadding(false);c.setPadding(0,dp(16),0,0);
  FrameLayout b=new FrameLayout(this);GradientDrawable g=new GradientDrawable();g.setShape(GradientDrawable.OVAL);g.setColor(color);b.setBackground(new RippleDrawable(ColorStateList(),g,null));b.setElevation(dp(8));
  ImageView i=new ImageView(this);int id=WebIcons.resolve(this,icon);if(id==0&&fallback!=null)id=WebIcons.resolve(this,fallback);if(id!=0)i.setImageDrawable(getDrawable(id).mutate());i.setColorFilter(0xffffffff);if(tilt&&WebIcons.resolve(this,icon)==0)i.setRotation(135);
  b.addView(i,new FrameLayout.LayoutParams(dp(32),dp(32),Gravity.CENTER));b.setOnClickListener(v->task.run());
  if(!tilt){ObjectAnimator bounce=ObjectAnimator.ofFloat(b,"translationY",0,-dp(10),0);bounce.setDuration(900);bounce.setRepeatCount(ValueAnimator.INFINITE);bounce.setStartDelay(300);bounce.start();}
  c.addView(b,new LinearLayout.LayoutParams(dp(74),dp(74)));TextView t=text(label,14,0xffe9e4ff);t.setPadding(0,dp(10),0,0);c.addView(t,new LinearLayout.LayoutParams(-1,-2));return c;}
 private static android.content.res.ColorStateList ColorStateList(){return android.content.res.ColorStateList.valueOf(0x55ffffff);}
 private void decline(){JSONObject m=KinnectService.pendingIncoming;if(m!=null)KinnectService.send(NativeSocket.json("type","call-decline","callId",m.optString("callId")));KinnectService.clearCall();finish();}
 private void accept(){if(KinnectService.pendingIncoming==null){finish();return;}KinnectService.pendingAccept=true;KinnectService.cancelCallNotification(this);
  startActivity(new Intent(this,MainActivity.class).putExtra("accept_call",true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));finish();}
 @Override public void onBackPressed(){}
 @Override protected void onDestroy(){if(showing==this)showing=null;super.onDestroy();}
}
