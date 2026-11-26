import AVKit
import PhotosUI
import SwiftUI
import UIKit
import WebRTC
import UniformTypeIdentifiers

fileprivate func compressChatPhotoToDataURL(
    _ rawData: Data,
    maxDimension: CGFloat = 2048,
    maxBytes: Int = 4_500_000
) async -> String? {
    await Task.detached(priority: .userInitiated) {
        guard let original = UIImage(data: rawData) else { return nil }

        func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
            let size = image.size
            let longest = max(size.width, size.height)
            guard longest > maxSide, longest > 0 else { return image }
            let scale = maxSide / longest
            let targetSize = CGSize(
                width: max(1, floor(size.width * scale)),
                height: max(1, floor(size.height * scale))
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }

        var currentImage = resized(original, maxSide: maxDimension)
        let qualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42, 0.32]

        for pass in 0..<3 {
            if pass > 0 {
                let nextSide = max(640, max(currentImage.size.width, currentImage.size.height) * 0.75)
                currentImage = resized(currentImage, maxSide: nextSide)
            }
            for q in qualities {
                if let jpeg = currentImage.jpegData(compressionQuality: q), jpeg.count <= maxBytes {
                    return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                }
            }
        }
        return nil
    }.value
}

/// List refresh after the server mark-read on GET messages. Detail screens ignore this
/// userInfo so they do not call loadMessages again and post the same notice forever.
private func postMessagesMarkedRead(kind: String, id: String) {
    guard !id.isEmpty else { return }
    NotificationCenter.default.post(
        name: .kinnectMessagesChanged,
        object: nil,
        userInfo: [
            "markReadKind": kind,
            "markReadId": id
        ]
    )
}

private func chatSearchKey(_ raw: String) -> String {
    raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
        .replacingOccurrences(of: "đ", with: "d")
        .replacingOccurrences(of: "Đ", with: "d")
}

private func isoString(from anyVal: Any?) -> String {
    if let s = anyVal as? String, !s.isEmpty {
        return s
    }
    if let n = anyVal as? NSNumber {
        let ms = n.doubleValue
        let sec = ms > 10_000_000_000 ? (ms / 1000.0) : ms
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: sec))
    }
    return ""
}

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
    @State private var chatsLoadGeneration = 0
    @State private var notifRefreshTask: Task<Void, Never>? = nil
    @State private var groupMetaFlags: [String: (pinned: Bool, muted: Bool, lastMine: Bool)] = [:]
    @State private var pendingClearChat: (kind: String, id: String, name: String)? = nil

    init(initialScope: ChatScope = .direct, onOpenFriends: @escaping () -> Void = {}, onBack: (() -> Void)? = nil) {
        self.onOpenFriends = onOpenFriends
        self.onBack = onBack
        _scope = State(initialValue: initialScope)
        if let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/conversations") {
            let list = (cached["users"] as? [[String: Any]]) ?? (cached["conversations"] as? [[String: Any]]) ?? []
            _conversations = State(initialValue: list)
        }
        if let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/groups"),
           let grps = cached["groups"] as? [[String: Any]] {
            _groups = State(initialValue: grps.map(ChatGroupItem.from))
            _groupMetaFlags = State(initialValue: Self.extractGroupMetaFlags(from: grps))
        }
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
                    .font(.system(size: 15))
                    .foregroundColor(KinnectTheme.textPrimary)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(KinnectTheme.messageMeta)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Xóa từ khóa tìm kiếm")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, searchQuery.isEmpty ? 12 : 4)
            .frame(minHeight: 44)
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

            // Filters: [Tất cả | Chưa đọc] for both Direct and Groups
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

            ScrollView {
                LazyVStack(spacing: 0) {
                    if scope == .direct {
                        let rows = filteredConversations
                        if let loadError, conversations.isEmpty && !isLoading {
                            chatsLoadErrorView(loadError)
                        } else if rows.isEmpty && !isLoading {
                            emptyDirectView
                        }

                        ForEach(rows, id: \.0) { index, conv, peer in
                            let isConvPinned = (conv["pinned"] as? Bool) == true
                            let isConvMuted = (conv["muted"] as? Bool) == true
                            NavigationLink {
                                DirectChatDetailView(peer: peer)
                            } label: {
                                directConversationRow(conv: conv, peer: peer)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    Task { await updateInboxPreference(kind: "direct", id: peer.id, body: ["pinned": !isConvPinned], toast: isConvPinned ? "Đã bỏ ghim." : "Đã ghim hội thoại.") }
                                } label: {
                                    Label(isConvPinned ? "Bỏ ghim hội thoại" : "Ghim hội thoại", systemImage: isConvPinned ? "pin.slash" : "pin")
                                }
                                Button {
                                    Task { await updateInboxPreference(kind: "direct", id: peer.id, body: ["muted": !isConvMuted], toast: isConvMuted ? "Đã bật thông báo." : "Đã tắt thông báo.") }
                                } label: {
                                    Label(isConvMuted ? "Bật thông báo" : "Tắt thông báo", systemImage: isConvMuted ? "bell" : "bell.slash")
                                }
                                Button {
                                    Task { await updateInboxPreference(kind: "direct", id: peer.id, body: ["unread": true], toast: "Đã đánh dấu chưa đọc.") }
                                } label: {
                                    Label("Đánh dấu chưa đọc", systemImage: "envelope.badge")
                                }
                                Button {
                                    Task { await updateInboxPreference(kind: "direct", id: peer.id, body: ["hidden": true], toast: "Đã ẩn hội thoại.") }
                                } label: {
                                    Label("Ẩn hội thoại", systemImage: "eye.slash")
                                }
                                Button(role: .destructive) {
                                    pendingClearChat = (kind: "direct", id: peer.id, name: peer.name)
                                } label: {
                                    Label("Xóa lịch sử trò chuyện", systemImage: "trash")
                                }
                            }

                            if index != rows.last?.0 {
                                Divider()
                                    .background(KinnectTheme.borderSoft.opacity(0.8))
                                    .padding(.leading, 82)
                            }
                        }
                    } else {
                        let visibleGroups = filteredGroups
                        if let loadError, groups.isEmpty && !isLoading {
                            chatsLoadErrorView(loadError)
                        } else if visibleGroups.isEmpty && !isLoading {
                            emptyGroupsView
                        }

                        ForEach(visibleGroups) { group in
                            let flags = groupMetaFlags[group.id]
                            let isGrpPinned = flags?.pinned ?? false
                            let isGrpMuted = flags?.muted ?? false
                            NavigationLink {
                                GroupChatDetailView(group: group) {
                                    Task { await loadChats() }
                                }
                            } label: {
                                groupConversationRow(group)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    Task { await updateInboxPreference(kind: "group", id: group.id, body: ["pinned": !isGrpPinned], toast: isGrpPinned ? "Đã bỏ ghim nhóm." : "Đã ghim nhóm.") }
                                } label: {
                                    Label(isGrpPinned ? "Bỏ ghim nhóm" : "Ghim nhóm", systemImage: isGrpPinned ? "pin.slash" : "pin")
                                }
                                Button {
                                    Task { await updateInboxPreference(kind: "group", id: group.id, body: ["muted": !isGrpMuted], toast: isGrpMuted ? "Đã bật thông báo nhóm." : "Đã tắt thông báo nhóm.") }
                                } label: {
                                    Label(isGrpMuted ? "Bật thông báo" : "Tắt thông báo", systemImage: isGrpMuted ? "bell" : "bell.slash")
                                }
                                Button {
                                    Task { await updateInboxPreference(kind: "group", id: group.id, body: ["unread": true], toast: "Đã đánh dấu chưa đọc.") }
                                } label: {
                                    Label("Đánh dấu chưa đọc", systemImage: "envelope.badge")
                                }
                                Button {
                                    Task { await updateInboxPreference(kind: "group", id: group.id, body: ["hidden": true], toast: "Đã ẩn nhóm chat.") }
                                } label: {
                                    Label("Ẩn nhóm chat", systemImage: "eye.slash")
                                }
                                Button(role: .destructive) {
                                    pendingClearChat = (kind: "group", id: group.id, name: group.name)
                                } label: {
                                    Label("Xóa lịch sử trò chuyện", systemImage: "trash")
                                }
                            }

                            if group.id != visibleGroups.last?.id {
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
        .onReceive(NotificationCenter.default.publisher(for: .kinnectMessagesChanged)) { note in
            if let kind = note.userInfo?["markReadKind"] as? String,
               let id = note.userInfo?["markReadId"] as? String {
                // Drop an in-flight list fetch that started before this mark-read.
                chatsLoadGeneration += 1
                clearLocalUnread(kind: kind, id: id)
            }
            Task { await loadChats() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectNotificationsChanged)) { _ in
            notifRefreshTask?.cancel()
            notifRefreshTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await loadChats()
            }
        }
        .onDisappear {
            notifRefreshTask?.cancel()
            notifRefreshTask = nil
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
        .alert(
            "Xóa lịch sử trò chuyện?",
            isPresented: Binding(
                get: { pendingClearChat != nil },
                set: { if !$0 { pendingClearChat = nil } }
            )
        ) {
            Button("Hủy", role: .cancel) { pendingClearChat = nil }
            Button("Xóa lịch sử", role: .destructive) {
                if let target = pendingClearChat {
                    pendingClearChat = nil
                    Task { await clearInboxHistory(kind: target.kind, id: target.id) }
                }
            }
        } message: {
            Text("Toàn bộ tin nhắn trong cuộc trò chuyện với \(pendingClearChat?.name ?? "") sẽ bị ẩn ở phía bạn.")
        }
    }

    private var filteredGroups: [ChatGroupItem] {
        let q = chatSearchKey(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        let base = groups.filter { g in
            if unreadOnly && g.unreadCount <= 0 { return false }
            if !q.isEmpty {
                return chatSearchKey(g.name).contains(q)
                    || chatSearchKey(g.description).contains(q)
                    || chatSearchKey(g.lastMessageText).contains(q)
            }
            return true
        }
        return base.enumerated().sorted { lhs, rhs in
            let lp = groupMetaFlags[lhs.element.id]?.pinned ?? false
            let rp = groupMetaFlags[rhs.element.id]?.pinned ?? false
            if lp != rp { return lp && !rp }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private var filteredConversations: [(Int, [String: Any], KinnectUser)] {
        let cleanQ = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = chatSearchKey(cleanQ.hasPrefix("@") ? String(cleanQ.dropFirst()) : cleanQ)
        let base = conversations.enumerated().compactMap { index, conv -> (Int, [String: Any], KinnectUser)? in
            let peer = extractPeer(from: conv)
            guard !peer.id.isEmpty && !appState.blockedUserIds.contains(peer.id) else { return nil }
            if !q.isEmpty {
                if !chatSearchKey(peer.name).contains(q) && !chatSearchKey(peer.handle).contains(q) {
                    return nil
                }
            }
            if unreadOnly {
                let unread = (conv["unread"] as? Int) ?? (conv["unreadCount"] as? Int) ?? 0
                if unread == 0 { return nil }
            }
            return (index, conv, peer)
        }
        return base.sorted { lhs, rhs in
            let lp = (lhs.1["pinned"] as? Bool) == true
            let rp = (rhs.1["pinned"] as? Bool) == true
            if lp != rp { return lp && !rp }
            return lhs.0 < rhs.0
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

    private func chatsLoadErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 38))
                .foregroundColor(KinnectTheme.messageMeta)
            Text("Không thể tải danh sách hội thoại")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(KinnectTheme.textPrimary)
            Text(message)
                .font(.caption)
                .foregroundColor(KinnectTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                Task { await loadChats() }
            } label: {
                Text("Thử lại")
                    .font(.caption.bold())
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 44)
    }

    private var emptyDirectView: some View {
        VStack(spacing: 12) {
            Image(systemName: unreadOnly ? "tray" : "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundColor(KinnectTheme.messageMeta)
            Text(unreadOnly ? "Không có tin nhắn chưa đọc." : "Chưa có cuộc trò chuyện riêng nào")
                .font(.subheadline)
                .foregroundColor(KinnectTheme.textSecondary)
            if !unreadOnly {
                Button("Mở danh sách bạn bè", action: onOpenFriends)
                    .font(.caption.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 48)
    }

    private var emptyGroupsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3")
                .font(.system(size: 40))
                .foregroundColor(KinnectTheme.messageMeta)
            Text("Bạn chưa tham gia nhóm trò chuyện nào")
                .font(.subheadline)
                .foregroundColor(KinnectTheme.textSecondary)
            Button("Tạo nhóm mới") {
                showCreateGroupSheet = true
            }
            .font(.caption.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(KinnectTheme.primaryGradient))
            .foregroundColor(.white)
        }
        .padding(.vertical, 48)
    }

    private func directConversationRow(conv: [String: Any], peer: KinnectUser) -> some View {
        let lastObj = conv["last"] as? [String: Any]
        let rawLastMsg = (lastObj?["body"] as? String)
            ?? ((conv["lastMessage"] as? [String: Any])?["text"] as? String)
            ?? (conv["preview"] as? String)
            ?? "Nhấn để trò chuyện"
        let isLastMine = (lastObj?["mine"] as? Bool) == true
        let lastMsg = (isLastMine && !rawLastMsg.isEmpty && rawLastMsg != "Nhấn để trò chuyện")
            ? "Bạn: \(rawLastMsg)"
            : rawLastMsg
        let unread = (conv["unread"] as? Int) ?? (conv["unreadCount"] as? Int) ?? 0
        let isPinned = (conv["pinned"] as? Bool) == true
        let isMuted = (conv["muted"] as? Bool) == true
        let rawTime = [
            isoString(from: lastObj?["createdAt"] ?? lastObj?["created"]),
            isoString(from: conv["updatedAt"]),
            isoString(from: conv["lastTime"]),
            isoString(from: conv["lastMessageAt"]),
            isoString(from: conv["createdAt"])
        ].first(where: { !$0.isEmpty }) ?? ""
        let isOnline = peer.showActivity && (peer.isActive || appState.onlineUserIds.contains(peer.id))

        return HStack(spacing: 14) {
            KinnectAvatarView(
                name: peer.name,
                avatarURL: peer.avatarUrl,
                colorHex: peer.avatarColor,
                size: 52,
                isOnline: isOnline
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(peer.name)
                        .font(.system(size: 16, weight: unread > 0 ? .bold : .semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    if isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11))
                            .foregroundColor(KinnectTheme.messageMeta)
                    }

                    Spacer(minLength: 8)

                    if !rawTime.isEmpty {
                        Text(formatRelativeDate(rawTime))
                            .font(.system(size: 13, weight: unread > 0 ? .semibold : .regular))
                            .foregroundColor(unread > 0 ? KinnectTheme.accentBright : KinnectTheme.messageMeta)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if !peer.handle.isEmpty {
                    Text("@\(peer.handle)")
                        .font(.system(size: 12))
                        .foregroundColor(KinnectTheme.messageMeta)
                        .lineLimit(1)
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
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
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
        let flags = groupMetaFlags[group.id]
        let isPinned = flags?.pinned ?? false
        let isMuted = flags?.muted ?? false
        let isLastMine = flags?.lastMine ?? false
        let rawPreview = group.lastMessageText.isEmpty ? group.description : group.lastMessageText
        let previewText = (isLastMine && !group.lastMessageText.isEmpty)
            ? "Bạn: \(rawPreview)"
            : rawPreview

        return HStack(spacing: 14) {
            KinnectAvatarView(
                name: group.name,
                avatarURL: group.avatarUrl,
                colorHex: group.avatarColor,
                size: 52
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(.system(size: 16, weight: group.unreadCount > 0 ? .bold : .semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                        Text("(\(group.membersCount))")
                            .font(.system(size: 13))
                            .foregroundColor(KinnectTheme.messageMeta)
                    }

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    if isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11))
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
                    Text(previewText)
                        .font(.system(size: 14, weight: group.unreadCount > 0 ? .medium : .regular))
                        .foregroundColor(group.unreadCount > 0 ? KinnectTheme.textPrimary : KinnectTheme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    if group.unreadCount > 0 {
                        Text("\(group.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            )
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func clearLocalUnread(kind: String, id: String) {
        guard !id.isEmpty else { return }
        if kind == "direct" {
            conversations = conversations.map { conv in
                guard extractPeer(from: conv).id == id else { return conv }
                var next = conv
                next["unread"] = 0
                next["unreadCount"] = 0
                return next
            }
        } else if kind == "group" {
            groups = groups.map { group in
                guard group.id == id else { return group }
                var next = group
                next.unreadCount = 0
                return next
            }
        }
    }

    private static func extractGroupMetaFlags(from rawGroups: [[String: Any]]) -> [String: (pinned: Bool, muted: Bool, lastMine: Bool)] {
        var flags: [String: (pinned: Bool, muted: Bool, lastMine: Bool)] = [:]
        for g in rawGroups {
            guard let id = g["id"] as? String, !id.isEmpty else { continue }
            let pinned = (g["pinned"] as? Bool) == true
            let muted = (g["muted"] as? Bool) == true
            let lastObj = (g["last"] as? [String: Any]) ?? (g["lastMessage"] as? [String: Any])
            let lastMine = (lastObj?["mine"] as? Bool) == true
            flags[id] = (pinned: pinned, muted: muted, lastMine: lastMine)
        }
        return flags
    }

    @MainActor
    private func updateInboxPreference(kind: String, id: String, body: [String: Any], toast: String) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-preferences/\(kind)/\(id)",
                method: "POST",
                body: body
            )
            appState.showToast(toast)
            await loadChats()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    @MainActor
    private func clearInboxHistory(kind: String, id: String) async {
        let path = (kind == "direct") ? "/api/users/\(id)/messages" : "/api/groups/\(id)/messages"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(path, method: "DELETE", body: [:])
            appState.showToast("Đã xóa lịch sử trò chuyện.")
            await loadChats()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    @MainActor
    private func loadChats() async {
        chatsLoadGeneration += 1
        let generation = chatsLoadGeneration
        if conversations.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/conversations") {
            let list = (cached["users"] as? [[String: Any]]) ?? (cached["conversations"] as? [[String: Any]]) ?? []
            self.conversations = list
        }
        if groups.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/groups"),
           let grps = cached["groups"] as? [[String: Any]] {
            self.groups = grps.map(ChatGroupItem.from)
            self.groupMetaFlags = Self.extractGroupMetaFlags(from: grps)
        }
        isLoading = true
        defer {
            if generation == chatsLoadGeneration {
                isLoading = false
            }
        }
        async let cTask = KinnectAPIClient.shared.requestJSON("/api/conversations")
        async let gTask = KinnectAPIClient.shared.requestJSON("/api/groups")

        var directErr: Error?
        var groupErr: Error?

        do {
            let cRes = try await cTask
            if generation == chatsLoadGeneration {
                let list = (cRes["users"] as? [[String: Any]]) ?? (cRes["conversations"] as? [[String: Any]]) ?? []
                self.conversations = list
            }
        } catch {
            directErr = error
        }

        do {
            let gRes = try await gTask
            if generation == chatsLoadGeneration {
                let rawGroups = gRes["groups"] as? [[String: Any]] ?? []
                self.groups = rawGroups.map(ChatGroupItem.from)
                self.groupMetaFlags = Self.extractGroupMetaFlags(from: rawGroups)
            }
        } catch {
            groupErr = error
        }

        guard generation == chatsLoadGeneration else { return }
        if let err = directErr ?? groupErr, conversations.isEmpty && groups.isEmpty {
            self.loadError = err.localizedDescription
        } else {
            self.loadError = nil
        }
        await appState.refreshGlobalBadges()
    }
}

private func mimeTypeForExt(_ ext: String) -> String {
    let lower = ext.lowercased()
    switch lower {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "pdf": return "application/pdf"
    case "doc", "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case "xls", "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case "zip": return "application/zip"
    case "rar": return "application/x-rar-compressed"
    case "mp3": return "audio/mpeg"
    case "m4a": return "audio/mp4"
    case "wav": return "audio/wav"
    case "mp4": return "video/mp4"
    case "txt": return "text/plain"
    default: return "application/octet-stream"
    }
}

struct MessageBubbleShape: Shape {
    let isMine: Bool

    func path(in rect: CGRect) -> Path {
        let corners: UIRectCorner = isMine
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: 18, height: 18)
        )
        return Path(path.cgPath)
    }
}

struct ChatAttachmentBubbleView: View {
    let fileName: String
    let fileUrl: String
    let isMine: Bool
    @State private var playableMediaItem: ChatPlayableMediaItem? = nil
    @State private var isLoadingMedia = false

    private var fileExt: String {
        let nameExt = (fileName as NSString).pathExtension.lowercased()
        if !nameExt.isEmpty { return nameExt }
        return (fileUrl as NSString).pathExtension.lowercased()
    }

    private var isPlayableAudioOrVideo: Bool {
        ["mp4", "mov", "m4v", "webm", "mp3", "m4a", "wav", "aac"].contains(fileExt)
            || fileUrl.hasPrefix("data:video/")
            || fileUrl.hasPrefix("data:audio/")
    }

    private var fileIconName: String {
        switch fileExt {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.richtext.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "zip", "rar", "tar", "gz": return "archivebox.fill"
        case "mp3", "m4a", "wav", "aac": return "music.note"
        case "mp4", "mov", "m4v", "webm", "avi": return "video.fill"
        default: return "doc.fill"
        }
    }

    private var fileIconColor: Color {
        switch fileExt {
        case "pdf": return Color(hex: "#EF4444")
        case "doc", "docx": return Color(hex: "#3B82F6")
        case "xls", "xlsx", "csv": return Color(hex: "#10B981")
        case "zip", "rar", "tar", "gz": return Color(hex: "#8B5CF6")
        case "mp3", "m4a", "wav", "aac": return Color(hex: "#F59E0B")
        default: return KinnectTheme.accentBright
        }
    }

    var body: some View {
        Button {
            openOrDownloadFile()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isMine ? Color.white.opacity(0.2) : fileIconColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: fileIconName)
                        .font(.system(size: 20))
                        .foregroundColor(isMine ? .white : fileIconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName.isEmpty ? "Tệp đính kèm" : fileName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isMine ? .white : KinnectTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(isPlayableAudioOrVideo ? "Phương tiện • Chạm để phát" : "Tệp đính kèm • Chạm để mở")
                        .font(.caption2)
                        .foregroundColor(isMine ? Color.white.opacity(0.8) : KinnectTheme.textSecondary)
                }

                Spacer(minLength: 4)

                if isLoadingMedia {
                    ProgressView()
                        .tint(isMine ? .white : KinnectTheme.accentBright)
                } else {
                    Image(systemName: isPlayableAudioOrVideo ? "play.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(isMine ? Color.white.opacity(0.9) : KinnectTheme.accentBright)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: KinnectTheme.radiusLG)
                    .fill(isMine ? AnyShapeStyle(Color.white.opacity(0.16)) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                    .overlay(
                        RoundedRectangle(cornerRadius: KinnectTheme.radiusLG)
                            .stroke(isMine ? Color.white.opacity(0.3) : KinnectTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(item: $playableMediaItem) { item in
            ChatMediaPlayerSheet(media: item)
        }
    }

    private func openOrDownloadFile() {
        guard !fileUrl.isEmpty, !isLoadingMedia else { return }
        if fileUrl.hasPrefix("data:") {
            if let commaIndex = fileUrl.firstIndex(of: ",") {
                let base64 = String(fileUrl[fileUrl.index(after: commaIndex)...])
                if let data = Data(base64Encoded: base64) {
                    let rawName = (fileName as NSString).lastPathComponent
                        .replacingOccurrences(of: "..", with: "_")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanName = (rawName.isEmpty || rawName == "." || rawName == "_") ? "attachment.\(fileExt.isEmpty ? "dat" : fileExt)" : rawName
                    let temp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("Kinnect-Attach-\(UUID().uuidString)-\(cleanName)")
                    try? data.write(to: temp)
                    if isPlayableAudioOrVideo {
                        playableMediaItem = ChatPlayableMediaItem(url: temp, title: fileName)
                    } else {
                        presentShareSheet(for: temp)
                    }
                    return
                }
            }
        }
        let rawExt = (fileName as NSString).pathExtension
        let urlExt = (fileUrl as NSString).pathExtension
        let ext = !rawExt.isEmpty ? rawExt : (!urlExt.isEmpty ? urlExt : "dat")
        isLoadingMedia = true
        Task {
            defer { Task { @MainActor in isLoadingMedia = false } }
            do {
                let localURL = try await KinnectAuthenticatedFile.fetch(path: fileUrl, fileExtension: ext)
                await MainActor.run {
                    if isPlayableAudioOrVideo {
                        playableMediaItem = ChatPlayableMediaItem(url: localURL, title: fileName)
                    } else {
                        presentShareSheet(for: localURL)
                    }
                }
            } catch {
                await MainActor.run {
                    AppState.shared.showToast("Không mở được tệp: \(error.localizedDescription)")
                }
            }
        }
    }

    private func presentShareSheet(for fileURL: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let keyWindow = activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first
        guard var topVC = keyWindow?.rootViewController else { return }
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
    }
}

private struct ChatPlayableMediaItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

private struct ChatFullscreenPhotoItem: Identifiable {
    let id = UUID()
    let rawURL: String
}

private struct ChatFullscreenImageSheet: View {
    let rawURL: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                KinnectRemoteImageView(rawURL: rawURL, contentMode: .fit, cornerRadius: 0, maxHeight: geo.size.height)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(max(1.0, min(4.0, scale * pinchScale)))
                    .gesture(
                        MagnificationGesture()
                            .updating($pinchScale) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                scale = max(1.0, min(4.0, scale * value))
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            scale = (scale > 1.05) ? 1.0 : 2.2
                        }
                    }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.65)))
            }
            .padding(16)
            .accessibilityLabel("Đóng ảnh")
        }
    }
}

private struct ChatAVPlayerViewController: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        let player = AVPlayer(url: url)
        vc.player = player
        player.play()
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
}

private struct ChatMediaPlayerSheet: View {
    let media: ChatPlayableMediaItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChatAVPlayerViewController(url: media.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(media.title.isEmpty ? "Trình phát phương tiện" : media.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") { dismiss() }
                    }
                }
        }
    }
}

private struct ChatMessageSearchSheet: View {
    let kind: String // "direct" | "group"
    let targetId: String
    let title: String
    let onSelectMessageId: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var query = ""
    @State private var results: [(id: String, senderName: String, body: String, createdAt: String)] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.tr("Đang tìm tin nhắn…"))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.tr("Nhập từ khóa để tìm trong lịch sử trò chuyện."))
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                } else if results.isEmpty {
                    Text(L10n.tr("Không tìm thấy tin nhắn phù hợp."))
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                } else {
                    ForEach(results, id: \.id) { item in
                        Button {
                            onSelectMessageId(item.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.senderName)
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.accentBright)
                                    Spacer()
                                    if !item.createdAt.isEmpty {
                                        Text(formatRelativeDate(item.createdAt))
                                            .font(.caption2)
                                            .foregroundColor(KinnectTheme.messageMeta)
                                    }
                                }
                                Text(item.body)
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .searchable(text: $query, prompt: String(format: L10n.tr("Tìm trong %@…"), title))
            .onChange(of: query) { newValue in
                searchTask?.cancel()
                let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else {
                    results = []
                    isSearching = false
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    await runSearch(clean)
                }
            }
            .navigationTitle(L10n.tr("Tìm tin nhắn"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func runSearch(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let path = (kind == "direct")
            ? "/api/users/\(targetId)/messages/search?q=\(encoded)"
            : "/api/groups/\(targetId)/messages/search?q=\(encoded)"
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(path)
            let raw = res["messages"] as? [[String: Any]] ?? []
            results = raw.map { dict in
                let id = (dict["id"] as? String) ?? UUID().uuidString
                let body = (dict["body"] as? String) ?? (dict["text"] as? String) ?? ""
                let created = isoString(from: dict["createdAt"] ?? dict["created"])
                let author = (dict["author"] as? [String: Any]) ?? (dict["sender"] as? [String: Any])
                let senderName = (author?["name"] as? String)
                    ?? (dict["senderName"] as? String)
                    ?? ((dict["sender"] as? String) == AppState.shared.currentUser?.id ? L10n.tr("Bạn") : title)
                return (id: id, senderName: senderName, body: body, createdAt: created)
            }
        } catch {
            results = []
        }
    }
}

private func chatContentContainsMention(_ content: String, username: String) -> Bool {
    guard !username.isEmpty else { return false }
    let token = "@" + username
    let lowerContent = content.lowercased()
    let lowerToken = token.lowercased()
    var searchStart = lowerContent.startIndex
    while let range = lowerContent.range(of: lowerToken, range: searchStart..<lowerContent.endIndex) {
        let validBefore: Bool
        if range.lowerBound == lowerContent.startIndex {
            validBefore = true
        } else {
            let ch = lowerContent[lowerContent.index(before: range.lowerBound)]
            validBefore = ch.isWhitespace || ch == "(" || ch == "[" || ch == "{"
        }
        let validAfter: Bool
        if range.upperBound == lowerContent.endIndex {
            validAfter = true
        } else {
            let ch = lowerContent[range.upperBound]
            validAfter = !ch.isLetter && !ch.isNumber && ch != "_" && ch != "." && ch != "-"
        }
        if validBefore && validAfter {
            return true
        }
        searchStart = range.upperBound
    }
    return false
}

private struct CompatPhotosPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var selection: PhotosPickerItem?

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.photosPicker(isPresented: $isPresented, selection: $selection, matching: .images)
        } else {
            content
        }
    }
}

