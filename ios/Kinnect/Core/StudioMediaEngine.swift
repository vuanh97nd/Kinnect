import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import SwiftUI
import UIKit

// MARK: - Crop Aspect Ratio
enum StudioCropRatio: String, CaseIterable, Identifiable {
    case original = "Ảnh gốc"
    case square = "1:1"
    case portrait = "4:5"
    case story = "9:16"

    var id: String { rawValue }

    var ratioValue: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1.0
        case .portrait: return 0.8
        case .story: return 9.0 / 16.0
        }
    }
}

// MARK: - Studio Pro Template
enum StudioProTemplate: String, CaseIterable, Identifiable {
    case none = "Gốc"
    case aurora = "Aurora"
    case travel = "Travel"
    case cinema = "Cinema"
    case vivid = "Kinnect Vivid"
    case noir = "Noir Cổ điển"
    case sunset = "Hoàng hôn"

    var id: String { rawValue }
}

// MARK: - Studio Photo Project
// MARK: - Shared Image & Video Media Filters (Real Edge-Preserving Skin Smoothing)
enum StudioMediaFilters {
    /// Real edge-preserving skin smoothing algorithm
    /// Separates high frequency details from low-frequency color masses.
    /// Blur softens skin blemishes while keeping eyes, lips, and hair sharp.
    static func applySkinSmoothing(to input: CIImage, intensity: Double) -> CIImage {
        let radius = max(1.0, (intensity / 100.0) * 8.0) // 1.0 to 8.0 px blur
        let clamped = input.clampedToExtent()
        let blurred = clamped.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: input.extent)

        // Edge detection to protect sharp facial contours
        let monoOriginal = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        let monoBlurred = blurred.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])

        // Difference identifies edges and textures
        let diff = monoOriginal.applyingFilter("CIDifferenceBlendMode", parameters: [
            kCIInputBackgroundImageKey: monoBlurred
        ])

        // Contrast boost on edges: edges get values close to 1.0, smooth skin gets 0.0
        let edgeMask = diff.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 2.2,
            kCIInputBrightnessKey: -0.15
        ])

        // BlendWithMask: where edgeMask is bright, keep original; where edgeMask is dark (skin), use blurred
        let smoothed = input.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputImageKey: input,
            kCIInputMaskImageKey: edgeMask
        ])

        // Blend back slightly based on intensity for natural look
        let blendFactor = min(1.0, intensity / 85.0)
        let alpha = CIVector(x: 0, y: 0, z: 0, w: CGFloat(blendFactor))
        let finalOutput = smoothed.applyingFilter("CIColorMatrix", parameters: ["inputAVector": alpha])
            .applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: input
            ])

        return finalOutput.cropped(to: input.extent)
    }
}

final class StudioPhotoProject: ObservableObject {
    @Published var originalImage: UIImage
    @Published var brightness: Double = 0        // -100 ... 100
    @Published var contrast: Double = 0          // -80 ... 100
    @Published var saturation: Double = 0        // -100 ... 100
    @Published var warmth: Double = 0            // -100 ... 100
    @Published var smooth: Double = 0            // 0 ... 100 (Real beauty smoothing)
    @Published var rotation: Int = 0             // 0, 90, 180, 270
    @Published var flipHorizontal: Bool = false
    @Published var cropRatio: StudioCropRatio = .original
    @Published var proTemplate: StudioProTemplate = .none

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(originalImage: UIImage) {
        self.originalImage = originalImage
    }

    func resetColor() {
        brightness = 0
        contrast = 0
        saturation = 0
        warmth = 0
        smooth = 0
        proTemplate = .none
    }

    func resetAll() {
        resetColor()
        rotation = 0
        flipHorizontal = false
        cropRatio = .original
    }

    var hasEdits: Bool {
        brightness != 0 || contrast != 0 || saturation != 0 || warmth != 0 ||
        smooth != 0 || rotation != 0 || flipHorizontal || cropRatio != .original || proTemplate != .none
    }

