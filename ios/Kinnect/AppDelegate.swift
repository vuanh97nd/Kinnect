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
        MediaPermissionHandler.shared.configureAudioSessionForMedia()
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
        if data["notificationId"] != nil {
            NotificationCenter.default.post(name: .kinnectNavigateRoute, object: "notifications")
        }
        completionHandler()
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
