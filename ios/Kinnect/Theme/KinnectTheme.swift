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

    static let rose = Color(red: 0.93, green: 0.28, blue: 0.60)
    static let emerald = Color(red: 0.09, green: 0.64, blue: 0.45)
    static let online = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)

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
        self.isOnline = user.isActive
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
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: maxHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
