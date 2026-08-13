import Foundation

/// Validates an HTTP response before the bytes are handed to the decoder.
public struct ResponseValidator: Sendable {
    /// Acceptable status-code range (default `200..<300`).
    public let acceptableStatusCodes: Range<Int>

    public init(acceptableStatusCodes: Range<Int> = 200..<300) {
        self.acceptableStatusCodes = acceptableStatusCodes
    }

    /// Throws a `PipelineError` if the response is unusable.
    public func validate(data: Data, response: HTTPURLResponse) throws {
        guard acceptableStatusCodes.contains(response.statusCode) else {
            throw PipelineError.invalidResponse(statusCode: response.statusCode)
        }
        guard !data.isEmpty else {
            throw PipelineError.emptyData
        }
        // If the server declares a content type, require that it looks like an image. When the
        // header is absent we defer to the decoder to accept or reject the bytes.
        if let contentType = response.value(forHTTPHeaderField: "Content-Type") {
            let normalized = contentType.lowercased()
            guard normalized.hasPrefix("image/") else {
                throw PipelineError.unacceptableContentType(contentType)
            }
        }
    }
}
