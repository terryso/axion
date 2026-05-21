import Foundation
import OpenAgentSDK

import AxionCore

/// Orchestrator that creates an Agent, assembles tools, and runs
/// an AgentMCPServer exposing Axion's capabilities via MCP stdio.
///
/// **Design Decisions:**
/// - **MCP Server mode (Epic 6)**: Axion runs as an MCP server (`axion mcp`) so external agents
///   (Claude Code, Cursor, etc.) can call Axion's desktop automation tools directly. This follows
///   the "tools as a service" pattern — the MCP consumer decides *what* to do, Axion executes *how*.
/// - **Tool merging strategy**: the tool pool combines Helper's AX tools (from MCP stdio discovery)
///   with two Axion-specific tools: `run_task` (queue a task for async execution) and
///   `query_task_status` (check progress). This gives MCP consumers both synchronous (direct tool
///   calls) and asynchronous (task submission) access patterns.
/// - **TaskQueue serialization**: MCP server mode uses a `TaskQueue` to serialize `agent.prompt()`
///   calls. This prevents concurrent LLM requests from interleaving, which would corrupt the
///   conversation context. The MCP protocol itself handles concurrent `tools/list` requests fine.
/// - **Graceful shutdown**: waits for `taskQueue.gracefulShutdown()` before closing the agent,
///   ensuring in-flight tasks complete rather than being abruptly terminated.
struct MCPServerRunner {

    // MARK: - Properties

    let config: AxionConfig
    let verbose: Bool

    // MARK: - Public API

    func run() async throws {
        // Build agent via shared builder (API key, helper path, memory, prompt, MCP, hooks)
        let buildConfig = AgentBuilder.BuildConfig.forMCP(
            config: config,
            verbose: verbose
        )

        let buildResult: AgentBuildResult
        do {
            buildResult = try await AgentBuilder.build(buildConfig)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            return
        }
        let agent = buildResult.agent

        // Assemble tool pool (connects to Helper, discovers tools)
        let (helperTools, _) = await agent.assembleFullToolPool()

        // Create RunTracker and custom tools
        let runTracker = RunCoordinator()
        let taskQueue = TaskQueue()
        let runTaskTool = RunTaskTool(agent: agent, runTracker: runTracker, taskQueue: taskQueue, runLockService: nil)
        let queryTool = QueryTaskStatusTool(runTracker: runTracker)

        // Merge all tools
        var allTools = helperTools
        allTools.append(runTaskTool)
        allTools.append(queryTool)

        // Create and run MCP server
        let version = AxionVersion.current
        let server = AgentMCPServer(name: "axion", version: version, tools: allTools)

        fputs("Axion MCP server running (version \(version))\n", stderr)
        try await server.run(agent: agent)

        // Cleanup — wait for in-flight tasks before closing agent
        await taskQueue.gracefulShutdown()
        try? await agent.close()
        fputs("Axion MCP server stopped.\n", stderr)
    }
}
