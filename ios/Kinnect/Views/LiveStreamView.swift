import SwiftUI

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

    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            if appState.liveRooms.isEmpty && !isLoading {
                VStack(spacing: 14) {
                    KinnectIcon(glyph: .live, size: 54, tint: KinnectTheme.textSecondary)
                    Text("Hiện chưa có phòng Live nào đang phát")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Khi có người phát trực tiếp, luồng Live sẽ tự động xuất hiện tại đây để bạn vuốt xem.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
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
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.05, blue: 0.22),
                                    Color(red: 0.04, green: 0.02, blue: 0.10)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            VStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(KinnectTheme.accent.opacity(0.2))
                                        .frame(width: 110, height: 110)
                                    KinnectAvatarView(
                                        name: room.hostName,
                                        avatarURL: room.hostAvatarUrl,
                                        colorHex: room.hostAvatarColor,
                                        size: 84
                                    )
                                }
                                Text(room.title)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .multilineTextAlignment(.center)
                                HStack(spacing: 6) {
                                    Circle().fill(KinnectTheme.online).frame(width: 8, height: 8)
                                    Text(room.gamePaused ? "Chủ phòng tạm dừng" : "Đang kết nối luồng Live WebRTC HD...")
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                            }
                        )
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
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)

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
                .padding(.bottom, 24)
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
                        Picker("Tựa game", selection: $gameTitle) {
                            Text("Liên Quân Mobile").tag("Liên Quân Mobile")
                            Text("Free Fire").tag("Free Fire")
                            Text("PUBG Mobile").tag("PUBG Mobile")
                            Text("Tốc Chiến").tag("Tốc Chiến")
                            Text("Play Together").tag("Play Together")
                            Text("Khác").tag("Khác")
                        }
                        Text("Lưu ý: Phát trực tiếp game sử dụng luồng âm thanh và camera native. Để truyền toàn màn hình ứng dụng bên ngoài trên iOS cần ReplayKit Broadcast Extension theo cơ chế bảo mật của Apple.")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
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
                    HStack(spacing: 10) {
                        TextField("Trò chuyện trong phòng Live...", text: $chatInput)
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
                    }
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

    private let quantities = [1, 5, 10, 100]

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
                            Text("x\(qty)")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
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

    @ViewBuilder
    private func giftIconView(_ gift: LiveGiftCatalogItem) -> some View {
        if let img = UIImage(named: "gift_\(gift.id)") ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "gift_\(gift.id)", ofType: "png") ?? "") ?? UIImage(contentsOfFile: Bundle.main.path(forResource: "gift_\(gift.id)_3d", ofType: "jpg") ?? "") {
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
        Text(symbol)
            .font(.system(size: 36))
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
