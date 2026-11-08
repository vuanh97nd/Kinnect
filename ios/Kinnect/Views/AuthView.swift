import SwiftUI
import AuthenticationServices
import CryptoKit
import UIKit
#if DEBUG && targetEnvironment(simulator)
import Darwin
#endif

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
    @State private var currentAppleNonce: String = ""

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
    @State private var showLoginLanguageSheet = false
    @FocusState private var focusedLoginField: LoginField?

    private enum LoginField: Hashable {
        case username
        case password
    }

    var body: some View {
        ZStack {
            Group {
                if stage == .login {
                    LoginChrome.background
                } else {
                    KinnectTheme.background
                }
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    #if DEBUG
                    if UIReviewFixture.isEnabled && stage != .login {
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
            if let screen = UIReviewFixture.activeScreen {
                loc.setLanguage(screen == "auth-login-en" ? .en : .vi)
                if screen.hasPrefix("auth-login") {
                    stage = .login
                    switch screen {
                    case "auth-login-populated":
                        loginUsername = "minhanh"
                        loginPassword = "kinnect2026"
                        rememberLogin = true
                        errorMessage = nil
                    case "auth-login-error":
                        loginUsername = "minhanh"
                        loginPassword = "123456"
                        rememberLogin = true
                        errorMessage = L10n.tr("Tên đăng nhập hoặc mật khẩu không đúng.")
                    case "auth-login-keyboard":
                        loginUsername = ""
                        loginPassword = ""
                        errorMessage = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            focusedLoginField = .username
                            #if DEBUG && targetEnvironment(simulator)
                            activateSimulatorSoftwareKeyboard()
                            #endif
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            focusedLoginField = .username
                            #if DEBUG && targetEnvironment(simulator)
                            activateSimulatorSoftwareKeyboard()
                            #endif
                        }
                    case "auth-login-lang-sheet":
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showLoginLanguageSheet = true
                        }
                    default:
                        loginUsername = ""
                        loginPassword = ""
                        errorMessage = nil
                    }
                } else if screen == "auth-register" {
                    stage = .register
                } else if screen == "auth-forgot" || screen == "auth-reset" {
                    stage = .forgotPassword
                }
            }
        }
        .sheet(isPresented: $showLoginLanguageSheet) {
            loginLanguageSheet
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

    // MARK: - 2. Login View (Android 1.2.12 build 118 hierarchy)
    private var loginView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Image("KinnectLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text("Kinnect")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(LoginChrome.purple)
                Spacer(minLength: 8)
                Text(L10n.tr("Sống đúng mình."))
                    .font(.system(size: 13))
                    .foregroundColor(LoginChrome.muted)
                    .lineLimit(1)
            }

            Button {
                errorMessage = nil
                infoMessage = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    stage = .welcome
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(L10n.tr("Trang chủ"))
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(LoginChrome.ink)
            }
            .padding(.top, 4)

            Button {
                showLoginLanguageSheet = true
            } label: {
                Text(L10n.tr("Tiếng Việt / English"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(LoginChrome.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 21).fill(LoginChrome.wash))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Chào bạn trở lại!"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(LoginChrome.ink)
                Text(L10n.tr("Đăng nhập để tiếp tục những kết nối của bạn."))
                    .font(.system(size: 14))
                    .foregroundColor(LoginChrome.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)

            HStack(spacing: 10) {
                loginProviderButton(title: "Google", asset: "BrandGoogle") {
                    oauth.startOAuth(provider: "google") { res in
                        switch res {
                        case .success(let user):
                            appState.applyAuthenticatedUser(user, rawDict: [:], rememberMe: true)
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    }
                }
                loginProviderButton(title: "Facebook", asset: "BrandFacebook") {
                    oauth.startOAuth(provider: "facebook") { res in
                        switch res {
                        case .success(let user):
                            appState.applyAuthenticatedUser(user, rawDict: [:], rememberMe: true)
                        case .failure(let err):
                            errorMessage = err.localizedDescription
                        }
                    }
                }
            }

            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                    let rawNonce = UUID().uuidString + "-" + UUID().uuidString
                    currentAppleNonce = rawNonce
                    let hashedData = SHA256.hash(data: Data(rawNonce.utf8))
                    request.nonce = hashedData.compactMap { String(format: "%02x", $0) }.joined()
                },
                onCompletion: handleAppleSignIn
            )
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .accessibilityLabel(L10n.tr("Đăng nhập bằng Apple"))

            if let oauthErr = oauth.oauthError {
                Text(oauthErr)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.warning)
            }

            loginDivider(L10n.tr("hoặc tiếp tục với mật khẩu"))

            loginCredentialField(
                systemImage: "person",
                placeholder: L10n.tr("Tên đăng nhập"),
                text: $loginUsername,
                secure: false,
                field: .username,
                trailing: { EmptyView() }
            )

            loginCredentialField(
                systemImage: "lock",
                placeholder: L10n.tr("Mật khẩu (từ 6 ký tự)"),
                text: $loginPassword,
                secure: !showLoginPassword,
                field: .password,
                trailing: {
                    Button {
                        showLoginPassword.toggle()
                    } label: {
                        Image(systemName: showLoginPassword ? "eye.slash" : "eye")
                            .foregroundColor(LoginChrome.muted)
                    }
                }
            )

            HStack {
                Button {
                    rememberLogin.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: rememberLogin ? "checkmark.square.fill" : "square")
                            .foregroundColor(rememberLogin ? LoginChrome.purple : LoginChrome.muted)
                        Text(L10n.tr("Ghi nhớ"))
                            .font(.system(size: 14))
                            .foregroundColor(LoginChrome.ink)
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(LoginChrome.purple)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(LoginChrome.danger)
            }

            Button {
                Task { await performLogin() }
            } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                    Text(L10n.tr("Đăng nhập"))
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(LoginChrome.purple))
                .foregroundColor(.white)
            }
            .disabled(isLoading || loginUsername.isEmpty || loginPassword.isEmpty)

            loginDivider(L10n.tr("Mới đến Kinnect?"))
                .padding(.top, 4)

            Button {
                errorMessage = nil
                infoMessage = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    stage = .register
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                    Text(L10n.tr("Tạo tài khoản mới"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(LoginChrome.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(LoginChrome.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(LoginChrome.line, lineWidth: 1)
                        )
                )
            }

            Text(L10n.tr("Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng."))
                .font(.system(size: 12))
                .foregroundColor(LoginChrome.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

    private var loginLanguageSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(LoginChrome.line)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text(L10n.tr("Ngôn ngữ ứng dụng"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(LoginChrome.ink)

            ForEach(AppLanguage.allCases) { language in
                Button {
                    loc.setLanguage(language)
                    showLoginLanguageSheet = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundColor(LoginChrome.purple)
                        Text(language.displayName)
                            .font(.system(size: 17))
                            .foregroundColor(LoginChrome.ink)
                        Spacer()
                        if loc.currentLanguage == language {
                            Image(systemName: "checkmark")
                                .foregroundColor(LoginChrome.purple)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Button {
                showLoginLanguageSheet = false
            } label: {
                Text(L10n.tr("Đóng"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(LoginChrome.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 23)
                            .fill(LoginChrome.card)
                            .overlay(RoundedRectangle(cornerRadius: 23).stroke(LoginChrome.line, lineWidth: 1))
                    )
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LoginChrome.background.ignoresSafeArea())
        .presentationDetents([.height(320)])
    }

    private func loginDivider(_ title: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(LoginChrome.line).frame(height: 1)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(LoginChrome.muted)
                .fixedSize()
            Rectangle().fill(LoginChrome.line).frame(height: 1)
        }
    }

    private func loginProviderButton(title: String, asset: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(LoginChrome.ink)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(LoginChrome.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(LoginChrome.line, lineWidth: 1)
                    )
            )
        }
    }

    private func loginCredentialField<Trailing: View>(
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        secure: Bool,
        field: LoginField,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let focused = focusedLoginField == field
        return HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundColor(focused ? LoginChrome.purple : LoginChrome.muted)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .focused($focusedLoginField, equals: field)
            .foregroundColor(LoginChrome.ink)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LoginChrome.wash)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focused ? LoginChrome.purple : LoginChrome.line, lineWidth: focused ? 1.5 : 1)
                )
        )
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

            // Native Sign In with Apple (Guideline 4.8) with cryptographic request-bound nonce
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                    let rawNonce = UUID().uuidString + "-" + UUID().uuidString
                    currentAppleNonce = rawNonce
                    let hashedData = SHA256.hash(data: Data(rawNonce.utf8))
                    request.nonce = hashedData.compactMap { String(format: "%02x", $0) }.joined()
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
                    var appleBody: [String: Any] = [
                        "appleId": userIdentifier,
                        "email": email,
                        "fullName": nameToUse,
                        "identityToken": identityTokenStr
                    ]
                    if !currentAppleNonce.isEmpty {
                        appleBody["nonce"] = currentAppleNonce
                    }
                    let res = try await KinnectAPIClient.shared.requestJSON(
                        "/api/auth/apple",
                        method: "POST",
                        body: appleBody
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

    #if DEBUG && targetEnvironment(simulator)
    private func disableSimulatorHardwareKeyboardMode() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW),
           let sym = dlsym(handle, "GSEventSetHardwareKeyboardAttached") {
            typealias Fn = @convention(c) (Bool, UInt8) -> Void
            let setAttached = unsafeBitCast(sym, to: Fn.self)
            setAttached(false, 0)
        }
        if let kbClass = NSClassFromString("UIKeyboardImpl") as? NSObject.Type,
           kbClass.responds(to: NSSelectorFromString("sharedInstance")),
           let kb = kbClass.perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue() as? NSObject {
            let sel = NSSelectorFromString("setInHardwareKeyboardMode:")
            if kb.responds(to: sel), let imp = kb.method(for: sel) {
                typealias SetModeFn = @convention(c) (AnyObject, Selector, Bool) -> Void
                let fn = unsafeBitCast(imp, to: SetModeFn.self)
                fn(kb, sel, false)
            }
            let showSel = NSSelectorFromString("showKeyboardIfNeeded")
            if kb.responds(to: showSel) {
                _ = kb.perform(showSel)
            }
        }
    }

    private func findFirstTextField(in view: UIView) -> UITextField? {
        if let tf = view as? UITextField {
            return tf
        }
        for sub in view.subviews {
            if let found = findFirstTextField(in: sub) {
                return found
            }
        }
        return nil
    }

    private func activateSimulatorSoftwareKeyboard() {
        disableSimulatorHardwareKeyboardMode()
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                if let tf = findFirstTextField(in: window) {
                    window.makeKeyAndVisible()
                    disableSimulatorHardwareKeyboardMode()
                    _ = tf.becomeFirstResponder()
                    disableSimulatorHardwareKeyboardMode()
                    tf.reloadInputViews()
                    return
                }
            }
        }
    }
    #endif
}

/// Login-only colors copied from `public/v2.css` `#kn` tokens.
/// Light values are the first `light-dark()` argument; dark values are the second.
private enum LoginChrome {
    static var background: Color { adaptive(light: 0xF6F5FA, dark: 0x151419) }
    static var card: Color { adaptive(light: 0xFFFFFF, dark: 0x222128) }
    static var wash: Color { adaptive(light: 0xF4F1FA, dark: 0x2C2833) }
    static var ink: Color { adaptive(light: 0x1F1D2B, dark: 0xF1EFF7) }
    static var muted: Color { adaptive(light: 0x6A6478, dark: 0xB1AABD) }
    static var line: Color { adaptive(light: 0xE4E0EC, dark: 0x38333F) }
    static var purple: Color { adaptive(light: 0x6C47E0, dark: 0x7652E8) }
    static var danger: Color { adaptive(light: 0xC2365A, dark: 0xD56579) }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            uiColor(trait.userInterfaceStyle == .light ? light : dark)
        })
    }

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
