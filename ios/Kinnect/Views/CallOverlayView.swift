import SwiftUI

/// Modern Fullscreen Call Overlay matching iOS FaceTime and Android NativeCalls.
/// Separated clean modes: Incoming Ringing, Active Video with Floating PiP & Bottom Capsule, and Active Audio.
struct CallOverlayView: View {
    @ObservedObject private var webrtc = NativeWebRTCManager.shared
    @State private var connectedAt: Date?
    @State private var showControls: Bool = true
    @State private var haloPulsing: Bool = false

    var body: some View {
        if let call = webrtc.activeCall {
            ZStack {
                if call.isIncoming && call.state == .ringingIncoming {
                    incomingCallView(call)
                } else if call.mode == "video" {
                    videoCallView(call)
                } else {
                    audioCallView(call)
                }
            }
            .preferredColorScheme(.dark)
            .statusBarHidden(false)
            .onAppear {
                updateTimer(call)
                haloPulsing = true
            }
            .onChange(of: call.state) { _ in updateTimer(call) }
            .onChange(of: call.callId) { _ in connectedAt = call.connectedAt; updateTimer(call) }
        }
    }

    // MARK: - Video Call View (FaceTime / Sleek Unobstructed Layout)
    private func videoCallView(_ call: ActiveCallSession) -> some View {
        ZStack {
            // Fullscreen Remote Video Track
            if let track = webrtc.remoteVideoTrack {
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
                            .font(KinnectTheme.scaled(26, weight: .bold))
                            .foregroundColor(.white)
                        if call.state == .connected {
                            callTimerLabel(call, prefix: "Đã kết nối • ")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.white.opacity(0.85))
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

            // Floating Top Bar with Gradient
            if showControls {
                VStack {
                    HStack(spacing: 12) {
                        Button {
                            webrtc.endOrRejectCurrentCall()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(KinnectTheme.scaled(18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Thu nhỏ cuộc gọi")

                        Spacer()

                        VStack(spacing: 3) {
                            Text(call.peerUser.name)
                                .font(KinnectTheme.scaled(18, weight: .bold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.6), radius: 4)
                            if call.state == .connected {
                                callTimerLabel(call)
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundColor(.white.opacity(0.92))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.black.opacity(0.38)))
                            } else {
                                Text(status(call))
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                    .shadow(color: .black.opacity(0.6), radius: 4)
                            }
                        }

                        Spacer()

                        Button {
                            webrtc.switchCamera()
                        } label: {
                            Image(systemName: "camera.rotate.fill")
                                .font(KinnectTheme.scaled(18, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Đổi camera")
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

            // Floating Local Video PiP in Top-Trailing Corner
            VStack {
                HStack {
                    Spacer()
                    if let track = webrtc.localVideoTrack, !webrtc.isCameraOff {
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
                                    .font(KinnectTheme.scaled(22))
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Camera tắt")
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
                            title: "Camera",
                            isActive: !webrtc.isCameraOff
                        ) {
                            webrtc.toggleCamera()
                        }

                        controlButton(
                            icon: webrtc.isMicMuted ? "mic.slash.fill" : "mic.fill",
                            title: "Mic",
                            isActive: !webrtc.isMicMuted
                        ) {
                            webrtc.toggleMute()
                        }

                        controlButton(
                            icon: webrtc.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                            title: "Loa",
                            isActive: webrtc.isSpeakerOn
                        ) {
                            webrtc.toggleSpeaker()
                        }

                        Button {
                            webrtc.endOrRejectCurrentCall()
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "phone.down.fill")
                                    .font(KinnectTheme.scaled(22, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Color.red, in: Circle())
                                    .shadow(color: .red.opacity(0.4), radius: 6)
                                Text("Kết thúc")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kết thúc cuộc gọi")
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
                colors: [Color(red: 0.14, green: 0.16, blue: 0.22), .black],
                startPoint: .top,
                endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Label(call.mode == "video" ? "Cuộc gọi video đến" : "Cuộc gọi thoại đến",
                          systemImage: call.mode == "video" ? "video.fill" : "phone.fill")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
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
                    Text("Kinnect")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // Action Buttons: Decline & Accept
                HStack(spacing: 60) {
                    Button {
                        webrtc.endOrRejectCurrentCall()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.down.fill")
                                .font(KinnectTheme.scaled(28, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 72, height: 72)
                                .background(Color.red, in: Circle())
                                .shadow(color: .red.opacity(0.5), radius: 8)
                            Text("Từ chối")
                                .font(KinnectTheme.scaled(13, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Từ chối cuộc gọi")

                    Button {
                        Task { await webrtc.acceptIncomingCall(callId: call.callId) }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color.green.opacity(0.4), lineWidth: 4)
                                    .frame(width: 86, height: 86)
                                    .scaleEffect(haloPulsing ? 1.15 : 1.0)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: haloPulsing)

                                Image(systemName: call.mode == "video" ? "video.fill" : "phone.fill")
                                    .font(KinnectTheme.scaled(28, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 72, height: 72)
                                    .background(Color.green, in: Circle())
                                    .shadow(color: .green.opacity(0.5), radius: 8)
                            }
                            Text("Trả lời")
                                .font(KinnectTheme.scaled(13, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Trả lời cuộc gọi")
                }
                .padding(.bottom, 48)
            }
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
                Label("Kinnect Audio", systemImage: "phone.fill")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.top, 40)

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
                        .font(KinnectTheme.scaled(28, weight: .bold))
                        .foregroundColor(.white)
                    if call.state == .connected {
                        VStack(spacing: 4) {
                            Text("Đã kết nối")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(hex: "#4ADE80"))
                            callTimerLabel(call)
                                .font(.title2.monospacedDigit().weight(.semibold))
                                .foregroundColor(.white.opacity(0.92))
                        }
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
                        title: "Loa",
                        isActive: webrtc.isSpeakerOn
                    ) {
                        webrtc.toggleSpeaker()
                    }

                    controlButton(
                        icon: webrtc.isMicMuted ? "mic.slash.fill" : "mic.fill",
                        title: "Mic",
                        isActive: !webrtc.isMicMuted
                    ) {
                        webrtc.toggleMute()
                    }

                    Button {
                        webrtc.endOrRejectCurrentCall()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "phone.down.fill")
                                .font(KinnectTheme.scaled(24, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.red, in: Circle())
                                .shadow(color: .red.opacity(0.4), radius: 6)
                            Text("Kết thúc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kết thúc cuộc gọi")
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
    private func callTimerLabel(_ call: ActiveCallSession, prefix: String = "") -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let start = call.connectedAt ?? connectedAt ?? context.date
            let totalSeconds = max(0, Int(context.date.timeIntervalSince(start)))
            let hours = totalSeconds / 3600
            let mins = (totalSeconds % 3600) / 60
            let secs = totalSeconds % 60
            let formatted = hours > 0
                ? String(format: "%d:%02d:%02d", hours, mins, secs)
                : String(format: "%02d:%02d", mins, secs)
            Text("\(prefix)\(formatted)")
        }
    }

    private func updateTimer(_ call: ActiveCallSession) {
        if call.state == .connected {
            if connectedAt == nil {
                connectedAt = call.connectedAt ?? Date()
            }
        } else {
            connectedAt = nil
        }
    }

    private func status(_ call: ActiveCallSession) -> String {
        switch call.state {
        case .ringingIncoming: return call.mode == "video" ? "Cuộc gọi video đến…" : "Cuộc gọi đến…"
        case .dialingOutgoing: return "Đang gọi…"
        case .connecting: return "Đang kết nối…"
        case .connected: return "Đã kết nối"
        case .ended: return "Đã kết thúc"
        }
    }

    private func controlButton(icon: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(KinnectTheme.scaled(22, weight: .medium))
                    .foregroundColor(isActive ? .white : .white.opacity(0.4))
                    .frame(width: 54, height: 54)
                    .background(
                        Circle().fill(isActive ? Color.white.opacity(0.25) : Color.white.opacity(0.1))
                    )
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
