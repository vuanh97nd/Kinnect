import SwiftUI

struct CallOverlayView: View {
    @ObservedObject private var webrtc = NativeWebRTCManager.shared
    @State private var connectedAt: Date?

    var body: some View {
        if let call = webrtc.activeCall {
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.19, blue: 0.25), .black],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                if call.mode == "video", let track = webrtc.remoteVideoTrack {
                    WebRTCVideoRendererView(track: track).ignoresSafeArea()
                    LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.65)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                }
                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        Label(call.mode == "video" ? "Kinnect Video" : "Kinnect Audio",
                              systemImage: call.mode == "video" ? "video.fill" : "phone.fill")
                            .font(.subheadline).foregroundColor(.white.opacity(0.75))
                        if webrtc.remoteVideoTrack == nil {
                            KinnectAvatarView(name: call.peerUser.name, avatarURL: call.peerUser.avatarUrl,
                                              colorHex: call.peerUser.avatarColor, size: 104)
                                .padding(.top, 20)
                        }
                        Text(call.peerUser.name).font(.system(size: 32, weight: .regular))
                            .multilineTextAlignment(.center).foregroundColor(.white)
                        if call.state == .connected, let connectedAt {
                            Text(connectedAt, style: .timer).monospacedDigit().foregroundColor(.white.opacity(0.8))
                        } else {
                            Text(status(call)).font(.title3).foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.top, 32)
                    Spacer(minLength: 24)
                    if call.mode == "video", let track = webrtc.localVideoTrack, !webrtc.isCameraOff {
                        HStack {
                            Spacer()
                            WebRTCVideoRendererView(track: track, mirror: webrtc.usingFrontCamera)
                                .frame(width: 108, height: 152)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.4)))
                        }
                    }
                    if call.isIncoming && call.state == .ringingIncoming {
                        HStack {
                            control("phone.down.fill", "Từ chối", color: .red) {
                                webrtc.endOrRejectCurrentCall()
                            }
                            Spacer()
                            control(call.mode == "video" ? "video.fill" : "phone.fill", "Trả lời", color: .green) {
                                Task { await webrtc.acceptIncomingCall(callId: call.callId) }
                            }
                        }.padding(.horizontal, 28)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 24) {
                            control(webrtc.isMicMuted ? "mic.slash.fill" : "mic.fill", "Tắt tiếng",
                                    selected: webrtc.isMicMuted) { webrtc.toggleMute() }
                            control("speaker.wave.3.fill", "Loa ngoài",
                                    selected: webrtc.isSpeakerOn) { webrtc.toggleSpeaker() }
                            if call.mode == "video" {
                                control(webrtc.isCameraOff ? "video.slash.fill" : "video.fill", "Camera",
                                        selected: webrtc.isCameraOff) { webrtc.toggleCamera() }
                                control("camera.rotate.fill", "Đổi camera") { webrtc.switchCamera() }
                            }
                        }.frame(maxWidth: 280)
                        control("phone.down.fill", "Kết thúc", color: .red) { webrtc.endOrRejectCurrentCall() }
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .frame(minHeight: geometry.size.height)
                    }
                }
            }
            .onAppear { updateTimer(call) }
            .onChange(of: call.state) { _ in updateTimer(call) }
            .onChange(of: call.callId) { _ in connectedAt = nil; updateTimer(call) }
        }
    }

    private func updateTimer(_ call: ActiveCallSession) {
        if call.state == .connected && connectedAt == nil { connectedAt = Date() }
        if call.state != .connected { connectedAt = nil }
    }

    private func status(_ call: ActiveCallSession) -> String {
        switch call.state {
        case .ringingIncoming: return call.mode == "video" ? "Cuộc gọi video đến" : "Cuộc gọi đến"
        case .dialingOutgoing: return "Đang gọi…"
        case .connecting: return "Đang kết nối…"
        case .connected: return "Đã kết nối"
        case .ended: return "Đã kết thúc"
        }
    }

    private func control(_ icon: String, _ title: String, color: Color? = nil,
                         selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 27, weight: .medium))
                    .foregroundColor(selected && color == nil ? .black : .white)
                    .frame(width: 72, height: 72)
                    .background(color ?? (selected ? .white : .white.opacity(0.22)), in: Circle())
                Text(title).font(.system(size: 13)).foregroundColor(.white).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(color == nil ? (selected ? "Bật" : "Tắt") : "")
    }
}
