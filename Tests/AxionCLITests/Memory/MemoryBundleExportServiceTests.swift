import Foundation
import Testing

@testable import AxionCLI

// Story 12.3 AC1, AC4: MemoryBundleExportService tests

@Suite("MemoryBundleExportService")
struct MemoryBundleExportServiceTests {

    private func makeStore() async throws -> (MemoryFactStore, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-export-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let store = MemoryFactStore(memoryDir: tmpDir)
        return (store, tmpDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("exportAll produces correct MemoryBundle JSON")
    func exportAllMultipleDomains() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        // Seed facts across two domains
        let factA = AppMemoryFact.create(domain: "com.apple.finder", kind: .affordance, description: "Finder tip")
        let factB = AppMemoryFact.create(domain: "com.apple.calculator", kind: .observation, description: "Calc note")
        try await store.save(domain: "com.apple.finder", fact: factA)
        try await store.save(domain: "com.apple.calculator", fact: factB)

        let service = MemoryBundleExportService()
        let bundle = try await service.exportAll(store: store)

        #expect(bundle.schemaVersion == 1)
        #expect(bundle.memories.count == 2)

        let finderDomain = bundle.memories.first { $0.domain == "com.apple.finder" }
        #expect(finderDomain != nil)
        #expect(finderDomain!.facts.count == 1)
        #expect(finderDomain!.facts[0].description == "Finder tip")
    }

    @Test("exportDomain filters to specified domain only")
    func exportDomainFilter() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let factA = AppMemoryFact.create(domain: "com.apple.finder", kind: .affordance, description: "Finder tip")
        let factB = AppMemoryFact.create(domain: "com.apple.calculator", kind: .observation, description: "Calc note")
        try await store.save(domain: "com.apple.finder", fact: factA)
        try await store.save(domain: "com.apple.calculator", fact: factB)

        let service = MemoryBundleExportService()
        let bundle = try await service.exportDomain(store: store, domain: "com.apple.finder")

        #expect(bundle.memories.count == 1)
        #expect(bundle.memories[0].domain == "com.apple.finder")
        #expect(bundle.memories[0].facts.count == 1)
    }

    @Test("exportAll with empty Memory returns empty memories array")
    func exportAllEmpty() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let service = MemoryBundleExportService()
        let bundle = try await service.exportAll(store: store)

        #expect(bundle.memories.isEmpty)
        #expect(bundle.schemaVersion == 1)
    }

    @Test("writeBundle writes valid JSON to disk")
    func writeBundleToFile() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let fact = AppMemoryFact.create(domain: "test.app", kind: .affordance, description: "write test")
        try await store.save(domain: "test.app", fact: fact)

        let service = MemoryBundleExportService()
        let bundle = try await service.exportAll(store: store)

        let outputFile = dir.appendingPathComponent("output.json")
        try service.writeBundle(bundle, to: outputFile)

        #expect(FileManager.default.fileExists(atPath: outputFile.path))

        let data = try Data(contentsOf: outputFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MemoryBundle.self, from: data)

        #expect(decoded.memories.count == bundle.memories.count)
        #expect(decoded.schemaVersion == 1)
    }

    @Test("writeBundle overwrites existing file")
    func writeBundleOverwrite() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-export-overwrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write initial content
        let file = tmpDir.appendingPathComponent("mem.json")
        try Data("old content".utf8).write(to: file)

        let bundle = MemoryBundle(memories: [])
        let service = MemoryBundleExportService()
        try service.writeBundle(bundle, to: file)

        let data = try Data(contentsOf: file)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("old content"))
        #expect(json.contains("schema_version"))
    }

    @Test("exportDomain for non-existent domain returns empty facts")
    func exportNonExistentDomain() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }

        let service = MemoryBundleExportService()
        let bundle = try await service.exportDomain(store: store, domain: "nonexistent.app")

        #expect(bundle.memories.count == 1)
        #expect(bundle.memories[0].domain == "nonexistent.app")
        #expect(bundle.memories[0].facts.isEmpty)
    }
}
