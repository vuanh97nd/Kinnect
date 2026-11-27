import SwiftUI

/// Modern Fullscreen Call Overlay matching iOS FaceTime and Android NativeCalls.
/// Separated clean modes: Incoming Ringing, Active Video with Floating PiP & Bottom Capsule, and Active Audio.
struct CallOverlayView: View {
    private static let callAcceptGreen = Color(red: 0x18 / 255.0, green: 0x66 / 255.0, blue: 0x3E / 255.0)
    private static let callHangupRed = Color(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x47 / 255.0)

    @ObservedObject private var webrtc = NativeWebRTCManager.shared
    @State private var connectedAt: Date?
    @State private var showControls: Bool = true
    @State private var haloPulsing: Bool = false
    @State private var isMinimized: Bool = false
    @State private var pipOffset: CGSize = .zero
    @GestureState private var pipDragTranslation: CGSize = .zero
    @State private var isPipSwapped: Bool = false
    @State private var showQuickReplySheet: Bool = false

    var body: some View {
        if let call = webrtc.activeCall {
            ZStack {
                if isMinimized && !(call.isIncoming && call.state == .ringingIncoming) {
                    minimizedCallBanner(call)
                } else if call.isIncoming && call.state == .ringingIncoming {
                    incomingCallView(call)
                } else if call.mode == "video" {
                    videoCallView(call)
                } else {
                    audioCallView(call)
                }
            }
            .preferredColorScheme(.dark)
            .kinnectActionSheet(
                isPresented: $showQuickReplySheet,
                title: L10n.tr("Nhắn tin"),
                message: call.peerUser.name,
                items: quickReplyItems(for: call)
            )
            .onAppear {
                isMinimized = false
                pipOffset = .zero
                isPipSwapped = false
                updateTimer(state: call.state, callConnectedAt: call.connectedAt)
                haloPulsing = true
            }
            .onChange(of: call.state) { newState in
                updateTimer(state: newState, callConnectedAt: webrtc.activeCall?.connectedAt)
            }
            .onChange(of: call.connectedAt) { newDate in
                if let newDate { connectedAt = newDate }
            }
            .onChange(of: call.callId) { _ in
                isMinimized = false
                pipOffset = .zero
                isPipSwapped = false
                connectedAt = webrtc.activeCall?.connectedAt
                updateTimer(state: webrtc.activeCall?.state ?? call.state, callConnectedAt: webrtc.activeCall?.connectedAt)
            }
        }
    }

