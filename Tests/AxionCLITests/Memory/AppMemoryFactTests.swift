import Foundation
import Testing

@testable import AxionCLI

// Story 12.1 AC1: AppMemoryFact model, enums, normalizeFact, factId

@Suite("AppMemoryFact")
struct AppMemoryFactTests {

    // MARK: - Enum Existence

    @Test("MemoryFactStatus has expected cases")
    func memoryFactStatusCases() {
        let candidate = MemoryFactStatus(rawValue: "candidate")
        let active = MemoryFactStatus(rawValue: "active")
        let retired = MemoryFactStatus(rawValue: "retired")
        #expect(candidate != nil)
        #expect(active != nil)
        #expect(retired != nil)
    }

    @Test("MemoryFactSource has expected cases")
    func memoryFactSourceCases() {
        let local = MemoryFactSource(rawValue: "local")
        let imported = MemoryFactSource(rawValue: "imported")
        #expect(local != nil)
        #expect(imported != nil)
    }

    @Test("MemoryKind has expected cases")
    func memoryKindCases() {
        let affordance = MemoryKind(rawValue: "affordance")
        let avoid = MemoryKind(rawValue: "avoid")
        let observation = MemoryKind(rawValue: "observation")
        #expect(affordance != nil)
        #expect(avoid != nil)
        #expect(observation != nil)
    }

    // MARK: - Codable Round-trip

    @Test("AppMemoryFact Codable round-trip")
    func codableRoundTrip() throws {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)  // Fixed, ISO8601-safe
        let fact = AppMemoryFact(
            id: "test-id",
            domain: "com.apple.calculator",
            kind: .observation,
            status: .candidate,
            confidence: 0.7,
            evidenceCount: 1,
            source: .local,
            scope: "main-window",
            cause: nil,
            description: "Calculator supports keyboard input",
            updatedAt: fixedDate,
            evidence: ["run-1"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(fact)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppMemoryFact.self, from: data)

        #expect(decoded == fact)
    }

    @Test("AppMemoryFact Codable round-trip with all optionals nil")
    func codableRoundTripNilOptionals() throws {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let fact = AppMemoryFact(
            id: "test-id-2",
            domain: "unknown",
            kind: .avoid,
            status: .active,
            confidence: 0.9,
            evidenceCount: 3,
            source: .imported,
            scope: nil,
            cause: nil,
            description: "Simple fact",
            updatedAt: fixedDate,
            evidence: []
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(fact)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppMemoryFact.self, from: data)

        #expect(decoded == fact)
        #expect(decoded.scope == nil)
        #expect(decoded.cause == nil)
    }

    // MARK: - Equatable + Sendable

    @Test("AppMemoryFact Equatable works")
    func equatableWorks() {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let fact1 = AppMemoryFact(
            id: "obs-123", domain: "test", kind: .observation, status: .candidate,
            confidence: 0.7, evidenceCount: 1, source: .local,
            scope: nil, cause: nil, description: "same description",
            updatedAt: fixedDate, evidence: []
        )
        let fact2 = AppMemoryFact(
            id: "obs-123", domain: "test", kind: .observation, status: .candidate,
            confidence: 0.7, evidenceCount: 1, source: .local,
            scope: nil, cause: nil, description: "same description",
            updatedAt: fixedDate, evidence: []
        )
        #expect(fact1 == fact2)
    }

    @Test("AppMemoryFact Equatable detects differences")
    func equatableDetectsDifferences() {
        let fact1 = AppMemoryFact.create(
            domain: "test",
            kind: .observation,
            description: "description A"
        )
        let fact2 = AppMemoryFact.create(
            domain: "test",
            kind: .avoid,
            description: "description B"
        )
        #expect(fact1 != fact2)
    }

    // MARK: - Factory Method

    @Test("create() sets defaults correctly")
    func createSetsDefaults() {
        let fact = AppMemoryFact.create(
            domain: "com.apple.calculator",
            kind: .observation,
            description: "Test fact"
        )

        #expect(fact.status == .candidate)
        #expect(fact.evidenceCount == 1)
        #expect(fact.source == .local)
        #expect(fact.confidence >= 0.0 && fact.confidence <= 1.0)
        #expect(fact.evidence == [])
    }

