import SwiftUI
import AVFoundation
import AVKit

struct ShortsVideoView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var shortsTab: String = "for" // "for" (Đề xuất) | "following" (Đang theo dõi)
    @State private var items: [ShortItem] = []
    @State private var currentIndex: Int = 0
    @State private var isLoading = false
    @State private var activeCommentShort: ShortItem?

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
                    TabView(selection: $currentIndex) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            shortVideoCard(item, at: index)
                                .rotationEffect(.degrees(-90))
                                .frame(width: geo.size.width, height: geo.size.height)
                                .tag(index)
                        }
                    }
                    .frame(width: geo.size.height, height: geo.size.width)
                    .rotationEffect(.degrees(90))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .ignoresSafeArea(edges: .top)
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
    }

    private func tabHeaderButton(id: String, title: String) -> some View {
        let isSelected = shortsTab == id
        return Button {
            shortsTab = id
            Task { await loadShorts() }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
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
            ShortClipPlayer(path: item.videoUrl, active: index == currentIndex)
                .allowsHitTesting(false)

            // Right Action Column (Like, Comment, Share)
            HStack(alignment: .bottom) {
                // Bottom left: Author info & Caption
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        KinnectAvatarView(
                            name: item.author.name,
                            avatarURL: item.author.avatarUrl,
                            colorHex: item.author.avatarColor,
                            size: 40,
                            isOnline: false
                        )
                        Text(item.author.name)
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }

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
                VStack(spacing: 18) {
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
                }
                .padding(.trailing, 12)
                .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func loadShorts() async {
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

private struct ShortClipPlayer: View {
    let path: String
    let active: Bool
    @ObservedObject private var calls = NativeWebRTCManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var loading = false
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
            }
            if loading {
                ProgressView().tint(.white)
            }
            if failed {
                VStack(spacing: 8) {
                    Text("Không phát được video")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Button("Thử lại") { Task { await load() } }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            }
        }
        .task(id: path) { await load() }
        .onChange(of: active) { _ in syncPlayback() }
        .onChange(of: scenePhase) { _ in syncPlayback() }
        .onChange(of: calls.activeCall != nil) { _ in syncPlayback() }
        .onDisappear { stop() }
    }

    private func load() async {
        stop()
        failed = false
        loading = true
        defer { loading = false }
        do {
            let file = try await KinnectAuthenticatedFile.fetch(path: path, fileExtension: "mp4")
            let item = AVPlayerItem(url: file)
            let next = AVPlayer(playerItem: item)
            next.isMuted = false
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                next.seek(to: .zero)
                if active { next.play() }
            }
            player = next
            syncPlayback()
        } catch {
            failed = true
        }
    }

    private func syncPlayback() {
        guard let player else { return }
        let blocked = !active || scenePhase != .active || calls.activeCall != nil
        if blocked {
            player.pause()
        } else {
            player.play()
        }
    }

    private func stop() {
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(comments) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.author.name)
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(c.text)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .kinnectMultiline()
                    }
                    .listRowBackground(KinnectTheme.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                HStack(spacing: 8) {
                    TextField("Bình luận video ngắn...", text: $text)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(.white)
                    KinnectIconButton(
                        glyph: .send,
                        label: "Gửi bình luận",
                        tint: KinnectTheme.accentBright
                    ) {
                        Task { await postComment() }
                    }
                }
                .padding(12)
                .background(KinnectTheme.surface)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Bình luận Shorts")
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
    }

    private func load() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/shorts/\(short.id)/comments") {
            self.comments = (res["comments"] as? [[String: Any]] ?? []).map(CommentItem.from)
        }
    }

    private func postComment() async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let draft = text
        text = ""
        let reqId = "short_cmt_\(short.id)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/shorts/\(short.id)/comments",
                method: "POST",
                body: KinnectWriteBody.comment(clean),
                requestId: reqId
            )
            await load()
            onUpdated()
        } catch {
            text = draft
            appState.showToast(error.localizedDescription)
        }
    }
}
