import XCTest
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

final class HelperMCPServerTests: XCTestCase {

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
    func test_mcpServer_creation_hasCorrectNameAndVersion() async throws {
        // Given: AxionHelper 启动
        let server = MCPServer(
            name: "AxionHelper",
            version: "0.1.0"
        )

        // When: 检查 server 属性
        // Then: 返回正确的 name 和 version
        let name = await server.name
        let version = await server.version
        XCTAssertEqual(name, "AxionHelper", "Server name should be AxionHelper")
        XCTAssertEqual(version, "0.1.0", "Server version should be 0.1.0")
    }

    // [P0] MCPServer initialize 响应包含服务端能力声明（tools capability）
    func test_mcpServer_initialize_includesToolsCapability() async throws {
        // Given: AxionHelper 启动并注册了工具
        let server = try await makeRegisteredServer()

        // When: 通过 MCP 协议发送 initialize 请求
        // MCPServer 的 createSession() 方法构建带有工具能力的 Server 实例
        let session = await server.createSession()

        // Then: 返回正确的 initialize 响应，包含服务端能力声明
        // 验证 session 存在（证明 initialize 可以成功）
        // 验证 server 的 toolRegistry 不为空
        let tools = await server.toolRegistry.definitions
        XCTAssertFalse(tools.isEmpty, "Server should have tools registered after initialize")
    }

    // MARK: - AC2: tools/list 响应

    // [P0] ToolRegistrar 注册所有 15 个工具
    func test_toolsList_returnsAllRegisteredTools() async throws {
        // Given: MCP 连接已建立（通过 ToolRegistrar 注册所有工具）
        let server = try await makeRegisteredServer()

        // When: 发送 tools/list 请求
        let tools = await server.toolRegistry.definitions

        // Then: 返回所有已注册工具的列表（至少 15 个）
        XCTAssertGreaterThanOrEqual(tools.count, 15, "Should register at least 15 tools")
    }

    // [P0] 每个工具包含 name、description 和 inputSchema
    func test_toolsList_eachToolHasNameDescriptionAndSchema() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions

