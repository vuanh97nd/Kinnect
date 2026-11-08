import AVFoundation
import ImageIO
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
    @Published var brightness: Double = 0
    @Published var exposure: Double = 0
    @Published var highlights: Double = 0
    @Published var shadows: Double = 0
    @Published var contrast: Double = 0
    @Published var saturation: Double = 0
    @Published var vibrance: Double = 0
    @Published var warmth: Double = 0
    @Published var tint: Double = 0
    @Published var smooth: Double = 0
    @Published var sharpness: Double = 0
    @Published var clarity: Double = 0
    @Published var curveAmount: Double = 0
    @Published var grain: Double = 0
    @Published var rotation: Int = 0
    @Published var flipHorizontal: Bool = false
    @Published var cropRatio: StudioCropRatio = .original
    @Published var proTemplate: StudioProTemplate = .none
    @Published var proPack: StudioProPack = .original
    @Published var overlayText: String = ""

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(originalImage: UIImage) {
        self.originalImage = originalImage
    }

    func resetColor() {
        brightness = 0
        exposure = 0
        highlights = 0
        shadows = 0
        contrast = 0
        saturation = 0
        vibrance = 0
        warmth = 0
        tint = 0
        smooth = 0
        sharpness = 0
        clarity = 0
        curveAmount = 0
        grain = 0
        overlayText = ""
        proTemplate = .none
        proPack = .original
    }

    func resetAll() {
        resetColor()
        rotation = 0
        flipHorizontal = false
        cropRatio = .original
    }

    var hasEdits: Bool {
        !makeGrade().isNeutral || rotation != 0 || flipHorizontal || cropRatio != .original
    }

    func makeGrade() -> StudioGradeState {
        StudioGradeState(
            exposure: exposure + brightness,
            highlights: highlights,
            shadows: shadows,
            contrast: contrast,
            saturation: saturation,
            vibrance: vibrance,
            warmth: warmth,
            tint: tint,
            smooth: smooth,
            sharpness: sharpness,
            clarity: clarity,
            curveAmount: curveAmount,
            grain: grain,
            pack: proPack,
            overlayText: overlayText
        )
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

        guard let ciInput = CIImage(image: processed) else { return processed }
        let graph = StudioEditGraph.make(grade: makeGrade())
        let needsSkin = graph.grade.smooth + graph.grade.pack.definition.smooth > 0
        let mask = needsSkin ? StudioSkinMask.mask(for: ciInput) : nil
        let ciOutput = StudioColorPipeline.apply(to: ciInput, graph: graph, faceMask: mask)

        if let cgImg = ciContext.createCGImage(ciOutput, from: ciOutput.extent) {
            return UIImage(cgImage: cgImg, scale: processed.scale, orientation: .up)
        }
        return processed
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
    @Published var exposure: Double = 0
    @Published var highlights: Double = 0
    @Published var shadows: Double = 0
    @Published var contrast: Double = 0
    @Published var saturation: Double = 0
    @Published var vibrance: Double = 0
    @Published var warmth: Double = 0
    @Published var tint: Double = 0
    @Published var smooth: Double = 0
    @Published var sharpness: Double = 0
    @Published var clarity: Double = 0
    @Published var curveAmount: Double = 0
    @Published var grain: Double = 0
    @Published var rotation: Int = 0
    @Published var proTemplate: StudioProTemplate = .none
    @Published var proPack: StudioProPack = .original
    @Published var playbackRate: Double = 1
    @Published var overlayText: String = ""
    @Published var isExporting = false
    @Published var exportProgress: Float = 0
    private var activeExport: AVAssetExportSession?

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        let asset = AVURLAsset(url: sourceURL)
        let dur = CMTimeGetSeconds(asset.duration)
        self.duration = dur.isFinite ? dur : 0
        self.trimOut = self.duration
    }

    var hasEdits: Bool {
        trimIn > 0.05 || (duration > 0 && trimOut < duration - 0.05) ||
        abs(playbackRate - 1) > 0.01 || rotation != 0 || !makeGrade().isNeutral
    }

    func makeGrade() -> StudioGradeState {
        StudioGradeState(
            exposure: exposure + brightness,
            highlights: highlights,
            shadows: shadows,
            contrast: contrast,
            saturation: saturation,
            vibrance: vibrance,
            warmth: warmth,
            tint: tint,
            smooth: smooth,
            sharpness: sharpness,
            clarity: clarity,
            curveAmount: curveAmount,
            grain: grain,
            pack: proPack,
            overlayText: overlayText
        )
    }

    func cancelExport() {
        activeExport?.cancelExport()
    }

    /// Builds a real AVVideoComposition that runs the shared edit graph per frame.
    func makeVideoComposition(for asset: AVAsset) -> AVVideoComposition {
        let graph = StudioEditGraph.make(grade: makeGrade())
        let grade = graph.grade
        let rot = rotation % 360
        let sampleMask: CIImage? = {
            guard grade.smooth + grade.pack.definition.smooth > 0 else { return nil }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: min(max(trimIn, 0), max(duration - 0.05, 0)), preferredTimescale: 600)
            guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
            return StudioSkinMask.mask(for: CIImage(cgImage: cg))
        }()

        let baseComposition = AVVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            let fittedMask = sampleMask.map { mask -> CIImage in
                let extent = request.sourceImage.extent
                let sx = extent.width / max(mask.extent.width, 1)
                let sy = extent.height / max(mask.extent.height, 1)
                return mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                    .transformed(by: CGAffineTransform(translationX: extent.minX - mask.extent.minX * sx, y: extent.minY - mask.extent.minY * sy))
                    .cropped(to: extent)
            }
            var output = StudioColorPipeline.apply(
                to: request.sourceImage,
                graph: graph,
                faceMask: fittedMask,
                compositionTime: request.compositionTime
            )
            if rot != 0 {
                switch rot {
                case 90:
                    output = output.oriented(.right)
                case 180:
                    output = output.oriented(.down)
                case 270:
                    output = output.oriented(.left)
                default:
                    break
                }
            }
            request.finish(with: output.cropped(to: output.extent), context: nil)
        })

        guard let mutableComposition = baseComposition.mutableCopy() as? AVMutableVideoComposition else {
            return baseComposition
        }

        if rot == 90 || rot == 270 {
            let baseSize = baseComposition.renderSize
            mutableComposition.renderSize = CGSize(width: baseSize.height, height: baseSize.width)
        }

        return mutableComposition
    }

    /// Exports one clip. Speed other than 1x changes pitch. HEVC is used when the preset exists.
    func exportVideo() async throws -> URL {
        let source = AVURLAsset(url: sourceURL)
        let exportAsset = try await assetForExport(from: source)
        let composition = makeVideoComposition(for: exportAsset)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kinnect-Video-\(UUID().uuidString).mp4")
        let preset = AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
            ? AVAssetExportPresetHEVCHighestQuality
            : AVAssetExportPresetHighestQuality
        guard let exportSession = AVAssetExportSession(asset: exportAsset, presetName: preset) else {
            throw NSError(domain: "KinnectStudio", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không khởi tạo được bộ xuất video."])
        }

        exportSession.videoComposition = composition
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        if abs(playbackRate - 1) < 0.05 {
            let startTime = CMTime(seconds: max(0, trimIn), preferredTimescale: 600)
            let endTime = CMTime(seconds: min(duration, trimOut > trimIn ? trimOut : duration), preferredTimescale: 600)
            exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)
        }
        activeExport = exportSession
        isExporting = true
        exportProgress = 0
        let progressTask = Task { @MainActor in
            while !Task.isCancelled {
                self.exportProgress = exportSession.progress
                let status = exportSession.status
                if status == .completed || status == .failed || status == .cancelled { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }
        progressTask.cancel()
        isExporting = false
        exportProgress = exportSession.status == .completed ? 1 : exportSession.progress
        activeExport = nil

        if exportSession.status == .completed {
            return outputURL
        }
        throw exportSession.error ?? NSError(domain: "KinnectStudio", code: -2, userInfo: [NSLocalizedDescriptionKey: "Xuất video không thành công."])
    }

    private func assetForExport(from source: AVURLAsset) async throws -> AVAsset {
        guard abs(playbackRate - 1) >= 0.05 else { return source }
        let composition = AVMutableComposition()
        let start = CMTime(seconds: max(0, trimIn), preferredTimescale: 600)
        let length = CMTime(seconds: max(0.1, (trimOut > trimIn ? trimOut : duration) - trimIn), preferredTimescale: 600)
        let range = CMTimeRange(start: start, duration: length)
        let scaled = CMTimeMultiplyByFloat64(length, multiplier: 1.0 / playbackRate)
        if let video = try await source.loadTracks(withMediaType: .video).first,
           let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(range, of: video, at: .zero)
            track.scaleTimeRange(CMTimeRange(start: .zero, duration: length), toDuration: scaled)
            track.preferredTransform = try await video.load(.preferredTransform)
        }
        if let audio = try await source.loadTracks(withMediaType: .audio).first,
           let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(range, of: audio, at: .zero)
            track.scaleTimeRange(CMTimeRange(start: .zero, duration: length), toDuration: scaled)
        }
        return composition
    }
}
