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
    @State private var welcomePreview = 1
    @State private var welcomeViewportHeight: CGFloat = 760
    @State private var showLoginLanguageSheet = false
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
                        colors: [LoginChrome.wash, LoginChrome.background, LoginChrome.background],
                        startPoint: .top, endPoint: .bottom
                    )
                } else if stage == .login {
                    LoginChrome.background
                } else {
                    KinnectTheme.background
                }
            }
            .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                    #if DEBUG
                    if UIReviewFixture.isEnabled && stage != .login && stage != .welcome {
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
                    .font(KinnectTheme.scaled(19, weight: .bold))
                    .foregroundColor(LoginChrome.purple)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    showLoginLanguageSheet = true
                } label: {
                    Text("VI / EN")
                        .font(KinnectTheme.scaled(12, weight: .bold))
                        .foregroundColor(LoginChrome.ink)
                        .frame(minWidth: 56, minHeight: 44)
                }
                .accessibilityLabel(L10n.tr("Ngôn ngữ ứng dụng"))
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) { stage = .login }
                } label: {
                    Text(L10n.tr("Đăng nhập"))
                        .font(KinnectTheme.scaled(14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(LoginChrome.purple))
                }
            }
            .frame(height: 48)

            Text(L10n.tr("Kết nối đúng gu.\nSống đúng mình."))
                .font(KinnectTheme.scaled(28, weight: .bold))
                .foregroundColor(LoginChrome.ink)
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
                    .font(KinnectTheme.scaled(16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 14).fill(LoginChrome.purple))
            }

            Text(L10n.tr("Dành cho người từ 18 tuổi · Minh họa tính năng"))
                .font(.system(size: 11))
                .foregroundColor(LoginChrome.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Text("Kinnect iOS v\(ServerConfig.appVersion) (Build \(ServerConfig.buildNumber))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(LoginChrome.muted.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

        }
        .task {
            // Production always cycles; UI captures opt in explicitly to remain reproducible.
            guard !UIReviewFixture.isEnabled || CommandLine.arguments.contains("--ui-review-welcome-autocycle") else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_500_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
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
                        .stroke(LoginChrome.purple.opacity(0.10), lineWidth: 1)
                        .frame(width: diameter, height: diameter)
                }
                welcomePhoneContent
                    .frame(width: 190, height: 409)
                    .background(RoundedRectangle(cornerRadius: 27).fill(LoginChrome.card))
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
                Text("Kinnect").font(KinnectTheme.scaled(14, weight: .bold))
                    .foregroundColor(LoginChrome.purple)
                Spacer()
                Image(systemName: "bell").font(.system(size: 11))
                Image("WelcomeProfile").resizable().scaledToFill()
                    .frame(width: 17, height: 17).clipShape(Circle())
            }
            Text(L10n.tr(["Bảng tin", "Khám phá", "Video", "Live"][welcomePreview]))
                .font(.system(size: 8)).foregroundColor(LoginChrome.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            welcomePreviewPage
                .id(welcomePreview)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        welcomePreview = (welcomePreview + 1) % 4
                    }
                }
            HStack(spacing: 0) {
                welcomeMiniTab("house", title: "Bảng tin", index: 0)
                welcomeMiniTab("safari", title: "Khám phá", index: 1)
                Image(systemName: "plus").font(KinnectTheme.scaled(20))
                    .frame(width: 27, height: 27)
                    .foregroundColor(.white)
                    .background(RoundedRectangle(cornerRadius: 9).fill(LoginChrome.purple))
                welcomeMiniTab("play.rectangle", title: "Video", index: 2)
                welcomeMiniTab("dot.radiowaves.left.and.right", title: "Live", index: 3)
            }
            Capsule().fill(LoginChrome.muted.opacity(0.25)).frame(width: 57, height: 3)
                .padding(.bottom, 4)
        }
        .foregroundColor(LoginChrome.ink)
        .padding(.horizontal, 9)
    }

    private func welcomeMiniTab(_ icon: String, title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { welcomePreview = index }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(KinnectTheme.scaled(12))
                Text(L10n.tr(title)).font(.system(size: 6)).lineLimit(1)
            }
            .foregroundColor(welcomePreview == index ? LoginChrome.purple : LoginChrome.muted)
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
                    Text(L10n.tr("Dành cho bạn")).foregroundColor(LoginChrome.purple)
                    Spacer()
                    Text(L10n.tr("Đang theo dõi"))
                }
                .font(.system(size: 7, weight: .semibold))
                .padding(6).background(RoundedRectangle(cornerRadius: 7).fill(LoginChrome.wash))
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    Text(L10n.tr("Tên đăng nhập"))
                    Spacer()
                }
                .font(.system(size: 8)).foregroundColor(LoginChrome.muted)
                .padding(7).background(RoundedRectangle(cornerRadius: 7).fill(LoginChrome.wash))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        VStack(spacing: 3) {
                            welcomePortrait(["WelcomeProfile", "WelcomeProfile1", "WelcomeProfile2", "WelcomeProfile3"][index])
                                .frame(width: 80, height: 72)
                            Text(["Minh Anh, 27", "Gia Huy, 28", "Hoàng Nam, 30", "Quang Minh, 26"][index])
                                .font(.system(size: 7, weight: .semibold)).lineLimit(1)
                                .padding(.bottom, 4)
                        }
                        .background(LoginChrome.wash)
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
                    Text("@minhanh_demo")
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
                                .fill(LoginChrome.wash)
                                .frame(width: 26, height: 26)
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(LoginChrome.purple)
                        }
                        Text(L10n.tr("Tạo tin"))
                            .font(.system(size: 7))
                            .foregroundColor(LoginChrome.muted)
                    }

                    VStack(spacing: 2) {
                        Image("WelcomeProfile")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(LoginChrome.purple, lineWidth: 1.5))
                        Text("Minh Anh")
                            .font(.system(size: 7))
                            .foregroundColor(LoginChrome.muted)
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
                        .foregroundColor(LoginChrome.muted)
                    Spacer()
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(LoginChrome.wash))

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
                                .foregroundColor(LoginChrome.ink)
                            Text(L10n.tr("Hồ sơ minh họa"))
                                .font(.system(size: 7))
                                .foregroundColor(LoginChrome.muted)
                        }
                        Spacer()
                    }

                    Text("Tập luyện mỗi ngày")
                        .font(.system(size: 8))
                        .foregroundColor(LoginChrome.ink)

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
                            .foregroundColor(LoginChrome.muted)
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.system(size: 10))
                            .foregroundColor(LoginChrome.muted)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(LoginChrome.wash.opacity(0.7)))
            }
        }
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
                    .font(KinnectTheme.scaled(20, weight: .bold))
                    .foregroundColor(LoginChrome.purple)
                Spacer(minLength: 8)
                Text(L10n.tr("Sống đúng mình."))
                    .font(KinnectTheme.scaled(13))
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
                .font(KinnectTheme.scaled(15, weight: .medium))
                .foregroundColor(LoginChrome.ink)
            }
            .padding(.top, 4)

            Button {
                showLoginLanguageSheet = true
            } label: {
                Text(L10n.tr("Tiếng Việt / English"))
                    .font(KinnectTheme.scaled(15, weight: .medium))
                    .foregroundColor(LoginChrome.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 21).fill(LoginChrome.wash))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("Chào bạn trở lại!"))
                    .font(KinnectTheme.scaled(28, weight: .bold))
                    .foregroundColor(LoginChrome.ink)
                Text(L10n.tr("Đăng nhập để tiếp tục những kết nối của bạn."))
                    .font(KinnectTheme.scaled(14))
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
                            .foregroundColor(LoginChrome.muted)
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
                            .foregroundColor(rememberLogin ? LoginChrome.purple : LoginChrome.muted)
                        Text(L10n.tr("Ghi nhớ"))
                            .font(KinnectTheme.scaled(14))
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
                        .font(KinnectTheme.scaled(14, weight: .semibold))
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
                        .font(KinnectTheme.scaled(16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(LoginChrome.purple))
                .foregroundColor(.white)
            }
            .disabled(isLoading || loginUsername.isEmpty || loginPassword.isEmpty)
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
                        .font(KinnectTheme.scaled(16, weight: .semibold))
                }
                .foregroundColor(LoginChrome.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LoginChrome.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(LoginChrome.line, lineWidth: 1)
                        )
                )
            }

            Text(L10n.tr("Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng."))
                .font(KinnectTheme.scaled(12))
                .foregroundColor(LoginChrome.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

            Text("Kinnect iOS v\(ServerConfig.appVersion) (Build \(ServerConfig.buildNumber))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(LoginChrome.muted.opacity(0.8))
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
                .font(KinnectTheme.scaled(22, weight: .bold))
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
                            .font(KinnectTheme.scaled(17))
                            .foregroundColor(LoginChrome.ink)
                        Spacer()
                        if loc.preference.rawValue == language.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundColor(LoginChrome.purple)
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
                        .foregroundColor(LoginChrome.purple)
                    Text(L10n.tr("Theo hệ thống"))
                        .font(KinnectTheme.scaled(17))
                        .foregroundColor(LoginChrome.ink)
                    Spacer()
                    if loc.preference == .system {
                        Image(systemName: "checkmark")
                            .foregroundColor(LoginChrome.purple)
                    }
                }
                .padding(.vertical, 8)
            }

            Button {
                showLoginLanguageSheet = false
            } label: {
                Text(L10n.tr("Đóng"))
                    .font(KinnectTheme.scaled(16, weight: .semibold))
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
                .font(KinnectTheme.scaled(13))
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
                    .font(KinnectTheme.scaled(15, weight: .semibold))
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
                .font(KinnectTheme.scaled(14))
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
            .submitLabel(field == .username ? .next : .go)
            .onSubmit {
                if field == .username {
                    focusedLoginField = .password
                } else if !loginUsername.isEmpty, !loginPassword.isEmpty, !isLoading {
                    Task { await performLogin() }
                }
            }
            .foregroundColor(LoginChrome.ink)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LoginChrome.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focused ? LoginChrome.purple : LoginChrome.line, lineWidth: focused ? 2 : 1)
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
            if nsErr.code == 1000 || nsErr.localizedDescription.lowercased().contains("unknown") {
                errorMessage = "Đăng nhập Apple trên bản cài Sideload cần tài khoản Apple Developer trả phí có kích hoạt Sign in with Apple Entitlement. Bạn vui lòng sử dụng Đăng nhập bằng Tên tài khoản & Mật khẩu bên dưới."
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
