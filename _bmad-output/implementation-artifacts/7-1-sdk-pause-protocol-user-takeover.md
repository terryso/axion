# Story 7.1: 基于 SDK Pause Protocol 的用户接管机制

Status: done

## Story

As a 用户,
I want 在自动化受阻时暂停、手动完成后恢复,
So that 不完美的自动化仍然可以完成任务，而不是直接报错退出.

## Acceptance Criteria

1. **AC1: Takeover 暂停触发**
   Given 任务执行遇到 `blocked` 状态且 Agent 调用了 `pause_for_human` 工具
   When SDK 暂停 Agent 执行
   Then 终端显示接管提示，包含阻塞原因和操作选项

2. **AC2: 用户恢复执行**
   Given Agent 处于 paused 状态，终端显示接管提示
   When 用户按 Enter
   Then 调用 `Agent.resume(context: "用户已完成手动操作")`，截取当前屏幕状态，Agent 继续执行

3. **AC3: 用户跳过步骤**
   Given Agent 处于 paused 状态，终端显示接管提示
   When 用户输入 `skip`
   Then 调用 `Agent.resume(context: "skip")`，标记当前步骤为 skipped，继续后续步骤

4. **AC4: 用户终止任务**
   Given Agent 处于 paused 状态，终端显示接管提示
   When 用户输入 `abort`
   Then 调用 `Agent.interrupt()`，进入 `cancelled` 状态，显示已完成步骤摘要

5. **AC5: 超时处理**
   Given SDK paused 超过 5 分钟无用户输入
   When 超时触发
   Then SDK 自动发出 `.pausedTimeout` 事件，RunCommand 显示超时提示，任务以 `failed` 状态结束

6. **AC6: 前台模式交互**
   Given `--allow-foreground` 模式且任务受阻进入 takeover
   When 暂停生效
   Then 前台操作限制暂时解除，用户可以自由操作桌面，恢复后限制重新生效

7. **AC7: JSON 输出模式兼容**
   Given `--json` 模式且任务受阻进入 takeover
   When 暂停生效
   Then paused 事件以 JSON 结构输出到 stdout，用户输入仍从 stdin 读取

## Tasks / Subtasks

