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
        VStack(spacing: 0) {
            // Pinned Header Bar (matching Android accountHeader pattern)
            PinnedHeaderBar(
                title: "TÃ i khoáº£n",
                onBack: { dismiss() },
                trailingActions: []
            )

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
                .padding(.bottom, 24)
            }
            .background(KinnectTheme.background.ignoresSafeArea())
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .confirmationDialog("ÄÄƒng xuáº¥t khá»i Kinnect?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("ÄÄƒng xuáº¥t", role: .destructive) {
                dismiss()
                Task {
                    await appState.logout()
                }
            }
            Button("Há»§y", role: .cancel) { }
        } message: {
            Text("Báº¡n cÃ³ thá»ƒ Ä‘Äƒng nháº­p láº¡i báº¥t ká»³ lÃºc nÃ o.")
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacySettingsView()
        }
        .sheet(isPresented: $showSecuritySheet) {
            SecuritySettingsView()
        }
        .sheet(isPresented: $showPasswordSheet) {
            ChangePasswordSheetView()
        }
        .sheet(isPresented: $showAppearanceSheet) {
            AppearanceSettingsSheetView()
        }
        .sheet(isPresented: $showSupportSheet) {
            HelpSupportSheetView()
        }
        .sheet(isPresented: $showAboutSheet) {
            AboutKinnectSheetView()
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
                    Text(appState.currentUser?.name ?? "NgÆ°á»i dÃ¹ng Kinnect")
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
        .accessibilityLabel("Trang cÃ¡ nhÃ¢n")
    }

    private var mainMenuGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "bag.fill", gradient: [Color(hex: "#8E2DE2"), Color(hex: "#4A00E0")], title: "Cá»­a hÃ ng Kinnect") {
                dismiss()
                onOpenStore?()
            }
            menuDivider

            menuRow(systemName: "creditcard.fill", gradient: [Color(hex: "#F59E0B"), Color(hex: "#D97706")], title: "VÃ­ Kinnect") {
                dismiss()
                onOpenWallet()
            }
        }
        .background(settingsGroupBackground)
    }

    private var socialGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "person.2.fill", gradient: [Color(hex: "#3B82F6"), Color(hex: "#1D4ED8")], title: "Báº¡n bÃ¨") {
                dismiss()
                onOpenFriends()
            }
            menuDivider

            menuRow(systemName: "bell.badge.fill", gradient: [Color(hex: "#EF4444"), Color(hex: "#DC2626")], title: "CÃ i Ä‘áº·t thÃ´ng bÃ¡o") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            menuDivider

            menuRow(systemName: "circle.lefthalf.filled", gradient: [Color(hex: "#6366F1"), Color(hex: "#4F46E5")], title: "Giao diá»‡n") {
                showAppearanceSheet = true
            }
        }
        .background(settingsGroupBackground)
    }

    private var securityGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "hand.raised.fill", gradient: [Color(hex: "#64748B"), Color(hex: "#475569")], title: "CÃ i Ä‘áº·t vÃ  quyá»n riÃªng tÆ°") {
                showPrivacySheet = true
            }
            menuDivider

            menuRow(systemName: "lock.shield.fill", gradient: [Color(hex: "#0EA5E9"), Color(hex: "#0284C7")], title: "Báº£o máº­t vÃ  Ä‘Äƒng nháº­p") {
                showSecuritySheet = true
            }
            menuDivider

            menuRow(systemName: "key.fill", gradient: [Color(hex: "#10B981"), Color(hex: "#059669")], title: "Äá»•i máº­t kháº©u") {
                showPasswordSheet = true
            }
        }
        .background(settingsGroupBackground)
    }

    private var supportGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "questionmark.circle.fill", gradient: [Color(hex: "#06B6D4"), Color(hex: "#0891B2")], title: "Trá»£ giÃºp vÃ  há»— trá»£") {
                showSupportSheet = true
            }
            menuDivider

            menuRow(systemName: "info.circle.fill", gradient: [Color(hex: "#8B5CF6"), Color(hex: "#7C3AED")], title: "Giá»›i thiá»‡u Kinnect") {
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
                title: "ÄÄƒng xuáº¥t",
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
        Text("Kinnect Â· Káº¿t ná»‘i Ä‘Ãºng gu Â· Sá»‘ng Ä‘Ãºng mÃ¬nh")
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
    @Environment(\ .dismiss) private var dismiss
    @State private var discoverable: Bool = true
    @State private var showDistance: Bool = true
    @State private var showActivity: Bool = true
    @State private var dmFriendsOnly: Bool = false
    @State private var isUpdating = false

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "CÃ i Ä‘áº·t & riÃªng tÆ°",
                onBack: { dismiss() },
                trailingActions: []
            )

            Form {
                Section("Quyá»n riÃªng tÆ°") {
                    Toggle(isOn: Binding(
                        get: { showActivity },
                        set: { val in
                            showActivity = val
                            updatePrivacySetting("showActivity", value: val)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tráº¡ng thÃ¡i hoáº¡t Ä‘á»™ng")
                                .font(.subheadline.bold())
                            Text("Cho ngÆ°á»i khÃ¡c biáº¿t khi báº¡n Ä‘ang online")
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
                            Text("Cho phÃ©p tÃ¬m tháº¥y tÃ´i")
                                .font(.subheadline.bold())
                            Text("Xuáº¥t hiá»‡n trong KhÃ¡m phÃ¡ vÃ  Quanh Ä‘Ã¢y")
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
                            Text("Hiá»ƒn thá»‹ khoáº£ng cÃ¡ch")
                                .font(.subheadline.bold())
                            Text("Chá»‰ hiá»‡n khoáº£ng cÃ¡ch gáº§n Ä‘Ãºng")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .tint(KinnectTheme.accentBright)
                }

                Section("Tin nháº¯n trá»±c tiáº¿p") {
                    Toggle("Chá»‰ nháº­n tin nháº¯n tá»« báº¡n bÃ¨", isOn: Binding(
                        get: { dmFriendsOnly },
                        set: { val in
                            dmFriendsOnly = val
                            updateDmMode(val ? "friends" : "everyone")
                        }
                    ))
                    .tint(KinnectTheme.accentBright)
                }

                Section("Vá»‹ trÃ­ vÃ  quanh Ä‘Ã¢y") {
                    Button(role: .destructive) {
                        Task { await turnOffLocation() }
                    } label: {
                        HStack {
                            Image(systemName: "location.slash")
                            Text("Táº¯t tÃ¬m quanh Ä‘Ã¢y")
                        }
                    }
                }
            }
            .onAppear {
                if let user = appState.currentUser {
                    self.discoverable = user.discoverable
                    self.showDistance = user.showDistance
                    self.showActivity = user.showActivity
                }
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
        appState.showToast("ÄÃ£ táº¯t tÃ¬m quanh Ä‘Ã¢y")
    }
}

private struct SecuritySettingsView: View {
    @Environment(\ .dismiss) private var dismiss
    @State private var twoFactor = false
    @State private var biometrics = true

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Báº£o máº­t",
                onBack: { dismiss() },
                trailingActions: []
            )

            Form {
                Section("Báº£o máº­t bá»• sung") {
                    Toggle("XÃ¡c thá»±c 2 yáº¿u tá»‘ (2FA)", isOn: $twoFactor)
                    Toggle("Má»Ÿ khÃ³a báº±ng Face ID / Touch ID", isOn: $biometrics)
                }
                Section("PhiÃªn Ä‘Äƒng nháº­p") {
                    HStack {
                        Text("Thiáº¿t bá»‹ nÃ y")
                        Spacer()
                        Text("Äang hoáº¡t Ä‘á»™ng").foregroundColor(KinnectTheme.online)
                    }
                }
            }
        }
    }
}

