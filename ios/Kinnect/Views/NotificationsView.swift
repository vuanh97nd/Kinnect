import SwiftUI

struct NotificationsView: View {
    var onBack: (() -> Void)? = nil
    var onOpenFriends: (() -> Void)? = nil
    var onOpenMessages: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    enum NotificationFilter: String, CaseIterable {
        case all = "Tất cả"
        case unread = "Chưa đọc"

        var localizedTitle: String { L10n.tr(rawValue) }
    }

    @State private var filter: NotificationFilter = .all
    @State private var searchQuery: String = ""
    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = false

    // Navigation targets (Parity with Android MainActivity.openNotification)
    @State private var selectedPost: PostItem? = nil
    @State private var shouldOpenPostComments = false
    @State private var selectedShort: ShortItem? = nil
    @State private var shouldOpenShortComments = false
    @State private var selectedChatPeer: KinnectUser? = nil
    @State private var selectedProfileUser: KinnectUser? = nil
    @State private var showPrivateAlbumSheet = false
    @State private var privatePhotos: [PrivatePhotoItem] = []
    @State private var privateRequests: [PrivateAccessRequestItem] = []

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Dedicated Header Bar - matches Android accountHeader pattern
            PinnedHeaderBar.standard(
                title: L10n.tr("Thông báo"),
                onBack: onBack ?? { dismiss() },
                trailingActions: [
                    PinnedHeaderBar.TrailingAction(
                        systemImage: "checkmark.circle.fill",
                        accessibilityLabel: L10n.tr("Đánh dấu đã đọc tất cả"),
                        action: { Task { await markAllRead() } },
                        badgeCount: appState.unreadNotificationsCount > 0 ? appState.unreadNotificationsCount : nil,
                        badgeColor: KinnectTheme.accent
                    )
                ]
            )

            VStack(spacing: 10) {
                // Search Bar (Parity with Android searchField)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(KinnectTheme.textSecondary)
                    TextField(
                        "",
                        text: $searchQuery,
                        prompt: Text(L10n.tr("Tìm kiếm thông báo…"))
                            .foregroundColor(KinnectTheme.inputPlaceholder)
                    )
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textPrimary)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(KinnectTheme.textSecondary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Xóa tìm kiếm"))
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, searchQuery.isEmpty ? 12 : 4)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // Filter Tabs (Tất cả · Chưa đọc)
                KinnectSegmentedBar(
                    selection: $filter,
                    accessibilityLabel: L10n.tr("Bộ lọc thông báo")
                )
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
                .clipped()
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
        .onReceive(NotificationCenter.default.publisher(for: .kinnectNotificationsChanged)) { _ in
            Task { await loadNotifications() }
        }
        .fullScreenCover(item: $selectedPost) { post in
            NotificationPostDetailView(post: post, autoOpenComments: shouldOpenPostComments)
        }
        .fullScreenCover(item: $selectedShort) { short in
            ProfileShortDetailSheet(short: short, initialOpenComments: shouldOpenShortComments)
        }
        .fullScreenCover(item: $selectedChatPeer) { peer in
            NavigationStack {
                DirectChatDetailView(peer: peer)
            }
        }
        .fullScreenCover(item: $selectedProfileUser) { user in
            ProfileView(targetUser: user)
        }
        .sheet(isPresented: $showPrivateAlbumSheet) {
            PrivateAlbumManageSheet(photos: $privatePhotos, requests: $privateRequests, onRefresh: {})
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
                .accessibilityLabel(L10n.tr("Quay lại"))
            }