    // MARK: - Minimized Floating Call Banner
    private func minimizedCallBanner(_ call: ActiveCallSession) -> some View {
        VStack {
            HStack(spacing: 12) {
                KinnectAvatarView(
                    name: call.peerUser.name,
                    avatarURL: call.peerUser.avatarUrl,
                    colorHex: call.peerUser.avatarColor,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(call.peerUser.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if call.isReconnecting {
                        Text(L10n.tr("Đang kết nối lại…"))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.yellow)
                    } else if call.state == .connected, let start = call.connectedAt ?? connectedAt {
                        callDurationText(since: start)
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundColor(KinnectTheme.online)
                    } else {
                        Text(status(call))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            isMinimized = false
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Mở rộng cuộc gọi"))

                    Button {
                        webrtc.endOrRejectCurrentCall()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Self.callHangupRed)
                                .frame(width: 36, height: 36)
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Kết thúc cuộc gọi"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.14).opacity(0.95))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    isMinimized = false
                }
            }

            Spacer()
        }
    }

    // MARK: - Video Call View (FaceTime / Sleek Unobstructed Layout)
    private func videoCallView(_ call: ActiveCallSession) -> some View {
        ZStack {
            // Fullscreen Primary Video Track (Remote by default, or Local when swapped)
            if isPipSwapped, let localTrack = webrtc.localVideoTrack, !webrtc.isCameraOff {
                WebRTCVideoRendererView(track: localTrack, mirror: webrtc.usingFrontCamera)
                    .ignoresSafeArea()
            } else if !isPipSwapped, let track = webrtc.remoteVideoTrack {
                WebRTCVideoRendererView(track: track, mirror: false)
                    .ignoresSafeArea()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.13, blue: 0.18), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    ).ignoresSafeArea()

                    VStack(spacing: 16) {
                        KinnectAvatarView(
                            name: call.peerUser.name,
                            avatarURL: call.peerUser.avatarUrl,
                            colorHex: call.peerUser.avatarColor,
                            size: 104
                        )
                        Text(call.peerUser.name)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                        if call.isReconnecting {
                            Text(L10n.tr("Đang kết nối lại…"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.yellow)
                        } else if call.state == .connected, let start = call.connectedAt ?? connectedAt {
                            callDurationText(since: start)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundColor(.white.opacity(0.9))
                        } else {
                            Text(status(call))
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .ignoresSafeArea()
            }

            // Screen tap toggles overlay controls
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                }

            // Persistent Caller Name + Duration Pill when controls are hidden
            if !showControls {
                VStack {
                    VStack(spacing: 2) {
                        Text(call.peerUser.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        if call.isReconnecting {
                            Text(L10n.tr("Đang kết nối lại…"))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.yellow)
                        } else if call.state == .connected, let start = call.connectedAt ?? connectedAt {
                            callDurationText(since: start)
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundColor(.white.opacity(0.9))
                        } else {
                            Text(status(call))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .padding(.top, 12)

                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Floating Top Bar with Gradient
            if showControls {
                VStack {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                isMinimized = true
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Thu nhỏ cuộc gọi"))

                        Spacer()

                        if webrtc.remoteVideoTrack != nil || isPipSwapped {
                            VStack(spacing: 3) {
                                Text(call.peerUser.name)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 4)
                                if call.isReconnecting {
                                    Text(L10n.tr("Đang kết nối lại…"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.yellow)
                                        .shadow(color: .black.opacity(0.6), radius: 4)
                                } else if call.state == .connected, let start = call.connectedAt ?? connectedAt {
                                    callDurationText(since: start)
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundColor(.white.opacity(0.95))
                                        .shadow(color: .black.opacity(0.6), radius: 4)
                                } else {
                                    Text(status(call))
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                        .shadow(color: .black.opacity(0.6), radius: 4)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            webrtc.switchCamera()
                        } label: {
                            Image(systemName: "camera.rotate.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Đổi camera"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.7), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 140)
                        .ignoresSafeArea(edges: .top)
                    )

                    Spacer()
                }
                .transition(.opacity)
            }

            // Floating Local Video PiP in Top-Trailing Corner (Drag + Tap to Swap)
            VStack {
                HStack {
                    Spacer()
                    Group {
                        if isPipSwapped {
                            if let remoteTrack = webrtc.remoteVideoTrack {
                                WebRTCVideoRendererView(track: remoteTrack, mirror: false)
                                    .frame(width: 104, height: 148)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                                    )
                                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(red: 0.12, green: 0.13, blue: 0.18))
                                    KinnectAvatarView(
                                        name: call.peerUser.name,
                                        avatarURL: call.peerUser.avatarUrl,
                                        colorHex: call.peerUser.avatarColor,
                                        size: 48
                                    )
                                }
                                .frame(width: 104, height: 148)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                            }
                        } else if let track = webrtc.localVideoTrack, !webrtc.isCameraOff {
                            WebRTCVideoRendererView(track: track, mirror: webrtc.usingFrontCamera)
                                .frame(width: 104, height: 148)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                        } else if webrtc.isCameraOff {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(red: 0.12, green: 0.13, blue: 0.18))
                                VStack(spacing: 4) {
                                    Image(systemName: "video.slash.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white.opacity(0.7))
                                    Text(L10n.tr("Camera tắt"))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .frame(width: 104, height: 148)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                        }
                    }
                    .offset(
                        x: pipOffset.width + pipDragTranslation.width,
                        y: pipOffset.height + pipDragTranslation.height
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isPipSwapped.toggle()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .updating($pipDragTranslation) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                let maxX: CGFloat = 24
                                let minX: CGFloat = -(UIScreen.main.bounds.width - 140)
                                let minY: CGFloat = -20
                                let maxY: CGFloat = max(120, UIScreen.main.bounds.height - 280)
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    pipOffset.width = min(maxX, max(minX, pipOffset.width + value.translation.width))
                                    pipOffset.height = min(maxY, max(minY, pipOffset.height + value.translation.height))
                                }
                            }
                    )
                    .accessibilityLabel(L10n.tr("Khung hình xem trước"))
                    .accessibilityHint(L10n.tr("Chạm để đổi khung hình, kéo để di chuyển"))
                }
                .padding(.trailing, 16)
                .padding(.top, 68)

                Spacer()
            }

            // Floating Bottom Action Capsule
            if showControls {
                VStack {
                    Spacer()
                    HStack(spacing: 18) {
                        controlButton(
                            icon: webrtc.isCameraOff ? "video.slash.fill" : "video.fill",
                            title: L10n.tr("Camera"),
                            isActive: !webrtc.isCameraOff
                        ) {
                            webrtc.toggleCamera()
                        }

                        controlButton(
                            icon: webrtc.isMicMuted ? "mic.slash.fill" : "mic.fill",
                            title: L10n.tr("Mic"),
                            isActive: !webrtc.isMicMuted
                        ) {
                            webrtc.toggleMute()
                        }

                        controlButton(
                            icon: webrtc.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                            title: L10n.tr("Loa"),
                            isActive: webrtc.isSpeakerOn
                        ) {
                            webrtc.toggleSpeaker()
                        }

                        Button {
                            webrtc.endOrRejectCurrentCall()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Self.callHangupRed, in: Circle())
                                    .shadow(color: Self.callHangupRed.opacity(0.4), radius: 6)
                                Text(L10n.tr("Kết thúc"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .frame(minWidth: 56, minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Kết thúc cuộc gọi"))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.1, green: 0.1, blue: 0.14).opacity(0.85))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                    )
                    .padding(.bottom, 34)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Incoming Call Screen
    private func incomingCallView(_ call: ActiveCallSession) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.15), .black],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Label(L10n.tr(call.mode == "video" ? "Cuộc gọi video đến" : "Cuộc gọi thoại đến"),
                          systemImage: call.mode == "video" ? "video.fill" : "phone.fill")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.top, 40)
                }

                Spacer()

                // Centered Avatar with Animated Pulsing Halo
                ZStack {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 2)
                            .frame(width: CGFloat(130 + i * 36), height: CGFloat(130 + i * 36))
                            .scaleEffect(haloPulsing ? 1.08 : 0.95)
                            .opacity(haloPulsing ? 0.3 : 0.7)
                            .animation(
                                .easeInOut(duration: 1.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.3),
                                value: haloPulsing
                            )
                    }

                    KinnectAvatarView(
                        name: call.peerUser.name,
                        avatarURL: call.peerUser.avatarUrl,
                        colorHex: call.peerUser.avatarColor,
                        size: 112
                    )
                }

                VStack(spacing: 6) {
                    Text(call.peerUser.name)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                    Text(L10n.tr("Đang đổ chuông..."))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }

                Spacer()

                // Secondary quick actions: Reply with message / Answer audio-only
                HStack(spacing: 28) {
                    Button {
                        showQuickReplySheet = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            Text(L10n.tr("Nhắn tin"))
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.92))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minWidth: 72, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Nhắn tin"))

                    if call.mode == "video" {
                        Button {
                            webrtc.activeCall?.mode = "audio"
                            webrtc.isCameraOff = true
                            CallKitManager.shared.requestAnswerCall(callId: call.callId)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(L10n.tr("Chỉ âm thanh"))
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white.opacity(0.92))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minWidth: 72, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.tr("Chỉ âm thanh"))
                    }
                }
                .padding(.bottom, 4)

                // Action Buttons: Decline & Accept
                HStack(spacing: 60) {
                    Button {
                        webrtc.endOrRejectCurrentCall()
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Self.callHangupRed, in: Circle())
                                    .shadow(color: Self.callHangupRed.opacity(0.5), radius: 8)
                            }
                            .frame(width: 86, height: 86)
                            Text(L10n.tr("Từ chối"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Từ chối cuộc gọi"))

                    Button {
                        CallKitManager.shared.requestAnswerCall(callId: call.callId)
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(KinnectTheme.onlineDot.opacity(0.45), lineWidth: 4)
                                    .frame(width: 86, height: 86)
                                    .scaleEffect(haloPulsing ? 1.15 : 1.0)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: haloPulsing)

                                Image(systemName: call.mode == "video" ? "video.fill" : "phone.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Self.callAcceptGreen, in: Circle())
                                    .shadow(color: Self.callAcceptGreen.opacity(0.5), radius: 8)
                            }
                            .frame(width: 86, height: 86)
                            Text(L10n.tr("Trả lời"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Trả lời cuộc gọi"))
                }
                .padding(.bottom, 48)
            }
        }
    }

    private func quickReplyItems(for call: ActiveCallSession) -> [KinnectActionSheetItem] {
        let presets = [
            "Tôi sẽ gọi lại sau.",
            "Đang bận, nhắn tin nhé!",
            "Tôi đang trong cuộc họp."
        ]
        return presets.map { text in
            let localized = L10n.tr(text)
            return KinnectActionSheetItem(title: localized, glyph: .messages) {
                sendQuickReplyAndReject(text: localized, peerId: call.peerUser.id)
            }
        }
    }

    private func sendQuickReplyAndReject(text: String, peerId: String) {
        webrtc.endOrRejectCurrentCall()
        Task {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(peerId)/messages",
                method: "POST",
                body: [
                    "body": text,
                    "text": text,
                    "requestId": UUID().uuidString
                ]
            )
        }
    }

    // MARK: - Audio Call View
    private func audioCallView(_ call: ActiveCallSession) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.14, green: 0.16, blue: 0.22), .black],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            isMinimized = true
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Thu nhỏ cuộc gọi"))

                    Spacer()

                    Label(L10n.tr("Kinnect Audio"), systemImage: "phone.fill")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))

                    Spacer()

                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                // Avatar with Pulsing Rings
                ZStack {
                    ForEach(0..<2) { i in
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 2)
                            .frame(width: CGFloat(136 + i * 40), height: CGFloat(136 + i * 40))
                            .scaleEffect(haloPulsing ? 1.06 : 0.96)
                            .animation(
                                .easeInOut(duration: 1.8)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.4),
                                value: haloPulsing
                            )
                    }

                    KinnectAvatarView(
                        name: call.peerUser.name,
                        avatarURL: call.peerUser.avatarUrl,
                        colorHex: call.peerUser.avatarColor,
                        size: 112
                    )
                }

                VStack(spacing: 8) {
                    Text(call.peerUser.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    if call.isReconnecting {
                        Text(L10n.tr("Đang kết nối lại…"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.yellow)
                    } else if call.state == .connected, let start = call.connectedAt ?? connectedAt {
                        callDurationText(since: start)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        Text(status(call))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                Spacer()

                // Audio Call Controls Row: Speaker, Mic, End
                HStack(spacing: 28) {
                    controlButton(
                        icon: webrtc.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                        title: L10n.tr("Loa"),
                        isActive: webrtc.isSpeakerOn
                    ) {
                        webrtc.toggleSpeaker()
                    }

                    controlButton(
                        icon: webrtc.isMicMuted ? "mic.slash.fill" : "mic.fill",
                        title: L10n.tr("Mic"),
                        isActive: !webrtc.isMicMuted
                    ) {
                        webrtc.toggleMute()
                    }

                    Button {
                        webrtc.endOrRejectCurrentCall()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Self.callHangupRed, in: Circle())
                                .shadow(color: Self.callHangupRed.opacity(0.4), radius: 6)
                            Text(L10n.tr("Kết thúc"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .frame(minWidth: 60, minHeight: 60)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("Kết thúc cuộc gọi"))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(Color(red: 0.1, green: 0.1, blue: 0.14).opacity(0.85))
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                )
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private func callDurationText(since start: Date) -> some View {
        TimelineView(.periodic(from: start, by: 1.0)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(start)))
            let hours = elapsed / 3600
            let mins = (elapsed % 3600) / 60
            let secs = elapsed % 60
            if hours > 0 {
                Text(String(format: "%d:%02d:%02d", hours, mins, secs))
            } else {
                Text(String(format: "%02d:%02d", mins, secs))
            }
        }
    }

    private func updateTimer(state: ActiveCallSession.CallLifecycleState, callConnectedAt: Date?) {
        if state == .connected {
            if let callConnectedAt {
                connectedAt = callConnectedAt
            } else if connectedAt == nil {
                connectedAt = Date()
            }
        } else {
            connectedAt = nil
        }
    }

    private func status(_ call: ActiveCallSession) -> String {
        if call.isReconnecting { return L10n.tr("Đang kết nối lại…") }
        switch call.state {
        case .ringingIncoming: return L10n.tr(call.mode == "video" ? "Cuộc gọi video đến…" : "Cuộc gọi đến…")
        case .dialingOutgoing: return L10n.tr("Đang gọi…")
        case .connecting: return L10n.tr("Đang kết nối…")
        case .connected: return L10n.tr("Đã kết nối")
        case .ended: return L10n.tr("Đã kết thúc")
        }
    }

    private func controlButton(icon: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isActive ? .white : .white.opacity(0.4))
                    .frame(width: 54, height: 54)
                    .background(
                        Circle().fill(isActive ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                    )
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(minWidth: 54, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
