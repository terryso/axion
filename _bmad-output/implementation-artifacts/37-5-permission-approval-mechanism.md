---
story_id: 37.5
epic: 37
title: 权限审批机制
status: done
created: 2026-06-07
baseline_commit: 9f71692
---

# Story 37.5: 权限审批机制

As a CLI 用户,
I want 在执行危险操作（文件覆盖、删除命令等）前收到确认提示,
So that 我可以防止意外破坏.

## Acceptance Criteria

1. **AC1 — 默认模式权限提示**：默认模式（不加 flag）下，agent 要执行非只读操作时，终端显示确认提示 `⚠️ <工具名>: <操作描述> 允许？[y/n]`，用户输入 `y` 后执行，`n` 后跳过（返回错误给 agent）

2. **AC2 — acceptEdits 模式**：`--accept-edits` 模式下，Write/Edit 工具自动通过（无需确认），危险 Bash 命令仍需确认

3. **AC3 — bypassPermissions 模式**：`--dangerously-skip-permissions` 模式下，所有操作自动通过（当前 MVP 行为不变）

4. **AC4 — 只读操作免确认**：Read、Grep、Glob 等只读工具在所有模式下自动通过，无需确认

5. **AC5 — 无回归**：`axion run "task"` 行为完全不受影响（仍使用 `permissionMode: .bypassPermissions`）；slash 命令、Ctrl+C 中断、Banner、输出格式化等现有功能正常

6. **AC6 — /config 显示权限模式**：`/config` 命令显示当前生效的权限模式名称（default / acceptEdits / bypassPermissions）

## Tasks / Subtasks

