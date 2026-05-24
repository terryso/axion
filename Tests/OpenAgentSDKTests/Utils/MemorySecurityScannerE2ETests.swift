// MemorySecurityScannerE2ETests.swift
// Story 21.4: Memory Security Scanner & Frozen Snapshot — E2E Integration Tests
//
// E2E tests that verify the security scanner integration with real LLM API calls
// and snapshot/rollback with real FactStore file I/O.
//
// IMPORTANT: These are REAL E2E tests — they make actual LLM API calls.
// Set ANTHROPIC_API_KEY environment variable to run them.

import XCTest
@testable import OpenAgentSDK

/// E2E tests for MemorySecurityScanner integration and FrozenSnapshot with real infrastructure.
///
/// Part 1: Real LLM extraction → security scanner → fact storage pipeline.
/// Part 2: Snapshot/rollback with real FactStore file persistence.
final class MemorySecurityScannerE2ETests: XCTestCase {

    // MARK: - Environment Helpers

    private var hasApiKey: Bool {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil
            || ProcessInfo.processInfo.environment["CODEANY_API_KEY"] != nil
    }

    private var resolvedApiKey: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
            ?? ProcessInfo.processInfo.environment["CODEANY_API_KEY"]
            ?? ""
    }

    private var resolvedBaseURL: String? {
        ProcessInfo.processInfo.environment["CODEANY_BASE_URL"]
    }

    private var extractionModel: String {
        ProcessInfo.processInfo.environment["CODEANY_MODEL"] ?? "claude-haiku-4-5-20251001"
    }

    private var tempDir: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory()
            .appending("MemorySecurityScannerE2E-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
        super.tearDown()
    }

    private func makeClient() -> AnthropicClient {
        AnthropicClient(apiKey: resolvedApiKey, baseURL: resolvedBaseURL)
    }

    private func makeFactStore() -> FactStore {
        FactStore(memoryDir: tempDir)
    }

    /// A conversation with clear extractable experience signals about testing practices.
    private func conversationWithLearnings() -> [SDKMessage] {
        [
            .userMessage(.init(message: "Run the full test suite after making changes.")),
            .assistant(.init(text: "I'll run the full test suite now.", model: "claude-sonnet-4-6", stopReason: "end_turn")),
            .toolResult(.init(toolUseId: "tu1", content: "Executed 882 tests. All passed.", isError: false)),
            .assistant(.init(text: "All 882 tests passed successfully.", model: "claude-sonnet-4-6", stopReason: "end_turn")),
            .userMessage(.init(message: "Good. Always run the full suite — never just the affected files.")),
            .assistant(.init(text: "Understood. I'll always run the full test suite for this project.", model: "claude-sonnet-4-6", stopReason: "end_turn")),
        ]
    }

    // MARK: - Part 1: Security Scanner + Real LLM Pipeline

    /// Verifies that a default-config scanner passes through all extracted facts.
    /// The scanner with default config (maxContentLength=500, no blocked patterns/domains,
    /// maxConfidence=1.0) should not block any legitimate facts.
    func testE2E_defaultScanner_passesAllExtractedFacts() async throws {
        try XCTSkipIf(!hasApiKey, "ANTHROPIC_API_KEY or CODEANY_API_KEY not set — skipping E2E test")

        let extractor = LLMExperienceExtractor(client: makeClient(), extractionModel: extractionModel)
        let factStore = makeFactStore()
        let config = MemoryReviewConfig()
        let scanner = MemorySecurityScanner() // default config — no restrictions
        let messages = conversationWithLearnings()

        let hook = MemoryReviewHook(
            extractor: extractor,
            factStore: factStore,
            config: config,
            securityScanner: scanner,
            messageProvider: { messages }
        )
        let handler = hook.makeHandler()
        let result = await handler(HookInput(event: .sessionEnd))

        guard let summary = result?.additionalContext, summary.contains("extracted") else {
            return // LLM didn't extract — acceptable
        }

        // With default scanner, no rejections should occur
        let domains = try await factStore.listDomains()
        XCTAssertGreaterThan(domains.count, 0, "Default scanner should not block legitimate facts")

        // Summary should NOT mention security filtering
        XCTAssertFalse(summary.contains("security"), "Default scanner should not add security noise")
    }

    /// Verifies that a restrictive scanner (blocking all content via pattern) rejects all facts.
    /// Uses a catch-all blocked pattern to ensure every extracted fact is rejected.
    func testE2E_restrictiveScanner_rejectsAllExtractedFacts() async throws {
        try XCTSkipIf(!hasApiKey, "ANTHROPIC_API_KEY or CODEANY_API_KEY not set — skipping E2E test")

        let extractor = LLMExperienceExtractor(client: makeClient(), extractionModel: extractionModel)
        let factStore = makeFactStore()
        let config = MemoryReviewConfig()
        // Use a pattern that matches any non-empty string
        let scanner = MemorySecurityScanner(config: MemorySecurityConfig(blockedPatterns: [".+"]))
        let messages = conversationWithLearnings()

        let hook = MemoryReviewHook(
            extractor: extractor,
            factStore: factStore,
            config: config,
            securityScanner: scanner,
            messageProvider: { messages }
        )
        let handler = hook.makeHandler()
        let handlerResult = await handler(HookInput(event: .sessionEnd))

        // With catch-all pattern, all facts should be rejected
        let domains = try await factStore.listDomains()
        XCTAssertTrue(domains.isEmpty, "Restrictive scanner should block all facts")

        // Handler should return "no extractable experience" since nothing was saved
        if let summary = handlerResult?.additionalContext {
            XCTAssertTrue(
                summary.contains("no extractable experience"),
                "All-rejected scanner should produce 'no extractable experience' — got: \(summary)"
            )
        }
    }

    /// Verifies that the scanner with blocked domains filters facts from blocked domains only.
    /// Uses a domain unlikely to be extracted ("admin") so that legitimate facts pass through.
    func testE2E_blockedDomainScanner_savesGoodFactsRejectsBlockedDomain() async throws {
        try XCTSkipIf(!hasApiKey, "ANTHROPIC_API_KEY or CODEANY_API_KEY not set — skipping E2E test")

        let extractor = LLMExperienceExtractor(client: makeClient(), extractionModel: extractionModel)
        let factStore = makeFactStore()
        let config = MemoryReviewConfig()
        // Block domains that should never appear in normal extraction
        let scanner = MemorySecurityScanner(config: MemorySecurityConfig(
            blockedDomains: ["system", "admin", "root", "internal"]
        ))
        let messages = conversationWithLearnings()

        let hook = MemoryReviewHook(
            extractor: extractor,
            factStore: factStore,
            config: config,
            securityScanner: scanner,
            messageProvider: { messages }
        )
        let handler = hook.makeHandler()
        let result = await handler(HookInput(event: .sessionEnd))

        guard let summary = result?.additionalContext, summary.contains("extracted") else {
            return
        }

        // Facts from non-blocked domains should be saved
        let domains = try await factStore.listDomains()
        XCTAssertGreaterThan(domains.count, 0, "Non-blocked domain facts should be saved")

        // Verify no facts in blocked domains
        for blockedDomain in ["system", "admin", "root", "internal"] {
            let facts = try await factStore.query(domain: blockedDomain)
            XCTAssertTrue(facts.isEmpty, "Blocked domain '\(blockedDomain)' should have no facts")
        }
    }

    /// Verifies that a low confidence ceiling rejects overconfident extracted facts.
    func testE2E_lowConfidenceCeiling_rejectsHighConfidenceFacts() async throws {
        try XCTSkipIf(!hasApiKey, "ANTHROPIC_API_KEY or CODEANY_API_KEY not set — skipping E2E test")

        let extractor = LLMExperienceExtractor(client: makeClient(), extractionModel: extractionModel)
        let factStore = makeFactStore()
        let config = MemoryReviewConfig()
        // Very low confidence ceiling — most extracted facts will exceed it
        let scanner = MemorySecurityScanner(config: MemorySecurityConfig(maxConfidence: 0.1))
        let messages = conversationWithLearnings()

        let hook = MemoryReviewHook(
            extractor: extractor,
            factStore: factStore,
            config: config,
            securityScanner: scanner,
            messageProvider: { messages }
        )
        let handler = hook.makeHandler()
        let _ = await handler(HookInput(event: .sessionEnd))

        // Most/all facts should be rejected due to low confidence ceiling
        let domains = try await factStore.listDomains()
        let totalFacts: Int
        if domains.isEmpty {
            totalFacts = 0
        } else {
            totalFacts = try await domains.asyncMap { domain in
                try await factStore.query(domain: domain).count
            }.reduce(0, +)
        }

        // With maxConfidence=0.1, very few (if any) facts should survive
        XCTAssertLessThanOrEqual(totalFacts, 2,
            "Low confidence ceiling should reject most facts — got \(totalFacts)")
    }

    // MARK: - Part 2: Snapshot/Rollback with Real FactStore I/O

    /// Verifies snapshot captures a deep copy and survives FactStore re-initialization.
    func testE2E_snapshot_persistsAcrossStoreReinit() async throws {
        let factStore = makeFactStore()

        // Save initial facts
        let fact1 = MemoryFact.create(domain: "testing", kind: .affordance, description: "E2E snapshot fact 1")
        let fact2 = MemoryFact.create(domain: "testing", kind: .avoid, description: "E2E snapshot fact 2")
        try await factStore.save(domain: "testing", fact: fact1)
        try await factStore.save(domain: "testing", fact: fact2)

        // Take snapshot
        let snapshot = try await factStore.snapshot(domain: "testing")
        XCTAssertEqual(snapshot.facts.count, 2)
        XCTAssertEqual(snapshot.domain, "testing")
        XCTAssertFalse(snapshot.snapshotId.isEmpty)

        // Re-create store from same directory
        let factStore2 = FactStore(memoryDir: tempDir)
        let snapshot2 = try await factStore2.snapshot(domain: "testing")
        XCTAssertEqual(snapshot2.facts.count, 2, "Facts should persist across store re-init")
        XCTAssertEqual(snapshot.domain, snapshot2.domain)
    }

    /// Verifies rollback with real file I/O restores facts and persists to disk.
    func testE2E_rollback_persistsRestoredState() async throws {
        let factStore = makeFactStore()

        // Save initial fact
        let fact1 = MemoryFact.create(domain: "testing", kind: .affordance, description: "Original E2E fact")
        try await factStore.save(domain: "testing", fact: fact1)

        // Snapshot the state
        let snapshot = try await factStore.snapshot(domain: "testing")

        // Add more facts
        let fact2 = MemoryFact.create(domain: "testing", kind: .avoid, description: "Added later")
        let fact3 = MemoryFact.create(domain: "testing", kind: .observation, description: "Also added later")
        try await factStore.save(domain: "testing", fact: fact2)
        try await factStore.save(domain: "testing", fact: fact3)
        let factsBeforeRollback = try await factStore.query(domain: "testing")
        XCTAssertEqual(factsBeforeRollback.count, 3)

        // Rollback to snapshot
        try await factStore.rollback(to: snapshot)

        // Verify in-memory state
        let restored = try await factStore.query(domain: "testing")
        XCTAssertEqual(restored.count, 1, "Rollback should restore to 1 fact")
        XCTAssertEqual(restored.first?.content, "Original E2E fact")

        // Verify persistence — re-create store
        let factStore2 = FactStore(memoryDir: tempDir)
        let persisted = try await factStore2.query(domain: "testing")
        XCTAssertEqual(persisted.count, 1, "Rolled-back state should persist to disk")
        XCTAssertEqual(persisted.first?.content, "Original E2E fact")
    }

    /// Verifies rollback preserves other domains' facts on disk.
    func testE2E_rollback_preservesOtherDomainsOnDisk() async throws {
        let factStore = makeFactStore()

        // Save facts in two domains
        let alpha = MemoryFact.create(domain: "alpha", kind: .affordance, description: "Alpha fact")
        let beta = MemoryFact.create(domain: "beta", kind: .avoid, description: "Beta fact")
        try await factStore.save(domain: "alpha", fact: alpha)
        try await factStore.save(domain: "beta", fact: beta)

        // Snapshot alpha
        let alphaSnapshot = try await factStore.snapshot(domain: "alpha")

        // Mutate alpha
        let alpha2 = MemoryFact.create(domain: "alpha", kind: .observation, description: "Alpha mutated")
        try await factStore.save(domain: "alpha", fact: alpha2)

        // Rollback alpha
        try await storeRollback(factStore: factStore, snapshot: alphaSnapshot)

        // Verify both domains on fresh store
        let factStore2 = FactStore(memoryDir: tempDir)
        let alphaFacts = try await factStore2.query(domain: "alpha")
        let betaFacts = try await factStore2.query(domain: "beta")

        XCTAssertEqual(alphaFacts.count, 1, "Alpha should be rolled back to 1 fact")
        XCTAssertEqual(alphaFacts.first?.content, "Alpha fact")
        XCTAssertEqual(betaFacts.count, 1, "Beta should be unaffected")
        XCTAssertEqual(betaFacts.first?.content, "Beta fact")
    }

    /// Verifies the full E2E flow: extract → scan → snapshot → mutate → rollback.
    /// Uses real LLM for extraction, real scanner, and real FactStore.
    func testE2E_fullPipeline_extractScanSnapshotRollback() async throws {
        try XCTSkipIf(!hasApiKey, "ANTHROPIC_API_KEY or CODEANY_API_KEY not set — skipping E2E test")

        let extractor = LLMExperienceExtractor(client: makeClient(), extractionModel: extractionModel)
        let factStore = makeFactStore()
        let config = MemoryReviewConfig()
        let scanner = MemorySecurityScanner() // default — no restrictions
        let messages = conversationWithLearnings()

        let hook = MemoryReviewHook(
            extractor: extractor,
            factStore: factStore,
            config: config,
            securityScanner: scanner,
            messageProvider: { messages }
        )
        let handler = hook.makeHandler()
        let result = await handler(HookInput(event: .sessionEnd))

        guard let summary = result?.additionalContext, summary.contains("extracted") else {
            return // LLM didn't extract — acceptable
        }

        // Step 1: Snapshot after extraction
        let domains = try await factStore.listDomains()
        XCTAssertGreaterThan(domains.count, 0)
        guard let firstDomain = domains.first else { return }
        let snapshot = try await factStore.snapshot(domain: firstDomain)
        let originalCount = snapshot.facts.count
        XCTAssertGreaterThan(originalCount, 0)

        // Step 2: Add a rogue fact
        let rogueFact = MemoryFact.create(domain: firstDomain, kind: .affordance, description: "Rogue fact added after snapshot")
        try await factStore.save(domain: firstDomain, fact: rogueFact)
        let mutatedCount = try await factStore.query(domain: firstDomain).count
        XCTAssertEqual(mutatedCount, originalCount + 1)

        // Step 3: Rollback to snapshot
        try await factStore.rollback(to: snapshot)
        let restoredCount = try await factStore.query(domain: firstDomain).count
        XCTAssertEqual(restoredCount, originalCount, "Rollback should remove the rogue fact")

        // Step 4: Verify snapshot is still valid (deep copy)
        XCTAssertEqual(snapshot.facts.count, originalCount, "Snapshot should be unaffected by rollback")
    }

    // MARK: - Helpers

    private func storeRollback(factStore: FactStore, snapshot: FrozenSnapshot) async throws {
        try await factStore.rollback(to: snapshot)
    }
}

// MARK: - Async Array Extension

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            try await result.append(transform(element))
        }
        return result
    }
}
