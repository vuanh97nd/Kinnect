package app.kinnect.audit;
import android.app.*;import android.content.*;import android.os.*;import android.view.*;import android.widget.*;import java.lang.reflect.*;import java.io.*;
public class StoreLayoutAudit extends Instrumentation {
  private Object call(Activity a,String name)throws Exception{Method m=a.getClass().getDeclaredMethod(name);m.setAccessible(true);return m.invoke(a);}
  private TextView find(View v,String text){if(v instanceof TextView&&((TextView)v).getText().toString().equals(text))return(TextView)v;if(v instanceof ViewGroup)for(int i=0;i<((ViewGroup)v).getChildCount();i++){TextView t=find(((ViewGroup)v).getChildAt(i),text);if(t!=null)return t;}return null;}
  private void check(boolean value,String message){if(!value)throw new AssertionError(message);}
  public void onCreate(Bundle b){super.onCreate(b);start();}
  public void onStart(){Bundle out=new Bundle();try{
    Activity a=startActivitySync(new Intent().setClassName("app.kinnect.live","app.kinnect.live.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));Thread.sleep(1400);
    runOnMainSync(()->{try{call(a,"intro");}catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();
    runOnMainSync(()->{TextView t=find(a.getWindow().getDecorView(),"VI / EN");check(t!=null,"Missing language selector");check(t.getLineCount()==1,"Language wraps");check(t.getLayout().getEllipsisCount(0)==0,"Language clipped");check(t.getGravity()==android.view.Gravity.CENTER,"Language not centered");ViewGroup p=(ViewGroup)t.getParent();check(!((LinearLayout)p).isBaselineAligned(),"Brand row shifts text baseline");check(Math.abs(t.getTop()+t.getHeight()/2f-p.getHeight()/2f)<=2,"Language vertically offset");check(t.getRight()<=p.getWidth(),"Language overflows row");});
    try(FileOutputStream f=new FileOutputStream(new File(a.getExternalFilesDir(null),"layout-language.jpg"))){getUiAutomation().takeScreenshot().compress(android.graphics.Bitmap.CompressFormat.JPEG,95,f);}
    runOnMainSync(()->a.finish());out.putString("result","PASS: VI/EN single line, centered and contained in brand row");finish(Activity.RESULT_OK,out);
  }catch(Throwable e){out.putString("error",e.toString());finish(Activity.RESULT_CANCELED,out);}}
}
