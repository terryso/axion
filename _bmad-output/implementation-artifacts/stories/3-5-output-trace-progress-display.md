# Story 3.5: 输出、Trace 与进度显示

Status: review

## Story

As a 用户,
I want 在终端实时看到任务执行进度和结果，并且系统自动记录完整的运行轨迹,
so that 我不需要猜测自动化任务的进展，且出问题时可以回溯调试.

## Acceptance Criteria

1. **AC1: 运行启动信息显示**
   - Given 任务开始执行
   - When TerminalOutput 显示
   - Then 输出运行 ID 和模式信息（如 `[axion] 模式: 规划执行（小批量）` 和 `[axion] 运行 ID: 20260508-a3f2k1`）

2. **AC2: 步骤执行进度显示**
   - Given 步骤开始执行
   - When TerminalOutput 更新
   - Then 显示步骤编号、工具名和目的（如 `[axion] 步骤 1/3: 启动 Calculator`）

3. **AC3: 步骤结果反馈**
   - Given 步骤执行完成
   - When TerminalOutput 更新
   - Then 显示步骤结果（ok 成功 或 x 失败及原因）

4. **AC4: 任务完成汇总**
   - Given 任务全部完成
   - When TerminalOutput 显示汇总
   - Then 显示总步数、耗时、重规划次数（如 `[axion] 完成。3 步，耗时 8.2 秒。`）

5. **AC5: JSON 结构化输出**
   - Given `--json` 标志启用
   - When JSONOutput 输出
   - Then 以结构化 JSON 格式输出完整的执行结果

6. **AC6: Trace 事件记录**
   - Given 任务运行中
   - When TraceRecorder 记录
   - Then 向 `~/.axion/runs/{runId}/trace.jsonl` 追加 JSONL 事件

7. **AC7: Trace 文件格式**
   - Given trace 文件存在
   - When 用 jq 或 cat 查看
   - Then 每行是一个独立 JSON 对象，包含 `ts`（ISO8601）和 `event`（snake_case）字段

## Tasks / Subtasks

