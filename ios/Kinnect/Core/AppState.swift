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
    @Published var toastMessage: String?
    @Published var blockedUserIds: Set<String> = []

    // Live room runtime state when inside a Live room
    @Published var currentLiveRoom: LiveRoomItem?
    @Published var isCurrentLiveHost: Bool = false
    @Published var liveChatMessages: [LiveChatMessage] = []
    @Published var liveGiftRanking: [[String: Any]] = []
    @Published var liveLastReactionBanner: String?

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
        if rememberMe {
            KeychainStore.shared.saveAccountId(user.id)
        } else {
            KeychainStore.shared.clearSession()
        }
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
                let history = (roomDict["chatHistory"] as? [[String: Any]] ?? []).map(LiveChatMessage.from)
                self.liveChatMessages = history
                self.liveGiftRanking = roomDict["giftRanking"] as? [[String: Any]] ?? []
            }
        case "peer":
            if isCurrentLiveHost, let peerId = json["peerId"] as? String {
                NativeWebRTCManager.shared.handleLiveViewerJoined(peerId: peerId)
            }
        case "signal":
            if let fromPeer = json["from"] as? String,
               let signal = json["signal"] as? [String: Any] {
                NativeWebRTCManager.shared.handleLiveSignal(from: fromPeer, signal: signal, isHost: isCurrentLiveHost)
            }
        case "chat":
            let msg = LiveChatMessage.from(json)
            liveChatMessages.append(msg)
        case "live-reaction":
            let senderName = (json["user"] as? [String: Any])?["name"] as? String ?? "Khán giả"
            let label = json["label"] as? String ?? "Quà tặng"
            let qty = json["quantity"] as? Int ?? 1
            let isGift = json["isGift"] as? Bool ?? false
            if isGift {
                self.liveLastReactionBanner = "🎁 \(senderName) đã gửi \(qty)x \(label)"
            } else {
                self.liveLastReactionBanner = "💜 \(senderName) thả cảm xúc \(label)"
            }
            if let ranking = json["giftRanking"] as? [[String: Any]] {
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
        default:
            break
        }
    }
}

extension Notification.Name {
    static let kinnectMessagesChanged = Notification.Name("kinnectMessagesChanged")
    static let kinnectNotificationsChanged = Notification.Name("kinnectNotificationsChanged")
    static let kinnectContentModerated = Notification.Name("kinnectContentModerated")
}

