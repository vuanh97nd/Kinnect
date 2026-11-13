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

    @Published var activeCall: ActiveCallSession?
    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var isMicMuted: Bool = false
    @Published var isCameraOff: Bool = false
    @Published var isSpeakerOn: Bool = true
    @Published var usingFrontCamera: Bool = true

    // Live stream WebRTC state
    @Published var liveLocalVideoTrack: RTCVideoTrack?
    @Published var liveRemoteVideoTrack: RTCVideoTrack?
    @Published var liveRemoteVideoTracksByPeer: [String: RTCVideoTrack] = [:]
    @Published var liveConnectionError: String?
    @Published private(set) var liveRole: String = "viewer"
    @Published private(set) var liveTransport: String = "mesh"
    @Published private(set) var liveStageRevision: Int = 0
    @Published private(set) var liveRoomId: String = ""

    private let factory: RTCPeerConnectionFactory
    private var callPeerConnection: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var videoSource: RTCVideoSource?
    private var cachedIceServers: [RTCIceServer] = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"])
    ]
    private var pendingIceCandidates: [RTCIceCandidate] = []

    // Live broadcast & SFU/mesh stage peer connections
    private var livePeerConnections: [String: PeerConnectionBox] = [:]
    private var livePeerPublishesMap: [String: Bool] = [:]
    private var pendingLiveIceCandidates: [String: [RTCIceCandidate]] = [:]
    private var liveSelfId: String = ""
    private var liveHostPeerId: String = ""
    private var liveStageMode: String = "video"
    private var liveEpoch: Int = 0
    private var liveAudioTrack: RTCAudioTrack?
    private var liveCapturer: RTCCameraVideoCapturer?
    private var liveVideoSource: RTCVideoSource?
    private var liveProcessor: LiveVideoProcessor?
    @Published private(set) var liveEffects = LiveVideoSettings()
    private var pendingAnswerCallId: String?
    private var isStartingCall = false

    @MainActor
    func updateLiveEffects(_ value: LiveVideoSettings) {
        liveEffects = value
        liveProcessor?.update(value)
    }

    private override init() {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        super.init()
    }

    // MARK: - ICE Server Configuration

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
                self.cachedIceServers = built
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
    func acceptIncomingCall(callId: String? = nil) async {
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
        MediaPermissionHandler.shared.configureAudioSessionForCall(speaker: isVideo)
        prepareLocalCallMedia(isVideo: isVideo)
        setupCallPeerConnection()

        NativeSocketClient.shared.sendJSON([
            "type": "call-accept",
            "callId": current.callId
        ])
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
        CallKitManager.shared.reportCallEnded(callId: callId, reason: .remoteEnded)
        cleanupCallMedia()
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
                pendingIceCandidates.append(ice)
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
        CallKitManager.shared.reportCallEnded(callId: current.callId, reason: .remoteEnded)
        cleanupCallMedia()
        activeCall = nil
        let reason = json["reason"] as? String ?? ""
        CallAudioFeedback.shared.ended(busy: reason == "busy" || reason == "declined")
        if reason == "busy" { AppState.shared.showToast("Người này đang bận.") }
        if reason == "offline" { AppState.shared.showToast("Hiện chưa liên lạc được với người này.") }
    }

    // MARK: - Controls

    @MainActor
    func toggleMute() {
        isMicMuted.toggle()
        localAudioTrack?.isEnabled = !isMicMuted
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
    }

    @MainActor
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(isSpeakerOn ? .speaker : .none)
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
        config.iceServers = cachedIceServers
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

    private func drainPendingCandidates(on pc: RTCPeerConnection) {
        let queued = pendingIceCandidates
        pendingIceCandidates.removeAll()
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

    private func cleanupCallMedia() {
        videoCapturer?.stopCapture()
        videoCapturer = nil
        videoSource = nil
        localAudioTrack = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        pendingIceCandidates.removeAll()
        callPeerConnection?.close()
        callPeerConnection = nil
        MediaPermissionHandler.shared.configureAudioSessionForMedia()
    }

    // MARK: - Live Stream WebRTC (Host, Guest & Viewer SFU/Mesh)

    @MainActor
    func prepareLiveRoomSession(roomId: String, role: String) {
        guard !roomId.isEmpty else { return }
        if liveRoomId == roomId {
            liveRole = role
            liveConnectionError = nil
            return
        }
        resetLivePeerConnections()
        liveRoomId = roomId
        liveStageRevision = 0
        liveTransport = "mesh"
        liveSelfId = ""
        liveHostPeerId = ""
        liveStageMode = "video"
        liveRole = role
        liveConnectionError = nil
        if role != "host" && role != "guest" {
            stopLiveLocalMedia()
            MediaPermissionHandler.shared.configureAudioSessionForMedia()
        }
    }

    @MainActor
    func startLiveHostBroadcast() async -> Bool {
        stopLiveLocalMedia()
        let mic = await MediaPermissionHandler.shared.requestMicrophoneAccess()
        let camera = await MediaPermissionHandler.shared.requestCameraAccess()
        guard mic && camera else { return false }
        liveConnectionError = nil
        await refreshIceServers()
        startLocalBroadcastCapture(withVideo: true)
        return true
    }

    @MainActor
    private func ensureLivePublisherMedia(withVideo: Bool) async -> Bool {
        let mic = await MediaPermissionHandler.shared.requestMicrophoneAccess()
        guard mic else { return false }
        if withVideo {
            let camera = await MediaPermissionHandler.shared.requestCameraAccess()
            guard camera else { return false }
        }
        await refreshIceServers()
        MediaPermissionHandler.shared.configureAudioSessionForCall()
        if liveAudioTrack == nil {
            let aSource = factory.audioSource(with: nil)
            self.liveAudioTrack = factory.audioTrack(with: aSource, trackId: "live_audio0")
            self.liveAudioTrack?.isEnabled = !isMicMuted
        }
        if withVideo {
            if liveLocalVideoTrack == nil {
                startLocalBroadcastVideoOnly()
            }
        } else {
            stopLiveLocalVideoOnly()
        }
        return true
    }

    @MainActor
    private func startLocalBroadcastCapture(withVideo: Bool) {
        MediaPermissionHandler.shared.configureAudioSessionForCall()
        let aSource = factory.audioSource(with: nil)
        let aTrack = factory.audioTrack(with: aSource, trackId: "live_audio0")
        aTrack.isEnabled = !isMicMuted
        self.liveAudioTrack = aTrack
        if withVideo {
            startLocalBroadcastVideoOnly()
        }
    }

    @MainActor
    private func startLocalBroadcastVideoOnly() {
        liveCapturer?.stopCapture()
        liveCapturer = nil
        liveVideoSource = nil
        liveProcessor = nil

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
    }

    @MainActor
    private func stopLiveLocalVideoOnly() {
        liveCapturer?.stopCapture()
        liveCapturer = nil
        liveVideoSource = nil
        liveProcessor = nil
        liveLocalVideoTrack = nil
    }

    @MainActor
    private func stopLiveLocalMedia() {
        stopLiveLocalVideoOnly()
        liveAudioTrack = nil
    }

    @MainActor
    func applyLiveStage(
        roomId: String,
        transport: String,
        revision: Int,
        selfId: String,
        role: String,
        mode: String,
        peers rawPeers: [[String: Any]],
        participants: [[String: Any]]
    ) {
        guard !roomId.isEmpty, revision > 0 else { return }
        if roomId == liveRoomId && liveStageRevision > 0 && revision < liveStageRevision {
            return
        }

        let normalizedTransport = LiveStageSignalingContract.normalizeTransport(transport)
        let normalizedRole = LiveStageSignalingContract.normalizeRole(role)
        let normalizedMode = LiveStageSignalingContract.normalizeMode(mode)
        liveHostPeerId = LiveStageSignalingContract.resolveHostPeerId(participants: participants)

        if LiveStageSignalingContract.isLayoutOnlyStageUpdate(
            currentRoomId: liveRoomId,
            incomingRoomId: roomId,
            currentTransport: liveTransport,
            incomingTransport: normalizedTransport,
            currentRevision: liveStageRevision,
            incomingRevision: revision,
            currentRole: liveRole,
            incomingRole: normalizedRole,
            currentMode: liveStageMode,
            incomingMode: normalizedMode
        ) {
            return
        }

        let previousRole = liveRole
        liveRoomId = roomId
        liveTransport = normalizedTransport
        liveStageRevision = revision
        liveSelfId = selfId
        liveRole = normalizedRole
        liveStageMode = normalizedMode
        liveConnectionError = nil

        resetLivePeerConnections()

        let parsedPeers = LiveStageSignalingContract.parsePeers(rawPeers)
        for peer in parsedPeers {
            livePeerPublishesMap[peer.id] = peer.publishes
        }

        let targetEpoch = liveEpoch
        if normalizedRole == "viewer" {
            if previousRole == "host" || previousRole == "guest" || liveCapturer != nil || liveAudioTrack != nil || liveLocalVideoTrack != nil {
                stopLiveLocalMedia()
            }
            MediaPermissionHandler.shared.configureAudioSessionForMedia()
            for peer in parsedPeers where peer.offer {
                initiateLiveOffer(to: peer.id, peerPublishes: peer.publishes, expectedEpoch: targetEpoch, expectedRevision: revision)
            }
            return
        }

        let needsVideo = (normalizedMode != "audio")
        let mediaReady = (liveAudioTrack != nil) && (!needsVideo || liveLocalVideoTrack != nil)
        if mediaReady {
            if !needsVideo {
                stopLiveLocalVideoOnly()
            }
            MediaPermissionHandler.shared.configureAudioSessionForCall()
            for peer in parsedPeers where peer.offer {
                initiateLiveOffer(to: peer.id, peerPublishes: peer.publishes, expectedEpoch: targetEpoch, expectedRevision: revision)
            }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.ensureLivePublisherMedia(withVideo: needsVideo)
            guard self.liveEpoch == targetEpoch,
                  self.liveRoomId == roomId,
                  self.liveStageRevision == revision,
                  (self.liveRole == "host" || self.liveRole == "guest") else { return }
            guard ok else {
                self.liveConnectionError = "Cần quyền camera và micro để lên sân khấu Live."
                if normalizedRole == "guest" {
                    NativeSocketClient.shared.sendJSON([
                        "type": "live-guest-leave",
                        "room": roomId
                    ])
                }
                return
            }
            for peer in parsedPeers where peer.offer {
                self.initiateLiveOffer(to: peer.id, peerPublishes: peer.publishes, expectedEpoch: targetEpoch, expectedRevision: revision)
            }
        }
    }

    @MainActor
    func handleLiveViewerJoined(peerId: String) {
        guard liveStageRevision == 0, !peerId.isEmpty else { return }
        let expectedEpoch = liveEpoch
        initiateLiveOffer(to: peerId, peerPublishes: false, expectedEpoch: expectedEpoch, expectedRevision: 0)
    }

    @MainActor
    private func initiateLiveOffer(to peerId: String, peerPublishes: Bool, expectedEpoch: Int, expectedRevision: Int) {
        guard !peerId.isEmpty,
              liveEpoch == expectedEpoch,
              liveStageRevision == expectedRevision else { return }
        removeLivePeerConnection(peerId: peerId)
        livePeerPublishesMap[peerId] = peerPublishes
        let box = createLivePeerBox(peerId: peerId, roomId: liveRoomId, epoch: expectedEpoch, revision: expectedRevision)
        livePeerConnections[peerId] = box

        let constraints = offerConstraints(for: peerId, peerPublishes: peerPublishes)
        box.pc.offer(for: constraints) { [weak self, weak box] sdp, err in
            guard let sdp = sdp, err == nil else { return }
            DispatchQueue.main.async { [weak self, weak box] in
                guard let self = self,
                      let box = box,
                      self.liveEpoch == expectedEpoch,
                      self.liveStageRevision == expectedRevision,
                      self.livePeerConnections[peerId] === box else { return }
                box.pc.setLocalDescription(sdp) { [weak self, weak box] setErr in
                    guard setErr == nil else { return }
                    DispatchQueue.main.async { [weak self, weak box] in
                        guard let self = self,
                              let box = box,
                              self.liveEpoch == expectedEpoch,
                              self.liveStageRevision == expectedRevision,
                              self.livePeerConnections[peerId] === box else { return }
                        let descPayload: [String: Any] = [
                            "type": Self.sdpTypeString(sdp.type),
                            "sdp": sdp.sdp
                        ]
                        self.sendLiveSignal(
                            to: peerId,
                            revision: expectedRevision,
                            key: "description",
                            payload: descPayload
                        )
                    }
                }
            }
        }
    }

    @MainActor
    func handleLiveSignal(
        from peerId: String,
        roomId: String? = nil,
        revision: Int = 0,
        signal: [String: Any],
        isHost: Bool
    ) {
        guard !peerId.isEmpty else { return }
        let usesStage = (liveStageRevision > 0)
        guard LiveStageSignalingContract.isValidInboundSignal(
            msgRoom: roomId,
            msgRevision: revision,
            currentRoomId: liveRoomId,
            currentRevision: liveStageRevision,
            usesStage: usesStage
        ) else { return }

        if !usesStage && liveRole == "viewer" && isHost {
            liveRole = "host"
        }

        let box: PeerConnectionBox
        if let existing = livePeerConnections[peerId] {
            box = existing
        } else {
            if !usesStage && !isHost {
                liveConnectionError = nil
            } else if usesStage && liveRole == "viewer" {
                liveConnectionError = nil
            }
            let created = createLivePeerBox(
                peerId: peerId,
                roomId: liveRoomId,
                epoch: liveEpoch,
                revision: liveStageRevision
            )
            livePeerConnections[peerId] = created
            box = created
        }

        let capturedEpoch = box.epoch
        let capturedRevision = box.revision

        if let desc = signal["description"] as? [String: Any],
           let typeStr = desc["type"] as? String,
           let sdpText = desc["sdp"] as? String {
            let normalizedType = typeStr.lowercased()
            guard normalizedType == "offer" || normalizedType == "answer" else { return }
            let sdpType: RTCSdpType = (normalizedType == "offer") ? .offer : .answer
            let remoteSDP = RTCSessionDescription(type: sdpType, sdp: sdpText)
            box.pc.setRemoteDescription(remoteSDP) { [weak self, weak box] err in
                guard err == nil else { return }
                DispatchQueue.main.async { [weak self, weak box] in
                    guard let self = self,
                          let box = box,
                          self.liveEpoch == capturedEpoch,
                          self.liveStageRevision == capturedRevision,
                          self.livePeerConnections[peerId] === box else { return }
                    self.drainPendingLiveCandidates(for: peerId, on: box)
                    guard sdpType == .offer else { return }
                    let constraints = self.answerConstraints(for: peerId)
                    box.pc.answer(for: constraints) { [weak self, weak box] answer, ansErr in
                        guard let answer = answer, ansErr == nil else { return }
                        DispatchQueue.main.async { [weak self, weak box] in
                            guard let self = self,
                                  let box = box,
                                  self.liveEpoch == capturedEpoch,
                                  self.liveStageRevision == capturedRevision,
                                  self.livePeerConnections[peerId] === box else { return }
                            box.pc.setLocalDescription(answer) { [weak self, weak box] setErr in
                                guard setErr == nil else { return }
                                DispatchQueue.main.async { [weak self, weak box] in
                                    guard let self = self,
                                          let box = box,
                                          self.liveEpoch == capturedEpoch,
                                          self.liveStageRevision == capturedRevision,
                                          self.livePeerConnections[peerId] === box else { return }
                                    let descPayload: [String: Any] = [
                                        "type": Self.sdpTypeString(answer.type),
                                        "sdp": answer.sdp
                                    ]
                                    self.sendLiveSignal(
                                        to: peerId,
                                        revision: capturedRevision,
                                        key: "description",
                                        payload: descPayload
                                    )
                                }
                            }
                        }
                    }
                }
            }
        } else if let cand = signal["candidate"] as? [String: Any],
                  let sdp = cand["candidate"] as? String {
            guard !sdp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let sdpMid = cand["sdpMid"] as? String
            let sdpMLineIndex: Int32 = (cand["sdpMLineIndex"] as? NSNumber)?.int32Value
                ?? (cand["sdpMLineIndex"] as? Int).map(Int32.init)
                ?? (cand["sdpMLineIndex"] as? String).flatMap(Int32.init)
                ?? 0
            let ice = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            if box.pc.remoteDescription != nil {
                box.pc.add(ice) { _ in }
            } else {
                var queued = pendingLiveIceCandidates[peerId] ?? []
                if queued.count < 100 {
                    queued.append(ice)
                    pendingLiveIceCandidates[peerId] = queued
                }
            }
        }
    }

    @MainActor
    func handleLivePeerLeft(peerId: String) {
        guard !peerId.isEmpty else { return }
        removeLivePeerConnection(peerId: peerId)
        livePeerPublishesMap.removeValue(forKey: peerId)
        if liveRemoteVideoTracksByPeer.removeValue(forKey: peerId) != nil {
            refreshPrimaryLiveRemoteVideoTrack()
        }
    }

    @MainActor
    func stopLiveSession() {
        liveEpoch += 1
        stopLiveLocalMedia()
        liveRoomId = ""
        liveStageRevision = 0
        liveTransport = "mesh"
        liveSelfId = ""
        liveHostPeerId = ""
        liveStageMode = "video"
        liveRole = "viewer"
        liveConnectionError = nil
        for (_, box) in livePeerConnections {
            box.pc.close()
        }
        livePeerConnections.removeAll()
        livePeerPublishesMap.removeAll()
        pendingLiveIceCandidates.removeAll()
        liveRemoteVideoTracksByPeer.removeAll()
        liveRemoteVideoTrack = nil
        MediaPermissionHandler.shared.configureAudioSessionForMedia()
    }

    @MainActor
    private func resetLivePeerConnections() {
        liveEpoch += 1
        for (_, box) in livePeerConnections {
            box.pc.close()
        }
        livePeerConnections.removeAll()
        livePeerPublishesMap.removeAll()
        pendingLiveIceCandidates.removeAll()
        liveRemoteVideoTracksByPeer.removeAll()
        liveRemoteVideoTrack = nil
    }

    @MainActor
    private func removeLivePeerConnection(peerId: String) {
        pendingLiveIceCandidates.removeValue(forKey: peerId)
        if let stale = livePeerConnections.removeValue(forKey: peerId) {
            stale.pc.close()
        }
    }

    @MainActor
    private func drainPendingLiveCandidates(for peerId: String, on box: PeerConnectionBox) {
        guard let queued = pendingLiveIceCandidates.removeValue(forKey: peerId),
              !queued.isEmpty else { return }
        for ice in queued {
            box.pc.add(ice) { _ in }
        }
    }

    @MainActor
    private func refreshPrimaryLiveRemoteVideoTrack() {
        if !liveHostPeerId.isEmpty, let hostTrack = liveRemoteVideoTracksByPeer[liveHostPeerId] {
            liveRemoteVideoTrack = hostTrack
            return
        }
        if let current = liveRemoteVideoTrack,
           liveRemoteVideoTracksByPeer.values.contains(where: { $0 === current }) {
            return
        }
        liveRemoteVideoTrack = liveRemoteVideoTracksByPeer.values.first
    }

    @MainActor
    private func sendLiveSignal(to peerId: String, revision: Int, key: String, payload: [String: Any]) {
        let envelope = LiveStageSignalingContract.signalEnvelope(
            to: peerId,
            revision: revision,
            key: key,
            payload: payload
        )
        NativeSocketClient.shared.sendJSON(envelope)
    }

    private func shouldAttachLocalMedia(for peerId: String) -> Bool {
        let isPublisherRole = (liveRole == "host" || liveRole == "guest")
        guard isPublisherRole else { return false }
        if liveTransport == "sfu" {
            return peerId == "@sfu"
        }
        return true
    }

    private func offerConstraints(for peerId: String, peerPublishes: Bool) -> RTCMediaConstraints {
        if liveTransport == "sfu" && peerId == "@sfu" {
            return RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "false", "OfferToReceiveVideo": "false"],
                optionalConstraints: nil
            )
        }
        let receive = peerPublishes ? "true" : "false"
        return RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": receive, "OfferToReceiveVideo": receive],
            optionalConstraints: nil
        )
    }

    private func answerConstraints(for peerId: String) -> RTCMediaConstraints {
        if liveTransport == "sfu" {
            return RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
                optionalConstraints: nil
            )
        }
        let expectsRemoteMedia = livePeerPublishesMap[peerId] ?? (liveRole == "viewer")
        let receive = expectsRemoteMedia ? "true" : "false"
        return RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": receive, "OfferToReceiveVideo": receive],
            optionalConstraints: nil
        )
    }

    private func createLivePeerBox(peerId: String, roomId: String, epoch: Int, revision: Int) -> PeerConnectionBox {
        let config = RTCConfiguration()
        config.iceServers = cachedIceServers
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        let box = PeerConnectionBox(
            peerId: peerId,
            roomId: roomId,
            epoch: epoch,
            revision: revision,
            onRemoteVideo: { [weak self] remotePeerId, boxEpoch, videoTrack in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          self.liveEpoch == boxEpoch,
                          remotePeerId != "@sfu" else { return }
                    self.liveConnectionError = nil
                    self.liveRemoteVideoTracksByPeer[remotePeerId] = videoTrack
                    self.refreshPrimaryLiveRemoteVideoTrack()
                }
            },
            onIceCandidate: { [weak self] sourceBox, candidate in
                DispatchQueue.main.async { [weak self, weak sourceBox] in
                    guard let self = self,
                          let sourceBox = sourceBox,
                          !self.liveRoomId.isEmpty,
                          self.liveRoomId == sourceBox.roomId,
                          self.liveEpoch == sourceBox.epoch,
                          self.liveStageRevision == sourceBox.revision,
                          self.livePeerConnections[sourceBox.peerId] === sourceBox else { return }
                    let candPayload: [String: Any] = [
                        "candidate": candidate.sdp,
                        "sdpMid": candidate.sdpMid ?? "0",
                        "sdpMLineIndex": candidate.sdpMLineIndex
                    ]
                    self.sendLiveSignal(
                        to: sourceBox.peerId,
                        revision: sourceBox.revision,
                        key: "candidate",
                        payload: candPayload
                    )
                }
            },
            onIceStateChange: { [weak self] sourceBox, pc, newState in
                DispatchQueue.main.async { [weak self, weak sourceBox] in
                    guard let self = self,
                          let sourceBox = sourceBox,
                          self.liveEpoch == sourceBox.epoch,
                          self.livePeerConnections[sourceBox.peerId] === sourceBox,
                          sourceBox.pc === pc else { return }
                    if newState == .connected || newState == .completed {
                        if self.liveRole == "viewer" || sourceBox.peerId == "@sfu" || sourceBox.peerId == self.liveHostPeerId {
                            self.liveConnectionError = nil
                        }
                        return
                    }
                    guard newState == .failed || newState == .closed else { return }
                    self.livePeerConnections.removeValue(forKey: sourceBox.peerId)
                    self.pendingLiveIceCandidates.removeValue(forKey: sourceBox.peerId)
                    sourceBox.pc.close()
                    if self.liveRemoteVideoTracksByPeer.removeValue(forKey: sourceBox.peerId) != nil {
                        self.refreshPrimaryLiveRemoteVideoTrack()
                    }
                    if newState == .failed,
                       (sourceBox.peerId == "@sfu" || self.liveRole == "viewer" || sourceBox.peerId == self.liveHostPeerId) {
                        self.liveConnectionError = "Mất kết nối luồng video Live (ICE failed)."
                    }
                }
            }
        )
        let pc = factory.peerConnection(with: config, constraints: constraints, delegate: box)!
        box.pc = pc
        if shouldAttachLocalMedia(for: peerId) {
            if let aTrack = liveAudioTrack {
                pc.add(aTrack, streamIds: ["kinnect_live"])
            }
            if liveStageMode != "audio", let vTrack = liveLocalVideoTrack {
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
            DispatchQueue.main.async {
                guard self.callPeerConnection === peerConnection else { return }
                self.remoteVideoTrack = videoTrack
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            guard self.callPeerConnection === peerConnection else { return }
            if newState == .connected || newState == .completed {
                if var current = self.activeCall {
                    CallAudioFeedback.shared.stop()
                    if current.state != .connected && !current.isIncoming {
                        CallKitManager.shared.reportCallConnected(callId: current.callId)
                    }
                    current.state = .connected
                    self.activeCall = current
                }
            } else if newState == .failed || newState == .closed {
                self.endOrRejectCurrentCall(sendSocket: false)
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
            guard self.callPeerConnection === peerConnection,
                  let callId = self.activeCall?.callId else { return }
            NativeSocketClient.shared.sendJSON([
                "type": "call-signal",
                "callId": callId,
                "candidate": [
                    "candidate": candidate.sdp,
                    "sdpMid": candidate.sdpMid ?? "0",
                    "sdpMLineIndex": candidate.sdpMLineIndex
                ],
                "signal": [
                    "candidate": [
                        "candidate": candidate.sdp,
                        "sdpMid": candidate.sdpMid ?? "0",
                        "sdpMLineIndex": candidate.sdpMLineIndex
                    ]
                ]
            ])
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            DispatchQueue.main.async {
                guard self.callPeerConnection === peerConnection else { return }
                self.remoteVideoTrack = track
            }
        } else if let track = mediaStreams.first?.videoTracks.first {
            DispatchQueue.main.async {
                guard self.callPeerConnection === peerConnection else { return }
                self.remoteVideoTrack = track
            }
        }
    }
}

// MARK: - Live Stage Protocol Contract & PeerConnection Box

struct LiveStagePeerDescriptor: Equatable {
    let id: String
    let publishes: Bool
    let offer: Bool
}

enum LiveStageSignalingContract {
    static func normalizeTransport(_ value: String?) -> String {
        let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clean == "sfu" ? "sfu" : "mesh"
    }

    static func normalizeRole(_ value: String?) -> String {
        let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case "host", "guest", "viewer":
            return clean
        default:
            return "viewer"
        }
    }

    static func normalizeMode(_ value: String?) -> String {
        let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clean == "audio" ? "audio" : "video"
    }

    static func parsePeers(_ rawPeers: [[String: Any]]) -> [LiveStagePeerDescriptor] {
        var result: [LiveStagePeerDescriptor] = []
        var seen = Set<String>()
        for entry in rawPeers {
            guard let id = entry["id"] as? String, !id.isEmpty, seen.insert(id).inserted else { continue }
            let publishes = (entry["publishes"] as? Bool) ?? false
            let offer = (entry["offer"] as? Bool) ?? false
            result.append(LiveStagePeerDescriptor(id: id, publishes: publishes, offer: offer))
        }
        return result
    }

    static func resolveHostPeerId(participants: [[String: Any]]) -> String {
        for item in participants {
            if (item["role"] as? String) == "host", let id = item["id"] as? String, !id.isEmpty {
                return id
            }
        }
        return ""
    }

    static func isLayoutOnlyStageUpdate(
        currentRoomId: String,
        incomingRoomId: String,
        currentTransport: String,
        incomingTransport: String,
        currentRevision: Int,
        incomingRevision: Int,
        currentRole: String,
        incomingRole: String,
        currentMode: String,
        incomingMode: String
    ) -> Bool {
        currentRevision > 0
            && incomingRevision == currentRevision
            && incomingRoomId == currentRoomId
            && incomingTransport == currentTransport
            && incomingRole == currentRole
            && incomingMode == currentMode
    }

    static func isValidInboundSignal(
        msgRoom: String?,
        msgRevision: Int,
        currentRoomId: String,
        currentRevision: Int,
        usesStage: Bool
    ) -> Bool {
        if let msgRoom, !msgRoom.isEmpty, !currentRoomId.isEmpty, msgRoom != currentRoomId {
            return false
        }
        if usesStage {
            guard !currentRoomId.isEmpty, currentRevision > 0 else { return false }
            return msgRevision == currentRevision
        }
        return msgRevision == 0 || msgRevision == currentRevision
    }

    static func signalEnvelope(to peerId: String, revision: Int, key: String, payload: [String: Any]) -> [String: Any] {
        var body: [String: Any] = [
            "type": "signal",
            "to": peerId,
            key: payload,
            "signal": [key: payload]
        ]
        if revision > 0 {
            body["revision"] = revision
        }
        return body
    }
}