- [x] Task 1: 添加 CLI flag 和 PermissionMode 传递 (AC: #1-#3)
  - [x] 1.1 在 `ChatCommand` 添加 `@Flag(name: .long, help: "自动允许文件编辑") var acceptEdits: Bool = false`
  - [x] 1.2 在 `ChatCommand` 添加 `@Flag(name: .long, help: "跳过所有权限确认") var dangerouslySkipPermissions: Bool = false`
  - [x] 1.3 在 `AgentBuilder.BuildConfig` 的 `forChat()` 方法中添加 `permissionMode: PermissionMode` 参数
  - [x] 1.4 在 `ChatCommand.run()` 中根据 flag 计算正确的 `PermissionMode`：默认 `.default`、`--accept-edits` → `.acceptEdits`、`--dangerously-skip-permissions` → `.bypassPermissions`
  - [x] 1.5 将 permissionMode 传入 `AgentBuilder.BuildConfig.forChat()`

- [x] Task 2: 创建 PermissionHandler 组件 (AC: #1, #4)
  - [x] 2.1 新建 `Sources/AxionCLI/Chat/PermissionHandler.swift`
  - [x] 2.2 实现 `static func createCanUseTool(isTTY: Bool, readUserInput: @escaping () -> String?) -> CanUseToolFn` — 返回 SDK `CanUseToolFn` 闭包
  - [x] 2.3 闭包逻辑：检查 `tool.isReadOnly` → 如果只读直接返回 `.allow()`
  - [x] 2.4 闭包逻辑：非只读工具 → 显示提示 `⚠️ <工具名>: <操作描述>`，等待用户输入 `y/n`
  - [x] 2.5 用户输入 `y` → 返回 `.allow()`；`n` → 返回 `.deny("用户拒绝执行 <工具名>")`
  - [x] 2.6 非 TTY 环境（管道/重定向）→ 默认 `.deny()`（安全默认值）
  - [x] 2.7 从 tool input 中提取操作描述：Bash → 提取 command 参数；Write/Edit → 提取 file_path 参数；其他 → 工具名

- [x] Task 3: 集成 canUseTool 到 ChatCommand (AC: #1-#4)
  - [x] 3.1 在 `AgentBuilder.build()` 中，当 `buildConfig.mode == .codingAgent` 时，将 `permissionMode` 从 `.bypassPermissions` 改为使用 `buildConfig` 传入的值
  - [x] 3.2 在 `AgentBuilder.build()` 中，当 `buildConfig.mode == .codingAgent` 时，将 `canUseTool` 回调设置到 `AgentOptions`
  - [x] 3.3 `canUseTool` 回调需要在 ChatCommand 层面创建（因为它需要 `readLine()` 访问），通过 `BuildConfig` 传递或在 build 后通过 `agent.setCanUseTool()` 注入
  - [x] 3.4 确认 `forCLI()` 路径（RunCommand）不受影响 — 仍使用 `.bypassPermissions`

- [x] Task 4: 更新 SlashCommandHandler (AC: #6)
  - [x] 4.1 修改 `SlashCommandHandler.handleConfig()` 中的 `permissionMode` 参数为动态值（从 BuildConfig 获取）
  - [x] 4.2 在 `ChatCommand` 调用 `handleConfig` 时传入实际 permissionMode 字符串

- [x] Task 5: 单元测试 (AC: #1-#4)
  - [x] 5.1 测试 `PermissionHandler.createCanUseTool` — 只读工具自动通过
  - [x] 5.2 测试 `PermissionHandler.createCanUseTool` — 非 TTY 环境默认拒绝
  - [x] 5.3 测试 `PermissionHandler.createCanUseTool` — 用户输入 `y` 允许执行
  - [x] 5.4 测试 `PermissionHandler.createCanUseTool` — 用户输入 `n` 拒绝执行
  - [x] 5.5 测试操作描述提取 — Bash command、Write file_path、其他工具名
  - [x] 5.6 测试 PermissionMode 计算逻辑 — flag 组合正确映射到 SDK PermissionMode

## Dev Notes

### SDK 权限流程（关键！）

**SDK `ToolExecutor` 的权限检查是两步流程（按优先级）：**

1. **Step 1 — `canUseTool` 回调**（优先级最高）：
   - 如果 `ToolContext.canUseTool` 非空，调用 `canUseTool(tool, input, context)`
   - 返回 `.allow()` → 直接执行工具
   - 返回 `.deny(message)` → 返回错误 ToolResult，不执行工具
   - 返回 `nil` → **回退到 Step 2**

2. **Step 2 — `permissionMode` 检查**（回退）：
   - `ToolExecutor.shouldBlockTool(permissionMode:tool:)` 根据 PermissionMode 决策
   - `.default` → 非只读工具返回 `.block("Permission required for ...")`（直接失败！不等待用户！）
   - `.acceptEdits` → Write/Edit 允许，其他非只读返回 `.block`
   - `.bypassPermissions` → 全部允许

**⚠️ 关键发现：SDK 的 `.default` 模式只是直接阻止非只读工具（返回错误），不会暂停等待用户确认！** 所以我们必须使用 `canUseTool` 回调来拦截工具调用，在回调中提示用户并返回结果。

**正确实现策略：**
- 设置 `permissionMode: .bypassPermissions`（让 SDK 的 Step 2 永远通过）
- **只用 `canUseTool` 回调控制权限**（在 Step 1 拦截所有非只读工具）
- 这给了我们完全的控制权，不依赖 SDK 的 `.default` 模式行为

### 当前代码位置

**AgentBuilder.build() 第 343 行：**
```swift
permissionMode: .bypassPermissions,  // 当前写死为 bypass
```

**AgentBuilder.BuildConfig.forChat()（第 99-126 行）：**
- 当前没有 `permissionMode` 参数
- `maxTokens: 131_072`（128K）已正确配置
- `mode: .codingAgent` 已正确设置

**ChatCommand（180 行）：**
- 第 37-45 行：创建 `buildConfig`（`forChat()` 调用）
- 第 134 行：创建 `ChatOutputFormatter()`
- 第 136 行：`buildResult.agent.stream(trimmed)` 开始执行
- 无 CLI flag 控制权限模式

**SlashCommandHandler 第 52 行：**
```swift
permissionMode: "bypassPermissions"  // 硬编码，需改为动态值
```

### 实现架构

```
ChatCommand
  │
  ├── 解析 CLI flags → 计算 PermissionMode
  │       --accept-edits → .acceptEdits
  │       --dangerously-skip-permissions → .bypassPermissions
  │       (default) → .default
  │
  ├── 创建 canUseTool 闭包 (PermissionHandler.createCanUseTool)
  │       ├── 检查 tool.isReadOnly → .allow()
  │       ├── 检查 isTTY → 非 TTY 拒绝
  │       ├── 显示 ⚠️ 提示 (stderr)
  │       ├── readLine() 等待用户输入
  │       └── y → .allow(), n → .deny()
  │
  ├── 传入 BuildConfig.forChat(permissionMode: ..., canUseTool: ...)
  │
  └── AgentBuilder.build()
        ├── permissionMode: .bypassPermissions  // SDK 层面永远允许
        ├── canUseTool: 传入的闭包              // 在这里拦截权限
        └── 其余不变
```

### 操作描述提取策略

```swift
static func extractDescription(tool: ToolProtocol, input: Any) -> String {
    guard let dict = input as? [String: Any] else {
        return tool.name
    }
    switch tool.name {
    case "Bash":
        return dict["command"] as? String ?? tool.name
    case "Write":
        return "写入 \(dict["file_path"] as? String ?? "文件")"
    case "Edit":
        return "编辑 \(dict["file_path"] as? String ?? "文件")"
    default:
        return tool.name
    }
}
```

### 权限提示格式

```
⚠️  Bash: rm -rf /tmp/test
   允许？[y/n] y
```

或对于 Write：
```
⚠️  Write: 写入 Sources/AxionCLI/Chat/PermissionHandler.swift
   允许？[y/n] n
```

### 关键设计决策

1. **使用 `canUseTool` 而非 SDK 的 `permissionMode: .default`**：SDK 的 `.default` 模式只是直接返回错误阻止工具，不提供用户交互机会。我们必须在 `canUseTool` 回调中实现用户交互逻辑。

2. **`permissionMode` 保持 `.bypassPermissions`**：因为 `canUseTool` 回调优先于 `permissionMode`，当 `canUseTool` 返回 `nil` 时（不应该发生，但防御性编程），`permissionMode: .bypassPermissions` 确保不会意外阻止。

3. **非 TTY 安全默认值**：管道输入模式下没有终端交互能力，默认拒绝非只读操作（安全优先）。

4. **`--accept-edits` 的行为**：在 `canUseTool` 回调中检查 `tool.name == "Write" || tool.name == "Edit"` → 自动 `.allow()`。这与 SDK `ToolExecutor.shouldBlockTool` 的 `.acceptEdits` 逻辑一致。

5. **不在 SDK 层面传递 mode**：由于我们只用 `canUseTool` 控制，实际上 `permissionMode` 始终是 `.bypassPermissions`。权限模式变量只在 `PermissionHandler` 内部使用，决定哪些工具需要确认。

### BuildConfig 修改方案

```swift
// AgentBuilder.BuildConfig 新增字段
struct BuildConfig: Sendable {
    // ... 现有字段 ...
    let permissionMode: PermissionMode  // 新增
    let canUseTool: CanUseToolFn?        // 新增

    static func forChat(
        config: AxionConfig,
        noMemory: Bool = false,
        noSkills: Bool = false,
        maxSteps: Int? = nil,
        verbose: Bool = false,
        sessionId: String? = nil,
        sessionStore: SessionStore? = nil,
        permissionMode: PermissionMode = .default,  // 新增
        canUseTool: CanUseToolFn? = nil              // 新增
    ) -> BuildConfig {
        BuildConfig(
            // ... 现有参数 ...
            permissionMode: permissionMode,
            canUseTool: canUseTool
        )
    }
}
```

### AgentBuilder.build() 修改点

在 `AgentBuilder.build()` 中，创建 `AgentOptions` 时：

```swift
// 现有第 343 行：
permissionMode: .bypassPermissions,

// 修改为：
permissionMode: buildConfig.mode == .codingAgent
    ? .bypassPermissions  // Chat 模式：canUseTool 控制权限，SDK 层面全允许
    : .bypassPermissions,  // Run 模式：保持现有行为
```

然后在创建 agent 后注入 canUseTool：

```swift
// 创建 agent 后、返回前
if let canUseTool = buildConfig.canUseTool {
    agent.setCanUseTool(canUseTool)  // SDK Agent 有此方法
}
```

或直接在 `AgentOptions` 中设置：
```swift
var agentOptions = AgentOptions(
    // ...
    permissionMode: .bypassPermissions,
    // ...
)
if let canUseTool = buildConfig.canUseTool {
    agentOptions.canUseTool = canUseTool
}
```

### 关键反模式（必须避免）

1. **不要修改 `RunCommand` 路径** — `axion run` 仍使用 `.bypassPermissions`，`forCLI()` 的 `BuildConfig` 不变
2. **不要在 SDK 的 `ToolExecutor` 层面使用 `.default` 模式** — 它直接返回错误，不提供用户交互
3. **不要在非 TTY 环境下自动允许** — 管道/重定向时拒绝非只读操作（安全默认值）
4. **不要使用 `print()`** — CLI 使用 `fputs()` + `fflush()` 控制输出目标（project-context.md 反模式 #3）
5. **不要忘记 import OpenAgentSDK** — `CanUseToolFn`、`PermissionMode`、`ToolProtocol`、`ToolContext` 均来自 SDK
6. **不要在 PermissionHandler 中使用 `readLine()` 直接** — 通过依赖注入传入 readUserInput 闭包，便于测试
7. **不要阻塞 REPL 主线程** — `canUseTool` 是 async 闭包，`readLine()` 是同步调用，在 async 上下文中可直接调用
8. **不要修改 `SDKTerminalOutputHandler`** — 它被 RunCommand 使用，Chat 有独立的输出格式化

### 测试策略

- **单元测试（必须 Mock）：**
  - `PermissionHandler` — 通过注入 `isTTY` 和 `readUserInput` 闭包来测试
  - 权限判断逻辑 — 只读工具自动通过、非 TTY 拒绝、y/n 响应
  - 操作描述提取 — Bash command、Write file_path、默认工具名
  - PermissionMode flag 计算逻辑
  - **Mock 策略：** 注入闭包替代 `readLine()` 和 `isatty()`

- **不写集成测试** — 不启动真实 agent 或终端

### Project Structure Notes

- 新文件 `PermissionHandler.swift` 放在 `Sources/AxionCLI/Chat/` 目录（与 BannerRenderer、SlashCommand、SignalHandler、ChatOutputFormatter 同级）
- 测试文件放在 `Tests/AxionCLITests/Chat/PermissionHandlerTests.swift`（镜像源结构）
- 使用 Swift Testing 框架（`import Testing`、`@Suite`、`@Test`、`#expect`）

### References

- [Source: docs/epics/epic-37-interactive-chat-mode.md#Story 37.5] — 完整 story 定义和 AC
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift] — 主 REPL 入口（需添加 flag 和 canUseTool 注入）
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift:343] — 当前 permissionMode 硬编码位置
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift:99-126] — forChat() 方法（需添加 permissionMode 和 canUseTool 参数）
- [Source: Sources/AxionCLI/Chat/SlashCommandHandler.swift:52] — /config 中硬编码 "bypassPermissions"
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Types/PermissionTypes.swift] — SDK PermissionMode 枚举、CanUseToolFn 类型、PermissionPolicy 协议
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Core/ToolExecutor.swift:60-89] — SDK shouldBlockTool() 权限检查逻辑
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Core/ToolExecutor.swift:352-485] — SDK 两步权限检查流程（canUseTool 优先 → permissionMode 回退）
- [Source: _bmad-output/implementation-artifacts/37-4-terminal-output-optimization.md] — Story 37.4 完成记录（前序 story）

