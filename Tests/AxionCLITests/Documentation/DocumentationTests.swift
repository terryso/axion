import Foundation
import Testing

/// Tests for Story 11.3: Developer documentation completeness and content validation.
/// Verifies that all required docs exist, have expected sections, and Examples README
/// contains the core scenario index.
///
/// These tests require the OpenAgentSDK repo to be present as a sibling directory
/// (../open-agent-sdk-swift) or via OPEN_AGENT_SDK_ROOT environment variable.
/// If the SDK is not found, all tests are silently skipped.
@Suite("Documentation Completeness Tests")
struct DocumentationTests {

    /// Resolve SDK root from environment variable or package root's sibling directory.
    /// Set OPEN_AGENT_SDK_ROOT to override detection (useful in CI).
    /// Default: assumes SDK is a sibling of this repo (../open-agent-sdk-swift).
    private var sdkRoot: String {
        if let env = ProcessInfo.processInfo.environment["OPEN_AGENT_SDK_ROOT"], !env.isEmpty {
            return env
        }
        // swift test runs from the package root (contains Package.swift)
        let packageRoot = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: packageRoot)
            .deletingLastPathComponent()
            .appendingPathComponent("open-agent-sdk-swift")
            .path
    }

    private var sdkDocsDir: String {
        "\(sdkRoot)/docs"
    }

    private var sdkExamplesDir: String {
        "\(sdkRoot)/Examples"
    }

    private var sdkIsAvailable: Bool {
        FileManager.default.fileExists(atPath: sdkRoot)
    }

    // MARK: - Task 9.1: Doc File Existence

    @Test("docs/getting-started.md exists and is non-empty")
    func gettingStartedExists() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/getting-started.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("docs/tool-development-guide.md exists and is non-empty")
    func toolDevGuideExists() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/tool-development-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("docs/mcp-integration-guide.md exists and is non-empty")
    func mcpGuideExists() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/mcp-integration-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("docs/agent-customization-guide.md exists and is non-empty")
    func agentCustomGuideExists() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/agent-customization-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("docs/session-memory-guide.md exists and is non-empty")
    func sessionMemoryGuideExists() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/session-memory-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("docs/packaging-distribution-guide.md exists and is non-empty")
    func packagingGuideExists() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/packaging-distribution-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(!content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Task 9.2: Doc Content Validation

    @Test("getting-started.md contains key sections")
    func gettingStartedContent() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/getting-started.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("createAgent"))  // API usage
        #expect(content.contains("AgentOptions"))  // Options type
        #expect(content.contains("swift"))  // Code examples
    }

    @Test("tool-development-guide.md contains defineTool documentation")
    func toolDevGuideContent() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/tool-development-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("defineTool"))  // Core API
        #expect(content.contains("ToolProtocol"))  // Interface
        #expect(content.contains("ToolContext"))  // Context
        #expect(content.contains("inputSchema"))  // Schema
    }

    @Test("mcp-integration-guide.md contains MCP config types")
    func mcpGuideContent() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/mcp-integration-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("McpServerConfig"))  // Config type
        #expect(content.contains("stdio") || content.contains("Stdio"))  // Transport mode
        #expect(content.contains("mcp__"))  // Namespace pattern
    }

    @Test("agent-customization-guide.md contains AgentOptions documentation")
    func agentCustomGuideContent() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/agent-customization-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("AgentOptions"))  // Main config type
        #expect(content.contains("PermissionMode"))  // Permission system
        #expect(content.contains("Hook"))  // Hook system
        #expect(content.contains("systemPrompt"))  // Prompt customization
    }

    @Test("session-memory-guide.md contains MemoryStore documentation")
    func sessionMemoryGuideContent() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/session-memory-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("MemoryStore") || content.contains("MemoryStoreProtocol"))
        #expect(content.contains("Session"))  // Session management
    }

    @Test("packaging-distribution-guide.md contains SPM and Homebrew sections")
    func packagingGuideContent() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkDocsDir)/packaging-distribution-guide.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("Package.swift") || content.contains("SPM"))
        #expect(content.contains("Homebrew") || content.contains("Formula"))
    }

    // MARK: - Task 9.3: Examples README Core Scenario Index

    @Test("Examples/README.md contains Core Scenario Quick Index")
    func examplesReadmeCoreScenarios() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkExamplesDir)/README.md")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("Core Scenario Quick Index"))
    }

    @Test("Examples/README.md covers all 5 core scenarios")
    func examplesReadmeCoversAllCoreScenarios() throws {
        guard sdkIsAvailable else { return }
        let url = URL(fileURLWithPath: "\(sdkExamplesDir)/README.md")
        let content = try String(contentsOf: url, encoding: .utf8)

        let coreScenarios = [
            "Basic Agent",
            "Custom Tool",
            "MCP Integration",
            "Session Management",
            "Memory",
        ]

        for scenario in coreScenarios {
            #expect(content.contains(scenario), "Examples README missing core scenario: \(scenario)")
        }
    }
}
