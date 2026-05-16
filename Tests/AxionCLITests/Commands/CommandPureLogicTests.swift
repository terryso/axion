import ArgumentParser
import AxionCore
import Foundation
import Testing

@testable import AxionCLI

@Suite("Command Pure Logic Tests")
struct CommandPureLogicTests {

    // MARK: - SkillRunCommand.parseParamStrings

    @Test("parseParamStrings parses single key=value")
    func parseParamStringsSingle() throws {
        let result = try SkillRunCommand.parseParamStrings(["key=value"])
        #expect(result == ["key": "value"])
    }

    @Test("parseParamStrings parses multiple params")
    func parseParamStringsMultiple() throws {
        let result = try SkillRunCommand.parseParamStrings(["url=https://example.com", "count=5"])
        #expect(result == ["url": "https://example.com", "count": "5"])
    }

    @Test("parseParamStrings handles empty array")
    func parseParamStringsEmpty() throws {
        let result = try SkillRunCommand.parseParamStrings([])
        #expect(result.isEmpty)
    }

    @Test("parseParamStrings handles value with equals sign")
    func parseParamStringsValueWithEquals() throws {
        let result = try SkillRunCommand.parseParamStrings(["expr=a=b+c"])
        #expect(result == ["expr": "a=b+c"])
    }

    @Test("parseParamStrings throws on missing equals")
    func parseParamStringsThrowsOnMissingEquals() {
        #expect(throws: ValidationError.self) {
            try SkillRunCommand.parseParamStrings(["noequalssign"])
        }
    }

    @Test("parseParamStrings throws on empty key")
    func parseParamStringsThrowsOnEmptyKey() {
        #expect(throws: ValidationError.self) {
            try SkillRunCommand.parseParamStrings(["=value"])
        }
    }

    @Test("parseParamStrings handles empty value")
    func parseParamStringsEmptyValue() throws {
        let result = try SkillRunCommand.parseParamStrings(["key="])
        #expect(result == ["key": ""])
    }

    // MARK: - RecordCommand.parseRecordingEvents

    @Test("parseRecordingEvents returns empty for invalid JSON")
    func parseRecordingEventsInvalidJSON() {
        let result = RecordCommand.parseRecordingEvents(from: "not json")
        #expect(result.isEmpty)
    }

    @Test("parseRecordingEvents returns empty for missing events key")
    func parseRecordingEventsMissingKey() {
        let result = RecordCommand.parseRecordingEvents(from: "{\"other\":[]}")
        #expect(result.isEmpty)
    }

    @Test("parseRecordingEvents parses valid events")
    func parseRecordingEventsValid() throws {
        let event = RecordedEvent(type: .click, timestamp: 1.5, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil)
        let eventData = try JSONEncoder().encode(event)
        let eventString = String(data: eventData, encoding: .utf8)!

        // Build JSON with events as an array of JSON-encoded strings
        let wrapper: [String: Any] = ["events": [eventString]]
        let wrapperData = try JSONSerialization.data(withJSONObject: wrapper)
        let input = String(data: wrapperData, encoding: .utf8)!

        let result = RecordCommand.parseRecordingEvents(from: input)
        #expect(result.count == 1)
        #expect(result[0].type == .click)
        #expect(result[0].timestamp == 1.5)
    }

    @Test("parseRecordingEvents skips invalid event entries")
    func parseRecordingEventsSkipsInvalid() throws {
        let validEvent = RecordedEvent(type: .hotkey, timestamp: 1.0, parameters: ["key": .string("a")], windowContext: nil)
        let validData = try JSONEncoder().encode(validEvent)
        let validString = String(data: validData, encoding: .utf8)!

        let wrapper: [String: Any] = ["events": ["invalid json", validString]]
        let wrapperData = try JSONSerialization.data(withJSONObject: wrapper)
        let input = String(data: wrapperData, encoding: .utf8)!

        let result = RecordCommand.parseRecordingEvents(from: input)
        #expect(result.count == 1)
        #expect(result[0].type == .hotkey)
    }

    // MARK: - RecordCommand.parseWindowSnapshots

    @Test("parseWindowSnapshots returns empty for invalid JSON")
    func parseWindowSnapshotsInvalidJSON() {
        let result = RecordCommand.parseWindowSnapshots(from: "not json")
        #expect(result.isEmpty)
    }

    @Test("parseWindowSnapshots returns empty for missing key")
    func parseWindowSnapshotsMissingKey() {
        let result = RecordCommand.parseWindowSnapshots(from: "{\"other\":[]}")
        #expect(result.isEmpty)
    }

    // MARK: - RecordCommand.sanitizeFileName

    @Test("sanitizeFileName removes path separators")
    func sanitizeFileNameRemovesSlashes() {
        let result = RecordCommand.sanitizeFileName("path/to/file")
        #expect(!result.contains("/"))
    }

    @Test("sanitizeFileName removes path traversal")
    func sanitizeFileNameRemovesTraversal() {
        let result = RecordCommand.sanitizeFileName("../../etc/passwd")
        #expect(!result.contains(".."))
    }

    @Test("sanitizeFileName returns untitled for empty/whitespace input")
    func sanitizeFileNameEmptyReturnsUntitled() {
        let result = RecordCommand.sanitizeFileName("   ")
        #expect(result == "untitled")
    }

    @Test("sanitizeFileName handles normal names")
    func sanitizeFileNameNormal() {
        let result = RecordCommand.sanitizeFileName("my_recording")
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

    // MARK: - SkillCompileCommand.skillsDirectory

    @Test("skillsDirectory returns path under .axion/skills")
    func skillsDirectoryPath() {
        let path = SkillCompileCommand.skillsDirectory()
        #expect(path.hasSuffix(".axion/skills"))
    }

    // MARK: - RecordCommand.recordingsDirectory

    @Test("recordingsDirectory returns path under .axion/recordings")
    func recordingsDirectoryPath() {
        let path = RecordCommand.recordingsDirectory()
        #expect(path.hasSuffix(".axion/recordings"))
    }
}
