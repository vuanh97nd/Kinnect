import SwiftUI
import UIKit

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

                    // Action Buttons (Apple iOS In-Call HIG style)
                    if call.isIncoming && call.state == .ringingIncoming {
                        HStack(spacing: 52) {
                            callActionButton(
                                systemIcon: "phone.down.fill",
                                label: "Từ chối",
                                color: KinnectTheme.callRed
                            ) {
                                webrtc.endOrRejectCurrentCall(sendSocket: true)
                            }

                            callActionButton(
                                systemIcon: call.mode == "video" ? "video.fill" : "phone.fill",
                                label: "Trả lời",
                                color: KinnectTheme.callGreen
                            ) {
                                Task { await webrtc.acceptIncomingCall(callId: call.callId) }
                            }
                        }
                        .padding(.bottom, 48)
                    } else {
                        HStack(spacing: 20) {
                            callControlCircle(
                                icon: webrtc.isMicMuted ? "mic.slash.fill" : "mic.fill",
                                isToggledOn: webrtc.isMicMuted,
                                label: webrtc.isMicMuted ? "Bật mic" : "Tắt mic",
                                accessibilityStateValue: webrtc.isMicMuted ? "Đang tắt tiếng" : "Đang bật tiếng"
                            ) {
                                webrtc.toggleMute()
                            }

                            if call.mode == "video" {
                                callControlCircle(
                                    icon: webrtc.isCameraOff ? "video.slash.fill" : "video.fill",
                                    isToggledOn: webrtc.isCameraOff,
                                    label: "Camera",
                                    accessibilityStateValue: webrtc.isCameraOff ? "Đang tắt camera" : "Đang bật camera"
                                ) {
                                    webrtc.toggleCamera()
                                }

                                callControlCircle(
                                    icon: "camera.rotate.fill",
                                    isToggledOn: false,
                                    label: "Đổi cam",
                                    accessibilityStateValue: webrtc.usingFrontCamera ? "Camera trước" : "Camera sau"
                                ) {
                                    webrtc.switchCamera()
                                }
                            }

                            callControlCircle(
                                icon: webrtc.isSpeakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                                isToggledOn: webrtc.isSpeakerOn,
                                label: "Loa ngoài",
                                accessibilityStateValue: webrtc.isSpeakerOn ? "Đang bật loa ngoài" : "Đang dùng loa trong"
                            ) {
                                webrtc.toggleSpeaker()
                            }

                            callActionButton(
                                systemIcon: "phone.down.fill",
                                label: "Kết thúc",
                                color: KinnectTheme.callRed
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

    private func callActionButton(systemIcon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 68, height: 68)
                    .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
                    .overlay {
                        Image(systemName: systemIcon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white)
                    }
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel(label)
    }

    private func callControlCircle(
        icon: String,
        isToggledOn: Bool,
        label: String,
        accessibilityStateValue: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(isToggledOn ? Color.white : Color.white.opacity(0.2))
                    .frame(width: 58, height: 58)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(isToggledOn ? .black : .white)
                    }
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityStateValue)
    }
}

