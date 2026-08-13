import CoreGraphics
import XCTest
@testable import AsyncImagePipeline

final class ImageIODecoderTests: XCTestCase {
    func testDecodesFullSize() throws {
        let data = TestFixtures.pngData(width: 120, height: 80)
        let container = try ImageIODecoder().decode(data, downsampleSize: nil, scale: 1)
        XCTAssertEqual(container.pixelWidth, 120)
        XCTAssertEqual(container.pixelHeight, 80)
    }

    func testDownsampleShrinksToTarget() throws {
        let data = TestFixtures.pngData(width: 2000, height: 2000)
        let container = try ImageIODecoder().decode(
            data,
            downsampleSize: CGSize(width: 100, height: 100),
            scale: 1
        )
        XCTAssertLessThanOrEqual(container.pixelWidth, 100)
        XCTAssertLessThanOrEqual(container.pixelHeight, 100)
        // And it actually did something — far smaller than the 2000px source.
        XCTAssertLessThan(container.pixelWidth, 2000)
    }

    func testDownsampleHonorsScale() throws {
        let data = TestFixtures.pngData(width: 2000, height: 2000)
        let container = try ImageIODecoder().decode(
            data,
            downsampleSize: CGSize(width: 100, height: 100),
            scale: 2
        )
        // 100 pt * 2 scale = 200 px max side.
        XCTAssertLessThanOrEqual(container.pixelWidth, 200)
        XCTAssertGreaterThan(container.pixelWidth, 100)
    }

    func testGarbageThrows() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try ImageIODecoder().decode(garbage, downsampleSize: nil, scale: 1)) {
            XCTAssertEqual($0 as? PipelineError, .decodingFailed)
        }
    }
}

final class ResponseValidatorTests: XCTestCase {
    private let validator = ResponseValidator()
    private let data = TestFixtures.pngData(width: 4, height: 4)

    func testAcceptsValidImageResponse() throws {
        try validator.validate(data: data, response: TestFixtures.response())
    }

    func testRejectsNon2xx() {
        let response = TestFixtures.response(status: 404)
        XCTAssertThrowsError(try validator.validate(data: data, response: response)) {
            XCTAssertEqual($0 as? PipelineError, .invalidResponse(statusCode: 404))
        }
    }

    func testRejectsNonImageContentType() {
        let response = TestFixtures.response(contentType: "text/html")
        XCTAssertThrowsError(try validator.validate(data: data, response: response)) {
            XCTAssertEqual($0 as? PipelineError, .unacceptableContentType("text/html"))
        }
    }

    func testRejectsEmptyData() {
        XCTAssertThrowsError(try validator.validate(data: Data(), response: TestFixtures.response())) {
            XCTAssertEqual($0 as? PipelineError, .emptyData)
        }
    }

    func testAcceptsMissingContentType() throws {
        // No Content-Type header: defer to the decoder rather than rejecting outright.
        try validator.validate(data: data, response: TestFixtures.response(contentType: nil))
    }
}
