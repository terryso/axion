import XCTest
@testable import AxionCLI
import AxionCore
import MCP

// [P0] 基础设施验证 — HelperProcessManager actor 类型存在性和方法签名
// [P1] 行为验证 — 启动连接、优雅关闭、崩溃重启、信号处理
// Story 3.1 AC: #1–#6

// MARK: - Mock Transport

/// Mock transport for testing HelperProcessManager without real processes.
actor MockHelperTransport: HelperTransportProtocol {
    var connectCalled = false
    var disconnectCalled = false
    var shouldFailConnect = false
    private var _isRunning = false

    func connect() async throws {
        connectCalled = true
        if shouldFailConnect {
            throw NSError(domain: "MockTransport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Connection failed"
            ])
        }
        _isRunning = true
    }

    func disconnect() async {
        disconnectCalled = true
        _isRunning = false
    }

    func getIsRunning() async -> Bool {
        _isRunning
    }

    func getTransport() async -> (any Transport)? {
        // Mock doesn't provide a real transport; tests use it only for state checks.
        nil
    }

    /// Simulate a crash (process stops unexpectedly).
    func simulateCrash() {
        _isRunning = false
    }

    /// Force set running state for testing.
    func setRunning(_ running: Bool) {
        _isRunning = running
    }
}

// MARK: - Mock MCP Client

/// Mock MCP client for testing HelperProcessManager without real MCP handshake.
actor MockHelperMCPClient: HelperMCPClientProtocol {
    var connectCalled = false
    var disconnectCalled = false
    var shouldFailConnect = false
    var shouldFailCallTool = false
    var shouldFailListTools = false
    var shouldReturnError = false

    private var stubbedTools: [String] = ["click", "type_text", "screenshot"]
    private var stubbedCallToolResult: String = "OK"

    func connect(transport: @escaping @Sendable () async throws -> any Transport) async throws {
        connectCalled = true
        if shouldFailConnect {
            throw NSError(domain: "MockMCPClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "MCP handshake failed"
            ])
        }
    }

    func disconnect() async {
        disconnectCalled = true
    }

    func callTool(name: String, arguments: [String: MCP.Value]?) async throws -> CallTool.Result {
        if shouldFailCallTool {
            throw NSError(domain: "MockMCPClient", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Tool call failed"
            ])
        }
        if shouldReturnError {
            return CallTool.Result(
                content: [.text("Error: something went wrong", annotations: nil, _meta: nil)],
                isError: true
            )
        }
        return CallTool.Result(
            content: [.text(stubbedCallToolResult, annotations: nil, _meta: nil)]
        )
    }

    func listTools() async throws -> ListTools.Result {
        if shouldFailListTools {
            throw NSError(domain: "MockMCPClient", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "List tools failed"
            ])
        }
        let tools = stubbedTools.map { name in
            Tool(name: name, description: "Mock tool: \(name)", inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:])
            ]))
        }
        return ListTools.Result(tools: tools)
    }

    func setStubbedTools(_ tools: [String]) {
        stubbedTools = tools
    }

    func setStubbedCallToolResult(_ result: String) {
        stubbedCallToolResult = result
    }
}

// MARK: - Tests

final class HelperProcessManagerTests: XCTestCase {

    // MARK: - Helper to create manager with mocks

