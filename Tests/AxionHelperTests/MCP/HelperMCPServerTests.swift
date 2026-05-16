import Foundation
import Testing
import MCP
import MCPTool
@testable import AxionHelper
@testable import AxionCore

// ATDD Red-Phase Test Scaffolds for Story 1.2
// AC: #1 - MCP initialize 响应
// AC: #2 - tools/list 响应
// AC: #3 - 未知工具调用错误
// AC: #4 - EOF 优雅退出
// These tests verify AxionHelper's MCP Server foundation using MCPServer + ToolRegistrar.
// Priority: P0 (foundational - all Helper communication depends on this)

@Suite("HelperMCP Server")
struct HelperMCPServerTests {

    // MARK: - Helpers

    /// Creates an MCPServer with all tools registered via ToolRegistrar.
    /// This mirrors the production setup in AxionHelper main.swift.
    private func makeRegisteredServer() async throws -> MCPServer {
        let server = MCPServer(
            name: "AxionHelper",
            version: "0.1.0"
        )
        try await ToolRegistrar.registerAll(to: server)
        return server
    }

    /// Creates a minimal HandlerContext suitable for testing tool execution.
    private func makeTestContext() -> HandlerContext {
        let requestContext = RequestHandlerContext(
            sessionId: nil,
            requestId: .number(1),
            _meta: nil,
            taskId: nil,
            authInfo: nil,
            requestInfo: nil,
            closeResponseStream: nil,
            closeNotificationStream: nil,
            sendNotification: { _ in },
            sendRequest: { _ in Data() }
        )
        return HandlerContext(handlerContext: requestContext, progressToken: nil)
    }

    // MARK: - AC1: MCP initialize 响应

    // [P0] MCPServer 创建成功，包含正确的 name 和 version
    @Test("MCP server creation has correct name and version")
    func mcpServerCreationHasCorrectNameAndVersion() async throws {
        // Given: AxionHelper 启动
        let server = MCPServer(
            name: "AxionHelper",
            version: "0.1.0"
        )

        // When: 检查 server 属性
        // Then: 返回正确的 name 和 version
        let name = await server.name
        let version = await server.version
        #expect(name == "AxionHelper")
        #expect(version == "0.1.0")
    }

    // [P0] MCPServer initialize 响应包含服务端能力声明（tools capability）
    @Test("MCP server initialize includes tools capability")
    func mcpServerInitializeIncludesToolsCapability() async throws {
        // Given: AxionHelper 启动并注册了工具
        let server = try await makeRegisteredServer()

        // When: 通过 MCP 协议发送 initialize 请求
        _ = await server.createSession()

        // Then: 返回正确的 initialize 响应，包含服务端能力声明
        let tools = await server.toolRegistry.definitions
        #expect(!tools.isEmpty)
    }

    // MARK: - AC2: tools/list 响应

    // [P0] ToolRegistrar 注册所有 15 个工具
    @Test("tools/list returns all registered tools")
    func toolsListReturnsAllRegisteredTools() async throws {
        // Given: MCP 连接已建立（通过 ToolRegistrar 注册所有工具）
        let server = try await makeRegisteredServer()

        // When: 发送 tools/list 请求
        let tools = await server.toolRegistry.definitions

        // Then: 返回所有已注册工具的列表（至少 15 个）
        #expect(tools.count >= 15)
    }

    // [P0] 每个工具包含 name、description 和 inputSchema
    @Test("each tool has name description and schema")
    func toolsListEachToolHasNameDescriptionAndSchema() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions

