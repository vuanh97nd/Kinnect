import Foundation
import SwiftUI

// MARK: - Supported App Languages
enum AppLanguage: String, CaseIterable, Identifiable {
    case vi = "vi"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vi: return "Tiếng Việt"
        case .en: return "English"
        }
    }

    var shortLabel: String {
        switch self {
        case .vi: return "VI"
        case .en: return "EN"
        }
    }

    var locale: Locale {
        return Locale(identifier: rawValue)
    }
}

// MARK: - App-wide Localization Manager
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private let userDefaultsKey = "kinnect_app_language"

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: userDefaultsKey)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            // Default to device preferred language if English, otherwise Vietnamese fallback
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "vi"
            if preferred.starts(with: "en") {
                self.currentLanguage = .en
            } else {
                self.currentLanguage = .vi
            }
        }
    }

    func setLanguage(_ lang: AppLanguage) {
        withAnimation(.easeInOut(duration: 0.2)) {
            self.currentLanguage = lang
        }
    }

    func toggle() {
        setLanguage(currentLanguage == .vi ? .en : .vi)
    }

    // MARK: - Dictionary Translations
    private let translations: [String: [AppLanguage: String]] = [
        // Welcome & Auth
        "Sống đúng mình.": [
            .vi: "Sống đúng mình.",
            .en: "Live authentically."
        ],
        "Kết nối đúng gu.\nSống đúng mình.": [
            .vi: "Kết nối đúng gu.\nSống đúng mình.",
            .en: "Connect with your vibe.\nLive authentically."
        ],
        "Trang chủ": [
            .vi: "Trang chủ",
            .en: "Home"
        ],
        "Về trang giới thiệu": [
            .vi: "Về trang giới thiệu",
            .en: "Back to intro"
        ],
        "Ngôn ngữ ứng dụng": [
            .vi: "Ngôn ngữ ứng dụng",
            .en: "App Language"
        ],
        "Tiếng Việt / English": [
            .vi: "Tiếng Việt / English",
            .en: "English / Tiếng Việt"
        ],
        "Chào bạn trở lại!": [
            .vi: "Chào bạn trở lại!",
            .en: "Welcome back!"
        ],
        "Bắt đầu kết nối của bạn.": [
            .vi: "Bắt đầu kết nối của bạn.",
            .en: "Start connecting."
        ],
        "Đăng nhập để tiếp tục những kết nối của bạn.": [
            .vi: "Đăng nhập để tiếp tục những kết nối của bạn.",
            .en: "Log in to continue your connections."
        ],
        "Tạo tài khoản để chia sẻ và gặp người cùng tần số.": [
            .vi: "Tạo tài khoản để chia sẻ và gặp người cùng tần số.",
            .en: "Create an account to share and meet your tribe."
        ],
        "Tên đăng nhập": [
            .vi: "Tên đăng nhập",
            .en: "Username"
        ],
        "Email hoặc tên đăng nhập": [
            .vi: "Email hoặc tên đăng nhập",
            .en: "Email or username"
        ],
        "Tên hiển thị": [
            .vi: "Tên hiển thị",
            .en: "Display name"
        ],
        "Họ và tên": [
            .vi: "Họ và tên",
            .en: "Full name"
        ],
        "Mật khẩu (từ 6 ký tự)": [
            .vi: "Mật khẩu (từ 6 ký tự)",
            .en: "Password (6+ chars)"
        ],
        "Mật khẩu": [
            .vi: "Mật khẩu",
            .en: "Password"
        ],
        "Ghi nhớ": [
            .vi: "Ghi nhớ",
            .en: "Remember me"
        ],
        "Ghi nhớ đăng nhập": [
            .vi: "Ghi nhớ đăng nhập",
            .en: "Remember login"
        ],
        "Quên mật khẩu?": [
            .vi: "Quên mật khẩu?",
            .en: "Forgot password?"
        ],
        "Đăng nhập": [
            .vi: "Đăng nhập",
            .en: "Log In"
        ],
        "Tạo tài khoản": [
            .vi: "Tạo tài khoản",
            .en: "Create Account"
        ],
        "Tạo tài khoản mới": [
            .vi: "Tạo tài khoản mới",
            .en: "Create New Account"
        ],
        "Bắt đầu kết nối": [
            .vi: "Bắt đầu kết nối",
            .en: "Get Started"
        ],
        "Dành cho người từ 18 tuổi · Minh họa tính năng": [
            .vi: "Dành cho người từ 18 tuổi · Minh họa tính năng",
            .en: "For ages 18+ · Feature preview"
        ],
        "Tôi đủ 18 tuổi và đồng ý Quy tắc cộng đồng": [
            .vi: "Tôi đủ 18 tuổi và đồng ý Quy tắc cộng đồng",
            .en: "I am 18+ and agree to Community Guidelines"
        ],
        "Tôi xác nhận từ 18 tuổi trở lên": [
            .vi: "Tôi xác nhận từ 18 tuổi trở lên",
            .en: "I confirm that I am 18 years or older"
        ],
        "Tôi đồng ý với Điều khoản & Chính sách quyền riêng tư": [
            .vi: "Tôi đồng ý với Điều khoản & Chính sách quyền riêng tư",
            .en: "I agree to Terms & Privacy Policy"
        ],
        "Mới đến Kinnect?": [
            .vi: "Mới đến Kinnect?",
            .en: "New to Kinnect?"
        ],
        "Đã có tài khoản?": [
            .vi: "Đã có tài khoản?",
            .en: "Already have an account?"
        ],
        "Đã có tài khoản? Đăng nhập": [
            .vi: "Đã có tài khoản? Đăng nhập",
            .en: "Already have an account? Log In"
        ],
        "Chưa có tài khoản? Đăng ký ngay": [
            .vi: "Chưa có tài khoản? Đăng ký ngay",
            .en: "Don't have an account? Sign up now"
        ],
        "Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng.": [
            .vi: "Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng.",
            .en: "Continuing means you agree to Community Guidelines."
        ],
        "hoặc tiếp tục với mật khẩu": [
            .vi: "hoặc tiếp tục với mật khẩu",
            .en: "or continue with password"
        ],
        "Tiếp tục với Google": [
            .vi: "Tiếp tục với Google",
            .en: "Continue with Google"
        ],
        "Tiếp tục với Facebook": [
            .vi: "Tiếp tục với Facebook",
            .en: "Continue with Facebook"
        ],
        "Đăng nhập bằng Apple": [
            .vi: "Đăng nhập bằng Apple",
            .en: "Sign in with Apple"
        ],
        "Khôi phục tài khoản": [
            .vi: "Khôi phục tài khoản",
            .en: "Account Recovery"
        ],
        "Tên đăng nhập hoặc email khôi phục": [
            .vi: "Tên đăng nhập hoặc email khôi phục",
            .en: "Username or recovery email"
        ],
        "Gửi mã": [
            .vi: "Gửi mã",
            .en: "Send Code"
        ],
        "Mã xác minh": [
            .vi: "Mã xác minh",
            .en: "Verification Code"
        ],
        "Mật khẩu mới": [
            .vi: "Mật khẩu mới",
            .en: "New Password"
        ],
        "Đặt lại mật khẩu": [
            .vi: "Đặt lại mật khẩu",
            .en: "Reset Password"
        ],

        // Tabs
        "Bảng tin": [
            .vi: "Bảng tin",
            .en: "Feed"
        ],
        "Khám phá": [
            .vi: "Khám phá",
            .en: "Discover"
        ],
        "Video": [
            .vi: "Video",
            .en: "Shorts"
        ],
        "Tin nhắn": [
            .vi: "Tin nhắn",
            .en: "Messages"
        ],
        "Cá nhân": [
            .vi: "Cá nhân",
            .en: "Profile"
        ],

        // Studio & Media Editor
        "Thoát": [
            .vi: "Thoát",
            .en: "Exit"
        ],
        "Lưu về máy": [
            .vi: "Lưu về máy",
            .en: "Save to device"
        ],
        "Dùng ảnh": [
            .vi: "Dùng ảnh",
            .en: "Use photo"
        ],
        "Đăng": [
            .vi: "Đăng",
            .en: "Post"
        ],
        "Hoàn tác": [
            .vi: "Hoàn tác",
            .en: "Undo"
        ],
        "Làm lại": [
            .vi: "Làm lại",
            .en: "Redo"
        ],
        "Giữ xem gốc": [
            .vi: "Giữ xem gốc",
            .en: "Hold for original"
        ],
        "Vừa khung": [
            .vi: "Vừa khung",
            .en: "Fit frame"
        ],
        "Cắt & xoay": [
            .vi: "Cắt & xoay",
            .en: "Crop & Rotate"
        ],
        "Điều chỉnh": [
            .vi: "Điều chỉnh",
            .en: "Adjust"
        ],
        "Làm mịn": [
            .vi: "Làm mịn",
            .en: "Smooth"
        ],
        "Làm đẹp": [
            .vi: "Làm đẹp",
            .en: "Beauty"
        ],
        "Độ sáng": [
            .vi: "Độ sáng",
            .en: "Brightness"
        ],
        "Tương phản": [
            .vi: "Tương phản",
            .en: "Contrast"
        ],
        "Độ rực màu": [
            .vi: "Độ rực màu",
            .en: "Saturation"
        ],
        "Nhiệt độ màu": [
            .vi: "Nhiệt độ màu",
            .en: "Warmth"
        ],
        "Mức làm mịn": [
            .vi: "Mức làm mịn",
            .en: "Smooth level"
        ],
        "Đặt lại màu": [
            .vi: "Đặt lại màu",
            .en: "Reset colors"
        ],
        "Xoay 90°": [
            .vi: "Xoay 90°",
            .en: "Rotate 90°"
        ],
        "Lật ảnh": [
            .vi: "Lật ảnh",
            .en: "Flip"
        ],
        "Ảnh gốc": [
            .vi: "Ảnh gốc",
            .en: "Original"
        ],

        // Settings & General
        "Cài đặt & riêng tư": [
            .vi: "Cài đặt & riêng tư",
            .en: "Settings & Privacy"
        ],
        "Ngôn ngữ": [
            .vi: "Ngôn ngữ",
            .en: "Language"
        ],
        "Đổi mật khẩu": [
            .vi: "Đổi mật khẩu",
            .en: "Change Password"
        ],
        "Người dùng đã chặn": [
            .vi: "Người dùng đã chặn",
            .en: "Blocked Users"
        ],
        "Xóa tài khoản": [
            .vi: "Xóa tài khoản",
            .en: "Delete Account"
        ],
        "Đăng xuất": [
            .vi: "Đăng xuất",
            .en: "Log Out"
        ],
        "Đóng": [
            .vi: "Đóng",
            .en: "Close"
        ],
        "Áp dụng": [
            .vi: "Áp dụng",
            .en: "Apply"
        ],
        "Hủy": [
            .vi: "Hủy",
            .en: "Cancel"
        ]
    ]

    func tr(_ key: String) -> String {
        if let entry = translations[key], let val = entry[currentLanguage] {
            return val
        }
        return key
    }
}

// MARK: - Global Convenience Helper
enum L10n {
    static func tr(_ key: String) -> String {
        LocalizationManager.shared.tr(key)
    }
}

// MARK: - Compact Language Selector Button
struct KinnectLanguageButton: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var showLanguageSheet = false

    var body: some View {
        Button {
            showLanguageSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.caption.weight(.medium))
                Text(loc.currentLanguage == .vi ? "VI / EN" : "EN / VI")
                    .font(.caption2.bold())
            }
            .foregroundColor(KinnectTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(KinnectTheme.surfaceElevated)
                    .overlay(Capsule().stroke(KinnectTheme.border, lineWidth: 1))
            )
        }
        .accessibilityLabel(L10n.tr("Ngôn ngữ ứng dụng"))
        .confirmationDialog(
            L10n.tr("Ngôn ngữ ứng dụng"),
            isPresented: $showLanguageSheet,
            titleVisibility: .visible
        ) {
            Button("Tiếng Việt") {
                loc.setLanguage(.vi)
            }
            Button("English") {
                loc.setLanguage(.en)
            }
            Button(L10n.tr("Đóng"), role: .cancel) {}
        }
    }
}
