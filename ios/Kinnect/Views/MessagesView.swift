import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessagesView: View {
    let onOpenFriends: () -> Void
    var onBack: (() -> Void)? = nil
    @ObservedObject private var appState = AppState.shared

    enum ChatScope: String, CaseIterable {
        case direct = "Tin nhắn riêng"
        case groups = "Nhóm chat"
    }

    @State private var scope: ChatScope = .direct
    @State private var unreadOnly: Bool = false
    @State private var conversations: [[String: Any]] = []
    @State private var groups: [ChatGroupItem] = []
    @State private var showCreateGroupSheet = false
    @State private var showNewDirectChatSheet = false
    @State private var activeChatPeer: KinnectUser? = nil
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var searchQuery: String = ""

    init(initialScope: ChatScope = .direct, onOpenFriends: @escaping () -> Void = {}, onBack: (() -> Void)? = nil) {
        self.onOpenFriends = onOpenFriends
        self.onBack = onBack
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Header Bar (matching Android accountHeader pattern)
            PinnedHeaderBar(
                title: "Tin nhắn",
                onBack: onBack,
                trailingActions: [
                    PinnedHeaderBar.TrailingAction(
                        systemImage: scope == .direct ? "square.and.pencil" : "person.2.badge.plus",
                        accessibilityLabel: scope == .direct ? "Soạn tin nhắn mới" : "Tạo nhóm mới",
                        action: {
                            if scope == .direct {
                                showNewDirectChatSheet = true
                            } else {
                                showCreateGroupSheet = true
                            }
                        }
                    )
                ]
            )

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(KinnectTheme.messageMeta)
                TextField("Tìm cuộc trò chuyện…", text: $searchQuery)
                    .font(KinnectTheme.scaled(15))
                    .foregroundColor(KinnectTheme.textPrimary)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(KinnectTheme.messageMeta)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KinnectTheme.surfaceElevated))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Scope Segmented Control
            Picker("Loại tin nhắn", selection: $scope) {
                ForEach(ChatScope.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Filters: [Tất cả | Chưa đọc]
            if scope == .direct {
                HStack(spacing: 8) {
                    filterCapsule(title: "Tất cả", isSelected: !unreadOnly) {
                        unreadOnly = false
                    }
                    filterCapsule(title: "Chưa đọc", isSelected: unreadOnly) {
                        unreadOnly = true
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if scope == .direct {
                        let rows = filteredConversations
                        if let loadError, !rows.isEmpty {
                            KinnectErrorBanner(message: loadError) {
                                Task { await loadChats() }
                            }
                            .padding(.horizontal, KinnectTheme.spaceLG)
                            .padding(.vertical, KinnectTheme.spaceSM)
                        }
                        if isLoading && rows.isEmpty {
                            conversationSkeletonList
                        }
                        if rows.isEmpty && !isLoading {
                            if let loadError {
                                KinnectStateView(mode: .error(
                                    title: "Không tải được tin nhắn",
                                    message: loadError,
                                    retryTitle: "Thử lại",
                                    onRetry: { Task { await loadChats() } }
                                ))
                            } else {
                                emptyDirectView
                            }
                        }

                        ForEach(rows, id: \.0) { index, conv, peer in
                            NavigationLink {
                                DirectChatDetailView(peer: peer)
                            } label: {
                                directConversationRow(conv: conv, peer: peer)
                            }
                            .buttonStyle(.plain)

                            if index != rows.last?.0 {
                                Divider()
                                    .background(KinnectTheme.borderSoft.opacity(0.8))
                                    .padding(.leading, 82)
                            }
                        }
                    } else {
                        if let loadError, !groups.isEmpty {
                            KinnectErrorBanner(message: loadError) {
                                Task { await loadChats() }
                            }
                            .padding(.horizontal, KinnectTheme.spaceLG)
                            .padding(.vertical, KinnectTheme.spaceSM)
                        }
                        if isLoading && groups.isEmpty {
                            conversationSkeletonList
                        }
                        if groups.isEmpty && !isLoading {
                            if let loadError {
                                KinnectStateView(mode: .error(
                                    title: "Không tải được nhóm chat",
                                    message: loadError,
                                    retryTitle: "Thử lại",
                                    onRetry: { Task { await loadChats() } }
                                ))
                            } else {
                                emptyGroupsView
                            }
                        }

                        ForEach(groups) { group in
                            NavigationLink {
                                GroupChatDetailView(group: group) {
                                    Task { await loadChats() }
                                }
                            } label: {
                                groupConversationRow(group)
                            }
                            .buttonStyle(.plain)

                            if group.id != groups.last?.id {
                                Divider()
                                    .background(KinnectTheme.borderSoft.opacity(0.8))
                                    .padding(.leading, 82)
                            }
                        }
                    }
                }
            }
            .refreshable {
                await loadChats()
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadChats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectMessagesChanged)) { _ in
            Task { await loadChats() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kinnect_open_new_chat"))) { _ in
            showNewDirectChatSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kinnect_open_create_group"))) { _ in
            showCreateGroupSheet = true
        }
        .sheet(isPresented: $showNewDirectChatSheet) {
            NewDirectChatPickerSheet { peer in
                activeChatPeer = peer
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeChatPeer) { peer in
            NavigationStack {
                DirectChatDetailView(peer: peer)
            }
        }
        .sheet(isPresented: $showCreateGroupSheet) {
            CreateGroupSheet {
                Task { await loadChats() }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showCreateGroupSheet)
        }
    }

    private var filteredConversations: [(Int, [String: Any], KinnectUser)] {
        conversations.enumerated().compactMap { index, conv in
            let peer = extractPeer(from: conv)
            guard !peer.id.isEmpty && !appState.blockedUserIds.contains(peer.id) else { return nil }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                if !peer.name.lowercased().contains(q) && !peer.handle.lowercased().contains(q) {
                    return nil
                }
            }
            if unreadOnly {
                let unread = (conv["unread"] as? Int) ?? (conv["unreadCount"] as? Int) ?? 0
                if unread == 0 { return nil }
            }
            return (index, conv, peer)
        }
    }

    private func extractPeer(from conv: [String: Any]) -> KinnectUser {
        if let u = conv["user"] as? [String: Any] ?? conv["peer"] as? [String: Any] {
            return KinnectUser.from(u)
        }
        return KinnectUser.from(conv)
    }

    private func filterCapsule(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : KinnectTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                )
        }
        .buttonStyle(.plain)
    }

    private var emptyDirectView: some View {
        KEmptyState(
            systemImage: unreadOnly ? "tray" : "bubble.left.and.bubble.right",
            title: unreadOnly ? "Không có tin nhắn chưa đọc" : "Chưa có cuộc trò chuyện nào",
            message: unreadOnly
                ? "Bạn đã xem hết tin nhắn. Chuyển sang tab Tất cả để xem lại."
                : "Kết nối với người bạn quan tâm để bắt đầu trò chuyện.",
            actionTitle: unreadOnly ? nil : "Mở danh sách bạn bè",
            action: unreadOnly ? nil : onOpenFriends
        )
    }

    private var emptyGroupsView: some View {
        KEmptyState(
            systemImage: "person.3",
            title: "Chưa tham gia nhóm nào",
            message: "Tạo nhóm để trò chuyện cùng nhiều người trong một nơi.",
            actionTitle: "Tạo nhóm mới",
            action: { showCreateGroupSheet = true }
        )
    }

    // Skeleton khi đang tải lần đầu: giữ đúng nhịp của danh sách thật để không bị "nhảy" layout.
    private var conversationSkeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                HStack(spacing: KTSpace.md) {
                    KSkeleton(width: 48, height: 48)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: KTSpace.sm) {
                        KSkeleton(width: i % 2 == 0 ? 130 : 96, height: 13)
                        KSkeleton(width: i % 3 == 0 ? 200 : 150, height: 11)
                    }
                    Spacer(minLength: 0)
                    KSkeleton(width: 34, height: 10)
                }
                .padding(.horizontal, KTSpace.lg)
                .frame(height: 76)
                if i < 5 {
                    Divider().background(KinnectTheme.borderSoft.opacity(0.6)).padding(.leading, 82)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang tải danh sách trò chuyện")
    }

    private func directConversationRow(conv: [String: Any], peer: KinnectUser) -> some View {
        let lastObj = conv["last"] as? [String: Any]
        let lastMsg = (lastObj?["body"] as? String)
            ?? ((conv["lastMessage"] as? [String: Any])?["text"] as? String)
            ?? (conv["preview"] as? String)
            ?? "Nhấn để trò chuyện"
        let unread = (conv["unread"] as? Int) ?? (conv["unreadCount"] as? Int) ?? 0
        let rawTime = (lastObj?["createdAt"] as? String)
            ?? (conv["updatedAt"] as? String)
            ?? (conv["lastTime"] as? String)
            ?? ""
        let isOnline = appState.onlineUserIds.contains(peer.id) || (peer.isActive && peer.showActivity)

        return HStack(spacing: 14) {
            KinnectAvatarView(
                name: peer.name,
                avatarURL: peer.avatarUrl,
                colorHex: peer.avatarColor,
                size: 52,
                isOnline: isOnline
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(peer.name)
                        .font(.system(size: 16, weight: unread > 0 ? .bold : .semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if !rawTime.isEmpty {
                        Text(formatRelativeDate(rawTime))
                            .font(.system(size: 13, weight: unread > 0 ? .semibold : .regular))
                            .foregroundColor(unread > 0 ? KinnectTheme.accentBright : KinnectTheme.messageMeta)
                    }
                }

                HStack(alignment: .top) {
                    Text(lastMsg)
                        .font(.system(size: 14, weight: unread > 0 ? .medium : .regular))
                        .foregroundColor(unread > 0 ? KinnectTheme.textPrimary : KinnectTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    if unread > 0 {
                        Text("\(unread)")
                            .font(KinnectTheme.scaled(12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(KinnectTheme.messageBubbleGradient)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func groupConversationRow(_ group: ChatGroupItem) -> some View {
        HStack(spacing: 14) {
            KinnectAvatarView(
                name: group.name,
                avatarURL: "",
                colorHex: group.avatarColor,
                size: 52
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.system(size: 16, weight: group.unreadCount > 0 ? .bold : .semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                        Text("(\(group.membersCount))")
                            .font(KinnectTheme.scaled(13))
                            .foregroundColor(KinnectTheme.messageMeta)
                    }

                    Spacer(minLength: 8)

                    if !group.updatedAt.isEmpty {
                        Text(formatRelativeDate(group.updatedAt))
                            .font(.system(size: 13, weight: group.unreadCount > 0 ? .semibold : .regular))
                            .foregroundColor(group.unreadCount > 0 ? KinnectTheme.accentBright : KinnectTheme.messageMeta)
                    }
                }

                HStack(alignment: .top) {
                    Text(group.lastMessageText.isEmpty ? group.description : group.lastMessageText)
                        .font(.system(size: 14, weight: group.unreadCount > 0 ? .medium : .regular))
                        .foregroundColor(group.unreadCount > 0 ? KinnectTheme.textPrimary : KinnectTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    if group.unreadCount > 0 {
                        Text("\(group.unreadCount)")
                            .font(KinnectTheme.scaled(12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(KinnectTheme.messageBubbleGradient)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func loadChats() async {
        if conversations.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/conversations") {
            let list = (cached["users"] as? [[String: Any]]) ?? (cached["conversations"] as? [[String: Any]]) ?? []
            self.conversations = list
        }
        if groups.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/groups"),
           let grps = cached["groups"] as? [[String: Any]] {
            self.groups = grps.map(ChatGroupItem.from)
        }
        isLoading = true
        defer { isLoading = false }
        async let cTask = KinnectAPIClient.shared.requestJSON("/api/conversations")
        async let gTask = KinnectAPIClient.shared.requestJSON("/api/groups")

        var fetchError: String? = nil
        do {
            let cRes = try await cTask
            let list = (cRes["users"] as? [[String: Any]]) ?? (cRes["conversations"] as? [[String: Any]]) ?? []
            self.conversations = list
        } catch {
            fetchError = error.localizedDescription
        }
        do {
            let gRes = try await gTask
            self.groups = (gRes["groups"] as? [[String: Any]] ?? []).map(ChatGroupItem.from)
        } catch {
            if fetchError == nil {
                fetchError = error.localizedDescription
            }
        }
        self.loadError = fetchError
        await appState.refreshGlobalBadges()
    }
}
