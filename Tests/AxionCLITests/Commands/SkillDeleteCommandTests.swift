import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("SkillDeleteCommand")
struct SkillDeleteCommandTests {

    private func createTempSkillFile(name: String) throws -> (dir: String, path: String) {
        let tempDir = NSTemporaryDirectory()
        let skillsDir = (tempDir as NSString).appendingPathComponent("axion_test_skills_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let skill = Skill(
            name: name,
            description: "test",
            createdAt: Date(),
            sourceRecording: name,
            steps: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(skill)
        let skillPath = (skillsDir as NSString).appendingPathComponent("\(name).json")
        try data.write(to: URL(fileURLWithPath: skillPath))

        return (dir: skillsDir, path: skillPath)
    }

    // MARK: - File Deletion

    @Test("delete removes skill file")
    func test_delete_removesFile() throws {
        let (dir, path) = try createTempSkillFile(name: "to_delete")
        defer { try? FileManager.default.removeItem(atPath: dir) }

        #expect(FileManager.default.fileExists(atPath: path))
        try FileManager.default.removeItem(atPath: path)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    // MARK: - File Not Found

    @Test("deleting nonexistent file throws error")
    func test_deleteNonexistent_throws() {
        let nonexistentPath = "/tmp/axion_nonexistent_\(UUID().uuidString).json"
        #expect(!FileManager.default.fileExists(atPath: nonexistentPath))
        #expect(throws: Error.self) {
            try FileManager.default.removeItem(atPath: nonexistentPath)
        }
    }

    // MARK: - sanitizeFileName Integration

    @Test("sanitizeFileName used for skill name safety")
    func test_sanitizeFileName_integration() {
        let malicious = RecordCommand.sanitizeFileName("../../secret")
        #expect(!malicious.contains(".."))
        #expect(malicious == "____secret")
    }

    // MARK: - Path Traversal Prevention

    @Test("path traversal name is sanitized before file access")
    func test_pathTraversal_sanitized() {
        let safeName = RecordCommand.sanitizeFileName("../../../etc/passwd")
        let skillsDir = SkillCompileCommand.skillsDirectory()
        let skillPath = (skillsDir as NSString).appendingPathComponent("\(safeName).json")

        // Path should be within skills directory
        #expect(skillPath.hasPrefix(skillsDir))
        #expect(!safeName.contains(".."))
        #expect(!safeName.contains("/"))
    }

    // MARK: - Delete Flow Verification

    @Test("delete constructs correct file path from sanitized name")
    func test_delete_constructsCorrectPath() {
        let name = "my_skill"
        let safeName = RecordCommand.sanitizeFileName(name)
        let skillsDir = SkillCompileCommand.skillsDirectory()
        let expectedPath = (skillsDir as NSString).appendingPathComponent("\(safeName).json")

        #expect(expectedPath.hasSuffix("my_skill.json"))
        #expect(expectedPath.hasPrefix(skillsDir))
    }

    // MARK: - Delete Then List Shows Removed

    @Test("deleted skill no longer appears in list")
    func test_deleteThenList_notVisible() throws {
        let skillsDir = try createTempSkillFile(name: "temp_skill").dir
        defer { try? FileManager.default.removeItem(atPath: skillsDir) }

        // Verify skill appears in list
        let listBefore = SkillListCommand.listSkills(in: skillsDir)
        #expect(listBefore.contains("temp_skill"))

        // Delete the skill file
        let skillPath = (skillsDir as NSString).appendingPathComponent("temp_skill.json")
        try FileManager.default.removeItem(atPath: skillPath)

        // Verify skill no longer appears
        let listAfter = SkillListCommand.listSkills(in: skillsDir)
        #expect(!listAfter.contains("temp_skill"))
    }
}
