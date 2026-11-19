import XCTest
@testable import Kinnect

final class KinnectOriginIsolationTests: XCTestCase {
    private let primaryProd = "https://app.kinnect.io.vn"
    private let fallbackProd = "https://kinnect-allocation.vuanh97nd.workers.dev"
    private let loopbackA = "https://127.0.0.1:18443"
    private let loopbackB = "https://127.0.0.1:18444"

    override func setUp() {
        super.setUp()
        KeychainStore.shared.clearAll()
        KeychainStore.shared.setRememberMe(true, for: primaryProd)
        AccountCache.shared.wipeAllCaches()
    }

    override func tearDown() {
        KeychainStore.shared.clearAll()
        AccountCache.shared.wipeAllCaches()
        super.tearDown()
    }

    func testFallbackOriginNeverReadsPrimaryCredentials() {
        KeychainStore.shared.saveSessionCookie("kinnect_session=primary_sess_only", for: primaryProd)
        KeychainStore.shared.saveDeviceCookie("kinnect_device=primary_dev_only", for: primaryProd)
        KeychainStore.shared.saveAccountId("uid_primary", for: primaryProd)

        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: primaryProd), "kinnect_session=primary_sess_only")
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: primaryProd), "kinnect_device=primary_dev_only")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: primaryProd), "uid_primary")

        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: fallbackProd), "")
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: fallbackProd), "")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: fallbackProd), "")
        XCTAssertEqual(KeychainStore.shared.cookieJarHeader(for: fallbackProd), "")
    }

    func testDistinctLoopbackPortsAreStrictlyIsolated() {
        KeychainStore.shared.saveSessionCookie("kinnect_session=loop_a", for: loopbackA)
        KeychainStore.shared.saveDeviceCookie("kinnect_device=dev_a", for: loopbackA)
        KeychainStore.shared.saveAccountId("uid_a", for: loopbackA)

        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: loopbackA), "kinnect_session=loop_a")
        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: loopbackB), "")
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: loopbackB), "")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: loopbackB), "")
        XCTAssertEqual(KeychainStore.shared.cookieJarHeader(for: loopbackB), "")
    }

    func testCaseAndDefaultPortNormalizationPreservesExistingPrimarySession() {
        KeychainStore.shared.saveSessionCookie("kinnect_session=primary_norm", for: primaryProd)
        KeychainStore.shared.saveDeviceCookie("kinnect_device=device_norm", for: primaryProd)
        KeychainStore.shared.saveAccountId("uid_norm", for: primaryProd)

        let upperVariant = "https://APP.KINNECT.IO.VN:443/"
        XCTAssertEqual(KeychainStore.shared.normalizedOriginKey(upperVariant), primaryProd)
        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: upperVariant), "kinnect_session=primary_norm")
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: upperVariant), "kinnect_device=device_norm")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: upperVariant), "uid_norm")
    }

    func testInvalidOriginsAreRejectedWithoutTouchingDefaultOrigin() {
        KeychainStore.shared.saveSessionCookie("kinnect_session=primary_safe", for: primaryProd)
        KeychainStore.shared.saveDeviceCookie("kinnect_device=device_safe", for: primaryProd)
        KeychainStore.shared.saveAccountId("uid_safe", for: primaryProd)

        let invalidOrigins = [
            "",
            "http://app.kinnect.io.vn",
            "http://127.0.0.1:8080",
            "https://user:pass@app.kinnect.io.vn",
            "https://app.kinnect.io.vn/api/posts",
            "not-a-url"
        ]

        for bad in invalidOrigins {
            XCTAssertNil(KeychainStore.shared.normalizedOriginKey(bad), "Invalid origin should normalize to nil: \(bad)")
            XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: bad), "")
            XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: bad), "")
            XCTAssertEqual(KeychainStore.shared.loadAccountId(for: bad), "")
            XCTAssertEqual(KeychainStore.shared.cookieJarHeader(for: bad), "")

            // Attempt to overwrite or clear via invalid origin must not affect primaryProd
            KeychainStore.shared.saveSessionCookie("kinnect_session=poison", for: bad)
            KeychainStore.shared.saveDeviceCookie("kinnect_device=poison", for: bad)
            KeychainStore.shared.saveAccountId("uid_poison", for: bad)
            KeychainStore.shared.clearSession(for: bad)
        }

        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: primaryProd), "kinnect_session=primary_safe")
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: primaryProd), "kinnect_device=device_safe")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: primaryProd), "uid_safe")
    }

    func testClearSessionPerOriginIsolatesLogoutAndPreservesRememberedDevice() {
        KeychainStore.shared.saveSessionCookie("kinnect_session=p_sess", for: primaryProd)
        KeychainStore.shared.saveDeviceCookie("kinnect_device=p_dev", for: primaryProd)
        KeychainStore.shared.saveAccountId("uid_p", for: primaryProd)

        KeychainStore.shared.saveSessionCookie("kinnect_session=f_sess", for: fallbackProd)
        KeychainStore.shared.saveDeviceCookie("kinnect_device=f_dev", for: fallbackProd)
        KeychainStore.shared.saveAccountId("uid_f", for: fallbackProd)

        // Clearing fallback session must NOT affect primary or fallback device cookie
        KeychainStore.shared.clearSession(for: fallbackProd)

        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: fallbackProd), "")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: fallbackProd), "")
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: fallbackProd), "kinnect_device=f_dev")

        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: primaryProd), "kinnect_session=p_sess")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: primaryProd), "uid_p")
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: primaryProd), "kinnect_device=p_dev")
    }

    func testClearAuthSessionsWipesBothOriginsSessionsWhilePreservingRememberedDevices() {
        KeychainStore.shared.saveSessionCookie("kinnect_session=p_sess", for: primaryProd)
        KeychainStore.shared.saveDeviceCookie("kinnect_device=p_dev", for: primaryProd)
        KeychainStore.shared.saveAccountId("uid_p", for: primaryProd)

        KeychainStore.shared.saveSessionCookie("kinnect_session=f_sess", for: fallbackProd)
        KeychainStore.shared.saveDeviceCookie("kinnect_device=f_dev", for: fallbackProd)
        KeychainStore.shared.saveAccountId("uid_f", for: fallbackProd)

        KeychainStore.shared.clearAuthSessions()

        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: primaryProd), "")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: primaryProd), "")
        XCTAssertEqual(KeychainStore.shared.loadSessionCookie(for: fallbackProd), "")
        XCTAssertEqual(KeychainStore.shared.loadAccountId(for: fallbackProd), "")

        // Remembered-device cookies remain intact for both origins
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: primaryProd), "kinnect_device=p_dev")
        XCTAssertEqual(KeychainStore.shared.loadDeviceCookie(for: fallbackProd), "kinnect_device=f_dev")
    }

    func testAccountCacheIsolatesPrimaryAndFallbackOrigins() {
        let primaryData = Data("{\"origin\":\"primary\"}".utf8)
        let fallbackData = Data("{\"origin\":\"fallback\"}".utf8)

        AccountCache.shared.store(primaryData, forKey: "json:/api/posts", origin: primaryProd, accountId: "uid_1")
        AccountCache.shared.store(fallbackData, forKey: "json:/api/posts", origin: fallbackProd, accountId: "uid_1")

        let loadedPrimary = AccountCache.shared.load(forKey: "json:/api/posts", origin: primaryProd, accountId: "uid_1")
        let loadedPrimaryUpper = AccountCache.shared.load(forKey: "json:/api/posts", origin: "https://APP.KINNECT.IO.VN:443/", accountId: "uid_1")
        let loadedFallback = AccountCache.shared.load(forKey: "json:/api/posts", origin: fallbackProd, accountId: "uid_1")

        XCTAssertEqual(loadedPrimary, primaryData)
        XCTAssertEqual(loadedPrimaryUpper, primaryData)
        XCTAssertEqual(loadedFallback, fallbackData)
        XCTAssertNotEqual(loadedPrimary, loadedFallback)
    }
}
