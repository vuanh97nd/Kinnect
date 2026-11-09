import Foundation
import SwiftUI
import UserNotifications

struct UGCReportContext: Identifiable {
    let id = UUID()
    let targetType: String // "post", "short", "user", "live", "comment", "message"
    let targetId: String
    let targetUserId: String?
    let targetTitle: String
}

struct PrivacyConsentRequest: Identifiable {
    let id = UUID()
    let version: String
    let notice: String
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRestoringSession: Bool = true
    @Published var currentUser: KinnectUser?
    @Published var unreadNotificationsCount: Int = 0
    @Published var unreadMessagesCount: Int = 0
    @Published var onlineUserIds: Set<String> = []
    @Published var liveRooms: [LiveRoomItem] = []
    @Published var activeReportContext: UGCReportContext?
    @Published var pendingPrivacyConsent: PrivacyConsentRequest?
    @Published var toastMessage: String?
    @Published var blockedUserIds: Set<String> = []

    // Live room runtime state when inside a Live room
    @Published var currentLiveRoom: LiveRoomItem?
    @Published var isCurrentLiveHost: Bool = false
    @Published var liveChatMessages: [LiveChatMessage] = []
    @Published var liveGiftRanking: [[String: Any]] = []
    @Published var navigationTargetRef: String = ""
    @Published var liveLastReactionBanner: String?
    @Published var liveGiftCombo: Int = 0

    func joinLiveRoom(_ room: LiveRoomItem) {
        if currentLiveRoom?.id == room.id {
            return
        }
        if currentLiveRoom != nil {
            NativeSocketClient.shared.sendJSON(["type": "leave"])
            NativeWebRTCManager.shared.stopLiveSession()
        }
        currentLiveRoom = room
        let isHost = (!room.hostUserId.isEmpty && room.hostUserId == currentUser?.id)
        isCurrentLiveHost = isHost
        liveChatMessages = []
        liveGiftRanking = []
        liveLastReactionBanner = nil
        liveGiftCombo = 0

        if !UIReviewFixture.isEnabled && !isHost {
            Task {
                await NativeWebRTCManager.shared.refreshIceServers()
                NativeSocketClient.shared.sendJSON([
                    "type": "join",
                    "room": room.id,
                    "liveMode": room.liveMode,
                    "multiGuest": false,
                    "liveModes": true
                ])
            }
        }
    }

    func leaveCurrentLiveRoom() {
        if currentLiveRoom != nil && !UIReviewFixture.isEnabled {
            NativeSocketClient.shared.sendJSON(["type": "leave"])
        }
        NativeWebRTCManager.shared.stopLiveSession()
        currentLiveRoom = nil
        isCurrentLiveHost = false
        liveChatMessages = []
        liveGiftRanking = []
        liveLastReactionBanner = nil
        liveGiftCombo = 0
    }

    private init() {
        setupCallKitCallbacks()
        setupSocketCallbacks()
    }

    private func setupCallKitCallbacks() {
        CallKitManager.shared.onAnswerCall = { callId in
            Task { @MainActor in
                await NativeWebRTCManager.shared.acceptIncomingCall(callId: callId)
            }
        }
        CallKitManager.shared.onEndCall = { _ in
            Task { @MainActor in
                NativeWebRTCManager.shared.endOrRejectCurrentCall(sendSocket: true)
            }
        }
        CallKitManager.shared.onSetMuted = { _, isMuted in
            Task { @MainActor in
                NativeWebRTCManager.shared.setMuted(isMuted)
            }
        }
    }

    private func setupSocketCallbacks() {
        NativeSocketClient.shared.onEvent = { [weak self] json in
            Task { @MainActor in
                self?.handleSocketEvent(json)
            }
        }
    }

    func bootstrapSession() async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        if let reviewScreen = UIReviewFixture.activeScreen {
            if reviewScreen == "auth" {
                self.currentUser = nil
            } else {
                self.currentUser = KinnectUser.from(UIReviewFixture.currentUserDict)
                self.onlineUserIds = ["fixture_user_peer"]
                self.unreadNotificationsCount = 1
                self.unreadMessagesCount = 2
            }
            return
        }

        // Check if user chose to remember session on this device
        let isRemembered = UserDefaults.standard.object(forKey: "kinnect_session_remembered") as? Bool ?? true
        if !isRemembered {
            clearSessionState()
            return
        }

