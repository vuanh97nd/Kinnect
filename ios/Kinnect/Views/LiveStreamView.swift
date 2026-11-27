import AudioToolbox
import AVFoundation
import AVKit
import SwiftUI
import UIKit
import WebRTC

enum SocketEventBridge {
    static let rawEventNotification = Notification.Name("kinnectRawSocketEvent")

    @MainActor
    static func installIfNeeded() {
        _ = AppState.shared
    }
}

struct LiveStreamView: View {
    let onOpenWallet: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("kinnect_live_gift_reduce_fx") private var reduceGiftEffects = false
    @AppStorage("kinnect_live_gift_sound") private var giftSoundEnabled = true

    @State private var selectedIndex = 0
    @State private var scrolledRoomId: String?
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var chatText = ""
    @State private var likesCount = 0
    @State private var isLiked = false
    @State private var showGiftDrawer = false
    @State private var giftCatalog: [LiveGiftCatalogItem] = []
    @State private var giftPriceVersion = 1
    @State private var showCreateLiveSheet = false
    @State private var pendingBlockLiveRoom: LiveRoomItem? = nil
    @State private var pendingBlockChatUser: KinnectUser? = nil
    @State private var activeGiftEffect: ActiveGiftEffect? = nil
    @State private var floatingReactions: [LiveFloatingReaction] = []
    @State private var isGuestMicMuted = false
    @State private var isPlaybackMuted = false
    @State private var followedHostIds: Set<String> = []
    @State private var followLoadingHostIds: Set<String> = []
    @State private var showViewersSheet = false
    @State private var showGiftLeaderboardSheet = false
    @State private var showCoHostSheet = false
    @State private var lastSentGift: LiveGiftCatalogItem? = nil
    @State private var lastSentGiftQuantity: Int = 1
    @State private var liveLayout: String = "panel"
    @StateObject private var giftComboTracker = LiveGiftComboTracker()

    var body: some View {
        ZStack(alignment: .top) {
            KinnectTheme.background.ignoresSafeArea()

            if appState.liveRooms.isEmpty && isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(KinnectTheme.accentBright)
                        .scaleEffect(1.2)
                    Text(L10n.tr("Đang tải phòng Live…"))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, appState.liveRooms.isEmpty && !isLoading {
                VStack(spacing: 14) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundColor(KinnectTheme.textSecondary)
                    Text(L10n.tr("Không thể tải danh sách phòng Live"))
                        .font(.headline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button {
                        Task { await fetchLiveRooms() }
                    } label: {
                        Text(L10n.tr("Thử lại"))
                            .font(.subheadline.bold())
                            .padding(.horizontal, 24)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Capsule().fill(KinnectTheme.liveRed))
                            .foregroundColor(.white)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.liveRooms.isEmpty && !isLoading {
                emptyLiveLobbyView
            } else {
                liveRoomsLobbyView
            }
        }
        .task {
            SocketEventBridge.installIfNeeded()
            await fetchLiveRooms()
            await loadGifts()
        }
        .onDisappear {
            if !appState.isCreatingLiveRoom && !appState.isCurrentLiveHost {
                appState.leaveCurrentLiveRoom()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kinnectLiveReactionReceived)) { notif in
            guard !appState.isCurrentLiveHost, let data = notif.userInfo as? [String: Any] else { return }
            handleIncomingReactionEvent(data)
        }
        .onReceive(NotificationCenter.default.publisher(for: SocketEventBridge.rawEventNotification)) { notif in
            guard let json = notif.userInfo as? [String: Any],
                  let type = json["type"] as? String else { return }
            let expectedRoom = appState.currentLiveRoom?.id ?? scrolledRoomId
            if let evtRoom = json["room"] as? String, !evtRoom.isEmpty,
               let expectedRoom, !expectedRoom.isEmpty,
               evtRoom != expectedRoom {
                return
            }
            if type == "live-stage", let layout = json["layout"] as? String {
                liveLayout = (layout == "grid") ? "grid" : "panel"
            }
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
                    priceVersion: giftPriceVersion,
                    onGiftSent: { gift, qty in
                        lastSentGift = gift
                        lastSentGiftQuantity = qty
                    },
                    onCatalogUpdated: { items, version in
                        giftCatalog = items
                        giftPriceVersion = version
                    },
                    comboTracker: giftComboTracker
                )
            }
        }
        .sheet(isPresented: $showViewersSheet) {
            if let room = activePageRoom {
                LiveViewersSheet(
                    roomId: room.id,
                    viewerCount: room.viewerCount,
                    isHost: room.id == appState.currentLiveRoom?.id && appState.isCurrentLiveHost
                )
            }
        }
        .sheet(isPresented: $showGiftLeaderboardSheet) {
            if let room = activePageRoom {
                LiveGiftLeaderboardSheet(
                    roomId: room.id,
                    isHost: room.id == appState.currentLiveRoom?.id && appState.isCurrentLiveHost
                )
            }
        }
        .sheet(isPresented: $showCoHostSheet) {
            if let room = activePageRoom {
                LiveCoHostManagerSheet(roomId: room.id)
            }
        }
        .onChange(of: appState.isCurrentLivePublisher) { publishing in
            if !publishing {
                isGuestMicMuted = false
            }
        }
        .alert(
            "Lời mời lên sóng Live",
            isPresented: Binding(
                get: { appState.pendingLiveGuestInvitation != nil },
                set: { if !$0 { appState.pendingLiveGuestInvitation = nil } }
            ),
            presenting: appState.pendingLiveGuestInvitation
        ) { inv in
            Button("Tham gia") {
                appState.respondToLiveGuestInvitation(accept: true, invitation: inv)
            }
            Button("Từ chối", role: .cancel) {
                appState.respondToLiveGuestInvitation(accept: false, invitation: inv)
            }
        } message: { inv in
            Text("\(inv.fromName) mời bạn tham gia phát cùng phòng Live này.")
        }
        .alert(
            "Chặn chủ phòng Live?",
            isPresented: Binding(
                get: { pendingBlockLiveRoom != nil },
                set: { if !$0 { pendingBlockLiveRoom = nil } }
            ),
            presenting: pendingBlockLiveRoom
        ) { room in
            Button("Chặn chủ phòng", role: .destructive) {
                pendingBlockLiveRoom = nil
                Task { await blockLiveHostAndExit(room) }
            }
            Button("Hủy", role: .cancel) {
                pendingBlockLiveRoom = nil
            }
        } message: { room in
            Text("Bạn sẽ rời khỏi phòng Live và không còn thấy nội dung từ \(room.hostName).")
        }
        .alert(
            "Chặn người bình luận?",
            isPresented: Binding(
                get: { pendingBlockChatUser != nil },
                set: { if !$0 { pendingBlockChatUser = nil } }
            ),
            presenting: pendingBlockChatUser
        ) { user in
            Button("Chặn người dùng", role: .destructive) {
                pendingBlockChatUser = nil
                Task {
                    await appState.blockUser(userId: user.id, userName: user.name)
                    appState.liveChatMessages.removeAll { $0.user.id == user.id }
                }
            }
            Button("Hủy", role: .cancel) {
                pendingBlockChatUser = nil
            }
        } message: { user in
            Text("Ẩn bình luận và chặn \(user.name) trên toàn bộ Kinnect.")
        }
    }

    private var activePageRoom: LiveRoomItem? {
        if let cur = appState.currentLiveRoom { return cur }
        if !appState.liveRooms.isEmpty && selectedIndex < appState.liveRooms.count {
            return appState.liveRooms[selectedIndex]
        }
        return nil
    }

    private func togglePlaybackMute() {
        isPlaybackMuted.toggle()
        RTCAudioSession.sharedInstance().isAudioEnabled = !isPlaybackMuted
    }

