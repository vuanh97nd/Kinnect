import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appearanceObservers: [NSObjectProtocol] = []

    private func removeAppearanceObservers() {
        for token in appearanceObservers {
            NotificationCenter.default.removeObserver(token)
        }
        appearanceObservers.removeAll()
    }

    private func applyAppearanceStyle() {
        guard let window else { return }
        #if DEBUG
        if let overrideLight = UIReviewFixture.overrideLightMode {
            window.overrideUserInterfaceStyle = overrideLight ? .light : .dark
            return
        }
        if UIReviewFixture.forceLightMode {
            window.overrideUserInterfaceStyle = .light
            return
        }
        #endif
        let mode = UserDefaults.standard.string(forKey: "app_appearance_mode") ?? "system"
        switch mode {
        case "light":
            window.overrideUserInterfaceStyle = .light
        case "dark":
            window.overrideUserInterfaceStyle = .dark
        default:
            window.overrideUserInterfaceStyle = .unspecified
        }
    }

    #if DEBUG
    @MainActor
    private func makeFixtureHostingController(for screenName: String) -> UIHostingController<AnyView> {
        let colorScheme: ColorScheme?
        if let overrideLight = UIReviewFixture.overrideLightMode {
            colorScheme = overrideLight ? .light : .dark
        } else {
            colorScheme = UIReviewFixture.forceLightMode ? .light : nil
        }

        let fixtureView = AnyView(
            UIReviewFixture.makeView(for: screenName)
                .environmentObject(AppState.shared)
                .preferredColorScheme(colorScheme)
                .dynamicTypeSize(UIReviewFixture.forceMaxDynamicType ? .xxxLarge : .large)
        )
        let hostingController = UIHostingController(rootView: fixtureView)
        hostingController.view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .light
                ? UIColor(red: 0.96, green: 0.95, blue: 0.98, alpha: 1.0)
                : UIColor(red: 0.05, green: 0.04, blue: 0.11, alpha: 1.0)
        }
        return hostingController
    }
    #endif

    #if DEBUG
    /// `#if DEBUG` deep-link router for single-session cloud simulator captures (`run.cloud`):
    /// `kinnect://ui-review?screen=<slug>&light=<0|1>&dyn=<0|1>`
    /// Compiled out completely in Release builds.
    @MainActor
    @discardableResult
    private func handleDebugUIReviewDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "kinnect",
              (url.host ?? "").lowercased() == "ui-review",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        let queryItems = components.queryItems ?? []
        guard let rawScreen = queryItems.first(where: { $0.name == "screen" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawScreen.isEmpty else {
            return false
        }

        let lightParam = queryItems.first(where: { $0.name == "light" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let dynParam = queryItems.first(where: { $0.name == "dyn" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        UIReviewFixture.overrideScreen = rawScreen
        if let lightParam, !lightParam.isEmpty {
            UIReviewFixture.overrideLightMode = (lightParam == "1" || lightParam == "true")
        } else {
            UIReviewFixture.overrideLightMode = nil
        }
        if let dynParam, !dynParam.isEmpty {
            UIReviewFixture.overrideMaxDynamicType = (dynParam == "1" || dynParam == "true")
        } else {
            UIReviewFixture.overrideMaxDynamicType = false
        }

        UIReviewFixture.prepareRuntimeState(for: rawScreen)

        if let window = self.window {
            applyAppearanceStyle()
            window.rootViewController = makeFixtureHostingController(for: rawScreen)
            window.makeKeyAndVisible()
        }
        return true
    }
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        let handledDebugUIReview: Bool
        #if DEBUG
        if let url = connectionOptions.urlContexts.first?.url {
            handledDebugUIReview = handleDebugUIReviewDeepLink(url)
        } else {
            handledDebugUIReview = false
        }
        #else
        handledDebugUIReview = false
        #endif

        if !handledDebugUIReview {
            #if DEBUG
            // UI Review Fixture Mode: Activated with `--ui-review-screen <screenName>`
            if UIReviewFixture.isEnabled,
               let screenName = UIReviewFixture.activeScreen {
                UIReviewFixture.prepareRuntimeState(for: screenName)
                window.rootViewController = makeFixtureHostingController(for: screenName)
            } else {
                let rootView = RootMainView().environmentObject(AppState.shared)
                let hostingController = UIHostingController(rootView: rootView)
                hostingController.view.backgroundColor = UIColor { trait in
                    trait.userInterfaceStyle == .light
                        ? UIColor(red: 0.96, green: 0.95, blue: 0.98, alpha: 1.0)
                        : UIColor(red: 0.05, green: 0.04, blue: 0.11, alpha: 1.0)
                }
                window.rootViewController = hostingController
            }
            #else
            let rootView = RootMainView().environmentObject(AppState.shared)
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.view.backgroundColor = UIColor { trait in
                trait.userInterfaceStyle == .light
                    ? UIColor(red: 0.96, green: 0.95, blue: 0.98, alpha: 1.0)
                    : UIColor(red: 0.05, green: 0.04, blue: 0.11, alpha: 1.0)
            }
            window.rootViewController = hostingController
            #endif
        }

        applyAppearanceStyle()
        removeAppearanceObservers()
        let defaultsToken = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyAppearanceStyle()
            }
        }
        let appearanceToken = NotificationCenter.default.addObserver(
            forName: .kinnectAppearanceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyAppearanceStyle()
            }
        }
        appearanceObservers = [defaultsToken, appearanceToken]

        window.makeKeyAndVisible()

        if !handledDebugUIReview, let url = connectionOptions.urlContexts.first?.url {
            Task { @MainActor in
                AppState.shared.handleDeepLink(url)
            }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        #if DEBUG
        if handleDebugUIReviewDeepLink(url) {
            return
        }
        #endif
        Task { @MainActor in
            AppState.shared.handleDeepLink(url)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        removeAppearanceObservers()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        applyAppearanceStyle()
        #if DEBUG
        if !UIReviewFixture.isEnabled {
            NativeSocketClient.shared.setAppForeground(true)
        }
        #else
        NativeSocketClient.shared.setAppForeground(true)
        #endif
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        applyAppearanceStyle()
        UIApplication.shared.applicationIconBadgeNumber = 0
        #if DEBUG
        guard !UIReviewFixture.isEnabled else { return }
        #endif
        NativeSocketClient.shared.setAppForeground(true)
        NativeSocketClient.shared.connectWithKeychainSession()
        Task { @MainActor in
            await AppState.shared.refreshGlobalBadges()
            AppState.shared.reportActiveStatus(force: true)
            AppState.shared.startActivityHeartbeat()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        NativeSocketClient.shared.setAppForeground(false)
        AppState.shared.stopActivityHeartbeat()
        // Do NOT use UIBackgroundTask WebSocket keepalive as a substitute for PushKit.
        // Only close the foreground WebSocket when neither a CallKit/WebRTC call nor a Live room is active.
        if NativeWebRTCManager.shared.activeCall == nil
            && AppState.shared.currentLiveRoom == nil
            && !AppState.shared.isCreatingLiveRoom {
            NativeSocketClient.shared.disconnect()
        }
    }
}