### Previous Story Intelligence (37.4)

- **ChatOutputFormatter 已完成** — 实现 `SDKMessageOutputHandler` 协议，处理流式输出
- **ChatCommand 结构已稳定** — 180 行，REPL 循环 + signal handler + slash commands
- **SDKTerminalOutputHandler 在 ChatCommand 不再使用** — 已替换为 ChatOutputFormatter
- **TokenUsage 累计** — 每轮 stream 结束后从 `SDKMessage.result` 提取
- **25 个单元测试** — TerminalOutputTests.swift 覆盖 Markdown/Spinner/ChatOutput

### Previous Story Intelligence (37.3)

- **BannerRenderer 已完成** — 纯函数 struct，static methods
- **ChatCommand 第 37-45 行** — `BuildConfig.forChat()` 调用
- **SessionStore 和 sessionId** — 会话持久化已就绪

### Previous Story Intelligence (37.2)

- **SignalHandler 已完成** — agent.interrupt() 模式
- **lastInterruptTime** — 双击退出检测变量

### Previous Story Intelligence (37.1)

- **Slash 命令系统已完成** — 8 个命令 + 未知命令拦截
- **Chat/ 目录已创建** — SlashCommand.swift、SlashCommandHandler.swift、SignalHandler.swift、BannerRenderer.swift
- **测试文件位置** — `Tests/AxionCLITests/Chat/` 目录

