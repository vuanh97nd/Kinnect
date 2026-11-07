import AVFoundation
import CallKit
import Foundation
import UIKit
import UserNotifications

final class CallKitManager: NSObject, CXProviderDelegate {
    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var callUUIDs: [String: UUID] = [:]
    private var callIDs: [UUID: String] = [:]

    var onAnswerCall: ((String) -> Void)?
    var onEndCall: ((String) -> Void)?

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

    func reportIncomingCall(callId: String, callerName: String, isVideo: Bool) {
        guard !callId.isEmpty else { return }
        if callUUIDs[callId] != nil {
            return
        }

        let uuid = UUID()
        callUUIDs[callId] = uuid
        callIDs[uuid] = callId

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
                self?.postFallbackCallNotification(callId: callId, callerName: callerName, isVideo: isVideo)
            }
        }
    }

    func reportCallConnected(callId: String) {
        guard let uuid = callUUIDs[callId] else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func reportCallEnded(callId: String, reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = callUUIDs.removeValue(forKey: callId) else { return }
        callIDs.removeValue(forKey: uuid)
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call-\(callId)"])
    }

    func endAllCalls() {
        for (callId, uuid) in callUUIDs {
            provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call-\(callId)"])
        }
        callUUIDs.removeAll()
        callIDs.removeAll()
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
        callUUIDs.removeAll()
        callIDs.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MediaPermissionHandler.shared.configureAudioSessionForCall()
        if let callId = callIDs[action.callUUID] {
            DispatchQueue.main.async { [weak self] in
                self?.onAnswerCall?(callId)
            }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if let callId = callIDs.removeValue(forKey: action.callUUID) {
            callUUIDs.removeValue(forKey: callId)
            DispatchQueue.main.async { [weak self] in
                self?.onEndCall?(callId)
            }
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        MediaPermissionHandler.shared.configureAudioSessionForCall()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MediaPermissionHandler.shared.configureAudioSessionForMedia()
    }
}
