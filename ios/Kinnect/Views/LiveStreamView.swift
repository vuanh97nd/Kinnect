import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct LiveStreamView: View {
    let onOpenWallet: () -> Void
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared

    @State private var selectedIndex = 0
    @State private var scrolledRoomId: String?
    @State private var categoryFilter: String = "all" // "all" | "chat" | "game"
    @State private var isLoading = false
    @State private var roomLoadError = ""
    @State private var chatText = ""
    @State private var likesCount = 0
    @State private var isLiked = false
    @State private var showGiftDrawer = false
    @State private var giftCatalog: [LiveGiftCatalogItem] = []
    @State private var giftPriceVersion = 1
    @State private var showCreateLiveSheet = false

    private var filteredRooms: [LiveRoomItem] {
        switch categoryFilter {
        case "chat":
            return appState.liveRooms.filter { $0.liveMode != "game" }
        case "game":
            return appState.liveRooms.filter { $0.liveMode == "game" }
        default:
            return appState.liveRooms
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if isLoading && appState.liveRooms.isEmpty {
                VStack(spacing: 14) {
                    ProgressView().tint(.white).scaleEffect(1.15)
                    Text("Đang kết nối phòng phát trực tiếp…")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !filteredRooms.isEmpty {
                // Unified native vertical swipe viewer for all Live streams (Parity Android 1.2.12 build 118)
                GeometryReader { proxy in
                    if #available(iOS 17.0, *) {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredRooms) { room in
                                    liveStreamPage(room)
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .clipped()
                                        .id(room.id)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $scrolledRoomId)
                        .onChange(of: scrolledRoomId) { newId in
                            guard let newId,
                                  let idx = filteredRooms.firstIndex(where: { $0.id == newId }) else { return }
                            if selectedIndex != idx {
                                selectedIndex = idx
                            }
                        }
                    } else {
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(filteredRooms.enumerated()), id: \.element.id) { index, room in
                                        liveStreamPage(room)
                                            .frame(width: proxy.size.width, height: proxy.size.height)
                                            .id(index)
                                    }
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 24)
                                    .onEnded { value in
                                        let dy = value.translation.height
                                        if dy < -50 && selectedIndex + 1 < filteredRooms.count {
                                            selectedIndex += 1
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                scrollProxy.scrollTo(selectedIndex, anchor: .top)
                                            }
                                        } else if dy > 50 && selectedIndex > 0 {
                                            selectedIndex -= 1
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                scrollProxy.scrollTo(selectedIndex, anchor: .top)
                                            }
                                        }
                                    }
                            )
                        }
                    }
                }
                .ignoresSafeArea()
            } else {
                liveEmptyStateView
            }

            // Persistent Pro Top Mode Filter & Studio Bar
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.75), Color.black.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 112)
                .ignoresSafeArea(edges: .top)
                Spacer()
            }
            .allowsHitTesting(false)

            liveTopLobbyBar
                .padding(.horizontal, 14)
                .padding(.top, 10)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .task {
            await fetchLiveRooms()
            await loadGifts()
            syncInitialOrFilteredRoom()
        }
        .onChange(of: categoryFilter) { _ in
            selectedIndex = 0
            syncInitialOrFilteredRoom()
        }
        .onChange(of: selectedIndex) { newIndex in
            guard filteredRooms.indices.contains(newIndex) else { return }
            let room = filteredRooms[newIndex]
            appState.joinLiveRoom(room)
            likesCount = room.likesCount
        }
        .onChange(of: appState.liveRooms.map(\.id)) { _ in
            syncInitialOrFilteredRoom()
        }
        .onDisappear {
            appState.leaveCurrentLiveRoom()
        }
        .sheet(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet(
                initialLiveMode: categoryFilter == "game" ? "game" : "chat",
                onStarted: {
                    Task {
                        await fetchLiveRooms()
                    }
                }
            )
        }
        .sheet(isPresented: $showGiftDrawer) {
            if filteredRooms.indices.contains(selectedIndex) {
                LiveGiftDrawerSheet(
                    roomId: filteredRooms[selectedIndex].id,
                    gifts: giftCatalog,
                    priceVersion: giftPriceVersion
                )
            }
        }
    }

    private func syncInitialOrFilteredRoom() {
        let rooms = filteredRooms
        guard !rooms.isEmpty else {
            selectedIndex = 0
            scrolledRoomId = nil
            return
        }
        if let currentId = scrolledRoomId, let idx = rooms.firstIndex(where: { $0.id == currentId }) {
            selectedIndex = idx
            if !appState.isCurrentLiveHost && appState.currentLiveRoom?.id != currentId {
                appState.joinLiveRoom(rooms[idx])
            }
        } else {
            selectedIndex = min(selectedIndex, rooms.count - 1)
            let target = rooms[selectedIndex]
            scrolledRoomId = target.id
            likesCount = target.likesCount
            if !appState.isCurrentLiveHost && appState.currentLiveRoom?.id != target.id {
                appState.joinLiveRoom(target)
            }
        }
    }

    private var liveTopLobbyBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                liveCategoryPill(id: "all", title: "Tất cả", icon: "sparkles")
                liveCategoryPill(id: "chat", title: "Trò chuyện", icon: "bubble.left.and.bubble.right.fill")
                liveCategoryPill(id: "game", title: "Chơi game", icon: "gamecontroller.fill")
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
            )

            Spacer(minLength: 4)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showCreateLiveSheet = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                    Text("Phát Live")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(red: 0.96, green: 0.24, blue: 0.42), Color(red: 0.64, green: 0.24, blue: 0.96)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .foregroundColor(.white)
                .shadow(color: Color(red: 0.96, green: 0.24, blue: 0.42).opacity(0.42), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    private func liveCategoryPill(id: String, title: String, icon: String) -> some View {
        let selected = (categoryFilter == id)
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                categoryFilter = id
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: selected ? .bold : .medium))
                    .lineLimit(1)
            }
            .foregroundColor(selected ? .black : .white.opacity(0.86))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? Color.white : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var liveEmptyStateView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.16),
                    Color(red: 0.04, green: 0.04, blue: 0.09),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [KinnectTheme.accent.opacity(0.35), .clear],
                                center: .center,
                                startRadius: 6,
                                endRadius: 64
                            )
                        )
                        .frame(width: 120, height: 120)
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 78, height: 78)
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    Image(systemName: categoryFilter == "game" ? "gamecontroller.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text(
                        roomLoadError.isEmpty
                            ? (categoryFilter == "game" ? "Chưa có phòng Game Live nào"
                               : (categoryFilter == "chat" ? "Chưa có phòng Trò chuyện nào" : "Chưa có phòng Live nào đang phát"))
                            : "Không tải được danh sách phòng"
                    )
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)

                    Text(
                        roomLoadError.isEmpty
                            ? "Trở thành người đầu tiên lên sóng hoặc khám phá các phòng phát trực tiếp khác trên Kinnect."
                            : roomLoadError
                    )
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                }

                HStack(spacing: 12) {
                    if !roomLoadError.isEmpty {
                        Button("Thử lại") { Task { await fetchLiveRooms() } }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .foregroundColor(.white)
                    }

                    Button {
                        showCreateLiveSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: categoryFilter == "game" ? "gamecontroller.fill" : "video.badge.plus")
                                .font(.system(size: 15, weight: .bold))
                            Text(categoryFilter == "game" ? "Phát Live Chơi game" : "Bắt đầu phát Live")
                                .font(.subheadline.weight(.bold))
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 13)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(red: 0.96, green: 0.24, blue: 0.42), Color(red: 0.56, green: 0.24, blue: 0.96)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                        .foregroundColor(.white)
                        .shadow(color: KinnectTheme.accent.opacity(0.45), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadGifts() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/gifts") {
            let parsed = LiveGiftCatalogAdapter.parse(res)
            if !parsed.items.isEmpty { self.giftCatalog = parsed.items }
            if parsed.version > 0 { self.giftPriceVersion = parsed.version }
        }
    }

    private func liveStreamPage(_ room: LiveRoomItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            // WebRTC Video Canvas with Fallback connecting state
            ZStack {
                if appState.currentLiveRoom?.id == room.id, appState.isCurrentLiveHost, let localTrack = webrtc.liveLocalVideoTrack {
                    WebRTCVideoRendererView(track: localTrack, mirror: webrtc.usingFrontCamera)
                } else if appState.currentLiveRoom?.id == room.id, let remoteTrack = webrtc.liveRemoteVideoTrack {
                    WebRTCVideoRendererView(track: remoteTrack, mirror: false)
                } else if UIReviewFixture.isEnabled, UIReviewFixture.activeScreen != "live-connecting", let sample = UIReviewFixture.samplePlayableVideoURL() {
                    // A sample video is permitted only in explicitly activated debug QA.
                    ZStack {
                        ShortClipPlayer(
                            path: sample.absoluteString,
                            active: appState.currentLiveRoom?.id == room.id
                        )
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.4),
                                Color.clear,
                                Color.black.opacity(0.7)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea()
                } else {
                    // Missing real tracks mean connecting/paused/error, never a demo broadcast.
                    VStack(spacing: 12) {
                        KinnectAvatarView(name: room.hostName, avatarURL: room.hostAvatarUrl,
                            colorHex: room.hostAvatarColor, size: 92)
                        if !room.gamePaused && webrtc.liveConnectionError == nil {
                            ProgressView().tint(.white)
                        }
                        Text(room.gamePaused ? "Chủ phòng đang tạm dừng màn hình game"
                            : (webrtc.liveConnectionError ?? "Đang kết nối luồng video Live..."))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }

            // Bottom & Top Scrim Overlays Container
            VStack(spacing: 0) {
                // Streamer Info Bar (sits right beneath liveTopLobbyBar)
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        KinnectAvatarView(
                            name: room.hostName,
                            avatarURL: room.hostAvatarUrl,
                            colorHex: room.hostAvatarColor,
                            size: 36
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.hostName)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                Text("LIVE")
                                    .font(.system(size: 8.5, weight: .black))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color(red: 0.96, green: 0.24, blue: 0.42)))
                                    .foregroundColor(.white)
                                Label("\(room.viewerCount)", systemImage: "eye.fill")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .padding(.leading, 5)
                    .padding(.trailing, 11)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                    )

                    HStack(spacing: 5) {
                        Image(systemName: room.liveMode == "game" ? "gamecontroller.fill" : "waveform")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(room.liveMode == "game" ? Color(hex: "#34D399") : KinnectTheme.accentBright)
                        Text(room.liveMode == "game" ? (room.gameTitle.isEmpty ? "Chơi game" : room.gameTitle) : "Trò chuyện")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.48))
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                    )

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 56)

                Spacer()

                // Bottom Gradient & Streaming Controls
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            if !room.title.isEmpty {
                                Text(room.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineLimit(1)
                                    .shadow(color: .black.opacity(0.5), radius: 3)
                            }

                            if let banner = appState.liveLastReactionBanner {
                                Text(banner)
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                            }

                            if appState.liveChatMessages.isEmpty {
                                chatBubble(
                                    name: "Kinnect Live",
                                    text: "Chào mừng đến phòng của \(room.hostName). Hãy gửi lời chào!",
                                    colorHex: "#A855F7"
                                )
                            } else {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(appState.liveChatMessages.suffix(6)) { msg in
                                        chatBubble(name: msg.user.name, text: msg.text, colorHex: msg.user.avatarColor)
                                    }
                                }
                                .mask(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0.0),
                                            .init(color: .white, location: 0.18),
                                            .init(color: .white, location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }

                            HStack(spacing: 8) {
                                TextField("Gửi bình luận…", text: $chatText)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.52))
                                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                                    )
                                    .foregroundColor(.white)

                                Button {
                                    let clean = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !clean.isEmpty {
                                        chatText = ""
                                        let localMsg = LiveChatMessage(
                                            id: UUID().uuidString,
                                            user: appState.currentUser ?? KinnectUser.from(["name": "Bạn"]),
                                            text: clean,
                                            createdAt: ""
                                        )
                                        appState.liveChatMessages.append(localMsg)
                                        NativeSocketClient.shared.sendJSON([
                                            "type": "chat",
                                            "text": clean,
                                            "room": room.id
                                        ])
                                    }
                                } label: {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 38, height: 38)
                                        .background(Circle().fill(KinnectTheme.primaryGradient))
                                }
                            }
                            .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Right Floating Action Rail
                        VStack(spacing: 14) {
                            Button {
                                showGiftDrawer = true
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(KinnectTheme.primaryGradient)
                                            .frame(width: 44, height: 44)
                                            .shadow(color: KinnectTheme.accent.opacity(0.4), radius: 8, y: 3)
                                        Image(systemName: "gift.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    Text("Tặng quà")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .accessibilityLabel("Tặng quà cho streamer")

                            Button {
                                isLiked = true
                                likesCount += 1
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                NativeSocketClient.shared.sendJSON([
                                    "type": "live-reaction",
                                    "room": room.id,
                                    "kind": "heart"
                                ])
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.45))
                                            .frame(width: 44, height: 44)
                                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(isLiked ? Color(red: 0.98, green: 0.28, blue: 0.45) : .white)
                                    }
                                    Text("\(likesCount)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .accessibilityLabel(isLiked ? "Bỏ thích" : "Thả tim")

                            Button {
                                let permalink = "https://kinnect.io.vn/live/\(room.id)"
                                UIPasteboard.general.string = permalink
                                appState.showToast("Đã sao chép liên kết phòng Live!")
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let rootVC = windowScene.windows.first?.rootViewController {
                                    let items: [Any] = [URL(string: permalink) ?? permalink]
                                    let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
                                    rootVC.present(av, animated: true)
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.45))
                                            .frame(width: 44, height: 44)
                                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                                        Image(systemName: "arrowshape.turn.up.right.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    Text("Chia sẻ")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .accessibilityLabel("Chia sẻ phòng Live")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 34)
                }
                .padding(.top, 28)
                .background(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.55), Color.black.opacity(0.86)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .bottom)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func chatBubble(name: String, text: String, colorHex: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(name + ":")
                .font(.caption2.bold())
                .foregroundColor(Color(hex: colorHex))
            Text(text)
                .font(.caption2)
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    private func fetchLiveRooms() async {
        isLoading = true
        roomLoadError = ""
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/live/rooms")
            guard let list = res["rooms"] as? [[String: Any]] else {
                throw KinnectAPIError.serverMessage("Không đọc được danh sách phòng. Vui lòng thử lại.")
            }
            appState.liveRooms = list.map(LiveRoomItem.from)
        } catch {
            roomLoadError = error.localizedDescription
            appState.showToast("Chưa tải được phòng Live. Vui lòng thử lại.")
        }
    }
}

