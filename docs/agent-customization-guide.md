# OpenAgentSDK Agent 定制指南

通过 `AgentOptions`、Hook 系统、权限模式等机制定制 AI Agent。

---

## 一、AgentOptions 所有参数详解

`AgentOptions` 是创建 Agent 的核心配置，控制模型、工具、会话、权限等全部行为。

### 1.1 基础连接参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `apiKey` | `String?` | `nil` | API 密钥。`nil` 时从环境变量 `CODEANY_API_KEY` 读取 |
| `model` | `String` | `"claude-sonnet-4-6"` | 模型标识符 |
| `baseURL` | `String?` | `nil` | 自定义 API 端点。`nil` 使用提供商默认地址 |
| `provider` | `LLMProvider` | `.anthropic` | 提供商：`.anthropic` 或 `.openai` |

```swift
let options = AgentOptions(apiKey: "sk-...", model: "claude-sonnet-4-6",
    baseURL: "https://api.example.com/v1", provider: .anthropic)
```

### 1.2 提示词与输出参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `systemPrompt` | `String?` | `nil` | 系统提示词，定义角色与行为准则 |
| `systemPromptConfig` | `SystemPromptConfig?` | `nil` | 高级提示词配置，支持预设模板，优先于 `systemPrompt` |
| `maxTurns` | `Int` | `10` | Agent 循环最大轮次 |
| `maxTokens` | `Int` | `16384` | 单次请求最大输出 token 数 |
| `outputFormat` | `OutputFormat?` | `nil` | 结构化输出格式（JSON Schema） |
| `effort` | `EffortLevel?` | `nil` | 推理深度：`.low`(1024)/`.medium`(5120)/`.high`(10240)/`.max`(32768) token |

```swift
let options = AgentOptions(systemPrompt: "你是代码审查专家。",
    maxTurns: 20, effort: .high,
    outputFormat: OutputFormat(jsonSchema: [
        "type": "object", "properties": ["summary": ["type": "string"]]
    ])
)
```

### 1.3 预算与限制参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `maxBudgetUsd` | `Double?` | `nil` | 费用上限（美元），超出后终止循环 |
| `thinking` | `ThinkingConfig?` | `nil` | 思考/推理配置 |
| `fallbackModel` | `String?` | `nil` | 备用模型，主模型失败时自动切换 |

### 1.4 权限与安全参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `permissionMode` | `PermissionMode` | `.default` | 权限模式（见第四章详解） |
| `canUseTool` | `CanUseToolFn?` | `nil` | 自定义授权回调，优先于 `permissionMode` |
| `sandbox` | `SandboxSettings?` | `nil` | 沙箱设置，限制文件系统和命令访问 |

```swift
let options = AgentOptions(
    canUseTool: canUseTool(policy: ReadOnlyPolicy()),
    sandbox: SandboxSettings(deniedCommands: ["rm", "sudo"])
)
```

### 1.5 工具相关参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `tools` | `[ToolProtocol]?` | `nil` | 自定义工具数组 |
| `mcpServers` | `[String: McpServerConfig]?` | `nil` | MCP 服务器配置 |
| `allowedTools` | `[String]?` | `nil` | 工具白名单，`nil` 允许所有 |
| `disallowedTools` | `[String]?` | `nil` | 工具黑名单，优先于 `allowedTools` |
| `toolConfig` | `ToolConfig?` | `nil` | 工具并发配置 |

```swift
let options = AgentOptions(
    mcpServers: [
        "github": .stdio(McpStdioConfig(command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"])),
        "remote": .http(McpTransportConfig(url: "https://mcp.example.com/api"))
    ],
    allowedTools: ["Read", "Bash", "Write"], disallowedTools: ["Bash"]
)
```

### 1.6 会话与记忆参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `memoryStore` | `MemoryStoreProtocol?` | `nil` | 跨运行知识积累存储 |
| `sessionStore` | `SessionStore?` | `nil` | 会话持久化存储 |
| `sessionId` | `String?` | `nil` | 恢复会话 ID |
| `continueRecentSession` | `Bool` | `false` | 自动恢复最近会话 |
| `forkSession` | `Bool` | `false` | 分叉当前会话 |
| `resumeSessionAt` | `String?` | `nil` | 从指定消息 ID 处恢复 |
| `persistSession` | `Bool` | `true` | 查询后是否持久化 |

