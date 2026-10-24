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

/** Native Android social screens; WebView is confined to the experimental live module. */
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
  private boolean shortMuted = true,
    postingVideo = false;
  private String tab = "discover";
  private int screen = 0;
  private boolean stopped = false;
  private Runnable poll;
  private LocationListener locationListener;
  private static final int BG = 0xff141329,
    CARD = 0xff242037,
    TEXT = 0xfff6f0ff,
    MUTED = 0xffb9adc9,
    ACCENT = 0xffbba2ff;

  private interface Done {
    void accept(JSONObject data);
  }

  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    api.configure(server());
    getWindow().setStatusBarColor(BG);
    getWindow().setNavigationBarColor(BG);
    auth(false);
    if (!api.cookieFor(server()).isEmpty()) request(
      "GET",
      "/api/me",
      null,
      data -> {
        me = data.optJSONObject("user");
        navigate("discover");
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
    b.setTextSize(13);
    b.setAllCaps(false);
    b.setBackground(background(0xff39304e, 12));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, dp(46));
    p.setMargins(0, dp(7), 0, dp(4));
    b.setLayoutParams(p);
    b.setOnClickListener(v -> action.run());
    return b;
  }

  private Button primary(String text, Runnable action) {
    Button b = button(text, action);
    b.setTextColor(BG);
    b.setBackground(background(ACCENT, 12));
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
    v.setBackground(background(0xff1a172b, 12));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
      -1,
      multiline ? dp(100) : dp(50)
    );
    p.setMargins(0, dp(7), 0, dp(10));
    parent.addView(v, p);
    return v;
  }

  private LinearLayout card() {
    LinearLayout v = column();
    v.setPadding(dp(16), dp(14), dp(16), dp(14));
    v.setBackground(background(CARD, 18));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.setMargins(0, dp(8), 0, dp(8));
    content.addView(v, p);
    return v;
  }

  private void shell(String title, boolean navigation) {
    stopShort();
    stopLocation();
    screen++;
    handler.removeCallbacksAndMessages(null);
    poll = null;
    chatUser = null;
    root = column();
    root.setBackgroundColor(BG);
    root.setPadding(dp(16), 0, dp(16), 0);
    root.setOnApplyWindowInsetsListener((v, insets) -> {
      v.setPadding(
        dp(16),
        insets.getSystemWindowInsetTop(),
        dp(16),
        insets.getSystemWindowInsetBottom()
      );
      return insets;
    });
    setContentView(root);
    toolbar = row();
    TextView brand = label(title, 25, TEXT);
    brand.setTypeface(null, Typeface.BOLD);
    toolbar.addView(brand, new LinearLayout.LayoutParams(0, dp(58), 1));
    Button settings = button("⚙", () -> settings());
    settings.setContentDescription("Cài đặt");
    toolbar.addView(settings, new LinearLayout.LayoutParams(dp(48), dp(44)));
    root.addView(toolbar);
    notice = label("", 12, 0xff78ddc5);
    root.addView(notice);
    ScrollView scroll = new ScrollView(this);
    scroll.setFillViewport(true);
    content = column();
    content.setPadding(0, dp(8), 0, dp(18));
    scroll.addView(content);
    root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    if (navigation) {
      bottom = row();
      String[] keys = {
          "discover",
          "shorts",
          "feed",
          "inbox",
          "live",
          "profile",
        },
        names = {
          "◎\nKhám phá",
          "▷\nVideo",
          "▤\nBảng tin",
          "◇\nTin nhắn",
          "◉\nLive",
          "○\nHồ sơ",
        };
      for (int i = 0; i < keys.length; i++) {
        final String key = keys[i];
        Button b = button(names[i], () -> navigate(key));
        b.setTextSize(10);
        b.setTextColor(tab.equals(key) ? ACCENT : MUTED);
        b.setBackgroundColor(BG);
        bottom.addView(b, new LinearLayout.LayoutParams(0, dp(64), 1));
      }
      root.addView(bottom);
    }
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
    ImageView logo = new ImageView(this);
    logo.setImageResource(
      getResources().getIdentifier("kinnect_icon", "drawable", getPackageName())
    );
    content.addView(logo, new LinearLayout.LayoutParams(dp(88), dp(88)));
    content.addView(label("Kết nối bằng\nchính bạn.", 34, TEXT));
    content.addView(
      label("Những người bạn mới, câu chuyện và khoảnh khắc chung.", 15, MUTED)
    );
    EditText username = input(content, "Tên đăng nhập", "", false),
      password = input(content, "Mật khẩu · tối thiểu 6 ký tự", "", false);
    username.setInputType(
      InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
    );
    password.setInputType(
      InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD
    );
    EditText name = register ? input(content, "Tên hiển thị", "", false) : null;
    CheckBox agree = new CheckBox(this);
    agree.setText(
      "Tôi xác nhận mình đủ 18 tuổi và tôn trọng quy tắc cộng đồng."
    );
    agree.setTextColor(MUTED);
    if (register) content.addView(agree);
    Button submit = primary(register ? "Tạo tài khoản" : "Đăng nhập", () -> {});
    submit.setOnClickListener(v -> {
      if (password.length() < 6) {
        say("Mật khẩu tối thiểu 6 ký tự, không bắt buộc ký tự đặc biệt.");
        return;
      }
      if (register && !agree.isChecked()) {
        say("Vui lòng xác nhận bạn đủ 18 tuổi.");
        return;
      }
      submit.setEnabled(false);
      final int generation = screen;
      api.call(
        "POST",
        register ? "/api/register" : "/api/login",
        json(
          "username",
          username.getText().toString(),
          "password",
          password.getText().toString(),
          "name",
          name == null ? "" : name.getText().toString(),
          "agree18",
          agree.isChecked()
        ),
        (data, error, status) -> {
          if (generation != screen || isDestroyed()) return;
          submit.setEnabled(true);
          password.setText("");
          if (error != null) {
            say(error);
            return;
          }
          me = data.optJSONObject("user");
          navigate("discover");
        }
      );
    });
    content.addView(submit);
    content.addView(
      button(
        register
          ? "Đã có tài khoản? Đăng nhập"
          : "Chưa có tài khoản? Tạo tài khoản",
        () -> auth(!register)
      )
    );
    content.addView(
      label(
        "Kinnect tôn trọng quyền riêng tư. Tuổi do người dùng tự xác nhận; không có xác minh danh tính.",
        12,
        MUTED
      )
    );
  }

  private void navigate(String next) {
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
                ? "Kinnect Live"
                : "Hồ sơ",
      true
    );
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
    image.setBackground(background(0xff4b3c69, 16));
    image.setClipToOutline(true);
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

  private void discover() {
    content.addView(label("Những kết nối cùng tần số", 22, TEXT));
    boolean nearby = me != null && me.optBoolean("hasLocation");
    content.addView(
      label(
        nearby
          ? "Thành viên xung quanh · khoảng cách gần đúng"
          : "Gợi ý theo sở thích · chưa dùng vị trí",
        13,
        MUTED
      )
    );
    content.addView(
      button(
        nearby ? "Cập nhật vị trí gần đúng" : "Bật danh sách xung quanh",
        () -> requestLocation()
      )
    );
    content.addView(button("Thông báo", () -> notifications()));
    EditText search = input(content, "Tìm tên hoặc sở thích", "", false);
    content.addView(
      primary("Tìm kiếm", () -> loadPeople(search.getText().toString(), nearby))
    );
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
      "/api/discover?q=" + encode(query) + (nearby ? "&nearby=1" : ""),
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
    avatar(u, content, 110);
    content.addView(label("@" + u.optString("username"), 14, MUTED));
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
    new AlertDialog.Builder(this)
      .setMessage(message)
      .setPositiveButton("Xác nhận", (d, w) -> yes.run())
      .setNegativeButton("Hủy", null)
      .show();
  }

  private void report(String type, String id) {
    EditText reason = new EditText(this);
    reason.setHint("Mô tả vấn đề ít nhất 5 ký tự");
    new AlertDialog.Builder(this)
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
    content.addView(label("Chuyện của chúng mình", 24, TEXT));
    EditText body = input(
      content,
      "Hôm nay bạn muốn chia sẻ điều gì?",
      "",
      true
    );
    CheckBox followers = new CheckBox(this);
    followers.setText("Chỉ người theo dõi được xem");
    followers.setTextColor(MUTED);
    content.addView(followers);
    content.addView(
      primary("Đăng bài", () ->
        request(
          "POST",
          "/api/posts",
          json(
            "body",
            body.getText().toString(),
            "visibility",
            followers.isChecked() ? "followers" : "public"
          ),
          d -> navigate("feed")
        )
      )
    );
    request("GET", "/api/posts", null, data -> {
      JSONArray posts = data.optJSONArray("posts");
      if (posts == null || posts.length() == 0) content.addView(
        label("Chia sẻ lời chào đầu tiên của bạn.", 14, MUTED)
      );
      for (int i = 0; posts != null && i < posts.length(); i++) {
        JSONObject p = posts.optJSONObject(i),
          author = p.optJSONObject("author");
        LinearLayout c = card();
        c.addView(label(author.optString("name"), 18, TEXT));
        c.addView(
          label(
            new java.text.SimpleDateFormat(
              "dd/MM HH:mm",
              Locale.getDefault()
            ).format(new Date(p.optLong("created"))),
            11,
            MUTED
          )
        );
        c.addView(label(p.optString("body"), 16, TEXT));
        if (p.optString("user_id").equals(me.optString("id"))) c.addView(
          button("Xóa bài", () ->
            confirm("Xóa bài viết?", () ->
              request("DELETE", "/api/posts/" + p.optString("id"), json(), d ->
                navigate("feed")
              )
            )
          )
        );
        else c.addView(
          button("Báo cáo bài viết", () -> report("post", p.optString("id")))
        );
      }
    });
  }

  private void inbox() {
    content.addView(label("Trò chuyện riêng", 23, TEXT));
    content.addView(
      label(
        "Mặc định chỉ nhắn tin khi hai bên cùng theo dõi. Chưa có mã hóa đầu cuối.",
        13,
        MUTED
      )
    );
    request("GET", "/api/conversations", null, data -> {
      JSONArray users = data.optJSONArray("users");
      if (users == null || users.length() == 0) content.addView(
        label(
          "Chưa có cuộc trò chuyện. Hãy tìm một người bạn ở Khám phá.",
          15,
          MUTED
        )
      );
      for (int i = 0; users != null && i < users.length(); i++) {
        JSONObject u = users.optJSONObject(i);
        LinearLayout c = card();
        c.addView(label(u.optString("name"), 19, TEXT));
        c.addView(button("Mở trò chuyện", () -> chat(u)));
      }
    });
  }

  private void chat(JSONObject u) {
    shell(u.optString("name"), true);
    chatUser = u;
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
          TextView text = label(
            (own ? "Bạn: " : u.optString("name") + ": ") + m.optString("body"),
            16,
            TEXT
          );
          text.setPadding(dp(14), dp(10), dp(14), dp(10));
          text.setBackground(background(own ? 0xff4b356b : CARD, 16));
          LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
          p.setMargins(own ? dp(28) : 0, dp(4), own ? 0 : dp(28), dp(4));
          list.addView(text, p);
          if (!own) text.setOnLongClickListener(v -> {
            report("message", m.optString("id"));
            return true;
          });
        }
      }
    );
  }

  private void profile() {
    request("GET", "/api/me", null, data -> {
      me = data.optJSONObject("user");
      avatar(me, content, 88);
      content.addView(label(me.optString("name"), 25, TEXT));
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
      content.addView(
        button("Tắt và xóa vị trí đã chia sẻ", () ->
          request("PATCH", "/api/me/location", json("enabled", false), d -> {
            me = d.optJSONObject("user");
            say("Đã xóa vị trí. Không hiển thị trong danh sách xung quanh.");
          })
        )
      );
      content.addView(button("Người đã chặn", () -> blocks()));
      content.addView(button("Thông báo", () -> notifications()));
      if (me.optString("role").equals("admin")) content.addView(
        primary("Quản trị viên · Quản lý cộng đồng", () -> admin())
      );
      content.addView(
        button("Đăng xuất", () ->
          request("POST", "/api/logout", json(), d -> {
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
        JSONObject n = rows.optJSONObject(i),
          u = n.optJSONObject("actor");
        content.addView(
          button(
            u.optString("name") +
              (n.optString("kind").equals("follow")
                ? " đã theo dõi bạn"
                : n.optString("kind").equals("gift")
                  ? " đã gửi quà miễn phí"
                  : " đã gửi tin nhắn"),
            () -> person(u)
          )
        );
      }
      if (rows == null || rows.length() == 0) content.addView(
        label("Chưa có thông báo mới.", 16, MUTED)
      );
      request("POST", "/api/notifications", json(), d -> {});
    });
  }

  private void admin() {
    shell("Quản trị Kinnect", true);
    content.addView(label("Báo cáo và tài khoản", 22, TEXT));
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
    content.addView(label("Kết nối trực tiếp", 28, TEXT));
    content.addView(
      label(
        "Phòng, camera/micro và chat đã có bản thử nghiệm. Video qua Internet chưa có TURN/SFU và chưa được xác nhận hoạt động.",
        16,
        MUTED
      )
    );
    content.addView(
      primary("Mở phòng Live thử nghiệm", () ->
        startActivity(new Intent(this, LiveActivity.class))
      )
    );
    content.addView(
      label(
        "Riêng module Live hiện vẫn dùng WebRTC trong WebView. Các màn hình tài khoản, khám phá, hồ sơ, bảng tin và chat ở app chính là giao diện Android native. Quà miễn phí thử nghiệm có trong phòng live, giới hạn chống spam; không có thanh toán hoặc quy đổi tiền.",
        13,
        MUTED
      )
    );
  }

  private void settings() {
    EditText url = new EditText(this);
    url.setSingleLine(true);
    url.setText(server());
    new AlertDialog.Builder(this)
      .setTitle("Đổi máy chủ Kinnect")
      .setMessage(
        "Quick Tunnel tạm thời có thể đổi URL. Đổi máy chủ sẽ đăng xuất phiên hiện tại."
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
    content.addView(primary("Tạo video ngắn", () -> chooseVideo()));
    content.addView(
      label(
        "Video từ thành viên · vuốt lên/xuống để chuyển. Tối đa 60 giây, MP4 12 MB.",
        13,
        MUTED
      )
    );
    request("GET", "/api/shorts", null, data -> {
      shortRows = data.optJSONArray("shorts");
      if (shortRows == null || shortRows.length() == 0) {
        content.addView(
          label("Chưa có video. Hãy chia sẻ khoảnh khắc đầu tiên.", 17, TEXT)
        );
        return;
      }
      showShort(0);
    });
  }

  private void showShort(int index) {
    if (shortRows == null || shortRows.length() == 0) return;
    shortIndex = Math.max(0, Math.min(index, shortRows.length() - 1));
    shell("Video ngắn", true);
    JSONObject item = shortRows.optJSONObject(shortIndex),
      author = item.optJSONObject("author");
    content.addView(button("＋ Tạo video", () -> chooseVideo()));
    shortVideo = new VideoView(this);
    final VideoView playerView = shortVideo;
    int height = Math.min(
      500,
      Math.max(
        300,
        (int) (getResources().getDisplayMetrics().heightPixels /
          getResources().getDisplayMetrics().density) - 330
      )
    );
    content.addView(shortVideo, new LinearLayout.LayoutParams(-1, dp(height)));
    MediaController controls = new MediaController(this);
    shortVideo.setMediaController(controls);
    Map<String, String> headers = new HashMap<>();
    headers.put("Cookie", api.cookieFor(server()));
    shortVideo.setVideoURI(
      android.net.Uri.parse(server() + item.optString("video")),
      headers
    );
    shortVideo.setOnPreparedListener(player -> {
      if (stopped || shortVideo != playerView) return;
      shortPlayer = player;
      player.setLooping(true);
      player.setVolume(shortMuted ? 0 : 1, shortMuted ? 0 : 1);
      shortVideo.start();
    });
    shortVideo.setOnErrorListener((player, what, extra) -> {
      say(
        "Không phát được video. Kiểm tra kết nối và codec MP4 trên điện thoại."
      );
      return true;
    });
    final float[] y = { 0 };
    shortVideo.setOnTouchListener((view, event) -> {
      if (event.getAction() == MotionEvent.ACTION_DOWN) y[0] = event.getY();
      if (
        event.getAction() == MotionEvent.ACTION_UP &&
        Math.abs(event.getY() - y[0]) > dp(60)
      ) {
        showShort(shortIndex + (event.getY() < y[0] ? 1 : -1));
        return true;
      }
      return false;
    });
    content.addView(label(author.optString("name"), 19, TEXT));
    content.addView(label(item.optString("caption"), 15, TEXT));
    content.addView(
      button(shortMuted ? "Bật âm thanh" : "Tắt âm thanh", () -> {
        shortMuted = !shortMuted;
        if (shortPlayer != null) shortPlayer.setVolume(
          shortMuted ? 0 : 1,
          shortMuted ? 0 : 1
        );
        say(shortMuted ? "Đã tắt âm thanh" : "Đã bật âm thanh");
      })
    );
    content.addView(
      button(
        (item.optBoolean("liked") ? "♥ Đã thích · " : "♡ Thích · ") +
          item.optInt("likes"),
        () ->
          request(
            item.optBoolean("liked") ? "DELETE" : "POST",
            "/api/shorts/" + item.optString("id") + "/like",
            json(),
            d ->
              request("GET", "/api/shorts", null, result -> {
                shortRows = result.optJSONArray("shorts");
                showShort(shortIndex);
              })
          )
      )
    );
    content.addView(button("Bình luận", () -> shortComments(item)));
    content.addView(button("Xem hồ sơ", () -> person(author)));
    content.addView(
      button("Báo cáo video", () -> report("short", item.optString("id")))
    );
    if (item.optString("user_id").equals(me.optString("id"))) content.addView(
      button("Xóa video của tôi", () ->
        confirm("Xóa video?", () ->
          request("DELETE", "/api/shorts/" + item.optString("id"), json(), d ->
            navigate("shorts")
          )
        )
      )
    );
    content.addView(button("↑ Video trước", () -> showShort(shortIndex - 1)));
    content.addView(
      button("↓ Video tiếp theo", () -> showShort(shortIndex + 1))
    );
  }

  private void shortComments(JSONObject item) {
    shell("Bình luận", true);
    EditText value = input(content, "Viết bình luận", "", false);
    content.addView(
      primary("Gửi bình luận", () ->
        request(
          "POST",
          "/api/shorts/" + item.optString("id") + "/comments",
          json("body", value.getText().toString()),
          d -> shortComments(item)
        )
      )
    );
    content.addView(button("Quay lại video", () -> showShort(shortIndex)));
    request(
      "GET",
      "/api/shorts/" + item.optString("id") + "/comments",
      null,
      data -> {
        JSONArray comments = data.optJSONArray("comments");
        for (int i = 0; comments != null && i < comments.length(); i++) {
          JSONObject c = comments.optJSONObject(i);
          LinearLayout row = card();
          row.addView(
            label(c.optJSONObject("author").optString("name"), 16, ACCENT)
          );
          row.addView(label(c.optString("body"), 15, TEXT));
          row.addView(
            button("Báo cáo", () -> report("comment", c.optString("id")))
          );
        }
      }
    );
  }

  private void chooseVideo() {
    if (postingVideo) {
      say("Đang tải video, vui lòng chờ.");
      return;
    }
    new AlertDialog.Builder(this)
      .setTitle("Tạo video ngắn")
      .setItems(
        new String[] { "Quay video bằng camera", "Chọn MP4 từ điện thoại" },
        (dialog, which) -> {
          if (which == 0) {
            if (
              checkSelfPermission(Manifest.permission.CAMERA) !=
              PackageManager.PERMISSION_GRANTED
            ) requestPermissions(
              new String[] { Manifest.permission.CAMERA },
              102
            );
            else captureVideo();
          } else {
            Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            pick.addCategory(Intent.CATEGORY_OPENABLE);
            pick.setType("video/mp4");
            try {
              startActivityForResult(pick, 200);
            } catch (Exception e) {
              say("Không mở được trình chọn video.");
            }
          }
        }
      )
      .show();
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
    new AlertDialog.Builder(this)
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
    new AlertDialog.Builder(this)
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
        navigate("discover");
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
    if (poll != null) handler.postDelayed(poll, 4000);
  }

  @Override
  protected void onDestroy() {
    stopShort();
    super.onDestroy();
  }

  @Override
  public void onBackPressed() {
    if (me != null && !tab.equals("discover")) {
      navigate("discover");
      return;
    }
    super.onBackPressed();
  }
}
