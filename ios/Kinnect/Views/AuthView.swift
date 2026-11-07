import SwiftUI

struct AuthView: View {
    @ObservedObject private var appState = AppState.shared

    enum AuthMode: String, CaseIterable {
        case login = "Đăng nhập"
        case register = "Đăng ký"
        case reset = "Quên mật khẩu"
    }

    @State private var mode: AuthMode = .login
    @State private var identifier = ""
    @State private var fullName = ""
    @State private var handle = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var rememberMe: Bool = UserDefaults.standard.object(forKey: "kinnect_session_remembered") as? Bool ?? true
    @State private var agree18 = true
    @State private var acceptPrivacy = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Brand Header
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(KinnectTheme.primaryGradient)
                            .frame(width: 84, height: 84)
                            .shadow(color: KinnectTheme.accent.opacity(0.5), radius: 16, y: 6)

                        Text("K")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 24)

                    Text("Kinnect")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Kết nối bạn bè, trò chuyện, gọi video & xem Live")
                        .font(.subheadline)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .kinnectMultiline()
                }

                // Mode Picker
                Picker("Chế độ", selection: $mode) {
                    ForEach(AuthMode.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _ in
                    errorMessage = nil
                    infoMessage = nil
                }

                // Form Card
                VStack(alignment: .leading, spacing: 14) {
                    if mode == .register {
                        fieldBlock(title: "Tên hiển thị", placeholder: "Ví dụ: Minh Anh", text: $fullName)
                        fieldBlock(title: "Handle (@tên_người_dùng)", placeholder: "minhanh", text: $handle)
                            .textInputAutocapitalization(.never)
                    }

                    fieldBlock(
                        title: mode == .register ? "Email hoặc Số điện thoại" : "Tài khoản (Email / SĐT / Handle)",
                        placeholder: "nhap@email.com hoặc 09xxxxxxxx",
                        text: $identifier
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                    if mode != .reset {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                KinnectIcon(glyph: .lock, size: 16, tint: KinnectTheme.textSecondary)
                                Text("Mật khẩu")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(KinnectTheme.textSecondary)
                            }
                            HStack(spacing: 4) {
                                Group {
                                    if showPassword {
                                        TextField("Nhập mật khẩu (tối thiểu 6 ký tự)", text: $password)
                                    } else {
                                        SecureField("Nhập mật khẩu (tối thiểu 6 ký tự)", text: $password)
                                    }
                                }
                                .padding(.leading, 12)
                                .padding(.vertical, 12)
                                .foregroundColor(KinnectTheme.textPrimary)

                                KinnectIconButton(
                                    glyph: showPassword ? .eyeOff : .eye,
                                    label: showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu",
                                    tint: KinnectTheme.textSecondary
                                ) {
                                    showPassword.toggle()
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                        }

                        if mode == .login {
                            HStack {
                                Toggle("Ghi nhớ", isOn: $rememberMe)
                                    .toggleStyle(.switch)
                                    .tint(KinnectTheme.accentBright)
                                    .font(.footnote)
                                    .foregroundColor(KinnectTheme.textPrimary)

                                Spacer()

                                Button("Quên mật khẩu?") {
                                    mode = .reset
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }

                    if mode == .register {
                        Toggle(isOn: $agree18) {
                            Text("Tôi xác nhận đủ 18 tuổi trở lên")
                                .font(.footnote)
                                .foregroundColor(KinnectTheme.textPrimary)
                                .kinnectMultiline()
                        }
                        .tint(KinnectTheme.accentBright)

                        Toggle(isOn: $acceptPrivacy) {
                            HStack(spacing: 6) {
                                KinnectIcon(glyph: .shield, size: 16, tint: KinnectTheme.accentBright)
                                Text("Tôi đồng ý với Chính sách quyền riêng tư & Điều khoản cộng đồng Kinnect")
                                    .font(.footnote)
                                    .foregroundColor(KinnectTheme.textPrimary)
                                    .kinnectMultiline()
                            }
                        }
                        .tint(KinnectTheme.accentBright)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundColor(KinnectTheme.danger)
                            .kinnectMultiline()
                    }

                    if let infoMessage {
                        Text(infoMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundColor(KinnectTheme.online)
                            .kinnectMultiline()
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode.rawValue)
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(KinnectTheme.primaryGradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSubmitting)

                    Text("Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng.")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .kinnectCard()

                #if DEBUG
                // Server Origin status (visible in debug builds only)
                HStack(spacing: 6) {
                    Circle()
                        .fill(KinnectTheme.online)
                        .frame(width: 8, height: 8)
                    Text("Máy chủ: \(ServerConfig.currentOrigin)")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                        .kinnectMultiline()
                }
                .padding(.bottom, 24)
                #endif
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .background(KinnectTheme.background.ignoresSafeArea())
    }

    private func fieldBlock(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(KinnectTheme.textSecondary)
            TextField(placeholder, text: text)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                .foregroundColor(KinnectTheme.textPrimary)
        }
    }

    private func submit() async {
        errorMessage = nil
        infoMessage = nil
        let cleanId = identifier.trimmingCharacters(inBounds: true)
        guard !cleanId.isEmpty else {
            errorMessage = "Vui lòng nhập thông tin tài khoản."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            switch mode {
            case .login:
                guard !password.isEmpty else {
                    errorMessage = "Vui lòng nhập mật khẩu."
                    return
                }
                let res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/login",
                    method: "POST",
                    body: [
                        "identifier": cleanId,
                        "email": cleanId,
                        "password": password,
                        "remember": rememberMe
                    ]
                )
                if let userDict = res["user"] as? [String: Any] {
                    let user = KinnectUser.from(userDict)
                    appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: rememberMe)
                    await appState.refreshGlobalBadges()
                    await appState.refreshBlockedUsers()
                }

            case .register:
                let cleanName = fullName.trimmingCharacters(inBounds: true)
                guard !cleanName.isEmpty else {
                    errorMessage = "Vui lòng nhập tên hiển thị."
                    return
                }
                guard password.count >= 6 else {
                    errorMessage = "Mật khẩu cần tối thiểu 6 ký tự."
                    return
                }
                guard agree18 && acceptPrivacy else {
                    errorMessage = "Bạn cần xác nhận đủ 18 tuổi và đồng ý Chính sách quyền riêng tư."
                    return
                }
                var payload: [String: Any] = [
                    "name": cleanName,
                    "password": password,
                    "agree18": true,
                    "acceptPrivacyNotice": true
                ]
                if cleanId.contains("@") {
                    payload["email"] = cleanId
                } else {
                    payload["phone"] = cleanId
                }
                let cleanHandle = handle.trimmingCharacters(inBounds: true)
                if !cleanHandle.isEmpty {
                    payload["handle"] = cleanHandle
                }
                payload["remember"] = true
                let res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/register",
                    method: "POST",
                    body: payload
                )
                if let userDict = res["user"] as? [String: Any] {
                    let user = KinnectUser.from(userDict)
                    appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: true)
                    await appState.refreshGlobalBadges()
                }

            case .reset:
                let res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/password-reset",
                    method: "POST",
                    body: ["identifier": cleanId]
                )
                let msg = res["message"] as? String ?? "Đã gửi yêu cầu khôi phục mật khẩu."
                infoMessage = msg
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    func trimmingCharacters(inBounds: Bool) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

