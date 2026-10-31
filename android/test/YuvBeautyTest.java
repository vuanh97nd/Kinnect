package app.kinnect.live;
import java.nio.ByteBuffer;
import java.util.Arrays;
public final class YuvBeautyTest {
  public static void main(String[] args){
    int width=21,height=19,stride=24;byte[] original=new byte[stride*height];Arrays.fill(original,(byte)233);
    for(int y=0;y<height;y++)for(int x=0;x<width;x++)original[y*stride+x]=(byte)(x*9);
    ByteBuffer result=ByteBuffer.wrap(original.clone());
    YuvBeauty.warpPlane(result,stride,width,height,original,10,9,8,6,0);
    check(Arrays.equals(original,result.array()),"zero strength preserves frame");
    YuvBeauty.warpPlane(result,stride,width,height,original,10,9,8,6,1);
    check((result.get(9*stride+14)&255)<(original[9*stride+14]&255),"inverse sampling enlarges feature");
    check(result.get(0)==original[0],"outside face unchanged");
    for(int y=0;y<height;y++)for(int x=width;x<stride;x++)check(result.get(y*stride+x)==(byte)233,"stride padding preserved");
    for(float x:new float[]{-4,0,20,25})for(float y:new float[]{-3,0,18,24})YuvBeauty.warpPlane(result,stride,width,height,original,x,y,7,5,1);
    System.out.println("PASS: strength, magnification, boundaries, stride, off-screen face");
  }
  private static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
}
