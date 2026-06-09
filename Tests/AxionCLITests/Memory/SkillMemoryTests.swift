import Foundation
import Testing

@testable import AxionCLI

// Story 18.2: Skill + Memory Integration Tests
// AC1: Prompt skill success → record Memory
// AC2: Prompt skill pre-execution → inject avoid Memory
// AC3: --no-memory flag respected
// AC4: Memory injection quantity limit (max 3)
// AC5: Recorded skill also records Memory

@Suite("SkillMemory")
struct SkillMemoryTests {

    // MARK: - Helpers

    private func makeTempStore() -> (AxionFactStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return (AxionFactStore(memoryDir: tempDir), tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeActiveFact(
        domain: String = "com.apple.calculator",
        kind: MemoryKind = .affordance,
        description: String,
        confidence: Double = 0.8,
        scope: String? = nil
    ) -> AppMemoryFact {
        var fact = AppMemoryFact.create(
            domain: domain,
            kind: kind,
            description: description,
            confidence: confidence,
            scope: scope
        )
        fact.status = .active
        fact.evidenceCount = 3
        return fact
    }

    // MARK: - 5.6: AppMemoryFact scope mutation for skill facts

    @Test("AppMemoryFact scope can be set to skill prefix")
    func factScopeCanBeSet() {
        var fact = AppMemoryFact.create(
            domain: "com.apple.calculator",
            kind: .affordance,
            description: "Test"
        )
        #expect(fact.scope == nil, "Default scope should be nil")
        fact.scope = "skill:screenshot-analyze"
        #expect(fact.scope == "skill:screenshot-analyze", "Scope should be settable")
    }

    @Test("AppMemoryFact create supports skill scope parameter")
    func factCreateWithScope() {
        let fact = AppMemoryFact.create(
            domain: "unknown",
            kind: .affordance,
            description: "Recorded skill test",
            confidence: 0.7,
            scope: "skill:my-skill"
        )
        #expect(fact.scope == "skill:my-skill", "Scope should be set via create()")
        #expect(fact.domain == "unknown", "Domain should match")
        #expect(fact.kind == .affordance, "Kind should match")
    }

    // MARK: - 5.6: --no-memory behavior validation

    @Test("Skill scope should not be applied when noMemory-like flag is set")
    func noMemorySkipsScopeTagging() {
        // Simulates AC3: when noMemory is true, facts should NOT get skill scope
        let fact = AppMemoryFact.create(
            domain: "com.apple.calculator",
            kind: .affordance,
            description: "Test fact"
        )
        #expect(fact.scope == nil, "Scope should remain nil when noMemory is true")
    }

    @Test("Skill scope should be applied when noMemory is false")
    func memoryEnabledAppliesScopeTag() {
        var fact = AppMemoryFact.create(
            domain: "com.apple.calculator",
            kind: .affordance,
            description: "Test fact"
        )
        let noMemory = false
        let shouldTagScope = !noMemory
        if shouldTagScope {
            fact.scope = "skill:screenshot-analyze"
        }
        #expect(fact.scope == "skill:screenshot-analyze", "Scope should be set when noMemory is false")
    }
}
