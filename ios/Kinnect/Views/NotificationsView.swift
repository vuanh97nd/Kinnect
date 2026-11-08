import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            if !notifications.isEmpty {
                HStack {
                    Spacer()
                    Button("Đọc tất cả") {
                        Task { await markAllRead() }
                    }
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.accentBright)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            List {
            if notifications.isEmpty && !isLoading {
                HStack(spacing: 10) {
                    KinnectIcon(glyph: .notifications, size: 24, tint: KinnectTheme.textSecondary)
                    Text("Chưa có thông báo mới")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                }
                .listRowBackground(Color.clear)
            }

            ForEach(notifications) { item in
                Button {
                    Task { await handleNotificationTap(item) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        KinnectAvatarView(
                            name: item.actor.name.isEmpty ? "K" : item.actor.name,
                            avatarURL: item.actor.avatarUrl,
                            colorHex: item.actor.avatarColor,
                            size: 42
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.actor.name.isEmpty ? "Kinnect" : item.actor.name)
                                    .font(.subheadline.bold())
                                    .foregroundColor(KinnectTheme.textPrimary)
                                Spacer()
                                Text(formatRelativeDate(item.createdAt))
                                    .font(.caption2)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            Text(item.preview.isEmpty ? "Bạn có tương tác mới" : item.preview)
                                .font(.subheadline)
                                .foregroundColor(item.read ? KinnectTheme.textSecondary : KinnectTheme.textPrimary)
                                .kinnectMultiline()
                        }

                        if !item.read {
                            Circle()
                                .fill(KinnectTheme.accentBright)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .listRowBackground(item.read ? KinnectTheme.surface : KinnectTheme.surfaceElevated)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(KinnectTheme.background)
        }
        .background(KinnectTheme.background)
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadNotifications()
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

        appState.navigationTargetRef = item.ref
        let t = item.type.lowercased()
        if t.contains("message") || t.contains("chat") || t.contains("group") {
            appState.navigate(to: "messages")
        } else if t.contains("friend") || t.contains("follow") || t.contains("profile") {
            appState.navigate(to: "profile")
        } else if t.contains("short") || t.contains("video") {
            appState.navigate(to: "video")
        } else if t.contains("post") || t.contains("comment") || t.contains("like") || t.contains("reaction") {
            appState.navigate(to: "feed")
        }
        dismiss()
    }

    private func markAllRead() async {
        let reqId = "notif_read_\(Int(Date().timeIntervalSince1970))"
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/notifications",
            method: "POST",
            body: [:],
            requestId: reqId
        )
        await loadNotifications()
        await appState.refreshGlobalBadges()
    }
}

