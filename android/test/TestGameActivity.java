package app.kinnect.audit;
import android.app.Activity;import android.os.Bundle;import android.widget.TextView;
/** Local launcher fixture only; never included in production APK. */
public final class TestGameActivity extends Activity {public void onCreate(Bundle b){super.onCreate(b);TextView t=new TextView(this);t.setText("Local game launch fixture");setContentView(t);}}
