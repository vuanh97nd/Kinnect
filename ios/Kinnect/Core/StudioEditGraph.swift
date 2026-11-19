import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

// MARK: - Pro packs (data, not UI branches)

enum StudioProPack: String, CaseIterable, Identifiable {
    case original = "Gốc"
    case vivid = "Kinnect Vivid"
    case cinema = "Cinema"
    case noir = "Noir Cổ điển"
    case sunset = "Hoàng hôn"
    case beauty = "Beauty"

    var id: String { rawValue }

    /// Offsets applied as pack nodes. They do not replace crop, rotation, or user text.
    var definition: StudioPackDefinition {
        switch self {
        case .original:
            return StudioPackDefinition()
        case .vivid:
            return StudioPackDefinition(vibrance: 18, contrast: 12, curve: 0.12)
        case .cinema:
            return StudioPackDefinition(contrast: 18, warmth: -8, shadowLift: -6, highlightWarmth: 14, curve: 0.22, grain: 0.035)
        case .noir:
            return StudioPackDefinition(contrast: 20, saturation: -100, curve: 0.35)
        case .sunset:
            return StudioPackDefinition(warmth: 36, shadowLift: 16, highlightWarmth: 8)
        case .beauty:
            return StudioPackDefinition(vibrance: 6, smooth: 32, sharpness: 18)
        }
    }
}

struct StudioPackDefinition: Equatable {
    var vibrance: Double = 0
    var contrast: Double = 0
    var warmth: Double = 0
    var shadowLift: Double = 0
    var highlightWarmth: Double = 0
    var saturation: Double = 0
    var curve: Double = 0
    var smooth: Double = 0
    var sharpness: Double = 0
    var grain: Double = 0
}

struct StudioGradeState: Equatable {
    var exposure: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var vibrance: Double = 0
    var warmth: Double = 0
    var tint: Double = 0
    var smooth: Double = 0
    var sharpness: Double = 0
    var clarity: Double = 0
    var curveAmount: Double = 0
    var grain: Double = 0
    var pack: StudioProPack = .original
    var overlayText: String = ""
    var textX: Double = 0.5
    var textY: Double = 0.82

    var isNeutral: Bool {
        let pack = pack.definition
        return exposure == 0 && highlights == 0 && shadows == 0 && contrast == 0 &&
            saturation == 0 && vibrance == 0 && warmth == 0 && tint == 0 &&
            smooth == 0 && sharpness == 0 && clarity == 0 && curveAmount == 0 &&
            grain == 0 && overlayText.isEmpty && pack == StudioPackDefinition()
    }
}

enum StudioEditKind: String, CaseIterable {
    case geometry
    case crop
    case exposure
    case color
    case lut
    case skin
    case sharpness
    case grain
    case text
}

struct StudioEditNode: Identifiable, Equatable {
    var id: StudioEditKind
    var enabled: Bool
}

struct StudioEditGraph: Equatable {
    var nodes: [StudioEditNode]
    var grade: StudioGradeState

    static func make(grade: StudioGradeState) -> StudioEditGraph {
        let order: [StudioEditKind] = [.geometry, .crop, .exposure, .color, .lut, .skin, .sharpness, .grain, .text]
        let nodes = order.map { kind in
            StudioEditNode(id: kind, enabled: true)
        }
        return StudioEditGraph(nodes: nodes, grade: grade)
    }
}