struct DirectChatDetailView: View {
    let peer: KinnectUser
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var messages: [DirectMessageItem] = []
    @State private var text = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var isSending = false
    @State private var editingMessageId: String?
    @State private var editingMessageText: String = ""
    @State private var messageReactions: [String: String] = [:]
    // Reaction Picker state (Android parity)
    @State private var showingReactionPicker = false
    @State private var reactionPickerMessageId: String = ""
    @State private var reactionPickerIsDirect = true
    @State private var reactionPickerFrame: CGRect = .zero
    @State private var forwardText: String = ""
    @State private var forwardImageUrl: String = ""
    @State private var showForwardSheet = false
    @State private var isPinned = false
    @State private var isMuted = false
    #if DEBUG
    @State private var showReviewChatMenu = (UIReviewFixture.activeScreen == "chat-menu")
    @State private var showReviewMessageMenu = (UIReviewFixture.activeScreen == "message-menu")
    #else
    @State private var showReviewChatMenu = false
    @State private var showReviewMessageMenu = false
    #endif
    @State private var showPeerProfile = false
    @State private var replyingToMessage: DirectMessageItem? = nil
    @State private var hasMoreMessages = false
    @State private var nextMessagesCursor: Int64? = nil
    @State private var hasReachedHistoryStart = false
    @State private var isLoadingOlder = false
    @State private var pendingOptIds: Set<String> = []
    @State private var loadError: String? = nil
    @State private var showBlockPeerConfirm = false
    @State private var pendingRecallMessage: DirectMessageItem? = nil
    @State private var showSearchSheet = false
    @State private var showClearHistoryConfirm = false
    @State private var pinnedMessageIds: Set<String> = []
    @State private var fullscreenPhoto: ChatFullscreenPhotoItem? = nil
    @State private var scrollTargetId: String? = nil
    @State private var aiSupportAvailable = false
    @State private var aiSupportConsent = "unset"
    @State private var isUpdatingAIConsent = false

    init(peer: KinnectUser) {
        self.peer = peer
        if let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/users/\(peer.id)/messages"),
           let list = cached["messages"] as? [[String: Any]] {
            let initial = list.map(DirectMessageItem.from)
            _messages = State(initialValue: initial)
            var rx: [String: String] = [:]
            for m in initial where !m.myReaction.isEmpty { rx[m.id] = m.myReaction }
            _messageReactions = State(initialValue: rx)
            _hasMoreMessages = State(initialValue: (cached["hasMore"] as? Bool) ?? false)
            _nextMessagesCursor = State(initialValue: (cached["nextCursor"] as? NSNumber)?.int64Value)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Conversational Header Bar (iOS Native Style)
            HStack(spacing: 6) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")

                Button {
                    showPeerProfile = true
                } label: {
                    HStack(spacing: 10) {
                        let peerOnline = peer.showActivity && (peer.isActive || appState.onlineUserIds.contains(peer.id))
                        KinnectAvatarView(
                            name: peer.name,
                            avatarURL: peer.avatarUrl,
                            colorHex: peer.avatarColor,
                            size: 38,
                            isOnline: peerOnline
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(
                                        peerOnline
                                            ? Color(hex: "#2E9E66")
                                            : KinnectTheme.messageMeta
                                    )
                                    .frame(width: 7, height: 7)

                                Text(peerOnline ? L10n.tr("Đang trực tuyến") : L10n.tr("Ngoại tuyến"))
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                    .lineLimit(1)
                            }
                        }
                        .layoutPriority(1)
                    }
                }
                .buttonStyle(.plain)
                .layoutPriority(1)

                Spacer(minLength: 4)

                // Call action buttons (iOS HIG native phone & video contour icons)
                HStack(spacing: 2) {
                    Button {
                        Task { await NativeWebRTCManager.shared.startOutgoingCall(targetUser: peer, mode: "audio") }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#2E9E66").opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: "phone.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Color(hex: "#2E9E66"))
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gọi thoại")

                    Button {
                        Task { await NativeWebRTCManager.shared.startOutgoingCall(targetUser: peer, mode: "video") }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(KinnectTheme.accentBright.opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: "video.fill")
                                .font(.system(size: 15))
                                .foregroundColor(KinnectTheme.accentBright)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Gọi video")

                    Menu {
                        Button {
                            showPeerProfile = true
                        } label: {
                            Label(L10n.tr("Xem hồ sơ"), systemImage: "person.crop.circle")
                        }
                        Button {
                            showSearchSheet = true
                        } label: {
                            Label(L10n.tr("Tìm kiếm tin nhắn"), systemImage: "magnifyingglass")
                        }
                        Button {
                            Task {
                                let next = !isPinned
                                do {
                                    _ = try await KinnectAPIClient.shared.requestJSON(
                                        "/api/chat-preferences/direct/\(peer.id)",
                                        method: "POST",
                                        body: ["pinned": next]
                                    )
                                    isPinned = next
                                    appState.showToast(isPinned ? "Đã ghim hội thoại." : "Đã bỏ ghim.")
                                } catch {
                                    appState.showToast(error.localizedDescription)
                                }
                            }
                        } label: {
                            Label(isPinned ? "Bỏ ghim hội thoại" : "Ghim hội thoại", systemImage: isPinned ? "pin.slash" : "pin")
                        }
                        Button {
                            Task {
                                let next = !isMuted
                                do {
                                    _ = try await KinnectAPIClient.shared.requestJSON(
                                        "/api/chat-preferences/direct/\(peer.id)",
                                        method: "POST",
                                        body: ["muted": next]
                                    )
                                    isMuted = next
                                    appState.showToast(isMuted ? "Đã tắt thông báo." : "Đã bật thông báo.")
                                } catch {
                                    appState.showToast(error.localizedDescription)
                                }
                            }
                        } label: {
                            Label(isMuted ? "Bật thông báo" : "Tắt thông báo", systemImage: isMuted ? "bell" : "bell.slash")
                        }
                        Button {
                            Task { await updateDirectPreference(body: ["unread": true], toast: "Đã đánh dấu chưa đọc.", dismissAfter: true) }
                        } label: {
                            Label("Đánh dấu chưa đọc", systemImage: "envelope.badge")
                        }
                        Button {
                            Task { await updateDirectPreference(body: ["hidden": true], toast: "Đã ẩn hội thoại.", dismissAfter: true) }
                        } label: {
                            Label("Ẩn hội thoại", systemImage: "eye.slash")
                        }
                        Button(role: .destructive) {
                            showClearHistoryConfirm = true
                        } label: {
                            Label("Xóa lịch sử trò chuyện", systemImage: "trash")
                        }
                        Button(role: .destructive) {
                            appState.activeReportContext = UGCReportContext(
                                targetType: "user",
                                targetId: peer.id,
                                targetUserId: peer.id,
                                targetTitle: peer.name
                            )
                        } label: {
                            Label("Báo cáo người dùng", systemImage: "exclamationmark.bubble")
                        }
                        Button(role: .destructive) {
                            showBlockPeerConfirm = true
                        } label: {
                            Label("Chặn người dùng", systemImage: "hand.raised.fill")
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(KinnectTheme.surfaceElevated)
                                .frame(width: 36, height: 36)
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Tùy chọn cuộc trò chuyện")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(KinnectTheme.surface)
            .overlay(alignment: .bottom) {
                Divider().background(KinnectTheme.borderSoft)
            }

            if aiSupportAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hỗ trợ AI Kinnect")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(aiSupportConsent == "enabled"
                             ? "Trợ lý AI có thể hỗ trợ trả lời nhanh trong cuộc trò chuyện này."
                             : "Bật để cho phép trợ lý AI hỗ trợ trả lời khi quản trị viên vắng mặt.")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { aiSupportConsent == "enabled" },
                        set: { enabled in
                            Task { await updateAIConsent(enabled: enabled) }
                        }
                    ))
                    .labelsHidden()
                    .tint(KinnectTheme.accentBright)
                    .disabled(isUpdatingAIConsent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(KinnectTheme.surfaceElevated)
                .overlay(alignment: .bottom) {
                    Divider().background(KinnectTheme.borderSoft)
                }
            }

            if let firstPinned = messages.last(where: { pinnedMessageIds.contains($0.id) && !$0.recalled }) {
                Button {
                    scrollTargetId = firstPinned.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(firstPinned.text.isEmpty ? "Tin nhắn đã ghim" : firstPinned.text)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(KinnectTheme.surfaceElevated)
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if let loadError, messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "wifi.exclamationmark")
                                    .font(.system(size: 36))
                                    .foregroundColor(KinnectTheme.messageMeta)
                                Text("Không thể tải tin nhắn")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text(loadError)
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                Button {
                                    Task { await loadMessages() }
                                } label: {
                                    Text("Thử lại")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 20)
                                        .frame(minHeight: 44)
                                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 44)
                        }
                        if hasMoreMessages, nextMessagesCursor != nil {
                            Button {
                                Task { await loadOlderMessages() }
                            } label: {
                                Text(isLoadingOlder ? "Đang tải…" : "Xem tin nhắn cũ hơn")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(KinnectTheme.accentBright)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                            }
                            .disabled(isLoadingOlder)
                        }
                        ForEach(messages) { msg in
                            let isMine = (msg.fromUserId == appState.currentUser?.id)
                            directMessageBubble(msg: msg, isMine: isMine)
                                .id(msg.id)
                        }
                    }
                    .padding(14)
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: messages.last?.id) { lastId in
                    if let lastId {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: scrollTargetId) { targetId in
                    if let targetId {
                        withAnimation {
                            proxy.scrollTo(targetId, anchor: .center)
                        }
                        scrollTargetId = nil
                    }
                }
            }

            if let reply = replyingToMessage {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(KinnectTheme.accentBright)
                        .frame(width: 3, height: 28)
                        .cornerRadius(2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Đang trả lời \(reply.fromUserId == appState.currentUser?.id ? "chính bạn" : peer.name)")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(reply.text.isEmpty ? "Tệp đính kèm" : reply.text)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        replyingToMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(KinnectTheme.textSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hủy trả lời")
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .padding(.vertical, 2)
                .background(KinnectTheme.surfaceElevated)
            }

