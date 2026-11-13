import AVFoundation
import Foundation

/// Locally generated progress tones (ringback, connect chime, ended/busy, fallback incoming ring).
final class CallAudioFeedback {
    static let shared = CallAudioFeedback()
    private var player: AVAudioPlayer?

    func stop() {
        player?.stop()
        player = nil
    }

    func ringback() {
        play(segments: [([440, 480], 1.0), ([], 2.0)], repeats: -1)
    }

    func incomingRing() {
        play(
            segments: [
                ([659.25, 783.99], 0.35),
                ([], 0.12),
                ([659.25, 783.99], 0.35),
                ([], 1.38)
            ],
            repeats: -1
        )
    }

    func connectedChime() {
        play(
            segments: [
                ([587.33], 0.09),
                ([880.0], 0.15)
            ],
            repeats: 0
        )
    }

    func ended(busy: Bool = false) {
        if busy {
            play(segments: [([480, 620], 0.24), ([], 0.22)], repeats: 2)
        } else {
            play(segments: [([425], 0.16), ([], 0.10), ([340], 0.18)], repeats: 0)
        }
    }

    private func play(segments: [(frequencies: [Double], duration: Double)], repeats: Int) {
        stop()
        let rate = 22050
        var pcm = Data()
        let totalSamplesEstimate = Int(segments.reduce(0.0) { $0 + $1.duration } * Double(rate))
        pcm.reserveCapacity(max(totalSamplesEstimate * 2, 1024))

        for seg in segments where seg.duration > 0 {
            let count = max(1, Int(seg.duration * Double(rate)))
            for frame in 0..<count {
                let time = Double(frame) / Double(rate)
                let wave: Double
                if seg.frequencies.isEmpty {
                    wave = 0
                } else {
                    let env = max(0, min(1, min(time / 0.008, (seg.duration - time) / 0.008)))
                    let sum = seg.frequencies.reduce(0.0) { $0 + sin(2 * .pi * $1 * time) }
                    wave = (sum / Double(seg.frequencies.count)) * env
                }
                var sample = Int16(max(-1.0, min(1.0, wave)) * 20000).littleEndian
                withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
            }
        }
        guard !pcm.isEmpty else { return }

        var wav = Data()
        func word(_ value: UInt16) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
        }
        func dword(_ value: UInt32) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: "RIFF".utf8); dword(UInt32(36 + pcm.count))
        wav.append(contentsOf: "WAVEfmt ".utf8); dword(16)
        word(1); word(1); dword(UInt32(rate)); dword(UInt32(rate * 2)); word(2); word(16)
        wav.append(contentsOf: "data".utf8); dword(UInt32(pcm.count)); wav.append(pcm)

        // When no CallKit/WebRTC session owns the audio session, ensure playback routing works cleanly.
        if NativeWebRTCManager.shared.activeCall == nil {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, options: [.mixWithOthers])
            try? session.setActive(true)
        }

        guard let sound = try? AVAudioPlayer(data: wav) else { return }
        sound.numberOfLoops = repeats
        sound.volume = 0.85
        sound.prepareToPlay()
        player = sound
        sound.play()
    }
}
