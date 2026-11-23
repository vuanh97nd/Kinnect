import AVFoundation
import CoreImage
import ImageIO
import UIKit
import WebRTC

struct LiveVideoSettings: Equatable {
    var filter = "none"
    var sticker = "none"
    var beauty = false
    var smooth = 0.0
    var whiten = 0.0
    var slim = 0.0
    var eyes = 0.0
    var lips = 0.0
    var blemish = 0.0
    var blush = 0.0
}

// The processed buffer feeds RTCVideoSource, so the host preview and remote stream share pixels.
final class LiveVideoProcessor: NSObject, RTCVideoCapturerDelegate {
    private let source: RTCVideoSource
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let detector = CIDetector(ofType: CIDetectorTypeFace, context: nil,
                                      options: [CIDetectorAccuracy: CIDetectorAccuracyHigh,
                                                CIDetectorTracking: true])
    private let lock = NSLock()
    private var settings = LiveVideoSettings()
    private var stickerImage: CIImage?
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    private var face: CIFaceFeature?
    private var frameCount = 0

    init(source: RTCVideoSource) { self.source = source; super.init() }

    func update(_ value: LiveVideoSettings) {
        let symbols = ["glasses":"🕶", "bunny":"🐰", "cat":"🐱", "dog":"🐶", "crown":"👑",
                       "flowers":"🌸", "bow":"🎀", "freckles":"🤎", "hearts":"💕", "sparkle":"✨",
                       "stars":"⭐", "round_glasses":"👓", "heart_glasses":"💗", "neon_glasses":"⚡",
                       "butterfly":"🦋", "halo":"😇", "devil":"😈", "rainbow":"🌈",
                       "bubbles":"🫧", "snow":"❄️", "confetti":"🎉", "mask":"🎭", "party":"🥳",
                       "blush":"🌸", "fire":"🔥", "music":"🎵"]
        let assetMap = [
            "bunny": "bunny_ears", "cat": "cat_whiskers", "dog": "dog_ears",
            "glasses": "neon_glasses", "crown": "golden_tiara", "flowers": "flower_crown",
            "hearts": "cheek_hearts", "sparkle": "sparkle_eyes", "halo": "angel_halo",
            "rainbow": "rainbow_paint", "stars": "star_confetti", "confetti": "star_confetti",
            "butterfly": "butterfly_clip", "devil": "cute_devil", "mask": "cyber_mask",
            "fire": "fire_aura", "music": "music_notes", "party": "party_hat", "blush": "blush_cheeks"
        ]
        lock.lock()
        let oldSticker = settings.sticker
        lock.unlock()
        var rendered: CIImage?
        if oldSticker != value.sticker && value.sticker != "none" {
            let key = assetMap[value.sticker] ?? value.sticker
            if let assetImg = UIImage(named: "kg20261109_sticker_\(key)")
                ?? UIImage(named: "kg20261109_sticker_\(value.sticker)")
                ?? UIImage(named: "sticker_\(key)")
                ?? UIImage(named: "sticker_\(value.sticker)") {
                rendered = CIImage(image: assetImg)
            } else if let symbol = symbols[value.sticker] {
                let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { _ in
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 120)]
                    let str = NSAttributedString(string: symbol, attributes: attrs)
                    let sz = str.size()
                    str.draw(at: CGPoint(x: (160 - sz.width) / 2, y: (160 - sz.height) / 2))
                }
                rendered = CIImage(image: image)
            }
        }
        lock.lock()
        settings = value
        if oldSticker != value.sticker { stickerImage = rendered }
        lock.unlock()
    }

    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        guard let buffer = frame.buffer as? RTCCVPixelBuffer else {
            source.capturer(capturer, didCapture: frame)
            return
        }
        lock.lock()
        let config = settings
        let sticker = stickerImage
        lock.unlock()
        var image = CIImage(cvPixelBuffer: buffer.pixelBuffer)
        // Bake device orientation once before face coordinates and preserve it as an upright RTC frame.
        switch frame.rotation.rawValue {
        case 90: image = image.oriented(.right)
        case 180: image = image.oriented(.down)
        case 270: image = image.oriented(.left)
        default: break
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let extent = image.extent
        if config.beauty || sticker != nil {
            if frameCount % 2 == 0 {
                face = detector?.features(in: image, options: [CIDetectorImageOrientation: 1]).first as? CIFaceFeature
            }
            frameCount += 1
        }
        if config.beauty {
            let smoothing = max(config.smooth, config.blemish * 0.8)
            if smoothing > 0 { image = StudioMediaFilters.applySkinSmoothing(to: image, intensity: smoothing * 100) }
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: config.whiten * 0.10])
            if let face {
                let center = CGPoint(x: face.bounds.midX, y: face.bounds.midY)
                if config.slim > 0 {
                    image = image.applyingFilter("CIPinchDistortion", parameters: [
                        kCIInputCenterKey: CIVector(cgPoint: center),
                        kCIInputRadiusKey: face.bounds.width * 0.65, kCIInputScaleKey: config.slim * 0.15])
                }
                for eye in [face.hasLeftEyePosition ? face.leftEyePosition : nil,
                            face.hasRightEyePosition ? face.rightEyePosition : nil].compactMap({ $0 }) {
                    if config.eyes > 0 {
                        image = image.applyingFilter("CIBumpDistortion", parameters: [
                            kCIInputCenterKey: CIVector(cgPoint: eye), kCIInputRadiusKey: face.bounds.width * 0.18,
                            kCIInputScaleKey: config.eyes * 0.2])
                    }
                }
                if face.hasMouthPosition && config.lips > 0 {
                    image = image.applyingFilter("CIBumpDistortion", parameters: [
                        kCIInputCenterKey: CIVector(cgPoint: face.mouthPosition),
                        kCIInputRadiusKey: face.bounds.width * 0.16, kCIInputScaleKey: config.lips * 0.12])
                }
                if config.blush > 0 {
                    for x in [face.bounds.minX + face.bounds.width * 0.23, face.bounds.maxX - face.bounds.width * 0.23] {
                        let blush = CIFilter(name: "CIRadialGradient", parameters: [
                            "inputCenter": CIVector(x: x, y: face.bounds.minY + face.bounds.height * 0.40),
                            "inputRadius0": 0, "inputRadius1": face.bounds.width * 0.17,
                            "inputColor0": CIColor(red: 1, green: 0.25, blue: 0.4, alpha: CGFloat(config.blush * 0.18)),
                            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)])?.outputImage
                        if let blush { image = blush.composited(over: image).cropped(to: extent) }
                    }
                }
            }
        }
        switch config.filter {
        case "mono": image = image.applyingFilter("CIPhotoEffectMono")
        case "noir": image = image.applyingFilter("CIPhotoEffectNoir")
        case "film", "retro", "polaroid": image = image.applyingFilter("CIPhotoEffectInstant")
        case "cinema", "city": image = image.applyingFilter("CIPhotoEffectProcess")
        case "warm", "sunset", "golden", "choco":
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5200, y: 0)])
        case "cool", "ice", "mint", "teal":
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 7800, y: 0)])
        case "peach", "rose", "candy", "lavender", "dream":
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6000, y: 12)])
        case "vivid": image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3, kCIInputContrastKey: 1.08])
        case "clear", "milk": image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: 0.04, kCIInputContrastKey: 0.96])
        default: break
        }
        if let sticker, let face {
            // CoreImage Y=0 ở đáy: minY là cằm, maxY là trán
            let (yRatio, widthScale): (CGFloat, CGFloat) = {
                switch config.sticker {
                case "crown", "bunny", "cat", "dog", "flowers", "halo", "devil", "butterfly", "party":
                    return (1.12, 1.15)
                case "glasses", "round_glasses", "heart_glasses", "neon_glasses", "mask":
                    return (0.62, 1.05)
                case "hearts", "freckles", "blush", "sparkle", "rainbow":
                    return (0.46, 0.95)
                case "bow", "lips":
                    return (0.22, 0.65)
                default:
                    return (0.85, 1.15)
                }
            }()
            let width = face.bounds.width * widthScale
            let height = width * (sticker.extent.height / max(1, sticker.extent.width))
            let sx = width / max(1, sticker.extent.width)
            let sy = height / max(1, sticker.extent.height)
            let cx = face.bounds.midX
            let cy = face.bounds.minY + face.bounds.height * yRatio
            let angle = face.hasFaceAngle ? CGFloat(-face.faceAngle) * .pi / 180.0 : 0
            let centered = sticker.transformed(by: CGAffineTransform(
                translationX: -sticker.extent.midX, y: -sticker.extent.midY
            ))
            let placed = centered
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                .transformed(by: CGAffineTransform(rotationAngle: angle))
                .transformed(by: CGAffineTransform(translationX: cx, y: cy))
            image = placed.composited(over: image).cropped(to: extent)
        }
        if pool == nil || poolSize != extent.size {
            poolSize = extent.size
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(extent.width),
                kCVPixelBufferHeightKey as String: Int(extent.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        var output: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let output else {
            source.capturer(capturer, didCapture: frame)
            return
        }
        context.render(image.cropped(to: extent), to: output)
        source.capturer(capturer, didCapture: RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: output), rotation: ._0, timeStampNs: frame.timeStampNs))
    }
}
