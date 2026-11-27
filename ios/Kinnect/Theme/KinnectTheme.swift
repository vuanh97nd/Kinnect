import SwiftUI
import UIKit

enum KinnectTheme {
    static var background: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0.96, green: 0.95, blue: 0.98, alpha: 1.0)
                : UIColor(red: 0.05, green: 0.04, blue: 0.11, alpha: 1.0)
        })
    }

    static var surface: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor.white
                : UIColor(red: 0.10, green: 0.08, blue: 0.19, alpha: 1.0)
        })
    }

    static var surfaceElevated: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0.92, green: 0.90, blue: 0.96, alpha: 1.0)
                : UIColor(red: 0.15, green: 0.12, blue: 0.27, alpha: 1.0)
        })
    }

    static var border: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                    ? UIColor.black.withAlphaComponent(0.15)
                    : UIColor.white.withAlphaComponent(0.20)
        })
    }

    static var borderSoft: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                    ? UIColor.black.withAlphaComponent(0.08)
                    : UIColor.white.withAlphaComponent(0.10)
        })
    }

    static var line: Color { border }

        // MARK: - Corner Radius Scale
        static let radiusXS: CGFloat = 8
        static let radiusSM: CGFloat = 12
        static let radiusMD: CGFloat = 16
        static let radiusLG: CGFloat = 24
        static let radiusXL: CGFloat = 32
        static let radiusPill: CGFloat = 999

    static let accent = Color(red: 0.49, green: 0.23, blue: 0.93)           // #7C3AED
    /// Adaptive brand accent for text, icons, and active badges: vivid #BC85FF (>6.5:1 WCAG AA) in Dark Mode,
    /// high-contrast #6E29D9 (>5.3:1 WCAG AA on light surfaces & white foreground) in Light Mode.
    static var accentBright: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0.43, green: 0.16, blue: 0.85, alpha: 1.0)
                : UIColor(red: 0xBC / 255.0, green: 0x85 / 255.0, blue: 0xFF / 255.0, alpha: 1.0)
        })
    }
    static var accentText: Color { accentBright }
    static let accentLight = Color(red: 0.58, green: 0.44, blue: 1.00)
    static var accentSoft: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0.93, green: 0.91, blue: 1.00, alpha: 1.0)
                : UIColor(red: 0x2D / 255.0, green: 0x24 / 255.0, blue: 0x48 / 255.0, alpha: 1.0)
        })
    }

    static var textPrimary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0.11, green: 0.08, blue: 0.22, alpha: 1.0)
                : UIColor.white
        })
    }

    static var textSecondary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0x5C / 255.0, green: 0x54 / 255.0, blue: 0x70 / 255.0, alpha: 1.0)
                : UIColor(red: 0.72, green: 0.69, blue: 0.84, alpha: 1.0)
        })
    }

    static var textTertiary: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0x7A / 255.0, green: 0x72 / 255.0, blue: 0x8E / 255.0, alpha: 1.0)
                : UIColor(red: 0.65, green: 0.62, blue: 0.78, alpha: 1.0)
        })
    }

    /// High-contrast placeholder color for inputs (#5C5470 Light >= 5.81:1 / #A9A2C6 Dark >= 6.36:1).
    static var inputPlaceholder: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0x5C / 255.0, green: 0x54 / 255.0, blue: 0x70 / 255.0, alpha: 1.0)
                : UIColor(red: 0xA9 / 255.0, green: 0xA2 / 255.0, blue: 0xC6 / 255.0, alpha: 1.0)
        })
    }

    // MARK: - Typography Fonts
    static let body: Font = .system(size: 15)
    static let bodyBold: Font = .system(size: 15, weight: .bold)
    static let caption: Font = .system(size: 12)
    static let captionBold: Font = .system(size: 12, weight: .bold)

    /// Time and small icons under chat bubbles. Dark mode stays light so it
    /// remains readable on the purple-black background. Light mode stays dark.
    static var messageMeta: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0.29, green: 0.25, blue: 0.38, alpha: 1.0)
                : UIColor(red: 0.82, green: 0.78, blue: 0.93, alpha: 1.0)
        })
    }

    static let rose = Color(red: 0.93, green: 0.28, blue: 0.60)
    static let emerald = Color(red: 0.09, green: 0.64, blue: 0.45)
    /// Adaptive WCAG AA compliant green for text & badges (#1F7A4D light / #75C89C dark).
    static var success: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0x1F / 255.0, green: 0x7A / 255.0, blue: 0x4D / 255.0, alpha: 1.0)
                : UIColor(red: 0x75 / 255.0, green: 0xC8 / 255.0, blue: 0x9C / 255.0, alpha: 1.0)
        })
    }
    static var online: Color { success }
    /// Vivid #21C45E strictly for non-text status indicator dots.
    static let onlineDot = Color(red: 0x21 / 255.0, green: 0xC4 / 255.0, blue: 0x5E / 255.0)
    static let callGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let callRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    /// Adaptive amber/warning: WCAG AA compliant #B45309 in Light Mode, vivid #F59E0B in Dark Mode.
    static var amber: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0xB4 / 255.0, green: 0x53 / 255.0, blue: 0x09 / 255.0, alpha: 1.0)
                : UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
        })
    }
    static var warning: Color { amber }
    /// Adaptive WCAG AA compliant danger/destructive red (#C2365A light / #D56579 dark).
    static var danger: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0xC2 / 255.0, green: 0x36 / 255.0, blue: 0x5A / 255.0, alpha: 1.0)
                : UIColor(red: 0xD5 / 255.0, green: 0x65 / 255.0, blue: 0x79 / 255.0, alpha: 1.0)
        })
    }
    /// High-contrast LIVE badge & CTA red (#D61F26, >= 5.05:1 with white text).
    static let liveRed = Color(red: 0xD6 / 255.0, green: 0x1F / 255.0, blue: 0x26 / 255.0)
    /// WCAG AA compliant purple preset for avatars (#9E34B0, >= 5.5:1 with white text).
    static let avatarPurplePreset = Color(red: 0x9E / 255.0, green: 0x34 / 255.0, blue: 0xB0 / 255.0)

    static var surfaceBg: Color { background }
    static var cardBg: Color { surface }

    @MainActor
    static func applyWindowAppearance(_ mode: String) {
        let style: UIUserInterfaceStyle
        #if DEBUG
        if UIReviewFixture.isEnabled,
           let screenName = UIReviewFixture.activeScreen,
           UIReviewFixture.requiresDarkAppearance(for: screenName) {
            style = .dark
        } else if let overrideLight = UIReviewFixture.overrideLightMode {
            style = overrideLight ? .light : .dark
        } else if UIReviewFixture.forceLightMode {
            style = .light
        } else {
            switch mode {
            case "light": style = .light
            case "dark": style = .dark
            default: style = .unspecified
            }
        }
        #else
        switch mode {
        case "light": style = .light
        case "dark": style = .dark
        default: style = .unspecified
        }
        #endif
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    static let primaryGradient = LinearGradient(
        colors: [
            Color(red: 0.49, green: 0.23, blue: 0.93),
            Color(red: 0.86, green: 0.15, blue: 0.67)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandGradient = primaryGradient

    static func relativeTime(from timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return L10n.tr("Vừa xong") }
        let seconds = max(0, Int((Int64(Date().timeIntervalSince1970 * 1000) - timestampMs) / 1000))
        if seconds < 45 { return L10n.tr("Vừa xong") }
        if seconds < 3600 { return "\(seconds / 60) \(L10n.tr("phút"))" }
        if seconds < 86400 { return "\(seconds / 3600) \(L10n.tr("giờ"))" }
        return "\(seconds / 86400) \(L10n.tr("ngày"))"
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (124, 58, 237)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

// MARK: - High-Performance In-Memory Image Cache (Zero Disk I/O & Butter-smooth 120 FPS)
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 120 * 1024 * 1024 // 120 MB
    }

    private func scopedKey(_ key: String) -> NSString {
        let accountScope = AccountCache.shared.activeAccountId ?? "anon"
        return "\(accountScope)|\(key)" as NSString
    }

    func image(forKey key: String) -> UIImage? {
        guard !key.isEmpty else { return nil }
        return cache.object(forKey: scopedKey(key))
    }

    func store(_ image: UIImage, forKey key: String) {
        guard !key.isEmpty else { return }
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: scopedKey(key), cost: cost)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

struct KinnectAvatarView: View {
    let name: String
    let avatarURL: String
    var colorHex: String = "#7C3AED"
    var size: CGFloat = 44
    var isOnline: Bool = false

    @State private var loadedImage: UIImage?

    init(
        name: String,
        avatarURL: String,
        colorHex: String = "#7C3AED",
        size: CGFloat = 44,
        isOnline: Bool = false
    ) {
        self.name = name
        self.avatarURL = avatarURL
        self.colorHex = colorHex
        self.size = size
        self.isOnline = isOnline
        _loadedImage = State(initialValue: ImageMemoryCache.shared.image(forKey: avatarURL))
    }

    init(user: KinnectUser, size: CGFloat = 44) {
        self.name = user.name
        self.avatarURL = user.avatarUrl
        self.colorHex = user.avatarColor
        self.size = size
        self.isOnline = user.isActive && user.showActivity
        _loadedImage = State(initialValue: ImageMemoryCache.shared.image(forKey: user.avatarUrl))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [resolvedLeadingColor, KinnectTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text(initials)
                            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(KinnectTheme.surface, lineWidth: size >= 64 ? 3 : 0)
            )

            if isOnline {
                Circle()
                    .fill(KinnectTheme.onlineDot)
                    .frame(width: max(10, size * 0.25), height: max(10, size * 0.25))
                    .overlay(Circle().stroke(KinnectTheme.surface, lineWidth: 2))
            }
        }
        .task(id: avatarURL) {
            if let mem = ImageMemoryCache.shared.image(forKey: avatarURL) {
                loadedImage = mem
                return
            }
            loadedImage = nil
            guard !avatarURL.isEmpty else {
                return
            }
            if let data = await KinnectAPIClient.shared.fetchBinaryData(path: avatarURL),
               let uiImg = UIImage(data: data) {
                ImageMemoryCache.shared.store(uiImg, forKey: avatarURL)
                loadedImage = uiImg
            }
        }
    }

    private var resolvedLeadingColor: Color {
        let normalized = colorHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized == "#EC4899" || normalized == "EC4899" {
            return KinnectTheme.avatarPurplePreset
        }
        return Color(hex: colorHex)
    }

    private var initials: String {
        let words = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "K" }
        let letters = words.suffix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "K" : result
    }
}

