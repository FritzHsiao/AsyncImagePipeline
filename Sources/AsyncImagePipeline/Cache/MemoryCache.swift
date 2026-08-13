import Foundation

/// In-memory image cache backed by `NSCache`.
///
/// `NSCache` is internally thread-safe, so this wrapper is safe to treat as `Sendable` even though
/// `NSCache` itself is a reference type. Entries are evicted automatically under memory pressure
/// and by the configured count / total-cost limits (cost is measured in bytes).
public final class MemoryCache: MemoryCaching, @unchecked Sendable {
    private final class Entry {
        let container: ImageContainer
        init(_ container: ImageContainer) { self.container = container }
    }

    private let storage = NSCache<NSString, Entry>()

    /// - Parameters:
    ///   - countLimit: Maximum number of images (0 = unlimited).
    ///   - totalCostLimit: Maximum total byte cost before eviction (default ~100 MB).
    public init(countLimit: Int = 0, totalCostLimit: Int = 100 * 1024 * 1024) {
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
    }

    public func image(for key: String) -> ImageContainer? {
        storage.object(forKey: key as NSString)?.container
    }

    public func store(_ container: ImageContainer, for key: String) {
        storage.setObject(
            Entry(container),
            forKey: key as NSString,
            cost: container.estimatedCostInBytes
        )
    }

    public func removeImage(for key: String) {
        storage.removeObject(forKey: key as NSString)
    }

    public func removeAll() {
        storage.removeAllObjects()
    }
}