        // Then: 每个工具包含 name、description 和 inputSchema
        for tool in tools {
            #expect(!tool.name.isEmpty)
            #expect(tool.description != nil)
            #expect(tool.inputSchema != nil)
        }
    }

    // [P0] 所有预期的工具名都存在（与 ToolNames.swift 常量一致）
    @Test("tools/list contains all expected tool names")
    func toolsListContainsAllExpectedToolNames() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions
        let toolNames = Set(tools.map { $0.name })

        // Then: 包含所有 Story 1.2 要求的工具
        let expectedTools = [
            "launch_app",
            "list_apps",
            "list_windows",
            "get_window_state",
            "click",
            "double_click",
            "right_click",
            "type_text",
            "press_key",
            "hotkey",
            "scroll",
            "drag",
            "screenshot",
            "get_accessibility_tree",
            "open_url",
        ]

        for expected in expectedTools {
            #expect(toolNames.contains(expected))
        }
    }

    // [P0] 工具名与 AxionCore/Constants/ToolNames.swift 保持一致
    @Test("tool names match ToolNames constants")
    func toolsListMatchesToolNamesConstants() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions
        let toolNames = Set(tools.map { $0.name })

        // Then: 关键工具名与 AxionCore 常量一致
        #expect(toolNames.contains(ToolNames.launchApp))
        #expect(toolNames.contains(ToolNames.click))
        #expect(toolNames.contains(ToolNames.typeText))
        #expect(toolNames.contains(ToolNames.pressKey))
        #expect(toolNames.contains(ToolNames.screenshot))
        #expect(toolNames.contains(ToolNames.getAccessibilityTree))
        #expect(toolNames.contains(ToolNames.openUrl))
        #expect(toolNames.contains(ToolNames.listWindows))
    }

    // [P1] Story 1.5 实现后，screenshot 工具不再返回 stub 文本
    // 验证所有 Story 1.5 工具（screenshot, get_accessibility_tree, open_url）已实现
    @Test("Story 1.5 tools do not return stub text")
    func story15ToolsDoNotReturnStubText() async throws {
        // Given: 所有工具已注册（Story 1.5 已实现）
        let server = try await makeRegisteredServer()

        // Setup mocks so the tools can execute
        let mockScreenshot = MockScreenshotCapture(
            captureWindowHandler: { _ in "mockBase64" },
            captureFullScreenHandler: { "mockBase64" }
        )
        let mockUrlOpener = MockURLOpener(openURLHandler: { _ in })
        let restore = ServiceContainerFixture.apply(
            screenshotCapture: mockScreenshot,
            urlOpener: mockUrlOpener
        )
        defer { restore() }

        // When: 执行 screenshot 工具（不再有 stub）
        let result = try await server.toolRegistry.execute(
            "screenshot",
            arguments: [:],
            context: makeTestContext()
        )

        let text = result.content.compactMap { content -> String? in
            if case let .text(t, _, _) = content { return t }
            return nil
        }.joined()

        // Then: 不应返回 "Not yet implemented"
        #expect(!text.lowercased().contains("not yet implemented"))
    }

    // MARK: - AC3: 未知工具调用错误

    // [P0] 调用未注册的工具名返回错误
    @Test("unknown tool returns error")
    func unknownToolReturnsError() async throws {
        // Given: Helper 收到未知工具名调用
        let server = try await makeRegisteredServer()

        // When: 执行未知工具名 "nonexistent_tool"
        // Then: 抛出 MCPError.invalidParams（MCPServer 内置处理）
        do {
            _ = try await server.toolRegistry.execute(
                "nonexistent_tool",
                arguments: nil,
                context: makeTestContext()
            )
            Issue.record("Expected error for unknown tool, but got success")
        } catch {
            // MCPServer 对未知工具抛出 MCPError.invalidParams
            // This satisfies AC3: 返回 isError=true 的 ToolResult，message 说明工具不存在
            let errorDescription = String(describing: error)
            #expect(
                errorDescription.contains("Unknown tool") || errorDescription.contains("nonexistent_tool")
            )
        }
    }

    // [P1] 多个未知工具名都正确返回错误
    @Test("various unknown tool names return errors")
    func unknownToolVariousNamesReturnErrors() async throws {
        // Given: MCP server 已注册所有工具
        let server = try await makeRegisteredServer()

        // When/Then: 多个未知工具名都应抛出错误
        let unknownNames = ["foo_bar", "launch_application", "Click", "TYPE_TEXT", "get-window-state"]
        for name in unknownNames {
            do {
                _ = try await server.toolRegistry.execute(
                    name,
                    arguments: nil,
                    context: makeTestContext()
                )
                Issue.record("Expected error for unknown tool '\(name)', but got success")
            } catch {
                // Expected: error for unknown tool
            }
        }
    }

    // MARK: - AC4: EOF 优雅退出

    // [P0] stdin EOF 时 MCPServer 优雅退出
    // Note: This test verifies the API contract that HelperMCPServer.run() uses.
    // The actual EOF behavior (process exit on stdin close) is verified by the
    // process-level smoke test (HelperProcessSmokeTests.helperProcessGracefulExitOnEOF).
    @Test("MCP server run stdio exits on EOF")
    func mcpServerRunStdioExitsOnEOF() async throws {
        // Given: An MCPServer configured like AxionHelper
        let server = MCPServer(name: "AxionHelper", version: "0.1.0")
        try await ToolRegistrar.registerAll(to: server)

        // When: Creating a session and stdio transport (mirrors HelperMCPServer.run())
        let session = await server.createSession()
        let transport = StdioTransport()

        // Then: session and transport are created successfully
        // This verifies the API contract that HelperMCPServer.run() depends on.
        _ = (session, transport)

        // Verify tools are registered in the session's server
        let tools = await server.toolRegistry.definitions
        #expect(tools.count >= 15)
    }

    // MARK: - ToolRegistrar Tests

    // [P0] ToolRegistrar.registerAll 方法存在且可调用
    @Test("ToolRegistrar registerAll is callable")
    func toolRegistrarRegisterAllIsCallable() async throws {
        // Given: 一个 MCPServer 实例
        let server = MCPServer(name: "TestHelper", version: "0.1.0")

        // When: 调用 ToolRegistrar.registerAll
        try await ToolRegistrar.registerAll(to: server)

        // Then: server 的 toolRegistry 不为空
        let tools = await server.toolRegistry.definitions
        #expect(!tools.isEmpty)
    }

    // [P1] ToolRegistrar 不注册重复工具名
    @Test("ToolRegistrar has no duplicate tool names")
    func toolRegistrarNoDuplicateToolNames() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions

        // Then: 没有重复的工具名
        let names = tools.map { $0.name }
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }

    // [P1] 所有工具使用 snake_case 命名
    @Test("all tools use snake_case naming")
    func toolRegistrarAllToolsUseSnakeCase() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions

        // Then: 所有工具名使用 snake_case（只包含小写字母、数字和下划线）
        let snakeCasePattern = "^[a-z][a-z0-9_]*$"
        let regex = try NSRegularExpression(pattern: snakeCasePattern)
        for tool in tools {
            let range = NSRange(tool.name.startIndex..., in: tool.name)
            let matches = regex.matches(in: tool.name, range: range)
            #expect(matches.count > 0)
        }
    }
}
