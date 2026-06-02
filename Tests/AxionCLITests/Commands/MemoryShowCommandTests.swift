import ArgumentParser
import Foundation
import Testing

@testable import AxionCLI

@Suite("MemoryShowCommand")
struct MemoryShowCommandTests {

    // MARK: - P0: Type Existence

    @Test("MemoryShowCommand type exists")
    func memoryShowCommandTypeExists() {
        let _ = MemoryShowCommand.self
    }

    // MARK: - P0 AC2: Show MEMORY.md content

    @Test("show memory displays content")
    func showMemoryDisplaysContent() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = UniversalMemoryStore(memoryDir: tempDir)
        await store.write(target: .memory, content: "§\nproject uses Swift\n§\n")

        let output = try await MemoryShowCommand.showContent(target: "memory", memoryDir: tempDir)
        #expect(output.contains("project uses Swift"), "Output should show MEMORY.md content")
    }

    // MARK: - P0 AC3: Show USER.md content

    @Test("show user displays content")
    func showUserDisplaysContent() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let store = UniversalMemoryStore(memoryDir: tempDir)
        await store.write(target: .user, content: "§\nprefers dark mode\n§\n")

        let output = try await MemoryShowCommand.showContent(target: "user", memoryDir: tempDir)
        #expect(output.contains("prefers dark mode"), "Output should show USER.md content")
    }

    // MARK: - P0: Empty file shows "No content" message

    @Test("show empty file displays no content message")
    func showEmptyFileDisplaysNoContent() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let output = try await MemoryShowCommand.showContent(target: "memory", memoryDir: tempDir)
        #expect(output.contains("No content"), "Output should indicate no content for empty file")
    }

    // MARK: - P0: Invalid target

    @Test("show invalid target returns error")
    func showInvalidTargetReturnsError() async throws {
        let tempDir = try createTempMemoryDir()
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        do {
            _ = try await MemoryShowCommand.showContent(target: "invalid", memoryDir: tempDir)
            Issue.record("Should throw for invalid target")
        } catch {
            #expect(error.localizedDescription.contains("'invalid'") || error.localizedDescription.contains("Invalid") || error is ValidationError,
                "Error should describe the invalid target: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func createTempMemoryDir() throws -> String {
        let tempDir = "/tmp/axion-test-memory-show-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return tempDir
    }
}
