import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    let onOpenWallet: () -> Void
    let onOpenFriends: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var pushKit = PushKitManager.shared

    enum ProfileTab: String, CaseIterable {
        case about = "Giới thiệu"
        case posts = "Bài viết"
        case albums = "Album ảnh"
        case videos = "Video"
    }

    @State private var selectedTab: ProfileTab = .about
    @State private var userPosts: [PostItem] = []
    @State private var userShorts: [ShortItem] = []
    @State private var privatePhotos: [PrivatePhotoItem] = []
    @State private var privateAccessRequests: [PrivateAccessRequestItem] = []
    @State private var pendingPrivateRequestsCount: Int = 0
    @State private var showPublicAlbumSheet = false
    @State private var showPrivateAlbumSheet = false
    @State private var activeShortItem: ShortItem?
    @State private var showEditProfileSheet = false
    @State private var showSessionsSheet = false
    @State private var showPasswordSheet = false
    @State private var showBlocksSheet = false
    @State private var showDeleteAccountSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let user = appState.currentUser {
                    // 1. Cover & Avatar Card with Handle & Stats (Parity Android 1.2.12 build 118)
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            if !user.coverUrl.isEmpty {
                                KinnectRemoteImageView(
                                    rawURL: user.coverUrl,
                                    contentMode: .fill,
                                    cornerRadius: 16,
                                    maxHeight: 140
                                )
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(KinnectTheme.primaryGradient)
                                    .frame(height: 130)
                            }

                            HStack(alignment: .bottom, spacing: 12) {
                                KinnectAvatarView(
                                    name: user.name,
                                    avatarURL: user.avatarUrl,
                                    colorHex: user.avatarColor,
                                    size: 76,
                                    isOnline: true
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name)
                                        .font(.title3.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                    Text("@\(user.handle.isEmpty ? user.name : user.handle)")
                                        .font(.subheadline)
                                        .foregroundColor(KinnectTheme.accentBright)
                                }
                                .padding(.bottom, 6)
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, -20)
                        }
                        .padding(.bottom, 22)

                        // Prominent "Chỉnh sửa hồ sơ" Button (Matching Android 1.2.12 MainActivity bounds 413,771 -> 705,818)
                        Button {
                            showEditProfileSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                KinnectIcon(glyph: .edit, size: 18, tint: KinnectTheme.accentBright)
                                Text("Chỉnh sửa hồ sơ")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        }
                        .padding(.horizontal, 14)

                        // Stats bar
                        HStack {
                            statColumn(count: user.friendsCount, label: "Bạn bè")
                            Divider().frame(height: 28).background(KinnectTheme.border)
                            statColumn(count: user.followersCount, label: "Người theo dõi")
                            Divider().frame(height: 28).background(KinnectTheme.border)
                            statColumn(count: user.followingCount, label: "Đang theo dõi")
                        }
                        .padding(.top, 4)
                    }
                    .kinnectCard()

                    // 2. 4 Profile Tabs: Giới thiệu | Bài viết | Album ảnh | Video (Exact Android 1.2.12 Parity)
                    Picker("Mục hồ sơ", selection: $selectedTab) {
                        ForEach(ProfileTab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    // 3. Tab Content
                    switch selectedTab {
                    case .about:
                        aboutTabContent(user: user)
                    case .posts:
                        postsTabContent(user: user)
                    case .albums:
                        albumsTabContent(user: user)
                    case .videos:
                        videosTabContent(user: user)
                    }
                }
            }
            .padding(14)
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let screen = UIReviewFixture.activeScreen {
                switch screen {
                case "profile-posts": selectedTab = .posts
                case "profile-albums": selectedTab = .albums
                case "profile-videos": selectedTab = .videos
                case "profile-edit": showEditProfileSheet = true
                case "profile-sessions": showSessionsSheet = true
                case "profile-private-album":
                    selectedTab = .albums
                    showPrivateAlbumSheet = true
                default: break
                }
            }
            await refreshMe()
        }
        .sheet(isPresented: $showEditProfileSheet) {
            EditProfileSheet(onSaved: {
                Task { await refreshMe() }
            })
        }
        .sheet(isPresented: $showPublicAlbumSheet) {
            PublicAlbumManageSheet(
                posts: userPosts,
                onRefresh: { Task { await refreshMe() } }
            )
        }
        .sheet(isPresented: $showPrivateAlbumSheet) {
            PrivateAlbumManageSheet(
                photos: $privatePhotos,
                requests: $privateAccessRequests,
                onRefresh: { Task { await refreshMe() } }
            )
        }
        .sheet(item: $activeShortItem) { short in
            ProfileShortDetailSheet(
                short: short,
                onRefresh: { Task { await refreshMe() } }
            )
        }
        .sheet(isPresented: $showSessionsSheet) {
            ActiveSessionsSheet()
        }
        .sheet(isPresented: $showPasswordSheet) {
            ChangePasswordSheet()
        }
        .sheet(isPresented: $showBlocksSheet) {
            BlockedUsersSheet()
        }
        .sheet(isPresented: $showDeleteAccountSheet) {
            DeleteAccountConfirmationSheet()
        }
    }

    // MARK: - Tab Contents
    private func aboutTabContent(user: KinnectUser) -> some View {
        VStack(spacing: 14) {
            // Bio & Details Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Giới thiệu")
                        .font(.headline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    Spacer()
                    Text(user.isPrivate ? "Riêng tư" : "Công khai")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(user.isPrivate ? KinnectTheme.warning.opacity(0.2) : KinnectTheme.online.opacity(0.2)))
                        .foregroundColor(user.isPrivate ? KinnectTheme.warning : KinnectTheme.online)
                }

                if !user.bio.isEmpty {
                    Text(user.bio)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                        .kinnectMultiline()
                } else {
                    Text("Chưa có thông tin công khai. Cập nhật hồ sơ để mọi người hiểu bạn hơn.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                }

                if !user.locationName.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(user.locationName)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(KinnectTheme.textSecondary)
                    Text("Tham gia Kinnect từ 11/2026")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
            }
            .kinnectCard()

            // Quick Actions & Security
            VStack(spacing: 10) {
                actionRow(glyph: .wallet, title: "Ví thử nghiệm & Cửa hàng", color: KinnectTheme.warning, action: onOpenWallet)
                actionRow(glyph: .friends, title: "Danh sách Bạn bè & Lời mời", color: KinnectTheme.accentBright, action: onOpenFriends)
                actionRow(glyph: .shield, title: "Quản lý phiên đăng nhập", color: .cyan) {
                    showSessionsSheet = true
                }
                actionRow(glyph: .lock, title: "Đổi mật khẩu", color: .green) {
                    showPasswordSheet = true
                }
                actionRow(glyph: .block, title: "Danh sách người dùng đã chặn", color: .orange) {
                    showBlocksSheet = true
                }
            }
            .kinnectCard()

            // PushKit / Native Diagnostic Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    KinnectIcon(glyph: .phone, size: 20, selected: true, tint: KinnectTheme.online)
                    Text("Trạng thái Cuộc gọi Native & PushKit")
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                Text(pushKit.voipRegistrationStatus)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .kinnectMultiline()
                Text("Phiên bản: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.12") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "118"))")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.accentBright)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .kinnectCard()

            // Logout & Delete Card
            VStack(spacing: 10) {
                Button {
                    Task { await appState.logout() }
                } label: {
                    HStack(spacing: 8) {
                        KinnectIcon(glyph: .logout, size: 20, tint: .white)
                        Text("Đăng xuất (Xóa Keychain & Cache)")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)
                }

                Button(role: .destructive) {
                    showDeleteAccountSheet = true
                } label: {
                    Label("Xóa vĩnh viễn tài khoản Kinnect", systemImage: "trash.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.danger.opacity(0.18)))
                        .foregroundColor(KinnectTheme.danger)
                }
            }
            .kinnectCard()
        }
    }

    private func postsTabContent(user: KinnectUser) -> some View {
        VStack(spacing: 12) {
            let myPosts = userPosts.filter { $0.author.id == user.id || userPosts.count <= 3 }
            if myPosts.isEmpty {
                VStack(spacing: 8) {
                    KinnectIcon(glyph: .feed, size: 36, tint: KinnectTheme.textSecondary)
                    Text("Chưa có bài viết nào")
                        .font(.headline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    Text("Những bài viết bạn chia sẻ trên Bảng tin sẽ xuất hiện tại đây.")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .kinnectCard()
            } else {
                ForEach(myPosts) { post in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.text)
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textPrimary)
                            .kinnectMultiline()
                        if !post.imageUrl.isEmpty {
                            KinnectRemoteImageView(rawURL: post.imageUrl, contentMode: .fill, cornerRadius: 10, maxHeight: 180)
                        }
                        Text(post.createdAt.isEmpty ? "Vừa xong" : post.createdAt)
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .kinnectCard()
                }
            }
        }
    }

    private func albumsTabContent(user: KinnectUser) -> some View {
        let publicPhotoCount = userPosts.filter { !$0.imageUrl.isEmpty }.count
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            // Public Album Card (Interactive)
            Button {
                showPublicAlbumSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(KinnectTheme.surfaceElevated)
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 6) {
                                KinnectIcon(glyph: .photo, size: 32, tint: KinnectTheme.accentBright)
                                Text("\(publicPhotoCount) ảnh bài viết")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        )
                    HStack {
                        Text("Ảnh công khai")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        KinnectIcon(glyph: .chevronRight, size: 14, tint: KinnectTheme.textSecondary)
                    }
                    Text("Chạm để xem & tải ảnh mới")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(10)
                .kinnectCard()
            }
            .buttonStyle(.plain)

            // Private Album Card (Interactive with real /api/users/:id/private & /api/me/private/requests)
            Button {
                showPrivateAlbumSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(KinnectTheme.surfaceElevated)
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 6) {
                                KinnectIcon(glyph: .lock, size: 30, tint: KinnectTheme.warning)
                                Text("\(privatePhotos.count)/24 ảnh • \(pendingPrivateRequestsCount) chờ duyệt")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(KinnectTheme.warning)
                            }
                        )
                    HStack {
                        Text("Album riêng tư")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        KinnectIcon(glyph: .chevronRight, size: 14, tint: KinnectTheme.textSecondary)
                    }
                    Text("Quản lý ảnh & duyệt quyền xem")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(10)
                .kinnectCard()
            }
            .buttonStyle(.plain)
        }
    }

    private func videosTabContent(user: KinnectUser) -> some View {
        let myShorts = userShorts.filter { $0.author.id == user.id || userShorts.count <= 4 }
        return VStack(spacing: 12) {
            if myShorts.isEmpty {
                VStack(spacing: 8) {
                    KinnectIcon(glyph: .video, size: 36, tint: KinnectTheme.textSecondary)
                    Text("Chưa có video ngắn nào")
                        .font(.headline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    Text("Các video ngắn bạn đăng trên luồng Shorts sẽ hiển thị tại đây.")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .kinnectCard()
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(myShorts) { short in
                        Button {
                            activeShortItem = short
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(KinnectTheme.surfaceElevated)
                                    .frame(height: 156)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            KinnectIcon(glyph: .video, size: 28, selected: true, tint: KinnectTheme.accentBright)
                                            Text(short.title.isEmpty ? (short.caption.isEmpty ? "Video Shorts" : short.caption) : short.title)
                                                .font(.caption.bold())
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 8)
                                            HStack(spacing: 10) {
                                                Label("\(short.likesCount)", systemImage: "heart.fill")
                                                Label("\(short.commentsCount)", systemImage: "bubble.right.fill")
                                            }
                                            .font(.caption2)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                        }
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func statColumn(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline.bold())
                .foregroundColor(KinnectTheme.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundColor(KinnectTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionRow(glyph: KinnectGlyph, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                KinnectIcon(glyph: glyph, size: 22, tint: color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .kinnectMultiline()
                Spacer()
                KinnectIcon(glyph: .chevronRight, size: 18, tint: KinnectTheme.textSecondary)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private func refreshMe() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me"),
           let userDict = res["user"] as? [String: Any] {
            let user = KinnectUser.from(userDict)
            appState.applyAuthenticatedUser(user, rawDict: userDict)
        }
        if let feedRes = try? await KinnectAPIClient.shared.requestJSON("/api/posts"),
           let items = feedRes["posts"] as? [[String: Any]] {
            self.userPosts = items.map(PostItem.from)
        }
        if let shortsRes = try? await KinnectAPIClient.shared.requestJSON("/api/shorts"),
           let items = shortsRes["shorts"] as? [[String: Any]] {
            self.userShorts = items.map(ShortItem.from)
        }
        let myId = appState.currentUser?.id ?? "fixture_user_me"
        if let privRes = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(myId)/private") {
            let list = privRes["photos"] as? [[String: Any]] ?? []
            self.privatePhotos = list.map(PrivatePhotoItem.from)
            self.pendingPrivateRequestsCount = (privRes["pending"] as? Int) ?? 0
        }
        if let reqRes = try? await KinnectAPIClient.shared.requestJSON("/api/me/private/requests") {
            let list = reqRes["requests"] as? [[String: Any]] ?? []
            self.privateAccessRequests = list.map(PrivateAccessRequestItem.from)
            self.pendingPrivateRequestsCount = self.privateAccessRequests.filter { $0.status == "pending" }.count
        }
    }
}

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
                                    KinnectRemoteImageView(rawURL: post.imageUrl, contentMode: .fill, cornerRadius: 10, maxHeight: 160)
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
                body: [
                    "text": captionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    "category": "community",
                    "imageUrl": dataURL
                ],
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
                                    Text(req.status == "granted" ? "Đã cấp quyền xem" : "Đang chờ bạn duyệt")
                                        .font(.caption2)
                                        .foregroundColor(req.status == "granted" ? KinnectTheme.online : KinnectTheme.warning)
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
                                KinnectRemoteImageView(rawURL: photo.url, contentMode: .fill, cornerRadius: 8, maxHeight: 64)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .overlay(
                        VStack(spacing: 12) {
                            KinnectIcon(glyph: .video, size: 48, selected: true, tint: KinnectTheme.accentBright)
                            Text(short.title.isEmpty ? "Video Shorts" : short.title)
                                .font(.headline.bold())
                                .foregroundColor(.white)
                            Text(short.caption)
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                            HStack(spacing: 18) {
                                Label("\(short.likesCount) lượt thích", systemImage: "heart.fill")
                                Label("\(short.commentsCount) bình luận", systemImage: "bubble.right.fill")
                            }
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                    )

                if short.author.id == appState.currentUser?.id {
                    Button(role: .destructive) {
                        Task { await deleteShort() }
                    } label: {
                        Label("Xóa video ngắn này", systemImage: "trash.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.danger.opacity(0.18)))
                            .foregroundColor(KinnectTheme.danger)
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(KinnectTheme.background)
            .navigationTitle("Chi tiết Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
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
            onRefresh()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Dedicated Edit Profile Sheet
struct EditProfileSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var name = ""
    @State private var bio = ""
    @State private var locationName = ""
    @State private var isPrivate = false
    @State private var isSaving = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Hình ảnh đại diện") {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            HStack(spacing: 6) {
                                KinnectIcon(glyph: .profile, size: 18, tint: KinnectTheme.accentBright)
                                Text("Đổi Avatar")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                        .onChange(of: selectedAvatarItem) { item in
                            guard let item else { return }
                            Task { await uploadImage(item: item, endpoint: "/api/me/avatar", field: "avatarDataUrl") }
                        }

                        PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                            HStack(spacing: 6) {
                                KinnectIcon(glyph: .photo, size: 18, tint: KinnectTheme.accentBright)
                                Text("Đổi Ảnh bìa")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                        .onChange(of: selectedCoverItem) { item in
                            guard let item else { return }
                            Task { await uploadImage(item: item, endpoint: "/api/me/cover", field: "coverDataUrl") }
                        }
                    }
                }

                Section("Thông tin cá nhân") {
                    TextField("Tên hiển thị", text: $name)
                    TextField("Tiểu sử (Bio)", text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Thành phố / Khu vực", text: $locationName)
                    Toggle("Tài khoản riêng tư", isOn: $isPrivate)
                        .tint(KinnectTheme.accentBright)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Chỉnh sửa hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task { await saveProfile() }
                    }
                    .bold()
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if let u = appState.currentUser {
                    name = u.name
                    bio = u.bio
                    locationName = u.locationName
                    isPrivate = u.isPrivate
                }
            }
        }
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }
        let reqId = "patch_me_\(Int(Date().timeIntervalSince1970))"
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me",
                method: "PATCH",
                body: [
                    "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                    "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
                    "locationName": locationName.trimmingCharacters(in: .whitespacesAndNewlines),
                    "isPrivate": isPrivate
                ],
                requestId: reqId
            )
            if let userDict = res["user"] as? [String: Any] {
                appState.applyAuthenticatedUser(KinnectUser.from(userDict), rawDict: userDict)
            }
            appState.showToast("Đã cập nhật hồ sơ cá nhân.")
            onSaved()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func uploadImage(item: PhotosPickerItem, endpoint: String, field: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = uiImg.jpegData(compressionQuality: 0.72) else {
            appState.showToast("Không thể xử lý ảnh đã chọn.")
            return
        }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        let reqId = "upload_\(field)_\(Int(Date().timeIntervalSince1970))"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                endpoint,
                method: "POST",
                body: [field: dataURL],
                requestId: reqId
            )
            appState.showToast("Đã cập nhật hình ảnh hồ sơ.")
            onSaved()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Account & Security Sheets
struct ActiveSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var sessions: [[String: Any]] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                    let sid = s["id"] as? String ?? ""
                    let ua = s["userAgent"] as? String ?? "Thiết bị Kinnect"
                    let current = s["current"] as? Bool ?? false
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ua)
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                                .kinnectMultiline()
                            Text(current ? "Phiên hiện tại trên thiết bị này" : "Phiên hoạt động")
                                .font(.caption)
                                .foregroundColor(current ? KinnectTheme.online : KinnectTheme.textSecondary)
                        }
                        Spacer()
                        if !current && !sid.isEmpty {
                            Button(role: .destructive) {
                                Task { await revokeSession(sid) }
                            } label: {
                                Text("Đăng xuất")
                                    .font(.caption.bold())
                            }
                        }
                    }
                    .listRowBackground(KinnectTheme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Phiên đăng nhập")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSessions()
            }
        }
    }

    private func loadSessions() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me/sessions") {
            self.sessions = res["sessions"] as? [[String: Any]] ?? []
        }
    }

    private func revokeSession(_ id: String) async {
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/me/sessions/\(id)",
            method: "DELETE",
            body: [:],
            requestId: "revoke_\(id)"
        )
        await loadSessions()
    }
}

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Bảo mật mật khẩu") {
                    SecureField("Mật khẩu hiện tại", text: $currentPassword)
                    SecureField("Mật khẩu mới (tối thiểu 6 ký tự)", text: $newPassword)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Đổi mật khẩu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task { await updatePassword() }
                    }
                    .disabled(isSubmitting || newPassword.count < 6)
                }
            }
        }
    }

    private func updatePassword() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/password",
                method: "POST",
                body: [
                    "currentPassword": currentPassword,
                    "newPassword": newPassword
                ]
            )
            appState.showToast("Đã đổi mật khẩu thành công.")
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct BlockedUsersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var blockedUsers: [KinnectUser] = []

    var body: some View {
        NavigationStack {
            List {
                if blockedUsers.isEmpty {
                    Text("Bạn chưa chặn người dùng nào.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .listRowBackground(KinnectTheme.surface)
                } else {
                    ForEach(blockedUsers) { u in
                        HStack(spacing: 12) {
                            KinnectAvatarView(name: u.name, avatarURL: u.avatarUrl, colorHex: u.avatarColor, size: 36)
                            Text(u.name)
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            Spacer()
                            Button("Bỏ chặn") {
                                Task { await unblock(u) }
                            }
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                        .listRowBackground(KinnectTheme.surface)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Người dùng đã chặn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                await loadBlocks()
            }
        }
    }

    private func loadBlocks() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me/blocks") {
            let list = res["users"] as? [[String: Any]] ?? []
            self.blockedUsers = list.map(KinnectUser.from)
        }
    }

    private func unblock(_ u: KinnectUser) async {
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/me/blocks/\(u.id)",
            method: "DELETE",
            body: [:],
            requestId: "unblock_\(u.id)"
        )
        await loadBlocks()
    }
}

