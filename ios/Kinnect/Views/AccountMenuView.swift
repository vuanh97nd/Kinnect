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
                    title: "Tài khoản",
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
        .confirmationDialog("Đăng xuất khỏi Kinnect?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) {
                if let onBack = onBack {
                    onBack()
                } else {
                    dismiss()
                }
                Task {
                    await appState.logout()
                }
            }
            Button("Hủy", role: .cancel) { }
        } message: {
            Text("Bạn có thể đăng nhập lại bất kỳ lúc nào.")
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
                    Text(appState.currentUser?.name ?? "Người dùng Kinnect")
                        .font(.title3.weight(.bold))
                        .foregroundColor(KinnectTheme.textPrimary)

                    Text("@\(appState.currentUser?.handle ?? "kinnect")")
                        .font(KinnectTheme.scaled(14))
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
        .accessibilityLabel("Trang cá nhân")
    }

    @ViewBuilder
    private var adminMenuGroup: some View {
        if appState.currentUser?.accountRole == "admin" {
            VStack(spacing: 0) {
                menuRow(systemName: "checkmark.shield", title: "Bảng quản trị") {
                    withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .admin }
                }
            }
            .background(settingsGroupBackground)
        }
    }

    private var mainMenuGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "bag", title: "Cửa hàng Kinnect") { onOpenStore?() }
            menuDivider
            menuRow(systemName: "creditcard", title: "Ví Kinnect") { onOpenWallet() }
            menuDivider
            menuRow(systemName: "hand.raised", title: "Cài đặt và quyền riêng tư") {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .privacy }
            }
            menuDivider
            menuRow(systemName: "lock.shield", title: "Bảo mật và đăng nhập") {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .security }
            }
            menuDivider
            menuRow(systemName: "bell", title: "Cài đặt thông báo") {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .notifications }
            }
            menuDivider
            menuRow(systemName: "circle.lefthalf.filled", title: "Giao diện") {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .appearance }
            }
            menuDivider
            menuRow(systemName: "questionmark.circle", title: "Trợ giúp và hỗ trợ") {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .support }
            }
            menuDivider
            menuRow(systemName: "info.circle", title: "Giới thiệu Kinnect") {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .about }
            }
        }
        .background(settingsGroupBackground)
    }

    private var endMenuGroup: some View {
        VStack(spacing: 0) {
            menuRow(systemName: "key", title: "Đổi mật khẩu") {
                withAnimation(.easeInOut(duration: 0.2)) { activeSubScreen = .password }
            }
            menuDivider
            menuRow(systemName: "rectangle.portrait.and.arrow.right", title: "Đăng xuất", isDestructive: true) {
                showLogoutConfirm = true
            }
        }
        .background(settingsGroupBackground)
    }

    private var menuDivider: some View {
        HStack {
            Spacer().frame(width: 64)
            Divider().background(KinnectTheme.borderSoft.opacity(0.8))
        }
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
        Text("Kinnect · Kết nối theo cách của bạn.")
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
                        .font(KinnectTheme.scaled(18, weight: .semibold))
                        .foregroundColor(tint)
                }

                Text(title)
                    .font(KinnectTheme.scaled(15, weight: .medium))
                    .foregroundColor(isDestructive ? tint : KinnectTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(KinnectTheme.scaled(14, weight: .semibold))
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

struct PrivacySettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var language = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil

    @State private var discoverable: Bool = true
    @State private var showDistance: Bool = true
    @State private var showActivity: Bool = true
    @State private var dmFriendsOnly: Bool = false
    @State private var statusNote = ""
    @State private var failedDmMode: String?
    @State private var failedPrivacyKey: String?
    @State private var failedPrivacyValue: Bool?
    @State private var failedLocationOff = false
    @State private var showEditProfile = false
    @State private var showPrivateAlbum = false
    @State private var showBlockedUsers = false
    @State private var showDeleteAccount = false
    @State private var privatePhotos: [PrivatePhotoItem] = []
    @State private var privateRequests: [PrivateAccessRequestItem] = []

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Cài đặt & riêng tư",
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            Form {
                if !statusNote.isEmpty {
                    Section {
                        Text(statusNote)
                            .font(KinnectTheme.caption)
                            .foregroundColor(KinnectTheme.danger)
                        if let failedDmMode {
                            Button("Thử lại") { updateDmMode(failedDmMode) }
                        } else if let failedPrivacyKey, let failedPrivacyValue {
                            Button("Thử lại") { updatePrivacySetting(failedPrivacyKey, value: failedPrivacyValue) }
                        } else if failedLocationOff {
                            Button("Thử lại") { Task { await turnOffLocation() } }
                        }
                    }
                }
                Section("Ngôn ngữ") {
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
                        languageRow("Theo hệ thống", selected: language.preference == .system)
                    }
                }

                Section("Thông tin cá nhân") {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack {
                            Text(appState.currentUser?.name ?? "Người dùng Kinnect")
                            Text("· chỉnh sửa hồ sơ")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    }
                }

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

                Section("Ai có thể nhắn tin") {
                    Picker("Ai có thể nhắn tin", selection: Binding(
                        get: { dmFriendsOnly ? "friends" : "everyone" },
                        set: { updateDmMode($0) }
                    )) {
                        Text("Mọi thành viên").tag("everyone")
                        Text("Bạn bè").tag("friends")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Quyền truy cập") {
                    Button("Ảnh riêng tư") { showPrivateAlbum = true }
                    Button("Tài khoản đã chặn") { showBlockedUsers = true }
                }

                Section("Quản lý tài khoản") {
                    Button("Xóa tài khoản và dữ liệu", role: .destructive) {
                        showDeleteAccount = true
                    }
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
            .onAppear {
                if let user = appState.currentUser {
                    self.discoverable = user.discoverable
                    self.showDistance = user.showDistance
                    self.showActivity = user.showActivity
                    self.dmFriendsOnly = user.dmMode == "friends"
                }
            }
            .task {
                if UIReviewFixture.activeScreen == "privacy-toggle-error" {
                    discoverable = true
                    updatePrivacySetting("discoverable", value: false)
                } else if UIReviewFixture.activeScreen == "dm-mode-error" {
                    dmFriendsOnly = false
                    updateDmMode("friends")
                } else if UIReviewFixture.activeScreen == "location-off-error" {
                    await turnOffLocation()
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

    private func storedBool(_ key: String) -> Bool {
        switch key {
        case "showActivity": return showActivity
        case "discoverable": return discoverable
        case "showDistance": return showDistance
        default: return false
        }
    }

    private func setStoredBool(_ key: String, _ value: Bool) {
        switch key {
        case "showActivity": showActivity = value
        case "discoverable": discoverable = value
        case "showDistance": showDistance = value
        default: break
        }
    }

    private func updatePrivacySetting(_ key: String, value: Bool) {
        let previous = storedBool(key)
        setStoredBool(key, value)
        statusNote = "Đang lưu..."
        Task {
            do {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/me",
                    method: "PATCH",
                    body: [key: value]
                )
                if var user = appState.currentUser {
                    if key == "showActivity" { user.showActivity = value }
                    if key == "discoverable" { user.discoverable = value }
                    if key == "showDistance" { user.showDistance = value }
                    appState.currentUser = user
                }
                if key == "showActivity" && value {
                    appState.reportActiveStatus(force: true)
                }
                failedPrivacyKey = nil
                failedPrivacyValue = nil
                statusNote = ""
            } catch {
                setStoredBool(key, previous)
                failedPrivacyKey = key
                failedPrivacyValue = value
                statusNote = "Chưa lưu. \(error.localizedDescription)"
                appState.showToast(statusNote)
                if UIReviewFixture.activeScreen == "privacy-toggle-error" {
                    UIReviewFixture.writeDocument("privacy-toggle-error.json", [
                        "rolledBack": storedBool(key) == previous,
                        "retry": failedPrivacyKey != nil,
                        "successToast": false,
                        "note": statusNote
                    ])
                }
            }
        }
    }

    private func updateDmMode(_ mode: String) {
        let normalized = mode == "friends" ? "friends" : "everyone"
        let previous = dmFriendsOnly
        dmFriendsOnly = normalized == "friends"
        statusNote = "Đang lưu..."
        Task {
            do {
                _ = try await KinnectAPIClient.shared.requestJSON(
                    "/api/me",
                    method: "PATCH",
                    body: ["dmMode": normalized]
                )
                if var user = appState.currentUser {
                    user.dmMode = normalized
                    appState.currentUser = user
                }
                failedDmMode = nil
                statusNote = ""
            } catch {
                dmFriendsOnly = previous
                failedDmMode = normalized
                statusNote = "Chưa lưu ai có thể nhắn tin. \(error.localizedDescription)"
                appState.showToast(statusNote)
                if UIReviewFixture.activeScreen == "dm-mode-error" {
                    UIReviewFixture.writeDocument("dm-mode-error.json", [
                        "priorMode": previous ? "friends" : "everyone",
                        "requestedMode": normalized,
                        "afterMode": dmFriendsOnly ? "friends" : "everyone",
                        "rolledBack": dmFriendsOnly == previous,
                        "retry": failedDmMode != nil,
                        "successToast": false
                    ])
                }
            }
        }
    }

    private func turnOffLocation() async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/location",
                method: "PATCH",
                body: ["enabled": false]
            )
            if var user = appState.currentUser {
                user.hasLocation = false
                appState.currentUser = user
            }
            failedLocationOff = false
            statusNote = ""
            appState.showToast("Đã tắt tìm quanh đây")
        } catch {
            failedLocationOff = true
            statusNote = "Chưa tắt tìm quanh đây. \(error.localizedDescription)"
            appState.showToast(statusNote)
            if UIReviewFixture.activeScreen == "location-off-error" {
                UIReviewFixture.writeDocument("location-off-error.json", [
                    "saved": false,
                    "retry": failedLocationOff,
                    "successToast": false,
                    "note": statusNote
                ])
            }
        }
    }
}

