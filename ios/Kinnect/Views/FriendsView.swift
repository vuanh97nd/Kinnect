import SwiftUI

struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    enum FriendTab: String, CaseIterable {
        case friends = "Bạn bè"
        case requests = "Lời mời"
        case suggestions = "Gợi ý"
    }

    @State private var tab: FriendTab = .friends
    @State private var friends: [KinnectUser] = []
    @State private var incoming: [KinnectUser] = []
    @State private var outgoing: [KinnectUser] = []
    @State private var suggestions: [KinnectUser] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("Bạn bè", selection: $tab) {
                ForEach(FriendTab.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 12) {
                    switch tab {
                    case .friends:
                        if friends.isEmpty && !isLoading {
                            emptyPlaceholder("Chưa có bạn bè nào trong danh sách")
                        }
                        ForEach(friends) { user in
                            friendRow(user: user)
                        }

                    case .requests:
                        if !incoming.isEmpty {
                            sectionHeader("Lời mời kết bạn đến (\(incoming.count))")
                            ForEach(incoming) { user in
                                incomingRequestRow(user: user)
                            }
                        }
                        if !outgoing.isEmpty {
                            sectionHeader("Lời mời đã gửi (\(outgoing.count))")
                            ForEach(outgoing) { user in
                                outgoingRequestRow(user: user)
                            }
                        }
                        if incoming.isEmpty && outgoing.isEmpty && !isLoading {
                            emptyPlaceholder("Không có lời mời kết bạn nào")
                        }

                    case .suggestions:
                        if suggestions.isEmpty && !isLoading {
                            emptyPlaceholder("Hiện chưa có gợi ý kết bạn mới")
                        }
                        ForEach(suggestions) { user in
                            suggestionRow(user: user)
                        }
                    }
                }
                .padding(14)
            }
            .refreshable {
                await loadAll()
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadAll()
        }
        .onAppear {
            if UIReviewFixture.activeScreen == "friends-requests" {
                tab = .requests
            } else if UIReviewFixture.activeScreen == "friends-suggestions" {
                tab = .suggestions
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundColor(KinnectTheme.textSecondary)
            Spacer()
        }
    }

    private func emptyPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(KinnectTheme.textSecondary)
            .padding(.vertical, 36)
    }

    private func friendRow(user: KinnectUser) -> some View {
        HStack(spacing: 10) {
            KinnectAvatarView(
                name: user.name,
                avatarURL: user.avatarUrl,
                colorHex: user.avatarColor,
                size: 46,
                isOnline: appState.onlineUserIds.contains(user.id)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !user.handle.isEmpty {
                    Text("@\(user.handle)")
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Button {
                    Task {
                        dismiss()
                        await NativeWebRTCManager.shared.startOutgoingCall(targetUser: user, mode: "audio")
                    }
                } label: {
                    KinnectIcon(glyph: .phone, size: 19, tint: KinnectTheme.online)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(KinnectTheme.surfaceElevated))
                }
                .accessibilityLabel("Gọi thoại")

                Button {
                    Task {
                        dismiss()
                        await NativeWebRTCManager.shared.startOutgoingCall(targetUser: user, mode: "video")
                    }
                } label: {
                    KinnectIcon(glyph: .videoCall, size: 19, tint: KinnectTheme.accentBright)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(KinnectTheme.surfaceElevated))
                }
                .accessibilityLabel("Gọi video")

                Menu {
                    Button(role: .destructive) {
                        Task { await unfriend(user) }
                    } label: {
                        Label("Hủy kết bạn", systemImage: "person.badge.minus")
                    }
                    Button(role: .destructive) {
                        Task { await appState.blockUser(userId: user.id, userName: user.name) }
                    } label: {
                        HStack {
                            Text("Chặn người dùng")
                            KinnectIcon(glyph: .block, size: 18, tint: KinnectTheme.danger)
                        }
                    }
                } label: {
                    KinnectIcon(glyph: .more, size: 20, tint: KinnectTheme.textSecondary)
                        .frame(width: 32, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn bạn bè")
            }
        }
        .kinnectCard()
    }

    private func incomingRequestRow(user: KinnectUser) -> some View {
        HStack(spacing: 12) {
            KinnectAvatarView(name: user.name, avatarURL: user.avatarUrl, colorHex: user.avatarColor, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                    .kinnectMultiline()
                Text("Muốn kết bạn với bạn")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            Spacer()
            Button("Đồng ý") {
                Task { await respondRequest(user: user, action: "accept") }
            }
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(KinnectTheme.primaryGradient))
            .foregroundColor(.white)

            Button("Từ chối") {
                Task { await respondRequest(user: user, action: "reject") }
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(KinnectTheme.surfaceElevated))
            .foregroundColor(KinnectTheme.textSecondary)
        }
        .kinnectCard()
    }

    private func outgoingRequestRow(user: KinnectUser) -> some View {
        HStack(spacing: 12) {
            KinnectAvatarView(name: user.name, avatarURL: user.avatarUrl, colorHex: user.avatarColor, size: 44)
            Text(user.name)
                .font(.subheadline.bold())
                .foregroundColor(KinnectTheme.textPrimary)
                .kinnectMultiline()
            Spacer()
            Button("Thu hồi") {
                Task { await cancelRequest(user) }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(KinnectTheme.surfaceElevated))
            .foregroundColor(KinnectTheme.danger)
        }
        .kinnectCard()
    }

    private func suggestionRow(user: KinnectUser) -> some View {
        HStack(spacing: 12) {
            KinnectAvatarView(name: user.name, avatarURL: user.avatarUrl, colorHex: user.avatarColor, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                    .kinnectMultiline()
                if !user.bio.isEmpty {
                    Text(user.bio)
                        .font(.caption)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                }
            }
            Spacer()
            Button("Kết bạn") {
                Task { await sendRequest(user) }
            }
            .font(.caption.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(KinnectTheme.primaryGradient))
            .foregroundColor(.white)
        }
        .kinnectCard()
    }

    private func loadAll() async {
        if friends.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/friends"),
           let list = cached["friends"] as? [[String: Any]] {
            self.friends = list.map(KinnectUser.from)
        }
        isLoading = true
        defer { isLoading = false }

        async let fTask = KinnectAPIClient.shared.requestJSON("/api/friends")
        async let rTask = KinnectAPIClient.shared.requestJSON("/api/friend-requests")
        async let sTask = KinnectAPIClient.shared.requestJSON("/api/friend-suggestions")

        if let fRes = try? await fTask {
            self.friends = (fRes["friends"] as? [[String: Any]] ?? []).map(KinnectUser.from)
        }
        if let rRes = try? await rTask {
            let inc = rRes["incoming"] as? [[String: Any]] ?? []
            let out = rRes["outgoing"] as? [[String: Any]] ?? []
            self.incoming = inc.map { item in
                if let u = item["fromUser"] as? [String: Any] ?? item["user"] as? [String: Any] {
                    return KinnectUser.from(u)
                }
                return KinnectUser.from(item)
            }
            self.outgoing = out.map { item in
                if let u = item["toUser"] as? [String: Any] ?? item["user"] as? [String: Any] {
                    return KinnectUser.from(u)
                }
                return KinnectUser.from(item)
            }
        }
        if let sRes = try? await sTask {
            self.suggestions = (sRes["suggestions"] as? [[String: Any]] ?? []).map(KinnectUser.from)
        }
    }

    private func sendRequest(_ user: KinnectUser) async {
        let reqId = "freq_\(user.id)"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/users/\(user.id)/friend-request",
            method: "POST",
            body: [:],
            requestId: reqId
        )
        await loadAll()
    }

    private func cancelRequest(_ user: KinnectUser) async {
        let reqId = "fcancel_\(user.id)"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/users/\(user.id)/friend-request",
            method: "DELETE",
            body: [:],
            requestId: reqId
        )
        await loadAll()
    }

    private func respondRequest(user: KinnectUser, action: String) async {
        let reqId = "fresp_\(user.id)_\(action)"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/users/\(user.id)/friend-request/respond",
            method: "POST",
            body: ["action": action],
            requestId: reqId
        )
        await loadAll()
    }

    private func unfriend(_ user: KinnectUser) async {
        let reqId = "unfriend_\(user.id)"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/users/\(user.id)/friendship",
            method: "DELETE",
            body: [:],
            requestId: reqId
        )
        await loadAll()
    }
}

