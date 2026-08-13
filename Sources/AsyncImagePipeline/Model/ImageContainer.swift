import CoreGraphics

/// The immutable, `Sendable` value that flows through the pipeline and lives in the caches.
///
/// It wraps a `CGImage` (rather than a `PlatformImage`) so it stays cross-platform and safe to
/// pass across concurrency domains: `CGImage` is an immutable, thread-safe Core Graphics type.
public struct ImageContainer: @unchecked Sendable {
    /// The decoded bitmap. `CGImage` is immutable and thread-safe, which is why the whole
    /// container can be treated as `Sendable`.
    public let cgImage: CGImage

    /// The display scale associated with the image (e.g. 2.0 for @2x).
    public let scale: CGFloat

    public init(cgImage: CGImage, scale: CGFloat = 1.0) {
        self.cgImage = cgImage
        self.scale = scale
    }

    /// Pixel width of the decoded bitmap.
    public var pixelWidth: Int { cgImage.width }

    /// Pixel height of the decoded bitmap.
    public var pixelHeight: Int { cgImage.height }

    /// Approximate in-memory cost in bytes, used to size the memory cache.
    public var estimatedCostInBytes: Int {
        // 4 bytes per pixel (RGBA) is a safe upper bound for the cache accounting.
        max(1, pixelWidth * pixelHeight * 4)
    }

    /// Bridges to the platform-native image type at the edge of the API.
    public var platformImage: PlatformImage {
        PlatformImage.make(cgImage: cgImage, scale: scale)
    }
}
