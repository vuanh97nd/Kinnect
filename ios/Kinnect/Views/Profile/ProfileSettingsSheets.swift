import SwiftUI
import UIKit

// MARK: - Account & Security Sheets
struct ActiveSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var sessions: [[String: Any]] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                    let sid = s["id"] as? String ?? ""
                    let label = (s["label"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Thiết bị Kinnect"
                    let current = s["current"] as? Bool ?? false
                    let expires = (s["expires"] as? NSNumber)?.int64Value ?? (s["expires"] as? Int64) ?? Int64((s["expires"] as? Int) ?? 0)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label)
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                                .kinnectMultiline()
                            Text(current ? "Thiết bị hiện tại" : Self.sessionExpiry(expires))
                                .font(.caption)
                                .foregroundColor(current ? KinnectTheme.online : KinnectTheme.textSecondary)
                        }
                        Spacer()
                        if !current && !sid.isEmpty {
                            Button(role: .destructive) {
                                Task { await revokeSession(sid) }
                            } label: {
                                Text("Đăng xuất")
                                    .font(.caption.bold())
                            }
                        }
                    }
                    .listRowBackground(KinnectTheme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Phiên đăng nhập")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSessions()
            }
        }
    }

    private static func sessionExpiry(_ expires: Int64) -> String {
        guard expires > 0 else { return "Phiên hoạt động" }
        let date = Date(timeIntervalSince1970: TimeInterval(expires) / 1000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM/yyyy"
        return "Hết hạn \(formatter.string(from: date))"
    }

    private func loadSessions() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me/sessions") {
            self.sessions = res["sessions"] as? [[String: Any]] ?? []
        }
    }

    private func revokeSession(_ id: String) async {
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/me/sessions/\(id)",
            method: "DELETE",
            body: [:],
            requestId: "revoke_\(id)"
        )
        await loadSessions()
    }
}

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showCurrentPassword = false
    @State private var showNewPassword = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bảo mật mật khẩu")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Mật khẩu mới cần tối thiểu 6 ký tự. Sau khi đổi mật khẩu, phiên đăng nhập trên thiết bị hiện tại sẽ được duy trì và các thiết bị khác sẽ cần đăng nhập lại.")
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mật khẩu hiện tại")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        HStack {
                            if showCurrentPassword {
                                TextField("Nhập mật khẩu hiện tại", text: $currentPassword)
                            } else {
                                SecureField("Nhập mật khẩu hiện tại", text: $currentPassword)
                            }
                            KinnectIconButton(
                                glyph: showCurrentPassword ? .eyeOff : .eye,
                                label: showCurrentPassword ? "Ẩn" : "Hiện",
                                tint: KinnectTheme.textSecondary
                            ) {
                                showCurrentPassword.toggle()
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mật khẩu mới")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        HStack {
                            if showNewPassword {
                                TextField("Tối thiểu 6 ký tự", text: $newPassword)
                            } else {
                                SecureField("Tối thiểu 6 ký tự", text: $newPassword)
                            }
                            KinnectIconButton(
                                glyph: showNewPassword ? .eyeOff : .eye,
                                label: showNewPassword ? "Ẩn" : "Hiện",
                                tint: KinnectTheme.textSecondary
                            ) {
                                showNewPassword.toggle()
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Xác nhận mật khẩu mới")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        SecureField("Nhập lại mật khẩu mới", text: $confirmPassword)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.footnote.weight(.medium))
                            .foregroundColor(KinnectTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await updatePassword() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }
                            Text("Cập nhật mật khẩu")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            canSubmit
                                ? KinnectTheme.primaryGradient
                                : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .disabled(!canSubmit || isSubmitting)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Đổi mật khẩu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty && newPassword.count >= 6 && !confirmPassword.isEmpty && confirmPassword == newPassword
    }

    private func updatePassword() async {
        errorMessage = nil
        guard newPassword == confirmPassword else {
            errorMessage = "Mật khẩu xác nhận không khớp."
            return
        }
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            appState.showToast("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.")
            dismiss()
            return
        }
        #endif
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/password",
                method: "POST",
                body: [
                    "current": currentPassword,
                    "next": newPassword
                ]
            )
            appState.showToast("Đã đổi mật khẩu. Các thiết bị khác đã được đăng xuất.")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            appState.showToast(error.localizedDescription)
        }
    }
}

