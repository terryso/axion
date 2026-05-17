import Foundation
import Testing

@testable import AxionCLI

// Story 12.3 AC2, AC5: MemoryImportCommand tests

@Suite("MemoryImportCommand")
struct MemoryImportCommandTests {

    private func makeTempDir() throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-import-cmd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        return tmpDir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("performImport imports facts from valid bundle")
    func performImportValid() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Write a bundle file
        let fact = AppMemoryFact.create(domain: "test.app", kind: .affordance, description: "import test")
        let bundle = MemoryBundle(memories: [ExportedDomain(domain: "test.app", facts: [fact])])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let inputFile = dir.appendingPathComponent("import.json")
        try data.write(to: inputFile, options: .atomic)

        let result = try await MemoryImportCommand.performImport(
            memoryDir: dir.path,
            inputFile: inputFile.path
        )

        #expect(result.contains("Facts imported: 1"))
        #expect(result.contains("Facts merged: 0"))
    }

    @Test("performImport with invalid file throws error")
    func performImportInvalidFile() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let inputFile = dir.appendingPathComponent("bad.json")
        try Data("not json".utf8).write(to: inputFile)

        do {
            _ = try await MemoryImportCommand.performImport(
                memoryDir: dir.path,
                inputFile: inputFile.path
            )
            Issue.record("Expected error for invalid file")
        } catch {
            // Expected
        }
    }

    @Test("performImport merges with existing facts")
    func performImportWithMerge() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Pre-existing fact
        let store = MemoryFactStore(memoryDir: dir)
        let local = AppMemoryFact.create(
            domain: "test.app",
            kind: .affordance,
            description: "same fact",
            confidence: 0.7,
            source: .local
        )
        try await store.save(domain: "test.app", fact: local)

        // Bundle with same ID fact
        let imported = AppMemoryFact(
            id: local.id,
            domain: "test.app",
            kind: .affordance,
            status: .candidate,
            confidence: 0.9,
            evidenceCount: 1,
            source: .local,
            scope: nil,
            cause: nil,
            description: "same fact",
            updatedAt: Date(),
            evidence: []
        )
        let bundle = MemoryBundle(memories: [ExportedDomain(domain: "test.app", facts: [imported])])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let inputFile = dir.appendingPathComponent("import.json")
        try data.write(to: inputFile, options: .atomic)

        let result = try await MemoryImportCommand.performImport(
            memoryDir: dir.path,
            inputFile: inputFile.path
        )

        #expect(result.contains("Facts merged: 1"))
        #expect(result.contains("Facts imported: 0"))
    }
}
