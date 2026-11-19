import Foundation
#if DEBUG
import CryptoKit
import Security
#endif

enum KinnectAPIError: LocalizedError {
    case invalidURL
    case networkError(String)
    case serverError(status: Int, message: String)
    case serverMessage(String)
    case unauthorized
    case originSwitchUnauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.tr("Địa chỉ máy chủ không hợp lệ.")
        case .networkError(let msg):
            return L10n.tr(msg)
        case .serverError(_, let message):
            return L10n.tr(message)
        case .serverMessage(let message):
            return L10n.tr(message)
        case .unauthorized:
            return L10n.tr("Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.")
        case .originSwitchUnauthorized:
            return L10n.tr("Đang dùng máy chủ dự phòng. Vui lòng đăng nhập lại trên máy chủ này.")
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

    private init() {
        let config = URLSessionConfiguration.ephemeral
        var requestTimeout: TimeInterval = 18
        #if DEBUG
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--qa-request-timeout"),
           idx + 1 < args.count,
           let parsed = TimeInterval(args[idx + 1]),
           parsed >= 1, parsed <= 18 {
            requestTimeout = parsed
        }
        #endif
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = 45
        config.httpShouldSetCookies = false
        #if DEBUG
        if let idx = CommandLine.arguments.firstIndex(of: "--qa-leaf-sha256"),
           idx + 1 < CommandLine.arguments.count {
            let expectedHex = CommandLine.arguments[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if expectedHex.count == 64 {
                self.session = URLSession(configuration: config, delegate: QALocalhostPinDelegate(leafSha256: expectedHex), delegateQueue: nil)
            } else {
                self.session = URLSession(configuration: config)
            }
        } else {
            self.session = URLSession(configuration: config)
        }
        #else
        self.session = URLSession(configuration: config)
        #endif
    }

    var currentAccountId: String {
        return KeychainStore.shared.loadAccountId(for: snapshotOrigin())
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
        if base.hasPrefix("/api/users/") || base.hasPrefix("/api/groups/") || base.hasPrefix("/api/chat-preferences/") {
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
        if UIReviewFixture.isEnabled {
            return UIReviewFixture.mockResponse(for: path)
        }
        let bodyRequestId = body?["requestId"] as? String
        let carriesRequestId = !(bodyRequestId ?? "").isEmpty
        let safeToRetryOnFallback = isIdempotent ?? (method == "GET" || method == "HEAD" || (carriesRequestId && method != "POST"))
        let origin = snapshotOrigin()
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
                throw KinnectAPIError.networkError("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.")
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
                throw fallbackErr
            } catch {
                throw KinnectAPIError.networkError("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.")
            }
        }

        guard let settledOrigin = await waitForFallbackSettlement(), settledOrigin != failedOrigin else {
            throw KinnectAPIError.networkError("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.")
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
            throw KinnectAPIError.networkError("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.")
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
            throw KinnectAPIError.networkError("Phản hồi máy chủ không hợp lệ.")
        }

        KeychainStore.shared.ingestResponseHeaderFields(http.allHeaderFields, responseURL: url, origin: origin)

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        // Handle 428 Precondition Required (Explicit Privacy Consent needed - Apple Guideline 5.1.1)
        if http.statusCode == 428 {
            // Server PRIVACY_VERSION is a date string (e.g. "2026-10-29"); never coerce to Int.
            let version = (json["version"] as? String) ?? (json["version"] as? NSNumber)?.stringValue ?? ""
            let noticeText = (json["error"] as? String) ?? "Cần đồng ý điều khoản bảo vệ dữ liệu cá nhân trước khi thực hiện thao tác này."
            await MainActor.run {
                AppState.shared.presentPrivacyConsent(version: version, notice: noticeText)
            }
            throw KinnectAPIError.serverError(status: 428, message: noticeText)
        }

        if http.statusCode == 401 && path != "/api/login" && path != "/api/me/password" {
            if origin == ServerConfig.fallbackOrigin {
                throw KinnectAPIError.originSwitchUnauthorized
            }
            throw KinnectAPIError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            let msg = json["error"] as? String ?? (json["message"] as? String) ?? "Yêu cầu không thành công (mã \(http.statusCode))."
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
        }

        return json
    }

    func fetchBinaryData(path: String, maxAge: TimeInterval = 7 * 86400) async -> Data? {
        if path.hasPrefix("data:"),
           let commaIdx = path.firstIndex(of: ",") {
            let b64 = String(path[path.index(after: commaIdx)...])
            return Data(base64Encoded: b64)
        }
        let uid = currentAccountId
        let origin = snapshotOrigin()
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

    func logoutAndWipe() async {
        _ = try? await request(method: "POST", path: "/api/logout", body: [:], isIdempotent: true, allowPrivacyAutoRetry: false)
        KeychainStore.shared.clearAuthSessions()
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
        let safeKey = "media_" + path.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression).prefix(64) + ".\(cleanExt)"
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
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw KinnectAPIError.networkError("Không tải được media (mã \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}

#if DEBUG
/// Strictly scoped loopback-only TLS leaf SHA-256 pin delegate for QA CI runs (`--qa-leaf-sha256`).
/// Accepts ONLY 127.0.0.1/localhost when the presented leaf certificate DER SHA-256 matches exactly.
private final class QALocalhostPinDelegate: NSObject, URLSessionDelegate {
    private let leafSha256: String
    init(leafSha256: String) {
        self.leafSha256 = leafSha256
    }
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = space.serverTrust,
              space.host == "127.0.0.1" || space.host == "localhost" else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let der = SecCertificateCopyData(leaf) as Data
        let hex = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        if hex == leafSha256 {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
#endif
