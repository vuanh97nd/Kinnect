package app.kinnect.live;
import android.content.Context;import android.graphics.*;import android.view.*;import android.widget.ScrollView;
/** Native pull refresh. A downward gesture is claimed only from the scroll boundary. */
final class PullRefreshScrollView extends ScrollView {
 interface Listener{void refresh(Runnable complete);boolean enabled();}
 private Listener listener;private float startX,startY,pull;private boolean top,dragging,busy;private final Paint paint=new Paint(3);
 PullRefreshScrollView(Context c){super(c);setOverScrollMode(OVER_SCROLL_NEVER);}
 void setRefreshListener(Listener l){listener=l;}
 void refreshNow(){if(busy||listener==null||!listener.enabled())return;busy=true;invalidate();listener.refresh(()->post(()->{busy=false;invalidate();}));}
 private float dp(float n){return n*getResources().getDisplayMetrics().density;}
 public boolean onInterceptTouchEvent(MotionEvent e){if(e.getActionMasked()==MotionEvent.ACTION_DOWN){startY=e.getY();startX=e.getX();top=!canScrollVertically(-1);dragging=false;}if(e.getActionMasked()==MotionEvent.ACTION_MOVE&&top&&!busy&&listener!=null&&listener.enabled()&&e.getY()-startY>dp(16)&&e.getY()-startY>Math.abs(e.getX()-startX)*1.3f){dragging=true;return true;}return super.onInterceptTouchEvent(e);}
 public boolean onTouchEvent(MotionEvent e){if(e.getActionMasked()==MotionEvent.ACTION_DOWN){startY=e.getY();startX=e.getX();top=!canScrollVertically(-1);}if(!dragging&&e.getActionMasked()==MotionEvent.ACTION_MOVE&&top&&!busy&&listener!=null&&listener.enabled()&&e.getY()-startY>dp(16)&&e.getY()-startY>Math.abs(e.getX()-startX)*1.3f){dragging=true;MotionEvent cancel=MotionEvent.obtain(e);cancel.setAction(MotionEvent.ACTION_CANCEL);super.onTouchEvent(cancel);cancel.recycle();}if(!dragging)return super.onTouchEvent(e);if(e.getActionMasked()==MotionEvent.ACTION_MOVE){pull=Math.max(0,Math.min(dp(88),(e.getY()-startY)*.6f));invalidate();return true;}if(e.getActionMasked()==MotionEvent.ACTION_UP||e.getActionMasked()==MotionEvent.ACTION_CANCEL){boolean trigger=e.getActionMasked()==MotionEvent.ACTION_UP&&pull>=dp(48);dragging=false;pull=0;if(trigger&&!busy&&listener!=null){busy=true;announceForAccessibility(I18n.t("Đang làm mới…"));listener.refresh(()->post(()->{busy=false;invalidate();}));}invalidate();return true;}return true;}
 protected void dispatchDraw(Canvas c){super.dispatchDraw(c);if(!busy&&pull<=0)return;float x=getWidth()/2f,y=getScrollY()+dp(30)+Math.min(pull,dp(28));paint.setStyle(Paint.Style.FILL);paint.setColor(0xfff4efff);c.drawCircle(x,y,dp(19),paint);paint.setColor(0xff7652dc);paint.setStyle(Paint.Style.STROKE);paint.setStrokeWidth(dp(2));paint.setStrokeCap(Paint.Cap.ROUND);float angle=busy?(android.os.SystemClock.uptimeMillis()%900)*.4f:Math.min(260,pull/dp(48)*260);c.drawArc(x-dp(9),y-dp(9),x+dp(9),y+dp(9),angle,260,false,paint);if(busy)postInvalidateDelayed(24);}
 protected void onDetachedFromWindow(){busy=false;dragging=false;super.onDetachedFromWindow();}
}
