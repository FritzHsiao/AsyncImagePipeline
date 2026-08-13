import Foundation

/// Errors surfaced by the image pipeline.
public enum PipelineError: Error, Sendable, Equatable {
    /// The HTTP response carried a status code outside the acceptable range.
    case invalidResponse(statusCode: Int)

    /// The response was not an `HTTPURLResponse`.
    case notAnHTTPResponse

    /// The `Content-Type` header did not describe an image.
    case unacceptableContentType(String?)

    /// The response body was empty.
    case emptyData

    /// The bytes could not be decoded into an image.
    case decodingFailed

    /// An image processor failed.
    case processingFailed(identifier: String)

    /// The request was cancelled before it could complete.
    case cancelled

    /// The underlying data loader failed.
    case dataLoading(message: String)

    public static func == (lhs: PipelineError, rhs: PipelineError) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidResponse(l), .invalidResponse(r)): return l == r
        case (.notAnHTTPResponse, .notAnHTTPResponse): return true
        case let (.unacceptableContentType(l), .unacceptableContentType(r)): return l == r
        case (.emptyData, .emptyData): return true
        case (.decodingFailed, .decodingFailed): return true
        case let (.processingFailed(l), .processingFailed(r)): return l == r
        case (.cancelled, .cancelled): return true
        case let (.dataLoading(l), .dataLoading(r)): return l == r
        default: return false
        }
    }
}
