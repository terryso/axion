import XCTest
import OpenAgentSDK

@testable import AxionCLI
@testable import AxionCore

// [P0] MemoryCleanupService type existence, cleanupExpired logic
// [P1] Edge cases (empty store, mixed ages, domain validation)
// Story 4.1 AC: #3

// MARK: - MemoryCleanupService ATDD Tests

/// ATDD red-phase tests for MemoryCleanupService (Story 4.1 AC3).
/// Tests that MemoryCleanupService correctly cleans up expired memory entries
/// using SDK MemoryStoreProtocol's delete(domain:olderThan:) method.
///
/// TDD RED PHASE: These tests will not compile until MemoryCleanupService is implemented
/// in Sources/AxionCLI/Memory/MemoryCleanupService.swift.
final class MemoryCleanupServiceTests: XCTestCase {

    // MARK: - P0: Type Existence

    func test_memoryCleanupService_typeExists() {
        let _ = MemoryCleanupService.self
    }

    // MARK: - P0 AC3: Cleanup Expired Records

    func test_cleanupExpired_removesOldEntries() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        // Insert an old entry (40 days ago, older than 30-day maxAge)
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let oldEntry = KnowledgeEntry(
            id: "old-1",
            content: "Old memory",
            tags: ["test"],
            createdAt: oldDate,
            sourceRunId: "old-run"
        )
        try await store.save(domain: "com.apple.calculator", knowledge: oldEntry)

        // Insert a recent entry (1 day ago)
        let recentDate = Date().addingTimeInterval(-1 * 24 * 60 * 60)
        let recentEntry = KnowledgeEntry(
            id: "recent-1",
            content: "Recent memory",
            tags: ["test"],
            createdAt: recentDate,
            sourceRunId: "recent-run"
        )
        try await store.save(domain: "com.apple.calculator", knowledge: recentEntry)

        // Run cleanup
        let deletedCount = try await service.cleanupExpired(in: store)

        // The old entry should be deleted
        XCTAssertEqual(deletedCount, 1, "Should delete 1 old entry")

        // Verify remaining entries
        let remaining = try await store.query(domain: "com.apple.calculator", filter: nil)
        XCTAssertEqual(remaining.count, 1, "Should have 1 remaining entry")
        XCTAssertEqual(remaining.first?.id, "recent-1")
    }

    func test_cleanupExpired_removesFromMultipleDomains() async throws {
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

        XCTAssertEqual(deletedCount, 2, "Should delete from both domains")

        // Both domains should be empty now
        let domains = try await store.listDomains()
        XCTAssertTrue(domains.isEmpty, "All domains should be empty after cleanup")
    }

    func test_cleanupExpired_noExpiredEntries_returnsZero() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        // Insert only recent entries
        let recentEntry = KnowledgeEntry(
            id: "recent-1",
            content: "Recent memory",
            tags: ["test"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: "com.apple.calculator", knowledge: recentEntry)

        let deletedCount = try await service.cleanupExpired(in: store)

        XCTAssertEqual(deletedCount, 0, "Should delete 0 entries when none expired")
    }

    func test_cleanupExpired_emptyStore_returnsZero() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let deletedCount = try await service.cleanupExpired(in: store)

        XCTAssertEqual(deletedCount, 0, "Empty store should report 0 deletions")
    }

    func test_cleanupExpired_preservesRecentEntries() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        // Insert mix of old and recent entries
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

        XCTAssertEqual(deletedCount, 1, "Should delete only the old entry")

        let remaining = try await store.query(domain: "com.apple.calculator", filter: nil)
        XCTAssertEqual(remaining.count, 2, "Should preserve 2 recent entries")
        let remainingIds = Set(remaining.map { $0.id })
        XCTAssertTrue(remainingIds.contains("recent-1"))
        XCTAssertTrue(remainingIds.contains("recent-2"))
    }

    // MARK: - P0 AC3: Uses 30-day threshold

    func test_cleanupExpired_uses30DayThreshold() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        // Entry exactly 29 days old — should be preserved
        let twentyNineDaysAgo = Date().addingTimeInterval(-29 * 24 * 60 * 60)
        try await store.save(domain: "com.apple.calculator", knowledge: KnowledgeEntry(
            id: "29days", content: "29 days old", tags: ["test"], createdAt: twentyNineDaysAgo, sourceRunId: nil
        ))

        // Entry exactly 31 days old — should be deleted
        let thirtyOneDaysAgo = Date().addingTimeInterval(-31 * 24 * 60 * 60)
        try await store.save(domain: "com.apple.calculator", knowledge: KnowledgeEntry(
            id: "31days", content: "31 days old", tags: ["test"], createdAt: thirtyOneDaysAgo, sourceRunId: nil
        ))

        let deletedCount = try await service.cleanupExpired(in: store)

        XCTAssertEqual(deletedCount, 1, "Should delete only entries older than 30 days")

        let remaining = try await store.query(domain: "com.apple.calculator", filter: nil)
        XCTAssertEqual(remaining.count, 1, "Should preserve the 29-day-old entry")
        XCTAssertEqual(remaining.first?.id, "29days")
    }

    // MARK: - P1: Edge Cases

    func test_cleanupExpired_mixedOldAndRecentInSameDomain() async throws {
        let store = InMemoryStore()
        let service = MemoryCleanupService()

        let oldDate = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        let recentDate = Date().addingTimeInterval(-10 * 24 * 60 * 60)

        // Mix entries in the same domain
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

        XCTAssertEqual(deletedCount, 2, "Should delete 2 old entries from Safari domain")

        let remaining = try await store.query(domain: "com.apple.safari", filter: nil)
        XCTAssertEqual(remaining.count, 1, "Should preserve 1 recent entry")
        XCTAssertEqual(remaining.first?.id, "recent-safari-1")
    }
}