- [x] Task 1: 实现 TerminalOutput (AC: #1, #2, #3, #4)
  - [x] 1.1 创建 `Sources/AxionCLI/Output/TerminalOutput.swift`
  - [x] 1.2 实现 `class TerminalOutput: OutputProtocol` — 所有方法格式化输出到 stdout
  - [x] 1.3 实现 `displayRunStart(runId:task:mode:)` — 输出运行 ID、任务描述、执行模式
  - [x] 1.4 实现 `displayPlan(_ plan: Plan)` — 输出计划摘要（步骤数、stopWhen 条件数）
  - [x] 1.5 实现 `displayStepResult(_ executedStep: ExecutedStep)` — 输出步骤进度（编号/总数 + 工具名 + 结果状态）
  - [x] 1.6 实现 `displayStateChange(from:to:)` — 输出状态转换（如「正在验证...」「正在重规划...」）
  - [x] 1.7 实现 `displayError(_ error: AxionError)` — 输出用户友好的错误信息
  - [x] 1.8 实现 `displaySummary(context: RunContext)` — 输出汇总（总步数、耗时、重规划次数）
  - [x] 1.9 添加 `displayReplan(attempt:maxRetries:reason:)` — 输出重规划信息

- [x] Task 2: 实现 JSONOutput (AC: #5)
  - [x] 2.1 创建 `Sources/AxionCLI/Output/JSONOutput.swift`
  - [x] 2.2 实现 `class JSONOutput: OutputProtocol` — 所有方法收集数据，最终输出 JSON
  - [x] 2.3 定义 `RunResult` 结构体：包含 runId、task、steps、state、duration、replanCount 等字段
  - [x] 2.4 实现 `finalize() -> String` — 累积数据序列化为格式化 JSON 字符串

- [x] Task 3: 实现 TraceRecorder (AC: #6, #7)
  - [x] 3.1 创建 `Sources/AxionCLI/Trace/TraceRecorder.swift`
  - [x] 3.2 实现 `actor TraceRecorder` — Actor 隔离确保文件写入串行化
  - [x] 3.3 实现 `init(runId:config:baseURL:)` — 创建 `{baseURL}/{runId}/trace.jsonl` 文件
  - [x] 3.4 实现 `func record(event: String, payload: [String: Any])` — 追加 JSONL 事件
  - [x] 3.5 定义 TraceEventType 常量：run_start, plan_created, step_start, step_done, state_change, verification_result, run_done, error
  - [x] 3.6 实现便捷方法：`recordRunStart`, `recordPlanCreated`, `recordStepStart`, `recordStepDone`, `recordStateChange`, `recordVerificationResult`, `recordRunDone`, `recordError`

- [x] Task 4: 更新 OutputProtocol (AC: #1-#7)
  - [x] 4.1 修改 `Sources/AxionCore/Protocols/OutputProtocol.swift` — 扩展协议方法签名，支持 runId、mode 等参数
  - [x] 4.2 添加 `func displayRunStart(runId: String, task: String, mode: String)`
  - [x] 4.3 添加 `func displayReplan(attempt: Int, maxRetries: Int, reason: String)`
  - [x] 4.4 添加 `func displayVerificationResult(_ result: VerificationResult)`
  - [x] 4.5 保留现有 5 个方法签名不变（displayPlan, displayStepResult, displayStateChange, displayError, displaySummary）

- [x] Task 5: 集成到现有模块 (AC: #1-#7)
  - [x] 5.1 在 StepExecutor 中添加 output + trace 回调点（步骤开始前记录 step_start，步骤完成后记录 step_done + displayStepResult）
  - [x] 5.2 在 TaskVerifier 中添加 trace 回调点（验证结果记录 verification_result）
  - [x] 5.3 在 LLMPlanner 中添加 trace 回调点（计划创建记录 plan_created）
  - [x] 5.4 确保 trace 目录 `~/.axion/runs/` 在首次写入时自动创建

- [x] Task 6: 编写单元测试
  - [x] 6.1 创建 `Tests/AxionCLITests/Output/TerminalOutputTests.swift` — 测试格式化输出字符串（捕获 stdout）
  - [x] 6.2 创建 `Tests/AxionCLITests/Output/JSONOutputTests.swift` — 测试 JSON 输出结构完整性
  - [x] 6.3 创建 `Tests/AxionCLITests/Trace/TraceRecorderTests.swift` — 测试 JSONL 文件写入、事件格式、ISO8601 时间戳
  - [x] 6.4 创建 `Tests/AxionCoreTests/OutputProtocolTests.swift` — 测试协议方法签名和默认实现

- [x] Task 7: 运行全部单元测试确认无回归
  - [x] 7.1 运行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` 确认全部通过

## Dev Notes

### 核心目标

实现 Axion 的「可观测性」层：TerminalOutput 提供人类可读的实时终端进度，JSONOutput 提供机器可解析的结构化结果，TraceRecorder 提供完整的运行轨迹持久化。三者共同实现 PRD 中的 FR33-FR35 和 NFR15、NFR20。

### 架构定位：输出和 Trace 是横切关注点

Output 和 Trace 不是执行循环的核心逻辑（Planner/Executor/Verifier 才是），而是横切关注点 — 它们需要被注入到核心模块中，但不影响核心逻辑的正确性。

**注入方式：** 通过构造器注入（dependency injection），StepExecutor/TaskVerifier/LLMPlanner 在初始化时可选接收 OutputProtocol 和 TraceRecorder。当注入为 nil 时，核心逻辑正常运行，只是没有输出和 trace。

这与 Story 3-3/3-4 中 MCPClientProtocol 的注入模式一致。

### 关键设计决策

#### 1. OutputProtocol 扩展而非重新设计

当前 OutputProtocol 已有 5 个方法。本 Story 在此基础上扩展，不破坏现有签名：

```swift
// 现有方法（保留不变）
func displayPlan(_ plan: Plan)
func displayStepResult(_ executedStep: ExecutedStep)
func displayStateChange(from oldState: RunState, to newState: RunState)
func displayError(_ error: AxionError)
func displaySummary(context: RunContext)

// 新增方法
func displayRunStart(runId: String, task: String, mode: String)
func displayReplan(attempt: Int, maxRetries: Int, reason: String)
func displayVerificationResult(_ result: VerificationResult)
```

**理由：** RunEngine（Story 3-6）是 OutputProtocol 的主要调用者。在 RunEngine 实现之前，先定义好完整的协议签名，确保 RunEngine 编排循环中每个状态转换点都有对应的输出方法。

#### 2. TraceRecorder 是 Actor

架构文档 D5 决定 TraceRecorder 使用 Actor 隔离。原因：
- JSONL 文件追加写入必须串行化，避免并发写入导致 JSON 行交错
- 多个模块（Planner、Executor、Verifier）可能并发调用 record
- Actor 确保 `~/.axion/runs/{runId}/trace.jsonl` 文件操作的线程安全

```swift
actor TraceRecorder {
    private let fileHandle: FileHandle
    private let encoder: JSONEncoder

    init(runId: String, config: AxionConfig) throws
    func record(event: String, payload: [String: Any] = [:])
    func close()
}
```

**FileHandle 管理要点：**
- init 中创建目录 `~/.axion/runs/`（如果不存在），然后以 append 模式打开文件
- record 方法将 payload 加上 `ts` 和 `event` 字段后序列化为 JSON，追加写入 + 换行
- close 方法刷新并关闭 FileHandle
- Actor deinit 中调用 close

#### 3. JSONOutput 的延迟输出策略

TerminalOutput 是即时输出（每次调用 print），JSONOutput 是延迟输出（累积数据，最后一次性输出完整 JSON）。原因：
- JSON 结构需要完整的开始和结束信息（run_start + run_done）才能构建
- 中间状态变化和步骤结果需要收集到数组中
- `--json` 模式下终端不显示中间进度，只输出最终 JSON

```swift
struct JSONOutput: OutputProtocol {
    private var runId: String?
    private var task: String?
    private var mode: String?
    private var steps: [StepRecord] = []
    private var stateTransitions: [StateTransition] = []
    private var errors: [ErrorRecord] = []
    private var verificationResults: [VerificationResultRecord] = []
    private var startTime: Date?
    private var endTime: Date?

    // OutputProtocol 方法收集数据，不立即输出
    func finalize() -> String  // 序列化为 JSON
}
```

#### 4. RunId 生成策略

Run ID 格式：`YYYYMMDD-{6位随机}`（架构文档 D7）。

```swift
static func generateRunId() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let datePart = formatter.string(from: Date())
    let randomPart = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    return "\(datePart)-\(randomPart)"
}
```

**放在哪里：** 考虑到 RunEngine（Story 3-6）是 RunId 的主要生成者，本 Story 将 `RunId.generate()` 放在 AxionCore/Models/ 或 AxionCLI/Output/ 中。建议放在 `TerminalOutput.swift` 内作为私有工具方法，RunEngine Story 时再决定是否提取到 Core。

### TerminalOutput 格式设计

参考 PRD 旅程一的用户界面期望，终端输出应该是简洁、信息丰富、实时更新的。

```
[axion] 模式: 规划执行（小批量）
[axion] 运行 ID: 20260508-a3f2k1
[axion] 任务: 打开计算器，计算 17 乘以 23
[axion] 规划完成: 3 个步骤
[axion] 步骤 1/3: 启动 Calculator — ok
[axion] 步骤 2/3: 输入表达式 — ok
[axion] 步骤 3/3: 验证结果显示 391 — ok
[axion] 验证: 任务完成
[axion] 完成。3 步，耗时 8.2 秒，重规划 0 次。
```

**格式规则：**
- 每行以 `[axion]` 前缀开头
- 步骤进度：`步骤 {current}/{total}: {purpose} — {status}`
- 状态标记：`ok`（成功）、`x {reason}`（失败）
- 状态转换：`正在{状态描述}...`（如 `正在验证...`、`正在重规划 (2/3)...`）
- 汇总：`完成。{N} 步，耗时 {T} 秒，重规划 {R} 次。`

**关键：不使用 emoji，保持纯 ASCII。** 原因：终端编码兼容性、管道/脚本处理友好。

### JSONOutput 格式设计

```json
{
  "runId": "20260508-a3f2k1",
  "task": "打开计算器，计算 17 乘以 23",
  "mode": "plan_execute",
  "state": "done",
  "steps": [
    {
      "index": 0,
      "tool": "launch_app",
      "purpose": "启动 Calculator",
      "success": true,
      "result": "...",
      "durationMs": 450
    }
  ],
  "verificationResults": [
    {
      "state": "done",
      "reason": "All stop conditions satisfied"
    }
  ],
  "summary": {
    "totalSteps": 3,
    "successfulSteps": 3,
    "failedSteps": 0,
    "durationMs": 8200,
    "replanCount": 0
  }
}
```

### TraceEvent 事件类型

| 事件名 | payload | 触发时机 |
|--------|---------|----------|
| `run_start` | `{runId, task, mode, config}` | RunEngine 启动 |
| `plan_created` | `{steps, stopWhenCount}` | Planner 生成 Plan 后 |
| `step_start` | `{index, tool, purpose}` | 步骤开始执行前 |
| `step_done` | `{index, tool, success, resultSnippet}` | 步骤执行完成后 |
| `state_change` | `{from, to}` | RunState 转换时 |
| `verification_result` | `{state, reason}` | Verifier 返回结果 |
| `replan` | `{attempt, maxRetries, reason}` | 触发重规划 |
| `run_done` | `{totalSteps, durationMs, replanCount}` | 运行完成 |
| `error` | `{error, message}` | 不可恢复错误 |

**Trace 事件 JSON 格式（每行一个）：**
```json
{"ts":"2026-05-10T10:30:00+08:00","event":"step_done","index":0,"tool":"launch_app","success":true,"resultSnippet":"{\"pid\":1234}"}
```

### 现有代码状态（直接复用）

**已完成的依赖：**
- `OutputProtocol`（AxionCore/Protocols/） — 已有 5 个方法签名，本 Story 扩展 3 个新方法
- `RunContext`（AxionCore/Models/） — 包含 currentState, executedSteps, replanCount, config
- `RunState`（AxionCore/Models/） — 9 个状态枚举（planning, executing, verifying, replanning, done, blocked, needsClarification, cancelled, failed）
- `ExecutedStep`（AxionCore/Models/） — stepIndex, tool, parameters, result, success, timestamp
- `Plan` / `Step`（AxionCore/Models/） — plan 结构和步骤模型
- `VerificationResult`（AxionCore/Models/） — state, reason, screenshotBase64, axTreeSnapshot
- `AxionConfig`（AxionCore/Models/） — traceEnabled 标志控制 trace 写入
- `AxionError`（AxionCore/Errors/） — 统一错误类型，有 errorPayload.message
- `ToolNames`（AxionCore/Constants/） — MCP 工具名常量

**空目录已存在：**
- `Sources/AxionCLI/Output/` — 空目录，需要在此创建 TerminalOutput.swift 和 JSONOutput.swift
- `Sources/AxionCLI/Trace/` — 空目录，需要在此创建 TraceRecorder.swift

**Story 3-3/3-4 的实现模式（延续）：**
- StepExecutor 使用 Protocol 注入（MCPClientProtocol），使其可测试
- TerminalOutput/JSONOutput/TraceRecorder 也应通过 Protocol 注入到核心模块
- 注入是可选的（`output: OutputProtocol? = nil`），核心模块无输出也能正常工作

### 如何注入 Output 和 Trace 到现有模块

**方案：不直接修改 StepExecutor/TaskVerifier/LLMPlanner 的构造器签名。** 原因：
- 这些模块在 Story 3-6 的 RunEngine 中被统一编排
- RunEngine 持有 OutputProtocol 和 TraceRecorder 实例
- RunEngine 在编排循环中调用 output 和 trace，不需要核心模块自己调用

**具体方式：**
- RunEngine 在每个关键点调用 output 和 trace：
  1. 调用 planner.createPlan 前后 → `trace.recordPlanCreated` + `output.displayPlan`
  2. 调用 executor.executeStep 前后 → `trace.recordStepStart/StepDone` + `output.displayStepResult`
  3. 调用 verifier.verify 前后 → `trace.recordVerificationResult` + `output.displayVerificationResult`
  4. 状态转换时 → `trace.recordStateChange` + `output.displayStateChange`
  5. 运行完成 → `trace.recordRunDone` + `output.displaySummary`

**因此，本 Story 只需要实现 TerminalOutput、JSONOutput、TraceRecorder 三个独立模块。** 集成到 StepExecutor/TaskVerifier/LLMPlanner 是 RunEngine（Story 3-6）的职责。

**但 Task 5（集成到现有模块）需要做轻量级集成：** 为现有模块添加可选的 output/trace 回调，以便 Story 3-6 可以平滑接入。这通过闭包注入实现：

```swift
// StepExecutor 添加可选回调
public struct StepExecutor: ExecutorProtocol {
    // 现有属性不变
    public var onStepStart: ((Step) -> Void)?
    public var onStepDone: ((ExecutedStep) -> Void)?
    // ...
}
```

### TraceRecorder 的 Actor 隔离

```swift
actor TraceRecorder {
    private var fileHandle: FileHandle?
    private let encoder: JSONEncoder
    private let runId: String
    private let enabled: Bool

    init(runId: String, config: AxionConfig) throws {
        self.runId = runId
        self.enabled = config.traceEnabled
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        if enabled {
            let runsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".axion/runs")
            try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
            let fileURL = runsDir.appendingPathComponent("\(runId)/trace.jsonl")
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // 创建或追加文件
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
            try fileHandle?.seekToEnd()
        }
    }

    func record(event: String, payload: [String: Any] = [:]) {
        guard enabled, let handle = fileHandle else { return }
        var record = payload
        record["ts"] = ISO8601DateFormatter().string(from: Date())
        record["event"] = event
        // 序列化为 JSON
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              var jsonLine = String(data: data, encoding: .utf8) else { return }
        jsonLine.append("\n")
        guard let lineData = jsonLine.data(using: .utf8) else { return }
        handle.write(lineData)
    }

    func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    deinit {
        try? fileHandle?.close()
    }
}
```

**注意 JSONSerialization 而非 Codable：** trace payload 是 `[String: Any]` 字典，字段类型不确定。使用 JSONSerialization 比 Codable 更灵活。

### 模块依赖规则

```
TerminalOutput.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — OutputProtocol, Plan, Step, RunState, ExecutedStep, RunContext, AxionError, VerificationResult)

JSONOutput.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — 同上)

TraceRecorder.swift 可以 import:
  - Foundation (系统)
  - AxionCore (项目内部 — AxionConfig)

禁止 import:
  - AxionHelper (进程隔离)
  - OpenAgentSDK (Output/Trace 不需要 SDK Agent)
  - MCP (不直接使用 MCP 底层 API)
```

### import 顺序

```swift
// TerminalOutput.swift / JSONOutput.swift
import Foundation

import AxionCore

// TraceRecorder.swift
import Foundation

import AxionCore
```

### 目录结构

```
Sources/AxionCLI/Output/
  TerminalOutput.swift              # 新建：终端实时输出
  JSONOutput.swift                  # 新建：JSON 结构化输出

Sources/AxionCLI/Trace/
  TraceRecorder.swift               # 新建：JSONL trace 记录器

Sources/AxionCore/Protocols/
  OutputProtocol.swift              # 修改：扩展 3 个新方法

Tests/AxionCLITests/Output/
  TerminalOutputTests.swift         # 新建：终端输出测试
  JSONOutputTests.swift             # 新建：JSON 输出测试

Tests/AxionCLITests/Trace/
  TraceRecorderTests.swift          # 新建：Trace 记录器测试

Tests/AxionCoreTests/
  OutputProtocolTests.swift         # 新建：协议签名测试
```

### 测试策略

**TerminalOutput 测试：**

TerminalOutput 使用 `print()` 输出到 stdout。测试策略：
1. 替换底层输出方法 — 让 TerminalOutput 通过注入的 `write: (String) -> Void` 闭包输出，默认为 `print`
2. 测试时注入捕获闭包，验证输出字符串格式

```swift
struct TerminalOutput: OutputProtocol {
    private let write: (String) -> Void

    init(write: @escaping (String) -> Void = { print($0) }) {
        self.write = write
    }
    // ...
}
```

**JSONOutput 测试：**

JSONOutput 的 `finalize()` 返回 JSON 字符串。直接验证 JSON 结构：
- 反序列化 JSON
- 验证顶层字段（runId, task, state, steps, summary）
- 验证 steps 数组长度和内容
- 验证 summary 计算正确

**TraceRecorder 测试：**

TraceRecorder 是 Actor，测试需要 `await`：
- 创建临时目录替代 `~/.axion/runs/`
- 注入自定义 `AxionConfig(traceEnabled: true)`
- 写入多条记录后验证文件内容
- 验证每行是合法 JSON，包含 `ts` 和 `event` 字段
- 验证 `traceEnabled: false` 时不写入文件

**关键测试用例：**
- `test_terminalOutput_runStart_displaysRunIdAndTask` — 运行启动信息格式
- `test_terminalOutput_stepResult_displaysProgress` — 步骤进度格式
- `test_terminalOutput_summary_displaysStats` — 汇总信息格式
- `test_jsonOutput_finalize_producesValidJSON` — JSON 结构完整性
- `test_jsonOutput_stepsArray_reflectsExecutedSteps` — steps 数组正确
- `test_traceRecorder_createsDirectoryAndFile` — 目录和文件自动创建
- `test_traceRecorder_eventsHaveTimestampAndEventField` — JSONL 格式正确
- `test_traceRecorder_disabled_doesNotWrite` — traceEnabled=false 不写入
- `test_traceRecorder_multipleRecords_allWritten` — 多条记录全部写入
- `test_traceRecorder_close_flushesData` — close 后数据持久化

### TerminalOutput 的具体格式化方法

**displayRunStart：**
```
[axion] 模式: 规划执行（小批量）
[axion] 运行 ID: 20260508-a3f2k1
[axion] 任务: 打开计算器，计算 17 乘以 23
```

**displayPlan：**
```
[axion] 规划完成: 3 个步骤
```

**displayStepResult（执行中）：**
```
[axion] 步骤 1/3: 启动 Calculator — ok
[axion] 步骤 2/3: 输入表达式 — x 应用未找到
```

注意：displayStepResult 需要知道步骤总数（Plan.steps.count）才能显示 `1/3` 格式。方法签名中 ExecutedStep 只包含 stepIndex，不包含总数。

**解决方案：** 在 TerminalOutput 中维护一个 `planStepsCount` 属性，由 `displayPlan` 设置。或者扩展 displayStepResult 方法签名，添加 `totalSteps: Int` 参数。推荐后者，更清晰：

```swift
func displayStepResult(_ executedStep: ExecutedStep, totalSteps: Int)
```

**但 OutputProtocol 当前签名是 `func displayStepResult(_ executedStep: ExecutedStep)`。** 不修改现有签名（RunEngine Story 中调用），改为 TerminalOutput 内部维护状态：

```swift
struct TerminalOutput: OutputProtocol {
    private var planStepsCount: Int = 0

    func displayPlan(_ plan: Plan) {
        planStepsCount = plan.steps.count
        write("[axion] 规划完成: \(plan.steps.count) 个步骤")
    }

    func displayStepResult(_ executedStep: ExecutedStep) {
        let total = planStepsCount > 0 ? planStepsCount : "?"
        let status = executedStep.success ? "ok" : "x \(executedStep.result)"
        write("[axion] 步骤 \(executedStep.stepIndex + 1)/\(total): {purpose} — \(status)")
    }
}
```

**问题：ExecutedStep 不包含 purpose。** purpose 在 Plan.Step 中。TerminalOutput 无法直接获取。

**解决方案：** displayStepResult 只显示工具名（ExecutedStep 有 tool 字段），不显示 purpose。RunEngine 可以在调用 displayStepResult 之前/之后额外调用 displayStepStart 来显示 purpose：

```swift
// OutputProtocol 新增（可选，给 RunEngine 使用）
func displayStepStart(stepIndex: Int, totalSteps: Int, tool: String, purpose: String)
```

**简化方案（推荐）：** 让 OutputProtocol.displayStepResult 接受额外的可选参数：

```swift
// 保持向后兼容，添加默认值
func displayStepResult(_ executedStep: ExecutedStep, totalSteps: Int = 0, purpose: String? = nil)
```

这样 RunEngine 可以传入完整信息，而协议默认实现（如果有的话）也能工作。

**最终决策：** 在 OutputProtocol 中保持原始 5 个方法签名不变，新增扩展方法。TerminalOutput 内部用 `planStepsCount` 状态来推断 totalSteps。purpose 暂不在步骤结果中显示（只显示工具名和状态）。RunEngine Story 可以进一步优化输出格式。

### 与前后 Story 的关系

- **Story 3-4（已完成）**：TaskVerifier 产生 VerificationResult。本 Story 的 `displayVerificationResult` 消费 VerificationResult 来显示验证结果。TraceRecorder 记录 verification_result 事件。
- **Story 3-3（已完成）**：StepExecutor 产生 ExecutedStep。本 Story 的 `displayStepResult` 消费 ExecutedStep。TraceRecorder 记录 step_start/step_done 事件。
- **Story 3-2（已完成）**：LLMPlanner 产生 Plan。本 Story 的 `displayPlan` 消费 Plan。TraceRecorder 记录 plan_created 事件。
- **Story 3-6（下一个）**：RunEngine 是 OutputProtocol 和 TraceRecorder 的主要消费者。RunEngine 持有这两个实例，在编排循环的每个关键点调用它们。RunEngine 负责创建 TraceRecorder（传入 runId 和 config），并根据 `--json` 标志选择 TerminalOutput 或 JSONOutput。
- **Story 3-7**：SDK 集成时，SDK 的 Streaming（AsyncStream<SDKMessage>）管道可能替代或增强 TerminalOutput。本 Story 的 OutputProtocol 抽象层为未来 SDK 流式输出预留了扩展空间。

### OpenClick 参考映射

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `TerminalOutput.swift` | `src/run.ts`（console.log 输出） | 终端输出格式：步骤进度、汇总信息 |
| `TraceRecorder.swift` | 无直接对应 | Axion 独创 — OpenClick 没有 JSONL trace 文件 |

**注意：** OpenClick 的输出逻辑分散在 `src/run.ts` 的循环体中（`console.log` 调用）。Axion 将输出抽象为 OutputProtocol，是更好的架构设计。参考 OpenClick 的输出文案风格，但不照搬其实现方式。

### 禁止事项（反模式）

- **不得创建新的错误类型** — 使用 `AxionError` 枚举
- **TerminalOutput 不得直接使用 `print()`** — 必须通过注入的 `write` 闭包，使其可测试
- **JSONOutput 不得在运行过程中输出** — 必须在 finalize() 时一次性输出
- **TraceRecorder 不得使用 FileManager.default.currentDirectoryPath** — trace 路径必须使用 `~/.axion/runs/` 绝对路径
- **TraceRecorder 的 record 方法不得抛出异常** — trace 写入失败不应中断任务执行，静默忽略
- **不得在 OutputProtocol 中添加不适用于 JSONOutput 的方法** — 两个实现必须共享同一协议
- **TraceRecorder 不得 import AxionHelper 或 OpenAgentSDK** — 纯文件 I/O 模块

### 检查清单合规

- [x] 故事声明：As a / I want / so that 格式
- [x] 验收标准：Given/When/Then BDD 格式
- [x] 任务分解：可执行的子任务，关联 AC
- [x] 开发者注记：架构决策、模式约束、反模式
- [x] 项目结构注记：文件位置、依赖规则、import 顺序
- [x] 参考：所有源文档引用
- [x] 测试策略：Mock 方式、关键测试用例

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.5] 原始 Story 定义和 AC
- [Source: _bmad-output/planning-artifacts/architecture.md#D5] 并发模型（Actor 隔离 TraceRecorder）
- [Source: _bmad-output/planning-artifacts/architecture.md#D7] Trace 记录格式（JSONL）
- [Source: _bmad-output/planning-artifacts/architecture.md#D8] Helper 进程生命周期（trace 记录进程事件）
- [Source: _bmad-output/planning-artifacts/architecture.md#FR33-FR35] 进度反馈功能需求
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR15] 实时进度更新要求
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR20] Trace 文件可调试要求
- [Source: _bmad-output/project-context.md#数据流] 完整数据流链路（TerminalOutput.display + TraceRecorder.record 阶段）
- [Source: _bmad-output/project-context.md#Trace记录] JSONL 格式规范、Run ID 格式
- [Source: _bmad-output/project-context.md#日志级别] 日志级别定义
- [Source: _bmad-output/project-context.md#安全规则] API Key 不出现在 trace 中
- [Source: _bmad-output/implementation-artifacts/stories/3-4-task-verification-stop-condition.md] 前序 Story（TaskVerifier 实现）
- [Source: Sources/AxionCore/Protocols/OutputProtocol.swift] 当前 OutputProtocol 接口（需扩展）
- [Source: Sources/AxionCore/Models/RunContext.swift] RunContext 结构体
- [Source: Sources/AxionCore/Models/RunState.swift] RunState 枚举
- [Source: Sources/AxionCore/Models/ExecutedStep.swift] ExecutedStep 结构体
- [Source: Sources/AxionCore/Models/VerificationResult.swift] VerificationResult 结构体
- [Source: Sources/AxionCore/Models/Plan.swift] Plan 结构体
- [Source: Sources/AxionCore/Models/AxionConfig.swift] AxionConfig 配置模型（traceEnabled 字段）
- [Source: Sources/AxionCore/Errors/AxionError.swift] 统一错误类型
- [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Examples/StreamingAgent/main.swift] SDK 流式输出 AsyncStream<SDKMessage> 使用模式

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- TraceRecorder apiKey sanitization test required payload value sanitization (not just key removal)
- TerminalOutput/JSONOutput changed from struct to class to support mutable state through protocol methods
- OutputProtocol needed `public` access modifier for cross-module visibility (AxionCore -> AxionCLI)
- ATDD test `test_terminalOutput_noEmojiInOutput` used `CharacterSets` (plural) -- corrected to emoji-range check

### Completion Notes List

- All 7 tasks completed. 460 unit tests pass (0 failures, 0 regressions).
- TerminalOutput: class with injectable write closure for testability. Outputs [axion]-prefixed Chinese text with step progress, status markers (ok/x), and summary.
- JSONOutput: class that accumulates data through OutputProtocol methods, produces final JSON via finalize(). Includes steps, stateTransitions, errors, verificationResults, summary.
- TraceRecorder: actor with JSONL file writing, API key sanitization in payload values, 8 convenience methods for all event types.
- OutputProtocol: extended with 3 new methods (displayRunStart, displayReplan, displayVerificationResult), 5 existing methods preserved unchanged.
- Integration: StepExecutor (onStepStart/onStepDone callbacks), TaskVerifier (onVerificationResult callback), LLMPlanner (onPlanCreated callback).
- Trace directory auto-created on first write via FileManager.createDirectory(withIntermediateDirectories:).

### File List

#### New Files
- Sources/AxionCLI/Output/TerminalOutput.swift
- Sources/AxionCLI/Output/JSONOutput.swift
- Sources/AxionCLI/Trace/TraceRecorder.swift

#### Modified Files
- Sources/AxionCore/Protocols/OutputProtocol.swift (added public modifier + 3 new methods)
- Sources/AxionCLI/Executor/StepExecutor.swift (added onStepStart/onStepDone callbacks)
- Sources/AxionCLI/Verifier/TaskVerifier.swift (added onVerificationResult callback)
- Sources/AxionCLI/Planner/LLMPlanner.swift (added onPlanCreated callback)
- Tests/AxionCLITests/Output/TerminalOutputTests.swift (fixed CharacterSets -> emoji range check)

#### Existing Test Files (ATDD, pre-created)
- Tests/AxionCoreTests/OutputProtocolTests.swift
- Tests/AxionCLITests/Output/TerminalOutputTests.swift
- Tests/AxionCLITests/Output/JSONOutputTests.swift
- Tests/AxionCLITests/Trace/TraceRecorderTests.swift

### Change Log

- 2026-05-10: Story 3-5 implementation complete. Added TerminalOutput, JSONOutput, TraceRecorder, extended OutputProtocol, integrated callbacks into StepExecutor/TaskVerifier/LLMPlanner. All 460 unit tests pass.
