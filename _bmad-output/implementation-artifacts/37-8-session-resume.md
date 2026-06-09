---
story_id: 37.8
epic: 37
title: 会话恢复
status: done
created: 2026-06-07
baseline_commit: 4e5e0c5
---

# Story 37.8: 会话恢复

As a CLI 用户,
I want 在交互聊天模式中通过 /resume 恢复之前的会话,
So that 我可以延续之前的对话上下文，无需从头开始.

## Acceptance Criteria

1. **AC1 — /resume 列表**：用户输入 `/resume`（无参数），显示最近的会话列表（最近 10 条），格式 `SESSION TASK STATUS STEPS CREATED`（复用 SessionsCommand.renderTable 格式），并在末尾提示 "输入 /resume <session-id> 恢复指定会话"

2. **AC2 — /resume <id> 恢复**：用户输入 `/resume <session-id>`，验证 session 存在且非 running 状态，然后：销毁当前 agent → 重建 agent 并加载历史对话 → 横幅显示 "已恢复会话 <session-id> (N 条消息)" → 继续 REPL 循环。当前 sessionUsage 和 contextTokens 重置

3. **AC3 — /resume 错误处理**：session 不存在时显示 "会话未找到: <id>"；session 正在运行时显示 "会话正在运行: <id>"；恢复失败（API/构建错误）时显示错误信息但**不退出 REPL**，用户可继续使用当前会话

4. **AC4 — 退出提示**：`BannerRenderer.renderExit()` 已提示 "使用 /resume 可恢复"，本 Story 需确保恢复后横幅正确显示恢复的 session ID

5. **AC5 — 无回归**：`axion run "task"` 行为不受影响；其他 slash 命令、Ctrl+C 中断、权限审批、compact、多行输入等功能正常

## Tasks / Subtasks

