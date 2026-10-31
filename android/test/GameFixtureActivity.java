package app.kinnect.audit;
import android.app.*;import android.os.*;import android.view.*;import android.media.*;
/** Separate-UID synthetic game fixture; generated tone only, no personal media. */
public class GameFixtureActivity extends Activity {
 volatile boolean playing;AudioTrack track;
 public void onCreate(Bundle b){super.onCreate(b);View v=new View(this);v.setBackgroundColor(0xff2385d0);setContentView(v);playing=true;new Thread(()->{try{track=new AudioTrack.Builder().setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).setAllowedCapturePolicy(AudioAttributes.ALLOW_CAPTURE_BY_ALL).build()).setAudioFormat(new AudioFormat.Builder().setSampleRate(48000).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()).setBufferSizeInBytes(19200).build();track.play();short[] wave=new short[960];int phase=0;while(playing){for(int i=0;i<wave.length;i++)wave[i]=(short)(Math.sin((phase++)*2*Math.PI*660/48000)*10000);track.write(wave,0,wave.length);}track.stop();track.release();}catch(Exception ignored){}},"FixtureTone").start();new Handler().postDelayed(this::finish,25000);}
 protected void onStop(){super.onStop();playing=false;finish();}
 public void onDestroy(){playing=false;super.onDestroy();}
}
