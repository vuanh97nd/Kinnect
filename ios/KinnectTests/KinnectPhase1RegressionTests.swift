import AVFoundation
import CoreMedia
import UIKit
import WebRTC
import XCTest
@testable import Kinnect

private final class LoopbackPCDelegate: NSObject, RTCPeerConnectionDelegate {
    var onIceCandidate: ((RTCIceCandidate) -> Void)?
    var onIceStateChange: ((RTCIceConnectionState) -> Void)?
    var onDataChannel: ((RTCDataChannel) -> Void)?

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        onIceStateChange?(newState)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onIceCandidate?(candidate)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        onDataChannel?(dataChannel)
    }
}

private final class LoopbackDCDelegate: NSObject, RTCDataChannelDelegate {
    var onStateChange: ((RTCDataChannelState) -> Void)?
    var onMessage: ((String) -> Void)?

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        onStateChange?(dataChannel.readyState)
    }
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let text = String(data: buffer.data, encoding: .utf8) {
            onMessage?(text)
        }
    }
}

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

    func testProductionImageDecodeAndStudioRender() {
        // Verify real production image asset decodes to a valid CGImage
        let prodAsset = UIImage(named: "welcome-profile-1") ?? UIImage(named: "gift_rose")
        XCTAssertNotNil(prodAsset, "Production asset image must load from main bundle Assets.car")
        if let prodAsset {
            XCTAssertNotNil(prodAsset.cgImage, "Production asset must decode to valid CGImage")
            XCTAssertGreaterThan(prodAsset.size.width, 0)
            XCTAssertGreaterThan(prodAsset.size.height, 0)

            // Exercise StudioPhotoProject CoreImage pipeline on decoded production image
            let project = StudioPhotoProject(originalImage: prodAsset)
            project.brightness = 0.08
            project.contrast = 1.05
            let rendered = project.render(maxDimension: 512)
            XCTAssertGreaterThan(rendered.size.width, 0, "StudioPhotoProject.render must produce non-empty UIImage")
            XCTAssertNotNil(rendered.cgImage)
            let jpeg = rendered.jpegData(compressionQuality: 0.8)
            XCTAssertNotNil(jpeg)
            XCTAssertGreaterThan(jpeg?.count ?? 0, 1024, "Rendered JPEG payload must be non-trivial")
        }
    }

    func testAVFoundationVideoFrameDecodeAndPlayback() async throws {
        #if DEBUG
        guard let videoURL = UIReviewFixture.samplePlayableVideoURL() else {
            XCTFail("Expected playable local MP4 URL")
            return
        }
        let asset = AVURLAsset(url: videoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertGreaterThanOrEqual(videoTracks.count, 1, "MP4 must contain at least 1 decodable video track")
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(CMTimeGetSeconds(duration), 0.2, "MP4 duration must be > 0.2s")

        // Decode actual video frame via AVAssetImageGenerator
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let cgFrame = try generator.copyCGImage(at: .zero, actualTime: nil)
        XCTAssertGreaterThan(cgFrame.width, 0, "Decoded video frame width must be > 0")
        XCTAssertGreaterThan(cgFrame.height, 0, "Decoded video frame height must be > 0")

        // Exercise actual AVPlayer playback progression
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()
        defer { player.pause() }

        let deadline = Date().addingTimeInterval(6.0)
        var advanced = false
        while Date() < deadline {
            if item.status == .readyToPlay && CMTimeGetSeconds(player.currentTime()) > 0.05 {
                advanced = true
                break
            }
            if item.status == .failed {
                XCTFail("AVPlayerItem failed: \(item.error?.localizedDescription ?? "unknown")")
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(advanced, "AVPlayer must reach readyToPlay and advance playback time > 0.05s (got \(CMTimeGetSeconds(player.currentTime())))")
        #else
        XCTFail("Expected Debug build for testAVFoundationVideoFrameDecodeAndPlayback")
        #endif
    }

    func testWebRTCLocalPeerOfferAnswerIceAndDataChannelFlow() throws {
        // Real in-process WebRTC loopback signaling: SDP offer/answer + ICE exchange + RTCDataChannel delivery
        RTCInitializeSSL()
        let factory = RTCPeerConnectionFactory()
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        let delegateA = LoopbackPCDelegate()
        let delegateB = LoopbackPCDelegate()
        guard let pcA = factory.peerConnection(with: config, constraints: constraints, delegate: delegateA),
              let pcB = factory.peerConnection(with: config, constraints: constraints, delegate: delegateB) else {
            XCTFail("Failed to create loopback RTCPeerConnections")
            return
        }
        defer {
            pcA.close()
            pcB.close()
        }

        let iceConnectedExp = expectation(description: "ICE loopback connected")
        iceConnectedExp.assertForOverFulfill = false
        let messageReceivedExp = expectation(description: "RTCDataChannel loopback payload received")
        var receivedPayload: String?

        delegateA.onIceCandidate = { cand in pcB.add(cand) { _ in } }
        delegateB.onIceCandidate = { cand in pcA.add(cand) { _ in } }
        delegateA.onIceStateChange = { state in
            if state == .connected || state == .completed { iceConnectedExp.fulfill() }
        }
        delegateB.onIceStateChange = { state in
            if state == .connected || state == .completed { iceConnectedExp.fulfill() }
        }

        let dcConfig = RTCDataChannelConfiguration()
        guard let dcA = pcA.dataChannel(forLabel: "kinnect-phase1-qa", configuration: dcConfig) else {
            XCTFail("Failed to create RTCDataChannel on pcA")
            return
        }
        let dcADelegate = LoopbackDCDelegate()
        let dcBDelegate = LoopbackDCDelegate()
        var dcB: RTCDataChannel?

        dcADelegate.onStateChange = { state in
            if state == .open {
                let payload = Data("kinnect-webrtc-loopback-ok".utf8)
                _ = dcA.sendData(RTCDataBuffer(data: payload, isBinary: false))
            }
        }
        dcA.delegate = dcADelegate

        dcBDelegate.onMessage = { text in
            receivedPayload = text
            messageReceivedExp.fulfill()
        }
        delegateB.onDataChannel = { channel in
            dcB = channel
            channel.delegate = dcBDelegate
        }

        let negotiatedExp = expectation(description: "SDP offer/answer negotiated")
        pcA.offer(for: constraints) { offer, err in
            XCTAssertNil(err)
            guard let offer else { return }
            pcA.setLocalDescription(offer) { err2 in
                XCTAssertNil(err2)
                pcB.setRemoteDescription(offer) { err3 in
                    XCTAssertNil(err3)
                    pcB.answer(for: constraints) { answer, err4 in
                        XCTAssertNil(err4)
                        guard let answer else { return }
                        pcB.setLocalDescription(answer) { err5 in
                            XCTAssertNil(err5)
                            pcA.setRemoteDescription(answer) { err6 in
                                XCTAssertNil(err6)
                                negotiatedExp.fulfill()
                            }
                        }
                    }
                }
            }
        }

        wait(for: [negotiatedExp, iceConnectedExp, messageReceivedExp], timeout: 15.0)
        XCTAssertEqual(receivedPayload, "kinnect-webrtc-loopback-ok", "Loopback RTCDataChannel must deliver exact payload")
        _ = dcB // keep strong reference until test end
    }
}
