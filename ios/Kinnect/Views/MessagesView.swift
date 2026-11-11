import PhotosUI
import SwiftUI
import UIKit

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
    @State private var isLoading = false
    @State private var searchQuery: String = ""

    init(initialScope: ChatScope = .direct, onOpenFriends: @escaping () -> Void = {}) {
        self.onOpenFriends = onOpenFriends
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(KinnectTheme.textSecondary)
                TextField("Tìm cuộc trò chuyện…", text: $searchQuery)
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

            HStack(spacing: 10) {
                Picker("Loại tin nhắn", selection: $scope) {
                    ForEach(ChatScope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                if scope == .groups {
                    KinnectIconButton(
                        glyph: .add,
                        label: "Tạo nhóm mới",
                        tint: KinnectTheme.accentBright
                    ) {
                        showCreateGroupSheet = true
                    }
                }
            }
            .padding(.horizontal, 14)

            // Android 1.2.12 MainActivity:2053 Parity Filter: [Tất cả | Chưa đọc]
            if scope == .direct {
                HStack(spacing: 8) {
                    Button {
                        unreadOnly = false
                    } label: {
                        Text("Tất cả")
                            .font(.caption.weight(!unreadOnly ? .bold : .medium))
                            .foregroundColor(!unreadOnly ? .white : KinnectTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(!unreadOnly ? KinnectTheme.accent : KinnectTheme.surfaceElevated))
                    }
                    .buttonStyle(.plain)

                    Button {
                        unreadOnly = true
                    } label: {
                        Text("Chưa đọc")
                            .font(.caption.weight(unreadOnly ? .bold : .medium))
                            .foregroundColor(unreadOnly ? .white : KinnectTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(unreadOnly ? KinnectTheme.accent : KinnectTheme.surfaceElevated))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if scope == .direct {
                        let rows = filteredConversations
                        if rows.isEmpty && !isLoading {
                            VStack(spacing: 12) {
                                Text(unreadOnly ? "Không có tin nhắn chưa đọc." : "Chưa có cuộc trò chuyện riêng nào")
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textSecondary)
                                if !unreadOnly {
                                    Button("Mở danh sách bạn bè", action: onOpenFriends)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.vertical, 36)
                        }

                        ForEach(rows, id: \.0) { _, conv, peer in
                            NavigationLink {
                                DirectChatDetailView(peer: peer)
                            } label: {
                                directConversationRow(conv: conv, peer: peer)
                            }
                        }
                    } else {
                        if groups.isEmpty && !isLoading {
                            VStack(spacing: 12) {
                                Text("Bạn chưa tham gia nhóm trò chuyện nào")
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Button("Tạo nhóm mới") {
                                    showCreateGroupSheet = true
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(KinnectTheme.primaryGradient))
                                .foregroundColor(.white)
                            }
                            .padding(.vertical, 36)
                        }

                        ForEach(groups) { group in
                            NavigationLink {
                                GroupChatDetailView(group: group) {
                                    Task { await loadChats() }
                                }
                            } label: {
                                groupConversationRow(group)
                            }
                        }
                    }
                }
                .padding(14)
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

        return HStack(spacing: 12) {
            KinnectAvatarView(
                name: peer.name,
                avatarURL: peer.avatarUrl,
                colorHex: peer.avatarColor,
                size: 48,
                isOnline: appState.onlineUserIds.contains(peer.id)
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(peer.name)
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if !rawTime.isEmpty {
                        Text(formatRelativeDate(rawTime))
                            .font(.caption2)
                            .foregroundColor(unread > 0 ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                    }
                }
                HStack {
                    Text(lastMsg)
                        .font(.caption)
                        .foregroundColor(unread > 0 ? KinnectTheme.textPrimary : KinnectTheme.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(KinnectTheme.accentBright))
                    }
                }
            }
        }
        .kinnectCard()
    }

    private func groupConversationRow(_ group: ChatGroupItem) -> some View {
        HStack(spacing: 12) {
            KinnectAvatarView(
                name: group.name,
                avatarURL: "",
                colorHex: group.avatarColor,
                size: 48
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineLimit(1)
                    Text("(\(group.membersCount) TV)")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Spacer()
                    if !group.updatedAt.isEmpty {
                        Text(formatRelativeDate(group.updatedAt))
                            .font(.caption2)
                            .foregroundColor(group.unreadCount > 0 ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                    }
                }
                HStack {
                    Text(group.lastMessageText.isEmpty ? group.description : group.lastMessageText)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    if group.unreadCount > 0 {
                        Text("\(group.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(KinnectTheme.accentBright))
                    }
                }
            }
        }
        .kinnectCard()
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

        if let cRes = try? await cTask {
            let list = (cRes["users"] as? [[String: Any]]) ?? (cRes["conversations"] as? [[String: Any]]) ?? []
            self.conversations = list
        }
        if let gRes = try? await gTask {
            self.groups = (gRes["groups"] as? [[String: Any]] ?? []).map(ChatGroupItem.from)
        }
        await appState.refreshGlobalBadges()
    }
}

struct DirectChatDetailView: View {
    let peer: KinnectUser
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var messages: [DirectMessageItem] = []
    @State private var text = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSending = false
    @State private var editingMessageId: String?
    @State private var editingMessageText: String = ""
    @State private var messageReactions: [String: String] = [:]
    @State private var forwardText: String = ""
    @State private var forwardImageUrl: String = ""
    @State private var showForwardSheet = false
    @State private var isPinned = false
    @State private var isMuted = false
    @State private var showReviewChatMenu = (UIReviewFixture.activeScreen == "chat-menu")
    @State private var showReviewMessageMenu = (UIReviewFixture.activeScreen == "message-menu")
    @State private var showPeerProfile = false

    var body: some View {
        VStack(spacing: 0) {
            // Conversational Header Bar (Back + Peer Avatar + Peer Name + Call/Video/More)
            HStack(spacing: 8) {
                KinnectIconButton(
                    glyph: .back,
                    label: "Quay lại",
                    tint: KinnectTheme.textPrimary
                ) {
                    dismiss()
                }

                Button {
                    showPeerProfile = true
                } label: {
                    HStack(spacing: 8) {
                        KinnectAvatarView(
                            name: peer.name,
                            avatarURL: peer.avatarUrl,
                            colorHex: peer.avatarColor,
                            size: 36,
                            isOnline: true
                        )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(peer.name)
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(1)
                            Text("Đang hoạt động")
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.online)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                // Call action buttons (iOS HIG native phone & video icons)
                Button {
                    Task { await NativeWebRTCManager.shared.startOutgoingCall(targetUser: peer, mode: "audio") }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(KinnectTheme.callGreen)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(KinnectTheme.callGreen.opacity(0.15)))
                }
                .accessibilityLabel("Gọi thoại")

                Button {
                    Task { await NativeWebRTCManager.shared.startOutgoingCall(targetUser: peer, mode: "video") }
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(KinnectTheme.accentBright.opacity(0.15)))
                }
                .accessibilityLabel("Gọi video")

                Menu {
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
                    Button(role: .destructive) {
                        appState.activeReportContext = UGCReportContext(
                            targetType: "user",
                            targetId: peer.id,
                            targetUserId: peer.id,
                            targetTitle: peer.name
                        )
                    } label: {
                        HStack {
                            Text("Báo cáo người dùng")
                            KinnectIcon(glyph: .report, size: 18, tint: KinnectTheme.danger)
                        }
                    }
                    Button(role: .destructive) {
                        Task { await appState.blockUser(userId: peer.id, userName: peer.name) }
                    } label: {
                        HStack {
                            Text("Chặn người dùng")
                            KinnectIcon(glyph: .block, size: 18, tint: KinnectTheme.danger)
                        }
                    }
                } label: {
                    KinnectIcon(glyph: .more, size: 22, tint: KinnectTheme.textSecondary)
                        .frame(minWidth: 40, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn cuộc trò chuyện")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(KinnectTheme.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(KinnectTheme.border).frame(height: 1)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            let isMine = (msg.fromUserId == appState.currentUser?.id)
                            directMessageBubble(msg: msg, isMine: isMine)
                                .id(msg.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            if let editId = editingMessageId {
                HStack(spacing: 8) {
                    KinnectIcon(glyph: .edit, size: 18, selected: true, tint: KinnectTheme.accentBright)
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

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    KinnectIcon(glyph: .photo, size: 24, tint: KinnectTheme.accentBright)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Chọn ảnh gửi tin nhắn")
                .onChange(of: selectedPhoto) { newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let uiImg = UIImage(data: data),
                           let jpeg = uiImg.jpegData(compressionQuality: 0.72) {
                            let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                            await sendMessage(text: text, imageDataURL: dataURL)
                        }
                    }
                }

                if editingMessageId != nil {
                    TextField(
                        "",
                        text: $editingMessageText,
                        prompt: Text("Nội dung tin nhắn mới...").foregroundColor(KinnectTheme.textSecondary)
                    )
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)
                } else {
                    TextField(
                        "",
                        text: $text,
                        prompt: Text("Nhắn tin...").foregroundColor(KinnectTheme.textSecondary)
                    )
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)

                    KinnectIconButton(
                        glyph: .send,
                        label: "Gửi tin nhắn",
                        tint: KinnectTheme.accentBright
                    ) {
                        Task { await sendMessage(text: text, imageDataURL: "") }
                    }
                    .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
            .background(KinnectTheme.surface)
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
        .confirmationDialog("Tùy chọn hội thoại", isPresented: $showReviewChatMenu, titleVisibility: .visible) {
            Button(isPinned ? "Bỏ ghim hội thoại" : "Ghim hội thoại") {}
            Button(isMuted ? "Bật thông báo" : "Tắt thông báo") {}
            Button("Báo cáo người dùng", role: .destructive) {}
            Button("Chặn người dùng", role: .destructive) {}
            Button("Hủy", role: .cancel) {}
        }
        .confirmationDialog("Tùy chọn tin nhắn", isPresented: $showReviewMessageMenu, titleVisibility: .visible) {
            Button("Sửa tin nhắn") {}
            Button("Chuyển tiếp tin nhắn") {}
            Button("Thu hồi / Xóa tin nhắn", role: .destructive) {}
            Button("Hủy", role: .cancel) {}
        }
        .task {
            await loadMessages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectMessagesChanged)) { _ in
            Task { await loadMessages() }
        }
    }

    private func directMessageBubble(msg: DirectMessageItem, isMine: Bool) -> some View {
        HStack {
            if isMine { Spacer(minLength: 44) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                // Message content on top
                if !msg.imageUrl.isEmpty {
                    KinnectRemoteImageView(rawURL: msg.imageUrl, cornerRadius: KinnectTheme.radiusMD, maxHeight: 220)
                }
                if !msg.text.isEmpty {
                    Text(msg.text)
                        .font(.subheadline)
                        .foregroundColor(isMine ? .white : KinnectTheme.textPrimary)
                        .kinnectMultiline()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: KinnectTheme.radiusXL, style: .continuous)
                                .fill(isMine ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                        )
                }

                // Bottom row: time, seen, reaction, and more (...) in a single row
                HStack(spacing: 8) {
                    Text(formatRelativeDate(msg.createdAt))
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#9CA3AF"))

                    if isMine {
                        HStack(spacing: 4) {
                            KinnectIcon(
                                glyph: .seen,
                                size: 16,
                                selected: msg.isSeen,
                                tint: msg.isSeen ? KinnectTheme.accentBright : Color(hex: "#9CA3AF")
                            )
                            Text(msg.isSeen ? "Đã xem" : (msg.deliveredAt.isEmpty ? "Đã gửi" : "Đã nhận"))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(msg.isSeen ? KinnectTheme.accentBright : Color(hex: "#9CA3AF"))
                        }
                    }

                    Menu {
                        ForEach(["👍", "❤️", "😂", "😮", "😢", "😡"], id: \.self) { emoji in
                            Button(emoji) {
                                Task { await reactToMessage(msgId: msg.id, emoji: emoji) }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            KinnectIcon(
                                glyph: .reaction,
                                size: 16,
                                selected: messageReactions[msg.id] != nil,
                                tint: messageReactions[msg.id] != nil ? KinnectTheme.accentBright : KinnectTheme.textSecondary
                            )
                            if let reacted = messageReactions[msg.id] {
                                Text(DirectMessageItem.emoji(for: reacted)).font(.caption2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityLabel("Thả cảm xúc tin nhắn")

                    Menu {
                        if isMine {
                            Button {
                                editingMessageId = msg.id
                                editingMessageText = msg.text
                            } label: {
                                HStack {
                                    Text("Sửa tin nhắn")
                                    KinnectIcon(glyph: .edit, size: 18)
                                }
                            }
                        }

                        Button {
                            forwardText = msg.text
                            forwardImageUrl = msg.imageUrl
                            showForwardSheet = true
                        } label: {
                            HStack {
                                Text("Chuyển tiếp tin nhắn")
                                KinnectIcon(glyph: .share, size: 18)
                            }
                        }

                        if isMine {
                            Button(role: .destructive) {
                                Task { await deleteMessage(msg) }
                            } label: {
                                Label("Thu hồi / Xóa tin nhắn", systemImage: "trash")
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
                                HStack {
                                    Text("Báo cáo tin nhắn")
                                    KinnectIcon(glyph: .report, size: 18, tint: KinnectTheme.danger)
                                }
                            }

                            Button(role: .destructive) {
                                Task { await appState.blockUser(userId: peer.id, userName: peer.name) }
                            } label: {
                                HStack {
                                    Text("Chặn người dùng")
                                    KinnectIcon(glyph: .block, size: 18, tint: KinnectTheme.danger)
                                }
                            }
                        }
                    } label: {
                        KinnectIcon(glyph: .more, size: 18, tint: KinnectTheme.textSecondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Tùy chọn tin nhắn")
                }
            }
            if !isMine { Spacer(minLength: 44) }
        }
    }

    private func loadMessages() async {
        if messages.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/users/\(peer.id)/messages"),
           let list = cached["messages"] as? [[String: Any]] {
            self.messages = list.map(DirectMessageItem.from)
            for m in self.messages where !m.reaction.isEmpty {
                messageReactions[m.id] = m.reaction
            }
        }
        // Fetching GET /api/users/:id/messages marks incoming messages as seen on backend
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(peer.id)/messages") {
            let list = res["messages"] as? [[String: Any]] ?? []
            self.messages = list.map(DirectMessageItem.from)
            for m in self.messages where !m.reaction.isEmpty {
                messageReactions[m.id] = m.reaction
            }
            await appState.refreshGlobalBadges()
        }
    }

    private func reactToMessage(msgId: String, emoji: String) async {
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
                let myRx = (msgObj["myReaction"] as? String) ?? ""
                if !myRx.isEmpty {
                    messageReactions[msgId] = myRx
                } else {
                    messageReactions.removeValue(forKey: msgId)
                }
            }
            NativeSocketClient.shared.sendJSON([
                "type": "chat-reaction",
                "messageId": msgId,
                "reaction": newKey ?? ""
            ])
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

    private func sendMessage(text: String, imageDataURL: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || !imageDataURL.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        self.text = ""
        let reqId = "dm_\(peer.id)_\(UUID().uuidString)"
        let tempId = "opt_\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())
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
        self.messages.append(optimistic)

        var payload: [String: Any] = [
            "body": clean,
            "text": clean,
            "imageUrl": imageDataURL,
            "requestId": reqId
        ]
        if !imageDataURL.isEmpty {
            payload["attachment"] = ["data": imageDataURL, "name": "photo.jpg"]
        }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            await loadMessages()
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: nil)
        } catch {
            self.messages.removeAll { $0.id == tempId }
            self.text = text
            appState.showToast(error.localizedDescription)
        }
    }

    private func deleteMessage(_ msg: DirectMessageItem) async {
        let reqId = "del_dm_\(msg.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/messages/\(msg.id)",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            await loadMessages()
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

    @State private var messages: [GroupMessageItem] = []
    @State private var groupMembers: [KinnectUser] = []
    @State private var text = ""
    @State private var groupReactions: [String: String] = [:]
    @State private var forwardText = ""
    @State private var forwardImageUrl = ""
    @State private var showForwardSheet = false
    @State private var showRenameSheet = false
    @State private var showAddMemberSheet = false
    @State private var newGroupName = ""

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
        return pool.filter {
            $0.name.lowercased().contains(query) ||
            $0.username.lowercased().contains(query)
        }
    }

    private func insertMention(tag: String) {
        guard let lastAt = text.lastIndex(of: "@") else { return }
        let prefix = text[..<lastAt]
        text = "\(prefix)@\(tag) "
    }

    private func formattedBubbleText(_ rawText: String, isMine: Bool) -> Text {
        let words = rawText.components(separatedBy: " ")
        var result = Text("")
        for (idx, word) in words.enumerated() {
            let space = (idx == 0) ? Text("") : Text(" ")
            if word.hasPrefix("@") {
                let styled = Text(word)
                    .font(.subheadline)
                    .bold()
                    .foregroundColor(isMine ? Color.white : KinnectTheme.accentBright)
                    .underline()
                result = result + space + styled
            } else {
                let normal = Text(word)
                    .font(.subheadline)
                    .foregroundColor(isMine ? Color.white : KinnectTheme.textPrimary)
                result = result + space + normal
            }
        }
        return result
    }

    @ViewBuilder
    private func groupMessageRow(msg: GroupMessageItem) -> some View {
        let isMine = (msg.sender.id == appState.currentUser?.id)
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 40) }
            if !isMine {
                KinnectAvatarView(
                    name: msg.sender.name,
                    avatarURL: msg.sender.avatarUrl,
                    colorHex: msg.sender.avatarColor,
                    size: 30
                )
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                if !isMine {
                    Text(msg.sender.name)
                        .font(.caption2.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                }
                // Content on top with Zalo-style member mention highlight
                formattedBubbleText(msg.text, isMine: isMine)
                    .kinnectMultiline()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: KinnectTheme.radiusXL)
                            .fill(isMine ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                    )
                // Bottom row: time, seen, reaction, more
                groupMessageFooter(msg: msg, isMine: isMine)
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func groupMessageFooter(msg: GroupMessageItem, isMine: Bool) -> some View {
        HStack(spacing: 8) {
            Text(formatRelativeDate(msg.createdAt))
                .font(.caption2)
                .foregroundColor(Color(hex: "#9CA3AF"))

            HStack(spacing: 4) {
                KinnectIcon(glyph: .seen, size: 16, selected: true, tint: KinnectTheme.accentBright)
                Text("\(max(msg.seenCount, 1))")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(KinnectTheme.accentBright)
            }

            Menu {
                ForEach(["👍", "❤️", "😂", "😮", "😢", "😡"], id: \.self) { emoji in
                    Button(emoji) {
                        Task { await reactToGroupMessage(msgId: msg.id, emoji: emoji) }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    KinnectIcon(
                        glyph: .reaction,
                        size: 16,
                        selected: groupReactions[msg.id] != nil,
                        tint: groupReactions[msg.id] != nil ? KinnectTheme.accentBright : KinnectTheme.textSecondary
                    )
                    if let reacted = groupReactions[msg.id] {
                        Text(DirectMessageItem.emoji(for: reacted)).font(.caption2)
                    }
                }
            }
            .accessibilityLabel("Thả cảm xúc tin nhắn nhóm")

            Menu {
                Button {
                    forwardText = msg.text
                    forwardImageUrl = msg.imageUrl
                    showForwardSheet = true
                } label: {
                    HStack {
                        Text("Chuyển tiếp tin nhắn")
                        KinnectIcon(glyph: .share, size: 18)
                    }
                }

                if !isMine {
                    Button(role: .destructive) {
                        appState.activeReportContext = UGCReportContext(
                            targetType: "group_message",
                            targetId: msg.id,
                            targetUserId: msg.sender.id,
                            targetTitle: "Tin nhắn nhóm của \(msg.sender.name)"
                        )
                    } label: {
                        HStack {
                            Text("Báo cáo tin nhắn")
                            KinnectIcon(glyph: .report, size: 18, tint: KinnectTheme.danger)
                        }
                    }
                    Button(role: .destructive) {
                        Task { await appState.blockUser(userId: msg.sender.id, userName: msg.sender.name) }
                    } label: {
                        HStack {
                            Text("Chặn người gửi")
                            KinnectIcon(glyph: .block, size: 18, tint: KinnectTheme.danger)
                        }
                    }
                }
            } label: {
                KinnectIcon(glyph: .more, size: 18, tint: KinnectTheme.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tùy chọn tin nhắn nhóm")
        }
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
                        // @Tất cả (Zalo Tag All)
                        Button {
                            insertMention(tag: "Tất cả")
                        } label: {
                            HStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(KinnectTheme.accentBright.opacity(0.2))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "person.3.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(KinnectTheme.accentBright)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("@Tất cả")
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.accentBright)
                                    Text("Cả nhóm")
                                        .font(.system(size: 9))
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
                        }
                        .buttonStyle(.plain)

                        // Group members
                        ForEach(filteredMentionMembers) { u in
                            Button {
                                let tag = u.username.isEmpty ? u.name : u.username
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
                                        Text("@\(u.username.isEmpty ? u.name : u.username)")
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
        HStack(spacing: 8) {
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
                    .foregroundColor(KinnectTheme.accentBright)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
            }
            .accessibilityLabel("Nhắc tên thành viên")

            TextField("Nhập tin nhắn trong nhóm...", text: $text)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                .foregroundColor(KinnectTheme.textPrimary)

            KinnectIconButton(
                glyph: .send,
                label: "Gửi tin nhắn nhóm",
                tint: KinnectTheme.accentBright
            ) {
                Task { await sendGroupMessage() }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(KinnectTheme.surface)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { msg in
                        groupMessageRow(msg: msg)
                    }
                }
                .padding(14)
            }

            mentionSuggestionBar

            groupChatInputBar
        }
        .background(KinnectTheme.background)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                }
                .accessibilityLabel("Quay lại")
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        newGroupName = group.name
                        showRenameSheet = true
                    } label: {
                        Label("Đổi tên nhóm", systemImage: "pencil")
                    }
                    Button {
                        showAddMemberSheet = true
                    } label: {
                        Label("Thêm thành viên", systemImage: "person.badge.plus")
                    }
                    Button(role: .destructive) {
                        Task { await leaveGroup() }
                    } label: {
                        HStack {
                            Text("Rời nhóm")
                            KinnectIcon(glyph: .logout, size: 18, tint: KinnectTheme.danger)
                        }
                    }
                } label: {
                    KinnectIcon(glyph: .more, size: 22, tint: KinnectTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn nhóm")
            }
        }
        .sheet(isPresented: $showForwardSheet) {
            ForwardMessageSheet(text: forwardText, imageUrl: forwardImageUrl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showForwardSheet)
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameGroupSheet(groupId: group.id, currentName: group.name) {
                Task { await loadGroupMessages() }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showRenameSheet)
        }
        .sheet(isPresented: $showAddMemberSheet) {
            AddGroupMembersSheet(groupId: group.id) {
                Task { await loadGroupMessages() }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showAddMemberSheet)
        }
        .task {
            if groupMembers.isEmpty {
                groupMembers = group.members
            }
            await loadGroupMessages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectMessagesChanged)) { _ in
            Task { await loadGroupMessages() }
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
            for m in self.messages where !m.reaction.isEmpty {
                groupReactions[m.id] = m.reaction
            }
            syncGroupMembersFromMessages()
        }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/groups/\(group.id)/messages") {
            let list = res["messages"] as? [[String: Any]] ?? []
            self.messages = list.map(GroupMessageItem.from)
            for m in self.messages where !m.reaction.isEmpty {
                groupReactions[m.id] = m.reaction
            }
            syncGroupMembersFromMessages()
        }
    }

    private func reactToGroupMessage(msgId: String, emoji: String) async {
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
                let myRx = (msgObj["myReaction"] as? String) ?? ""
                if !myRx.isEmpty {
                    groupReactions[msgId] = myRx
                } else {
                    groupReactions.removeValue(forKey: msgId)
                }
            }
            NativeSocketClient.shared.sendJSON([
                "type": "group-reaction",
                "messageId": msgId,
                "reaction": newKey ?? ""
            ])
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

    private func sendGroupMessage() async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let draft = text
        text = ""
        let reqId = "grp_msg_\(group.id)_\(UUID().uuidString)"

        var payload: [String: Any] = ["body": clean]
        let currentUserId = appState.currentUser?.id
        let mentionedIds = groupMembers.filter { m in
            m.id != currentUserId &&
            (clean.contains("@\(m.username)") || (!m.name.isEmpty && clean.contains("@\(m.name)")))
        }.map(\.id)
        if !mentionedIds.isEmpty {
            payload["mentions"] = mentionedIds
        }

        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(group.id)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            await loadGroupMessages()
        } catch {
            text = draft
            appState.showToast(error.localizedDescription)
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
                    self.friends = (res["friends"] as? [[String: Any]] ?? []).map(KinnectUser.from)
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
                                    KinnectAvatarView(name: g.name, avatarURL: "", colorHex: g.avatarColor, size: 36)
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
        if UIReviewFixture.activeScreen != nil {
            self.conversations = [
                [
                    "peer": [
                        "id": "fixture_user_fwd_1",
                        "name": "Hoàng Nam",
                        "handle": "hoang_nam",
                        "avatarColor": "#7C3AED"
                    ]
                ],
                [
                    "peer": [
                        "id": "fixture_user_fwd_2",
                        "name": "Thanh Trúc",
                        "handle": "thanh_truc",
                        "avatarColor": "#EC4899"
                    ]
                ]
            ]
            self.groups = [
                ChatGroupItem.from([
                    "id": "group-fixture-01",
                    "name": "Gia đình Kinnect",
                    "description": "Nhóm trò chuyện chia sẻ",
                    "avatarColor": "#8A3FFC",
                    "membersCount": 5,
                    "lastMessageText": "Hẹn gặp mọi người tối nay nhé!",
                    "unreadCount": 0
                ])
            ]
            self.friends = [
                KinnectUser.from([
                    "id": "fixture_user_fwd_3",
                    "name": "Võ Minh Khang",
                    "handle": "minh_khang",
                    "avatarColor": "#3B82F6"
                ])
            ]
            return
        }
        isLoading = true
        defer { isLoading = false }
        if let cRes = try? await KinnectAPIClient.shared.requestJSON("/api/conversations") {
            self.conversations = cRes["conversations"] as? [[String: Any]] ?? []
        }
        if let gRes = try? await KinnectAPIClient.shared.requestJSON("/api/groups") {
            self.groups = (gRes["groups"] as? [[String: Any]] ?? []).map(ChatGroupItem.from)
        }
        if let fRes = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
            self.friends = (fRes["friends"] as? [[String: Any]] ?? []).map(KinnectUser.from)
        }
    }

    private func forwardToUser(_ userId: String, name: String) async {
        let reqId = "fwd_u_\(userId)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(userId)/messages",
                method: "POST",
                body: [
                    "body": text,
                    "text": text,
                    "imageUrl": imageUrl,
                    "requestId": reqId
                ],
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
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/messages",
                method: "POST",
                body: [
                    "body": text,
                    "text": text,
                    "imageUrl": imageUrl,
                    "requestId": reqId
                ],
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
    let onRenamed: () -> Void
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
            onRenamed()
            dismiss()
        } catch {
            appState.showToast("Lỗi đổi tên: \(error.localizedDescription)")
        }
    }
}

struct AddGroupMembersSheet: View {
    let groupId: String
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
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
                    self.friends = (res["friends"] as? [[String: Any]] ?? []).map(KinnectUser.from)
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

