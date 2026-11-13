import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct KinnectMovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("Kinnect-Picked-\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return KinnectMovieTransferable(url: dest)
        }
    }
}

enum KinnectStillVideo {
    static func make(image: UIImage, durationSeconds: Double = 7.0) async throws -> URL {
        try await makeCardVideo(image: image, text: "", backgroundColorHex: "#0F101A", durationSeconds: durationSeconds)
    }

    static func makeCardVideo(
        image: UIImage?,
        text: String,
        backgroundColorHex: String,
        durationSeconds: Double = 7.0
    ) async throws -> URL {
        let size = CGSize(width: 720, height: 1280)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseColor = uiColorFromHex(backgroundColorHex) ?? UIColor(red: 0.49, green: 0.23, blue: 0.93, alpha: 1.0)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            if image != nil {
                UIColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1.0).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            } else {
                var r: CGFloat = 0.4, g: CGFloat = 0.2, b: CGFloat = 0.9, a: CGFloat = 1
                baseColor.getRed(&r, green: &g, blue: &b, alpha: &a)
                let deeper = UIColor(red: max(0, r * 0.55), green: max(0, g * 0.55), blue: max(0, b * 0.72), alpha: 1.0)
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [baseColor.cgColor, deeper.cgColor] as CFArray,
                    locations: [0.0, 1.0]
                ) {
                    context.cgContext.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: 0),
                        end: CGPoint(x: size.width, y: size.height),
                        options: []
                    )
                } else {
                    baseColor.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                }
            }

            if let image, image.size.width > 0, image.size.height > 0 {
                let scale = min(size.width / image.size.width, size.height / image.size.height)
                let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(
                    x: (size.width - drawn.width) / 2,
                    y: (size.height - drawn.height) / 2,
                    width: drawn.width,
                    height: drawn.height
                ))
            }

            if !cleanText.isEmpty {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byWordWrapping
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
                let maxRect = CGRect(x: 64, y: 0, width: size.width - 128, height: size.height - 240)
                let measured = (cleanText as NSString).boundingRect(
                    with: maxRect.size,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                let boxHeight = min(measured.height + 48, size.height - 200)
                let drawY = (size.height - boxHeight) / 2
                let textRect = CGRect(x: 64, y: drawY + 24, width: size.width - 128, height: boxHeight - 48)
                if image != nil {
                    UIColor.black.withAlphaComponent(0.52).setFill()
                    UIBezierPath(roundedRect: CGRect(x: 40, y: drawY, width: size.width - 80, height: boxHeight), cornerRadius: 28).fill()
                }
                (cleanText as NSString).draw(in: textRect, withAttributes: attrs)
            }
        }
        guard let cgImage = rendered.cgImage else { throw KinnectAPIError.serverMessage("Không tạo được khung hình video.") }
        let frameCount = max(60, Int((durationSeconds * 24.0).rounded()))
        return try await Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Kinnect-PhotoMusic-\(UUID().uuidString).mp4")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 720,
                AVVideoHeightKey: 1280
            ])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 720,
                kCVPixelBufferHeightKey as String: 1280,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
            guard writer.canAdd(input) else { throw KinnectAPIError.serverMessage("Không tạo được video ảnh.") }
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? KinnectAPIError.serverMessage("Không xuất được video ảnh.") }
            writer.startSession(atSourceTime: .zero)
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 720, 1280, kCVPixelFormatType_32ARGB, nil, &buffer)
            guard let buffer else { throw KinnectAPIError.serverMessage("Không đủ bộ nhớ tạo video.") }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 720, height: 1280, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                CVPixelBufferUnlockBaseAddress(buffer, [])
                throw KinnectAPIError.serverMessage("Không tạo được khung hình.")
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 720, height: 1280))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            for frame in 0..<frameCount {
                let deadline = Date().addingTimeInterval(15)
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else {
                        writer.cancelWriting()
                        throw KinnectAPIError.serverMessage("Xuất video ảnh quá thời gian.")
                    }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)) else {
                    writer.cancelWriting()
                    throw writer.error ?? KinnectAPIError.serverMessage("Không ghi được video ảnh.")
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? KinnectAPIError.serverMessage("Xuất video ảnh thất bại.") }
            return url
        }.value
    }

    private static func uiColorFromHex(_ hex: String) -> UIColor? {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let val = UInt64(clean, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >> 8) & 0xFF) / 255.0,
            blue: CGFloat(val & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