            if let editId = editingMessageId {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(KinnectTheme.accentBright)
                    Text("Đang sửa tin nhắn")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                    Spacer()
                    Button("Hủy") {
                        editingMessageId = nil
                        editingMessageText = ""
                    }
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                    Button("Lưu") {
                        Task { await saveEditedMessage(messageId: editId) }
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(KinnectTheme.surfaceElevated)
            }

            // Apple iMessage Input Bar
            HStack(alignment: .bottom, spacing: 4) {
                Menu {
                    if #available(iOS 17.0, *) {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Thư viện ảnh", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Tệp & Tài liệu", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(KinnectTheme.messageMeta)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Đính kèm tệp hoặc ảnh")
                .disabled(isSending || editingMessageId != nil)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 19))
                        .foregroundColor((isSending || editingMessageId != nil) ? KinnectTheme.textSecondary.opacity(0.4) : KinnectTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(isSending || editingMessageId != nil)
                .accessibilityLabel("Chọn ảnh gửi")
                .modifier(CompatPhotosPickerModifier(isPresented: $showPhotoPicker, selection: $selectedPhoto))
                .onChange(of: selectedPhoto) { newItem in
                    guard let newItem else { return }
                    selectedPhoto = nil
                    guard !isSending else { return }
                    Task { @MainActor in
                        guard let data = try? await newItem.loadTransferable(type: Data.self),
                              let dataURL = await compressChatPhotoToDataURL(data) else {
                            appState.showToast("Không thể xử lý ảnh đã chọn (tối đa 4.5 MB sau khi nén).")
                            return
                        }
                        await sendMessage(text: text, imageDataURL: dataURL)
                    }
                }

                if let activeEditId = editingMessageId {
                    HStack(spacing: 6) {
                        TextField(
                            "",
                            text: $editingMessageText,
                            prompt: Text("Nội dung tin nhắn mới...").foregroundColor(KinnectTheme.textSecondary)
                        )
                        .font(.system(size: 16))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundColor(KinnectTheme.textPrimary)

                        Button {
                            Task { await saveEditedMessage(messageId: activeEditId) }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? KinnectTheme.messageMeta : KinnectTheme.accentBright)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Lưu tin nhắn đã sửa")
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(KinnectTheme.surfaceElevated)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KinnectTheme.borderSoft, lineWidth: 0.8))
                    )
                } else {
                    HStack(alignment: .bottom, spacing: 6) {
                        TextField(
                            "",
                            text: $text,
                            prompt: Text("Tin nhắn…").foregroundColor(KinnectTheme.textSecondary),
                            axis: .vertical
                        )
                        .lineLimit(1...5)
                        .font(.system(size: 16))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                Task { await sendMessage(text: text, imageDataURL: "") }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .disabled(isSending)
                            .accessibilityLabel("Gửi tin nhắn")
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(KinnectTheme.surfaceElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(KinnectTheme.borderSoft.opacity(0.8), lineWidth: 0.8)
                            )
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(KinnectTheme.surface.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Divider().background(KinnectTheme.borderSoft)
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showForwardSheet) {
            ForwardMessageSheet(text: forwardText, imageUrl: forwardImageUrl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showForwardSheet)
        }
        .sheet(isPresented: $showPeerProfile) {
            ProfileView(targetUser: peer)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showPeerProfile)
        }
        .sheet(isPresented: $showSearchSheet) {
            ChatMessageSearchSheet(kind: "direct", targetId: peer.id, title: peer.name) { targetId in
                scrollTargetId = targetId
            }
        }
        .fullScreenCover(item: $fullscreenPhoto) { item in
            ChatFullscreenImageSheet(rawURL: item.rawURL)
        }
        .alert("Xóa lịch sử trò chuyện?", isPresented: $showClearHistoryConfirm) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa lịch sử", role: .destructive) {
                Task { await clearDirectHistory() }
            }
        } message: {
            Text("Toàn bộ tin nhắn với \(peer.name) sẽ bị ẩn ở phía bạn.")
        }
        .confirmationDialog(L10n.tr("Tùy chọn hội thoại"), isPresented: $showReviewChatMenu, titleVisibility: .visible) {
            Button(L10n.tr("Xem hồ sơ")) { showPeerProfile = true }
            Button(L10n.tr("Tìm kiếm tin nhắn")) { showSearchSheet = true }
            Button(isPinned ? L10n.tr("Bỏ ghim hội thoại") : L10n.tr("Ghim hội thoại")) {}
            Button(isMuted ? L10n.tr("Bật thông báo") : L10n.tr("Tắt thông báo")) {}
            Button(L10n.tr("Báo cáo người dùng"), role: .destructive) {}
            Button(L10n.tr("Chặn người dùng"), role: .destructive) {}
            Button(L10n.tr("Hủy"), role: .cancel) {}
        }
        .confirmationDialog(L10n.tr("Tùy chọn tin nhắn"), isPresented: $showReviewMessageMenu, titleVisibility: .visible) {
            Button(L10n.tr("Ghim tin nhắn")) {}
            Button(L10n.tr("Sửa tin nhắn")) {}
            Button(L10n.tr("Chuyển tiếp tin nhắn")) {}
            Button(L10n.tr("Thu hồi / Xóa tin nhắn"), role: .destructive) {}
            Button(L10n.tr("Hủy"), role: .cancel) {}
        }
        .alert("Chặn \(peer.name)?", isPresented: $showBlockPeerConfirm) {
            Button("Chặn người dùng", role: .destructive) {
                Task { await appState.blockUser(userId: peer.id, userName: peer.name) }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("\(peer.name) sẽ không thể nhắn tin hoặc xem nội dung của bạn.")
        }
        .alert(
            "Thu hồi tin nhắn?",
            isPresented: Binding(
                get: { pendingRecallMessage != nil },
                set: { if !$0 { pendingRecallMessage = nil } }
            ),
            presenting: pendingRecallMessage
        ) { msg in
            Button("Thu hồi tin nhắn", role: .destructive) {
                pendingRecallMessage = nil
                Task { await deleteMessage(msg) }
            }
            Button("Hủy", role: .cancel) {
                pendingRecallMessage = nil
            }
        } message: { _ in
            Text("Tin nhắn sẽ được thu hồi với mọi người trong cuộc trò chuyện.")
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let fileURL):
                guard !isSending else { return }
                guard fileURL.startAccessingSecurityScopedResource() else {
                    appState.showToast("Không có quyền truy cập tệp đã chọn.")
                    return
                }
                let maxBytes = 20 * 1024 * 1024
                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = values.fileSize,
                   fileSize > maxBytes {
                    fileURL.stopAccessingSecurityScopedResource()
                    appState.showToast("Tệp vượt quá giới hạn 20 MB.")
                    return
                }
                let fileName = fileURL.lastPathComponent
                let ext = fileURL.pathExtension
                Task.detached(priority: .userInitiated) {
                    defer { fileURL.stopAccessingSecurityScopedResource() }
                    guard let data = try? Data(contentsOf: fileURL) else {
                        await MainActor.run {
                            appState.showToast("Không thể đọc tệp đã chọn.")
                        }
                        return
                    }
                    if data.count > maxBytes {
                        await MainActor.run {
                            appState.showToast("Tệp vượt quá giới hạn 20 MB.")
                        }
                        return
                    }
                    let base64 = data.base64EncodedString()
                    let mime = mimeTypeForExt(ext)
                    let dataURL = "data:\(mime);base64,\(base64)"
                    await MainActor.run {
                        Task {
                            await sendFileMessage(name: fileName, dataURL: dataURL)
                        }
                    }
                }
            case .failure(let err):
                appState.showToast("Không thể chọn tệp: \(err.localizedDescription)")
            }
        }
        .task {
            await loadChatPreferences()
            await loadMessages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectMessagesChanged)) { note in
            guard note.userInfo?["markReadKind"] == nil else { return }
            Task { await loadMessages() }
        }
    }

    private func directMessageBubble(msg: DirectMessageItem, isMine: Bool) -> some View {
        let isRecalled = msg.recalled
        return HStack(alignment: .bottom, spacing: 6) {
            if isMine { Spacer(minLength: 44) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                ZStack(alignment: isMine ? .topLeading : .topTrailing) {
                    VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                        if isRecalled {
                            Text(msg.text.isEmpty ? "Tin nhắn đã được thu hồi" : msg.text)
                                .font(.system(size: 15).italic())
                                .foregroundColor(KinnectTheme.textSecondary)
                                .kinnectMultiline()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    MessageBubbleShape(isMine: isMine)
                                        .fill(KinnectTheme.surfaceElevated.opacity(0.7))
                                )
                                .overlay(
                                    MessageBubbleShape(isMine: isMine)
                                        .stroke(KinnectTheme.borderSoft.opacity(0.8), lineWidth: 0.8)
                                )
                        } else {
                            if let q = msg.replyTo {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(q.senderName.isEmpty ? "Tin nhắn" : q.senderName)
                                        .font(.caption2.bold())
                                        .foregroundColor(isMine ? .white.opacity(0.9) : KinnectTheme.accentBright)
                                    Text(q.body.isEmpty ? "Tệp đính kèm" : q.body)
                                        .font(.caption)
                                        .foregroundColor(isMine ? .white.opacity(0.85) : KinnectTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(isMine ? Color.white.opacity(0.18) : KinnectTheme.surfaceElevated))
                            }

                            // Image preview if present (tap to zoom)
                            if !msg.imageUrl.isEmpty {
                                Button {
                                    fullscreenPhoto = ChatFullscreenPhotoItem(rawURL: msg.imageUrl)
                                } label: {
                                    KinnectRemoteImageView(rawURL: msg.imageUrl, contentMode: .fill, cornerRadius: 16, maxHeight: 260)
                                        .frame(maxWidth: 260)
                                        .clipShape(MessageBubbleShape(isMine: isMine))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Xem ảnh toàn màn hình")
                            }

                            // Attachment file bubble
                            if !msg.attachmentName.isEmpty {
                                ChatAttachmentBubbleView(fileName: msg.attachmentName, fileUrl: msg.attachmentUrl, isMine: isMine)
                            }

                            // Text content with iconic asymmetric bubble
                            if !msg.text.isEmpty {
                                Text(msg.text)
                                    .font(.system(size: 16))
                                    .foregroundColor(isMine ? .white : KinnectTheme.textPrimary)
                                    .kinnectMultiline()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        MessageBubbleShape(isMine: isMine)
                                            .fill(
                                                isMine
                                                    ? AnyShapeStyle(
                                                        LinearGradient(
                                                            colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    : AnyShapeStyle(KinnectTheme.surfaceElevated)
                                            )
                                    )
                                    .overlay(
                                        MessageBubbleShape(isMine: isMine)
                                            .stroke(
                                                isMine ? Color.clear : KinnectTheme.borderSoft.opacity(0.7),
                                                lineWidth: 0.8
                                            )
                                    )
                            }
                        }
                    }

                    // Floating Tapback reaction badge
                    if !isRecalled, let reacted = messageReactions[msg.id] {
                        FloatingReactionBadge(reaction: reacted, isMine: isMine)
                    }
                }

                // Reaction Summary (Android parity) - shows reaction counts on message
                if !isRecalled && !msg.reactions.isEmpty {
                    ReactionSummary(reactions: msg.reactions, myReaction: messageReactions[msg.id])
                        .padding(.horizontal, isMine ? 0 : 4)
                        .padding(.top, -2)
                }

                // Bottom row: time, edited badge, delivery state, reaction trigger & more options
                HStack(spacing: 6) {
                    Text(formatRelativeDate(msg.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(KinnectTheme.messageMeta)

                    if !isRecalled && pinnedMessageIds.contains(msg.id) {
                        HStack(spacing: 2) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                            Text("Đã ghim")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(KinnectTheme.accentBright)
                    }

                    if !isRecalled && !msg.editedAt.isEmpty {
                        Text("· Đã sửa")
                            .font(.system(size: 11))
                            .foregroundColor(KinnectTheme.messageMeta)
                    }

                    if isMine && !isRecalled {
                        if msg.isSeen {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Đã xem")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(KinnectTheme.accentBright)
                        } else if !msg.deliveredAt.isEmpty {
                            Text("· Đã nhận")
                                .font(.system(size: 11))
                                .foregroundColor(KinnectTheme.messageMeta)
                        } else {
                            Text("· Đã gửi")
                                .font(.system(size: 11))
                                .foregroundColor(KinnectTheme.messageMeta)
                        }
                    }

                    if !isRecalled && !msg.id.hasPrefix("opt_") {
                        // Reaction Picker Button - Long press to show picker, tap to quick react
                        Button {
                            // Quick react with default (love) on tap
                            Task { await reactToMessage(msgId: msg.id, emoji: "❤️") }
                        } label: {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 12))
                                .foregroundColor(messageReactions[msg.id] != nil ? KinnectTheme.accentBright : KinnectTheme.messageMeta)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Thả cảm xúc tin nhắn")
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35)
                                .onEnded { _ in
                                    showReactionPicker(for: msg.id, isDirect: true, frame: .zero)
                                }
                        )

                        Menu {
                            Button {
                                replyingToMessage = msg
                            } label: {
                                Label("Trả lời", systemImage: "arrowshape.turn.up.left")
                            }

                            let isMsgPinned = pinnedMessageIds.contains(msg.id)
                            Button {
                                Task { await togglePinMessage(msgId: msg.id, pinned: !isMsgPinned) }
                            } label: {
                                Label(isMsgPinned ? "Bỏ ghim tin nhắn" : "Ghim tin nhắn", systemImage: isMsgPinned ? "pin.slash" : "pin")
                            }

                            if isMine && !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    editingMessageId = msg.id
                                    editingMessageText = msg.text
                                } label: {
                                    Label("Sửa tin nhắn", systemImage: "pencil")
                                }
                            }

                            Button {
                                forwardText = msg.text
                                forwardImageUrl = msg.imageUrl
                                showForwardSheet = true
                            } label: {
                                Label("Chuyển tiếp", systemImage: "arrow.turn.up.right")
                            }

                            Button(role: .destructive) {
                                Task { await deleteMessageForMe(msg) }
                            } label: {
                                Label("Xóa ở phía tôi", systemImage: "eye.slash")
                            }

                            if isMine {
                                Button(role: .destructive) {
                                    pendingRecallMessage = msg
                                } label: {
                                    Label("Thu hồi tin nhắn", systemImage: "trash")
                                }
                            } else {
                                Button(role: .destructive) {
                                    appState.activeReportContext = UGCReportContext(
                                        targetType: "message",
                                        targetId: msg.id,
                                        targetUserId: msg.fromUserId,
                                        targetTitle: "Tin nhắn của \(peer.name)"
                                    )
                                } label: {
                                    Label("Báo cáo tin nhắn", systemImage: "exclamationmark.bubble")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12))
                                .foregroundColor(KinnectTheme.messageMeta)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tùy chọn tin nhắn")
                    }
                }
                .padding(.horizontal, 4)
            }

            if !isMine { Spacer(minLength: 44) }
        }
        // Reaction Picker Overlay (Android-style popup)
        .overlay(
            Group {
                if !isRecalled && showingReactionPicker && reactionPickerMessageId == msg.id && reactionPickerIsDirect {
                    ReactionPicker(
                        messageId: msg.id,
                        currentReaction: messageReactions[msg.id],
                        reactionCounts: msg.reactions,
                        isMine: isMine,
                        onReact: { reactionKey in
                            Task { await reactToMessage(msgId: msg.id, emoji: reactionKey) }
                        },
                        onDismiss: { showingReactionPicker = false }
                    )
                    .transition(.scale.combined(with: .opacity).combined(with: .move(edge: .top)))
                    .zIndex(100)
                }
            },
            alignment: isMine ? .topTrailing : .topLeading
        )
    }

    private func loadChatPreferences() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/chat-preferences/direct/\(peer.id)") {
            let pref = (res["preference"] as? [String: Any]) ?? (res["preferences"] as? [String: Any]) ?? res
            if let pinned = pref["pinned"] as? Bool {
                self.isPinned = pinned
            }
            if let muted = pref["muted"] as? Bool {
                self.isMuted = muted
            }
        }
    }

    private func loadMessages() async {
        if messages.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/users/\(peer.id)/messages"),
           let list = cached["messages"] as? [[String: Any]] {
            self.messages = list.map(DirectMessageItem.from)
            var rx: [String: String] = [:]
            for m in self.messages where !m.myReaction.isEmpty {
                rx[m.id] = m.myReaction
            }
            self.messageReactions = rx
        }
        // Fetching GET /api/users/:id/messages marks incoming messages as seen on backend
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/users/\(peer.id)/messages")
            let list = res["messages"] as? [[String: Any]] ?? []
            if let aiInfo = res["aiSupport"] as? [String: Any] {
                self.aiSupportAvailable = (aiInfo["available"] as? Bool) == true
                self.aiSupportConsent = (aiInfo["consent"] as? String) ?? "unset"
            }
            var newPinned = self.pinnedMessageIds
            for rawMsg in list {
                if let mid = rawMsg["id"] as? String {
                    if (rawMsg["pinned"] as? Bool) == true {
                        newPinned.insert(mid)
                    } else {
                        newPinned.remove(mid)
                    }
                }
            }
            self.pinnedMessageIds = newPinned
            let latest = list.map(DirectMessageItem.from)
            let latestIds = Set(latest.map(\.id))
            let inFlightOpt = self.messages.filter { pendingOptIds.contains($0.id) && !latestIds.contains($0.id) }
            var merged: [DirectMessageItem]
            if self.messages.isEmpty || latest.isEmpty {
                merged = latest + inFlightOpt
            } else if let oldestLatestTime = latest.first?.createdAt, !oldestLatestTime.isEmpty {
                let older = self.messages.filter {
                    !latestIds.contains($0.id) && !$0.id.hasPrefix("opt_") && !$0.createdAt.isEmpty && $0.createdAt < oldestLatestTime
                }
                merged = older + latest + inFlightOpt
            } else {
                merged = latest + inFlightOpt
            }
            if hasReachedHistoryStart {
                self.hasMoreMessages = false
            } else if self.nextMessagesCursor == nil {
                self.hasMoreMessages = (res["hasMore"] as? Bool) ?? false
                self.nextMessagesCursor = (res["nextCursor"] as? NSNumber)?.int64Value
                if !self.hasMoreMessages {
                    self.hasReachedHistoryStart = true
                }
            }
            let sig: ([DirectMessageItem]) -> [String] = { arr in
                arr.map { msg in
                    let rxSig = msg.reactions.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: ",")
                    return "\(msg.id)|\(msg.text)|\(msg.recalled)|\(msg.editedAt)|\(msg.isSeen)|\(msg.deliveredAt)|\(msg.myReaction)|\(rxSig)|\(msg.imageUrl)|\(msg.attachmentUrl)"
                }
            }
            if sig(merged) != sig(self.messages) {
                self.messages = merged
            }
            var rx: [String: String] = [:]
            for m in self.messages where !m.myReaction.isEmpty {
                rx[m.id] = m.myReaction
            }
            self.messageReactions = rx
            self.loadError = nil
            postMessagesMarkedRead(kind: "direct", id: peer.id)
            await appState.refreshGlobalBadges()
        } catch {
            if self.messages.isEmpty {
                self.loadError = error.localizedDescription
            }
        }
    }

    private func loadOlderMessages() async {
        guard hasMoreMessages, let cursor = nextMessagesCursor, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(peer.id)/messages?limit=50&before=\(cursor)") {
            let older = (res["messages"] as? [[String: Any]] ?? []).map(DirectMessageItem.from)
            let existing = Set(self.messages.map(\.id))
            let newlyAdded = older.filter { !existing.contains($0.id) }
            self.messages = newlyAdded + self.messages
            for m in newlyAdded where !m.myReaction.isEmpty {
                self.messageReactions[m.id] = m.myReaction
            }
            let more = (res["hasMore"] as? Bool) ?? false
            self.hasMoreMessages = more
            self.nextMessagesCursor = (res["nextCursor"] as? NSNumber)?.int64Value
            if !more || self.nextMessagesCursor == nil {
                self.hasReachedHistoryStart = true
            }
        }
    }

    private func reactToMessage(msgId: String, emoji: String) async {
        guard !msgId.hasPrefix("opt_") else { return }
        if let existing = messages.first(where: { $0.id == msgId }), existing.recalled { return }
        guard let canonicalKey = DirectMessageItem.canonical(for: emoji) else { return }
        let previous = messageReactions[msgId]
        let isTogglingOff = (previous == canonicalKey)
        let newKey: String? = isTogglingOff ? nil : canonicalKey

        // Optimistic update
        if let newKey {
            messageReactions[msgId] = newKey
        } else {
            messageReactions.removeValue(forKey: msgId)
        }

        do {
            let bodyVal: Any = newKey ?? NSNull()
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-messages/direct/\(msgId)/reaction",
                method: "POST",
                body: ["reaction": bodyVal]
            )
            if let msgObj = res["message"] as? [String: Any] {
                let updated = DirectMessageItem.from(msgObj)
                if let idx = messages.firstIndex(where: { $0.id == msgId }) {
                    messages[idx].reactions = updated.reactions
                    messages[idx].myReaction = updated.myReaction
                    messages[idx].reaction = updated.myReaction
                }
                if !updated.myReaction.isEmpty {
                    messageReactions[msgId] = updated.myReaction
                } else {
                    messageReactions.removeValue(forKey: msgId)
                }
            }
        } catch {
            // Revert on failure
            if let previous {
                messageReactions[msgId] = previous
            } else {
                messageReactions.removeValue(forKey: msgId)
            }
            appState.showToast("Không thể gửi cảm xúc: \(error.localizedDescription)")
        }
    }

    // MARK: - Reaction Picker Helpers (Android parity)

    private func showReactionPicker(for messageId: String, isDirect: Bool, frame: CGRect) {
        reactionPickerMessageId = messageId
        reactionPickerIsDirect = isDirect
        reactionPickerFrame = frame
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingReactionPicker = true
        }
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func sendMessage(text: String, imageDataURL: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || !imageDataURL.isEmpty else { return }
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        let draft = self.text
        self.text = ""
        let reqId = "dm_\(peer.id)_\(UUID().uuidString)"
        let tempId = "opt_\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let replyTarget = self.replyingToMessage
        let optimistic = DirectMessageItem(
            id: tempId,
            fromUserId: appState.currentUser?.id ?? "",
            toUserId: peer.id,
            text: clean,
            imageUrl: imageDataURL,
            createdAt: createdAt,
            deliveredAt: "",
            seenAt: "",
            reaction: "",
            reactions: [:],
            myReaction: ""
        )
        pendingOptIds.insert(tempId)
        self.messages.append(optimistic)

        var payload: [String: Any] = [
            "body": clean,
            "text": clean,
            "requestId": reqId
        ]
        if let reply = replyTarget {
            payload["replyToId"] = reply.id
        }
        self.replyingToMessage = nil
        if !imageDataURL.isEmpty {
            payload["attachment"] = ["data": imageDataURL, "name": "photo.jpg"]
        }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            pendingOptIds.remove(tempId)
            if let msgObj = res["message"] as? [String: Any] {
                var realMsg = DirectMessageItem.from(msgObj)
                if realMsg.imageUrl.isEmpty && !optimistic.imageUrl.isEmpty {
                    realMsg.imageUrl = optimistic.imageUrl
                }
                if let existingRealIdx = self.messages.firstIndex(where: { $0.id == realMsg.id }) {
                    self.messages[existingRealIdx] = realMsg
                    self.messages.removeAll { $0.id == tempId }
                } else if let optIdx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages[optIdx] = realMsg
                } else {
                    self.messages.append(realMsg)
                }
            } else {
                await loadMessages()
            }
            if !imageDataURL.isEmpty {
                await loadMessages()
            }
        } catch {
            pendingOptIds.remove(tempId)
            self.messages.removeAll { $0.id == tempId }
            self.text = draft
            if self.replyingToMessage == nil {
                self.replyingToMessage = replyTarget
            }
            appState.showToast(error.localizedDescription)
        }
    }

    private func sendFileMessage(name: String, dataURL: String) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        let isImg = dataURL.hasPrefix("data:image/") || name.hasSuffix(".jpg") || name.hasSuffix(".png") || name.hasSuffix(".webp")
        let reqId = "dm_att_\(peer.id)_\(UUID().uuidString)"
        let tempId = "opt_\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let replyTarget = self.replyingToMessage
        let optimistic = DirectMessageItem(
            id: tempId,
            fromUserId: appState.currentUser?.id ?? "",
            toUserId: peer.id,
            text: "",
            imageUrl: isImg ? dataURL : "",
            attachmentName: isImg ? "" : name,
            attachmentUrl: isImg ? "" : dataURL,
            createdAt: createdAt,
            deliveredAt: "",
            seenAt: "",
            reaction: "",
            reactions: [:],
            myReaction: ""
        )
        pendingOptIds.insert(tempId)
        self.messages.append(optimistic)

        var payload: [String: Any] = [
            "body": "",
            "text": "",
            "attachment": ["name": name, "data": dataURL],
            "requestId": reqId
        ]
        if let replyTarget {
            payload["replyToId"] = replyTarget.id
        }
        self.replyingToMessage = nil
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            pendingOptIds.remove(tempId)
            if let msgObj = res["message"] as? [String: Any] {
                var realMsg = DirectMessageItem.from(msgObj)
                if realMsg.imageUrl.isEmpty && !optimistic.imageUrl.isEmpty {
                    realMsg.imageUrl = optimistic.imageUrl
                }
                if realMsg.attachmentName.isEmpty && !optimistic.attachmentName.isEmpty {
                    realMsg.attachmentName = optimistic.attachmentName
                    realMsg.attachmentUrl = optimistic.attachmentUrl
                }
                if let existingRealIdx = self.messages.firstIndex(where: { $0.id == realMsg.id }) {
                    self.messages[existingRealIdx] = realMsg
                    self.messages.removeAll { $0.id == tempId }
                } else if let optIdx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages[optIdx] = realMsg
                } else {
                    self.messages.append(realMsg)
                }
            }
            await loadMessages()
        } catch {
            pendingOptIds.remove(tempId)
            self.messages.removeAll { $0.id == tempId }
            if self.replyingToMessage == nil {
                self.replyingToMessage = replyTarget
            }
            appState.showToast("Không gửi được tệp: \(error.localizedDescription)")
        }
    }

    private func deleteMessage(_ msg: DirectMessageItem) async {
        let reqId = "recall_dm_\(msg.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-messages/direct/\(msg.id)/recall",
                method: "POST",
                body: [:],
                requestId: reqId
            )
            await loadMessages()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func togglePinMessage(msgId: String, pinned: Bool) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-messages/direct/\(msgId)/pin",
                method: pinned ? "POST" : "DELETE",
                body: [:]
            )
            if pinned {
                pinnedMessageIds.insert(msgId)
                appState.showToast("Đã ghim tin nhắn.")
            } else {
                pinnedMessageIds.remove(msgId)
                appState.showToast("Đã bỏ ghim tin nhắn.")
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deleteMessageForMe(_ msg: DirectMessageItem) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-messages/direct/\(msg.id)",
                method: "DELETE",
                body: [:]
            )
            messages.removeAll { $0.id == msg.id }
            pinnedMessageIds.remove(msg.id)
            appState.showToast("Đã xóa tin nhắn ở phía bạn.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func updateDirectPreference(body: [String: Any], toast: String, dismissAfter: Bool = false) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-preferences/direct/\(peer.id)",
                method: "POST",
                body: body
            )
            appState.showToast(toast)
            if dismissAfter {
                NotificationCenter.default.post(name: .kinnectMessagesChanged, object: nil)
                dismiss()
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func clearDirectHistory() async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/messages",
                method: "DELETE",
                body: [:]
            )
            messages = []
            pinnedMessageIds = []
            appState.showToast("Đã xóa lịch sử trò chuyện.")
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: nil)
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func updateAIConsent(enabled: Bool) async {
        guard !isUpdatingAIConsent else { return }
        isUpdatingAIConsent = true
        defer { isUpdatingAIConsent = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/ai-consent",
                method: "POST",
                body: ["enabled": enabled]
            )
            let saved = (res["enabled"] as? Bool) ?? enabled
            aiSupportConsent = saved ? "enabled" : "disabled"
            appState.showToast(saved ? "Đã bật hỗ trợ AI Kinnect." : "Đã tắt hỗ trợ AI Kinnect.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func saveEditedMessage(messageId: String) async {
        let clean = editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let draft = editingMessageText
        editingMessageId = nil
        editingMessageText = ""
        let reqId = "edit_dm_\(messageId)_\(Int(Date().timeIntervalSince1970))"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/messages/\(messageId)",
                method: "PATCH",
                body: ["body": clean],
                requestId: reqId
            )
            await loadMessages()
        } catch {
            editingMessageId = messageId
            editingMessageText = draft
            appState.showToast(error.localizedDescription)
        }
    }
}