struct KinnectRemoteImageView: View {
    let rawURL: String
    var contentMode: ContentMode = .fit
    var cornerRadius: CGFloat = 16
    var maxHeight: CGFloat = 320

    @State private var image: UIImage?
    @State private var failed = false

    init(
        rawURL: String,
        contentMode: ContentMode = .fit,
        cornerRadius: CGFloat = 16,
        maxHeight: CGFloat = 320
    ) {
        self.rawURL = rawURL
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.maxHeight = maxHeight
        _image = State(initialValue: ImageMemoryCache.shared.image(forKey: rawURL))
    }

    init(path: String, maxHeight: CGFloat = 320) {
        self.rawURL = path
        self.maxHeight = maxHeight
        _image = State(initialValue: ImageMemoryCache.shared.image(forKey: path))
    }

    var body: some View {
        Group {
            if let img = image {
                if contentMode == .fill {
                    let rawRatio = img.size.height > 0 ? (img.size.width / img.size.height) : 1.0
                    let clampedRatio = min(max(rawRatio, 0.78), 1.91)
                    Color.clear
                        .aspectRatio(clampedRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                        )
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: maxHeight)
                }
            } else if failed {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(height: min(180, maxHeight))
                    .overlay(ProgressView().tint(KinnectTheme.accentBright))
            }
        }
        .task(id: rawURL) {
            failed = false
            if let mem = ImageMemoryCache.shared.image(forKey: rawURL) {
                image = mem
                return
            }
            image = nil
            guard !rawURL.isEmpty else {
                failed = true
                return
            }
            if let data = await KinnectAPIClient.shared.fetchBinaryData(path: rawURL),
               let uiImg = UIImage(data: data) {
                ImageMemoryCache.shared.store(uiImg, forKey: rawURL)
                image = uiImg
            } else {
                failed = true
            }
        }
    }
}

