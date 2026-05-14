import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("SkillListCommand")
struct SkillListCommandTests {

    private func createTempSkillsDir(files: [(name: String, skill: Skill)]) throws -> String {
        let tempDir = NSTemporaryDirectory()
        let skillsDir = (tempDir as NSString).appendingPathComponent("axion_test_skills_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601

        for file in files {
            let data = try encoder.encode(file.skill)
            let path = (skillsDir as NSString).appendingPathComponent("\(file.name).json")
            try data.write(to: URL(fileURLWithPath: path))
        }

        return skillsDir
    }

    // MARK: - Empty Directory

    @Test("empty directory shows no skills message")
    func test_emptyDirectory() throws {
        let dir = try createTempSkillsDir(files: [])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let output = SkillListCommand.listSkills(in: dir)
        #expect(output.contains("无已保存的技能"))
        #expect(output.contains("axion skill compile"))
    }

    // MARK: - Nonexistent Directory

    @Test("nonexistent directory shows no skills message")
    func test_nonexistentDirectory() {
        let output = SkillListCommand.listSkills(in: "/nonexistent/path/skills")
        #expect(output.contains("无已保存的技能"))
    }

    // MARK: - Multiple Skills

    @Test("lists multiple skills with details")
    func test_multipleSkills() throws {
        let skillsDir = try createTempSkillsDir(files: [
            (
                name: "alpha",
                skill: Skill(
                    name: "alpha",
                    description: "First skill",
                    createdAt: Date(),
                    sourceRecording: "alpha",
                    parameters: [SkillParameter(name: "url", description: "URL")],
                    steps: [SkillStep(tool: "click", arguments: ["x": "100"])],
                    lastUsedAt: Date(),
                    executionCount: 3
                )
            ),
            (
                name: "beta",
                skill: Skill(
                    name: "beta",
                    description: "Second skill",
                    createdAt: Date(),
                    sourceRecording: "beta",
                    steps: [],
                    executionCount: 0
                )
            ),
        ])
        defer { try? FileManager.default.removeItem(atPath: skillsDir) }

        let output = SkillListCommand.listSkills(in: skillsDir)
        #expect(output.contains("已保存的技能"))
        #expect(output.contains("alpha"))
        #expect(output.contains("beta"))
        #expect(output.contains("First skill"))
        #expect(output.contains("url (默认值: 无)"))
        #expect(output.contains("执行次数: 3"))
        #expect(output.contains("执行次数: 0"))
        #expect(output.contains("从未使用"))
    }

    // MARK: - Ignores Non-JSON Files

    @Test("ignores non-JSON files in directory")
    func test_ignoresNonJSONFiles() throws {
        let tempDir = NSTemporaryDirectory()
        let skillsDir = (tempDir as NSString).appendingPathComponent("axion_test_skills_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: skillsDir) }

        // Write a non-JSON file
        let txtPath = (skillsDir as NSString).appendingPathComponent("readme.txt")
        try "hello".write(toFile: txtPath, atomically: true, encoding: .utf8)

        let output = SkillListCommand.listSkills(in: skillsDir)
        #expect(output.contains("无已保存的技能"))
    }

    // MARK: - Skill Without Parameters

    @Test("skill without parameters does not show parameter line")
    func test_skillWithoutParameters() throws {
        let skillsDir = try createTempSkillsDir(files: [
            (
                name: "simple",
                skill: Skill(
                    name: "simple",
                    description: "No params",
                    createdAt: Date(),
                    sourceRecording: "simple",
                    parameters: [],
                    steps: [SkillStep(tool: "click", arguments: ["x": "100"])]
                )
            ),
        ])
        defer { try? FileManager.default.removeItem(atPath: skillsDir) }

        let output = SkillListCommand.listSkills(in: skillsDir)
        #expect(output.contains("已保存的技能"))
        #expect(output.contains("simple"))
        #expect(output.contains("No params"))
        #expect(!output.contains("参数:"))
    }

    // MARK: - Corrupted JSON File

    @Test("corrupted JSON file is skipped, other skills still listed")
    func test_corruptedJSON_skipped() throws {
        let tempDir = NSTemporaryDirectory()
        let skillsDir = (tempDir as NSString).appendingPathComponent("axion_test_skills_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: skillsDir) }

        // Write corrupted JSON
        let corruptedPath = (skillsDir as NSString).appendingPathComponent("bad.json")
        try "{ not valid json".write(toFile: corruptedPath, atomically: true, encoding: .utf8)

        // Write valid skill
        let validSkill = Skill(
            name: "good",
            description: "Valid skill",
            createdAt: Date(),
            sourceRecording: "good",
            steps: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let validData = try encoder.encode(validSkill)
        let validPath = (skillsDir as NSString).appendingPathComponent("good.json")
        try validData.write(to: URL(fileURLWithPath: validPath))

        let output = SkillListCommand.listSkills(in: skillsDir)
        #expect(output.contains("已保存的技能"))
        #expect(output.contains("good"))
        #expect(output.contains("Valid skill"))
        #expect(!output.contains("bad"))
    }

    // MARK: - Default Value Display

    @Test("parameter with default value shows value, nil shows 无")
    func test_defaultValueDisplay() throws {
        let skillsDir = try createTempSkillsDir(files: [
            (
                name: "with_defaults",
                skill: Skill(
                    name: "with_defaults",
                    description: "Has defaults",
                    createdAt: Date(),
                    sourceRecording: "test",
                    parameters: [
                        SkillParameter(name: "search", defaultValue: "hello", description: "search term"),
                        SkillParameter(name: "url", defaultValue: nil, description: "URL"),
                    ],
                    steps: []
                )
            ),
        ])
        defer { try? FileManager.default.removeItem(atPath: skillsDir) }

        let output = SkillListCommand.listSkills(in: skillsDir)
        #expect(output.contains("search (默认值: hello)"))
        #expect(output.contains("url (默认值: 无)"))
    }
}
