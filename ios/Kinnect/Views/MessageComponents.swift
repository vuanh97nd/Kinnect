import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

func kinnectMessageIsoString(from anyVal: Any?) -> String {
    if let s = anyVal as? String, !s.isEmpty {
        return s
    }
    if let n = anyVal as? NSNumber {
        let ms = n.doubleValue
        let sec = ms > 10_000_000_000 ? (ms / 1000.0) : ms
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: sec))
    }
    return ""
}

func kinnectMimeTypeForExt(_ ext: String) -> String {
    let lower = ext.lowercased()
    switch lower {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "pdf": return "application/pdf"
    case "doc", "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    case "xls", "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    case "zip": return "application/zip"
    case "rar": return "application/x-rar-compressed"
    case "mp3": return "audio/mpeg"
    case "m4a": return "audio/mp4"
    case "wav": return "audio/wav"
    case "mp4": return "video/mp4"
    case "txt": return "text/plain"
    default: return "application/octet-stream"
    }
}

struct MessageBubbleShape: Shape {
    let isMine: Bool

    func path(in rect: CGRect) -> Path {
        let corners: UIRectCorner = isMine
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: 18, height: 18)
        )
        return Path(path.cgPath)
    }
}

struct ChatAttachmentBubbleView: View {
    let fileName: String
    let fileUrl: String
    let isMine: Bool

    private var fileIconName: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.richtext.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "zip", "rar", "tar", "gz": return "archivebox.fill"
        case "mp3", "m4a", "wav", "aac": return "music.note"
        case "mp4", "mov", "avi": return "video.fill"
        default: return "doc.fill"
        }
    }

    private var fileIconColor: Color {
        KinnectTheme.attachmentColor(forExtension: (fileName as NSString).pathExtension)
    }

    var body: some View {
        Button {
            openOrDownloadFile()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isMine ? Color.white.opacity(0.2) : fileIconColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: fileIconName)
                        .font(KinnectTheme.scaled(20))
                        .foregroundColor(isMine ? .white : fileIconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName.isEmpty ? "Tệp đính kèm" : fileName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isMine ? .white : KinnectTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("Tệp đính kèm • Chạm để mở")
                        .font(.caption2)
                        .foregroundColor(isMine ? Color.white.opacity(0.8) : KinnectTheme.textSecondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.down.circle.fill")
                    .font(KinnectTheme.scaled(20))
                    .foregroundColor(isMine ? Color.white.opacity(0.9) : KinnectTheme.accentBright)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: KinnectTheme.radiusLG)
                    .fill(isMine ? AnyShapeStyle(Color.white.opacity(0.16)) : AnyShapeStyle(KinnectTheme.surfaceElevated))
                    .overlay(
                        RoundedRectangle(cornerRadius: KinnectTheme.radiusLG)
                            .stroke(isMine ? Color.white.opacity(0.3) : KinnectTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func openOrDownloadFile() {
        guard !fileUrl.isEmpty else { return }
        if fileUrl.hasPrefix("data:") {
            if let commaIndex = fileUrl.firstIndex(of: ",") {
                let base64 = String(fileUrl[fileUrl.index(after: commaIndex)...])
                if let data = Data(base64Encoded: base64) {
                    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(fileName.isEmpty ? "attachment.dat" : fileName)
                    try? data.write(to: temp)
                    presentShareSheet(for: temp)
                    return
                }
            }
        }
        let fullURLStr = fileUrl.hasPrefix("http") ? fileUrl : "\(KinnectAPIClient.shared.baseURL)\(fileUrl)"
        if let targetURL = URL(string: fullURLStr) {
            UIApplication.shared.open(targetURL)
        }
    }

    private func presentShareSheet(for fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
}

struct NewDirectChatPickerSheet: View {
    let onSelectPeer: (KinnectUser) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var friends: [KinnectUser] = []
    @State private var searchQuery = ""
    @State private var isLoading = false

    private var filteredFriends: [KinnectUser] {
        if searchQuery.isEmpty { return friends }
        let q = searchQuery.lowercased()
        return friends.filter { $0.name.lowercased().contains(q) || $0.handle.lowercased().contains(q) }
    }

    private var onlineFriends: [KinnectUser] {
        filteredFriends.filter { ($0.isActive && $0.showActivity) || appState.onlineUserIds.contains($0.id) }
    }

    private var offlineFriends: [KinnectUser] {
        filteredFriends.filter { !(($0.isActive && $0.showActivity) || appState.onlineUserIds.contains($0.id)) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(KinnectTheme.textSecondary)
                    TextField("Tìm bạn bè để nhắn tin…", text: $searchQuery)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(KinnectTheme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: KinnectTheme.radiusMD).fill(KinnectTheme.surfaceElevated))
                .padding(.horizontal, 16)

                if isLoading {
                    ProgressView().padding(.vertical, 30)
                    Spacer()
                } else if filteredFriends.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 36))
                            .foregroundColor(KinnectTheme.textSecondary)
                        Text(searchQuery.isEmpty ? "Chưa có bạn bè nào để nhắn tin" : "Không tìm thấy bạn bè phù hợp")
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                } else {
                    List {
                        if !onlineFriends.isEmpty {
                            Section {
                                ForEach(onlineFriends) { friend in
                                    friendPickerRow(friend)
                                }
                            } header: {
                                Text("Đang trực tuyến (\(onlineFriends.count))")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.onlinePresence)
                            }
                        }

                        if !offlineFriends.isEmpty {
                            Section {
                                ForEach(offlineFriends) { friend in
                                    friendPickerRow(friend)
                                }
                            } header: {
                                Text("Ngoại tuyến (\(offlineFriends.count))")
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(KinnectTheme.background)
                }
            }
            .navigationTitle("Tin nhắn mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                isLoading = true
                defer { isLoading = false }
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
                    let list = (res["users"] as? [[String: Any]]) ?? (res["friends"] as? [[String: Any]]) ?? []
                    self.friends = list.map(KinnectUser.from)
                }
            }
        }
    }

    private func friendPickerRow(_ friend: KinnectUser) -> some View {
        Button {
            dismiss()
            onSelectPeer(friend)
        } label: {
            HStack(spacing: 12) {
                KinnectAvatarView(
                    name: friend.name,
                    avatarURL: friend.avatarUrl,
                    colorHex: friend.avatarColor,
                    size: 44,
                    isOnline: (friend.isActive && friend.showActivity) || appState.onlineUserIds.contains(friend.id)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                    Text("@\(friend.handle.isEmpty ? friend.name : friend.handle)")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "bubble.right.fill")
                    .foregroundColor(KinnectTheme.accentBright)
                    .font(.subheadline)
            }
            .padding(.vertical, 4)
        }
    }
}

