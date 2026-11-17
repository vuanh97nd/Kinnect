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

    // MARK: - 4-Point Spacing Scale
    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 12
    static let spaceLG: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let space2XL: CGFloat = 32

    // MARK: - Corner Radius Scale
    static let radiusXS: CGFloat = 8
    static let radiusSM: CGFloat = 12
    static let radiusMD: CGFloat = 16
    static let radiusLG: CGFloat = 24
    static let radiusXL: CGFloat = 32
    static let radiusPill: CGFloat = 999

    static let accent = Color(red: 0.49, green: 0.23, blue: 0.93)           // #7C3AED
    static let accentBright = Color(red: 0.65, green: 0.33, blue: 0.97)     // #A855F7
    static let accentLight = Color(red: 0.58, green: 0.44, blue: 1.00)
    static let accentSoft = Color(red: 0.93, green: 0.91, blue: 1.00)

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
                ? UIColor(red: 0.45, green: 0.40, blue: 0.55, alpha: 1.0)
                : UIColor(red: 0.72, green: 0.69, blue: 0.84, alpha: 1.0)
        })
    }

    static var textTertiary: Color {
        textSecondary.opacity(0.65)
    }

    // MARK: - Typography Fonts
    // Android roles at the default scale are 22 / 16 / 15 / 14 / 13.
    // These use text styles so Dynamic Type can grow them.
    static let screenTitle: Font = .title2.weight(.bold)
    static let sectionTitle: Font = .headline
    static var body: Font { scaled(15) }
    static var bodyBold: Font { scaled(15, weight: .bold) }
    static let secondary: Font = .subheadline
    static let caption: Font = .footnote
    static let captionBold: Font = .footnote.weight(.semibold)

    /// Keeps the Android role size at the default text scale and grows it
    /// when the user raises Dynamic Type. Sizes 22, 16–17, 15, 14 and 13
    /// map to title, headline, subheadline, footnote and caption.
    static func scaled(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let role: Font
        if size >= 22 {
            role = .title2
        } else if size >= 17 {
            role = .headline
        } else if size >= 15 {
            role = .subheadline
        } else if size >= 13 {
            role = .footnote
        } else {
            role = .caption
        }
        return role.weight(weight)
    }

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
    static let online = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let onlinePresence = Color(hex: "#2E9E66")
    static let success = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let callGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let callRed = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)

    // MARK: - Canonical Brand & Feature Tokens
    static let brandViolet = Color(red: 0x7B / 255.0, green: 0x43 / 255.0, blue: 0xF7 / 255.0)
    static let brandMagenta = Color(red: 0xED / 255.0, green: 0x45 / 255.0, blue: 0xAA / 255.0)
    static let brandSignatureGradient = LinearGradient(
        colors: [brandViolet, brandMagenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let messageVioletStart = Color(hex: "#8E2DE2")
    static let messageVioletEnd = Color(hex: "#4A00E0")
    static let messageBubbleGradient = LinearGradient(
        colors: [messageVioletStart, messageVioletEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let storyPurpleGradient = LinearGradient(
        colors: [Color(red: 0x83 / 255.0, green: 0x54 / 255.0, blue: 0xEF / 255.0), Color(red: 0xD9 / 255.0, green: 0x4C / 255.0, blue: 0xAE / 255.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let storyBlueGradient = LinearGradient(
        colors: [Color(red: 0x39 / 255.0, green: 0x7B / 255.0, blue: 0xE9 / 255.0), Color(red: 0x72 / 255.0, green: 0x4E / 255.0, blue: 0xE5 / 255.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let storyBackdropDark = Color(red: 0.06, green: 0.06, blue: 0.10)

    static let walletBalanceGradient = LinearGradient(
        colors: [accent, Color(hex: "#C026D3")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let walletStoreBalanceGradient = LinearGradient(
        colors: [Color(hex: "#5B21B6"), Color(hex: "#C026D3")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let storeHeroGradient = LinearGradient(
        colors: [Color(hex: "#3B1E6D"), Color(hex: "#1E1338")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let storeFrameBackdrop = Color(hex: "#23183D")
    static let storePreviewSurface = Color(hex: "#1A102E")
    static let storeArtworkDarkFallback = Color(hex: "#161329")
    static let storeBannerDarkFallback = Color(hex: "#181326")

    static let profileDefaultBannerGradient = LinearGradient(
        colors: [Color(red: 0x42 / 255.0, green: 0x35 / 255.0, blue: 0x5d / 255.0), Color(red: 0x1d / 255.0, green: 0x19 / 255.0, blue: 0x29 / 255.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let shortsBackdropGradient = LinearGradient(
        colors: [Color(red: 0.16, green: 0.08, blue: 0.32), Color(red: 0.05, green: 0.03, blue: 0.14)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let mediaTileDark = Color(red: 0.06, green: 0.08, blue: 0.13)

    static let authFrameBorder = Color(red: 0.65, green: 0.65, blue: 0.68)
    static let authLiveBadge = Color(red: 0.86, green: 0.15, blue: 0.47)

    static let callBackdropColors: [Color] = [Color(red: 0.14, green: 0.16, blue: 0.22), .black]
    static let callVideoBackdropColors: [Color] = [Color(red: 0.12, green: 0.13, blue: 0.18), .black]
    static let callPipBackground = Color(red: 0.12, green: 0.13, blue: 0.18)
    static let callDockFill = Color(red: 0.10, green: 0.10, blue: 0.14).opacity(0.85)
    static let callConnectedTint = Color(hex: "#4ADE80")

    static let studioCanvasDark = Color(red: 0.05, green: 0.04, blue: 0.08)
    static let studioPreviewUIColor = UIColor(red: 0.05, green: 0.04, blue: 0.09, alpha: 1.0)
    static let studioViewfinderCGColors: [CGColor] = [
        UIColor(red: 0.11, green: 0.07, blue: 0.22, alpha: 1.0).cgColor,
        UIColor(red: 0.04, green: 0.03, blue: 0.08, alpha: 1.0).cgColor,
        UIColor(red: 0.09, green: 0.05, blue: 0.16, alpha: 1.0).cgColor
    ]
    static let studioGridGuideCGColor: CGColor = UIColor(red: 0xFD / 255.0, green: 0xD6 / 255.0, blue: 0x63 / 255.0, alpha: 0.65).cgColor

    static let liveCrimson = Color(red: 0.96, green: 0.24, blue: 0.42)
    static let livePinkHighlight = Color(red: 0.98, green: 0.45, blue: 0.65)
    static let liveEndRed = Color(red: 0.92, green: 0.24, blue: 0.34)
    static let liveCoralError = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let liveGameEmerald = Color(hex: "#10B981")
    static let liveGameMint = Color(hex: "#34D399")
    static let liveGameCyan = Color(hex: "#0284C7")
    static let liveAmberPause = Color(hex: "#F59E0B")
    static let liveGameStageColors: [Color] = [
        Color(red: 0.04, green: 0.07, blue: 0.14),
        Color(red: 0.05, green: 0.11, blue: 0.16),
        Color(red: 0.03, green: 0.04, blue: 0.08)
    ]
    static let liveChatCTAGradient = LinearGradient(
        colors: [liveCrimson, Color(red: 0.56, green: 0.24, blue: 0.96)],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let liveGameCTAGradient = LinearGradient(
        colors: [liveGameEmerald, liveGameCyan],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let giftStarGlow = Color(red: 0.67, green: 0.55, blue: 1.0)
    static let giftStarGoldTop = Color(red: 1.0, green: 0.94, blue: 0.68)
    static let giftStarGoldBottom = Color(red: 0.96, green: 0.72, blue: 0.25)

    /// Adapter for server-provided dynamic hex colors (stories, store themes, avatar badges).
    static func serverColor(_ hex: String) -> Color {
        Color(hex: hex)
    }

    static func attachmentColor(forExtension ext: String) -> Color {
        switch ext.lowercased() {
        case "pdf": return Color(hex: "#EF4444")
        case "doc", "docx": return Color(hex: "#3B82F6")
        case "xls", "xlsx", "csv": return Color(hex: "#10B981")
        case "zip", "rar", "tar", "gz": return Color(hex: "#8B5CF6")
        case "mp3", "m4a", "wav", "aac": return Color(hex: "#F59E0B")
        default: return accentBright
        }
    }

    static func seasonalEffectPalette(for id: String) -> (systemName: String, primary: Color, secondary: Color)? {
        switch id {
        case "butterfly":
            return ("sparkles", Color(red: 0.25, green: 0.85, blue: 0.82), Color(red: 0.56, green: 0.42, blue: 0.98))
        case "aurora":
            return ("sparkles", Color(red: 0.22, green: 0.82, blue: 0.92), Color(red: 0.48, green: 0.36, blue: 0.96))
        case "meteor":
            return ("sparkle", Color(red: 1.0, green: 0.85, blue: 0.35), Color(red: 0.98, green: 0.50, blue: 0.28))
        case "lotus":
            return ("leaf.fill", Color(red: 0.98, green: 0.48, blue: 0.72), accentBright)
        default:
            return nil
        }
    }

    static func liveFilterOverlay(for id: String) -> Color? {
        switch id {
        case "clear": return Color.cyan.opacity(0.08)
        case "milk": return Color.white.opacity(0.12)
        case "peach": return Color.pink.opacity(0.12)
        case "warm": return Color.orange.opacity(0.12)
        case "cool": return Color.blue.opacity(0.12)
        case "film": return Color(red: 0.82, green: 0.72, blue: 0.52).opacity(0.16)
        case "mono": return Color.gray.opacity(0.25)
        case "noir": return Color.black.opacity(0.22)
        case "vivid": return Color.purple.opacity(0.08)
        case "sunset": return Color(red: 1.0, green: 0.42, blue: 0.22).opacity(0.16)
        case "candy": return Color(red: 1.0, green: 0.50, blue: 0.80).opacity(0.16)
        case "mint": return Color(red: 0.30, green: 0.90, blue: 0.70).opacity(0.12)
        case "dream": return Color(red: 0.80, green: 0.60, blue: 0.90).opacity(0.14)
        case "retro": return Color(red: 0.75, green: 0.65, blue: 0.35).opacity(0.16)
        case "city": return Color(red: 0.20, green: 0.40, blue: 0.65).opacity(0.14)
        case "cinema": return Color(red: 0.10, green: 0.30, blue: 0.45).opacity(0.15)
        case "rose": return Color(red: 0.92, green: 0.40, blue: 0.55).opacity(0.15)
        case "golden": return Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.15)
        case "ice": return Color(red: 0.60, green: 0.90, blue: 1.0).opacity(0.15)
        case "lavender": return Color(red: 0.75, green: 0.55, blue: 0.92).opacity(0.14)
        case "choco": return Color(red: 0.55, green: 0.32, blue: 0.12).opacity(0.16)
        case "polaroid": return Color(red: 0.92, green: 0.88, blue: 0.76).opacity(0.14)
        case "teal": return Color(red: 0.0, green: 0.50, blue: 0.50).opacity(0.15)
        default: return nil
        }
    }

    static func liveFilterSwatch(for id: String) -> Color {
        switch id {
        case "clear": return .cyan
        case "milk": return .white
        case "peach", "candy": return .pink
        case "warm", "sunset": return .orange
        case "cool", "city": return .blue
        case "film": return Color(red: 0.82, green: 0.72, blue: 0.52)
        case "noir": return .black
        case "vivid", "dream": return .purple
        case "mint": return .mint
        case "retro": return Color(red: 0.75, green: 0.65, blue: 0.35)
        case "cinema": return .indigo
        case "rose": return .red
        case "golden": return .yellow
        case "ice", "teal": return .teal
        case "lavender": return Color(red: 0.75, green: 0.55, blue: 0.92)
        case "choco": return Color(red: 0.55, green: 0.32, blue: 0.12)
        case "polaroid": return Color(red: 0.92, green: 0.88, blue: 0.76)
        default: return .gray
        }
    }

    static var surfaceBg: Color { background }
    static var cardBg: Color { surface }

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
        guard timestampMs > 0 else { return "Vừa xong" }
        let seconds = max(0, Int((Int64(Date().timeIntervalSince1970 * 1000) - timestampMs) / 1000))
        if seconds < 45 { return "Vừa xong" }
        if seconds < 3600 { return "\(seconds / 60) phút" }
        if seconds < 86400 { return "\(seconds / 3600) giờ" }
        return "\(seconds / 86400) ngày"
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

    func image(forKey key: String) -> UIImage? {
        guard !key.isEmpty else { return nil }
        return cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, forKey key: String) {
        guard !key.isEmpty else { return }
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
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
                            colors: [Color(hex: colorHex), KinnectTheme.accent],
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
                    .fill(KinnectTheme.online)
                    .frame(width: max(10, size * 0.25), height: max(10, size * 0.25))
                    .overlay(Circle().stroke(KinnectTheme.surface, lineWidth: 2))
            }
        }
        .task(id: avatarURL) {
            if let mem = ImageMemoryCache.shared.image(forKey: avatarURL) {
                loadedImage = mem
                return
            }
            guard !avatarURL.isEmpty else {
                loadedImage = nil
                return
            }
            if let data = await KinnectAPIClient.shared.fetchBinaryData(path: avatarURL),
               let uiImg = UIImage(data: data) {
                ImageMemoryCache.shared.store(uiImg, forKey: avatarURL)
                loadedImage = uiImg
            }
        }
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "K" }
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let last = parts.last?.first {
            return String([first, last]).uppercased()
        }
        return String(trimmed.prefix(1)).uppercased()
    }
}

struct KinnectRemoteImageView: View {
    let rawURL: String
    var contentMode: ContentMode = .fit
    var cornerRadius: CGFloat = 16
    var maxHeight: CGFloat = 320
    var fillWidthNaturalHeight: Bool = false

    @State private var image: UIImage?
    @State private var failed = false

    init(
        rawURL: String,
        contentMode: ContentMode = .fit,
        cornerRadius: CGFloat = 16,
        maxHeight: CGFloat = 320,
        fillWidthNaturalHeight: Bool = false
    ) {
        self.rawURL = rawURL
        self.contentMode = contentMode
        self.cornerRadius = cornerRadius
        self.maxHeight = maxHeight
        self.fillWidthNaturalHeight = fillWidthNaturalHeight
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
                if fillWidthNaturalHeight, img.size.width > 0, img.size.height > 0 {
                    let ratio = img.size.width / img.size.height
                    let clampedRatio = max(ratio, 0.72)
                    Color.clear
                        .aspectRatio(clampedRatio, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay(
                            Group {
                                if ratio >= 0.72 {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                } else {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                }
                            }
                        )
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(maxWidth: .infinity, maxHeight: maxHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            } else if failed {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(maxWidth: .infinity)
                    .frame(height: fillWidthNaturalHeight ? min(260, maxHeight) : min(180, maxHeight))
                    .overlay(ProgressView().tint(KinnectTheme.accentBright))
            }
        }
        .task(id: rawURL) {
            if let mem = ImageMemoryCache.shared.image(forKey: rawURL) {
                image = mem
                return
            }
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
    @State private var phase: CGFloat = -1.0

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 1.5)
                    .offset(x: phase * geo.size.width)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(
                    .linear(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.8
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

// MARK: - Standardized 4-State UI Components (Loading / Error / Empty / Refresh Error Banner)
struct KinnectErrorBanner: View {
    let message: String
    var retryTitle: String = "Thử lại"
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: KinnectTheme.spaceSM) {
            Image(systemName: "wifi.exclamationmark")
                .font(KinnectTheme.scaled(15, weight: .semibold))
                .foregroundColor(KinnectTheme.danger)
            Text(message)
                .font(.caption.weight(.medium))
                .foregroundColor(KinnectTheme.textPrimary)
                .lineLimit(2)
                .kinnectMultiline()
            Spacer(minLength: KinnectTheme.spaceSM)
            Button(retryTitle) {
                onRetry()
            }
            .font(.caption.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, KinnectTheme.spaceMD)
            .padding(.vertical, 6)
            .background(Capsule().fill(KinnectTheme.accent))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KinnectTheme.spaceMD)
        .padding(.vertical, KinnectTheme.spaceSM)
        .background(
            RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous)
                .fill(KinnectTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous)
                        .stroke(KinnectTheme.danger.opacity(0.45), lineWidth: 1)
                )
        )
    }
}

struct KinnectStateView: View {
    enum Mode {
        case loading(String)
        case error(title: String, message: String, retryTitle: String, onRetry: () -> Void)
        case empty(glyph: KinnectGlyph?, systemIcon: String?, title: String, subtitle: String?, actionTitle: String?, onAction: (() -> Void)?)
    }

    let mode: Mode
    var forceDarkSurface: Bool = false

    private var titleColor: Color {
        forceDarkSurface ? .white : KinnectTheme.textPrimary
    }

    private var subtitleColor: Color {
        forceDarkSurface ? Color.white.opacity(0.72) : KinnectTheme.textSecondary
    }

    var body: some View {
        VStack(spacing: KinnectTheme.spaceMD) {
            switch mode {
            case .loading(let message):
                ProgressView()
                    .tint(forceDarkSurface ? .white : KinnectTheme.accentBright)
                    .scaleEffect(1.1)
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(subtitleColor)

            case .error(let title, let message, let retryTitle, let onRetry):
                ZStack {
                    Circle()
                        .fill(KinnectTheme.danger.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(KinnectTheme.danger)
                }
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(titleColor)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(subtitleColor)
                    .multilineTextAlignment(.center)
                    .kinnectMultiline()
                    .padding(.horizontal, KinnectTheme.spaceXL)
                Button {
                    onRetry()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(KinnectTheme.scaled(13, weight: .bold))
                        Text(retryTitle)
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, KinnectTheme.spaceXL)
                    .padding(.vertical, KinnectTheme.spaceMD)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                }
                .buttonStyle(.plain)
                .padding(.top, KinnectTheme.spaceXS)

            case .empty(let glyph, let systemIcon, let title, let subtitle, let actionTitle, let onAction):
                if let glyph {
                    KinnectIcon(glyph: glyph, size: 44, tint: subtitleColor)
                } else if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(subtitleColor)
                }
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(titleColor)
                    .multilineTextAlignment(.center)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(subtitleColor)
                        .multilineTextAlignment(.center)
                        .kinnectMultiline()
                        .padding(.horizontal, KinnectTheme.spaceXL)
                }
                if let actionTitle, let onAction {
                    Button(actionTitle, action: onAction)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, KinnectTheme.spaceXL)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(KinnectTheme.accent))
                        .buttonStyle(.plain)
                        .padding(.top, KinnectTheme.spaceXS)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KinnectTheme.space2XL)
        .padding(.horizontal, KinnectTheme.spaceLG)
    }
}
