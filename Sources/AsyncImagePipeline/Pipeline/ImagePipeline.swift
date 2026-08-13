import Foundation

/// The entry point: an actor that turns a URL/`ImageRequest` into a decoded image, layering an
/// in-memory cache over an on-disk cache over the network, deduplicating concurrent requests, and
/// downsampling/processing as configured.
///
/// ```swift
/// let image = try await ImagePipeline.shared.image(for: url)
/// ```
public actor ImagePipeline {
    /// Shared instance using production defaults.
    public static let shared = ImagePipeline()

    private let configuration: ImagePipelineConfiguration
    private let pool = DeduplicatingTaskPool()

    public init(configuration: ImagePipelineConfiguration = .init()) {
        self.configuration = configuration
    }

    // MARK: Public API

    /// Loads the image at `url` with default options.
    public func image(for url: URL) async throws -> PlatformImage {
        try await image(for: ImageRequest(url: url))
    }

    /// Loads the image described by `request`.
    public func image(for request: ImageRequest) async throws -> PlatformImage {
        try await container(for: request).platformImage
    }

    /// Loads and returns the raw `ImageContainer` (used by the UI/prefetch layers).
    public func container(for request: ImageRequest) async throws -> ImageContainer {
        let cacheKey = request.cacheKey
        let policy = request.options.cachePolicy

        // Fast path: synchronous memory hit, no task hop.
        if policy.readsFromMemory, let hit = configuration.memoryCache.image(for: cacheKey) {
            return hit
        }

        let configuration = self.configuration
        // Coalesce by dedupeKey (content + policy) so requests with different caching behavior
        // don't share a load; cache reads/writes inside `produce` still use the content cacheKey.
        return try await pool.perform(key: request.dedupeKey, priority: request.options.priority) {
            try await ImagePipeline.produce(request: request, key: cacheKey, configuration: configuration)
        }
    }

    /// Warms the caches for `url` without returning the image. Deduplicates against live requests.
    @discardableResult
    public func prefetch(_ request: ImageRequest) async throws -> ImageContainer {
        try await container(for: request)
    }

    /// Removes a single entry from the in-memory cache.
    public func removeMemoryCachedImage(for request: ImageRequest) {
        configuration.memoryCache.removeImage(for: request.cacheKey)
    }

    /// Clears the in-memory cache.
    public func clearMemoryCache() {
        configuration.memoryCache.removeAll()
    }

    /// Clears the on-disk cache.
    public func clearDiskCache() async {
        await configuration.diskCache.removeAll()
    }

    // MARK: Production (runs off the actor)

    /// The actual load. Static and `nonisolated` so decoding/processing run on the cooperative
    /// pool rather than serializing on the pipeline actor.
    private static func produce(
        request: ImageRequest,
        key: String,
        configuration: ImagePipelineConfiguration
    ) async throws -> ImageContainer {
        let policy = request.options.cachePolicy
        let options = request.options

        // Disk layer: decode stored bytes and re-apply processors (the disk holds original data).
        if policy.readsFromDisk, let data = await configuration.diskCache.data(for: key) {
            if let container = try? configuration.decoder.decode(
                data,
                downsampleSize: options.downsampleSize,
                scale: options.scale
            ) {
                let processed = try apply(request.processors, to: container, key: key)
                if policy.writesToMemory {
                    configuration.memoryCache.store(processed, for: key)
                }
                return processed
            }
        }

        try Task.checkCancellation()

        // Network layer.
        var urlRequest = URLRequest(url: request.url)
        if case .reloadIgnoringCache = policy {
            urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        }
        let (data, response) = try await configuration.dataLoader.data(for: urlRequest)
        try configuration.validator.validate(data: data, response: response)

        try Task.checkCancellation()

        let container = try configuration.decoder.decode(
            data,
            downsampleSize: options.downsampleSize,
            scale: options.scale
        )
        let processed = try apply(request.processors, to: container, key: key)

        if policy.writesToMemory {
            configuration.memoryCache.store(processed, for: key)
        }
        if policy.writesToDisk {
            await configuration.diskCache.store(data, for: key)
        }
        return processed
    }

    private static func apply(
        _ processors: [any ImageProcessing],
        to container: ImageContainer,
        key: String
    ) throws -> ImageContainer {
        var current = container
        for processor in processors {
            current = try processor.process(current)
        }
        return current
    }
}
