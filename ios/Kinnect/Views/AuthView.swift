import SwiftUI
import AuthenticationServices

enum AuthStage {
    case welcome
    case login
    case register
    case forgotPassword
}

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var oauth = OAuthManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var stage: AuthStage

    init(initialStage: AuthStage = .welcome) {
        _stage = State(initialValue: initialStage)
    }

    // Login Form State
    @State private var loginUsername = ""
    @State private var loginPassword = ""
    @State private var showLoginPassword = false
    @State private var rememberLogin = true

    // Register Form State
    @State private var regName = ""
    @State private var regUsername = ""
    @State private var regPassword = ""
    @State private var showRegPassword = false
    @State private var agree18 = false
    @State private var agreePrivacy = false

    // Forgot Password State
    @State private var forgotUsername = ""

    // UI Feedback
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var showPrivacySheet = false

    var body: some View {
        ZStack {
            KinnectTheme.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    #if DEBUG
                    if UIReviewFixture.isEnabled {
                        HStack {
                            Text("Mock CI Active")
                                .font(.caption2.bold())
                                .foregroundColor(.yellow)
                            Spacer()
                            Text("origin: \(ServerConfig.currentOrigin)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                    #endif

                    switch stage {
                    case .welcome:
                        welcomeView
                            .transition(.opacity)
                    case .login:
                        loginView
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case .register:
                        registerView
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    case .forgotPassword:
                        forgotView
                            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            if UIReviewFixture.activeScreen == "auth-login" {
                stage = .login
            } else if UIReviewFixture.activeScreen == "auth-register" {
                stage = .register
            } else if UIReviewFixture.activeScreen == "auth-forgot" {
                stage = .forgotPassword
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyConsentSheet(
                request: PrivacyConsentRequest(
                    version: "2026.11",
                    notice: L10n.tr("Chính sách quyền riêng tư và bảo mật dữ liệu Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.")
                ),
                recordOnServer: false,
                onAccepted: {
                    showPrivacySheet = false
                }
            )
        }
    }

    // MARK: - 1. Welcome & Feature Intro View
    private var welcomeView: some View {
        VStack(spacing: 24) {
            // App Branding Banner
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title2.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                    Text("Kinnect")
                        .font(.largeTitle.bold())
                        .foregroundColor(KinnectTheme.textPrimary)
                }

                Text(L10n.tr("Kết nối đúng gu.\nSống đúng mình."))
                    .font(.title3.weight(.medium))
                    .foregroundColor(KinnectTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            // Feature Highlights
            VStack(spacing: 12) {
                featureShowcaseCard(
                    icon: "bubble.left.and.bubble.right.fill",
                    title: loc.currentLanguage == .en ? "Direct Connections" : "Kết nối bạn bè",
                    desc: loc.currentLanguage == .en ? "End-to-end private messaging & audio/video calls." : "Nhắn tin và gọi điện thoại, video mượt mà, bảo mật."
                )
                featureShowcaseCard(
                    icon: "camera.viewfinder",
                    title: loc.currentLanguage == .en ? "Studio Pro" : "Studio sáng tạo Pro",
                    desc: loc.currentLanguage == .en ? "Color grading, edge-preserving smoothing & HD video export." : "Bộ lọc màu điện ảnh, làm mịn da bảo toàn chi tiết và xuất video HD."
                )
                featureShowcaseCard(
                    icon: "video.badge.waveform.fill",
                    title: loc.currentLanguage == .en ? "Livestream & Interactive" : "Livestream & Tương tác",
                    desc: loc.currentLanguage == .en ? "Real-time room broadcasting, virtual gifts & WebRTC signaling." : "Phát trực tiếp chất lượng cao, tặng quà tương tác và kết nối."
                )
            }

            // Primary Call-to-Actions
            VStack(spacing: 12) {
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .register
                    }
                } label: {
                    HStack {
                        Text(L10n.tr("Bắt đầu kết nối"))
                            .font(.headline.bold())
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(KinnectTheme.primaryGradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .login
                    }
                } label: {
                    Text(L10n.tr("Đăng nhập"))
                        .font(.headline.weight(.semibold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).stroke(KinnectTheme.border, lineWidth: 1.5))
                }
            }
            .padding(.top, 8)

            // Age & Policy Notice
            VStack(spacing: 6) {
                Text(L10n.tr("Dành cho người từ 18 tuổi · Minh họa tính năng"))
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)

                HStack(spacing: 4) {
                    Text(L10n.tr("Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng."))
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                }

                HStack(spacing: 6) {
                    Link(destination: URL(string: "https://kinnect.io.vn/community")!) {
                        Text(L10n.tr("Quy tắc cộng đồng"))
                            .font(.caption2.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    Text("&")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Link(destination: URL(string: "https://kinnect.io.vn/privacy")!) {
                        Text(L10n.tr("Chính sách quyền riêng tư"))
                            .font(.caption2.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 16)
        }
    }

    private func featureShowcaseCard(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(KinnectTheme.accentBright)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(desc)
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
    }

    // MARK: - 2. Login View
    private var loginView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header Bar
            HStack {
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .welcome
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(L10n.tr("Trang chủ"))
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.accentBright)
                }

                Spacer()

                // Language switch toggle
                Button {
                    loc.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption)
                        Text(loc.currentLanguage.shortLabel)
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("Chào bạn trở lại!"))
                    .font(.title2.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(L10n.tr("Đăng nhập để tiếp tục những kết nối của bạn."))
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
            }

            // Input Fields
            VStack(spacing: 12) {
                TextField(L10n.tr("Tài khoản hoặc email"), text: $loginUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)

                HStack {
                    if showLoginPassword {
                        TextField(L10n.tr("Mật khẩu"), text: $loginPassword)
                    } else {
                        SecureField(L10n.tr("Mật khẩu"), text: $loginPassword)
                    }
                    Button {
                        showLoginPassword.toggle()
                    } label: {
                        Image(systemName: showLoginPassword ? "eye.slash" : "eye")
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                .foregroundColor(KinnectTheme.textPrimary)
            }

            // Options Row: Remember Me & Forgot Password
            HStack {
                Button {
                    rememberLogin.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: rememberLogin ? "checkmark.square.fill" : "square")
                            .foregroundColor(rememberLogin ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        Text(L10n.tr("Ghi nhớ đăng nhập"))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }

                Spacer()

                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .forgotPassword
                    }
                } label: {
                    Text(L10n.tr("Quên mật khẩu?"))
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.danger)
            }

            // Primary Login Button
            Button {
                Task { await performLogin() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white).padding(.trailing, 6)
                    }
                    Text(L10n.tr("Đăng nhập"))
                        .font(.headline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(KinnectTheme.primaryGradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isLoading || loginUsername.isEmpty || loginPassword.isEmpty)

            // Switch to Register
            HStack {
                Spacer()
                Text(L10n.tr("Chưa có tài khoản?"))
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .register
                    }
                } label: {
                    Text(L10n.tr("Tạo tài khoản mới"))
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                }
                Spacer()
            }
            .padding(.top, 4)

            // Social Logins (Sign in with Apple, Google, Facebook)
            socialAuthSection
        }
    }

    // MARK: - 3. Register View
    private var registerView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header Bar
            HStack {
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .welcome
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(L10n.tr("Trang chủ"))
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.accentBright)
                }

                Spacer()

                Button {
                    loc.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption)
                        Text(loc.currentLanguage.shortLabel)
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("Bắt đầu kết nối của bạn."))
                    .font(.title2.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(L10n.tr("Tạo tài khoản để chia sẻ và gặp người cùng tần số."))
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
            }

            // Input Fields
            VStack(spacing: 12) {
                TextField(L10n.tr("Tên hiển thị"), text: $regName)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)

                TextField(L10n.tr("Tên đăng nhập (3-30 ký tự)"), text: $regUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .foregroundColor(KinnectTheme.textPrimary)

                HStack {
                    if showRegPassword {
                        TextField(L10n.tr("Mật khẩu (ít nhất 6 ký tự)"), text: $regPassword)
                    } else {
                        SecureField(L10n.tr("Mật khẩu (ít nhất 6 ký tự)"), text: $regPassword)
                    }
                    Button {
                        showRegPassword.toggle()
                    } label: {
                        Image(systemName: showRegPassword ? "eye.slash" : "eye")
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                .foregroundColor(KinnectTheme.textPrimary)
            }

            // Mandatory Checkboxes: 18+ and Privacy
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    agree18.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: agree18 ? "checkmark.square.fill" : "square")
                            .foregroundColor(agree18 ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        Text(L10n.tr("Tôi xác nhận mình đủ 18 tuổi và đồng ý với quy tắc cộng đồng."))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Button {
                    agreePrivacy.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: agreePrivacy ? "checkmark.square.fill" : "square")
                            .foregroundColor(agreePrivacy ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        Text(L10n.tr("Tôi đồng ý với Chính sách quyền riêng tư & Điều khoản Kinnect."))
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Button {
                    showPrivacySheet = true
                } label: {
                    Text(L10n.tr("Đọc toàn văn chính sách bảo vệ dữ liệu"))
                        .font(.caption2.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                        .padding(.leading, 26)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.danger)
            }

            // Primary Register Button
            Button {
                Task { await performRegister() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white).padding(.trailing, 6)
                    }
                    Text(L10n.tr("Tạo tài khoản"))
                        .font(.headline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(KinnectTheme.primaryGradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isLoading || !agree18 || !agreePrivacy || regUsername.isEmpty || regPassword.count < 6)

            // Switch to Login
            HStack {
                Spacer()
                Text(L10n.tr("Đã có tài khoản?"))
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .login
                    }
                } label: {
                    Text(L10n.tr("Đăng nhập ngay"))
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                }
                Spacer()
            }
            .padding(.top, 4)

            socialAuthSection
        }
    }

    // MARK: - 4. Forgot Password View
    private var forgotView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header Bar
            HStack {
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .login
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(L10n.tr("Quay lại đăng nhập"))
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(KinnectTheme.accentBright)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("Quên mật khẩu"))
                    .font(.title2.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(L10n.tr("Chúng tôi sẽ gửi mã xác minh hoặc hướng dẫn tới email khôi phục của bạn."))
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
            }

            TextField(L10n.tr("Tên đăng nhập hoặc email"), text: $forgotUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                .foregroundColor(KinnectTheme.textPrimary)

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.danger)
            }
            if let info = infoMessage {
                Text(info)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.online)
            }

            Button {
                Task { await performForgot() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView().tint(.white).padding(.trailing, 6)
                    }
                    Text(L10n.tr("Gửi mã qua email"))
                        .font(.headline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(KinnectTheme.primaryGradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isLoading || forgotUsername.isEmpty)

            HStack {
                Spacer()
                Text(L10n.tr("Chưa có email khôi phục?"))
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                Link(destination: URL(string: "https://kinnect.io.vn/support")!) {
                    Text(L10n.tr("Gửi yêu cầu hỗ trợ"))
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                }
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    // MARK: - 5. Social Auth Section (Apple Guideline 4.8 Compliance)
    private var socialAuthSection: some View {
        VStack(spacing: 12) {
            HStack {
                Rectangle().fill(KinnectTheme.border).frame(height: 1)
                Text(L10n.tr("hoặc tiếp tục với mạng xã hội"))
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .padding(.horizontal, 8)
                Rectangle().fill(KinnectTheme.border).frame(height: 1)
            }
            .padding(.vertical, 8)

            // Native Sign In with Apple (Guideline 4.8)
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: handleAppleSignIn
            )
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(L10n.tr("Đăng nhập bằng Apple"))

            // Google & Facebook Social Login Buttons
            HStack(spacing: 12) {
                Button {
                    oauth.startOAuth(provider: "google") { res in
                        switch res {
                        case .success(let user):
                            appState.applyAuthenticatedUser(user, rawDict: [:], rememberMe: true)
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("G")
                            .font(.headline.bold())
                            .foregroundColor(.red)
                        Text(L10n.tr("Tiếp tục với Google"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(KinnectTheme.border, lineWidth: 1))
                }

                Button {
                    oauth.startOAuth(provider: "facebook") { res in
                        switch res {
                        case .success(let user):
                            appState.applyAuthenticatedUser(user, rawDict: [:], rememberMe: true)
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("f")
                            .font(.headline.bold())
                            .foregroundColor(.blue)
                        Text(L10n.tr("Tiếp tục với Facebook"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(KinnectTheme.border, lineWidth: 1))
                }
            }

            if let oauthErr = oauth.oauthError {
                Text(oauthErr)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.warning)
            }
        }
    }

    // MARK: - Actions & Handlers
    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Không nhận diện được chứng chỉ Apple."
                return
            }
            let userIdentifier = appleIDCredential.user
            // Do NOT fabricate privaterelay email: use what Apple actually returned or empty string
            let email = appleIDCredential.email ?? ""
            let givenName = appleIDCredential.fullName?.givenName ?? ""
            let familyName = appleIDCredential.fullName?.familyName ?? ""
            let fullName = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let nameToUse = fullName.isEmpty ? (email.isEmpty ? "Apple User" : email.components(separatedBy: "@").first ?? "Apple User") : fullName

            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityTokenStr = String(data: identityTokenData, encoding: .utf8),
                  !identityTokenStr.isEmpty else {
                errorMessage = L10n.tr("Không nhận được token xác thực từ Apple.")
                return
            }

            Task {
                do {
                    let res = try await KinnectAPIClient.shared.requestJSON(
                        "/api/auth/apple",
                        method: "POST",
                        body: [
                            "appleId": userIdentifier,
                            "email": email,
                            "fullName": nameToUse,
                            "identityToken": identityTokenStr
                        ]
                    )
                    if let userDict = res["user"] as? [String: Any] {
                        let user = KinnectUser.from(userDict)
                        appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: true)
                        await appState.refreshGlobalBadges()
                    }
                } catch {
                    if UIReviewFixture.isEnabled {
                        appState.applyAuthenticatedUser(KinnectUser.from(UIReviewFixture.currentUserDict), rawDict: UIReviewFixture.currentUserDict, rememberMe: true)
                    } else {
                        errorMessage = "Apple Sign-In: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            let nsErr = error as NSError
            if nsErr.domain == ASAuthorizationError.errorDomain && nsErr.code == ASAuthorizationError.canceled.rawValue {
                // User intentionally cancelled: ignore quietly
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func performLogin() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/login",
                method: "POST",
                body: [
                    "username": loginUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    "password": loginPassword,
                    "remember": rememberLogin
                ]
            )
            if let userDict = res["user"] as? [String: Any] {
                let user = KinnectUser.from(userDict)
                appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: rememberLogin)
                await appState.refreshGlobalBadges()
            }
        } catch {
            if UIReviewFixture.isEnabled {
                appState.applyAuthenticatedUser(KinnectUser.from(UIReviewFixture.currentUserDict), rawDict: UIReviewFixture.currentUserDict, rememberMe: true)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performRegister() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/register",
                method: "POST",
                body: [
                    "name": regName.trimmingCharacters(in: .whitespacesAndNewlines),
                    "username": regUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    "password": regPassword,
                    "agree18": agree18,
                    "acceptPrivacyNotice": agreePrivacy
                ]
            )
            if let userDict = res["user"] as? [String: Any] {
                let user = KinnectUser.from(userDict)
                appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: true)
                await appState.refreshGlobalBadges()
            }
        } catch {
            if UIReviewFixture.isEnabled {
                appState.applyAuthenticatedUser(KinnectUser.from(UIReviewFixture.currentUserDict), rawDict: UIReviewFixture.currentUserDict, rememberMe: true)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performForgot() async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/password-reset",
                method: "POST",
                body: [
                    "username": forgotUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    "contact": forgotUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                    "note": "iOS App password reset request"
                ]
            )
            infoMessage = loc.currentLanguage == .en
                ? "Password reset request sent. Check your recovery email."
                : "Yêu cầu khôi phục mật khẩu đã được gửi. Vui lòng kiểm tra email của bạn."
        } catch {
            if UIReviewFixture.isEnabled {
                infoMessage = loc.currentLanguage == .en ? "Demo verification code dispatched." : "Đã gửi mã minh họa thành công."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