enum StudioColorCube {
    static func data(dimension: Int, transform: (Float, Float, Float) -> (Float, Float, Float)) -> Data {
        let size = dimension
        var floats = [Float](repeating: 0, count: size * size * size * 4)
        var index = 0
        let denom = Float(size - 1)
        for z in 0..<size {
            for y in 0..<size {
                for x in 0..<size {
                    let r = Float(x) / denom
                    let g = Float(y) / denom
                    let b = Float(z) / denom
                    let mapped = transform(r, g, b)
                    floats[index] = mapped.0
                    floats[index + 1] = mapped.1
                    floats[index + 2] = mapped.2
                    floats[index + 3] = 1
                    index += 4
                }
            }
        }
        return Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size)
    }

    /// Monotone cubic-ish S curve. Amount 0 is identity.
    static func sCurve(_ x: Float, amount: Float) -> Float {
        if amount == 0 { return x }
        let t = min(1, max(0, x))
        let smooth = t * t * (3 - 2 * t)
        let bent = t + (smooth - t) * amount
        return min(1, max(0, bent))
    }
}

enum StudioPipelineAudit {
    static func identityCubeIsExact() -> Bool {
        let data = StudioColorCube.data(dimension: 4) { r, g, b in (r, g, b) }
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard floats.count == 4 * 4 * 4 * 4 else { return false }
        var index = 0
        for z in 0..<4 {
            for y in 0..<4 {
                for x in 0..<4 {
                    let r = Float(x) / 3
                    let g = Float(y) / 3
                    let b = Float(z) / 3
                    if abs(floats[index] - r) > 0.0001 { return false }
                    if abs(floats[index + 1] - g) > 0.0001 { return false }
                    if abs(floats[index + 2] - b) > 0.0001 { return false }
                    index += 4
                }
            }
        }
        return true
    }

    static func sCurveIsMonotone() -> Bool {
        for amount: Float in [0, 0.2, 0.8] {
            var previous: Float = -1
            for step in 0...20 {
                let x = Float(step) / 20
                let y = StudioColorCube.sCurve(x, amount: amount)
                if y + 0.0001 < previous { return false }
                previous = y
            }
            if abs(StudioColorCube.sCurve(0, amount: amount)) > 0.0001 { return false }
            if abs(StudioColorCube.sCurve(1, amount: amount) - 1) > 0.0001 { return false }
        }
        return true
    }
}

