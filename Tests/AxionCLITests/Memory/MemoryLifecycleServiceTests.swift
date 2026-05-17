import Foundation
import Testing

@testable import AxionCLI

// Story 12.1 AC3, AC5, AC6, AC8: MemoryLifecycleService lifecycle tests

@Suite("MemoryLifecycleService")
struct MemoryLifecycleServiceTests {

    private let service = MemoryLifecycleService()

    // Helper to create a candidate fact
    private func makeCandidate(
        description: String = "test fact",
        confidence: Double = 0.7,
        evidenceCount: Int = 1,
        domain: String = "test"
    ) -> AppMemoryFact {
        var fact = AppMemoryFact.create(
            domain: domain,
            kind: .observation,
            description: description,
            confidence: confidence
        )
        fact.evidenceCount = evidenceCount
        return fact
    }

    private func makeActive(
        description: String = "active fact",
        confidence: Double = 0.8,
        domain: String = "test"
    ) -> AppMemoryFact {
        var fact = AppMemoryFact.create(
            domain: domain,
            kind: .observation,
            description: description,
            confidence: confidence
        )
        fact.status = .active
        fact.evidenceCount = 3
        return fact
    }

    private func makeRetired(
        description: String = "retired fact",
        domain: String = "test"
    ) -> AppMemoryFact {
        var fact = AppMemoryFact.create(
            domain: domain,
            kind: .observation,
            description: description
        )
        fact.status = .retired
        return fact
    }

    // MARK: - AC3: Evidence-based promotion (candidate → active)

    @Test("maybePromote returns nil when evidenceCount < 2")
    func maybePromoteInsufficientEvidence() {
        let fact = makeCandidate(confidence: 0.8, evidenceCount: 1)
        let result = service.maybePromote(fact: fact)
        #expect(result == nil)
    }

    @Test("maybePromote returns nil when confidence < 0.65")
    func maybePromoteInsufficientConfidence() {
        let fact = makeCandidate(confidence: 0.5, evidenceCount: 3)
        let result = service.maybePromote(fact: fact)
        #expect(result == nil)
    }

    @Test("maybePromote promotes when evidenceCount >= 2 and confidence >= 0.65")
    func maybePromoteSuccess() {
        let fact = makeCandidate(confidence: 0.7, evidenceCount: 2)
        let result = service.maybePromote(fact: fact)
        #expect(result != nil)
        #expect(result!.status == .active)
    }

    @Test("maybePromote boosts confidence by 0.1")
    func maybePromoteBoostsConfidence() {
        let fact = makeCandidate(confidence: 0.7, evidenceCount: 2)
        let result = service.maybePromote(fact: fact)!
        #expect(abs(result.confidence - 0.8) < 0.001)
    }

    @Test("maybePromote caps confidence at 1.0")
    func maybePromoteCapsConfidence() {
        let fact = makeCandidate(confidence: 0.95, evidenceCount: 5)
        let result = service.maybePromote(fact: fact)!
        #expect(result.confidence <= 1.0)
        #expect(result.confidence == 1.0)
    }

    @Test("maybePromote does not promote active or retired facts")
    func maybePromoteOnlyPromotesCandidates() {
        let active = makeActive()
        #expect(service.maybePromote(fact: active) == nil)

        let retired = makeRetired()
        #expect(service.maybePromote(fact: retired) == nil)
    }

    // MARK: - AC5: 30-day demotion (active → retired)

