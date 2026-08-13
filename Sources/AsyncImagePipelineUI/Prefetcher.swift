import Foundation
import AsyncImagePipeline

/// Warms the pipeline's caches ahead of display — e.g. for the rows just past the visible edge of
/// a scroll view. Loads run at low priority with **bounded concurrency**, and share the pipeline's
/// deduplication, so prefetching an image already on screen costs nothing extra.
///
/// Isolated as an `actor`, so its in-flight bookkeeping needs no locks.
public actor Prefetcher {
    private let pipeline: ImagePipeline
    private let maxConcurrent: Int

    /// In-flight prefetch tasks, keyed by content cache key (so duplicates coalesce here too).
    private var tasks: [String: Task<Void, Never>] = [:]

    // A small async semaphore limiting how many loads run at once.
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(pipeline: ImagePipeline = .shared, maxConcurrentLoads: Int = 5) {
        self.pipeline = pipeline
        self.maxConcurrent = max(1, maxConcurrentLoads)
        self.available = max(1, maxConcurrentLoads)
    }

    // MARK: Public API

    /// Begins prefetching each URL (default options, low priority).
    public func startPrefetching(urls: [URL]) {
        startPrefetching(requests: urls.map { url in
            ImageRequest(url: url, options: .init(priority: .low))
        })
    }

    /// Begins prefetching each request. Already-active requests are ignored.
    public func startPrefetching(requests: [ImageRequest]) {
        for request in requests {
            let key = request.cacheKey
            guard tasks[key] == nil else { continue }
            tasks[key] = Task { [weak self] in
                await self?.run(request: request, key: key)
            }
        }
    }

    /// Cancels prefetching for each URL (e.g. rows that scrolled back off-screen).
    public func stopPrefetching(urls: [URL]) {
        stopPrefetching(requests: urls.map { ImageRequest(url: $0) })
    }

    /// Cancels prefetching for each request.
    public func stopPrefetching(requests: [ImageRequest]) {
        for request in requests {
            cancel(key: request.cacheKey)
        }
    }

    /// Cancels all in-flight prefetching.
    public func stopAll() {
        for key in Array(tasks.keys) {
            cancel(key: key)
        }
    }

    /// The number of prefetches currently tracked — exposed for tests.
    public var inFlightCount: Int { tasks.count }

    /// Awaits completion of all currently-tracked prefetches — intended for tests.
    public func waitUntilFinished() async {
        for task in Array(tasks.values) {
            await task.value
        }
    }

    // MARK: Internals

    private func run(request: ImageRequest, key: String) async {
        defer { tasks[key] = nil }
        guard !Task.isCancelled else { return }

        await acquire()
        defer { release() }

        guard !Task.isCancelled else { return }
        _ = try? await pipeline.prefetch(request)
    }

    private func cancel(key: String) {
        tasks[key]?.cancel()
        tasks[key] = nil
    }

    // MARK: Bounded-concurrency semaphore

    private func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        // Suspend until a permit is transferred to us by `release`.
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if let continuation = waiters.first {
            waiters.removeFirst()
            // Transfer the permit directly to the next waiter (keep `available` unchanged).
            continuation.resume()
        } else {
            available += 1
        }
    }
}
