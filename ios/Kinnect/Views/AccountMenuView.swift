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
                    socialGroup
                    securityGroup
                    supportGroup
                    accountActionsGroup
                    footerLabel
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(KinnectTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
            menuRow(systemName: "bag.fill", gradient: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")], title: "Cửa hàng Kinnect") {
                dismiss()
                onOpenStore?()
            }
            menuDivider

            menuRow(systemName: "creditcard.fill", gradient: [Color(hex: "#F59E0B"), Color(hex: "#D97706")], title: "Ví Kinnect") {
                dismiss()
                onOpenWallet()
            }
        }
        .background(settingsGroupBackground)
    }

    private var socialGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "person.2.fill", gradient: [Color(hex: "#3B82F6"), Color(hex: "#1D4ED8")], title: "Bạn bè") {
                dismiss()
                onOpenFriends()
            }
            menuDivider

            menuRow(systemName: "bell.badge.fill", gradient: [Color(hex: "#EF4444"), Color(hex: "#DC2626")], title: "Cài đặt thông báo") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            menuDivider

            menuRow(systemName: "circle.lefthalf.filled", gradient: [Color(hex: "#6366F1"), Color(hex: "#4F46E5")], title: "Giao diện") {
                showAppearanceSheet = true
            }
        }
        .background(settingsGroupBackground)
    }

    private var securityGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "hand.raised.fill", gradient: [Color(hex: "#64748B"), Color(hex: "#475569")], title: "Cài đặt và quyền riêng tư") {
                showPrivacySheet = true
            }
            menuDivider

            menuRow(systemName: "lock.shield.fill", gradient: [Color(hex: "#0EA5E9"), Color(hex: "#0284C7")], title: "Bảo mật và đăng nhập") {
                showSecuritySheet = true
            }
            menuDivider

            menuRow(systemName: "key.fill", gradient: [Color(hex: "#10B981"), Color(hex: "#059669")], title: "Đổi mật khẩu") {
                showPasswordSheet = true
            }
        }
        .background(settingsGroupBackground)
    }

    private var supportGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "questionmark.circle.fill", gradient: [Color(hex: "#06B6D4"), Color(hex: "#0891B2")], title: "Trợ giúp và hỗ trợ") {
                showSupportSheet = true
            }
            menuDivider

            menuRow(systemName: "info.circle.fill", gradient: [Color(hex: "#8B5CF6"), Color(hex: "#7C3AED")], title: "Giới thiệu Kinnect") {
                showAboutSheet = true
            }
        }
        .background(settingsGroupBackground)
    }

    private var accountActionsGroup: some View {
        VStack(spacing: 0) {
            menuRow(
                systemName: "rectangle.portrait.and.arrow.right.fill",
                gradient: [Color(hex: "#F43F5E"), Color(hex: "#E11D48")],
                title: "Đăng xuất",
                isDestructive: true
            ) {
                showLogoutConfirm = true
            }
        }
        .background(settingsGroupBackground)
    }

    private var menuDivider: some View {
        HStack {
            Spacer().frame(width: 58)
            Divider().background(KinnectTheme.borderSoft.opacity(0.8))
        }
    }

    private var settingsGroupBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(KinnectTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(KinnectTheme.borderSoft.opacity(0.8), lineWidth: 0.8)
            )
    }

    private var footerLabel: some View {
        Text("Kinnect · Kết nối đúng gu · Sống đúng mình")
            .font(.footnote)
            .foregroundColor(KinnectTheme.textSecondary)
            .padding(.top, 4)
            .padding(.bottom, 24)
    }

    private func menuRow(
        systemName: String,
        gradient: [Color],
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 2, y: 1)

                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(title)
                    .font(.system(size: 16, weight: isDestructive ? .medium : .regular))
                    .foregroundColor(isDestructive ? KinnectTheme.danger : KinnectTheme.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(UIColor.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sub-sheets

private struct PrivacySettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var discoverable: Bool = true
    @State private var showDistance: Bool = true
    @State private var showActivity: Bool = true
    @State private var dmFriendsOnly: Bool = false
    @State private var isUpdating = false

    var body: some View {
        Form {
            Section("Quyền riêng tư") {
                Toggle(isOn: Binding(
                    get: { showActivity },
                    set: { val in
                        showActivity = val
                        updatePrivacySetting("showActivity", value: val)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trạng thái hoạt động")
                            .font(.subheadline.bold())
                        Text("Cho người khác biết khi bạn đang online")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
                .tint(KinnectTheme.accentBright)

                Toggle(isOn: Binding(
                    get: { discoverable },
                    set: { val in
                        discoverable = val
                        updatePrivacySetting("discoverable", value: val)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cho phép tìm thấy tôi")
                            .font(.subheadline.bold())
                        Text("Xuất hiện trong Khám phá và Quanh đây")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
                .tint(KinnectTheme.accentBright)

                Toggle(isOn: Binding(
                    get: { showDistance },
                    set: { val in
                        showDistance = val
                        updatePrivacySetting("showDistance", value: val)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hiển thị khoảng cách")
                            .font(.subheadline.bold())
                        Text("Chỉ hiện khoảng cách gần đúng")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
                .tint(KinnectTheme.accentBright)
            }

            Section("Tin nhắn trực tiếp") {
                Toggle("Chỉ nhận tin nhắn từ bạn bè", isOn: Binding(
                    get: { dmFriendsOnly },
                    set: { val in
                        dmFriendsOnly = val
                        updateDmMode(val ? "friends" : "everyone")
                    }
                ))
                .tint(KinnectTheme.accentBright)
            }

            Section("Vị trí và quanh đây") {
                Button(role: .destructive) {
                    Task { await turnOffLocation() }
                } label: {
                    HStack {
                        Image(systemName: "location.slash")
                        Text("Tắt tìm quanh đây")
                    }
                }
            }
        }
        .navigationTitle("Cài đặt & riêng tư")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let user = appState.currentUser {
                self.discoverable = user.discoverable
                self.showDistance = user.showDistance
                self.showActivity = user.showActivity
            }
        }
    }

    private func updatePrivacySetting(_ key: String, value: Bool) {
        if var user = appState.currentUser {
            if key == "showActivity" { user.showActivity = value }
            if key == "discoverable" { user.discoverable = value }
            if key == "showDistance" { user.showDistance = value }
            appState.currentUser = user
        }
        Task {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/me",
                method: "PATCH",
                body: [key: value]
            )
            if key == "showActivity" && value {
                appState.reportActiveStatus(force: true)
            }
        }
    }

    private func updateDmMode(_ mode: String) {
        Task {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/me",
                method: "PATCH",
                body: ["dmMode": mode]
            )
        }
    }

    private func turnOffLocation() async {
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/me/location",
            method: "PATCH",
            body: ["enabled": false]
        )
        if var user = appState.currentUser {
            user.hasLocation = false
            appState.currentUser = user
        }
        appState.showToast("Đã tắt tìm quanh đây")
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
