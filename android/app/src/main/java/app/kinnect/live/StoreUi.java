package app.kinnect.live;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.view.*;
import android.widget.*;
import org.json.*;
import java.util.*;

public final class StoreUi implements StoreBilling.Events {
  private final Activity activity;
  private final ViewGroup container;
  private final ViewGroup headerActionContainer;
  private final Runnable onStyleChanged;
  private final CommerceUi ui;
  private final StoreBilling billing;
  private final Map<String, String> prices = new HashMap<>();
  private final ArrayDeque<String[]> receiptQueue = new ArrayDeque<>();
  private JSONObject catalog;
  private LinearLayout body;
  private String selectedTab = "style";
  private boolean busy;
  private boolean closed;

  public StoreUi(Activity activity, ViewGroup container, ViewGroup headerActionContainer, Runnable onStyleChanged) {
    this.activity = activity;
    this.container = container;
    this.headerActionContainer = headerActionContainer;
    this.onStyleChanged = onStyleChanged;
    this.ui = new CommerceUi(activity);
    this.billing = StoreBilling.create(activity);
    NativeApi.shared.initialize(activity, ServerConfig.DEFAULT_ORIGIN);

    JSONObject cached = NativeApi.shared.cachedGet("/api/store");
    if (cached != null) {
      catalog = cached;
      draw();
    } else {
      renderLoading();
    }
    load(true);
  }

  private int dp(int value) {
    return Math.round(value * activity.getResources().getDisplayMetrics().density * WebDesign.UI_SCALE);
  }

  private String tr(String s) {
    return I18n.t(s);
  }

  private int variant() {
    return WebTheme.isDark(activity) ? 1 : 0;
  }

