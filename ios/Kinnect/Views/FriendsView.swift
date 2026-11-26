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
    @State private var discoverSearchResults: [KinnectUser] = []
    @State private var isSearchingDiscover = false
    @State private var isLoading = false
    @State private var selectedProfileUser: KinnectUser? = nil
    @State private var activeChatPeer: KinnectUser? = nil
    @State private var pendingUnfriendUser: KinnectUser? = nil
    @State private var pendingBlockUser: KinnectUser? = nil

    var onBack: (() -> Void)? = nil

    init(initialTab: FriendTab = .friends, onBack: (() -> Void)? = nil) {
        _tab = State(initialValue: initialTab)
        self.onBack = onBack
    }

    private func matchesSearch(_ user: KinnectUser) -> Bool {
        let clean = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return true }
        let q = (clean.hasPrefix("@") ? String(clean.dropFirst()) : clean)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
        let nameKey = user.name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
        let handleKey = user.handle
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
        return nameKey.contains(q) || handleKey.contains(q)
    }

    private func isUserOnline(_ user: KinnectUser) -> Bool {
        user.showActivity && (user.isActive || appState.onlineUserIds.contains(user.id))
    }

    private var filteredFriends: [KinnectUser] {
        friends.filter(matchesSearch)
    }

    private var filteredIncoming: [KinnectUser] {
        incoming.filter(matchesSearch)
    }

    private var filteredOutgoing: [KinnectUser] {
        outgoing.filter(matchesSearch)
    }

    // Suggestions filtered by search, max 6 - matches Android discover integration
    private var filteredSuggestions: [KinnectUser] {
        Array(suggestions.filter(matchesSearch).prefix(6))
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
                        let hasQuery = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        if filteredFriends.isEmpty && !isLoading && filteredSuggestions.isEmpty && discoverSearchResults.isEmpty && !isSearchingDiscover {
                            emptyPlaceholder(searchQuery.isEmpty ? "Chưa có bạn bè nào trong danh sách" : "Không tìm thấy bạn bè phù hợp")
                        } else {
                            let online = filteredFriends.filter { isUserOnline($0) }
                            let offline = filteredFriends.filter { !isUserOnline($0) }

                            if !online.isEmpty {
                                sectionHeader("Đang trực tuyến", count: online.count, color: KinnectTheme.online)
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

                            if hasQuery {
                                if isSearchingDiscover && discoverSearchResults.isEmpty {
                                    HStack(spacing: 8) {
                                        ProgressView().tint(KinnectTheme.accentBright)
                                        Text(L10n.tr("Đang tìm thành viên…"))
                                            .font(.caption)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                    }
                                    .padding(.vertical, 10)
                                } else if !discoverSearchResults.isEmpty {
                                    sectionHeader(L10n.tr("Kết quả tìm kiếm"), count: discoverSearchResults.count, color: KinnectTheme.accentBright)
                                    VStack(spacing: 0) {
                                        ForEach(discoverSearchResults) { user in
                                            suggestionRow(user: user)
                                            if user.id != discoverSearchResults.last?.id {
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
                        if filteredIncoming.isEmpty && !isLoading {
                            emptyPlaceholder(searchQuery.isEmpty ? "Không có lời mời kết bạn nào" : "Không tìm thấy lời mời phù hợp")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(filteredIncoming) { user in
                                    incomingRequestRow(user: user)
                                    if user.id != filteredIncoming.last?.id {
                                        Divider().background(KinnectTheme.borderSoft).padding(.leading, 64)
                                    }
                                }
                            }
                            .background(groupedCardBackground)
                        }

                    case .outgoing:
                        if filteredOutgoing.isEmpty && !isLoading {
                            emptyPlaceholder(searchQuery.isEmpty ? "Không có lời mời nào đã gửi" : "Không tìm thấy lời mời phù hợp")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(filteredOutgoing) { user in
                                    outgoingRequestRow(user: user)
                                    if user.id != filteredOutgoing.last?.id {
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
            await searchDiscoverUsers()
        }
        .onAppear {
            #if DEBUG
            if UIReviewFixture.activeScreen == "friends-requests" {
                tab = .requests
            } else if UIReviewFixture.activeScreen == "friends-suggestions" {
                tab = .friends
            }
            #endif
        }
        .sheet(item: $selectedProfileUser) { user in
            ProfileView(targetUser: user)
        }
        .sheet(item: $activeChatPeer) { peer in
            NavigationStack {
                DirectChatDetailView(peer: peer)
            }
        }
        .alert(
            "Hủy kết bạn?",
            isPresented: Binding(
                get: { pendingUnfriendUser != nil },
                set: { if !$0 { pendingUnfriendUser = nil } }
            ),
            presenting: pendingUnfriendUser
        ) { user in
            Button("Hủy kết bạn", role: .destructive) {
                pendingUnfriendUser = nil
                Task { await unfriend(user) }
            }
            Button("Đóng", role: .cancel) {
                pendingUnfriendUser = nil
            }
        } message: { user in
            Text("Bạn có chắc muốn hủy kết bạn với \(user.name)?")
        }
        .alert(
            "Chặn người dùng?",
            isPresented: Binding(
                get: { pendingBlockUser != nil },
                set: { if !$0 { pendingBlockUser = nil } }
            ),
            presenting: pendingBlockUser
        ) { user in
            Button("Chặn người dùng", role: .destructive) {
                pendingBlockUser = nil
                Task {
                    await appState.blockUser(userId: user.id, userName: user.name)
                    await loadAll()
                }
            }
            Button("Hủy", role: .cancel) {
                pendingBlockUser = nil
            }
        } message: { user in
            Text("\(user.name) sẽ không thể nhắn tin hoặc xem nội dung của bạn.")
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
                    Task { await respondRequest(user: user, action: "decline") }
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
        VStack(alignment: .leading, spacing: 10) {
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
                            isOnline: isUserOnline(user)
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(.subheadline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            let active = isUserOnline(user)
                            Text("@\(user.handle.isEmpty ? user.name : user.handle) • \(active ? "Đang hoạt động" : "Ngoại tuyến")")
                                .font(.caption)
                                .foregroundColor(active ? KinnectTheme.online : KinnectTheme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                Menu {
                    Button(role: .destructive) {
                        pendingUnfriendUser = user
                    } label: {
                        Label("Hủy kết bạn", systemImage: "person.badge.minus")
                    }
                    Button(role: .destructive) {
                        pendingBlockUser = user
                    } label: {
                        HStack {
                            Text("Chặn người dùng")
                            KinnectIcon(glyph: .block, size: 18, tint: KinnectTheme.danger)
                        }
                    }
                } label: {
                    KinnectIcon(glyph: .more, size: 20, tint: KinnectTheme.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tùy chọn bạn bè")
            }

            HStack(spacing: 8) {
                Button {
                    activeChatPeer = user
                } label: {
                    HStack(spacing: 5) {
                        KinnectIcon(glyph: .messages, size: 15, tint: .white)
                        Text("Nhắn tin")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(KinnectTheme.primaryGradient))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nhắn tin")

                Button {
                    Task {
                        dismiss()
                        await NativeWebRTCManager.shared.startOutgoingCall(targetUser: user, mode: "audio")
                    }
                } label: {
                    HStack(spacing: 5) {
                        KinnectIcon(glyph: .phone, size: 15, tint: KinnectTheme.online)
                        Text("Gọi thoại")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gọi thoại")

                Button {
                    Task {
                        dismiss()
                        await NativeWebRTCManager.shared.startOutgoingCall(targetUser: user, mode: "video")
                    }
                } label: {
                    HStack(spacing: 5) {
                        KinnectIcon(glyph: .videoCall, size: 15, tint: KinnectTheme.accentBright)
                        Text("Video")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Gọi video")
            }
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
                        isOnline: isUserOnline(user)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        let active = isUserOnline(user)
                        Text("@\(user.handle.isEmpty ? user.name : user.handle) • \(active ? "Đang hoạt động" : "Ngoại tuyến")")
                            .font(.caption2)
                            .foregroundColor(active ? KinnectTheme.online : KinnectTheme.textSecondary)
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
        VStack(alignment: .leading, spacing: 10) {
            Button {
                selectedProfileUser = user
            } label: {
                HStack(spacing: 10) {
                    KinnectAvatarView(name: user.name, avatarURL: user.avatarUrl, colorHex: user.avatarColor, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                        Text("Muốn kết bạn với bạn")
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    Task { await respondRequest(user: user, action: "accept") }
                } label: {
                    Text("Đồng ý")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(KinnectTheme.primaryGradient))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await respondRequest(user: user, action: "decline") }
                } label: {
                    Text("Từ chối")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
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
        if incoming.isEmpty && outgoing.isEmpty,
           let cachedReq = KinnectAPIClient.shared.cachedJSON(for: "/api/friend-requests") {
            let inc = cachedReq["incoming"] as? [[String: Any]] ?? []
            let out = cachedReq["outgoing"] as? [[String: Any]] ?? []
            self.incoming = inc.map { item in
                if let u = item["fromUser"] as? [String: Any] ?? item["user"] as? [String: Any] { return KinnectUser.from(u) }
                return KinnectUser.from(item)
            }
            self.outgoing = out.map { item in
                if let u = item["toUser"] as? [String: Any] ?? item["user"] as? [String: Any] { return KinnectUser.from(u) }
                return KinnectUser.from(item)
            }
        }
        if suggestions.isEmpty,
           let cachedSug = KinnectAPIClient.shared.cachedJSON(for: "/api/friend-suggestions"),
           let list = (cachedSug["users"] as? [[String: Any]]) ?? (cachedSug["suggestions"] as? [[String: Any]]) {
            self.suggestions = list.map(KinnectUser.from)
        }
        isLoading = friends.isEmpty && incoming.isEmpty && outgoing.isEmpty
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
            appState.pendingFriendRequestsCount = self.incoming.count
        }
        if let sRes = try? await sTask {
            let list = (sRes["users"] as? [[String: Any]]) ?? (sRes["suggestions"] as? [[String: Any]]) ?? []
            self.suggestions = list.map(KinnectUser.from)
        }
    }

    private func searchDiscoverUsers() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            discoverSearchResults = []
            isSearchingDiscover = false
            return
        }
        isSearchingDiscover = true
        defer { isSearchingDiscover = false }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        let clean = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/discover?q=\(encoded)") {
            let list = (res["people"] as? [[String: Any]] ?? res["users"] as? [[String: Any]] ?? []).map(KinnectUser.from)
            let existingFriendIds = Set(friends.map(\.id))
            discoverSearchResults = list.filter {
                $0.id != appState.currentUser?.id
                    && !appState.blockedUserIds.contains($0.id)
                    && !existingFriendIds.contains($0.id)
            }
        }
    }

    private func sendRequest(_ user: KinnectUser) async {
        let reqId = "freq_\(user.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request",
                method: "POST",
                body: [:],
                requestId: reqId
            )
            await loadAll()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func cancelRequest(_ user: KinnectUser) async {
        let reqId = "fcancel_\(user.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            await loadAll()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func respondRequest(user: KinnectUser, action: String) async {
        let reqId = "fresp_\(user.id)_\(action)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friend-request/respond",
                method: "POST",
                body: ["action": action],
                requestId: reqId
            )
            await loadAll()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }

    private func unfriend(_ user: KinnectUser) async {
        let reqId = "unfriend_\(user.id)"
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/users/\(user.id)/friendship",
                method: "DELETE",
                body: [:],
                requestId: reqId
            )
            await loadAll()
        } catch {
            appState.showToast(error.localizedDescription)
        }
    }
}

