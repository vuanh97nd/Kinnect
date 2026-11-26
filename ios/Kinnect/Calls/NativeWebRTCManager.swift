import AVFoundation
import Foundation
import SwiftUI
import UIKit
import WebRTC

struct ActiveCallSession: Identifiable, Equatable {
    var id: String { callId }
    let callId: String
    let peerUser: KinnectUser
    var mode: String // "video" | "audio"
    var isIncoming: Bool
    var state: CallLifecycleState
    var connectedAt: Date? = nil
    var isReconnecting: Bool = false

    enum CallLifecycleState: String, Equatable {
        case ringingIncoming
        case dialingOutgoing
        case connecting
        case connected
        case ended
    }
}

struct WebRTCVideoRendererView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var mirror: Bool = false

    final class Coordinator {
        weak var currentTrack: RTCVideoTrack?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if context.coordinator.currentTrack !== track {
            context.coordinator.currentTrack?.remove(uiView)
            context.coordinator.currentTrack = track
            track?.add(uiView)
        }
        uiView.transform = mirror ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.currentTrack?.remove(uiView)
        coordinator.currentTrack = nil
    }
}

final class NativeWebRTCManager: NSObject, ObservableObject {
    static let shared = NativeWebRTCManager()

    @Published var activeCall: ActiveCallSession? {
        didSet {
            Task { @MainActor in
                AppState.shared.syncSocketRealtimeSessionFlag()
            }
        }
    }
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var isMicMuted: Bool = false
    @Published var isCameraOff: Bool = false
    @Published var isSpeakerOn: Bool = true
    @Published var usingFrontCamera: Bool = true

    // Live stream WebRTC state
    @Published var liveLocalVideoTrack: RTCVideoTrack?
    @Published var liveRemoteVideoTrack: RTCVideoTrack?
    @Published var liveRemoteVideoTracks: [String: RTCVideoTrack] = [:]
    @Published private(set) var livePrimaryRemotePeerId: String? = nil

