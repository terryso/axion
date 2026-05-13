import Foundation
import OpenAgentSDK

/// Service that cleans up expired memory entries across all domains.
///
/// Iterates over every domain in a ``MemoryStoreProtocol``-conforming store
/// and deletes entries older than 30 days using the SDK's
/// `delete(domain:olderThan:)` method.
struct MemoryCleanupService {

    /// The threshold age for expiration (30 days in seconds).
    static let expirationInterval: TimeInterval = 30 * 24 * 60 * 60  // 2_592_000

    // MARK: - Public API

    /// Remove expired entries from all domains in the given store.
    ///
    /// - Parameter store: Any ``MemoryStoreProtocol``-conforming store.
    /// - Returns: The total number of deleted entries across all domains.
    func cleanupExpired(in store: any MemoryStoreProtocol) async throws -> Int {
        let domains = try await store.listDomains()
        guard !domains.isEmpty else { return 0 }

        let cutoffDate = Date().addingTimeInterval(-Self.expirationInterval)
        var totalDeleted = 0

        for domain in domains {
            let deleted = try await store.delete(domain: domain, olderThan: cutoffDate)
            totalDeleted += deleted
        }

        return totalDeleted
    }
}
