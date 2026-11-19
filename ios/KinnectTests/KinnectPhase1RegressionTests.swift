import XCTest
@testable import Kinnect

final class KinnectPhase1RegressionTests: XCTestCase {
    func testDebugFixturesAndSampleMediaRemainOperationalInDebugBuild() {
        #if DEBUG
        let posts = UIReviewFixture.mockPosts()
        XCTAssertFalse(posts.isEmpty, "Debug UIReviewFixture.mockPosts() must remain operational")
        let img = UIReviewFixture.samplePreviewImage()
        XCTAssertGreaterThan(img.size.width, 0, "Debug samplePreviewImage must produce non-empty UIImage")
        let videoURL = UIReviewFixture.samplePlayableVideoURL()
        XCTAssertNotNil(videoURL, "Debug samplePlayableVideoURL must produce playable local MP4 URL")
        if let videoURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path), "Sample fixture MP4 must exist on disk")
        }
        let audioURL = UIReviewFixture.sampleAudioURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path), "Sample fixture WAV must exist on disk")
        #else
        XCTFail("KinnectPhase1RegressionTests runs under Debug test configuration")
        #endif
    }

    @MainActor
    func testWebRTCManagerInitializesWithoutCrash() {
        let manager = NativeWebRTCManager.shared
        XCTAssertNil(manager.activeCall, "No call should be active on clean initialization")
        XCTAssertFalse(manager.isMicMuted, "Default mic mute state should be false")
        XCTAssertFalse(manager.isCameraOff, "Default camera off state should be false")
    }
}
