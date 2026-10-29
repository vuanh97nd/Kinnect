package app.kinnect.audit;
import android.app.*;import android.os.*;import android.content.*;import android.view.*;import android.widget.*;import android.graphics.*;import java.lang.reflect.*;import java.io.*;import org.json.*;
/** Offline measurement of the actual native components; does not send messages or upload media. */
public class Compact18Audit extends Instrumentation {
 public void onCreate(Bundle b){super.onCreate(b);start();}
 Object call(Object a,String n,Class<?>[] t,Object...v)throws Exception{Method m=a.getClass().getDeclaredMethod(n,t);m.setAccessible(true);return m.invoke(a,v);}
 void set(Object a,String n,Object v)throws Exception{Field f=a.getClass().getDeclaredField(n);f.setAccessible(true);f.set(a,v);}
 void check(boolean b,String why){if(!b)throw new AssertionError(why);}
 int dp(Activity a,int v){return Math.round(v*a.getResources().getDisplayMetrics().density);}
 EditText input(View v){if(v instanceof EditText)return(EditText)v;if(v instanceof ViewGroup){ViewGroup g=(ViewGroup)v;for(int i=0;i<g.getChildCount();i++){EditText e=input(g.getChildAt(i));if(e!=null)return e;}}return null;}
 String text(View v){String s=v instanceof TextView?((TextView)v).getText().toString():"";if(v instanceof ViewGroup){ViewGroup g=(ViewGroup)v;for(int i=0;i<g.getChildCount();i++)s+="\n"+text(g.getChildAt(i));}return s;}
 void shot(Activity a,String n)throws Exception{waitForIdleSync();Thread.sleep(200);try(FileOutputStream out=new FileOutputStream(new File(a.getExternalFilesDir(null),n))){getUiAutomation().takeScreenshot().compress(Bitmap.CompressFormat.PNG,100,out);}}
 public void onStart(){Bundle result=new Bundle();try{
  getTargetContext().getSharedPreferences("kinnect_crash",0).edit().remove("last").commit();
  getTargetContext().getSharedPreferences("native_setup",0).edit().putBoolean("asked_v1",true).commit();
  Class<?> language=getTargetContext().getClassLoader().loadClass("app.kinnect.live.I18n");Method select=language.getDeclaredMethod("select",Context.class,String.class);select.setAccessible(true);select.invoke(null,getTargetContext(),"vi");
  Activity a=startActivitySync(new Intent().setClassName("app.kinnect.live","app.kinnect.live.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));Thread.sleep(800);
  runOnMainSync(()->{try{
   LinearLayout root=new LinearLayout(a);root.setOrientation(1);root.setPadding(dp(a,12),dp(a,12),dp(a,12),dp(a,12));a.setContentView(root);
   for(boolean own:new boolean[]{true,false})for(boolean recalled:new boolean[]{false,true}){
    JSONObject message=new JSONObject().put("id","local-layout-only").put("recalled",recalled).put("receipt",new JSONObject().put("seenAt",1)).put("pinned",true).put("reactions",new JSONObject().put("like",3));
    LinearLayout footer=(LinearLayout)call(a,"messageFooter",new Class[]{JSONObject.class,boolean.class,String.class,boolean.class,String.class,Runnable.class},message,own,"23:10",false,"/unused",(Runnable)()->{});
    int available=dp(a,320-24-48-28);footer.measure(View.MeasureSpec.makeMeasureSpec(available,View.MeasureSpec.AT_MOST),View.MeasureSpec.makeMeasureSpec(0,View.MeasureSpec.UNSPECIFIED));footer.layout(0,0,footer.getMeasuredWidth(),footer.getMeasuredHeight());
    check(footer.getOrientation()==0,"Footer is not one row");ViewGroup tools=(ViewGroup)footer.getChildAt(1);check(tools.getChildCount()==(recalled?1:own?4:3),"Message actions missing");check(tools.getRight()<=available,"Actions overflow at 320dp");
    TextView time=(TextView)footer.getChildAt(0);check(time.getLineCount()==1,"Time wraps");if(own&&!recalled)check(time.getContentDescription().toString().contains("Đã xem"),"Receipt lost");
    LinearLayout bubble=new LinearLayout(a);bubble.setOrientation(1);bubble.setPadding(dp(a,14),dp(a,9),dp(a,14),dp(a,7));android.graphics.drawable.GradientDrawable bg=new android.graphics.drawable.GradientDrawable();bg.setColor(own?0xff6c47e0:0xffeeeeee);bg.setCornerRadius(dp(a,18));bubble.setBackground(bg);
    TextView body=(TextView)call(a,"label",new Class[]{String.class,int.class,int.class},recalled?"Tin nhắn đã được thu hồi":"hi",15,own?Color.WHITE:Color.BLACK);body.setPadding(0,0,0,0);bubble.addView(body);bubble.addView(footer);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-2,-2);lp.gravity=own?Gravity.END:Gravity.START;lp.bottomMargin=dp(a,8);root.addView(bubble,lp);check(bubble.getChildCount()==2,"Short message must have two rows");
   }
  }catch(Exception e){throw new RuntimeException(e);}});check(a.hasWindowFocus(),"Message component capture obscured");shot(a,"compact18-messages.png");
  runOnMainSync(()->{try{JSONObject user=new JSONObject().put("id","local-profile").put("name","Hồ sơ kiểm tra").put("bio","Giới thiệu mặc định");set(a,"me",user);LinearLayout root=new LinearLayout(a);root.setOrientation(1);a.setContentView(root);set(a,"content",root);call(a,"profileSections",new Class[]{JSONObject.class},user);HorizontalScrollView tabs=(HorizontalScrollView)root.getChildAt(0);LinearLayout controls=(LinearLayout)tabs.getChildAt(0);check(controls.getChildAt(0).isSelected(),"About is not selected by default");check(text(root).contains("Giới thiệu mặc định"),"About content absent on initial open");}catch(Exception e){throw new RuntimeException(e);}});check(a.hasWindowFocus(),"Profile capture obscured");shot(a,"compact18-profile.png");
  final Dialog[] dialog={null};runOnMainSync(()->{try{dialog[0]=(Dialog)call(a,"uploadVideoNow",new Class[]{android.net.Uri.class},android.net.Uri.parse("content://local-layout-only/video"));EditText caption=input(dialog[0].getWindow().getDecorView());check(caption!=null,"Caption missing");check(caption.getPaddingLeft()>=dp(a,14)&&caption.getPaddingRight()>=dp(a,14),"Caption touches border");check(((View)caption.getParent()).getPaddingTop()>=dp(a,8),"Caption too close to title");}catch(Exception e){throw new RuntimeException(e);}});shot(a,"compact18-upload.png");runOnMainSync(()->{dialog[0].dismiss();a.finish();});result.putString("result","PASS: compact native footer and all actions at 320dp; initial About selection/content; upload caption insets. Offline component QA; no real-device verification.");finish(Activity.RESULT_OK,result);
 }catch(Throwable e){result.putString("error",e.toString());finish(Activity.RESULT_CANCELED,result);}}
}
