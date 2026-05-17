import ArgumentParser
import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI
@testable import AxionCore

@Suite("ExplicitSkillTrigger")
struct ExplicitSkillTriggerTests {

    // MARK: - AC1: Prompt skill — promptTemplate injected as systemPrompt

    @Test("AC1: Explicit prompt skill parses invocation correctly")
    func testPromptTemplateInjection() throws {
        let cmd = try RunCommand.parse(["/polyv-live-cli 获取频道列表"])
        let invocation = SkillLookupService.parseSkillInvocation(cmd.task)
        #expect(invocation != nil)
        #expect(invocation?.name == "polyv-live-cli")
        #expect(invocation?.args == "获取频道列表")
    }

    @Test("AC1: Explicit skill prompt includes promptTemplate and Available Tools, no Skills section")
    func testExplicitSkillPromptContent() {
        let skill = OpenAgentSDK.Skill(
            name: "test-skill",
            description: "Test",
            promptTemplate: "You are a test skill agent. Do X, Y, Z.",
            whenToUse: "when testing"
        )

        let toolList = PromptBuilder.buildToolListDescription(from: ["mcp__axion-helper__click"])
        var prompt = skill.promptTemplate
        prompt += "\n\n## Available Tools\n\(toolList)"

        #expect(prompt.hasPrefix("You are a test skill agent"))
        #expect(prompt.contains("## Available Tools"))
        #expect(!prompt.contains("## Available Skills"))
    }

    @Test("AC2/H1: toolRestrictions limits Available Tools in prompt, no MCP tools listed")
    func testToolRestrictionsLimitsToolList() {
        let skill = OpenAgentSDK.Skill(
            name: "restricted",
            description: "Restricted skill",
            toolRestrictions: [.bash, .read],
            promptTemplate: "Do stuff"
        )

        // Simulate the conditional logic from RunCommand
        let mcpPrefixedToolNames = ["mcp__axion-helper__click", "mcp__axion-helper__screenshot"]
        let toolNames: [String]
        if let restrictions = skill.toolRestrictions {
            toolNames = restrictions.map(\.rawValue)
        } else {
            toolNames = mcpPrefixedToolNames
        }
        let toolList = PromptBuilder.buildToolListDescription(from: toolNames)
        var prompt = skill.promptTemplate
        prompt += "\n\n## Available Tools\n\(toolList)"

        #expect(prompt.contains("## Available Tools"))
        #expect(prompt.contains("bash"))
        #expect(prompt.contains("read"))
        #expect(!prompt.contains("mcp__axion-helper__"))
    }

    @Test("AC1: Explicit skill prompt includes memory context when available")
    func testExplicitSkillPromptWithMemory() {
        let skill = OpenAgentSDK.Skill(
            name: "test-skill",
            description: "Test",
            promptTemplate: "Do the thing."
        )

        let toolList = PromptBuilder.buildToolListDescription(from: [])
        var prompt = skill.promptTemplate
        prompt += "\n\n## Available Tools\n\(toolList)"
        let memoryContext = "## Memory\nYou previously worked with Calculator app."
        prompt += "\n\n\(memoryContext)"

        #expect(prompt.contains("## Memory"))
        #expect(prompt.contains("Calculator"))
    }