struct GroupChatDetailView: View {
    let group: ChatGroupItem
    let onLeftGroup: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var l10n = LocalizationManager.shared

    @State private var messages: [GroupMessageItem] = []
    @State private var groupMembers: [KinnectUser] = []
    @State private var displayGroupName: String
    @State private var displayGroupAvatarUrl: String
    @State private var displayGroupAvatarPreset: String = "violet"
    @State private var text = ""
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var isSending = false
    @State private var replyingToMessage: GroupMessageItem? = nil
    @State private var editingMessageId: String?
    @State private var editingMessageText: String = ""
    @State private var forwardText = ""
    @State private var forwardImageUrl = ""
    @State private var showForwardSheet = false
    @State private var showRenameSheet = false
    @State private var showAddMemberSheet = false
    @State private var showMembersSheet = false
    @State private var showPollsSheet = false
    @State private var showAvatarPickerSheet = false
    @State private var showSearchSheet = false
    @State private var showClearHistoryConfirm = false
    @State private var isGroupPinned = false
    @State private var isGroupMuted = false
    @State private var pinnedMessageIds: Set<String> = []
    @State private var fullscreenPhoto: ChatFullscreenPhotoItem? = nil
    @State private var selectedMentionUser: KinnectUser? = nil
    @State private var scrollTargetId: String? = nil
    @State private var activeGroupCallActive = false
    @State private var activeGroupCallMode = "audio"
    @State private var activeGroupCallCount = 0
    @State private var showGroupCallSheet = false
    @State private var groupCallLaunchMode = "audio"
    @State private var newGroupName = ""
    // Reaction state (Android parity)
    @State private var groupReactions: [String: String] = [:]
    @State private var showingReactionPicker = false
    @State private var reactionPickerMessageId: String = ""
    @State private var reactionPickerIsDirect = false
    @State private var reactionPickerFrame: CGRect = .zero
    @State private var hasMoreMessages = false
    @State private var nextMessagesCursor: Int64? = nil
    @State private var hasReachedHistoryStart = false
    @State private var isLoadingOlder = false
    @State private var pendingOptIds: Set<String> = []
    @State private var groupOwnerId: String = ""
    @State private var memberRoles: [String: String] = [:]
    @State private var notifRefreshTask: Task<Void, Never>? = nil
    @State private var loadError: String? = nil
    @State private var pendingBlockSender: KinnectUser? = nil
    @State private var pendingRecallGroupMessage: GroupMessageItem? = nil
    @State private var showLeaveGroupConfirm = false

    private var canManageGroup: Bool {
        guard let myId = appState.currentUser?.id, !myId.isEmpty else { return false }
        if !groupOwnerId.isEmpty && groupOwnerId == myId { return true }
        if let role = memberRoles[myId], role == "owner" || role == "deputy" { return true }
        if let me = groupMembers.first(where: { $0.id == myId }),
           me.groupRole == "owner" || me.groupRole == "deputy" {
            return true
        }
        return false
    }

    init(group: ChatGroupItem, onLeftGroup: @escaping () -> Void) {
        self.group = group
        self.onLeftGroup = onLeftGroup
        _displayGroupName = State(initialValue: group.name)
        _displayGroupAvatarUrl = State(initialValue: group.avatarUrl)
        _groupOwnerId = State(initialValue: group.ownerId)
        var initialRoles: [String: String] = [:]
        for m in group.members where !m.groupRole.isEmpty {
            initialRoles[m.id] = m.groupRole
        }
        _memberRoles = State(initialValue: initialRoles)
        if let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/groups/\(group.id)/messages"),
           let list = cached["messages"] as? [[String: Any]] {
            let initial = list.map(GroupMessageItem.from)
            _messages = State(initialValue: initial)
            var rx: [String: String] = [:]
            for m in initial where !m.myReaction.isEmpty { rx[m.id] = m.myReaction }
            _groupReactions = State(initialValue: rx)
            _hasMoreMessages = State(initialValue: (cached["hasMore"] as? Bool) ?? false)
            _nextMessagesCursor = State(initialValue: (cached["nextCursor"] as? NSNumber)?.int64Value)
        }
    }

    private var currentMentionQuery: String? {
        guard let lastAt = text.lastIndex(of: "@") else { return nil }
        if lastAt > text.startIndex {
            let before = text[text.index(before: lastAt)]
            if !before.isWhitespace && before != "(" && before != "[" {
                return nil
            }
        }
        let after = text[text.index(after: lastAt)...]
        if after.contains(" ") {
            return nil
        }
        return String(after).lowercased()
    }

    private var filteredMentionMembers: [KinnectUser] {
        let currentId = appState.currentUser?.id
        let pool = groupMembers.filter { $0.id != currentId }
        guard let query = currentMentionQuery, !query.isEmpty else { return pool }
        let q = chatSearchKey(query)
        return pool.filter {
            chatSearchKey($0.name).contains(q) ||
            chatSearchKey($0.handle).contains(q) ||
            chatSearchKey($0.username).contains(q)
        }
    }

    private func insertMention(tag: String) {
        guard let lastAt = text.lastIndex(of: "@") else { return }
        let prefix = text[..<lastAt]
        text = "\(prefix)@\(tag) "
    }

    private func showReactionPicker(for messageId: String, isDirect: Bool, frame: CGRect) {
        reactionPickerMessageId = messageId
        reactionPickerIsDirect = isDirect
        reactionPickerFrame = frame
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showingReactionPicker = true
        }
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private struct MentionSegment: Identifiable {
        let id = UUID()
        let text: String
        let member: KinnectUser?
    }

