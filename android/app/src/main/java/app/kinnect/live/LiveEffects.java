package app.kinnect.live;

import android.graphics.*;
import android.media.FaceDetector;
import java.nio.ByteBuffer;
import java.util.concurrent.*;
import org.webrtc.*;

/**
 * Bộ lọc màu và sticker bám khuôn mặt cho phát trực tiếp. Xử lý thẳng trên khung I420
 * (xoay về chiều đứng, chỉnh màu ở kênh Y/U/V, trộn lớp sticker) để không phải đổi sang RGB.
 */
final class LiveEffects implements VideoProcessor {
  static final String[][] FILTERS = FxEngine.FILTERS;
  static final String[][] STICKERS = FxEngine.STICKERS;
  volatile String filter = "none", sticker = "none";
  volatile boolean beautyOn=false;
  volatile float smooth=.72f,blemish=.8f,eyes=.08f,lips=.05f;
  private final FxEngine stamp=new FxEngine();
  private byte[] beautyY,beautyU,beautyV;
  private volatile VideoSink sink;
  private volatile boolean closed;
  private final ExecutorService worker = Executors.newSingleThreadExecutor();
  private volatile boolean detecting;
  private volatile float[] face;
  private int frames, missed;
  private Bitmap overlay;
  private int[] pixels;
  private final Paint emoji = new Paint(Paint.ANTI_ALIAS_FLAG);

  LiveEffects() { emoji.setTextAlign(Paint.Align.CENTER); }

  @Override public void setSink(VideoSink sink) { this.sink = sink; }
  @Override public void onCapturerStarted(boolean success) {}
  @Override public void onCapturerStopped() {}

  void close() { closed=true; sink=null; face=null; worker.shutdownNow(); }

  @Override
  public void onFrameCaptured(VideoFrame frame) {
    VideoSink out = sink;
    if (out == null || closed) return;
    if (filter.equals("none") && sticker.equals("none") && !beautyOn) { out.onFrame(frame); return; }
    VideoFrame.I420Buffer src = frame.getBuffer().toI420();
    try {
      int rotation = frame.getRotation();
      int w = src.getWidth(), h = src.getHeight();
      int ow = rotation % 180 == 0 ? w : h, oh = rotation % 180 == 0 ? h : w;
      JavaI420Buffer dst = JavaI420Buffer.allocate(ow, oh);
      try {
      YuvHelper.I420Rotate(src.getDataY(), src.getStrideY(), src.getDataU(), src.getStrideU(), src.getDataV(), src.getStrideV(),
        dst.getDataY(), dst.getStrideY(), dst.getDataU(), dst.getStrideU(), dst.getDataV(), dst.getStrideV(), w, h, rotation);
      colour(dst);
      frames++;
      if (!sticker.equals("none") || beautyOn) {
        if (frames % 6 == 0 && !detecting) detect(dst);
        if (face != null) {
          if(beautyOn)retouch(dst);
          if(!sticker.equals("none"))stickers(dst);
        }
      }
      VideoFrame next = new VideoFrame(dst, 0, frame.getTimestampNs());
      // The frame owns dst; the finally block releases our reference even if the sink throws.
      out.onFrame(next);
      } finally { dst.release(); }
    } finally {
      src.release();
    }
  }

  // Chỉnh màu trong miền YUV: độ sáng ở Y, sắc độ ở U (xanh lam) / V (đỏ).
  private void colour(JavaI420Buffer b) {
    String f = filter;
    if (f.equals("none")) return;
    int yAdd = 0, uAdd = 0, vAdd = 0;
    float yMul = 1, cMul = 1;
    if (f.equals("warm")) { uAdd = -8; vAdd = 10; }
    else if (f.equals("cool")) { uAdd = 10; vAdd = -6; }
    else if (f.equals("bright")) { yMul = 1.06f; yAdd = 14; cMul = 0.95f; }
    else if (f.equals("mono")) cMul = 0;
    else if (f.equals("vintage")) { cMul = 0.55f; uAdd = -10; vAdd = 8; yAdd = 6; }
    else if(f.equals("clear")){yMul=1.05f;yAdd=3;cMul=1.08f;}
    else if(f.equals("milk")){yMul=.94f;yAdd=16;cMul=.75f;}
    else if(f.equals("peach")){yAdd=7;uAdd=-4;vAdd=8;cMul=1.05f;}
    else if(f.equals("film")){yMul=.92f;yAdd=12;cMul=.7f;uAdd=-10;vAdd=7;}
    else if(f.equals("noir")){yMul=1.4f;yAdd=-45;cMul=0;}
    else if(f.equals("vivid")){yMul=1.08f;yAdd=-8;cMul=1.55f;}
    else if(f.equals("sunset")){yAdd=6;cMul=1.3f;uAdd=-15;vAdd=12;}
    else if(f.equals("candy")){yMul=.95f;yAdd=15;cMul=1.3f;vAdd=5;}
    else if(f.equals("mint")){yAdd=8;cMul=.9f;uAdd=3;vAdd=-8;}
    else if(f.equals("dream")){yMul=.9f;yAdd=22;cMul=.85f;uAdd=4;}
    else if(f.equals("retro")){yMul=1.1f;yAdd=-8;cMul=.9f;uAdd=-8;vAdd=6;}
    else if(f.equals("city")){yMul=1.15f;yAdd=-20;cMul=.7f;}
    else if(f.equals("cinema")){yMul=1.15f;yAdd=-18;cMul=.82f;uAdd=-3;vAdd=4;}
    else if(f.equals("rose")){yAdd=11;cMul=1.12f;uAdd=4;vAdd=10;}
    else if(f.equals("golden")){yAdd=12;cMul=1.2f;uAdd=-12;vAdd=9;}
    else if(f.equals("ice")){yAdd=14;cMul=.75f;uAdd=10;vAdd=-5;}
    else if(f.equals("lavender")){yAdd=14;cMul=.8f;uAdd=10;vAdd=5;}
    else if(f.equals("choco")){yMul=1.1f;yAdd=-15;cMul=.72f;uAdd=-12;vAdd=9;}
    else if(f.equals("polaroid")){yMul=.9f;yAdd=24;cMul=.8f;uAdd=-6;vAdd=5;}
    else if(f.equals("teal")){yMul=1.12f;yAdd=-13;cMul=1.16f;uAdd=8;vAdd=-9;}
    if (yMul != 1 || yAdd != 0) plane(b.getDataY(), b.getStrideY(), b.getWidth(), b.getHeight(), yMul, yAdd, false);
    int cw = (b.getWidth() + 1) / 2, ch = (b.getHeight() + 1) / 2;
    plane(b.getDataU(), b.getStrideU(), cw, ch, cMul, uAdd, true);
    plane(b.getDataV(), b.getStrideV(), cw, ch, cMul, vAdd, true);
  }

