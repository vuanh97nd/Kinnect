import SwiftUI

struct NotificationsView: View {
    var onBack: (() -> Void)? = nil
    var onOpenFriends: (() -> Void)? = nil
    var onOpenMessages: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    enum NotificationFilter: String, CaseIterable {
        case all = "Tất cả"
        case unread = "Chưa đọc"
    }

    @State private var filter: NotificationFilter = .all
    @State private var searchQuery: String = ""
    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = false

    // Navigation targets (Parity with Android MainActivity.openNotification)
    @State private var selectedPost: PostItem? = nil
    @State private var selectedShort: ShortItem? = nil
    @State private var selectedChatPeer: KinnectUser? = nil
    @State private var selectedProfileUser: KinnectUser? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Dedicated Header Bar (No duplicate title)
            headerBar

            VStack(spacing: 10) {
                // Search Bar (Parity with Android searchField)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(KinnectTheme.textSecondary)
                    TextField("Tìm kiếm thông báo…", text: $searchQuery)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Filter Tabs (Tất cả · Chưa đọc)
                Picker("Bộ lọc thông báo", selection: $filter) {
                    ForEach(NotificationFilter.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)

                // Notifications List
                ScrollView {
                    if filteredNotifications.isEmpty && !isLoading {
                        emptyStateView
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredNotifications.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Divider()
                                        .background(KinnectTheme.border)
                                        .padding(.leading, 68)
                                        .padding(.trailing, 10)
                                }
                                notificationRow(item)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(KinnectTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.border, lineWidth: 1))
                        )
                        .padding(.horizontal, 14)
                        .padding(.bottom, 16)
                    }
                }
                .refreshable {
                    await loadNotifications()
                }
            }
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadNotifications()
        }
        .fullScreenCover(item: $selectedPost) { post in
            NotificationPostDetailView(post: post)
        }
        .fullScreenCover(item: $selectedShort) { short in
            ProfileShortDetailSheet(short: short)
        }
        .fullScreenCover(item: $selectedChatPeer) { peer in
            NavigationStack {
                DirectChatDetailView(peer: peer)
            }
        }
        .fullScreenCover(item: $selectedProfileUser) { user in
            ProfileView(targetUser: user)
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 12) {
            if let onBack = onBack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")
            }

            HStack(spacing: 8) {
                Text("Thông báo")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)

                if appState.unreadNotificationsCount > 0 {
                    Text("\(appState.unreadNotificationsCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(KinnectTheme.accentBright))
                }
            }

            Spacer()

            Button {
                Task { await markAllRead() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Đã đọc")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(KinnectTheme.accentBright)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(KinnectTheme.surfaceElevated))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đánh dấu tất cả đã đọc")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
        .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .bottom)
    }

    private var filteredNotifications: [NotificationItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return notifications.filter { item in
            let t = item.type.lowercased()
            if t == "message" || t == "group_message" {
                return false
            }
            if filter == .unread && item.read {
                return false
            }
            if !q.isEmpty {
                let text = "\(item.actor.name) \(actionText(for: item.type)) \(item.preview)".lowercased()
                if !text.contains(q) {
                    return false
                }
            }
            return true
        }
    }

    private func notificationRow(_ item: NotificationItem) -> some View {
        Button {
            Task { await handleNotificationTap(item) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Left avatar
                Button {
                    if !item.actor.id.isEmpty {
                        selectedProfileUser = item.actor
                    }
                } label: {
                    KinnectAvatarView(
                        name: item.actor.name.isEmpty ? "K" : item.actor.name,
                        avatarURL: item.actor.avatarUrl,
                        colorHex: item.actor.avatarColor,
                        size: 46
                    )
                }
                .buttonStyle(.plain)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(item.actor.name.isEmpty ? "Kinnect" : item.actor.name)
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        + Text(" ")
                        + Text(actionText(for: item.type))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)

                        Spacer(minLength: 4)

                        if !item.read {
                            Circle()
                                .fill(KinnectTheme.accentBright)
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)
                        }
                    }

                    if !item.preview.isEmpty && !item.type.lowercased().contains("like") {
                        Text(item.preview)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Text(formatRelativeDate(item.createdAt))
                        .font(.caption2)
                        .foregroundColor(item.read ? KinnectTheme.textSecondary : KinnectTheme.accentBright)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(item.read ? Color.clear : KinnectTheme.accent.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            KinnectIcon(glyph: .notifications, size: 40, tint: KinnectTheme.textSecondary)
            Text(
                filter == .unread
                    ? "Không có thông báo chưa đọc."
                    : (searchQuery.isEmpty ? "Chưa có thông báo mới." : "Không tìm thấy thông báo.")
            )
            .font(.subheadline)
            .foregroundColor(KinnectTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func actionText(for type: String) -> String {
        switch type.lowercased() {
        case "like": return "đã thích bài viết của bạn"
        case "comment": return "đã bình luận về bài viết của bạn"
        case "comment_reply": return "đã trả lời bình luận của bạn"
        case "friend_request": return "đã gửi lời mời kết bạn"
        case "friend_accept", "friend_accepted": return "đã chấp nhận lời mời kết bạn"
        case "follow": return "đã bắt đầu theo dõi bạn"
        case "short_like": return "đã thích video ngắn của bạn"
        case "short_comment": return "đã bình luận video ngắn của bạn"
        case "missed_call": return "đã gọi nhỡ cho bạn"
        default: return "đã tương tác với bạn"
        }
    }

    private func loadNotifications() async {
        if notifications.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/notifications"),
           let list = cached["notifications"] as? [[String: Any]] {
            self.notifications = list.map(NotificationItem.from)
        }
        isLoading = true
        defer { isLoading = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/notifications") {
            let list = res["notifications"] as? [[String: Any]] ?? []
            self.notifications = list.map(NotificationItem.from)
        }
    }

    // MARK: - Navigation Target Handler (Matching Android MainActivity.openNotification)
    private func handleNotificationTap(_ item: NotificationItem) async {
        if !item.read {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/notifications",
                method: "POST",
                body: ["ids": [item.id]],
                requestId: "read_\(item.id)"
            )
            if let idx = notifications.firstIndex(where: { $0.id == item.id }) {
                notifications[idx].read = true
            }
            await appState.refreshGlobalBadges()
        }

        let kind = item.type.lowercased()
        let ref = item.ref

        // 1. Direct message / missed call -> open chat
        if kind == "message" || kind == "missed_call" {
            self.selectedChatPeer = item.actor
            return
        }

        // 2. Short like / short comment -> open short detail video player
        if kind.contains("short") || kind.contains("video") {
            if !ref.isEmpty, let res = try? await KinnectAPIClient.shared.requestJSON("/api/shorts?video=\(ref)") {
                let list = res["shorts"] as? [[String: Any]] ?? []
                if let first = list.first {
                    self.selectedShort = ShortItem.from(first)
                    return
                }
            }
            // Fallback short item
            self.selectedShort = ShortItem(
                id: ref.isEmpty ? item.id : ref,
                author: item.actor,
                title: item.preview.isEmpty ? "Video ngắn" : item.preview,
                caption: item.preview,
                videoUrl: "/api/shorts/\(ref)/video",
                durationSec: 15,
                likesCount: 1,
                commentsCount: 0,
                viewsCount: 10,
                liked: false,
                createdAt: item.createdAt
            )
            return
        }

        // 3. Like / comment / comment_reply / post -> open post detail view
        if kind.contains("post") || kind.contains("comment") || kind.contains("like") {
            if !ref.isEmpty, let res = try? await KinnectAPIClient.shared.requestJSON("/api/posts?post=\(ref)") {
                let list = res["posts"] as? [[String: Any]] ?? []
                if let first = list.first {
                    self.selectedPost = PostItem.from(first)
                    return
                }
            }
            // Fallback post item
            self.selectedPost = PostItem(
                id: ref.isEmpty ? item.id : ref,
                author: item.actor,
                text: item.preview.isEmpty ? "Bài viết từ thông báo" : item.preview,
                imageUrl: "",
                category: "general",
                createdAt: item.createdAt,
                likesCount: 1,
                commentsCount: 1,
                liked: false,
                userReaction: ""
            )
            return
        }

        // 4. Friend request / Friend accept / Follow -> open Profile
        if kind.contains("friend") || kind.contains("follow") {
            self.selectedProfileUser = item.actor
            return
        }

        // 5. Default: Actor profile
        if !item.actor.id.isEmpty {
            self.selectedProfileUser = item.actor
        }
    }

    private func markAllRead() async {
        let reqId = "notif_read_\(Int(Date().timeIntervalSince1970))"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/notifications",
            method: "POST",
            body: ["scope": "social"],
            requestId: reqId
        )
        for idx in notifications.indices {
            notifications[idx].read = true
        }
        await appState.refreshGlobalBadges()
    }
}

