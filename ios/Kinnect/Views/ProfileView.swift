import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    let onOpenWallet: () -> Void
    let onOpenFriends: () -> Void

    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var pushKit = PushKitManager.shared

    enum ProfileTab: String, CaseIterable {
        case about = "Giới thiệu"
        case posts = "Bài viết"
        case albums = "Album ảnh"
        case videos = "Video"
    }

    @State private var selectedTab: ProfileTab = .about
    @State private var showEditProfileSheet = false
    @State private var showSessionsSheet = false
    @State private var showPasswordSheet = false
    @State private var showBlocksSheet = false
    @State private var showDeleteAccountSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let user = appState.currentUser {
                    // 1. Cover & Avatar Card with Handle & Stats (Parity Android 1.2.12 build 118)
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
                                    Text("@\(user.username)")
                                        .font(.subheadline)
                                        .foregroundColor(KinnectTheme.accentBright)
                                }
                                .padding(.bottom, 6)
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, -20)
                        }
                        .padding(.bottom, 22)

                        // Prominent "Chỉnh sửa hồ sơ" Button (Matching Android 1.2.12 MainActivity bounds 413,771 -> 705,818)
                        Button {
                            showEditProfileSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                KinnectIcon(glyph: .edit, size: 18, tint: KinnectTheme.accentBright)
                                Text("Chỉnh sửa hồ sơ")
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        }
                        .padding(.horizontal, 14)

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

                    // 2. 4 Profile Tabs: Giới thiệu | Bài viết | Album ảnh | Video (Exact Android 1.2.12 Parity)
                    Picker("Mục hồ sơ", selection: $selectedTab) {
                        ForEach(ProfileTab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    // 3. Tab Content
                    switch selectedTab {
                    case .about:
                        aboutTabContent(user: user)
                    case .posts:
                        postsTabContent(user: user)
                    case .albums:
                        albumsTabContent(user: user)
                    case .videos:
                        videosTabContent(user: user)
                    }
                }
            }
            .padding(14)
        }
        .background(KinnectTheme.background)
        .navigationTitle("Hồ sơ cá nhân")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshMe()
        }
        .sheet(isPresented: $showEditProfileSheet) {
            EditProfileSheet(onSaved: {
                Task { await refreshMe() }
            })
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

    // MARK: - Tab Contents
    private func aboutTabContent(user: KinnectUser) -> some View {
        VStack(spacing: 14) {
            // Bio & Details Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Giới thiệu")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Text(user.isPrivate ? "Riêng tư" : "Công khai")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(user.isPrivate ? KinnectTheme.warning.opacity(0.2) : KinnectTheme.online.opacity(0.2)))
                        .foregroundColor(user.isPrivate ? KinnectTheme.warning : KinnectTheme.online)
                }

                if !user.bio.isEmpty {
                    Text(user.bio)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                        .kinnectMultiline()
                } else {
                    Text("Chưa có thông tin công khai. Cập nhật hồ sơ để mọi người hiểu bạn hơn.")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                }

                if !user.locationName.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(user.locationName)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(KinnectTheme.textSecondary)
                    Text("Tham gia Kinnect từ 11/2026")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
            }
            .kinnectCard()

            // Quick Actions & Security
            VStack(spacing: 10) {
                actionRow(glyph: .wallet, title: "Ví thử nghiệm & Cửa hàng", color: KinnectTheme.warning, action: onOpenWallet)
                actionRow(glyph: .friends, title: "Danh sách Bạn bè & Lời mời", color: KinnectTheme.accentBright, action: onOpenFriends)
                actionRow(glyph: .shield, title: "Quản lý phiên đăng nhập", color: .cyan) {
                    showSessionsSheet = true
                }
                actionRow(glyph: .lock, title: "Đổi mật khẩu", color: .green) {
                    showPasswordSheet = true
                }
                actionRow(glyph: .block, title: "Danh sách người dùng đã chặn", color: .orange) {
                    showBlocksSheet = true
                }
            }
            .kinnectCard()

            // PushKit / Native Diagnostic Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    KinnectIcon(glyph: .phone, size: 20, selected: true, tint: KinnectTheme.online)
                    Text("Trạng thái Cuộc gọi Native & PushKit")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                }
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

            // Logout & Delete Card
            VStack(spacing: 10) {
                Button {
                    Task { await appState.logout() }
                } label: {
                    HStack(spacing: 8) {
                        KinnectIcon(glyph: .logout, size: 20, tint: .white)
                        Text("Đăng xuất (Xóa Keychain & Cache)")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(.white)
                }

                Button(role: .destructive) {
                    showDeleteAccountSheet = true
                } label: {
                    Label("Xóa vĩnh viễn tài khoản Kinnect", systemImage: "trash.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.danger.opacity(0.18)))
                        .foregroundColor(KinnectTheme.danger)
                }
            }
            .kinnectCard()
        }
    }

    private func postsTabContent(user: KinnectUser) -> some View {
        VStack(spacing: 12) {
            let myPosts = appState.feedPosts.filter { $0.author.id == user.id }
            if myPosts.isEmpty {
                VStack(spacing: 8) {
                    KinnectIcon(glyph: .feed, size: 36, tint: KinnectTheme.textSecondary)
                    Text("Chưa có bài viết nào")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Những bài viết bạn chia sẻ trên Bảng tin sẽ xuất hiện tại đây.")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .kinnectCard()
            } else {
                ForEach(myPosts) { post in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.text)
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textPrimary)
                            .kinnectMultiline()
                        if !post.imageUrl.isEmpty {
                            KinnectRemoteImageView(rawURL: post.imageUrl, contentMode: .fill, cornerRadius: 10, maxHeight: 180)
                        }
                        Text(formatRelativeDate(post.createdAt))
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .kinnectCard()
                }
            }
        }
    }

    private func albumsTabContent(user: KinnectUser) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            // Public Album Card
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(height: 120)
                    .overlay(
                        KinnectIcon(glyph: .photo, size: 32, tint: KinnectTheme.accentBright)
                    )
                Text("Ảnh công khai")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text("Công khai cho tất cả mọi người")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(10)
            .kinnectCard()

            // Private Album Card (with secure lock badge)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(height: 120)
                    .overlay(
                        VStack(spacing: 6) {
                            KinnectIcon(glyph: .lock, size: 30, tint: KinnectTheme.warning)
                            Text("Bảo mật PIN/FaceID")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(KinnectTheme.warning)
                        }
                    )
                Text("Album riêng tư")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text("Chỉ bạn và bạn bè được cấp quyền")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(10)
            .kinnectCard()
        }
    }

    private func videosTabContent(user: KinnectUser) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(0..<6) { i in
                RoundedRectangle(cornerRadius: 10)
                    .fill(KinnectTheme.surfaceElevated)
                    .frame(height: 150)
                    .overlay(
                        VStack(spacing: 4) {
                            KinnectIcon(glyph: .video, size: 24, tint: KinnectTheme.accentBright)
                            Text("Shorts #\(i + 1)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        }
                    )
            }
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

    private func actionRow(glyph: KinnectGlyph, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                KinnectIcon(glyph: glyph, size: 22, tint: color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .kinnectMultiline()
                Spacer()
                KinnectIcon(glyph: .chevronRight, size: 18, tint: KinnectTheme.textSecondary)
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private func refreshMe() async {
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/me"),
           let userDict = res["user"] as? [String: Any] {
            let user = KinnectUser.from(userDict)
            appState.applyAuthenticatedUser(user, rawDict: userDict)
        }
    }
}

// MARK: - Dedicated Edit Profile Sheet
struct EditProfileSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var name = ""
    @State private var bio = ""
    @State private var locationName = ""
    @State private var isPrivate = false
    @State private var isSaving = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var selectedCoverItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Hình ảnh đại diện") {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                            HStack(spacing: 6) {
                                KinnectIcon(glyph: .profile, size: 18, tint: KinnectTheme.accentBright)
                                Text("Đổi Avatar")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                        .onChange(of: selectedAvatarItem) { item in
                            guard let item else { return }
                            Task { await uploadImage(item: item, endpoint: "/api/me/avatar", field: "avatarDataUrl") }
                        }

                        PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                            HStack(spacing: 6) {
                                KinnectIcon(glyph: .photo, size: 18, tint: KinnectTheme.accentBright)
                                Text("Đổi Ảnh bìa")
                                    .font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                        .onChange(of: selectedCoverItem) { item in
                            guard let item else { return }
                            Task { await uploadImage(item: item, endpoint: "/api/me/cover", field: "coverDataUrl") }
                        }
                    }
                }

                Section("Thông tin cá nhân") {
                    TextField("Tên hiển thị", text: $name)
                    TextField("Tiểu sử (Bio)", text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Thành phố / Khu vực", text: $locationName)
                    Toggle("Tài khoản riêng tư", isOn: $isPrivate)
                        .tint(KinnectTheme.accentBright)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Chỉnh sửa hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task { await saveProfile() }
                    }
                    .bold()
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if let u = appState.currentUser {
                    name = u.name
                    bio = u.bio
                    locationName = u.locationName
                    isPrivate = u.isPrivate
                }
            }
        }
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }
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
            onSaved()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func uploadImage(item: PhotosPickerItem, endpoint: String, field: String) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = uiImg.jpegData(compressionQuality: 0.72) else {
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
            appState.showToast("Đã cập nhật hình ảnh hồ sơ.")
            onSaved()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
