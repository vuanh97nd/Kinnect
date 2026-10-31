package app.kinnect.live;

import android.app.Activity;
import android.content.Context;
import android.content.pm.ActivityInfo;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.view.WindowInsets;
import android.view.animation.DecelerateInterpolator;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Locale;
import java.util.UUID;

/** Full-screen landscape farm game with its own launch logo and a lightweight HUD over the 3D scene. */
public class FarmActivity extends Activity {
  private final Handler handler = new Handler(Looper.getMainLooper());
  private final Runnable farmReload = new Runnable() {
    @Override public void run() { if (active) loadFarm(); }
  };
  private Farm3DView farm3d;
  private JSONObject farmState;
  private TextView levelChip, coinChip, loadingChip;
  private TextView missionChip;
  private FrameLayout splash;
  private boolean active;

  @Override protected void attachBaseContext(Context base) {
    super.attachBaseContext(I18n.localized(base));
  }

  @Override protected void onCreate(Bundle state) {
    super.onCreate(state);
    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    immersive();
    String language = getIntent().getStringExtra("language");
    if ("vi".equals(language) || "en".equals(language)) I18n.select(this, language);
    String origin = getIntent().getStringExtra("origin");
    if (origin == null || origin.isEmpty()) origin = ServerConfig.DEFAULT_ORIGIN;
    NativeApi.shared.initialize(this, origin);
    String session = getIntent().getStringExtra("session");
    if (session != null && !session.isEmpty()) NativeApi.shared.adopt(origin, session);
    active = true;
    FrameLayout root = new FrameLayout(this);
    root.setBackgroundColor(0xff07160e);
    farm3d = new Farm3DView(this);
    farm3d.setOnPlotTapListener(this::onPlotTap);
    root.addView(farm3d, new FrameLayout.LayoutParams(-1, -1));
    root.addView(buildHud(), new FrameLayout.LayoutParams(-1, -1));
    splash = buildSplash();
    root.addView(splash, new FrameLayout.LayoutParams(-1, -1));
    setContentView(root);
    loadFarm();
    handler.postDelayed(this::dismissSplash, 2300);
  }

  private void immersive() {
    getWindow().setStatusBarColor(Color.TRANSPARENT);
    getWindow().setNavigationBarColor(Color.TRANSPARENT);
    getWindow().getDecorView().setSystemUiVisibility(
      View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        | View.SYSTEM_UI_FLAG_FULLSCREEN);
  }