    private let factory: RTCPeerConnectionFactory
    private var callPeerConnection: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var videoSource: RTCVideoSource?
    private let stateLock = NSLock()
    private var cachedIceServers: [RTCIceServer] = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"])
    ]
    private var pendingIceCandidates: [RTCIceCandidate] = []

    // Live broadcast peer connections (SFU uplink/downlink & mesh peers)
    private var livePeerConnections: [String: PeerConnectionBox] = [:]
    private var liveHostPeerId: String? = nil
    private var liveStageRevision: Int = 0
    private var liveTransport: String = "mesh"
    private var liveStageRole: String = "viewer"
    private var liveStageActive: Bool = false
    private var liveAudioTrack: RTCAudioTrack?
    private var liveCapturer: RTCCameraVideoCapturer?
    private var liveVideoSource: RTCVideoSource?
    private var liveProcessor: LiveVideoProcessor?
    @Published private(set) var liveEffects = LiveVideoSettings()
    private var pendingAnswerCallId: String?
    private var pendingIncomingCallSignals: [[String: Any]] = []
    private var isStartingCall = false
    private var callReconnectGraceTask: Task<Void, Never>? = nil

    @MainActor
    func updateLiveEffects(_ value: LiveVideoSettings) {
        liveEffects = value
        liveProcessor?.update(value)
    }

    private override init() {
        RTCInitializeSSL()
        RTCAudioSession.sharedInstance().useManualAudio = true
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        super.init()
    }

    // MARK: - ICE Server Configuration

    private func getIceServers() -> [RTCIceServer] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedIceServers
    }

    private func setIceServers(_ servers: [RTCIceServer]) {
        stateLock.lock()
        defer { stateLock.unlock() }
        cachedIceServers = servers
    }

    func refreshIceServers() async {
        do {
            let json = try await KinnectAPIClient.shared.requestJSON("/api/call-config")
            guard let list = json["iceServers"] as? [[String: Any]], !list.isEmpty else { return }
            var built: [RTCIceServer] = []
            for entry in list {
                var urls: [String] = []
                if let single = entry["urls"] as? String {
                    urls.append(single)
                } else if let arr = entry["urls"] as? [String] {
                    urls.append(contentsOf: arr)
                }
                guard !urls.isEmpty else { continue }
                let username = entry["username"] as? String ?? ""
                let credential = entry["credential"] as? String ?? ""
                if !username.isEmpty || !credential.isEmpty {
                    built.append(RTCIceServer(urlStrings: urls, username: username, credential: credential))
                } else {
                    built.append(RTCIceServer(urlStrings: urls))
                }
            }
            if !built.isEmpty {
                self.setIceServers(built)
            }
        } catch {
            // Keep default STUN servers
        }
    }

    // MARK: - 1-1 Direct Call Flow

    @MainActor
    func startOutgoingCall(targetUser: KinnectUser, mode: String) async {
        guard activeCall == nil, !isStartingCall else { return }
        isStartingCall = true
        defer { isStartingCall = false }
        let isVideo = (mode != "audio")
        let micOk = await MediaPermissionHandler.shared.requestMicrophoneAccess()
        guard micOk else { return }
        if isVideo {
            _ = await MediaPermissionHandler.shared.requestCameraAccess()
        }

        guard await NativeSocketClient.shared.ensureConnected() else {
            AppState.shared.showToast("Chưa kết nối được cuộc gọi. Vui lòng thử lại.")
            return
        }
        await refreshIceServers()
        guard await NativeSocketClient.shared.ensureConnected(), activeCall == nil else { return }
        let callId = "call_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))"
        let session = ActiveCallSession(
            callId: callId,
            peerUser: targetUser,
            mode: isVideo ? "video" : "audio",
            isIncoming: false,
            state: .dialingOutgoing
        )
        self.activeCall = session
        MediaPermissionHandler.shared.configureAudioSessionForCall(speaker: isVideo)
        prepareLocalCallMedia(isVideo: isVideo)
        CallAudioFeedback.shared.ringback()
        CallKitManager.shared.startOutgoingCall(callId: callId, targetName: targetUser.name, isVideo: isVideo)

        NativeSocketClient.shared.sendJSON([
            "type": "call-start",
            "callId": callId,
            "to": targetUser.id,
            "targetUserId": targetUser.id,
            "requestId": callId,
            "mode": isVideo ? "video" : "audio"
        ])
    }

    @MainActor
    func handleCallRingingSocket(_ json: [String: Any]) {
        guard let current = activeCall, !current.isIncoming, current.state == .dialingOutgoing else { return }
        let requestId = json["requestId"] as? String ?? ""
        let canonicalId = json["callId"] as? String ?? ""
        guard requestId == current.callId || canonicalId == current.callId else { return }
        if let serverCallId = json["callId"] as? String, !serverCallId.isEmpty {
                CallKitManager.shared.remapCallId(from: current.callId, to: serverCallId)
                let updated = ActiveCallSession(
                    callId: serverCallId,
                    peerUser: current.peerUser,
                    mode: current.mode,
                    isIncoming: current.isIncoming,
                    state: current.state
                )
                self.activeCall = updated
            }
        }

    @MainActor
    func handleIncomingCallSocket(_ json: [String: Any]) {
        let callId = json["callId"] as? String ?? ""
        guard !callId.isEmpty else { return }
        if activeCall != nil && activeCall?.callId != callId {
            NativeSocketClient.shared.sendJSON([
                "type": "call-decline",
                "callId": callId,
                "reason": "busy"
            ])
            return
        }

        if let current = activeCall, current.callId == callId,
           current.state == .connecting || current.state == .connected { return }
        let mode = json["mode"] as? String ?? "video"
        let fromDict = json["from"] as? [String: Any] ?? [:]
        let caller = KinnectUser.from(fromDict)
        let isVideo = (mode != "audio")

        if self.activeCall?.callId != callId {
            self.pendingIncomingCallSignals.removeAll()
        }
        self.activeCall = ActiveCallSession(
            callId: callId,
            peerUser: caller,
            mode: isVideo ? "video" : "audio",
            isIncoming: true,
            state: .ringingIncoming
        )
        CallKitManager.shared.reportIncomingCall(callId: callId, callerName: caller.name, isVideo: isVideo)
        if pendingAnswerCallId == callId {
            pendingAnswerCallId = nil
            Task { await acceptIncomingCall(callId: callId) }
        }
    }

    @MainActor
    func acceptIncomingCall(callId: String? = nil, activateAudioDirectly: Bool = false) async {
        guard var current = activeCall else {
            pendingAnswerCallId = callId
            NativeSocketClient.shared.connectWithKeychainSession()
            return
        }
        if let callId, current.callId != callId { return }
        guard current.state == .ringingIncoming else { return }

        let isVideo = (current.mode != "audio")
        guard await MediaPermissionHandler.shared.requestMicrophoneAccess() else {
            endOrRejectCurrentCall()
            AppState.shared.showToast("Hãy cho phép dùng micro trong Cài đặt để nhận cuộc gọi.")
            return
        }
        if isVideo {
            _ = await MediaPermissionHandler.shared.requestCameraAccess()
        }
        await refreshIceServers()
        guard await NativeSocketClient.shared.ensureConnected() else {
            endOrRejectCurrentCall()
            AppState.shared.showToast("Chưa kết nối được cuộc gọi. Vui lòng thử lại.")
            return
        }
        guard activeCall?.callId == current.callId,
              activeCall?.state == .ringingIncoming else { return }

        CallAudioFeedback.shared.stop()
        current.state = .connecting
        self.activeCall = current
        let needsManualAudioActivation = activateAudioDirectly || !CallKitManager.shared.hasCallKitSession(callId: current.callId)
        MediaPermissionHandler.shared.configureAudioSessionForCall(
            speaker: isVideo,
            activate: needsManualAudioActivation
        )
        if needsManualAudioActivation {
            let rtcAudio = RTCAudioSession.sharedInstance()
            rtcAudio.audioSessionDidActivate(AVAudioSession.sharedInstance())
            rtcAudio.isAudioEnabled = true
        }
        prepareLocalCallMedia(isVideo: isVideo)
        setupCallPeerConnection()

        NativeSocketClient.shared.sendJSON([
            "type": "call-accept",
            "callId": current.callId
        ])

        if !pendingIncomingCallSignals.isEmpty {
            let buffered = pendingIncomingCallSignals
            pendingIncomingCallSignals.removeAll()
            for signalMsg in buffered {
                handleCallSignalSocket(signalMsg)
            }
        }
    }

    @MainActor
    func endOrRejectCurrentCall(sendSocket: Bool = true, fallbackCallId: String? = nil) {
        pendingAnswerCallId = nil
        CallAudioFeedback.shared.stop()
        guard let current = activeCall else {
            // CallKit can be answered or declined before the websocket finishes reconnecting.
            if sendSocket, let callId = fallbackCallId {
                Task {
                    _ = try? await KinnectAPIClient.shared.requestJSON(
                        "/api/push/decline", method: "POST", body: ["callId": callId])
                }
                CallKitManager.shared.reportCallEnded(callId: callId)
            }
            return
        }
        let callId = current.callId
        if sendSocket {
            let msgType: String
            if current.isIncoming && current.state == .ringingIncoming {
                msgType = "call-decline"
                if !NativeSocketClient.shared.isConnected {
                    Task {
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/push/decline", method: "POST", body: ["callId": callId])
                    }
                }
            } else if !current.isIncoming && current.state == .dialingOutgoing {
                msgType = "call-cancel"
            } else {
                msgType = "call-end"
            }
            NativeSocketClient.shared.sendJSON([
                "type": msgType,
                "callId": callId
            ])
        }
        let hadCallKit = CallKitManager.shared.hasCallKitSession(callId: callId) || CallKitManager.shared.isAudioSessionActive
        CallKitManager.shared.reportCallEnded(callId: callId, reason: .remoteEnded)
        cleanupCallMedia(callKitManaged: hadCallKit)
        self.activeCall = nil
        if sendSocket { CallAudioFeedback.shared.ended() }
    }

    @MainActor
    func handleCallAcceptedSocket(_ json: [String: Any]) {
        guard var current = activeCall else { return }
        let callId = json["callId"] as? String ?? ""
        guard callId == current.callId else { return }

        CallAudioFeedback.shared.stop()
        current.state = .connecting
        self.activeCall = current
        setupCallPeerConnection()
        // The caller creates the offer; the recipient answers it.
        guard !current.isIncoming, let pc = callPeerConnection else { return }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )
        pc.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp, error == nil else { return }
            pc.setLocalDescription(sdp) { err in
                guard err == nil else { return }
                NativeSocketClient.shared.sendJSON([
                    "type": "call-signal",
                    "callId": callId,
                    "description": [
                        "type": Self.sdpTypeString(sdp.type),
                        "sdp": sdp.sdp
                    ],
                    "signal": [
                        "description": [
                            "type": Self.sdpTypeString(sdp.type),
                            "sdp": sdp.sdp
                        ]
                    ]
                ])
            }
        }
    }

    @MainActor
    func handleCallSignalSocket(_ json: [String: Any]) {
        guard let current = activeCall else { return }
        let callId = json["callId"] as? String ?? ""
        guard callId.isEmpty || callId == current.callId else { return }

        // Buffer early incoming call-signal packets until the user accepts and local media tracks are prepared.
        if current.isIncoming && (current.state == .ringingIncoming || (localAudioTrack == nil && callPeerConnection == nil)) {
            pendingIncomingCallSignals.append(json)
            return
        }

        if callPeerConnection == nil {
            setupCallPeerConnection()
        }
        guard let pc = callPeerConnection else { return }

        let signal = json["signal"] as? [String: Any]
        let desc = (json["description"] as? [String: Any]) ?? (signal?["description"] as? [String: Any])
        let cand = (json["candidate"] as? [String: Any]) ?? (signal?["candidate"] as? [String: Any])

        if let desc = desc,
           let typeStr = desc["type"] as? String,
           let sdpText = desc["sdp"] as? String {
            let sdpType: RTCSdpType = (typeStr == "offer") ? .offer : .answer
            let remoteSDP = RTCSessionDescription(type: sdpType, sdp: sdpText)
            pc.setRemoteDescription(remoteSDP) { [weak self] error in
                guard let self = self, error == nil else { return }
                self.drainPendingCandidates(on: pc)
                if sdpType == .offer {
                    let constraints = RTCMediaConstraints(
                        mandatoryConstraints: [
                            "OfferToReceiveAudio": "true",
                            "OfferToReceiveVideo": "true"
                        ],
                        optionalConstraints: nil
                    )
                    pc.answer(for: constraints) { answerSDP, err in
                        guard let answerSDP = answerSDP, err == nil else { return }
                        pc.setLocalDescription(answerSDP) { setErr in
                            guard setErr == nil else { return }
                            NativeSocketClient.shared.sendJSON([
                                "type": "call-signal",
                                "callId": callId.isEmpty ? current.callId : callId,
                                "description": [
                                    "type": Self.sdpTypeString(answerSDP.type),
                                    "sdp": answerSDP.sdp
                                ],
                                "signal": [
                                    "description": [
                                        "type": Self.sdpTypeString(answerSDP.type),
                                        "sdp": answerSDP.sdp
                                    ]
                                ]
                            ])
                        }
                    }
                }
            }
        } else if let cand = cand,
                  let sdp = cand["candidate"] as? String {
            let sdpMid = cand["sdpMid"] as? String
            let sdpMLineIndex: Int32 = (cand["sdpMLineIndex"] as? NSNumber)?.int32Value
                ?? (cand["sdpMLineIndex"] as? Int).map(Int32.init)
                ?? (cand["sdpMLineIndex"] as? String).flatMap(Int32.init)
                ?? 0
            let ice = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            if pc.remoteDescription != nil {
                pc.add(ice) { _ in }
            } else {
                enqueuePendingCandidate(ice)
            }
        }
    }

    @MainActor
    func handleCallEndedSocket(_ json: [String: Any]) {
        let callId = json["callId"] as? String ?? ""
        let requestId = json["requestId"] as? String ?? ""
        guard let current = activeCall else {
            if !callId.isEmpty { CallKitManager.shared.reportCallEnded(callId: callId) }
            return
        }
        guard current.callId == callId || current.callId == requestId else { return }
        CallAudioFeedback.shared.stop()
        let hadCallKit = CallKitManager.shared.hasCallKitSession(callId: current.callId) || CallKitManager.shared.isAudioSessionActive
        CallKitManager.shared.reportCallEnded(callId: current.callId, reason: .remoteEnded)
        cleanupCallMedia(callKitManaged: hadCallKit)
        activeCall = nil
        let reason = json["reason"] as? String ?? ""
        CallAudioFeedback.shared.ended(busy: reason == "busy" || reason == "declined")
        if reason == "busy" { AppState.shared.showToast("Người này đang bận.") }
        if reason == "offline" || reason == "unavailable" { AppState.shared.showToast("Hiện chưa liên lạc được với người này.") }
        if reason == "disconnected" { AppState.shared.showToast("Cuộc gọi đã kết thúc do mất kết nối.") }
    }

    @MainActor
    func handleCallReconnectingSocket(_ json: [String: Any]) {
        guard let current = activeCall else { return }
        let callId = json["callId"] as? String ?? ""
        guard callId.isEmpty || callId == current.callId else { return }
        beginCallReconnectGrace(for: current.callId)
    }

    @MainActor
    func handleCallResumedSocket(_ json: [String: Any]) {
        guard let current = activeCall else { return }
        let callId = json["callId"] as? String ?? ""
        guard callId.isEmpty || callId == current.callId else { return }
        Task { @MainActor [weak self] in
            guard let self, self.activeCall?.callId == current.callId else { return }
            await self.refreshIceServers()
            self.restartCallIceIfNeeded()
        }
    }

    @MainActor
    private func beginCallReconnectGrace(for callId: String) {
        guard var current = activeCall, current.callId == callId,
              current.state == .connecting || current.state == .connected else { return }
        if !current.isReconnecting {
            current.isReconnecting = true
            self.activeCall = current
        }
        if !NativeSocketClient.shared.isConnected {
            NativeSocketClient.shared.connectWithKeychainSession()
        }
        callReconnectGraceTask?.cancel()
        callReconnectGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, let self,
                  let liveCall = self.activeCall,
                  liveCall.callId == callId,
                  liveCall.isReconnecting else { return }
            self.endOrRejectCurrentCall(sendSocket: false)
        }
    }

    @MainActor
    private func restartCallIceIfNeeded() {
        guard let current = activeCall else { return }
        if callPeerConnection == nil {
            setupCallPeerConnection()
        }
        guard let pc = callPeerConnection else { return }
        let updatedConfig = pc.configuration
        updatedConfig.iceServers = getIceServers()
        _ = pc.setConfiguration(updatedConfig)
        pc.restartIce()
        // Offer from the active caller side to prevent SDP glare when both peers receive `call-resumed`.
        guard !current.isIncoming else { return }
        let callId = current.callId
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true",
                "IceRestart": "true"
            ],
            optionalConstraints: nil
        )
        pc.offer(for: constraints) { sdp, error in
            guard let sdp = sdp, error == nil else { return }
            pc.setLocalDescription(sdp) { err in
                guard err == nil else { return }
                let descPayload: [String: Any] = [
                    "type": Self.sdpTypeString(sdp.type),
                    "sdp": sdp.sdp
                ]
                NativeSocketClient.shared.sendJSON([
                    "type": "call-signal",
                    "callId": callId,
                    "description": descPayload,
                    "signal": ["description": descPayload]
                ])
            }
        }
    }

    // MARK: - Controls

    @MainActor
    func toggleMute() {
        isMicMuted.toggle()
        localAudioTrack?.isEnabled = !isMicMuted
        liveAudioTrack?.isEnabled = !isMicMuted
    }

    @MainActor
    func setMuted(_ muted: Bool) {
        isMicMuted = muted
        localAudioTrack?.isEnabled = !muted
        liveAudioTrack?.isEnabled = !muted
    }

    @MainActor
    func setMicrophoneMuted(_ muted: Bool) {
        setMuted(muted)
    }

    @MainActor
    func toggleCamera() {
        isCameraOff.toggle()
        localVideoTrack?.isEnabled = !isCameraOff
        liveLocalVideoTrack?.isEnabled = !isCameraOff
    }

    @MainActor
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        MediaPermissionHandler.shared.configureAudioSessionForCall(
            speaker: isSpeakerOn,
            activate: false,
            explicitRouteToggle: true
        )
    }

    @MainActor
    func switchCamera() {
        usingFrontCamera.toggle()
        if let capturer = videoCapturer {
            startCapture(on: capturer, front: usingFrontCamera)
        }
        if let liveCap = liveCapturer {
            startCapture(on: liveCap, front: usingFrontCamera)
        }
    }

    @MainActor
    func flipCamera() {
        switchCamera()
    }

    // MARK: - Private Call Setup

    private func prepareLocalCallMedia(isVideo: Bool) {
        isMicMuted = false
        isCameraOff = !isVideo
        isSpeakerOn = isVideo
        usingFrontCamera = true

        let audioSource = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "kinnect_audio0")
        audioTrack.isEnabled = true
        self.localAudioTrack = audioTrack

        if isVideo {
            let vSource = factory.videoSource()
            let capturer = RTCCameraVideoCapturer(delegate: vSource)
            let vTrack = factory.videoTrack(with: vSource, trackId: "kinnect_video0")
            vTrack.isEnabled = true
            self.videoSource = vSource
            self.videoCapturer = capturer
            self.localVideoTrack = vTrack
            startCapture(on: capturer, front: usingFrontCamera)
        } else {
            self.localVideoTrack = nil
        }
    }

    private func setupCallPeerConnection() {
        guard callPeerConnection == nil else { return }
        let config = RTCConfiguration()
        config.iceServers = getIceServers()
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
        self.callPeerConnection = pc

        let streamId = "kinnect_call_stream"
        if let audio = localAudioTrack {
            pc.add(audio, streamIds: [streamId])
        }
        if let video = localVideoTrack {
            pc.add(video, streamIds: [streamId])
        }
    }

    private func enqueuePendingCandidate(_ ice: RTCIceCandidate) {
        stateLock.lock()
        pendingIceCandidates.append(ice)
        stateLock.unlock()
    }

    private func clearPendingCandidates() {
        stateLock.lock()
        pendingIceCandidates.removeAll()
        stateLock.unlock()
    }

    private func drainPendingCandidates(on pc: RTCPeerConnection) {
        stateLock.lock()
        let queued = pendingIceCandidates
        pendingIceCandidates.removeAll()
        stateLock.unlock()
        for candidate in queued {
            pc.add(candidate) { _ in }
        }
    }

    private func startCapture(on capturer: RTCCameraVideoCapturer, front: Bool) {
        let position: AVCaptureDevice.Position = front ? .front : .back
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == position }) ?? devices.first else { return }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let targetFormat = formats.first(where: {
            let dim = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return dim.width == 1280 && dim.height == 720
        }) ?? formats.last

        guard let format = targetFormat else { return }
        let fps = format.videoSupportedFrameRateRanges.first.map { Int(min($0.maxFrameRate, 30)) } ?? 30
        capturer.startCapture(with: device, format: format, fps: fps)
    }

    @MainActor
    private func cleanupCallMedia(callKitManaged: Bool = false) {
        callReconnectGraceTask?.cancel()
        callReconnectGraceTask = nil
        videoCapturer?.stopCapture()
        videoCapturer = nil
        videoSource = nil
        localAudioTrack = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        pendingIncomingCallSignals.removeAll()
        clearPendingCandidates()
        callPeerConnection?.close()
        callPeerConnection = nil
        if !callKitManaged && !CallKitManager.shared.isAudioSessionActive {
            let rtcAudio = RTCAudioSession.sharedInstance()
            rtcAudio.isAudioEnabled = false
            rtcAudio.audioSessionDidDeactivate(AVAudioSession.sharedInstance())
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            MediaPermissionHandler.shared.configureAudioSessionForMedia()
        }
    }

    // MARK: - Live Stream WebRTC (Host, SFU & Viewer)

    @MainActor
    func prepareLiveViewerAudio() {
        guard activeCall == nil else { return }
        MediaPermissionHandler.shared.configureAudioSessionForLiveViewer()
        let rtcAudio = RTCAudioSession.sharedInstance()
        rtcAudio.audioSessionDidActivate(AVAudioSession.sharedInstance())
        rtcAudio.isAudioEnabled = true
    }

    @MainActor
    func startLiveHostBroadcast() async -> Bool {
        let mic = await MediaPermissionHandler.shared.requestMicrophoneAccess()
        let camera = await MediaPermissionHandler.shared.requestCameraAccess()
        guard mic && camera else { return false }
        await refreshIceServers()

        MediaPermissionHandler.shared.configureAudioSessionForCall(speaker: true, activate: true)
        let rtcAudio = RTCAudioSession.sharedInstance()
        rtcAudio.audioSessionDidActivate(AVAudioSession.sharedInstance())
        rtcAudio.isAudioEnabled = true
        let aSource = factory.audioSource(with: nil)
        let aTrack = factory.audioTrack(with: aSource, trackId: "live_audio0")
        self.liveAudioTrack = aTrack

        let vSource = factory.videoSource()
        let processor = LiveVideoProcessor(source: vSource)
        processor.update(liveEffects)
        liveProcessor = processor
        let capturer = RTCCameraVideoCapturer(delegate: processor)
        let vTrack = factory.videoTrack(with: vSource, trackId: "live_video0")
        self.liveVideoSource = vSource
        self.liveCapturer = capturer
        self.liveLocalVideoTrack = vTrack
        startCapture(on: capturer, front: usingFrontCamera)
        return true
    }

    @MainActor
    func setLiveHostPeerId(_ peerId: String?) {
        liveHostPeerId = peerId
        syncPrimaryLiveRemoteVideoTrack()
    }

    @MainActor
    private func syncPrimaryLiveRemoteVideoTrack() {
        if let hostPid = liveHostPeerId, !hostPid.isEmpty,
           let hostTrack = liveRemoteVideoTracks[hostPid] {
            liveRemoteVideoTrack = hostTrack
            livePrimaryRemotePeerId = hostPid
            return
        }
        if let firstKey = liveRemoteVideoTracks.keys.sorted().first,
           let firstTrack = liveRemoteVideoTracks[firstKey] {
            liveRemoteVideoTrack = firstTrack
            livePrimaryRemotePeerId = firstKey
        } else {
            liveRemoteVideoTrack = nil
            livePrimaryRemotePeerId = nil
        }
    }

    @MainActor
    func stopLiveLocalMedia() {
        liveCapturer?.stopCapture()
        liveCapturer = nil
        liveVideoSource = nil
        liveProcessor = nil
        liveAudioTrack = nil
        liveLocalVideoTrack = nil
        if activeCall == nil {
            prepareLiveViewerAudio()
        }
    }

    @MainActor
    private func attachLiveStagePeer(
        _ peer: [String: Any],
        isPublisher: Bool,
        transport: String,
        revision: Int
    ) {
        guard let peerId = peer["id"] as? String, !peerId.isEmpty else { return }
        let shouldOffer = (peer["offer"] as? Bool) == true
        let peerPublishes = (peer["publishes"] as? Bool) == true
        let attachLocalMedia = isPublisher && (transport != "sfu" || peerId == "@sfu")
        guard let box = createLivePeerBox(peerId: peerId, isPublisher: attachLocalMedia, stageRevision: revision),
              let pc = box.pc else { return }
        livePeerConnections[peerId] = box

        if shouldOffer {
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    "OfferToReceiveAudio": peerPublishes ? "true" : "false",
                    "OfferToReceiveVideo": peerPublishes ? "true" : "false"
                ],
                optionalConstraints: nil
            )
            pc.offer(for: constraints) { sdp, err in
                guard let sdp = sdp, err == nil else { return }
                pc.setLocalDescription(sdp) { setErr in
                    guard setErr == nil else { return }
                    let descPayload: [String: Any] = [
                        "type": Self.sdpTypeString(sdp.type),
                        "sdp": sdp.sdp
                    ]
                    var payload: [String: Any] = [
                        "type": "signal",
                        "to": peerId,
                        "description": descPayload,
                        "signal": ["description": descPayload]
                    ]
                    if revision > 0 {
                        payload["revision"] = revision
                    }
                    NativeSocketClient.shared.sendJSON(payload)
                }
            }
        }
    }

    @MainActor
    func applyLiveStage(
        revision: Int,
        transport: String,
        role: String,
        peers: [[String: Any]],
        participants: [[String: Any]] = []
    ) {
        if let hostParticipant = participants.first(where: { ($0["role"] as? String) == "host" }),
           let hostPid = hostParticipant["id"] as? String, !hostPid.isEmpty {
            liveHostPeerId = hostPid
        }
        let isPublisher = (role == "host" || role == "guest")
        if !isPublisher && (liveCapturer != nil || liveLocalVideoTrack != nil || liveAudioTrack != nil) {
            stopLiveLocalMedia()
        }

        if liveStageActive && liveStageRevision == revision && liveTransport == transport && liveStageRole == role {
            let desiredIds = Set(peers.compactMap { $0["id"] as? String }.filter { !$0.isEmpty })
            let validIds: Set<String>
            if transport == "sfu" {
                let participantIds = Set(participants.compactMap { $0["id"] as? String }.filter { !$0.isEmpty })
                validIds = desiredIds.union(participantIds)
            } else {
                validIds = desiredIds
            }
            for existingId in Array(livePeerConnections.keys) where !validIds.contains(existingId) {
                if let existing = livePeerConnections.removeValue(forKey: existingId) {
                    existing.pc?.close()
                }
                liveRemoteVideoTracks.removeValue(forKey: existingId)
            }
            for peer in peers {
                guard let peerId = peer["id"] as? String, !peerId.isEmpty else { continue }
                if livePeerConnections[peerId] == nil {
                    attachLiveStagePeer(peer, isPublisher: isPublisher, transport: transport, revision: revision)
                }
            }
            syncPrimaryLiveRemoteVideoTrack()
            return
        }
        liveStageRevision = revision
        liveTransport = transport
        liveStageRole = role
        liveStageActive = true

        for (_, box) in livePeerConnections {
            box.pc?.close()
        }
        livePeerConnections.removeAll()
        liveRemoteVideoTracks.removeAll()
        syncPrimaryLiveRemoteVideoTrack()

        if !isPublisher {
            prepareLiveViewerAudio()
        }

        for peer in peers {
            attachLiveStagePeer(peer, isPublisher: isPublisher, transport: transport, revision: revision)
        }
    }

    @MainActor
    func handleLiveViewerJoined(peerId: String) {
        guard !peerId.isEmpty else { return }
        if let existing = livePeerConnections.removeValue(forKey: peerId) {
            existing.pc?.close()
        }
        let rev = liveStageActive ? liveStageRevision : 0
        guard let box = createLivePeerBox(peerId: peerId, isPublisher: true, stageRevision: rev),
              let pc = box.pc else { return }
        livePeerConnections[peerId] = box

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "false", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil
        )
        pc.offer(for: constraints) { sdp, err in
            guard let sdp = sdp, err == nil else { return }
            pc.setLocalDescription(sdp) { setErr in
                guard setErr == nil else { return }
                let descPayload: [String: Any] = [
                    "type": Self.sdpTypeString(sdp.type),
                    "sdp": sdp.sdp
                ]
                var payload: [String: Any] = [
                    "type": "signal",
                    "to": peerId,
                    "description": descPayload,
                    "signal": ["description": descPayload]
                ]
                if rev > 0 {
                    payload["revision"] = rev
                }
                NativeSocketClient.shared.sendJSON(payload)
            }
        }
    }

    @MainActor
    func handleLivePeerLeft(peerId: String) {
        guard !peerId.isEmpty else { return }
        if let existing = livePeerConnections.removeValue(forKey: peerId) {
            existing.pc?.close()
        }
        if liveRemoteVideoTracks.removeValue(forKey: peerId) != nil {
            syncPrimaryLiveRemoteVideoTrack()
        }
    }

    @MainActor
    func handleLiveSignal(from peerId: String, signal: [String: Any], revision: Int? = nil, isPublisher: Bool) {
        guard !peerId.isEmpty else { return }
        if liveStageActive,
           let rev = revision,
           rev > 0,
           liveStageRevision > 0,
           rev != liveStageRevision {
            return
        }
        let effectiveRevision: Int = {
            if let rev = revision, rev > 0 { return rev }
            return liveStageActive ? liveStageRevision : 0
        }()

        let box: PeerConnectionBox
        if let existing = livePeerConnections[peerId] {
            box = existing
        } else {
            let attachLocalMedia = isPublisher && (liveTransport != "sfu" || peerId == "@sfu")
            guard let created = createLivePeerBox(
                peerId: peerId,
                isPublisher: attachLocalMedia,
                stageRevision: effectiveRevision
            ) else { return }
            livePeerConnections[peerId] = created
            box = created
        }
        guard let pc = box.pc else { return }

        if let desc = signal["description"] as? [String: Any],
           let typeStr = desc["type"] as? String,
           let sdpText = desc["sdp"] as? String {
            let sdpType: RTCSdpType = (typeStr == "offer") ? .offer : .answer
            let remoteSDP = RTCSessionDescription(type: sdpType, sdp: sdpText)
            pc.setRemoteDescription(remoteSDP) { err in
                guard err == nil else { return }
                box.drainPendingCandidates()
                if sdpType == .offer {
                    let constraints = RTCMediaConstraints(
                        mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
                        optionalConstraints: nil
                    )
                    pc.answer(for: constraints) { answer, ansErr in
                        guard let answer = answer, ansErr == nil else { return }
                        pc.setLocalDescription(answer) { setErr in
                            guard setErr == nil else { return }
                            let descPayload: [String: Any] = [
                                "type": Self.sdpTypeString(answer.type),
                                "sdp": answer.sdp
                            ]
                            var payload: [String: Any] = [
                                "type": "signal",
                                "to": peerId,
                                "description": descPayload,
                                "signal": ["description": descPayload]
                            ]
                            if effectiveRevision > 0 {
                                payload["revision"] = effectiveRevision
                            }
                            NativeSocketClient.shared.sendJSON(payload)
                        }
                    }
                }
            }
        } else if let cand = signal["candidate"] as? [String: Any],
                  let sdp = cand["candidate"] as? String {
            let sdpMid = cand["sdpMid"] as? String
            let sdpMLineIndex: Int32 = (cand["sdpMLineIndex"] as? NSNumber)?.int32Value
                ?? (cand["sdpMLineIndex"] as? Int).map(Int32.init)
                ?? (cand["sdpMLineIndex"] as? String).flatMap(Int32.init)
                ?? 0
            let ice = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            if pc.remoteDescription != nil {
                pc.add(ice) { _ in }
            } else {
                box.enqueueCandidate(ice)
            }
        }
    }

    @MainActor
    func stopLiveSession() {
        liveCapturer?.stopCapture()
        liveCapturer = nil
        liveVideoSource = nil
        liveProcessor = nil
        liveAudioTrack = nil
        liveLocalVideoTrack = nil
        liveRemoteVideoTracks.removeAll()
        liveRemoteVideoTrack = nil
        livePrimaryRemotePeerId = nil
        liveHostPeerId = nil
        liveStageRevision = 0
        liveTransport = "mesh"
        liveStageRole = "viewer"
        liveStageActive = false
        for (_, box) in livePeerConnections {
            box.pc?.close()
        }
        livePeerConnections.removeAll()
        if activeCall == nil {
            let rtcAudio = RTCAudioSession.sharedInstance()
            rtcAudio.isAudioEnabled = false
            rtcAudio.audioSessionDidDeactivate(AVAudioSession.sharedInstance())
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            MediaPermissionHandler.shared.configureAudioSessionForMedia()
        }
    }

    @MainActor
    private func createLivePeerBox(peerId: String, isPublisher: Bool, stageRevision: Int) -> PeerConnectionBox? {
        if !isPublisher {
            prepareLiveViewerAudio()
        }
        let config = RTCConfiguration()
        config.iceServers = getIceServers()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        let box = PeerConnectionBox(peerId: peerId, stageRevision: stageRevision) { [weak self] videoTrack in
            Task { @MainActor [weak self] in
                guard let self, self.livePeerConnections[peerId] != nil else { return }
                self.liveRemoteVideoTracks[peerId] = videoTrack
                self.syncPrimaryLiveRemoteVideoTrack()
            }
        }
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: box) else {
            return nil
        }
        box.pc = pc
        if isPublisher {
            if let aTrack = liveAudioTrack {
                pc.add(aTrack, streamIds: ["kinnect_live"])
            }
            if let vTrack = liveLocalVideoTrack {
                pc.add(vTrack, streamIds: ["kinnect_live"])
            }
        }
        return box
    }

    private static func sdpTypeString(_ type: RTCSdpType) -> String {
        switch type {
        case .offer: return "offer"
        case .prAnswer: return "pranswer"
        case .answer: return "answer"
        case .rollback: return "rollback"
        @unknown default: return "offer"
        }
    }
}

