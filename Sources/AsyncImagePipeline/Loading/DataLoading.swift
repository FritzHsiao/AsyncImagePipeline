import Foundation

/// The network seam. Everything above it works in terms of this protocol, so tests can inject a
/// deterministic loader instead of hitting the network.
public protocol DataLoading: Sendable {
    /// Loads the raw bytes for `request`. Must honor cooperative cancellation.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
