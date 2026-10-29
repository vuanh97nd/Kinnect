package app.kinnect.live;
import java.nio.ByteBuffer;
/** Bounded inverse warp shared by luminance and chroma planes. */
final class YuvBeauty {
  static void warpPlane(ByteBuffer target,int stride,int width,int height,byte[] source,float cx,float cy,float rx,float ry,float amount){
    if(amount<=.01f)return;int x0=Math.max(0,(int)(cx-rx)),x1=Math.min(width-1,(int)(cx+rx)),y0=Math.max(0,(int)(cy-ry)),y1=Math.min(height-1,(int)(cy+ry));
    for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++){
      float dx=x-cx,dy=y-cy,r=dx*dx/(rx*rx)+dy*dy/(ry*ry);if(r>=1)continue;float scale=1-amount*.32f*(1-r)*(1-r);
      int sx=Math.max(0,Math.min(width-1,Math.round(cx+dx*scale))),sy=Math.max(0,Math.min(height-1,Math.round(cy+dy*scale)));target.put(y*stride+x,source[sy*stride+sx]);
    }
  }

}
