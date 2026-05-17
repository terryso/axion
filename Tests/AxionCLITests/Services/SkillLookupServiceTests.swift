import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI
@testable import AxionCore

@Suite("SkillLookupService")
struct SkillLookupServiceTests {

    private func makeTempSkillsDir() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true)
        return tempDir.path
    }

    private func writeRecordedSkill(
        name: String, to dir: String
    ) throws -> String {
        let safeName = RecordCommand.sanitizeFileName(name)
        let path = (dir as NSString).appendingPathComponent("\(safeName).json")
        let skill = AxionCore.Skill(
            name: name,
            description: "Test skill",
            createdAt: Date(),
            sourceRecording: "test",
            steps: [
                .init(tool: "click", arguments: ["x": "100", "y": "200"]),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - AC1: Prompt skill takes priority

    @Test("AC1: Prompt skill found via registry returns .promptSkill")
    func testPromptSkillFound() {
        let registry = SkillRegistry()
        let sdkSkill = OpenAgentSDK.Skill(
            name: "polyv-live-cli",
            description: "直播管理",
            userInvocable: true,
            promptTemplate: "管理直播",
            whenToUse: "当用户需要管理直播时"
        )
        registry.register(sdkSkill)

        let service = SkillLookupService(
            registry: registry, skillsDirectory: "/tmp/nonexistent")
        let result = service.lookup(name: "polyv-live-cli")

        if case .promptSkill(let found) = result {
            #expect(found.name == "polyv-live-cli")
        } else {
            Issue.record("Expected .promptSkill, got \(result)")
        }
    }

    // MARK: - AC2: Recorded skill fallback

    @Test("AC2: Recorded skill found when registry misses")
    func testRecordedSkillFallback() throws {
        let registry = SkillRegistry()
        let tempDir = try makeTempSkillsDir()
        try writeRecordedSkill(name: "open_calculator", to: tempDir)

        let service = SkillLookupService(
            registry: registry, skillsDirectory: tempDir)
        let result = service.lookup(name: "open_calculator")

        if case .recordedSkill(let skill, _) = result {
            #expect(skill.name == "open_calculator")
        } else {
            Issue.record("Expected .recordedSkill, got \(result)")
        }
    }

    // MARK: - AC3: Same name — prompt skill wins

    @Test("AC3: Prompt skill takes priority over recorded skill with same name")
    func testPromptSkillPriorityOverRecorded() throws {
        let registry = SkillRegistry()
        let sdkSkill = OpenAgentSDK.Skill(
            name: "my-skill",
            description: "Prompt skill",
            userInvocable: true,
            promptTemplate: "Do something",
            whenToUse: "when needed"
        )
        registry.register(sdkSkill)

        let tempDir = try makeTempSkillsDir()
        try writeRecordedSkill(name: "my-skill", to: tempDir)

        let service = SkillLookupService(
            registry: registry, skillsDirectory: tempDir)
        let result = service.lookup(name: "my-skill")

        if case .promptSkill = result {
            // correct
        } else {
            Issue.record("Expected .promptSkill (priority), got \(result)")
        }
    }

    // MARK: - AC4: Not found

    @Test("AC4: Neither found returns .notFound")
    func testNotFound() {
        let registry = SkillRegistry()
        let service = SkillLookupService(
            registry: registry, skillsDirectory: "/tmp/nonexistent")
        let result = service.lookup(name: "nonexistent-skill")

        if case .notFound = result {
            // correct
        } else {
            Issue.record("Expected .notFound, got \(result)")
        }
    }

    // MARK: - parseSkillInvocation tests

    @Test("parseSkillInvocation extracts name and args")
    func testParseWithArgs() {
        let parsed = SkillLookupService.parseSkillInvocation(
            "/polyv-live-cli 获取频道列表")
        #expect(parsed != nil)
        #expect(parsed?.name == "polyv-live-cli")
        #expect(parsed?.args == "获取频道列表")
    }

    @Test("parseSkillInvocation extracts name without args")
    func testParseWithoutArgs() {
        let parsed = SkillLookupService.parseSkillInvocation("/open_calculator")
        #expect(parsed != nil)
        #expect(parsed?.name == "open_calculator")
        #expect(parsed?.args == nil)
    }

    @Test("parseSkillInvocation returns nil for non-slash prefix")
    func testParseNoSlash() {
        let parsed = SkillLookupService.parseSkillInvocation("just a task")
        #expect(parsed == nil)
    }

    @Test("parseSkillInvocation returns nil for bare slash")
    func testParseBareSlash() {
        let parsed = SkillLookupService.parseSkillInvocation("/")
        #expect(parsed == nil)
    }

    // MARK: - Edge cases

    @Test("Empty name returns .notFound")
    func testEmptyName() {
        let registry = SkillRegistry()
        let service = SkillLookupService(
            registry: registry, skillsDirectory: "/tmp/nonexistent")
        let result = service.lookup(name: "")
        if case .notFound = result {
            // correct
        } else {
            Issue.record("Expected .notFound, got \(result)")
        }
    }

    @Test("Invalid JSON file returns .notFound")
    func testInvalidJson() throws {
        let tempDir = try makeTempSkillsDir()
        let path = (tempDir as NSString).appendingPathComponent("bad.json")
        try "not valid json".write(toFile: path, atomically: true, encoding: .utf8)

        let registry = SkillRegistry()
        let service = SkillLookupService(
            registry: registry, skillsDirectory: tempDir)
        let result = service.lookup(name: "bad")
        if case .notFound = result {
            // correct
        } else {
            Issue.record("Expected .notFound, got \(result)")
        }
    }

    @Test("Special characters in skill name handled safely")
    func testSpecialChars() throws {
        let tempDir = try makeTempSkillsDir()
        try writeRecordedSkill(name: "my skill", to: tempDir)

        let registry = SkillRegistry()
        let service = SkillLookupService(
            registry: registry, skillsDirectory: tempDir)
        let result = service.lookup(name: "my skill")

        // sanitizeFileName replaces spaces with _, so "my skill" → "my_skill.json"
        if case .recordedSkill(let skill, _) = result {
            #expect(skill.name == "my skill")
        } else {
            Issue.record("Expected .recordedSkill, got \(result)")
        }
    }

    // MARK: - AC5: --no-skills skips lookup

    @Test("AC5: parseSkillInvocation still works but caller controls skip")
    func testNoSkillsSkip() {
        // parseSkillInvocation still parses correctly
        let parsed = SkillLookupService.parseSkillInvocation("/polyv-live-cli test")
        #expect(parsed != nil)
        #expect(parsed?.name == "polyv-live-cli")
        // The caller (RunCommand) checks noSkills flag before calling lookup
    }

    // MARK: - AC6: Metadata update after recorded skill execution

    @Test("AC6: Recorded skill result includes path for metadata update")
    func testRecordedSkillReturnsPath() throws {
        let tempDir = try makeTempSkillsDir()
        let path = try writeRecordedSkill(name: "metadata-test", to: tempDir)

        let registry = SkillRegistry()
        let service = SkillLookupService(
            registry: registry, skillsDirectory: tempDir)
        let result = service.lookup(name: "metadata-test")

        if case .recordedSkill(let skill, let returnedPath) = result {
            #expect(skill.name == "metadata-test")
            #expect(returnedPath == path)
            // RecordedSkillRunner updates last_used_at and execution_count at this path
        } else {
            Issue.record("Expected .recordedSkill, got \(result)")
        }
    }

    @Test("Recorded skill execution_count starts at 0")
    func testExecutionCountStartsAtZero() throws {
        let tempDir = try makeTempSkillsDir()
        let skill = AxionCore.Skill(
            name: "count-test",
            description: "Test",
            createdAt: Date(),
            sourceRecording: "test",
            steps: [.init(tool: "click", arguments: ["x": "1"])],
            executionCount: 0
        )
        let safeName = RecordCommand.sanitizeFileName("count-test")
        let path = (tempDir as NSString).appendingPathComponent("\(safeName).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(skill).write(to: URL(fileURLWithPath: path))

        let service = SkillLookupService(
            registry: SkillRegistry(), skillsDirectory: tempDir)
        let result = service.lookup(name: "count-test")

        if case .recordedSkill(let loaded, _) = result {
            #expect(loaded.executionCount == 0)
            #expect(loaded.lastUsedAt == nil)
        } else {
            Issue.record("Expected .recordedSkill, got \(result)")
        }
    }

    // MARK: - RecordedSkillRunner param parsing

    @Test("parseParamStrings handles URL-like values with equals")
    func testParamParsingWithUrlValue() throws {
        let result = try SkillRunCommand.parseParamStrings([
            "url=http://example.com", "type=slow",
        ])
        #expect(result["url"] == "http://example.com")
        #expect(result["type"] == "slow")
    }

    @Test("Invocation with key=value args parsed correctly")
    func testInvocationWithKeyValueArgs() {
        let parsed = SkillLookupService.parseSkillInvocation(
            "/open_calculator app=Calc")
        #expect(parsed?.name == "open_calculator")
        #expect(parsed?.args == "app=Calc")
    }
}
