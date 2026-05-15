# OpenAgentSDK 快速开始

> Swift AI Agent SDK -- 用几行代码构建智能代理应用

## 系统要求

- **Swift 6.1+**（swift-tools-version: 6.1）
- **macOS 14+**（Sonoma 及以上）
- **Xcode 16+**

---

## 1. 五分钟快速开始教程

### 1.1 添加 SPM 依赖

在 `Package.swift` 中添加 OpenAgentSDK 依赖：

```swift
// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MyAgentApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(
            url: "https://github.com/terryso/open-agent-sdk-swift.git",
            from: "0.1.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "MyAgentApp",
            dependencies: ["OpenAgentSDK"]
        )
    ]
)
```

### 1.2 配置 API Key

**方式一：环境变量（推荐）**

```bash
# Anthropic 官方 API
export ANTHROPIC_API_KEY="sk-ant-..."

# 或使用 OpenAI 兼容提供商（GLM、DeepSeek、Ollama 等）
export CODEANY_API_KEY="your-key"
export CODEANY_BASE_URL="https://api.deepseek.com/v1"
export CODEANY_MODEL="deepseek-chat"
```

**方式二：代码中直接指定**

```swift
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-ant-...",
    model: "claude-sonnet-4-6"
))
```

**方式三：使用 .env 文件**

SDK 提供 `loadDotEnv()` 辅助函数加载 `.env` 文件：

```swift
let dotEnv = loadDotEnv()
let apiKey = getEnv("ANTHROPIC_API_KEY", from: dotEnv) ?? "sk-..."
```

### 1.3 第一个 Agent

创建 `Sources/MyAgentApp/main.swift`：

```swift
import Foundation
import OpenAgentSDK

// 创建 Agent
let agent = createAgent(options: AgentOptions(
    apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
    systemPrompt: "你是一个有用的助手。回答要简洁。",
    maxTurns: 10,
    permissionMode: .bypassPermissions
))

print("Agent 已创建: \(agent)")

// 发送提示并获取结果
let result = await agent.prompt("用一段话解释什么是 AI Agent。")

print("回答: \(result.text)")
print()
print("--- 查询统计 ---")
print("  状态: \(result.status)")
print("  轮次: \(result.numTurns)")
print("  耗时: \(result.durationMs)ms")
print("  输入 token: \(result.usage.inputTokens)")
print("  输出 token: \(result.usage.outputTokens)")
print("  费用: $\(String(format: "%.6f", result.totalCostUsd))")
```

运行：

```bash
swift run MyAgentApp
```

### 1.4 流式响应

使用 `agent.stream()` 逐事件接收响应，适合实时输出场景：

```swift
for await message in agent.stream("写一首关于编程的俳句。") {
    switch message {
    case .partialMessage(let data):
        print(data.text, terminator: "")
    case .toolUse(let data):
        print("[工具调用: \(data.toolName)]")
    case .toolResult(let data):
        print(data.isError ? "[错误: \(data.content)]" : "[结果: \(data.content)]")
    case .result(let data):
        print("\n轮次: \(data.numTurns), 耗时: \(data.durationMs)ms, 费用: $\(String(format: "%.6f", data.totalCostUsd))")
    default:
        break
    }
}
```

---

## 2. API Key 配置说明

### 2.1 Anthropic 官方 API

最简配置，只需一个 API Key：

```swift
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-ant-...",
    model: "claude-sonnet-4-6"  // 默认模型
))
```

### 2.2 环境变量自动发现

设置 `ANTHROPIC_API_KEY` 后可省略所有参数：`let agent = createAgent()` 自动从环境变量读取。

### 2.3 OpenAI 兼容提供商

支持任何兼容 OpenAI Chat API 的后端（GLM、DeepSeek、Qwen、Ollama、vLLM 等）：

```swift
let agent = createAgent(options: AgentOptions(
    apiKey: "your-deepseek-key",
    model: "deepseek-chat",
    baseURL: "https://api.deepseek.com/v1",
    provider: .openai  // 关键：切换为 OpenAI 兼容模式
))
```

常用提供商配置示例：

| 提供商 | baseURL | model |
|--------|---------|-------|
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4` | `glm-4` |
| Ollama 本地 | `http://localhost:11434/v1` | `llama3` |
| OpenRouter | `https://openrouter.ai/api/v1` | `anthropic/claude-sonnet-4-6` |

使用环境变量配置 OpenAI 兼容提供商：设置 `CODEANY_API_KEY`、`CODEANY_BASE_URL`、`CODEANY_MODEL` 后，SDK 可自动检测并切换提供商。详见 SDK 示例 `Examples/OpenAICompatExample`。

---

## 3. 第一个 Agent 代码示例

### 3.1 最小可运行示例

以下代码可直接编译运行：

```swift
import Foundation
import OpenAgentSDK

// 1. 创建 Agent
let agent = createAgent(options: AgentOptions(
    apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]!,
    systemPrompt: "你是一个有用的助手。",
    permissionMode: .bypassPermissions
))

// 2. 阻塞式查询
let result = await agent.prompt("1+1等于几？")
print("回答: \(result.text)")
print("状态: \(result.status), 轮次: \(result.numTurns)")

// 3. 流式查询
print("\n--- 流式输出 ---")
for await message in agent.stream("用三个词描述 Swift。") {
    if case .partialMessage(let data) = message {
        print(data.text, terminator: "")
    }
    if case .result(let data) = message {
        print("\n费用: $\(String(format: "%.6f", data.totalCostUsd))")
    }
}
```

