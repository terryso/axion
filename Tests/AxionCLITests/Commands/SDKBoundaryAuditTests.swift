import XCTest
import Foundation
@testable import AxionCLI
import AxionCore

// [P0] 基础设施验证 — SDK 边界审计
// [P1] 行为验证 — 文档与结构合规性检查
// Story 3.8: SDK 边界文档与端到端验证
// ATDD RED PHASE — 审计测试验证 SDK 集成边界合规

/// ATDD 开关。
/// SDK 边界审计测试。
/// - `SDK_BOUNDARY_AUDIT_COMPLETE`: AC1 import 审计已完成
/// - `SDK_BOUNDARY_DOC_WRITTEN`: AC2/AC3 文档已编写
/// - `SDK_API_USAGE_VERIFIED`: AC1 SDK API 使用审计已完成
private let SDK_BOUNDARY_AUDIT_COMPLETE = true
private let SDK_BOUNDARY_DOC_WRITTEN = true
private let SDK_API_USAGE_VERIFIED = true

final class SDKBoundaryAuditTests: XCTestCase {

    // MARK: - 测试辅助

    private func skipUntilAuditComplete() throws {
        if !SDK_BOUNDARY_AUDIT_COMPLETE {
            throw XCTSkip("ATDD RED PHASE: SDK 边界审计尚未完成。完成审计后将 SDK_BOUNDARY_AUDIT_COMPLETE 改为 true。")
        }
    }

    private func skipUntilDocWritten() throws {
        if !SDK_BOUNDARY_DOC_WRITTEN {
            throw XCTSkip("ATDD RED PHASE: SDK 边界文档尚未编写。完成文档后将 SDK_BOUNDARY_DOC_WRITTEN 改为 true。")
        }
    }

    private func skipUntilAPIUsageVerified() throws {
        if !SDK_API_USAGE_VERIFIED {
            throw XCTSkip("ATDD RED PHASE: SDK API 使用审计尚未完成。完成审计后将 SDK_API_USAGE_VERIFIED 改为 true。")
        }
    }

    /// 获取项目源文件根目录
    private func sourcesDirectory() -> String {
        // 从测试 bundle 位置推算 Sources 目录
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
        // 匹配 import 语句（行首或空白后 + import + 空格 + 模块名）
        let pattern = "^\\s*import\\s+\(moduleName)\\b"
        return content.range(of: pattern, options: .regularExpression) != nil
    }

    // ========================================================================
    // MARK: - [P0] AC1: import 审计 — AxionCore 无 import OpenAgentSDK
    // ========================================================================

    /// 3.8-UNIT-001: AxionCore 所有源文件不包含 `import OpenAgentSDK`
    /// AxionCore 是纯模型层，零外部依赖。如果发现违规 import，说明模块边界被破坏。
    func test_axionCore_noImportOpenAgentSDK() throws {
        try skipUntilAuditComplete()

        let sourcesDir = sourcesDirectory()
        let coreDir = "\(sourcesDir)/AxionCore"
        let files = swiftFiles(in: coreDir)

        XCTAssertGreaterThan(files.count, 0, "AxionCore should contain Swift source files")

        for file in files {
            let hasViolation = fileContainsImport(file, moduleName: "OpenAgentSDK")
            XCTAssertFalse(hasViolation, "AxionCore file '\(file)' MUST NOT import OpenAgentSDK. Core is the pure model layer with zero external dependencies.")
        }
    }

    // ========================================================================
    // MARK: - [P0] AC1: import 审计 — AxionHelper 无 import OpenAgentSDK
    // ========================================================================

    /// 3.8-UNIT-002: AxionHelper 所有源文件不包含 `import OpenAgentSDK`
    /// Helper 只做 AX 操作，不使用 SDK。SDK 由 AxionCLI 层使用。
    func test_axionHelper_noImportOpenAgentSDK() throws {
        try skipUntilAuditComplete()

        let sourcesDir = sourcesDirectory()
        let helperDir = "\(sourcesDir)/AxionHelper"
        let files = swiftFiles(in: helperDir)

        XCTAssertGreaterThan(files.count, 0, "AxionHelper should contain Swift source files")

        for file in files {
            let hasViolation = fileContainsImport(file, moduleName: "OpenAgentSDK")
            XCTAssertFalse(hasViolation, "AxionHelper file '\(file)' MUST NOT import OpenAgentSDK. Helper only performs AX operations.")
        }
    }

    // ========================================================================
    // MARK: - [P0] AC1: import 审计 — AxionCLI 不 import AxionHelper
    // ========================================================================

    /// 3.8-UNIT-003: AxionCLI 所有源文件不包含 `import AxionHelper`
    /// AxionCLI 与 AxionHelper 仅通过 MCP stdio JSON-RPC 通信（由 SDK 管理）。
    func test_axionCLI_noImportAxionHelper() throws {
        try skipUntilAuditComplete()

        let sourcesDir = sourcesDirectory()
        let cliDir = "\(sourcesDir)/AxionCLI"
        let files = swiftFiles(in: cliDir)

        XCTAssertGreaterThan(files.count, 0, "AxionCLI should contain Swift source files")

        for file in files {
            let hasViolation = fileContainsImport(file, moduleName: "AxionHelper")
            XCTAssertFalse(hasViolation, "AxionCLI file '\(file)' MUST NOT import AxionHelper. Communication is via MCP stdio only.")
        }
    }

