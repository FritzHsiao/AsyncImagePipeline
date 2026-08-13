import CoreGraphics

#if canImport(UIKit)
import UIKit

/// The platform-native image type. `UIImage` on iOS/tvOS/watchOS, `NSImage` on macOS.
public typealias PlatformImage = UIImage

extension PlatformImage {
    /// Builds a platform image from a decoded `CGImage`, preserving scale.
    static func make(cgImage: CGImage, scale: CGFloat) -> PlatformImage {
        UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    /// The backing `CGImage`, if one is available.
    var decodedCGImage: CGImage? { cgImage }
}

#elseif canImport(AppKit)
import AppKit

/// The platform-native image type. `UIImage` on iOS/tvOS/watchOS, `NSImage` on macOS.
public typealias PlatformImage = NSImage

extension PlatformImage {
    /// Builds a platform image from a decoded `CGImage`, preserving scale.
    static func make(cgImage: CGImage, scale: CGFloat) -> PlatformImage {
        // NSImage sizes in points; divide pixel dimensions by scale.
        let size = NSSize(
            width: CGFloat(cgImage.width) / scale,
            height: CGFloat(cgImage.height) / scale
        )
        return NSImage(cgImage: cgImage, size: size)
    }

    /// The backing `CGImage`, if one is available.
    var decodedCGImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#endif
