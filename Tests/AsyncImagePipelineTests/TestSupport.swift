import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import AsyncImagePipeline

// MARK: - Spy data loader

/// A deterministic `DataLoading` used in place of the network.
///
/// Tracks how many loads started (`callCount`) and how many were cancelled mid-flight
/// (`cancelledCount`), and can inject an artificial delay so cancellation can be exercised.
actor MockDataLoader: DataLoading {
    private(set) var callCount = 0
    private(set) var cancelledCount = 0

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

/// A `DiskCaching` that does nothing — isolates memory/dedup/cancellation tests from the filesystem.
final class NullDiskCache: DiskCaching, @unchecked Sendable {
    func data(for key: String) async -> Data? { nil }
    func store(_ data: Data, for key: String) async {}
    func removeData(for key: String) async {}
    func removeAll() async {}
}

/// A `DiskCaching` spy that counts writes — used by the cache-policy tests.
actor SpyDiskCache: DiskCaching {
    private(set) var storeCount = 0
    private(set) var readCount = 0

    func data(for key: String) async -> Data? { readCount += 1; return nil }
    func store(_ data: Data, for key: String) async { storeCount += 1 }
    func removeData(for key: String) async {}
    func removeAll() async {}
}

// MARK: - Fixtures

enum TestFixtures {
    static let url = URL(string: "https://example.com/image.png")!

    static func response(
        url: URL = url,
        status: Int = 200,
        contentType: String? = "image/png"
    ) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let contentType { headers["Content-Type"] = contentType }
        return HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    /// Encodes a solid-color PNG of the requested pixel size.
    static func pngData(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
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

    /// A pipeline wired to a mock loader and, by default, no disk.
    static func pipeline(
        loader: any DataLoading,
        memoryCache: any MemoryCaching = MemoryCache(),
        diskCache: any DiskCaching = NullDiskCache(),
        decoder: any ImageDecoding = ImageIODecoder()
    ) -> ImagePipeline {
        ImagePipeline(configuration: .init(
            dataLoader: loader,
            memoryCache: memoryCache,
            diskCache: diskCache,
            decoder: decoder
        ))
    }

    /// A unique scratch directory for disk-cache tests.
    static func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIPTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
