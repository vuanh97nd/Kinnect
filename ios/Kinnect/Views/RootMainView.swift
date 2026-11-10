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
    case wallet
    case friends
    case messages
    case profile

    var id: String { rawValue }
}

struct RootMainView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: KinnectNavTab = .feed
    @State private var activeTopSection: KinnectTopSection? = nil
    @State private var showCameraStudioSheet = false
    @State private var fixturePrivatePhotos: [PrivatePhotoItem] = UIReviewFixture.mockPrivatePhotos()
    @State private var fixturePrivateRequests: [PrivateAccessRequestItem] = UIReviewFixture.mockPrivateRequests()
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all

    // Shared trailing toolbar for all tabs (P1)
    @ToolbarContentBuilder
    private var headerTrailingButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
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
                activeTopSection = (activeTopSection == .wallet) ? nil : .wallet
            } label: {
                KinnectIcon(
                    glyph: .store,
                    size: 22,
                    selected: activeTopSection == .wallet,
                    tint: activeTopSection == .wallet ? KinnectTheme.accentBright : KinnectTheme.textPrimary
                )
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ví Kinnect và Cửa hàng Kinnect")

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
            } else if appState.isRestoringSession && appState.currentUser == nil {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(KinnectTheme.accentBright)
                        .scaleEffect(1.3)
                    Text("Đang kết nối Kinnect...")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                }
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
                            .preferredColorScheme(UIReviewFixture.forceLightMode ? .light : .dark)
                            .modifier(UIReviewDynamicTypeModifier())
                            .task {
                                await appState.bootstrapSession()
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
                            .sheet(isPresented: $showCameraStudioSheet) {
                                NavigationStack {
                                    CameraStudioView()
                                }
                            }
                        }

                        @ViewBuilder
                        private var authenticatedLayout: some View {
                            if horizontalSizeClass == .regular {
                                // iPad / landscape split view with sidebar navigation
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
                                            .navigationTitle("")
                                            .toolbar(.hidden, for: .navigationBar)
                                    }
                                }
                            } else {
                                // iPhone compact layout with native TabView (5 tabs) + shared trailing toolbar
                                TabView(selection: $selectedTab) {
                                    NavigationStack {
                                                                            FeedView(
                                                                                onOpenCamera: { showCameraStudioSheet = true },
                                                                                onOpenFriends: { activeTopSection = .friends }
                                                                            )
                                                                            .toolbar(headerTrailingButtons)
                                                                            .navigationTitle("Bảng tin")
                                        .navigationBarTitleDisplayMode(.large)
                                    }
                                    .tag(KinnectNavTab.feed)
                                    .tabItem {
                                        Label("Bảng tin", systemImage: "house.fill")
                                    }

                                    NavigationStack {
                                                                            DiscoverView(onOpenCamera: { showCameraStudioSheet = true })
                                                                            .toolbar(headerTrailingButtons)
                                                                            .navigationTitle("Khám phá")
                                        .navigationBarTitleDisplayMode(.large)
                                    }
                                    .tag(KinnectNavTab.discover)
                                    .tabItem {
                                        Label("Khám phá", systemImage: "magnifyingglass")
                                    }

                                    NavigationStack {
                                                                            CameraStudioView()
                                                                            .toolbar(headerTrailingButtons)
                                                                            .navigationTitle("Tạo")
                                        .navigationBarTitleDisplayMode(.large)
                                    }
                                    .tag(KinnectNavTab.create)
                                    .tabItem {
                                        Label("Tạo", systemImage: "plus.circle.fill")
                                    }

                                    NavigationStack {
                                                                            ShortsVideoView()
                                                                            .toolbar(headerTrailingButtons)
                                                                            .navigationTitle("Video")
                                        .navigationBarTitleDisplayMode(.large)
                                    }
                                    .tag(KinnectNavTab.video)
                                    .tabItem {
                                        Label("Video", systemImage: "play.rectangle.fill")
                                    }

                                    NavigationStack {
                                                                            LiveStreamView(onOpenWallet: { activeTopSection = .wallet })
                                                                            .toolbar(headerTrailingButtons)
                                                                            .navigationTitle("Live")
                                        .navigationBarTitleDisplayMode(.large)
                                    }
                                    .tag(KinnectNavTab.live)
                                    .tabItem {
                                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                                    }
                                }
                                .onChange(of: selectedTab) { _, newTab in
                                    // Haptic feedback on tab selection (P1)
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }
                                .toolbarBackground(KinnectTheme.surface, for: .tabBar)
                                .toolbarBackground(.visible, for: .tabBar)
                                .toolbarColorScheme(.dark, for: .tabBar)
                            }
                        }

                        @ViewBuilder
                        private var mainSectionContent: some View {
                            if let topSection = activeTopSection {
                                switch topSection {
                                case .notifications:
                                    NotificationsView()
                                case .wallet:
                                    WalletStoreView()
                                case .friends:
                                    FriendsView()
                                case .messages:
                                    MessagesView(onOpenFriends: { activeTopSection = .friends })
                                case .profile:
                                    ProfileView(
                                        onOpenWallet: { activeTopSection = .wallet },
                                        onOpenFriends: { activeTopSection = .friends }
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
            content.dynamicTypeSize(.accessibility5)
        } else if UIReviewFixture.isEnabled {
            content.dynamicTypeSize(.large)
        } else {
            content
        }
    }
}
