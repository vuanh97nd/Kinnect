import Foundation

enum ServerConfig {
    static let defaultOrigin = "https://app.kinnect.io.vn"
    static let fallbackOrigin = "https://kinnect-allocation.vuanh97nd.workers.dev"
    static let appVersion = "1.2.12"
    static let buildNumber = "118"

    private static let savedOriginKey = "kinnect.server.origin"

    static var currentOrigin: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: savedOriginKey),
               let url = URL(string: saved),
               url.scheme?.lowercased() == "https",
               url.host != nil {
                return saved
            }
            return defaultOrigin
        }
        set {
            UserDefaults.standard.set(newValue, forKey: savedOriginKey)
        }
    }

    static var mainAppURL: URL {
        return URL(string: currentOrigin + "/v2.html") ?? URL(string: defaultOrigin)!
    }

    static var webSocketURL: URL {
        let wsString = currentOrigin.replacingOccurrences(of: "https://", with: "wss://") + "/"
        return URL(string: wsString) ?? URL(string: "wss://app.kinnect.io.vn/")!
    }
}
