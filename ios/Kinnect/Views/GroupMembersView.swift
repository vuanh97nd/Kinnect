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

    var body: some View {
        NavigationStack {
            List {
                if let errorText { Text(errorText).foregroundColor(KinnectTheme.danger) }
                ForEach(members) { member in
                    HStack {
                        KinnectAvatarView(name: member.name, avatarURL: member.avatarUrl,
                                          colorHex: member.avatarColor, size: 40)
                        VStack(alignment: .leading) {
                            Text(member.name)
                            Text(roleTitle(member.id)).font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        Spacer()
                        if ownerId == appState.currentUser?.id && member.id != ownerId {
                            Button(roles[member.id] == "deputy" ? "Bỏ phó nhóm" : "Bổ nhiệm") {
                                pendingChange = member
                            }
                            .disabled(isSaving)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Thành viên nhóm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task { await loadMembers() }
            .refreshable { await loadMembers() }
            .alert("Thay đổi vai trò?", isPresented: Binding(
                get: { pendingChange != nil },
                set: { if !$0 { pendingChange = nil } }
            )) {
                Button("Hủy", role: .cancel) { pendingChange = nil }
                Button("Xác nhận") {
                    if let member = pendingChange {
                        Task { await changeRole(member) }
                    }
                    pendingChange = nil
                }
            } message: {
                Text(pendingChange?.name ?? "")
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
}
