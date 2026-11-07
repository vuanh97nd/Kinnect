import PhotosUI
import SwiftUI
import UIKit

struct MessagesView: View {
    let onOpenFriends: () -> Void
    @ObservedObject private var appState = AppState.shared

    enum ChatScope: String, CaseIterable {
        case direct = "Tin nhắn riêng"
        case groups = "Nhóm chat"
    }

    @State private var scope: ChatScope = .direct
    @State private var conversations: [[String: Any]] = []
    @State private var groups: [ChatGroupItem] = []
    @State private var showCreateGroupSheet = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 10) {
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
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if scope == .direct {
                        if conversations.isEmpty && !isLoading {
                            VStack(spacing: 12) {
                                Text("Chưa có cuộc trò chuyện riêng nào")
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Button("Mở danh sách bạn bè", action: onOpenFriends)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 36)
                        }

                        ForEach(Array(conversations.enumerated()), id: \.offset) { _, conv in
                            let peer = extractPeer(from: conv)
                            if !peer.id.isEmpty && !appState.blockedUserIds.contains(peer.id) {
                                NavigationLink {
                                    DirectChatDetailView(peer: peer)
                                } label: {
                                    directConversationRow(conv: conv, peer: peer)
                                }
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
        .navigationTitle("Tin nhắn")
        .navigationBarTitleDisplayMode(.inline)
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
        }
    }

    private func extractPeer(from conv: [String: Any]) -> KinnectUser {
        if let u = conv["user"] as? [String: Any] ?? conv["peer"] as? [String: Any] {
            return KinnectUser.from(u)
        }
        return KinnectUser.from(conv)
    }

    private func directConversationRow(conv: [String: Any], peer: KinnectUser) -> some View {
        let lastMsg = (conv["lastMessage"] as? [String: Any])?["text"] as? String
            ?? (conv["preview"] as? String)
            ?? "Nhấn để trò chuyện"
        let unread = conv["unreadCount"] as? Int ?? 0

        return HStack(spacing: 12) {
            KinnectAvatarView(
                name: peer.name,
                avatarURL: peer.avatarUrl,
                colorHex: peer.avatarColor,
                size: 48,
                isOnline: appState.onlineUserIds.contains(peer.id)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(peer.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .kinnectMultiline()
                Text(lastMsg)
                    .font(.caption)
                    .foregroundColor(unread > 0 ? .white : KinnectTheme.textSecondary)
                    .lineLimit(2)
            }

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
                        .foregroundColor(.white)
                        .kinnectMultiline()
                    Text("(\(group.membersCount) TV)")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                Text(group.lastMessageText.isEmpty ? group.description : group.lastMessageText)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .lineLimit(2)
            }
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
        .kinnectCard()
    }

    private func loadChats() async {
        isLoading = true
        defer { isLoading = false }
        async let cTask = KinnectAPIClient.shared.requestJSON("/api/conversations")
        async let gTask = KinnectAPIClient.shared.requestJSON("/api/groups")

        if let cRes = try? await cTask {
            self.conversations = cRes["conversations"] as? [[String: Any]] ?? []
        }
        if let gRes = try? await gTask {
            self.groups = (gRes["groups"] as? [[String: Any]] ?? []).map(ChatGroupItem.from)
        }
        await appState.refreshGlobalBadges()
    }
}

struct DirectChatDetailView: View {
    let peer: KinnectUser
    @ObservedObject private var appState = AppState.shared

    @State private var messages: [DirectMessageItem] = []
    @State private var text = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSending = false
    @State private var editingMessageId: String?
    @State private var editingMessageText: String = ""
    @State private var messageReactions: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
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
                    TextField("Nội dung tin nhắn mới...", text: $editingMessageText)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(.white)
                } else {
                    TextField("Nhắn tin cho \(peer.name)...", text: $text)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(.white)

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
        .navigationTitle(peer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                KinnectIconButton(
                    glyph: .phone,
                    label: "Gọi thoại",
                    tint: KinnectTheme.online
                ) {
                    Task { await NativeWebRTCManager.shared.startOutgoingCall(targetUser: peer, mode: "audio") }
                }

                KinnectIconButton(
                    glyph: .videoCall,
                    label: "Gọi video",
                    tint: KinnectTheme.accentBright
                ) {
                    Task { await NativeWebRTCManager.shared.startOutgoingCall(targetUser: peer, mode: "video") }
                }

                Menu {
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
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn cuộc trò chuyện")
            }
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
                    KinnectRemoteImageView(rawURL: msg.imageUrl, cornerRadius: 12, maxHeight: 220)
                }
                if !msg.text.isEmpty {
                    Text(msg.text)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .kinnectMultiline()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isMine ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                        )
                }

                // Bottom row: time, seen, reaction, and more (...) in a single row
                HStack(spacing: 8) {
                    Text(formatRelativeDate(msg.createdAt))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)

                    if isMine {
                        HStack(spacing: 4) {
                            KinnectIcon(
                                glyph: .seen,
                                size: 16,
                                selected: msg.isSeen,
                                tint: msg.isSeen ? KinnectTheme.accentBright : KinnectTheme.textSecondary
                            )
                            Text(msg.isSeen ? "Đã xem" : (msg.deliveredAt.isEmpty ? "Đã gửi" : "Đã nhận"))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(msg.isSeen ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        }
                    }

                    Menu {
                        ForEach(["❤️", "👍", "😆", "😮", "😢"], id: \.self) { emoji in
                            Button(emoji) {
                                messageReactions[msg.id] = emoji
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
                                Text(reacted).font(.caption2)
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
                            UIPasteboard.general.string = msg.text
                            appState.showToast("Đã sao chép để chuyển tiếp tin nhắn.")
                        } label: {
                            HStack {
                                Text("Chuyển tiếp / Sao chép")
                                KinnectIcon(glyph: .share, size: 18)
                            }
                        }

                        if isMine {
                            Button(role: .destructive) {
                                Task { await recallMessage(msg) }
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
        // Fetching GET /api/users/:id/messages marks incoming messages as seen on backend
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(peer.id)/messages") {
            let list = res["messages"] as? [[String: Any]] ?? []
            self.messages = list.map(DirectMessageItem.from)
            await appState.refreshGlobalBadges()
        }
    }

    private func sendMessage(text: String, imageDataURL: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || !imageDataURL.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        self.text = ""
        let reqId = "dm_\(peer.id)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peer.id)/messages",
                method: "POST",
                body: [
                    "text": clean,
                    "imageUrl": imageDataURL,
                    "requestId": reqId
                ],
                requestId: reqId
            )
            await loadMessages()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func recallMessage(_ msg: DirectMessageItem) async {
        let reqId = "del_dm_\(msg.id)"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/users/\(peer.id)/messages/\(msg.id)",
            method: "DELETE",
            body: [:],
            requestId: reqId
        )
        await loadMessages()
    }

    private func saveEditedMessage(messageId: String) async {
        let clean = editingMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        editingMessageId = nil
        editingMessageText = ""
        let reqId = "edit_dm_\(messageId)_\(Int(Date().timeIntervalSince1970))"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/users/\(peer.id)/messages/\(messageId)",
            method: "PATCH",
            body: ["text": clean],
            requestId: reqId
        )
        await loadMessages()
    }
}

struct GroupChatDetailView: View {
    let group: ChatGroupItem
    let onLeftGroup: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var messages: [GroupMessageItem] = []
    @State private var text = ""
    @State private var groupReactions: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { msg in
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
                                // Content on top
                                Text(msg.text)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .kinnectMultiline()
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(isMine ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                                    )
                                // Bottom row: time, seen, reaction, more
                                HStack(spacing: 8) {
                                    Text(formatRelativeDate(msg.createdAt))
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.textSecondary)

                                    HStack(spacing: 4) {
                                        KinnectIcon(glyph: .seen, size: 16, selected: true, tint: KinnectTheme.accentBright)
                                        Text("\(max(msg.seenCount, 1))")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(KinnectTheme.accentBright)
                                    }

                                    Menu {
                                        ForEach(["❤️", "👍", "😆", "😮", "😢"], id: \.self) { emoji in
                                            Button(emoji) {
                                                groupReactions[msg.id] = emoji
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
                                                Text(reacted).font(.caption2)
                                            }
                                        }
                                    }
                                    .accessibilityLabel("Thả cảm xúc tin nhắn nhóm")

                                    Menu {
                                        Button {
                                            UIPasteboard.general.string = msg.text
                                            appState.showToast("Đã sao chép để chuyển tiếp tin nhắn.")
                                        } label: {
                                            HStack {
                                                Text("Chuyển tiếp / Sao chép")
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
                            if !isMine { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding(14)
            }

            HStack(spacing: 10) {
                TextField("Nhắn vào nhóm \(group.name)...", text: $text)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(.white)

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
        .background(KinnectTheme.background)
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                KinnectIconButton(
                    glyph: .logout,
                    label: "Rời nhóm",
                    tint: KinnectTheme.danger
                ) {
                    Task { await leaveGroup() }
                }
            }
        }
        .task {
            await loadGroupMessages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectMessagesChanged)) { _ in
            Task { await loadGroupMessages() }
        }
    }

    private func loadGroupMessages() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/groups/\(group.id)/messages") {
            let list = res["messages"] as? [[String: Any]] ?? []
            self.messages = list.map(GroupMessageItem.from)
        }
    }

    private func sendGroupMessage() async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        text = ""
        let reqId = "grp_msg_\(group.id)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(group.id)/messages",
                method: "POST",
                body: ["text": clean],
                requestId: reqId
            )
            await loadGroupMessages()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func leaveGroup() async {
        let reqId = "leave_grp_\(group.id)"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/groups/\(group.id)/leave",
            method: "POST",
            body: [:],
            requestId: reqId
        )
        onLeftGroup()
        dismiss()
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
                                    .foregroundColor(.white)
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

