import XCTest
@testable import OpenAgentSDK

final class MemoryLifecycleServiceTests: XCTestCase {

    private let service = MemoryLifecycleService()

    private func makeFact(
        id: String = "test-id",
        domain: String = "test",
        status: MemoryFactStatus = .candidate,
        confidence: Double = 0.5,
        evidenceCount: Int = 1,
        kind: MemoryKind = .affordance,
        lastVerifiedAt: Date = Date()
    ) -> MemoryFact {
        MemoryFact(
            id: id, domain: domain, content: "test content",
            status: status, confidence: confidence, evidenceCount: evidenceCount,
            source: .observation, kind: kind,
            createdAt: Date(), lastVerifiedAt: lastVerifiedAt
        )
    }

    // MARK: - addFact

    func testAddFactCreatesNew() {
        let fact = makeFact(id: "new-id")
        let result = service.addFact(fact, mergingWith: [])
        XCTAssertEqual(result.id, "new-id")
        XCTAssertEqual(result.status, .candidate)
    }

    func testAddFactMergesWithExisting() {
        let existing = makeFact(id: "same", confidence: 0.5, evidenceCount: 1)
        let incoming = makeFact(id: "same", confidence: 0.4, evidenceCount: 1)
        let result = service.addFact(incoming, mergingWith: [existing])

        XCTAssertEqual(result.id, "same")
        XCTAssertEqual(result.evidenceCount, 2)
        XCTAssertEqual(result.confidence, 0.5) // max of 0.5, 0.4; no promotion (evidence=2 but conf < 0.65)
    }

    func testAddFactReactivatesRetired() {
        let retired = makeFact(id: "same", status: .retired, confidence: 0.8, evidenceCount: 5)
        let incoming = makeFact(id: "same")
        let result = service.addFact(incoming, mergingWith: [retired])

        XCTAssertEqual(result.status, .candidate)
        XCTAssertEqual(result.evidenceCount, 1)
    }

    // MARK: - Promotion

    func testOnlyCandidateCanBePromoted() {
        let active = makeFact(status: .active, confidence: 0.9, evidenceCount: 5)
        let result = service.maybePromote(fact: active)
        XCTAssertNil(result, "Active facts should not be promoted again")
    }

    func testRetiredCannotBePromoted() {
        let retired = makeFact(status: .retired, confidence: 0.9, evidenceCount: 5)
        let result = service.maybePromote(fact: retired)
        XCTAssertNil(result, "Retired facts should not be promoted")
    }

    func testPromotionWhenThresholdsMet() {
        let fact = makeFact(status: .candidate, confidence: 0.65, evidenceCount: 2)
        let promoted = service.maybePromote(fact: fact)
        XCTAssertNotNil(promoted)
        XCTAssertEqual(promoted?.status, .active)
        XCTAssertEqual(promoted?.confidence, 0.75) // +0.1 boost
    }

    func testNoPromotionBelowEvidenceThreshold() {
        let fact = makeFact(status: .candidate, confidence: 0.7, evidenceCount: 1)
        let result = service.maybePromote(fact: fact)
        XCTAssertNil(result)
    }

    func testNoPromotionBelowConfidenceThreshold() {
        let fact = makeFact(status: .candidate, confidence: 0.6, evidenceCount: 3)
        let result = service.maybePromote(fact: fact)
        XCTAssertNil(result)
    }

    func testPromotionConfidenceCappedAt1() {
        let fact = makeFact(status: .candidate, confidence: 0.95, evidenceCount: 3)
        let promoted = service.maybePromote(fact: fact)
        XCTAssertEqual(promoted?.confidence, 1.0)
    }

    // MARK: - Demotion

    func testDemotionOfStaleActiveFacts() {
        let staleDate = Date().addingTimeInterval(-3_000_000) // > 30 days ago
        let active = makeFact(status: .active, lastVerifiedAt: staleDate)
        let demoted = service.demoteRetired(facts: [active], lastVerifiedBefore: Date())

        XCTAssertEqual(demoted.count, 1)
        XCTAssertEqual(demoted.first?.status, .retired)
    }

