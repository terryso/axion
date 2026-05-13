// AgentMCPServerExample 示例
//
// 演示 Agent 作为 MCP Server 的能力（Agent-as-MCP-Server），包括：
//   1. 创建自定义工具并注册到 AgentMCPServer
//   2. 使用 AgentMCPServer 将工具暴露为 MCP 服务
//   3. 通过 InMemoryTransport 进行进程内 MCP 协议通信
//   4. MCP 客户端发现工具列表（tools/list）
//   5. MCP 客户端调用工具（tools/call）
//   6. agent_prompt 特殊工具：提交任务给 Agent 进行完整执行
//
// Demonstrates Agent-as-MCP-Server capability:
//   1. Create custom tools and register with AgentMCPServer
//   2. Use AgentMCPServer to expose tools as an MCP service
//   3. In-process MCP protocol communication via InMemoryTransport
//   4. MCP client discovers tools (tools/list)
//   5. MCP client invokes tools (tools/call)
//   6. agent_prompt special tool: submit task for full Agent execution
//
// 运行方式：swift run AgentMCPServerExample
// 说明：无需 API Key（使用 InMemoryTransport 进行进程内通信）

import Foundation
import OpenAgentSDK
import MCP

print("=== AgentMCPServerExample ===")
print()

// MARK: - Part 1: Create Custom Tools（创建自定义工具）

print("--- Part 1: Create Custom Tools ---")
print()

// 定义一个简单的计算器工具
struct CalculatorInput: Codable {
    let expression: String
}

let calculatorTool = defineTool(
    name: "calculator",
    description: "Evaluate a simple math expression. Supports +, -, *, / operations.",
    inputSchema: [
        "type": "object",
        "properties": [
            "expression": ["type": "string", "description": "The math expression to evaluate, e.g. '2 + 3'"]
        ],
        "required": ["expression"]
    ],
    isReadOnly: true
) { (input: CalculatorInput, context: ToolContext) -> String in
    let expr = input.expression.replacingOccurrences(of: " ", with: "")
    let parts: [String]
    if expr.contains("+") {
        parts = expr.components(separatedBy: "+")
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) else {
            return "Error: invalid expression"
        }
        return "\(a + b)"
    } else if expr.contains("*") {
        parts = expr.components(separatedBy: "*")
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) else {
            return "Error: invalid expression"
        }
        return "\(a * b)"
    } else if expr.contains("-") {
        parts = expr.components(separatedBy: "-")
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) else {
            return "Error: invalid expression"
        }
        return "\(a - b)"
    } else if expr.contains("/") {
        parts = expr.components(separatedBy: "/")
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 else {
            return "Error: invalid expression or division by zero"
        }
        return "\(a / b)"
    }
    return "Error: unsupported operation"
}

// 定义一个问候工具
let greetingTool = defineTool(
    name: "greeting",
    description: "Generate a greeting message for a given name.",
    inputSchema: [
        "type": "object",
        "properties": [
            "name": ["type": "string", "description": "The name to greet"]
        ],
        "required": ["name"]
    ],
    isReadOnly: true
) { (input: [String: Any], context: ToolContext) -> ToolExecuteResult in
    let name = input["name"] as? String ?? "World"
    return ToolExecuteResult(content: "Hello, \(name)! Welcome to OpenAgentSDK.", isError: false)
}

print("[Created calculator and greeting tools]")
print()

// MARK: - Part 2: Create AgentMCPServer and Connect Client（创建服务并连接客户端）

print("--- Part 2: Create AgentMCPServer and Connect Client ---")
print()

// 创建 AgentMCPServer，传入工具列表
// AgentMCPServer 会自动将所有工具注册为 MCP 工具
// 同时自动注册 agent_prompt 特殊工具
let mcpServer = AgentMCPServer(
    name: "example-agent-server",
    version: "1.0.0",
    tools: [calculatorTool, greetingTool]
)

print("[AgentMCPServer created: \(await mcpServer.name) v\(await mcpServer.version)]")

// 创建进程内 MCP 会话
// createSession() 返回 (MCPServer, InMemoryTransport) 对
// InMemoryTransport 是客户端侧的传输层
let (server, clientTransport) = try await mcpServer.createSession()

// 创建 MCP 客户端并连接
let client = Client(name: "example-client", version: "1.0.0")
try await client.connect(transport: clientTransport)

print("[MCP client connected to server via InMemoryTransport]")

// 验证初始化握手完成
let serverInfo = await client.serverInfo
print("[Server info received: \(serverInfo?.name ?? "nil")]")
print()

// MARK: - Part 3: Discover Tools via MCP（通过 MCP 发现工具）

print("--- Part 3: Discover Tools via MCP ---")
print()

let toolsResult = try await client.listTools()
print("[Discovered \(toolsResult.tools.count) tools via MCP:]")
for tool in toolsResult.tools {
    print("  - \(tool.name): \(tool.description ?? "no description")")
}

// 验证工具已注册
let toolNames = toolsResult.tools.map { $0.name }
assert(toolNames.contains("calculator"), "calculator tool should be registered")
assert(toolNames.contains("greeting"), "greeting tool should be registered")
assert(toolNames.contains("agent_prompt"), "agent_prompt special tool should always be registered")
print()
print("✅ Tool discovery via MCP: PASS")
print()

// MARK: - Part 4: Call Tool via MCP（通过 MCP 调用工具）

print("--- Part 4: Call Tool via MCP ---")
print()

// 调用 calculator 工具
let calcResult = try await client.callTool(
    name: "calculator",
    arguments: ["expression": .string("2 + 3")]
)
print("[calculator('2 + 3') result:]")
for content in calcResult.content {
    print("  \(content)")
}
assert(calcResult.isError != true, "Tool call should succeed")
print("✅ Calculator tool call: PASS")
print()

// 调用 greeting 工具
let greetResult = try await client.callTool(
    name: "greeting",
    arguments: ["name": .string("Swift Developer")]
)
print("[greeting('Swift Developer') result:]")
for content in greetResult.content {
    print("  \(content)")
}
assert(greetResult.isError != true, "Tool call should succeed")
print("✅ Greeting tool call: PASS")
print()

// MARK: - Part 5: agent_prompt Tool（agent_prompt 特殊工具）

print("--- Part 5: agent_prompt Tool ---")
print()

// agent_prompt 是 AgentMCPServer 自动注册的特殊工具
// 允许 MCP 客户端提交任务给 Agent 进行完整执行
print("[agent_prompt tool is always registered by AgentMCPServer]")
print("[It allows MCP clients to submit tasks for full Agent execution]")
print("[In production, this would invoke agent.stream() and return the final result]")
print()
print("✅ agent_prompt tool registered: PASS")
print()

// 清理：关闭客户端连接
await server.stop()
await client.disconnect()
print("[MCP session closed]")
print()

print("=== AgentMCPServerExample Complete ===")
