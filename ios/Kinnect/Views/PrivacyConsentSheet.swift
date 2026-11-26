import SwiftUI

struct PrivacyConsentSheet: View {
    let request: PrivacyConsentRequest
    /// false = pre-registration: no session yet, so the choice is passed to /api/register
    /// as acceptPrivacyNotice instead of POSTing /api/me/privacy-consent (which requires auth).
    var recordOnServer: Bool = true
    let onAccepted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isSubmitting = false

    init(
        request: PrivacyConsentRequest = PrivacyConsentRequest(
            version: "2026-10-29",
            notice: L10n.tr("Chính sách quyền riêng tư và điều khoản dịch vụ Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.")
        ),
        recordOnServer: Bool = true,
        onAccepted: @escaping () -> Void = {}
    ) {
        self.request = request
        self.recordOnServer = recordOnServer
        self.onAccepted = onAccepted
    }

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
                            Text(L10n.tr("Bảo vệ dữ liệu & Quyền riêng tư"))
                                .font(.headline.bold())
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text(request.version.isEmpty ? L10n.tr("Thông báo dữ liệu hiện hành") : "\(L10n.tr("Phiên bản quy định")): \(request.version)")
                                .font(.caption)
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                    }

                    Text(L10n.tr(request.notice))
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textPrimary)
                        .lineSpacing(4)
                        .kinnectCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("Quyền kiểm soát của bạn:"))
                            .font(.caption.bold())
                            .foregroundColor(KinnectTheme.textSecondary)

                        bulletPoint(L10n.tr("Quản lý bài viết, ảnh, video và thu hồi bất kỳ lúc nào."))
                        bulletPoint(L10n.tr("Chặn người dùng và báo cáo nội dung vi phạm ngay trong ứng dụng."))
                        bulletPoint(L10n.tr("Yêu cầu xóa vĩnh viễn tài khoản và toàn bộ dữ liệu trong Hồ sơ cá nhân."))
                    }
                    .padding(.horizontal, 4)

                    if let privacyUrl = URL(string: "https://kinnect.io.vn/privacy") {
                        Link(destination: privacyUrl) {
                            HStack(spacing: 6) {
                                Text(L10n.tr("Xem chính sách quyền riêng tư đầy đủ"))
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
                                    Text(L10n.tr("Tôi đồng ý & Tiếp tục"))
                                        .font(.subheadline.bold())
                                }
                                Spacer()
                            }
                            .frame(minHeight: 46)
                            .background(Capsule().fill(KinnectTheme.primaryGradient))
                            .foregroundColor(.white)
                        }
                        .disabled(isSubmitting)

                        Button(L10n.tr("Để sau")) {
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
                    KinnectIconButton(glyph: .close, label: L10n.tr("Đóng"), tint: KinnectTheme.textPrimary) {
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
        guard recordOnServer else {
            onAccepted()
            dismiss()
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/me/privacy-consent",
                method: "POST",
                body: ["accepted": true, "version": request.version]
            )
            appState.pendingPrivacyConsent = nil
            appState.showToast(L10n.tr("Đã ghi nhận sự đồng ý của bạn."))
            onAccepted()
            dismiss()
        } catch {
            appState.showToast("\(L10n.tr("Không thể lưu:")) \(error.localizedDescription)")
        }
    }
}

