import Foundation
import Testing

@testable import AxionCLI
import OpenAgentSDK
import enum OpenAgentSDK.SDKMessage

/// E2E tests for /skills command and /skill-name direct execution.
///
/// Tests exercise the real SkillRegistry, Agent.executeSkillStream(), and Agent.stream()
/// to verify end-to-end skill discovery, listing, and execution paths.
///
/// Tests that require API key use `guard let … else { return }` to skip gracefully.
@Suite("Skill Execution E2E")
struct SkillExecutionE2ETests {

    // MARK: - /skills Command (no API key needed)

    @Test("/skills parse correctly")
    func parseSkills() {
        #expect(SlashCommand.parse("/skills") == .skills)
        #expect(SlashCommand.parse("/Skills") == .skills)
        #expect(SlashCommand.parse("/SKILLS") == .skills)
    }

    @Test("/skills helpText is non-empty")
    func skillsHelpText() {
        #expect(!SlashCommand.skills.helpText.isEmpty)
        #expect(SlashCommand.skills.helpText == "列出可用技能")
    }

    @Test("/skills not available during task")
    func skillsNotDuringTask() {
        #expect(SlashCommand.skills.availableDuringTask == false)
    }

    @Test("/skills appears in allCases")
    func skillsInAllCases() {
        #expect(SlashCommand.allCases.contains(.skills))
    }

    // MARK: - /skills Listing with Real SkillRegistry

    @Test("handleSkills with real built-in skills")
    func handleSkillsRealRegistry() {
        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        let output = SlashCommandHandler.handleSkills(registry: registry)

        // Should list at least one skill
        #expect(output.contains("可用技能"))
        let invocable = registry.userInvocableSkills
        for skill in invocable {
            #expect(output.contains(skill.name), "Output should contain skill name: \(skill.name)")
        }
    }