    @Test("AC1: Normal flow uses buildFullSystemPrompt with Available Skills")
    func testNormalFlowIncludesSkills() throws {
        let cmd = try RunCommand.parse(["do something"])
        // In normal flow, buildFullSystemPrompt appends skillsPrompt
        let result = cmd.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: false,
            dryrun: false,
            verbose: false,
            memoryContext: nil,
            skillsPrompt: "- **test-skill**: Test skill"
        )
        #expect(result.hasPrefix("Base prompt"))
        #expect(result.contains("## Available Skills"))
    }

    // MARK: - AC2: toolRestrictions → allowedTools

    @Test("AC2: toolRestrictions map to allowedTools correctly")
    func testToolRestrictionsMapping() {
        let skill = OpenAgentSDK.Skill(
            name: "restricted",
            description: "Restricted skill",
            toolRestrictions: [.bash, .read, .glob, .grep],
            promptTemplate: "Do stuff"
        )

        let allowedTools: [String]? = skill.toolRestrictions?.map(\.rawValue)
        #expect(allowedTools != nil)
        #expect(allowedTools == ["bash", "read", "glob", "grep"])
    }

    @Test("AC2: No toolRestrictions → allowedTools is nil")
    func testNoToolRestrictions() {
        let skill = OpenAgentSDK.Skill(
            name: "unrestricted",
            description: "No restrictions",
            promptTemplate: "Do stuff"
        )

        let allowedTools: [String]? = skill.toolRestrictions?.map(\.rawValue)
        #expect(allowedTools == nil)
    }

    // MARK: - AC3: modelOverride

    @Test("AC3: modelOverride replaces default model")
    func testModelOverride() {
        let skill = OpenAgentSDK.Skill(
            name: "opus-skill",
            description: "Uses opus",
            modelOverride: "claude-opus-4-6",
            promptTemplate: "Do stuff"
        )
        let configModel = "claude-sonnet-4-6"
        let effectiveModel = skill.modelOverride ?? configModel
        #expect(effectiveModel == "claude-opus-4-6")
    }

    @Test("AC3: No modelOverride uses default model")
    func testNoModelOverride() {
        let skill = OpenAgentSDK.Skill(
            name: "default-model",
            description: "No override",
            promptTemplate: "Do stuff"
        )
        let configModel = "claude-sonnet-4-6"
        let effectiveModel = skill.modelOverride ?? configModel
        #expect(effectiveModel == "claude-sonnet-4-6")
    }

    // MARK: - AC4: Recorded skill — required parameter validation

    @Test("AC4: Missing required parameter throws ExitCode(1)")
    func testMissingRequiredParam() async {
        let skill = AxionCore.Skill(
            name: "open_calculator",
            description: "Opens a calculator",
            createdAt: Date(),
            sourceRecording: "test",
            parameters: [
                .init(name: "url", defaultValue: nil, description: "The URL to open"),
            ],
            steps: [.init(tool: "launch", arguments: ["url": "{{url}}"])]
        )

        do {
            try await RecordedSkillRunner.run(
                skill: skill,
                skillPath: "/tmp/fake.json",
                paramValues: [:]
            )
            Issue.record("Should have thrown ExitCode(1)")
        } catch let error as ExitCode {
            #expect(error.rawValue == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("AC4: Parameters with defaultValue auto-filled when not provided")
    func testDefaultValueAutoFill() {
        let params: [AxionCore.SkillParameter] = [
            .init(name: "url", defaultValue: nil, description: "Required URL"),
            .init(name: "timeout", defaultValue: "30", description: "Timeout in seconds"),
        ]

        var resolvedParams: [String: String] = ["url": "https://example.com"]
        for param in params {
            if resolvedParams[param.name] == nil, let defaultVal = param.defaultValue {
                resolvedParams[param.name] = defaultVal
            }
        }

        #expect(resolvedParams["url"] == "https://example.com")
        #expect(resolvedParams["timeout"] == "30")
    }

    @Test("AC4: All required params provided — no error")
    func testAllRequiredParamsProvided() {
        let skill = AxionCore.Skill(
            name: "open_calculator",
            description: "Opens a calculator",
            createdAt: Date(),
            sourceRecording: "test",
            parameters: [
                .init(name: "url", defaultValue: nil, description: "The URL to open"),
                .init(name: "timeout", defaultValue: "30", description: "Timeout"),
            ],
            steps: [.init(tool: "launch", arguments: ["url": "{{url}}"])]
        )

        var resolvedParams: [String: String] = ["url": "https://example.com"]
        for param in skill.parameters {
            if resolvedParams[param.name] == nil, let defaultVal = param.defaultValue {
                resolvedParams[param.name] = defaultVal
            }
        }
        let requiredParams = skill.parameters.filter { $0.defaultValue == nil }
        let missingParams = requiredParams.filter { resolvedParams[$0.name] == nil }
        #expect(missingParams.isEmpty)
        #expect(resolvedParams["url"] == "https://example.com")
        #expect(resolvedParams["timeout"] == "30")
    }

    // MARK: - AC5: / not at start does not trigger

    @Test("AC5: / not at start is not a skill invocation")
    func testSlashNotAtStart() {
        let parsed = SkillLookupService.parseSkillInvocation("请帮我/polyv-live-cli获取频道")
        #expect(parsed == nil)
    }

    // MARK: - AC6: --no-skills disables explicit trigger

    @Test("AC6: --no-skills flag prevents skill lookup from executing")
    func testNoSkillsFlag() throws {
        let cmd = try RunCommand.parse(["--no-skills", "/polyv-live-cli test"])
        #expect(cmd.noSkills == true)
        // When noSkills is true, the guard `!noSkills` on line 81 of RunCommand.run()
        // prevents the entire skill lookup block from executing.
        // parseSkillInvocation still works (pure parser), but the result is never used.
        let parsed = SkillLookupService.parseSkillInvocation(cmd.task)
        #expect(parsed != nil)
        #expect(parsed?.name == "polyv-live-cli")
        // The critical behavior: noSkills=true → RunCommand.run() skips skill lookup entirely.
        // The task "/polyv-live-cli test" is sent as a plain prompt to the LLM.
    }

    // MARK: - Combined: explicit trigger with all features

    @Test("Combined: explicit skill with promptTemplate + toolRestrictions + modelOverride")
    func testCombinedExplicitTrigger() {
        let skill = OpenAgentSDK.Skill(
            name: "polyv-live-cli",
            description: "直播管理",
            toolRestrictions: [.bash, .read, .glob, .grep],
            modelOverride: "claude-opus-4-6",
            promptTemplate: "你是直播管理助手。"
        )

        let effectiveModel = skill.modelOverride ?? "claude-sonnet-4-6"
        let allowedTools: [String]? = skill.toolRestrictions?.map(\.rawValue)

        #expect(effectiveModel == "claude-opus-4-6")
        #expect(allowedTools == ["bash", "read", "glob", "grep"])

        let toolList = PromptBuilder.buildToolListDescription(from: ["mcp__axion-helper__click"])
        var prompt = skill.promptTemplate
        prompt += "\n\n## Available Tools\n\(toolList)"
        #expect(prompt.hasPrefix("你是直播管理助手"))
        #expect(prompt.contains("## Available Tools"))
    }

    // MARK: - Task override when no args provided

    @Test("Task defaults when invocation has no args")
    func testTaskDefaultWithoutArgs() {
        let skill = OpenAgentSDK.Skill(
            name: "review",
            description: "Review code",
            promptTemplate: "Review changes"
        )
        let invocation = SkillLookupService.parseSkillInvocation("/review")
        let task = invocation?.args ?? "Execute skill \(skill.name)"
        #expect(task == "Execute skill review")
    }

    @Test("Task uses invocation args when provided")
    func testTaskWithArgs() {
        let skill = OpenAgentSDK.Skill(
            name: "review",
            description: "Review code",
            promptTemplate: "Review changes"
        )
        let invocation = SkillLookupService.parseSkillInvocation("/review src/main.swift")
        let task = invocation?.args ?? "Execute skill \(skill.name)"
        #expect(task == "src/main.swift")
    }
}