    private func mentionSegments(for rawText: String) -> [MentionSegment] {
        let nsText = rawText as NSString
        guard nsText.length > 0 else { return [] }
        let pattern = "(?<=^|[\\s(\\[\\{])@[\\p{L}\\p{N}_.-]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [MentionSegment(text: rawText, member: nil)]
        }
        let matches = regex.matches(in: rawText, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return [MentionSegment(text: rawText, member: nil)]
        }
        var segments: [MentionSegment] = []
        var cursor = 0
        for match in matches {
            let range = match.range
            if range.location > cursor {
                let plain = nsText.substring(with: NSRange(location: cursor, length: range.location - cursor))
                segments.append(MentionSegment(text: plain, member: nil))
            }
            let token = nsText.substring(with: range)
            let handleKey = String(token.dropFirst()).lowercased()
            let matchedMember = groupMembers.first { m in
                (!m.handle.isEmpty && m.handle.lowercased() == handleKey) ||
                (!m.username.isEmpty && m.username.lowercased() == handleKey)
            }
            segments.append(MentionSegment(text: token, member: matchedMember))
            cursor = range.location + range.length
        }
        if cursor < nsText.length {
            segments.append(MentionSegment(text: nsText.substring(from: cursor), member: nil))
        }
        return segments
    }

    @ViewBuilder
    private func interactiveBubbleText(_ rawText: String, isMine: Bool) -> some View {
        let segs = mentionSegments(for: rawText)
        let tappableMembers = segs.compactMap(\.member)
        let composedText = segs.reduce(Text("")) { acc, seg in
            let isMention = seg.text.hasPrefix("@")
            let piece = Text(seg.text)
                .font(.subheadline)
                .bold(isMention)
                .foregroundColor(isMention ? (isMine ? Color.white : KinnectTheme.accentBright) : (isMine ? Color.white : KinnectTheme.textPrimary))
                .underline(isMention)
            return acc + piece
        }
        if tappableMembers.isEmpty {
            composedText
        } else {
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                composedText
                HStack(spacing: 6) {
                    ForEach(tappableMembers) { member in
                        Button {
                            selectedMentionUser = member
                        } label: {
                            Text("@\(member.handle.isEmpty ? member.username : member.handle)")
                                .font(.caption2.bold())
                                .foregroundColor(isMine ? .white : KinnectTheme.accentBright)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(isMine ? Color.white.opacity(0.22) : KinnectTheme.accentSoft))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func roleBadgeText(for userId: String) -> String? {
        if !groupOwnerId.isEmpty && userId == groupOwnerId {
            return "· Trưởng nhóm"
        }
        let role = memberRoles[userId] ?? groupMembers.first(where: { $0.id == userId })?.groupRole ?? ""
        if role == "owner" { return "· Trưởng nhóm" }
        if role == "deputy" { return "· Phó nhóm" }
        return nil
    }

    @ViewBuilder
    private func groupMessageRow(msg: GroupMessageItem) -> some View {
        let isMine = (msg.sender.id == appState.currentUser?.id)
        let isRecalled = msg.recalled
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 44) }
            if !isMine {
                KinnectAvatarView(
                    name: msg.sender.name,
                    avatarURL: msg.sender.avatarUrl,
                    colorHex: msg.sender.avatarColor,
                    size: 30
                )
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if !isMine {
                    HStack(spacing: 4) {
                        Text(msg.sender.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(KinnectTheme.accentBright)
                        if let badge = roleBadgeText(for: msg.sender.id) {
                            Text(badge)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(KinnectTheme.messageMeta)
                        }
                    }
                    .padding(.leading, 4)
                }

                ZStack(alignment: isMine ? .topLeading : .topTrailing) {
                    VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                        if isRecalled {
                            Text(msg.text.isEmpty ? "Tin nhắn đã được thu hồi" : msg.text)
                                .font(.system(size: 15).italic())
                                .foregroundColor(KinnectTheme.textSecondary)
                                .kinnectMultiline()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    MessageBubbleShape(isMine: isMine)
                                        .fill(KinnectTheme.surfaceElevated.opacity(0.7))
                                )
                                .overlay(
                                    MessageBubbleShape(isMine: isMine)
                                        .stroke(KinnectTheme.borderSoft.opacity(0.8), lineWidth: 0.8)
                                )
                        } else {
                            if let q = msg.replyTo {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(q.senderName.isEmpty ? "Tin nhắn" : q.senderName)
                                        .font(.caption2.bold())
                                        .foregroundColor(isMine ? .white.opacity(0.9) : KinnectTheme.accentBright)
                                    Text(q.body.isEmpty ? "Tệp đính kèm" : q.body)
                                        .font(.caption)
                                        .foregroundColor(isMine ? .white.opacity(0.85) : KinnectTheme.textSecondary)
                                        .lineLimit(2)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 10).fill(isMine ? Color.white.opacity(0.18) : KinnectTheme.surfaceElevated))
                            }

                            // Image preview if present (tap to zoom)
                            if !msg.imageUrl.isEmpty {
                                Button {
                                    fullscreenPhoto = ChatFullscreenPhotoItem(rawURL: msg.imageUrl)
                                } label: {
                                    KinnectRemoteImageView(rawURL: msg.imageUrl, contentMode: .fill, cornerRadius: 16, maxHeight: 260)
                                        .frame(maxWidth: 260)
                                        .clipShape(MessageBubbleShape(isMine: isMine))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Xem ảnh toàn màn hình")
                            }
                            // File attachment card if present
                            if !msg.attachmentName.isEmpty {
                                ChatAttachmentBubbleView(fileName: msg.attachmentName, fileUrl: msg.attachmentUrl, isMine: isMine)
                            }
                            // Content on top with member mention highlight
                            if !msg.text.isEmpty {
                                interactiveBubbleText(msg.text, isMine: isMine)
                                    .kinnectMultiline()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        MessageBubbleShape(isMine: isMine)
                                            .fill(
                                                isMine
                                                    ? AnyShapeStyle(
                                                        LinearGradient(
                                                            colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    : AnyShapeStyle(KinnectTheme.surfaceElevated)
                                            )
                                    )
                                    .overlay(
                                        MessageBubbleShape(isMine: isMine)
                                            .stroke(
                                                isMine ? Color.clear : KinnectTheme.borderSoft.opacity(0.7),
                                                lineWidth: 0.8
                                            )
                                    )
                            }
                        }
                    }

                    // Floating Tapback reaction badge
                    if !isRecalled, let reacted = groupReactions[msg.id] {
                        FloatingReactionBadge(reaction: reacted, isMine: isMine)
                    }
                }

                // Reaction Summary (Android parity) - shows reaction counts on message
                if !isRecalled && !msg.reactions.isEmpty {
                    ReactionSummary(reactions: msg.reactions, myReaction: groupReactions[msg.id])
                        .padding(.horizontal, isMine ? 0 : 4)
                        .padding(.top, -2)
                }

                // Bottom row: time, edited badge, seen count, reaction, more
                groupMessageFooter(msg: msg, isMine: isMine)
            }
            if !isMine { Spacer(minLength: 44) }
        }
        // Reaction Picker Overlay (Android-style popup)
        .overlay(
            Group {
                if !isRecalled && showingReactionPicker && reactionPickerMessageId == msg.id && !reactionPickerIsDirect {
                    ReactionPicker(
                        messageId: msg.id,
                        currentReaction: groupReactions[msg.id],
                        reactionCounts: msg.reactions,
                        isMine: isMine,
                        onReact: { reactionKey in
                            Task { await reactToGroupMessage(msgId: msg.id, emoji: reactionKey) }
                        },
                        onDismiss: { showingReactionPicker = false }
                    )
                    .transition(.scale.combined(with: .opacity).combined(with: .move(edge: .top)))
                    .zIndex(100)
                }
            },
            alignment: isMine ? .topTrailing : .topLeading
        )
    }

    @ViewBuilder
    private func groupMessageFooter(msg: GroupMessageItem, isMine: Bool) -> some View {
            HStack(spacing: 6) {
                Text(formatRelativeDate(msg.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(KinnectTheme.messageMeta)

                if !msg.recalled && pinnedMessageIds.contains(msg.id) {
                    HStack(spacing: 2) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                        Text("Đã ghim")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(KinnectTheme.accentBright)
                }

                if !msg.recalled && !msg.editedAt.isEmpty {
                    Text("· Đã sửa")
                        .font(.system(size: 11))
                        .foregroundColor(KinnectTheme.messageMeta)
                }

                if isMine && !msg.recalled && msg.seenCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(msg.seenCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(KinnectTheme.accentBright)
                }

                if !msg.recalled && !msg.id.hasPrefix("opt_") {
                    // Reaction Picker Button - Long press to show picker, tap to quick react
                    Button {
                        // Quick react with default (love) on tap
                        Task { await reactToGroupMessage(msgId: msg.id, emoji: "❤️") }
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 12))
                            .foregroundColor(groupReactions[msg.id] != nil ? KinnectTheme.accentBright : KinnectTheme.messageMeta)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Thả cảm xúc tin nhắn nhóm")
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.35)
                            .onEnded { _ in
                                showReactionPicker(for: msg.id, isDirect: false, frame: .zero)
                            }
                    )

                    Menu {
                        Button {
                            replyingToMessage = msg
                        } label: {
                            Label("Trả lời", systemImage: "arrowshape.turn.up.left")
                        }

                        let isMsgPinned = pinnedMessageIds.contains(msg.id)
                        Button {
                            Task { await togglePinGroupMessage(msgId: msg.id, pinned: !isMsgPinned) }
                        } label: {
                            Label(isMsgPinned ? "Bỏ ghim tin nhắn" : "Ghim tin nhắn", systemImage: isMsgPinned ? "pin.slash" : "pin")
                        }

                        if isMine && !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                editingMessageId = msg.id
                                editingMessageText = msg.text
                            } label: {
                                Label("Sửa tin nhắn", systemImage: "pencil")
                            }
                        }

                        Button {
                            forwardText = msg.text
                            forwardImageUrl = msg.imageUrl
                            showForwardSheet = true
                        } label: {
                            Label("Chuyển tiếp", systemImage: "arrow.turn.up.right")
                        }

                        Button(role: .destructive) {
                            Task { await deleteGroupMessageForMe(msg) }
                        } label: {
                            Label("Xóa ở phía tôi", systemImage: "eye.slash")
                        }

                        if isMine {
                            Button(role: .destructive) {
                                pendingRecallGroupMessage = msg
                            } label: {
                                Label("Thu hồi tin nhắn", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                appState.activeReportContext = UGCReportContext(
                                    targetType: "group_message",
                                    targetId: msg.id,
                                    targetUserId: msg.sender.id,
                                    targetTitle: "Tin nhắn nhóm của \(msg.sender.name)"
                                )
                            } label: {
                                Label("Báo cáo tin nhắn", systemImage: "exclamationmark.bubble")
                            }
                            Button(role: .destructive) {
                                pendingBlockSender = msg.sender
                            } label: {
                                Label("Chặn người gửi", systemImage: "hand.raised.fill")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                            .foregroundColor(KinnectTheme.messageMeta)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tùy chọn tin nhắn nhóm")
                }
            }
            .padding(.horizontal, 4)
        }

    @ViewBuilder
    private var mentionSuggestionBar: some View {
        if currentMentionQuery != nil {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Nhắc thành viên (@)")
                        .font(.caption2.bold())
                        .foregroundColor(KinnectTheme.textSecondary)
                    Spacer()
                    Button {
                        text.append(" ")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Group members
                        ForEach(filteredMentionMembers) { u in
                            Button {
                                let tag = u.handle.isEmpty ? u.username : u.handle
                                insertMention(tag: tag)
                            } label: {
                                HStack(spacing: 6) {
                                    KinnectAvatarView(
                                        name: u.name,
                                        avatarURL: u.avatarUrl,
                                        colorHex: u.avatarColor,
                                        size: 28
                                    )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(u.name)
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(KinnectTheme.textPrimary)
                                        Text("@\(u.handle.isEmpty ? u.username : u.handle)")
                                            .font(.system(size: 9))
                                            .foregroundColor(KinnectTheme.textSecondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }
            }
            .background(KinnectTheme.surface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(KinnectTheme.border), alignment: .bottom)
        }
    }

    @ViewBuilder
    private var groupChatInputBar: some View {
        HStack(alignment: .bottom, spacing: 2) {
            Menu {
                if #available(iOS 17.0, *) {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Thư viện ảnh", systemImage: "photo.on.rectangle.angled")
                    }
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("Tệp & Tài liệu", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(KinnectTheme.messageMeta)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Đính kèm tệp hoặc ảnh")
            .disabled(isSending || editingMessageId != nil)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 19))
                    .foregroundColor((isSending || editingMessageId != nil) ? KinnectTheme.textSecondary.opacity(0.4) : KinnectTheme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isSending || editingMessageId != nil)
            .accessibilityLabel("Chọn ảnh gửi")
            .modifier(CompatPhotosPickerModifier(isPresented: $showPhotoPicker, selection: $selectedPhoto))
            .onChange(of: selectedPhoto) { newItem in
                guard let newItem else { return }
                selectedPhoto = nil
                guard !isSending else { return }
                Task { @MainActor in
                    guard let data = try? await newItem.loadTransferable(type: Data.self),
                          let dataURL = await compressChatPhotoToDataURL(data) else {
                        appState.showToast("Không thể xử lý ảnh đã chọn (tối đa 4.5 MB sau khi nén).")
                        return
                    }
                    await sendGroupMessage(text: text, imageDataURL: dataURL)
                }
            }

            // Mention shortcut button (@)
            Button {
                if !text.hasSuffix("@") {
                    if text.isEmpty || text.hasSuffix(" ") {
                        text.append("@")
                    } else {
                        text.append(" @")
                    }
                }
            } label: {
                Text("@")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor((isSending || editingMessageId != nil) ? KinnectTheme.textSecondary.opacity(0.4) : KinnectTheme.accentBright)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isSending || editingMessageId != nil)
            .accessibilityLabel("Nhắc tên thành viên")

            if let activeEditId = editingMessageId {
                HStack(spacing: 6) {
                    TextField(
                        "",
                        text: $editingMessageText,
                        prompt: Text("Nội dung tin nhắn mới...").foregroundColor(KinnectTheme.textSecondary)
                    )
                    .font(.system(size: 16))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(KinnectTheme.textPrimary)

                    Button {
                        Task { await saveEditedGroupMessage(messageId: activeEditId) }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? KinnectTheme.messageMeta : KinnectTheme.accentBright)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Lưu tin nhắn đã sửa")
                }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(KinnectTheme.surfaceElevated)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KinnectTheme.borderSoft, lineWidth: 0.8))
                )
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    TextField(
                        "",
                        text: $text,
                        prompt: Text("Tin nhắn nhóm…").foregroundColor(KinnectTheme.textSecondary),
                        axis: .vertical
                    )
                    .lineLimit(1...5)
                    .font(.system(size: 16))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            Task { await sendGroupMessage(text: text, imageDataURL: "") }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(isSending)
                        .accessibilityLabel("Gửi tin nhắn")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(KinnectTheme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(KinnectTheme.borderSoft.opacity(0.8), lineWidth: 0.8)
                        )
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Divider().background(KinnectTheme.borderSoft)
        }
    }

    private var groupHeaderBar: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(KinnectTheme.accentBright)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quay lại")

            // Group Avatar + Title
            HStack(spacing: 10) {
                if !displayGroupAvatarUrl.isEmpty {
                    KinnectAvatarView(
                        name: displayGroupName,
                        avatarURL: displayGroupAvatarUrl,
                        colorHex: groupPresetColor(displayGroupAvatarPreset),
                        size: 38
                    )
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [groupPresetPrimary(displayGroupAvatarPreset), Color(hex: "#4A00E0")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayGroupName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("\(max(groupMembers.count, 1)) \(L10n.tr("thành viên"))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(KinnectTheme.messageMeta)
                        .lineLimit(1)
                }
                .layoutPriority(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 2) {
                Button {
                    launchGroupCall(mode: "audio")
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#2E9E66").opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#2E9E66"))
                    }
                    .frame(minWidth: 40, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Gọi thoại nhóm"))

                Button {
                    launchGroupCall(mode: "video")
                } label: {
                    ZStack {
                        Circle()
                            .fill(KinnectTheme.accentBright.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: "video.fill")
                            .font(.system(size: 14))
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    .frame(minWidth: 40, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Gọi video nhóm"))

                Menu {
                    Button {
                        showPollsSheet = true
                    } label: {
                        Label("Bình chọn nhóm", systemImage: "chart.bar.fill")
                    }
                    Button {
                        showSearchSheet = true
                    } label: {
                        Label(L10n.tr("Tìm kiếm tin nhắn"), systemImage: "magnifyingglass")
                    }
                    if canManageGroup {
                        Button {
                            newGroupName = displayGroupName
                            showRenameSheet = true
                        } label: {
                            Label("Đổi tên nhóm", systemImage: "pencil")
                        }
                        Button {
                            showAvatarPickerSheet = true
                        } label: {
                            Label("Đổi ảnh nhóm", systemImage: "photo.circle")
                        }
                        Button {
                            showAddMemberSheet = true
                        } label: {
                            Label("Thêm thành viên", systemImage: "person.badge.plus")
                        }
                    }
                    Button {
                        showMembersSheet = true
                    } label: {
                        Label("Thành viên & phân quyền", systemImage: "person.3")
                    }
                    Button {
                        Task {
                            let next = !isGroupPinned
                            await updateGroupPreference(body: ["pinned": next], toast: next ? "Đã ghim nhóm." : "Đã bỏ ghim nhóm.")
                            isGroupPinned = next
                        }
                    } label: {
                        Label(isGroupPinned ? "Bỏ ghim nhóm" : "Ghim nhóm", systemImage: isGroupPinned ? "pin.slash" : "pin")
                    }
                    Button {
                        Task {
                            let next = !isGroupMuted
                            await updateGroupPreference(body: ["muted": next], toast: next ? "Đã tắt thông báo nhóm." : "Đã bật thông báo nhóm.")
                            isGroupMuted = next
                        }
                    } label: {
                        Label(isGroupMuted ? "Bật thông báo" : "Tắt thông báo", systemImage: isGroupMuted ? "bell" : "bell.slash")
                    }
                    Button {
                        Task { await updateGroupPreference(body: ["unread": true], toast: "Đã đánh dấu chưa đọc.", dismissAfter: true) }
                    } label: {
                        Label("Đánh dấu chưa đọc", systemImage: "envelope.badge")
                    }
                    Button {
                        Task { await updateGroupPreference(body: ["hidden": true], toast: "Đã ẩn nhóm chat.", dismissAfter: true) }
                    } label: {
                        Label("Ẩn nhóm chat", systemImage: "eye.slash")
                    }
                    Button(role: .destructive) {
                        showClearHistoryConfirm = true
                    } label: {
                        Label("Xóa lịch sử trò chuyện", systemImage: "trash")
                    }
                    Button(role: .destructive) {
                        showLeaveGroupConfirm = true
                    } label: {
                        Label("Rời nhóm", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(KinnectTheme.surfaceElevated)
                            .frame(width: 34, height: 34)
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .frame(minWidth: 40, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn nhóm")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(KinnectTheme.surface)
        .overlay(alignment: .bottom) {
            Divider().background(KinnectTheme.borderSoft)
        }
    }

    private var groupMessagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let loadError, messages.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundColor(KinnectTheme.messageMeta)
                            Text("Không thể tải tin nhắn nhóm")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text(loadError)
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Button {
                                Task { await loadGroupMessages() }
                            } label: {
                                Text("Thử lại")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 20)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 44)
                    }
                    if hasMoreMessages, nextMessagesCursor != nil {
                        Button {
                            Task { await loadOlderMessages() }
                        } label: {
                            Text(isLoadingOlder ? "Đang tải…" : "Xem tin nhắn cũ hơn")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.accentBright)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        }
                        .disabled(isLoadingOlder)
                    }
                    ForEach(messages) { msg in
                        groupMessageRow(msg: msg)
                            .id(msg.id)
                    }
                }
                .padding(14)
            }
            .onAppear {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.id) { lastId in
                if let lastId {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
            .onChange(of: scrollTargetId) { targetId in
                if let targetId {
                    withAnimation {
                        proxy.scrollTo(targetId, anchor: .center)
                    }
                    scrollTargetId = nil
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            groupHeaderBar

            if activeGroupCallActive {
                HStack(spacing: 10) {
                    Image(systemName: activeGroupCallMode == "video" ? "video.fill" : "phone.fill")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Text(String(format: L10n.tr("Cuộc gọi nhóm đang diễn ra (%d người)"), max(1, activeGroupCallCount)))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Button(L10n.tr("Tham gia")) {
                        launchGroupCall(mode: activeGroupCallMode)
                    }
                    .font(.caption.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(KinnectTheme.online)
            }

            if let firstPinned = messages.last(where: { pinnedMessageIds.contains($0.id) && !$0.recalled }) {
                Button {
                    scrollTargetId = firstPinned.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(firstPinned.text.isEmpty ? L10n.tr("Tin nhắn đã ghim") : firstPinned.text)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(KinnectTheme.surfaceElevated)
                }
                .buttonStyle(.plain)
            }

            groupMessagesScrollView

            mentionSuggestionBar

            if let reply = replyingToMessage {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(KinnectTheme.accentBright)
                        .frame(width: 3, height: 28)
                        .cornerRadius(2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Đang trả lời \(reply.sender.id == appState.currentUser?.id ? "chính bạn" : reply.sender.name)")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(reply.text.isEmpty ? "Tệp đính kèm" : reply.text)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        replyingToMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(KinnectTheme.textSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hủy trả lời")
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .padding(.vertical, 2)
                .background(KinnectTheme.surfaceElevated)
            }

            if let editId = editingMessageId {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(KinnectTheme.accentBright)
                    Text("Đang sửa tin nhắn")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                    Spacer()
                    Button("Hủy") {
                        editingMessageId = nil
                        editingMessageText = ""
                    }
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                    Button("Lưu") {
                        Task { await saveEditedGroupMessage(messageId: editId) }
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(KinnectTheme.surfaceElevated)
            }

            groupChatInputBar
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showForwardSheet) {
            ForwardMessageSheet(text: forwardText, imageUrl: forwardImageUrl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showForwardSheet)
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameGroupSheet(groupId: group.id, currentName: displayGroupName) { updatedName in
                if !updatedName.isEmpty {
                    displayGroupName = updatedName
                }
                onLeftGroup()
                Task { await loadGroupMessages() }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showRenameSheet)
        }
        .sheet(isPresented: $showMembersSheet) {
            GroupMembersView(groupId: group.id)
        }
        .sheet(isPresented: $showAddMemberSheet) {
            AddGroupMembersSheet(
                groupId: group.id,
                existingMemberIds: Set(groupMembers.map(\.id))
            ) {
                Task {
                    await loadGroupMeta()
                    await loadGroupMessages()
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showAddMemberSheet)
        }
        .sheet(isPresented: $showPollsSheet) {
            GroupPollsSheet(groupId: group.id, canManage: canManageGroup)
        }
        .sheet(isPresented: $showAvatarPickerSheet) {
            GroupAvatarPickerSheet(
                groupId: group.id,
                currentPreset: displayGroupAvatarPreset
            ) { newUrl, newPreset in
                displayGroupAvatarUrl = newUrl
                displayGroupAvatarPreset = newPreset
                onLeftGroup()
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            ChatMessageSearchSheet(kind: "group", targetId: group.id, title: displayGroupName) { targetId in
                scrollTargetId = targetId
            }
        }
        .fullScreenCover(item: $fullscreenPhoto) { item in
            ChatFullscreenImageSheet(rawURL: item.rawURL)
        }
        .sheet(item: $selectedMentionUser) { member in
            NavigationStack {
                ProfileView(targetUser: member)
            }
        }
        .fullScreenCover(isPresented: $showGroupCallSheet) {
            GroupCallSheet(
                groupId: group.id,
                groupName: displayGroupName,
                initialMode: groupCallLaunchMode
            )
        }
        .alert("Xóa lịch sử trò chuyện?", isPresented: $showClearHistoryConfirm) {
            Button("Hủy", role: .cancel) {}
            Button("Xóa lịch sử", role: .destructive) {
                Task { await clearGroupHistory() }
            }
        } message: {
            Text("Toàn bộ tin nhắn trong nhóm \"\(displayGroupName)\" sẽ bị ẩn ở phía bạn.")
        }
        .alert("Rời nhóm \"\(displayGroupName)\"?", isPresented: $showLeaveGroupConfirm) {
            Button("Rời nhóm", role: .destructive) {
                Task { await leaveGroup() }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Bạn sẽ không còn nhận được tin nhắn mới từ nhóm này.")
        }
        .alert(
            "Thu hồi tin nhắn?",
            isPresented: Binding(
                get: { pendingRecallGroupMessage != nil },
                set: { if !$0 { pendingRecallGroupMessage = nil } }
            ),
            presenting: pendingRecallGroupMessage
        ) { msg in
            Button("Thu hồi tin nhắn", role: .destructive) {
                pendingRecallGroupMessage = nil
                Task { await recallGroupMessage(msg) }
            }
            Button("Hủy", role: .cancel) {
                pendingRecallGroupMessage = nil
            }
        } message: { _ in
            Text("Tin nhắn sẽ được thu hồi với mọi thành viên trong nhóm.")
        }
        .alert(
            "Chặn người gửi?",
            isPresented: Binding(
                get: { pendingBlockSender != nil },
                set: { if !$0 { pendingBlockSender = nil } }
            ),
            presenting: pendingBlockSender
        ) { sender in
            Button("Chặn người dùng", role: .destructive) {
                pendingBlockSender = nil
                Task { await appState.blockUser(userId: sender.id, userName: sender.name) }
            }
            Button("Hủy", role: .cancel) {
                pendingBlockSender = nil
            }
        } message: { sender in
            Text("\(sender.name) sẽ không thể nhắn tin hoặc xem nội dung của bạn.")
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let fileURL):
                guard !isSending else { return }
                guard fileURL.startAccessingSecurityScopedResource() else {
                    appState.showToast("Không có quyền truy cập tệp đã chọn.")
                    return
                }
                let maxBytes = 20 * 1024 * 1024
                if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = values.fileSize,
                   fileSize > maxBytes {
                    fileURL.stopAccessingSecurityScopedResource()
                    appState.showToast("Tệp vượt quá giới hạn 20 MB.")
                    return
                }
                let fileName = fileURL.lastPathComponent
                let ext = fileURL.pathExtension
                Task.detached(priority: .userInitiated) {
                    defer { fileURL.stopAccessingSecurityScopedResource() }
                    guard let data = try? Data(contentsOf: fileURL) else {
                        await MainActor.run {
                            appState.showToast("Không thể đọc tệp đã chọn.")
                        }
                        return
                    }
                    if data.count > maxBytes {
                        await MainActor.run {
                            appState.showToast("Tệp vượt quá giới hạn 20 MB.")
                        }
                        return
                    }
                    let base64 = data.base64EncodedString()
                    let mime = mimeTypeForExt(ext)
                    let dataURL = "data:\(mime);base64,\(base64)"
                    await MainActor.run {
                        Task {
                            await sendGroupFileMessage(name: fileName, dataURL: dataURL)
                        }
                    }
                }
            case .failure(let err):
                appState.showToast("Không thể chọn tệp: \(err.localizedDescription)")
            }
        }
        .task {
            SocketEventBridge.installIfNeeded()
            if groupMembers.isEmpty {
                groupMembers = group.members
            }
            await loadGroupPreferences()
            await loadGroupMeta()
            await loadGroupCallState()
            await loadGroupMessages()
        }
        .onReceive(NotificationCenter.default.publisher(for: SocketEventBridge.rawEventNotification)) { notif in
            guard let json = notif.userInfo as? [String: Any],
                  let type = json["type"] as? String,
                  (json["groupId"] as? String) == group.id else { return }
            if type == "group-call-state" {
                activeGroupCallActive = (json["active"] as? Bool) == true
                activeGroupCallMode = (json["mode"] as? String) ?? "audio"
                activeGroupCallCount = (json["participants"] as? [[String: Any]])?.count ?? 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectMessagesChanged)) { note in
            guard note.userInfo?["markReadKind"] == nil else { return }
            Task { await loadGroupMessages() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectNotificationsChanged)) { _ in
            notifRefreshTask?.cancel()
            notifRefreshTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await loadGroupMessages()
            }
        }
        .onDisappear {
            notifRefreshTask?.cancel()
            notifRefreshTask = nil
        }
    }

    private func loadGroupMeta() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/groups/\(group.id)"),
           let gObj = res["group"] as? [String: Any] {
            if let owner = gObj["owner"] as? String, !owner.isEmpty {
                self.groupOwnerId = owner
            }
            if let gName = gObj["name"] as? String, !gName.isEmpty {
                self.displayGroupName = gName
            }
            if let av = gObj["avatar"] as? String {
                self.displayGroupAvatarUrl = av
            }
            if let preset = gObj["avatarPreset"] as? String, !preset.isEmpty {
                self.displayGroupAvatarPreset = preset
            }
            if let pinned = gObj["pinned"] as? Bool {
                self.isGroupPinned = pinned
            }
            if let muted = gObj["muted"] as? Bool {
                self.isGroupMuted = muted
            }
            if let rawMembers = gObj["members"] as? [[String: Any]] {
                self.groupMembers = rawMembers.map(KinnectUser.from)
                var roles: [String: String] = [:]
                for m in rawMembers {
                    if let uid = m["id"] as? String, let r = m["groupRole"] as? String {
                        roles[uid] = r
                    }
                }
                self.memberRoles = roles
            }
        }
    }

    private func syncGroupMembersFromMessages() {
        for m in self.messages {
            if !groupMembers.contains(where: { $0.id == m.sender.id }) {
                groupMembers.append(m.sender)
            }
        }
    }

    private func loadGroupMessages() async {
        if messages.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/groups/\(group.id)/messages"),
           let list = cached["messages"] as? [[String: Any]] {
            self.messages = list.map(GroupMessageItem.from)
            var rx: [String: String] = [:]
            for m in self.messages where !m.myReaction.isEmpty {
                rx[m.id] = m.myReaction
            }
            self.groupReactions = rx
            syncGroupMembersFromMessages()
        }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/groups/\(group.id)/messages")
            let list = res["messages"] as? [[String: Any]] ?? []
            var newPinned = self.pinnedMessageIds
            for rawMsg in list {
                if let mid = rawMsg["id"] as? String {
                    if (rawMsg["pinned"] as? Bool) == true {
                        newPinned.insert(mid)
                    } else {
                        newPinned.remove(mid)
                    }
                }
            }
            self.pinnedMessageIds = newPinned
            let latest = list.map(GroupMessageItem.from)
            let latestIds = Set(latest.map(\.id))
            let inFlightOpt = self.messages.filter { pendingOptIds.contains($0.id) && !latestIds.contains($0.id) }
            let merged: [GroupMessageItem]
            if self.messages.isEmpty || latest.isEmpty {
                merged = latest + inFlightOpt
            } else if let oldestLatestTime = latest.first?.createdAt, !oldestLatestTime.isEmpty {
                let older = self.messages.filter {
                    !latestIds.contains($0.id) && !$0.id.hasPrefix("opt_") && !$0.createdAt.isEmpty && $0.createdAt < oldestLatestTime
                }
                merged = older + latest + inFlightOpt
            } else {
                merged = latest + inFlightOpt
            }
            if hasReachedHistoryStart {
                self.hasMoreMessages = false
            } else if self.nextMessagesCursor == nil {
                self.hasMoreMessages = (res["hasMore"] as? Bool) ?? false
                self.nextMessagesCursor = (res["nextCursor"] as? NSNumber)?.int64Value
                if !self.hasMoreMessages {
                    self.hasReachedHistoryStart = true
                }
            }
            let sig: ([GroupMessageItem]) -> [String] = { arr in
                arr.map { msg in
                    let rxSig = msg.reactions.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: ",")
                    return "\(msg.id)|\(msg.text)|\(msg.recalled)|\(msg.editedAt)|\(msg.seenCount)|\(msg.myReaction)|\(rxSig)|\(msg.imageUrl)|\(msg.attachmentUrl)"
                }
            }
            if sig(merged) != sig(self.messages) {
                self.messages = merged
            }
            var rx: [String: String] = [:]
            for m in self.messages where !m.myReaction.isEmpty {
                rx[m.id] = m.myReaction
            }
            self.groupReactions = rx
            self.loadError = nil
            syncGroupMembersFromMessages()
            postMessagesMarkedRead(kind: "group", id: group.id)
            await appState.refreshGlobalBadges()
        } catch {
            if self.messages.isEmpty {
                self.loadError = error.localizedDescription
            }
        }
    }

    private func loadOlderMessages() async {
        guard hasMoreMessages, let cursor = nextMessagesCursor, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/groups/\(group.id)/messages?limit=50&before=\(cursor)") {
            let older = (res["messages"] as? [[String: Any]] ?? []).map(GroupMessageItem.from)
            let existing = Set(self.messages.map(\.id))
            let newlyAdded = older.filter { !existing.contains($0.id) }
            self.messages = newlyAdded + self.messages
            for m in newlyAdded where !m.myReaction.isEmpty {
                self.groupReactions[m.id] = m.myReaction
            }
            let more = (res["hasMore"] as? Bool) ?? false
            self.hasMoreMessages = more
            self.nextMessagesCursor = (res["nextCursor"] as? NSNumber)?.int64Value
            if !more || self.nextMessagesCursor == nil {
                self.hasReachedHistoryStart = true
            }
            syncGroupMembersFromMessages()
        }
    }

    private func reactToGroupMessage(msgId: String, emoji: String) async {
        guard !msgId.hasPrefix("opt_") else { return }
        if let existing = messages.first(where: { $0.id == msgId }), existing.recalled { return }
        guard let canonicalKey = DirectMessageItem.canonical(for: emoji) else { return }
        let previous = groupReactions[msgId]
        let isTogglingOff = (previous == canonicalKey)
        let newKey: String? = isTogglingOff ? nil : canonicalKey

        // Optimistic update
        if let newKey {
            groupReactions[msgId] = newKey
        } else {
            groupReactions.removeValue(forKey: msgId)
        }

        do {
            let bodyVal: Any = newKey ?? NSNull()
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-messages/group/\(msgId)/reaction",
                method: "POST",
                body: ["reaction": bodyVal]
            )
            if let msgObj = res["message"] as? [String: Any] {
                let updated = GroupMessageItem.from(msgObj)
                if let idx = messages.firstIndex(where: { $0.id == msgId }) {
                    messages[idx].reactions = updated.reactions
                    messages[idx].myReaction = updated.myReaction
                    messages[idx].reaction = updated.myReaction
                }
                if !updated.myReaction.isEmpty {
                    groupReactions[msgId] = updated.myReaction
                } else {
                    groupReactions.removeValue(forKey: msgId)
                }
            }
        } catch {
            // Revert on failure
            if let previous {
                groupReactions[msgId] = previous
            } else {
                groupReactions.removeValue(forKey: msgId)
            }
            appState.showToast("Không thể gửi cảm xúc: \(error.localizedDescription)")
        }
    }

    private func sendGroupMessage(text: String, imageDataURL: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || !imageDataURL.isEmpty else { return }
        guard !isSending else { return }
        let draft = self.text
        self.text = ""
        isSending = true
        defer { isSending = false }
        let reqId = "grp_msg_\(group.id)_\(UUID().uuidString)"
        let tempId = "opt_\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())

        let optimistic = GroupMessageItem(
            id: tempId,
            groupId: group.id,
            sender: appState.currentUser ?? KinnectUser.fallbackSelf,
            text: clean,
            imageUrl: imageDataURL,
            attachmentName: "",
            attachmentUrl: "",
            createdAt: createdAt,
            seenCount: 0,
            reaction: "",
            reactions: [:],
            myReaction: ""
        )
        pendingOptIds.insert(tempId)
        self.messages.append(optimistic)

        var payload: [String: Any] = [
            "body": clean,
            "text": clean,
            "requestId": reqId
        ]
        let replyTarget = self.replyingToMessage
        if let replyTarget {
            payload["replyToId"] = replyTarget.id
        }
        self.replyingToMessage = nil
        if !imageDataURL.isEmpty {
            payload["attachment"] = ["data": imageDataURL, "name": "photo.jpg"]
        }
        let currentUserId = appState.currentUser?.id
        let mentionedIds = groupMembers.filter { m in
            guard m.id != currentUserId else { return false }
            let handleToken = m.handle.isEmpty ? m.username : m.handle
            return chatContentContainsMention(clean, username: handleToken)
                || (!m.username.isEmpty && chatContentContainsMention(clean, username: m.username))
        }.map(\.id)
        if !mentionedIds.isEmpty {
            payload["mentions"] = mentionedIds
        }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(group.id)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            pendingOptIds.remove(tempId)
            if let msgObj = res["message"] as? [String: Any] {
                var realMsg = GroupMessageItem.from(msgObj)
                if realMsg.imageUrl.isEmpty && !optimistic.imageUrl.isEmpty {
                    realMsg.imageUrl = optimistic.imageUrl
                }
                if let existingRealIdx = self.messages.firstIndex(where: { $0.id == realMsg.id }) {
                    self.messages[existingRealIdx] = realMsg
                    self.messages.removeAll { $0.id == tempId }
                } else if let optIdx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages[optIdx] = realMsg
                } else {
                    self.messages.append(realMsg)
                }
            } else {
                await loadGroupMessages()
            }
            if !imageDataURL.isEmpty {
                await loadGroupMessages()
            }
        } catch {
            pendingOptIds.remove(tempId)
            self.messages.removeAll { $0.id == tempId }
            self.text = draft
            if self.replyingToMessage == nil {
                self.replyingToMessage = replyTarget
            }
            appState.showToast(error.localizedDescription)
        }
    }

    private func sendGroupFileMessage(name: String, dataURL: String) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        let isImg = dataURL.hasPrefix("data:image/") || name.hasSuffix(".jpg") || name.hasSuffix(".png") || name.hasSuffix(".webp")
        let reqId = "grp_att_\(group.id)_\(UUID().uuidString)"
        let tempId = "opt_\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let replyTarget = self.replyingToMessage

        let optimistic = GroupMessageItem(
            id: tempId,
            groupId: group.id,
            sender: appState.currentUser ?? KinnectUser.fallbackSelf,
            text: "",
            imageUrl: isImg ? dataURL : "",
            attachmentName: isImg ? "" : name,
            attachmentUrl: isImg ? "" : dataURL,
            createdAt: createdAt,
            seenCount: 0,
            reaction: "",
            reactions: [:],
            myReaction: ""
        )
        pendingOptIds.insert(tempId)
        self.messages.append(optimistic)

        var payload: [String: Any] = [
            "body": "",
            "text": "",
            "attachment": ["name": name, "data": dataURL],
            "requestId": reqId
        ]
        if let replyTarget {
            payload["replyToId"] = replyTarget.id
        }
        self.replyingToMessage = nil
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(group.id)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            pendingOptIds.remove(tempId)
            if let msgObj = res["message"] as? [String: Any] {
                var realMsg = GroupMessageItem.from(msgObj)
                if realMsg.imageUrl.isEmpty && !optimistic.imageUrl.isEmpty {
                    realMsg.imageUrl = optimistic.imageUrl
                }
                if realMsg.attachmentName.isEmpty && !optimistic.attachmentName.isEmpty {
                    realMsg.attachmentName = optimistic.attachmentName
                    realMsg.attachmentUrl = optimistic.attachmentUrl
                }
                if let existingRealIdx = self.messages.firstIndex(where: { $0.id == realMsg.id }) {
                    self.messages[existingRealIdx] = realMsg
                    self.messages.removeAll { $0.id == tempId }
                } else if let optIdx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages[optIdx] = realMsg
                } else {
                    self.messages.append(realMsg)
                }
            }
            await loadGroupMessages()
        } catch {
            pendingOptIds.remove(tempId)
            self.messages.removeAll { $0.id == tempId }
            if self.replyingToMessage == nil {
                self.replyingToMessage = replyTarget
            }
            appState.showToast("Không gửi được tệp: \(error.localizedDescription)")
        }
    }

    private func recallGroupMessage(_ msg: GroupMessageItem) async {
        let reqId = "recall_grp_\(msg.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-messages/group/\(msg.id)/recall",
                method: "POST",
                body: [:],
                requestId: reqId
            )
            await loadGroupMessages()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func saveEditedGroupMessage(messageId: String) async {
        let clean = editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let draft = editingMessageText
        editingMessageId = nil
        editingMessageText = ""
        let reqId = "edit_grp_\(messageId)_\(Int(Date().timeIntervalSince1970))"
        let currentUserId = appState.currentUser?.id
        let mentionedIds = groupMembers.filter { m in
            guard m.id != currentUserId else { return false }
            let handleToken = m.handle.isEmpty ? m.username : m.handle
            return chatContentContainsMention(clean, username: handleToken)
                || (!m.username.isEmpty && chatContentContainsMention(clean, username: m.username))
        }.map(\.id)
        var bodyPayload: [String: Any] = ["body": clean]
        if !mentionedIds.isEmpty {
            bodyPayload["mentions"] = mentionedIds
        }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(group.id)/messages/\(messageId)",
                method: "PATCH",
                body: bodyPayload,
                requestId: reqId
            )
            await loadGroupMessages()
        } catch {
            editingMessageId = messageId
            editingMessageText = draft
            appState.showToast(error.localizedDescription)
        }
    }

    private func togglePinGroupMessage(msgId: String, pinned: Bool) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-messages/group/\(msgId)/pin",
                method: pinned ? "POST" : "DELETE",
                body: [:]
            )
            if pinned {
                pinnedMessageIds.insert(msgId)
                appState.showToast("Đã ghim tin nhắn.")
            } else {
                pinnedMessageIds.remove(msgId)
                appState.showToast("Đã bỏ ghim tin nhắn.")
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deleteGroupMessageForMe(_ msg: GroupMessageItem) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-messages/group/\(msg.id)",
                method: "DELETE",
                body: [:]
            )
            messages.removeAll { $0.id == msg.id }
            pinnedMessageIds.remove(msg.id)
            appState.showToast("Đã xóa tin nhắn ở phía bạn.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func loadGroupPreferences() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/chat-preferences/group/\(group.id)") {
            let pref = (res["preference"] as? [String: Any]) ?? (res["preferences"] as? [String: Any]) ?? res
            if let pinned = pref["pinned"] as? Bool { self.isGroupPinned = pinned }
            if let muted = pref["muted"] as? Bool { self.isGroupMuted = muted }
        }
    }

    private func updateGroupPreference(body: [String: Any], toast: String, dismissAfter: Bool = false) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/chat-preferences/group/\(group.id)",
                method: "POST",
                body: body
            )
            appState.showToast(toast)
            if dismissAfter {
                NotificationCenter.default.post(name: .kinnectMessagesChanged, object: nil)
                onLeftGroup()
                dismiss()
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func clearGroupHistory() async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(group.id)/messages",
                method: "DELETE",
                body: [:]
            )
            messages = []
            pinnedMessageIds = []
            appState.showToast("Đã xóa lịch sử trò chuyện.")
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: nil)
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func loadGroupCallState() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/groups/\(group.id)/call") {
            activeGroupCallActive = (res["active"] as? Bool) == true
            activeGroupCallMode = (res["mode"] as? String) ?? "audio"
            activeGroupCallCount = (res["participants"] as? [[String: Any]])?.count ?? 0
        }
    }

    private func launchGroupCall(mode: String) {
        groupCallLaunchMode = mode
        showGroupCallSheet = true
    }

    private func groupPresetColor(_ preset: String) -> String {
        switch preset {
        case "ocean": return "#0EA5E9"
        case "sunset": return "#F97316"
        case "forest": return "#10B981"
        default: return group.avatarColor
        }
    }

    private func groupPresetPrimary(_ preset: String) -> Color {
        switch preset {
        case "ocean": return Color(hex: "#0EA5E9")
        case "sunset": return Color(hex: "#F97316")
        case "forest": return Color(hex: "#10B981")
        default: return Color(hex: "#8E2DE2")
        }
    }

    private func leaveGroup() async {
        let reqId = "leave_grp_\(group.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(group.id)/leave",
                method: "POST",
                body: [:],
                requestId: reqId
            )
            onLeftGroup()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct NewDirectChatPickerSheet: View {
    let onSelectPeer: (KinnectUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var friends: [KinnectUser] = []
    @State private var searchQuery = ""
    @State private var isLoading = false

    private var filteredFriends: [KinnectUser] {
        let clean = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return friends }
        let q = chatSearchKey(clean.hasPrefix("@") ? String(clean.dropFirst()) : clean)
        return friends.filter { chatSearchKey($0.name).contains(q) || chatSearchKey($0.handle).contains(q) }
    }

    private var onlineFriends: [KinnectUser] {
        filteredFriends.filter { $0.showActivity && ($0.isActive || appState.onlineUserIds.contains($0.id)) }
    }

    private var offlineFriends: [KinnectUser] {
        filteredFriends.filter { !($0.showActivity && ($0.isActive || appState.onlineUserIds.contains($0.id))) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(KinnectTheme.textSecondary)
                    TextField("Tìm bạn bè để nhắn tin…", text: $searchQuery)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                .padding(.horizontal, 14)

                if isLoading {
                    ProgressView().padding(.vertical, 30)
                    Spacer()
                } else if filteredFriends.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 36))
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text(searchQuery.isEmpty ? "Chưa có bạn bè nào để nhắn tin" : "Không tìm thấy bạn bè phù hợp")
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                } else {
                    List {
                        if !onlineFriends.isEmpty {
                            Section {
                                ForEach(onlineFriends) { friend in
                                    friendPickerRow(friend)
                                }
                            } header: {
                                Text("Đang trực tuyến (\(onlineFriends.count))")
                                    .font(.caption.bold())
                                    .foregroundColor(Color(hex: "#2E9E66"))
                            }
                        }

                        if !offlineFriends.isEmpty {
                            Section {
                                ForEach(offlineFriends) { friend in
                                    friendPickerRow(friend)
                                }
                            } header: {
                                Text("Ngoại tuyến (\(offlineFriends.count))")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(KinnectTheme.background)
                }
            }
            .navigationTitle("Tin nhắn mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                isLoading = true
                defer { isLoading = false }
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
                    let list = (res["users"] as? [[String: Any]]) ?? (res["friends"] as? [[String: Any]]) ?? []
                    self.friends = list.map(KinnectUser.from)
                }
            }
        }
    }

    private func friendPickerRow(_ friend: KinnectUser) -> some View {
        Button {
            dismiss()
            onSelectPeer(friend)
        } label: {
            HStack(spacing: 12) {
                KinnectAvatarView(
                    name: friend.name,
                    avatarURL: friend.avatarUrl,
                    colorHex: friend.avatarColor,
                    size: 44,
                    isOnline: friend.showActivity && (friend.isActive || appState.onlineUserIds.contains(friend.id))
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                    Text("@\(friend.handle.isEmpty ? friend.name : friend.handle)")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "bubble.right.fill")
                    .foregroundColor(KinnectTheme.accentBright)
                    .font(.subheadline)
            }
            .padding(.vertical, 4)
        }
    }
}