    // ========================================================================
    // MARK: - [P0] AC1: SDK API 使用审计 — createAgent
    // ========================================================================

    /// 3.8-UNIT-004: RunCommand 使用 createAgent() 公共 API 创建 Agent
    /// 这是 SDK 集成的核心入口点 — 绕过 SDK 直接调用 LLM 是违规的。
    func test_runCommand_usesCreateAgentPublicAPI() throws {
        try skipUntilAPIUsageVerified()

        let sourcesDir = sourcesDirectory()
        let runCommandPath = "\(sourcesDir)/AxionCLI/Commands/RunCommand.swift"

        let content = try String(contentsOfFile: runCommandPath, encoding: .utf8)

        // 验证 RunCommand 使用 createAgent() 函数
        XCTAssertTrue(content.contains("createAgent("),
                       "RunCommand MUST use createAgent() public API from OpenAgentSDK")
    }

    // ========================================================================
    // MARK: - [P1] AC1: SDK API 使用审计 — Agent.stream
    // ========================================================================

    /// 3.8-UNIT-005: RunCommand 使用 Agent.stream() 公共 API 启动流式执行
    func test_runCommand_usesAgentStreamPublicAPI() throws {
        try skipUntilAPIUsageVerified()

        let sourcesDir = sourcesDirectory()
        let runCommandPath = "\(sourcesDir)/AxionCLI/Commands/RunCommand.swift"

        let content = try String(contentsOfFile: runCommandPath, encoding: .utf8)

        XCTAssertTrue(content.contains("agent.stream("),
                       "RunCommand MUST use agent.stream() public API for execution")
    }

    // ========================================================================
    // MARK: - [P1] AC1: SDK API 使用审计 — McpStdioConfig
    // ========================================================================

    /// 3.8-UNIT-006: RunCommand 使用 McpStdioConfig 配置 Helper 为 MCP stdio server
    func test_runCommand_usesMcpStdioConfigForHelper() throws {
        try skipUntilAPIUsageVerified()

        let sourcesDir = sourcesDirectory()
        let runCommandPath = "\(sourcesDir)/AxionCLI/Commands/RunCommand.swift"

        let content = try String(contentsOfFile: runCommandPath, encoding: .utf8)

        XCTAssertTrue(content.contains("McpStdioConfig("),
                       "RunCommand MUST use McpStdioConfig to configure Helper as MCP stdio server")
        XCTAssertTrue(content.contains("McpServerConfig"),
                       "RunCommand MUST use McpServerConfig for MCP server configuration")
    }

    // ========================================================================
    // MARK: - [P1] AC1: SDK API 使用审计 — HookRegistry
    // ========================================================================

    /// 3.8-UNIT-007: RunCommand 使用 HookRegistry + preToolUse hook 实现安全检查
    func test_runCommand_usesHookRegistryForSafetyCheck() throws {
        try skipUntilAPIUsageVerified()

        let sourcesDir = sourcesDirectory()
        let runCommandPath = "\(sourcesDir)/AxionCLI/Commands/RunCommand.swift"

        let content = try String(contentsOfFile: runCommandPath, encoding: .utf8)

        XCTAssertTrue(content.contains("HookRegistry"),
                       "RunCommand MUST use HookRegistry for hook management")
        XCTAssertTrue(content.contains("HookDefinition"),
                       "RunCommand MUST use HookDefinition for hook configuration")
        XCTAssertTrue(content.contains(".preToolUse"),
                       "RunCommand MUST register preToolUse hook for safety checking")
    }

    // ========================================================================
    // MARK: - [P0] AC1: 反模式 — 无直接 Anthropic HTTP 调用
    // ========================================================================

    /// 3.8-UNIT-008: 代码中无绕过 SDK 的直接 Anthropic API 调用
    /// 检查所有 AxionCLI 源文件中不包含直接 HTTP 调用 Anthropic 的模式。
    func test_noDirectAnthropicHTTPCalls() throws {
        try skipUntilAuditComplete()

        let sourcesDir = sourcesDirectory()
        let cliDir = "\(sourcesDir)/AxionCLI"
        let files = swiftFiles(in: cliDir)

        // 排除合法的 SDK import 文件
        let forbiddenPatterns = [
            "api.anthropic.com",
            "URLSession",  // 不应有直接的 HTTP 请求到 Anthropic
            "import Anthropic",  // 不应直接 import Anthropic SDK
        ]

        for file in files {
            let content = try String(contentsOfFile: file, encoding: .utf8)
            // 只检查包含 anthropic 的文件中的 URLSession 调用
            if content.contains("anthropic") && content.contains("URLSession") {
                XCTFail("File '\(file)' contains both 'anthropic' and 'URLSession' — direct Anthropic API calls are FORBIDDEN. Use OpenAgentSDK instead.")
            }
            // 检查是否直接 import Anthropic
            if content.contains("import Anthropic") {
                XCTFail("File '\(file)' directly imports Anthropic — MUST use OpenAgentSDK public API instead.")
            }
        }
    }