struct CreateLiveRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    var initialLiveMode: String = "chat"
    var onStarted: (() -> Void)? = nil

    @State private var title = ""
    @State private var topic = "Giao lưu kết bạn"
    @State private var liveMode: String
    @State private var gameTitle = "Liên Quân Mobile"
    @State private var customGameName = ""
    @State private var gameSound = true
    @State private var gameComments = true
    @State private var isStarting = false
    @State private var createErrorMessage: String? = nil
    @State private var showPreviewEffects = false
    @State private var previewSticker = "none"
    @State private var previewFilter = "none"
    @State private var previewBeautyOn = true
    @State private var previewSmooth = 0.5
    @State private var previewWhiten = 0.3
    @State private var previewSlim = 0.2
    @State private var previewEyes = 0.2
    @State private var previewLips = 0.0
    @State private var previewBlemish = 0.4
    @State private var previewBlush = 0.0
    @State private var previewMicEnabled = true

    init(initialLiveMode: String = "chat", onStarted: (() -> Void)? = nil) {
        self.initialLiveMode = initialLiveMode
        self.onStarted = onStarted
        _liveMode = State(initialValue: initialLiveMode == "game" ? "game" : "chat")
    }

    private let popularGames = [
        "Liên Quân Mobile",
        "Free Fire",
        "PUBG Mobile",
        "Tốc Chiến",
        "Genshin Impact",
        "Roblox",
        "Minecraft",
        "Khác…"
    ]

    private let chatTopics = [
        "Giao lưu kết bạn",
        "Tâm sự đêm khuya",
        "Âm nhạc & Chill",
        "Hỏi đáp cùng fan"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.06, blue: 0.13),
                        Color(red: 0.04, green: 0.04, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let createErrorMessage, !createErrorMessage.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
                                Text(createErrorMessage)
                                    .font(.footnote.weight(.medium))
                                    .foregroundColor(.white)
                                    .kinnectMultiline()
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.red.opacity(0.22))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.red.opacity(0.45), lineWidth: 1)
                                    )
                            )
                        }

                        // Real SwiftUI 2-Tab Mode Switcher (Replaces broken UISegmentedControl HStack Picker)
                        liveModeTabBar

                        // Dynamic Mode Hero Preview Card — visibly transforms when switching between Trò chuyện and Chơi game
                        studioStagePreviewCard

                        // Room Info Card
                        roomInfoCard

                        // Mode-specific Configuration Card
                        if liveMode == "game" {
                            gameConfigCard
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        } else {
                            chatTopicsCard
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }

                        // Device & Effects Controls
                        deviceControlsCard
                    }
                    .padding(16)
                    .padding(.bottom, 86)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Button {
                        Task { await startHostLive() }
                    } label: {
                        HStack(spacing: 10) {
                            if isStarting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: liveMode == "game" ? "gamecontroller.fill" : "dot.radiowaves.left.and.right")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Text(isStarting ? "Đang khởi tạo phòng Live…" : (liveMode == "game" ? "Bắt đầu Live Chơi game" : "Bắt đầu Live Trò chuyện"))
                                .font(.headline.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Capsule().fill(
                                liveMode == "game"
                                    ? LinearGradient(colors: [Color(hex: "#10B981"), Color(hex: "#0284C7")], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color(red: 0.96, green: 0.24, blue: 0.42), Color(red: 0.56, green: 0.24, blue: 0.96)], startPoint: .leading, endPoint: .trailing)
                            )
                        )
                        .foregroundColor(.white)
                        .shadow(color: (liveMode == "game" ? Color(hex: "#10B981") : KinnectTheme.accent).opacity(0.45), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStarting)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Phòng phát trực tiếp")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .statusBarHidden(false)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                        .foregroundColor(.white.opacity(0.85))
                        .disabled(isStarting)
                }
            }
            .sheet(isPresented: $showPreviewEffects) {
                LiveEffectsSheet(
                    activeSticker: $previewSticker,
                    activeFilter: $previewFilter,
                    beautyEnabled: $previewBeautyOn,
                    smooth: $previewSmooth,
                    whiten: $previewWhiten,
                    slim: $previewSlim,
                    eyes: $previewEyes,
                    lips: $previewLips,
                    blemish: $previewBlemish,
                    blush: $previewBlush
                )
            }
        }
    }

    private var liveModeTabBar: some View {
        HStack(spacing: 8) {
            modeTabButton(
                id: "chat",
                title: "Trò chuyện",
                subtitle: "Camera & Làm đẹp",
                icon: "video.fill",
                activeColors: [Color(red: 0.96, green: 0.24, blue: 0.42), Color(red: 0.56, green: 0.24, blue: 0.96)]
            )
            modeTabButton(
                id: "game",
                title: "Chơi game",
                subtitle: "Luồng Game HD",
                icon: "gamecontroller.fill",
                activeColors: [Color(hex: "#10B981"), Color(hex: "#0284C7")]
            )
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func modeTabButton(id: String, title: String, subtitle: String, icon: String, activeColors: [Color]) -> some View {
        let isSelected = (liveMode == id)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                liveMode = id
                if id == "game" && topic == "Giao lưu kết bạn" {
                    topic = "Chơi game cùng khán giả"
                } else if id == "chat" && topic == "Chơi game cùng khán giả" {
                    topic = "Giao lưu kết bạn"
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.75))
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.88) : .white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? LinearGradient(colors: activeColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.clear, Color.clear], startPoint: .top, endPoint: .bottom)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var studioStagePreviewCard: some View {
        let isGame = (liveMode == "game")
        let displayedGame = (gameTitle == "Khác…" && !customGameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? customGameName.trimmingCharacters(in: .whitespacesAndNewlines)
            : (gameTitle == "Khác…" ? "Game tùy chọn" : gameTitle)

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [(isGame ? Color(hex: "#10B981") : Color(red: 0.96, green: 0.24, blue: 0.42)).opacity(0.45), .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 34
                        )
                    )
                    .frame(width: 58, height: 58)
                Image(systemName: isGame ? "gamecontroller.fill" : "sparkles.tv.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isGame ? "CHẾ ĐỘ CHƠI GAME" : "CHẾ ĐỘ TRÒ CHUYỆN")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.6)
                        .foregroundColor(isGame ? Color(hex: "#34D399") : Color(red: 0.98, green: 0.45, blue: 0.65))
                    Spacer()
                    Text("HD 720p")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .foregroundColor(.white.opacity(0.85))
                }
                Text(isGame ? displayedGame : (appState.currentUser?.name ?? "Phòng trò chuyện trực tiếp"))
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(isGame
                     ? "Đồng bộ khung hình Game, âm thanh & bảng quà tặng 3D thời gian thực."
                     : "Kết nối camera, bộ lọc làm đẹp AI và giao lưu trực tiếp cùng khán giả.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .kinnectMultiline()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke((isGame ? Color(hex: "#10B981") : KinnectTheme.accentBright).opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var roomInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THÔNG TIN PHÒNG")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.55))

            VStack(spacing: 10) {
                TextField(
                    liveMode == "game" ? "Tiêu đề buổi Live Game…" : "Tiêu đề buổi trò chuyện…",
                    text: $title
                )
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))

                TextField("Chủ đề phòng Live", text: $topic)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private var chatTopicsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHỦ ĐỀ GỢI Ý")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.55))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chatTopics, id: \.self) { item in
                        let selected = (topic == item)
                        Button {
                            topic = item
                        } label: {
                            Text(item)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selected ? .white : .white.opacity(0.78))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selected ? KinnectTheme.accent : Color.white.opacity(0.09))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private var gameConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHỌN TỰA GAME PHÁT LIVE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.55))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popularGames, id: \.self) { game in
                        let selected = (gameTitle == game)
                        Button {
                            gameTitle = game
                        } label: {
                            Text(game)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selected ? .black : .white.opacity(0.88))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selected ? Color(hex: "#34D399") : Color.white.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if gameTitle == "Khác…" {
                TextField("Nhập tên game của bạn", text: $customGameName)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            }

            Toggle("Âm thanh game", isOn: $gameSound)
                .font(.subheadline)
                .foregroundColor(.white)
                .tint(Color(hex: "#10B981"))

            Toggle("Bình luận nổi trên màn hình", isOn: $gameComments)
                .font(.subheadline)
                .foregroundColor(.white)
                .tint(Color(hex: "#10B981"))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: "#10B981").opacity(0.32), lineWidth: 1))
        )
    }

    private var deviceControlsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIẾT BỊ & STUDIO")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.55))

            HStack(spacing: 10) {
                Button {
                    NativeWebRTCManager.shared.flipCamera()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                        Text("Lật camera")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Button {
                    showPreviewEffects = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.title3)
                            .foregroundColor(KinnectTheme.accentBright)
                        Text("Làm đẹp")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Button {
                    previewMicEnabled.toggle()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: previewMicEnabled ? "mic.fill" : "mic.slash.fill")
                            .font(.title3)
                            .foregroundColor(previewMicEnabled ? Color(hex: "#34D399") : Color(red: 1.0, green: 0.42, blue: 0.42))
                        Text(previewMicEnabled ? "Mic Bật" : "Mic Tắt")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private func startHostLive() async {
        isStarting = true
        createErrorMessage = nil
        defer { isStarting = false }

        if appState.currentLiveRoom != nil {
            appState.leaveCurrentLiveRoom()
        }

        let manager = NativeWebRTCManager.shared
        manager.updateLiveEffects(LiveVideoSettings(
            filter: previewFilter, sticker: previewSticker, beauty: previewBeautyOn,
            smooth: previewSmooth, whiten: previewWhiten, slim: previewSlim, eyes: previewEyes,
            lips: previewLips, blemish: previewBlemish, blush: previewBlush))
        guard await manager.startLiveHostBroadcast() else {
            let msg = "Cần quyền camera và micro để bắt đầu Live."
            createErrorMessage = msg
            appState.showToast(msg)
            return
        }
        manager.setMicrophoneMuted(!previewMicEnabled)

        let selectedGame = (gameTitle == "Khác…" && !customGameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? customGameName.trimmingCharacters(in: .whitespacesAndNewlines)
            : (gameTitle == "Khác…" ? "Trò chơi" : gameTitle)

        let roomTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (liveMode == "game" ? "Live Game: \(selectedGame)" : "Phòng Live của \(appState.currentUser?.name ?? "Kinnect")")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let createResult = await appState.createLiveRoomAndAwaitJoin(payload: [
            "title": roomTitle,
            "topic": topic,
            "liveMode": liveMode,
            "gameTitle": liveMode == "game" ? selectedGame : "",
            "multiGuest": true,
            "liveModes": true,
            "comments": gameComments
        ])
        switch createResult {
        case .success:
            dismiss()
            onStarted?()
        case .failure(let failure):
            manager.stopLiveSession()
            let msg = failure.errorDescription ?? "Không thể bắt đầu phát Live."
            createErrorMessage = msg
            appState.showToast(msg)
        }
    }
}

struct LiveRoomFullScreenView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared

    @State private var chatInput = ""
    @State private var giftCatalog: [LiveGiftCatalogItem] = LiveGiftCatalogItem.defaultCatalog
    @State private var giftPriceVersion: Int = 1
    @State private var showGiftSheet = false
    @State private var showEffectsSheet = false
    @State private var activeLiveSticker: String = "none"
    @State private var activeLiveFilter: String = "none"
    @State private var beautyEnabled: Bool = true
    @State private var beautySmooth: Double = 0.5
    @State private var beautyWhiten: Double = 0.3
    @State private var beautySlim: Double = 0.2
    @State private var beautyEyes: Double = 0.2
    @State private var beautyLips: Double = 0.0
    @State private var beautyBlemish: Double = 0.4
    @State private var beautyBlush: Double = 0.0
    @State private var hostMicMuted: Bool = false
    @State private var activeGiftEffect: ActiveGiftEffect? = nil
    @State private var floatingReactions: [LiveFloatingReaction] = []

    var body: some View {
        if let room = appState.currentLiveRoom {
            ZStack {
                KinnectTheme.background.ignoresSafeArea()

                // Video Canvas
                if appState.isCurrentLiveHost, let localTrack = webrtc.liveLocalVideoTrack {
                    WebRTCVideoRendererView(track: localTrack, mirror: webrtc.usingFrontCamera)
                        .ignoresSafeArea()
                } else if let remoteTrack = webrtc.liveRemoteVideoTrack {
                    WebRTCVideoRendererView(track: remoteTrack, mirror: false)
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        KinnectAvatarView(
                            name: room.hostName,
                            avatarURL: room.hostAvatarUrl,
                            colorHex: room.hostAvatarColor,
                            size: 92
                        )
                        Text(room.gamePaused ? "Chủ phòng đang tạm dừng màn hình game" : (webrtc.liveConnectionError ?? "Đang kết nối luồng video Live..."))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                }

                // Filters are baked into RTCVideoSource, not painted over the viewer UI.

                // Top & Bottom Gradient Scrims + Broadcast HUD
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.76), Color.black.opacity(0.28), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                    .ignoresSafeArea(edges: .top)
                    Spacer()
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Pro Top Studio Bar
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            KinnectAvatarView(
                                name: room.hostName,
                                avatarURL: room.hostAvatarUrl,
                                colorHex: room.hostAvatarColor,
                                size: 36
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.title.isEmpty ? room.hostName : room.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text("LIVE")
                                        .font(.system(size: 8.5, weight: .black))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(Color(red: 0.96, green: 0.24, blue: 0.42)))
                                        .foregroundColor(.white)
                                    Label("\(room.viewerCount)", systemImage: "eye.fill")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.92))
                                }
                            }
                        }
                        .padding(.leading, 5)
                        .padding(.trailing, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                        )

                        HStack(spacing: 5) {
                            Image(systemName: room.liveMode == "game" ? "gamecontroller.fill" : "waveform")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(room.liveMode == "game" ? Color(hex: "#34D399") : KinnectTheme.accentBright)
                            Text(room.liveMode == "game" ? (room.gameTitle.isEmpty ? "Chơi game" : room.gameTitle) : "Trò chuyện")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.45))
                                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                        )

                        Spacer()

                        if appState.isCurrentLiveHost && room.liveMode == "game" {
                            Button {
                                let nextPaused = !room.gamePaused
                                NativeSocketClient.shared.sendJSON([
                                    "type": "live-game-state",
                                    "paused": nextPaused,
                                    "gameTitle": room.gameTitle
                                ])
                            } label: {
                                Text(room.gamePaused ? "Tiếp tục" : "Tạm ẩn")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color(hex: "#F59E0B")))
                                    .foregroundColor(.black)
                            }
                            .buttonStyle(.plain)
                        }

                        if !appState.isCurrentLiveHost {
                            Button {
                                appState.activeReportContext = UGCReportContext(
                                    targetType: "live",
                                    targetId: room.id,
                                    targetUserId: room.hostUserId,
                                    targetTitle: room.title
                                )
                            } label: {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.black.opacity(0.45)))
                            }
                        }

                        Button {
                            leaveLiveRoom()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: appState.isCurrentLiveHost ? "power" : "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                if appState.isCurrentLiveHost {
                                    Text("Kết thúc")
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, appState.isCurrentLiveHost ? 11 : 10)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color(red: 0.92, green: 0.24, blue: 0.34)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    if let banner = appState.liveLastReactionBanner {
                        Text(banner)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                            .padding(.top, 6)
                    }

                    Spacer()

                    VStack(spacing: 10) {
                        // Fading Frosted Chat Stream
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(appState.liveChatMessages.suffix(30)) { msg in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("\(msg.user.name):")
                                            .font(.caption.bold())
                                            .foregroundColor(KinnectTheme.accentBright)
                                        Text(msg.text)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .kinnectMultiline()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(Color.black.opacity(0.45))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.6)
                                            )
                                    )
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                        .frame(maxHeight: 190)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white, location: 0.16),
                                    .init(color: .white, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Bottom Control Dock
                        HStack(spacing: 8) {
                            TextField("Gửi bình luận…", text: $chatInput)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.5))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                                )
                                .foregroundColor(.white)

                            Button {
                                sendLiveChat()
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(KinnectTheme.primaryGradient))
                            }

                            if appState.isCurrentLiveHost {
                                Button {
                                    NativeWebRTCManager.shared.flipCamera()
                                } label: {
                                    Image(systemName: "camera.rotate.fill")
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                                }
                                .accessibilityLabel("Lật camera")

                                Button {
                                    hostMicMuted.toggle()
                                    NativeWebRTCManager.shared.setMicrophoneMuted(hostMicMuted)
                                } label: {
                                    Image(systemName: hostMicMuted ? "mic.slash.fill" : "mic.fill")
                                        .foregroundColor(hostMicMuted ? KinnectTheme.danger : .white)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                                }
                                .accessibilityLabel(hostMicMuted ? "Bật micro" : "Tắt micro")

                                Button {
                                    showEffectsSheet = true
                                } label: {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(KinnectTheme.accentBright)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                                }
                                .accessibilityLabel("Hiệu ứng Live")
                            }

                            Button {
                                triggerLiveReaction(symbol: "💜", kind: "heart", room: room.id)
                            } label: {
                                Text("💜")
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                            }

                            Button {
                                showGiftSheet = true
                            } label: {
                                Image(systemName: "gift.fill")
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(KinnectTheme.primaryGradient))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 18)
                    }
                    .padding(.top, 18)
                    .background(
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.55), Color.black.opacity(0.86)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)
                    )
                }

                // Face stickers travel in the encoded video stream.

                // 3D Gift Animation Showcase Effect
                if let giftEffect = activeGiftEffect {
                    LiveGiftBurstShowcaseView(effect: giftEffect)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(60)
                }

                // Floating Reactions Layer matching Web `live-reactions`
                ForEach(floatingReactions) { reaction in
                    LiveFloatingReactionView(symbol: reaction.symbol)
                        .position(x: reaction.x, y: reaction.y)
                }
            }
            .preferredColorScheme(.dark)
            .statusBarHidden(false)
            .task {
                await loadGiftCatalog()
            }
            .sheet(isPresented: $showGiftSheet) {
                LiveGiftDrawerSheet(
                    roomId: room.id,
                    gifts: giftCatalog,
                    priceVersion: giftPriceVersion,
                    onGiftSent: { gift, qty in
                        triggerGiftEffect(gift: gift, qty: qty, senderName: appState.currentUser?.name ?? "Bạn")
                    }
                )
            }
            .onAppear {
                let value = webrtc.liveEffects
                activeLiveFilter = value.filter
                activeLiveSticker = value.sticker
                beautyEnabled = value.beauty
                beautySmooth = value.smooth
                beautyWhiten = value.whiten
                beautySlim = value.slim
                beautyEyes = value.eyes
                beautyLips = value.lips
                beautyBlemish = value.blemish
                beautyBlush = value.blush
            }
            .onChange(of: liveVideoSettings) { value in
                if appState.isCurrentLiveHost { webrtc.updateLiveEffects(value) }
            }
            .sheet(isPresented: $showEffectsSheet) {
                LiveEffectsSheet(
                    activeSticker: $activeLiveSticker,
                    activeFilter: $activeLiveFilter,
                    beautyEnabled: $beautyEnabled,
                    smooth: $beautySmooth,
                    whiten: $beautyWhiten,
                    slim: $beautySlim,
                    eyes: $beautyEyes,
                    lips: $beautyLips,
                    blemish: $beautyBlemish,
                    blush: $beautyBlush
                )
            }
        }
    }

    private var liveVideoSettings: LiveVideoSettings {
        LiveVideoSettings(filter: activeLiveFilter, sticker: activeLiveSticker, beauty: beautyEnabled,
                          smooth: beautySmooth, whiten: beautyWhiten, slim: beautySlim, eyes: beautyEyes,
                          lips: beautyLips, blemish: beautyBlemish, blush: beautyBlush)
    }

    private func triggerLiveReaction(symbol: String, kind: String, room: String) {
        let screenWidth = UIScreen.main.bounds.width
        let startX = screenWidth * CGFloat.random(in: 0.68...0.88)
        let startY = UIScreen.main.bounds.height * 0.78
        let r = LiveFloatingReaction(symbol: symbol, x: startX, y: startY)
        floatingReactions.append(r)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            floatingReactions.removeAll(where: { $0.id == r.id })
        }
        NativeSocketClient.shared.sendJSON([
            "type": "live-reaction",
            "room": room,
            "kind": kind
        ])
    }

    private func triggerGiftEffect(gift: LiveGiftCatalogItem, qty: Int, senderName: String) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let effect = ActiveGiftEffect(
            giftId: gift.id,
            giftName: gift.label,
            giftEmoji: gift.emoji,
            senderName: senderName,
            quantity: qty
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            activeGiftEffect = effect
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if activeGiftEffect?.id == effect.id {
                withAnimation(.easeOut(duration: 0.3)) {
                    activeGiftEffect = nil
                }
            }
        }
    }

    private func sendLiveChat() {
        let clean = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        chatInput = ""
        NativeSocketClient.shared.sendJSON([
            "type": "chat",
            "text": clean
        ])
    }

    private func leaveLiveRoom() {
        appState.leaveCurrentLiveRoom()
    }

    private func loadGiftCatalog() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/gifts") {
            let parsed = LiveGiftCatalogAdapter.parse(res)
            if !parsed.items.isEmpty { self.giftCatalog = parsed.items }
            if parsed.version > 0 { self.giftPriceVersion = parsed.version }
        } else if self.giftCatalog.isEmpty {
            self.giftCatalog = LiveGiftCatalogItem.defaultCatalog
        }
    }
}

