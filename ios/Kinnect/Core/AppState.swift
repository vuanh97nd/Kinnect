import Foundation
import SwiftUI
import UIKit
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

struct LiveGuestInvitation: Identifiable, Equatable {
    var id: String { token }
    let roomId: String
    let token: String
    let fromPeerId: String
    let fromUserId: String
    let fromName: String
    let expiresAtMs: Int64
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRestoringSession: Bool = true
    @Published var currentUser: KinnectUser?
    @Published var unreadNotificationsCount: Int = 0
    @Published var unreadMessagesCount: Int = 0
    @Published var pendingFriendRequestsCount: Int = 0
    @Published var onlineUserIds: Set<String> = []
    @Published var liveRooms: [LiveRoomItem] = []
    @Published var activeReportContext: UGCReportContext?
    @Published var pendingPrivacyConsent: PrivacyConsentRequest?
    @Published var toastMessage: String?
    @Published var blockedUserIds: Set<String> = []

    // Cold-start APNs push & kinnect:// deep link routing
    @Published var pendingPushRoute: String? = nil
    @Published var pendingPushPayload: [String: String] = [:]
    @Published var pendingDeepLinkURL: URL? = nil

    // Live room runtime state when inside a Live room
    @Published var currentLiveRoom: LiveRoomItem? {
        didSet { syncSocketRealtimeSessionFlag() }
    }
    @Published var isCurrentLiveHost: Bool = false
    @Published var isCurrentLivePublisher: Bool = false
    @Published var isCreatingLiveRoom: Bool = false {
        didSet { syncSocketRealtimeSessionFlag() }
    }
    @Published var liveChatMessages: [LiveChatMessage] = []
    @Published var liveGiftRanking: [[String: Any]] = []
    @Published var navigationTargetRef: String = ""
    @Published var liveLastReactionBanner: String?
    @Published var liveGiftCombo: Int = 0
    @Published var currentLiveStageRevision: Int = 0
    @Published var currentLiveTransport: String = "mesh"
    @Published var liveStageParticipants: [[String: Any]] = []
    @Published var liveStagePeers: [[String: Any]] = []
    @Published var pendingLiveGuestInvitation: LiveGuestInvitation? = nil
    @Published var hasPendingLiveGuestRequest: Bool = false
    @Published var liveGuestRequests: [[String: Any]] = []

    private var hostRoomGraceTask: Task<Void, Never>? = nil
    private var toastDismissTask: Task<Void, Never>? = nil

    func syncSocketRealtimeSessionFlag() {
        let active = (currentLiveRoom != nil)
            || isCreatingLiveRoom
            || (NativeWebRTCManager.shared.activeCall != nil)
        NativeSocketClient.shared.setHasActiveRealtimeSession(active)
    }

    func handleSocketReconnectedWelcome(flushedTypes: Set<String>) {
        guard let room = currentLiveRoom, !isCreatingLiveRoom else { return }
        if !isCurrentLiveHost {
            guard !flushedTypes.contains("join"), !flushedTypes.contains("create") else { return }
            NativeWebRTCManager.shared.prepareLiveViewerAudio()
            NativeSocketClient.shared.sendJSON([
                "type": "join",
                "room": room.id,
                "multiGuest": true,
                "liveModes": true
            ])
        }
    }

    func joinLiveRoom(_ room: LiveRoomItem) {
        guard !isCreatingLiveRoom else { return }
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
        isCurrentLivePublisher = isHost
        liveChatMessages = []
        liveGiftRanking = []
        liveLastReactionBanner = nil
        liveGiftCombo = 0
        currentLiveStageRevision = 0
        currentLiveTransport = "mesh"
        liveStageParticipants = []
        liveStagePeers = []

        #if DEBUG
        let fixtureEnabled = UIReviewFixture.isEnabled
        #else
        let fixtureEnabled = false
        #endif
        if !fixtureEnabled && !isHost {
            NativeWebRTCManager.shared.prepareLiveViewerAudio()
            Task { @MainActor in
                guard await NativeSocketClient.shared.ensureConnected() else { return }
                await NativeWebRTCManager.shared.refreshIceServers()
                guard self.currentLiveRoom?.id == room.id else { return }
                NativeSocketClient.shared.sendJSON([
                    "type": "join",
                    "room": room.id,
                    "multiGuest": true,
                    "liveModes": true
                ])
            }
        }
    }