            HStack(spacing: 8) {
                Text(L10n.tr("Thông báo"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)

                if appState.unreadNotificationsCount > 0 {
                    Text("\(appState.unreadNotificationsCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(KinnectTheme.accent))
                }
            }

            Spacer()

            Button {
                Task { await markAllRead() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text(L10n.tr("Đã đọc"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(KinnectTheme.accentBright)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(KinnectTheme.surfaceElevated))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Đánh dấu tất cả đã đọc"))
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
        .overlay(Divider().background(KinnectTheme.borderSoft), alignment: .bottom)
    }

    // MARK: - Filtered Notifications

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

    private func shouldShowPreview(for item: NotificationItem) -> Bool {
        let trimmed = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let kind = item.type.lowercased()
        if kind.contains("like")
            || kind == "friend_request"
            || kind == "friend_accept"
            || kind == "friend_accepted"
            || kind == "follow" {
            return false
        }
        let foldedPreview = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
        let foldedAction = actionText(for: item.type)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
        return !foldedPreview.contains(foldedAction)
    }

    private func notificationRow(_ item: NotificationItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left avatar button (sibling, not nested inside another Button)
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
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Notification content button
            Button {
                Task { await handleNotificationTap(item) }
            } label: {
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

                    if shouldShowPreview(for: item) {
                        Text(item.preview)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Text(formatRelativeDate(item.createdAt))
                        .font(.caption2)
                        .foregroundColor(item.read ? KinnectTheme.textSecondary : KinnectTheme.accentBright)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(item.read ? Color.clear : KinnectTheme.accent.opacity(0.08))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            KinnectIcon(glyph: .notifications, size: 40, tint: KinnectTheme.textSecondary)
            Text(
                filter == .unread
                    ? L10n.tr("Không có thông báo chưa đọc.")
                    : (searchQuery.isEmpty ? L10n.tr("Chưa có thông báo mới.") : L10n.tr("Không tìm thấy thông báo."))
            )
            .font(.subheadline)
            .foregroundColor(KinnectTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func actionText(for type: String) -> String {
        switch type.lowercased() {
        case "like", "post_like", "reaction":
            return L10n.tr("đã thích bài viết của bạn")
        case "comment", "post_comment":
            return L10n.tr("đã bình luận về bài viết của bạn")
        case "comment_reply", "reply":
            return L10n.tr("đã trả lời bình luận của bạn")
        case "comment_reaction", "comment_like":
            return L10n.tr("đã bày tỏ cảm xúc với bình luận của bạn")
        case "share", "post_share", "repost":
            return L10n.tr("đã chia sẻ bài viết của bạn")
        case "gift", "live_gift":
            return L10n.tr("đã gửi quà tặng cho bạn")
        case "live", "live_started", "live_stream":
            return L10n.tr("đang phát trực tiếp")
        case "call", "incoming_call", "video_call", "voice_call":
            return L10n.tr("đã gọi cho bạn")
        case "missed_call":
            return L10n.tr("đã gọi nhỡ cho bạn")
        case "private_request":
            return L10n.tr("muốn xem ảnh riêng tư của bạn")
        case "private_granted":
            return L10n.tr("đã cấp quyền xem album riêng tư cho bạn")
        case "private_revoked":
            return L10n.tr("đã thu hồi quyền xem album riêng tư")
        case "friend_request":
            return L10n.tr("đã gửi lời mời kết bạn")
        case "friend_accept", "friend_accepted":
            return L10n.tr("đã chấp nhận lời mời kết bạn")
        case "follow":
            return L10n.tr("đã bắt đầu theo dõi bạn")
        case "short_like":
            return L10n.tr("đã thích video ngắn của bạn")
        case "short_comment", "short_comment_reply":
            return L10n.tr("đã bình luận video ngắn của bạn")
        case "message":
            return L10n.tr("đã gửi tin nhắn cho bạn")
        case "group_message":
            return L10n.tr("đã nhắn tin trong nhóm")
        case "security_alert":
            return L10n.tr("gửi cảnh báo bảo mật tài khoản")
        case "support_ticket", "support_reply":
            return L10n.tr("đã phản hồi yêu cầu hỗ trợ")
        case "ai_review", "moderation":
            return L10n.tr("đã cập nhật trạng thái kiểm duyệt")
        default:
            return L10n.tr("đã tương tác với bạn")
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

        // 1. Direct message / call / missed call -> open chat
        if kind == "message" || kind == "missed_call" || kind == "call" || kind == "incoming_call" || kind == "video_call" || kind == "voice_call" {
            self.selectedChatPeer = item.actor
            return
        }

        // 2. Private album access events
        if kind == "private_request" {
            self.showPrivateAlbumSheet = true
            return
        }
        if kind == "private_granted" || kind == "private_revoked" {
            if !item.actor.id.isEmpty {
                self.selectedProfileUser = item.actor
            } else {
                appState.showToast(L10n.tr("Thông tin album riêng tư không còn khả dụng."))
            }
            return
        }

        // 3. Gift / Live -> open actor profile
        if kind == "gift" || kind == "live_gift" || kind == "live" || kind == "live_started" || kind == "live_stream" {
            if !item.actor.id.isEmpty {
                self.selectedProfileUser = item.actor
            }
            return
        }

        // 4. Short like / short comment / short comment_reply -> open short detail video player
        if kind.contains("short") || kind.contains("video")
            || (kind == "comment_reply" && item.targetKind.lowercased() == "short") {
            let openComments = kind == "short_comment" || kind == "short_like" || kind == "short_comment_reply" || kind == "comment_reply"
            if !ref.isEmpty, let res = try? await KinnectAPIClient.shared.requestJSON("/api/shorts?video=\(ref)") {
                let list = res["shorts"] as? [[String: Any]] ?? []
                if let matched = list.first(where: { ($0["id"] as? String) == ref }) {
                    self.shouldOpenShortComments = openComments
                    self.selectedShort = ShortItem.from(matched)
                    return
                }
            }
            appState.showToast(L10n.tr("Video này không còn khả dụng hoặc đã bị xóa."))
            return
        }

        // 5. Like / comment / comment_reply / comment_reaction / share / post -> open post detail view
        //    (comment_reply may reference a Short when targetKind is absent; fall back to /api/shorts)
        if kind.contains("post") || kind.contains("comment") || kind.contains("like") || kind == "share" || kind == "repost" || kind == "reaction" {
            let openPostComments = kind == "comment_reply" || kind == "comment" || kind == "post_comment" || kind == "comment_reaction" || kind == "comment_like"
            if !ref.isEmpty, let res = try? await KinnectAPIClient.shared.requestJSON("/api/posts?post=\(ref)") {
                let list = res["posts"] as? [[String: Any]] ?? []
                if let first = list.first {
                    self.shouldOpenPostComments = openPostComments
                    self.selectedPost = PostItem.from(first)
                    return
                }
            }
            if (kind == "comment_reply" || kind == "comment_reaction"), !ref.isEmpty,
               let res = try? await KinnectAPIClient.shared.requestJSON("/api/shorts?video=\(ref)") {
                let list = res["shorts"] as? [[String: Any]] ?? []
                if let matched = list.first(where: { ($0["id"] as? String) == ref }) {
                    self.shouldOpenShortComments = true
                    self.selectedShort = ShortItem.from(matched)
                    return
                }
            }
            appState.showToast(L10n.tr("Bài viết này không còn khả dụng hoặc đã bị xóa."))
            return
        }

        // 6. Friend request / Friend accept / Follow -> open Profile
        if kind.contains("friend") || kind.contains("follow") {
            self.selectedProfileUser = item.actor
            return
        }

        // 7. Default: Actor profile
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

// MARK: - Dedicated Notification Post Detail View (Full PostCardView + Comments Parity)
struct NotificationPostDetailView: View {
    let post: PostItem
    var autoOpenComments: Bool = false

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var currentPost: PostItem
    @State private var comments: [CommentItem] = []
    @State private var commentText = ""
    @State private var isSubmittingComment = false
    @State private var showCommentsSheet = false
    @State private var didApplyAutoOpen = false
    @State private var selectedAuthor: KinnectUser? = nil
    @State private var isEditingPost = false
    @State private var editingPostText = ""
    @State private var showAudienceDialog = false
    @State private var showDeleteConfirm = false
    @State private var editingComment: CommentItem? = nil
    @State private var editingCommentText = ""
    @State private var pendingDeleteComment: CommentItem? = nil

    init(post: PostItem, autoOpenComments: Bool = false) {
        self.post = post
        self.autoOpenComments = autoOpenComments
        self._currentPost = State(initialValue: post)
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar.standard(
                title: L10n.tr("Chi tiết bài viết"),
                onBack: { dismiss() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PostCardView(
                        post: currentPost,
                        currentUserId: appState.currentUser?.id ?? "",
                        isAuthorOnline: appState.onlineUserIds.contains(currentPost.author.id),
                        onOpenAuthorProfile: {
                            if !currentPost.author.id.isEmpty {
                                selectedAuthor = currentPost.author
                            }
                        },
                        onReact: { reaction in
                            Task { await reactToPost(reaction) }
                        },
                        onOpenComments: {
                            showCommentsSheet = true
                        },
                        onEdit: {
                            editingPostText = currentPost.text
                            isEditingPost = true
                        },
                        onChangeAudience: {
                            showAudienceDialog = true
                        },
                        onHide: {
                            appState.showToast(L10n.tr("Đã ẩn bài viết."))
                            dismiss()
                        },
                        onDelete: {
                            showDeleteConfirm = true
                        },
                        onReport: {
                            appState.activeReportContext = UGCReportContext(
                                targetType: "post",
                                targetId: currentPost.id,
                                targetUserId: currentPost.author.id,
                                targetTitle: "\(L10n.tr("Bài viết của")) \(currentPost.author.name)"
                            )
                        },
                        onBookmark: {
                            Task { await toggleBookmark() }
                        },
                        onRepost: {
                            Task { await repost(quoteBody: "") }
                        },
                        onShareQuote: { quote in
                            Task { await repost(quoteBody: quote) }
                        }
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(L10n.tr("Bình luận")) (\(comments.count))")
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            Spacer()
                            Button {
                                showCommentsSheet = true
                            } label: {
                                Text(L10n.tr("Xem tất cả bình luận"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(KinnectTheme.accentBright)
                                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        if comments.isEmpty {
                            Text(L10n.tr("Chưa có bình luận nào. Hãy là người đầu tiên bình luận!"))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(comments) { comment in
                                    let name = comment.author.name.isEmpty ? L10n.tr("Thành viên") : comment.author.name
                                    let isMine = comment.author.id == (appState.currentUser?.id ?? "")

                                    HStack(alignment: .top, spacing: 10) {
                                        KinnectAvatarView(
                                            name: name,
                                            avatarURL: comment.author.avatarUrl,
                                            colorHex: comment.author.avatarColor,
                                            size: 32
                                        )
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(name)
                                                    .font(.caption.bold())
                                                    .foregroundColor(KinnectTheme.textPrimary)
                                                Spacer()
                                                 Menu {
                                                    if isMine {
                                                        Button(L10n.tr("Chỉnh sửa")) {
                                                            editingComment = comment
                                                            editingCommentText = comment.text
                                                        }
                                                        Button(L10n.tr("Xóa bình luận"), role: .destructive) {
                                                            pendingDeleteComment = comment
                                                        }
                                                    } else {
                                                        Button(L10n.tr("Báo cáo bình luận"), role: .destructive) {
                                                            appState.activeReportContext = UGCReportContext(
                                                                targetType: "comment",
                                                                targetId: comment.id,
                                                                targetUserId: comment.author.id,
                                                                targetTitle: "\(L10n.tr("Bình luận của")) \(name)"
                                                            )
                                                        }
                                                    }
                                                } label: {
                                                    Image(systemName: "ellipsis")
                                                        .font(.caption)
                                                        .foregroundColor(KinnectTheme.textSecondary)
                                                        .frame(minWidth: 44, minHeight: 44)
                                                        .contentShape(Rectangle())
                                                }
                                            }
                                            Text(comment.text)
                                                .font(.subheadline)
                                                .foregroundColor(KinnectTheme.textPrimary)
                                                .kinnectMultiline()
                                            if !isMine {
                                                HStack(spacing: 12) {
                                                    Button {
                                                        appState.activeReportContext = UGCReportContext(
                                                            targetType: "comment",
                                                            targetId: comment.id,
                                                            targetUserId: comment.author.id,
                                                            targetTitle: "\(L10n.tr("Bình luận của")) \(name)"
                                                        )
                                                    } label: {
                                                        Label(L10n.tr("Báo cáo"), systemImage: "flag")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundColor(KinnectTheme.textSecondary)
                                                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                                            .contentShape(Rectangle())
                                                    }
                                                    .buttonStyle(.plain)
                                                    Spacer()
                                                }
                                                .padding(.top, 2)
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                }
                            }
                        }
                    }
                    .padding(14)
                    .kinnectCard()
                }
                .padding(14)
            }
            .clipped()
            .refreshable {
                await refreshPostAndComments()
            }

            // Bottom Comment Input Bar
            let canSend = !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmittingComment
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $commentText,
                    prompt: Text(L10n.tr("Viết bình luận…"))
                        .foregroundColor(KinnectTheme.inputPlaceholder)
                )
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 20).fill(KinnectTheme.surfaceElevated))
                .foregroundColor(KinnectTheme.textPrimary)

                Button {
                    guard canSend else { return }
                    Task { await submitComment() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(canSend ? .white : KinnectTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(canSend ? KinnectTheme.accent : KinnectTheme.surfaceElevated))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSubmittingComment)
                .accessibilityLabel(L10n.tr("Gửi bình luận"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(KinnectTheme.surface.ignoresSafeArea(edges: .bottom))
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .task {
            await refreshPostAndComments()
            if autoOpenComments && !didApplyAutoOpen {
                didApplyAutoOpen = true
                showCommentsSheet = true
            }
        }
        .sheet(isPresented: $showCommentsSheet) {
            PostCommentsSheet(
                post: currentPost,
                onCountChanged: { count in
                    currentPost.commentsCount = count
                },
                onChanged: {
                    Task { await refreshPostAndComments() }
                }
            )
        }
        .fullScreenCover(item: $selectedAuthor) { author in
            ProfileView(targetUser: author)
        }
        .sheet(isPresented: $isEditingPost) {
            NavigationStack {
                VStack(spacing: 14) {
                    TextEditor(text: $editingPostText)
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    Spacer()
                }
                .padding()
                .background(KinnectTheme.background.ignoresSafeArea())
                .navigationTitle(L10n.tr("Chỉnh sửa bài viết"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.tr("Hủy")) { isEditingPost = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        let canSaveEdit = !editingPostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button(L10n.tr("Lưu")) {
                            guard canSaveEdit else { return }
                            Task { await saveEditedPost() }
                        }
                        .foregroundColor(canSaveEdit ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                    }
                }
            }
        }
        .sheet(item: $editingComment) { comment in
            NavigationStack {
                VStack(spacing: 14) {
                    TextEditor(text: $editingCommentText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    Spacer()
                }
                .padding()
                .background(KinnectTheme.background.ignoresSafeArea())
                .navigationTitle(L10n.tr("Chỉnh sửa bình luận"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.tr("Hủy")) { editingComment = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        let canSaveEdit = !editingCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        Button(L10n.tr("Lưu")) {
                            guard canSaveEdit else { return }
                            Task { await saveEditedComment(comment) }
                        }
                        .foregroundColor(canSaveEdit ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                    }
                }
            }
        }
        .kinnectActionSheet(
            isPresented: $showAudienceDialog,
            title: L10n.tr("Ai có thể xem bài viết này?"),
            items: [
                KinnectActionSheetItem(title: L10n.tr("Công khai"), glyph: .discover) {
                    Task { await changeAudience("public", title: L10n.tr("Công khai")) }
                },
                KinnectActionSheetItem(title: L10n.tr("Bạn bè"), glyph: .friends) {
                    Task { await changeAudience("friends", title: L10n.tr("Bạn bè")) }
                },
                KinnectActionSheetItem(title: L10n.tr("Chỉ mình tôi"), glyph: .lock) {
                    Task { await changeAudience("private", title: L10n.tr("Chỉ mình tôi")) }
                }
            ]
        )
        .alert(L10n.tr("Xóa bài viết?"), isPresented: $showDeleteConfirm) {
            Button(L10n.tr("Hủy"), role: .cancel) {}
            Button(L10n.tr("Xóa"), role: .destructive) {
                Task { await deletePost() }
            }
        } message: {
            Text(L10n.tr("Bài viết sẽ bị xóa vĩnh viễn và không thể khôi phục."))
        }
        .alert(L10n.tr("Xóa bình luận?"), isPresented: Binding(
            get: { pendingDeleteComment != nil },
            set: { if !$0 { pendingDeleteComment = nil } }
        )) {
            Button(L10n.tr("Hủy"), role: .cancel) { pendingDeleteComment = nil }
            Button(L10n.tr("Xóa"), role: .destructive) {
                if let target = pendingDeleteComment {
                    pendingDeleteComment = nil
                    Task { await deleteComment(target) }
                }
            }
        } message: {
            Text(L10n.tr("Bình luận này sẽ bị xóa vĩnh viễn."))
        }
    }

    private func refreshPostAndComments() async {
        async let postTask = KinnectAPIClient.shared.requestJSON("/api/posts?post=\(currentPost.id)")
        async let commentsTask = KinnectAPIClient.shared.requestJSON("/api/posts/\(currentPost.id)/comments")
        if let res = try? await postTask,
           let list = res["posts"] as? [[String: Any]],
           let first = list.first {
            currentPost = PostItem.from(first)
        }
        if let res = try? await commentsTask {
            let list = res["comments"] as? [[String: Any]] ?? []
            comments = list.map(CommentItem.from)
            currentPost.commentsCount = comments.count
        }
    }

    private func reactToPost(_ reaction: String) async {
        let remove = currentPost.liked && currentPost.userReaction == reaction
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(currentPost.id)/like",
                method: remove ? "DELETE" : "POST",
                body: remove ? [:] : ["reaction": reaction]
            )
            let nextLiked = (res["liked"] as? Bool) ?? !remove
            let nextLikes = (res["likes"] as? Int)
                ?? (res["likesCount"] as? Int)
                ?? max(0, currentPost.likesCount + (nextLiked ? (currentPost.liked ? 0 : 1) : (currentPost.liked ? -1 : 0)))
            let rawReaction = (res["myReaction"] as? String) ?? (res["userReaction"] as? String)
            currentPost.liked = nextLiked
            currentPost.likesCount = nextLikes
            currentPost.userReaction = nextLiked ? ((rawReaction?.isEmpty == false) ? rawReaction! : reaction) : ""
            if let rawRx = res["reactions"] as? [String: Any] {
                var updated: [String: Int] = [:]
                for (k, v) in rawRx {
                    if let n = v as? Int, n > 0 { updated[k] = n }
                    else if let n = (v as? NSNumber)?.intValue, n > 0 { updated[k] = n }
                }
                currentPost.reactions = updated
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func saveEditedPost() async {
        let trimmed = editingPostText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(currentPost.id)",
                method: "PATCH",
                body: ["body": editingPostText]
            )
            if let updated = res["post"] as? [String: Any] {
                currentPost = PostItem.from(updated)
            } else {
                currentPost.text = trimmed
            }
            isEditingPost = false
            appState.showToast(L10n.tr("Đã lưu bài viết!"))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func changeAudience(_ visibility: String, title: String) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(currentPost.id)",
                method: "PATCH",
                body: ["visibility": visibility]
            )
            currentPost.visibility = visibility
            appState.showToast("\(L10n.tr("Đã đổi đối tượng xem thành")) \(title).")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deletePost() async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON("/api/posts/\(currentPost.id)", method: "DELETE")
            appState.showToast(L10n.tr("Đã xóa bài viết."))
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func toggleBookmark() async {
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(currentPost.id)/bookmark",
                method: currentPost.bookmarked ? "DELETE" : "POST",
                body: currentPost.bookmarked ? nil : [:]
            )
            let saved = (res["bookmarked"] as? Bool) ?? !currentPost.bookmarked
            currentPost.bookmarked = saved
            appState.showToast(L10n.tr(saved ? "Đã lưu bài viết." : "Đã bỏ lưu bài viết."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func repost(quoteBody: String) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(currentPost.id)/share",
                method: "POST",
                body: ["body": quoteBody.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
            appState.showToast(L10n.tr("Đã chia sẻ bài viết lên bảng tin."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func saveEditedComment(_ comment: CommentItem) async {
        let trimmed = editingCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(currentPost.id)/comments/\(comment.id)",
                method: "PATCH",
                body: ["body": trimmed]
            )
            editingComment = nil
            await refreshPostAndComments()
            appState.showToast(L10n.tr("Đã cập nhật bình luận."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deleteComment(_ comment: CommentItem) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(currentPost.id)/comments/\(comment.id)",
                method: "DELETE"
            )
            await refreshPostAndComments()
            appState.showToast(L10n.tr("Đã xóa bình luận."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func submitComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSubmittingComment = true
        defer { isSubmittingComment = false }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(currentPost.id)/comments",
                method: "POST",
                body: ["body": text]
            )
            if res["id"] != nil || res["ok"] != nil || res["comment"] != nil {
                commentText = ""
                await refreshPostAndComments()
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