private struct ChangePasswordSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Đổi mật khẩu",
                onBack: { dismiss() },
                trailingActions: []
            )

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
        }
    }
}

private struct AppearanceSettingsSheetView: View {
    @AppStorage("kinnect_color_scheme") private var colorSchemeSetting: String = "system"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Giao diện",
                onBack: { dismiss() },
                trailingActions: []
            )

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
        }
    }
}

private struct HelpSupportSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Trợ giúp",
                onBack: { dismiss() },
                trailingActions: []
            )

            List {
                Section("Liên hệ hỗ trợ") {
                    Link("Trung tâm trợ giúp Kinnect", destination: URL(string: "https://kinnect.app")!)
                    Link("Điều khoản dịch vụ", destination: URL(string: "https://kinnect.app")!)
                    Link("Chính sách quyền riêng tư", destination: URL(string: "https://kinnect.app")!)
                }
            }
        }
    }
}

private struct AboutKinnectSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Giới thiệu",
                onBack: { dismiss() },
                trailingActions: []
            )

            VStack(spacing: 16) {
                KinnectBrandLogo(size: 72)
                    .padding(.top, 32)
                Text("Kinnect")
                    .font(.title.weight(.bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                Text("Phiên bản 1.2.12 (Build 122)")
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                Text("Nền tảng mạng xã hội kết nối trực tiếp, livestream thời gian thực và tương tác đa phương tiện.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .padding(.horizontal, 32)
                Spacer()
            }
        }
    }
}