extension View {
    /// Prevents text clipping or horizontal compression across iPhone and iPad sizes.
    func kinnectMultiline() -> some View {
        self.lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    func kinnectCard() -> some View {
        self.padding(14)
            .background(
                    RoundedRectangle(cornerRadius: KinnectTheme.radiusMD, style: .continuous)
                    .fill(KinnectTheme.surface)
                    .overlay(
                            RoundedRectangle(cornerRadius: KinnectTheme.radiusMD, style: .continuous)
                            .stroke(KinnectTheme.border, lineWidth: 1)
                    )
            )
    }

    /// Shimmer wave animation for skeleton loading
    func kinnectShimmer() -> some View {
        modifier(KinnectShimmerModifier())
    }
}

// MARK: - Skeleton Shimmer Loading (Micro-interactions & UX Parity)
public struct KinnectShimmerModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.0

    public func body(content: Content) -> some View {
        let sweepBase: Color = (colorScheme == .light) ? Color.black : Color.white
        let sweepPeakOpacity: Double = (colorScheme == .light) ? 0.08 : 0.12
        content
            .overlay(
                Group {
                    if !reduceMotion {
                        GeometryReader { geo in
                            LinearGradient(
                                colors: [
                                    sweepBase.opacity(0.0),
                                    sweepBase.opacity(sweepPeakOpacity),
                                    sweepBase.opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 1.5)
                            .offset(x: phase * geo.size.width)
                        }
                    }
                }
            )
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .linear(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.8
                }
            }
            .onChange(of: reduceMotion) { reduced in
                if reduced {
                    withAnimation(nil) {
                        phase = -1.0
                    }
                } else {
                    withAnimation(
                        .linear(duration: 1.4)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1.8
                    }
                }
            }
    }
}