    private func toggleFollowHost(_ hostId: String) async {
        guard !hostId.isEmpty, !followLoadingHostIds.contains(hostId) else { return }
        followLoadingHostIds.insert(hostId)
        defer { followLoadingHostIds.remove(hostId) }
        let currentlyFollowed = followedHostIds.contains(hostId)
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(hostId)/follow",
                method: currentlyFollowed ? "DELETE" : "POST"
            )
            if currentlyFollowed {
                followedHostIds.remove(hostId)
                appState.showToast("Đã bỏ theo dõi chủ phòng.")
            } else {
                followedHostIds.insert(hostId)
                appState.showToast("Đã theo dõi chủ phòng!")
            }
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func sendQuickComboGift(_ gift: LiveGiftCatalogItem, quantity: Int, room: LiveRoomItem) {
        guard NativeSocketClient.shared.isConnected else {
            appState.showToast("Mất kết nối phòng Live.")
            return
        }
        let targetUserId = room.hostUserId
        let comboId = giftComboTracker.nextComboId(roomId: room.id, giftId: gift.id, targetUserId: targetUserId)
        let reqId = "gift_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var payload: [String: Any] = [
            "type": "live-reaction",
            "room": room.id,
            "kind": gift.id,
            "giftId": gift.id,
            "quantity": quantity,
            "comboId": comboId,
            "fundingSource": "gifted",
            "requestId": reqId,
            "priceVersion": giftPriceVersion
        ]
        if !targetUserId.isEmpty {
            payload["targetUserId"] = targetUserId
        }
        NativeSocketClient.shared.sendJSON(payload)
    }

    private func loadGifts() async {
        if giftCatalog.isEmpty, let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/live/gifts") {
            let items = (cached["items"] as? [[String: Any]]) ?? (cached["gifts"] as? [[String: Any]]) ?? []
            if !items.isEmpty {
                self.giftCatalog = items.map(LiveGiftCatalogItem.from)
            }
            self.giftPriceVersion = (cached["version"] as? Int) ?? (cached["priceVersion"] as? Int) ?? 1
        }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/gifts") {
            let items = (res["items"] as? [[String: Any]]) ?? (res["gifts"] as? [[String: Any]]) ?? []
            if !items.isEmpty {
                self.giftCatalog = items.map(LiveGiftCatalogItem.from)
            }
            self.giftPriceVersion = (res["version"] as? Int) ?? (res["priceVersion"] as? Int) ?? 1
        }
    }

    private var liveLobbyHeader: some View {
        let liveRed = KinnectTheme.liveRed
        return HStack(spacing: 10) {
            Text(L10n.tr("Trực tiếp"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(KinnectTheme.textPrimary)

            HStack(spacing: 4) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                Text("LIVE")
                    .font(.system(size: 11, weight: .black))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(liveRed))

            Spacer()

            Button {
                Task { await fetchLiveRooms() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KinnectTheme.surfaceElevated))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Làm mới danh sách Live"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var liveRoomsLobbyView: some View {
        let liveRed = KinnectTheme.liveRed
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(spacing: 0) {
            liveLobbyHeader

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(appState.liveRooms) { room in
                        Button {
                            appState.joinLiveRoom(room)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 5, height: 5)
                                        Text("LIVE")
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(liveRed))

                                    Spacer(minLength: 4)

                                    Text("👁 \(room.viewerCount)")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.black.opacity(0.45)))
                                }

                                HStack {
                                    Spacer()
                                    ZStack {
                                        Circle()
                                            .stroke(liveRed, lineWidth: 2)
                                            .frame(width: 62, height: 62)
                                        KinnectAvatarView(
                                            name: room.hostName,
                                            avatarURL: room.hostAvatarUrl,
                                            colorHex: room.hostAvatarColor,
                                            size: 56
                                        )
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 2)

                                let modeTitle = room.liveMode == "game" ? L10n.tr("Chơi game") : L10n.tr("Trò chuyện")
                                Text(modeTitle)
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(Color(hex: "#E9D5FF"))
                                    .lineLimit(1)

                                Text(room.title.isEmpty ? room.hostName : room.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                Text(room.hostName)
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "#D2CAE8"))
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(hex: "#2B1848"), Color(hex: "#161028")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .clipped()
            .refreshable {
                await fetchLiveRooms()
            }

            HStack {
                Spacer()
                Button {
                    showCreateLiveSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 15, weight: .bold))
                        Text(L10n.tr("Phát live"))
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Capsule().fill(liveRed))
                    .shadow(color: liveRed.opacity(0.32), radius: 10, y: 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(KinnectTheme.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyLiveLobbyView: some View {
        let liveRed = KinnectTheme.liveRed
        return VStack(spacing: 0) {
            liveLobbyHeader

            Spacer()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(liveRed.opacity(0.14))
                        .frame(width: 78, height: 78)
                    Circle()
                        .fill(liveRed)
                        .frame(width: 56, height: 56)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 2)

                Text(L10n.tr("Chưa có buổi live"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(L10n.tr("Hãy là người mở màn!"))
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    showCreateLiveSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 15, weight: .bold))
                        Text(L10n.tr("Phát live"))
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(liveRed))
                    .shadow(color: liveRed.opacity(0.32), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(KinnectTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func liveConnectingBackdrop(room: LiveRoomItem) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.08, blue: 0.28),
                    Color(red: 0.05, green: 0.03, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            VStack(spacing: 12) {
                KinnectAvatarView(
                    name: room.hostName,
                    avatarURL: room.hostAvatarUrl,
                    colorHex: room.hostAvatarColor,
                    size: 84
                )
                ProgressView().tint(.white)
                Text(room.gamePaused ? L10n.tr("Chủ phòng đang tạm dừng màn hình game") : L10n.tr("Đang kết nối luồng video Live..."))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    private func liveStreamPage(_ room: LiveRoomItem, containerWidth: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // WebRTC Video Canvas with Fallback connecting state
            ZStack {
                if room.id == appState.currentLiveRoom?.id,
                   appState.isCurrentLiveHost,
                   let localTrack = webrtc.liveLocalVideoTrack {
                    WebRTCVideoRendererView(track: localTrack, mirror: webrtc.usingFrontCamera)
                } else if room.id == appState.currentLiveRoom?.id,
                          let remoteTrack = webrtc.liveRemoteVideoTrack {
                    WebRTCVideoRendererView(track: remoteTrack, mirror: false)
                } else {
                    #if DEBUG
                    if UIReviewFixture.isEnabled && room.id == scrolledRoomId {
                        ZStack {
                            ShortClipPlayer(
                                path: UIReviewFixture.samplePlayableVideoURL()?.absoluteString ?? "",
                                active: true,
                                muted: true
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
                        liveConnectingBackdrop(room: room)
                    }
                    #else
                    liveConnectingBackdrop(room: room)
                    #endif
                }
            }

            // Subtle top & bottom gradient scrim so white controls stay readable on bright scenes
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.clear,
                    Color.clear,
                    Color.black.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Overlays Container
            VStack(spacing: 0) {
                // Top Header Overlay (Row 1: Streamer Pill + Go Live + Safety Menu; Row 2: Gift Leaderboard + Room Title)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // Streamer Info Pill
                        HStack(spacing: 7) {
                            KinnectAvatarView(
                                name: room.hostName,
                                avatarURL: room.hostAvatarUrl,
                                colorHex: room.hostAvatarColor,
                                size: 34
                            )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(room.hostName)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text("LIVE")
                                        .font(.system(size: 8, weight: .black))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(KinnectTheme.liveRed))
                                        .foregroundColor(.white)
                                        .fixedSize()
                                    Button {
                                        showViewersSheet = true
                                    } label: {
                                        Text("• 👁 \(room.viewerCount)")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.9))
                                            .fixedSize()
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(L10n.tr("Xem danh sách người xem"))
                                }
                            }
                            .layoutPriority(1)

                            if !room.hostUserId.isEmpty && room.hostUserId != appState.currentUser?.id {
                                let isFollowed = followedHostIds.contains(room.hostUserId)
                                Button {
                                    Task { await toggleFollowHost(room.hostUserId) }
                                } label: {
                                    Text(L10n.tr(isFollowed ? "Đang theo dõi" : "Theo dõi"))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(isFollowed ? Color.white.opacity(0.22) : KinnectTheme.accent))
                                }
                                .buttonStyle(.plain)
                                .disabled(followLoadingHostIds.contains(room.hostUserId))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.5)))

                        Spacer(minLength: 4)

                        // Viewer UGC Safety Menu (Report / Block Host — Apple Guideline 1.2)
                        Menu {
                            Button(role: .destructive) {
                                let hasPeerHost = !room.hostUserId.isEmpty && room.hostUserId != appState.currentUser?.id
                                appState.activeReportContext = UGCReportContext(
                                    targetType: hasPeerHost ? "user" : "app",
                                    targetId: hasPeerHost ? room.hostUserId : (appState.currentUser?.id ?? room.id),
                                    targetUserId: hasPeerHost ? room.hostUserId : nil,
                                    targetTitle: room.title.isEmpty
                                        ? "Phòng Live của \(room.hostName)"
                                        : "Phòng Live: \(room.hostName) — \(room.title)"
                                )
                            } label: {
                                Label("Báo cáo phòng Live", systemImage: "flag")
                            }

                            if !room.hostUserId.isEmpty && room.hostUserId != appState.currentUser?.id {
                                Button(role: .destructive) {
                                    pendingBlockLiveRoom = room
                                } label: {
                                    Label("Chặn chủ phòng", systemImage: "hand.raised.fill")
                                }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(L10n.tr("Tùy chọn phòng Live"))
                    }

                    // Row 2: Gift Leaderboard Pill + Room Title (no horizontal collision on 375pt iPhones)
                    HStack(spacing: 8) {
                        Button {
                            showGiftLeaderboardSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(KinnectTheme.warning)
                                Text(L10n.tr("BXH Quà"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel(L10n.tr("Bảng xếp hạng quà Live"))

                        if !room.title.isEmpty {
                            Text(room.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                                .shadow(color: .black.opacity(0.75), radius: 3, y: 1)
                        }

                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Spacer()

                if room.id == appState.currentLiveRoom?.id {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack {
                            Spacer()
                            LiveCoHostPiPStackView(isHostCanvas: appState.isCurrentLiveHost, layout: liveLayout)
                        }
                        if appState.isCurrentLivePublisher && !appState.isCurrentLiveHost {
                            HStack(spacing: 10) {
                                Button {
                                    isGuestMicMuted.toggle()
                                    NativeWebRTCManager.shared.setMicrophoneMuted(isGuestMicMuted)
                                } label: {
                                    Image(systemName: isGuestMicMuted ? "mic.slash.fill" : "mic.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(isGuestMicMuted ? KinnectTheme.danger : .white)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isGuestMicMuted ? "Bật micro" : "Tắt micro")

                                Button {
                                    NativeWebRTCManager.shared.flipCamera()
                                } label: {
                                    Image(systemName: "camera.rotate.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Lật camera")

                                Button {
                                    NativeSocketClient.shared.sendJSON(["type": "live-guest-leave"])
                                    appState.isCurrentLivePublisher = false
                                    isGuestMicMuted = false
                                    NativeWebRTCManager.shared.setMicrophoneMuted(false)
                                    NativeWebRTCManager.shared.stopLiveLocalMedia()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "phone.down.fill")
                                            .font(.system(size: 12, weight: .bold))
                                        Text(L10n.tr("Rời sóng"))
                                            .font(.caption2.bold())
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(Capsule().fill(KinnectTheme.liveRed))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.tr("Rời vị trí khách mời"))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }

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
                            #if DEBUG
                            if UIReviewFixture.isEnabled {
                                chatBubble(name: "Linh Nhi", text: "\(L10n.tr("Chào mừng bạn đến với phòng Live của")) \(room.hostName)!", colorHex: "#A855F7")
                                chatBubble(name: "Trần Thanh Trúc", text: "Chào anh Nam nhé! Chúc anh buổi live vui vẻ ❤️", colorHex: "#EC4899")
                                chatBubble(name: "Lê Hoàng Nam", text: "Âm thanh và hình ảnh rất nét ạ!", colorHex: "#22C55E")
                            }
                            #endif
                        } else {
                            ForEach(appState.liveChatMessages.filter { !appState.blockedUserIds.contains($0.user.id) }.suffix(6)) { msg in
                                chatBubble(senderId: msg.user.id, name: msg.user.name, text: msg.text, colorHex: msg.user.avatarColor)
                            }
                        }

                        // Message input field
                        let effectiveRoom = (room.id == appState.currentLiveRoom?.id) ? (appState.currentLiveRoom ?? room) : room
                        let isHostOfRoom = (room.id == appState.currentLiveRoom?.id && appState.isCurrentLiveHost)
                        let commentsDisabled = !effectiveRoom.comments && !isHostOfRoom
                        HStack(spacing: 8) {
                            TextField(
                                "",
                                text: $chatText,
                                prompt: Text(L10n.tr(commentsDisabled ? "Chủ phòng đã tắt bình luận" : "Bình luận phòng Live..."))
                                    .foregroundColor(.white.opacity(0.75))
                            )
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .tint(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(commentsDisabled ? 0.08 : 0.14))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                        )
                                )
                                .disabled(commentsDisabled)

                            Button {
                                guard !commentsDisabled else { return }
                                let clean = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty {
                                    chatText = ""
                                    #if DEBUG
                                    if UIReviewFixture.isEnabled {
                                        let localMsg = LiveChatMessage(
                                            id: UUID().uuidString,
                                            user: appState.currentUser ?? KinnectUser.from(["name": "Bạn"]),
                                            text: clean,
                                            createdAt: ""
                                        )
                                        appState.liveChatMessages.append(localMsg)
                                    } else {
                                        NativeSocketClient.shared.sendJSON([
                                            "type": "chat",
                                            "text": clean,
                                            "room": room.id
                                        ])
                                    }
                                    #else
                                    NativeSocketClient.shared.sendJSON([
                                        "type": "chat",
                                        "text": clean,
                                        "room": room.id
                                    ])
                                    #endif
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(commentsDisabled ? 0.3 : 0.5))
                                        .frame(width: 38, height: 38)
                                    KinnectIcon(glyph: .send, size: 20, selected: !commentsDisabled, tint: commentsDisabled ? KinnectTheme.textSecondary : KinnectTheme.accentBright)
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .disabled(commentsDisabled)
                            .accessibilityLabel("Gửi bình luận")
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right Floating Action Sidebar
                    VStack(spacing: 14) {
                        // Quick Combo Button
                        if !(room.id == appState.currentLiveRoom?.id && appState.isCurrentLiveHost),
                           let comboGift = lastSentGift {
                            Button {
                                sendQuickComboGift(comboGift, quantity: lastSentGiftQuantity, room: room)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(comboGift.emoji)
                                        .font(.system(size: 20))
                                    Text("Combo")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundColor(.white)
                                    if appState.liveGiftCombo > 0 {
                                        Text("x\(appState.liveGiftCombo)")
                                            .font(.system(size: 9, weight: .heavy))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(Color(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x47 / 255.0)))
                                .shadow(color: Color(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x47 / 255.0).opacity(0.55), radius: 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: L10n.tr("Gửi nhanh combo %@"), comboGift.label))
                        }

                        // Co-Host Request Button (for viewers)
                        if room.id == appState.currentLiveRoom?.id && !appState.isCurrentLiveHost && !appState.isCurrentLivePublisher {
                            Button {
                                if appState.hasPendingLiveGuestRequest {
                                    NativeSocketClient.shared.sendJSON(["type": "live-guest-cancel"])
                                } else {
                                    NativeSocketClient.shared.sendJSON(["type": "live-guest-request", "mode": "video"])
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(appState.hasPendingLiveGuestRequest ? KinnectTheme.warning : Color.black.opacity(0.45))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: appState.hasPendingLiveGuestRequest ? "person.crop.circle.badge.clock" : "person.badge.plus")
                                            .font(.system(size: 19, weight: .semibold))
                                            .foregroundColor(appState.hasPendingLiveGuestRequest ? .black : .white)
                                    }
                                    Text(appState.hasPendingLiveGuestRequest ? L10n.tr("Đang chờ") : L10n.tr("Lên sóng"))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.tr(appState.hasPendingLiveGuestRequest ? "Hủy yêu cầu lên sóng" : "Xin lên sóng cùng"))
                        }

                        // Playback Mute Button
                        if !(room.id == appState.currentLiveRoom?.id && appState.isCurrentLiveHost) {
                            Button {
                                togglePlaybackMute()
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.45))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: isPlaybackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(isPlaybackMuted ? KinnectTheme.danger : .white)
                                    }
                                    Text(isPlaybackMuted ? L10n.tr("Đang tắt") : L10n.tr("Âm thanh"))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.tr(isPlaybackMuted ? "Bật âm thanh Live" : "Tắt tiếng Live"))
                        }

                        // Gift Drawer button (hidden for host broadcasting their own room)
                        if !(room.id == appState.currentLiveRoom?.id && appState.isCurrentLiveHost) {
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
                                    Text(L10n.tr("Tặng quà"))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                            }
                            .accessibilityLabel("Tặng quà cho streamer")
                        }

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
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityLabel(isLiked ? "Bỏ thích" : "Thả tim")

                        // Share button (Real permalink copy + iPad-safe share sheet)
                        Button {
                            let permalink = "https://app.kinnect.io.vn/share/live/\(room.id)"
                            UIPasteboard.general.string = permalink
                            appState.showToast("Đã sao chép liên kết phòng Live!")
                            let shareItems: [Any] = [URL(string: permalink) ?? permalink]
                            KinnectShareSheet.present(items: shareItems)
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                        .frame(width: 44, height: 44)
                                    KinnectIcon(glyph: .share, size: 22, tint: .white)
                                }
                                Text(L10n.tr("Chia sẻ"))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }
                        .accessibilityLabel("Chia sẻ phòng Live")
                    }
                    .frame(width: 58)
                    .padding(.bottom, 6)
                }
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .padding(.bottom, 14)
            }
            .frame(width: containerWidth)

            if room.id == appState.currentLiveRoom?.id {
                if let giftEffect = activeGiftEffect {
                    LiveGiftBurstShowcaseView(effect: giftEffect)
                        .transition(.scale.combined(with: .opacity))
                        .zIndex(60)
                }
                ForEach(floatingReactions) { reaction in
                    LiveFloatingReactionView(symbol: reaction.symbol)
                        .position(x: reaction.x, y: reaction.y)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func handleIncomingReactionEvent(_ data: [String: Any]) {
        let isGift = (data["experience"] as? Bool) ?? (data["isGift"] as? Bool) ?? (data["giftId"] != nil)
        if isGift {
            let giftId = (data["giftId"] as? String) ?? (data["kind"] as? String) ?? "rose"
            let giftName = (data["giftName"] as? String) ?? LiveGiftCatalogItem.defaultName(for: giftId)
            let emoji = LiveGiftCatalogItem.defaultEmoji(for: giftId)
            let senderName = (data["name"] as? String) ?? "Khán giả"
            let qty = (data["quantity"] as? Int) ?? (data["quantity"] as? NSNumber)?.intValue ?? 1
            let combo = (data["comboCount"] as? Int) ?? (data["comboCount"] as? NSNumber)?.intValue ?? 1
            let recipient = (data["recipientName"] as? String) ?? ""
            let tier = (data["tier"] as? String) ?? "standard"
            if giftSoundEnabled {
                AudioServicesPlaySystemSound(1104)
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let effect = ActiveGiftEffect(
                giftId: giftId,
                giftName: giftName,
                giftEmoji: emoji,
                senderName: senderName,
                recipientName: recipient,
                quantity: qty,
                comboCount: combo,
                tier: tier
            )
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                activeGiftEffect = effect
            }
            spawnFloatingSymbol(giftId)
            let burstNanos = Self.burstDurationNanoseconds(for: tier, reduceEffects: reduceGiftEffects)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: burstNanos)
                if activeGiftEffect?.id == effect.id {
                    withAnimation(.easeOut(duration: 0.3)) {
                        activeGiftEffect = nil
                    }
                }
            }
        } else {
            let senderId = (data["senderId"] as? String) ?? ""
            if senderId != appState.currentUser?.id {
                likesCount += 1
            }
            spawnFloatingSymbol("❤️")
        }
    }

    private func spawnFloatingSymbol(_ symbol: String) {
        let screenWidth = UIScreen.main.bounds.width
        let startX = screenWidth * CGFloat.random(in: 0.68...0.88)
        let startY = UIScreen.main.bounds.height * 0.76
        let item = LiveFloatingReaction(symbol: symbol, x: startX, y: startY)
        floatingReactions.append(item)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            floatingReactions.removeAll { $0.id == item.id }
        }
    }

    private func chatBubble(senderId: String? = nil, name: String, text: String, colorHex: String) -> some View {
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
        .contextMenu {
            Button(role: .destructive) {
                let hasPeerSender = (senderId?.isEmpty == false) && senderId != appState.currentUser?.id
                appState.activeReportContext = UGCReportContext(
                    targetType: hasPeerSender ? "user" : "app",
                    targetId: hasPeerSender ? (senderId ?? "") : (appState.currentUser?.id ?? "live_comment"),
                    targetUserId: hasPeerSender ? senderId : nil,
                    targetTitle: "Bình luận Live của \(name): \"\(String(text.prefix(40)))\""
                )
            } label: {
                Label("Báo cáo bình luận", systemImage: "flag")
            }

            if let uid = senderId, !uid.isEmpty, uid != appState.currentUser?.id {
                Button(role: .destructive) {
                    pendingBlockChatUser = KinnectUser(id: uid, name: name)
                } label: {
                    Label("Chặn \(name)", systemImage: "hand.raised.fill")
                }
            }
        }
    }

    private func blockLiveHostAndExit(_ room: LiveRoomItem) async {
        appState.leaveCurrentLiveRoom()
        await appState.blockUser(userId: room.hostUserId, userName: room.hostName)
        appState.liveRooms.removeAll { $0.hostUserId == room.hostUserId }
        if !appState.liveRooms.isEmpty {
            selectedIndex = min(selectedIndex, appState.liveRooms.count - 1)
            let nextRoom = appState.liveRooms[selectedIndex]
            scrolledRoomId = nextRoom.id
            appState.joinLiveRoom(nextRoom)
            likesCount = nextRoom.likesCount
        } else {
            scrolledRoomId = nil
        }
    }

    private func fetchLiveRooms() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/live/rooms")
            let list = res["rooms"] as? [[String: Any]] ?? []
            appState.liveRooms = list.map(LiveRoomItem.from).filter {
                $0.hostUserId.isEmpty || !appState.blockedUserIds.contains($0.hostUserId)
            }
            loadError = nil
        } catch {
            if appState.liveRooms.isEmpty {
                loadError = error.localizedDescription
            }
        }
    }
    static func burstDurationNanoseconds(for tier: String, reduceEffects: Bool) -> UInt64 {
        if reduceEffects { return 1_400_000_000 }
        switch tier.lowercased() {
        case "legendary": return 4_500_000_000
        case "large": return 3_500_000_000
        case "medium": return 2_600_000_000
        default: return 2_000_000_000
        }
    }
}