struct CreateGroupSheet: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var name = ""
    @State private var description = ""
    @State private var friends: [KinnectUser] = []
    @State private var selectedIds: Set<String> = []
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin nhóm") {
                    TextField("Tên nhóm trò chuyện", text: $name)
                    TextField("Mô tả nhóm", text: $description)
                }

                Section("Chọn thành viên từ bạn bè") {
                    ForEach(friends) { friend in
                        Button {
                            if selectedIds.contains(friend.id) {
                                selectedIds.remove(friend.id)
                            } else {
                                selectedIds.insert(friend.id)
                            }
                        } label: {
                            HStack {
                                Text(friend.name)
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Spacer()
                                Image(systemName: selectedIds.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Tạo nhóm mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo") {
                        Task { await create() }
                    }
                    .disabled(isCreating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
                    let list = (res["users"] as? [[String: Any]]) ?? (res["friends"] as? [[String: Any]]) ?? []
                    self.friends = list.map(KinnectUser.from)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let reqId = "create_grp_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups",
                method: "POST",
                body: [
                    "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                    "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
                    "members": Array(selectedIds),
                    "memberIds": Array(selectedIds)
                ],
                requestId: reqId
            )
            onCreated()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct ForwardMessageSheet: View {
    let text: String
    let imageUrl: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var conversations: [[String: Any]] = []
    @State private var groups: [ChatGroupItem] = []
    @State private var friends: [KinnectUser] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if !conversations.isEmpty {
                    Section("Hội thoại gần đây") {
                        ForEach(Array(conversations.enumerated()), id: \.offset) { _, conv in
                            let peer = extractPeer(from: conv)
                            if !peer.id.isEmpty {
                                Button {
                                    Task { await forwardToUser(peer.id, name: peer.name) }
                                } label: {
                                    HStack(spacing: 12) {
                                        KinnectAvatarView(name: peer.name, avatarURL: peer.avatarUrl, colorHex: peer.avatarColor, size: 36)
                                        Text(peer.name).foregroundColor(KinnectTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "paperplane.fill").foregroundColor(KinnectTheme.accentBright)
                                    }
                                }
                            }
                        }
                    }
                }

                if !groups.isEmpty {
                    Section("Nhóm trò chuyện") {
                        ForEach(groups) { g in
                            Button {
                                Task { await forwardToGroup(g.id, name: g.name) }
                            } label: {
                                HStack(spacing: 12) {
                                    KinnectAvatarView(name: g.name, avatarURL: g.avatarUrl, colorHex: g.avatarColor, size: 36)
                                    Text(g.name).foregroundColor(KinnectTheme.textPrimary)
                                    Spacer()
                                    Image(systemName: "paperplane.fill").foregroundColor(KinnectTheme.accentBright)
                                }
                            }
                        }
                    }
                }

                if !friends.isEmpty {
                    Section("Bạn bè") {
                        ForEach(friends) { f in
                            Button {
                                Task { await forwardToUser(f.id, name: f.name) }
                            } label: {
                                HStack(spacing: 12) {
                                    KinnectAvatarView(name: f.name, avatarURL: f.avatarUrl, colorHex: f.avatarColor, size: 36)
                                    Text(f.name).foregroundColor(KinnectTheme.textPrimary)
                                    Spacer()
                                    Image(systemName: "paperplane.fill").foregroundColor(KinnectTheme.accentBright)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Chuyển tiếp tin nhắn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadTargets()
            }
        }
    }

    private func extractPeer(from conv: [String: Any]) -> KinnectUser {
        if let u = conv["user"] as? [String: Any] ?? conv["peer"] as? [String: Any] {
            return KinnectUser.from(u)
        }
        return KinnectUser.from(conv)
    }

    private func loadTargets() async {
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            self.conversations = [
                [
                    "peer": [
                        "id": "u2",
                        "name": "Lê Hoàng Nam",
                        "handle": "hoangnam",
                        "avatarColor": "#2563EB"
                    ]
                ],
                [
                    "peer": [
                        "id": "u3",
                        "name": "Trần Thanh Trúc",
                        "handle": "thanhtruc",
                        "avatarColor": "#EC4899"
                    ]
                ]
            ]
            self.groups = [
                ChatGroupItem.from([
                    "id": "fixture_group_1",
                    "name": "Nhóm Thiết Kế Kinnect",
                    "description": "Trao đổi ý tưởng sáng tạo và nhiếp ảnh",
                    "avatarColor": "#6D4AFF",
                    "membersCount": 4,
                    "lastMessageText": "Hẹn gặp mọi người tối nay nhé!",
                    "unreadCount": 0
                ])
            ]
            self.friends = [
                KinnectUser.from([
                    "id": "u4",
                    "name": "Linh Nhi",
                    "handle": "linhnhi",
                    "avatarColor": "#8B5CF6"
                ])
            ]
            return
        }
        #endif
        isLoading = true
        defer { isLoading = false }
        if let cRes = try? await KinnectAPIClient.shared.requestJSON("/api/conversations") {
            self.conversations = (cRes["users"] as? [[String: Any]]) ?? (cRes["conversations"] as? [[String: Any]]) ?? []
        }
        if let gRes = try? await KinnectAPIClient.shared.requestJSON("/api/groups") {
            self.groups = (gRes["groups"] as? [[String: Any]] ?? []).map(ChatGroupItem.from)
        }
        if let fRes = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
            let list = (fRes["users"] as? [[String: Any]]) ?? (fRes["friends"] as? [[String: Any]]) ?? []
            self.friends = list.map(KinnectUser.from)
        }
    }

    private func buildForwardPayload(reqId: String) async -> [String: Any] {
        var payload: [String: Any] = [
            "body": text,
            "text": text,
            "imageUrl": imageUrl,
            "requestId": reqId
        ]
        if !imageUrl.isEmpty {
            if imageUrl.hasPrefix("data:") {
                payload["attachment"] = ["name": "photo.jpg", "data": imageUrl]
            } else if let data = await KinnectAPIClient.shared.fetchBinaryData(path: imageUrl) {
                let b64 = await Task.detached(priority: .userInitiated) {
                    data.base64EncodedString()
                }.value
                payload["attachment"] = ["name": "photo.jpg", "data": "data:image/jpeg;base64,\(b64)"]
            }
        }
        return payload
    }

    private func forwardToUser(_ userId: String, name: String) async {
        let reqId = "fwd_u_\(userId)_\(UUID().uuidString)"
        let payload = await buildForwardPayload(reqId: reqId)
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(userId)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            appState.showToast("Đã chuyển tiếp tới \(name)!")
            dismiss()
        } catch {
            appState.showToast("Không thể chuyển tiếp: \(error.localizedDescription)")
        }
    }

    private func forwardToGroup(_ groupId: String, name: String) async {
        let reqId = "fwd_g_\(groupId)_\(UUID().uuidString)"
        let payload = await buildForwardPayload(reqId: reqId)
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            appState.showToast("Đã chuyển tiếp tới nhóm \(name)!")
            dismiss()
        } catch {
            appState.showToast("Không thể chuyển tiếp: \(error.localizedDescription)")
        }
    }
}

struct RenameGroupSheet: View {
    let groupId: String
    let currentName: String
    let onRenamed: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var name: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tên nhóm mới") {
                    TextField("Nhập tên nhóm", text: $name)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Đổi tên nhóm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = currentName
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)",
                method: "PATCH",
                body: ["name": clean]
            )
            appState.showToast("Đã đổi tên nhóm thành '\(clean)'.")
            onRenamed(clean)
            dismiss()
        } catch {
            appState.showToast("Lỗi đổi tên: \(error.localizedDescription)")
        }
    }
}

