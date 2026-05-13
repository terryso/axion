import Foundation
import OpenAgentSDK

/// Lightweight service that tracks App familiarity based on accumulated
/// successful operations stored in a ``MemoryStoreProtocol``.
///
/// When an App has >= 3 successful operations, this tracker saves a "familiar"
/// knowledge entry to mark the app as well-known. Subsequent calls with the
/// same domain will not create duplicate entries.
struct FamiliarityTracker {

    /// The minimum number of successful operations required to mark an app as familiar.
    static let familiarityThreshold = 3

    // MARK: - Public API

    /// Check the number of successful operations for a domain and update
    /// the "familiar" tag if the threshold is met.
    ///
    /// This method:
    /// 1. Queries all entries with "success" tag for the domain.
    /// 2. If count >= 3 and no existing "familiar" entry exists, saves one.
    /// 3. Does not duplicate the familiar entry if one already exists.
    ///
    /// - Parameters:
    ///   - domain: The App domain to check.
    ///   - store: The memory store to query and save to.
    func checkAndUpdateFamiliarity(
        domain: String,
        store: any MemoryStoreProtocol
    ) async throws {
        // Query all success entries for this domain
        let successEntries = try await store.query(
            domain: domain,
            filter: KnowledgeQueryFilter(tags: ["success"])
        )

        guard successEntries.count >= Self.familiarityThreshold else { return }

        // Check if a familiar entry already exists
        let existingFamiliar = try await store.query(
            domain: domain,
            filter: KnowledgeQueryFilter(tags: ["familiar"])
        )

        guard existingFamiliar.isEmpty else { return }

        // Save a familiar marker entry
        let familiarEntry = KnowledgeEntry(
            id: UUID().uuidString,
            content: "App \(domain) 已熟悉（累计 \(successEntries.count) 次成功操作）",
            tags: ["app:\(domain)", "familiar"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: domain, knowledge: familiarEntry)
    }
}
