import AVFoundation
import AVKit
import Combine
import SwiftUI
import UIKit

@MainActor
final class ShortsFeedPlaybackState: ObservableObject {
    @Published var activeIndex: Int? = 0
    @Published var isMuted: Bool = false
    @Published var userPaused: Bool = false
}

struct ShortsVideoView: View {
    @ObservedObject private var appState = AppState.shared
    @StateObject private var playbackState = ShortsFeedPlaybackState()
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
                    let bottomSafeInset = geo.safeAreaInsets.bottom
                    if #available(iOS 17.0, *) {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                    shortVideoCard(item, at: index, bottomSafeInset: bottomSafeInset)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                }
                            }
                            .scrollTargetLayout()
                            .background(
                                GeometryReader { contentGeo in
                                    Color.clear.preference(
                                        key: ShortsScrollOffsetKey.self,
                                        value: contentGeo.frame(in: .named("shortsScrollArea")).minY
                                    )
                                }
                            )
                            .background(
                                ShortsScrollObserver(
                                    pageHeight: geo.size.height,
                                    itemCount: items.count,
                                    onPageSettled: { nearest in
                                        if currentIndex != nearest {
                                            currentIndex = nearest
                                        }
                                        if playbackState.activeIndex != nearest {
                                            playbackState.activeIndex = nearest
                                        }
                                    }
                                )
                            )
                        }
                        .coordinateSpace(name: "shortsScrollArea")
                        .contentMargins(0, for: .scrollContent)
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $currentIndex)
                        .ignoresSafeArea()
                        .onPreferenceChange(ShortsScrollOffsetKey.self) { minY in
                            guard geo.size.height > 100 else { return }
                            let progress = Double(-minY / geo.size.height)
                            let nearest = Int(progress.rounded())
                            if nearest >= 0,
                               nearest < items.count,
                               abs(progress - Double(nearest)) < 0.08 {
                                if currentIndex != nearest {
                                    currentIndex = nearest
                                }
                                if playbackState.activeIndex != nearest {
                                    playbackState.activeIndex = nearest
                                }
                            }
                        }
                    } else {
                        TabView(selection: $currentIndex) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                shortVideoCard(item, at: index, bottomSafeInset: bottomSafeInset)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .rotationEffect(.degrees(-90))
                                    .tag(Optional(index))
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(width: geo.size.height, height: geo.size.width)
                        .rotationEffect(.degrees(90))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .ignoresSafeArea()
                    }
                }
                .ignoresSafeArea()
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
        .onChange(of: currentIndex) { next in
            userPaused = false
            playbackState.userPaused = false
            playbackState.activeIndex = next ?? 0
        }
        .onChange(of: isMuted) { next in
            playbackState.isMuted = next
        }
        .onChange(of: userPaused) { next in
            playbackState.userPaused = next
        }
        .task {
            playbackState.activeIndex = currentIndex ?? 0
            playbackState.isMuted = isMuted
            playbackState.userPaused = userPaused
            await loadShorts()
            #if DEBUG
            if UIReviewFixture.activeScreen == "shorts-real-swipe" {
                await runRealSwipeProof()
            }
            #endif
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
            playbackState.activeIndex = 0
            userPaused = false
            playbackState.userPaused = false
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

    private func shortVideoCard(_ item: ShortItem, at index: Int, bottomSafeInset: CGFloat = 0) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.black)
            ShortClipPlayer(
                path: item.videoUrl,
                active: index == currentIndex,
                muted: isMuted,
                userPaused: userPaused && index == currentIndex,
                feedIndex: index,
                feedState: playbackState
            )
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
                .padding(.bottom, max(24, bottomSafeInset + 12))

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
                .padding(.bottom, max(28, bottomSafeInset + 16))
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

    #if DEBUG
    @MainActor
    private func runRealSwipeProof() async {
        let start = Date()
        var e0: UIReviewFixture.ShortsRealSwipeObserver.Entry? = nil
        while Date().timeIntervalSince(start) < 5.0 {
            if items.count >= 2,
               let entry = UIReviewFixture.ShortsRealSwipeObserver.shared.entry(for: items[0].videoUrl),
               entry.item.status == .readyToPlay,
               entry.player.rate > 0,
               entry.player.currentTime().seconds.isFinite,
               entry.player.currentTime().seconds > 0.20 {
                e0 = entry
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let beforeIndex = currentIndex ?? -1
        let beforeId = (beforeIndex >= 0 && beforeIndex < items.count) ? items[beforeIndex].id : ""
        let item0Player = e0?.player
        let item0RateBefore = Double(item0Player?.rate ?? 0)
        let item0TimeBefore = item0Player?.currentTime().seconds ?? 0
        var frame1 = UIReviewFixture.AVBufferSample()
        if let e0 {
            (frame1, _) = await UIReviewFixture.sampleVideoFrame(output: e0.output, item: e0.item, fileName: "shorts-real-swipe-frame-1.png")
        }

        let sv = UIReviewFixture.findVerticalPagingScrollView()
        let scrollOffsetBefore = Double(sv?.contentOffset.y ?? -1)
        let pageHeight = Double(sv?.bounds.height ?? 0)
        let isPagingEnabled = sv?.isPagingEnabled ?? false
        if let sv, pageHeight > 100 {
            let targetY = CGFloat(pageHeight) - sv.adjustedContentInset.top
            sv.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
        }

        try? await Task.sleep(nanoseconds: 1_600_000_000)

        var e1: UIReviewFixture.ShortsRealSwipeObserver.Entry? = nil
        let secondWaitStart = Date()
        while Date().timeIntervalSince(secondWaitStart) < 3.0 {
            if items.count >= 2,
               let entry = UIReviewFixture.ShortsRealSwipeObserver.shared.entry(for: items[1].videoUrl),
               entry.item.status == .readyToPlay,
               entry.player.rate > 0,
               entry.player.currentTime().seconds.isFinite,
               entry.player.currentTime().seconds > 0.20 {
                e1 = entry
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        let latestE1 = e1 ?? UIReviewFixture.ShortsRealSwipeObserver.shared.entry(for: items[1].videoUrl)
        let scrollOffsetAfter = Double(sv?.contentOffset.y ?? -1)
        let afterIndex = currentIndex ?? -1
        let afterId = (afterIndex >= 0 && afterIndex < items.count) ? items[afterIndex].id : ""
        let item0TimeCheck1 = item0Player?.currentTime().seconds ?? 0
        try? await Task.sleep(nanoseconds: 250_000_000)
        let item0TimeCheck2 = item0Player?.currentTime().seconds ?? 0
        let item0RateAfter = Double(item0Player?.rate ?? -1)
        let item0HeldPaused = item0RateAfter == 0 && abs(item0TimeCheck2 - item0TimeCheck1) < 0.08

        let item1RateAfter = Double(latestE1?.player.rate ?? 0)
        var frame2 = UIReviewFixture.AVBufferSample()
        if let sampleTarget = latestE1 {
            (frame2, _) = await UIReviewFixture.sampleVideoFrame(output: sampleTarget.output, item: sampleTarget.item, fileName: "shorts-real-swipe-frame-2.png")
        }

        let item0Lifecycle = UIReviewFixture.ShortsRealSwipeObserver.shared.lifecycleDictionary(for: items[0].videoUrl)
        let item1Lifecycle = items.count >= 2 ? UIReviewFixture.ShortsRealSwipeObserver.shared.lifecycleDictionary(for: items[1].videoUrl) : [:]
        let distinct = frame1.received && frame2.received && (frame1.red != frame2.red || frame1.green != frame2.green || frame1.blue != frame2.blue)
        let payload: [String: Any] = [
            "realShortsView": true,
            "itemCount": items.count,
            "items": items.map { item in
                [
                    "id": item.id,
                    "title": item.title,
                    "videoFile": URL(string: item.videoUrl)?.lastPathComponent ?? item.videoUrl
                ]
            },
            "swipeMethod": "uiscrollview-animated-paging",
            "gestureType": "programmatic-setContentOffset-animated",
            "scrollViewFound": sv != nil,
            "isPagingEnabled": isPagingEnabled,
            "pageHeight": pageHeight,
            "scrollOffsetYBefore": scrollOffsetBefore,
            "scrollOffsetYAfter": scrollOffsetAfter,
            "selectedIndexBefore": beforeIndex,
            "selectedIndexAfter": afterIndex,
            "selectedIdBefore": beforeId,
            "selectedIdAfter": afterId,
            "scrollDrivenIndexChanged": (beforeIndex == 0 && afterIndex == 1 && afterId == "fixture_short_2"),
            "item0RateBefore": item0RateBefore,
            "item0TimeBefore": item0TimeBefore.isFinite ? item0TimeBefore : 0,
            "item0RateAfter": item0RateAfter,
            "item0HeldPaused": item0HeldPaused,
            "item1PresentAfter": latestE1 != nil,
            "item1ActiveAfter": e1 != nil && item1RateAfter > 0,
            "item1RateAfter": item1RateAfter,
            "item0Lifecycle": item0Lifecycle,
            "item1Lifecycle": item1Lifecycle,
            "frame1": [
                "received": frame1.received,
                "width": frame1.width,
                "height": frame1.height,
                "timeSeconds": frame1.time,
                "r": frame1.red,
                "g": frame1.green,
                "b": frame1.blue,
                "frameSaved": frame1.frameSaved,
                "frameFile": frame1.frameFile
            ],
            "frame2": [
                "received": frame2.received,
                "width": frame2.width,
                "height": frame2.height,
                "timeSeconds": frame2.time,
                "r": frame2.red,
                "g": frame2.green,
                "b": frame2.blue,
                "frameSaved": frame2.frameSaved,
                "frameFile": frame2.frameFile
            ],
            "framesPixelDistinct": distinct
        ]
        UIReviewFixture.writeDocument("shorts-real-swipe.json", payload)
    }
    #endif
}

@MainActor
private final class ClipPlaybackController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published var failed = false
    @Published var loading = false

    private var isMounted = false
    private var isAppActive: Bool = UIApplication.shared.applicationState != .background
    private var shouldPlay = false
    private var currentToken = UUID()
    private var currentPlayerId = ""
    private var currentPath = ""
    private var directActive = false
    private var directMuted = false
    private var directUserPaused = false
    private var feedIndex: Int?
    private weak var feedState: ShortsFeedPlaybackState?
    private weak var observedFeedState: ShortsFeedPlaybackState?
    private var statusObserver: NSKeyValueObservation?
    private var globalCancellables: Set<AnyCancellable> = []
    private var feedCancellables: Set<AnyCancellable> = []
    private var playerCancellables: Set<AnyCancellable> = []

    func bind(
        path: String,
        active: Bool,
        muted: Bool,
        userPaused: Bool,
        feedIndex: Int?,
        feedState: ShortsFeedPlaybackState?,
        trigger: String
    ) {
        let activeChanged = (directActive != active)
        currentPath = path
        directActive = active
        directMuted = muted
        directUserPaused = userPaused
        self.feedIndex = feedIndex
        self.feedState = feedState
        isMounted = true
        isAppActive = UIApplication.shared.applicationState != .background

        if globalCancellables.isEmpty {
            NativeWebRTCManager.shared.$activeCall
                .sink { [weak self] nextCall in
                    self?.syncPlayback(trigger: "callState", overrideHasCall: nextCall != nil)
                }
                .store(in: &globalCancellables)
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
                .sink { [weak self] _ in
                    self?.isAppActive = true
                    self?.syncPlayback(trigger: "didBecomeActive")
                }
                .store(in: &globalCancellables)
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
                .sink { [weak self] _ in
                    self?.isAppActive = false
                    self?.syncPlayback(trigger: "willResignActive")
                }
                .store(in: &globalCancellables)
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in
                    self?.isAppActive = false
                    self?.syncPlayback(trigger: "didEnterBackground")
                }
                .store(in: &globalCancellables)
        }

        if observedFeedState !== feedState {
            feedCancellables.removeAll()
            observedFeedState = feedState
            if let feedState {
                feedState.$activeIndex
                    .sink { [weak self] nextIdx in
                        self?.syncPlayback(trigger: "feedActiveIndex", overrideActiveIndex: .some(nextIdx))
                    }
                    .store(in: &feedCancellables)
                feedState.$userPaused
                    .sink { [weak self] nextPaused in
                        self?.syncPlayback(trigger: "feedUserPaused", overrideUserPaused: nextPaused)
                    }
                    .store(in: &feedCancellables)
                feedState.$isMuted
                    .sink { [weak self] nextMuted in
                        self?.syncPlayback(trigger: "feedMuted", overrideMuted: nextMuted)
                    }
                    .store(in: &feedCancellables)
            }
        }

        if activeChanged && trigger == "onChangeActive" {
            syncPlayback(trigger: "onChangeActive")
        } else {
            syncPlayback(trigger: trigger)
        }
    }

    func load(
        path: String,
        active: Bool,
        muted: Bool,
        userPaused: Bool,
        feedIndex: Int?,
        feedState: ShortsFeedPlaybackState?
    ) async {
        bind(
            path: path,
            active: active,
            muted: muted,
            userPaused: userPaused,
            feedIndex: feedIndex,
            feedState: feedState,
            trigger: "loadStart"
        )
        prepareForReload()
        guard !path.isEmpty else {
            failed = false
            return
        }
        failed = false
        loading = true
        defer { loading = false }

        if NativeWebRTCManager.shared.activeCall == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }

        if path.hasPrefix("file://"), let localURL = URL(string: path) {
            setupPlayer(with: AVPlayerItem(url: localURL), expectedPath: path)
            return
        }

        let origin = KinnectAPIClient.shared.mediaOrigin
        if let resolved = ServerConfig.url(for: path, origin: origin),
           ServerConfig.matchesOrigin(resolved, origin: origin) {
            if let cachedLocalURL = try? await KinnectAuthenticatedFile.fetch(path: path, fileExtension: "mp4") {
                guard !Task.isCancelled, isMounted, currentPath == path else { return }
                setupPlayer(with: AVPlayerItem(url: cachedLocalURL), expectedPath: path)
                return
            }
            guard !Task.isCancelled, isMounted, currentPath == path else { return }
        }

        KeychainStore.shared.syncToHTTPCookieStorage(origin: origin)
        guard let remoteURL = ServerConfig.url(for: path, origin: origin) else {
            #if DEBUG
            if UIReviewFixture.isEnabled, let fixtureURL = UIReviewFixture.samplePlayableVideoURL() {
                setupPlayer(with: AVPlayerItem(url: fixtureURL), expectedPath: path)
                return
            }
            #endif
            clearPlayerInstance(keepMounted: true)
            failed = true
            loading = false
            return
        }

        let cookie = KeychainStore.shared.cookieJarHeader(for: origin)
        var options: [String: Any] = [:]
        if !cookie.isEmpty, ServerConfig.matchesOrigin(remoteURL, origin: origin) {
            options["AVURLAssetHTTPHeaderFieldsKey"] = ["Cookie": cookie]
        }

        let asset = AVURLAsset(url: remoteURL, options: options)
        let item = AVPlayerItem(asset: asset)
        setupPlayer(with: item, expectedPath: path)
    }

    private func setupPlayer(with item: AVPlayerItem, expectedPath: String) {
        guard isMounted, currentPath == expectedPath else { return }
        clearPlayerInstance(keepMounted: true)

        let token = UUID()
        let pid = String(token.uuidString.prefix(8))
        currentToken = token
        currentPlayerId = pid

        let next = AVPlayer(playerItem: item)
        #if DEBUG
        if UIReviewFixture.activeScreen == "shorts-real-swipe" {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
            item.add(output)
            UIReviewFixture.ShortsRealSwipeObserver.shared.register(
                path: expectedPath,
                playerId: pid,
                player: next,
                item: item,
                output: output
            )
        }
        #endif

        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self, weak next] observedItem, _ in
            Task { @MainActor [weak self, weak next] in
                guard let self,
                      let next,
                      self.isMounted,
                      self.currentToken == token,
                      self.player === next else {
                    next?.pause()
                    #if DEBUG
                    if UIReviewFixture.activeScreen == "shorts-real-swipe" {
                        UIReviewFixture.ShortsRealSwipeObserver.shared.recordEvent(
                            path: expectedPath,
                            event: "obsoleteRestartBlocked",
                            playerId: pid,
                            rate: next.map { Double($0.rate) } ?? 0
                        )
                    }
                    #endif
                    return
                }
                switch observedItem.status {
                case .readyToPlay:
                    self.failed = false
                    self.loading = false
                    self.syncPlayback(trigger: "readyToPlay")
                case .failed:
                    self.failed = true
                    self.loading = false
                default:
                    break
                }
            }
        }

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak next] _ in
                guard let self,
                      let next,
                      self.isMounted,
                      self.currentToken == token,
                      self.player === next else {
                    next?.pause()
                    #if DEBUG
                    if UIReviewFixture.activeScreen == "shorts-real-swipe" {
                        UIReviewFixture.ShortsRealSwipeObserver.shared.recordEvent(
                            path: expectedPath,
                            event: "obsoleteRestartBlocked",
                            playerId: pid,
                            rate: next.map { Double($0.rate) } ?? 0
                        )
                    }
                    #endif
                    return
                }
                next.seek(to: .zero)
                self.syncPlayback(trigger: "didPlayToEnd")
            }
            .store(in: &playerCancellables)

        player = next
        syncPlayback(trigger: "setupPlayer")
    }

    func syncPlayback(
        trigger: String,
        overrideActiveIndex: Int?? = nil,
        overrideUserPaused: Bool? = nil,
        overrideMuted: Bool? = nil,
        overrideHasCall: Bool? = nil
    ) {
        let effectiveActive: Bool
        if let feedState, let feedIndex {
            let idx = overrideActiveIndex ?? feedState.activeIndex
            effectiveActive = (idx == feedIndex)
        } else {
            effectiveActive = directActive
        }

        let effectiveUserPaused: Bool
        if let feedState, let feedIndex {
            let idx = overrideActiveIndex ?? feedState.activeIndex
            let paused = overrideUserPaused ?? feedState.userPaused
            effectiveUserPaused = paused && (idx == feedIndex)
        } else {
            effectiveUserPaused = directUserPaused
        }

        let effectiveMuted = overrideMuted ?? (feedState?.isMuted ?? directMuted)
        let hasCall = overrideHasCall ?? (NativeWebRTCManager.shared.activeCall != nil)
        let blocked = !isMounted || !effectiveActive || !isAppActive || hasCall || effectiveUserPaused
        shouldPlay = !blocked

        if let player {
            player.isMuted = effectiveMuted
            if blocked {
                player.pause()
            } else {
                player.play()
            }
        }

        #if DEBUG
        if UIReviewFixture.activeScreen == "shorts-real-swipe", !currentPath.isEmpty {
            UIReviewFixture.ShortsRealSwipeObserver.shared.recordEvent(
                path: currentPath,
                event: trigger,
                playerId: currentPlayerId,
                active: effectiveActive,
                userPaused: effectiveUserPaused,
                isAppActive: isAppActive,
                shouldPlay: shouldPlay,
                rate: player.map { Double($0.rate) }
            )
        }
        #endif
    }

    func prepareForReload() {
        clearPlayerInstance(keepMounted: true)
    }

    func teardown() {
        #if DEBUG
        if UIReviewFixture.activeScreen == "shorts-real-swipe", !currentPath.isEmpty {
            UIReviewFixture.ShortsRealSwipeObserver.shared.recordEvent(
                path: currentPath,
                event: "onDisappear",
                playerId: currentPlayerId,
                active: false,
                shouldPlay: false,
                rate: 0
            )
        }
        #endif
        clearPlayerInstance(keepMounted: false)
        feedCancellables.removeAll()
        observedFeedState = nil
        globalCancellables.removeAll()
    }

    private func clearPlayerInstance(keepMounted: Bool) {
        let deadPath = currentPath
        let deadPid = currentPlayerId
        currentToken = UUID()
        isMounted = keepMounted
        shouldPlay = false
        statusObserver?.invalidate()
        statusObserver = nil
        playerCancellables.removeAll()
        player?.pause()
        player = nil
        currentPlayerId = ""
        #if DEBUG
        if UIReviewFixture.activeScreen == "shorts-real-swipe", !deadPath.isEmpty, !deadPid.isEmpty {
            UIReviewFixture.ShortsRealSwipeObserver.shared.unregister(path: deadPath, playerId: deadPid)
        }
        #endif
    }
}

