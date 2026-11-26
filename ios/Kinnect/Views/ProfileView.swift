import AuthenticationServices
import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UIKit

fileprivate func compressProfileImageToDataURL(
    _ rawData: Data,
    maxDimension: CGFloat = 1280,
    maxBytes: Int = 920 * 1024
) async -> String? {
    await Task.detached(priority: .userInitiated) {
        guard let original = UIImage(data: rawData) else { return nil }

        func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
            let size = image.size
            let longest = max(size.width, size.height)
            guard longest > maxSide, longest > 0 else { return image }
            let scale = maxSide / longest
            let targetSize = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }

        var currentImage = resized(original, maxSide: maxDimension)
        let qualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42, 0.32, 0.22]
        var bestData: Data? = nil

        for pass in 0..<3 {
            if pass > 0 {
                let nextSide = max(480, max(currentImage.size.width, currentImage.size.height) * 0.75)
                currentImage = resized(currentImage, maxSide: nextSide)
            }
            for q in qualities {
                if let jpeg = currentImage.jpegData(compressionQuality: q) {
                    bestData = jpeg
                    if jpeg.count <= maxBytes {
                        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                    }
                }
            }
        }

        guard let fallback = bestData, fallback.count <= maxBytes else { return nil }
        return "data:image/jpeg;base64,\(fallback.base64EncodedString())"
    }.value
}

fileprivate func evictProfileMeCache(accountId: String?) {
    let uid = (accountId?.isEmpty == false ? accountId! : KinnectAPIClient.shared.currentAccountId)
    guard !uid.isEmpty else { return }
    AccountCache.shared.evict(forKey: "json:/api/me", origin: KinnectAPIClient.shared.baseURL, accountId: uid)
    if KinnectAPIClient.shared.baseURL != ServerConfig.currentOrigin {
        AccountCache.shared.evict(forKey: "json:/api/me", origin: ServerConfig.currentOrigin, accountId: uid)
    }
}

struct ProfileView: View {
    var targetUser: KinnectUser? = nil
    var onBack: (() -> Void)? = nil
    var onOpenWallet: (() -> Void)? = nil
    var onOpenFriends: (() -> Void)? = nil
    var onOpenStore: (() -> Void)? = nil
    var initialTab: ProfileTab? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var pushKit = PushKitManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    private var isSelf: Bool {
        guard let target = targetUser else { return true }
        guard let me = appState.currentUser else { return false }
        return target.id == me.id
    }

    private var activeUser: KinnectUser? {
        if isSelf {
            return appState.currentUser
        }
        return detailedPeerUser ?? targetUser
    }

    enum ProfileTab: String, CaseIterable {
        case about = "Giới thiệu"
        case posts = "Bài viết"
        case albums = "Album ảnh"
        case videos = "Video"
    }

    @State private var selectedTab: ProfileTab = .about

    init(targetUser: KinnectUser? = nil, onBack: (() -> Void)? = nil, onOpenWallet: (() -> Void)? = nil, onOpenFriends: (() -> Void)? = nil, onOpenStore: (() -> Void)? = nil, initialTab: ProfileTab? = nil) {
        self.targetUser = targetUser
        self.onBack = onBack
        self.onOpenWallet = onOpenWallet
        self.onOpenFriends = onOpenFriends
        self.onOpenStore = onOpenStore
        if let initialTab = initialTab {
            _selectedTab = State(initialValue: initialTab)
        }
    }
    @State private var userPosts: [PostItem] = []
    @State private var userShorts: [ShortItem] = []
    @State private var privatePhotos: [PrivatePhotoItem] = []
    @State private var privateAccessRequests: [PrivateAccessRequestItem] = []
    @State private var pendingPrivateRequestsCount: Int = 0
    @State private var showPublicAlbumSheet = false
    @State private var showPrivateAlbumSheet = false
    @State private var activeShortItem: ShortItem?
    @State private var activeCommentsPost: PostItem? = nil
    @State private var selectedConnectionsInfo: ConnectionsInfo? = nil
    @State private var showEditProfileSheet = false
    @State private var showSessionsSheet = false
    @State private var showPasswordSheet = false
    @State private var showBlocksSheet = false
    @State private var showPrivacySheet = false
    @State private var showSupportSheet = false
    @State private var showDeleteAccountSheet = false

    @State private var selectedCoverItem: PhotosPickerItem? = nil
    @State private var selectedAvatarItem: PhotosPickerItem? = nil

    @State private var detailedPeerUser: KinnectUser? = nil
    @State private var peerFriendship: String = "none"
    @State private var peerPrivateStatus: String = "none"
    @State private var peerPrivatePhotos: [PrivatePhotoItem] = []
    @State private var peerPrivatePhotoCount: Int = 0
    @State private var showPeerPrivateAlbumSheet = false
    @State private var showPeerChat = false
    @State private var isFriendActionLoading = false
    @State private var pendingBlockPeer: KinnectUser? = nil
    @State private var pendingUnfriendPeer: KinnectUser? = nil
    @State private var pendingDeleteProfilePost: PostItem? = nil
    @State private var editingProfilePost: PostItem? = nil
    @State private var editingProfilePostText = ""
    @State private var audienceProfilePost: PostItem? = nil
    @State private var showProfileAudienceDialog = false
    @State private var hiddenProfilePostIds: Set<String> = []
    @State private var selectedProfileAuthor: KinnectUser? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Dedicated Pinned Header Bar (1:1 Android shell / accountHeader)
            profilePinnedHeader

