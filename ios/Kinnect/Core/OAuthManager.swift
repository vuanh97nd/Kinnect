import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

enum OAuthError: LocalizedError {
    case twoFactorRequired(code: String)
    case pendingRegistration(ticket: String, provider: String, name: String, suggestedUsername: String)
    case canceled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .twoFactorRequired:
            return L10n.tr("Tài khoản yêu cầu mã xác thực 2 bước (2FA).")
        case .pendingRegistration:
            return L10n.tr("Vui lòng chọn tên đăng nhập và xác nhận đủ 18 tuổi để hoàn tất đăng ký.")
        case .canceled:
            return L10n.tr("Đã hủy đăng nhập.")
        case .message(let text):
            return text
        }
    }
}

@MainActor
final class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static let shared = OAuthManager()

    @Published var availableProviders: [String] = []
    @Published var isAuthenticating: Bool = false
    @Published var oauthError: String?

    private var authSession: ASWebAuthenticationSession?
    private var appleAuthController: ASAuthorizationController?
    private var activeAppleNonce: String = ""
    private var appleContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    override private init() {
        super.init()
    }

    private var keyPresentationWindow: ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window
        }
        return UIWindow()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        keyPresentationWindow
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        keyPresentationWindow
    }

    func checkAvailableProviders() async {
        do {
            let res = try await KinnectAPIClient.shared.requestJSON("/api/oauth/providers")
            if let list = res["providers"] as? [String] {
                self.availableProviders = list
            }
        } catch {
            self.availableProviders = []
        }
    }

    @discardableResult
    func authenticate(provider: String, rememberMe: Bool = true, totpCode: String? = nil) async throws -> KinnectUser {
        if provider == "apple" {
            let res = try await reauthenticateWithApple(totpCode: totpCode)
            if let userDict = res["user"] as? [String: Any] {
                return await hydrateAndApplySession(fallbackUserDict: userDict, rememberMe: rememberMe)
            }
            return AppState.shared.currentUser ?? KinnectUser()
        }
        return try await withCheckedThrowingContinuation { continuation in
            startOAuth(provider: provider, rememberMe: rememberMe) { result in
                continuation.resume(with: result)
            }
        }
    }

    func hydrateAndApplySession(fallbackUserDict: [String: Any], rememberMe: Bool) async -> KinnectUser {
        var resolvedDict = fallbackUserDict
        if let meRes = try? await KinnectAPIClient.shared.requestJSON("/api/me"),
           let fullDict = meRes["user"] as? [String: Any],
           !((fullDict["id"] as? String) ?? "").isEmpty {
            resolvedDict = fullDict
        }
        let fullUser = KinnectUser.from(resolvedDict)
        AppState.shared.applyAuthenticatedUser(fullUser, rawDict: resolvedDict, rememberMe: rememberMe)
        await AppState.shared.refreshGlobalBadges()
        await AppState.shared.refreshBlockedUsers()
        return fullUser
    }

    struct SessionSnapshot {
        let origin: String
        let sessionCookie: String
        let deviceCookie: String
        let accountId: String

        static func capture() -> SessionSnapshot {
            let origin = KinnectAPIClient.shared.baseURL
            return SessionSnapshot(
                origin: origin,
                sessionCookie: KeychainStore.shared.loadSessionCookie(for: origin),
                deviceCookie: KeychainStore.shared.loadDeviceCookie(for: origin),
                accountId: KeychainStore.shared.loadAccountId(for: origin)
            )
        }

        func restore() {
            if sessionCookie.isEmpty {
                KeychainStore.shared.clearSession(for: origin)
            } else {
                KeychainStore.shared.saveSessionCookie(sessionCookie, for: origin)
            }
            if !deviceCookie.isEmpty {
                KeychainStore.shared.saveDeviceCookie(deviceCookie, for: origin)
            }
            if !accountId.isEmpty {
                KeychainStore.shared.saveAccountId(accountId, for: origin)
            }
            KeychainStore.shared.syncToHTTPCookieStorage(origin: origin)
        }
    }

    /// Re-authenticates an OAuth/Apple provider strictly for confirming deletion of `expectedUserId`.
    /// Never switches `AppState.shared.currentUser` and immediately restores the prior session if a different account signs in.
    func reauthenticateForAccountDeletion(provider: String, expectedUserId: String, totpCode: String? = nil) async throws {
        guard !expectedUserId.isEmpty else {
            throw OAuthError.message(L10n.tr("Không xác định được tài khoản hiện tại."))
        }
        let snapshot = SessionSnapshot.capture()
        let normalized = provider.lowercased()
        if normalized == "apple" {
            let res = try await reauthenticateWithApple(totpCode: totpCode)
            let returnedId = (res["user"] as? [String: Any])?["id"] as? String ?? ""
            guard returnedId == expectedUserId else {
                snapshot.restore()
                throw OAuthError.message(L10n.tr("Tài khoản Apple vừa xác thực không khớp với tài khoản đang yêu cầu xóa."))
            }
            return
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            startRawWebOAuthSession(provider: normalized) { result in
                continuation.resume(with: result)
            }
        }
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            throw OAuthError.message(L10n.tr("Dữ liệu trả về từ dịch vụ xác thực không hợp lệ."))
        }
        if let err = queryItems.first(where: { $0.name == "error" })?.value {
            if err == "cancelled" { throw OAuthError.canceled }
            throw OAuthError.message("\(L10n.tr("Lỗi xác thực:")) \(err)")
        }
        if queryItems.first(where: { $0.name == "ticket" })?.value != nil {
            snapshot.restore()
            throw OAuthError.message(String(format: L10n.tr("Tài khoản %@ này chưa liên kết với tài khoản hiện tại của bạn."), provider.capitalized))
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw OAuthError.message(L10n.tr("Phản hồi xác thực không hợp lệ."))
        }
        if queryItems.first(where: { $0.name == "requires2fa" })?.value == "1" {
            throw OAuthError.twoFactorRequired(code: code)
        }
        do {
            var body: [String: Any] = ["code": code]
            if let cleanTotp = totpCode?.trimmingCharacters(in: .whitespacesAndNewlines), !cleanTotp.isEmpty {
                body["totpCode"] = cleanTotp
            }
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/oauth/app-session",
                method: "POST",
                body: body
            )
            let returnedId = (res["user"] as? [String: Any])?["id"] as? String ?? ""
            guard returnedId == expectedUserId else {
                snapshot.restore()
                throw OAuthError.message(String(format: L10n.tr("Tài khoản %@ vừa xác thực không khớp với tài khoản đang yêu cầu xóa."), provider.capitalized))
            }
        } catch let error as KinnectAPIError {
            if case .serverError(let status, _) = error, status == 403 {
                throw OAuthError.twoFactorRequired(code: code)
            }
            snapshot.restore()
            throw error
        } catch {
            snapshot.restore()
            throw error
        }
    }

    func verifyOAuth2FAForAccountDeletion(code: String, totpCode: String, expectedUserId: String, snapshot: SessionSnapshot) async throws {
        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/oauth/app-session",
                method: "POST",
                body: ["code": code, "totpCode": totpCode]
            )
            let returnedId = (res["user"] as? [String: Any])?["id"] as? String ?? ""
            guard returnedId == expectedUserId else {
                snapshot.restore()
                throw OAuthError.message(L10n.tr("Tài khoản xác thực 2FA không khớp với tài khoản đang yêu cầu xóa."))
            }
        } catch {
            snapshot.restore()
            throw error
        }
    }

    @discardableResult
    func reauthenticateWithApple(totpCode: String? = nil) async throws -> [String: Any] {
        let rawNonce = UUID().uuidString + "-" + UUID().uuidString
        let hashedData = SHA256.hash(data: Data(rawNonce.utf8))
        let hashedNonce = hashedData.compactMap { String(format: "%02x", $0) }.joined()

        let credential: ASAuthorizationAppleIDCredential = try await withCheckedThrowingContinuation { continuation in
            if let prev = self.appleContinuation {
                self.appleContinuation = nil
                prev.resume(throwing: OAuthError.canceled)
            }
            self.activeAppleNonce = rawNonce
            self.appleContinuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.appleAuthController = controller
            controller.performRequests()
        }

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              !identityToken.isEmpty else {
            throw OAuthError.message(L10n.tr("Không nhận được token xác thực từ Apple."))
        }

        var body: [String: Any] = [
            "appleId": credential.user,
            "identityToken": identityToken,
            "nonce": rawNonce
        ]
        if let cleanTotp = totpCode?.trimmingCharacters(in: .whitespacesAndNewlines), !cleanTotp.isEmpty {
            body["totpCode"] = cleanTotp
        }

        do {
            let res = try await KinnectAPIClient.shared.requestJSON(
                "/api/oauth/apple",
                method: "POST",
                body: body
            )
            return res
        } catch let error as KinnectAPIError {
            if case .serverError(let status, let msg) = error,
               status == 403,
               (msg.localizedCaseInsensitiveContains("2FA")
                || msg.localizedCaseInsensitiveContains("2 bước")
                || msg.localizedCaseInsensitiveContains("2 lớp")) {
                throw OAuthError.twoFactorRequired(code: "")
            }
            throw error
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        appleAuthController = nil
        guard let continuation = appleContinuation else { return }
        appleContinuation = nil
        if let appleCred = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation.resume(returning: appleCred)
        } else {
            continuation.resume(throwing: OAuthError.message(L10n.tr("Không nhận diện được chứng chỉ Apple.")))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        appleAuthController = nil
        guard let continuation = appleContinuation else { return }
        appleContinuation = nil
        let nsErr = error as NSError
        if nsErr.domain == ASAuthorizationError.errorDomain && nsErr.code == ASAuthorizationError.canceled.rawValue {
            continuation.resume(throwing: OAuthError.canceled)
        } else {
            continuation.resume(throwing: error)
        }
    }

    private func startRawWebOAuthSession(provider: String, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let origin = URL(string: KinnectAPIClient.shared.baseURL) else {
            completion(.failure(NSError(domain: "KinnectOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Máy chủ chưa được cấu hình.")])))
            return
        }

        let startURL = origin.appendingPathComponent("/api/oauth/\(provider)/start")
        var comps = URLComponents(url: startURL, resolvingAgainstBaseURL: true)
        comps?.queryItems = [URLQueryItem(name: "client", value: "android")]

        guard let targetURL = comps?.url else {
            completion(.failure(NSError(domain: "KinnectOAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Đường dẫn OAuth không hợp lệ.")])))
            return
        }

        isAuthenticating = true
        oauthError = nil

        let session = ASWebAuthenticationSession(
            url: targetURL,
            callbackURLScheme: "kinnect"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.isAuthenticating = false
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    completion(.failure(OAuthError.canceled))
                    return
                }
                if let error = error {
                    self?.oauthError = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                guard let callbackURL = callbackURL else {
                    let err = NSError(domain: "KinnectOAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Không nhận được phản hồi từ dịch vụ xác thực.")])
                    self?.oauthError = err.localizedDescription
                    completion(.failure(err))
                    return
                }
                completion(.success(callbackURL))
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.authSession = session
        session.start()
    }

    func startOAuth(provider: String, rememberMe: Bool = true, completion: @escaping (Result<KinnectUser, Error>) -> Void) {
        startRawWebOAuthSession(provider: provider) { [weak self] result in
            switch result {
            case .success(let callbackURL):
                Task { @MainActor in
                    await self?.handleCallbackURL(callbackURL, providerFallback: provider, rememberMe: rememberMe, completion: completion)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func handleCallbackURL(_ url: URL, providerFallback: String = "", rememberMe: Bool, completion: @escaping (Result<KinnectUser, Error>) -> Void) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            completion(.failure(NSError(domain: "KinnectOAuth", code: -4, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Dữ liệu trả về không hợp lệ.")])))
            return
        }

        if let err = queryItems.first(where: { $0.name == "error" })?.value {
            if err == "cancelled" {
                self.oauthError = nil
                completion(.failure(OAuthError.canceled))
                return
            }
            let msg = "\(L10n.tr("Lỗi xác thực:")) \(err)"
            self.oauthError = msg
            completion(.failure(NSError(domain: "KinnectOAuth", code: -5, userInfo: [NSLocalizedDescriptionKey: msg])))
            return
        }

        if let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            let requires2FA = queryItems.first(where: { $0.name == "requires2fa" })?.value == "1"
            if requires2FA {
                self.oauthError = nil
                completion(.failure(OAuthError.twoFactorRequired(code: code)))
                return
            }

            // Returning user session exchange
            do {
                let res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/oauth/app-session",
                    method: "POST",
                    body: [
                        "code": code,
                        "remember": rememberMe
                    ]
                )
                if let userDict = res["user"] as? [String: Any] {
                    let user = await hydrateAndApplySession(fallbackUserDict: userDict, rememberMe: rememberMe)
                    completion(.success(user))
                } else {
                    throw NSError(domain: "KinnectOAuth", code: -6, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Không tạo được phiên đăng nhập.")])
                }
            } catch {
                if case KinnectAPIError.serverError(let status, _) = error, status == 403 {
                    self.oauthError = nil
                    completion(.failure(OAuthError.twoFactorRequired(code: code)))
                    return
                }
                self.oauthError = error.localizedDescription
                completion(.failure(error))
            }
        } else if let ticket = queryItems.first(where: { $0.name == "ticket" })?.value, !ticket.isEmpty {
            // First-time registration: fetch pending info and require explicit user username & 18+ consent in AuthView.
            do {
                let encodedTicket = ticket.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ticket
                let pending = try await KinnectAPIClient.shared.requestJSON("/api/oauth/pending?ticket=\(encodedTicket)")
                let provider = (pending["provider"] as? String) ?? providerFallback
                let name = (pending["name"] as? String) ?? ""
                let suggested = (pending["suggestedUsername"] as? String) ?? ""
                self.oauthError = nil
                completion(.failure(OAuthError.pendingRegistration(
                    ticket: ticket,
                    provider: provider,
                    name: name,
                    suggestedUsername: suggested
                )))
            } catch {
                self.oauthError = error.localizedDescription
                completion(.failure(error))
            }
        } else {
            let err = NSError(domain: "KinnectOAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Phản hồi xác thực không hợp lệ.")])
            self.oauthError = err.localizedDescription
            completion(.failure(err))
        }
    }
}
