import SwiftUI

struct CallOverlayView: View {
    @ObservedObject private var webrtc = NativeWebRTCManager.shared

    var body: some View {
        if let call = webrtc.activeCall {
            ZStack {
                KinnectTheme.background.ignoresSafeArea()

                // Remote Video Fullscreen when in video mode
                if call.mode == "video", let remoteTrack = webrtc.remoteVideoTrack {
                    WebRTCVideoRendererView(track: remoteTrack, mirror: false)
                        .ignoresSafeArea()
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.14, green: 0.08, blue: 0.28), KinnectTheme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }

                VStack(spacing: 20) {
                    // Caller / Peer info header
                    VStack(spacing: 10) {
                        KinnectAvatarView(
                            name: call.peerUser.name,
                            avatarURL: call.peerUser.avatarUrl,
                            colorHex: call.peerUser.avatarColor,
                            size: 88
                        )

                        Text(call.peerUser.name)
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .kinnectMultiline()

                        Text(statusLabel(for: call))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .padding(.top, 48)

                    Spacer()

                    // Local Video PiP
                    if call.mode == "video", let localTrack = webrtc.localVideoTrack, !webrtc.isCameraOff {
                        HStack {
                            Spacer()
                            WebRTCVideoRendererView(track: localTrack, mirror: webrtc.usingFrontCamera)
                                .frame(width: 118, height: 168)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(radius: 10)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Action Buttons
                    if call.isIncoming && call.state == .ringingIncoming {
                        HStack(spacing: 48) {
                            callActionButton(
                                systemIcon: "phone.down.fill",
                                glyph: nil,
                                label: "Từ chối",
                                color: KinnectTheme.danger
                            ) {
                                webrtc.endOrRejectCurrentCall(sendSocket: true)
                            }

                            callActionButton(
                                systemIcon: nil,
                                glyph: call.mode == "video" ? .videoCall : .phone,
                                label: "Trả lời",
                                color: KinnectTheme.online
                            ) {
                                Task { await webrtc.acceptIncomingCall(callId: call.callId) }
                            }
                        }
                        .padding(.bottom, 44)
                    } else {
                        HStack(spacing: 22) {
                            callControlCircle(
                                glyphWhenActive: .microphone,
                                slashedSystemIconWhenOff: "mic.slash.fill",
                                active: !webrtc.isMicMuted,
                                label: webrtc.isMicMuted ? "Bật mic" : "Tắt mic",
                                accessibilityStateValue: webrtc.isMicMuted ? "Đang tắt tiếng" : "Đang bật tiếng"
                            ) {
                                webrtc.toggleMute()
                            }

                            if call.mode == "video" {
                                callControlCircle(
                                    glyphWhenActive: .videoCall,
                                    slashedSystemIconWhenOff: "video.slash.fill",
                                    active: !webrtc.isCameraOff,
                                    label: "Camera",
                                    accessibilityStateValue: webrtc.isCameraOff ? "Đang tắt camera" : "Đang bật camera"
                                ) {
                                    webrtc.toggleCamera()
                                }

                                callControlCircle(
                                    glyphWhenActive: .refresh,
                                    slashedSystemIconWhenOff: "arrow.triangle.2.circlepath.camera.fill",
                                    active: true,
                                    label: "Đổi cam",
                                    accessibilityStateValue: webrtc.usingFrontCamera ? "Camera trước" : "Camera sau"
                                ) {
                                    webrtc.switchCamera()
                                }
                            }

                            callControlCircle(
                                glyphWhenActive: nil,
                                slashedSystemIconWhenOff: webrtc.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                                active: webrtc.isSpeakerOn,
                                label: "Loa ngoài",
                                accessibilityStateValue: webrtc.isSpeakerOn ? "Đang bật loa ngoài" : "Đang dùng loa trong"
                            ) {
                                webrtc.toggleSpeaker()
                            }

                            callActionButton(
                                systemIcon: "phone.down.fill",
                                glyph: nil,
                                label: "Kết thúc",
                                color: KinnectTheme.danger
                            ) {
                                webrtc.endOrRejectCurrentCall(sendSocket: true)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func statusLabel(for call: ActiveCallSession) -> String {
        switch call.state {
        case .ringingIncoming:
            return call.mode == "video" ? "Cuộc gọi video đến..." : "Cuộc gọi thoại đến..."
        case .dialingOutgoing:
            return "Đang đổ chuông..."
        case .connecting:
            return "Đang kết nối WebRTC..."
        case .connected:
            return "Đang trong cuộc gọi"
        case .ended:
            return "Đã kết thúc"
        }
    }

    private func callActionButton(systemIcon: String?, glyph: KinnectGlyph?, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 64, height: 64)
                    .overlay {
                        if let glyph = glyph {
                            KinnectIcon(glyph: glyph, size: 26, selected: true, tint: .white)
                        } else if let systemIcon = systemIcon {
                            Image(systemName: systemIcon)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                        }
                    }
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel(label)
    }

    private func callControlCircle(
        glyphWhenActive: KinnectGlyph?,
        slashedSystemIconWhenOff: String,
        active: Bool,
        label: String,
        accessibilityStateValue: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(active ? Color.white.opacity(0.2) : KinnectTheme.danger.opacity(0.8))
                    .frame(width: 54, height: 54)
                    .overlay {
                        if active, let glyph = glyphWhenActive {
                            KinnectIcon(glyph: glyph, size: 24, selected: true, tint: .white)
                        } else {
                            Image(systemName: slashedSystemIconWhenOff)
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityStateValue)
    }
}

