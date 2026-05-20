import XCTest
@testable import OpenAgentSDK

/// Integration tests that verify the full memory lifecycle across multiple components.
final class MemoryLifecycleIntegrationTests: XCTestCase {

    private var tempDir: String!
    private var store: FactStore!
    private let lifecycle = MemoryLifecycleService()
    private let contextProvider = MemoryContextProvider()
    private let exportService = MemoryBundleExportService()
    private let importService = MemoryBundleImportService()

    override func setUp() {
        super.setUp()
        tempDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("memory-lifecycle-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true
        )
        store = FactStore(memoryDir: tempDir)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Full Lifecycle: create → save → merge → promote → context → export → import

    func testFullLifecycleCandidateToActiveToContextToExport() async throws {
        // 1. Create a candidate fact
        let fact = MemoryFact.create(
            domain: "navigation",
            kind: .affordance,
            description: "Use tab-based navigation for multi-section apps",
            confidence: 0.7
        )
        XCTAssertEqual(fact.status, .candidate)
        XCTAssertEqual(fact.evidenceCount, 1)

        // 2. Save to store
        try await store.save(domain: "navigation", fact: fact)
        var results = try await store.query(domain: "navigation")
        XCTAssertEqual(results.count, 1)

        // 3. Simulate re-observation → merge → auto-promotion (happens inside addFact)
        let reobserved = MemoryFact.create(
            domain: "navigation",
            kind: .affordance,
            description: "Use tab-based navigation for multi-section apps",
            confidence: 0.6
        )
        // Same id means same description
        XCTAssertEqual(reobserved.id, fact.id)

        let merged = lifecycle.addFact(reobserved, mergingWith: results)

        // addFact calls mergeFact which calls maybePromote internally:
        // evidenceCount = 2, confidence = max(0.7, 0.6) = 0.7 >= 0.65 → auto-promoted
        XCTAssertEqual(merged.status, .active)
        XCTAssertEqual(merged.confidence, 0.8, accuracy: 0.001) // 0.7 + 0.1 boost

        // Save promoted fact
        try await store.save(domain: "navigation", fact: merged)
        results = try await store.query(domain: "navigation")
        XCTAssertEqual(results.first?.status, .active)

        // 4. Build context
        let context = try XCTUnwrap(contextProvider.buildContext(domain: "navigation", facts: results))
        XCTAssertTrue(context.contains("Recommended Paths"))
        XCTAssertTrue(context.contains("soft hints, not hard rules"))
        XCTAssertTrue(context.contains("tab-based navigation"))

        // 5. Export bundle
        let bundle = try await exportService.exportAll(store: store)
        XCTAssertEqual(bundle.memories.count, 1)
        XCTAssertEqual(bundle.memories.first?.facts.count, 1)

        // 6. Write and reimport into a fresh store
        let bundlePath = (tempDir as NSString).appendingPathComponent("export.json")
        try exportService.writeBundle(bundle, to: URL(fileURLWithPath: bundlePath))

        let store2Dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("memory-lifecycle-import-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: store2Dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: store2Dir) }

        let store2 = FactStore(memoryDir: store2Dir)
        let importResult = try await importService.importBundle(from: URL(fileURLWithPath: bundlePath), store: store2)

        XCTAssertEqual(importResult.factsImported, 1)
        XCTAssertEqual(importResult.domainsProcessed, 1)

        // 7. Verify downgrade: imported fact is candidate, confidence capped at 0.55
        let imported = try await store2.query(domain: "navigation")
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.status, .candidate)
        XCTAssertEqual(imported.first?.confidence, 0.55)
        XCTAssertEqual(imported.first?.source, .imported)
    }

    // MARK: - Lifecycle: demote stale facts → reactivate

    func testDemotionAndReactivationCycle() async throws {
        // Create an active fact
        let fact = MemoryFact(
            id: "stale-1", domain: "test", content: "stale fact",
            status: .active, confidence: 0.9, evidenceCount: 3,
            source: .observation, kind: .observation,
            createdAt: Date().addingTimeInterval(-4_000_000),
            lastVerifiedAt: Date().addingTimeInterval(-4_000_000)
        )
        try await store.save(domain: "test", fact: fact)

        // Demote stale facts
        let allFacts = try await store.query(domain: "test")
        let demoted = lifecycle.demoteRetired(facts: allFacts, lastVerifiedBefore: Date())
        XCTAssertEqual(demoted.count, 1)
        XCTAssertEqual(demoted.first?.status, .retired)

        // Save demoted fact
        try await store.save(domain: "test", fact: try XCTUnwrap(demoted.first))

        // Reactivate by re-observation
        let reobserved = try await store.query(domain: "test")
        let reactivated = lifecycle.reactivateRetired(fact: try XCTUnwrap(reobserved.first))
        XCTAssertEqual(reactivated.status, .candidate)
        XCTAssertEqual(reactivated.evidenceCount, 1)

        // Save reactivated
        try await store.save(domain: "test", fact: reactivated)
        let final = try await store.query(domain: "test")
        XCTAssertEqual(final.first?.status, .candidate)
    }

    // MARK: - Export → Import round-trip preserves data integrity

    func testExportImportRoundTrip() async throws {
        // Seed store with multiple domains and kinds
        let facts: [MemoryFact] = [
            MemoryFact.create(domain: "coding", kind: .affordance, description: "Use Swift Concurrency", confidence: 0.8),
            MemoryFact.create(domain: "coding", kind: .avoid, description: "Avoid force unwraps", confidence: 0.9),
            MemoryFact.create(domain: "testing", kind: .observation, description: "Unit tests run in < 5s", confidence: 0.7),
        ]
        try await store.saveAll(domain: "coding", facts: [facts[0], facts[1]])
        try await store.save(domain: "testing", fact: facts[2])

        // Export
        let bundle = try await exportService.exportAll(store: store)
        XCTAssertEqual(bundle.memories.count, 2)

        // Import into fresh store
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(bundle)

        let store2Dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("memory-roundtrip-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: store2Dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: store2Dir) }

        let store2 = FactStore(memoryDir: store2Dir)
        let result = try await importService.importBundle(from: data, store: store2)

        XCTAssertEqual(result.factsImported, 3)
        XCTAssertEqual(result.domainsProcessed, 2)

        // All imported facts are downgraded
        let codingFacts = try await store2.query(domain: "coding")
        let testingFacts = try await store2.query(domain: "testing")

        XCTAssertEqual(codingFacts.count, 2)
        XCTAssertEqual(testingFacts.count, 1)

        for fact in codingFacts + testingFacts {
            XCTAssertEqual(fact.status, .candidate)
            XCTAssertLessThanOrEqual(fact.confidence, 0.55)
            XCTAssertEqual(fact.source, .imported)
        }
    }

    // MARK: - FactStore persistence survives re-initialization

    func testFactStorePersistsAcrossReinitialization() async throws {
        let fact = MemoryFact.create(domain: "persist", kind: .affordance, description: "persists to disk")
        try await store.save(domain: "persist", fact: fact)

        // Re-create store pointing at same dir
        let store2 = FactStore(memoryDir: tempDir)
        let results = try await store2.query(domain: "persist")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, fact.id)
        XCTAssertEqual(results.first?.content, "persists to disk")
    }

    // MARK: - Context provider with all three kinds

    func testContextProviderWithAllKinds() async throws {
        let facts: [MemoryFact] = [
            MemoryFact(id: "1", domain: "d", content: "aff1", status: .active, confidence: 0.9, evidenceCount: 2, source: .observation, kind: .affordance, createdAt: Date(), lastVerifiedAt: Date()),
            MemoryFact(id: "2", domain: "d", content: "avoid1", status: .active, confidence: 0.8, evidenceCount: 2, source: .observation, kind: .avoid, createdAt: Date(), lastVerifiedAt: Date()),
            MemoryFact(id: "3", domain: "d", content: "obs1", status: .active, confidence: 0.7, evidenceCount: 2, source: .observation, kind: .observation, createdAt: Date(), lastVerifiedAt: Date()),
            MemoryFact(id: "4", domain: "d", content: "candidate-ignored", status: .candidate, confidence: 0.99, evidenceCount: 5, source: .observation, kind: .affordance, createdAt: Date(), lastVerifiedAt: Date()),
        ]

        let context = contextProvider.buildContext(domain: "d", facts: facts)
        XCTAssertNotNil(context)
        XCTAssertTrue(context!.contains("Recommended Paths"))
        XCTAssertTrue(context!.contains("Cautions"))
        XCTAssertTrue(context!.contains("Environment Notes"))
        XCTAssertFalse(context!.contains("candidate-ignored"))
    }

    // MARK: - selectActiveFacts integrates with store and lifecycle

    func testSelectActiveFactsFromStoreAfterPromotion() async throws {
        // Create and save a candidate
        let fact = MemoryFact(
            id: "promo-1", domain: "selection", content: "promote me",
            status: .candidate, confidence: 0.7, evidenceCount: 1,
            source: .observation, kind: .affordance,
            createdAt: Date(), lastVerifiedAt: Date()
        )
        try await store.save(domain: "selection", fact: fact)

        // Simulate merge that pushes evidence to 2 → promotion
        let reobs = MemoryFact(
            id: "promo-1", domain: "selection", content: "promote me",
            status: .candidate, confidence: 0.7, evidenceCount: 1,
            source: .observation, kind: .affordance,
            createdAt: Date(), lastVerifiedAt: Date()
        )
        let existing = try await store.query(domain: "selection")
        let merged = lifecycle.addFact(reobs, mergingWith: existing)

        // Should auto-promote since evidenceCount=2, confidence=0.7 >= 0.65
        XCTAssertEqual(merged.status, .active)

        try await store.save(domain: "selection", fact: merged)

        // Now selectActiveFacts should find it
        let allFacts = try await store.query(domain: "selection")
        let active = lifecycle.selectActiveFacts(domain: "selection", from: allFacts)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.status, .active)
    }
}
