import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private weak var rootController: KinnectViewController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        let vc = KinnectViewController()
        self.rootController = vc
        window.rootViewController = vc
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        endBackgroundTask()
        UIApplication.shared.applicationIconBadgeNumber = 0
        rootController?.syncBackgroundSocket()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        rootController?.syncBackgroundSocket()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "KinnectSocketKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