private final class PeerConnectionBox: NSObject, RTCPeerConnectionDelegate {
    let peerId: String
    let roomId: String
    let epoch: Int
    let revision: Int
    var pc: RTCPeerConnection!
    let onRemoteVideo: (String, Int, RTCVideoTrack) -> Void
    let onIceCandidate: (PeerConnectionBox, RTCIceCandidate) -> Void
    let onIceStateChange: (PeerConnectionBox, RTCPeerConnection, RTCIceConnectionState) -> Void

    init(
        peerId: String,
        roomId: String,
        epoch: Int,
        revision: Int,
        onRemoteVideo: @escaping (String, Int, RTCVideoTrack) -> Void,
        onIceCandidate: @escaping (PeerConnectionBox, RTCIceCandidate) -> Void,
        onIceStateChange: @escaping (PeerConnectionBox, RTCPeerConnection, RTCIceConnectionState) -> Void
    ) {
        self.peerId = peerId
        self.roomId = roomId
        self.epoch = epoch
        self.revision = revision
        self.onRemoteVideo = onRemoteVideo
        self.onIceCandidate = onIceCandidate
        self.onIceStateChange = onIceStateChange
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let v = stream.videoTracks.first {
            onRemoteVideo(peerId, epoch, v)
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        onIceStateChange(self, peerConnection, newState)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onIceCandidate(self, candidate)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let v = rtpReceiver.track as? RTCVideoTrack {
            onRemoteVideo(peerId, epoch, v)
        } else if let v = mediaStreams.first?.videoTracks.first {
            onRemoteVideo(peerId, epoch, v)
        }
    }
}

