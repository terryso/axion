import Foundation
import Testing
import OpenAgentSDK

@testable import AxionCLI

// [P0] FamiliarityTracker type existence, familiarity threshold logic
// [P1] Edge cases (duplicate familiar tag, empty domain, boundary count)
// Story 4.2 AC: #4

// MARK: - FamiliarityTracker ATDD Tests

/// ATDD red-phase tests for FamiliarityTracker (Story 4.2 AC4).
@Suite("FamiliarityTracker")
struct FamiliarityTrackerTests {

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

    @Test("type exists")
    func typeExists() {
        let _ = FamiliarityTracker.self
    }

    // MARK: - P0 AC4: Familiarity threshold (< 3 no mark, >= 3 marks familiar)

    @Test("below threshold does not mark")
    func belowThresholdDoesNotMark() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        try await store.save(domain: domain, knowledge: makeEntry(
            id: "run-1", content: "Success 1", tags: ["app:\(domain)", "success"]
        ))
        try await store.save(domain: domain, knowledge: makeEntry(
            id: "run-2", content: "Success 2", tags: ["app:\(domain)", "success"]
        ))

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { entry in
            entry.tags.contains("familiar")
        }
        #expect(familiarEntries.isEmpty, "Should NOT mark as familiar with only 2 successful runs")
    }

    @Test("at threshold marks familiar")
    func atThresholdMarksFamiliar() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

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

        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { entry in
            entry.tags.contains("familiar")
        }
        #expect(!familiarEntries.isEmpty, "Should mark as familiar with exactly 3 successful runs")
    }

    @Test("above threshold marks familiar")
    func aboveThresholdMarksFamiliar() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

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
        #expect(!familiarEntries.isEmpty, "Should mark as familiar with > 3 successful runs")
    }

    // MARK: - P0 AC4: Does not duplicate familiar tag

    @Test("already familiar does not duplicate")
    func alreadyFamiliarDoesNotDuplicate() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        for i in 1...3 {
            try await store.save(domain: domain, knowledge: makeEntry(
                id: "run-\(i)", content: "Success \(i)", tags: ["app:\(domain)", "success"]
            ))
        }

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let entriesAfterFirst = try await store.query(domain: domain, filter: nil)
        let familiarCountAfterFirst = entriesAfterFirst.filter { $0.tags.contains("familiar") }.count

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let entriesAfterSecond = try await store.query(domain: domain, filter: nil)
        let familiarCountAfterSecond = entriesAfterSecond.filter { $0.tags.contains("familiar") }.count

        #expect(familiarCountAfterFirst == familiarCountAfterSecond,
            "Should not duplicate familiar tag on repeated calls")
    }

    // MARK: - P0 AC4: Only counts success entries (not failures)

    @Test("only counts successes")
    func onlyCountsSuccesses() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

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
        #expect(familiarEntries.isEmpty,
            "Should NOT mark familiar when only 2 successes exist (even with many failures)")
    }

    @Test("mixed with three successes marks familiar")
    func mixedWithThreeSuccessesMarksFamiliar() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

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
        #expect(!familiarEntries.isEmpty,
            "Should mark familiar with 3 successes even with failures present")
    }

    // MARK: - P1: Edge Cases

    @Test("empty domain does not mark")
    func emptyDomainDoesNotMark() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()

        try await tracker.checkAndUpdateFamiliarity(domain: "com.apple.empty", store: store)

        let domains = try await store.listDomains()
        #expect(domains.isEmpty, "Empty domain should not create any entries")
    }

    @Test("zero successful entries does not mark")
    func zeroSuccessfulEntriesDoesNotMark() async throws {
        let store = InMemoryStore()
        let tracker = FamiliarityTracker()
        let domain = "com.apple.calculator"

        try await store.save(domain: domain, knowledge: makeEntry(
            id: "fail-1", content: "Failure", tags: ["app:\(domain)", "failure"]
        ))

        try await tracker.checkAndUpdateFamiliarity(domain: domain, store: store)

        let allEntries = try await store.query(domain: domain, filter: nil)
        let familiarEntries = allEntries.filter { $0.tags.contains("familiar") }
        #expect(familiarEntries.isEmpty, "Should not mark familiar with 0 successful entries")
    }

    @Test("familiar entry has correct tags")
    func familiarEntryHasCorrectTags() async throws {
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

        #expect(familiarEntry != nil, "Should have a familiar entry")
        let entry = familiarEntry!

        #expect(entry.tags.contains("app:\(domain)"), "Familiar entry should include app domain tag")
        #expect(entry.tags.contains("familiar"), "Familiar entry should include 'familiar' tag")
    }
}
