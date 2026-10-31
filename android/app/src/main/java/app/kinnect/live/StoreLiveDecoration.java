package app.kinnect.live;
import android.app.Activity;import android.graphics.*;import android.view.View;
/** Noninteractive, bounded corner frame below controls/comments; no continuous animation cost. */
final class StoreLiveDecoration extends View {
 final Paint p=new Paint(3);final String theme;
 StoreLiveDecoration(Activity a,String theme){super(a);this.theme=theme;setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);setClickable(false);}
 protected void onDraw(Canvas c){super.onDraw(c);if(theme==null||theme.isEmpty())return;float d=getResources().getDisplayMetrics().density,l=9*d,t=74*d,r=getWidth()-9*d,b=getHeight()-12*d,length=34*d;int color=theme.equals("live_chill")?0xff38bdf8:theme.equals("live_spotlight")?0xfffbbf24:0xffa78bfa;p.setShader(new LinearGradient(0,t,getWidth(),b,new int[]{color,0x226d28d9,color},null,Shader.TileMode.CLAMP));p.setStrokeWidth(2*d);p.setStyle(Paint.Style.STROKE);p.setStrokeCap(Paint.Cap.ROUND);for(int x=0;x<2;x++)for(int y=0;y<2;y++){float xx=x==0?l:r,yy=y==0?t:b,dx=x==0?length:-length,dy=y==0?length:-length;c.drawLine(xx,yy,xx+dx,yy,p);c.drawLine(xx,yy,xx,yy+dy,p);}p.setShader(null);}
}