### Previous Story Intelligence (37.0)

- **Coding Agent 系统提示已完成** — `coding-agent-system.md` 模板
- **CLAUDE.md 加载** — `buildCodingSystemPrompt()` 已实现
- **maxTokens: 131_072** — 128K 输出
- **AgentMode.codingAgent** — mode 枚举已定义

### Git Intelligence

最近 5 个提交：
- `9f71692` feat(story-37.4): 终端输出优化
- `9c7e56f` feat(story-37.3): 启动横幅 + 会话信息
- `3cb12d6` feat(story-37.2): Ctrl+C 优雅中断
- `aff3118` feat(story-37.1): Slash 命令体系
- `3b9f251` feat(story-37.0): Coding Agent 系统提示 + 项目上下文

本 Story 37.5 修改 ChatCommand（添加 flag）、AgentBuilder.build()（第 343 行 permissionMode 和新增 canUseTool 注入）、SlashCommandHandler（第 52 行动态 permissionMode），并新增 PermissionHandler.swift 独立文件。与前序 story 互不干扰。

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

无调试问题，所有测试一次通过。

### Completion Notes List

- ✅ 新建 `PermissionHandler.swift` — 提供 `createCanUseTool()` 工厂方法，支持三种模式（default/acceptEdits/bypassPermissions）
- ✅ `ChatCommand` 添加 `--accept-edits` 和 `--dangerously-skip-permissions` 两个 CLI flag
- ✅ `AgentBuilder.BuildConfig` 新增 `permissionMode` 和 `canUseTool` 字段，`forChat()` 方法接受这两个参数
- ✅ `AgentBuilder.build()` 通过 `agentOptions.canUseTool` 注入权限回调（SDK 层面 `permissionMode` 保持 `.bypassPermissions`）
- ✅ `SlashCommandHandler.handleConfig()` 使用 `PermissionHandler.modeDisplayName()` 动态显示权限模式
- ✅ 25 个单元测试覆盖：只读自动通过（3 种模式）、bypass 全通过、acceptEdits Write/Edit 自动通过、acceptEdits Bash 需确认、default y/n 提示、非 TTY 拒绝、操作描述提取（6 场景）、模式计算（4 场景）
- ✅ 全量回归测试 2016 tests passed，0 failures

