import SwiftUI

struct GroupMembersView: View {
    let groupId: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var members: [KinnectUser] = []
    @State private var roles: [String: String] = [:]
    @State private var ownerId = ""
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var pendingChange: KinnectUser?
    @State private var pendingTransferOwner: KinnectUser?
    @State private var pendingRemoveMember: KinnectUser?
    @State private var selectedProfileMember: KinnectUser?
    @State private var searchQuery = ""

    private var canManage: Bool {
        guard let myId = appState.currentUser?.id, !myId.isEmpty else { return false }
        return myId == ownerId || roles[myId] == "deputy"
    }

    private var filteredMembers: [KinnectUser] {
        let clean = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return members }
        let q = Self.searchKey(clean.hasPrefix("@") ? String(clean.dropFirst()) : clean)
        return members.filter {
            Self.searchKey($0.name).contains(q) || Self.searchKey($0.handle).contains(q)
        }
    }

    private static func searchKey(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorText { Text(errorText).foregroundColor(KinnectTheme.danger) }
                ForEach(filteredMembers) { member in
                    HStack(spacing: 10) {
                        Button {
                            selectedProfileMember = member
                        } label: {
                            HStack(spacing: 10) {
                                KinnectAvatarView(name: member.name, avatarURL: member.avatarUrl,
                                                  colorHex: member.avatarColor, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .foregroundColor(KinnectTheme.textPrimary)
                                    Text(roleTitle(member.id)).font(.caption)
                                        .foregroundColor(KinnectTheme.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        let isMe = (member.id == appState.currentUser?.id)
                        let isOwner = (ownerId == appState.currentUser?.id)
                        let canRemove = canManage && !isMe && member.id != ownerId && (isOwner || roles[member.id] != "deputy")

                        Menu {
                            Button {
                                selectedProfileMember = member
                            } label: {
                                Label("Xem hồ sơ", systemImage: "person.circle")
                            }

                            if isOwner && member.id != ownerId {
                                Button {
                                    pendingChange = member
                                } label: {
                                    Label(roles[member.id] == "deputy" ? "Bỏ phó nhóm" : "Bổ nhiệm phó nhóm", systemImage: "shield")
                                }

                                Button {
                                    pendingTransferOwner = member
                                } label: {
                                    Label("Chuyển quyền trưởng nhóm", systemImage: "crown")
                                }
                            }

                            if canRemove {
                                Button(role: .destructive) {
                                    pendingRemoveMember = member
                                } label: {
                                    Label("Xóa khỏi nhóm", systemImage: "person.badge.minus")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18))
                                .foregroundColor(KinnectTheme.textSecondary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .disabled(isSaving)
                        .accessibilityLabel("Tùy chọn thành viên \(member.name)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .searchable(text: $searchQuery, prompt: "Tìm thành viên…")
            .navigationTitle("Thành viên nhóm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task { await loadMembers() }
            .refreshable { await loadMembers() }
            .alert(
                "Thay đổi vai trò?",
                isPresented: Binding(
                    get: { pendingChange != nil },
                    set: { if !$0 { pendingChange = nil } }
                ),
                presenting: pendingChange
            ) { member in
                Button("Hủy", role: .cancel) { pendingChange = nil }
                Button("Xác nhận") {
                    pendingChange = nil
                    Task { await changeRole(member) }
                }
            } message: { member in
                Text(member.name)
            }
            .alert(
                "Chuyển quyền trưởng nhóm?",
                isPresented: Binding(
                    get: { pendingTransferOwner != nil },
                    set: { if !$0 { pendingTransferOwner = nil } }
                ),
                presenting: pendingTransferOwner
            ) { member in
                Button("Hủy", role: .cancel) { pendingTransferOwner = nil }
                Button("Chuyển quyền", role: .destructive) {
                    pendingTransferOwner = nil
                    Task { await transferOwnership(to: member) }
                }
            } message: { member in
                Text("Bạn sẽ trao quyền trưởng nhóm cho \(member.name) và trở thành thành viên.")
            }
            .alert(
                "Xóa thành viên khỏi nhóm?",
                isPresented: Binding(
                    get: { pendingRemoveMember != nil },
                    set: { if !$0 { pendingRemoveMember = nil } }
                ),
                presenting: pendingRemoveMember
            ) { member in
                Button("Hủy", role: .cancel) { pendingRemoveMember = nil }
                Button("Xóa khỏi nhóm", role: .destructive) {
                    pendingRemoveMember = nil
                    Task { await removeMember(member) }
                }
            } message: { member in
                Text("\(member.name) sẽ bị xóa khỏi nhóm trò chuyện này.")
            }
            .sheet(item: $selectedProfileMember) { member in
                NavigationStack {
                    ProfileView(targetUser: member)
                }
            }
        }
    }

    private func roleTitle(_ id: String) -> String {
        id == ownerId ? "Trưởng nhóm" : roles[id] == "deputy" ? "Phó nhóm" : "Thành viên"
    }

    private func applyGroup(_ group: [String: Any]) {
        ownerId = group["owner"] as? String ?? ""
        let raw = group["members"] as? [[String: Any]] ?? []
        members = raw.map(KinnectUser.from)
        roles = raw.reduce(into: [:]) { result, member in
            if let id = member["id"] as? String {
                result[id] = member["groupRole"] as? String ?? "member"
            }
        }
        errorText = nil
    }

    @MainActor private func loadMembers() async {
        do {
            let response = try await KinnectAPIClient.shared.requestJSON("/api/groups/\(groupId)")
            if let group = response["group"] as? [String: Any] { applyGroup(group) }
        } catch { errorText = error.localizedDescription }
    }

    @MainActor private func changeRole(_ member: KinnectUser) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/roles", method: "PATCH",
                body: ["userId": member.id, "role": roles[member.id] == "deputy" ? "member" : "deputy"])
            if let group = response["group"] as? [String: Any] { applyGroup(group) }
        } catch { errorText = error.localizedDescription }
    }

    @MainActor private func transferOwnership(to member: KinnectUser) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/roles", method: "PATCH",
                body: ["userId": member.id, "role": "owner"])
            if let group = response["group"] as? [String: Any] { applyGroup(group) }
            appState.showToast("Đã chuyển quyền trưởng nhóm cho \(member.name).")
        } catch { errorText = error.localizedDescription }
    }

    @MainActor private func removeMember(_ member: KinnectUser) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await KinnectAPIClient.shared.requestJSON(
                "/api/groups/\(groupId)/members", method: "DELETE",
                body: ["userId": member.id])
            if let group = response["group"] as? [String: Any] { applyGroup(group) }
            appState.showToast("Đã xóa \(member.name) khỏi nhóm.")
        } catch { errorText = error.localizedDescription }
    }
}
