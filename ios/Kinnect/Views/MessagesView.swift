import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @State private var showNewDirectChatSheet = false
    @State private var activeChatPeer: KinnectUser? = nil
    @State private var isLoading = false
    @State private var searchQuery: String = ""

    init(initialScope: ChatScope = .direct, onOpenFriends: @escaping () -> Void = {}) {
        self.onOpenFriends = onOpenFriends
        _scope = State(initialValue: initialScope)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Header Bar (matching Android accountHeader pattern)
            PinnedHeaderBar(
                title: "Tin nhắn",
                onBack: nil,
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
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                TextField("Tìm cuộc trò chuyện…", text: $searchQuery)
                    .font(.system(size: 15))
                    .foregroundColor(KinnectTheme.textPrimary)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(UIColor.tertiaryLabel))
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
                        if rows.isEmpty && !isLoading {
                            emptyDirectView
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
                        if groups.isEmpty && !isLoading {
                            emptyGroupsView
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
        VStack(spacing: 12) {
            Image(systemName: unreadOnly ? "tray" : "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundColor(Color(UIColor.tertiaryLabel))
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
                .foregroundColor(Color(UIColor.tertiaryLabel))
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
                            .foregroundColor(unread > 0 ? KinnectTheme.accentBright : Color(UIColor.tertiaryLabel))
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
                            .font(.system(size: 13))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }

                    Spacer(minLength: 8)

                    if !group.updatedAt.isEmpty {
                        Text(formatRelativeDate(group.updatedAt))
                            .font(.system(size: 13, weight: group.unreadCount > 0 ? .semibold : .regular))
                            .foregroundColor(group.unreadCount > 0 ? KinnectTheme.accentBright : Color(UIColor.tertiaryLabel))
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

    private var fileIconName: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.richtext.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "zip", "rar", "tar", "gz": return "archivebox.fill"
        case "mp3", "m4a", "wav", "aac": return "music.note"
        case "mp4", "mov", "avi": return "video.fill"
        default: return "doc.fill"
        }
    }

    private var fileIconColor: Color {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
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
                    Text("Tệp đính kèm • Chạm để mở")
                        .font(.caption2)
                        .foregroundColor(isMine ? Color.white.opacity(0.8) : KinnectTheme.textSecondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(isMine ? Color.white.opacity(0.9) : KinnectTheme.accentBright)
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
    }

    private func openOrDownloadFile() {
        guard !fileUrl.isEmpty else { return }
        if fileUrl.hasPrefix("data:") {
            if let commaIndex = fileUrl.firstIndex(of: ",") {
                let base64 = String(fileUrl[fileUrl.index(after: commaIndex)...])
                if let data = Data(base64Encoded: base64) {
                    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName.isEmpty ? "attachment.dat" : fileName)
                    try? data.write(to: temp)
                    presentShareSheet(for: temp)
                    return
                }
            }
        }
        let fullURLStr = fileUrl.hasPrefix("http") ? fileUrl : "\(KinnectAPIClient.shared.baseURL)\(fileUrl)"
        if let targetURL = URL(string: fullURLStr) {
            UIApplication.shared.open(targetURL)
        }
    }

    private func presentShareSheet(for fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
}

struct DirectChatDetailView: View {
    let peer: KinnectUser
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var messages: [DirectMessageItem] = []
    @State private var text = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var isSending = false
    @State private var editingMessageId: String?
    @State private var editingMessageText: String = ""
    @State private var messageReactions: [String: String] = [:]
    @State private var groupReactions: [String: String] = [:]
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
    @State private var showReviewChatMenu = (UIReviewFixture.activeScreen == "chat-menu")
    @State private var showReviewMessageMenu = (UIReviewFixture.activeScreen == "message-menu")
    @State private var showPeerProfile = false

    var body: some View {
        VStack(spacing: 0) {
            // Conversational Header Bar (iOS Native Style)
            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")

                Button {
                    showPeerProfile = true
                } label: {
                    HStack(spacing: 10) {
                        KinnectAvatarView(
                            name: peer.name,
                            avatarURL: peer.avatarUrl,
                            colorHex: peer.avatarColor,
                            size: 38,
                            isOnline: appState.onlineUserIds.contains(peer.id) || (peer.isActive && peer.showActivity)
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(
                                        (appState.onlineUserIds.contains(peer.id) || (peer.isActive && peer.showActivity))
                                            ? Color(hex: "#2E9E66")
                                            : Color(UIColor.tertiaryLabel)
                                    )
                                    .frame(width: 7, height: 7)

                                Text(
                                    (appState.onlineUserIds.contains(peer.id) || (peer.isActive && peer.showActivity))
                                        ? "Đang trực tuyến"
                                        : "Ngoại tuyến"
                                )
                                .font(.system(size: 12))
                                .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                // Call action buttons (iOS HIG native phone & video contour icons)
                HStack(spacing: 8) {
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
                    }
                    .buttonStyle(.plain)
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
                            Label("Báo cáo người dùng", systemImage: "exclamationmark.bubble")
                        }
                        Button(role: .destructive) {
                            Task { await appState.blockUser(userId: peer.id, userName: peer.name) }
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
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Thư viện ảnh", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Tệp & Tài liệu", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .frame(width: 34, height: 38)
                }
                .accessibilityLabel("Đính kèm tệp hoặc ảnh")

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                        .foregroundColor(KinnectTheme.textSecondary)
                        .frame(width: 32, height: 38)
                }
                .accessibilityLabel("Chọn ảnh nhanh")
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
                    .font(.system(size: 16))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(KinnectTheme.surfaceElevated)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(KinnectTheme.borderSoft, lineWidth: 0.8))
                    )
                    .foregroundColor(KinnectTheme.textPrimary)
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
                            }
                            .disabled(isSending)
                            .padding(.trailing, 4)
                            .padding(.bottom, 3)
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

                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            appState.showToast("Ghi âm tin nhắn thoại (Đang hoàn thiện)")
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18))
                                .foregroundColor(KinnectTheme.textSecondary)
                                .frame(width: 32, height: 38)
                        }
                        .buttonStyle(.plain)
                    }
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
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let fileURL):
                guard fileURL.startAccessingSecurityScopedResource() else { return }
                defer { fileURL.stopAccessingSecurityScopedResource() }
                let fileName = fileURL.lastPathComponent
                if let data = try? Data(contentsOf: fileURL) {
                    let base64 = data.base64EncodedString()
                    let mime = mimeTypeForExt(fileURL.pathExtension)
                    let dataURL = "data:\(mime);base64,\(base64)"
                    Task {
                        await sendFileMessage(name: fileName, dataURL: dataURL)
                    }
                }
            case .failure(let err):
                appState.showToast("Không thể chọn tệp: \(err.localizedDescription)")
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
        HStack(alignment: .bottom, spacing: 6) {
            if isMine { Spacer(minLength: 44) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                ZStack(alignment: isMine ? .topLeading : .topTrailing) {
                    VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                        // Image preview if present
                        if !msg.imageUrl.isEmpty {
                            KinnectRemoteImageView(rawURL: msg.imageUrl, cornerRadius: 16, maxHeight: 240)
                                .clipShape(MessageBubbleShape(isMine: isMine))
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

                    // Floating Tapback reaction badge
                    if let reacted = messageReactions[msg.id] {
                        FloatingReactionBadge(reaction: reacted, isMine: isMine)
                    }
                }

                // Reaction Summary (Android parity) - shows reaction counts on message
                if !msg.reactions.isEmpty {
                    ReactionSummary(reactions: msg.reactions, myReaction: messageReactions[msg.id])
                        .padding(.horizontal, isMine ? 0 : 4)
                        .padding(.top, -2)
                }

                // Bottom row: time, delivery state, reaction trigger & more options
                HStack(spacing: 6) {
                    Text(formatRelativeDate(msg.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(Color(UIColor.tertiaryLabel))

                    if isMine {
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
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        } else {
                            Text("· Đã gửi")
                                .font(.system(size: 11))
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                    }

                    // Reaction Picker Button - Long press to show picker, tap to quick react
                    Button {
                        // Quick react with default (love) on tap
                        Task { await reactToMessage(msgId: msg.id, emoji: "❤️") }
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 12))
                            .foregroundColor(messageReactions[msg.id] != nil ? KinnectTheme.accentBright : Color(UIColor.tertiaryLabel))
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
                        if isMine {
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

                        if isMine {
                            Button(role: .destructive) {
                                Task { await deleteMessage(msg) }
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
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tùy chọn tin nhắn")
                }
                .padding(.horizontal, 4)
            }

            if !isMine { Spacer(minLength: 44) }
        }
        // Reaction Picker Overlay (Android-style popup)
        .overlay(
            Group {
                if showingReactionPicker && reactionPickerMessageId == msg.id && reactionPickerIsDirect {
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

    private func sendFileMessage(name: String, dataURL: String) async {
        let isImg = dataURL.hasPrefix("data:image/") || name.hasSuffix(".jpg") || name.hasSuffix(".png") || name.hasSuffix(".webp")
        let reqId = "dm_att_\(peer.id)_\(UUID().uuidString)"
        let tempId = "opt_\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())
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
        self.messages.append(optimistic)

        let payload: [String: Any] = [
            "body": "",
            "text": "",
            "attachment": ["name": name, "data": dataURL],
            "requestId": reqId
        ]
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
            appState.showToast("Không gửi được tệp: \(error.localizedDescription)")
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
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var showFileImporter = false
    @State private var isSending = false
    @State private var forwardText = ""
    @State private var forwardImageUrl = ""
    @State private var showForwardSheet = false
    @State private var showRenameSheet = false
    @State private var showAddMemberSheet = false
    @State private var showMembersSheet = false
    @State private var newGroupName = ""
    // Reaction state (Android parity)
    @State private var groupReactions: [String: String] = [:]
    @State private var showingReactionPicker = false
    @State private var reactionPickerMessageId: String = ""
    @State private var reactionPickerIsDirect = false
    @State private var reactionPickerFrame: CGRect = .zero

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
                    Text(msg.sender.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                        .padding(.leading, 4)
                }

                ZStack(alignment: isMine ? .topLeading : .topTrailing) {
                    VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                        // Image preview if present
                        if !msg.imageUrl.isEmpty {
                            KinnectRemoteImageView(rawURL: msg.imageUrl, cornerRadius: 16, maxHeight: 240)
                                .clipShape(MessageBubbleShape(isMine: isMine))
                        }
                        // File attachment card if present
                        if !msg.attachmentName.isEmpty {
                            ChatAttachmentBubbleView(fileName: msg.attachmentName, fileUrl: msg.attachmentUrl, isMine: isMine)
                        }
                        // Content on top with member mention highlight
                        if !msg.text.isEmpty {
                            formattedBubbleText(msg.text, isMine: isMine)
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

                    // Floating Tapback reaction badge
                    if let reacted = groupReactions[msg.id] {
                        FloatingReactionBadge(reaction: reacted, isMine: isMine)
                    }
                }

                // Reaction Summary (Android parity) - shows reaction counts on message
                if !msg.reactions.isEmpty {
                    ReactionSummary(reactions: msg.reactions, myReaction: groupReactions[msg.id])
                        .padding(.horizontal, isMine ? 0 : 4)
                        .padding(.top, -2)
                }

                // Bottom row: time, seen count, reaction, more
                groupMessageFooter(msg: msg, isMine: isMine)
            }
            if !isMine { Spacer(minLength: 44) }
        }
        // Reaction Picker Overlay (Android-style popup)
        .overlay(
            Group {
                if showingReactionPicker && reactionPickerMessageId == msg.id && !reactionPickerIsDirect {
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
                    .foregroundColor(Color(UIColor.tertiaryLabel))

                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(max(msg.seenCount, 1))")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(KinnectTheme.accentBright)

                // Reaction Picker Button - Long press to show picker, tap to quick react
                Button {
                    // Quick react with default (love) on tap
                    Task { await reactToGroupMessage(msgId: msg.id, emoji: "❤️") }
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 12))
                        .foregroundColor(groupReactions[msg.id] != nil ? KinnectTheme.accentBright : Color(UIColor.tertiaryLabel))
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
                        forwardText = msg.text
                        forwardImageUrl = msg.imageUrl
                        showForwardSheet = true
                    } label: {
                        Label("Chuyển tiếp", systemImage: "arrow.turn.up.right")
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
                            Label("Báo cáo tin nhắn", systemImage: "exclamationmark.bubble")
                        }
                        Button(role: .destructive) {
                            Task { await appState.blockUser(userId: msg.sender.id, userName: msg.sender.name) }
                        } label: {
                            Label("Chặn người gửi", systemImage: "hand.raised.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tùy chọn tin nhắn nhóm")
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
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Thư viện ảnh", systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("Tệp & Tài liệu", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .frame(width: 34, height: 38)
            }
            .accessibilityLabel("Đính kèm tệp hoặc ảnh")

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18))
                    .foregroundColor(KinnectTheme.textSecondary)
                    .frame(width: 32, height: 38)
            }
            .accessibilityLabel("Chọn ảnh nhanh")
            .onChange(of: selectedPhoto) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImg = UIImage(data: data),
                       let jpeg = uiImg.jpegData(compressionQuality: 0.72) {
                        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                        await sendGroupMessage(text: text, imageDataURL: dataURL)
                    }
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
                    .foregroundColor(KinnectTheme.accentBright)
                    .frame(width: 32, height: 38)
            }
            .accessibilityLabel("Nhắc tên thành viên")

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
                    }
                    .disabled(isSending)
                    .padding(.trailing, 4)
                    .padding(.bottom, 3)
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

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    appState.showToast("Ghi âm tin nhắn thoại (Đang hoàn thiện)")
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18))
                        .foregroundColor(KinnectTheme.textSecondary)
                        .frame(width: 32, height: 38)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Divider().background(KinnectTheme.borderSoft)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // iOS Custom Navigation Bar for Group Chat
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")

                // Group Avatar + Title
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)

                        Text("\(max(groupMembers.count, 1)) thành viên")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                }

                Spacer()

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
                    Button {
                        showMembersSheet = true
                    } label: {
                        Label("Thành viên & phân quyền", systemImage: "person.3")
                    }
                    Button(role: .destructive) {
                        Task { await leaveGroup() }
                    } label: {
                        Label("Rời nhóm", systemImage: "rectangle.portrait.and.arrow.right")
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
                }
                .accessibilityLabel("Tùy chọn nhóm")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(KinnectTheme.surface)
            .overlay(alignment: .bottom) {
                Divider().background(KinnectTheme.borderSoft)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { msg in
                            groupMessageRow(msg: msg)
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

            mentionSuggestionBar

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
            RenameGroupSheet(groupId: group.id, currentName: group.name) {
                Task { await loadGroupMessages() }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showRenameSheet)
        }
        .sheet(isPresented: $showMembersSheet) {
            GroupMembersView(groupId: group.id)
        }
        .sheet(isPresented: $showAddMemberSheet) {
            AddGroupMembersSheet(groupId: group.id) {
                Task { await loadGroupMessages() }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showAddMemberSheet)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let fileURL):
                guard fileURL.startAccessingSecurityScopedResource() else { return }
                defer { fileURL.stopAccessingSecurityScopedResource() }
                let fileName = fileURL.lastPathComponent
                if let data = try? Data(contentsOf: fileURL) {
                    let base64 = data.base64EncodedString()
                    let mime = mimeTypeForExt(fileURL.pathExtension)
                    let dataURL = "data:\(mime);base64,\(base64)"
                    Task {
                        await sendGroupFileMessage(name: fileName, dataURL: dataURL)
                    }
                }
            case .failure(let err):
                appState.showToast("Không thể chọn tệp: \(err.localizedDescription)")
            }
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

    private func sendGroupMessage(text: String, imageDataURL: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || !imageDataURL.isEmpty else { return }
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
            seenCount: 1,
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
            payload["attachment"] = ["name": "photo.jpg", "data": imageDataURL]
        }
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
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: nil)
        } catch {
            self.messages.removeAll { $0.id == tempId }
            self.text = draft
            appState.showToast(error.localizedDescription)
        }
    }

    private func sendGroupFileMessage(name: String, dataURL: String) async {
        let isImg = dataURL.hasPrefix("data:image/") || name.hasSuffix(".jpg") || name.hasSuffix(".png") || name.hasSuffix(".webp")
        let reqId = "grp_att_\(group.id)_\(UUID().uuidString)"
        let tempId = "opt_\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())

        let optimistic = GroupMessageItem(
            id: tempId,
            groupId: group.id,
            sender: appState.currentUser ?? KinnectUser.fallbackSelf,
            text: "",
            imageUrl: isImg ? dataURL : "",
            attachmentName: isImg ? "" : name,
            attachmentUrl: isImg ? "" : dataURL,
            createdAt: createdAt,
            seenCount: 1,
            reaction: "",
            reactions: [:],
            myReaction: ""
        )
        self.messages.append(optimistic)

        let payload: [String: Any] = [
            "body": "",
            "text": "",
            "attachment": ["name": name, "data": dataURL],
            "requestId": reqId
        ]
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(group.id)/messages",
                method: "POST",
                body: payload,
                requestId: reqId
            )
            await loadGroupMessages()
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: nil)
        } catch {
            self.messages.removeAll { $0.id == tempId }
            appState.showToast("Không gửi được tệp: \(error.localizedDescription)")
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
        if searchQuery.isEmpty { return friends }
        let q = searchQuery.lowercased()
        return friends.filter { $0.name.lowercased().contains(q) || $0.handle.lowercased().contains(q) }
    }

    private var onlineFriends: [KinnectUser] {
        filteredFriends.filter { ($0.isActive && $0.showActivity) || appState.onlineUserIds.contains($0.id) }
    }

    private var offlineFriends: [KinnectUser] {
        filteredFriends.filter { !(($0.isActive && $0.showActivity) || appState.onlineUserIds.contains($0.id)) }
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
                    isOnline: (friend.isActive && friend.showActivity) || appState.onlineUserIds.contains(friend.id)
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

