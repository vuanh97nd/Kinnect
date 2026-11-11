import SwiftUI

/// Pinned top header bar matching Android 1.2.12 MainActivity (lines 398-438)
/// Features 40dp squircle Logo K (no text next to it) and trailing icons:
/// 1. Thông báo, 2. Cửa hàng, 3. Bạn bè, 4. Tin nhắn, 5. Tài khoản.
struct KinnectTopBar: View {
    @ObservedObject var appState: AppState
    @Binding var activeTopSection: KinnectTopSection?
    var onLogoTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            // Left: Brand Logo K (40dp squircle matching Android line 407, no text)
            Button {
                onLogoTap?()
            } label: {
                KinnectBrandLogo(size: 40)
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

            // Trailing icon 2: Store / Cửa hàng
            topBarButton(
                glyph: .store,
                label: "Cửa hàng",
                isSelected: activeTopSection == .wallet
            ) {
                toggleSection(.wallet)
            }

            // Trailing icon 3: Friends / Bạn bè
            topBarButton(
                glyph: .friends,
                label: "Bạn bè",
                isSelected: activeTopSection == .friends
            ) {
                toggleSection(.friends)
            }

            // Trailing icon 4: Messages / Tin nhắn
            topBarButton(
                glyph: .messages,
                label: "Tin nhắn",
                badgeCount: appState.unreadMessagesCount,
                isSelected: activeTopSection == .messages
            ) {
                toggleSection(.messages)
            }

            // Trailing icon 5: User Account / Tài khoản (Avatar 24dp in 44dp holder matching Android meHolder)
            Button {
                toggleSection(.profile)
            } label: {
                ZStack {
                    Circle()
                        .fill(activeTopSection == .profile ? KinnectTheme.accentSoft : Color.clear)
                        .frame(width: 44, height: 44)

                    if let u = appState.currentUser {
                        KinnectAvatarView(
                            name: u.name,
                            avatarURL: u.avatarUrl,
                            colorHex: u.avatarColor,
                            size: 28,
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
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tài khoản")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 56)
        .background(KinnectTheme.surface.ignoresSafeArea(edges: .top))
        .overlay(
            Divider().background(KinnectTheme.borderSoft),
            alignment: .bottom
        )
    }

    private func toggleSection(_ section: KinnectTopSection) {
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

