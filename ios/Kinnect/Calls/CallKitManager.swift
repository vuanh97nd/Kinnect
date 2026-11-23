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

    var onAnswerCall: ((String) -> Void)?
    var onEndCall: ((String) -> Void)?
    var onSetMuted: ((String, Bool) -> Void)?

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
        completion: (() -> Void)? = nil
    ) {
        guard !callId.isEmpty else {
            completion?()
            return
        }
        lock.lock()
        if callUUIDs[callId] != nil {
            lock.unlock()
            completion?()
            return
        }

        let uuid = UUID()
        callUUIDs[callId] = uuid
        callIDs[uuid] = callId
        lock.unlock()

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.localizedCallerName = callerName
        update.hasVideo = isVideo
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false
        update.supportsDTMF = false

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
                    DispatchQueue.main.async { [weak self] in
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
        DispatchQueue.main.async { [weak self] in
            for callId in endedCallIDs {
                self?.onEndCall?(callId)
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        DispatchQueue.main.async {
            MediaPermissionHandler.shared.configureAudioSessionForCall(speaker: NativeWebRTCManager.shared.isSpeakerOn)
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MediaPermissionHandler.shared.configureAudioSessionForCall()
        lock.lock()
        let callId = callIDs[action.callUUID]
        lock.unlock()
        if let callId {
            DispatchQueue.main.async { [weak self] in
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
            DispatchQueue.main.async { [weak self] in
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
            DispatchQueue.main.async { [weak self] in
                self?.onSetMuted?(callId, action.isMuted)
            }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // Forward the external activation to WebRTC. Without this, a call
        // answered while locked can retain an interrupted audio device.
        RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
        DispatchQueue.main.async {
            MediaPermissionHandler.shared.configureAudioSessionForCall(
                speaker: NativeWebRTCManager.shared.isSpeakerOn)
        }
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
        // CallKit owns deactivation. Do not reactivate a media playback session
        // here while another system call or interruption is taking ownership.
    }
}
