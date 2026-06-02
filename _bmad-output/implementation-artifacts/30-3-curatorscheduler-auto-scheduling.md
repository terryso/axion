# Story 30.3: CuratorScheduler 自动调度

---
baseline_commit: b5b9a1e9a13fc79ea2d3253062ec079c11b36ba1
---
Status: done

## Story

As a Axion Gateway 长驻进程,
I want 空闲时自动触发 Curator（基于空闲时长和间隔配置），执行技能策展（合并重叠、归档过期、修补 SKILL.md），
so that Axion 在后台持续自我进化，技能库保持精简和高质量，无需用户手动运行 `axion curator run`。

## Acceptance Criteria

1. **CuratorScheduler actor** — 新建 `Sources/AxionCLI/Services/CuratorScheduler.swift`（~80 行），作为 actor 实现 EventHandler protocol，监听 `AgentCompletedEvent` 和 `AgentFailedEvent`。

   **Given** CuratorScheduler 注册为 EventHandler 并订阅 AgentCompletedEvent 和 AgentFailedEvent
   **When** 任务完成事件到达
   **Then** CuratorScheduler 记录 `lastTaskAt` 时间戳，并检查是否满足 curator 触发条件

2. **空闲检测 + 间隔检查** — CuratorScheduler 检查两个条件：(a) 空闲时间 > `gatewayCuratorIdleHours`（默认 2h），(b) 距上次 curator > `gatewayCuratorIntervalHours`（默认 168h = 7d）。

   **Given** lastTaskAt 距今 > curatorIdleHours 且 lastCuratorAt 距今 > curatorIntervalHours
   **When** CuratorScheduler 检查条件
   **Then** 在 detached Task 中调用 `IntelligentCurator.execute(parentAgent:dryRun:)`

   **Given** 条件不满足
   **When** CuratorScheduler 检查条件
   **Then** 不触发 curator，等待下次事件

3. **Curator 执行与结果处理** — CuratorScheduler 在 detached Task 中执行 `IntelligentCurator.execute()`，完成后记录结果到 trace + stderr + `lastCuratorAt`。

   **Given** Curator 执行成功
   **When** IntelligentCuratorResult 返回
   **Then** 使用 `CuratorRunReport(from:).renderMarkdown()` 记录 trace，stderr 输出摘要行，更新 `lastCuratorAt`

   **Given** Curator 执行失败
   **When** execute() 抛出错误
   **Then** logger.warning 记录错误，不影响 Gateway 主流程

4. **CuratorScheduler 不触发审查路径** — CuratorScheduler 只负责 Curator 调度，不涉及 ReviewScheduler 的逻辑。两者独立运行。

   **Given** CuratorScheduler 和 ReviewScheduler 都注册为 EventHandler
   **When** AgentCompletedEvent 到达
   **Then** ReviewScheduler 检查审查间隔，CuratorScheduler 检查空闲间隔，互不干扰

5. **GatewayRunner 集成** — CuratorScheduler 在 Gateway 模式下注册为 EventHandler，通过 `extraHandlers` 注入。`lastCuratorAt` 桥接到 GatewayRunner 的 `_curatorStatusProvider`。

   **Given** Gateway 进程启动
   **When** GatewayStartCommand 初始化
   **Then** CuratorScheduler 创建并注入到 AxionRuntime 的 extraHandlers（与 ReviewScheduler 并列）

6. **Gateway status 展示 curator 详情** — `axion gateway status` 输出中，`last_curator_at` 字段从 CuratorScheduler 获取。

   **Given** 至少执行过一次 curator
   **When** 查询 gateway status
   **Then** `last_curator_at` 显示 ISO8601 时间戳

   **Given** 从未执行过 curator
   **When** 查询 gateway status
   **Then** `last_curator_at` 为 nil（显示 "(pending)"）

7. **可选 TG 推送 Curator 结果** — 如果 `gatewayNotifyCuratorResults == true`，Curator 完成后推送摘要到 TG。否则仅记录 trace + stderr。

   **Given** gatewayNotifyCuratorResults == true 且 TG 已配置
   **When** Curator 执行成功
   **Then** 推送如 "🔧 策展完成: 合并 2 个技能, 归档 1 个技能" 到 TG

   **Given** gatewayNotifyCuratorResults == false（默认）
   **When** Curator 执行成功
   **Then** 仅 trace + stderr 输出，不推送 TG