private struct SecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil
    var onChangePassword: () -> Void

    @State private var showRecovery = false
    @State private var showSessions = false

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Bảo mật và đăng nhập",
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            List {
                Button("Đổi mật khẩu", action: onChangePassword)
                Button("Email khôi phục") { showRecovery = true }
                Button("Thiết bị đăng nhập") { showSessions = true }
                Link("Hỗ trợ tài khoản và khôi phục", destination: URL(string: "https://kinnect.io.vn/support")!)
            }
            .foregroundColor(KinnectTheme.textPrimary)
        }
        .sheet(isPresented: $showRecovery) {
            RecoveryEmailSheet()
        }
        .sheet(isPresented: $showSessions) {
            ActiveSessionsSheet()
        }
    }
}

private struct ChangePasswordSheetView: View {
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Đổi mật khẩu",
                onBack: onBack ?? { dismiss() },
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
                    Button("Lưu") {
                        Task { await submit() }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(KinnectTheme.accentBright)
                }
            }
        }
    }

    private func submit() async {
        errorMessage = ""
        let decision = PasswordChangeValidation.evaluate(
            current: oldPassword,
            next: newPassword,
            confirm: confirmPassword
        )
        if let message = decision.message {
            errorMessage = message
            return
        }
        if UIReviewFixture.activeScreen != nil {
            PasswordTransportSpy.record(current: oldPassword, next: newPassword)
            AppState.shared.showToast("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.")
            close()
            return
        }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/password",
                method: "POST",
                body: ["current": oldPassword, "next": newPassword]
            )
            AppState.shared.showToast("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.")
            close()
        } catch {
            errorMessage = error.localizedDescription
            AppState.shared.showToast(error.localizedDescription)
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
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Giao diện",
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            Form {
                Section("Giao diện ứng dụng") {
                    appearanceChoice("Theo hệ thống", value: "system")
                    appearanceChoice("Sáng", value: "light")
                    appearanceChoice("Tối", value: "dark")
                }
            }
        }
    }

    private func appearanceChoice(_ title: String, value: String) -> some View {
        Button {
            colorSchemeSetting = value
        } label: {
            HStack {
                Text(title)
                    .foregroundColor(KinnectTheme.textPrimary)
                Spacer()
                if colorSchemeSetting == value {
                    Image(systemName: "checkmark").foregroundColor(KinnectTheme.accent)
                }
            }
        }
    }
}

