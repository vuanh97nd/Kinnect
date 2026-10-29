package app.kinnect.live;

import android.content.*;import android.net.Uri;import android.media.*;import android.os.*;
import java.io.*;import java.nio.*;import java.nio.channels.FileChannel;

/** PCM16 mixer BEFORE WebRTC encoding. No speaker-to-mic recording of backing tracks. */
final class LiveAudioMix implements AutoCloseable {
 volatile boolean mic=true,playing,gameEnabled;volatile float voiceGain=1,musicGain=.65f,echo;
 volatile long positionFrames;private int sourceRate=48000;private ByteBuffer song;private File songFile;
 private volatile AudioTrack monitor;private final short[] monitorBuffer=new short[1920],echoBuffer=new short[48000];private int echoAt;
 private final short[] gameRing=new short[48000];private int gameRead,gameWrite;private AudioRecord gameRecord;private Thread gameThread;private volatile boolean gameRunning,closed;
 interface Loaded{void done(String error);}
 long durationMs(){ByteBuffer s=song;return s==null?0:(long)s.capacity()*500/sourceRate;}
 long positionMs(){return positionFrames*1000/48000;}
 void seek(long ms){positionFrames=Math.max(0,Math.min(durationMs(),ms))*48;java.util.Arrays.fill(echoBuffer,(short)0);}
 void load(Context context,Uri uri)throws Exception{
  if(closed)throw new IOException("closed");playing=false;
  File out=File.createTempFile("sing-", ".pcm",context.getCacheDir());MediaExtractor extractor=new MediaExtractor();MediaCodec codec=null;boolean ok=false;
  try{extractor.setDataSource(context,uri,null);int track=-1;MediaFormat format=null;
   for(int i=0;i<extractor.getTrackCount();i++){MediaFormat f=extractor.getTrackFormat(i);if(f.getString(MediaFormat.KEY_MIME).startsWith("audio/")){track=i;format=f;break;}}
   if(track<0)throw new IOException("audio");if(format.containsKey(MediaFormat.KEY_DURATION)&&format.getLong(MediaFormat.KEY_DURATION)>600000000L)throw new IOException("duration");
   extractor.selectTrack(track);codec=MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));format.setInteger(MediaFormat.KEY_PCM_ENCODING,AudioFormat.ENCODING_PCM_16BIT);codec.configure(format,null,null,0);codec.start();
   int rate=format.getInteger(MediaFormat.KEY_SAMPLE_RATE),channels=format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);boolean inputDone=false,outputDone=false;MediaCodec.BufferInfo info=new MediaCodec.BufferInfo();long bytes=0,deadline=SystemClock.elapsedRealtime()+90000;
   try(FileOutputStream file=new FileOutputStream(out)){while(!outputDone){if(closed||Thread.currentThread().isInterrupted()||SystemClock.elapsedRealtime()>deadline)throw new IOException("cancel");
    if(!inputDone){int id=codec.dequeueInputBuffer(10000);if(id>=0){ByteBuffer b=codec.getInputBuffer(id);int n=extractor.readSampleData(b,0);if(n<0){codec.queueInputBuffer(id,0,0,0,MediaCodec.BUFFER_FLAG_END_OF_STREAM);inputDone=true;}else{codec.queueInputBuffer(id,0,n,extractor.getSampleTime(),0);extractor.advance();}}}
    int id=codec.dequeueOutputBuffer(info,10000);if(id==MediaCodec.INFO_OUTPUT_FORMAT_CHANGED){MediaFormat f=codec.getOutputFormat();rate=f.getInteger(MediaFormat.KEY_SAMPLE_RATE);channels=f.getInteger(MediaFormat.KEY_CHANNEL_COUNT);if(f.containsKey(MediaFormat.KEY_PCM_ENCODING)&&f.getInteger(MediaFormat.KEY_PCM_ENCODING)!=AudioFormat.ENCODING_PCM_16BIT)throw new IOException("pcm");}
    else if(id>=0){ByteBuffer b=codec.getOutputBuffer(id).order(ByteOrder.LITTLE_ENDIAN);b.position(info.offset);b.limit(info.offset+info.size);if(channels<1||channels>8||rate<8000||rate>96000)throw new IOException("format");byte[] mono=new byte[(info.size/(channels*2))*2];for(int j=0;j<mono.length;j+=2){int sum=0;for(int c=0;c<channels;c++)sum+=b.getShort();int v=sum/channels;mono[j]=(byte)v;mono[j+1]=(byte)(v>>8);}file.write(mono);bytes+=mono.length;if(bytes>rate*2L*600||bytes>115200000)throw new IOException("duration");outputDone=(info.flags&MediaCodec.BUFFER_FLAG_END_OF_STREAM)!=0;codec.releaseOutputBuffer(id,false);}
   }}if(bytes<rate*2)throw new IOException("short");
   ByteBuffer mapped;try(RandomAccessFile f=new RandomAccessFile(out,"r")){mapped=f.getChannel().map(FileChannel.MapMode.READ_ONLY,0,f.length()).order(ByteOrder.LITTLE_ENDIAN);}
   if(closed)throw new IOException("cancel");File old=songFile;sourceRate=rate;songFile=out;positionFrames=0;song=mapped;if(old!=null)old.delete();ok=true;
  }finally{if(codec!=null){try{codec.stop();}catch(Exception ignored){}codec.release();}extractor.release();if(!ok)out.delete();}
 }
 synchronized void monitor(boolean enable){if(monitor!=null){try{monitor.stop();}catch(Exception ignored){}monitor.release();monitor=null;}if(enable&&!closed){try{monitor=new AudioTrack(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build(),new AudioFormat.Builder().setSampleRate(48000).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build(),19200,AudioTrack.MODE_STREAM,AudioManager.AUDIO_SESSION_ID_GENERATE);monitor.play();}catch(Exception ignored){monitor=null;}}}
 long mix(ByteBuffer buffer,int format,int channels,int rate,int bytes,long timestamp){if(closed||format!=AudioFormat.ENCODING_PCM_16BIT||channels<1||rate<1)return timestamp;buffer.order(ByteOrder.LITTLE_ENDIAN);int frames=Math.min(bytes,buffer.capacity())/(2*channels),count=Math.min(frames,monitorBuffer.length);ByteBuffer source=song;long pos=positionFrames;boolean run=playing&&source!=null;
  for(int f=0;f<frames;f++){double srcFrame=(pos+f*48000.0/rate)*sourceRate/48000.0;int ix=(int)srcFrame;int music=0;if(run&&ix>=0&&ix*2+3<source.capacity()){double fraction=srcFrame-ix;music=(int)((source.getShort(ix*2)*(1-fraction)+source.getShort(ix*2+2)*fraction)*musicGain);}
   int game=0;synchronized(gameRing){if(gameEnabled&&gameRead!=gameWrite){game=(int)(gameRing[gameRead]*musicGain);gameRead=(gameRead+1)%gameRing.length;}}
   int voice=0;for(int c=0;c<channels;c++)voice+=buffer.getShort((f*channels+c)*2);voice=mic?(int)(voice*voiceGain/channels):0;int wet=(int)(echoBuffer[echoAt]*echo);echoBuffer[echoAt]=(short)clip(voice+wet*.35f);echoAt=(echoAt+1)%Math.max(1,rate/6);int result=clip(voice+wet+music+game);for(int c=0;c<channels;c++)buffer.putShort((f*channels+c)*2,(short)result);if(f<count)monitorBuffer[f]=(short)music;
  }if(run){positionFrames=pos+Math.round(frames*48000.0/rate);if(positionMs()>=durationMs()){playing=false;positionFrames=durationMs()*48;}}
  AudioTrack output=monitor;if(output!=null&&rate==48000&&run)try{output.write(monitorBuffer,0,count,AudioTrack.WRITE_NON_BLOCKING);}catch(Exception ignored){}return timestamp;
 }
 static int clip(float n){return (int)Math.max(-32768,Math.min(32767,n));}
 void startGame(android.media.projection.MediaProjection projection)throws Exception{if(Build.VERSION.SDK_INT<29)throw new IOException("Android 10");stopGame();AudioPlaybackCaptureConfiguration capture=new AudioPlaybackCaptureConfiguration.Builder(projection).addMatchingUsage(AudioAttributes.USAGE_GAME).addMatchingUsage(AudioAttributes.USAGE_MEDIA).excludeUid(android.os.Process.myUid()).build();gameRecord=new AudioRecord.Builder().setAudioPlaybackCaptureConfig(capture).setAudioFormat(new AudioFormat.Builder().setSampleRate(48000).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build()).setBufferSizeInBytes(19200).build();if(gameRecord.getState()!=AudioRecord.STATE_INITIALIZED)throw new IOException("capture");gameRecord.startRecording();gameRunning=true;gameEnabled=true;final AudioRecord record=gameRecord;gameThread=new Thread(()->{short[] buf=new short[960];while(gameRunning){int n=record.read(buf,0,buf.length);if(n<0)break;synchronized(gameRing){for(int i=0;i<n;i++){int next=(gameWrite+1)%gameRing.length;if(next==gameRead)gameRead=(gameRead+1)%gameRing.length;gameRing[gameWrite]=buf[i];gameWrite=next;}}}},"KinnectGameAudio");gameThread.start();}
 void stopGame(){gameEnabled=false;gameRunning=false;AudioRecord record=gameRecord;gameRecord=null;if(record!=null)try{record.stop();}catch(Exception ignored){}if(gameThread!=null)try{gameThread.join(500);}catch(InterruptedException e){Thread.currentThread().interrupt();}gameThread=null;if(record!=null)record.release();synchronized(gameRing){gameRead=gameWrite=0;}}
 public void close(){closed=true;playing=false;stopGame();monitor(false);song=null;if(songFile!=null)songFile.delete();}
}
