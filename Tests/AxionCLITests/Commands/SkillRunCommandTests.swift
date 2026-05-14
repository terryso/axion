import Testing
import Foundation
import ArgumentParser
@testable import AxionCLI
@testable import AxionCore

@Suite("SkillRunCommand")
struct SkillRunCommandTests {

    // MARK: - Skills Directory Path

    @Test("uses same skills directory as SkillCompileCommand")
    func test_skillsDirectory_shared() {
        let dir = SkillCompileCommand.skillsDirectory()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = (homeDir as NSString).appendingPathComponent(".axion/skills")
        #expect(dir == expected)
    }

    // MARK: - sanitizeFileName Reuse

    @Test("sanitizeFileName prevents path traversal")
    func test_sanitizeFileName_preventsTraversal() {
        let result = RecordCommand.sanitizeFileName("../../etc/passwd")
        #expect(!result.contains(".."))
    }

    @Test("sanitizeFileName preserves valid skill names")
    func test_sanitizeFileName_validSkillName() {
        let result = RecordCommand.sanitizeFileName("open_calculator")
        #expect(result == "open_calculator")
    }

    @Test("sanitizeFileName handles special characters")
    func test_sanitizeFileName_specialChars() {
        let result = RecordCommand.sanitizeFileName("my/skill:name")
        #expect(!result.contains("/"))
        #expect(!result.contains(":"))
    }

    // MARK: - parseParamStrings

    @Test("parseParamStrings parses key=value correctly")
    func test_parseParams_validKeyValue() throws {
        let result = try SkillRunCommand.parseParamStrings(["url=https://example.com"])
        #expect(result == ["url": "https://example.com"])
    }

    @Test("parseParamStrings parses multiple params")
    func test_parseParams_multipleParams() throws {
        let result = try SkillRunCommand.parseParamStrings([
            "url=https://example.com",
            "search=hello world",
        ])
        #expect(result["url"] == "https://example.com")
        #expect(result["search"] == "hello world")
    }

    @Test("parseParamStrings parses value with equals sign")
    func test_parseParams_valueWithEquals() throws {
        let result = try SkillRunCommand.parseParamStrings(["expr=a=b"])
        #expect(result["expr"] == "a=b")
    }

    @Test("parseParamStrings empty array returns empty dict")
    func test_parseParams_emptyArray() throws {
        let result = try SkillRunCommand.parseParamStrings([])
        #expect(result.isEmpty)
    }

    @Test("parseParamStrings missing equals throws ValidationError")
    func test_parseParams_missingEquals_throws() {
        do {
            _ = try SkillRunCommand.parseParamStrings(["no_equals_here"])
            #expect(Bool(false), "Should have thrown")
        } catch let error as ValidationError {
            #expect(error.description.contains("参数格式错误"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("parseParamStrings empty key throws ValidationError")
    func test_parseParams_emptyKey_throws() {
        do {
            _ = try SkillRunCommand.parseParamStrings(["=value"])
            #expect(Bool(false), "Should have thrown")
        } catch let error as ValidationError {
            #expect(error.description.contains("参数名不能为空"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Skill Execution Result Formatting

    @Test("SkillExecutionResult for success has no error message")
    func test_executionResult_success() {
        let result = SkillExecutionResult(
            success: true,
            stepsExecuted: 5,
            failedStepIndex: nil,
            durationSeconds: 1.23,
            errorMessage: nil
        )
        #expect(result.success)
        #expect(result.stepsExecuted == 5)
        #expect(result.failedStepIndex == nil)
        #expect(result.errorMessage == nil)
    }

    @Test("SkillExecutionResult for failure includes error info")
    func test_executionResult_failure() {
        let result = SkillExecutionResult(
            success: false,
            stepsExecuted: 2,
            failedStepIndex: 2,
            durationSeconds: 0.5,
            errorMessage: "步骤 3 失败: element not found"
        )
        #expect(!result.success)
        #expect(result.failedStepIndex == 2)
        #expect(result.errorMessage?.contains("步骤 3") == true)
    }
}
