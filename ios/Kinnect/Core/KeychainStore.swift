import Foundation
import Security

/// Native Keychain & Shared In-Memory Session Storage.
/// - When rememberMe = true: Session cookies & account IDs persist securely in Keychain across app restarts.
/// - When rememberMe = false: Session cookies & account IDs are held in memory for the active lifecycle only
///   (enabling HTTP calls, uploads, and WebSocket connection in the current session), while persistent Keychain
///   items and device cookies are wiped. Upon restart, the user returns cleanly to Login.
final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "app.kinnect.live.session.v2"
    private let lock = NSLock()

    // Shared In-Memory Session Store
    private var memorySessionCookie: [String: String] = [:]
    private var memoryDeviceCookie: [String: String] = [:]
    private var memoryAccountId: [String: String] = [:]
    private(set) var isPersistent: Bool = true

    private init() {
        let remembered = UserDefaults.standard.object(forKey: "kinnect_session_remembered") as? Bool ?? true
        self.isPersistent = remembered
    }

    func setRememberMe(_ remember: Bool, for origin: String = ServerConfig.defaultOrigin) {
        lock.lock()
        defer { lock.unlock() }
        self.isPersistent = remember
        let key = originKey(origin)

        if !remember {
            // Delete persistent items from Keychain for this origin
            deleteItemLocked(account: "session:\(key)")
            deleteItemLocked(account: "device:\(key)")
            deleteItemLocked(account: "uid:\(key)")

            // Clean HTTPCookieStorage to avoid leaking persistent session cookies across relaunch
            if let url = URL(string: origin) ?? URL(string: ServerConfig.defaultOrigin) {
                if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                    for cookie in cookies {
                        if cookie.name == "kinnect_session" || cookie.name == "kinnect_device" {
                            HTTPCookieStorage.shared.deleteCookie(cookie)
                        }
                    }
                }
            }
        } else {
            // Flush active in-memory session into Keychain
            if let s = memorySessionCookie[key], !s.isEmpty {
                setStringLocked(s, account: "session:\(key)")
            }
            if let d = memoryDeviceCookie[key], !d.isEmpty {
                setStringLocked(d, account: "device:\(key)")
            }
            if let u = memoryAccountId[key], !u.isEmpty {
                setStringLocked(u, account: "uid:\(key)")
            }
        }
    }

    func saveSessionCookie(_ value: String, for origin: String = ServerConfig.defaultOrigin) {
        let key = originKey(origin)
        lock.lock()
        memorySessionCookie[key] = value
        let persistent = isPersistent
        if persistent {
            setStringLocked(value, account: "session:\(key)")
        } else {
            deleteItemLocked(account: "session:\(key)")
        }
        lock.unlock()
    }

    func loadSessionCookie(for origin: String = ServerConfig.defaultOrigin) -> String {
        let key = originKey(origin)
        lock.lock()
        if let mem = memorySessionCookie[key], !mem.isEmpty {
            lock.unlock()
            return mem
        }
        let persistent = isPersistent
        if persistent {
            let val = getStringLocked(account: "session:\(key)") ?? ""
            if !val.isEmpty {
                memorySessionCookie[key] = val
            }
            lock.unlock()
            return val
        }
        lock.unlock()
        return ""
    }

    func saveDeviceCookie(_ value: String, for origin: String = ServerConfig.defaultOrigin) {
        let key = originKey(origin)
        lock.lock()
        memoryDeviceCookie[key] = value
        let persistent = isPersistent
        if persistent {
            setStringLocked(value, account: "device:\(key)")
        } else {
            deleteItemLocked(account: "device:\(key)")
        }
        lock.unlock()
    }

    func loadDeviceCookie(for origin: String = ServerConfig.defaultOrigin) -> String {
        let key = originKey(origin)
        lock.lock()
        if let mem = memoryDeviceCookie[key], !mem.isEmpty {
            lock.unlock()
            return mem
        }
        let persistent = isPersistent
        if persistent {
            let val = getStringLocked(account: "device:\(key)") ?? ""
            if !val.isEmpty {
                memoryDeviceCookie[key] = val
            }
            lock.unlock()
            return val
        }
        lock.unlock()
        return ""
    }

    func saveAccountId(_ userId: String, for origin: String = ServerConfig.defaultOrigin) {
        let key = originKey(origin)
        lock.lock()
        memoryAccountId[key] = userId
        let persistent = isPersistent
        if persistent {
            setStringLocked(userId, account: "uid:\(key)")
        } else {
            deleteItemLocked(account: "uid:\(key)")
        }
        lock.unlock()
    }

    func loadAccountId(for origin: String = ServerConfig.defaultOrigin) -> String {
        let key = originKey(origin)
        lock.lock()
        if let mem = memoryAccountId[key], !mem.isEmpty {
            lock.unlock()
            return mem
        }
        let persistent = isPersistent
        if persistent {
            let val = getStringLocked(account: "uid:\(key)") ?? ""
            if !val.isEmpty {
                memoryAccountId[key] = val
            }
            lock.unlock()
            return val
        }
        lock.unlock()
        return ""
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
                    clearSession(for: origin)
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
        let key = originKey(origin)
        lock.lock()
        memorySessionCookie.removeValue(forKey: key)
        memoryAccountId.removeValue(forKey: key)
        deleteItemLocked(account: "session:\(key)")
        deleteItemLocked(account: "uid:\(key)")
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        memorySessionCookie.removeAll()
        memoryDeviceCookie.removeAll()
        memoryAccountId.removeAll()
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

    private func setStringLocked(_ value: String, account: String) {
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

    private func getStringLocked(account: String) -> String? {
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

    private func deleteItemLocked(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
