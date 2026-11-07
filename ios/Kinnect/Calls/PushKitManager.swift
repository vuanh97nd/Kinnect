import Foundation
import PushKit
import UIKit
import UserNotifications

@MainActor
final class PushKitManager: NSObject, ObservableObject, PKPushRegistryDelegate {
    static let shared = PushKitManager()

    @Published private(set) var voipTokenHex: String?
    @Published private(set) var apnsTokenHex: String?
    @Published private(set) var voipRegistrationStatus: String = "Đang kiểm tra PushKit VoIP..."

    private var voipRegistry: PKPushRegistry?

    private override init() {
        super.init()
    }

    func startRegistration() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry

        // Check if VoIP token is already cached by PushKit
        if let tokenData = registry.pushToken(for: .voIP), !tokenData.isEmpty {
            let hex = tokenData.map { String(format: "%02x", $0) }.joined()
            self.voipTokenHex = hex
            self.voipRegistrationStatus = "PushKit VoIP đã kích hoạt (\(hex.prefix(8))...)"
        } else {
            self.voipRegistrationStatus = "Chưa có chứng chỉ VoIP Apple Developer trả phí (chế độ cài thử Sideload chỉ nhận cuộc gọi khi ứng dụng đang mở)"
        }

        // Request standard APNs notification registration if authorized
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.apnsTokenHex = hex
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        // Sideload builds without paid provisioning profiles will naturally fail APNs registration
        print("[KinnectPushKit] Standard APNs registration unavailable: \(error.localizedDescription)")
    }

    // MARK: - PKPushRegistryDelegate

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let hex = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            self.voipTokenHex = hex
            self.voipRegistrationStatus = "PushKit VoIP đã kích hoạt (\(hex.prefix(8))...)"
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        Task { @MainActor in
            self.voipTokenHex = nil
            self.voipRegistrationStatus = "Token PushKit VoIP đã hết hiệu lực"
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        let dict = payload.dictionaryPayload
        let callId = (dict["callId"] as? String) ?? UUID().uuidString
        let callerName = (dict["callerName"] as? String) ?? (dict["name"] as? String) ?? "Cuộc gọi Kinnect"
        let mode = (dict["mode"] as? String) ?? "video"
        let isVideo = (mode != "audio")

        // iOS 13+ strict requirement: reportNewIncomingCall MUST be invoked synchronously before completion()
        CallKitManager.shared.reportIncomingCall(
            callId: callId,
            callerName: callerName,
            isVideo: isVideo,
            completion: completion
        )
    }
}

