import Foundation
import Testing

@testable import AxionCLI

@Suite("MemoryListCommand")
struct MemoryListCommandTests {

    // MARK: - P0: Type Existence

    @Test("MemoryListCommand type exists")
    func memoryListCommandTypeExists() {
        let _ = MemoryListCommand.self
    }

    // MARK: - Story 12.2 AC6: Status icon and kind label mappings

    @Test("status icon for active is checkmark")
    func statusIconActive() {
        #expect(MemoryListCommand.statusIcons[.active] == "✓")
    }

    @Test("status icon for candidate is circle")
    func statusIconCandidate() {
        #expect(MemoryListCommand.statusIcons[.candidate] == "○")
    }

    @Test("status icon for retired is cross")
    func statusIconRetired() {
        #expect(MemoryListCommand.statusIcons[.retired] == "✗")
    }

    @Test("kind label for affordance is 推荐")
    func kindLabelAffordance() {
        #expect(MemoryListCommand.kindLabels[.affordance] == "推荐")
    }

    @Test("kind label for avoid is 警告")
    func kindLabelAvoid() {
        #expect(MemoryListCommand.kindLabels[.avoid] == "警告")
    }

    @Test("kind label for observation is 备注")
    func kindLabelObservation() {
        #expect(MemoryListCommand.kindLabels[.observation] == "备注")
    }

    // MARK: - P0 AC5: Display app list with entry counts and last-used time

    @Test("list output contains app memory header")
    func listOutputContainsAppMemoryHeader() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = AxionFactStore(memoryDir: tempDir)

        let facts: [AppMemoryFact] = [
            AppMemoryFact.create(domain: "com.apple.calculator", kind: .observation, description: "Test run", evidence: ["r1"]),
        ]
        for fact in facts { try await store.save(domain: "com.apple.calculator", fact: fact) }

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("App Memory") || output.contains("Memory"),
            "Output should contain a header line for memory listing")
    }

    @Test("list output shows domain with facts")
    func listOutputShowsDomainFacts() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = AxionFactStore(memoryDir: tempDir)
        let domain = "com.apple.calculator"

        var facts: [AppMemoryFact] = []
        for i in 0..<3 {
            var fact = AppMemoryFact.create(
                domain: domain,
                kind: .observation,
                description: "Run \(i)",
                evidence: ["r\(i)"]
            )
            fact.status = .active
            fact.evidenceCount = 3
            facts.append(fact)
        }
        for fact in facts { try await store.save(domain: domain, fact: fact) }

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains(domain), "Output should show the domain name")
        #expect(output.contains("3 facts"), "Output should show fact count for the domain")
    }

    @Test("list output multiple domains shows all")
    func listOutputMultipleDomainsShowsAll() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = AxionFactStore(memoryDir: tempDir)

        var calcFact = AppMemoryFact.create(domain: "com.apple.calculator", kind: .affordance, description: "Calculator run", evidence: ["r1"])
        calcFact.status = .active
        calcFact.evidenceCount = 3

        var finderFact = AppMemoryFact.create(domain: "com.apple.finder", kind: .observation, description: "Finder run", evidence: ["r2"])
        finderFact.status = .active
        finderFact.evidenceCount = 3

        try await store.save(domain: "com.apple.calculator", fact: calcFact)
        try await store.save(domain: "com.apple.finder", fact: finderFact)

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("com.apple.calculator"), "Output should include Calculator domain")
        #expect(output.contains("com.apple.finder"), "Output should include Finder domain")
        #expect(output.contains("Total"), "Output should show total summary")
    }

    // MARK: - P0 AC5: Empty Memory output

    @Test("list output no memory shows empty message")
    func listOutputNoMemoryShowsEmptyMessage() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("No App Memory found") || output.contains("0 apps") || output.contains("none"),
            "Output should indicate no memory data exists")
    }

    @Test("list output non-existent directory shows empty message")
    func listOutputNonExistentDirectoryShowsEmptyMessage() async {
        let tempDir = "/tmp/axion-test-nonexistent-\(UUID().uuidString)"

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(!output.isEmpty, "Should return a non-empty string even for non-existent directory")
    }

    // MARK: - Story 12.2 AC6: Status icon and kind display in output

    @Test("list output displays facts with status icon and kind label")
    func listOutputDisplaysIconAndKind() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = AxionFactStore(memoryDir: tempDir)
        let domain = "com.apple.calculator"

        var fact = AppMemoryFact.create(
            domain: domain,
            kind: .affordance,
            description: "Use hotkey to navigate",
            confidence: 0.82,
            evidence: ["r1"]
        )
        fact.status = .active
        fact.evidenceCount = 3
        try await store.save(domain: domain, fact: fact)

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("✓"), "Should display active icon ✓")
        #expect(output.contains("推荐"), "Should display affordance kind label '推荐'")
        #expect(output.contains("confidence:0.82"), "Should display confidence value")
        #expect(output.contains("evidence:3"), "Should display evidence count")
    }

    @Test("list output displays multiple kinds with correct labels")
    func listOutputDisplaysMultipleKinds() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = AxionFactStore(memoryDir: tempDir)
        let domain = "com.apple.finder"

        var affordance = AppMemoryFact.create(
            domain: domain,
            kind: .affordance,
            description: "Cmd+Shift+G for go to folder",
            confidence: 0.72,
            evidence: ["r1"]
        )
        affordance.status = .active
        affordance.evidenceCount = 2

        var avoid = AppMemoryFact.create(
            domain: domain,
            kind: .avoid,
            description: "Avoid AX click on sidebar",
            confidence: 0.55,
            evidence: ["r2"]
        )
        avoid.status = .candidate
        avoid.evidenceCount = 1

        var observation = AppMemoryFact.create(
            domain: domain,
            kind: .observation,
            description: "Window title is folder name",
            confidence: 0.8,
            evidence: ["r3"]
        )
        observation.status = .retired
        observation.evidenceCount = 4

        for fact in [affordance, avoid, observation] { try await store.save(domain: domain, fact: fact) }

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("✓"), "Should display active icon")
        #expect(output.contains("○"), "Should display candidate icon")
        #expect(output.contains("✗"), "Should display retired icon")
        #expect(output.contains("推荐"), "Should display affordance label")
        #expect(output.contains("警告"), "Should display avoid label")
        #expect(output.contains("备注"), "Should display observation label")
    }

    // MARK: - Helpers

    private func createTempMemoryDir() throws -> String {
        let tempDir = "/tmp/axion-test-memory-list-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return tempDir
    }
}