enum StudioColorPipeline {
    static func apply(to input: CIImage, graph: StudioEditGraph, faceMask: CIImage?, compositionTime: CMTime? = nil) -> CIImage {
        let grade = graph.grade
        func on(_ kind: StudioEditKind) -> Bool {
            graph.nodes.first(where: { $0.id == kind })?.enabled ?? true
        }
        if grade.isNeutral { return input }
        let pack = grade.pack.definition
        var output = input

        let exposure = on(.exposure) ? grade.exposure : 0
        if exposure != 0 {
            output = output.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: exposure / 100.0 * 2.0
            ])
        }

        let highlight = on(.exposure) ? grade.highlights : 0
        let shadow = (on(.exposure) ? grade.shadows : 0) + pack.shadowLift
        if highlight != 0 || shadow != 0 {
            let highlightAmount = 1.0 - (highlight / 200.0)
            output = output.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": highlightAmount,
                "inputShadowAmount": max(0, shadow / 100.0)
            ])
        }

        let contrast = 1.0 + (((on(.color) ? grade.contrast : 0) + pack.contrast) / 100.0) * 0.5
        let saturation = max(0, 1.0 + (((on(.color) ? grade.saturation : 0) + pack.saturation) / 100.0))
        if abs(contrast - 1) > 0.001 || abs(saturation - 1) > 0.001 {
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0,
                kCIInputContrastKey: contrast,
                kCIInputSaturationKey: saturation
            ])
        }

        let warmth = (on(.color) ? grade.warmth : 0) + pack.warmth
        let tint = on(.color) ? grade.tint : 0
        if warmth != 0 || tint != 0 {
            output = output.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 6500 + warmth * 18, y: tint * 8)
            ])
        }

        let vibrance = ((on(.color) ? grade.vibrance : 0) + pack.vibrance) / 100.0
        if abs(vibrance) > 0.001 {
            output = output.applyingFilter("CIVibrance", parameters: [
                "inputAmount": vibrance
            ])
        }

        let curve = (on(.lut) ? grade.curveAmount / 100.0 : 0) + (on(.lut) ? pack.curve : 0)
        let split = on(.lut) ? pack.highlightWarmth / 100.0 : 0
        if abs(curve) > 0.001 || abs(split) > 0.001 {
            output = applyCube(to: output, curve: Float(curve), highlightWarmth: Float(split))
        }

        let smooth = on(.skin) ? grade.smooth + pack.smooth : 0
        if smooth > 0 {
            output = StudioSkinSmoothing.apply(to: output, intensity: smooth, faceMask: faceMask)
        }

        let sharp = on(.sharpness) ? grade.sharpness + pack.sharpness : 0
        if sharp > 0 {
            output = output.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 1.2,
                kCIInputIntensityKey: min(1.2, sharp / 100.0 * 0.8)
            ])
        }
        if on(.sharpness) && grade.clarity != 0 {
            output = output.applyingFilter("CIUnsharpMask", parameters: [
                kCIInputRadiusKey: 12,
                kCIInputIntensityKey: grade.clarity / 100.0 * 0.45
            ])
        }

        let grain = on(.grain) ? grade.grain + pack.grain : 0
        if grain > 0.001 {
            output = applyGrain(to: output, amount: grain)
        }

        if on(.text), !grade.overlayText.isEmpty, shouldDrawText(grade: grade, time: compositionTime) {
            output = drawText(grade.overlayText, on: output, x: grade.textX, y: grade.textY)
        }

        return output.cropped(to: input.extent)
    }

    private static func shouldDrawText(grade: StudioGradeState, time: CMTime?) -> Bool {
        guard let time, time.isValid else { return true }
        return true
    }

    private static func applyCube(to image: CIImage, curve: Float, highlightWarmth: Float) -> CIImage {
        let data = StudioColorCube.data(dimension: 32) { r, g, b in
            var rr = StudioColorCube.sCurve(r, amount: curve)
            var gg = StudioColorCube.sCurve(g, amount: curve)
            var bb = StudioColorCube.sCurve(b, amount: curve)
            let luma = rr * 0.2126 + gg * 0.7152 + bb * 0.0722
            if highlightWarmth != 0 {
                if luma > 0.55 {
                    rr = min(1, rr + highlightWarmth * (luma - 0.55))
                    gg = min(1, gg + highlightWarmth * 0.35 * (luma - 0.55))
                } else {
                    bb = min(1, bb + max(0, -highlightWarmth) * (0.55 - luma) * 0.2)
                    bb = min(1, max(0, bb - highlightWarmth * (0.55 - luma) * 0.15))
                }
            }
            return (rr, gg, bb)
        }
        return image.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": 32,
            "inputCubeData": data
        ])
    }

    private static func applyGrain(to image: CIImage, amount: Double) -> CIImage {
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let mono = noise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1
        ]).cropped(to: image.extent)
        let faded = mono.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
        ])
        return faded.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: image.extent)
    }

    private static func drawText(_ text: String, on image: CIImage, x: Double, y: Double) -> CIImage {
        let fontSize = max(18, image.extent.height * 0.045)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white
        ])
        guard let filter = CIFilter(name: "CIAttributedTextImageGenerator") else { return image }
        filter.setValue(attributed, forKey: "inputText")
        guard var textImage = filter.outputImage else { return image }
        let dx = image.extent.minX + CGFloat(x) * image.extent.width - textImage.extent.width / 2
        let dy = image.extent.minY + CGFloat(y) * image.extent.height
        textImage = textImage.transformed(by: CGAffineTransform(translationX: dx - textImage.extent.minX, y: dy))
        return textImage.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image
        ]).cropped(to: image.extent)
    }
}

