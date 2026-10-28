package app.kinnect.live;
import java.io.*;

/** Bounded disk-backed PCM sampling; stereo output supports mono and different sample rates. */
final class PcmMixer implements Closeable {
  private final RandomAccessFile file;private final int channels,rate,bytes;private final boolean floating,loop;
  private final long frames;private final byte[] block;private long start=-1;private int loaded;
  PcmMixer(File path,int sampleRate,int channelCount,boolean pcmFloat,boolean looping)throws IOException{
    channels=channelCount;rate=sampleRate;floating=pcmFloat;bytes=pcmFloat?4:2;loop=looping;
    if(channels<1||channels>8||rate<=0)throw new IOException("Thông số âm thanh không hợp lệ.");file=new RandomAccessFile(path,"r");frames=file.length()/(channels*bytes);block=new byte[2048*channels*bytes];
  }
  private float sample(long frame,int channel)throws IOException{
    if(frames==0)return 0;if(loop)frame=((frame%frames)+frames)%frames;else if(frame<0||frame>=frames)return 0;
    if(frame<start||frame>=start+loaded){start=frame/2048*2048;file.seek(start*channels*bytes);int n=(int)Math.min(block.length,(frames-start)*channels*bytes);file.readFully(block,0,n);loaded=n/(channels*bytes);}
    int at=(int)(frame-start)*channels*bytes+Math.min(channel,channels-1)*bytes;
    if(floating){int bits=(block[at]&255)|((block[at+1]&255)<<8)|((block[at+2]&255)<<16)|(block[at+3]<<24);float v=Float.intBitsToFloat(bits);return Float.isNaN(v)||Float.isInfinite(v)?0:Math.max(-1,Math.min(1,v));}
    return (short)((block[at]&255)|(block[at+1]<<8))/32768f;
  }
  float at(double seconds,int channel)throws IOException{double frame=Math.max(0,seconds)*rate;long i=(long)frame;float fraction=(float)(frame-i);return sample(i,channel)*(1-fraction)+sample(i+1,channel)*fraction;}
  static short mixed(float original,float music,float originalGain,float musicGain){return (short)Math.round(Math.max(-1,Math.min(.9999695f,original*originalGain+music*musicGain))*32768);}
  public void close()throws IOException{file.close();}
}
