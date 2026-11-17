import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
                        .font(KinnectTheme.scaled(18, weight: .semibold))
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
                                .font(KinnectTheme.scaled(16, weight: .semibold))
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(
                                        (appState.onlineUserIds.contains(peer.id) || (peer.isActive && peer.showActivity))
                                            ? KinnectTheme.onlinePresence
                                            : KinnectTheme.messageMeta
                                    )
                                    .frame(width: 7, height: 7)

                                Text(
                                    (appState.onlineUserIds.contains(peer.id) || (peer.isActive && peer.showActivity))
                                        ? "Đang trực tuyến"
                                        : "Ngoại tuyến"
                                )
                                .font(KinnectTheme.scaled(12))
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
                                .fill(KinnectTheme.onlinePresence.opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: "phone.fill")
                                .font(KinnectTheme.scaled(15))
                                .foregroundColor(KinnectTheme.onlinePresence)
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
                                .font(KinnectTheme.scaled(15))
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
                                .font(KinnectTheme.scaled(15, weight: .bold))
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
                        .font(KinnectTheme.scaled(16))
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
                        .font(KinnectTheme.scaled(28))
                        .foregroundColor(KinnectTheme.messageMeta)
                        .frame(width: 34, height: 38)
                }
                .accessibilityLabel("Đính kèm tệp hoặc ảnh")

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(KinnectTheme.scaled(18))
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
                    .font(KinnectTheme.scaled(16))
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
                        .font(KinnectTheme.scaled(16))
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
                                            colors: [KinnectTheme.messageVioletStart, KinnectTheme.messageVioletEnd],
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
                                .font(KinnectTheme.scaled(18))
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
                    let mime = kinnectMimeTypeForExt(fileURL.pathExtension)
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
                                .font(KinnectTheme.scaled(16))
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
                                                        colors: [KinnectTheme.messageVioletStart, KinnectTheme.messageVioletEnd],
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
                        .foregroundColor(KinnectTheme.messageMeta)

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
                                .foregroundColor(KinnectTheme.messageMeta)
                        } else {
                            Text("· Đã gửi")
                                .font(.system(size: 11))
                                .foregroundColor(KinnectTheme.messageMeta)
                        }
                    }

                    // Reaction Picker Button - Long press to show picker, tap to quick react
                    Button {
                        // Quick react with default (love) on tap
                        Task { await reactToMessage(msgId: msg.id, emoji: "❤️") }
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(KinnectTheme.scaled(12))
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
                            .font(KinnectTheme.scaled(12))
                            .foregroundColor(KinnectTheme.messageMeta)
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
