package app.kinnect.live;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.location.*;
import android.os.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import java.net.URLEncoder;
import java.util.*;
import org.json.*;

/** Native Android social client. All application screens use Android views. */
public class MainActivity extends Activity {

  private final NativeApi api = NativeApi.shared;
  private final Handler handler = new Handler(Looper.getMainLooper());
  private LinearLayout root, content, toolbar, bottom;
  private TextView notice;
  private JSONObject me, chatUser;
  private JSONArray shortRows;
  private int shortIndex = 0;
  private VideoView shortVideo;
  private android.media.MediaPlayer shortPlayer;
  private boolean shortMuted = false,
    postingVideo = false;
  private String tab = "feed";
  private int screen = 0;
  private boolean stopped = false;
  private Runnable poll;
  private NativeCalls calls;
  private void ensureCalls(){if(me!=null&&calls==null)calls=new NativeCalls(this,server());}
  private LocationListener locationListener;
  // Màu lấy từ public/theme.css để app và web mobile trông giống nhau; tự theo chế độ sáng/tối của máy.
  private int BG, CARD, TEXT, MUTED, ACCENT, SOFT, LINE, PRIMARY_SOFT;
  private static final int PINK = 0xffff4f9a, WHITE = 0xffffffff;

  private void palette() {
    boolean dark = (getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES;
    BG = dark ? 0xff18191a : 0xfff0f2f5;
    CARD = dark ? 0xff242526 : 0xffffffff;
    TEXT = dark ? 0xffe4e6eb : 0xff1c1e21;
    MUTED = dark ? 0xffb0b3b8 : 0xff65676b;
    ACCENT = dark ? 0xff8b6dff : 0xff6d4aff;
    SOFT = dark ? 0xff3a3b3c : 0xfff2f3f5;
    LINE = dark ? 0xff3a3b3c : 0xffe4e6eb;
    PRIMARY_SOFT = dark ? 0xff2e2752 : 0xffece8ff;
  }

  private GradientDrawable gradient(int radius) {
    GradientDrawable d = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6d4aff, PINK });
    d.setCornerRadius(dp(radius));
    return d;
  }

  private interface Done {
    void accept(JSONObject data);
  }

  @Override
  public void onCreate(Bundle state) {
    boolean night = (getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) == android.content.res.Configuration.UI_MODE_NIGHT_YES;
    setTheme(night ? android.R.style.Theme_Material_NoActionBar : android.R.style.Theme_Material_Light_NoActionBar);
    super.onCreate(state);
    palette();
    api.initialize(this,server());
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    if ((getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK) != android.content.res.Configuration.UI_MODE_NIGHT_YES)
      getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    intro();
    handleLink(getIntent());
    if (!api.cookieFor(server()).isEmpty()) request(
      "GET",
      "/api/me",
      null,
      data -> {
        me = data.optJSONObject("user");
        navigate("feed");
      }
    );
  }

  private String server() {
    return ServerConfig.resolve(
      getSharedPreferences("kinnect_settings", 0).getString("server", null)
    );
  }

  private int dp(int n) {
    return Math.round(n * getResources().getDisplayMetrics().density);
  }

  private GradientDrawable background(int color, int radius) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    return d;
  }

  private TextView label(String text, int size, int color) {
    TextView v = new TextView(this);
    v.setText(text);
    v.setTextColor(color);
    v.setTextSize(size);
    v.setPadding(0, dp(5), 0, dp(5));
    return v;
  }

  private LinearLayout column() {
    LinearLayout v = new LinearLayout(this);
    v.setOrientation(LinearLayout.VERTICAL);
    return v;
  }

  private LinearLayout row() {
    LinearLayout v = new LinearLayout(this);
    v.setOrientation(LinearLayout.HORIZONTAL);
    v.setGravity(Gravity.CENTER_VERTICAL);
    return v;
  }

  private Button button(String text, Runnable action) {
    Button b = new Button(this);
    b.setText(text);
    b.setTextColor(TEXT);
    b.setTextSize(14);
    b.setAllCaps(false);
    b.setStateListAnimator(null);
    b.setTypeface(null, Typeface.BOLD);
    b.setBackground(background(SOFT, 12));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, dp(44));
    p.setMargins(0, dp(6), 0, dp(4));
    b.setLayoutParams(p);
    b.setOnClickListener(v -> action.run());
    return b;
  }

  private Button primary(String text, Runnable action) {
    Button b = button(text, action);
    b.setTextColor(WHITE);
    b.setBackground(gradient(12));
    return b;
  }

  private EditText input(
    LinearLayout parent,
    String hint,
    String value,
    boolean multiline
  ) {
    EditText v = new EditText(this);
    v.setHint(hint);
    v.setContentDescription(hint);
    v.setText(value);
    v.setTextColor(TEXT);
    v.setHintTextColor(MUTED);
    v.setTextSize(15);
    v.setSingleLine(!multiline);
    v.setPadding(dp(14), dp(12), dp(14), dp(12));
    v.setBackground(background(SOFT, 12));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
      -1,
      multiline ? dp(96) : dp(46)
    );
    p.setMargins(0, dp(7), 0, dp(10));
    parent.addView(v, p);
    return v;
  }

  private LinearLayout card() {
    LinearLayout v = column();
    v.setPadding(dp(16), dp(14), dp(16), dp(14));
    GradientDrawable cardBg = background(CARD, 14);
    cardBg.setStroke(1, LINE);
    v.setBackground(cardBg);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.setMargins(0, dp(6), 0, dp(6));
    content.addView(v, p);
    return v;
  }

  private boolean onTabRoot = false;

  private void shell(String title, boolean navigation) {
    onTabRoot = false;
    stopShort();
    stopLocation();
    screen++;
    handler.removeCallbacksAndMessages(null);
    poll = null;
    chatUser = null;
    root = column();
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener((v, insets) -> {
      v.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
      return insets;
    });
    setContentView(root);
    // Thanh trên: logo Kinnect · Live · Tin nhắn · Thông báo · tài khoản
    toolbar = row();
    toolbar.setPadding(dp(14), 0, dp(8), 0);
    toolbar.setBackgroundColor(CARD);
    ImageView logo = new ImageView(this);
    logo.setImageResource(getResources().getIdentifier("kinnect_icon", "drawable", getPackageName()));
    logo.setClipToOutline(true);
    logo.setBackground(background(CARD, 9));
    toolbar.addView(logo, new LinearLayout.LayoutParams(dp(32), dp(32)));
    TextView brand = label("Kinnect", 21, ACCENT);
    brand.setTypeface(null, Typeface.BOLD);
    brand.setPadding(dp(8), 0, 0, 0);
    toolbar.addView(brand, new LinearLayout.LayoutParams(0, -2, 1));
    if (me != null && navigation) {
      toolbar.addView(topIcon("🎥", "Live", tab.equals("live"), () -> navigate("live")));
      toolbar.addView(topIcon("💬", "Tin nhắn", tab.equals("inbox"), () -> navigate("inbox")));
      toolbar.addView(topIcon("🔔", "Thông báo", false, () -> notifications()));
      TextView meButton = label(me.optString("name", "?").isEmpty() ? "?" : me.optString("name").substring(0, 1).toUpperCase(Locale.ROOT), 15, WHITE);
      meButton.setGravity(Gravity.CENTER);
      meButton.setTypeface(null, Typeface.BOLD);
      meButton.setBackground(gradient(999));
      meButton.setContentDescription("Tài khoản");
      meButton.setOnClickListener(v -> meMenu());
      LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(dp(36), dp(36));
      mp.setMargins(dp(6), 0, dp(6), 0);
      toolbar.addView(meButton, mp);
    } else {
      Button settings = topIcon("⚙", "Cài đặt", false, () -> settings());
      toolbar.addView(settings);
    }
    root.addView(toolbar, new LinearLayout.LayoutParams(-1, dp(56)));
    View line = new View(this);
    line.setBackgroundColor(LINE);
    root.addView(line, new LinearLayout.LayoutParams(-1, 1));
    notice = label("", 12, ACCENT);
    notice.setPadding(dp(16), 0, dp(16), 0);
    root.addView(notice);
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    content = column();
    content.setPadding(dp(12), dp(4), dp(12), dp(18));
    scroll.addView(content);
    root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    if (navigation && me != null) {
      TextView heading = label(title, 22, TEXT);
      heading.setTypeface(null, Typeface.BOLD);
      content.addView(heading);
    }
    if (navigation) {
      View top = new View(this);
      top.setBackgroundColor(LINE);
      root.addView(top, new LinearLayout.LayoutParams(-1, 1));
      bottom = row();
      bottom.setBackgroundColor(CARD);
      String[][] items = { { "feed", "⌂", "Bảng tin" }, { "discover", "✦", "Khám phá" }, { "create", "＋", "Quay video" }, { "shorts", "▷", "Video" }, { "profile", "◯", "Hồ sơ" } };
      for (final String[] it : items) {
        if (it[0].equals("create")) {
          FrameLayout holder = new FrameLayout(this);
          TextView plus = label("＋", 24, WHITE);
          plus.setGravity(Gravity.CENTER);
          plus.setPadding(0, 0, 0, 0);
          plus.setBackground(gradient(14));
          plus.setContentDescription(it[2]);
          plus.setOnClickListener(v -> chooseVideo());
          holder.addView(plus, new FrameLayout.LayoutParams(dp(48), dp(38), Gravity.CENTER));
          bottom.addView(holder, new LinearLayout.LayoutParams(0, dp(60), 1));
          continue;
        }
        boolean active = tab.equals(it[0]);
        TextView b = label(it[1] + "\n" + it[2], 11, active ? ACCENT : MUTED);
        b.setGravity(Gravity.CENTER);
        b.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
        b.setContentDescription(it[2]);
        b.setOnClickListener(v -> navigate(it[0]));
        bottom.addView(b, new LinearLayout.LayoutParams(0, dp(60), 1));
      }
      root.addView(bottom);
    }
  }

  private Button topIcon(String glyph, String name, boolean active, Runnable action) {
    Button b = new Button(this);
    b.setText(glyph);
    b.setTextSize(18);
    b.setStateListAnimator(null);
    b.setContentDescription(name);
    b.setPadding(0, 0, 0, 0);
    b.setMinWidth(0);
    b.setMinimumWidth(0);
    b.setBackground(background(active ? PRIMARY_SOFT : CARD, 12));
    b.setOnClickListener(v -> action.run());
    b.setLayoutParams(new LinearLayout.LayoutParams(dp(42), dp(42)));
    return b;
  }

  private void meMenu() {
    final List<String> labels = new ArrayList<>(Arrays.asList("Trang cá nhân", "Cài đặt tài khoản", "Đổi mật khẩu", "Kiểm tra cập nhật APK"));
    final boolean admin = me != null && me.optString("role").equals("admin");
    if (admin) labels.add("Quản trị");
    labels.add("Đăng xuất");
    new Sheet(this).setTitle(me.optString("name") + " · @" + me.optString("username")).setItems(labels.toArray(new String[0]), (d, w) -> {
      String pick = labels.get(w);
      if (pick.equals("Trang cá nhân")) navigate("profile");
      else if (pick.equals("Cài đặt tài khoản")) settings();
      else if (pick.equals("Đổi mật khẩu")) changePassword();
      else if (pick.equals("Kiểm tra cập nhật APK")) ApkUpdates.check(this);
      else if (pick.equals("Quản trị")) admin();
      else confirm("Đăng xuất khỏi Kinnect?", () -> request("POST", "/api/logout", json(), x -> {
        if (calls != null) { calls.close(); calls = null; }
        api.clear();
        me = null;
        intro();
      }));
    }).show();
  }

  private void say(String text) {
    if (notice != null) notice.setText(text);
  }

  private JSONObject json(Object... values) {
    JSONObject obj = new JSONObject();
    try {
      for (int i = 0; i < values.length; i += 2) obj.put(
        String.valueOf(values[i]),
        values[i + 1]
      );
    } catch (JSONException e) {
      throw new IllegalArgumentException(e);
    }
    return obj;
  }

  private String encode(String v) {
    try {
      return URLEncoder.encode(v, "UTF-8");
    } catch (Exception e) {
      return "";
    }
  }

  private void request(String method, String path, JSONObject data, Done done) {
    final int generation = screen;
    api.call(method, path, data, (answer, error, status) -> {
      if (isFinishing() || isDestroyed() || generation != screen) return;
      if (error != null) {
        if (status == 401 && me != null) {
          me = null;
          api.clear();
          auth(false);
        }
        say(error);
        return;
      }
      done.accept(answer);
    });
  }

  private void auth(boolean register) {
    shell("Kinnect", false);
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    LinearLayout panel = card();
    panel.setPadding(dp(20), dp(22), dp(20), dp(22));
    TextView title = label(register ? "Tạo tài khoản mới" : "Chào mừng trở lại", 26, TEXT);
    title.setTypeface(null, Typeface.BOLD);
    panel.addView(title);
    panel.addView(label(register ? "Miễn phí, chỉ mất một phút." : "Đăng nhập để tiếp tục với Kinnect.", 15, MUTED));
    // Hai tab Đăng nhập / Tạo tài khoản như web
    LinearLayout tabs = row();
    tabs.setPadding(dp(4), dp(4), dp(4), dp(4));
    tabs.setBackground(background(SOFT, 14));
    for (int i = 0; i < 2; i++) {
      final boolean reg = i == 1;
      TextView t = label(reg ? "Tạo tài khoản" : "Đăng nhập", 15, reg == register ? TEXT : MUTED);
      t.setGravity(Gravity.CENTER);
      t.setTypeface(null, Typeface.BOLD);
      if (reg == register) t.setBackground(background(CARD, 11));
      t.setOnClickListener(v -> { if (reg != register) auth(reg); });
      tabs.addView(t, new LinearLayout.LayoutParams(0, dp(42), 1));
    }
    LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(-1, -2);
    tp.setMargins(0, dp(14), 0, dp(12));
    panel.addView(tabs, tp);
    final LinearLayout extras = column();
    panel.addView(extras);
    LinearLayout saved = content;
    content = extras;
    if (!register) authExtras();
    content = saved;
    if (!register) {
      TextView divider = label("hoặc dùng tên đăng nhập", 13, MUTED);
      divider.setGravity(Gravity.CENTER);
      panel.addView(divider);
    }
    panel.addView(fieldLabel("Tên đăng nhập"));
    final EditText username = input(panel, "vd: minh_anh", "", false);
    username.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
    username.setTypeface(Typeface.DEFAULT);
    username.setContentDescription("Tên đăng nhập");
    if (register) panel.addView(label("3–30 ký tự: chữ không dấu, số hoặc dấu gạch dưới.", 12, MUTED));
    panel.addView(fieldLabel("Mật khẩu"));
    LinearLayout pwRow = row();
    final EditText password = input(pwRow, "Tối thiểu 6 ký tự", "", false);
    password.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
    password.setTypeface(Typeface.DEFAULT);
    password.setContentDescription("Mật khẩu");
    ((LinearLayout.LayoutParams) password.getLayoutParams()).width = 0;
    ((LinearLayout.LayoutParams) password.getLayoutParams()).weight = 1;
    final TextView toggle = label("Hiện", 14, ACCENT);
    toggle.setTypeface(null, Typeface.BOLD);
    toggle.setPadding(dp(12), 0, dp(4), 0);
    toggle.setOnClickListener(v -> {
      boolean hidden = (password.getInputType() & InputType.TYPE_TEXT_VARIATION_PASSWORD) == InputType.TYPE_TEXT_VARIATION_PASSWORD;
      password.setInputType(InputType.TYPE_CLASS_TEXT | (hidden ? InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD : InputType.TYPE_TEXT_VARIATION_PASSWORD));
      password.setTypeface(Typeface.DEFAULT);
      password.setSelection(password.length());
      toggle.setText(hidden ? "Ẩn" : "Hiện");
    });
    pwRow.addView(toggle);
    panel.addView(pwRow);
    final EditText name;
    if (register) {
      panel.addView(fieldLabel("Tên hiển thị"));
      name = input(panel, "Tên bạn muốn mọi người thấy", "", false);
    } else name = null;
    final CheckBox agree = new CheckBox(this);
    agree.setText("Tôi xác nhận mình đủ 18 tuổi và đồng ý với quy tắc cộng đồng.");
    agree.setTextColor(TEXT);
    if (register) panel.addView(agree);
    if (!register) {
      TextView forgotLink = label("Quên mật khẩu?", 14, ACCENT);
      forgotLink.setTypeface(null, Typeface.BOLD);
      forgotLink.setGravity(Gravity.END);
      forgotLink.setOnClickListener(v -> forgot());
      panel.addView(forgotLink, new LinearLayout.LayoutParams(-1, -2));
    }
    final Button submit = primary(register ? "Tạo tài khoản" : "Đăng nhập", () -> {});
    submit.getLayoutParams().height = dp(50);
    submit.setOnClickListener(v -> {
      if (password.length() < 6) { say("Mật khẩu tối thiểu 6 ký tự."); return; }
      if (register && !agree.isChecked()) { say("Vui lòng xác nhận bạn đủ 18 tuổi."); return; }
      submit.setEnabled(false);
      final int generation = screen;
      api.call("POST", register ? "/api/register" : "/api/login",
        json("username", username.getText().toString(), "password", password.getText().toString(), "name", name == null ? "" : name.getText().toString(), "agree18", agree.isChecked(), "remember", true),
        (data, error, status) -> {
          if (generation != screen || isDestroyed()) return;
          submit.setEnabled(true);
          password.setText("");
          if (error != null) { say(error); return; }
          me = data.optJSONObject("user");
          navigate("feed");
        });
    });
    panel.addView(submit);
    TextView foot = label("Kinnect tôn trọng quyền riêng tư. Tuổi do người dùng tự xác nhận.", 12, MUTED);
    foot.setGravity(Gravity.CENTER);
    content.addView(foot);
    TextView back = label("← Xem lại giới thiệu", 14, ACCENT);
    back.setGravity(Gravity.CENTER);
    back.setPadding(0, dp(10), 0, dp(10));
    back.setOnClickListener(v -> intro());
    content.addView(back);
  }

  private TextView fieldLabel(String text) {
    TextView t = label(text, 14, TEXT);
    t.setTypeface(null, Typeface.BOLD);
    t.setPadding(0, dp(10), 0, 0);
    return t;
  }

  private void navigate(String next) {
    ensureCalls();
    activity();
    tab = next;
    shell(
      next.equals("discover")
        ? "Khám phá"
        : next.equals("shorts")
          ? "Video ngắn"
          : next.equals("feed")
            ? "Bảng tin"
            : next.equals("inbox")
              ? "Tin nhắn"
              : next.equals("live")
                ? "Trực tiếp"
                : "Hồ sơ",
      true
    );
    onTabRoot = true;
    if (next.equals("shorts")) shorts();
    if (next.equals("discover")) discover();
    if (next.equals("feed")) feed();
    if (next.equals("inbox")) inbox();
    if (next.equals("profile")) profile();
    if (next.equals("live")) live();
  }

  private ImageView avatar(JSONObject u, LinearLayout parent, int size) {
    ImageView image = new ImageView(this);
    image.setScaleType(ImageView.ScaleType.CENTER_CROP);
    GradientDrawable round = new GradientDrawable();
    round.setShape(GradientDrawable.OVAL);
    round.setColor(PRIMARY_SOFT);
    image.setBackground(round);
    image.setClipToOutline(true);
    image.setImageBitmap(initials(u, dp(size)));
    image.setContentDescription("Ảnh của " + u.optString("name"));
    parent.addView(image, new LinearLayout.LayoutParams(dp(size), dp(size)));
    String path = u.optString("avatar", "");
    if (!path.isEmpty() && !path.equals("null")) api.image(path, bytes -> {
      if (bytes != null && !isDestroyed() && image.isAttachedToWindow()) {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(bytes, 0, bytes.length, o);
        o.inSampleSize = Math.max(1, Math.max(o.outWidth, o.outHeight) / 512);
        o.inJustDecodeBounds = false;
        Bitmap bitmap = BitmapFactory.decodeByteArray(
          bytes,
          0,
          bytes.length,
          o
        );
        if (bitmap != null) image.setImageBitmap(bitmap);
      }
    });
    return image;
  }


  // Ảnh đại diện mặc định như web: vòng tròn chuyển sắc theo người dùng + chữ cái đầu.
  private Bitmap initials(JSONObject u, int px) {
    px = Math.max(16, px);
    Bitmap b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888);
    Canvas c = new Canvas(b);
    String key = u == null ? "?" : u.optString("id", u.optString("username", "?"));
    float hue = (Math.abs(key.hashCode()) % 360);
    Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    p.setShader(new LinearGradient(0, 0, px, px, Color.HSVToColor(new float[] { hue, 0.62f, 0.95f }), Color.HSVToColor(new float[] { (hue + 40) % 360, 0.7f, 0.85f }), Shader.TileMode.CLAMP));
    c.drawOval(0, 0, px, px, p);
    p.setShader(null);
    p.setColor(Color.WHITE);
    p.setTextAlign(Paint.Align.CENTER);
    p.setTextSize(px * 0.42f);
    p.setFakeBoldText(true);
    String name = u == null ? "?" : u.optString("name", u.optString("username", "?")).trim();
    String letter = name.isEmpty() ? "?" : name.substring(0, 1).toUpperCase(Locale.ROOT);
    c.drawText(letter, px / 2f, px / 2f + px * 0.15f, p);
    return b;
  }

  private void discover() {
    boolean nearby = me != null && me.optBoolean("hasLocation") && discoverSort.equals("near");
    LinearLayout chipsRow = row();
    String[][] sorts = { { "new", "✨ Mới" }, { "active", "🟢 Online" }, { "interests", "💜 Hợp gu" }, { "near", "📍 Gần đây" } };
    for (final String[] item : sorts) chipsRow.addView(chip(item[1], discoverSort.equals(item[0]), () -> {
      discoverSort = item[0];
      if (item[0].equals("near") && (me == null || !me.optBoolean("hasLocation"))) { requestLocation(); return; }
      navigate("discover");
    }));
    HorizontalScrollView scroller = new HorizontalScrollView(this);
    scroller.setHorizontalScrollBarEnabled(false);
    scroller.addView(chipsRow);
    content.addView(scroller);
    EditText search = input(content, "Tìm tên hoặc sở thích", "", false);
    search.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH);
    search.setOnEditorActionListener((v, action, event) -> { loadPeople(search.getText().toString(), nearby); return true; });
    if (discoverSort.equals("near")) content.addView(button("Cập nhật vị trí gần đúng", () -> requestLocation()));
    loadPeople("", nearby);
  }

  private LinearLayout people;

  private void loadPeople(String query, boolean nearby) {
    if (people != null && people.getParent() == content) content.removeView(
      people
    );
    people = column();
    content.addView(people);
    final LinearLayout list = people;
    request(
      "GET",
      "/api/discover?q=" + encode(query) + (nearby ? "&nearby=1" : "") + "&sort=" + (discoverSort.equals("near") ? "new" : discoverSort),
      null,
      data -> {
        JSONArray users = data.optJSONArray("users");
        if (users == null || users.length() == 0) {
          list.addView(
            label(
              "Chưa có thành viên phù hợp. Khoảng cách chỉ có khi cả hai đồng ý chia sẻ vị trí.",
              14,
              MUTED
            )
          );
          return;
        }
        for (int i = 0; i < users.length(); i++) {
          final JSONObject u = users.optJSONObject(i);
          LinearLayout c = column();
          c.setPadding(dp(16), dp(16), dp(16), dp(16));
          c.setBackground(background(CARD, 18));
          LinearLayout.LayoutParams margins = new LinearLayout.LayoutParams(
            -1,
            -2
          );
          margins.setMargins(0, 0, 0, dp(12));
          list.addView(c, margins);
          LinearLayout head = row();
          avatar(u, head, 72);
          LinearLayout text = column();
          text.setPadding(dp(14), 0, 0, 0);
          text.addView(label(u.optString("name"), 20, TEXT));
          text.addView(
            label(
              u.optString("distanceBand", "@" + u.optString("username")),
              12,
              0xff78ddc5
            )
          );
          head.addView(text, new LinearLayout.LayoutParams(0, -2, 1));
          c.addView(head);
          c.addView(label(u.optString("bio", ""), 14, MUTED));
          c.addView(label(join(u.optJSONArray("interests")), 12, ACCENT));
          if (u.optInt("score") > 0) c.addView(
            label(u.optInt("score") + " sở thích chung", 12, MUTED)
          );
          c.addView(button("Xem hồ sơ", () -> person(u)));
        }
      }
    );
  }

  private String join(JSONArray values) {
    List<String> parts = new ArrayList<>();
    if (values != null) for (int i = 0; i < values.length(); i++) parts.add(
      values.optString(i)
    );
    return android.text.TextUtils.join(" · ", parts);
  }

  private void person(JSONObject u) {
    shell(u.optString("name"), true);
    if (!u.optString("cover").isEmpty() && !u.isNull("cover")) mediaView(json("kind", "image", "url", u.optString("cover")), content);
    avatar(u, content, 110);
    content.addView(label("@" + u.optString("username"), 14, MUTED));
    stats(u, content);
    content.addView(label(u.optString("bio"), 17, TEXT));
    content.addView(label(join(u.optJSONArray("interests")), 14, ACCENT));
    content.addView(
      primary(u.optBoolean("following") ? "Bỏ theo dõi" : "Theo dõi", () ->
        request(
          u.optBoolean("following") ? "DELETE" : "POST",
          "/api/users/" + u.optString("id") + "/follow",
          json(),
          d -> person(d.optJSONObject("user"))
        )
      )
    );
    content.addView(button("Nhắn tin", () -> chat(u)));
    content.addView(button("Bài viết", () -> userPosts(u)));
    content.addView(button("Báo cáo", () -> report("user", u.optString("id"))));
    content.addView(
      button("Chặn người này", () ->
        confirm("Chặn " + u.optString("name") + "?", () ->
          request(
            "POST",
            "/api/users/" + u.optString("id") + "/block",
            json(),
            d -> navigate("discover")
          )
        )
      )
    );
    content.addView(button("Quay lại khám phá", () -> navigate("discover")));
  }

  private void confirm(String message, Runnable yes) {
    new Sheet(this)
      .setMessage(message)
      .setPositiveButton("Xác nhận", (d, w) -> yes.run())
      .setNegativeButton("Hủy", null)
      .show();
  }

  private void report(String type, String id) {
    EditText reason = new EditText(this);
    reason.setHint("Mô tả vấn đề ít nhất 5 ký tự");
    new Sheet(this)
      .setTitle("Báo cáo nội dung")
      .setView(reason)
      .setPositiveButton("Gửi", (dialog, w) ->
        request(
          "POST",
          "/api/reports",
          json(
            "targetType",
            type,
            "targetId",
            id,
            "reason",
            reason.getText().toString()
          ),
          data -> say("Đã gửi báo cáo để quản trị viên xem xét.")
        )
      )
      .setNegativeButton("Hủy", null)
      .show();
  }


  private void feed() {
    LinearLayout tabs = row();
    String[][] cats = { { "community", "Cộng đồng" }, { "confessions", "Tâm sự" }, { "questions", "Hỏi đáp" }, { "events", "Sự kiện" }, { "news", "📰 Tin tức" } };
    for (final String[] c : cats) tabs.addView(chip(c[1], feedCategory.equals(c[0]), () -> { feedCategory = c[0]; navigate("feed"); }));
    HorizontalScrollView tabScroll = new HorizontalScrollView(this);
    tabScroll.setHorizontalScrollBarEnabled(false);
    tabScroll.addView(tabs);
    content.addView(tabScroll);
    if (feedCategory.equals("news")) { news(); return; }
    stories();
    LinearLayout composer = card();
    EditText body = new EditText(this);
    body.setHint("Bạn đang nghĩ gì?");
    body.setTextColor(TEXT);
    body.setHintTextColor(MUTED);
    body.setBackground(null);
    composer.addView(body, new LinearLayout.LayoutParams(-1, -2));
    LinearLayout tools = row();
    final Button attach = chip("🖼 Ảnh/Video", false, () -> {});
    attach.setOnClickListener(v -> { pendingMedia = null; attachButton = attach; pickFile(300, "image/*|video/mp4"); });
    tools.addView(attach);
    CheckBox followers = new CheckBox(this);
    followers.setText("Chỉ người theo dõi");
    followers.setTextColor(MUTED);
    tools.addView(followers, new LinearLayout.LayoutParams(0, -2, 1));
    composer.addView(tools);
    Button post = primary("Đăng", () -> {});
    post.setOnClickListener(v -> {
      if (body.getText().toString().trim().isEmpty() && pendingMedia == null) { say("Viết nội dung hoặc chọn ảnh/video."); return; }
      post.setEnabled(false);
      say(pendingMedia == null ? "" : "Đang tải lên…");
      JSONObject payload = json("body", body.getText().toString(), "visibility", followers.isChecked() ? "followers" : "public", "category", feedCategory);
      if (pendingMedia != null) try { payload.put("media", pendingMedia); } catch (JSONException ignored) {}
      request("POST", "/api/posts", payload, d -> { pendingMedia = null; say("Đã đăng bài."); navigate("feed"); });
    });
    composer.addView(post);
    request("GET", "/api/posts?category=" + feedCategory, null, data -> posts(data.optJSONArray("posts"), "Chưa có bài nào ở mục này. Hãy là người đầu tiên chia sẻ."));
  }


  private void inbox() {
    LinearLayout actions = row();
    actions.addView(chip("＋ Tạo nhóm", false, () -> createGroup()));
    actions.addView(chip("🔔 Thông báo", false, () -> notifications()));
    content.addView(actions);
    final LinearLayout direct = column(), groupList = column();
    content.addView(label("Nhóm", 13, MUTED));
    content.addView(groupList);
    content.addView(label("Tin nhắn", 13, MUTED));
    content.addView(direct);
    request("GET", "/api/groups", null, data -> {
      JSONArray groups = data.optJSONArray("groups");
      if (groups == null || groups.length() == 0) groupList.addView(label("Chưa có nhóm nào.", 14, MUTED));
      for (int i = 0; groups != null && i < groups.length(); i++) {
        final JSONObject g = groups.optJSONObject(i);
        JSONObject last = g.optJSONObject("last");
        JSONArray members = g.optJSONArray("members");
        inboxRow(groupList, null, "👥 " + g.optString("name"), (last == null ? (members == null ? 0 : members.length()) + " thành viên" : last.optString("name") + ": " + last.optString("body")), g.optInt("unread"), () -> groupChat(g));
      }
    });
    request("GET", "/api/conversations", null, data -> {
      conversationUsers = data.optJSONArray("users");
      JSONArray users = conversationUsers;
      if (users == null || users.length() == 0) direct.addView(label("Chưa có cuộc trò chuyện. Hãy tìm một người bạn ở Khám phá.", 14, MUTED));
      for (int i = 0; users != null && i < users.length(); i++) {
        final JSONObject u = users.optJSONObject(i);
        JSONObject last = u.optJSONObject("last");
        inboxRow(direct, u, u.optString("name"), last == null ? "@" + u.optString("username") : (last.optBoolean("mine") ? "Bạn: " : "") + last.optString("body"), u.optInt("unread"), () -> chat(u));
      }
    });
  }

  private void chat(JSONObject u) {
    shell(u.optString("name"), true);
    chatUser = u;
    content.addView(button("Gọi thoại",()->{ensureCalls();calls.start(u,"audio");}));
    content.addView(button("Gọi video",()->{ensureCalls();calls.start(u,"video");}));
    LinearLayout messages = column();
    content.addView(messages);
    EditText input = input(content, "Tin nhắn riêng", "", false);
    content.addView(
      primary("Gửi", () ->
        request(
          "POST",
          "/api/users/" + u.optString("id") + "/messages",
          json("body", input.getText().toString()),
          d -> {
            input.setText("");
            loadMessages(u, messages);
          }
        )
      )
    );
    content.addView(button("📎 Gửi ảnh, video hoặc tệp", () -> { attachTarget = "/api/users/" + u.optString("id") + "/messages"; pickFile(303, "*/*"); }));
    content.addView(button("⋯ Tuỳ chọn cuộc trò chuyện", () -> conversationMenu("direct", u.optString("id"), u.optString("name"))));
    content.addView(button("Quay lại hộp thư", () -> navigate("inbox")));
    loadMessages(u, messages);
    poll = () -> {
      if (!stopped && chatUser == u) {
        loadMessages(u, messages);
        handler.postDelayed(poll, 4000);
      }
    };
    handler.postDelayed(poll, 4000);
  }

  private String lastMessages = "";

  private void loadMessages(JSONObject u, LinearLayout list) {
    request(
      "GET",
      "/api/users/" + u.optString("id") + "/messages",
      null,
      data -> {
        JSONArray messages = data.optJSONArray("messages");
        String signature = messages == null ? "" : messages.toString();
        if (signature.equals(lastMessages) && list.getChildCount() > 0) return;
        lastMessages = signature;
        list.removeAllViews();
        for (int i = 0; messages != null && i < messages.length(); i++) {
          JSONObject m = messages.optJSONObject(i);
          boolean own = m.optString("sender").equals(me.optString("id"));
          JSONObject file = m.optJSONObject("attachment");
          TextView text = label(
            (own ? "Bạn: " : u.optString("name") + ": ") + (m.optBoolean("recalled") ? "Tin nhắn đã được thu hồi" : m.optString("body")) + (file == null ? "" : (m.optString("body").isEmpty() ? "" : "\n") + "📎 " + file.optString("name")),
            16,
            TEXT
          );
          if (file != null) text.setOnClickListener(v -> openAttachment(file));
          text.setPadding(dp(14), dp(10), dp(14), dp(10));
          text.setBackground(background(own ? PRIMARY_SOFT : CARD, 16));
          LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
          p.setMargins(own ? dp(28) : 0, dp(4), own ? 0 : dp(28), dp(4));
          list.addView(text, p);
          text.setOnLongClickListener(v -> {
            messageMenu("direct", m, own, () -> { lastMessages = ""; loadMessages(u, list); });
            return true;
          });
        }
      }
    );
  }

  private void profile() {
    request("GET", "/api/me", null, data -> {
      me = data.optJSONObject("user");
      if (!me.isNull("cover") && !me.optString("cover").isEmpty()) mediaView(json("kind", "image", "url", me.optString("cover")), content);
      LinearLayout head = row();
      avatar(me, head, 84);
      LinearLayout who = column();
      who.setPadding(dp(14), 0, 0, 0);
      TextView name = label(me.optString("name"), 22, TEXT);
      name.setTypeface(null, Typeface.BOLD);
      who.addView(name);
      who.addView(label("@" + me.optString("username"), 13, MUTED));
      head.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
      content.addView(head);
      if (!me.optString("bio").isEmpty()) content.addView(label(me.optString("bio"), 15, TEXT));
      if (me.optJSONArray("interests") != null && me.optJSONArray("interests").length() > 0) content.addView(label(join(me.optJSONArray("interests")), 13, ACCENT));
      stats(me, content);
      LinearLayout acts = row();
      Button edit = primary("Sửa hồ sơ", () -> editProfile());
      acts.addView(edit, new LinearLayout.LayoutParams(0, dp(44), 1));
      Button share = button("Cài đặt", () -> meMenu());
      LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(0, dp(44), 1);
      sp.setMargins(dp(8), 0, 0, 0);
      acts.addView(share, sp);
      content.addView(acts);
      TextView section = label("Bài viết", 17, TEXT);
      section.setTypeface(null, Typeface.BOLD);
      section.setPadding(0, dp(14), 0, dp(4));
      content.addView(section);
      request("GET", "/api/posts?user=" + me.optString("id"), null, d -> posts(d.optJSONArray("posts"), "Bạn chưa có bài viết nào."));
    });
  }

  private void editProfile() {
    shell("Sửa hồ sơ", true);
    request("GET", "/api/me", null, data -> {
      me = data.optJSONObject("user");
      avatar(me, content, 88);
      content.addView(
        label(me.optInt("receivedGifts") + " quà thử nghiệm đã nhận", 12, MUTED)
      );
      EditText name = input(
          content,
          "Tên hiển thị",
          me.optString("name"),
          false
        ),
        bio = input(content, "Giới thiệu", me.optString("bio"), true),
        interests = input(
          content,
          "Sở thích, cách nhau bằng dấu phẩy",
          join(me.optJSONArray("interests")).replace(" · ", ", "),
          false
        );
      CheckBox visible = new CheckBox(this);
      visible.setText("Hiển thị trong khám phá");
      visible.setTextColor(MUTED);
      visible.setChecked(me.optBoolean("discoverable"));
      content.addView(visible);
      CheckBox dm = new CheckBox(this);
      dm.setText("Nhận tin từ mọi thành viên");
      dm.setTextColor(MUTED);
      dm.setChecked(me.optString("dmMode").equals("everyone"));
      content.addView(dm);
      content.addView(
        primary("Lưu hồ sơ", () -> {
          JSONArray tags = new JSONArray();
          for (String v : interests.getText().toString().split(","))
            if (!v.trim().isEmpty()) tags.put(v.trim());
          request(
            "PATCH",
            "/api/me",
            json(
              "name",
              name.getText().toString(),
              "bio",
              bio.getText().toString(),
              "interests",
              tags,
              "discoverable",
              visible.isChecked(),
              "dmMode",
              dm.isChecked() ? "everyone" : "mutual"
            ),
            d -> {
              me = d.optJSONObject("user");
              say("Đã lưu hồ sơ.");
            }
          );
        })
      );
      content.addView(
        button("Đổi ảnh đại diện (tối đa 1 MB)", () -> pickAvatar())
      );
      content.addView(button("Đổi ảnh bìa", () -> pickFile(306, "image/*")));
      content.addView(
        button("Tắt và xóa vị trí đã chia sẻ", () ->
          request("PATCH", "/api/me/location", json("enabled", false), d -> {
            me = d.optJSONObject("user");
            say("Đã xóa vị trí. Không hiển thị trong danh sách xung quanh.");
          })
        )
      );
      content.addView(button("Người đã chặn", () -> blocks()));
      content.addView(button("Đổi mật khẩu", () -> changePassword()));
      content.addView(button("Thông báo", () -> notifications()));
      if (me.optString("role").equals("admin")) content.addView(
        primary("Quản trị viên · Quản lý cộng đồng", () -> admin())
      );
      content.addView(
        button("Đăng xuất", () ->
          request("POST", "/api/logout", json(), d -> {
            if(calls!=null){calls.close();calls=null;}
            api.clear();
            me = null;
            auth(false);
          })
        )
      );
    });
  }

  private void blocks() {
    shell("Người đã chặn", true);
    request("GET", "/api/blocks", null, data -> {
      JSONArray users = data.optJSONArray("users");
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        content.addView(
          button("Bỏ chặn " + u.optString("name"), () ->
            request(
              "DELETE",
              "/api/users/" + u.optString("id") + "/block",
              json(),
              d -> blocks()
            )
          )
        );
      }
      if (users == null || users.length() == 0) content.addView(
        label("Bạn chưa chặn ai.", 16, MUTED)
      );
    });
  }

  private void notifications() {
    shell("Thông báo", true);
    request("GET", "/api/notifications", null, data -> {
      JSONArray rows = data.optJSONArray("notifications");
      for (int i = 0; rows != null && i < rows.length(); i++) {
        final JSONObject n = rows.optJSONObject(i), u = n.optJSONObject("actor");
        LinearLayout r = row();
        r.setPadding(dp(12), dp(10), dp(12), dp(10));
        r.setBackground(background(n.optInt("seen") == 0 ? PRIMARY_SOFT : CARD, 14));
        avatar(u, r, 46);
        LinearLayout t = column();
        t.setPadding(dp(12), 0, dp(8), 0);
        TextView line = new TextView(this);
        android.text.SpannableStringBuilder sb = new android.text.SpannableStringBuilder(u.optString("name"));
        sb.setSpan(new android.text.style.StyleSpan(Typeface.BOLD), 0, sb.length(), 0);
        sb.append(noticeText(n.optString("kind")));
        line.setText(sb);
        line.setTextColor(TEXT);
        line.setTextSize(15);
        t.addView(line);
        t.addView(label(ago(n.optLong("created")), 12, n.optInt("seen") == 0 ? ACCENT : MUTED));
        r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
        if (n.optInt("seen") == 0) {
          View dot = new View(this);
          dot.setBackground(background(ACCENT, 99));
          r.addView(dot, new LinearLayout.LayoutParams(dp(10), dp(10)));
        }
        r.setOnClickListener(v -> {
          String kind = n.optString("kind");
          if (kind.equals("message")) chat(u);
          else if (kind.equals("group_message")) navigate("inbox");
          else if (kind.equals("like") || kind.equals("comment")) navigate("feed");
          else person(u);
        });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        content.addView(r, p);
      }
      if (rows == null || rows.length() == 0) {
        TextView empty = label("🔔\nChưa có thông báo mới", 16, MUTED);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(0, dp(60), 0, 0);
        content.addView(empty);
      }
      request("POST", "/api/notifications", json(), d -> {});
    });
  }

  private void admin() {
    shell("Quản trị Kinnect", true);
    content.addView(label("Báo cáo và tài khoản", 22, TEXT));
    adminResets();
    adminMusic();
    request("GET", "/api/admin/reports", null, data -> {
      JSONArray reports = data.optJSONArray("reports");
      if (reports == null || reports.length() == 0) content.addView(
        label("Chưa có báo cáo.", 15, MUTED)
      );
      for (int i = 0; reports != null && i < reports.length(); i++) {
        JSONObject r = reports.optJSONObject(i),
          subject = r.optJSONObject("subject");
        LinearLayout c = card();
        c.addView(
          label(
            r.optString("target_type") + " · " + r.optString("status"),
            16,
            ACCENT
          )
        );
        c.addView(label(r.optString("reason"), 16, TEXT));
        if (subject != null) {
          c.addView(
            label(
              subject.optString("body", subject.optString("username")),
              14,
              MUTED
            )
          );
          if (r.optString("target_type").equals("short")) c.addView(
            button(
              subject.optBoolean("hidden") ? "Hiện video" : "Ẩn video",
              () ->
                moderate(
                  subject.optBoolean("hidden") ? "show-short" : "hide-short",
                  r.optString("target_id")
                )
            )
          );
          if (r.optString("target_type").equals("post")) c.addView(
            button(subject.optBoolean("hidden") ? "Hiện bài" : "Ẩn bài", () ->
              moderate(
                subject.optBoolean("hidden") ? "show-post" : "hide-post",
                r.optString("target_id")
              )
            )
          );
          c.addView(
            button("Đình chỉ tài khoản", () ->
              moderate("suspend-user", subject.optString("userId"))
            )
          );
        }
        if (r.optString("status").equals("open")) c.addView(
          button("Đóng báo cáo", () ->
            moderate("close-report", r.optString("id"))
          )
        );
      }
    });
    request("GET", "/api/admin/users", null, data -> {
      JSONArray users = data.optJSONArray("users");
      content.addView(label("Thành viên gần đây", 22, TEXT));
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        LinearLayout c = card();
        c.addView(
          label(u.optString("username") + " · " + u.optString("role"), 16, TEXT)
        );
        if (!u.optString("role").equals("admin")) c.addView(
          button(u.optInt("suspended") == 1 ? "Khôi phục" : "Đình chỉ", () ->
            moderate(
              u.optInt("suspended") == 1 ? "restore-user" : "suspend-user",
              u.optString("id")
            )
          )
        );
      }
    });
  }

  private void moderate(String action, String target) {
    confirm("Xác nhận thao tác quản trị?", () ->
      request(
        "POST",
        "/api/admin/moderate",
        json("action", action, "target", target),
        d -> admin()
      )
    );
  }

  private void live() {
    content.addView(label("Trực tiếp cùng Kinnect", 26, TEXT));
    content.addView(label("Camera, micro, video và trò chuyện được xử lý bằng WebRTC native trên Android.",15,MUTED));
    content.addView(primary("Mở phòng trực tiếp", () -> startActivity(new Intent(this, LiveActivity.class))));
  }

  private void settings() {
    new Sheet(this).setTitle("Cài đặt tài khoản").setItems(new String[]{"Kiểm tra cập nhật APK", "Đổi mật khẩu", "Thông báo", "Người đã chặn", "Đổi máy chủ", "Đóng"},(d,w)->{if(w==0)ApkUpdates.check(this);if(w==1)changePassword();if(w==2&&me!=null)notifications();if(w==3&&me!=null)blocks();if(w==4)serverSettings();}).show();
  }

  private void serverSettings() {

    EditText url = new EditText(this);
    url.setSingleLine(true);
    url.setText(server());
    new Sheet(this)
      .setTitle("Đổi máy chủ Kinnect")
      .setMessage(
        "Máy chủ mặc định: app.kinnect.io.vn. Đổi máy chủ sẽ đăng xuất phiên hiện tại."
      )
      .setView(url)
      .setPositiveButton("Lưu", (d, w) -> {
        try {
          String value = ServerConfig.normalize(url.getText().toString());
          getSharedPreferences("kinnect_settings", 0)
            .edit()
            .putString("server", value)
            .apply();
          api.configure(value);
          api.clear();
          me = null;
          auth(false);
        } catch (Exception e) {
          say("Cần URL HTTPS hợp lệ.");
        }
      })
      .setNeutralButton("Mặc định", (d, w) -> {
        getSharedPreferences("kinnect_settings", 0)
          .edit()
          .remove("server")
          .apply();
        api.configure(server());
        api.clear();
        me = null;
        auth(false);
      })
      .setNegativeButton("Hủy", null)
      .show();
  }

  private void stopShort() {
    if (shortVideo != null) {
      shortVideo.stopPlayback();
      shortVideo = null;
      shortPlayer = null;
    }
  }

  private void shorts() {
    content.addView(
      label(
        "Video từ thành viên · vuốt lên/xuống để chuyển. Tối đa 60 giây, MP4 12 MB.",
        13,
        MUTED
      )
    );
    LinearLayout feeds = row();
    feeds.addView(chip("Dành cho bạn", !shortsFollowing, () -> { shortsFollowing = false; navigate("shorts"); }));
    feeds.addView(chip("Đang theo dõi", shortsFollowing, () -> { shortsFollowing = true; navigate("shorts"); }));
    content.addView(feeds);
    request("GET", shortsFollowing ? "/api/shorts?feed=following" : "/api/shorts", null, data -> {
      shortRows = data.optJSONArray("shorts");
      if (shortRows == null || shortRows.length() == 0) {
        TextView empty = label("🎬\nChưa có video nào\nBấm + để quay video đầu tiên.", 16, MUTED);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(0, dp(60), 0, dp(16));
        content.addView(empty);
        content.addView(primary("＋ Quay video", () -> chooseVideo()));
        return;
      }
      showShort(0);
    });
  }

  private void showShort(int index) {
    if (shortRows == null || shortRows.length() == 0) return;
    shortIndex = Math.max(0, Math.min(index, shortRows.length() - 1));
    shell("Video ngắn", true);
    final JSONObject item = shortRows.optJSONObject(shortIndex), author = item.optJSONObject("author");
    // Video dọc toàn màn hình như web: nền đen, nút bên phải, tên + chú thích ở dưới.
    ScrollView scroll = (ScrollView) content.getParent();
    int at = root.indexOfChild(scroll);
    root.removeView(scroll);
    FrameLayout stage = new FrameLayout(this);
    stage.setBackgroundColor(0xff000000);
    root.addView(stage, at, new LinearLayout.LayoutParams(-1, 0, 1));
    shortVideo = new VideoView(this);
    final VideoView playerView = shortVideo;
    stage.addView(shortVideo, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
    Map<String, String> headers = new HashMap<>();
    headers.put("Cookie", api.jar());
    shortVideo.setVideoURI(android.net.Uri.parse(server() + item.optString("video")), headers);
    shortVideo.setOnPreparedListener(player -> {
      if (stopped || shortVideo != playerView) return;
      shortPlayer = player;
      player.setLooping(true);
      player.setVolume(shortMuted ? 0 : 1, shortMuted ? 0 : 1);
      shortVideo.start();
    });
    shortVideo.setOnErrorListener((player, what, extra) -> { say("Không phát được video."); return true; });
    final float[] y = { 0 };
    stage.setOnTouchListener((view, event) -> {
      if (event.getAction() == MotionEvent.ACTION_DOWN) y[0] = event.getY();
      if (event.getAction() == MotionEvent.ACTION_UP) {
        if (Math.abs(event.getY() - y[0]) > dp(60)) showShort(shortIndex + (event.getY() < y[0] ? 1 : -1));
        else if (shortVideo != null) { if (shortVideo.isPlaying()) shortVideo.pause(); else shortVideo.start(); }
      }
      return true;
    });
    // Tab trên cùng
    LinearLayout tabs = row();
    tabs.setGravity(Gravity.CENTER);
    tabs.addView(reelTab("Dành cho bạn", !shortsFollowing, () -> { shortsFollowing = false; navigate("shorts"); }));
    tabs.addView(reelTab("Đang theo dõi", shortsFollowing, () -> { shortsFollowing = true; navigate("shorts"); }));
    FrameLayout.LayoutParams tp = new FrameLayout.LayoutParams(-1, -2, Gravity.TOP);
    tp.topMargin = dp(8);
    stage.addView(tabs, tp);
    // Cột nút bên phải
    LinearLayout side = column();
    side.setGravity(Gravity.CENTER_HORIZONTAL);
    ImageView face = avatar(author, side, 46);
    face.setOnClickListener(v -> person(author));
    side.addView(reelButton(item.optBoolean("liked") ? "♥" : "♡", String.valueOf(item.optInt("likes")), item.optBoolean("liked") ? PINK : WHITE, () ->
      request(item.optBoolean("liked") ? "DELETE" : "POST", "/api/shorts/" + item.optString("id") + "/like", json(), d ->
        request("GET", shortsFollowing ? "/api/shorts?feed=following" : "/api/shorts", null, result -> { shortRows = result.optJSONArray("shorts"); showShort(shortIndex); }))));
    side.addView(reelButton("💬", item.has("comments") ? String.valueOf(item.optInt("comments")) : "Bình luận", WHITE, () -> shortComments(item)));
    side.addView(reelButton(shortMuted ? "🔇" : "🔊", shortMuted ? "Bật tiếng" : "Tắt tiếng", WHITE, () -> {
      shortMuted = !shortMuted;
      if (shortPlayer != null) shortPlayer.setVolume(shortMuted ? 0 : 1, shortMuted ? 0 : 1);
      showShort(shortIndex);
    }));
    final boolean mine = item.optString("user_id").equals(me.optString("id"));
    side.addView(reelButton("⋯", "Thêm", WHITE, () -> new Sheet(this).setItems(new String[] { mine ? "Xoá video của tôi" : "Báo cáo video", "Xem hồ sơ", "Đóng" }, (d, w) -> {
      if (w == 0) { if (mine) confirm("Xoá video?", () -> request("DELETE", "/api/shorts/" + item.optString("id"), json(), r -> navigate("shorts"))); else report("short", item.optString("id")); }
      if (w == 1) person(author);
    }).show()));
    FrameLayout.LayoutParams sp = new FrameLayout.LayoutParams(dp(72), -2, Gravity.END | Gravity.BOTTOM);
    sp.bottomMargin = dp(24);
    stage.addView(side, sp);
    // Tên + chú thích
    LinearLayout meta = column();
    TextView name = label("@" + author.optString("username"), 16, WHITE);
    name.setTypeface(null, Typeface.BOLD);
    name.setShadowLayer(4, 0, 1, 0xaa000000);
    meta.addView(name);
    if (!item.optString("caption").isEmpty()) {
      TextView cap = label(item.optString("caption"), 14, WHITE);
      cap.setShadowLayer(4, 0, 1, 0xaa000000);
      meta.addView(cap);
    }
    TextView hint = label((shortIndex + 1) + "/" + shortRows.length() + " · vuốt lên để xem tiếp", 11, 0xccffffff);
    meta.addView(hint);
    FrameLayout.LayoutParams mp = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
    mp.setMargins(dp(14), 0, dp(84), dp(18));
    stage.addView(meta, mp);
  }

  private TextView reelTab(String text, boolean active, Runnable click) {
    TextView t = label(text, 16, active ? WHITE : 0x99ffffff);
    t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
    t.setPadding(dp(12), dp(6), dp(12), dp(6));
    t.setShadowLayer(4, 0, 1, 0xaa000000);
    t.setOnClickListener(v -> click.run());
    return t;
  }

  private LinearLayout reelButton(String glyph, String caption, int color, Runnable click) {
    LinearLayout box = column();
    box.setGravity(Gravity.CENTER_HORIZONTAL);
    box.setPadding(0, dp(10), 0, 0);
    TextView icon = label(glyph, 26, color);
    icon.setGravity(Gravity.CENTER);
    icon.setBackground(background(0x33000000, 999));
    box.addView(icon, new LinearLayout.LayoutParams(dp(48), dp(48)));
    TextView text = label(caption, 11, WHITE);
    text.setShadowLayer(4, 0, 1, 0xaa000000);
    text.setGravity(Gravity.CENTER);
    box.addView(text);
    box.setContentDescription(caption);
    box.setOnClickListener(v -> click.run());
    return box;
  }

  private void shortComments(final JSONObject item) {
    shell("Bình luận", true);
    comments("/api/shorts/" + item.optString("id"), () -> shortComments(item), () -> showShort(shortIndex), "Quay lại video");
  }

  private void chooseVideo() {
    if (postingVideo) {
      say("Đang tải video, vui lòng chờ.");
      return;
    }
    startActivityForResult(new Intent(this, StudioActivity.class), 203);
  }

  private void captureVideo() {
    Intent capture = new Intent(
      android.provider.MediaStore.ACTION_VIDEO_CAPTURE
    );
    capture.putExtra(android.provider.MediaStore.EXTRA_DURATION_LIMIT, 60);
    capture.putExtra(
      android.provider.MediaStore.EXTRA_SIZE_LIMIT,
      12L * 1024 * 1024
    );
    capture.putExtra(android.provider.MediaStore.EXTRA_VIDEO_QUALITY, 0);
    try {
      startActivityForResult(capture, 201);
    } catch (Exception e) {
      say("Không mở được camera quay video.");
    }
  }

  private void uploadVideo(android.net.Uri uri) {
    EditText caption = new EditText(this);
    caption.setHint("Viết chú thích cho video");
    new Sheet(this)
      .setTitle("Đăng video · MP4 ≤12 MB, ≤60 giây")
      .setView(caption)
      .setPositiveButton("Đăng", (dialog, which) -> {
        postingVideo = true;
        say("Đang đọc và tải video…");
        final int generation = screen;
        String text = caption.getText().toString();
        new Thread(() -> {
          try {
            android.media.MediaMetadataRetriever metadata =
              new android.media.MediaMetadataRetriever();
            long duration;
            try {
              metadata.setDataSource(this, uri);
              duration = Long.parseLong(
                metadata.extractMetadata(
                  android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                )
              );
            } finally {
              metadata.release();
            }
            if (duration <= 0 || duration > 60000) throw new Exception(
              "Video phải dài không quá 60 giây."
            );
            byte[] bytes = NativeApi.read(
              getContentResolver().openInputStream(uri),
              12 * 1024 * 1024
            );
            String encoded = android.util.Base64.encodeToString(
              bytes,
              android.util.Base64.NO_WRAP
            );
            JSONObject payload = json(
              "data",
              "data:video/mp4;base64," + encoded,
              "caption",
              text
            );
            api.call(
              "POST",
              "/api/shorts",
              payload,
              (result, error, status) -> {
                postingVideo = false;
                if (isDestroyed() || generation != screen) return;
                if (error != null) say(error);
                else {
                  navigate("shorts");
                  say("Đã đăng video.");
                }
              }
            );
          } catch (Exception e) {
            runOnUiThread(() -> {
              postingVideo = false;
              if (generation == screen) say(
                "Chọn MP4 hợp lệ, tối đa 12 MB và 60 giây."
              );
            });
          }
        }).start();
      })
      .setNegativeButton("Hủy", null)
      .show();
  }

  private void pickAvatar() {
    Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    intent.addCategory(Intent.CATEGORY_OPENABLE);
    intent.setType("image/*");
    intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
      "image/png",
      "image/jpeg",
      "image/webp",
    });
    try {
      startActivityForResult(intent, 100);
    } catch (Exception e) {
      say("Không mở được trình chọn ảnh.");
    }
  }

  @Override
  protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (request == 203 && result == RESULT_OK && data != null && data.getStringExtra(StudioActivity.EXTRA_VIDEO) != null) {
      uploadVideo(android.net.Uri.fromFile(new java.io.File(data.getStringExtra(StudioActivity.EXTRA_VIDEO))));
      return;
    }
    if (request == 203 && result == RESULT_FIRST_USER) {
      Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
      pick.addCategory(Intent.CATEGORY_OPENABLE);
      pick.setType("video/mp4");
      try { startActivityForResult(pick, 200); } catch (Exception e) { say("Không mở được trình chọn video."); }
      return;
    }
    if (request >= 300 && request <= 306) {
      if (result == RESULT_OK && data != null && data.getData() != null) picked(request, data.getData());
      return;
    }
    if (
      (request == 200 || request == 201) &&
      result == RESULT_OK &&
      data != null &&
      data.getData() != null
    ) {
      uploadVideo(data.getData());
      return;
    }
    if (
      request == 100 &&
      result == RESULT_OK &&
      data != null &&
      data.getData() != null
    ) {
      try {
        byte[] image = NativeApi.read(
          getContentResolver().openInputStream(data.getData()),
          1024 * 1024
        );
        String type = getContentResolver().getType(data.getData());
        if (
          !Arrays.asList("image/png", "image/jpeg", "image/webp").contains(type)
        ) {
          say("Chọn ảnh PNG/JPEG/WebP.");
          return;
        }
        request(
          "POST",
          "/api/me/avatar",
          json(
            "data",
            "data:" +
              type +
              ";base64," +
              android.util.Base64.encodeToString(
                image,
                android.util.Base64.NO_WRAP
              )
          ),
          d -> navigate("profile")
        );
      } catch (Exception e) {
        say("Chọn ảnh nhỏ hơn 1 MB.");
      }
    }
  }

  private void stopLocation() {
    if (locationListener != null) {
      try {
        ((LocationManager) getSystemService(LOCATION_SERVICE)).removeUpdates(
          locationListener
        );
      } catch (SecurityException ignored) {}
      locationListener = null;
    }
  }

  private void requestLocation() {
    new Sheet(this)
      .setTitle("Tìm thành viên xung quanh")
      .setMessage(
        "Chỉ dùng vị trí gần đúng, lưu theo ô khoảng 5 km trong tối đa 24 giờ hiệu lực; không công khai tọa độ. Bạn có thể tắt và xóa ở Hồ sơ."
      )
      .setPositiveButton("Đồng ý", (d, w) -> {
        if (
          checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) !=
          PackageManager.PERMISSION_GRANTED
        ) requestPermissions(
          new String[] { Manifest.permission.ACCESS_COARSE_LOCATION },
          101
        );
        else locate();
      })
      .setNegativeButton("Hủy", null)
      .show();
  }

  private void locate() {
    try {
      LocationManager manager = (LocationManager) getSystemService(
        LOCATION_SERVICE
      );
      Location best = null;
      for (String provider : manager.getProviders(true)) {
        if (provider.equals(LocationManager.GPS_PROVIDER)) continue;
        Location last = manager.getLastKnownLocation(provider);
        if (
          last != null &&
          System.currentTimeMillis() - last.getTime() < 1800000 &&
          (best == null || last.getTime() > best.getTime())
        ) best = last;
      }
      if (best != null) {
        sendLocation(best);
        return;
      }
      if (!manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
        say("Bật dịch vụ vị trí gần đúng trên điện thoại rồi thử lại.");
        return;
      }
      locationListener = new LocationListener() {
        public void onLocationChanged(Location value) {
          manager.removeUpdates(this);
          locationListener = null;
          sendLocation(value);
        }

        public void onProviderEnabled(String p) {}

        public void onProviderDisabled(String p) {}

        public void onStatusChanged(String p, int s, Bundle b) {}
      };
      manager.requestSingleUpdate(
        LocationManager.NETWORK_PROVIDER,
        locationListener,
        Looper.getMainLooper()
      );
      say("Đang lấy vị trí gần đúng…");
      handler.postDelayed(() -> {
        if (locationListener != null) {
          manager.removeUpdates(locationListener);
          locationListener = null;
          say("Chưa lấy được vị trí. Hãy kiểm tra cài đặt vị trí và thử lại.");
        }
      }, 15000);
    } catch (SecurityException e) {
      say("Chưa được cấp quyền vị trí.");
    }
  }

  private void sendLocation(Location location) {
    request(
      "PATCH",
      "/api/me/location",
      json(
        "enabled",
        true,
        "latitude",
        location.getLatitude(),
        "longitude",
        location.getLongitude()
      ),
      d -> {
        me = d.optJSONObject("user");
        navigate("feed");
      }
    );
  }

  @Override
  public void onRequestPermissionsResult(
    int code,
    String[] permissions,
    int[] results
  ) {
    super.onRequestPermissionsResult(code, permissions, results);
    if(code==901){if(calls!=null)calls.permissionsResult(results);return;}
    if (code == 102) {
      if (
        results.length > 0 && results[0] == PackageManager.PERMISSION_GRANTED
      ) captureVideo();
      else say("Cần quyền camera để quay video.");
      return;
    }
    if (
      code == 101 &&
      results.length > 0 &&
      results[0] == PackageManager.PERMISSION_GRANTED
    ) locate();
    else if (code == 101) say(
      "Bạn vẫn có thể tìm bạn theo sở thích khi không cấp vị trí."
    );
  }

  @Override
  protected void onStop() {
    super.onStop();
    if(calls!=null){calls.close();calls=null;}
    if (shortVideo != null) shortVideo.pause();
    stopped = true;
    handler.removeCallbacksAndMessages(null);
    if (locationListener != null) {
      try {
        ((LocationManager) getSystemService(LOCATION_SERVICE)).removeUpdates(
          locationListener
        );
      } catch (SecurityException ignored) {}
      locationListener = null;
    }
  }

  @Override
  protected void onResume() {
    super.onResume();
    stopped = false;
    ensureCalls();
    if (poll != null) handler.postDelayed(poll, 4000);
  }

  @Override
  protected void onDestroy() {
    stopShort();
    super.onDestroy();
  }

  @Override
  public void onBackPressed() {
    if (me != null && (!onTabRoot || !tab.equals("feed"))) {
      navigate(onTabRoot ? "feed" : tab);
      return;
    }
    super.onBackPressed();
  }


  // ===================== Bổ sung cho bản Android đầy đủ =====================
  private String discoverSort = "new", feedCategory = "community", attachTarget = "";
  private String pendingMedia;
  private Button attachButton;
  private JSONArray conversationUsers;
  private JSONObject pendingStoryMedia;
  private static final String[][] REACTIONS = { { "like", "👍" }, { "love", "❤️" }, { "haha", "😆" }, { "wow", "😮" }, { "sad", "😢" }, { "angry", "😡" } };

  private Button chip(String text, boolean active, Runnable action) {
    Button b = new Button(this);
    b.setText(text);
    b.setAllCaps(false);
    b.setTextSize(13);
    b.setTextColor(active ? WHITE : TEXT);
    b.setStateListAnimator(null);
    b.setBackground(background(active ? ACCENT : SOFT, 999));
    b.setPadding(dp(14), 0, dp(14), 0);
    b.setMinWidth(0);
    b.setMinimumWidth(0);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, dp(38));
    p.setMargins(0, dp(6), dp(8), dp(6));
    b.setLayoutParams(p);
    b.setOnClickListener(v -> action.run());
    return b;
  }

  private String ago(long time) {
    long s = Math.max(0, (System.currentTimeMillis() - time) / 1000);
    if (s < 60) return "vừa xong";
    if (s < 3600) return (s / 60) + " phút";
    if (s < 86400) return (s / 3600) + " giờ";
    if (s < 7 * 86400) return (s / 86400) + " ngày";
    return new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()).format(new Date(time));
  }

  private String noticeText(String kind) {
    if (kind.equals("follow")) return " đã theo dõi bạn";
    if (kind.equals("like")) return " đã bày tỏ cảm xúc về bài viết của bạn";
    if (kind.equals("comment")) return " đã bình luận bài viết của bạn";
    if (kind.equals("gift")) return " đã gửi quà miễn phí";
    if (kind.equals("group_message")) return " đã nhắn trong nhóm";
    if (kind.equals("short_like")) return " đã thích video của bạn";
    if (kind.equals("short_comment")) return " đã bình luận video của bạn";
    return " đã gửi tin nhắn";
  }

  // ----- Màn giới thiệu (hiện mỗi lần mở app khi chưa đăng nhập)
  private int introPage = 0;

  private void intro() {
    if (!api.cookieFor(server()).isEmpty()) { auth(false); return; }
    final String[][] pages = {
      { "CHÀO MỪNG ĐẾN KINNECT", "Kết nối đúng gu. Sống đúng mình.", "Bảng tin, video ngắn, khám phá bạn mới và live — tất cả trong một nơi an toàn dành cho bạn." },
      { "BẢNG TIN", "Chia sẻ chuyện mỗi ngày", "Đăng suy nghĩ, khoảnh khắc và theo dõi những người bạn quan tâm. Bạn chọn ai được xem bài viết." },
      { "VIDEO NGẮN", "Lướt video, thả tim", "Video dọc toàn màn hình, vuốt để xem tiếp. Đăng video của bạn chỉ trong vài giây." },
      { "KHÁM PHÁ", "Gặp người cùng tần số", "Gợi ý theo sở thích chung. Bật “Quanh đây” nếu muốn — vị trí luôn được làm tròn, không lộ chính xác." },
      { "LIVE & TIN NHẮN", "Trò chuyện an toàn", "Nhắn tin riêng, xem và phát live. Chặn hoặc báo cáo bất kỳ lúc nào chỉ với một chạm." },
    };
    final int page = Math.min(introPage, pages.length - 1);
    shell("Kinnect", false);
    // Nền chuyển sắc tím → tối → đỏ mận như màn giới thiệu trên web
    root.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0xff4a3a9e, 0xff221d3f, 0xff1b1830, 0xff5a2a44 }));
    getWindow().setStatusBarColor(0xff4a3a9e);
    getWindow().setNavigationBarColor(0xff5a2a44);
    getWindow().getDecorView().setSystemUiVisibility(0);
    toolbar.setBackgroundColor(0);
    toolbar.removeViewAt(toolbar.getChildCount() - 1);
    TextView more = label("Tìm hiểu thêm ↗", 15, 0xffc9a4ff);
    more.setOnClickListener(v -> { try { startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://kinnect.io.vn/"))); } catch (Exception ignored) {} });
    more.setOnLongClickListener(v -> { settings(); return true; });
    toolbar.addView(more);
    for (int i = 0; i < toolbar.getChildCount(); i++) if (toolbar.getChildAt(i) instanceof TextView && !(toolbar.getChildAt(i) instanceof Button)) ((TextView) toolbar.getChildAt(i)).setTextColor(0xffc9a4ff);
    TextView skip = label("Bỏ qua", 15, 0xccffffff);
    skip.setPadding(dp(8), dp(8), dp(8), dp(8));
    skip.setOnClickListener(v -> { introPage = 0; auth(false); });
    content.addView(skip);
    content.addView(new IntroArt(this, page), new LinearLayout.LayoutParams(-1, dp(330)));
    TextView eyebrow = label(pages[page][0], 13, 0xffb59cff);
    eyebrow.setLetterSpacing(0.12f);
    eyebrow.setTypeface(null, Typeface.BOLD);
    eyebrow.setPadding(dp(14), dp(6), dp(14), dp(6));
    eyebrow.setBackground(background(0x33ffffff & 0x22ffffff | 0x22000000, 999));
    LinearLayout.LayoutParams ep = new LinearLayout.LayoutParams(-2, -2);
    ep.gravity = Gravity.CENTER_HORIZONTAL;
    ep.topMargin = dp(10);
    content.addView(eyebrow, ep);
    TextView title = label(pages[page][1], 30, 0xffffffff);
    title.setTypeface(null, Typeface.BOLD);
    title.setGravity(Gravity.CENTER);
    content.addView(title);
    TextView text = label(pages[page][2], 15, 0xd9ffffff);
    text.setGravity(Gravity.CENTER);
    text.setLineSpacing(0, 1.2f);
    content.addView(text);
    LinearLayout dots = row();
    dots.setGravity(Gravity.CENTER);
    for (int i = 0; i < pages.length; i++) {
      View dot = new View(this);
      dot.setBackground(i == page ? gradient(99) : background(0xb3ffffff, 99));
      LinearLayout.LayoutParams dp8 = new LinearLayout.LayoutParams(dp(i == page ? 26 : 9), dp(9));
      dp8.setMargins(dp(4), dp(20), dp(4), dp(20));
      dots.addView(dot, dp8);
    }
    content.addView(dots);
    Button next = primary(page < pages.length - 1 ? "Tiếp tục" : "Bắt đầu", () -> {
      if (page < pages.length - 1) { introPage++; intro(); } else { introPage = 0; auth(true); }
    });
    next.setTextSize(17);
    next.setBackground(gradient(999));
    next.getLayoutParams().height = dp(56);
    content.addView(next);
    TextView have = label("Tôi đã có tài khoản", 16, 0xffffffff);
    have.setTypeface(null, Typeface.BOLD);
    have.setGravity(Gravity.CENTER);
    have.setPadding(0, dp(14), 0, dp(14));
    have.setOnClickListener(v -> { introPage = 0; auth(false); });
    content.addView(have);
    // Vuốt ngang để chuyển trang
    final float[] x0 = { 0 };
    content.setOnTouchListener((v, e) -> {
      if (e.getAction() == MotionEvent.ACTION_DOWN) x0[0] = e.getX();
      if (e.getAction() == MotionEvent.ACTION_UP && Math.abs(e.getX() - x0[0]) > dp(60)) {
        introPage = Math.max(0, Math.min(pages.length - 1, page + (e.getX() < x0[0] ? 1 : -1)));
        intro();
        return true;
      }
      return true;
    });
  }

  // ----- Đăng nhập nhanh trên thiết bị này + Google/Facebook
  private void authExtras() {
    final LinearLayout box = column();
    content.addView(box);
    api.call("GET", "/api/remembered", null, (data, error, status) -> {
      JSONArray accounts = data == null ? null : data.optJSONArray("accounts");
      if (accounts == null || accounts.length() == 0 || isDestroyed()) return;
      box.addView(label("Đăng nhập gần đây", 13, MUTED));
      for (int i = 0; i < accounts.length(); i++) {
        final JSONObject a = accounts.optJSONObject(i);
        LinearLayout r = row();
        r.setPadding(dp(10), dp(8), dp(10), dp(8));
        r.setBackground(background(CARD, 14));
        avatar(a, r, 40);
        LinearLayout t = column();
        t.setPadding(dp(12), 0, 0, 0);
        t.addView(label(a.optString("name"), 16, TEXT));
        t.addView(label("@" + a.optString("username"), 12, MUTED));
        r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
        Button remove = chip("✕", false, () -> api.call("DELETE", "/api/remembered/" + a.optString("id"), json(), (d, e, s) -> auth(false)));
        remove.setContentDescription("Gỡ tài khoản khỏi thiết bị");
        r.addView(remove);
        r.setOnClickListener(v -> api.call("POST", "/api/remembered/login", json("userId", a.optString("id")), (d, e, s) -> {
          if (e != null) { say(e); return; }
          me = d.optJSONObject("user");
          navigate("feed");
        }));
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        box.addView(r, p);
      }
    });
    api.call("GET", "/api/oauth/providers", null, (data, error, status) -> {
      JSONArray providers = data == null ? null : data.optJSONArray("providers");
      for (int i = 0; providers != null && i < providers.length() && !isDestroyed(); i++) {
        final String provider = providers.optString(i);
        box.addView(button(provider.equals("google") ? "Tiếp tục với Google" : "Tiếp tục với Facebook", () -> {
          try {
            startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(server() + "/api/oauth/" + provider + "/start?client=android")));
          } catch (Exception e) { say("Không mở được trình duyệt."); }
        }));
      }
    });
  }

  @Override
  protected void onNewIntent(Intent intent) {
    super.onNewIntent(intent);
    handleLink(intent);
  }

  private void handleLink(Intent intent) {
    android.net.Uri uri = intent == null ? null : intent.getData();
    if (uri == null || !"kinnect".equals(uri.getScheme()) || !"oauth".equals(uri.getHost())) return;
    String code = uri.getQueryParameter("code"), ticket = uri.getQueryParameter("ticket"), error = uri.getQueryParameter("error");
    if (error != null) { auth(false); say("Đăng nhập chưa hoàn tất. Hãy thử lại."); return; }
    if (code != null) api.call("POST", "/api/oauth/app-session", json("code", code), (d, e, s) -> {
      if (e != null) { auth(false); say(e); return; }
      me = d.optJSONObject("user");
      navigate("feed");
    });
    if (ticket != null) oauthComplete(ticket);
  }

  private void oauthComplete(String ticket) {
    api.call("GET", "/api/oauth/pending?ticket=" + encode(ticket), null, (d, e, s) -> {
      if (e != null) { auth(false); say(e); return; }
      shell("Hoàn tất đăng ký", false);
      content.addView(label("Chào " + d.optString("name") + "! Chọn tên đăng nhập cho Kinnect.", 16, TEXT));
      EditText username = input(content, "Tên đăng nhập", d.optString("suggestedUsername"), false);
      CheckBox agree = new CheckBox(this);
      agree.setText("Tôi xác nhận mình đủ 18 tuổi và tôn trọng quy tắc cộng đồng.");
      agree.setTextColor(MUTED);
      content.addView(agree);
      content.addView(primary("Bắt đầu", () -> api.call("POST", "/api/oauth/complete", json("ticket", ticket, "username", username.getText().toString(), "agree18", agree.isChecked()), (r, err, st) -> {
        if (err != null) { say(err); return; }
        me = r.optJSONObject("user");
        navigate("feed");
      })));
    });
  }

  // ----- Quên / đổi mật khẩu
  private void forgot() {
    shell("Quên mật khẩu", false);
    content.addView(label("Để lại thông tin liên hệ, quản trị viên sẽ cấp mật khẩu tạm cho bạn.", 15, MUTED));
    EditText username = input(content, "Tên đăng nhập", "", false),
      contact = input(content, "Email, số điện thoại hoặc Zalo", "", false),
      note = input(content, "Ghi chú (không bắt buộc)", "", true);
    content.addView(primary("Gửi yêu cầu", () -> api.call("POST", "/api/password-reset", json("username", username.getText().toString(), "contact", contact.getText().toString(), "note", note.getText().toString()), (d, e, s) -> {
      if (e != null) { say(e); return; }
      content.removeAllViews();
      content.addView(label("✓ " + d.optString("message"), 17, TEXT));
      content.addView(primary("Về đăng nhập", () -> auth(false)));
    })));
    content.addView(button("Quay lại", () -> auth(false)));
  }

  private void changePassword() {
    if (me == null) return;
    LinearLayout box = column();
    box.setPadding(dp(20), dp(8), dp(20), 0);
    EditText current = new EditText(this), next = new EditText(this);
    current.setHint("Mật khẩu hiện tại");
    next.setHint("Mật khẩu mới (tối thiểu 6 ký tự)");
    current.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
    next.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
    box.addView(current);
    box.addView(next);
    new Sheet(this).setTitle("Đổi mật khẩu").setView(box).setPositiveButton("Lưu", (d, w) ->
      api.call("POST", "/api/me/password", json("current", current.getText().toString(), "next", next.getText().toString()), (r, e, s) ->
        Toast.makeText(this, e != null ? e : "Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.", Toast.LENGTH_LONG).show())
    ).setNegativeButton("Hủy", null).show();
  }

  // ----- Hồ sơ: số liệu, người theo dõi, bài viết
  private void stats(JSONObject u, LinearLayout parent) {
    final LinearLayout r = row();
    parent.addView(r);
    request("GET", "/api/users/" + u.optString("id") + "/stats", null, d -> {
      String[][] items = { { String.valueOf(d.optInt("posts")), "Bài viết", "" }, { String.valueOf(d.optInt("followers")), "Người theo dõi", "followers" }, { String.valueOf(d.optInt("following")), "Đang theo dõi", "following" } };
      for (final String[] it : items) {
        LinearLayout c = column();
        c.setGravity(Gravity.CENTER);
        TextView n = label(it[0], 20, TEXT);
        n.setTypeface(null, Typeface.BOLD);
        n.setGravity(Gravity.CENTER);
        TextView l = label(it[1], 12, MUTED);
        l.setGravity(Gravity.CENTER);
        c.addView(n);
        c.addView(l);
        if (!it[2].isEmpty()) c.setOnClickListener(v -> connections(u, it[2], it[1]));
        r.addView(c, new LinearLayout.LayoutParams(0, -2, 1));
      }
    });
  }

  private void connections(JSONObject u, String kind, String title) {
    shell(title, true);
    request("GET", "/api/users/" + u.optString("id") + "/" + kind, null, d -> {
      JSONArray users = d.optJSONArray("users");
      if (users == null || users.length() == 0) content.addView(label("Chưa có ai.", 15, MUTED));
      for (int i = 0; users != null && i < users.length(); i++) {
        final JSONObject p = users.optJSONObject(i);
        inboxRow(content, p, p.optString("name"), "@" + p.optString("username"), 0, () -> person(p));
      }
    });
  }

  private void userPosts(JSONObject u) {
    shell(u.optString("name"), true);
    request("GET", "/api/posts?user=" + u.optString("id"), null, d -> posts(d.optJSONArray("posts"), "Chưa có bài viết."));
  }

  // ----- Danh sách bài viết dùng chung
  private void posts(JSONArray posts, String empty) {
    if (posts == null || posts.length() == 0) content.addView(label(empty, 14, MUTED));
    for (int i = 0; posts != null && i < posts.length(); i++) postCard(posts.optJSONObject(i));
  }

  private void postCard(final JSONObject p) {
    final JSONObject author = p.optJSONObject("author");
    LinearLayout c = card();
    LinearLayout head = row();
    avatar(author, head, 40);
    LinearLayout who = column();
    who.setPadding(dp(10), 0, 0, 0);
    TextView name = label(author.optString("name"), 16, TEXT);
    name.setTypeface(null, Typeface.BOLD);
    who.addView(name);
    who.addView(label(ago(p.optLong("created")) + (p.optString("visibility").equals("followers") ? " · 👥" : " · 🌐"), 11, MUTED));
    head.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
    head.setOnClickListener(v -> person(author));
    Button more = chip("⋯", false, () -> {
      boolean mine = p.optString("user_id").equals(me.optString("id"));
      new Sheet(this).setItems(new String[] { mine ? "Xoá bài" : "Báo cáo bài viết", "Đóng" }, (d, w) -> {
        if (w != 0) return;
        if (mine) confirm("Xoá bài viết?", () -> request("DELETE", "/api/posts/" + p.optString("id"), json(), r -> navigate("feed")));
        else report("post", p.optString("id"));
      }).show();
    });
    more.setContentDescription("Thêm thao tác");
    head.addView(more);
    c.addView(head);
    if (!p.optString("body").isEmpty()) c.addView(label(p.optString("body"), 16, TEXT));
    JSONObject media = p.optJSONObject("media");
    if (media != null) mediaView(media, c);
    LinearLayout actions = row();
    String mine = p.optString("myReaction", "");
    String glyph = "♡";
    for (String[] r : REACTIONS) if (r[0].equals(mine)) glyph = r[1];
    final Button react = chip(glyph + " " + p.optInt("likes"), !mine.isEmpty() && !mine.equals("null"), () -> {});
    react.setOnClickListener(v -> request(p.optBoolean("liked") ? "DELETE" : "POST", "/api/posts/" + p.optString("id") + "/like", p.optBoolean("liked") ? json() : json("reaction", "like"), d -> refreshReaction(p, react, d)));
    react.setOnLongClickListener(v -> {
      String[] names = new String[REACTIONS.length];
      for (int i = 0; i < names.length; i++) names[i] = REACTIONS[i][1];
      new Sheet(this).setTitle("Bày tỏ cảm xúc").setItems(names, (d, w) ->
        request("POST", "/api/posts/" + p.optString("id") + "/like", json("reaction", REACTIONS[w][0]), r -> refreshReaction(p, react, r))).show();
      return true;
    });
    actions.addView(react);
    actions.addView(chip("💬 " + p.optInt("comments"), false, () -> postComments(p)));
    actions.addView(chip("✉", false, () -> chat(author)));
    c.addView(actions);
  }

  private void refreshReaction(JSONObject p, Button react, JSONObject d) {
    try {
      p.put("liked", d.optBoolean("liked"));
      p.put("likes", d.optInt("likes"));
      p.put("myReaction", d.isNull("myReaction") ? "" : d.optString("myReaction"));
    } catch (JSONException ignored) {}
    String glyph = "♡";
    for (String[] r : REACTIONS) if (r[0].equals(p.optString("myReaction"))) glyph = r[1];
    react.setText(glyph + " " + d.optInt("likes"));
    react.setTextColor(d.optBoolean("liked") ? WHITE : TEXT);
    react.setBackground(background(d.optBoolean("liked") ? ACCENT : SOFT, 999));
  }

  private void postComments(final JSONObject p) {
    shell("Bình luận", true);
    comments("/api/posts/" + p.optString("id"), () -> postComments(p), () -> navigate("feed"), "Quay lại bảng tin");
  }

  // ----- Ảnh / video trong bài viết, tin, tin nhắn
  private void mediaView(JSONObject media, LinearLayout parent) {
    String url = media.optString("url");
    if (media.optString("kind").equals("video")) {
      final VideoView video = new VideoView(this);
      Map<String, String> headers = new HashMap<>();
      headers.put("Cookie", api.jar());
      video.setVideoURI(android.net.Uri.parse(server() + url), headers);
      video.setOnPreparedListener(mp -> { mp.setLooping(true); video.seekTo(1); });
      video.setOnClickListener(v -> { if (video.isPlaying()) video.pause(); else video.start(); });
      video.setOnTouchListener((v, e) -> { if (e.getAction() == MotionEvent.ACTION_UP) v.performClick(); return true; });
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, dp(360));
      lp.setMargins(0, dp(8), 0, dp(4));
      parent.addView(video, lp);
      parent.addView(label("▶ Chạm để phát/tạm dừng", 11, MUTED));
      return;
    }
    final ImageView image = new ImageView(this);
    image.setAdjustViewBounds(true);
    image.setScaleType(ImageView.ScaleType.FIT_CENTER);
    image.setBackground(background(SOFT, 14));
    image.setClipToOutline(true);
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.setMargins(0, dp(8), 0, dp(4));
    parent.addView(image, lp);
    api.image(url, bytes -> {
      if (bytes == null || isDestroyed()) return;
      BitmapFactory.Options o = new BitmapFactory.Options();
      o.inJustDecodeBounds = true;
      BitmapFactory.decodeByteArray(bytes, 0, bytes.length, o);
      o.inSampleSize = Math.max(1, Math.max(o.outWidth, o.outHeight) / 1280);
      o.inJustDecodeBounds = false;
      Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, o);
      if (b != null) image.setImageBitmap(b);
    });
  }

  private void openAttachment(JSONObject file) {
    if (file.optString("kind").equals("image") || file.optString("kind").equals("video")) {
      shell(file.optString("name"), true);
      mediaView(file, content);
      content.addView(button("Quay lại", () -> { if (chatUser != null) chat(chatUser); else navigate("inbox"); }));
    } else say("Tệp " + file.optString("name") + " chỉ xem được trên bản web.");
  }

  // ----- Tin 24 giờ
  private void stories() {
    final LinearLayout strip = row();
    HorizontalScrollView scroll = new HorizontalScrollView(this);
    scroll.setHorizontalScrollBarEnabled(false);
    scroll.addView(strip);
    content.addView(scroll);
    Button add = chip("＋ Tin của bạn", false, () -> pickFile(304, "image/*|video/mp4"));
    strip.addView(add);
    request("GET", "/api/stories", null, d -> {
      final JSONArray stories = d.optJSONArray("stories");
      for (int i = 0; stories != null && i < stories.length(); i++) {
        final int index = i;
        JSONObject st = stories.optJSONObject(i);
        strip.addView(chip("◉ " + st.optJSONObject("author").optString("name"), false, () -> story(stories, index)));
      }
    });
  }

  private void story(final JSONArray stories, final int index) {
    if (index < 0 || index >= stories.length()) { navigate("feed"); return; }
    JSONObject st = stories.optJSONObject(index);
    shell("Tin · " + st.optJSONObject("author").optString("name"), true);
    content.addView(label(ago(st.optLong("created")) + " · còn " + Math.max(0, (st.optLong("expires") - System.currentTimeMillis()) / 3600000) + " giờ", 12, MUTED));
    if (st.optJSONObject("media") != null) mediaView(st.optJSONObject("media"), content);
    if (!st.optString("body").isEmpty()) content.addView(label(st.optString("body"), 18, TEXT));
    LinearLayout nav = row();
    nav.addView(chip("‹ Trước", false, () -> story(stories, index - 1)));
    nav.addView(chip("Tiếp ›", false, () -> story(stories, index + 1)));
    nav.addView(chip("Đóng", false, () -> navigate("feed")));
    content.addView(nav);
  }

  // ----- Tin tức
  private void news() {
    request("GET", "/api/news", null, d -> {
      JSONArray items = d.optJSONArray("articles");
      if (items == null || items.length() == 0) content.addView(label("Chưa tải được tin tức. Thử lại sau.", 14, MUTED));
      for (int i = 0; items != null && i < Math.min(items.length(), 60); i++) {
        final JSONObject a = items.optJSONObject(i);
        LinearLayout c = card();
        c.addView(label(a.optString("source") + (a.optLong("publishedAt") > 0 ? " · " + ago(a.optLong("publishedAt")) : ""), 11, ACCENT));
        TextView t = label(a.optString("title"), 17, TEXT);
        t.setTypeface(null, Typeface.BOLD);
        c.addView(t);
        if (!a.optString("summary").isEmpty()) c.addView(label(a.optString("summary"), 13, MUTED));
        c.setOnClickListener(v -> {
          String url = a.optString("url");
          if (url.startsWith("https://")) try { startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))); } catch (Exception ignored) {}
        });
      }
    });
  }

  // ----- Hộp thư: hàng, nhóm
  private void inboxRow(LinearLayout parent, JSONObject u, String title, String subtitle, int unread, Runnable open) {
    LinearLayout r = row();
    r.setPadding(dp(12), dp(10), dp(12), dp(10));
    r.setBackground(background(CARD, 16));
    if (u != null) avatar(u, r, 46);
    else {
      TextView g = label("👥", 22, TEXT);
      g.setGravity(Gravity.CENTER);
      g.setBackground(background(PRIMARY_SOFT, 16));
      r.addView(g, new LinearLayout.LayoutParams(dp(46), dp(46)));
    }
    LinearLayout t = column();
    t.setPadding(dp(12), 0, 0, 0);
    TextView n = label(title, 16, TEXT);
    n.setTypeface(null, unread > 0 ? Typeface.BOLD : Typeface.NORMAL);
    n.setSingleLine(true);
    TextView s2 = label(subtitle, 13, unread > 0 ? TEXT : MUTED);
    s2.setSingleLine(true);
    s2.setEllipsize(android.text.TextUtils.TruncateAt.END);
    t.addView(n);
    t.addView(s2);
    r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
    if (unread > 0) {
      TextView badge = label(String.valueOf(unread), 11, 0xffffffff);
      badge.setGravity(Gravity.CENTER);
      badge.setPadding(dp(7), 0, dp(7), 0);
      badge.setBackground(background(0xfff23663, 99));
      r.addView(badge, new LinearLayout.LayoutParams(-2, dp(22)));
    }
    r.setOnClickListener(v -> open.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.setMargins(0, dp(4), 0, dp(4));
    parent.addView(r, p);
  }

  private void createGroup() {
    final JSONArray users = conversationUsers;
    if (users == null || users.length() == 0) { say("Hãy nhắn tin với ít nhất một người trước khi tạo nhóm."); return; }
    final String[] names = new String[users.length()];
    final boolean[] chosen = new boolean[users.length()];
    for (int i = 0; i < names.length; i++) names[i] = users.optJSONObject(i).optString("name");
    final EditText name = new EditText(this);
    name.setHint("Tên nhóm");
    new Sheet(this).setTitle("Chọn thành viên").setMultiChoiceItems(names, chosen, (d, w, c) -> chosen[w] = c)
      .setPositiveButton("Tiếp", (d, w) -> new Sheet(this).setTitle("Tên nhóm").setView(name).setPositiveButton("Tạo nhóm", (d2, w2) -> {
        JSONArray ids = new JSONArray();
        for (int i = 0; i < chosen.length; i++) if (chosen[i]) ids.put(users.optJSONObject(i).optString("id"));
        request("POST", "/api/groups", json("name", name.getText().toString(), "members", ids), r -> groupChat(r.optJSONObject("group")));
      }).setNegativeButton("Hủy", null).show())
      .setNegativeButton("Hủy", null).show();
  }

  private void groupChat(final JSONObject g) {
    shell(g.optString("name"), true);
    final LinearLayout list = column();
    content.addView(list);
    EditText input = input(content, "Nhắn vào nhóm", "", false);
    final String path = "/api/groups/" + g.optString("id") + "/messages";
    content.addView(primary("Gửi", () -> request("POST", path, json("body", input.getText().toString()), d -> { input.setText(""); loadGroup(path, list); })));
    content.addView(button("📎 Gửi ảnh, video hoặc tệp", () -> { attachTarget = path; pickFile(303, "*/*"); }));
    content.addView(button("⋯ Quản lý nhóm", () -> groupMenu(g)));
    content.addView(button("Rời nhóm", () -> confirm("Rời nhóm " + g.optString("name") + "?", () -> request("POST", "/api/groups/" + g.optString("id") + "/leave", json(), d -> navigate("inbox")))));
    content.addView(button("Quay lại hộp thư", () -> navigate("inbox")));
    loadGroup(path, list);
    final int generation = screen;
    poll = () -> {
      if (!stopped && generation == screen) {
        loadGroup(path, list);
        handler.postDelayed(poll, 4000);
      }
    };
    handler.postDelayed(poll, 4000);
  }

  private void loadGroup(String path, LinearLayout list) {
    request("GET", path, null, d -> {
      JSONArray messages = d.optJSONArray("messages");
      String signature = messages == null ? "" : messages.toString();
      if (signature.equals(lastMessages) && list.getChildCount() > 0) return;
      lastMessages = signature;
      list.removeAllViews();
      for (int i = 0; messages != null && i < messages.length(); i++) {
        final JSONObject m = messages.optJSONObject(i);
        boolean own = m.optString("sender").equals(me.optString("id"));
        final JSONObject file = m.optJSONObject("attachment");
        TextView text = label((own ? "Bạn" : m.optJSONObject("author").optString("name")) + ": " + (m.optBoolean("recalled") ? "Tin nhắn đã được thu hồi" : m.optString("body")) + (file == null ? "" : "\n📎 " + file.optString("name")), 16, TEXT);
        text.setPadding(dp(14), dp(10), dp(14), dp(10));
        text.setBackground(background(own ? PRIMARY_SOFT : CARD, 16));
        if (file != null) text.setOnClickListener(v -> openAttachment(file));
        text.setOnLongClickListener(v -> { messageMenu("group", m, own, () -> { lastMessages = ""; loadGroup(path, list); }); return true; });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(own ? dp(28) : 0, dp(4), own ? 0 : dp(28), dp(4));
        list.addView(text, p);
      }
    });
  }

  // ----- Chọn tệp: 300 ảnh/video bài viết · 303 tệp tin nhắn · 304 tin 24h · 305 nhạc (quản trị)
  private void pickFile(int code, String types) {
    Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
    pick.addCategory(Intent.CATEGORY_OPENABLE);
    if (types.contains("|")) {
      pick.setType("*/*");
      pick.putExtra(Intent.EXTRA_MIME_TYPES, new String[] { "image/png", "image/jpeg", "image/webp", "video/mp4" });
    } else pick.setType(types);
    try { startActivityForResult(pick, code); } catch (Exception e) { say("Không mở được trình chọn tệp."); }
  }

  private String dataUrl(android.net.Uri uri, int max, String forcedType) throws Exception {
    byte[] bytes = NativeApi.read(getContentResolver().openInputStream(uri), max);
    String type = forcedType != null ? forcedType : getContentResolver().getType(uri);
    if (type == null) type = "application/octet-stream";
    return "data:" + type + ";base64," + android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP);
  }

  private String fileName(android.net.Uri uri) {
    try (android.database.Cursor c = getContentResolver().query(uri, new String[] { android.provider.OpenableColumns.DISPLAY_NAME }, null, null, null)) {
      if (c != null && c.moveToFirst()) return c.getString(0);
    } catch (Exception ignored) {}
    return "tep-dinh-kem";
  }

  private void picked(int code, android.net.Uri uri) {
    String type = getContentResolver().getType(uri);
    boolean video = "video/mp4".equals(type);
    try {
      if (code == 300 || code == 304) {
        if (!video && !Arrays.asList("image/png", "image/jpeg", "image/webp").contains(type)) { say("Chọn ảnh PNG/JPEG/WebP hoặc video MP4."); return; }
        String media = dataUrl(uri, (video ? 12 : 5) * 1024 * 1024, null);
        if (code == 300) {
          pendingMedia = media;
          if (attachButton != null) attachButton.setText(video ? "✓ Đã chọn video" : "✓ Đã chọn ảnh");
          return;
        }
        final EditText caption = new EditText(this);
        caption.setHint("Viết gì đó cho tin (không bắt buộc)");
        final String storyMedia = media;
        new Sheet(this).setTitle("Đăng tin 24 giờ").setView(caption).setPositiveButton("Đăng", (d, w) -> {
          say("Đang đăng tin…");
          request("POST", "/api/stories", json("body", caption.getText().toString(), "media", storyMedia), r -> { say("Đã đăng tin, hiển thị 24 giờ với người theo dõi."); navigate("feed"); });
        }).setNegativeButton("Hủy", null).show();
        return;
      }
      if (code == 303) {
        JSONObject file = json("name", fileName(uri), "data", dataUrl(uri, 20 * 1024 * 1024, null));
        say("Đang gửi tệp…");
        final String target = attachTarget;
        request("POST", target, json("body", "", "attachment", file), d -> {
          say("Đã gửi tệp.");
          if (target.startsWith("/api/users/") && chatUser != null) chat(chatUser);
          else navigate("inbox");
        });
        return;
      }
      if (code == 305) uploadMusic(uri);
      if (code == 306) {
        if (!Arrays.asList("image/png", "image/jpeg", "image/webp").contains(type)) { say("Chọn ảnh PNG/JPEG/WebP."); return; }
        request("POST", "/api/me/cover", json("data", dataUrl(uri, 3 * 1024 * 1024, null)), d -> { say("Đã đổi ảnh bìa."); navigate("profile"); });
      }
    } catch (Exception e) {
      say(code == 303 ? "Tệp tối đa 20 MB." : video ? "Video tối đa 12 MB." : "Ảnh tối đa 5 MB.");
    }
  }

  // ----- Quản trị: yêu cầu quên mật khẩu và thư viện nhạc
  private void adminResets() {
    final LinearLayout box = column();
    content.addView(box);
    request("GET", "/api/admin/password-resets", null, d -> {
      JSONArray rows = d.optJSONArray("requests");
      box.addView(label("Yêu cầu quên mật khẩu", 20, TEXT));
      int open = 0;
      for (int i = 0; rows != null && i < rows.length(); i++) {
        final JSONObject r = rows.optJSONObject(i);
        if (!r.optString("status").equals("open")) continue;
        open++;
        LinearLayout c = column();
        c.setPadding(dp(14), dp(12), dp(14), dp(12));
        c.setBackground(background(CARD, 16));
        c.addView(label("@" + r.optString("username") + (r.isNull("user_id") ? " · không tồn tại" : ""), 16, TEXT));
        c.addView(label("Liên hệ: " + r.optString("contact") + (r.optString("note").isEmpty() ? "" : "\n" + r.optString("note")), 13, MUTED));
        LinearLayout acts = row();
        if (!r.isNull("user_id")) acts.addView(chip("Cấp mật khẩu tạm", true, () -> confirm("Cấp mật khẩu tạm cho @" + r.optString("username") + "?", () ->
          request("POST", "/api/admin/password-resets/" + r.optString("id") + "/reset", json(), x ->
            new Sheet(this).setTitle("Mật khẩu tạm").setMessage("@" + x.optString("username") + ": " + x.optString("temporaryPassword") + "\n\nGửi riêng cho người dùng và nhắc họ đổi mật khẩu ngay.").setPositiveButton("Xong", (dd, ww) -> admin()).show()))));
        acts.addView(chip("Bỏ qua", false, () -> request("POST", "/api/admin/password-resets/" + r.optString("id") + "/dismiss", json(), x -> admin())));
        c.addView(acts);
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        box.addView(c, p);
      }
      if (open == 0) box.addView(label("Không có yêu cầu mới.", 14, MUTED));
    });
  }

  private android.media.MediaPlayer adminPlayer;

  private void adminMusic() {
    final LinearLayout box = column();
    content.addView(box);
    api.call("GET", "/api/music", null, (d, e, s) -> {
      if (isDestroyed()) return;
      box.addView(label("Thư viện nhạc", 20, TEXT));
      JSONArray tracks = d == null ? null : d.optJSONArray("tracks");
      if (tracks == null || tracks.length() == 0) box.addView(label("Chưa có bài nào.", 14, MUTED));
      for (int i = 0; tracks != null && i < tracks.length(); i++) {
        final JSONObject t = tracks.optJSONObject(i);
        LinearLayout r = row();
        r.setPadding(dp(10), dp(6), dp(10), dp(6));
        r.setBackground(background(CARD, 14));
        r.addView(chip("▶", false, () -> {
          try {
            if (adminPlayer != null) adminPlayer.release();
            adminPlayer = new android.media.MediaPlayer();
            Map<String, String> headers = new HashMap<>();
            headers.put("Cookie", api.jar());
            adminPlayer.setDataSource(this, android.net.Uri.parse(server() + t.optString("url")), headers);
            adminPlayer.setOnPreparedListener(mp -> mp.start());
            adminPlayer.prepareAsync();
          } catch (Exception ex) { say("Không phát được bài này."); }
        }));
        LinearLayout tx = column();
        tx.setPadding(dp(8), 0, 0, 0);
        tx.addView(label(t.optString("title"), 15, TEXT));
        tx.addView(label(t.optString("artist") + " · " + t.optString("license"), 11, MUTED));
        r.addView(tx, new LinearLayout.LayoutParams(0, -2, 1));
        r.addView(chip("Xoá", false, () -> confirm("Xoá bài “" + t.optString("title") + "” khỏi thư viện?", () -> request("DELETE", "/api/music", json("file", t.optString("file")), x -> admin()))));
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.setMargins(0, dp(4), 0, dp(4));
        box.addView(r, p);
      }
      box.addView(button("＋ Tải bài nhạc lên (MP3/M4A ≤15 MB)", () -> pickFile(305, "audio/*")));
    });
  }

  private void uploadMusic(final android.net.Uri uri) throws Exception {
    String name = fileName(uri);
    boolean m4a = name.toLowerCase(Locale.ROOT).endsWith(".m4a");
    final String data = dataUrl(uri, 15 * 1024 * 1024, m4a ? "audio/mp4" : "audio/mpeg");
    LinearLayout box = column();
    box.setPadding(dp(20), dp(8), dp(20), 0);
    final EditText title = new EditText(this), artist = new EditText(this), license = new EditText(this), source = new EditText(this);
    title.setHint("Tên bài");
    title.setText(name.replaceAll("\\.[^.]+$", ""));
    artist.setHint("Nghệ sĩ");
    license.setHint("Giấy phép (vd: CC0, CC BY 4.0, tự sáng tác)");
    source.setHint("Link nguồn (không bắt buộc)");
    final CheckBox rights = new CheckBox(this);
    rights.setText("Tôi có quyền dùng và chia sẻ bài này trên Kinnect.");
    box.addView(title);
    box.addView(artist);
    box.addView(license);
    box.addView(source);
    box.addView(rights);
    new Sheet(this).setTitle("Thêm bài vào thư viện").setView(box).setPositiveButton("Tải lên", (d, w) -> {
      say("Đang tải nhạc lên…");
      request("POST", "/api/music", json("data", data, "title", title.getText().toString(), "artist", artist.getText().toString(), "license", license.getText().toString(), "source", source.getText().toString(), "rights", rights.isChecked()), r -> { say("Đã thêm bài vào thư viện nhạc."); admin(); });
    }).setNegativeButton("Hủy", null).show();
  }


  // ===================== Tin nhắn, nhóm, bình luận nâng cao =====================
  private boolean shortsFollowing = false;
  private long lastActivity = 0;

  private void activity() {
    if (me == null || System.currentTimeMillis() - lastActivity < 60000) return;
    lastActivity = System.currentTimeMillis();
    api.call("POST", "/api/me/activity", json(), (d, e, s) -> {});
  }

  private String[] reactionGlyphs() {
    String[] names = new String[REACTIONS.length];
    for (int i = 0; i < names.length; i++) names[i] = REACTIONS[i][1];
    return names;
  }

  private void messageMenu(final String kind, final JSONObject m, boolean own, final Runnable refresh) {
    if (m.optBoolean("recalled")) return;
    final String base = "/api/chat-messages/" + kind + "/" + m.optString("id");
    final List<String> labels = new ArrayList<>();
    final List<Runnable> actions = new ArrayList<>();
    labels.add("Thả cảm xúc");
    actions.add(() -> new Sheet(this).setItems(reactionGlyphs(), (d, w) ->
      request("POST", base + "/reaction", json("reaction", REACTIONS[w][0]), r -> refresh.run())).show());
    labels.add(m.optBoolean("pinned") ? "Bỏ ghim tin nhắn" : "Ghim tin nhắn");
    actions.add(() -> request(m.optBoolean("pinned") ? "DELETE" : "POST", base + "/pin", json(), r -> refresh.run()));
    if (own) {
      labels.add("Thu hồi với mọi người");
      actions.add(() -> confirm("Thu hồi tin nhắn này?", () -> request("POST", base + "/recall", json(), r -> refresh.run())));
    }
    labels.add("Xoá ở phía bạn");
    actions.add(() -> request("DELETE", base, json(), r -> refresh.run()));
    if (!own) {
      labels.add("Báo cáo tin nhắn");
      actions.add(() -> report("message", m.optString("id")));
    }
    JSONObject reactions = m.optJSONObject("reactions");
    String title = null;
    if (reactions != null && reactions.length() > 0) {
      StringBuilder b = new StringBuilder();
      for (String[] r : REACTIONS) if (reactions.optInt(r[0]) > 0) b.append(r[1]).append(" ").append(reactions.optInt(r[0])).append("  ");
      title = b.toString().trim();
    }
    new Sheet(this).setTitle(title).setItems(labels.toArray(new String[0]), (d, w) -> actions.get(w).run()).show();
  }

  private void conversationMenu(final String kind, final String id, final String name) {
    final String prefs = "/api/chat-preferences/" + kind + "/" + id;
    request("GET", prefs, null, p -> {
      final boolean muted = p.optBoolean("muted"), pinned = p.optBoolean("pinned");
      String[] items = { pinned ? "Bỏ ghim cuộc trò chuyện" : "Ghim lên đầu hộp thư", muted ? "Bật lại thông báo" : "Tắt thông báo", "Xoá lịch sử trò chuyện (phía bạn)", "Đóng" };
      new Sheet(this).setTitle(name).setItems(items, (d, w) -> {
        if (w == 0) request("POST", prefs, json("pinned", !pinned), r -> say(pinned ? "Đã bỏ ghim." : "Đã ghim cuộc trò chuyện."));
        if (w == 1) request("POST", prefs, json("muted", !muted), r -> say(muted ? "Đã bật thông báo." : "Đã tắt thông báo cuộc trò chuyện."));
        if (w == 2) confirm("Xoá toàn bộ lịch sử ở phía bạn?", () -> request("DELETE", kind.equals("direct") ? "/api/users/" + id + "/messages" : "/api/groups/" + id + "/messages", json(), r -> navigate("inbox")));
      }).show();
    });
  }

  private void groupMenu(final JSONObject g) {
    final String id = g.optString("id");
    final boolean owner = g.optString("owner").equals(me.optString("id"));
    final List<String> labels = new ArrayList<>();
    final List<Runnable> actions = new ArrayList<>();
    labels.add("Thành viên");
    actions.add(() -> {
      shell("Thành viên · " + g.optString("name"), true);
      JSONArray members = g.optJSONArray("members");
      for (int i = 0; members != null && i < members.length(); i++) {
        final JSONObject u = members.optJSONObject(i);
        boolean self = u.optString("id").equals(me.optString("id"));
        inboxRow(content, u, u.optString("name") + (u.optString("id").equals(g.optString("owner")) ? " · Trưởng nhóm" : ""), "@" + u.optString("username"), 0, () -> {
          if (owner && !self) new Sheet(this).setItems(new String[] { "Xem hồ sơ", "Xoá khỏi nhóm" }, (d, w) -> {
            if (w == 0) person(u);
            else confirm("Xoá " + u.optString("name") + " khỏi nhóm?", () -> request("DELETE", "/api/groups/" + id + "/members", json("userId", u.optString("id")), r -> groupChat(r.optJSONObject("group"))));
          }).show();
          else person(u);
        });
      }
      content.addView(button("Quay lại nhóm", () -> groupChat(g)));
    });
    if (owner) {
      labels.add("Đổi tên nhóm");
      actions.add(() -> {
        final EditText name = new EditText(this);
        name.setText(g.optString("name"));
        new Sheet(this).setTitle("Tên nhóm").setView(name).setPositiveButton("Lưu", (d, w) ->
          request("PATCH", "/api/groups/" + id, json("name", name.getText().toString()), r -> groupChat(r.optJSONObject("group")))).setNegativeButton("Hủy", null).show();
      });
      labels.add("Thêm thành viên");
      actions.add(() -> request("GET", "/api/conversations", null, data -> {
        final JSONArray users = data.optJSONArray("users");
        if (users == null || users.length() == 0) { say("Chưa có ai để thêm."); return; }
        final String[] names = new String[users.length()];
        final boolean[] chosen = new boolean[users.length()];
        for (int i = 0; i < names.length; i++) names[i] = users.optJSONObject(i).optString("name");
        new Sheet(this).setTitle("Thêm vào nhóm").setMultiChoiceItems(names, chosen, (d, w, c) -> chosen[w] = c).setPositiveButton("Thêm", (d, w) -> {
          JSONArray ids = new JSONArray();
          for (int i = 0; i < chosen.length; i++) if (chosen[i]) ids.put(users.optJSONObject(i).optString("id"));
          request("POST", "/api/groups/" + id + "/members", json("members", ids), r -> groupChat(r.optJSONObject("group")));
        }).setNegativeButton("Hủy", null).show();
      }));
    }
    labels.add("Tuỳ chọn thông báo / ghim / xoá lịch sử");
    actions.add(() -> conversationMenu("group", id, g.optString("name")));
    new Sheet(this).setTitle(g.optString("name")).setItems(labels.toArray(new String[0]), (d, w) -> actions.get(w).run()).show();
  }

  // Bình luận dạng chuỗi: trả lời, cảm xúc, báo cáo — dùng cho bài viết và video ngắn
  private String replyTo = null;

  private void comments(final String base, final Runnable reload, Runnable back, String backLabel) {
    final LinearLayout list = column();
    content.addView(list);
    final TextView replying = label("", 12, ACCENT);
    content.addView(replying);
    final EditText value = input(content, "Viết bình luận…", "", false);
    content.addView(primary("Gửi", () -> {
      JSONObject payload = json("body", value.getText().toString());
      if (replyTo != null) try { payload.put("parentId", replyTo); } catch (JSONException ignored) {}
      request("POST", base + "/comments", payload, d -> { replyTo = null; reload.run(); });
    }));
    content.addView(button(backLabel, () -> { replyTo = null; back.run(); }));
    request("GET", base + "/comments", null, d -> {
      JSONArray all = d.optJSONArray("comments");
      if (all == null || all.length() == 0) { list.addView(label("Chưa có bình luận. Hãy là người đầu tiên.", 14, MUTED)); return; }
      for (int i = 0; i < all.length(); i++) {
        JSONObject cm = all.optJSONObject(i);
        if (cm.isNull("parentId") || cm.optString("parentId").isEmpty()) {
          commentRow(base, cm, list, 0, reload, replying, value);
          for (int j = 0; j < all.length(); j++) {
            JSONObject child = all.optJSONObject(j);
            if (child.optString("parentId").equals(cm.optString("id"))) commentRow(base, child, list, 1, reload, replying, value);
          }
        }
      }
    });
  }

  private void commentRow(final String base, final JSONObject cm, LinearLayout list, int depth, final Runnable reload, final TextView replying, final EditText value) {
    LinearLayout r = row();
    r.setPadding(dp(depth * 36), dp(6), 0, dp(2));
    r.setGravity(Gravity.TOP);
    avatar(cm.optJSONObject("author"), r, depth == 0 ? 34 : 28);
    LinearLayout t = column();
    LinearLayout bubble = column();
    bubble.setPadding(dp(12), dp(8), dp(12), dp(8));
    bubble.setBackground(background(CARD, 14));
    bubble.addView(label(cm.optJSONObject("author").optString("name"), 12, ACCENT));
    bubble.addView(label(cm.optString("body"), 15, TEXT));
    t.addView(bubble);
    LinearLayout meta = row();
    String mine = cm.isNull("myReaction") ? "" : cm.optString("myReaction");
    int total = 0;
    JSONObject counts = cm.optJSONObject("reactions");
    if (counts != null) for (String[] x : REACTIONS) total += counts.optInt(x[0]);
    String glyph = "Thích";
    for (String[] x : REACTIONS) if (x[0].equals(mine)) glyph = x[1];
    TextView like = label(ago(cm.optLong("created")) + "   " + glyph + (total > 0 ? " " + total : ""), 12, mine.isEmpty() ? MUTED : ACCENT);
    like.setOnClickListener(v -> request("POST", base + "/comments/" + cm.optString("id") + "/reaction", mine.isEmpty() ? json("reaction", "like") : json("reaction", JSONObject.NULL), x -> reload.run()));
    like.setOnLongClickListener(v -> {
      new Sheet(this).setItems(reactionGlyphs(), (d, w) -> request("POST", base + "/comments/" + cm.optString("id") + "/reaction", json("reaction", REACTIONS[w][0]), x -> reload.run())).show();
      return true;
    });
    meta.addView(like);
    TextView reply = label("   Trả lời", 12, MUTED);
    final String parent = cm.isNull("parentId") || cm.optString("parentId").isEmpty() ? cm.optString("id") : cm.optString("parentId");
    reply.setOnClickListener(v -> {
      replyTo = parent;
      replying.setText("Đang trả lời " + cm.optJSONObject("author").optString("name") + " · chạm để huỷ");
      replying.setOnClickListener(x -> { replyTo = null; replying.setText(""); });
      value.requestFocus();
    });
    meta.addView(reply);
    TextView rep = label("   Báo cáo", 12, MUTED);
    rep.setOnClickListener(v -> report("comment", cm.optString("id")));
    meta.addView(rep);
    t.addView(meta);
    LinearLayout.LayoutParams tp = new LinearLayout.LayoutParams(0, -2, 1);
    tp.setMargins(dp(8), 0, 0, 0);
    r.addView(t, tp);
    list.addView(r);
  }
}
