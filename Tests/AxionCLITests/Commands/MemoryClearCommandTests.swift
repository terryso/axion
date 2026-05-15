import Foundation
import Testing
import OpenAgentSDK

@testable import AxionCLI

@Suite("MemoryClearCommand")
struct MemoryClearCommandTests {

    // MARK: - P0: Type Existence

    @Test("MemoryClearCommand type exists")
    func memoryClearCommandTypeExists() {
        let _ = MemoryClearCommand.self
    }

    // MARK: - P0 AC6: Clear specific domain Memory

    @Test("clear existing domain removes domain file")
    func clearExistingDomainRemovesDomainFile() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)
        let domain = "com.apple.calculator"

        let entry = KnowledgeEntry(
            id: UUID().uuidString,
            content: "Calculator run",
            tags: ["app:\(domain)", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: domain, knowledge: entry)

        let filePath = (tempDir as NSString).appendingPathComponent("\(domain).json")
        #expect(FileManager.default.fileExists(atPath: filePath),
            "Precondition: domain file should exist before clear")

        let result = try await MemoryClearCommand.clearDomain(domain, memoryDir: tempDir)

        #expect(result.success, "Clear should succeed for existing domain")
        #expect(!FileManager.default.fileExists(atPath: filePath),
            "Domain file should be removed after clear")
    }

    @Test("clear existing domain returns success")
    func clearExistingDomainReturnsSuccess() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)
        let domain = "com.apple.calculator"

        let entry = KnowledgeEntry(
            id: UUID().uuidString,
            content: "Run",
            tags: ["app:\(domain)", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: domain, knowledge: entry)

        let result = try await MemoryClearCommand.clearDomain(domain, memoryDir: tempDir)

        #expect(result.success, "Clear should report success for existing domain")
        #expect(result.message.contains(domain),
            "Success message should reference the cleared domain")
    }

    // MARK: - P0 AC6: Non-existent domain does not error

    @Test("clear non-existent domain does not error")
    func clearNonExistentDomainDoesNotError() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let result = try await MemoryClearCommand.clearDomain(
            "com.apple.nonexistent",
            memoryDir: tempDir
        )

        #expect(!result.success, "Clear should report non-success for non-existent domain")
        #expect(result.message.contains("not found") || result.message.contains("不存在") || result.message.contains("No"),
            "Message should indicate domain was not found")
    }

    // MARK: - P0 AC6: Clearing one domain does not affect others

    @Test("clear one domain does not affect other")
    func clearOneDomainDoesNotAffectOther() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)

        let calcEntry = KnowledgeEntry(
            id: "calc-1",
            content: "Calculator run",
            tags: ["app:com.apple.calculator", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )
        let finderEntry = KnowledgeEntry(
            id: "finder-1",
            content: "Finder run",
            tags: ["app:com.apple.finder", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: "com.apple.calculator", knowledge: calcEntry)
        try await store.save(domain: "com.apple.finder", knowledge: finderEntry)

        _ = try await MemoryClearCommand.clearDomain("com.apple.calculator", memoryDir: tempDir)

        let finderPath = (tempDir as NSString).appendingPathComponent("com.apple.finder.json")
        #expect(FileManager.default.fileExists(atPath: finderPath),
            "Finder domain file should NOT be removed when Calculator is cleared")

        let calcPath = (tempDir as NSString).appendingPathComponent("com.apple.calculator.json")
        #expect(!FileManager.default.fileExists(atPath: calcPath),
            "Calculator domain file should be removed after clear")
    }

    // MARK: - P1: Edge cases

    @Test("clear path traversal rejected")
    func clearPathTraversalRejected() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let maliciousDomains = ["../../../etc/passwd", "foo/bar", "foo\\bar", ".."]
        for domain in maliciousDomains {
            let result = try await MemoryClearCommand.clearDomain(domain, memoryDir: tempDir)
            #expect(!result.success, "Should reject path-traversal domain: '\(domain)'")
            #expect(result.message.contains("Invalid"),
                "Should report invalid domain for: '\(domain)'")
        }
    }

    @Test("clear empty memory dir does not crash")
    func clearEmptyMemoryDirDoesNotCrash() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let result = try await MemoryClearCommand.clearDomain(
            "com.apple.calculator",
            memoryDir: tempDir
        )

        #expect(!result.success, "Clear in empty dir should report non-success")
    }

    @Test("clear non-existent dir does not crash")
    func clearNonExistentDirDoesNotCrash() async throws {
        let tempDir = "/tmp/axion-test-nonexistent-\(UUID().uuidString)"

        let result = try await MemoryClearCommand.clearDomain(
            "com.apple.calculator",
            memoryDir: tempDir
        )

        #expect(!result.success, "Clear in non-existent dir should report non-success")
    }

    // MARK: - Helpers

    private func createTempMemoryDir() throws -> String {
        let tempDir = "/tmp/axion-test-memory-clear-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return tempDir
    }
}