struct LiveGiftDrawerSheet: View {
    let roomId: String
    let gifts: [LiveGiftCatalogItem]
    let priceVersion: Int
    var onGiftSent: ((LiveGiftCatalogItem, Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuantity: Int = 1
    @State private var selectedGiftID: String? = nil
    @State private var pendingGift: LiveGiftCatalogItem?
    @State private var pendingRequestId: String?
    @State private var pendingQuantity = 1
    @State private var confirmGift: LiveGiftCatalogItem?
    @State private var giftError: String?

    private let quantities = [1, 5, 10, 99]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(UIReviewFixture.isEnabled ? "Xu tặng · 1.200" : "Xu tặng")
                            .font(KinnectTheme.bodyBold)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                    }
                    Text("Quà từ xu tặng không tạo tiền rút")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // Quantity / Combo Multiplier Pills matching Android & Web
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Text("Số lượng:")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textSecondary)

                    ForEach(quantities, id: \.self) { qty in
                        Button {
                            selectedQuantity = qty
                        } label: {
                            Text("x\(qty)")
                                .font(KinnectTheme.bodyBold)
                                .frame(minWidth: 44, minHeight: 36)
                                .padding(.horizontal, 8)
                                .background(
                                    Capsule().fill(selectedQuantity == qty ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                                )
                                .foregroundColor(selectedQuantity == qty ? .white : KinnectTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Số lượng \(qty)")
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                }
                if let giftError { Text(giftError).foregroundColor(KinnectTheme.danger) }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        let activeId = selectedGiftID ?? gifts.first?.id
                        ForEach(gifts) { gift in
                            let isSelected = activeId == gift.id
                            Button {
                                selectedGiftID = gift.id
                            } label: {
                                VStack(spacing: 6) {
                                    giftIconView(gift)
                                    Text(gift.label)
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .lineLimit(1)
                                    HStack(spacing: 3) {
                                        KinnectIcon(glyph: .coin, size: 12, selected: true, tint: KinnectTheme.warning)
                                        Text("\(GiftQuote(unitCoins: gift.coins, quantity: selectedQuantity).total) xu")
                                            .font(.caption2.bold())
                                            .foregroundColor(KinnectTheme.warning)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(isSelected ? KinnectTheme.accentBright.opacity(0.14) : KinnectTheme.surfaceElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    isSelected ? KinnectTheme.accentBright : Color.white.opacity(0.08),
                                                    lineWidth: isSelected ? 2 : 1
                                                )
                                        )
                                )
                            }
                        }
                    }
                    .padding(16)
                }
                if let gift = gifts.first(where: { $0.id == (selectedGiftID ?? gifts.first?.id) }) {
                    let quote = GiftQuote(unitCoins: gift.coins, quantity: selectedQuantity)
                    Button {
                        if quote.needsConfirmation { confirmGift = gift }
                        else { sendGift(gift) }
                    } label: {
                        Text("Tặng · \(quote.total) xu")
                            .font(KinnectTheme.sectionTitle)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(KinnectTheme.primaryGradient)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .disabled(pendingRequestId != nil)
                }
            }
            .background(KinnectTheme.background)
            .disabled(pendingRequestId != nil)
            .navigationTitle("Tặng quà phòng Live")
            .alert("Xác nhận tặng quà?", isPresented: Binding(
                get: { confirmGift != nil }, set: { if !$0 { confirmGift = nil } }
            )) {
                Button("Hủy", role: .cancel) { confirmGift = nil }
                Button("Tặng quà") {
                    if let gift = confirmGift { sendGift(gift) }
                    confirmGift = nil
                }
            } message: {
                Text("\(confirmGift?.label ?? "") · \((confirmGift?.coins ?? 0) * selectedQuantity) xu")
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kinnectLiveGiftResult"))) { event in
                guard let pendingRequestId, let data = event.userInfo else { return }
                if data["type"] as? String == "live-gift-receipt",
                   data["requestId"] as? String == pendingRequestId {
                    if let gift = pendingGift {
                        UserDefaults.standard.removeObject(forKey: giftRequestKey(gift.id, quantity: pendingQuantity))
                        onGiftSent?(gift, pendingQuantity)
                    }
                    self.pendingRequestId = nil
                    dismiss()
                } else if data["type"] as? String == "live-gift-error" || data["type"] as? String == "live-mode-error" {
                    giftError = data["message"] as? String ?? "Chưa gửi được quà."
                    self.pendingRequestId = nil
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .fraction(0.85)])
        .presentationDragIndicator(.visible)
    }

