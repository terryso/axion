import Foundation
import Testing
import OpenAgentSDK

@testable import AxionCLI

@Suite("MemoryListCommand")
struct MemoryListCommandTests {

    // MARK: - P0: Type Existence

    @Test("MemoryListCommand type exists")
    func memoryListCommandTypeExists() {
        let _ = MemoryListCommand.self
    }

    // MARK: - P0 AC5: Display app list with entry counts and last-used time

    @Test("list output contains app memory header")
    func listOutputContainsAppMemoryHeader() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)

        let entry = KnowledgeEntry(
            id: UUID().uuidString,
            content: "Test run",
            tags: ["app:com.apple.calculator", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: "com.apple.calculator", knowledge: entry)

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("App Memory") || output.contains("Memory"),
            "Output should contain a header line for memory listing")
    }

    @Test("list output shows domain entry count and date")
    func listOutputShowsDomainEntryCountAndDate() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)
        let domain = "com.apple.calculator"

        let now = Date()
        for i in 0..<3 {
            let entry = KnowledgeEntry(
                id: "entry-\(i)",
                content: "Run \(i)",
                tags: ["app:\(domain)", "success"],
                createdAt: now.addingTimeInterval(Double(-i) * 86400),
                sourceRunId: nil
            )
            try await store.save(domain: domain, knowledge: entry)
        }

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains(domain), "Output should show the domain name")
        #expect(output.contains("3") || output.contains("3 entries"),
            "Output should show entry count for the domain")
    }

    @Test("list output multiple domains shows all")
    func listOutputMultipleDomainsShowsAll() async throws {
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

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("com.apple.calculator"), "Output should include Calculator domain")
        #expect(output.contains("com.apple.finder"), "Output should include Finder domain")
        #expect(output.contains("Total") || output.contains("total") || output.contains("2"),
            "Output should show total count of apps/entries")
    }

    // MARK: - P0 AC5: Empty Memory output

    @Test("list output no memory shows empty message")
    func listOutputNoMemoryShowsEmptyMessage() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        #expect(output.contains("No") || output.contains("empty") || output.contains("0") || output.contains("Total: 0"),
            "Output should indicate no memory data exists")
    }

    @Test("list output non-existent directory shows empty message")
    func listOutputNonExistentDirectoryShowsEmptyMessage() async throws {
        let tempDir = "/tmp/axion-test-nonexistent-\(UUID().uuidString)"

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        #expect(!output.isEmpty, "Should return a non-empty string even for non-existent directory")
    }

    // MARK: - P1: Last used date display

    @Test("list output shows last used date")
    func listOutputShowsLastUsedDate() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)
        let domain = "com.apple.calculator"

        let entry = KnowledgeEntry(
            id: "entry-1",
            content: "Recent run",
            tags: ["app:\(domain)", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: domain, knowledge: entry)

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        let datePattern = #"20\d{2}-\d{2}-\d{2}"#
        let regex = try NSRegularExpression(pattern: datePattern)
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        #expect(!matches.isEmpty, "Output should contain a date representation for 'last used'")
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