// MARK: - Setup Camera Preview Controller (Releases cleanly before WebRTC takes camera)
private final class LiveSetupCameraController: ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "kinnect.live.setup.camera")
    private var configured = false
    private var currentFront = true

    func start(front: Bool) {
        currentFront = front
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.configureSessionLocked(front: self.currentFront)
            }
            if self.configured && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func setCamera(front: Bool) {
        currentFront = front
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.configureSessionLocked(front: front)
                if self.configured && !self.session.isRunning {
                    self.session.startRunning()
                }
                return
            }
            self.session.beginConfiguration()
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            self.session.commitConfiguration()
        }
    }

    func stopAndRelease() {
        sessionQueue.sync {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.session.beginConfiguration()
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            self.session.commitConfiguration()
            self.configured = false
        }
    }

    private func configureSessionLocked(front: Bool) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        for input in session.inputs {
            session.removeInput(input)
        }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            configured = true
        }
        session.commitConfiguration()
    }
}

private struct LiveSetupCameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewHostView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewHostView {
        let v = PreviewHostView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

struct CreateLiveRoomSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var appState = AppState.shared
    var onStarted: (() -> Void)? = nil

    @State private var title = ""
    @State private var topic = "Giao lưu kết bạn"
    @State private var liveMode: String

