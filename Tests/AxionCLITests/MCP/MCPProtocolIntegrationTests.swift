import Testing
import Foundation
import MCP
import OpenAgentSDK
@testable import AxionCLI

@Suite("MCPProtocolIntegration")
struct MCPProtocolIntegrationTests {

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

    @Test("MCP initialize handshake returns capabilities")
    func mcpInitializeHandshakeReturnsCapabilities() async throws {
        let (_, mcpServer, client) = try await createTestServer(tools: [])

        let serverInfo = await client.serverInfo
        #expect(serverInfo != nil)

        await mcpServer.stop()
        await client.disconnect()
    }

    @Test("MCP initialize tools capability enabled")
    func mcpInitializeToolsCapabilityEnabled() async throws {
        let (_, mcpServer, client) = try await createTestServer(tools: [])

        let result = try await client.listTools()
        #expect(!result.tools.isEmpty)

        await mcpServer.stop()
        await client.disconnect()
    }

    @Test("tools/list returns run_task and query_task_status")
    func toolsListReturnsRunTaskAndQueryStatus() async throws {
        let runTask = createRunTaskTool()
        let queryTool = createQueryTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        let result = try await client.listTools()
        let toolNames = Set(result.tools.map { $0.name })

        #expect(toolNames.contains("run_task"))
        #expect(toolNames.contains("query_task_status"))

        await mcpServer.stop()
        await client.disconnect()
    }

    @Test("tool has name, description, and schema")
    func toolsListToolHasNameDescriptionSchema() async throws {
        let runTask = createRunTaskTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask])

        let result = try await client.listTools()
        let tool = result.tools.first(where: { $0.name == "run_task" })

        #expect(tool != nil)
        #expect(tool?.description != nil)
        #expect(tool?.inputSchema != nil)

        await mcpServer.stop()
        await client.disconnect()
    }

    @Test("tool_call run_task returns run_id")
    func toolCallRunTaskReturnsRunId() async throws {
        let runTask = createRunTaskTool()
        let queryTool = createQueryTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        let result = try await client.callTool(
            name: "run_task",
            arguments: ["task": .string("open calculator")]
        )

        #expect(result.isError != true)

        let responseText = extractTextContent(from: result)
        #expect(responseText.contains("run_id"))
        #expect(responseText.contains("running"))

        await mcpServer.stop()
        await client.disconnect()
    }

    @Test("query_task_status for unknown run_id returns error")
    func toolCallQueryStatusUnknownRunIdReturnsError() async throws {
        let runTask = createRunTaskTool()
        let queryTool = createQueryTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        let result = try await client.callTool(
            name: "query_task_status",
            arguments: ["run_id": .string("nonexistent-run-id")]
        )

        #expect(result.isError == true)

        let responseText = extractTextContent(from: result)
        #expect(responseText.contains("not_found"))

        await mcpServer.stop()
        await client.disconnect()
    }

    @Test("run_task then query_task_status succeeds")
    func toolCallRunTaskThenQueryStatusSucceeds() async throws {
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

        let runResult = try await client.callTool(
            name: "run_task",
            arguments: ["task": .string("open calculator")]
        )
        #expect(runResult.isError != true)

        let responseText = extractTextContent(from: runResult)
        let pattern = #"run_id":"([^"]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(responseText.startIndex..., in: responseText)
        let match = regex.firstMatch(in: responseText, range: nsRange)
        #expect(match != nil)
        let runId: String
        if let match = match,
           let range = Range(match.range(at: 1), in: responseText) {
            runId = String(responseText[range])
        } else {
            Issue.record("Could not extract run_id from response")
            return
        }

        let statusResult = try await client.callTool(
            name: "query_task_status",
            arguments: ["run_id": .string(runId)]
        )
        #expect(statusResult.isError != true)

        let statusText = extractTextContent(from: statusResult)
        #expect(statusText.contains(runId))

        await mcpServer.stop()
        await client.disconnect()
    }

    @Test("graceful shutdown on transport disconnect")
    func gracefulShutdownOnTransportDisconnect() async throws {
        let runTask = createRunTaskTool()
        let server = AgentMCPServer(name: "shutdown-test", version: "1.0.0", tools: [runTask])

        let (mcpServer, clientTransport) = try await server.createSession()
        let client = Client(name: "shutdown-client", version: "1.0.0")
        try await client.connect(transport: clientTransport)

        let listResult = try await client.listTools()
        #expect(!listResult.tools.isEmpty)

        await client.disconnect()
        await mcpServer.stop()
    }

    @Test("server remains operational after tool error")
    func serverRemainsOperationalAfterToolError() async throws {
        let runTask = createRunTaskTool()
        let queryTool = createQueryTool()
        let (_, mcpServer, client) = try await createTestServer(tools: [runTask, queryTool])

        _ = try await client.callTool(
            name: "query_task_status",
            arguments: ["run_id": .string("nonexistent")]
        )

        let listResult = try await client.listTools()
        #expect(!listResult.tools.isEmpty)

        let runResult = try await client.callTool(
            name: "run_task",
            arguments: ["task": .string("test task")]
        )
        #expect(runResult.isError != true)

        await mcpServer.stop()
        await client.disconnect()
    }

    private func extractTextContent(from result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let text, _, _) = content {
                return text
            }
            return nil
        }.joined()
    }
}