```swift
let options = AgentOptions(
    memoryStore: FileBasedMemoryStore(directory: "/data/mem"),
    sessionStore: SessionStore(directory: "/data/sessions"), sessionId: "sess-1"
)
```

### 1.7 Hook 与 Skill 参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `hookRegistry` | `HookRegistry?` | `nil` | 生命周期事件钩子注册表 |
| `skillRegistry` | `SkillRegistry?` | `nil` | 技能注册表 |
| `skillDirectories` | `[String]?` | `nil` | 自动扫描技能的目录 |
| `skillNames` | `[String]?` | `nil` | 白名单技能名称 |
| `maxSkillRecursionDepth` | `Int` | `4` | 技能嵌套最大深度 |

### 1.8 其他参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `cwd` | `String?` | `nil` | 工具执行工作目录 |
| `logLevel` | `LogLevel` | `.none` | 日志级别：`.none`/`.error`/`.warn`/`.info`/`.debug` |
| `logOutput` | `LogOutput` | `.console` | 日志目标：`.console`/`.file(url)`/`.custom` |
| `retryConfig` | `RetryConfig?` | `nil` | API 重试配置（见第六章） |
| `agentName` | `String?` | `nil` | Agent 名称（多 Agent 场景） |
| `env` | `[String: String]?` | `nil` | 注入工具执行环境的环境变量 |
| `projectRoot` | `String?` | `nil` | 项目根目录，`nil` 自动发现 |

---

## 二、createAgent API 说明

### 2.1 创建 Agent

```swift
public func createAgent(options: AgentOptions? = nil) -> Agent
```

`options` 为 `nil` 时从环境变量创建配置。三种创建方式：

```swift
// 完整配置
let agent = createAgent(options: AgentOptions(apiKey: "sk-...", model: "claude-sonnet-4-6"))
// 合并环境变量
let agent = createAgent(options: AgentOptions(from: SDKConfiguration(apiKey: "sk-...")))
// 纯环境变量（CODEANY_API_KEY / CODEANY_MODEL / CODEANY_BASE_URL）
let agent = createAgent()
```

### 2.2 Agent 方法

| 方法 | 签名 | 说明 |
|------|------|------|
| `prompt` | `func prompt(_ text: String) async -> QueryResult` | 发送提示并等待完整结果 |
| `stream` | `func stream(_ text: String) -> AsyncStream<SDKMessage>` | 流式返回消息 |
| `close` | `func close() async throws` | 关闭 Agent，释放资源 |
| `switchModel` | `func switchModel(_ model: String) throws` | 运行时切换模型 |
| `interrupt` | `func interrupt()` | 中断当前查询 |
| `getMessages` | `func getMessages() -> [SDKMessage]` | 获取最近查询消息 |
| `clear` | `func clear()` | 清除对话状态 |
| `setPermissionMode` | `func setPermissionMode(_ mode: PermissionMode)` | 动态切换权限 |
| `setCanUseTool` | `func setCanUseTool(_ callback: CanUseToolFn?)` | 动态设置授权 |

### 2.3 QueryResult 返回类型

`text`(回复)、`usage`(Token 统计)、`numTurns`(轮次)、`durationMs`(耗时)、`messages`(全部消息)、`status`(终止状态)、`totalCostUsd`(费用)、`costBreakdown`(按模型明细)、`isCancelled`(是否取消)、`errors`(错误消息)。

### 2.4 完整使用示例

```swift
import OpenAgentSDK
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...", model: "claude-sonnet-4-6",
    systemPrompt: "你是代码审查助手。", maxTurns: 10, maxBudgetUsd: 0.1
))
let result = await agent.prompt("审查代码：\n" + myCode)
print("回复: \(result.text), 费用: $\(result.totalCostUsd)")
for await msg in agent.stream("解释代码") { print(msg) }
try agent.switchModel("claude-opus-4")
try await agent.close()
```

---

## 三、System Prompt 设计指南和最佳实践

### 3.1 设计原则