    /// Renders the image with all geometric transforms and CoreImage filters applied.
    func render(maxDimension: CGFloat? = nil) -> UIImage {
        // 1. Geometric transforms: rotate and flip
        var processed = applyGeometry(to: originalImage)

        // 2. Crop ratio
        if let ratio = cropRatio.ratioValue {
            processed = cropToRatio(processed, ratio: ratio)
        }

        // 3. Downscale for preview if requested
        if let maxDim = maxDimension {
            let currentMax = max(processed.size.width, processed.size.height)
            if currentMax > maxDim {
                let scale = maxDim / currentMax
                let newSize = CGSize(width: processed.size.width * scale, height: processed.size.height * scale)
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                processed.draw(in: CGRect(origin: .zero, size: newSize))
                if let scaled = UIGraphicsGetImageFromCurrentImageContext() {
                    processed = scaled
                }
                UIGraphicsEndImageContext()
            }
        }

        // 4. CoreImage Filters (Color, Pro Template, Real Beauty Smoothing)
        guard let ciInput = CIImage(image: processed) else { return processed }
        var ciOutput = ciInput

        // A. Color Adjustments
        ciOutput = applyColorControls(to: ciOutput)

        // B. Pro Filter Preset
        ciOutput = applyProTemplate(to: ciOutput)

        // C. Real Edge-Preserving Skin Smoothing
        if smooth > 0 {
            ciOutput = applySkinSmoothing(to: ciOutput, intensity: smooth)
        }

        if let cgImg = ciContext.createCGImage(ciOutput, from: ciOutput.extent) {
            return UIImage(cgImage: cgImg, scale: processed.scale, orientation: .up)
        }
        return processed
    }

    // MARK: - CoreImage Pipelines
    private func applyColorControls(to input: CIImage) -> CIImage {
        let b = brightness / 200.0 // -0.5 ... 0.5
        let c = 1.0 + (contrast / 100.0) * 0.5 // 0.6 ... 1.5
        let s = max(0.0, 1.0 + (saturation / 100.0)) // 0 ... 2.0

        var out = input.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: b,
            kCIInputContrastKey: c,
            kCIInputSaturationKey: s
        ])

        if warmth != 0 {
            let targetTemp = 6500.0 + warmth * 15.0
            out = out.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: targetTemp, y: 0)
            ])
        }
        return out
    }

    private func applyProTemplate(to input: CIImage) -> CIImage {
        switch proTemplate {
        case .none:
            return input
        case .aurora:
            // Lavender/cool tones with gentle highlight glow
            let tinted = input.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5800, y: 15)
            ])
            return tinted.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.08,
                kCIInputSaturationKey: 1.15
            ])
        case .travel:
            // Golden warmth + saturation boost
            let warm = input.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 7400, y: 0)
            ])
            return warm.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.10,
                kCIInputSaturationKey: 1.20
            ])
        case .cinema:
            // Cinematic teal & orange curve
            let cc = input.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.18,
                kCIInputSaturationKey: 0.95
            ])
            return cc.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 5400, y: -10)
            ])
        case .vivid:
            return input.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.15,
                kCIInputSaturationKey: 1.35
            ])
        case .noir:
            return input.applyingFilter("CIPhotoEffectNoir")
        case .sunset:
            let sun = input.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 7800, y: 10)
            ])
            return sun.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.05,
                kCIInputSaturationKey: 1.25
            ])
        }
    }

    /// Real edge-preserving skin smoothing algorithm
    /// Separates high frequency details from low-frequency color masses.
    /// Blur softens skin blemishes while keeping eyes, lips, and hair sharp.
    private func applySkinSmoothing(to input: CIImage, intensity: Double) -> CIImage {
        return StudioMediaFilters.applySkinSmoothing(to: input, intensity: intensity)
    }

    // MARK: - Geometry Helpers
    private func applyGeometry(to img: UIImage) -> UIImage {
        if rotation == 0 && !flipHorizontal { return img }
        var radians: CGFloat = 0
        switch rotation % 360 {
        case 90: radians = .pi / 2
        case 180: radians = .pi
        case 270: radians = 3 * .pi / 2
        default: radians = 0
        }

        var newSize = CGRect(origin: .zero, size: img.size)
            .applying(CGAffineTransform(rotationAngle: radians)).integral.size

        UIGraphicsBeginImageContextWithOptions(newSize, false, img.scale)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return img
        }

        ctx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        ctx.rotate(by: radians)
        if flipHorizontal {
            ctx.scaleBy(x: -1.0, y: 1.0)
        }
        img.draw(in: CGRect(x: -img.size.width / 2, y: -img.size.height / 2, width: img.size.width, height: img.size.height))

        let rotated = UIGraphicsGetImageFromCurrentImageContext() ?? img
        UIGraphicsEndImageContext()
        return rotated
    }

    private func cropToRatio(_ img: UIImage, ratio: CGFloat) -> UIImage {
        let currentRatio = img.size.width / img.size.height
        var cropRect = CGRect.zero

        if currentRatio > ratio {
            // Image is wider than target ratio: crop sides
            let newWidth = img.size.height * ratio
            let xOffset = (img.size.width - newWidth) / 2.0
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: img.size.height)
        } else {
            // Image is taller than target ratio: crop top/bottom
            let newHeight = img.size.width / ratio
            let yOffset = (img.size.height - newHeight) / 2.0
            cropRect = CGRect(x: 0, y: yOffset, width: img.size.width, height: newHeight)
        }

        guard let cg = img.cgImage?.cropping(to: CGRect(
            x: cropRect.origin.x * img.scale,
            y: cropRect.origin.y * img.scale,
            width: cropRect.size.width * img.scale,
            height: cropRect.size.height * img.scale
        )) else {
            return img
        }
        return UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation)
    }
}