  private View buildHud() {
    FrameLayout hud = new FrameLayout(this);
    LinearLayout top = row();
    top.setPadding(dp(8), dp(6), dp(10), dp(6));
    GradientDrawable topBg = round(0xbb081b12, 18);
    topBg.setStroke(dp(1), 0x33ffffff);
    top.setBackground(topBg);
    FrameLayout back = new FrameLayout(this);
    back.setBackground(round(0x33000000, 99));
    back.addView(icon("back", 20, Color.WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    back.setContentDescription(I18n.t("Quay lại"));
    back.setOnClickListener(v -> finish());
    top.addView(back, new LinearLayout.LayoutParams(dp(34), dp(34)));
    LinearLayout titles = column();
    titles.setPadding(dp(9), 0, dp(10), 0);
    titles.addView(text("Nông trại", 15, Color.WHITE, true));
    TextView brand = text("KINNECT", 8, 0xfff0c766, true);
    brand.setLetterSpacing(0.25f);
    titles.addView(brand);
    top.addView(titles);
    top.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    levelChip = chip("Cấp 1 · 0/25 XP", 0xffc7e7d3);
    top.addView(levelChip, chipParams(dp(4)));
    coinChip = chip("0 xu", 0xfff0c766);
    top.addView(coinChip, chipParams(0));
    FrameLayout.LayoutParams topLp = new FrameLayout.LayoutParams(-1, -2, Gravity.TOP);
    topLp.setMargins(dp(12), dp(9), dp(12), 0);
    hud.addView(top, topLp);

    LinearLayout bottom = row();
    bottom.setPadding(dp(8), dp(6), dp(8), dp(6));
    GradientDrawable bottomBg = round(0xbb081b12, 18);
    bottomBg.setStroke(dp(1), 0x33ffffff);
    bottom.setBackground(bottomBg);
    Button shop = gameButton("Cửa hàng", true, this::shop);
    bottom.addView(shop, new LinearLayout.LayoutParams(dp(142), dp(36)));
    Button missions = gameButton("Nhiệm vụ 0/3", false, this::missionsSheet);
    missionChip = missions;
    LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(dp(156), dp(36));
    mp.leftMargin = dp(8);
    bottom.addView(missions, mp);
    TextView hint = text("Kéo để xoay · Chạm ô đất để chọn", 10, 0xccffffff, false);
    hint.setPadding(dp(12), 0, dp(4), 0);
    bottom.addView(hint, new LinearLayout.LayoutParams(0, -2, 1));
    FrameLayout.LayoutParams bottomLp = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
    bottomLp.setMargins(dp(12), 0, dp(12), dp(9));
    hud.addView(bottom, bottomLp);

    loadingChip = text("Đang tải nông trại…", 12, Color.WHITE, false);
    loadingChip.setGravity(Gravity.CENTER);
    loadingChip.setPadding(dp(14), dp(8), dp(14), dp(8));
    loadingChip.setBackground(round(0xaa000000, 99));
    loadingChip.setOnClickListener(v -> loadFarm());
    loadingChip.setVisibility(View.GONE);
    hud.addView(loadingChip, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
    hud.setOnApplyWindowInsetsListener((v, insets) -> {
      if (Build.VERSION.SDK_INT >= 30) {
        Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
        topLp.topMargin = dp(9) + bars.top;
        bottomLp.bottomMargin = dp(9) + bars.bottom;
        top.setLayoutParams(topLp);
        bottom.setLayoutParams(bottomLp);
      }
      return insets;
    });
    return hud;
  }

  private FrameLayout buildSplash() {
    FrameLayout overlay = new FrameLayout(this);
    overlay.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR,
      new int[]{0xff04160e, 0xff0c3422, 0xff061d13}));
    LinearLayout column = column();
    column.setGravity(Gravity.CENTER_HORIZONTAL);
    FarmLogoView logo = new FarmLogoView(this);
    column.addView(logo, new LinearLayout.LayoutParams(dp(148), dp(148)));
    TextView title = text("NÔNG TRẠI", 27, Color.WHITE, true);
    title.setLetterSpacing(0.16f);
    title.setGravity(Gravity.CENTER);
    LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(-2, -2);
    tp.topMargin = dp(2);
    column.addView(title, tp);
    TextView brand = text("KINNECT", 12, 0xfff0c766, true);
    brand.setLetterSpacing(0.55f);
    brand.setGravity(Gravity.CENTER);
    column.addView(brand);
    View line = new View(this);
    line.setBackground(round(0x66e9c46a, 99));
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(54), Math.max(1, dp(1)));
    lp.topMargin = dp(10);
    lp.bottomMargin = dp(8);
    column.addView(line, lp);
    column.addView(text("Gieo hạt · Chăm vườn · Kết nối", 11, 0xffb9d8c6, false));
    overlay.addView(column, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));

    TextView foot = text("KINNECT · NÔNG TRẠI 3D", 9, 0x88ffffff, true);
    foot.setLetterSpacing(0.2f);
    FrameLayout.LayoutParams fp = new FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
    fp.bottomMargin = dp(12);
    overlay.addView(foot, fp);

