import SwiftUI
import UIKit

enum KinnectTheme {
    static let background = Color(red: 0.05, green: 0.04, blue: 0.11)       // #0D0A1C
    static let surface = Color(red: 0.10, green: 0.08, blue: 0.19)          // #191430
    static let surfaceElevated = Color(red: 0.15, green: 0.12, blue: 0.27)  // #261F45
    static let border = Color.white.opacity(0.10)

    static let accent = Color(red: 0.49, green: 0.23, blue: 0.93)           // #7C3AED
    static let accentBright = Color(red: 0.65, green: 0.33, blue: 0.97)     // #A855F7
    static let accentLight = Color(red: 0.58, green: 0.44, blue: 1.00)
    static let accentSoft = Color(red: 0.93, green: 0.91, blue: 1.00)

    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.72, green: 0.69, blue: 0.84)

    static let rose = Color(red: 0.93, green: 0.28, blue: 0.60)
    static let emerald = Color(red: 0.09, green: 0.64, blue: 0.45)
    static let online = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)

    static let surfaceBg = background
    static let cardBg = surface

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
    }

    init(user: KinnectUser, size: CGFloat = 44) {
        self.name = user.name
        self.avatarURL = user.avatarUrl
        self.colorHex = user.avatarColor
        self.size = size
        self.isOnline = user.isActive
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

            if isOnline {
                Circle()
                    .fill(KinnectTheme.online)
                    .frame(width: max(10, size * 0.25), height: max(10, size * 0.25))
                    .overlay(Circle().stroke(KinnectTheme.surface, lineWidth: 2))
            }
        }
        .task(id: avatarURL) {
            guard !avatarURL.isEmpty else {
                loadedImage = nil
                return
            }
            if let data = await KinnectAPIClient.shared.fetchBinaryData(path: avatarURL),
               let uiImg = UIImage(data: data) {
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
    }

    init(path: String, maxHeight: CGFloat = 320) {
        self.rawURL = path
        self.maxHeight = maxHeight
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
            guard !rawURL.isEmpty else {
                failed = true
                return
            }
            if let data = await KinnectAPIClient.shared.fetchBinaryData(path: rawURL),
               let uiImg = UIImage(data: data) {
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(KinnectTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(KinnectTheme.border, lineWidth: 1)
                    )
            )
    }
}
