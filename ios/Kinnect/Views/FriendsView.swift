import SwiftUI

struct FriendsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    enum FriendTab: String, CaseIterable {
        case friends = "Bạn bè"
        case requests = "Lời mời"
        case outgoing = "Đã gửi"
    }

    @State private var tab: FriendTab = .friends
    @State private var searchQuery: String = ""
    @State private var friends: [KinnectUser] = []
    @State private var incoming: [KinnectUser] = []
    @State private var outgoing: [KinnectUser] = []
    @State private var suggestions: [KinnectUser] = []
    @State private var discoverResults: [KinnectUser] = []
    @State private var isSearchingServer = false
    @State private var isLoading = false
    @State private var selectedProfileUser: KinnectUser? = nil
    @State private var activeChatPeer: KinnectUser? = nil

    var onBack: (() -> Void)? = nil

    init(initialTab: FriendTab = .friends, onBack: (() -> Void)? = nil) {
        _tab = State(initialValue: initialTab)
        self.onBack = onBack
    }

    private var filteredFriends: [KinnectUser] {
        let clean = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.isEmpty { return friends }
        let q = clean.hasPrefix("@") ? String(clean.dropFirst()) : clean
        return friends.filter { $0.name.lowercased().contains(q) || $0.handle.lowercased().contains(q) }
    }

    private var trimmedSearchQuery: String {
        let clean = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.hasPrefix("@") ? String(clean.dropFirst()) : clean
    }

    private var filteredDiscoverResults: [KinnectUser] {
        guard !trimmedSearchQuery.isEmpty else { return [] }
        let friendIds = Set(filteredFriends.map(\.id))
        return discoverResults.filter { !friendIds.contains($0.id) }
    }

    // Suggestions filtered by search, max 6 - matches Android discover integration
    private var filteredSuggestions: [KinnectUser] {
        let clean = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let discoverIds = Set(filteredDiscoverResults.map(\.id))
        var filtered = suggestions.filter { !discoverIds.contains($0.id) }
        if !clean.isEmpty {
            let q = clean.hasPrefix("@") ? String(clean.dropFirst()) : clean
            filtered = filtered.filter { $0.name.lowercased().contains(q) || $0.handle.lowercased().contains(q) }
        }
        return Array(filtered.prefix(6))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned Header Bar (matching Android accountHeader pattern)
            PinnedHeaderBar(
                title: "Bạn bè",
                onBack: onBack ?? { dismiss() },
                trailingActions: []
            )

            // Tab Picker
            Picker("Bạn bè", selection: $tab) {
                ForEach(FriendTab.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Search Bar matching Android searchField
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(KinnectTheme.textSecondary)
                TextField("Tên hoặc @username", text: $searchQuery)
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textPrimary)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
            .padding(.horizontal, 16)

            ScrollView {
                LazyVStack(spacing: 14) {
                    switch tab {
                    case .friends:
                        if filteredFriends.isEmpty && filteredDiscoverResults.isEmpty && !isLoading && !isSearchingServer && filteredSuggestions.isEmpty {
                            emptyPlaceholder(searchQuery.isEmpty ? "Chưa có bạn bè nào trong danh sách" : "Không tìm thấy người dùng phù hợp")
                        } else {
                            let online = filteredFriends.filter { ($0.isActive && $0.showActivity) || appState.onlineUserIds.contains($0.id) }
                            let offline = filteredFriends.filter { !(($0.isActive && $0.showActivity) || appState.onlineUserIds.contains($0.id)) }

                            if !online.isEmpty {
                                sectionHeader("Đang trực tuyến", count: online.count, color: Color(hex: "#2E9E66"))
                                VStack(spacing: 0) {
                                    ForEach(online) { user in
                                        friendRow(user: user)
                                        if user.id != online.last?.id {
                                            Divider().background(KinnectTheme.borderSoft).padding(.leading, 64)
                                        }
                                    }
                                }
                                .background(groupedCardBackground)
                            }

                            if !offline.isEmpty {
                                sectionHeader("Ngoại tuyến", count: offline.count, color: KinnectTheme.textSecondary)
                                VStack(spacing: 0) {
                                    ForEach(offline) { user in
                                        friendRow(user: user)
                                        if user.id != offline.last?.id {
                                            Divider().background(KinnectTheme.borderSoft).padding(.leading, 64)
                                        }
                                    }
                                }
                                .background(groupedCardBackground)
                            }

                            if !trimmedSearchQuery.isEmpty {
                                if isSearchingServer && filteredDiscoverResults.isEmpty {
                                    HStack(spacing: 8) {
                                        ProgressView().tint(KinnectTheme.accentBright)
                                        Text("Đang tìm trên toàn bộ Kinnect…")
                                            .font(.caption)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                } else if !filteredDiscoverResults.isEmpty {
                                    sectionHeader("Kết quả tìm kiếm trên Kinnect", count: filteredDiscoverResults.count, color: KinnectTheme.accentBright)
                                    VStack(spacing: 0) {
                                        ForEach(filteredDiscoverResults) { user in
                                            suggestionRow(user: user)
                                            if user.id != filteredDiscoverResults.last?.id {
                                                Divider().background(KinnectTheme.borderSoft).padding(.leading, 64)
                                            }
                                        }
                                    }
                                    .background(groupedCardBackground)
                                }
                            }

                            // Suggestions integrated at bottom of friends tab (max 6, search-filtered) - matches Android
                            if !filteredSuggestions.isEmpty {
                                sectionHeader("Gợi ý kết bạn", count: filteredSuggestions.count, color: KinnectTheme.accentBright)
                                VStack(spacing: 0) {
                                    ForEach(filteredSuggestions) { user in
                                        suggestionRow(user: user)
                                        if user.id != filteredSuggestions.last?.id {
                                            Divider().background(KinnectTheme.borderSoft).padding(.leading, 64)
                                        }
                                    }
                                }
                                .background(groupedCardBackground)
                            }
                        }

                    case .requests:
                        if incoming.isEmpty && !isLoading {
                            emptyPlaceholder("Không có lời mời kết bạn nào")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(incoming) { user in
                                    incomingRequestRow(user: user)
                                    if user.id != incoming.last?.id {
                                        Divider().background(KinnectTheme.borderSoft).padding(.leading, 64)
                                    }
                                }
                            }
                            .background(groupedCardBackground)
                        }

                    case .outgoing:
                        if outgoing.isEmpty && !isLoading {
                            emptyPlaceholder("Không có lời mời nào đã gửi")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(outgoing) { user in
                                    outgoingRequestRow(user: user)
                                    if user.id != outgoing.last?.id {
                                        Divider().background(KinnectTheme.borderSoft).padding(.leading, 64)
                                    }
                                }
                            }
                            .background(groupedCardBackground)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
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
        .task(id: searchQuery) {
            await searchDiscover(query: searchQuery, immediate: false)
        }
        .onAppear {
            if UIReviewFixture.activeScreen == "friends-requests" {
                tab = .requests
            } else if UIReviewFixture.activeScreen == "friends-suggestions" {
                tab = .friends
            }
        }
        .sheet(item: $selectedProfileUser) { user in
            ProfileView(targetUser: user)
        }
        .sheet(item: $activeChatPeer) { peer in
            NavigationStack {
                DirectChatDetailView(peer: peer)
            }
        }
    }

    private func sectionHeader(_ text: String, count: Int? = nil, color: Color = KinnectTheme.textSecondary) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundColor(color)
            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(0.15)))
            }
            Spacer()
        }
    }

    private var groupedCardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(KinnectTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(KinnectTheme.borderSoft.opacity(0.8), lineWidth: 0.8)
            )
    }

    private func emptyPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(KinnectTheme.textSecondary)
            .padding(.vertical, 36)
    }

    // MARK: - Friendship Status Chip (matches Android personTile friendship actions)
    @ViewBuilder
    private func friendshipStatusChip(for user: KinnectUser) -> some View {
        let status = user.friendshipStatus.lowercased()

        switch status {
        case "friends":
            // Already friends - show "Nhắn tin" primary action
            Button {
                activeChatPeer = user
            } label: {
                Text("Nhắn tin")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
            }
            .fixedSize()
            .accessibilityLabel("Nhắn tin với \(user.name)")

        case "incoming":
            // Incoming friend request - show "Chấp nhận" / "Từ chối"
            HStack(spacing: 6) {
                Button("Chấp nhận") {
                    Task { await respondRequest(user: user, action: "accept") }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(KinnectTheme.primaryGradient))

                Button("Từ chối") {
                    Task { await respondRequest(user: user, action: "reject") }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(KinnectTheme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(KinnectTheme.surfaceElevated))
            }
            .fixedSize()

        case "outgoing":
            // Outgoing friend request - show "Huỷ lời mời"
            Button("Huỷ lời mời") {
                Task { await cancelRequest(user) }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(KinnectTheme.danger)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(KinnectTheme.surfaceElevated))
            .fixedSize()

        default:
            // Not friends - show "Kết bạn"
            Button("Kết bạn") {
                Task { await sendRequest(user) }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(KinnectTheme.primaryGradient))
            .fixedSize()
        }
    }

    private func friendRow(user: KinnectUser) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedProfileUser = user
            } label: {
                HStack(spacing: 10) {
                    KinnectAvatarView(
                        name: user.name,
                        avatarURL: user.avatarUrl,
                        colorHex: user.avatarColor,
                        size: 42,
                        isOnline: (user.isActive && user.showActivity) || appState.onlineUserIds.contains(user.id)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        let active = (user.isActive && user.showActivity) || appState.onlineUserIds.contains(user.id)
                        Text("@\(user.handle.isEmpty ? user.name : user.handle) • \(active ? "Đang hoạt động" : "Ngoại tuyến")")
                            .font(.caption2)
                            .foregroundColor(active ? Color(hex: "#2E9E66") : KinnectTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HStack(spacing: 0) {
                Button {
                    activeChatPeer = user
                } label: {
                    KinnectIcon(glyph: .messages, size: 18, tint: KinnectTheme.accentBright)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(KinnectTheme.surfaceElevated))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nhắn tin")

                Menu {
                    Button {
                        Task {
                            dismiss()
                            await NativeWebRTCManager.shared.startOutgoingCall(targetUser: user, mode: "audio")
                        }
                    } label: {
                        Label("Gọi thoại", systemImage: "phone")
                    }
                    Button {
                        Task {
                            dismiss()
                            await NativeWebRTCManager.shared.startOutgoingCall(targetUser: user, mode: "video")
                        }
                    } label: {
                        Label("Gọi video", systemImage: "video")
                    }
                    Divider()
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn bạn bè")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .kinnectCard()
    }

    private func suggestionRow(user: KinnectUser) -> some View {
        HStack(spacing: 10) {
            Button {
                selectedProfileUser = user
            } label: {
                HStack(spacing: 10) {
                    KinnectAvatarView(
                        name: user.name,
                        avatarURL: user.avatarUrl,
                        colorHex: user.avatarColor,
                        size: 46,
                        isOnline: (user.isActive && user.showActivity) || appState.onlineUserIds.contains(user.id)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        let active = (user.isActive && user.showActivity) || appState.onlineUserIds.contains(user.id)
                        Text("@\(user.handle.isEmpty ? user.name : user.handle) • \(active ? "Đang hoạt động" : "Ngoại tuyến")")
                            .font(.caption2)
                            .foregroundColor(active ? Color(hex: "#2E9E66") : KinnectTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            friendshipStatusChip(for: user)
        }
        .kinnectCard()
    }

    private func incomingRequestRow(user: KinnectUser) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedProfileUser = user
            } label: {
                HStack(spacing: 10) {
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
                }
            }
            .buttonStyle(.plain)

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
            Button {
                selectedProfileUser = user
            } label: {
                HStack(spacing: 10) {
                    KinnectAvatarView(name: user.name, avatarURL: user.avatarUrl, colorHex: user.avatarColor, size: 44)
                    Text(user.name)
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                        .kinnectMultiline()
                }
            }
            .buttonStyle(.plain)

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

    private func loadAll() async {
        if friends.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/friends"),
           let list = (cached["users"] as? [[String: Any]]) ?? (cached["friends"] as? [[String: Any]]) {
            self.friends = list.map(KinnectUser.from)
        }
        isLoading = true
        defer { isLoading = false }

        async let fTask = KinnectAPIClient.shared.requestJSON("/api/friends")
        async let rTask = KinnectAPIClient.shared.requestJSON("/api/friend-requests")
        async let sTask = KinnectAPIClient.shared.requestJSON("/api/friend-suggestions")

        if let fRes = try? await fTask {
            let list = (fRes["users"] as? [[String: Any]]) ?? (fRes["friends"] as? [[String: Any]]) ?? []
            self.friends = list.map(KinnectUser.from)
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
            let list = (sRes["users"] as? [[String: Any]]) ?? (sRes["suggestions"] as? [[String: Any]]) ?? []
            self.suggestions = list.map(KinnectUser.from)
        }
        if !trimmedSearchQuery.isEmpty {
            await searchDiscover(query: searchQuery, immediate: true)
        }
    }

    private func searchDiscover(query: String, immediate: Bool) async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = clean.hasPrefix("@") ? String(clean.dropFirst()) : clean
        guard !normalized.isEmpty else {
            discoverResults = []
            isSearchingServer = false
            return
        }
        if !immediate {
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }
        }
        isSearchingServer = true
        defer { isSearchingServer = false }
        var components = URLComponents()
        components.path = "/api/discover"
        components.queryItems = [URLQueryItem(name: "q", value: normalized)]
        let path = components.string ?? "/api/discover?q=\(normalized)"
        if let res = try? await KinnectAPIClient.shared.requestJSON(path),
           !Task.isCancelled {
            let list = (res["users"] as? [[String: Any]]) ?? []
            discoverResults = list.map(KinnectUser.from)
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

