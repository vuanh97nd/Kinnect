import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    let onOpenWallet: () -> Void
    let onOpenFriends: () -> Void

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var pushKit = PushKitManager.shared

    @State private var name = ""
    @State private var bio = ""
    @State private var locationName = ""
    @State private var isPrivate = false
    @State private var isSavingProfile = false

    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?

    @State private var showSessionsSheet = false
    @State private var showPasswordSheet = false
    @State private var showBlocksSheet = false
    @State private var showDeleteAccountSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let user = appState.currentUser {
                    // Cover & Avatar Card
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            if !user.coverUrl.isEmpty {
                                KinnectRemoteImageView(
                                    rawURL: user.coverUrl,
                                    contentMode: .fill,
                                    cornerRadius: 16,
                                    maxHeight: 140
                                )
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(KinnectTheme.primaryGradient)
                                    .frame(height: 130)
                            }

                            HStack(alignment: .bottom, spacing: 12) {
                                KinnectAvatarView(
                                    name: user.name,
                                    avatarURL: user.avatarUrl,
                                    colorHex: user.avatarColor,
                                    size: 76,
                                    isOnline: true
                                )
                                .overlay(Circle().stroke(KinnectTheme.surface, lineWidth: 3))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name)
                                        .font(.title3.bold())
                                        .foregroundColor(.white)
                                        .kinnectMultiline()
                                    if !user.handle.isEmpty {
                                        Text("@\(user.handle)")
                                            .font(.caption)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(12)
                        }

                        // Upload Avatar & Cover pickers
                        HStack(spacing: 10) {
                            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                                Label("Đổi Avatar", systemImage: "person.crop.circle.badge.plus")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                            .onChange(of: selectedAvatarItem) { item in
                                guard let item else { return }
                                Task { await uploadImage(item: item, endpoint: "/api/me/avatar", field: "avatarDataUrl") }
                            }

                            PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                                Label("Đổi Ảnh bìa", systemImage: "photo.badge.plus")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                            .onChange(of: selectedCoverItem) { item in
                                guard let item else { return }
                                Task { await uploadImage(item: item, endpoint: "/api/me/cover", field: "coverDataUrl") }
                            }
                        }

                        // Stats bar
                        HStack {
                            statColumn(count: user.friendsCount, label: "Bạn bè")
                            Divider().frame(height: 28).background(KinnectTheme.border)
                            statColumn(count: user.followersCount, label: "Người theo dõi")
                            Divider().frame(height: 28).background(KinnectTheme.border)
                            statColumn(count: user.followingCount, label: "Đang theo dõi")
                        }
                        .padding(.top, 4)
                    }
                    .kinnectCard()

                    // Edit Profile Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Chỉnh sửa hồ sơ")
                            .font(.headline)
                            .foregroundColor(.white)

                        TextField("Tên hiển thị", text: $name)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(.white)

                        TextField("Tiểu sử (Bio)", text: $bio, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(.white)

                        TextField("Thành phố / Khu vực", text: $locationName)
                            .padding(11)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(.white)

                        Toggle("Tài khoản riêng tư", isOn: $isPrivate)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .tint(KinnectTheme.accentBright)

                        Button {
                            Task { await saveProfile() }
                        } label: {
                            HStack {
                                Spacer()
                                if isSavingProfile {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Lưu thay đổi")
                                        .font(.subheadline.bold())
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .background(KinnectTheme.primaryGradient)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isSavingProfile)
                    }
                    .kinnectCard()

                    // Quick Actions & Security
                    VStack(spacing: 10) {
                        actionRow(icon: "creditcard.fill", title: "Ví thử nghiệm & Cửa hàng", color: KinnectTheme.warning, action: onOpenWallet)
                        actionRow(icon: "person.2.fill", title: "Danh sách Bạn bè & Lời mời", color: KinnectTheme.accentBright, action: onOpenFriends)
                        actionRow(icon: "laptopcomputer.and.iphone", title: "Quản lý phiên đăng nhập", color: .cyan) {
                            showSessionsSheet = true
                        }
                        actionRow(icon: "key.fill", title: "Đổi mật khẩu", color: .green) {
                            showPasswordSheet = true
                        }
                        actionRow(icon: "hand.raised.fill", title: "Danh sách người dùng đã chặn", color: .orange) {
                            showBlocksSheet = true
                        }
                    }
                    .kinnectCard()

                    // Native PushKit / CallKit / Build Diagnostic Card
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Trạng thái Cuộc gọi Native & PushKit", systemImage: "phone.badge.waveform.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text(pushKit.voipRegistrationStatus)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                        Text("Phiên bản: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.12") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "118"))")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .kinnectCard()

                    // Logout & Permanent Account Deletion
                    VStack(spacing: 10) {
                        Button {
                            Task { await appState.logout() }
                        } label: {
                            Label("Đăng xuất (Xóa Keychain & Cache)", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(.white)
                        }

                        Button(role: .destructive) {
                            showDeleteAccountSheet = true
                        } label: {
                            Label("Xóa vĩnh viễn tài khoản Kinnect", systemImage: "trash.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.danger.opacity(0.18)))
                                .foregroundColor(KinnectTheme.danger)
                        }
                    }
                    .kinnectCard()
                }
            }
            .padding(14)
        }
        .background(KinnectTheme.background)
        .navigationTitle("Hồ sơ cá nhân")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            syncFieldsFromUser()
            await refreshMe()
        }
        .sheet(isPresented: $showSessionsSheet) {
            ActiveSessionsSheet()
        }
        .sheet(isPresented: $showPasswordSheet) {
            ChangePasswordSheet()
        }
        .sheet(isPresented: $showBlocksSheet) {
            BlockedUsersSheet()
        }
        .sheet(isPresented: $showDeleteAccountSheet) {
            DeleteAccountConfirmationSheet()
        }
    }

    private func statColumn(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline.bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(KinnectTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionRow(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .kinnectMultiline()
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(.vertical, 6)
        }
    }

    private func syncFieldsFromUser() {
        guard let u = appState.currentUser else { return }
        name = u.name
        bio = u.bio
        locationName = u.locationName
        isPrivate = u.isPrivate
    }

    private func refreshMe() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me"),
           let userDict = res["user"] as? [String: Any] {
            let user = KinnectUser.from(userDict)
            appState.applyAuthenticatedUser(user, rawDict: userDict)
            syncFieldsFromUser()
        }
    }

    private func saveProfile() async {
        isSavingProfile = true
        defer { isSavingProfile = false }
        let reqId = "patch_me_\(Int(Date().timeIntervalSince1970))"
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me",
                method: "PATCH",
                body: [
                    "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                    "bio": bio.trimmingCharacters(in: .whitespacesAndNewlines),
                    "locationName": locationName.trimmingCharacters(in: .whitespacesAndNewlines),
                    "isPrivate": isPrivate
                ],
                requestId: reqId
            )
            if let userDict = res["user"] as? [String: Any] {
                appState.applyAuthenticatedUser(KinnectUser.from(userDict), rawDict: userDict)
            }
            appState.showToast("Đã cập nhật hồ sơ cá nhân.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func uploadImage(item: PhotosPickerItem, endpoint: String, field: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = compressUnderOneMegabyte(uiImg) else {
            appState.showToast("Không thể xử lý ảnh đã chọn.")
            return
        }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        let reqId = "upload_\(field)_\(Int(Date().timeIntervalSince1970))"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                endpoint,
                method: "POST",
                body: [field: dataURL],
                requestId: reqId
            )
            await refreshMe()
            appState.showToast("Đã cập nhật hình ảnh hồ sơ.")
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func compressUnderOneMegabyte(_ image: UIImage) -> Data? {
        var quality: CGFloat = 0.75
        while quality >= 0.25 {
            if let data = image.jpegData(compressionQuality: quality), data.count < 900_000 {
                return data
            }
            quality -= 0.15
        }
        return image.jpegData(compressionQuality: 0.2)
    }
}