        // If cached user exists for active account, restore optimistically while verifying
        if let accountId = AccountCache.shared.activeAccountId,
           let cachedDict: [String: Any] = AccountCache.shared.loadJSONObject(forKey: "profile_me", accountId: accountId) {
            let user = KinnectUser.from(cachedDict)
            if !user.id.isEmpty {
                self.currentUser = user
            }
        }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/me")
            if let userDict = res["user"] as? [String: Any] {
                let user = KinnectUser.from(userDict)
                guard !user.id.isEmpty else {
                    clearSessionState()
                    return
                }
                applyAuthenticatedUser(user, rawDict: userDict)
                await refreshGlobalBadges()
                await refreshBlockedUsers()
            } else {
                clearSessionState()
            }
        } catch {
            if case KinnectAPIError.unauthorized = error {
                clearSessionState()
            }
        }
    }

    func applyAuthenticatedUser(_ user: KinnectUser, rawDict: [String: Any], rememberMe: Bool = true) {
        self.currentUser = user
        UserDefaults.standard.set(rememberMe, forKey: "kinnect_session_remembered")
        AccountCache.shared.setActiveAccount(user.id)
        AccountCache.shared.saveJSONObject(rawDict, forKey: "profile_me", accountId: user.id)
        KeychainStore.shared.setRememberMe(rememberMe)
        KeychainStore.shared.saveAccountId(user.id)
        NativeSocketClient.shared.connectWithKeychainSession()
        PushKitManager.shared.startRegistration()
    }

    func logout() async {
        _ = try? await KinnectAPIClient.shared.requestJSON("/api/logout", method: "POST", body: [:])
        clearSessionState()
    }

    func clearSessionState() {
        NativeWebRTCManager.shared.endOrRejectCurrentCall(sendSocket: false)
        NativeWebRTCManager.shared.stopLiveSession()
        CallKitManager.shared.endAllCalls()
        NativeSocketClient.shared.disconnect()
        KeychainStore.shared.clearAll()
        AccountCache.shared.wipeAllCaches()
        currentUser = nil
        unreadNotificationsCount = 0
        unreadMessagesCount = 0
        onlineUserIds.removeAll()
        liveRooms.removeAll()
        blockedUserIds.removeAll()
        currentLiveRoom = nil
    }

    func refreshGlobalBadges() async {
        guard currentUser != nil else { return }
        if let notifRes = try? await KinnectAPIClient.shared.requestJSON("/api/notifications") {
            let items = (notifRes["notifications"] as? [[String: Any]] ?? []).map(NotificationItem.from)
            self.unreadNotificationsCount = items.filter { !$0.read }.count
        }
        if let convRes = try? await KinnectAPIClient.shared.requestJSON("/api/conversations") {
            let list = convRes["conversations"] as? [[String: Any]] ?? []
            var total = 0
            for item in list {
                total += (item["unreadCount"] as? Int ?? 0)
            }
            self.unreadMessagesCount = total
        }
    }

    func refreshBlockedUsers() async {
        guard currentUser != nil else { return }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/blocks") {
            let blocks = res["blocks"] as? [[String: Any]] ?? []
            var ids = Set<String>()
            for b in blocks {
                if let u = b["user"] as? [String: Any], let id = u["id"] as? String {
                    ids.insert(id)
                } else if let id = b["blockedUserId"] as? String {
                    ids.insert(id)
                }
            }
            self.blockedUserIds = ids
        }
    }

    func blockUser(userId: String, userName: String) async {
        guard !userId.isEmpty else { return }
        let reqId = "block_\(userId)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(userId)/block",
                method: "POST",
                body: [:],
                requestId: reqId
            )
            blockedUserIds.insert(userId)
            showToast("Đã chặn \(userName). Nội dung của người này đã được ẩn.")
            NotificationCenter.default.post(name: .kinnectContentModerated, object: nil)
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func unblockUser(userId: String) async {
        guard !userId.isEmpty else { return }
        let reqId = "unblock_\(userId)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(userId)/block",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            blockedUserIds.remove(userId)
            showToast("Đã bỏ chặn người dùng.")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func showToast(_ message: String) {
        self.toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    // MARK: - Socket Event Dispatch

    private func handleSocketEvent(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }

        switch type {
        case "presence":
            if let ids = json["onlineUserIds"] as? [String] {
                self.onlineUserIds = Set(ids)
            }
        case "rooms":
            if let list = json["rooms"] as? [[String: Any]] {
                self.liveRooms = list.map(LiveRoomItem.from)
                if let current = currentLiveRoom,
                   let updated = self.liveRooms.first(where: { $0.id == current.id }) {
                    self.currentLiveRoom = updated
                }
            }
        case "joined":
            if let roomDict = json["room"] as? [String: Any] {
                let room = LiveRoomItem.from(roomDict)
                self.currentLiveRoom = room
                let role = json["role"] as? String ?? "viewer"
                self.isCurrentLiveHost = (role == "host")
                let historyRaw = (json["history"] as? [[String: Any]]) ?? (roomDict["chatHistory"] as? [[String: Any]]) ?? []
                self.liveChatMessages = historyRaw.map(LiveChatMessage.from)
                self.liveGiftRanking = (json["giftRanking"] as? [[String: Any]]) ?? (roomDict["giftRanking"] as? [[String: Any]]) ?? []
            }
        case "peer":
            if isCurrentLiveHost, let peerId = (json["id"] as? String) ?? (json["peerId"] as? String) {
                NativeWebRTCManager.shared.handleLiveViewerJoined(peerId: peerId)
            }
        case "signal":
            if let fromPeer = json["from"] as? String {
                let signalPayload = (json["signal"] as? [String: Any]) ?? json
                NativeWebRTCManager.shared.handleLiveSignal(from: fromPeer, signal: signalPayload, isHost: isCurrentLiveHost)
            }
        case "chat":
            let msg = LiveChatMessage.from(json)
            liveChatMessages.append(msg)
        case "live-reaction":
            let senderName = (json["name"] as? String) ?? (json["user"] as? [String: Any])?["name"] as? String ?? "Khán giả"
            let label = (json["giftName"] as? String) ?? (json["label"] as? String) ?? "Quà tặng"
            let qty = json["quantity"] as? Int ?? 1
            let isGift = (json["experience"] as? Bool) ?? (json["isGift"] as? Bool) ?? (json["giftId"] != nil)
            if isGift {
                let same = self.liveLastReactionBanner?.contains(label) == true
                self.liveGiftCombo = same ? self.liveGiftCombo + qty : qty
                self.liveLastReactionBanner = "🎁 \(senderName) đã gửi \(self.liveGiftCombo)x \(label)"
            } else {
                self.liveLastReactionBanner = "💜 \(senderName) thả cảm xúc \(label)"
            }
            if let rankingObj = json["ranking"] as? [String: Any],
               let topSenders = rankingObj["topSenders"] as? [[String: Any]] {
                self.liveGiftRanking = topSenders
            } else if let ranking = json["giftRanking"] as? [[String: Any]] {
                self.liveGiftRanking = ranking
            }
        case "live-gift-error":
            if let message = json["message"] as? String {
                showToast(message)
            }
        case "live-mode-state":
            if var room = currentLiveRoom {
                if let paused = json["gamePaused"] as? Bool {
                    room.gamePaused = paused
                }
                if let title = json["gameTitle"] as? String {
                    room.gameTitle = title
                }
                self.currentLiveRoom = room
            }
        case "room-ended":
            if currentLiveRoom != nil {
                NativeWebRTCManager.shared.stopLiveSession()
                currentLiveRoom = nil
                showToast("Phiên phát trực tiếp đã kết thúc.")
            }
        case "call-incoming":
            NativeWebRTCManager.shared.handleIncomingCallSocket(json)
        case "call-ringing":
            NativeWebRTCManager.shared.handleCallRingingSocket(json)
        case "call-accepted":
            NativeWebRTCManager.shared.handleCallAcceptedSocket(json)
        case "call-signal":
            NativeWebRTCManager.shared.handleCallSignalSocket(json)
        case "call-ended":
            NativeWebRTCManager.shared.handleCallEndedSocket(json)
        case "notification", "notifications-changed":
            Task { await refreshGlobalBadges() }
            NotificationCenter.default.post(name: .kinnectNotificationsChanged, object: nil)
        case "direct-message", "group-message", "conversations-changed":
            Task { await refreshGlobalBadges() }
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: json)
        case "error":
            let message = (json["message"] as? String) ?? (json["error"] as? String) ?? ""
            // server.js:626 rejects WS live "create"/"chat" without current consent; route to the explicit consent sheet.
            if message.localizedCaseInsensitiveContains("đồng ý thông báo dữ liệu") {
                presentPrivacyConsent(version: "", notice: message)
            } else if !message.isEmpty {
                showToast(message)
            }
        default:
            break
        }
    }

    func navigate(to route: String) {
        NotificationCenter.default.post(name: .kinnectNavigateRoute, object: route)
    }

    /// Presents the explicit privacy consent sheet. If the version or full notice is unknown
    /// (e.g. WebSocket errors carry only a message), fetch the authoritative values from
    /// GET /api/me/privacy-consent so the POST sends the exact current server version.
    func presentPrivacyConsent(version: String, notice: String) {
        guard pendingPrivacyConsent == nil else { return }
        if !version.isEmpty {
            pendingPrivacyConsent = PrivacyConsentRequest(version: version, notice: notice)
            return
        }
        Task { @MainActor in
            do {
                let status = try await KinnectAPIClient.shared.requestJSON("/api/me/privacy-consent")
                if (status["accepted"] as? Bool) == true { return }
                let serverVersion = (status["version"] as? String) ?? ""
                let serverNotice = (status["notice"] as? String) ?? notice
                guard !serverVersion.isEmpty else { showToast(notice); return }
                self.pendingPrivacyConsent = PrivacyConsentRequest(version: serverVersion, notice: serverNotice)
            } catch {
                showToast(notice)
            }
        }
    }
}

extension Notification.Name {
    static let kinnectNavigateRoute = Notification.Name("kinnectNavigateRoute")
    static let kinnectMessagesChanged = Notification.Name("kinnectMessagesChanged")
    static let kinnectNotificationsChanged = Notification.Name("kinnectNotificationsChanged")
    static let kinnectContentModerated = Notification.Name("kinnectContentModerated")
}