    init(initialMode: String = "chat", onStarted: (() -> Void)? = nil) {
        self.onStarted = onStarted
        // Screen-broadcast game mode is unavailable on iOS; always normalize to camera chat mode.
        _liveMode = State(initialValue: "chat")
    }
    @State private var gameComments = true
    @State private var isStarting = false
    @State private var showPreviewEffects = false
    @State private var previewFrontCamera = true
    @State private var previewCameraAuthorized = false
    @StateObject private var setupCamera = LiveSetupCameraController()
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
    private let availableLiveModes: [(mode: String, title: String, systemImage: String)] = [
        ("chat", "Trò chuyện", "video.fill")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                cameraPreviewStage
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                darkControlDeck
            }
            .background(Color(hex: "#0A0A0C").ignoresSafeArea())
            .task {
                let camOk = await MediaPermissionHandler.shared.requestCameraAccess()
                previewCameraAuthorized = camOk
                previewFrontCamera = NativeWebRTCManager.shared.usingFrontCamera
                if camOk && !isStarting {
                    setupCamera.start(front: previewFrontCamera)
                }
            }
            .onDisappear {
                setupCamera.stopAndRelease()
            }
            .navigationTitle(L10n.tr("Bắt đầu phát Live"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.tr("Bắt đầu phát Live"))
                        .font(.headline)
                        .foregroundColor(.white)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.tr("Hủy"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private var cameraPreviewStage: some View {
        ZStack {
            if previewCameraAuthorized {
                LiveSetupCameraPreviewLayer(session: setupCamera.session)
                    .overlay(
                        LiveFilterColorOverlay(filterId: previewFilter)
                            .allowsHitTesting(false)
                    )
            } else {
                LinearGradient(
                    colors: [Color(hex: "#1A102E"), Color(hex: "#0A0A0C")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                    Text(L10n.tr("Cấp quyền camera để xem trước trực tiếp"))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Text("●  \(L10n.tr("Xem trước · Chưa phát sóng"))")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Color(hex: "#FDD663"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.58))
                                .overlay(Capsule().stroke(Color(hex: "#FDD663").opacity(0.32), lineWidth: 1))
                        )
                    Spacer()
                }
                .padding(.top, 14)

                Spacer()

                HStack(spacing: 8) {
                    Text(L10n.tr(previewFrontCamera ? "Camera trước" : "Camera sau"))
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.58)))
                    if previewFilter != "none" {
                        Text("\(L10n.tr("Bộ lọc:")) \(previewFilter)")
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(KinnectTheme.accent))
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#0F0D18"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var darkControlDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                "",
                text: $title,
                prompt: Text(L10n.tr("Tiêu đề buổi Live"))
                    .foregroundColor(.white.opacity(0.55))
            )
            .font(.subheadline)
            .foregroundColor(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#201E2B"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )

            TextField(
                "",
                text: $topic,
                prompt: Text(L10n.tr("Nhập chủ đề buổi Live"))
                    .foregroundColor(.white.opacity(0.55))
            )
            .font(.footnote)
            .foregroundColor(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "#201E2B"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 0), spacing: 6),
                    count: dynamicTypeSize.isAccessibilitySize ? 2 : 4
                ),
                spacing: 6
            ) {
                setupChipButton(
                    icon: previewMicEnabled ? "mic.fill" : "mic.slash.fill",
                    label: L10n.tr("Micro"),
                    active: previewMicEnabled,
                    activeColor: KinnectTheme.accentBright
                ) {
                    previewMicEnabled.toggle()
                }

                setupChipButton(
                    icon: "bubble.left.fill",
                    label: L10n.tr("Bình luận"),
                    active: gameComments,
                    activeColor: KinnectTheme.accentBright
                ) {
                    gameComments.toggle()
                }

                setupChipButton(
                    icon: "camera.rotate.fill",
                    label: L10n.tr("Lật cam"),
                    active: false,
                    activeColor: KinnectTheme.accentBright
                ) {
                    previewFrontCamera.toggle()
                    NativeWebRTCManager.shared.usingFrontCamera = previewFrontCamera
                    setupCamera.setCamera(front: previewFrontCamera)
                }

                setupChipButton(
                    icon: "wand.and.stars",
                    label: L10n.tr("Làm đẹp"),
                    active: previewBeautyOn,
                    activeColor: KinnectTheme.accentBright
                ) {
                    showPreviewEffects = true
                }
            }

            Button {
                Task { await startHostLive() }
            } label: {
                HStack(spacing: 8) {
                    if isStarting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.headline)
                    }
                    Text(isStarting ? L10n.tr("Đang khởi tạo phòng Live…") : L10n.tr("Bắt đầu phát Live"))
                        .font(.headline.weight(.bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(
                    Capsule()
                        .fill(KinnectTheme.liveRed)
                        .shadow(color: KinnectTheme.liveRed.opacity(0.35), radius: 12, y: 4)
                )
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
            .fill(Color(hex: "#141418"))
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func setupChipButton(
        icon: String,
        label: String,
        active: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
            }
            .foregroundColor(active ? .white : Color.white.opacity(0.75))
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(active ? activeColor.opacity(0.26) : Color(hex: "#201E2B"))
                    .overlay(
                        Capsule().stroke(active ? activeColor : Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func startHostLive() async {
        isStarting = true
        defer { isStarting = false }
        setupCamera.stopAndRelease()
        if appState.currentLiveRoom != nil {
            appState.leaveCurrentLiveRoom()
        }
        appState.isCreatingLiveRoom = true
        let manager = NativeWebRTCManager.shared
        manager.usingFrontCamera = previewFrontCamera
        manager.updateLiveEffects(LiveVideoSettings(
            filter: previewFilter, sticker: previewSticker, beauty: previewBeautyOn,
            smooth: previewSmooth, whiten: previewWhiten, slim: previewSlim, eyes: previewEyes,
            lips: previewLips, blemish: previewBlemish, blush: previewBlush))
        guard await manager.startLiveHostBroadcast() else {
            appState.isCreatingLiveRoom = false
            setupCamera.start(front: previewFrontCamera)
            appState.showToast(L10n.tr("Cần quyền camera và micro để bắt đầu Live."))
            return
        }
        manager.setMicrophoneMuted(!previewMicEnabled)

        let roomTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(L10n.tr("Phòng Live của")) \(appState.currentUser?.name ?? "Kinnect")"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard await NativeSocketClient.shared.ensureConnected() else {
            appState.isCreatingLiveRoom = false
            manager.stopLiveSession()
            appState.showToast(L10n.tr("Chưa kết nối được máy chủ Live. Vui lòng thử lại."))
            return
        }

        NativeSocketClient.shared.sendJSON([
            "type": "create",
            "title": roomTitle,
            "topic": topic,
            "liveMode": "chat",
            "gameTitle": "",
            "multiGuest": true,
            "liveModes": true,
            "comments": gameComments
        ])
        dismiss()
        onStarted?()
    }
}

struct LiveRoomFullScreenView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("kinnect_live_gift_reduce_fx") private var reduceGiftEffects = false
    @AppStorage("kinnect_live_gift_sound") private var giftSoundEnabled = true

    @State private var chatInput = ""
    @State private var giftCatalog: [LiveGiftCatalogItem] = LiveGiftCatalogItem.defaultCatalog
    @State private var giftPriceVersion: Int = 1
    @State private var showGiftSheet = false
    @State private var showEffectsSheet = false
    @State private var showEndLiveConfirm = false
    @State private var showViewersSheet = false
    @State private var showCoHostSheet = false
    @State private var showGiftLeaderboardSheet = false
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
    @State private var isPlaybackMuted: Bool = false
    @State private var isHostFollowed: Bool = false
    @State private var isFollowLoading: Bool = false
    @State private var liveLayout: String = "panel"
    @State private var lastSentGift: LiveGiftCatalogItem? = nil
    @State private var lastSentGiftQuantity: Int = 1
    @State private var activeGiftEffect: ActiveGiftEffect? = nil
    @State private var floatingReactions: [LiveFloatingReaction] = []
    @StateObject private var giftComboTracker = LiveGiftComboTracker()

    var body: some View {
        if let room = appState.currentLiveRoom {
            ZStack {
                KinnectTheme.background.ignoresSafeArea()

                // Video Canvas
                if appState.isCurrentLiveHost, let localTrack = webrtc.liveLocalVideoTrack, !webrtc.isCameraOff {
                    WebRTCVideoRendererView(track: localTrack, mirror: webrtc.usingFrontCamera)
                        .ignoresSafeArea()
                } else if appState.isCurrentLiveHost && webrtc.isCameraOff {
                    VStack(spacing: 12) {
                        KinnectAvatarView(
                            name: room.hostName,
                            avatarURL: room.hostAvatarUrl,
                            colorHex: room.hostAvatarColor,
                            size: 92
                        )
                        Text(L10n.tr("Camera đang tắt"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                } else if let remoteTrack = webrtc.liveRemoteVideoTrack {
                    WebRTCVideoRendererView(track: remoteTrack, mirror: false)
                        .ignoresSafeArea()
                } else {
                    #if DEBUG
                    if UIReviewFixture.isEnabled {
                        ShortClipPlayer(
                            path: UIReviewFixture.samplePlayableVideoURL()?.absoluteString ?? "",
                            active: true,
                            muted: true
                        )
                        .ignoresSafeArea()
                    } else {
                        VStack(spacing: 12) {
                            KinnectAvatarView(
                                name: room.hostName,
                                avatarURL: room.hostAvatarUrl,
                                colorHex: room.hostAvatarColor,
                                size: 92
                            )
                            Text(room.gamePaused ? L10n.tr("Chủ phòng đang tạm dừng màn hình game") : L10n.tr("Đang kết nối luồng video Live..."))
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .kinnectMultiline()
                        }
                    }
                    #else
                    VStack(spacing: 12) {
                        KinnectAvatarView(
                            name: room.hostName,
                            avatarURL: room.hostAvatarUrl,
                            colorHex: room.hostAvatarColor,
                            size: 92
                        )
                        Text(room.gamePaused ? L10n.tr("Chủ phòng đang tạm dừng màn hình game") : L10n.tr("Đang kết nối luồng video Live..."))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    #endif
                }

                // Subtle top & bottom gradient scrim so Host controls remain legible over bright video
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.clear,
                        Color.clear,
                        Color.black.opacity(0.75)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // Filters are baked into RTCVideoSource, not painted over the viewer UI.

                VStack(spacing: 6) {
                    // Row 1: Host pill + LIVE + Mode + Viewers + Report + Close
                    HStack(spacing: 6) {
                        HStack(spacing: 8) {
                            KinnectAvatarView(
                                name: room.hostName,
                                avatarURL: room.hostAvatarUrl,
                                colorHex: room.hostAvatarColor,
                                size: 34
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(room.hostName)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                HStack(spacing: 5) {
                                    Text("LIVE")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(KinnectTheme.liveRed))
                                    Text(room.liveMode == "game" ? "🎮 \(room.gameTitle)" : "💬 \(L10n.tr("Trò chuyện"))")
                                        .font(.caption2)
                                        .foregroundColor(Color(hex: "#E9D5FF"))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 4)

                        Button {
                            showViewersSheet = true
                        } label: {
                            Text("👁 \(room.viewerCount)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.45)))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Xem danh sách người xem"))

                        if !appState.isCurrentLiveHost {
                            Button {
                                appState.activeReportContext = UGCReportContext(
                                    targetType: "user",
                                    targetId: room.hostUserId.isEmpty ? room.id : room.hostUserId,
                                    targetUserId: room.hostUserId,
                                    targetTitle: room.title.isEmpty ? room.hostName : "\(room.hostName) — \(room.title)"
                                )
                            } label: {
                                Image(systemName: "flag.fill")
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Circle().fill(Color.black.opacity(0.45)))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.tr("Báo cáo phòng Live"))
                        }

                        Button {
                            if appState.isCurrentLiveHost {
                                showEndLiveConfirm = true
                            } else {
                                leaveLiveRoom()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Circle().fill(KinnectTheme.liveRed))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr(appState.isCurrentLiveHost ? "Kết thúc Live" : "Rời phòng Live"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    // Row 2: BXH Quà pill + Full Room Title + Host Game toggle
                    HStack(spacing: 8) {
                        Button {
                            showGiftLeaderboardSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(KinnectTheme.warning)
                                Text(L10n.tr("BXH Quà"))
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                                if !appState.liveGiftRanking.isEmpty {
                                    Text("\(appState.liveGiftRanking.count)")
                                        .font(.caption2.bold())
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel(L10n.tr("Bảng xếp hạng quà"))

                        if !room.title.isEmpty {
                            Text(room.title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .shadow(color: .black.opacity(0.75), radius: 3, y: 1)
                        }

                        Spacer(minLength: 4)

                        if !appState.isCurrentLiveHost && !room.hostUserId.isEmpty && room.hostUserId != appState.currentUser?.id {
                            Button {
                                guard !isFollowLoading else { return }
                                Task { await toggleFollowRoomHost(room.hostUserId) }
                            } label: {
                                Text(L10n.tr(isHostFollowed ? "Đang theo dõi" : "Theo dõi"))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(isHostFollowed ? Color.white.opacity(0.22) : KinnectTheme.accent))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .fixedSize(horizontal: true, vertical: false)
                        }

                        if appState.isCurrentLiveHost && room.liveMode == "game" {
                            Button {
                                let nextPaused = !room.gamePaused
                                NativeSocketClient.shared.sendJSON([
                                    "type": "live-game-state",
                                    "paused": nextPaused,
                                    "gameTitle": room.gameTitle
                                ])
                            } label: {
                                Text(L10n.tr(room.gamePaused ? "Tiếp tục Game" : "Tạm ẩn Game"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(KinnectTheme.warning))
                                    .foregroundColor(.black)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)

                    if let banner = appState.liveLastReactionBanner {
                        Text(banner)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                            .padding(.top, 2)
                    }

                    Spacer()

                    HStack {
                        Spacer()
                        LiveCoHostPiPStackView(isHostCanvas: appState.isCurrentLiveHost, layout: liveLayout)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)

                    if !appState.isCurrentLiveHost, let comboGift = lastSentGift {
                        HStack {
                            Spacer()
                            Button {
                                sendQuickComboGift(comboGift, quantity: lastSentGiftQuantity, room: room)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(comboGift.emoji)
                                        .font(.system(size: 16))
                                    Text(appState.liveGiftCombo > 0 ? "Combo x\(appState.liveGiftCombo)" : "Combo")
                                        .font(.caption.weight(.black))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x47 / 255.0)))
                                .shadow(color: Color(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x47 / 255.0).opacity(0.45), radius: 6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                    }

                    // Chat list + Floating Right Tool Rail (prevents horizontal crowding in bottom bar)
                    HStack(alignment: .bottom, spacing: 10) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                #if DEBUG
                                if appState.liveChatMessages.isEmpty && UIReviewFixture.isEnabled {
                                    liveFullScreenChatRow(name: "Linh Nhi", text: "Chào mừng mọi người đến với buổi tối cuối tuần!")
                                    liveFullScreenChatRow(name: "Trần Thanh Trúc", text: "Chúc buổi phát trực tiếp thật nhiều niềm vui nha ❤️")
                                    liveFullScreenChatRow(name: "Lê Hoàng Nam", text: "Cảm ơn cả nhà đã ghé xem!")
                                }
                                #endif
                                ForEach(appState.liveChatMessages.filter { !appState.blockedUserIds.contains($0.user.id) }.suffix(30)) { msg in
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
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            let hasPeerSender = !msg.user.id.isEmpty && msg.user.id != appState.currentUser?.id
                                            appState.activeReportContext = UGCReportContext(
                                                targetType: hasPeerSender ? "user" : "app",
                                                targetId: hasPeerSender ? msg.user.id : (appState.currentUser?.id ?? "live_comment"),
                                                targetUserId: hasPeerSender ? msg.user.id : nil,
                                                targetTitle: "\(L10n.tr("Bình luận Live của")) \(msg.user.name): \"\(String(msg.text.prefix(40)))\""
                                            )
                                        } label: {
                                            Label(L10n.tr("Báo cáo bình luận"), systemImage: "flag")
                                        }
                                    }
                                }
                            }
                        }
                        .clipped()
                        .frame(maxWidth: .infinity, maxHeight: 190, alignment: .leading)

                        // Vertical Right Tool Rail (1-tap access to Camera, Mic, Layout, Effects / Viewer Audio & Co-Host)
                        VStack(spacing: 10) {
                            if appState.isCurrentLiveHost {
                                liveRailButton(
                                    icon: "camera.rotate.fill",
                                    label: L10n.tr("Lật"),
                                    tint: .white,
                                    accessibility: L10n.tr("Lật camera")
                                ) {
                                    NativeWebRTCManager.shared.flipCamera()
                                }

                                liveRailButton(
                                    icon: webrtc.isCameraOff ? "video.slash.fill" : "video.fill",
                                    label: L10n.tr("Camera"),
                                    tint: webrtc.isCameraOff ? KinnectTheme.danger : .white,
                                    accessibility: L10n.tr(webrtc.isCameraOff ? "Bật camera" : "Tắt camera")
                                ) {
                                    NativeWebRTCManager.shared.toggleCamera()
                                }

                                liveRailButton(
                                    icon: hostMicMuted ? "mic.slash.fill" : "mic.fill",
                                    label: L10n.tr("Mic"),
                                    tint: hostMicMuted ? KinnectTheme.danger : .white,
                                    accessibility: L10n.tr(hostMicMuted ? "Bật micro" : "Tắt micro")
                                ) {
                                    hostMicMuted.toggle()
                                    NativeWebRTCManager.shared.setMicrophoneMuted(hostMicMuted)
                                }

                                liveRailButton(
                                    icon: liveLayout == "grid" ? "rectangle.grid.2x2.fill" : "rectangle.inset.bottomright.fill",
                                    label: L10n.tr(liveLayout == "grid" ? "Lưới" : "Bố cục"),
                                    tint: .white,
                                    accessibility: L10n.tr("Đổi bố cục khung hình")
                                ) {
                                    let nextLayout = (liveLayout == "grid") ? "panel" : "grid"
                                    liveLayout = nextLayout
                                    NativeSocketClient.shared.sendJSON(["type": "live-layout", "layout": nextLayout])
                                }

                                liveRailButton(
                                    icon: "sparkles",
                                    label: L10n.tr("Hiệu ứng"),
                                    tint: .white,
                                    accessibility: L10n.tr("Hiệu ứng Live")
                                ) {
                                    showEffectsSheet = true
                                }
                            } else {
                                liveRailButton(
                                    icon: isPlaybackMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                    label: L10n.tr("Âm thanh"),
                                    tint: isPlaybackMuted ? KinnectTheme.danger : .white,
                                    accessibility: L10n.tr(isPlaybackMuted ? "Bật âm thanh" : "Tắt tiếng")
                                ) {
                                    isPlaybackMuted.toggle()
                                    RTCAudioSession.sharedInstance().isAudioEnabled = !isPlaybackMuted
                                }

                                if !appState.isCurrentLivePublisher {
                                    liveRailButton(
                                        icon: appState.hasPendingLiveGuestRequest ? "person.crop.circle.badge.clock" : "person.badge.plus",
                                        label: L10n.tr(appState.hasPendingLiveGuestRequest ? "Đang chờ" : "Lên sóng"),
                                        tint: appState.hasPendingLiveGuestRequest ? KinnectTheme.warning : .white,
                                        accessibility: L10n.tr(appState.hasPendingLiveGuestRequest ? "Hủy yêu cầu lên sóng" : "Xin lên sóng")
                                    ) {
                                        if appState.hasPendingLiveGuestRequest {
                                            NativeSocketClient.shared.sendJSON(["type": "live-guest-cancel"])
                                        } else {
                                            NativeSocketClient.shared.sendJSON(["type": "live-guest-request", "mode": "video"])
                                        }
                                    }
                                }
                            }

                            liveRailButton(
                                icon: "square.and.arrow.up",
                                label: L10n.tr("Chia sẻ"),
                                tint: .white,
                                accessibility: L10n.tr("Chia sẻ")
                            ) {
                                let permalink = "https://app.kinnect.io.vn/share/live/\(room.id)"
                                UIPasteboard.general.string = permalink
                                appState.showToast("Đã sao chép liên kết phòng Live!")
                                let shareItems: [Any] = [URL(string: permalink) ?? permalink]
                                KinnectShareSheet.present(items: shareItems)
                            }
                        }
                    }
                    .padding(.horizontal, 12)

                    // Compact Bottom Chat Bar (TextField + at most 3 compact circular buttons so input always stays wide)
                    let commentsDisabledForViewer = !room.comments && !appState.isCurrentLiveHost
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            text: $chatInput,
                            prompt: Text(L10n.tr(commentsDisabledForViewer ? "Chủ phòng đã tắt bình luận" : "Bình luận phòng Live..."))
                                .foregroundColor(.white.opacity(0.75))
                        )
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .tint(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(commentsDisabledForViewer ? 0.08 : 0.14))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                    )
                            )
                            .disabled(commentsDisabledForViewer)

                        Button {
                            sendLiveChat()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(commentsDisabledForViewer ? KinnectTheme.surfaceElevated : KinnectTheme.accent)
                                    .frame(width: 38, height: 38)
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(commentsDisabledForViewer)
                        .accessibilityLabel(L10n.tr("Gửi bình luận"))

                        if appState.isCurrentLiveHost {
                            Button {
                                showCoHostSheet = true
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    Circle()
                                        .fill(Color.black.opacity(0.55))
                                        .frame(width: 38, height: 38)
                                        .overlay(
                                            Image(systemName: "person.2.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.white)
                                        )
                                    if !appState.liveGuestRequests.isEmpty {
                                        Text("\(appState.liveGuestRequests.count)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .background(Circle().fill(KinnectTheme.liveRed))
                                            .offset(x: 4, y: -4)
                                    }
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.tr("Quản lý khách mời lên sóng"))
                        }

                        Button {
                            triggerLiveReaction(symbol: "💜", kind: "heart", room: room.id)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                    .frame(width: 38, height: 38)
                                Text("💜")
                                    .font(.system(size: 17))
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !appState.isCurrentLiveHost {
                            Button {
                                showGiftSheet = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.55))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "gift.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(KinnectTheme.warning)
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
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
            .task {
                SocketEventBridge.installIfNeeded()
                await loadGiftCatalog()
            }
            .alert(L10n.tr("Kết thúc Live?"), isPresented: $showEndLiveConfirm) {
                Button(L10n.tr("Tiếp tục phát"), role: .cancel) {}
                Button(L10n.tr("Kết thúc Live"), role: .destructive) {
                    leaveLiveRoom()
                }
            } message: {
                Text(L10n.tr("Buổi phát trực tiếp sẽ dừng ngay với tất cả người xem."))
            }
            .sheet(isPresented: $showGiftSheet) {
                LiveGiftDrawerSheet(
                    roomId: room.id,
                    gifts: giftCatalog,
                    priceVersion: giftPriceVersion,
                    onGiftSent: { gift, qty in
                        lastSentGift = gift
                        lastSentGiftQuantity = qty
                    },
                    onCatalogUpdated: { items, version in
                        giftCatalog = items
                        giftPriceVersion = version
                    },
                    comboTracker: giftComboTracker
                )
            }
            .sheet(isPresented: $showViewersSheet) {
                LiveViewersSheet(roomId: room.id, viewerCount: room.viewerCount, isHost: appState.isCurrentLiveHost)
            }
            .sheet(isPresented: $showCoHostSheet) {
                LiveCoHostManagerSheet(roomId: room.id)
            }
            .sheet(isPresented: $showGiftLeaderboardSheet) {
                LiveGiftLeaderboardSheet(roomId: room.id, isHost: appState.isCurrentLiveHost)
            }
            .onReceive(NotificationCenter.default.publisher(for: .kinnectLiveReactionReceived)) { notif in
                guard let data = notif.userInfo as? [String: Any] else { return }
                handleIncomingFullScreenReaction(data)
            }
            .onReceive(NotificationCenter.default.publisher(for: SocketEventBridge.rawEventNotification)) { notif in
                guard let json = notif.userInfo as? [String: Any],
                      let type = json["type"] as? String else { return }
                let expectedRoom = appState.currentLiveRoom?.id ?? room.id
                if let evtRoom = json["room"] as? String, !evtRoom.isEmpty, evtRoom != expectedRoom {
                    return
                }
                if type == "live-stage", let layout = json["layout"] as? String {
                    liveLayout = (layout == "grid") ? "grid" : "panel"
                }
            }
            .onAppear {
                hostMicMuted = webrtc.isMicMuted
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

    private func liveRailButton(
        icon: String,
        label: String,
        tint: Color,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tint)
                }
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
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

    private func triggerGiftEffect(
        giftId: String,
        giftName: String,
        giftEmoji: String,
        qty: Int,
        comboCount: Int,
        senderName: String,
        recipientName: String = "",
        tier: String = "standard"
    ) {
        if giftSoundEnabled {
            AudioServicesPlaySystemSound(1104)
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        let effect = ActiveGiftEffect(
            giftId: giftId,
            giftName: giftName,
            giftEmoji: emojiOrDefault(giftEmoji, id: giftId),
            senderName: senderName,
            recipientName: recipientName,
            quantity: qty,
            comboCount: comboCount,
            tier: tier
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            activeGiftEffect = effect
        }
        let burstNanos = LiveStreamView.burstDurationNanoseconds(for: tier, reduceEffects: reduceGiftEffects)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: burstNanos)
            if activeGiftEffect?.id == effect.id {
                withAnimation(.easeOut(duration: 0.3)) {
                    activeGiftEffect = nil
                }
            }
        }
    }

    private func emojiOrDefault(_ emoji: String, id: String) -> String {
        emoji.isEmpty ? LiveGiftCatalogItem.defaultEmoji(for: id) : emoji
    }

    private func handleIncomingFullScreenReaction(_ data: [String: Any]) {
        let isGift = (data["experience"] as? Bool) ?? (data["isGift"] as? Bool) ?? (data["giftId"] != nil)
        if isGift {
            let giftId = (data["giftId"] as? String) ?? (data["kind"] as? String) ?? "rose"
            let giftName = (data["giftName"] as? String) ?? LiveGiftCatalogItem.defaultName(for: giftId)
            let emoji = LiveGiftCatalogItem.defaultEmoji(for: giftId)
            let senderName = (data["name"] as? String) ?? "Khán giả"
            let recipientName = (data["recipientName"] as? String) ?? ""
            let qty = (data["quantity"] as? Int) ?? (data["quantity"] as? NSNumber)?.intValue ?? 1
            let combo = (data["comboCount"] as? Int) ?? (data["comboCount"] as? NSNumber)?.intValue ?? 1
            let tier = (data["tier"] as? String) ?? "standard"
            triggerGiftEffect(
                giftId: giftId,
                giftName: giftName,
                giftEmoji: emoji,
                qty: qty,
                comboCount: combo,
                senderName: senderName,
                recipientName: recipientName,
                tier: tier
            )
            spawnFullScreenFloatingReaction(symbol: giftId)
        } else {
            let senderId = (data["senderId"] as? String) ?? ""
            if senderId != appState.currentUser?.id {
                spawnFullScreenFloatingReaction(symbol: "💜")
            }
        }
    }

    private func toggleFollowRoomHost(_ hostId: String) async {
        guard !hostId.isEmpty, !isFollowLoading else { return }
        isFollowLoading = true
        defer { isFollowLoading = false }
        let next = !isHostFollowed
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(hostId)/follow",
                method: next ? "POST" : "DELETE"
            )
            isHostFollowed = next
            appState.showToast(next ? "Đã theo dõi chủ phòng!" : "Đã bỏ theo dõi chủ phòng.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func sendQuickComboGift(_ gift: LiveGiftCatalogItem, quantity: Int, room: LiveRoomItem) {
        guard NativeSocketClient.shared.isConnected else {
            appState.showToast("Mất kết nối phòng Live.")
            return
        }
        let targetUserId = room.hostUserId
        let comboId = giftComboTracker.nextComboId(roomId: room.id, giftId: gift.id, targetUserId: targetUserId)
        let reqId = "gift_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var payload: [String: Any] = [
            "type": "live-reaction",
            "room": room.id,
            "kind": gift.id,
            "giftId": gift.id,
            "quantity": quantity,
            "comboId": comboId,
            "fundingSource": "gifted",
            "requestId": reqId,
            "priceVersion": giftPriceVersion
        ]
        if !targetUserId.isEmpty {
            payload["targetUserId"] = targetUserId
        }
        NativeSocketClient.shared.sendJSON(payload)
    }

    private func spawnFullScreenFloatingReaction(symbol: String) {
        let screenWidth = UIScreen.main.bounds.width
        let startX = screenWidth * CGFloat.random(in: 0.68...0.88)
        let startY = UIScreen.main.bounds.height * 0.78
        let r = LiveFloatingReaction(symbol: symbol, x: startX, y: startY)
        floatingReactions.append(r)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            floatingReactions.removeAll(where: { $0.id == r.id })
        }
    }

    #if DEBUG
    private func liveFullScreenChatRow(name: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(name):")
                .font(.caption.bold())
                .foregroundColor(KinnectTheme.accentBright)
            Text(text)
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
    #endif

    private func sendLiveChat() {
        if let room = appState.currentLiveRoom, !room.comments && !appState.isCurrentLiveHost {
            return
        }
        let clean = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        chatInput = ""
        #if DEBUG
        if UIReviewFixture.isEnabled {
            let localMsg = LiveChatMessage(
                id: UUID().uuidString,
                user: appState.currentUser ?? KinnectUser.from(["name": "Bạn"]),
                text: clean,
                createdAt: ""
            )
            appState.liveChatMessages.append(localMsg)
            return
        }
        #endif
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
            let items = (res["items"] as? [[String: Any]]) ?? (res["gifts"] as? [[String: Any]]) ?? []
            if !items.isEmpty {
                self.giftCatalog = items.map(LiveGiftCatalogItem.from)
            }
            self.giftPriceVersion = (res["version"] as? Int) ?? (res["priceVersion"] as? Int) ?? 1
        }
        if self.giftCatalog.isEmpty {
            self.giftCatalog = LiveGiftCatalogItem.defaultCatalog
        }
    }
}

final class LiveGiftComboTracker: ObservableObject {
    static let shared = LiveGiftComboTracker()
    private let lock = NSLock()
    private var activeComboId: String = ""
    private var activeComboKey: String = ""
    private var activeComboAt: Date = .distantPast

    func nextComboId(roomId: String, giftId: String, targetUserId: String) -> String {
        let comboKey = "\(roomId):\(giftId):\(targetUserId)"
        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        let comboId: String
        if comboKey == activeComboKey && now.timeIntervalSince(activeComboAt) < 4.5 && !activeComboId.isEmpty {
            comboId = activeComboId
        } else {
            comboId = "combo_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)
            activeComboKey = comboKey
            activeComboId = comboId
        }
        activeComboAt = now
        return comboId
    }

    func reset() {
        lock.lock()
        activeComboId = ""
        activeComboKey = ""
        activeComboAt = .distantPast
        lock.unlock()
    }
}

struct LiveGiftDrawerSheet: View {
    let roomId: String
    let gifts: [LiveGiftCatalogItem]
    let priceVersion: Int
    var onGiftSent: ((LiveGiftCatalogItem, Int) -> Void)? = nil
    var onCatalogUpdated: (([LiveGiftCatalogItem], Int) -> Void)? = nil
    @ObservedObject var comboTracker: LiveGiftComboTracker = .shared
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @AppStorage("kinnect_live_gift_sound") private var giftSoundEnabled = true
    @AppStorage("kinnect_live_gift_reduce_fx") private var reduceGiftEffects = false
    @State private var loadedGifts: [LiveGiftCatalogItem] = []
    @State private var currentPriceVersion: Int? = nil
    @State private var coinBalance: Int? = nil
    @State private var giftInventoryCounts: [String: Int] = [:]
    @State private var selectedQuantity: Int = 1
    @State private var selectedGiftId: String = ""
    @State private var selectedTargetUserId: String = ""
    @State private var pendingGift: LiveGiftCatalogItem?
    @State private var pendingRequestId: String?
    @State private var pendingQuantity = 1
    @State private var confirmGift: LiveGiftCatalogItem?
    @State private var giftError: String?

    private let quantities = [1, 5, 10, 99]

    private var activeGifts: [LiveGiftCatalogItem] {
        loadedGifts.isEmpty ? gifts : loadedGifts
    }

    private var selectedGift: LiveGiftCatalogItem? {
        if !selectedGiftId.isEmpty, let match = activeGifts.first(where: { $0.id == selectedGiftId }) {
            return match
        }
        return activeGifts.first
    }

    private var activePriceVersion: Int {
        currentPriceVersion ?? priceVersion
    }

    private var recipientOptions: [(userId: String, name: String)] {
        let meId = appState.currentUser?.id ?? ""
        var seen = Set<String>()
        var options: [(userId: String, name: String)] = []
        if let room = appState.currentLiveRoom ?? appState.liveRooms.first(where: { $0.id == roomId }),
           !room.hostUserId.isEmpty, room.hostUserId != meId {
            seen.insert(room.hostUserId)
            options.append((room.hostUserId, room.hostName))
        }
        for p in appState.liveStageParticipants {
            guard let uid = p["userId"] as? String, !uid.isEmpty, uid != meId, !seen.contains(uid) else { continue }
            seen.insert(uid)
            let name = (p["name"] as? String) ?? "Khách mời"
            options.append((uid, name))
        }
        return options
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Balance + Sound / Reduce-Effects Controls
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        KinnectIcon(glyph: .coin, size: 14, selected: true, tint: KinnectTheme.warning)
                        let displayBalance = coinBalance ?? appState.currentUser?.giftedCoins ?? appState.currentUser?.trialCoins ?? 0
                        Text("\(L10n.tr("Xu tặng")) · \(displayBalance.formattedWithSeparator())")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))

                    Spacer(minLength: 4)

                    Button {
                        giftSoundEnabled.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: giftSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.caption2)
                            Text(L10n.tr("Âm thanh"))
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(giftSoundEnabled ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        reduceGiftEffects.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: reduceGiftEffects ? "sparkles.slash" : "sparkles")
                                .font(.caption2)
                            Text(L10n.tr("Giảm hiệu ứng"))
                                .font(.caption2.bold())
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(reduceGiftEffects ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if recipientOptions.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Người nhận:")
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            ForEach(recipientOptions, id: \.userId) { target in
                                let chosen = (selectedTargetUserId.isEmpty ? recipientOptions.first?.userId : selectedTargetUserId) == target.userId
                                Button {
                                    selectedTargetUserId = target.userId
                                } label: {
                                    Text(target.name)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .background(Capsule().fill(chosen ? KinnectTheme.accent : KinnectTheme.surfaceElevated))
                                        .foregroundColor(chosen ? .white : KinnectTheme.textSecondary)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    }
                    .clipped()
                    .disabled(pendingRequestId != nil)
                }

                // Quantity / Combo Multiplier Pills matching Android & Web
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text(L10n.tr("Số lượng:"))
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)

                        ForEach(quantities, id: \.self) { qty in
                            Button {
                                selectedQuantity = qty
                            } label: {
                                Text("x\(qty)")
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(
                                        Capsule().fill(selectedQuantity == qty ? KinnectTheme.accent : KinnectTheme.surfaceElevated)
                                    )
                                    .foregroundColor(selectedQuantity == qty ? .white : KinnectTheme.textSecondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
                .clipped()
                .disabled(pendingRequestId != nil)
                if let giftError {
                    Text(giftError)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.danger)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }

                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10, alignment: .top),
                            GridItem(.flexible(), spacing: 10, alignment: .top),
                            GridItem(.flexible(), spacing: 10, alignment: .top)
                        ],
                        spacing: 10
                    ) {
                        ForEach(activeGifts) { gift in
                            let isChosen = selectedGift?.id == gift.id
                            Button {
                                selectedGiftId = gift.id
                                giftError = nil
                            } label: {
                                VStack(spacing: 6) {
                                    giftIconView(gift)
                                    Text(gift.label)
                                        .font(.caption.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    let invCount = giftInventoryCounts[gift.id] ?? 0
                                    if invCount > 0 {
                                        Text("\(L10n.tr("Trong kho")) · \(invCount)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)))
                                    } else {
                                        HStack(spacing: 3) {
                                            KinnectIcon(glyph: .coin, size: 12, selected: true, tint: KinnectTheme.warning)
                                            Text("\((gift.coins * selectedQuantity).formattedWithSeparator()) \(L10n.tr("xu"))")
                                                .font(.caption2.bold())
                                                .foregroundColor(KinnectTheme.textPrimary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.85)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 112, alignment: .top)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isChosen ? KinnectTheme.accentBright.opacity(0.16) : KinnectTheme.surfaceElevated)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(
                                                    isChosen ? KinnectTheme.accentBright : Color.white.opacity(0.08),
                                                    lineWidth: isChosen ? 2 : 1
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .clipped()
                .disabled(pendingRequestId != nil)

                giftDrawerFooter
            }
            .background(KinnectTheme.background)
            .navigationTitle("Tặng quà phòng Live")
            .alert(
                "Xác nhận tặng quà?",
                isPresented: Binding(
                    get: { confirmGift != nil },
                    set: { if !$0 { confirmGift = nil } }
                ),
                presenting: confirmGift
            ) { gift in
                Button("Hủy", role: .cancel) { confirmGift = nil }
                Button("Tặng quà") {
                    confirmGift = nil
                    sendGift(gift)
                }
            } message: { gift in
                Text("\(gift.label) · \(gift.coins * selectedQuantity) xu")
            }
            .task {
                await refreshGiftCatalog()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kinnectLiveGiftResult"))) { event in
                guard let data = event.userInfo else { return }
                let eventType = data["type"] as? String
                if let catalogDict = data["catalog"] as? [String: Any] {
                    applyCatalogPayload(catalogDict)
                }
                if let bal = (data["balance"] as? Int) ?? (data["balance"] as? NSNumber)?.intValue {
                    coinBalance = bal
                }
                guard let pendingRequestId else { return }
                if eventType == "live-gift-receipt",
                   data["requestId"] as? String == pendingRequestId {
                    if let gift = pendingGift {
                        UserDefaults.standard.removeObject(forKey: giftRequestKey(gift.id, quantity: pendingQuantity))
                        onGiftSent?(gift, pendingQuantity)
                    }
                    self.pendingRequestId = nil
                    dismiss()
                } else if eventType == "live-gift-error" || eventType == "live-mode-error" {
                    giftError = data["message"] as? String ?? "Chưa gửi được quà."
                    self.pendingRequestId = nil
                    if eventType == "live-gift-error" && data["catalog"] == nil {
                        Task { await refreshGiftCatalog() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.tr("Đóng"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(KinnectTheme.surfaceElevated))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.medium, .fraction(0.85)])
        .presentationDragIndicator(.visible)
    }

    private var giftDrawerFooter: some View {
        VStack(spacing: 8) {
            Divider().background(KinnectTheme.borderSoft)

            Text(L10n.tr("Quà từ xu tặng không tạo tiền rút"))
                .font(.caption2)
                .foregroundColor(KinnectTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let gift = selectedGift {
                let invCount = giftInventoryCounts[gift.id] ?? 0
                let totalCoins = gift.coins * selectedQuantity
                let useInventory = invCount >= selectedQuantity
                Button {
                    if !useInventory && totalCoins >= 1000 {
                        confirmGift = gift
                    } else {
                        sendGift(gift)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if pendingRequestId != nil {
                            ProgressView().tint(.white)
                        } else {
                            KinnectIcon(glyph: .gift, size: 18, selected: true, tint: .white)
                        }
                        Text(
                            useInventory
                                ? "\(L10n.tr("Tặng từ kho")) · x\(selectedQuantity)"
                                : "\(L10n.tr("Tặng")) · \(totalCoins.formattedWithSeparator()) \(L10n.tr("xu"))"
                        )
                        .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                }
                .buttonStyle(.plain)
                .disabled(pendingRequestId != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .background(KinnectTheme.background)
    }

    private func giftAssetName(for id: String) -> String {
        return (id == "car") ? "sports_car" : id
    }

    @ViewBuilder
    private func giftIconView(_ gift: LiveGiftCatalogItem) -> some View {
        let key = giftAssetName(for: gift.id)
        if gift.id == "aurora" {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#0D9488"), Color(hex: "#38BDF8"), Color(hex: "#8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
        } else if let img = UIImage(named: "kg20261109_gift_\(key)")
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
                .font(.system(size: 36))
                .frame(width: 44, height: 44)
        }
    }

    private func giftRequestKey(_ giftId: String, quantity: Int) -> String {
        "kinnect-gift-request:" + ServerConfig.currentOrigin + ":"
            + (AppState.shared.currentUser?.id ?? "") + ":" + roomId + ":" + giftId + ":" + String(quantity)
    }

    private func sendGift(_ gift: LiveGiftCatalogItem) {
        guard pendingRequestId == nil else { return }
        guard NativeSocketClient.shared.isConnected else {
            giftError = "Mất kết nối phòng Live. Hãy kết nối lại trước khi tặng quà."
            return
        }
        let invCount = giftInventoryCounts[gift.id] ?? 0
        if invCount < selectedQuantity, let currentBal = coinBalance ?? appState.currentUser?.giftedCoins ?? appState.currentUser?.trialCoins {
            let totalCost = gift.coins * selectedQuantity
            if currentBal < totalCost {
                giftError = "Chưa đủ xu."
                return
            }
        }
        let key = giftRequestKey(gift.id, quantity: selectedQuantity)
        let reqId = UserDefaults.standard.string(forKey: key)
            ?? "gift_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(reqId, forKey: key)
        pendingGift = gift
        pendingRequestId = reqId
        pendingQuantity = selectedQuantity
        giftError = nil
        let resolvedTarget = selectedTargetUserId.isEmpty
            ? (recipientOptions.first?.userId ?? appState.currentLiveRoom?.hostUserId ?? "")
            : selectedTargetUserId
        let comboId = comboTracker.nextComboId(roomId: roomId, giftId: gift.id, targetUserId: resolvedTarget)

        var payload: [String: Any] = [
            "type": "live-reaction",
            "room": roomId,
            "kind": gift.id,
            "giftId": gift.id,
            "quantity": selectedQuantity,
            "comboId": comboId,
            "fundingSource": "gifted",
            "requestId": reqId,
            "priceVersion": activePriceVersion
        ]
        if !resolvedTarget.isEmpty {
            payload["targetUserId"] = resolvedTarget
        }
        NativeSocketClient.shared.sendJSON(payload)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            if pendingRequestId == reqId {
                giftError = "Chưa nhận được xác nhận. Kiểm tra số dư và lịch sử quà trước khi gửi lại."
                pendingRequestId = nil
                // Preserve idempotency key in UserDefaults so a retry reuses the same requestId.
            }
        }
    }

    @MainActor
    private func applyCatalogPayload(_ payload: [String: Any]) {
        let items = (payload["items"] as? [[String: Any]]) ?? (payload["gifts"] as? [[String: Any]]) ?? []
        let parsed = items.map(LiveGiftCatalogItem.from)
        let version = (payload["version"] as? Int)
            ?? (payload["priceVersion"] as? Int)
            ?? (payload["version"] as? NSNumber)?.intValue
            ?? (payload["priceVersion"] as? NSNumber)?.intValue
        if !parsed.isEmpty {
            loadedGifts = parsed
        }
        if let version, version > 0 {
            currentPriceVersion = version
        }
        if let bal = (payload["balance"] as? Int) ?? (payload["balance"] as? NSNumber)?.intValue {
            coinBalance = bal
        }
        if let inv = payload["inventory"] as? [[String: Any]] {
            var counts: [String: Int] = [:]
            for item in inv {
                guard let gid = item["giftId"] as? String, !gid.isEmpty else { continue }
                let qty = (item["quantity"] as? Int) ?? (item["quantity"] as? NSNumber)?.intValue ?? 0
                if qty > 0 {
                    counts[gid, default: 0] += qty
                }
            }
            giftInventoryCounts = counts
        }
        let syncedGifts = loadedGifts.isEmpty ? gifts : loadedGifts
        let syncedVersion = currentPriceVersion ?? priceVersion
        if !syncedGifts.isEmpty {
            onCatalogUpdated?(syncedGifts, syncedVersion)
        }
    }

    @MainActor
    private func refreshGiftCatalog() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/gifts") {
            applyCatalogPayload(res)
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

// MARK: - Multi-Guest Co-Host / Guest PiP Tiles
private struct LiveCoHostPiPStackView: View {
    let isHostCanvas: Bool
    var layout: String = "panel"
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var webrtc = NativeWebRTCManager.shared

    private struct GuestTileItem: Identifiable {
        let id: String
        let name: String
        let track: RTCVideoTrack
        let mirror: Bool
    }

    private var tiles: [GuestTileItem] {
        var result: [GuestTileItem] = []
        let participantNames: [String: String] = Dictionary(
            appState.liveStageParticipants.compactMap { p -> (String, String)? in
                guard let id = p["id"] as? String, !id.isEmpty else { return nil }
                return (id, (p["name"] as? String) ?? "Khách mời")
            },
            uniquingKeysWith: { first, _ in first }
        )
        let orderedIds = appState.liveStageParticipants.compactMap { $0["id"] as? String }
            + webrtc.liveRemoteVideoTracks.keys.sorted()
        var visited = Set<String>()
        for peerId in orderedIds {
            guard !visited.contains(peerId) else { continue }
            visited.insert(peerId)
            if !isHostCanvas && peerId == webrtc.livePrimaryRemotePeerId {
                continue
            }
            if let track = webrtc.liveRemoteVideoTracks[peerId] {
                let label = participantNames[peerId] ?? "Khách mời"
                result.append(GuestTileItem(id: peerId, name: label, track: track, mirror: false))
            }
        }
        if !isHostCanvas, let localGuestTrack = webrtc.liveLocalVideoTrack {
            result.append(GuestTileItem(
                id: "local_guest",
                name: appState.currentUser?.name ?? "Bạn",
                track: localGuestTrack,
                mirror: webrtc.usingFrontCamera
            ))
        }
        return result
    }

    var body: some View {
        let items = tiles
        if !items.isEmpty {
            if layout == "grid" {
                LazyVGrid(columns: [GridItem(.fixed(96), spacing: 8), GridItem(.fixed(96), spacing: 8)], spacing: 8) {
                    ForEach(items) { tile in
                        tileView(tile, width: 96, height: 120)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(items) { tile in
                        tileView(tile, width: 92, height: 128)
                    }
                }
            }
        }
    }

    private func tileView(_ tile: GuestTileItem, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            WebRTCVideoRendererView(track: tile.track, mirror: tile.mirror)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 6, y: 3)

            Text(tile.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(5)
        }
    }
}

// MARK: - Active Gift Effect Model
struct ActiveGiftEffect: Identifiable {
    let id = UUID()
    let giftId: String
    let giftName: String
    let giftEmoji: String
    let senderName: String
    var recipientName: String = ""
    let quantity: Int
    var comboCount: Int = 1
    var tier: String = "standard"
}

// MARK: - Live Gift Burst Showcase View (Big 3D Animation Overlay)
struct LiveGiftBurstShowcaseView: View {
    let effect: ActiveGiftEffect
    @AppStorage("kinnect_live_gift_reduce_fx") private var reduceGiftEffects = false
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
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(effect.recipientName.isEmpty
                             ? "đã gửi tặng \(effect.giftName)"
                             : "tặng \(effect.giftName) cho \(effect.recipientName)")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.warning)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(effect.comboCount > 1 ? "Combo x\(effect.comboCount)" : "x\(effect.quantity)")
                        .font(.subheadline.bold())
                        .foregroundStyle(KinnectTheme.primaryGradient)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: 340)
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
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundColor(KinnectTheme.warning)
                    if effect.comboCount > 1 {
                        Text("COMBO x\(effect.comboCount)")
                            .font(.caption.weight(.black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x47 / 255.0)))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: .black.opacity(0.8), radius: 4, y: 2)

                Spacer()
            }
            .padding(.top, 40)
        }
        .onAppear {
            if reduceGiftEffects {
                bannerOffset = 0
                scale = 0.95
                return
            }
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
                KinnectSegmentedBar(
                    selection: $selectedTab,
                    options: [
                        (0, L10n.tr("Làm đẹp")),
                        (1, L10n.tr("Hiệu ứng")),
                        (2, L10n.tr("Màu"))
                    ],
                    accessibilityLabel: L10n.tr("Chế độ")
                )
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
            .navigationTitle(L10n.tr("Hiệu ứng Live"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.tr("Xong"))
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Capsule().fill(KinnectTheme.surfaceElevated))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                .clipped()

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
                    Text(L10n.tr("Đặt lại"))
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
        .clipped()
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
                                .foregroundColor(activeSticker == s.id ? KinnectTheme.accentBright : KinnectTheme.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .clipped()
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
                                        .foregroundColor(KinnectTheme.textPrimary)
                                } else {
                                    Circle()
                                        .fill(f.color)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            Text(f.name)
                                .font(.caption2)
                                .foregroundColor(activeFilter == f.id ? KinnectTheme.accentBright : KinnectTheme.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .clipped()
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
                    .foregroundColor(KinnectTheme.textPrimary)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func beautySliderRow(label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.accentBright)
            }
            Slider(value: value, in: 0...1)
                .tint(KinnectTheme.accentBright)
                .frame(minHeight: 44)
        }
    }
}

// MARK: - Live Viewer List Sheet
private struct LiveViewersSheet: View {
    let roomId: String
    let viewerCount: Int
    let isHost: Bool
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var viewers: [KinnectUser] = []
    @State private var guestCandidates: [[String: Any]] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if isLoading && viewers.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.tr("Đang tải danh sách người xem…"))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                } else if viewers.isEmpty {
                    Text(L10n.tr("Chưa có người xem nào trong phòng."))
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                } else {
                    ForEach(viewers) { viewer in
                        HStack(spacing: 12) {
                            KinnectAvatarView(
                                name: viewer.name,
                                avatarURL: viewer.avatarUrl,
                                colorHex: viewer.avatarColor,
                                size: 40
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewer.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(KinnectTheme.textPrimary)
                                if !viewer.handle.isEmpty {
                                    Text("@\(viewer.handle)")
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                            }
                            Spacer()
                            if isHost,
                               let candidate = guestCandidates.first(where: { ($0["userId"] as? String) == viewer.id }),
                               let peerId = candidate["id"] as? String,
                               (candidate["onStage"] as? Bool) != true {
                                Button {
                                    NativeSocketClient.shared.sendJSON([
                                        "type": "live-guest-invite",
                                        "to": peerId
                                    ])
                                    AppState.shared.showToast(String(format: L10n.tr("Đã gửi lời mời tới %@."), viewer.name))
                                } label: {
                                    Text(L10n.tr("Mời lên sóng"))
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(KinnectTheme.accent))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle(String(format: L10n.tr("Người xem (%d)"), max(viewerCount, viewers.count)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
            .onAppear {
                SocketEventBridge.installIfNeeded()
                NativeSocketClient.shared.sendJSON(["type": "viewers"])
                if isHost {
                    NativeSocketClient.shared.sendJSON(["type": "live-guest-list"])
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: SocketEventBridge.rawEventNotification)) { notif in
                guard let json = notif.userInfo as? [String: Any],
                      let type = json["type"] as? String else { return }
                if let evtRoom = json["room"] as? String, !evtRoom.isEmpty, evtRoom != roomId { return }
                if type == "viewers" {
                    let raw = json["users"] as? [[String: Any]] ?? []
                    viewers = raw.map(KinnectUser.from)
                    isLoading = false
                } else if type == "live-guest-list" {
                    guestCandidates = json["users"] as? [[String: Any]] ?? []
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Live Co-Host / Guest Manager Sheet
private struct LiveCoHostManagerSheet: View {
    let roomId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var candidates: [[String: Any]] = []

    private var destructiveInk: Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 0xFF / 255.0, green: 0x8D / 255.0, blue: 0xA1 / 255.0, opacity: 1.0)
            : Color(.sRGB, red: 0xA3 / 255.0, green: 0x1E / 255.0, blue: 0x43 / 255.0, opacity: 1.0)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(String(format: L10n.tr("Yêu cầu xin lên sóng (%d)"), appState.liveGuestRequests.count)) {
                    if appState.liveGuestRequests.isEmpty {
                        Text(L10n.tr("Chưa có yêu cầu nào."))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(Array(appState.liveGuestRequests.enumerated()), id: \.offset) { _, req in
                            let peerId = (req["id"] as? String) ?? ""
                            let name = (req["name"] as? String) ?? L10n.tr("Khán giả")
                            HStack(spacing: 8) {
                                Text(name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button(role: .destructive) {
                                    NativeSocketClient.shared.sendJSON(["type": "live-guest-decline", "to": peerId])
                                } label: {
                                    Text(L10n.tr("Từ chối"))
                                        .font(.caption.bold())
                                        .foregroundColor(destructiveInk)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    NativeSocketClient.shared.sendJSON(["type": "live-guest-approve", "to": peerId])
                                } label: {
                                    Text(L10n.tr("Duyệt"))
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let activeGuests = appState.liveStageParticipants.filter { ($0["role"] as? String) == "guest" }
                Section(String(format: L10n.tr("Khách đang trên sóng (%d/3)"), activeGuests.count)) {
                    if activeGuests.isEmpty {
                        Text(L10n.tr("Chưa có khách mời nào trên sóng."))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(Array(activeGuests.enumerated()), id: \.offset) { _, guest in
                            let peerId = (guest["id"] as? String) ?? ""
                            let name = (guest["name"] as? String) ?? L10n.tr("Khách mời")
                            HStack {
                                Text(name)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Button(role: .destructive) {
                                    NativeSocketClient.shared.sendJSON(["type": "live-guest-remove", "to": peerId])
                                } label: {
                                    Text(L10n.tr("Gỡ khỏi sóng"))
                                        .font(.caption.bold())
                                        .foregroundColor(destructiveInk)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                let invitable = candidates.filter { ($0["onStage"] as? Bool) != true }
                Section(L10n.tr("Mời khán giả lên sóng")) {
                    if invitable.isEmpty {
                        Text(L10n.tr("Chưa có khán giả khả dụng."))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(Array(invitable.enumerated()), id: \.offset) { _, user in
                            let peerId = (user["id"] as? String) ?? ""
                            let name = (user["name"] as? String) ?? L10n.tr("Khán giả")
                            HStack {
                                Text(name)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    NativeSocketClient.shared.sendJSON(["type": "live-guest-invite", "to": peerId])
                                    appState.showToast(String(format: L10n.tr("Đã gửi lời mời tới %@."), name))
                                } label: {
                                    Text(L10n.tr("Mời"))
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(KinnectTheme.accent))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Khách mời lên sóng"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
            .onAppear {
                SocketEventBridge.installIfNeeded()
                NativeSocketClient.shared.sendJSON(["type": "live-guest-list"])
            }
            .onReceive(NotificationCenter.default.publisher(for: SocketEventBridge.rawEventNotification)) { notif in
                guard let json = notif.userInfo as? [String: Any],
                      (json["type"] as? String) == "live-guest-list" else { return }
                if let evtRoom = json["room"] as? String, !evtRoom.isEmpty, evtRoom != roomId { return }
                candidates = json["users"] as? [[String: Any]] ?? []
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Live Gift Leaderboard & Goal Sheet
private struct LiveGiftLeaderboardSheet: View {
    let roomId: String
    let isHost: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var totalCoins: Int = 0
    @State private var totalGifts: Int = 0
    @State private var goalTitle: String = ""
    @State private var goalTargetCoins: Int = 0
    @State private var goalProgressCoins: Int = 0
    @State private var newGoalTitle: String = ""
    @State private var newGoalCoins: String = ""

    private var destructiveInk: Color {
        colorScheme == .dark
            ? Color(.sRGB, red: 0xFF / 255.0, green: 0x8D / 255.0, blue: 0xA1 / 255.0, opacity: 1.0)
            : Color(.sRGB, red: 0xA3 / 255.0, green: 0x1E / 255.0, blue: 0x43 / 255.0, opacity: 1.0)
    }

    var body: some View {
        NavigationStack {
            List {
                if goalTargetCoins > 0 {
                    Section(L10n.tr("Mục tiêu quà Live")) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(goalTitle.isEmpty ? L10n.tr("Mục tiêu quà Live") : goalTitle)
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(String(format: L10n.tr("%@ / %@ xu"), goalProgressCoins.formattedWithSeparator(), goalTargetCoins.formattedWithSeparator()))
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.warning)
                            }
                            ProgressView(value: min(1.0, Double(goalProgressCoins) / Double(max(1, goalTargetCoins))))
                                .tint(KinnectTheme.accentBright)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if isHost {
                    Section(L10n.tr("Cài đặt mục tiêu quà")) {
                        TextField(
                            "",
                            text: $newGoalTitle,
                            prompt: Text(L10n.tr("Tên mục tiêu (vd: Mục tiêu 500 xu)")).foregroundColor(KinnectTheme.inputPlaceholder)
                        )
                        TextField(
                            "",
                            text: $newGoalCoins,
                            prompt: Text(L10n.tr("Số xu mục tiêu (50 - 1.000.000)")).foregroundColor(KinnectTheme.inputPlaceholder)
                        )
                            .keyboardType(.numberPad)
                        HStack {
                            Button {
                                let target = Int(newGoalCoins.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                                guard target >= 50 else {
                                    appState.showToast(L10n.tr("Mục tiêu tối thiểu 50 xu."))
                                    return
                                }
                                NativeSocketClient.shared.sendJSON([
                                    "type": "live-gift-goal",
                                    "title": newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                    "targetCoins": target
                                ])
                            } label: {
                                Text(L10n.tr("Đặt mục tiêu"))
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if goalTargetCoins > 0 {
                                Spacer()
                                Button(role: .destructive) {
                                    NativeSocketClient.shared.sendJSON([
                                        "type": "live-gift-goal",
                                        "targetCoins": 0
                                    ])
                                } label: {
                                    Text(L10n.tr("Xóa mục tiêu"))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(destructiveInk)
                                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section(String(format: L10n.tr("Xếp hạng tặng quà (%d quà · %@ xu)"), totalGifts, totalCoins.formattedWithSeparator())) {
                    if appState.liveGiftRanking.isEmpty {
                        Text(L10n.tr("Chưa có lượt tặng quà nào trong phiên Live này."))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(Array(appState.liveGiftRanking.enumerated()), id: \.offset) { index, row in
                            let name = (row["name"] as? String) ?? L10n.tr("Khán giả")
                            let coins = (row["coins"] as? Int) ?? (row["coins"] as? NSNumber)?.intValue ?? 0
                            let giftsCount = (row["gifts"] as? Int) ?? (row["gifts"] as? NSNumber)?.intValue ?? 0
                            HStack(spacing: 10) {
                                Text("#\(index + 1)")
                                    .font(.caption.weight(.black))
                                    .foregroundColor(index == 0 ? KinnectTheme.warning : KinnectTheme.textSecondary)
                                    .frame(width: 28, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(String(format: L10n.tr("%d món quà"), giftsCount))
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                                Spacer()
                                Text(String(format: L10n.tr("%@ xu"), coins.formattedWithSeparator()))
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.warning)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle(L10n.tr("Bảng xếp hạng quà"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
            .onAppear {
                SocketEventBridge.installIfNeeded()
                NativeSocketClient.shared.sendJSON(["type": "live-gift-ranking"])
            }
            .onReceive(NotificationCenter.default.publisher(for: SocketEventBridge.rawEventNotification)) { notif in
                guard let json = notif.userInfo as? [String: Any],
                      let type = json["type"] as? String,
                      type == "live-gift-ranking" || type == "live-gift-goal" else { return }
                if let evtRoom = json["room"] as? String, !evtRoom.isEmpty, evtRoom != roomId { return }
                totalCoins = (json["totalCoins"] as? Int) ?? (json["totalCoins"] as? NSNumber)?.intValue ?? totalCoins
                totalGifts = (json["totalGifts"] as? Int) ?? (json["totalGifts"] as? NSNumber)?.intValue ?? totalGifts
                if let top = json["topSenders"] as? [[String: Any]] {
                    appState.liveGiftRanking = top
                }
                if let goal = json["goal"] as? [String: Any] {
                    goalTitle = (goal["title"] as? String) ?? ""
                    goalTargetCoins = (goal["targetCoins"] as? Int) ?? (goal["targetCoins"] as? NSNumber)?.intValue ?? 0
                    goalProgressCoins = (goal["progressCoins"] as? Int) ?? (goal["progressCoins"] as? NSNumber)?.intValue ?? 0
                } else if json["goal"] is NSNull {
                    goalTitle = ""
                    goalTargetCoins = 0
                    goalProgressCoins = 0
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
