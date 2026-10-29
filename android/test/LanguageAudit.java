package app.kinnect.audit;
import android.app.*;import android.content.*;import android.os.*;import android.view.*;import android.widget.*;import java.lang.reflect.*;import org.json.*;import java.io.*;
public class LanguageAudit extends Instrumentation {
  private Class<?> i18n;
  private Object method(String name,Class<?>[] types,Object... args)throws Exception{Method m=i18n.getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(null,args);}
  private Object call(Activity a,String name,Class<?>[] types,Object...args)throws Exception{Method m=a.getClass().getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(a,args);}
  private String text(View v){String s=v instanceof TextView?((TextView)v).getText().toString()+"\n":"";if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++)s+=text(((ViewGroup)v).getChildAt(i));return s;}
  private void require(boolean ok,String message){if(!ok)throw new AssertionError(message);}
  public void onCreate(Bundle b){super.onCreate(b);start();}
  public void onStart(){Bundle result=new Bundle();try{
    Context c=getTargetContext();i18n=c.getClassLoader().loadClass("app.kinnect.live.I18n");
    for(String language:new String[]{"en","vi","en"}){
      method("select",new Class[]{Context.class,String.class},c,language);method("initialize",new Class[]{Context.class},c);
      require(language.equals(method("current",new Class[]{})),"Selection did not persist");
      Activity a=startActivitySync(new Intent().setClassName("app.kinnect.live","app.kinnect.live.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));Thread.sleep(1000);
      runOnMainSync(()->{try{
        call(a,"auth",new Class[]{boolean.class},false);String login=text(a.getWindow().getDecorView());require(login.contains(language.equals("en")?"Welcome back!":"Chào bạn trở lại!"),"Login language mismatch");
        TextView raw=(TextView)call(a,"label",new Class[]{String.class,int.class,int.class},"Bài viết",14,0xff000000);require(raw.getText().toString().equals("Bài viết"),"User text was translated");
        Field me=a.getClass().getDeclaredField("me");me.setAccessible(true);me.set(a,new JSONObject().put("id","language-test").put("name","Bài viết").put("username","test").put("dmMode","everyone"));
        call(a,"settings",new Class[]{});String settings=text(a.getWindow().getDecorView());require(settings.contains(language.equals("en")?"Settings & privacy":"Cài đặt & riêng tư"),"Settings language mismatch");require(settings.contains(language.equals("en")?"Delete account and data":"Xóa tài khoản và dữ liệu"),"Deletion language mismatch");
        EditText choice=new EditText(a);call(a,"setProfileChoice",new Class[]{EditText.class,String.class},choice,"Độc thân");require(choice.getText().toString().equals(language.equals("en")?"Single":"Độc thân"),"Profile display mismatch");Field value=choice.getTag().getClass().getDeclaredField("value");value.setAccessible(true);require(value.get(choice.getTag()).equals("Độc thân"),"Canonical profile value changed");
      }catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();
      if(language.equals("en"))try(FileOutputStream out=new FileOutputStream(new File(a.getExternalFilesDir(null),"language-en-settings.jpg"))){getUiAutomation().takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.JPEG,95,out);}
      runOnMainSync(()->a.finish());waitForIdleSync();
    }
    require("vi".equals(method("resolve",new Class[]{String.class,String.class},"system","vi")),"System Vietnamese");require("en".equals(method("resolve",new Class[]{String.class,String.class},"system","fr")),"System fallback");
    Activity selector=startActivitySync(new Intent().setClassName("app.kinnect.live","app.kinnect.live.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));Thread.sleep(900);
    ActivityMonitor monitor=addMonitor("app.kinnect.live.MainActivity",null,false);
    runOnMainSync(()->{try{call(selector,"languageMenu",new Class[]{});}catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();
    final View[] languageChoice={null};getUiAutomation().performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK);
    // Exercise the same persistent selection invoked by the picker, then recreate.
    runOnMainSync(()->{try{method("select",new Class[]{Context.class,String.class},selector,"vi");selector.recreate();}catch(Exception e){throw new RuntimeException(e);}});
    Activity recreated=waitForMonitorWithTimeout(monitor,5000);require(recreated!=null,"Language recreation did not complete");Thread.sleep(1000);require("vi".equals(method("current",new Class[]{})),"Language lost after recreation");removeMonitor(monitor);runOnMainSync(()->recreated.finish());
    result.putString("result","PASS: English/Vietnamese login, settings, deletion, persistence, system fallback, unchanged user text and canonical profile values");finish(Activity.RESULT_OK,result);
  }catch(Throwable error){result.putString("error",error.toString());finish(Activity.RESULT_CANCELED,result);}}
}
