import XCTest
import OpenAgentSDK

@testable import AxionCLI

// [P0] MemoryClearCommand type existence, clear specific domain
// [P1] Edge cases (non-existent domain, clear one doesn't affect others)
// Story 4.3 AC: #6

// MARK: - MemoryClearCommand ATDD Tests

/// ATDD red-phase tests for `axion memory clear --app` command (Story 4.3 AC6).
/// Tests that MemoryClearCommand:
/// - Deletes a specific domain's Memory file
/// - Does not error when domain doesn't exist
/// - Does not affect other domains' Memory
///
/// TDD RED PHASE: These tests will not compile until MemoryClearCommand is implemented
/// in Sources/AxionCLI/Commands/MemoryClearCommand.swift.
final class MemoryClearCommandTests: XCTestCase {

    // MARK: - P0: Type Existence

    func test_memoryClearCommand_typeExists() {
        let _ = MemoryClearCommand.self
    }

    // MARK: - P0 AC6: Clear specific domain Memory

    func test_clear_existingDomain_removesDomainFile() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)
        let domain = "com.apple.calculator"

        // Populate with data
        let entry = KnowledgeEntry(
            id: UUID().uuidString,
            content: "Calculator run",
            tags: ["app:\(domain)", "success"],
            createdAt: Date(),
            sourceRunId: nil
        )
        try await store.save(domain: domain, knowledge: entry)

        // Verify file exists
        let filePath = (tempDir as NSString).appendingPathComponent("\(domain).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath),
            "Precondition: domain file should exist before clear")

        // Clear the domain
        let result = try await MemoryClearCommand.clearDomain(domain, memoryDir: tempDir)

        XCTAssertTrue(result.success,
            "Clear should succeed for existing domain")
        XCTAssertFalse(FileManager.default.fileExists(atPath: filePath),
            "Domain file should be removed after clear")
    }

    func test_clear_existingDomain_returnsSuccess() async throws {
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

        XCTAssertTrue(result.success,
            "Clear should report success for existing domain")
        XCTAssertTrue(result.message.contains(domain),
            "Success message should reference the cleared domain")
    }

    // MARK: - P0 AC6: Non-existent domain does not error

    func test_clear_nonExistentDomain_doesNotError() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let result = try await MemoryClearCommand.clearDomain(
            "com.apple.nonexistent",
            memoryDir: tempDir
        )

        // Should not throw and should indicate the domain was not found
        XCTAssertFalse(result.success,
            "Clear should report non-success for non-existent domain")
        XCTAssertTrue(result.message.contains("not found") || result.message.contains("不存在") || result.message.contains("No"),
            "Message should indicate domain was not found")
    }

    // MARK: - P0 AC6: Clearing one domain does not affect others

    func test_clear_oneDomain_doesNotAffectOther() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = FileBasedMemoryStore(memoryDir: tempDir)

        // Populate two domains
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

        // Clear only Calculator
        _ = try await MemoryClearCommand.clearDomain("com.apple.calculator", memoryDir: tempDir)

        // Verify Finder still exists
        let finderPath = (tempDir as NSString).appendingPathComponent("com.apple.finder.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderPath),
            "Finder domain file should NOT be removed when Calculator is cleared")

        // Verify Calculator is gone
        let calcPath = (tempDir as NSString).appendingPathComponent("com.apple.calculator.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: calcPath),
            "Calculator domain file should be removed after clear")
    }

    // MARK: - P1: Edge cases

    func test_clear_emptyMemoryDir_doesNotCrash() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Empty directory, no files
        let result = try await MemoryClearCommand.clearDomain(
            "com.apple.calculator",
            memoryDir: tempDir
        )

        // Should not crash
        XCTAssertFalse(result.success,
            "Clear in empty dir should report non-success")
    }

    func test_clear_nonExistentDir_doesNotCrash() async throws {
        let tempDir = "/tmp/axion-test-nonexistent-\(UUID().uuidString)"

        // Directory doesn't exist — should not crash
        let result = try await MemoryClearCommand.clearDomain(
            "com.apple.calculator",
            memoryDir: tempDir
        )

        XCTAssertFalse(result.success,
            "Clear in non-existent dir should report non-success")
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
