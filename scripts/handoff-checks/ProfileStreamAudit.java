package app.kinnect.audit;
import android.app.*;import android.os.*;import android.content.*;import android.view.*;import android.widget.*;import java.lang.reflect.*;import org.json.*;
public class ProfileStreamAudit extends Instrumentation {
 private static void field(Activity a,String n,Object value)throws Exception{Field f=a.getClass().getDeclaredField(n);f.setAccessible(true);f.set(a,value);}
 private static Object call(Activity a,String n,Class<?>[] types,Object...args)throws Exception{Method m=a.getClass().getDeclaredMethod(n,types);m.setAccessible(true);return m.invoke(a,args);}
 public void onCreate(Bundle b){super.onCreate(b);start();}
 public void onStart(){Bundle result=new Bundle();try{
  Activity a=startActivitySync(new Intent().setClassName("app.kinnect.live","app.kinnect.live.MainActivity").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));Thread.sleep(1200);
  final ScrollView[] scroll=new ScrollView[1];final LinearLayout[] content=new LinearLayout[1],list=new LinearLayout[1];
  runOnMainSync(()->{try{scroll[0]=new ScrollView(a);content[0]=new LinearLayout(a);content[0].setOrientation(1);scroll[0].addView(content[0]);a.setContentView(scroll[0]);field(a,"content",content[0]);TextView header=new TextView(a);header.setText("Hồ sơ kiểm tra");content[0].addView(header,new LinearLayout.LayoutParams(-1,260));call(a,"profileSections",new Class[]{JSONObject.class},new JSONObject().put("id","audit-local"));list[0]=(LinearLayout)content[0].getChildAt(2);list[0].removeAllViews();TextView empty=new TextView(a);empty.setText("Chưa có bài viết");list[0].addView(empty,new LinearLayout.LayoutParams(-1,120));}catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();Thread.sleep(200);
  runOnMainSync(()->{if(list[0].getMinimumHeight()!=0)throw new AssertionError("Profile forces blank minimum height");scroll[0].fullScroll(View.FOCUS_DOWN);});waitForIdleSync();
  runOnMainSync(()->{if(content[0].getHeight()<scroll[0].getHeight()&&scroll[0].getScrollY()!=0)throw new AssertionError("Empty profile scrolls beyond content");});
  runOnMainSync(()->{try{list[0]=new LinearLayout(a);list[0].setOrientation(1);scroll[0]=new ScrollView(a);scroll[0].addView(list[0]);a.setContentView(scroll[0]);field(a,"aiChatList",list[0]);field(a,"aiChatScroll",scroll[0]);field(a,"aiChatSender","audit-admin");}catch(Exception e){throw new RuntimeException(e);}});waitForIdleSync();
  for(String text:new String[]{"Chào ","Chào bạn"}){runOnMainSync(()->{try{call(a,"receiveAIStream",new Class[]{JSONObject.class},new JSONObject().put("id","test-stream").put("sender","audit-admin").put("body",text));if(list[0].getChildCount()!=1||!((TextView)list[0].getChildAt(0)).getText().toString().equals(text))throw new AssertionError("Streaming text missing/duplicated");}catch(Exception e){throw new RuntimeException(e);}});}
  runOnMainSync(()->{try{call(a,"receiveAIStream",new Class[]{JSONObject.class},new JSONObject().put("id","test-stream").put("sender","audit-admin").put("done",true));if(list[0].getChildCount()!=0)throw new AssertionError("Completed draft remains");}catch(Exception e){throw new RuntimeException(e);}});
  result.putString("result","PASS: profile wraps content; actual native chat paints incremental text once and clears completed drafts");finish(Activity.RESULT_OK,result);
 }catch(Throwable t){result.putString("error",t.toString());finish(Activity.RESULT_CANCELED,result);}}
}