struct CreateGroupSheet: View {
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var name = ""
    @State private var description = ""
    @State private var friends: [KinnectUser] = []
    @State private var selectedIds: Set<String> = []
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin nhóm") {
                    TextField("Tên nhóm trò chuyện", text: $name)
                    TextField("Mô tả nhóm", text: $description)
                }

                Section("Chọn thành viên từ bạn bè") {
                    ForEach(friends) { friend in
                        Button {
                            if selectedIds.contains(friend.id) {
                                selectedIds.remove(friend.id)
                            } else {
                                selectedIds.insert(friend.id)
                            }
                        } label: {
                            HStack {
                                Text(friend.name)
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Spacer()
                                Image(systemName: selectedIds.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Tạo nhóm mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo") {
                        Task { await create() }
                    }
                    .disabled(isCreating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
                    let list = (res["users"] as? [[String: Any]]) ?? (res["friends"] as? [[String: Any]]) ?? []
                    self.friends = list.map(KinnectUser.from)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let reqId = "create_grp_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups",
                method: "POST",
                body: [
                    "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
                    "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
                    "members": Array(selectedIds),
                    "memberIds": Array(selectedIds)
                ],
                requestId: reqId
            )
            onCreated()
            dismiss()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

struct ForwardMessageSheet: View {
    let text: String
    let imageUrl: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var conversations: [[String: Any]] = []
    @State private var groups: [ChatGroupItem] = []
    @State private var friends: [KinnectUser] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if !conversations.isEmpty {
                    Section("Hội thoại gần đây") {
                        ForEach(Array(conversations.enumerated()), id: \.offset) { _, conv in
                            let peer = extractPeer(from: conv)
                            if !peer.id.isEmpty {
                                Button {
                                    Task { await forwardToUser(peer.id, name: peer.name) }
                                } label: {
                                    HStack(spacing: 12) {
                                        KinnectAvatarView(name: peer.name, avatarURL: peer.avatarUrl, colorHex: peer.avatarColor, size: 36)
                                        Text(peer.name).foregroundColor(KinnectTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "paperplane.fill").foregroundColor(KinnectTheme.accentBright)
                                    }
                                }
                            }
                        }
                    }
                }

                if !groups.isEmpty {
                    Section("Nhóm trò chuyện") {
                        ForEach(groups) { g in
                            Button {
                                Task { await forwardToGroup(g.id, name: g.name) }
                            } label: {
                                HStack(spacing: 12) {
                                    KinnectAvatarView(name: g.name, avatarURL: "", colorHex: g.avatarColor, size: 36)
                                    Text(g.name).foregroundColor(KinnectTheme.textPrimary)
                                    Spacer()
                                    Image(systemName: "paperplane.fill").foregroundColor(KinnectTheme.accentBright)
                                }
                            }
                        }
                    }
                }

                if !friends.isEmpty {
                    Section("Bạn bè") {
                        ForEach(friends) { f in
                            Button {
                                Task { await forwardToUser(f.id, name: f.name) }
                            } label: {
                                HStack(spacing: 12) {
                                    KinnectAvatarView(name: f.name, avatarURL: f.avatarUrl, colorHex: f.avatarColor, size: 36)
                                    Text(f.name).foregroundColor(KinnectTheme.textPrimary)
                                    Spacer()
                                    Image(systemName: "paperplane.fill").foregroundColor(KinnectTheme.accentBright)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Chuyển tiếp tin nhắn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textSecondary) {
                        dismiss()
                    }
                }
            }
            .task {
                await loadTargets()
            }
        }
    }

    private func extractPeer(from conv: [String: Any]) -> KinnectUser {
        if let u = conv["user"] as? [String: Any] ?? conv["peer"] as? [String: Any] {
            return KinnectUser.from(u)
        }
        return KinnectUser.from(conv)
    }

    private func loadTargets() async {
        if UIReviewFixture.activeScreen != nil {
            self.conversations = [
                [
                    "peer": [
                        "id": "fixture_user_fwd_1",
                        "name": "Hoàng Nam",
                        "handle": "hoang_nam",
                        "avatarColor": "#7C3AED"
                    ]
                ],
                [
                    "peer": [
                        "id": "fixture_user_fwd_2",
                        "name": "Thanh Trúc",
                        "handle": "thanh_truc",
                        "avatarColor": "#EC4899"
                    ]
                ]
            ]
            self.groups = [
                ChatGroupItem.from([
                    "id": "group-fixture-01",
                    "name": "Gia đình Kinnect",
                    "description": "Nhóm trò chuyện chia sẻ",
                    "avatarColor": "#8A3FFC",
                    "membersCount": 5,
                    "lastMessageText": "Hẹn gặp mọi người tối nay nhé!",
                    "unreadCount": 0
                ])
            ]
            self.friends = [
                KinnectUser.from([
                    "id": "fixture_user_fwd_3",
                    "name": "Võ Minh Khang",
                    "handle": "minh_khang",
                    "avatarColor": "#3B82F6"
                ])
            ]
            return
        }
        isLoading = true
        defer { isLoading = false }
        if let cRes = try? await KinnectAPIClient.shared.requestJSON("/api/conversations") {
            self.conversations = cRes["conversations"] as? [[String: Any]] ?? []
        }
        if let gRes = try? await KinnectAPIClient.shared.requestJSON("/api/groups") {
            self.groups = (gRes["groups"] as? [[String: Any]] ?? []).map(ChatGroupItem.from)
        }
        if let fRes = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
            self.friends = (fRes["friends"] as? [[String: Any]] ?? []).map(KinnectUser.from)
        }
    }

    private func forwardToUser(_ userId: String, name: String) async {
        let reqId = "fwd_u_\(userId)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(userId)/messages",
                method: "POST",
                body: [
                    "body": text,
                    "text": text,
                    "imageUrl": imageUrl,
                    "requestId": reqId
                ],
                requestId: reqId
            )
            appState.showToast("Đã chuyển tiếp tới \(name)!")
            dismiss()
        } catch {
            appState.showToast("Không thể chuyển tiếp: \(error.localizedDescription)")
        }
    }

    private func forwardToGroup(_ groupId: String, name: String) async {
        let reqId = "fwd_g_\(groupId)_\(UUID().uuidString)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/messages",
                method: "POST",
                body: [
                    "body": text,
                    "text": text,
                    "imageUrl": imageUrl,
                    "requestId": reqId
                ],
                requestId: reqId
            )
            appState.showToast("Đã chuyển tiếp tới nhóm \(name)!")
            dismiss()
        } catch {
            appState.showToast("Không thể chuyển tiếp: \(error.localizedDescription)")
        }
    }
}

