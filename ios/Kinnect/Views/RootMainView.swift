import SwiftUI

enum KinnectNavTab: String, CaseIterable, Identifiable {
    case feed
    case discover
    case live
    case messages
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Bảng tin"
        case .discover: return "Khám phá"
        case .live: return "Live"
        case .messages: return "Tin nhắn"
        case .profile: return "Hồ sơ"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "sparkles.rectangle.stack.fill"
        case .discover: return "safari.fill"
        case .live: return "dot.radiowaves.left.and.right"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

struct RootMainView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab: KinnectNavTab = .feed
    @State private var showFriendsSheet = false
    @State private var showNotificationsSheet = false
    @State private var showCameraStudioSheet = false
    @State private var showWalletStoreSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            KinnectTheme.background.ignoresSafeArea()

            if appState.isRestoringSession && appState.currentUser == nil {
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
            } else {
                authenticatedLayout
            }

            if webrtc.activeCall != nil {
                CallOverlayView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(50)
            }

            if appState.currentLiveRoom != nil {
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
        .preferredColorScheme(.dark)
        .task {
            await appState.bootstrapSession()
        }
        .sheet(item: $appState.activeReportContext) { context in
            UGCReportSheet(context: context)
        }
        .sheet(isPresented: $showFriendsSheet) {
            NavigationStack {
                FriendsView()
            }
        }
        .sheet(isPresented: $showNotificationsSheet) {
            NavigationStack {
                NotificationsView()
            }
        }
        .sheet(isPresented: $showCameraStudioSheet) {
            NavigationStack {
                CameraStudioView()
            }
        }
        .sheet(isPresented: $showWalletStoreSheet) {
            NavigationStack {
                WalletStoreView()
            }
        }
    }

    @ViewBuilder
    private var authenticatedLayout: some View {
        if horizontalSizeClass == .regular {
            // iPad / landscape split view
            NavigationSplitView {
                List {
                    Section("Điều hướng") {
                        ForEach(KinnectNavTab.allCases) { tab in
                            Button {
                                selectedTab = tab
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: tab.icon)
                                        .foregroundColor(selectedTab == tab ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                                        .frame(width: 24)
                                    Text(tab.title)
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .kinnectMultiline()
                                    Spacer()
                                    if tab == .messages && appState.unreadMessagesCount > 0 {
                                        badgePill(appState.unreadMessagesCount)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(selectedTab == tab ? KinnectTheme.accent.opacity(0.22) : Color.clear)
                        }
                    }

                    Section("Tiện ích") {
                        Button {
                            showCameraStudioSheet = true
                        } label: {
                            Label("Tạo ảnh / Video", systemImage: "camera.aperture")
                        }
                        Button {
                            showFriendsSheet = true
                        } label: {
                            Label("Bạn bè", systemImage: "person.2.fill")
                        }
                        Button {
                            showNotificationsSheet = true
                        } label: {
                            HStack {
                                Label("Thông báo", systemImage: "bell.fill")
                                Spacer()
                                if appState.unreadNotificationsCount > 0 {
                                    badgePill(appState.unreadNotificationsCount)
                                }
                            }
                        }
                        Button {
                            showWalletStoreSheet = true
                        } label: {
                            Label("Ví & Cửa hàng", systemImage: "creditcard.fill")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(KinnectTheme.surface)
                .navigationTitle("Kinnect")
            } detail: {
                NavigationStack {
                    tabContent(for: selectedTab)
                        .toolbar {
                            topToolbarItems
                        }
                }
            }
        } else {
            // iPhone compact TabView
            TabView(selection: $selectedTab) {
                ForEach(KinnectNavTab.allCases) { tab in
                    NavigationStack {
                        tabContent(for: tab)
                            .toolbar {
                                topToolbarItems
                            }
                    }
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .badge(tab == .messages ? appState.unreadMessagesCount : 0)
                    .tag(tab)
                }
            }
            .tint(KinnectTheme.accentBright)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: KinnectNavTab) -> some View {
        switch tab {
        case .feed:
            FeedView(
                onOpenCamera: { showCameraStudioSheet = true },
                onOpenFriends: { showFriendsSheet = true }
            )
        case .discover:
            DiscoverView(onOpenCamera: { showCameraStudioSheet = true })
        case .live:
            LiveStreamView(onOpenWallet: { showWalletStoreSheet = true })
        case .messages:
            MessagesView(onOpenFriends: { showFriendsSheet = true })
        case .profile:
            ProfileView(
                onOpenWallet: { showWalletStoreSheet = true },
                onOpenFriends: { showFriendsSheet = true }
            )
        }
    }

    @ToolbarContentBuilder
    private var topToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                showCameraStudioSheet = true
            } label: {
                Image(systemName: "plus.viewfinder")
                    .foregroundColor(KinnectTheme.accentBright)
            }
            .accessibilityLabel("Tạo nội dung")

            Button {
                showFriendsSheet = true
            } label: {
                Image(systemName: "person.2.fill")
                    .foregroundColor(KinnectTheme.textPrimary)
            }
            .accessibilityLabel("Bạn bè")

            Button {
                showWalletStoreSheet = true
            } label: {
                Image(systemName: "bag.fill")
                    .foregroundColor(KinnectTheme.warning)
            }
            .accessibilityLabel("Ví & Cửa hàng")

            Button {
                showNotificationsSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(KinnectTheme.textPrimary)
                    if appState.unreadNotificationsCount > 0 {
                        Circle()
                            .fill(KinnectTheme.danger)
                            .frame(width: 9, height: 9)
                            .offset(x: 4, y: -3)
                    }
                }
            }
            .accessibilityLabel("Thông báo")
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
                    Text("Báo cáo vi phạm: \(context.targetTitle)")
                        .font(.headline)
                        .foregroundColor(KinnectTheme.textPrimary)
                        .kinnectMultiline()

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
                            Text("Đồng thời chặn người dùng này và ẩn toàn bộ nội dung của họ")
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textPrimary)
                                .kinnectMultiline()
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