            ScrollView {
                VStack(spacing: 16) {
                    if let user = activeUser {
                        // 1. Cover & Avatar Card with Handle, Bio & Stats (Parity Android 1.2.12 MainActivity.profileCard lines 2206-2278)
                        profileCard(user: user)

                        // 2. Profile Tabs (Android 1.2.12 Parity)
                        Picker(L10n.tr("Mục hồ sơ"), selection: $selectedTab) {
                            ForEach(ProfileTab.allCases, id: \.self) { t in
                                Text(L10n.tr(t.rawValue)).tag(t)
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
            if isSelf {
                #if DEBUG
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
                #endif
                await refreshMe()
            } else if let target = targetUser {
                await refreshPeer(target: target)
            }
        }
        .fullScreenCover(isPresented: $showPeerChat) {
            if let u = activeUser {
                NavigationStack {
                    DirectChatDetailView(peer: u)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPeerChat)
        .fullScreenCover(isPresented: $showEditProfileSheet) {
            EditProfileSheet(onSaved: {
                Task { await refreshMe() }
            })
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showEditProfileSheet)
        .fullScreenCover(isPresented: $showPublicAlbumSheet) {
            PublicAlbumManageSheet(
                posts: userPosts,
                isSelf: isSelf,
                onRefresh: {
                    Task {
                        if isSelf { await refreshMe() }
                        else if let target = targetUser { await refreshPeer(target: target) }
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPublicAlbumSheet)
        .fullScreenCover(isPresented: $showPrivateAlbumSheet) {
            PrivateAlbumManageSheet(
                photos: $privatePhotos,
                requests: $privateAccessRequests,
                onRefresh: { Task { await refreshMe() } }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPrivateAlbumSheet)
        .fullScreenCover(isPresented: $showPeerPrivateAlbumSheet) {
            if let u = activeUser {
                PeerPrivateAlbumSheet(
                    peer: u,
                    status: $peerPrivateStatus,
                    photos: $peerPrivatePhotos,
                    photoCount: $peerPrivatePhotoCount,
                    onRefresh: { Task { await refreshPeer(target: u) } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPeerPrivateAlbumSheet)
        .fullScreenCover(item: $activeShortItem) { short in
            ProfileShortDetailSheet(
                short: short,
                shorts: userShorts,
                onRefresh: {
                    Task {
                        if isSelf {
                            await refreshMe()
                        } else if let target = targetUser {
                            await refreshPeer(target: target)
                        }
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: activeShortItem)
        .fullScreenCover(isPresented: $showSessionsSheet) {
            ActiveSessionsSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSessionsSheet)
        .fullScreenCover(isPresented: $showPasswordSheet) {
            ChangePasswordSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPasswordSheet)
        .fullScreenCover(isPresented: $showBlocksSheet) {
            BlockedUsersSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showBlocksSheet)
        .fullScreenCover(isPresented: $showPrivacySheet) {
            PrivacySettingsSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPrivacySheet)
        .fullScreenCover(isPresented: $showSupportSheet) {
            SupportContactSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSupportSheet)
        .fullScreenCover(isPresented: $showDeleteAccountSheet) {
            DeleteAccountConfirmationSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showDeleteAccountSheet)
        .sheet(item: $activeCommentsPost) { post in
            PostCommentsSheet(post: post, onChanged: {
                Task {
                    if isSelf {
                        await refreshMe()
                    } else if let target = targetUser {
                        await refreshPeer(target: target)
                    }
                }
            })
        }
        .sheet(item: $selectedConnectionsInfo) { info in
            UserConnectionsSheet(
                userId: activeUser?.id ?? "",
                kind: info.kind,
                title: info.title
            )
        }
        .alert(
            L10n.tr("Chặn tài khoản?"),
            isPresented: Binding(
                get: { pendingBlockPeer != nil },
                set: { if !$0 { pendingBlockPeer = nil } }
            ),
            presenting: pendingBlockPeer
        ) { user in
            Button(L10n.tr("Chặn tài khoản"), role: .destructive) {
                pendingBlockPeer = nil
                Task {
                    await appState.blockUser(userId: user.id, userName: user.name)
                    dismiss()
                }
            }
            Button(L10n.tr("Hủy"), role: .cancel) {
                pendingBlockPeer = nil
            }
        } message: { user in
            Text("\(user.name) \(L10n.tr("sẽ không thể nhắn tin hoặc xem nội dung của bạn."))")
        }
        .alert(
            L10n.tr("Hủy kết bạn?"),
            isPresented: Binding(
                get: { pendingUnfriendPeer != nil },
                set: { if !$0 { pendingUnfriendPeer = nil } }
            ),
            presenting: pendingUnfriendPeer
        ) { user in
            Button(L10n.tr("Hủy kết bạn"), role: .destructive) {
                pendingUnfriendPeer = nil
                Task {
                    _ = try? await KinnectAPIClient.shared.requestJSON(
                        "/api/users/\(user.id)/friendship",
                        method: "DELETE",
                        body: [:],
                        requestId: "pfriend_del_\(user.id)_\(Int(Date().timeIntervalSince1970))"
                    )
                    peerFriendship = "none"
                    appState.showToast(L10n.tr("Đã hủy kết bạn"))
                    await refreshPeer(target: user)
                }
            }
            Button(L10n.tr("Đóng"), role: .cancel) {
                pendingUnfriendPeer = nil
            }
        } message: { user in
            Text("\(L10n.tr("Bạn có chắc muốn hủy kết bạn với")) \(user.name)?")
        }
        .alert(
            L10n.tr("Xóa bài viết?"),
            isPresented: Binding(
                get: { pendingDeleteProfilePost != nil },
                set: { if !$0 { pendingDeleteProfilePost = nil } }
            ),
            presenting: pendingDeleteProfilePost
        ) { post in
            Button(L10n.tr("Xóa bài viết"), role: .destructive) {
                pendingDeleteProfilePost = nil
                Task {
                    do {
                        _ = try await KinnectAPIClient.shared.requestJSON("/api/posts/\(post.id)", method: "DELETE")
                        userPosts.removeAll { $0.id == post.id }
                        appState.showToast(L10n.tr("Đã xóa bài viết"))
                    } catch {
                        appState.showToast(error.localizedDescription)
                    }
                }
            }
            Button(L10n.tr("Hủy"), role: .cancel) {
                pendingDeleteProfilePost = nil
            }
        } message: { _ in
            Text(L10n.tr("Bài viết đã xóa sẽ không thể khôi phục."))
        }
        .sheet(item: $editingProfilePost) { post in
            NavigationStack {
                VStack(spacing: 16) {
                    TextEditor(text: $editingProfilePostText)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .frame(minHeight: 180)
                    Spacer()
                }
                .padding(16)
                .background(KinnectTheme.background.ignoresSafeArea())
                .navigationTitle(L10n.tr("Chỉnh sửa bài viết"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.tr("Hủy")) { editingProfilePost = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.tr("Lưu")) {
                            Task { await saveEditedProfilePost(post) }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            L10n.tr("Ai có thể xem bài viết?"),
            isPresented: $showProfileAudienceDialog,
            titleVisibility: .visible
        ) {
            if let p = audienceProfilePost {
                Button(L10n.tr("Mọi thành viên (Công khai)")) {
                    Task { await changeProfilePostAudience(post: p, visibility: "public", title: L10n.tr("Mọi thành viên")) }
                }
                Button(L10n.tr("Người theo dõi")) {
                    Task { await changeProfilePostAudience(post: p, visibility: "followers", title: L10n.tr("Người theo dõi")) }
                }
                Button(L10n.tr("Hủy"), role: .cancel) {}
            }
        }
        .fullScreenCover(item: $selectedProfileAuthor) { author in
            ProfileView(targetUser: author)
        }
        .onChange(of: selectedCoverItem) { item in
            guard let item else { return }
            Task { await uploadProfileImage(item: item, endpoint: "/api/me/cover", field: "coverDataUrl") }
        }
        .onChange(of: selectedAvatarItem) { item in
            guard let item else { return }
            Task { await uploadProfileImage(item: item, endpoint: "/api/me/avatar", field: "avatarDataUrl") }
        }
    }
}

    // MARK: - Header & Visual Helpers (Parity Android shell & profileCard)
    private var profilePinnedHeader: some View {
        PinnedHeaderBar(
            title: isSelf ? L10n.tr("Trang cá nhân") : (activeUser?.name ?? L10n.tr("Hồ sơ")),
            onBack: onBack ?? { dismiss() },
            trailingActions: isSelf ? [
                PinnedHeaderBar.TrailingAction(
                    systemImage: "pencil",
                    accessibilityLabel: L10n.tr("Chỉnh sửa hồ sơ"),
                    action: { showEditProfileSheet = true }
                )
            ] : []
        )
    }

    @ViewBuilder
    private func profileCard(user: KinnectUser) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover Image (130dp height flush to edges with camera button for self)
            ZStack(alignment: .topTrailing) {
                if !user.coverUrl.isEmpty {
                    KinnectRemoteImageView(
                        rawURL: user.coverUrl,
                        contentMode: .fill,
                        cornerRadius: 0,
                        maxHeight: 130
                    )
                    .frame(maxWidth: .infinity, maxHeight: 130)
                    .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(KinnectTheme.primaryGradient)
                        .frame(maxWidth: .infinity, maxHeight: 130)
                }

                if isSelf {
                    PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .padding(8)
                    .accessibilityLabel(L10n.tr("Đổi ảnh bìa"))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130)

            // Identity Row (Parity Android lines 2230-2248: Avatar on Left overlapping cover by 28dp, Name & Handle on Right)
            HStack(alignment: .bottom, spacing: 14) {
                Group {
                    if isSelf {
                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            avatarBadge(user: user, size: 88)
                        }
                        .accessibilityLabel(L10n.tr("Đổi ảnh đại diện"))
                    } else {
                        avatarBadge(user: user, size: 88)
                    }
                }
                .offset(y: -28)
                .padding(.bottom, -28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)

                    Text("@\(user.handle.isEmpty ? user.name : user.handle)")
                        .font(.system(size: 13))
                        .foregroundColor(KinnectTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)

                Spacer()
            }
            .padding(.horizontal, 14)

            // Action Button Row (Parity Android lines 2249-2270: full-width 44dp pencil "Chỉnh sửa hồ sơ" or peer actions)
            Group {
                if isSelf {
                    Button {
                        showEditProfileSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                                .font(.subheadline.bold())
                            Text(L10n.tr("Chỉnh sửa hồ sơ"))
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(KinnectTheme.primaryGradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .padding(.top, 10)
                } else {
                    peerActionsRow(user: user)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 14)

            // Bio in Profile Card (Android parity lines 2272-2276: 13sp MUTED, lineSpacing 1.6f)
            if !user.bio.isEmpty {
                Text(user.bio)
                    .font(.system(size: 13))
                    .foregroundColor(KinnectTheme.textSecondary)
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            // Stats Bar: 3 soft cards (Android parity lines 4508-4529: bài viết, người theo dõi, đang theo dõi)
            HStack(spacing: 8) {
                statCard(count: user.postsCount, label: L10n.tr("bài viết")) {
                    selectedTab = .posts
                }
                statCard(count: user.followersCount, label: L10n.tr("người theo dõi")) {
                    selectedConnectionsInfo = ConnectionsInfo(kind: "followers", title: L10n.tr("Người theo dõi"))
                }
                statCard(count: user.followingCount, label: L10n.tr("đang theo dõi")) {
                    selectedConnectionsInfo = ConnectionsInfo(kind: "following", title: L10n.tr("Đang theo dõi"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: KinnectTheme.radiusMD, style: .continuous)
                .fill(KinnectTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: KinnectTheme.radiusMD, style: .continuous)
                        .stroke(KinnectTheme.border, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD, style: .continuous))
    }

    private func avatarBadge(user: KinnectUser, size: CGFloat) -> some View {
        KinnectAvatarView(
            name: user.name,
            avatarURL: user.avatarUrl,
            colorHex: user.avatarColor,
            size: size,
            isOnline: !isSelf && user.showActivity && (user.isActive || appState.onlineUserIds.contains(user.id))
        )
        .overlay(
            Circle().stroke(KinnectTheme.surface, lineWidth: 4)
        )
    }

    // MARK: - Tab Contents (100% Parity with Android MainActivity.profileAbout lines 2329-2346)
    private func isFieldVisible(key: String, user: KinnectUser) -> Bool {
        if isSelf { return true }
        if !user.identityPublic {
            let identityKeys = ["gender", "orientation", "communityRole", "pronouns", "relationshipRole"]
            if identityKeys.contains(key) { return false }
        }
        if let vis = user.profileVisibility[key], !vis {
            return false
        }
        return true
    }

    private func isProfileEmpty(user: KinnectUser) -> Bool {
        let hasBio = isFieldVisible(key: "bio", user: user) && !user.bio.isEmpty
        let hasAge = isFieldVisible(key: "age", user: user) && user.age > 0
        let displayCity = user.city.isEmpty ? user.locationName : user.city
        let hasCity = isFieldVisible(key: "city", user: user) && !displayCity.isEmpty
        let hasHeight = isFieldVisible(key: "height", user: user) && user.height > 0
        let hasWeight = isFieldVisible(key: "weight", user: user) && user.weight > 0
        let hasOcc = isFieldVisible(key: "occupation", user: user) && !user.occupation.isEmpty
        let hasSchool = isFieldVisible(key: "school", user: user) && !user.school.isEmpty
        let hasGender = isFieldVisible(key: "gender", user: user) && !user.gender.isEmpty
        let hasOrient = isFieldVisible(key: "orientation", user: user) && !user.orientation.isEmpty
        let hasRole = isFieldVisible(key: "communityRole", user: user) && !user.communityRole.isEmpty
        let hasPronouns = isFieldVisible(key: "pronouns", user: user) && !user.pronouns.isEmpty
        let hasRel = isFieldVisible(key: "relationshipRole", user: user) && !user.relationshipRole.isEmpty
        let hasLooking = isFieldVisible(key: "lookingFor", user: user) && !user.lookingFor.isEmpty
        let hasInterests = isFieldVisible(key: "interests", user: user) && !user.interests.isEmpty
        return !(hasBio || hasAge || hasCity || hasHeight || hasWeight || hasOcc || hasSchool || hasGender || hasOrient || hasRole || hasPronouns || hasRel || hasLooking || hasInterests)
    }

    private var emptyAboutBlock: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 40))
                .foregroundColor(KinnectTheme.textSecondary)
            Text(L10n.tr("Chưa có thông tin công khai"))
                .font(.headline)
                .foregroundColor(KinnectTheme.textPrimary)
            Text(L10n.tr(isSelf ? "Cập nhật hồ sơ để mọi người hiểu bạn hơn." : "Thành viên này chưa chia sẻ thông tin giới thiệu."))
                .font(.subheadline)
                .foregroundColor(KinnectTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func formattedJoinedDate(_ timestamp: Int64) -> String {
        guard timestamp > 0 else { return "" }
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/yyyy"
        return L10n.tr("Tham gia Kinnect từ ") + formatter.string(from: date)
    }

    @ViewBuilder
    private func aboutTabContent(user: KinnectUser) -> some View {
        VStack(spacing: 14) {
            // Bio & Details Card (Parity Android MainActivity.java:2329-2346 profileAbout)
            VStack(alignment: .leading, spacing: 0) {
                // Header: "Giới thiệu", globe icon, "Công khai"
                HStack {
                    Text(L10n.tr("Giới thiệu"))
                        .font(.headline.weight(.bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                    Spacer()
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Text(L10n.tr(user.isPrivate ? "Riêng tư" : "Công khai"))
                        .font(.caption2.bold())
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(.bottom, 12)

                // 0. Tiểu sử (Bio)
                if isFieldVisible(key: "bio", user: user) && !user.bio.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("Tiểu sử"))
                            .font(.system(size: 12))
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text(user.bio)
                            .font(.system(size: 14))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .kinnectMultiline()
                    }
                    .padding(.vertical, 8)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // Canonical Identity & Details List (matching Android lines 2338-2339)
                // 1. Tuổi
                if isFieldVisible(key: "age", user: user) && user.age > 0 {
                    profileDetailRow(label: L10n.tr("Tuổi"), value: "\(user.age) \(L10n.tr("tuổi"))")
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 2. Nơi sống
                let displayCity = user.city.isEmpty ? user.locationName : user.city
                if isFieldVisible(key: "city", user: user) && !displayCity.isEmpty {
                    profileDetailRow(label: L10n.tr("Nơi sống"), value: displayCity)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 3. Chiều cao
                if isFieldVisible(key: "height", user: user) && user.height > 0 {
                    profileDetailRow(label: L10n.tr("Chiều cao"), value: "\(user.height) cm")
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 4. Cân nặng
                if isFieldVisible(key: "weight", user: user) && user.weight > 0 {
                    profileDetailRow(label: L10n.tr("Cân nặng"), value: "\(user.weight) kg")
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 5. Nghề nghiệp
                if isFieldVisible(key: "occupation", user: user) && !user.occupation.isEmpty {
                    profileDetailRow(label: L10n.tr("Nghề nghiệp"), value: user.occupation)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 6. Trường học
                if isFieldVisible(key: "school", user: user) && !user.school.isEmpty {
                    profileDetailRow(label: L10n.tr("Trường học"), value: user.school)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // Giới tính & Bản sắc LGBT (Android parity: Bản dạng giới, Xu hướng, Vai trò cộng đồng, Cách xưng hô)
                // 7. Bản dạng giới
                if isFieldVisible(key: "gender", user: user) && !user.gender.isEmpty {
                    profileDetailRow(label: L10n.tr("Bản dạng giới"), value: localizedIdentityValue("gender", user.gender))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 8. Xu hướng
                if isFieldVisible(key: "orientation", user: user) && !user.orientation.isEmpty {
                    profileDetailRow(label: L10n.tr("Xu hướng"), value: localizedIdentityValue("orientation", user.orientation))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 9. Vai trò cộng đồng
                if isFieldVisible(key: "communityRole", user: user) && !user.communityRole.isEmpty {
                    profileDetailRow(label: L10n.tr("Vai trò cộng đồng"), value: localizedIdentityValue("communityRole", user.communityRole))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 10. Cách xưng hô
                if isFieldVisible(key: "pronouns", user: user) && !user.pronouns.isEmpty {
                    profileDetailRow(label: L10n.tr("Cách xưng hô"), value: localizedIdentityValue("pronouns", user.pronouns))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 11. Tình trạng quan hệ
                if isFieldVisible(key: "relationshipRole", user: user) && !user.relationshipRole.isEmpty {
                    profileDetailRow(label: L10n.tr("Tình trạng quan hệ"), value: localizedIdentityValue("relationshipRole", user.relationshipRole))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 12. Mong muốn
                if isFieldVisible(key: "lookingFor", user: user) && !user.lookingFor.isEmpty {
                    profileDetailRow(label: L10n.tr("Mong muốn"), value: user.lookingFor)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // Sở thích (Interests Tags)
                if isFieldVisible(key: "interests", user: user) && !user.interests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("Sở thích"))
                            .font(.system(size: 12))
                            .foregroundColor(KinnectTheme.textSecondary)
                        WrappingHStack(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(user.interests, id: \.self) { item in
                                Text(L10n.tr(item))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(KinnectTheme.accentBright)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(KinnectTheme.accentSoft)
                                    )
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                // Empty state if nothing filled or visible
                if isProfileEmpty(user: user) {
                    emptyAboutBlock
                }

                // Tham gia Kinnect từ MM/yyyy (Android parity line 2344)
                if user.joinedAt > 0 {
                    Text(formattedJoinedDate(user.joinedAt))
                        .font(.system(size: 12))
                        .foregroundColor(KinnectTheme.textSecondary)
                        .padding(.top, 16)
                        .padding(.bottom, 6)
                }
            }
            .kinnectCard()
        }
        .refreshable {
            if isSelf {
                await refreshMe()
            } else if let target = targetUser {
                await refreshPeer(target: target)
            }
        }
    }

    private func postsTabContent(user: KinnectUser) -> some View {
        VStack(spacing: 12) {
            let myPosts = userPosts.filter { $0.author.id == user.id && !hiddenProfilePostIds.contains($0.id) }
            if myPosts.isEmpty {
                VStack(spacing: 8) {
                    KinnectIcon(glyph: .feed, size: 36, tint: KinnectTheme.textSecondary)
                    Text(L10n.tr("Chưa có bài viết nào"))
                        .font(.headline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    Text(L10n.tr("Những bài viết bạn chia sẻ trên Bảng tin sẽ xuất hiện tại đây."))
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .kinnectCard()
            } else {
                ForEach(myPosts) { post in
                    PostCardView(
                        post: post,
                        currentUserId: appState.currentUser?.id ?? "",
                        isAuthorOnline: !isSelf && user.showActivity && (user.isActive || appState.onlineUserIds.contains(user.id)),
                        onOpenAuthorProfile: {
                            if post.author.id != user.id {
                                selectedProfileAuthor = post.author
                            }
                        },
                        onReact: { reaction in
                            Task {
                                do {
                                    let remove = post.liked && post.userReaction == reaction
                                    let res = try await KinnectAPIClient.shared.requestJSON(
                                        "/api/posts/\(post.id)/like",
                                        method: remove ? "DELETE" : "POST",
                                        body: remove ? [:] : ["reaction": reaction])
                                    if let idx = userPosts.firstIndex(where: { $0.id == post.id }) {
                                        let nextLiked = (res["liked"] as? Bool) ?? !remove
                                        let nextLikes = (res["likes"] as? Int)
                                            ?? (res["likesCount"] as? Int)
                                            ?? max(0, userPosts[idx].likesCount + (nextLiked ? (userPosts[idx].liked ? 0 : 1) : (userPosts[idx].liked ? -1 : 0)))
                                        let rawReaction = (res["myReaction"] as? String) ?? (res["userReaction"] as? String)
                                        userPosts[idx].liked = nextLiked
                                        userPosts[idx].likesCount = nextLikes
                                        userPosts[idx].userReaction = nextLiked ? ((rawReaction?.isEmpty == false) ? rawReaction! : reaction) : ""
                                        if let rawRx = res["reactions"] as? [String: Any] {
                                            var updated: [String: Int] = [:]
                                            for (k, v) in rawRx {
                                                if let n = v as? Int, n > 0 { updated[k] = n }
                                                else if let n = (v as? NSNumber)?.intValue, n > 0 { updated[k] = n }
                                            }
                                            userPosts[idx].reactions = updated
                                        }
                                    }
                                    if isSelf { await refreshMe() }
                                    else { await refreshPeer(target: user) }
                                } catch { appState.showToast(error.localizedDescription) }
                            }
                        },
                        onOpenComments: { activeCommentsPost = post },
                        onEdit: {
                            editingProfilePost = post
                            editingProfilePostText = post.text
                        },
                        onChangeAudience: {
                            audienceProfilePost = post
                            showProfileAudienceDialog = true
                        },
                        onHide: {
                            hiddenProfilePostIds.insert(post.id)
                            appState.showToast(L10n.tr("Đã ẩn bài viết."))
                        },
                        onDelete: {
                            pendingDeleteProfilePost = post
                        },
                        onReport: {
                            appState.activeReportContext = UGCReportContext(targetType: "post", targetId: post.id, targetUserId: post.author.id, targetTitle: "\(L10n.tr("Bài viết của")) \(post.author.name)")
                        },
                        onBookmark: {
                            Task { await toggleProfilePostBookmark(post) }
                        },
                        onRepost: {
                            Task { await repostProfilePost(post, quoteBody: "") }
                        },
                        onShareQuote: { quote in
                            Task { await repostProfilePost(post, quoteBody: quote) }
                        }
                    )
                }
            }
        }
    }

    private func saveEditedProfilePost(_ post: PostItem) async {
        do {
            let trimmed = editingProfilePostText.trimmingCharacters(in: .whitespacesAndNewlines)
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)",
                method: "PATCH",
                body: ["body": editingProfilePostText]
            )
            if let idx = userPosts.firstIndex(where: { $0.id == post.id }) {
                if let updatedDict = res["post"] as? [String: Any] {
                    userPosts[idx] = PostItem.from(updatedDict)
                } else {
                    userPosts[idx].text = trimmed
                }
            }
            editingProfilePost = nil
            appState.showToast(L10n.tr("Đã lưu bài viết!"))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func changeProfilePostAudience(post: PostItem, visibility: String, title: String) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)",
                method: "PATCH",
                body: ["visibility": visibility]
            )
            if let idx = userPosts.firstIndex(where: { $0.id == post.id }) {
                userPosts[idx].visibility = visibility
            }
            appState.showToast("\(L10n.tr("Đã đổi đối tượng xem thành")) \(title).")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func toggleProfilePostBookmark(_ post: PostItem) async {
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/bookmark",
                method: post.bookmarked ? "DELETE" : "POST",
                body: post.bookmarked ? nil : [:]
            )
            let saved = (res["bookmarked"] as? Bool) ?? !post.bookmarked
            if let idx = userPosts.firstIndex(where: { $0.id == post.id }) {
                userPosts[idx].bookmarked = saved
            }
            appState.showToast(L10n.tr(saved ? "Đã lưu bài viết." : "Đã bỏ lưu bài viết."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func repostProfilePost(_ post: PostItem, quoteBody: String) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/share",
                method: "POST",
                body: ["body": quoteBody.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
            appState.showToast(L10n.tr("Đã chia sẻ bài viết lên bảng tin."))
            if isSelf { await refreshMe() }
            else if let target = targetUser { await refreshPeer(target: target) }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func publicPhotoCount(from posts: [PostItem]) -> Int {
        var total = 0
        for post in posts {
            if !post.mediaItems.isEmpty {
                total += post.mediaItems.filter { item in
                    !item.url.isEmpty && !item.kind.lowercased().contains("video") && !item.url.lowercased().contains(".mp4")
                }.count
            } else if !post.imageUrl.isEmpty && !post.mediaKind.lowercased().contains("video") && !post.imageUrl.lowercased().contains(".mp4") {
                total += 1
            }
        }
        return total
    }

    private func albumsTabContent(user: KinnectUser) -> some View {
        let photoCount = publicPhotoCount(from: userPosts)
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12, alignment: .top),
                GridItem(.flexible(), spacing: 12, alignment: .top)
            ],
            spacing: 12
        ) {
            // Public Album Card (Interactive)
            Button {
                showPublicAlbumSheet = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: KinnectTheme.radiusMD)
                        .fill(KinnectTheme.surfaceElevated)
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 6) {
                                KinnectIcon(glyph: .photo, size: 32, tint: KinnectTheme.accentBright)
                                Text("\(photoCount) \(L10n.tr("ảnh bài viết"))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        )
                    HStack {
                        Text(L10n.tr("Ảnh công khai"))
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        KinnectIcon(glyph: .chevronRight, size: 14, tint: KinnectTheme.textSecondary)
                    }
                    Text(L10n.tr(isSelf ? "Chạm để xem & tải ảnh mới" : "Chạm để xem ảnh bài viết"))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .kinnectCard()
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .buttonStyle(.plain)

            // Private Album Card (Interactive with real /api/users/:id/private & /api/me/private/requests)
            Button {
                if isSelf {
                    showPrivateAlbumSheet = true
                } else {
                    showPeerPrivateAlbumSheet = true
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: KinnectTheme.radiusMD)
                        .fill(KinnectTheme.surfaceElevated)
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 6) {
                                KinnectIcon(glyph: .lock, size: 30, tint: KinnectTheme.warning)
                                if isSelf {
                                    Text("\(privatePhotos.count)/24 \(L10n.tr("ảnh")) • \(pendingPrivateRequestsCount) \(L10n.tr("chờ duyệt"))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(KinnectTheme.warning)
                                } else {
                                    let statusText = peerPrivateStatus == "granted" || peerPrivateStatus == "owner"
                                        ? "\(L10n.tr("Đã cấp quyền")) • \(peerPrivatePhotos.count) \(L10n.tr("ảnh"))"
                                        : (peerPrivateStatus == "pending" ? L10n.tr("Đang chờ duyệt") : "\(peerPrivatePhotoCount) \(L10n.tr("ảnh riêng tư"))")
                                    Text(statusText)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(peerPrivateStatus == "granted" ? KinnectTheme.online : KinnectTheme.warning)
                                }
                            }
                        )
                    HStack {
                        Text(L10n.tr("Album riêng tư"))
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        KinnectIcon(glyph: .chevronRight, size: 14, tint: KinnectTheme.textSecondary)
                    }
                    Text(L10n.tr(isSelf ? "Quản lý ảnh & duyệt quyền xem" : (peerPrivateStatus == "granted" ? "Chạm để xem ảnh được chia sẻ" : "Chạm để yêu cầu quyền xem")))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .kinnectCard()
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .buttonStyle(.plain)
        }
    }

    private func videosTabContent(user: KinnectUser) -> some View {
        let myShorts = userShorts.filter { $0.author.id == user.id }
        return VStack(spacing: 12) {
            if myShorts.isEmpty {
                VStack(spacing: 8) {
                    KinnectIcon(glyph: .video, size: 36, tint: KinnectTheme.textSecondary)
                    Text(L10n.tr("Chưa có video ngắn nào"))
                        .font(.headline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    Text(L10n.tr("Các video ngắn bạn đăng trên luồng Shorts sẽ hiển thị tại đây."))
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .kinnectCard()
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(myShorts) { short in
                        Button {
                            activeShortItem = short
                        } label: {
                            ShortThumbnailView(short: short)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func statCard(count: Int, label: String, onClick: (() -> Void)? = nil) -> some View {
        Button {
            onClick?()
        } label: {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16).fill(KinnectTheme.surfaceElevated))
        }
        .buttonStyle(.plain)
        .disabled(onClick == nil)
    }

    private func statColumn(count: Int, label: String) -> some View {
        statCard(count: count, label: label)
    }

    private func localizedIdentityValue(_ key: String, _ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        switch key {
        case "gender":
            switch trimmed.lowercased() {
            case "male", "nam": return L10n.tr("Nam")
            case "female", "nu", "nữ": return L10n.tr("Nữ")
            case "transgender_male", "trans_male", "nam chuyển giới": return L10n.tr("Nam chuyển giới")
            case "transgender_female", "trans_female", "nữ chuyển giới": return L10n.tr("Nữ chuyển giới")
            case "non_binary", "nonbinary", "phi nhị nguyên": return L10n.tr("Phi nhị nguyên")
            case "genderfluid", "linh hoạt giới": return L10n.tr("Linh hoạt giới")
            case "agender", "vô giới": return L10n.tr("Vô giới")
            case "questioning", "đang tìm hiểu": return L10n.tr("Đang tìm hiểu")
            case "other", "khác": return L10n.tr("Khác")
            default: return L10n.tr(trimmed)
            }
        case "orientation":
            switch trimmed.lowercased() {
            case "heterosexual", "straight", "dị tính": return L10n.tr("Dị tính")
            case "gay", "gay / đồng tính nam", "đồng tính nam": return L10n.tr("Gay / Đồng tính nam")
            case "lesbian", "lesbian / đồng tính nữ", "đồng tính nữ": return L10n.tr("Lesbian / Đồng tính nữ")
            case "bisexual", "song tính / bisexual", "song tính": return L10n.tr("Song tính / Bisexual")
            case "pansexual", "toàn tính / pansexual", "toàn tính": return L10n.tr("Toàn tính / Pansexual")
            case "asexual", "vô tính / asexual", "vô tính": return L10n.tr("Vô tính / Asexual")
            case "queer": return "Queer"
            case "demisexual", "á tính / demisexual", "á tính": return L10n.tr("Á tính / Demisexual")
            case "questioning", "đang tìm hiểu": return L10n.tr("Đang tìm hiểu")
            case "other", "khác": return L10n.tr("Khác")
            default: return L10n.tr(trimmed)
            }
        case "pronouns":
            switch trimmed.lowercased() {
            case "he", "him", "he/him", "anh": return L10n.tr("Anh")
            case "she", "her", "she/her", "chị": return L10n.tr("Chị")
            case "em": return L10n.tr("Em")
            case "you", "bạn": return L10n.tr("Bạn")
            case "they", "them", "they/them", "họ / they": return L10n.tr("Họ / They")
            default: return L10n.tr(trimmed)
            }
        case "relationshipRole":
            switch trimmed.lowercased() {
            case "single", "độc thân": return L10n.tr("Độc thân")
            case "dating", "đang tìm hiểu": return L10n.tr("Đang tìm hiểu")
            case "in_relationship", "đang trong mối quan hệ": return L10n.tr("Đang trong mối quan hệ")
            case "married", "đã kết hôn": return L10n.tr("Đã kết hôn")
            case "open_relationship", "mối quan hệ mở": return L10n.tr("Mối quan hệ mở")
            default: return L10n.tr(trimmed)
            }
        default:
            return L10n.tr(trimmed)
        }
    }

    private func profileDetailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(KinnectTheme.textSecondary)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(KinnectTheme.textPrimary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func uploadProfileImage(item: PhotosPickerItem, endpoint: String, field: String) async {
        defer {
            if endpoint.contains("cover") {
                selectedCoverItem = nil
            } else if endpoint.contains("avatar") {
                selectedAvatarItem = nil
            }
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let dataURL = await compressProfileImageToDataURL(data) else {
            appState.showToast(L10n.tr("Không thể xử lý ảnh đã chọn (tối đa ~920 KB sau khi nén)."))
            return
        }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                endpoint,
                method: "POST",
                body: ["data": dataURL],
                requestId: "upload_\(UUID().uuidString)"
            )
            evictProfileMeCache(accountId: appState.currentUser?.id)
            if let userDict = res["user"] as? [String: Any] {
                appState.updateCurrentUser(KinnectUser.from(userDict), rawDict: userDict)
            }
            appState.showToast(L10n.tr("Đã cập nhật ảnh thành công!"))
            await refreshMe()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func refreshMe() async {
        let initialId = appState.currentUser?.id ?? ""
        if !initialId.isEmpty {
            if userPosts.isEmpty,
               let cachedPosts = KinnectAPIClient.shared.cachedJSON(for: "/api/posts?user=\(initialId)"),
               let items = cachedPosts["posts"] as? [[String: Any]] {
                self.userPosts = items.map(PostItem.from)
            }
            if userShorts.isEmpty,
               let cachedShorts = KinnectAPIClient.shared.cachedJSON(for: "/api/shorts?user=\(initialId)"),
               let items = cachedShorts["shorts"] as? [[String: Any]] {
                self.userShorts = items.map(ShortItem.from)
            }
            if let cachedStats = KinnectAPIClient.shared.cachedJSON(for: "/api/users/\(initialId)/stats"),
               var current = appState.currentUser {
                if let p = cachedStats["posts"] as? Int { current.postsCount = p }
                if let fo = cachedStats["followers"] as? Int { current.followersCount = fo }
                if let fi = cachedStats["following"] as? Int { current.followingCount = fi }
                appState.currentUser = current
            }
        }

        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me"),
           let userDict = res["user"] as? [String: Any] {
            let user = KinnectUser.from(userDict)
            appState.updateCurrentUser(user, rawDict: userDict)
        }
        let myId = appState.currentUser?.id ?? ""
        guard !myId.isEmpty else { return }
        if let statsRes = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(myId)/stats") {
            if var current = appState.currentUser {
                if let p = statsRes["posts"] as? Int { current.postsCount = p }
                if let fo = statsRes["followers"] as? Int { current.followersCount = fo }
                if let fi = statsRes["following"] as? Int { current.followingCount = fi }
                appState.currentUser = current
            }
        }
        if let feedRes = try? await KinnectAPIClient.shared.requestJSON("/api/posts?user=\(myId)"),
           let items = feedRes["posts"] as? [[String: Any]] {
            self.userPosts = items.map(PostItem.from)
        }
        if let shortsRes = try? await KinnectAPIClient.shared.requestJSON("/api/shorts?user=\(myId)"),
           let items = shortsRes["shorts"] as? [[String: Any]] {
            self.userShorts = items.map(ShortItem.from)
        }
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

    @ViewBuilder
    private func peerFriendshipButton(user: KinnectUser) -> some View {
        let isFriends = (peerFriendship == "friends")
        let isOutgoing = (peerFriendship == "outgoing")
        let isIncoming = (peerFriendship == "incoming")
        let title: String = L10n.tr(isFriends ? "Bạn bè" : (isOutgoing ? "Đã gửi" : (isIncoming ? "Chấp nhận" : "Kết bạn")))
        let glyph: KinnectGlyph = isFriends ? .friends : (isOutgoing ? .refresh : .add)
        let fgColor: Color = isFriends ? KinnectTheme.online : (isOutgoing ? KinnectTheme.textPrimary : .white)

        Button {
            Task { await handlePeerFriendAction(user: user) }
        } label: {
            HStack(spacing: 6) {
                KinnectIcon(glyph: glyph, size: 18, tint: fgColor)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(fgColor)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Group {
                    if isFriends || isOutgoing {
                        RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated)
                    } else {
                        RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.primaryGradient)
                    }
                }
            )
        }
        .disabled(isFriendActionLoading)
    }

    @ViewBuilder
    private func peerMessageButton() -> some View {
        Button {
            showPeerChat = true
        } label: {
            HStack(spacing: 6) {
                KinnectIcon(glyph: .messages, size: 18, tint: KinnectTheme.accentBright)
                Text(L10n.tr("Nhắn tin"))
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.accentBright)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
        }
    }

    @ViewBuilder
    private func peerMoreMenu(user: KinnectUser) -> some View {
        Menu {
            Button {
                Task {
                    let endpoint = "/api/users/\(user.id)/follow"
                    _ = try? await KinnectAPIClient.shared.requestJSON(
                        endpoint,
                        method: user.isFollowing ? "DELETE" : "POST"
                    )
                    await refreshPeer(target: user)
                }
            } label: {
                Label(L10n.tr(user.isFollowing ? "Bỏ theo dõi" : "Theo dõi"), systemImage: "heart")
            }

            if peerFriendship == "incoming" {
                Button {
                    Task {
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/users/\(user.id)/friend-request/respond",
                            method: "POST",
                            body: ["action": "decline"]
                        )
                        peerFriendship = "none"
                        appState.showToast(L10n.tr("Đã từ chối lời mời"))
                    }
                } label: {
                    Label(L10n.tr("Từ chối lời mời"), systemImage: "xmark")
                }
            } else if peerFriendship == "friends" {
                Button(role: .destructive) {
                    pendingUnfriendPeer = user
                } label: {
                    Label(L10n.tr("Huỷ kết bạn"), systemImage: "person.badge.minus")
                }
            } else if peerFriendship == "outgoing" {
                Button {
                    Task {
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/users/\(user.id)/friend-request",
                            method: "DELETE"
                        )
                        peerFriendship = "none"
                        appState.showToast(L10n.tr("Đã huỷ lời mời"))
                    }
                } label: {
                    Label(L10n.tr("Huỷ lời mời"), systemImage: "xmark.circle")
                }
            }

            Button {
                appState.activeReportContext = UGCReportContext(
                    targetType: "user",
                    targetId: user.id,
                    targetUserId: user.id,
                    targetTitle: user.name
                )
            } label: {
                Label(L10n.tr("Báo cáo hồ sơ"), systemImage: "flag")
            }

            Button(role: .destructive) {
                pendingBlockPeer = user
            } label: {
                Label(L10n.tr("Chặn tài khoản"), systemImage: "nosign")
            }
        } label: {
            KinnectIcon(glyph: .more, size: 18, tint: KinnectTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(KinnectTheme.surfaceElevated))
        }
        .accessibilityLabel(L10n.tr("Tùy chọn hồ sơ"))
    }

    @ViewBuilder
    private func peerActionsRow(user: KinnectUser) -> some View {
        HStack(spacing: 8) {
            peerFriendshipButton(user: user)
            peerMessageButton()
            peerMoreMenu(user: user)
        }
        .padding(.horizontal, 14)
    }

    private func handlePeerFriendAction(user: KinnectUser) async {
        if peerFriendship == "friends" {
            pendingUnfriendPeer = user
            return
        }
        isFriendActionLoading = true
        defer { isFriendActionLoading = false }
        let reqId = "pfriend_\(user.id)_\(Int(Date().timeIntervalSince1970))"
        if peerFriendship == "outgoing" {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            peerFriendship = "none"
            appState.showToast(L10n.tr("Đã thu hồi lời mời kết bạn"))
        } else if peerFriendship == "incoming" {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request/respond",
                method: "POST",
                body: ["action": "accept"],
                requestId: reqId
            )
            peerFriendship = "friends"
            appState.showToast(L10n.tr("Đã chấp nhận kết bạn!"))
        } else {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request",
                method: "POST",
                body: [:],
                requestId: reqId
            )
            peerFriendship = "outgoing"
            appState.showToast(L10n.tr("Đã gửi lời mời kết bạn"))
        }
        await refreshPeer(target: user)
    }

    private func refreshPeer(target: KinnectUser) async {
        if detailedPeerUser == nil,
           let cachedUser = KinnectAPIClient.shared.cachedJSON(for: "/api/users/\(target.id)") {
            let userDict = (cachedUser["user"] as? [String: Any]) ?? cachedUser
            self.detailedPeerUser = KinnectUser.from(userDict)
            self.peerFriendship = (userDict["friendship"] as? String) ?? "none"
        }
        if let cachedStats = KinnectAPIClient.shared.cachedJSON(for: "/api/users/\(target.id)/stats") {
            var current = self.detailedPeerUser ?? target
            if let p = cachedStats["posts"] as? Int { current.postsCount = p }
            if let fo = cachedStats["followers"] as? Int { current.followersCount = fo }
            if let fi = cachedStats["following"] as? Int { current.followingCount = fi }
            self.detailedPeerUser = current
        }
        if userPosts.isEmpty,
           let cachedPosts = KinnectAPIClient.shared.cachedJSON(for: "/api/posts?user=\(target.id)"),
           let items = cachedPosts["posts"] as? [[String: Any]] {
            self.userPosts = items.map(PostItem.from)
        }
        if userShorts.isEmpty,
           let cachedShorts = KinnectAPIClient.shared.cachedJSON(for: "/api/shorts?user=\(target.id)"),
           let items = cachedShorts["shorts"] as? [[String: Any]] {
            self.userShorts = items.map(ShortItem.from)
        }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(target.id)") {
            let userDict = (res["user"] as? [String: Any]) ?? res
            let prev = self.detailedPeerUser
            var parsed = KinnectUser.from(userDict)
            if parsed.postsCount == 0, let prevPosts = prev?.postsCount, prevPosts > 0 { parsed.postsCount = prevPosts }
            if parsed.followersCount == 0, let prevFo = prev?.followersCount, prevFo > 0 { parsed.followersCount = prevFo }
            if parsed.followingCount == 0, let prevFi = prev?.followingCount, prevFi > 0 { parsed.followingCount = prevFi }
            self.detailedPeerUser = parsed
            self.peerFriendship = (userDict["friendship"] as? String) ?? "none"
        }
        if let statsRes = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(target.id)/stats") {
            var current = self.detailedPeerUser ?? target
            if let p = statsRes["posts"] as? Int { current.postsCount = p }
            if let fo = statsRes["followers"] as? Int { current.followersCount = fo }
            if let fi = statsRes["following"] as? Int { current.followingCount = fi }
            self.detailedPeerUser = current
        }
        if let feedRes = try? await KinnectAPIClient.shared.requestJSON("/api/posts?user=\(target.id)"),
           let items = feedRes["posts"] as? [[String: Any]] {
            self.userPosts = items.map(PostItem.from)
        }
        if let shortsRes = try? await KinnectAPIClient.shared.requestJSON("/api/shorts?user=\(target.id)"),
           let items = shortsRes["shorts"] as? [[String: Any]] {
            self.userShorts = items.map(ShortItem.from)
        }
        if let privRes = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(target.id)/private") {
            self.peerPrivateStatus = (privRes["status"] as? String) ?? "none"
            self.peerPrivatePhotoCount = (privRes["count"] as? Int) ?? 0
            let list = privRes["photos"] as? [[String: Any]] ?? []
            self.peerPrivatePhotos = list.map(PrivatePhotoItem.from)
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
    var isSelf: Bool = true
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var captionText = ""
    @State private var isUploading = false

    private struct PublicPhotoEntry: Identifiable {
        let id: String
        let postId: String
        let caption: String
        let url: String
    }

    private var imageEntries: [PublicPhotoEntry] {
        var result: [PublicPhotoEntry] = []
        for post in posts {
            if !post.mediaItems.isEmpty {
                for item in post.mediaItems {
                    let isVideo = item.kind.lowercased().contains("video") || item.url.lowercased().contains(".mp4")
                    if !item.url.isEmpty && !isVideo {
                        result.append(PublicPhotoEntry(
                            id: "\(post.id)_\(item.id)",
                            postId: post.id,
                            caption: post.text,
                            url: item.url
                        ))
                    }
                }
            } else {
                let isVideo = post.mediaKind.lowercased().contains("video") || post.imageUrl.lowercased().contains(".mp4")
                if !post.imageUrl.isEmpty && !isVideo {
                    result.append(PublicPhotoEntry(
                        id: post.id,
                        postId: post.id,
                        caption: post.text,
                        url: post.imageUrl
                    ))
                }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if isSelf {
                    Section(L10n.tr("Đăng ảnh công khai mới")) {
                        TextField(L10n.tr("Chú thích cho ảnh..."), text: $captionText)
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            HStack(spacing: 8) {
                                KinnectIcon(glyph: .photo, size: 20, tint: KinnectTheme.accentBright)
                                Text(L10n.tr(isUploading ? "Đang tải ảnh lên..." : "Chọn ảnh từ thư viện & Đăng"))
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
                }

                Section("\(L10n.tr("Danh sách ảnh công khai")) (\(imageEntries.count))") {
                    if imageEntries.isEmpty {
                        Text(L10n.tr("Chưa có ảnh công khai nào."))
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)
                            ],
                            spacing: 8
                        ) {
                            ForEach(imageEntries) { entry in
                                KinnectMediaTile(path: entry.url, kind: "image")
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Ảnh công khai"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
        }
    }

    private func uploadPublicPhoto(_ item: PhotosPickerItem) async {
        defer { selectedPhotoItem = nil }
        isUploading = true
        defer { isUploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let dataURL = await compressProfileImageToDataURL(data, maxDimension: 1920, maxBytes: 3_500_000) else {
            appState.showToast(L10n.tr("Không thể xử lý ảnh đã chọn (tối đa ~3.5 MB sau khi nén)."))
            return
        }
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
            appState.showToast(L10n.tr("Đã đăng ảnh công khai mới!"))
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct PeerPrivateAlbumSheet: View {
    let peer: KinnectUser
    @Binding var status: String
    @Binding var photos: [PrivatePhotoItem]
    @Binding var photoCount: Int
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isLoading = false
    @State private var previewPhoto: PrivatePhotoItem? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if status == "granted" || status == "owner" {
                        if photos.isEmpty {
                            VStack(spacing: 10) {
                                KinnectIcon(glyph: .photo, size: 36, tint: KinnectTheme.textSecondary)
                                Text(L10n.tr("Album riêng tư hiện chưa có ảnh."))
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            .padding(.vertical, 40)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(photos) { photo in
                                    Button {
                                        previewPhoto = photo
                                    } label: {
                                        KinnectRemoteImageView(rawURL: photo.url, contentMode: .fill, cornerRadius: KinnectTheme.radiusSM, maxHeight: 120)
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L10n.tr("Xem ảnh riêng tư"))
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 14) {
                            KinnectIcon(glyph: .lock, size: 42, tint: KinnectTheme.warning)
                            Text("\(L10n.tr("Album riêng tư của")) \(peer.name)")
                                .font(.headline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text(status == "pending"
                                 ? "\(L10n.tr("Bạn đã gửi yêu cầu xem Album riêng tư. Vui lòng chờ")) \(peer.name) \(L10n.tr("phê duyệt."))"
                                 : (photoCount > 0 ? "\(L10n.tr("Album có")) \(photoCount) \(L10n.tr("ảnh riêng tư. Gửi yêu cầu để được cấp quyền xem."))" : L10n.tr("Thành viên này chưa có ảnh riêng tư hoặc cần cấp quyền xem.")))
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            if status == "pending" {
                                Button(role: .destructive) {
                                    Task { await cancelAccessRequest() }
                                } label: {
                                    Text(L10n.tr(isLoading ? "Đang hủy..." : "Thu hồi yêu cầu xem"))
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                        .foregroundColor(KinnectTheme.danger)
                                }
                                .disabled(isLoading)
                            } else {
                                Button {
                                    Task { await requestAccess() }
                                } label: {
                                    Text(L10n.tr(isLoading ? "Đang gửi..." : "Gửi yêu cầu xem Album"))
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 11)
                                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                                        .foregroundColor(.white)
                                }
                                .disabled(isLoading)
                            }
                        }
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                        .kinnectCard()
                    }
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Album riêng tư"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
            .task {
                await reloadPeerAlbum()
            }
            .fullScreenCover(item: $previewPhoto) { photo in
                PrivatePhotoPreviewSheet(photo: photo)
            }
        }
    }

    private func reloadPeerAlbum() async {
        if let privRes = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(peer.id)/private") {
            status = (privRes["status"] as? String) ?? "none"
            photoCount = (privRes["count"] as? Int) ?? 0
            let list = privRes["photos"] as? [[String: Any]] ?? []
            photos = list.map(PrivatePhotoItem.from)
        }
    }

    private func requestAccess() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/private/request",
                method: "POST",
                body: [:],
                requestId: "priv_req_\(peer.id)_\(Int(Date().timeIntervalSince1970))"
            )
            status = (res["status"] as? String) ?? "pending"
            appState.showToast(L10n.tr("Đã gửi yêu cầu xem Album riêng tư."))
            await reloadPeerAlbum()
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func cancelAccessRequest() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/private/request",
                method: "DELETE",
                body: [:],
                requestId: "priv_cancel_\(peer.id)_\(Int(Date().timeIntervalSince1970))"
            )
            status = (res["status"] as? String) ?? "none"
            appState.showToast(L10n.tr("Đã thu hồi yêu cầu xem Album."))
            await reloadPeerAlbum()
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
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var previewPhoto: PrivatePhotoItem? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("\(L10n.tr("Tải ảnh lên Album riêng tư")) (\(photos.count)/24)") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack(spacing: 8) {
                            KinnectIcon(glyph: .lock, size: 20, tint: KinnectTheme.warning)
                            Text(L10n.tr(isUploading ? "Đang mã hóa & tải lên..." : "Thêm ảnh riêng tư mới (< 4MB)"))
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

                Section("\(L10n.tr("Yêu cầu & Quyền truy cập")) (\(requests.count))") {
                    if requests.isEmpty {
                        Text(L10n.tr("Chưa có yêu cầu xem Album riêng tư nào."))
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
                                    Text(L10n.tr(req.status == "granted" ? "Đã cấp quyền xem" : "Đang chờ bạn duyệt"))
                                        .font(.caption2)
                                        .foregroundColor(req.status == "granted" ? KinnectTheme.online : KinnectTheme.warning)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if req.status == "pending" {
                                    Button(L10n.tr("Duyệt")) {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "grant") }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(KinnectTheme.accent)
                                    .controlSize(.small)

                                    Button(L10n.tr("Từ chối"), role: .destructive) {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "deny") }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button(L10n.tr("Thu hồi"), role: .destructive) {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "revoke") }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("\(L10n.tr("Ảnh trong Album riêng tư")) (\(photos.count))") {
                    if photos.isEmpty {
                        Text(L10n.tr("Album riêng tư hiện chưa có ảnh."))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(photos) { photo in
                                ZStack(alignment: .topTrailing) {
                                    Button {
                                        previewPhoto = photo
                                    } label: {
                                        KinnectRemoteImageView(rawURL: photo.url, contentMode: .fill, cornerRadius: KinnectTheme.radiusSM, maxHeight: 110)
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusSM, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L10n.tr("Xem ảnh riêng tư"))

                                    Button(role: .destructive) {
                                        Task { await deletePrivatePhoto(photo.id) }
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 26, height: 26)
                                            .background(Circle().fill(Color.black.opacity(0.65)))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(5)
                                    .accessibilityLabel(L10n.tr("Xóa ảnh bảo mật"))
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Album riêng tư"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                if let uid = appState.currentUser?.id {
                    if let privRes = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(uid)/private") {
                        let pList = privRes["photos"] as? [[String: Any]] ?? []
                        photos = pList.map(PrivatePhotoItem.from)
                    }
                }
                if let reqRes = try? await KinnectAPIClient.shared.requestJSON("/api/me/private/requests") {
                    let rList = reqRes["requests"] as? [[String: Any]] ?? []
                    requests = rList.map(PrivateAccessRequestItem.from)
                }
            }
            .fullScreenCover(item: $previewPhoto) { photo in
                PrivatePhotoPreviewSheet(photo: photo)
            }
        }
    }

    private func uploadPrivatePhoto(_ item: PhotosPickerItem) async {
        defer { selectedItem = nil }
        isUploading = true
        defer { isUploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let dataURL = await compressProfileImageToDataURL(data, maxDimension: 1920, maxBytes: 3_500_000) else {
            appState.showToast(L10n.tr("Không thể xử lý ảnh đã chọn (tối đa ~3.5 MB sau khi nén)."))
            return
        }
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
            appState.showToast(L10n.tr("Đã thêm ảnh vào Album riêng tư."))
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
            appState.showToast(L10n.tr("Đã xóa ảnh khỏi Album riêng tư."))
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
            if let reqRes = try? await KinnectAPIClient.shared.requestJSON("/api/me/private/requests") {
                let rList = reqRes["requests"] as? [[String: Any]] ?? []
                requests = rList.map(PrivateAccessRequestItem.from)
            }
            let msg = L10n.tr(action == "grant" ? "Đã cấp quyền xem Album riêng tư." : (action == "deny" ? "Đã từ chối yêu cầu." : "Đã thu hồi quyền xem."))
            appState.showToast(msg)
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

private struct PrivatePhotoPreviewSheet: View {
    let photo: PrivatePhotoItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            KinnectRemoteImageView(
                rawURL: photo.url,
                contentMode: .fit,
                cornerRadius: 0,
                maxHeight: UIScreen.main.bounds.height
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .padding(16)
            .accessibilityLabel(L10n.tr("Đóng"))
        }
    }
}

struct ProfileShortDetailSheet: View {
    let short: ShortItem
    var shorts: [ShortItem] = []
    var initialOpenComments: Bool = false
    var onRefresh: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ShortsVideoView(
            initialItems: shorts.isEmpty ? [short] : shorts,
            initialShortID: short.id,
            initialOpenComments: initialOpenComments
        )
            .overlay(alignment: .topLeading) {
                Button { onRefresh?(); dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .padding(12).accessibilityLabel(L10n.tr("Đóng video"))
            }
    }
}

// MARK: - Dedicated Edit Profile Sheet (100% Android & Web Parity)
struct EditProfileSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    // Basic Info
    @State private var name = ""
    @State private var birthDate = ""
    @State private var birthDateValue = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var showDatePicker = false
    @State private var showPublicPreview = false

    // About & Interests
    @State private var bio = ""
    @State private var selectedInterests: [String] = []

    // Identity
    @State private var gender = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var orientation = ""
    @State private var communityRole = ""
    @State private var pronouns = ""

    // Connection & Life
    @State private var relationshipRole = ""
    @State private var selectedLookingFor: [String] = []
    @State private var city = ""
    @State private var occupation = ""
    @State private var school = ""
    @State private var identityPublic: Bool = AppState.shared.currentUser?.identityPublic ?? true

    // Field-level Public/Private Visibility (Globe 🌐 vs Lock 🔒)
    @State private var visibility: [String: Bool] = [:]

    // Media & State
    @State private var isSaving = false
    @State private var isLoading = false
    @State private var isLoaded = false
    @State private var loadFailed = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        if let u = AppState.shared.currentUser {
            _name = State(initialValue: u.name)
            _bio = State(initialValue: u.bio)
            _selectedInterests = State(initialValue: u.interests)
            _gender = State(initialValue: u.gender)
            _height = State(initialValue: u.height > 0 ? "\(u.height)" : "")
            _weight = State(initialValue: u.weight > 0 ? "\(u.weight)" : "")
            _orientation = State(initialValue: u.orientation)
            _communityRole = State(initialValue: u.communityRole)
            _pronouns = State(initialValue: u.pronouns)
            _relationshipRole = State(initialValue: u.relationshipRole)
            let lf = u.lookingFor.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            _selectedLookingFor = State(initialValue: lf)
            _city = State(initialValue: u.city.isEmpty ? u.locationName : u.city)
            _occupation = State(initialValue: u.occupation)
            _school = State(initialValue: u.school)
            _identityPublic = State(initialValue: u.identityPublic)
            if !u.profileVisibility.isEmpty {
                _visibility = State(initialValue: u.profileVisibility)
            }
        }
    }

    private let interestChoices = [
        "Nhiếp ảnh", "Du lịch", "Âm nhạc", "Đọc sách",
        "Thể thao", "Ẩm thực", "Phim ảnh", "Công nghệ",
        "Nghệ thuật", "Thiên nhiên", "Game", "Thú cưng"
    ]

    private let genderChoices = [
        "Nam", "Nữ", "Nam chuyển giới", "Nữ chuyển giới",
        "Phi nhị nguyên", "Linh hoạt giới", "Vô giới", "Đang tìm hiểu", "Khác"
    ]

    private let orientationChoices = [
        "Dị tính", "Gay / Đồng tính nam", "Lesbian / Đồng tính nữ",
        "Song tính / Bisexual", "Toàn tính / Pansexual", "Vô tính / Asexual",
        "Queer", "Á tính / Demisexual", "Đang tìm hiểu", "Khác"
    ]

    private let communityRoleChoices = [
        "Top", "Bottom", "Vers", "Vers Top", "Vers Bottom",
        "Side", "Femme", "Masc / Butch", "Androgynous", "Stem", "Đang tìm hiểu", "Khác"
    ]

    private let pronounChoices = ["Anh", "Chị", "Em", "Bạn", "Họ / They"]

    private let relationshipChoices = [
        "Độc thân", "Đang tìm hiểu", "Đang trong mối quan hệ", "Đã kết hôn", "Mối quan hệ mở"
    ]

    private let lookingForChoices = [
        "Kết bạn", "Trò chuyện", "Hẹn hò", "Mối quan hệ nghiêm túc", "Cùng sở thích"
    ]

    var body: some View {
        NavigationStack {
            Form {
                if loadFailed {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(KinnectTheme.danger)
                            Text(L10n.tr("Không thể tải hồ sơ hiện tại. Thử lại trước khi lưu để tránh ghi đè dữ liệu."))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.danger)
                            Spacer()
                            Button(L10n.tr("Thử lại")) {
                                Task { await loadMyProfile() }
                            }
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                    }
                }

                // 1. Photos Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                HStack(spacing: 6) {
                                    KinnectIcon(glyph: .profile, size: 18, tint: KinnectTheme.accentBright)
                                    Text(L10n.tr("Đổi Avatar"))
                                        .font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.accentBright)
                            }
                            .onChange(of: selectedAvatarItem) { item in
                                guard let item else { return }
                                Task { await uploadImage(item: item, endpoint: "/api/me/avatar", field: "avatarDataUrl") }
                            }

                            PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                                HStack(spacing: 6) {
                                    KinnectIcon(glyph: .photo, size: 18, tint: KinnectTheme.accentBright)
                                    Text(L10n.tr("Đổi Ảnh bìa"))
                                        .font(.caption.bold())
                                }
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.accentBright)
                            }
                            .onChange(of: selectedCoverItem) { item in
                                guard let item else { return }
                                Task { await uploadImage(item: item, endpoint: "/api/me/cover", field: "coverDataUrl") }
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.accentBright)
                            Text(L10n.tr("Chạm 🌐 / 🔒 để chọn thông tin công khai hoặc riêng tư."))
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }

                        Button {
                            showPublicPreview = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "eye.fill")
                                    .foregroundColor(KinnectTheme.accentBright)
                                Text(L10n.tr("Xem trước hồ sơ công khai"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(KinnectTheme.accentBright)
                                Spacer()
                                KinnectIcon(glyph: .chevronRight, size: 14, tint: KinnectTheme.textSecondary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L10n.tr("Hình ảnh đại diện"))
                }

                // 2. Thông tin cơ bản
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.tr("Tên hiển thị"))
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        TextField(L10n.tr("Nhập tên hiển thị..."), text: $name)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.tr("Ngày sinh"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "age", title: L10n.tr("Hiện tuổi"))
                        }
                        Button {
                            showDatePicker.toggle()
                        } label: {
                            HStack {
                                Text(birthDate.isEmpty ? L10n.tr("Chọn ngày sinh (YYYY-MM-DD)") : birthDate)
                                    .foregroundColor(birthDate.isEmpty ? KinnectTheme.textSecondary : KinnectTheme.textPrimary)
                                Spacer()
                                Image(systemName: "calendar")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        .buttonStyle(.plain)

                        if showDatePicker {
                            DatePicker(
                                L10n.tr("Ngày sinh"),
                                selection: $birthDateValue,
                                in: ...eighteenYearsAgo,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .onChange(of: birthDateValue) { newDate in
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd"
                                self.birthDate = formatter.string(from: newDate)
                            }
                        }
                        Text(L10n.tr("Ngày sinh chỉ bạn xem; biểu tượng 🌐 cho phép hiện tuổi trên hồ sơ."))
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                } header: {
                    Text(L10n.tr("Thông tin cơ bản"))
                }

                // 3. Giới thiệu và sở thích
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.tr("Giới thiệu bản thân (Bio)"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "bio", title: L10n.tr("Tiểu sử"))
                        }
                        TextField(L10n.tr("Chia sẻ vài dòng về bạn..."), text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.tr("Sở thích"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "interests", title: L10n.tr("Sở thích"))
                        }
                        chipFlow(choices: interestChoices, selected: $selectedInterests, max: 10)
                    }
                } header: {
                    Text(L10n.tr("Giới thiệu và sở thích"))
                }

                // 4. Bản thân và cách xưng hô (Identity)
                Section {
                    Toggle(isOn: $identityPublic) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("Hiển thị thông tin bản dạng công khai"))
                                .font(.subheadline.bold())
                            Text(L10n.tr("Khi tắt, nhóm bản dạng giới và xu hướng của bạn được giữ riêng tư."))
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .tint(KinnectTheme.accentBright)

                    pickerWithVisibility(title: L10n.tr("Bản dạng giới"), key: "gender", selection: $gender, choices: genderChoices)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L10n.tr("Chiều cao (cm)"))
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Spacer()
                                visibilityToggle(key: "height", title: L10n.tr("Chiều cao"))
                            }
                            TextField("175", text: $height)
                                .keyboardType(.numberPad)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L10n.tr("Cân nặng (kg)"))
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Spacer()
                                visibilityToggle(key: "weight", title: L10n.tr("Cân nặng"))
                            }
                            TextField("68", text: $weight)
                                .keyboardType(.numberPad)
                        }
                    }

                    pickerWithVisibility(title: L10n.tr("Xu hướng tính dục"), key: "orientation", selection: $orientation, choices: orientationChoices)
                    pickerWithVisibility(title: L10n.tr("Vai trò tự mô tả (tùy chọn)"), key: "communityRole", selection: $communityRole, choices: communityRoleChoices)
                    pickerWithVisibility(title: L10n.tr("Cách xưng hô"), key: "pronouns", selection: $pronouns, choices: pronounChoices)
                } header: {
                    Text(L10n.tr("Bản thân và cách xưng hô"))
                }

                // 5. Kết nối và cuộc sống
                Section {
                    pickerWithVisibility(title: L10n.tr("Tình trạng quan hệ"), key: "relationshipRole", selection: $relationshipRole, choices: relationshipChoices)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.tr("Mong muốn kết nối"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "lookingFor", title: L10n.tr("Mong muốn"))
                        }
                        chipFlow(choices: lookingForChoices, selected: $selectedLookingFor, max: 7)
                    }

                    textWithVisibility(title: L10n.tr("Nơi sống"), key: "city", text: $city, placeholder: L10n.tr("Hà Nội, TP. Hồ Chí Minh..."))
                    textWithVisibility(title: L10n.tr("Nghề nghiệp"), key: "occupation", text: $occupation, placeholder: L10n.tr("Lập trình viên, Nhiếp ảnh gia..."))
                    textWithVisibility(title: L10n.tr("Trường học"), key: "school", text: $school, placeholder: L10n.tr("Đại học Bách Khoa..."))
                } header: {
                    Text(L10n.tr("Kết nối và cuộc sống"))
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 36)
            }
            .navigationTitle(L10n.tr("Chỉnh sửa hồ sơ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Hủy")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Lưu thay đổi")) {
                        Task { await saveProfile() }
                    }
                    .bold()
                    .disabled(isSaving || isLoading || loadFailed || !isLoaded)
                }
            }
            .task {
                await loadMyProfile()
            }
            .sheet(isPresented: $showPublicPreview) {
                PublicProfilePreviewSheet(
                    name: name,
                    bio: bio,
                    age: calculatedPreviewAge,
                    city: city,
                    height: Int(height) ?? 0,
                    weight: Int(weight) ?? 0,
                    occupation: occupation,
                    school: school,
                    gender: gender,
                    orientation: orientation,
                    communityRole: communityRole,
                    pronouns: pronouns,
                    relationshipRole: relationshipRole,
                    lookingFor: selectedLookingFor.joined(separator: ", "),
                    interests: selectedInterests,
                    identityPublic: identityPublic,
                    visibility: visibility
                )
            }
        }
    }

    private var calculatedPreviewAge: Int {
        if !birthDate.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let dob = formatter.date(from: birthDate) {
                let years = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
                if years >= 18 { return years }
            }
        }
        return appState.currentUser?.age ?? 0
    }

    private var eighteenYearsAgo: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }

    @ViewBuilder
    private func visibilityToggle(key: String, title: String) -> some View {
        let isPublic = visibility[key] ?? true
        Button {
            visibility[key] = !isPublic
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isPublic ? "globe" : "lock.fill")
                    .font(.caption2)
                Text(L10n.tr(isPublic ? "Công khai" : "Chỉ tôi"))
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(isPublic ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(KinnectTheme.surfaceElevated))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(L10n.tr(isPublic ? "Công khai" : "Ẩn")) \(title)")
    }

    @ViewBuilder
    private func chipFlow(choices: [String], selected: Binding<[String]>, max: Int) -> some View {
        WrappingHStack(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(choices, id: \.self) { choice in
                let isSel = selected.wrappedValue.contains(choice)
                Button {
                    if isSel {
                        selected.wrappedValue.removeAll { $0 == choice }
                    } else {
                        if selected.wrappedValue.count < max {
                            selected.wrappedValue.append(choice)
                        } else {
                            appState.showToast("\(L10n.tr("Tối đa")) \(max) \(L10n.tr("lựa chọn."))")
                        }
                    }
                } label: {
                    Text(L10n.tr(choice))
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSel ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                        )
                        .foregroundColor(isSel ? .white : KinnectTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func pickerWithVisibility(title: String, key: String, selection: Binding<String>, choices: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textSecondary)
                Spacer()
                visibilityToggle(key: key, title: title)
            }
            Picker(title, selection: selection) {
                Text(L10n.tr("Không muốn tiết lộ")).tag("")
                ForEach(choices, id: \.self) { c in
                    Text(L10n.tr(c)).tag(c)
                }
            }
            .pickerStyle(.menu)
            .tint(KinnectTheme.accentBright)
        }
    }

    @ViewBuilder
    private func textWithVisibility(title: String, key: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textSecondary)
                Spacer()
                visibilityToggle(key: key, title: title)
            }
            TextField(placeholder, text: text)
        }
    }

    private func loadMyProfile() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        #if DEBUG
        if UIReviewFixture.isEnabled {
            isLoaded = true
            return
        }
        #endif
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/me")
            if let me = res["user"] as? [String: Any] {
                self.name = me["name"] as? String ?? ""
                self.bio = me["bio"] as? String ?? ""
                self.birthDate = me["birthDate"] as? String ?? ""
                if !self.birthDate.isEmpty {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    if let d = formatter.date(from: self.birthDate) {
                        self.birthDateValue = d
                    }
                }
                if let ints = me["interests"] as? [String] {
                    self.selectedInterests = ints
                } else if let intStr = me["interests"] as? String {
                    self.selectedInterests = intStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                self.gender = me["gender"] as? String ?? ""
                if let h = me["height"] as? Int, h > 0 { self.height = "\(h)" }
                if let w = me["weight"] as? Int, w > 0 { self.weight = "\(w)" }
                self.orientation = me["orientation"] as? String ?? ""
                self.communityRole = me["communityRole"] as? String ?? ""
                self.pronouns = me["pronouns"] as? String ?? ""
                self.relationshipRole = me["relationshipRole"] as? String ?? ""
                if let lfs = me["lookingFor"] as? [String] {
                    self.selectedLookingFor = lfs
                } else if let lfStr = me["lookingFor"] as? String {
                    self.selectedLookingFor = lfStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                self.city = (me["city"] as? String) ?? (me["locationName"] as? String) ?? ""
                self.occupation = me["occupation"] as? String ?? ""
                self.school = me["school"] as? String ?? ""
                self.identityPublic = (me["identityPublic"] as? Bool) ?? self.identityPublic

                if let vis = me["profileVisibility"] as? [String: Bool] {
                    self.visibility = vis
                } else {
                    for k in ["bio", "age", "gender", "orientation", "communityRole", "pronouns", "relationshipRole", "lookingFor", "city", "interests", "height", "weight", "occupation", "school"] {
                        self.visibility[k] = true
                    }
                }
                self.isLoaded = true
                self.loadFailed = false
            } else {
                self.loadFailed = true
                self.isLoaded = false
            }
        } catch {
            self.loadFailed = true
            self.isLoaded = false
            appState.showToast("\(L10n.tr("Không tải được hồ sơ:")) \(error.localizedDescription)")
        }
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }
        let reqId = "patch_me_\(Int(Date().timeIntervalSince1970))"

        var payload: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "birthDate": birthDate.trimmingCharacters(in: .whitespacesAndNewlines),
            "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
            "interests": selectedInterests,
            "gender": gender,
            "orientation": orientation,
            "communityRole": communityRole,
            "pronouns": pronouns,
            "relationshipRole": relationshipRole,
            "lookingFor": selectedLookingFor.joined(separator: ", "),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "locationName": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "occupation": occupation.trimmingCharacters(in: .whitespacesAndNewlines),
            "school": school.trimmingCharacters(in: .whitespacesAndNewlines),
            "identityPublic": identityPublic,
            "profileVisibility": visibility
        ]

        if let h = Int(height.trimmingCharacters(in: .whitespacesAndNewlines)), h > 0 {
            payload["height"] = h
        } else {
            payload["height"] = NSNull()
        }
        if let w = Int(weight.trimmingCharacters(in: .whitespacesAndNewlines)), w > 0 {
            payload["weight"] = w
        } else {
            payload["weight"] = NSNull()
        }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me",
                method: "PATCH",
                body: payload,
                requestId: reqId
            )
            if let userDict = res["user"] as? [String: Any] {
                appState.updateCurrentUser(KinnectUser.from(userDict), rawDict: userDict)
            }
            appState.showToast(L10n.tr("Đã cập nhật hồ sơ cá nhân hoàn chỉnh."))
            onSaved()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func uploadImage(item: PhotosPickerItem, endpoint: String, field: String) async {
        defer {
            if endpoint.contains("cover") {
                selectedCoverItem = nil
            } else if endpoint.contains("avatar") {
                selectedAvatarItem = nil
            }
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let dataURL = await compressProfileImageToDataURL(data) else {
            appState.showToast(L10n.tr("Không thể xử lý ảnh đã chọn (tối đa ~920 KB sau khi nén)."))
            return
        }
        let reqId = "upload_\(field)_\(Int(Date().timeIntervalSince1970))"
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                endpoint,
                method: "POST",
                body: ["data": dataURL],
                requestId: reqId
            )
            evictProfileMeCache(accountId: appState.currentUser?.id)
            if let userDict = res["user"] as? [String: Any] {
                appState.updateCurrentUser(KinnectUser.from(userDict), rawDict: userDict)
            }
            appState.showToast(L10n.tr("Đã cập nhật hình ảnh hồ sơ."))
            onSaved()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// Simple wrapping flow layout for chips on iOS
private struct WrappingHStack: Layout {
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

private struct PublicProfilePreviewSheet: View {
    let name: String
    let bio: String
    let age: Int
    let city: String
    let height: Int
    let weight: Int
    let occupation: String
    let school: String
    let gender: String
    let orientation: String
    let communityRole: String
    let pronouns: String
    let relationshipRole: String
    let lookingFor: String
    let interests: [String]
    let identityPublic: Bool
    let visibility: [String: Bool]

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    private func canShow(_ key: String) -> Bool {
        if !identityPublic && ["gender", "orientation", "communityRole", "pronouns", "relationshipRole"].contains(key) {
            return false
        }
        return visibility[key] ?? true
    }

    private var visibleEntries: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if canShow("bio") && !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append((L10n.tr("Tiểu sử"), bio))
        }
        if canShow("age") && age > 0 {
            rows.append((L10n.tr("Tuổi"), "\(age) \(L10n.tr("tuổi"))"))
        }
        if canShow("city") && !city.isEmpty {
            rows.append((L10n.tr("Nơi sống"), city))
        }
        if canShow("height") && height > 0 {
            rows.append((L10n.tr("Chiều cao"), "\(height) cm"))
        }
        if canShow("weight") && weight > 0 {
            rows.append((L10n.tr("Cân nặng"), "\(weight) kg"))
        }
        if canShow("occupation") && !occupation.isEmpty {
            rows.append((L10n.tr("Nghề nghiệp"), occupation))
        }
        if canShow("school") && !school.isEmpty {
            rows.append((L10n.tr("Trường học"), school))
        }
        if canShow("gender") && !gender.isEmpty {
            rows.append((L10n.tr("Bản dạng giới"), gender))
        }
        if canShow("orientation") && !orientation.isEmpty {
            rows.append((L10n.tr("Xu hướng"), orientation))
        }
        if canShow("communityRole") && !communityRole.isEmpty {
            rows.append((L10n.tr("Vai trò cộng đồng"), communityRole))
        }
        if canShow("pronouns") && !pronouns.isEmpty {
            rows.append((L10n.tr("Cách xưng hô"), pronouns))
        }
        if canShow("relationshipRole") && !relationshipRole.isEmpty {
            rows.append((L10n.tr("Tình trạng quan hệ"), relationshipRole))
        }
        if canShow("lookingFor") && !lookingFor.isEmpty {
            rows.append((L10n.tr("Mong muốn"), lookingFor))
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        KinnectAvatarView(
                            name: name.isEmpty ? (appState.currentUser?.name ?? "Kinnect") : name,
                            avatarURL: appState.currentUser?.avatarUrl ?? "",
                            colorHex: appState.currentUser?.avatarColor ?? "#7C3AED",
                            size: 64
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name.isEmpty ? (appState.currentUser?.name ?? "Kinnect") : name)
                                .font(.title3.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            if let h = appState.currentUser?.handle, !h.isEmpty {
                                Text("@\(h)")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            Text(L10n.tr("Chế độ xem của người khác"))
                                .font(.caption2.bold())
                                .foregroundColor(KinnectTheme.accentBright)
                        }
                        Spacer()
                    }
                    .kinnectCard()

                    VStack(alignment: .leading, spacing: 8) {
                        if visibleEntries.isEmpty && !(canShow("interests") && !interests.isEmpty) {
                            Text(L10n.tr("Chưa có thông tin công khai"))
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(Array(visibleEntries.enumerated()), id: \.offset) { idx, entry in
                                if idx > 0 { Divider().background(KinnectTheme.borderSoft) }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.label)
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                    Text(entry.value)
                                        .font(.subheadline)
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .kinnectMultiline()
                                }
                                .padding(.vertical, 4)
                            }
                            if canShow("interests") && !interests.isEmpty {
                                Divider().background(KinnectTheme.borderSoft)
                                Text(L10n.tr("Sở thích"))
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                                WrappingHStack(horizontalSpacing: 6, verticalSpacing: 6) {
                                    ForEach(interests, id: \.self) { item in
                                        Text(item)
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(KinnectTheme.accentBright)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.accentSoft))
                                    }
                                }
                            }
                        }
                    }
                    .kinnectCard()
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Xem trước hồ sơ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Account & Security Sheets
struct ActiveSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var sessions: [[String: Any]] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                    let sid = s["id"] as? String ?? ""
                    let label = (s["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? L10n.tr("Thiết bị Kinnect")
                    let current = s["current"] as? Bool ?? false
                    let expires = (s["expires"] as? NSNumber)?.int64Value ?? (s["expires"] as? Int64) ?? Int64((s["expires"] as? Int) ?? 0)
                    let deviceIcon: String = {
                        let low = label.lowercased()
                        if low.contains("ipad") { return "ipad" }
                        if low.contains("mac") || low.contains("windows") || low.contains("linux") || low.contains("web") { return "desktopcomputer" }
                        return "iphone"
                    }()
                    HStack(spacing: 12) {
                        Image(systemName: deviceIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(current ? KinnectTheme.online : KinnectTheme.accentBright)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(KinnectTheme.surfaceElevated))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label)
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                                .kinnectMultiline()
                            Text(current ? L10n.tr("Thiết bị hiện tại") : Self.sessionExpiry(expires))
                                .font(.caption)
                                .foregroundColor(current ? KinnectTheme.online : KinnectTheme.textSecondary)
                        }
                        Spacer()
                        if !current && !sid.isEmpty {
                            Button(role: .destructive) {
                                Task { await revokeSession(sid) }
                            } label: {
                                Text(L10n.tr("Đăng xuất"))
                                    .font(.caption.bold())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(KinnectTheme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Phiên đăng nhập"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSessions()
            }
        }
    }

    private static func sessionExpiry(_ expires: Int64) -> String {
        guard expires > 0 else { return L10n.tr("Phiên hoạt động") }
        let date = Date(timeIntervalSince1970: TimeInterval(expires) / 1000)
        let formatter = DateFormatter()
        formatter.locale = LocalizationManager.shared.currentLanguage.locale
        formatter.dateFormat = "dd/MM/yyyy"
        return "\(L10n.tr("Hết hạn")) \(formatter.string(from: date))"
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
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showCurrentPassword = false
    @State private var showNewPassword = false
    @State private var showConfirmPassword = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Bảo mật mật khẩu"))
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(L10n.tr("Mật khẩu mới cần tối thiểu 6 ký tự. Sau khi đổi mật khẩu, phiên đăng nhập trên thiết bị hiện tại sẽ được duy trì và các thiết bị khác sẽ cần đăng nhập lại."))
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                    if hasPassword {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("Mật khẩu hiện tại"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.textSecondary)
                            HStack {
                                if showCurrentPassword {
                                    TextField(L10n.tr("Nhập mật khẩu hiện tại"), text: $currentPassword)
                                } else {
                                    SecureField(L10n.tr("Nhập mật khẩu hiện tại"), text: $currentPassword)
                                }
                                KinnectIconButton(
                                    glyph: showCurrentPassword ? .eyeOff : .eye,
                                    label: L10n.tr(showCurrentPassword ? "Ẩn" : "Hiện"),
                                    tint: KinnectTheme.textSecondary
                                ) {
                                    showCurrentPassword.toggle()
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                        }
                    } else {
                        Text(L10n.tr("Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Bạn có thể đặt mật khẩu mới khi phiên đăng nhập còn mới (trong 10 phút)."))
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Mật khẩu mới"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        HStack {
                            if showNewPassword {
                                TextField(L10n.tr("Tối thiểu 6 ký tự"), text: $newPassword)
                            } else {
                                SecureField(L10n.tr("Tối thiểu 6 ký tự"), text: $newPassword)
                            }
                            KinnectIconButton(
                                glyph: showNewPassword ? .eyeOff : .eye,
                                label: L10n.tr(showNewPassword ? "Ẩn" : "Hiện"),
                                tint: KinnectTheme.textSecondary
                            ) {
                                showNewPassword.toggle()
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Xác nhận mật khẩu mới"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        HStack {
                            if showConfirmPassword {
                                TextField(L10n.tr("Nhập lại mật khẩu mới"), text: $confirmPassword)
                            } else {
                                SecureField(L10n.tr("Nhập lại mật khẩu mới"), text: $confirmPassword)
                            }
                            KinnectIconButton(
                                glyph: showConfirmPassword ? .eyeOff : .eye,
                                label: L10n.tr(showConfirmPassword ? "Ẩn" : "Hiện"),
                                tint: KinnectTheme.textSecondary
                            ) {
                                showConfirmPassword.toggle()
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.footnote.weight(.medium))
                            .foregroundColor(KinnectTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await updatePassword() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }
                            Text(L10n.tr("Cập nhật mật khẩu"))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            canSubmit
                                ? KinnectTheme.primaryGradient
                                : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .disabled(!canSubmit || isSubmitting)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr(hasPassword ? "Đổi mật khẩu" : "Đặt mật khẩu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var hasPassword: Bool {
        appState.currentUser?.hasPassword ?? true
    }

    private var canSubmit: Bool {
        (!hasPassword || !currentPassword.isEmpty) && newPassword.count >= 6 && !confirmPassword.isEmpty && confirmPassword == newPassword
    }

    private func updatePassword() async {
        errorMessage = nil
        guard newPassword == confirmPassword else {
            errorMessage = L10n.tr("Mật khẩu xác nhận không khớp.")
            return
        }
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            appState.currentUser?.hasPassword = true
            appState.showToast(L10n.tr("Đã lưu mật khẩu. Các thiết bị khác đã được đăng xuất."))
            dismiss()
            return
        }
        #endif
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/password",
                method: "POST",
                body: [
                    "current": hasPassword ? currentPassword : "",
                    "next": newPassword
                ]
            )
            appState.currentUser?.hasPassword = true
            appState.showToast(L10n.tr("Đã lưu mật khẩu. Các thiết bị khác đã được đăng xuất."))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            appState.showToast(error.localizedDescription)
        }
    }
}

struct BlockedUsersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var blockedUsers: [KinnectUser] = []

    var body: some View {
        NavigationStack {
            List {
                if blockedUsers.isEmpty {
                    Text(L10n.tr("Bạn chưa chặn người dùng nào."))
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
                            Button(L10n.tr("Bỏ chặn")) {
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
            .navigationTitle(L10n.tr("Người dùng đã chặn"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadBlocks()
            }
        }
    }

    private func loadBlocks() async {
        #if DEBUG
        if UIReviewFixture.isEnabled {
            self.blockedUsers = [
                KinnectUser.from([
                    "id": "fixture_blocked_01",
                    "name": "Trần Văn Bình",
                    "handle": "binh_tran",
                    "avatarColor": "#EF4444"
                ]),
                KinnectUser.from([
                    "id": "fixture_blocked_02",
                    "name": "Lê Hoàng Phúc",
                    "handle": "phuc_le",
                    "avatarColor": "#F59E0B"
                ])
            ]
            return
        }
        #endif
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/blocks") {
            let list = (res["users"] as? [[String: Any]]) ?? (res["blocks"] as? [[String: Any]]) ?? []
            self.blockedUsers = list.map { entry in
                if let userDict = entry["user"] as? [String: Any] {
                    return KinnectUser.from(userDict)
                }
                return KinnectUser.from(entry)
            }
        }
    }

    private func unblock(_ u: KinnectUser) async {
        await appState.unblockUser(userId: u.id)
        await loadBlocks()
    }
}

struct DeleteAccountConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var confirmUsername = ""
    @State private var password = ""
    @State private var totpCode = ""
    @State private var showTotpField = false
    @State private var twoFactorEnabled = false
    @State private var pendingOAuth2FACode: String? = nil
    @State private var pendingOAuthSnapshot: OAuthManager.SessionSnapshot? = nil
    @State private var requiredUsername = ""
    @State private var requiresPassword = true
    @State private var oauthProviders: [String] = []
    @State private var summaryInfo: String = "Xóa tài khoản là hành động không thể đảo ngược."
    @State private var isDeleting = false
    @State private var isReauthenticating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.tr("Cảnh báo: Hành động này sẽ xóa vĩnh viễn tài khoản Kinnect, bài viết, video ngắn, tin nhắn, ví và toàn bộ phiên đăng nhập của bạn. Không thể khôi phục sau khi xóa."))
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.danger)
                        .kinnectMultiline()

                    Text(L10n.tr(summaryInfo))
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(L10n.tr("Nhập chính xác tên đăng nhập của bạn để xác nhận")) (\(requiredUsername.isEmpty ? (appState.currentUser?.handle ?? "") : requiredUsername)):")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        TextField(L10n.tr("Tên đăng nhập"), text: $confirmUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    if requiresPassword {
                        if !oauthProviders.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.tr("Xác thực lại tài khoản liên kết"))
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                ForEach(oauthProviders, id: \.self) { provider in
                                    Button {
                                        Task { await reauthenticate(provider: provider) }
                                    } label: {
                                        HStack(spacing: 8) {
                                            if isReauthenticating {
                                                ProgressView()
                                            } else {
                                                Image(systemName: providerIconName(provider))
                                                    .font(.subheadline.weight(.semibold))
                                            }
                                            Text("\(L10n.tr("Xác thực lại bằng")) \(providerDisplayName(provider))")
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                                        .foregroundColor(KinnectTheme.textPrimary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isReauthenticating || isDeleting)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(oauthProviders.isEmpty ? L10n.tr("Nhập mật khẩu hiện tại") : L10n.tr("Hoặc nhập mật khẩu hiện tại"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            SecureField(L10n.tr("Mật khẩu của bạn"), text: $password)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                    } else if !oauthProviders.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(KinnectTheme.online)
                            Text(L10n.tr("Đã xác thực phiên đăng nhập gần đây. Bạn có thể xóa tài khoản mà không cần mật khẩu."))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }

                    if twoFactorEnabled || showTotpField || pendingOAuth2FACode != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("Mã xác thực 2 bước (2FA)"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            TextField(L10n.tr("Nhập mã 6 chữ số hoặc mã dự phòng"), text: $totpCode)
                                .keyboardType(.asciiCapable)
                                .textContentType(.oneTimeCode)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.textPrimary)

                            if let oauthCode = pendingOAuth2FACode, !oauthCode.isEmpty {
                                Button {
                                    Task { await finishOAuthReauth2FA(code: oauthCode) }
                                } label: {
                                    Text(L10n.tr("Hoàn tất xác thực 2FA OAuth"))
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.accentBright)
                                }
                                .disabled(isReauthenticating || totpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        Task { await performAccountDeletion() }
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Text(L10n.tr("Xác nhận xóa vĩnh viễn tài khoản"))
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(KinnectTheme.danger)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .disabled(
                        isDeleting
                            || isReauthenticating
                            || confirmUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != targetUsername.lowercased()
                            || (requiresPassword
                                && password.isEmpty
                                && !((twoFactorEnabled || showTotpField)
                                    && !oauthProviders.isEmpty
                                    && !totpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    )
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Xóa tài khoản"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Hủy")) { dismiss() }
                }
            }
            .task {
                await refreshDeletionRequirements()
            }
        }
    }

    private var targetUsername: String {
        if !requiredUsername.isEmpty { return requiredUsername }
        return appState.currentUser?.handle ?? ""
    }

    private func providerDisplayName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "apple": return "Apple"
        case "google": return "Google"
        case "facebook": return "Facebook"
        default: return provider.capitalized
        }
    }

    private func providerIconName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "apple": return "apple.logo"
        case "google": return "globe"
        case "facebook": return "person.2.circle.fill"
        default: return "key.fill"
        }
    }

    private func refreshDeletionRequirements() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me/account-deletion") {
            if let u = res["username"] as? String, !u.isEmpty {
                self.requiredUsername = u
            }
            self.requiresPassword = (res["requiresPassword"] as? Bool) ?? true
            self.oauthProviders = (res["oauthProviders"] as? [String]) ?? []
            if let tfEnabled = res["twoFactorEnabled"] as? Bool {
                self.twoFactorEnabled = tfEnabled
            }
        }
        if let tfRes = try? await KinnectAPIClient.shared.requestJSON("/api/me/2fa") {
            self.twoFactorEnabled = (tfRes["enabled"] as? Bool) == true
        }
    }

    private func reauthenticate(provider: String) async {
        guard let expectedUserId = appState.currentUser?.id, !expectedUserId.isEmpty else {
            appState.showToast(L10n.tr("Không xác định được tài khoản hiện tại."))
            return
        }
        isReauthenticating = true
        defer { isReauthenticating = false }
        let cleanTotp = totpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = OAuthManager.SessionSnapshot.capture()
        do {
            try await OAuthManager.shared.reauthenticateForAccountDeletion(
                provider: provider,
                expectedUserId: expectedUserId,
                totpCode: cleanTotp.isEmpty ? nil : cleanTotp
            )
            pendingOAuth2FACode = nil
            pendingOAuthSnapshot = nil
            await refreshDeletionRequirements()
            if !requiresPassword {
                appState.showToast(L10n.tr("Đã xác thực lại tài khoản. Bạn có thể tiếp tục xóa tài khoản."))
            }
        } catch {
            if case OAuthError.canceled = error {
                return
            }
            if case OAuthError.twoFactorRequired(let oauthCode) = error {
                showTotpField = true
                twoFactorEnabled = true
                pendingOAuthSnapshot = snapshot
                if !oauthCode.isEmpty {
                    pendingOAuth2FACode = oauthCode
                }
                appState.showToast(L10n.tr("Tài khoản bật 2FA. Nhập mã 6 số rồi bấm xác thực lại hoặc xác nhận xóa tài khoản."))
                return
            }
            appState.showToast(error.localizedDescription)
        }
    }

    private func finishOAuthReauth2FA(code: String) async {
        let cleanTotp = totpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTotp.isEmpty else { return }
        guard let expectedUserId = appState.currentUser?.id, !expectedUserId.isEmpty else {
            appState.showToast(L10n.tr("Không xác định được tài khoản hiện tại."))
            return
        }
        let snapshot = pendingOAuthSnapshot ?? OAuthManager.SessionSnapshot.capture()
        isReauthenticating = true
        defer { isReauthenticating = false }
        do {
            try await OAuthManager.shared.verifyOAuth2FAForAccountDeletion(
                code: code,
                totpCode: cleanTotp,
                expectedUserId: expectedUserId,
                snapshot: snapshot
            )
            pendingOAuth2FACode = nil
            pendingOAuthSnapshot = nil
            await refreshDeletionRequirements()
            if !requiresPassword {
                appState.showToast(L10n.tr("Đã xác thực 2FA. Bạn có thể tiếp tục xóa tài khoản."))
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func performAccountDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        var body: [String: Any] = [
            "confirmUsername": confirmUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "confirmDelete": true
        ]
        if requiresPassword && !password.isEmpty {
            body["password"] = password
        }
        let cleanTotp = totpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTotp.isEmpty {
            body["totpCode"] = cleanTotp
        }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/account-deletion",
                method: "DELETE",
                body: body
            )
            dismiss()
            appState.clearSessionState()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct PrivacySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @AppStorage("app_appearance_mode") private var appearanceMode: String = "system"

    @State private var discoverable: Bool = true
    @State private var showDistance: Bool = true
    @State private var showActivity: Bool = true
    @State private var dmFriendsOnly: Bool = false
    @State private var cloudChatSync: Bool = true
    @State private var isSaving = false
    @State private var showPrivateAlbum = false
    @State private var showBlockedUsers = false
    @State private var showDeleteAccount = false
    @State private var privatePhotos: [PrivatePhotoItem] = []
    @State private var privateRequests: [PrivateAccessRequestItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("Ngôn ngữ ứng dụng"))
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Picker(L10n.tr("Ngôn ngữ"), selection: Binding(
                            get: { loc.preference.rawValue },
                            set: { raw in
                                loc.setPreference(AppLanguagePreference(rawValue: raw) ?? .system)
                            }
                        )) {
                            Text("Tiếng Việt").tag("vi")
                            Text("English").tag("en")
                            Text(L10n.tr("Theo hệ thống")).tag("system")
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surface))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("Giao diện & Chế độ sáng/tối"))
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(L10n.tr("Tùy chỉnh giao diện theo sở thích của bạn: Sáng, Tối hoặc tự động theo cài đặt iOS."))
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()

                        Picker(L10n.tr("Chế độ hiển thị"), selection: $appearanceMode) {
                            Text(L10n.tr("Hệ thống")).tag("system")
                            Text(L10n.tr("Chế độ tối")).tag("dark")
                            Text(L10n.tr("Chế độ sáng")).tag("light")
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 4)
                        .onChange(of: appearanceMode) { newMode in
                            KinnectTheme.applyWindowAppearance(newMode)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surface))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Quyền riêng tư & Định vị"))
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(L10n.tr("Quản lý thông tin hiển thị với người dùng khác và mức độ khám phá tài khoản của bạn trên Kinnect."))
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        Toggle(isOn: $discoverable) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.tr("Cho phép tìm thấy tôi"))
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text(L10n.tr("Xuất hiện trong Khám phá và danh sách người dùng Quanh đây."))
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $showDistance) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.tr("Hiển thị khoảng cách"))
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text(L10n.tr("Chỉ hiển thị khoảng cách gần đúng để bảo vệ vị trí chính xác của bạn."))
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $showActivity) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.tr("Trạng thái hoạt động"))
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text(L10n.tr("Hiển thị chấm xanh khi bạn đang trực tuyến trên Kinnect."))
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $dmFriendsOnly) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.tr("Chỉ nhận tin nhắn từ bạn bè"))
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text(L10n.tr("Người lạ cần gửi lời mời kết bạn trước khi nhắn tin trực tiếp."))
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $cloudChatSync) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.tr("Đồng bộ tin nhắn đám mây"))
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text(L10n.tr("Lưu trữ và đồng bộ lịch sử hội thoại an toàn qua máy chủ Kinnect."))
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusXL).fill(KinnectTheme.surface))

                    VStack(spacing: 0) {
                        Button {
                            showPrivateAlbum = true
                        } label: {
                            privacyActionRow(title: L10n.tr("Ảnh riêng tư"), icon: "lock.fill", tint: KinnectTheme.warning)
                        }
                        .buttonStyle(.plain)

                        Divider().background(KinnectTheme.borderSoft)

                        Button {
                            showBlockedUsers = true
                        } label: {
                            privacyActionRow(title: L10n.tr("Tài khoản đã chặn"), icon: "nosign", tint: KinnectTheme.accentBright)
                        }
                        .buttonStyle(.plain)

                        Divider().background(KinnectTheme.borderSoft)

                        Button(role: .destructive) {
                            Task { await turnOffLocation() }
                        } label: {
                            privacyActionRow(title: L10n.tr("Tắt tìm quanh đây"), icon: "location.slash", tint: KinnectTheme.danger)
                        }
                        .buttonStyle(.plain)

                        Divider().background(KinnectTheme.borderSoft)

                        Button(role: .destructive) {
                            showDeleteAccount = true
                        } label: {
                            privacyActionRow(title: L10n.tr("Xóa tài khoản và dữ liệu"), icon: "trash.fill", tint: KinnectTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surface))
                }
                .padding(20)
                .padding(.bottom, 8)
            }
            .background(KinnectTheme.background)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await saveSettings() }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text(L10n.tr("Lưu cài đặt"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(KinnectTheme.primaryGradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                }
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(KinnectTheme.background)
            }
            .navigationTitle(L10n.tr("Quyền riêng tư"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSettings()
            }
            .sheet(isPresented: $showPrivateAlbum) {
                PrivateAlbumManageSheet(photos: $privatePhotos, requests: $privateRequests, onRefresh: {})
            }
            .sheet(isPresented: $showBlockedUsers) {
                BlockedUsersSheet()
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountConfirmationSheet()
            }
        }
    }

    private func privacyActionRow(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(tint == KinnectTheme.danger ? KinnectTheme.danger : KinnectTheme.textPrimary)
            Spacer()
            KinnectIcon(glyph: .chevronRight, size: 14, tint: KinnectTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func turnOffLocation() async {
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/me/location",
            method: "PATCH",
            body: ["enabled": false]
        )
        if var user = appState.currentUser {
            user.hasLocation = false
            appState.currentUser = user
        }
        appState.showToast(L10n.tr("Đã tắt tìm quanh đây"))
    }

    private func loadSettings() async {
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            self.discoverable = true
            self.showDistance = true
            self.showActivity = true
            self.dmFriendsOnly = false
            self.cloudChatSync = true
            return
        }
        #endif
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me") {
            let user = (res["user"] as? [String: Any]) ?? res
            self.discoverable = (user["discoverable"] as? Bool) ?? ((user["discoverable"] as? Int) == 1)
            self.showDistance = (user["showDistance"] as? Bool) ?? ((user["show_distance"] as? Int) == 1)
            self.showActivity = (user["showActivity"] as? Bool) ?? ((user["show_activity"] as? Int) == 1)
            let dm = user["dmMode"] as? String ?? user["dm_mode"] as? String ?? "everyone"
            self.dmFriendsOnly = (dm == "friends")
            self.cloudChatSync = (user["cloudChatSync"] as? Bool) ?? ((user["cloud_chat_sync"] as? Int) == 1)
        }
    }

    private func saveSettings() async {
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            appState.showToast(L10n.tr("Đã cập nhật quyền riêng tư."))
            dismiss()
            return
        }
        #endif
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me",
                method: "PATCH",
                body: [
                    "discoverable": discoverable,
                    "showDistance": showDistance,
                    "showActivity": showActivity,
                    "dmMode": dmFriendsOnly ? "friends" : "everyone",
                    "cloudChatSync": cloudChatSync
                ]
            )
            if var user = appState.currentUser {
                user.discoverable = discoverable
                user.showDistance = showDistance
                user.showActivity = showActivity
                user.cloudChatSync = cloudChatSync
                appState.currentUser = user
            }
            if showActivity {
                appState.reportActiveStatus(force: true)
            }
            appState.showToast(L10n.tr("Đã cập nhật quyền riêng tư."))
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct SupportContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var contactText = ""
    @State private var noteText = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Trung tâm Hỗ trợ & Trợ giúp"))
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(L10n.tr("Gửi phản hồi, báo cáo sự cố hoặc yêu cầu trợ giúp kỹ thuật từ đội ngũ phát triển Kinnect."))
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Thông tin liên hệ (Email hoặc SĐT)"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        TextField(L10n.tr("nhap@email.com hoặc 09xxxxxxxx"), text: $contactText)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Mô tả yêu cầu / Báo cáo sự cố"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        TextEditor(text: $noteText)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                    }

                    Button {
                        Task { await submitSupport() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }
                            Text(L10n.tr("Gửi yêu cầu hỗ trợ"))
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(canSubmit ? KinnectTheme.primaryGradient : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .disabled(!canSubmit || isSubmitting)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("Thông tin hữu ích"))
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        Link(destination: URL(string: "https://kinnect.io.vn/privacy")!) {
                            HStack {
                                Text(L10n.tr("Chính sách quyền riêng tư"))
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.accentBright)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        Link(destination: URL(string: "https://kinnect.io.vn/community")!) {
                            HStack {
                                Text(L10n.tr("Quy tắc cộng đồng"))
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.accentBright)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surface))
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Hỗ trợ"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                #if DEBUG
                if UIReviewFixture.activeScreen != nil {
                    contactText = "minhanh@kinnect.vn"
                    noteText = "Cần hỗ trợ hướng dẫn kích hoạt gói Studio Pro trên thiết bị mới."
                }
                #endif
            }
        }
    }

    private var canSubmit: Bool {
        !contactText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitSupport() async {
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            appState.showToast(L10n.tr("Đã gửi yêu cầu hỗ trợ thành công."))
            dismiss()
            return
        }
        #endif
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/support/request",
                method: "POST",
                body: [
                    "contact": contactText,
                    "note": noteText
                ]
            )
            appState.showToast(L10n.tr("Đã gửi yêu cầu hỗ trợ thành công."))
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Connections Sheet (Followers / Following)

