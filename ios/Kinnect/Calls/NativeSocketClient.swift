import Foundation
import UIKit
import UserNotifications

final class NativeSocketClient: NSObject, URLSessionWebSocketDelegate {
    static let shared = NativeSocketClient()

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private(set) var isConnected = false
    private var shouldReconnect = false

    var onEvent: (([String: Any]) -> Void)?

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func connectWithKeychainSession() {
        let origin = KinnectAPIClient.shared.baseURL
        KeychainStore.shared.syncToHTTPCookieStorage(origin: origin)
        let cookieHeader = KeychainStore.shared.cookieJarHeader(for: origin)
        guard !cookieHeader.isEmpty else {
            disconnect()
            return
        }
        shouldReconnect = true
        if webSocketTask != nil && isConnected {
            return
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        let wsScheme = origin.lowercased().hasPrefix("https://") ? "wss://" : "ws://"
        let cleanHost = origin
            .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(wsScheme)\(cleanHost)/") else { return }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = true
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let task = session?.webSocketTask(with: request)
        self.webSocketTask = task
        task?.resume()
        if let task { receiveNextMessage(task) }
        startPingTimer()
    }

    @MainActor
    func ensureConnected() async -> Bool {
        if isConnected { return true }
        connectWithKeychainSession()
        for _ in 0..<80 {
            if isConnected { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return isConnected
    }

    func disconnect() {
        shouldReconnect = false
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    private func receiveNextMessage(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self, self.webSocketTask === task else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveNextMessage(task)
            case .failure:
                self.handleDisconnection()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        if type == "welcome" {
            isConnected = true
        }

        DispatchQueue.main.async { [weak self] in
            if type == "welcome", let call = NativeWebRTCManager.shared.activeCall,
               call.state == .connecting || call.state == .connected {
                self?.sendJSON(["type": "call-resume", "callId": call.callId])
            }
            self?.onEvent?(json)
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { _ in }
        }
    }

    private func handleDisconnection() {
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask = nil
        guard shouldReconnect,
              UIApplication.shared.applicationState == .active || NativeWebRTCManager.shared.activeCall != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self, self.shouldReconnect, self.webSocketTask == nil else { return }
            self.connectWithKeychainSession()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard self.webSocketTask === webSocketTask else { return }
        isConnected = true
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard self.webSocketTask === webSocketTask else { return }
        handleDisconnection()
    }
}
