import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        _ = CallKitManager.shared
        _ = StoreKitManager.shared
        MediaPermissionHandler.shared.configureAudioSessionForMedia()
        if let remotePayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            routeNotificationPayload(remotePayload)
        }
        Task { @MainActor in
            PushKitManager.shared.startRegistration()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushKitManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushKitManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let kind = (notification.request.content.userInfo["kind"] as? String)
            ?? (notification.request.content.userInfo["type"] as? String)
            ?? ""
        if KinnectNotificationPrefs.allowsPresentation(kind: kind) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let data = response.notification.request.content.userInfo
        routeNotificationPayload(data)
        completionHandler()
    }

    private func routeNotificationPayload(_ data: [AnyHashable: Any]) {
        func stringValue(_ keys: [String]) -> String {
            for k in keys {
                if let s = data[k] as? String, !s.isEmpty { return s }
                if let n = data[k] as? NSNumber { return n.stringValue }
            }
            return ""
        }

        let kind = stringValue(["kind", "type"]).lowercased()
        let actorId = stringValue(["actorId", "actor_id", "senderId", "fromUserId"])
        let ref = stringValue(["ref", "targetId"])
        let conversationId = stringValue(["conversationId", "conversation_id", "groupId", "chatId"])
        let postId = stringValue(["postId", "post_id"])
        let shortId = stringValue(["shortId", "short_id"])
        let roomId = stringValue(["roomId", "room_id", "room"])
        let notificationId = stringValue(["notificationId", "notification_id"])
        let targetKind = stringValue(["targetKind", "target_kind"]).lowercased()

        var payload: [String: String] = [:]
        if !kind.isEmpty { payload["kind"] = kind }
        if !actorId.isEmpty { payload["actorId"] = actorId }
        if !ref.isEmpty { payload["ref"] = ref }
        if !conversationId.isEmpty { payload["conversationId"] = conversationId }
        if !postId.isEmpty { payload["postId"] = postId }
        if !shortId.isEmpty { payload["shortId"] = shortId }
        if !roomId.isEmpty { payload["roomId"] = roomId }
        if !notificationId.isEmpty { payload["notificationId"] = notificationId }
        if !targetKind.isEmpty { payload["targetKind"] = targetKind }

        let route: String
        let targetRef: String
        if kind == "call-incoming" || kind == "call-ended" {
            return
        } else if kind == "message" || kind == "group_message" || kind == "direct-message" || kind == "missed_call" || !conversationId.isEmpty {
            route = "messages"
            if !conversationId.isEmpty {
                targetRef = conversationId
            } else if kind == "missed_call" {
                targetRef = !actorId.isEmpty ? actorId : ref
            } else {
                targetRef = !ref.isEmpty ? ref : actorId
            }
        } else if kind == "friend_request" || kind == "friend_accept" || kind == "friend_accepted" || kind == "follow" {
            route = "friends"
            targetRef = !actorId.isEmpty ? actorId : ref
        } else if kind == "live" || !roomId.isEmpty {
            route = "live"
            targetRef = !roomId.isEmpty ? roomId : ref
        } else if kind == "short" || kind == "short_comment" || kind == "short_like" || (kind == "comment_reply" && targetKind == "short") || !shortId.isEmpty {
            route = "shorts"
            targetRef = !shortId.isEmpty ? shortId : ref
        } else if !postId.isEmpty || kind == "post" || kind == "comment" || kind == "comment_reply" || kind == "like" || kind == "share" || kind == "mention" {
            route = "feed"
            targetRef = !postId.isEmpty ? postId : ref
        } else if !notificationId.isEmpty || !kind.isEmpty {
            route = "notifications"
            targetRef = !ref.isEmpty ? ref : notificationId
        } else {
            return
        }

        Task { @MainActor in
            AppState.shared.enqueuePushNavigation(route: route, ref: targetRef, payload: payload)
        }
    }
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if userInfo["type"] as? String == "call-ended", let callId = userInfo["callId"] as? String {
            Task { @MainActor in
                let current = NativeWebRTCManager.shared.activeCall
                let reason = userInfo["reason"] as? String ?? ""
                // An answered notification also reaches the device answering the call.
                // Only dismiss another device that is still showing the incoming ring.
                if reason == "answered", current?.callId == callId,
                   current?.state == .connecting || current?.state == .connected { return }
                if current?.callId == callId {
                    NativeWebRTCManager.shared.endOrRejectCurrentCall(sendSocket: false)
                } else {
                    CallKitManager.shared.reportCallEnded(callId: callId)
                }
            }
        }
        completionHandler(.newData)
    }

}
