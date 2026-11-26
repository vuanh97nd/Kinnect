import Foundation
import UIKit
import UserNotifications

final class NativeSocketClient: NSObject, URLSessionWebSocketDelegate {
    static let shared = NativeSocketClient()

    private struct QueuedMessage {
        let type: String
        let text: String
        let queuedAt: Date
    }

    private static let criticalMessageTypes: Set<String> = [
        "call-accept",
        "call-start",
        "call-decline",
        "call-cancel",
        "call-end",
        "call-resume",
        "join",
        "create"
    ]

    private let lock = NSLock()
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pingTimer: Timer?
    private var _isConnected = false
    private var _hasWelcome = false
    private var _hasWelcomedOnce = false
    private var _isAppForeground = true
    private var _hasActiveRealtimeSession = false
    private var shouldReconnect = false
    private var activeSocketOrigin: String = ""
    private var activeCookieHeader: String = ""
    private var reconnectAttempt: Int = 0
    private var blockedSessionSignature: String? = nil
    private var pendingCriticalMessages: [QueuedMessage] = []
    private var _onEvent: (([String: Any]) -> Void)?

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    var isAppForeground: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAppForeground
    }

    var hasActiveRealtimeSession: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _hasActiveRealtimeSession
    }

    func setAppForeground(_ active: Bool) {
        let shouldNotify: Bool
        lock.lock()
        let changed = (_isAppForeground != active)
        _isAppForeground = active
        shouldNotify = changed && _hasWelcome && webSocketTask?.state == .running
        lock.unlock()
        if shouldNotify {
            sendJSON(["type": "visibility", "visible": active])
        }
    }

    func setHasActiveRealtimeSession(_ active: Bool) {
        lock.lock()
        _hasActiveRealtimeSession = active
        lock.unlock()
    }

    var onEvent: (([String: Any]) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onEvent
        }
        set {
            lock.lock()
            _onEvent = newValue
            lock.unlock()
        }
    }

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

        let taskToCancel: URLSessionWebSocketTask?
        let newTask: URLSessionWebSocketTask?

        lock.lock()
        if blockedSessionSignature == signature {
            lock.unlock()
            return
        }
        blockedSessionSignature = nil
        shouldReconnect = true
        if let existing = webSocketTask,
           existing.state == .running,
           activeSocketOrigin == origin,
           activeCookieHeader == cookieHeader {
            lock.unlock()
            return
        }
        taskToCancel = webSocketTask
        webSocketTask = nil
        _isConnected = false
        _hasWelcome = false
        activeSocketOrigin = origin
        activeCookieHeader = cookieHeader

        let wsScheme = origin.lowercased().hasPrefix("https://") ? "wss://" : "ws://"
        let cleanHost = origin
            .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(wsScheme)\(cleanHost)/") else {
            lock.unlock()
            taskToCancel?.cancel(with: .goingAway, reason: nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = true
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        newTask = session?.webSocketTask(with: request)
        self.webSocketTask = newTask
        lock.unlock()

        taskToCancel?.cancel(with: .goingAway, reason: nil)
        newTask?.resume()
        if let newTask { receiveNextMessage(newTask) }
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
        let taskToCancel: URLSessionWebSocketTask?
        lock.lock()
        shouldReconnect = false
        _isConnected = false
        _hasWelcome = false
        _hasWelcomedOnce = false
        reconnectAttempt = 0
        blockedSessionSignature = nil
        activeSocketOrigin = ""
        activeCookieHeader = ""
        pendingCriticalMessages.removeAll()
        taskToCancel = webSocketTask
        webSocketTask = nil
        lock.unlock()

        Task { @MainActor [weak self] in
            self?.pingTimer?.invalidate()
            self?.pingTimer = nil
        }
        taskToCancel?.cancel(with: .goingAway, reason: nil)
    }

    func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        let msgType = (dict["type"] as? String) ?? ""
        let isCritical = Self.criticalMessageTypes.contains(msgType)

        var taskToSend: URLSessionWebSocketTask?
        var shouldConnect = false

        lock.lock()
        if msgType == "leave" {
            pendingCriticalMessages.removeAll { $0.type == "join" || $0.type == "create" }
        }
        if let task = webSocketTask, task.state == .running, (_hasWelcome || (!isCritical && _isConnected)) {
            taskToSend = task
        } else if isCritical {
            if msgType == "join" || msgType == "create" {
                pendingCriticalMessages.removeAll { $0.type == "join" || $0.type == "create" }
            }
            let cutoff = Date().addingTimeInterval(-30)
            pendingCriticalMessages.removeAll { $0.queuedAt < cutoff }
            pendingCriticalMessages.append(QueuedMessage(type: msgType, text: text, queuedAt: Date()))
            if pendingCriticalMessages.count > 24 {
                pendingCriticalMessages.removeFirst(pendingCriticalMessages.count - 24)
            }
            shouldConnect = (webSocketTask == nil || webSocketTask?.state != .running)
        } else {
            taskToSend = nil
        }
        lock.unlock()

        if let taskToSend {
            taskToSend.send(.string(text)) { [weak self] error in
                if error != nil, isCritical {
                    self?.requeueCriticalMessage(type: msgType, text: text)
                }
            }
        } else if shouldConnect {
            connectWithKeychainSession()
        }
    }

    private func requeueCriticalMessage(type: String, text: String) {
        lock.lock()
        let cutoff = Date().addingTimeInterval(-30)
        pendingCriticalMessages.removeAll { $0.queuedAt < cutoff }
        pendingCriticalMessages.append(QueuedMessage(type: type, text: text, queuedAt: Date()))
        if pendingCriticalMessages.count > 24 {
            pendingCriticalMessages.removeFirst(pendingCriticalMessages.count - 24)
        }
        lock.unlock()
    }

    private func flushPendingCriticalMessages(on task: URLSessionWebSocketTask) -> Set<String> {
        let queued: [QueuedMessage]
        lock.lock()
        guard self.webSocketTask === task, _hasWelcome else {
            lock.unlock()
            return []
        }
        let cutoff = Date().addingTimeInterval(-30)
        queued = pendingCriticalMessages.filter { $0.queuedAt >= cutoff }
        pendingCriticalMessages.removeAll()
        lock.unlock()

        for item in queued {
            task.send(.string(item.text)) { [weak self] error in
                if error != nil {
                    self?.requeueCriticalMessage(type: item.type, text: item.text)
                }
            }
        }
        return Set(queued.map(\.type))
    }

    private func receiveNextMessage(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            self.lock.lock()
            let isCurrent = (self.webSocketTask === task)
            self.lock.unlock()
            guard isCurrent else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text, from: task)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text, from: task)
                    }
                @unknown default:
                    break
                }
                self.receiveNextMessage(task)
            case .failure:
                self.handleDisconnection(for: task)
            }
        }
    }

    private func handleMessage(_ text: String, from task: URLSessionWebSocketTask) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        var wasReconnect = false
        var flushedTypes: Set<String> = []
        var visibleOnWelcome = true
        if type == "welcome" {
            lock.lock()
            if self.webSocketTask === task {
                wasReconnect = _hasWelcomedOnce
                _hasWelcomedOnce = true
                _isConnected = true
                _hasWelcome = true
                reconnectAttempt = 0
                visibleOnWelcome = _isAppForeground
            }
            lock.unlock()
            sendJSON(["type": "visibility", "visible": visibleOnWelcome])
            flushedTypes = flushPendingCriticalMessages(on: task)
        }

        let handler = self.onEvent
        Task { @MainActor [weak self] in
            if type == "welcome" {
                if let call = NativeWebRTCManager.shared.activeCall,
                   (call.state == .connecting || call.state == .connected || call.isReconnecting),
                   !flushedTypes.contains("call-resume") {
                    self?.sendJSON(["type": "call-resume", "callId": call.callId])
                }
                if wasReconnect {
                    AppState.shared.handleSocketReconnectedWelcome(flushedTypes: flushedTypes)
                }
            }
            handler?(json)
        }
    }

    private func startPingTimer() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pingTimer?.invalidate()
            self.pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                let task = self.webSocketTask
                self.lock.unlock()
                guard let task, task.state == .running else { return }
                task.sendPing { [weak self] error in
                    if error != nil {
                        self?.handleDisconnection(for: task)
                    }
                }
            }
        }
    }

    private func handleDisconnection(
        for task: URLSessionWebSocketTask? = nil,
        closeCode: URLSessionWebSocketTask.CloseCode? = nil
    ) {
        let failedTask: URLSessionWebSocketTask?
        let shouldAttemptReconnect: Bool
        let delay: TimeInterval

        lock.lock()
        if let task, self.webSocketTask !== task {
            lock.unlock()
            return
        }
        failedTask = webSocketTask
        _isConnected = false
        _hasWelcome = false
        webSocketTask = nil

        let effectiveCloseRaw = closeCode?.rawValue ?? failedTask?.closeCode.rawValue ?? 0
        let isAuthFailure: Bool = {
            if effectiveCloseRaw == 4401 { return true }
            if let http = failedTask?.response as? HTTPURLResponse,
               http.statusCode == 401 || http.statusCode == 403 {
                return true
            }
            return false
        }()

        if isAuthFailure {
            blockedSessionSignature = "\(activeSocketOrigin)|\(activeCookieHeader)"
            shouldReconnect = false
            pendingCriticalMessages.removeAll()
            lock.unlock()
            Task { @MainActor [weak self] in
                self?.pingTimer?.invalidate()
                self?.pingTimer = nil
            }
            return
        }

        shouldAttemptReconnect = shouldReconnect
        let schedule: [TimeInterval] = [2.5, 5.0, 10.0, 20.0, 30.0]
        delay = schedule[min(reconnectAttempt, schedule.count - 1)]
        if shouldAttemptReconnect {
            reconnectAttempt += 1
        }
        let allowBackgroundRealtime = _isAppForeground || _hasActiveRealtimeSession
        lock.unlock()

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pingTimer?.invalidate()
            self.pingTimer = nil
            let canKeepSocketAlive = allowBackgroundRealtime
                || UIApplication.shared.applicationState == .active
                || NativeWebRTCManager.shared.activeCall != nil
                || AppState.shared.currentLiveRoom != nil
                || AppState.shared.isCreatingLiveRoom
            guard shouldAttemptReconnect, canKeepSocketAlive else { return }
            let nanos = UInt64(max(0.2, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            self.lock.lock()
            let canReconnect = self.shouldReconnect && self.webSocketTask == nil
            self.lock.unlock()
            guard canReconnect else { return }
            self.connectWithKeychainSession()
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        lock.lock()
        let isCurrent = (self.webSocketTask === webSocketTask)
        if isCurrent {
            _isConnected = true
        }
        lock.unlock()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        handleDisconnection(for: webSocketTask, closeCode: closeCode)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, let wsTask = task as? URLSessionWebSocketTask else { return }
        handleDisconnection(for: wsTask)
    }
}
