import CryptoKit
import Foundation
import XCTest
@testable import Kinnect

final class AccountCacheTests: XCTestCase {
    private let cache = AccountCache.shared
    private let defaultOrigin = "https://app.kinnect.io.vn"
    private let alternateOrigin = "https://staging.kinnect.io.vn"

    override func setUp() {
        super.setUp()
        cache.wipeAllCaches()
    }

    override func tearDown() {
        cache.wipeAllCaches()
        super.tearDown()
    }

    func testStoreAndLoadReturnsExactData() {
        let payload = Data("{\"hello\":\"kinnect\",\"count\":42}".utf8)
        cache.store(payload, forKey: "feed.snapshot", origin: defaultOrigin, accountId: "account-1")

        let loaded = cache.load(forKey: "feed.snapshot", origin: defaultOrigin, accountId: "account-1")
        XCTAssertEqual(loaded, payload)
    }

    func testAccountIsolationPreventsCrossAccountRead() {
        let secretA = Data("private-data-for-account-A".utf8)
        cache.store(secretA, forKey: "messages.inbox", origin: defaultOrigin, accountId: "account-A")

        let leakToB = cache.load(forKey: "messages.inbox", origin: defaultOrigin, accountId: "account-B")
        XCTAssertNil(leakToB, "Account B must not be able to read Account A's cached data")

        let readByA = cache.load(forKey: "messages.inbox", origin: defaultOrigin, accountId: "account-A")
        XCTAssertEqual(readByA, secretA)
    }

    func testOriginIsolationPreventsCrossOriginReadForSameAccount() {
        let prodData = Data("prod-payload".utf8)
        cache.store(prodData, forKey: "user.profile", origin: defaultOrigin, accountId: "account-A")

        let stagingRead = cache.load(forKey: "user.profile", origin: alternateOrigin, accountId: "account-A")
        XCTAssertNil(stagingRead, "Different origins must not share cached entries for the same accountId")
    }

    func testDiskScopeUsesSHA256OfOriginAndAccountId() throws {
        let key = "disk.only.snapshot"
        let accountA = "user-sha-A"
        let accountB = "user-sha-B"
        let expectedData = Data("persisted-on-disk-for-A".utf8)

        let cachesBase = try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let rootDir = cachesBase.appendingPathComponent("kinnect-native-v2", isDirectory: true)

        let scopeDigestA = SHA256.hash(data: Data("\(defaultOrigin)|\(accountA)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let fileDigest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let dirA = rootDir.appendingPathComponent(scopeDigestA, isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        let fileURL = dirA.appendingPathComponent(fileDigest)
        try expectedData.write(to: fileURL, options: .atomic)

        // Not in memoryCache yet -> forces AccountCache.load to resolve SHA256(origin|accountId) on disk.
        let loadedFromB = cache.load(forKey: key, origin: defaultOrigin, accountId: accountB)
        XCTAssertNil(loadedFromB, "Account B must not read Account A's SHA256-scoped disk directory")

        let loadedFromA = cache.load(forKey: key, origin: defaultOrigin, accountId: accountA)
        XCTAssertEqual(loadedFromA, expectedData)
    }

    func testSaveAndLoadJSONObjectRoundTripAndAccountIsolation() {
        let sample: [String: Any] = [
            "id": "u_100",
            "name": "Kinnect QA",
            "unreadCount": 7
        ]

        cache.saveJSONObject(sample, forKey: "bootstrap.me", accountId: "account-json-A")

        let loadedForB: [String: Any]? = cache.loadJSONObject(forKey: "bootstrap.me", accountId: "account-json-B")
        XCTAssertNil(loadedForB)

        let loadedForA: [String: Any]? = cache.loadJSONObject(forKey: "bootstrap.me", accountId: "account-json-A")
        XCTAssertEqual(loadedForA?["id"] as? String, "u_100")
        XCTAssertEqual(loadedForA?["name"] as? String, "Kinnect QA")
        XCTAssertEqual(loadedForA?["unreadCount"] as? Int, 7)
    }

    func testEvictAndEmptyAccountGuardBehavior() {
        let dataA = Data("value-A".utf8)
        let dataB = Data("value-B".utf8)

        cache.store(dataA, forKey: "shared.key", origin: defaultOrigin, accountId: "")
        XCTAssertNil(cache.load(forKey: "shared.key", origin: defaultOrigin, accountId: ""))

        cache.store(dataA, forKey: "shared.key", origin: defaultOrigin, accountId: "account-A")
        cache.store(dataB, forKey: "shared.key", origin: defaultOrigin, accountId: "account-B")

        cache.evict(forKey: "shared.key", origin: defaultOrigin, accountId: "account-A")

        XCTAssertNil(cache.load(forKey: "shared.key", origin: defaultOrigin, accountId: "account-A"))
        XCTAssertEqual(cache.load(forKey: "shared.key", origin: defaultOrigin, accountId: "account-B"), dataB)
    }
}

/*
 GHI CHÚ VỀ CÁC PHẦN KHÔNG TEST ĐƯỢC TRONG AccountCache.swift (Theo luật không sửa code production):
 1. Prune về 75% của cap 64 MB & không xoá file mới nhất (`pruneDiskCacheIfNeeded`):
    - `AccountCache.init()` là `private`, chỉ truy cập được qua singleton `AccountCache.shared`.
    - `maxDiskCacheBytes` là hằng số `private let maxDiskCacheBytes: Int64 = 64 * 1024 * 1024` (64 MB cứng, không cho phép inject cap nhỏ).
    - `rootDirectory` là `private var` trỏ cố định vào `<Caches>/kinnect-native-v2` (không cho phép inject thư mục tạm riêng).
    - `pruneDiskCacheIfNeeded()` là hàm `private`, chỉ tự kích hoạt bất đồng bộ trên `queue` sau mỗi 20 lần gọi `store()` và chỉ cắt giảm khi tổng dung lượng đĩa vượt quá 64 MB thật.
    -> Do đó không thể test trực tiếp nhánh prune với cap nhỏ mà không sửa access control / dependency injection trong `AccountCache.swift`.
*/