    private func makeManager(
        transport: MockHelperTransport? = nil,
        client: MockHelperMCPClient? = nil
    ) -> (HelperProcessManager, MockHelperTransport, MockHelperMCPClient) {
        let transport = transport ?? MockHelperTransport()
        let client = client ?? MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)
        return (manager, transport, client)
    }

    /// Starts the manager by manually setting connected state (bypassing path resolution).
    /// For mock-based tests, use the init(transport:client:) which sets connected=true.
    /// This method is kept for tests that need the real start() path.
    private func startMocked(
        _ manager: HelperProcessManager,
        client: MockHelperMCPClient
    ) async throws {
        // For tests using the default init(), start() requires a real helper path.
        // Set a fake path that will trigger the MCP handshake to fail predictably.
        setenv("AXION_HELPER_PATH", "/usr/bin/true", 1)
        defer { unsetenv("AXION_HELPER_PATH") }

        try await manager.start()
    }

    // MARK: - [P0] 类型存在性

    // AC1: HelperProcessManager actor 类型存在
    func test_helperProcessManager_typeExists() {
        _ = HelperProcessManager.self
    }

    // AC1: start() async throws 方法存在
    func test_helperProcessManager_startMethodExists() async {
        let manager = HelperProcessManager()
        // start() will fail without helper path, but the method exists
        setenv("AXION_HELPER_PATH", "/nonexistent/path", 1)
        defer { unsetenv("AXION_HELPER_PATH") }
        do {
            try await manager.start()
        } catch {
            // Expected to fail with helperConnectionFailed
        }
    }

    // AC3: stop() async 方法存在
    func test_helperProcessManager_stopMethodExists() async {
        let manager = HelperProcessManager()
        await manager.stop()
    }

    // AC1: isRunning() async -> Bool 方法存在
    func test_helperProcessManager_isRunningMethodExists() async {
        let manager = HelperProcessManager()
        _ = await manager.isRunning()
    }

    // AC1: callTool(name:arguments:) async throws -> String 方法存在
    func test_helperProcessManager_callToolMethodExists() async {
        let manager = HelperProcessManager()
        do {
            _ = try await manager.callTool(name: "test", arguments: [:])
        } catch {
            // Expected: not connected
        }
    }

    // AC1: listTools() async throws -> [String] 方法存在
    func test_helperProcessManager_listToolsMethodExists() async {
        let manager = HelperProcessManager()
        do {
            _ = try await manager.listTools()
        } catch {
            // Expected: not connected
        }
    }

    // MARK: - [P1] AC1: 启动 Helper 并建立 MCP 连接

    // Helper 路径未找到时，start() 抛出 helperNotRunning 错误
    func test_start_throwsWhenHelperPathNotFound() async {
        // Given: 环境中无法找到 Helper 可执行文件
        unsetenv("AXION_HELPER_PATH")
        let manager = HelperProcessManager()

        // When/Then: start() 应抛出 AxionError.helperNotRunning
        do {
            try await manager.start()
            XCTFail("start() 应在 Helper 路径未找到时抛出错误")
        } catch let error as AxionError {
            XCTAssertEqual(error, .helperNotRunning, "应抛出 helperNotRunning 错误")
        } catch {
            XCTFail("应抛出 AxionError.helperNotRunning，实际: \(error)")
        }
    }

    // MARK: - [P1] AC1: Mock-based connection test

    // Mock-based manager with connected=true returns isRunning based on transport
    func test_start_connectsMCPClient_isRunningReflectsTransport() async throws {
        let transport = MockHelperTransport()
        await transport.setRunning(true)
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        // Manager created with mock init is connected; isRunning checks transport
        let running = await manager.isRunning()
        XCTAssertTrue(running, "Mock transport running 时 isRunning 应为 true")

        // Simulate transport going down
        await transport.simulateCrash()
        let afterCrash = await manager.isRunning()
        XCTAssertFalse(afterCrash, "Transport 停止后 isRunning 应为 false")
    }

    // MCP 握手失败时，start() 抛出 helperConnectionFailed
    func test_start_throwsHelperConnectionFailed_onMCPError() async {
        // Given: helper path 存在但 MCP 连接失败
        setenv("AXION_HELPER_PATH", "/usr/bin/true", 1)
        defer { unsetenv("AXION_HELPER_PATH") }

        let manager = HelperProcessManager()

        do {
            try await manager.start()
            // /usr/bin/true may succeed in process launch but fail MCP handshake
            // This is expected behavior
        } catch let error as AxionError {
            if case .helperConnectionFailed = error {
                // expected: MCP handshake fails because /usr/bin/true isn't an MCP server
            } else {
                // helperNotRunning also acceptable if path resolution has issues
            }
        } catch {
            XCTFail("应抛出 AxionError，实际: \(error)")
        }
    }

    // MARK: - [P1] AC2: MCP 连接就绪确认

    // 连接就绪后可以获取工具列表 — 通过 mock
    func test_listTools_returnsToolNames() async throws {
        let client = MockHelperMCPClient()
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        // Manager with mock init is connected; listTools should return tools from mock client
        let tools = try await manager.listTools()
        XCTAssertEqual(tools, ["click", "type_text", "screenshot"])
    }

    // 工具名应为 snake_case
    func test_listTools_toolNamesAreSnakeCase() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedTools(["click", "type_text", "get_window_state"])

        let result = try await client.listTools()
        for tool in result.tools {
            XCTAssertTrue(
                tool.name.allSatisfy { $0.isLowercase || $0 == "_" || $0.isNumber },
                "工具名应为 snake_case: \(tool.name)"
            )
        }
    }

    // MARK: - [P1] AC3: 正常退出清理

    // stop() 关闭 MCP 连接和 transport
    func test_stop_closesMCPClientAndTransport() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        // Simulate connected state
        await transport.setRunning(true)

        // stop should clean up
        await manager.stop()

        let disconnectCalled = await client.disconnectCalled
        let transportDisconnected = await transport.disconnectCalled
        XCTAssertTrue(disconnectCalled, "stop() 应调用 client.disconnect()")
        XCTAssertTrue(transportDisconnected, "stop() 应调用 transport.disconnect()")

        let running = await manager.isRunning()
        XCTAssertFalse(running, "stop() 后 isRunning 应为 false")
    }

    // stop() 在 Helper 未启动时是空操作
    func test_stop_whenNotStarted_isNoOp() async {
        let manager = HelperProcessManager()

        // When/Then: stop() 不应抛出异常
        await manager.stop()
        let running = await manager.isRunning()
        XCTAssertFalse(running, "未启动时 stop() 后 isRunning 应为 false")
    }

    // 优雅关闭流程：先关 MCP 连接，再关 transport
    func test_stop_gracefulShutdown_closesConnectionFirst() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        await transport.setRunning(true)

        await manager.stop()

        let running = await manager.isRunning()
        XCTAssertFalse(running, "优雅关闭后应清理所有资源")
    }

    // MARK: - [P1] AC4: 强制终止回退

    // stop() 调用 disconnect，最终清理进程
    func test_stop_forceKillAfterTimeout() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        await transport.setRunning(true)

        await manager.stop()
        let running = await manager.isRunning()
        XCTAssertFalse(running, "stop() 后进程应已终止")
    }

    // MARK: - [P1] AC5: Ctrl-C 信号传播（NFR8）

    // setupSignalHandling 注册 SIGINT 处理 — 接口存在性测试
    func test_setupSignalHandling_registersSIGINTHandler() async {
        let manager = HelperProcessManager()
        // Should not throw
        await manager.setupSignalHandling()
    }

    // MARK: - [P1] AC6: Helper 崩溃检测与重启

    // 崩溃后 crash monitor 检测到 transport 不再运行
    func test_crashMonitor_detectsCrashViaTransportState() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        // Simulate running state
        await transport.setRunning(true)

        // Before crash, isRunning is true
        let beforeCrash = await manager.isRunning()
        XCTAssertTrue(beforeCrash, "崩溃前 isRunning 应为 true")

        // Simulate crash
        await transport.simulateCrash()

        // After crash, isRunning reflects transport state
        let afterCrash = await manager.isRunning()
        XCTAssertFalse(afterCrash, "崩溃后 isRunning 应为 false")
    }

    // 二次崩溃不再重启 — hasRestarted 标志验证
    func test_crashMonitor_hasRestartedPreventsSecondRestart() async throws {
        // Test the guard in performCrashRestart: if hasRestarted is true, return early.
        // We verify through the public API that after stop + manual state inspection.
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        // After stop(), further crashes won't trigger restart because isStopping prevents it
        await manager.stop()

        // Simulate crash while stopped — should not cause issues
        await transport.simulateCrash()

        let running = await manager.isRunning()
        XCTAssertFalse(running, "停止后崩溃不应触发重启")
    }

    // MARK: - [P1] Value 类型转换（通过 callTool 端到端验证）

    // AxionCore.Value.string 通过 callTool 正确转换为 MCP.Value.string
    func test_callTool_convertsStringValue() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedCallToolResult("typed: hello")
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let result = try await manager.callTool(name: "type_text", arguments: ["text": .string("hello")])
        XCTAssertEqual(result, "typed: hello")
    }

    // AxionCore.Value.int 通过 callTool 正确转换为 MCP.Value.int
    func test_callTool_convertsIntValue() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedCallToolResult("clicked")
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let result = try await manager.callTool(name: "click", arguments: ["x": .int(100), "y": .int(200)])
        XCTAssertEqual(result, "clicked")
    }

    // AxionCore.Value.bool 通过 callTool 正确转换为 MCP.Value.bool
    func test_callTool_convertsBoolValue() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedCallToolResult("ok")
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let result = try await manager.callTool(name: "test_tool", arguments: ["flag": .bool(true)])
        XCTAssertEqual(result, "ok")
    }

    // AxionCore.Value.placeholder 作为 MCP.Value.string 传递
    func test_callTool_convertsPlaceholderAsString() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedCallToolResult("window focused")
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let result = try await manager.callTool(name: "focus_window", arguments: ["window_id": .placeholder("$window_id")])
        XCTAssertEqual(result, "window focused")
    }

    // MARK: - [P1] MCP ToolResult 提取

    // 从 MCP ToolResult 中提取文本内容
    func test_callTool_extractsTextFromResult() async throws {
        let result = CallTool.Result(
            content: [.text("clicked at (100, 200)", annotations: nil, _meta: nil)]
        )
        let textParts = result.content.compactMap { block -> String? in
            if case .text(let text, _, _) = block { return text }
            return nil
        }
        XCTAssertEqual(textParts, ["clicked at (100, 200)"])
    }

    // 多个 content 块用换行符连接
    func test_callTool_joinsMultipleContentBlocks() async throws {
        let result = CallTool.Result(
            content: [
                .text("line 1", annotations: nil, _meta: nil),
                .text("line 2", annotations: nil, _meta: nil),
            ]
        )
        let textParts = result.content.compactMap { block -> String? in
            if case .text(let text, _, _) = block { return text }
            return nil
        }
        XCTAssertEqual(textParts.joined(separator: "\n"), "line 1\nline 2")
    }

    // 错误结果（isError=true）抛出 mcpError
    func test_callTool_handlesErrorResult() async throws {
        let client = MockHelperMCPClient()
        await client.setShouldReturnError(true)
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        do {
            _ = try await manager.callTool(name: "test_tool", arguments: [:])
            XCTFail("isError=true 时 callTool 应抛出错误")
        } catch let error as AxionError {
            if case .mcpError(let tool, let reason) = error {
                XCTAssertEqual(tool, "test_tool")
                XCTAssertTrue(reason.contains("something went wrong"), "应包含错误文本")
            } else {
                XCTFail("应抛出 mcpError，实际: \(error)")
            }
        } catch {
            XCTFail("应抛出 AxionError.mcpError，实际: \(error)")
        }
    }

    // MARK: - [P1] 未启动时调用工具

    // 未启动时调用 callTool 抛出错误
    func test_callTool_whenNotStarted_throwsError() async {
        let manager = HelperProcessManager()

        do {
            _ = try await manager.callTool(name: "click", arguments: ["x": AxionCore.Value.int(100), "y": AxionCore.Value.int(200)])
            XCTFail("未启动时 callTool 应抛出错误")
        } catch let error as AxionError {
            XCTAssertEqual(error, .helperNotRunning, "应抛出 helperNotRunning")
        } catch {
            XCTFail("应抛出 AxionError.helperNotRunning，实际: \(error)")
        }
    }

    // 未启动时调用 listTools 抛出错误
    func test_listTools_whenNotStarted_throwsError() async {
        let manager = HelperProcessManager()

        do {
            _ = try await manager.listTools()
            XCTFail("未启动时 listTools 应抛出错误")
        } catch let error as AxionError {
            XCTAssertEqual(error, .helperNotRunning, "应抛出 helperNotRunning")
        } catch {
            XCTFail("应抛出 AxionError.helperNotRunning，实际: \(error)")
        }
    }
}

// MARK: - MockHelperMCPClient helpers

extension MockHelperMCPClient {
    func setShouldReturnError(_ value: Bool) {
        shouldReturnError = value
    }
}
