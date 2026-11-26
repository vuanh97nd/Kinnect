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
    @ObservedObject private var appState = AppState.shared
    @StateObject private var oauth = OAuthManager.shared
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var stage: AuthStage
    @State private var currentAppleNonce: String = ""

    init(initialStage: AuthStage = .welcome) {
        _stage = State(initialValue: initialStage)
    }

    private struct PendingApple2FA {
        let appleId: String
        let email: String
        let fullName: String
        let identityToken: String
        let nonce: String
    }

    private struct PendingAppleConsent: Identifiable {
        let id = UUID()
        let appleId: String
        let email: String
        let fullName: String
        let identityToken: String
        let nonce: String
    }

    private struct PendingOAuthRegistration: Identifiable {
        let id = UUID()
        let ticket: String
        let provider: String
        let name: String
        let suggestedUsername: String
    }

    private struct RememberedAccount: Identifiable, Equatable {
        let id: String
        let username: String
        let name: String
    }

    // Login Form State
    @State private var loginUsername = ""
    @State private var loginPassword = ""
    @State private var loginTotpCode = ""
    @State private var needs2FA = false
    @State private var pendingOAuth2FACode: String? = nil
    @State private var pendingApple2FA: PendingApple2FA? = nil
    @State private var pendingAppleConsent: PendingAppleConsent? = nil
    @State private var pendingOAuthRegistration: PendingOAuthRegistration? = nil
    @State private var rememberedAccounts: [RememberedAccount] = []
    @State private var pendingRememberedAccount: RememberedAccount? = nil
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
    @State private var forgotContact = ""
    @State private var forgotChallengeId = ""
    @State private var forgotOtpCode = ""
    @State private var forgotNewPassword = ""
    @State private var showForgotFallbackButton = false
    @State private var showForgotAdminFields = false

    // UI Feedback
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var showPrivacySheet = false
    @State private var welcomePreview = 1
    @State private var welcomeShowcasePaused = false
    @State private var welcomeViewportHeight: CGFloat = 760
    @State private var showLoginLanguageSheet = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceWelcomeMotion
    @FocusState private var focusedLoginField: LoginField?

    private enum LoginField: Hashable {
        case username
        case password
    }

    var body: some View {
        ZStack {
            Group {
                if stage == .welcome {
                    LinearGradient(
                        colors: [KinnectTheme.accentSoft, KinnectTheme.background, KinnectTheme.background],
                        startPoint: .top, endPoint: .bottom
                    )
                } else {
                    KinnectTheme.background
                }
            }
            .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                    switch stage {
                    case .welcome:
                        welcomeView
                            .frame(minHeight: max(0, welcomeViewportHeight - 32))
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
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedLoginField) { field in
                    guard stage == .login, field != nil else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("login-submit", anchor: .bottom)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("login-submit", anchor: .bottom)
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("login-submit", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background {
            GeometryReader { viewport in
                Color.clear
                    .onAppear { welcomeViewportHeight = viewport.size.height }
                    .onChange(of: viewport.size.height) { welcomeViewportHeight = $0 }
            }
        }
        .onAppear {
            #if DEBUG
            if let screen = UIReviewFixture.activeScreen {
                loc.setLanguage(screen.hasSuffix("-en") ? .en : .vi)
                if let option = CommandLine.arguments.firstIndex(of: "--ui-review-welcome-tab"),
                   option + 1 < CommandLine.arguments.count,
                   let page = Int(CommandLine.arguments[option + 1]), (0..<4).contains(page) {
                    welcomePreview = page
                }
                if screen.hasPrefix("auth-welcome") || screen == "auth" {
                    stage = .welcome
                } else if screen.hasPrefix("auth-login") {
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
                            activateSimulatorSoftwareKeyboard(fieldIndex: 0)
                            #endif
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            focusedLoginField = .username
                            #if DEBUG && targetEnvironment(simulator)
                            activateSimulatorSoftwareKeyboard(fieldIndex: 0)
                            #endif
                        }
                    case "auth-login-password-keyboard":
                        loginUsername = "minhanh"
                        loginPassword = "kinnect2026"
                        rememberLogin = true
                        errorMessage = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            focusedLoginField = .password
                            #if DEBUG && targetEnvironment(simulator)
                            activateSimulatorSoftwareKeyboard(fieldIndex: 1)
                            #endif
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            focusedLoginField = .password
                            #if DEBUG && targetEnvironment(simulator)
                            activateSimulatorSoftwareKeyboard(fieldIndex: 1)
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
            #endif
        }
        .task {
            await loadRememberedAccounts()
        }
        .sheet(isPresented: $showLoginLanguageSheet) {
            loginLanguageSheet
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyConsentSheet(
                request: PrivacyConsentRequest(
                    version: "2026-10-29",
                    notice: L10n.tr("Chính sách quyền riêng tư và bảo mật dữ liệu Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.")
                ),
                recordOnServer: false,
                onAccepted: {
                    agreePrivacy = true
                    showPrivacySheet = false
                }
            )
        }
        .sheet(item: $pendingAppleConsent) { pending in
            AppleAgeConsentSheet { confirmed in
                pendingAppleConsent = nil
                guard confirmed else { return }
                agree18 = true
                agreePrivacy = true
                Task {
                    await submitAppleSignIn(
                        appleId: pending.appleId,
                        email: pending.email,
                        fullName: pending.fullName,
                        identityToken: pending.identityToken,
                        nonce: pending.nonce,
                        confirmed18: true,
                        recordPrivacyConsent: true
                    )
                }
            }
        }
        .sheet(item: $pendingOAuthRegistration) { pending in
            OAuthCompleteRegistrationSheet(
                ticket: pending.ticket,
                provider: pending.provider,
                initialName: pending.name,
                suggestedUsername: pending.suggestedUsername,
                rememberMe: rememberLogin
            ) {
                pendingOAuthRegistration = nil
            }
        }
    }

    // MARK: - 1. Welcome (Android intro hierarchy)
    private var welcomeView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image("KinnectLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Kinnect")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(KinnectTheme.accentBright)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    showLoginLanguageSheet = true
                } label: {
                    Text("VI / EN")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(KinnectTheme.textPrimary)
                        .frame(minWidth: 56, minHeight: 44)
                }
                .accessibilityLabel(L10n.tr("Ngôn ngữ ứng dụng"))
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) { stage = .login }
                } label: {
                    Text(L10n.tr("Đăng nhập"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.accentBright))
                }
            }
            .frame(height: 48)

            Text(L10n.tr("Kết nối đúng gu.\nSống đúng mình."))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(KinnectTheme.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 84)
                .padding(.top, 8)

            welcomePhoneShowcase
                .frame(maxWidth: .infinity)
                .frame(height: max(360, welcomeViewportHeight - 280))
                .padding(.vertical, 8)

            Button {
                errorMessage = nil
                infoMessage = nil
                withAnimation(.easeInOut(duration: 0.2)) { stage = .register }
            } label: {
                Text(L10n.tr("Bắt đầu kết nối"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KinnectTheme.primaryGradient))
            }

            Text(L10n.tr("Dành cho người từ 18 tuổi · Minh họa tính năng"))
                .font(.system(size: 11))
                .foregroundColor(KinnectTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text("Kinnect iOS v\(ServerConfig.appVersion) (Build \(ServerConfig.buildNumber))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(KinnectTheme.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

        }
        .task(id: reduceWelcomeMotion) {
            #if DEBUG
            let forceAutocycle = CommandLine.arguments.contains("--ui-review-welcome-autocycle")
            let fixtureEnabled = UIReviewFixture.isEnabled
            #else
            let forceAutocycle = false
            let fixtureEnabled = false
            #endif
            // Respect Reduce Motion unless UI review explicitly opts into autocycle.
            guard (!fixtureEnabled && !reduceWelcomeMotion) || forceAutocycle else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_500_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                guard !welcomeShowcasePaused || forceAutocycle else { continue }
                withAnimation(reduceWelcomeMotion ? nil : .easeInOut(duration: 0.3)) {
                    welcomePreview = (welcomePreview + 1) % 4
                }
            }
        }
    }

    // A fixed portrait design scaled as one unit; never stretch the phone to the page width.
    private var welcomePhoneShowcase: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 330, geometry.size.height / 450)
            ZStack {
                ForEach([280.0, 340.0, 400.0], id: \.self) { diameter in
                    Circle()
                        .stroke(KinnectTheme.accentBright.opacity(0.10), lineWidth: 1)
                        .frame(width: diameter, height: diameter)
                }
                welcomePhoneContent
                    .frame(width: 190, height: 409)
                    .background(RoundedRectangle(cornerRadius: 27).fill(KinnectTheme.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 27))
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 32).fill(Color.black))
                    .overlay(RoundedRectangle(cornerRadius: 32)
                        .stroke(Color(red: 0.65, green: 0.65, blue: 0.68), lineWidth: 2))
            }
            .frame(width: 330, height: 450)
            .scaleEffect(scale)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("Điện thoại minh họa luân phiên các tính năng Bảng tin, Khám phá, Video và Live. Chạm để chuyển tính năng."))

    }

    private var welcomePhoneContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                Text("9:41").font(.system(size: 8, weight: .bold))
                Spacer()
                Capsule().fill(Color.black).frame(width: 33, height: 11)
                Spacer()
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 7))
            .padding(.top, 12)
            HStack(spacing: 5) {
                Image("KinnectLogo").resizable().frame(width: 19, height: 19)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Kinnect").font(.system(size: 14, weight: .bold))
                    .foregroundColor(KinnectTheme.accentBright)
                Spacer()
                Image(systemName: "bell").font(.system(size: 11))
                Image("WelcomeProfile").resizable().scaledToFill()
                    .frame(width: 17, height: 17).clipShape(Circle())
            }
            HStack(spacing: 4) {
                Text(L10n.tr(["Bảng tin", "Khám phá", "Video", "Live"][welcomePreview]))
                    .font(.system(size: 8)).foregroundColor(KinnectTheme.textSecondary)
                Spacer()
                if !reduceWelcomeMotion {
                    Button {
                        welcomeShowcasePaused.toggle()
                    } label: {
                        Image(systemName: welcomeShowcasePaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(KinnectTheme.textSecondary)
                            .frame(width: 16, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr(welcomeShowcasePaused ? "Tiếp tục minh họa tự động" : "Tạm dừng minh họa tự động"))
                }
            }
            welcomePreviewPage
                .id(welcomePreview)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    welcomeShowcasePaused = true
                    withAnimation(reduceWelcomeMotion ? nil : .easeInOut(duration: 0.25)) {
                        welcomePreview = (welcomePreview + 1) % 4
                    }
                }
            HStack(spacing: 0) {
                welcomeMiniTab("house", title: "Bảng tin", index: 0)
                welcomeMiniTab("safari", title: "Khám phá", index: 1)
                Image(systemName: "plus").font(.system(size: 20))
                    .frame(width: 27, height: 27)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 9).fill(KinnectTheme.accentBright))
                welcomeMiniTab("play.rectangle", title: "Video", index: 2)
                welcomeMiniTab("dot.radiowaves.left.and.right", title: "Live", index: 3)
            }
            Capsule().fill(KinnectTheme.textSecondary.opacity(0.25)).frame(width: 57, height: 3)
                .padding(.bottom, 4)
        }
        .foregroundColor(KinnectTheme.textPrimary)
        .padding(.horizontal, 9)
    }

    private func welcomeMiniTab(_ icon: String, title: String, index: Int) -> some View {
        Button {
            welcomeShowcasePaused = true
            withAnimation(reduceWelcomeMotion ? nil : .easeInOut(duration: 0.25)) { welcomePreview = index }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 12))
                Text(L10n.tr(title)).font(.system(size: 6)).lineLimit(1)
            }
            .foregroundColor(welcomePreview == index ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr(title))
        .accessibilityAddTraits(welcomePreview == index ? [.isSelected] : [])
        .frame(maxWidth: .infinity)
    }

    // Explicit bounds keep every showcase page from center-cropping portrait faces.
    private func welcomePortrait(_ asset: String) -> some View {
        GeometryReader { geometry in
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
        }
    }

    @ViewBuilder
    private var welcomePreviewPage: some View {
        switch welcomePreview {
        case 1:
            VStack(spacing: 6) {
                HStack {
                    Text(L10n.tr("Dành cho bạn")).foregroundColor(KinnectTheme.accentBright)
                    Spacer()
                    Text(L10n.tr("Đang theo dõi"))
                }
                .font(.system(size: 7, weight: .semibold))
                .padding(6).background(RoundedRectangle(cornerRadius: 7).fill(KinnectTheme.surfaceElevated))
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    Text(L10n.tr("Tên đăng nhập"))
                    Spacer()
                }
                .font(.system(size: 8)).foregroundColor(KinnectTheme.textSecondary)
                .padding(7).background(RoundedRectangle(cornerRadius: 7).fill(KinnectTheme.surfaceElevated))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        VStack(spacing: 3) {
                            welcomePortrait(["WelcomeProfile", "WelcomeProfile1", "WelcomeProfile2", "WelcomeProfile3"][index])
                                .frame(width: 80, height: 72)
                            Text(["Minh Anh, 27", "Gia Huy, 28", "Hoàng Nam, 30", "Quang Minh, 26"][index])
                                .font(.system(size: 7, weight: .semibold)).lineLimit(1)
                                .padding(.bottom, 4)
                        }
                        .background(KinnectTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                Spacer(minLength: 0)
            }
        case 2:
            welcomePortrait("WelcomeProfile1")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) {
                    Text("@minhanh")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                }
        case 3:
            welcomePortrait("WelcomeProfile2")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(red: 0.86, green: 0.15, blue: 0.47)))
                        .padding(8)
                }
        default:
            VStack(alignment: .leading, spacing: 6) {
                // Story row: Tạo tin + Story Minh Anh (Android 1.2.12 MainActivity.java:4278)
                HStack(spacing: 8) {
                    VStack(spacing: 2) {
                        ZStack {
                            Circle()
                                .fill(KinnectTheme.surfaceElevated)
                                .frame(width: 26, height: 26)
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(KinnectTheme.accentBright)
                        }
                        Text(L10n.tr("Tạo tin"))
                            .font(.system(size: 7))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }

                    VStack(spacing: 2) {
                        Image("WelcomeProfile")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(KinnectTheme.accentBright, lineWidth: 1.5))
                        Text("Minh Anh")
                            .font(.system(size: 7))
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    Spacer()
                }

                // Composer box: Bạn đang nghĩ gì?
                HStack(spacing: 6) {
                    Image("WelcomeProfile")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                    Text(L10n.tr("Bạn đang nghĩ gì?"))
                        .font(.system(size: 8))
                        .foregroundColor(KinnectTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surfaceElevated))

                // Post Card
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image("WelcomeProfile")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Minh Anh · 27")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(KinnectTheme.textPrimary)
                            Text(L10n.tr("Hồ sơ minh họa"))
                                .font(.system(size: 7))
                                .foregroundColor(KinnectTheme.textSecondary)
                        }
                        Spacer()
                    }

                    Text(L10n.tr("Tập luyện mỗi ngày"))
                        .font(.system(size: 8))
                        .foregroundColor(KinnectTheme.textPrimary)

                    // Post Image with safe aspect ratio and top alignment (Head/face fully visible - Android Parity)
                    GeometryReader { geo in
                        Image("WelcomeProfile")
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: 112, alignment: .top)
                            .clipped()
                    }
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                    // Action buttons: Heart, Comment, Share
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 0.93, green: 0.28, blue: 0.6))
                        Image(systemName: "message.fill")
                            .font(.system(size: 10))
                            .foregroundColor(KinnectTheme.textSecondary)
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.system(size: 10))
                            .foregroundColor(KinnectTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(KinnectTheme.surfaceElevated.opacity(0.7)))
            }
        }
    }

    // MARK: - 2. Login View (Android 1.2.12 build 118 hierarchy)
    private var loginView: some View {
        VStack(alignment: .leading, spacing: 14) {
            authBrandHeader

            HStack(alignment: .center) {
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
                    .foregroundColor(KinnectTheme.textPrimary)
                }

                Spacer()

                authLanguagePill
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Chào bạn trở lại!"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(L10n.tr("Đăng nhập để tiếp tục những kết nối của bạn."))
                    .font(.system(size: 14))
                    .foregroundColor(KinnectTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)

            if !rememberedAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("Tài khoản đã ghi nhớ"))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(KinnectTheme.textSecondary)
                    ForEach(rememberedAccounts) { account in
                        HStack(spacing: 10) {
                            Button {
                                Task { await loginWithRemembered(account) }
                            } label: {
                                HStack(spacing: 10) {
                                    KinnectAvatarView(
                                        name: account.name.isEmpty ? account.username : account.name,
                                        avatarURL: "/api/users/\(account.id)/avatar",
                                        size: 38
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.name.isEmpty ? account.username : account.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(KinnectTheme.textPrimary)
                                            .lineLimit(1)
                                        Text("@\(account.username)")
                                            .font(.caption)
                                            .foregroundColor(KinnectTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(L10n.tr("Đăng nhập nhanh"))
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(KinnectTheme.accentBright)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)

                            Button {
                                Task { await removeRememberedAccount(account) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(KinnectTheme.textSecondary)
                                    .frame(minWidth: 36, minHeight: 36)
                            }
                            .buttonStyle(.plain)
                            .disabled(isLoading)
                            .accessibilityLabel(L10n.tr("Gỡ tài khoản đã ghi nhớ"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(KinnectTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(KinnectTheme.border, lineWidth: 1)
                                )
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                loginProviderButton(title: "Google", asset: "BrandGoogle") {
                    triggerOAuthLogin(provider: "google")
                }
                loginProviderButton(title: "Facebook", asset: "BrandFacebook") {
                    triggerOAuthLogin(provider: "facebook")
                }
            }

            // Native Sign in with Apple. AuthenticationServices draws the title from
            // CFBundleLocalizations and the system language. The in-app VI/EN toggle does
            // not change it, and Apple provides no public title override.
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
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
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
            .id("login-username")

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
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
            )
            .id("login-password")

            HStack {
                Button {
                    rememberLogin.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: rememberLogin ? "checkmark.square.fill" : "square")
                            .foregroundColor(rememberLogin ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                        Text(L10n.tr("Ghi nhớ"))
                            .font(.system(size: 14))
                            .foregroundColor(KinnectTheme.textPrimary)
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
                        .foregroundColor(KinnectTheme.accentBright)
                }
            }

            if needs2FA {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.tr("Mã xác thực 2 lớp (6 số / mã dự phòng)"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        if pendingOAuth2FACode != nil || pendingApple2FA != nil || pendingRememberedAccount != nil {
                            Button {
                                pendingOAuth2FACode = nil
                                pendingApple2FA = nil
                                pendingRememberedAccount = nil
                                needs2FA = false
                                loginTotpCode = ""
                                infoMessage = nil
                                errorMessage = nil
                            } label: {
                                Text(L10n.tr("Hủy"))
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }
                    if (pendingOAuth2FACode != nil || pendingApple2FA != nil || pendingRememberedAccount != nil), let info = infoMessage {
                        Text(info)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                    TextField(L10n.tr("Nhập mã 6 chữ số"), text: $loginTotpCode)
                        .keyboardType(.asciiCapable)
                        .textContentType(.oneTimeCode)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit {
                            if !isLoading && !loginTotpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Task { await performLogin() }
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KinnectTheme.surfaceElevated))
                        .foregroundColor(KinnectTheme.textPrimary)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.danger)
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
                    Text((pendingOAuth2FACode != nil || pendingApple2FA != nil || pendingRememberedAccount != nil) ? L10n.tr("Xác nhận đăng nhập") : L10n.tr("Đăng nhập"))
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KinnectTheme.primaryGradient))
                .foregroundColor(.white)
            }
            .disabled(
                isLoading || (
                    (pendingOAuth2FACode != nil || pendingApple2FA != nil || pendingRememberedAccount != nil)
                        ? loginTotpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        : (loginUsername.isEmpty || loginPassword.isEmpty)
                )
            )
            .id("login-submit")

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
                .foregroundColor(KinnectTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(KinnectTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(KinnectTheme.border, lineWidth: 1)
                        )
                )
            }

            Text(L10n.tr("Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng."))
                .font(.system(size: 12))
                .foregroundColor(KinnectTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

            Text("Kinnect iOS v\(ServerConfig.appVersion) (Build \(ServerConfig.buildNumber))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(KinnectTheme.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }

    private var loginLanguageSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(KinnectTheme.border)
                .frame(width: 42, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            Text(L10n.tr("Ngôn ngữ ứng dụng"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(KinnectTheme.textPrimary)

            ForEach(AppLanguage.allCases) { language in
                Button {
                    loc.setLanguage(language)
                    showLoginLanguageSheet = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundColor(KinnectTheme.accentBright)
                        Text(language.displayName)
                            .font(.system(size: 17))
                            .foregroundColor(KinnectTheme.textPrimary)
                        Spacer()
                        if loc.preference.rawValue == language.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundColor(KinnectTheme.accentBright)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Button {
                loc.setPreference(.system)
                showLoginLanguageSheet = false
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .foregroundColor(KinnectTheme.accentBright)
                    Text(L10n.tr("Theo hệ thống"))
                        .font(.system(size: 17))
                        .foregroundColor(KinnectTheme.textPrimary)
                    Spacer()
                    if loc.preference == .system {
                        Image(systemName: "checkmark")
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                }
                .padding(.vertical, 8)
            }

            Button {
                showLoginLanguageSheet = false
            } label: {
                Text(L10n.tr("Đóng"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(KinnectTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 23)
                            .fill(KinnectTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 23).stroke(KinnectTheme.border, lineWidth: 1))
                    )
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(KinnectTheme.background.ignoresSafeArea())
        .presentationDetents([.height(320)])
    }

    private func loginDivider(_ title: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(KinnectTheme.border).frame(height: 1)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(KinnectTheme.textSecondary)
                .fixedSize()
            Rectangle().fill(KinnectTheme.border).frame(height: 1)
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
                    .foregroundColor(KinnectTheme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(KinnectTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(KinnectTheme.border, lineWidth: 1)
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
                .foregroundColor(focused ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
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
            .submitLabel(field == .username ? .next : .go)
            .onSubmit {
                if field == .username {
                    focusedLoginField = .password
                } else if !loginUsername.isEmpty, !loginPassword.isEmpty, !isLoading {
                    Task { await performLogin() }
                }
            }
            .foregroundColor(KinnectTheme.textPrimary)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(KinnectTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focused ? KinnectTheme.accentBright : KinnectTheme.border, lineWidth: focused ? 2 : 1)
                )
        )
    }

    private var authBrandHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Image("KinnectLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text("Kinnect")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(KinnectTheme.accentBright)
            Spacer(minLength: 8)
            Text(L10n.tr("Sống đúng mình."))
                .font(.system(size: 13))
                .foregroundColor(KinnectTheme.textSecondary)
                .lineLimit(1)
        }
    }

    private var authLanguagePill: some View {
        Button {
            showLoginLanguageSheet = true
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
            .overlay(Capsule().stroke(KinnectTheme.borderSoft, lineWidth: 1))
            .foregroundColor(KinnectTheme.textPrimary)
        }
        .accessibilityLabel(L10n.tr("Ngôn ngữ ứng dụng"))
    }

    private var authSocialProvidersCluster: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                loginProviderButton(title: "Google", asset: "BrandGoogle") {
                    triggerOAuthLogin(provider: "google")
                }
                loginProviderButton(title: "Facebook", asset: "BrandFacebook") {
                    triggerOAuthLogin(provider: "facebook")
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
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .accessibilityLabel(L10n.tr("Đăng nhập bằng Apple"))

            if let oauthErr = oauth.oauthError {
                Text(oauthErr)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.warning)
            }
        }
    }

    private func authStyledInputField(
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        secure: Bool = false,
        autocapitalizeNever: Bool = true,
        keyboardType: UIKeyboardType = .default,
        contentType: UITextContentType? = nil
    ) -> some View {
        authStyledInputField(
            systemImage: systemImage,
            placeholder: placeholder,
            text: text,
            secure: secure,
            autocapitalizeNever: autocapitalizeNever,
            keyboardType: keyboardType,
            contentType: contentType,
            trailing: { EmptyView() }
        )
    }

    private func authStyledInputField<Trailing: View>(
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        secure: Bool = false,
        autocapitalizeNever: Bool = true,
        keyboardType: UIKeyboardType = .default,
        contentType: UITextContentType? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundColor(KinnectTheme.textSecondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(autocapitalizeNever ? .never : .words)
                        .autocorrectionDisabled(autocapitalizeNever)
                        .keyboardType(keyboardType)
                        .textContentType(contentType)
                }
            }
            .foregroundColor(KinnectTheme.textPrimary)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(KinnectTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(KinnectTheme.border, lineWidth: 1)
                )
        )
    }

    // MARK: - 3. Register View
    private var registerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            authBrandHeader

            // Header Navigation Bar
            HStack {
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
                    .foregroundColor(KinnectTheme.textPrimary)
                }

                Spacer()

                authLanguagePill
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Bắt đầu kết nối của bạn."))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(L10n.tr("Tạo tài khoản để chia sẻ và gặp người cùng tần số."))
                    .font(.system(size: 14))
                    .foregroundColor(KinnectTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)

            // OAuth First (Matching Login & Android Register Hierarchy)
            authSocialProvidersCluster

            loginDivider(L10n.tr("hoặc đăng ký bằng tài khoản"))

            // Bordered Input Fields matching Login
            VStack(spacing: 12) {
                authStyledInputField(
                    systemImage: "person.text.rectangle",
                    placeholder: L10n.tr("Tên hiển thị"),
                    text: $regName,
                    autocapitalizeNever: false
                )

                authStyledInputField(
                    systemImage: "person",
                    placeholder: L10n.tr("Tên đăng nhập (3-30 ký tự)"),
                    text: $regUsername
                )

                authStyledInputField(
                    systemImage: "lock",
                    placeholder: L10n.tr("Mật khẩu (ít nhất 6 ký tự)"),
                    text: $regPassword,
                    secure: !showRegPassword
                ) {
                    Button {
                        showRegPassword.toggle()
                    } label: {
                        Image(systemName: showRegPassword ? "eye.slash" : "eye")
                            .foregroundColor(KinnectTheme.textSecondary)
                    }
                }
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
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "person.badge.plus")
                    }
                    Text(L10n.tr("Tạo tài khoản"))
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KinnectTheme.primaryGradient))
                .foregroundColor(.white)
            }
            .disabled(isLoading)

            // Switch to Login
            HStack(spacing: 4) {
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
        }
    }

    // MARK: - 4. Forgot Password View
    private var forgotView: some View {
        VStack(alignment: .leading, spacing: 14) {
            authBrandHeader

            // Header Bar
            HStack {
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    forgotChallengeId = ""
                    forgotOtpCode = ""
                    forgotNewPassword = ""
                    forgotContact = ""
                    showForgotFallbackButton = false
                    showForgotAdminFields = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .login
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(L10n.tr("Quay lại đăng nhập"))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(KinnectTheme.textPrimary)
                }
                Spacer()
                authLanguagePill
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Quên mật khẩu"))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(KinnectTheme.textPrimary)
                Text(L10n.tr("Chúng tôi sẽ gửi mã xác minh hoặc hướng dẫn tới email khôi phục của bạn."))
                    .font(.system(size: 14))
                    .foregroundColor(KinnectTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)

            if forgotChallengeId.isEmpty {
                authStyledInputField(
                    systemImage: "person",
                    placeholder: showForgotAdminFields ? L10n.tr("Tên đăng nhập (vd: ten_tai_khoan)") : L10n.tr("Tên đăng nhập hoặc email"),
                    text: $forgotUsername
                )

                if showForgotFallbackButton || showForgotAdminFields {
                    authStyledInputField(
                        systemImage: "envelope",
                        placeholder: L10n.tr("Email, số điện thoại hoặc Zalo liên hệ"),
                        text: $forgotContact
                    )
                }
            } else {
                authStyledInputField(
                    systemImage: "number",
                    placeholder: L10n.tr("Mã xác minh 6 chữ số (OTP)"),
                    text: $forgotOtpCode,
                    keyboardType: .numberPad,
                    contentType: .oneTimeCode
                )

                authStyledInputField(
                    systemImage: "lock",
                    placeholder: L10n.tr("Mật khẩu mới (ít nhất 6 ký tự)"),
                    text: $forgotNewPassword,
                    secure: true
                )
            }

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

            if forgotChallengeId.isEmpty {
                Button {
                    Task { await performForgot() }
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "envelope.badge")
                        }
                        Text(L10n.tr("Gửi mã qua email"))
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KinnectTheme.primaryGradient))
                    .foregroundColor(.white)
                }
                .disabled(isLoading || forgotUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if showForgotFallbackButton {
                    Button {
                        if !showForgotAdminFields {
                            showForgotAdminFields = true
                            errorMessage = nil
                            infoMessage = nil
                        } else {
                            Task { await performForgotAdminFallback() }
                        }
                    } label: {
                        Text(L10n.tr("Gửi yêu cầu hỗ trợ quản trị viên"))
                            .font(.subheadline.bold())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    .disabled(isLoading || (showForgotAdminFields && forgotUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            } else {
                Button {
                    Task { await performForgotFinish() }
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView().tint(.white)
                        }
                        Text(L10n.tr("Đặt lại mật khẩu"))
                            .font(.system(size: 16, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KinnectTheme.primaryGradient))
                    .foregroundColor(.white)
                }
                .disabled(isLoading || forgotOtpCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 6 || forgotNewPassword.count < 6)

                Button {
                    Task { await performForgot() }
                } label: {
                    Text(L10n.tr("Gửi lại mã"))
                        .font(.subheadline.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                }
                .disabled(isLoading)

                Button {
                    forgotChallengeId = ""
                    forgotOtpCode = ""
                    forgotNewPassword = ""
                    showForgotFallbackButton = true
                    showForgotAdminFields = true
                } label: {
                    Text(L10n.tr("Không nhận được mã? Gửi yêu cầu hỗ trợ quản trị viên"))
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 6) {
                Text(L10n.tr("Chưa có email khôi phục?"))
                    .font(.caption)
                    .foregroundColor(KinnectTheme.textSecondary)
                Button {
                    if !showForgotAdminFields {
                        showForgotAdminFields = true
                        showForgotFallbackButton = true
                        errorMessage = nil
                        infoMessage = nil
                    } else {
                        Task { await performForgotAdminFallback() }
                    }
                } label: {
                    Text(L10n.tr("Gửi yêu cầu hỗ trợ quản trị viên"))
                        .font(.caption.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    // MARK: - 5. Social Auth Section (Apple Guideline 4.8 Compliance)
    private var socialAuthSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Rectangle().fill(KinnectTheme.border).frame(height: 1)
                Text(L10n.tr("hoặc tiếp tục với mạng xã hội"))
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .fixedSize()
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
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(L10n.tr("Đăng nhập bằng Apple"))

            // Google & Facebook Social Login Buttons
            HStack(spacing: 12) {
                Button {
                    triggerOAuthLogin(provider: "google")
                } label: {
                    HStack(spacing: 8) {
                        Image("BrandGoogle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("Google")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(KinnectTheme.border, lineWidth: 1))
                }

                Button {
                    triggerOAuthLogin(provider: "facebook")
                } label: {
                    HStack(spacing: 8) {
                        Image("BrandFacebook")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("Facebook")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(KinnectTheme.textPrimary)
                            .lineLimit(1)
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
    private func triggerOAuthLogin(provider: String) {
        errorMessage = nil
        infoMessage = nil
        oauth.startOAuth(provider: provider, rememberMe: rememberLogin) { res in
            if case .failure(let err) = res {
                if case OAuthError.canceled = err {
                    return
                }
                if case OAuthError.pendingRegistration(let ticket, let regProvider, let name, let suggestedUsername) = err {
                    pendingOAuthRegistration = PendingOAuthRegistration(
                        ticket: ticket,
                        provider: regProvider.isEmpty ? provider : regProvider,
                        name: name,
                        suggestedUsername: suggestedUsername
                    )
                    return
                }
                if case OAuthError.twoFactorRequired(let oauthCode) = err {
                    pendingOAuth2FACode = oauthCode
                    needs2FA = true
                    loginTotpCode = ""
                    infoMessage = L10n.tr("Tài khoản bật bảo mật 2 lớp. Nhập mã 6 số hoặc mã dự phòng để tiếp tục.")
                    if stage != .login {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            stage = .login
                        }
                    }
                    return
                }
                errorMessage = err.localizedDescription
            }
        }
    }

    private func hydrateAuthenticatedMe(fallbackUserDict: [String: Any], rememberMe: Bool) async {
        _ = await OAuthManager.shared.hydrateAndApplySession(fallbackUserDict: fallbackUserDict, rememberMe: rememberMe)
    }

    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = L10n.tr("Không nhận diện được chứng chỉ Apple.")
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

            let isLikelyNewAccount = (stage == .register) || !email.isEmpty || !fullName.isEmpty
            if isLikelyNewAccount && !agree18 {
                pendingAppleConsent = PendingAppleConsent(
                    appleId: userIdentifier,
                    email: email,
                    fullName: nameToUse,
                    identityToken: identityTokenStr,
                    nonce: currentAppleNonce
                )
                return
            }

            Task {
                await submitAppleSignIn(
                    appleId: userIdentifier,
                    email: email,
                    fullName: nameToUse,
                    identityToken: identityTokenStr,
                    nonce: currentAppleNonce,
                    confirmed18: agree18,
                    recordPrivacyConsent: agree18 && agreePrivacy
                )
            }
        case .failure(let error):
            let nsErr = error as NSError
            if nsErr.domain == ASAuthorizationError.errorDomain && nsErr.code == ASAuthorizationError.canceled.rawValue {
                // User intentionally cancelled: ignore quietly
                return
            }
            if nsErr.code == 1000 || nsErr.localizedDescription.lowercased().contains("unknown") {
                errorMessage = L10n.tr("Không thể đăng nhập bằng Apple lúc này. Vui lòng kiểm tra iCloud và thử lại.")
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func submitAppleSignIn(
        appleId: String,
        email: String,
        fullName: String,
        identityToken: String,
        nonce: String,
        confirmed18: Bool,
        recordPrivacyConsent: Bool = false
    ) async {
        do {
            var appleBody: [String: Any] = [
                "appleId": appleId,
                "email": email,
                "fullName": fullName,
                "identityToken": identityToken,
                "agree18": confirmed18
            ]
            if !nonce.isEmpty {
                appleBody["nonce"] = nonce
            }
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/auth/apple",
                method: "POST",
                body: appleBody
            )
            if let userDict = res["user"] as? [String: Any] {
                pendingApple2FA = nil
                needs2FA = false
                loginTotpCode = ""
                if recordPrivacyConsent {
                    let consentStatus = try? await KinnectAPIClient.shared.requestJSON("/api/me/privacy-consent")
                    let alreadyAccepted = (consentStatus?["accepted"] as? Bool) == true
                    if !alreadyAccepted {
                        let liveVersion = (consentStatus?["version"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "2026-10-29"
                        _ = try? await KinnectAPIClient.shared.requestJSON(
                            "/api/me/privacy-consent",
                            method: "POST",
                            body: ["accepted": true, "version": liveVersion]
                        )
                    }
                }
                await hydrateAuthenticatedMe(fallbackUserDict: userDict, rememberMe: rememberLogin)
            }
        } catch {
            #if DEBUG
            if UIReviewFixture.isEnabled {
                appState.applyAuthenticatedUser(KinnectUser.from(UIReviewFixture.currentUserDict), rawDict: UIReviewFixture.currentUserDict, rememberMe: rememberLogin)
                return
            }
            #endif
            if case KinnectAPIError.requiresAgree18 = error {
                errorMessage = nil
                pendingAppleConsent = PendingAppleConsent(
                    appleId: appleId,
                    email: email,
                    fullName: fullName,
                    identityToken: identityToken,
                    nonce: nonce
                )
            } else if case KinnectAPIError.serverError(let status, let msg) = error,
                      status == 400,
                      !confirmed18,
                      msg.localizedCaseInsensitiveContains("18") {
                errorMessage = nil
                pendingAppleConsent = PendingAppleConsent(
                    appleId: appleId,
                    email: email,
                    fullName: fullName,
                    identityToken: identityToken,
                    nonce: nonce
                )
            } else if case KinnectAPIError.serverError(let status, let msg) = error,
                      status == 403,
                      (msg.localizedCaseInsensitiveContains("2FA")
                       || msg.localizedCaseInsensitiveContains("2 bước")
                       || msg.localizedCaseInsensitiveContains("2 lớp")) {
                pendingApple2FA = PendingApple2FA(
                    appleId: appleId,
                    email: email,
                    fullName: fullName,
                    identityToken: identityToken,
                    nonce: nonce
                )
                pendingOAuth2FACode = nil
                needs2FA = true
                loginTotpCode = ""
                errorMessage = nil
                infoMessage = L10n.tr("Tài khoản Apple bật bảo mật 2 lớp. Nhập mã 6 số hoặc mã dự phòng để tiếp tục.")
                if stage != .login {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .login
                    }
                }
            } else {
                errorMessage = "Apple Sign-In: \(error.localizedDescription)"
            }
        }
    }

    private func loadRememberedAccounts() async {
        #if DEBUG
        guard !UIReviewFixture.isEnabled else { return }
        #endif
        guard let res = try? await KinnectAPIClient.shared.requestJSON("/api/remembered"),
              let list = res["accounts"] as? [[String: Any]] else {
            return
        }
        self.rememberedAccounts = list.compactMap { dict in
            guard let id = dict["id"] as? String, !id.isEmpty,
                  let username = dict["username"] as? String else { return nil }
            let name = (dict["name"] as? String) ?? username
            return RememberedAccount(id: id, username: username, name: name)
        }
    }

    private func loginWithRemembered(_ account: RememberedAccount) async {
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/remembered/login",
                method: "POST",
                body: ["userId": account.id]
            )
            if let userDict = res["user"] as? [String: Any] {
                pendingRememberedAccount = nil
                needs2FA = false
                loginTotpCode = ""
                let user = KinnectUser.from(userDict)
                appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: true)
                await appState.refreshGlobalBadges()
                await appState.refreshBlockedUsers()
            }
        } catch let error as KinnectAPIError {
            if case .serverError(let status, _) = error, status == 403 {
                pendingRememberedAccount = account
                pendingOAuth2FACode = nil
                pendingApple2FA = nil
                needs2FA = true
                loginTotpCode = ""
                infoMessage = L10n.tr("Tài khoản bật bảo mật 2 lớp. Nhập mã 6 số hoặc mã dự phòng để tiếp tục.")
                return
            }
            if case .unauthorized = error {
                rememberedAccounts.removeAll { $0.id == account.id }
                loginUsername = account.username
            }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeRememberedAccount(_ account: RememberedAccount) async {
        _ = try? await KinnectAPIClient.shared.requestJSON(
            "/api/remembered/\(account.id)",
            method: "DELETE",
            body: [:]
        )
        rememberedAccounts.removeAll { $0.id == account.id }
        if pendingRememberedAccount?.id == account.id {
            pendingRememberedAccount = nil
            needs2FA = false
            loginTotpCode = ""
        }
    }

    private func performLogin() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if let remembered = pendingRememberedAccount {
            let cleanTotp = loginTotpCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTotp.isEmpty else {
                errorMessage = L10n.tr("Vui lòng nhập mã xác thực 2 bước.")
                return
            }
            do {
                let res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/remembered/login",
                    method: "POST",
                    body: ["userId": remembered.id, "totpCode": cleanTotp]
                )
                if let userDict = res["user"] as? [String: Any] {
                    pendingRememberedAccount = nil
                    needs2FA = false
                    loginTotpCode = ""
                    infoMessage = nil
                    let user = KinnectUser.from(userDict)
                    appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: true)
                    await appState.refreshGlobalBadges()
                    await appState.refreshBlockedUsers()
                }
            } catch {
                if case KinnectAPIError.unauthorized = error {
                    pendingRememberedAccount = nil
                    needs2FA = false
                    loginTotpCode = ""
                    infoMessage = nil
                    rememberedAccounts.removeAll { $0.id == remembered.id }
                }
                errorMessage = error.localizedDescription
            }
            return
        }

        if let apple2FA = pendingApple2FA {
            let cleanTotp = loginTotpCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTotp.isEmpty else {
                errorMessage = L10n.tr("Vui lòng nhập mã xác thực 2 bước.")
                return
            }
            do {
                var appleBody: [String: Any] = [
                    "appleId": apple2FA.appleId,
                    "email": apple2FA.email,
                    "fullName": apple2FA.fullName,
                    "identityToken": apple2FA.identityToken,
                    "totpCode": cleanTotp,
                    "agree18": agree18
                ]
                if !apple2FA.nonce.isEmpty {
                    appleBody["nonce"] = apple2FA.nonce
                }
                let res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/auth/apple",
                    method: "POST",
                    body: appleBody
                )
                if let userDict = res["user"] as? [String: Any] {
                    pendingApple2FA = nil
                    needs2FA = false
                    loginTotpCode = ""
                    infoMessage = nil
                    await hydrateAuthenticatedMe(fallbackUserDict: userDict, rememberMe: rememberLogin)
                }
            } catch {
                let isUnauthorized: Bool = {
                    if case KinnectAPIError.unauthorized = error { return true }
                    if case KinnectAPIError.serverError(let status, _) = error, status == 401 { return true }
                    return false
                }()
                if isUnauthorized {
                    pendingApple2FA = nil
                    needs2FA = false
                    loginTotpCode = ""
                    infoMessage = nil
                }
                errorMessage = error.localizedDescription
            }
            return
        }

        if let oauthCode = pendingOAuth2FACode, !oauthCode.isEmpty {
            let cleanTotp = loginTotpCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTotp.isEmpty else {
                errorMessage = L10n.tr("Vui lòng nhập mã xác thực 2 bước.")
                return
            }
            do {
                let res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/oauth/app-session",
                    method: "POST",
                    body: [
                        "code": oauthCode,
                        "totpCode": cleanTotp,
                        "remember": rememberLogin
                    ]
                )
                if let userDict = res["user"] as? [String: Any] {
                    pendingOAuth2FACode = nil
                    needs2FA = false
                    loginTotpCode = ""
                    infoMessage = nil
                    await hydrateAuthenticatedMe(fallbackUserDict: userDict, rememberMe: rememberLogin)
                }
            } catch {
                if case KinnectAPIError.unauthorized = error {
                    pendingOAuth2FACode = nil
                    needs2FA = false
                    loginTotpCode = ""
                    infoMessage = nil
                }
                errorMessage = error.localizedDescription
            }
            return
        }

        do {
            var payload: [String: Any] = [
                "username": loginUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": loginPassword,
                "remember": rememberLogin
            ]
            let cleanTotp = loginTotpCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanTotp.isEmpty {
                payload["totpCode"] = cleanTotp
            }
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/login",
                method: "POST",
                body: payload
            )
            if let userDict = res["user"] as? [String: Any] {
                needs2FA = false
                loginTotpCode = ""
                let user = KinnectUser.from(userDict)
                appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: rememberLogin)
                await appState.refreshGlobalBadges()
                await appState.refreshBlockedUsers()
            }
        } catch {
            #if DEBUG
            if UIReviewFixture.isEnabled {
                appState.applyAuthenticatedUser(KinnectUser.from(UIReviewFixture.currentUserDict), rawDict: UIReviewFixture.currentUserDict, rememberMe: true)
                return
            }
            #endif
            if error.localizedDescription.localizedCaseInsensitiveContains("2 lớp") {
                needs2FA = true
            }
            errorMessage = error.localizedDescription
        }
    }

    private func performRegister() async {
        errorMessage = nil
        let cleanName = regName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = regUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        let validUsername = cleanUsername.count >= 3
            && cleanUsername.count <= 30
            && cleanUsername.unicodeScalars.allSatisfy { allowed.contains($0) }

        guard !cleanName.isEmpty else {
            errorMessage = L10n.tr("Vui lòng nhập tên hiển thị.")
            return
        }
        guard validUsername else {
            errorMessage = L10n.tr("Tên đăng nhập cần 3–30 ký tự chữ thường không dấu, số hoặc gạch dưới.")
            return
        }
        guard regPassword.count >= 6 else {
            errorMessage = L10n.tr("Mật khẩu phải có ít nhất 6 ký tự.")
            return
        }
        guard agree18 else {
            errorMessage = L10n.tr("Vui lòng xác nhận bạn đủ 18 tuổi và đồng ý quy tắc cộng đồng.")
            return
        }
        guard agreePrivacy else {
            errorMessage = L10n.tr("Vui lòng đồng ý Chính sách quyền riêng tư & Điều khoản Kinnect.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/register",
                method: "POST",
                body: [
                    "name": cleanName,
                    "username": cleanUsername,
                    "password": regPassword,
                    "agree18": agree18,
                    "acceptPrivacyNotice": agreePrivacy
                ]
            )
            if let userDict = res["user"] as? [String: Any] {
                let user = KinnectUser.from(userDict)
                appState.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: true)
                await appState.refreshGlobalBadges()
                await appState.refreshBlockedUsers()
            }
        } catch {
            #if DEBUG
            if UIReviewFixture.isEnabled {
                appState.applyAuthenticatedUser(KinnectUser.from(UIReviewFixture.currentUserDict), rawDict: UIReviewFixture.currentUserDict, rememberMe: true)
                return
            }
            #endif
            errorMessage = error.localizedDescription
        }
    }

    private func performForgot() async {
        let trimmed = forgotUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/recovery/reset/start",
                method: "POST",
                body: ["identifier": trimmed]
            )
            if let cid = res["challengeId"] as? String, !cid.isEmpty {
                forgotChallengeId = cid
                showForgotFallbackButton = false
                infoMessage = (res["message"] as? String) ?? (loc.currentLanguage == .en
                    ? "Verification code sent to your recovery email."
                    : "Nếu tài khoản có email khôi phục đã xác minh, mã OTP đã được gửi tới email đó.")
            } else {
                showForgotFallbackButton = true
                infoMessage = (res["message"] as? String) ?? "Tài khoản chưa có email khôi phục đã xác minh. Bạn có thể gửi yêu cầu hỗ trợ quản trị viên."
            }
        } catch {
            #if DEBUG
            if UIReviewFixture.isEnabled {
                infoMessage = loc.currentLanguage == .en ? "Verification code dispatched." : "Đã gửi mã xác nhận thành công."
                return
            }
            #endif
            showForgotFallbackButton = true
            errorMessage = error.localizedDescription
        }
    }

    private func performForgotFinish() async {
        let cleanCode = forgotOtpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !forgotChallengeId.isEmpty, !cleanCode.isEmpty, forgotNewPassword.count >= 6 else { return }
        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/recovery/reset/finish",
                method: "POST",
                body: [
                    "challengeId": forgotChallengeId,
                    "code": cleanCode,
                    "password": forgotNewPassword
                ]
            )
            let msg = (res["message"] as? String) ?? "Đã đổi mật khẩu. Hãy đăng nhập bằng mật khẩu mới."
            appState.showToast(msg)
            loginUsername = forgotUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            forgotChallengeId = ""
            forgotOtpCode = ""
            forgotNewPassword = ""
            showForgotFallbackButton = false
            withAnimation(.easeInOut(duration: 0.2)) {
                stage = .login
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performForgotAdminFallback() async {
        if !showForgotAdminFields {
            showForgotAdminFields = true
            showForgotFallbackButton = true
            errorMessage = nil
            infoMessage = nil
            return
        }
        showForgotAdminFields = true
        showForgotFallbackButton = true

        let rawInput = forgotUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleanContact = forgotContact.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the user typed an email address in the first field, move it to contact and ask for username.
        if rawInput.contains("@") && !rawInput.hasPrefix("@") {
            if cleanContact.isEmpty {
                forgotContact = rawInput
                cleanContact = rawInput
                forgotUsername = ""
            }
            errorMessage = L10n.tr("Vui lòng nhập tên đăng nhập (3–30 ký tự, không gồm @) để gửi yêu cầu cho quản trị viên.")
            return
        }

        let normalizedUsername = rawInput
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        let usernameAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        let validUsername = normalizedUsername.count >= 3
            && normalizedUsername.count <= 30
            && normalizedUsername.unicodeScalars.allSatisfy { usernameAllowed.contains($0) }

        guard validUsername else {
            errorMessage = L10n.tr("Nhập đúng tên đăng nhập của bạn (3–30 ký tự chữ thường, số hoặc _).")
            return
        }

        if cleanContact.count < 5 {
            errorMessage = L10n.tr("Để lại email, số điện thoại hoặc Zalo (tối thiểu 5 ký tự) để quản trị viên liên hệ.")
            return
        }

        isLoading = true
        errorMessage = nil
        infoMessage = nil
        defer { isLoading = false }

        do {
            _ = try await KinnectAPIClient.shared.requestJSON(
                "/api/password-reset",
                method: "POST",
                body: [
                    "username": normalizedUsername,
                    "contact": cleanContact,
                    "note": "iOS App password reset request"
                ]
            )
            forgotChallengeId = ""
            infoMessage = loc.currentLanguage == .en
                ? "Admin support request sent."
                : "Đã gửi yêu cầu hỗ trợ quản trị viên thành công."
        } catch {
            errorMessage = error.localizedDescription
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

    private func findTextFields(in view: UIView) -> [UITextField] {
        var result: [UITextField] = []
        if let tf = view as? UITextField {
            result.append(tf)
        }
        for sub in view.subviews {
            result.append(contentsOf: findTextFields(in: sub))
        }
        return result
    }

    private func activateSimulatorSoftwareKeyboard(fieldIndex: Int = 0) {
        disableSimulatorHardwareKeyboardMode()
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                let fields = findTextFields(in: window)
                if fields.indices.contains(fieldIndex) {
                    let tf = fields[fieldIndex]
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

private struct AppleAgeConsentSheet: View {
    let onFinish: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var confirm18AndPrivacy = false
    @State private var showPrivacyNoticeSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Xác nhận độ tuổi (18+)"))
                            .font(.title3.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(L10n.tr("Để tạo tài khoản Kinnect bằng Apple, vui lòng xác nhận bạn đã đủ 18 tuổi và đồng ý Quy tắc cộng đồng cùng Chính sách quyền riêng tư."))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $confirm18AndPrivacy) {
                            Text(L10n.tr("Tôi xác nhận đã đủ 18 tuổi và đồng ý Điều khoản & Chính sách quyền riêng tư"))
                                .font(.footnote.weight(.medium))
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                        .tint(KinnectTheme.accentBright)

                        HStack(spacing: 14) {
                            Button {
                                showPrivacyNoticeSheet = true
                            } label: {
                                Text(L10n.tr("Xem thông báo dữ liệu"))
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                            .buttonStyle(.plain)

                            if let termsURL = URL(string: "https://kinnect.io.vn/terms") {
                                Link(L10n.tr("Điều khoản"), destination: termsURL)
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }

                            if let privacyURL = URL(string: "https://kinnect.io.vn/privacy") {
                                Link(L10n.tr("Quyền riêng tư"), destination: privacyURL)
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surface))

                    Button {
                        onFinish(true)
                        dismiss()
                    } label: {
                        Text(L10n.tr("Tiếp tục với Apple"))
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(KinnectTheme.primaryGradient)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!confirm18AndPrivacy)
                }
                .padding(20)
            }
            .background(KinnectTheme.background.ignoresSafeArea())
            .navigationTitle(L10n.tr("Xác nhận độ tuổi (18+)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Hủy")) {
                        onFinish(false)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPrivacyNoticeSheet) {
                PrivacyConsentSheet(
                    request: PrivacyConsentRequest(
                        version: "2026-10-29",
                        notice: L10n.tr("Chính sách quyền riêng tư và điều khoản dịch vụ Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.")
                    ),
                    recordOnServer: false,
                    onAccepted: {
                        confirm18AndPrivacy = true
                        showPrivacyNoticeSheet = false
                    }
                )
            }
        }
    }
}

private struct OAuthCompleteRegistrationSheet: View {
    let ticket: String
    let provider: String
    let initialName: String
    let suggestedUsername: String
    let rememberMe: Bool
    let onCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var displayName: String
    @State private var username: String
    @State private var confirm18AndPrivacy: Bool = false
    @State private var showPrivacyNoticeSheet: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    init(
        ticket: String,
        provider: String,
        initialName: String,
        suggestedUsername: String,
        rememberMe: Bool,
        onCompleted: @escaping () -> Void
    ) {
        self.ticket = ticket
        self.provider = provider
        self.initialName = initialName
        self.suggestedUsername = suggestedUsername
        self.rememberMe = rememberMe
        self.onCompleted = onCompleted
        _displayName = State(initialValue: initialName)
        _username = State(initialValue: suggestedUsername)
    }

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isUsernameValid: Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        return normalizedUsername.count >= 3
            && normalizedUsername.count <= 30
            && normalizedUsername.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private var providerLabel: String {
        switch provider.lowercased() {
        case "google": return "Google"
        case "facebook": return "Facebook"
        default: return provider.capitalized
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(L10n.tr("Tạo tài khoản từ")) \(providerLabel)")
                            .font(.title3.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                        Text(L10n.tr("Chọn tên đăng nhập và xác nhận độ tuổi cùng chính sách bảo vệ dữ liệu trước khi hoàn tất đăng ký."))
                            .font(.subheadline)
                            .foregroundColor(KinnectTheme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("Tên hiển thị"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            TextField(L10n.tr("Tên hiển thị của bạn"), text: $displayName)
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.textPrimary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("Tên đăng nhập (3–30 chữ thường không dấu, số hoặc _)"))
                                .font(.caption.bold())
                                .foregroundColor(KinnectTheme.textSecondary)
                            TextField("ten_dang_nhap", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $confirm18AndPrivacy) {
                            Text(L10n.tr("Tôi xác nhận đã đủ 18 tuổi và đồng ý Điều khoản & Chính sách quyền riêng tư"))
                                .font(.footnote.weight(.medium))
                                .foregroundColor(KinnectTheme.textPrimary)
                        }
                        .tint(KinnectTheme.accentBright)

                        HStack(spacing: 14) {
                            Button {
                                showPrivacyNoticeSheet = true
                            } label: {
                                Text(L10n.tr("Xem thông báo dữ liệu"))
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                            .buttonStyle(.plain)

                            if let termsURL = URL(string: "https://kinnect.io.vn/terms") {
                                Link(L10n.tr("Điều khoản"), destination: termsURL)
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }

                            if let privacyURL = URL(string: "https://kinnect.io.vn/privacy") {
                                Link(L10n.tr("Quyền riêng tư"), destination: privacyURL)
                                    .font(.caption.bold())
                                    .foregroundColor(KinnectTheme.accentBright)
                            }
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(KinnectTheme.surface))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(KinnectTheme.danger)
                    }

                    Button {
                        Task { await submitRegistration() }
                    } label: {
                        HStack(spacing: 8) {
                            Spacer()
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(L10n.tr("Hoàn tất đăng ký"))
                                    .font(.headline.bold())
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(KinnectTheme.primaryGradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isSubmitting || !confirm18AndPrivacy || !isUsernameValid)
                }
                .padding(20)
            }
            .background(KinnectTheme.background.ignoresSafeArea())
            .navigationTitle(L10n.tr("Hoàn tất đăng ký"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Hủy")) {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            .sheet(isPresented: $showPrivacyNoticeSheet) {
                PrivacyConsentSheet(
                    request: PrivacyConsentRequest(
                        version: "2026-10-29",
                        notice: L10n.tr("Chính sách quyền riêng tư và điều khoản dịch vụ Kinnect. Cam kết bảo mật theo tiêu chuẩn Apple và pháp luật Việt Nam.")
                    ),
                    recordOnServer: false,
                    onAccepted: {
                        confirm18AndPrivacy = true
                        showPrivacyNoticeSheet = false
                    }
                )
            }
        }
    }

    @MainActor
    private func submitRegistration() async {
        guard confirm18AndPrivacy else {
            errorMessage = L10n.tr("Vui lòng xác nhận đủ 18 tuổi và đồng ý Điều khoản & Chính sách quyền riêng tư.")
            return
        }
        guard isUsernameValid else {
            errorMessage = L10n.tr("Tên đăng nhập cần 3–30 ký tự chữ thường không dấu, số hoặc gạch dưới.")
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            var payload: [String: Any] = [
                "ticket": ticket,
                "username": normalizedUsername,
                "agree18": true
            ]
            let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanName.isEmpty {
                payload["name"] = cleanName
            }
            let completeRes = try await KinnectAPIClient.shared.requestJSON(
                "/api/oauth/complete",
                method: "POST",
                body: payload
            )
            guard let userDict = completeRes["user"] as? [String: Any] else {
                throw OAuthError.message(L10n.tr("Không hoàn tất được đăng ký tài khoản."))
            }

            let consentStatus = try? await KinnectAPIClient.shared.requestJSON("/api/me/privacy-consent")
            let alreadyAccepted = (consentStatus?["accepted"] as? Bool) == true
            if !alreadyAccepted {
                let liveVersion = (consentStatus?["version"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "2026-10-29"
                _ = try? await KinnectAPIClient.shared.requestJSON(
                    "/api/me/privacy-consent",
                    method: "POST",
                    body: ["accepted": true, "version": liveVersion]
                )
            }

            _ = await OAuthManager.shared.hydrateAndApplySession(
                fallbackUserDict: userDict,
                rememberMe: rememberMe
            )
            onCompleted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
