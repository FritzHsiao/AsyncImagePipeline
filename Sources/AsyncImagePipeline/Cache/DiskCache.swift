import Foundation

/// Persistent cache of encoded image bytes, stored as individual files.
///
/// Isolated as an `actor`, so its filesystem bookkeeping (size accounting, eviction) is race-free
/// without explicit locking. Enforces an optional total-size cap (LRU eviction by last access) and
/// an optional time-to-live.
public actor DiskCache: DiskCaching {
    private let directory: URL
    private let fileManager: FileManager
    private let sizeLimit: Int
    private let timeToLive: TimeInterval?

    private var didPrepareDirectory = false

    /// - Parameters:
    ///   - name: Subdirectory name inside Caches; distinct names give isolated caches.
    ///   - sizeLimit: Maximum total bytes on disk before LRU eviction (default ~150 MB).
    ///   - timeToLive: If set, entries older than this (by last access) are treated as misses and
    ///     removed. `nil` means entries never expire by age.
    ///   - fileManager: Injected for testability.
    public init(
        name: String = "AsyncImagePipeline",
        sizeLimit: Int = 150 * 1024 * 1024,
        timeToLive: TimeInterval? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.sizeLimit = sizeLimit
        self.timeToLive = timeToLive

        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = caches.appendingPathComponent(name, isDirectory: true)
    }

    /// Directly targets a caller-provided directory (used by tests).
    public init(
        directory: URL,
        sizeLimit: Int = 150 * 1024 * 1024,
        timeToLive: TimeInterval? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.sizeLimit = sizeLimit
        self.timeToLive = timeToLive
        self.directory = directory
    }

    // MARK: DiskCaching

    public func data(for key: String) async -> Data? {
        prepareDirectoryIfNeeded()
        let url = fileURL(for: key)

        guard let data = try? Data(contentsOf: url) else { return nil }

        if let ttl = timeToLive, isExpired(url, ttl: ttl) {
            try? fileManager.removeItem(at: url)
            return nil
        }

        // Touch the access time so eviction treats recently-read entries as "hot".
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    public func store(_ data: Data, for key: String) async {
        prepareDirectoryIfNeeded()
        let url = fileURL(for: key)
        do {
            try data.write(to: url, options: .atomic)
            trimIfNeeded()
        } catch {
            // A failed disk write is non-fatal: the pipeline still has the in-memory result.
        }
    }

    public func removeData(for key: String) async {
        try? fileManager.removeItem(at: fileURL(for: key))
    }

    public func removeAll() async {
        try? fileManager.removeItem(at: directory)
        didPrepareDirectory = false
    }

    // MARK: Helpers

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(CacheKey.filename(for: key), isDirectory: false)
    }

    private func prepareDirectoryIfNeeded() {
        guard !didPrepareDirectory else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        didPrepareDirectory = true
    }

    private func isExpired(_ url: URL, ttl: TimeInterval) -> Bool {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modified = values?.contentModificationDate else { return false }
        return Date().timeIntervalSince(modified) > ttl
    }

    /// Evicts least-recently-used entries until the directory is within `sizeLimit`.
    private func trimIfNeeded() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        ) else { return }

        var entries: [(url: URL, size: Int, date: Date)] = []
        var total = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = values?.totalFileAllocatedSize ?? 0
            let date = values?.contentModificationDate ?? .distantPast
            entries.append((url, size, date))
            total += size
        }

        guard total > sizeLimit else { return }

        // Oldest first; remove until we're back under the limit.
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > sizeLimit else { break }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