enum StudioSkinSmoothing {
    static func apply(to input: CIImage, intensity: Double, faceMask: CIImage?) -> CIImage {
        let amount = min(1, max(0, intensity / 100.0))
        if amount <= 0 { return input }
        let radius = 2.0 + amount * 7.0
        let low = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        guard let mask = faceMask else {
            return input
        }
        let softened = low.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: input,
            kCIInputMaskImageKey: mask
        ])
        let alpha = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount))
        return softened
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": alpha])
            .applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: input
            ])
            .cropped(to: input.extent)
    }
}

enum StudioSkinMask {
    static func mask(for image: CIImage) -> CIImage? {
        let extent = image.extent.integral
        guard extent.width > 16, extent.height > 16 else { return nil }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let faces = request.results, !faces.isEmpty else { return nil }

        let scale = min(1, 480 / max(extent.width, extent.height))
        let canvas = CGSize(width: max(1, extent.width * scale), height: max(1, extent.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        let uiImage = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            let cg = ctx.cgContext
            for face in faces {
                drawSkin(face, in: cg, canvas: canvas)
            }
        }
        guard var mask = CIImage(image: uiImage) else { return nil }
        let sx = extent.width / canvas.width
        let sy = extent.height / canvas.height
        mask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        return mask.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6])
            .cropped(to: extent)
    }

    private static func drawSkin(_ face: VNFaceObservation, in cg: CGContext, canvas: CGSize) {
        let box = face.boundingBox
        func map(nx: CGFloat, ny: CGFloat) -> CGPoint {
            CGPoint(x: nx * canvas.width, y: (1 - ny) * canvas.height)
        }
        func ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat) {
            let center = map(nx: box.minX + box.width * cx, ny: box.minY + box.height * cy)
            let rw = box.width * canvas.width * rx
            let rh = box.height * canvas.height * ry
            cg.fillEllipse(in: CGRect(x: center.x - rw, y: center.y - rh, width: rw * 2, height: rh * 2))
        }
        cg.setFillColor(UIColor.white.cgColor)
        ellipse(cx: 0.50, cy: 0.78, rx: 0.26, ry: 0.12)
        ellipse(cx: 0.30, cy: 0.42, rx: 0.16, ry: 0.14)
        ellipse(cx: 0.70, cy: 0.42, rx: 0.16, ry: 0.14)
        ellipse(cx: 0.50, cy: 0.22, rx: 0.18, ry: 0.12)

        cg.setFillColor(UIColor.black.cgColor)
        let landmarks = face.landmarks
        fill(region: landmarks?.leftEye, box: box, cg: cg, canvas: canvas)
        fill(region: landmarks?.rightEye, box: box, cg: cg, canvas: canvas)
        fill(region: landmarks?.leftEyebrow, box: box, cg: cg, canvas: canvas)
        fill(region: landmarks?.rightEyebrow, box: box, cg: cg, canvas: canvas)
        fill(region: landmarks?.outerLips, box: box, cg: cg, canvas: canvas)
        fill(region: landmarks?.innerLips, box: box, cg: cg, canvas: canvas)
        if landmarks?.leftEye == nil {
            ellipse(cx: 0.35, cy: 0.62, rx: 0.08, ry: 0.05)
            ellipse(cx: 0.65, cy: 0.62, rx: 0.08, ry: 0.05)
            ellipse(cx: 0.50, cy: 0.40, rx: 0.10, ry: 0.05)
        }
    }

    private static func fill(region: VNFaceLandmarkRegion2D?, box: CGRect, cg: CGContext, canvas: CGSize) {
        guard let region, region.pointCount > 1 else { return }
        let path = CGMutablePath()
        for index in 0..<region.pointCount {
            let point = region.normalizedPoints[index]
            let nx = box.minX + point.x * box.width
            let ny = box.minY + point.y * box.height
            let view = CGPoint(x: nx * canvas.width, y: (1 - ny) * canvas.height)
            if index == 0 {
                path.move(to: view)
            } else {
                path.addLine(to: view)
            }
        }
        path.closeSubpath()
        cg.addPath(path)
        cg.fillPath()
    }
}