    private func giftAssetName(for id: String) -> String {
        return (id == "car") ? "sports_car" : id
    }

    @ViewBuilder
    private func giftIconView(_ gift: LiveGiftCatalogItem) -> some View {
        let key = giftAssetName(for: gift.id)
        if let img = UIImage(named: "kg20261109_gift_\(key)")
            ?? UIImage(named: "kg20261109_gift_\(gift.id)")
            ?? UIImage(named: "gift_\(key)")
            ?? UIImage(named: "gift_\(gift.id)")
            ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "gift_\(key)", ofType: "png") ?? "")
            ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "gift_\(key)_3d", ofType: "jpg") ?? "") {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if gift.id == "star" {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.67, green: 0.55, blue: 1.0).opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 24))
                Image(systemName: "star.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.94, blue: 0.68), Color(red: 0.96, green: 0.72, blue: 0.25)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(red: 0.67, green: 0.55, blue: 1.0).opacity(0.65), radius: 5)
            }
            .frame(width: 44, height: 44)
        } else if let vectorSpec = Self.vectorSymbol(for: gift.id) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [vectorSpec.primary.opacity(0.28), .clear], center: .center, startRadius: 2, endRadius: 24))
                Image(systemName: vectorSpec.systemName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [vectorSpec.primary, vectorSpec.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .frame(width: 44, height: 44)
        } else {
            let symbol = gift.emoji == "🎁" ? LiveGiftCatalogItem.defaultEmoji(for: gift.id) : gift.emoji
            Text(symbol)
                .font(.system(size: 38))
        }
    }

    private static func vectorSymbol(for id: String) -> (systemName: String, primary: Color, secondary: Color)? {
        switch id {
        case "butterfly":
            return ("sparkles", Color(red: 0.25, green: 0.85, blue: 0.82), Color(red: 0.56, green: 0.42, blue: 0.98))
        case "aurora":
            return ("sparkles", Color(red: 0.22, green: 0.82, blue: 0.92), Color(red: 0.48, green: 0.36, blue: 0.96))
        case "meteor":
            return ("sparkle", Color(red: 1.0, green: 0.85, blue: 0.35), Color(red: 0.98, green: 0.50, blue: 0.28))
        case "lotus":
            return ("leaf.fill", Color(red: 0.98, green: 0.48, blue: 0.72), Color(red: 0.65, green: 0.33, blue: 0.97))
        default:
            return nil
        }
    }

    private func giftRequestKey(_ giftId: String, quantity: Int) -> String {
        "kinnect-gift-request:" + ServerConfig.currentOrigin + ":"
            + (AppState.shared.currentUser?.id ?? "") + ":" + roomId + ":" + giftId + ":" + String(quantity)
    }

    private func sendGift(_ gift: LiveGiftCatalogItem) {
        guard pendingRequestId == nil else { return }
        let quote = GiftQuote(unitCoins: gift.coins, quantity: selectedQuantity)
        if UIReviewFixture.isEnabled {
            giftError = "Fixture: \(gift.label) · \(quote.total) xu. Không gửi giao dịch."
            return
        }
        guard NativeSocketClient.shared.isConnected else {
            giftError = "Mất kết nối phòng Live. Hãy kết nối lại trước khi tặng quà."
            return
        }
        let key = giftRequestKey(gift.id, quantity: selectedQuantity)
        let reqId = UserDefaults.standard.string(forKey: key)
            ?? "gift_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(reqId, forKey: key)
        pendingGift = gift
        pendingRequestId = reqId
        pendingQuantity = selectedQuantity
        giftError = nil
        NativeSocketClient.shared.sendJSON([
            "type": "live-reaction",
            "room": roomId,
            "kind": gift.id,
            "quantity": selectedQuantity,
            "fundingSource": "gifted",
            "requestId": reqId,
            "priceVersion": priceVersion
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            if pendingRequestId == reqId {
                giftError = "Chưa nhận được xác nhận. Kiểm tra số dư và lịch sử quà trước khi gửi lại."
                // Keep the drawer from sending a second transaction after an ambiguous timeout.
            }
        }
    }
}

