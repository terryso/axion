---
story_id: 37.2
epic: 37
title: Ctrl+C 优雅中断
status: done
created: 2026-06-07
baseline_commit: aff3118
---

# Story 37.2: Ctrl+C 优雅中断

As a CLI 用户,
I want 按 Ctrl+C 时只中断当前正在执行的任务而不是退出整个交互模式,
So that 我可以取消一个耗时操作但继续在同一会话中工作.

## Acceptance Criteria

1. **AC1 — 单次中断**：agent 正在执行一个耗时任务时，用户按一次 Ctrl+C，当前任务被中断，显示 `[axion] 已中断`，回到 `axion>` 提示符，会话历史保留，可以继续对话

2. **AC2 — 双次退出**：用户在 2 秒内连续按两次 Ctrl+C，第二次 Ctrl+C 退出交互模式，显示 `[axion] 再见`

3. **AC3 — 空闲不退出**：用户在 `axion>` 提示符下按 Ctrl+C（没有任务在执行），显示新行 `axion>` 提示符，不退出程序

4. **AC4 — 无回归**：`axion run "task"` 行为完全不受影响（信号处理仅在 ChatCommand 中注册）

5. **AC5 — Agent 清理**：中断后 agent 仍可用（不需要重建），后续 `agent.stream()` 调用正常工作

## Tasks / Subtasks