  private static void plane(ByteBuffer p, int stride, int w, int h, float mul, int add, boolean chroma) {
    int[] lut = new int[256];
    for (int i = 0; i < 256; i++) {
      float v = chroma ? (i - 128) * mul + 128 + add : i * mul + add;
      lut[i] = Math.max(0, Math.min(255, Math.round(v)));
    }
    for (int y = 0; y < h; y++) {
      int row = y * stride;
      for (int x = 0; x < w; x++) p.put(row + x, (byte) lut[p.get(row + x) & 255]);
    }
  }

  // Nhận diện khuôn mặt trên ảnh xám nửa độ phân giải (android.media.FaceDetector, chạy nền).
  private void detect(JavaI420Buffer b) {
    final int w = (b.getWidth() / 2) & ~1, h = b.getHeight() / 2;
    if (closed || w < 2 || h < 2) return;
    final int[] gray = new int[w * h];
    ByteBuffer y = b.getDataY();
    int stride = b.getStrideY();
    for (int r = 0; r < h; r++) for (int c = 0; c < w; c++) {
      int v = y.get(r * 2 * stride + c * 2) & 255;
      gray[r * w + c] = 0xff000000 | (v << 16) | (v << 8) | v;
    }
    detecting = true;
    try { worker.execute(() -> {
      try {
        Bitmap bmp = Bitmap.createBitmap(gray, w, h, Bitmap.Config.RGB_565);
        FaceDetector.Face[] found = new FaceDetector.Face[1];
        int n = new FaceDetector(w, h, 1).findFaces(bmp, found);
        bmp.recycle();
        if (n > 0 && found[0] != null && found[0].confidence() >= 0.3f) {
          PointF mid = new PointF();
          found[0].getMidPoint(mid);
          float[] next = { mid.x * 2, mid.y * 2, found[0].eyesDistance() * 2, found[0].pose(FaceDetector.Face.EULER_Z) };
          float[] old = face;
          if (old != null) for (int i = 0; i < 4; i++) next[i] = old[i] * 0.4f + next[i] * 0.6f;
          if (!closed) face = next;
          missed = 0;
        } else if (++missed >= 4) face = null;
      } catch (Exception ignored) {
      } finally {
        detecting = false;
      }
    }); } catch (RejectedExecutionException stopped) { detecting=false; }
  }

