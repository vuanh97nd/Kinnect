import Foundation
import SwiftUI

// MARK: - Supported App Languages
enum AppLanguagePreference: String {
    case vi
    case en
    case system
}

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

    @Published var preference: AppLanguagePreference
    @Published var currentLanguage: AppLanguage

    private init() {
        #if DEBUG
        if UIReviewFixture.isEnabled {
            let english = UIReviewFixture.activeScreen?.hasSuffix("-en") == true
            self.preference = english ? .en : .vi
            self.currentLanguage = english ? .en : .vi
        } else if let saved = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let preference = AppLanguagePreference(rawValue: saved) ?? .system
            self.preference = preference
            self.currentLanguage = Self.resolved(preference)
        } else {
            self.preference = .system
            self.currentLanguage = Self.resolved(.system)
        }
        #else
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey) {
            let preference = AppLanguagePreference(rawValue: saved) ?? .system
            self.preference = preference
            self.currentLanguage = Self.resolved(preference)
        } else {
            self.preference = .system
            self.currentLanguage = Self.resolved(.system)
        }
        #endif
    }

    func setLanguage(_ lang: AppLanguage) {
        setPreference(lang == .en ? .en : .vi)
    }

    func setPreference(_ value: AppLanguagePreference) {
        let resolved = Self.resolved(value)
        UserDefaults.standard.set(value.rawValue, forKey: userDefaultsKey)
        withAnimation(.easeInOut(duration: 0.2)) {
            preference = value
            currentLanguage = resolved
        }
    }

    private static func resolved(_ preference: AppLanguagePreference) -> AppLanguage {
        switch preference {
        case .vi:
            return .vi
        case .en:
            return .en
        case .system:
            let device = Locale.preferredLanguages.first?.lowercased() ?? "vi"
            return device.hasPrefix("vi") ? .vi : .en
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
        "Theo hệ thống": [
            .vi: "Theo hệ thống",
            .en: "System"
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
        "Không thể đăng nhập bằng Apple lúc này. Vui lòng kiểm tra iCloud và thử lại.": [
            .vi: "Không thể đăng nhập bằng Apple lúc này. Vui lòng kiểm tra iCloud và thử lại.",
            .en: "Unable to sign in with Apple right now. Please check iCloud and try again."
        ],
        "Tạm dừng minh họa tự động": [
            .vi: "Tạm dừng minh họa tự động",
            .en: "Pause automatic preview"
        ],
        "Tiếp tục minh họa tự động": [
            .vi: "Tiếp tục minh họa tự động",
            .en: "Resume automatic preview"
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
        ],

        // Missing AuthView & Welcome Showcase Keys
        "Tạo tin": [
            .vi: "Tạo tin",
            .en: "Add story"
        ],
        "Bạn đang nghĩ gì?": [
            .vi: "Bạn đang nghĩ gì?",
            .en: "What's on your mind?"
        ],
        "Tập luyện mỗi ngày": [
            .vi: "Tập luyện mỗi ngày",
            .en: "Training every day"
        ],
        "Tên đăng nhập (vd: ten_tai_khoan)": [
            .vi: "Tên đăng nhập (vd: ten_tai_khoan)",
            .en: "Username (e.g. my_username)"
        ],
        "Email, số điện thoại hoặc Zalo liên hệ": [
            .vi: "Email, số điện thoại hoặc Zalo liên hệ",
            .en: "Contact email, phone, or Zalo"
        ],
        "Mã xác minh 6 chữ số (OTP)": [
            .vi: "Mã xác minh 6 chữ số (OTP)",
            .en: "6-digit verification code (OTP)"
        ],
        "Mật khẩu mới (ít nhất 6 ký tự)": [
            .vi: "Mật khẩu mới (ít nhất 6 ký tự)",
            .en: "New password (at least 6 chars)"
        ],
        "Gửi yêu cầu hỗ trợ quản trị viên": [
            .vi: "Gửi yêu cầu hỗ trợ quản trị viên",
            .en: "Request admin support"
        ],
        "Đặt lại mật khẩu": [
            .vi: "Đặt lại mật khẩu",
            .en: "Reset Password"
        ],
        "Không nhận được mã? Gửi yêu cầu hỗ trợ quản trị viên": [
            .vi: "Không nhận được mã? Gửi yêu cầu hỗ trợ quản trị viên",
            .en: "Didn't receive a code? Request admin support"
        ],
        "Mã xác thực 2 lớp (6 số / mã dự phòng)": [
            .vi: "Mã xác thực 2 lớp (6 số / mã dự phòng)",
            .en: "Two-factor code (6 digits / backup code)"
        ],
        "Hủy": [
            .vi: "Hủy",
            .en: "Cancel"
        ],
        "Nhập mã 6 chữ số": [
            .vi: "Nhập mã 6 chữ số",
            .en: "Enter 6-digit code"
        ],
        "Xác nhận đăng nhập": [
            .vi: "Xác nhận đăng nhập",
            .en: "Verify Sign In"
        ],
        "Không nhận diện được chứng chỉ Apple.": [
            .vi: "Không nhận diện được chứng chỉ Apple.",
            .en: "Could not recognize Apple credential."
        ],
        "Không nhận được token xác thực từ Apple.": [
            .vi: "Không nhận được token xác thực từ Apple.",
            .en: "Could not receive authentication token from Apple."
        ],
        "Tài khoản bật bảo mật 2 lớp. Nhập mã 6 số hoặc mã dự phòng để tiếp tục.": [
            .vi: "Tài khoản bật bảo mật 2 lớp. Nhập mã 6 số hoặc mã dự phòng để tiếp tục.",
            .en: "Two-factor authentication is enabled. Enter your 6-digit or backup code to continue."
        ],
        "Tài khoản Apple bật bảo mật 2 lớp. Nhập mã 6 số hoặc mã dự phòng để tiếp tục.": [
            .vi: "Tài khoản Apple bật bảo mật 2 lớp. Nhập mã 6 số hoặc mã dự phòng để tiếp tục.",
            .en: "This Apple account has 2FA enabled. Enter your 6-digit or backup code to continue."
        ],
        "Vui lòng nhập mã xác thực 2 bước.": [
            .vi: "Vui lòng nhập mã xác thực 2 bước.",
            .en: "Please enter your two-factor verification code."
        ],
        "Chính sách quyền riêng tư và bảo mật dữ liệu Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.": [
            .vi: "Chính sách quyền riêng tư và bảo mật dữ liệu Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.",
            .en: "Kinnect Privacy Policy and Data Protection notice. Committed to privacy under Apple standards and applicable law."
        ],
        "Chính sách quyền riêng tư và điều khoản dịch vụ Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.": [
            .vi: "Chính sách quyền riêng tư và điều khoản dịch vụ Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.",
            .en: "Kinnect Privacy Policy and Terms of Service. Committed to privacy under Apple standards and applicable law."
        ],
        "Vui lòng nhập tên đăng nhập (3–30 ký tự, không gồm @) để gửi yêu cầu cho quản trị viên.": [
            .vi: "Vui lòng nhập tên đăng nhập (3–30 ký tự, không gồm @) để gửi yêu cầu cho quản trị viên.",
            .en: "Please enter your username (3–30 chars, without @) to request admin assistance."
        ],
        "Nhập đúng tên đăng nhập của bạn (3–30 ký tự chữ thường, số hoặc _).": [
            .vi: "Nhập đúng tên đăng nhập của bạn (3–30 ký tự chữ thường, số hoặc _).",
            .en: "Enter your exact username (3–30 lowercase letters, numbers, or _)."
        ],
        "Để lại email, số điện thoại hoặc Zalo (tối thiểu 5 ký tự) để quản trị viên liên hệ.": [
            .vi: "Để lại email, số điện thoại hoặc Zalo (tối thiểu 5 ký tự) để quản trị viên liên hệ.",
            .en: "Provide an email, phone, or Zalo (at least 5 characters) so support can reach you."
        ],
        "Xác nhận độ tuổi (18+)": [
            .vi: "Xác nhận độ tuổi (18+)",
            .en: "Age Confirmation (18+)"
        ],
        "Để tạo tài khoản Kinnect bằng Apple, vui lòng xác nhận bạn đã đủ 18 tuổi và đồng ý Quy tắc cộng đồng cùng Chính sách quyền riêng tư.": [
            .vi: "Để tạo tài khoản Kinnect bằng Apple, vui lòng xác nhận bạn đã đủ 18 tuổi và đồng ý Quy tắc cộng đồng cùng Chính sách quyền riêng tư.",
            .en: "To create a Kinnect account with Apple, please confirm you are 18+ and agree to the Community Guidelines and Privacy Policy."
        ],
        "Tiếp tục với Apple": [
            .vi: "Tiếp tục với Apple",
            .en: "Continue with Apple"
        ],

        // OAuth Complete Registration Sheet
        "Tạo tài khoản từ": [
            .vi: "Tạo tài khoản từ",
            .en: "Create account with"
        ],
        "Chọn tên đăng nhập và xác nhận độ tuổi cùng chính sách bảo vệ dữ liệu trước khi hoàn tất đăng ký.": [
            .vi: "Chọn tên đăng nhập và xác nhận độ tuổi cùng chính sách bảo vệ dữ liệu trước khi hoàn tất đăng ký.",
            .en: "Choose a username and confirm your age and data privacy policy to complete sign-up."
        ],
        "Tên hiển thị của bạn": [
            .vi: "Tên hiển thị của bạn",
            .en: "Your display name"
        ],
        "Tên đăng nhập (3–30 chữ thường không dấu, số hoặc _)": [
            .vi: "Tên đăng nhập (3–30 chữ thường không dấu, số hoặc _)",
            .en: "Username (3–30 lowercase letters, digits, or _)"
        ],
        "Tôi xác nhận đã đủ 18 tuổi và đồng ý Điều khoản & Chính sách quyền riêng tư": [
            .vi: "Tôi xác nhận đã đủ 18 tuổi và đồng ý Điều khoản & Chính sách quyền riêng tư",
            .en: "I confirm I am at least 18 years old and agree to the Terms & Privacy Policy"
        ],
        "Xem thông báo dữ liệu": [
            .vi: "Xem thông báo dữ liệu",
            .en: "View data notice"
        ],
        "Điều khoản": [
            .vi: "Điều khoản",
            .en: "Terms"
        ],
        "Quyền riêng tư": [
            .vi: "Quyền riêng tư",
            .en: "Privacy"
        ],
        "Hoàn tất đăng ký": [
            .vi: "Hoàn tất đăng ký",
            .en: "Complete Sign Up"
        ],
        "Vui lòng xác nhận đủ 18 tuổi và đồng ý Điều khoản & Chính sách quyền riêng tư.": [
            .vi: "Vui lòng xác nhận đủ 18 tuổi và đồng ý Điều khoản & Chính sách quyền riêng tư.",
            .en: "Please confirm you are 18+ and agree to the Terms & Privacy Policy."
        ],
        "Tên đăng nhập cần 3–30 ký tự chữ thường không dấu, số hoặc gạch dưới.": [
            .vi: "Tên đăng nhập cần 3–30 ký tự chữ thường không dấu, số hoặc gạch dưới.",
            .en: "Username must be 3–30 lowercase letters, numbers, or underscores."
        ],
        "Không hoàn tất được đăng ký tài khoản.": [
            .vi: "Không hoàn tất được đăng ký tài khoản.",
            .en: "Unable to complete account registration."
        ],

        // Privacy Consent Sheet
        "Bảo vệ dữ liệu & Quyền riêng tư": [
            .vi: "Bảo vệ dữ liệu & Quyền riêng tư",
            .en: "Data Protection & Privacy"
        ],
        "Thông báo dữ liệu hiện hành": [
            .vi: "Thông báo dữ liệu hiện hành",
            .en: "Current data notice"
        ],
        "Phiên bản quy định": [
            .vi: "Phiên bản quy định",
            .en: "Policy version"
        ],
        "Quyền kiểm soát của bạn:": [
            .vi: "Quyền kiểm soát của bạn:",
            .en: "Your controls:"
        ],
        "Quản lý bài viết, ảnh, video và thu hồi bất kỳ lúc nào.": [
            .vi: "Quản lý bài viết, ảnh, video và thu hồi bất kỳ lúc nào.",
            .en: "Manage posts, photos, and videos and remove them anytime."
        ],
        "Chặn người dùng và báo cáo nội dung vi phạm ngay trong ứng dụng.": [
            .vi: "Chặn người dùng và báo cáo nội dung vi phạm ngay trong ứng dụng.",
            .en: "Block users and report abusive content directly in the app."
        ],
        "Yêu cầu xóa vĩnh viễn tài khoản và toàn bộ dữ liệu trong Hồ sơ cá nhân.": [
            .vi: "Yêu cầu xóa vĩnh viễn tài khoản và toàn bộ dữ liệu trong Hồ sơ cá nhân.",
            .en: "Request permanent deletion of your account and all data in Profile settings."
        ],
        "Xem chính sách quyền riêng tư đầy đủ": [
            .vi: "Xem chính sách quyền riêng tư đầy đủ",
            .en: "Read full Privacy Policy"
        ],
        "Tôi đồng ý & Tiếp tục": [
            .vi: "Tôi đồng ý & Tiếp tục",
            .en: "I Agree & Continue"
        ],
        "Để sau": [
            .vi: "Để sau",
            .en: "Not Now"
        ],
        "Đã ghi nhận sự đồng ý của bạn.": [
            .vi: "Đã ghi nhận sự đồng ý của bạn.",
            .en: "Your consent has been recorded."
        ],

        // App Shell, Top Bar, Bottom Bar & iPad Sidebar
        "Tạo": [
            .vi: "Tạo",
            .en: "Create"
        ],
        "Tạo nội dung": [
            .vi: "Tạo nội dung",
            .en: "Create content"
        ],
        "Về đầu Bảng tin Kinnect": [
            .vi: "Về đầu Bảng tin Kinnect",
            .en: "Return to top of Kinnect Feed"
        ],
        "Cửa hàng": [
            .vi: "Cửa hàng",
            .en: "Store"
        ],
        "Cửa hàng Kinnect": [
            .vi: "Cửa hàng Kinnect",
            .en: "Kinnect Store"
        ],
        "Bạn bè": [
            .vi: "Bạn bè",
            .en: "Friends"
        ],
        "Tài khoản": [
            .vi: "Tài khoản",
            .en: "Account"
        ],
        "Hồ sơ": [
            .vi: "Hồ sơ",
            .en: "Profile"
        ],
        "Hồ sơ cá nhân": [
            .vi: "Hồ sơ cá nhân",
            .en: "Personal Profile"
        ],
        "Điều hướng": [
            .vi: "Điều hướng",
            .en: "Navigation"
        ],
        "Liên lạc & Cá nhân": [
            .vi: "Liên lạc & Cá nhân",
            .en: "Social & Profile"
        ],
        "Tiện ích": [
            .vi: "Tiện ích",
            .en: "Utilities"
        ],
        "Tạo ảnh / Video": [
            .vi: "Tạo ảnh / Video",
            .en: "Create Photo / Video"
        ],
        "Ví Kinnect": [
            .vi: "Ví Kinnect",
            .en: "Kinnect Wallet"
        ],
        "Bài viết": [
            .vi: "Bài viết",
            .en: "Posts"
        ],
        "Album ảnh": [
            .vi: "Album ảnh",
            .en: "Albums"
        ],
        "Lời mời kết bạn": [
            .vi: "Lời mời kết bạn",
            .en: "Friend Requests"
        ],
        "Gợi ý kết bạn": [
            .vi: "Gợi ý kết bạn",
            .en: "Friend Suggestions"
        ],
        "Nạp xu Kinnect": [
            .vi: "Nạp xu Kinnect",
            .en: "Top Up Kinnect Coins"
        ],

        // Content Report Sheet
        "Không đính kèm ảnh hoặc video vi phạm an toàn trẻ em. Báo cáo của bạn sẽ được ưu tiên xử lý khẩn cấp và chuyển cơ quan chức năng khi cần.": [
            .vi: "Không đính kèm ảnh hoặc video vi phạm an toàn trẻ em. Báo cáo của bạn sẽ được ưu tiên xử lý khẩn cấp và chuyển cơ quan chức năng khi cần.",
            .en: "Do not attach images or videos depicting child exploitation. Your report is prioritized for urgent review and escalated to authorities as required."
        ],
        "Nội dung không phù hợp / phản cảm": [
            .vi: "Nội dung không phù hợp / phản cảm",
            .en: "Inappropriate or offensive content"
        ],
        "Quấy rối, đe dọa hoặc xúc phạm": [
            .vi: "Quấy rối, đe dọa hoặc xúc phạm",
            .en: "Harassment, threats, or hate speech"
        ],
        "Lừa đảo hoặc giả mạo": [
            .vi: "Lừa đảo hoặc giả mạo",
            .en: "Scam or impersonation"
        ],
        "Spam hoặc quảng cáo trái phép": [
            .vi: "Spam hoặc quảng cáo trái phép",
            .en: "Spam or unauthorized advertising"
        ],
        "Vi phạm bản quyền / quyền riêng tư": [
            .vi: "Vi phạm bản quyền / quyền riêng tư",
            .en: "Copyright or privacy violation"
        ],
        "Báo cáo vi phạm": [
            .vi: "Báo cáo vi phạm",
            .en: "Report violation"
        ],
        "Lý do báo cáo": [
            .vi: "Lý do báo cáo",
            .en: "Reason for reporting"
        ],
        "Chi tiết bổ sung (tùy chọn)": [
            .vi: "Chi tiết bổ sung (tùy chọn)",
            .en: "Additional details (optional)"
        ],
        "Mô tả thêm...": [
            .vi: "Mô tả thêm...",
            .en: "Add more details..."
        ],
        "Đồng thời chặn người dùng này và ẩn toàn bộ nội dung của họ": [
            .vi: "Đồng thời chặn người dùng này và ẩn toàn bộ nội dung của họ",
            .en: "Also block this user and hide all their content"
        ],
        "Gửi báo cáo": [
            .vi: "Gửi báo cáo",
            .en: "Submit Report"
        ],
        "Báo cáo nội dung": [
            .vi: "Báo cáo nội dung",
            .en: "Report Content"
        ],
        "Báo cáo / Chặn": [
            .vi: "Báo cáo / Chặn",
            .en: "Report / Block"
        ],
        "Đã gửi báo cáo và chặn người dùng.": [
            .vi: "Đã gửi báo cáo và chặn người dùng.",
            .en: "Report submitted and user blocked."
        ],
        "Đã gửi báo cáo vi phạm. Cảm ơn bạn đã giữ cộng đồng an toàn.": [
            .vi: "Đã gửi báo cáo vi phạm. Cảm ơn bạn đã giữ cộng đồng an toàn.",
            .en: "Report submitted. Thank you for helping keep the community safe."
        ],

        // Account Menu & Settings
        "Trang cá nhân": [
            .vi: "Trang cá nhân",
            .en: "My Profile"
        ],
        "Người dùng Kinnect": [
            .vi: "Người dùng Kinnect",
            .en: "Kinnect User"
        ],
        "Bảng quản trị": [
            .vi: "Bảng quản trị",
            .en: "Admin Console"
        ],
        "Bài viết đã lưu": [
            .vi: "Bài viết đã lưu",
            .en: "Saved Posts"
        ],
        "Cài đặt và quyền riêng tư": [
            .vi: "Cài đặt và quyền riêng tư",
            .en: "Settings & Privacy"
        ],
        "Cài đặt & riêng tư": [
            .vi: "Cài đặt & riêng tư",
            .en: "Settings & Privacy"
        ],
        "Bảo mật và đăng nhập": [
            .vi: "Bảo mật và đăng nhập",
            .en: "Security & Login"
        ],
        "Cài đặt thông báo": [
            .vi: "Cài đặt thông báo",
            .en: "Notification Settings"
        ],
        "Giao diện": [
            .vi: "Giao diện",
            .en: "Appearance"
        ],
        "Giao diện ứng dụng": [
            .vi: "Giao diện ứng dụng",
            .en: "App Appearance"
        ],
        "Sáng": [
            .vi: "Sáng",
            .en: "Light"
        ],
        "Tối": [
            .vi: "Tối",
            .en: "Dark"
        ],
        "Trợ giúp và hỗ trợ": [
            .vi: "Trợ giúp và hỗ trợ",
            .en: "Help & Support"
        ],
        "Giới thiệu Kinnect": [
            .vi: "Giới thiệu Kinnect",
            .en: "About Kinnect"
        ],
        "Giới thiệu": [
            .vi: "Giới thiệu",
            .en: "About"
        ],
        "Đổi mật khẩu": [
            .vi: "Đổi mật khẩu",
            .en: "Change Password"
        ],
        "Đặt mật khẩu": [
            .vi: "Đặt mật khẩu",
            .en: "Set Password"
        ],
        "Đang lưu…": [
            .vi: "Đang lưu…",
            .en: "Saving…"
        ],
        "Vui lòng nhập mật khẩu hiện tại.": [
            .vi: "Vui lòng nhập mật khẩu hiện tại.",
            .en: "Please enter your current password."
        ],
        "Mật khẩu mới phải có ít nhất 6 ký tự.": [
            .vi: "Mật khẩu mới phải có ít nhất 6 ký tự.",
            .en: "New password must be at least 6 characters."
        ],
        "Mật khẩu nhập lại không khớp.": [
            .vi: "Mật khẩu nhập lại không khớp.",
            .en: "Passwords do not match."
        ],
        "Mật khẩu xác nhận không khớp.": [
            .vi: "Mật khẩu xác nhận không khớp.",
            .en: "Confirmation password does not match."
        ],
        "Đã lưu mật khẩu. Các thiết bị khác đã được đăng xuất.": [
            .vi: "Đã lưu mật khẩu. Các thiết bị khác đã được đăng xuất.",
            .en: "Password saved. Other devices have been signed out."
        ],
        "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Bạn có thể đặt mật khẩu mới khi phiên đăng nhập còn mới (trong 10 phút).": [
            .vi: "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Bạn có thể đặt mật khẩu mới khi phiên đăng nhập còn mới (trong 10 phút).",
            .en: "This social login account doesn't have a password yet. You can set a new password while your login session is fresh (within 10 minutes)."
        ],
        "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Cần phiên đăng nhập trong 10 phút gần đây.": [
            .vi: "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Cần phiên đăng nhập trong 10 phút gần đây.",
            .en: "This social login account doesn't have a password yet. A recent login session (within 10 minutes) is required."
        ],
        "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây trong 10 phút).": [
            .vi: "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây trong 10 phút).",
            .en: "This social login account doesn't have a password yet (requires a recent login session within 10 minutes)."
        ],
        "Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập trong 10 phút gần đây).": [
            .vi: "Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập trong 10 phút gần đây).",
            .en: "This social account doesn't have a password yet (requires a login session within the last 10 minutes)."
        ],
        "Đã xác thực phiên đăng nhập gần đây. Bạn có thể xóa tài khoản mà không cần mật khẩu.": [
            .vi: "Đã xác thực phiên đăng nhập gần đây. Bạn có thể xóa tài khoản mà không cần mật khẩu.",
            .en: "Recent login session verified. You can delete your account without a password."
        ],
        "Đăng xuất": [
            .vi: "Đăng xuất",
            .en: "Log Out"
        ],
        "Đăng xuất khỏi Kinnect?": [
            .vi: "Đăng xuất khỏi Kinnect?",
            .en: "Log out of Kinnect?"
        ],
        "Bạn có thể đăng nhập lại bất kỳ lúc nào.": [
            .vi: "Bạn có thể đăng nhập lại bất kỳ lúc nào.",
            .en: "You can sign back in anytime."
        ],
        "Kinnect · Kết nối theo cách của bạn.": [
            .vi: "Kinnect · Kết nối theo cách của bạn.",
            .en: "Kinnect · Connect your way."
        ],
        "Ngôn ngữ": [
            .vi: "Ngôn ngữ",
            .en: "Language"
        ],
        "Thông tin cá nhân": [
            .vi: "Thông tin cá nhân",
            .en: "Personal Info"
        ],
        "· chỉnh sửa hồ sơ": [
            .vi: "· chỉnh sửa hồ sơ",
            .en: "· edit profile"
        ],
        "Trạng thái hoạt động": [
            .vi: "Trạng thái hoạt động",
            .en: "Active Status"
        ],
        "Cho người khác biết khi bạn đang online": [
            .vi: "Cho người khác biết khi bạn đang online",
            .en: "Let others see when you're online"
        ],
        "Cho phép tìm thấy tôi": [
            .vi: "Cho phép tìm thấy tôi",
            .en: "Allow others to discover me"
        ],
        "Xuất hiện trong Khám phá và Quanh đây": [
            .vi: "Xuất hiện trong Khám phá và Quanh đây",
            .en: "Appear in Explore and Nearby"
        ],
        "Hiển thị khoảng cách": [
            .vi: "Hiển thị khoảng cách",
            .en: "Show Distance"
        ],
        "Chỉ hiện khoảng cách gần đúng": [
            .vi: "Chỉ hiện khoảng cách gần đúng",
            .en: "Only show approximate distance"
        ],
        "Ai có thể nhắn tin": [
            .vi: "Ai có thể nhắn tin",
            .en: "Who can message you"
        ],
        "Mọi thành viên": [
            .vi: "Mọi thành viên",
            .en: "Everyone"
        ],
        "Quyền truy cập": [
            .vi: "Quyền truy cập",
            .en: "Access Control"
        ],
        "Ảnh riêng tư": [
            .vi: "Ảnh riêng tư",
            .en: "Private Photos"
        ],
        "Tài khoản đã chặn": [
            .vi: "Tài khoản đã chặn",
            .en: "Blocked Accounts"
        ],
        "Quản lý tài khoản": [
            .vi: "Quản lý tài khoản",
            .en: "Account Management"
        ],
        "Xóa tài khoản và dữ liệu": [
            .vi: "Xóa tài khoản và dữ liệu",
            .en: "Delete Account & Data"
        ],
        "Vị trí và quanh đây": [
            .vi: "Vị trí và quanh đây",
            .en: "Location & Nearby"
        ],
        "Tắt tìm quanh đây": [
            .vi: "Tắt tìm quanh đây",
            .en: "Turn Off Nearby Location"
        ],
        "Đã tắt tìm quanh đây": [
            .vi: "Đã tắt tìm quanh đây",
            .en: "Nearby location turned off"
        ],
        "Xác thực 2 bước (2FA)": [
            .vi: "Xác thực 2 bước (2FA)",
            .en: "Two-Factor Authentication (2FA)"
        ],
        "Email khôi phục": [
            .vi: "Email khôi phục",
            .en: "Recovery Email"
        ],
        "Thiết bị đăng nhập": [
            .vi: "Thiết bị đăng nhập",
            .en: "Logged-in Devices"
        ],
        "Hỗ trợ tài khoản và khôi phục": [
            .vi: "Hỗ trợ tài khoản và khôi phục",
            .en: "Account & Recovery Support"
        ],
        "Báo sự cố": [
            .vi: "Báo sự cố",
            .en: "Report a Problem"
        ],
        "Trung tâm hỗ trợ": [
            .vi: "Trung tâm hỗ trợ",
            .en: "Help Center"
        ],
        "An toàn trẻ em": [
            .vi: "An toàn trẻ em",
            .en: "Child Safety"
        ],
        "Giấy phép phần mềm": [
            .vi: "Giấy phép phần mềm",
            .en: "Software Licenses"
        ],
        "Mật khẩu hiện tại": [
            .vi: "Mật khẩu hiện tại",
            .en: "Current Password"
        ],
        "Mật khẩu mới": [
            .vi: "Mật khẩu mới",
            .en: "New Password"
        ],
        "Nhập lại mật khẩu mới": [
            .vi: "Nhập lại mật khẩu mới",
            .en: "Confirm New Password"
        ],
        "Lưu": [
            .vi: "Lưu",
            .en: "Save"
        ],
        "Hiện thông báo": [
            .vi: "Hiện thông báo",
            .en: "Show Notifications"
        ],
        "Bài viết và tương tác": [
            .vi: "Bài viết và tương tác",
            .en: "Posts & Interactions"
        ],
        "Cài đặt thông báo của iOS": [
            .vi: "Cài đặt thông báo của iOS",
            .en: "iOS Notification Settings"
        ],
        "Chưa có bài viết đã lưu": [
            .vi: "Chưa có bài viết đã lưu",
            .en: "No Saved Posts"
        ],
        "Bỏ lưu": [
            .vi: "Bỏ lưu",
            .en: "Unsave"
        ],
        "Đang tải…": [
            .vi: "Đang tải…",
            .en: "Loading…"
        ],
        "Xem thêm bài viết đã lưu": [
            .vi: "Xem thêm bài viết đã lưu",
            .en: "Load More Saved Posts"
        ],
        "Đang tải bài viết đã lưu…": [
            .vi: "Đang tải bài viết đã lưu…",
            .en: "Loading saved posts…"
        ],
        "Các bài viết bạn lưu từ Bảng tin sẽ xuất hiện tại đây để xem lại bất kỳ lúc nào.": [
            .vi: "Các bài viết bạn lưu từ Bảng tin sẽ xuất hiện tại đây để xem lại bất kỳ lúc nào.",
            .en: "Posts you save from the Feed will appear here to revisit anytime."
        ],
        "Nền tảng mạng xã hội kết nối trực tiếp, livestream thời gian thực và tương tác đa phương tiện.": [
            .vi: "Nền tảng mạng xã hội kết nối trực tiếp, livestream thời gian thực và tương tác đa phương tiện.",
            .en: "A social platform for direct connections, real-time livestreams, and rich media sharing."
        ],
        "Phiên bản": [
            .vi: "Phiên bản",
            .en: "Version"
        ],

        // Wave 6 Full UI & CallOverlayView Coverage
        "%@ mời bạn lên sóng cùng phòng Live!": [
            .vi: "%@ mời bạn lên sóng cùng phòng Live!",
            .en: "%@ invited you to join the Live stream!"
        ],
        "%d mã": [
            .vi: "%d mã",
            .en: "%d codes"
        ],
        "Ai có thể xem bài viết này?": [
            .vi: "Ai có thể xem bài viết này?",
            .en: "Who can see this post?"
        ],
        "Ai có thể xem bài viết?": [
            .vi: "Ai có thể xem bài viết?",
            .en: "Who can see this post?"
        ],
        "Album có": [
            .vi: "Album có",
            .en: "This album has"
        ],
        "Album riêng tư": [
            .vi: "Album riêng tư",
            .en: "Private Album"
        ],
        "Album riêng tư của": [
            .vi: "Album riêng tư của",
            .en: "Private Album of"
        ],
        "Album riêng tư hiện chưa có ảnh.": [
            .vi: "Album riêng tư hiện chưa có ảnh.",
            .en: "This private album has no photos yet."
        ],
        "Anh": [
            .vi: "Anh",
            .en: "He / Him"
        ],
        "Bài viết của": [
            .vi: "Bài viết của",
            .en: "Post by"
        ],
        "Bài viết này không còn khả dụng hoặc đã bị xóa.": [
            .vi: "Bài viết này không còn khả dụng hoặc đã bị xóa.",
            .en: "This post is no longer available or has been deleted."
        ],
        "Bài viết sẽ bị xóa vĩnh viễn và không thể khôi phục.": [
            .vi: "Bài viết sẽ bị xóa vĩnh viễn và không thể khôi phục.",
            .en: "This post will be permanently deleted and cannot be recovered."
        ],
        "Bài viết đã xóa sẽ không thể khôi phục.": [
            .vi: "Bài viết đã xóa sẽ không thể khôi phục.",
            .en: "Deleted posts cannot be recovered."
        ],
        "Bán kính tìm quanh đây": [
            .vi: "Bán kính tìm quanh đây",
            .en: "Nearby radius"
        ],
        "Báo cáo": [
            .vi: "Báo cáo",
            .en: "Report"
        ],
        "Báo cáo bình luận": [
            .vi: "Báo cáo bình luận",
            .en: "Report comment"
        ],
        "Báo cáo hồ sơ": [
            .vi: "Báo cáo hồ sơ",
            .en: "Report profile"
        ],
        "Bình luận": [
            .vi: "Bình luận",
            .en: "Comments"
        ],
        "Bình luận của": [
            .vi: "Bình luận của",
            .en: "Comment by"
        ],
        "Bình luận này sẽ bị xóa vĩnh viễn.": [
            .vi: "Bình luận này sẽ bị xóa vĩnh viễn.",
            .en: "This comment will be permanently deleted."
        ],
        "Bình luận đã xóa sẽ không thể khôi phục.": [
            .vi: "Bình luận đã xóa sẽ không thể khôi phục.",
            .en: "Deleted comments cannot be recovered."
        ],
        "Bước 1: Khởi tạo khóa 2FA": [
            .vi: "Bước 1: Khởi tạo khóa 2FA",
            .en: "Step 1: Initialize 2FA Key"
        ],
        "Bước 2: Liên kết ứng dụng Authenticator": [
            .vi: "Bước 2: Liên kết ứng dụng Authenticator",
            .en: "Step 2: Link Authenticator App"
        ],
        "Bước 3: Xác nhận mã 6 chữ số để bật": [
            .vi: "Bước 3: Xác nhận mã 6 chữ số để bật",
            .en: "Step 3: Confirm 6-digit code to enable"
        ],
        "Bạn": [
            .vi: "Bạn",
            .en: "You / They"
        ],
        "Bạn chưa chặn người dùng nào.": [
            .vi: "Bạn chưa chặn người dùng nào.",
            .en: "You have not blocked any users yet."
        ],
        "Bạn có chắc muốn hủy kết bạn với": [
            .vi: "Bạn có chắc muốn hủy kết bạn với",
            .en: "Are you sure you want to unfriend"
        ],
        "Bạn đã gửi yêu cầu xem Album riêng tư. Vui lòng chờ": [
            .vi: "Bạn đã gửi yêu cầu xem Album riêng tư. Vui lòng chờ",
            .en: "You have requested access to this Private Album. Please wait for"
        ],
        "Bạn đã khởi tạo khóa 2FA trước đó. Hãy nhập mã 6 chữ số từ ứng dụng Authenticator để kích hoạt, hoặc tạo lại khóa mới bên dưới.": [
            .vi: "Bạn đã khởi tạo khóa 2FA trước đó. Hãy nhập mã 6 chữ số từ ứng dụng Authenticator để kích hoạt, hoặc tạo lại khóa mới bên dưới.",
            .en: "You previously generated a 2FA key. Enter the 6-digit code from your Authenticator app to activate, or generate a new key below."
        ],
        "Bạn đã rời vị trí khách mời.": [
            .vi: "Bạn đã rời vị trí khách mời.",
            .en: "You left the guest seat."
        ],
        "Bản dạng giới": [
            .vi: "Bản dạng giới",
            .en: "Gender Identity"
        ],
        "Bản thân và cách xưng hô": [
            .vi: "Bản thân và cách xưng hô",
            .en: "Identity & Pronouns"
        ],
        "Bản xem giao diện không gửi email.": [
            .vi: "Bản xem giao diện không gửi email.",
            .en: "Preview mode does not send emails."
        ],
        "Bảo mật mật khẩu": [
            .vi: "Bảo mật mật khẩu",
            .en: "Password Security"
        ],
        "Bỏ chặn": [
            .vi: "Bỏ chặn",
            .en: "Unblock"
        ],
        "Bỏ lưu bài viết": [
            .vi: "Bỏ lưu bài viết",
            .en: "Remove Bookmark"
        ],
        "Bỏ theo dõi": [
            .vi: "Bỏ theo dõi",
            .en: "Unfollow"
        ],
        "Bổ sung chi tiết (tùy chọn)": [
            .vi: "Bổ sung chi tiết (tùy chọn)",
            .en: "Additional details (optional)"
        ],
        "Bộ lọc thông báo": [
            .vi: "Bộ lọc thông báo",
            .en: "Notification filter"
        ],
        "Camera": [
            .vi: "Camera",
            .en: "Camera"
        ],
        "Camera tắt": [
            .vi: "Camera tắt",
            .en: "Camera off"
        ],
        "Chi tiết bài viết": [
            .vi: "Chi tiết bài viết",
            .en: "Post Details"
        ],
        "Chia sẻ": [
            .vi: "Chia sẻ",
            .en: "Share"
        ],
        "Chia sẻ bài viết": [
            .vi: "Chia sẻ bài viết",
            .en: "Share Post"
        ],
        "Chia sẻ bài viết từ": [
            .vi: "Chia sẻ bài viết từ",
            .en: "Share post from"
        ],
        "Chia sẻ liên kết ngoài": [
            .vi: "Chia sẻ liên kết ngoài",
            .en: "Share external link"
        ],
        "Chia sẻ lên bảng tin": [
            .vi: "Chia sẻ lên bảng tin",
            .en: "Share to feed"
        ],
        "Chia sẻ lên bảng tin của bạn": [
            .vi: "Chia sẻ lên bảng tin của bạn",
            .en: "Share to your feed"
        ],
        "Chia sẻ vài dòng về bạn...": [
            .vi: "Chia sẻ vài dòng về bạn...",
            .en: "Tell others a little about yourself..."
        ],
        "Chiều cao": [
            .vi: "Chiều cao",
            .en: "Height"
        ],
        "Chiều cao (cm)": [
            .vi: "Chiều cao (cm)",
            .en: "Height (cm)"
        ],
        "Chú thích cho ảnh...": [
            .vi: "Chú thích cho ảnh...",
            .en: "Photo caption..."
        ],
        "Chưa có bài viết nào": [
            .vi: "Chưa có bài viết nào",
            .en: "No posts yet"
        ],
        "Chưa có báo cáo.": [
            .vi: "Chưa có báo cáo.",
            .en: "No reports yet."
        ],
        "Chưa có bình luận nào. Hãy là người đầu tiên bình luận!": [
            .vi: "Chưa có bình luận nào. Hãy là người đầu tiên bình luận!",
            .en: "No comments yet. Be the first to comment!"
        ],
        "Chưa có cảm xúc": [
            .vi: "Chưa có cảm xúc",
            .en: "No reactions yet"
        ],
        "Chưa có lượt cảm xúc nào.": [
            .vi: "Chưa có lượt cảm xúc nào.",
            .en: "No reactions yet."
        ],
        "Chưa có người theo dõi": [
            .vi: "Chưa có người theo dõi",
            .en: "No followers yet"
        ],
        "Chưa có người xem tin này.": [
            .vi: "Chưa có người xem tin này.",
            .en: "No viewers for this story yet."
        ],
        "Chưa có thông báo mới.": [
            .vi: "Chưa có thông báo mới.",
            .en: "No new notifications."
        ],
        "Chưa có thông tin công khai": [
            .vi: "Chưa có thông tin công khai",
            .en: "No public info yet"
        ],
        "Chưa có video ngắn nào": [
            .vi: "Chưa có video ngắn nào",
            .en: "No shorts yet"
        ],
        "Chưa có yêu cầu xem Album riêng tư nào.": [
            .vi: "Chưa có yêu cầu xem Album riêng tư nào.",
            .en: "No private album requests yet."
        ],
        "Chưa có ảnh công khai nào.": [
            .vi: "Chưa có ảnh công khai nào.",
            .en: "No public photos yet."
        ],
        "Chưa theo dõi ai": [
            .vi: "Chưa theo dõi ai",
            .en: "Not following anyone yet"
        ],
        "Chưa tải được dữ liệu quản trị.": [
            .vi: "Chưa tải được dữ liệu quản trị.",
            .en: "Could not load admin data."
        ],
        "Chưa xác minh email khôi phục.": [
            .vi: "Chưa xác minh email khôi phục.",
            .en: "Recovery email not verified."
        ],
        "Chưa đọc": [
            .vi: "Chưa đọc",
            .en: "Unread"
        ],
        "Chạm để xem & tải ảnh mới": [
            .vi: "Chạm để xem & tải ảnh mới",
            .en: "Tap to view & upload new photos"
        ],
        "Chạm để xem danh sách": [
            .vi: "Chạm để xem danh sách",
            .en: "Tap to view list"
        ],
        "Chạm để xem ảnh bài viết": [
            .vi: "Chạm để xem ảnh bài viết",
            .en: "Tap to view post photos"
        ],
        "Chạm để xem ảnh được chia sẻ": [
            .vi: "Chạm để xem ảnh được chia sẻ",
            .en: "Tap to view shared photos"
        ],
        "Chạm để yêu cầu quyền xem": [
            .vi: "Chạm để yêu cầu quyền xem",
            .en: "Tap to request access"
        ],
        "Chạm để đóng": [
            .vi: "Chạm để đóng",
            .en: "Tap to close"
        ],
        "Chạm để đổi khung hình, kéo để di chuyển": [
            .vi: "Chạm để đổi khung hình, kéo để di chuyển",
            .en: "Tap to switch aspect ratio, drag to reposition"
        ],
        "Chạm 🌐 / 🔒 để chọn thông tin công khai hoặc riêng tư.": [
            .vi: "Chạm 🌐 / 🔒 để chọn thông tin công khai hoặc riêng tư.",
            .en: "Tap 🌐 / 🔒 to choose whether each detail is public or private."
        ],
        "Chấp nhận": [
            .vi: "Chấp nhận",
            .en: "Accept"
        ],
        "Chặn tài khoản": [
            .vi: "Chặn tài khoản",
            .en: "Block Account"
        ],
        "Chặn tài khoản?": [
            .vi: "Chặn tài khoản?",
            .en: "Block account?"
        ],
        "Chế độ hiển thị": [
            .vi: "Chế độ hiển thị",
            .en: "Appearance"
        ],
        "Chế độ sáng": [
            .vi: "Chế độ sáng",
            .en: "Light Mode"
        ],
        "Chế độ tối": [
            .vi: "Chế độ tối",
            .en: "Dark Mode"
        ],
        "Chế độ xem của người khác": [
            .vi: "Chế độ xem của người khác",
            .en: "Public View Mode"
        ],
        "Chỉ hiển thị khoảng cách gần đúng để bảo vệ vị trí chính xác của bạn.": [
            .vi: "Chỉ hiển thị khoảng cách gần đúng để bảo vệ vị trí chính xác của bạn.",
            .en: "Only approximate distance is shown to protect your exact location."
        ],
        "Chỉ mình tôi": [
            .vi: "Chỉ mình tôi",
            .en: "Only me"
        ],
        "Chỉ nhận tin nhắn từ bạn bè": [
            .vi: "Chỉ nhận tin nhắn từ bạn bè",
            .en: "Friends-only messages"
        ],
        "Chỉ quản trị viên được vào bảng quản trị.": [
            .vi: "Chỉ quản trị viên được vào bảng quản trị.",
            .en: "Only admins can access the admin console."
        ],
        "Chỉ tôi": [
            .vi: "Chỉ tôi",
            .en: "Only me"
        ],
        "Chỉnh sửa": [
            .vi: "Chỉnh sửa",
            .en: "Edit"
        ],
        "Chỉnh sửa bài viết": [
            .vi: "Chỉnh sửa bài viết",
            .en: "Edit Post"
        ],
        "Chỉnh sửa bình luận": [
            .vi: "Chỉnh sửa bình luận",
            .en: "Edit Comment"
        ],
        "Chỉnh sửa hồ sơ": [
            .vi: "Chỉnh sửa hồ sơ",
            .en: "Edit Profile"
        ],
        "Chị": [
            .vi: "Chị",
            .en: "She / Her"
        ],
        "Chọn bán kính": [
            .vi: "Chọn bán kính",
            .en: "Select radius"
        ],
        "Chọn lưu tệp video trong bảng chia sẻ.": [
            .vi: "Chọn lưu tệp video trong bảng chia sẻ.",
            .en: "Choose Save Video in the share sheet."
        ],
        "Chọn ngày sinh (YYYY-MM-DD)": [
            .vi: "Chọn ngày sinh (YYYY-MM-DD)",
            .en: "Select birth date (YYYY-MM-DD)"
        ],
        "Chọn ảnh từ thư viện & Đăng": [
            .vi: "Chọn ảnh từ thư viện & Đăng",
            .en: "Choose Photo & Post"
        ],
        "Chờ xác nhận": [
            .vi: "Chờ xác nhận",
            .en: "Pending confirmation"
        ],
        "Chủ phòng": [
            .vi: "Chủ phòng",
            .en: "Host"
        ],
        "Chủ phòng đã từ chối yêu cầu lên sóng.": [
            .vi: "Chủ phòng đã từ chối yêu cầu lên sóng.",
            .en: "The host declined your request to go live."
        ],
        "Cuộc gọi thoại đến": [
            .vi: "Cuộc gọi thoại đến",
            .en: "Incoming voice call"
        ],
        "Cuộc gọi video đến": [
            .vi: "Cuộc gọi video đến",
            .en: "Incoming video call"
        ],
        "Cuộc gọi video đến…": [
            .vi: "Cuộc gọi video đến…",
            .en: "Incoming video call…"
        ],
        "Cuộc gọi đến…": [
            .vi: "Cuộc gọi đến…",
            .en: "Incoming call…"
        ],
        "Các video ngắn bạn đăng trên luồng Shorts sẽ hiển thị tại đây.": [
            .vi: "Các video ngắn bạn đăng trên luồng Shorts sẽ hiển thị tại đây.",
            .en: "Shorts you publish will appear here."
        ],
        "Cách xưng hô": [
            .vi: "Cách xưng hô",
            .en: "Pronouns"
        ],
        "Cân nặng": [
            .vi: "Cân nặng",
            .en: "Weight"
        ],
        "Cân nặng (kg)": [
            .vi: "Cân nặng (kg)",
            .en: "Weight (kg)"
        ],
        "Công khai": [
            .vi: "Công khai",
            .en: "Public"
        ],
        "Công nghệ": [
            .vi: "Công nghệ",
            .en: "Technology"
        ],
        "Cùng sở thích": [
            .vi: "Cùng sở thích",
            .en: "Shared interests"
        ],
        "Cảm xúc": [
            .vi: "Cảm xúc",
            .en: "Reactions"
        ],
        "Cảnh báo: Hành động này sẽ xóa vĩnh viễn tài khoản Kinnect, bài viết, video ngắn, tin nhắn, ví và toàn bộ phiên đăng nhập của bạn. Không thể khôi phục sau khi xóa.": [
            .vi: "Cảnh báo: Hành động này sẽ xóa vĩnh viễn tài khoản Kinnect, bài viết, video ngắn, tin nhắn, ví và toàn bộ phiên đăng nhập của bạn. Không thể khôi phục sau khi xóa.",
            .en: "Warning: This action will permanently delete your Kinnect account, posts, shorts, messages, wallet, and all active sessions. This cannot be undone."
        ],
        "Cần quyền camera và micro để tham gia lên sóng.": [
            .vi: "Cần quyền camera và micro để tham gia lên sóng.",
            .en: "Camera and microphone access are required to join live."
        ],
        "Cần đăng nhập để gửi báo cáo.": [
            .vi: "Cần đăng nhập để gửi báo cáo.",
            .en: "Please sign in to submit a report."
        ],
        "Cần đồng ý điều khoản bảo vệ dữ liệu cá nhân trước khi thực hiện thao tác này.": [
            .vi: "Cần đồng ý điều khoản bảo vệ dữ liệu cá nhân trước khi thực hiện thao tác này.",
            .en: "Please accept the personal data privacy terms before continuing."
        ],
        "Cập nhật hồ sơ để mọi người hiểu bạn hơn.": [
            .vi: "Cập nhật hồ sơ để mọi người hiểu bạn hơn.",
            .en: "Update your profile so others can get to know you better."
        ],
        "Cập nhật mật khẩu": [
            .vi: "Cập nhật mật khẩu",
            .en: "Update Password"
        ],
        "Danh sách ảnh công khai": [
            .vi: "Danh sách ảnh công khai",
            .en: "Public Photos"
        ],
        "Du lịch": [
            .vi: "Du lịch",
            .en: "Travel"
        ],
        "Duyệt": [
            .vi: "Duyệt",
            .en: "Approve"
        ],
        "Dị tính": [
            .vi: "Dị tính",
            .en: "Heterosexual / Straight"
        ],
        "Dữ liệu trả về không hợp lệ.": [
            .vi: "Dữ liệu trả về không hợp lệ.",
            .en: "Invalid server data."
        ],
        "Dữ liệu trả về từ dịch vụ xác thực không hợp lệ.": [
            .vi: "Dữ liệu trả về từ dịch vụ xác thực không hợp lệ.",
            .en: "Invalid response from authentication service."
        ],
        "Em": [
            .vi: "Em",
            .en: "Em"
        ],
        "Email đã xác minh:": [
            .vi: "Email đã xác minh:",
            .en: "Verified email:"
        ],
        "Game": [
            .vi: "Game",
            .en: "Gaming"
        ],
        "Gay / Đồng tính nam": [
            .vi: "Gay / Đồng tính nam",
            .en: "Gay"
        ],
        "Giao diện & Chế độ sáng/tối": [
            .vi: "Giao diện & Chế độ sáng/tối",
            .en: "Appearance & Light/Dark Mode"
        ],
        "Giới thiệu bản thân (Bio)": [
            .vi: "Giới thiệu bản thân (Bio)",
            .en: "About Me (Bio)"
        ],
        "Giới thiệu và sở thích": [
            .vi: "Giới thiệu và sở thích",
            .en: "About & Interests"
        ],
        "Gỡ cảm xúc": [
            .vi: "Gỡ cảm xúc",
            .en: "Remove reaction"
        ],
        "Gỡ nội dung tin nhắn": [
            .vi: "Gỡ nội dung tin nhắn",
            .en: "Remove message content"
        ],
        "Gỡ tài khoản đã ghi nhớ": [
            .vi: "Gỡ tài khoản đã ghi nhớ",
            .en: "Remove remembered account"
        ],
        "Gửi": [
            .vi: "Gửi",
            .en: "Send"
        ],
        "Gửi cho bạn bè": [
            .vi: "Gửi cho bạn bè",
            .en: "Send to Friends"
        ],
        "Gửi lại mã": [
            .vi: "Gửi lại mã",
            .en: "Resend code"
        ],
        "Gửi mã xác minh": [
            .vi: "Gửi mã xác minh",
            .en: "Send verification code"
        ],
        "Gửi phản hồi, báo cáo sự cố hoặc yêu cầu trợ giúp kỹ thuật từ đội ngũ phát triển Kinnect.": [
            .vi: "Gửi phản hồi, báo cáo sự cố hoặc yêu cầu trợ giúp kỹ thuật từ đội ngũ phát triển Kinnect.",
            .en: "Send feedback, bug reports, or technical help requests to the Kinnect team."
        ],
        "Gửi yêu cầu xem Album": [
            .vi: "Gửi yêu cầu xem Album",
            .en: "Request Album Access"
        ],
        "Hiển thị chấm xanh khi bạn đang trực tuyến trên Kinnect.": [
            .vi: "Hiển thị chấm xanh khi bạn đang trực tuyến trên Kinnect.",
            .en: "Show a green dot when you are online on Kinnect."
        ],
        "Hiển thị thông tin bản dạng công khai": [
            .vi: "Hiển thị thông tin bản dạng công khai",
            .en: "Show identity info publicly"
        ],
        "Hiện": [
            .vi: "Hiện",
            .en: "Show"
        ],
        "Hiện bài": [
            .vi: "Hiện bài",
            .en: "Restore post"
        ],
        "Hiện tuổi": [
            .vi: "Hiện tuổi",
            .en: "Show age"
        ],
        "Hiện video": [
            .vi: "Hiện video",
            .en: "Restore video"
        ],
        "Hoàn tất xác thực 2FA OAuth": [
            .vi: "Hoàn tất xác thực 2FA OAuth",
            .en: "Complete OAuth 2FA Verification"
        ],
        "Hoặc nhập mật khẩu hiện tại": [
            .vi: "Hoặc nhập mật khẩu hiện tại",
            .en: "Or enter current password"
        ],
        "Hoặc tạo lại khóa 2FA mới": [
            .vi: "Hoặc tạo lại khóa 2FA mới",
            .en: "Or regenerate 2FA key"
        ],
        "Huỷ kết bạn": [
            .vi: "Huỷ kết bạn",
            .en: "Unfriend"
        ],
        "Huỷ lời mời": [
            .vi: "Huỷ lời mời",
            .en: "Cancel request"
        ],
        "Hà Nội, TP. Hồ Chí Minh...": [
            .vi: "Hà Nội, TP. Hồ Chí Minh...",
            .en: "Hanoi, Ho Chi Minh City..."
        ],
        "Hình ảnh đại diện": [
            .vi: "Hình ảnh đại diện",
            .en: "Profile Photos"
        ],
        "Hẹn hò": [
            .vi: "Hẹn hò",
            .en: "Dating"
        ],
        "Hết hạn": [
            .vi: "Hết hạn",
            .en: "Expires"
        ],
        "Hệ thống": [
            .vi: "Hệ thống",
            .en: "System"
        ],
        "Họ / They": [
            .vi: "Họ / They",
            .en: "They / Them"
        ],
        "Hỗ trợ": [
            .vi: "Hỗ trợ",
            .en: "Support"
        ],
        "Hỗ trợ Kinnect": [
            .vi: "Hỗ trợ Kinnect",
            .en: "Kinnect Support"
        ],
        "Hủy kết bạn": [
            .vi: "Hủy kết bạn",
            .en: "Unfriend"
        ],
        "Hủy kết bạn?": [
            .vi: "Hủy kết bạn?",
            .en: "Unfriend?"
        ],
        "Khi tắt, nhóm bản dạng giới và xu hướng của bạn được giữ riêng tư.": [
            .vi: "Khi tắt, nhóm bản dạng giới và xu hướng của bạn được giữ riêng tư.",
            .en: "When off, your gender identity and orientation remain private."
        ],
        "Khung hình xem trước": [
            .vi: "Khung hình xem trước",
            .en: "Preview frame"
        ],
        "Khác": [
            .vi: "Khác",
            .en: "Other"
        ],
        "Khóa bí mật (Secret):": [
            .vi: "Khóa bí mật (Secret):",
            .en: "Secret Key:"
        ],
        "Khôi phục": [
            .vi: "Khôi phục",
            .en: "Restore"
        ],
        "Không có thông báo chưa đọc.": [
            .vi: "Không có thông báo chưa đọc.",
            .en: "No unread notifications."
        ],
        "Không muốn tiết lộ": [
            .vi: "Không muốn tiết lộ",
            .en: "Prefer not to say"
        ],
        "Không nhận được phản hồi từ dịch vụ xác thực.": [
            .vi: "Không nhận được phản hồi từ dịch vụ xác thực.",
            .en: "No response from authentication service."
        ],
        "Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.": [
            .vi: "Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.",
            .en: "Unable to reach Kinnect servers. Please check your Internet connection."
        ],
        "Không thể lưu:": [
            .vi: "Không thể lưu:",
            .en: "Could not save:"
        ],
        "Không thể tải danh sách khám phá": [
            .vi: "Không thể tải danh sách khám phá",
            .en: "Could not load Discover feed"
        ],
        "Không thể tải hồ sơ hiện tại. Thử lại trước khi lưu để tránh ghi đè dữ liệu.": [
            .vi: "Không thể tải hồ sơ hiện tại. Thử lại trước khi lưu để tránh ghi đè dữ liệu.",
            .en: "Could not load current profile. Please retry before saving to avoid overwriting data."
        ],
        "Không thể xử lý ảnh đã chọn (tối đa ~3.5 MB sau khi nén).": [
            .vi: "Không thể xử lý ảnh đã chọn (tối đa ~3.5 MB sau khi nén).",
            .en: "Unable to process selected photo (max ~3.5 MB after compression)."
        ],
        "Không thể xử lý ảnh đã chọn (tối đa ~920 KB sau khi nén).": [
            .vi: "Không thể xử lý ảnh đã chọn (tối đa ~920 KB sau khi nén).",
            .en: "Unable to process selected photo (max ~920 KB after compression)."
        ],
        "Không tìm thấy thông báo.": [
            .vi: "Không tìm thấy thông báo.",
            .en: "No notifications found."
        ],
        "Không tìm thấy video để lưu.": [
            .vi: "Không tìm thấy video để lưu.",
            .en: "Video not found for saving."
        ],
        "Không tạo được phiên đăng nhập.": [
            .vi: "Không tạo được phiên đăng nhập.",
            .en: "Could not create session."
        ],
        "Không tải được hồ sơ:": [
            .vi: "Không tải được hồ sơ:",
            .en: "Could not load profile:"
        ],
        "Không tải được media (mã %d).": [
            .vi: "Không tải được media (mã %d).",
            .en: "Failed to load media (code %d)."
        ],
        "Không xác định được tài khoản hiện tại.": [
            .vi: "Không xác định được tài khoản hiện tại.",
            .en: "Could not identify current account."
        ],
        "Kinh tế, trợ lý AI và thư viện nhạc chưa có trên màn này.": [
            .vi: "Kinh tế, trợ lý AI và thư viện nhạc chưa có trên màn này.",
            .en: "Economy, AI assistant, and music library are not available on this screen."
        ],
        "Kinnect Audio": [
            .vi: "Kinnect Audio",
            .en: "Kinnect Audio"
        ],
        "Kích hoạt 2FA": [
            .vi: "Kích hoạt 2FA",
            .en: "Activate 2FA"
        ],
        "Kết bạn": [
            .vi: "Kết bạn",
            .en: "Add Friend"
        ],
        "Kết nối và cuộc sống": [
            .vi: "Kết nối và cuộc sống",
            .en: "Connections & Lifestyle"
        ],
        "Kết quả tìm kiếm": [
            .vi: "Kết quả tìm kiếm",
            .en: "Search Results"
        ],
        "Kết thúc": [
            .vi: "Kết thúc",
            .en: "End"
        ],
        "Kết thúc cuộc gọi": [
            .vi: "Kết thúc cuộc gọi",
            .en: "End call"
        ],
        "Lesbian / Đồng tính nữ": [
            .vi: "Lesbian / Đồng tính nữ",
            .en: "Lesbian"
        ],
        "Linh hoạt giới": [
            .vi: "Linh hoạt giới",
            .en: "Genderfluid"
        ],
        "Liên hệ riêng Mr Ánh: anhvn53@wru.vn. Không gửi mật khẩu hoặc OTP.": [
            .vi: "Liên hệ riêng Mr Ánh: anhvn53@wru.vn. Không gửi mật khẩu hoặc OTP.",
            .en: "Direct contact Mr Anh: anhvn53@wru.vn. Never send your password or OTP."
        ],
        "Loa": [
            .vi: "Loa",
            .en: "Speaker"
        ],
        "Lý do": [
            .vi: "Lý do",
            .en: "Reason"
        ],
        "Lưu bài viết": [
            .vi: "Lưu bài viết",
            .en: "Bookmark Post"
        ],
        "Lưu cài đặt": [
            .vi: "Lưu cài đặt",
            .en: "Save Settings"
        ],
        "Lưu thay đổi": [
            .vi: "Lưu thay đổi",
            .en: "Save Changes"
        ],
        "Lưu trữ và đồng bộ lịch sử hội thoại an toàn qua máy chủ Kinnect.": [
            .vi: "Lưu trữ và đồng bộ lịch sử hội thoại an toàn qua máy chủ Kinnect.",
            .en: "Securely store and sync chat history across devices via Kinnect servers."
        ],
        "Lưu video": [
            .vi: "Lưu video",
            .en: "Save Video"
        ],
        "Lượt xem:": [
            .vi: "Lượt xem:",
            .en: "Views:"
        ],
        "Lập trình viên, Nhiếp ảnh gia...": [
            .vi: "Lập trình viên, Nhiếp ảnh gia...",
            .en: "Software Engineer, Photographer..."
        ],
        "Lỗi xác thực:": [
            .vi: "Lỗi xác thực:",
            .en: "Authentication error:"
        ],
        "Mic": [
            .vi: "Mic",
            .en: "Mic"
        ],
        "Mong muốn": [
            .vi: "Mong muốn",
            .en: "Looking for"
        ],
        "Mong muốn kết nối": [
            .vi: "Mong muốn kết nối",
            .en: "Looking For"
        ],
        "Mr Ánh · Hỗ trợ và quyền riêng tư: anhvn53@wru.vn": [
            .vi: "Mr Ánh · Hỗ trợ và quyền riêng tư: anhvn53@wru.vn",
            .en: "Mr Anh · Support & Privacy: anhvn53@wru.vn"
        ],
        "Máy chủ chính đang tạm thời gián đoạn. Vui lòng thử lại sau ít phút.": [
            .vi: "Máy chủ chính đang tạm thời gián đoạn. Vui lòng thử lại sau ít phút.",
            .en: "Main server is temporarily unavailable. Please try again in a few minutes."
        ],
        "Máy chủ chưa được cấu hình.": [
            .vi: "Máy chủ chưa được cấu hình.",
            .en: "Server is not configured."
        ],
        "Mã 2FA 6 số hoặc mã dự phòng": [
            .vi: "Mã 2FA 6 số hoặc mã dự phòng",
            .en: "6-digit 2FA or backup code"
        ],
        "Mã dự phòng còn lại": [
            .vi: "Mã dự phòng còn lại",
            .en: "Remaining backup codes"
        ],
        "Mã dự phòng khôi phục (Lưu giữ an toàn)": [
            .vi: "Mã dự phòng khôi phục (Lưu giữ an toàn)",
            .en: "Recovery Backup Codes (Keep Safe)"
        ],
        "Mã xác minh": [
            .vi: "Mã xác minh",
            .en: "Verification code"
        ],
        "Mã xác thực 2 bước (2FA)": [
            .vi: "Mã xác thực 2 bước (2FA)",
            .en: "Two-Factor Authentication Code (2FA)"
        ],
        "Mô tả yêu cầu / Báo cáo sự cố": [
            .vi: "Mô tả yêu cầu / Báo cáo sự cố",
            .en: "Describe your request / issue"
        ],
        "Mật khẩu của bạn": [
            .vi: "Mật khẩu của bạn",
            .en: "Your password"
        ],
        "Mật khẩu mới cần tối thiểu 6 ký tự. Sau khi đổi mật khẩu, phiên đăng nhập trên thiết bị hiện tại sẽ được duy trì và các thiết bị khác sẽ cần đăng nhập lại.": [
            .vi: "Mật khẩu mới cần tối thiểu 6 ký tự. Sau khi đổi mật khẩu, phiên đăng nhập trên thiết bị hiện tại sẽ được duy trì và các thiết bị khác sẽ cần đăng nhập lại.",
            .en: "New password must be at least 6 characters. After changing it, this device stays signed in while other devices will need to sign in again."
        ],
        "Mật khẩu phải có ít nhất 6 ký tự.": [
            .vi: "Mật khẩu phải có ít nhất 6 ký tự.",
            .en: "Password must be at least 6 characters."
        ],
        "Mọi thành viên (Công khai)": [
            .vi: "Mọi thành viên (Công khai)",
            .en: "Everyone (Public)"
        ],
        "Mối quan hệ mở": [
            .vi: "Mối quan hệ mở",
            .en: "Open relationship"
        ],
        "Mối quan hệ nghiêm túc": [
            .vi: "Mối quan hệ nghiêm túc",
            .en: "Serious relationship"
        ],
        "Mỗi mã dự phòng chỉ dùng được 1 lần khi bạn mất thiết bị xác thực.": [
            .vi: "Mỗi mã dự phòng chỉ dùng được 1 lần khi bạn mất thiết bị xác thực.",
            .en: "Each backup code can be used once if you lose your authenticator device."
        ],
        "Mở rộng cuộc gọi": [
            .vi: "Mở rộng cuộc gọi",
            .en: "Expand call"
        ],
        "Mục hồ sơ": [
            .vi: "Mục hồ sơ",
            .en: "Profile tabs"
        ],
        "Nam": [
            .vi: "Nam",
            .en: "Male"
        ],
        "Nam chuyển giới": [
            .vi: "Nam chuyển giới",
            .en: "Transgender Male"
        ],
        "Nghề nghiệp": [
            .vi: "Nghề nghiệp",
            .en: "Occupation"
        ],
        "Nghệ thuật": [
            .vi: "Nghệ thuật",
            .en: "Art"
        ],
        "Ngày sinh": [
            .vi: "Ngày sinh",
            .en: "Birth Date"
        ],
        "Ngày sinh chỉ bạn xem; biểu tượng 🌐 cho phép hiện tuổi trên hồ sơ.": [
            .vi: "Ngày sinh chỉ bạn xem; biểu tượng 🌐 cho phép hiện tuổi trên hồ sơ.",
            .en: "Your birth date is private; toggle 🌐 to show your age on your profile."
        ],
        "Người dùng đã chặn": [
            .vi: "Người dùng đã chặn",
            .en: "Blocked Users"
        ],
        "Người lạ cần gửi lời mời kết bạn trước khi nhắn tin trực tiếp.": [
            .vi: "Người lạ cần gửi lời mời kết bạn trước khi nhắn tin trực tiếp.",
            .en: "Strangers must send a friend request before messaging you directly."
        ],
        "Người theo dõi": [
            .vi: "Người theo dõi",
            .en: "Followers"
        ],
        "Người đã bày tỏ cảm xúc": [
            .vi: "Người đã bày tỏ cảm xúc",
            .en: "Reactions"
        ],
        "Người đã xem": [
            .vi: "Người đã xem",
            .en: "Viewers"
        ],
        "Nhiếp ảnh": [
            .vi: "Nhiếp ảnh",
            .en: "Photography"
        ],
        "Nhập chính xác tên đăng nhập của bạn để xác nhận": [
            .vi: "Nhập chính xác tên đăng nhập của bạn để xác nhận",
            .en: "Enter your exact username to confirm"
        ],
        "Nhập mã 6 chữ số hoặc mã dự phòng": [
            .vi: "Nhập mã 6 chữ số hoặc mã dự phòng",
            .en: "Enter 6-digit or backup code"
        ],
        "Nhập mã 6 chữ số từ ứng dụng": [
            .vi: "Nhập mã 6 chữ số từ ứng dụng",
            .en: "Enter 6-digit code from app"
        ],
        "Nhập mã xác minh trong email của bạn.": [
            .vi: "Nhập mã xác minh trong email của bạn.",
            .en: "Enter the verification code sent to your email."
        ],
        "Nhập mật khẩu hiện tại": [
            .vi: "Nhập mật khẩu hiện tại",
            .en: "Enter current password"
        ],
        "Nhập tên hiển thị...": [
            .vi: "Nhập tên hiển thị...",
            .en: "Enter display name..."
        ],
        "Nhắn tin": [
            .vi: "Nhắn tin",
            .en: "Message"
        ],
        "Những bài viết bạn chia sẻ trên Bảng tin sẽ xuất hiện tại đây.": [
            .vi: "Những bài viết bạn chia sẻ trên Bảng tin sẽ xuất hiện tại đây.",
            .en: "Posts you share to the feed will appear here."
        ],
        "Nói gì đó về bài viết này (tùy chọn)…": [
            .vi: "Nói gì đó về bài viết này (tùy chọn)…",
            .en: "Say something about this post (optional)…"
        ],
        "Nơi sống": [
            .vi: "Nơi sống",
            .en: "City"
        ],
        "Nữ": [
            .vi: "Nữ",
            .en: "Female"
        ],
        "Nữ chuyển giới": [
            .vi: "Nữ chuyển giới",
            .en: "Transgender Female"
        ],
        "Phi nhị nguyên": [
            .vi: "Phi nhị nguyên",
            .en: "Non-binary"
        ],
        "Phim ảnh": [
            .vi: "Phim ảnh",
            .en: "Movies"
        ],
        "Phiên Live đã kết thúc do mất kết nối.": [
            .vi: "Phiên Live đã kết thúc do mất kết nối.",
            .en: "Live stream ended due to disconnection."
        ],
        "Phiên hoạt động": [
            .vi: "Phiên hoạt động",
            .en: "Active Sessions"
        ],
        "Phiên phát trực tiếp đã kết thúc.": [
            .vi: "Phiên phát trực tiếp đã kết thúc.",
            .en: "Live stream has ended."
        ],
        "Phiên đăng nhập": [
            .vi: "Phiên đăng nhập",
            .en: "Login Sessions"
        ],
        "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.": [
            .vi: "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.",
            .en: "Your session has expired. Please sign in again."
        ],
        "Phản hồi máy chủ không hợp lệ.": [
            .vi: "Phản hồi máy chủ không hợp lệ.",
            .en: "Invalid server response."
        ],
        "Phản hồi xác thực không hợp lệ.": [
            .vi: "Phản hồi xác thực không hợp lệ.",
            .en: "Invalid authentication response."
        ],
        "Quay lại": [
            .vi: "Quay lại",
            .en: "Back"
        ],
        "Quyền riêng tư & Định vị": [
            .vi: "Quyền riêng tư & Định vị",
            .en: "Privacy & Location"
        ],
        "Quản lý & Tắt 2FA": [
            .vi: "Quản lý & Tắt 2FA",
            .en: "Manage & Disable 2FA"
        ],
        "Quản lý thông tin hiển thị với người dùng khác và mức độ khám phá tài khoản của bạn trên Kinnect.": [
            .vi: "Quản lý thông tin hiển thị với người dùng khác và mức độ khám phá tài khoản của bạn trên Kinnect.",
            .en: "Control what others see and how discoverable your profile is on Kinnect."
        ],
        "Quản lý ảnh & duyệt quyền xem": [
            .vi: "Quản lý ảnh & duyệt quyền xem",
            .en: "Manage photos & access requests"
        ],
        "Riêng tư": [
            .vi: "Riêng tư",
            .en: "Private"
        ],
        "Sao chép URI otpauth://": [
            .vi: "Sao chép URI otpauth://",
            .en: "Copy otpauth:// URI"
        ],
        "Sao chép khóa Secret": [
            .vi: "Sao chép khóa Secret",
            .en: "Copy Secret Key"
        ],
        "Sao chép liên kết": [
            .vi: "Sao chép liên kết",
            .en: "Copy Link"
        ],
        "Sao chép mã dự phòng": [
            .vi: "Sao chép mã dự phòng",
            .en: "Copy Backup Codes"
        ],
        "Song tính / Bisexual": [
            .vi: "Song tính / Bisexual",
            .en: "Bisexual"
        ],
        "Sở thích": [
            .vi: "Sở thích",
            .en: "Interests"
        ],
        "Tham gia Kinnect từ ": [
            .vi: "Tham gia Kinnect từ ",
            .en: "Joined Kinnect "
        ],
        "Theo dõi": [
            .vi: "Theo dõi",
            .en: "Follow"
        ],
        "Thiên nhiên": [
            .vi: "Thiên nhiên",
            .en: "Nature"
        ],
        "Thiết bị Kinnect": [
            .vi: "Thiết bị Kinnect",
            .en: "Kinnect Device"
        ],
        "Thiết bị hiện tại": [
            .vi: "Thiết bị hiện tại",
            .en: "Current device"
        ],
        "Thiết lập đang chờ xác nhận": [
            .vi: "Thiết lập đang chờ xác nhận",
            .en: "Setup pending verification"
        ],
        "Thu hồi": [
            .vi: "Thu hồi",
            .en: "Revoke"
        ],
        "Thu hồi yêu cầu xem": [
            .vi: "Thu hồi yêu cầu xem",
            .en: "Cancel access request"
        ],
        "Thu nhỏ cuộc gọi": [
            .vi: "Thu nhỏ cuộc gọi",
            .en: "Minimize call"
        ],
        "Thành viên": [
            .vi: "Thành viên",
            .en: "Member"
        ],
        "Thành viên gần đây": [
            .vi: "Thành viên gần đây",
            .en: "Recent Members"
        ],
        "Thành viên này chưa chia sẻ thông tin giới thiệu.": [
            .vi: "Thành viên này chưa chia sẻ thông tin giới thiệu.",
            .en: "This member has not shared any bio details yet."
        ],
        "Thành viên này chưa có ảnh riêng tư hoặc cần cấp quyền xem.": [
            .vi: "Thành viên này chưa có ảnh riêng tư hoặc cần cấp quyền xem.",
            .en: "This member has no private photos yet or requires access approval."
        ],
        "Thêm ảnh riêng tư mới (< 4MB)": [
            .vi: "Thêm ảnh riêng tư mới (< 4MB)",
            .en: "Add New Private Photo (< 4MB)"
        ],
        "Thông tin album riêng tư không còn khả dụng.": [
            .vi: "Thông tin album riêng tư không còn khả dụng.",
            .en: "Private album information is no longer available."
        ],
        "Thông tin cơ bản": [
            .vi: "Thông tin cơ bản",
            .en: "Basic Information"
        ],
        "Thông tin hữu ích": [
            .vi: "Thông tin hữu ích",
            .en: "Helpful Links"
        ],
        "Thông tin liên hệ (Email hoặc SĐT)": [
            .vi: "Thông tin liên hệ (Email hoặc SĐT)",
            .en: "Contact Info (Email or Phone)"
        ],
        "Thú cưng": [
            .vi: "Thú cưng",
            .en: "Pets"
        ],
        "Thể thao": [
            .vi: "Thể thao",
            .en: "Sports"
        ],
        "Thử lại": [
            .vi: "Thử lại",
            .en: "Retry"
        ],
        "Tin 24h": [
            .vi: "Tin 24h",
            .en: "24h Story"
        ],
        "Tin đã xóa sẽ không thể khôi phục.": [
            .vi: "Tin đã xóa sẽ không thể khôi phục.",
            .en: "Deleted stories cannot be recovered."
        ],
        "Tiểu sử": [
            .vi: "Tiểu sử",
            .en: "Bio"
        ],
        "Toàn tính / Pansexual": [
            .vi: "Toàn tính / Pansexual",
            .en: "Pansexual"
        ],
        "Trung tâm Hỗ trợ & Trợ giúp": [
            .vi: "Trung tâm Hỗ trợ & Trợ giúp",
            .en: "Help & Support Center"
        ],
        "Trò chuyện": [
            .vi: "Trò chuyện",
            .en: "Chatting"
        ],
        "Trường học": [
            .vi: "Trường học",
            .en: "School"
        ],
        "Trạng thái bảo mật": [
            .vi: "Trạng thái bảo mật",
            .en: "Security Status"
        ],
        "Trả lời": [
            .vi: "Trả lời",
            .en: "Answer"
        ],
        "Trả lời cuộc gọi": [
            .vi: "Trả lời cuộc gọi",
            .en: "Answer call"
        ],
        "Tuổi": [
            .vi: "Tuổi",
            .en: "Age"
        ],
        "Tài khoản %@ này chưa liên kết với tài khoản hiện tại của bạn.": [
            .vi: "Tài khoản %@ này chưa liên kết với tài khoản hiện tại của bạn.",
            .en: "This %@ account is not linked to your current account."
        ],
        "Tài khoản %@ vừa xác thực không khớp với tài khoản đang yêu cầu xóa.": [
            .vi: "Tài khoản %@ vừa xác thực không khớp với tài khoản đang yêu cầu xóa.",
            .en: "The %@ account you just verified does not match the account being deleted."
        ],
        "Tài khoản Apple vừa xác thực không khớp với tài khoản đang yêu cầu xóa.": [
            .vi: "Tài khoản Apple vừa xác thực không khớp với tài khoản đang yêu cầu xóa.",
            .en: "The Apple account you just verified does not match the account being deleted."
        ],
        "Tài khoản bật 2FA. Nhập mã 6 số rồi bấm xác thực lại hoặc xác nhận xóa tài khoản.": [
            .vi: "Tài khoản bật 2FA. Nhập mã 6 số rồi bấm xác thực lại hoặc xác nhận xóa tài khoản.",
            .en: "2FA is enabled. Enter your 6-digit code and tap reauthenticate or confirm deletion."
        ],
        "Tài khoản xác thực 2FA không khớp với tài khoản đang yêu cầu xóa.": [
            .vi: "Tài khoản xác thực 2FA không khớp với tài khoản đang yêu cầu xóa.",
            .en: "The 2FA account does not match the account requested for deletion."
        ],
        "Tài khoản yêu cầu mã xác thực 2 bước (2FA).": [
            .vi: "Tài khoản yêu cầu mã xác thực 2 bước (2FA).",
            .en: "This account requires a 2FA verification code."
        ],
        "Tài khoản đã ghi nhớ": [
            .vi: "Tài khoản đã ghi nhớ",
            .en: "Remembered Accounts"
        ],
        "Tìm kiếm thông báo…": [
            .vi: "Tìm kiếm thông báo…",
            .en: "Search notifications…"
        ],
        "Tìm kiếm...": [
            .vi: "Tìm kiếm...",
            .en: "Search..."
        ],
        "Tìm tên, @username hoặc sở thích…": [
            .vi: "Tìm tên, @username hoặc sở thích…",
            .en: "Search name, @username, or interests…"
        ],
        "Tình trạng quan hệ": [
            .vi: "Tình trạng quan hệ",
            .en: "Relationship Status"
        ],
        "Tùy chỉnh giao diện theo sở thích của bạn: Sáng, Tối hoặc tự động theo cài đặt iOS.": [
            .vi: "Tùy chỉnh giao diện theo sở thích của bạn: Sáng, Tối hoặc tự động theo cài đặt iOS.",
            .en: "Customize appearance: Light, Dark, or follow your iOS system setting."
        ],
        "Tùy chọn hồ sơ": [
            .vi: "Tùy chọn hồ sơ",
            .en: "Profile options"
        ],
        "Tạo khóa xác thực 2FA": [
            .vi: "Tạo khóa xác thực 2FA",
            .en: "Generate 2FA Secret Key"
        ],
        "Tạo lại 8 mã dự phòng mới": [
            .vi: "Tạo lại 8 mã dự phòng mới",
            .en: "Regenerate 8 Backup Codes"
        ],
        "Tải ảnh lên Album riêng tư": [
            .vi: "Tải ảnh lên Album riêng tư",
            .en: "Upload to Private Album"
        ],
        "Tất cả": [
            .vi: "Tất cả",
            .en: "All"
        ],
        "Tắt xác thực 2 bước": [
            .vi: "Tắt xác thực 2 bước",
            .en: "Disable 2FA"
        ],
        "Tối thiểu 6 ký tự": [
            .vi: "Tối thiểu 6 ký tự",
            .en: "At least 6 characters"
        ],
        "Tối đa": [
            .vi: "Tối đa",
            .en: "Maximum"
        ],
        "Từ chối": [
            .vi: "Từ chối",
            .en: "Decline"
        ],
        "Từ chối cuộc gọi": [
            .vi: "Từ chối cuộc gọi",
            .en: "Decline call"
        ],
        "Từ chối lời mời": [
            .vi: "Từ chối lời mời",
            .en: "Decline request"
        ],
        "Vai trò cộng đồng": [
            .vi: "Vai trò cộng đồng",
            .en: "Community Role"
        ],
        "Vai trò tự mô tả (tùy chọn)": [
            .vi: "Vai trò tự mô tả (tùy chọn)",
            .en: "Self-described role (optional)"
        ],
        "Video này không còn khả dụng hoặc đã bị xóa.": [
            .vi: "Video này không còn khả dụng hoặc đã bị xóa.",
            .en: "This video is no longer available or has been deleted."
        ],
        "Viết bình luận…": [
            .vi: "Viết bình luận…",
            .en: "Write a comment…"
        ],
        "Vui lòng chọn tên đăng nhập và xác nhận đủ 18 tuổi để hoàn tất đăng ký.": [
            .vi: "Vui lòng chọn tên đăng nhập và xác nhận đủ 18 tuổi để hoàn tất đăng ký.",
            .en: "Please choose a username and confirm you are 18+ to finish signing up."
        ],
        "Vui lòng nhập tên hiển thị.": [
            .vi: "Vui lòng nhập tên hiển thị.",
            .en: "Please enter a display name."
        ],
        "Vui lòng xác nhận bạn đủ 18 tuổi và đồng ý quy tắc cộng đồng.": [
            .vi: "Vui lòng xác nhận bạn đủ 18 tuổi và đồng ý quy tắc cộng đồng.",
            .en: "Please confirm you are 18+ and agree to community guidelines."
        ],
        "Vui lòng đồng ý Chính sách quyền riêng tư & Điều khoản Kinnect.": [
            .vi: "Vui lòng đồng ý Chính sách quyền riêng tư & Điều khoản Kinnect.",
            .en: "Please accept the Kinnect Privacy Policy & Terms."
        ],
        "Vô giới": [
            .vi: "Vô giới",
            .en: "Agender"
        ],
        "Vô tính / Asexual": [
            .vi: "Vô tính / Asexual",
            .en: "Asexual"
        ],
        "Xem bài viết trên Kinnect": [
            .vi: "Xem bài viết trên Kinnect",
            .en: "View post on Kinnect"
        ],
        "Xem trước hồ sơ": [
            .vi: "Xem trước hồ sơ",
            .en: "Preview Profile"
        ],
        "Xem trước hồ sơ công khai": [
            .vi: "Xem trước hồ sơ công khai",
            .en: "Public Profile Preview"
        ],
        "Xem tất cả bình luận": [
            .vi: "Xem tất cả bình luận",
            .en: "View all comments"
        ],
        "Xem ảnh riêng tư": [
            .vi: "Xem ảnh riêng tư",
            .en: "View private photo"
        ],
        "Xu hướng": [
            .vi: "Xu hướng",
            .en: "Orientation"
        ],
        "Xu hướng tính dục": [
            .vi: "Xu hướng tính dục",
            .en: "Sexual Orientation"
        ],
        "Xuất hiện trong Khám phá và danh sách người dùng Quanh đây.": [
            .vi: "Xuất hiện trong Khám phá và danh sách người dùng Quanh đây.",
            .en: "Appear in Discover and Nearby users lists."
        ],
        "Xác minh": [
            .vi: "Xác minh",
            .en: "Verify"
        ],
        "Xác nhận": [
            .vi: "Xác nhận",
            .en: "Confirm"
        ],
        "Xác nhận mật khẩu mới": [
            .vi: "Xác nhận mật khẩu mới",
            .en: "Confirm New Password"
        ],
        "Xác nhận thao tác quản trị?": [
            .vi: "Xác nhận thao tác quản trị?",
            .en: "Confirm admin action?"
        ],
        "Xác nhận xóa vĩnh viễn tài khoản": [
            .vi: "Xác nhận xóa vĩnh viễn tài khoản",
            .en: "Confirm Permanent Account Deletion"
        ],
        "Xác thực 2 bước (TOTP)": [
            .vi: "Xác thực 2 bước (TOTP)",
            .en: "Two-Factor Auth (TOTP)"
        ],
        "Xác thực lại bằng": [
            .vi: "Xác thực lại bằng",
            .en: "Reauthenticate with"
        ],
        "Xác thực lại tài khoản liên kết": [
            .vi: "Xác thực lại tài khoản liên kết",
            .en: "Reauthenticate Linked Account"
        ],
        "Xóa": [
            .vi: "Xóa",
            .en: "Delete"
        ],
        "Xóa bài viết": [
            .vi: "Xóa bài viết",
            .en: "Delete Post"
        ],
        "Xóa bài viết?": [
            .vi: "Xóa bài viết?",
            .en: "Delete post?"
        ],
        "Xóa bình luận": [
            .vi: "Xóa bình luận",
            .en: "Delete Comment"
        ],
        "Xóa bình luận?": [
            .vi: "Xóa bình luận?",
            .en: "Delete comment?"
        ],
        "Xóa tin": [
            .vi: "Xóa tin",
            .en: "Delete Story"
        ],
        "Xóa tin 24h?": [
            .vi: "Xóa tin 24h?",
            .en: "Delete 24h story?"
        ],
        "Xóa tài khoản": [
            .vi: "Xóa tài khoản",
            .en: "Delete Account"
        ],
        "Xóa tài khoản là hành động không thể đảo ngược.": [
            .vi: "Xóa tài khoản là hành động không thể đảo ngược.",
            .en: "Account deletion is irreversible."
        ],
        "Xóa tìm kiếm": [
            .vi: "Xóa tìm kiếm",
            .en: "Clear search"
        ],
        "Xóa ảnh bảo mật": [
            .vi: "Xóa ảnh bảo mật",
            .en: "Delete private photo"
        ],
        "Yêu cầu & Quyền truy cập": [
            .vi: "Yêu cầu & Quyền truy cập",
            .en: "Requests & Access"
        ],
        "Yêu cầu không thành công (mã %d).": [
            .vi: "Yêu cầu không thành công (mã %d).",
            .en: "Request failed (code %d)."
        ],
        "bài viết": [
            .vi: "bài viết",
            .en: "posts"
        ],
        "bình luận": [
            .vi: "bình luận",
            .en: "comments"
        ],
        "chờ duyệt": [
            .vi: "chờ duyệt",
            .en: "pending"
        ],
        "cảm xúc": [
            .vi: "cảm xúc",
            .en: "reactions"
        ],
        "gửi cảnh báo bảo mật tài khoản": [
            .vi: "gửi cảnh báo bảo mật tài khoản",
            .en: "sent an account security alert"
        ],
        "lựa chọn.": [
            .vi: "lựa chọn.",
            .en: "selections."
        ],
        "muốn xem ảnh riêng tư của bạn": [
            .vi: "muốn xem ảnh riêng tư của bạn",
            .en: "wants to view your private photos"
        ],
        "người theo dõi": [
            .vi: "người theo dõi",
            .en: "followers"
        ],
        "nhap@email.com hoặc 09xxxxxxxx": [
            .vi: "nhap@email.com hoặc 09xxxxxxxx",
            .en: "name@email.com or phone number"
        ],
        "phê duyệt.": [
            .vi: "phê duyệt.",
            .en: "approval."
        ],
        "sẽ không thể nhắn tin hoặc xem nội dung của bạn.": [
            .vi: "sẽ không thể nhắn tin hoặc xem nội dung của bạn.",
            .en: "will no longer be able to message you or view your content."
        ],
        "tuổi": [
            .vi: "tuổi",
            .en: "years old"
        ],
        "Á tính / Demisexual": [
            .vi: "Á tính / Demisexual",
            .en: "Demisexual"
        ],
        "Âm nhạc": [
            .vi: "Âm nhạc",
            .en: "Music"
        ],
        "Đang bật": [
            .vi: "Đang bật",
            .en: "Enabled"
        ],
        "Đang chờ bạn duyệt": [
            .vi: "Đang chờ bạn duyệt",
            .en: "Waiting for your approval"
        ],
        "Đang chờ duyệt": [
            .vi: "Đang chờ duyệt",
            .en: "Pending approval"
        ],
        "Đang gọi…": [
            .vi: "Đang gọi…",
            .en: "Calling…"
        ],
        "Đang gửi...": [
            .vi: "Đang gửi...",
            .en: "Sending..."
        ],
        "Đang hủy...": [
            .vi: "Đang hủy...",
            .en: "Canceling..."
        ],
        "Đang kích hoạt...": [
            .vi: "Đang kích hoạt...",
            .en: "Activating..."
        ],
        "Đang kết nối lại…": [
            .vi: "Đang kết nối lại…",
            .en: "Reconnecting…"
        ],
        "Đang kết nối…": [
            .vi: "Đang kết nối…",
            .en: "Connecting…"
        ],
        "Đang mã hóa & tải lên...": [
            .vi: "Đang mã hóa & tải lên...",
            .en: "Encrypting & uploading..."
        ],
        "Đang trong mối quan hệ": [
            .vi: "Đang trong mối quan hệ",
            .en: "In a relationship"
        ],
        "Đang tìm hiểu": [
            .vi: "Đang tìm hiểu",
            .en: "Questioning / Exploring"
        ],
        "Đang tìm thành viên…": [
            .vi: "Đang tìm thành viên…",
            .en: "Searching members…"
        ],
        "Đang tạo khóa...": [
            .vi: "Đang tạo khóa...",
            .en: "Generating key..."
        ],
        "Đang tạo lại...": [
            .vi: "Đang tạo lại...",
            .en: "Regenerating..."
        ],
        "Đang tải ảnh lên...": [
            .vi: "Đang tải ảnh lên...",
            .en: "Uploading photo..."
        ],
        "Đang tắt": [
            .vi: "Đang tắt",
            .en: "Disabled"
        ],
        "Đang tắt...": [
            .vi: "Đang tắt...",
            .en: "Disabling..."
        ],
        "Đang xác minh...": [
            .vi: "Đang xác minh...",
            .en: "Verifying..."
        ],
        "Đang đọc email khôi phục...": [
            .vi: "Đang đọc email khôi phục...",
            .en: "Loading recovery email..."
        ],
        "Đánh dấu tất cả đã đọc": [
            .vi: "Đánh dấu tất cả đã đọc",
            .en: "Mark all as read"
        ],
        "Đánh dấu đã đọc tất cả": [
            .vi: "Đánh dấu đã đọc tất cả",
            .en: "Mark all as read"
        ],
        "Đã bật xác thực 2 bước thành công!": [
            .vi: "Đã bật xác thực 2 bước thành công!",
            .en: "Two-factor authentication enabled!"
        ],
        "Đã bỏ chặn người dùng.": [
            .vi: "Đã bỏ chặn người dùng.",
            .en: "User unblocked."
        ],
        "Đã bỏ lưu bài viết.": [
            .vi: "Đã bỏ lưu bài viết.",
            .en: "Removed from saved posts."
        ],
        "Đã chia sẻ bài viết lên bảng tin.": [
            .vi: "Đã chia sẻ bài viết lên bảng tin.",
            .en: "Shared post to your feed."
        ],
        "Đã chấp nhận kết bạn!": [
            .vi: "Đã chấp nhận kết bạn!",
            .en: "Friend request accepted!"
        ],
        "Đã chặn %@. Nội dung của người này đã được ẩn.": [
            .vi: "Đã chặn %@. Nội dung của người này đã được ẩn.",
            .en: "Blocked %@. Their content is now hidden."
        ],
        "Đã cấp quyền": [
            .vi: "Đã cấp quyền",
            .en: "Granted"
        ],
        "Đã cấp quyền xem": [
            .vi: "Đã cấp quyền xem",
            .en: "Access granted"
        ],
        "Đã cấp quyền xem Album riêng tư.": [
            .vi: "Đã cấp quyền xem Album riêng tư.",
            .en: "Private album access granted."
        ],
        "Đã cập nhật bình luận.": [
            .vi: "Đã cập nhật bình luận.",
            .en: "Comment updated."
        ],
        "Đã cập nhật hình ảnh hồ sơ.": [
            .vi: "Đã cập nhật hình ảnh hồ sơ.",
            .en: "Profile photo updated."
        ],
        "Đã cập nhật hồ sơ cá nhân hoàn chỉnh.": [
            .vi: "Đã cập nhật hồ sơ cá nhân hoàn chỉnh.",
            .en: "Profile updated successfully."
        ],
        "Đã cập nhật quyền riêng tư.": [
            .vi: "Đã cập nhật quyền riêng tư.",
            .en: "Privacy settings updated."
        ],
        "Đã cập nhật ảnh thành công!": [
            .vi: "Đã cập nhật ảnh thành công!",
            .en: "Photo updated successfully!"
        ],
        "Đã gửi": [
            .vi: "Đã gửi",
            .en: "Sent"
        ],
        "Đã gửi báo cáo để quản trị viên xem xét.": [
            .vi: "Đã gửi báo cáo để quản trị viên xem xét.",
            .en: "Report submitted for admin review."
        ],
        "Đã gửi lời mời kết bạn": [
            .vi: "Đã gửi lời mời kết bạn",
            .en: "Friend request sent"
        ],
        "Đã gửi mã xác minh tới email của bạn.": [
            .vi: "Đã gửi mã xác minh tới email của bạn.",
            .en: "Verification code sent to your email."
        ],
        "Đã gửi thao tác quản trị.": [
            .vi: "Đã gửi thao tác quản trị.",
            .en: "Admin action submitted."
        ],
        "Đã gửi yêu cầu hỗ trợ thành công.": [
            .vi: "Đã gửi yêu cầu hỗ trợ thành công.",
            .en: "Support request submitted successfully."
        ],
        "Đã gửi yêu cầu lên sóng tới chủ phòng.": [
            .vi: "Đã gửi yêu cầu lên sóng tới chủ phòng.",
            .en: "Requested to join the live stream."
        ],
        "Đã gửi yêu cầu xem Album riêng tư.": [
            .vi: "Đã gửi yêu cầu xem Album riêng tư.",
            .en: "Private album access requested."
        ],
        "Đã huỷ lời mời": [
            .vi: "Đã huỷ lời mời",
            .en: "Request canceled"
        ],
        "Đã hủy kết bạn": [
            .vi: "Đã hủy kết bạn",
            .en: "Unfriended"
        ],
        "Đã hủy đăng nhập.": [
            .vi: "Đã hủy đăng nhập.",
            .en: "Sign-in canceled."
        ],
        "Đã khởi tạo khóa 2FA. Hãy nhập mã 6 số để hoàn tất.": [
            .vi: "Đã khởi tạo khóa 2FA. Hãy nhập mã 6 số để hoàn tất.",
            .en: "2FA key generated. Enter the 6-digit code to finish."
        ],
        "Đã kết hôn": [
            .vi: "Đã kết hôn",
            .en: "Married"
        ],
        "Đã kết nối": [
            .vi: "Đã kết nối",
            .en: "Connected"
        ],
        "Đã kết thúc": [
            .vi: "Đã kết thúc",
            .en: "Ended"
        ],
        "Đã lưu bài viết!": [
            .vi: "Đã lưu bài viết!",
            .en: "Post updated!"
        ],
        "Đã lưu bài viết.": [
            .vi: "Đã lưu bài viết.",
            .en: "Post bookmarked."
        ],
        "Đã lưu video vào thư viện Ảnh!": [
            .vi: "Đã lưu video vào thư viện Ảnh!",
            .en: "Video saved to Photos!"
        ],
        "Đã sao chép danh sách mã dự phòng.": [
            .vi: "Đã sao chép danh sách mã dự phòng.",
            .en: "Backup codes copied."
        ],
        "Đã sao chép khóa bí mật 2FA.": [
            .vi: "Đã sao chép khóa bí mật 2FA.",
            .en: "2FA secret key copied."
        ],
        "Đã sao chép liên kết bài viết!": [
            .vi: "Đã sao chép liên kết bài viết!",
            .en: "Post link copied!"
        ],
        "Đã sao chép liên kết otpauth://": [
            .vi: "Đã sao chép liên kết otpauth://",
            .en: "otpauth:// URI copied"
        ],
        "Đã thu hồi lời mời kết bạn": [
            .vi: "Đã thu hồi lời mời kết bạn",
            .en: "Friend request withdrawn"
        ],
        "Đã thu hồi quyền xem.": [
            .vi: "Đã thu hồi quyền xem.",
            .en: "Access revoked."
        ],
        "Đã thu hồi yêu cầu xem Album.": [
            .vi: "Đã thu hồi yêu cầu xem Album.",
            .en: "Album request withdrawn."
        ],
        "Đã thêm ảnh vào Album riêng tư.": [
            .vi: "Đã thêm ảnh vào Album riêng tư.",
            .en: "Photo added to Private Album."
        ],
        "Đã tạo mới mã dự phòng 2FA.": [
            .vi: "Đã tạo mới mã dự phòng 2FA.",
            .en: "Generated new 2FA backup codes."
        ],
        "Đã tắt xác thực 2 bước.": [
            .vi: "Đã tắt xác thực 2 bước.",
            .en: "Two-factor authentication disabled."
        ],
        "Đã từ chối lời mời": [
            .vi: "Đã từ chối lời mời",
            .en: "Request declined"
        ],
        "Đã từ chối yêu cầu.": [
            .vi: "Đã từ chối yêu cầu.",
            .en: "Request declined."
        ],
        "Đã xác minh email.": [
            .vi: "Đã xác minh email.",
            .en: "Email verified."
        ],
        "Đã xác thực 2FA. Bạn có thể tiếp tục xóa tài khoản.": [
            .vi: "Đã xác thực 2FA. Bạn có thể tiếp tục xóa tài khoản.",
            .en: "2FA verified. You may now continue deleting your account."
        ],
        "Đã xác thực lại tài khoản. Bạn có thể tiếp tục xóa tài khoản.": [
            .vi: "Đã xác thực lại tài khoản. Bạn có thể tiếp tục xóa tài khoản.",
            .en: "Account reauthenticated. You may now continue deleting your account."
        ],
        "Đã xóa bài viết": [
            .vi: "Đã xóa bài viết",
            .en: "Post deleted"
        ],
        "Đã xóa bài viết.": [
            .vi: "Đã xóa bài viết.",
            .en: "Post deleted."
        ],
        "Đã xóa bình luận.": [
            .vi: "Đã xóa bình luận.",
            .en: "Comment deleted."
        ],
        "Đã xóa tin 24h.": [
            .vi: "Đã xóa tin 24h.",
            .en: "Story deleted."
        ],
        "Đã xóa ảnh khỏi Album riêng tư.": [
            .vi: "Đã xóa ảnh khỏi Album riêng tư.",
            .en: "Photo removed from Private Album."
        ],
        "Đã đăng ảnh công khai mới!": [
            .vi: "Đã đăng ảnh công khai mới!",
            .en: "New public photo posted!"
        ],
        "Đã đọc": [
            .vi: "Đã đọc",
            .en: "Read"
        ],
        "Đã đổi đối tượng xem thành": [
            .vi: "Đã đổi đối tượng xem thành",
            .en: "Changed audience to"
        ],
        "Đã ẩn bài viết.": [
            .vi: "Đã ẩn bài viết.",
            .en: "Post hidden."
        ],
        "Đình chỉ": [
            .vi: "Đình chỉ",
            .en: "Suspend"
        ],
        "Đình chỉ tài khoản": [
            .vi: "Đình chỉ tài khoản",
            .en: "Suspend Account"
        ],
        "Đóng báo cáo": [
            .vi: "Đóng báo cáo",
            .en: "Dismiss Report"
        ],
        "Đóng video": [
            .vi: "Đóng video",
            .en: "Close video"
        ],
        "Đăng nhập nhanh": [
            .vi: "Đăng nhập nhanh",
            .en: "Quick Sign-In"
        ],
        "Đăng ảnh công khai mới": [
            .vi: "Đăng ảnh công khai mới",
            .en: "Post New Public Photo"
        ],
        "Đường dẫn OAuth không hợp lệ.": [
            .vi: "Đường dẫn OAuth không hợp lệ.",
            .en: "Invalid OAuth URL."
        ],
        "Đại học Bách Khoa...": [
            .vi: "Đại học Bách Khoa...",
            .en: "University of Technology..."
        ],
        "Địa chỉ máy chủ không hợp lệ.": [
            .vi: "Địa chỉ máy chủ không hợp lệ.",
            .en: "Invalid server address."
        ],
        "Đọc sách": [
            .vi: "Đọc sách",
            .en: "Reading"
        ],
        "Đồng bộ tin nhắn đám mây": [
            .vi: "Đồng bộ tin nhắn đám mây",
            .en: "Cloud Chat Sync"
        ],
        "Đổi Avatar": [
            .vi: "Đổi Avatar",
            .en: "Change Avatar"
        ],
        "Đổi camera": [
            .vi: "Đổi camera",
            .en: "Flip Camera"
        ],
        "Đổi Ảnh bìa": [
            .vi: "Đổi Ảnh bìa",
            .en: "Change Cover"
        ],
        "Đổi ảnh bìa": [
            .vi: "Đổi ảnh bìa",
            .en: "Change cover photo"
        ],
        "Đổi ảnh đại diện": [
            .vi: "Đổi ảnh đại diện",
            .en: "Change avatar"
        ],
        "Độc thân": [
            .vi: "Độc thân",
            .en: "Single"
        ],
        "đang phát trực tiếp": [
            .vi: "đang phát trực tiếp",
            .en: "is live now"
        ],
        "đang theo dõi": [
            .vi: "đang theo dõi",
            .en: "following"
        ],
        "đã bày tỏ cảm xúc với bình luận của bạn": [
            .vi: "đã bày tỏ cảm xúc với bình luận của bạn",
            .en: "reacted to your comment"
        ],
        "đã bình luận video ngắn của bạn": [
            .vi: "đã bình luận video ngắn của bạn",
            .en: "commented on your short"
        ],
        "đã bình luận về bài viết của bạn": [
            .vi: "đã bình luận về bài viết của bạn",
            .en: "commented on your post"
        ],
        "đã bắt đầu theo dõi bạn": [
            .vi: "đã bắt đầu theo dõi bạn",
            .en: "started following you"
        ],
        "đã chia sẻ bài viết của bạn": [
            .vi: "đã chia sẻ bài viết của bạn",
            .en: "shared your post"
        ],
        "đã chấp nhận lời mời kết bạn": [
            .vi: "đã chấp nhận lời mời kết bạn",
            .en: "accepted your friend request"
        ],
        "đã cấp quyền xem album riêng tư cho bạn": [
            .vi: "đã cấp quyền xem album riêng tư cho bạn",
            .en: "granted you access to their private album"
        ],
        "đã cập nhật trạng thái kiểm duyệt": [
            .vi: "đã cập nhật trạng thái kiểm duyệt",
            .en: "updated moderation status"
        ],
        "đã gọi cho bạn": [
            .vi: "đã gọi cho bạn",
            .en: "called you"
        ],
        "đã gọi nhỡ cho bạn": [
            .vi: "đã gọi nhỡ cho bạn",
            .en: "missed your call"
        ],
        "đã gửi lời mời kết bạn": [
            .vi: "đã gửi lời mời kết bạn",
            .en: "sent you a friend request"
        ],
        "đã gửi quà tặng cho bạn": [
            .vi: "đã gửi quà tặng cho bạn",
            .en: "sent you a gift"
        ],
        "đã gửi tin nhắn cho bạn": [
            .vi: "đã gửi tin nhắn cho bạn",
            .en: "sent you a message"
        ],
        "đã nhắn tin trong nhóm": [
            .vi: "đã nhắn tin trong nhóm",
            .en: "sent a message in the group"
        ],
        "đã phản hồi yêu cầu hỗ trợ": [
            .vi: "đã phản hồi yêu cầu hỗ trợ",
            .en: "replied to your support ticket"
        ],
        "đã thu hồi quyền xem album riêng tư": [
            .vi: "đã thu hồi quyền xem album riêng tư",
            .en: "revoked your private album access"
        ],
        "đã thích bài viết của bạn": [
            .vi: "đã thích bài viết của bạn",
            .en: "liked your post"
        ],
        "đã thích video ngắn của bạn": [
            .vi: "đã thích video ngắn của bạn",
            .en: "liked your short"
        ],
        "đã trả lời bình luận của bạn": [
            .vi: "đã trả lời bình luận của bạn",
            .en: "replied to your comment"
        ],
        "đã tương tác với bạn": [
            .vi: "đã tương tác với bạn",
            .en: "interacted with you"
        ],
        "Ảnh công khai": [
            .vi: "Ảnh công khai",
            .en: "Public Photos"
        ],
        "Ảnh trong Album riêng tư": [
            .vi: "Ảnh trong Album riêng tư",
            .en: "Photos in Private Album"
        ],
        "ảnh": [
            .vi: "ảnh",
            .en: "photos"
        ],
        "ảnh bài viết": [
            .vi: "ảnh bài viết",
            .en: "post photos"
        ],
        "ảnh riêng tư": [
            .vi: "ảnh riêng tư",
            .en: "private photos"
        ],
        "ảnh riêng tư. Gửi yêu cầu để được cấp quyền xem.": [
            .vi: "ảnh riêng tư. Gửi yêu cầu để được cấp quyền xem.",
            .en: "private photos. Request access to view."
        ],
        "Ẩm thực": [
            .vi: "Ẩm thực",
            .en: "Food & Dining"
        ],
        "Ẩn": [
            .vi: "Ẩn",
            .en: "Hide"
        ],

        // Relative Time
        "Vừa xong": [
            .vi: "Vừa xong",
            .en: "Just now"
        ],
        "phút": [
            .vi: "phút",
            .en: "min"
        ],
        "giờ": [
            .vi: "giờ",
            .en: "hr"
        ],
        "ngày": [
            .vi: "ngày",
            .en: "d"
        ],
        "Gần đây": [
            .vi: "Gần đây",
            .en: "Recently"
        ],

        // Wave 6B Live Sheets, Message Search & Group Calls
        "Đang tải danh sách người xem…": [
            .vi: "Đang tải danh sách người xem…",
            .en: "Loading viewer list…"
        ],
        "Chưa có người xem nào trong phòng.": [
            .vi: "Chưa có người xem nào trong phòng.",
            .en: "No viewers in the room yet."
        ],
        "Mời lên sóng": [
            .vi: "Mời lên sóng",
            .en: "Invite to stage"
        ],
        "Đã gửi lời mời tới %@.": [
            .vi: "Đã gửi lời mời tới %@.",
            .en: "Invitation sent to %@."
        ],
        "Người xem (%d)": [
            .vi: "Người xem (%d)",
            .en: "Viewers (%d)"
        ],
        "Yêu cầu xin lên sóng (%d)": [
            .vi: "Yêu cầu xin lên sóng (%d)",
            .en: "Co-host requests (%d)"
        ],
        "Chưa có yêu cầu nào.": [
            .vi: "Chưa có yêu cầu nào.",
            .en: "No requests yet."
        ],
        "Khán giả": [
            .vi: "Khán giả",
            .en: "Viewer"
        ],
        "Khách đang trên sóng (%d/3)": [
            .vi: "Khách đang trên sóng (%d/3)",
            .en: "Guests on stage (%d/3)"
        ],
        "Chưa có khách mời nào trên sóng.": [
            .vi: "Chưa có khách mời nào trên sóng.",
            .en: "No guests on stage yet."
        ],
        "Khách mời": [
            .vi: "Khách mời",
            .en: "Guest"
        ],
        "Gỡ khỏi sóng": [
            .vi: "Gỡ khỏi sóng",
            .en: "Remove from stage"
        ],
        "Mời khán giả lên sóng": [
            .vi: "Mời khán giả lên sóng",
            .en: "Invite viewers to stage"
        ],
        "Chưa có khán giả khả dụng.": [
            .vi: "Chưa có khán giả khả dụng.",
            .en: "No available viewers."
        ],
        "Mời": [
            .vi: "Mời",
            .en: "Invite"
        ],
        "Khách mời lên sóng": [
            .vi: "Khách mời lên sóng",
            .en: "Live Co-Hosts"
        ],
        "Mục tiêu quà Live": [
            .vi: "Mục tiêu quà Live",
            .en: "Live Gift Goal"
        ],
        "%@ / %@ xu": [
            .vi: "%@ / %@ xu",
            .en: "%@ / %@ coins"
        ],
        "Cài đặt mục tiêu quà": [
            .vi: "Cài đặt mục tiêu quà",
            .en: "Gift Goal Settings"
        ],
        "Tên mục tiêu (vd: Mục tiêu 500 xu)": [
            .vi: "Tên mục tiêu (vd: Mục tiêu 500 xu)",
            .en: "Goal title (e.g. 500 coins goal)"
        ],
        "Số xu mục tiêu (50 - 1.000.000)": [
            .vi: "Số xu mục tiêu (50 - 1.000.000)",
            .en: "Target coins (50 - 1,000,000)"
        ],
        "Đặt mục tiêu": [
            .vi: "Đặt mục tiêu",
            .en: "Set Goal"
        ],
        "Mục tiêu tối thiểu 50 xu.": [
            .vi: "Mục tiêu tối thiểu 50 xu.",
            .en: "Minimum goal is 50 coins."
        ],
        "Xóa mục tiêu": [
            .vi: "Xóa mục tiêu",
            .en: "Remove Goal"
        ],
        "Xếp hạng tặng quà (%d quà · %@ xu)": [
            .vi: "Xếp hạng tặng quà (%d quà · %@ xu)",
            .en: "Gift Ranking (%d gifts · %@ coins)"
        ],
        "Chưa có lượt tặng quà nào trong phiên Live này.": [
            .vi: "Chưa có lượt tặng quà nào trong phiên Live này.",
            .en: "No gifts sent in this Live session yet."
        ],
        "%d món quà": [
            .vi: "%d món quà",
            .en: "%d gifts"
        ],
        "%@ xu": [
            .vi: "%@ xu",
            .en: "%@ coins"
        ],
        "Bảng xếp hạng quà": [
            .vi: "Bảng xếp hạng quà",
            .en: "Gift Leaderboard"
        ],
        "Xem danh sách người xem": [
            .vi: "Xem danh sách người xem",
            .en: "View viewer list"
        ],
        "BXH Quà": [
            .vi: "BXH Quà",
            .en: "Top Gifts"
        ],
        "Bảng xếp hạng quà Live": [
            .vi: "Bảng xếp hạng quà Live",
            .en: "Live Gift Leaderboard"
        ],
        "Quản lý khách mời lên sóng": [
            .vi: "Quản lý khách mời lên sóng",
            .en: "Manage live co-hosts"
        ],
        "Đổi bố cục khung hình": [
            .vi: "Đổi bố cục khung hình",
            .en: "Switch stage layout"
        ],
        "Đang tìm tin nhắn…": [
            .vi: "Đang tìm tin nhắn…",
            .en: "Searching messages…"
        ],
        "Nhập từ khóa để tìm trong lịch sử trò chuyện.": [
            .vi: "Nhập từ khóa để tìm trong lịch sử trò chuyện.",
            .en: "Enter keywords to search chat history."
        ],
        "Không tìm thấy tin nhắn phù hợp.": [
            .vi: "Không tìm thấy tin nhắn phù hợp.",
            .en: "No matching messages found."
        ],
        "Tìm trong %@…": [
            .vi: "Tìm trong %@…",
            .en: "Search in %@…"
        ],
        "Tìm tin nhắn": [
            .vi: "Tìm tin nhắn",
            .en: "Search Messages"
        ],
        "Cuộc gọi nhóm đang diễn ra (%d người)": [
            .vi: "Cuộc gọi nhóm đang diễn ra (%d người)",
            .en: "Group call in progress (%d people)"
        ],
        "Tham gia": [
            .vi: "Tham gia",
            .en: "Join"
        ],
        "Tin nhắn đã ghim": [
            .vi: "Tin nhắn đã ghim",
            .en: "Pinned message"
        ],
        "Gọi thoại nhóm": [
            .vi: "Gọi thoại nhóm",
            .en: "Group voice call"
        ],
        "Gọi video nhóm": [
            .vi: "Gọi video nhóm",
            .en: "Group video call"
        ],
        "Tìm tin nhắn nhóm": [
            .vi: "Tìm tin nhắn nhóm",
            .en: "Search group messages"
        ],
        "Tìm kiếm tin nhắn": [
            .vi: "Tìm kiếm tin nhắn",
            .en: "Search messages"
        ],
        "Đang tham gia cuộc gọi nhóm…": [
            .vi: "Đang tham gia cuộc gọi nhóm…",
            .en: "Joining group call…"
        ],
        "Chưa kết nối được máy chủ.": [
            .vi: "Chưa kết nối được máy chủ.",
            .en: "Could not connect to server."
        ],
        "Đang trong cuộc gọi nhóm": [
            .vi: "Đang trong cuộc gọi nhóm",
            .en: "In group call"
        ],
        "Lỗi cuộc gọi nhóm.": [
            .vi: "Lỗi cuộc gọi nhóm.",
            .en: "Group call error."
        ],
        "Bạn (Tắt mic)": [
            .vi: "Bạn (Tắt mic)",
            .en: "You (Muted)"
        ],
        "%@ (Tắt mic)": [
            .vi: "%@ (Tắt mic)",
            .en: "%@ (Muted)"
        ],
        "Bật camera": [
            .vi: "Bật camera",
            .en: "Turn camera on"
        ],
        "Tắt camera": [
            .vi: "Tắt camera",
            .en: "Turn camera off"
        ],
        "Bật mic": [
            .vi: "Bật mic",
            .en: "Unmute microphone"
        ],
        "Tắt mic": [
            .vi: "Tắt mic",
            .en: "Mute microphone"
        ],
        "Lật camera": [
            .vi: "Lật camera",
            .en: "Flip camera"
        ],
        "Rời cuộc gọi nhóm": [
            .vi: "Rời cuộc gọi nhóm",
            .en: "Leave group call"
        ],
        "Phát Live": [
            .vi: "Phát Live",
            .en: "Go Live"
        ],
        "Lật": [
            .vi: "Lật",
            .en: "Flip"
        ],
        "Bố cục": [
            .vi: "Bố cục",
            .en: "Layout"
        ],
        "Lưới": [
            .vi: "Lưới",
            .en: "Grid"
        ],
        "Hiệu ứng": [
            .vi: "Hiệu ứng",
            .en: "Effects"
        ],
        "Hiệu ứng Live": [
            .vi: "Hiệu ứng Live",
            .en: "Live Effects"
        ],
        "Gửi bình luận": [
            .vi: "Gửi bình luận",
            .en: "Send comment"
        ],
        "Bật micro": [
            .vi: "Bật micro",
            .en: "Unmute mic"
        ],
        "Tắt micro": [
            .vi: "Tắt micro",
            .en: "Mute mic"
        ],
        "Trò chuyện...": [
            .vi: "Trò chuyện...",
            .en: "Say something..."
        ],
        "Chủ phòng đã tắt bình luận": [
            .vi: "Chủ phòng đã tắt bình luận",
            .en: "Host disabled comments"
        ],
        "Âm thanh": [
            .vi: "Âm thanh",
            .en: "Audio"
        ],
        "Bật âm thanh": [
            .vi: "Bật âm thanh",
            .en: "Unmute audio"
        ],
        "Tắt tiếng": [
            .vi: "Tắt tiếng",
            .en: "Mute audio"
        ],
        "Đang chờ": [
            .vi: "Đang chờ",
            .en: "Pending"
        ],
        "Lên sóng": [
            .vi: "Lên sóng",
            .en: "Go live"
        ],
        "Hủy yêu cầu lên sóng": [
            .vi: "Hủy yêu cầu lên sóng",
            .en: "Cancel co-host request"
        ],
        "Xin lên sóng": [
            .vi: "Xin lên sóng",
            .en: "Request to join"
        ],

        // Wave 4 UI Parity (Studio, Live, Chat, Call, Auth, Store, Shorts)
        "Báo cáo người dùng": [
            .vi: "Báo cáo người dùng",
            .en: "Report user"
        ],
        "Bình luận phòng Live...": [
            .vi: "Bình luận phòng Live...",
            .en: "Comment in Live room..."
        ],
        "Bật lưới bố cục": [
            .vi: "Bật lưới bố cục",
            .en: "Turn on composition grid"
        ],
        "Bật thông báo": [
            .vi: "Bật thông báo",
            .en: "Turn on notifications"
        ],
        "Bật đèn flash": [
            .vi: "Bật đèn flash",
            .en: "Turn on flash"
        ],
        "Bắt đầu phát Live": [
            .vi: "Bắt đầu phát Live",
            .en: "Start Live Broadcast"
        ],
        "Bỏ ghim hội thoại": [
            .vi: "Bỏ ghim hội thoại",
            .en: "Unpin conversation"
        ],
        "Bộ lọc Pro": [
            .vi: "Bộ lọc Pro",
            .en: "Pro Filters"
        ],
        "Bộ lọc màu & Hiệu ứng Pro": [
            .vi: "Bộ lọc màu & Hiệu ứng Pro",
            .en: "Pro Color Filters & Effects"
        ],
        "Chia sẻ video": [
            .vi: "Chia sẻ video",
            .en: "Share video"
        ],
        "Cho phép khán giả bình luận": [
            .vi: "Cho phép khán giả bình luận",
            .en: "Allow viewer comments"
        ],
        "Chuyển tiếp tin nhắn": [
            .vi: "Chuyển tiếp tin nhắn",
            .en: "Forward message"
        ],
        "Chưa có buổi live": [
            .vi: "Chưa có buổi live",
            .en: "No live streams yet"
        ],
        "Chặn người dùng": [
            .vi: "Chặn người dùng",
            .en: "Block user"
        ],
        "Chọn nhạc nền cho bài đăng hoặc video": [
            .vi: "Chọn nhạc nền cho bài đăng hoặc video",
            .en: "Choose background music for post or video"
        ],
        "Chủ đề": [
            .vi: "Chủ đề",
            .en: "Topic"
        ],
        "Công nghệ Kinnect Studio Pro": [
            .vi: "Công nghệ Kinnect Studio Pro",
            .en: "Kinnect Studio Pro Engine"
        ],
        "Cắt & xoay": [
            .vi: "Cắt & xoay",
            .en: "Crop & Rotate"
        ],
        "Ghim hội thoại": [
            .vi: "Ghim hội thoại",
            .en: "Pin conversation"
        ],
        "Ghim tin nhắn": [
            .vi: "Ghim tin nhắn",
            .en: "Pin message"
        ],
        "Giữ nguyên màu sắc tự nhiên ban đầu": [
            .vi: "Giữ nguyên màu sắc tự nhiên ban đầu",
            .en: "Keep original natural colors"
        ],
        "Giữ xem gốc": [
            .vi: "Giữ xem gốc",
            .en: "Hold for original"
        ],
        "Giữ để xem ảnh gốc": [
            .vi: "Giữ để xem ảnh gốc",
            .en: "Hold to preview original photo"
        ],
        "Gán nhạc": [
            .vi: "Gán nhạc",
            .en: "Add music"
        ],
        "Gán nhạc nền cho video": [
            .vi: "Gán nhạc nền cho video",
            .en: "Add background music to video"
        ],
        "Hãy là người mở màn!": [
            .vi: "Hãy là người mở màn!",
            .en: "Be the first to go live!"
        ],
        "Hẹn giờ chụp": [
            .vi: "Hẹn giờ chụp",
            .en: "Capture timer"
        ],
        "Không thể tải danh sách phòng Live": [
            .vi: "Không thể tải danh sách phòng Live",
            .en: "Unable to load Live rooms"
        ],
        "Kinnect Studio Pro": [
            .vi: "Kinnect Studio Pro",
            .en: "Kinnect Studio Pro"
        ],
        "Làm mịn": [
            .vi: "Làm mịn",
            .en: "Smooth"
        ],
        "Làm mới danh sách Live": [
            .vi: "Làm mới danh sách Live",
            .en: "Refresh Live list"
        ],
        "Lưu vào thiết bị": [
            .vi: "Lưu vào thiết bị",
            .en: "Save to device"
        ],
        "Màu sắc rực rỡ, độ tương phản sống động": [
            .vi: "Màu sắc rực rỡ, độ tương phản sống động",
            .en: "Vibrant colors and lively contrast"
        ],
        "Mẫu màu Studio Pro:": [
            .vi: "Mẫu màu Studio Pro:",
            .en: "Studio Pro Presets:"
        ],
        "Mịn da tự nhiên, sáng dịu và hài hòa": [
            .vi: "Mịn da tự nhiên, sáng dịu và hài hòa",
            .en: "Natural skin smoothing with soft balance"
        ],
        "Ngoại tuyến": [
            .vi: "Ngoại tuyến",
            .en: "Offline"
        ],
        "Nhập chủ đề buổi Live": [
            .vi: "Nhập chủ đề buổi Live",
            .en: "Enter Live topic"
        ],
        "Phát live": [
            .vi: "Phát live",
            .en: "Go Live"
        ],
        "Quà từ xu tặng không tạo tiền rút": [
            .vi: "Quà từ xu tặng không tạo tiền rút",
            .en: "Gifts from gifted coins do not generate withdrawable cash"
        ],
        "Số lượng:": [
            .vi: "Số lượng:",
            .en: "Quantity:"
        ],
        "Sửa tin nhắn": [
            .vi: "Sửa tin nhắn",
            .en: "Edit message"
        ],
        "Thoát": [
            .vi: "Thoát",
            .en: "Exit"
        ],
        "Thoát Camera": [
            .vi: "Thoát Camera",
            .en: "Exit Camera"
        ],
        "Thu hồi / Xóa tin nhắn": [
            .vi: "Thu hồi / Xóa tin nhắn",
            .en: "Unsend / Delete message"
        ],
        "Thêm nhạc": [
            .vi: "Thêm nhạc",
            .en: "Add music"
        ],
        "Thông tin phòng Live": [
            .vi: "Thông tin phòng Live",
            .en: "Live Room Info"
        ],
        "Tiêu đề": [
            .vi: "Tiêu đề",
            .en: "Title"
        ],
        "Tiêu đề buổi Live": [
            .vi: "Tiêu đề buổi Live",
            .en: "Live Stream Title"
        ],
        "Trong kho": [
            .vi: "Trong kho",
            .en: "In bag"
        ],
        "Trực tiếp": [
            .vi: "Trực tiếp",
            .en: "Live"
        ],
        "Tông màu điện ảnh sâu lắng, có chiều sâu": [
            .vi: "Tông màu điện ảnh sâu lắng, có chiều sâu",
            .en: "Deep cinematic tone with rich depth"
        ],
        "Tùy chọn hội thoại": [
            .vi: "Tùy chọn hội thoại",
            .en: "Conversation options"
        ],
        "Tùy chọn tin nhắn": [
            .vi: "Tùy chọn tin nhắn",
            .en: "Message options"
        ],
        "Tùy chọn video": [
            .vi: "Tùy chọn video",
            .en: "Video options"
        ],
        "Tắt lưới bố cục": [
            .vi: "Tắt lưới bố cục",
            .en: "Turn off composition grid"
        ],
        "Tắt thông báo": [
            .vi: "Tắt thông báo",
            .en: "Mute notifications"
        ],
        "Tắt đèn flash": [
            .vi: "Tắt đèn flash",
            .en: "Turn off flash"
        ],
        "Tặng": [
            .vi: "Tặng",
            .en: "Send"
        ],
        "Tặng quà": [
            .vi: "Tặng quà",
            .en: "Send Gift"
        ],
        "Tặng từ kho": [
            .vi: "Tặng từ kho",
            .en: "Send from bag"
        ],
        "Vừa khung": [
            .vi: "Vừa khung",
            .en: "Fit frame"
        ],
        "Vừa khung hình ảnh": [
            .vi: "Vừa khung hình ảnh",
            .en: "Fit image to frame"
        ],
        "Xem hồ sơ": [
            .vi: "Xem hồ sơ",
            .en: "View profile"
        ],
        "Xem thử": [
            .vi: "Xem thử",
            .en: "Preview"
        ],
        "Xem thử Pro": [
            .vi: "Xem thử Pro",
            .en: "Pro Preview"
        ],
        "Xem tất cả": [
            .vi: "Xem tất cả",
            .en: "View all"
        ],
        "Xử lý chất lượng hình ảnh & video cao cấp": [
            .vi: "Xử lý chất lượng hình ảnh & video cao cấp",
            .en: "High-precision photo & video enhancement"
        ],
        "hoặc đăng ký bằng tài khoản": [
            .vi: "hoặc đăng ký bằng tài khoản",
            .en: "or sign up with an account"
        ],
        "thành viên": [
            .vi: "thành viên",
            .en: "members"
        ],
        "xu": [
            .vi: "xu",
            .en: "coins"
        ],
        "Ánh vàng ấm áp mang sắc hoàng hôn": [
            .vi: "Ánh vàng ấm áp mang sắc hoàng hôn",
            .en: "Warm golden sunset glow"
        ],
        "Áp dụng bộ lọc màu điện ảnh, cân bằng ánh sáng và tăng cường chi tiết sắc nét theo thời gian thực.": [
            .vi: "Áp dụng bộ lọc màu điện ảnh, cân bằng ánh sáng và tăng cường chi tiết sắc nét theo thời gian thực.",
            .en: "Apply cinematic color presets, balanced lighting, and crisp detail enhancement in real time."
        ],
        "Đang khởi tạo phòng Live…": [
            .vi: "Đang khởi tạo phòng Live…",
            .en: "Starting Live room…"
        ],
        "Đang trực tuyến": [
            .vi: "Đang trực tuyến",
            .en: "Online"
        ],
        "Đang tải phòng Live…": [
            .vi: "Đang tải phòng Live…",
            .en: "Loading Live rooms…"
        ],
        "Đang xem ảnh gốc": [
            .vi: "Đang xem ảnh gốc",
            .en: "Viewing original"
        ],
        "Đang đổ chuông...": [
            .vi: "Đang đổ chuông...",
            .en: "Ringing..."
        ],
        "Đen trắng nghệ thuật tương phản cao": [
            .vi: "Đen trắng nghệ thuật tương phản cao",
            .en: "High-contrast artistic monochrome"
        ],
        "Điều chỉnh": [
            .vi: "Điều chỉnh",
            .en: "Adjust"
        ],
        "Đổi thời lượng quay": [
            .vi: "Đổi thời lượng quay",
            .en: "Change recording duration"
        ],
        "Đổi tỉ lệ khung hình": [
            .vi: "Đổi tỉ lệ khung hình",
            .en: "Change aspect ratio"
        ],
        "Ảnh": [
            .vi: "Ảnh",
            .en: "Photo"
        ],
        "Đang tải cửa hàng…": [
            .vi: "Đang tải cửa hàng…",
            .en: "Loading store…"
        ],
        "Nguồn xu": [
            .vi: "Nguồn xu",
            .en: "Coin balance"
        ],
        "Xu tặng": [
            .vi: "Xu tặng",
            .en: "Gift coins"
        ],
        "Xu mua": [
            .vi: "Xu mua",
            .en: "Purchased coins"
        ],
        "Thanh toán bằng Xu mua": [
            .vi: "Thanh toán bằng Xu mua",
            .en: "Pay with Purchased coins"
        ],
        "xu mua": [
            .vi: "xu mua",
            .en: "purchased coins"
        ],
        "Khôi phục giao dịch": [
            .vi: "Khôi phục giao dịch",
            .en: "Restore purchases"
        ],
        "Đã kiểm tra và khôi phục các giao dịch hợp lệ.": [
            .vi: "Đã kiểm tra và khôi phục các giao dịch hợp lệ.",
            .en: "Checked and restored valid purchases."
        ],
        "Một số giao dịch chưa xác minh được. Hãy thử lại.": [
            .vi: "Một số giao dịch chưa xác minh được. Hãy thử lại.",
            .en: "Some purchases could not be verified. Please try again."
        ],
        "Chưa khôi phục được:": [
            .vi: "Chưa khôi phục được:",
            .en: "Could not restore:"
        ],
        "Phong cách mặc định": [
            .vi: "Phong cách mặc định",
            .en: "Default style"
        ],
        "Đã chuyển về phong cách mặc định": [
            .vi: "Đã chuyển về phong cách mặc định",
            .en: "Switched back to default style"
        ],
        "Chưa đổi được phong cách:": [
            .vi: "Chưa đổi được phong cách:",
            .en: "Could not change style:"
        ],
        "Thông tin cửa hàng": [
            .vi: "Thông tin cửa hàng",
            .en: "Store information"
        ],
        "Quyền lợi gắn với tài khoản Kinnect. Xem thử không thay đổi hồ sơ của bạn. Giá hiển thị quy đổi theo xu hoặc App Store.": [
            .vi: "Quyền lợi gắn với tài khoản Kinnect. Xem thử không thay đổi hồ sơ của bạn. Giá hiển thị quy đổi theo xu hoặc App Store.",
            .en: "Benefits are linked to your Kinnect account. Previewing does not modify your profile. Prices are shown in coins or App Store currency."
        ],
        "Xác nhận đổi gói?": [
            .vi: "Xác nhận đổi gói?",
            .en: "Confirm package exchange?"
        ],
        "Đổi ngay": [
            .vi: "Đổi ngay",
            .en: "Exchange now"
        ],
        "Gói:": [
            .vi: "Gói:",
            .en: "Package:"
        ],
        "Chi phí:": [
            .vi: "Chi phí:",
            .en: "Cost:"
        ],
        "Xem ví Kinnect": [
            .vi: "Xem ví Kinnect",
            .en: "View Kinnect Wallet"
        ],
        "Tùy chọn cửa hàng": [
            .vi: "Tùy chọn cửa hàng",
            .en: "Store options"
        ],
        "Xem thử miễn phí": [
            .vi: "Xem thử miễn phí",
            .en: "Free preview"
        ],
        "Thêm sắc màu.\nThêm chất riêng.": [
            .vi: "Thêm sắc màu.\nThêm chất riêng.",
            .en: "Add color.\nAdd your style."
        ],
        "Xin chào! Đây là bản xem thử.": [
            .vi: "Xin chào! Đây là bản xem thử.",
            .en: "Hello! This is a preview."
        ],
        "Xem thử không thay đổi hồ sơ thực tế của bạn.": [
            .vi: "Xem thử không thay đổi hồ sơ thực tế của bạn.",
            .en: "Previewing does not alter your live profile."
        ],
        "Mở khóa vĩnh viễn trên tài khoản Kinnect qua Apple ID.": [
            .vi: "Mở khóa vĩnh viễn trên tài khoản Kinnect qua Apple ID.",
            .en: "Permanently unlock on your Kinnect account via Apple ID."
        ],
        "Mở khóa qua App Store": [
            .vi: "Mở khóa qua App Store",
            .en: "Unlock via App Store"
        ],
        "Đang dùng": [
            .vi: "Đang dùng",
            .en: "Active"
        ],
        "Đã sở hữu": [
            .vi: "Đã sở hữu",
            .en: "Owned"
        ],
        "Mở Studio Pro": [
            .vi: "Mở Studio Pro",
            .en: "Open Studio Pro"
        ],
        "Gỡ trang trí": [
            .vi: "Gỡ trang trí",
            .en: "Remove decoration"
        ],
        "Dùng": [
            .vi: "Dùng",
            .en: "Use"
        ],
        "Mua": [
            .vi: "Mua",
            .en: "Buy"
        ],
        "Chưa mở App Store": [
            .vi: "Chưa mở App Store",
            .en: "Could not open App Store"
        ],
        "Trò chuyện · Miễn phí": [
            .vi: "Trò chuyện · Miễn phí",
            .en: "Chat · Free"
        ],
        "MIỄN PHÍ": [
            .vi: "MIỄN PHÍ",
            .en: "FREE"
        ],
        "Phát trực tiếp trò chuyện với bạn bè, bộ lọc làm đẹp và nhận quà tặng hoàn toàn miễn phí.": [
            .vi: "Phát trực tiếp trò chuyện với bạn bè, bộ lọc làm đẹp và nhận quà tặng hoàn toàn miễn phí.",
            .en: "Go live to chat with friends, apply beauty filters, and receive gifts completely free."
        ],
        "Kho quà Live": [
            .vi: "Kho quà Live",
            .en: "Live gift inventory"
        ],
        "món quà": [
            .vi: "món quà",
            .en: "gifts"
        ],
        "Chưa có quà dự trữ trong kho.": [
            .vi: "Chưa có quà dự trữ trong kho.",
            .en: "No gifts in inventory yet."
        ],
        "Chưa có gói trong mục này": [
            .vi: "Chưa có gói trong mục này",
            .en: "No packages in this category"
        ],
        "Còn": [
            .vi: "Còn",
            .en: "Left"
        ],
        "Gia hạn": [
            .vi: "Gia hạn",
            .en: "Renew"
        ],
        "Mua thêm": [
            .vi: "Mua thêm",
            .en: "Buy more"
        ],
        "Đang có gói": [
            .vi: "Đang có gói",
            .en: "Subscribed"
        ],
        "Đổi": [
            .vi: "Đổi",
            .en: "Redeem"
        ],
        "Mở Studio": [
            .vi: "Mở Studio",
            .en: "Open Studio"
        ],
        "Xem kho quà": [
            .vi: "Xem kho quà",
            .en: "View gift inventory"
        ],
        "Đang sử dụng": [
            .vi: "Đang sử dụng",
            .en: "In use"
        ],
        "Quyền Live Game": [
            .vi: "Quyền Live Game",
            .en: "Live Game access"
        ],
        "Gỡ trang bị": [
            .vi: "Gỡ trang bị",
            .en: "Unequip"
        ],
        "Áp dụng": [
            .vi: "Áp dụng",
            .en: "Apply"
        ],
        "xu tặng": [
            .vi: "xu tặng",
            .en: "gift coins"
        ],
        "Chưa đủ": [
            .vi: "Chưa đủ",
            .en: "Insufficient"
        ],
        "Cần": [
            .vi: "Cần",
            .en: "Need"
        ],
        "hiện có": [
            .vi: "hiện có",
            .en: "available"
        ],
        "Chưa tải được cửa hàng:": [
            .vi: "Chưa tải được cửa hàng:",
            .en: "Could not load store:"
        ],
        "Đã mở khóa": [
            .vi: "Đã mở khóa",
            .en: "Unlocked"
        ],
        "Máy chủ chưa xác nhận trang trí.": [
            .vi: "Máy chủ chưa xác nhận trang trí.",
            .en: "Server did not confirm decoration."
        ],
        "Đã gỡ trang trí.": [
            .vi: "Đã gỡ trang trí.",
            .en: "Decoration removed."
        ],
        "Đã áp dụng": [
            .vi: "Đã áp dụng",
            .en: "Applied"
        ],
        "Máy chủ chưa xác nhận quyền sử dụng gói.": [
            .vi: "Máy chủ chưa xác nhận quyền sử dụng gói.",
            .en: "Server did not confirm package entitlement."
        ],
        "Giao dịch đã được ghi nhận trước đó cho": [
            .vi: "Giao dịch đã được ghi nhận trước đó cho",
            .en: "Purchase was already recorded for"
        ],
        "Giao dịch chưa hoàn tất:": [
            .vi: "Giao dịch chưa hoàn tất:",
            .en: "Purchase incomplete:"
        ],
        "Huy hiệu thành viên được áp dụng tự động trong thời hạn gói.": [
            .vi: "Huy hiệu thành viên được áp dụng tự động trong thời hạn gói.",
            .en: "Membership badge applies automatically while the package is active."
        ],
        "Gói đã được ghi nhận. Phát màn hình game trên iOS đang được hoàn thiện.": [
            .vi: "Gói đã được ghi nhận. Phát màn hình game trên iOS đang được hoàn thiện.",
            .en: "Package recorded. Game screen streaming on iOS is coming soon."
        ],
        "Đã gỡ trang bị.": [
            .vi: "Đã gỡ trang bị.",
            .en: "Unequipped."
        ],
        "Đã kích hoạt": [
            .vi: "Đã kích hoạt",
            .en: "Activated"
        ],
        "Chưa kích hoạt được:": [
            .vi: "Chưa kích hoạt được:",
            .en: "Could not activate:"
        ],
        "Chơi game": [
            .vi: "Chơi game",
            .en: "Gaming"
        ],
        "người xem": [
            .vi: "người xem",
            .en: "viewers"
        ],
        "Chủ phòng đang tạm dừng màn hình game": [
            .vi: "Chủ phòng đang tạm dừng màn hình game",
            .en: "Host paused game screen share"
        ],
        "Đang kết nối luồng video Live...": [
            .vi: "Đang kết nối luồng video Live...",
            .en: "Connecting to Live stream..."
        ],
        "Chào mừng bạn đến với phòng Live của": [
            .vi: "Chào mừng bạn đến với phòng Live của",
            .en: "Welcome to Live room by"
        ],
        "Cấp quyền camera để xem trước trực tiếp": [
            .vi: "Cấp quyền camera để xem trước trực tiếp",
            .en: "Allow camera access for live preview"
        ],
        "Xem trước · Chưa phát sóng": [
            .vi: "Xem trước · Chưa phát sóng",
            .en: "Preview · Not live yet"
        ],
        "Bộ lọc:": [
            .vi: "Bộ lọc:",
            .en: "Filter:"
        ],
        "Micro": [
            .vi: "Micro",
            .en: "Mic"
        ],
        "Lật cam": [
            .vi: "Lật cam",
            .en: "Flip"
        ],
        "Làm đẹp": [
            .vi: "Làm đẹp",
            .en: "Beauty"
        ],
        "Cần quyền camera và micro để bắt đầu Live.": [
            .vi: "Cần quyền camera và micro để bắt đầu Live.",
            .en: "Camera and microphone permissions are required to go live."
        ],
        "Phòng Live của": [
            .vi: "Phòng Live của",
            .en: "Live room by"
        ],
        "Chưa kết nối được máy chủ Live. Vui lòng thử lại.": [
            .vi: "Chưa kết nối được máy chủ Live. Vui lòng thử lại.",
            .en: "Could not connect to Live server. Please try again."
        ],
        "Camera đang tắt": [
            .vi: "Camera đang tắt",
            .en: "Camera off"
        ],
        "Báo cáo phòng Live": [
            .vi: "Báo cáo phòng Live",
            .en: "Report Live room"
        ],
        "Bình luận Live của": [
            .vi: "Bình luận Live của",
            .en: "Live comment by"
        ],
        "Kết thúc Live?": [
            .vi: "Kết thúc Live?",
            .en: "End Live?"
        ],
        "Tiếp tục phát": [
            .vi: "Tiếp tục phát",
            .en: "Keep streaming"
        ],
        "Kết thúc Live": [
            .vi: "Kết thúc Live",
            .en: "End Live"
        ],
        "Buổi phát trực tiếp sẽ dừng ngay với tất cả người xem.": [
            .vi: "Buổi phát trực tiếp sẽ dừng ngay với tất cả người xem.",
            .en: "The live stream will stop immediately for all viewers."
        ],
        "kết quả cho": [
            .vi: "kết quả cho",
            .en: "results for"
        ],
        "Chọn tệp âm thanh từ thiết bị": [
            .vi: "Chọn tệp âm thanh từ thiết bị",
            .en: "Choose audio file from device"
        ],
        "Không dùng nhạc nền": [
            .vi: "Không dùng nhạc nền",
            .en: "No background music"
        ],
        "Thư viện âm thanh Kinnect": [
            .vi: "Thư viện âm thanh Kinnect",
            .en: "Kinnect audio library"
        ],
        "Đang tải danh sách nhạc…": [
            .vi: "Đang tải danh sách nhạc…",
            .en: "Loading music catalog…"
        ],
        "Chưa có âm thanh trong thư viện.": [
            .vi: "Chưa có âm thanh trong thư viện.",
            .en: "No audio tracks in library yet."
        ],
        "Nghe thử": [
            .vi: "Nghe thử",
            .en: "Preview"
        ],
        "Tìm nhạc, nghệ sĩ": [
            .vi: "Tìm nhạc, nghệ sĩ",
            .en: "Search tracks, artists"
        ],
        "Thêm nhạc nền": [
            .vi: "Thêm nhạc nền",
            .en: "Add music"
        ],
        "Không tải được thư viện nhạc:": [
            .vi: "Không tải được thư viện nhạc:",
            .en: "Could not load music library:"
        ],
        "Đã ghi nhận yêu cầu xác minh email.": [
            .vi: "Đã ghi nhận yêu cầu xác minh email.",
            .en: "Email verification request recorded."
        ],
        "Phong cách": [
            .vi: "Phong cách",
            .en: "Styles"
        ],
        "Studio": [
            .vi: "Studio",
            .en: "Studio"
        ],
        "Quà": [
            .vi: "Quà",
            .en: "Gifts"
        ],
        "Của tôi": [
            .vi: "Của tôi",
            .en: "Owned"
        ],
        "Camera trước": [
            .vi: "Camera trước",
            .en: "Front camera"
        ],
        "Camera sau": [
            .vi: "Camera sau",
            .en: "Back camera"
        ],
        "Tiếp tục Game": [
            .vi: "Tiếp tục Game",
            .en: "Resume Game"
        ],
        "Tạm ẩn Game": [
            .vi: "Tạm ẩn Game",
            .en: "Hide Game"
        ],
        "Rời phòng Live": [
            .vi: "Rời phòng Live",
            .en: "Leave Live"
        ],
        "Thích": [
            .vi: "Thích",
            .en: "Like"
        ],
        "Yêu thích": [
            .vi: "Yêu thích",
            .en: "Love"
        ],
        "Haha": [
            .vi: "Haha",
            .en: "Haha"
        ],
        "Wow": [
            .vi: "Wow",
            .en: "Wow"
        ],
        "Buồn": [
            .vi: "Buồn",
            .en: "Sad"
        ],
        "Phẫn nộ": [
            .vi: "Phẫn nộ",
            .en: "Angry"
        ],
        "Quấy rối hoặc bắt nạt": [
            .vi: "Quấy rối hoặc bắt nạt",
            .en: "Harassment or bullying"
        ],
        "Thù ghét hoặc phân biệt đối xử": [
            .vi: "Thù ghét hoặc phân biệt đối xử",
            .en: "Hate speech or discrimination"
        ],
        "Giả mạo tài khoản": [
            .vi: "Giả mạo tài khoản",
            .en: "Account impersonation"
        ],
        "Lừa đảo hoặc spam": [
            .vi: "Lừa đảo hoặc spam",
            .en: "Scam or spam"
        ],
        "Nội dung tình dục không phù hợp": [
            .vi: "Nội dung tình dục không phù hợp",
            .en: "Inappropriate sexual content"
        ],
        "Bạo lực hoặc nguy hiểm": [
            .vi: "Bạo lực hoặc nguy hiểm",
            .en: "Violence or dangerous content"
        ],
        "Vấn đề khác": [
            .vi: "Vấn đề khác",
            .en: "Other issue"
        ],
        "Ẩn video": [
            .vi: "Ẩn video",
            .en: "Hide video"
        ],
        "Ẩn bài": [
            .vi: "Ẩn bài",
            .en: "Hide post"
        ],
        "Khóa bí mật (Secret)": [
            .vi: "Khóa bí mật (Secret)",
            .en: "Secret key"
        ],
        "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây trong 10 phút)": [
            .vi: "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây trong 10 phút)",
            .en: "Social login accounts do not have a password yet (requires a recent login within 10 minutes)"
        ],
        "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Bạn có thể đặt mật khẩu mới khi phiên đăng nhập còn mới (trong 10 phút)": [
            .vi: "Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Bạn có thể đặt mật khẩu mới khi phiên đăng nhập còn mới (trong 10 phút)",
            .en: "Social login accounts do not have a password yet. You can set a new password while your login session is recent (within 10 minutes)"
        ],
        "Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập trong 10 phút gần đây)": [
            .vi: "Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập trong 10 phút gần đây)",
            .en: "Social accounts do not have a password yet (requires a login within the last 10 minutes)"
        ],
        "Nói gì đó về bài viết này (tùy chọn)": [
            .vi: "Nói gì đó về bài viết này (tùy chọn)",
            .en: "Say something about this post (optional)"
        ],

        // M3A: Splash & ActionSheet
        "Đang kết nối...": [
            .vi: "Đang kết nối...",
            .en: "Connecting..."
        ],
        "Tùy chọn": [
            .vi: "Tùy chọn",
            .en: "Options"
        ],

        // M3B: Auth, Feed, Discover, Shorts, Friends
        "Gửi tin nhắn...": [
            .vi: "Gửi tin nhắn...",
            .en: "Send a message..."
        ],
        "Gửi tin nhắn…": [
            .vi: "Gửi tin nhắn…",
            .en: "Send a message…"
        ],
        "Nhập nội dung tin 24h...": [
            .vi: "Nhập nội dung tin 24h...",
            .en: "Write your 24h story..."
        ],
        "Quanh đây": [
            .vi: "Quanh đây",
            .en: "Nearby"
        ],
        "Viết bình luận...": [
            .vi: "Viết bình luận...",
            .en: "Write a comment..."
        ],
        "Lời mời": [
            .vi: "Lời mời",
            .en: "Requests"
        ],
        "Tên hoặc @username": [
            .vi: "Tên hoặc @username",
            .en: "Name or @username"
        ],
        "Đồng ý": [
            .vi: "Đồng ý",
            .en: "Accept"
        ],
        "Gọi thoại": [
            .vi: "Gọi thoại",
            .en: "Voice Call"
        ],
        "Gọi video": [
            .vi: "Gọi video",
            .en: "Video Call"
        ],

        // M3C: Messages & CallOverlay
        "Loại tin nhắn": [
            .vi: "Loại tin nhắn",
            .en: "Message Type"
        ],
        "Tin nhắn riêng": [
            .vi: "Tin nhắn riêng",
            .en: "Direct"
        ],
        "Nhóm chat": [
            .vi: "Nhóm chat",
            .en: "Groups"
        ],
        "Tìm cuộc trò chuyện…": [
            .vi: "Tìm cuộc trò chuyện…",
            .en: "Search conversations…"
        ],
        "Nội dung tin nhắn mới...": [
            .vi: "Nội dung tin nhắn mới...",
            .en: "New message text..."
        ],
        "Sao chép": [
            .vi: "Sao chép",
            .en: "Copy"
        ],
        "Bỏ ghim tin nhắn": [
            .vi: "Bỏ ghim tin nhắn",
            .en: "Unpin message"
        ],
        "Báo cáo tin nhắn": [
            .vi: "Báo cáo tin nhắn",
            .en: "Report message"
        ],
        "Chỉ âm thanh": [
            .vi: "Chỉ âm thanh",
            .en: "Audio Only"
        ],

        // M3C: LiveStreamView & LiveEffectsSheet
        "Giảm hiệu ứng": [
            .vi: "Giảm hiệu ứng",
            .en: "Reduce FX"
        ],
        "Chế độ": [
            .vi: "Chế độ",
            .en: "Mode"
        ],
        "Màu": [
            .vi: "Màu",
            .en: "Filters"
        ],
        "Đặt lại": [
            .vi: "Đặt lại",
            .en: "Reset"
        ],
        "Xong": [
            .vi: "Xong",
            .en: "Done"
        ],
        "Giao lưu kết bạn": [
            .vi: "Giao lưu kết bạn",
            .en: "Chill & Meet Friends"
        ],
        "Giao lưu trực tiếp, nhận quà tặng từ bạn bè": [
            .vi: "Giao lưu trực tiếp, nhận quà tặng từ bạn bè",
            .en: "Go live to hang out and receive gifts from friends"
        ],

        // M3C: CameraStudioView (SCR-27..31)
        "Đích đăng": [
            .vi: "Đích đăng",
            .en: "Publish Target"
        ],
        "Đích đăng tải:": [
            .vi: "Đích đăng tải:",
            .en: "Publish to:"
        ],
        "ẢNH": [
            .vi: "ẢNH",
            .en: "PHOTO"
        ],
        "VIDEO": [
            .vi: "VIDEO",
            .en: "VIDEO"
        ],
        "LIVE": [
            .vi: "LIVE",
            .en: "LIVE"
        ],
        "Chọn nhạc nền": [
            .vi: "Chọn nhạc nền",
            .en: "Choose Music"
        ],
        "Thư viện": [
            .vi: "Thư viện",
            .en: "Library"
        ],
        "Nhạc của bạn": [
            .vi: "Nhạc của bạn",
            .en: "Your Audio"
        ],
        "Đặt lại màu": [
            .vi: "Đặt lại màu",
            .en: "Reset Color"
        ],
        "Bộ lọc": [
            .vi: "Bộ lọc",
            .en: "Filters"
        ],
        "Sticker": [
            .vi: "Sticker",
            .en: "Stickers"
        ],
        "Tiêu đề video ngắn...": [
            .vi: "Tiêu đề video ngắn...",
            .en: "Short video title..."
        ],
        "Mô tả / Nội dung bài viết...": [
            .vi: "Mô tả / Nội dung bài viết...",
            .en: "Caption / Post content..."
        ],
        "Dùng ảnh & Đăng ngay": [
            .vi: "Dùng ảnh & Đăng ngay",
            .en: "Use Photo & Publish"
        ],
        "Dùng video & Đăng ngay": [
            .vi: "Dùng video & Đăng ngay",
            .en: "Use Video & Publish"
        ],

        // M3C: Profile, AccountMenu, Store, Wallet
        "Đăng xuất tất cả thiết bị khác": [
            .vi: "Đăng xuất tất cả thiết bị khác",
            .en: "Log out all other devices"
        ],
        "Xóa vĩnh viễn tài khoản và dữ liệu": [
            .vi: "Xóa vĩnh viễn tài khoản và dữ liệu",
            .en: "Permanently delete account & data"
        ],
        "Tài chính": [
            .vi: "Tài chính",
            .en: "Finance"
        ],
        "Quyền riêng tư & Bảo mật": [
            .vi: "Quyền riêng tư & Bảo mật",
            .en: "Privacy & Security"
        ],
        "Ứng dụng": [
            .vi: "Ứng dụng",
            .en: "App"
        ],
        "Gỡ": [
            .vi: "Gỡ",
            .en: "Remove"
        ],
        "Nạp xu": [
            .vi: "Nạp xu",
            .en: "Top Up"
        ],
        "Ví & Cửa hàng": [
            .vi: "Ví & Cửa hàng",
            .en: "Wallet & Store"
        ],
        "Rút tiền": [
            .vi: "Rút tiền",
            .en: "Withdraw"
        ],
        "Lịch sử giao dịch": [
            .vi: "Lịch sử giao dịch",
            .en: "Transaction History"
        ],

        // M3-Sync: CallOverlay, Profile, Wallet, Feed, Discover, Friends, Shorts, Live, CameraStudio
        "Tôi sẽ gọi lại sau.": [
            .vi: "Tôi sẽ gọi lại sau.",
            .en: "I'll call you back soon."
        ],
        "Đang bận, nhắn tin nhé!": [
            .vi: "Đang bận, nhắn tin nhé!",
            .en: "Busy right now, text me!"
        ],
        "Tôi đang trong cuộc họp.": [
            .vi: "Tôi đang trong cuộc họp.",
            .en: "I'm in a meeting."
        ],
        "Vui lòng nhập đầy đủ thông tin xác nhận.": [
            .vi: "Vui lòng nhập đầy đủ thông tin xác nhận.",
            .en: "Please fill in all confirmation fields."
        ],
        "Tùy chọn ví": [
            .vi: "Tùy chọn ví",
            .en: "Wallet options"
        ],
        "Làm mới": [
            .vi: "Làm mới",
            .en: "Refresh"
        ],
        "Không thể tải bảng tin": [
            .vi: "Không thể tải bảng tin",
            .en: "Unable to load feed"
        ],
        "Nhấn đúp để xem tin": [
            .vi: "Nhấn đúp để xem tin",
            .en: "Double tap to view story"
        ],
        "Xoá video ngắn?": [
            .vi: "Xoá video ngắn?",
            .en: "Delete short video?"
        ],
        "Xoá video": [
            .vi: "Xoá video",
            .en: "Delete video"
        ],
        "Video ngắn đã xoá sẽ không thể khôi phục.": [
            .vi: "Video ngắn đã xoá sẽ không thể khôi phục.",
            .en: "Deleted short videos cannot be recovered."
        ],
        "Không tìm thấy lời mời phù hợp": [
            .vi: "Không tìm thấy lời mời phù hợp",
            .en: "No matching requests found"
        ],
        "Chặn người dùng?": [
            .vi: "Chặn người dùng?",
            .en: "Block user?"
        ],
        "Tùy chọn phòng Live": [
            .vi: "Tùy chọn phòng Live",
            .en: "Live room options"
        ],
        "Rời sóng": [
            .vi: "Rời sóng",
            .en: "Leave live"
        ],
        "Rời vị trí khách mời": [
            .vi: "Rời vị trí khách mời",
            .en: "Leave guest spot"
        ],
        "Xin lên sóng cùng": [
            .vi: "Xin lên sóng cùng",
            .en: "Request to join live"
        ],
        "Bật âm thanh Live": [
            .vi: "Bật âm thanh Live",
            .en: "Unmute Live audio"
        ],
        "Tắt tiếng Live": [
            .vi: "Tắt tiếng Live",
            .en: "Mute Live audio"
        ],
        "Thu phóng 2x": [
            .vi: "Thu phóng 2x",
            .en: "Zoom 2x"
        ],
        "Thu phóng 1x": [
            .vi: "Thu phóng 1x",
            .en: "Zoom 1x"
        ],
        "Nhập chữ hiển thị...": [
            .vi: "Nhập chữ hiển thị...",
            .en: "Enter display text..."
        ],
        "Hủy xuất": [
            .vi: "Hủy xuất",
            .en: "Cancel export"
        ],
        "Tin 24h của %@": [
            .vi: "Tin 24h của %@",
            .en: "%@'s story"
        ],
        "Không tìm thấy kết quả cho \"%@\".": [
            .vi: "Không tìm thấy kết quả cho \"%@\".",
            .en: "No results found for \"%@\"."
        ],
        "Bạn có chắc muốn hủy kết bạn với %@?": [
            .vi: "Bạn có chắc muốn hủy kết bạn với %@?",
            .en: "Are you sure you want to unfriend %@?"
        ],
        "%@ sẽ không thể nhắn tin hoặc xem nội dung của bạn.": [
            .vi: "%@ sẽ không thể nhắn tin hoặc xem nội dung của bạn.",
            .en: "%@ will no longer be able to message you or view your content."
        ],
        "Gửi nhanh combo %@": [
            .vi: "Gửi nhanh combo %@",
            .en: "Quick send %@ combo"
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
