import Foundation

/// Client-side password change rules. A failure never reaches the network.
struct PasswordChangeDecision: Equatable {
    let message: String?
    let sendsToServer: Bool
}

enum PasswordChangeValidation {
    static func evaluate(current: String, next: String, confirm: String) -> PasswordChangeDecision {
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PasswordChangeDecision(message: "Vui lòng nhập mật khẩu hiện tại.", sendsToServer: false)
        }
        if next.count < 6 {
            return PasswordChangeDecision(message: "Mật khẩu mới phải có ít nhất 6 ký tự.", sendsToServer: false)
        }
        if next.count > 128 {
            return PasswordChangeDecision(message: "Mật khẩu mới cần 6–128 ký tự.", sendsToServer: false)
        }
        if confirm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PasswordChangeDecision(message: "Vui lòng nhập lại mật khẩu mới.", sendsToServer: false)
        }
        if confirm != next {
            return PasswordChangeDecision(message: "Mật khẩu nhập lại không khớp.", sendsToServer: false)
        }
        return PasswordChangeDecision(message: nil, sendsToServer: true)
    }
}

/// Records the body that would be posted. Fixture mode uses this instead of the network.
enum PasswordTransportSpy {
    struct Attempt: Equatable {
        let current: String
        let next: String
    }

    static var attempts: [Attempt] = []

    static func reset() {
        attempts = []
    }

    static func record(current: String, next: String) {
        attempts.append(Attempt(current: current, next: next))
    }
}