    func testNoDemotionOfRecentActiveFacts() {
        let recent = makeFact(status: .active, lastVerifiedAt: Date())
        let cutoff = Date().addingTimeInterval(-1) // cutoff is in the past
        let demoted = service.demoteRetired(facts: [recent], lastVerifiedBefore: cutoff)
        XCTAssertTrue(demoted.isEmpty)
    }

    func testNoDemotionOfCandidateFacts() {
        let staleDate = Date().addingTimeInterval(-3_000_000)
        let candidate = makeFact(status: .candidate, lastVerifiedAt: staleDate)
        let demoted = service.demoteRetired(facts: [candidate], lastVerifiedBefore: Date())
        XCTAssertTrue(demoted.isEmpty)
    }

    // MARK: - Reactivation

    func testMergePreservesExistingContentWhenIncomingIsEmpty() {
        let existing = makeFact(id: "same", confidence: 0.5, evidenceCount: 1)
        let incoming = MemoryFact(
            id: "same", domain: "test", content: "",
            status: .candidate, confidence: 0.6, evidenceCount: 1,
            source: .observation, kind: .affordance,
            createdAt: Date(), lastVerifiedAt: Date()
        )
        let result = service.mergeFact(existing: existing, incoming: incoming)
        XCTAssertEqual(result.content, "test content", "Should keep existing content when incoming is empty")
    }

    func testDemotionMixedStaleAndRecent() {
        let cutoff = Date()
        let stale = makeFact(id: "stale", status: .active, lastVerifiedAt: cutoff.addingTimeInterval(-3_000_000))
        let recent = makeFact(id: "recent", status: .active, lastVerifiedAt: cutoff.addingTimeInterval(60))
        let candidate = makeFact(id: "cand", status: .candidate, lastVerifiedAt: cutoff.addingTimeInterval(-3_000_000))

        let demoted = service.demoteRetired(facts: [stale, recent, candidate], lastVerifiedBefore: cutoff)
        XCTAssertEqual(demoted.count, 1, "Only stale active facts should be demoted")
        XCTAssertEqual(demoted.first?.id, "stale")
    }

    func testReactivateRetired() {
        let retired = makeFact(status: .retired, evidenceCount: 10)
        let reactivatedAt = Date().addingTimeInterval(-100)
        let reactivated = service.reactivateRetired(fact: retired, reactivatedAt: reactivatedAt)

        XCTAssertEqual(reactivated.status, .candidate)
        XCTAssertEqual(reactivated.evidenceCount, 1)
        XCTAssertEqual(reactivated.lastVerifiedAt, reactivatedAt)
    }

    func testReactivateRetiredDefaultDate() {
        let before = Date()
        let retired = makeFact(status: .retired, evidenceCount: 5)
        let reactivated = service.reactivateRetired(fact: retired)
        let after = Date()

        XCTAssertEqual(reactivated.status, .candidate)
        XCTAssertTrue(reactivated.lastVerifiedAt >= before && reactivated.lastVerifiedAt <= after)
    }

    // MARK: - selectActiveFacts

    func testSelectActiveFactsSortsByConfidence() {
        let facts = [
            makeFact(id: "a", domain: "test", status: .active, confidence: 0.5),
            makeFact(id: "b", domain: "test", status: .active, confidence: 0.9),
            makeFact(id: "c", domain: "test", status: .active, confidence: 0.7),
            makeFact(id: "d", domain: "other", status: .active, confidence: 0.99),
        ]
        let selected = service.selectActiveFacts(domain: "test", from: facts)

        XCTAssertEqual(selected.count, 3)
        XCTAssertEqual(selected[0].id, "b")
        XCTAssertEqual(selected[1].id, "c")
        XCTAssertEqual(selected[2].id, "a")
    }
}
