import Testing
import Foundation
@testable import AxionCLI
import AxionCore

private let SDK_BOUNDARY_AUDIT_COMPLETE = true
private let SDK_BOUNDARY_DOC_WRITTEN = true
private let SDK_API_USAGE_VERIFIED = true

@Suite("SDKBoundaryAudit")
struct SDKBoundaryAuditTests {

    /// 获取项目源文件根目录
    private func sourcesDirectory() -> String {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        return "\(currentDir)/Sources"
    }

    /// 递归获取目录下所有 .swift 文件
    private func swiftFiles(in directory: String) -> [String] {
        let fileManager = FileManager.default
        var result: [String] = []

        guard let enumerator = fileManager.enumerator(atPath: directory) else { return result }

        for case let file as String in enumerator {
            if file.hasSuffix(".swift") {
                result.append("\(directory)/\(file)")
            }
        }
        return result
    }

    /// 检查文件中是否包含指定 import 语句
    private func fileContainsImport(_ filePath: String, moduleName: String) -> Bool {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return false }
        let pattern = "^\\s*import\\s+\(moduleName)\\b"
        return content.range(of: pattern, options: .regularExpression) != nil
    }

    // ========================================================================
    // MARK: - [P0] AC1: import 审计 — AxionCore 无 import OpenAgentSDK
    // ========================================================================

    @Test("AxionCore has no import OpenAgentSDK")
    func axionCoreNoImportOpenAgentSDK() throws {
        guard SDK_BOUNDARY_AUDIT_COMPLETE else { return }

        let sourcesDir = sourcesDirectory()
        let coreDir = "\(sourcesDir)/AxionCore"
        let files = swiftFiles(in: coreDir)

        #expect(files.count > 0, "AxionCore should contain Swift source files")

        for file in files {
            let hasViolation = fileContainsImport(file, moduleName: "OpenAgentSDK")
            #expect(!hasViolation, "AxionCore file '\(file)' MUST NOT import OpenAgentSDK. Core is the pure model layer with zero external dependencies.")
        }
    }

    // ========================================================================
    // MARK: - [P0] AC1: import 审计 — AxionHelper 无 import OpenAgentSDK
    // ========================================================================

    @Test("AxionHelper has no import OpenAgentSDK")
    func axionHelperNoImportOpenAgentSDK() throws {
        guard SDK_BOUNDARY_AUDIT_COMPLETE else { return }

        let sourcesDir = sourcesDirectory()
        let helperDir = "\(sourcesDir)/AxionHelper"
        let files = swiftFiles(in: helperDir)

        #expect(files.count > 0, "AxionHelper should contain Swift source files")

        for file in files {
            let hasViolation = fileContainsImport(file, moduleName: "OpenAgentSDK")
            #expect(!hasViolation, "AxionHelper file '\(file)' MUST NOT import OpenAgentSDK. Helper only performs AX operations.")
        }
    }

    // ========================================================================
    // MARK: - [P0] AC1: import 审计 — AxionCLI 不 import AxionHelper
    // ========================================================================

    @Test("AxionCLI has no import AxionHelper")
    func axionCLINoImportAxionHelper() throws {
        guard SDK_BOUNDARY_AUDIT_COMPLETE else { return }

        let sourcesDir = sourcesDirectory()
        let cliDir = "\(sourcesDir)/AxionCLI"
        let files = swiftFiles(in: cliDir)

        #expect(files.count > 0, "AxionCLI should contain Swift source files")

        for file in files {
            let hasViolation = fileContainsImport(file, moduleName: "AxionHelper")
            #expect(!hasViolation, "AxionCLI file '\(file)' MUST NOT import AxionHelper. Communication is via MCP stdio only.")
        }
    }

    // ========================================================================
    // MARK: - [P0] AC1: SDK API 使用审计 — createAgent
    // ========================================================================

    @Test("RunCommand uses createAgent public API")
    func runCommandUsesCreateAgentPublicAPI() throws {
        guard SDK_API_USAGE_VERIFIED else { return }

        let sourcesDir = sourcesDirectory()
        let runCommandPath = "\(sourcesDir)/AxionCLI/Commands/RunCommand.swift"

        let content = try String(contentsOfFile: runCommandPath, encoding: .utf8)

        #expect(content.contains("createAgent("),
            "RunCommand MUST use createAgent() public API from OpenAgentSDK")
    }

    // ========================================================================
    // MARK: - [P1] AC1: SDK API 使用审计 — Agent.stream
    // ========================================================================

    @Test("RunCommand uses Agent.stream public API")
    func runCommandUsesAgentStreamPublicAPI() throws {
        guard SDK_API_USAGE_VERIFIED else { return }

        let sourcesDir = sourcesDirectory()
        let runCommandPath = "\(sourcesDir)/AxionCLI/Commands/RunCommand.swift"

        let content = try String(contentsOfFile: runCommandPath, encoding: .utf8)

        #expect(content.contains("agent.stream("),
            "RunCommand MUST use agent.stream() public API for execution")
    }

    // ========================================================================
    // MARK: - [P1] AC1: SDK API 使用审计 — McpStdioConfig
    // ========================================================================

    @Test("RunCommand uses McpStdioConfig for helper")
    func runCommandUsesMcpStdioConfigForHelper() throws {
        guard SDK_API_USAGE_VERIFIED else { return }

        let sourcesDir = sourcesDirectory()
        let runCommandPath = "\(sourcesDir)/AxionCLI/Commands/RunCommand.swift"

        let content = try String(contentsOfFile: runCommandPath, encoding: .utf8)

        #expect(content.contains("McpStdioConfig("),
            "RunCommand MUST use McpStdioConfig to configure Helper as MCP stdio server")
        #expect(content.contains("McpServerConfig"),
            "RunCommand MUST use McpServerConfig for MCP server configuration")
    }

    // ========================================================================
    // MARK: - [P1] AC1: SDK API 使用审计 — HookRegistry
    // ========================================================================

    @Test("RunCommand uses HookRegistry for safety check")
    func runCommandUsesHookRegistryForSafetyCheck() throws {
        guard SDK_API_USAGE_VERIFIED else { return }

        let sourcesDir = sourcesDirectory()
        let runCommandPath = "\(sourcesDir)/AxionCLI/Commands/RunCommand.swift"

        let content = try String(contentsOfFile: runCommandPath, encoding: .utf8)

        #expect(content.contains("HookRegistry"), "RunCommand MUST use HookRegistry for hook management")
        #expect(content.contains("HookDefinition"), "RunCommand MUST use HookDefinition for hook configuration")
        #expect(content.contains(".preToolUse"), "RunCommand MUST register preToolUse hook for safety checking")
    }

    // ========================================================================
    // MARK: - [P0] AC1: 反模式 — 无直接 Anthropic HTTP 调用
    // ========================================================================

    @Test("no direct Anthropic HTTP calls")
    func noDirectAnthropicHTTPCalls() throws {
        guard SDK_BOUNDARY_AUDIT_COMPLETE else { return }

        let sourcesDir = sourcesDirectory()
        let cliDir = "\(sourcesDir)/AxionCLI"
        let files = swiftFiles(in: cliDir)

        for file in files {
            let content = try String(contentsOfFile: file, encoding: .utf8)
            if content.contains("anthropic") && content.contains("URLSession") {
                Issue.record("File '\(file)' contains both 'anthropic' and 'URLSession' — direct Anthropic API calls are FORBIDDEN. Use OpenAgentSDK instead.")
            }
            if content.contains("import Anthropic") {
                Issue.record("File '\(file)' directly imports Anthropic — MUST use OpenAgentSDK public API instead.")
            }
        }
    }

    // ========================================================================
    // MARK: - [P1] AC2: SDK 边界文档 — 存在性检查
    // ========================================================================

    @Test("SDK boundary doc exists and is non-empty")
    func sdkBoundaryDocExistsAndNonEmpty() throws {
        guard SDK_BOUNDARY_DOC_WRITTEN else { return }

        let sourcesDir = sourcesDirectory()
        let docPath = "\(sourcesDir)/../docs/sdk-boundary.md"

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: docPath), "docs/sdk-boundary.md must exist")

        let attributes = try fileManager.attributesOfItem(atPath: docPath)
        let fileSize = attributes[.size] as? Int ?? 0
        #expect(fileSize > 0, "docs/sdk-boundary.md must not be empty")
    }

    // ========================================================================
    // MARK: - [P1] AC2: SDK 边界文档 — 内容章节检查
    // ========================================================================

    @Test("SDK boundary doc contains boundary table")
    func sdkBoundaryDocContainsBoundaryTable() throws {
        guard SDK_BOUNDARY_DOC_WRITTEN else { return }

        let sourcesDir = sourcesDirectory()
        let docPath = "\(sourcesDir)/../docs/sdk-boundary.md"

        let content = try String(contentsOfFile: docPath, encoding: .utf8)

        #expect(content.contains("SDK") && content.contains("应用层"),
            "SDK boundary doc must contain 'SDK' and '应用层' section describing the boundary")
        #expect(content.contains("Agent") && content.contains("SDK"),
            "SDK boundary doc must describe Agent module ownership")
    }

    @Test("SDK boundary doc contains API usage inventory")
    func sdkBoundaryDocContainsAPIUsageInventory() throws {
        guard SDK_BOUNDARY_DOC_WRITTEN else { return }

        let sourcesDir = sourcesDirectory()
        let docPath = "\(sourcesDir)/../docs/sdk-boundary.md"

        let content = try String(contentsOfFile: docPath, encoding: .utf8)

        #expect(content.contains("createAgent"), "SDK boundary doc must list createAgent in API usage inventory")
        #expect(content.contains("AgentOptions"), "SDK boundary doc must list AgentOptions in API usage inventory")
    }

    // ========================================================================
    // MARK: - [P2] AC3: SDK 短板记录 — 章节存在性检查
    // ========================================================================

    @Test("SDK boundary doc contains gap analysis section")
    func sdkBoundaryDocContainsGapAnalysisSection() throws {
        guard SDK_BOUNDARY_DOC_WRITTEN else { return }

        let sourcesDir = sourcesDirectory()
        let docPath = "\(sourcesDir)/../docs/sdk-boundary.md"

        let content = try String(contentsOfFile: docPath, encoding: .utf8)

        let hasGapSection = content.contains("短板") || content.contains("Gap") || content.contains("改进")
        #expect(hasGapSection, "SDK boundary doc must contain a gap analysis section (短板/Gaps)")
    }

    // ========================================================================
    // MARK: - [P1] Task 8: ToolNames 审计
    // ========================================================================

    @Test("ToolNames.allToolNames contains all registered tools")
    func toolNamesAllToolNamesContainsAllRegisteredTools() {
        let allNames = ToolNames.allToolNames

        #expect(allNames.count == 24, "ToolNames.allToolNames should contain exactly 24 tool names")

        let expectedTools = [
            "launch_app", "list_apps", "quit_app",
            "activate_window", "list_windows", "get_window_state",
            "move_window", "resize_window",
            "click", "double_click", "right_click",
            "type_text", "press_key", "hotkey",
            "scroll", "drag",
            "screenshot", "get_accessibility_tree",
            "open_url", "get_file_info"
        ]

        for tool in expectedTools {
            #expect(allNames.contains(tool), "ToolNames.allToolNames must contain '\(tool)'")
        }
    }

    @Test("ToolNames.foregroundToolNames correct classification")
    func toolNamesForegroundToolNamesCorrectClassification() {
        let foregroundTools = ToolNames.foregroundToolNames

        let expectedForeground: Set<String> = [
            "click", "double_click", "right_click",
            "type_text", "press_key", "hotkey",
            "scroll", "drag"
        ]

        #expect(foregroundTools == expectedForeground,
            "foregroundToolNames should match expected set of interactive tools")

        let readOnlyTools = ["launch_app", "list_apps", "screenshot", "get_accessibility_tree", "open_url"]
        for tool in readOnlyTools {
            #expect(!foregroundTools.contains(tool), "'\(tool)' should NOT be in foregroundToolNames")
        }
    }
}
