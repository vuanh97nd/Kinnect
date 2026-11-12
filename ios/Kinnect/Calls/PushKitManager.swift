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
        // A VoIP push may launch the app without creating a SwiftUI scene.
        // Install answer/end and websocket callbacks before CallKit can deliver actions.
        _ = AppState.shared
        guard voipRegistry == nil else {
            uploadStoredTokens()
            return
        }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.voipRegistry = registry

        // Check if VoIP token is already cached by PushKit
        if let tokenData = registry.pushToken(for: .voIP), !tokenData.isEmpty {
            let hex = tokenData.map { String(format: "%02x", $0) }.joined()
            self.voipTokenHex = hex
            self.voipRegistrationStatus = "Đã nhận token cuộc gọi Apple, đang đăng ký với máy chủ..."
            self.uploadToken(kind: "voip", token: hex)
        } else {
            self.voipRegistrationStatus = "Đang chờ Apple cấp token cuộc gọi. Bản cài đặt cần quyền Push Notifications hợp lệ."
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
        uploadToken(kind: "apns", token: hex)
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
            self.voipRegistrationStatus = "Đã nhận token cuộc gọi Apple, đang đăng ký với máy chủ..."
            self.uploadToken(kind: "voip", token: hex)
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        Task { @MainActor in
            let previous = self.voipTokenHex
            self.voipTokenHex = nil
            self.voipRegistrationStatus = "Token PushKit VoIP đã hết hiệu lực"
            if let previous {
                self.deleteToken(kind: "voip", token: previous)
            }
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

        // Keep callbacks available even on a cold background launch.
        // Report to CallKit immediately; reconnect signalling in parallel, without
        // waiting for network access before presenting the system incoming UI.
        DispatchQueue.main.async {
            _ = AppState.shared
            NativeSocketClient.shared.connectWithKeychainSession()
        }
        // iOS 13+ strict requirement: reportNewIncomingCall MUST be invoked synchronously before completion()
        CallKitManager.shared.reportIncomingCall(
            callId: callId,
            callerName: callerName,
            isVideo: isVideo,
            completion: completion
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            let current = NativeWebRTCManager.shared.activeCall
            if current == nil || (current?.callId == callId && current?.state == .ringingIncoming) {
                CallKitManager.shared.reportCallEnded(callId: callId, reason: .unanswered)
            }
        }
    }

    func unregisterStoredTokens() async {
        for (kind, token) in [("voip", voipTokenHex), ("apns", apnsTokenHex)] {
            if let token {
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/devices/push", method: "DELETE", body: ["kind": kind, "token": token])
            }
        }
    }

    func uploadStoredTokens() {
        if let voipTokenHex {
            uploadToken(kind: "voip", token: voipTokenHex)
        }
        if let apnsTokenHex {
            uploadToken(kind: "apns", token: apnsTokenHex)
        }
    }

    private func uploadToken(kind: String, token: String) {
        Task {
            do {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/devices/push",
                    method: "POST",
                    body: ["kind": kind, "token": token]
                )
                if kind == "voip", self.voipTokenHex == token {
                    self.voipRegistrationStatus = "Đã đăng ký thiết bị nhận cuộc gọi với máy chủ."
                }
            } catch {
                if kind == "voip", self.voipTokenHex == token {
                    self.voipRegistrationStatus = "Chưa đăng ký được thiết bị nhận cuộc gọi. Đang chờ kết nối máy chủ."
                }
            }
        }
    }

    private func deleteToken(kind: String, token: String) {
        Task {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/devices/push",
                method: "DELETE",
                body: ["kind": kind, "token": token]
            )
        }
    }
}

