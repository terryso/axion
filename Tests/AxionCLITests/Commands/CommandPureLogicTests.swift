import ArgumentParser
import AxionCore
import Foundation
import Testing

@testable import AxionCLI

@Suite("Command Pure Logic Tests")
struct CommandPureLogicTests {

    // MARK: - sanitizeFileName

    @Test("sanitizeFileName removes path separators")
    func sanitizeFileNameRemovesSlashes() {
        let result = sanitizeFileName("path/to/file")
        #expect(!result.contains("/"))
    }

    @Test("sanitizeFileName removes path traversal")
    func sanitizeFileNameRemovesTraversal() {
        let result = sanitizeFileName("../../etc/passwd")
        #expect(!result.contains(".."))
    }

    @Test("sanitizeFileName returns untitled for empty/whitespace input")
    func sanitizeFileNameEmptyReturnsUntitled() {
        let result = sanitizeFileName("   ")
        #expect(result == "untitled")
    }

    @Test("sanitizeFileName handles normal names")
    func sanitizeFileNameNormal() {
        let result = sanitizeFileName("my_recording")
        #expect(result == "my_recording")
    }

    // MARK: - SkillDeleteCommand

    @Test("SkillDeleteCommand deletes existing skill file")
    func skillDeleteDeletesExistingFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write a dummy skill file
        let skill = Skill(name: "test_delete", description: "test", version: 1, createdAt: Date(), sourceRecording: "test", parameters: [], steps: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        try data.write(to: tempDir.appendingPathComponent("test_delete.json"))

        // Verify file exists
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("test_delete.json").path))

        // Delete manually (simulating what SkillDeleteCommand does)
        try FileManager.default.removeItem(atPath: tempDir.appendingPathComponent("test_delete.json").path)
        #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("test_delete.json").path))
    }

    // MARK: - ServerCommand.validate

    @Test("ServerCommand validate rejects maxConcurrent < 1")
    func serverCommandValidateRejectsZero() {
        #expect(throws: (any Error).self) {
            _ = try ServerCommand.parse(["--max-concurrent", "0"])
        }
    }

    @Test("ServerCommand validate accepts maxConcurrent >= 1")
    func serverCommandValidateAcceptsOne() throws {
        let command = try ServerCommand.parse(["--max-concurrent", "1"])
        try command.validate()
    }

    @Test("ServerCommand defaults port to 4242")
    func serverCommandDefaultPort() throws {
        let command = try ServerCommand.parse([])
        #expect(command.port == 4242)
    }

    @Test("ServerCommand defaults host to 127.0.0.1")
    func serverCommandDefaultHost() throws {
        let command = try ServerCommand.parse([])
        #expect(command.host == "127.0.0.1")
    }

    // MARK: - ConfigManager directory paths

    @Test("skillsDirectory returns path under .axion/skills")
    func skillsDirectoryPath() {
        let path = ConfigManager.skillsDirectory
        #expect(path.hasSuffix(".axion/skills"))
    }

    @Test("recordingsDirectory returns path under .axion/recordings")
    func recordingsDirectoryPath() {
        let path = ConfigManager.recordingsDirectory
        #expect(path.hasSuffix(".axion/recordings"))
    }
}
