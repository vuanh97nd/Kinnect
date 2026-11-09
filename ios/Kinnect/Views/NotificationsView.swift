import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    enum NotificationFilter: String, CaseIterable {
        case all = "Tất cả"
        case unread = "Chưa đọc"
    }

    @State private var filter: NotificationFilter = .all
    @State private var searchQuery: String = ""
    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = false
    @State private var selectedProfileUser: KinnectUser? = nil

    var body: some View {
        VStack(spacing: 10) {
            // Header Bar with Title and "Đánh dấu tất cả đã đọc"
            HStack(spacing: 12) {
                Text("Thông báo")
                    .font(.title3.bold())
                    .foregroundColor(KinnectTheme.textPrimary)

                Spacer()

                Button {
                    Task { await markAllRead() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Đánh dấu tất cả đã đọc")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.accentBright)
                }
                .accessibilityLabel("Đánh dấu tất cả đã đọc")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Search Bar (Parity with Android searchField)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(KinnectTheme.textSecondary)
                TextField("Tìm kiếm thông báo…", text: $searchQuery)
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textPrimary)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
            .padding(.horizontal, 14)

            // Filter Tabs (Tất cả · Chưa đọc)
            Picker("Bộ lọc thông báo", selection: $filter) {
                ForEach(NotificationFilter.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)

            // Notifications List
            ScrollView {
                if filteredNotifications.isEmpty && !isLoading {
                    emptyStateView
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredNotifications.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Divider()
                                    .background(KinnectTheme.border)
                                    .padding(.leading, 68)
                                    .padding(.trailing, 10)
                            }
                            notificationRow(item)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(KinnectTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.border, lineWidth: 1))
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
            }
            .refreshable {
                await loadNotifications()
            }
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadNotifications()
        }
        .sheet(item: $selectedProfileUser) { user in
            ProfileView(targetUser: user)
        }
    }

    private var filteredNotifications: [NotificationItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return notifications.filter { item in
            // Filter out direct message notifications (belong to Inbox)
            let t = item.type.lowercased()
            if t == "message" || t == "group_message" {
                return false
            }
            // Filter unread if selected
            if filter == .unread && item.read {
                return false
            }
            // Search query match
            if !q.isEmpty {
                let text = "\(item.actor.name) \(actionText(for: item.type)) \(item.preview)".lowercased()
                if !text.contains(q) {
                    return false
                }
            }
            return true
        }
    }

    private func notificationRow(_ item: NotificationItem) -> some View {
        Button {
            Task { await handleNotificationTap(item) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Left avatar
                Button {
                    if !item.actor.id.isEmpty {
                        selectedProfileUser = item.actor
                    }
                } label: {
                    KinnectAvatarView(
                        name: item.actor.name.isEmpty ? "K" : item.actor.name,
                        avatarURL: item.actor.avatarUrl,
                        colorHex: item.actor.avatarColor,
                        size: 46
                    )
                }
                .buttonStyle(.plain)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(item.actor.name.isEmpty ? "Kinnect" : item.actor.name)
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        + Text(" ")
                        + Text(actionText(for: item.type))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)

                        Spacer(minLength: 4)

                        if !item.read {
                            Circle()
                                .fill(KinnectTheme.accentBright)
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)
                        }
                    }

                    if !item.preview.isEmpty && !item.type.lowercased().contains("like") {
                        Text(item.preview)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .lineLimit(2)
                    }

                    Text(formatRelativeDate(item.createdAt))
                        .font(.caption2)
                        .foregroundColor(item.read ? KinnectTheme.textSecondary : KinnectTheme.accentBright)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(item.read ? Color.clear : KinnectTheme.accent.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            KinnectIcon(glyph: .notifications, size: 40, tint: KinnectTheme.textSecondary)
            Text(
                filter == .unread
                    ? "Không có thông báo chưa đọc."
                    : (searchQuery.isEmpty ? "Chưa có thông báo mới." : "Không tìm thấy thông báo.")
            )
            .font(.subheadline)
            .foregroundColor(KinnectTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func actionText(for type: String) -> String {
        switch type.lowercased() {
        case "like": return "đã thích bài viết của bạn"
        case "comment": return "đã bình luận về bài viết của bạn"
        case "comment_reply": return "đã trả lời bình luận của bạn"
        case "friend_request": return "đã gửi lời mời kết bạn"
        case "friend_accept": return "đã chấp nhận lời mời kết bạn"
        case "follow": return "đã bắt đầu theo dõi bạn"
        case "short_like": return "đã thích video ngắn của bạn"
        case "short_comment": return "đã bình luận video ngắn của bạn"
        default: return "đã tương tác với bạn"
        }
    }

    private func loadNotifications() async {
        if notifications.isEmpty,
           let cached = KinnectAPIClient.shared.cachedJSON(for: "/api/notifications"),
           let list = cached["notifications"] as? [[String: Any]] {
            self.notifications = list.map(NotificationItem.from)
        }
        isLoading = true
        defer { isLoading = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/notifications") {
            let list = res["notifications"] as? [[String: Any]] ?? []
            self.notifications = list.map(NotificationItem.from)
        }
    }

    private func handleNotificationTap(_ item: NotificationItem) async {
        if !item.read {
            _ = try? await KinnectAPIClient.shared.requestJSON(
                "/api/notifications",
                method: "POST",
                body: ["ids": [item.id]],
                requestId: "read_\(item.id)"
            )
            if let idx = notifications.firstIndex(where: { $0.id == item.id }) {
                notifications[idx].read = true
            }
            await appState.refreshGlobalBadges()
        }

        let t = item.type.lowercased()
        if t.contains("friend") || t.contains("follow") || t.contains("profile") {
            selectedProfileUser = item.actor
        } else if t.contains("short") || t.contains("video") {
            appState.navigate(to: "video")
            dismiss()
        } else if t.contains("post") || t.contains("comment") || t.contains("like") {
            appState.navigate(to: "feed")
            dismiss()
        }
    }

    private func markAllRead() async {
        let reqId = "notif_read_\(Int(Date().timeIntervalSince1970))"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/notifications",
            method: "POST",
            body: ["scope": "social"],
            requestId: reqId
        )
        for idx in notifications.indices {
            notifications[idx].read = true
        }
        await appState.refreshGlobalBadges()
    }
}
