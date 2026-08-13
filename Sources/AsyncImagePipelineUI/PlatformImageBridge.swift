import SwiftUI
import AsyncImagePipeline

extension Image {
    /// Builds a SwiftUI `Image` from the platform-native image type.
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}
