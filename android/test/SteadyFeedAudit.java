package app.kinnect.audit;
import android.app.*;import android.os.*;import android.content.*;import android.view.*;import android.widget.*;import android.graphics.*;import java.lang.reflect.*;import java.io.*;import java.util.concurrent.*;import org.json.*;import app.kinnect.live.NativeApi;
/** Captures actual server-backed UI using the private, ordinary App-access account. */
public class SteadyFeedAudit extends Instrumentation {
 public void onCreate(Bundle b){super.onCreate(b);start();}
 private JSONObject api(String method,String path,JSONObject body)throws Exception{CountDownLatch done=new CountDownLatch(1);JSONObject[] result=new JSONObject[1];String[] failure=new String[1];NativeApi.shared.call(method,path,body,(data,error,status)->{result[0]=data;failure[0]=error;done.countDown();});if(!done.await(25,TimeUnit.SECONDS))throw new AssertionError("API timeout");if(failure[0]!=null)throw new AssertionError("API failed: "+failure[0]);return result[0];}
 private static Object call(Activity a,String name,Class<?>[] types,Object...args)throws Exception{Method m=a.getClass().getDeclaredMethod(name,types);m.setAccessible(true);return m.invoke(a,args);}
 private static TextView find(View v,String value){if(v instanceof TextView&&((TextView)v).getText().toString().equals(value))return (TextView)v;if(v instanceof android.view.ViewGroup){android.view.ViewGroup g=(android.view.ViewGroup)v;for(int i=0;i<g.getChildCount();i++){TextView t=find(g.getChildAt(i),value);if(t!=null)return t;}}return null;}
 private void shot(Activity a,String name)throws Exception{waitForIdleSync();Thread.sleep(350);if(!a.hasWindowFocus())throw new AssertionError("Screen obscured by another window: "+name);try(FileOutputStream out=new FileOutputStream(new File(a.getExternalFilesDir(null),name))){getUiAutomation().takeScreenshot().compress(Bitmap.CompressFormat.JPEG,95,out);}}
 private void tapText(String value)throws Exception{
  for(int attempt=0;attempt<30;attempt++){
   android.view.accessibility.AccessibilityNodeInfo root=getUiAutomation().getRootInActiveWindow();
   if(root!=null)for(android.view.accessibility.AccessibilityNodeInfo node:root.findAccessibilityNodeInfosByText(value))if(value.contentEquals(node.getText()==null?"":node.getText())){
    android.view.accessibility.AccessibilityNodeInfo target=node;while(target!=null&&!target.isClickable())target=target.getParent();
    if(target!=null&&target.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)){Thread.sleep(400);return;}
   }
   Thread.sleep(100);
  }
  throw new AssertionError("Missing navigation control: "+value);
 }
 public void onStart(){Bundle result=new Bundle();try{
 getTargetContext().getSharedPreferences("kinnect_crash",0).edit().remove("last").commit();getTargetContext().getSharedPreferences("native_setup",0).edit().putBoolean("asked_v1",true).commit();
 Activity a=startActivitySync(new Intent().setClassName("app.kinnect.live","app.kinnect.live.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));Thread.sleep(1200);
 JSONObject credentials;try(InputStream stream=getContext().getAssets().open("private-reviewer.json")){byte[] bytes=new byte[stream.available()];new DataInputStream(stream).readFully(bytes);credentials=new JSONObject(new String(bytes,"UTF-8"));}
 JSONObject account=api("POST","/api/login",new JSONObject().put("username",credentials.getString("username")).put("password",credentials.getString("password")).put("remember",false)).getJSONObject("user");credentials=null;
 if(!account.optString("role").equals("user"))throw new AssertionError("Ordinary QA account required");
 runOnMainSync(()->{try{Field me=a.getClass().getDeclaredField("me");me.setAccessible(true);me.set(a,account);call(a,"navigate",new Class[]{String.class},"feed");}catch(Exception e){throw new RuntimeException(e);}});Thread.sleep(3000);
 final ScrollView[] old={null};final View[] oldContent={null};final int[] y={0},height={0},frames={0};final boolean[] wrongFrame={false};
 runOnMainSync(()->{try{Field f=a.getClass().getDeclaredField("content");f.setAccessible(true);oldContent[0]=(View)f.get(a);old[0]=(ScrollView)oldContent[0].getParent();old[0].scrollTo(0,900);y[0]=old[0].getScrollY();height[0]=oldContent[0].getHeight();if(y[0]<100)throw new AssertionError("Need scrollable feed");call(a,"navigate",new Class[]{String.class},"discover");}catch(Exception e){throw new RuntimeException(e);}});Thread.sleep(700);
 runOnMainSync(()->{try{call(a,"selectNavigation",new Class[]{String.class},"feed");Field f=a.getClass().getDeclaredField("content");f.setAccessible(true);View shown=(View)f.get(a);if(shown!=oldContent[0]||shown.getParent()!=old[0])throw new AssertionError("Feed viewport was rebuilt");if(old[0].getScrollY()!=y[0])throw new AssertionError("Return starts at top");old[0].getViewTreeObserver().addOnDrawListener(()->{frames[0]++;if(Math.abs(old[0].getScrollY()-y[0])>2)wrongFrame[0]=true;});old[0].invalidate();}catch(Exception e){throw new RuntimeException(e);}});Thread.sleep(1200);waitForIdleSync();
 if(wrongFrame[0]||frames[0]==0||oldContent[0].getHeight()!=height[0])throw new AssertionError("Feed jumped during first rendered frames");shot(a,"steady19-feed-return.jpg");
 runOnMainSync(()->{try{call(a,"selectNavigation",new Class[]{String.class},"feed");}catch(Exception e){throw new RuntimeException(e);}});Thread.sleep(1000);if(old[0].getScrollY()>5)throw new AssertionError("Active Feed tap no longer resets top");
 runOnMainSync(()->{try{call(a,"say",new Class[]{String.class},"Máy chủ đang tạm gián đoạn. Vui lòng thử lại sau.");Field f=a.getClass().getDeclaredField("toastView");f.setAccessible(true);Object first=f.get(a);call(a,"say",new Class[]{String.class},"Máy chủ đang tạm gián đoạn. Vui lòng thử lại sau.");if(f.get(a)!=first)throw new AssertionError("Repeated error created another toast");}catch(Exception e){throw new RuntimeException(e);}});
 JSONObject people=api("GET","/api/discover",null);JSONArray users=people.optJSONArray("users");if(users==null||users.length()==0)throw new AssertionError("No available member for conversation navigation QA");final JSONObject other=users.getJSONObject(0);
 runOnMainSync(()->{try{call(a,"chat",new Class[]{JSONObject.class},other);call(a,"directChatMenu",new Class[]{JSONObject.class},other);}catch(Exception e){throw new RuntimeException(e);}});Thread.sleep(600);
 tapText("Cài đặt hội thoại");tapText("Quay lại");
 android.view.accessibility.AccessibilityNodeInfo menuRoot=getUiAutomation().getRootInActiveWindow();if(menuRoot==null||menuRoot.findAccessibilityNodeInfosByText("Xem hồ sơ").isEmpty())throw new AssertionError("Settings Back did not return to conversation menu");tapText("Quay lại");Thread.sleep(300);
 if(!a.hasWindowFocus())throw new AssertionError("Root Back did not close to the chat");
 shot(a,"steady19-chat-return.jpg");
 runOnMainSync(()->a.finish());result.putString("result","PASS: same feed viewport/content restored; immediate and first drawn frame positions unchanged; media layout height unchanged; active Feed tap refreshes at top; duplicate errors suppressed; actual direct chat menu > settings > Back > parent menu > Back > chat.");finish(Activity.RESULT_OK,result);
 }catch(Throwable e){result.putString("error",e.toString());finish(Activity.RESULT_CANCELED,result);}}
}