- [x] Task 1: 注册 pause_for_human 工具 (AC: #1)
  - [x] 1.1 在 RunCommand 中将 `createPauseForHumanTool()` 添加到 AgentOptions.tools 数组
  - [x] 1.2 配置 `AgentOptions.pauseTimeoutMs = 300_000`（5 分钟）
  - [x] 1.3 编写测试验证工具已注册到 Agent

- [x] Task 2: 处理 .paused 和 .pausedTimeout SDKMessage 事件 (AC: #1, #2, #3, #4, #5)
  - [x] 2.1 在 RunCommand 的 stream 循环中添加 `.system` 消息的 paused 子类型处理分支
  - [x] 2.2 解析 `PausedData.reason` 显示阻塞原因
  - [x] 2.3 从 stdin 读取用户输入（Enter / skip / abort）
  - [x] 2.4 根据用户输入调用 `agent.resume()` 或 `agent.interrupt()`
  - [x] 2.5 处理 `.pausedTimeout` 事件 — 显示超时提示
  - [x] 2.6 编写单元测试验证消息处理逻辑

- [x] Task 3: 创建 TakeoverIO 终端交互模块 (AC: #1, #2, #3, #4)
  - [x] 3.1 创建 `Sources/AxionCLI/IO/TakeoverIO.swift`
  - [x] 3.2 实现 `displayTakeoverPrompt(reason:)` — 显示接管提示
  - [x] 3.3 实现 `readTakeoverInput() -> TakeoverAction` — 读取并解析用户输入
  - [x] 3.4 定义 `TakeoverAction` 枚举（.resume, .skip, .abort）
  - [x] 3.5 编写测试（Mock stdin）

- [x] Task 4: 输出处理器增强 (AC: #1, #7)
  - [x] 4.1 在 `SDKTerminalOutputHandler` 中处理 `.paused` 和 `.pausedTimeout` 系统消息
  - [x] 4.2 在 `SDKJSONOutputHandler` 中输出 paused 事件为 JSON 结构
  - [x] 4.3 编写测试验证两种输出模式

- [x] Task 5: 前台模式集成 (AC: #6)
  - [x] 5.1 在 takeover 暂停时，如果 `--allow-foreground` 模式，显示前台操作提示
  - [x] 5.2 恢复后无需额外处理（SafetyChecker hook 仅在工具执行前检查）
  - [x] 5.3 编写测试验证前台模式提示文案

- [x] Task 6: Trace 记录集成 (AC: #1, #2, #4, #5)
  - [x] 6.1 记录 `takeover_paused` 事件（含 reason）
  - [x] 6.2 记录 `takeover_resumed` 事件（含用户 context）
  - [x] 6.3 记录 `takeover_aborted` 事件
  - [x] 6.4 记录 `takeover_timeout` 事件
  - [x] 6.5 编写测试验证 trace 记录

## Dev Notes

### SDK Pause Protocol 已实现的能力

SDK 已完整实现 pause/resume/abort 协议（`Sources/OpenAgentSDK/Core/Agent.swift:320-471`）。关键 API：

- `Agent.pause(reason:)` — 设置暂停状态（由 `pause_for_human` 工具内部调用）
- `Agent.resume(context:)` — 恢复执行，注入用户上下文到对话
- `Agent.interrupt()` — 中断执行，触发 `.aborted` 结果
- `AgentOptions.pauseTimeoutMs` — 配置暂停超时（默认 300000ms = 5 分钟）

SDK 的 `pause_for_human` 工具（`Sources/OpenAgentSDK/Tools/Core/PauseForHumanTool.swift`）通过 `setPauseHandler()` 设置回调。回调在 `stream()` 内部自动设置：
1. 发出 `.system(.paused, pausedData)` SDKMessage
2. 通过 `CheckedContinuation` 挂起等待
3. `agent.resume()` 恢复 continuation → 工具返回 `PauseResult.resumed(context:)`
4. `agent.interrupt()` 恢复 continuation → 工具返回 `PauseResult.aborted`
5. 超时 → 发出 `.system(.pausedTimeout)` → 工具返回 `PauseResult.timedOut`

**关键：Axion 不需要自己调用 `setPauseHandler()` — SDK 在 `stream()` 内部自动处理。Axion 只需：**
1. 注册 `pause_for_human` 工具到工具池
2. 在 stream 循环中监听 `.paused` / `.pausedTimeout` SDKMessage
3. 读取 stdin → 调用 `agent.resume()` / `agent.interrupt()`

### 需要修改的现有文件

1. **`Sources/AxionCLI/Commands/RunCommand.swift`** [UPDATE]
   - 在 AgentOptions 构建时添加 `createPauseForHumanTool()` 到 tools 数组
   - 添加 `pauseTimeoutMs: 300_000` 到 AgentOptions
   - 在 `for await message in messageStream` 循环中添加 `.system` 处理分支
   - 调用 TakeoverIO 读取用户输入，根据结果调用 resume/interrupt
   - 保留：现有 agent 创建、stream 循环、cancellation handler、memory 提取逻辑

2. **`Sources/AxionCLI/Output/TerminalOutput.swift`** [UPDATE] — 无需修改（TakeoverIO 独立输出）

3. **`RunCommand.swift` 中的 `SDKTerminalOutputHandler`** [UPDATE]
   - 添加 `.system` 消息的 paused/pausedTimeout 子类型处理

4. **`RunCommand.swift` 中的 `SDKJSONOutputHandler`** [UPDATE]
   - 添加 paused 事件的 JSON 输出

### 需要创建的新文件

1. **`Sources/AxionCLI/IO/TakeoverIO.swift`** [NEW]
   - TakeoverAction 枚举（.resume, .skip, .abort）
   - TakeoverIO 类：displayTakeoverPrompt + readTakeoverInput

2. **`Tests/AxionCLITests/IO/TakeoverIOTests.swift`** [NEW]
   - 测试 TakeoverAction 解析
   - 测试提示显示格式

3. **`Tests/AxionCLITests/Commands/TakeoverIntegrationTests.swift`** [NEW]
   - 测试 stream 循环中 paused 事件处理

### AgentOptions.pauseTimeoutMs 默认值

SDK 默认值：`300_000`（5 分钟），在 `AgentTypes.swift:496` 定义。Axion 显式传入以保持一致。

### Import 顺序

```swift
// RunCommand.swift — 不需要新增 import
import ArgumentParser
import Foundation
import OpenAgentSDK
import AxionCore

// TakeoverIO.swift
import Foundation
```

### TakeoverIO 设计

```swift
enum TakeoverAction: String {
    case resume  // Enter 或 "continue"
    case skip    // "skip"
    case abort   // "abort" 或 "quit"
}

final class TakeoverIO {
    let write: (String) -> Void
    let readLine: () -> String?

    init(write: @escaping (String) -> Void = { fputs($0 + "\n", stdout); fflush(stdout) },
         readLine: @escaping () -> String? = { Swift.readLine() })

    func displayTakeoverPrompt(reason: String, allowForeground: Bool) { ... }
    func readTakeoverAction() -> TakeoverAction { ... }
}
```

### SDKMessage.SystemData.Subtype.paused 事件结构

SDK 发出的 paused 事件：
```swift
.system(SDKMessage.SystemData(
    subtype: .paused,
    message: "Agent paused: {reason}",
    sessionId: sessionId,
    pausedData: SDKMessage.PausedData(reason: reason)
))
```

SDK 发出的 pausedTimeout 事件：
```swift
.system(SDKMessage.SystemData(
    subtype: .pausedTimeout,
    message: "Pause timed out after \(pauseTimeoutMs)ms",
    sessionId: sessionId,
    pausedData: SDKMessage.PausedData(reason: reason, canResume: false)
))
```

Axion 在 stream 循环中处理：
```swift
case .system(let data):
    switch data.subtype {
    case .paused:
        guard let pausedData = data.pausedData else { break }
        let action = takeoverIO.displayTakeoverPrompt(
            reason: pausedData.reason,
            allowForeground: allowForeground
        )
        switch action {
        case .resume:
            agent.resume(context: "用户已完成手动操作")
        case .skip:
            agent.resume(context: "skip")
        case .abort:
            agent.interrupt()
        }
    case .pausedTimeout:
        // SDK 已自动处理超时，工具返回 .timedOut
        // 只需显示提示
        output.write("[axion] 接管超时（5 分钟无操作），任务终止。")
    default:
        break
    }
```

### 关键注意事项

1. **不要调用 `setPauseHandler()`** — SDK 在 `stream()` 内部自动设置，外部调用会覆盖内部 handler
2. **`agent.resume()` 是非阻塞的** — 它恢复 CheckedContinuation，pause_for_human 工具立即返回
3. **stdin 读取阻塞整个 async 任务** — `readLine()` 是同步阻塞的，但这正是预期行为（暂停直到用户输入）
4. **超时由 SDK 管理** — `pauseTimeoutMs` 触发后 SDK 自动恢复 continuation 并返回 `.timedOut`
5. **`createPauseForHumanTool()` 返回 `ToolProtocol`** — 直接添加到 tools 数组即可

### 前台模式行为

当 `--allow-foreground` 时，SafetyChecker 的 hook 不会阻止前台操作。用户在 takeover 期间可以自由操作桌面。恢复后 Agent 继续执行，hook 正常生效。无需特殊代码处理。

### NFR 注意

- **NFR8**: Ctrl-C 在 takeover 期间也应正确清理 — 现有 `withTaskCancellationHandler` + `agent.interrupt()` 已覆盖
- **NFR9**: paused 事件中的 reason 可能包含屏幕信息，不应包含 API Key
- **NFR15**: 接管提示清晰，用户无需猜测操作方式

### 前一 Story 的关键学习（Story 6.2）

- **SDK `createPauseForHumanTool()`** 是 module-level 函数，直接调用即可
- **863 测试全部通过**，零回归 — 变更时保持测试通过
- **stdout 纯净原则**：TakeoverIO 使用 `fputs(..., stderr)` 还是 stdout？ takeover 提示应输出到 stdout（用户需要看到），但如果是 `--json` 模式则不能写 stdout。解决方案：
  - Terminal 模式：TakeoverIO 输出到 stdout
  - JSON 模式：通过 SDKJSONOutputHandler 输出 paused 事件 JSON
  - stdin 读取始终通过 `readLine()` — 两种模式都从 stdin 读取

### 项目结构注意事项

- TakeoverIO 放 `Sources/AxionCLI/IO/` 目录（已有 TerminalSetupIO、TerminalDoctorIO）
- 测试放 `Tests/AxionCLITests/IO/`
- TakeoverAction 枚举放 `TakeoverIO.swift` 同文件
- 所有变更仅在 AxionCLI 模块内

### References

- Epic 7 定义: `_bmad-output/planning-artifacts/epics.md` (Story 7.1)
- Architecture: `_bmad-output/planning-artifacts/architecture.md`
- Project Context: `_bmad-output/project-context.md`
- Previous Story 6.2: `_bmad-output/implementation-artifacts/6-2-axion-mcp-command-agent-integration.md`
- SDK Agent.swift (pause/resume): `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift:320-471`
- SDK PauseForHumanTool: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Core/PauseForHumanTool.swift`
- SDK PauseResult enum: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Core/PauseForHumanTool.swift:12-19`
- SDK SDKMessage.PausedData: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/SDKMessage.swift:921`
- SDK AgentOptions.pauseTimeoutMs: `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/AgentTypes.swift:432`
- RunCommand: `Sources/AxionCLI/Commands/RunCommand.swift`
- TerminalOutput: `Sources/AxionCLI/Output/TerminalOutput.swift`
- TerminalSetupIO (stdin 读取参考): `Sources/AxionCLI/IO/TerminalSetupIO.swift`

## Dev Agent Record

### Agent Model Used

GLM-5.1 (via Claude Code)

### Debug Log References

无阻塞问题。

### Completion Notes List

- Created TakeoverIO module with TakeoverAction enum and interactive prompt
- Registered `createPauseForHumanTool()` in AgentOptions.tools with `pauseTimeoutMs: 300_000`
- Added `.system(.paused)` and `.system(.pausedTimeout)` handling in RunCommand stream loop
- Implemented TakeoverIO.write to stderr in JSON mode (stdout stays clean for JSON events)
- Added paused/pausedTimeout handling in both SDKTerminalOutputHandler and SDKJSONOutputHandler
- SDKJSONOutputHandler now has `writeEvent` closure for streaming JSON paused events
- Foreground mode hint displayed when `--allow-foreground` is active
- Trace events: takeover_paused, takeover_resumed, takeover_aborted, takeover_timeout
- 889 total tests pass, 0 regressions (26 new tests added)

### Change Log

- 2026-05-14: Implemented SDK Pause Protocol user takeover mechanism (Story 7.1)
- 2026-05-14: Senior Developer Review (AI) — 找到 7 个问题，全部修复
  - **HIGH**: TakeoverIntegrationTests 两个 tautology 测试替换为有意义的流程测试
  - **HIGH**: AC4 缺少 abort 步骤摘要 — TakeoverIO 新增 completedSteps 参数，abort 时显示已完成步骤数
  - **MEDIUM**: SDKJSONOutputHandler.pausedTimeout JSON 缺少 reason 字段 — 已补充
  - **MEDIUM**: JSON paused 事件缺少 sessionId — paused 和 pausedTimeout 均已添加 sessionId
  - **MEDIUM**: SDKJSONOutputHandler 可选值隐式转换警告 — 已修复
  - **LOW**: takeover_aborted trace 事件补充 completedSteps payload
  - **LOW**: 新增 3 个测试覆盖 abort 步骤摘要和 JSON 新字段

### File List

- `Sources/AxionCLI/IO/TakeoverIO.swift` [NEW]
- `Sources/AxionCLI/Commands/RunCommand.swift` [MODIFIED]
- `Tests/AxionCLITests/IO/TakeoverIOTests.swift` [NEW]
- `Tests/AxionCLITests/Commands/PauseToolRegistrationTests.swift` [NEW]
- `Tests/AxionCLITests/Commands/TakeoverIntegrationTests.swift` [NEW]
- `Tests/AxionCLITests/SDKOutputHandlerTests.swift` [MODIFIED]