// MARK: - Studio Video Project
final class StudioVideoProject: ObservableObject {
    let sourceURL: URL
    @Published var duration: Double = 0
    @Published var trimIn: Double = 0
    @Published var trimOut: Double = 0
    @Published var brightness: Double = 0
    @Published var contrast: Double = 0
    @Published var saturation: Double = 0
    @Published var warmth: Double = 0
    @Published var smooth: Double = 0
    @Published var rotation: Int = 0
    @Published var proTemplate: StudioProTemplate = .none
    @Published var isExporting = false
    @Published var exportProgress: Float = 0

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        let asset = AVURLAsset(url: sourceURL)
        let dur = CMTimeGetSeconds(asset.duration)
        self.duration = dur.isFinite ? dur : 0
        self.trimOut = self.duration
    }

    var hasEdits: Bool {
        trimIn > 0.05 || (duration > 0 && trimOut < duration - 0.05) ||
        brightness != 0 || contrast != 0 || saturation != 0 || warmth != 0 ||
        smooth != 0 || rotation != 0 || proTemplate != .none
    }

    /// Builds a real AVVideoComposition that runs the CoreImage filter pipeline per frame
    func makeVideoComposition(for asset: AVAsset) -> AVVideoComposition {
        let b = brightness / 200.0
        let c = 1.0 + (contrast / 100.0) * 0.5
        let s = max(0.0, 1.0 + (saturation / 100.0))
        let w = warmth
        let sm = smooth
        let template = proTemplate
        let rot = rotation % 360

        let composition = AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let source = request.sourceImage.clampedToExtent()
            var output = source

            // 1. Color controls
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: b,
                kCIInputContrastKey: c,
                kCIInputSaturationKey: s
            ])

            // 2. Warmth
            if w != 0 {
                output = output.applyingFilter("CITemperatureAndTint", parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(x: 6500.0 + w * 15.0, y: 0)
                ])
            }

            // 3. Pro template
            switch template {
            case .none: break
            case .aurora:
                output = output.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.10, kCIInputSaturationKey: 1.15])
            case .travel:
                output = output.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 7400, y: 0)])
            case .cinema:
                output = output.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.20, kCIInputSaturationKey: 0.95])
            case .vivid:
                output = output.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.15, kCIInputSaturationKey: 1.35])
            case .noir:
                output = output.applyingFilter("CIPhotoEffectNoir")
            case .sunset:
                output = output.applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 7800, y: 10)])
            }

            // 4. Real edge-preserving skin smoothing per frame
            if sm > 0 {
                output = StudioMediaFilters.applySkinSmoothing(to: output, intensity: sm)
            } else {
                output = output.cropped(to: request.sourceImage.extent)
            }

            // 5. Video rotation geometry (90, 180, 270 degrees)
            if rot != 0 {
                let extent = request.sourceImage.extent
                var transform = CGAffineTransform.identity
                switch rot {
                case 90:
                    transform = transform.translatedBy(x: extent.height, y: 0).rotated(by: .pi / 2)
                case 180:
                    transform = transform.translatedBy(x: extent.width, y: extent.height).rotated(by: .pi)
                case 270:
                    transform = transform.translatedBy(x: 0, y: extent.width).rotated(by: 3 * .pi / 2)
                default: break
                }
                output = output.transformed(by: transform)
            }

            request.finish(with: output, context: nil)
        })

        if let track = asset.tracks(withMediaType: .video).first {
            var size = track.naturalSize
            if rot == 90 || rot == 270 {
                size = CGSize(width: size.height, height: size.width)
            }
            composition.renderSize = size
        }

        return composition
    }

    /// Real AVAssetExportSession export preserving source audio and trimmed time range
    func exportVideo() async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let composition = makeVideoComposition(for: asset)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kinnect-Video-\(UUID().uuidString).mp4")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "KinnectStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không khởi tạo được bộ xuất video."])
        }

        exportSession.videoComposition = composition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Trimming range
        let startTime = CMTime(seconds: max(0, trimIn), preferredTimescale: 600)
        let endTime = CMTime(seconds: min(duration, trimOut > trimIn ? trimOut : duration), preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)

        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        if exportSession.status == .completed {
            return outputURL
        } else {
            throw exportSession.error ?? NSError(domain: "KinnectStudio", code: -2, userInfo: [NSLocalizedDescriptionKey: "Xuất video không thành công."])
        }
    }
}