struct ShortClipPlayer: View {
    let path: String
    let active: Bool
    var muted: Bool = false
    var userPaused: Bool = false
    var feedIndex: Int? = nil
    var feedState: ShortsFeedPlaybackState? = nil
    @StateObject private var controller = ClipPlaybackController()

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

            if controller.failed {
                VStack(spacing: 12) {
                    Text("Không thể phát video.").foregroundColor(.white)
                    Button("Thử lại") {
                        Task {
                            await controller.load(
                                path: path,
                                active: active,
                                muted: muted,
                                userPaused: userPaused,
                                feedIndex: feedIndex,
                                feedState: feedState
                            )
                        }
                    }
                    .tint(.white)
                }
            } else if let player = controller.player {
                VideoPlayer(player: player)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            } else if controller.loading {
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
        .task(id: path) {
            await controller.load(
                path: path,
                active: active,
                muted: muted,
                userPaused: userPaused,
                feedIndex: feedIndex,
                feedState: feedState
            )
        }
        .onAppear {
            controller.bind(
                path: path,
                active: active,
                muted: muted,
                userPaused: userPaused,
                feedIndex: feedIndex,
                feedState: feedState,
                trigger: "onAppear"
            )
        }
        .onChange(of: active) { nextActive in
            controller.bind(
                path: path,
                active: nextActive,
                muted: muted,
                userPaused: userPaused,
                feedIndex: feedIndex,
                feedState: feedState,
                trigger: "onChangeActive"
            )
        }
        .onChange(of: muted) { nextMuted in
            controller.bind(
                path: path,
                active: active,
                muted: nextMuted,
                userPaused: userPaused,
                feedIndex: feedIndex,
                feedState: feedState,
                trigger: "onChangeMuted"
            )
        }
        .onChange(of: userPaused) { nextPaused in
            controller.bind(
                path: path,
                active: active,
                muted: muted,
                userPaused: nextPaused,
                feedIndex: feedIndex,
                feedState: feedState,
                trigger: "onChangeUserPaused"
            )
        }
        .onDisappear { controller.teardown() }
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

private struct ShortsScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ShortsScrollObserver: UIViewRepresentable {
    let pageHeight: CGFloat
    let itemCount: Int
    let onPageSettled: (Int) -> Void

    final class Coordinator {
        var observation: NSKeyValueObservation?
        var pageHeight: CGFloat = 0
        var itemCount: Int = 0
        var onPageSettled: (Int) -> Void
        weak var scrollView: UIScrollView?

        init(onPageSettled: @escaping (Int) -> Void) {
            self.onPageSettled = onPageSettled
        }

        deinit {
            observation?.invalidate()
        }

        func attach(to view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                var ancestor = view.superview
                while let current = ancestor {
                    if let sv = current as? UIScrollView {
                        if self.scrollView !== sv {
                            self.observation?.invalidate()
                            self.scrollView = sv
                            self.observation = sv.observe(\.contentOffset, options: [.initial, .new]) { [weak self] sv, _ in
                                guard let self else { return }
                                let h = self.pageHeight > 100 ? self.pageHeight : sv.bounds.height
                                guard h > 100, self.itemCount > 0 else { return }
                                let effectiveY = sv.contentOffset.y + sv.adjustedContentInset.top
                                let progress = Double(effectiveY / h)
                                let nearest = Int(progress.rounded())
                                if nearest >= 0, nearest < self.itemCount, abs(progress - Double(nearest)) < 0.08 {
                                    DispatchQueue.main.async { [weak self] in
                                        self?.onPageSettled(nearest)
                                    }
                                }
                            }
                        }
                        break
                    }
                    ancestor = current.superview
                }
            }
        }
    }

    private final class ObserverHostView: UIView {
        var onAttach: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onAttach?()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onAttach?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageSettled: onPageSettled)
    }

    func makeUIView(context: Context) -> UIView {
        let view = ObserverHostView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.pageHeight = pageHeight
        context.coordinator.itemCount = itemCount
        context.coordinator.onPageSettled = onPageSettled
        view.onAttach = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.attach(to: view)
        }
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.pageHeight = pageHeight
        context.coordinator.itemCount = itemCount
        context.coordinator.onPageSettled = onPageSettled
        context.coordinator.attach(to: uiView)
    }
}
