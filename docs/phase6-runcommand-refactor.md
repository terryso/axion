# Phase 6 重构：RunCommand 职责瘦身 + SDK 边界优化

> 日期：2026-05-19
> 状态：Draft
> 基于：`_bmad-output/planning-artifacts/phase6-refactor-architecture.md` 与当前代码的差距分析

---

## 1. 目标

让 RunCommand 从 770 行"万能入口"瘦身为架构定义的薄层：**CLI 参数解析 + TakeoverIO + 终端输出**。其余逻辑下沉到 AgentBuilder（共享层）或 SDK。

---

## 2. 当前问题清单

| # | 问题 | 位置 | 行数 | 应属于谁 |
|---|---|---|---|---|
| 1 | Skill 发现与注册 | RunCommand:71-80 | ~10 | AgentBuilder |
| 2 | Skill 预解析三路分支（`/skill-name` 路由） | RunCommand:82-148 | ~67 | **删除**（SDK 已支持自动发现） |
| 3 | Memory 清理（过期清理 + fact demotion） | RunCommand:237-260 | ~24 | AgentBuilder 或 MemoryLifecycleManager |
| 4 | Memory 提取/保存/Profile 分析/familiarity/takeover learning | RunCommand:471-584 | ~114 | MemoryLifecycleManager（共享层） |
| 5 | CostTracker 实例化与 stream loop 内预算检查 | RunCommand:285-286, 325-332 | ~10 | SDK（`maxModelCalls`） |
| 6 | SeatMonitor 实例化与检查 | RunCommand:289-296, 315-323 | ~12 | 仅 ApiRunner（架构已明确） |
| 7 | VisualDeltaTracker | RunCommand:279-283, 349-366 | ~18 | 桌面自动化共享层（非 CLI 层） |
| 8 | Tool pair 收集（pendingToolUses / collectedPairs） | RunCommand:275-276, 334-348 | ~15 | SDK `ResultData.toolPairs`（已实现） |
| 9 | Takeover 事件上下文 + takeover learning | RunCommand:297-584 | ~50 | MemoryLifecycleManager |

---

## 3. SDK 已实现的新能力

### 3.1 `ResultData.toolPairs` — 自动 Tool Pair 收集

SDK 在 agent loop 内部自动收集所有 `toolUse`/`toolResult` 对（按 `toolUseId` 配对），并附加到最终的 `.result()` 消息中。

**新增类型：**

```swift
// SDKMessage.ResultData 新增字段
public let toolPairs: [ToolExecutionPair]

// 新增类型
public struct ToolExecutionPair: Sendable, Equatable {
    public let toolUse: ToolUseData     // 工具调用
    public let toolResult: ToolResultData // 工具结果
}
```

**Axion 如何使用：**

删除 RunCommand 中手动收集 tool pair 的代码（L275-276 的 `pendingToolUses`/`collectedPairs` 声明，L312-348 的 stream 内收集逻辑），改为从 `.result()` 直接读取：

```swift
// 之前（手动收集 ~40 行代码）
var pendingToolUses: [String: SDKMessage.ToolUseData] = [:]
var collectedPairs: [(toolUse: SDKMessage.ToolUseData, toolResult: SDKMessage.ToolResultData)] = []
// ... stream loop 内复杂匹配逻辑 ...

// 之后（直接从 SDK 获取）
case .result(let data):
    let pairs = data.toolPairs  // SDK 自动配对好的完整列表
    // 用 pairs 做 memory 提取、takeover learning 等
```

### 3.2 `maxModelCalls` — LLM 调用次数限制

SDK 在 agent loop 内自动计数 LLM API 调用次数，超过限制时终止并 yield `.result(subtype: .errorMaxModelCalls)`。

**新增字段：**

```swift
// AgentOptions 新增
public var maxModelCalls: Int?  // nil = 无限制

// QueryStatus 新增
case errorMaxModelCalls

// ResultData.Subtype 新增
case errorMaxModelCalls
```

**Axion 如何使用：**

```swift
// AgentBuilder.build() 中设置
var options = AgentOptions(
    // ... 其他配置 ...
    maxModelCalls: config.maxModelCalls  // 从 CLI --max-model-calls 或 config.json 传入
)
```

SDK 内部每次收到 LLM 响应后检查，超限自动中断。Axion 的 `CostTracker` 中 model call 计数和检查逻辑可以完全删除，但 `maxScreenshots` 计数仍需保留在应用层（screenshot 是 MCP 外部工具，SDK 不知道它的存在）。

### 3.3 `onRunComplete` — 运行完成后回调

SDK 在 stream 结束后、session 保存前调用此回调，提供完整的运行上下文。

**新增类型和字段：**

