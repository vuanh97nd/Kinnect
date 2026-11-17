import AVFoundation
import AVKit
import PhotosUI
import SwiftUI
import UIKit

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
    @State private var showPeerChat = false
    @State private var isFriendActionLoading = false

    var body: some View {
        VStack(spacing: 0) {
            // Dedicated Pinned Header Bar (1:1 Android shell / accountHeader)
            profilePinnedHeader

            ScrollView {
                VStack(spacing: 16) {
                    if let user = activeUser {
                        // 1. Cover & Avatar Card with Handle, Bio & Stats (Parity Android 1.2.12 MainActivity.profileCard lines 2206-2278)
                        profileCard(user: user)

                        // 2. Profile Tabs — dùng KSegmented để trạng thái chọn dùng accent,
                        // không phải pill xám của Picker hệ thống (trông như bị vô hiệu).
                        KSegmented(
                            options: isSelf ? ProfileTab.allCases : [.about, .posts, .videos],
                            title: { $0.rawValue },
                            selection: $selectedTab
                        )
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
                onRefresh: { Task { await refreshMe() } }
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
        .fullScreenCover(item: $activeShortItem) { short in
            ProfileShortDetailSheet(
                short: short,
                shorts: userShorts,
                onRefresh: { Task { await refreshMe() } }
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
            title: isSelf ? "Trang cá nhân" : (activeUser?.name ?? "Hồ sơ"),
            onBack: onBack ?? { dismiss() },
            trailingActions: isSelf ? [
                PinnedHeaderBar.TrailingAction(
                    systemImage: "pencil",
                    accessibilityLabel: "Chỉnh sửa hồ sơ",
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
                            .font(KinnectTheme.scaled(14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .padding(8)
                    .accessibilityLabel("Đổi ảnh bìa")
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
                        .accessibilityLabel("Đổi ảnh đại diện")
                    } else {
                        avatarBadge(user: user, size: 88)
                    }
                }
                .offset(y: -28)
                .padding(.bottom, -28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.name)
                        .font(KinnectTheme.scaled(20, weight: .bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)

                    Text("@\(user.handle.isEmpty ? user.name : user.handle)")
                        .font(KinnectTheme.scaled(13))
                        .foregroundColor(KinnectTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)

                Spacer()
            }
            .padding(.horizontal, 16)

            // Action Button Row (Parity Android lines 2249-2270: full-width 44dp pencil "Chỉnh sửa hồ sơ" or peer actions)
            Group {
                if isSelf {
                    Button {
                        showEditProfileSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                                .font(.subheadline.bold())
                            Text("Chỉnh sửa hồ sơ")
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
            .padding(.horizontal, 16)

            // Bio in Profile Card (Android parity lines 2272-2276: 13sp MUTED, lineSpacing 1.6f)
            if !user.bio.isEmpty {
                Text(user.bio)
                    .font(KinnectTheme.scaled(13))
                    .foregroundColor(KinnectTheme.textSecondary)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            // Stats Bar: 3 soft cards (Android parity lines 4508-4529: bài viết, người theo dõi, đang theo dõi)
            HStack(spacing: 8) {
                statCard(count: user.postsCount, label: "bài viết") {
                    selectedTab = .posts
                }
                statCard(count: user.followersCount, label: "người theo dõi") {
                    selectedConnectionsInfo = ConnectionsInfo(kind: "followers", title: "Người theo dõi")
                }
                statCard(count: user.followingCount, label: "đang theo dõi") {
                    selectedConnectionsInfo = ConnectionsInfo(kind: "following", title: "Đang theo dõi")
                }
            }
            .padding(.horizontal, 16)
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
            Text("Chưa có thông tin công khai")
                .font(.headline)
                .foregroundColor(KinnectTheme.textPrimary)
            Text(isSelf ? "Cập nhật hồ sơ để mọi người hiểu bạn hơn." : "Thành viên này chưa chia sẻ thông tin giới thiệu.")
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
        return "Tham gia Kinnect từ " + formatter.string(from: date)
    }

    @ViewBuilder
    private func aboutTabContent(user: KinnectUser) -> some View {
        VStack(spacing: 14) {
            // Bio & Details Card (Parity Android MainActivity.java:2329-2346 profileAbout)
            VStack(alignment: .leading, spacing: 0) {
                // Header: "Giới thiệu", globe icon, "Công khai"
                HStack {
                    Text("Giới thiệu")
                        .font(.headline.weight(.bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                    Spacer()
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Text(user.isPrivate ? "Riêng tư" : "Công khai")
                        .font(.caption2.bold())
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(.bottom, 12)

                // 0. Tiểu sử (Bio)
                if isFieldVisible(key: "bio", user: user) && !user.bio.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tiểu sử")
                            .font(KinnectTheme.scaled(12))
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text(user.bio)
                            .font(KinnectTheme.scaled(14))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .kinnectMultiline()
                    }
                    .padding(.vertical, 8)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // Canonical Identity & Details List (matching Android lines 2338-2339)
                // 1. Tuổi
                if isFieldVisible(key: "age", user: user) && user.age > 0 {
                    profileDetailRow(label: "Tuổi", value: "\(user.age) tuổi")
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 2. Nơi sống
                let displayCity = user.city.isEmpty ? user.locationName : user.city
                if isFieldVisible(key: "city", user: user) && !displayCity.isEmpty {
                    profileDetailRow(label: "Nơi sống", value: displayCity)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 3. Chiều cao
                if isFieldVisible(key: "height", user: user) && user.height > 0 {
                    profileDetailRow(label: "Chiều cao", value: "\(user.height) cm")
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 4. Cân nặng
                if isFieldVisible(key: "weight", user: user) && user.weight > 0 {
                    profileDetailRow(label: "Cân nặng", value: "\(user.weight) kg")
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 5. Nghề nghiệp
                if isFieldVisible(key: "occupation", user: user) && !user.occupation.isEmpty {
                    profileDetailRow(label: "Nghề nghiệp", value: user.occupation)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 6. Trường học
                if isFieldVisible(key: "school", user: user) && !user.school.isEmpty {
                    profileDetailRow(label: "Trường học", value: user.school)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // Giới tính & Bản sắc LGBT (Android parity: Bản dạng giới, Xu hướng, Vai trò cộng đồng, Cách xưng hô)
                // 7. Bản dạng giới
                if isFieldVisible(key: "gender", user: user) && !user.gender.isEmpty {
                    profileDetailRow(label: "Bản dạng giới", value: localizedIdentityValue("gender", user.gender))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 8. Xu hướng
                if isFieldVisible(key: "orientation", user: user) && !user.orientation.isEmpty {
                    profileDetailRow(label: "Xu hướng", value: localizedIdentityValue("orientation", user.orientation))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 9. Vai trò cộng đồng
                if isFieldVisible(key: "communityRole", user: user) && !user.communityRole.isEmpty {
                    profileDetailRow(label: "Vai trò cộng đồng", value: localizedIdentityValue("communityRole", user.communityRole))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 10. Cách xưng hô
                if isFieldVisible(key: "pronouns", user: user) && !user.pronouns.isEmpty {
                    profileDetailRow(label: "Cách xưng hô", value: localizedIdentityValue("pronouns", user.pronouns))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 11. Tình trạng quan hệ
                if isFieldVisible(key: "relationshipRole", user: user) && !user.relationshipRole.isEmpty {
                    profileDetailRow(label: "Tình trạng quan hệ", value: localizedIdentityValue("relationshipRole", user.relationshipRole))
                    Divider().background(KinnectTheme.borderSoft)
                }

                // 12. Mong muốn
                if isFieldVisible(key: "lookingFor", user: user) && !user.lookingFor.isEmpty {
                    profileDetailRow(label: "Mong muốn", value: user.lookingFor)
                    Divider().background(KinnectTheme.borderSoft)
                }

                // Sở thích (Interests Tags)
                if isFieldVisible(key: "interests", user: user) && !user.interests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sở thích")
                            .font(KinnectTheme.scaled(12))
                            .foregroundColor(KinnectTheme.textSecondary)
                        WrappingHStack(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(user.interests, id: \.self) { item in
                                Text(item)
                                    .font(KinnectTheme.scaled(13, weight: .medium))
                                    .foregroundColor(KinnectTheme.accentBright)
                                    .padding(.horizontal, 12)
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
                        .font(KinnectTheme.scaled(12))
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
            let myPosts = userPosts.filter { $0.author.id == user.id }
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
                    PostCardView(
                        post: post,
                        currentUserId: appState.currentUser?.id ?? "",
                        isAuthorOnline: !isSelf && user.showActivity && appState.onlineUserIds.contains(user.id),
                        onReact: { reaction in
                            Task {
                                do {
                                    let remove = post.liked && post.userReaction == reaction
                                    _ = try await KinnectAPIClient.shared.requestJSON(
                                        "/api/posts/\(post.id)/like",
                                        method: remove ? "DELETE" : "POST",
                                        body: remove ? [:] : ["reaction": reaction])
                                    if isSelf { await refreshMe() }
                                    else { await refreshPeer(target: user) }
                                } catch { appState.showToast(error.localizedDescription) }
                            }
                        },
                        onOpenComments: { activeCommentsPost = post },
                        onDelete: {
                            Task {
                                do {
                                    _ = try await KinnectAPIClient.shared.requestJSON("/api/posts/\(post.id)", method: "DELETE")
                                    userPosts.removeAll { $0.id == post.id }
                                    appState.showToast("Đã xóa bài viết")
                                } catch { appState.showToast(error.localizedDescription) }
                            }
                        },
                        onReport: {
                            appState.activeReportContext = UGCReportContext(targetType: "post", targetId: post.id, targetUserId: post.author.id, targetTitle: "Bài viết của \(post.author.name)")
                        }
                    )
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
        let myShorts = userShorts.filter { $0.author.id == user.id }
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
                    .font(KinnectTheme.scaled(18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
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
            case "male", "nam": return "Nam"
            case "female", "nu", "nữ": return "Nữ"
            case "transgender_male", "trans_male", "nam chuyển giới": return "Nam chuyển giới"
            case "transgender_female", "trans_female", "nữ chuyển giới": return "Nữ chuyển giới"
            case "non_binary", "nonbinary", "phi nhị nguyên": return "Phi nhị nguyên"
            case "genderfluid", "linh hoạt giới": return "Linh hoạt giới"
            case "agender", "vô giới": return "Vô giới"
            case "questioning", "đang tìm hiểu": return "Đang tìm hiểu"
            case "other", "khác": return "Khác"
            default: return trimmed
            }
        case "orientation":
            switch trimmed.lowercased() {
            case "heterosexual", "straight", "dị tính": return "Dị tính"
            case "gay", "gay / đồng tính nam", "đồng tính nam": return "Gay / Đồng tính nam"
            case "lesbian", "lesbian / đồng tính nữ", "đồng tính nữ": return "Lesbian / Đồng tính nữ"
            case "bisexual", "song tính / bisexual", "song tính": return "Song tính / Bisexual"
            case "pansexual", "toàn tính / pansexual", "toàn tính": return "Toàn tính / Pansexual"
            case "asexual", "vô tính / asexual", "vô tính": return "Vô tính / Asexual"
            case "queer": return "Queer"
            case "demisexual", "á tính / demisexual", "á tính": return "Á tính / Demisexual"
            case "questioning", "đang tìm hiểu": return "Đang tìm hiểu"
            case "other", "khác": return "Khác"
            default: return trimmed
            }
        case "pronouns":
            switch trimmed.lowercased() {
            case "he", "him", "he/him", "anh": return "Anh"
            case "she", "her", "she/her", "chị": return "Chị"
            case "em": return "Em"
            case "you", "bạn": return "Bạn"
            case "they", "them", "they/them", "họ / they": return "Họ / They"
            default: return trimmed
            }
        case "relationshipRole":
            switch trimmed.lowercased() {
            case "single", "độc thân": return "Độc thân"
            case "dating", "đang tìm hiểu": return "Đang tìm hiểu"
            case "in_relationship", "đang trong mối quan hệ": return "Đang trong mối quan hệ"
            case "married", "đã kết hôn": return "Đã kết hôn"
            case "open_relationship", "mối quan hệ mở": return "Mối quan hệ mở"
            default: return trimmed
            }
        default:
            return trimmed
        }
    }

    private func profileDetailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(KinnectTheme.scaled(12))
                .foregroundColor(KinnectTheme.textSecondary)
            Text(value)
                .font(KinnectTheme.scaled(14))
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
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = uiImg.jpegData(compressionQuality: 0.72) else {
            appState.showToast("Không thể xử lý ảnh đã chọn.")
            return
        }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                endpoint,
                method: "POST",
                body: [field: dataURL],
                requestId: "upload_\(UUID().uuidString)"
            )
            if let userDict = res["user"] as? [String: Any] {
                appState.applyAuthenticatedUser(KinnectUser.from(userDict), rawDict: userDict)
            }
            appState.showToast("Đã cập nhật ảnh thành công!")
            await refreshMe()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func refreshMe() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me"),
           let userDict = res["user"] as? [String: Any] {
            let user = KinnectUser.from(userDict)
            appState.applyAuthenticatedUser(user, rawDict: userDict)
        }
        let myId = appState.currentUser?.id ?? "fixture_user_me"
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
                Text("Nhắn tin")
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
                Label(user.isFollowing ? "Bỏ theo dõi" : "Theo dõi", systemImage: "heart")
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
                        appState.showToast("Đã từ chối lời mời")
                    }
                } label: {
                    Label("Từ chối lời mời", systemImage: "xmark")
                }
            } else if peerFriendship == "friends" {
                Button(role: .destructive) {
                    Task {
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/users/\(user.id)/friendship",
                            method: "DELETE"
                        )
                        peerFriendship = "none"
                        appState.showToast("Đã hủy kết bạn")
                    }
                } label: {
                    Label("Huỷ kết bạn", systemImage: "person.badge.minus")
                }
            } else if peerFriendship == "outgoing" {
                Button {
                    Task {
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/users/\(user.id)/friend-request",
                            method: "DELETE"
                        )
                        peerFriendship = "none"
                        appState.showToast("Đã huỷ lời mời")
                    }
                } label: {
                    Label("Huỷ lời mời", systemImage: "xmark.circle")
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
                Label("Báo cáo hồ sơ", systemImage: "flag")
            }

            Button(role: .destructive) {
                Task {
                    await appState.blockUser(userId: user.id, userName: user.name)
                    dismiss()
                }
            } label: {
                Label("Chặn tài khoản", systemImage: "nosign")
            }
        } label: {
            KinnectIcon(glyph: .more, size: 18, tint: KinnectTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(KinnectTheme.surfaceElevated))
        }
        .accessibilityLabel("Tùy chọn hồ sơ")
    }

    @ViewBuilder
    private func peerActionsRow(user: KinnectUser) -> some View {
        HStack(spacing: 8) {
            peerFriendshipButton(user: user)
            peerMessageButton()
            peerMoreMenu(user: user)
        }
        .padding(.horizontal, 16)
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
