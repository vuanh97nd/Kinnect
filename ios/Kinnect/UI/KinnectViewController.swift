import AVFoundation
import UIKit
import WebKit

final class KinnectViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private let bridge = NativeBridge()
    private let offlineView = OfflineOverlayView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var triedFallback = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
        setupWebView()
        setupOverlays()
        setupCallKitCallbacks()
        MediaPermissionHandler.shared.configureAudioSessionForMedia()
        MediaPermissionHandler.shared.requestNotificationPermission()
        loadKinnect(url: ServerConfig.mainAppURL)
    }

    private func setupWebView() {
        let contentController = WKUserContentController()
        contentController.addUserScript(NativeBridge.bootstrapUserScript)
        contentController.add(bridge, name: NativeBridge.handlerName)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.applicationNameForUserAgent = "KinnectiOS/\(ServerConfig.appVersion) (Build \(ServerConfig.buildNumber))"

        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)

        bridge.viewController = self
        bridge.webView = webView

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupOverlays() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = UIColor(red: 0.43, green: 0.29, blue: 1.0, alpha: 1.0)
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)

        offlineView.translatesAutoresizingMaskIntoConstraints = false
        offlineView.isHidden = true
        offlineView.onRetry = { [weak self] in
            guard let self = self else { return }
            self.offlineView.isHidden = true
            self.triedFallback = false
            self.loadKinnect(url: ServerConfig.mainAppURL)
        }
        view.addSubview(offlineView)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            offlineView.topAnchor.constraint(equalTo: view.topAnchor),
            offlineView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            offlineView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            offlineView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupCallKitCallbacks() {
        CallKitManager.shared.onAnswerCall = { [weak self] callId in
            guard let self = self else { return }
            let js = """
            (function() {
                var btn = document.querySelector('[data-do="call-answer"]');
                if (btn) { btn.click(); }
            })();
            """
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }

        CallKitManager.shared.onEndCall = { [weak self] callId in
            guard let self = self else { return }
            let js = """
            (function() {
                var btn = document.querySelector('[data-do="call-end"]');
                if (btn) { btn.click(); }
            })();
            """
            self.webView.evaluateJavaScript(js, completionHandler: nil)
            NativeSocketClient.shared.sendJSON(["type": "call-decline", "callId": callId])
        }
    }

    func loadKinnect(url: URL) {
        offlineView.isHidden = true
        activityIndicator.startAnimating()
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        webView.load(request)
    }

    func syncBackgroundSocket() {
        NativeSocketClient.shared.syncCookiesAndConnect(from: webView.configuration.websiteDataStore.httpCookieStore)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        offlineView.isHidden = true
        syncBackgroundSocket()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    private func handleLoadError(_ error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }

        if !triedFallback, let fallbackURL = URL(string: ServerConfig.fallbackOrigin + "/v2.html") {
            triedFallback = true
            loadKinnect(url: fallbackURL)
            return
        }

        activityIndicator.stopAnimating()
        offlineView.isHidden = false
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "tel" || scheme == "mailto" {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate (WebRTC Camera & Microphone auto-grant + Dialogs)

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        MediaPermissionHandler.shared.configureAudioSessionForCall()
        MediaPermissionHandler.shared.requestCameraAndMicrophoneIfNeeded { _ in
            decisionHandler(.grant)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: "Kinnect", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Đóng", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: "Kinnect", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "Đồng ý", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }
}
