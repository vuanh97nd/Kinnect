import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

struct FeedView: View {
    let onOpenCamera: () -> Void
    let onOpenFriends: () -> Void

    @ObservedObject private var appState = AppState.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var stories: [StoryItem] = []
    @State private var posts: [PostItem] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil

    // Composer state
    @State private var showComposerSheet = false
    @State private var showCreateStorySheet = false
    @State private var activeStoryItem: StoryItem?
    @State private var activeCommentPost: PostItem?
    @State private var editingPost: PostItem?
    @State private var editingPostText = ""
    @State private var audiencePost: PostItem?
    @State private var showAudienceDialog = false
    @State private var hiddenPostIds: Set<String> = []
    @State private var selectedAuthorProfile: KinnectUser? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                quickComposeRow

                storiesStrip

                if let loadError, !visiblePosts.isEmpty {
                    KinnectErrorBanner(message: loadError) {
                        Task { await loadFeedAndStories() }
                    }
                }

                if isLoading && posts.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        PostSkeletonCard()
                    }
                } else if visiblePosts.isEmpty {
                    if let loadError {
                        KinnectStateView(mode: .error(
                            title: "Không tải được bảng tin",
                            message: loadError,
                            retryTitle: "Thử lại",
                            onRetry: { Task { await loadFeedAndStories() } }
                        ))
                    } else {
                        KinnectStateView(mode: .empty(
                            glyph: .feed,
                            systemIcon: nil,
                            title: "Chưa có bài viết nào",
                            subtitle: "Hãy theo dõi thêm bạn bè hoặc đăng bài viết đầu tiên của bạn.",
                            actionTitle: "Đăng bài mới",
                            onAction: { showComposerSheet = true }
                        ))
                    }
                } else {
                    ForEach(visiblePosts) { post in
                        PostCardView(
                            post: post,
                            currentUserId: appState.currentUser?.id ?? "",
                            isAuthorOnline: appState.onlineUserIds.contains(post.author.id),
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
                                Task { await deletePost(post) }
                            },
                            onReport: {
                                appState.activeReportContext = UGCReportContext(
                                    targetType: "post",
                                    targetId: post.id,
                                    targetUserId: post.author.id,
                                    targetTitle: "Bài viết của \(post.author.name)"
                                )
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 72)
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
            await restoreCachedFeed()
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
        .sheet(item: $activeStoryItem) { story in
            StoryDetailSheet(story: story)
        }
        .sheet(item: $activeCommentPost) { post in
            PostCommentsSheet(post: post) {
                Task { await loadFeedAndStories() }
            }
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
                                    _ = try await KinnectAPIClient.shared.requestJSON(
                                        "/api/posts/\(post.id)",
                                        method: "PATCH",
                                        body: ["body": editingPostText]
                                    )
                                    editingPost = nil
                                    await loadFeedAndStories()
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
            appState.showToast("Đã đổi đối tượng xem thành \(title).")
            await loadFeedAndStories()
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

    private var storyCellWidth: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : 68
    }

    private var storiesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 12) {
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
                                size: dynamicTypeSize.isAccessibilitySize ? 58 : 58
                            )
                            Circle()
                                .fill(KinnectTheme.accentBright)
                                .frame(width: 22, height: 22)
                                .overlay(KinnectIcon(glyph: .add, size: 14, selected: true, tint: .white))
                        }
                        Text(dynamicTypeSize.isAccessibilitySize ? "Tạo\ntin" : "Tạo tin")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                    .frame(width: storyCellWidth)
                }
                .accessibilityLabel("Tạo tin 24h mới")
                .accessibilityHint("Nhấn đúp để mở trình tạo tin")

                ForEach(stories.filter { !appState.blockedUserIds.contains($0.author.id) }) { story in
                    Button {
                        activeStoryItem = story
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(
                                        story.viewed
                                            ? LinearGradient(colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                                            : KinnectTheme.primaryGradient,
                                        lineWidth: 2.5
                                    )
                                    .frame(width: 62, height: 62)

                                KinnectAvatarView(
                                    name: story.author.name,
                                    avatarURL: story.author.avatarUrl,
                                    colorHex: story.author.avatarColor,
                                    size: 54
                                )
                            }
                            Text(shortStoryDisplayName(story.author.name))
                                .font(.caption2.weight(.medium))
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
                        .frame(width: storyCellWidth)
                    }
                    .accessibilityLabel("Tin 24h của \(story.author.name)")
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
        if dynamicTypeSize.isAccessibilitySize {
            if words.count >= 2 {
                return words.suffix(2).joined(separator: "\n")
            }
            return cleaned.isEmpty ? "Kinnect" : cleaned
        }
        if words.count >= 2 {
            return words.suffix(2).joined(separator: " ")
        }
        return cleaned.isEmpty ? "Kinnect" : cleaned
    }

    private var quickComposeRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
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
                        .padding(.horizontal, 16)
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
                        .padding(.horizontal, 14) // spacing-ok: viền capsule gợi ý
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

    private func restoreCachedFeed() async {
        #if DEBUG
        if UIReviewFixture.activeScreen == "feed-error" {
            self.posts = []
            return
        }
        #endif
        guard let accountId = appState.currentUser?.id else { return }
        await Task.detached(priority: .userInitiated) {
            if let cached: [[String: Any]] = AccountCache.shared.loadJSONObject(forKey: "feed_posts", accountId: accountId) {
                let mapped = cached.map(PostItem.from)
                await MainActor.run {
                    self.posts = mapped
                }
            }
        }.value
    }

    private func loadFeedAndStories() async {
        isLoading = true
        defer { isLoading = false }

        async let postsTask = KinnectAPIClient.shared.requestJSON("/api/posts")
        async let storiesTask = KinnectAPIClient.shared.requestJSON("/api/stories")

        do {
            let postsRes = try await postsTask
            let rawList = postsRes["posts"] as? [[String: Any]] ?? []
            self.posts = rawList.map(PostItem.from)
            self.loadError = nil
            if let accountId = appState.currentUser?.id {
                AccountCache.shared.saveJSONObject(rawList, forKey: "feed_posts", accountId: accountId)
            }
            let mediaPaths = self.posts.prefix(6).flatMap { [$0.imageUrl, $0.author.avatarUrl] }
            ImageMemoryCache.shared.prefetch(paths: mediaPaths, maxPointSize: 560)
        } catch {
            self.loadError = error.localizedDescription
        }
        if let storiesRes = try? await storiesTask {
            let rawStories = storiesRes["stories"] as? [[String: Any]] ?? []
            self.stories = rawStories.map(StoryItem.from)
        }
    }

    private func toggleReaction(post: PostItem, reaction: String) async {
        let reqId = "react_\(post.id)_\(Int(Date().timeIntervalSince1970))"
        do {
            if post.liked && post.userReaction == reaction {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/like",
                    method: "DELETE",
                    body: [:],
                    requestId: reqId
                )
            } else {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/like",
                    method: "POST",
                    body: ["reaction": reaction],
                    requestId: reqId
                )
            }
            await loadFeedAndStories()
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
            appState.showToast("Đã xóa bài viết.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

func formatRelativeDate(_ iso: String) -> String {
    guard !iso.isEmpty else { return "Vừa xong" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return "Gần đây" }
    let rel = RelativeDateTimeFormatter()
    rel.locale = Locale(identifier: "vi_VN")
    rel.unitsStyle = .short
    return rel.localizedString(for: date, relativeTo: Date())
}


// Feed-only styling keeps the rest of the app's card appearance unchanged.
struct FeedCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}
