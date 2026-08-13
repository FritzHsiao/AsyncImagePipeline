import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import AsyncImagePipeline

/// A loader that serves fixed bytes, tracking call/cancel counts and peak concurrency so the
/// Prefetcher's bounded-concurrency behavior can be asserted.
actor CountingLoader: DataLoading {
    private(set) var callCount = 0
    private(set) var cancelledCount = 0
    private(set) var maxConcurrent = 0
    private var active = 0

    private let payload: Data
    private let response: HTTPURLResponse
    private let delay: Duration?

    init(payload: Data, response: HTTPURLResponse, delay: Duration? = nil) {
        self.payload = payload
        self.response = response
        self.delay = delay
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        active += 1
        maxConcurrent = max(maxConcurrent, active)
        defer { active -= 1 }

        if let delay {
            do {
                try await Task.sleep(for: delay)
            } catch {
                cancelledCount += 1
                throw error
            }
        }
        return (payload, response)
    }
}

enum UIFixtures {
    static func url(_ index: Int) -> URL {
        URL(string: "https://example.com/image-\(index).png")!
    }

    static func response(url: URL = URL(string: "https://example.com/image.png")!) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png"]
        )!
    }

    static func pngData(width: Int = 8, height: Int = 8) -> Data {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!

        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func pipeline(loader: any DataLoading) -> ImagePipeline {
        ImagePipeline(configuration: .init(
            dataLoader: loader,
            memoryCache: MemoryCache(),
            diskCache: NullDiskCacheUI()
        ))
    }
}

/// No-op disk cache to keep prefetch tests off the filesystem.
final class NullDiskCacheUI: DiskCaching, @unchecked Sendable {
    func data(for key: String) async -> Data? { nil }
    func store(_ data: Data, for key: String) async {}
    func removeData(for key: String) async {}
    func removeAll() async {}
}