- [x] Task 1: 创建 SignalHandler 工具类 (AC: #1-#3)
  - [x] 1.1 新建 `Sources/AxionCLI/Chat/SignalHandler.swift`
  - [x] 1.2 实现 `final class SignalHandler` — 封装 `DispatchSource` + `SIGINT` 处理
  - [x] 1.3 `static func install(handler: @escaping () -> Void)` — 注册 SIGINT 为 SIG_IGN + DispatchSource
  - [x] 1.4 `static func uninstall()` — 恢复 SIGINT 为 SIG_DFL（退出时调用）
  - [x] 1.5 `static func fireCount() -> Int` — 返回自上次 reset 以来的信号触发次数
  - [x] 1.6 `static func reset()` — 重置计数

- [x] Task 2: 修改 ChatCommand REPL 循环 (AC: #1-#5)
  - [x] 2.1 在 REPL 循环前安装 SignalHandler
  - [x] 2.2 handler 直接调用 `agent.interrupt()` 中断流（与 RunOrchestrator 同模式，避免 Task 包装）
  - [x] 2.3 REPL 循环内联 for-await stream，信号触发时 agent.interrupt() 自动终止流
  - [x] 2.4 信号触发时调用 `buildResult.agent.interrupt()` 中断当前流
  - [x] 2.5 双击检测：记录上次中断时间戳，2 秒内第二次 → `break` 退出 REPL
  - [x] 2.6 单次中断：显示 `[axion] 已中断`，继续 REPL 循环
  - [x] 2.7 空闲态 Ctrl+C：显示新提示符（readLine 被中断时 guard let 失败 → continue）+ ^C 字符过滤
  - [x] 2.8 退出前调用 `SignalHandler.uninstall()` 恢复默认信号处理

- [x] Task 3: 单元测试 (AC: #1-#4)
  - [x] 3.1 测试 `SignalHandler` — install/uninstall 不崩溃
  - [x] 3.2 测试 `SignalHandler.fireCount()` — 初始为 0，触发后递增，reset 后归零
  - [x] 3.3 测试双击检测逻辑 — `chatShouldExit(lastInterrupt:now:)` 2 秒内返回 true，超过 2 秒返回 false
  - [x] 3.4 测试 ChatCommand 中断行为不回归 — 验证 SlashCommand 解析不受影响

## Dev Notes

### 核心架构理解

**当前 ChatCommand（117 行）的 REPL 循环：**
```swift
while true {
    fputs("axion> ", stdout); fflush(stdout)
    guard let line = readLine(strippingNewline: true) else { break }
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    // Slash command handling...
    let outputHandler = SDKTerminalOutputHandler(mode: "chat")
    let messageStream = buildResult.agent.stream(trimmed)
    for await message in messageStream {
        outputHandler.handle(message)
        // token 累计...
    }
    outputHandler.displayCompletion()
}
```

**当前问题：** 没有任何 SIGINT 处理。Ctrl+C 直接触发默认的 SIG_DFL 行为（终止进程），整个 REPL 退出。

**本 Story 的改动路径：** 注册 SIGINT 处理器，在 REPL 循环中区分「空闲态」和「执行态」的 Ctrl+C 响应。

### 已有信号处理模式参考

**RunOrchestrator（RunCommand 使用的模式）：**
```swift
// Sources/AxionCLI/Services/RunOrchestrator.swift:164-170
signal(SIGINT, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
sigintSource.setEventHandler {
    agent.interrupt()
}
sigintSource.resume()
```

**RunOrchestrator 退出时恢复：**
```swift
// Sources/AxionCLI/Services/RunOrchestrator.swift:310
signal(SIGINT, SIG_DFL)
```

**GatewayCommand 的模式：**
```swift
// Sources/AxionCLI/Commands/GatewayCommand.swift:578-582
signal(SIGTERM) { _ in
    _Concurrency.Task { await Self.signalHandlerRunner?.stop(graceful: true) }
}
signal(SIGINT) { _ in
    _Concurrency.Task { await Self.signalHandlerRunner?.stop(graceful: false) }
}
```

**本 Story 应复用 RunOrchestrator 的 DispatchSource 模式**（更安全，信号源可取消）。不使用 signal() 闭包模式（GatewayCommand 的方式），因为闭包中调用 Agent.interrupt() 不够可控。

### SDK Agent.interrupt() 方法

SDK 的 `Agent.interrupt()` 方法（[Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift#L392]）：

```swift
public func interrupt() {
    _interrupted = true
    // If paused, resume the continuation with abort sentinel
    let continuationToResume = _pauseLock.withLock { () -> CheckedContinuation<String, Never>? in
        let cont = _pauseContinuation
        _pauseContinuation = nil
        _pauseTimeoutTask?.cancel()
        _pauseTimeoutTask = nil
        _paused = false
        return cont
    }
    continuationToResume?.resume(returning: "__PAUSE_ABORT__")
    _streamTask?.cancel()
}
```

**关键行为：**
1. 设置 `_interrupted = true` — SDK 内部循环检查此标志
2. 如果 agent 处于 paused 状态，abort pause
3. 取消 `_streamTask` — 引发 cooperative cancellation

**interrupt() 后 agent 仍可用：** `_interrupted` 标志在新的 `stream()` 调用时被重置（Agent.swift 第 489 行附近 `guard !_Concurrency.Task.isCancelled` 是检查 Task 级别取消，而 `_interrupted` 在 stream() 入口处重置）。后续 `agent.stream()` 调用可以正常工作（AC5）。

### 关键文件位置

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/AxionCLI/Chat/SignalHandler.swift` | **NEW** | SIGINT 处理封装 |
| `Sources/AxionCLI/Commands/ChatCommand.swift` | **UPDATE** | REPL 循环添加中断逻辑 |
| `Tests/AxionCLITests/Chat/SignalHandlerTests.swift` | **NEW** | 单元测试 |

### SignalHandler 设计

```swift
import Darwin
import Foundation

/// SIGINT 信号处理器封装，用于 Chat REPL 的 Ctrl+C 优雅中断。
///
/// 使用 DispatchSource 模式（非 signal() 闭包），线程安全且可取消。
/// 参考同模式：RunOrchestrator.swift:164-170。
final class SignalHandler: Sendable {
    private static let lock = NSLock()
    private static var _source: DispatchSourceSignal?
    private static var _count: Int = 0

    /// 安装 SIGINT 处理器。重复调用是安全的（幂等）。
    static func install(handler: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard _source == nil else { return } // 已安装

        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        source.setEventHandler {
            lock.lock()
            _count += 1
            lock.unlock()
            handler()
        }
        source.resume()
        _source = source
    }

    /// 卸载处理器，恢复 SIGINT 默认行为。
    static func uninstall() {
        lock.lock()
        defer { lock.unlock() }
        _source?.cancel()
        _source = nil
        signal(SIGINT, SIG_DFL)
    }

    /// 返回自上次 reset 以来的信号触发次数。
    static func fireCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    /// 重置计数器为 0。
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        _count = 0
    }
}
```

**线程安全说明：** `_count` 通过 `NSLock` 保护。handler 闭包在 `DispatchSource` 的全局队列上执行，与 REPL 的 async 上下文安全隔离。`NSLock` 本身不是 `Sendable`，但 `static` 方法访问不跨 actor 边界。

### ChatCommand REPL 改动

```swift
mutating func run() async throws {
    // ... 现有初始化代码不变 ...

    var sessionUsage = TokenUsage(inputTokens: 0, outputTokens: 0)
    var lastInterruptTime: ContinuousClock.Instant?

    // 安装 SIGINT 处理器
    SignalHandler.install {
        // handler 在 DispatchSource 全局队列上执行
        // 不做任何 UI 操作，仅计数
        // ChatCommand REPL 循环在等待 stream task 时检查 fireCount
    }

    while true {
        SignalHandler.reset()  // 每轮重置
        fputs("axion> ", stdout)
        fflush(stdout)
        guard let line = readLine(strippingNewline: true) else {
            // readLine 返回 nil 可能是因为 SIGINT 中断了 read
            if SignalHandler.fireCount() > 0 {
                continue  // AC3: 空闲态 Ctrl+C → 显示新提示符
            }
            break
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }

        // Slash command handling（不变）
        if let cmd = SlashCommand.parse(trimmed) {
            let argument = SlashCommand.parseArgument(trimmed)
            let shouldExit = SlashCommandHandler.handle(
                cmd, argument: argument, agent: buildResult.agent,
                config: config, sessionUsage: sessionUsage, buildConfig: buildConfig
            )
            if shouldExit { break }
            continue
        } else if trimmed.hasPrefix("/") {
            fputs(SlashCommandHandler.handleUnknown(trimmed), stderr)
            continue
        }

        // 执行 agent stream
        let outputHandler = SDKTerminalOutputHandler(mode: "chat")
        let streamTask = Task {
            let messageStream = buildResult.agent.stream(trimmed)
            for await message in messageStream {
                guard !_Concurrency.Task.isCancelled else { return }
                outputHandler.handle(message)
                if case .result(let data) = message, let usage = data.usage {
                    sessionUsage = sessionUsage + usage
                }
            }
        }

        // 等待 stream 完成，同时轮询中断信号
        _ = await withTaskGroup(of: Void.self) { group in
            group.addTask { await streamTask.value }
            group.addTask {
                // 中断等待循环
                while !streamTask.isCancelled {
                    if SignalHandler.fireCount() > 0 {
                        buildResult.agent.interrupt()
                        break
                    }
                    try? await _Concurrency.Task.sleep(for: .milliseconds(100))
                }
            }
            // 任一完成即取消另一个
            await group.next()
            group.cancelAll()
        }

        // 中断处理
        let interruptCount = SignalHandler.fireCount()
        if interruptCount > 0 {
            let now = ContinuousClock.now
            if let last = lastInterruptTime,
               (now - last).components.seconds < 2 {
                // AC2: 2 秒内双击 Ctrl+C → 退出
                break
            }
            lastInterruptTime = now
            fputs("[axion] 已中断\n", stderr)  // AC1
        } else {
            lastInterruptTime = nil
            outputHandler.displayCompletion()
            fputs("\n", stdout)
        }
    }

    SignalHandler.uninstall()
    try? await buildResult.agent.close()
    fputs("[axion] 再见\n", stderr)
}
```

**关键设计决策：**

1. **轮询 vs DispatchSource handler 直接触发：** 轮询 100ms 间隔足够快（用户感知不到 100ms 延迟），且避免了从 DispatchSource 全局队列跨到 async 上下文的复杂性。RunOrchestrator 的 `agent.interrupt()` 可以在 handler 中直接调用（因为 interrupt() 是线程安全的），但 ChatCommand 还需要更新 `lastInterruptTime` 和控制 REPL 循环流程，轮询模式更清晰。

2. **withTaskGroup 取消策略：** stream task 和中断轮询放在同一个 TaskGroup 中，任一完成即取消另一个。`group.cancelAll()` 会取消 stream task，进而 cooperative cancellation 让 agent.stream() 退出。

3. **readLine 中断处理：** `readLine()` 在收到 SIGINT（已被 SIG_IGN）时不会中断，但某些终端配置下可能返回 nil。guard nil 时检查 fireCount，如果 > 0 说明是中断导致的，continue 显示新提示符。

### 空闲态 Ctrl+C 处理（AC3）

空闲态（`readLine()` 等待中）按 Ctrl+C 的行为：
1. SIGINT 已被 SIG_IGN 忽略，不会终止进程
2. `SignalHandler.fireCount()` 递增
3. `readLine()` 不会被 SIGINT 中断（因为 SIG_IGN），但用户会在终端看到 `^C` 显示
4. 用户按回车后，`readLine()` 返回空字符串或 `^C` 字符
5. 如果返回空 → `continue` 显示新提示符
6. 如果返回 `^C` → trimmed 为 `^C`（非空，非 slash 命令）→ 会发送给 agent

**问题：** 上述第 6 点是 undesirable 的。解决方案：在 REPL 循环的 readLine 后添加 `^C` 检测：

```swift
// 过滤终端产生的 ^C 字符
if trimmed == "^C" { continue }
```

### 双击退出检测（AC2）

```swift
/// 检查是否应在双击后退出 REPL。
private func shouldExitAfterDoubleInterrupt(
    lastInterruptTime: inout ContinuousClock.Instant?
) -> Bool {
    let now = ContinuousClock.now
    if let last = lastInterruptTime,
       (now - last).components.seconds < 2 {
        return true  // 2 秒内双击 → 退出
    }
    lastInterruptTime = now
    return false
}
```

### 关键反模式（必须避免）

1. **不要在 ChatCommand 外注册 SIGINT** — 信号处理仅在 ChatCommand REPL 中使用，不影响 `axion run`（AC4）
2. **不要在 DispatchSource handler 中做 UI 操作** — handler 在全局队列执行，`fputs` 等操作应在 REPL 主循环中进行
3. **不要忘记 uninstall()** — 退出前必须恢复 SIG_DFL，否则后续代码（如 ArgumentParser 错误处理）的 Ctrl+C 行为异常
4. **不要在每次 REPL 循环都 install()** — `install()` 应在循环外调用一次，`reset()` 在每轮循环开始时调用
5. **不要修改 `SDKTerminalOutputHandler`** — 它被 RunCommand 使用（project-context.md 反模式 #3）
6. **不要修改 `axion run` 路径** — RunOrchestrator 有自己的信号处理，完全独立
7. **不要在中断后重建 agent** — SDK `Agent.interrupt()` 后仍可用，后续 `stream()` 调用会重置 `_interrupted` 标志
8. **不要使用 `signal(SIGINT, closure)` 模式** — 使用 DispatchSource 模式（更安全，可取消，与 RunOrchestrator 一致）

### 测试策略

- **单元测试（必须 Mock）：**
  - `SignalHandler.install/uninstall` — 验证安装和卸载不崩溃
  - `SignalHandler.fireCount/reset` — 初始为 0，发送 SIGINT 后递增，reset 后归零
  - `shouldExitAfterDoubleInterrupt()` — 2 秒内双击返回 true，超过 2 秒返回 false
  - **Mock 策略：** SignalHandler 是 static 方法，直接测试真实行为（发送 SIGINT 给自身进程）。发送 SIGINT 使用 `kill(getpid(), SIGINT)`。
  - ChatCommand 中断行为通过 `SlashCommand.parse()` 不受影响来验证无回归

- **不写集成测试** — 不启动真实 agent 或终端

### Project Structure Notes

- 新文件 `SignalHandler.swift` 放在 `Sources/AxionCLI/Chat/` 目录（与 SlashCommand 同级）
- 测试文件放在 `Tests/AxionCLITests/Chat/SignalHandlerTests.swift`（镜像源结构）

### References

- [Source: docs/epics/epic-37-interactive-chat-mode.md#Story 37.2] — 完整 story 定义和 AC
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift] — 当前 REPL 实现（117 行）
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift#L164-L170] — RunCommand 的 SIGINT 处理模式（参考）
- [Source: Sources/AxionCLI/Services/RunOrchestrator.swift#L310] — SIG_DFL 恢复（参考）
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift#L392] — `Agent.interrupt()` 方法
- [Source: open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift#L489] — stream() 内部的 cancellation check
- [Source: _bmad-output/implementation-artifacts/37-1-slash-command-system.md] — Story 37.1 完成记录（前序 story）

### Previous Story Intelligence (37.1)

- **Slash 命令系统已完成** — 8 个命令（help/clear/compact/model/cost/resume/config/exit）+ 未知命令拦截
- **sessionUsage 累计** — 每轮 stream 结束后从 `SDKMessage.result` 提取 `TokenUsage` 累计
- **REPL 循环结构** — SlashCommand.parse → SlashCommandHandler.handle → agent.stream
- **Chat/ 目录已创建** — SlashCommand.swift 和 SlashCommandHandler.swift 在此目录
- **测试文件位置** — `Tests/AxionCLITests/Chat/SlashCommandTests.swift`（31 个测试通过）
- **Code Review 修复要点** — 未知斜杠命令拦截（`else if trimmed.hasPrefix("/")`）、handleModel 重构为纯函数、成本估算加入 cache token

### Git Intelligence

最近 3 个提交：
- `aff3118` feat(story-37.1): Slash 命令体系
- `3b9f251` feat(story-37.0): Coding Agent 系统提示 + 项目上下文
- `582feeb` feat: add interactive chat mode as default command

Story 37.1 在 ChatCommand REPL 中建立了 slash 命令处理体系。本 Story 37.2 在同一 REPL 循环中添加 SIGINT 信号处理，两者互不干扰（slash 命令在 readLine 之后、stream 之前处理；中断处理在 stream 执行期间生效）。

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Swift 6 strict concurrency: `nonisolated(unsafe)` 用于 SignalHandler static 可变属性（通过 NSLock 保护）
- `_Concurrency.Task` 包装 stream 导致 `@Sendable` 闭包捕获非 Sendable 类型 → 改为 handler 直接调用 `agent.interrupt()`，for-await 循环内联
- 测试框架并发执行共享静态状态竞争 → `@Suite(.serialized)` 解决
- 真实 SIGINT 信号在测试进程中无法可靠传递 → 添加 `simulateFire()` 测试方法

### Completion Notes List

- ✅ Task 1: SignalHandler 工具类创建完成 — DispatchSource + SIG_IGN 模式，NSLock 线程安全，幂等安装
- ✅ Task 2: ChatCommand REPL 循环改造完成 — 3 种 Ctrl+C 场景（执行中断/双击退出/空闲新行），agent.interrupt() 直接触发模式
- ✅ Task 3: 12 个单元测试全部通过 — SignalHandler 生命周期、fireCount/reset、chatShouldExit 双击检测、SlashCommand 无回归
- ✅ 全量回归测试 1948 个测试通过，0 失败

### File List

| File | Status | Description |
|------|--------|-------------|
| `Sources/AxionCLI/Chat/SignalHandler.swift` | NEW | SIGINT 信号处理器封装 |
| `Sources/AxionCLI/Commands/ChatCommand.swift` | MODIFIED | REPL 循环添加 Ctrl+C 中断处理 |
| `Tests/AxionCLITests/Chat/SignalHandlerTests.swift` | NEW | 12 个单元测试 |

## Change Log

- 2026-06-07: Story 37.2 实现 — Ctrl+C 优雅中断（SignalHandler + ChatCommand REPL 改造 + 12 个测试）
- 2026-06-07: 代码审查 — 2 个 MEDIUM 修复：`chatShouldExit` 改用 Duration 直接比较（更地道精确）、`install(handler:)` 添加 `@Sendable` 注解（类型安全）

## Senior Developer Review (AI)

**日期:** 2026-06-07
**结果:** Approve（2 个 MEDIUM 已自动修复，无 CRITICAL 问题）

### AC 验证

| AC | 状态 | 证据 |
|----|------|------|
| AC1 单次中断 | ✅ IMPLEMENTED | `SignalHandler.fireCount() > 0` → `fputs("[axion] 已中断\n")`, REPL 继续 |
| AC2 双次退出 | ✅ IMPLEMENTED | `chatShouldExit()` 检查 2 秒内双击 → `break` + `[axion] 再见` |
| AC3 空闲不退出 | ✅ IMPLEMENTED | `^C` 过滤 + readLine nil guard → `continue` 显示新提示符 |
| AC4 无回归 | ✅ IMPLEMENTED | 信号处理仅在 ChatCommand 注册，RunOrchestrator 独立，1948 回归测试通过 |
| AC5 Agent 清理 | ✅ IMPLEMENTED | `agent.interrupt()` 后 SDK `stream()` 重置 `_interrupted`，agent 可复用 |

### Task 审计

所有 Task 标记 [x] 均有实现证据，无虚假完成。

### 审查发现

**MEDIUM — 已修复：**
1. `chatShouldExit` 使用 `.components.seconds < 2`（截断到整秒）→ 改为 `(now - last) < .seconds(2)`（Duration 直接比较，更地道精确）
2. `install(handler:)` 缺少 `@Sendable` 注解 → 添加 `@escaping @Sendable () -> Void`，与 DispatchSource handler 的 Sendable 上下文匹配

**LOW — 记录：**
- `chatShouldExit` 是 `internal` 自由函数（测试需要，可接受）
- `simulateFire()` 测试专用方法暴露在生产代码中（标准 Swift 模式）
- readLine nil + fireCount 路径在 SIG_IGN 下为防御性代码（SIGINT 不会导致 readLine 返回 nil）

### 测试验证

- 12/12 单元测试通过
- 1948/1948 全量回归测试通过
