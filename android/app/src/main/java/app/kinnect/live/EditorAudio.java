package app.kinnect.live;
import android.content.Context;
import android.media.*;
import android.net.Uri;
import java.io.*;
import java.nio.*;
import java.net.*;
import java.util.*;

/** Mixes optional music and original sound, then muxes the edited video without re-encoding it again. */
final class EditorAudio {
  private static final int RATE=44100;
  private static final class Pcm {File file;int rate,channels;boolean floating;Pcm(File f){file=f;}}
  static void merge(Context c,File video,Uri original,String musicURL,Uri musicUri,String cookie,float originalGain,float musicGain,float offset,float originalOffset,float speed,long durationMs,File out)throws Exception{
    List<File> temporary=new ArrayList<>();MediaExtractor v=new MediaExtractor();MediaMuxer mux=null;MediaCodec encoder=null;PcmMixer old=null,music=null;boolean started=false;
    try{
      Pcm a=originalGain>0?decode(c,original,temporary):null;
      if(a!=null)old=new PcmMixer(a.file,a.rate,a.channels,a.floating,false);
      Uri selected=musicUri;
      if(musicURL!=null){File downloaded=File.createTempFile("kinnect-music-",".audio",c.getCacheDir());temporary.add(downloaded);HttpURLConnection connection=(HttpURLConnection)new URL(musicURL).openConnection();connection.setConnectTimeout(15000);connection.setReadTimeout(30000);connection.setInstanceFollowRedirects(false);if(cookie!=null&&!cookie.isEmpty())connection.setRequestProperty("Cookie",cookie);
        try{if(connection.getResponseCode()!=200)throw new IOException("Không tải được nhạc đã chọn.");try(InputStream in=connection.getInputStream();OutputStream dst=new FileOutputStream(downloaded)){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException();dst.write(b,0,n);}}}finally{connection.disconnect();}selected=Uri.fromFile(downloaded);
      }
      Pcm b=selected!=null&&musicGain>0?decode(c,selected,temporary):null;if(selected!=null&&musicGain>0&&b==null)throw new IOException("Tệp nhạc không có âm thanh.");
      if(b!=null)music=new PcmMixer(b.file,b.rate,b.channels,b.floating,true);
      if(old==null&&music==null){copy(video,out);return;}
      v.setDataSource(video.getAbsolutePath());int inputVideo=-1;for(int i=0;i<v.getTrackCount();i++)if(v.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("video/")){inputVideo=i;break;}
      if(inputVideo<0)throw new IOException("Không có hình ảnh video đã chỉnh.");v.selectTrack(inputVideo);MediaFormat vf=v.getTrackFormat(inputVideo);
      mux=new MediaMuxer(out.getAbsolutePath(),MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);int outVideo=mux.addTrack(vf),outAudio=-1;
      MediaFormat audio=MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC,RATE,2);audio.setInteger(MediaFormat.KEY_AAC_PROFILE,MediaCodecInfo.CodecProfileLevel.AACObjectLC);audio.setInteger(MediaFormat.KEY_BIT_RATE,160000);audio.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE,16384);
      encoder=MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC);encoder.configure(audio,null,null,MediaCodec.CONFIGURE_FLAG_ENCODE);encoder.start();
      long total=Math.max(1,durationMs)*RATE/1000,position=0,lastProgress=android.os.SystemClock.elapsedRealtime();boolean inputDone=false,outputDone=false;MediaCodec.BufferInfo info=new MediaCodec.BufferInfo();
      while(!outputDone){
        if(Thread.currentThread().isInterrupted())throw new InterruptedIOException();
        if(!inputDone){int index=encoder.dequeueInputBuffer(10000);if(index>=0){ByteBuffer input=encoder.getInputBuffer(index);input.clear();input.order(ByteOrder.LITTLE_ENDIAN);int frames=(int)Math.min(input.remaining()/4,total-position);for(int i=0;i<frames;i++){double second=(position+i)/(double)RATE;for(int channel=0;channel<2;channel++)input.putShort(PcmMixer.mixed(old==null?0:old.at(second*speed+originalOffset,channel),music==null?0:music.at(second+offset,channel),originalGain,musicGain));}boolean end=position+frames>=total;encoder.queueInputBuffer(index,0,frames*4,position*1000000/RATE,end?MediaCodec.BUFFER_FLAG_END_OF_STREAM:0);position+=frames;inputDone=end;lastProgress=android.os.SystemClock.elapsedRealtime();}}
        int index=encoder.dequeueOutputBuffer(info,10000);
        if(index==MediaCodec.INFO_OUTPUT_FORMAT_CHANGED){if(started)throw new IOException("Định dạng âm thanh thay đổi bất thường.");outAudio=mux.addTrack(encoder.getOutputFormat());mux.start();started=true;lastProgress=android.os.SystemClock.elapsedRealtime();}
        else if(index>=0){if(info.size>0&&(info.flags&MediaCodec.BUFFER_FLAG_CODEC_CONFIG)==0){if(!started)throw new IOException("Bộ mã hóa chưa sẵn sàng.");ByteBuffer data=encoder.getOutputBuffer(index);data.position(info.offset);data.limit(info.offset+info.size);mux.writeSampleData(outAudio,data,info);}outputDone=(info.flags&MediaCodec.BUFFER_FLAG_END_OF_STREAM)!=0;encoder.releaseOutputBuffer(index,false);lastProgress=android.os.SystemClock.elapsedRealtime();}
        if(android.os.SystemClock.elapsedRealtime()-lastProgress>15000)throw new IOException("Thiết bị không hoàn tất mã hóa âm thanh.");
      }
      int capacity=vf.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)?Math.max(1024*1024,vf.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)):1024*1024;ByteBuffer sample=ByteBuffer.allocateDirect(capacity);
      while(v.getSampleTrackIndex()>=0){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException();if(android.os.Build.VERSION.SDK_INT>=28){long n=v.getSampleSize();if(n>Integer.MAX_VALUE)throw new IOException("Khung hình quá lớn.");if(n>sample.capacity())sample=ByteBuffer.allocateDirect((int)n);}sample.clear();int n=v.readSampleData(sample,0);if(n<0)break;info.set(0,n,v.getSampleTime(),(v.getSampleFlags()&MediaExtractor.SAMPLE_FLAG_SYNC)!=0?MediaCodec.BUFFER_FLAG_KEY_FRAME:0);mux.writeSampleData(outVideo,sample,info);v.advance();}
      mux.stop();started=false;
    }finally{if(old!=null)old.close();if(music!=null)music.close();if(encoder!=null){try{encoder.stop();}catch(Exception ignored){}encoder.release();}v.release();if(mux!=null){if(started)try{mux.stop();}catch(Exception ignored){}mux.release();}for(File f:temporary)f.delete();}
  }
  private static Pcm decode(Context c,Uri uri,List<File> temporary)throws Exception{
    if(uri==null)return null;MediaExtractor e=new MediaExtractor();MediaCodec codec=null;File file=null;
    try{e.setDataSource(c,uri,null);int track=-1;for(int i=0;i<e.getTrackCount();i++)if(e.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("audio/")){track=i;break;}if(track<0)return null;
      e.selectTrack(track);MediaFormat format=e.getTrackFormat(track);file=File.createTempFile("kinnect-pcm-",".raw",c.getCacheDir());temporary.add(file);Pcm result=new Pcm(file);result.rate=format.getInteger(MediaFormat.KEY_SAMPLE_RATE);result.channels=format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
      codec=MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));codec.configure(format,null,null,0);codec.start();boolean inDone=false,outDone=false;MediaCodec.BufferInfo info=new MediaCodec.BufferInfo();long last=android.os.SystemClock.elapsedRealtime();
      try(OutputStream out=new BufferedOutputStream(new FileOutputStream(file))){while(!outDone){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException();
        if(!inDone){int i=codec.dequeueInputBuffer(10000);if(i>=0){ByteBuffer input=codec.getInputBuffer(i);input.clear();int n=e.readSampleData(input,0);if(n<0){codec.queueInputBuffer(i,0,0,0,MediaCodec.BUFFER_FLAG_END_OF_STREAM);inDone=true;}else{codec.queueInputBuffer(i,0,n,e.getSampleTime(),0);e.advance();}last=android.os.SystemClock.elapsedRealtime();}}
        int i=codec.dequeueOutputBuffer(info,10000);if(i==MediaCodec.INFO_OUTPUT_FORMAT_CHANGED){MediaFormat f=codec.getOutputFormat();result.rate=f.getInteger(MediaFormat.KEY_SAMPLE_RATE);result.channels=f.getInteger(MediaFormat.KEY_CHANNEL_COUNT);result.floating=f.containsKey(MediaFormat.KEY_PCM_ENCODING)&&f.getInteger(MediaFormat.KEY_PCM_ENCODING)==AudioFormat.ENCODING_PCM_FLOAT;}
        else if(i>=0){if(info.size>0){ByteBuffer data=codec.getOutputBuffer(i);data.position(info.offset);byte[] bytes=new byte[info.size];data.get(bytes);out.write(bytes);}outDone=(info.flags&MediaCodec.BUFFER_FLAG_END_OF_STREAM)!=0;codec.releaseOutputBuffer(i,false);last=android.os.SystemClock.elapsedRealtime();}
        if(android.os.SystemClock.elapsedRealtime()-last>15000)throw new IOException("Không giải mã được âm thanh này.");
      }}return result;
    }finally{e.release();if(codec!=null){try{codec.stop();}catch(Exception ignored){}codec.release();}}
  }
  private static void copy(File source,File out)throws IOException{try(InputStream in=new FileInputStream(source);OutputStream dst=new FileOutputStream(out)){byte[] buffer=new byte[65536];int n;while((n=in.read(buffer))!=-1){if(Thread.currentThread().isInterrupted())throw new InterruptedIOException();dst.write(buffer,0,n);}}}
}
