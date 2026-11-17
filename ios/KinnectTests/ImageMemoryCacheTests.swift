import UIKit
import XCTest
@testable import Kinnect

final class ImageMemoryCacheTests: XCTestCase {
    private let cache = ImageMemoryCache.shared

    override func setUp() {
        super.setUp()
        cache.clear()
    }

    override func tearDown() {
        cache.clear()
        super.tearDown()
    }

    func testSamePathWithDifferentMaxPointSizeProducesDifferentCacheKeys() {
        let path = "/uploads/avatars/user-42.jpg"
        let avatarKey = ImageMemoryCache.cacheKey(forKey: path, maxPointSize: 44, scale: 3.0)
        let feedKey = ImageMemoryCache.cacheKey(forKey: path, maxPointSize: 560, scale: 3.0)

        XCTAssertNotEqual(avatarKey, feedKey)
        XCTAssertEqual(avatarKey, "/uploads/avatars/user-42.jpg#px=160")
        XCTAssertEqual(feedKey, "/uploads/avatars/user-42.jpg#px=2048")
    }

    func testPixelBucketAssignsExpectedBucketsAndClampsBounds() {
        // 44pt vs 560pt must map to distinct pixel buckets across standard iOS scales
        let bucket44At2x = ImageMemoryCache.pixelBucket(forPointSize: 44, scale: 2.0)   // 88px -> 160
        let bucket560At2x = ImageMemoryCache.pixelBucket(forPointSize: 560, scale: 2.0) // 1120px -> 1440
        XCTAssertNotEqual(bucket44At2x, bucket560At2x)
        XCTAssertEqual(bucket44At2x, 160)
        XCTAssertEqual(bucket560At2x, 1440)

        // Verify bucket ladder [160, 320, 640, 960, 1440, 2048] at 1x scale
        XCTAssertEqual(ImageMemoryCache.pixelBucket(forPointSize: 10, scale: 1.0), 160)   // clamped to min 64px -> 160
        XCTAssertEqual(ImageMemoryCache.pixelBucket(forPointSize: 200, scale: 1.0), 320)
        XCTAssertEqual(ImageMemoryCache.pixelBucket(forPointSize: 500, scale: 1.0), 640)
        XCTAssertEqual(ImageMemoryCache.pixelBucket(forPointSize: 800, scale: 1.0), 960)
        XCTAssertEqual(ImageMemoryCache.pixelBucket(forPointSize: 1200, scale: 1.0), 1440)
        XCTAssertEqual(ImageMemoryCache.pixelBucket(forPointSize: 3000, scale: 1.0), 2048) // capped at 2048
    }

    func testCacheKeyHandlesEmptyKeyAndMissingOrNonPositivePointSize() {
        XCTAssertEqual(ImageMemoryCache.cacheKey(forKey: "", maxPointSize: 44, scale: 2.0), "")
        XCTAssertEqual(ImageMemoryCache.cacheKey(forKey: "/media/banner.png", maxPointSize: nil, scale: 2.0), "/media/banner.png")
        XCTAssertEqual(ImageMemoryCache.cacheKey(forKey: "/media/banner.png", maxPointSize: 0, scale: 2.0), "/media/banner.png")
        XCTAssertEqual(ImageMemoryCache.cacheKey(forKey: "/media/banner.png", maxPointSize: -12, scale: 2.0), "/media/banner.png")
    }

    func testStoreAndRetrieveImageScopedByMaxPointSize() {
        let path = "/uploads/posts/photo-1.jpg"
        let thumbImage = makeSolidImage(color: .red, size: CGSize(width: 16, height: 16))
        let fullImage = makeSolidImage(color: .blue, size: CGSize(width: 64, height: 64))

        cache.store(thumbImage, forKey: path, maxPointSize: 44)
        cache.store(fullImage, forKey: path, maxPointSize: 560)

        let loadedThumb = cache.image(forKey: path, maxPointSize: 44)
        let loadedFull = cache.image(forKey: path, maxPointSize: 560)

        XCTAssertNotNil(loadedThumb)
        XCTAssertNotNil(loadedFull)
        XCTAssertTrue(loadedThumb === thumbImage)
        XCTAssertTrue(loadedFull === fullImage)
        XCTAssertFalse(loadedThumb === loadedFull)
    }

    func testImageLookupFallsBackToUnscopedKeyAndClearRemovesEntries() {
        let path = "/uploads/stories/fallback.jpg"
        let baseImage = makeSolidImage(color: .green, size: CGSize(width: 24, height: 24))

        cache.store(baseImage, forKey: path, maxPointSize: nil)

        // Requesting with maxPointSize misses the #px=... entry and falls back to the unscoped key
        let fallbackHit = cache.image(forKey: path, maxPointSize: 560)
        XCTAssertTrue(fallbackHit === baseImage)

        cache.clear()
        XCTAssertNil(cache.image(forKey: path, maxPointSize: 560))
        XCTAssertNil(cache.image(forKey: path, maxPointSize: nil))
    }

    private func makeSolidImage(color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

/*
 GHI CHÚ VỀ PHẦN KHÔNG TEST ĐƯỢC TRONG ImageMemoryCache (Theo luật không sửa code production):
 - Dedupe in-flight (`inFlight: [String: Task<UIImage?, Never>]` trong `loadImage(path:maxPointSize:)`):
   + Biến `inFlight` có mức truy cập `private`.
   + Hàm `loadImage(path:maxPointSize:)` gọi trực tiếp `await KinnectAPIClient.shared.fetchBinaryData(path: path)` bên trong `Task.detached` mà không có cơ chế inject mock transport / closure.
   + Vì không được sửa code production để lộ `inFlight` hoặc inject mock network, phần dedupe 2 lời gọi tải song song không thể kiểm thử đơn vị độc lập với mạng; các test trên tập trung kiểm thử đầy đủ phần `cacheKey`, `pixelBucket`, và `store`/`image(forKey:maxPointSize:)`/`clear`.
*/
