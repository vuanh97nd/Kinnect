import SwiftUI

enum KinnectNavTab: String, CaseIterable, Identifiable {
    case feed
    case discover
    case create
    case video
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Bảng tin"
        case .discover: return "Khám phá"
        case .create: return "Tạo"
        case .video: return "Video"
        case .live: return "Live"
        }
    }

    var glyph: KinnectGlyph {
        switch self {
        case .feed: return .feed
        case .discover: return .discover
        case .create: return .add
        case .video: return .video
        case .live: return .live
        }
    }

    var systemImage: String {
        switch self {
        case .feed: return "house.fill"
        case .discover: return "magnifyingglass"
        case .create: return "plus.circle.fill"
        case .video: return "play.rectangle.fill"
        case .live: return "dot.radiowaves.left.and.right"
        }
    }
}

enum KinnectTopSection: String, Identifiable {
    case notifications
    case store
    case wallet
    case friends
    case messages
    case profile

    var id: String { rawValue }
}

struct RootMainView: View {
    typealias TopSection = KinnectTopSection
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: KinnectNavTab = .feed
    @State private var activeTopSection: KinnectTopSection? = nil
    @State private var showCameraStudioSheet = false
    @State private var showProfileDetailSheet = false
    @State private var isShowingSplash = true
    @AppStorage("app_appearance_mode") private var appearanceMode: String = "system"

