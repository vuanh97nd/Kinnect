import SwiftUI
import UIKit

enum KinnectTheme {
    static let accent = Color(red: 0.43, green: 0.29, blue: 1.00)        // #6D4AFF
    static let accentLight = Color(red: 0.58, green: 0.44, blue: 1.00)   // #9470FF
    static let accentSoft = Color(red: 0.93, green: 0.91, blue: 1.00)    // #EDE8FF
    static let rose = Color(red: 0.93, green: 0.28, blue: 0.60)          // #EC4899
    static let emerald = Color(red: 0.09, green: 0.64, blue: 0.45)       // #16A374
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)         // #F59E0B
    static let danger = Color(red: 0.88, green: 0.19, blue: 0.34)        // #E13057
    static let surfaceBg = Color(UIColor.systemGroupedBackground)
    static let cardBg = Color(UIColor.secondarySystemGroupedBackground)

    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.43, green: 0.29, blue: 1.00), Color(red: 0.75, green: 0.22, blue: 0.83)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func relativeTime(from timestampMs: Int64) -> String {
        guard timestampMs > 0 else { return "Vừa xong" }
        let seconds = max(0, Int((Int64(Date().timeIntervalSince1970 * 1000) - timestampMs) / 1000))
        if seconds < 45 { return "Vừa xong" }
        if seconds < 3600 { return "\(seconds / 60) phút" }
        if seconds < 86400 { return "\(seconds / 3600) giờ" }
        return "\(seconds / 86400) ngày"
    }
}

struct KinnectAvatarView: View {
    let user: KinnectUser
    var size: CGFloat = 44
    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        KinnectTheme.brandGradient
                        Text(initials)
                            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))

            if user.isActive {
                Circle()
                    .fill(KinnectTheme.emerald)
                    .frame(width: max(10, size * 0.24), height: max(10, size * 0.24))
                    .overlay(Circle().stroke(Color(UIColor.systemBackground), lineWidth: 2))
            }
        }
        .task(id: user.avatarURL) {
            guard let path = user.avatarURL, !path.isEmpty else {
                loadedImage = nil
                return
            }
            if let data = await KinnectAPIClient.shared.fetchBinaryData(path: path),
               let uiImg = UIImage(data: data) {
                loadedImage = uiImg
            }
        }
    }

    private var initials: String {
        let trimmed = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "K" }
        let parts = trimmed.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let last = parts.last?.first {
            return String([first, last]).uppercased()
        }
        return String(trimmed.prefix(1)).uppercased()
    }
}

struct KinnectRemoteImageView: View {
    let path: String
    var maxHeight: CGFloat = 320
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if failed {
                EmptyView()
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(KinnectTheme.accentSoft)
                    .frame(height: 180)
                    .overlay(ProgressView().tint(KinnectTheme.accent))
            }
        }
        .task(id: path) {
            if let data = await KinnectAPIClient.shared.fetchBinaryData(path: path),
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
}
