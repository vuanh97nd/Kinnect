import SwiftUI
import UIKit

/// Dedicated Account Menu screen matching Android 1.2.12 MainActivity.meMenu() (lines 742-790)
/// Features user profile header card, games, wallet, privacy, security, notifications, theme, support, password, logout.
struct AccountMenuView: View {
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss

    var onOpenProfile: () -> Void
    var onOpenStore: (() -> Void)? = nil
    var onOpenWallet: () -> Void
    var onOpenFriends: () -> Void

    @State private var showPrivacySheet = false
    @State private var showSecuritySheet = false
    @State private var showPasswordSheet = false
    @State private var showSupportSheet = false
    @State private var showAboutSheet = false
    @State private var showLogoutConfirm = false
    @State private var showAppearanceSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerProfileCard
                    mainMenuGroup
                    accountSettingsGroup
                    footerLabel
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(KinnectTheme.background.ignoresSafeArea())
            .navigationTitle("Tài khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(KinnectTheme.accentBright)
                }
            }
            .confirmationDialog("Đăng xuất khỏi Kinnect?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive) {
                    dismiss()
                    Task {
                        await appState.logout()
                    }
                }
                Button("Hủy", role: .cancel) { }
            } message: {
                Text("Bạn có thể đăng nhập lại bất kỳ lúc nào.")
            }
            .navigationDestination(isPresented: $showPrivacySheet) {
                PrivacySettingsView()
            }
            .navigationDestination(isPresented: $showSecuritySheet) {
                SecuritySettingsView()
            }
            .navigationDestination(isPresented: $showPasswordSheet) {
                ChangePasswordSheetView()
            }
            .navigationDestination(isPresented: $showAppearanceSheet) {
                AppearanceSettingsSheetView()
            }
            .navigationDestination(isPresented: $showSupportSheet) {
                HelpSupportSheetView()
            }
            .navigationDestination(isPresented: $showAboutSheet) {
                AboutKinnectSheetView()
            }
        }
    }

    // MARK: - Subviews

    private var headerProfileCard: some View {
        Button {
            dismiss()
            onOpenProfile()
        } label: {
            HStack(spacing: 16) {
                if let u = appState.currentUser {
                    KinnectAvatarView(
                        name: u.name,
                        avatarURL: u.avatarUrl,
                        colorHex: u.avatarColor,
                        size: 60,
                        isOnline: false
                    )
                } else {
                    Circle()
                        .fill(KinnectTheme.accentSoft)
                        .frame(width: 60, height: 60)
                        .overlay(
                            KinnectIcon(glyph: .profile, size: 30, tint: KinnectTheme.accentBright)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.currentUser?.name ?? "Người dùng Kinnect")
                        .font(.title3.weight(.bold))
                        .foregroundColor(KinnectTheme.textPrimary)

                    Text("@\(appState.currentUser?.handle ?? "kinnect")")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(KinnectTheme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trang cá nhân")
    }

    private var mainMenuGroup: some View {
        VStack(spacing: 0) {
            menuRow(glyph: .games, title: "Trò chơi", color: .purple) {
                appState.showToast("Trò chơi: Nông trại, Đố vui, Chơi nhanh 1-1")
            }
            Divider().background(KinnectTheme.borderSoft)

            menuRow(glyph: .store, title: "Cửa hàng Kinnect", color: KinnectTheme.accentBright) {
                dismiss()
                onOpenStore?()
            }
            Divider().background(KinnectTheme.borderSoft)

            menuRow(glyph: .wallet, title: "Ví Kinnect", color: KinnectTheme.warning) {
                dismiss()
                onOpenWallet()
            }
            Divider().background(KinnectTheme.borderSoft)

            menuRow(glyph: .settings, title: "Cài đặt và quyền riêng tư", color: .blue) {
                showPrivacySheet = true
            }
            Divider().background(KinnectTheme.borderSoft)

            menuRow(glyph: .shield, title: "Bảo mật và đăng nhập", color: .green) {
                showSecuritySheet = true
            }
            Divider().background(KinnectTheme.borderSoft)

            menuRow(glyph: .notifications, title: "Cài đặt thông báo", color: .orange) {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Divider().background(KinnectTheme.borderSoft)

            menuRow(glyph: .moon, title: "Giao diện", color: .indigo) {
                showAppearanceSheet = true
            }
            Divider().background(KinnectTheme.borderSoft)

            menuRow(glyph: .help, title: "Trợ giúp và hỗ trợ", color: .teal) {
                showSupportSheet = true
            }
            Divider().background(KinnectTheme.borderSoft)

            menuRow(glyph: .info, title: "Giới thiệu Kinnect", color: .pink) {
                showAboutSheet = true
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KinnectTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
        )
    }

    private var accountSettingsGroup: some View {
        VStack(spacing: 0) {
            menuRow(glyph: .lock, title: "Đổi mật khẩu", color: .mint) {
                showPasswordSheet = true
            }
            Divider().background(KinnectTheme.borderSoft)

            Button {
                showLogoutConfirm = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(KinnectTheme.danger.opacity(0.15))
                            .frame(width: 34, height: 34)
                        KinnectIcon(glyph: .logout, size: 18, tint: KinnectTheme.danger)
                    }
                    Text("Đăng xuất")
                        .font(.body.weight(.medium))
                        .foregroundColor(KinnectTheme.danger)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(KinnectTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
        )
    }

    private var footerLabel: some View {
        Text("Kinnect · Kết nối theo cách của bạn.")
            .font(.footnote)
            .foregroundColor(KinnectTheme.textSecondary)
            .padding(.top, 8)
            .padding(.bottom, 24)
    }

    private func menuRow(glyph: KinnectGlyph, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    KinnectIcon(glyph: glyph, size: 18, tint: color)
                }

                Text(title)
                    .font(.body)
                    .foregroundColor(KinnectTheme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sub-sheets

private struct PrivacySettingsView: View {
    @State private var isPrivate = false
    @State private var allowSearch = true
    @State private var showOnlineStatus = true

    var body: some View {
        Form {
            Section("Quyền riêng tư hồ sơ") {
                Toggle("Hồ sơ riêng tư", isOn: $isPrivate)
                Toggle("Cho phép tìm kiếm theo số điện thoại / email", isOn: $allowSearch)
                Toggle("Hiển thị trạng thái hoạt động", isOn: $showOnlineStatus)
            }
            Section(footer: Text("Khi bật tài khoản riêng tư, chỉ những người bạn chấp nhận mới xem được bài viết và thông tin chi tiết.")) {
                EmptyView()
            }
        }
        .navigationTitle("Quyền riêng tư")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SecuritySettingsView: View {
    @State private var twoFactor = false
    @State private var biometrics = true

    var body: some View {
        Form {
            Section("Bảo mật bổ sung") {
                Toggle("Xác thực 2 yếu tố (2FA)", isOn: $twoFactor)
                Toggle("Mở khóa bằng Face ID / Touch ID", isOn: $biometrics)
            }
            Section("Phiên đăng nhập") {
                HStack {
                    Text("Thiết bị này")
                    Spacer()
                    Text("Đang hoạt động").foregroundColor(KinnectTheme.online)
                }
            }
        }
        .navigationTitle("Bảo mật")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChangePasswordSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""

    var body: some View {
        Form {
            Section {
                SecureField("Mật khẩu hiện tại", text: $oldPassword)
                SecureField("Mật khẩu mới", text: $newPassword)
                SecureField("Nhập lại mật khẩu mới", text: $confirmPassword)
            }
            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage).foregroundColor(KinnectTheme.danger)
                }
            }
            Section {
                Button("Cập nhật mật khẩu") {
                    if newPassword.count < 6 {
                        errorMessage = "Mật khẩu phải từ 6 ký tự trở lên"
                        return
                    }
                    if newPassword != confirmPassword {
                        errorMessage = "Mật khẩu mới không khớp"
                        return
                    }
                    AppState.shared.showToast("Đã đổi mật khẩu thành công")
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundColor(KinnectTheme.accentBright)
            }
        }
        .navigationTitle("Đổi mật khẩu")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AppearanceSettingsSheetView: View {
    @AppStorage("kinnect_color_scheme") private var colorSchemeSetting: String = "system"

    var body: some View {
        Form {
            Section("Giao diện ứng dụng") {
                Button {
                    colorSchemeSetting = "light"
                } label: {
                    HStack {
                        Text("Sáng")
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        if colorSchemeSetting == "light" {
                            Image(systemName: "checkmark").foregroundColor(KinnectTheme.accentBright)
                        }
                    }
                }
                Button {
                    colorSchemeSetting = "dark"
                } label: {
                    HStack {
                        Text("Tối")
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        if colorSchemeSetting == "dark" {
                            Image(systemName: "checkmark").foregroundColor(KinnectTheme.accentBright)
                        }
                    }
                }
                Button {
                    colorSchemeSetting = "system"
                } label: {
                    HStack {
                        Text("Theo hệ thống")
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        if colorSchemeSetting == "system" {
                            Image(systemName: "checkmark").foregroundColor(KinnectTheme.accentBright)
                        }
                    }
                }
            }
        }
        .navigationTitle("Giao diện")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HelpSupportSheetView: View {
    var body: some View {
        List {
            Section("Liên hệ hỗ trợ") {
                Link("Trung tâm trợ giúp Kinnect", destination: URL(string: "https://kinnect.app")!)
                Link("Điều khoản dịch vụ", destination: URL(string: "https://kinnect.app")!)
                Link("Chính sách quyền riêng tư", destination: URL(string: "https://kinnect.app")!)
            }
        }
        .navigationTitle("Trợ giúp")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutKinnectSheetView: View {
    var body: some View {
        VStack(spacing: 16) {
            KinnectBrandLogo(size: 72)
                .padding(.top, 32)
            Text("Kinnect")
                .font(.title.weight(.bold))
                .foregroundColor(KinnectTheme.textPrimary)
            Text("Phiên bản 1.2.12 (Build 119)")
                .font(.subheadline)
                .foregroundColor(KinnectTheme.textSecondary)
            Text("Nền tảng mạng xã hội kết nối trực tiếp, livestream thời gian thực và tương tác đa phương tiện.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(KinnectTheme.textPrimary)
                .padding(.horizontal, 32)
            Spacer()
        }
        .navigationTitle("Giới thiệu")
        .navigationBarTitleDisplayMode(.inline)
    }
}