  private void retouch(JavaI420Buffer b){
    float[] f=face;if(f==null)return;int w=b.getWidth(),h=b.getHeight(),stride=b.getStrideY();
    float ex=f[0],ey=f[1],e=f[2];if(e<8)return;
    int x0=Math.max(2,(int)(ex-e*1.5f)),x1=Math.min(w-3,(int)(ex+e*1.5f)),y0=Math.max(2,(int)(ey-e*.85f)),y1=Math.min(h-3,(int)(ey+e*2));
    ByteBuffer Y=b.getDataY(),U=b.getDataU(),V=b.getDataV();if(beautyY==null||beautyY.length<stride*h)beautyY=new byte[stride*h];byte[] original=beautyY;for(int y=0;y<h;y++)for(int x=0;x<w;x++)original[y*stride+x]=Y.get(y*stride+x);
    double a=Math.toRadians(f[3]);float cos=(float)Math.cos(a),sin=(float)Math.sin(a);
    for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++){
      float dx=x-ex,dy=y-ey,rx=dx*cos+dy*sin,ry=-dx*sin+dy*cos;
      float ellipse=rx*rx/(e*e*1.3f)+(ry-e*.55f)*(ry-e*.55f)/(e*e*2.1f);
      if(ellipse>=1)continue;
      // Exclude both eyes and mouth from smoothing.
      float left=(rx+e*.5f)*(rx+e*.5f)/(e*e*.14f)+ry*ry/(e*e*.05f),right=(rx-e*.5f)*(rx-e*.5f)/(e*e*.14f)+ry*ry/(e*e*.05f);
      float mouth=rx*rx/(e*e*.32f)+(ry-e*1.12f)*(ry-e*1.12f)/(e*e*.08f);
      int cb=U.get((y/2)*b.getStrideU()+x/2)&255,cr=V.get((y/2)*b.getStrideV()+x/2)&255;
      if(left<1||right<1||mouth<1||cb<70||cb>140||cr<125||cr>190)continue;
      int at=y*stride+x,value=original[at]&255,sum=value*2;
      for(int sy=-2;sy<=2;sy+=2)for(int sx=-2;sx<=2;sx+=2)sum+=original[(y+sy)*stride+x+sx]&255;
      float average=sum/11f,difference=Math.abs(value-average),blend=(smooth*.55f+blemish*.18f)*Math.min(1,(1-ellipse)*3);
      if(difference>28)blend*=.15f;
      Y.put(at,(byte)Math.max(0,Math.min(255,Math.round(value*(1-blend)+average*blend+2*blend))));
    }
    if(eyes>.01f||lips>.01f){
      YuvBeauty.warpPlane(Y,stride,w,h,original,ex-cos*e*.5f,ey-sin*e*.5f,e*.58f,e*.42f,eyes);
      YuvBeauty.warpPlane(Y,stride,w,h,original,ex+cos*e*.5f,ey+sin*e*.5f,e*.58f,e*.42f,eyes);
      YuvBeauty.warpPlane(Y,stride,w,h,original,ex-sin*e*1.12f,ey+cos*e*1.12f,e*.65f,e*.37f,lips);
      for(ByteBuffer plane:new ByteBuffer[]{U,V}){
        int s=plane==U?b.getStrideU():b.getStrideV(),cw=(w+1)/2,ch=(h+1)/2;if(plane==U){if(beautyU==null||beautyU.length<s*ch)beautyU=new byte[s*ch];}else if(beautyV==null||beautyV.length<s*ch)beautyV=new byte[s*ch];byte[] before=plane==U?beautyU:beautyV;for(int y=0;y<ch;y++)for(int x=0;x<cw;x++)before[y*s+x]=plane.get(y*s+x);
        YuvBeauty.warpPlane(plane,s,cw,ch,before,(ex-cos*e*.5f)/2,(ey-sin*e*.5f)/2,e*.29f,e*.21f,eyes);
        YuvBeauty.warpPlane(plane,s,cw,ch,before,(ex+cos*e*.5f)/2,(ey+sin*e*.5f)/2,e*.29f,e*.21f,eyes);
        YuvBeauty.warpPlane(plane,s,cw,ch,before,(ex-sin*e*1.12f)/2,(ey+cos*e*1.12f)/2,e*.325f,e*.185f,lips);
      }
    }
  }

  // Vẽ sticker lên lớp trong suốt rồi trộn vào khung I420.
  private void stickers(JavaI420Buffer b) {
    int w = b.getWidth(), h = b.getHeight();
    if (overlay == null || overlay.getWidth() != w || overlay.getHeight() != h) {
      if (overlay != null) overlay.recycle();
      overlay = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
      pixels = new int[w * h];
    }
    overlay.eraseColor(0);
    Canvas c = new Canvas(overlay);
    float[] f = face;
    stamp.sticker=sticker;stamp.drawSticker(c,f,frames);
    overlay.getPixels(pixels, 0, w, 0, 0, w, h);
    ByteBuffer Y = b.getDataY(), U = b.getDataU(), V = b.getDataV();
    int sy = b.getStrideY(), su = b.getStrideU(), sv = b.getStrideV();
    for (int r = 0; r < h; r++) {
      for (int col = 0; col < w; col++) {
        int p = pixels[r * w + col], a = p >>> 24;
        if (a == 0) continue;
        int R = (p >> 16) & 255, G = (p >> 8) & 255, B = p & 255;
        int yv = (66 * R + 129 * G + 25 * B + 128 >> 8) + 16;
        int yi = r * sy + col;
        Y.put(yi, (byte) (((Y.get(yi) & 255) * (255 - a) + yv * a) / 255));
        if ((r & 1) == 0 && (col & 1) == 0) {
          int uv = (-38 * R - 74 * G + 112 * B + 128 >> 8) + 128, vv = (112 * R - 94 * G - 18 * B + 128 >> 8) + 128;
          int ui = (r / 2) * su + col / 2, vi = (r / 2) * sv + col / 2;
          U.put(ui, (byte) (((U.get(ui) & 255) * (255 - a) + uv * a) / 255));
          V.put(vi, (byte) (((V.get(vi) & 255) * (255 - a) + vv * a) / 255));
        }
      }
    }
  }
}
