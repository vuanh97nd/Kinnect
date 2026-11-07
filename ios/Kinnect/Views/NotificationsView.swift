import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared

    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if notifications.isEmpty && !isLoading {
                Text("Chưa có thông báo mới")
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .listRowBackground(Color.clear)
            }

            ForEach(notifications) { item in
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
                                .foregroundColor(.white)
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
                .listRowBackground(item.read ? KinnectTheme.surface : KinnectTheme.surfaceElevated)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(KinnectTheme.background)
        .navigationTitle("Thông báo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Đóng") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Đọc tất cả") {
                    Task { await markAllRead() }
                }
            }
        }
        .task {
            await loadNotifications()
        }
    }

    private func loadNotifications() async {
        isLoading = true
        defer { isLoading = false }
        if let res = try? await KinnectAPIClient.shared.requestJSON("/api/notifications") {
            let list = res["notifications"] as? [[String: Any]] ?? []
            self.notifications = list.map(NotificationItem.from)
        }
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