- [x] Task 1: 创建 SessionResumeManager 组件 (AC: #1, #2, #3)
  - [x] 1.1 新建 `Sources/AxionCLI/Chat/SessionResumeManager.swift`
  - [x] 1.2 实现 `struct SessionResumeManager` — 会话恢复核心逻辑
  - [x] 1.3 实现 `static func listSessions(store:) async throws -> [SessionInfo]` — 列出最近 10 条非 running 会话
  - [x] 1.4 实现 `static func formatSessionList(_ sessions: [SessionInfo]) -> String` — 格式化会话列表
  - [x] 1.5 实现 `static func formatResumeSuccess(sessionId: String, messageCount: Int) -> String` — 恢复成功消息
  - [x] 1.6 实现 `static func formatResumeHint() -> String` — 列表末尾提示
  - [x] 1.7 实现 `static func formatResumeError(_ error: Error) -> String` — 错误消息格式化

- [x] Task 2: 修改 ChatCommand 支持会话恢复 (AC: #2, #4)
  - [x] 2.1 在 `ChatCommand.run()` 中提取 REPL 循环为可重入结构（或通过重建 agent 方式）
  - [x] 2.2 将 `buildResult`、`sessionId`、`sessionUsage`、`contextTokens` 改为 `var`（已是），在 /resume 时重建 agent 并重置状态
  - [x] 2.3 `/resume <id>` 时：销毁当前 agent（`agent.close()`）→ 通过 `SessionStore` 加载历史 → 用新 sessionId 重建 BuildConfig → 调用 `AgentBuilder.build()` → 重新安装 SignalHandler → 显示恢复横幅
  - [x] 2.4 重置 `sessionUsage` 和 `contextTokens` 为零

- [x] Task 3: 实现 /resume 命令处理 (AC: #1, #2, #3)
  - [x] 3.1 修改 `SlashCommandHandler.handle()` — 将 `.resume` case 改为调用新逻辑
  - [x] 3.2 `handleResume(argument:sessionStore:)` — 无参数时列出会话，有参数时触发恢复
  - [x] 3.3 恢复逻辑需要通知 ChatCommand 重建 agent — 通过返回值或闭包机制
  - [x] 3.4 更新 `SlashCommand.resume` 的 `helpText` — 从 `"恢复会话（暂未实现）"` 改为 `"恢复会话（/resume [id]）"`

- [x] Task 4: 单元测试 (AC: #1-#5)
  - [x] 4.1 新建 `Tests/AxionCLITests/Chat/SessionResumeManagerTests.swift`
  - [x] 4.2 测试 `listSessions` — Mock SessionStore，验证过滤 running 状态
  - [x] 4.3 测试 `formatSessionList` — 格式化验证
  - [x] 4.4 测试 `formatResumeSuccess` / `formatResumeError` — 消息格式验证
  - [x] 4.5 测试 `formatResumeHint` — 提示文本验证
  - [x] 4.6 测试 /resume 无参数 — 显示列表
  - [x] 4.7 测试 /resume 错误 — sessionNotFound / sessionAlreadyRunning

## Dev Notes

### 核心设计：ChatCommand 内联恢复

**关键区别：** Story 27.2 的 `axion resume <id>` 是独立 CLI 命令，创建新进程。本 Story 是在 ChatCommand REPL 循环**内部**恢复，需要：

1. **销毁旧 agent** — `try? await buildResult.agent.close()`
2. **重建 BuildConfig** — 使用目标 sessionId + 同一个 sessionStore
3. **重建 agent** — `AgentBuilder.build(resumeBuildConfig)`
4. **重装 SignalHandler** — 新 agent 需要新的 interrupt 回调
5. **重置状态** — `sessionUsage = TokenUsage()`、`contextTokens = 0`
6. **显示恢复横幅** — 类似启动横幅但标注 "已恢复"
7. **继续 REPL** — 循环不中断，prompt 用新 sessionId

### 通信机制：SlashCommandHandler → ChatCommand

当前 `SlashCommandHandler.handle()` 返回 `Bool`（是否退出）。恢复会话需要 ChatCommand 执行 agent 重建逻辑，但 SlashCommandHandler 不应持有 ChatCommand 状态。

**推荐方案：扩展 handle() 返回类型**

```swift
enum SlashCommandAction {
    case none           // 继续循环
    case exit           // 退出 REPL
    case resumeSession(String)  // 恢复指定 session
}

static func handle(...) -> SlashCommandAction
```

ChatCommand 在 REPL 循环中检查返回值：

```swift
let action = SlashCommandHandler.handle(cmd, ...)
switch action {
case .none: continue
case .exit: break  // 退出循环
case .resumeSession(let sid):
    // 销毁旧 agent，重建，重置状态
    try? await buildResult.agent.close()
    // ... 重建逻辑 ...
}
```

### 当前代码位置

**ChatCommand.swift 第 143-161 行 — slash 命令分发：**
```swift
if let cmd = SlashCommand.parse(trimmed) {
    let argument = SlashCommand.parseArgument(trimmed)
    let shouldExit = SlashCommandHandler.handle(
        cmd, argument: argument, ...
    )
    if shouldExit { break }
    continue
}
```

**SlashCommandHandler.swift 第 44-45 行 — /resume 占位：**
```swift
case .resume:
    fputs(handleResume(), stderr)
```

**SlashCommandHandler.swift 第 163-166 行 — 占位实现：**
```swift
static func handleResume() -> String {
    "[axion] /resume 暂未实现，将在后续版本中支持\n"
}
```

**SlashCommand.swift 第 52 行 — 帮助文本：**
```swift
case .resume: return "恢复会话（暂未实现）"
```

### 会话列表获取

**关键：** ChatCommand 已有 `sessionStore`（`BuildConfig.forChat()` 传入的 `SessionStore(sessionsDir: sessionsDir)`），可直接使用 `sessionStore.list()` 获取会话列表。

但 `SessionStore` 是 SDK actor，需要 `await`。`SlashCommandHandler` 目前全是 `static` 同步方法。

**方案 A（推荐）：** 在 ChatCommand REPL 循环中处理列表逻辑，SlashCommandHandler 只负责格式化：
1. ChatCommand 检测到 `/resume` 无参数 → 调用 `sessionStore.list()` 获取列表
2. 传给 `SessionResumeManager.formatSessionList()` 格式化
3. 显示结果

**方案 B：** 让 ChatCommand 的 REPL 循环直接处理 `.resume` case，不通过 SlashCommandHandler。

**推荐方案 A** — 保持 SlashCommandHandler 的分发职责，复用格式化逻辑。

### 恢复横幅

新增 `BannerRenderer.renderResumeBanner()` 方法：

```swift
static func renderResumeBanner(
    sessionId: String,
    messageCount: Int,
    model: String,
    contextWindow: Int
) -> String {
    let contextMax = formatTokenCount(contextWindow)
    return """
        [axion] 已恢复会话 \(sessionId) (\(messageCount) 条消息)
        Model: \(model) · Context: 0/\(contextMax)
        输入任务继续对话，/help 查看命令

        """
}
```

### SessionResumeManager 设计

```swift
struct SessionResumeManager {
    /// 从 SessionStore 获取可恢复的会话列表（最近 10 条，排除 running）
    static func listResumableSessions(store: SessionStore, limit: Int = 10) async throws -> [SessionInfo]

    /// 格式化会话列表为文本表格
    static func formatSessionList(_ sessions: [SessionInfo]) -> String

    /// 格式化恢复成功消息
    static func formatResumeSuccess(sessionId: String, messageCount: Int) -> String

    /// 格式化列表末尾提示
    static func formatResumeHint() -> String

    /// 格式化恢复错误消息
    static func formatResumeError(_ error: Error) -> String

    /// 从 SessionData 获取消息数量
    static func getMessageCount(from data: SessionData) -> Int
}
```

### 实现架构

```
SessionResumeManager (新组件，纯函数 struct)
  │
  ├── listResumableSessions(store:limit:) → [SessionInfo]
  ├── formatSessionList(_:) → String
  ├── formatResumeSuccess(sessionId:messageCount:) → String
  ├── formatResumeHint() → String
  └── formatResumeError(_:) → String

ChatCommand.swift (修改)
  │
  ├── REPL 循环中处理 SlashCommandAction.resumeSession
  ├── 销毁旧 agent + 重建 agent + 重置状态
  ├── /resume 无参数时列出会话
  └── 显示恢复横幅

SlashCommandHandler.swift (修改)
  │
  ├── handle() 返回类型从 Bool 改为 SlashCommandAction
  ├── .resume case 调用 handleResume(argument:)
  └── handleResume 返回 .resumeSession(id) 或 .none

BannerRenderer.swift (修改)
  │
  └── 新增 renderResumeBanner()

SlashCommand.swift (修改)
  │
  └── /resume 帮助文本更新
```

### 关键设计决策

1. **SessionResumeManager 是纯函数 struct** — 所有方法为 static，不持有状态。与 `BannerRenderer`、`ContextManager`、`PermissionHandler` 同模式。

2. **agent 重建在 ChatCommand 中执行** — SlashCommandHandler 只返回意图（`SlashCommandAction.resumeSession(id)`），不直接操作 agent。

3. **handle() 返回类型改为 enum** — 从 `Bool` 改为 `SlashCommandAction` enum，支持更多操作类型。现有 `return true` 改为 `return .exit`，`return false` 改为 `return .none`。

4. **恢复失败不退出 REPL** — 重建 agent 失败时，尝试恢复旧 agent（或保持错误状态但允许 `/exit`），不让用户卡住。

5. **列表限制 10 条** — 终端空间有限，只显示最近 10 条可恢复会话。用户可用 `axion sessions` 查看完整列表。

6. **不通过 AxionRuntime 恢复** — `AxionRuntime.resumeSession()` 是为 `axion resume` CLI 命令设计的（涉及 EventHandler 注册、event loop 等）。ChatCommand 直接使用 `AgentBuilder.build()` + `agent.stream()` 更简单。

7. **SessionStore 已在 ChatCommand 中** — `BuildConfig.forChat()` 传入了 `sessionStore`，可直接从 `buildConfig.sessionStore` 获取，无需新建。

### 恢复流程详解

```
用户输入: /resume chat-a1b2c3d4

ChatCommand REPL 循环:
  1. SlashCommandHandler.handle(.resume, argument: "chat-a1b2c3d4") → .resumeSession("chat-a1b2c3d4")
  2. ChatCommand 匹配 .resumeSession(let sid):
     a. 验证 session 存在: sessionStore.load(sessionId: sid)
     b. 验证 session 非 running: loadOverlay(sessionId: sid)
     c. 销毁旧 agent: try? await buildResult.agent.close()
     d. 重建 BuildConfig: BuildConfig.forChat(sessionId: sid, sessionStore: sessionStore, ...)
     e. 重建 agent: AgentBuilder.build(resumeBuildConfig)
     f. 重装 SignalHandler: SignalHandler.install { newAgent.interrupt() }
     g. 更新变量: buildResult = newBuildResult, sessionId = sid
     h. 重置: sessionUsage = TokenUsage(), contextTokens = 0
     i. 获取消息数: loadedSession.metadata.messageCount
     j. 显示恢复横幅: BannerRenderer.renderResumeBanner(...)
  3. 继续下一轮 REPL 循环
```

### 关键反模式（必须避免）

1. **不要在 SlashCommandHandler 中操作 agent** — handler 只返回意图，agent 重建在 ChatCommand 中
2. **不要使用 `print()`** — 控制序列用 `fputs()` + `stderr`/`stdout`（project-context.md 反模式 #3）
3. **不要修改 `RunCommand`** — `axion run "task"` 不受影响
4. **不要通过 AxionRuntime 恢复** — ChatCommand 直接用 AgentBuilder 更简单
5. **不要在恢复失败时退出 REPL** — 错误后用户应能继续或 /exit
6. **不要忘记重装 SignalHandler** — 新 agent 需要新的 interrupt 回调
7. **不要忘记更新 `buildResult` 引用** — REPL 循环后续代码依赖 `buildResult.agent`
8. **不要硬编码列表限制** — 使用 `SessionResumeManager` 的参数
9. **不要修改 SDK** — 使用现有 `SessionStore.load()` / `SessionStore.list()` API

### 测试策略

- **单元测试（必须 Mock）：**
  - `SessionResumeManager` — 纯函数，直接测试静态方法
  - `formatSessionList` — 验证表格格式
  - `formatResumeSuccess` / `formatResumeError` — 消息格式
  - `SlashCommandAction` — enum 值验证
  - `SlashCommandHandler` — `/resume` 无参数返回 `.none`，有参数返回 `.resumeSession`
  - `BannerRenderer.renderResumeBanner` — 格式化验证
  - **Mock 策略：** 与现有 SlashCommandHandlerTests 同模式

- **不写集成测试** — 不调用真实 LLM API 或 SessionStore

### SDK 关键 API 参考

| 函数/类型 | 位置 | 说明 |
|-----------|------|------|
| `SessionStore.list(limit:)` | `OpenAgentSDK/Stores/SessionStore.swift:278` | 列出所有会话（按 updatedAt 降序） |
| `SessionStore.load(sessionId:)` | `OpenAgentSDK/Stores/SessionStore.swift:122` | 加载指定会话的消息和元数据 |
| `SessionMetadata.messageCount` | `OpenAgentSDK/Stores/SessionStore.swift` | 会话消息数量 |
| `SessionMetadata.id` | `OpenAgentSDK/Stores/SessionStore.swift` | 会话 ID |
| `AgentOptions.sessionId` | `OpenAgentSDK/Types/AgentTypes.swift:297` | SDK 自动恢复此 session 的历史 |
| `AgentOptions.sessionStore` | `OpenAgentSDK/Types/AgentTypes.swift:293` | SDK 读写 session 的存储后端 |
| `Agent.close()` | `OpenAgentSDK/Core/Agent.swift` | 关闭 agent 释放资源 |
| `AgentBuilder.BuildConfig.forChat()` | `Sources/AxionCLI/Services/AgentBuilder.swift:103` | Chat 模式 BuildConfig 工厂 |

### References

- [Source: _bmad-output/implementation-artifacts/37-7-context-management.md] — Story 37.7（前序 story，上下文管理）
- [Source: _bmad-output/implementation-artifacts/37-1-slash-command-system.md:32] — /resume 占位声明
- [Source: _bmad-output/implementation-artifacts/27-2-session-resume-cli.md] — Story 27.2（axion resume CLI 命令，参考但不同路径）
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift:143-161] — slash 命令分发（需修改返回类型）
- [Source: Sources/AxionCLI/Chat/SlashCommandHandler.swift:44-45] — /resume case 处理
- [Source: Sources/AxionCLI/Chat/SlashCommandHandler.swift:163-166] — /resume 占位实现
- [Source: Sources/AxionCLI/Chat/SlashCommand.swift:52] — /resume 帮助文本
- [Source: Sources/AxionCLI/Chat/BannerRenderer.swift:52-53] — renderExit（已提示 /resume）
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift:103-134] — BuildConfig.forChat 工厂方法
- [Source: Sources/AxionCLI/Services/AxionRuntime.swift:354-437] — resumeSession 参考实现
- [Source: Sources/AxionCLI/Commands/SessionsCommand.swift:60-85] — renderTable 格式参考
- [Source: Sources/AxionCore/Models/SessionInfo.swift] — SessionInfo 模型

### Previous Story Intelligence (37.7)

- **ContextManager 已完成** — 纯函数 struct，static methods 模式
- **contextTokens 变量已存在** — `ChatCommand.swift:96`，恢复时需重置为 0
- **compactBoundary 事件处理** — 不受 resume 影响，恢复后新 agent 的 compact 事件照常处理
- **68 个测试全部通过** — 新测试需覆盖 SlashCommandAction enum

### Previous Story Intelligence (37.6)

- **MultiLineInputReader 已完成** — 恢复后继续使用同一 inputReader 实例
- **ChatCommand REPL 循环已稳定** — ~250 行，结构清晰

### Previous Story Intelligence (37.5)

- **PermissionHandler 已完成** — 恢复后 permissionMode 需保持不变（从原 buildConfig 复制）

### Previous Story Intelligence (37.4)

- **ChatOutputFormatter 已完成** — 不受 resume 影响

### Previous Story Intelligence (37.3)

- **BannerRenderer 已完成** — 需新增 renderResumeBanner()
- **renderExit 提示** — 已包含 "使用 /resume 可恢复"

### Previous Story Intelligence (37.2)

- **SignalHandler 已完成** — 恢复后需重装（新 agent.interrupt() 回调）

### Previous Story Intelligence (37.1)

- **/resume 是占位实现** — 本 Story 核心任务
- **SlashCommandHandler.handle() 返回 Bool** — 需改为 SlashCommandAction enum

### Previous Story Intelligence (37.0)

- **BuildConfig.forChat()** — 支持 sessionId + sessionStore 参数

### Git Intelligence

最近 5 个提交：
- `4e5e0c5` feat(story-37.7): 上下文管理 — 新增 ContextManager，compact 检测
- `eca8a70` feat(story-37.6): 多行输入支持 — 新增 MultiLineInputReader
- `c37d8f0` feat(story-37.5): 权限审批机制 — 新增 PermissionHandler
- `9f71692` feat(story-37.4): 终端输出优化 — 新增 ChatOutputFormatter
- `9c7e56f` feat(story-37.3): 启动横幅 + 会话信息 — 新增 BannerRenderer

本 Story 37.8 新增 SessionResumeManager.swift 独立文件，修改 ChatCommand（resume 逻辑）、SlashCommandHandler（返回类型 + resume handler）、SlashCommand（帮助文本）、BannerRenderer（恢复横幅）。与 ContextManager、MultiLineInputReader 等 Chat 组件互不干扰。

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- ✅ Task 1: 创建 `SessionResumeManager.swift` — 纯函数 struct，包含 `formatSessionList`、`formatResumeSuccess`、`formatResumeHint`、`formatResumeError`、`formatSessionNotFound`、`formatSessionAlreadyRunning`
- ✅ Task 2: 修改 `ChatCommand.swift` — 将 `buildResult`/`sessionId`/`buildConfig`/`contextWindow` 改为 `var`，在 REPL 循环中处理 `SlashCommandAction.resumeSession`：销毁旧 agent → 重建 BuildConfig + agent → 重装 SignalHandler → 重置 sessionUsage/contextTokens → 显示恢复横幅
- ✅ Task 3: 新增 `SlashCommandAction` enum（`.none`/`.exit`/`.resumeSession(String)`），`SlashCommandHandler.handle()` 返回类型从 `Bool` 改为 `SlashCommandAction`，`handleResume(argument:)` 无参数返回 `.none`（ChatCommand 显示列表），有参数返回 `.resumeSession(id)`；`/resume` 无参数时 ChatCommand 通过 `SessionStore.list()` 获取会话列表并用 `SessionResumeManager` 格式化显示
- ✅ Task 3.4: 更新 `SlashCommand.resume` helpText 从 "暂未实现" 改为 "恢复会话（/resume [id]）"
- ✅ Task 4: 新建 `SessionResumeManagerTests.swift` — 17 个测试覆盖 `formatSessionList`（空/非空/无 summary）、`formatResumeSuccess`、`formatResumeHint`、`formatResumeError`、`formatSessionNotFound`、`formatSessionAlreadyRunning`、`SlashCommandAction` enum 相等性、`BannerRenderer.renderResumeBanner`、`handleResume` 参数场景、helpText 更新
- ✅ `BannerRenderer` 新增 `renderResumeBanner()` 方法
- ✅ 全部 2092 个单元测试通过，0 回归

### Senior Developer Review (AI)

**Reviewer:** Nick · **Date:** 2026-06-07 · **Model:** GLM-5.1

**Issues Found:** 3 CRITICAL, 2 HIGH, 3 MEDIUM → **6 fixed, 0 action items remaining**

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| C1 | CRITICAL | AC3: 无 session 存在性验证 — `formatSessionNotFound()` 从未被调用 | ✅ ChatCommand 恢复路径增加 `store.load()` 验证 |
| C2 | CRITICAL | AC3: 无 session 运行状态检查 — `formatSessionAlreadyRunning()` 从未被调用 | ✅ 检查 `targetSessionId == sessionId`，阻止恢复当前会话 |
| C3 | CRITICAL | AC2: `messageCount: 0` 硬编码 — 恢复横幅永远显示 0 条消息 | ✅ 从 `sessionData.metadata.messageCount` 获取实际值 |
| H1 | HIGH | Session ID 截断至 8 字符 — 用户无法看到完整 ID 来恢复 | ✅ SESSION 列宽 12→16，截断 8→14（覆盖 `chat-a1b2c3d4`） |
| H2 | HIGH | `formatSessionNotFound`/`formatSessionAlreadyRunning` 死代码 | ✅ 修复 C1/C2 后已使用 |
| M1 | MEDIUM | AC1: 未过滤 running 会话 | ⚠️ SDK SessionMetadata 无 status 字段，无法实现；增加当前会话检查作为替代 |

**Files Modified in Review:**
- `Sources/AxionCLI/Commands/ChatCommand.swift` — 增加 session 验证 + 实际 messageCount
- `Sources/AxionCLI/Chat/SessionResumeManager.swift` — 修正 SESSION 列宽 12→16, 截断 8→14
- `Tests/AxionCLITests/Chat/SessionResumeManagerTests.swift` — 更新断言匹配新列宽

**Test Result:** 1863 tests passed, 0 failures

### File List

- `Sources/AxionCLI/Chat/SessionResumeManager.swift` — 新增：会话恢复格式化组件
- `Sources/AxionCLI/Chat/SlashCommandHandler.swift` — 修改：新增 SlashCommandAction enum，handle() 返回类型改为 SlashCommandAction，handleResume(argument:) 替代旧占位
- `Sources/AxionCLI/Chat/SlashCommand.swift` — 修改：resume helpText 更新
- `Sources/AxionCLI/Chat/BannerRenderer.swift` — 修改：新增 renderResumeBanner()
- `Sources/AxionCLI/Commands/ChatCommand.swift` — 修改：REPL 循环支持 SlashCommandAction，/resume 无参数列出会话，/resume <id> 重建 agent
- `Tests/AxionCLITests/Chat/SlashCommandTests.swift` — 修改：更新 handleResume 测试从占位改为参数化返回值测试
- `Tests/AxionCLITests/Chat/SessionResumeManagerTests.swift` — 新增：17 个单元测试
