/// Controls which cache layers a request reads from and writes to.
public enum CachePolicy: Sendable, Hashable {
    /// Read and write both memory and disk (default).
    case memoryAndDisk

    /// Read and write only the in-memory cache; never touch disk.
    case memoryOnly

    /// Read and write only the on-disk cache; skip the memory layer.
    case diskOnly

    /// Ignore any cached value and fetch fresh, then repopulate both caches.
    case reloadIgnoringCache

    /// Skip cache reads entirely and do not persist the result.
    case none

    /// A stable discriminator used when coalescing in-flight requests by behavior.
    var identifier: String {
        switch self {
        case .memoryAndDisk: return "memoryAndDisk"
        case .memoryOnly: return "memoryOnly"
        case .diskOnly: return "diskOnly"
        case .reloadIgnoringCache: return "reloadIgnoringCache"
        case .none: return "none"
        }
    }

    var readsFromMemory: Bool {
        switch self {
        case .memoryAndDisk, .memoryOnly: return true
        case .diskOnly, .reloadIgnoringCache, .none: return false
        }
    }

    var writesToMemory: Bool {
        switch self {
        case .memoryAndDisk, .memoryOnly, .reloadIgnoringCache: return true
        case .diskOnly, .none: return false
        }
    }

    var readsFromDisk: Bool {
        switch self {
        case .memoryAndDisk, .diskOnly: return true
        case .memoryOnly, .reloadIgnoringCache, .none: return false
        }
    }

    var writesToDisk: Bool {
        switch self {
        case .memoryAndDisk, .diskOnly, .reloadIgnoringCache: return true
        case .memoryOnly, .none: return false
        }
    }
}
