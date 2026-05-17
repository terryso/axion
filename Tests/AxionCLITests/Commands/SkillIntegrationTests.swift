import Testing
import Foundation
import OpenAgentSDK

@testable import AxionCLI

@Suite("Skill Integration Tests (Story 17.1)")
struct SkillIntegrationTests {

    // MARK: - Helper: create temp SKILL.md

    private func createTempSkillDir(name: String, description: String, body: String = "Test skill body") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let skillMD = """
        ---
        name: \(name)
        description: \(description)
        ---

        \(body)
        """
        try! skillMD.write(to: tempDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return tempDir
    }

    // MARK: - AC1: Auto skill discovery and registration

    @Test("SkillLoader discovers skills from specified directory")
    func test_skillLoader_discoversSkills() {
        let tempDir = createTempSkillDir(name: "test-skill", description: "A test skill")
        let parentDir = tempDir.deletingLastPathComponent().path

        let skills = SkillLoader.discoverSkills(from: [parentDir])
        #expect(skills.count == 1)
        #expect(skills[0].name == "test-skill")
        #expect(skills[0].description == "A test skill")

        try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent())
    }

    @Test("SkillRegistry.registerDiscoveredSkills registers found skills")
    func test_registry_registerDiscoveredSkills() {
        let tempDir = createTempSkillDir(name: "reg-test", description: "Registry test skill")
        let parentDir = tempDir.deletingLastPathComponent().path

        let registry = SkillRegistry()
        let count = registry.registerDiscoveredSkills(from: [parentDir])

        #expect(count == 1)
        #expect(registry.find("reg-test") != nil)

        try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent())
    }

    // MARK: - AC2: SkillTool registration

    @Test("createSkillTool does not crash with non-empty registry")
    func test_skillTool_nonEmptyRegistry() {
        let registry = SkillRegistry()
        registry.register(Skill(name: "test-skill", description: "Test", promptTemplate: "template"))

        let tool = createSkillTool(registry: registry)
        #expect(tool.name == "Skill")
    }

    @Test("createSkillTool does not crash with empty registry")
    func test_skillTool_emptyRegistry() {
        let registry = SkillRegistry()
        let tool = createSkillTool(registry: registry)
        #expect(tool.name == "Skill")
    }

    // MARK: - AC3: Last-wins dedup

    @Test("Same-name skills in multiple directories use last-wins")
    func test_lastWins_deduplication() {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir1 = tempBase.appendingPathComponent("dir1").appendingPathComponent("dup-skill")
        let dir2 = tempBase.appendingPathComponent("dir2").appendingPathComponent("dup-skill")

        try! FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        let skill1 = """
        ---
        name: dup-skill
        description: First version
        ---

        Body 1
        """
        let skill2 = """
        ---
        name: dup-skill
        description: Second version
        ---

        Body 2
        """
        try! skill1.write(to: dir1.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try! skill2.write(to: dir2.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let registry = SkillRegistry()
        _ = registry.registerDiscoveredSkills(from: [
            dir1.deletingLastPathComponent().path,
            dir2.deletingLastPathComponent().path,
        ])

        let found = registry.find("dup-skill")
        #expect(found != nil)
        #expect(found?.description == "Second version")

        try? FileManager.default.removeItem(at: tempBase)
    }

    // MARK: - AC4: Empty directory does not affect runtime

    @Test("Empty skill directory produces empty registry")
    func test_emptyDirectory_emptyRegistry() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let registry = SkillRegistry()
        let count = registry.registerDiscoveredSkills(from: [tempDir.path])

        #expect(count == 0)
        #expect(registry.allSkills.isEmpty)

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - AC5: formatSkillsForPrompt output

    @Test("formatSkillsForPrompt includes registered skill description")
    func test_formatSkillsForPrompt_includesSkill() {
        let registry = SkillRegistry()
        registry.register(Skill(
            name: "my-skill",
            description: "Does something useful",
            userInvocable: true,
            promptTemplate: "template"
        ))

        let output = registry.formatSkillsForPrompt()
        #expect(output.contains("my-skill"))
        #expect(output.contains("Does something useful"))
    }

    @Test("formatSkillsForPrompt returns empty for no user-invocable skills")
    func test_formatSkillsForPrompt_empty() {
        let registry = SkillRegistry()
        let output = registry.formatSkillsForPrompt()
        #expect(output.isEmpty)
    }

    // MARK: - AC5: Skills prompt injected into system prompt

    @Test("buildFullSystemPrompt appends skills section")
    func test_buildFullSystemPrompt_withSkills() throws {
        let cmd = try RunCommand.parse(["test"])
        let prompt = cmd.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: false,
            dryrun: false,
            verbose: false,
            skillsPrompt: "- my-skill: A useful skill"
        )

        #expect(prompt.contains("## Available Skills"))
        #expect(prompt.contains("my-skill: A useful skill"))
    }

    @Test("buildFullSystemPrompt without skills does not append section")
    func test_buildFullSystemPrompt_withoutSkills() throws {
        let cmd = try RunCommand.parse(["test"])
        let prompt = cmd.buildFullSystemPrompt(
            basePrompt: "Base prompt",
            fast: false,
            dryrun: false,
            verbose: false,
            skillsPrompt: ""
        )

        #expect(!prompt.contains("## Available Skills"))
    }

    // MARK: - AC6: --no-skills mode

    @Test("--no-skills flag is parsed correctly")
    func test_noSkillsFlag() throws {
        let cmd = try RunCommand.parse(["--no-skills", "test task"])
        #expect(cmd.noSkills == true)

        let cmdNormal = try RunCommand.parse(["test task"])
        #expect(cmdNormal.noSkills == false)
    }

    @Test("No skills prompt when --no-skills mode")
    func test_noSkillsMode_noPromptInjection() throws {
        let cmd = try RunCommand.parse(["--no-skills", "test"])
        let prompt = cmd.buildFullSystemPrompt(
            basePrompt: "Base",
            fast: false,
            dryrun: false,
            verbose: false,
            skillsPrompt: ""
        )
        #expect(!prompt.contains("Available Skills"))
    }

    @Test("SkillTool is registered even when registry is empty (AC4)")
    func test_skillTool_registeredWithEmptyRegistry() {
        let registry = SkillRegistry()
        let tool = createSkillTool(registry: registry)
        #expect(tool.name == "Skill")
        #expect(registry.allSkills.isEmpty)
    }

    @Test("buildFullSystemPrompt with --no-skills produces no skills section even if skills exist")
    func test_noSkillsFlag_omitsSkillsFromPrompt() throws {
        let cmd = try RunCommand.parse(["--no-skills", "test"])
        #expect(cmd.noSkills == true)
        let prompt = cmd.buildFullSystemPrompt(
            basePrompt: "Base",
            fast: false,
            dryrun: false,
            verbose: false,
            skillsPrompt: ""
        )
        #expect(!prompt.contains("Available Skills"))
    }
}
