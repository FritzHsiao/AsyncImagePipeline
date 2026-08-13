import Foundation

/// Default `DataLoading` backed by `URLSession`. Its `async` API already propagates `Task`
/// cancellation to the underlying data task.
public struct URLSessionDataLoader: DataLoading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PipelineError.notAnHTTPResponse
        }
        return (data, http)
    }
}
