import XCTest
@testable import AsyncImagePipeline
@testable import AsyncImagePipelineUI

final class PrefetcherTests: XCTestCase {

    func testPrefetchWarmsMemoryCache() async throws {
        let loader = CountingLoader(payload: UIFixtures.pngData(), response: UIFixtures.response())
        let pipeline = UIFixtures.pipeline(loader: loader)
        let prefetcher = Prefetcher(pipeline: pipeline, maxConcurrentLoads: 4)

        let url = UIFixtures.url(1)
        await prefetcher.startPrefetching(urls: [url])
        await prefetcher.waitUntilFinished()

        let afterPrefetch = await loader.callCount
        XCTAssertEqual(afterPrefetch, 1)

        // A subsequent real request is served from the warmed memory cache — no new load.
        _ = try await pipeline.container(for: ImageRequest(url: url))
        let afterFetch = await loader.callCount
        XCTAssertEqual(afterFetch, 1, "Prefetched image should be served from cache")
    }

    func testDuplicateRequestsAreCoalesced() async throws {
        let loader = CountingLoader(
            payload: UIFixtures.pngData(),
            response: UIFixtures.response(),
            delay: .milliseconds(60)
        )
        let pipeline = UIFixtures.pipeline(loader: loader)
        let prefetcher = Prefetcher(pipeline: pipeline)

        let url = UIFixtures.url(1)
        // Same URL three times in one batch → one tracked task, one load.
        await prefetcher.startPrefetching(urls: [url, url, url])
        let inFlight = await prefetcher.inFlightCount
        XCTAssertEqual(inFlight, 1)

        await prefetcher.waitUntilFinished()
        let calls = await loader.callCount
        XCTAssertEqual(calls, 1)
    }

    func testDistinctURLsEachLoad() async throws {
        let loader = CountingLoader(payload: UIFixtures.pngData(), response: UIFixtures.response())
        let pipeline = UIFixtures.pipeline(loader: loader)
        let prefetcher = Prefetcher(pipeline: pipeline)

        let urls = (0..<5).map { UIFixtures.url($0) }
        await prefetcher.startPrefetching(urls: urls)
        await prefetcher.waitUntilFinished()

        let calls = await loader.callCount
        XCTAssertEqual(calls, 5)
    }

    func testConcurrencyIsBounded() async throws {
        let loader = CountingLoader(
            payload: UIFixtures.pngData(),
            response: UIFixtures.response(),
            delay: .milliseconds(60)
        )
        let pipeline = UIFixtures.pipeline(loader: loader)
        let prefetcher = Prefetcher(pipeline: pipeline, maxConcurrentLoads: 2)

        let urls = (0..<8).map { UIFixtures.url($0) }
        await prefetcher.startPrefetching(urls: urls)
        await prefetcher.waitUntilFinished()

        let peak = await loader.maxConcurrent
        let calls = await loader.callCount
        XCTAssertEqual(calls, 8)
        XCTAssertLessThanOrEqual(peak, 2, "Prefetcher must not exceed its concurrency limit")
    }

    func testStopCancelsInFlightLoad() async throws {
        let loader = CountingLoader(
            payload: UIFixtures.pngData(),
            response: UIFixtures.response(),
            delay: .seconds(5)
        )
        let pipeline = UIFixtures.pipeline(loader: loader)
        let prefetcher = Prefetcher(pipeline: pipeline, maxConcurrentLoads: 4)

        let url = UIFixtures.url(1)
        await prefetcher.startPrefetching(urls: [url])
        // Let the load reach the network.
        try await Task.sleep(for: .milliseconds(120))
        await prefetcher.stopPrefetching(urls: [url])

        // Give cancellation a beat to propagate to the loader.
        try await Task.sleep(for: .milliseconds(120))
        let cancelled = await loader.cancelledCount
        let inFlight = await prefetcher.inFlightCount
        XCTAssertEqual(cancelled, 1, "Stopping a prefetch should cancel its underlying load")
        XCTAssertEqual(inFlight, 0)
    }
}
