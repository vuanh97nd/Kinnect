package app.kinnect.live;
import java.io.*;import java.nio.*;
public final class PcmMixerTest {
 public static void main(String[] args)throws Exception{
  File f=File.createTempFile("kinnect-mixer-test-",".pcm");try{
   ByteBuffer data=ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN);for(short v:new short[]{0,16384,0,-16384})data.putShort(v);try(FileOutputStream out=new FileOutputStream(f)){out.write(data.array());}
   try(PcmMixer mono=new PcmMixer(f,4,1,false,false);PcmMixer loop=new PcmMixer(f,4,1,false,true)){
    near(mono.at(.125,0),.25f,"sample-rate interpolation");near(mono.at(.25,1),.5f,"mono to stereo");near(mono.at(3,0),0,"no extra original sound");near(loop.at(1.25,0),.5f,"music loops");near(loop.at(.75,0),-.5f,"negative samples");
   }
   if(PcmMixer.mixed(.8f,.8f,1,1)!=32767||PcmMixer.mixed(-.8f,-.8f,1,1)!=-32768)throw new AssertionError("clipping");
   if(PcmMixer.mixed(.5f,.5f,0,0)!=0)throw new AssertionError("mute");System.out.println("PASS: resampling, stereo, loop, duration, clipping and mute");
  }finally{f.delete();}
 }
 static void near(float a,float b,String message){if(Math.abs(a-b)>.0001f)throw new AssertionError(message+": "+a);}
}
