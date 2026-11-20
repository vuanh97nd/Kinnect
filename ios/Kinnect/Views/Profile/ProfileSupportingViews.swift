import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Private Album & Public Album Models & Sheets

struct PrivatePhotoItem: Identifiable, Equatable {
    var id: String
    var url: String
    var createdAt: String

    static func from(_ dict: [String: Any]) -> PrivatePhotoItem {
        PrivatePhotoItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            url: (dict["url"] as? String) ?? "",
            createdAt: "\((dict["created"] as? Int) ?? 0)"
        )
    }
}

struct PrivateAccessRequestItem: Identifiable, Equatable {
    var id: String { user.id }
    var status: String // "pending" | "granted"
    var user: KinnectUser

    static func from(_ dict: [String: Any]) -> PrivateAccessRequestItem {
        let uDict = (dict["user"] as? [String: Any]) ?? [:]
        return PrivateAccessRequestItem(
            status: (dict["status"] as? String) ?? "pending",
            user: KinnectUser.from(uDict)
        )
    }
}

struct ProfileShortDetailSheet: View {
    let short: ShortItem
    var shorts: [ShortItem] = []
    var onRefresh: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        ShortsVideoView(initialItems: shorts.isEmpty ? [short] : shorts, initialShortID: short.id)
            .overlay(alignment: .topLeading) {
                Button { onRefresh?(); dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .padding(12).accessibilityLabel("Đóng video")
            }
    }

    private func deleteShort() async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts/\(short.id)",
                method: "DELETE",
                body: [:],
                requestId: "del_short_\(short.id)"
            )
            appState.showToast("Đã xóa video ngắn.")
            onRefresh?()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// Simple wrapping flow layout for chips on iOS
struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Connections Sheet (Followers / Following)

struct ConnectionsInfo: Identifiable {
    let id = UUID()
    let kind: String
    let title: String
}

// MARK: - Video Thumbnail Loader & Grid Item (Parity Android loadVideoPreview)

final class VideoThumbnailLoader: ObservableObject {
    @Published var image: UIImage? = nil
    private static let cache = NSCache<NSString, UIImage>()
    private var task: Task<Void, Never>? = nil

    func load(urlString: String) {
        guard let url = URL(string: KinnectAPIClient.shared.absoluteURL(urlString)) else { return }
        let key = "\(KinnectAPIClient.shared.currentAccountId):\(url.absoluteString)" as NSString
        if let cached = Self.cache.object(forKey: key) {
            self.image = cached
            return
        }

        task?.cancel()
        let origin = KinnectAPIClient.shared.mediaOrigin
        let cookie = KeychainStore.shared.cookieJarHeader(for: origin)
        let headers = url.host == URL(string: origin)?.host && !cookie.isEmpty ? ["Cookie": cookie] : [:]
        task = Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 576)

            do {
                let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                Self.cache.setObject(uiImage, forKey: key)
                await MainActor.run {
                    self.image = uiImage
                }
            } catch {
                // Ignore extraction failure
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

struct ShortThumbnailView: View {
    let short: ShortItem
    @StateObject private var loader = VideoThumbnailLoader()

    var body: some View {
        ZStack {
            // Android parity 0xff42355d -> 0xff1d1929 gradient
            LinearGradient(
                colors: [
                    Color(red: 0x42 / 255.0, green: 0x35 / 255.0, blue: 0x5d / 255.0),
                    Color(red: 0x1d / 255.0, green: 0x19 / 255.0, blue: 0x29 / 255.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let uiImage = loader.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }

            Image(systemName: "play.fill")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)

            VStack {
                Spacer()
                HStack {
                    if short.durationSec > 0 {
                        Text("\(Int(round(short.durationSec)))s")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(4)
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .aspectRatio(10.0 / 16.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if loader.image == nil && !short.videoUrl.isEmpty {
                loader.load(urlString: short.videoUrl)
            }
        }
    }
}

// MARK: - Profile Post Card (Full-width Card with Author Header, Actions & Comments)

struct ProfilePostCard: View {
    let post: PostItem
    let author: KinnectUser
    let isSelf: Bool
    let onDelete: () -> Void
    let onOpenComments: () -> Void

    @State private var isLiked: Bool
    @State private var likesCount: Int
    @State private var commentsCount: Int

    init(post: PostItem, author: KinnectUser, isSelf: Bool, onDelete: @escaping () -> Void, onOpenComments: @escaping () -> Void) {
        self.post = post
        self.author = author
        self.isSelf = isSelf
        self.onDelete = onDelete
        self.onOpenComments = onOpenComments
        _isLiked = State(initialValue: post.liked)
        _likesCount = State(initialValue: post.likesCount)
        _commentsCount = State(initialValue: post.commentsCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar, Name, Handle, Timestamp & Menu
            HStack(spacing: 10) {
                KinnectAvatarView(
                    name: author.name.isEmpty ? post.author.name : author.name,
                    avatarURL: author.avatarUrl.isEmpty ? post.author.avatarUrl : author.avatarUrl,
                    colorHex: author.avatarColor.isEmpty ? post.author.avatarColor : author.avatarColor,
                    size: 40,
                    isOnline: author.isActive && author.showActivity
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(author.name.isEmpty ? post.author.name : author.name)
                        .font(KinnectTheme.bodyBold)
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        let h = author.handle.isEmpty ? post.author.handle : author.handle
                        if !h.isEmpty {
                            Text("@\(h)")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textTertiary)
                        }
                        Text(formatRelativeDate(post.createdAt))
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }

                Spacer()

                if isSelf {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Xóa bài viết", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                }
            }

            // Post content (Full-width, leading alignment)
            if !post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(post.text)
                    .font(KinnectTheme.body)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Media Image
            if !post.imageUrl.isEmpty {
                AsyncImage(url: URL(string: KinnectAPIClient.shared.absoluteURL(post.imageUrl))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous))
                    case .failure:
                        Rectangle()
                            .fill(KinnectTheme.surfaceElevated)
                            .frame(height: 180)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 30))
                                    .foregroundColor(KinnectTheme.textSecondary)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous))
                    case .empty:
                        Rectangle()
                            .fill(KinnectTheme.surfaceElevated)
                            .frame(height: 180)
                            .overlay(ProgressView())
                            .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous))
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Action bar (Like & Comment)
            Divider()
                .background(KinnectTheme.border)
                .padding(.vertical, 2)

            HStack(spacing: 24) {
                Button(action: toggleLike) {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundColor(isLiked ? KinnectTheme.rose : KinnectTheme.textSecondary)

                        Text("\(likesCount)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isLiked ? KinnectTheme.rose : KinnectTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                Button(action: onOpenComments) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16))
                            .foregroundColor(KinnectTheme.textSecondary)

                        Text("\(commentsCount)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: KinnectTheme.radiusMD, style: .continuous)
                .fill(KinnectTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KinnectTheme.radiusMD, style: .continuous)
                .stroke(KinnectTheme.border, lineWidth: 1)
        )
    }

    private func toggleLike() {
        let willLike = !isLiked
        isLiked = willLike
        likesCount = max(0, likesCount + (willLike ? 1 : -1))
        Task {
            if willLike {
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/react",
                    method: "POST",
                    body: ["reaction": "love"]
                )
            } else {
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/like",
                    method: "DELETE",
                    body: [:]
                )
            }
        }
    }
}