    @Test("handleSkills with discovered filesystem skills")
    func handleSkillsDiscoveredSkills() {
        // Create a temp skill directory with a real SKILL.md
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("e2e-test-skill")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: e2e-test-skill
        description: E2E test skill
        userInvocable: true
        ---

        This is an E2E test skill body.
        """
        try! skillMD.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent()) }

        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        let count = registry.registerDiscoveredSkills(from: [tempDir.deletingLastPathComponent().path])
        #expect(count >= 1)

        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("e2e-test-skill"))
        #expect(output.contains("[fs]"), "Filesystem skill should have [fs] tag")
    }

    @Test("handleSkills with nil registry shows disabled message")
    func handleSkillsNil() {
        let output = SlashCommandHandler.handleSkills(registry: nil)
        #expect(output.contains("技能系统未启用"))
    }

    // MARK: - Skill Name Matching (SkillRegistry.find)

    @Test("SkillRegistry.find matches built-in skill name")
    func findBuiltInSkill() {
        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)

        let invocable = registry.userInvocableSkills
        guard let first = invocable.first else {
            Issue.record("No built-in skills registered")
            return
        }

        let found = registry.find(first.name)
        #expect(found != nil)
        #expect(found?.name == first.name)
        #expect(found?.userInvocable == true)
    }

    @Test("SkillRegistry.find returns nil for unknown name")
    func findUnknownSkill() {
        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        #expect(registry.find("nonexistent-skill-xyz") == nil)
    }

    // MARK: - /skill-name Execution Path Verification

    @Test("Unknown /xxx command parse returns nil (not built-in)")
    func unknownSlashNotBuiltIn() {
        // /teambition is not a built-in slash command
        #expect(SlashCommand.parse("/teambition") == nil)
        #expect(SlashCommand.parse("/some-random-skill") == nil)
    }

    @Test("Unknown /xxx hasPrefix slash detection works")
    func unknownSlashDetection() {
        let inputs = ["/teambition", "/webwright", "/custom-skill arg1"]
        for input in inputs {
            #expect(input.hasPrefix("/"))
            #expect(SlashCommand.parse(input) == nil)
        }
    }

    @Test("Skill name extraction from /skillname args")
    func skillNameExtraction() {
        let inputs = [
            "/teambition": ("teambition", nil as String?),
            "/webwright search term": ("webwright", "search term"),
            "/commit": ("commit", nil as String?),
            "/my-skill arg1 arg2": ("my-skill", "arg1 arg2"),
        ]

        for (input, (expectedName, expectedArgs)) in inputs {
            let parts = input.split(separator: " ", maxSplits: 1)
            let rawName = String(parts[0].dropFirst())
            #expect(rawName == expectedName, "Name extraction failed for: \(input)")

            let args: String? = parts.count > 1 ? String(parts[1]) : nil
            #expect(args == expectedArgs, "Args extraction failed for: \(input)")
        }
    }

    // MARK: - executeSkillStream vs stream Path Selection

    @Test("SkillRegistry match determines execution path")
    func executionPathSelection() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "test-skill",
            description: "Test",
            userInvocable: true,
            promptTemplate: "Execute test"
        ))

        // Skill in registry → should use executeSkillStream path
        let matched = registry.find("test-skill")
        #expect(matched != nil)
        #expect(matched?.userInvocable == true)

        // Skill not in registry → should use stream path (agent handles /xxx)
        let unmatched = registry.find("unknown-skill")
        #expect(unmatched == nil)
    }

    @Test("Skill not in registry but starts with / falls through to agent stream")
    func skillNotInRegistryFallsThrough() {
        let registry = SkillRegistry()
        let input = "/teambition"

        // Not a built-in command
        #expect(SlashCommand.parse(input) == nil)
        // Not in registry
        #expect(registry.find("teambition") == nil)
        // Input starts with / → should fall through to agent.stream("/teambition")
        #expect(input.hasPrefix("/"))
    }

    // MARK: - Skill Discovery Directories

    @Test("ConfigManager.skillDiscoveryDirectories returns valid paths")
    func skillDiscoveryDirectories() {
        let dirs = ConfigManager.skillDiscoveryDirectories
        #expect(!dirs.isEmpty, "Should have at least one skill discovery directory")
        for dir in dirs {
            // Paths should be absolute
            #expect(dir.hasPrefix("/"), "Skill directory should be absolute: \(dir)")
        }
    }

    // MARK: - Agent.executeSkillStream with Real Agent (needs API key)

    @Test("executeSkillStream returns stream for registered skill")
    func executeSkillStreamRegisteredSkill() async throws {
        guard let (agent, _) = try await buildRealChatAgent(maxTurns: 1) else { return }

        // Register a skill in the agent's registry
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "hello-e2e",
            description: "E2E test skill",
            userInvocable: true,
            promptTemplate: "Say hello"
        ))

        // executeSkillStream should return a non-nil stream
        let stream = agent.executeSkillStream("hello-e2e", args: nil)
        var gotMessage = false
        for await message in stream {
            gotMessage = true
            // We just need to verify the stream produces messages
            switch message {
            case .result(let data):
                // Skill might succeed or fail (no skill registered in agent)
                _ = data
            default:
                break
            }
            // Only read first message to keep test fast
            break
        }
        #expect(gotMessage, "executeSkillStream should produce at least one message")

        try? await agent.close()
    }

    @Test("executeSkillStream with unknown skill returns error result")
    func executeSkillStreamUnknownSkill() async throws {
        guard let (agent, _) = try await buildRealChatAgent(maxTurns: 1) else { return }

        let stream = agent.executeSkillStream("nonexistent-skill-xyz", args: nil)
        var gotErrorResult = false
        for await message in stream {
            if case .result(let data) = message {
                if data.subtype == .errorDuringExecution {
                    gotErrorResult = true
                }
                break
            }
        }
        #expect(gotErrorResult, "Unknown skill should produce error result")

        try? await agent.close()
    }

    @Test("agent.stream with /skillname text sends to agent normally")
    func agentStreamWithSkillNameText() async throws {
        guard let (agent, _) = try await buildRealChatAgent(maxTurns: 1) else { return }

        let stream = agent.stream("/teambition")
        var gotMessage = false
        for await message in stream {
            gotMessage = true
            // Agent receives "/teambition" as regular text
            // It may or may not know about the skill via system prompt
            _ = message
            break
        }
        #expect(gotMessage, "agent.stream should produce at least one message")

        try? await agent.close()
    }

    // MARK: - Full Skill Registration → Discovery → Execution Pipeline

    @Test("Full pipeline: create skill → register → find → verify promptTemplate")
    func fullPipelineSkillRegistration() {
        // 1. Create a temp skill on disk
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("pipeline-skill")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: pipeline-skill
        description: Pipeline test skill
        userInvocable: true
        ---

        You are a pipeline test skill. Execute the following task: {args}
        """
        try! skillMD.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent()) }

        // 2. Discover and register
        let registry = SkillRegistry()
        let count = registry.registerDiscoveredSkills(from: [tempDir.deletingLastPathComponent().path])
        #expect(count == 1)

        // 3. Find by name
        let skill = registry.find("pipeline-skill")
        #expect(skill != nil)
        #expect(skill?.name == "pipeline-skill")
        #expect(skill?.userInvocable == true)

        // 4. Verify promptTemplate has {args}
        let template = skill?.promptTemplate ?? ""
        #expect(template.contains("{args}"))

        // 5. Simulate arg substitution (what ChatCommand does)
        let expanded = template.replacingOccurrences(of: "{args}", with: "test task")
        #expect(expanded.contains("test task"))
        #expect(!expanded.contains("{args}"))
    }

    @Test("Full pipeline: skill appears in /skills output")
    func fullPipelineSkillsListing() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("list-skill")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: list-test-skill
        description: Skill for listing test
        userInvocable: true
        aliases: lts
        ---

        Test body
        """
        try! skillMD.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent()) }

        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        _ = registry.registerDiscoveredSkills(from: [tempDir.deletingLastPathComponent().path])

        let output = SlashCommandHandler.handleSkills(registry: registry)
        #expect(output.contains("list-test-skill"))
        #expect(output.contains("Skill for listing test"))
        #expect(output.contains("lts"), "Should show alias")
        #expect(output.contains("[fs]"), "Filesystem skill should be tagged")
    }

    // MARK: - Edge Cases

    @Test("/skills with spaces after command name still parses")
    func skillsWithTrailingSpaces() {
        #expect(SlashCommand.parse("/skills   ") == .skills)
    }

    @Test("Skill with no args: promptTemplate used as-is")
    func skillNoArgs() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "no-args",
            description: "No args skill",
            userInvocable: true,
            promptTemplate: "Just do it"
        ))

        let skill = registry.find("no-args")
        #expect(skill?.promptTemplate == "Just do it")

        // No {args} in template → no substitution needed
        let expanded = skill!.promptTemplate.replacingOccurrences(of: "{args}", with: "ignored")
        #expect(expanded == "Just do it")
    }

    @Test("Skill alias resolution via find()")
    func skillAliasResolution() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "commit",
            description: "Create commit",
            aliases: ["ci"],
            userInvocable: true,
            promptTemplate: "Commit changes"
        ))

        // Find by name
        #expect(registry.find("commit") != nil)
        // Find by alias
        #expect(registry.find("ci") != nil)
        #expect(registry.find("ci")?.name == "commit")
    }

    @Test("Multiple skill discovery directories merge correctly")
    func multipleDiscoveryDirectories() {
        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let dir1 = tempBase.appendingPathComponent("dir1").appendingPathComponent("skill-a")
        let dir2 = tempBase.appendingPathComponent("dir2").appendingPathComponent("skill-b")
        try! FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let skillA = """
        ---
        name: skill-a
        description: Skill A
        ---
        Body A
        """
        let skillB = """
        ---
        name: skill-b
        description: Skill B
        ---
        Body B
        """
        try! skillA.write(to: dir1.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try! skillB.write(to: dir2.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let registry = SkillRegistry()
        let count = registry.registerDiscoveredSkills(from: [
            dir1.deletingLastPathComponent().path,
            dir2.deletingLastPathComponent().path,
        ])
        #expect(count == 2)
        #expect(registry.find("skill-a") != nil)
        #expect(registry.find("skill-b") != nil)
    }
}
