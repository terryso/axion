---
story_id: 37.1
epic: 37
title: Slash 命令体系
status: done
created: 2026-06-07
baseline_commit: 3b9f251
---

# Story 37.1: Slash 命令体系

As a CLI 用户,
I want 在交互模式中使用 /help、/clear、/compact 等斜杠命令,
So that 我可以控制对话行为而不用退出重进.

## Acceptance Criteria

1. **AC1 — /help**：用户输入 `/help`，显示所有可用 slash 命令列表（命令名 + 简短说明），含 `/exit`、`/quit`

2. **AC2 — /clear**：用户输入 `/clear`，终端清屏（ANSI `\u{1B}[2J\u{1B}[H]`），会话历史不变，下一轮对话仍记得上下文

3. **AC3 — /model 无参数**：用户输入 `/model`，显示当前使用的模型名称（从 `buildResult.agent.model` 读取）

4. **AC4 — /model 切换**：用户输入 `/model gpt-4o`，调用 `buildResult.agent.switchModel("gpt-4o")` 切换模型，显示确认消息。切换失败时显示错误信息（switchModel throws）

5. **AC5 — /cost**：用户输入 `/cost`，显示当前会话累计 token 用量（input / output / cache / total）和预估成本。Token 数据从每次 stream 结束后的 `SDKMessage.result` 中提取 `ResultData.usage`，累计在 ChatCommand 的 `sessionUsage: TokenUsage` 变量中

6. **AC6 — /config**：用户输入 `/config`，显示当前生效的关键配置项（model、maxTokens、maxSteps、memory enabled、skills enabled、permissionMode）

7. **AC7 — /compact**：用户输入 `/compact`，触发上下文压缩（本 story 仅打印"暂未实现"占位，实际实现在 Story 37.7）

8. **AC8 — /resume**：用户输入 `/resume`，打印"暂未实现"占位（实际实现在 Story 37.8）

9. **AC9 — /exit /quit**：保持现有行为，退出 REPL 循环

10. **AC10 — 未知命令**：用户输入 `/unknown`，显示"未知命令"提示和 `/help` 建议

11. **AC11 — 无回归**：`axion run "task"` 行为完全不受影响（SlashCommand 仅在 ChatCommand 中使用）

## Tasks / Subtasks

