import AVFoundation
import Foundation

/// Locally generated progress tones; incoming ringing belongs to CallKit.
final class CallAudioFeedback {
    static let shared = CallAudioFeedback()
    private var player: AVAudioPlayer?

    func stop() {
        player?.stop()
        player = nil
    }

    func ringback() { play(frequencies: [440, 480], on: 1, off: 2, repeats: -1) }
    func ended(busy: Bool = false) {
        play(frequencies: busy ? [480, 620] : [425], on: busy ? 0.25 : 0.18,
             off: busy ? 0.25 : 0.12, repeats: busy ? 3 : 1)
    }

    private func play(frequencies: [Double], on: Double, off: Double, repeats: Int) {
        stop()
        let rate = 22050
        let count = Int((on + off) * Double(rate))
        var pcm = Data(capacity: count * 2)
        for frame in 0..<count {
            let time = Double(frame) / Double(rate)
            let envelope = max(0, min(1, min(time / 0.008, (on - time) / 0.008)))
            let wave = time < on
                ? frequencies.reduce(0.0) { $0 + sin(2 * .pi * $1 * time) } / Double(frequencies.count)
                : 0
            var sample = Int16(wave * envelope * 6500).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
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
        guard let sound = try? AVAudioPlayer(data: wav) else { return }
        sound.numberOfLoops = repeats
        sound.volume = 0.65
        sound.prepareToPlay()
        player = sound
        sound.play()
    }
}