// MARK: - Floating Reaction Model & View (Web Parity `live-floating-reaction`)
struct LiveFloatingReaction: Identifiable {
    let id = UUID()
    let symbol: String
    let x: CGFloat
    let y: CGFloat
}

struct LiveFloatingReactionView: View {
    let symbol: String
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = 0.5

    var body: some View {
        Group {
            if let img = UIImage(named: "kg20261109_gift_\(symbol)")
                ?? UIImage(named: "kg20261109_gift_\(symbol == "car" ? "sports_car" : symbol)")
                ?? UIImage(named: "gift_\(symbol)") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
            } else {
                Text(symbol)
                    .font(.system(size: 36))
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(y: offsetY)
        .onAppear {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                scale = 1.15
            }
            withAnimation(.easeOut(duration: 1.1)) {
                offsetY = -180
                opacity = 0
                scale = 1.3
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Active Gift Effect Model
struct ActiveGiftEffect: Identifiable {
    let id = UUID()
    let giftId: String
    let giftName: String
    let giftEmoji: String
    let senderName: String
    let quantity: Int
}

// MARK: - Live Gift Burst Showcase View (Big 3D Animation Overlay)
struct LiveGiftBurstShowcaseView: View {
    let effect: ActiveGiftEffect
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 0.2
    @State private var bannerOffset: CGFloat = -60

    var body: some View {
        ZStack {
            // Dark vignette backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Top Gift Banner
                HStack(spacing: 10) {
                    KinnectAvatarView(name: effect.senderName, avatarURL: "", colorHex: "#7C3AED", size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(effect.senderName)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Text("đã gửi tặng \(effect.giftName)")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.warning)
                    }
                    Spacer()
                    Text("x\(effect.quantity)")
                        .font(.title2.bold())
                        .foregroundStyle(KinnectTheme.primaryGradient)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: 320)
                .background(
                    Capsule()
                        .fill(KinnectTheme.surface.opacity(0.95))
                        .overlay(Capsule().stroke(KinnectTheme.warning.opacity(0.8), lineWidth: 1.5))
                )
                .offset(y: bannerOffset)

                Spacer()

                // Center 3D Gift Artwork & Glowing Burst Rays
                ZStack {
                    // Rotating Light Rays
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 220))
                        .foregroundColor(KinnectTheme.warning.opacity(0.25))
                        .rotationEffect(.degrees(rotation))

                    // 3D Gift Image
                    giftArtworkView
                        .scaleEffect(scale)
                }
                .frame(width: 240, height: 240)

                // Combo Badge
                HStack(spacing: 6) {
                    Text(effect.giftName)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("x\(effect.quantity)")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(KinnectTheme.warning)
                }
                .shadow(color: .black.opacity(0.8), radius: 4, y: 2)

                Spacer()
            }
            .padding(.top, 40)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                bannerOffset = 0
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                scale = 1.05
            }
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var giftArtworkView: some View {
        let key = giftAssetName(for: effect.giftId)
        if let img = UIImage(named: "gift_\(key)")
            ?? UIImage(named: "gift_\(effect.giftId)")
            ?? UIImage(named: "kg20261109_gift_\(key)") {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
                .shadow(color: KinnectTheme.warning.opacity(0.6), radius: 18)
        } else {
            Text(effect.giftEmoji)
                .font(.system(size: 110))
                .shadow(color: .black.opacity(0.5), radius: 10)
        }
    }

    private func giftAssetName(for id: String) -> String {
        switch id {
        case "rose": return "rose"
        case "heart": return "heart"
        case "crown": return "crown"
        case "diamond": return "diamond"
        case "car", "sports_car": return "sports_car"
        case "yacht": return "yacht"
        case "castle": return "castle"
        default: return id
        }
    }
}

// MARK: - AR Face Sticker Overlay in Live
struct LiveStickerOverlayView: View {
    let stickerId: String

