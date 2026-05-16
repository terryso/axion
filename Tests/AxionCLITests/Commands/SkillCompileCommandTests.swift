import Testing
import Foundation
@testable import AxionCLI

@Suite("SkillCompileCommand")
struct SkillCompileCommandTests {

    // MARK: - Skills Directory

    @Test("skillsDirectory returns ~/.axion/skills path")
    func test_skillsDirectory_returnsCorrectPath() {
        let dir = SkillCompileCommand.skillsDirectory()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = (homeDir as NSString).appendingPathComponent(".axion/skills")
        #expect(dir == expected)
    }

    @Test("skillsDirectory path ends with .axion/skills")
    func test_skillsDirectory_endsCorrectly() {
        let dir = SkillCompileCommand.skillsDirectory()
        #expect(dir.hasSuffix(".axion/skills"))
    }

    // MARK: - sanitizeFileName reuse

    @Test("sanitizeFileName removes path traversal attempts")
    func test_sanitizeFileName_preventsTraversal() {
        let result = RecordCommand.sanitizeFileName("../../etc/passwd")
        #expect(!result.contains(".."))
        #expect(result == "____etc_passwd")
    }

    @Test("sanitizeFileName handles empty string")
    func test_sanitizeFileName_emptyString() {
        let result = RecordCommand.sanitizeFileName("")
        #expect(result == "untitled")
    }

    @Test("sanitizeFileName preserves valid names")
    func test_sanitizeFileName_validName() {
        let result = RecordCommand.sanitizeFileName("open_calculator")
        #expect(result == "open_calculator")
    }

    @Test("sanitizeFileName replaces invalid characters")
    func test_sanitizeFileName_invalidChars() {
        let result = RecordCommand.sanitizeFileName("my/recording:name")
        #expect(!result.contains("/"))
        #expect(!result.contains(":"))
    }
}
