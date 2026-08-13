import CoreGraphics
import Foundation

/// Redraws the image at an exact target pixel size.
///
/// Prefer `ImageRequest.Options.downsampleSize` for the common "shrink a large download" case —
/// that avoids allocating the full bitmap. Use this processor when you need a precise output size
/// regardless of the source, or in combination with other processors.
public struct ResizeProcessor: ImageProcessing {
    /// Target size in pixels.
    public let targetPixelSize: CGSize

    public init(targetPixelSize: CGSize) {
        self.targetPixelSize = targetPixelSize
    }

    public var identifier: String {
        "resize(\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height)))"
    }

    public func process(_ container: ImageContainer) throws -> ImageContainer {
        let width = Int(targetPixelSize.width.rounded())
        let height = Int(targetPixelSize.height.rounded())
        guard width > 0, height > 0, let context = makeContext(width: width, height: height) else {
            throw PipelineError.processingFailed(identifier: identifier)
        }
        context.interpolationQuality = .high
        context.draw(container.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else {
            throw PipelineError.processingFailed(identifier: identifier)
        }
        return ImageContainer(cgImage: output, scale: container.scale)
    }
}

/// Clips the image to a rounded rectangle. Radius is expressed in pixels.
public struct RoundCornerProcessor: ImageProcessing {
    public let radius: CGFloat

    public init(radius: CGFloat) {
        self.radius = radius
    }

    public var identifier: String { "roundCorner(\(Int(radius)))" }

    public func process(_ container: ImageContainer) throws -> ImageContainer {
        let width = container.pixelWidth
        let height = container.pixelHeight
        guard width > 0, height > 0, let context = makeContext(width: width, height: height) else {
            throw PipelineError.processingFailed(identifier: identifier)
        }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        context.addPath(path)
        context.clip()
        context.draw(container.cgImage, in: rect)
        guard let output = context.makeImage() else {
            throw PipelineError.processingFailed(identifier: identifier)
        }
        return ImageContainer(cgImage: output, scale: container.scale)
    }
}

/// Builds a premultiplied-RGBA bitmap context in the device RGB color space.
private func makeContext(width: Int, height: Int) -> CGContext? {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}
