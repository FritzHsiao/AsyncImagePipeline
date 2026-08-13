import CoreGraphics
import Foundation

/// Turns encoded image bytes into a decoded `ImageContainer`, optionally downsampling to a target
/// size in the same pass.
public protocol ImageDecoding: Sendable {
    /// - Parameters:
    ///   - data: Encoded image bytes (JPEG/PNG/HEIC/…).
    ///   - downsampleSize: Target size in points, or `nil` to decode at full resolution.
    ///   - scale: Display scale applied to `downsampleSize` and stored on the result.
    func decode(_ data: Data, downsampleSize: CGSize?, scale: CGFloat) throws -> ImageContainer
}
