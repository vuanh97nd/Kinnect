import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var oauth = OAuthManager.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum AuthStage: String {
        case welcome = "Chào mừng"
        case login = "Đăng nhập"
        case register = "Đăng ký"
        case forgotPassword = "Quên mật khẩu"
    }

    @State private var stage: AuthStage = .welcome
    @State private var identifier = ""
    @State private var fullName = ""
    @State private var handle = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var rememberMe: Bool = UserDefaults.standard.object(forKey: "kinnect_session_remembered") as? Bool ?? true
    @State private var agree18 = false
    @State private var acceptPrivacy = false
    @State private var showPrivacyNotice = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    init(initialStage: AuthStage = .welcome) {
        _stage = State(initialValue: initialStage)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch stage {
                case .welcome:
                    welcomeView
                case .login:
                    loginView
                case .register:
                    registerView
                case .forgotPassword:
                    forgotPasswordView
                }

                #if DEBUG
                if !UIReviewFixture.isEnabled {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(KinnectTheme.online)
                            .frame(width: 8, height: 8)
                        Text("Máy chủ: \(ServerConfig.currentOrigin)")
                            .font(.caption2)
                            .foregroundColor(KinnectTheme.textSecondary)
                            .kinnectMultiline()
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                #endif
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .background(KinnectTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showPrivacyNotice) {
            PrivacyConsentSheet(
                request: PrivacyConsentRequest(
                    version: "",
                    notice: "Kinnect lưu hồ sơ, nội dung và tin nhắn trên máy chủ; không có mã hóa đầu cuối. Ảnh hồ sơ, bài đăng, ảnh/video và nội dung công khai có thể được gửi tới Cloudflare hoặc NVIDIA để kiểm duyệt. Tin nhắn hỗ trợ chỉ được gửi tới AI khi bạn chủ động bật trợ lý AI. Bạn có thể ẩn thông tin, báo cáo, chặn và xóa tài khoản cùng dữ liệu trong Cài đặt. Không gửi mật khẩu hoặc OTP. Chính sách đầy đủ: https://kinnect.io.vn/privacy. Liên hệ: anhvn53@wru.vn."
                ),
                recordOnServer: false,
                onAccepted: {
                    acceptPrivacy = true
                }
            )
        }
        .task {
            await oauth.checkAvailableProviders()
            if let active = UIReviewFixture.activeScreen {
                switch active {
                case "auth-login":
                    stage = .login
                    if identifier.isEmpty { identifier = "minhanh" }
                case "auth-register":
                    stage = .register
                    if fullName.isEmpty { fullName = "Nguyễn Minh Anh" }
                    if handle.isEmpty { handle = "minhanh" }
                    if identifier.isEmpty { identifier = "minhanh@kinnect.vn" }
                case "auth-reset", "auth-forgot", "forgot-password":
                    stage = .forgotPassword
                    if identifier.isEmpty { identifier = "minhanh@kinnect.vn" }
                default:
                    stage = .welcome
                }
            }
        }
    }

    // MARK: - 1. Welcome View (First Launch / Unauthenticated Home - 100% Android Parity)
    private var welcomeView: some View {
        VStack(spacing: 20) {
            // Top Bar: Logo + Brand (left) and Language + Login button (right)
            HStack(spacing: 8) {
                KinnectBrandLogo(size: 34)
                Text("Kinnect")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(KinnectTheme.accentBright)

                Spacer()

                KinnectLanguageButton()

                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .login
                    }
                } label: {
                    Text(L10n.tr("Đăng nhập"))
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KinnectTheme.accentBright))
                        .foregroundColor(.white)
                }
            }
            .padding(.top, 12)

            // Headline
            Text(L10n.tr("Kết nối đúng gu.\nSống đúng mình."))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(KinnectTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            // Feature Showcase Preview Cards (Feed, Discover, Shorts, Live)
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    featureShowcaseCard(icon: "newspaper.fill", title: L10n.tr("Bảng tin"), desc: "Chia sẻ khoảnh khắc")
                    featureShowcaseCard(icon: "compass.drawing", title: L10n.tr("Khám phá"), desc: "Tìm bạn cùng gu")
                }
                HStack(spacing: 12) {
                    featureShowcaseCard(icon: "play.rectangle.fill", title: L10n.tr("Video"), desc: "Shorts giải trí")
                    featureShowcaseCard(icon: "dot.radiowaves.left.and.right", title: "Live", desc: "Trực tiếp & phòng game")
                }
            }
            .padding(.vertical, 10)

            // Action Buttons
            VStack(spacing: 12) {
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.25)) {
                        stage = .register
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text(L10n.tr("Bắt đầu kết nối"))
                            .font(.headline)
                        Spacer()
                    }
                    .frame(height: 52)
                    .background(KinnectTheme.primaryGradient)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Text(L10n.tr("Dành cho người từ 18 tuổi · Minh họa tính năng"))
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)

                socialAuthSection
            }

            // Community & Privacy Rules Footer
            VStack(spacing: 4) {
                Text(L10n.tr("Tiếp tục nghĩa là bạn đồng ý quy tắc cộng đồng."))
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
                HStack(spacing: 4) {
                    Link(destination: URL(string: "https://kinnect.io.vn/community")!) {
                        Text("Quy tắc cộng đồng")
                            .font(.caption2.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                    Text("&")
                        .font(.caption2)
                        .foregroundColor(KinnectTheme.textSecondary)
                    Link(destination: URL(string: "https://kinnect.io.vn/privacy")!) {
                        Text("Chính sách quyền riêng tư")
                            .font(.caption2.bold())
                            .foregroundColor(KinnectTheme.accentBright)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 20)
        }
    }

    private func featureShowcaseCard(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(KinnectTheme.accentBright)
                .frame(width: 32)
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
        .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated.opacity(0.8)))
    }

    // MARK: - 2. Primary Login View
    private var loginView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Top Bar with Back Icon and Language Switcher
            HStack {
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .welcome
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                            .font(.subheadline.bold())
                        Text(L10n.tr("Trang chủ"))
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(KinnectTheme.textPrimary)
                }
                .accessibilityLabel(L10n.tr("Về trang giới thiệu"))

                Spacer()

                KinnectLanguageButton()
            }
            .padding(.top, 12)

            // Header Copy
            VStack(alignment: .leading, spacing: 6) {
                Text("Chào bạn trở lại!")
                    .font(.title2.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text("Đăng nhập để tiếp tục những kết nối của bạn.")
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .kinnectMultiline()
            }

            // Input Fields Card
            VStack(alignment: .leading, spacing: 14) {
                fieldBlock(
                    title: "Tên đăng nhập / Email / SĐT",
                    placeholder: "vd: minh_anh hoặc 09xxxxxxxx",
                    text: $identifier
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mật khẩu")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(KinnectTheme.textSecondary)
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
                            glyph: showPassword ? .eye : .eye,
                            label: showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu",
                            tint: KinnectTheme.textSecondary
                        ) {
                            showPassword.toggle()
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                }

                // Compact Checkbox Row with Quên mật khẩu on Right (Responsive for Dynamic Type)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        rememberMeCheckbox
                        Button("Quên mật khẩu?") {
                            errorMessage = nil
                            infoMessage = nil
                            withAnimation(.easeInOut(duration: 0.2)) {
                                stage = .forgotPassword
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                    }
                } else {
                    HStack {
                        rememberMeCheckbox
                        Spacer()
                        Button("Quên mật khẩu?") {
                            errorMessage = nil
                            infoMessage = nil
                            withAnimation(.easeInOut(duration: 0.2)) {
                                stage = .forgotPassword
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(KinnectTheme.accentBright)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(KinnectTheme.danger)
                        .kinnectMultiline()
                }

                Button {
                    Task { await submitLogin() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Đăng nhập")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .frame(height: 50)
                    .background(canSubmitLogin ? KinnectTheme.primaryGradient : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSubmitLogin || isSubmitting)
                .padding(.top, 4)

                socialAuthSection
            }
            .kinnectCard()

            // Footer Switch to Registration (Integrated container)
            HStack {
                Spacer()
                Text("Chưa có tài khoản?")
                    .font(.footnote)
                    .foregroundColor(KinnectTheme.textSecondary)
                Button("Đăng ký ngay") {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.25)) {
                        stage = .register
                    }
                }
                .font(.footnote.bold())
                .foregroundColor(KinnectTheme.accentBright)
                Spacer()
            }
            .padding(.top, 6)
        }
    }

    private var rememberMeCheckbox: some View {
        Button {
            rememberMe.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundColor(rememberMe ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                Text("Ghi nhớ đăng nhập")
                    .font(.footnote)
                    .foregroundColor(KinnectTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    private var canSubmitLogin: Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    // MARK: - 3. Integrated Registration View
    private var registerView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Top Bar with Back Icon and Language Switcher
            HStack {
                Button {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .welcome
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                            .font(.subheadline.bold())
                        Text(L10n.tr("Trang chủ"))
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(KinnectTheme.textPrimary)
                }
                .accessibilityLabel(L10n.tr("Về trang giới thiệu"))

                Spacer()

                KinnectLanguageButton()
            }
            .padding(.top, 12)

            // Header Copy
            VStack(alignment: .leading, spacing: 6) {
                Text("Bắt đầu kết nối của bạn.")
                    .font(.title2.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text("Tạo tài khoản để chia sẻ và gặp người cùng tần số.")
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .kinnectMultiline()
            }

            // Input Fields Card
            VStack(alignment: .leading, spacing: 14) {
                fieldBlock(title: "Tên hiển thị", placeholder: "Tên mọi người sẽ thấy", text: $fullName)

                fieldBlock(title: "Tên đăng nhập (@handle)", placeholder: "vd: minh_anh", text: $handle)
                    .textInputAutocapitalization(.never)

                fieldBlock(
                    title: "Email hoặc Số điện thoại",
                    placeholder: "nhap@email.com hoặc 09xxxxxxxx",
                    text: $identifier
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Mật khẩu")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(KinnectTheme.textSecondary)
                    HStack(spacing: 4) {
                        Group {
                            if showPassword {
                                TextField("Tối thiểu 6 ký tự", text: $password)
                            } else {
                                SecureField("Tối thiểu 6 ký tự", text: $password)
                            }
                        }
                        .padding(.leading, 12)
                        .padding(.vertical, 12)
                        .foregroundColor(KinnectTheme.textPrimary)

                        KinnectIconButton(
                            glyph: showPassword ? .eye : .eye,
                            label: showPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu",
                            tint: KinnectTheme.textSecondary
                        ) {
                            showPassword.toggle()
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                }

                // Explicit Checkbox 1: 18+ (NOT defaulted true)
                Button {
                    agree18.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: agree18 ? "checkmark.square.fill" : "square")
                            .font(.body)
                            .foregroundColor(agree18 ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                            .padding(.top, 2)
                        Text("Tôi xác nhận mình đủ 18 tuổi và đồng ý với quy tắc cộng đồng.")
                            .font(.footnote)
                            .foregroundColor(KinnectTheme.textPrimary)
                            .kinnectMultiline()
                    }
                }
                .buttonStyle(.plain)

                // Explicit Checkbox 2: Privacy (NOT defaulted true)
                Button {
                    acceptPrivacy.toggle()
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: acceptPrivacy ? "checkmark.square.fill" : "square")
                            .font(.body)
                            .foregroundColor(acceptPrivacy ? KinnectTheme.accentBright : KinnectTheme.textSecondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tôi đồng ý với Chính sách quyền riêng tư & Điều khoản Kinnect.")
                                .font(.footnote)
                                .foregroundColor(KinnectTheme.textPrimary)
                                .kinnectMultiline()
                        }
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showPrivacyNotice = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Đọc toàn văn chính sách bảo vệ dữ liệu")
                            .font(.caption.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(KinnectTheme.accentBright)
                    .padding(.leading, 26)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(KinnectTheme.danger)
                        .kinnectMultiline()
                }

                Button {
                    Task { await submitRegister() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Tạo tài khoản")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .frame(height: 50)
                    .background(canSubmitRegister ? KinnectTheme.primaryGradient : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSubmitRegister || isSubmitting)
                .padding(.top, 4)
            }
            .kinnectCard()

            // Footer Switch Back to Login
            HStack {
                Spacer()
                Text("Đã có tài khoản?")
                    .font(.footnote)
                    .foregroundColor(KinnectTheme.textSecondary)
                Button("Đăng nhập") {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.25)) {
                        stage = .login
                    }
                }
                .font(.footnote.bold())
                .foregroundColor(KinnectTheme.accentBright)
                Spacer()
            }
            .padding(.top, 6)
        }
    }

    private var canSubmitRegister: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        password.count >= 6 &&
        agree18 &&
        acceptPrivacy
    }

    // MARK: - 4. Forgot Password Subflow
    private var forgotPasswordView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Top Bar with Back Icon returning to Login
            HStack {
                KinnectIconButton(glyph: .back, label: "Quay lại đăng nhập", tint: KinnectTheme.textSecondary) {
                    errorMessage = nil
                    infoMessage = nil
                    withAnimation(.easeInOut(duration: 0.2)) {
                        stage = .login
                    }
                }
                Spacer()
            }
            .padding(.top, 12)

            // Header Copy
            VStack(alignment: .leading, spacing: 6) {
                Text("Quên mật khẩu")
                    .font(.title2.bold())
                    .foregroundColor(KinnectTheme.textPrimary)
                Text("Chúng tôi sẽ gửi mã xác minh hoặc hướng dẫn tới email khôi phục của bạn.")
                    .font(.subheadline)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .kinnectMultiline()
            }

            // Input Fields Card
            VStack(alignment: .leading, spacing: 14) {
                fieldBlock(
                    title: "Tên đăng nhập hoặc email khôi phục",
                    placeholder: "vd: minh_anh hoặc nhap@email.com",
                    text: $identifier
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)

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
                    Task { await submitReset() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Gửi mã qua email")
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .frame(height: 50)
                    .background(!identifier.isEmpty ? KinnectTheme.primaryGradient : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(identifier.isEmpty || isSubmitting)
                .padding(.top, 4)
            }
            .kinnectCard()

            // Support link
            HStack {
                Spacer()
                Text("Chưa có email khôi phục?")
                    .font(.footnote)
                    .foregroundColor(KinnectTheme.textSecondary)
                Link(destination: URL(string: "https://kinnect.io.vn/privacy")!) {
                    Text("Gửi yêu cầu hỗ trợ")
                        .font(.footnote.bold())
                        .foregroundColor(KinnectTheme.accentBright)
                }
                Spacer()
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Social Auth Section (Google, Facebook, Apple)
    private var socialAuthSection: some View {
        VStack(spacing: 10) {
            HStack {
                VStack { Divider().background(KinnectTheme.border) }
                Text("hoặc")
                    .font(.caption2)
                    .foregroundColor(KinnectTheme.textSecondary)
                    .padding(.horizontal, 8)
                VStack { Divider().background(KinnectTheme.border) }
            }
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                // Google OAuth Button
                Button {
                    oauth.startOAuth(provider: "google") { _ in }
                } label: {
                    HStack(spacing: 8) {
                        Text("G")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.9, green: 0.25, blue: 0.2))
                        Text("Google")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(KinnectTheme.border, lineWidth: 1))
                }

                // Facebook OAuth Button
                Button {
                    oauth.startOAuth(provider: "facebook") { _ in }
                } label: {
                    HStack(spacing: 8) {
                        Text("f")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.1, green: 0.45, blue: 0.9))
                        Text("Facebook")
                            .font(.subheadline.bold())
                            .foregroundColor(KinnectTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(KinnectTheme.surfaceElevated))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(KinnectTheme.border, lineWidth: 1))
                }
            }

            if let oauthErr = oauth.oauthError {
                Text(oauthErr)
                    .font(.caption)
                    .foregroundColor(KinnectTheme.warning)
                    .kinnectMultiline()
            }
        }
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

    // MARK: - Submission Actions
    private func submitLogin() async {
        errorMessage = nil
        infoMessage = nil
        let cleanId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else {
            errorMessage = "Vui lòng nhập thông tin tài khoản."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Vui lòng nhập mật khẩu."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            KeychainStore.shared.setRememberMe(rememberMe)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitRegister() async {
        errorMessage = nil
        infoMessage = nil
        let cleanId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
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

        isSubmitting = true
        defer { isSubmitting = false }

        do {
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
            let cleanHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitReset() async {
        errorMessage = nil
        infoMessage = nil
        let cleanId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else {
            errorMessage = "Vui lòng nhập tên đăng nhập hoặc email."
            return
        }

        if UIReviewFixture.activeScreen != nil {
            infoMessage = "Đã gửi mã xác nhận tới \(cleanId)."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/password-reset",
                method: "POST",
                body: ["identifier": cleanId]
            )
            let msg = res["message"] as? String ?? "Đã gửi yêu cầu khôi phục mật khẩu."
            infoMessage = msg
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
