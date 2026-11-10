import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    var targetUser: KinnectUser? = nil
    var onOpenWallet: (() -> Void)? = nil
    var onOpenFriends: (() -> Void)? = nil
    var onOpenStore: (() -> Void)? = nil
    var initialTab: ProfileTab? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var pushKit = PushKitManager.shared

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

    init(targetUser: KinnectUser? = nil, onOpenWallet: (() -> Void)? = nil, onOpenFriends: (() -> Void)? = nil, onOpenStore: (() -> Void)? = nil, initialTab: ProfileTab? = nil) {
        self.targetUser = targetUser
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
    @State private var showEditProfileSheet = false
    @State private var showSessionsSheet = false
    @State private var showPasswordSheet = false
    @State private var showBlocksSheet = false
    @State private var showPrivacySheet = false
    @State private var showSupportSheet = false
    @State private var showDeleteAccountSheet = false

    @State private var detailedPeerUser: KinnectUser? = nil
    @State private var peerFriendship: String = "none"
    @State private var showPeerChat = false
    @State private var isFriendActionLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !isSelf, let peer = activeUser {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                KinnectIcon(glyph: .back, size: 18, tint: KinnectTheme.textPrimary)
                                Text("Quay lại")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        }
                        Spacer()
                        Text("@\(peer.handle.isEmpty ? peer.name : peer.handle)")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.horizontal, 4)
                }

                if let user = activeUser {
                    // 1. Cover & Avatar Card with Handle & Stats (Parity Android 1.2.12 build 118)
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            if !user.coverUrl.isEmpty {
                                KinnectRemoteImageView(
                                    rawURL: user.coverUrl,
                                    contentMode: .fill,
                                    cornerRadius: KinnectTheme.radiusXL,
                                    maxHeight: 140
                                )
                            } else {
                                RoundedRectangle(cornerRadius: KinnectTheme.radiusXL)
                                    .fill(KinnectTheme.primaryGradient)
                                    .frame(height: 130)
                            }

                            HStack(alignment: .bottom, spacing: 12) {
                                KinnectAvatarView(
                                    name: user.name,
                                    avatarURL: user.avatarUrl,
                                    colorHex: user.avatarColor,
                                    size: 76,
                                    isOnline: isSelf ? true : appState.onlineUserIds.contains(user.id)
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

                        if isSelf {
                            // Prominent "Chỉnh sửa hồ sơ" Button
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
                                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            }
                            .padding(.horizontal, 14)
                        } else {
                            peerActionsRow(user: user)
                        }

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

                    // 2. Profile Tabs (Android 1.2.12 Parity)
                    Picker("Mục hồ sơ", selection: $selectedTab) {
                        ForEach(isSelf ? ProfileTab.allCases : [.about, .posts, .videos], id: \.self) { t in
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
                        if isSelf {
                            albumsTabContent(user: user)
                        } else {
                            aboutTabContent(user: user)
                        }
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
            } else if let target = targetUser {
                await refreshPeer(target: target)
            }
        }
        .sheet(isPresented: $showPeerChat) {
            if let u = activeUser {
                NavigationStack {
                    DirectChatDetailView(peer: u)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPeerChat)
        .sheet(isPresented: $showEditProfileSheet) {
            EditProfileSheet(onSaved: {
                Task { await refreshMe() }
            })
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showEditProfileSheet)
        .sheet(isPresented: $showPublicAlbumSheet) {
            PublicAlbumManageSheet(
                posts: userPosts,
                onRefresh: { Task { await refreshMe() } }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPublicAlbumSheet)
        .sheet(isPresented: $showPrivateAlbumSheet) {
            PrivateAlbumManageSheet(
                photos: $privatePhotos,
                requests: $privateAccessRequests,
                onRefresh: { Task { await refreshMe() } }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPrivateAlbumSheet)
        .sheet(item: $activeShortItem) { short in
            ProfileShortDetailSheet(
                short: short,
                onRefresh: { Task { await refreshMe() } }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: activeShortItem)
        .sheet(isPresented: $showSessionsSheet) {
            ActiveSessionsSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSessionsSheet)
        .sheet(isPresented: $showPasswordSheet) {
            ChangePasswordSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPasswordSheet)
        .sheet(isPresented: $showBlocksSheet) {
            BlockedUsersSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showBlocksSheet)
        .sheet(isPresented: $showPrivacySheet) {
            PrivacySettingsSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPrivacySheet)
        .sheet(isPresented: $showSupportSheet) {
            SupportContactSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSupportSheet)
        .sheet(isPresented: $showDeleteAccountSheet) {
            DeleteAccountConfirmationSheet()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showDeleteAccountSheet)
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
                    Text(isSelf ? "Chưa có thông tin công khai. Cập nhật hồ sơ để mọi người hiểu bạn hơn." : "Người dùng chưa cập nhật phần tự giới thiệu.")
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

            if isSelf {
                // Quick Actions & Security
                VStack(spacing: 10) {
                    actionRow(glyph: .wallet, title: "Ví Kinnect", color: KinnectTheme.warning) {
                        if let onOpenWallet { onOpenWallet() } else { appState.navigate(to: "wallet") }
                    }
                    actionRow(glyph: .store, title: "Cửa hàng Kinnect", color: KinnectTheme.accentBright) {
                        if let onOpenStore { onOpenStore() } else if let onOpenWallet { onOpenWallet() } else { appState.navigate(to: "wallet") }
                    }
                    actionRow(glyph: .friends, title: "Bạn bè", color: KinnectTheme.accent) {
                        if let onOpenFriends { onOpenFriends() } else { appState.navigate(to: "friends") }
                    }
                    actionRow(glyph: .shield, title: "Quản lý phiên đăng nhập", color: .cyan) {
                        showSessionsSheet = true
                    }
                    actionRow(glyph: .lock, title: "Đổi mật khẩu", color: .green) {
                        showPasswordSheet = true
                    }
                    actionRow(glyph: .block, title: "Danh sách người dùng đã chặn", color: .orange) {
                        showBlocksSheet = true
                    }
                    actionRow(glyph: .shield, title: "Cài đặt và quyền riêng tư", color: .purple) {
                        showPrivacySheet = true
                    }
                    actionRow(glyph: .notifications, title: "Trung tâm Hỗ trợ & Trợ giúp", color: .blue) {
                        showSupportSheet = true
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
                        .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                    }

                    Button(role: .destructive) {
                        showDeleteAccountSheet = true
                    } label: {
                        Label("Xóa vĩnh viễn tài khoản Kinnect", systemImage: "trash.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.danger.opacity(0.18)))
                            .foregroundColor(KinnectTheme.danger)
                    }
                }
                .kinnectCard()
            }
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
                            KinnectRemoteImageView(rawURL: post.imageUrl, contentMode: .fill, cornerRadius: KinnectTheme.radiusSM, maxHeight: 180)
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
                    RoundedRectangle(cornerRadius: KinnectTheme.radiusMD)
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
                    RoundedRectangle(cornerRadius: KinnectTheme.radiusMD)
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
                                RoundedRectangle(cornerRadius: KinnectTheme.radiusMD)
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

    @ViewBuilder
    private func peerFriendshipButton(user: KinnectUser) -> some View {
        let isFriends = (peerFriendship == "friends")
        let isOutgoing = (peerFriendship == "outgoing")
        let isIncoming = (peerFriendship == "incoming")
        let title: String = isFriends ? "Bạn bè" : (isOutgoing ? "Đã gửi" : (isIncoming ? "Chấp nhận" : "Kết bạn"))
        let glyph: KinnectGlyph = isFriends ? .friends : (isOutgoing ? .refresh : .add)
        let fgColor: Color = isFriends ? KinnectTheme.online : .white

        Button {
            Task { await handlePeerFriendAction(user: user) }
        } label: {
            HStack(spacing: 6) {
                KinnectIcon(glyph: glyph, size: 18, tint: fgColor)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(fgColor)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
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
                Text("Nhắn tin")
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.accentBright)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
        }
    }

    @ViewBuilder
    private func peerCallButton(user: KinnectUser, mode: String) -> some View {
        let isVideo = (mode == "video")
        Button {
            Task {
                dismiss()
                await NativeWebRTCManager.shared.startOutgoingCall(targetUser: user, mode: mode)
            }
        } label: {
            KinnectIcon(
                glyph: isVideo ? .videoCall : .phone,
                size: 18,
                tint: isVideo ? KinnectTheme.accentBright : KinnectTheme.online
            )
            .frame(width: 40, height: 40)
            .background(Circle().fill(KinnectTheme.surfaceElevated))
        }
        .accessibilityLabel(isVideo ? "Gọi video" : "Gọi thoại")
    }

    @ViewBuilder
    private func peerMoreMenu(user: KinnectUser) -> some View {
        Menu {
            Button(role: .destructive) {
                Task {
                    await appState.blockUser(userId: user.id, userName: user.name)
                    dismiss()
                }
            } label: {
                Label("Chặn người dùng", systemImage: "hand.raised.fill")
            }
            Button {
                appState.activeReportContext = UGCReportContext(
                    targetType: "user",
                    targetId: user.id,
                    targetUserId: user.id,
                    targetTitle: user.name
                )
            } label: {
                Label("Báo cáo người dùng", systemImage: "flag.fill")
            }
        } label: {
            KinnectIcon(glyph: .more, size: 18, tint: KinnectTheme.textSecondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(KinnectTheme.surfaceElevated))
        }
        .accessibilityLabel("Tùy chọn khác")
    }

    @ViewBuilder
    private func peerActionsRow(user: KinnectUser) -> some View {
        HStack(spacing: 8) {
            peerFriendshipButton(user: user)
            peerMessageButton()
            peerCallButton(user: user, mode: "audio")
            peerCallButton(user: user, mode: "video")
            peerMoreMenu(user: user)
        }
        .padding(.horizontal, 14)
    }

    private func handlePeerFriendAction(user: KinnectUser) async {
        isFriendActionLoading = true
        defer { isFriendActionLoading = false }
        let reqId = "pfriend_\(user.id)_\(Int(Date().timeIntervalSince1970))"
        if peerFriendship == "friends" {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friendship",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            peerFriendship = "none"
            appState.showToast("Đã hủy kết bạn")
        } else if peerFriendship == "outgoing" {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            peerFriendship = "none"
            appState.showToast("Đã thu hồi lời mời kết bạn")
        } else if peerFriendship == "incoming" {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request/respond",
                method: "POST",
                body: ["action": "accept"],
                requestId: reqId
            )
            peerFriendship = "friends"
            appState.showToast("Đã chấp nhận kết bạn!")
        } else {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request",
                method: "POST",
                body: [:],
                requestId: reqId
            )
            peerFriendship = "outgoing"
            appState.showToast("Đã gửi lời mời kết bạn")
        }
        await refreshPeer(target: user)
    }

    private func refreshPeer(target: KinnectUser) async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(target.id)"),
           let userDict = (res["user"] as? [String: Any]) ?? (res as? [String: Any]) {
            self.detailedPeerUser = KinnectUser.from(userDict)
            self.peerFriendship = (userDict["friendship"] as? String) ?? "none"
        }
        if let feedRes = try? await KinnectAPIClient.shared.requestJSON("/api/posts?user=\(target.id)"),
           let items = feedRes["posts"] as? [[String: Any]] {
            self.userPosts = items.map(PostItem.from)
        }
        if let shortsRes = try? await KinnectAPIClient.shared.requestJSON("/api/shorts?user=\(target.id)"),
           let items = shortsRes["shorts"] as? [[String: Any]] {
            self.userShorts = items.map(ShortItem.from)
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
                                    KinnectRemoteImageView(rawURL: post.imageUrl, contentMode: .fill, cornerRadius: KinnectTheme.radiusSM, maxHeight: 160)
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
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: KinnectTheme.radiusXL)
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
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.danger.opacity(0.18)))
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

// MARK: - Dedicated Edit Profile Sheet (100% Android & Web Parity)
struct EditProfileSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    // Basic Info
    @State private var name = ""
    @State private var birthDate = ""
    @State private var birthDateValue = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var showDatePicker = false

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
    @State private var isPrivate = false

    // Field-level Public/Private Visibility (Globe 🌐 vs Lock 🔒)
    @State private var visibility: [String: Bool] = [:]

    // Media & State
    @State private var isSaving = false
    @State private var isLoading = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?

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
        "Kết bạn", "Trò chuyện", "Hẹn hò", "Mối quan hệ nghiêm túc",
        "Tìm bạn chung sở thích", "Giao lưu học hỏi", "Tâm sự"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // 1. Photos Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                HStack(spacing: 6) {
                                    KinnectIcon(glyph: .profile, size: 18, tint: KinnectTheme.accentBright)
                                    Text("Đổi Avatar")
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
                                    Text("Đổi Ảnh bìa")
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
                            Text("Chạm 🌐 / 🔒 để chọn thông tin công khai hoặc riêng tư.")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                } header: {
                    Text("Hình ảnh đại diện")
                }

                // 2. Thông tin cơ bản
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tên hiển thị")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        TextField("Nhập tên hiển thị...", text: $name)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Ngày sinh")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "age", title: "Hiện tuổi")
                        }
                        Button {
                            showDatePicker.toggle()
                        } label: {
                            HStack {
                                Text(birthDate.isEmpty ? "Chọn ngày sinh (YYYY-MM-DD)" : birthDate)
                                    .foregroundColor(birthDate.isEmpty ? KinnectTheme.textSecondary : KinnectTheme.textPrimary)
                                Spacer()
                                Image(systemName: "calendar")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        .buttonStyle(.plain)

                        if showDatePicker {
                            DatePicker(
                                "Ngày sinh",
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
                        Text("Ngày sinh chỉ bạn xem; biểu tượng 🌐 cho phép hiện tuổi trên hồ sơ.")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                } header: {
                    Text("Thông tin cơ bản")
                }

                // 3. Giới thiệu và sở thích
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Giới thiệu bản thân (Bio)")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "bio", title: "Tiểu sử")
                        }
                        TextField("Chia sẻ vài dòng về bạn...", text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sở thích")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "interests", title: "Sở thích")
                        }
                        chipFlow(choices: interestChoices, selected: $selectedInterests, max: 10)
                    }
                } header: {
                    Text("Giới thiệu và sở thích")
                }

                // 4. Bản thân và cách xưng hô (Identity)
                Section {
                    pickerWithVisibility(title: "Bản dạng giới", key: "gender", selection: $gender, choices: genderChoices)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Chiều cao (cm)")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Spacer()
                                visibilityToggle(key: "height", title: "Chiều cao")
                            }
                            TextField("175", text: $height)
                                .keyboardType(.numberPad)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Cân nặng (kg)")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Spacer()
                                visibilityToggle(key: "weight", title: "Cân nặng")
                            }
                            TextField("68", text: $weight)
                                .keyboardType(.numberPad)
                        }
                    }

                    pickerWithVisibility(title: "Xu hướng tính dục", key: "orientation", selection: $orientation, choices: orientationChoices)
                    pickerWithVisibility(title: "Vai trò tự mô tả", key: "communityRole", selection: $communityRole, choices: communityRoleChoices)
                    pickerWithVisibility(title: "Cách xưng hô", key: "pronouns", selection: $pronouns, choices: pronounChoices)
                } header: {
                    Text("Bản thân và cách xưng hô")
                }

                // 5. Kết nối và cuộc sống
                Section {
                    pickerWithVisibility(title: "Tình trạng quan hệ", key: "relationshipRole", selection: $relationshipRole, choices: relationshipChoices)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Mong muốn kết nối")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            visibilityToggle(key: "lookingFor", title: "Mong muốn")
                        }
                        chipFlow(choices: lookingForChoices, selected: $selectedLookingFor, max: 7)
                    }

                    textWithVisibility(title: "Tỉnh / Thành phố", key: "city", text: $city, placeholder: "Hà Nội, TP. Hồ Chí Minh...")
                    textWithVisibility(title: "Nghề nghiệp", key: "occupation", text: $occupation, placeholder: "Lập trình viên, Nhiếp ảnh gia...")
                    textWithVisibility(title: "Trường học", key: "school", text: $school, placeholder: "Đại học Bách Khoa...")

                    Toggle(isOn: $isPrivate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Chế độ tài khoản riêng tư")
                                .font(.subheadline.bold())
                            Text("Chỉ bạn bè mới xem được đầy đủ bài viết và album của bạn.")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .tint(KinnectTheme.accentBright)
                } header: {
                    Text("Kết nối và cuộc sống")
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
                    Button("Lưu thay đổi") {
                        Task { await saveProfile() }
                    }
                    .bold()
                    .disabled(isSaving)
                }
            }
            .task {
                await loadMyProfile()
            }
        }
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
                Text(isPublic ? "Công khai" : "Chỉ tôi")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(isPublic ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(KinnectTheme.surfaceElevated))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isPublic ? "Công khai" : "Ẩn") \(title)")
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
                            appState.showToast("Tối đa \(max) lựa chọn.")
                        }
                    }
                } label: {
                    Text(choice)
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
                Text("Không muốn tiết lộ").tag("")
                ForEach(choices, id: \.self) { c in
                    Text(c).tag(c)
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
        defer { isLoading = false }
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
                self.isPrivate = me["isPrivate"] as? Bool ?? false

                if let vis = me["profileVisibility"] as? [String: Bool] {
                    self.visibility = vis
                } else {
                    for k in ["bio", "age", "gender", "orientation", "communityRole", "pronouns", "relationshipRole", "lookingFor", "city", "interests", "height", "weight", "occupation", "school"] {
                        self.visibility[k] = true
                    }
                }
            }
        } catch {}
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
            "isPrivate": isPrivate,
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
                appState.applyAuthenticatedUser(KinnectUser.from(userDict), rawDict: userDict)
            }
            appState.showToast("Đã cập nhật hồ sơ cá nhân hoàn chỉnh.")
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
    @State private var confirmPassword = ""
    @State private var showCurrentPassword = false
    @State private var showNewPassword = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bảo mật mật khẩu")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Mật khẩu mới cần tối thiểu 6 ký tự. Sau khi đổi mật khẩu, phiên đăng nhập trên thiết bị hiện tại sẽ được duy trì và các thiết bị khác sẽ cần đăng nhập lại.")
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mật khẩu hiện tại")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        HStack {
                            if showCurrentPassword {
                                TextField("Nhập mật khẩu hiện tại", text: $currentPassword)
                            } else {
                                SecureField("Nhập mật khẩu hiện tại", text: $currentPassword)
                            }
                            KinnectIconButton(
                                glyph: showCurrentPassword ? .eyeOff : .eye,
                                label: showCurrentPassword ? "Ẩn" : "Hiện",
                                tint: KinnectTheme.textSecondary
                            ) {
                                showCurrentPassword.toggle()
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mật khẩu mới")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        HStack {
                            if showNewPassword {
                                TextField("Tối thiểu 6 ký tự", text: $newPassword)
                            } else {
                                SecureField("Tối thiểu 6 ký tự", text: $newPassword)
                            }
                            KinnectIconButton(
                                glyph: showNewPassword ? .eyeOff : .eye,
                                label: showNewPassword ? "Ẩn" : "Hiện",
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
                        Text("Xác nhận mật khẩu mới")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        SecureField("Nhập lại mật khẩu mới", text: $confirmPassword)
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
                            Text("Cập nhật mật khẩu")
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
            .navigationTitle("Đổi mật khẩu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty && newPassword.count >= 6 && (confirmPassword.isEmpty || confirmPassword == newPassword)
    }

    private func updatePassword() async {
        errorMessage = nil
        guard newPassword == confirmPassword || confirmPassword.isEmpty else {
            errorMessage = "Mật khẩu xác nhận không khớp."
            return
        }
        if UIReviewFixture.activeScreen != nil {
            appState.showToast("Đã đổi mật khẩu thành công.")
            dismiss()
            return
        }
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
            errorMessage = error.localizedDescription
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
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
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
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nhập mật khẩu hiện tại")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        SecureField("Mật khẩu của bạn", text: $password)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
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
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
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

struct PrivacySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var discoverable: Bool = true
    @State private var showDistance: Bool = true
    @State private var showActivity: Bool = true
    @State private var dmFriendsOnly: Bool = false
    @State private var cloudChatSync: Bool = true
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quyền riêng tư & Định vị")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Quản lý thông tin hiển thị với người dùng khác và mức độ khám phá tài khoản của bạn trên Kinnect.")
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        Toggle(isOn: $discoverable) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cho phép tìm thấy tôi")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Xuất hiện trong Khám phá và danh sách người dùng Quanh đây.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $showDistance) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hiển thị khoảng cách")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Chỉ hiển thị khoảng cách gần đúng để bảo vệ vị trí chính xác của bạn.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $showActivity) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trạng thái hoạt động")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Hiển thị chấm xanh khi bạn đang trực tuyến trên Kinnect.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $dmFriendsOnly) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chỉ nhận tin nhắn từ bạn bè")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Người lạ cần gửi lời mời kết bạn trước khi nhắn tin trực tiếp.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $cloudChatSync) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Đồng bộ tin nhắn đám mây")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Lưu trữ và đồng bộ lịch sử hội thoại an toàn qua máy chủ Kinnect.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusXL).fill(KinnectTheme.surface))

                    Button {
                        Task { await saveSettings() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView().tint(.white)
                            }
                            Text("Lưu cài đặt")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(KinnectTheme.primaryGradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .disabled(isSaving)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Quyền riêng tư")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSettings()
            }
        }
    }

    private func loadSettings() async {
        if UIReviewFixture.activeScreen != nil {
            self.discoverable = true
            self.showDistance = true
            self.showActivity = true
            self.dmFriendsOnly = false
            self.cloudChatSync = true
            return
        }
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
        if UIReviewFixture.activeScreen != nil {
            appState.showToast("Đã cập nhật quyền riêng tư.")
            dismiss()
            return
        }
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
            appState.showToast("Đã cập nhật quyền riêng tư.")
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct SupportContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var contactText = ""
    @State private var noteText = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trung tâm Hỗ trợ & Trợ giúp")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Gửi phản hồi, báo cáo sự cố hoặc yêu cầu trợ giúp kỹ thuật từ đội ngũ phát triển Kinnect.")
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Thông tin liên hệ (Email hoặc SĐT)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        TextField("nhap@email.com hoặc 09xxxxxxxx", text: $contactText)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mô tả yêu cầu / Báo cáo sự cố")
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
                            Text("Gửi yêu cầu hỗ trợ")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(canSubmit ? KinnectTheme.primaryGradient : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .disabled(!canSubmit || isSubmitting)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Thông tin hữu ích")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        Link(destination: URL(string: "https://kinnect.io.vn/privacy")!) {
                            HStack {
                                Text("Chính sách quyền riêng tư")
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
                                Text("Quy tắc cộng đồng")
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
            .navigationTitle("Hỗ trợ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                if UIReviewFixture.activeScreen != nil {
                    contactText = "minhanh@kinnect.vn"
                    noteText = "Cần hỗ trợ hướng dẫn kích hoạt gói Studio Pro trên thiết bị mới."
                }
            }
        }
    }

    private var canSubmit: Bool {
        !contactText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitSupport() async {
        if UIReviewFixture.activeScreen != nil {
            appState.showToast("Đã gửi yêu cầu hỗ trợ thành công.")
            dismiss()
            return
        }
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
            appState.showToast("Đã gửi yêu cầu hỗ trợ thành công.")
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