struct RenameGroupSheet: View {
    let groupId: String
    let currentName: String
    let onRenamed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var name: String = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tên nhóm mới") {
                    TextField("Nhập tên nhóm", text: $name)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Đổi tên nhóm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = currentName
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)",
                method: "PATCH",
                body: ["name": clean]
            )
            appState.showToast("Đã đổi tên nhóm thành '\(clean)'.")
            onRenamed()
            dismiss()
        } catch {
            appState.showToast("Lỗi đổi tên: \(error.localizedDescription)")
        }
    }
}

struct AddGroupMembersSheet: View {
    let groupId: String
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var friends: [KinnectUser] = []
    @State private var selectedIds: Set<String> = []
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List(friends) { friend in
                Button {
                    if selectedIds.contains(friend.id) {
                        selectedIds.remove(friend.id)
                    } else {
                        selectedIds.insert(friend.id)
                    }
                } label: {
                    HStack {
                        KinnectAvatarView(name: friend.name, avatarURL: friend.avatarUrl, colorHex: friend.avatarColor, size: 36)
                        Text(friend.name).foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        Image(systemName: selectedIds.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Thêm thành viên")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Thêm (\(selectedIds.count))") {
                        Task { await add() }
                    }
                    .disabled(isAdding || selectedIds.isEmpty)
                }
            }
            .task {
                if let res = try? await KinnectAPIClient.shared.requestJSON("/api/friends") {
                    self.friends = (res["friends"] as? [[String: Any]] ?? []).map(KinnectUser.from)
                }
            }
        }
    }

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/members",
                method: "POST",
                body: ["members": Array(selectedIds)]
            )
            appState.showToast("Đã thêm thành viên vào nhóm!")
            onAdded()
            dismiss()
        } catch {
            appState.showToast("Lỗi thêm thành viên: \(error.localizedDescription)")
        }
    }
}
