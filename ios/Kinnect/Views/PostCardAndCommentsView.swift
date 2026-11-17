import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct PostCardView: View {
    let post: PostItem
    let currentUserId: String
    let isAuthorOnline: Bool
    var onOpenAuthorProfile: (() -> Void)? = nil
    let onReact: (String) -> Void
    let onOpenComments: () -> Void
    var onEdit: (() -> Void)? = nil
    var onChangeAudience: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    let onDelete: () -> Void
    let onReport: () -> Void

    private let reactionOptions: [(key: String, emoji: String, title: String)] = [
        ("like", "👍", "Thích"),
        ("love", "❤️", "Yêu thích"),
        ("haha", "😆", "Haha"),
        ("wow", "😮", "Wow"),
        ("sad", "😢", "Buồn"),
        ("angry", "😡", "Phẫn nộ")
    ]

    @State private var isBouncing = false
    @State private var showReactionDock = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    onOpenAuthorProfile?()
                } label: {
                    KinnectAvatarView(
                        name: post.author.name,
                        avatarURL: post.author.avatarUrl,
                        colorHex: post.author.avatarColor,
                        size: 42,
                        isOnline: isAuthorOnline
                    )
                }
                .buttonStyle(.plain)

                Button {
                    onOpenAuthorProfile?()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.author.name)
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                            .kinnectMultiline()
                        HStack(spacing: 6) {
                            if !post.author.handle.isEmpty {
                                Text("@\(post.author.handle)")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            Text(formatRelativeDate(post.createdAt))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    if post.author.id == currentUserId {
                        if let onEdit {
                            Button(action: onEdit) {
                                Label("Chỉnh sửa bài viết", systemImage: "pencil")
                            }
                        }
                        if let onChangeAudience {
                            Button(action: onChangeAudience) {
                                Label("Thay đổi đối tượng xem", systemImage: "globe")
                            }
                        }
                        if let onHide {
                            Button(action: onHide) {
                                Label("Ẩn bài viết", systemImage: "eye.slash")
                            }
                        }
                        Button(role: .destructive, action: onDelete) {
                            Label("Xóa bài viết", systemImage: "trash")
                        }
                    } else {
                        if let onHide {
                            Button(action: onHide) {
                                Label("Ẩn bài viết", systemImage: "eye.slash")
                            }
                        }
                        Button(role: .destructive, action: onReport) {
                            HStack {
                                Text("Báo cáo / Chặn UGC")
                                KinnectIcon(glyph: .report, size: 18, tint: KinnectTheme.danger)
                            }
                        }
                    }
                } label: {
                    KinnectIcon(glyph: .more, size: 22, tint: KinnectTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn bài viết")
            }

            if !post.text.isEmpty {
                Text(post.text)
                    .font(.body)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .kinnectMultiline()
            }

            if !post.imageUrl.isEmpty {
                KinnectMediaTile(path: post.imageUrl, kind: post.mediaKind)
            }

            // Statistics Summary Row (Android parity: ❤️ 2 cảm xúc ... 0 bình luận)
            HStack {
                if post.likesCount > 0 {
                    HStack(spacing: 4) {
                        Text(post.liked ? reactionEmoji(for: post.userReaction) : "❤️")
                            .font(.caption)
                        Text("\(post.likesCount) cảm xúc")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                } else {
                    Text("Chưa có cảm xúc")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }

                Spacer()

                Text("\(post.commentsCount) bình luận")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(.top, 2)
            .padding(.bottom, 2)

            Divider()

            // Equal 3-Column Action Bar (Android parity: 33% Cảm xúc, 33% Bình luận, 33% Chia sẻ)
            HStack(spacing: 0) {
                // Column 1: Cảm xúc (Reaction)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        showReactionDock.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if post.liked {
                            Text(reactionEmoji(for: post.userReaction))
                                .font(.subheadline)
                            Text(reactionTitle(for: post.userReaction))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.accentBright)
                        } else {
                            KinnectIcon(glyph: .reaction, size: 18, tint: KinnectTheme.textSecondary)
                            Text("Cảm xúc")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .scaleEffect(isBouncing ? 1.3 : 1.0)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.25).onEnded { _ in
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            showReactionDock = true
                        }
                    }
                )
                .accessibilityLabel("Cảm xúc")

                // Column 2: Bình luận (Comment)
                Button(action: onOpenComments) {
                    HStack(spacing: 6) {
                        KinnectIcon(glyph: .comment, size: 18, tint: KinnectTheme.textSecondary)
                        Text("Bình luận")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Bình luận")

                // Column 3: Chia sẻ (Share) - Native SwiftUI ShareLink (safe on iPad popover & route permalink)
                if let shareURL = postShareURL {
                    ShareLink(
                        item: shareURL,
                        subject: Text(shareSubject),
                        message: Text(post.text.isEmpty ? "Xem bài viết trên Kinnect" : post.text)
                    ) {
                        HStack(spacing: 6) {
                            KinnectIcon(glyph: .share, size: 18, tint: KinnectTheme.textSecondary)
                            Text("Chia sẻ")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Chia sẻ bài viết")
                }
            }
            .overlay(alignment: .topLeading) {
                if showReactionDock {
                    HStack(spacing: 6) {
                        ForEach(reactionOptions, id: \.key) { item in
                            let isSelected = post.liked && post.userReaction == item.key
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onReact(item.key)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                                    isBouncing = true
                                    showReactionDock = false
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    isBouncing = false
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(item.emoji)
                                        .font(KinnectTheme.scaled(27))
                                        .scaleEffect(isSelected ? 1.16 : 1.0)
                                    Text(item.title)
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(isSelected ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? KinnectTheme.accent.opacity(0.14) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            .shadow(color: Color.black.opacity(0.18), radius: 14, y: 5)
                            .overlay(Capsule().stroke(KinnectTheme.borderSoft, lineWidth: 1))
                    )
                    .offset(x: 2, y: -62)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.78, anchor: .bottomLeading).combined(with: .opacity),
                        removal: .scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity)
                    ))
                    .zIndex(30)
                }
            }
        }
        .modifier(FeedCardStyle())
        .zIndex(showReactionDock ? 50 : 0)
    }

    private var postShareURL: URL? {
        let encodedId = post.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?#"))) ?? post.id
        let route = "/?s=postDetail&post=\(encodedId)"
        return ServerConfig.resolveURL(route) ?? URL(string: "\(ServerConfig.defaultOrigin)\(route)") ?? URL(string: "https://app.kinnect.io.vn\(route)")
    }

    private var shareSubject: String {
        return "Bài viết từ \(post.author.name) trên Kinnect"
    }

    private func reactionTitle(for key: String) -> String {
        switch key.lowercased() {
        case "love": return "Yêu thích"
        case "haha": return "Haha"
        case "wow": return "Wow"
        case "sad": return "Buồn"
        case "angry": return "Phẫn nộ"
        default: return "Thích"
        }
    }

    private func reactionEmoji(for key: String) -> String {
        switch key.lowercased() {
        case "love": return "❤️"
        case "care": return "🥰"
        case "haha": return "😆"
        case "wow": return "😮"
        case "sad": return "😢"
        case "angry": return "😡"
        default: return "👍"
        }
    }
}

