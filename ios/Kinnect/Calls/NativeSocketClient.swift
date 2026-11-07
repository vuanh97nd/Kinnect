import Foundation
import UIKit
import UserNotifications
import WebKit

final class NativeSocketClient: NSObject, URLSessionWebSocketDelegate {
    static let shared = NativeSocketClient()

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var cookieHeader: String = ""
    private var isConnected = false
    private var shouldReconnect = false

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func syncCookiesAndConnect(from cookieStore: WKHTTPCookieStore) {
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            let relevant = cookies.filter {
                $0.domain.contains("kinnect") && ($0.name == "kinnect_session" || $0.name == "kinnect_device")
            }
            guard !relevant.isEmpty else {
                self.disconnect()
                return
            }
            self.cookieHeader = relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            self.shouldReconnect = true
            if !self.isConnected {
                self.connect()
            }
        }
    }

    func connect() {
        guard !cookieHeader.isEmpty, webSocketTask == nil else { return }
        var request = URLRequest(url: ServerConfig.webSocketURL)
        request.setValue(ServerConfig.currentOrigin, forHTTPHeaderField: "Origin")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let task = session?.webSocketTask(with: request)
        self.webSocketTask = task
        task?.resume()
        receiveNextMessage()
        startPingTimer()
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

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
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
                self.receiveNextMessage()
            case .failure:
                self.handleDisconnection()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "welcome":
            isConnected = true
        case "call-incoming":
            let callId = json["callId"] as? String ?? ""
            let mode = json["mode"] as? String ?? "video"
            let fromObj = json["from"] as? [String: Any]
            let callerName = fromObj?["name"] as? String ?? "Kinnect"
            let isVideo = (mode != "audio")
            if UIApplication.shared.applicationState != .active {
                CallKitManager.shared.reportIncomingCall(callId: callId, callerName: callerName, isVideo: isVideo)
            }
        case "call-ended":
            if let callId = json["callId"] as? String, !callId.isEmpty {
                CallKitManager.shared.reportCallEnded(callId: callId, reason: .remoteEnded)
            }
        case "call-accepted":
            if let callId = json["callId"] as? String, !callId.isEmpty {
                CallKitManager.shared.reportCallConnected(callId: callId)
            }
        case "notification":
            if UIApplication.shared.applicationState != .active {
                postLocalNotification(from: json)
            }
        default:
            break
        }
    }

    private func postLocalNotification(from json: [String: Any]) {
        let actor = json["actor"] as? [String: Any]
        let sender = actor?["name"] as? String ?? "Kinnect"
        let preview = json["preview"] as? String ?? "Bạn có thông báo mới trên Kinnect"

        let content = UNMutableNotificationContent()
        content.title = sender
        content.body = preview
        content.sound = .default

        let id = json["id"] as? String ?? UUID().uuidString
        let req = UNNotificationRequest(identifier: "msg-\(id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
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
        if shouldReconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self, self.shouldReconnect, self.webSocketTask == nil else { return }
                self.connect()
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleDisconnection()
    }
}