// MARK: - Dedicated Notification Post Detail View (Parity Android postDetail lines 2771-2779)
private struct NotificationPostDetailView: View {
    let post: PostItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var comments: [[String: Any]] = []
    @State private var commentText = ""
    @State private var isSubmittingComment = false
    @State private var isLiked = false
    @State private var likesCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Header
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quay lại")

                Text("Chi tiết bài viết")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
            .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Author Row
                    HStack(spacing: 12) {
                        KinnectAvatarView(
                            name: post.author.name,
                            avatarURL: post.author.avatarUrl,
                            colorHex: post.author.avatarColor,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.author.name)
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text("@\(post.author.handle.isEmpty ? post.author.name : post.author.handle) · \(formatRelativeDate(post.createdAt))")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        Spacer()
                    }

                    // Post Text
                    Text(post.text)
                        .font(.body)
                        .foregroundColor(KinnectTheme.textPrimary)
                        .kinnectMultiline()

                    // Post Image
                    if !post.imageUrl.isEmpty {
                        KinnectRemoteImageView(
                            rawURL: post.imageUrl,
                            contentMode: .fit,
                            cornerRadius: 14,
                            maxHeight: 340
                        )
                        .frame(maxWidth: .infinity)
                    }

                    // Stats and React Button
                    HStack(spacing: 16) {
                        Button {
                            toggleLike()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .foregroundColor(isLiked ? KinnectTheme.danger : KinnectTheme.textSecondary)
                                Text("\(likesCount) thích")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(isLiked ? KinnectTheme.danger : KinnectTheme.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 6) {
                            Image(systemName: "bubble.right")
                                .foregroundColor(KinnectTheme.textSecondary)
                            Text("\(comments.count) bình luận")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)

                    Divider().background(KinnectTheme.borderSoft)

                    // Comments Section
                    Text("Bình luận")
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)

                    if comments.isEmpty {
                        Text("Chưa có bình luận nào. Hãy là người đầu tiên bình luận!")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(comments.enumerated()), id: \.offset) { _, comment in
                                let user = comment["user"] as? [String: Any] ?? [:]
                                let name = user["name"] as? String ?? "Thành viên"
                                let av = user["avatar"] as? String ?? ""
                                let color = user["avatarColor"] as? String ?? "#7C3AED"
                                let text = comment["text"] as? String ?? ""

                                HStack(alignment: .top, spacing: 10) {
                                    KinnectAvatarView(name: name, avatarURL: av, colorHex: color, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.caption.bold())
                                            .foregroundColor(KinnectTheme.textPrimary)
                                        Text(text)
                                            .font(.subheadline)
                                            .foregroundColor(KinnectTheme.textPrimary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            }
                        }
                    }
                }
                .padding(16)
                .kinnectCard()
                .padding(14)
            }

            // Bottom Comment Input Bar
            HStack(spacing: 10) {
                TextField("Viết bình luận…", text: $commentText)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)

                Button {
                    Task { await submitComment() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(commentText.trimmingCharacters(in: .whitespaces).isEmpty ? KinnectTheme.surfaceElevated : KinnectTheme.accentBright))
                }
                .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmittingComment)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(KinnectTheme.surface.ignoresSafeArea(edges: .bottom))
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .onAppear {
            self.likesCount = post.likesCount
            self.isLiked = post.liked
            Task { await loadComments() }
        }
    }

    private func toggleLike() {
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        Task {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/react",
                method: "POST",
                body: ["reaction": isLiked ? "like" : "none"]
            )
        }
    }

    private func loadComments() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/posts/\(post.id)/comments") {
            self.comments = res["comments"] as? [[String: Any]] ?? []
        }
    }

    private func submitComment() async {
        let text = commentText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSubmittingComment = true
        defer { isSubmittingComment = false }

        let res = try? await KinnectAPIClient.shared.requestJSON(
            "/api/posts/\(post.id)/comments",
            method: "POST",
            body: ["text": text]
        )
        if res?["ok"] as? Bool == true || res?["comment"] != nil {
            commentText = ""
            await loadComments()
        }
    }
}
