import SwiftUI

struct PrivacyConsentSheet: View {
    let request: PrivacyConsentRequest
    let onAccepted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(KinnectTheme.accent.opacity(0.18))
                                .frame(width: 48, height: 48)
                            KinnectIcon(glyph: .shield, size: 26, selected: true, tint: KinnectTheme.accentBright)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bảo vệ dữ liệu & Quyền riêng tư")
                                .font(.headline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text("Phiên bản quy định: \(request.version)")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }

                    Text(request.notice)
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineSpacing(4)
                        .kinnectCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quyền kiểm soát của bạn:")
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)

                        bulletPoint("Quản lý bài viết, ảnh, video và thu hồi bất kỳ lúc nào.")
                        bulletPoint("Chặn người dùng và báo cáo nội dung vi phạm ngay trong ứng dụng.")
                        bulletPoint("Yêu cầu xóa vĩnh viễn tài khoản và toàn bộ dữ liệu trong Hồ sơ cá nhân.")
                    }
                    .padding(.horizontal, 4)

                    if let privacyUrl = URL(string: "https://kinnect.io.vn/privacy") {
                        Link(destination: privacyUrl) {
                            HStack(spacing: 6) {
                                Text("Xem chính sách quyền riêng tư đầy đủ")
                                    .font(.caption.bold())
                                KinnectIcon(glyph: .chevronRight, size: 14)
                            }
                            .foregroundColor(KinnectTheme.accentBright)
                        }
                        .padding(.top, 4)
                    }

                    VStack(spacing: 10) {
                        Button {
                            Task { await acceptConsent() }
                        } label: {
                            HStack {
                                Spacer()
                                if isSubmitting {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Tôi đồng ý & Tiếp tục")
                                        .font(.subheadline.bold())
                                }
                                Spacer()
                            }
                            .frame(minHeight: 46)
                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                            .foregroundColor(.white)
                        }
                        .disabled(isSubmitting)

                        Button("Để sau") {
                            dismiss()
                        }
                        .font(.footnote)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .padding(.top, 10)
                }
                .padding(20)
            }
            .background(KinnectTheme.background)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    KinnectIconButton(glyph: .close, label: "Đóng", tint: KinnectTheme.textPrimary) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(KinnectTheme.accentBright)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundColor(KinnectTheme.textSecondary)
                .kinnectMultiline()
        }
    }

    private func acceptConsent() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/privacy-consent",
                method: "POST",
                body: ["accepted": true, "version": request.version]
            )
            appState.pendingPrivacyConsent = nil
            appState.showToast("Đã ghi nhận sự đồng ý của bạn.")
            onAccepted()
            dismiss()
        } catch {
            appState.showToast("Không thể lưu: \(error.localizedDescription)")
        }
    }
}
