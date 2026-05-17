import Foundation
import Testing

@testable import AxionCLI

// Story 12.3 AC1, AC4: MemoryExportCommand tests

@Suite("MemoryExportCommand")
struct MemoryExportCommandTests {

    private func makeStoreWithFacts() async throws -> (MemoryFactStore, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-export-cmd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let store = MemoryFactStore(memoryDir: tmpDir)

        let factA = AppMemoryFact.create(domain: "com.apple.finder", kind: .affordance, description: "Finder tip")
        let factB = AppMemoryFact.create(domain: "com.apple.calculator", kind: .observation, description: "Calc note")
        try await store.save(domain: "com.apple.finder", fact: factA)
        try await store.save(domain: "com.apple.calculator", fact: factB)

        return (store, tmpDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("performExport exports all domains")
    func performExportAll() async throws {
        let (_, dir) = try await makeStoreWithFacts()
        defer { cleanup(dir) }

        let outputFile = dir.appendingPathComponent("export.json").path
        let result = try await MemoryExportCommand.performExport(
            memoryDir: dir.path,
            outputFile: outputFile,
            app: nil
        )

        #expect(result.contains("2 facts"))
        #expect(result.contains("2 domain"))

        let data = try Data(contentsOf: URL(fileURLWithPath: outputFile))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(MemoryBundle.self, from: data)
        #expect(bundle.memories.count == 2)
    }

    @Test("performExport with --app filters to single domain")
    func performExportFiltered() async throws {
        let (_, dir) = try await makeStoreWithFacts()
        defer { cleanup(dir) }

        let outputFile = dir.appendingPathComponent("export-filtered.json").path
        let result = try await MemoryExportCommand.performExport(
            memoryDir: dir.path,
            outputFile: outputFile,
            app: "com.apple.finder"
        )

        #expect(result.contains("1 facts"))
        #expect(result.contains("1 domain"))

        let data = try Data(contentsOf: URL(fileURLWithPath: outputFile))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(MemoryBundle.self, from: data)
        #expect(bundle.memories.count == 1)
        #expect(bundle.memories[0].domain == "com.apple.finder")
    }

    @Test("performExport with empty store exports empty bundle")
    func performExportEmpty() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("axion-export-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let outputFile = tmpDir.appendingPathComponent("empty.json").path
        let result = try await MemoryExportCommand.performExport(
            memoryDir: tmpDir.path,
            outputFile: outputFile,
            app: nil
        )

        #expect(result.contains("0 facts"))
        #expect(result.contains("0 domain"))
    }
}
