#if DEBUG
import Foundation

/// Scoped debug-only URLProtocol stub and request contract helper for isolated
/// local harness verification without relaxing production ATS (`Info.plist`)
/// or `ServerConfig.normalize(_:)` HTTPS-only enforcement.
final class KinnectLocalStubURLProtocol: URLProtocol {
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var handlerStorage: RequestHandler?

    static var handler: RequestHandler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return handlerStorage
        }
        set {
            lock.lock()
            handlerStorage = newValue
            lock.unlock()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        handler != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum LocalTransportHarness {
    static func makeStubbedSession(handler: @escaping KinnectLocalStubURLProtocol.RequestHandler) -> URLSession {
        KinnectLocalStubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.protocolClasses = [KinnectLocalStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func makePasswordRequest(origin: String, current: String, next: String) throws -> URLRequest {
        try makeJSONRequest(origin: origin, method: "POST", path: "/api/me/password", body: [
            "current": current,
            "next": next
        ])
    }

    static func makeDmModeRequest(origin: String, dmMode: String) throws -> URLRequest {
        try makeJSONRequest(origin: origin, method: "PATCH", path: "/api/me", body: [
            "dmMode": dmMode
        ])
    }

    static func makeRevokeSessionRequest(origin: String, sessionId: String) throws -> URLRequest {
        try makeJSONRequest(
            origin: origin,
            method: "DELETE",
            path: "/api/me/sessions/\(sessionId)",
            body: ["requestId": "revoke_\(sessionId)"]
        )
    }

    private static func makeJSONRequest(origin: String, method: String, path: String, body: [String: Any]?) throws -> URLRequest {
        guard let url = ServerConfig.url(for: path, origin: origin) else {
            throw KinnectAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(origin, forHTTPHeaderField: "Origin")
        if method != "GET" && method != "HEAD" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body ?? [:])
        }
        return request
    }
}
#endif

