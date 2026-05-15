# MCP 集成指南

本文介绍如何在 OpenAgentSDK 中集成 MCP（Model Context Protocol）服务器，为 Agent 添加外部工具能力。

---

## 1. MCP 协议概念介绍

### 什么是 MCP？

MCP（Model Context Protocol）是一种开放协议，用于在 LLM 应用与外部工具/数据源之间建立标准化通信。它定义了工具发现、调用和结果返回的统一规范，使 Agent 能以一致的方式接入任意工具提供方。

### 传输模式

MCP 支持四种传输模式：

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| **stdio** | 启动子进程，通过 stdin/stdout 通信 | 本地 CLI 工具、命令行 MCP 服务器 |
| **SSE** | 通过 Server-Sent Events 连接远程端点 | 远程 MCP 服务、Web 托管服务 |
| **HTTP** | 通过 HTTP POST 请求通信 | 远程 MCP 服务（非流式） |
| **SDK（进程内）** | 直接引用 `InProcessMCPServer`，无协议开销 | 自定义 Swift 工具、高性能场景 |

### MCP 如何实现工具集成

Agent 启动时连接配置的 MCP 服务器，执行 MCP 握手（`initialize`），然后通过 `listTools` 发现可用工具。发现的工具以 `mcp__{serverName}__{toolName}` 格式注册到 Agent 的工具池中，LLM 即可像调用内置工具一样调用它们。

---

## 2. McpServerConfig 配置说明

`McpServerConfig` 是一个枚举，每个 case 对应一种传输方式。通过 `AgentOptions` 的 `mcpServers` 参数传入：

```swift
let options = AgentOptions(
    mcpServers: ["serverName": config]
)
```

### 2.1 stdio 模式

启动子进程，通过标准输入/输出通信。适用于本地命令行 MCP 服务器。

```swift
let config = McpServerConfig.stdio(McpStdioConfig(
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
    env: ["NODE_ENV": "production"]
))
```

参数说明：
- `command`：要执行的命令（如 `npx`、`python3`、`axion`）
- `args`：传给命令的参数列表（可选）
- `env`：子进程的环境变量（可选）

### 2.2 SSE 模式

通过 Server-Sent Events 连接远程 MCP 端点。

```swift
let config = McpServerConfig.sse(McpSseConfig(
    url: "https://mcp.example.com/sse",
    headers: ["Authorization": "Bearer token123"]
))
```

### 2.3 HTTP 模式

通过 HTTP POST 请求与远程 MCP 服务器通信（非流式）。

```swift
let config = McpServerConfig.http(McpHttpConfig(
    url: "https://mcp.example.com/mcp",
    headers: ["X-API-Key": "key123"]
))
```

### 2.4 SDK 模式（进程内）

直接使用 `InProcessMCPServer` 实例，无需启动外部进程，零协议开销。

```swift
let server = InProcessMCPServer(
    name: "my-tools",
    version: "1.0.0",
    tools: [tool1, tool2],
    cwd: "/Users/me/project"
)
let config = server.asConfig()  // 返回 McpServerConfig.sdk(...)
```

### 完整配置示例

```swift
let options = AgentOptions(
    apiKey: "sk-...",
    model: "claude-sonnet-4-6",
    mcpServers: [
        "filesystem": .stdio(McpStdioConfig(
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
        )),
        "remote-api": .sse(McpSseConfig(
            url: "https://mcp.example.com/sse"
        )),
        "my-tools": server.asConfig()
    ]
)
```

---

## 3. 集成 Axion 的 axion mcp 作为桌面操作工具源