### 3.2 自定义工具（天气查询）

使用 `defineTool()` 定义自定义工具，支持 Codable 输入类型：

```swift
import Foundation
import OpenAgentSDK

// 定义 Codable 输入类型
struct WeatherInput: Codable {
    let city: String
    let unit: String?  // "celsius" 或 "fahrenheit"
}

// 使用 defineTool 创建工具
let weatherTool = defineTool(
    name: "get_weather",
    description: "查询指定城市的当前天气",
    inputSchema: [
        "type": "object",
        "properties": [
            "city": ["type": "string", "description": "城市名称，如 '北京'"],
            "unit": ["type": "string", "description": "温度单位：'celsius' 或 'fahrenheit'"]
        ],
        "required": ["city"]
    ],
    isReadOnly: true
) { (input: WeatherInput, context: ToolContext) -> String in
    // 实际应用中调用真实天气 API
    let unit = input.unit ?? "celsius"
    let temp = unit == "fahrenheit" ? "72F" : "22C"
    return "\(input.city)天气：晴，温度 \(temp)"
}

// 创建带工具的 Agent
let agent = createAgent(options: AgentOptions(
    apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]!,
    systemPrompt: "你是一个天气助手，可以查询城市天气。",
    permissionMode: .bypassPermissions,
    tools: [weatherTool]
))

// 发送需要工具调用的查询
let result = await agent.prompt("东京和纽约今天天气怎么样？")

print("回答: \(result.text)")
print("轮次: \(result.numTurns)")  // 工具调用会增加轮次
print("费用: $\(String(format: "%.6f", result.totalCostUsd))")
```

`defineTool` 支持两种返回类型：`String`（自动视为成功）或 `ToolExecuteResult`（可通过 `isError` 标记错误）。

### 3.3 使用预算限制

设置 `maxBudgetUsd` 防止意外超支：

```swift
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...",
    maxBudgetUsd: 0.50,  // 最多花费 $0.50
    permissionMode: .bypassPermissions
))
```

当费用超限时，查询会自动终止，`result.subtype` 为 `.errorMaxBudgetUsd`。

---

## 4. 常见问题排查

### 编译错误

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `swift-tools-version: 6.1` | Swift 版本过低 | 升级到 Swift 6.1+（Xcode 26+） |
| `platforms: [.macOS(.v14)]` | macOS 版本过低 | 升级到 macOS 14 Sonoma 及以上 |
| `cannot find 'createAgent' in scope` | 未导入 SDK | 添加 `import OpenAgentSDK` |
| `type 'AgentOptions' has no member` | SDK 版本不匹配 | 更新 SPM 依赖到最新版本 |

### API 连接问题

| 症状 | 可能原因 | 解决方案 |
|------|---------|---------|
| `[401] authentication_error` | API Key 无效 | 检查 key 是否正确、是否过期 |
| `[403] permission_error` | 账户权限不足 | 确认账户已开通 API 访问权限 |
| `[429] rate_limit_error` | 请求频率超限 | 降低请求频率或升级 API 套餐 |
| `[500] server_error` | 服务端错误 | 稍后重试，SDK 内置自动重试机制 |
| 连接超时 | 网络问题 | 检查网络代理、防火墙设置 |
| `Invalid baseURL` | OpenAI 兼容 URL 格式错误 | 确认 baseURL 包含完整路径（如 `/v1`） |

使用 OpenAI 兼容提供商时须设置 `provider: .openai`，确认 `baseURL` 有效且目标提供商支持 `tools` 参数。

### 权限问题

| 症状 | 原因 | 解决方案 |
|------|------|---------|
| 工具被拒绝执行 | `permissionMode` 限制 | 开发阶段使用 `.bypassPermissions` |
| Sandbox 权限错误 | macOS 沙箱限制 | 移除 Package.swift 沙箱限制 |
| 文件读写失败 | 文件系统权限 | 检查 `cwd` 目录权限 |

可用权限模式：`.bypassPermissions`（开发）、`.default`、`.acceptEdits`、`.plan`、`.auto`。

### 运行环境检查

```bash
swift --version              # 需要 6.1+
sw_vers                      # macOS 14.0+
echo $ANTHROPIC_API_KEY      # 确认 Key 已设置
swift package resolve        # 确认依赖已解析
```

---

## 核心类型速查

```swift
// 创建 Agent
func createAgent(options: AgentOptions? = nil) -> Agent

// 阻塞查询
agent.prompt("任务") -> QueryResult

// 流式查询
agent.stream("任务") -> AsyncStream<SDKMessage>

// QueryResult 字段
result.text          // String - 回答文本
result.usage         // TokenUsage - token 用量
result.numTurns      // Int - 轮次
result.durationMs    // Int - 耗时（毫秒）
result.totalCostUsd  // Double - 费用（美元）
result.status        // QueryStatus - 终止状态

// SDKMessage 主要事件
.partialMessage(PartialData)   // 增量文本
.assistant(AssistantData)      // 完整助手消息
.toolUse(ToolUseData)          // 工具调用
.toolResult(ToolResultData)    // 工具结果
.result(ResultData)            // 最终结果
.system(SystemData)            // 系统事件

// 默认值
model:     "claude-sonnet-4-6"
maxTurns:  10
maxTokens: 16384
```