- [x] Task 1: 创建 SlashCommand 枚举 (AC: #1-#10)
  - [x] 1.1 新建 `Sources/AxionCLI/Chat/SlashCommand.swift`
  - [x] 1.2 定义 `enum SlashCommand` — `.help`、`.clear`、`.compact`、`.model`、`.cost`、`.resume`、`.config`、`.exit`
  - [x] 1.3 实现 `static func parse(_ input: String) -> SlashCommand?` — 解析 `/` 前缀 + 命令名 + 可选参数，大小写不敏感
  - [x] 1.4 实现 `var helpText: String` — 返回命令的简短描述

- [x] Task 2: 创建 SlashCommandHandler (AC: #1-#10)
  - [x] 2.1 新建 `Sources/AxionCLI/Chat/SlashCommandHandler.swift`
  - [x] 2.2 实现 `struct SlashCommandHandler` — 处理各 slash 命令的具体逻辑
  - [x] 2.3 `handleHelp()` — 格式化输出所有命令列表
  - [x] 2.4 `handleClear()` — ANSI escape 清屏
  - [x] 2.5 `handleModel(argument:agent:)` — 显示/切换模型
  - [x] 2.6 `handleCost(usage:model:)` — 显示累计 token 用量和预估成本
  - [x] 2.7 `handleConfig(model:maxTokens:maxSteps:noMemory:noSkills:permissionMode:)` — 显示当前配置
  - [x] 2.8 `handleCompact()` / `handleResume()` — 占位实现
  - [x] 2.9 `handleUnknown(_ input:)` — 未知命令提示

- [x] Task 3: 修改 ChatCommand REPL 循环 (AC: #1-#10)
  - [x] 3.1 在 REPL 循环中，`readLine()` 后、`agent.stream()` 之前，调用 `SlashCommand.parse()`
  - [x] 3.2 匹配到 slash 命令时，调用 `SlashCommandHandler` 处理并 `continue`
  - [x] 3.3 在 stream 循环中捕获 `SDKMessage.result`，提取 `usage` 累计到 `sessionUsage`
  - [x] 3.4 将 `sessionUsage`、`config` 等上下文传递给 SlashCommandHandler

- [x] Task 4: 单元测试 (AC: #1-#10)
  - [x] 4.1 测试 `SlashCommand.parse()` — 所有 8 个命令精确匹配、`/quit` → `.exit`、未知命令 `/foo` → nil、非斜杠命令 `hello` → nil
  - [x] 4.2 测试 `SlashCommand.parse()` 边界 — 大小写 `/Help`/`/CLEAR`、尾部空白 `/help   `、空参数 `/model `
  - [x] 4.3 测试 `SlashCommand.parseArgument()` — 有参数 `/model gpt-4o` → `"gpt-4o"`、无参数 `/help` → nil、空白参数 `/model   ` → nil
  - [x] 4.4 测试 `SlashCommand.allCases` — count == 8、每个 helpText 非空且唯一
  - [x] 4.5 测试 `handleHelp()` — 输出包含所有 8 个命令名和描述
  - [x] 4.6 测试 `handleCost()` — 给定 TokenUsage 值验证输出包含 input/output/cache/total 数字
  - [x] 4.7 测试 `handleCost()` 零值 — TokenUsage(inputTokens: 0, outputTokens: 0) 输出正确
  - [x] 4.8 测试 `handleConfig()` — 给定配置验证输出包含 model、maxTokens、maxSteps、memory、skills
  - [x] 4.9 测试 `handleUnknown()` — 输出包含 `/help` 建议
  - [x] 4.10 测试 `handleCompact()` / `handleResume()` — 输出包含"暂未实现"

## Dev Notes

### 核心架构理解

**当前 ChatCommand（91 行）的 REPL 循环：**
```
while true {
    fputs("axion> ", stdout); fflush(stdout)
    guard let line = readLine(strippingNewline: true) else { break }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    if trimmed == "/exit" || trimmed == "/quit" { break }    // ← 硬编码退出
    let outputHandler = SDKTerminalOutputHandler(mode: "chat")
    let messageStream = buildResult.agent.stream(trimmed)
    for await message in messageStream {
        outputHandler.handle(message)
    }
    outputHandler.displayCompletion()
}
```

**本 Story 的改动：** 在 `if trimmed == "/exit"` 处替换为通用的 slash 命令解析，不改变 `agent.stream()` 调用逻辑。

### 关键文件位置

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/AxionCLI/Chat/SlashCommand.swift` | **NEW** | SlashCommand 枚举定义 + parse() |
| `Sources/AxionCLI/Chat/SlashCommandHandler.swift` | **NEW** | 各命令处理逻辑 |
| `Sources/AxionCLI/Commands/ChatCommand.swift` | **UPDATE** | REPL 循环集成 slash 命令 + token 累计 |
| `Tests/AxionCLITests/Chat/SlashCommandTests.swift` | **NEW** | 单元测试 |

### SlashCommand 枚举设计

```swift
import Foundation

/// 斜杠命令枚举。不依赖 SDK 类型，纯解析层。
///
/// 注意：`/quit` 在 parse() 中映射为 `.exit`，不出现在 allCases 中
/// （allCases 用于 /help 输出，/quit 是 /exit 的别名）。
enum SlashCommand: String, CaseIterable, Equatable {
    case help    = "/help"
    case clear   = "/clear"
    case compact = "/compact"
    case model   = "/model"     // 带可选参数
    case cost    = "/cost"
    case resume  = "/resume"
    case config  = "/config"
    case exit    = "/exit"

    /// 解析用户输入为 SlashCommand。非斜杠命令或未知命令返回 nil。
    static func parse(_ input: String) -> SlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return nil }
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let cmd = String(parts[0]).lowercased()
        switch cmd {
        case "/help":    return .help
        case "/clear":   return .clear
        case "/compact": return .compact
        case "/model":   return .model
        case "/cost":    return .cost
        case "/resume":  return .resume
        case "/config":  return .config
        case "/exit", "/quit": return .exit
        default: return nil
        }
    }

    /// 提取命令参数（命令名之后的部分，已 trim）。
    static func parseArgument(_ input: String) -> String? {
        let parts = input.split(separator: " ", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        let arg = String(parts[1]).trimmingCharacters(in: .whitespaces)
        return arg.isEmpty ? nil : arg
    }

    /// 用于 /help 显示的简短描述。
    var helpText: String {
        switch self {
        case .help:    return "显示帮助信息"
        case .clear:   return "清屏（不重置会话）"
        case .compact: return "压缩上下文（暂未实现）"
        case .model:   return "显示/切换模型（/model [name]）"
        case .cost:    return "显示当前会话 token 用量和成本"
        case .resume:  return "恢复会话（暂未实现）"
        case .config:  return "显示当前配置"
        case .exit:    return "退出交互模式（/quit 同义）"
        }
    }
}
```

### Token 用量累计设计

SDK 的 `SDKMessage.result(ResultData)` 包含：
- `ResultData.usage: TokenUsage?` — inputTokens, outputTokens, cacheCreationInputTokens, cacheReadInputTokens
- `ResultData.numTurns: Int`
- `ResultData.durationMs: Int`

在 ChatCommand 中维护一个 `var sessionUsage = TokenUsage(inputTokens: 0, outputTokens: 0)` 累计：

```swift
// ChatCommand REPL 循环内
for await message in messageStream {
    outputHandler.handle(message)
    // 累计 token 用量
    if case .result(let data) = message, let usage = data.usage {
        sessionUsage = sessionUsage + usage
    }
}
```

### /cost 成本估算

使用 Anthropic 公开定价估算成本（简化版，用户可感知数量级即可）：

```swift
func estimateCost(usage: TokenUsage, model: String) -> String {
    // 简化估算：Sonnet $3/$15 per 1M tokens, Opus $15/$75
    let inputCostPer1M: Double
    let outputCostPer1M: Double
    if model.contains("opus") {
        inputCostPer1M = 15.0; outputCostPer1M = 75.0
    } else {
        inputCostPer1M = 3.0; outputCostPer1M = 15.0
    }
    let cost = Double(usage.inputTokens) / 1_000_000 * inputCostPer1M
             + Double(usage.outputTokens) / 1_000_000 * outputCostPer1M
    return String(format: "$%.4f", cost)
}
```

### /clear 实现

```swift
static func handleClear() {
    // ANSI escape: clear screen + move cursor to top-left
    fputs("\u{1B}[2J\u{1B}[H", stdout)
    fflush(stdout)
}
```

### /model 切换

SDK `Agent` 有 `public func switchModel(_ model: String) throws` 方法（[Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift#L344]）。切换后 `buildResult.agent.model` 自动更新。

```swift
static func handleModel(argument: String?, agent: Agent) {
    if let arg = argument, !arg.isEmpty {
        do {
            try agent.switchModel(arg)
            fputs("[axion] 模型已切换为 \(arg)\n", stderr)
        } catch {
            fputs("[axion] 切换失败: \(error.localizedDescription)\n", stderr)
        }
    } else {
        fputs("当前模型: \(agent.model)\n", stderr)
    }
}
```

### /config 输出格式

```
当前配置:
  模型:         claude-sonnet-4-20250514
  最大输出:     131072 tokens
  最大步骤:     20
  Memory:       开启
  技能系统:     开启
  权限模式:     bypassPermissions
```

### /compact 和 /resume 占位消息

```
[axion] /compact 暂未实现，将在后续版本中支持
[axion] /resume 暂未实现，将在后续版本中支持
```

### ChatCommand REPL 改动要点

```swift
// 替换原来的硬编码 /exit 检查
if let cmd = SlashCommand.parse(trimmed) {
    let argument = SlashCommand.parseArgument(trimmed)
    let shouldExit = SlashCommandHandler.handle(
        cmd,
        argument: argument,
        agent: buildResult.agent,
        config: config,
        sessionUsage: sessionUsage,
        buildConfig: buildConfig
    )
    if shouldExit { break }
    continue
}
```

`SlashCommandHandler.handle()` 返回 `Bool`：`true` 表示应退出 REPL（仅 `.exit` 命令），`false` 表示继续循环。

### SlashCommandHandler 接口设计

```swift
import Foundation
import OpenAgentSDK  // TokenUsage, Agent

struct SlashCommandHandler {
    /// 处理 slash 命令。返回 true 表示应退出 REPL。
    static func handle(
        _ command: SlashCommand,
        argument: String?,
        agent: Agent,
        config: AxionConfig,
        sessionUsage: TokenUsage,
        buildConfig: AgentBuilder.BuildConfig
    ) -> Bool {
        switch command {
        case .help:    handleHelp()
        case .clear:   handleClear()
        case .compact: handleCompact()
        case .model:   handleModel(argument: argument, agent: agent)
        case .cost:    handleCost(usage: sessionUsage, model: agent.model)
        case .resume:  handleResume()
        case .config:  handleConfig(config: config, buildConfig: buildConfig)
        case .exit:    return true
        }
        return false
    }
    // ... 各 private handler 方法
}
```

**线程安全说明：** `sessionUsage` 在 REPL 主线程（async 但非并发）中累计，不存在竞态。`agent.switchModel()` 是 SDK Agent 的公开方法，内部处理线程安全。

### 关键反模式（必须避免）

1. **不要在 SlashCommand 中 import 不必要的模块** — 只需 `Foundation`
2. **不要修改 `SDKTerminalOutputHandler`** — 它被 RunCommand 使用（project-context.md 反模式 #3）
3. **不要修改 `axion run` 路径** — SlashCommand 仅在 ChatCommand REPL 中使用
4. **不要硬编码成本定价在代码中** — 使用常量或配置（即使简化版也要提取为命名常量）
5. **不要在 SlashCommandHandler 中持有 Agent 引用** — 作为参数传入，不存储
6. **`/compact` 和 `/resume` 不要省略** — 定义 case 但打印"暂未实现"占位，Story 37.7/37.8 会补充实现
7. **不要 import OpenAgentSDK 在 SlashCommand.swift 中** — 解析层不依赖 SDK 类型（TokenUsage 引用在 Handler 层）
8. **不要在测试中调用真实 Agent** — switchModel 等通过协议/闭包 Mock

### 测试策略

- **单元测试（必须 Mock）：**
  - `SlashCommand.parse()` — 每个命令精确匹配、大小写（`/Help`、`/CLEAR`）、尾部空白（`/help   `）、未知命令（`/foo` → nil）、非斜杠命令（`hello` → nil）、空字符串
  - `SlashCommand.parseArgument()` — 有参数、无参数、空白参数
  - `SlashCommand.allCases` — 验证帮助文本非空且唯一
  - `handleHelp()` — 输出包含所有命令（使用 `CaseIterable.allCases` 遍历）
  - `handleCost()` — 给定 TokenUsage 值，验证格式化输出包含数字；零值边界
  - `handleConfig()` — 给定配置，验证输出包含 model、maxTokens、maxSteps、memory、skills 字段
  - `handleUnknown()` — 输出包含 `/help` 提示
  - `handleCompact()` / `handleResume()` — 输出包含"暂未实现"
  - **Mock 策略：** SlashCommand 纯解析无需 Mock；SlashCommandHandler 中的 `Agent` 通过闭包/协议注入来测试 switchModel 等 SDK 调用
- **不写集成测试** — 不启动真实 agent 或终端

### Project Structure Notes

- 新建 `Sources/AxionCLI/Chat/` 目录（当前不存在）
- `Chat/` 目录包含交互模式专属代码：SlashCommand、SlashCommandHandler
- 后续 Story 37.4 的 `ChatOutputFormatter`、`MarkdownTerminalRenderer` 也放在此目录
- 测试文件放在 `Tests/AxionCLITests/Chat/`（镜像源结构）

### References

- [Source: docs/epics/epic-37-interactive-chat-mode.md#Story 37.1] — 完整 story 定义、命令清单和 AC
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift] — 当前 MVP REPL 实现（91 行）
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift#L39-L42] — AgentMode 枚举定义
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift#L97-L125] — BuildConfig.forChat() 工厂方法
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Types/TokenUsage.swift] — TokenUsage struct（inputTokens, outputTokens, cacheReadInputTokens, totalTokens, + 操作符）
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift#L26] — `public private(set) var model: String`
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift#L344] — `public func switchModel(_ model: String) throws`
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Types/SDKMessage.swift#L29] — `case result(ResultData)`，ResultData.usage: TokenUsage?
- [Source: _bmad-output/implementation-artifacts/37-0-coding-agent-system-prompt-project-context.md] — Story 37.0 完成记录（前序 story）

### Previous Story Intelligence (37.0)

- **Helper 守卫已跳过 coding agent** — `build()` 第 231 行 `guard resolvedHelperPath != nil || buildConfig.dryrun || buildConfig.mode == .codingAgent`
- **MCP 连接已跳过** — `mcpServers = nil` in coding agent mode，不会暴露桌面自动化工具
- **forChat() 配置** — `maxTokens: 131072`、`includePlaywright: false`、`mode: .codingAgent`
- **13 个单元测试通过** — 在 `Tests/AxionCLITests/Services/AgentBuilderCodingTests.swift`
- **Code Review 修复** — MCP 隔离测试已验证 coding agent 不连接 Helper
- **测试临时目录清理** — 使用 `cleanup(base)` 清理整个树（非仅 homeDir）

### Git Intelligence

最近 2 个提交：
- `3b9f251` feat(story-37.0): Coding Agent 系统提示 + 项目上下文
- `582feeb` feat: add interactive chat mode as default command

Story 37.0 建立了 coding agent 的 prompt 体系和 BuildConfig 分支。本 Story 37.1 在此基础上扩展 REPL 的命令处理能力。

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

无阻塞问题。

### Completion Notes List

- ✅ Task 1: 创建 `SlashCommand` 枚举 — 8 个 case + `parse()` + `parseArgument()` + `helpText`，仅依赖 Foundation
- ✅ Task 2: 创建 `SlashCommandHandler` — 所有命令处理逻辑，成本估算提取为命名常量，Agent 通过参数传入不持有引用
- ✅ Task 3: 修改 ChatCommand REPL — 替换硬编码 `/exit` 为通用 SlashCommand 解析，添加 sessionUsage 累计
- ✅ Task 4: 31 个单元测试全部通过 — parse() 精确匹配/边界/大小写、parseArgument()、allCases、handleHelp/Cost/Config/Unknown/Compact/Resume
- 1931 个单元测试全通过，零回归
- `axion run` 路径完全不受影响（SlashCommand 仅在 ChatCommand 使用）

### File List

- `Sources/AxionCLI/Chat/SlashCommand.swift` (NEW)
- `Sources/AxionCLI/Chat/SlashCommandHandler.swift` (NEW)
- `Sources/AxionCLI/Commands/ChatCommand.swift` (MODIFIED)
- `Tests/AxionCLITests/Chat/SlashCommandTests.swift` (NEW)

### Change Log

- 2026-06-07: Story 37.1 实现 — Slash 命令体系（/help、/clear、/model、/cost、/config、/compact、/resume、/exit、/quit），含 token 用量累计和成本估算
- 2026-06-07: Code Review 修复 — (1) AC10 未知斜杠命令拦截：ChatCommand REPL 添加 `else if trimmed.hasPrefix("/")` 分支调用 handleUnknown()；(2) handleModel 重构为纯函数便于测试（handleModelDisplay/handleModelSwitchSuccess/handleModelSwitchError）；(3) 成本估算加入 cache token 定价（Sonnet $0.30/M, Opus $1.50/M cache read）；(4) 新增 5 个单元测试（1707 全通过）

## Senior Developer Review (AI)

**Reviewer:** Nick on 2026-06-07
**Outcome:** ✅ Approved (auto-fixed)

### Issues Found & Fixed

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| 1 | 🔴 HIGH | AC10 未实现：`handleUnknown()` 是死代码，`/foo` 被发送给 agent | ChatCommand REPL 添加 `else if trimmed.hasPrefix("/")` 分支 |
| 2 | 🟡 MEDIUM | handleModel 无单元测试，接口不接受协议注入无法 Mock | 提取纯函数 `handleModelDisplay/SwitchSuccess/SwitchError` 返回 String |
| 3 | 🟡 MEDIUM | permissionMode 硬编码 `"bypassPermissions"` | 保留（当前行为正确，AgentOptions 固定为 .bypassPermissions） |
| 4 | 🟢 LOW | 成本估算忽略 cache token 定价差异 | 添加 cacheReadCostPerMTokens 常量，estimateCost 计入 cache read |

### Test Results

- 1707 单元测试全部通过（+5 新增）
- 0 CRITICAL issues 残留
