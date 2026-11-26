import AVFoundation
import CallKit
import Foundation
import UIKit
import UserNotifications
import WebRTC

final class CallKitManager: NSObject, CXProviderDelegate {
    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private let lock = NSLock()
    private var callUUIDs: [String: UUID] = [:]
    private var callIDs: [UUID: String] = [:]
    private var callKitAudioActive: Bool = false

    var onAnswerCall: ((String) -> Void)?
    var onEndCall: ((String) -> Void)?
    var onSetMuted: ((String, Bool) -> Void)?

    var isAudioSessionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return callKitAudioActive
    }

    func hasCallKitSession(callId: String) -> Bool {
        guard !callId.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return callUUIDs[callId] != nil
    }

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = true

        self.provider = CXProvider(configuration: config)
        super.init()
        self.provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(
        callId: String,
        callerName: String,
        isVideo: Bool,
        fromVoIPPush: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = isVideo
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false
        update.supportsDTMF = false

        guard !callId.isEmpty else {
            if fromVoIPPush {
                let tempUUID = UUID()
                provider.reportNewIncomingCall(with: tempUUID, update: update) { [weak self] _ in
                    self?.provider.reportCall(with: tempUUID, endedAt: Date(), reason: .answeredElsewhere)
                    completion?()
                }
            } else {
                completion?()
            }
            return
        }
        lock.lock()
        if callUUIDs[callId] != nil {
            lock.unlock()
            if fromVoIPPush {
                let tempUUID = UUID()
                provider.reportNewIncomingCall(with: tempUUID, update: update) { [weak self] _ in
                    self?.provider.reportCall(with: tempUUID, endedAt: Date(), reason: .answeredElsewhere)
                    completion?()
                }
            } else {
                completion?()
            }
            return
        }

        let uuid = UUID()
        callUUIDs[callId] = uuid
        callIDs[uuid] = callId
        lock.unlock()

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                print("[KinnectCallKit] Failed to report incoming call: \(error)")
                if let self {
                    self.lock.lock()
                    if self.callUUIDs[callId] == uuid {
                        self.callUUIDs.removeValue(forKey: callId)
                        self.callIDs.removeValue(forKey: uuid)
                    }
                    self.lock.unlock()
                    self.postFallbackCallNotification(callId: callId, callerName: callerName, isVideo: isVideo)
                }
            }
            completion?()
        }
    }

    func startOutgoingCall(callId: String, targetName: String, isVideo: Bool) {
        guard !callId.isEmpty else { return }
        lock.lock()
        let uuid = callUUIDs[callId] ?? UUID()
        callUUIDs[callId] = uuid
        callIDs[uuid] = callId
        lock.unlock()

        let handle = CXHandle(type: .generic, value: targetName)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = isVideo
        let transaction = CXTransaction(action: startAction)
        callController.request(transaction) { [weak self] error in
            guard let self else { return }
            if let error = error {
                print("[KinnectCallKit] Start outgoing call transaction failed: \(error.localizedDescription)")
                var shouldNotify = false
                self.lock.lock()
                if self.callUUIDs[callId] == uuid {
                    self.callUUIDs.removeValue(forKey: callId)
                    self.callIDs.removeValue(forKey: uuid)
                    shouldNotify = true
                }
                self.lock.unlock()
                if shouldNotify {
                    Task { @MainActor [weak self] in
                        self?.onEndCall?(callId)
                    }
                }
            } else {
                self.provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
            }
        }
    }

    func remapCallId(from previous: String, to canonical: String) {
        guard previous != canonical else { return }
        lock.lock()
        if let uuid = callUUIDs.removeValue(forKey: previous) {
            callUUIDs[canonical] = uuid
            callIDs[uuid] = canonical
        }
        lock.unlock()
    }

    func reportCallConnected(callId: String) {
        lock.lock()
        let uuid = callUUIDs[callId]
        lock.unlock()
        guard let uuid else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func reportCallEnded(callId: String, reason: CXCallEndedReason = .remoteEnded) {
        lock.lock()
        let uuid = callUUIDs.removeValue(forKey: callId)
        if let uuid { callIDs.removeValue(forKey: uuid) }
        lock.unlock()
        guard let uuid else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call-\(callId)"])
    }

    func requestAnswerCall(callId: String) {
        lock.lock()
        let uuid = callUUIDs[callId]
        lock.unlock()
        guard let uuid else {
            Task { @MainActor in
                await NativeWebRTCManager.shared.acceptIncomingCall(callId: callId, activateAudioDirectly: true)
            }
            return
        }
        let answerAction = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: answerAction)
        callController.request(transaction) { error in
            if error != nil {
                Task { @MainActor in
                    await NativeWebRTCManager.shared.acceptIncomingCall(callId: callId, activateAudioDirectly: true)
                }
            }
        }
    }

    func requestEndCall(callId: String) {
        lock.lock()
        let uuid = callUUIDs[callId]
        lock.unlock()
        guard let uuid else { return }
        let endAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endAction)
        callController.request(transaction) { [weak self] error in
            if error != nil {
                self?.reportCallEnded(callId: callId, reason: .remoteEnded)
            }
        }
    }

    func endAllCalls() {
        lock.lock()
        let snapshot = callUUIDs
        callUUIDs.removeAll()
        callIDs.removeAll()
        lock.unlock()
        for (callId, uuid) in snapshot {
            provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call-\(callId)"])
        }
    }

    private func postFallbackCallNotification(callId: String, callerName: String, isVideo: Bool) {
        let content = UNMutableNotificationContent()
        content.title = callerName
        content.body = isVideo ? "Cuộc gọi video đến trên Kinnect" : "Cuộc gọi thoại đến trên Kinnect"
        content.sound = .default
        content.userInfo = ["callId": callId, "type": "call-incoming"]

        let request = UNNotificationRequest(identifier: "call-\(callId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        lock.lock()
        let endedCallIDs = Array(callUUIDs.keys)
        callUUIDs.removeAll()
        callIDs.removeAll()
        lock.unlock()
        Task { @MainActor [weak self] in
            for callId in endedCallIDs {
                self?.onEndCall?(callId)
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
        lock.lock()
        let callId = callIDs[action.callUUID]
        lock.unlock()
        if let callId {
            Task { @MainActor [weak self] in
                self?.onAnswerCall?(callId)
            }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        lock.lock()
        let callId = callIDs.removeValue(forKey: action.callUUID)
        if let callId { callUUIDs.removeValue(forKey: callId) }
        lock.unlock()
        if let callId {
            Task { @MainActor [weak self] in
                self?.onEndCall?(callId)
            }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        lock.lock()
        let callId = callIDs[action.callUUID]
        lock.unlock()
        if let callId {
            Task { @MainActor [weak self] in
                self?.onSetMuted?(callId, action.isMuted)
            }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        lock.lock()
        callKitAudioActive = true
        lock.unlock()
        // Forward the external activation to WebRTC. Without this, a call
        // answered while locked can retain an interrupted audio device.
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
        Task { @MainActor in
            MediaPermissionHandler.configureAudioSessionForCall(
                speaker: NativeWebRTCManager.shared.isSpeakerOn)
        }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        lock.lock()
        callKitAudioActive = false
        lock.unlock()
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        // CallKit owns deactivation. Do not reactivate a media playback session
        // here while another system call or interruption is taking ownership.
    }
}
