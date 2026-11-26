import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FeedView: View {
    let onOpenCamera: () -> Void
    let onOpenFriends: () -> Void

    @ObservedObject private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var stories: [StoryItem] = []
    @State private var posts: [PostItem] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var hasMorePosts = false
    @State private var nextPostsCursor: Int64? = nil
    @State private var isLoadingMorePosts = false

    // Composer state
    @State private var showComposerSheet = false
    @State private var showCreateStorySheet = false
    @State private var activeStorySession: StorySession? = nil
    @State private var activeCommentPost: PostItem?
    @State private var editingPost: PostItem?
    @State private var editingPostText = ""
    @State private var audiencePost: PostItem?
    @State private var showAudienceDialog = false
    @State private var pendingDeletePost: PostItem? = nil
    @State private var hiddenPostIds: Set<String> = []
    @State private var selectedAuthorProfile: KinnectUser? = nil

    private struct StorySession: Identifiable {
        let id = UUID()
        let stories: [StoryItem]
        let initialIndex: Int
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                storiesStrip

                quickComposeRow

                if isLoading && posts.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        PostSkeletonCard()
                    }
                } else if let loadError, posts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text("Không thể tải bảng tin")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(loadError)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button {
                            Task { await loadFeedAndStories() }
                        } label: {
                            Text("Thử lại")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(KinnectTheme.primaryGradient))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 36)
                } else if visiblePosts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "newspaper.fill")
                            .font(.largeTitle)
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text("Chưa có bài viết nào")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.vertical, 36)
                } else {
                    ForEach(visiblePosts) { post in
                        PostCardView(
                            post: post,
                            currentUserId: appState.currentUser?.id ?? "",
                            isAuthorOnline: post.author.showActivity && (post.author.isActive || appState.onlineUserIds.contains(post.author.id)),
                            onOpenAuthorProfile: {
                                selectedAuthorProfile = post.author
                            },
                            onReact: { reaction in
                                Task { await toggleReaction(post: post, reaction: reaction) }
                            },
                            onOpenComments: {
                                activeCommentPost = post
                            },
                            onEdit: {
                                editingPost = post
                                editingPostText = post.text
                            },
                            onChangeAudience: {
                                audiencePost = post
                                showAudienceDialog = true
                            },
                            onHide: {
                                hiddenPostIds.insert(post.id)
                                appState.showToast("Đã ẩn bài viết.")
                            },
                            onDelete: {
                                pendingDeletePost = post
                            },
                            onReport: {
                                appState.activeReportContext = UGCReportContext(
                                    targetType: "post",
                                    targetId: post.id,
                                    targetUserId: post.author.id,
                                    targetTitle: "Bài viết của \(post.author.name)"
                                )
                            },
                            onBookmark: {
                                Task { await toggleBookmark(post: post) }
                            },
                            onRepost: {
                                Task { await repostToFeed(post: post, quoteBody: "") }
                            },
                            onShareQuote: { quote in
                                Task { await repostToFeed(post: post, quoteBody: quote) }
                            }
                        )
                    }
                    if hasMorePosts, nextPostsCursor != nil {
                        Button {
                            Task { await loadMorePosts() }
                        } label: {
                            HStack(spacing: 8) {
                                if isLoadingMorePosts { ProgressView() }
                                Text(isLoadingMorePosts ? "Đang tải…" : "Xem thêm bài viết")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
                        }
                        .disabled(isLoadingMorePosts)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .refreshable {
            await loadFeedAndStories()
        }
        .task {
            restoreCachedFeed()
            await loadFeedAndStories()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectContentModerated)) { _ in
            Task { await loadFeedAndStories() }
        }
        .fullScreenCover(isPresented: $showComposerSheet) {
            PostComposerSheet {
                Task { await loadFeedAndStories() }
            }
        }
        .sheet(isPresented: $showCreateStorySheet) {
            StoryComposerSheet {
                Task { await loadFeedAndStories() }
            }
        }
        .fullScreenCover(item: $activeStorySession) { session in
            StoryDetailSheet(
                stories: session.stories,
                initialIndex: session.initialIndex,
                onViewed: { viewedId in
                    if let idx = stories.firstIndex(where: { $0.id == viewedId }) {
                        stories[idx].viewed = true
                    }
                },
                onDeleted: { deletedId in
                    stories.removeAll { $0.id == deletedId }
                }
            )
        }
        .sheet(item: $activeCommentPost) { post in
            PostCommentsSheet(
                post: post,
                onCountChanged: { count in
                    if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                        posts[idx].commentsCount = count
                    }
                },
                onChanged: {}
            )
        }
        .sheet(item: $editingPost) { post in
            NavigationStack {
                VStack(spacing: 16) {
                    TextEditor(text: $editingPostText)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .frame(minHeight: 180)
                    Spacer()
                }
                .padding(16)
                .background(KinnectTheme.background.ignoresSafeArea())
                .navigationTitle("Chỉnh sửa bài viết")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Hủy") { editingPost = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lưu") {
                            Task {
                                do {
                                    let trimmed = editingPostText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let res = try await KinnectAPIClient.shared.requestJSON(
                                        "/api/posts/\(post.id)",
                                        method: "PATCH",
                                        body: ["body": editingPostText]
                                    )
                                    if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                                        if let updatedDict = res["post"] as? [String: Any] {
                                            posts[idx] = PostItem.from(updatedDict)
                                        } else {
                                            posts[idx].text = trimmed
                                        }
                                    }
                                    editingPost = nil
                                    appState.showToast("Đã lưu bài viết!")
                                } catch {
                                    appState.showToast(error.localizedDescription)
                                }
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Ai có thể xem bài viết?",
            isPresented: $showAudienceDialog,
            titleVisibility: .visible
        ) {
            if let p = audiencePost {
                Button("Mọi thành viên (Công khai)") {
                    Task {
                        await changeAudience(post: p, visibility: "public", title: "Mọi thành viên")
                    }
                }
                Button("Người theo dõi") {
                    Task {
                        await changeAudience(post: p, visibility: "followers", title: "Người theo dõi")
                    }
                }
                Button("Hủy", role: .cancel) {}
            }
        }
        .alert(
            "Xóa bài viết?",
            isPresented: Binding(
                get: { pendingDeletePost != nil },
                set: { if !$0 { pendingDeletePost = nil } }
            ),
            presenting: pendingDeletePost
        ) { post in
            Button("Xóa bài viết", role: .destructive) {
                pendingDeletePost = nil
                Task { await deletePost(post) }
            }
            Button("Hủy", role: .cancel) {
                pendingDeletePost = nil
            }
        } message: { _ in
            Text("Bài viết đã xóa sẽ không thể khôi phục.")
        }
        .fullScreenCover(item: $selectedAuthorProfile) { user in
            ProfileView(targetUser: user)
        }
    }

    private func changeAudience(post: PostItem, visibility: String, title: String) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)",
                method: "PATCH",
                body: ["visibility": visibility]
            )
            if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                posts[idx].visibility = visibility
            }
            appState.showToast("Đã đổi đối tượng xem thành \(title).")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private var visiblePosts: [PostItem] {
        posts.filter { post in
            guard !hiddenPostIds.contains(post.id) else { return false }
            guard !appState.blockedUserIds.contains(post.author.id) else { return false }
            return true
        }
    }

    private var isLargeDynamicType: Bool {
        dynamicTypeSize >= .xLarge
    }

    private var storyCellWidth: CGFloat {
        isLargeDynamicType ? 82 : 72
    }

    private var groupedStories: [(author: KinnectUser, stories: [StoryItem])] {
        let visible = stories.filter { !appState.blockedUserIds.contains($0.author.id) }
        var order: [String] = []
        var byAuthor: [String: [StoryItem]] = [:]
        for s in visible {
            let aid = s.author.id.isEmpty ? s.id : s.author.id
            if byAuthor[aid] == nil {
                order.append(aid)
                byAuthor[aid] = [s]
            } else {
                byAuthor[aid]?.append(s)
            }
        }
        return order.compactMap { aid in
            guard let list = byAuthor[aid], let first = list.first else { return nil }
            return (author: first.author, stories: list)
        }
    }

    private var storiesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Add Story Button
                Button {
                    showCreateStorySheet = true
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            KinnectAvatarView(
                                name: appState.currentUser?.name ?? "Tôi",
                                avatarURL: appState.currentUser?.avatarUrl ?? "",
                                colorHex: appState.currentUser?.avatarColor ?? "#7C3AED",
                                size: 58
                            )
                            Circle()
                                .fill(KinnectTheme.accentBright)
                                .frame(width: 22, height: 22)
                                .overlay(KinnectIcon(glyph: .add, size: 14, selected: true, tint: .white))
                        }
                        Text(L10n.tr("Tạo tin"))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: storyCellWidth)
                    }
                    .frame(width: storyCellWidth)
                }
                .accessibilityLabel("Tạo tin 24h mới")
                .accessibilityHint("Nhấn đúp để mở trình tạo tin")

                ForEach(groupedStories, id: \.author.id) { group in
                    let hasUnviewed = group.stories.contains { !$0.viewed }
                    Button {
                        let firstUnviewedIdx = group.stories.firstIndex(where: { !$0.viewed }) ?? 0
                        activeStorySession = StorySession(stories: group.stories, initialIndex: firstUnviewedIdx)
                    } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottomTrailing) {
                                ZStack {
                                    Circle()
                                        .stroke(
                                            !hasUnviewed
                                                ? LinearGradient(colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                                                : KinnectTheme.primaryGradient,
                                            lineWidth: 2.5
                                        )
                                        .frame(width: 62, height: 62)

                                    KinnectAvatarView(
                                        name: group.author.name,
                                        avatarURL: group.author.avatarUrl,
                                        colorHex: group.author.avatarColor,
                                        size: 54
                                    )
                                }
                                if group.stories.count > 1 {
                                    Text("\(group.stories.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(KinnectTheme.accentBright))
                                        .overlay(Capsule().stroke(KinnectTheme.surface, lineWidth: 1.5))
                                }
                            }
                            Text(shortStoryDisplayName(group.author.name))
                                .font(.caption2.weight(.medium))
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: storyCellWidth)
                        }
                        .frame(width: storyCellWidth)
                    }
                    .accessibilityLabel("Tin 24h của \(group.author.name)")
                    .accessibilityHint("Nhấn đúp để xem tin")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func shortStoryDisplayName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.split(separator: " ").map(String.init)
        if words.count >= 2 {
            return words.suffix(2).joined(separator: " ")
        }
        return cleaned.isEmpty ? "Kinnect" : cleaned
    }

    private var quickComposeRow: some View {
        Group {
            if isLargeDynamicType {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        KinnectAvatarView(
                            name: appState.currentUser?.name ?? "K",
                            avatarURL: appState.currentUser?.avatarUrl ?? "",
                            colorHex: appState.currentUser?.avatarColor ?? "#7C3AED",
                            size: 40
                        )
                        Spacer()
                        KinnectIconButton(
                            glyph: .camera,
                            label: "Mở Camera & Studio",
                            tint: KinnectTheme.accentBright,
                            action: onOpenCamera
                        )
                    }

                    Button {
                        showComposerSheet = true
                    } label: {
                        HStack {
                            Text("Bạn đang nghĩ gì?")
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                    }
                }
                .modifier(FeedCardStyle())
            } else {
                HStack(spacing: 10) {
                    KinnectAvatarView(
                        name: appState.currentUser?.name ?? "K",
                        avatarURL: appState.currentUser?.avatarUrl ?? "",
                        colorHex: appState.currentUser?.avatarColor ?? "#7C3AED",
                        size: 40
                    )

                    Button {
                        showComposerSheet = true
                    } label: {
                        HStack {
                            Text("Bạn đang nghĩ gì?")
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemGroupedBackground)))
                    }

                    KinnectIconButton(
                        glyph: .camera,
                        label: "Mở Camera & Studio",
                        tint: KinnectTheme.accentBright,
                        action: onOpenCamera
                    )
                }
                .modifier(FeedCardStyle())
            }
        }
    }

    private func restoreCachedFeed() {
        if posts.isEmpty, let accountId = appState.currentUser?.id,
           let cached: [[String: Any]] = AccountCache.shared.loadJSONObject(forKey: "feed_posts", accountId: accountId) {
            self.posts = cached.map(PostItem.from)
        }
        if posts.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/posts?limit=25"),
           let rawList = cached["posts"] as? [[String: Any]] {
            self.posts = rawList.map(PostItem.from)
        }
        if stories.isEmpty,
           let cachedStories = KinnectAPIClient.shared.cachedJSON(for: "/api/stories"),
           let rawStories = cachedStories["stories"] as? [[String: Any]] {
            self.stories = rawStories.map(StoryItem.from)
        }
    }

    private func loadFeedAndStories() async {
        restoreCachedFeed()
        isLoading = posts.isEmpty
        defer { isLoading = false }

        async let postsTask = KinnectAPIClient.shared.requestJSON("/api/posts?limit=25")
        async let storiesTask = KinnectAPIClient.shared.requestJSON("/api/stories")

        do {
            let postsRes = try await postsTask
            let rawList = postsRes["posts"] as? [[String: Any]] ?? []
            self.posts = rawList.map(PostItem.from)
            self.hasMorePosts = (postsRes["hasMore"] as? Bool) ?? false
            self.nextPostsCursor = (postsRes["nextCursor"] as? NSNumber)?.int64Value
            self.loadError = nil
            if let accountId = appState.currentUser?.id {
                AccountCache.shared.saveJSONObject(rawList, forKey: "feed_posts", accountId: accountId)
            }
        } catch {
            if self.posts.isEmpty {
                self.loadError = error.localizedDescription
            }
        }
        if let storiesRes = try? await storiesTask {
            let rawStories = storiesRes["stories"] as? [[String: Any]] ?? []
            self.stories = rawStories.map(StoryItem.from)
        }
    }

    private func loadMorePosts() async {
        guard hasMorePosts, let cursor = nextPostsCursor, !isLoadingMorePosts else { return }
        isLoadingMorePosts = true
        defer { isLoadingMorePosts = false }
        if let postsRes = try? await KinnectAPIClient.shared.requestJSON("/api/posts?limit=25&before=\(cursor)") {
            let more = (postsRes["posts"] as? [[String: Any]] ?? []).map(PostItem.from)
            let existing = Set(self.posts.map(\.id))
            self.posts.append(contentsOf: more.filter { !existing.contains($0.id) })
            self.hasMorePosts = (postsRes["hasMore"] as? Bool) ?? false
            self.nextPostsCursor = (postsRes["nextCursor"] as? NSNumber)?.int64Value
        }
    }

    private func toggleBookmark(post: PostItem) async {
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/bookmark",
                method: post.bookmarked ? "DELETE" : "POST",
                body: post.bookmarked ? nil : [:]
            )
            let saved = (res["bookmarked"] as? Bool) ?? !post.bookmarked
            if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                posts[idx].bookmarked = saved
            }
            appState.showToast(saved ? "Đã lưu bài viết." : "Đã bỏ lưu bài viết.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func repostToFeed(post: PostItem, quoteBody: String = "") async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/share",
                method: "POST",
                body: ["body": quoteBody.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
            appState.showToast("Đã chia sẻ bài viết lên bảng tin.")
            await loadFeedAndStories()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func toggleReaction(post: PostItem, reaction: String) async {
        let reqId = "react_\(post.id)_\(Int(Date().timeIntervalSince1970))"
        let removing = post.liked && post.userReaction == reaction
        do {
            let res: [String: Any]
            if removing {
                res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/like",
                    method: "DELETE",
                    body: [:],
                    requestId: reqId
                )
            } else {
                res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/like",
                    method: "POST",
                    body: ["reaction": reaction],
                    requestId: reqId
                )
            }
            if let idx = posts.firstIndex(where: { $0.id == post.id }) {
                let nextLiked = (res["liked"] as? Bool) ?? !removing
                let nextLikes = (res["likes"] as? Int)
                    ?? (res["likesCount"] as? Int)
                    ?? max(0, posts[idx].likesCount + (nextLiked ? (posts[idx].liked ? 0 : 1) : (posts[idx].liked ? -1 : 0)))
                let rawReaction = (res["myReaction"] as? String) ?? (res["userReaction"] as? String)
                posts[idx].liked = nextLiked
                posts[idx].likesCount = nextLikes
                posts[idx].userReaction = nextLiked ? ((rawReaction?.isEmpty == false) ? rawReaction! : reaction) : ""
                if let rawRx = res["reactions"] as? [String: Any] {
                    var updated: [String: Int] = [:]
                    for (k, v) in rawRx {
                        if let n = v as? Int, n > 0 { updated[k] = n }
                        else if let n = (v as? NSNumber)?.intValue, n > 0 { updated[k] = n }
                    }
                    posts[idx].reactions = updated
                }
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deletePost(_ post: PostItem) async {
        let reqId = "del_post_\(post.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            posts.removeAll { $0.id == post.id }
            let accountId = appState.currentUser?.id ?? KinnectAPIClient.shared.currentAccountId
            if !accountId.isEmpty {
                AccountCache.shared.evict(forKey: "feed_posts", origin: ServerConfig.currentOrigin, accountId: accountId)
                AccountCache.shared.evict(forKey: "json:/api/posts?limit=25", origin: KinnectAPIClient.shared.baseURL, accountId: accountId)
                if KinnectAPIClient.shared.baseURL != ServerConfig.currentOrigin {
                    AccountCache.shared.evict(forKey: "json:/api/posts?limit=25", origin: ServerConfig.currentOrigin, accountId: accountId)
                }
            }
            appState.showToast("Đã xóa bài viết.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

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
    var onBookmark: (() -> Void)? = nil
    var onRepost: (() -> Void)? = nil
    var onShareQuote: ((String) -> Void)? = nil

    private let reactionOptions: [(key: String, emoji: String, title: String)] = [
        ("like", "👍", "Thích"),
        ("love", "❤️", "Yêu thích"),
        ("haha", "😆", "Haha"),
        ("wow", "😮", "Wow"),
        ("sad", "😢", "Buồn"),
        ("angry", "😡", "Phẫn nộ")
    ]

    @State private var isBouncing = false
    #if DEBUG
    @State private var showReactionDock = ProcessInfo.processInfo.arguments.contains("--ui-review-reaction-dock")
    #else
    @State private var showReactionDock = false
    #endif
    @State private var showReactorsSheet = false
    @State private var showShareSheet = false

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
                            .lineLimit(1)
                            .truncationMode(.tail)
                        (Text("\(formatRelativeDate(post.createdAt)) · ")
                            + Text(Image(systemName: post.visibility == "followers" ? "person.2.fill" : "globe"))
                            + Text(" \(post.visibility == "followers" ? L10n.tr("Người theo dõi") : L10n.tr("Công khai"))"))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .layoutPriority(1)
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    if let onBookmark {
                        Button(action: onBookmark) {
                            Label(post.bookmarked ? "Bỏ lưu bài viết" : "Lưu bài viết", systemImage: post.bookmarked ? "bookmark.fill" : "bookmark")
                        }
                    }
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
                                Text(L10n.tr("Báo cáo / Chặn"))
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

            if !post.hashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(post.hashtags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.accentBright)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(KinnectTheme.accentBright.opacity(0.12)))
                        }
                    }
                }
            }

            if post.mediaItems.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.mediaItems) { item in
                            KinnectMediaTile(path: item.url, kind: item.kind, thumbnailUrl: item.thumbnail)
                                .frame(width: 240)
                        }
                    }
                }
            } else if !post.imageUrl.isEmpty {
                KinnectMediaTile(path: post.imageUrl, kind: post.mediaKind, thumbnailUrl: post.thumbnailUrl)
            }

            if let shared = post.sharedPost {
                VStack(alignment: .leading, spacing: 6) {
                    Text(shared.author.name)
                        .font(.caption.weight(.bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                    if !shared.text.isEmpty {
                        Text(shared.text)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    if !shared.imageUrl.isEmpty {
                        KinnectMediaTile(path: shared.imageUrl, kind: shared.mediaKind, thumbnailUrl: shared.thumbnailUrl)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(KinnectTheme.borderSoft, lineWidth: 1))
            }

            // Statistics Summary Row (Android parity: top-3 reactions + tappable ReactorsSheet)
            HStack {
                if post.likesCount > 0 {
                    Button {
                        showReactorsSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            HStack(spacing: -4) {
                                ForEach(Array(topThreeReactionKeys.enumerated()), id: \.offset) { _, key in
                                    Text(reactionEmoji(for: key))
                                        .font(.caption)
                                        .padding(2)
                                        .background(Circle().fill(KinnectTheme.surface))
                                }
                            }
                            Text("\(post.likesCount) \(L10n.tr("cảm xúc"))")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(post.likesCount) \(L10n.tr("cảm xúc")). \(L10n.tr("Chạm để xem danh sách"))")
                } else {
                    Text(L10n.tr("Chưa có cảm xúc"))
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }

                Spacer()

                Button(action: onOpenComments) {
                    Text("\(post.commentsCount) \(L10n.tr("bình luận"))")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .buttonStyle(.plain)
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

                // Column 3: Chia sẻ (Share Sheet: Quote-caption, Send to friend, Copy link, Bookmark, System share)
                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: 6) {
                        KinnectIcon(glyph: .share, size: 18, tint: KinnectTheme.textSecondary)
                        Text(post.sharesCount > 0 ? "\(L10n.tr("Chia sẻ")) (\(post.sharesCount))" : L10n.tr("Chia sẻ"))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Chia sẻ bài viết"))
            }
            .overlay(alignment: .topLeading) {
                if showReactionDock {
                    HStack(spacing: 6) {
                        ForEach(reactionOptions, id: \.key) { item in
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onReact(item.key)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                                    showReactionDock = false
                                }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(item.emoji)
                                        .font(.system(size: 24))
                                    Text(item.title)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            .shadow(color: Color.black.opacity(0.28), radius: 14, y: 5)
                            .overlay(Capsule().stroke(KinnectTheme.border, lineWidth: 1))
                    )
                    .offset(x: 0, y: -56)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity),
                        removal: .scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity)
                    ))
                    .zIndex(30)
                }
            }
        }
        .modifier(FeedCardStyle())
        .contentShape(Rectangle())
        .onTapGesture {
            if showReactionDock {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    showReactionDock = false
                }
            }
        }
        .zIndex(showReactionDock ? 25 : 0)
        .sheet(isPresented: $showReactorsSheet) {
            PostReactorsSheet(postId: post.id)
        }
        .sheet(isPresented: $showShareSheet) {
            PostShareSheet(
                post: post,
                shareURL: postShareURL,
                shareSubject: shareSubject,
                onBookmark: onBookmark,
                onShareToFeed: { quote in
                    if let onShareQuote {
                        onShareQuote(quote)
                    } else if quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let onRepost {
                        onRepost()
                    } else {
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/posts/\(post.id)/share",
                            method: "POST",
                            body: ["body": quote.trimmingCharacters(in: .whitespacesAndNewlines)]
                        )
                        AppState.shared.showToast(L10n.tr("Đã chia sẻ bài viết lên bảng tin."))
                    }
                }
            )
        }
    }

    private var topThreeReactionKeys: [String] {
        let sorted = post.reactions
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)
        if !sorted.isEmpty {
            return Array(sorted)
        }
        return [post.liked && !post.userReaction.isEmpty ? post.userReaction : "love"]
    }

    private var postShareURL: URL {
        URL(string: "https://app.kinnect.io.vn/share/post/\(post.id)")
            ?? URL(string: "https://app.kinnect.io.vn")!
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

struct PostReactorsSheet: View {
    let postId: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var reactors: [(user: KinnectUser, reaction: String)] = []
    @State private var selectedFilter: String = "all"
    @State private var isLoading = true
    @State private var selectedUser: KinnectUser? = nil

    private let reactionTabs: [(key: String, emoji: String, label: String)] = [
        ("all", "", "Tất cả"),
        ("like", "👍", "Thích"),
        ("love", "❤️", "Yêu thích"),
        ("haha", "😆", "Haha"),
        ("wow", "😮", "Wow"),
        ("sad", "😢", "Buồn"),
        ("angry", "😡", "Phẫn nộ")
    ]

    private var filteredReactors: [(user: KinnectUser, reaction: String)] {
        if selectedFilter == "all" { return reactors }
        return reactors.filter { $0.reaction == selectedFilter }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(reactionTabs, id: \.key) { tab in
                            let count = tab.key == "all" ? reactors.count : reactors.filter { $0.reaction == tab.key }.count
                            if tab.key == "all" || count > 0 {
                                Button {
                                    selectedFilter = tab.key
                                } label: {
                                    HStack(spacing: 4) {
                                        if !tab.emoji.isEmpty { Text(tab.emoji) }
                                        Text("\(L10n.tr(tab.label)) (\(count))")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(selectedFilter == tab.key ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                                    )
                                    .foregroundColor(selectedFilter == tab.key ? .white : KinnectTheme.textPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider().background(KinnectTheme.borderSoft)

                if isLoading {
                    Spacer()
                    ProgressView().tint(KinnectTheme.accentBright)
                    Spacer()
                } else if filteredReactors.isEmpty {
                    Spacer()
                    Text(L10n.tr("Chưa có lượt cảm xúc nào."))
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Spacer()
                } else {
                    List {
                        ForEach(filteredReactors, id: \.user.id) { entry in
                            Button {
                                selectedUser = entry.user
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack(alignment: .bottomTrailing) {
                                        KinnectAvatarView(user: entry.user, size: 42)
                                        Text(emoji(for: entry.reaction))
                                            .font(.system(size: 12))
                                            .padding(2)
                                            .background(Circle().fill(KinnectTheme.surface))
                                            .offset(x: 3, y: 3)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.user.name)
                                            .font(.subheadline.bold())
                                            .foregroundColor(KinnectTheme.textPrimary)
                                        if !entry.user.handle.isEmpty {
                                            Text("@\(entry.user.handle)")
                                                .font(.caption)
                                                .foregroundColor(KinnectTheme.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    KinnectIcon(glyph: .chevronRight, size: 16, tint: KinnectTheme.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(KinnectTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Người đã bày tỏ cảm xúc"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task { await loadReactors() }
            .fullScreenCover(item: $selectedUser) { user in
                ProfileView(targetUser: user)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func emoji(for key: String) -> String {
        reactionTabs.first(where: { $0.key == key })?.emoji ?? "👍"
    }

    private func loadReactors() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/posts/\(postId)/reactions")
            let users = res["users"] as? [[String: Any]] ?? []
            self.reactors = users.map { dict in
                let user = KinnectUser.from(dict)
                let rx = (dict["reaction"] as? String) ?? "like"
                return (user: user, reaction: rx)
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

private struct PostShareSheet: View {
    let post: PostItem
    let shareURL: URL
    let shareSubject: String
    let onBookmark: (() -> Void)?
    let onShareToFeed: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var quoteCaption = ""
    @State private var isSharing = false
    @State private var showForwardSheet = false

    private var forwardMessageText: String {
        let snippet = post.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if snippet.isEmpty {
            return "\(L10n.tr("Chia sẻ bài viết từ")) \(post.author.name): \(shareURL.absoluteString)"
        }
        return "\(post.author.name): \"\(snippet.prefix(140))\"\n\(shareURL.absoluteString)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if post.visibility == "public" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("Chia sẻ lên bảng tin của bạn"))
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)

                            TextField(L10n.tr("Nói gì đó về bài viết này (tùy chọn)…"), text: $quoteCaption, axis: .vertical)
                                .lineLimit(2...5)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.textPrimary)

                            Button {
                                Task {
                                    isSharing = true
                                    defer { isSharing = false }
                                    await onShareToFeed(quoteCaption)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isSharing {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "arrow.2.squarepath")
                                    }
                                    Text(L10n.tr("Chia sẻ lên bảng tin"))
                                        .font(.subheadline.bold())
                                }
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.primaryGradient))
                                .foregroundColor(.white)
                            }
                            .disabled(isSharing)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(KinnectTheme.surface))
                    }

                    VStack(spacing: 0) {
                        Button {
                            showForwardSheet = true
                        } label: {
                            shareActionRow(icon: "paperplane.fill", title: L10n.tr("Gửi cho bạn bè"))
                        }
                        .buttonStyle(.plain)

                        Divider().background(KinnectTheme.borderSoft)

                        Button {
                            UIPasteboard.general.string = shareURL.absoluteString
                            appState.showToast(L10n.tr("Đã sao chép liên kết bài viết!"))
                            dismiss()
                        } label: {
                            shareActionRow(icon: "link", title: L10n.tr("Sao chép liên kết"))
                        }
                        .buttonStyle(.plain)

                        if let onBookmark {
                            Divider().background(KinnectTheme.borderSoft)
                            Button {
                                onBookmark()
                                dismiss()
                            } label: {
                                shareActionRow(
                                    icon: post.bookmarked ? "bookmark.fill" : "bookmark",
                                    title: L10n.tr(post.bookmarked ? "Bỏ lưu bài viết" : "Lưu bài viết")
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Divider().background(KinnectTheme.borderSoft)

                        ShareLink(
                            item: shareURL,
                            subject: Text(shareSubject),
                            message: Text(post.text.isEmpty ? L10n.tr("Xem bài viết trên Kinnect") : post.text)
                        ) {
                            shareActionRow(icon: "square.and.arrow.up", title: L10n.tr("Chia sẻ liên kết ngoài"))
                        }
                        .buttonStyle(.plain)
                    }
                    .background(RoundedRectangle(cornerRadius: 16).fill(KinnectTheme.surface))
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Chia sẻ bài viết"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
            .sheet(isPresented: $showForwardSheet) {
                ForwardMessageSheet(text: forwardMessageText, imageUrl: post.imageUrl)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func shareActionRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(KinnectTheme.accentBright)
                .frame(width: 32, height: 32)
                .background(Circle().fill(KinnectTheme.accentSoft))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(KinnectTheme.textPrimary)
            Spacer()
            KinnectIcon(glyph: .chevronRight, size: 15, tint: KinnectTheme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct PostComposerSheet: View {
    let onPosted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var text = ""
    @State private var visibility = "public"
    @State private var photo: PhotosPickerItem?
    @State private var video: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var videoURL: URL?
    @State private var mediaDataURL = ""
    @State private var isSubmitting = false
    @State private var loadingMedia = false
    @State private var showCamera = false
    @State private var showMusic = false
    @State private var musicTitle = ""
    @State private var musicURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        KinnectAvatarView(name: appState.currentUser?.name ?? "Bạn",
                            avatarURL: appState.currentUser?.avatarUrl ?? "",
                            colorHex: appState.currentUser?.avatarColor ?? "#7C3AED", size: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appState.currentUser?.name ?? "Bạn").font(.headline)
                            Menu {
                                Button("Mọi thành viên") { visibility = "public" }
                                Button("Người theo dõi") { visibility = "followers" }
                            } label: {
                                Label(visibility == "public" ? "Mọi thành viên" : "Người theo dõi",
                                      systemImage: visibility == "public" ? "globe" : "person.2")
                                    .font(.caption.bold())
                            }
                        }
                        Spacer()
                    }
                    TextField("Bạn đang nghĩ gì?", text: $text, axis: .vertical)
                        .font(.system(size: 18)).lineLimit(6...16)
                        .onChange(of: text) { value in if value.count > 2000 { text = String(value.prefix(2000)) } }
                    if loadingMedia { ProgressView("Đang chuẩn bị media…") }
                    if let previewImage {
                        Image(uiImage: previewImage).resizable().scaledToFit().frame(maxHeight: 360)
                    }
                    if let videoURL {
                        ShortClipPlayer(path: videoURL.absoluteString, active: true).frame(height: 320)
                        Button { showMusic = true } label: {
                            Label(musicTitle.isEmpty ? "Thêm nhạc" : musicTitle, systemImage: "music.note")
                        }
                    }
                    if !mediaDataURL.isEmpty || videoURL != nil {
                        Button("Gỡ media", role: .destructive) {
                            cleanupTempFile(videoURL)
                            previewImage = nil; videoURL = nil; mediaDataURL = ""
                            musicTitle = ""; musicURL = nil; photo = nil; video = nil
                        }
                    }
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 0) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Ảnh", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 52)
                    }
                    PhotosPicker(selection: $video, matching: .videos) {
                        Label("Video", systemImage: "video").frame(maxWidth: .infinity, minHeight: 52)
                    }
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                        else { appState.showToast("Thiết bị chưa có camera khả dụng.") }
                    } label: {
                        Label("Chụp/quay", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 52)
                    }
                }
                .font(.subheadline).background(KinnectTheme.surfaceElevated)
                .disabled(loadingMedia || isSubmitting)
            }
            .navigationTitle("Bài viết mới").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Đóng")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Đang đăng…" : "Đăng") { Task { await submitPost() } }
                        .font(.subheadline.bold())
                        .disabled(isSubmitting || loadingMedia || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaDataURL.isEmpty && videoURL == nil))
                }
            }
        }
        .onChange(of: photo) { item in
            guard let item else { return }
            Task {
                loadingMedia = true
                defer { loadingMedia = false }
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    useImage(image)
                } else { appState.showToast("Không đọc được ảnh đã chọn.") }
            }
        }
        .onChange(of: video) { item in
            guard let item else { return }
            Task { @MainActor in
                loadingMedia = true
                defer {
                    loadingMedia = false
                    video = nil
                }
                do {
                    guard let pickedMovie = try await item.loadTransferable(type: PickedMovieFile.self) else {
                        appState.showToast("Không đọc được video đã chọn.")
                        return
                    }
                    cleanupTempFile(videoURL)
                    videoURL = pickedMovie.url
                    previewImage = nil
                    mediaDataURL = ""
                } catch {
                    appState.showToast(error.localizedDescription)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            KinnectComposerCamera { image, movie in
                if let image { useImage(image) }
                if let movie {
                    cleanupTempFile(videoURL)
                    videoURL = movie; previewImage = nil; mediaDataURL = ""
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showMusic) {
            NavigationStack {
                StudioMusicPickerSheet(selectedTrack: $musicTitle) { title, url in
                    musicTitle = title; musicURL = url
                }
            }
        }
        .onDisappear {
            cleanupTempFile(videoURL)
            videoURL = nil
        }
    }

    private func cleanupTempFile(_ url: URL?) {
        guard let url, url.isFileURL else { return }
        let tempPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(tempPath) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func useImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.72), data.count <= 20 * 1024 * 1024 else {
            appState.showToast("Ảnh vượt quá giới hạn 20 MB."); return
        }
        cleanupTempFile(videoURL)
        previewImage = image; videoURL = nil
        mediaDataURL = "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    private func submitPost() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            var media = mediaDataURL
            if let videoURL {
                let project = StudioVideoProject(sourceURL: videoURL)
                project.musicURL = musicURL; project.musicTitle = musicTitle
                let output = try await project.exportVideo()
                defer { cleanupTempFile(output) }
                let data = try Data(contentsOf: output)
                guard data.count <= 20 * 1024 * 1024 else {
                    appState.showToast("Video vượt quá giới hạn 20 MB."); return
                }
                media = "data:video/mp4;base64,\(data.base64EncodedString())"
            }
            _ = try await KinnectAPIClient.shared.requestJSON("/api/posts", method: "POST",
                body: KinnectWriteBody.post(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                           visibility: visibility, mediaDataURL: media),
                requestId: "post_\(UUID().uuidString)")
            cleanupTempFile(videoURL)
            videoURL = nil
            onPosted(); dismiss()
        } catch { appState.showToast(error.localizedDescription) }
    }
}

struct StoryMusicTrack: Identifiable {
    let id: String
    let title: String
    let artist: String
}

struct StoryComposerSheet: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var text = ""
    @State private var backgroundColor = "#7C3AED"
    @State private var selectedMediaItem: PhotosPickerItem?
    @State private var imageDataURL = ""
    @State private var previewImage: UIImage?
    @State private var selectedVideoName: String?
    @State private var selectedMusic: StoryMusicTrack?
    @State private var showMusicSheet = false
    @State private var isSubmitting = false

    private let colors = ["#7C3AED", "#EC4899", "#2563EB", "#059669", "#D97706"]
    @State private var storyMusicTitle = ""
    @State private var storyMusicURL: URL?
    @State private var storyVideoURL: URL?
    @State private var storyMediaLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Two prominent creation tiles (100% Android parity MainActivity lines 6140-6152: "Quay tin" & "Ảnh kèm nhạc")
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedMediaItem, matching: .videos) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                                Text("Quay tin")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text("Camera · Nhạc · Hiệu ứng")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0x83 / 255.0, green: 0x54 / 255.0, blue: 0xEF / 255.0), Color(red: 0xD9 / 255.0, green: 0x4C / 255.0, blue: 0xAE / 255.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }

                        PhotosPicker(selection: $selectedMediaItem, matching: .images) {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "photo.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                                Text("Ảnh kèm nhạc")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text("Chọn ảnh · thêm bài hát")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0x39 / 255.0, green: 0x7B / 255.0, blue: 0xE9 / 255.0), Color(red: 0x72 / 255.0, green: 0x4E / 255.0, blue: 0xE5 / 255.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }

                    // 24-hour visibility note (Android line 6154 parity)
                    Text("Tin hiển thị 24 giờ cho những người theo dõi bạn.")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    // Main Story Canvas Preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hex: backgroundColor))
                            .frame(height: 280)

                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        }

                        if let storyVideoURL {
                            ShortClipPlayer(path: storyVideoURL.absoluteString, active: true).frame(height: 280)
                        } else if let videoName = selectedVideoName {
                            VStack(spacing: 8) {
                                Image(systemName: "video.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                                Text(videoName)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.black.opacity(0.5)))
                            }
                        }

                        // Music overlay badge
                        if let music = selectedMusic {
                            VStack {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "music.note")
                                            .font(.caption.bold())
                                        Text(music.artist.isEmpty ? music.title : "\(music.title) — \(music.artist)")
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Button {
                                            selectedMusic = nil
                                            storyMusicTitle = ""
                                            storyMusicURL = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.black.opacity(0.65)))
                                    .foregroundColor(.white)

                                    Spacer()
                                }
                                .padding(12)
                                Spacer()
                            }
                        }

                        TextField("Nhập nội dung tin 24h...", text: $text, axis: .vertical)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .padding(20)
                            .background(previewImage != nil || selectedVideoName != nil ? Color.black.opacity(0.4) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Color Palette Selector
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: backgroundColor == hex ? 3 : 0)
                                )
                                .onTapGesture {
                                    backgroundColor = hex
                                }
                        }
                    }

                    Button { showMusicSheet = true } label: {
                        Label(storyMusicTitle.isEmpty ? "Thêm nhạc" : storyMusicTitle, systemImage: "music.note")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(isSubmitting || storyMediaLoading)
                    if storyMediaLoading { ProgressView("Đang chuẩn bị media…") }

                    // Photo/Video Picker Button
                    PhotosPicker(selection: $selectedMediaItem, matching: .any(of: [.images, .videos])) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Chọn ảnh hoặc video từ máy")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.accentBright)
                    }
                    .onChange(of: selectedMediaItem) { item in
                        guard let item else { return }
                        Task { @MainActor in
                            storyMediaLoading = true
                            defer {
                                storyMediaLoading = false
                                selectedMediaItem = nil
                            }
                            let isMovieItem = item.supportedContentTypes.contains {
                                $0.conforms(to: .movie) || $0.conforms(to: .video)
                            }
                            if isMovieItem {
                                do {
                                    guard let pickedMovie = try await item.loadTransferable(type: PickedMovieFile.self) else {
                                        appState.showToast("Không đọc được tệp video đã chọn.")
                                        return
                                    }
                                    let fileSizeBytes = ((try? FileManager.default.attributesOfItem(atPath: pickedMovie.url.path)[.size]) as? NSNumber)?.int64Value ?? 0
                                    cleanupTempFile(storyVideoURL)
                                    storyVideoURL = pickedMovie.url
                                    previewImage = nil
                                    imageDataURL = ""
                                    selectedVideoName = "Đã chọn video 24h (\(max(1, Int(fileSizeBytes / 1024 / 1024))) MB)"
                                } catch {
                                    appState.showToast(error.localizedDescription)
                                }
                                return
                            }

                            do {
                                if let data = try await item.loadTransferable(type: Data.self),
                                   let uiImg = UIImage(data: data),
                                   let jpeg = uiImg.jpegData(compressionQuality: 0.72) {
                                    guard jpeg.count <= 20 * 1024 * 1024 else {
                                        appState.showToast("Ảnh vượt quá giới hạn 20 MB.")
                                        return
                                    }
                                    cleanupTempFile(storyVideoURL)
                                    previewImage = uiImg
                                    selectedVideoName = nil
                                    storyVideoURL = nil
                                    imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                                    return
                                }
                                if let pickedMovie = try await item.loadTransferable(type: PickedMovieFile.self) {
                                    let fileSizeBytes = ((try? FileManager.default.attributesOfItem(atPath: pickedMovie.url.path)[.size]) as? NSNumber)?.int64Value ?? 0
                                    cleanupTempFile(storyVideoURL)
                                    storyVideoURL = pickedMovie.url
                                    previewImage = nil
                                    imageDataURL = ""
                                    selectedVideoName = "Đã chọn video 24h (\(max(1, Int(fileSizeBytes / 1024 / 1024))) MB)"
                                    return
                                }
                                appState.showToast("Không đọc được ảnh hoặc video đã chọn.")
                            } catch {
                                appState.showToast(error.localizedDescription)
                            }
                        }
                    }

                    Button {
                        Task { await createStory() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Đăng tin 24h")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(KinnectTheme.primaryGradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSubmitting || storyMediaLoading || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageDataURL.isEmpty && storyVideoURL == nil))
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Tạo tin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .sheet(isPresented: $showMusicSheet) {
                NavigationStack {
                    StudioMusicPickerSheet(selectedTrack: $storyMusicTitle) { title, url in
                        selectedMusic = title.isEmpty ? nil : StoryMusicTrack(id: url?.absoluteString ?? title, title: title, artist: "")
                        storyMusicTitle = title
                        storyMusicURL = url
                    }
                }
            }
            .onDisappear {
                cleanupTempFile(storyVideoURL)
                storyVideoURL = nil
            }
        }
    }

    private func cleanupTempFile(_ url: URL?) {
        guard let url, url.isFileURL else { return }
        let tempPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(tempPath) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func createStory() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let reqId = "story_\(UUID().uuidString)"
        do {
            var media = imageDataURL
            var generatedStillURL: URL? = nil
            defer { cleanupTempFile(generatedStillURL) }
            let source: URL?
            if let storyVideoURL { source = storyVideoURL }
            else if storyMusicURL != nil, let previewImage {
                let still = try await KinnectStillVideo.make(image: previewImage)
                generatedStillURL = still
                source = still
            }
            else { source = nil }
            if storyMusicURL != nil && source == nil {
                throw KinnectAPIError.serverMessage("Chọn ảnh hoặc video để ghép nhạc.")
            }
            if let source {
                let project = StudioVideoProject(sourceURL: source)
                project.musicURL = storyMusicURL
                let output = try await project.exportVideo()
                defer { cleanupTempFile(output) }
                let data = try Data(contentsOf: output)
                guard data.count <= 20 * 1024 * 1024 else { throw KinnectAPIError.serverMessage("Tin vượt quá giới hạn 20 MB.") }
                media = "data:video/mp4;base64,\(data.base64EncodedString())"
            }
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/stories",
                method: "POST",
                body: KinnectWriteBody.story(
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    colorHex: backgroundColor,
                    mediaDataURL: media
                ),
                requestId: reqId
            )
            cleanupTempFile(storyVideoURL)
            storyVideoURL = nil
            onCreated()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct StoryDetailSheet: View {
    var onViewed: ((String) -> Void)? = nil
    var onDeleted: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var storyItems: [StoryItem]
    @State private var currentIndex: Int
    @State private var progress: Double = 0.0
    @State private var isHolding: Bool = false
    @State private var showViewersSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var isDeleting: Bool = false
    @State private var viewersByStory: [String: [KinnectUser]] = [:]

    private let storyDurationSeconds: Double = 6.0

    init(
        stories: [StoryItem],
        initialIndex: Int = 0,
        onViewed: ((String) -> Void)? = nil,
        onDeleted: ((String) -> Void)? = nil
    ) {
        self._storyItems = State(initialValue: stories)
        let clamped = stories.isEmpty ? 0 : min(max(0, initialIndex), stories.count - 1)
        self._currentIndex = State(initialValue: clamped)
        self.onViewed = onViewed
        self.onDeleted = onDeleted
    }

    init(story: StoryItem) {
        self.init(stories: [story], initialIndex: 0)
    }

    private var currentStory: StoryItem? {
        guard !storyItems.isEmpty, currentIndex >= 0, currentIndex < storyItems.count else { return nil }
        return storyItems[currentIndex]
    }

    private var currentViewers: [KinnectUser] {
        guard let story = currentStory else { return [] }
        return viewersByStory[story.id] ?? []
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = currentStory {
                let isOwner = story.author.id == appState.currentUser?.id
                let isVideoStory = story.mediaKind.lowercased().contains("video")
                    || story.imageUrl.lowercased().contains(".mp4")

                ZStack {
                    // Full-bleed edge-to-edge background canvas
                    Color(hex: story.backgroundColor)
                        .ignoresSafeArea()

                    if !story.imageUrl.isEmpty {
                        if isVideoStory {
                            ShortClipPlayer(
                                path: story.imageUrl,
                                active: !isHolding && !showViewersSheet && !showDeleteConfirm && !isDeleting,
                                muted: false
                            )
                            .ignoresSafeArea()
                        } else {
                            GeometryReader { mediaGeo in
                                KinnectRemoteImageView(
                                    rawURL: story.imageUrl,
                                    contentMode: .fill,
                                    cornerRadius: 0,
                                    maxHeight: mediaGeo.size.height
                                )
                                .frame(width: mediaGeo.size.width, height: mediaGeo.size.height)
                                .clipped()
                            }
                            .ignoresSafeArea()
                        }
                    }

                    // Top & bottom scrim gradients so white HUD controls stay crisp
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.62),
                            Color.clear,
                            Color.clear,
                            Color.black.opacity(0.68)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    // Prev / Next tap overlay + hold-to-pause
                    GeometryReader { tapGeo in
                        HStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: tapGeo.size.width * 0.35)
                                .onTapGesture {
                                    goPreviousStory()
                                }
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(width: tapGeo.size.width * 0.65)
                                .onTapGesture {
                                    goNextStory()
                                }
                        }
                    }
                    .ignoresSafeArea()
                    .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 30, pressing: { pressing in
                        isHolding = pressing
                    }, perform: {})

                    // Foreground HUD inside safe area
                    VStack(spacing: 12) {
                        storyProgressBars

                        storyTopHeader(story: story, isOwner: isOwner)

                        Spacer()

                        if !story.text.isEmpty {
                            Text(story.text)
                                .font(.title3.bold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .kinnectMultiline()
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.black.opacity(story.imageUrl.isEmpty ? 0.18 : 0.48))
                                )
                                .padding(.horizontal, 16)
                                .allowsHitTesting(false)
                        }

                        Spacer()

                        if isOwner {
                            Button {
                                showViewersSheet = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "eye.fill")
                                        .foregroundColor(.white)
                                    Text("\(L10n.tr("Người đã xem")) (\(max(story.viewsCount, currentViewers.count)))")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundColor(.white.opacity(0.75))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.45))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .task(id: story.id) {
                    progress = 0.0
                    await recordViewOrFetchViewers(for: story)
                }
                .task(id: "timer_\(story.id)_\(currentIndex)") {
                    let tickSeconds = 0.05
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        guard !Task.isCancelled else { return }
                        if isHolding || showViewersSheet || showDeleteConfirm || isDeleting {
                            continue
                        }
                        progress += tickSeconds / storyDurationSeconds
                        if progress >= 1.0 {
                            goNextStory()
                            return
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showViewersSheet) {
            NavigationStack {
                List {
                    if currentViewers.isEmpty {
                        Text(L10n.tr("Chưa có người xem tin này."))
                            .foregroundColor(KinnectTheme.textSecondary)
                            .listRowBackground(KinnectTheme.surface)
                    } else {
                        ForEach(currentViewers) { viewer in
                            HStack(spacing: 10) {
                                KinnectAvatarView(user: viewer, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewer.name)
                                        .font(.subheadline.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                    if !viewer.handle.isEmpty {
                                        Text("@\(viewer.handle)")
                                            .font(.caption)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                    }
                                }
                            }
                            .listRowBackground(KinnectTheme.surface)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(KinnectTheme.background)
                .navigationTitle(L10n.tr("Người đã xem"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.tr("Đóng")) { showViewersSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert(L10n.tr("Xóa tin 24h?"), isPresented: $showDeleteConfirm) {
            Button(L10n.tr("Xóa tin"), role: .destructive) {
                if let story = currentStory {
                    Task { await deleteStory(story) }
                }
            }
            Button(L10n.tr("Hủy"), role: .cancel) {}
        } message: {
            Text(L10n.tr("Tin đã xóa sẽ không thể khôi phục."))
        }
    }

    private var storyProgressBars: some View {
        HStack(spacing: 4) {
            ForEach(Array(storyItems.enumerated()), id: \.element.id) { idx, _ in
                GeometryReader { barGeo in
                    let fillRatio: Double = idx < currentIndex ? 1.0 : (idx == currentIndex ? progress : 0.0)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.32))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(0, barGeo.size.width * min(1.0, max(0.0, fillRatio))))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func storyTopHeader(story: StoryItem, isOwner: Bool) -> some View {
        HStack(spacing: 10) {
            KinnectAvatarView(
                name: story.author.name,
                avatarURL: story.author.avatarUrl,
                colorHex: story.author.avatarColor,
                size: 38
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(story.author.name)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                if isOwner {
                    Text("\(L10n.tr("Lượt xem:")) \(max(story.viewsCount, currentViewers.count))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(1)
                } else if !story.createdAt.isEmpty {
                    Text(formatRelativeDate(story.createdAt))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if isOwner {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .accessibilityLabel(L10n.tr("Xóa tin"))
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Đóng"))
        }
    }

    private func goPreviousStory() {
        if currentIndex > 0 {
            currentIndex -= 1
            progress = 0.0
        } else {
            progress = 0.0
        }
    }

    private func goNextStory() {
        if currentIndex + 1 < storyItems.count {
            currentIndex += 1
            progress = 0.0
        } else {
            dismiss()
        }
    }

    private func recordViewOrFetchViewers(for story: StoryItem) async {
        let isOwner = story.author.id == appState.currentUser?.id
        if isOwner {
            if let res = try? await KinnectAPIClient.shared.requestJSON("/api/stories/\(story.id)/viewers") {
                let raw = res["viewers"] as? [[String: Any]] ?? []
                viewersByStory[story.id] = raw.map { dict in
                    if let u = dict["user"] as? [String: Any] {
                        return KinnectUser.from(u)
                    }
                    return KinnectUser.from(dict)
                }
            }
        } else {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/stories/\(story.id)/view",
                method: "POST",
                body: [:],
                requestId: "view_story_\(story.id)"
            )
            onViewed?(story.id)
        }
    }

    private func deleteStory(_ story: StoryItem) async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(story.id)",
                method: "DELETE",
                body: [:],
                requestId: "del_story_\(story.id)"
            )
            onDeleted?(story.id)
            storyItems.removeAll { $0.id == story.id }
            appState.showToast(L10n.tr("Đã xóa tin 24h."))
            if storyItems.isEmpty {
                dismiss()
            } else {
                currentIndex = min(currentIndex, storyItems.count - 1)
                progress = 0.0
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct PostCommentsSheet: View {
    let post: PostItem
    var onCountChanged: ((Int) -> Void)? = nil
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var comments: [CommentItem] = []
    @State private var newComment = ""
    @State private var pendingCommentReactions: Set<String> = []
    @State private var reactionPickerCommentId: String? = nil
    @State private var replyingTo: CommentItem? = nil
    @State private var editingComment: CommentItem? = nil
    @State private var editingCommentText = ""
    @State private var pendingDeleteComment: CommentItem? = nil
    @State private var isLoading = false

    private let quickEmojis = ["😍", "😂", "🔥", "👏", "🥰", "😮", "😢", "💜"]

    private let commentReactionOptions: [(key: String, emoji: String, title: String)] = [
        ("like", "👍", "Thích"),
        ("love", "❤️", "Yêu thích"),
        ("haha", "😆", "Haha"),
        ("wow", "😮", "Wow"),
        ("sad", "😢", "Buồn"),
        ("angry", "😡", "Phẫn nộ")
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
                if comments.isEmpty && !isLoading {
                    VStack(spacing: 8) {
                        Spacer()
                        KinnectIcon(glyph: .comment, size: 36, tint: KinnectTheme.textSecondary)
                        Text("Chưa có bình luận nào")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Hãy là người đầu tiên để lại bình luận!")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(commentRows) { row in
                                VStack(spacing: 0) {
                                    commentRowView(row.comment, depth: min(row.depth, 1), parentAuthorName: row.parentAuthorName)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(KinnectTheme.surface)
                                    Divider()
                                        .background(KinnectTheme.borderSoft)
                                }
                                .zIndex(reactionPickerCommentId == row.comment.id ? 25 : 0)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .background(KinnectTheme.background)
                    .onTapGesture {
                        if reactionPickerCommentId != nil {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                reactionPickerCommentId = nil
                            }
                        }
                    }
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
                    TextField(
                        "",
                        text: $newComment,
                        prompt: Text(replyingTo != nil ? "Trả lời \(replyingTo!.author.name)..." : "Viết bình luận...")
                            .foregroundColor(KinnectTheme.textSecondary)
                    )
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)

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
            .alert(
                L10n.tr("Xóa bình luận?"),
                isPresented: Binding(
                    get: { pendingDeleteComment != nil },
                    set: { if !$0 { pendingDeleteComment = nil } }
                ),
                presenting: pendingDeleteComment
            ) { comment in
                Button(L10n.tr("Xóa"), role: .destructive) {
                    pendingDeleteComment = nil
                    Task { await deleteComment(comment) }
                }
                Button(L10n.tr("Hủy"), role: .cancel) {
                    pendingDeleteComment = nil
                }
            } message: { _ in
                Text(L10n.tr("Bình luận đã xóa sẽ không thể khôi phục."))
            }
            .sheet(item: $editingComment) { comment in
                NavigationStack {
                    VStack(spacing: 16) {
                        TextEditor(text: $editingCommentText)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .frame(minHeight: 140)
                        Spacer()
                    }
                    .padding(16)
                    .background(KinnectTheme.background.ignoresSafeArea())
                    .navigationTitle(L10n.tr("Chỉnh sửa bình luận"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.tr("Hủy")) { editingComment = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.tr("Lưu")) {
                                Task { await saveEditedComment(comment) }
                            }
                            .disabled(editingCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
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
                        Menu {
                            Button {
                                editingComment = c
                                editingCommentText = c.text
                            } label: {
                                Label(L10n.tr("Chỉnh sửa"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                pendingDeleteComment = c
                            } label: {
                                Label(L10n.tr("Xóa bình luận"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .frame(minWidth: 32, minHeight: 32)
                                .contentShape(Rectangle())
                        }
                    } else {
                        Menu {
                            Button(role: .destructive) {
                                appState.activeReportContext = UGCReportContext(
                                    targetType: "comment",
                                    targetId: c.id,
                                    targetUserId: c.author.id,
                                    targetTitle: "\(L10n.tr("Bình luận của")) \(c.author.name)"
                                )
                            } label: {
                                Label(L10n.tr("Báo cáo bình luận"), systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .frame(minWidth: 32, minHeight: 32)
                                .contentShape(Rectangle())
                        }
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
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            reactionPickerCommentId = (reactionPickerCommentId == c.id) ? nil : c.id
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if let matched = commentReactionOptions.first(where: { $0.key == c.myReaction }) {
                                Text(matched.emoji)
                                    .font(.caption)
                                Text(matched.title)
                                    .font(.caption2.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            } else {
                                Text("👍")
                                    .font(.caption)
                                Text("Cảm xúc")
                                    .font(.caption2.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            if c.likesCount > 0 {
                                Text("· \(c.likesCount)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(c.liked ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
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
                            Button("Gỡ cảm xúc", role: .destructive) {
                                setCommentReaction(c, reaction: nil)
                            }
                        }
                    }
                    .accessibilityLabel("Cảm xúc bình luận")
                    .accessibilityHint("Chạm để mở bảng cảm xúc cho bình luận này")

                    Text(formatRelativeDate(c.createdAt))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)

                    if c.author.id != (appState.currentUser?.id ?? "") {
                        Button {
                            appState.activeReportContext = UGCReportContext(
                                targetType: "comment",
                                targetId: c.id,
                                targetUserId: c.author.id,
                                targetTitle: "\(L10n.tr("Bình luận của")) \(c.author.name)"
                            )
                        } label: {
                            Label(L10n.tr("Báo cáo"), systemImage: "flag")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(KinnectTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
                .overlay(alignment: .topLeading) {
                    if reactionPickerCommentId == c.id {
                        HStack(spacing: 8) {
                            ForEach(commentReactionOptions, id: \.key) { option in
                                Button {
                                    let next: String? = (c.myReaction == option.key) ? nil : option.key
                                    setCommentReaction(c, reaction: next)
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                        reactionPickerCommentId = nil
                                    }
                                } label: {
                                    Text(option.emoji)
                                        .font(.system(size: 20))
                                        .padding(4)
                                        .background(
                                            Circle()
                                                .fill(c.myReaction == option.key ? KinnectTheme.accentBright.opacity(0.22) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(option.title)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                .shadow(color: Color.black.opacity(0.24), radius: 10, y: 4)
                                .overlay(Capsule().stroke(KinnectTheme.borderSoft, lineWidth: 1))
                        )
                        .fixedSize()
                        .offset(x: 0, y: -46)
                        .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
                        .zIndex(30)
                    }
                }
            }
        }
        .padding(.leading, CGFloat(depth * 24))
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
        if comments.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/posts/\(post.id)/comments"),
           let list = cached["comments"] as? [[String: Any]] {
            self.comments = list.map(CommentItem.from)
        }
        isLoading = comments.isEmpty
        defer { isLoading = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/posts/\(post.id)/comments") {
            let list = res["comments"] as? [[String: Any]] ?? []
            self.comments = list.map(CommentItem.from)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-review-comment-reactions"),
               let firstId = self.comments.first?.id {
                self.reactionPickerCommentId = firstId
            }
            #endif
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
            onCountChanged?(comments.count)
            onChanged()
        } catch {
            newComment = draft
            replyingTo = replyTarget
            appState.showToast(error.localizedDescription)
        }
    }

    private func saveEditedComment(_ item: CommentItem) async {
        let clean = editingCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/comments/\(item.id)",
                method: "PATCH",
                body: ["body": clean]
            )
            editingComment = nil
            await loadComments()
            onChanged()
            appState.showToast(L10n.tr("Đã cập nhật bình luận."))
        } catch {
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
            onCountChanged?(comments.count)
            onChanged()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

func formatRelativeDate(_ iso: String) -> String {
    guard !iso.isEmpty else { return L10n.tr("Vừa xong") }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return L10n.tr("Gần đây") }
    let rel = RelativeDateTimeFormatter()
    rel.locale = LocalizationManager.shared.currentLanguage == .en
        ? Locale(identifier: "en_US")
        : Locale(identifier: "vi_VN")
    rel.unitsStyle = .short
    return rel.localizedString(for: date, relativeTo: Date())
}


// Feed-only styling keeps the rest of the app's card appearance unchanged.
private struct FeedCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}
