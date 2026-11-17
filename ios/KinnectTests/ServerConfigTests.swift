import XCTest
@testable import Kinnect

final class ServerConfigTests: XCTestCase {
    func testNormalizeRejectsHttpScheme() {
        XCTAssertNil(ServerConfig.normalize("http://app.kinnect.io.vn"))
    }

    func testNormalizeRejectsUserinfo() {
        XCTAssertNil(ServerConfig.normalize("https://user:pass@app.kinnect.io.vn"))
        XCTAssertNil(ServerConfig.normalize("https://admin@app.kinnect.io.vn"))
    }

    func testNormalizeRejectsQuery() {
        XCTAssertNil(ServerConfig.normalize("https://app.kinnect.io.vn?redirect=1"))
    }

    func testNormalizeRejectsNonRootPath() {
        XCTAssertNil(ServerConfig.normalize("https://app.kinnect.io.vn/api/v1"))
    }

    func testNormalizeRejectsFragment() {
        XCTAssertNil(ServerConfig.normalize("https://app.kinnect.io.vn#section"))
    }

    func testNormalizeAcceptsValidHttpsOrigin() {
        XCTAssertEqual(ServerConfig.normalize("  https://APP.KINNECT.IO.VN/  "), "https://app.kinnect.io.vn")
    }

    func testNormalizePreservesCustomPortAndStripsDefault443() {
        XCTAssertEqual(ServerConfig.normalize("https://app.kinnect.io.vn:443"), "https://app.kinnect.io.vn")
        XCTAssertEqual(ServerConfig.normalize("https://app.kinnect.io.vn:8443/"), "https://app.kinnect.io.vn:8443")
    }

    func testMatchesOriginRejectsSpoofedHostSuffix() {
        let spoofedURL = URL(string: "https://kinnect.io.vn.evil.com/api/me")!
        XCTAssertFalse(ServerConfig.matchesOrigin(spoofedURL, origin: "https://kinnect.io.vn"))
        XCTAssertFalse(ServerConfig.matchesOrigin(spoofedURL, origin: "https://app.kinnect.io.vn"))
    }

    func testMatchesOriginRejectsHttpUrl() {
        let insecureURL = URL(string: "http://app.kinnect.io.vn/api/me")!
        XCTAssertFalse(ServerConfig.matchesOrigin(insecureURL, origin: "https://app.kinnect.io.vn"))
    }

    func testMatchesOriginRejectsUserinfoInUrl() {
        let userinfoURL = URL(string: "https://attacker:secret@app.kinnect.io.vn/api/me")!
        XCTAssertFalse(ServerConfig.matchesOrigin(userinfoURL, origin: "https://app.kinnect.io.vn"))
    }

    func testMatchesOriginRejectsDifferentPort() {
        let altPortURL = URL(string: "https://app.kinnect.io.vn:8443/api/me")!
        XCTAssertFalse(ServerConfig.matchesOrigin(altPortURL, origin: "https://app.kinnect.io.vn"))
    }

    func testMatchesOriginAcceptsValidOriginUrl() {
        let validURL = URL(string: "https://app.kinnect.io.vn:443/api/v1/feed?limit=20")!
        XCTAssertTrue(ServerConfig.matchesOrigin(validURL, origin: "https://app.kinnect.io.vn"))
    }
}