优秀 System Prompt 包含：**角色定义**、**输出格式**、**约束规则**、**行为边界**。

### 3.2 代码审查 Agent

```swift
let prompt = """
你是一位资深代码审查专家。
## 职责：审查代码的安全性、性能、可维护性
## 输出格式：1.严重问题 2.改进建议 3.亮点
## 规则：用中文回复，标注严重级别（P0-P3），提供修改建议
"""
```

### 3.3 数据分析 Agent

```swift
let prompt = """
你是数据分析专家。使用 Markdown 格式，结论需数据支撑。
分析前确认数据源可靠性，不确定数据标注"待验证"。
"""
```

### 3.4 自动化 Agent

```swift
let prompt = """
你是自动化运维助手。
安全规则：危险操作先确认，不执行 rm -rf，修改前先备份。
工作流：理解意图 → 制定计划 → 确认 → 执行验证
"""
```

### 3.5 SystemPromptConfig 预设

```swift
// 预设模板 + 自定义追加
AgentOptions(systemPromptConfig: .preset(name: "claude_code", append: "请用中文回复。"))

// 或直接文本
AgentOptions(systemPrompt: "你是 Swift 开发者。")
```

---

## 四、PermissionMode 6 种模式详解

### 4.1 模式总览

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| `.bypassPermissions` | 无限制，所有工具自动执行 | 本地开发/测试 |
| `.default` | 危险操作需确认 | 一般用途 |
| `.acceptEdits` | 自动接受文件编辑，其他危险操作确认 | 代码编辑 |
| `.auto` | 自动接受安全操作 | 半自动化 |
| `.dontAsk` | 自动接受所有操作 | CI/CD |
| `.plan` | 只允许只读工具，需审批计划后写操作 | 规划模式 |

```swift
let devAgent = createAgent(options: AgentOptions(permissionMode: .bypassPermissions))
let ciAgent = createAgent(options: AgentOptions(permissionMode: .dontAsk))
```

### 4.2 自定义授权回调

```swift
// 内置策略组合
let policy = CompositePolicy(policies: [
    ToolNameDenylistPolicy(deniedToolNames: ["Bash", "Write"]),
    ReadOnlyPolicy()
])
let opts = AgentOptions(canUseTool: canUseTool(policy: policy))

// 自定义回调：工作时间允许写操作
let opts = AgentOptions(canUseTool: { tool, _, _ in
    let h = Calendar.current.component(.hour, from: Date())
    return (h >= 9 && h < 18) || tool.isReadOnly ? .allow() : .deny("非工作时间禁止")
})
```

### 4.3 动态切换
```swift
let agent = createAgent(options: AgentOptions(permissionMode: .default))
agent.setPermissionMode(.bypassPermissions)
```

---

## 五、Hook 系统详解

### 5.1 生命周期事件（23 种）

**工具：** `preToolUse`(执行前，可拦截)、`postToolUse`、`postToolUseFailure`
**会话：** `sessionStart`、`sessionEnd`、`stop`
**子 Agent：** `subagentStart`、`subagentStop`
**用户：** `userPromptSubmit`、`permissionRequest`、`permissionDenied`、`notification`
**系统：** `taskCreated`、`taskCompleted`、`configChange`、`cwdChanged`、`fileChanged`、`preCompact`、`postCompact`、`setup`、`worktreeCreate`、`worktreeRemove`、`teammateIdle`

### 5.2 HookRegistry 注册

```swift
let registry = HookRegistry()
await registry.register(.preToolUse, definition: HookDefinition(
    handler: { input in print("执行: \(input.toolName ?? "?")"); return nil }
))

// 批量注册
let registry = await createHookRegistry(config: [
    "preToolUse": [HookDefinition(handler: { _ in HookOutput(message: "已记录") })],
    "sessionStart": [HookDefinition(handler: { i in HookOutput(message: "开始: \(i.cwd ?? "")") })]
])
```

### 5.3 HookDefinition

`command`(Shell 命令，stdin 传 JSON)、`handler`(Swift 闭包)、`matcher`(正则匹配 toolName)、`timeout`(超时毫秒，默认 30000)。

### 5.4 HookInput 关键字段