// MARK: - RTCPeerConnectionDelegate (1-1 Call)

extension NativeWebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let videoTrack = stream.videoTracks.first {
            Task { @MainActor [weak self] in
                guard let self, self.callPeerConnection === peerConnection else { return }
                self.remoteVideoTrack = videoTrack
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    private func markCallConnectedIfNeeded(for peerConnection: RTCPeerConnection) {
        Task { @MainActor [weak self] in
            guard let self,
                  self.callPeerConnection === peerConnection,
                  var current = self.activeCall else { return }
            self.callReconnectGraceTask?.cancel()
            self.callReconnectGraceTask = nil
            CallAudioFeedback.shared.stop()
            let wasConnected = (current.state == .connected)
            if !wasConnected && !current.isIncoming {
                CallKitManager.shared.reportCallConnected(callId: current.callId)
            }
            if current.connectedAt == nil {
                current.connectedAt = Date()
            }
            current.state = .connected
            current.isReconnecting = false
            self.activeCall = current
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if newState == .connected || newState == .completed {
            markCallConnectedIfNeeded(for: peerConnection)
        } else if newState == .disconnected || newState == .failed {
            Task { @MainActor [weak self] in
                guard let self,
                      self.callPeerConnection === peerConnection,
                      let current = self.activeCall else { return }
                if current.state == .connecting || current.state == .connected || current.isReconnecting {
                    self.beginCallReconnectGrace(for: current.callId)
                    if newState == .failed && NativeSocketClient.shared.isConnected && !current.isIncoming {
                        self.restartCallIceIfNeeded()
                    }
                } else {
                    self.endOrRejectCurrentCall(sendSocket: false)
                }
            }
        } else if newState == .closed {
            Task { @MainActor [weak self] in
                guard let self, self.callPeerConnection === peerConnection else { return }
                self.endOrRejectCurrentCall(sendSocket: false)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        if newState == .connected {
            markCallConnectedIfNeeded(for: peerConnection)
        } else if newState == .disconnected || newState == .failed {
            Task { @MainActor [weak self] in
                guard let self,
                      self.callPeerConnection === peerConnection,
                      let current = self.activeCall else { return }
                if current.state == .connecting || current.state == .connected || current.isReconnecting {
                    self.beginCallReconnectGrace(for: current.callId)
                    if newState == .failed && NativeSocketClient.shared.isConnected && !current.isIncoming {
                        self.restartCallIceIfNeeded()
                    }
                } else {
                    self.endOrRejectCurrentCall(sendSocket: false)
                }
            }
        } else if newState == .closed {
            Task { @MainActor [weak self] in
                guard let self, self.callPeerConnection === peerConnection else { return }
                self.endOrRejectCurrentCall(sendSocket: false)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let sdp = candidate.sdp
        let sdpMid = candidate.sdpMid ?? "0"
        let sdpMLineIndex = candidate.sdpMLineIndex
        Task { @MainActor [weak self] in
            guard let self,
                  self.callPeerConnection === peerConnection,
                  let callId = self.activeCall?.callId else { return }
            NativeSocketClient.shared.sendJSON([
                "type": "call-signal",
                "callId": callId,
                "candidate": [
                    "candidate": sdp,
                    "sdpMid": sdpMid,
                    "sdpMLineIndex": sdpMLineIndex
                ],
                "signal": [
                    "candidate": [
                        "candidate": sdp,
                        "sdpMid": sdpMid,
                        "sdpMLineIndex": sdpMLineIndex
                    ]
                ]
            ])
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            Task { @MainActor [weak self] in
                guard let self, self.callPeerConnection === peerConnection else { return }
                self.remoteVideoTrack = track
            }
        } else if let track = mediaStreams.first?.videoTracks.first {
            Task { @MainActor [weak self] in
                guard let self, self.callPeerConnection === peerConnection else { return }
                self.remoteVideoTrack = track
            }
        }
        if rtpReceiver.track != nil {
            Task { @MainActor [weak self] in
                guard let self,
                      self.callPeerConnection === peerConnection,
                      self.activeCall?.state == .connecting || self.activeCall?.isReconnecting == true else { return }
                if peerConnection.iceConnectionState == .connected || peerConnection.iceConnectionState == .completed || peerConnection.connectionState == .connected {
                    self.markCallConnectedIfNeeded(for: peerConnection)
                }
            }
        }
    }
}

// MARK: - Live PeerConnection Box

private final class PeerConnectionBox: NSObject, RTCPeerConnectionDelegate {
    let peerId: String
    let stageRevision: Int
    var pc: RTCPeerConnection?
    let onRemoteVideo: (RTCVideoTrack) -> Void
    private let candidateLock = NSLock()
    private var pendingCandidates: [RTCIceCandidate] = []

    init(peerId: String, stageRevision: Int = 0, onRemoteVideo: @escaping (RTCVideoTrack) -> Void) {
        self.peerId = peerId
        self.stageRevision = stageRevision
        self.onRemoteVideo = onRemoteVideo
    }

    func enqueueCandidate(_ ice: RTCIceCandidate) {
        candidateLock.lock()
        pendingCandidates.append(ice)
        candidateLock.unlock()
    }

    func drainPendingCandidates() {
        candidateLock.lock()
        let queued = pendingCandidates
        pendingCandidates.removeAll()
        candidateLock.unlock()
        guard let pc else { return }
        for ice in queued {
            pc.add(ice) { _ in }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let v = stream.videoTracks.first {
            onRemoteVideo(v)
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let candPayload: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "0",
            "sdpMLineIndex": candidate.sdpMLineIndex
        ]
        var payload: [String: Any] = [
            "type": "signal",
            "to": peerId,
            "candidate": candPayload,
            "signal": ["candidate": candPayload]
        ]
        if stageRevision > 0 {
            payload["revision"] = stageRevision
        }
        NativeSocketClient.shared.sendJSON(payload)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let v = rtpReceiver.track as? RTCVideoTrack {
            onRemoteVideo(v)
        }
    }
}

