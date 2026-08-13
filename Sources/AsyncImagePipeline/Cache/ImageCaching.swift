import Foundation

/// A synchronous, thread-safe in-memory cache of decoded images.
///
/// Implementations must be safe to call from any isolation domain (hence `Sendable`); the default
/// `MemoryCache` relies on `NSCache`'s internal locking.
public protocol MemoryCaching: Sendable {
    /// Returns the cached container for `key`, or `nil`.
    func image(for key: String) -> ImageContainer?

    /// Stores `container` under `key`, using its estimated byte cost.
    func store(_ container: ImageContainer, for key: String)

    /// Removes the entry for `key`.
    func removeImage(for key: String)

    /// Empties the cache.
    func removeAll()
}

/// An asynchronous, persistent cache of *encoded* image data (backed by the filesystem).
public protocol DiskCaching: Sendable {
    /// Returns the stored bytes for `key`, or `nil`. Touches the entry's access time on a hit.
    func data(for key: String) async -> Data?

    /// Persists `data` under `key`.
    func store(_ data: Data, for key: String) async

    /// Removes the entry for `key`.
    func removeData(for key: String) async

    /// Empties the cache directory.
    func removeAll() async
}
