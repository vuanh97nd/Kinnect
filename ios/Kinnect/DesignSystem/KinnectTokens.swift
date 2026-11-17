// GENERATED FILE — do not edit by hand.
// Source: design/tokens.json (v1.1.0) · regenerate with: node tools/gen-tokens.mjs
import SwiftUI
import UIKit

// MARK: - Color (light/dark tự động theo traitCollection)

enum KTColor {
    static let background = dyn(light: "#F5F2FA", dark: "#0D0A1C")
    static let surface = dyn(light: "#FFFFFF", dark: "#1A1430")
    static let surfaceElevated = dyn(light: "#EBE6F5", dark: "#261F45")
    static let textPrimary = dyn(light: "#1C1438", dark: "#FFFFFF")
    static let textSecondary = dyn(light: "#5B5077", dark: "#B8B0D6")
    static let textTertiary = dyn(light: "#6E6880", dark: "#9A93B8")
    static let accent = dyn(light: "#6D3BE4", dark: "#7C3AED")
    static let accentSoft = dyn(light: "#EDE7FE", dark: "#2A1F52")
    static let onAccent = dyn(light: "#FFFFFF", dark: "#FFFFFF")
    static let border = dyn(light: "#DCD8EA", dark: "#332B52")
    static let danger = dyn(light: "#F04545", dark: "#F04545")
    static let success = dyn(light: "#0F7A4E", dark: "#21C45E")
    static let warning = dyn(light: "#F59E0A", dark: "#F59E0A")
    static let online = dyn(light: "#2E9E66", dark: "#2E9E66")

    private static func dyn(light: String, dark: String) -> Color {
        Color(UIColor { trait in
            UIColor(ktHex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// MARK: - Typography
// Giữ ĐÚNG size thiết kế ở cỡ chữ mặc định, vẫn scale theo Dynamic Type.
// (Trước đây scaled() bóp 16→17, 14→13 nên lệch thiết kế Android.)

enum KTType {
    static let displayL: Font = scaled(34, .bold, .largeTitle)
    static let displayM: Font = scaled(28, .bold, .title1)
    static let title: Font = scaled(22, .semibold, .title2)
    static let titleS: Font = scaled(20, .semibold, .title3)
    static let bodyL: Font = scaled(17, .regular, .body)
    static let body: Font = scaled(15, .regular, .subheadline)
    static let label: Font = scaled(13, .medium, .footnote)
    static let meta: Font = scaled(12, .regular, .caption1)
    static let micro: Font = scaled(11, .medium, .caption2)

    private static func scaled(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return Font(UIFontMetrics(forTextStyle: style).scaledFont(for: base))
    }
}

// MARK: - Spacing / Radius

enum KTSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum KTRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let pill: CGFloat = 999
}

// MARK: - Layout

enum KTLayout {
    static let contentMaxWidth: CGFloat = 700
    static let touchTargetMin: CGFloat = 44
    static let bubbleMaxWidthRatio: CGFloat = 0.72
}

// MARK: - Motion (tôn trọng Reduce Motion)

enum KTMotion {
    static let fast: Double = 0.14
    static let base: Double = 0.22
    static let slow: Double = 0.32

    static func animation(_ duration: Double, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0, 0, 1, duration: duration)
    }
}

// MARK: - Elevation

enum KTElevation {
    struct Spec { let y: CGFloat; let blur: CGFloat; let opacity: Double }
    static let e0 = Spec(y: 0, blur: 0, opacity: 0)
    static let e1 = Spec(y: 1, blur: 3, opacity: 0.1)
    static let e2 = Spec(y: 8, blur: 24, opacity: 0.16)
}

extension View {
    func ktElevation(_ spec: KTElevation.Spec) -> some View {
        shadow(color: .black.opacity(spec.opacity), radius: spec.blur / 2, x: 0, y: spec.y)
    }
}

// MARK: - Hex helper

extension UIColor {
    convenience init(ktHex hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let n = h.count == 3 ? h.map { "\($0)\($0)" }.joined() : h
        let v = UInt64(n, radix: 16) ?? 0
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}