### File List

- `Sources/AxionCLI/Chat/PermissionHandler.swift` (新增) — 权限审批处理器
- `Sources/AxionCLI/Commands/ChatCommand.swift` (修改) — 添加 --accept-edits / --dangerously-skip-permissions flag + canUseTool 创建
- `Sources/AxionCLI/Services/AgentBuilder.swift` (修改) — BuildConfig 新增 permissionMode/canUseTool 字段 + forChat() 参数 + build() 注入 canUseTool
- `Sources/AxionCLI/Chat/SlashCommandHandler.swift` (修改) — /config 动态显示权限模式
- `Sources/AxionCLI/Services/AxionRuntime.swift` (修改) — 两处 BuildConfig 直接构造添加新字段
- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` (修改) — 两处 BuildConfig 直接构造添加新字段
- `Tests/AxionCLITests/Chat/PermissionHandlerTests.swift` (新增) — 28 个单元测试

### Change Log

- 2026-06-07: Story 37.5 完成 — 实现权限审批机制，支持 default/acceptEdits/bypassPermissions 三种模式
- 2026-06-07: Code Review — 5 issues found (0 critical, 3 medium, 2 low), all auto-fixed

## Senior Developer Review (AI)

**Reviewer:** terryso
**Date:** 2026-06-07
**Outcome:** ✅ Approved (all issues auto-fixed)

### Issues Found & Fixed

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| M1 | Medium | 误导性测试名 `nonTTYReadLineNil` 实际用 `isTTY: true` | 重命名为 `ttyReadLineNilDenies`，原 `nonTTYDeniesNonReadOnly` 重命名为 `defaultNonTTYDeniesNonReadOnly` |
| M2 | Medium | 缺少 acceptEdits + non-TTY + Write 测试 | 新增 `acceptEditsNonTTYWriteAutoAllows` 测试 |
| M3 | Medium | 缺少 acceptEdits + non-TTY + Bash 测试 | 新增 `acceptEditsNonTTYBashDenied` 测试 |
| L1 | Low | `modeDisplayNames` 只覆盖 3/6 case | 补全 `.plan` / `.dontAsk` / `.auto` 验证 |
| L2 | Low | `defaultModeEmptyInput` 不验证 deny 消息 | 添加 `#expect(result?.message?.contains("用户拒绝") == true)` |

### Verification

- 28 tests passed (原 25 + 新增 3)
- Git vs Story File List: 0 discrepancies
- AC1-AC6: 全部 IMPLEMENTED
- Tasks 1-5: 全部 VERIFIED
- No regression risk: forCLI/forAPI/forSkillExecution/forMCP 全部保持 `.bypassPermissions` + `canUseTool: nil`
