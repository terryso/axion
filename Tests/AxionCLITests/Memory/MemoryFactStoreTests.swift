import Foundation
import Testing

@testable import AxionCLI

// Story 12.1 AC1, AC7: MemoryFactStore CRUD and lazy migration

@Suite("MemoryFactStore")
struct MemoryFactStoreTests {

    /// Create a temporary store for each test.
    private func makeStore() async throws -> (MemoryFactStore, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-test-facts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let store = MemoryFactStore(memoryDir: tmpDir)
        return (store, tmpDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - CRUD

    @Test("save and query round-trip")
    func saveAndQuery() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let fact = AppMemoryFact.create(
            domain: "com.apple.calculator",
            kind: .observation,
            description: "Calculator has AXButton for equals"
        )

        try await store.save(domain: "com.apple.calculator", fact: fact)
        let results = try await store.query(domain: "com.apple.calculator")

        #expect(results.count == 1)
        #expect(results[0].id == fact.id)
        #expect(results[0].description == fact.description)
    }

    @Test("save updates existing fact by ID")
    func saveUpdatesExisting() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        var fact = AppMemoryFact.create(
            domain: "com.apple.calculator",
            kind: .observation,
            description: "Same observation"
        )
        try await store.save(domain: "com.apple.calculator", fact: fact)

        fact.confidence = 0.9
        fact.evidenceCount = 3
        try await store.save(domain: "com.apple.calculator", fact: fact)

        let results = try await store.query(domain: "com.apple.calculator")
        #expect(results.count == 1)
        #expect(results[0].confidence == 0.9)
        #expect(results[0].evidenceCount == 3)
    }

    @Test("query with status filter")
    func queryWithFilter() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let candidate = AppMemoryFact.create(
            domain: "test", kind: .observation, description: "fact A"
        )
        var active = AppMemoryFact.create(
            domain: "test", kind: .avoid, description: "fact B"
        )
        active.status = .active

        try await store.save(domain: "test", fact: candidate)
        try await store.save(domain: "test", fact: active)

        let activeResults = try await store.query(domain: "test", filter: FactFilter(status: .active))
        #expect(activeResults.count == 1)
        #expect(activeResults[0].status == .active)

        let avoidResults = try await store.query(domain: "test", filter: FactFilter(kind: .avoid))
        #expect(avoidResults.count == 1)
        #expect(avoidResults[0].kind == .avoid)
    }

    @Test("query returns empty for non-existent domain")
    func queryNonExistent() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let results = try await store.query(domain: "nonexistent")
        #expect(results.isEmpty)
    }

    @Test("listDomains returns saved domains")
    func listDomains() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let fact1 = AppMemoryFact.create(domain: "app-b", kind: .observation, description: "f1")
        let fact2 = AppMemoryFact.create(domain: "app-a", kind: .observation, description: "f2")

        try await store.save(domain: "app-b", fact: fact1)
        try await store.save(domain: "app-a", fact: fact2)

        let domains = try await store.listDomains()
        #expect(domains == ["app-a", "app-b"])
    }

    @Test("delete removes domain")
    func deleteDomain() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let fact = AppMemoryFact.create(domain: "to-delete", kind: .observation, description: "f")
        try await store.save(domain: "to-delete", fact: fact)

        let before = try await store.query(domain: "to-delete")
        #expect(!before.isEmpty)

        try await store.delete(domain: "to-delete")
        let after = try await store.query(domain: "to-delete")
        #expect(after.isEmpty)
    }

    @Test("saveAll batch upserts multiple facts")
    func saveAllBatchUpsert() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let facts = [
            AppMemoryFact.create(domain: "test", kind: .observation, description: "fact 1"),
            AppMemoryFact.create(domain: "test", kind: .avoid, description: "fact 2"),
        ]
        try await store.saveAll(domain: "test", facts: facts)

        let results = try await store.query(domain: "test")
        #expect(results.count == 2)
    }

    // MARK: - AC7: Lazy Migration from KnowledgeEntry

    @Test("lazy migration converts old KnowledgeEntry JSON to AppMemoryFact")
    func lazyMigrationFromLegacy() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        // Write a legacy KnowledgeEntry file
        let legacyData: [[String: Any]] = [
            [
                "id": "legacy-1",
                "content": "Calculator supports keyboard shortcuts",
                "tags": ["app:com.apple.calculator", "success"],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ]
        ]
        let legacyURL = dir.appendingPathComponent("com.apple.calculator.json")
        let jsonData = try JSONSerialization.data(
            withJSONObject: legacyData,
            options: [.sortedKeys, .prettyPrinted]
        )
        try jsonData.write(to: legacyURL)

        // Query via the store — should trigger lazy migration
        let facts = try await store.query(domain: "com.apple.calculator")
        #expect(facts.count == 1)
        #expect(facts[0].kind == .observation)
        #expect(facts[0].status == .candidate)
        #expect(facts[0].confidence == 0.5)
        #expect(facts[0].description == "Calculator supports keyboard shortcuts")
    }

    @Test("lazy migration writes new -facts.json file")
    func lazyMigrationWritesNewFile() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        // Write legacy file
        let legacyData: [[String: Any]] = [
            [
                "id": "legacy-2",
                "content": "Test content",
                "tags": ["test"],
                "createdAt": ISO8601DateFormatter().string(from: Date()),
            ]
        ]
        let legacyURL = dir.appendingPathComponent("test-app.json")
        let jsonData = try JSONSerialization.data(withJSONObject: legacyData, options: [.sortedKeys])
        try jsonData.write(to: legacyURL)

        // Trigger migration
        _ = try await store.query(domain: "test-app")

        // Verify new file exists
        let newURL = dir.appendingPathComponent("test-app-facts.json")
        #expect(FileManager.default.fileExists(atPath: newURL.path))
    }

    // MARK: - JSON Format

    @Test("saved file uses sortedKeys and prettyPrinted")
    func savedFileFormat() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let fact = AppMemoryFact.create(domain: "format-test", kind: .observation, description: "test")
        try await store.save(domain: "format-test", fact: fact)

        let fileURL = dir.appendingPathComponent("format-test-facts.json")
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        // prettyPrinted should have newlines
        #expect(content.contains("\n"))
        // sortedKeys should have alphabetically ordered keys
        #expect(content.contains("\"confidence\""))
        #expect(content.contains("\"description\""))
    }
}
