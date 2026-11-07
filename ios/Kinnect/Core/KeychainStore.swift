import Foundation
import Security

/// Native Keychain storage for session and remembered-device cookies.
/// Credentials never touch plain UserDefaults or logs.
final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "app.kinnect.live.session.v2"
    private let lock = NSLock()

    private init() {}

    func saveSessionCookie(_ value: String, for origin: String = ServerConfig.defaultOrigin) {
        setString(value, account: "session:\(originKey(origin))")
    }

    func loadSessionCookie(for origin: String = ServerConfig.defaultOrigin) -> String {
        return getString(account: "session:\(originKey(origin))") ?? ""
    }

    func saveDeviceCookie(_ value: String, for origin: String = ServerConfig.defaultOrigin) {
        setString(value, account: "device:\(originKey(origin))")
    }

    func loadDeviceCookie(for origin: String = ServerConfig.defaultOrigin) -> String {
        return getString(account: "device:\(originKey(origin))") ?? ""
    }

    func saveAccountId(_ userId: String, for origin: String = ServerConfig.defaultOrigin) {
        setString(userId, account: "uid:\(originKey(origin))")
    }

    func loadAccountId(for origin: String = ServerConfig.defaultOrigin) -> String {
        return getString(account: "uid:\(originKey(origin))") ?? ""
    }

    func cookieJarHeader(for origin: String = ServerConfig.defaultOrigin) -> String {
        let session = loadSessionCookie(for: origin)
        let device = loadDeviceCookie(for: origin)
        return [session, device].filter { !$0.isEmpty }.joined(separator: "; ")
    }

    func ingestResponseHeaderFields(_ headers: [AnyHashable: Any], responseURL: URL, origin: String = ServerConfig.defaultOrigin) {
        var stringHeaders: [String: String] = [:]
        for (k, v) in headers {
            if let ks = k as? String, let vs = v as? String {
                stringHeaders[ks] = vs
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: responseURL)
        for cookie in cookies {
            if cookie.name == "kinnect_session" {
                if cookie.value.isEmpty || (cookie.expiresDate != nil && cookie.expiresDate! <= Date()) {
                    deleteItem(account: "session:\(originKey(origin))")
                } else {
                    saveSessionCookie("kinnect_session=\(cookie.value)", for: origin)
                }
            } else if cookie.name == "kinnect_device" {
                if !cookie.value.isEmpty {
                    saveDeviceCookie("kinnect_device=\(cookie.value)", for: origin)
                }
            }
        }
    }

    func clearSession(for origin: String = ServerConfig.defaultOrigin) {
        deleteItem(account: "session:\(originKey(origin))")
        deleteItem(account: "uid:\(originKey(origin))")
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func originKey(_ origin: String) -> String {
        if origin == ServerConfig.fallbackOrigin {
            return ServerConfig.defaultOrigin
        }
        return ServerConfig.normalize(origin) ?? ServerConfig.defaultOrigin
    }

    private func setString(_ value: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = value.data(using: .utf8) else { return }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func getString(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteItem(account: String) {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
