import SwiftUI

/// Dedicated Account Menu screen matching Android 1.2.12 MainActivity.meMenu() (lines 742-790)
/// Features user profile header card, games, wallet, privacy, security, notifications, theme, support, password, logout.
struct AccountMenuView: View {
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss

    var onOpenProfile: () -> Void
    var onOpenWallet: () -> Void
    var onOpenFriends: () -> Void

    @State private var showPrivacySheet = false
    @State private var showSecuritySheet = false
    @State private var showPasswordSheet = false
    @State private var showSupportSheet = false
    @State private var showAboutSheet = false
    @State private var showLogoutConfirm = false
    @State private var showAppearanceSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Profile Header Card (matching Android line 745-764)
                    Button {
                        dismiss()
                        onOpenProfile()
                    } label: {
                        HStack(spacing: 16) {
                            if let u = appState.currentUser {
                                KinnectAvatarView(
                                    name: u.name,
                                    avatarURL: u.avatarUrl,
                                    colorHex: u.avatarColor,
                                    size: 60,
                                    isOnline: false
                                )
                            } else {
                                Circle()
                                    .fill(KinnectTheme.accentSoft)
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        KinnectIcon(glyph: .profile, size: 30, tint: KinnectTheme.accentBright)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(appState.currentUser?.name ?? "Người dùng Kinnect")
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(KinnectTheme.textPrimary)

                                Text("@\(appState.currentUser?.handle ?? "kinnect")")
                                    .font(.subheadline)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.body)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(KinnectTheme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(KinnectTheme.borderSoft, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Trang cá nhân")

                    // Main Group (matching Android line 770-778)
                    VStack(spacing: 0) {
                        menuRow(glyph: .games, title: "Trò chơi", color: .purple) {
                            appState.showToast("Trò chơi: Nông trại, Đố vui, Chơi nhanh 1-1")
                        }
                        Divider().background(KinnectTheme.borderSoft)

                        menuRow(glyph: .wallet, title: "Ví Kinnect", color: KinnectTheme.warning) {
                            dismiss()
                            onOpenWallet()
                        }
                        Divider().background(KinnectTheme.borderSoft)

                        menuRow(glyph: .settings, title: "Cài đặt và quyền riêng tư", color: .blue) {
                            showPrivacySheet = true
                        }
                        Divider().background(KinnectTheme.borderSoft)

                        menuRow(glyph: .shield, title: "Bảo mật và đăng nhập", color: .green) {
                            showSecuritySheet = true
                        }
                        Divider().background(KinnectTheme.borderSoft)

                        menuRow(glyph: .notifications, title: "Cài đặt thông báo", color: .orange) {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Divider().background(KinnectTheme.borderSoft)

                        menuRow(glyph: .moon, title: "Giao diện", color: .indigo) {
                            showAppearanceSheet = true
                        }
                        Divider().background(KinnectTheme.borderSoft)

                        menuRow(glyph: .help, title: "Trợ giúp và hỗ trợ", color: .teal) {
                            showSupportSheet = true
                        }
                        Divider().background(KinnectTheme.borderSoft)

                        menuRow(glyph: .info, title: "Giới thiệu Kinnect", color: .pink) {
                            showAboutSheet = true
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(KinnectTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                    )

                    // End Group: Đổi mật khẩu & Đăng xuất (matching Android line 779-785)
                    VStack(spacing: 0) {
                        menuRow(glyph: .lock, title: "Đổi mật khẩu", color: .mint) {
                            showPasswordSheet = true
                        }
                        Divider().background(KinnectTheme.borderSoft)

                        Button {
                            showLogoutConfirm = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(KinnectTheme.danger.opacity(0.15))
                                        .frame(width: 34, height: 34)
                                    KinnectIcon(glyph: .logout, size: 18, tint: KinnectTheme.danger)
                                }
                                Text("Đăng xuất")
                                    .font(.body.weight(.medium))
                                    .foregroundColor(KinnectTheme.danger)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(KinnectTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(KinnectTheme.borderSoft, lineWidth: 1))
                    )

                    // Footer label (matching Android line 786-788)
                    Text("Kinnect · Kết nối theo cách của bạn.")
                        .font(.footnote)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(KinnectTheme.background.ignoresSafeArea())
            .navigationTitle("Tài khoản")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .confirmationDialog("Đăng xuất khỏi Kinnect?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive) {
                    Task {
                        await appState.logout()
                        dismiss()
                    }
                }
                Button("Hủy", role: .cancel) { }
            } message: {
                Text("Bạn sẽ cần đăng nhập lại để tiếp tục sử dụng Kinnect.")
            }
            .sheet(isPresented: $showPasswordSheet) {
                ChangePasswordSheet()
            }
            .sheet(isPresented: $showPrivacySheet) {
                PrivacySettingsSheet()
            }
            .sheet(isPresented: $showSecuritySheet) {
                ActiveSessionsSheet()
            }
            .sheet(isPresented: $showSupportSheet) {
                SupportContactSheet()
            }
            .sheet(isPresented: $showAppearanceSheet) {
                AppearanceSettingsSheet()
            }
            .sheet(isPresented: $showAboutSheet) {
                AboutKinnectSheet()
            }
        }
    }

    private func menuRow(glyph: KinnectGlyph, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    KinnectIcon(glyph: glyph, size: 18, tint: color)
                }
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(KinnectTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AppearanceSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_appearance_mode") private var appearanceMode: String = "system"

    var body: some View {
        NavigationStack {
            Form {
                Section("Chế độ giao diện") {
                    Picker("Giao diện", selection: $appearanceMode) {
                        Text("Tự động theo hệ thống").tag("system")
                        Text("Chế độ tối (Dark)").tag("dark")
                        Text("Chế độ sáng (Light)").tag("light")
                    }
                    .pickerStyle(.inline)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KinnectTheme.background)
            .navigationTitle("Giao diện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }
}

struct AboutKinnectSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                KinnectBrandLogo(size: 80)
                Text("Kinnect")
                    .font(.title.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text("Phiên bản 1.2.12 (Build 118)")
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.accentBright)
                Text("Nền tảng mạng xã hội kết nối cộng đồng, livestream, video ngắn và chia sẻ khoảnh khắc đích thực.")
                    .font(.footnote)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Text("Bản quyền © 2026 Kinnect. Tất cả các quyền được bảo lưu.")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KinnectTheme.background.ignoresSafeArea())
            .navigationTitle("Giới thiệu Kinnect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}

