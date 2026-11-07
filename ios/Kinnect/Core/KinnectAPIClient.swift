import Foundation

enum KinnectAPIError: LocalizedError {
    case invalidURL
    case networkError(String)
    case serverError(status: Int, message: String)
    case serverMessage(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Địa chỉ máy chủ không hợp lệ."
        case .networkError(let msg):
            return msg
        case .serverError(_, let message):
            return message
        case .serverMessage(let message):
            return message
        case .unauthorized:
            return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
        }
    }
}

/// Native async/await HTTP client with Keychain cookie management, account-scoped caching,
/// CSRF Origin protection, and safe PC -> Cloud fallback without duplicating non-idempotent writes.
final class KinnectAPIClient {
    static let shared = KinnectAPIClient()

    private let session: URLSession
    private var activeOrigin: String = ServerConfig.currentOrigin

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 45
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)
    }

    var currentAccountId: String {
        return KeychainStore.shared.loadAccountId(for: ServerConfig.defaultOrigin)
    }

    private func isCacheableGET(_ path: String) -> Bool {
        let base = path.components(separatedBy: "?").first ?? path
        let allowedExact: Set<String> = [
            "/api/me", "/api/posts", "/api/stories", "/api/discover", "/api/shorts",
            "/api/conversations", "/api/groups", "/api/notifications",
            "/api/friends", "/api/friend-requests", "/api/friend-suggestions",
            "/api/store", "/api/wallet", "/api/live/gifts"
        ]
        if allowedExact.contains(base) { return true }
        if base.hasPrefix("/api/users/") || base.hasPrefix("/api/groups/") || base.hasPrefix("/api/chat-preferences/") {
            return true
        }
        return false
    }

    func cachedJSON(for path: String) -> [String: Any]? {
        let uid = currentAccountId
        guard !uid.isEmpty, isCacheableGET(path),
              let data = AccountCache.shared.load(forKey: "json:\(path)", origin: activeOrigin, accountId: uid),
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
        let isIdempotent = (method == "GET" || method == "HEAD" || (requestId != nil && !requestId!.isEmpty))
        return try await request(
            method: method,
            path: path,
            body: payload,
            isIdempotent: isIdempotent
        )
    }

    /// Performs an authenticated HTTP request.
    /// - Parameter isIdempotent: Only true for GET/HEAD or requests carrying an explicit idempotency `requestId`.
    ///   Non-idempotent writes never auto-retry across PC/Cloud fallback to prevent duplicate transactions.
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
        let safeToRetryOnFallback = isIdempotent ?? (method == "GET" || method == "HEAD" || (body?["requestId"] as? String != nil))
        do {
            return try await performSingleRequest(
                origin: activeOrigin,
                method: method,
                path: path,
                body: body,
                allowPrivacyAutoRetry: allowPrivacyAutoRetry
            )
        } catch let error as KinnectAPIError {
            throw error
        } catch {
            // Transport / connection error: only fall back to cloud gateway if the operation is idempotent!
            if safeToRetryOnFallback && activeOrigin == ServerConfig.defaultOrigin {
                do {
                    let result = try await performSingleRequest(
                        origin: ServerConfig.fallbackOrigin,
                        method: method,
                        path: path,
                        body: body,
                        allowPrivacyAutoRetry: allowPrivacyAutoRetry
                    )
                    activeOrigin = ServerConfig.fallbackOrigin
                    return result
                } catch let fallbackErr as KinnectAPIError {
                    throw fallbackErr
                } catch {
                    throw KinnectAPIError.networkError("Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.")
                }
            }
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
        let cacheKey = "bin:\(path)"
        if !uid.isEmpty, let cached = AccountCache.shared.load(forKey: cacheKey, maxAge: maxAge, origin: activeOrigin, accountId: uid) {
            return cached
        }
        guard let url = ServerConfig.url(for: path, origin: activeOrigin) else { return nil }
        var req = URLRequest(url: url)
        let cookieHeader = KeychainStore.shared.cookieJarHeader(for: activeOrigin)
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
            AccountCache.shared.store(data, forKey: cacheKey, origin: activeOrigin, accountId: uid)
        }
        return data
    }

    func logoutAndWipe() async {
        _ = try? await request(method: "POST", path: "/api/logout", body: [:], isIdempotent: true, allowPrivacyAutoRetry: false)
        KeychainStore.shared.clearAll()
        AccountCache.shared.wipeAllCaches()
    }
}
