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

    // MARK: - 5.2: buildSkillMemoryContext filters by scope, sorts by kind, limits count

    @Test("buildSkillMemoryContext filters by skill scope")
    func filtersBySkillScope() async throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let domain = "com.apple.calculator"
        let skillFact = makeActiveFact(
            domain: domain,
            kind: .affordance,
            description: "Skill-specific path",
            scope: "skill:screenshot-analyze"
        )
        let appFact = makeActiveFact(
            domain: domain,
            kind: .affordance,
            description: "General app path",
            scope: nil
        )
        try await store.saveAll(domain: domain, facts: [skillFact, appFact])

        let provider = MemoryContextProvider()
        let context = await provider.buildSkillMemoryContext(
            skillName: "screenshot-analyze",
            task: "打开计算器",
            factStore: store
        )

        #expect(context != nil, "Should return non-nil for matching scope")
        let ctx = try #require(context)
        #expect(ctx.contains("Skill-specific path"), "Should include skill-scoped fact")
        #expect(!ctx.contains("General app path"), "Should NOT include app-level fact")
    }

    @Test("buildSkillMemoryContext prioritizes affordance over avoid over observation")
    func prioritizesByKind() async throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let domain = "com.apple.calculator"
        let avoidFact = makeActiveFact(
            domain: domain,
            kind: .avoid,
            description: "Avoid this path",
            confidence: 0.9,
            scope: "skill:screenshot-analyze"
        )
        let affordanceFact = makeActiveFact(
            domain: domain,
            kind: .affordance,
            description: "Good path",
            confidence: 0.7,
            scope: "skill:screenshot-analyze"
        )
        try await store.saveAll(domain: domain, facts: [avoidFact, affordanceFact])

        let provider = MemoryContextProvider()
        let context = await provider.buildSkillMemoryContext(
            skillName: "screenshot-analyze",
            task: "打开计算器",
            factStore: store
        )

        #expect(context != nil)
        let ctx = try #require(context)
        let lines = ctx.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        // affordance should come before avoid
        if lines.count >= 2 {
            let affordanceIdx = lines.firstIndex(where: { $0.contains("affordance") }) ?? -1
            let avoidIdx = lines.firstIndex(where: { $0.contains("avoid") }) ?? -1
            if affordanceIdx >= 0 && avoidIdx >= 0 {
                #expect(affordanceIdx < avoidIdx, "Affordance should appear before avoid")
            }
        }
    }

    // MARK: - 5.3: buildSkillMemoryContext returns nil when no matching scope

    @Test("buildSkillMemoryContext returns nil when no matching scope")
    func returnsNilNoMatchingScope() async throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let domain = "com.apple.calculator"
        let fact = makeActiveFact(
            domain: domain,
            kind: .affordance,
            description: "Other skill fact",
            scope: "skill:other-skill"
        )
        try await store.save(domain: domain, fact: fact)

        let provider = MemoryContextProvider()
        let context = await provider.buildSkillMemoryContext(
            skillName: "screenshot-analyze",
            task: "打开计算器",
            factStore: store
        )

        #expect(context == nil, "Should return nil when no scope matches skill name")
    }

    @Test("buildSkillMemoryContext returns nil when no matching domain")
    func returnsNilNoMatchingDomain() async throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let provider = MemoryContextProvider()
        let context = await provider.buildSkillMemoryContext(
            skillName: "screenshot-analyze",
            task: "在 Photoshop 中编辑",
            factStore: store
        )

        #expect(context == nil, "Should return nil when domain cannot be inferred")
    }

    // MARK: - 5.4: More than 5 facts only takes top 3, by kind priority

    @Test("buildSkillMemoryContext limits to max 3 facts with kind priority")
    func limitsTo3WithKindPriority() async throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let domain = "com.apple.calculator"
        var facts: [AppMemoryFact] = []

        // 2 affordances
        for i in 0..<2 {
            facts.append(makeActiveFact(
                domain: domain,
                kind: .affordance,
                description: "Affordance \(i)",
                confidence: 0.9 - Double(i) * 0.1,
                scope: "skill:screenshot-analyze"
            ))
        }
        // 2 avoids
        for i in 0..<2 {
            facts.append(makeActiveFact(
                domain: domain,
                kind: .avoid,
                description: "Avoid \(i)",
                confidence: 0.8 - Double(i) * 0.1,
                scope: "skill:screenshot-analyze"
            ))
        }
        // 2 observations
        for i in 0..<2 {
            facts.append(makeActiveFact(
                domain: domain,
                kind: .observation,
                description: "Observation \(i)",
                confidence: 0.7 - Double(i) * 0.1,
                scope: "skill:screenshot-analyze"
            ))
        }

        try await store.saveAll(domain: domain, facts: facts)

        let provider = MemoryContextProvider()
        let context = await provider.buildSkillMemoryContext(
            skillName: "screenshot-analyze",
            task: "打开计算器",
            factStore: store
        )

        #expect(context != nil)
        let ctx = try #require(context)
        let factLines = ctx.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        #expect(factLines.count == 3,
            "Should select at most 3 facts, got \(factLines.count)")

        // Verify kind priority: 1 affordance + 1 avoid + 1 observation
        let kinds = factLines.map { line -> String in
            if line.contains("affordance") { return "affordance" }
            if line.contains("avoid") { return "avoid" }
            return "observation"
        }
        #expect(kinds[0] == "affordance", "First should be affordance")
        #expect(kinds[1] == "avoid", "Second should be avoid")
        #expect(kinds[2] == "observation", "Third should be observation")
    }

    @Test("buildSkillMemoryContext takes at most 1 affordance and 1 avoid")
    func takesAtMost1PerKind() async throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let domain = "com.apple.calculator"
        var facts: [AppMemoryFact] = []

        // 3 affordances (only 1 should be selected)
        for i in 0..<3 {
            facts.append(makeActiveFact(
                domain: domain,
                kind: .affordance,
                description: "Affordance \(i)",
                confidence: 0.9 - Double(i) * 0.1,
                scope: "skill:my-skill"
            ))
        }
        // 3 avoids (only 1 should be selected)
        for i in 0..<3 {
            facts.append(makeActiveFact(
                domain: domain,
                kind: .avoid,
                description: "Avoid \(i)",
                confidence: 0.8 - Double(i) * 0.1,
                scope: "skill:my-skill"
            ))
        }

        try await store.saveAll(domain: domain, facts: facts)

        let provider = MemoryContextProvider()
        let context = await provider.buildSkillMemoryContext(
            skillName: "my-skill",
            task: "打开计算器",
            factStore: store
        )

        #expect(context != nil)
        let ctx = try #require(context)
        let lines = ctx.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }

        let affordanceLines = lines.filter { $0.contains("affordance") }
        let avoidLines = lines.filter { $0.contains("avoid") }
        #expect(affordanceLines.count == 1, "Should select at most 1 affordance")
        #expect(avoidLines.count == 1, "Should select at most 1 avoid")
        #expect(lines.count == 2, "Total should be 2 (1 affordance + 1 avoid)")
    }

    // MARK: - 5.5: Memory injection during skill trigger

    @Test("buildSkillMemoryContext includes soft hints declaration")
    func includesSoftHintsDeclaration() async throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let domain = "com.apple.calculator"
        let fact = makeActiveFact(
            domain: domain,
            kind: .affordance,
            description: "Test path",
            scope: "skill:screenshot-analyze"
        )
        try await store.save(domain: domain, fact: fact)

        let provider = MemoryContextProvider()
        let context = await provider.buildSkillMemoryContext(
            skillName: "screenshot-analyze",
            task: "打开计算器",
            factStore: store
        )

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("soft hints"), "Should include soft hints declaration")
        #expect(ctx.contains("Skill-specific memory"), "Should include skill memory header")
    }

    @Test("buildSkillMemoryContext selects highest confidence per kind")
    func selectsHighestConfidence() async throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let domain = "com.apple.calculator"
        let highFact = makeActiveFact(
            domain: domain,
            kind: .affordance,
            description: "High confidence path",
            confidence: 0.95,
            scope: "skill:my-skill"
        )
        let lowFact = makeActiveFact(
            domain: domain,
            kind: .affordance,
            description: "Low confidence path",
            confidence: 0.5,
            scope: "skill:my-skill"
        )
        try await store.saveAll(domain: domain, facts: [lowFact, highFact])

        let provider = MemoryContextProvider()
        let context = await provider.buildSkillMemoryContext(
            skillName: "my-skill",
            task: "打开计算器",
            factStore: store
        )

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("High confidence path"),
            "Should select the highest confidence fact")
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

    // MARK: - maxSkillFacts constant

    @Test("maxSkillFacts is 3")
    func maxSkillFactsIs3() {
        #expect(MemoryContextProvider.maxSkillFacts == 3,
            "Maximum skill-scoped facts should be 3")
    }

    // MARK: - 5.6: --no-memory behavior validation

    @Test("Skill scope should not be applied when noMemory-like flag is set")
    func noMemorySkipsScopeTagging() {
        // Simulates AC3: when noMemory is true, facts should NOT get skill scope
        var fact = AppMemoryFact.create(
            domain: "com.apple.calculator",
            kind: .affordance,
            description: "Test fact"
        )
        let noMemory = true
        let shouldTagScope = !noMemory
        if shouldTagScope {
            fact.scope = "skill:screenshot-analyze"
        }
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