    private var activeColorScheme: ColorScheme? {
        if UIReviewFixture.forceLightMode { return .light }
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil // Follows system appearance (Light or Dark)
        }
    }

    // Shared leading brand logo for main tabs (Android parity: 40dp logo only)
    @ToolbarContentBuilder
    static func headerLeadingLogoStatic() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            KinnectBrandLogo(size: 36)
        }
    }

    @ToolbarContentBuilder
    private func headerLeadingLogo() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            KinnectBrandLogo(size: 36)
        }
    }

    // Shared trailing toolbar for all tabs (P1) - static version for UI Review Fixture
    @ToolbarContentBuilder
    static func headerTrailingButtonsStatic() -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Notifications
            Button { } label: {
                KinnectIcon(glyph: .notifications, size: 22, tint: KinnectTheme.textPrimary)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thông báo")

            // Store
            Button { } label: {
                KinnectIcon(glyph: .store, size: 22, tint: KinnectTheme.textPrimary)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cửa hàng")

            // Friends
            Button { } label: {
                KinnectIcon(glyph: .friends, size: 22, tint: KinnectTheme.textPrimary)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bạn bè")

            // Messages
            Button { } label: {
                KinnectIcon(glyph: .messages, size: 22, tint: KinnectTheme.textPrimary)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tin nhắn")

            // Profile
            Button { } label: {
                Circle()
                    .fill(KinnectTheme.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text("MA")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    )
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hồ sơ")
        }
    }
    @State private var fixturePrivatePhotos: [PrivatePhotoItem] = UIReviewFixture.mockPrivatePhotos()
    @State private var fixturePrivateRequests: [PrivateAccessRequestItem] = UIReviewFixture.mockPrivateRequests()
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all

        // Shared trailing toolbar for all tabs (P1) - instance version
    @ToolbarContentBuilder
        private func headerTrailingButtons() -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Notifications
            Button {
                activeTopSection = (activeTopSection == .notifications) ? nil : .notifications
            } label: {
                ZStack(alignment: .topTrailing) {
                    KinnectIcon(
                        glyph: .notifications,
                        size: 22,
                        selected: activeTopSection == .notifications,
                        tint: activeTopSection == .notifications ? KinnectTheme.accentBright : KinnectTheme.textPrimary
                    )
                    if appState.unreadNotificationsCount > 0 {
                        Circle()
                            .fill(KinnectTheme.danger)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thông báo")

            // Store
            Button {
                activeTopSection = (activeTopSection == .store) ? nil : .store
            } label: {
                KinnectIcon(
                    glyph: .store,
                    size: 22,
                    selected: activeTopSection == .store,
                    tint: activeTopSection == .store ? KinnectTheme.accentBright : KinnectTheme.textPrimary
                )
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cửa hàng")

            // Friends
            Button {
                activeTopSection = (activeTopSection == .friends) ? nil : .friends
            } label: {
                KinnectIcon(
                    glyph: .friends,
                    size: 22,
                    selected: activeTopSection == .friends,
                    tint: activeTopSection == .friends ? KinnectTheme.accentBright : KinnectTheme.textPrimary
                )
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bạn bè")

            // Messages
            Button {
                activeTopSection = (activeTopSection == .messages) ? nil : .messages
            } label: {
                ZStack(alignment: .topTrailing) {
                    KinnectIcon(
                        glyph: .messages,
                        size: 22,
                        selected: activeTopSection == .messages,
                        tint: activeTopSection == .messages ? KinnectTheme.accentBright : KinnectTheme.textPrimary
                    )
                    if appState.unreadMessagesCount > 0 {
                        Circle()
                            .fill(KinnectTheme.danger)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tin nhắn")

            // Profile
            Button {
                activeTopSection = (activeTopSection == .profile) ? nil : .profile
            } label: {
                if let u = appState.currentUser {
                    KinnectAvatarView(
                        name: u.name,
                        avatarURL: u.avatarUrl,
                        colorHex: u.avatarColor,
                        size: 28,
                        isOnline: false
                    )
                    .overlay(
                        Circle()
                            .stroke(activeTopSection == .profile ? KinnectTheme.accentBright : Color.clear, lineWidth: 2)
                    )
                } else {
                    KinnectIcon(
                        glyph: .profile,
                        size: 22,
                        selected: activeTopSection == .profile,
                        tint: activeTopSection == .profile ? KinnectTheme.accentBright : KinnectTheme.textPrimary
                    )
                }
            }
            .frame(width: 36, height: 44)
            .buttonStyle(.plain)
            .accessibilityLabel("Tài khoản")
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            KinnectTheme.background.ignoresSafeArea()

            if UIReviewFixture.activeScreen == "auth" || UIReviewFixture.activeScreen?.hasPrefix("auth-welcome") == true {
                AuthView(initialStage: .welcome)
            } else if UIReviewFixture.activeScreen?.hasPrefix("auth-login") == true {
                AuthView(initialStage: .login)
            } else if UIReviewFixture.activeScreen == "auth-register" {
                AuthView(initialStage: .register)
            } else if UIReviewFixture.activeScreen == "auth-reset" || UIReviewFixture.activeScreen == "auth-forgot" || UIReviewFixture.activeScreen == "forgot-password" {
                AuthView(initialStage: .forgotPassword)
            } else if isShowingSplash || (appState.isRestoringSession && appState.currentUser == nil) {
                KinnectSplashScreen()
            } else if appState.currentUser == nil {
                AuthView(initialStage: .welcome)
            } else if UIReviewFixture.activeScreen == "chat-detail" || UIReviewFixture.activeScreen == "chat-menu" || UIReviewFixture.activeScreen == "message-menu" {
                if horizontalSizeClass == .regular {
                    // iPad two-column layout: Conversation List on left + Chat Detail on right
                    VStack(spacing: 0) {
                                            NavigationSplitView(columnVisibility: $splitColumnVisibility) {
                                                NavigationStack {
                                                    MessagesView(onOpenFriends: { activeTopSection = .friends })
                                                }
                                                .navigationTitle("")
                                                .toolbar(.hidden, for: .navigationBar)
                                            } detail: {
                                                NavigationStack {
                                                    DirectChatDetailView(peer: KinnectUser.from(UIReviewFixture.peerUserDict))
                                                }
                                            }
                                            .navigationSplitViewStyle(.balanced)
                                        }
                                    } else {
                                        NavigationStack {
                                            DirectChatDetailView(peer: KinnectUser.from(UIReviewFixture.peerUserDict))
                                        }
                                    }
                                } else if UIReviewFixture.activeScreen == "camera-studio" || UIReviewFixture.activeScreen == "camera-studio-edit" || UIReviewFixture.activeScreen == "camera-studio-video-edit" {
                                    NavigationStack {
                                        CameraStudioView()
                                    }
                                } else if UIReviewFixture.activeScreen == "camera-studio-video" {
                                    NavigationStack {
                                        CameraStudioView(initialMode: .video)
                                    }
                                } else if UIReviewFixture.activeScreen == "studio-pro-sheet" {
                                    NavigationStack {
                                        StudioProSheet(
                                            appliedEffect: .constant("Cinematic Teal & Orange"),
                                            onApply: { _ in }
                                        )
                                    }
                                } else if UIReviewFixture.activeScreen == "group-chat-detail" {
                                    NavigationStack {
                                        GroupChatDetailView(group: ChatGroupItem.from(UIReviewFixture.fixtureGroupDict), onLeftGroup: {})
                                    }
                                } else if UIReviewFixture.activeScreen == "profile-edit" {
                                    EditProfileSheet(onSaved: {})
                                } else if UIReviewFixture.activeScreen == "profile-public-album" {
                                    PublicAlbumManageSheet(
                                        posts: UIReviewFixture.mockPosts(),
                                        onRefresh: {}
                                    )
                                } else if UIReviewFixture.activeScreen == "profile-private-album" {
                                    PrivateAlbumManageSheet(
                                        photos: $fixturePrivatePhotos,
                                        requests: $fixturePrivateRequests,
                                        onRefresh: {}
                                    )
                                } else if UIReviewFixture.activeScreen == "profile-sessions" {
                                    ActiveSessionsSheet()
                                } else if UIReviewFixture.activeScreen == "privacy-consent" {
                                    PrivacyConsentSheet(
                                        request: PrivacyConsentRequest(
                                            version: "2026.11",
                                            notice: "Chính sách quyền riêng tư và điều khoản dịch vụ Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam."
                                        ),
                                        recordOnServer: false,
                                        onAccepted: {}
                                    )
                                } else if UIReviewFixture.activeScreen == "delete-account" {
                                    DeleteAccountConfirmationSheet()
                                } else if UIReviewFixture.activeScreen == "ugc-report" {
                                    UGCReportSheet(
                                        context: UGCReportContext(
                                            targetType: "user",
                                            targetId: "fixture_user_peer",
                                            targetUserId: "fixture_user_peer",
                                            targetTitle: "Lê Hoàng Nam"
                                        )
                                    )
                                } else if UIReviewFixture.activeScreen == "forward-message" {
                                    ForwardMessageSheet(text: "Tin nhắn chia sẻ từ Bảng tin Kinnect", imageUrl: "")
                                } else if UIReviewFixture.activeScreen == "change-password" {
                                    ChangePasswordSheet()
                                } else if UIReviewFixture.activeScreen == "blocked-users" {
                                    BlockedUsersSheet()
                                } else if UIReviewFixture.activeScreen == "privacy-settings" {
                                    PrivacySettingsSheet()
                                } else if UIReviewFixture.activeScreen == "support" {
                                    SupportContactSheet()
                                } else if UIReviewFixture.activeScreen == "messages" {
                                    NavigationStack {
                                        MessagesView(initialScope: .direct, onOpenFriends: { activeTopSection = .friends })
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Tin nhắn")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "profile" {
                                    NavigationStack {
                                        ProfileView(onOpenWallet: { activeTopSection = .wallet }, onOpenFriends: { activeTopSection = .friends })
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Hồ sơ")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "profile-posts" {
                                    NavigationStack {
                                        ProfileView(onOpenWallet: { activeTopSection = .wallet }, onOpenFriends: { activeTopSection = .friends }, initialTab: .posts)
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Bài viết")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "profile-albums" {
                                    NavigationStack {
                                        ProfileView(onOpenWallet: { activeTopSection = .wallet }, onOpenFriends: { activeTopSection = .friends }, initialTab: .albums)
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Album ảnh")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "profile-videos" {
                                    NavigationStack {
                                        ProfileView(onOpenWallet: { activeTopSection = .wallet }, onOpenFriends: { activeTopSection = .friends }, initialTab: .videos)
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Video")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "friends" {
                                    NavigationStack {
                                        FriendsView(initialTab: .friends)
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Bạn bè")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "friends-requests" {
                                    NavigationStack {
                                        FriendsView(initialTab: .requests)
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Lời mời kết bạn")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "friends-suggestions" {
                                    NavigationStack {
                                        FriendsView(initialTab: .friends)
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Gợi ý kết bạn")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "notifications" {
                                    NavigationStack {
                                        NotificationsView()
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Thông báo")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "wallet" {
                                    NavigationStack {
                                        WalletView(onBack: { })
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Ví Kinnect")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "wallet-topup" {
                                    NavigationStack {
                                        WalletView(onBack: { })
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Nạp xu Kinnect")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else if UIReviewFixture.activeScreen == "wallet-packages" || UIReviewFixture.activeScreen == "store-packages" || UIReviewFixture.activeScreen == "store" {
                                    NavigationStack {
                                        StoreView(onBack: { }, onOpenWallet: { })
                                            .toolbar { RootMainView.headerTrailingButtonsStatic() }
                                            .navigationTitle("Cửa hàng Kinnect")
                                            .navigationBarTitleDisplayMode(.large)
                                    }
                                } else {
                                    authenticatedLayout
                                }

                                if webrtc.activeCall != nil {
                                    CallOverlayView()
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                        .zIndex(50)
                                }

                                if appState.currentLiveRoom != nil && appState.isCurrentLiveHost {
                                    LiveRoomFullScreenView()
                                        .transition(.move(edge: .bottom))
                                        .zIndex(40)
                                }

                                if let toast = appState.toastMessage {
                                    Text(toast)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(.white)
                                        .kinnectMultiline()
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(KinnectTheme.surfaceElevated)
                                                .overlay(Capsule().stroke(KinnectTheme.accentBright.opacity(0.6), lineWidth: 1))
                                        )
                                        .padding(.top, 12)
                                        .padding(.horizontal, 16)
                                        .zIndex(100)
                                }
                            }
                            .preferredColorScheme(activeColorScheme)
                            .modifier(UIReviewDynamicTypeModifier())
                            .task {
                                await appState.bootstrapSession()
                                if UIReviewFixture.isEnabled {
                                    isShowingSplash = false
                                } else {
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        isShowingSplash = false
                                    }
                                }
                                if let screen = UIReviewFixture.activeScreen {
                                    switch screen {
                                    case "feed":
                                        activeTopSection = nil
                                        selectedTab = .feed
                                    case "discover":
                                        activeTopSection = nil
                                        selectedTab = .discover
                                    case "shorts", "video":
                                        activeTopSection = nil
                                        selectedTab = .video
                                    case "live":
                                        activeTopSection = nil
                                        selectedTab = .live
                                    case "messages":
                                        activeTopSection = .messages
                                    case "profile", "profile-posts", "profile-albums", "profile-videos":
                                        activeTopSection = .profile
                                    case "friends", "friends-requests", "friends-suggestions":
                                        activeTopSection = .friends
                                    case "notifications":
                                        activeTopSection = .notifications
                                    case "wallet", "wallet-topup", "wallet-packages":
                                        activeTopSection = .wallet
                                    default:
                                        break
                                    }
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .kinnectNavigateRoute)) { notif in
                                guard let route = notif.object as? String else { return }
                                switch route {
                                case "notifications":
                                    activeTopSection = .notifications
                                case "messages":
                                    activeTopSection = .messages
                                case "profile":
                                    activeTopSection = .profile
                                case "friends":
                                    activeTopSection = .friends
                                case "video", "shorts":
                                    activeTopSection = nil
                                    selectedTab = .video
                                case "feed":
                                    activeTopSection = nil
                                    selectedTab = .feed
                                default:
                                    break
                                }
                            }
                            .sheet(item: $appState.activeReportContext) { context in
                                UGCReportSheet(context: context)
                            }
                            .sheet(item: $appState.pendingPrivacyConsent) { req in
                                PrivacyConsentSheet(request: req, onAccepted: {})
                            }
                        }

    @ViewBuilder
    private var authenticatedLayout: some View {
        if horizontalSizeClass == .regular {
            iPadSplitView
        } else {
            iPhoneLayout
        }
    }

    private var iPadSplitView: some View {
        NavigationSplitView {
            List {
                Section("Điều hướng") {
                    ForEach(KinnectNavTab.allCases) { tab in
                        let isSelected = (activeTopSection == nil && selectedTab == tab)
                        Button {
                            activeTopSection = nil
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 12) {
                                KinnectIcon(
                                    glyph: tab.glyph,
                                    size: 26,
                                    selected: isSelected,
                                    tint: isSelected ? KinnectTheme.accentBright : KinnectTheme.textSecondary
                                )
                                Text(tab.title)
                                    .font(isSelected ? .body.weight(.bold) : .body.weight(.regular))
                                    .foregroundColor(isSelected ? KinnectTheme.accentBright : KinnectTheme.textPrimary)
                                    .kinnectMultiline()
                                Spacer()
                                if isSelected {
                                    Capsule()
                                        .fill(KinnectTheme.accentBright)
                                        .frame(width: 4, height: 18)
                                }
                            }
                            .padding(.vertical, 6)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        .listRowBackground(isSelected ? KinnectTheme.accent.opacity(0.22) : Color.clear)
                    }
                }

                Section("Liên lạc & Cá nhân") {
                    Button {
                        activeTopSection = .messages
                    } label: {
                        HStack(spacing: 12) {
                            KinnectIcon(glyph: .messages, size: 24, tint: KinnectTheme.accentBright)
                            Text("Tin nhắn")
                                .foregroundColor(KinnectTheme.textPrimary)
                            Spacer()
                            if appState.unreadMessagesCount > 0 {
                                badgePill(appState.unreadMessagesCount)
                            }
                        }
                        .frame(minHeight: 44)
                    }

                    Button {
                        activeTopSection = .profile
                    } label: {
                        HStack(spacing: 12) {
                            KinnectIcon(glyph: .profile, size: 24, tint: KinnectTheme.textPrimary)
                            Text("Hồ sơ cá nhân")
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                        .frame(minHeight: 44)
                    }
                }

                Section("Tiện ích") {
                    Button {
                        showCameraStudioSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            KinnectIcon(glyph: .camera, size: 24, tint: KinnectTheme.accentBright)
                            Text("Tạo ảnh / Video")
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                        .frame(minHeight: 44)
                    }
                    Button {
                        activeTopSection = .friends
                    } label: {
                        HStack(spacing: 12) {
                            KinnectIcon(glyph: .friends, size: 24, tint: KinnectTheme.textPrimary)
                            Text("Bạn bè")
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                        .frame(minHeight: 44)
                    }
                    Button {
                        activeTopSection = .notifications
                    } label: {
                        HStack(spacing: 12) {
                            KinnectIcon(glyph: .notifications, size: 24, tint: KinnectTheme.textPrimary)
                            Text("Thông báo")
                                .foregroundColor(KinnectTheme.textPrimary)
                            Spacer()
                            if appState.unreadNotificationsCount > 0 {
                                badgePill(appState.unreadNotificationsCount)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    Button {
                        activeTopSection = .wallet
                    } label: {
                        HStack(spacing: 12) {
                            KinnectIcon(glyph: .wallet, size: 24, tint: KinnectTheme.warning)
                            Text("Ví Kinnect & Cửa hàng Kinnect")
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.surface)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        } detail: {
            NavigationStack {
                mainSectionContent
                    .toolbar {
                        headerLeadingLogo()
                        headerTrailingButtons()
                    }
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var iPhoneLayout: some View {
        ZStack {
            VStack(spacing: 0) {
                if selectedTab == .feed || selectedTab == .discover {
                    KinnectTopBar(
                        appState: appState,
                        activeTopSection: $activeTopSection,
                        onLogoTap: {
                            selectedTab = .feed
                        }
                    )
                }

                ZStack {
                    switch selectedTab {
                    case .feed:
                        FeedView(
                            onOpenCamera: { showCameraStudioSheet = true },
                            onOpenFriends: { activeTopSection = .friends }
                        )
                    case .discover:
                        DiscoverView(onOpenCamera: { showCameraStudioSheet = true })
                    case .create:
                        CameraStudioView(onClose: { selectedTab = .feed })
                    case .video:
                        ShortsVideoView()
                    case .live:
                        LiveStreamView(onOpenWallet: { activeTopSection = .wallet })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Material 3 Bottom Navigation Bar (Android 1.2.12 lines 473-515)
                KinnectBottomBar(selectedTab: $selectedTab) {
                    showCameraStudioSheet = true
                }
            }

            // FULL SCREEN MAIN SECTIONS (TIN NHẮN, THÔNG BÁO, CỬA HÀNG & VÍ, BẠN BÈ, HỒ SƠ)
            if let section = activeTopSection {
                fullScreenSectionView(section)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
                    .zIndex(30)
            }

            // FULL SCREEN CAMERA STUDIO (TẠO ẢNH / VIDEO)
            if showCameraStudioSheet {
                CameraStudioView(onClose: { showCameraStudioSheet = false })
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom),
                        removal: .move(edge: .bottom)
                    ))
                    .zIndex(35)
            }

            // FULL SCREEN PROFILE DETAIL
            if showProfileDetailSheet {
                fullScreenProfileDetailView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
                    .zIndex(40)
            }
        }
    }

    @ViewBuilder
    private func fullScreenSectionView(_ section: KinnectTopSection) -> some View {
        switch section {
        case .store:
            StoreView(
                onBack: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        activeTopSection = nil
                    }
                },
                onOpenWallet: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        activeTopSection = .wallet
                    }
                }
            )
        case .wallet:
            WalletView(
                onBack: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        activeTopSection = nil
                    }
                },
                onOpenStore: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        activeTopSection = .store
                    }
                }
            )
        case .notifications:
            NotificationsView(
                onBack: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        activeTopSection = nil
                    }
                },
                onOpenFriends: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        activeTopSection = .friends
                    }
                },
                onOpenMessages: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        activeTopSection = .messages
                    }
                }
            )
        default:
            VStack(spacing: 0) {
                sectionCustomHeader(section)

                Group {
                    switch section {
                    case .friends:
                        FriendsView(initialTab: .friends)
                    case .messages:
                        NavigationStack {
                            MessagesView(initialScope: .direct, onOpenFriends: { activeTopSection = .friends })
                        }
                    case .profile:
                        AccountMenuView(
                            onOpenProfile: {
                                showProfileDetailSheet = true
                            },
                            onOpenStore: {
                                activeTopSection = .store
                            },
                            onOpenWallet: {
                                activeTopSection = .wallet
                            },
                            onOpenFriends: {
                                activeTopSection = .friends
                            }
                        )
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(KinnectTheme.background.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private func sectionCustomHeader(_ section: KinnectTopSection) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    activeTopSection = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại")

            HStack(spacing: 8) {
                Text(sectionTitle(for: section))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .lineLimit(1)

                if section == .messages && appState.unreadMessagesCount > 0 {
                    badgePill(appState.unreadMessagesCount)
                }
                if section == .notifications && appState.unreadNotificationsCount > 0 {
                    badgePill(appState.unreadNotificationsCount)
                }
            }

            Spacer()

            sectionTrailingActions(section)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
        .overlay(
            Divider().background(KinnectTheme.borderSoft),
            alignment: .bottom
        )
    }

    private func sectionTitle(for section: KinnectTopSection) -> String {
        switch section {
        case .notifications: return "Thông báo"
        case .store: return "Cửa hàng"
        case .wallet: return "Ví Kinnect"
        case .friends: return "Bạn bè"
        case .messages: return "Tin nhắn"
        case .profile: return "Tài khoản"
        }
    }

    @ViewBuilder
    private func sectionTrailingActions(_ section: KinnectTopSection) -> some View {
        switch section {
        case .notifications:
            Button {
                Task {
                    await appState.refreshGlobalBadges()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Đã đọc")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(KinnectTheme.accentBright)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(KinnectTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đánh dấu tất cả đã đọc")

        case .store:
            if let user = appState.currentUser {
                Button {
                    activeTopSection = .wallet
                } label: {
                    HStack(spacing: 4) {
                        Text("🪙")
                            .font(.system(size: 13))
                        Text("\(user.coins) xu")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(KinnectTheme.warning)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xem ví Kinnect")
            }

        case .wallet:
            if let user = appState.currentUser {
                HStack(spacing: 4) {
                    Text("🪙")
                        .font(.system(size: 13))
                    Text("\(user.coins) xu")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(KinnectTheme.warning)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(KinnectTheme.surfaceElevated))
            }

        case .messages:
            Menu {
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("kinnect_open_new_chat"), object: nil)
                } label: {
                    Label("Tin nhắn mới", systemImage: "square.and.pencil")
                }
                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("kinnect_open_create_group"), object: nil)
                } label: {
                    Label("Tạo nhóm mới", systemImage: "person.3")
                }
            } label: {
                KinnectIcon(glyph: .add, size: 20, tint: KinnectTheme.accentBright)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
            }
            .accessibilityLabel("Tùy chọn tin nhắn mới")

        case .friends:
            Button {
                activeTopSection = .messages
            } label: {
                KinnectIcon(glyph: .messages, size: 20, tint: KinnectTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tin nhắn bạn bè")

        case .profile:
            Button {
                showProfileDetailSheet = true
            } label: {
                Text("Xem hồ sơ")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(KinnectTheme.accentBright)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xem hồ sơ đầy đủ")
        }
    }

    private var fullScreenProfileDetailView: some View {
        ProfileView(
            onBack: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showProfileDetailSheet = false
                }
            },
            onOpenWallet: {
                showProfileDetailSheet = false
                activeTopSection = .wallet
            },
            onOpenFriends: {
                showProfileDetailSheet = false
                activeTopSection = .friends
            },
            onOpenStore: {
                showProfileDetailSheet = false
                activeTopSection = .store
            }
        )
        .background(KinnectTheme.background.ignoresSafeArea())
    }

                        @ViewBuilder
                        private var mainSectionContent: some View {
                            if let topSection = activeTopSection {
                                switch topSection {
                                case .notifications:
                                    NotificationsView()
                                case .store:
                                    StoreView(
                                        onBack: { activeTopSection = nil },
                                        onOpenWallet: { activeTopSection = .wallet }
                                    )
                                case .wallet:
                                    WalletView(
                                        onBack: { activeTopSection = nil },
                                        onOpenStore: { activeTopSection = .store }
                                    )
                                case .friends:
                                    FriendsView()
                                case .messages:
                                    MessagesView(onOpenFriends: { activeTopSection = .friends })
                                case .profile:
                                    ProfileView(
                                        onOpenWallet: { activeTopSection = .wallet },
                                        onOpenFriends: { activeTopSection = .friends },
                                        onOpenStore: { activeTopSection = .store }
                                    )
                                }
                            } else {
                                tabContent(for: selectedTab)
                            }
                        }

                        @ViewBuilder
                        private func tabContent(for tab: KinnectNavTab) -> some View {
                            switch tab {
                            case .feed:
                                FeedView(
                                    onOpenCamera: { showCameraStudioSheet = true },
                                    onOpenFriends: { activeTopSection = .friends }
                                )
                            case .discover:
                                DiscoverView(onOpenCamera: { showCameraStudioSheet = true })
                            case .create:
                                CameraStudioView()
                            case .video:
                                ShortsVideoView()
                            case .live:
                                LiveStreamView(onOpenWallet: { activeTopSection = .wallet })
                            }
                        }

                        private func badgePill(_ count: Int) -> some View {
                            Text("\(min(count, 99))")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(KinnectTheme.danger))
                        }
                    }

                    struct UGCReportSheet: View {
                        let context: UGCReportContext
                        @Environment(\.dismiss) private var dismiss
                        @ObservedObject private var appState = AppState.shared

                        @State private var selectedReason = "Nội dung không phù hợp / phản cảm"
                        @State private var details = ""
                        @State private var alsoBlockUser = false
                        @State private var isSubmitting = false

                        private let reasons = [
                            "Nội dung không phù hợp / phản cảm",
                            "Quấy rối, đe dọa hoặc xúc phạm",
                            "Lừa đảo hoặc giả mạo",
                            "Spam hoặc quảng cáo trái phép",
                            "Vi phạm bản quyền / quyền riêng tư"
                        ]

                        var body: some View {
                            NavigationStack {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 16) {
                                        HStack(spacing: 10) {
                                            KinnectIcon(glyph: .report, size: 24, selected: true, tint: KinnectTheme.danger)
                                            Text("Báo cáo vi phạm: \(context.targetTitle)")
                                                .font(.headline)
                                                .foregroundColor(KinnectTheme.textPrimary)
                                                .kinnectMultiline()
                                        }

                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Lý do báo cáo")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(KinnectTheme.textSecondary)

                                            ForEach(reasons, id: \.self) { reason in
                                                Button {
                                                    selectedReason = reason
                                                } label: {
                                                    HStack(spacing: 10) {
                                                        Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                                                            .foregroundColor(selectedReason == reason ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                                                        Text(reason)
                                                            .font(.subheadline)
                                                            .foregroundColor(KinnectTheme.textPrimary)
                                                            .kinnectMultiline()
                                                        Spacer()
                                                    }
                                                    .padding(10)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .fill(KinnectTheme.surfaceElevated)
                                                    )
                                                }
                                            }
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Chi tiết bổ sung (tùy chọn)")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(KinnectTheme.textSecondary)

                                            TextField("Mô tả thêm...", text: $details, axis: .vertical)
                                                .lineLimit(3...6)
                                                .padding(12)
                                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                                .foregroundColor(KinnectTheme.textPrimary)
                                        }

                                        if let uid = context.targetUserId, !uid.isEmpty, uid != appState.currentUser?.id {
                                            Toggle(isOn: $alsoBlockUser) {
                                                HStack(spacing: 8) {
                                                    KinnectIcon(glyph: .block, size: 20, tint: KinnectTheme.danger)
                                                    Text("Đồng thời chặn người dùng này và ẩn toàn bộ nội dung của họ")
                                                        .font(.subheadline)
                                                        .foregroundColor(KinnectTheme.textPrimary)
                                                        .kinnectMultiline()
                                                }
                                            }
                                            .tint(KinnectTheme.danger)
                                        }

                                        Button {
                                            Task { await submitReport() }
                                        } label: {
                                            HStack {
                                                Spacer()
                                                if isSubmitting {
                                                    ProgressView().tint(.white)
                                                } else {
                                                    Text("Gửi báo cáo")
                                                        .font(.headline)
                                                }
                                                Spacer()
                                            }
                                            .padding(.vertical, 14)
                                            .background(KinnectTheme.primaryGradient)
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                        }
                                        .disabled(isSubmitting)
                                    }
                                    .padding(16)
                                }
                                .background(KinnectTheme.background)
                                .navigationTitle("Báo cáo UGC")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Đóng") { dismiss() }
                                    }
                                }
                            }
                        }

                        private func submitReport() async {
                            isSubmitting = true
                            defer { isSubmitting = false }
                            let reqId = "report_\(context.targetType)_\(context.targetId)_\(Int(Date().timeIntervalSince1970))"
                            do {
                                _ = try await KinnectAPIClient.shared.requestJSON(
                                    "/api/reports",
                                    method: "POST",
                                    body: [
                                        "targetType": context.targetType,
                                        "targetId": context.targetId,
                                        "reason": selectedReason,
                                        "details": details
                                    ],
                                    requestId: reqId
                                )
                                if alsoBlockUser, let uid = context.targetUserId, !uid.isEmpty {
                                    await appState.blockUser(userId: uid, userName: context.targetTitle)
                                } else {
                                    appState.showToast("Đã gửi báo cáo vi phạm. Cảm ơn bạn đã giữ cộng đồng an toàn.")
                                }
                                dismiss()
                            } catch {
                                appState.showToast(error.localizedDescription)
                            }
                        }
                    }

                    private struct UIReviewDynamicTypeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if UIReviewFixture.forceMaxDynamicType {
            content.dynamicTypeSize(...DynamicTypeSize.accessibility2)
        } else if UIReviewFixture.isEnabled {
            content.dynamicTypeSize(.large)
        } else {
            content
        }
    }
}