struct BlockedUsersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var blockedUsers: [KinnectUser] = []

    var body: some View {
        NavigationStack {
            List {
                if blockedUsers.isEmpty {
                    Text("Bạn chưa chặn người dùng nào.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .listRowBackground(KinnectTheme.surface)
                } else {
                    ForEach(blockedUsers) { u in
                        HStack(spacing: 12) {
                            KinnectAvatarView(name: u.name, avatarURL: u.avatarUrl, colorHex: u.avatarColor, size: 36)
                            Text(u.name)
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            Spacer()
                            Button("Bỏ chặn") {
                                Task { await unblock(u) }
                            }
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                        .listRowBackground(KinnectTheme.surface)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Người dùng đã chặn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadBlocks()
            }
        }
    }

    private func loadBlocks() async {
        #if DEBUG
        if UIReviewFixture.isEnabled {
            self.blockedUsers = [
                KinnectUser.from([
                    "id": "fixture_blocked_01",
                    "name": "Trần Văn Bình",
                    "handle": "binh_tran",
                    "avatarColor": "#EF4444"
                ]),
                KinnectUser.from([
                    "id": "fixture_blocked_02",
                    "name": "Lê Hoàng Phúc",
                    "handle": "phuc_le",
                    "avatarColor": "#F59E0B"
                ])
            ]
            return
        }
        #endif
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me/blocks") {
            let list = res["users"] as? [[String: Any]] ?? []
            self.blockedUsers = list.map(KinnectUser.from)
        }
    }

    private func unblock(_ u: KinnectUser) async {
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/me/blocks/\(u.id)",
            method: "DELETE",
            body: [:],
            requestId: "unblock_\(u.id)"
        )
        await loadBlocks()
    }
}

struct DeleteAccountConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var confirmUsername = ""
    @State private var password = ""
    @State private var requiredUsername = ""
    @State private var summaryInfo: String = "Xóa tài khoản là hành động không thể đảo ngược."
    @State private var isDeleting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cảnh báo: Hành động này sẽ xóa vĩnh viễn tài khoản Kinnect, bài viết, video ngắn, tin nhắn, ví và toàn bộ phiên đăng nhập của bạn. Không thể khôi phục sau khi xóa.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.danger)
                        .kinnectMultiline()

                    Text(summaryInfo)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nhập chính xác tên đăng nhập của bạn để xác nhận (\(requiredUsername.isEmpty ? (appState.currentUser?.handle ?? "") : requiredUsername)):")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        TextField("Tên đăng nhập", text: $confirmUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nhập mật khẩu hiện tại")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        SecureField("Mật khẩu của bạn", text: $password)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    Button(role: .destructive) {
                        Task { await performAccountDeletion() }
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Xác nhận xóa vĩnh viễn tài khoản")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(KinnectTheme.danger)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .disabled(isDeleting || confirmUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != targetUsername.lowercased())
                }
                .padding(16)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Xóa tài khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
            }
            .task {
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me/account-deletion") {
                    if let u = res["username"] as? String, !u.isEmpty {
                        self.requiredUsername = u
                    }
                }
            }
        }
    }

    private var targetUsername: String {
        if !requiredUsername.isEmpty { return requiredUsername }
        return appState.currentUser?.handle ?? ""
    }

    private func performAccountDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/account-deletion",
                method: "DELETE",
                body: [
                    "confirmUsername": confirmUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    "confirmDelete": true,
                    "password": password
                ]
            )
            dismiss()
            appState.clearSessionState()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct PrivacySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @AppStorage("app_appearance_mode") private var appearanceMode: String = "system"

    @State private var discoverable: Bool = true
    @State private var showDistance: Bool = true
    @State private var showActivity: Bool = true
    @State private var dmFriendsOnly: Bool = false
    @State private var cloudChatSync: Bool = true
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Giao diện & Chế độ sáng/tối")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Tùy chỉnh giao diện theo sở thích của bạn: Sáng, Tối hoặc tự động theo cài đặt iOS.")
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()

                        Picker("Chế độ hiển thị", selection: $appearanceMode) {
                            Text("Hệ thống").tag("system")
                            Text("Chế độ tối").tag("dark")
                            Text("Chế độ sáng").tag("light")
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surface))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quyền riêng tư & Định vị")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Quản lý thông tin hiển thị với người dùng khác và mức độ khám phá tài khoản của bạn trên Kinnect.")
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        Toggle(isOn: $discoverable) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cho phép tìm thấy tôi")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Xuất hiện trong Khám phá và danh sách người dùng Quanh đây.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $showDistance) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hiển thị khoảng cách")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Chỉ hiển thị khoảng cách gần đúng để bảo vệ vị trí chính xác của bạn.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $showActivity) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trạng thái hoạt động")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Hiển thị chấm xanh khi bạn đang trực tuyến trên Kinnect.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $dmFriendsOnly) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chỉ nhận tin nhắn từ bạn bè")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Người lạ cần gửi lời mời kết bạn trước khi nhắn tin trực tiếp.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)

                        Divider().background(KinnectTheme.surfaceElevated)

                        Toggle(isOn: $cloudChatSync) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Đồng bộ tin nhắn đám mây")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Text("Lưu trữ và đồng bộ lịch sử hội thoại an toàn qua máy chủ Kinnect.")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        .tint(KinnectTheme.accentBright)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusXL).fill(KinnectTheme.surface))
                }
                .padding(20)
                .padding(.bottom, 8)
            }
            .background(KinnectTheme.background)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await saveSettings() }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Lưu cài đặt")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(KinnectTheme.primaryGradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                }
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(KinnectTheme.background)
            }
            .navigationTitle("Quyền riêng tư")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSettings()
            }
        }
    }

    private func loadSettings() async {
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            self.discoverable = true
            self.showDistance = true
            self.showActivity = true
            self.dmFriendsOnly = false
            self.cloudChatSync = true
            return
        }
        #endif
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me") {
            let user = (res["user"] as? [String: Any]) ?? res
            self.discoverable = (user["discoverable"] as? Bool) ?? ((user["discoverable"] as? Int) == 1)
            self.showDistance = (user["showDistance"] as? Bool) ?? ((user["show_distance"] as? Int) == 1)
            self.showActivity = (user["showActivity"] as? Bool) ?? ((user["show_activity"] as? Int) == 1)
            let dm = user["dmMode"] as? String ?? user["dm_mode"] as? String ?? "everyone"
            self.dmFriendsOnly = (dm == "friends")
            self.cloudChatSync = (user["cloudChatSync"] as? Bool) ?? ((user["cloud_chat_sync"] as? Int) == 1)
        }
    }

    private func saveSettings() async {
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            appState.showToast("Đã cập nhật quyền riêng tư.")
            dismiss()
            return
        }
        #endif
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me",
                method: "PATCH",
                body: [
                    "discoverable": discoverable,
                    "showDistance": showDistance,
                    "showActivity": showActivity,
                    "dmMode": dmFriendsOnly ? "friends" : "everyone",
                    "cloudChatSync": cloudChatSync
                ]
            )
            if var user = appState.currentUser {
                user.discoverable = discoverable
                user.showDistance = showDistance
                user.showActivity = showActivity
                user.cloudChatSync = cloudChatSync
                appState.currentUser = user
            }
            if showActivity {
                appState.reportActiveStatus(force: true)
            }
            appState.showToast("Đã cập nhật quyền riêng tư.")
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct SupportContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var contactText = ""
    @State private var noteText = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Trung tâm Hỗ trợ & Trợ giúp")
                            .font(.headline)
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text("Gửi phản hồi, báo cáo sự cố hoặc yêu cầu trợ giúp kỹ thuật từ đội ngũ phát triển Kinnect.")
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Thông tin liên hệ (Email hoặc SĐT)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        TextField("nhap@email.com hoặc 09xxxxxxxx", text: $contactText)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mô tả yêu cầu / Báo cáo sự cố")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textSecondary)
                        TextEditor(text: $noteText)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                    }

                    Button {
                        Task { await submitSupport() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            }
                            Text("Gửi yêu cầu hỗ trợ")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(canSubmit ? KinnectTheme.primaryGradient : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD))
                    }
                    .disabled(!canSubmit || isSubmitting)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Thông tin hữu ích")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)
                        Link(destination: URL(string: "https://kinnect.io.vn/privacy")!) {
                            HStack {
                                Text("Chính sách quyền riêng tư")
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.accentBright)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                        Link(destination: URL(string: "https://kinnect.io.vn/community")!) {
                            HStack {
                                Text("Quy tắc cộng đồng")
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.accentBright)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surface))
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .background(KinnectTheme.background)
            .navigationTitle("Hỗ trợ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                #if DEBUG
                if UIReviewFixture.activeScreen != nil {
                    contactText = "minhanh@kinnect.vn"
                    noteText = "Cần hỗ trợ hướng dẫn kích hoạt gói Studio Pro trên thiết bị mới."
                }
                #endif
            }
        }
    }

    private var canSubmit: Bool {
        !contactText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitSupport() async {
        #if DEBUG
        if UIReviewFixture.activeScreen != nil {
            appState.showToast("Đã gửi yêu cầu hỗ trợ thành công.")
            dismiss()
            return
        }
        #endif
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/support/request",
                method: "POST",
                body: [
                    "contact": contactText,
                    "note": noteText
                ]
            )
            appState.showToast("Đã gửi yêu cầu hỗ trợ thành công.")
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct UserConnectionsSheet: View {
    let userId: String
    let kind: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var users: [KinnectUser] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var filteredUsers: [KinnectUser] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return users
        }
        return users.filter { $0.name.lowercased().contains(q) || $0.handle.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(KinnectTheme.textSecondary)
                    TextField("Tìm kiếm...", text: $searchText)
                        .font(KinnectTheme.body)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                }
                .padding(10)
                .background(KinnectTheme.surface)
                .cornerRadius(KinnectTheme.radiusSM)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filteredUsers.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: kind == "followers" ? "person.2" : "person.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(KinnectTheme.textTertiary)
                        Text(kind == "followers" ? "Chưa có người theo dõi" : "Chưa theo dõi ai")
                            .font(KinnectTheme.body)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredUsers) { u in
                            HStack(spacing: 12) {
                                KinnectAvatarView(user: u, size: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(u.name)
                                        .font(KinnectTheme.bodyBold)
                                        .foregroundColor(KinnectTheme.textPrimary)
                                    if !u.handle.isEmpty {
                                        Text("@\(u.handle)")
                                            .font(.system(size: 13))
                                            .foregroundColor(KinnectTheme.textSecondary)
                                    }
                                }

                                Spacer()

                                if !u.city.isEmpty {
                                    Text(u.city)
                                        .font(.system(size: 12))
                                        .foregroundColor(KinnectTheme.textTertiary)
                                }
                            }
                            .listRowBackground(KinnectTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(KinnectTheme.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadConnections()
            }
        }
    }

    private func loadConnections() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = "/api/users/\(userId)/\(kind)"
            let res = try await KinnectAPIClient.shared.requestJSON(endpoint)
            let rawList = (res["users"] as? [[String: Any]]) ?? (res[kind] as? [[String: Any]]) ?? []
            users = rawList.compactMap { KinnectUser.from($0) }
        } catch {
            // fallback
        }
    }
}
