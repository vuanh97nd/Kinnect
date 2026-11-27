package app.kinnect.audit;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.os.Bundle;
import android.content.Intent;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.Map;
import org.json.JSONArray;

/** Device-runtime regression of real NativeApi and Android Keystore SessionStore.
 * Run only on a disposable emulator; uses synthetic cookies and sends no HTTP.
 */
public final class P1SessionAudit extends Instrumentation {
  private int checks;
  private void check(boolean value, String label) {
    if (!value) throw new AssertionError(label);
    checks++;
  }
  private Object field(Object object, String name) throws Exception {
    Field f = object.getClass().getDeclaredField(name); f.setAccessible(true); return f.get(object);
  }
  private Object invoke(Object object, String name, Class<?>[] types, Object... args) throws Exception {
    Method m = object.getClass().getDeclaredMethod(name, types); m.setAccessible(true); return m.invoke(object, args);
  }
  private void set(Object object, String name, Object value) throws Exception {
    Field f = object.getClass().getDeclaredField(name); f.setAccessible(true); f.set(object, value);
  }
  public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
  public void onStart() {
    Bundle result = new Bundle();
    Object api = null;
    try {
      Context context = getTargetContext();
      Class<?> type = context.getClassLoader().loadClass("app.kinnect.live.NativeApi");
      api = type.getField("shared").get(null);
      String primary = "https://app.kinnect.io.vn";
      String fallback = "https://kinnect-allocation.vuanh97nd.workers.dev";
      String cookie = "kinnect_session=qa_synthetic_not_a_real_login";
      invoke(api, "initialize", new Class<?>[]{Context.class, String.class}, context, primary);
      invoke(api, "clear", new Class<?>[]{});
      invoke(api, "adopt", new Class<?>[]{String.class, String.class}, primary, cookie + "; kinnect_device=qa_synthetic_device");
      Object store = field(api, "sessions");
      check(cookie.equals(invoke(store, "load", new Class<?>[]{String.class}, primary)), "primary saved with real Android Keystore");
      check(Boolean.TRUE.equals(invoke(api, "failoverFrom", new Class<?>[]{String.class}, primary)), "failover elected");
      check("".equals(field(api, "cookie")) && "".equals(field(api, "device")), "no cross-origin cookie or device carry");
      invoke(api, "clearTransientSession", new Class<?>[]{});
      check(cookie.equals(invoke(store, "load", new Class<?>[]{String.class}, primary)), "fallback unauthorized preserves persisted primary");
      invoke(api, "switchBackToPrimary", new Class<?>[]{});
      check(cookie.equals(field(api, "cookie")), "switchback restores primary before explicit logout");
      invoke(api, "clear", new Class<?>[]{});
      check("".equals(invoke(store, "load", new Class<?>[]{String.class}, primary)), "primary explicit logout wipes saved session");
      invoke(api, "adopt", new Class<?>[]{String.class, String.class}, primary, cookie + "; kinnect_device=qa_synthetic_device");
      check(Boolean.TRUE.equals(invoke(api, "failoverFrom", new Class<?>[]{String.class}, primary)), "second failover elected");
      invoke(api, "clear", new Class<?>[]{});
      check("".equals(invoke(store, "load", new Class<?>[]{String.class}, primary)), "fallback explicit logout wipes primary saved session");
      check("".equals(field(api, "cookie")) && "".equals(field(api, "device")), "explicit logout clears in-memory credentials");
      invoke(api, "switchBackToPrimary", new Class<?>[]{});
      check("".equals(field(api, "cookie")), "switchback cannot resurrect explicitly logged-out session");
      check(context.getSharedPreferences("native_session", 0).getAll().isEmpty(), "saved auth preferences empty");
      final Object activeApi = api;
      final Throwable[] feedError = new Throwable[1];
      runOnMainSync(() -> {
        try {
          // Construct the actual Activity without launching its lifecycle or network.
          Activity activity = newActivity(context.getClassLoader(), "app.kinnect.live.MainActivity", new Intent());
          Class<?> refreshType = context.getClassLoader().loadClass("app.kinnect.live.MainActivity$RefreshLoader");
          final int[] refreshes = {0};
          Object refresh = Proxy.newProxyInstance(context.getClassLoader(), new Class<?>[]{refreshType}, (proxy, method, args) -> {
            if (method.getName().equals("run")) { refreshes[0]++; ((Runnable)args[0]).run(); }
            return null;
          });
          set(activity, "feedRows", new JSONArray("[{\"id\":\"old_post\"}]"));
          set(activity, "feedRefresh", refresh);
          set(activity, "retainedFeedRefresh", refresh);
          set(activity, "retainedFeedContent", new android.widget.LinearLayout(context));
          String key = field(activeApi, "epoch") + ":" + field(activeApi, "origin") + "/api/posts";
          Map snapshots = (Map)field(activeApi, "snapshots");
          snapshots.put(key, "stale-sentinel");
          invoke(activity, "refreshAfterPostMutation", new Class<?>[]{});
          check(field(activity, "feedRows") == null, "post mutation clears stale rows");
          check(field(activity, "retainedFeedContent") == null && field(activity, "retainedFeedRefresh") == null, "post mutation invalidates retained content and refresh owner");
          check(Boolean.TRUE.equals(field(activity, "postsGetSnapshotStale")), "post mutation marks GET snapshot stale");
          check(!snapshots.containsKey(key), "post mutation removes stale ETag snapshot");
          check(refreshes[0] == 1, "post mutation triggers one active refresh");
        } catch (Throwable error) { feedError[0] = error; }
      });
      if (feedError[0] != null) throw new AssertionError("Feed mutation regression", feedError[0]);
      result.putString("result", "PASS " + checks + " checks: real NativeApi + Android Keystore session and Activity feed invalidation; synthetic local-only credentials, no HTTP/lifecycle");
      finish(Activity.RESULT_OK, result);
    } catch (Throwable error) {
      result.putString("error", error.toString());
      result.putInt("checksPassed", checks);
      finish(Activity.RESULT_CANCELED, result);
    } finally {
      try { if (api != null) invoke(api, "clear", new Class<?>[]{}); } catch (Exception ignored) {}
    }
  }
}