public struct PostSkeletonCard: View {
    public init() {}
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(KinnectTheme.surfaceElevated)
                        .frame(width: 130, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(KinnectTheme.surfaceElevated)
                        .frame(width: 80, height: 10)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(maxWidth: .infinity, minHeight: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(width: 220, height: 12)
            }
            RoundedRectangle(cornerRadius: KinnectTheme.radiusLG)
                .fill(KinnectTheme.surfaceElevated)
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(width: 70, height: 18)
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(width: 80, height: 18)
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(width: 60, height: 18)
            }
            .padding(.top, 4)
        }
        .kinnectCard()
        .kinnectShimmer()
    }
}

public struct StorySkeletonStrip: View {
    public init() {}
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(KinnectTheme.surfaceElevated)
                            .frame(width: 58, height: 58)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(KinnectTheme.surfaceElevated)
                            .frame(width: 44, height: 10)
                    }
                    .frame(width: 68)
                }
            }
            .padding(.vertical, 6)
        }
        .kinnectShimmer()
    }
}

// MARK: - iPad-Safe UIActivityViewController Presenter
enum KinnectShareSheet {
    @MainActor
    static func present(items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let keyWindow = activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first
        guard var topVC = keyWindow?.rootViewController else { return }
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
    }
}

// MARK: - Modal-Visible Bottom Toast Snackbar (Pass-Through UIWindow)
@MainActor
private final class PassThroughToastWindow: UIWindow {
    var toastHitRect: CGRect = .zero

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0, !toastHitRect.isEmpty, toastHitRect.contains(point) else {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

private struct ToastPillFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct KinnectToastOverlayView: View {
    @ObservedObject private var appState = AppState.shared
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        VStack {
            Spacer()
            if let toast = appState.toastMessage, !toast.isEmpty {
                HStack(spacing: 10) {
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .kinnectMultiline()
                        .multilineTextAlignment(.leading)
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.11, green: 0.09, blue: 0.16).opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ToastPillFrameKey.self, value: geo.frame(in: .global))
                    }
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    appState.dismissToast()
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(toast). \(L10n.tr("Chạm để đóng"))")
                .padding(.horizontal, 16)
                .padding(.bottom, appState.currentUser != nil ? 76 : 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: appState.toastMessage)
        .onPreferenceChange(ToastPillFrameKey.self) { frame in
            onFrameChange(frame)
        }
    }
}

@MainActor
final class KinnectToastPresenter {
    static let shared = KinnectToastPresenter()
    private var window: PassThroughToastWindow?
    private var hostingController: UIHostingController<KinnectToastOverlayView>?

    private init() {}

    func sync(visible: Bool) {
        if !visible {
            window?.toastHitRect = .zero
            window?.isHidden = true
            return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return
        }
        if window == nil || window?.windowScene !== activeScene {
            let win = PassThroughToastWindow(windowScene: activeScene)
            win.backgroundColor = .clear
            win.windowLevel = .statusBar + 50
            win.isOpaque = false
            let host = UIHostingController(rootView: KinnectToastOverlayView { [weak win] frame in
                win?.toastHitRect = frame
            })
            host.view.backgroundColor = .clear
            win.rootViewController = host
            self.window = win
            self.hostingController = host
        }
        if let primaryStyle = activeScene.windows.first(where: { $0 !== window && $0.isKeyWindow })?.overrideUserInterfaceStyle {
            window?.overrideUserInterfaceStyle = primaryStyle
        }
        window?.isHidden = false
    }
}
