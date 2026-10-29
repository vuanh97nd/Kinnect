package app.kinnect.live;
import android.content.Context;import android.graphics.Rect;import android.view.*;import android.widget.*;
/** One gesture and motion model for reels and viewer LIVE; controls and chat retain touch ownership. */
class VerticalMediaStage extends FrameLayout {
 interface Steps{boolean step(int direction);}
 private final Steps steps;private float x,y;private boolean eligible,drag;private VelocityTracker velocity;private boolean moving;
 VerticalMediaStage(Context context,Steps steps){super(context);this.steps=steps;}
 private float dp(float value){return value*getResources().getDisplayMetrics().density;}
 private boolean interactive(View view,int x,int y){if(view.getVisibility()!=VISIBLE)return false;Rect bounds=new Rect();if(!view.getGlobalVisibleRect(bounds)||!bounds.contains(x,y))return false;if(view!=this&&(view.isClickable()||view instanceof EditText||view instanceof ScrollView||view instanceof HorizontalScrollView))return true;if(view instanceof ViewGroup){ViewGroup group=(ViewGroup)view;for(int i=group.getChildCount()-1;i>=0;i--)if(interactive(group.getChildAt(i),x,y))return true;}return false;}
 private void down(MotionEvent event){x=event.getRawX();y=event.getRawY();eligible=!moving&&event.getY()>dp(80)&&event.getY()<getHeight()-dp(66)&&!interactive(this,(int)x,(int)y);drag=false;if(velocity!=null)velocity.recycle();velocity=VelocityTracker.obtain();velocity.addMovement(event);}
 private boolean claim(MotionEvent e){float dy=e.getRawY()-y,dx=e.getRawX()-x;return eligible&&Math.abs(dy)>dp(10)&&Math.abs(dy)>Math.abs(dx)*1.35f;}
 @Override public boolean onInterceptTouchEvent(MotionEvent e){if(e.getActionMasked()==MotionEvent.ACTION_DOWN)down(e);if(e.getActionMasked()==MotionEvent.ACTION_MOVE&&claim(e)){drag=true;return true;}return super.onInterceptTouchEvent(e);}
 @Override public boolean onTouchEvent(MotionEvent e){if(e.getActionMasked()==MotionEvent.ACTION_DOWN)down(e);if(velocity!=null)velocity.addMovement(e);float dy=e.getRawY()-y;if(e.getActionMasked()==MotionEvent.ACTION_MOVE&&(drag||claim(e))){drag=true;setTranslationY((float)Math.tanh(dy/dp(170))*dp(76));setAlpha(1-Math.min(.12f,Math.abs(dy)/dp(1800)));return true;}if(e.getActionMasked()==MotionEvent.ACTION_UP||e.getActionMasked()==MotionEvent.ACTION_CANCEL){boolean was=drag;float speed=0;if(velocity!=null){velocity.computeCurrentVelocity(1000);speed=velocity.getYVelocity();velocity.recycle();velocity=null;}boolean commit=was&&e.getActionMasked()==MotionEvent.ACTION_UP&&(Math.abs(dy)>dp(64)||Math.abs(dy)>dp(24)&&Math.abs(speed)>dp(700)&&speed*dy>0);drag=false;eligible=false;if(commit&&steps.step(dy<0?1:-1))return true;settle();if(!was&&e.getActionMasked()==MotionEvent.ACTION_UP)performClick();return true;}return true;}
 @Override public boolean performClick(){return super.performClick();}
 void prepare(){moving=false;animate().cancel();setTranslationY(0);setAlpha(1);}
 void settle(){animate().cancel();moving=false;animate().translationY(0).alpha(1).setDuration(180).setInterpolator(new android.view.animation.DecelerateInterpolator()).start();}
 void exit(int direction,Runnable next){moving=true;animate().cancel();animate().translationY(-direction*dp(82)).alpha(.2f).setDuration(120).setInterpolator(new android.view.animation.AccelerateInterpolator()).withEndAction(next).start();}
 static void enter(View stage,int direction){stage.animate().cancel();stage.setTranslationY(direction*48*stage.getResources().getDisplayMetrics().density);stage.setAlpha(.25f);stage.animate().translationY(0).alpha(1).setDuration(180).setInterpolator(new android.view.animation.DecelerateInterpolator()).start();}
 @Override protected void onDetachedFromWindow(){animate().cancel();if(velocity!=null){velocity.recycle();velocity=null;}super.onDetachedFromWindow();}
}