```swift
// AgentOptions 新增
public var onRunComplete: (@Sendable (RunCompleteContext) -> Void)?
public var runId: String?  // 调用方提供的 runId，透传到回调

// 新增类型
public struct RunCompleteContext: Sendable {
    public let toolPairs: [SDKMessage.ToolExecutionPair]
    public let task: String
    public let runId: String?
    public let status: QueryStatus
    public let usage: TokenUsage
    public let totalCostUsd: Double
    public let durationMs: Int
    public let numTurns: Int
    public let costBreakdown: [CostBreakdownEntry]
}
```

**Axion 如何使用：**

将 RunCommand 中的 memory 提取、takeover learning 等后处理逻辑移入回调：

```swift
// AgentBuilder.build() 中设置回调
options.onRunComplete = { context in
    // context.toolPairs — 完整的 tool 调用对
    // context.task — 原始任务描述
    // context.status — 运行状态（success/errorMaxTurns/...）
    // context.runId — Axion 传入的 runId

    // Memory 提取
    let extractor = AppMemoryExtractor()
    let entries = try? await extractor.extract(
        from: context.toolPairs,
        task: context.task,
        runId: context.runId ?? ""
    )
    // ... 保存到 memoryStore ...

    // Takeover learning
    // ... 记录接管事件学习 ...

    // Profile 分析
    // ... 分析和保存 ...
}

options.runId = runId  // 传入 RunCommand 生成的 runId
```

**注意：** `onRunComplete` 是同步闭包。如果内部需要 async 操作（如 memory store 写入），需要在闭包内使用 `Task { }` 包装，或改用 SDK 已有的 `.result()` 消息中读取 `toolPairs` 在 stream loop 外做处理。两种方式都可以。

---

## 4. 重构方案

### 4.1 删除 Skill 预解析（问题 #2）

**不变** — 按原方案执行。

### 4.2 Skill 注册移入 AgentBuilder（问题 #1）

**不变** — 按原方案执行。

### 4.3 抽取 MemoryLifecycleManager（问题 #3, #4, #9）

**调整** — 利用 SDK 的 `onRunComplete` 回调，MemoryLifecycleManager 的调用方式变为：

```swift
// RunCommand 中
options.onRunComplete = { [memoryStore, memoryDir] context in
    Task {
        await MemoryLifecycleManager.postRunExtract(
            toolPairs: context.toolPairs,
            task: context.task,
            runId: context.runId,
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            takeoverEvent: takeoverEvent,  // 需要从 stream loop 传出
            runSucceeded: context.status == .success,
            runCompleted: context.status != .cancelled,
            externallyModified: externallyModified,  // SeatMonitor 检测结果
            noMemory: noMemory
        )
    }
}
```

### 4.4 CostTracker 简化（问题 #5）

**大幅简化** — `maxModelCalls` 由 SDK 处理，Axion 只需保留 `maxScreenshots` 计数：

```swift
// 之前
let costTracker = CostTracker(maxModelCalls: config.maxModelCalls, maxScreenshots: config.maxScreenshots)

// 之后 — 只需截图计数
var screenshotCount = 0
// stream loop 内：
if data.toolName.contains("screenshot") {
    screenshotCount += 1
    if let limit = config.maxScreenshots, screenshotCount > limit {
        // 记录日志（不中断，screenshot 不是关键预算）
    }
}
```

### 4.5 SeatMonitor 从 RunCommand 移除（问题 #6）

**不变** — 按原方案执行。

### 4.6 VisualDeltaTracker 抽取（问题 #7）

**不变** — 按原方案执行。

---

## 5. 不放 SDK 的能力（不变）

| 能力 | 原因 |
|---|---|
| `maxScreenshots` | screenshot 是 MCP 外部工具，SDK 不知道它的存在，计数留给应用层 |
| Skill 预解析 | SDK 已有 `autoDiscoverSkills()` + `SkillTool` 自动发现和执行 |
| VisualDelta | 桌面自动化特有，不是通用 agent 能力 |
| SeatMonitor | 单机桌面独占检测，不是通用 agent 能力 |

---

## 6. 重构后的 RunCommand 骨架

