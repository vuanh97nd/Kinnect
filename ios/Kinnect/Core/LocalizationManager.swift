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
        if let idx = CommandLine.arguments.firstIndex(of: "--qa-lang"),
           idx + 1 < CommandLine.arguments.count {
            let qaLang = CommandLine.arguments[idx + 1].lowercased()
            if qaLang == "en" {
                self.preference = .en
                self.currentLanguage = .en
                return
            } else if qaLang == "vi" {
                self.preference = .vi
                self.currentLanguage = .vi
                return
            }
        }
        #endif
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

        // Common Navigation, Top Bar, Bottom Bar & Accessibility
        "Quay lại": [
            .vi: "Quay lại",
            .en: "Back"
        ],
        "Hủy": [
            .vi: "Hủy",
            .en: "Cancel"
        ],
        "Lưu": [
            .vi: "Lưu",
            .en: "Save"
        ],
        "Xóa": [
            .vi: "Xóa",
            .en: "Delete"
        ],
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
            .en: "Back to top of Kinnect Feed"
        ],
        "Cửa hàng": [
            .vi: "Cửa hàng",
            .en: "Store"
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
            .en: "Personal profile"
        ],
        "Trang cá nhân": [
            .vi: "Trang cá nhân",
            .en: "Profile"
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
        "Ví Kinnect & Cửa hàng Kinnect": [
            .vi: "Ví Kinnect & Cửa hàng Kinnect",
            .en: "Kinnect Wallet & Store"
        ],
        "Ví Kinnect": [
            .vi: "Ví Kinnect",
            .en: "Kinnect Wallet"
        ],
        "Cửa hàng Kinnect": [
            .vi: "Cửa hàng Kinnect",
            .en: "Kinnect Store"
        ],
        "Tôi": [
            .vi: "Tôi",
            .en: "Me"
        ],

        // Relative Time
        "Vừa xong": [
            .vi: "Vừa xong",
            .en: "Just now"
        ],
        "Gần đây": [
            .vi: "Gần đây",
            .en: "Recently"
        ],

        // API & Network Errors
        "Địa chỉ máy chủ không hợp lệ.": [
            .vi: "Địa chỉ máy chủ không hợp lệ.",
            .en: "Invalid server address."
        ],
        "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.": [
            .vi: "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.",
            .en: "Your session has expired. Please log in again."
        ],
        "Đang dùng máy chủ dự phòng. Vui lòng đăng nhập lại trên máy chủ này.": [
            .vi: "Đang dùng máy chủ dự phòng. Vui lòng đăng nhập lại trên máy chủ này.",
            .en: "Using backup server. Please log in again on this server."
        ],
        "Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.": [
            .vi: "Không thể kết nối máy chủ Kinnect. Kiểm tra mạng Internet của bạn.",
            .en: "Unable to connect to Kinnect server. Please check your internet connection."
        ],
        "Phản hồi máy chủ không hợp lệ.": [
            .vi: "Phản hồi máy chủ không hợp lệ.",
            .en: "Invalid server response."
        ],

        // Feed & Reactions
        "Bạn đang nghĩ gì?": [
            .vi: "Bạn đang nghĩ gì?",
            .en: "What's on your mind?"
        ],
        "Mở Camera & Studio": [
            .vi: "Mở Camera & Studio",
            .en: "Open Camera & Studio"
        ],
        "Tạo tin": [
            .vi: "Tạo tin",
            .en: "Add story"
        ],
        "Tạo\ntin": [
            .vi: "Tạo\ntin",
            .en: "Add\nstory"
        ],
        "Tạo tin 24h mới": [
            .vi: "Tạo tin 24h mới",
            .en: "Create new 24h story"
        ],
        "Nhấn đúp để mở trình tạo tin": [
            .vi: "Nhấn đúp để mở trình tạo tin",
            .en: "Double tap to open story creator"
        ],
        "Nhấn đúp để xem tin": [
            .vi: "Nhấn đúp để xem tin",
            .en: "Double tap to view story"
        ],
        "Chưa có bài viết nào": [
            .vi: "Chưa có bài viết nào",
            .en: "No posts yet"
        ],
        "Chưa có cảm xúc": [
            .vi: "Chưa có cảm xúc",
            .en: "No reactions yet"
        ],
        "Cảm xúc": [
            .vi: "Cảm xúc",
            .en: "React"
        ],
        "Bình luận": [
            .vi: "Bình luận",
            .en: "Comment"
        ],
        "Chia sẻ": [
            .vi: "Chia sẻ",
            .en: "Share"
        ],
        "Chia sẻ bài viết": [
            .vi: "Chia sẻ bài viết",
            .en: "Share post"
        ],
        "Xem bài viết trên Kinnect": [
            .vi: "Xem bài viết trên Kinnect",
            .en: "View post on Kinnect"
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
        "Tùy chọn bài viết": [
            .vi: "Tùy chọn bài viết",
            .en: "Post options"
        ],
        "Chỉnh sửa bài viết": [
            .vi: "Chỉnh sửa bài viết",
            .en: "Edit post"
        ],
        "Thay đổi đối tượng xem": [
            .vi: "Thay đổi đối tượng xem",
            .en: "Change audience"
        ],
        "Ẩn bài viết": [
            .vi: "Ẩn bài viết",
            .en: "Hide post"
        ],
        "Xóa bài viết": [
            .vi: "Xóa bài viết",
            .en: "Delete post"
        ],
        "Báo cáo / Chặn UGC": [
            .vi: "Báo cáo / Chặn UGC",
            .en: "Report / Block"
        ],
        "Đã ẩn bài viết.": [
            .vi: "Đã ẩn bài viết.",
            .en: "Post hidden."
        ],
        "Đã xóa bài viết.": [
            .vi: "Đã xóa bài viết.",
            .en: "Post deleted."
        ],
        "Đã xóa bài viết": [
            .vi: "Đã xóa bài viết",
            .en: "Post deleted"
        ],
        "Đã lưu bài viết!": [
            .vi: "Đã lưu bài viết!",
            .en: "Post saved!"
        ],
        "Ai có thể xem bài viết?": [
            .vi: "Ai có thể xem bài viết?",
            .en: "Who can see this post?"
        ],
        "Mọi thành viên (Công khai)": [
            .vi: "Mọi thành viên (Công khai)",
            .en: "Everyone (Public)"
        ],
        "Mọi thành viên": [
            .vi: "Mọi thành viên",
            .en: "Everyone"
        ],
        "Người theo dõi": [
            .vi: "Người theo dõi",
            .en: "Followers"
        ],
        "Chưa có bình luận nào": [
            .vi: "Chưa có bình luận nào",
            .en: "No comments yet"
        ],
        "Hãy là người đầu tiên để lại bình luận!": [
            .vi: "Hãy là người đầu tiên để lại bình luận!",
            .en: "Be the first to leave a comment!"
        ],
        "Viết bình luận...": [
            .vi: "Viết bình luận...",
            .en: "Write a comment..."
        ],
        "Gửi bình luận": [
            .vi: "Gửi bình luận",
            .en: "Send comment"
        ],

        // Inbox, Direct Chat & Group Chat
        "Soạn tin nhắn mới": [
            .vi: "Soạn tin nhắn mới",
            .en: "New message"
        ],
        "Tạo nhóm mới": [
            .vi: "Tạo nhóm mới",
            .en: "Create group"
        ],
        "Tìm cuộc trò chuyện…": [
            .vi: "Tìm cuộc trò chuyện…",
            .en: "Search conversations…"
        ],
        "Loại tin nhắn": [
            .vi: "Loại tin nhắn",
            .en: "Message type"
        ],
        "Tin nhắn riêng": [
            .vi: "Tin nhắn riêng",
            .en: "Direct"
        ],
        "Nhóm chat": [
            .vi: "Nhóm chat",
            .en: "Groups"
        ],
        "Tất cả": [
            .vi: "Tất cả",
            .en: "All"
        ],
        "Chưa đọc": [
            .vi: "Chưa đọc",
            .en: "Unread"
        ],
        "Không có tin nhắn chưa đọc.": [
            .vi: "Không có tin nhắn chưa đọc.",
            .en: "No unread messages."
        ],
        "Chưa có cuộc trò chuyện riêng nào": [
            .vi: "Chưa có cuộc trò chuyện riêng nào",
            .en: "No direct conversations yet"
        ],
        "Mở danh sách bạn bè": [
            .vi: "Mở danh sách bạn bè",
            .en: "Open friends list"
        ],
        "Bạn chưa tham gia nhóm trò chuyện nào": [
            .vi: "Bạn chưa tham gia nhóm trò chuyện nào",
            .en: "You haven't joined any group chats yet"
        ],
        "Nhấn để trò chuyện": [
            .vi: "Nhấn để trò chuyện",
            .en: "Tap to chat"
        ],
        "Đang trực tuyến": [
            .vi: "Đang trực tuyến",
            .en: "Online"
        ],
        "Ngoại tuyến": [
            .vi: "Ngoại tuyến",
            .en: "Offline"
        ],
        "Gọi thoại": [
            .vi: "Gọi thoại",
            .en: "Voice call"
        ],
        "Gọi video": [
            .vi: "Gọi video",
            .en: "Video call"
        ],
        "Ghim hội thoại": [
            .vi: "Ghim hội thoại",
            .en: "Pin conversation"
        ],
        "Bỏ ghim hội thoại": [
            .vi: "Bỏ ghim hội thoại",
            .en: "Unpin conversation"
        ],
        "Đã ghim hội thoại.": [
            .vi: "Đã ghim hội thoại.",
            .en: "Conversation pinned."
        ],
        "Đã bỏ ghim.": [
            .vi: "Đã bỏ ghim.",
            .en: "Conversation unpinned."
        ],
        "Tắt thông báo": [
            .vi: "Tắt thông báo",
            .en: "Mute notifications"
        ],
        "Bật thông báo": [
            .vi: "Bật thông báo",
            .en: "Unmute notifications"
        ],
        "Đã tắt thông báo.": [
            .vi: "Đã tắt thông báo.",
            .en: "Notifications muted."
        ],
        "Đã bật thông báo.": [
            .vi: "Đã bật thông báo.",
            .en: "Notifications unmuted."
        ],
        "Báo cáo người dùng": [
            .vi: "Báo cáo người dùng",
            .en: "Report user"
        ],
        "Chặn người dùng": [
            .vi: "Chặn người dùng",
            .en: "Block user"
        ],
        "Tùy chọn cuộc trò chuyện": [
            .vi: "Tùy chọn cuộc trò chuyện",
            .en: "Conversation options"
        ],
        "Đang sửa tin nhắn": [
            .vi: "Đang sửa tin nhắn",
            .en: "Editing message"
        ],
        "Thư viện ảnh": [
            .vi: "Thư viện ảnh",
            .en: "Photo library"
        ],
        "Tệp & Tài liệu": [
            .vi: "Tệp & Tài liệu",
            .en: "Files & Documents"
        ],
        "Đính kèm tệp hoặc ảnh": [
            .vi: "Đính kèm tệp hoặc ảnh",
            .en: "Attach file or photo"
        ],
        "Chọn ảnh nhanh": [
            .vi: "Chọn ảnh nhanh",
            .en: "Quick photo"
        ],
        "Nội dung tin nhắn mới...": [
            .vi: "Nội dung tin nhắn mới...",
            .en: "Edited message..."
        ],
        "Tin nhắn…": [
            .vi: "Tin nhắn…",
            .en: "Message…"
        ],
        "Tin nhắn nhóm…": [
            .vi: "Tin nhắn nhóm…",
            .en: "Group message…"
        ],
        "Ghi âm tin nhắn thoại (Đang hoàn thiện)": [
            .vi: "Ghi âm tin nhắn thoại (Đang hoàn thiện)",
            .en: "Voice messages (Coming soon)"
        ],
        "Tùy chọn hội thoại": [
            .vi: "Tùy chọn hội thoại",
            .en: "Conversation options"
        ],
        "Tùy chọn tin nhắn": [
            .vi: "Tùy chọn tin nhắn",
            .en: "Message options"
        ],
        "Sửa tin nhắn": [
            .vi: "Sửa tin nhắn",
            .en: "Edit message"
        ],
        "Chuyển tiếp tin nhắn": [
            .vi: "Chuyển tiếp tin nhắn",
            .en: "Forward message"
        ],
        "Thu hồi / Xóa tin nhắn": [
            .vi: "Thu hồi / Xóa tin nhắn",
            .en: "Unsend / Delete message"
        ],
        "Nhắc tên thành viên": [
            .vi: "Nhắc tên thành viên",
            .en: "Mention member"
        ],
        "Nhắc thành viên (@)": [
            .vi: "Nhắc thành viên (@)",
            .en: "Mention member (@)"
        ],
        "Đổi tên nhóm": [
            .vi: "Đổi tên nhóm",
            .en: "Rename group"
        ],
        "Thêm thành viên": [
            .vi: "Thêm thành viên",
            .en: "Add members"
        ],
        "Thành viên & phân quyền": [
            .vi: "Thành viên & phân quyền",
            .en: "Members & roles"
        ],
        "Rời nhóm": [
            .vi: "Rời nhóm",
            .en: "Leave group"
        ],
        "Tùy chọn nhóm": [
            .vi: "Tùy chọn nhóm",
            .en: "Group options"
        ],

        // Profile & Account Menu
        "Mục hồ sơ": [
            .vi: "Mục hồ sơ",
            .en: "Profile section"
        ],
        "Giới thiệu": [
            .vi: "Giới thiệu",
            .en: "About"
        ],
        "Bài viết": [
            .vi: "Bài viết",
            .en: "Posts"
        ],
        "Album ảnh": [
            .vi: "Album ảnh",
            .en: "Photos"
        ],
        "Chỉnh sửa hồ sơ": [
            .vi: "Chỉnh sửa hồ sơ",
            .en: "Edit profile"
        ],
        "Đổi ảnh bìa": [
            .vi: "Đổi ảnh bìa",
            .en: "Change cover photo"
        ],
        "Đổi ảnh đại diện": [
            .vi: "Đổi ảnh đại diện",
            .en: "Change profile photo"
        ],
        "Công khai": [
            .vi: "Công khai",
            .en: "Public"
        ],
        "Riêng tư": [
            .vi: "Riêng tư",
            .en: "Private"
        ],
        "Tiểu sử": [
            .vi: "Tiểu sử",
            .en: "Bio"
        ],
        "Tuổi": [
            .vi: "Tuổi",
            .en: "Age"
        ],
        "Nơi sống": [
            .vi: "Nơi sống",
            .en: "Location"
        ],
        "Chiều cao": [
            .vi: "Chiều cao",
            .en: "Height"
        ],
        "Cân nặng": [
            .vi: "Cân nặng",
            .en: "Weight"
        ],
        "Nghề nghiệp": [
            .vi: "Nghề nghiệp",
            .en: "Occupation"
        ],
        "Trường học": [
            .vi: "Trường học",
            .en: "School"
        ],
        "Bản dạng giới": [
            .vi: "Bản dạng giới",
            .en: "Gender identity"
        ],
        "Xu hướng": [
            .vi: "Xu hướng",
            .en: "Orientation"
        ],
        "Vai trò cộng đồng": [
            .vi: "Vai trò cộng đồng",
            .en: "Community role"
        ],
        "Cách xưng hô": [
            .vi: "Cách xưng hô",
            .en: "Pronouns"
        ],
        "Tình trạng quan hệ": [
            .vi: "Tình trạng quan hệ",
            .en: "Relationship"
        ],
        "Mong muốn": [
            .vi: "Mong muốn",
            .en: "Looking for"
        ],
        "Sở thích": [
            .vi: "Sở thích",
            .en: "Interests"
        ],
        "Chưa có thông tin công khai": [
            .vi: "Chưa có thông tin công khai",
            .en: "No public information yet"
        ],
        "Cập nhật hồ sơ để mọi người hiểu bạn hơn.": [
            .vi: "Cập nhật hồ sơ để mọi người hiểu bạn hơn.",
            .en: "Update your profile so people can get to know you."
        ],
        "Thành viên này chưa chia sẻ thông tin giới thiệu.": [
            .vi: "Thành viên này chưa chia sẻ thông tin giới thiệu.",
            .en: "This member hasn't shared any bio details yet."
        ],
        "Những bài viết bạn chia sẻ trên Bảng tin sẽ xuất hiện tại đây.": [
            .vi: "Những bài viết bạn chia sẻ trên Bảng tin sẽ xuất hiện tại đây.",
            .en: "Posts you share on Feed will appear here."
        ],
        "Ảnh công khai": [
            .vi: "Ảnh công khai",
            .en: "Public photos"
        ],
        "Chạm để xem & tải ảnh mới": [
            .vi: "Chạm để xem & tải ảnh mới",
            .en: "Tap to view & upload photos"
        ],
        "Album riêng tư": [
            .vi: "Album riêng tư",
            .en: "Private album"
        ],
        "Quản lý ảnh & duyệt quyền xem": [
            .vi: "Quản lý ảnh & duyệt quyền xem",
            .en: "Manage photos & access requests"
        ],
        "Chưa có video ngắn nào": [
            .vi: "Chưa có video ngắn nào",
            .en: "No short videos yet"
        ],
        "Các video ngắn bạn đăng trên luồng Shorts sẽ hiển thị tại đây.": [
            .vi: "Các video ngắn bạn đăng trên luồng Shorts sẽ hiển thị tại đây.",
            .en: "Short videos you post will appear here."
        ],
        "Người dùng Kinnect": [
            .vi: "Người dùng Kinnect",
            .en: "Kinnect User"
        ],
        "Bảng quản trị": [
            .vi: "Bảng quản trị",
            .en: "Admin Console"
        ],
        "Cài đặt và quyền riêng tư": [
            .vi: "Cài đặt và quyền riêng tư",
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
        "Trợ giúp và hỗ trợ": [
            .vi: "Trợ giúp và hỗ trợ",
            .en: "Help & Support"
        ],
        "Giới thiệu Kinnect": [
            .vi: "Giới thiệu Kinnect",
            .en: "About Kinnect"
        ],
        "Đổi mật khẩu": [
            .vi: "Đổi mật khẩu",
            .en: "Change Password"
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
            .en: "You can log back in anytime."
        ],
        "Kinnect · Kết nối theo cách của bạn.": [
            .vi: "Kinnect · Kết nối theo cách của bạn.",
            .en: "Kinnect · Connect your way."
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
    static var isEnglish: Bool {
        LocalizationManager.shared.currentLanguage == .en
    }

    static func tr(_ key: String) -> String {
        LocalizationManager.shared.localized(key)
    }

    static func count(_ n: Int, vi: String, enSingular: String, enPlural: String) -> String {
        if isEnglish {
            return "\(n) \(n == 1 ? enSingular : enPlural)"
        }
        return "\(n) \(vi)"
    }

    static func pluralLabel(_ n: Int, vi: String, enSingular: String, enPlural: String) -> String {
        if isEnglish {
            return n == 1 ? enSingular : enPlural
        }
        return vi
    }

    static func joinedKinnect(monthYear: String) -> String {
        if isEnglish {
            return "Joined Kinnect in \(monthYear)"
        }
        return "Tham gia Kinnect từ \(monthYear)"
    }
}