struct PostCommentsSheet: View {
    let post: PostItem
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var comments: [CommentItem] = []
    @State private var newComment = ""
    @State private var pendingCommentReactions: Set<String> = []
    @State private var replyingTo: CommentItem? = nil
    @State private var isLoading = false
    @State private var loadError: String? = nil

    private let quickEmojis = ["😍", "😂", "🔥", "👏", "🥰", "😮", "😢", "💜"]

    private let commentReactionOptions: [(key: String, emoji: String, title: String)] = [
        ("like", "??", "Th?ch"), ("love", "??", "Y?u th?ch"),
        ("haha", "??", "Haha"), ("wow", "??", "Wow"),
        ("sad", "??", "Bu?n"), ("angry", "??", "Ph?n n?")
    ]

    private struct CommentRow: Identifiable {
        let comment: CommentItem
        let depth: Int
        let parentAuthorName: String?
        var id: String { comment.id }
    }

    private var commentRows: [CommentRow] {
        let ids = Set(comments.map { $0.id })
        let children = Dictionary(grouping: comments, by: { $0.parentId ?? "" })
        var visited = Set<String>()
        var rows: [CommentRow] = []
        func appendThread(_ start: CommentItem) {
            var stack: [(CommentItem, Int, String?)] = [(start, 0, nil)]
            while let (comment, depth, parentName) = stack.popLast() {
                guard visited.insert(comment.id).inserted else { continue }
                rows.append(CommentRow(comment: comment, depth: depth, parentAuthorName: parentName))
                for child in (children[comment.id] ?? []).reversed() {
                    stack.append((child, depth + 1, comment.author.name))
                }
            }
        }
        for comment in comments where comment.parentId == nil || !ids.contains(comment.parentId ?? "") {
            appendThread(comment)
        }
        // Also render malformed cycles once, without recursive SwiftUI views.
        for comment in comments where !visited.contains(comment.id) {
            appendThread(comment)
        }
        return rows
    }

