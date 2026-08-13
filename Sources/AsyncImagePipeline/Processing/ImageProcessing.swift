/// A transform applied to a decoded image before it is cached and returned.
///
/// The `identifier` participates in the cache key, so two requests with different processors (or
/// differently-configured processors) resolve to distinct cache entries.
public protocol ImageProcessing: Sendable {
    /// A stable string that uniquely describes this processor and its configuration.
    var identifier: String { get }

    /// Transforms the container, returning a new one. Throws to fail the request.
    func process(_ container: ImageContainer) throws -> ImageContainer
}
