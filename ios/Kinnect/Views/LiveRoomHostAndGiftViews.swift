import AVFoundation
import AVKit
import SwiftUI
import UIKit

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
                                        .background(Capsule().fill(KinnectTheme.liveCrimson))
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
                                .foregroundColor(room.liveMode == "game" ? KinnectTheme.liveGameMint : KinnectTheme.accentBright)
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
                                    .background(Capsule().fill(KinnectTheme.liveAmberPause))
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
                            .background(Capsule().fill(KinnectTheme.liveEndRed))
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
                    .fill(RadialGradient(colors: [KinnectTheme.giftStarGlow.opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 24))
                Image(systemName: "star.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [KinnectTheme.giftStarGoldTop, KinnectTheme.giftStarGoldBottom], startPoint: .top, endPoint: .bottom))
                    .shadow(color: KinnectTheme.giftStarGlow.opacity(0.65), radius: 5)
            }
            .frame(width: 44, height: 44)
        } else if let vectorSpec = KinnectTheme.seasonalEffectPalette(for: gift.id) {
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
            if let overlayColor = KinnectTheme.liveFilterOverlay(for: filterId) {
                overlayColor
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
        ("none", "Gốc", KinnectTheme.liveFilterSwatch(for: "none")),
        ("clear", "Trong trẻo", KinnectTheme.liveFilterSwatch(for: "clear")),
        ("milk", "Sữa", KinnectTheme.liveFilterSwatch(for: "milk")),
        ("peach", "Hồng đào", KinnectTheme.liveFilterSwatch(for: "peach")),
        ("warm", "Ấm áp", KinnectTheme.liveFilterSwatch(for: "warm")),
        ("cool", "Mát lạnh", KinnectTheme.liveFilterSwatch(for: "cool")),
        ("film", "Phim cũ", KinnectTheme.liveFilterSwatch(for: "film")),
        ("mono", "Đen trắng", KinnectTheme.liveFilterSwatch(for: "mono")),
        ("noir", "Tương phản", KinnectTheme.liveFilterSwatch(for: "noir")),
        ("vivid", "Rực rỡ", KinnectTheme.liveFilterSwatch(for: "vivid")),
        ("sunset", "Hoàng hôn", KinnectTheme.liveFilterSwatch(for: "sunset")),
        ("candy", "Kẹo ngọt", KinnectTheme.liveFilterSwatch(for: "candy")),
        ("mint", "Bạc hà", KinnectTheme.liveFilterSwatch(for: "mint")),
        ("dream", "Mộng mơ", KinnectTheme.liveFilterSwatch(for: "dream")),
        ("retro", "Retro", KinnectTheme.liveFilterSwatch(for: "retro")),
        ("city", "Thành phố", KinnectTheme.liveFilterSwatch(for: "city")),
        ("cinema", "Cinema", KinnectTheme.liveFilterSwatch(for: "cinema")),
        ("rose", "Rose", KinnectTheme.liveFilterSwatch(for: "rose")),
        ("golden", "Golden", KinnectTheme.liveFilterSwatch(for: "golden")),
        ("ice", "Ice", KinnectTheme.liveFilterSwatch(for: "ice")),
        ("lavender", "Lavender", KinnectTheme.liveFilterSwatch(for: "lavender")),
        ("choco", "Choco", KinnectTheme.liveFilterSwatch(for: "choco")),
        ("polaroid", "Polaroid", KinnectTheme.liveFilterSwatch(for: "polaroid")),
        ("teal", "Teal", KinnectTheme.liveFilterSwatch(for: "teal"))
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
