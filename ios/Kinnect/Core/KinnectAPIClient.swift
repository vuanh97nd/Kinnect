import CryptoKit
import Foundation

enum KinnectAPIError: LocalizedError {
    case invalidURL
    case networkError(String)
    case originUnavailable
    case serverError(status: Int, message: String)
    case requiresAgree18(String)
    case serverMessage(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.tr("Địa chỉ máy chủ không hợp lệ.")
        case .networkError(let msg):
            return msg
        case .originUnavailable:
            return L10n.tr("Máy chủ chính đang tạm thời gián đoạn. Vui lòng thử lại sau ít phút.")
        case .serverError(_, let message):
            return message
        case .requiresAgree18(let message):
            return message
        case .serverMessage(let message):
            return message
        case .unauthorized:
            return L10n.tr("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.")
        }
    }
}

/// Native async/await HTTP client with Keychain cookie management, account-scoped caching,
/// CSRF Origin protection, and safe PC -> Cloud fallback without duplicating non-idempotent writes.
/// Reads of `activeOrigin` and the single fallback write share `originLock`. The lock is never held across `await`.
final class KinnectAPIClient {
    static let shared = KinnectAPIClient()

    private let session: URLSession
    private let originLock = NSLock()
    private var activeOrigin: String = ServerConfig.currentOrigin
    /// True only while the one elected request is probing `ServerConfig.fallbackOrigin`.
    private var fallbackLeaderActive = false
    /// Stays set until every request that started on `defaultOrigin` in this overlap has returned.
    /// Stops a sibling whose probe already failed from starting a second one.
    private var fallbackProbeStarted = false
    private var defaultOriginBatchCount = 0
    /// Peers blocked until that probe commits or fails. Resumed with a snapshot taken under `originLock`.
    private var fallbackWaiters: [CheckedContinuation<String?, Never>] = []
    /// Background health-probe state for recovering `defaultOrigin` every 60s when on `fallbackOrigin`.
    private var lastPrimaryProbeAt: TimeInterval = 0
    private var primaryProbeInFlight = false
    private let primaryProbeInterval: TimeInterval = 60.0

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 45
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    var currentAccountId: String {
        let primary = KeychainStore.shared.loadAccountId(for: ServerConfig.defaultOrigin)
        if !primary.isEmpty { return primary }
        return AccountCache.shared.activeAccountId ?? ""
    }

    var baseURL: String {
        return snapshotOrigin()
    }

    var mediaOrigin: String { snapshotOrigin() }

    func absoluteURL(_ path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        let origin = snapshotOrigin()
        return ServerConfig.url(for: path, origin: origin)?.absoluteString ?? "\(origin)\(path.hasPrefix("/") ? "" : "/")\(path)"
    }

    private func isCacheableGET(_ path: String) -> Bool {
        let base = path.components(separatedBy: "?").first ?? path
        let allowedExact: Set<String> = [
            "/api/me", "/api/posts", "/api/stories", "/api/discover", "/api/shorts",
            "/api/conversations", "/api/groups", "/api/notifications",
            "/api/friends", "/api/friend-requests", "/api/friend-suggestions",
            "/api/store", "/api/wallet", "/api/live/gifts", "/api/music"
        ]
        if allowedExact.contains(base) { return true }
        if base.hasPrefix("/api/users/") || base.hasPrefix("/api/groups/") || base.hasPrefix("/api/chat-preferences/") || base.hasPrefix("/api/posts/") || base.hasPrefix("/api/shorts/") {
            return true
        }
        return false
    }

