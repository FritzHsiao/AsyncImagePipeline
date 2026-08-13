import CoreGraphics
import Foundation
import AsyncImagePipeline

/// Sample data for the demo. Uses picsum.photos, which serves a stable image per `seed`.
enum DemoData {
    /// The photo "rows" shown in the grid.
    static let ids: [Int] = Array(0..<60)

    /// A downsampled thumbnail request. The grid and the prefetcher both use this exact request so
    /// their cache keys match — meaning a prefetch actually warms the entry the grid displays.
    static func thumbRequest(_ id: Int) -> ImageRequest {
        ImageRequest(
            url: url(seed: "aip-\(id)", size: 400),
            options: .init(
                priority: .low,
                downsampleSize: CGSize(width: 130, height: 130),
                scale: 3
            )
        )
    }

    /// Full-resolution URL for the detail screen.
    static func fullURL(_ id: Int) -> URL {
        url(seed: "aip-\(id)", size: 1200)
    }

    /// A deliberately huge image used to show the downsampling memory win.
    static let largeURL = url(seed: "aip-large", size: 3000)

    private static func url(seed: String, size: Int) -> URL {
        URL(string: "https://picsum.photos/seed/\(seed)/\(size)/\(size)")!
    }
}
