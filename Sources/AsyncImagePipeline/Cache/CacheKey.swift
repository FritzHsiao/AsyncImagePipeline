import CryptoKit
import Foundation

/// Turns a request's `cacheKey` string into a filesystem-safe filename via SHA-256.
enum CacheKey {
    /// A hex-encoded SHA-256 digest, safe to use as a disk filename.
    static func filename(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