    @Test("demoteRetired demotes active facts older than cutoff")
    func demoteRetiredDemotesOldActive() {
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)  // 40 days ago
        var fact = makeActive()
        fact.updatedAt = oldDate
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)

        let result = service.demoteRetired(facts: [fact], lastVerifiedBefore: cutoff)
        #expect(result[0].status == .retired)
    }

    @Test("demoteRetired does not demote recently verified active facts")
    func demoteRetiredKeepsRecentActive() {
        let fact = makeActive()  // updatedAt = now
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)

        let result = service.demoteRetired(facts: [fact], lastVerifiedBefore: cutoff)
        #expect(result[0].status == .active)
    }

    @Test("demoteRetired does not affect candidate facts")
    func demoteRetiredIgnoresCandidates() {
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        var fact = makeCandidate()
        fact.updatedAt = oldDate
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)

        let result = service.demoteRetired(facts: [fact], lastVerifiedBefore: cutoff)
        #expect(result[0].status == .candidate)
    }

    // MARK: - AC6: Retired reactivation (retired → candidate)

    @Test("reactivateRetired changes retired to candidate")
    func reactivateRetiredChangesStatus() {
        let fact = makeRetired()
        let result = service.reactivateRetired(fact: fact)
        #expect(result.status == .candidate)
    }

    @Test("reactivateRetired resets evidenceCount to 1")
    func reactivateRetiredResetsEvidenceCount() {
        var fact = makeRetired()
        fact.evidenceCount = 10
        let result = service.reactivateRetired(fact: fact)
        #expect(result.evidenceCount == 1)
    }

    @Test("reactivateRetired updates updatedAt")
    func reactivateRetiredUpdatesDate() {
        let oldDate = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        var fact = makeRetired()
        fact.updatedAt = oldDate
        let result = service.reactivateRetired(fact: fact)
        #expect(result.updatedAt > oldDate)
    }

    @Test("reactivateRetired does not affect non-retired facts")
    func reactivateRetiredOnlyAffectsRetired() {
        let active = makeActive()
        let result = service.reactivateRetired(fact: active)
        #expect(result.status == .active)
    }

    // MARK: - AC8: addFact / mergeFact

    @Test("addFact creates new fact when no existing match")
    func addFactCreatesNew() {
        let newFact = makeCandidate(description: "new observation")
        let result = service.addFact(newFact, mergingWith: [])
        #expect(result.id == newFact.id)
        #expect(result.evidenceCount == 1)
    }

    @Test("addFact merges when existing match found")
    func addFactMergesWithExisting() {
        let existing = makeCandidate(description: "same observation", confidence: 0.6, evidenceCount: 2)
        let incoming = makeCandidate(description: "same observation", confidence: 0.8)
        let result = service.addFact(incoming, mergingWith: [existing])

        // Should merge: max confidence (0.8), evidenceCount +1 (3), promoted to active (0.8 + 0.1 boost)
        #expect(result.status == .active)
        #expect(abs(result.confidence - 0.9) < 0.001)
        #expect(result.evidenceCount == 3)
    }

    @Test("addFact reactivates retired fact instead of merging")
    func addFactReactivatesRetired() {
        let retired = makeRetired(description: "old observation")
        let incoming = makeCandidate(description: "old observation")
        let result = service.addFact(incoming, mergingWith: [retired])

        #expect(result.status == .candidate)
        #expect(result.evidenceCount == 1)
    }

    @Test("mergeFact takes max confidence and accumulates evidence")
    func mergeFactStrategy() {
        let existing = makeCandidate(confidence: 0.5, evidenceCount: 3)
        let incoming = makeCandidate(confidence: 0.7)
        let result = service.mergeFact(existing: existing, incoming: incoming)

        // evidenceCount = 4 >= 2, confidence = 0.7 >= 0.65, so promoted to active with +0.1
        #expect(result.status == .active)
        #expect(abs(result.confidence - 0.8) < 0.001)
        #expect(result.evidenceCount == 4)
    }

    @Test("mergeFact promotes candidate when thresholds met")
    func mergeFactPromotesWhenReady() {
        let existing = makeCandidate(confidence: 0.65, evidenceCount: 1)
        let incoming = makeCandidate(confidence: 0.7, evidenceCount: 1)
        let result = service.mergeFact(existing: existing, incoming: incoming)

        // evidenceCount becomes 2, confidence is 0.7 >= 0.65, so promote
        #expect(result.status == .active)
    }

    // MARK: - AC4: Contradictory facts create separate entries

    @Test("addFact creates separate entries for contradictory facts (AC4)")
    func addFactCreatesSeparateForContradictory() {
        // Same description but different kind → different ID → not merged
        let existing = AppMemoryFact.create(
            domain: "test",
            kind: .observation,
            description: "click button X",
            confidence: 0.7
        )
        let incoming = AppMemoryFact.create(
            domain: "test",
            kind: .avoid,
            description: "click button X",
            confidence: 0.5
        )

        let result = service.addFact(incoming, mergingWith: [existing])

        // Different kind → different ID → returned as new entry, not merged
        #expect(result.id != existing.id)
        #expect(result.kind == .avoid)
        #expect(result.evidenceCount == 1)
    }

    // MARK: - selectActiveFacts

    @Test("selectActiveFacts returns only active facts sorted by confidence")
    func selectActiveFactsFiltersAndSorts() {
        let facts = [
            makeCandidate(description: "a"),
            makeActive(description: "b", confidence: 0.7),
            makeRetired(description: "c"),
            makeActive(description: "d", confidence: 0.9),
        ]
        let result = service.selectActiveFacts(domain: "test", from: facts)
        #expect(result.count == 2)
        #expect(result[0].confidence > result[1].confidence)
    }

    @Test("selectActiveFacts filters by domain")
    func selectActiveFactsFiltersByDomain() {
        let facts = [
            makeActive(description: "a", confidence: 0.8, domain: "app1"),
            makeActive(description: "b", confidence: 0.9, domain: "app2"),
        ]
        let result = service.selectActiveFacts(domain: "app1", from: facts)
        #expect(result.count == 1)
        #expect(result[0].domain == "app1")
    }
}
