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

struct LiveCreateFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
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
    private var pendingLiveCreateToken: UUID?
    private var pendingLiveCreateContinuation: CheckedContinuation<Result<LiveRoomItem, LiveCreateFailure>, Never>?
    private var announcedNotificationIds: Set<String> = []
    private var hasSeededNotifications = false

    func createLiveRoomAndAwaitJoin(payload: [String: Any]) async -> Result<LiveRoomItem, LiveCreateFailure> {
        let connected = await NativeSocketClient.shared.ensureConnected()
        guard connected else {
            return .failure(LiveCreateFailure(message: "Không thể kết nối máy chủ Live. Vui lòng thử lại."))
        }

        resolvePendingLiveCreate(with: .failure(LiveCreateFailure(message: "Đã hủy yêu cầu tạo phòng Live trước đó.")))

        let token = UUID()
        self.pendingLiveCreateToken = token

        var createPayload = payload
        createPayload["type"] = "create"
        createPayload["multiGuest"] = true
        createPayload["liveModes"] = true

        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<LiveRoomItem, LiveCreateFailure>, Never>) in
            self.pendingLiveCreateContinuation = continuation
            NativeSocketClient.shared.sendJSON(createPayload)

            Task { @MainActor [weak self] in
                for _ in 0..<40 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard let self, self.pendingLiveCreateToken == token else { return }
                    if !NativeSocketClient.shared.isConnected {
                        self.resolvePendingLiveCreate(with: .failure(LiveCreateFailure(message: "Mất kết nối máy chủ Live khi tạo phòng.")))
                        return
                    }
                }
                guard let self, self.pendingLiveCreateToken == token else { return }
                self.resolvePendingLiveCreate(with: .failure(LiveCreateFailure(message: "Không nhận được phản hồi từ máy chủ Live. Vui lòng thử lại.")))
            }
        }
    }

    private func resolvePendingLiveCreate(with result: Result<LiveRoomItem, LiveCreateFailure>) {
        pendingLiveCreateToken = nil
        guard let continuation = pendingLiveCreateContinuation else { return }
        pendingLiveCreateContinuation = nil
        continuation.resume(returning: result)
    }

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
            let targetRoomId = room.id
            let targetLiveMode = room.liveMode
            Task { @MainActor [weak self] in
                await NativeWebRTCManager.shared.refreshIceServers()
                guard let self, self.currentLiveRoom?.id == targetRoomId else { return }
                let connected = await NativeSocketClient.shared.ensureConnected()
                guard self.currentLiveRoom?.id == targetRoomId else { return }
                guard connected else {
                    NativeWebRTCManager.shared.liveConnectionError = "Không thể kết nối máy chủ Live."
                    self.showToast("Không thể kết nối máy chủ Live.")
                    return
                }
                NativeSocketClient.shared.sendJSON([
                    "type": "join",
                    "room": targetRoomId,
                    "liveMode": targetLiveMode,
                    "multiGuest": true,
                    "liveModes": true
                ])
            }
        }
    }

    func leaveCurrentLiveRoom() {
        resolvePendingLiveCreate(with: .failure(LiveCreateFailure(message: "Đã rời phòng Live.")))
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
        CallKitManager.shared.onEndCall = { callId in
            Task { @MainActor in
                NativeWebRTCManager.shared.endOrRejectCurrentCall(sendSocket: true, fallbackCallId: callId)
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
        requestLocalNotificationAuthorizationIfNeeded()
        startActivityHeartbeat()
    }

    private func requestLocalNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        }
    }

    func logout() async {
        await PushKitManager.shared.unregisterStoredTokens()
        _ = try? await KinnectAPIClient.shared.requestJSON("/api/logout", method: "POST", body: [:])
        clearSessionState()
    }

    func clearSessionState() {
        stopActivityHeartbeat()
        NativeWebRTCManager.shared.endOrRejectCurrentCall(sendSocket: false)
        NativeWebRTCManager.shared.stopLiveSession()
        CallKitManager.shared.endAllCalls()
        NativeSocketClient.shared.disconnect()
        KeychainStore.shared.clearAll()
        AccountCache.shared.wipeAllCaches()
        KinnectAuthenticatedFile.wipe()
        resolvePendingLiveCreate(with: .failure(LiveCreateFailure(message: "Phiên đăng nhập đã kết thúc.")))
        currentUser = nil
        unreadNotificationsCount = 0
        unreadMessagesCount = 0
        onlineUserIds.removeAll()
        liveRooms.removeAll()
        blockedUserIds.removeAll()
        currentLiveRoom = nil
        isCurrentLiveHost = false
        announcedNotificationIds.removeAll()
        hasSeededNotifications = false
    }

    func refreshGlobalBadges(announceNew: Bool = false) async {
        guard currentUser != nil else { return }
        if let notifRes = try? await KinnectAPIClient.shared.requestJSON("/api/notifications") {
            let items = (notifRes["notifications"] as? [[String: Any]] ?? []).map(NotificationItem.from)
            let bellItems = items.filter {
                let kind = $0.type.lowercased()
                return !$0.read && kind != "message" && kind != "group_message"
            }
            self.unreadNotificationsCount = bellItems.count
            if !hasSeededNotifications {
                announcedNotificationIds.formUnion(items.map(\.id))
                hasSeededNotifications = true
            } else if announceNew {
                let freshUnread = items.filter { !$0.read && !announcedNotificationIds.contains($0.id) }
                announcedNotificationIds.formUnion(items.map(\.id))
                for item in freshUnread.prefix(2) {
                    presentLocalNotification(for: item)
                }
            }
        }
        if let convRes = try? await KinnectAPIClient.shared.requestJSON("/api/conversations") {
            let people = (convRes["users"] as? [[String: Any]])
                ?? (convRes["conversations"] as? [[String: Any]])
                ?? []
            let groups = (convRes["groups"] as? [[String: Any]]) ?? []
            var total = 0
            for item in people + groups {
                total += (item["unread"] as? Int) ?? (item["unreadCount"] as? Int) ?? 0
            }
            self.unreadMessagesCount = total
        }
    }

    private func presentLocalNotification(for item: NotificationItem) {
        let sender = item.actor.name.isEmpty ? "Kinnect" : item.actor.name
        let kind = item.type.lowercased()
        let actionLine: String
        switch kind {
        case "message": actionLine = "đã gửi cho bạn một tin nhắn mới"
        case "group_message": actionLine = "đã gửi tin nhắn trong nhóm"
        case "like": actionLine = "đã thích bài viết của bạn"
        case "comment": actionLine = "đã bình luận bài viết của bạn"
        case "comment_reply": actionLine = "đã trả lời bình luận của bạn"
        case "friend_request": actionLine = "đã gửi lời mời kết bạn"
        case "friend_accept", "friend_accepted": actionLine = "đã chấp nhận lời mời kết bạn"
        case "follow": actionLine = "đã bắt đầu theo dõi bạn"
        case "short_like": actionLine = "đã thích video ngắn của bạn"
        case "short_comment": actionLine = "đã bình luận video ngắn của bạn"
        case "missed_call": actionLine = "đã gọi nhỡ cho bạn"
        default: actionLine = "có thông báo mới dành cho bạn"
        }

        let bodyText = item.preview.isEmpty ? "\(sender) \(actionLine)" : "\(sender) \(actionLine): \(item.preview)"
        showToast(bodyText)

        let content = UNMutableNotificationContent()
        content.title = sender
        content.body = item.preview.isEmpty ? actionLine : "\(actionLine): \(item.preview)"
        content.sound = .default
        content.userInfo = ["notificationId": item.id, "kind": item.type]
        let req = UNNotificationRequest(identifier: "kinnect_notif_\(item.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
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
        case "welcome":
            Task { await refreshGlobalBadges(announceNew: false) }
            NotificationCenter.default.post(name: .kinnectNotificationsChanged, object: nil)
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: json)
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
                NativeWebRTCManager.shared.prepareLiveRoomSession(roomId: room.id, role: role)
                if role == "host" || pendingLiveCreateContinuation != nil {
                    resolvePendingLiveCreate(with: .success(room))
                }
            }
        case "live-stage":
            guard let roomId = json["room"] as? String, !roomId.isEmpty,
                  currentLiveRoom?.id == roomId else { return }
            let revision = (json["revision"] as? Int) ?? (json["revision"] as? NSNumber)?.intValue ?? 0
            guard revision > 0 else { return }
            let transport = (json["transport"] as? String) ?? "mesh"
            let selfId = (json["selfId"] as? String) ?? ""
            let role = (json["role"] as? String) ?? (isCurrentLiveHost ? "host" : "viewer")
            let mode = (json["mode"] as? String) ?? "video"
            let peers = json["peers"] as? [[String: Any]] ?? []
            let participants = json["participants"] as? [[String: Any]] ?? []
            self.isCurrentLiveHost = (role == "host")
            NativeWebRTCManager.shared.applyLiveStage(
                roomId: roomId,
                transport: transport,
                revision: revision,
                selfId: selfId,
                role: role,
                mode: mode,
                peers: peers,
                participants: participants
            )
        case "peer":
            if isCurrentLiveHost,
               NativeWebRTCManager.shared.liveStageRevision == 0,
               let peerId = (json["id"] as? String) ?? (json["peerId"] as? String) {
                NativeWebRTCManager.shared.handleLiveViewerJoined(peerId: peerId)
            }
        case "peer-left":
            if let peerId = (json["id"] as? String) ?? (json["peerId"] as? String) {
                NativeWebRTCManager.shared.handleLivePeerLeft(peerId: peerId)
            }
        case "signal":
            if let fromPeer = json["from"] as? String {
                let signalPayload = (json["signal"] as? [String: Any]) ?? json
                let msgRoom = json["room"] as? String
                let msgRevision = (json["revision"] as? Int) ?? (json["revision"] as? NSNumber)?.intValue ?? 0
                NativeWebRTCManager.shared.handleLiveSignal(
                    from: fromPeer,
                    roomId: msgRoom,
                    revision: msgRevision,
                    signal: signalPayload,
                    isHost: isCurrentLiveHost
                )
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
        case "live-gift-receipt":
            NotificationCenter.default.post(name: Notification.Name("kinnectLiveGiftResult"), object: nil, userInfo: json)
            Task { await refreshGlobalBadges() }
        case "live-mode-error", "live-gift-error", "live-guest-error":
            NotificationCenter.default.post(name: Notification.Name("kinnectLiveGiftResult"), object: nil, userInfo: json)
            if let message = json["message"] as? String, !message.isEmpty {
                if type == "live-mode-error" {
                    let msgRoom = json["room"] as? String
                    if msgRoom == nil || msgRoom == currentLiveRoom?.id {
                        NativeWebRTCManager.shared.liveConnectionError = message
                    }
                }
                showToast(message)
            }
        case "live-guest-removed":
            let msgRoom = json["room"] as? String
            if msgRoom == nil || msgRoom == currentLiveRoom?.id {
                showToast("Bạn đã rời khỏi vị trí khách mời Live.")
            }
        case "live-mode-state":
            let msgRoom = (json["room"] as? String) ?? currentLiveRoom?.id ?? ""
            let nextMode = (json["liveMode"] as? String) ?? (json["mode"] as? String)
            let nextPaused = (json["screenPaused"] as? Bool) ?? (json["gamePaused"] as? Bool)
            let nextTitle = json["gameTitle"] as? String
            if var room = currentLiveRoom, msgRoom.isEmpty || room.id == msgRoom {
                if let nextMode, !nextMode.isEmpty { room.liveMode = nextMode }
                if let nextPaused { room.gamePaused = nextPaused }
                if let nextTitle { room.gameTitle = nextTitle }
                self.currentLiveRoom = room
            }
            if !msgRoom.isEmpty, let idx = liveRooms.firstIndex(where: { $0.id == msgRoom }) {
                if let nextMode, !nextMode.isEmpty { liveRooms[idx].liveMode = nextMode }
                if let nextPaused { liveRooms[idx].gamePaused = nextPaused }
                if let nextTitle { liveRooms[idx].gameTitle = nextTitle }
            }
        case "ended", "room-ended":
            let msgRoom = json["room"] as? String
            resolvePendingLiveCreate(with: .failure(LiveCreateFailure(message: "Phiên phát trực tiếp đã kết thúc.")))
            if let activeRoom = currentLiveRoom, (msgRoom == nil || msgRoom == activeRoom.id) {
                NativeWebRTCManager.shared.stopLiveSession()
                currentLiveRoom = nil
                isCurrentLiveHost = false
                liveChatMessages = []
                liveGiftRanking = []
                liveLastReactionBanner = nil
                liveGiftCombo = 0
                liveRooms.removeAll { $0.id == activeRoom.id }
                let notice = (json["message"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Phiên phát trực tiếp đã kết thúc."
                showToast(notice)
            } else if let msgRoom, !msgRoom.isEmpty {
                liveRooms.removeAll { $0.id == msgRoom }
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
            Task { await refreshGlobalBadges(announceNew: true) }
            NotificationCenter.default.post(name: .kinnectNotificationsChanged, object: nil)
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: json)
        case "direct-message", "group-message", "conversations-changed":
            Task { await refreshGlobalBadges(announceNew: true) }
            NotificationCenter.default.post(name: .kinnectMessagesChanged, object: json)
        case "error":
            let message = (json["message"] as? String) ?? (json["error"] as? String) ?? ""
            let effectiveMessage = message.isEmpty ? "Không thể thực hiện thao tác Live." : message
            resolvePendingLiveCreate(with: .failure(LiveCreateFailure(message: effectiveMessage)))
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

    // MARK: - Active Status Reporting (1:1 Android MainActivity.activity lines 5411-5415)
    private var lastActivityReportTime: TimeInterval = 0
    private var activityTimer: Timer?

    func reportActiveStatus(force: Bool = false) {
        guard currentUser != nil else { return }
        let now = Date().timeIntervalSince1970
        if !force && (now - lastActivityReportTime < 50.0) {
            return
        }
        lastActivityReportTime = now
        Task {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/me/activity",
                method: "POST",
                body: [:]
            )
        }
    }

    func startActivityHeartbeat() {
        activityTimer?.invalidate()
        reportActiveStatus(force: true)
        activityTimer = Timer.scheduledTimer(withTimeInterval: 50.0, repeats: true) { [weak self] _ in
            self?.reportActiveStatus(force: true)
        }
    }

    func stopActivityHeartbeat() {
        activityTimer?.invalidate()
        activityTimer = nil
    }

    func navigate(to route: String) {
        reportActiveStatus()
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