    var body: some View {
        VStack {
            Spacer().frame(height: 120)
            stickerContentView
                .transition(.scale.combined(with: .opacity))
            Spacer()
        }
    }

    @ViewBuilder
    private var stickerContentView: some View {
        if let img = UIImage(named: "sticker_\(stickerId)") {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.4), radius: 6)
        } else {
            Text(emojiForSticker(stickerId))
                .font(.system(size: 90))
                .shadow(color: .black.opacity(0.4), radius: 6)
        }
    }

    private func emojiForSticker(_ id: String) -> String {
        switch id {
        case "glasses": return "🕶️"
        case "bunny": return "🐰"
        case "cat": return "🐱"
        case "dog": return "🐶"
        case "crown": return "👑"
        case "flowers": return "🌸"
        case "bow": return "🎀"
        case "freckles": return "🤎"
        case "hearts": return "💕"
        case "sparkle": return "✨"
        case "stars": return "⭐"
        case "round_glasses": return "👓"
        case "heart_glasses": return "💗"
        case "neon_glasses": return "⚡"
        case "butterfly": return "🦋"
        case "halo": return "😇"
        case "devil": return "😈"
        case "rainbow": return "🌈"
        case "bubbles": return "🫧"
        case "snow": return "❄️"
        case "confetti": return "🎉"
        default: return "✨"
        }
    }
}