8. **单元测试** — 所有新增逻辑有对应单元测试。

   **Given** 新增 CuratorScheduler
   **When** 运行 `swift test --filter "AxionCLITests"`
   **Then** 所有测试通过

## Tasks / Subtasks

- [x] Task 1: 创建 CuratorScheduler actor (AC: #1, #2)
  - [x] 1.1 新建 `Sources/AxionCLI/Services/CuratorScheduler.swift`（actor）
  - [x] 1.2 实现 EventHandler protocol（identifier、subscribedEventTypes: [AgentCompletedEvent.self, AgentFailedEvent.self]）
  - [x] 1.3 维护 `lastTaskAt: Date?` 状态（每次收到事件时更新）
  - [x] 1.4 维护 `lastCuratorAt: Date?` 状态（curator 执行成功后更新）
  - [x] 1.5 实现 `shouldCurate()` 方法：检查空闲 + 间隔条件
  - [x] 1.6 使用 `LockedStringBox` 提供 `lastCuratorAtValue: String?`（nonisolated getter）

- [x] Task 2: Curator 执行与结果处理 (AC: #3)
  - [x] 2.1 handle() 中调用 shouldCurate() → 满足则 detached Task 执行 curator
  - [x] 2.2 通过 init 注入 `IntelligentCurator` 和 `Agent`（或闭包获取）
  - [x] 2.3 调用 `IntelligentCurator.execute(parentAgent:dryRun:)` 获取 IntelligentCuratorResult
  - [x] 2.4 使用 `CuratorRunReport(from:).renderMarkdown()` 生成报告并记录 trace
  - [x] 2.5 stderr 输出摘要行（如 `[axion] Curator: 合并 2 个技能, 归档 1 个技能`）
  - [x] 2.6 更新 `lastCuratorAt` 时间戳
  - [x] 2.7 失败时 logger.warning + 不影响主流程
  - [x] 2.8 实现 `onCuratorResult` 回调（可选 TG 推送）

- [x] Task 3: GatewayRunner 集成 (AC: #5, #6)
  - [x] 3.1 在 GatewayStartCommand 中创建 CuratorScheduler 实例
  - [x] 3.2 通过 extraHandlers 注入到 AxionRuntime（与 ReviewScheduler 并列）
  - [x] 3.3 将 CuratorScheduler 的 lastCuratorAtValue 桥接为 GatewayRunner 的 curatorStatus provider
  - [x] 3.4 将 `setStatusProviders(curatorStatus:)` 从 `nil` 替换为 `curatorScheduler.lastCuratorAtValue`（见 GatewayCommand.swift:242-246 和 :282-287 两处）

- [x] Task 4: 可选 TG 推送 (AC: #7)
  - [x] 4.1 CuratorScheduler init 接收 `notifyResults: Bool` 参数
  - [x] 4.2 当 notifyResults == true 时，通过回调推送 curator 结果到 TG
  - [x] 4.3 GatewayCommand 中根据 `config.gatewayNotifyCuratorResults` 传入

- [x] Task 5: 单元测试 (AC: #8)
  - [x] 5.1 CuratorSchedulerTests: 测试 shouldCurate() 条件判断
  - [x] 5.2 CuratorSchedulerTests: 测试 lastTaskAt 更新（收到事件时）
  - [x] 5.3 CuratorSchedulerTests: 测试 handle() 触发 detached Task
  - [x] 5.4 CuratorSchedulerTests: 测试 lastCuratorAt 状态更新
  - [x] 5.5 CuratorSchedulerTests: 测试条件不满足时不触发
  - [x] 5.6 CuratorSchedulerTests: 测试 curator 执行失败场景
  - [x] 5.7 CuratorSchedulerTests: 测试 onCuratorResult 回调

## Dev Notes

### 核心架构

**CuratorScheduler** 是一个 actor，实现 EventHandler protocol。它监听 `AgentCompletedEvent` 和 `AgentFailedEvent`（用于追踪最后一次任务时间），在收到事件后：
1. 更新 `lastTaskAt` 为当前时间
2. 检查空闲条件：`now - lastTaskAt > curatorIdleHours` 且 `now - lastCuratorAt > curatorIntervalHours`
3. 如果满足，在 detached Task 中执行 `IntelligentCurator.execute(parentAgent:dryRun:)`
4. 处理结果：trace 记录 + stderr 提示 + lastCuratorAt 更新 + 可选 TG 推送

### 关键：CuratorScheduler 与 ReviewScheduler 的区别

| 方面 | ReviewScheduler | CuratorScheduler |
|------|----------------|-----------------|
| 触发条件 | 间隔检查（memory/skill interval） | 空闲检查（idleHours + intervalHours） |
| 执行方式 | ReviewOrchestrator.executeReview() | IntelligentCurator.execute() |
| 需要 agent | 是（fork review agent） | 是（作为 parentAgent 传入） |
| 工具白名单 | memory + skill 操作 | 由 IntelligentCurator 内部管理 |
| TG 推送 | 通过 onReviewResult 回调（Story 30.2） | 通过 onCuratorResult 回调（可选） |

### 关键：获取 Agent 和 IntelligentCurator

CuratorScheduler 需要：
1. **Agent** — 传给 `IntelligentCurator.execute(parentAgent:)`
2. **IntelligentCurator** — 已构建好的 curator 实例

**方案**：使用与 ReviewScheduler 相同的模式 — 通过闭包/inject 获取依赖：
- `agentProvider: (@Sendable () -> Agent?)?` — 闭包获取当前 agent
- `curator: IntelligentCurator` — init 时注入

或者更简方案：使用 `ReviewDataContext` 已有的模式 — CuratorScheduler 在 init 时接收 `agentProvider` 和 `curatorProvider` 闭包。

**推荐方案**：参考 ReviewScheduler 的 `reviewDataContext` 模式。但 CuratorScheduler 不需要 ReviewDataContext。改为直接注入：
```swift
init(
    curatorIdleHours: Double,
    curatorIntervalHours: Double,
    curator: IntelligentCurator,
    agentProvider: @Sendable @escaping () -> Agent?,
    traceDir: String,
    notifyResults: Bool,
    onCuratorResult: (@Sendable (CuratorResultInfo) async -> Void)?
)
```

### 关键：IntelligentCurator 在哪里创建

IntelligentCurator 在 `AgentBuilder.build()` 中创建（见 `AgentBuilder.swift:340-346`）。它需要 6 个依赖：skillCurator、factStore、skillRegistry、skillEvolver、usageStore、curatorStore。

**方案**：GatewayStartCommand 中手动创建 IntelligentCurator（参考 CuratorCommand.swift 的组装模式），不依赖 AgentBuilder.build()。这与 CuratorCommand 的做法一致 — CuratorCommand 直接创建所有依赖。

```swift
// In GatewayStartCommand, before creating CuratorScheduler:
let skillsDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("skills")
let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
let usageStore = SkillUsageStore(skillsDir: skillsDir)
let curatorStore = SkillCuratorStore(skillsDir: skillsDir)
let factStore = FactStore(memoryDir: memoryDir)
let skillRegistry = SkillRegistry()
AxionBuiltInSkills.registerAll(into: skillRegistry)
_ = skillRegistry.registerDiscoveredSkills()
let evolverClient = AnthropicClient(apiKey: apiKey, baseURL: config.baseURL)
let skillEvolver = LLMSkillEvolver(client: evolverClient, evolutionModel: config.reviewModel ?? AxionConfig.defaultReviewModel)
let curatorConfig = SkillCuratorConfig(intervalHours: config.curatorIntervalHours ?? 168.0, ...)
let skillCurator = SkillCurator(usageStore: usageStore, curatorStore: curatorStore, config: curatorConfig)
let curator = IntelligentCurator(skillCurator: skillCurator, factStore: factStore, skillRegistry: skillRegistry, skillEvolver: skillEvolver, usageStore: usageStore, curatorStore: curatorStore)
```

**注意**：`SkillRegistry` 在 GatewayStartCommand 中已经创建了（用于 AxionAPI），可以直接复用。但 `FactStore`、`SkillUsageStore`、`SkillCuratorStore` 需要额外创建。参考 CuratorCommand.swift:30-67 的完整组装逻辑。

### 关键：Agent 获取方式

`IntelligentCurator.execute(parentAgent:)` 需要一个 Agent 实例。在 Gateway 模式下：
- 每次 run 创建独立的 AxionRuntime → AgentBuilder.build() → agent
- CuratorScheduler 不能使用正在执行任务的 agent
- 需要一个独立的 agent（不连接 Helper）

**方案**：创建一个 minimal agent（仅用于 Curator，不需要 Helper）。参考 CuratorCommand.swift:69-76：
```swift
let buildConfig = AgentBuilder.BuildConfig.forCLI(config: config, task: "curator background task", noMemory: false, verbose: false, dryrun: false)
let buildResult = try await AgentBuilder.build(buildConfig)
let agent = buildResult.agent
```

**但**：AgentBuilder.build() 会启动 HelperProcessManager，Curator 不需要。而且 build() 需要 async await，不适合在 detached Task 中调用。

**更好方案**：在 GatewayStartCommand 启动时预先构建一个 Curator 专用 agent（类似 placeholderAgent 的模式），传入 CuratorScheduler。这个 agent 的 Helper 连接不会被使用（Curator 只操作文件），但 build() 需要成功。

**或者最简方案**：使用 GatewayStartCommand 中已有的 `placeholderAgent`。IntelligentCurator 只用 parentAgent 来 fork curator agent（prompt 调用），不需要 MCP/Helper。placeholderAgent 有 model 和 apiKey 配置就足够了。

```swift
// Already exists in GatewayStartCommand:
let placeholderAgent = Agent(options: AgentOptions(model: "placeholder"))
```

但 placeholderAgent 使用 `"placeholder"` model，不够。应该使用 config 中的 model：
```swift
let curatorAgent = Agent(options: AgentOptions(model: config.model))
```

### CuratorScheduler 的 detached Task 模式

与 ReviewScheduler 一致：`_Concurrency.Task.detached` 避免 NIO Task 名字冲突。

```swift
func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
    let now = Date()
    _lastTaskAt = now

    guard shouldCurate(now: now) else { return }
    guard let curator = curator, let agent = agentProvider() else { return }

    _lastCuratorAt = now  // 防止重复触发

    _Concurrency.Task.detached { [curator, agent, traceDir, lastCuratorAtBox, onCuratorResult] in
        do {
            let result = try await curator.execute(parentAgent: agent, dryRun: false)
            // trace + stderr + update lastCuratorAtBox + optional TG push
        } catch {
            // logger.warning
        }
    }
}
```

### TG 推送 Curator 结果

与 ReviewScheduler 的 `onReviewResult` 回调模式一致：
- CuratorScheduler init 时注入 `onCuratorResult: (@Sendable (CuratorResultInfo) async -> Void)?`
- GatewayCommand 中根据 `config.gatewayNotifyCuratorResults ?? false` 决定是否设置回调
- 回调内容：格式化 consolidations 和 prunings 数量

### CuratorResultInfo 结构

```swift
struct CuratorResultInfo: Sendable {
    let consolidations: Int
    let prunings: Int
    let autoTransitions: Int
    let success: Bool
    let durationMs: Int
    let error: String?
}
```

或者直接复用 `IntelligentCuratorResult`（它已经是 Sendable）。

### 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/AxionCLI/Services/CuratorScheduler.swift` | NEW | CuratorScheduler actor + EventHandler |
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | UPDATE | 创建 CuratorScheduler 并注入 extraHandlers + curatorStatus provider |
| `Sources/AxionCLI/Services/GatewayRunner.swift` | UPDATE（可选） | 如需 curatorSummary 字段则扩展 |
| `Tests/AxionCLITests/Services/CuratorSchedulerTests.swift` | NEW | 单元测试 |

### 文件操作细节 — GatewayCommand.swift UPDATE

需要在 GatewayStartCommand.run() 中：
1. 组装 IntelligentCurator 及其依赖（参考 CuratorCommand.swift:30-67）
2. 创建 CuratorScheduler 实例
3. 将 CuratorScheduler 加入 `extraHandlers`（与 ReviewScheduler 并列）
4. 将 `curatorScheduler.lastCuratorAtValue` 桥接为 `curatorStatus` provider

当前 extraHandlers 注入点：
- HTTP API runHandler 中：`extraHandlers: [reviewScheduler]`（行 142）
- TaskSerialQueue 中：`extraHandlers: [reviewScheduler]`（行 231）

两处都需要改为 `[reviewScheduler, curatorScheduler]`。

### Project Structure Notes

- CuratorScheduler 遵循 `Sources/AxionCLI/Services/` 的 actor 放置规则（与 ReviewScheduler、TelegramAdapter、GatewayRunner 同级）
- 测试文件遵循 `Tests/AxionCLITests/Services/` 镜像规则
- CuratorScheduler 不需要 Protocol 抽象（IntelligentCurator 已是 struct，可直接使用；但如果需要 mock 则提取 `CuratorExecuting` protocol）

### References

- [Source: architecture.md#D9] Gateway 进程模型 — CuratorScheduler 组件定义
- [Source: architecture.md#D11] 后台审查 Actor 隔离策略 — CuratorScheduler 同理
- [Source: prds/prd-axion-gateway-2026-05-29/prd.md#FR-4] Curator 自进化功能需求
- [Source: CuratorCommand.swift] Curator 手动触发的完整组装逻辑（IntelligentCurator 6 个依赖）
- [Source: ReviewScheduler.swift] 当前实现模式 — EventHandler + detached Task + LockedStringBox + 回调
- [Source: AgentBuilder.swift:295-366] IntelligentCurator 在 build() 中的组装逻辑
- [Source: GatewayCommand.swift:79-84] ReviewScheduler 创建和注入模式
- [Source: GatewayCommand.swift:142] extraHandlers 注入点（HTTP API runHandler）
- [Source: GatewayCommand.swift:231] extraHandlers 注入点（TaskSerialQueue）
- [Source: GatewayCommand.swift:242-246] setStatusProviders 调用点
- [Source: GatewayRunner.swift:195] _curatorStatusProvider 使用点

### 从 Story 30.1 + 30.2 学到的教训

- **ReviewDataContext 模式** — CuratorScheduler 不需要 ReviewDataContext（不需要 ReviewOrchestrator），直接注入 IntelligentCurator
- **LockedStringBox 模式** — 非隔离域读取 actor 状态用 LockedStringBox（与 ReviewScheduler 一致）
- **_Concurrency.Task.detached** — 避免 NIO Task 名字冲突
- **直接回调 vs EventBus** — ReviewScheduler 的 `onReviewResult` 回调模式比 EventBus 更可靠（per-request EventBus 在 detached Task 完成前已停止），CuratorScheduler 使用相同的直接回调模式
- **extraHandlers 参数** — TaskSerialQueue 和 HTTP runHandler 都有 extraHandlers，两处都要更新
- **LockedStringBox.set() 使用 defer unlock** — 与 ReviewScheduler 保持一致

### 反模式预防

- **不要重新创建 Curator pipeline** — IntelligentCurator.execute() 已有完整实现（机械式 + LLM 策展），直接调用
- **不要在 CuratorScheduler 中创建 Agent** — Agent 通过 init 注入或闭包获取
- **不要在 handle() 中 await curator 结果** — detached Task，不阻塞
- **不要让 CuratorScheduler 直接调用 TG 推送** — 通过回调解耦
- **不要修改 GatewayRunner 的 GatewayRunnerStatus 结构** — lastCuratorAt 已存在
- **不要在 CuratorScheduler 中复用正在执行任务的 Agent** — 可能导致状态冲突
- **不要忘记 Curator 执行失败场景** — do/catch 防护，不影响主流程
- **不要在每次 handle() 都触发 curator** — 必须检查空闲 + 间隔两个条件
- **不要使用 EventBus 发送 Curator 结果** — 使用直接回调（与 ReviewScheduler 的 onReviewResult 模式一致）

### Curator 触发时机

CuratorScheduler 监听 `AgentCompletedEvent` 和 `AgentFailedEvent` 来追踪 `lastTaskAt`。但它还需要定期检查空闲条件——不能仅靠事件触发，因为如果长时间没有任务，curator 就永远不会触发。

**方案**：在 GatewayStartCommand 中启动一个后台定时 Task，每隔 `curatorIdleHours` 唤醒一次 CuratorScheduler 检查条件：

```swift
let idleSeconds = Int64(curatorIdleHours * 3600)
_Concurrency.Task {
    while true {
        try? await _Concurrency.Task.sleep(nanoseconds: UInt64(idleSeconds) * 1_000_000_000)
        await curatorScheduler.checkIdle()
    }
}
```

CuratorScheduler 新增 `checkIdle()` 方法，供定时器调用。`handle()` 中收到事件时也调用 `shouldCurate()` 检查。

**或者**：更简单——只在收到事件时检查。因为 Gateway 如果真的空闲（无任务），意味着没有用户交互，curator 虽然理论上应该运行，但实际不急。下次有任务完成时再检查即可。这与 PRD 的 "空闲时触发" 描述一致，但实现上是 "任务完成后检查是否空闲够久"。

**推荐**：MVP 先只用事件驱动检查（与 ReviewScheduler 一致）。如果后续发现 curator 从不触发，再加定时器。

### IntelligentCurator 线程安全

IntelligentCurator 是 `struct`（值类型）且 `Sendable`。可以安全地在 detached Task 中使用。但注意：struct 的 copy 语义意味着 curator 内部的 actor 属性（如 SkillCuratorStore、FactStore）仍然共享引用。

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- CuratorScheduler actor created with EventHandler protocol, subscribes to AgentCompletedEvent + AgentFailedEvent
- shouldCurate() checks idle hours (default 2h) + interval hours (default 168h = 7d) conditions
- Curator runs in detached Task, results recorded to trace + stderr, lastCuratorAt updated via LockedStringBox
- Extracted CuratorExecuting protocol for testability (IntelligentCurator conforms automatically)
- GatewayCommand integration: assembles IntelligentCurator + 6 deps, injects into extraHandlers alongside ReviewScheduler
- curatorStatus provider bridged from CuratorScheduler.lastCuratorAtValue to GatewayRunner (both TG and non-TG paths)
- TG push: optional callback via onCuratorResult, triggered when gatewayNotifyCuratorResults == true
- 16 unit tests all pass: shouldCurate conditions, lastTaskAt updates, handle() triggers, lastCuratorAt state, failure handling, callbacks
- No regressions introduced (pre-existing TelegramAdapter test failure unrelated)

### Senior Developer Review (AI)

**Reviewer:** Nick (via Claude Opus 4.7) on 2026-05-30
**Outcome:** Approved with auto-fixes applied

#### Findings (5 total)

| # | Severity | Issue | Resolution |
|---|----------|-------|------------|
| C1 | CRITICAL | `handle()` set `_lastTaskAt = now` BEFORE `shouldCurate()`, making idle check always 0 — curator never triggered with default 2h idle | **Fixed**: `handle()` now saves previous `_lastTaskAt` before updating, passes it to `shouldCurate(referenceLastTaskAt:)` |
| H1 | HIGH | Missing `TraceRecorder.recordCuratorFailed()` on failure path | **Fixed**: Added call in catch block of `executeCurator()` |
| M1 | MEDIUM | Missing `CuratorRunReport(from:).renderMarkdown()` per AC #3 | **Fixed**: Added `CuratorRunReport` + `logger.debug()` in success path |
| L1 | LOW | All handle() tests used `curatorIdleHours: 0.0`, masking C1 bug | **Fixed**: Added 2 tests with realistic 1h idle threshold |
| L2 | LOW | `checkIdle()` public method had no tests | **Fixed**: Added 2 checkIdle() tests |

#### Files Modified by Review

| File | Change |
|------|--------|
| `Sources/AxionCLI/Services/CuratorScheduler.swift` | Fixed handle() timing, added recordCuratorFailed, added CuratorRunReport |
| `Tests/AxionCLITests/Services/CuratorSchedulerTests.swift` | Added 4 new tests (20 total) |

### Change Log

- 2026-05-30: Story 30.3 complete — CuratorScheduler auto-scheduling implemented and tested
- 2026-05-30: Review — 5 issues found and auto-fixed (1 CRITICAL idle-timing bug, 1 missing failure trace, 1 missing CuratorRunReport, 2 test gaps). 20 tests pass.

### File List

| File | Operation | Description |
|------|-----------|-------------|
| `Sources/AxionCLI/Services/CuratorScheduler.swift` | NEW | CuratorScheduler actor + EventHandler + CuratorExecuting protocol + CuratorResultInfo |
| `Sources/AxionCLI/Commands/GatewayCommand.swift` | MODIFIED | CuratorScheduler creation, IntelligentCurator assembly, extraHandlers injection, curatorStatus provider, TG push callback |
| `Tests/AxionCLITests/Services/CuratorSchedulerTests.swift` | NEW | 20 unit tests covering all acceptance criteria + review fixes |