    func cachedJSON(for path: String) -> [String: Any]? {
        let uid = currentAccountId
        let origin = snapshotOrigin()
        guard !uid.isEmpty, isCacheableGET(path),
              let data = AccountCache.shared.load(forKey: "json:\(path)", origin: origin, accountId: uid),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    @discardableResult
    func requestJSON(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        requestId: String? = nil
    ) async throws -> [String: Any] {
        var payload = body
        if let requestId, !requestId.isEmpty {
            var dict = payload ?? [:]
            if dict["requestId"] == nil {
                dict["requestId"] = requestId
            }
            payload = dict
        }
        // Keep requestId on the body for a future server dedupe. It does not make POST replay-safe:
        // the messages INSERT does not read requestId, so a transport replay would duplicate the send.
        let carriesRequestId = !(requestId ?? "").isEmpty
        let isIdempotent = method == "GET" || method == "HEAD" || (carriesRequestId && method != "POST")
        return try await request(
            method: method,
            path: path,
            body: payload,
            isIdempotent: isIdempotent
        )
    }

    /// Performs an authenticated HTTP request.
    /// - Parameter isIdempotent: Explicit override. When nil, GET/HEAD may retry on transport failure.
    ///   POST is never treated as idempotent just because it carries `requestId`. HTTP 4xx/5xx never fall back.
    @discardableResult
    func request(
        method: String = "GET",
        path: String,
        body: [String: Any]? = nil,
        isIdempotent: Bool? = nil,
        allowPrivacyAutoRetry: Bool = true
    ) async throws -> [String: Any] {
        #if DEBUG
        if UIReviewFixture.isEnabled {
            return UIReviewFixture.mockResponse(for: path)
        }
        #endif
        let bodyRequestId = body?["requestId"] as? String
        let carriesRequestId = !(bodyRequestId ?? "").isEmpty
        let safeToRetryOnFallback = isIdempotent ?? (method == "GET" || method == "HEAD" || (carriesRequestId && method != "POST"))
        let origin = snapshotOrigin()
        if origin == ServerConfig.fallbackOrigin {
            maybeProbePrimary()
        }
        if origin == ServerConfig.defaultOrigin {
            enterDefaultOriginBatch()
        }
        defer {
            if origin == ServerConfig.defaultOrigin {
                leaveDefaultOriginBatch()
            }
        }
        do {
            return try await performSingleRequest(
                origin: origin,
                method: method,
                path: path,
                body: body,
                allowPrivacyAutoRetry: allowPrivacyAutoRetry
            )
        } catch let error as KinnectAPIError {
            throw error
        } catch {
            // Transport / connection error: only fall back to cloud gateway if the operation is idempotent.
            // POST (including sends that carry requestId) is not replayed, so a lost response cannot
            // insert a second message and activeOrigin stays on the origin that failed.
            // Cookies stay in the per-origin jar; nothing is copied onto fallbackOrigin.
            // Overlapping callers share one probe. The decision uses the origin this call already used,
            // not a second unlocked read of `activeOrigin`.
            guard safeToRetryOnFallback, origin == ServerConfig.defaultOrigin else {
                throw KinnectAPIError.networkError(L10n.tr("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn."))
            }
            return try await resolveOriginForFallbackIfNeeded(
                failedOrigin: origin,
                method: method,
                path: path,
                body: body,
                allowPrivacyAutoRetry: allowPrivacyAutoRetry
            )
        }
    }

    private func snapshotOrigin() -> String {
        originLock.lock()
        defer { originLock.unlock() }
        return activeOrigin
    }

    private func enterDefaultOriginBatch() {
        originLock.lock()
        defer { originLock.unlock() }
        defaultOriginBatchCount += 1
    }

    private func leaveDefaultOriginBatch() {
        originLock.lock()
        defer { originLock.unlock() }
        if defaultOriginBatchCount > 0 {
            defaultOriginBatchCount -= 1
        }
        if defaultOriginBatchCount == 0 {
            fallbackProbeStarted = false
        }
    }

    /// Elects one probe for the overlapping default-origin batch. A peer returns false.
    private func claimFallbackLeader(failedOrigin: String) -> Bool {
        originLock.lock()
        defer { originLock.unlock() }
        guard failedOrigin == ServerConfig.defaultOrigin,
              activeOrigin == ServerConfig.defaultOrigin,
              !fallbackLeaderActive,
              !fallbackProbeStarted else {
            return false
        }
        fallbackProbeStarted = true
        fallbackLeaderActive = true
        return true
    }

    /// Snapshot published by the in-flight probe. Nil means the probe did not switch origin.
    private func waitForFallbackSettlement() async -> String? {
        await withCheckedContinuation { continuation in
            originLock.lock()
            if fallbackLeaderActive {
                fallbackWaiters.append(continuation)
                originLock.unlock()
                return
            }
            let settled = activeOrigin == ServerConfig.fallbackOrigin ? activeOrigin : nil
            originLock.unlock()
            continuation.resume(returning: settled)
        }
    }

    /// Only the elected probe calls this. The assignment is the sole write of `activeOrigin`.
    private func finishFallbackLeader(committed: Bool) {
        originLock.lock()
        if committed && activeOrigin == ServerConfig.defaultOrigin {
            activeOrigin = ServerConfig.fallbackOrigin
        }
        let settled = activeOrigin == ServerConfig.fallbackOrigin ? activeOrigin : nil
        fallbackLeaderActive = false
        let waiters = fallbackWaiters
        fallbackWaiters.removeAll()
        originLock.unlock()
        for waiter in waiters {
            waiter.resume(returning: settled)
        }
    }

    /// Lightweight 60-second background probe when `activeOrigin == ServerConfig.fallbackOrigin`
    /// that hits `ServerConfig.defaultOrigin + "/health"` and switches `activeOrigin` back to
    /// `ServerConfig.defaultOrigin` ONLY when HTTP status is 200.
    func maybeProbePrimary() {
        let now = Date().timeIntervalSince1970
        originLock.lock()
        guard activeOrigin == ServerConfig.fallbackOrigin,
              !primaryProbeInFlight,
              (now - lastPrimaryProbeAt) >= primaryProbeInterval else {
            originLock.unlock()
            return
        }
        primaryProbeInFlight = true
        lastPrimaryProbeAt = now
        originLock.unlock()

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runPrimaryHealthProbe()
        }
    }