struct AddGroupMembersSheet: View {
    let groupId: String
    var existingMemberIds: Set<String> = []
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var friends: [KinnectUser] = []
    @State private var selectedIds: Set<String> = []
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List(friends) { friend in
                Button {
                    if selectedIds.contains(friend.id) {
                        selectedIds.remove(friend.id)
                    } else {
                        selectedIds.insert(friend.id)
                    }
                } label: {
                    HStack {
                        KinnectAvatarView(name: friend.name, avatarURL: friend.avatarUrl, colorHex: friend.avatarColor, size: 36)
                        Text(friend.name).foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        Image(systemName: selectedIds.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Thêm thành viên")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Thêm (\(selectedIds.count))") {
                        Task { await add() }
                    }
                    .disabled(isAdding || selectedIds.isEmpty)
                }
            }
            .task {
                var currentIds = existingMemberIds
                if currentIds.isEmpty,
                   let grpRes = try? await KinnectAPIClient.shared.requestJSON("/api/groups/\(groupId)"),
                   let grpObj = grpRes["group"] as? [String: Any],
                   let rawMembers = grpObj["members"] as? [[String: Any]] {
                    for m in rawMembers {
                        if let uid = m["id"] as? String { currentIds.insert(uid) }
                    }
                }
                if let myId = appState.currentUser?.id, !myId.isEmpty {
                    currentIds.insert(myId)
                }
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
                    let raw = (res["users"] as? [[String: Any]]) ?? (res["friends"] as? [[String: Any]]) ?? []
                    self.friends = raw.map(KinnectUser.from).filter { !$0.id.isEmpty && !currentIds.contains($0.id) }
                }
            }
        }
    }

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/members",
                method: "POST",
                body: ["members": Array(selectedIds)]
            )
            appState.showToast("Đã thêm thành viên vào nhóm!")
            onAdded()
            dismiss()
        } catch {
            appState.showToast("Lỗi thêm thành viên: \(error.localizedDescription)")
        }
    }
}

// MARK: - Group Polls Sheet (GET/POST /api/groups/:id/polls)
private struct GroupPollsSheet: View {
    let groupId: String
    let canManage: Bool
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    struct PollOption: Identifiable {
        let id: String
        let label: String
        let votes: Int
        let voted: Bool
    }

    struct PollItem: Identifiable {
        let id: String
        let creatorId: String
        let creatorName: String
        let question: String
        let multiple: Bool
        let closed: Bool
        let totalVotes: Int
        let totalVoters: Int
        let options: [PollOption]
    }

