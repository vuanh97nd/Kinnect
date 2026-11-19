import AVFoundation
import UIKit

enum KinnectStillVideo {
    static func make(image: UIImage) async throws -> URL {
        let size = CGSize(width: 720, height: 1280)
        let rendered = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        guard let cgImage = rendered.cgImage else { throw KinnectAPIError.serverMessage("Không đọc được ảnh.") }
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
            for frame in 0..<180 {
                let deadline = Date().addingTimeInterval(10)
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else {
                        writer.cancelWriting()
                        throw KinnectAPIError.serverMessage("Xuất video ảnh quá thời gian.")
                    }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
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
}
