import SwiftUI
import UIKit

enum KinnectNotificationPrefs {
    private static func storageKey(_ name: String) -> String { "kinnect_notifications.\(name)" }

    static func isOn(_ name: String) -> Bool {
        let key = storageKey(name)
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ name: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: storageKey(name))
    }

    static func allowsPresentation(kind: String) -> Bool {
        if kind == "call" || kind == "call-ended" || kind == "voip" { return true }
        guard isOn("enabled") else { return false }
        if kind.isEmpty { return true }
        if kind == "message" || kind == "group_message" { return isOn("messages") }
        if kind.hasPrefix("friend_") { return isOn("friends") }
        return isOn("posts")
    }
}

/// Dedicated Account Menu screen matching Android MainActivity.meMenu()
/// Features user profile header card, store, wallet, friends, privacy, security, theme, support, password, logout.
struct AccountMenuView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    var onOpenProfile: () -> Void
    var onOpenStore: (() -> Void)? = nil
    var onOpenWallet: () -> Void
    var onOpenFriends: () -> Void
    var onBack: (() -> Void)? = nil

    enum AccountSubScreen: Hashable {
        case privacy
        case security
        case password
        case appearance
        case support
        case admin
        case about
        case notifications
    }

    @State private var activeSubScreen: AccountSubScreen? = nil
    @State private var showBookmarksSheet = false
    @State private var showLogoutConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if let sub = activeSubScreen {
                switch sub {
                case .privacy:
                    PrivacySettingsView(onBack: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = nil } })
                case .security:
                    SecuritySettingsView(
                        onBack: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = nil } },
                        onChangePassword: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .password } }
                    )
                case .password:
                    ChangePasswordSheetView(onBack: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = nil } })
                case .appearance:
                    AppearanceSettingsSheetView(onBack: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = nil } })
                case .support:
                    HelpSupportSheetView(onBack: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = nil } })
                case .admin:
                    AdminConsoleView(onBack: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = nil } })
                case .about:
                    AboutKinnectSheetView(onBack: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = nil } })
                case .notifications:
                    NotificationSettingsView(onBack: { withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = nil } })
                }
            } else {
                // Pinned Header Bar (matching Android accountHeader pattern)
                PinnedHeaderBar(
                    title: L10n.tr("Tài khoản"),
                    onBack: onBack ?? { dismiss() },
                    trailingActions: []
                )

                ScrollView {
                    VStack(spacing: 16) {
                        headerProfileCard
                        adminMenuGroup
                        mainMenuGroup
                        endMenuGroup
                        footerLabel
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .background(KinnectTheme.background.ignoresSafeArea())
            }
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .confirmationDialog(L10n.tr("Đăng xuất khỏi Kinnect?"), isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button(L10n.tr("Đăng xuất"), role: .destructive) {
                if let onBack = onBack {
                    onBack()
                } else {
                    dismiss()
                }
                Task {
                    await appState.logout()
                }
            }
            Button(L10n.tr("Hủy"), role: .cancel) { }
        } message: {
            Text(L10n.tr("Bạn có thể đăng nhập lại bất kỳ lúc nào."))
        }
        .sheet(isPresented: $showBookmarksSheet) {
            SavedBookmarksSheet()
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
                        size: 64,
                        isOnline: false
                    )
                } else {
                    Circle()
                        .fill(KinnectTheme.accentSoft)
                        .frame(width: 64, height: 64)
                        .overlay(
                            KinnectIcon(glyph: .profile, size: 30, tint: KinnectTheme.accentBright)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.currentUser?.name ?? L10n.tr("Người dùng Kinnect"))
                        .font(.title3.weight(.bold))
                        .foregroundColor(KinnectTheme.textPrimary)

                    Text("@\(appState.currentUser?.handle ?? "kinnect")")
                        .font(.system(size: 14))
                        .foregroundColor(KinnectTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(KinnectTheme.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("Trang cá nhân"))
    }

    @ViewBuilder
    private var adminMenuGroup: some View {
        if appState.currentUser?.accountRole == "admin" {
            VStack(spacing: 0) {
                menuRow(systemName: "checkmark.shield", title: L10n.tr("Bảng quản trị")) {
                    withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .admin }
                }
            }
            .background(settingsGroupBackground)
        }
    }

    private var mainMenuGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "bag", title: L10n.tr("Cửa hàng Kinnect")) { onOpenStore?() }
            menuDivider
            menuRow(systemName: "creditcard", title: L10n.tr("Ví Kinnect")) { onOpenWallet() }
            menuDivider
            menuRow(systemName: "bookmark", title: L10n.tr("Bài viết đã lưu")) {
                showBookmarksSheet = true
            }
            menuDivider
            menuRow(systemName: "hand.raised", title: L10n.tr("Cài đặt và quyền riêng tư")) {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .privacy }
            }
            menuDivider
            menuRow(systemName: "lock.shield", title: L10n.tr("Bảo mật và đăng nhập")) {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .security }
            }
            menuDivider
            menuRow(systemName: "bell", title: L10n.tr("Cài đặt thông báo")) {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .notifications }
            }
            menuDivider
            menuRow(systemName: "circle.lefthalf.filled", title: L10n.tr("Giao diện")) {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .appearance }
            }
            menuDivider
            menuRow(systemName: "questionmark.circle", title: L10n.tr("Trợ giúp và hỗ trợ")) {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .support }
            }
            menuDivider
            menuRow(systemName: "info.circle", title: L10n.tr("Giới thiệu Kinnect")) {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .about }
            }
        }
        .background(settingsGroupBackground)
    }

    private var endMenuGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "key", title: L10n.tr((appState.currentUser?.hasPassword ?? true) ? "Đổi mật khẩu" : "Đặt mật khẩu")) {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .password }
            }
            menuDivider
            menuRow(systemName: "rectangle.portrait.and.arrow.right", title: L10n.tr("Đăng xuất"), isDestructive: true) {
                showLogoutConfirm = true
            }
        }
        .background(settingsGroupBackground)
    }

    private var menuDivider: some View {
        Divider()
            .background(KinnectTheme.borderSoft.opacity(0.8))
            .padding(.leading, 64)
    }

    private var settingsGroupBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(KinnectTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(KinnectTheme.borderSoft.opacity(0.8), lineWidth: 0.8)
            )
    }

    private var footerLabel: some View {
        Text(L10n.tr("Kinnect · Kết nối theo cách của bạn."))
            .font(.caption)
            .foregroundColor(KinnectTheme.textSecondary)
            .padding(.top, 4)
            .padding(.bottom, 24)
    }

    private func menuRow(
        systemName: String,
        title: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let tint = isDestructive ? KinnectTheme.danger : KinnectTheme.accent
        return Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isDestructive ? KinnectTheme.danger.opacity(0.12) : KinnectTheme.accentSoft)
                        .frame(width: 40, height: 40)
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tint)
                }

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isDestructive ? tint : KinnectTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(KinnectTheme.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Sub-screens with Pinned Header Bar (1:1 Android Parity)

private struct PrivacySettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var language = LocalizationManager.shared
    @AppStorage("app_appearance_mode") private var appearanceMode: String = "system"
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil

    @State private var discoverable: Bool = true
    @State private var showDistance: Bool = true
    @State private var showActivity: Bool = true
    @State private var dmFriendsOnly: Bool = false
    @State private var cloudChatSync: Bool = true
    @State private var showEditProfile = false
    @State private var showPrivateAlbum = false
    @State private var showBlockedUsers = false
    @State private var showDeleteAccount = false
    @State private var privatePhotos: [PrivatePhotoItem] = []
    @State private var privateRequests: [PrivateAccessRequestItem] = []

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: L10n.tr("Cài đặt & riêng tư"),
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            Form {
                Section(L10n.tr("Ngôn ngữ")) {
                    Button {
                        language.setLanguage(.vi)
                    } label: {
                        languageRow("Tiếng Việt", selected: language.preference == .vi)
                    }
                    Button {
                        language.setLanguage(.en)
                    } label: {
                        languageRow("English", selected: language.preference == .en)
                    }
                    Button {
                        language.setPreference(.system)
                    } label: {
                        languageRow(L10n.tr("Theo hệ thống"), selected: language.preference == .system)
                    }
                }

                Section(L10n.tr("Giao diện ứng dụng")) {
                    Picker(L10n.tr("Chế độ hiển thị"), selection: $appearanceMode) {
                        Text(L10n.tr("Theo hệ thống")).tag("system")
                        Text(L10n.tr("Tối")).tag("dark")
                        Text(L10n.tr("Sáng")).tag("light")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearanceMode) { newMode in
                        KinnectTheme.applyWindowAppearance(newMode)
                    }
                }

                Section(L10n.tr("Thông tin cá nhân")) {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack {
                            Text(appState.currentUser?.name ?? L10n.tr("Người dùng Kinnect"))
                            Text(L10n.tr("· chỉnh sửa hồ sơ"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    }
                }

                Section(L10n.tr("Quyền riêng tư")) {
                    Toggle(isOn: Binding(
                        get: { showActivity },
                        set: { val in
                            showActivity = val
                            updatePrivacySetting("showActivity", value: val)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("Trạng thái hoạt động"))
                                .font(.subheadline.bold())
                            Text(L10n.tr("Cho người khác biết khi bạn đang online"))
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
                            Text(L10n.tr("Cho phép tìm thấy tôi"))
                                .font(.subheadline.bold())
                            Text(L10n.tr("Xuất hiện trong Khám phá và Quanh đây"))
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
                            Text(L10n.tr("Hiển thị khoảng cách"))
                                .font(.subheadline.bold())
                            Text(L10n.tr("Chỉ hiện khoảng cách gần đúng"))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .tint(KinnectTheme.accentBright)

                    Toggle(isOn: Binding(
                        get: { cloudChatSync },
                        set: { val in
                            cloudChatSync = val
                            updatePrivacySetting("cloudChatSync", value: val)
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("Đồng bộ tin nhắn đám mây"))
                                .font(.subheadline.bold())
                            Text(L10n.tr("Lưu trữ và đồng bộ lịch sử hội thoại an toàn qua máy chủ Kinnect."))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    .tint(KinnectTheme.accentBright)
                }

                Section(L10n.tr("Ai có thể nhắn tin")) {
                    Picker(L10n.tr("Ai có thể nhắn tin"), selection: Binding(
                        get: { dmFriendsOnly ? "friends" : "everyone" },
                        set: { updateDmMode($0) }
                    )) {
                        Text(L10n.tr("Mọi thành viên")).tag("everyone")
                        Text(L10n.tr("Bạn bè")).tag("friends")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(L10n.tr("Quyền truy cập")) {
                    Button(L10n.tr("Ảnh riêng tư")) { showPrivateAlbum = true }
                    Button(L10n.tr("Tài khoản đã chặn")) { showBlockedUsers = true }
                }

                Section(L10n.tr("Quản lý tài khoản")) {
                    Button(L10n.tr("Xóa tài khoản và dữ liệu"), role: .destructive) {
                        showDeleteAccount = true
                    }
                }

                Section(L10n.tr("Vị trí và quanh đây")) {
                    Button(role: .destructive) {
                        Task { await turnOffLocation() }
                    } label: {
                        HStack {
                            Image(systemName: "location.slash")
                            Text(L10n.tr("Tắt tìm quanh đây"))
                        }
                    }
                }
            }
            .onAppear {
                if let user = appState.currentUser {
                    self.discoverable = user.discoverable
                    self.showDistance = user.showDistance
                    self.showActivity = user.showActivity
                    self.dmFriendsOnly = user.dmMode == "friends"
                    self.cloudChatSync = user.cloudChatSync
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileSheet(onSaved: {})
            }
            .sheet(isPresented: $showPrivateAlbum) {
                PrivateAlbumManageSheet(photos: $privatePhotos, requests: $privateRequests, onRefresh: {})
            }
            .sheet(isPresented: $showBlockedUsers) {
                BlockedUsersSheet()
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountConfirmationSheet()
            }
        }
    }

    private func languageRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundColor(KinnectTheme.textPrimary)
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundColor(KinnectTheme.accent)
            }
        }
    }

    private func updatePrivacySetting(_ key: String, value: Bool) {
        if var user = appState.currentUser {
            if key == "showActivity" { user.showActivity = value }
            if key == "discoverable" { user.discoverable = value }
            if key == "showDistance" { user.showDistance = value }
            if key == "cloudChatSync" { user.cloudChatSync = value }
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
        let normalized = mode == "friends" ? "friends" : "everyone"
        dmFriendsOnly = normalized == "friends"
        if var user = appState.currentUser {
            user.dmMode = normalized
            appState.currentUser = user
        }
        Task {
            do {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/me",
                    method: "PATCH",
                    body: ["dmMode": normalized]
                )
            } catch {
                appState.showToast(error.localizedDescription)
            }
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
        appState.showToast(L10n.tr("Đã tắt tìm quanh đây"))
    }
}

private struct SecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    var onBack: (() -> Void)? = nil
    var onChangePassword: () -> Void

    @State private var showRecovery = false
    @State private var showTwoFactor = false
    @State private var showSessions = false

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: L10n.tr("Bảo mật và đăng nhập"),
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            List {
                Button(L10n.tr((appState.currentUser?.hasPassword ?? true) ? "Đổi mật khẩu" : "Đặt mật khẩu"), action: onChangePassword)
                Button(L10n.tr("Xác thực 2 bước (2FA)")) { showTwoFactor = true }
                Button(L10n.tr("Email khôi phục")) { showRecovery = true }
                Button(L10n.tr("Thiết bị đăng nhập")) { showSessions = true }
                Link(L10n.tr("Hỗ trợ tài khoản và khôi phục"), destination: URL(string: "https://kinnect.io.vn/support")!)
            }
            .foregroundColor(KinnectTheme.textPrimary)
        }
        .sheet(isPresented: $showTwoFactor) {
            TwoFactorSettingsSheet()
        }
        .sheet(isPresented: $showRecovery) {
            RecoveryEmailSheet()
        }
        .sheet(isPresented: $showSessions) {
            ActiveSessionsSheet()
        }
    }
}

private struct TwoFactorSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var isLoading = true
    @State private var isBusy = false
    @State private var enabled = false
    @State private var pending = false
    @State private var remainingBackupCodes = 0

    // Setup flow state
    @State private var currentPassword = ""
    @State private var setupSecret = ""
    @State private var setupOtpauthUrl = ""
    @State private var setupBackupCodes: [String] = []
    @State private var verificationCode = ""

    // Enabled actions state
    @State private var actionPassword = ""
    @State private var actionCode = ""

    private var hasPassword: Bool {
        appState.currentUser?.hasPassword ?? true
    }

    private var hasPendingSetup: Bool {
        pending && !enabled
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("Trạng thái bảo mật")) {
                    HStack {
                        Text(L10n.tr("Xác thực 2 bước (TOTP)"))
                            .font(.subheadline.bold())
                        Spacer()
                        Text(enabled ? L10n.tr("Đang bật") : (hasPendingSetup ? L10n.tr("Chờ xác nhận") : L10n.tr("Đang tắt")))
                            .font(.caption.bold())
                            .foregroundColor(enabled ? KinnectTheme.online : (hasPendingSetup ? KinnectTheme.warning : KinnectTheme.textSecondary))
                    }
                    if enabled {
                        HStack {
                            Text(L10n.tr("Mã dự phòng còn lại"))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                            Spacer()
                            Text(String(format: L10n.tr("%d mã"), remainingBackupCodes))
                                .font(.caption.bold())
                                .foregroundColor(remainingBackupCodes > 0 ? KinnectTheme.accentBright : KinnectTheme.danger)
                        }
                    }
                }

                if !setupBackupCodes.isEmpty {
                    Section(L10n.tr("Mã dự phòng khôi phục (Lưu giữ an toàn)")) {
                        Text(L10n.tr("Mỗi mã dự phòng chỉ dùng được 1 lần khi bạn mất thiết bị xác thực."))
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text(setupBackupCodes.joined(separator: "\n"))
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = setupBackupCodes.joined(separator: "\n")
                            appState.showToast(L10n.tr("Đã sao chép danh sách mã dự phòng."))
                        } label: {
                            Label(L10n.tr("Sao chép mã dự phòng"), systemImage: "doc.on.doc")
                        }
                    }
                }

                if !enabled {
                    if !setupSecret.isEmpty || hasPendingSetup {
                        if !setupSecret.isEmpty {
                            Section(L10n.tr("Bước 2: Liên kết ứng dụng Authenticator")) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L10n.tr("Khóa bí mật (Secret):"))
                                        .font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                    Text(setupSecret)
                                        .font(.system(.subheadline, design: .monospaced).bold())
                                        .foregroundColor(KinnectTheme.accentBright)
                                        .textSelection(.enabled)
                                }
                                Button {
                                    UIPasteboard.general.string = setupSecret
                                    appState.showToast(L10n.tr("Đã sao chép khóa bí mật 2FA."))
                                } label: {
                                    Label(L10n.tr("Sao chép khóa Secret"), systemImage: "doc.on.doc")
                                }
                                if !setupOtpauthUrl.isEmpty {
                                    Button {
                                        UIPasteboard.general.string = setupOtpauthUrl
                                        appState.showToast(L10n.tr("Đã sao chép liên kết otpauth://"))
                                    } label: {
                                        Label(L10n.tr("Sao chép URI otpauth://"), systemImage: "link")
                                    }
                                }
                            }
                        } else {
                            Section(L10n.tr("Thiết lập đang chờ xác nhận")) {
                                Text(L10n.tr("Bạn đã khởi tạo khóa 2FA trước đó. Hãy nhập mã 6 chữ số từ ứng dụng Authenticator để kích hoạt, hoặc tạo lại khóa mới bên dưới."))
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }

                        Section(L10n.tr("Bước 3: Xác nhận mã 6 chữ số để bật")) {
                            TextField(L10n.tr("Nhập mã 6 chữ số từ ứng dụng"), text: $verificationCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                            Button(isBusy ? L10n.tr("Đang kích hoạt...") : L10n.tr("Kích hoạt 2FA")) {
                                Task { await enableTwoFactor() }
                            }
                            .font(.body.bold())
                            .foregroundColor(KinnectTheme.online)
                            .disabled(isBusy || verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
                        }
                    }

                    if setupSecret.isEmpty {
                        Section(hasPendingSetup ? L10n.tr("Hoặc tạo lại khóa 2FA mới") : L10n.tr("Bước 1: Khởi tạo khóa 2FA")) {
                            if hasPassword {
                                SecureField(L10n.tr("Mật khẩu hiện tại"), text: $currentPassword)
                            } else {
                                Text(L10n.tr("Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Cần phiên đăng nhập trong 10 phút gần đây."))
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            Button(isBusy ? L10n.tr("Đang tạo khóa...") : L10n.tr("Tạo khóa xác thực 2FA")) {
                                Task { await startSetup() }
                            }
                            .disabled(isBusy || (hasPassword && currentPassword.isEmpty))
                        }
                    }
                } else {
                    Section(L10n.tr("Quản lý & Tắt 2FA")) {
                        if hasPassword {
                            SecureField(L10n.tr("Mật khẩu hiện tại"), text: $actionPassword)
                        } else {
                            Text(L10n.tr("Tài khoản đăng nhập mạng xã hội chưa có mật khẩu (cần phiên đăng nhập gần đây trong 10 phút)."))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        TextField(L10n.tr("Mã 2FA 6 số hoặc mã dự phòng"), text: $actionCode)
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()

                        Button(isBusy ? L10n.tr("Đang tạo lại...") : L10n.tr("Tạo lại 8 mã dự phòng mới")) {
                            Task { await regenerateRecoveryCodes() }
                        }
                        .disabled(isBusy || (hasPassword && actionPassword.isEmpty) || actionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(isBusy ? L10n.tr("Đang tắt...") : L10n.tr("Tắt xác thực 2 bước"), role: .destructive) {
                            Task { await disableTwoFactor() }
                        }
                        .disabled(isBusy || (hasPassword && actionPassword.isEmpty) || actionCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle(L10n.tr("Xác thực 2 bước (2FA)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
            .task {
                await loadStatus()
            }
        }
    }

    private func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if UIReviewFixture.isEnabled { return }
        #endif
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/me/2fa")
            enabled = (res["enabled"] as? Bool) ?? false
            pending = (res["pending"] as? Bool) ?? false
            remainingBackupCodes = (res["remainingBackupCodes"] as? Int) ?? (res["recoveryRemaining"] as? Int) ?? 0
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func startSetup() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/2fa/setup",
                method: "POST",
                body: ["password": currentPassword]
            )
            setupSecret = (res["secret"] as? String) ?? ""
            setupOtpauthUrl = (res["otpauthUrl"] as? String) ?? (res["otpauthUri"] as? String) ?? ""
            setupBackupCodes = (res["backupCodes"] as? [String]) ?? []
            currentPassword = ""
            appState.showToast(L10n.tr("Đã khởi tạo khóa 2FA. Hãy nhập mã 6 số để hoàn tất."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func enableTwoFactor() async {
        isBusy = true
        defer { isBusy = false }
        let cleanCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/2fa/enable",
                method: "POST",
                body: ["code": cleanCode]
            )
            enabled = (res["enabled"] as? Bool) ?? true
            if let codes = res["backupCodes"] as? [String], !codes.isEmpty {
                setupBackupCodes = codes
            }
            remainingBackupCodes = (res["remainingBackupCodes"] as? Int) ?? (res["recoveryRemaining"] as? Int) ?? setupBackupCodes.count
            verificationCode = ""
            setupSecret = ""
            appState.showToast(L10n.tr("Đã bật xác thực 2 bước thành công!"))
            await loadStatus()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func regenerateRecoveryCodes() async {
        isBusy = true
        defer { isBusy = false }
        let cleanCode = actionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/2fa/recovery",
                method: "POST",
                body: ["password": actionPassword, "code": cleanCode]
            )
            setupBackupCodes = (res["backupCodes"] as? [String]) ?? []
            remainingBackupCodes = (res["remainingBackupCodes"] as? Int) ?? (res["recoveryRemaining"] as? Int) ?? setupBackupCodes.count
            actionCode = ""
            appState.showToast(L10n.tr("Đã tạo mới mã dự phòng 2FA."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func disableTwoFactor() async {
        isBusy = true
        defer { isBusy = false }
        let cleanCode = actionCode.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/2fa/disable",
                method: "POST",
                body: ["password": actionPassword, "code": cleanCode]
            )
            enabled = false
            pending = false
            remainingBackupCodes = 0
            setupSecret = ""
            setupOtpauthUrl = ""
            setupBackupCodes = []
            actionPassword = ""
            actionCode = ""
            appState.showToast(L10n.tr("Đã tắt xác thực 2 bước."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

private struct ChangePasswordSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    var onBack: (() -> Void)? = nil

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showOldPassword = false
    @State private var showNewPassword = false
    @State private var showConfirmPassword = false
    @State private var errorMessage = ""
    @State private var isSubmitting = false

    private var hasPassword: Bool {
        appState.currentUser?.hasPassword ?? true
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: hasPassword ? L10n.tr("Đổi mật khẩu") : L10n.tr("Đặt mật khẩu"),
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            Form {
                Section {
                    if hasPassword {
                        HStack {
                            if showOldPassword {
                                TextField(L10n.tr("Mật khẩu hiện tại"), text: $oldPassword)
                            } else {
                                SecureField(L10n.tr("Mật khẩu hiện tại"), text: $oldPassword)
                            }
                            KinnectIconButton(
                                glyph: showOldPassword ? .eyeOff : .eye,
                                label: L10n.tr(showOldPassword ? "Ẩn" : "Hiện"),
                                tint: KinnectTheme.textSecondary
                            ) {
                                showOldPassword.toggle()
                            }
                        }
                    } else {
                        Text(L10n.tr("Tài khoản đăng nhập mạng xã hội chưa có mật khẩu. Bạn có thể đặt mật khẩu mới khi phiên đăng nhập còn mới (trong 10 phút)."))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    HStack {
                        if showNewPassword {
                            TextField(L10n.tr("Mật khẩu mới"), text: $newPassword)
                        } else {
                            SecureField(L10n.tr("Mật khẩu mới"), text: $newPassword)
                        }
                        KinnectIconButton(
                            glyph: showNewPassword ? .eyeOff : .eye,
                            label: L10n.tr(showNewPassword ? "Ẩn" : "Hiện"),
                            tint: KinnectTheme.textSecondary
                        ) {
                            showNewPassword.toggle()
                        }
                    }
                    HStack {
                        if showConfirmPassword {
                            TextField(L10n.tr("Nhập lại mật khẩu mới"), text: $confirmPassword)
                        } else {
                            SecureField(L10n.tr("Nhập lại mật khẩu mới"), text: $confirmPassword)
                        }
                        KinnectIconButton(
                            glyph: showConfirmPassword ? .eyeOff : .eye,
                            label: L10n.tr(showConfirmPassword ? "Ẩn" : "Hiện"),
                            tint: KinnectTheme.textSecondary
                        ) {
                            showConfirmPassword.toggle()
                        }
                    }
                }
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage).foregroundColor(KinnectTheme.danger)
                    }
                }
                Section {
                    Button(L10n.tr(isSubmitting ? "Đang lưu…" : "Lưu")) {
                        Task { await submit() }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(KinnectTheme.accentBright)
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        errorMessage = ""
        if hasPassword && oldPassword.isEmpty {
            errorMessage = L10n.tr("Vui lòng nhập mật khẩu hiện tại.")
            return
        }
        if newPassword.count < 6 {
            errorMessage = L10n.tr("Mật khẩu mới phải có ít nhất 6 ký tự.")
            return
        }
        if newPassword != confirmPassword {
            errorMessage = L10n.tr("Mật khẩu nhập lại không khớp.")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            appState.currentUser?.hasPassword = true
            appState.showToast(L10n.tr("Đã lưu mật khẩu. Các thiết bị khác đã được đăng xuất."))
            close()
            return
        }
        #endif
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/password",
                method: "POST",
                body: ["current": hasPassword ? oldPassword : "", "next": newPassword]
            )
            appState.currentUser?.hasPassword = true
            appState.showToast(L10n.tr("Đã lưu mật khẩu. Các thiết bị khác đã được đăng xuất."))
            close()
        } catch {
            errorMessage = error.localizedDescription
            appState.showToast(error.localizedDescription)
        }
    }

    private func close() {
        if let onBack = onBack {
            onBack()
        } else {
            dismiss()
        }
    }
}

private struct AppearanceSettingsSheetView: View {
    @AppStorage("app_appearance_mode") private var colorSchemeSetting: String = "system"
    @ObservedObject private var loc = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: L10n.tr("Giao diện"),
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            Form {
                Section(L10n.tr("Giao diện ứng dụng")) {
                    Button {
                        colorSchemeSetting = "light"
                        KinnectTheme.applyWindowAppearance("light")
                    } label: {
                        HStack {
                            Text(L10n.tr("Sáng"))
                                .foregroundColor(KinnectTheme.textPrimary)
                            Spacer()
                            if colorSchemeSetting == "light" {
                                Image(systemName: "checkmark").foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }
                    Button {
                        colorSchemeSetting = "dark"
                        KinnectTheme.applyWindowAppearance("dark")
                    } label: {
                        HStack {
                            Text(L10n.tr("Tối"))
                                .foregroundColor(KinnectTheme.textPrimary)
                            Spacer()
                            if colorSchemeSetting == "dark" {
                                Image(systemName: "checkmark").foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }
                    Button {
                        colorSchemeSetting = "system"
                        KinnectTheme.applyWindowAppearance("system")
                    } label: {
                        HStack {
                            Text(L10n.tr("Theo hệ thống"))
                                .foregroundColor(KinnectTheme.textPrimary)
                            Spacer()
                            if colorSchemeSetting == "system" {
                                Image(systemName: "checkmark").foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }
                }
            }
            .onChange(of: colorSchemeSetting) { newMode in
                KinnectTheme.applyWindowAppearance(newMode)
            }
        }
    }
}

private struct HelpSupportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    var onBack: (() -> Void)? = nil
    @State private var showReport = false
    @State private var supportPeer: KinnectUser?
    @State private var showSupportFallback = false

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: L10n.tr("Trợ giúp và hỗ trợ"),
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            List {
                Button(L10n.tr("Báo sự cố")) { showReport = true }
                Button(L10n.tr("Trung tâm hỗ trợ")) { Task { await openSupport() } }
                Link(L10n.tr("Chính sách quyền riêng tư"), destination: URL(string: "https://kinnect.io.vn/privacy")!)
                Link(L10n.tr("Quy tắc cộng đồng"), destination: URL(string: "https://kinnect.io.vn/community")!)
                Link(L10n.tr("An toàn trẻ em"), destination: URL(string: "https://kinnect.io.vn/child-safety")!)
                Link(L10n.tr("Giấy phép phần mềm"), destination: URL(string: "https://app.kinnect.io.vn/third-party-notices.txt")!)
                Text(L10n.tr("Mr Ánh · Hỗ trợ và quyền riêng tư: anhvn53@wru.vn"))
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .foregroundColor(KinnectTheme.textPrimary)
        }
        .sheet(isPresented: $showReport) {
            AppReportSheet()
        }
        .sheet(item: $supportPeer) { peer in
            DirectChatDetailView(peer: peer)
        }
        .alert(L10n.tr("Hỗ trợ Kinnect"), isPresented: $showSupportFallback) {
            Button(L10n.tr("Đóng"), role: .cancel) {}
        } message: {
            Text(L10n.tr("Liên hệ riêng Mr Ánh: anhvn53@wru.vn. Không gửi mật khẩu hoặc OTP."))
        }
    }

    private func openSupport() async {
        do {
            let data = try await KinnectAPIClient.shared.requestJSON("/api/support")
            if let user = data["user"] as? [String: Any],
               let id = user["id"] as? String, !id.isEmpty {
                supportPeer = KinnectUser.from(user)
                return
            }
        } catch {}
        showSupportFallback = true
    }
}

private struct AdminModeration: Identifiable {
    let id = UUID()
    let action: String
    let target: String
}

struct AdminConsoleView: View {
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var reports: [[String: Any]] = []
    @State private var users: [[String: Any]] = []
    @State private var status = ""
    @State private var pending: AdminModeration?
    @State private var confirm = false

    private var allowed: Bool {
        #if DEBUG
        if UIReviewFixture.activeScreen == "admin" { return true }
        #endif
        return appState.currentUser?.accountRole == "admin"
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: L10n.tr("Bảng quản trị"),
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )
            if allowed {
                List {
                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Section(L10n.tr("Báo cáo")) {
                        if reports.isEmpty {
                            Text(L10n.tr("Chưa có báo cáo."))
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        ForEach(Array(reports.enumerated()), id: \.offset) { _, report in
                            reportRow(report)
                        }
                    }
                    Section(L10n.tr("Thành viên gần đây")) {
                        ForEach(Array(users.enumerated()), id: \.offset) { _, user in
                            userRow(user)
                        }
                    }
                    Text(L10n.tr("Kinh tế, trợ lý AI và thư viện nhạc chưa có trên màn này."))
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
            } else {
                Text(L10n.tr("Chỉ quản trị viên được vào bảng quản trị."))
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(KinnectTheme.background)
        .task { await reload() }
        .confirmationDialog(L10n.tr("Xác nhận thao tác quản trị?"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L10n.tr("Xác nhận"), role: .destructive) {
                if let pending {
                    Task { await moderate(pending.action, pending.target) }
                }
            }
            Button(L10n.tr("Hủy"), role: .cancel) { pending = nil }
        }
    }

    @ViewBuilder
    private func reportRow(_ report: [String: Any]) -> some View {
        let subject = report["subject"] as? [String: Any]
        let kind = report["target_type"] as? String ?? ""
        let target = report["target_id"] as? String ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Text("\(kind) · \(report["status"] as? String ?? "")")
                .font(.subheadline.bold())
                .foregroundColor(KinnectTheme.accentBright)
            Text(report["reason"] as? String ?? "")
                .font(.subheadline)
                .foregroundColor(KinnectTheme.textPrimary)
            if let subject {
                Text((subject["body"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (subject["username"] as? String ?? ""))
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                if kind == "short" || kind == "post" {
                    let hidden = Self.flag(subject["hidden"])
                    Button(L10n.tr(hidden ? (kind == "short" ? "Hiện video" : "Hiện bài") : (kind == "short" ? "Ẩn video" : "Ẩn bài"))) {
                        ask(hidden ? "show-\(kind)" : "hide-\(kind)", target)
                    }
                }
                if kind == "message" || kind == "group_message" {
                    Button(L10n.tr("Gỡ nội dung tin nhắn")) { ask("hide-\(kind)", target) }
                }
                if let userId = subject["userId"] as? String, !userId.isEmpty {
                    Button(L10n.tr("Đình chỉ tài khoản")) { ask("suspend-user", userId) }
                }
            }
            if (report["status"] as? String) == "open", let id = report["id"] as? String {
                Button(L10n.tr("Đóng báo cáo")) { ask("close-report", id) }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func userRow(_ user: [String: Any]) -> some View {
        let role = user["role"] as? String ?? ""
        VStack(alignment: .leading, spacing: 8) {
            Text("\(user["username"] as? String ?? "") · \(role)")
                .font(.subheadline.bold())
                .foregroundColor(KinnectTheme.textPrimary)
            if role != "admin", let id = user["id"] as? String, !id.isEmpty {
                let suspended = Self.flag(user["suspended"])
                Button(L10n.tr(suspended ? "Khôi phục" : "Đình chỉ")) {
                    ask(suspended ? "restore-user" : "suspend-user", id)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func ask(_ action: String, _ target: String) {
        guard !target.isEmpty else { return }
        pending = AdminModeration(action: action, target: target)
        confirm = true
    }

    private static func flag(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.intValue == 1 }
        return false
    }

    private func reload() async {
        guard allowed else { return }
        do {
            let reportData = try await KinnectAPIClient.shared.requestJSON("/api/admin/reports")
            let userData = try await KinnectAPIClient.shared.requestJSON("/api/admin/users")
            reports = reportData["reports"] as? [[String: Any]] ?? []
            users = userData["users"] as? [[String: Any]] ?? []
            status = ""
        } catch {
            status = L10n.tr("Chưa tải được dữ liệu quản trị.")
        }
    }

    private func moderate(_ action: String, _ target: String) async {
        defer { pending = nil }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/admin/moderate",
                method: "POST",
                body: ["action": action, "target": target]
            )
            appState.showToast(L10n.tr("Đã gửi thao tác quản trị."))
            await reload()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

private struct AboutKinnectSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    var onBack: (() -> Void)? = nil

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary
        let rawVersion = (info?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawBuild = (info?["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = (rawVersion?.isEmpty == false) ? rawVersion! : ServerConfig.appVersion
        let build = (rawBuild?.isEmpty == false) ? rawBuild! : ServerConfig.buildNumber
        return "\(L10n.tr("Phiên bản")) \(version) (Build \(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: L10n.tr("Giới thiệu"),
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            VStack(spacing: 16) {
                KinnectBrandLogo(size: 72)
                    .padding(.top, 32)
                Text("Kinnect")
                    .font(.title.weight(.bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(appVersionLabel)
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                Text(L10n.tr("Nền tảng mạng xã hội kết nối trực tiếp, livestream thời gian thực và tương tác đa phương tiện."))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(KinnectTheme.textPrimary)
                    .padding(.horizontal, 32)
                Spacer()
            }
        }
    }
}

private struct SavedBookmarksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var posts: [PostItem] = []
    @State private var isLoading = false
    @State private var hasMore = false
    @State private var nextCursor: Int64? = nil
    @State private var isLoadingMore = false
    @State private var activeCommentPost: PostItem? = nil
    @State private var selectedAuthorProfile: KinnectUser? = nil
    @State private var pendingDeletePost: PostItem? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if isLoading && posts.isEmpty {
                        ProgressView(L10n.tr("Đang tải bài viết đã lưu…"))
                            .padding(.top, 48)
                    } else if posts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundColor(KinnectTheme.textSecondary)
                            Text(L10n.tr("Chưa có bài viết đã lưu"))
                                .font(.headline)
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text(L10n.tr("Các bài viết bạn lưu từ Bảng tin sẽ xuất hiện tại đây để xem lại bất kỳ lúc nào."))
                                .font(.subheadline)
                                .foregroundColor(KinnectTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(posts) { post in
                            VStack(alignment: .trailing, spacing: 6) {
                                Button {
                                    Task { await unbookmark(post) }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bookmark.slash")
                                            .font(.caption.weight(.semibold))
                                        Text(L10n.tr("Bỏ lưu"))
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundColor(KinnectTheme.accentBright)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                                }
                                .buttonStyle(.plain)

                                PostCardView(
                                    post: post,
                                    currentUserId: appState.currentUser?.id ?? "",
                                    isAuthorOnline: post.author.showActivity && (post.author.isActive || appState.onlineUserIds.contains(post.author.id)),
                                    onOpenAuthorProfile: {
                                        selectedAuthorProfile = post.author
                                    },
                                    onReact: { reaction in
                                        Task { await toggleReaction(post: post, reaction: reaction) }
                                    },
                                    onOpenComments: {
                                        activeCommentPost = post
                                    },
                                    onDelete: {
                                        pendingDeletePost = post
                                    },
                                    onReport: {
                                        appState.activeReportContext = UGCReportContext(
                                            targetType: "post",
                                            targetId: post.id,
                                            targetUserId: post.author.id,
                                            targetTitle: "\(L10n.tr("Bài viết của")) \(post.author.name)"
                                        )
                                    },
                                    onBookmark: {
                                        Task { await unbookmark(post) }
                                    }
                                )
                            }
                        }

                        if hasMore, nextCursor != nil {
                            Button {
                                Task { await loadMoreBookmarks() }
                            } label: {
                                HStack(spacing: 8) {
                                    if isLoadingMore { ProgressView() }
                                    Text(isLoadingMore ? L10n.tr("Đang tải…") : L10n.tr("Xem thêm bài viết đã lưu"))
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surfaceElevated))
                            }
                            .disabled(isLoadingMore)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(KinnectTheme.background)
            .refreshable {
                await loadBookmarks()
            }
            .navigationTitle(L10n.tr("Bài viết đã lưu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
            .task {
                await loadBookmarks()
            }
            .sheet(item: $activeCommentPost) { post in
                PostCommentsSheet(post: post) {
                    Task { await loadBookmarks() }
                }
            }
            .fullScreenCover(item: $selectedAuthorProfile) { user in
                ProfileView(targetUser: user)
            }
            .alert(
                L10n.tr("Xóa bài viết?"),
                isPresented: Binding(
                    get: { pendingDeletePost != nil },
                    set: { if !$0 { pendingDeletePost = nil } }
                ),
                presenting: pendingDeletePost
            ) { post in
                Button(L10n.tr("Xóa bài viết"), role: .destructive) {
                    pendingDeletePost = nil
                    Task { await deletePost(post) }
                }
                Button(L10n.tr("Hủy"), role: .cancel) {
                    pendingDeletePost = nil
                }
            } message: { _ in
                Text(L10n.tr("Bài viết đã xóa sẽ không thể khôi phục."))
            }
        }
    }

    private func loadBookmarks() async {
        isLoading = posts.isEmpty
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/bookmarks")
            let rawList = res["posts"] as? [[String: Any]] ?? []
            self.posts = rawList.map { dict in
                var item = PostItem.from(dict)
                item.bookmarked = (dict["bookmarked"] as? Bool) ?? true
                return item
            }
            self.hasMore = (res["hasMore"] as? Bool) ?? false
            self.nextCursor = (res["nextCursor"] as? NSNumber)?.int64Value
        } catch {
            if posts.isEmpty {
                appState.showToast(error.localizedDescription)
            }
        }
    }

    private func loadMoreBookmarks() async {
        guard hasMore, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/bookmarks?before=\(cursor)")
            let more = (res["posts"] as? [[String: Any]] ?? []).map { dict -> PostItem in
                var item = PostItem.from(dict)
                item.bookmarked = (dict["bookmarked"] as? Bool) ?? true
                return item
            }
            let existing = Set(self.posts.map(\.id))
            self.posts.append(contentsOf: more.filter { !existing.contains($0.id) })
            self.hasMore = (res["hasMore"] as? Bool) ?? false
            self.nextCursor = (res["nextCursor"] as? NSNumber)?.int64Value
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func unbookmark(_ post: PostItem) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)/bookmark",
                method: "DELETE"
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                posts.removeAll { $0.id == post.id }
            }
            if let uid = appState.currentUser?.id, !uid.isEmpty {
                AccountCache.shared.evict(forKey: "feed_posts", accountId: uid)
                AccountCache.shared.evict(forKey: "json:/api/posts?limit=25", accountId: uid)
            }
            appState.showToast(L10n.tr("Đã bỏ lưu bài viết."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func toggleReaction(post: PostItem, reaction: String) async {
        let reqId = "react_bm_\(post.id)_\(Int(Date().timeIntervalSince1970))"
        do {
            if post.liked && post.userReaction == reaction {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/like",
                    method: "DELETE",
                    body: [:],
                    requestId: reqId
                )
            } else {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/posts/\(post.id)/like",
                    method: "POST",
                    body: ["reaction": reaction],
                    requestId: reqId
                )
            }
            await loadBookmarks()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deletePost(_ post: PostItem) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts/\(post.id)",
                method: "DELETE",
                body: [:],
                requestId: "del_post_\(post.id)"
            )
            posts.removeAll { $0.id == post.id }
            appState.showToast(L10n.tr("Đã xóa bài viết."))
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

private struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    var onBack: (() -> Void)? = nil
    @State private var enabled = true
    @State private var messages = true
    @State private var friends = true
    @State private var posts = true

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: L10n.tr("Cài đặt thông báo"),
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )
            Form {
                Section {
                    toggle(L10n.tr("Hiện thông báo"), key: "enabled", value: $enabled)
                    toggle(L10n.tr("Tin nhắn"), key: "messages", value: $messages)
                    toggle(L10n.tr("Lời mời kết bạn"), key: "friends", value: $friends)
                    toggle(L10n.tr("Bài viết và tương tác"), key: "posts", value: $posts)
                }
                Section {
                    Button(L10n.tr("Cài đặt thông báo của iOS")) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .onAppear {
            enabled = KinnectNotificationPrefs.isOn("enabled")
            messages = KinnectNotificationPrefs.isOn("messages")
            friends = KinnectNotificationPrefs.isOn("friends")
            posts = KinnectNotificationPrefs.isOn("posts")
        }
    }

    private func toggle(_ title: String, key: String, value: Binding<Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                KinnectNotificationPrefs.set(key, newValue)
            }
        ))
        .tint(KinnectTheme.accent)
    }
}

private struct RecoveryEmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var status = L10n.tr("Đang đọc email khôi phục...")
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challengeId = ""
    @State private var busy = false

    private var hasPassword: Bool {
        appState.currentUser?.hasPassword ?? true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                if challengeId.isEmpty {
                    Section {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                        if hasPassword {
                            SecureField(L10n.tr("Mật khẩu hiện tại"), text: $password)
                        } else {
                            Text(L10n.tr("Tài khoản mạng xã hội chưa có mật khẩu (cần phiên đăng nhập trong 10 phút gần đây)."))
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    Section {
                        Button(busy ? L10n.tr("Đang gửi...") : L10n.tr("Gửi mã xác minh")) {
                            Task { await start() }
                        }
                        .disabled(busy)
                    }
                } else {
                    Section {
                        Text(L10n.tr("Nhập mã xác minh trong email của bạn."))
                        TextField(L10n.tr("Mã xác minh"), text: $code)
                            .keyboardType(.numberPad)
                    }
                    Section {
                        Button(busy ? L10n.tr("Đang xác minh...") : L10n.tr("Xác minh")) {
                            Task { await verify() }
                        }
                        .disabled(busy)
                    }
                }
            }
            .navigationTitle(L10n.tr("Email khôi phục"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Đóng")) { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        #if DEBUG
        if UIReviewFixture.isEnabled {
            status = L10n.tr("Chưa xác minh email khôi phục.")
            return
        }
        #endif
        do {
            let data = try await KinnectAPIClient.shared.requestJSON("/api/recovery/email")
            if let saved = data["email"] as? String, !saved.isEmpty {
                status = "\(L10n.tr("Email đã xác minh:")) \(saved)"
            } else {
                status = L10n.tr("Chưa xác minh email khôi phục.")
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func start() async {
        busy = true
        defer { busy = false }
        #if DEBUG
        if UIReviewFixture.isEnabled {
            AppState.shared.showToast(L10n.tr("Đã ghi nhận yêu cầu xác minh email."))
            return
        }
        #endif
        do {
            let data = try await KinnectAPIClient.shared.requestJSON(
                "/api/recovery/email/start",
                method: "POST",
                body: ["email": email, "password": password]
            )
            challengeId = (data["challengeId"] as? String) ?? ""
            AppState.shared.showToast((data["message"] as? String) ?? L10n.tr("Đã gửi mã xác minh tới email của bạn."))
        } catch {
            AppState.shared.showToast(error.localizedDescription)
        }
    }

    private func verify() async {
        busy = true
        defer { busy = false }
        do {
            let data = try await KinnectAPIClient.shared.requestJSON(
                "/api/recovery/email/verify",
                method: "POST",
                body: ["challengeId": challengeId, "code": code]
            )
            AppState.shared.showToast(L10n.tr("Đã xác minh email."))
            if let saved = data["email"] as? String, !saved.isEmpty {
                status = "\(L10n.tr("Email đã xác minh:")) \(saved)"
            }
            challengeId = ""
            code = ""
            password = ""
        } catch {
            AppState.shared.showToast(error.localizedDescription)
        }
    }
}

private struct AppReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    private let reasons = [
        "An toàn trẻ em",
        "Quấy rối hoặc bắt nạt",
        "Thù ghét hoặc phân biệt đối xử",
        "Giả mạo tài khoản",
        "Lừa đảo hoặc spam",
        "Nội dung tình dục không phù hợp",
        "Bạo lực hoặc nguy hiểm",
        "Vấn đề khác"
    ]
    @State private var reason = "Vấn đề khác"
    @State private var detail = ""
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Picker(L10n.tr("Lý do"), selection: $reason) {
                    ForEach(reasons, id: \.self) { Text(L10n.tr($0)).tag($0) }
                }
                TextField(L10n.tr("Bổ sung chi tiết (tùy chọn)"), text: $detail)
                Button(sending ? L10n.tr("Đang gửi...") : L10n.tr("Gửi")) {
                    Task { await submit() }
                }
                .disabled(sending)
            }
            .navigationTitle(L10n.tr("Báo cáo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Hủy")) { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        let target = appState.currentUser?.id ?? ""
        guard !target.isEmpty else {
            appState.showToast(L10n.tr("Cần đăng nhập để gửi báo cáo."))
            return
        }
        sending = true
        defer { sending = false }
        let composed = detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? reason : "\(reason): \(detail)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/reports",
                method: "POST",
                body: ["targetType": "app", "targetId": target, "reason": composed],
                requestId: "report_app_\(target)"
            )
            appState.showToast(L10n.tr("Đã gửi báo cáo để quản trị viên xem xét."))
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