    @State private var polls: [PollItem] = []
    @State private var isLoading = true
    @State private var showCreateForm = false
    @State private var newQuestion = ""
    @State private var newOptions: [String] = ["", ""]
    @State private var allowMultiple = false
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            List {
                if showCreateForm {
                    Section("Tạo bình chọn mới") {
                        TextField("Câu hỏi bình chọn…", text: $newQuestion)
                        ForEach(newOptions.indices, id: \.self) { idx in
                            HStack {
                                TextField("Lựa chọn \(idx + 1)", text: $newOptions[idx])
                                if newOptions.count > 2 {
                                    Button(role: .destructive) {
                                        newOptions.remove(at: idx)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(KinnectTheme.danger)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if newOptions.count < 10 {
                            Button {
                                newOptions.append("")
                            } label: {
                                Label("Thêm lựa chọn", systemImage: "plus.circle")
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                        Toggle("Cho phép chọn nhiều phương án", isOn: $allowMultiple)
                            .tint(KinnectTheme.accentBright)
                        HStack {
                            Button("Hủy") {
                                showCreateForm = false
                            }
                            .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            Button(isSubmitting ? "Đang tạo…" : "Đăng bình chọn") {
                                Task { await createPoll() }
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                            .disabled(isSubmitting)
                        }
                    }
                }

                if isLoading && polls.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Đang tải bình chọn…")
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                } else if polls.isEmpty {
                    Text("Chưa có bình chọn nào trong nhóm.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                } else {
                    ForEach(polls) { poll in
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(poll.question)
                                        .font(.headline)
                                        .foregroundColor(KinnectTheme.textPrimary)
                                    Spacer()
                                    if poll.closed {
                                        Text("Đã đóng")
                                            .font(.caption2.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(KinnectTheme.messageMeta))
                                    }
                                }

                                Text("\(poll.creatorName) · \(poll.totalVoters) người đã chọn\(poll.multiple ? " · Chọn nhiều" : "")")
                                    .font(.caption2)
                                    .foregroundColor(KinnectTheme.textSecondary)

                                ForEach(poll.options) { opt in
                                    let ratio = poll.totalVotes > 0 ? Double(opt.votes) / Double(poll.totalVotes) : 0
                                    Button {
                                        guard !poll.closed else { return }
                                        Task { await toggleVote(poll: poll, option: opt) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Image(systemName: opt.voted ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(opt.voted ? KinnectTheme.accentBright : KinnectTheme.messageMeta)
                                                Text(opt.label)
                                                    .font(.subheadline)
                                                    .foregroundColor(KinnectTheme.textPrimary)
                                                Spacer()
                                                Text("\(opt.votes)")
                                                    .font(.caption.bold())
                                                    .foregroundColor(KinnectTheme.accentBright)
                                            }
                                            ProgressView(value: ratio)
                                                .tint(opt.voted ? KinnectTheme.accentBright : KinnectTheme.messageMeta)
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(opt.voted ? KinnectTheme.accentSoft : KinnectTheme.surfaceElevated)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(poll.closed || isSubmitting)
                                }

                                if !poll.closed && (canManage || poll.creatorId == appState.currentUser?.id) {
                                    Button(role: .destructive) {
                                        Task { await closePoll(poll.id) }
                                    } label: {
                                        Text("Đóng bình chọn")
                                            .font(.caption.bold())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Bình chọn nhóm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showCreateForm.toggle() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Tạo bình chọn mới")
                }
            }
            .task {
                await loadPolls()
            }
            .refreshable {
                await loadPolls()
            }
        }
    }

    private func parsePoll(_ dict: [String: Any]) -> PollItem {
        let creator = dict["creator"] as? [String: Any]
        let rawOpts = dict["options"] as? [[String: Any]] ?? []
        let opts = rawOpts.map { o in
            PollOption(
                id: (o["id"] as? String) ?? UUID().uuidString,
                label: (o["label"] as? String) ?? "",
                votes: (o["votes"] as? Int) ?? (o["votes"] as? NSNumber)?.intValue ?? 0,
                voted: (o["voted"] as? Bool) == true
            )
        }
        return PollItem(
            id: (dict["id"] as? String) ?? UUID().uuidString,
            creatorId: (dict["creatorId"] as? String) ?? "",
            creatorName: (creator?["name"] as? String) ?? "Thành viên",
            question: (dict["question"] as? String) ?? "",
            multiple: (dict["multiple"] as? Bool) == true,
            closed: (dict["closed"] as? Bool) == true,
            totalVotes: (dict["totalVotes"] as? Int) ?? (dict["totalVotes"] as? NSNumber)?.intValue ?? 0,
            totalVoters: (dict["totalVoters"] as? Int) ?? (dict["totalVoters"] as? NSNumber)?.intValue ?? 0,
            options: opts
        )
    }

    @MainActor
    private func loadPolls() async {
        isLoading = true
        defer { isLoading = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/groups/\(groupId)/polls"),
           let raw = res["polls"] as? [[String: Any]] {
            polls = raw.map(parsePoll)
        }
    }

    @MainActor
    private func createPoll() async {
        let q = newQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let opts = newOptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !q.isEmpty, opts.count >= 2 else {
            appState.showToast("Nhập câu hỏi và ít nhất 2 lựa chọn.")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/polls",
                method: "POST",
                body: ["question": q, "options": opts, "multiple": allowMultiple]
            )
            newQuestion = ""
            newOptions = ["", ""]
            allowMultiple = false
            showCreateForm = false
            await loadPolls()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    @MainActor
    private func toggleVote(poll: PollItem, option: PollOption) async {
        isSubmitting = true
        defer { isSubmitting = false }
        var nextIds: [String]
        if poll.multiple {
            let current = poll.options.filter(\.voted).map(\.id)
            if option.voted {
                nextIds = current.filter { $0 != option.id }
            } else {
                nextIds = current + [option.id]
            }
        } else {
            nextIds = option.voted ? [] : [option.id]
        }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/polls/\(poll.id)/vote",
                method: "POST",
                body: ["optionIds": nextIds]
            )
            if let pollDict = res["poll"] as? [String: Any],
               let idx = polls.firstIndex(where: { $0.id == poll.id }) {
                polls[idx] = parsePoll(pollDict)
            } else {
                await loadPolls()
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    @MainActor
    private func closePoll(_ pollId: String) async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/polls/\(pollId)/close",
                method: "POST",
                body: [:]
            )
            await loadPolls()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Group Avatar Picker Sheet (4 Presets + Gallery Upload)
private struct GroupAvatarPickerSheet: View {
    let groupId: String
    let currentPreset: String
    let onUpdated: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var isSaving = false

    private let presets: [(id: String, name: String, colors: [Color])] = [
        ("violet", "Tím Kinnect", [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")]),
        ("ocean", "Đại dương", [Color(hex: "#0EA5E9"), Color(hex: "#2563EB")]),
        ("sunset", "Hoàng hôn", [Color(hex: "#F97316"), Color(hex: "#EC4899")]),
        ("forest", "Rừng xanh", [Color(hex: "#10B981"), Color(hex: "#059669")])
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Ảnh mẫu có sẵn") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(presets, id: \.id) { preset in
                            Button {
                                Task { await applyPreset(preset.id) }
                            } label: {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 56, height: 56)
                                        .overlay(
                                            Image(systemName: "person.2.fill")
                                                .foregroundColor(.white)
                                        )
                                        .overlay(
                                            Circle().stroke(currentPreset == preset.id ? KinnectTheme.accentBright : Color.clear, lineWidth: 3)
                                        )
                                    Text(preset.name)
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Tải ảnh từ thư viện") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(isSaving ? "Đang tải ảnh…" : "Chọn ảnh từ thư viện", systemImage: "photo.on.rectangle.angled")
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    .disabled(isSaving)
                    .onChange(of: selectedPhoto) { item in
                        guard let item else { return }
                        selectedPhoto = nil
                        Task { await uploadPickedPhoto(item) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Đổi ảnh nhóm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @MainActor
    private func applyPreset(_ presetId: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/avatar",
                method: "POST",
                body: ["preset": presetId]
            )
            let grp = res["group"] as? [String: Any]
            let newAv = (grp?["avatar"] as? String) ?? ""
            onUpdated(newAv, presetId)
            appState.showToast("Đã cập nhật ảnh nhóm.")
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    @MainActor
    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        isSaving = true
        defer { isSaving = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let dataURL = await compressChatPhotoToDataURL(data, maxDimension: 512, maxBytes: 900_000) else {
            appState.showToast("Không xử lý được ảnh (tối đa 1 MB).")
            return
        }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/avatar",
                method: "POST",
                body: ["data": dataURL]
            )
            let grp = res["group"] as? [String: Any]
            let newAv = (grp?["avatar"] as? String) ?? dataURL
            onUpdated(newAv, (grp?["avatarPreset"] as? String) ?? "violet")
            appState.showToast("Đã cập nhật ảnh nhóm.")
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Group Call Manager & Sheet (WebSocket group-call-* + WebRTC Mesh)
private struct GroupCallParticipantItem: Identifiable {
    let id: String // peerId
    let userId: String
    let name: String
    let avatarUrl: String
    var muted: Bool
    var video: Bool
}

@MainActor
private final class GroupCallSessionManager: NSObject, ObservableObject {
    @Published var participants: [GroupCallParticipantItem] = []
    @Published var remoteVideoTracks: [String: RTCVideoTrack] = [:]
    @Published var localVideoTrack: RTCVideoTrack? = nil
    @Published var isMicMuted = false
    @Published var isCameraOff = false
    @Published var usingFrontCamera = true
    @Published var statusText = L10n.tr("Đang tham gia cuộc gọi nhóm…")
    @Published var shouldDismiss = false

    private let groupId: String
    private let initialMode: String
    private var selfPeerId = ""
    private var hasJoined = false
    private let factory = RTCPeerConnectionFactory()
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var pendingIceByPeer: [String: [RTCIceCandidate]] = [:]
    private var iceServers: [RTCIceServer] = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
    private var localAudioTrack: RTCAudioTrack?
    private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCCameraVideoCapturer?

    init(groupId: String, mode: String) {
        self.groupId = groupId
        self.initialMode = mode
        self.isCameraOff = (mode != "video")
        super.init()
    }

    func start() async {
        SocketEventBridge.installIfNeeded()
        _ = await MediaPermissionHandler.shared.requestMicrophoneAccess()
        if initialMode == "video" {
            _ = await MediaPermissionHandler.shared.requestCameraAccess()
        }
        if let cfg = try? await KinnectAPIClient.shared.requestJSON("/api/call-config"),
           let rawIce = cfg["iceServers"] as? [[String: Any]] {
            let parsed = rawIce.compactMap { item -> RTCIceServer? in
                let urls = (item["urls"] as? [String]) ?? ((item["urls"] as? String).map { [$0] } ?? [])
                guard !urls.isEmpty else { return nil }
                return RTCIceServer(
                    urlStrings: urls,
                    username: item["username"] as? String,
                    credential: item["credential"] as? String
                )
            }
            if !parsed.isEmpty { iceServers = parsed }
        }
        _ = try? await KinnectAPIClient.shared.requestJSON("/api/groups/\(groupId)/call")
        prepareLocalMedia(video: initialMode == "video")
        guard await NativeSocketClient.shared.ensureConnected() else {
            statusText = L10n.tr("Chưa kết nối được máy chủ.")
            return
        }
        NativeSocketClient.shared.sendJSON([
            "type": "group-call-join",
            "groupId": groupId,
            "mode": initialMode
        ])
    }

    func handleSocketEvent(_ json: [String: Any]) {
        guard let type = json["type"] as? String,
              type.hasPrefix("group-call-"),
              (json["groupId"] as? String) == groupId || (json["groupId"] as? String)?.isEmpty == true else {
            return
        }
        switch type {
        case "group-call-joined":
            hasJoined = true
            selfPeerId = (json["selfId"] as? String) ?? ""
            statusText = L10n.tr("Đang trong cuộc gọi nhóm")
            updateParticipants(from: json["participants"] as? [[String: Any]])
            let peers = json["peers"] as? [String] ?? []
            for peerId in peers where peerId != selfPeerId {
                createPeerConnection(for: peerId, shouldOffer: true)
            }
        case "group-call-state":
            updateParticipants(from: json["participants"] as? [[String: Any]])
        case "group-call-peer-joined":
            if let peerId = json["peerId"] as? String, !peerId.isEmpty, peerId != selfPeerId {
                statusText = L10n.tr("Đang trong cuộc gọi nhóm")
                createPeerConnection(for: peerId, shouldOffer: false)
            }
        case "group-call-peer-left":
            if let peerId = json["peerId"] as? String {
                closePeer(peerId)
            }
        case "group-call-signal":
            if let fromPeer = json["from"] as? String, !fromPeer.isEmpty {
                handleSignal(from: fromPeer, json: json)
            }
        case "group-call-ended":
            leave()
            shouldDismiss = true
        case "group-call-error":
            let msg = (json["message"] as? String) ?? L10n.tr("Lỗi cuộc gọi nhóm.")
            AppState.shared.showToast(msg)
            statusText = msg
        default:
            break
        }
    }

    func toggleMute() {
        isMicMuted.toggle()
        localAudioTrack?.isEnabled = !isMicMuted
        NativeSocketClient.shared.sendJSON([
            "type": "group-call-media",
            "muted": isMicMuted,
            "video": !isCameraOff
        ])
    }

    func toggleCamera() {
        if isCameraOff && localVideoTrack == nil {
            Task { @MainActor in
                let ok = await MediaPermissionHandler.shared.requestCameraAccess()
                guard ok else { return }
                setupLocalVideoTrack()
                isCameraOff = false
                if let video = localVideoTrack {
                    for (peerId, pc) in peerConnections {
                        pc.add(video, streamIds: ["kinnect_group_stream"])
                        renegotiatePeer(peerId)
                    }
                }
                NativeSocketClient.shared.sendJSON([
                    "type": "group-call-media",
                    "muted": isMicMuted,
                    "video": true
                ])
            }
            return
        }
        isCameraOff.toggle()
        localVideoTrack?.isEnabled = !isCameraOff
        NativeSocketClient.shared.sendJSON([
            "type": "group-call-media",
            "muted": isMicMuted,
            "video": !isCameraOff
        ])
    }

    func flipCamera() {
        usingFrontCamera.toggle()
        if let cap = videoCapturer {
            startCapture(on: cap, front: usingFrontCamera)
        }
    }

    func leave() {
        if hasJoined {
            NativeSocketClient.shared.sendJSON(["type": "group-call-leave", "groupId": groupId])
            hasJoined = false
        }
        videoCapturer?.stopCapture()
        videoCapturer = nil
        videoSource = nil
        localAudioTrack = nil
        localVideoTrack = nil
        for pc in peerConnections.values {
            pc.close()
        }
        peerConnections.removeAll()
        pendingIceByPeer.removeAll()
        remoteVideoTracks.removeAll()
        let rtcAudio = RTCAudioSession.sharedInstance()
        rtcAudio.isAudioEnabled = false
        rtcAudio.audioSessionDidDeactivate(AVAudioSession.sharedInstance())
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MediaPermissionHandler.shared.configureAudioSessionForMedia()
    }

    private func prepareLocalMedia(video: Bool) {
        MediaPermissionHandler.shared.configureAudioSessionForCall(speaker: true, activate: true)
        let rtcAudio = RTCAudioSession.sharedInstance()
        rtcAudio.audioSessionDidActivate(AVAudioSession.sharedInstance())
        rtcAudio.isAudioEnabled = true

        let aSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let aTrack = factory.audioTrack(with: aSource, trackId: "grp_audio0")
        aTrack.isEnabled = true
        localAudioTrack = aTrack
        if video {
            setupLocalVideoTrack()
        }
    }

    private func setupLocalVideoTrack() {
        let vSource = factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: vSource)
        let vTrack = factory.videoTrack(with: vSource, trackId: "grp_video0")
        vTrack.isEnabled = true
        self.videoSource = vSource
        self.videoCapturer = capturer
        self.localVideoTrack = vTrack
        startCapture(on: capturer, front: usingFrontCamera)
    }

    private func startCapture(on capturer: RTCCameraVideoCapturer, front: Bool) {
        let pos: AVCaptureDevice.Position = front ? .front : .back
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == pos }) ?? devices.first else { return }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        guard let format = formats.last else { return }
        let fps = format.videoSupportedFrameRateRanges.first.map { Int(min($0.maxFrameRate, 24)) } ?? 24
        capturer.startCapture(with: device, format: format, fps: fps)
    }

    private func updateParticipants(from raw: [[String: Any]]?) {
        guard let raw else { return }
        participants = raw.map { item in
            GroupCallParticipantItem(
                id: (item["peerId"] as? String) ?? UUID().uuidString,
                userId: (item["userId"] as? String) ?? "",
                name: (item["name"] as? String) ?? L10n.tr("Thành viên"),
                avatarUrl: (item["avatar"] as? String) ?? "",
                muted: (item["muted"] as? Bool) == true,
                video: (item["video"] as? Bool) == true
            )
        }
    }

    @MainActor
    private func renegotiatePeer(_ peerId: String) {
        guard let pc = peerConnections[peerId], pc.signalingState == .stable else { return }
        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
            optionalConstraints: nil
        )
        pc.offer(for: offerConstraints) { [weak self] sdp, err in
            guard err == nil, let sdp else { return }
            let sdpString = sdp.sdp
            pc.setLocalDescription(sdp) { [weak self] setErr in
                guard setErr == nil else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.peerConnections[peerId] === pc else { return }
                    NativeSocketClient.shared.sendJSON([
                        "type": "group-call-signal",
                        "groupId": self.groupId,
                        "to": peerId,
                        "description": ["type": "offer", "sdp": sdpString]
                    ])
                }
            }
        }
    }

    @discardableResult
    private func createPeerConnection(for peerId: String, shouldOffer: Bool) -> RTCPeerConnection? {
        if let existing = peerConnections[peerId] {
            return existing
        }
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return nil }
        peerConnections[peerId] = pc
        if let audio = localAudioTrack { pc.add(audio, streamIds: ["kinnect_group_stream"]) }
        if let video = localVideoTrack { pc.add(video, streamIds: ["kinnect_group_stream"]) }

        if shouldOffer {
            renegotiatePeer(peerId)
        }
        return pc
    }

    private func handleSignal(from peerId: String, json: [String: Any]) {
        let pc = peerConnections[peerId] ?? createPeerConnection(for: peerId, shouldOffer: false)
        guard let pc else { return }
        if let desc = json["description"] as? [String: Any],
           let typeStr = desc["type"] as? String,
           (typeStr == "offer" || typeStr == "answer"),
           let sdpStr = desc["sdp"] as? String {
            let sdpType: RTCSdpType = (typeStr == "offer") ? .offer : .answer
            let remoteDesc = RTCSessionDescription(type: sdpType, sdp: sdpStr)
            if sdpType == .answer, pc.signalingState != .haveLocalOffer {
                return
            }
            if sdpType == .offer, pc.signalingState == .haveLocalOffer {
                if !selfPeerId.isEmpty && selfPeerId > peerId {
                    return
                }
                let rollback = RTCSessionDescription(type: .rollback, sdp: "")
                pc.setLocalDescription(rollback) { [weak self] err in
                    guard err == nil else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.peerConnections[peerId] === pc else { return }
                        self.applyRemoteDescription(remoteDesc, for: peerId, on: pc)
                    }
                }
                return
            }
            applyRemoteDescription(remoteDesc, for: peerId, on: pc)
        } else if let cand = json["candidate"] as? [String: Any],
                  let sdp = cand["candidate"] as? String {
            let mid = cand["sdpMid"] as? String
            let mline = (cand["sdpMLineIndex"] as? Int32) ?? (cand["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0
            let ice = RTCIceCandidate(sdp: sdp, sdpMLineIndex: mline, sdpMid: mid)
            if pc.remoteDescription != nil {
                pc.add(ice) { _ in }
            } else {
                pendingIceByPeer[peerId, default: []].append(ice)
            }
        }
    }

    private func applyRemoteDescription(_ remoteDesc: RTCSessionDescription, for peerId: String, on pc: RTCPeerConnection) {
        pc.setRemoteDescription(remoteDesc) { [weak self] err in
            guard err == nil else { return }
            Task { @MainActor [weak self] in
                guard let self, self.peerConnections[peerId] === pc else { return }
                self.drainIce(for: peerId, on: pc)
                if remoteDesc.type == .offer {
                    let ansConstraints = RTCMediaConstraints(
                        mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
                        optionalConstraints: nil
                    )
                    pc.answer(for: ansConstraints) { [weak self] ans, ansErr in
                        guard ansErr == nil, let ans else { return }
                        let answerSdp = ans.sdp
                        pc.setLocalDescription(ans) { [weak self] setErr in
                            guard setErr == nil else { return }
                            Task { @MainActor [weak self] in
                                guard let self, self.peerConnections[peerId] === pc else { return }
                                NativeSocketClient.shared.sendJSON([
                                    "type": "group-call-signal",
                                    "groupId": self.groupId,
                                    "to": peerId,
                                    "description": ["type": "answer", "sdp": answerSdp]
                                ])
                            }
                        }
                    }
                }
            }
        }
    }

    private func drainIce(for peerId: String, on pc: RTCPeerConnection) {
        let queued = pendingIceByPeer.removeValue(forKey: peerId) ?? []
        for ice in queued {
            pc.add(ice) { _ in }
        }
    }

    private func closePeer(_ peerId: String) {
        peerConnections[peerId]?.close()
        peerConnections.removeValue(forKey: peerId)
        pendingIceByPeer.removeValue(forKey: peerId)
        remoteVideoTracks.removeValue(forKey: peerId)
    }

    private func peerId(for pc: RTCPeerConnection) -> String? {
        peerConnections.first(where: { $0.value === pc })?.key
    }
}

extension GroupCallSessionManager: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let track = stream.videoTracks.first
        Task { @MainActor [weak self] in
            guard let self, let track, let pid = self.peerId(for: peerConnection) else { return }
            self.remoteVideoTracks[pid] = track
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let sdp = candidate.sdp
        let mline = candidate.sdpMLineIndex
        let mid = candidate.sdpMid ?? ""
        Task { @MainActor [weak self] in
            guard let self, let pid = self.peerId(for: peerConnection) else { return }
            NativeSocketClient.shared.sendJSON([
                "type": "group-call-signal",
                "groupId": self.groupId,
                "to": pid,
                "candidate": ["candidate": sdp, "sdpMLineIndex": mline, "sdpMid": mid]
            ])
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard let vTrack = rtpReceiver.track as? RTCVideoTrack else { return }
        Task { @MainActor [weak self] in
            guard let self, let pid = self.peerId(for: peerConnection) else { return }
            self.remoteVideoTracks[pid] = vTrack
        }
    }
}

private struct GroupCallSheet: View {
    let groupId: String
    let groupName: String
    let initialMode: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared
    @StateObject private var manager: GroupCallSessionManager

    init(groupId: String, groupName: String, initialMode: String) {
        self.groupId = groupId
        self.groupName = groupName
        self.initialMode = initialMode
        _manager = StateObject(wrappedValue: GroupCallSessionManager(groupId: groupId, mode: initialMode))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(groupName)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Text(manager.statusText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.top, 16)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        // Local tile
                        ZStack(alignment: .bottomLeading) {
                            if let localTrack = manager.localVideoTrack, !manager.isCameraOff {
                                WebRTCVideoRendererView(track: localTrack, mirror: manager.usingFrontCamera)
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(red: 0.14, green: 0.14, blue: 0.2))
                                    .frame(height: 180)
                                    .overlay(
                                        KinnectAvatarView(
                                            name: AppState.shared.currentUser?.name ?? L10n.tr("Bạn"),
                                            avatarURL: AppState.shared.currentUser?.avatarUrl ?? "",
                                            colorHex: AppState.shared.currentUser?.avatarColor ?? "#7C3AED",
                                            size: 56
                                        )
                                    )
                            }
                            Text(manager.isMicMuted ? L10n.tr("Bạn (Tắt mic)") : L10n.tr("Bạn"))
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                                .padding(8)
                        }

                        // Remote participants
                        ForEach(manager.participants.filter { $0.userId != AppState.shared.currentUser?.id }) { peer in
                            ZStack(alignment: .bottomLeading) {
                                if let remoteTrack = manager.remoteVideoTracks[peer.id], peer.video {
                                    WebRTCVideoRendererView(track: remoteTrack, mirror: false)
                                        .frame(height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(red: 0.14, green: 0.14, blue: 0.2))
                                        .frame(height: 180)
                                        .overlay(
                                            KinnectAvatarView(
                                                name: peer.name,
                                                avatarURL: peer.avatarUrl,
                                                colorHex: "#7C3AED",
                                                size: 56
                                            )
                                        )
                                }
                                Text(peer.muted ? String(format: L10n.tr("%@ (Tắt mic)"), peer.name) : peer.name)
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.6)))
                                    .padding(8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 22) {
                    Button {
                        manager.toggleCamera()
                    } label: {
                        Image(systemName: manager.isCameraOff ? "video.slash.fill" : "video.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(manager.isCameraOff ? Color.white.opacity(0.15) : Color.white.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(manager.isCameraOff ? L10n.tr("Bật camera") : L10n.tr("Tắt camera"))

                    Button {
                        manager.toggleMute()
                    } label: {
                        Image(systemName: manager.isMicMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(manager.isMicMuted ? Color.white.opacity(0.15) : Color.white.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(manager.isMicMuted ? L10n.tr("Bật mic") : L10n.tr("Tắt mic"))

                    Button {
                        manager.flipCamera()
                    } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.white.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Lật camera"))

                    Button {
                        manager.leave()
                        dismiss()
                    } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 58, height: 58)
                            .background(Circle().fill(KinnectTheme.danger))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Rời cuộc gọi nhóm"))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .padding(.bottom, 28)
            }
        }
        .task {
            await manager.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: SocketEventBridge.rawEventNotification)) { notif in
            if let json = notif.userInfo as? [String: Any] {
                manager.handleSocketEvent(json)
            }
        }
        .onChange(of: manager.shouldDismiss) { shouldClose in
            if shouldClose { dismiss() }
        }
        .onDisappear {
            manager.leave()
        }
    }
}