    func leaveCurrentLiveRoom() {
        hostRoomGraceTask?.cancel()
        hostRoomGraceTask = nil
        #if DEBUG
        let fixtureEnabled = UIReviewFixture.isEnabled
        #else
        let fixtureEnabled = false
        #endif
        if (currentLiveRoom != nil || isCreatingLiveRoom) && !fixtureEnabled {
            NativeSocketClient.shared.sendJSON(["type": "leave"])
        }
        NativeWebRTCManager.shared.stopLiveSession()
        currentLiveRoom = nil
        isCurrentLiveHost = false
        isCurrentLivePublisher = false
        isCreatingLiveRoom = false
        liveChatMessages = []
        liveGiftRanking = []
        liveLastReactionBanner = nil
        liveGiftCombo = 0
        currentLiveStageRevision = 0
        currentLiveTransport = "mesh"
        liveStageParticipants = []
        liveStagePeers = []
        pendingLiveGuestInvitation = nil
        hasPendingLiveGuestRequest = false
        liveGuestRequests = []
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

        #if DEBUG
        if let reviewScreen = UIReviewFixture.activeScreen {
            if reviewScreen == "auth" {
                self.currentUser = nil
            } else {
                self.currentUser = KinnectUser.from(UIReviewFixture.currentUserDict)
                self.onlineUserIds = ["u2"]
                self.unreadNotificationsCount = 1
                self.unreadMessagesCount = 2
            }
            return
        }
        #endif

        // Check if user chose to remember session on this device
        let isRemembered = UserDefaults.standard.object(forKey: "kinnect_session_remembered") as? Bool ?? true
        if !isRemembered {
            clearSessionState()
            return
        }

        // If cached user exists for active account, restore optimistically while verifying
        _ = hydrateCachedSessionUser()

        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/me")
            if let userDict = res["user"] as? [String: Any] {
                let user = KinnectUser.from(userDict)
                guard !user.id.isEmpty else {
                    if KinnectAPIClient.shared.baseURL == ServerConfig.defaultOrigin {
                        clearSessionState()
                    }
                    return
                }
                if KinnectAPIClient.shared.baseURL == ServerConfig.defaultOrigin {
                    applyAuthenticatedUser(user, rawDict: userDict)
                    await refreshGlobalBadges()
                    await refreshBlockedUsers()
                    dispatchPendingPushRouteIfReady()
                } else {
                    self.currentUser = user
                    dispatchPendingPushRouteIfReady()
                }
            } else if KinnectAPIClient.shared.baseURL == ServerConfig.defaultOrigin {
                clearSessionState()
            } else {
                _ = hydrateCachedSessionUser()
            }
        } catch {
            if case KinnectAPIError.unauthorized = error,
               KinnectAPIClient.shared.baseURL == ServerConfig.defaultOrigin {
                clearSessionState()
            } else {
                _ = hydrateCachedSessionUser()
            }
        }
    }

    @discardableResult
    private func hydrateCachedSessionUser() -> Bool {
        let accountId = AccountCache.shared.activeAccountId
            ?? {
                let uid = KeychainStore.shared.loadAccountId(for: ServerConfig.defaultOrigin)
                return uid.isEmpty ? nil : uid
            }()
        if let accountId {
            if let cachedDict: [String: Any] = AccountCache.shared.loadJSONObject(forKey: "profile_me", accountId: accountId) {
                let user = KinnectUser.from(cachedDict)
                if !user.id.isEmpty {
                    self.currentUser = user
                    return true
                }
            }
            if let cachedMe = KinnectAPIClient.shared.cachedJSON(for: "/api/me"),
               let userDict = cachedMe["user"] as? [String: Any] {
                let user = KinnectUser.from(userDict)
                if !user.id.isEmpty {
                    self.currentUser = user
                    return true
                }
            }
        }
        return self.currentUser != nil
    }

    func applyAuthenticatedUser(_ user: KinnectUser, rawDict: [String: Any], rememberMe: Bool? = nil) {
        let effectiveRemember = rememberMe ?? (UserDefaults.standard.object(forKey: "kinnect_session_remembered") as? Bool ?? true)
        self.currentUser = user
        UserDefaults.standard.set(effectiveRemember, forKey: "kinnect_session_remembered")
        AccountCache.shared.setActiveAccount(user.id)
        AccountCache.shared.saveJSONObject(rawDict, forKey: "profile_me", accountId: user.id)
        KeychainStore.shared.setRememberMe(effectiveRemember)
        KeychainStore.shared.saveAccountId(user.id)
        NativeSocketClient.shared.connectWithKeychainSession()
        PushKitManager.shared.startRegistration()
        startActivityHeartbeat()
    }

    func updateCurrentUser(_ user: KinnectUser, rawDict: [String: Any]) {
        self.currentUser = user
        if !user.id.isEmpty {
            AccountCache.shared.setActiveAccount(user.id)
            AccountCache.shared.saveJSONObject(rawDict, forKey: "profile_me", accountId: user.id)
        }
    }

    func logout() async {
        await PushKitManager.shared.unregisterStoredTokens()
        _ = try? await KinnectAPIClient.shared.requestJSON("/api/logout", method: "POST", body: [:])
        clearSessionState()
    }

    func clearSessionState() {
        hostRoomGraceTask?.cancel()
        hostRoomGraceTask = nil
        stopActivityHeartbeat()
        NativeWebRTCManager.shared.endOrRejectCurrentCall(sendSocket: false)
        NativeWebRTCManager.shared.stopLiveSession()
        CallKitManager.shared.endAllCalls()
        NativeSocketClient.shared.disconnect()
        KeychainStore.shared.clearAll()
        ImageMemoryCache.shared.clear()
        VideoThumbnailLoader.clearCache()
        AccountCache.shared.wipeAllCaches()
        let tempDir = FileManager.default.temporaryDirectory
        if let items = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for item in items {
                let name = item.lastPathComponent
                if name.hasPrefix("media_")
                    || name.hasPrefix("picked_video_")
                    || name.hasPrefix("kinnect_capture_")
                    || name.hasPrefix("Kinnect-Capture-")
                    || name.hasPrefix("Kinnect-Post-")
                    || name.hasPrefix("Kinnect-Story-")
                    || name.hasPrefix("Kinnect-Attach-")
                    || name.hasPrefix("Kinnect-Video-")
                    || name.hasPrefix("Kinnect-Music-")
                    || name.hasPrefix("Kinnect-PhotoMusic-") {
                    try? FileManager.default.removeItem(at: item)
                }
            }
        }
        currentUser = nil
        unreadNotificationsCount = 0
        unreadMessagesCount = 0
        pendingFriendRequestsCount = 0
        onlineUserIds.removeAll()
        liveRooms.removeAll()
        blockedUserIds.removeAll()
        currentLiveRoom = nil
        isCurrentLiveHost = false
        isCurrentLivePublisher = false
        isCreatingLiveRoom = false
        liveChatMessages.removeAll()
        liveGiftRanking.removeAll()
        liveLastReactionBanner = nil
        liveGiftCombo = 0
        currentLiveStageRevision = 0
        currentLiveTransport = "mesh"
        liveStageParticipants.removeAll()
        liveStagePeers.removeAll()
        pendingLiveGuestInvitation = nil
        hasPendingLiveGuestRequest = false
        liveGuestRequests.removeAll()
        activeReportContext = nil
        pendingPrivacyConsent = nil
        pendingPushRoute = nil
        pendingPushPayload = [:]
        pendingDeepLinkURL = nil
        navigationTargetRef = ""
        dismissToast()
    }

    func refreshGlobalBadges() async {
        guard currentUser != nil else { return }
        // Sequential: KinnectAPIClient.activeOrigin is unsynchronized shared state.
        // Overlapping calls can read it while a transport fallback writes it.
        let notifRes = try? await KinnectAPIClient.shared.requestJSON("/api/notifications")
        let convRes = try? await KinnectAPIClient.shared.requestJSON("/api/conversations")
        let groupRes = try? await KinnectAPIClient.shared.requestJSON("/api/groups")

        if let notifRes {
            let items = (notifRes["notifications"] as? [[String: Any]] ?? []).map(NotificationItem.from)
            self.unreadNotificationsCount = items.filter {
                !$0.read && $0.type != "message" && $0.type != "group_message"
            }.count
            if let pendingCount = (notifRes["friendRequestsPending"] as? Int) ?? (notifRes["friendRequestsPending"] as? NSNumber)?.intValue {
                self.pendingFriendRequestsCount = max(0, pendingCount)
            } else if let reqRes = try? await KinnectAPIClient.shared.requestJSON("/api/friend-requests") {
                let inc = reqRes["incoming"] as? [[String: Any]] ?? []
                self.pendingFriendRequestsCount = inc.count
            }
        }
        // Real API: { users: [{ unread }] } plus /api/groups { groups: [{ unread }] }.
        // UI review fixture: { conversations: [{ unreadCount }] } and groups[].unreadCount.
        guard let convRes else { return }
        let direct = (convRes["users"] as? [[String: Any]])
            ?? (convRes["conversations"] as? [[String: Any]])
            ?? []
        var total = Self.unreadTotal(direct)
        if let groupRes {
            let groups = groupRes["groups"] as? [[String: Any]] ?? []
            total += Self.unreadTotal(groups)
        }
        self.unreadMessagesCount = total
    }

    /// Prefer the live `unread` field, then the fixture `unreadCount` field.
    private static func unreadTotal(_ items: [[String: Any]]) -> Int {
        var total = 0
        for item in items {
            let count = (item["unread"] as? Int) ?? (item["unreadCount"] as? Int) ?? 0
            if count > 0 { total += count }
        }
        return total
    }

    func refreshBlockedUsers() async {
        guard currentUser != nil else { return }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/blocks") {
            let blocks = (res["users"] as? [[String: Any]]) ?? (res["blocks"] as? [[String: Any]]) ?? []
            var ids = Set<String>()
            for b in blocks {
                if let u = b["user"] as? [String: Any], let id = u["id"] as? String, !id.isEmpty {
                    ids.insert(id)
                } else if let id = b["id"] as? String, !id.isEmpty {
                    ids.insert(id)
                } else if let id = b["blockedUserId"] as? String, !id.isEmpty {
                    ids.insert(id)
                }
            }
            self.blockedUserIds = ids
        }
    }

    private func evictModerationCaches() {
        guard let accountId = AccountCache.shared.activeAccountId, !accountId.isEmpty else { return }
        for key in [
            "json:/api/blocks",
            "json:/api/conversations",
            "json:/api/friends",
            "json:/api/posts?limit=25",
            "json:/api/posts",
            "feed_posts",
            "json:/api/stories",
            "json:/api/shorts",
            "json:/api/shorts?feed=for",
            "json:/api/shorts?feed=following",
            "shorts_feed_for",
            "shorts_feed_following",
            "json:/api/discover"
        ] {
            AccountCache.shared.evict(forKey: key, accountId: accountId)
        }
    }

    @discardableResult
    func blockUser(userId: String, userName: String, silentToast: Bool = false) async -> Bool {
        guard !userId.isEmpty else { return false }
        let reqId = "block_\(userId)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(userId)/block",
                method: "POST",
                body: [:],
                requestId: reqId
            )
            blockedUserIds.insert(userId)
            evictModerationCaches()
            if !silentToast {
                showToast(String(format: L10n.tr("Đã chặn %@. Nội dung của người này đã được ẩn."), userName))
            }
            NotificationCenter.default.post(name: .kinnectContentModerated, object: nil)
            return true
        } catch {
            showToast(error.localizedDescription)
            return false
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
            evictModerationCaches()
            showToast(L10n.tr("Đã bỏ chặn người dùng."))
        } catch {
            showToast(error.localizedDescription)
        }
    }

    func showToast(_ message: String) {
        toastDismissTask?.cancel()
        self.toastMessage = message
        KinnectToastPresenter.shared.sync(visible: true)
        UIAccessibility.post(notification: .announcement, argument: message)
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            if self.toastMessage == message {
                self.toastMessage = nil
                KinnectToastPresenter.shared.sync(visible: false)
            }
        }
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toastMessage = nil
        KinnectToastPresenter.shared.sync(visible: false)
    }

    // MARK: - Socket Event Dispatch

    private func handleSocketEvent(_ json: [String: Any]) {
        NotificationCenter.default.post(name: SocketEventBridge.rawEventNotification, object: nil, userInfo: json)
        guard let type = json["type"] as? String else { return }

        switch type {
        case "presence":
            if let ids = json["onlineUserIds"] as? [String] {
                self.onlineUserIds = Set(ids)
            }
        case "rooms":
            if let list = json["rooms"] as? [[String: Any]] {
                let parsedRooms = list.map(LiveRoomItem.from)
                self.liveRooms = parsedRooms
                if let current = currentLiveRoom {
                    if var updated = parsedRooms.first(where: { $0.id == current.id }) {
                        hostRoomGraceTask?.cancel()
                        hostRoomGraceTask = nil
                        let rawRoom = list.first(where: {
                            (($0["id"] as? String) ?? ($0["roomId"] as? String)) == current.id
                        })
                        if rawRoom?["comments"] == nil {
                            updated.comments = current.comments
                        }
                        if rawRoom?["gamePaused"] == nil && rawRoom?["screenPaused"] == nil {
                            updated.gamePaused = current.gamePaused
                        }
                        self.currentLiveRoom = updated
                    } else if isCurrentLiveHost && !isCreatingLiveRoom {
                        // Do not kill an active host broadcast from a single transient snapshot;
                        // rely on explicit ended/room-ended events or a delayed server verification.
                        scheduleHostRoomGraceCheck(roomId: current.id)
                    }
                }
            }
        case "count":
            if let viewers = json["viewers"] as? Int {
                let targetRoomId = (json["room"] as? String) ?? currentLiveRoom?.id
                if var current = currentLiveRoom,
                   (targetRoomId == nil || current.id == targetRoomId) {
                    current.viewerCount = viewers
                    self.currentLiveRoom = current
                }
                if let targetRoomId,
                   let idx = self.liveRooms.firstIndex(where: { $0.id == targetRoomId }) {
                    self.liveRooms[idx].viewerCount = viewers
                }
            }
        case "joined":
            hostRoomGraceTask?.cancel()
            hostRoomGraceTask = nil
            self.isCreatingLiveRoom = false
            if let roomDict = json["room"] as? [String: Any] {
                let room = LiveRoomItem.from(roomDict)
                self.currentLiveRoom = room
                let role = json["role"] as? String ?? "viewer"
                self.isCurrentLiveHost = (role == "host")
                self.isCurrentLivePublisher = (role == "host" || role == "guest")
                if let hostPeerId = json["host"] as? String, !hostPeerId.isEmpty {
                    NativeWebRTCManager.shared.setLiveHostPeerId(hostPeerId)
                }
                let historyRaw = (json["history"] as? [[String: Any]]) ?? (roomDict["chatHistory"] as? [[String: Any]]) ?? []
                self.liveChatMessages = historyRaw.map(LiveChatMessage.from)
                self.liveGiftRanking = (json["giftRanking"] as? [[String: Any]]) ?? (roomDict["giftRanking"] as? [[String: Any]]) ?? []
                if !self.isCurrentLivePublisher {
                    NativeWebRTCManager.shared.prepareLiveViewerAudio()
                }
            }
        case "live-stage":
            let stageRoomId = (json["room"] as? String) ?? ""
            if !stageRoomId.isEmpty, let activeId = currentLiveRoom?.id, activeId != stageRoomId {
                return
            }
            let revision = (json["revision"] as? Int) ?? (json["revision"] as? NSNumber)?.intValue ?? 0
            let transport = (json["transport"] as? String) ?? "mesh"
            let role = (json["role"] as? String) ?? (isCurrentLiveHost ? "host" : (isCurrentLivePublisher ? "guest" : "viewer"))
            let participants = (json["participants"] as? [[String: Any]]) ?? []
            let peers = (json["peers"] as? [[String: Any]]) ?? []
            self.currentLiveStageRevision = revision
            self.currentLiveTransport = transport
            self.liveStageParticipants = participants
            self.liveStagePeers = peers
            self.isCurrentLiveHost = (role == "host")
            self.isCurrentLivePublisher = (role == "host" || role == "guest")
            NativeWebRTCManager.shared.applyLiveStage(
                revision: revision,
                transport: transport,
                role: role,
                peers: peers,
                participants: participants
            )
        case "peer":
            if isCurrentLivePublisher, let peerId = (json["id"] as? String) ?? (json["peerId"] as? String) {
                NativeWebRTCManager.shared.handleLiveViewerJoined(peerId: peerId)
            }
        case "peer-left":
            if let peerId = (json["id"] as? String) ?? (json["peerId"] as? String) {
                NativeWebRTCManager.shared.handleLivePeerLeft(peerId: peerId)
            }
        case "signal":
            if let fromPeer = json["from"] as? String {
                let signalPayload = (json["signal"] as? [String: Any]) ?? json
                let revision = (json["revision"] as? Int) ?? (json["revision"] as? NSNumber)?.intValue
                NativeWebRTCManager.shared.handleLiveSignal(
                    from: fromPeer,
                    signal: signalPayload,
                    revision: revision,
                    isPublisher: isCurrentLivePublisher
                )
            }
        case "chat":
            let msg = LiveChatMessage.from(json)
            liveChatMessages.append(msg)
        case "live-reaction":
            if let evtRoom = json["room"] as? String, !evtRoom.isEmpty,
               let curId = currentLiveRoom?.id, evtRoom != curId {
                return
            }
            if let senderId = json["senderId"] as? String, !senderId.isEmpty,
               blockedUserIds.contains(senderId) {
                return
            }
            let senderName = (json["name"] as? String) ?? (json["user"] as? [String: Any])?["name"] as? String ?? "Khán giả"
            let giftId = (json["giftId"] as? String) ?? (json["kind"] as? String) ?? ""
            let label = (json["giftName"] as? String) ?? (json["label"] as? String) ?? LiveGiftCatalogItem.defaultName(for: giftId)
            let qty = (json["quantity"] as? Int) ?? (json["quantity"] as? NSNumber)?.intValue ?? 1
            let serverCombo = (json["comboCount"] as? Int) ?? (json["comboCount"] as? NSNumber)?.intValue ?? 1
            let isGift = (json["experience"] as? Bool) ?? (json["isGift"] as? Bool) ?? (json["giftId"] != nil)
            if isGift {
                self.liveGiftCombo = serverCombo
                let comboSuffix = serverCombo > 1 ? " · Combo x\(serverCombo)!" : ""
                self.liveLastReactionBanner = "🎁 \(senderName) đã gửi \(qty)x \(label)\(comboSuffix)"
            } else {
                self.liveLastReactionBanner = "💜 \(senderName) thả tim"
            }
            if let rankingObj = json["ranking"] as? [String: Any],
               let topSenders = rankingObj["topSenders"] as? [[String: Any]] {
                self.liveGiftRanking = topSenders
            } else if let ranking = json["giftRanking"] as? [[String: Any]] {
                self.liveGiftRanking = ranking
            }
            NotificationCenter.default.post(name: .kinnectLiveReactionReceived, object: nil, userInfo: json)
        case "live-gift-receipt":
            NotificationCenter.default.post(name: Notification.Name("kinnectLiveGiftResult"), object: nil, userInfo: json)
            Task { await refreshGlobalBadges() }
        case "live-mode-error", "live-gift-error":
            if isCreatingLiveRoom || (currentLiveRoom == nil && NativeWebRTCManager.shared.liveLocalVideoTrack != nil) {
                isCreatingLiveRoom = false
                NativeWebRTCManager.shared.stopLiveSession()
            }
            NotificationCenter.default.post(name: Notification.Name("kinnectLiveGiftResult"), object: nil, userInfo: json)
            if let message = json["message"] as? String {
                showToast(message)
            }
        case "live-mode-state", "live-mode":
            if var room = currentLiveRoom {
                if let paused = (json["screenPaused"] as? Bool) ?? (json["gamePaused"] as? Bool) {
                    room.gamePaused = paused
                }
                if let title = json["gameTitle"] as? String {
                    room.gameTitle = title
                }
                if let mode = json["liveMode"] as? String {
                    room.liveMode = (mode.lowercased() == "game") ? "game" : "chat"
                }
                if let comments = json["comments"] as? Bool {
                    room.comments = comments
                }
                self.currentLiveRoom = room
            }
            if let roomId = json["room"] as? String,
               let idx = self.liveRooms.firstIndex(where: { $0.id == roomId }) {
                if let comments = json["comments"] as? Bool {
                    self.liveRooms[idx].comments = comments
                }
                if let paused = (json["screenPaused"] as? Bool) ?? (json["gamePaused"] as? Bool) {
                    self.liveRooms[idx].gamePaused = paused
                }
            }
        case "ended", "room-ended":
            hostRoomGraceTask?.cancel()
            hostRoomGraceTask = nil
            isCreatingLiveRoom = false
            if currentLiveRoom != nil {
                NativeWebRTCManager.shared.stopLiveSession()
                currentLiveRoom = nil
                isCurrentLiveHost = false
                isCurrentLivePublisher = false
                liveChatMessages = []
                liveGiftRanking = []
                liveLastReactionBanner = nil
                liveGiftCombo = 0
                currentLiveStageRevision = 0
                currentLiveTransport = "mesh"
                liveStageParticipants = []
                liveStagePeers = []
                pendingLiveGuestInvitation = nil
                hasPendingLiveGuestRequest = false
                liveGuestRequests = []
                showToast(L10n.tr("Phiên phát trực tiếp đã kết thúc."))
            }
        case "live-guest-invitation":
            let roomId = (json["room"] as? String) ?? ""
            let token = (json["token"] as? String) ?? ""
            guard !token.isEmpty, roomId.isEmpty || roomId == currentLiveRoom?.id else { return }
            let from = (json["from"] as? [String: Any]) ?? [:]
            let fromName = (from["name"] as? String) ?? currentLiveRoom?.hostName ?? L10n.tr("Chủ phòng")
            let expiresAt = (json["expiresAt"] as? NSNumber)?.int64Value ?? 0
            pendingLiveGuestInvitation = LiveGuestInvitation(
                roomId: roomId.isEmpty ? (currentLiveRoom?.id ?? "") : roomId,
                token: token,
                fromPeerId: (from["id"] as? String) ?? "",
                fromUserId: (from["userId"] as? String) ?? "",
                fromName: fromName,
                expiresAtMs: expiresAt
            )
            hasPendingLiveGuestRequest = false
            showToast(String(format: L10n.tr("%@ mời bạn lên sóng cùng phòng Live!"), fromName))
        case "live-guest-requested":
            let roomId = (json["room"] as? String) ?? ""
            if roomId.isEmpty || roomId == currentLiveRoom?.id {
                hasPendingLiveGuestRequest = true
                showToast(L10n.tr("Đã gửi yêu cầu lên sóng tới chủ phòng."))
            }
        case "live-guest-cancelled":
            hasPendingLiveGuestRequest = false
        case "live-guest-declined":
            hasPendingLiveGuestRequest = false
            pendingLiveGuestInvitation = nil
            showToast(L10n.tr("Chủ phòng đã từ chối yêu cầu lên sóng."))
        case "live-guest-removed":
            hasPendingLiveGuestRequest = false
            pendingLiveGuestInvitation = nil
            if !isCurrentLiveHost {
                isCurrentLivePublisher = false
                NativeWebRTCManager.shared.stopLiveLocalMedia()
            }
            showToast(L10n.tr("Bạn đã rời vị trí khách mời."))
        case "live-guest-state":
            liveGuestRequests = (json["requests"] as? [[String: Any]]) ?? []
        case "live-guest-error":
            if !isCurrentLivePublisher && NativeWebRTCManager.shared.liveLocalVideoTrack != nil {
                NativeWebRTCManager.shared.stopLiveLocalMedia()
            }
            if let message = json["message"] as? String, !message.isEmpty {
                showToast(message)
            }
        case "call-incoming":
            NativeWebRTCManager.shared.handleIncomingCallSocket(json)
        case "call-ringing":
            NativeWebRTCManager.shared.handleCallRingingSocket(json)
        case "call-accepted":
            NativeWebRTCManager.shared.handleCallAcceptedSocket(json)
        case "call-reconnecting":
            NativeWebRTCManager.shared.handleCallReconnectingSocket(json)
        case "call-resumed":
            NativeWebRTCManager.shared.handleCallResumedSocket(json)
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
            if isCreatingLiveRoom || (currentLiveRoom == nil && NativeWebRTCManager.shared.liveLocalVideoTrack != nil) {
                isCreatingLiveRoom = false
                NativeWebRTCManager.shared.stopLiveSession()
            }
            let message = (json["message"] as? String) ?? (json["error"] as? String) ?? ""
            if !isCurrentLiveHost && currentLiveRoom != nil && message.localizedCaseInsensitiveContains("Phòng đã kết thúc") {
                leaveCurrentLiveRoom()
            }
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

    private func scheduleHostRoomGraceCheck(roomId: String) {
        guard hostRoomGraceTask == nil else { return }
        hostRoomGraceTask = Task { @MainActor [weak self] in
            defer { self?.hostRoomGraceTask = nil }
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  self.isCurrentLiveHost,
                  !self.isCreatingLiveRoom,
                  self.currentLiveRoom?.id == roomId else { return }
            // Verify against HTTP room list before tearing down host broadcast.
            if let res = try? await KinnectAPIClient.shared.requestJSON("/api/live/rooms"),
               let list = res["rooms"] as? [[String: Any]] {
                let parsed = list.map(LiveRoomItem.from)
                if parsed.contains(where: { $0.id == roomId }) {
                    return
                }
            } else {
                // Network hiccup: keep host broadcast alive while socket reconnects.
                return
            }
            guard self.isCurrentLiveHost,
                  !self.isCreatingLiveRoom,
                  self.currentLiveRoom?.id == roomId else { return }
            NativeWebRTCManager.shared.stopLiveSession()
            self.currentLiveRoom = nil
            self.isCurrentLiveHost = false
            self.isCurrentLivePublisher = false
            self.liveChatMessages = []
            self.liveGiftRanking = []
            self.liveLastReactionBanner = nil
            self.liveGiftCombo = 0
            self.currentLiveStageRevision = 0
            self.currentLiveTransport = "mesh"
            self.liveStageParticipants = []
            self.liveStagePeers = []
            self.pendingLiveGuestInvitation = nil
            self.hasPendingLiveGuestRequest = false
            self.liveGuestRequests = []
            self.showToast(L10n.tr("Phiên Live đã kết thúc do mất kết nối."))
        }
    }

    func respondToLiveGuestInvitation(accept: Bool, mode: String = "video", invitation: LiveGuestInvitation? = nil) {
        guard let inv = invitation ?? pendingLiveGuestInvitation else { return }
        pendingLiveGuestInvitation = nil
        if accept {
            Task { @MainActor in
                let ok = await NativeWebRTCManager.shared.startLiveHostBroadcast()
                guard ok else {
                    NativeSocketClient.shared.sendJSON([
                        "type": "live-guest-answer",
                        "token": inv.token,
                        "accept": false
                    ])
                    showToast(L10n.tr("Cần quyền camera và micro để tham gia lên sóng."))
                    return
                }
                NativeSocketClient.shared.sendJSON([
                    "type": "live-guest-answer",
                    "token": inv.token,
                    "accept": true,
                    "mode": mode == "audio" ? "audio" : "video"
                ])
            }
        } else {
            NativeSocketClient.shared.sendJSON([
                "type": "live-guest-answer",
                "token": inv.token,
                "accept": false
            ])
        }
    }

    // MARK: - Cold-start Push & Deep Link Routing

    func enqueuePushNavigation(route: String, ref: String = "", payload: [String: String] = [:]) {
        guard !route.isEmpty else { return }
        pendingPushRoute = route
        pendingPushPayload = payload
        if !ref.isEmpty {
            navigationTargetRef = ref
        }
        if currentUser != nil && !isRestoringSession {
            NotificationCenter.default.post(name: .kinnectNavigateRoute, object: route, userInfo: payload)
        }
    }

    @discardableResult
    func consumePendingPushRoute() -> String? {
        let route = pendingPushRoute
        pendingPushRoute = nil
        pendingPushPayload = [:]
        return route
    }

    private func dispatchPendingPushRouteIfReady() {
        guard currentUser != nil, let route = pendingPushRoute else { return }
        let payload = pendingPushPayload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            NotificationCenter.default.post(name: .kinnectNavigateRoute, object: route, userInfo: payload)
        }
    }

    func handleDeepLink(_ url: URL) {
        pendingDeepLinkURL = url
        guard let scheme = url.scheme?.lowercased(), scheme == "kinnect" else { return }
        let host = (url.host ?? "").lowercased()
        let pathParts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let firstArg = pathParts.first ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryRef = queryItems.first(where: { ["id", "ref", "postId", "conversationId", "roomId", "userId"].contains($0.name) })?.value ?? ""
        let targetRef = !firstArg.isEmpty ? firstArg : queryRef

        let route: String
        switch host {
        case "messages", "message", "chat", "dm", "group":
            route = "messages"
        case "notifications", "notification":
            route = "notifications"
        case "friends", "friend", "friend-requests":
            route = "friends"
        case "profile", "user", "users":
            route = "profile"
        case "live":
            route = "live"
        case "shorts", "short", "video", "videos":
            route = "shorts"
        case "store", "shop":
            route = "store"
        case "wallet":
            route = "wallet"
        case "post", "posts", "feed", "story", "stories":
            route = "feed"
        default:
            route = "feed"
        }
        var payload: [String: String] = ["url": url.absoluteString]
        if !targetRef.isEmpty {
            payload["ref"] = targetRef
        }
        enqueuePushNavigation(route: route, ref: targetRef, payload: payload)
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
            Task { @MainActor [weak self] in
                self?.reportActiveStatus(force: true)
            }
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
    static let kinnectLiveReactionReceived = Notification.Name("kinnectLiveReactionReceived")
    static let kinnectStoreUpdated = Notification.Name("kinnectStoreUpdated")
    static let kinnectAppearanceChanged = Notification.Name("kinnectAppearanceChanged")
}

