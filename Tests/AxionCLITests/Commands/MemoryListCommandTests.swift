import XCTest
import OpenAgentSDK

@testable import AxionCLI

// [P0] MemoryListCommand type existence, output format
// [P1] Edge cases (empty memory, multiple domains, date display)
// Story 4.3 AC: #5

// MARK: - MemoryListCommand ATDD Tests

/// ATDD red-phase tests for `axion memory list` command (Story 4.3 AC5).
/// Tests that MemoryListCommand:
/// - Lists all domains with entry counts and last-used dates
/// - Handles empty Memory gracefully
/// - Outputs correct format
///
/// TDD RED PHASE: These tests will not compile until MemoryListCommand is implemented
/// in Sources/AxionCLI/Commands/MemoryListCommand.swift.
final class MemoryListCommandTests: XCTestCase {

    // MARK: - P0: Type Existence

    func test_memoryListCommand_typeExists() {
        let _ = MemoryListCommand.self
    }

    // MARK: - P0 AC5: Display app list with entry counts and last-used time

    func test_listOutput_containsAppMemoryHeader() async throws {
        // Use a temp directory as memory store
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)

        // Add some data
        let entry = KnowledgeEntry(
            id: UUID().uuidString,
            content: "Test run",
            tags: ["app:com.apple.calculator", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: "com.apple.calculator", knowledge: entry)

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        XCTAssertTrue(output.contains("App Memory") || output.contains("Memory"),
            "Output should contain a header line for memory listing")
    }

    func test_listOutput_showsDomainEntryCountAndDate() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)
        let domain = "com.apple.calculator"

        // Add 3 entries with different dates
        let now = Date()
        for i in 0..<3 {
            let entry = KnowledgeEntry(
                id: "entry-\(i)",
                content: "Run \(i)",
                tags: ["app:\(domain)", "success"],
                createdAt: now.addingTimeInterval(Double(-i) * 86400), // i days ago
                sourceRunId: nil
            )
            try await store.save(domain: domain, knowledge: entry)
        }

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        XCTAssertTrue(output.contains(domain),
            "Output should show the domain name")
        XCTAssertTrue(output.contains("3") || output.contains("3 entries"),
            "Output should show entry count for the domain")
    }

    func test_listOutput_multipleDomains_showsAll() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)

        // Add data for 2 domains
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

        XCTAssertTrue(output.contains("com.apple.calculator"),
            "Output should include Calculator domain")
        XCTAssertTrue(output.contains("com.apple.finder"),
            "Output should include Finder domain")
        XCTAssertTrue(output.contains("Total") || output.contains("total") || output.contains("2"),
            "Output should show total count of apps/entries")
    }

    // MARK: - P0 AC5: Empty Memory output

    func test_listOutput_noMemory_showsEmptyMessage() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        // Should not crash and should indicate no memory
        XCTAssertTrue(output.contains("No") || output.contains("empty") || output.contains("0") || output.contains("Total: 0"),
            "Output should indicate no memory data exists")
    }

    func test_listOutput_nonExistentDirectory_showsEmptyMessage() async throws {
        let tempDir = "/tmp/axion-test-nonexistent-\(UUID().uuidString)"

        let output = try await MemoryListCommand.listMemory(in: tempDir)

        // Should not crash even if directory doesn't exist
        XCTAssertFalse(output.isEmpty,
            "Should return a non-empty string even for non-existent directory")
    }

    // MARK: - P1: Last used date display

    func test_listOutput_showsLastUsedDate() async throws {
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

        // Should contain a date-like string (YYYY-MM-DD or similar)
        let datePattern = #"20\d{2}-\d{2}-\d{2}"#
        let regex = try NSRegularExpression(pattern: datePattern)
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        XCTAssertFalse(matches.isEmpty,
            "Output should contain a date representation for 'last used'")
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
