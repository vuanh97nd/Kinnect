import Foundation

enum KinnectWriteBody {
    static func post(text: String, category: String, visibility: String = "public", mediaDataURL: String) -> [String: Any] {
        var payload: [String: Any] = [
            "body": text,
            "visibility": visibility,
            "category": category
        ]
        if !mediaDataURL.isEmpty {
            payload["media"] = mediaDataURL
        }
        return payload
    }

    static func story(text: String, colorHex: String, mediaDataURL: String) -> [String: Any] {
        var payload: [String: Any] = [
            "body": text,
            "background": storyBackground(hex: colorHex)
        ]
        if !mediaDataURL.isEmpty {
            payload["media"] = mediaDataURL
        }
        return payload
    }

    static func shortVideo(caption: String, dataURL: String) -> [String: Any] {
        [
            "caption": caption,
            "data": dataURL
        ]
    }

    static func comment(_ text: String) -> [String: Any] {
        ["body": text]
    }

    static func packageBuy(productId: String, priceCoins: Int, requestId: String, coinSource: String) -> [String: Any] {
        [
            "productId": productId,
            "priceCoins": priceCoins,
            "requestId": requestId,
            "coinSource": coinSource
        ]
    }

    static func packageApply(productId: String) -> [String: Any] {
        ["productId": productId]
    }

    static func packageRequestId() -> String {
        "pkg_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func storyBackground(hex: String) -> String {
        switch hex.uppercased() {
        case "#059669", "#047857":
            return "forest"
        case "#2563EB", "#0EA5E9", "#38BDF8":
            return "ocean"
        case "#D97706", "#F59E0B", "#EC4899":
            return "sunset"
        default:
            return "purple"
        }
    }
}