// MARK: - Story 31.5: Universal Memory section tests

@Suite("MemoryListCommand Universal Memory")
struct MemoryListUniversalTests {

    @Test("list output includes universal memory section with entry counts")
    func listIncludesUniversalMemorySection() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = UniversalMemoryStore(memoryDir: tempDir, maxMemoryChars: 1000, maxUserChars: 1000)
        _ = await store.add(target: .memory, content: "entry one")
        _ = await store.add(target: .memory, content: "entry two")
        _ = await store.add(target: .memory, content: "entry three")
        _ = await store.add(target: .user, content: "user entry")

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("Universal Memory"), "Output should include Universal Memory section header")
        #expect(output.contains("MEMORY.md"), "Output should mention MEMORY.md")
        #expect(output.contains("USER.md"), "Output should mention USER.md")
        #expect(output.contains("3 entries"), "Output should show 3 entries for MEMORY.md")
        #expect(output.contains("1 entry"), "Output should show 1 entry for USER.md")
    }

    @Test("list output shows last updated date for universal memory")
    func listShowsLastUpdatedDate() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = UniversalMemoryStore(memoryDir: tempDir)
        await store.write(target: .memory, content: "some content")

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("last updated"), "Output should show last updated date")
    }

    @Test("list output with empty universal memory shows 0 entries")
    func listEmptyUniversalMemoryShowsZero() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let output = await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("Universal Memory"), "Output should include Universal Memory section")
        #expect(output.contains("0 entries"), "Output should show 0 entries for empty files")
    }

    private func createTempMemoryDir() throws -> String {
        let tempDir = "/tmp/axion-test-memory-list-univ-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return tempDir
    }
}
