import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        let hostingController = UIHostingController(rootView: RootMainView())
        hostingController.view.backgroundColor = UIColor(red: 0.05, green: 0.04, blue: 0.11, alpha: 1.0)
        window.rootViewController = hostingController
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        UIApplication.shared.applicationIconBadgeNumber = 0
        NativeSocketClient.shared.connectWithKeychainSession()
        Task { @MainActor in
            await AppState.shared.refreshGlobalBadges()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Do NOT use UIBackgroundTask WebSocket keepalive as a substitute for PushKit.
        // If there is no active CallKit/WebRTC call in progress, allow the foreground WebSocket to close cleanly.
        if NativeWebRTCManager.shared.activeCall == nil {
            NativeSocketClient.shared.disconnect()
        }
    }
}