[Axion](https://github.com/nick/axion) 是一个 macOS 桌面自动化工具，提供应用启动、点击、输入文字、截图等能力。通过 MCP 集成，Agent 可以控制 macOS 桌面。

### 配置 Axion MCP

Axion 通过 stdio 模式接入，命令为 `axion mcp`：

```swift
let axionConfig = McpServerConfig.stdio(McpStdioConfig(
    command: "axion",
    args: ["mcp"]
))

let options = AgentOptions(
    apiKey: "sk-...",
    model: "claude-sonnet-4-6",
    systemPrompt: "你可以控制 macOS 桌面。使用 axion 工具来操作应用和屏幕。",
    mcpServers: [
        "axion": axionConfig
    ]
)

let agent = createAgent(options: options)
let result = await agent.prompt("打开 Safari 并访问 apple.com")
```

Axion 提供的桌面工具包括（注册后以 `mcp__axion__` 为前缀）：

| 工具名 | 功能 |
|--------|------|
| `launch_app` | 启动 macOS 应用 |
| `click` | 点击屏幕坐标 |
| `type_text` | 输入文字 |
| `screenshot` | 截取屏幕截图 |
| `get_active_window` | 获取当前活动窗口信息 |

---

## 4. 工具命名空间规则

### 命名模式

所有 MCP 工具按 `mcp__{serverName}__{toolName}` 格式命名，避免与内置工具冲突。

例如，服务器名为 `weather`，工具名为 `get_weather`，则完整工具名为：

```
mcp__weather__get_weather
```

> **注意：** 服务器名不能包含双下划线（`__`），否则会导致命名冲突。SDK 在初始化时会进行断言检查。

### 在 allowedTools / disallowedTools 中引用

```swift
let options = AgentOptions(
    mcpServers: [
        "weather": .stdio(McpStdioConfig(command: "weather-server")),
        "axion": .stdio(McpStdioConfig(command: "axion", args: ["mcp"]))
    ],
    // 只允许使用 weather 的 get_weather 和 axion 的 screenshot
    allowedTools: [
        "mcp__weather__get_weather",
        "mcp__axion__screenshot",
        "bash",       // 内置工具不受影响
        "file_read"
    ],
    // 禁止 axion 的 click（disallowedTools 优先级高于 allowedTools）
    disallowedTools: [
        "mcp__axion__click"
    ]
)
```

### LLM 如何看到命名空间工具名

Agent 将 MCP 工具的完整命名空间名称（如 `mcp__weather__get_weather`）作为工具名发送给 LLM。LLM 在 tool_use 响应中使用同样的完整名称。SDK 自动将调用路由到正确的 MCP 服务器和工具。

---

## 5. 自定义 MCP Server 开发

OpenAgentSDK 提供 `defineTool` 工厂函数，可快速创建自定义工具并包装为 `InProcessMCPServer`。

### 步骤 1：定义输入类型

```swift
struct WeatherInput: Codable {
    let city: String
}
```

### 步骤 2：用 defineTool 创建工具

```swift
let weatherTool = defineTool(
    name: "get_weather",
    description: "获取指定城市的当前天气信息。",
    inputSchema: [
        "type": "object",
        "properties": [
            "city": ["type": "string", "description": "城市名称"]
        ],
        "required": ["city"]
    ],
    isReadOnly: true
) { (input: WeatherInput, _: ToolContext) async throws -> String in
    // 实际场景中可调用天气 API
    return "\(input.city)：22°C，晴天"
}
```

### 步骤 3：包装为 InProcessMCPServer

```swift
let mcpServer = InProcessMCPServer(
    name: "weather-service",
    version: "1.0.0",
    tools: [weatherTool],
    cwd: "/Users/me/project"
)
```

### 步骤 4：注入 AgentOptions

```swift
let options = AgentOptions(
    apiKey: "sk-...",
    model: "claude-sonnet-4-6",
    mcpServers: ["weather": mcpServer.asConfig()]
)

let agent = createAgent(options: options)
let result = await agent.prompt("查询北京的天气")
// LLM 会调用 mcp__weather__get_weather，参数 {"city": "北京"}
```

### 多工具服务器示例

```swift
struct TranslateInput: Codable {
    let text: String
    let to: String
}

let translateTool = defineTool(
    name: "translate",
    description: "将文本翻译为目标语言。",
    inputSchema: [
        "type": "object",
        "properties": [
            "text": ["type": "string", "description": "待翻译文本"],
            "to": ["type": "string", "description": "目标语言"]
        ],
        "required": ["text", "to"]
    ],
    isReadOnly: true
) { (input: TranslateInput, _: ToolContext) async throws -> String in
    return "翻译结果：[\(input.text)] -> \(input.to) 模拟翻译"
}

let detectLangTool = defineTool(
    name: "detect_language",
    description: "检测文本的语言。",
    inputSchema: [
        "type": "object",
        "properties": [
            "text": ["type": "string", "description": "待检测文本"]
        ],
        "required": ["text"]
    ],
    isReadOnly: true
) { (input: TranslateInput, _: ToolContext) async throws -> String in
    return "检测到的语言：中文"
}

let server = InProcessMCPServer(
    name: "nlp-service",
    version: "1.0.0",
    tools: [translateTool, detectLangTool]
)
```

---

## 6. InProcessMCPServer 直接集成模式

`InProcessMCPServer` 是一个 Swift Actor，在进程内托管 MCP 工具，无需启动外部进程，适合高性能自定义工具场景。

### 核心用法

```swift
// 1. 创建工具
let screenshotTool = defineTool(
    name: "take_screenshot",
    description: "截取当前屏幕。",
    inputSchema: ["type": "object", "properties": [:] as [String: Any]],
    isReadOnly: true
) { (_: ToolContext) async throws -> String in
    return "screenshot_data_base64..."
}

let clickTool = defineTool(
    name: "click",
    description: "点击屏幕坐标。",
    inputSchema: [
        "type": "object",
        "properties": [
            "x": ["type": "number"],
            "y": ["type": "number"]
        ],
        "required": ["x", "y"]
    ]
) { (input: ClickInput, _: ToolContext) async throws -> String in
    return "已点击 (\(input.x), \(input.y))"
}

struct ClickInput: Codable {
    let x: Double
    let y: Double
}

// 2. 创建 InProcessMCPServer
let desktopServer = InProcessMCPServer(
    name: "desktop-ops",
    version: "1.0.0",
    tools: [screenshotTool, clickTool],
    cwd: "/Users/me"
)

// 3. 通过 asConfig() 获取配置
let config = desktopServer.asConfig()

// 4. 注入 Agent
let options = AgentOptions(
    apiKey: "sk-...",
    model: "claude-sonnet-4-6",
    systemPrompt: "你是一个桌面操作助手。",
    mcpServers: ["desktop": config]
)

let agent = createAgent(options: options)
```

### asConfig() 的工作原理

`asConfig()` 返回 `McpServerConfig.sdk(McpSdkServerConfig(...))`。Agent 在组装工具池时检测到 `.sdk` 类型，直接通过 `getTools()` 提取工具列表，跳过 MCP 协议握手，以零开销方式将工具注册到工具池。

### 多服务器混合配置

可将进程内服务器与外部 stdio/SSE 服务器混合使用：

```swift
let options = AgentOptions(
    apiKey: "sk-...",
    model: "claude-sonnet-4-6",
    mcpServers: [
        // 进程内工具（零开销）
        "weather": weatherServer.asConfig(),
        // 本地进程（stdio）
        "axion": .stdio(McpStdioConfig(command: "axion", args: ["mcp"])),
        // 远程服务（SSE）
        "search": .sse(McpSseConfig(url: "https://search-mcp.example.com/sse"))
    ]
)
```

---

## 总结

| 集成方式 | 配置类型 | 适用场景 |
|----------|----------|----------|
| 本地 CLI 工具 | `.stdio(McpStdioConfig)` | Axion、文件系统、数据库 CLI |
| 远程 MCP 服务 | `.sse(McpSseConfig)` / `.http(McpHttpConfig)` | 云端 API、Web 服务 |
| 自定义 Swift 工具 | `.sdk(InProcessMCPServer.asConfig())` | 高性能进程内工具 |
