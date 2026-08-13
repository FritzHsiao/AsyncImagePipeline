import CoreGraphics
import Foundation
import ImageIO

/// Default decoder built on ImageIO.
///
/// When a `downsampleSize` is supplied it uses `CGImageSourceCreateThumbnailAtIndex`, which decodes
/// directly to the requested pixel dimensions — the full-size bitmap is never allocated. This is
/// the memory win over `UIImage(data:)` when displaying large remote images in small views.
public struct ImageIODecoder: ImageDecoding {
    public init() {}

    public func decode(_ data: Data, downsampleSize: CGSize?, scale: CGFloat) throws -> ImageContainer {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PipelineError.decodingFailed
        }

        if let size = downsampleSize {
            return try downsample(source: source, size: size, scale: scale)
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PipelineError.decodingFailed
        }
        return ImageContainer(cgImage: cgImage, scale: scale)
    }

    private func downsample(source: CGImageSource, size: CGSize, scale: CGFloat) throws -> ImageContainer {
        // Largest edge, in pixels.
        let maxPixelDimension = max(size.width, size.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension.rounded()),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PipelineError.decodingFailed
        }
        return ImageContainer(cgImage: cgImage, scale: scale)
    }
}
