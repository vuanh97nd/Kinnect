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
        if UIReviewFixture.isEnabled {
            self.currentLanguage = (UIReviewFixture.activeScreen?.hasSuffix("-en") == true) ? .en : .vi
        } else if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
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
        // Welcome & Intro
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
        "Bắt đầu kết nối": [
            .vi: "Bắt đầu kết nối",
            .en: "Get Started"
        ],
        "Dành cho người từ 18 tuổi · Minh họa tính năng": [
            .vi: "Dành cho người từ 18 tuổi · Minh họa tính năng",
            .en: "Ages 18+ · Feature Preview"
        ],
        "Dành cho bạn": [
            .vi: "Dành cho bạn",
            .en: "For you"
        ],
        "Đang theo dõi": [
            .vi: "Đang theo dõi",
            .en: "Following"
        ],
        "Hồ sơ minh họa": [
            .vi: "Hồ sơ minh họa",
            .en: "Sample profile"
        ],
        "Live": [
            .vi: "Live",
            .en: "Live"
        ],
        "Điện thoại minh họa luân phiên các tính năng Bảng tin, Khám phá, Video và Live. Chạm để chuyển tính năng.": [
            .vi: "Điện thoại minh họa luân phiên các tính năng Bảng tin, Khám phá, Video và Live. Chạm để chuyển tính năng.",
            .en: "Phone preview cycling through Feed, Explore, Video, and Live features. Tap to switch."
        ],
        "Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng.": [
            .vi: "Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng.",
            .en: "Continuing means you agree to community guidelines."
        ],
        "Quy tắc cộng đồng": [
            .vi: "Quy tắc cộng đồng",
            .en: "Community Guidelines"
        ],
        "Chính sách quyền riêng tư": [
            .vi: "Chính sách quyền riêng tư",
            .en: "Privacy Policy"
        ],
        "Điều khoản dịch vụ": [
            .vi: "Điều khoản dịch vụ",
            .en: "Terms of Service"
        ],

        // Auth & Login
        "Chào bạn trở lại!": [
            .vi: "Chào bạn trở lại!",
            .en: "Welcome back!"
        ],
        "Đăng nhập để tiếp tục những kết nối của bạn.": [
            .vi: "Đăng nhập để tiếp tục những kết nối của bạn.",
            .en: "Log in to continue your connections."
        ],
        "Đăng nhập": [
            .vi: "Đăng nhập",
            .en: "Log In"
        ],
        "Tài khoản hoặc email": [
            .vi: "Tài khoản hoặc email",
            .en: "Username or email"
        ],
        "Mật khẩu": [
            .vi: "Mật khẩu",
            .en: "Password"
        ],
        "Ghi nhớ đăng nhập": [
            .vi: "Ghi nhớ đăng nhập",
            .en: "Remember login"
        ],
        "Quên mật khẩu?": [
            .vi: "Quên mật khẩu?",
            .en: "Forgot password?"
        ],
        "Ghi nhớ": [
            .vi: "Ghi nhớ",
            .en: "Remember"
        ],
        "Tiếng Việt / English": [
            .vi: "Tiếng Việt / English",
            .en: "Tiếng Việt / English"
        ],
        "hoặc tiếp tục với mật khẩu": [
            .vi: "hoặc tiếp tục với mật khẩu",
            .en: "or continue with a password"
        ],
        "Tên đăng nhập": [
            .vi: "Tên đăng nhập",
            .en: "Username"
        ],
        "Mật khẩu (từ 6 ký tự)": [
            .vi: "Mật khẩu (từ 6 ký tự)",
            .en: "Password (6+ characters)"
        ],
        "Mới đến Kinnect?": [
            .vi: "Mới đến Kinnect?",
            .en: "New to Kinnect?"
        ],
        "Ngôn ngữ ứng dụng": [
            .vi: "Ngôn ngữ ứng dụng",
            .en: "App language"
        ],
        "Đóng": [
            .vi: "Đóng",
            .en: "Close"
        ],
        "Tên đăng nhập hoặc mật khẩu không đúng.": [
            .vi: "Tên đăng nhập hoặc mật khẩu không đúng.",
            .en: "Invalid username or password."
        ],
        "Chưa có tài khoản?": [
            .vi: "Chưa có tài khoản?",
            .en: "Don\'t have an account?"
        ],
        "Tạo tài khoản mới": [
            .vi: "Tạo tài khoản mới",
            .en: "Create new account"
        ],
        "hoặc tiếp tục với mạng xã hội": [
            .vi: "hoặc tiếp tục với mạng xã hội",
            .en: "or continue with social networks"
        ],
        "Đăng nhập bằng Apple": [
            .vi: "Đăng nhập bằng Apple",
            .en: "Sign in with Apple"
        ],
        "Tiếp tục với Google": [
            .vi: "Tiếp tục với Google",
            .en: "Continue with Google"
        ],
        "Tiếp tục với Facebook": [
            .vi: "Tiếp tục với Facebook",
            .en: "Continue with Facebook"
        ],

        // Register
        "Bắt đầu kết nối của bạn.": [
            .vi: "Bắt đầu kết nối của bạn.",
            .en: "Start your connection."
        ],
        "Tạo tài khoản để chia sẻ và gặp người cùng tần số.": [
            .vi: "Tạo tài khoản để chia sẻ và gặp người cùng tần số.",
            .en: "Create an account to share and meet your tribe."
        ],
        "Tên hiển thị": [
            .vi: "Tên hiển thị",
            .en: "Display name"
        ],
        "Tên đăng nhập (3-30 ký tự)": [
            .vi: "Tên đăng nhập (3-30 ký tự)",
            .en: "Username (3-30 chars)"
        ],
        "Mật khẩu (ít nhất 6 ký tự)": [
            .vi: "Mật khẩu (ít nhất 6 ký tự)",
            .en: "Password (at least 6 chars)"
        ],
        "Tôi xác nhận mình đủ 18 tuổi và đồng ý với quy tắc cộng đồng.": [
            .vi: "Tôi xác nhận mình đủ 18 tuổi và đồng ý với quy tắc cộng đồng.",
            .en: "I confirm I am 18+ and agree to community guidelines."
        ],
        "Tôi đồng ý với Chính sách quyền riêng tư & Điều khoản Kinnect.": [
            .vi: "Tôi đồng ý với Chính sách quyền riêng tư & Điều khoản Kinnect.",
            .en: "I agree to Kinnect Privacy Policy & Terms."
        ],
        "Đọc toàn văn chính sách bảo vệ dữ liệu": [
            .vi: "Đọc toàn văn chính sách bảo vệ dữ liệu",
            .en: "Read full data protection policy"
        ],
        "Tạo tài khoản": [
            .vi: "Tạo tài khoản",
            .en: "Create Account"
        ],
        "Đã có tài khoản?": [
            .vi: "Đã có tài khoản?",
            .en: "Already have an account?"
        ],
        "Đăng nhập ngay": [
            .vi: "Đăng nhập ngay",
            .en: "Log in now"
        ],

        // Forgot Password
        "Quên mật khẩu": [
            .vi: "Quên mật khẩu",
            .en: "Forgot Password"
        ],
        "Chúng tôi sẽ gửi mã xác minh hoặc hướng dẫn tới email khôi phục của bạn.": [
            .vi: "Chúng tôi sẽ gửi mã xác minh hoặc hướng dẫn tới email khôi phục của bạn.",
            .en: "We will send a verification code or instructions to your recovery email."
        ],
        "Tên đăng nhập hoặc email": [
            .vi: "Tên đăng nhập hoặc email",
            .en: "Username or email"
        ],
        "Gửi mã qua email": [
            .vi: "Gửi mã qua email",
            .en: "Send code via email"
        ],
        "Chưa có email khôi phục?": [
            .vi: "Chưa có email khôi phục?",
            .en: "No recovery email yet?"
        ],
        "Gửi yêu cầu hỗ trợ": [
            .vi: "Gửi yêu cầu hỗ trợ",
            .en: "Submit support request"
        ],
        "Quay lại đăng nhập": [
            .vi: "Quay lại đăng nhập",
            .en: "Back to login"
        ],

        // Tabs & Navigation
        "Bảng tin": [
            .vi: "Bảng tin",
            .en: "Feed"
        ],
        "Khám phá": [
            .vi: "Khám phá",
            .en: "Explore"
        ],
        "Video": [
            .vi: "Video",
            .en: "Video"
        ],
        "Thông báo": [
            .vi: "Thông báo",
            .en: "Notifications"
        ],
        "Cá nhân": [
            .vi: "Cá nhân",
            .en: "Profile"
        ],
        "Tin nhắn": [
            .vi: "Tin nhắn",
            .en: "Messages"
        ],

        // Studio Pro
        "Studio Pro": [
            .vi: "Studio Pro",
            .en: "Studio Pro"
        ],
        "Chỉnh sửa Studio Pro": [
            .vi: "Chỉnh sửa Studio Pro",
            .en: "Studio Pro Editor"
        ],
        "Lưu về máy": [
            .vi: "Lưu về máy",
            .en: "Save to Photos"
        ],
        "Đăng ngay": [
            .vi: "Đăng ngay",
            .en: "Publish Now"
        ],
        "Đang xuất video qua Studio Pro...": [
            .vi: "Đang xuất video qua Studio Pro...",
            .en: "Exporting video via Studio Pro..."
        ],
        "Đã lưu ảnh vào Album ảnh trên thiết bị.": [
            .vi: "Đã lưu ảnh vào Album ảnh trên thiết bị.",
            .en: "Saved photo to device Photos album."
        ],
        "Đã lưu video đã chỉnh sửa vào Album ảnh trên thiết bị.": [
            .vi: "Đã lưu video đã chỉnh sửa vào Album ảnh trên thiết bị.",
            .en: "Saved edited video to device Photos album."
        ],
        "Độ sáng": [
            .vi: "Độ sáng",
            .en: "Brightness"
        ],
        "Tương phản": [
            .vi: "Tương phản",
            .en: "Contrast"
        ],
        "Bão hòa": [
            .vi: "Bão hòa",
            .en: "Saturation"
        ],
        "Độ ấm": [
            .vi: "Độ ấm",
            .en: "Warmth"
        ],
        "Mịn da": [
            .vi: "Mịn da",
            .en: "Skin Smoothing"
        ],
        "Cắt & Xoay": [
            .vi: "Cắt & Xoay",
            .en: "Trim & Rotate"
        ],
        "Điểm đầu": [
            .vi: "Điểm đầu",
            .en: "Trim In"
        ],
        "Điểm cuối": [
            .vi: "Điểm cuối",
            .en: "Trim Out"
        ],
        "Xoay 90°": [
            .vi: "Xoay 90°",
            .en: "Rotate 90°"
        ]
    ]

    func localized(_ key: String) -> String {
        if let dict = translations[key], let val = dict[currentLanguage] {
            return val
        }
        return key
    }
}

// MARK: - Global Convenience Helper
enum L10n {
    static func tr(_ key: String) -> String {
        LocalizationManager.shared.localized(key)
    }
}
