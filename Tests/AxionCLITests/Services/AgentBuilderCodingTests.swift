import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

// MARK: - loadClaudeMd Tests

@Suite("AgentBuilder.loadClaudeMd")
struct AgentBuilderLoadClaudeMdTests {

    /// Create an isolated temp home + cwd pair for testing.
    /// Returns `base` so callers can clean up the entire tree.
    private func makeTempDirs() throws -> (base: String, homeDir: String, cwdDir: String) {
        let base = NSTemporaryDirectory() + "axion-test-claudemd-\(UUID().uuidString)"
        let homeDir = base + "/home"
        let cwdDir = base + "/cwd"
        try FileManager.default.createDirectory(atPath: homeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: cwdDir, withIntermediateDirectories: true)
        return (base, homeDir, cwdDir)
    }

    private func cleanup(_ base: String) {
        try? FileManager.default.removeItem(atPath: base)
    }

    @Test("Returns empty string when no CLAUDE.md files exist")
    func test_noClaudeMdFiles_returnsEmpty() throws {
        let (base, homeDir, cwdDir) = try makeTempDirs()
        defer { cleanup(base) }

        let result = AgentBuilder.loadClaudeMd(cwd: cwdDir, homeDir: homeDir)
        #expect(result.isEmpty)
    }

    @Test("Merges all existing CLAUDE.md files")
    func test_allClaudeMdFiles_mergesContent() throws {
        let (base, homeDir, cwdDir) = try makeTempDirs()
        defer { cleanup(base) }

        // Create <homeDir>/.claude/CLAUDE.md (global)
        try FileManager.default.createDirectory(atPath: homeDir + "/.claude", withIntermediateDirectories: true)
        try "global instructions".write(
            toFile: homeDir + "/.claude/CLAUDE.md",
            atomically: true, encoding: .utf8
        )

        // Create <cwd>/CLAUDE.md
        try "root instructions".write(
            toFile: cwdDir + "/CLAUDE.md",
            atomically: true, encoding: .utf8
        )

        // Create <cwd>/.claude/CLAUDE.md
        try FileManager.default.createDirectory(atPath: cwdDir + "/.claude", withIntermediateDirectories: true)
        try "project team instructions".write(
            toFile: cwdDir + "/.claude/CLAUDE.md",
            atomically: true, encoding: .utf8
        )

        // Create <cwd>/.axion/instructions.md
        try FileManager.default.createDirectory(atPath: cwdDir + "/.axion", withIntermediateDirectories: true)
        try "axion-specific instructions".write(
            toFile: cwdDir + "/.axion/instructions.md",
            atomically: true, encoding: .utf8
        )

        let result = AgentBuilder.loadClaudeMd(cwd: cwdDir, homeDir: homeDir)
        #expect(result.contains("global instructions"))
        #expect(result.contains("root instructions"))
        #expect(result.contains("project team instructions"))
        #expect(result.contains("axion-specific instructions"))
        #expect(result.contains("## 项目指令"))
    }

    @Test("Correctly merges partial files when only some exist")
    func test_partialClaudeMdFiles_mergesExisting() throws {
        let (base, homeDir, cwdDir) = try makeTempDirs()
        defer { cleanup(base) }

        // Only create <cwd>/CLAUDE.md
        try "only root".write(
            toFile: cwdDir + "/CLAUDE.md",
            atomically: true, encoding: .utf8
        )

        let result = AgentBuilder.loadClaudeMd(cwd: cwdDir, homeDir: homeDir)
        #expect(result.contains("only root"))
        #expect(!result.contains("project team"))
        #expect(!result.contains("axion-specific"))
    }

    @Test("Skips empty files")
    func test_emptyClaudeMdFiles_skipped() throws {
        let (base, homeDir, cwdDir) = try makeTempDirs()
        defer { cleanup(base) }

        // Create empty CLAUDE.md
        try "   \n  ".write(
            toFile: cwdDir + "/CLAUDE.md",
            atomically: true, encoding: .utf8
        )

        let result = AgentBuilder.loadClaudeMd(cwd: cwdDir, homeDir: homeDir)
        #expect(result.isEmpty)
    }

    @Test("Wraps each file with header containing filename")
    func test_fileHeader_containsFilename() throws {
        let (base, homeDir, cwdDir) = try makeTempDirs()
        defer { cleanup(base) }

        try "content here".write(
            toFile: cwdDir + "/CLAUDE.md",
            atomically: true, encoding: .utf8
        )

        let result = AgentBuilder.loadClaudeMd(cwd: cwdDir, homeDir: homeDir)
        #expect(result.contains("## 项目指令 (CLAUDE.md)"))
        #expect(result.contains("content here"))
    }
}

