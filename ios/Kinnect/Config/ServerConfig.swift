import Foundation

enum ServerConfig {
    static let defaultOrigin = "https://app.kinnect.io.vn"
    static let fallbackOrigin = "https://kinnect-allocation.vuanh97nd.workers.dev"
    static let appVersion = "1.2.12"
    static let buildNumber = "124"
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
        if let components = URLComponents(string: path), components.scheme != nil {
            guard components.scheme?.lowercased() == "https", components.host?.isEmpty == false,
                  components.user == nil, components.password == nil else { return nil }
            return components.url
        }
        guard let normalizedOrigin = normalize(origin) else { return nil }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        return URL(string: normalizedOrigin + normalizedPath)
    }

    static func matchesOrigin(_ url: URL, origin: String) -> Bool {
        guard let expected = URLComponents(string: origin),
              let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              expected.scheme?.lowercased() == "https", actual.scheme?.lowercased() == "https",
              let expectedHost = expected.host?.lowercased(), let actualHost = actual.host?.lowercased(),
              expectedHost == actualHost, expected.user == nil, expected.password == nil,
              actual.user == nil, actual.password == nil else { return false }
        return (expected.port ?? 443) == (actual.port ?? 443)
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
