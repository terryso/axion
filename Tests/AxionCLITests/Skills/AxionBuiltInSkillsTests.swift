import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

@Suite("AxionBuiltInSkills")
struct AxionBuiltInSkillsTests {

    // MARK: - AC1: Three skills registered with correct attributes

    @Test("screenshot-analyze skill has correct name and attributes")
    func testScreenshotAnalyzeAttributes() {
        let skill = AxionBuiltInSkills.screenshotAnalyze
        #expect(skill.name == "screenshot-analyze")
        #expect(skill.userInvocable == true)
        #expect(skill.isAvailable() == true)
        #expect(skill.toolRestrictions == nil)
    }

    @Test("data-extract skill has correct name and attributes")
    func testDataExtractAttributes() {
        let skill = AxionBuiltInSkills.dataExtract
        #expect(skill.name == "data-extract")
        #expect(skill.userInvocable == true)
        #expect(skill.isAvailable() == true)
        #expect(skill.toolRestrictions == nil)
    }

    @Test("form-fill skill has correct name and attributes")
    func testFormFillAttributes() {
        let skill = AxionBuiltInSkills.formFill
        #expect(skill.name == "form-fill")
        #expect(skill.userInvocable == true)
        #expect(skill.isAvailable() == true)
        #expect(skill.toolRestrictions == nil)
    }

    // MARK: - AC6: Register to SkillRegistry and find via lookup

    @Test("Built-in skills found in registry after registration")
    func testRegistryLookup() {
        let registry = SkillRegistry()
        registry.register(AxionBuiltInSkills.screenshotAnalyze)
        registry.register(AxionBuiltInSkills.dataExtract)
        registry.register(AxionBuiltInSkills.formFill)

        #expect(registry.find("screenshot-analyze") != nil)
        #expect(registry.find("data-extract") != nil)
        #expect(registry.find("form-fill") != nil)
        #expect(registry.allSkills.count == 3)
    }

    @Test("Built-in skills found via aliases")
    func testRegistryAliasLookup() {
        let registry = SkillRegistry()
        registry.register(AxionBuiltInSkills.screenshotAnalyze)
        registry.register(AxionBuiltInSkills.dataExtract)
        registry.register(AxionBuiltInSkills.formFill)

        #expect(registry.find("sa")?.name == "screenshot-analyze")
        #expect(registry.find("analyze")?.name == "screenshot-analyze")
        #expect(registry.find("extract")?.name == "data-extract")
        #expect(registry.find("de")?.name == "data-extract")
        #expect(registry.find("fill")?.name == "form-fill")
        #expect(registry.find("ff")?.name == "form-fill")
        #expect(registry.find("screen")?.name == "screenshot-analyze")
    }

    // MARK: - Prompt templates non-empty with key instructions

    @Test("screenshot-analyze promptTemplate contains key instructions")
    func testScreenshotAnalyzePromptContent() {
        let skill = AxionBuiltInSkills.screenshotAnalyze
        #expect(!skill.promptTemplate.isEmpty)
        #expect(skill.promptTemplate.contains("screenshot"))
        #expect(skill.promptTemplate.contains("get_accessibility_tree"))
    }

    @Test("data-extract promptTemplate contains key instructions")
    func testDataExtractPromptContent() {
        let skill = AxionBuiltInSkills.dataExtract
        #expect(!skill.promptTemplate.isEmpty)
        #expect(skill.promptTemplate.contains("get_accessibility_tree"))
        #expect(skill.promptTemplate.contains("AXTable"))
    }

    @Test("form-fill promptTemplate contains key instructions")
    func testFormFillPromptContent() {
        let skill = AxionBuiltInSkills.formFill
        #expect(!skill.promptTemplate.isEmpty)
        #expect(skill.promptTemplate.contains("type_text"))
        #expect(skill.promptTemplate.contains("AXTextField"))
    }

    // MARK: - whenToUse non-empty (implicit trigger support)

    @Test("All skills have non-empty whenToUse")
    func testWhenToUseNonEmpty() {
        let skills = [
            AxionBuiltInSkills.screenshotAnalyze,
            AxionBuiltInSkills.dataExtract,
            AxionBuiltInSkills.formFill,
        ]
        for skill in skills {
            #expect(skill.whenToUse != nil)
            #expect(!skill.whenToUse!.isEmpty)
        }
    }

    @Test("All skills have non-empty argumentHint")
    func testArgumentHintNonEmpty() {
        let skills = [
            AxionBuiltInSkills.screenshotAnalyze,
            AxionBuiltInSkills.dataExtract,
            AxionBuiltInSkills.formFill,
        ]
        for skill in skills {
            #expect(skill.argumentHint != nil)
            #expect(!skill.argumentHint!.isEmpty)
        }
    }

    @Test("registerAll registers all three skills into registry")
    func testRegisterAll() {
        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        #expect(registry.allSkills.count == 3)
        #expect(registry.find("screenshot-analyze") != nil)
        #expect(registry.find("data-extract") != nil)
        #expect(registry.find("form-fill") != nil)
    }

    // MARK: - AC5: SkillListCommand output includes built-in skills

    @Test("listPromptSkills includes built-in skills with correct source")
    func testListPromptSkillsIncludesBuiltIn() {
        let registry = SkillRegistry()
        registry.register(AxionBuiltInSkills.screenshotAnalyze)
        registry.register(AxionBuiltInSkills.dataExtract)
        registry.register(AxionBuiltInSkills.formFill)

        let output = SkillListCommand.listPromptSkills(from: registry)
        #expect(output.contains("screenshot-analyze"))
        #expect(output.contains("data-extract"))
        #expect(output.contains("form-fill"))
        #expect(output.contains("类型: prompt"))
        #expect(output.contains("来源: built-in"))
    }

    @Test("listPromptSkills returns empty for empty registry")
    func testListPromptSkillsEmpty() {
        let registry = SkillRegistry()
        let output = SkillListCommand.listPromptSkills(from: registry)
        #expect(output.isEmpty)
    }
}
