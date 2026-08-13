import XCTest
@testable import AsyncImagePipeline

final class MemoryCacheTests: XCTestCase {
    private func container(side: Int) -> ImageContainer {
        let data = TestFixtures.pngData(width: side, height: side)
        return try! ImageIODecoder().decode(data, downsampleSize: nil, scale: 1)
    }

    func testStoreAndRetrieve() {
        let cache = MemoryCache()
        let image = container(side: 10)
        cache.store(image, for: "key")

        let hit = cache.image(for: "key")
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.pixelWidth, 10)
    }

    func testMissReturnsNil() {
        XCTAssertNil(MemoryCache().image(for: "absent"))
    }

    func testRemove() {
        let cache = MemoryCache()
        cache.store(container(side: 8), for: "key")
        cache.removeImage(for: "key")
        XCTAssertNil(cache.image(for: "key"))
    }

    func testCostLimitEvicts() {
        // Room for roughly one 100x100 image (100*100*4 ≈ 40 KB).
        let cache = MemoryCache(totalCostLimit: 100 * 100 * 4)
        for index in 0..<20 {
            cache.store(container(side: 100), for: "key-\(index)")
        }
        // NSCache evicts to stay near the cost limit; not everything can survive.
        let survivors = (0..<20).filter { cache.image(for: "key-\($0)") != nil }
        XCTAssertLessThan(survivors.count, 20)
    }
}

final class DiskCacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = TestFixtures.makeTempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testRoundTrip() async {
        let cache = DiskCache(directory: directory)
        let payload = TestFixtures.pngData(width: 12, height: 12)

        await cache.store(payload, for: "key")
        let read = await cache.data(for: "key")
        XCTAssertEqual(read, payload)
    }

    func testMissReturnsNil() async {
        let cache = DiskCache(directory: directory)
        let read = await cache.data(for: "absent")
        XCTAssertNil(read)
    }

    func testExpiryByTTL() async {
        let cache = DiskCache(directory: directory, timeToLive: 0.05)
        await cache.store(TestFixtures.pngData(width: 4, height: 4), for: "key")

        try? await Task.sleep(for: .milliseconds(120))
        let read = await cache.data(for: "key")
        XCTAssertNil(read, "Entry older than its TTL should be treated as a miss")
    }

    func testRemoveAll() async {
        let cache = DiskCache(directory: directory)
        await cache.store(TestFixtures.pngData(width: 4, height: 4), for: "a")
        await cache.store(TestFixtures.pngData(width: 4, height: 4), for: "b")

        await cache.removeAll()
        let a = await cache.data(for: "a")
        let b = await cache.data(for: "b")
        XCTAssertNil(a)
        XCTAssertNil(b)
    }

    func testSizeLimitEviction() async {
        // Each ~64x64 PNG is small; cap the cache well below the total to force eviction.
        let cache = DiskCache(directory: directory, sizeLimit: 4 * 1024)
        for index in 0..<10 {
            await cache.store(TestFixtures.pngData(width: 64, height: 64), for: "key-\(index)")
        }
        var survivors = 0
        for index in 0..<10 where await cache.data(for: "key-\(index)") != nil {
            survivors += 1
        }
        XCTAssertLessThan(survivors, 10, "Oldest entries should have been evicted under the cap")
    }
}
