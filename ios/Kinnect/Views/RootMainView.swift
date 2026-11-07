import SwiftUI

enum KinnectNavTab: String, CaseIterable, Identifiable {
    case feed
    case discover
    case video
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Bảng tin"
        case .discover: return "Khám phá"
        case .video: return "Video"
        case .live: return "Live"
        }
    }

    var glyph: KinnectGlyph {
        switch self {
        case .feed: return .feed
        case .discover: return .discover
        case .video: return .video
        case .live: return .live
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
    @State private var fixturePrivatePhotos: [PrivatePhotoItem] = []
    @State private var fixturePrivateRequests: [PrivateAccessRequestItem] = []
    @State private var splitColumnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack(alignment: .top) {
            KinnectTheme.background.ignoresSafeArea()

            if UIReviewFixture.activeScreen == "auth" {
                AuthView()
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
                AuthView()
            } else if UIReviewFixture.activeScreen == "chat-detail" {
                if horizontalSizeClass == .regular {
                    // iPad two-column layout: Conversation List on left + Chat Detail on right
                    VStack(spacing: 0) {
                        globalHeaderBar
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
            } else if UIReviewFixture.activeScreen == "camera-studio" || UIReviewFixture.activeScreen == "camera-studio-edit" {
                NavigationStack {
                    CameraStudioView()
                }
            } else if UIReviewFixture.activeScreen == "profile-edit" {
                EditProfileSheet(onSaved: {})
            } else if UIReviewFixture.activeScreen == "profile-private-album" {
                PrivateAlbumManageSheet(
                    photos: $fixturePrivatePhotos,
                    requests: $fixturePrivateRequests,
                    onRefresh: {}
                )
            } else if UIReviewFixture.activeScreen == "profile-sessions" {
                ActiveSessionsSheet()
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
                case "friends":
                    activeTopSection = .friends
                case "notifications":
                    activeTopSection = .notifications
                case "wallet":
                    activeTopSection = .wallet
                default:
                    break
                }
            }
        }
        .sheet(item: $appState.activeReportContext) { context in
            UGCReportSheet(context: context)
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
            // iPad / landscape split view with shared K brand header (no text beside K)
            VStack(spacing: 0) {
                globalHeaderBar

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
                                    Text("Ví & Cửa hàng")
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
            }
        } else {
            // iPhone compact layout with shared K brand header at top and 5-tab bar at bottom
            VStack(spacing: 0) {
                globalHeaderBar

                NavigationStack {
                    mainSectionContent
                        .navigationTitle("")
                        .toolbar(.hidden, for: .navigationBar)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                compactBottomTabBar
            }
        }
    }

    private var globalHeaderBar: some View {
        HStack(spacing: 0) {
            Button {
                activeTopSection = nil
                selectedTab = .feed
            } label: {
                KinnectBrandLogo(size: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trang chủ Kinnect")

            Spacer()

            HStack(spacing: 4) {
                // 1. Thông báo / Notifications (bell) with unread badge
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

                // 2. Cửa hàng / Store
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
                .accessibilityLabel("Ví & Cửa hàng")

                // 3. Bạn bè / Friends
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

                // 4. Tin nhắn / Messages with unread badge
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

                // 5. Tài khoản / Current User circular Avatar
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
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(
            KinnectTheme.surface
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(KinnectTheme.border)
                        .frame(height: 1)
                }
        )
    }

    private var compactBottomTabBar: some View {
        HStack(spacing: 0) {
            // Tab 1: Bảng tin
            tabBarItem(tab: .feed)

            // Tab 2: Khám phá
            tabBarItem(tab: .discover)

            // Center (+): Camera & Studio Creation Button (Parity Android 1.2.12 MainActivity)
            Button {
                showCameraStudioSheet = true
            } label: {
                VStack(spacing: 2) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(KinnectTheme.primaryGradient)
                            .frame(width: 46, height: 38)
                            .shadow(color: KinnectTheme.accent.opacity(0.35), radius: 4, y: 2)

                        KinnectIcon(glyph: .add, size: 22, selected: true, tint: .white)
                    }
                    Text("Tạo")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(KinnectTheme.accentBright)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tạo nội dung")

            // Tab 3: Video (Shorts)
            tabBarItem(tab: .video)

            // Tab 4: Live
            tabBarItem(tab: .live)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(
            KinnectTheme.surface
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabBarItem(tab: KinnectNavTab) -> some View {
        let isSelected = (activeTopSection == nil && selectedTab == tab)
        return Button {
            activeTopSection = nil
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Capsule()
                    .fill(isSelected ? KinnectTheme.accentBright : Color.clear)
                    .frame(width: 20, height: 3)

                KinnectIcon(
                    glyph: tab.glyph,
                    size: 26,
                    selected: isSelected,
                    tint: isSelected ? KinnectTheme.accentBright : KinnectTheme.textSecondary
                )

                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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

