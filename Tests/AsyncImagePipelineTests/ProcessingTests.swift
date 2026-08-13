import CoreGraphics
import XCTest
@testable import AsyncImagePipeline

final class ProcessingTests: XCTestCase {
    private func container(width: Int, height: Int) -> ImageContainer {
        try! ImageIODecoder().decode(
            TestFixtures.pngData(width: width, height: height),
            downsampleSize: nil,
            scale: 1
        )
    }

    func testResizeProducesExactPixelSize() throws {
        let processor = ResizeProcessor(targetPixelSize: CGSize(width: 64, height: 48))
        let output = try processor.process(container(width: 200, height: 200))
        XCTAssertEqual(output.pixelWidth, 64)
        XCTAssertEqual(output.pixelHeight, 48)
    }

    func testRoundCornerKeepsDimensions() throws {
        let processor = RoundCornerProcessor(radius: 10)
        let output = try processor.process(container(width: 80, height: 80))
        XCTAssertEqual(output.pixelWidth, 80)
        XCTAssertEqual(output.pixelHeight, 80)
    }

    func testProcessorsChangeCacheKey() {
        let plain = ImageRequest(url: TestFixtures.url)
        let resized = ImageRequest(
            url: TestFixtures.url,
            processors: [ResizeProcessor(targetPixelSize: CGSize(width: 10, height: 10))]
        )
        XCTAssertNotEqual(plain.cacheKey, resized.cacheKey)
    }

    func testDownsampleSizeChangesCacheKey() {
        let plain = ImageRequest(url: TestFixtures.url)
        let thumb = ImageRequest(
            url: TestFixtures.url,
            options: .init(downsampleSize: CGSize(width: 50, height: 50))
        )
        XCTAssertNotEqual(plain.cacheKey, thumb.cacheKey)
    }
}