    private func replyRoot(for comment: CommentItem) -> CommentItem {
        var root = comment
        var visited: Set<String> = [comment.id]
        while let parentId = root.parentId,
              let parent = comments.first(where: { $0.id == parentId }),
              visited.insert(parent.id).inserted {
            root = parent
        }
        return root
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let loadError, !comments.isEmpty {
                    KinnectErrorBanner(message: loadError) {
                        Task { await loadComments() }
                    }
                    .padding(.horizontal, KinnectTheme.spaceLG)
                    .padding(.vertical, KinnectTheme.spaceSM)
                }

                if comments.isEmpty && isLoading {
                    KinnectStateView(mode: .loading("Đang tải bình luận…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if comments.isEmpty && !isLoading {
                    if let loadError {
                        KinnectStateView(mode: .error(
                            title: "Không tải được bình luận",
                            message: loadError,
                            retryTitle: "Thử lại",
                            onRetry: { Task { await loadComments() } }
                        ))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        KinnectStateView(mode: .empty(
                            glyph: .comment,
                            systemIcon: nil,
                            title: "Chưa có bình luận nào",
                            subtitle: "Hãy là người đầu tiên để lại bình luận!",
                            actionTitle: nil,
                            onAction: nil
                        ))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    List {
                        ForEach(commentRows) { row in
                            commentRowView(row.comment, depth: min(row.depth, 1), parentAuthorName: row.parentAuthorName)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                // Quick emoji reaction bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(quickEmojis, id: \.self) { emoji in
                            Button {
                                newComment.append(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.title3)
                                    .frame(minWidth: 32, minHeight: 32)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
                .background(KinnectTheme.surface)

                // Replying banner
                if let replying = replyingTo {
                    HStack {
                        Text("Đang trả lời \(replying.author.name) • Chạm để huỷ")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.accentBright)
                        Spacer()
                        Button {
                            replyingTo = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(KinnectTheme.surfaceElevated)
                }

                HStack(spacing: 8) {
                    TextField(replyingTo != nil ? "Trả lời \(replyingTo!.author.name)..." : "Viết bình luận...", text: $newComment)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(.white)

                    KinnectIconButton(
                        glyph: .send,
                        label: "Gửi bình luận",
                        tint: KinnectTheme.accentBright
                    ) {
                        Task { await sendComment() }
                    }
                    .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(KinnectTheme.surface)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Bình luận")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadComments()
            }
        }
    }

    private func commentRowView(_ c: CommentItem, depth: Int, parentAuthorName: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2.bold())
                    .foregroundColor(KinnectTheme.textSecondary)
                    .padding(.top, 6)
            }

            KinnectAvatarView(
                name: c.author.name,
                avatarURL: c.author.avatarUrl,
                colorHex: c.author.avatarColor,
                size: depth > 0 ? 28 : 34
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(c.author.name)
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textPrimary)

                    if let parent = parentAuthorName, depth > 0 {
                        Text("▸ \(parent)")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.accentBright)
                    }

                    Spacer()

                    if c.author.id == appState.currentUser?.id {
                        Button(role: .destructive) {
                            Task { await deleteComment(c) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(c.text)
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .kinnectMultiline()

                // Action bar: Trả lời, Thả cảm xúc, Thời gian
                HStack(spacing: 14) {
                    Button {
                        replyingTo = replyRoot(for: c)
                    } label: {
                        Text("Trả lời")
                            .font(.caption2.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    .buttonStyle(.plain)

                    Button {
                        setCommentReaction(c, reaction: c.liked ? nil : "like")
                    } label: {
                        HStack(spacing: 3) {
                            Text(commentReactionOptions.first(where: { $0.key == c.myReaction })?.emoji ?? "?")
                                .font(.caption2)
                                .foregroundColor(c.liked ? KinnectTheme.danger : KinnectTheme.textSecondary)
                            if c.likesCount > 0 {
                                Text("\(c.likesCount)")
                                    .font(.caption2)
                                    .foregroundColor(c.liked ? KinnectTheme.danger : KinnectTheme.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    .disabled(pendingCommentReactions.contains(c.id))
                    .contextMenu {
                        ForEach(commentReactionOptions, id: \.key) { option in
                            Button {
                                setCommentReaction(c, reaction: option.key)
                            } label: {
                                Text("\(option.emoji) \(option.title)")
                            }
                        }
                        if c.liked {
                            Button("G? c?m x?c", role: .destructive) {
                                setCommentReaction(c, reaction: nil)
                            }
                        }
                    }
                    .accessibilityLabel("C?m x?c b?nh lu?n")
                    .accessibilityHint("Nh?n gi? ?? ch?n m?t trong s?u c?m x?c")

                    Text(formatRelativeDate(c.createdAt))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.leading, CGFloat(depth * 24))
        .listRowBackground(KinnectTheme.surface)
    }

    private func setCommentReaction(_ item: CommentItem, reaction: String?) {
        guard !pendingCommentReactions.contains(item.id) else { return }
        pendingCommentReactions.insert(item.id)
        Task {
            defer { pendingCommentReactions.remove(item.id) }
            do {
                let response = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/comments/\(item.id)/reaction",
                    method: "POST",
                    body: ["reaction": reaction.map { $0 as Any } ?? NSNull()]
                )
                if let updated = response["comment"] as? [String: Any],
                   let idx = comments.firstIndex(where: { $0.id == item.id }) {
                    var updatedComment = CommentItem.from(updated)
                    updatedComment.author = comments[idx].author
                    comments[idx] = updatedComment
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                appState.showToast(error.localizedDescription)
            }
        }
    }

    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/posts/\(post.id)/comments")
            let list = res["comments"] as? [[String: Any]] ?? []
            self.comments = list.map(CommentItem.from)
            self.loadError = nil
        } catch {
            self.loadError = error.localizedDescription
        }
    }

    private func sendComment() async {
        let clean = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let draft = newComment
        newComment = ""
        let replyTarget = replyingTo
        let parent = replyTarget?.id
        replyingTo = nil
        let reqId = "comment_\(post.id)_\(UUID().uuidString)"
        do {
            var bodyDict: [String: Any] = ["body": clean]
            if let parent = parent {
                bodyDict["parentId"] = parent
            }
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/comments",
                method: "POST",
                body: bodyDict,
                requestId: reqId
            )
            await loadComments()
            onChanged()
        } catch {
            newComment = draft
            replyingTo = replyTarget
            appState.showToast(error.localizedDescription)
        }
    }

    private func deleteComment(_ item: CommentItem) async {
        let reqId = "del_comment_\(item.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/comments/\(item.id)",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            await loadComments()
            onChanged()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