```swift
struct RunCommand: AsyncParsableCommand {
    // CLI 参数定义（不变）

    mutating func run() async throws {
        // 1. 加载配置
        let config = try await ConfigManager.loadConfig(cliOverrides: ...)

        // 2. 构建 Agent（Skill 注册、Memory、Prompt、MCP、Hook 全在内部）
        let effectiveMaxSteps = Self.computeEffectiveMaxSteps(fast: fast, maxSteps: maxSteps, configMaxSteps: config.maxSteps)
        var buildConfig = AgentBuilder.BuildConfig.forCLI(
            config: config, task: task, noMemory: noMemory, noSkills: noSkills, ...
        )
        // 2a. 设置 SDK onRunComplete 回调（memory 提取 + takeover learning）
        buildConfig.onRunComplete = { context in
            await MemoryLifecycleManager.postRunExtract(
                toolPairs: context.toolPairs, task: context.task, runId: context.runId, ...
            )
        }
        buildConfig.runId = runId
        // 2b. 设置 maxModelCalls — SDK 自动处理 LLM 调用预算
        buildConfig.maxModelCalls = config.maxModelCalls

        let buildResult = try await AgentBuilder.build(buildConfig)
        let agent = buildResult.agent

        // 3. 选择输出处理器
        let outputHandler: any SDKMessageOutputHandler = json
            ? SDKJSONOutputHandler(mode: ...) : SDKTerminalOutputHandler(mode: ...)

        // 4. 运行前 Memory 清理
        await MemoryLifecycleManager.preRunCleanup(...)

        // 5. 获取桌面锁
        // ...

        // 6. Stream loop — 大幅简化：只做输出 + TakeoverIO + screenshot 计数
        var screenshotCount = 0
        for await message in agent.stream(task) {
            outputHandler.handleMessage(message)
            // TakeoverIO 处理 .paused 事件
            // VisualDeltaTracker 处理 screenshot toolResult
            // screenshot 计数（应用层预算）
            // SeatMonitor 检查（如果启用）
        }

        // 7. SDK 已在内部自动调用 onRunComplete
        //    （memory 提取、takeover learning 等全部在回调中完成）

        // 8. 释放锁 + 输出统计
        // ...
    }
}
```

**目标行数**：~250-300 行（从 770 行减少 ~60%）

**主要节省来源：**
- 删除 tool pair 手动收集代码（~40 行）→ SDK `toolPairs`
- 删除 CostTracker model call 计数和检查（~15 行）→ SDK `maxModelCalls`
- Memory 提取逻辑移入 `onRunComplete` 回调（~100 行）→ 回调闭包
- 删除 Skill 预解析三路分支（~67 行）→ SDK `autoDiscoverSkills`

---

## 7. 重构优先级与顺序

```
Phase 6A — 安全删除（低风险）
  ├── 删除 Skill 预解析三路分支（#2）
  ├── 删除 RunCommand 中的 SkillLookupService 引用
  └── 删除 pendingToolUses / collectedPairs 手动收集代码 → 改用 ResultData.toolPairs（#8）

Phase 6B — 职责下沉（中风险）
  ├── Skill 注册移入 AgentBuilder.build()（#1）
  ├── 抽取 MemoryLifecycleManager（#3, #4, #9）
  │   └── 利用 SDK onRunComplete 回调作为触发点
  ├── SeatMonitor 从 RunCommand 移除（#6）
  └── CostTracker 简化为仅 screenshot 计数 → maxModelCalls 由 SDK 处理（#5）

Phase 6C — SDK 适配（依赖 SDK 发版）
  ├── 确认 SDK 版本包含 toolPairs + maxModelCalls + onRunComplete
  ├── AgentBuilder.build() 中设置 onRunComplete 回调
  └── 删除 CostTracker 中 model call 相关代码

Phase 6D — 可选优化
  └── VisualDeltaTracker 抽取为 StreamMiddleware（#7）
```

---

## 8. SDK 变更清单

| 变更 | 类型 | 文件 | 说明 |
|---|---|---|---|
| `SDKMessage.ToolExecutionPair` | 新类型 | SDKMessage.swift | toolUse/toolResult 配对 |
| `ResultData.toolPairs` | 新字段 | SDKMessage.swift | 自动收集的完整 tool pair 列表 |
| `ResultData.Subtype.errorMaxModelCalls` | 新 case | SDKMessage.swift | LLM 调用次数超限 |
| `AgentOptions.maxModelCalls` | 新字段 | AgentTypes.swift | LLM 调用次数上限 |
| `QueryStatus.errorMaxModelCalls` | 新 case | AgentTypes.swift | 对应查询状态 |
| `RunCompleteContext` | 新类型 | AgentTypes.swift | onRunComplete 回调参数 |
| `AgentOptions.onRunComplete` | 新字段 | AgentTypes.swift | 运行完成后回调 |
| `AgentOptions.runId` | 新字段 | AgentTypes.swift | 调用方 runId 透传 |
| `QueryResult.toolPairs` | 新字段 | AgentTypes.swift | prompt() 同步接口也包含 tool pairs |
| Agent engine tool pair 收集 | 内部逻辑 | Agent.swift | promptImpl + stream 自动收集 |
| Agent engine maxModelCalls 检查 | 内部逻辑 | Agent.swift | 每次 LLM 响应后检查 |
| Agent engine onRunComplete 调用 | 内部逻辑 | Agent.swift | stream 结束后、session 保存前调用 |
