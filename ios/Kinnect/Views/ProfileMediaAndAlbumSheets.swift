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

struct PublicAlbumManageSheet: View {
    let posts: [PostItem]
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var captionText = ""
    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Đăng ảnh công khai mới") {
                    TextField("Chú thích cho ảnh...", text: $captionText)
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack(spacing: 8) {
                            KinnectIcon(glyph: .photo, size: 20, tint: KinnectTheme.accentBright)
                            Text(isUploading ? "Đang tải ảnh lên..." : "Chọn ảnh từ thư viện & Đăng")
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.accentBright)
                        }
                    }
                    .disabled(isUploading)
                    .onChange(of: selectedPhotoItem) { item in
                        guard let item else { return }
                        Task { await uploadPublicPhoto(item) }
                    }
                }

                Section("Danh sách bài viết & ảnh công khai (\(posts.count))") {
                    if posts.isEmpty {
                        Text("Chưa có ảnh công khai nào.")
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(posts) { post in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(post.text.isEmpty ? "Ảnh công khai" : post.text)
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textPrimary)
                                if !post.imageUrl.isEmpty {
                                    KinnectMediaTile(path: post.imageUrl, kind: post.mediaKind)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Ảnh công khai")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private func uploadPublicPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = uiImg.jpegData(compressionQuality: 0.75) else { return }
        isUploading = true
        defer { isUploading = false }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts",
                method: "POST",
                body: KinnectWriteBody.post(
                    text: captionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    mediaDataURL: dataURL
                ),
                requestId: "pub_photo_\(UUID().uuidString)"
            )
            captionText = ""
            appState.showToast("Đã đăng ảnh công khai mới!")
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct PrivateAlbumManageSheet: View {
    @Binding var photos: [PrivatePhotoItem]
    @Binding var requests: [PrivateAccessRequestItem]
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Tải ảnh lên Album riêng tư (\(photos.count)/24)") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack(spacing: 8) {
                            KinnectIcon(glyph: .lock, size: 20, tint: KinnectTheme.warning)
                            Text(isUploading ? "Đang mã hóa & tải lên..." : "Thêm ảnh riêng tư mới (< 4MB)")
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.warning)
                        }
                    }
                    .disabled(isUploading || photos.count >= 24)
                    .onChange(of: selectedItem) { item in
                        guard let item else { return }
                        Task { await uploadPrivatePhoto(item) }
                    }
                }

                Section("Yêu cầu & Quyền truy cập (\(requests.count))") {
                    if requests.isEmpty {
                        Text("Chưa có yêu cầu xem Album riêng tư nào.")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(requests) { req in
                            HStack(spacing: 10) {
                                KinnectAvatarView(
                                    name: req.user.name,
                                    avatarURL: req.user.avatarUrl,
                                    colorHex: req.user.avatarColor,
                                    size: 36
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.user.name)
                                        .font(.subheadline.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text(req.status == "granted" ? "Đã cấp quyền xem" : "Đang chờ bạn duyệt")
                                        .font(.caption2)
                                        .foregroundColor(req.status == "granted" ? KinnectTheme.online : KinnectTheme.warning)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if req.status == "pending" {
                                    Button("Duyệt") {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "grant") }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(KinnectTheme.accent)
                                    .controlSize(.small)

                                    Button("Từ chối", role: .destructive) {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "deny") }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("Thu hồi", role: .destructive) {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "revoke") }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("Ảnh trong Album riêng tư (\(photos.count))") {
                    if photos.isEmpty {
                        Text("Album riêng tư hiện chưa có ảnh.")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(photos) { photo in
                            HStack(alignment: .center, spacing: 12) {
                                // Fixed-size, clipped thumbnail so the image can never extend under the text column.
                                KinnectRemoteImageView(rawURL: photo.url, contentMode: .fill, cornerRadius: KinnectTheme.radiusXS, maxHeight: 64)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusXS, style: .continuous))
                                    .contentShape(Rectangle())
                                    .layoutPriority(0)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ảnh bảo mật")
                                        .font(.subheadline.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .lineLimit(1)
                                    Text("Chỉ người được duyệt mới xem được")
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                                Button(role: .destructive) {
                                    Task { await deletePrivatePhoto(photo.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(KinnectTheme.danger)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Xóa ảnh bảo mật")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Album riêng tư")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                if photos.isEmpty, let uid = appState.currentUser?.id {
                    if let privRes = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(uid)/private") {
                        let pList = privRes["photos"] as? [[String: Any]] ?? []
                        photos = pList.map(PrivatePhotoItem.from)
                    }
                }
                if requests.isEmpty {
                    if let reqRes = try? await KinnectAPIClient.shared.requestJSON("/api/me/private/requests") {
                        let rList = reqRes["requests"] as? [[String: Any]] ?? []
                        requests = rList.map(PrivateAccessRequestItem.from)
                    }
                }
            }
        }
    }

    private func uploadPrivatePhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = uiImg.jpegData(compressionQuality: 0.72) else { return }
        isUploading = true
        defer { isUploading = false }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/private-photos",
                method: "POST",
                body: ["data": dataURL],
                requestId: "priv_up_\(UUID().uuidString)"
            )
            if let list = res["photos"] as? [[String: Any]] {
                photos = list.map(PrivatePhotoItem.from)
            }
            appState.showToast("Đã thêm ảnh vào Album riêng tư.")
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deletePrivatePhoto(_ photoId: String) async {
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/private-photos/\(photoId)",
                method: "DELETE",
                body: [:],
                requestId: "priv_del_\(photoId)"
            )
            if let list = res["photos"] as? [[String: Any]] {
                photos = list.map(PrivatePhotoItem.from)
            }
            appState.showToast("Đã xóa ảnh khỏi Album riêng tư.")
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func handleAccessAction(viewerId: String, action: String) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/private/requests/\(viewerId)",
                method: "POST",
                body: ["action": action],
                requestId: "priv_act_\(viewerId)_\(action)"
            )
            let msg = action == "grant" ? "Đã cấp quyền xem Album riêng tư." : (action == "deny" ? "Đã từ chối yêu cầu." : "Đã thu hồi quyền xem.")
            appState.showToast(msg)
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
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
            .preferredColorScheme(.dark)
            .statusBarHidden(false)
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

// MARK: - Video Thumbnail Loader & Grid Item (Parity Android loadVideoPreview)

final class VideoThumbnailLoader: ObservableObject {
    @Published var image: UIImage? = nil
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        c.totalCostLimit = 32 * 1024 * 1024
        return c
    }()
    private var task: Task<Void, Never>? = nil

    static func clearCache() {
        cache.removeAllObjects()
    }

    func load(urlString: String) {
        let origin = KinnectAPIClient.shared.mediaOrigin
        guard let url = ServerConfig.url(for: urlString, origin: origin) else { return }
        let key = "\(KinnectAPIClient.shared.currentAccountId):\(url.absoluteString)" as NSString
        if let cached = Self.cache.object(forKey: key) {
            self.image = cached
            return
        }

        task?.cancel()
        let cookie = KeychainStore.shared.cookieJarHeader(for: origin)
        let headers = ServerConfig.matchesOrigin(url, origin: origin) && !cookie.isEmpty ? ["Cookie": cookie] : [:]
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
            KinnectTheme.profileDefaultBannerGradient

            if let uiImage = loader.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }

            Image(systemName: "play.fill")
                .font(KinnectTheme.scaled(22))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)

            VStack {
                Spacer()
                HStack {
                    if short.durationSec > 0 {
                        Text("\(Int(round(short.durationSec)))s")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6) // spacing-ok: badge thời lượng video
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
                            .font(KinnectTheme.scaled(16, weight: .semibold))
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
                            .font(KinnectTheme.scaled(16))
                            .foregroundColor(isLiked ? KinnectTheme.rose : KinnectTheme.textSecondary)

                        Text("\(likesCount)")
                            .font(KinnectTheme.scaled(13, weight: .medium))
                            .foregroundColor(isLiked ? KinnectTheme.rose : KinnectTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                Button(action: onOpenComments) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(KinnectTheme.scaled(16))
                            .foregroundColor(KinnectTheme.textSecondary)

                        Text("\(commentsCount)")
                            .font(KinnectTheme.scaled(13, weight: .medium))
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