struct ConnectionsInfo: Identifiable {
    let id = UUID()
    let kind: String
    let title: String
}

struct UserConnectionsSheet: View {
    let userId: String
    let kind: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var users: [KinnectUser] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedProfileUser: KinnectUser? = nil

    var filteredUsers: [KinnectUser] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return users
        }
        return users.filter { $0.name.lowercased().contains(q) || $0.handle.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(KinnectTheme.textSecondary)
                    TextField(L10n.tr("Tìm kiếm..."), text: $searchText)
                        .font(KinnectTheme.body)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                }
                .padding(10)
                .background(KinnectTheme.surface)
                .cornerRadius(KinnectTheme.radiusSM)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filteredUsers.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: kind == "followers" ? "person.2" : "person.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(KinnectTheme.textTertiary)
                        Text(kind == "followers" ? L10n.tr("Chưa có người theo dõi") : L10n.tr("Chưa theo dõi ai"))
                            .font(KinnectTheme.body)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredUsers) { u in
                            Button {
                                selectedProfileUser = u
                            } label: {
                                HStack(spacing: 12) {
                                    KinnectAvatarView(user: u, size: 44)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(u.name)
                                            .font(KinnectTheme.bodyBold)
                                            .foregroundColor(KinnectTheme.textPrimary)
                                        if !u.handle.isEmpty {
                                            Text("@\(u.handle)")
                                                .font(.system(size: 13))
                                                .foregroundColor(KinnectTheme.textSecondary)
                                        }
                                    }

                                    Spacer()

                                    if !u.city.isEmpty {
                                        Text(u.city)
                                            .font(.system(size: 12))
                                            .foregroundColor(KinnectTheme.textTertiary)
                                    }
                                    KinnectIcon(glyph: .chevronRight, size: 15, tint: KinnectTheme.textSecondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(KinnectTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadConnections()
            }
            .fullScreenCover(item: $selectedProfileUser) { user in
                ProfileView(targetUser: user)
            }
        }
    }

    private func loadConnections() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = "/api/users/\(userId)/\(kind)"
            let res = try await KinnectAPIClient.shared.requestJSON(endpoint)
            let rawList = (res["users"] as? [[String: Any]]) ?? (res[kind] as? [[String: Any]]) ?? []
            users = rawList.compactMap { KinnectUser.from($0) }
        } catch {
            // fallback
        }
    }
}