    @Test("create() with custom confidence")
    func createCustomConfidence() {
        let fact = AppMemoryFact.create(
            domain: "test",
            kind: .avoid,
            description: "Failed action",
            confidence: 0.5,
            cause: "error"
        )
        #expect(fact.confidence == 0.5)
        #expect(fact.cause == "error")
        #expect(fact.kind == .avoid)
    }

    // MARK: - normalizeFact

    @Test("normalizeFact clamps confidence to [0, 1]")
    func normalizeFactClampsConfidence() {
        let over = AppMemoryFact(
            id: "t", domain: "d", kind: .observation, status: .candidate,
            confidence: 1.5, evidenceCount: 1, source: .local,
            scope: nil, cause: nil, description: "desc",
            updatedAt: Date(), evidence: []
        )
        let normalized = AppMemoryFact.normalizeFact(over)
        #expect(normalized.confidence == 1.0)

        let under = AppMemoryFact(
            id: "t", domain: "d", kind: .observation, status: .candidate,
            confidence: -0.3, evidenceCount: 1, source: .local,
            scope: nil, cause: nil, description: "desc",
            updatedAt: Date(), evidence: []
        )
        let normalized2 = AppMemoryFact.normalizeFact(under)
        #expect(normalized2.confidence == 0.0)
    }

    @Test("normalizeFact clamps evidenceCount >= 0")
    func normalizeFactClampsEvidenceCount() {
        let negative = AppMemoryFact(
            id: "t", domain: "d", kind: .observation, status: .candidate,
            confidence: 0.5, evidenceCount: -5, source: .local,
            scope: nil, cause: nil, description: "desc",
            updatedAt: Date(), evidence: []
        )
        let normalized = AppMemoryFact.normalizeFact(negative)
        #expect(normalized.evidenceCount == 0)
    }

    @Test("normalizeFact preserves valid values")
    func normalizeFactPreservesValid() {
        let valid = AppMemoryFact(
            id: "t", domain: "d", kind: .observation, status: .active,
            confidence: 0.75, evidenceCount: 3, source: .local,
            scope: "scope", cause: nil, description: "desc",
            updatedAt: Date(), evidence: ["e1"]
        )
        let normalized = AppMemoryFact.normalizeFact(valid)
        #expect(normalized.confidence == 0.75)
        #expect(normalized.evidenceCount == 3)
        #expect(normalized.status == .active)
    }

    // MARK: - factId Determinism

    @Test("factId is deterministic for same kind + description")
    func factIdDeterministic() {
        let id1 = AppMemoryFact.factId(kind: .observation, description: "Calculator supports keyboard input")
        let id2 = AppMemoryFact.factId(kind: .observation, description: "Calculator supports keyboard input")
        #expect(id1 == id2)
    }

    @Test("factId differs for different descriptions")
    func factIdDiffersForDifferentDescriptions() {
        let id1 = AppMemoryFact.factId(kind: .observation, description: "Action A")
        let id2 = AppMemoryFact.factId(kind: .observation, description: "Action B")
        #expect(id1 != id2)
    }

    @Test("factId includes kind prefix")
    func factIdIncludesKindPrefix() {
        let id = AppMemoryFact.factId(kind: .avoid, description: "test")
        #expect(id.hasPrefix("avoid-"))
    }

    @Test("factId is case-insensitive")
    func factIdCaseInsensitive() {
        let id1 = AppMemoryFact.factId(kind: .observation, description: "Calculator Test")
        let id2 = AppMemoryFact.factId(kind: .observation, description: "calculator test")
        #expect(id1 == id2)
    }

    @Test("factId uses deterministic hash (not Swift hashValue)")
    func factIdDeterministicHash() {
        let id = AppMemoryFact.factId(kind: .avoid, description: "test input")
        #expect(id.hasPrefix("avoid-"))
        let hashPart = id.dropFirst("avoid-".count)
        #expect(hashPart.allSatisfy { $0.isNumber })
    }
}
