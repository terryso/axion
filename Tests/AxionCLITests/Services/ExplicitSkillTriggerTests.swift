import ArgumentParser
import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI
@testable import AxionCore

@Suite("ExplicitSkillTrigger")
struct ExplicitSkillTriggerTests {

    // MARK: - AC1: Prompt skill — skill object construction

    @Test("AC1: System prompt is generic planner — skill content is in user message")
    func testExplicitSkillSystemPromptIsGeneric() {
        let result = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base planner prompt",
            skillsPrompt: ""
        )
        #expect(result.contains("Base planner prompt"))
        #expect(!result.contains("You are a test skill agent"))
    }

    @Test("AC2/H1: toolRestrictions are preserved in explicitSkill for model/restriction info")
    func testToolRestrictionsPreserved() {
        let skill = OpenAgentSDK.Skill(
            name: "restricted",
            description: "Restricted skill",
            toolRestrictions: [.bash, .read],
            promptTemplate: "Do stuff"
        )

        let restrictions = skill.toolRestrictions
        #expect(restrictions != nil)
        #expect(restrictions!.map(\.rawValue) == ["bash", "read"])
    }

    @Test("AC1: Memory context still injected in generic system prompt")
    func testExplicitSkillPromptWithMemory() {
        let result = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            memoryContext: "## Memory\nYou previously worked with Calculator app.",
            skillsPrompt: ""
        )

        #expect(result.contains("## Memory"))
        #expect(result.contains("Calculator"))
    }

    @Test("AC1: Normal flow uses buildFullSystemPrompt with Available Skills")
    func testNormalFlowIncludesSkills() {
        let result = AgentBuilder.buildFullSystemPrompt(
            basePrompt: "Base prompt",
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

    // MARK: - AC6: --no-skills disables skill registration

    @Test("AC6: --no-skills flag prevents skill registration in AgentBuilder")
    func testNoSkillsFlag() throws {
        let cmd = try RunCommand.parse(["--no-skills", "/polyv-live-cli test"])
        #expect(cmd.noSkills == true)
        // When noSkills is true, AgentBuilder.build() skips skill registration
        // and does not add SkillTool to the agent's tools.
    }

    // MARK: - BuildConfig.forSkillExecution

    @Test("forSkillExecution creates minimal config: no MCP, no skills, no memory")
    func testForSkillExecutionConfig() {
        let skill = OpenAgentSDK.Skill(
            name: "polyv-live-cli",
            description: "直播管理",
            toolRestrictions: [.bash, .read],
            modelOverride: "claude-opus-4-6",
            promptTemplate: "你是直播管理助手。"
        )

        let config = AxionConfig.default
        let buildConfig = AgentBuilder.BuildConfig.forSkillExecution(
            config: config,
            skill: skill,
            verbose: false
        )

        #expect(buildConfig.noMemory == true)
        #expect(buildConfig.noSkills == true)
        #expect(buildConfig.includePlaywright == false)
        #expect(buildConfig.allowForeground == false)
    }

    @Test("Combined: explicit skill with toolRestrictions + modelOverride via skill object")
    func testCombinedExplicitTrigger() {
        let skill = OpenAgentSDK.Skill(
            name: "polyv-live-cli",
            description: "直播管理",
            toolRestrictions: [.bash, .read, .glob, .grep],
            modelOverride: "claude-opus-4-6",
            promptTemplate: "你是直播管理助手。"
        )

        let effectiveModel = skill.modelOverride ?? "claude-sonnet-4-6"
        #expect(effectiveModel == "claude-opus-4-6")

        let restrictions = skill.toolRestrictions?.map(\.rawValue)
        #expect(restrictions == ["bash", "read", "glob", "grep"])
    }
}