    private func runPrimaryHealthProbe() async {
        defer {
            originLock.lock()
            primaryProbeInFlight = false
            originLock.unlock()
        }
        guard let healthURL = ServerConfig.url(for: "/health", origin: ServerConfig.defaultOrigin) else {
            return
        }
        var req = URLRequest(url: healthURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 6
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("KinnectiOS/\(ServerConfig.appVersion) (Build \(ServerConfig.buildNumber))", forHTTPHeaderField: "User-Agent")

        guard let (_, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return
        }

        var switchedBack = false
        originLock.lock()
        if activeOrigin == ServerConfig.fallbackOrigin {
            activeOrigin = ServerConfig.defaultOrigin
            fallbackProbeStarted = false
            switchedBack = true
        }
        originLock.unlock()

        if switchedBack {
            await MainActor.run {
                NativeSocketClient.shared.connectWithKeychainSession()
            }
        }
    }

    /// One idempotent transport failure probes `fallbackOrigin`. Peers wait for that result,
    /// then perform their own path on the published snapshot. They do not write `activeOrigin`
    /// and do not copy the default-origin cookie jar.
    private func resolveOriginForFallbackIfNeeded(
        failedOrigin: String,
        method: String,
        path: String,
        body: [String: Any]?,
        allowPrivacyAutoRetry: Bool
    ) async throws -> [String: Any] {
        if claimFallbackLeader(failedOrigin: failedOrigin) {
            var committed = false
            defer { finishFallbackLeader(committed: committed) }
            do {
                let result = try await performSingleRequest(
                    origin: ServerConfig.fallbackOrigin,
                    method: method,
                    path: path,
                    body: body,
                    allowPrivacyAutoRetry: allowPrivacyAutoRetry
                )
                committed = true
                return result
            } catch let fallbackErr as KinnectAPIError {
                if case .originUnavailable = fallbackErr {
                    committed = true
                }
                throw fallbackErr
            } catch {
                throw KinnectAPIError.networkError(L10n.tr("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn."))
            }
        }

        guard let settledOrigin = await waitForFallbackSettlement(), settledOrigin != failedOrigin else {
            throw KinnectAPIError.networkError(L10n.tr("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn."))
        }
        do {
            return try await performSingleRequest(
                origin: settledOrigin,
                method: method,
                path: path,
                body: body,
                allowPrivacyAutoRetry: allowPrivacyAutoRetry
            )
        } catch let error as KinnectAPIError {
            throw error
        } catch {
            throw KinnectAPIError.networkError(L10n.tr("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn."))
        }
    }

    private func performSingleRequest(
        origin: String,
        method: String,
        path: String,
        body: [String: Any]?,
        allowPrivacyAutoRetry: Bool
    ) async throws -> [String: Any] {
        guard let url = ServerConfig.url(for: path, origin: origin) else {
            throw KinnectAPIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue("KinnectiOS/\(ServerConfig.appVersion) (Build \(ServerConfig.buildNumber))", forHTTPHeaderField: "User-Agent")

        let cookieHeader = KeychainStore.shared.cookieJarHeader(for: origin)
        if !cookieHeader.isEmpty {
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        if method != "GET" && method != "HEAD" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload = body ?? [:]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw KinnectAPIError.networkError(L10n.tr("Phản hồi máy chủ không hợp lệ."))
        }

        KeychainStore.shared.ingestResponseHeaderFields(http.allHeaderFields, responseURL: url, origin: origin)

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        // Handle 428 Precondition Required (Explicit Privacy Consent needed - Apple Guideline 5.1.1)
        if http.statusCode == 428 {
            // Server PRIVACY_VERSION is a date string (e.g. "2026-10-29"); never coerce to Int.
            let version = (json["version"] as? String) ?? (json["version"] as? NSNumber)?.stringValue ?? ""
            let noticeText = (json["error"] as? String) ?? L10n.tr("Cần đồng ý điều khoản bảo vệ dữ liệu cá nhân trước khi thực hiện thao tác này.")
            await MainActor.run {
                AppState.shared.presentPrivacyConsent(version: version, notice: noticeText)
            }
            throw KinnectAPIError.serverError(status: 428, message: noticeText)
        }

        let basePath = path.components(separatedBy: "?").first ?? path
        if http.statusCode == 401
            && basePath != "/api/login"
            && basePath != "/api/auth/apple"
            && basePath != "/api/oauth/apple"
            && basePath != "/api/oauth/app-session"
            && basePath != "/api/remembered/login"
            && basePath != "/api/me/password"
            && basePath != "/api/recovery/email/start"
            && !basePath.hasPrefix("/api/me/2fa/") {
            let isUnauthenticatedFallback = (origin == ServerConfig.fallbackOrigin || snapshotOrigin() == ServerConfig.fallbackOrigin)
                && KeychainStore.shared.sessionCookie(for: ServerConfig.fallbackOrigin).isEmpty
            if isUnauthenticatedFallback {
                if method == "GET", let cached = cachedJSON(for: path) {
                    return cached
                }
                throw KinnectAPIError.originUnavailable
            }
            throw KinnectAPIError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            let msg = json["error"] as? String ?? (json["message"] as? String) ?? String(format: L10n.tr("Yêu cầu không thành công (mã %d)."), http.statusCode)
            if http.statusCode == 400 && ((json["requiresAgree18"] as? Bool) == true) {
                throw KinnectAPIError.requiresAgree18(msg)
            }
            throw KinnectAPIError.serverError(status: http.statusCode, message: msg)
        }

        if let userDict = json["user"] as? [String: Any],
           let uid = userDict["id"] as? String,
           !uid.isEmpty,
           (path == "/api/login" || path == "/api/register" || path == "/api/me") {
            KeychainStore.shared.saveAccountId(uid, for: origin)
        }

        if method == "GET" && isCacheableGET(path) {
            let uid = currentAccountId
            if !uid.isEmpty {
                AccountCache.shared.store(data, forKey: "json:\(path)", origin: origin, accountId: uid)
            }
        } else if method != "GET" && method != "HEAD" {
            evictRelatedCaches(for: path, origin: origin)
        }

        return json
    }

    private func evictRelatedCaches(for path: String, origin: String) {
        let uid = currentAccountId.isEmpty ? (AccountCache.shared.activeAccountId ?? "") : currentAccountId
        guard !uid.isEmpty else { return }
        let base = path.components(separatedBy: "?").first ?? path

        func evictKeys(_ keys: [String]) {
            for k in keys {
                AccountCache.shared.evict(forKey: "json:\(k)", origin: origin, accountId: uid)
                AccountCache.shared.evict(forKey: k, origin: origin, accountId: uid)
            }
        }

        if base == "/api/posts" || base.hasPrefix("/api/posts/") {
            evictKeys(["/api/posts?limit=25", "/api/posts", "/api/posts?user=\(uid)", "/api/me", "/api/users/\(uid)/posts", "feed_posts"])
            if base.hasPrefix("/api/posts/") {
                let parts = base.split(separator: "/")
                if parts.count >= 3 {
                    let postId = String(parts[2])
                    evictKeys(["/api/posts/\(postId)", "/api/posts/\(postId)/comments"])
                }
            }
        } else if base == "/api/stories" || base.hasPrefix("/api/stories/") {
            evictKeys(["/api/stories"])
        } else if base == "/api/shorts" || base.hasPrefix("/api/shorts/") {
            evictKeys(["/api/shorts", "/api/shorts?feed=for", "/api/shorts?feed=following", "/api/shorts?user=\(uid)", "shorts_feed_for", "shorts_feed_following"])
            if base.hasPrefix("/api/shorts/") {
                let parts = base.split(separator: "/")
                if parts.count >= 3 {
                    let shortId = String(parts[2])
                    evictKeys(["/api/shorts/\(shortId)", "/api/shorts/\(shortId)/comments"])
                }
            }
        } else if base.hasPrefix("/api/users/") && base.hasSuffix("/block") {
            evictKeys([
                "/api/blocks", "/api/conversations", "/api/friends",
                "/api/posts?limit=25", "/api/posts", "feed_posts",
                "/api/stories", "/api/shorts", "/api/shorts?feed=for", "/api/shorts?feed=following",
                "shorts_feed_for", "shorts_feed_following", "/api/discover"
            ])
        } else if base == "/api/me/avatar" || base == "/api/me/cover" {
            evictKeys(["/api/me", "/api/users/\(uid)", "profile_me"])
            AccountCache.shared.evict(forKey: "bin:/api/users/\(uid)/avatar", origin: origin, accountId: uid)
            AccountCache.shared.evict(forKey: "bin:/api/users/\(uid)/cover", origin: origin, accountId: uid)
            ImageMemoryCache.shared.clear()
        } else if base == "/api/me" || base.hasPrefix("/api/me/") {
            evictKeys(["/api/me", "profile_me"])
        } else if base.hasPrefix("/api/notifications") {
            evictKeys(["/api/notifications"])
        } else if base.hasPrefix("/api/friends")
            || base.hasPrefix("/api/friend-request")
            || base.hasSuffix("/friend-request")
            || base.contains("/friendship")
            || base.hasSuffix("/follow") {
            evictKeys(["/api/friends", "/api/friend-requests", "/api/friend-suggestions", "/api/discover", "/api/me", "feed_posts"])
        } else if base.hasPrefix("/api/groups") {
            evictKeys(["/api/groups", "/api/conversations"])
        } else if base.hasPrefix("/api/conversations") || base.hasPrefix("/api/chat-messages") || (base.hasPrefix("/api/users/") && base.contains("/messages")) {
            evictKeys(["/api/conversations"])
        } else if base.hasPrefix("/api/store") || base.hasPrefix("/api/wallet") {
            evictKeys(["/api/store", "/api/wallet", "/api/me"])
        }
        if base.contains("/private") {
            var privKeys = ["/api/me/private/requests", "/api/users/\(uid)/private"]
            if base.hasPrefix("/api/users/") {
                let parts = base.split(separator: "/")
                if parts.count >= 3 {
                    let targetId = String(parts[2])
                    privKeys.append("/api/users/\(targetId)/private")
                    privKeys.append("/api/users/\(targetId)")
                }
            }
            evictKeys(privKeys)
        }
    }

    func fetchBinaryData(path: String, maxAge: TimeInterval = 7 * 86400) async -> Data? {
        if path.hasPrefix("data:"),
           let commaIdx = path.firstIndex(of: ",") {
            let b64 = String(path[path.index(after: commaIdx)...])
            return Data(base64Encoded: b64)
        }
        let uid = currentAccountId
        let origin = snapshotOrigin()
        if origin == ServerConfig.fallbackOrigin {
            maybeProbePrimary()
        }
        let cacheKey = "bin:\(path)"
        if !uid.isEmpty, let cached = AccountCache.shared.load(forKey: cacheKey, maxAge: maxAge, origin: origin, accountId: uid) {
            return cached
        }
        guard let url = ServerConfig.url(for: path, origin: origin) else { return nil }
        var req = URLRequest(url: url)
        let cookieHeader = KeychainStore.shared.cookieJarHeader(for: origin)
        if !cookieHeader.isEmpty {
            req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              http.statusCode == 200,
              !data.isEmpty else {
            return nil
        }
        if !uid.isEmpty {
            AccountCache.shared.store(data, forKey: cacheKey, origin: origin, accountId: uid)
        }
        return data
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        return try await session.download(for: request)
    }

    func logoutAndWipe() async {
        _ = try? await request(method: "POST", path: "/api/logout", body: [:], isIdempotent: true, allowPrivacyAutoRetry: false)
        KeychainStore.shared.clearAll()
        AccountCache.shared.wipeAllCaches()
    }
}

enum KinnectAuthenticatedFile {
    static func fetch(path: String, fileExtension: String) async throws -> URL {
        if path.hasPrefix("file://"), let url = URL(string: path) {
            return url
        }
        let safeExt = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let cleanExt = safeExt.isEmpty ? "mp4" : safeExt
        let acct = KinnectAPIClient.shared.currentAccountId
        let accountScope = acct.isEmpty ? (AccountCache.shared.activeAccountId ?? "anon") : acct
        let digest = SHA256.hash(data: Data("\(accountScope)|\(path)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let safeKey = "media_\(digest).\(cleanExt)"
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(safeKey)

        if FileManager.default.fileExists(atPath: destination.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
           let size = attrs[.size] as? UInt64, size > 1024 {
            return destination
        }

        let origin = KinnectAPIClient.shared.mediaOrigin
        guard let remote = ServerConfig.url(for: path, origin: origin) else {
            throw KinnectAPIError.invalidURL
        }
        var request = URLRequest(url: remote)
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("KinnectiOS/\(ServerConfig.appVersion) (Build \(ServerConfig.buildNumber))", forHTTPHeaderField: "User-Agent")
        let cookie = KeychainStore.shared.cookieJarHeader(for: origin)
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (temporary, response) = try await KinnectAPIClient.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            throw KinnectAPIError.networkError(String(format: L10n.tr("Không tải được media (mã %d)."), (response as? HTTPURLResponse)?.statusCode ?? 0))
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return destination
    }
}
