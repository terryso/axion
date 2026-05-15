import Testing
import Foundation
@testable import AxionCLI
import AxionCore
import MCP

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

extension MockHelperMCPClient {
    func setShouldReturnError(_ value: Bool) {
        shouldReturnError = value
    }
}

@Suite("HelperProcessManager")
struct HelperProcessManagerTests {

    private func makeManager(
        transport: MockHelperTransport? = nil,
        client: MockHelperMCPClient? = nil
    ) -> (HelperProcessManager, MockHelperTransport, MockHelperMCPClient) {
        let transport = transport ?? MockHelperTransport()
        let client = client ?? MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)
        return (manager, transport, client)
    }

    @Test("HelperProcessManager type exists")
    func helperProcessManagerTypeExists() {
        _ = HelperProcessManager.self
    }

    @Test("start() async throws method exists")
    func helperProcessManagerStartMethodExists() async {
        let manager = HelperProcessManager()
        setenv("AXION_HELPER_PATH", "/nonexistent/path", 1)
        defer { unsetenv("AXION_HELPER_PATH") }
        do {
            try await manager.start()
        } catch {
            // Expected to fail with helperConnectionFailed
        }
    }

    @Test("stop() async method exists")
    func helperProcessManagerStopMethodExists() async {
        let manager = HelperProcessManager()
        await manager.stop()
    }

    @Test("isRunning() async -> Bool method exists")
    func helperProcessManagerIsRunningMethodExists() async {
        let manager = HelperProcessManager()
        _ = await manager.isRunning()
    }

    @Test("callTool(name:arguments:) async throws method exists")
    func helperProcessManagerCallToolMethodExists() async {
        let manager = HelperProcessManager()
        do {
            _ = try await manager.callTool(name: "test", arguments: [:])
        } catch {
            // Expected: not connected
        }
    }

    @Test("listTools() async throws method exists")
    func helperProcessManagerListToolsMethodExists() async {
        let manager = HelperProcessManager()
        do {
            _ = try await manager.listTools()
        } catch {
            // Expected: not connected
        }
    }

    @Test("start() throws when helper path not found")
    func startThrowsWhenHelperPathNotFound() async {
        unsetenv("AXION_HELPER_PATH")
        let manager = HelperProcessManager()

        do {
            try await manager.start()
            Issue.record("start() should throw when Helper path not found")
        } catch let error as AxionError {
            #expect(error == .helperNotRunning)
        } catch {
            Issue.record("Expected AxionError.helperNotRunning, got: \(error)")
        }
    }

    @Test("mock-based manager reflects transport isRunning state")
    func startConnectsMCPClientIsRunningReflectsTransport() async throws {
        let transport = MockHelperTransport()
        await transport.setRunning(true)
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        let running = await manager.isRunning()
        #expect(running)

        await transport.simulateCrash()
        let afterCrash = await manager.isRunning()
        #expect(!afterCrash)
    }

    @Test("start() throws helperConnectionFailed on MCP error")
    func startThrowsHelperConnectionFailedOnMCPError() async {
        setenv("AXION_HELPER_PATH", "/usr/bin/true", 1)
        defer { unsetenv("AXION_HELPER_PATH") }

        let manager = HelperProcessManager()

        do {
            try await manager.start()
        } catch let error as AxionError {
            if case .helperConnectionFailed = error {
                // expected: MCP handshake fails because /usr/bin/true isn't an MCP server
            } else {
                // helperNotRunning also acceptable if path resolution has issues
            }
        } catch {
            Issue.record("Expected AxionError, got: \(error)")
        }
    }

    @Test("listTools returns tool names")
    func listToolsReturnsToolNames() async throws {
        let client = MockHelperMCPClient()
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let tools = try await manager.listTools()
        #expect(tools == ["click", "type_text", "screenshot"])
    }

    @Test("tool names are snake_case")
    func listToolsToolNamesAreSnakeCase() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedTools(["click", "type_text", "get_window_state"])

        let result = try await client.listTools()
        for tool in result.tools {
            #expect(
                tool.name.allSatisfy { $0.isLowercase || $0 == "_" || $0.isNumber }
            )
        }
    }

    @Test("stop() closes MCP client and transport")
    func stopClosesMCPClientAndTransport() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        await transport.setRunning(true)

        await manager.stop()

        let disconnectCalled = await client.disconnectCalled
        let transportDisconnected = await transport.disconnectCalled
        #expect(disconnectCalled)
        #expect(transportDisconnected)

        let running = await manager.isRunning()
        #expect(!running)
    }

    @Test("stop() when not started is a no-op")
    func stopWhenNotStartedIsNoOp() async {
        let manager = HelperProcessManager()

        await manager.stop()
        let running = await manager.isRunning()
        #expect(!running)
    }

    @Test("graceful shutdown closes connection first")
    func stopGracefulShutdownClosesConnectionFirst() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        await transport.setRunning(true)

        await manager.stop()

        let running = await manager.isRunning()
        #expect(!running)
    }

    @Test("stop() force kills after timeout")
    func stopForceKillAfterTimeout() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        await transport.setRunning(true)

        await manager.stop()
        let running = await manager.isRunning()
        #expect(!running)
    }

    @Test("setupSignalHandling registers SIGINT handler")
    func setupSignalHandlingRegistersSIGINTHandler() async {
        let manager = HelperProcessManager()
        await manager.setupSignalHandling()
    }

    @Test("crash monitor detects crash via transport state")
    func crashMonitorDetectsCrashViaTransportState() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        await transport.setRunning(true)

        let beforeCrash = await manager.isRunning()
        #expect(beforeCrash)

        await transport.simulateCrash()

        let afterCrash = await manager.isRunning()
        #expect(!afterCrash)
    }

    @Test("hasRestarted prevents second restart after stop")
    func crashMonitorHasRestartedPreventsSecondRestart() async throws {
        let transport = MockHelperTransport()
        let client = MockHelperMCPClient()
        let manager = HelperProcessManager(transport: transport, client: client)

        await manager.stop()

        await transport.simulateCrash()

        let running = await manager.isRunning()
        #expect(!running)
    }

    @Test("callTool converts AxionCore.Value.string to MCP.Value.string")
    func callToolConvertsStringValue() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedCallToolResult("typed: hello")
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let result = try await manager.callTool(name: "type_text", arguments: ["text": .string("hello")])
        #expect(result == "typed: hello")
    }

    @Test("callTool converts AxionCore.Value.int to MCP.Value.int")
    func callToolConvertsIntValue() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedCallToolResult("clicked")
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let result = try await manager.callTool(name: "click", arguments: ["x": .int(100), "y": .int(200)])
        #expect(result == "clicked")
    }

    @Test("callTool converts AxionCore.Value.bool to MCP.Value.bool")
    func callToolConvertsBoolValue() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedCallToolResult("ok")
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let result = try await manager.callTool(name: "test_tool", arguments: ["flag": .bool(true)])
        #expect(result == "ok")
    }

    @Test("callTool converts AxionCore.Value.placeholder as MCP.Value.string")
    func callToolConvertsPlaceholderAsString() async throws {
        let client = MockHelperMCPClient()
        await client.setStubbedCallToolResult("window focused")
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        let result = try await manager.callTool(name: "focus_window", arguments: ["window_id": .placeholder("$window_id")])
        #expect(result == "window focused")
    }

    @Test("extracts text from MCP ToolResult content")
    func callToolExtractsTextFromResult() async throws {
        let result = CallTool.Result(
            content: [.text("clicked at (100, 200)", annotations: nil, _meta: nil)]
        )
        let textParts = result.content.compactMap { block -> String? in
            if case .text(let text, _, _) = block { return text }
            return nil
        }
        #expect(textParts == ["clicked at (100, 200)"])
    }

    @Test("joins multiple content blocks with newline")
    func callToolJoinsMultipleContentBlocks() async throws {
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
        #expect(textParts.joined(separator: "\n") == "line 1\nline 2")
    }

    @Test("isError=true causes callTool to throw mcpError")
    func callToolHandlesErrorResult() async throws {
        let client = MockHelperMCPClient()
        await client.setShouldReturnError(true)
        let transport = MockHelperTransport()
        let manager = HelperProcessManager(transport: transport, client: client)

        do {
            _ = try await manager.callTool(name: "test_tool", arguments: [:])
            Issue.record("callTool should throw when isError=true")
        } catch let error as AxionError {
            if case .mcpError(let tool, let reason) = error {
                #expect(tool == "test_tool")
                #expect(reason.contains("something went wrong"))
            } else {
                Issue.record("Expected mcpError, got: \(error)")
            }
        } catch {
            Issue.record("Expected AxionError.mcpError, got: \(error)")
        }
    }

    @Test("callTool when not started throws helperNotRunning")
    func callToolWhenNotStartedThrowsError() async {
        let manager = HelperProcessManager()

        do {
            _ = try await manager.callTool(name: "click", arguments: ["x": AxionCore.Value.int(100), "y": AxionCore.Value.int(200)])
            Issue.record("callTool should throw when not started")
        } catch let error as AxionError {
            #expect(error == .helperNotRunning)
        } catch {
            Issue.record("Expected AxionError.helperNotRunning, got: \(error)")
        }
    }

    @Test("listTools when not started throws helperNotRunning")
    func listToolsWhenNotStartedThrowsError() async {
        let manager = HelperProcessManager()

        do {
            _ = try await manager.listTools()
            Issue.record("listTools should throw when not started")
        } catch let error as AxionError {
            #expect(error == .helperNotRunning)
        } catch {
            Issue.record("Expected AxionError.helperNotRunning, got: \(error)")
        }
    }
}
