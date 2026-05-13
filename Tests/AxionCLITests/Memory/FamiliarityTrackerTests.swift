import XCTest
import OpenAgentSDK

@testable import AxionCLI

// [P0] FamiliarityTracker type existence, familiarity threshold logic
// [P1] Edge cases (duplicate familiar tag, empty domain, boundary count)
// Story 4.2 AC: #4

// MARK: - FamiliarityTracker ATDD Tests

/// ATDD red-phase tests for FamiliarityTracker (Story 4.2 AC4).
/// Tests that FamiliarityTracker correctly queries success counts from
/// MemoryStore and adds "familiar" tags when >= 3 successful operations exist.
///
/// TDD RED PHASE: These tests will not compile until FamiliarityTracker is implemented
/// in Sources/AxionCLI/Memory/FamiliarityTracker.swift.
final class FamiliarityTrackerTests: XCTestCase {

    // MARK: - Helper: Create KnowledgeEntry

    private func makeEntry(
        id: String = UUID().uuidString,
        content: String,
        tags: [String],
        createdAt: Date = Date(),
        sourceRunId: String? = nil
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: id,
            content: content,
            tags: tags,
            createdAt: createdAt,
            sourceRunId: sourceRunId
        )
    }

    // MARK: - P0: Type Existence

    func test_familiarityTracker_typeExists() {
        let _ = FamiliarityTracker.self
    }

    // MARK: - P0 AC4: Familiarity threshold (< 3 no mark, >= 3 marks familiar)

    func test_checkAndUpdateFamiliarity_belowThreshold_doesNotMark() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        // Only 2 successful entries — below the threshold of 3
        try await store.save(domain: domain, knowledge: makeEntry(
            id: "run-1", content: "Success 1", tags: ["app:\(domain)", "success"]
        ))
        try await store.save(domain: domain, knowledge: makeEntry(
            id: "run-2", content: "Success 2", tags: ["app:\(domain)", "success"]
        ))

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        // Verify no "familiar" entry was saved
        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { entry in
            entry.tags.contains("familiar")
        }
        XCTAssertTrue(familiarEntries.isEmpty,
            "Should NOT mark as familiar with only 2 successful runs")
    }

    func test_checkAndUpdateFamiliarity_atThreshold_marksFamiliar() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        // Exactly 3 successful entries — meets the threshold
        try await store.save(domain: domain, knowledge: makeEntry(
            id: "run-1", content: "Success 1", tags: ["app:\(domain)", "success"]
        ))
        try await store.save(domain: domain, knowledge: makeEntry(
            id: "run-2", content: "Success 2", tags: ["app:\(domain)", "success"]
        ))
        try await store.save(domain: domain, knowledge: makeEntry(
            id: "run-3", content: "Success 3", tags: ["app:\(domain)", "success"]
        ))

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        // Verify a "familiar" entry was saved
        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { entry in
            entry.tags.contains("familiar")
        }
        XCTAssertFalse(familiarEntries.isEmpty,
            "Should mark as familiar with exactly 3 successful runs")
    }

    func test_checkAndUpdateFamiliarity_aboveThreshold_marksFamiliar() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        // 5 successful entries — above the threshold
        for i in 1...5 {
            try await store.save(domain: domain, knowledge: makeEntry(
                id: "run-\(i)", content: "Success \(i)", tags: ["app:\(domain)", "success"]
            ))
        }

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { entry in
            entry.tags.contains("familiar")
        }
        XCTAssertFalse(familiarEntries.isEmpty,
            "Should mark as familiar with > 3 successful runs")
    }

    // MARK: - P0 AC4: Does not duplicate familiar tag

    func test_checkAndUpdateFamiliarity_alreadyFamiliar_doesNotDuplicate() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        // Pre-populate with 3 successful entries
        for i in 1...3 {
            try await store.save(domain: domain, knowledge: makeEntry(
                id: "run-\(i)", content: "Success \(i)", tags: ["app:\(domain)", "success"]
            ))
        }

        // First call: should create the familiar mark
        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let entriesAfterFirst = try await store.query(domain: domain, filter: nil)
        let familiarCountAfterFirst = entriesAfterFirst.filter { $0.tags.contains("familiar") }.count

        // Second call: should NOT add another familiar entry
        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let entriesAfterSecond = try await store.query(domain: domain, filter: nil)
        let familiarCountAfterSecond = entriesAfterSecond.filter { $0.tags.contains("familiar") }.count

        XCTAssertEqual(familiarCountAfterFirst, familiarCountAfterSecond,
            "Should not duplicate familiar tag on repeated calls")
    }

    // MARK: - P0 AC4: Only counts success entries (not failures)

    func test_checkAndUpdateFamiliarity_onlyCountsSuccesses() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        // 2 successes + 5 failures = still only 2 successes (below threshold)
        for i in 1...2 {
            try await store.save(domain: domain, knowledge: makeEntry(
                id: "success-\(i)", content: "Success \(i)", tags: ["app:\(domain)", "success"]
            ))
        }
        for i in 1...5 {
            try await store.save(domain: domain, knowledge: makeEntry(
                id: "failure-\(i)", content: "Failure \(i)", tags: ["app:\(domain)", "failure"]
            ))
        }

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { $0.tags.contains("familiar") }
        XCTAssertTrue(familiarEntries.isEmpty,
            "Should NOT mark familiar when only 2 successes exist (even with many failures)")
    }

    func test_checkAndUpdateFamiliarity_mixedWithThreeSuccesses_marksFamiliar() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        // 3 successes + 2 failures = 3 successes (meets threshold)
        for i in 1...3 {
            try await store.save(domain: domain, knowledge: makeEntry(
                id: "success-\(i)", content: "Success \(i)", tags: ["app:\(domain)", "success"]
            ))
        }
        for i in 1...2 {
            try await store.save(domain: domain, knowledge: makeEntry(
                id: "failure-\(i)", content: "Failure \(i)", tags: ["app:\(domain)", "failure"]
            ))
        }

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { $0.tags.contains("familiar") }
        XCTAssertFalse(familiarEntries.isEmpty,
            "Should mark familiar with 3 successes even with failures present")
    }

    // MARK: - P1: Edge Cases

    func test_checkAndUpdateFamiliarity_emptyDomain_doesNotMark() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()

        try await tracker.checkAndUpdateFamiliarity(domain: "com.apple.empty", store: store)

        let domains = try await store.listDomains()
        XCTAssertTrue(domains.isEmpty,
            "Empty domain should not create any entries")
    }

    func test_checkAndUpdateFamiliarity_zeroSuccessfulEntries_doesNotMark() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        // Only failure entries
        try await store.save(domain: domain, knowledge: makeEntry(
            id: "fail-1", content: "Failure", tags: ["app:\(domain)", "failure"]
        ))

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { $0.tags.contains("familiar") }
        XCTAssertTrue(familiarEntries.isEmpty,
            "Should not mark familiar with 0 successful entries")
    }

    func test_checkAndUpdateFamiliarity_familiarEntryHasCorrectTags() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        for i in 1...3 {
            try await store.save(domain: domain, knowledge: makeEntry(
                id: "run-\(i)", content: "Success \(i)", tags: ["app:\(domain)", "success"]
            ))
        }

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntry = allEntries.first { $0.tags.contains("familiar") }

        XCTAssertNotNil(familiarEntry, "Should have a familiar entry")
        let entry = familiarEntry!

        // Should have the app tag and familiar tag
        XCTAssertTrue(entry.tags.contains("app:\(domain)"),
            "Familiar entry should include app domain tag")
        XCTAssertTrue(entry.tags.contains("familiar"),
            "Familiar entry should include 'familiar' tag")
    }
}
