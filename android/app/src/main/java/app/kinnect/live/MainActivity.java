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
  private LinearLayout headActions;
  private TextView inboxBadge, bellBadge;
  private int inboxCount, bellCount;
  private long badgesAt;

  private void shell(String title, boolean navigation) {
    onTabRoot = false;
    stopShort();
    stopLocation();
    screen++;
    handler.removeCallbacksAndMessages(null);
    poll = null;
    chatUser = null;
    chatReload = null;
    root = column();
    root.setBackgroundColor(BG);
    root.setOnApplyWindowInsetsListener((v, insets) -> {
      v.setPadding(0, insets.getSystemWindowInsetTop(), 0, insets.getSystemWindowInsetBottom());
      return insets;
    });
    setContentView(root);
    getWindow().setStatusBarColor(CARD);
    getWindow().setNavigationBarColor(CARD);
    // Thanh trên giống web: logo · Live · Tin nhắn · Thông báo · tài khoản
    toolbar = row();
    toolbar.setPadding(dp(12), 0, dp(10), 0);
    toolbar.setBackgroundColor(CARD);
    ImageView logo = new ImageView(this);
    logo.setImageResource(getResources().getIdentifier("kinnect_icon", "drawable", getPackageName()));
    logo.setClipToOutline(true);
    logo.setBackground(background(CARD, 10));
    toolbar.addView(logo, new LinearLayout.LayoutParams(dp(34), dp(34)));
    TextView brand = label("Kinnect", 21, ACCENT);
    brand.setTypeface(null, Typeface.BOLD);
    brand.getPaint().setShader(new LinearGradient(0, 0, dp(90), 0, 0xff6d4aff, PINK, Shader.TileMode.CLAMP));
    brand.setPadding(dp(8), 0, 0, 0);
    toolbar.addView(brand, new LinearLayout.LayoutParams(0, -2, 1));
    if (me != null && navigation) {
      toolbar.addView(topIcon("live", "Live", false, () -> startActivity(new Intent(this, LiveActivity.class)), null));
      FrameLayout inboxHolder = topIcon("inbox", "Tin nhắn", tab.equals("inbox"), () -> navigate("inbox"), "inbox");
      toolbar.addView(inboxHolder);
      toolbar.addView(topIcon("bell", "Thông báo", false, () -> notifications(), "bell"));
      ImageView meButton = new ImageView(this);
      GradientDrawable round = new GradientDrawable();
      round.setShape(GradientDrawable.OVAL);
      meButton.setBackground(round);
      meButton.setClipToOutline(true);
      meButton.setImageBitmap(initials(me, dp(38)));
      loadAvatarInto(me, meButton);
      meButton.setContentDescription("Tài khoản");
      meButton.setOnClickListener(v -> meMenu());
      LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(dp(38), dp(38));
      mp.setMargins(dp(6), 0, 0, 0);
      toolbar.addView(meButton, mp);
      refreshBadges();
    } else if (me == null) {
      ImageView settings = icon("settings", 22, MUTED);
      settings.setPadding(dp(10), dp(10), dp(10), dp(10));
      settings.setContentDescription("Cài đặt");
      settings.setOnClickListener(v -> settings());
      toolbar.addView(settings, new LinearLayout.LayoutParams(dp(44), dp(44)));
    }
    root.addView(toolbar, new LinearLayout.LayoutParams(-1, dp(58)));
    View line = new View(this);
    line.setBackgroundColor(LINE);
    root.addView(line, new LinearLayout.LayoutParams(-1, 1));
    notice = label("", 12, ACCENT);
    notice.setPadding(dp(16), 0, dp(16), 0);
    notice.setVisibility(View.GONE);
    root.addView(notice);
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    content = column();
    content.setPadding(dp(12), dp(10), dp(12), dp(18));
    scroll.addView(content);
    root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    headActions = null;
    if (navigation && me != null && !title.isEmpty()) {
      LinearLayout head = row();
      TextView heading = label(title, 23, TEXT);
      heading.setTypeface(null, Typeface.BOLD);
      head.addView(heading, new LinearLayout.LayoutParams(0, -2, 1));
      headActions = row();
      head.addView(headActions);
      LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(-1, -2);
      hp.bottomMargin = dp(6);
      content.addView(head, hp);
    }
    if (navigation) {
      View top = new View(this);
      top.setBackgroundColor(LINE);
      root.addView(top, new LinearLayout.LayoutParams(-1, 1));
      bottom = row();
      bottom.setBackgroundColor(CARD);
      String[][] items = { { "feed", "feed", "Bảng tin" }, { "discover", "discover", "Khám phá" }, { "create", "plus", "Quay video" }, { "shorts", "shorts", "Video" }, { "profile", "profile", "Hồ sơ" } };
      for (final String[] it : items) {
        if (it[0].equals("create")) {
          FrameLayout holder = new FrameLayout(this);
          FrameLayout plus = new FrameLayout(this);
          plus.setBackground(background(ACCENT, 14));
          plus.addView(icon("plus", 24, WHITE), new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
          plus.setContentDescription(it[2]);
          plus.setOnClickListener(v -> chooseVideo());
          holder.addView(plus, new FrameLayout.LayoutParams(dp(48), dp(42), Gravity.CENTER));
          bottom.addView(holder, new LinearLayout.LayoutParams(0, dp(62), 1));
          continue;
        }
        boolean active = tab.equals(it[0]);
        LinearLayout b = column();
        b.setGravity(Gravity.CENTER);
        b.addView(icon(it[1], 24, active ? ACCENT : TEXT), new LinearLayout.LayoutParams(dp(24), dp(24)));
        TextView t = label(it[2], 11, active ? ACCENT : TEXT);
        t.setPadding(0, dp(2), 0, 0);
        t.setGravity(Gravity.CENTER);
        t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
        b.addView(t);
        b.setContentDescription(it[2]);
        b.setOnClickListener(v -> navigate(it[0]));
        bottom.addView(b, new LinearLayout.LayoutParams(0, dp(62), 1));
      }
      root.addView(bottom);
    }
  }

  private ImageView icon(String name, int size, int color) {
    ImageView v = new ImageView(this);
    int id = getResources().getIdentifier("ic_" + name, "drawable", getPackageName());
    if (id != 0) {
      android.graphics.drawable.Drawable d = getDrawable(id).mutate();
      d.setTint(color);
      v.setImageDrawable(d);
    }
    v.setScaleType(ImageView.ScaleType.FIT_CENTER);
    return v;
  }

  private FrameLayout topIcon(String name, String label, boolean active, Runnable action, String badgeKey) {
    FrameLayout f = new FrameLayout(this);
    ImageView i = icon(name, 24, active ? ACCENT : TEXT);
    f.addView(i, new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
    if (badgeKey != null) {
      TextView badge = label("", 10, WHITE);
      badge.setTypeface(null, Typeface.BOLD);
      badge.setGravity(Gravity.CENTER);
      badge.setPadding(dp(4), 0, dp(4), 0);
      badge.setMinWidth(dp(17));
      GradientDrawable bd = background(0xfff23663, 99);
      bd.setStroke(dp(2), CARD);
      badge.setBackground(bd);
      badge.setVisibility(View.GONE);
      FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-2, dp(18), Gravity.TOP | Gravity.END);
      bp.topMargin = dp(4);
      f.addView(badge, bp);
      if (badgeKey.equals("inbox")) inboxBadge = badge; else bellBadge = badge;
      showBadge(badge, badgeKey.equals("inbox") ? inboxCount : bellCount);
    }
    f.setContentDescription(label);
    f.setOnClickListener(v -> action.run());
    f.setLayoutParams(new LinearLayout.LayoutParams(dp(42), dp(46)));
    return f;
  }

  private void showBadge(TextView badge, int count) {
    if (badge == null) return;
    badge.setText(count > 9 ? "9+" : String.valueOf(count));
    badge.setVisibility(count > 0 ? View.VISIBLE : View.GONE);
  }

  private void refreshBadges() {
    if (me == null || System.currentTimeMillis() - badgesAt < 20000) return;
    badgesAt = System.currentTimeMillis();
    api.call("GET", "/api/notifications", null, (d, e, s) -> {
      JSONArray rows = d == null ? null : d.optJSONArray("notifications");
      int inbox = 0, bell = 0;
      for (int i = 0; rows != null && i < rows.length(); i++) {
        JSONObject n = rows.optJSONObject(i);
        if (n.optInt("seen") != 0) continue;
        String k = n.optString("kind");
        if (k.equals("message") || k.equals("group_message")) inbox++; else bell++;
      }
      inboxCount = inbox;
      bellCount = bell;
      showBadge(inboxBadge, inbox);
      showBadge(bellBadge, bell);
    });
  }

  private void loadAvatarInto(JSONObject u, final ImageView image) {
    String path = u == null ? "" : u.optString("avatar", "");
    if (path.isEmpty() || path.equals("null")) return;
    api.image(path, bytes -> {
      if (bytes == null || isDestroyed()) return;
      Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
      if (b != null) image.setImageBitmap(b);
    });
  }

  // Chip kiểu web: viền mảnh, nền trắng; đang chọn → nền tím nhạt chữ tím (soft) hoặc tím đặc (solid)
  private TextView webChip(String text, boolean active, boolean solid, Runnable action) {
    TextView t = label(text, 14, active ? (solid ? WHITE : ACCENT) : TEXT);
    t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
    t.setGravity(Gravity.CENTER);
    t.setPadding(dp(16), 0, dp(16), 0);
    GradientDrawable g = background(active ? (solid ? ACCENT : PRIMARY_SOFT) : CARD, 999);
    if (!active) g.setStroke(1, LINE);
    t.setBackground(g);
    t.setOnClickListener(v -> action.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, dp(38));
    p.setMargins(0, dp(4), dp(8), dp(4));
    t.setLayoutParams(p);
    return t;
  }

  private View hscroll(LinearLayout row) {
    HorizontalScrollView s = new HorizontalScrollView(this);
    s.setHorizontalScrollBarEnabled(false);
    s.addView(row);
    return s;
  }

  private TextView sectionLabel(String text) {
    TextView t = label(text.toUpperCase(Locale.ROOT), 13, MUTED);
    t.setTypeface(null, Typeface.BOLD);
    t.setLetterSpacing(0.04f);
    t.setPadding(dp(4), dp(14), 0, dp(6));
    return t;
  }

  private View divider() {
    View v = new View(this);
    v.setBackgroundColor(LINE);
    v.setLayoutParams(new LinearLayout.LayoutParams(-1, 1));
    return v;
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
    // Chỉ một chế độ trên màn; dòng nhỏ ở cuối để chuyển qua lại như web
    TextView swap = new TextView(this);
    android.text.SpannableStringBuilder sw = new android.text.SpannableStringBuilder(register ? "Đã có tài khoản? " : "Chưa có tài khoản? ");
    int start = sw.length();
    sw.append(register ? "Đăng nhập" : "Tạo tài khoản mới");
    sw.setSpan(new android.text.style.ForegroundColorSpan(ACCENT), start, sw.length(), 0);
    sw.setSpan(new android.text.style.StyleSpan(Typeface.BOLD), start, sw.length(), 0);
    swap.setText(sw);
    swap.setTextColor(MUTED);
    swap.setTextSize(14);
    swap.setGravity(Gravity.CENTER);
    swap.setPadding(0, dp(14), 0, dp(2));
    swap.setOnClickListener(v -> auth(!register));
    panel.addView(swap);
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
        : next.equals("inbox")
          ? "Tin nhắn"
          : "",
      true
    );
    onTabRoot = true;
    if (next.equals("shorts")) shorts();
    if (next.equals("discover")) discover();
    if (next.equals("feed")) feed();
    if (next.equals("inbox")) inbox();
    if (next.equals("profile")) profile();
    if (next.equals("live")) { startActivity(new Intent(this, LiveActivity.class)); tab = "feed"; feed(); }
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
    final boolean hasLocation = me != null && me.optBoolean("hasLocation");
    LinearLayout box = card();
    box.setPadding(dp(12), dp(10), dp(12), dp(12));
    LinearLayout chipsRow = row();
    String[][] sorts = { { "near", "Gần đây" }, { "new", "Mới" }, { "active", "Đang online" }, { "interests", "Hợp gu" } };
    for (final String[] item : sorts) chipsRow.addView(webChip(item[1], discoverSort.equals(item[0]), false, () -> {
      discoverSort = item[0];
      if (item[0].equals("near") && !hasLocation) { requestLocation(); return; }
      navigate("discover");
    }));
    box.addView(hscroll(chipsRow));
    LinearLayout searchRow = row();
    final EditText search = new EditText(this);
    search.setHint("Tìm bạn...");
    search.setTextColor(TEXT);
    search.setHintTextColor(MUTED);
    search.setSingleLine(true);
    search.setPadding(dp(16), 0, dp(16), 0);
    search.setBackground(background(SOFT, 999));
    searchRow.addView(search, new LinearLayout.LayoutParams(0, dp(46), 1));
    TextView go = label("Tìm", 15, WHITE);
    go.setTypeface(null, Typeface.BOLD);
    go.setGravity(Gravity.CENTER);
    go.setBackground(background(ACCENT, 999));
    LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(dp(64), dp(46));
    gp.leftMargin = dp(8);
    searchRow.addView(go, gp);
    LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-1, -2);
    sp.topMargin = dp(8);
    box.addView(searchRow, sp);
    final boolean nearby = hasLocation && discoverSort.equals("near");
    go.setOnClickListener(v -> loadPeople(search.getText().toString(), nearby));
    search.setOnEditorActionListener((v, a, e) -> { loadPeople(search.getText().toString(), nearby); return true; });
    LinearLayout loc = row();
    loc.setPadding(dp(12), dp(8), dp(8), dp(8));
    loc.setBackground(background(PRIMARY_SOFT, 12));
    loc.addView(label(hasLocation ? "📍 Đang hiện người quanh bạn (gần đúng)" : "📍 Bật vị trí để thấy người gần bạn", 13, TEXT), new LinearLayout.LayoutParams(0, -2, 1));
    TextView locBtn = label(hasLocation ? "Cập nhật" : "Bật vị trí", 13, TEXT);
    locBtn.setTypeface(null, Typeface.BOLD);
    locBtn.setPadding(dp(12), dp(8), dp(12), dp(8));
    locBtn.setBackground(background(CARD, 10));
    locBtn.setOnClickListener(v -> requestLocation());
    loc.addView(locBtn);
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.topMargin = dp(10);
    box.addView(loc, lp);
    content.addView(sectionLabel(discoverSort.equals("near") ? "Quanh bạn" : discoverSort.equals("active") ? "Đang online" : discoverSort.equals("interests") ? "Hợp gu với bạn" : "Mới tham gia"));
    loadPeople("", nearby);
  }

  private LinearLayout people;

  private void loadPeople(String query, boolean nearby) {
    if (people != null && people.getParent() == content) content.removeView(people);
    people = column();
    content.addView(people);
    final LinearLayout list = people;
    request("GET", "/api/discover?q=" + encode(query) + (nearby ? "&nearby=1" : "") + "&sort=" + (discoverSort.equals("near") ? "new" : discoverSort), null, data -> {
      JSONArray users = data.optJSONArray("users");
      if (users == null || users.length() == 0) {
        TextView empty = label("🔎\nChưa tìm thấy ai\nThử từ khoá khác hoặc bổ sung sở thích cho hồ sơ.", 14, MUTED);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(0, dp(40), 0, 0);
        list.addView(empty);
        return;
      }
      LinearLayout line = null;
      for (int i = 0; i < users.length(); i++) {
        if (i % 2 == 0) { line = row(); line.setGravity(Gravity.TOP); list.addView(line); }
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(0, -2, 1);
        p.setMargins(i % 2 == 0 ? 0 : dp(5), 0, i % 2 == 0 ? dp(5) : 0, dp(10));
        line.addView(personTile(users.optJSONObject(i)), p);
      }
      if (users.length() % 2 == 1) line.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
    });
  }

  // Thẻ người dùng như web: ảnh/nền màu, nhãn Online/Mới, tên đè lên ảnh, hai nút theo dõi · nhắn tin.
  private LinearLayout personTile(final JSONObject u) {
    LinearLayout c = column();
    GradientDrawable g = background(CARD, 16);
    g.setStroke(1, LINE);
    c.setBackground(g);
    c.setClipToOutline(true);
    FrameLayout photo = new FrameLayout(this);
    float hue = Math.abs(u.optString("id").hashCode()) % 360;
    photo.setBackground(new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { Color.HSVToColor(new float[] { hue, 0.7f, 0.75f }), Color.HSVToColor(new float[] { (hue + 40) % 360, 0.8f, 0.55f }) }));
    TextView letter = label(u.optString("name", "?").isEmpty() ? "?" : u.optString("name").substring(0, 1).toUpperCase(Locale.ROOT), 40, 0xddffffff);
    letter.setTypeface(null, Typeface.BOLD);
    letter.setGravity(Gravity.CENTER);
    photo.addView(letter, new FrameLayout.LayoutParams(-1, -1));
    final ImageView img = new ImageView(this);
    img.setScaleType(ImageView.ScaleType.CENTER_CROP);
    photo.addView(img, new FrameLayout.LayoutParams(-1, -1));
    loadAvatarInto(u, img);
    View shade = new View(this);
    shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[] { 0x00000000, 0x99000000 }));
    photo.addView(shade, new FrameLayout.LayoutParams(-1, dp(70), Gravity.BOTTOM));
    LinearLayout badges = row();
    if (u.optBoolean("isActive")) badges.addView(tag("● Online", 0xff16a34a));
    if (u.optBoolean("isNew")) badges.addView(tag("Mới", ACCENT));
    FrameLayout.LayoutParams bp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.START);
    bp.setMargins(dp(8), dp(8), 0, 0);
    photo.addView(badges, bp);
    LinearLayout who = column();
    TextView n = label(u.optString("name"), 15, WHITE);
    n.setTypeface(null, Typeface.BOLD);
    n.setSingleLine(true);
    n.setPadding(0, 0, 0, 0);
    who.addView(n);
    TextView h = label(u.optString("distanceBand", "@" + u.optString("username")), 11, 0xddffffff);
    h.setPadding(0, 0, 0, 0);
    who.addView(h);
    FrameLayout.LayoutParams wp = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
    wp.setMargins(dp(10), 0, dp(10), dp(8));
    photo.addView(who, wp);
    photo.setOnClickListener(v -> person(u));
    c.addView(photo, new LinearLayout.LayoutParams(-1, dp(150)));
    LinearLayout acts = row();
    acts.setPadding(dp(6), dp(6), dp(6), dp(6));
    FrameLayout follow = new FrameLayout(this);
    follow.setBackground(background(u.optBoolean("following") ? SOFT : ACCENT, 10));
    follow.addView(icon("person_add", 20, u.optBoolean("following") ? TEXT : WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    follow.setContentDescription(u.optBoolean("following") ? "Bỏ theo dõi" : "Theo dõi");
    follow.setOnClickListener(v -> request(u.optBoolean("following") ? "DELETE" : "POST", "/api/users/" + u.optString("id") + "/follow", json(), d -> { say(u.optBoolean("following") ? "Đã bỏ theo dõi." : "Đã theo dõi " + u.optString("name") + "."); navigate("discover"); }));
    acts.addView(follow, new LinearLayout.LayoutParams(0, dp(40), 1));
    FrameLayout msg = new FrameLayout(this);
    msg.setBackground(background(SOFT, 10));
    msg.addView(icon("comment", 20, TEXT), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    msg.setContentDescription("Nhắn tin");
    msg.setOnClickListener(v -> chat(u));
    LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(0, dp(40), 1);
    mp.leftMargin = dp(6);
    acts.addView(msg, mp);
    c.addView(acts);
    return c;
  }

  private TextView tag(String text, int color) {
    TextView t = label(text, 10, color);
    t.setTypeface(null, Typeface.BOLD);
    t.setPadding(dp(7), dp(2), dp(7), dp(2));
    t.setBackground(background(0xf2ffffff, 99));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, -2);
    p.rightMargin = dp(4);
    t.setLayoutParams(p);
    return t;
  }

  private String join(JSONArray values) {
    List<String> parts = new ArrayList<>();
    if (values != null) for (int i = 0; i < values.length(); i++) parts.add(
      values.optString(i)
    );
    return android.text.TextUtils.join(" · ", parts);
  }

  private void person(final JSONObject u) {
    shell("", true);
    profileCard(u, u.optString("id").equals(me == null ? "" : me.optString("id")));
    content.addView(sectionLabel("Bài viết"));
    final LinearLayout list = column();
    content.addView(list);
    request("GET", "/api/posts?user=" + u.optString("id"), null, d -> { LinearLayout saved = content; content = list; posts(d.optJSONArray("posts"), "Chưa có bài viết."); content = saved; });
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
    String[][] cats = { { "community", "Cộng đồng" }, { "confessions", "Tâm sự" }, { "questions", "Hỏi đáp" }, { "news", "Tin tức" } };
    for (final String[] c : cats) tabs.addView(webChip(c[1], feedCategory.equals(c[0]), true, () -> { feedCategory = c[0]; navigate("feed"); }));
    content.addView(hscroll(tabs));
    if (feedCategory.equals("news")) { news(); return; }
    stories();
    // Ô đăng bài: avatar + "… ơi, bạn đang nghĩ gì?" như web
    LinearLayout composer = card();
    composer.setPadding(dp(12), dp(12), dp(12), dp(12));
    LinearLayout r = row();
    avatar(me, r, 42);
    TextView pill = label(me.optString("name") + " ơi, bạn đang nghĩ gì?", 15, MUTED);
    pill.setSingleLine(true);
    pill.setGravity(Gravity.CENTER_VERTICAL);
    pill.setPadding(dp(16), 0, dp(12), 0);
    pill.setBackground(background(SOFT, 999));
    LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(0, dp(44), 1);
    pp.leftMargin = dp(10);
    r.addView(pill, pp);
    composer.addView(r);
    composer.setOnClickListener(v -> composePost());
    pill.setOnClickListener(v -> composePost());
    final LinearLayout list = column();
    content.addView(list);
    request("GET", "/api/posts?category=" + feedCategory, null, data -> {
      LinearLayout saved = content;
      content = list;
      posts(data.optJSONArray("posts"), "Chưa có bài nào ở mục này. Hãy là người đầu tiên chia sẻ.");
      content = saved;
      if (feedCategory.equals("community")) newsStrip();
    });
  }

  private void composePost() {
    shell("Tạo bài viết", true);
    pendingMedia = null;
    LinearLayout c = card();
    LinearLayout who = row();
    avatar(me, who, 42);
    LinearLayout t = column();
    t.setPadding(dp(10), 0, 0, 0);
    TextView n = label(me.optString("name"), 16, TEXT);
    n.setTypeface(null, Typeface.BOLD);
    t.addView(n);
    final String[] visibility = { "public" };
    final TextView vis = label("🌐 Mọi thành viên ▾", 12, TEXT);
    vis.setPadding(dp(10), dp(3), dp(10), dp(3));
    vis.setBackground(background(SOFT, 999));
    vis.setOnClickListener(v -> {
      visibility[0] = visibility[0].equals("public") ? "followers" : "public";
      vis.setText(visibility[0].equals("public") ? "🌐 Mọi thành viên ▾" : "👥 Người theo dõi ▾");
    });
    t.addView(vis, new LinearLayout.LayoutParams(-2, -2));
    who.addView(t);
    c.addView(who);
    final EditText body = new EditText(this);
    body.setHint(feedCategory.equals("confessions") ? "Chia sẻ điều bạn muốn nói…" : feedCategory.equals("questions") ? "Bạn muốn hỏi điều gì?" : "Bạn đang nghĩ gì?");
    body.setTextSize(18);
    body.setTextColor(TEXT);
    body.setHintTextColor(MUTED);
    body.setBackground(null);
    body.setGravity(Gravity.TOP);
    body.setMinHeight(dp(140));
    c.addView(body);
    final String[] category = { feedCategory.equals("news") ? "community" : feedCategory };
    LinearLayout cats = row();
    String[][] list = { { "community", "Cộng đồng" }, { "confessions", "Tâm sự" }, { "questions", "Hỏi đáp" } };
    final List<TextView> chips = new ArrayList<>();
    for (final String[] it : list) {
      final TextView chip = webChip(it[1], category[0].equals(it[0]), false, () -> {});
      chip.setOnClickListener(v -> { category[0] = it[0]; for (int i = 0; i < chips.size(); i++) { boolean on = list[i][0].equals(it[0]); chips.get(i).setTextColor(on ? ACCENT : TEXT); GradientDrawable g = background(on ? PRIMARY_SOFT : CARD, 999); if (!on) g.setStroke(1, LINE); chips.get(i).setBackground(g); } });
      chips.add(chip);
      cats.addView(chip);
    }
    c.addView(hscroll(cats));
    LinearLayout tools = row();
    tools.setPadding(dp(4), dp(10), dp(4), dp(4));
    final ImageView img = icon("image", 26, 0xff22a565);
    tools.addView(img, new LinearLayout.LayoutParams(dp(26), dp(26)));
    final TextView attach = label("  Ảnh/Video", 15, TEXT);
    tools.addView(attach, new LinearLayout.LayoutParams(0, -2, 1));
    tools.setOnClickListener(v -> { attachButton = null; attachLabel = attach; pickFile(300, "image/*|video/mp4"); });
    c.addView(divider());
    c.addView(tools);
    Button post = primary("Đăng", () -> {});
    post.setOnClickListener(v -> {
      if (body.getText().toString().trim().isEmpty() && pendingMedia == null) { say("Viết nội dung hoặc chọn ảnh/video."); return; }
      post.setEnabled(false);
      say(pendingMedia == null ? "" : "Đang tải lên…");
      JSONObject payload = json("body", body.getText().toString(), "visibility", visibility[0], "category", category[0]);
      if (pendingMedia != null) try { payload.put("media", pendingMedia); } catch (JSONException ignored) {}
      request("POST", "/api/posts", payload, d -> { pendingMedia = null; feedCategory = category[0]; navigate("feed"); });
    });
    content.addView(post);
  }
  private TextView attachLabel;

  private void newsStrip() {
    request("GET", "/api/news", null, d -> {
      JSONArray items = d.optJSONArray("articles");
      if (items == null || items.length() == 0) return;
      LinearLayout head = row();
      head.setPadding(dp(4), dp(18), 0, dp(8));
      TextView t = label("Tin tức", 20, TEXT);
      t.setTypeface(null, Typeface.BOLD);
      head.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
      TextView all = label("Xem tất cả", 13, WHITE);
      all.setTypeface(null, Typeface.BOLD);
      all.setPadding(dp(12), dp(8), dp(12), dp(8));
      all.setBackground(background(ACCENT, 12));
      all.setOnClickListener(v -> { feedCategory = "news"; navigate("feed"); });
      head.addView(all);
      content.addView(head);
      LinearLayout strip = row();
      strip.setGravity(Gravity.TOP);
      for (int i = 0; i < Math.min(items.length(), 10); i++) strip.addView(newsCard(items.optJSONObject(i), dp(240)));
      content.addView(hscroll(strip));
    });
  }

  private LinearLayout newsCard(final JSONObject a, int width) {
    LinearLayout c = column();
    GradientDrawable g = background(CARD, 14);
    g.setStroke(1, LINE);
    c.setBackground(g);
    c.setClipToOutline(true);
    final ImageView img = new ImageView(this);
    img.setScaleType(ImageView.ScaleType.CENTER_CROP);
    img.setBackgroundColor(SOFT);
    c.addView(img, new LinearLayout.LayoutParams(-1, width > 0 ? width * 9 / 16 : dp(190)));
    if (a.optString("image").startsWith("https://")) api.remote(a.optString("image"), bytes -> {
      if (bytes == null || isDestroyed()) return;
      BitmapFactory.Options o = new BitmapFactory.Options();
      o.inSampleSize = 2;
      Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, o);
      if (b != null) img.setImageBitmap(b);
    });
    LinearLayout text = column();
    text.setPadding(dp(12), dp(8), dp(12), dp(12));
    text.addView(label(a.optString("source") + (a.optLong("publishedAt") > 0 ? " · " + ago(a.optLong("publishedAt")) : ""), 11, ACCENT));
    TextView t = label(a.optString("title"), 15, TEXT);
    t.setTypeface(null, Typeface.BOLD);
    t.setMaxLines(3);
    t.setEllipsize(android.text.TextUtils.TruncateAt.END);
    text.addView(t);
    c.addView(text);
    c.setOnClickListener(v -> {
      String url = a.optString("url");
      if (url.startsWith("https://")) try { startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))); } catch (Exception ignored) {}
    });
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(width > 0 ? width : -1, -2);
    p.setMargins(0, 0, width > 0 ? dp(10) : 0, dp(10));
    c.setLayoutParams(p);
    return c;
  }


  private void inbox() {
    if (headActions != null) {
      FrameLayout send = new FrameLayout(this);
      send.setBackground(background(PRIMARY_SOFT, 12));
      send.addView(icon("send", 20, ACCENT), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
      send.setContentDescription("Tin nhắn mới");
      send.setOnClickListener(v -> navigate("discover"));
      LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(dp(42), dp(40));
      sp.rightMargin = dp(8);
      headActions.addView(send, sp);
      TextView group = label("Tạo nhóm", 14, WHITE);
      group.setTypeface(null, Typeface.BOLD);
      group.setGravity(Gravity.CENTER);
      group.setPadding(dp(14), 0, dp(14), 0);
      group.setBackground(background(ACCENT, 12));
      group.setOnClickListener(v -> createGroup());
      headActions.addView(group, new LinearLayout.LayoutParams(-2, dp(40)));
    }
    final EditText search = input(content, "Tìm cuộc trò chuyện", "", false);
    search.setBackground(background(CARD, 12));
    final LinearLayout filters = row();
    content.addView(filters);
    final LinearLayout list = column();
    GradientDrawable g = background(CARD, 16);
    g.setStroke(1, LINE);
    list.setBackground(g);
    list.setPadding(0, dp(4), 0, dp(4));
    LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
    lp.topMargin = dp(8);
    content.addView(list, lp);
    final List<JSONObject> rows = new ArrayList<>();
    final boolean[] unreadOnly = { false };
    final Runnable render = () -> {
      list.removeAllViews();
      String q = search.getText().toString().trim().toLowerCase(Locale.ROOT);
      int shown = 0;
      for (final JSONObject item : rows) {
        boolean group = item.has("members");
        String name = group ? item.optString("name") : item.optString("name");
        if (!q.isEmpty() && !name.toLowerCase(Locale.ROOT).contains(q)) continue;
        if (unreadOnly[0] && item.optInt("unread") == 0) continue;
        JSONObject last = item.optJSONObject("last");
        String sub = last == null ? (group ? item.optJSONArray("members").length() + " thành viên" : "@" + item.optString("username")) : (last.optBoolean("mine") ? "Bạn: " : group ? last.optString("name") + ": " : "") + last.optString("body");
        conversationRow(list, group ? null : item, group ? item.optString("name") : name, sub, last == null ? "" : ago(last.optLong("created")), item.optInt("unread"), !group && item.optBoolean("isActive"), item.optBoolean("pinned"), () -> { if (group) groupChat(item); else chat(item); });
        shown++;
      }
      if (shown == 0) {
        TextView empty = label(unreadOnly[0] ? "Không có tin nhắn chưa đọc." : "Chưa có cuộc trò chuyện. Hãy tìm một người bạn ở Khám phá.", 14, MUTED);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(dp(16), dp(28), dp(16), dp(28));
        list.addView(empty);
      }
    };
    final Runnable[] drawFilters = new Runnable[1];
    drawFilters[0] = () -> {
      filters.removeAllViews();
      filters.addView(webChip("Tất cả", !unreadOnly[0], false, () -> { unreadOnly[0] = false; drawFilters[0].run(); render.run(); }));
      filters.addView(webChip("Chưa đọc", unreadOnly[0], false, () -> { unreadOnly[0] = true; drawFilters[0].run(); render.run(); }));
    };
    drawFilters[0].run();
    search.addTextChangedListener(new android.text.TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
      public void onTextChanged(CharSequence s, int a, int b, int c) {}
      public void afterTextChanged(android.text.Editable s) { render.run(); }
    });
    request("GET", "/api/conversations", null, data -> {
      conversationUsers = data.optJSONArray("users");
      for (int i = 0; conversationUsers != null && i < conversationUsers.length(); i++) rows.add(conversationUsers.optJSONObject(i));
      request("GET", "/api/groups", null, g2 -> {
        JSONArray groups = g2.optJSONArray("groups");
        for (int i = 0; groups != null && i < groups.length(); i++) rows.add(groups.optJSONObject(i));
        Collections.sort(rows, (a, b) -> {
          if (a.optBoolean("pinned") != b.optBoolean("pinned")) return a.optBoolean("pinned") ? -1 : 1;
          long ta = a.optJSONObject("last") == null ? a.optLong("created") : a.optJSONObject("last").optLong("created");
          long tb = b.optJSONObject("last") == null ? b.optLong("created") : b.optJSONObject("last").optLong("created");
          return Long.compare(tb, ta);
        });
        render.run();
      });
    });
  }

  private void conversationRow(LinearLayout parent, JSONObject u, String title, String subtitle, String time, int unread, boolean online, boolean pinned, Runnable open) {
    LinearLayout r = row();
    r.setPadding(dp(12), dp(10), dp(12), dp(10));
    FrameLayout face = new FrameLayout(this);
    if (u != null) {
      LinearLayout h = new LinearLayout(this);
      avatar(u, h, 50);
      face.addView(h);
    } else {
      FrameLayout g = new FrameLayout(this);
      GradientDrawable o = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6d4aff, PINK });
      o.setShape(GradientDrawable.OVAL);
      g.setBackground(o);
      g.addView(icon("profile", 24, WHITE), new FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER));
      face.addView(g, new FrameLayout.LayoutParams(dp(50), dp(50)));
    }
    if (online) {
      View dot = new View(this);
      GradientDrawable d = new GradientDrawable();
      d.setShape(GradientDrawable.OVAL);
      d.setColor(0xff22c55e);
      d.setStroke(dp(2), CARD);
      dot.setBackground(d);
      face.addView(dot, new FrameLayout.LayoutParams(dp(14), dp(14), Gravity.BOTTOM | Gravity.END));
    }
    r.addView(face, new LinearLayout.LayoutParams(dp(50), dp(50)));
    LinearLayout t = column();
    t.setPadding(dp(12), 0, dp(8), 0);
    TextView n = label((pinned ? "📌 " : "") + title, 16, TEXT);
    n.setTypeface(null, Typeface.BOLD);
    n.setSingleLine(true);
    n.setPadding(0, 0, 0, 0);
    TextView s2 = label(subtitle, 14, unread > 0 ? TEXT : MUTED);
    s2.setTypeface(null, unread > 0 ? Typeface.BOLD : Typeface.NORMAL);
    s2.setSingleLine(true);
    s2.setEllipsize(android.text.TextUtils.TruncateAt.END);
    s2.setPadding(0, dp(2), 0, 0);
    t.addView(n);
    t.addView(s2);
    r.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
    LinearLayout right = column();
    right.setGravity(Gravity.END);
    right.addView(label(time, 11, MUTED));
    if (unread > 0) {
      TextView badge = label(String.valueOf(unread), 11, WHITE);
      badge.setGravity(Gravity.CENTER);
      badge.setTypeface(null, Typeface.BOLD);
      badge.setPadding(dp(6), 0, dp(6), 0);
      badge.setMinWidth(dp(20));
      badge.setBackground(background(0xfff23663, 99));
      right.addView(badge, new LinearLayout.LayoutParams(-2, dp(20)));
    }
    r.addView(right);
    r.setOnClickListener(v -> open.run());
    parent.addView(r);
  }


  private String lastMessages = "";


  private void profile() {
    request("GET", "/api/me", null, data -> {
      me = data.optJSONObject("user");
      profileCard(me, true);
      content.addView(sectionLabel("Bài viết của bạn"));
      final LinearLayout list = column();
      content.addView(list);
      request("GET", "/api/posts?user=" + me.optString("id"), null, d -> { LinearLayout saved = content; content = list; posts(d.optJSONArray("posts"), "Bạn chưa có bài viết nào."); content = saved; });
    });
  }

  // Thẻ hồ sơ giống web: dải bìa, avatar lớn ở giữa, tên, giới thiệu, số liệu, nút hành động.
  private void profileCard(final JSONObject u, final boolean self) {
    LinearLayout c = card();
    c.setPadding(0, 0, 0, dp(14));
    c.setClipToOutline(true);
    FrameLayout top = new FrameLayout(this);
    final ImageView cover = new ImageView(this);
    cover.setScaleType(ImageView.ScaleType.CENTER_CROP);
    cover.setBackground(new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, new int[] { PRIMARY_SOFT, BG == 0xfff0f2f5 ? 0xfff6e9f6 : 0xff3a2742 }));
    top.addView(cover, new FrameLayout.LayoutParams(-1, dp(100)));
    if (!u.isNull("cover") && !u.optString("cover").isEmpty()) api.image(u.optString("cover"), bytes -> {
      if (bytes == null || isDestroyed()) return;
      Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
      if (b != null) cover.setImageBitmap(b);
    });
    if (self) {
      FrameLayout cam = new FrameLayout(this);
      cam.setBackground(background(0x66000000, 99));
      TextView ci = label("📷", 14, WHITE);
      ci.setGravity(Gravity.CENTER);
      cam.addView(ci, new FrameLayout.LayoutParams(-1, -1));
      cam.setContentDescription("Đổi ảnh bìa");
      cam.setOnClickListener(v -> pickFile(306, "image/*"));
      FrameLayout.LayoutParams cp = new FrameLayout.LayoutParams(dp(34), dp(34), Gravity.TOP | Gravity.END);
      cp.setMargins(0, dp(12), dp(12), 0);
      top.addView(cam, cp);
    }
    FrameLayout face = new FrameLayout(this);
    LinearLayout holder = new LinearLayout(this);
    holder.setPadding(dp(4), dp(4), dp(4), dp(4));
    GradientDrawable ring = new GradientDrawable();
    ring.setShape(GradientDrawable.OVAL);
    ring.setColor(CARD);
    holder.setBackground(ring);
    avatar(u, holder, 104);
    face.addView(holder);
    if (self) {
      TextView badge = label("📷", 11, WHITE);
      badge.setGravity(Gravity.CENTER);
      GradientDrawable bd = background(ACCENT, 99);
      bd.setStroke(dp(2), CARD);
      badge.setBackground(bd);
      badge.setOnClickListener(v -> pickAvatar());
      face.addView(badge, new FrameLayout.LayoutParams(dp(30), dp(30), Gravity.BOTTOM | Gravity.END));
    }
    FrameLayout.LayoutParams fp = new FrameLayout.LayoutParams(dp(112), dp(112), Gravity.CENTER_HORIZONTAL | Gravity.TOP);
    fp.topMargin = dp(42);
    top.addView(face, fp);
    c.addView(top, new LinearLayout.LayoutParams(-1, dp(158)));
    TextView name = label(u.optString("name"), 21, TEXT);
    name.setTypeface(null, Typeface.BOLD);
    name.setGravity(Gravity.CENTER);
    c.addView(name);
    TextView handle = label("@" + u.optString("username"), 13, MUTED);
    handle.setGravity(Gravity.CENTER);
    handle.setPadding(0, 0, 0, dp(6));
    c.addView(handle);
    String bioText = u.optString("bio");
    TextView bio = label(bioText.isEmpty() ? (self ? "Thêm vài dòng giới thiệu để mọi người hiểu bạn hơn." : "") : bioText, 14, bioText.isEmpty() ? MUTED : TEXT);
    bio.setGravity(Gravity.CENTER);
    bio.setPadding(dp(20), 0, dp(20), dp(8));
    if (!bio.getText().toString().isEmpty()) c.addView(bio);
    if (u.optJSONArray("interests") != null && u.optJSONArray("interests").length() > 0) {
      TextView tags = label(join(u.optJSONArray("interests")), 13, ACCENT);
      tags.setGravity(Gravity.CENTER);
      c.addView(tags);
    }
    LinearLayout statsBox = column();
    statsBox.setPadding(dp(16), 0, dp(16), 0);
    statsBox.addView(divider());
    stats(u, statsBox);
    statsBox.addView(divider());
    c.addView(statsBox);
    LinearLayout acts = row();
    acts.setPadding(dp(16), dp(12), dp(16), 0);
    if (self) {
      Button edit = button("Sửa hồ sơ", () -> editProfile());
      acts.addView(edit, new LinearLayout.LayoutParams(0, dp(44), 1));
    } else {
      Button follow = u.optBoolean("following") ? button("Đang theo dõi", () -> {}) : primary("Theo dõi", () -> {});
      follow.setOnClickListener(v -> request(u.optBoolean("following") ? "DELETE" : "POST", "/api/users/" + u.optString("id") + "/follow", json(), d -> person(d.optJSONObject("user"))));
      acts.addView(follow, new LinearLayout.LayoutParams(0, dp(44), 1));
      Button msg = button("Nhắn tin", () -> chat(u));
      LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(0, dp(44), 1);
      mp.leftMargin = dp(8);
      acts.addView(msg, mp);
      Button dots = button("⋯", () -> new Sheet(this).setItems(new String[] { "Báo cáo", "Chặn người này" }, (d, w) -> {
        if (w == 0) report("user", u.optString("id"));
        else confirm("Chặn " + u.optString("name") + "?", () -> request("POST", "/api/users/" + u.optString("id") + "/block", json(), r -> navigate("discover")));
      }).show());
      LinearLayout.LayoutParams dp2 = new LinearLayout.LayoutParams(dp(48), dp(44));
      dp2.leftMargin = dp(8);
      acts.addView(dots, dp2);
    }
    c.addView(acts);
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
    root.addView(reelTabs(), 2);
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
    root.addView(reelTabs(), at++);
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
    // Cột nút bên phải
    LinearLayout side = column();
    side.setGravity(Gravity.CENTER_HORIZONTAL);
    ImageView face = avatar(author, side, 46);
    face.setOnClickListener(v -> person(author));
    side.addView(reelButton("heart", String.valueOf(item.optInt("likes")), item.optBoolean("liked") ? PINK : WHITE, () ->
      request(item.optBoolean("liked") ? "DELETE" : "POST", "/api/shorts/" + item.optString("id") + "/like", json(), d ->
        request("GET", shortsFollowing ? "/api/shorts?feed=following" : "/api/shorts", null, result -> { shortRows = result.optJSONArray("shorts"); showShort(shortIndex); }))));
    side.addView(reelButton("comment", item.has("comments") ? String.valueOf(item.optInt("comments")) : "0", WHITE, () -> shortComments(item)));
    side.addView(reelButton("share", "Chia sẻ", WHITE, () -> {
      Intent send = new Intent(Intent.ACTION_SEND);
      send.setType("text/plain");
      send.putExtra(Intent.EXTRA_TEXT, "Xem video của @" + author.optString("username") + " trên Kinnect: https://app.kinnect.io.vn/?video=" + item.optString("id"));
      try { startActivity(Intent.createChooser(send, "Chia sẻ video")); } catch (Exception ignored) {}
    }));
    side.addView(reelButton(shortMuted ? "mute" : "sound", "Âm thanh", WHITE, () -> {
      shortMuted = !shortMuted;
      if (shortPlayer != null) shortPlayer.setVolume(shortMuted ? 0 : 1, shortMuted ? 0 : 1);
      showShort(shortIndex);
    }));
    final boolean mine = item.optString("user_id").equals(me.optString("id"));
    side.addView(reelButton("more", mine ? "Thêm" : "Báo cáo", WHITE, () -> new Sheet(this).setItems(new String[] { mine ? "Xoá video của tôi" : "Báo cáo video", "Xem hồ sơ", "Đóng" }, (d, w) -> {
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

  private LinearLayout reelButton(String iconName, String caption, int color, Runnable click) {
    LinearLayout box = column();
    box.setGravity(Gravity.CENTER_HORIZONTAL);
    box.setPadding(0, dp(12), 0, 0);
    ImageView i = icon(iconName, 32, color);
    i.setElevation(dp(2));
    box.addView(i, new LinearLayout.LayoutParams(dp(34), dp(34)));
    TextView text = label(caption, 11, WHITE);
    text.setTypeface(null, Typeface.BOLD);
    text.setShadowLayer(4, 0, 1, 0xaa000000);
    text.setGravity(Gravity.CENTER);
    text.setPadding(0, dp(2), 0, 0);
    box.addView(text);
    box.setContentDescription(caption);
    box.setOnClickListener(v -> click.run());
    return box;
  }

  // Thanh tab trắng phía trên video như web: Trực tiếp · Đề xuất · Đang theo dõi
  private LinearLayout reelTabs() {
    LinearLayout bar = row();
    bar.setBackgroundColor(CARD);
    String[][] items = { { "live", "Trực tiếp" }, { "for", "Đề xuất" }, { "following", "Đang theo dõi" } };
    for (final String[] it : items) {
      boolean active = it[0].equals("following") ? shortsFollowing : it[0].equals("for") && !shortsFollowing;
      LinearLayout cell = column();
      cell.setGravity(Gravity.CENTER);
      TextView t = label(it[1], 15, active ? ACCENT : TEXT);
      t.setTypeface(null, active ? Typeface.BOLD : Typeface.NORMAL);
      t.setPadding(0, 0, 0, 0);
      t.setGravity(Gravity.CENTER);
      cell.addView(t);
      View line = new View(this);
      line.setBackground(background(active ? ACCENT : CARD, 99));
      LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(30), dp(3));
      lp.topMargin = dp(6);
      cell.addView(line, lp);
      cell.setOnClickListener(v -> {
        if (it[0].equals("live")) startActivity(new Intent(this, LiveActivity.class));
        else { shortsFollowing = it[0].equals("following"); navigate("shorts"); }
      });
      bar.addView(cell, new LinearLayout.LayoutParams(0, dp(50), 1));
    }
    return bar;
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
    r.setPadding(0, dp(10), 0, dp(10));
    parent.addView(r);
    request("GET", "/api/users/" + u.optString("id") + "/stats", null, d -> {
      String[][] items = { { String.valueOf(d.optInt("posts")), "bài viết", "" }, { String.valueOf(d.optInt("followers")), "người theo dõi", "followers" }, { String.valueOf(d.optInt("following")), "đang theo dõi", "following" } };
      for (final String[] it : items) {
        LinearLayout c = column();
        c.setGravity(Gravity.CENTER);
        TextView n = label(it[0], 18, TEXT);
        n.setTypeface(null, Typeface.BOLD);
        n.setGravity(Gravity.CENTER);
        n.setPadding(0, 0, 0, 0);
        TextView l = label(it[1], 11, MUTED);
        l.setGravity(Gravity.CENTER);
        l.setPadding(0, 0, 0, 0);
        c.addView(n);
        c.addView(l);
        if (!it[2].isEmpty()) c.setOnClickListener(v -> connections(u, it[2], it[1].substring(0, 1).toUpperCase(Locale.ROOT) + it[1].substring(1)));
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
    final boolean mine = p.optString("user_id").equals(me.optString("id"));
    LinearLayout c = card();
    c.setPadding(dp(14), dp(12), dp(14), dp(4));
    LinearLayout head = row();
    avatar(author, head, 40);
    LinearLayout who = column();
    who.setPadding(dp(10), 0, 0, 0);
    TextView name = label(author.optString("name"), 15, TEXT);
    name.setTypeface(null, Typeface.BOLD);
    name.setPadding(0, 0, 0, 0);
    who.addView(name);
    LinearLayout meta = row();
    meta.addView(label(ago(p.optLong("created")) + " · ", 12, MUTED));
    meta.addView(icon(p.optString("visibility").equals("followers") ? "profile" : "globe", 12, MUTED), new LinearLayout.LayoutParams(dp(12), dp(12)));
    meta.addView(label(p.optString("visibility").equals("followers") ? " Người theo dõi" : " Mọi thành viên", 12, MUTED));
    who.addView(meta);
    head.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
    who.setOnClickListener(v -> person(author));
    ImageView more = icon("more", 22, MUTED);
    more.setPadding(dp(8), dp(8), dp(8), dp(8));
    more.setContentDescription("Thêm thao tác");
    more.setOnClickListener(v -> new Sheet(this).setItems(new String[] { mine ? "Xoá bài viết" : "Báo cáo bài viết" }, (d, w) -> {
      if (mine) confirm("Xoá bài viết?", () -> request("DELETE", "/api/posts/" + p.optString("id"), json(), r -> navigate(tab)));
      else report("post", p.optString("id"));
    }).show());
    head.addView(more, new LinearLayout.LayoutParams(dp(40), dp(40)));
    c.addView(head);
    if (!p.optString("body").isEmpty()) {
      TextView body = label(p.optString("body"), 15, TEXT);
      body.setPadding(0, dp(8), 0, dp(4));
      body.setLineSpacing(0, 1.15f);
      c.addView(body);
    }
    JSONObject media = p.optJSONObject("media");
    if (media != null) mediaView(media, c);
    if (p.optInt("likes") > 0 || p.optInt("comments") > 0) {
      LinearLayout stats = row();
      stats.setPadding(0, dp(6), 0, dp(4));
      StringBuilder glyphs = new StringBuilder();
      JSONObject counts = p.optJSONObject("reactions");
      for (String[] r : REACTIONS) if (counts != null && counts.optInt(r[0]) > 0 && glyphs.length() < 6) glyphs.append(r[1]);
      if (p.optInt("likes") > 0) stats.addView(label((glyphs.length() == 0 ? "👍" : glyphs.toString()) + " " + p.optInt("likes"), 13, MUTED), new LinearLayout.LayoutParams(0, -2, 1));
      else stats.addView(new View(this), new LinearLayout.LayoutParams(0, 1, 1));
      if (p.optInt("comments") > 0) stats.addView(label(p.optInt("comments") + " bình luận", 13, MUTED));
      c.addView(stats);
    }
    c.addView(divider());
    LinearLayout actions = row();
    String mineReaction = p.isNull("myReaction") ? "" : p.optString("myReaction");
    String glyph = null;
    for (String[] r : REACTIONS) if (r[0].equals(mineReaction)) glyph = r[1];
    final LinearLayout react = actionButton(glyph == null ? "like" : null, glyph == null ? "👍" : glyph, "Thích", !mineReaction.isEmpty());
    react.setOnClickListener(v -> request(p.optBoolean("liked") ? "DELETE" : "POST", "/api/posts/" + p.optString("id") + "/like", p.optBoolean("liked") ? json() : json("reaction", "like"), d -> refreshReaction(p, react, d)));
    react.setOnLongClickListener(v -> {
      new Sheet(this).setTitle("Bày tỏ cảm xúc").setItems(reactionGlyphs(), (d, w) ->
        request("POST", "/api/posts/" + p.optString("id") + "/like", json("reaction", REACTIONS[w][0]), r -> refreshReaction(p, react, r))).show();
      return true;
    });
    actions.addView(react, new LinearLayout.LayoutParams(0, dp(44), 1));
    LinearLayout comment = actionButton("comment", null, "Bình luận", false);
    comment.setOnClickListener(v -> postComments(p));
    actions.addView(comment, new LinearLayout.LayoutParams(0, dp(44), 1));
    if (!mine) {
      LinearLayout dm = actionButton("message", null, "Nhắn tin", false);
      dm.setOnClickListener(v -> chat(author));
      actions.addView(dm, new LinearLayout.LayoutParams(0, dp(44), 1));
    }
    c.addView(actions);
  }

  private LinearLayout actionButton(String iconName, String emoji, String text, boolean active) {
    LinearLayout b = row();
    b.setGravity(Gravity.CENTER);
    if (emoji != null && iconName == null) {
      TextView e = label(emoji, 18, TEXT);
      e.setPadding(0, 0, 0, 0);
      b.addView(e);
    } else if (iconName != null && iconName.equals("like")) {
      TextView e = label("👍", 18, TEXT);
      e.setPadding(0, 0, 0, 0);
      b.addView(e);
    } else b.addView(icon(iconName, 20, TEXT), new LinearLayout.LayoutParams(dp(20), dp(20)));
    TextView t = label("  " + text, 14, active ? ACCENT : TEXT);
    t.setTypeface(null, Typeface.BOLD);
    t.setPadding(0, 0, 0, 0);
    b.addView(t);
    return b;
  }

  private void refreshReaction(JSONObject p, LinearLayout react, JSONObject d) {
    try {
      p.put("liked", d.optBoolean("liked"));
      p.put("likes", d.optInt("likes"));
      p.put("myReaction", d.isNull("myReaction") ? "" : d.optString("myReaction"));
      if (d.optJSONObject("reactions") != null) p.put("reactions", d.optJSONObject("reactions"));
    } catch (JSONException ignored) {}
    String glyph = "👍";
    for (String[] r : REACTIONS) if (r[0].equals(p.optString("myReaction"))) glyph = r[1];
    ((TextView) react.getChildAt(0)).setText(glyph);
    ((TextView) react.getChildAt(1)).setTextColor(d.optBoolean("liked") ? ACCENT : TEXT);
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
    strip.setGravity(Gravity.TOP);
    strip.setPadding(0, dp(6), 0, dp(6));
    strip.addView(storyBubble(me, "+ Tạo tin", true, () -> pickFile(304, "image/*|video/mp4")));
    content.addView(hscroll(strip));
    request("GET", "/api/stories", null, d -> {
      final JSONArray stories = d.optJSONArray("stories");
      for (int i = 0; stories != null && i < stories.length(); i++) {
        final int index = i;
        JSONObject st = stories.optJSONObject(i);
        strip.addView(storyBubble(st.optJSONObject("author"), st.optJSONObject("author").optString("name"), false, () -> story(stories, index)));
      }
    });
  }

  private LinearLayout storyBubble(JSONObject u, String caption, boolean mine, Runnable open) {
    LinearLayout b = column();
    b.setGravity(Gravity.CENTER_HORIZONTAL);
    FrameLayout ring = new FrameLayout(this);
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6d4aff, PINK });
    g.setShape(GradientDrawable.OVAL);
    ring.setBackground(g);
    ring.setPadding(dp(3), dp(3), dp(3), dp(3));
    FrameLayout inner = new FrameLayout(this);
    GradientDrawable w = new GradientDrawable();
    w.setShape(GradientDrawable.OVAL);
    w.setColor(CARD);
    inner.setBackground(w);
    inner.setPadding(dp(2), dp(2), dp(2), dp(2));
    LinearLayout holder = new LinearLayout(this);
    avatar(u, holder, 56);
    inner.addView(holder);
    ring.addView(inner);
    b.addView(ring, new LinearLayout.LayoutParams(dp(68), dp(68)));
    TextView t = label(caption, 12, mine ? ACCENT : TEXT);
    t.setSingleLine(true);
    t.setEllipsize(android.text.TextUtils.TruncateAt.END);
    t.setGravity(Gravity.CENTER);
    b.addView(t, new LinearLayout.LayoutParams(dp(76), -2));
    b.setOnClickListener(v -> open.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(dp(80), -2);
    p.rightMargin = dp(4);
    b.setLayoutParams(p);
    return b;
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
      for (int i = 0; items != null && i < Math.min(items.length(), 60); i++) content.addView(newsCard(items.optJSONObject(i), 0));
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
          if (attachLabel != null) attachLabel.setText(video ? "  ✓ Đã chọn video" : "  ✓ Đã chọn ảnh");
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
          if (chatReload != null) chatReload.run();
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

  private Runnable chatReload;

  private void chat(final JSONObject u) {
    final String path = "/api/users/" + u.optString("id") + "/messages";
    chatScreen(u, u.optString("name"), u.optBoolean("isActive") ? "Đang hoạt động" : "@" + u.optString("username"), path, false, () -> conversationMenu("direct", u.optString("id"), u.optString("name")), () -> chat(u));
    chatUser = u;
  }

  private void groupChat(final JSONObject g) {
    JSONArray members = g.optJSONArray("members");
    chatScreen(null, g.optString("name"), (members == null ? 0 : members.length()) + " thành viên", "/api/groups/" + g.optString("id") + "/messages", true, () -> groupMenu(g), () -> groupChat(g));
  }

  // Khung chat toàn màn giống web: đầu trang (quay lại, avatar, gọi), tin nhắn dạng bong bóng, ô nhập bo tròn.
  private void chatScreen(final JSONObject u, String title, String subtitle, final String path, final boolean group, final Runnable more, final Runnable reopen) {
    shell("", true);
    chatReload = reopen;
    ScrollView scroll = (ScrollView) content.getParent();
    int at = root.indexOfChild(scroll);
    root.removeView(scroll);
    LinearLayout box = column();
    box.setBackgroundColor(CARD);
    root.addView(box, at, new LinearLayout.LayoutParams(-1, 0, 1));
    LinearLayout head = row();
    head.setPadding(dp(6), dp(8), dp(8), dp(8));
    ImageView back = icon("back", 24, TEXT);
    back.setPadding(dp(8), dp(8), dp(8), dp(8));
    back.setContentDescription("Quay lại");
    back.setOnClickListener(v -> navigate("inbox"));
    head.addView(back, new LinearLayout.LayoutParams(dp(42), dp(42)));
    if (u != null) avatar(u, head, 42);
    else {
      FrameLayout g = new FrameLayout(this);
      GradientDrawable o = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[] { 0xff6d4aff, PINK });
      o.setShape(GradientDrawable.OVAL);
      g.setBackground(o);
      g.addView(icon("profile", 20, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
      head.addView(g, new LinearLayout.LayoutParams(dp(42), dp(42)));
    }
    LinearLayout who = column();
    who.setPadding(dp(10), 0, 0, 0);
    TextView n = label(title, 16, TEXT);
    n.setTypeface(null, Typeface.BOLD);
    n.setSingleLine(true);
    n.setPadding(0, 0, 0, 0);
    who.addView(n);
    TextView st = label(subtitle, 12, MUTED);
    st.setPadding(0, 0, 0, 0);
    who.addView(st);
    if (u != null) who.setOnClickListener(v -> person(u));
    head.addView(who, new LinearLayout.LayoutParams(0, -2, 1));
    if (u != null) {
      head.addView(softIconButton("call", "Gọi thoại", () -> { ensureCalls(); calls.start(u, "audio"); }));
      head.addView(softIconButton("video", "Gọi video", () -> { ensureCalls(); calls.start(u, "video"); }));
    }
    ImageView dots = icon("more", 22, TEXT);
    dots.setPadding(dp(8), dp(8), dp(8), dp(8));
    dots.setOnClickListener(v -> more.run());
    head.addView(dots, new LinearLayout.LayoutParams(dp(40), dp(40)));
    box.addView(head);
    box.addView(divider());
    final ScrollView msgScroll = new ScrollView(this);
    msgScroll.setBackgroundColor(BG == 0xfff0f2f5 ? 0xfff7f8fa : BG);
    final LinearLayout list = column();
    list.setPadding(dp(12), dp(10), dp(12), dp(10));
    msgScroll.addView(list);
    box.addView(msgScroll, new LinearLayout.LayoutParams(-1, 0, 1));
    box.addView(divider());
    LinearLayout bar = row();
    bar.setPadding(dp(8), dp(8), dp(10), dp(8));
    ImageView clip = icon("attach", 22, ACCENT);
    clip.setPadding(dp(9), dp(9), dp(9), dp(9));
    clip.setContentDescription("Đính kèm");
    clip.setOnClickListener(v -> { attachTarget = path; pickFile(303, "*/*"); });
    bar.addView(clip, new LinearLayout.LayoutParams(dp(42), dp(42)));
    final EditText input = new EditText(this);
    input.setHint("Nhắn tin...");
    input.setTextColor(TEXT);
    input.setHintTextColor(MUTED);
    input.setTextSize(15);
    input.setPadding(dp(16), 0, dp(16), 0);
    input.setBackground(background(SOFT, 999));
    input.setSingleLine(true);
    LinearLayout.LayoutParams ip = new LinearLayout.LayoutParams(0, dp(44), 1);
    ip.setMargins(dp(4), 0, dp(8), 0);
    bar.addView(input, ip);
    FrameLayout send = new FrameLayout(this);
    send.setBackground(gradient(999));
    send.addView(icon("send", 20, WHITE), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    send.setContentDescription("Gửi");
    final Runnable load = () -> loadChat(path, list, msgScroll, group, u);
    send.setOnClickListener(v -> {
      String text = input.getText().toString().trim();
      if (text.isEmpty()) return;
      input.setText("");
      request("POST", path, json("body", text), d -> { lastMessages = ""; load.run(); });
    });
    bar.addView(send, new LinearLayout.LayoutParams(dp(56), dp(44)));
    box.addView(bar);
    lastMessages = "";
    load.run();
    final int generation = screen;
    poll = () -> {
      if (!stopped && generation == screen) {
        load.run();
        handler.postDelayed(poll, 4000);
      }
    };
    handler.postDelayed(poll, 4000);
  }

  private FrameLayout softIconButton(String name, String label, Runnable action) {
    FrameLayout f = new FrameLayout(this);
    f.setBackground(background(PRIMARY_SOFT, 12));
    f.addView(icon(name, 20, ACCENT), new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
    f.setContentDescription(label);
    f.setOnClickListener(v -> action.run());
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(dp(42), dp(40));
    p.leftMargin = dp(6);
    f.setLayoutParams(p);
    return f;
  }

  private void loadChat(final String path, final LinearLayout list, final ScrollView scroll, final boolean group, final JSONObject other) {
    request("GET", path, null, data -> {
      JSONArray messages = data.optJSONArray("messages");
      String signature = messages == null ? "" : messages.toString();
      if (signature.equals(lastMessages) && list.getChildCount() > 0) return;
      lastMessages = signature;
      list.removeAllViews();
      String lastDay = "";
      java.text.SimpleDateFormat day = new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()), clock = new java.text.SimpleDateFormat("HH:mm", Locale.getDefault());
      String today = day.format(new Date());
      if (messages == null || messages.length() == 0) {
        TextView hello = label("👋\nHãy gửi lời chào đầu tiên!", 15, MUTED);
        hello.setGravity(Gravity.CENTER);
        hello.setPadding(0, dp(60), 0, 0);
        list.addView(hello);
      }
      for (int i = 0; messages != null && i < messages.length(); i++) {
        final JSONObject m = messages.optJSONObject(i);
        final boolean own = m.optString("sender").equals(me.optString("id"));
        Date at = new Date(m.optLong("created"));
        String d = day.format(at);
        if (!d.equals(lastDay)) {
          lastDay = d;
          TextView sep = label(d.equals(today) ? "Hôm nay" : d, 11, MUTED);
          sep.setPadding(dp(10), dp(3), dp(10), dp(3));
          sep.setBackground(background(SOFT, 999));
          LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(-2, -2);
          sp.gravity = Gravity.CENTER_HORIZONTAL;
          sp.setMargins(0, dp(10), 0, dp(10));
          list.addView(sep, sp);
        }
        LinearLayout bubble = column();
        bubble.setPadding(dp(14), dp(9), dp(14), dp(7));
        GradientDrawable shape = background(own ? ACCENT : CARD, 18);
        if (!own) shape.setStroke(1, LINE);
        bubble.setBackground(shape);
        if (group && !own) {
          TextView author = label(m.optJSONObject("author") == null ? "" : m.optJSONObject("author").optString("name"), 12, ACCENT);
          author.setTypeface(null, Typeface.BOLD);
          author.setPadding(0, 0, 0, 0);
          bubble.addView(author);
        }
        final JSONObject file = m.optJSONObject("attachment");
        if (file != null && file.optString("kind").equals("image")) mediaView(file, bubble);
        else if (file != null) {
          TextView f = label("📎 " + file.optString("name"), 15, own ? WHITE : TEXT);
          f.setOnClickListener(v -> openAttachment(file));
          bubble.addView(f);
        }
        String body = m.optBoolean("recalled") ? "Tin nhắn đã được thu hồi" : m.optString("body");
        if (!body.isEmpty()) {
          TextView t = label(body, 15, own ? WHITE : TEXT);
          t.setPadding(0, 0, 0, 0);
          if (m.optBoolean("recalled")) t.setTypeface(null, Typeface.ITALIC);
          bubble.addView(t);
        }
        JSONObject reactions = m.optJSONObject("reactions");
        StringBuilder rx = new StringBuilder();
        for (String[] r : REACTIONS) if (reactions != null && reactions.optInt(r[0]) > 0) rx.append(r[1]);
        TextView time = label(clock.format(at) + (m.optBoolean("pinned") ? "  📌" : "") + (rx.length() > 0 ? "  " + rx : ""), 10, own ? 0xccffffff : MUTED);
        time.setPadding(0, dp(2), 0, 0);
        bubble.addView(time);
        bubble.setOnLongClickListener(v -> { messageMenu(group ? "group" : "direct", m, own, () -> { lastMessages = ""; loadChat(path, list, scroll, group, other); }); return true; });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, -2);
        p.gravity = own ? Gravity.END : Gravity.START;
        p.setMargins(own ? dp(48) : 0, dp(3), own ? 0 : dp(48), dp(3));
        list.addView(bubble, p);
      }
      scroll.post(() -> scroll.fullScroll(View.FOCUS_DOWN));
    });
  }
}
