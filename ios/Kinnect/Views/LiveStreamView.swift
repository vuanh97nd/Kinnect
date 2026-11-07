import SwiftUI

struct LiveStreamView: View {
    let onOpenWallet: () -> Void
    @ObservedObject private var appState = AppState.shared

    @State private var showCreateLiveSheet = false
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header CTA to start Live (mode selected inside CreateLiveRoomSheet — no top filter bar)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Phát trực tiếp Kinnect Live")
                            .font(.headline)
                            .foregroundColor(.white)
                            .kinnectMultiline()
                        Text("Chọn chế độ Trò chuyện hoặc Chơi game khi bắt đầu phát")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    Spacer()
                    Button {
                        showCreateLiveSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            KinnectIcon(glyph: .live, size: 20, selected: true, tint: .white)
                            Text("Phát Live")
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                        .foregroundColor(.white)
                    }
                    .accessibilityLabel("Bắt đầu phát Live")
                }
                .kinnectCard()

                if appState.liveRooms.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        KinnectIcon(glyph: .live, size: 40, tint: KinnectTheme.textSecondary)
                        Text("Hiện chưa có phòng Live nào đang phát")
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)
                } else {
                    // Unified scrollable stream of Live rooms
                    LazyVStack(spacing: 12) {
                        ForEach(appState.liveRooms) { room in
                            Button {
                                joinLiveRoom(room)
                            } label: {
                                liveRoomCard(room)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(KinnectTheme.background)
        .navigationTitle("Phòng Live")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await fetchLiveRooms()
        }
        .task {
            await fetchLiveRooms()
        }
        .sheet(isPresented: $showCreateLiveSheet) {
            CreateLiveRoomSheet()
        }
    }

    private func liveRoomCard(_ room: LiveRoomItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 4) {
                    KinnectIcon(glyph: .live, size: 14, selected: true, tint: .white)
                    Text("LIVE")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(KinnectTheme.danger))
                .foregroundColor(.white)

                HStack(spacing: 4) {
                    KinnectIcon(glyph: room.liveMode == "game" ? .game : .messages, size: 15, tint: KinnectTheme.accentBright)
                    Text(room.liveMode == "game" ? "Chơi game" : "Trò chuyện")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                }

                Spacer()

                HStack(spacing: 4) {
                    KinnectIcon(glyph: .eye, size: 15, tint: KinnectTheme.textSecondary)
                    Text("\(room.viewerCount)")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                KinnectAvatarView(
                    name: room.hostName,
                    avatarURL: room.hostAvatarUrl,
                    colorHex: room.hostAvatarColor,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(room.hostName)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            if room.liveMode == "game" && !room.gameTitle.isEmpty {
                Text("Game: \(room.gameTitle)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(KinnectTheme.warning)
                    .lineLimit(1)
            }
        }
        .kinnectCard()
    }

    private func fetchLiveRooms() async {
        isLoading = true
        defer { isLoading = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/rooms") {
            let list = res["rooms"] as? [[String: Any]] ?? []
            appState.liveRooms = list.map(LiveRoomItem.from)
        }
    }

    private func joinLiveRoom(_ room: LiveRoomItem) {
        appState.currentLiveRoom = room
        appState.isCurrentLiveHost = false
        appState.liveChatMessages = []
        NativeSocketClient.shared.sendJSON([
            "type": "join",
            "roomId": room.id
        ])
    }
}

struct CreateLiveRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var title = ""
    @State private var topic = "Giao lưu kết bạn"
    @State private var liveMode = "chat" // "chat" | "game" (NO karaoke)
    @State private var gameTitle = "Liên Quân Mobile"
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Chế độ phát trực tiếp") {
                    Picker("Chế độ", selection: $liveMode) {
                        Text("💬 Trò chuyện trực tiếp").tag("chat")
                        Text("🎮 Chơi game").tag("game")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Thông tin phòng Live") {
                    TextField("Tiêu đề phòng Live", text: $title)
                    TextField("Chủ đề", text: $topic)
                    if liveMode == "game" {
                        TextField("Tên tựa game đang chơi", text: $gameTitle)
                    }
                }
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
                    Button("Phát ngay") {
                        Task { await startHostLive() }
                    }
                    .disabled(isStarting)
                }
            }
        }
    }

    private func startHostLive() async {
        isStarting = true
        defer { isStarting = false }
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
    }
}

struct LiveRoomFullScreenView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared

    @State private var chatInput = ""
    @State private var giftCatalog: [LiveGiftCatalogItem] = []
    @State private var giftPriceVersion: Int = 1
    @State private var showGiftSheet = false

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
                            KinnectIconButton(
                                glyph: .report,
                                label: "Báo cáo phòng Live",
                                tint: .white
                            ) {
                                appState.activeReportContext = UGCReportContext(
                                    targetType: "live",
                                    targetId: room.id,
                                    targetUserId: room.hostUserId,
                                    targetTitle: room.title
                                )
                            }
                        }

                        KinnectIconButton(
                            glyph: .close,
                            label: "Rời phòng Live",
                            tint: .white
                        ) {
                            leaveLiveRoom()
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
                        TextField("Trò chuyện trong phòng Live...", text: $chatInput)
                            .padding(10)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .foregroundColor(.white)

                        KinnectIconButton(
                            glyph: .send,
                            label: "Gửi bình luận Live",
                            tint: KinnectTheme.accentBright
                        ) {
                            sendLiveChat()
                        }

                        KinnectIconButton(
                            glyph: .heart,
                            label: "Thả tim Live",
                            tint: KinnectTheme.accentBright
                        ) {
                            NativeSocketClient.shared.sendJSON([
                                "type": "live-reaction",
                                "reaction": "heart"
                            ])
                        }

                        KinnectIconButton(
                            glyph: .gift,
                            label: "Tặng quà Live",
                            tint: KinnectTheme.warning
                        ) {
                            showGiftSheet = true
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
            }
            .task {
                await loadGiftCatalog()
            }
            .sheet(isPresented: $showGiftSheet) {
                LiveGiftDrawerSheet(
                    gifts: giftCatalog,
                    priceVersion: giftPriceVersion
                )
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
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/gifts") {
            let items = res["gifts"] as? [[String: Any]] ?? []
            self.giftCatalog = items.map(LiveGiftCatalogItem.from)
            self.giftPriceVersion = res["priceVersion"] as? Int ?? 1
        }
    }
}

struct LiveGiftDrawerSheet: View {
    let gifts: [LiveGiftCatalogItem]
    let priceVersion: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                    ForEach(gifts) { gift in
                        Button {
                            sendGift(gift)
                        } label: {
                            VStack(spacing: 6) {
                                Text(gift.emoji)
                                    .font(.largeTitle)
                                Text(gift.label)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                Text("\(gift.coins) xu")
                                    .font(.caption2)
                                    .foregroundColor(KinnectTheme.warning)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
                        }
                    }
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Gửi quà tặng thử nghiệm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private func sendGift(_ gift: LiveGiftCatalogItem) {
        let reqId = "gift_\(gift.id)_\(UUID().uuidString)"
        NativeSocketClient.shared.sendJSON([
            "type": "live-reaction",
            "reaction": gift.id,
            "quantity": 1,
            "requestId": reqId,
            "priceVersion": priceVersion
        ])
        dismiss()
    }
}

