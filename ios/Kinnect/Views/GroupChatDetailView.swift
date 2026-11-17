import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
                        .font(KinnectTheme.scaled(12, weight: .semibold))
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
                    .foregroundColor(KinnectTheme.messageMeta)

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
                        .font(KinnectTheme.scaled(12))
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
                        .font(KinnectTheme.scaled(12))
                        .foregroundColor(KinnectTheme.messageMeta)
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
                                        .font(KinnectTheme.scaled(12))
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
                    .font(KinnectTheme.scaled(16, weight: .bold))
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
                .font(KinnectTheme.scaled(16))
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
                        .font(KinnectTheme.scaled(18, weight: .semibold))
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
                                    colors: [KinnectTheme.messageVioletStart, KinnectTheme.messageVioletEnd],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                        Image(systemName: "person.2.fill")
                            .font(KinnectTheme.scaled(16, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(KinnectTheme.scaled(16, weight: .bold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)

                        Text("\(max(groupMembers.count, 1)) thành viên")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(KinnectTheme.messageMeta)
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
                            .font(KinnectTheme.scaled(15, weight: .bold))
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
                    let mime = kinnectMimeTypeForExt(fileURL.pathExtension)
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
