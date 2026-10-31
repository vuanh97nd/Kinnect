package app.kinnect.audit;
import android.app.*;import android.content.*;import android.graphics.*;import android.net.Uri;import android.os.*;import android.view.*;import android.widget.*;import java.io.*;import java.lang.reflect.*;import java.util.*;import org.json.*;

/** Offline pixel/storage/UI audit. Entitlement fixtures are injected only by Instrumentation reflection. */
public class PhotoLayoutAudit extends Instrumentation {
 Class<?> model,engine;int checks;
 public void onCreate(Bundle b){super.onCreate(b);start();}
 void check(boolean ok,String why){if(!ok)throw new AssertionError(why);checks++;}
 Object get(Object o,String name)throws Exception{Field f=o.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(o);}
 void set(Object o,String name,Object value)throws Exception{Field f=o.getClass().getDeclaredField(name);f.setAccessible(true);f.set(o,value);}
 Object call(Object o,String name,Class<?>[] types,Object...args)throws Exception{Method m=o.getClass().getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(o,args);}
 Object document(JSONObject data)throws Exception{Method m=model.getDeclaredMethod("decode",String.class);m.setAccessible(true);return m.invoke(null,data.toString());}
 Bitmap render(JSONObject data)throws Exception{Method m=engine.getDeclaredMethod("render",Context.class,model,int.class);m.setAccessible(true);return(Bitmap)m.invoke(null,getTargetContext(),document(data),128);}
 JSONObject base(File f)throws Exception{return new JSONObject().put("schema",1).put("width",64).put("height",48).put("originalSource",f.getPath()).put("selected","base").put("layers",new JSONArray().put(new JSONObject().put("id","base").put("source",f.getPath()).put("kind","image")));}
 JSONObject copy(JSONObject o)throws Exception{return new JSONObject(o.toString());}
 byte[] bytes(File file)throws Exception{try(InputStream in=new FileInputStream(file);ByteArrayOutputStream out=new ByteArrayOutputStream()){byte[] b=new byte[8192];for(int n;(n=in.read(b))!=-1;)out.write(b,0,n);return out.toByteArray();}}
 View find(View v,String label){if(label.equals(v.getContentDescription())||v instanceof TextView&&label.equals(((TextView)v).getText().toString()))return v;if(v instanceof ViewGroup){ViewGroup g=(ViewGroup)v;for(int i=0;i<g.getChildCount();i++){View result=find(g.getChildAt(i),label);if(result!=null)return result;}}return null;}
 View slider(View v,String label){if(v instanceof SeekBar&&label.equals(v.getContentDescription()))return v;if(v instanceof ViewGroup){ViewGroup g=(ViewGroup)v;for(int i=0;i<g.getChildCount();i++){View result=slider(g.getChildAt(i),label);if(result!=null)return result;}}return null;}
 void waitReady(Activity a)throws Exception{for(int i=0;i<100;i++){final boolean[] ready={false};runOnMainSync(()->{try{ready[0]=get(a,"project")!=null&&get(a,"rendered")!=null&&!((Boolean)get(a,"loading"));}catch(Exception e){throw new RuntimeException(e);}});if(ready[0])return;Thread.sleep(100);}throw new AssertionError("Photo editor did not load");}
 void shot(Activity a,String name)throws Exception{waitForIdleSync();Thread.sleep(150);check(a.hasWindowFocus(),"Editor screenshot obscured");try(FileOutputStream out=new FileOutputStream(new File(a.getExternalFilesDir(null),name))){getUiAutomation().takeScreenshot().compress(Bitmap.CompressFormat.PNG,100,out);}}
 void tap(String label)throws Exception{for(int i=0;i<30;i++){android.view.accessibility.AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();if(root!=null)for(android.view.accessibility.AccessibilityNodeInfo n:root.findAccessibilityNodeInfosByText(label)){if(!label.contentEquals(n.getText()==null?"":n.getText()))continue;while(n!=null&&!n.isClickable())n=n.getParent();if(n!=null&&n.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)){Thread.sleep(100);return;}}Thread.sleep(100);}throw new AssertionError("Missing action "+label);}
 public void onStart(){Bundle result=new Bundle();try{
 Class<?> language=getTargetContext().getClassLoader().loadClass("app.kinnect.live.I18n");Method select=language.getDeclaredMethod("select",Context.class,String.class);select.setAccessible(true);
 Class<?> apiClass=getTargetContext().getClassLoader().loadClass("app.kinnect.live.NativeApi");Object api=apiClass.getField("shared").get(null);Field cookie=apiClass.getDeclaredField("cookie");cookie.setAccessible(true);Object previous=cookie.get(api);cookie.set(api,"photo-layout-audit-only");
 File photo=new File(getTargetContext().getCacheDir(),"photo-layout-audit.webp");try(InputStream in=getContext().getAssets().open("photo-reference.webp");FileOutputStream out=new FileOutputStream(photo)){byte[] bytes=new byte[8192];for(int n;(n=in.read(bytes))!=-1;)out.write(bytes,0,n);}
 for(String code:new String[]{"vi","en"}){
  select.invoke(null,getTargetContext(),code);Activity a=startActivitySync(new Intent().setClassName("app.kinnect.live","app.kinnect.live.PhotoEditActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));String account=UUID.randomUUID().toString().replace("-","");JSONObject catalog=new JSONObject().put("accountId",account+account).put("owned",new JSONArray().put("kinnect_studio_pro"));
  runOnMainSync(()->{try{set(a,"initialUri",Uri.fromFile(photo));call(a,"acceptCatalog",new Class[]{JSONObject.class},catalog);}catch(Exception e){throw new RuntimeException(e);}});waitReady(a);
  for(String group:new String[]{"crop","color","beauty","merge","text"}){
   runOnMainSync(()->{try{set(a,"group",group);call(a,"renderControls",new Class[]{});}catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();Thread.sleep(150);
   runOnMainSync(()->{try{View canvas=(View)get(a,"canvas");check(canvas.getHeight()>100,"Canvas collapsed");LinearLayout tools=(LinearLayout)get(a,"tools");check(tools.getChildCount()==5,"Primary tool count changed");for(int i=0;i<5;i++){ViewGroup tool=(ViewGroup)tools.getChildAt(i);TextView label=(TextView)tool.getChildAt(1);check(label.getLayout()!=null&&label.getLayout().getHeight()<=label.getHeight()-label.getPaddingTop()-label.getPaddingBottom(),"Tool label clipped: "+label.getText());ImageView image=(ImageView)tool.getChildAt(0);check(image.getDrawable()!=null,"Primary tool icon missing");}}catch(Exception e){throw new RuntimeException(e);}});shot(a,"photo21-"+code+"-"+group+".png");
  }
  runOnMainSync(()->{try{call(a,"curves",new Class[]{});}catch(Exception e){throw new RuntimeException(e);}});Thread.sleep(200);try(FileOutputStream out=new FileOutputStream(new File(a.getExternalFilesDir(null),"photo21-"+code+"-curves.png"))){getUiAutomation().takeScreenshot().compress(Bitmap.CompressFormat.PNG,100,out);}tap(code.equals("vi")?"Áp dụng":"Apply");
  runOnMainSync(()->a.finish());
 }
 cookie.set(api,previous);select.invoke(null,getTargetContext(),"vi");result.putString("result","PASS: "+checks+" layout checks across five tool groups in VI/EN at current font scale; canvas retained; primary labels fit and icons exist; native Curves chart captured.");finish(Activity.RESULT_OK,result);
 }catch(Throwable e){result.putString("error",e.toString());finish(Activity.RESULT_CANCELED,result);}}
}