  private GradientDrawable round(int color, int radius) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    return d;
  }

  private GradientDrawable gradient(int a, int b, int radius) {
    GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, new int[]{a, b});
    g.setCornerRadius(dp(radius));
    return g;
  }

  private boolean owns(String id) {
    JSONArray owned = catalog == null ? null : catalog.optJSONArray("owned");
    if (owned != null) {
      for (int i = 0; i < owned.length(); i++) {
        if (id.equals(owned.optString(i))) return true;
      }
    }
    return false;
  }

  private boolean ownsPackage(String id) {
    JSONArray all = catalog == null ? null : catalog.optJSONArray("ownedPackages");
    if (all != null) {
      for (int i = 0; i < all.length(); i++) {
        if (id.equals(all.optString(i))) return true;
      }
    }
    return false;
  }

  private boolean isEquipped(JSONObject p) {
    if (catalog == null) return false;
    String id = p.optString("id"), kind = p.optString("kind");
    if (kind.equals("style")) return id.equals(catalog.optString("appearance"));
    if (kind.equals("live") && !id.equals("live_game_30")) {
      return id.equals(catalog.optString("liveDecoration", catalog.optString("liveTheme")));
    }
    if (kind.equals("member")) return id.equals(catalog.optString("membership"));
    return false;
  }

  private String amount(long n) {
    return java.text.NumberFormat.getIntegerInstance(new Locale("vi", "VN")).format(n);
  }

  private String balanceText() {
    if (catalog == null) return "";
    return CoinBalanceCard.display(catalog.optLong("purchasedCoins") + catalog.optLong("giftedCoins", catalog.optLong("trialCoins")));
  }

  private void renderLoading() {
    if (container == null) return;
    container.removeAllViews();
    LinearLayout loading = ui.col();
    loading.addView(ui.empty("shopping_bag", tr("Đang tải…")));
    container.addView(loading, new LinearLayout.LayoutParams(-1, -2));
  }

  private void load(boolean connect) {
    NativeApi.shared.call("GET", "/api/store", null, (data, error, status) -> {
      if (closed || activity.isFinishing() || activity.isDestroyed()) return;
      if (error != null) {
        if (catalog == null) {
          message(tr("Chưa tải được cửa hàng. Hãy thử lại."));
          if (container != null) {
            container.removeAllViews();
            LinearLayout errBox = ui.col();
            errBox.addView(ui.text(tr("Chưa tải được cửa hàng."), 15, ui.ink, true));
            errBox.addView(ui.action(tr("Thử lại"), "refresh_cw", () -> load(true)), 12);
            container.addView(errBox);
          }
        }
        return;
      }
      catalog = data;
      draw();
      if (connect && catalog != null) {
        List<String> ids = new ArrayList<>();
        JSONArray products = catalog.optJSONArray("products");
        if (products != null) {
          for (int i = 0; i < products.length(); i++) {
            ids.add(products.optJSONObject(i).optString("id"));
          }
        }
        billing.connect(ids, catalog.optString("accountId"), this);
      }
    });
  }

  private void selectTab(String key) {
    selectedTab = key;
    draw();
  }

  private void storeMenu() {
    new Sheet(activity).setTitle(tr("Cửa hàng")).setItemIcons(new String[]{"rotate_ccw", "palette", "info"}).setItems(
      new String[]{tr("Khôi phục giao dịch"), tr("Phong cách mặc định"), tr("Thông tin")},
      (d, n) -> {
        if (n == 0) {
          billing.restore();
          load(false);
        } else if (n == 1) {
          apply("");
        } else {
          new Sheet(activity).setTitle(tr("Cửa hàng"))
            .setMessage(tr("Quyền lợi gắn với tài khoản Kinnect. Xem thử không thay đổi hồ sơ. Giá thanh toán chỉ hiển thị khi Google Play sẵn sàng."))
            .setPositiveButton(tr("Đóng"), null).show();
        }
      }
    ).show();
  }

  private LinearLayout walletChip() {
    LinearLayout chip = ui.row();
    chip.setGravity(Gravity.CENTER_VERTICAL);
    chip.setPadding(ui.dp(9), 0, ui.dp(9), 0);
    chip.setBackground(ui.round(ui.soft, 99));
    ImageView icon = new ImageView(activity);
    icon.setImageDrawable(ui.glyph("wallet", ui.purple, 16));
    chip.addView(icon, new LinearLayout.LayoutParams(ui.dp(16), ui.dp(16)));
    TextView amt = ui.text(balanceText(), 13, ui.purple, true);
    amt.setPadding(ui.dp(6), 0, 0, 0);
    amt.setSingleLine(true);
    chip.addView(amt);
    chip.setContentDescription(I18n.t("Mở ví"));
    chip.setOnClickListener(v -> activity.startActivity(new Intent(activity, WalletActivity.class)));
    return chip;
  }

  public void draw() {
    if (closed || container == null) return;

    if (headerActionContainer != null) {
      headerActionContainer.removeAllViews();
      if (catalog != null) {
        headerActionContainer.addView(walletChip(), new LinearLayout.LayoutParams(-2, ui.dp(32)));
      }
      FrameLayout options = ui.icon("ellipsis", tr("Tùy chọn cửa hàng"), this::storeMenu);
      LinearLayout.LayoutParams op = new LinearLayout.LayoutParams(ui.dp(36), ui.dp(36));
      op.leftMargin = ui.dp(4);
      headerActionContainer.addView(options, op);
    }

    container.removeAllViews();

    HorizontalScrollView strip = new HorizontalScrollView(activity);
    strip.setHorizontalScrollBarEnabled(false);
    LinearLayout tabs = ui.row();
    tabs.setPadding(0, ui.dp(2), 0, ui.dp(8));
    for (String key : new String[]{"style", "studio", "live", "gifts", "member", "owned"}) {
      String title = key.equals("style") ? "Phong cách" : key.equals("studio") ? "Studio" : key.equals("live") ? "Live" : key.equals("gifts") ? "Quà" : key.equals("member") ? "Thành viên" : "Của tôi";
      Button tab = ui.action(title, null, () -> selectTab(key));
      tab.setTag("store:tab:" + key);
      tab.setTextSize(11);
      tab.setPadding(ui.dp(10), ui.dp(4), ui.dp(10), ui.dp(4));
      tab.setCompoundDrawablesRelative(ui.glyph(key.equals("style") ? "palette" : key.equals("studio") ? "clapperboard" : key.equals("live") ? "radio" : key.equals("gifts") ? "gift" : key.equals("member") ? "crown" : "check", selectedTab.equals(key) ? Color.WHITE : ui.purple, 16), null, null, null);
      tab.setCompoundDrawablePadding(ui.dp(4));
      tab.setMinLines(1);
      tab.setMinHeight(ui.dp(32));
      if (!selectedTab.equals(key)) {
        tab.setTextColor(ui.purple);
        tab.setBackground(ui.round(ui.soft, 14));
      }
      LinearLayout.LayoutParams at = new LinearLayout.LayoutParams(-2, -2);
      at.setMargins(0, 0, ui.dp(6), 0);
      tabs.addView(tab, at);
      if (selectedTab.equals(key)) {
        tab.post(() -> strip.smoothScrollTo(tab.getLeft() - ui.dp(12), 0));
      }
    }
    strip.addView(tabs);
    container.addView(strip, new LinearLayout.LayoutParams(-1, -2));

    body = ui.col();
    body.setPadding(0, ui.dp(4), 0, ui.dp(24));
    container.addView(body, new LinearLayout.LayoutParams(-1, -2));

    if (catalog == null) return;

    if (!selectedTab.equals("owned") && catalog.optJSONArray("packages") != null) {
      if (selectedTab.equals("style") && Distribution.PLAY && catalog.optBoolean("billingReady")) {
        JSONArray products = catalog.optJSONArray("products");
        List<JSONObject> styleProducts = new ArrayList<>();
        for (int i = 0; products != null && i < products.length(); i++) {
          JSONObject p = products.optJSONObject(i);
          if (p != null && "style".equals(p.optString("kind"))) styleProducts.add(p);
        }
        if (!styleProducts.isEmpty()) productGrid(body, styleProducts);
      }
      if (selectedTab.equals("studio")) {
        JSONArray studioPlans = catalog.optJSONArray("packages");
        List<JSONObject> videoPlans = new ArrayList<>(), photoPlans = new ArrayList<>();
        for (int i = 0; studioPlans != null && i < studioPlans.length(); i++) {
          JSONObject p = studioPlans.optJSONObject(i);
          if (p == null || !p.optString("kind").equals("studio")) continue;
          if ("video".equals(p.optString("line"))) videoPlans.add(p);
          else photoPlans.add(p);
        }
        if (!videoPlans.isEmpty()) planSection(body, "Studio Video Pro", videoPlans);
        if (!photoPlans.isEmpty()) planSection(body, "Studio Ảnh Pro", photoPlans);
      }
      if (selectedTab.equals("live")) {
        LinearLayout free = ui.section();
        free.setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(12));
        free.addView(ui.text("Trò chuyện", 16, ui.ink, true));
        free.addView(ui.text("Miễn phí", 12, ui.purple, true));
        ui.add(body, free, 8);
      }
      if (!selectedTab.equals("studio")) {
        JSONArray plans = catalog.optJSONArray("packages");
        List<JSONObject> gridPlans = new ArrayList<>();
        for (int i = 0; plans != null && i < plans.length(); i++) {
          JSONObject p = plans.optJSONObject(i);
          if (p != null && selectedTab.equals(p.optString("kind"))) gridPlans.add(p);
        }
        planGrid(body, gridPlans);
      }
    } else if (selectedTab.equals("style") && catalog.optJSONArray("packages") == null) {
      JSONArray products = catalog.optJSONArray("products");
      List<JSONObject> styleProducts = new ArrayList<>();
      for (int i = 0; products != null && i < products.length(); i++) {
        JSONObject p = products.optJSONObject(i);
        if (p != null && "style".equals(p.optString("kind"))) styleProducts.add(p);
      }
      productGrid(body, styleProducts);
    } else {
      List<View> styleTiles = new ArrayList<>(), studioTiles = new ArrayList<>(), liveTiles = new ArrayList<>(), giftTiles = new ArrayList<>(), memberTiles = new ArrayList<>();
      JSONArray all = catalog.optJSONArray("packages");
      for (int i = 0; all != null && i < all.length(); i++) {
        JSONObject p = all.optJSONObject(i);
        if (p == null || !ownsPackage(p.optString("id"))) continue;
        String kind = p.optString("kind");
        if (kind.equals("style")) styleTiles.add(planTile(p, true));
        else if (kind.equals("live") && !p.optString("id").equals("live_game_30")) liveTiles.add(planTile(p, true));
        else if (kind.equals("gifts")) giftTiles.add(planTile(p, true));
        else if (kind.equals("member")) memberTiles.add(planTile(p, true));
      }
      JSONArray products = catalog.optJSONArray("products");
      for (int i = 0; products != null && i < products.length(); i++) {
        JSONObject p = products.optJSONObject(i);
        if (p == null || !owns(p.optString("id"))) continue;
        if (p.optString("kind").equals("style")) styleTiles.add(product(p, false));
      }
      if (catalog.optLong("studioVideoUntil") > System.currentTimeMillis()) studioTiles.add(studioLineTile(true));
      if (catalog.optLong("studioPhotoUntil") > System.currentTimeMillis()) studioTiles.add(studioLineTile(false));
      if (catalog.optLong("liveGameUntil") > System.currentTimeMillis()) liveTiles.add(livePassTile());
      LinearLayout invBox = null;
      JSONArray inv = catalog.optJSONArray("giftInventory");
      if (inv != null && inv.length() > 0) {
        invBox = ui.section();
        invBox.setPadding(ui.dp(14), ui.dp(10), ui.dp(14), ui.dp(10));
        GradientDrawable boxBg = ui.round(ui.card, 14);
        boxBg.setStroke(Math.max(1, ui.dp(1)), WebDesign.LINE[WebTheme.isDark(activity) ? 1 : 0]);
        invBox.setBackground(boxBg);
        invBox.setElevation(0);
        invBox.addView(ui.text("Kho quà Live", 14, ui.ink, true));
        for (int i = 0; i < inv.length(); i++) {
          JSONObject g = inv.optJSONObject(i);
          if (g == null || g.optInt("quantity") <= 0) continue;
          String gid = g.optString("giftId"), gname = LiveGiftExperience.name(gid);
          LinearLayout line = ui.row();
          line.setPadding(0, ui.dp(4), 0, ui.dp(4));
          line.addView(ui.text(gname != null ? gname : gid, 12, ui.ink, false), new LinearLayout.LayoutParams(0, -2, 1));
          TextView qty = ui.badge(tr("Trong kho") + " · " + g.optInt("quantity"));
          qty.setTextSize(10);
          line.addView(qty);
          invBox.addView(line);
        }
      }
      int count = 0;
      if (!styleTiles.isEmpty()) {
        ownSection(body, "Phong cách", styleTiles);
        count += styleTiles.size();
      }
      if (!studioTiles.isEmpty()) {
        ownSection(body, "Studio", studioTiles);
        count += studioTiles.size();
      }
      if (!liveTiles.isEmpty()) {
        ownSection(body, "Live", liveTiles);
        count += liveTiles.size();
      }
      if (invBox != null || !giftTiles.isEmpty()) {
        TextView head = ui.text("Quà", 14, ui.ink, true);
        head.setPadding(ui.dp(2), ui.dp(10), 0, ui.dp(2));
        body.addView(head);
        if (invBox != null) {
          ui.add(body, invBox, 8);
          count++;
        }
        if (!giftTiles.isEmpty()) {
          ownedGrid(body, giftTiles);
          count += giftTiles.size();
        }
      }
      if (!memberTiles.isEmpty()) {
        ownSection(body, "Thành viên", memberTiles);
        count += memberTiles.size();
      }
      if (count == 0) ui.add(body, ui.empty("shopping_bag", "Chưa có sản phẩm"), 24);
    }
  }

  private void buyPlan(JSONObject p) {
    PackagePurchase.buy(activity, p, catalog, () -> load(false), () -> usePackage(p));
  }

  private void usePackage(JSONObject p) {
    String kind = p.optString("kind"), id = p.optString("id");
    if (kind.equals("studio")) {
      chooseMedia();
      return;
    }
    if (kind.equals("style")) {
      apply(isEquipped(p) && selectedTab.equals("owned") ? "" : id);
      return;
    }
    if (kind.equals("live") && !id.equals("live_game_30")) {
      try {
        String target = isEquipped(p) && selectedTab.equals("owned") ? "" : id;
        NativeApi.shared.call("POST", "/api/store/packages/apply", new JSONObject().put("productId", target), (data, error, status) -> {
          if (error != null) message(tr("Chưa áp dụng được."));
          else {
            message("Đã áp dụng phong cách.");
            load(false);
            if (onStyleChanged != null) onStyleChanged.run();
          }
        });
      } catch (Exception ignored) {}
      return;
    }
    if (id.equals("live_game_30")) {
      activity.startActivity(new Intent(activity, StudioActivity.class).putExtra(StudioActivity.EXTRA_MODE, "live"));
      return;
    }
    selectedTab = "owned";
    load(false);
  }

  private void apply(String id) {
    try {
      NativeApi.shared.call("POST", "/api/store/style", new JSONObject().put("productId", id), (data, error, status) -> {
        if (error != null) message(error);
        else {
          message(tr("Đã áp dụng phong cách."));
          load(false);
          if (onStyleChanged != null) onStyleChanged.run();
        }
      });
    } catch (Exception e) {
      message(tr("Chưa áp dụng được phong cách."));
    }
  }

  private LinearLayout tileCard() {
    LinearLayout card = ui.section();
    card.setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8));
    GradientDrawable bg = ui.round(ui.card, 14);
    bg.setStroke(Math.max(1, ui.dp(1)), WebDesign.LINE[WebTheme.isDark(activity) ? 1 : 0]);
    card.setBackground(bg);
    card.setElevation(0);
    card.setMinimumHeight(ui.dp(148));
    return card;
  }

  private String kindLabel(String kind) {
    if (kind.equals("style")) return tr("Phong cách");
    if (kind.equals("member")) return tr("Thành viên");
    if (kind.equals("gifts")) return tr("Quà Live");
    if (kind.equals("live")) return tr("Live");
    if (kind.equals("studio")) return tr("Studio");
    return tr("Gói");
  }

  private TextView chipAction(String label, boolean enabled, Runnable click) {
    TextView t = ui.text(label, 10, Color.WHITE, true);
    t.setGravity(Gravity.CENTER);
    t.setPadding(ui.dp(10), ui.dp(4), ui.dp(10), ui.dp(4));
    t.setBackground(ui.round(enabled ? ui.purple : ui.soft, 99));
    if (!enabled) t.setTextColor(ui.muted);
    if (enabled && click != null) t.setOnClickListener(v -> click.run());
    return t;
  }

  private View planTile(JSONObject p, boolean owned) {
    String id = p.optString("id"), kind = p.optString("kind"), tier = p.optString("tier");
    boolean studio = kind.equals("studio");
    boolean active = ownsPackage(id);
    LinearLayout card = tileCard();
    card.setTag("store:plan:" + id);
    {
      FrameLayout artWrap = new FrameLayout(activity);
      artWrap.addView(new StorePackageDesign.Art(activity, p), new FrameLayout.LayoutParams(-1, -1));
      if (!owned && !tier.isEmpty()) {
        TextView ribbon = ui.badge(StorePackageDesign.tierLabel(tier));
        ribbon.setTextSize(9);
        ribbon.setPadding(ui.dp(8), ui.dp(3), ui.dp(8), ui.dp(3));
        ribbon.setTextColor(StorePackageDesign.tierColor(tier, ui.purple));
        ribbon.setBackground(ui.round(0xcc111018, 99));
        FrameLayout.LayoutParams rlp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.END);
        rlp.setMargins(0, ui.dp(4), ui.dp(4), 0);
        artWrap.addView(ribbon, rlp);
      }
      card.addView(artWrap, new LinearLayout.LayoutParams(-1, ui.dp(64)));
    }
    String label = p.optString("name");
    if (label.isEmpty()) label = studio ? tr("Studio") : tr("Gói");
    TextView name = ui.text(label, 13, ui.ink, true);
    name.setMaxLines(owned ? 1 : 2);
    name.setEllipsize(android.text.TextUtils.TruncateAt.END);
    LinearLayout.LayoutParams np = new LinearLayout.LayoutParams(-1, -2);
    np.topMargin = studio ? ui.dp(2) : ui.dp(6);
    card.addView(name, np);
    if (owned) {
      TextView meta = ui.text(kindLabel(kind), 10, ui.muted, false);
      meta.setMaxLines(1);
      meta.setPadding(0, ui.dp(1), 0, 0);
      card.addView(meta);
      LinearLayout footer = ui.row();
      footer.setPadding(0, ui.dp(4), 0, 0);
      footer.addView(ui.text(isEquipped(p) ? "Đang trang bị" : "Đang dùng", 10, ui.purple, true), new LinearLayout.LayoutParams(0, -2, 1));
      card.addView(footer);
    } else {
      if (studio && !p.optString("period").isEmpty()) {
        TextView period = ui.text(p.optString("period"), 10, ui.muted, false);
        period.setMaxLines(1);
        period.setPadding(0, ui.dp(1), 0, 0);
        card.addView(period);
      }
      TextView price = ui.text(amount(p.optLong("priceCoins")) + " " + tr("xu"), 14, ui.purple, true);
      price.setCompoundDrawablesRelative(CoinBalanceCard.coin(activity, ui.dp(14)), null, null, null);
      price.setCompoundDrawablePadding(ui.dp(4));
      LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(-1, -2);
      pp.topMargin = ui.dp(4);
      card.addView(price, pp);
      if (active) {
        TextView state = ui.text(isEquipped(p) ? "Đang trang bị" : "Đang dùng", 10, ui.purple, false);
        LinearLayout.LayoutParams st = new LinearLayout.LayoutParams(-1, -2);
        st.topMargin = ui.dp(2);
        card.addView(state, st);
      }
    }
    card.setOnClickListener(v -> showPlan(p));
    return card;
  }

  private void planGrid(LinearLayout parent, List<JSONObject> plans) {
    for (int i = 0; i < plans.size(); i += 2) {
      LinearLayout row = ui.row();
      row.setBaselineAligned(false);
      LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
      rp.topMargin = ui.dp(8);
      parent.addView(row, rp);
      View first = planTile(plans.get(i), false);
      LinearLayout.LayoutParams fp = new LinearLayout.LayoutParams(0, -2, 1);
      fp.rightMargin = ui.dp(4);
      row.addView(first, fp);
      if (i + 1 < plans.size()) {
        View second = planTile(plans.get(i + 1), false);
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(0, -2, 1);
        sp.leftMargin = ui.dp(4);
        row.addView(second, sp);
      } else {
        row.addView(new View(activity), new LinearLayout.LayoutParams(0, -2, 1));
      }
    }
  }

  private void ownedGrid(LinearLayout parent, List<View> tiles) {
    for (int i = 0; i < tiles.size(); i += 2) {
      LinearLayout row = ui.row();
      row.setBaselineAligned(false);
      LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
      rp.topMargin = ui.dp(8);
      parent.addView(row, rp);
      View first = tiles.get(i);
      LinearLayout.LayoutParams fp = new LinearLayout.LayoutParams(0, -2, 1);
      fp.rightMargin = ui.dp(4);
      row.addView(first, fp);
      if (i + 1 < tiles.size()) {
        View second = tiles.get(i + 1);
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(0, -2, 1);
        sp.leftMargin = ui.dp(4);
        row.addView(second, sp);
      } else {
        row.addView(new View(activity), new LinearLayout.LayoutParams(0, -2, 1));
      }
    }
  }

  private void ownSection(LinearLayout parent, String title, List<View> tiles) {
    TextView head = ui.text(title, 14, ui.ink, true);
    head.setPadding(ui.dp(2), ui.dp(10), 0, ui.dp(2));
    parent.addView(head);
    ownedGrid(parent, tiles);
  }

  private void planSection(LinearLayout parent, String title, List<JSONObject> plans) {
    TextView head = ui.text(title, 14, ui.ink, true);
    head.setPadding(ui.dp(2), ui.dp(10), 0, ui.dp(2));
    parent.addView(head);
    planGrid(parent, plans);
  }

  private String durationText(long until) {
    if (until > 4102444800000L) return tr("Không giới hạn");
    long days = Math.max(0, (until - System.currentTimeMillis() + 86399999L) / 86400000L);
    if (days <= 0) return tr("Hết hạn");
    long years = days / 365, months = (days % 365) / 30, rest = days % 30;
    StringBuilder out = new StringBuilder();
    if (years > 0) out.append(years).append(" ").append(tr("năm"));
    if (months > 0) {
      if (out.length() > 0) out.append(" ");
      out.append(months).append(" ").append(tr("tháng"));
    }
    if (rest > 0) {
      if (out.length() > 0) out.append(" ");
      out.append(rest).append(" ").append(tr("ngày"));
    }
    return tr("Còn") + " " + out;
  }

  private View livePassTile() {
    long passUntil = catalog.optLong("liveGameUntil");
    LinearLayout card = tileCard();
    card.setTag("store:pass:live_game");
    FrameLayout art = new FrameLayout(activity);
    JSONObject pass = null;
    JSONArray packAll = catalog.optJSONArray("packages");
    for (int i = 0; packAll != null && i < packAll.length(); i++) {
      JSONObject cand = packAll.optJSONObject(i);
      if (cand != null && cand.optString("id").equals("live_game_30")) {
        pass = cand;
        break;
      }
    }
    if (pass != null) art.addView(new StorePackageDesign.Art(activity, pass), new FrameLayout.LayoutParams(-1, -1));
    card.addView(art, new LinearLayout.LayoutParams(-1, ui.dp(64)));
    TextView name = ui.text("Live Game", 13, ui.ink, true);
    name.setPadding(0, ui.dp(6), 0, 0);
    card.addView(name);
    String untilText = passUntil > 4102444800000L ? tr("Không giới hạn") : tr("Hết hạn") + " · " + new java.text.SimpleDateFormat("dd/MM/yyyy", Locale.getDefault()).format(new Date(passUntil));
    TextView meta = ui.text(untilText, 10, ui.muted, false);
    meta.setMaxLines(1);
    meta.setEllipsize(android.text.TextUtils.TruncateAt.END);
    meta.setPadding(0, ui.dp(1), 0, 0);
    card.addView(meta);
    LinearLayout footer = ui.row();
    footer.setPadding(0, ui.dp(4), 0, 0);
    footer.addView(ui.text(tr("Đang dùng"), 10, ui.purple, true), new LinearLayout.LayoutParams(0, -2, 1));
    card.addView(footer);
    return card;
  }

  private View studioLineTile(boolean video) {
    long until = catalog.optLong(video ? "studioVideoUntil" : "studioPhotoUntil");
    LinearLayout card = tileCard();
    card.setTag("store:studio_" + (video ? "video" : "photo"));
    FrameLayout art = new FrameLayout(activity);
    JSONObject artSource = null;
    JSONArray artAll = catalog.optJSONArray("packages");
    for (int i = 0; artAll != null && i < artAll.length(); i++) {
      JSONObject cand = artAll.optJSONObject(i);
      if (cand != null && cand.optString("kind").equals("studio") && video == cand.optString("line").equals("video")) {
        artSource = cand;
        break;
      }
    }
    if (artSource != null) art.addView(new StorePackageDesign.Art(activity, artSource), new FrameLayout.LayoutParams(-1, -1));
    card.addView(art, new LinearLayout.LayoutParams(-1, ui.dp(64)));
    TextView name = ui.text(video ? "Studio Video Pro" : "Studio Ảnh Pro", 13, ui.ink, true);
    name.setPadding(0, ui.dp(6), 0, 0);
    card.addView(name);
    TextView meta = ui.text(durationText(until), 10, ui.muted, false);
    meta.setMaxLines(1);
    meta.setEllipsize(android.text.TextUtils.TruncateAt.END);
    meta.setPadding(0, ui.dp(1), 0, 0);
    card.addView(meta);
    LinearLayout footer = ui.row();
    footer.setPadding(0, ui.dp(4), 0, 0);
    footer.addView(ui.text(tr("Đã có"), 10, ui.purple, true), new LinearLayout.LayoutParams(0, -2, 1));
    card.addView(footer);
    card.setOnClickListener(v -> chooseMedia());
    return card;
  }

  private void productGrid(LinearLayout parent, List<JSONObject> products) {
    for (int i = 0; i < products.size(); i += 2) {
      LinearLayout row = ui.row();
      row.setBaselineAligned(false);
      LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(-1, -2);
      rp.topMargin = ui.dp(8);
      parent.addView(row, rp);
      View first = product(products.get(i), true);
      LinearLayout.LayoutParams fp = new LinearLayout.LayoutParams(0, -2, 1);
      fp.rightMargin = ui.dp(4);
      row.addView(first, fp);
      if (i + 1 < products.size()) {
        View second = product(products.get(i + 1), true);
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(0, -2, 1);
        sp.leftMargin = ui.dp(4);
        row.addView(second, sp);
      } else {
        row.addView(new View(activity), new LinearLayout.LayoutParams(0, -2, 1));
      }
    }
  }

  private View product(JSONObject p, boolean actions) {
    String id = p.optString("id");
    boolean studio = p.optString("kind").equals("studio"), free = studio && catalog.optBoolean("studioProFree"), owned = owns(id), applied = id.equals(catalog.optString("appearance"));
    String state = free ? "Miễn phí" : owned ? (applied ? "Đang dùng" : "Đã có") : (Distribution.PLAY && catalog.optBoolean("billingReady") && prices.containsKey(id) ? "Mua một lần" : "Chưa mở bán");
    LinearLayout card = tileCard();
    card.setTag("store:product:" + id);
    View art = actions ? new StoreArt(activity, p) : new StorePackageDesign.Art(activity, p);
    art.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
    card.addView(art, new LinearLayout.LayoutParams(-1, ui.dp(64)));
    TextView name = ui.text(p.optString("name"), 13, ui.ink, true);
    name.setMaxLines(1);
    name.setEllipsize(android.text.TextUtils.TruncateAt.END);
    name.setPadding(0, ui.dp(6), 0, 0);
    card.addView(name);
    TextView meta = ui.text(studio ? tr("Studio") : tr("Phong cách"), 10, ui.muted, false);
    meta.setPadding(0, ui.dp(1), 0, 0);
    card.addView(meta);
    LinearLayout footer = ui.row();
    footer.setPadding(0, ui.dp(4), 0, 0);
    footer.addView(ui.text(state, 10, owned || free ? ui.purple : ui.muted, true), new LinearLayout.LayoutParams(0, -2, 1));
    if (actions) {
      if (free || owned) {
        if (studio) {
          footer.addView(chipAction(tr("Mở"), true, this::chooseMedia), new LinearLayout.LayoutParams(-2, -2));
        } else if (!applied) {
          footer.addView(chipAction(tr("Dùng"), true, () -> apply(id)), new LinearLayout.LayoutParams(-2, -2));
        }
      } else if (Distribution.PLAY && catalog.optBoolean("billingReady") && prices.containsKey(id)) {
        footer.addView(chipAction(prices.get(id), true, () -> {
          if (busy) return;
          new Sheet(activity).setTitle(p.optString("name"))
            .setMessage(tr("Mua một lần") + " · " + prices.get(id) + "\n\n" + tr("Quyền lợi gắn với tài khoản Kinnect đang đăng nhập."))
            .setPositiveButton(tr("Tiếp tục với Google Play"), (d, w) -> billing.buy(id))
            .setNegativeButton(tr("Hủy"), null).show();
        }), new LinearLayout.LayoutParams(-2, -2));
      } else {
        footer.addView(chipAction(tr("Xem thử"), true, () -> showProduct(p)), new LinearLayout.LayoutParams(-2, -2));
      }
    }
    card.addView(footer);
    card.setContentDescription(p.optString("name") + " · " + tr("Xem thử"));
    card.setOnClickListener(v -> showProduct(p));
    return card;
  }

  private void showPlan(JSONObject p) {
    String id = p.optString("id");
    boolean active = ownsPackage(id);
    try {
      JSONObject details = new JSONObject(p.toString());
      details.put("actionLabel", active ? (isEquipped(p) && selectedTab.equals("owned") ? "Gỡ trang bị" : "Dùng ngay") : "Mua gói");
      details.put("adminAccess", catalog != null && catalog.optBoolean("adminAccess"));
      StorePackageDesign.details(activity, details, p.optBoolean("available") ? () -> {
        if (active) usePackage(p);
        else buyPlan(p);
      } : null);
    } catch (JSONException ignored) {}
  }

  private void showProduct(JSONObject p) {
    String id = p.optString("id");
    String description = p.optString(I18n.current().equals("en") ? "descriptionEn" : "description");
    if (id.equals("kinnect_studio_pro") && catalog != null && catalog.optBoolean("studioProFree")) {
      description = tr("Miễn phí trải nghiệm") + "\n\n" + description.replace("Mua một lần, dùng trên tài khoản này.", "").replace("One-time purchase for this account.", "");
    }
    if (!owns(id) && !(id.equals("kinnect_studio_pro") && catalog != null && catalog.optBoolean("studioProFree")) && !prices.containsKey(id)) {
      description += "\n\n" + tr("Giá dự kiến, chưa phải giá thanh toán") + ": " + java.text.NumberFormat.getIntegerInstance(new Locale("vi", "VN")).format(p.optInt("referenceVnd")) + "đ";
    }
    Sheet sheet = new Sheet(activity).setTitle(p.optString("name")).setMessage(description + "\n\n" + tr("Xem thử không thay đổi hồ sơ hoặc cấp quyền sử dụng.")).setView(preview(p));
    if (owns(id) && p.optString("kind").equals("style") && catalog != null && !id.equals(catalog.optString("appearance"))) {
      sheet.setPositiveButton(tr("Dùng"), (d, w) -> apply(id)).setNegativeButton(tr("Đóng"), null);
    } else {
      sheet.setPositiveButton(tr("Đóng"), null);
    }
    sheet.show();
  }

  private View preview(JSONObject product) {
    LinearLayout box = new LinearLayout(activity);
    box.setOrientation(LinearLayout.VERTICAL);
    box.setPadding(dp(12), dp(12), dp(12), dp(12));
    JSONArray colors = product.optJSONArray("colors");
    int color = Color.parseColor(colors != null && colors.length() > 0 ? colors.optString(0) : "#7c3aed");
    TextView demo = new KinnectText(activity);
    demo.setText(product.optString("kind").equals("studio") ? "Aurora · Travel · Cinema" : "Kinnect · " + tr("Hồ sơ minh họa"));
    demo.setTextSize(22);
    demo.setTextColor(color);
    demo.setGravity(Gravity.CENTER);
    GradientDrawable frame = round(WebDesign.CARD[variant()], 18);
    frame.setStroke(dp(3), color);
    demo.setPadding(dp(16), dp(18), dp(16), dp(18));
    demo.setBackground(frame);
    box.addView(demo);

    TextView chat = new KinnectText(activity);
    chat.setText(tr("Xin chào! Đây là bản xem thử."));
    chat.setTextSize(16);
    chat.setTextColor(Color.WHITE);
    chat.setPadding(dp(16), dp(16), dp(16), dp(16));
    chat.setBackground(round(color, 18));
    LinearLayout.LayoutParams at = new LinearLayout.LayoutParams(-1, -2);
    at.topMargin = dp(18);
    box.addView(chat, at);
    return box;
  }

  private void chooseMedia() {
    new Sheet(activity).setTitle("Studio Pro").setItemIcons(new String[]{"image", "clapperboard"}).setItems(
      new String[]{tr("Ảnh"), tr("Video")},
      (d, w) -> {
        try {
          activity.startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(w == 0 ? "image/*" : "video/*"), w == 0 ? 701 : 700);
        } catch (Exception e) {
          message(tr("Không mở được thư viện tệp."));
        }
      }
    ).setNegativeButton(tr("Quay lại"), null).show();
  }

  public void prices(Map<String, String> value) {
    activity.runOnUiThread(() -> {
      if (closed || activity.isDestroyed()) return;
      prices.clear();
      prices.putAll(value);
      if (catalog != null) draw();
    });
  }

  public void receipt(String product, String token) {
    activity.runOnUiThread(() -> {
      if (closed || activity.isDestroyed()) return;
      receiptQueue.add(new String[]{product, token});
      verifyNext();
    });
  }

  private void verifyNext() {
    if (busy || receiptQueue.isEmpty() || closed || activity.isDestroyed()) return;
    busy = true;
    String[] receipt = receiptQueue.remove();
    try {
      NativeApi.shared.call("POST", "/api/store/verify", new JSONObject().put("productId", receipt[0]).put("purchaseToken", receipt[1]), (data, error, status) -> {
        busy = false;
        if (closed || activity.isDestroyed()) return;
        message(error != null ? error : data.optString("state").equals("PURCHASED") ? tr("Giao dịch đã xác minh. Quyền lợi đã được cập nhật.") : tr("Giao dịch đang chờ xử lý; chưa cấp quyền lợi."));
        if (receiptQueue.isEmpty()) load(false);
        else verifyNext();
      });
    } catch (Exception e) {
      busy = false;
      message(tr("Chưa xác minh được giao dịch."));
      verifyNext();
    }
  }

  public void message(String text) {
    activity.runOnUiThread(() -> {
      if (!closed && !activity.isDestroyed() && !SuccessEffects.message(activity, text)) {
        Toast.makeText(activity, I18n.t(text), Toast.LENGTH_LONG).show();
      }
    });
  }

  public void close() {
    closed = true;
    SuccessEffects.clear(activity);
    if (billing != null) billing.close();
  }

  private static final class StoreArt extends View {
    private final JSONObject product;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
    private final Activity activity;

    StoreArt(Activity activity, JSONObject value) {
      super(activity);
      this.activity = activity;
      this.product = value;
      setContentDescription(value.optString("name") + " · " + I18n.t("Xem thử"));
    }

    private void box(Canvas c, float l, float t, float r, float b, float radius, int color) {
      paint.setShader(null);
      paint.setColor(color);
      c.drawRoundRect(l, t, r, b, radius, radius, paint);
    }

    protected void onDraw(Canvas source) {
      super.onDraw(source);
      Canvas c = source;
      int save = c.save();
      c.scale(getWidth() / 300f, getHeight() / 178f);
      JSONArray colors = product.optJSONArray("colors");
      int a = Color.parseColor(colors != null && colors.length() > 0 ? colors.optString(0) : "#7c3aed");
      int b = Color.parseColor(colors != null && colors.length() > 1 ? colors.optString(1) : "#c026d3");
      paint.setShader(new LinearGradient(0, 0, 300, 178, a, b, Shader.TileMode.CLAMP));
      c.drawRoundRect(0, 0, 300, 178, 18, 18, paint);
      paint.setShader(null);
      paint.setColor(0x33ffffff);
      c.drawCircle(55, 30, 110, paint);
      paint.setColor(0x22ffffff);
      c.drawCircle(265, 160, 85, paint);

      if (product.optString("kind").equals("studio")) {
        for (int i = 0; i < 3; i++) {
          float x = 55 + i * 65;
          box(c, x, 30 + (i == 1 ? -8 : 4), x + 55, 132 + (i == 1 ? 8 : 0), 10, 0x55ffffff);
          Drawable icon = WebIcons.load(activity, i == 0 ? "sparkles" : i == 1 ? "play" : "clapperboard");
          if (icon != null) {
            icon.setTint(Color.WHITE);
            icon.setBounds((int) x + 15, 65, (int) x + 40, 90);
            icon.draw(c);
          }
        }
      } else {
        paint.setColor(0x66ffffff);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(1);
        c.drawCircle(139, 78, 70, paint);
        paint.setStrokeWidth(4);
        c.drawCircle(125, 70, 36, paint);
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(0x44ffffff);
        c.drawCircle(125, 70, 32, paint);
        paint.setColor(Color.WHITE);
        paint.setTypeface(ApprovedTypography.font(activity, Typeface.BOLD));
        paint.setTextSize(32);
        paint.setTextAlign(Paint.Align.CENTER);
        c.drawText("K", 125, 81, paint);
        box(c, 157, 85, 246, 124, 12, 0xeeffffff);
        box(c, 170, 96, 230, 101, 3, a);
        box(c, 170, 108, 212, 112, 3, b);
      }
      paint.setShader(null);
      paint.setColor(Color.WHITE);
      paint.setTextAlign(Paint.Align.CENTER);
      paint.setTypeface(ApprovedTypography.font(activity, Typeface.BOLD));
      paint.setTextSize(9);
      c.restoreToCount(save);
    }
  }
}

