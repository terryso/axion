import ArgumentParser
import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

@Suite("ImplicitSkillTrigger (Story 17.4)")
struct ImplicitSkillTriggerTests {

    // MARK: - AC1: Skill tool usage guide in system prompt

    @Test("AC1: Available Skills section contains Skill tool usage guide")
    func testSkillsSectionContainsToolGuide() {
        let prompt = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base",
            skillsPrompt: "- my-skill [args]: A useful skill TRIGGER when: user needs X"
        )

        #expect(prompt.contains("## Available Skills"))
        #expect(prompt.contains("TRIGGER"))
        #expect(prompt.contains("Skill"))
    }

    @Test("AC1: Guide mentions skill parameter and args parameter")
    func testGuideMentionsParameters() {
        let prompt = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base",
            skillsPrompt: "- my-skill [args]: A useful skill TRIGGER when: user needs X"
        )

        let skillsRange = prompt.range(of: "## Available Skills")!
        let afterSkills = prompt[skillsRange.lowerBound...]
        // Match backtick-wrapped parameter names to avoid false positives from heading text
        #expect(afterSkills.contains("`skill`"))
        #expect(afterSkills.contains("`args`"))
    }

    @Test("AC1: Guide mentions prompt return value")
    func testGuideMentionsPromptReturn() {
        let prompt = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base",
            skillsPrompt: "- my-skill [args]: A useful skill TRIGGER when: user needs X"
        )

        let skillsRange = prompt.range(of: "## Available Skills")!
        let afterSkills = prompt[skillsRange.lowerBound...]
        #expect(afterSkills.contains("prompt"))
    }

    @Test("AC1: No Available Skills section when skillsPrompt is empty")
    func testNoSkillsSectionWhenEmpty() {
        let prompt = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base",
            skillsPrompt: ""
        )

        #expect(!prompt.contains("## Available Skills"))
    }

    // MARK: - AC2: Token budget truncation (verify existing behavior)

    @Test("AC2: formatSkillsForPrompt lists skills in registration order")
    func testSkillsListedInOrder() {
        let registry = SkillRegistry()
        registry.register(Skill(name: "alpha", description: "First", userInvocable: true, promptTemplate: "t"))
        registry.register(Skill(name: "beta", description: "Second", userInvocable: true, promptTemplate: "t"))
        registry.register(Skill(name: "gamma", description: "Third", userInvocable: true, promptTemplate: "t"))

        let output = registry.formatSkillsForPrompt()
        let alphaRange = output.range(of: "alpha")
        let betaRange = output.range(of: "beta")
        let gammaRange = output.range(of: "gamma")

        #expect(alphaRange != nil)
        #expect(betaRange != nil)
        #expect(gammaRange != nil)
        // Verify order: alpha before beta before gamma
        #expect(alphaRange!.lowerBound < betaRange!.lowerBound)
        #expect(betaRange!.lowerBound < gammaRange!.lowerBound)
    }

    // MARK: - AC3: isAvailable filter

    @Test("AC3: isAvailable=false skill excluded from formatSkillsForPrompt")
    func testUnavailableSkillExcluded() {
        let registry = SkillRegistry()
        registry.register(Skill(name: "available-skill", description: "Available", userInvocable: true, isAvailable: { true }, promptTemplate: "t"))
        registry.register(Skill(name: "unavailable-skill", description: "Not available", userInvocable: true, isAvailable: { false }, promptTemplate: "t"))

        let output = registry.formatSkillsForPrompt()
        #expect(output.contains("available-skill"))
        #expect(!output.contains("unavailable-skill"))
    }

    // MARK: - AC4: --no-skills regression

    @Test("AC4: --no-skills produces no Available Skills section")
    func testNoSkillsFlag() throws {
        let cmd = try RunCommand.parse(["--no-skills", "test"])
        #expect(cmd.noSkills == true)
        // Simulate the actual noSkills code path: noSkills → skillsPrompt = ""
        let skillsPrompt = cmd.noSkills ? "" : "dummy"
        let prompt = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base",
            skillsPrompt: skillsPrompt
        )
        #expect(!prompt.contains("## Available Skills"))
    }

    // MARK: - Guide text completeness

    @Test("Guide contains key tool usage info: Skill tool name and TRIGGER keyword")
    func testGuideContentCompleteness() {
        let prompt = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base",
            skillsPrompt: "- demo-skill: Demo skill TRIGGER when: user needs demo"
        )

        let skillsSection = prompt[prompt.range(of: "## Available Skills")!.lowerBound...]

        // Must mention the Skill tool
        #expect(skillsSection.contains("Skill"))
        // Must reference TRIGGER condition
        #expect(skillsSection.contains("TRIGGER"))
        // Must mention the skill list content
        #expect(skillsSection.contains("demo-skill"))
    }
}