// MARK: - BuildConfig.forChat Tests

@Suite("AgentBuilder.BuildConfig.forChat")
struct BuildConfigForChatTests {

    private func makeConfig() -> AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    @Test("Returns desktopAutomation mode (unified with run)")
    func test_forChat_returnsDesktopAutomationMode() throws {
        let buildConfig = AgentBuilder.BuildConfig.forChat(config: makeConfig())
        #expect(buildConfig.mode == AgentBuilder.AgentMode.desktopAutomation)
    }

    @Test("Returns maxTokens 131072 (128K)")
    func test_forChat_returns128KMaxTokens() throws {
        let buildConfig = AgentBuilder.BuildConfig.forChat(config: makeConfig())
        #expect(buildConfig.maxTokens == 131_072)
    }

    @Test("forCLI returns desktopAutomation mode")
    func test_forCLI_returnsDesktopAutomationMode() throws {
        let buildConfig = AgentBuilder.BuildConfig.forCLI(config: makeConfig(), task: "test")
        #expect(buildConfig.mode == AgentBuilder.AgentMode.desktopAutomation)
    }

    @Test("forChat includes Playwright (unified with run)")
    func test_forChat_includesPlaywright() throws {
        let buildConfig = AgentBuilder.BuildConfig.forChat(config: makeConfig())
        #expect(buildConfig.includePlaywright == true)
    }

    @Test("forChat passes through optional parameters")
    func test_forChat_passesOptionalParams() throws {
        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: makeConfig(),
            noMemory: true,
            noSkills: true,
            maxSteps: 50,
            verbose: true
        )
        #expect(buildConfig.noMemory == true)
        #expect(buildConfig.noSkills == true)
        #expect(buildConfig.maxSteps == 50)
        #expect(buildConfig.verbose == true)
    }
}

// MARK: - Unified Prompt Content Tests

@Suite("Unified System Prompt Content")
struct UnifiedPromptContentTests {

    @Test("Unified prompt template exists and loads")
    func test_unifiedPromptTemplate_loads() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20", "cwd": "/tmp/test"],
            fromDirectory: promptDir
        )
        #expect(!content.isEmpty)
        #expect(content.contains("general-purpose"))
    }

    @Test("Unified prompt contains both coding and desktop automation capabilities")
    func test_unifiedPrompt_hasCodingAndDesktopCapabilities() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20", "cwd": "/tmp/test"],
            fromDirectory: promptDir
        )
        // Coding capabilities merged from the former coding-agent prompt
        #expect(content.contains("LSP"))
        #expect(content.contains("Working Directory"))
        // Desktop automation capabilities (inherited from the desktop prompt)
        let lowered = content.lowercased()
        #expect(lowered.contains("screenshot"))
        #expect(lowered.contains("launch_app"))
        #expect(lowered.contains("click"))
    }

    @Test("Unified prompt resolves cwd variable placeholder")
    func test_unifiedPrompt_hasCwdVariable() throws {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let testCwd = "/Users/test/project"
        let content = try PromptBuilder.load(
            name: "planner-system",
            variables: ["tools": "test", "max_steps": "20", "cwd": testCwd],
            fromDirectory: promptDir
        )
        #expect(content.contains(testCwd))
        #expect(!content.contains("{{cwd}}"))
    }

}

// MARK: - Unified Agent MCP Tests

@Suite("Unified Agent MCP Configuration")
struct UnifiedAgentMCPTests {

    private func makeConfig() -> AxionConfig {
        AxionConfig(apiKey: "sk-test")
    }

    @Test("forChat now loads desktop automation MCP (unified with run)")
    func test_forChat_hasDesktopAutomation() throws {
        // After unification, chat shares MCP with run: desktopAutomation mode + Playwright.
        let buildConfig = AgentBuilder.BuildConfig.forChat(config: makeConfig())
        #expect(buildConfig.mode == AgentBuilder.AgentMode.desktopAutomation)
        #expect(buildConfig.includePlaywright == true)
    }

    @Test("forCLI still has desktop automation mode")
    func test_forCLI_stillDesktop() throws {
        let buildConfig = AgentBuilder.BuildConfig.forCLI(config: makeConfig(), task: "test")
        #expect(buildConfig.mode == AgentBuilder.AgentMode.desktopAutomation)
        #expect(buildConfig.includePlaywright == true)
    }
}