// MARK: - Video Thumbnail Loader & Grid Item (Parity Android loadVideoPreview)

final class VideoThumbnailLoader: ObservableObject {
    @Published var image: UIImage? = nil
    private static let cache = NSCache<NSString, UIImage>()
    private var task: Task<Void, Never>? = nil

    static func clearCache() {
        cache.removeAllObjects()
    }

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
        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 576)

            do {
                let cgImage = try await generator.image(at: .zero).image
                guard !Task.isCancelled else { return }
                let uiImage = UIImage(cgImage: cgImage)
                Self.cache.setObject(uiImage, forKey: key)
                await MainActor.run { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.image = uiImage
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

            if !short.thumbnailUrl.isEmpty {
                KinnectRemoteImageView(
                    rawURL: short.thumbnailUrl,
                    contentMode: .fill,
                    cornerRadius: 12,
                    maxHeight: 280
                )
            } else if let uiImage = loader.image {
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
            if short.thumbnailUrl.isEmpty && loader.image == nil && !short.videoUrl.isEmpty {
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
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textTertiary)
                        HStack(spacing: 3) {
                            Image(systemName: post.visibility == "followers" ? "person.2.fill" : "globe")
                                .font(.system(size: 9, weight: .semibold))
                            Text(post.visibility == "followers" ? L10n.tr("Người theo dõi") : L10n.tr("Công khai"))
                                .font(.caption2)
                        }
                        .foregroundColor(KinnectTheme.textSecondary)
                    }
                }

                Spacer()

                if isSelf {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label(L10n.tr("Xóa bài viết"), systemImage: "trash")
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

            // Media (Authenticated KinnectRemoteImageView / KinnectMediaTile instead of unauthenticated AsyncImage)
            if post.mediaItems.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.mediaItems) { item in
                            KinnectMediaTile(path: item.url, kind: item.kind, thumbnailUrl: item.thumbnail)
                                .frame(width: 240)
                        }
                    }
                }
            } else if !post.imageUrl.isEmpty {
                if post.mediaKind.lowercased().contains("video") {
                    KinnectMediaTile(path: post.imageUrl, kind: post.mediaKind, thumbnailUrl: post.thumbnailUrl)
                } else {
                    KinnectRemoteImageView(
                        rawURL: post.imageUrl,
                        contentMode: .fit,
                        cornerRadius: KinnectTheme.radiusSM,
                        maxHeight: 340
                    )
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
            do {
                if willLike {
                    _ = try await KinnectAPIClient.shared.requestJSON(
                        "/api/posts/\(post.id)/like",
                        method: "POST",
                        body: ["reaction": "love"]
                    )
                } else {
                    _ = try await KinnectAPIClient.shared.requestJSON(
                        "/api/posts/\(post.id)/like",
                        method: "DELETE",
                        body: [:]
                    )
                }
            } catch {
                isLiked = !willLike
                likesCount = max(0, likesCount + (willLike ? -1 : 1))
                AppState.shared.showToast(error.localizedDescription)
            }
        }
    }
}

