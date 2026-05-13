import XCTest
import MCP
import OpenAgentSDK
@testable import AxionCLI

// [P0] ATDD — Story 6.2 AC1, AC2: MCP 协议集成测试

final class MCPProtocolIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func createTestServer(
        tools: [ToolProtocol]
    ) async throws -> (AgentMCPServer, Server, Client) {
        let agentServer = AgentMCPServer(
            name: "axion-test",
            version: "1.0.0",
            tools: tools
        )
        let (mcpServer, clientTransport) = try await agentServer.createSession()
        let client = Client(name: "test-client", version: "1.0.0")
        try await client.connect(transport: clientTransport)
        return (agentServer, mcpServer, client)
    }

    private func createRunTaskTool() -> RunTaskTool {
        let tracker = RunTracker()
        let queue = TaskQueue()
        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "test-model",
            systemPrompt: "test",
            maxTurns: 1,
            maxTokens: 100,
            permissionMode: .bypassPermissions
        ))
        return RunTaskTool(agent: agent, runTracker: tracker, taskQueue: queue)
    }

    private func createQueryTool() -> QueryTaskStatusTool {
        QueryTaskStatusTool(runTracker: RunTracker())
    }

    // MARK: - 3.2: MCP initialize 握手

    func test_mcpInitialize_handshake_returnsCapabilities() async throws {
        let (_, mcpServer, client) = try await createTestServer(tools: [])

        let serverInfo = await client.serverInfo
        XCTAssertNotNil(serverInfo, "Client should have server info after initialize")

        await mcpServer.stop()
        await client.disconnect()
    }

    func test_mcpInitialize_toolsCapabilityEnabled() async throws {
        let (_, mcpServer, client) = try await createTestServer(tools: [])

        let result = try await client.listTools()
        XCTAssertNotNil(result, "Client should be able to list tools")

        await mcpServer.stop()
        await client.disconnect()
    }

    // MARK: - 3.3: tools/list 返回预期工具

    func test_toolsList_returnsRunTaskAndQueryStatus() async throws {
        let runTask = createRunTaskTool()
        let queryTool = createQueryTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        let result = try await client.listTools()
        let toolNames = Set(result.tools.map { $0.name })

        XCTAssertTrue(toolNames.contains("run_task"),
                       "Tool list should contain run_task")
        XCTAssertTrue(toolNames.contains("query_task_status"),
                       "Tool list should contain query_task_status")

        await mcpServer.stop()
        await client.disconnect()
    }

    func test_toolsList_toolHasNameDescriptionSchema() async throws {
        let runTask = createRunTaskTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask])

        let result = try await client.listTools()
        let tool = result.tools.first(where: { $0.name == "run_task" })

        XCTAssertNotNil(tool, "Should find run_task in tool list")
        XCTAssertNotNil(tool?.description, "Tool should have description")
        XCTAssertNotNil(tool?.inputSchema, "Tool should have inputSchema")

        await mcpServer.stop()
        await client.disconnect()
    }

    // MARK: - 3.4: tool_call run_task 返回 run_id JSON

    func test_toolCall_runTask_returnsRunId() async throws {
        let runTask = createRunTaskTool()
        let queryTool = createQueryTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        let result = try await client.callTool(
            name: "run_task",
            arguments: ["task": .string("open calculator")]
        )

        XCTAssertNotEqual(result.isError, true, "run_task should succeed")

        let responseText = extractTextContent(from: result)
        XCTAssertTrue(responseText.contains("run_id"),
                       "run_task response should contain run_id")
        XCTAssertTrue(responseText.contains("running"),
                       "run_task response should contain 'running' status")

        await mcpServer.stop()
        await client.disconnect()
    }

    // MARK: - 3.5: query_task_status 对未知 run_id 返回错误

    func test_toolCall_queryStatus_unknownRunId_returnsError() async throws {
        let runTask = createRunTaskTool()
        let queryTool = createQueryTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        let result = try await client.callTool(
            name: "query_task_status",
            arguments: ["run_id": .string("nonexistent-run-id")]
        )

        XCTAssertEqual(result.isError, true,
                         "Query for unknown run_id should return isError: true")

        let responseText = extractTextContent(from: result)
        XCTAssertTrue(responseText.contains("not_found"),
                       "Error response should contain 'not_found'")

        await mcpServer.stop()
        await client.disconnect()
    }

    func test_toolCall_runTask_thenQueryStatus_succeeds() async throws {
        let tracker = RunTracker()
        let queue = TaskQueue()
        let agent = createAgent(options: AgentOptions(
            apiKey: "test-key",
            model: "test-model",
            systemPrompt: "test",
            maxTurns: 1,
            maxTokens: 100,
            permissionMode: .bypassPermissions
        ))
        let runTask = RunTaskTool(agent: agent, runTracker: tracker, taskQueue: queue)
        let queryTool = QueryTaskStatusTool(runTracker: tracker)
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        // Submit a task
        let runResult = try await client.callTool(
            name: "run_task",
            arguments: ["task": .string("open calculator")]
        )
        XCTAssertNotEqual(runResult.isError, true, "run_task should succeed")

        // Extract run_id from JSON response
        let responseText = extractTextContent(from: runResult)
        let pattern = #"run_id":"([^"]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(responseText.startIndex..., in: responseText)
        let match = regex.firstMatch(in: responseText, range: nsRange)
        XCTAssertNotNil(match, "Response should contain a run_id")
        let runId: String
        if let match = match,
           let range = Range(match.range(at: 1), in: responseText) {
            runId = String(responseText[range])
        } else {
            XCTFail("Could not extract run_id from response")
            return
        }

        // Query the status with the real run_id
        let statusResult = try await client.callTool(
            name: "query_task_status",
            arguments: ["run_id": .string(runId)]
        )
        XCTAssertNotEqual(statusResult.isError, true,
                            "Query with valid run_id should succeed")

        let statusText = extractTextContent(from: statusResult)
        XCTAssertTrue(statusText.contains(runId),
                       "Status response should contain the run_id")

        await mcpServer.stop()
        await client.disconnect()
    }

    // MARK: - 3.6: stdin EOF 触发优雅退出

    func test_gracefulShutdown_onTransportDisconnect() async throws {
        let runTask = createRunTaskTool()
        let server = AgentMCPServer(name: "shutdown-test", version: "1.0.0", tools: [runTask])

        let (mcpServer, clientTransport) = try await server.createSession()
        let client = Client(name: "shutdown-client", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        // Verify session works before disconnect
        let listResult = try await client.listTools()
        XCTAssertFalse(listResult.tools.isEmpty)

        // Disconnect (simulates EOF)
        await client.disconnect()
        await mcpServer.stop()
        // If we get here without hanging, shutdown was graceful
    }

    // MARK: - Server remains operational after tool error

    func test_serverRemainsOperational_afterToolError() async throws {
        let runTask = createRunTaskTool()
        let queryTool = createQueryTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        // Trigger error with unknown run_id
        _ = try await client.callTool(
            name: "query_task_status",
            arguments: ["run_id": .string("nonexistent")]
        )

        // Server should still work — list tools
        let listResult = try await client.listTools()
        XCTAssertFalse(listResult.tools.isEmpty, "Server should still list tools after error")

        // Server should still work — call run_task
        let runResult = try await client.callTool(
            name: "run_task",
            arguments: ["task": .string("test task")]
        )
        XCTAssertNotEqual(runResult.isError, true, "run_task should still work after error")

        await mcpServer.stop()
        await client.disconnect()
    }

    // MARK: - Helpers

    private func extractTextContent(from result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let text, _, _) = content {
                return text
            }
            return nil
        }.joined()
    }
}
