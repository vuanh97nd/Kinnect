package app.kinnect.live;

import android.app.Service;
import android.content.Intent;
import android.os.Binder;
import android.os.IBinder;

/** Google Play flavor stub: Live Game screen-sharing foreground service is disabled on Play. */
public final class LiveGameService extends Service {
 static final String START = "live.game.start", STOP = "live.game.stop", PAUSE = "live.game.pause", MIC = "live.game.mic";
 interface Controls { void stop(); void pause(); void mic(); void reply(String text); }
 final class SessionBinder extends Binder { LiveGameService service() { return LiveGameService.this; } }
 @Override public IBinder onBind(Intent intent) { return null; }
 @Override public int onStartCommand(Intent intent, int flags, int id) { stopSelf(); return START_NOT_STICKY; }
 boolean attach(Controls value) { stopSelf(); return false; }
 void overlayVisible(boolean visible) {}
 void viewers(int count) {}
 void comment(String name, String text) {}
 void flags(boolean pause, boolean mute) {}
 void detach() { stopSelf(); }
}