struct ActiveSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var sessions: [[String: Any]] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(sessions.enumerated()), id: \.offset) { _, s in
                    let sid = s["id"] as? String ?? ""
                    let ua = s["userAgent"] as? String ?? "Thiết bị Kinnect"
                    let current = s["current"] as? Bool ?? false
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ua)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .kinnectMultiline()
                            Text(current ? "Phiên hiện tại trên thiết bị này" : "Phiên hoạt động")
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
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                await loadSessions()
            }
        }
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
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Bảo mật mật khẩu") {
                    SecureField("Mật khẩu hiện tại", text: $currentPassword)
                    SecureField("Mật khẩu mới (tối thiểu 6 ký tự)", text: $newPassword)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Đổi mật khẩu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task { await updatePassword() }
                    }
                    .disabled(isSubmitting || newPassword.count < 6)
                }
            }
        }
    }

    private func updatePassword() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/password",
                method: "POST",
                body: [
                    "currentPassword": currentPassword,
                    "newPassword": newPassword
                ]
            )
            appState.showToast("Đã đổi mật khẩu thành công.")
            dismiss()
        } catch {
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
                        .foregroundColor(KinnectTheme.textSecondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(blockedUsers) { u in
                    HStack {
                        KinnectAvatarView(name: u.name, avatarURL: u.avatarUrl, colorHex: u.avatarColor, size: 38)
                        Text(u.name)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Bỏ chặn") {
                            Task {
                                await appState.unblockUser(userId: u.id)
                                await loadBlocks()
                            }
                        }
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                    }
                    .listRowBackground(KinnectTheme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Người dùng đã chặn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                await loadBlocks()
            }
        }
    }

    private func loadBlocks() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/blocks") {
            let list = res["blocks"] as? [[String: Any]] ?? []
            self.blockedUsers = list.map { entry in
                if let u = entry["user"] as? [String: Any] {
                    return KinnectUser.from(u)
                }
                return KinnectUser.from(entry)
            }
        }
    }
}

struct DeleteAccountConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var confirmPhrase = ""
    @State private var password = ""
    @State private var requiredPhrase = "XOA TAI KHOAN"
    @State private var summaryInfo: String = "Đang kiểm tra dữ liệu tài khoản..."
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
                        Text("Nhập chính xác cụm từ xác nhận: \(requiredPhrase)")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        TextField(requiredPhrase, text: $confirmPhrase)
                            .textInputAutocapitalization(.characters)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nhập mật khẩu hiện tại")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        SecureField("Mật khẩu của bạn", text: $password)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(.white)
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
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isDeleting || confirmPhrase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != requiredPhrase)
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
                    if let phrase = res["confirmText"] as? String, !phrase.isEmpty {
                        self.requiredPhrase = phrase
                    }
                    if let summary = res["summary"] as? [String: Any] {
                        let posts = summary["posts"] as? Int ?? 0
                        let messages = summary["messages"] as? Int ?? 0
                        let friends = summary["friends"] as? Int ?? 0
                        self.summaryInfo = "Dữ liệu sẽ bị xóa vĩnh viễn: \(posts) bài viết, \(messages) tin nhắn, \(friends) liên kết bạn bè."
                    }
                }
            }
        }
    }

    private func performAccountDeletion() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/account-deletion",
                method: "DELETE",
                body: [
                    "confirmText": confirmPhrase.trimmingCharacters(in: .whitespacesAndNewlines),
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