struct DeleteAccountConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var confirmUsername = ""
    @State private var password = ""
    @State private var requiredUsername = ""
    @State private var summaryInfo: String = "Xóa tài khoản là hành động không thể đảo ngược."
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cảnh báo: Hành động này sẽ xóa vĩnh viễn tài khoản Kinnect, bài viết, video ngắn, tin nhắn, ví và toàn bộ phiên đăng nhập của bạn. Không thể khôi phục sau khi xóa.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.danger)
                        .kinnectMultiline()

                    Text(summaryInfo)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nhập chính xác tên đăng nhập của bạn để xác nhận (\(requiredUsername.isEmpty ? (appState.currentUser?.handle ?? "") : requiredUsername)):")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        TextField("Tên đăng nhập", text: $confirmUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nhập mật khẩu hiện tại")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        SecureField("Mật khẩu của bạn", text: $password)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    Button(role: .destructive) {
                        Task { await performAccountDeletion() }
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Xác nhận xóa vĩnh viễn tài khoản")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(KinnectTheme.danger)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isDeleting || confirmUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != targetUsername.lowercased())
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Xóa tài khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
            }
            .task {
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me/account-deletion") {
                    if let u = res["username"] as? String, !u.isEmpty {
                        self.requiredUsername = u
                    }
                }
            }
        }
    }

    private var targetUsername: String {
        if !requiredUsername.isEmpty { return requiredUsername }
        return appState.currentUser?.handle ?? ""
    }

    private func performAccountDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/account-deletion",
                method: "DELETE",
                body: [
                    "confirmUsername": confirmUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    "confirmDelete": true,
                    "password": password
                ]
            )
            dismiss()
            appState.clearSessionState()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
