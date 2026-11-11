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
                    Text("Hiện chưa có phòng Live nào đang phát")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Khi có người phát trực tiếp, luồng Live sẽ tự động xuất hiện tại đây để bạn vuốt xem.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        showCreateLiveSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 16, weight: .bold))
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
            }
        }
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
            guard newIndex < appState.liveRooms.count else { return }
            let room = appState.liveRooms[newIndex]
            appState.joinLiveRoom(room)
            likesCount = room.likesCount
        }
        .onDisappear {
            appState.leaveCurrentLiveRoom()
        }
        .sheet(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet(onStarted: {
                Task {
                    await fetchLiveRooms()
                }
            })
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
            let items = res["gifts"] as? [[String: Any]] ?? []
            self.giftCatalog = items.map(LiveGiftCatalogItem.from)
            self.giftPriceVersion = res["priceVersion"] as? Int ?? 1
        }
    }

    private func liveStreamPage(_ room: LiveRoomItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            // WebRTC Video Canvas with Fallback connecting state
            ZStack {
                if appState.isCurrentLiveHost, let localTrack = webrtc.liveLocalVideoTrack {
                    WebRTCVideoRendererView(track: localTrack, mirror: webrtc.usingFrontCamera)
                } else if let remoteTrack = webrtc.liveRemoteVideoTrack {
                    WebRTCVideoRendererView(track: remoteTrack, mirror: false)
                } else {
                    // Playable live video fallback with vignette overlay (Parity Android 1.2.12 build 118)
                    ZStack {
                        ShortClipPlayer(
                            path: UIReviewFixture.samplePlayableVideoURL()?.absoluteString ?? "https://kinnect.io.vn/media/welcome-feed-demo.mp4",
                            active: true
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
                }
            }

            // Overlays Container
            VStack {
                // Top Header Overlay
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

                // Bottom Content: Comments + Right Actions
                HStack(alignment: .bottom, spacing: 12) {
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
                            chatBubble(name: "kinnect_mod", text: "Chào mừng bạn đến với phòng Live của \(room.hostName)!", colorHex: "#A855F7")
                            chatBubble(name: "Thanh Trúc", text: "Chào anh Nam nhé! Chúc anh buổi live vui vẻ ❤️", colorHex: "#EC4899")
                            chatBubble(name: "kinnect_user", text: "Âm thanh và hình ảnh rất nét ạ!", colorHex: "#22C55E")
                        } else {
                            ForEach(appState.liveChatMessages.suffix(6)) { msg in
                                chatBubble(name: msg.user.name, text: msg.text, colorHex: msg.user.avatarColor)
                            }
                        }

                        // Message input field
                        HStack(spacing: 8) {
                            TextField("Bình luận phòng Live...", text: $chatText)
                                .padding(.horizontal, 12)
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

                    // Right Floating Action Sidebar
                    VStack(spacing: 16) {
                        // Gift Drawer button
                        Button {
                            showGiftDrawer = true
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(KinnectTheme.primaryGradient)
                                        .frame(width: 44, height: 44)
                                    KinnectIcon(glyph: .gift, size: 22, selected: true, tint: .white)
                                }
                                Text("Tặng quà")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Tặng quà cho streamer")

                        // Like button
                        Button {
                            isLiked = true
                            likesCount += 1
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
                                    KinnectIcon(
                                        glyph: .heart,
                                        size: 24,
                                        selected: isLiked,
                                        tint: isLiked ? KinnectTheme.danger : .white
                                    )
                                }
                                Text("\(likesCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel(isLiked ? "Bỏ thích" : "Thả tim")

                        // Share button (Real permalink copy + UIActivityViewController presentation)
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
                                    KinnectIcon(glyph: .share, size: 22, tint: .white)
                                }
                                Text("Chia sẻ")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityLabel("Chia sẻ phòng Live")
                    }
                    .padding(.bottom, 6)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 38)
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
        defer { isLoading = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/rooms") {
            let list = res["rooms"] as? [[String: Any]] ?? []
            appState.liveRooms = list.map(LiveRoomItem.from)
        }
    }
}

struct CreateLiveRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    var onStarted: (() -> Void)? = nil

    @State private var title = ""
    @State private var topic = "Giao lưu kết bạn"
    @State private var liveMode = "chat" // "chat" | "game" (NO karaoke)
    @State private var gameTitle = "Liên Quân Mobile"
    @State private var isStarting = false
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

    var body: some View {
        NavigationStack {
            Form {
                roomInfoSection
                deviceSection
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Bắt đầu phát Live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bắt đầu Live") {
                        Task { await startHostLive() }
                    }
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

    private var liveModeSection: some View {
        Section("Chế độ phát trực tiếp") {
            Picker("Chế độ", selection: $liveMode) {
                Text("💬 Trò chuyện trực tiếp").tag("chat")
                Text("🎮 Chơi game").tag("game")
            }
            .pickerStyle(.segmented)
        }
    }

    private var roomInfoSection: some View {
        Section("Thông tin phòng Live") {
            TextField("Tiêu đề buổi Live", text: $title)
            TextField("Chủ đề", text: $topic)
        }
    }

    private var deviceSection: some View {
        Section("Thiết bị & Hiệu ứng") {
            HStack(spacing: 12) {
                Button {
                    NativeWebRTCManager.shared.flipCamera()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "camera.rotate.fill")
                            .font(.title3)
                        Text("Lật camera")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(KinnectTheme.surfaceElevated)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button {
                    showPreviewEffects = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.title3)
                            .foregroundColor(KinnectTheme.accentBright)
                        Text("Làm đẹp")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(KinnectTheme.surfaceElevated)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button {
                    previewMicEnabled.toggle()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: previewMicEnabled ? "mic.fill" : "mic.slash.fill")
                            .font(.title3)
                            .foregroundColor(previewMicEnabled ? KinnectTheme.success : KinnectTheme.danger)
                        Text("Micro")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(KinnectTheme.surfaceElevated)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func startHostLive() async {
        isStarting = true
        defer { isStarting = false }
        _ = await MediaPermissionHandler.shared.requestMicrophoneAccess()
        _ = await MediaPermissionHandler.shared.requestCameraAccess()
        await NativeWebRTCManager.shared.startLiveHostBroadcast()

        let roomTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Phòng Live của \(appState.currentUser?.name ?? "Kinnect")"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        NativeSocketClient.shared.sendJSON([
            "type": "create",
            "title": roomTitle,
            "topic": topic,
            "liveMode": liveMode,
            "gameTitle": liveMode == "game" ? gameTitle : ""
        ])
        dismiss()
        onStarted?()
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
                        Text(room.gamePaused ? "Chủ phòng đang tạm dừng màn hình game" : "Đang kết nối luồng video Live...")
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                }

                // Live Color Filter Grading Overlay
                if activeLiveFilter != "none" {
                    LiveFilterColorOverlay(filterId: activeLiveFilter)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                VStack {
                    // Top bar
                    HStack(spacing: 10) {
                        KinnectAvatarView(
                            name: room.hostName,
                            avatarURL: room.hostAvatarUrl,
                            colorHex: room.hostAvatarColor,
                            size: 38
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.title)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(room.liveMode == "game" ? "🎮 \(room.gameTitle)" : "💬 Trò chuyện")
                                    .font(.caption2)
                                    .foregroundColor(KinnectTheme.accentBright)
                                Text("• 👁 \(room.viewerCount)")
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }

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
                                Text(room.gamePaused ? "Tiếp tục Game" : "Tạm ẩn Game")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(KinnectTheme.warning))
                                    .foregroundColor(.black)
                            }
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
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Circle().fill(Color.black.opacity(0.45)))
                            }
                        }

                        Button {
                            leaveLiveRoom()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Circle().fill(KinnectTheme.danger))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                    if let banner = appState.liveLastReactionBanner {
                        Text(banner)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                            .padding(.top, 4)
                    }

                    Spacer()

                    // Chat list
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
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.black.opacity(0.5))
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(maxHeight: 190)

                    // Bottom controls
                    HStack(spacing: 8) {
                        TextField("Trò chuyện...", text: $chatInput)
                            .padding(10)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .foregroundColor(.white)

                        Button {
                            sendLiveChat()
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Circle().fill(KinnectTheme.accent))
                        }

                        if appState.isCurrentLiveHost {
                            Button {
                                NativeWebRTCManager.shared.flipCamera()
                            } label: {
                                Image(systemName: "camera.rotate.fill")
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                            }
                            .accessibilityLabel("Lật camera")

                            Button {
                                hostMicMuted.toggle()
                                NativeWebRTCManager.shared.setMicrophoneMuted(hostMicMuted)
                            } label: {
                                Image(systemName: hostMicMuted ? "mic.slash.fill" : "mic.fill")
                                    .foregroundColor(hostMicMuted ? KinnectTheme.danger : .white)
                                    .padding(10)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                            }
                            .accessibilityLabel(hostMicMuted ? "Bật micro" : "Tắt micro")
                        }

                        // Hiệu ứng Live (Làm đẹp, Sticker AR, Bộ lọc màu)
                        Button {
                            showEffectsSheet = true
                        } label: {
                            Image(systemName: "sparkles")
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .accessibilityLabel("Hiệu ứng Live")

                        Button {
                            triggerLiveReaction(symbol: "💜", kind: "heart", room: room.id)
                        } label: {
                            Text("💜")
                                .font(.title3)
                                .padding(8)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }

                        Button {
                            showGiftSheet = true
                        } label: {
                            Image(systemName: "gift.fill")
                                .foregroundColor(KinnectTheme.warning)
                                .padding(10)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }

                // AR Face Sticker in Live
                if activeLiveSticker != "none" {
                    LiveStickerOverlayView(stickerId: activeLiveSticker)
                        .allowsHitTesting(false)
                }

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
            .task {
                await loadGiftCatalog()
            }
            .sheet(isPresented: $showGiftSheet) {
                LiveGiftDrawerSheet(
                    roomId: room.id,
                    gifts: giftCatalog,
                    priceVersion: giftPriceVersion,
                    onGiftSent: { gift, qty in
                        triggerLiveReaction(symbol: gift.emoji, kind: gift.id, room: room.id)
                        triggerGiftEffect(gift: gift, qty: qty, senderName: appState.currentUser?.name ?? "Bạn")
                    }
                )
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
        NativeSocketClient.shared.sendJSON(["type": "leave"])
        webrtc.stopLiveSession()
        appState.currentLiveRoom = nil
    }

    private func loadGiftCatalog() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/gifts"),
           let items = res["gifts"] as? [[String: Any]], !items.isEmpty {
            self.giftCatalog = items.map(LiveGiftCatalogItem.from)
            self.giftPriceVersion = res["priceVersion"] as? Int ?? 1
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

    private let quantities = [1, 2, 5, 10, 50]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quantity / Combo Multiplier Pills matching Android & Web
                HStack(spacing: 10) {
                    Text("Số lượng:")
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.textSecondary)

                    ForEach(quantities, id: \.self) { qty in
                        Button {
                            selectedQuantity = qty
                        } label: {
                            HStack(spacing: 4) {
                                if let img = UIImage(named: "kg20261109_combo_x\(qty)") {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 18)
                                } else {
                                    Text("x\(qty)")
                                        .font(.caption.bold())
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(selectedQuantity == qty ? KinnectTheme.accentBright : KinnectTheme.surfaceElevated)
                            )
                            .foregroundColor(selectedQuantity == qty ? .white : KinnectTheme.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(gifts) { gift in
                            Button {
                                sendGift(gift)
                            } label: {
                                VStack(spacing: 6) {
                                    giftIconView(gift)
                                    Text(gift.label)
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    HStack(spacing: 3) {
                                        KinnectIcon(glyph: .coin, size: 12, selected: true, tint: KinnectTheme.warning)
                                        Text("\(gift.coins * selectedQuantity) xu")
                                            .font(.caption2.bold())
                                            .foregroundColor(KinnectTheme.warning)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(KinnectTheme.surfaceElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(KinnectTheme.background)
            .navigationTitle("Tặng quà phòng Live")
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
        } else {
            Text(gift.emoji)
                .font(.system(size: 38))
        }
    }

    private func sendGift(_ gift: LiveGiftCatalogItem) {
        let reqId = "gift_\(gift.id)_\(UUID().uuidString)"
        NativeSocketClient.shared.sendJSON([
            "type": "live-reaction",
            "room": roomId,
            "kind": gift.id,
            "quantity": selectedQuantity,
            "fundingSource": "gifted",
            "requestId": reqId,
            "priceVersion": priceVersion
        ])
        onGiftSent?(gift, selectedQuantity)
        dismiss()
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
                                    .font(.system(size: 26))
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
                    .font(.system(size: 20))
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
