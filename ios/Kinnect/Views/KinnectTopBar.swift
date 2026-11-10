import SwiftUI

/// Pinned top header bar matching Android 1.2.12 MainActivity (lines 398-438)
/// Features Logo K, Kinnect title, and trailing icons (Notifications, Store, Friends, Messages, Account).
struct KinnectTopBar: View {
    @ObservedObject var appState: AppState
    @Binding var activeTopSection: RootMainView.TopSection?
    var onLogoTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            // Left: Brand Logo K + App Title
            Button {
                onLogoTap?()
            } label: {
                HStack(spacing: 8) {
                    KinnectBrandLogo(size: 36)
                    Text("Kinnect")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Về đầu Bảng tin Kinnect")

            Spacer(minLength: 8)

            // Trailing icon 1: Notifications (Bell)
            topBarButton(
                glyph: .notifications,
                label: "Thông báo",
                badgeCount: appState.unreadNotificationsCount,
                isSelected: activeTopSection == .notifications
            ) {
                toggleSection(.notifications)
            }

            // Trailing icon 2: Store / Wallet
            topBarButton(
                glyph: .store,
                label: "Ví Kinnect và Cửa hàng Kinnect",
                isSelected: activeTopSection == .wallet
            ) {
                toggleSection(.wallet)
            }

            // Trailing icon 3: Friends
            topBarButton(
                glyph: .friends,
                label: "Bạn bè",
                isSelected: activeTopSection == .friends
            ) {
                toggleSection(.friends)
            }

            // Trailing icon 4: Messages / Inbox
            topBarButton(
                glyph: .messages,
                label: "Tin nhắn",
                badgeCount: appState.unreadMessagesCount,
                isSelected: activeTopSection == .messages
            ) {
                toggleSection(.messages)
            }

            // Trailing icon 5: User Account / Avatar
            Button {
                toggleSection(.profile)
            } label: {
                if let u = appState.currentUser {
                    KinnectAvatarView(
                        name: u.name,
                        avatarURL: u.avatarUrl,
                        colorHex: u.avatarColor,
                        size: 32,
                        isOnline: false
                    )
                    .overlay(
                        Circle()
                            .stroke(activeTopSection == .profile ? KinnectTheme.accentBright : Color.clear, lineWidth: 2)
                    )
                } else {
                    KinnectIcon(
                        glyph: .profile,
                        size: 24,
                        selected: activeTopSection == .profile,
                        tint: activeTopSection == .profile ? KinnectTheme.accentBright : KinnectTheme.textPrimary
                    )
                    .frame(width: 38, height: 44)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hồ sơ cá nhân")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 54)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
        .overlay(
            Divider().background(KinnectTheme.borderSoft),
            alignment: .bottom
        )
    }

    private func toggleSection(_ section: RootMainView.TopSection) {
        if activeTopSection == section {
            activeTopSection = nil
        } else {
            activeTopSection = section
        }
    }

    private func topBarButton(
        glyph: KinnectGlyph,
        label: String,
        badgeCount: Int = 0,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                KinnectIcon(
                    glyph: glyph,
                    size: 22,
                    selected: isSelected,
                    tint: isSelected ? KinnectTheme.accentBright : KinnectTheme.textPrimary
                )
                .frame(width: 36, height: 40)
                .contentShape(Rectangle())

                if badgeCount > 0 {
                    Circle()
                        .fill(KinnectTheme.danger)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
