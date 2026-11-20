import PhotosUI
import SwiftUI
import UIKit

struct PublicAlbumManageSheet: View {
    let posts: [PostItem]
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var captionText = ""
    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Đăng ảnh công khai mới") {
                    TextField("Chú thích cho ảnh...", text: $captionText)
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack(spacing: 8) {
                            KinnectIcon(glyph: .photo, size: 20, tint: KinnectTheme.accentBright)
                            Text(isUploading ? "Đang tải ảnh lên..." : "Chọn ảnh từ thư viện & Đăng")
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.accentBright)
                        }
                    }
                    .disabled(isUploading)
                    .onChange(of: selectedPhotoItem) { item in
                        guard let item else { return }
                        Task { await uploadPublicPhoto(item) }
                    }
                }

                Section("Danh sách bài viết & ảnh công khai (\(posts.count))") {
                    if posts.isEmpty {
                        Text("Chưa có ảnh công khai nào.")
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(posts) { post in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(post.text.isEmpty ? "Ảnh công khai" : post.text)
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textPrimary)
                                if !post.imageUrl.isEmpty {
                                    KinnectMediaTile(path: post.imageUrl, kind: post.mediaKind)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Ảnh công khai")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private func uploadPublicPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = uiImg.jpegData(compressionQuality: 0.75) else { return }
        isUploading = true
        defer { isUploading = false }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/posts",
                method: "POST",
                body: KinnectWriteBody.post(
                    text: captionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    mediaDataURL: dataURL
                ),
                requestId: "pub_photo_\(UUID().uuidString)"
            )
            captionText = ""
            appState.showToast("Đã đăng ảnh công khai mới!")
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct PrivateAlbumManageSheet: View {
    @Binding var photos: [PrivatePhotoItem]
    @Binding var requests: [PrivateAccessRequestItem]
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Tải ảnh lên Album riêng tư (\(photos.count)/24)") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack(spacing: 8) {
                            KinnectIcon(glyph: .lock, size: 20, tint: KinnectTheme.warning)
                            Text(isUploading ? "Đang mã hóa & tải lên..." : "Thêm ảnh riêng tư mới (< 4MB)")
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.warning)
                        }
                    }
                    .disabled(isUploading || photos.count >= 24)
                    .onChange(of: selectedItem) { item in
                        guard let item else { return }
                        Task { await uploadPrivatePhoto(item) }
                    }
                }

                Section("Yêu cầu & Quyền truy cập (\(requests.count))") {
                    if requests.isEmpty {
                        Text("Chưa có yêu cầu xem Album riêng tư nào.")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(requests) { req in
                            HStack(spacing: 10) {
                                KinnectAvatarView(
                                    name: req.user.name,
                                    avatarURL: req.user.avatarUrl,
                                    colorHex: req.user.avatarColor,
                                    size: 36
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.user.name)
                                        .font(.subheadline.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text(req.status == "granted" ? "Đã cấp quyền xem" : "Đang chờ bạn duyệt")
                                        .font(.caption2)
                                        .foregroundColor(req.status == "granted" ? KinnectTheme.online : KinnectTheme.warning)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if req.status == "pending" {
                                    Button("Duyệt") {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "grant") }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(KinnectTheme.accent)
                                    .controlSize(.small)

                                    Button("Từ chối", role: .destructive) {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "deny") }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("Thu hồi", role: .destructive) {
                                        Task { await handleAccessAction(viewerId: req.user.id, action: "revoke") }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("Ảnh trong Album riêng tư (\(photos.count))") {
                    if photos.isEmpty {
                        Text("Album riêng tư hiện chưa có ảnh.")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    } else {
                        ForEach(photos) { photo in
                            HStack(alignment: .center, spacing: 12) {
                                // Fixed-size, clipped thumbnail so the image can never extend under the text column.
                                KinnectRemoteImageView(rawURL: photo.url, contentMode: .fill, cornerRadius: KinnectTheme.radiusXS, maxHeight: 64)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: KinnectTheme.radiusXS, style: .continuous))
                                    .contentShape(Rectangle())
                                    .layoutPriority(0)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Ảnh bảo mật")
                                        .font(.subheadline.bold())
                                        .foregroundColor(KinnectTheme.textPrimary)
                                        .lineLimit(1)
                                    Text("Chỉ người được duyệt mới xem được")
                                        .font(.caption2)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                                Button(role: .destructive) {
                                    Task { await deletePrivatePhoto(photo.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(KinnectTheme.danger)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Xóa ảnh bảo mật")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Album riêng tư")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
            .task {
                if photos.isEmpty, let uid = appState.currentUser?.id {
                    if let privRes = try? await KinnectAPIClient.shared.requestJSON("/api/users/\(uid)/private") {
                        let pList = privRes["photos"] as? [[String: Any]] ?? []
                        photos = pList.map(PrivatePhotoItem.from)
                    }
                }
                if requests.isEmpty {
                    if let reqRes = try? await KinnectAPIClient.shared.requestJSON("/api/me/private/requests") {
                        let rList = reqRes["requests"] as? [[String: Any]] ?? []
                        requests = rList.map(PrivateAccessRequestItem.from)
                    }
                }
            }
        }
    }

    private func uploadPrivatePhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImg = UIImage(data: data),
              let jpeg = uiImg.jpegData(compressionQuality: 0.72) else { return }
        isUploading = true
        defer { isUploading = false }
        let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/private-photos",
                method: "POST",
                body: ["data": dataURL],
                requestId: "priv_up_\(UUID().uuidString)"
            )
            if let list = res["photos"] as? [[String: Any]] {
                photos = list.map(PrivatePhotoItem.from)
            }
            appState.showToast("Đã thêm ảnh vào Album riêng tư.")
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func deletePrivatePhoto(_ photoId: String) async {
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/private-photos/\(photoId)",
                method: "DELETE",
                body: [:],
                requestId: "priv_del_\(photoId)"
            )
            if let list = res["photos"] as? [[String: Any]] {
                photos = list.map(PrivatePhotoItem.from)
            }
            appState.showToast("Đã xóa ảnh khỏi Album riêng tư.")
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func handleAccessAction(viewerId: String, action: String) async {
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/private/requests/\(viewerId)",
                method: "POST",
                body: ["action": action],
                requestId: "priv_act_\(viewerId)_\(action)"
            )
            let msg = action == "grant" ? "Đã cấp quyền xem Album riêng tư." : (action == "deny" ? "Đã từ chối yêu cầu." : "Đã thu hồi quyền xem.")
            appState.showToast(msg)
            onRefresh()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}
