import Foundation
import AuthenticationServices
import UIKit

@MainActor
final class OAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()

    @Published var availableProviders: [String] = []
    @Published var isAuthenticating: Bool = false
    @Published var oauthError: String?

    private var authSession: ASWebAuthenticationSession?

    override private init() {
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
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

    func startOAuth(provider: String, completion: @escaping (Result<KinnectUser, Error>) -> Void) {
        guard let origin = URL(string: ServerConfig.currentOrigin) else {
            completion(.failure(NSError(domain: "KinnectOAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Máy chủ chưa được cấu hình."])))
            return
        }

        let startURL = origin.appendingPathComponent("/api/oauth/\(provider)/start")
        var comps = URLComponents(url: startURL, resolvingAgainstBaseURL: true)
        comps?.queryItems = [URLQueryItem(name: "client", value: "android")]

        guard let targetURL = comps?.url else {
            completion(.failure(NSError(domain: "KinnectOAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Đường dẫn OAuth không hợp lệ."])))
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
                    // User dismissed the auth dialog
                    return
                }
                if let error = error {
                    self?.oauthError = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                guard let callbackURL = callbackURL else {
                    let err = NSError(domain: "KinnectOAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không nhận được phản hồi từ dịch vụ xác thực."])
                    self?.oauthError = err.localizedDescription
                    completion(.failure(err))
                    return
                }

                await self?.handleCallbackURL(callbackURL, completion: completion)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true
        self.authSession = session
        session.start()
    }

    private func handleCallbackURL(_ url: URL, completion: @escaping (Result<KinnectUser, Error>) -> Void) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            completion(.failure(NSError(domain: "KinnectOAuth", code: -4, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu trả về không hợp lệ."])))
            return
        }

        if let err = queryItems.first(where: { $0.name == "error" })?.value {
            let msg = err == "cancelled" ? "Đã hủy đăng nhập." : "Lỗi xác thực: \(err)"
            self.oauthError = msg
            completion(.failure(NSError(domain: "KinnectOAuth", code: -5, userInfo: [NSLocalizedDescriptionKey: msg])))
            return
        }

        if let code = queryItems.first(where: { $0.name == "code" })?.value {
            // Returning user session exchange
            do {
                let res = try await KinnectAPIClient.shared.requestJSON(
                    "/api/oauth/app-session",
                    method: "POST",
                    body: ["code": code]
                )
                if let userDict = res["user"] as? [String: Any] {
                    let user = KinnectUser.from(userDict)
                    AppState.shared.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: true)
                    await AppState.shared.refreshGlobalBadges()
                    await AppState.shared.refreshBlockedUsers()
                    completion(.success(user))
                } else {
                    throw NSError(domain: "KinnectOAuth", code: -6, userInfo: [NSLocalizedDescriptionKey: "Không tạo được phiên đăng nhập."])
                }
            } catch {
                self.oauthError = error.localizedDescription
                completion(.failure(error))
            }
        } else if let ticket = queryItems.first(where: { $0.name == "ticket" })?.value {
            // First time registration with provider ticket
            do {
                let pending = try await KinnectAPIClient.shared.requestJSON("/api/oauth/pending?ticket=\(ticket)")
                let suggested = (pending["suggestedUsername"] as? String) ?? "ban_\(UUID().uuidString.prefix(6))"
                let completeRes = try await KinnectAPIClient.shared.requestJSON(
                    "/api/oauth/complete",
                    method: "POST",
                    body: [
                        "ticket": ticket,
                        "username": suggested,
                        "agree18": true
                    ]
                )
                if let userDict = completeRes["user"] as? [String: Any] {
                    let user = KinnectUser.from(userDict)
                    AppState.shared.applyAuthenticatedUser(user, rawDict: userDict, rememberMe: true)
                    await AppState.shared.refreshGlobalBadges()
                    completion(.success(user))
                }
            } catch {
                self.oauthError = error.localizedDescription
                completion(.failure(error))
            }
        }
    }
}
