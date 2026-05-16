import Foundation
import Testing
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// [P0] MemoryCleanupService type existence, cleanupExpired logic
// [P1] Edge cases (empty store, mixed ages, domain validation)
// Story 4.1 AC: #3

// MARK: - MemoryCleanupService ATDD Tests

/// ATDD red-phase tests for MemoryCleanupService (Story 4.1 AC3).
@Suite("MemoryCleanupService")
struct MemoryCleanupServiceTests {

    // MARK: - P0: Type Existence

    @Test("type exists")
    func typeExists() {
        let _ = MemoryCleanupService.self
    }

    // MARK: - P0 AC3: Cleanup Expired Records

    @Test("cleanup expired removes old entries")
    func cleanupExpiredRemovesOldEntries() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let oldEntry = KnowledgeEntry(
            id: "old-1",
            content: "Old memory",
            tags: ["test"],
            createdAt: oldDate,
            sourceRunId: "old-run"
        )
        try await store.save(domain: "com.apple.calculator", knowledge: oldEntry)

        let recentDate = Date().addingTimeInterval(-1 * 24 * 60 * 60)
        let recentEntry = KnowledgeEntry(
            id: "recent-1",
            content: "Recent memory",
            tags: ["test"],
            createdAt: recentDate,
            sourceRunId: "recent-run"
        )
        try await store.save(domain: "com.apple.calculator", knowledge: recentEntry)

        let deletedCount = try await service.cleanupExpired(in: store)

        #expect(deletedCount == 1, "Should delete 1 old entry")

        let remaining = try await store.query(domain: "com.apple.calculator", filter: nil)
        #expect(remaining.count == 1, "Should have 1 remaining entry")
        #expect(remaining.first?.id == "recent-1")
    }

    @Test("cleanup expired removes from multiple domains")
    func cleanupExpiredRemovesFromMultipleDomains() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let oldEntry1 = KnowledgeEntry(
            id: "old-calc",
            content: "Old Calculator memory",
            tags: ["test"],
            createdAt: oldDate,
            sourceRunId: nil
        )
        let oldEntry2 = KnowledgeEntry(
            id: "old-notes",
            content: "Old Notes memory",
            tags: ["test"],
            createdAt: oldDate,
            sourceRunId: nil
        )

        try await store.save(domain: "com.apple.calculator", knowledge: oldEntry1)
        try await store.save(domain: "com.apple.notes", knowledge: oldEntry2)

        let deletedCount = try await service.cleanupExpired(in: store)

        #expect(deletedCount == 2, "Should delete from both domains")

        let domains = try await store.listDomains()
        #expect(domains.isEmpty, "All domains should be empty after cleanup")
    }

    @Test("cleanup expired no expired entries returns zero")
    func cleanupExpiredNoExpiredEntriesReturnsZero() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let recentEntry = KnowledgeEntry(
            id: "recent-1",
            content: "Recent memory",
            tags: ["test"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: "com.apple.calculator", knowledge: recentEntry)

        let deletedCount = try await service.cleanupExpired(in: store)

        #expect(deletedCount == 0, "Should delete 0 entries when none expired")
    }

    @Test("cleanup expired empty store returns zero")
    func cleanupExpiredEmptyStoreReturnsZero() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let deletedCount = try await service.cleanupExpired(in: store)

        #expect(deletedCount == 0, "Empty store should report 0 deletions")
    }

    @Test("cleanup expired preserves recent entries")
    func cleanupExpiredPreservesRecentEntries() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let recentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60)

        try await store.save(domain: "com.apple.calculator", knowledge: KnowledgeEntry(
            id: "old-1", content: "Old", tags: ["test"], createdAt: oldDate, sourceRunId: nil
        ))
        try await store.save(domain: "com.apple.calculator", knowledge: KnowledgeEntry(
            id: "recent-1", content: "Recent", tags: ["test"], createdAt: recentDate, sourceRunId: nil
        ))
        try await store.save(domain: "com.apple.calculator", knowledge: KnowledgeEntry(
            id: "recent-2", content: "Very Recent", tags: ["test"], createdAt: Date(), sourceRunId: nil
        ))

        let deletedCount = try await service.cleanupExpired(in: store)

        #expect(deletedCount == 1, "Should delete only the old entry")

        let remaining = try await store.query(domain: "com.apple.calculator", filter: nil)
        #expect(remaining.count == 2, "Should preserve 2 recent entries")
        let remainingIds = Set(remaining.map { $0.id })
        #expect(remainingIds.contains("recent-1"))
        #expect(remainingIds.contains("recent-2"))
    }

    // MARK: - P0 AC3: Uses 30-day threshold

    @Test("cleanup expired uses 30-day threshold")
    func cleanupExpiredUses30DayThreshold() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let twentyNineDaysAgo = Date().addingTimeInterval(-29 * 24 * 60 * 60)
        try await store.save(domain: "com.apple.calculator", knowledge: KnowledgeEntry(
            id: "29days", content: "29 days old", tags: ["test"], createdAt: twentyNineDaysAgo, sourceRunId: nil
        ))

        let thirtyOneDaysAgo = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        try await store.save(domain: "com.apple.calculator", knowledge: KnowledgeEntry(
            id: "31days", content: "31 days old", tags: ["test"], createdAt: thirtyOneDaysAgo, sourceRunId: nil
        ))

        let deletedCount = try await service.cleanupExpired(in: store)

        #expect(deletedCount == 1, "Should delete only entries older than 30 days")

        let remaining = try await store.query(domain: "com.apple.calculator", filter: nil)
        #expect(remaining.count == 1, "Should preserve the 29-day-old entry")
        #expect(remaining.first?.id == "29days")
    }

    // MARK: - P1: Edge Cases

    @Test("cleanup expired mixed old and recent in same domain")
    func cleanupExpiredMixedOldAndRecentInSameDomain() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let oldDate = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        let recentDate = Date().addingTimeInterval(-10 * 24 * 60 * 60)

        try await store.save(domain: "com.apple.safari", knowledge: KnowledgeEntry(
            id: "old-safari-1", content: "Old Safari 1", tags: [], createdAt: oldDate, sourceRunId: nil
        ))
        try await store.save(domain: "com.apple.safari", knowledge: KnowledgeEntry(
            id: "recent-safari-1", content: "Recent Safari 1", tags: [], createdAt: recentDate, sourceRunId: nil
        ))
        try await store.save(domain: "com.apple.safari", knowledge: KnowledgeEntry(
            id: "old-safari-2", content: "Old Safari 2", tags: [], createdAt: oldDate, sourceRunId: nil
        ))

        let deletedCount = try await service.cleanupExpired(in: store)

        #expect(deletedCount == 2, "Should delete 2 old entries from Safari domain")

        let remaining = try await store.query(domain: "com.apple.safari", filter: nil)
        #expect(remaining.count == 1, "Should preserve 1 recent entry")
        #expect(remaining.first?.id == "recent-safari-1")
    }
}
