import Foundation

/// Playback intent for a Shorts clip. Mute never changes pause, and a paused
/// clip does not start playing because the mute flag changed.
struct ShortsPlaybackState: Equatable {
    var index: Int
    var userPaused: Bool
    var muted: Bool

    var playing: Bool { !userPaused }

    mutating func togglePause() {
        userPaused.toggle()
    }

    mutating func toggleMute() {
        muted.toggle()
    }

    mutating func swipe(to newIndex: Int) {
        guard newIndex != index else { return }
        index = newIndex
        userPaused = false
    }
}

struct GiftQuote {
    let unitCoins: Int
    let quantity: Int

    var total: Int { unitCoins * quantity }
    var needsConfirmation: Bool { total >= 1000 }
}

enum MusicPickerQuery {
    static func matches(title: String, artist: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return (title + " " + artist).localizedCaseInsensitiveContains(trimmed)
    }
}

enum AppLanguageStore {
    /// Local only. The server does not store this preference.
    static let defaultsKey = "kinnect_app_language"

    static func resolve(saved: String, deviceLanguage: String) -> String {
        switch saved {
        case "vi":
            return "vi"
        case "en":
            return "en"
        default:
            return deviceLanguage.lowercased().hasPrefix("vi") ? "vi" : "en"
        }
    }
}