// MARK: - Live Color Grading Filter Overlay
struct LiveFilterColorOverlay: View {
    let filterId: String

    var body: some View {
        Group {
            switch filterId {
            case "clear":
                Color.cyan.opacity(0.08)
            case "milk":
                Color.white.opacity(0.12)
            case "peach":
                Color.pink.opacity(0.12)
            case "warm":
                Color.orange.opacity(0.12)
            case "cool":
                Color.blue.opacity(0.12)
            case "film":
                Color(red: 0.82, green: 0.72, blue: 0.52).opacity(0.16)
            case "mono":
                Color.gray.opacity(0.25)
            case "noir":
                Color.black.opacity(0.22)
            case "vivid":
                Color.purple.opacity(0.08)
            case "sunset":
                Color(red: 1.0, green: 0.42, blue: 0.22).opacity(0.16)
            case "candy":
                Color(red: 1.0, green: 0.5, blue: 0.8).opacity(0.16)
            case "mint":
                Color(red: 0.3, green: 0.9, blue: 0.7).opacity(0.12)
            case "dream":
                Color(red: 0.8, green: 0.6, blue: 0.9).opacity(0.14)
            case "retro":
                Color(red: 0.75, green: 0.65, blue: 0.35).opacity(0.16)
            case "city":
                Color(red: 0.2, green: 0.4, blue: 0.65).opacity(0.14)
            case "cinema":
                Color(red: 0.1, green: 0.3, blue: 0.45).opacity(0.15)
            case "rose":
                Color(red: 0.92, green: 0.4, blue: 0.55).opacity(0.15)
            case "golden":
                Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.15)
            case "ice":
                Color(red: 0.6, green: 0.9, blue: 1.0).opacity(0.15)
            case "lavender":
                Color(red: 0.75, green: 0.55, blue: 0.92).opacity(0.14)
            case "choco":
                Color(red: 0.55, green: 0.32, blue: 0.12).opacity(0.16)
            case "polaroid":
                Color(red: 0.92, green: 0.88, blue: 0.76).opacity(0.14)
            case "teal":
                Color(red: 0.0, green: 0.5, blue: 0.5).opacity(0.15)
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Live Effects Sheet (Hiệu ứng Live: Làm đẹp · Hiệu ứng · Màu)
struct LiveEffectsSheet: View {
    @Binding var activeSticker: String
    @Binding var activeFilter: String
    @Binding var beautyEnabled: Bool
    @Binding var smooth: Double
    @Binding var whiten: Double
    @Binding var slim: Double
    @Binding var eyes: Double
    @Binding var lips: Double
    @Binding var blemish: Double
    @Binding var blush: Double
    @State private var selectedTab: Int = 0
    @Environment(\.dismiss) private var dismiss

    // 22 Stickers matching FxEngine.STICKERS
    private let stickerList: [(id: String, name: String, emoji: String)] = [
        ("none", "Không", "🚫"),
        ("glasses", "Kính râm", "🕶"),
        ("bunny", "Tai thỏ", "🐰"),
        ("cat", "Tai mèo", "🐱"),
        ("dog", "Cún con", "🐶"),
        ("crown", "Vương miện", "👑"),
        ("flowers", "Vòng hoa", "🌸"),
        ("bow", "Nơ xinh", "🎀"),
        ("freckles", "Tàn nhang", "🤎"),
        ("hearts", "Tim bay", "💕"),
        ("sparkle", "Lấp lánh", "✨"),
        ("stars", "Sao xoay", "⭐"),
        ("round_glasses", "Kính tròn", "👓"),
        ("heart_glasses", "Kính tim", "💗"),
        ("neon_glasses", "Kính neon", "⚡"),
        ("butterfly", "Bướm", "🦋"),
        ("halo", "Thiên thần", "😇"),
        ("devil", "Sừng xinh", "😈"),
        ("rainbow", "Cầu vồng", "🌈"),
        ("bubbles", "Bong bóng", "🫧"),
        ("snow", "Tuyết", "❄️"),
        ("confetti", "Lễ hội", "🎉")
    ]

    // 24 Filters matching FxEngine.FILTERS
    private let filterList: [(id: String, name: String, color: Color)] = [
        ("none", "Gốc", .gray),
        ("clear", "Trong trẻo", .cyan),
        ("milk", "Sữa", .white),
        ("peach", "Hồng đào", .pink),
        ("warm", "Ấm áp", .orange),
        ("cool", "Mát lạnh", .blue),
        ("film", "Phim cũ", Color(red: 0.82, green: 0.72, blue: 0.52)),
        ("mono", "Đen trắng", .gray),
        ("noir", "Tương phản", .black),
        ("vivid", "Rực rỡ", .purple),
        ("sunset", "Hoàng hôn", .orange),
        ("candy", "Kẹo ngọt", .pink),
        ("mint", "Bạc hà", .mint),
        ("dream", "Mộng mơ", .purple),
        ("retro", "Retro", Color(red: 0.75, green: 0.65, blue: 0.35)),
        ("city", "Thành phố", .blue),
        ("cinema", "Cinema", .indigo),
        ("rose", "Rose", .red),
        ("golden", "Golden", .yellow),
        ("ice", "Ice", .teal),
        ("lavender", "Lavender", Color(red: 0.75, green: 0.55, blue: 0.92)),
        ("choco", "Choco", Color(red: 0.55, green: 0.32, blue: 0.12)),
        ("polaroid", "Polaroid", Color(red: 0.92, green: 0.88, blue: 0.76)),
        ("teal", "Teal", .teal)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Chế độ", selection: $selectedTab) {
                    Text("Làm đẹp").tag(0)
                    Text("Hiệu ứng").tag(1)
                    Text("Màu").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Group {
                    if selectedTab == 0 {
                        beautyTab
                    } else if selectedTab == 1 {
                        stickersTab
                    } else {
                        filtersTab
                    }
                }

                Spacer()
            }
            .background(KinnectTheme.background)
            .navigationTitle("Hiệu ứng Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Xong") { dismiss() }
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                }
            }
        }
        .presentationDetents([.height(420), .medium, .large])
    }

    private var beautyTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        lookPresetButton(id: "off", name: "Gốc", icon: "slash.circle") {
                            beautyEnabled = false
                            smooth = 0; whiten = 0; slim = 0; eyes = 0; lips = 0; blemish = 0; blush = 0
                        }
                        lookPresetButton(id: "natural", name: "Tự nhiên", icon: "sparkles") {
                            beautyEnabled = true
                            smooth = 0.55; blemish = 0.5; eyes = 0.08; lips = 0.05; slim = 0.2; whiten = 0.3; blush = 0.1
                        }
                        lookPresetButton(id: "glass", name: "Da căng", icon: "drop.fill") {
                            beautyEnabled = true
                            smooth = 0.78; blemish = 0.85; eyes = 0.15; lips = 0.2; slim = 0.25; whiten = 0.45; blush = 0.15
                        }
                        lookPresetButton(id: "peach", name: "Đào", icon: "heart.fill") {
                            beautyEnabled = true
                            smooth = 0.62; blemish = 0.65; eyes = 0.14; lips = 0.13; blush = 0.4; whiten = 0.35; slim = 0.2
                        }
                        lookPresetButton(id: "doll", name: "Búp bê", icon: "face.smiling.inverse") {
                            beautyEnabled = true
                            smooth = 0.7; eyes = 0.72; lips = 0.27; slim = 0.4; whiten = 0.4; blemish = 0.6; blush = 0.35
                        }
                        lookPresetButton(id: "eyes", name: "Mắt to", icon: "eye.fill") {
                            beautyEnabled = true
                            eyes = 0.9; smooth = 0.55; whiten = 0.3
                        }
                        lookPresetButton(id: "lips", name: "Môi đầy", icon: "mouth.fill") {
                            beautyEnabled = true
                            lips = 0.78; blush = 0.25; smooth = 0.55; whiten = 0.3
                        }
                    }
                    .padding(.horizontal, 16)
                }

                VStack(spacing: 12) {
                    beautySliderRow(label: "Mịn da", value: $smooth)
                    beautySliderRow(label: "Sáng da", value: $whiten)
                    beautySliderRow(label: "Gọn mặt", value: $slim)
                    beautySliderRow(label: "Giảm đốm", value: $blemish)
                    beautySliderRow(label: "Mắt to", value: $eyes)
                    beautySliderRow(label: "Môi đầy", value: $lips)
                    beautySliderRow(label: "Má hồng", value: $blush)
                }
                .padding(.horizontal, 16)

                Button {
                    beautyEnabled = true
                    smooth = 0.5; whiten = 0.3; slim = 0.2; eyes = 0.2; lips = 0.0; blemish = 0.4; blush = 0.0
                } label: {
                    Text("Đặt lại mặc định")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textSecondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var stickersTab: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 14) {
                ForEach(stickerList, id: \.id) { s in
                    Button {
                        activeSticker = s.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(activeSticker == s.id ? KinnectTheme.accent.opacity(0.3) : KinnectTheme.surfaceElevated)
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Circle().stroke(activeSticker == s.id ? KinnectTheme.accentBright : Color.clear, lineWidth: 2)
                                    )
                                Text(s.emoji)
                                    .font(KinnectTheme.scaled(26))
                            }
                            Text(s.name)
                                .font(.caption2)
                                .foregroundColor(activeSticker == s.id ? KinnectTheme.accentBright : .white)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var filtersTab: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 14) {
                ForEach(filterList, id: \.id) { f in
                    Button {
                        activeFilter = f.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(f.color.opacity(0.35))
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Circle().stroke(activeFilter == f.id ? KinnectTheme.accentBright : KinnectTheme.line, lineWidth: activeFilter == f.id ? 2.5 : 1)
                                    )
                                if f.id == "none" {
                                    Image(systemName: "circle.slash")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                } else {
                                    Circle()
                                        .fill(f.color)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            Text(f.name)
                                .font(.caption2)
                                .foregroundColor(activeFilter == f.id ? KinnectTheme.accentBright : .white)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func lookPresetButton(id: String, name: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(KinnectTheme.scaled(20))
                    .foregroundColor(KinnectTheme.accentBright)
                    .frame(width: 44, height: 44)
                    .background(KinnectTheme.surfaceElevated)
                    .clipShape(Circle())
                Text(name)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private func beautySliderRow(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.accentBright)
            }
            Slider(value: value, in: 0...1)
                .tint(KinnectTheme.accentBright)
        }
    }
}
