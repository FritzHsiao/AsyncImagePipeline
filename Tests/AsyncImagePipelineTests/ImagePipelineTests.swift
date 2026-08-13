import CoreGraphics
import XCTest
@testable import AsyncImagePipeline

final class ImagePipelineTests: XCTestCase {

    // MARK: End-to-end

    func testLoadsThroughNetworkThenServesFromMemory() async throws {
        let loader = MockDataLoader(
            payload: TestFixtures.pngData(width: 50, height: 50),
            response: TestFixtures.response()
        )
        let pipeline = TestFixtures.pipeline(loader: loader)
        let request = ImageRequest(url: TestFixtures.url)

        let first = try await pipeline.container(for: request)
        XCTAssertEqual(first.pixelWidth, 50)

        let second = try await pipeline.container(for: request)
        XCTAssertEqual(second.pixelWidth, 50)

        // Second call hit the memory cache — the loader ran only once.
        let calls = await loader.callCount
        XCTAssertEqual(calls, 1)
    }

    // MARK: Deduplication

    func testConcurrentRequestsShareOneLoad() async throws {
        let loader = MockDataLoader(
            payload: TestFixtures.pngData(width: 30, height: 30),
            response: TestFixtures.response(),
            delay: .milliseconds(80)
        )
        // .none policy so the memory cache never short-circuits the coalescing under test.
        let pipeline = TestFixtures.pipeline(loader: loader)
        let request = ImageRequest(
            url: TestFixtures.url,
            options: .init(cachePolicy: .none)
        )

        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try await pipeline.container(for: request).pixelWidth
                }
            }
            for try await width in group {
                XCTAssertEqual(width, 30)
            }
        }

        let calls = await loader.callCount
        XCTAssertEqual(calls, 1, "All concurrent requests should collapse onto one network load")
    }

    // MARK: Cancellation

    func testLoneCancellationCancelsUnderlyingLoad() async throws {
        let loader = MockDataLoader(
            payload: TestFixtures.pngData(width: 20, height: 20),
            response: TestFixtures.response(),
            delay: .seconds(5)
        )
        let pipeline = TestFixtures.pipeline(loader: loader)
        let request = ImageRequest(url: TestFixtures.url, options: .init(cachePolicy: .none))

        let task = Task { try await pipeline.container(for: request) }
        // Let the load start.
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled request should throw")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        // Give the cancellation propagation a beat to reach the loader.
        try await Task.sleep(for: .milliseconds(100))
        let cancelled = await loader.cancelledCount
        XCTAssertEqual(cancelled, 1, "The only caller withdrawing should cancel the shared load")
    }

    func testCancellingOneSubscriberLeavesSiblingUnaffected() async throws {
        let loader = MockDataLoader(
            payload: TestFixtures.pngData(width: 40, height: 40),
            response: TestFixtures.response(),
            delay: .milliseconds(300)
        )
        let pipeline = TestFixtures.pipeline(loader: loader)
        let request = ImageRequest(url: TestFixtures.url, options: .init(cachePolicy: .none))

        let victim = Task { try await pipeline.container(for: request) }
        let survivor = Task { try await pipeline.container(for: request) }

        // Let both subscribe to the same in-flight job.
        try await Task.sleep(for: .milliseconds(80))
        victim.cancel()

        // Survivor still gets a real image.
        let image = try await survivor.value
        XCTAssertEqual(image.pixelWidth, 40)

        // Victim is cancelled...
        do {
            _ = try await victim.value
            XCTFail("Cancelled subscriber should throw")
        } catch is CancellationError {
            // expected
        }

        // ...but the shared load ran exactly once and was NOT cancelled.
        let calls = await loader.callCount
        let cancelled = await loader.cancelledCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cancelled, 0, "Sibling kept the shared load alive")
    }

    // MARK: Cache policy

    func testMemoryOnlyPolicySkipsDisk() async throws {
        let disk = SpyDiskCache()
        let loader = MockDataLoader(
            payload: TestFixtures.pngData(width: 16, height: 16),
            response: TestFixtures.response()
        )
        let pipeline = TestFixtures.pipeline(loader: loader, diskCache: disk)
        let request = ImageRequest(url: TestFixtures.url, options: .init(cachePolicy: .memoryOnly))

        _ = try await pipeline.container(for: request)

        let reads = await disk.readCount
        let writes = await disk.storeCount
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(writes, 0)
    }

    func testReloadIgnoringCacheBypassesMemory() async throws {
        let memory = MemoryCache()
        let loader = MockDataLoader(
            payload: TestFixtures.pngData(width: 20, height: 20),
            response: TestFixtures.response()
        )
        let pipeline = TestFixtures.pipeline(loader: loader, memoryCache: memory)
        let request = ImageRequest(url: TestFixtures.url)

        // Pre-seed the memory cache with a differently-sized sentinel under the same key.
        let sentinel = try ImageIODecoder().decode(
            TestFixtures.pngData(width: 5, height: 5),
            downsampleSize: nil,
            scale: 1
        )
        memory.store(sentinel, for: request.cacheKey)

        let reload = ImageRequest(url: TestFixtures.url, options: .init(cachePolicy: .reloadIgnoringCache))
        let result = try await pipeline.container(for: reload)

        XCTAssertEqual(result.pixelWidth, 20, "reloadIgnoringCache should bypass the seeded memory entry")
        let calls = await loader.callCount
        XCTAssertEqual(calls, 1)
    }

    func testReloadDoesNotJoinCachingJob() async throws {
        // A slow disk-hit job for a default request is in flight; a concurrent .reloadIgnoringCache
        // request for the same content must NOT join it and must fetch fresh (P1 regression).
        let directory = TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let stalePayload = TestFixtures.pngData(width: 10, height: 10)
        let freshPayload = TestFixtures.pngData(width: 20, height: 20)

        // Seed disk with the "stale" 10x10 image under the default request's cache key.
        let disk = DiskCache(directory: directory)
        await disk.store(stalePayload, for: ImageRequest(url: TestFixtures.url).cacheKey)

        // Loader always serves the "fresh" 20x20 image, with a delay so both requests overlap.
        let loader = MockDataLoader(
            payload: freshPayload,
            response: TestFixtures.response(),
            delay: .milliseconds(120)
        )
        let pipeline = ImagePipeline(configuration: .init(
            dataLoader: loader,
            memoryCache: MemoryCache(),
            diskCache: disk
        ))

        async let defaultResult = pipeline.container(
            for: ImageRequest(url: TestFixtures.url, options: .init(cachePolicy: .memoryAndDisk))
        )
        // Give the default (disk-hit) job a head start.
        try await Task.sleep(for: .milliseconds(20))
        async let reloadResult = pipeline.container(
            for: ImageRequest(url: TestFixtures.url, options: .init(cachePolicy: .reloadIgnoringCache))
        )

        let (fromDefault, fromReload) = try await (defaultResult, reloadResult)
        XCTAssertEqual(fromDefault.pixelWidth, 10, "Default request should have served the disk hit")
        XCTAssertEqual(fromReload.pixelWidth, 20, "Reload must fetch fresh, not join the disk-hit job")

        let calls = await loader.callCount
        XCTAssertEqual(calls, 1, "Only the reload request hit the network")
    }

    func testDifferentScalesDoNotCollideInMemory() async throws {
        // Full-size requests differing only by scale must resolve to distinct cache entries (P2).
        let memory = MemoryCache()
        let scale1 = try ImageIODecoder().decode(
            TestFixtures.pngData(width: 30, height: 30), downsampleSize: nil, scale: 1
        )
        let requestScale1 = ImageRequest(url: TestFixtures.url, options: .init(scale: 1))
        let requestScale2 = ImageRequest(url: TestFixtures.url, options: .init(scale: 2))

        memory.store(scale1, for: requestScale1.cacheKey)

        XCTAssertNotEqual(requestScale1.cacheKey, requestScale2.cacheKey)
        XCTAssertNotNil(memory.image(for: requestScale1.cacheKey))
        XCTAssertNil(memory.image(for: requestScale2.cacheKey), "scale 2 must not read the scale 1 entry")
    }

    // MARK: Disk round-trip through the pipeline

    func testSecondPipelineReadsFromDisk() async throws {
        let directory = TestFixtures.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = TestFixtures.pngData(width: 24, height: 24)

        // First pipeline populates disk.
        let loaderA = MockDataLoader(payload: payload, response: TestFixtures.response())
        let pipelineA = ImagePipeline(configuration: .init(
            dataLoader: loaderA,
            memoryCache: MemoryCache(),
            diskCache: DiskCache(directory: directory)
        ))
        _ = try await pipelineA.container(for: ImageRequest(url: TestFixtures.url))

        // Second pipeline shares the disk directory but has a loader that would fail if hit.
        let loaderB = MockDataLoader(
            payload: Data(),
            response: TestFixtures.response(status: 500)
        )
        let pipelineB = ImagePipeline(configuration: .init(
            dataLoader: loaderB,
            memoryCache: MemoryCache(),
            diskCache: DiskCache(directory: directory)
        ))
        let result = try await pipelineB.container(for: ImageRequest(url: TestFixtures.url))

        XCTAssertEqual(result.pixelWidth, 24)
        let callsB = await loaderB.callCount
        XCTAssertEqual(callsB, 0, "Disk hit should avoid the network entirely")
    }
}