`event`(触发事件)、`toolName`(工具名)、`toolInput`/`toolOutput`(输入输出)、`sessionId`、`cwd`、`error`、`agentId`、`permissionMode` 等。

### 5.5 HookOutput 关键字段

`message`(日志)、`block`(是否阻止)、`decision`(`.approve`/`.block`)、`permissionUpdate`(动态修改权限)、`notification`(用户通知)、`systemMessage`(注入系统消息)、`updatedInput`(替换工具输入)。

### 5.6 实战示例

**记录工具调用：**
```swift
await registry.register(.postToolUse, definition: HookDefinition(
    handler: { input in print("[LOG] \(input.toolName ?? "?") 完成"); return nil }
))
```

**阻止危险工具：**
```swift
await registry.register(.preToolUse, definition: HookDefinition(
    matcher: "^(Bash|Write|Edit)$",
    handler: { _ in HookOutput(decision: .block, reason: "安全策略") }
))
```

**Shell 命令 Hook：**
```swift
await registry.register(.preToolUse, definition: HookDefinition(
    command: "/usr/bin/python3 /hooks/audit.py", matcher: ".*", timeout: 5000
))
```

**注入到 Agent：**
```swift
let agent = createAgent(options: AgentOptions(hookRegistry: registry, apiKey: "sk-..."))
```

---

## 六、错误处理模式

### 6.1 QueryStatus

```swift
public enum QueryStatus: String, Sendable {
    case success               // 正常完成
    case errorMaxTurns         // 超过最大轮次
    case errorDuringExecution  // API 错误或执行异常
    case errorMaxBudgetUsd     // 超过预算
    case cancelled             // 用户取消
}
```

### 6.2 SDKError 错误类型

| 错误 | 说明 |
|------|------|
| `.apiError(statusCode, message)` | HTTP API 错误 |
| `.toolExecutionError(toolName, message)` | 工具执行错误 |
| `.budgetExceeded(cost, turnsUsed)` | 预算超限 |
| `.maxTurnsExceeded(turnsUsed)` | 轮次超限 |
| `.sessionError(message)` | 会话持久化错误 |
| `.mcpConnectionError(serverName, message)` | MCP 连接错误 |
| `.permissionDenied(tool, reason)` | 权限拒绝 |
| `.abortError` | 操作中止 |
| `.invalidConfiguration(String)` | 配置无效 |

### 6.3 错误处理策略

```swift
let result = await agent.prompt("分析架构")
switch result.status {
case .success: print(result.text)
case .errorMaxTurns: print("未完成，\(result.numTurns) 轮")
case .errorMaxBudgetUsd: print("超限 $\(result.totalCostUsd)")
case .errorDuringExecution: print("错误: \(result.errors ?? [])")
case .cancelled: print("已取消")
}
```

**捕获 SDKError：**
```swift
do {
    let r = await agent.prompt("执行重构")
} catch let e as SDKError {
    switch e {
    case .apiError(let c, let m): print("API(\(c)): \(m)")
    case .toolExecutionError(let t, let m): print("工具 \(t): \(m)")
    default: print(e.localizedDescription)
    }
}
```

### 6.4 重试配置（RetryConfig）

默认：3 次重试，2 秒基础延迟，30 秒上限，重试状态码 `[429, 500, 502, 503, 529]`。

```swift
let agent = createAgent(options: AgentOptions(
    retryConfig: RetryConfig(maxRetries: 5, baseDelayMs: 1000, maxDelayMs: 60000)
))
```

### 6.5 配置验证

```swift
let options = AgentOptions(baseURL: "not-a-url")
do { try options.validate() } catch let e as SDKError { print(e.message) }
```

---

## 快速参考

```swift
import OpenAgentSDK
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...", model: "claude-sonnet-4-6",
    systemPrompt: "你是 Swift 专家，用中文。", maxTurns: 10,
    maxBudgetUsd: 0.5, effort: .high, permissionMode: .default,
    cwd: "/Users/me/project", logLevel: .info,
    sandbox: SandboxSettings(deniedCommands: ["rm"]),
    retryConfig: RetryConfig.default
))
let r = await agent.prompt("重构函数"); print(r.text)
for await msg in agent.stream("解释架构") { print(msg) }
try await agent.close()
```
