import CoreGraphics
import Foundation

/// Describes a single image load: where it comes from, how it should be decoded/processed, and
/// how it interacts with the caches.
public struct ImageRequest: Sendable {
    /// Per-request tuning.
    public struct Options: Sendable {
        /// Which cache layers to read from / write to.
        public var cachePolicy: CachePolicy

        /// Relative scheduling priority for the underlying network task.
        public var priority: TaskPriority

        /// If set, the image is decoded straight to a thumbnail whose largest side is at most
        /// `max(width, height)` points (multiplied by `scale`), never allocating the full bitmap.
        public var downsampleSize: CGSize?

        /// The display scale applied to `downsampleSize` and to the decoded image.
        public var scale: CGFloat

        public init(
            cachePolicy: CachePolicy = .memoryAndDisk,
            priority: TaskPriority = .medium,
            downsampleSize: CGSize? = nil,
            scale: CGFloat = 1.0
        ) {
            self.cachePolicy = cachePolicy
            self.priority = priority
            self.downsampleSize = downsampleSize
            self.scale = scale
        }
    }

    /// The remote HTTP(S) URL to load. The default `URLSessionDataLoader` requires an HTTP(S)
    /// response; substitute a custom `DataLoading` to source images from elsewhere (e.g. files).
    public let url: URL

    /// Processors applied in order after decoding.
    public let processors: [any ImageProcessing]

    /// Per-request options.
    public var options: Options

    public init(
        url: URL,
        processors: [any ImageProcessing] = [],
        options: Options = .init()
    ) {
        self.url = url
        self.processors = processors
        self.options = options
    }

    /// A deterministic key identifying the *content* produced by this request (URL + scale +
    /// downsample size + processors). Independent of cache policy/priority, so a
    /// `.reloadIgnoringCache` request still overwrites the same entry a normal request would read.
    ///
    /// `scale` is always included: two full-size requests at different scales decode to containers
    /// with different display scales, so they must not collide on one cache entry.
    public var cacheKey: String {
        var key = url.absoluteString
        key += "|s:\(options.scale)"
        if let size = options.downsampleSize {
            key += "|d:\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        }
        for processor in processors {
            key += "|p:\(processor.identifier)"
        }
        return key
    }

    /// The key used to coalesce concurrent in-flight requests. It extends `cacheKey` with the
    /// cache policy, so requests whose caching *behavior* differs (e.g. `.reloadIgnoringCache` vs
    /// `.memoryAndDisk`, or `.none` vs a default) never share one underlying load — which would
    /// otherwise let a force-reload return cached bytes, or let a default request miss its writes.
    ///
    /// It also serves as a stable identity for UI loads: two requests with the same `dedupeKey`
    /// produce the same displayed result via the same caching behavior, so a view need only reload
    /// when this value changes. Priority is deliberately excluded — it is a scheduling hint that
    /// should not restart display.
    public var dedupeKey: String {
        cacheKey + "|policy:\(options.cachePolicy.identifier)"
    }
}
