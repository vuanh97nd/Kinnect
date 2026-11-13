import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct ShortsVideoView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var shortsTab: String = "for" // "for" (Đề xuất) | "following" (Đang theo dõi)
    @State private var items: [ShortItem] = []
    @State private var currentIndex: Int? = 0
    @State private var isLoading = false
    @State private var activeCommentShort: ShortItem?
    @State private var activeOptionsShort: ShortItem?
    @State private var selectedAuthorProfile: KinnectUser? = nil
    @State private var isMuted: Bool = false
    @State private var userPaused: Bool = false
    @State private var floatingHearts: [FloatingHeart] = []
    @State private var followingRequests: Set<String> = []
    private let profileItems: [ShortItem]?

    init(initialItems: [ShortItem]? = nil, initialShortID: String? = nil) {
        profileItems = initialItems
        if let initialItems {
            let selected = initialItems.firstIndex { $0.id == initialShortID } ?? 0
            let ordered = Array(initialItems.dropFirst(selected)) + Array(initialItems.prefix(selected))
            _items = State(initialValue: ordered)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if items.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    KinnectIcon(glyph: .video, size: 48, tint: KinnectTheme.textSecondary)
                    Text("Chưa có video ngắn")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Các video ngắn thịnh hành sẽ hiển thị tại đây.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !items.isEmpty {
                GeometryReader { geo in
                    if #available(iOS 17.0, *) {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    shortVideoCard(item, at: index)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .id(index)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $currentIndex)
                    } else {
                        TabView(selection: $currentIndex) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                shortVideoCard(item, at: index)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .rotationEffect(.degrees(-90))
                                    .tag(Optional(index))
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(width: geo.size.height, height: geo.size.width)
                        .rotationEffect(.degrees(90))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                    .onChange(of: currentIndex) { _ in
                        userPaused = false
                    }
                }
            }

            // Top transparent floating bar (Đề xuất · Đang theo dõi) - Parity with Android 1.2.12
            HStack(spacing: 24) {
                Spacer()
                tabHeaderButton(id: "for", title: "Đề xuất")
                tabHeaderButton(id: "following", title: "Đang theo dõi")
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.7), Color.black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )
        }
        .task {
            await loadShorts()
        }
        .sheet(item: $activeCommentShort) { short in
            ShortCommentsSheet(short: short) {
                Task { await loadShorts() }
            }
        }
        .sheet(item: $activeOptionsShort) { short in
            ShortOptionsSheet(
                item: short,
                isMine: short.author.id == appState.currentUser?.id,
                onMuteToggle: { isMuted.toggle() },
                isMuted: isMuted,
                onDelete: {
                    Task { await deleteShort(short) }
                },
                onReport: {
                    appState.activeReportContext = UGCReportContext(
                        targetType: "short",
                        targetId: short.id,
                        targetUserId: short.author.id,
                        targetTitle: "Video ngắn của \(short.author.name)"
                    )
                },
                onOpenAuthor: {
                    selectedAuthorProfile = short.author
                },
                onShare: {
                    let permalink = "https://kinnect.io.vn/shorts/\(short.id)"
                    UIPasteboard.general.string = permalink
                    appState.showToast("Đã sao chép liên kết video!")
                }
            )
        }
        .fullScreenCover(item: $selectedAuthorProfile) { author in
            NavigationStack {
                ProfileView(targetUser: author)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đóng") { selectedAuthorProfile = nil }
                        }
                    }
            }
        }
    }

    private func tabHeaderButton(id: String, title: String) -> some View {
        let isSelected = shortsTab == id
        return Button {
            shortsTab = id
            currentIndex = 0
            Task { await loadShorts() }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(KinnectTheme.scaled(16, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                if isSelected {
                    Capsule()
                        .fill(KinnectTheme.accentBright)
                        .frame(width: 24, height: 3)
                } else {
                    Capsule()
                        .fill(Color.clear)
                        .frame(width: 24, height: 3)
                }
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func shortVideoCard(_ item: ShortItem, at index: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.black)
            ShortClipPlayer(path: item.videoUrl, active: index == currentIndex, muted: isMuted, userPaused: userPaused && index == currentIndex)
                .allowsHitTesting(false)

            // Double tap detector for floating heart
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    triggerDoubleTapHeart(at: index, point: location)
                }
                .onTapGesture(count: 1) {
                    userPaused.toggle()
                }

            // Floating hearts animation overlay
            ForEach(floatingHearts) { heart in
                HeartEffectView()
                    .position(x: heart.x, y: heart.y)
                    .allowsHitTesting(false)
            }

            // Right Action Column (Like, Comment, Share)
            HStack(alignment: .bottom) {
                // Bottom left: Author info & Caption
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        selectedAuthorProfile = item.author
                    } label: {
                        HStack(spacing: 8) {
                            KinnectAvatarView(
                                name: item.author.name,
                                avatarURL: item.author.avatarUrl,
                                colorHex: item.author.avatarColor,
                                size: 36,
                                isOnline: false
                            )
                            Text("@\(item.author.handle.isEmpty ? item.author.name : item.author.handle)")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                    }
                    .buttonStyle(.plain)

                    if !item.caption.isEmpty {
                        Text(item.caption)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.95))
                            .lineLimit(3)
                            .shadow(radius: 2)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Âm thanh gốc — \(item.author.name)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

                Spacer()

                // Right Action Sidebar
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        Button { selectedAuthorProfile = item.author } label: {
                            KinnectAvatarView(name: item.author.name, avatarURL: item.author.avatarUrl,
                                              colorHex: item.author.avatarColor, size: 46)
                        }
                        .buttonStyle(.plain)
                        if item.author.id != appState.currentUser?.id {
                            Button { Task { await toggleFollow(item.author) } } label: {
                                Image(systemName: item.author.isFollowed ? "checkmark" : "plus")
                                    .font(KinnectTheme.scaled(13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(item.author.isFollowed ? KinnectTheme.accentBright : KinnectTheme.danger))
                                    .frame(width: 44, height: 44)
                            }
                            .disabled(followingRequests.contains(item.author.id))
                            .accessibilityLabel(item.author.isFollowed ? "Bỏ theo dõi" : "Theo dõi")
                        }
                    }

                    // Like button
                    Button {
                        toggleLike(at: index)
                    } label: {
                        VStack(spacing: 4) {
                            KinnectIcon(
                                glyph: .heart,
                                size: 28,
                                selected: item.liked,
                                tint: item.liked ? KinnectTheme.danger : .white
                            )
                            Text("\(item.likesCount)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(item.liked ? "Bỏ thích video" : "Thích video")

                    // Comments button
                    Button {
                        activeCommentShort = item
                    } label: {
                        VStack(spacing: 4) {
                            KinnectIcon(glyph: .comment, size: 28, selected: true, tint: .white)
                            Text("\(item.commentsCount)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Bình luận")

                    // Share button (Real permalink copy + UIActivityViewController presentation)
                    Button {
                        let permalink = "https://kinnect.io.vn/shorts/\(item.id)"
                        UIPasteboard.general.string = permalink
                        appState.showToast("Đã sao chép liên kết video!")
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootVC = windowScene.windows.first?.rootViewController {
                            let items: [Any] = [URL(string: permalink) ?? permalink]
                            let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
                            rootVC.present(av, animated: true)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            KinnectIcon(glyph: .share, size: 28, tint: .white)
                            Text("Chia sẻ")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Chia sẻ video")

                    // Options / More button (Tùy chọn) - Parity with Android shortOptions
                    Button {
                        activeOptionsShort = item
                    } label: {
                        VStack(spacing: 4) {
                            KinnectIcon(glyph: .more, size: 28, tint: .white)
                            Text("Tùy chọn")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Tùy chọn video")
                }
                .padding(.trailing, 12)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func triggerDoubleTapHeart(at index: Int, point: CGPoint) {
        let heart = FloatingHeart(x: point.x, y: point.y)
        floatingHearts.append(heart)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            floatingHearts.removeAll(where: { $0.id == heart.id })
        }
        guard index < items.count else { return }
        if !items[index].liked {
            toggleLike(at: index)
        }
    }

    private func toggleLike(at index: Int) {
        guard index < items.count else { return }
        let current = items[index]
        let newLiked = !current.liked
        items[index].liked = newLiked
        items[index].likesCount = max(0, current.likesCount + (newLiked ? 1 : -1))

        Task {
            do {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts/\(current.id)/like",
                    method: newLiked ? "POST" : "DELETE"
                )
            } catch {
                // Revert on failure
                if index < items.count {
                    items[index].liked = current.liked
                    items[index].likesCount = current.likesCount
                }
            }
        }
    }

    private func toggleFollow(_ author: KinnectUser) async {
        guard !followingRequests.contains(author.id) else { return }
        followingRequests.insert(author.id)
        defer { followingRequests.remove(author.id) }
        do {
            let result = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(author.id)/follow", method: author.isFollowed ? "DELETE" : "POST")
            let user = result["user"] as? [String: Any]
            let following = (user?["following"] as? Bool) ?? !author.isFollowed
            for index in items.indices where items[index].author.id == author.id {
                items[index].author.isFollowed = following
            }
        } catch { appState.showToast(error.localizedDescription) }
    }

    private func deleteShort(_ item: ShortItem) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts/\(item.id)",
                method: "DELETE"
            )
            items.removeAll(where: { $0.id == item.id })
            appState.showToast("Đã xoá video ngắn.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func loadShorts() async {
        if profileItems != nil { return }
        let cacheKey = "shorts_feed_\(shortsTab)"
        if let accountId = AccountCache.shared.activeAccountId {
            if let cached: [[String: Any]] = AccountCache.shared.loadJSONObject(forKey: cacheKey, accountId: accountId), items.isEmpty {
                self.items = cached.map(ShortItem.from)
            }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts?feed=\(shortsTab)",
                method: "GET"
            )
            if let arr = res["shorts"] as? [[String: Any]] {
                self.items = arr.map(ShortItem.from)
                if let accountId = AccountCache.shared.activeAccountId {
                    AccountCache.shared.saveJSONObject(arr, forKey: cacheKey, accountId: accountId)
                }
            }
        } catch {
            if items.isEmpty {
                appState.showToast("Không thể tải video: \(error.localizedDescription)")
            }
        }
    }
}

struct ShortClipPlayer: View {
    let path: String
    let active: Bool
    var muted: Bool = false
    var userPaused: Bool = false
    @ObservedObject private var calls = NativeWebRTCManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var loading = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var shouldPlay = false
    @State private var statusObserver: NSKeyValueObservation?

    var body: some View {
        ZStack {
            // Elegant cinematic gradient background so video is never a black void
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.08, blue: 0.32),
                    Color(red: 0.05, green: 0.03, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if failed {
                VStack(spacing: 12) {
                    Text("Không thể phát video.").foregroundColor(.white)
                    Button("Thử lại") { Task { await load() } }.tint(.white)
                }
            } else if let player {
                VideoPlayer(player: player)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            } else if loading {
                ProgressView().tint(.white)
            } else {
                VStack(spacing: 12) {
                    KinnectIcon(glyph: .video, size: 54, tint: KinnectTheme.accentBright.opacity(0.85))
                    Text("Kinnect Video HD")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Text("Chưa có nguồn video khả dụng.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .task(id: path) { await load() }
        .onChange(of: active) { _ in syncPlayback() }
        .onChange(of: muted) { player?.isMuted = $0 }
        .onChange(of: userPaused) { _ in syncPlayback() }
        .onChange(of: scenePhase) { _ in syncPlayback() }
        .onChange(of: calls.activeCall != nil) { _ in syncPlayback() }
        .onDisappear { stop() }
    }

    private func load() async {
        stop()
        guard !path.isEmpty else {
            failed = false
            return
        }
        failed = false
        loading = true
        defer { loading = false }

        // Configure audio session for smooth video audio playback
        if calls.activeCall == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }

        if path.hasPrefix("file://"), let localURL = URL(string: path) {
            setupPlayer(with: AVPlayerItem(url: localURL))
            return
        }

        // 1. Try playing from authenticated media cache (fast, reliable, no AVURLAsset cookie dropping on iOS)
        if path.hasPrefix("/api/") || path.hasPrefix("/") || path.contains("app.kinnect.io.vn") {
            if let cachedLocalURL = try? await KinnectAuthenticatedFile.fetch(path: path, fileExtension: "mp4") {
                setupPlayer(with: AVPlayerItem(url: cachedLocalURL))
                return
            }
        }

        // 2. Direct streaming fallback with cookie jar
        let origin = KinnectAPIClient.shared.mediaOrigin
        KeychainStore.shared.syncToHTTPCookieStorage(origin: origin)
        guard let remoteURL = ServerConfig.url(for: path, origin: origin) else {
            if let fixtureURL = UIReviewFixture.samplePlayableVideoURL() {
                setupPlayer(with: AVPlayerItem(url: fixtureURL))
                return
            }
            failed = true
            return
        }

        let cookie = KeychainStore.shared.cookieJarHeader(for: origin)
        var options: [String: Any] = [:]
        if !cookie.isEmpty, remoteURL.host == URL(string: origin)?.host {
            options["AVURLAssetHTTPHeaderFieldsKey"] = ["Cookie": cookie]
        }

        let asset = AVURLAsset(url: remoteURL, options: options)
        let item = AVPlayerItem(asset: asset)
        setupPlayer(with: item)
    }

    private func setupPlayer(with item: AVPlayerItem) {
        let next = AVPlayer(playerItem: item)
        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak next] item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    failed = false
                    loading = false
                    if shouldPlay { next?.play() }
                case .failed:
                    failed = true
                    loading = false
                default:
                    break
                }
            }
        }
        next.isMuted = muted
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            next.seek(to: .zero)
            if shouldPlay { next.play() }
        }
        player = next
        syncPlayback()
    }

    private func syncPlayback() {
        let blocked = !active || scenePhase != .active || calls.activeCall != nil || userPaused
        shouldPlay = !blocked
        guard let player else { return }
        if blocked {
            player.pause()
        } else {
            player.play()
        }
    }

    private func stop() {
        statusObserver?.invalidate()
        statusObserver = nil
        shouldPlay = false
        player?.pause()
        player = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
    }
}

struct ShortCommentsSheet: View {
    let short: ShortItem
    let onUpdated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var comments: [CommentItem] = []
    @State private var text = ""
    @State private var replyingTo: CommentItem? = nil
    @State private var isPosting = false

    private let quickEmojis = ["😍", "😂", "🔥", "👏", "🥰", "😮", "😢", "💜"]

    private var rootComments: [CommentItem] {
        let roots = comments.filter { $0.parentId == nil || $0.parentId?.isEmpty == true }
        if roots.isEmpty && !comments.isEmpty { return comments }
        return roots
    }

    private func childReplies(for rootId: String) -> [CommentItem] {
        comments.filter { $0.parentId == rootId }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if comments.isEmpty {
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
                    List {
                        ForEach(rootComments) { root in
                            commentRowView(root, depth: 0)

                            ForEach(childReplies(for: root.id)) { reply in
                                commentRowView(reply, depth: 1, parentAuthorName: root.author.name)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                // Quick emoji reaction bar
                HStack(spacing: 10) {
                    ForEach(quickEmojis, id: \.self) { emoji in
                        Button {
                            text.append(emoji)
                        } label: {
                            Text(emoji)
                                .font(.title3)
                                .frame(minWidth: 32, minHeight: 32)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
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

                // Composer input row
                HStack(spacing: 8) {
                    TextField(replyingTo != nil ? "Trả lời \(replyingTo!.author.name)..." : "Viết bình luận...", text: $text)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)

                    Button {
                        Task { await postComment() }
                    } label: {
                        KinnectIcon(glyph: .send, size: 20, selected: true, tint: KinnectTheme.accentBright)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(KinnectTheme.surfaceElevated))
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(KinnectTheme.surface)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Bình luận (\(comments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                await load()
            }
        }
        .presentationDetents([.medium, .fraction(0.85)])
        .presentationDragIndicator(.visible)
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
                HStack(spacing: 6) {
                    Text(c.author.name)
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)

                    if let parent = parentAuthorName, depth > 0 {
                        Text("▸ \(parent)")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.accentBright)
                    }

                    Text(formatRelativeDate(c.createdAt))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }

                Text(c.text)
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .kinnectMultiline()

                // Action bar: Trả lời, Thả cảm xúc
                HStack(spacing: 14) {
                    Button {
                        replyingTo = c
                    } label: {
                        Text("Trả lời")
                            .font(.caption2.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    .buttonStyle(.plain)

                    Button {
                        toggleCommentLike(c)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: c.liked ? "heart.fill" : "heart")
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
                }
                .padding(.top, 2)
            }
        }
        .padding(.leading, CGFloat(depth * 24))
        .listRowBackground(KinnectTheme.surface)
        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
    }

    private func toggleCommentLike(_ item: CommentItem) {
        if let idx = comments.firstIndex(where: { $0.id == item.id }) {
            comments[idx].liked.toggle()
            comments[idx].likesCount += comments[idx].liked ? 1 : -1
            if comments[idx].likesCount < 0 { comments[idx].likesCount = 0 }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts/\(short.id)/comments/\(item.id)/like",
                    method: "POST",
                    body: [:]
                )
            }
        }
    }

    private func load() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/shorts/\(short.id)/comments") {
            self.comments = (res["comments"] as? [[String: Any]] ?? []).map(CommentItem.from)
        }
    }

    private func postComment() async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        isPosting = true
        let draft = text
        text = ""
        let parent = replyingTo?.id
        replyingTo = nil
        let reqId = "short_cmt_\(short.id)_\(UUID().uuidString)"
        do {
            var bodyDict: [String: Any] = ["body": clean]
            if let parent = parent {
                bodyDict["parentId"] = parent
            }
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts/\(short.id)/comments",
                method: "POST",
                body: bodyDict,
                requestId: reqId
            )
            await load()
            onUpdated()
        } catch {
            text = draft
            appState.showToast(error.localizedDescription)
        }
        isPosting = false
    }
}

// MARK: - Video Options Sheet (Parity with Android shortOptions)
struct ShortOptionsSheet: View {
    let item: ShortItem
    let isMine: Bool
    let onMuteToggle: () -> Void
    let isMuted: Bool
    let onDelete: () -> Void
    let onReport: () -> Void
    let onOpenAuthor: () -> Void
    let onShare: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Horizontal scrolling options buttons row (Android parity: tiktokOptionBtn)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        optionTile(icon: "arrow.down.circle.fill", label: "Lưu video") {
                            dismiss()
                            UIPasteboard.general.string = item.videoUrl
                            AppState.shared.showToast("Đã lưu liên kết video vào bộ nhớ tạm!")
                        }

                        optionTile(icon: "music.note", label: "Âm thanh") {
                            dismiss()
                            AppState.shared.showToast("Âm thanh gốc — \(item.author.name)")
                        }

                        optionTile(icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: isMuted ? "Bật âm" : "Tắt âm") {
                            dismiss()
                            onMuteToggle()
                        }

                        optionTile(icon: isMine ? "trash.fill" : "flag.fill", label: isMine ? "Xoá video" : "Báo cáo", isDestructive: isMine) {
                            dismiss()
                            if isMine { onDelete() } else { onReport() }
                        }

                        optionTile(icon: "person.crop.circle.fill", label: "Hồ sơ tác giả") {
                            dismiss()
                            onOpenAuthor()
                        }

                        optionTile(icon: "link", label: "Sao chép link") {
                            dismiss()
                            onShare()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }

                Spacer()
            }
            .padding(.top, 16)
            .background(KinnectTheme.background)
            .navigationTitle("Tùy chọn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(180)])
    }

    private func optionTile(icon: String, label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isDestructive ? KinnectTheme.danger.opacity(0.18) : KinnectTheme.surfaceElevated)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(KinnectTheme.scaled(24))
                        .foregroundColor(isDestructive ? KinnectTheme.danger : KinnectTheme.accentBright)
                }
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Floating Heart Animation (Web Parity `liveReaction` & Double Tap)
struct FloatingHeart: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
}

struct HeartEffectView: View {
    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 1.0
    @State private var offsetY: CGFloat = 0

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 64))
            .foregroundColor(KinnectTheme.danger)
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(y: offsetY)
            .onAppear {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    scale = 1.25
                }
                withAnimation(.easeOut(duration: 0.75).delay(0.2)) {
                    offsetY = -120
                    opacity = 0
                    scale = 1.45
                }
            }
    }
}
