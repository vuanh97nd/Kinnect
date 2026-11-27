package app.kinnect.live;

/**
 * Generated from the approved web CSS. Native Android resources only.
 * Modified for Google Pixel / Material You aesthetics and WCAG v2.0 tokens.
 */
final class WebDesign {
  // Bảng màu nhẹ nhàng, pastel đặc trưng của Pixel (Monet) — khớp android/design/web-reference.json
  static final int[] PURPLE = { 0xff6c47e0, 0xff7652e8 };
  static final int[] PURPLE_INK = { 0xff5b3fd6, 0xff7652e8 };
  static final int[] SOFT = { 0xfff1ecff, 0xff332a48 };
  static final int[] BG = { 0xfff6f5fa, 0xff151419 };
  static final int[] CARD = { 0xffffffff, 0xff222128 };
  static final int[] INK = { 0xff1f1d2b, 0xfff1eff7 };
  static final int[] MUTED = { 0xff6a6478, 0xffb1aabd };
  static final int[] LINE = { 0xffe4e0ec, 0xff38333f };
  static final int[] WASH = { 0xfff4f1fa, 0xff2c2833 };
  static final int[] DANGER = { 0xffc2365a, 0xffd56579 };
  static final int[] SUCCESS = { 0xff1f7a4d, 0xff75c89c };
  static final int[] ONLINE = { 0xff2e9e66, 0xff40ae78 };

  // Token tương phản nghiêm ngặt WCAG AA v2.0 (giữ nguyên 12 mảng trên cho test-native-design.py)
  static final int[] MUTED_STRICT = { 0xff5e586c, 0xffb1aabd };
  static final int[] ONLINE_STRICT = { 0xff187a4b, 0xff40ae78 };
  static final int[] PURPLE_HERO = { 0xff5b21b6, 0xff7c3aed };
  static final int[] HERO_GRADIENT = PURPLE_HERO;
  static final int[] WALLET_HERO_GRADIENT = { 0xff5b21b6, 0xffa21caf };
  static final int[] PURPLE_TEXT_STRICT = { 0xff5b3fd6, 0xffbc85ff };
  static final int[] CHIP_WASH_BG = { 0xfff4f1fa, 0xff2c2833 };
  static final int[] SCRIM_BOTTOM = { 0x00000000, 0xd914111d };
  static final int LIVE_RED = 0xffd61f26;
  static final int DARK_ACCENT_TEXT = 0xffbc85ff;
  static final int STORE_DARK_REMOVE_BG = 0xff1f7a4d;
  static final int STORE_DARK_PREVIEW_TEXT = 0xffc4b5fd;

  // Kích thước chữ to hơn một chút cho chuẩn dễ đọc của Google
  static final int BODY = 15, LABEL = 14, META = 13, TITLE = 22, SECTION = 16;

  // Tăng bán kính bo góc card lên 24 (Chuẩn M3) và chiều cao control
  static final int CONTROL = 48, CARD_RADIUS = 24, HEADER = 64;

  // Chuyển động dùng chung cho toàn app (ms) — khớp token web 140/220/320.
  static final int MOTION_FAST = 140, MOTION_BASE = 220;
  static final int MOTION_SLOW = 320;

  // Tỉ lệ thu nhỏ giao diện (dp/icon/box) để hiển thị nhiều nội dung hơn; chữ do fontScale trong Application lo.
  static final float UI_SCALE = 0.9f;

  static int dpRaw(android.content.Context context, int dp) {
    return UiMetrics.dpRaw(context, dp);
  }
}