private struct HelpSupportSheetView: View {
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Trợ giúp và hỗ trợ",
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            List {
                Button("Báo sự cố") { showReport = true }
                Button("Trung tâm hỗ trợ") { Task { await openSupport() } }
                Link("Chính sách quyền riêng tư", destination: URL(string: "https://kinnect.io.vn/privacy")!)
                Link("Quy tắc cộng đồng", destination: URL(string: "https://kinnect.io.vn/community")!)
                Link("An toàn trẻ em", destination: URL(string: "https://kinnect.io.vn/child-safety")!)
                Link("Giấy phép phần mềm", destination: URL(string: "https://app.kinnect.io.vn/third-party-notices.txt")!)
                Text("Mr Ánh · Hỗ trợ và quyền riêng tư: anhvn53@wru.vn")
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
        .alert("Hỗ trợ Kinnect", isPresented: $showSupportFallback) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Liên hệ riêng Mr Ánh: anhvn53@wru.vn. Không gửi mật khẩu hoặc OTP.")
        }
    }

    @State private var showReport = false
    @State private var supportPeer: KinnectUser?
    @State private var showSupportFallback = false

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
    @State private var reports: [[String: Any]] = []
    @State private var users: [[String: Any]] = []
    @State private var economyLines: [String] = []
    @State private var aiLine = ""
    @State private var musicLines: [String] = []
    @State private var status = ""
    @State private var corePhase = "loading"
    @State private var economyPhase = "loading"
    @State private var aiPhase = "loading"
    @State private var musicPhase = "loading"
    @State private var pending: AdminModeration?
    @State private var confirm = false
    @State private var economyDraft: AdminEconomyDraft?
    @State private var aiSummary: AdminAICredentialSummary?
    @State private var aiSupportEnabled = false
    @State private var aiModerationEnabled = false
    @State private var musicItems: [AdminMusicItem] = []
    @State private var showEconomyEditor = false
    @State private var showMusicManager = false
    @State private var showAISettings = false

    private var allowed: Bool {
        #if DEBUG
        if UIReviewFixture.activeScreen == "admin-denied" { return false }
        if ["admin", "admin-loading", "admin-empty", "admin-error"].contains(UIReviewFixture.activeScreen) {
            return true
        }
        #endif
        return appState.currentUser?.accountRole == "admin"
    }

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Bảng quản trị",
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )
            if allowed {
                List {
                    if corePhase == "loading" {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Đang tải bảng quản trị.")
                                .font(.footnote)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    if !status.isEmpty {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    if corePhase == "failed" || economyPhase == "failed" || aiPhase == "failed" || musicPhase == "failed" {
                        Button("Thử lại") { Task { await reload() } }
                    }
                    Section("Báo cáo") {
                        if corePhase == "loading" {
                            Text("Đang tải báo cáo.")
                                .foregroundColor(KinnectTheme.textSecondary)
                        } else if reports.isEmpty {
                            Text("Chưa có báo cáo.")
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        ForEach(Array(reports.enumerated()), id: \.offset) { _, report in
                            reportRow(report)
                        }
                    }
                    Section("Thành viên gần đây") {
                        if corePhase == "loading" {
                            Text("Đang tải thành viên.")
                                .foregroundColor(KinnectTheme.textSecondary)
                        } else if users.isEmpty {
                            Text("Chưa có thành viên.")
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        ForEach(Array(users.enumerated()), id: \.offset) { _, user in
                            userRow(user)
                        }
                    }
                    Section("Kinh tế") {
                        panelStatus(
                            economyPhase,
                            loading: "Đang tải giá quà.",
                            empty: "Chưa có giá quà.",
                            failed: "Chưa tải được giá quà."
                        )
                        ForEach(Array(economyLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(KinnectTheme.caption)
                        }
                        if economyPhase == "ready", economyDraft != nil {
                            Button("Chỉnh sửa & lưu cấu hình kinh tế") {
                                showEconomyEditor = true
                            }
                        } else {
                            Text("Khóa phiên bản lạc quan (PATCH /api/admin/economy).")
                                .font(KinnectTheme.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                    Section("Trợ lý AI") {
                        panelStatus(
                            aiPhase,
                            loading: "Đang tải trạng thái AI.",
                            empty: "Chưa có trạng thái AI.",
                            failed: "Chưa tải được trạng thái AI."
                        )
                        if aiPhase == "ready" {
                            Text(aiLine).font(KinnectTheme.caption)
                            if aiSummary != nil {
                                Button("Xem cấu hình & bảo mật AI") {
                                    showAISettings = true
                                }
                            }
                        }
                        Text("Không hiện khóa. Cập nhật khóa AI yêu cầu xác thực mật khẩu quản trị.")
                            .font(KinnectTheme.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Section("Thư viện nhạc") {
                        panelStatus(
                            musicPhase,
                            loading: "Đang tải danh sách nhạc.",
                            empty: "Chưa có bài nhạc.",
                            failed: "Chưa tải được danh sách nhạc."
                        )
                        ForEach(Array(musicLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(KinnectTheme.caption)
                        }
                        if musicPhase == "ready" || musicPhase == "empty" {
                            Button("Quản lý / thêm bài nhạc") {
                                showMusicManager = true
                            }
                        }
                    }
                }
            } else {
                Text("Chỉ quản trị viên được vào bảng quản trị.")
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(KinnectTheme.background)
        .task { await reload() }
        .confirmationDialog("Xác nhận thao tác quản trị?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Xác nhận", role: .destructive) {
                if let pending {
                    Task { await moderate(pending.action, pending.target) }
                }
            }
            Button("Hủy", role: .cancel) { pending = nil }
        }
        .sheet(isPresented: $showEconomyEditor) {
            if let economyDraft {
                AdminEconomyEditorSheet(initialDraft: economyDraft) {
                    Task { await reload() }
                }
            }
        }
        .sheet(isPresented: $showMusicManager) {
            AdminMusicManagerSheet(tracks: musicItems) {
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showAISettings) {
            if let aiSummary {
                AdminAISettingsSheet(
                    summary: aiSummary,
                    supportEnabled: aiSupportEnabled,
                    moderationEnabled: aiModerationEnabled,
                    onSaved: { Task { await reload() } }
                )
            }
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
                    Button(hidden ? (kind == "short" ? "Hiện video" : "Hiện bài") : (kind == "short" ? "Ẩn video" : "Ẩn bài")) {
                        ask(hidden ? "show-\(kind)" : "hide-\(kind)", target)
                    }
                }
                if kind == "message" || kind == "group_message" {
                    Button("Gỡ nội dung tin nhắn") { ask("hide-\(kind)", target) }
                }
                if let userId = subject["userId"] as? String, !userId.isEmpty {
                    Button("Đình chỉ tài khoản") { ask("suspend-user", userId) }
                }
            }
            if (report["status"] as? String) == "open", let id = report["id"] as? String {
                Button("Đóng báo cáo") { ask("close-report", id) }
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
                Button(suspended ? "Khôi phục" : "Đình chỉ") {
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

    @ViewBuilder
    private func panelStatus(_ phase: String, loading: String, empty: String, failed: String) -> some View {
        if phase == "loading" {
            Text(loading).foregroundColor(KinnectTheme.textSecondary)
        } else if phase == "empty" {
            Text(empty).foregroundColor(KinnectTheme.textSecondary)
        } else if phase == "failed" {
            Text(failed).foregroundColor(KinnectTheme.textSecondary)
        }
    }

    private func reload() async {
        guard allowed else {
            UIReviewFixture.writeDocument("admin-denied.json", [
                "allowed": false,
                "adminApiCalls": UIReviewFixture.adminApiCalls
            ])
            return
        }
        corePhase = "loading"
        economyPhase = "loading"
        aiPhase = "loading"
        musicPhase = "loading"
        do {
            let reportData = try await KinnectAPIClient.shared.requestJSON("/api/admin/reports")
            let userData = try await KinnectAPIClient.shared.requestJSON("/api/admin/users")
            reports = reportData["reports"] as? [[String: Any]] ?? []
            users = userData["users"] as? [[String: Any]] ?? []
            corePhase = "ready"
            status = ""
        } catch {
            reports = []
            users = []
            economyLines = []
            musicLines = []
            aiLine = ""
            corePhase = "failed"
            economyPhase = "failed"
            aiPhase = "failed"
            musicPhase = "failed"
            status = "Chưa tải được dữ liệu quản trị."
            return
        }
        await loadEconomy()
        await loadAIStatus()
        await loadMusicLibrary()
    }

    private func loadEconomy() async {
        guard let data = try? await KinnectAPIClient.shared.requestJSON("/api/admin/economy") else {
            economyLines = []
            economyDraft = nil
            economyPhase = "failed"
            return
        }
        economyDraft = AdminEconomyDraft.parse(from: data)
        let config = data["config"] as? [String: Any] ?? [:]
        let prices = config["giftPrices"] as? [String: Any] ?? [:]
        economyLines = prices.keys.sorted().map { key in
            let value = (prices[key] as? NSNumber)?.intValue ?? (prices[key] as? Int) ?? 0
            return "\(key): \(value) xu"
        }
        economyPhase = economyLines.isEmpty ? "empty" : "ready"
    }

    private func loadAIStatus() async {
        guard let data = try? await KinnectAPIClient.shared.requestJSON("/api/admin/ai") else {
            aiLine = ""
            aiSummary = nil
            aiPhase = "failed"
            return
        }
        let config = data["config"] as? [String: Any] ?? [:]
        if config.isEmpty {
            aiLine = ""
            aiSummary = nil
            aiPhase = "empty"
            return
        }
        aiSummary = AdminAICredentialSummary.parse(from: data)
        aiSupportEnabled = AdminActionsContract.flag(config["support"])
        aiModerationEnabled = AdminActionsContract.flag(config["moderation"])
        let ready = (config["ready"] as? Bool) ?? ((config["ready"] as? NSNumber)?.boolValue ?? false)
        let queue = (config["queue"] as? NSNumber)?.intValue ?? (config["queue"] as? Int) ?? 0
        let failed = (config["failed"] as? NSNumber)?.intValue ?? (config["failed"] as? Int) ?? 0
        aiLine = "Sẵn sàng: \(ready ? "có" : "không"). Hàng chờ \(queue). Lỗi \(failed)."
        aiPhase = "ready"
    }

    private func loadMusicLibrary() async {
        guard let data = try? await KinnectAPIClient.shared.requestJSON("/api/music") else {
            musicLines = []
            musicItems = []
            musicPhase = "failed"
            return
        }
        let tracks = data["tracks"] as? [[String: Any]] ?? []
        musicItems = tracks.compactMap { track in
            let file = track["file"] as? String ?? ""
            let title = track["title"] as? String ?? ""
            guard !file.isEmpty, !title.isEmpty else { return nil }
            return AdminMusicItem(
                file: file,
                title: title,
                artist: track["artist"] as? String ?? "",
                license: track["license"] as? String ?? ""
            )
        }
        musicLines = tracks.compactMap { track in
            let title = track["title"] as? String ?? ""
            return title.isEmpty ? nil : title
        }
        musicPhase = musicLines.isEmpty ? "empty" : "ready"
    }

    private func moderate(_ action: String, _ target: String) async {
        defer { pending = nil }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/admin/moderate",
                method: "POST",
                body: ["action": action, "target": target]
            )
            appState.showToast("Đã gửi thao tác quản trị.")
            await reload()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

private struct AboutKinnectSheetView: View {
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Giới thiệu Kinnect",
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            ScrollView {
                VStack(spacing: 8) {
                    KinnectBrandLogo(size: 72)
                        .padding(.top, 20)
                    Text("Kinnect")
                        .font(KinnectTheme.scaled(22, weight: .bold))
                        .foregroundColor(KinnectTheme.accent)
                    Text("Kết nối theo cách của bạn.")
                        .font(KinnectTheme.scaled(13))
                        .foregroundColor(KinnectTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 10) {
                        aboutRow("Tác giả", "Vũ Ngọc Ánh")
                        aboutRow("Đang dùng", "\(ServerConfig.appVersion) (\(ServerConfig.buildNumber))")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 24).fill(KinnectTheme.surface))
                    .padding(.top, 12)
                    Text("Kiểm tra cập nhật APK là luồng Android. iOS không có màn cập nhật đó.")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
        }
    }

    private func aboutRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(KinnectTheme.textSecondary)
            Text(value)
                .font(KinnectTheme.scaled(15, weight: .medium))
                .foregroundColor(KinnectTheme.textPrimary)
                .textSelection(.enabled)
        }
    }
}

private struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var onBack: (() -> Void)? = nil
    @State private var enabled = true
    @State private var messages = true
    @State private var friends = true
    @State private var posts = true

    var body: some View {
        VStack(spacing: 0) {
            PinnedHeaderBar(
                title: "Cài đặt thông báo",
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )
            Form {
                Section {
                    toggle("Hiện thông báo", key: "enabled", value: $enabled)
                    toggle("Tin nhắn", key: "messages", value: $messages)
                    toggle("Lời mời kết bạn", key: "friends", value: $friends)
                    toggle("Bài viết và tương tác", key: "posts", value: $posts)
                }
                Section {
                    Button("Cài đặt thông báo của iOS") {
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
    @State private var status = "Đang đọc email khôi phục..."
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var challengeId = ""
    @State private var busy = false

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
                        SecureField("Mật khẩu hiện tại", text: $password)
                    }
                    Section {
                        Button(busy ? "Đang gửi..." : "Gửi mã xác minh") {
                            Task { await start() }
                        }
                        .disabled(busy)
                    }
                } else {
                    Section {
                        Text("Nhập mã xác minh trong email của bạn.")
                        TextField("Mã xác minh", text: $code)
                            .keyboardType(.numberPad)
                    }
                    Section {
                        Button(busy ? "Đang xác minh..." : "Xác minh") {
                            Task { await verify() }
                        }
                        .disabled(busy)
                    }
                }
            }
            .navigationTitle("Email khôi phục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        if UIReviewFixture.isEnabled {
            status = "Chưa xác minh email khôi phục."
            return
        }
        do {
            let data = try await KinnectAPIClient.shared.requestJSON("/api/recovery/email")
            if let saved = data["email"] as? String, !saved.isEmpty {
                status = "Email đã xác minh: \(saved)"
            } else {
                status = "Chưa xác minh email khôi phục."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func start() async {
        busy = true
        defer { busy = false }
        if UIReviewFixture.isEnabled {
            AppState.shared.showToast("Bản xem giao diện không gửi email.")
            return
        }
        do {
            let data = try await KinnectAPIClient.shared.requestJSON(
                "/api/recovery/email/start",
                method: "POST",
                body: ["email": email, "password": password]
            )
            challengeId = (data["challengeId"] as? String) ?? ""
            AppState.shared.showToast((data["message"] as? String) ?? "Đã gửi mã xác minh tới email của bạn.")
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
            AppState.shared.showToast("Đã xác minh email.")
            if let saved = data["email"] as? String, !saved.isEmpty {
                status = "Email đã xác minh: \(saved)"
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
    private let reasons = [
        "An toàn trẻ em · CSAE/CSAM",
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
                Picker("Lý do", selection: $reason) {
                    ForEach(reasons, id: \.self) { Text($0).tag($0) }
                }
                TextField("Bổ sung chi tiết (tùy chọn)", text: $detail)
                Button(sending ? "Đang gửi..." : "Gửi") {
                    Task { await submit() }
                }
                .disabled(sending)
            }
            .navigationTitle("Báo cáo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        let target = appState.currentUser?.id ?? ""
        guard !target.isEmpty else {
            appState.showToast("Cần đăng nhập để gửi báo cáo.")
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
            appState.showToast("Đã gửi báo cáo để quản trị viên xem xét.")
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