    logo.setAlpha(0f);
    logo.setScaleX(0.8f);
    logo.setScaleY(0.8f);
    logo.setRotation(-8f);
    logo.animate().alpha(1f).scaleX(1f).scaleY(1f).rotation(0f)
      .setStartDelay(80).setDuration(650).setInterpolator(new DecelerateInterpolator()).start();
    title.setAlpha(0f);
    title.setTranslationY(dp(8));
    title.animate().alpha(1f).translationY(0).setStartDelay(300).setDuration(450).start();
    brand.setAlpha(0f);
    brand.animate().alpha(1f).setStartDelay(430).setDuration(400).start();
    return overlay;
  }

  private void dismissSplash() {
    FrameLayout current = splash;
    if (current == null || isFinishing() || isDestroyed()) return;
    splash = null;
    current.animate().alpha(0f).setDuration(320).withEndAction(() -> {
      ViewParent parent = current.getParent();
      if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(current);
      if (farmState == null && loadingChip != null) loadingChip.setVisibility(View.VISIBLE);
    }).start();
  }

  private void loadFarm() {
    if (!active) return;
    if (farmState == null && splash == null && loadingChip != null) {
      loadingChip.setVisibility(View.VISIBLE);
      loadingChip.setText(I18n.t("Đang tải nông trại…"));
    }
    NativeApi.shared.call("GET", "/api/farm", null, (data, error, status) -> {
      if (!active || isFinishing() || isDestroyed()) return;
      if (error != null) {
        if (loadingChip != null) {
          loadingChip.setText(I18n.t("Chưa tải được nông trại. Chạm để thử lại."));
          if (splash == null) loadingChip.setVisibility(View.VISIBLE);
        }
        return;
      }
      farmState = data;
      if (loadingChip != null) loadingChip.setVisibility(View.GONE);
      renderFarm();
    });
  }

  private void renderFarm() {
    if (farmState == null) return;
    int level = farmState.optInt("level", 1);
    int xp = farmState.optInt("xp", 0);
    int next = Math.max(1, farmState.optInt("nextXp", 25));
    levelChip.setText(I18n.t("Cấp ") + level + " · " + xp + "/" + next + " XP");
    coinChip.setText(number(farmState.optLong("coins", 0)) + " " + I18n.t("xu"));
    JSONObject missions = farmState.optJSONObject("missions");
    if (missions != null) {
      JSONObject progress = missions.optJSONObject("progress");
      JSONObject targets = missions.optJSONObject("targets");
      int done = 0;
      if (progress != null && targets != null) {
        if (progress.optInt("plant") >= targets.optInt("plant", 3)) done++;
        if (progress.optInt("harvest") >= targets.optInt("harvest", 5)) done++;
        if (progress.optInt("buy") >= targets.optInt("buy", 2)) done++;
      }
      boolean claimable = missions.optBoolean("claimable");
      missionChip.setText(I18n.t("Nhiệm vụ ") + done + "/3" + (claimable ? " · " + I18n.t("Thưởng") : ""));
      missionChip.setTextColor(claimable ? 0xfff0c766 : Color.WHITE);
    }
    if (farm3d != null) farm3d.setFarm(farmState);
    handler.removeCallbacks(farmReload);
    JSONArray plots = farmState.optJSONArray("plots");
    if (plots != null) {
      long soonest = Long.MAX_VALUE;
      for (int i = 0; i < plots.length(); i++) {
        JSONObject plot = plots.optJSONObject(i);
        if (plot == null || plot.optString("cropId").isEmpty()) continue;
        long remaining = plot.optLong("remaining", 0);
        if (remaining > 0 && remaining < soonest) soonest = remaining;
      }
      if (soonest != Long.MAX_VALUE) handler.postDelayed(farmReload, soonest + 600);
    }
  }

  private void onPlotTap(int slot) {
    if (farmState == null) return;
    JSONArray plots = farmState.optJSONArray("plots");
    JSONObject plot = plots != null ? plots.optJSONObject(slot) : null;
    if (plot == null) return;
    if (plot.optString("cropId").isEmpty()) seedPicker(slot);
    else plotSheet(plot);
  }

  private void seedPicker(int slot) {
    if (farmState == null) return;
    JSONArray crops = farmState.optJSONArray("crops");
    JSONObject inventory = farmState.optJSONObject("inventory");
    JSONObject seeds = inventory != null ? inventory.optJSONObject("seeds") : null;
    ArrayList<String> labels = new ArrayList<>(), ids = new ArrayList<>();
    if (crops != null && seeds != null) for (int i = 0; i < crops.length(); i++) {
      JSONObject crop = crops.optJSONObject(i);
      if (crop == null) continue;
      int count = seeds.optInt(crop.optString("id"));
      if (count <= 0) continue;
      labels.add(crop.optString("name") + " · " + I18n.t("kho ") + count
        + (crop.optBoolean("unlocked") ? "" : " · " + I18n.t("Cấp ") + crop.optInt("level")));
      ids.add(crop.optString("id"));
    }
    if (labels.isEmpty()) {
      new Sheet(this).setTitle(I18n.t("Chọn hạt giống"))
        .setMessage(I18n.t("Chưa có hạt giống. Mua hạt giống trong cửa hàng rồi quay lại trồng."))
        .setPositiveButton(I18n.t("Mở cửa hàng"), (d, w) -> shop())
        .setNegativeButton(I18n.t("Đóng"), null).show();
      return;
    }
    new Sheet(this).setTitle(I18n.t("Chọn hạt giống"))
      .setItems(labels.toArray(new CharSequence[0]),
        (d, i) -> post("/api/farm/plant", json("slot", slot, "cropId", ids.get(i)), I18n.t("Đã trồng cây")))
      .setNegativeButton(I18n.t("Đóng"), null).show();
  }

  private void shop() {
    if (farmState == null) return;
    JSONArray crops = farmState.optJSONArray("crops");
    JSONArray supplies = farmState.optJSONArray("supplies");
    JSONObject inventory = farmState.optJSONObject("inventory");
    JSONObject seeds = inventory != null ? inventory.optJSONObject("seeds") : null;
    JSONObject stock = inventory != null ? inventory.optJSONObject("supplies") : null;
    ArrayList<String> labels = new ArrayList<>(), ids = new ArrayList<>();
    if (crops != null) for (int i = 0; i < crops.length(); i++) {
      JSONObject crop = crops.optJSONObject(i);
      if (crop == null) continue;
      String id = crop.optString("id");
      int owned = seeds != null ? seeds.optInt(id) : 0;
      labels.add(crop.optString("name") + " · " + crop.optInt("seed") + " " + I18n.t("xu") + " · "
        + I18n.t("kho ") + owned + (crop.optBoolean("unlocked") ? "" : " · " + I18n.t("Cấp ") + crop.optInt("level")));
      ids.add("seed_" + id);
    }
    if (supplies != null) for (int i = 0; i < supplies.length(); i++) {
      JSONObject item = supplies.optJSONObject(i);
      if (item == null) continue;
      int owned = stock != null ? stock.optInt(item.optString("id")) : 0;
      labels.add(item.optString("name") + " · " + item.optInt("price") + " " + I18n.t("xu") + " · " + I18n.t("kho ") + owned);
      ids.add(item.optString("id"));
    }
    if (labels.isEmpty()) return;
    new Sheet(this).setTitle(I18n.t("Cửa hàng nông trại"))
      .setMessage(I18n.t("Mua bằng xu tặng. Chạm một món để mua 1."))
      .setItems(labels.toArray(new CharSequence[0]), (d, i) -> buy(ids.get(i)))
      .setNegativeButton(I18n.t("Đóng"), null).show();
  }

  private void buy(String itemId) {
    post("/api/farm/shop/buy", json("itemId", itemId, "quantity", 1, "requestId", UUID.randomUUID().toString()),
      I18n.t("Đã mua vật phẩm nông trại."));
  }

  private void plotSheet(JSONObject plot) {
    int slot = plot.optInt("slot");
    String name = plot.optString("name");
    long remaining = plot.optLong("remaining", 0);
    boolean watered = plot.optBoolean("watered"), fertilized = plot.optBoolean("fertilized"), pest = plot.optBoolean("pest");
    ArrayList<String> labels = new ArrayList<>(), actions = new ArrayList<>();
    String message;
    if (remaining <= 0) {
      message = I18n.t("Cây đã chín. Thu hoạch để nhận xu tặng và XP.");
      labels.add(I18n.t("Thu hoạch"));
      actions.add("harvest");
    } else {
      message = I18n.t("Còn ") + time(remaining) + " · " + I18n.t("Tưới +10% · Phân +25% xu.");
      if (!watered) { labels.add(I18n.t("Tưới nước") + stock("water")); actions.add("water"); }
      if (!fertilized) { labels.add(I18n.t("Bón phân") + stock("fertilizer")); actions.add("fertilize"); }
      if (pest) { labels.add(I18n.t("Xử lý sâu") + stock("pesticide")); actions.add("treat"); }
      if (labels.isEmpty()) {
        new Sheet(this).setTitle(name)
          .setMessage(I18n.t("Cây đang lớn và đã được chăm sóc đầy đủ. Quay lại khi chín."))
          .setPositiveButton(I18n.t("Đóng"), null).show();
        return;
      }
    }
    new Sheet(this).setTitle(name).setMessage(message)
      .setItems(labels.toArray(new CharSequence[0]), (d, i) -> {
        String action = actions.get(i);
        String path = action.equals("harvest") ? "/api/farm/harvest"
          : action.equals("water") ? "/api/farm/water"
          : action.equals("fertilize") ? "/api/farm/fertilize" : "/api/farm/treat";
        String done = action.equals("harvest") ? I18n.t("Đã thu hoạch")
          : action.equals("water") ? I18n.t("Đã tưới nước")
          : action.equals("fertilize") ? I18n.t("Đã bón phân") : I18n.t("Đã xử lý sâu");
        post(path, json("slot", slot), done);
      }).setNegativeButton(I18n.t("Đóng"), null).show();
  }

  private String stock(String item) {
    int count = 0;
    if (farmState != null) {
      JSONObject inventory = farmState.optJSONObject("inventory");
      JSONObject supplies = inventory != null ? inventory.optJSONObject("supplies") : null;
      if (supplies != null) count = supplies.optInt(item);
    }
    return " · " + (count > 0 ? I18n.t("kho ") + count : I18n.t("chưa có"));
  }

  private void missionsSheet() {
    if (farmState == null) return;
    JSONObject missions = farmState.optJSONObject("missions");
    if (missions == null) return;
    JSONObject progress = missions.optJSONObject("progress");
    JSONObject targets = missions.optJSONObject("targets");
    int plant = progress != null ? progress.optInt("plant") : 0;
    int harvest = progress != null ? progress.optInt("harvest") : 0;
    int buy = progress != null ? progress.optInt("buy") : 0;
    int plantTarget = targets != null ? targets.optInt("plant", 3) : 3;
    int harvestTarget = targets != null ? targets.optInt("harvest", 5) : 5;
    int buyTarget = targets != null ? targets.optInt("buy", 2) : 2;
    String message = I18n.t("Trồng cây") + ": " + Math.min(plant, plantTarget) + "/" + plantTarget + "\n"
      + I18n.t("Thu hoạch") + ": " + Math.min(harvest, harvestTarget) + "/" + harvestTarget + "\n"
      + I18n.t("Mua vật tư") + ": " + Math.min(buy, buyTarget) + "/" + buyTarget + "\n\n"
      + I18n.t("Thưởng") + ": " + missions.optInt("rewardCoins", 30) + " " + I18n.t("xu")
      + " + " + missions.optInt("rewardXp", 20) + " XP";
    Sheet sheet = new Sheet(this).setTitle(I18n.t("Nhiệm vụ hôm nay"))
      .setMessage(message).setNegativeButton(I18n.t("Đóng"), null);
    if (missions.optBoolean("claimable")) {
      sheet.setPositiveButton(I18n.t("Nhận thưởng"),
        (d, w) -> post("/api/farm/missions/claim", new JSONObject(), I18n.t("Đã nhận thưởng nhiệm vụ")));
    }
    sheet.show();
  }

  private void post(String path, JSONObject payload, String success) {
    NativeApi.shared.call("POST", path, payload, (data, error, status) -> {
      if (!active || isFinishing() || isDestroyed()) return;
      if (error != null) { toast(error); return; }
      farmState = data;
      renderFarm();
      JSONObject receipt = data.optJSONObject("receipt");
      if (receipt != null) {
        String message = I18n.t("Thu hoạch ") + receipt.optString("name") + " +" + receipt.optLong("coins") + " " + I18n.t("xu");
        if (receipt.optBoolean("golden")) message += " · " + I18n.t("Vàng");
        toast(message);
      } else toast(success);
    });
  }

  private void toast(String text) {
    String message = I18n.t(text);
    try {
      if (!SuccessEffects.message(this, message)) Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    } catch (RuntimeException ignored) {
      Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }
  }

  private JSONObject json(Object... pairs) {
    JSONObject object = new JSONObject();
    try {
      for (int i = 0; i + 1 < pairs.length; i += 2) object.put(String.valueOf(pairs[i]), pairs[i + 1]);
    } catch (JSONException ignored) { }
    return object;
  }

  private String number(long value) {
    return java.text.NumberFormat.getIntegerInstance(new Locale("vi", "VN")).format(value);
  }

  private static String time(long millis) {
    long seconds = Math.max(0, millis / 1000);
    if (seconds >= 3600) return (seconds / 3600) + "h " + ((seconds % 3600) / 60) + "m";
    if (seconds >= 60) return (seconds / 60) + "m " + (seconds % 60) + "s";
    return seconds + "s";
  }

  private LinearLayout row() {
    LinearLayout view = new LinearLayout(this);
    view.setOrientation(LinearLayout.HORIZONTAL);
    view.setGravity(Gravity.CENTER_VERTICAL);
    return view;
  }

  private LinearLayout column() {
    LinearLayout view = new LinearLayout(this);
    view.setOrientation(LinearLayout.VERTICAL);
    return view;
  }

  private TextView text(String value, int size, int color, boolean bold) {
    TextView view = new KinnectText(this);
    view.setText(I18n.t(value));
    view.setTextSize(size);
    view.setTextColor(color);
    view.setIncludeFontPadding(false);
    view.setTypeface(ApprovedTypography.font(this, bold ? Typeface.BOLD : Typeface.NORMAL));
    return view;
  }

  private TextView chip(String value, int color) {
    TextView view = text(value, 11, color, true);
    view.setGravity(Gravity.CENTER);
    view.setPadding(dp(9), dp(5), dp(9), dp(5));
    view.setBackground(round(0x44000000, 99));
    return view;
  }

  private LinearLayout.LayoutParams chipParams(int left) {
    LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-2, -2);
    params.leftMargin = left;
    return params;
  }

  private Button gameButton(String value, boolean primary, Runnable action) {
    Button button = new KinnectButton(this);
    button.setText(I18n.t(value));
    button.setAllCaps(false);
    button.setTextSize(12);
    button.setTypeface(ApprovedTypography.font(this, Typeface.BOLD));
    button.setTextColor(primary ? 0xff07200f : Color.WHITE);
    button.setBackground(primary ? brandGradient(99) : round(0x33ffffff, 99));
    button.setPadding(dp(8), 0, dp(8), 0);
    button.setOnClickListener(v -> action.run());
    return button;
  }

  private GradientDrawable brandGradient(int radius) {
    GradientDrawable drawable = new GradientDrawable(GradientDrawable.Orientation.TL_BR,
      new int[]{0xfff0cf72, 0xff78c66f});
    drawable.setCornerRadius(dp(radius));
    return drawable;
  }

  private GradientDrawable round(int color, int radius) {
    GradientDrawable drawable = new GradientDrawable();
    drawable.setColor(color);
    drawable.setCornerRadius(dp(radius));
    return drawable;
  }

  private ImageView icon(String name, int size, int color) {
    ImageView view = new ImageView(this);
    int id = WebIcons.resolve(this, name);
    if (id != 0) {
      android.graphics.drawable.Drawable drawable = WebIcons.load(this, name);
      drawable.setTint(color);
      view.setImageDrawable(drawable);
    }
    view.setScaleType(ImageView.ScaleType.FIT_CENTER);
    return view;
  }

  private int dp(int value) {
    return Math.round(value * getResources().getDisplayMetrics().density);
  }

  @Override protected void onDestroy() {
    active = false;
    handler.removeCallbacksAndMessages(null);
    farm3d = null;
    super.onDestroy();
  }
}
