package app.kinnect.live;

/**
 * Số đo thanh tiêu đề, dùng chung với iOS (KTLayout trong KinnectTokens.swift).
 * Tỷ lệ icon : khoảng cách : lề = 20 : 12 : 16.
 *
 * Không dùng số khác cho thanh tiêu đề. Nếu cần thay đổi, sửa design/tokens.json
 * rồi chạy tools/gen-tokens.mjs, và cập nhật file này theo cùng giá trị.
 */
final class UiMetrics {
  private UiMetrics() {}

  /** Chiều cao thanh tiêu đề (dp). */
  static final int HEADER_HEIGHT = 56;
  /** Lề ngang hai bên (dp). */
  static final int HEADER_SIDE_PADDING = 16;
  /** Cỡ icon nhìn (dp). */
  static final int HEADER_ICON_SIZE = 20;
  /** Khoảng cách giữa các icon (dp). */
  static final int HEADER_ICON_GAP = 12;
  /** Số hành động tối đa bên phải; vượt thì gom vào menu. */
  static final int HEADER_MAX_TRAILING_ACTIONS = 3;
  /** Vùng chạm tối thiểu trên Android (Material). iOS dùng 44. */
  static final int TOUCH_TARGET_MIN = 48;
}
