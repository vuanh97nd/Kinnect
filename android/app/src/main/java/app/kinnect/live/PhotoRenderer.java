package app.kinnect.live;

import android.content.Context;
import android.graphics.*;
import android.media.ExifInterface;
import java.io.*;

/** One offline compositor for preview and exported pixels; no network or AI calls. */
final class PhotoRenderer {
  static final class Layout {final Matrix matrix=new Matrix();int width,height;float docW,docH;}
  static Layout layout(PhotoProject p,int side){Layout l=new Layout();float s=Math.min(1f,(float)side/Math.max(p.width,p.height));l.docW=p.width*s;l.docH=p.height*s;l.matrix.setTranslate(-p.left*l.docW,-p.top*l.docH);l.matrix.postScale(p.flip?-1:1,1);l.matrix.postRotate(p.rotation);RectF crop=new RectF(p.left*l.docW,p.top*l.docH,p.right*l.docW,p.bottom*l.docH);l.matrix.mapRect(crop);l.matrix.postTranslate(-crop.left,-crop.top);l.width=Math.max(1,Math.round(crop.width()));l.height=Math.max(1,Math.round(crop.height()));return l;}
  static Bitmap decode(File file,int side)throws IOException {
    BitmapFactory.Options o=new BitmapFactory.Options();o.inJustDecodeBounds=true;BitmapFactory.decodeFile(file.getPath(),o);if(o.outWidth<1||o.outHeight<1)throw new IOException("Không mở được ảnh.");o.inJustDecodeBounds=false;o.inSampleSize=1;while(Math.max(o.outWidth,o.outHeight)/o.inSampleSize>Math.min(side,4096)*1.3f||(long)(o.outWidth/o.inSampleSize)*(o.outHeight/o.inSampleSize)>8500000L)o.inSampleSize*=2;
    Bitmap b=BitmapFactory.decodeFile(file.getPath(),o);if(b==null)throw new IOException("Không mở được ảnh.");Matrix m=new Matrix();try{int orientation=new ExifInterface(file.getPath()).getAttributeInt(ExifInterface.TAG_ORIENTATION,1);switch(orientation){case 2:m.postScale(-1,1);break;case 3:m.postRotate(180);break;case 4:m.postScale(1,-1);break;case 5:m.postRotate(90);m.postScale(-1,1);break;case 6:m.postRotate(90);break;case 7:m.postRotate(270);m.postScale(-1,1);break;case 8:m.postRotate(270);break;}}catch(IOException ignored){}
    if(!m.isIdentity()){Bitmap rotated=Bitmap.createBitmap(b,0,0,b.getWidth(),b.getHeight(),m,true);if(rotated!=b)b.recycle();b=rotated;}return b;
  }
  static Bitmap render(Context context,PhotoProject p,int side)throws IOException {
    Layout l=layout(p,side);if((long)l.width*l.height>8500000L)throw new IOException("Chọn kích thước xuất nhỏ hơn.");Bitmap out=Bitmap.createBitmap(l.width,l.height,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(out);c.drawColor(p.background);c.concat(l.matrix);c.clipRect(p.left*l.docW,p.top*l.docH,p.right*l.docW,p.bottom*l.docH);
    Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);paint.setTypeface(ApprovedTypography.font(context,0));
    try{for(PhotoProject.Layer layer:p.layers){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException();if(!layer.visible)continue;int save=c.save();c.translate(layer.x*l.docW,layer.y*l.docH);c.rotate(layer.angle);c.scale(layer.scale,layer.scale);paint.setAlpha(Math.round(255*layer.opacity));
      if(layer.kind.equals("text")){paint.setColor(layer.color);paint.setAlpha(Math.round(255*layer.opacity));paint.setTextAlign(Paint.Align.CENTER);paint.setTextSize(layer.textSize*l.docW);String[] lines=layer.text.split("\n",-1);for(int i=0;i<lines.length;i++)c.drawText(lines[i],0,(i-(lines.length-1)/2f)*paint.getTextSize()*1.25f,paint);}
      else{Bitmap image=decode(new File(layer.source),Math.max(256,Math.round(side*Math.min(2,layer.scale))));float fit=Math.min(l.docW/image.getWidth(),l.docH/image.getHeight());RectF dest=new RectF(-image.getWidth()*fit/2,-image.getHeight()*fit/2,image.getWidth()*fit/2,image.getHeight()*fit/2);int composited=c.saveLayer(-l.docW,-l.docH,l.docW,l.docH,null);paint.setColor(Color.WHITE);paint.setAlpha(Math.round(255*layer.opacity));c.drawBitmap(image,null,dest,paint);
        if(!layer.strokes.isEmpty()){Bitmap mask=Bitmap.createBitmap(Math.max(1,Math.round(l.docW)),Math.max(1,Math.round(l.docH)),Bitmap.Config.ARGB_8888);Canvas mc=new Canvas(mask);mc.drawColor(Color.WHITE);Paint brush=new Paint(3);brush.setStrokeCap(Paint.Cap.ROUND);brush.setStrokeJoin(Paint.Join.ROUND);brush.setStyle(Paint.Style.STROKE);
          for(PhotoProject.Stroke stroke:layer.strokes){brush.setColor(Color.WHITE);brush.setXfermode(new PorterDuffXfermode(stroke.restore?PorterDuff.Mode.SRC_OVER:PorterDuff.Mode.DST_OUT));brush.setStrokeWidth(Math.max(1,stroke.size*l.docW));brush.setMaskFilter(stroke.softness>0?new BlurMaskFilter(stroke.size*l.docW*stroke.softness*.22f,BlurMaskFilter.Blur.NORMAL):null);Path path=new Path();for(int i=0;i+1<stroke.points.size();i+=2){float x=stroke.points.get(i)*l.docW,y=stroke.points.get(i+1)*l.docH;if(i==0)path.moveTo(x,y);else path.lineTo(x,y);}if(stroke.points.size()==2)path.lineTo(stroke.points.get(0)*l.docW+.1f,stroke.points.get(1)*l.docH);mc.drawPath(path,brush);}
          Paint maskPaint=new Paint(3);maskPaint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.DST_IN));c.drawBitmap(mask,-l.docW/2,-l.docH/2,maskPaint);mask.recycle();}
        c.restoreToCount(composited);image.recycle();}
      c.restoreToCount(save);
    }
    applyColor(out,p);if(p.smooth>0){int w=Math.max(2,out.getWidth()/12),h=Math.max(2,out.getHeight()/12);Bitmap small=Bitmap.createScaledBitmap(out,w,h,true);Canvas soft=new Canvas(out);Paint blend=new Paint(Paint.FILTER_BITMAP_FLAG);blend.setAlpha(Math.round(Math.min(100,p.smooth)*1.2f));soft.drawBitmap(small,null,new Rect(0,0,out.getWidth(),out.getHeight()),blend);small.recycle();}return out;
    }catch(IOException|RuntimeException|OutOfMemoryError error){out.recycle();throw error;}
  }
  private static int clamp(float v){return Math.max(0,Math.min(255,Math.round(v)));}
  private static void applyColor(Bitmap image,PhotoProject p){boolean hsl=false;for(int i=0;i<6;i++)hsl|=p.hue[i]!=0||p.hslSaturation[i]!=0||p.lightness[i]!=0;if(!hsl&&p.brightness==0&&p.contrast==0&&p.saturation==0&&p.warmth==0&&p.curves==0)return;int w=image.getWidth(),h=image.getHeight();int[] row=new int[w];float contrast=1+p.contrast/100f,sat=1+p.saturation/100f;float midpoint=Math.max(.12f,Math.min(.88f,.5f+p.curves/250f));for(int y=0;y<h;y++){if(Thread.currentThread().isInterrupted())return;image.getPixels(row,0,w,0,y,w,1);for(int x=0;x<w;x++){int v=row[x],alpha=v>>>24;float r=(v>>16)&255,g=(v>>8)&255,b=v&255,gray=.2126f*r+.7152f*g+.0722f*b;r=gray+(r-gray)*sat;g=gray+(g-gray)*sat;b=gray+(b-gray)*sat;r=(r-127.5f)*contrast+127.5f+p.brightness*1.7f+p.warmth*.45f;g=(g-127.5f)*contrast+127.5f+p.brightness*1.7f;b=(b-127.5f)*contrast+127.5f+p.brightness*1.7f-p.warmth*.45f;if(p.curves!=0){r=curve(r,midpoint);g=curve(g,midpoint);b=curve(b,midpoint);}if(hsl){row[x]=adjustHsl(alpha,clamp(r),clamp(g),clamp(b),p);}else row[x]=(alpha<<24)|(clamp(r)<<16)|(clamp(g)<<8)|clamp(b);}image.setPixels(row,0,w,0,y,w,1);}}
  private static int adjustHsl(int alpha,int red,int green,int blue,PhotoProject p){
    float r=red/255f,g=green/255f,b=blue/255f,max=Math.max(r,Math.max(g,b)),min=Math.min(r,Math.min(g,b)),delta=max-min,light=(max+min)/2,hue=0,sat=0;
    if(delta>0){sat=delta/Math.max(.0001f,1-Math.abs(2*light-1));if(max==r)hue=60*((g-b)/delta%6);else if(max==g)hue=60*((b-r)/delta+2);else hue=60*((r-g)/delta+4);if(hue<0)hue+=360;}
    float dh=0,ds=0,dl=0;for(int band=0;band<6;band++){float distance=Math.abs(hue-band*60);distance=Math.min(distance,360-distance);float weight=Math.max(0,1-distance/60);dh+=p.hue[band]*weight;ds+=p.hslSaturation[band]*weight;dl+=p.lightness[band]*weight;}
    hue=(hue+dh+360)%360;sat=Math.max(0,Math.min(1,sat*(1+ds/100)));light=Math.max(0,Math.min(1,light+dl/100));float chroma=(1-Math.abs(2*light-1))*sat,x=chroma*(1-Math.abs((hue/60)%2-1)),m=light-chroma/2;int sector=(int)(hue/60);float rr=0,gg=0,bb=0;switch(sector){case 0:rr=chroma;gg=x;break;case 1:rr=x;gg=chroma;break;case 2:gg=chroma;bb=x;break;case 3:gg=x;bb=chroma;break;case 4:rr=x;bb=chroma;break;default:rr=chroma;bb=x;break;}return(alpha<<24)|(clamp((rr+m)*255)<<16)|(clamp((gg+m)*255)<<8)|clamp((bb+m)*255);
  }
  private static float curve(float v,float mid){float t=Math.max(0,Math.min(1,v/255));return 255*(t<=.5f?t*2*mid:mid+(t-.5f)*2*(1-mid));}
}