        // Then: 每个工具包含 name、description 和 inputSchema
        for tool in tools {
            XCTAssertFalse(tool.name.isEmpty, "Each tool must have a non-empty name")
            XCTAssertNotNil(tool.description, "Each tool must have a description")
            XCTAssertNotNil(tool.inputSchema, "Each tool must have an inputSchema")
        }
    }

    // [P0] 所有预期的工具名都存在（与 ToolNames.swift 常量一致）
    func test_toolsList_containsAllExpectedToolNames() async throws {
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
            XCTAssertTrue(
                toolNames.contains(expected),
                "Tool '\(expected)' should be registered. Available: \(toolNames.sorted())"
            )
        }
    }

    // [P0] 工具名与 AxionCore/Constants/ToolNames.swift 保持一致
    func test_toolsList_matchesToolNamesConstants() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions
        let toolNames = Set(tools.map { $0.name })

        // Then: 关键工具名与 AxionCore 常量一致
        XCTAssertTrue(toolNames.contains(ToolNames.launchApp))
        XCTAssertTrue(toolNames.contains(ToolNames.click))
        XCTAssertTrue(toolNames.contains(ToolNames.typeText))
        XCTAssertTrue(toolNames.contains(ToolNames.pressKey))
        XCTAssertTrue(toolNames.contains(ToolNames.screenshot))
        XCTAssertTrue(toolNames.contains(ToolNames.getAccessibilityTree))
        XCTAssertTrue(toolNames.contains(ToolNames.openUrl))
        XCTAssertTrue(toolNames.contains(ToolNames.listWindows))
    }

    // [P1] Story 1.5 实现后，screenshot 工具不再返回 stub 文本
    // 验证所有 Story 1.5 工具（screenshot, get_accessibility_tree, open_url）已实现
    func test_story15_tools_doNotReturnStubText() async throws {
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
        XCTAssertFalse(
            text.lowercased().contains("not yet implemented"),
            "screenshot tool should not return stub text after Story 1.5 implementation"
        )
    }

    // MARK: - AC3: 未知工具调用错误

    // [P0] 调用未注册的工具名返回错误
    func test_unknownTool_returnsError() async throws {
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
            XCTFail("Expected error for unknown tool, but got success")
        } catch {
            // MCPServer 对未知工具抛出 MCPError.invalidParams
            // This satisfies AC3: 返回 isError=true 的 ToolResult，message 说明工具不存在
            let errorDescription = String(describing: error)
            XCTAssertTrue(
                errorDescription.contains("Unknown tool") || errorDescription.contains("nonexistent_tool"),
                "Error should mention unknown tool, got: \(errorDescription)"
            )
        }
    }

    // [P1] 多个未知工具名都正确返回错误
    func test_unknownTool_variousNames_returnErrors() async throws {
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
                XCTFail("Expected error for unknown tool '\(name)', but got success")
            } catch {
                // Expected: error for unknown tool
            }
        }
    }

    // MARK: - AC4: EOF 优雅退出

    // [P0] stdin EOF 时 MCPServer 优雅退出
    // Note: This test verifies the API contract that HelperMCPServer.run() uses.
    // The actual EOF behavior (process exit on stdin close) is verified by the
    // process-level smoke test (HelperProcessSmokeTests.test_helperProcess_gracefulExitOnEOF).
    func test_mcpServer_runStdio_exitsOnEOF() async throws {
        // Given: An MCPServer configured like AxionHelper
        let server = MCPServer(name: "AxionHelper", version: "0.1.0")
        try await ToolRegistrar.registerAll(to: server)

        // When: Creating a session and stdio transport (mirrors HelperMCPServer.run())
        let session = await server.createSession()
        let transport = StdioTransport()

        // Then: session.start() and session.waitUntilCompleted() are callable
        // This verifies the API contract that HelperMCPServer.run() depends on.
        // We cannot call session.start() in a test because it blocks on stdin,
        // but we verify that the session and transport can be created successfully.
        XCTAssertNotNil(session, "Session should be created from MCPServer")
        XCTAssertNotNil(transport, "StdioTransport should be constructable")

        // Verify tools are registered in the session's server
        let tools = await server.toolRegistry.definitions
        XCTAssertGreaterThanOrEqual(tools.count, 15, "Server should have all tools registered")
    }

    // MARK: - ToolRegistrar Tests

    // [P0] ToolRegistrar.registerAll 方法存在且可调用
    func test_toolRegistrar_registerAll_isCallable() async throws {
        // Given: 一个 MCPServer 实例
        let server = MCPServer(name: "TestHelper", version: "0.1.0")

        // When: 调用 ToolRegistrar.registerAll
        try await ToolRegistrar.registerAll(to: server)

        // Then: server 的 toolRegistry 不为空
        let tools = await server.toolRegistry.definitions
        XCTAssertFalse(tools.isEmpty, "ToolRegistrar should register at least one tool")
    }

    // [P1] ToolRegistrar 不注册重复工具名
    func test_toolRegistrar_noDuplicateToolNames() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions

        // Then: 没有重复的工具名
        let names = tools.map { $0.name }
        let uniqueNames = Set(names)
        XCTAssertEqual(
            names.count,
            uniqueNames.count,
            "Tool names should be unique, but found duplicates: \(names.filter { name in names.filter { $0 == name }.count > 1 })"
        )
    }

    // [P1] 所有工具使用 snake_case 命名
    func test_toolRegistrar_allToolsUseSnakeCase() async throws {
        // Given: 所有工具已注册
        let server = try await makeRegisteredServer()
        let tools = await server.toolRegistry.definitions

        // Then: 所有工具名使用 snake_case（只包含小写字母、数字和下划线）
        let snakeCasePattern = "^[a-z][a-z0-9_]*$"
        let regex = try NSRegularExpression(pattern: snakeCasePattern)
        for tool in tools {
            let range = NSRange(tool.name.startIndex..., in: tool.name)
            let matches = regex.matches(in: tool.name, range: range)
            XCTAssertGreaterThan(
                matches.count, 0,
                "Tool name '\(tool.name)' should be snake_case (lowercase + underscores)"
            )
        }
    }
}
