import CryptoKit
import Foundation

/// Account-scoped cache for JSON snapshots and binary media.
/// Scoped by SHA256(origin + "|" + accountId) so switching or logging out never leaks data across accounts.
final class AccountCache {
    static let shared = AccountCache()

    private let memoryCache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "app.kinnect.live.cache", qos: .utility)
    private let activeAccountDefaultsKey = "kinnect.active.account.id"

    private var rootDirectory: URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("kinnect-native-v2", isDirectory: true)
    }

    private init() {
        memoryCache.totalCostLimit = 32 * 1024 * 1024
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    var activeAccountId: String? {
        let uid = UserDefaults.standard.string(forKey: activeAccountDefaultsKey) ?? KeychainStore.shared.loadAccountId(for: ServerConfig.defaultOrigin)
        return uid.isEmpty ? nil : uid
    }

    func setActiveAccount(_ accountId: String) {
        UserDefaults.standard.set(accountId, forKey: activeAccountDefaultsKey)
        KeychainStore.shared.saveAccountId(accountId, for: ServerConfig.defaultOrigin)
    }

    func saveJSONObject(_ object: Any, forKey key: String, accountId: String) {
        guard !accountId.isEmpty,
              JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        store(data, forKey: key, origin: ServerConfig.currentOrigin, accountId: accountId)
    }

    func loadJSONObject<T>(forKey key: String, accountId: String) -> T? {
        guard !accountId.isEmpty,
              let data = load(forKey: key, origin: ServerConfig.currentOrigin, accountId: accountId),
              let obj = try? JSONSerialization.jsonObject(with: data) as? T else {
            return nil
        }
        return obj
    }

    private func scopeDirectory(origin: String, accountId: String) -> URL? {
        guard !accountId.isEmpty else { return nil }
        let canonicalOrigin = (origin == ServerConfig.fallbackOrigin) ? ServerConfig.defaultOrigin : origin
        let digest = SHA256.hash(data: Data("\(canonicalOrigin)|\(accountId)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let dir = rootDirectory.appendingPathComponent(digest, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileKey(_ key: String) -> String {
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func store(_ data: Data, forKey key: String, origin: String = ServerConfig.currentOrigin, accountId: String) {
        guard !accountId.isEmpty else { return }
        let memKey = "\(origin)|\(accountId)|\(key)" as NSString
        memoryCache.setObject(data as NSData, forKey: memKey, cost: data.count)

        queue.async { [weak self] in
            guard let self = self,
                  let dir = self.scopeDirectory(origin: origin, accountId: accountId) else { return }
            let target = dir.appendingPathComponent(self.fileKey(key))
            try? data.write(to: target, options: .atomic)
        }
    }

    func load(forKey key: String, maxAge: TimeInterval = 7 * 86400, origin: String = ServerConfig.currentOrigin, accountId: String) -> Data? {
        guard !accountId.isEmpty else { return nil }
        let memKey = "\(origin)|\(accountId)|\(key)" as NSString
        if let cached = memoryCache.object(forKey: memKey) {
            return cached as Data
        }
        guard let dir = scopeDirectory(origin: origin, accountId: accountId) else { return nil }
        let target = dir.appendingPathComponent(fileKey(key))
        guard let attrs = try? fileManager.attributesOfItem(atPath: target.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) <= maxAge,
              let data = try? Data(contentsOf: target) else {
            return nil
        }
        memoryCache.setObject(data as NSData, forKey: memKey, cost: data.count)
        return data
    }

    func evict(forKey key: String, origin: String = ServerConfig.currentOrigin, accountId: String) {
        guard !accountId.isEmpty else { return }
        let memKey = "\(origin)|\(accountId)|\(key)" as NSString
        memoryCache.removeObject(forKey: memKey)
        queue.async { [weak self] in
            guard let self = self,
                  let dir = self.scopeDirectory(origin: origin, accountId: accountId) else { return }
            let target = dir.appendingPathComponent(self.fileKey(key))
            try? self.fileManager.removeItem(at: target)
        }
    }

    func wipeAllCaches() {
        UserDefaults.standard.removeObject(forKey: activeAccountDefaultsKey)
        memoryCache.removeAllObjects()
        queue.sync {
            try? fileManager.removeItem(at: rootDirectory)
            try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
    }
}