    // ========================================================================
    // MARK: - [P1] AC2: SDK 边界文档 — 存在性检查
    // ========================================================================

    /// 3.8-UNIT-009: docs/sdk-boundary.md 文件存在且非空
    func test_sdkBoundaryDoc_existsAndNonEmpty() throws {
        try skipUntilDocWritten()

        let sourcesDir = sourcesDirectory()
        let docPath = "\(sourcesDir)/../docs/sdk-boundary.md"

        let fileManager = FileManager.default
        XCTAssertTrue(fileManager.fileExists(atPath: docPath),
                       "docs/sdk-boundary.md must exist")

        let attributes = try fileManager.attributesOfItem(atPath: docPath)
        let fileSize = attributes[.size] as? Int ?? 0
        XCTAssertGreaterThan(fileSize, 0, "docs/sdk-boundary.md must not be empty")
    }

    // ========================================================================
    // MARK: - [P1] AC2: SDK 边界文档 — 内容章节检查
    // ========================================================================

    /// 3.8-UNIT-010: SDK 边界文档包含 SDK vs 应用层边界表
    func test_sdkBoundaryDoc_containsBoundaryTable() throws {
        try skipUntilDocWritten()

        let sourcesDir = sourcesDirectory()
        let docPath = "\(sourcesDir)/../docs/sdk-boundary.md"

        let content = try String(contentsOfFile: docPath, encoding: .utf8)

        // 验证文档包含关键章节标题
        XCTAssertTrue(content.contains("SDK") && content.contains("应用层"),
                       "SDK boundary doc must contain 'SDK' and '应用层' section describing the boundary")
        XCTAssertTrue(content.contains("Agent") && content.contains("SDK"),
                       "SDK boundary doc must describe Agent module ownership")
    }

    /// 3.8-UNIT-011: SDK 边界文档包含 SDK API 使用清单
    func test_sdkBoundaryDoc_containsAPIUsageInventory() throws {
        try skipUntilDocWritten()

        let sourcesDir = sourcesDirectory()
        let docPath = "\(sourcesDir)/../docs/sdk-boundary.md"

        let content = try String(contentsOfFile: docPath, encoding: .utf8)

        // 验证文档包含 API 使用清单
        XCTAssertTrue(content.contains("createAgent"),
                       "SDK boundary doc must list createAgent in API usage inventory")
        XCTAssertTrue(content.contains("AgentOptions"),
                       "SDK boundary doc must list AgentOptions in API usage inventory")
    }

    // ========================================================================
    // MARK: - [P2] AC3: SDK 短板记录 — 章节存在性检查
    // ========================================================================

    /// 3.8-UNIT-012: SDK 边界文档包含短板与改进建议章节
    func test_sdkBoundaryDoc_containsGapAnalysisSection() throws {
        try skipUntilDocWritten()

        let sourcesDir = sourcesDirectory()
        let docPath = "\(sourcesDir)/../docs/sdk-boundary.md"

        let content = try String(contentsOfFile: docPath, encoding: .utf8)

        // 验证文档包含短板分析章节
        let hasGapSection = content.contains("短板") || content.contains("Gap") || content.contains("改进")
        XCTAssertTrue(hasGapSection,
                       "SDK boundary doc must contain a gap analysis section (短板/Gaps)")
    }

    // ========================================================================
    // MARK: - [P1] Task 8: ToolNames 审计
    // ========================================================================

    /// 3.8-UNIT-013: ToolNames.allToolNames 包含全部 20 个已注册工具名
    func test_toolNames_allToolNames_containsAllRegisteredTools() {
        let allNames = ToolNames.allToolNames

        XCTAssertEqual(allNames.count, 24, "ToolNames.allToolNames should contain exactly 24 tool names")

        // 验证关键工具名存在
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
            XCTAssertTrue(allNames.contains(tool),
                           "ToolNames.allToolNames must contain '\(tool)'")
        }
    }

    /// 3.8-UNIT-014: ToolNames.foregroundToolNames 正确分类前台操作工具
    func test_toolNames_foregroundToolNames_correctClassification() {
        let foregroundTools = ToolNames.foregroundToolNames

        // 前台操作工具应该是交互类：click, type, key, drag, scroll
        let expectedForeground: Set<String> = [
            "click", "double_click", "right_click",
            "type_text", "press_key", "hotkey",
            "scroll", "drag"
        ]

        XCTAssertEqual(foregroundTools, expectedForeground,
                        "foregroundToolNames should match expected set of interactive tools")

        // 验证只读工具不在前台列表中
        let readOnlyTools = ["launch_app", "list_apps", "screenshot", "get_accessibility_tree", "open_url"]
        for tool in readOnlyTools {
            XCTAssertFalse(foregroundTools.contains(tool),
                            "'\(tool)' should NOT be in foregroundToolNames")
        }
    }
}
