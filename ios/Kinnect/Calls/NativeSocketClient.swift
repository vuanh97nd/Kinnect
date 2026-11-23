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
    private var activeSocketOrigin: String = ""
    private var activeCookieHeader: String = ""
    private var reconnectAttempt: Int = 0
    private var blockedSessionSignature: String? = nil

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
        let signature = "\(origin)|\(cookieHeader)"
        if blockedSessionSignature == signature {
            return
        }
        blockedSessionSignature = nil
        shouldReconnect = true
        if let existing = webSocketTask,
           existing.state == .running,
           activeSocketOrigin == origin,
           activeCookieHeader == cookieHeader {
            return
        }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        activeSocketOrigin = origin
        activeCookieHeader = cookieHeader

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
        reconnectAttempt = 0
        blockedSessionSignature = nil
        activeSocketOrigin = ""
        activeCookieHeader = ""
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
            reconnectAttempt = 0
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
            guard let self, let task = self.webSocketTask else { return }
            task.sendPing { [weak self] error in
                if error != nil {
                    Task { @MainActor [weak self] in
                        guard let self, self.webSocketTask === task else { return }
                        self.handleDisconnection()
                    }
                }
            }
        }
    }

    private func handleDisconnection() {
        let failedTask = webSocketTask
        isConnected = false
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask = nil
        if let http = failedTask?.response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            blockedSessionSignature = "\(activeSocketOrigin)|\(activeCookieHeader)"
            shouldReconnect = false
            return
        }
        guard shouldReconnect,
              UIApplication.shared.applicationState == .active || NativeWebRTCManager.shared.activeCall != nil else { return }
        let schedule: [TimeInterval] = [2.5, 5.0, 10.0, 20.0, 30.0]
        let delay = schedule[min(reconnectAttempt, schedule.count - 1)]
        reconnectAttempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
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

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard self.webSocketTask === task, error != nil else { return }
        handleDisconnection()
    }
}
