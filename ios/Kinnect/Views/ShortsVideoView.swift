import AVFoundation
import AVKit
import Photos
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
    @State private var isManuallyPaused: Bool = false
    @State private var floatingHearts: [FloatingHeart] = []
    @State private var followingRequests: Set<String> = []
    @State private var hasMoreShorts: Bool = false
    @State private var nextShortsOffset: Int? = nil
    @State private var nextShortsCursor: Int64? = nil
    @State private var isLoadingMoreShorts: Bool = false
    private let profileItems: [ShortItem]?
    private let initialOpenComments: Bool

    private var isPlaybackPausedByModal: Bool {
        activeCommentShort != nil
            || activeOptionsShort != nil
            || selectedAuthorProfile != nil
            || appState.activeReportContext != nil
    }

    init(initialItems: [ShortItem]? = nil, initialShortID: String? = nil, initialOpenComments: Bool = false) {
        profileItems = initialItems
        self.initialOpenComments = initialOpenComments
        if let initialItems {
            let selected = initialItems.firstIndex { $0.id == initialShortID } ?? 0
            let ordered = Array(initialItems.dropFirst(selected)) + Array(initialItems.prefix(selected))
            _items = State(initialValue: ordered)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if items.isEmpty && isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                    Text("Đang tải video ngắn…")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty && !isLoading {
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
                                    shortVideoCard(item, at: index, containerWidth: geo.size.width)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .id(index)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .clipped()
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $currentIndex)
                    } else {
                        TabView(selection: $currentIndex) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                shortVideoCard(item, at: index, containerWidth: geo.size.width)
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
                }
            }

            // Top transparent floating bar (Đề xuất · Đang theo dõi) - hidden when viewing profile shorts
            if profileItems == nil {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 20) {
                        tabHeaderButton(id: "for", title: "Đề xuất")
                        tabHeaderButton(id: "following", title: "Đang theo dõi")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(red: 0x19 / 255.0, green: 0x14 / 255.0, blue: 0x30 / 255.0).opacity(0.84))
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    )
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
        }
        .task {
            await loadShorts()
            if initialOpenComments, activeCommentShort == nil, let first = items.first {
                activeCommentShort = first
            }
        }
        .onChange(of: currentIndex) { newIdx in
            isManuallyPaused = false
            guard profileItems == nil, let idx = newIdx else { return }
            if hasMoreShorts && !isLoadingMoreShorts && idx >= max(0, items.count - 2) {
                Task { await loadMoreShorts() }
            }
        }
        .onChange(of: appState.blockedUserIds) { blocked in
            if profileItems == nil {
                items.removeAll { blocked.contains($0.author.id) }
                clampCurrentIndex()
            }
        }
        .sheet(item: $activeCommentShort) { short in
            ShortCommentsSheet(
                short: short,
                onCountChanged: { count in
                    if let idx = items.firstIndex(where: { $0.id == short.id }) {
                        items[idx].commentsCount = count
                    }
                },
                onUpdated: {}
            )
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
                    let permalink = "https://app.kinnect.io.vn/share/short/\(short.id)"
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
                            KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textPrimary) {
                                selectedAuthorProfile = nil
                            }
                        }
                    }
            }
        }
    }

    private func tabHeaderButton(id: String, title: String) -> some View {
        let isSelected = shortsTab == id
        return Button {
            guard shortsTab != id else { return }
            shortsTab = id
            items = []
            currentIndex = 0
            hasMoreShorts = false
            nextShortsOffset = nil
            nextShortsCursor = nil
            Task { await loadShorts() }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.88))
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
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func shortVideoCard(_ item: ShortItem, at index: Int, containerWidth: CGFloat) -> some View {
        let activeIdx = currentIndex ?? 0
        let withinPlayerWindow = abs(index - activeIdx) <= 1
        let isPaused = (index == activeIdx) && isManuallyPaused
        let isCardActive = (index == activeIdx) && !isPlaybackPausedByModal && !isManuallyPaused
        return ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.black)
            if withinPlayerWindow {
                ShortClipPlayer(path: item.videoUrl, active: isCardActive, muted: isMuted)
                    .allowsHitTesting(false)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.08, blue: 0.32),
                            Color(red: 0.05, green: 0.03, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    if !item.thumbnailUrl.isEmpty {
                        KinnectRemoteImageView(rawURL: item.thumbnailUrl, contentMode: .fill, cornerRadius: 0, maxHeight: 1200)
                    }
                }
                .allowsHitTesting(false)
            }

            // Double tap detector for floating heart + single tap Play/Pause toggle
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2, coordinateSpace: .local) { location in
                    triggerDoubleTapHeart(at: index, point: location)
                }
                .onTapGesture(count: 1) {
                    guard index == (currentIndex ?? 0) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isManuallyPaused.toggle()
                    }
                }

            if isPaused {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.52))
                        .frame(width: 68, height: 68)
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))
                        .offset(x: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            // Floating hearts animation overlay
            ForEach(floatingHearts) { heart in
                HeartEffectView()
                    .position(x: heart.x, y: heart.y)
                    .allowsHitTesting(false)
            }

            // Right Action Column (Like, Comment, Share, More)
            HStack(alignment: .bottom, spacing: 10) {
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
                                .lineLimit(1)
                                .shadow(radius: 2)
                        }
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
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
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.bottom, 24)

                // Right Action Sidebar
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        Button { selectedAuthorProfile = item.author } label: {
                            KinnectAvatarView(name: item.author.name, avatarURL: item.author.avatarUrl,
                                              colorHex: item.author.avatarColor, size: 46)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if item.author.id != appState.currentUser?.id {
                            Button { Task { await toggleFollow(item.author) } } label: {
                                Image(systemName: item.author.isFollowed ? "checkmark" : "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(item.author.isFollowed ? KinnectTheme.accent : KinnectTheme.liveRed))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
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
                                size: 24,
                                selected: item.liked,
                                tint: item.liked ? Color(red: 1.0, green: 0x8D / 255.0, blue: 0xA1 / 255.0) : .white
                            )
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.78)))
                            Text("\(item.likesCount)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.liked ? "Bỏ thích video" : "Thích video")

                    // Comments button
                    Button {
                        activeCommentShort = item
                    } label: {
                        VStack(spacing: 4) {
                            KinnectIcon(glyph: .comment, size: 24, selected: true, tint: .white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.black.opacity(0.78)))
                            Text("\(item.commentsCount)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bình luận")

                    // Share button (icon-only for TikTok & Android parity)
                    Button {
                        let permalink = "https://app.kinnect.io.vn/share/short/\(item.id)"
                        UIPasteboard.general.string = permalink
                        appState.showToast("Đã sao chép liên kết video!")
                        let shareItems: [Any] = [URL(string: permalink) ?? permalink]
                        KinnectShareSheet.present(items: shareItems)
                    } label: {
                        KinnectIcon(glyph: .share, size: 24, tint: .white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.78)))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Chia sẻ video"))

                    // Options / More button (icon-only for TikTok & Android parity)
                    Button {
                        activeOptionsShort = item
                    } label: {
                        KinnectIcon(glyph: .more, size: 24, tint: .white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.78)))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Tùy chọn video"))
                }
                .frame(width: 52)
                .padding(.trailing, 14)
                .padding(.bottom, 28)
            }
            .frame(width: containerWidth)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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

    private func clampCurrentIndex() {
        if items.isEmpty {
            currentIndex = 0
        } else if let cur = currentIndex, cur >= items.count {
            currentIndex = max(0, items.count - 1)
        } else if currentIndex == nil {
            currentIndex = 0
        }
    }

    private func toggleLike(at index: Int) {
        guard index < items.count else { return }
        let current = items[index]
        let shortId = current.id
        let newLiked = !current.liked
        items[index].liked = newLiked
        items[index].likesCount = max(0, current.likesCount + (newLiked ? 1 : -1))

        Task {
            do {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts/\(shortId)/like",
                    method: newLiked ? "POST" : "DELETE"
                )
            } catch {
                // Revert by short.id on failure so index shifts never corrupt another video
                if let revertIdx = items.firstIndex(where: { $0.id == shortId }) {
                    items[revertIdx].liked = current.liked
                    items[revertIdx].likesCount = current.likesCount
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
            clampCurrentIndex()
            if let accountId = AccountCache.shared.activeAccountId, !accountId.isEmpty {
                AccountCache.shared.evict(forKey: "shorts_feed_for", accountId: accountId)
                AccountCache.shared.evict(forKey: "shorts_feed_following", accountId: accountId)
            }
            appState.showToast("Đã xoá video ngắn.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func loadShorts() async {
        if profileItems != nil { return }
        let requestedTab = shortsTab
        let cacheKey = "shorts_feed_\(requestedTab)"
        if let accountId = AccountCache.shared.activeAccountId {
            if let cached: [[String: Any]] = AccountCache.shared.loadJSONObject(forKey: cacheKey, accountId: accountId), items.isEmpty {
                self.items = cached.map(ShortItem.from).filter { !appState.blockedUserIds.contains($0.author.id) }
            }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts?feed=\(requestedTab)",
                method: "GET"
            )
            guard shortsTab == requestedTab else { return }
            if let arr = res["shorts"] as? [[String: Any]] {
                self.items = arr.map(ShortItem.from).filter { !appState.blockedUserIds.contains($0.author.id) }
                self.hasMoreShorts = (res["hasMore"] as? Bool) ?? false
                self.nextShortsOffset = (res["nextOffset"] as? NSNumber)?.intValue
                self.nextShortsCursor = (res["nextCursor"] as? NSNumber)?.int64Value
                clampCurrentIndex()
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

    private func loadMoreShorts() async {
        guard profileItems == nil, hasMoreShorts, !isLoadingMoreShorts else { return }
        let requestedTab = shortsTab
        let path: String
        if requestedTab == "following" {
            guard let cursor = nextShortsCursor else { return }
            path = "/api/shorts?feed=following&before=\(cursor)"
        } else {
            guard let offset = nextShortsOffset else { return }
            path = "/api/shorts?feed=\(requestedTab)&offset=\(offset)"
        }
        isLoadingMoreShorts = true
        defer { isLoadingMoreShorts = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(path, method: "GET")
            guard shortsTab == requestedTab else { return }
            let more = (res["shorts"] as? [[String: Any]] ?? [])
                .map(ShortItem.from)
                .filter { !appState.blockedUserIds.contains($0.author.id) }
            let existing = Set(items.map(\.id))
            items.append(contentsOf: more.filter { !existing.contains($0.id) })
            hasMoreShorts = (res["hasMore"] as? Bool) ?? false
            nextShortsOffset = (res["nextOffset"] as? NSNumber)?.intValue
            nextShortsCursor = (res["nextCursor"] as? NSNumber)?.int64Value
        } catch {
            // Silent on background page fetch; user can swipe again to retry
        }
    }
}

struct ShortClipPlayer: View {
    let path: String
    let active: Bool
    var muted: Bool = false
    @ObservedObject private var calls = NativeWebRTCManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var loading = false
    @State private var loopObserver: NSObjectProtocol?
    @State private var shouldPlay = false
    @State private var statusObserver: NSKeyValueObservation?
    @State private var loadTask: Task<Void, Never>? = nil

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
                    Button {
                        startLoad()
                    } label: {
                        Text(L10n.tr("Thử lại"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else if let player {
                ShortFillVideoPlayerView(player: player)
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
        .onAppear { startLoad() }
        .onChange(of: path) { _ in startLoad() }
        .onChange(of: active) { _ in syncPlayback() }
        .onChange(of: muted) { newMuted in
            player?.isMuted = newMuted
            syncPlayback()
        }
        .onChange(of: scenePhase) { _ in syncPlayback() }
        .onChange(of: calls.activeCall != nil) { _ in syncPlayback() }
        .onDisappear { stop() }
    }

    private func startLoad() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    private func load() async {
        resetPlayer()
        guard !path.isEmpty else {
            failed = false
            return
        }
        failed = false
        loading = true
        defer { loading = false }

        if path.hasPrefix("file://"), let localURL = URL(string: path) {
            setupPlayer(with: AVPlayerItem(url: localURL))
            return
        }

        // 1. Try playing from authenticated media cache (fast, reliable, no AVURLAsset cookie dropping on iOS)
        if path.hasPrefix("/api/") || path.hasPrefix("/") || path.contains("app.kinnect.io.vn") {
            let cachedLocalURL = try? await KinnectAuthenticatedFile.fetch(path: path, fileExtension: "mp4")
            guard !Task.isCancelled else { return }
            if let cachedLocalURL {
                setupPlayer(with: AVPlayerItem(url: cachedLocalURL))
                return
            }
        }
        guard !Task.isCancelled else { return }

        // 2. Direct streaming fallback with cookie jar
        let origin = KinnectAPIClient.shared.mediaOrigin
        KeychainStore.shared.syncToHTTPCookieStorage(origin: origin)
        guard let remoteURL = ServerConfig.url(for: path, origin: origin) else {
            #if DEBUG
            if UIReviewFixture.isEnabled, let fixtureURL = UIReviewFixture.samplePlayableVideoURL() {
                setupPlayer(with: AVPlayerItem(url: fixtureURL))
                return
            }
            #endif
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
        guard !Task.isCancelled else { return }
        let next = AVPlayer(playerItem: item)
        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak next] item, _ in
            let status = item.status
            Task { @MainActor in
                switch status {
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
        ) { [weak next] _ in
            Task { @MainActor in
                guard let next else { return }
                next.seek(to: .zero)
                if shouldPlay { next.play() }
            }
        }
        player = next
        syncPlayback()
    }

    private func syncPlayback() {
        let blocked = !active || scenePhase != .active || calls.activeCall != nil
        shouldPlay = !blocked
        guard let player else { return }
        if blocked {
            player.pause()
        } else {
            // Only claim audio playback session when actively playing unmuted
            if !muted && calls.activeCall == nil && calls.liveLocalVideoTrack == nil {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            player.play()
        }
    }

    private func resetPlayer() {
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

    private func stop() {
        loadTask?.cancel()
        loadTask = nil
        resetPlayer()
    }
}

struct ShortCommentsSheet: View {
    let short: ShortItem
    var onCountChanged: ((Int) -> Void)? = nil
    let onUpdated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var comments: [CommentItem] = []
    @State private var text = ""
    @State private var replyingTo: CommentItem? = nil
    @State private var reactionPickerCommentId: String? = nil
    @State private var pendingCommentReactions: Set<String> = []
    @State private var editingComment: CommentItem? = nil
    @State private var editingCommentText = ""
    @State private var pendingDeleteComment: CommentItem? = nil
    @State private var isPosting = false

    private let quickEmojis = ["😍", "😂", "🔥", "👏", "🥰", "😮", "😢", "💜"]

    private let commentReactionOptions: [(key: String, emoji: String, title: String)] = [
        ("like", "👍", "Thích"),
        ("love", "❤️", "Yêu thích"),
        ("haha", "😆", "Haha"),
        ("wow", "😮", "Wow"),
        ("sad", "😢", "Buồn"),
        ("angry", "😡", "Phẫn nộ")
    ]

    private struct ShortCommentRow: Identifiable {
        let comment: CommentItem
        let depth: Int
        let parentAuthorName: String?
        var id: String { comment.id }
    }

    private var commentRows: [ShortCommentRow] {
        let ids = Set(comments.map(\.id))
        let children = Dictionary(grouping: comments, by: { $0.parentId ?? "" })
        var visited = Set<String>()
        var rows: [ShortCommentRow] = []
        func appendThread(_ start: CommentItem) {
            var stack: [(CommentItem, Int, String?)] = [(start, 0, nil)]
            while let (comment, depth, parentName) = stack.popLast() {
                guard visited.insert(comment.id).inserted else { continue }
                rows.append(ShortCommentRow(comment: comment, depth: depth, parentAuthorName: parentName))
                for child in (children[comment.id] ?? []).reversed() {
                    stack.append((child, depth + 1, comment.author.name))
                }
            }
        }
        // Top-level comments + orphaned replies whose parentId is not in list
        for comment in comments where comment.parentId == nil || comment.parentId?.isEmpty == true || !ids.contains(comment.parentId ?? "") {
            appendThread(comment)
        }
        // Safety pass for malformed cycles
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
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(commentRows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    Divider()
                                        .background(KinnectTheme.borderSoft)
                                        .padding(.leading, 58)
                                }
                                commentRowView(row.comment, depth: min(row.depth, 1), parentAuthorName: row.parentAuthorName)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                    .background(KinnectTheme.surface)
                    .clipped()
                }

                // Quick emoji reaction bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(quickEmojis, id: \.self) { emoji in
                            Button {
                                text.append(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.title3)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(emoji)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                }
                .clipped()
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
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Hủy"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(KinnectTheme.surfaceElevated)
                }

                // Composer input row
                let canSend = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $text,
                        prompt: Text(replyingTo != nil ? "\(L10n.tr("Trả lời")) \(replyingTo!.author.name)..." : L10n.tr("Viết bình luận..."))
                            .foregroundColor(KinnectTheme.inputPlaceholder)
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)

                    Button {
                        guard canSend else { return }
                        Task { await postComment() }
                    } label: {
                        KinnectIcon(glyph: .send, size: 20, selected: true, tint: canSend ? .white : KinnectTheme.textSecondary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(canSend ? KinnectTheme.accent : KinnectTheme.surfaceElevated))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPosting)
                    .accessibilityLabel(L10n.tr("Gửi bình luận"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(KinnectTheme.surface)
            }
            .background(KinnectTheme.surface)
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
                            let canSaveEdit = !editingCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            Button(L10n.tr("Lưu")) {
                                guard canSaveEdit else { return }
                                Task { await saveEditedComment(comment) }
                            }
                            .foregroundColor(canSaveEdit ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .presentationDetents([.medium, .large])
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
                        .lineLimit(1)

                    if let parent = parentAuthorName, depth > 0 {
                        Text("▸ \(parent)")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.accentBright)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

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
                                .frame(minWidth: 44, minHeight: 44)
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
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }
                }

                Text(c.text)
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .kinnectMultiline()

                // Action bar: Timestamp, Trả lời, Thả cảm xúc (6-reaction picker + quick love/like)
                HStack(spacing: 14) {
                    Text(formatRelativeDate(c.createdAt))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .lineLimit(1)

                    Button {
                        replyingTo = replyRoot(for: c)
                    } label: {
                        Text(L10n.tr("Trả lời"))
                            .font(.caption2.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
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
                                Text(L10n.tr(matched.title))
                                    .font(.caption2.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            } else {
                                Text("❤️")
                                    .font(.caption)
                                Text(L10n.tr("Cảm xúc"))
                                    .font(.caption2.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            if c.likesCount > 0 {
                                Text("· \(c.likesCount)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(c.liked ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(pendingCommentReactions.contains(c.id))
                    .contextMenu {
                        ForEach(commentReactionOptions, id: \.key) { option in
                            Button {
                                setCommentReaction(c, reaction: option.key)
                            } label: {
                                Text("\(option.emoji) \(L10n.tr(option.title))")
                            }
                        }
                        if c.liked {
                            Button(L10n.tr("Gỡ cảm xúc"), role: .destructive) {
                                setCommentReaction(c, reaction: nil)
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .overlay(alignment: .topLeading) {
                    if reactionPickerCommentId == c.id {
                        HStack(spacing: 2) {
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
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(
                                            Circle()
                                                .fill(c.myReaction == option.key ? KinnectTheme.accentBright.opacity(0.22) : Color.clear)
                                                .frame(width: 34, height: 34)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.tr(option.title))
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
        .zIndex(reactionPickerCommentId == c.id ? 25 : 0)
    }

    private func setCommentReaction(_ item: CommentItem, reaction: String?) {
        guard !pendingCommentReactions.contains(item.id) else { return }
        pendingCommentReactions.insert(item.id)
        Task {
            defer { pendingCommentReactions.remove(item.id) }
            do {
                let response = try await KinnectAPIClient.shared.requestJSON(
                    "/api/shorts/\(short.id)/comments/\(item.id)/reaction",
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

    private func saveEditedComment(_ item: CommentItem) async {
        let clean = editingCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts/\(short.id)/comments/\(item.id)",
                method: "PATCH",
                body: ["body": clean]
            )
            editingComment = nil
            await load()
            onUpdated()
            appState.showToast(L10n.tr("Đã cập nhật bình luận."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deleteComment(_ item: CommentItem) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts/\(short.id)/comments/\(item.id)",
                method: "DELETE",
                body: [:],
                requestId: "del_short_cmt_\(item.id)"
            )
            await load()
            onCountChanged?(comments.count)
            onUpdated()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func load() async {
        if comments.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/shorts/\(short.id)/comments"),
           let list = cached["comments"] as? [[String: Any]] {
            self.comments = list.map(CommentItem.from)
        }
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
            onCountChanged?(comments.count)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirm = false
    @State private var isSavingVideo = false

    private var destructiveLabelColor: Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 0xFF / 255.0, green: 0x8D / 255.0, blue: 0xA1 / 255.0, opacity: 1.0)
            : Color(.sRGB, red: 0xA3 / 255.0, green: 0x1E / 255.0, blue: 0x43 / 255.0, opacity: 1.0)
    }

    private static let destructiveBadgeFill = Color(
        .sRGB,
        red: 0xB9 / 255.0,
        green: 0x1C / 255.0,
        blue: 0x47 / 255.0,
        opacity: 1.0
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Horizontal scrolling options buttons row (Android parity: tiktokOptionBtn)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        optionTile(
                            icon: isSavingVideo ? "arrow.down.circle" : "arrow.down.circle.fill",
                            label: isSavingVideo ? L10n.tr("Đang lưu…") : L10n.tr("Lưu video")
                        ) {
                            guard !isSavingVideo else { return }
                            Task { await downloadAndSaveVideo() }
                        }

                        optionTile(icon: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: isMuted ? "Bật âm" : "Tắt âm") {
                            dismiss()
                            onMuteToggle()
                        }

                        optionTile(icon: isMine ? "trash.fill" : "flag.fill", label: isMine ? "Xoá video" : "Báo cáo", isDestructive: isMine) {
                            if isMine {
                                showDeleteConfirm = true
                            } else {
                                dismiss()
                                onReport()
                            }
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
                .clipped()

                Spacer()
            }
            .padding(.top, 16)
            .background(KinnectTheme.background)
            .navigationTitle("Tùy chọn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .alert(L10n.tr("Xoá video ngắn?"), isPresented: $showDeleteConfirm) {
                Button(L10n.tr("Xoá video"), role: .destructive) {
                    dismiss()
                    onDelete()
                }
                Button(L10n.tr("Hủy"), role: .cancel) {}
            } message: {
                Text(L10n.tr("Video ngắn đã xoá sẽ không thể khôi phục."))
            }
        }
        .presentationDetents([.height(180)])
    }

    private func optionTile(icon: String, label: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isDestructive ? Self.destructiveBadgeFill : KinnectTheme.surfaceElevated)
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(isDestructive ? .white : KinnectTheme.accentBright)
                }
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isDestructive ? destructiveLabelColor : KinnectTheme.textPrimary)
                    .lineLimit(1)
            }
            .frame(minWidth: 72, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func downloadAndSaveVideo() async {
        isSavingVideo = true
        defer { isSavingVideo = false }
        do {
            let localURL = try await KinnectAuthenticatedFile.fetch(path: item.videoUrl, fileExtension: "mp4")
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if status == .authorized || status == .limited {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL)
                }
                AppState.shared.showToast(L10n.tr("Đã lưu video vào thư viện Ảnh!"))
                dismiss()
            } else {
                dismiss()
                KinnectShareSheet.present(items: [localURL])
                AppState.shared.showToast(L10n.tr("Chọn lưu tệp video trong bảng chia sẻ."))
            }
        } catch {
            AppState.shared.showToast(error.localizedDescription)
        }
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

/// Edge-to-edge AVPlayerLayer renderer (`resizeAspectFill`) so Shorts & Live videos
/// fill the full vertical viewport without black letterbox bars.
private struct ShortFillVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            layer as! AVPlayerLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            clipsToBounds = true
            playerLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != .resizeAspectFill {
            uiView.playerLayer.videoGravity = .resizeAspectFill
        }
    }
}
