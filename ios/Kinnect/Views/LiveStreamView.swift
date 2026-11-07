import SwiftUI

struct LiveStreamView: View {
    let onOpenWallet: () -> Void
    @ObservedObject private var appState = AppState.shared

    @State private var selectedIndex = 0
    @State private var isLoading = false
    @State private var chatText = ""
    @State private var likesCount = 142
    @State private var isLiked = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

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
                // Unified vertical swipe viewer for all Live streams (Parity Android 1.2.12 build 118)
                TabView(selection: $selectedIndex) {
                    ForEach(Array(appState.liveRooms.enumerated()), id: \.element.id) { index, room in
                        liveStreamPage(room)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .top)
            }
        }
        .task {
            await fetchLiveRooms()
        }
    }

    private func liveStreamPage(_ room: LiveRoomItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Live Stream Video Canvas
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
                            Text("Đang kết nối luồng phát trực tiếp HD")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                )
                .ignoresSafeArea()

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
                .padding(.top, 54)

                Spacer()

                // Bottom Content: Comments + Right Actions
                HStack(alignment: .bottom, spacing: 12) {
                    // Chat messages stream
                    VStack(alignment: .leading, spacing: 6) {
                        chatBubble(name: "kinnect_mod", text: "Chào mừng bạn đến với phòng Live của \(room.hostName)!", colorHex: "#A855F7")
                        chatBubble(name: "Thanh Trúc", text: "Chào anh Nam nhé! Chúc anh buổi live vui vẻ ❤️", colorHex: "#EC4899")
                        chatBubble(name: "kinnect_user", text: "Âm thanh và hình ảnh rất nét ạ!", colorHex: "#22C55E")

                        // Message input field
                        HStack(spacing: 8) {
                            TextField("Bình luận phòng Live...", text: $chatText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                                .foregroundColor(.white)

                            Button {
                                if !chatText.isEmpty {
                                    chatText = ""
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
                        // Gift / Wallet button
                        Button(action: onOpenWallet) {
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
                            isLiked.toggle()
                            likesCount += isLiked ? 1 : -1
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

                        // Share button
                        Button {
                            appState.showToast("Đã sao chép liên kết phòng Live!")
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
