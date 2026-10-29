package app.kinnect.live;
import android.graphics.*;import android.graphics.drawable.Drawable;
/** Soft semantic color tile for section actions; navigation and white camera controls stay plain. */
final class FlowIconDrawable extends Drawable {
 private final Drawable glyph;private final Paint paint=new Paint(3);private final int color;
 FlowIconDrawable(Drawable d,String name){glyph=d;String n=name.toLowerCase();color=n.contains("heart")||n.contains("live")||n.contains("radio")?0xffd94688:n.contains("message")||n.contains("phone")||n.contains("call")?0xff20a47c:n.contains("video")||n.contains("clapper")?0xffee674b:n.contains("compass")||n.contains("shield")||n.contains("lock")?0xff1997bd:0xff7652d4;glyph.setTint(color);}
 public void draw(Canvas c){Rect b=getBounds();paint.setShader(new LinearGradient(b.left,b.top,b.right,b.bottom,new int[]{(color&0xffffff)|0x22000000,(color&0xffffff)|0x0c000000},null,Shader.TileMode.CLAMP));c.drawRoundRect(new RectF(b),b.width()*.28f,b.height()*.28f,paint);int inset=Math.max(1,b.width()/12);glyph.setBounds(b.left+inset,b.top+inset,b.right-inset,b.bottom-inset);glyph.draw(c);}
 public void setAlpha(int a){glyph.setAlpha(a);}public void setColorFilter(ColorFilter f){glyph.setColorFilter(f);}public int getOpacity(){return PixelFormat.TRANSLUCENT;}public int getIntrinsicWidth(){return 24;}public int getIntrinsicHeight(){return 24;}
}
