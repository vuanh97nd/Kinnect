import Foundation

enum ServerConfig {
    static let defaultOrigin = "https://app.kinnect.io.vn"
    static let fallbackOrigin = "https://kinnect-allocation.vuanh97nd.workers.dev"
    static let appVersion = "1.2.12"
    static let buildNumber = "118"
    static let bundleId = "app.kinnect.live"

    private static let savedOriginKey = "kinnect.server.origin"

    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              (components.path.isEmpty || components.path == "/") else {
            return nil
        }
        if let port = components.port, port != 443 {
            guard (1...65535).contains(port) else { return nil }
            return "https://\(host):\(port)"
        }
        return "https://\(host)"
    }

    static var currentOrigin: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: savedOriginKey),
               let normalized = normalize(saved) {
                return normalized
            }
            return defaultOrigin
        }
        set {
            if let normalized = normalize(newValue) {
                UserDefaults.standard.set(normalized, forKey: savedOriginKey)
            }
        }
    }

    static func url(for path: String, origin: String = currentOrigin) -> URL? {
        if path.hasPrefix("https://") || path.hasPrefix("http://") {
            return URL(string: path)
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        return URL(string: origin + normalizedPath)
    }

    static func resolveURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return url(for: trimmed)
    }

    static var webSocketURL: URL {
        let wsBase = currentOrigin.replacingOccurrences(of: "https://", with: "wss://")
        return URL(string: wsBase + "/") ?? URL(string: "wss://app.kinnect.io.vn/")!
    }
}
