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
    @State private var isLoading = false
    @State private var roomLoadError = ""
    @State private var chatText = ""
    @State private var likesCount = 0
    @State private var isLiked = false
    @State private var showGiftDrawer = false
    @State private var giftCatalog: [LiveGiftCatalogItem] = []
    @State private var giftPriceVersion = 1
    @State private var showCreateLiveSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if appState.liveRooms.isEmpty && !isLoading {
                VStack(spacing: 16) {
                    KinnectIcon(glyph: .live, size: 54, tint: KinnectTheme.textSecondary)
                    Text(roomLoadError.isEmpty ? "Hiện chưa có phòng Live nào đang phát" : "Chưa tải được phòng Live")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(roomLoadError.isEmpty ? "Khi có người phát trực tiếp, luồng Live sẽ tự động xuất hiện tại đây để bạn vuốt xem." : roomLoadError)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    if !roomLoadError.isEmpty {
                        Button("Thử lại") { Task { await fetchLiveRooms() } }
                            .buttonStyle(.borderedProminent)
                    }

                    Button {
                        showCreateLiveSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "video.badge.plus")
                                .font(KinnectTheme.scaled(16, weight: .bold))
                            Text("Bắt đầu phát Live ngay")
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                        .foregroundColor(.white)
                        .shadow(color: KinnectTheme.accent.opacity(0.4), radius: 10, y: 4)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !appState.liveRooms.isEmpty {
                // Unified native vertical swipe viewer for all Live streams (Parity Android 1.2.12 build 118)
                GeometryReader { proxy in
                    if #available(iOS 17.0, *) {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(appState.liveRooms) { room in
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
                                  let idx = appState.liveRooms.firstIndex(where: { $0.id == newId }) else { return }
                            if selectedIndex != idx {
                                selectedIndex = idx
                            }
                        }
                    } else {
                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(appState.liveRooms.enumerated()), id: \.element.id) { index, room in
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
                                        if dy < -50 && selectedIndex + 1 < appState.liveRooms.count {
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
            } else if isLoading {
                ProgressView("Đang tải phòng Live...")
                    .tint(.white)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .task {
            await fetchLiveRooms()
            await loadGifts()
            if !appState.liveRooms.isEmpty && selectedIndex < appState.liveRooms.count {
                let initialRoom = appState.liveRooms[selectedIndex]
                scrolledRoomId = initialRoom.id
                appState.joinLiveRoom(initialRoom)
                likesCount = initialRoom.likesCount
            }
        }
        .onChange(of: selectedIndex) { newIndex in
            guard newIndex >= 0 && newIndex < appState.liveRooms.count else { return }
            let room = appState.liveRooms[newIndex]
            appState.joinLiveRoom(room)
            likesCount = room.likesCount
        }
        .onChange(of: appState.liveRooms.map(\.id)) { ids in
            if ids.isEmpty {
                selectedIndex = 0
                scrolledRoomId = nil
                return
            }
            if selectedIndex >= ids.count {
                selectedIndex = ids.count - 1
            }
            if let currentId = scrolledRoomId, let idx = ids.firstIndex(of: currentId) {
                if selectedIndex != idx {
                    selectedIndex = idx
                }
            } else if selectedIndex < appState.liveRooms.count {
                let fallback = appState.liveRooms[selectedIndex]
                scrolledRoomId = fallback.id
                if !appState.isCurrentLiveHost && appState.currentLiveRoom?.id != fallback.id {
                    appState.joinLiveRoom(fallback)
                }
            }
        }
        .onDisappear {
            appState.leaveCurrentLiveRoom()
        }
        .fullScreenCover(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet(
                initialLiveMode: "chat",
                onStarted: {
                    Task {
                        await fetchLiveRooms()
                    }
                }
            )
        }
        .sheet(isPresented: $showGiftDrawer) {
            if !appState.liveRooms.isEmpty && selectedIndex < appState.liveRooms.count {
                LiveGiftDrawerSheet(
                    roomId: appState.liveRooms[selectedIndex].id,
                    gifts: giftCatalog,
                    priceVersion: giftPriceVersion
                )
            }
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

            // Overlays Container
            VStack {
                // Top Header Overlay (kept clean matching original viewer)
                HStack(spacing: 10) {
                    // Streamer Info Pill
                    HStack(spacing: 8) {
                        KinnectAvatarView(
                            name: room.hostName,
                            avatarURL: room.hostAvatarUrl,
                            colorHex: room.hostAvatarColor,
                            size: 36
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.hostName)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            HStack(spacing: 4) {
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .black))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(KinnectTheme.danger))
                                    .foregroundColor(.white)
                                Text("• 👁 \(room.viewerCount)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))

                    // Topic / Game Badge
                    HStack(spacing: 5) {
                        KinnectIcon(
                            glyph: room.liveMode == "game" ? .game : .messages,
                            size: 14,
                            tint: KinnectTheme.accentBright
                        )
                        Text(room.liveMode == "game" ? (room.gameTitle.isEmpty ? "Chơi game" : room.gameTitle) : "Trò chuyện")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.18)))

                    Spacer()

                    // Go Live Button
                    Button {
                        showCreateLiveSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Phát Live")
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.4), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 54)

                Spacer()

                // Bottom Content: Comments + Right Vertical Action Sidebar
                HStack(alignment: .bottom, spacing: 10) {
                    // Chat messages stream
                    VStack(alignment: .leading, spacing: 6) {
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
                            TextField("Bình luận phòng Live...", text: $chatText)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
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
                                KinnectIcon(glyph: .send, size: 20, selected: true, tint: KinnectTheme.accentBright)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right Floating Action Sidebar (uniform column alignment & right-edge clearance)
                    VStack(spacing: 16) {
                        Button {
                            showGiftDrawer = true
                        } label: {
                            liveVerticalActionButtonLabel(title: "Tặng quà") {
                                ZStack {
                                    Circle()
                                        .fill(KinnectTheme.primaryGradient)
                                        .frame(width: 44, height: 44)
                                    KinnectIcon(glyph: .gift, size: 22, selected: true, tint: .white)
                                }
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
                            liveVerticalActionButtonLabel(title: "\(likesCount)") {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                        .frame(width: 44, height: 44)
                                    KinnectIcon(
                                        glyph: .heart,
                                        size: 24,
                                        selected: isLiked,
                                        tint: isLiked ? KinnectTheme.danger : .white
                                    )
                                }
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
                            liveVerticalActionButtonLabel(title: "Chia sẻ") {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                        .frame(width: 44, height: 44)
                                    KinnectIcon(glyph: .share, size: 22, tint: .white)
                                }
                            }
                        }
                        .accessibilityLabel("Chia sẻ phòng Live")
                    }
                    .padding(.bottom, 6)
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.bottom, 38)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func liveVerticalActionButtonLabel<Icon: View>(
        title: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        VStack(spacing: 4) {
            icon()
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
        }
        .frame(width: 56)
        .contentShape(Rectangle())
    }

    private func chatBubble(name: String, text: String, colorHex: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(name + ":")
                .font(.caption2.bold())
                .foregroundColor(KinnectTheme.serverColor(colorHex))
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

    @StateObject private var previewController = CameraCaptureController()
    @State private var previewFrontCamera = true
    @State private var previewFlashOn = false

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
        let normalized = (initialLiveMode == "game") ? "game" : "chat"
        _liveMode = State(initialValue: normalized)
        _topic = State(initialValue: normalized == "game" ? "Chơi game cùng khán giả" : "Giao lưu kết bạn")
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

    private var isGameMode: Bool { liveMode == "game" }

    private var resolvedGameName: String {
        let trimmed = customGameName.trimmingCharacters(in: .whitespacesAndNewlines)
        if gameTitle == "Khác…" {
            return trimmed.isEmpty ? "Trò chơi" : trimmed
        }
        return gameTitle
    }

    private var hasActiveEffects: Bool {
        previewFilter != "none" || previewSticker != "none"
    }

    var body: some View {
        ZStack {
            preLiveBackdrop

            VStack(spacing: 12) {
                preLiveTopHeader
                preLiveRoomCoverCard

                if let createErrorMessage, !createErrorMessage.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(KinnectTheme.liveCoralError)
                        Text(createErrorMessage)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                            .kinnectMultiline()
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.red.opacity(0.28))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                            )
                    )
                }

                Spacer(minLength: 8)

                if isGameMode {
                    preLiveGameSetupDeck
                } else {
                    HStack(alignment: .bottom) {
                        Spacer()
                        preLiveStudioRail
                    }
                }

                preLiveBottomDock
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onChange(of: liveMode) { nextMode in
            if nextMode == "game" {
                previewController.stop()
            } else if !UIReviewFixture.isEnabled {
                previewController.configureIfAuthorized(initialPosition: previewFrontCamera ? .front : .back)
                previewController.start()
            }
        }
        .onDisappear {
            previewController.stop()
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

    @ViewBuilder
    private var preLiveBackdrop: some View {
        if isGameMode {
            ZStack {
                LinearGradient(
                    colors: KinnectTheme.liveGameStageColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [KinnectTheme.liveGameEmerald.opacity(0.28), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 210
                        )
                    )
                    .frame(width: 360, height: 360)
                    .offset(x: 90, y: -120)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [KinnectTheme.liveGameCyan.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: 180
                        )
                    )
                    .frame(width: 320, height: 320)
                    .offset(x: -110, y: 120)
            }
            .ignoresSafeArea()
        } else {
            ZStack {
                LiveCameraPreviewView(
                    controller: previewController,
                    isFlashOn: $previewFlashOn,
                    isUsingFrontCamera: $previewFrontCamera,
                    showGrid: false
                )
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.62), location: 0.0),
                        .init(color: Color.black.opacity(0.18), location: 0.35),
                        .init(color: Color.black.opacity(0.22), location: 0.65),
                        .init(color: Color.black.opacity(0.84), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
    }

    private var preLiveTopHeader: some View {
        HStack(spacing: 10) {
            Button {
                previewController.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                    )
            }
            .disabled(isStarting)
            .accessibilityLabel("Đóng màn hình chuẩn bị Live")

            HStack(spacing: 6) {
                Circle()
                    .fill(isGameMode ? KinnectTheme.liveGameMint : KinnectTheme.liveCrimson)
                    .frame(width: 7, height: 7)
                Text(isGameMode ? "Chơi game · \(resolvedGameName)" : "Trực tiếp · Trò chuyện")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().stroke(
                            (isGameMode ? KinnectTheme.liveGameEmerald : Color.white).opacity(0.22),
                            lineWidth: 0.8
                        )
                    )
            )

            Spacer()

            Text("HD 720p")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.42))
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.8))
                )
        }
    }

    private var preLiveRoomCoverCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottom) {
                    KinnectAvatarView(
                        name: appState.currentUser?.name ?? "Kinnect",
                        avatarURL: appState.currentUser?.avatarUrl ?? "",
                        colorHex: appState.currentUser?.avatarColor ?? "#7C3AED",
                        size: 52
                    )
                    Text(isGameMode ? "GAME" : "LIVE")
                        .font(.system(size: 8.5, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                isGameMode
                                    ? KinnectTheme.liveGameEmerald
                                    : KinnectTheme.liveCrimson
                            )
                        )
                        .offset(y: 4)
                }

                VStack(alignment: .leading, spacing: 5) {
                    TextField(
                        isGameMode ? "Đặt tiêu đề buổi Live Game…" : "Thêm tiêu đề thu hút người xem…",
                        text: $title
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                    HStack(spacing: 6) {
                        Image(systemName: isGameMode ? "gamecontroller.fill" : "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isGameMode ? KinnectTheme.liveGameMint : KinnectTheme.accentBright)
                        Text(isGameMode ? "Phát luồng Game · \(resolvedGameName)" : topic)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                }
            }

            if !isGameMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(chatTopics, id: \.self) { item in
                            let selected = (topic == item)
                            Button {
                                topic = item
                            } label: {
                                Text(item)
                                    .font(.system(size: 11.5, weight: selected ? .bold : .medium))
                                    .foregroundColor(selected ? .black : .white.opacity(0.86))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(selected ? Color.white : Color.white.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke((isGameMode ? KinnectTheme.liveGameEmerald : Color.white).opacity(0.18), lineWidth: 0.9)
                )
        )
    }

    private var preLiveStudioRail: some View {
        VStack(spacing: 14) {
            studioRailButton(
                icon: "camera.rotate.fill",
                label: "Lật cam",
                tint: .white,
                isActive: false
            ) {
                previewFrontCamera.toggle()
                NativeWebRTCManager.shared.usingFrontCamera = previewFrontCamera
            }

            studioRailButton(
                icon: "wand.and.stars",
                label: "Làm đẹp",
                tint: previewBeautyOn ? KinnectTheme.accentBright : .white,
                isActive: previewBeautyOn
            ) {
                showPreviewEffects = true
            }

            studioRailButton(
                icon: "camera.filters",
                label: "Hiệu ứng",
                tint: hasActiveEffects ? KinnectTheme.accentBright : .white,
                isActive: hasActiveEffects
            ) {
                showPreviewEffects = true
            }

            studioRailButton(
                icon: previewMicEnabled ? "mic.fill" : "mic.slash.fill",
                label: previewMicEnabled ? "Micro" : "Tắt mic",
                tint: previewMicEnabled ? KinnectTheme.liveGameMint : KinnectTheme.liveCoralError,
                isActive: !previewMicEnabled
            ) {
                previewMicEnabled.toggle()
            }
        }
        .padding(.bottom, 6)
    }

    private func studioRailButton(
        icon: String,
        label: String,
        tint: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle().stroke(
                                isActive ? tint.opacity(0.65) : Color.white.opacity(0.18),
                                lineWidth: 1
                            )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(tint)
                }
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.65), radius: 2, y: 1)
            }
            .frame(width: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var preLiveGameSetupDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(KinnectTheme.liveGameMint)
                    Text("THIẾT LẬP CHƠI GAME")
                        .font(.system(size: 11, weight: .black))
                        .tracking(0.6)
                        .foregroundColor(KinnectTheme.liveGameMint)
                }
                Spacer()
                Button {
                    previewMicEnabled.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: previewMicEnabled ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(previewMicEnabled ? "Mic Bật" : "Mic Tắt")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(previewMicEnabled ? KinnectTheme.liveGameMint : KinnectTheme.liveCoralError)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(popularGames, id: \.self) { game in
                        let selected = (gameTitle == game)
                        Button {
                            gameTitle = game
                        } label: {
                            Text(game)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selected ? .black : .white.opacity(0.9))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selected ? KinnectTheme.liveGameMint : Color.white.opacity(0.11))
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
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.09)))
            }

            VStack(spacing: 8) {
                Toggle("Âm thanh game", isOn: $gameSound)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .tint(KinnectTheme.liveGameEmerald)

                Toggle("Bình luận nổi trên màn hình", isOn: $gameComments)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .tint(KinnectTheme.liveGameEmerald)
            }

            Text("Hiển thị huy hiệu Game trực tiếp, đồng bộ bảng xếp hạng quà tặng và bình luận thời gian thực.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.65))
                .kinnectMultiline()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.5))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(KinnectTheme.liveGameEmerald.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var preLiveBottomDock: some View {
        VStack(spacing: 14) {
            Button {
                Task { await startHostLive() }
            } label: {
                HStack(spacing: 9) {
                    if isStarting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: isGameMode ? "gamecontroller.fill" : "dot.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(isStarting ? "Đang khởi tạo phòng Live…" : (isGameMode ? "Bắt đầu Live Chơi game" : "Bắt đầu phát Live"))
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    Capsule().fill(
                        isGameMode
                            ? KinnectTheme.liveGameCTAGradient
                            : KinnectTheme.liveChatCTAGradient
                    )
                )
                .foregroundColor(.white)
                .shadow(color: (isGameMode ? KinnectTheme.liveGameEmerald : KinnectTheme.accent).opacity(0.45), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(isStarting)

            // Bottom Studio Mode Switcher (TikTok Live / Bigo Live style — 100% distinct Trò chuyện vs Chơi game)
            HStack(spacing: 28) {
                modeSwitchButton(id: "chat", title: "Trò chuyện", icon: "video.fill")
                modeSwitchButton(id: "game", title: "Chơi game", icon: "gamecontroller.fill")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.8))
            )
        }
    }

    private func modeSwitchButton(id: String, title: String, icon: String) -> some View {
        let selected = (liveMode == id)
        let accent = (id == "game") ? KinnectTheme.liveGameMint : KinnectTheme.livePinkHighlight
        return Button {
            switchLiveMode(to: id)
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                    Text(title)
                        .font(.subheadline.weight(selected ? .bold : .medium))
                }
                .foregroundColor(selected ? .white : .white.opacity(0.55))

                Capsule()
                    .fill(selected ? accent : Color.clear)
                    .frame(width: 24, height: 3)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chế độ \(title)")
    }

    private func switchLiveMode(to nextMode: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            liveMode = (nextMode == "game") ? "game" : "chat"
            if liveMode == "game" && topic == "Giao lưu kết bạn" {
                topic = "Chơi game cùng khán giả"
            } else if liveMode == "chat" && topic == "Chơi game cùng khán giả" {
                topic = "Giao lưu kết bạn"
            }
        }
    }

    private func startHostLive() async {
        isStarting = true
        createErrorMessage = nil
        defer { isStarting = false }

        if appState.currentLiveRoom != nil {
            appState.leaveCurrentLiveRoom()
        }

        // Release pre-live preview session cleanly before WebRTC opens hardware capture.
        previewController.stop()

        let manager = NativeWebRTCManager.shared
        manager.usingFrontCamera = previewFrontCamera
        manager.updateLiveEffects(LiveVideoSettings(
            filter: previewFilter, sticker: previewSticker, beauty: previewBeautyOn,
            smooth: previewSmooth, whiten: previewWhiten, slim: previewSlim, eyes: previewEyes,
            lips: previewLips, blemish: previewBlemish, blush: previewBlush))
        guard await manager.startLiveHostBroadcast() else {
            let msg = "Cần quyền camera và micro để bắt đầu Live."
            createErrorMessage = msg
            appState.showToast(msg)
            if liveMode == "chat" && !UIReviewFixture.isEnabled {
                previewController.configureIfAuthorized(initialPosition: previewFrontCamera ? .front : .back)
                previewController.start()
            }
            return
        }
        manager.setMicrophoneMuted(!previewMicEnabled)

        let roomTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (liveMode == "game" ? "Live Game: \(resolvedGameName)" : "Phòng Live của \(appState.currentUser?.name ?? "Kinnect")")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        let createResult = await appState.createLiveRoomAndAwaitJoin(payload: [
            "title": roomTitle,
            "topic": topic,
            "liveMode": liveMode,
            "gameTitle": liveMode == "game" ? resolvedGameName : "",
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
            if liveMode == "chat" && !UIReviewFixture.isEnabled {
                previewController.configureIfAuthorized(initialPosition: previewFrontCamera ? .front : .back)
                previewController.start()
            }
        }
    }
}
