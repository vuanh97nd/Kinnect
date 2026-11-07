import PhotosUI
import SwiftUI
import UIKit

struct FeedView: View {
    let onOpenCamera: () -> Void
    let onOpenFriends: () -> Void

    @ObservedObject private var appState = AppState.shared

    @State private var stories: [StoryItem] = []
    @State private var posts: [PostItem] = []
    @State private var selectedCategory: String = "all"
    @State private var isLoading = false

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

    private struct FeedCategoryOption: Identifiable {
        let id: String
        let label: String
        let icon: String
    }

    private let categories: [FeedCategoryOption] = [
        FeedCategoryOption(id: "all", label: "Tất cả", icon: "sparkles"),
        FeedCategoryOption(id: "community", label: "Cộng đồng", icon: "person.3.fill"),
        FeedCategoryOption(id: "confessions", label: "Tâm sự", icon: "heart.text.square.fill"),
        FeedCategoryOption(id: "questions", label: "Hỏi đáp", icon: "questionmark.bubble.fill"),
        FeedCategoryOption(id: "events", label: "Sự kiện", icon: "calendar.badge.clock")
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                storiesStrip

                categoryFilterStrip

                quickComposeRow

                if isLoading && posts.isEmpty {
                    ProgressView()
                        .tint(KinnectTheme.accentBright)
                        .padding(.vertical, 32)
                } else if filteredPosts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "newspaper.fill")
                            .font(.largeTitle)
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text("Chưa có bài viết trong mục này")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.vertical, 36)
                } else {
                    ForEach(filteredPosts) { post in
                        PostCardView(
                            post: post,
                            currentUserId: appState.currentUser?.id ?? "",
                            isAuthorOnline: appState.onlineUserIds.contains(post.author.id),
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showComposerSheet) {
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
                                _ = try? await KinnectAPIClient.shared.requestJSON(
                                    "/api/posts/\(post.id)",
                                    method: "PATCH",
                                    body: ["body": editingPostText]
                                )
                                editingPost = nil
                                await loadFeedAndStories()
                                appState.showToast("Đã lưu bài viết!")
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
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/posts/\(p.id)",
                            method: "PATCH",
                            body: ["visibility": "public"]
                        )
                        appState.showToast("Đã đổi đối tượng xem thành Mọi thành viên.")
                        await loadFeedAndStories()
                    }
                }
                Button("Người theo dõi (Bạn bè)") {
                    Task {
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/posts/\(p.id)",
                            method: "PATCH",
                            body: ["visibility": "followers"]
                        )
                        appState.showToast("Đã đổi đối tượng xem thành Người theo dõi.")
                        await loadFeedAndStories()
                    }
                }
                Button("Hủy", role: .cancel) {}
            }
        }
    }

    private var filteredPosts: [PostItem] {
        posts.filter { post in
            guard !hiddenPostIds.contains(post.id) else { return false }
            guard !appState.blockedUserIds.contains(post.author.id) else { return false }
            if selectedCategory == "all" { return true }
            return post.category == selectedCategory
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
                        Text("Tạo tin")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                    .frame(width: 68)
                }
                .accessibilityLabel("Tạo tin 24h")

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
                            Text(story.author.name.components(separatedBy: " ").last ?? story.author.name)
                                .font(.caption2)
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(width: 68)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var categoryFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    let active = (selectedCategory == cat.id)
                    Button {
                        selectedCategory = cat.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.caption)
                            Text(cat.label)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(active ? AnyShapeStyle(KinnectTheme.primaryGradient) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                        )
                        .foregroundColor(.white)
                    }
                }
            }
        }
    }

    private var quickComposeRow: some View {
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
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(KinnectTheme.surfaceElevated))
            }

            KinnectIconButton(
                glyph: .camera,
                label: "Mở Camera & Studio",
                tint: KinnectTheme.accentBright,
                action: onOpenCamera
            )
        }
        .kinnectCard()
    }

    private func restoreCachedFeed() {
        guard let accountId = appState.currentUser?.id else { return }
        if let cached: [[String: Any]] = AccountCache.shared.loadJSONObject(forKey: "feed_posts", accountId: accountId) {
            self.posts = cached.map(PostItem.from)
        }
    }

    private func loadFeedAndStories() async {
        isLoading = true
        defer { isLoading = false }

        async let postsTask = KinnectAPIClient.shared.requestJSON("/api/posts")
        async let storiesTask = KinnectAPIClient.shared.requestJSON("/api/stories")

        if let postsRes = try? await postsTask {
            let rawList = postsRes["posts"] as? [[String: Any]] ?? []
            self.posts = rawList.map(PostItem.from)
            if let accountId = appState.currentUser?.id {
                AccountCache.shared.saveJSONObject(rawList, forKey: "feed_posts", accountId: accountId)
            }
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

private struct PostCardView: View {
    let post: PostItem
    let currentUserId: String
    let isAuthorOnline: Bool
    let onReact: (String) -> Void
    let onOpenComments: () -> Void
    var onEdit: (() -> Void)? = nil
    var onChangeAudience: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil
    let onDelete: () -> Void
    let onReport: () -> Void

    private let reactionOptions: [(key: String, emoji: String)] = [
        ("like", "👍"),
        ("love", "❤️"),
        ("haha", "😆"),
        ("wow", "😮"),
        ("sad", "😢")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                KinnectAvatarView(
                    name: post.author.name,
                    avatarURL: post.author.avatarUrl,
                    colorHex: post.author.avatarColor,
                    size: 42,
                    isOnline: isAuthorOnline
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .kinnectMultiline()
                    HStack(spacing: 6) {
                        Text(categoryLabel(post.category))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(KinnectTheme.accentBright)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text(formatRelativeDate(post.createdAt))
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }

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
                KinnectRemoteImageView(
                    rawURL: post.imageUrl,
                    contentMode: .fill,
                    cornerRadius: 14,
                    maxHeight: 340
                )
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

            Divider().background(KinnectTheme.border)

            // Equal 3-Column Action Bar (Android parity: 33% Cảm xúc, 33% Bình luận, 33% Chia sẻ)
            HStack(spacing: 0) {
                // Column 1: Cảm xúc (Reaction)
                Menu {
                    ForEach(reactionOptions, id: \.key) { item in
                        Button("\(item.emoji) \(item.key.capitalized)") {
                            onReact(item.key)
                        }
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
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                } primaryAction: {
                    onReact(post.liked ? post.userReaction : "like")
                }
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
                ShareLink(
                    item: postShareURL,
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
        .kinnectCard()
    }

    private var postShareURL: URL {
        let route = "/?s=postDetail&post=\(post.id)"
        return ServerConfig.resolveURL(route) ?? URL(string: "\(ServerConfig.defaultOrigin)\(route)") ?? URL(string: "https://app.kinnect.io.vn\(route)")!
    }

    private var shareSubject: String {
        return "Bài viết từ \(post.author.name) trên Kinnect"
    }

    private func reactionTitle(for key: String) -> String {
        switch key {
        case "love": return "Yêu thích"
        case "haha": return "Haha"
        case "wow": return "Wow"
        case "sad": return "Buồn"
        default: return "Thích"
        }
    }

    private func reactionEmoji(for key: String) -> String {
        switch key {
        case "love": return "❤️"
        case "haha": return "😆"
        case "wow": return "😮"
        case "sad": return "😢"
        default: return "👍"
        }
    }

    private func categoryLabel(_ key: String) -> String {
        switch key {
        case "confessions": return "Tâm sự"
        case "questions": return "Hỏi đáp"
        case "events": return "Sự kiện"
        default: return "Cộng đồng"
        }
    }
}

struct PostComposerSheet: View {
    let onPosted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var text = ""
    @State private var category = "community"
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageDataURL: String = ""
    @State private var previewImage: UIImage?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Chuyên mục", selection: $category) {
                        Text("Cộng đồng").tag("community")
                        Text("Tâm sự").tag("confessions")
                        Text("Hỏi đáp").tag("questions")
                        Text("Sự kiện").tag("events")
                    }
                    .pickerStyle(.segmented)

                    TextField("Chia sẻ câu chuyện hoặc khoảnh khắc của bạn...", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)

                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Chọn ảnh từ thư viện", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    .onChange(of: selectedPhotoItem) { newItem in
                        guard let newItem else { return }
                        Task {
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let uiImg = UIImage(data: data),
                               let compressed = uiImg.jpegData(compressionQuality: 0.72) {
                                self.previewImage = uiImg
                                self.imageDataURL = "data:image/jpeg;base64,\(compressed.base64EncodedString())"
                            }
                        }
                    }

                    Button {
                        Task { await submitPost() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Đăng bài viết")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(KinnectTheme.primaryGradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSubmitting || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageDataURL.isEmpty))
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Tạo bài viết")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
            }
        }
    }

    private func submitPost() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let reqId = "post_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts",
                method: "POST",
                body: [
                    "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
                    "category": category,
                    "imageUrl": imageDataURL
                ],
                requestId: reqId
            )
            onPosted()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct StoryComposerSheet: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var text = ""
    @State private var backgroundColor = "#7C3AED"
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var imageDataURL = ""
    @State private var previewImage: UIImage?
    @State private var isSubmitting = false

    private let colors = ["#7C3AED", "#EC4899", "#2563EB", "#059669", "#D97706"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hex: backgroundColor))
                            .frame(height: 260)

                        if let previewImage {
                            Image(uiImage: previewImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        }

                        TextField("Nhập nội dung tin 24h...", text: $text, axis: .vertical)
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .padding(20)
                    }

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

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Chọn ảnh cho Tin", systemImage: "photo")
                            .font(.subheadline.weight(.semibold))
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    .onChange(of: selectedPhotoItem) { item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let uiImg = UIImage(data: data),
                               let jpeg = uiImg.jpegData(compressionQuality: 0.72) {
                                previewImage = uiImg
                                imageDataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
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
                    .disabled(isSubmitting || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageDataURL.isEmpty))
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Tạo Tin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private func createStory() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let reqId = "story_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/stories",
                method: "POST",
                body: [
                    "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
                    "imageUrl": imageDataURL,
                    "backgroundColor": backgroundColor
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

struct StoryDetailSheet: View {
    let story: StoryItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var viewers: [KinnectUser] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    KinnectAvatarView(
                        name: story.author.name,
                        avatarURL: story.author.avatarUrl,
                        colorHex: story.author.avatarColor,
                        size: 40
                    )
                    VStack(alignment: .leading) {
                        Text(story.author.name)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text("Lượt xem: \(max(story.viewsCount, viewers.count))")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Spacer()
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(hex: story.backgroundColor))
                        .frame(maxWidth: .infinity, minHeight: 340)

                    if !story.imageUrl.isEmpty {
                        KinnectRemoteImageView(
                            rawURL: story.imageUrl,
                            contentMode: .fit,
                            cornerRadius: 22,
                            maxHeight: 380
                        )
                    }

                    if !story.text.isEmpty {
                        Text(story.text)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .kinnectMultiline()
                            .padding(24)
                            .background(Color.black.opacity(story.imageUrl.isEmpty ? 0 : 0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                if !viewers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Người đã xem (\(viewers.count))")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewers) { viewer in
                                    HStack(spacing: 6) {
                                        KinnectAvatarView(
                                            name: viewer.name,
                                            avatarURL: viewer.avatarUrl,
                                            colorHex: viewer.avatarColor,
                                            size: 26
                                        )
                                        Text(viewer.name)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(KinnectTheme.background)
            .navigationTitle("Tin 24h")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/stories/\(story.id)/view",
                    method: "POST",
                    body: [:],
                    requestId: "view_story_\(story.id)"
                )
                if story.author.id == appState.currentUser?.id,
                   let res = try? await KinnectAPIClient.shared.requestJSON("/api/stories/\(story.id)/viewers") {
                    let raw = res["viewers"] as? [[String: Any]] ?? []
                    self.viewers = raw.map { dict in
                        if let u = dict["user"] as? [String: Any] {
                            return KinnectUser.from(u)
                        }
                        return KinnectUser.from(dict)
                    }
                }
            }
        }
    }
}

struct PostCommentsSheet: View {
    let post: PostItem
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var comments: [CommentItem] = []
    @State private var newComment = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(comments) { c in
                        HStack(alignment: .top, spacing: 10) {
                            KinnectAvatarView(
                                name: c.author.name,
                                avatarURL: c.author.avatarUrl,
                                colorHex: c.author.avatarColor,
                                size: 34
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(c.author.name)
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                    Spacer()
                                    if c.author.id == appState.currentUser?.id {
                                        Button(role: .destructive) {
                                            Task { await deleteComment(c) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                        }
                                    }
                                }
                                Text(c.text)
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .kinnectMultiline()
                            }
                        }
                        .listRowBackground(KinnectTheme.surface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                HStack(spacing: 10) {
                    TextField("Viết bình luận...", text: $newComment)
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

    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/posts/\(post.id)/comments") {
            let list = res["comments"] as? [[String: Any]] ?? []
            self.comments = list.map(CommentItem.from)
        }
    }

    private func sendComment() async {
        let clean = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        newComment = ""
        let reqId = "comment_\(post.id)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/comments",
                method: "POST",
                body: ["text": clean],
                requestId: reqId
            )
            await loadComments()
            onChanged()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deleteComment(_ item: CommentItem) async {
        let reqId = "del_comment_\(item.id)"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/posts/\(post.id)/comments/\(item.id)",
            method: "DELETE",
            body: [:],
            requestId: reqId
        )
        await loadComments()
        onChanged()
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

