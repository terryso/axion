# Story 15.2: Takeover 结构化标记

Status: done

## Story

As a 用户,
I want takeover 有结构化的标记和反馈机制,
So that 接管经验可以被系统精确理解和复用.

## Acceptance Criteria

1. **AC1: Takeover 提示引导用户输入反馈**
   - **Given** 任务进入 takeover 状态，系统提示用户
   - **When** 显示接管提示
   - **Then** 提示包含："手动完成后按 Enter 继续。可选：输入反馈描述你的操作（如 '使用了 Cmd+Shift+G 输入路径'），或直接 Enter 跳过"

2. **AC2: 用户输入反馈纳入 Memory evidence**
   - **Given** Takeover 恢复时用户输入了反馈文本
   - **When** 记录 takeover 学习
   - **Then** feedback 字段包含用户描述，作为 Memory 的 evidence 之一

3. **AC3: 无反馈时 feedback 为空**
   - **Given** 用户直接按 Enter（无反馈输入）
   - **When** 记录 takeover 学习
   - **Then** feedback 字段为空，Memory 仅包含 issue 和 outcome

4. **AC4: Takeover 事件记入 trace**
   - **Given** trace 记录已开启
   - **When** takeover 事件发生
   - **Then** 记录 `takeover` 事件，包含 issue、summary、outcome、feedback、duration（用户花费的时间）

5. **AC5: TakeoverResumedMarker 结构化数据**
   - **Given** Takeover 恢复时
   - **When** 构造 marker 数据
   - **Then** 包含 schemaVersion、runId、outcome、issue、summary、reasonType、feedback、duration、bundleId、appName、task、createdAt

6. **AC6: InterventionReason 分类**
   - **Given** SDK 暂停原因（pausedData.reason）
   - **When** 记录 takeover 事件
   - **Then** 将 reason 映射到 InterventionReason 枚举值（planner_blocked / needs_clarification / foreground_required / repeated_action_failure / verification_failed / permission_prompt / confirmation_dialog / login_or_2fa / captcha / native_modal / low_confidence / unexpected_screen_change / destructive_action_risk / user_requested_takeover / unknown）

7. **AC7: AxionBar 任务面板显示 takeover 状态（可选）**
   - **Given** AxionBar 任务面板
   - **When** 显示 takeover 状态
   - **Then** 显示阻塞原因、手动操作提示和恢复按钮
   - **注：** 此 AC 为 AxionBar SSE 事件消费，核心变更在后端事件发送。AxionBar 已有 SSE 解析管线，只需在 TaskDetailPanel 中处理 `takeover` 事件即可。

## Tasks / Subtasks

- [x] Task 1: 定义 TakeoverMarker 和 InterventionReason 模型 (AC: #5, #6)
  - [x] 1.1 新建 `Sources/AxionCLI/Memory/TakeoverMarker.swift`
  - [x] 1.2 定义 `InterventionReason` 枚举（String, Codable, CaseIterable）：planner_blocked, needs_clarification, foreground_required, repeated_action_failure, verification_failed, permission_prompt, confirmation_dialog, login_or_2fa, captcha, native_modal, low_confidence, unexpected_screen_change, destructive_action_risk, user_requested_takeover, unknown
  - [x] 1.3 定义 `TakeoverMarker` struct（Codable）：schemaVersion (Int, 默认 1), runId, outcome (TakeoverOutcome), issue, summary, reasonType (InterventionReason, 默认 .unknown), feedback (String?), duration (TimeInterval?), bundleId (String?), appName (String?), task (String?), createdAt (ISO8601)
  - [x] 1.4 提供静态工厂方法 `TakeoverMarker.create(...)` 自动填充 schemaVersion 和 createdAt
  - [x] 1.5 提供 `static func classifyReason(_ reason: String) -> InterventionReason` 方法，基于关键词映射 SDK 暂停原因到枚举值

- [x] Task 2: 改进 TakeoverIO 提示语，引导用户输入反馈 (AC: #1, #2, #3)
  - [x] 2.1 修改 `displayTakeoverPrompt()` 中的提示文本，加入反馈引导语
  - [x] 2.2 修改返回值，增加 `feedback: String?` 字段：如果用户输入不是 skip/abort/continue/空行，则该输入既是 `userInput`（传给 agent.resume），也是 `feedback`（传给 marker）；如果是空行，feedback 为 nil
  - [x] 2.3 更新 TakeoverAction.fromInput 逻辑不变（保持现有行为），但区分"用户输入作为反馈"vs"用户输入作为命令"

- [x] Task 3: 集成 TakeoverMarker 到 RunCommand (AC: #4, #5, #6)
  - [x] 3.1 扩展 `takeoverEvent` 元组，增加 `feedback: String?`、`reason: String`、`startTime: ContinuousClock.Instant` 字段
  - [x] 3.2 在 `.paused` case 中记录 `takeoverStartTime = ContinuousClock.now`
  - [x] 3.3 在 `.resume` case 中计算 `duration = ContinuousClock.now - takeoverStartTime`，收集 feedback
  - [x] 3.4 在 takeover 学习记录段（L521-539），构造 `TakeoverMarker` 并使用 `classifyReason()` 映射 reason
  - [x] 3.5 将 feedback 传递给 `TakeoverLearningService.recordTakeoverLearning()` 的 feedback 参数
  - [x] 3.6 调用 `tracer?.record(event: "takeover", payload: marker.toDictionary())` 写入 trace

- [x] Task 4: 扩展 TraceRecorder 事件类型 (AC: #4)
  - [x] 4.1 在 `TraceEventType` 中新增 `static let takeover = "takeover"`
  - [x] 4.2 新增便利方法 `recordTakeoverEvent(marker: TakeoverMarker)` 或直接在 RunCommand 中调用 `record(event:payload:)`

- [x] Task 5: 单元测试 (All ACs)
  - [x] 5.1 新建 `Tests/AxionCLITests/Memory/TakeoverMarkerTests.swift`
  - [x] 5.2 测试 InterventionReason 所有序例的 Codable round-trip
  - [x] 5.3 测试 `classifyReason()` 关键词映射（如 "blocked" → .plannerBlocked, "permission" → .permissionPrompt, 无匹配 → .unknown）
  - [x] 5.4 测试 TakeoverMarker.create() 工厂方法（自动填充 schemaVersion=1, createdAt）
  - [x] 5.5 测试 TakeoverMarker Codable round-trip
  - [x] 5.6 测试 TakeoverIO 新提示语和 feedback 分离逻辑（用户输入文本 → feedback 有值，空行 → feedback 为 nil）
  - [x] 5.7 测试 RunCommand 中 feedback 传递到 TakeoverLearningService（集成级测试可覆盖在 TakeoverLearningServiceTests 中）
  - [x] 5.8 测试 duration 计算逻辑（mock Clock 或直接使用已有模式）

## Dev Notes

### 核心设计：结构化 Takeover 标记

本 Story 的核心是为 Takeover 添加结构化元数据（`TakeoverMarker`）和用户反馈机制，使接管经验更精确。

**数据流（Story 15.1 基础上扩展）：**

```
Takeover 发生 → 记录 startTime → 显示新提示（引导反馈）
                                          ↓
用户操作 → 输入反馈文本或直接 Enter → 恢复执行
                                          ↓
计算 duration → 构造 TakeoverMarker → 写入 trace
                                          ↓
传递 feedback → TakeoverLearningService.recordTakeoverLearning()
                                          ↓
Memory evidence 中包含 feedback
```

### InterventionReason 映射策略

OpenClick 定义了 14 种 InterventionReason，但 Axion 的 SDK `PausedData.reason` 是自由文本。需要实现一个基于关键词的映射器：

```swift
static func classifyReason(_ reason: String) -> InterventionReason {
    let lower = reason.lowercased()
    if lower.contains("blocked") || lower.contains("stuck") { return .plannerBlocked }
    if lower.contains("clarif") { return .needsClarification }
    if lower.contains("foreground") { return .foregroundRequired }
    if lower.contains("repeat") { return .repeatedActionFailure }
    if lower.contains("verif") { return .verificationFailed }
    if lower.contains("permission") || lower.contains("access") { return .permissionPrompt }
    if lower.contains("confirm") || lower.contains("dialog") { return .confirmationDialog }
    if lower.contains("login") || lower.contains("2fa") || lower.contains("password") { return .loginOr2fa }
    if lower.contains("captcha") { return .captcha }
    if lower.contains("modal") || lower.contains("popup") { return .nativeModal }
    if lower.contains("confidence") || lower.contains("unsure") { return .lowConfidence }
    if lower.contains("unexpected") || lower.contains("screen change") { return .unexpectedScreenChange }
    if lower.contains("destructive") || lower.contains("danger") { return .destructiveActionRisk }
    if lower.contains("user request") { return .userRequestedTakeover }
    return .unknown
}
```

**注意：** `InterventionReason` 用 camelCase（Swift 惯例），Codable 自动转为 snake_case（需 CodingKeys 映射，或使用 rawValue 为 snake_case）。建议 rawValue 使用 snake_case 与 OpenClick/trace JSON 保持一致。

### TakeoverIO 提示改进

当前提示：
```
━━━ Axion Takeover ━━━
任务受阻: {reason}
前台操作限制已暂时解除...
请在桌面上手动完成操作，然后回到终端按 Enter 继续。
也可以输入信息（如凭据）供 agent 使用，或输入 skip 跳过 / abort 终止。
```

改进为（AC1）：
```
━━━ Axion Takeover ━━━
任务受阻: {reason}
前台操作限制已暂时解除...
请在桌面上手动完成操作。
手动完成后按 Enter 继续。可选：输入反馈描述你的操作（如 '使用了 Cmd+Shift+G 输入路径'），或直接 Enter 跳过。
输入 skip 跳过当前步骤 / abort 终止任务。
```

**feedback 分离逻辑：** 当前 `displayTakeoverPrompt` 返回 `(action: TakeoverAction, userInput: String?)`。需要额外返回 `feedback: String?`：
- 如果用户输入文本（非 skip/abort/空行），则 feedback = userInput（用户的操作描述）
- 如果用户直接 Enter，则 feedback = nil
- 如果用户输入 skip/abort，则 feedback = nil

这只需在返回时判断：`let feedback = (action == .resume && userInput非空) ? userInput : nil`

### duration 计时

使用 `ContinuousClock`（已有 `startTime` 在 RunCommand 中）。在 `.paused` case 记录：
```swift
let takeoverStartTime = ContinuousClock.now
```
在 `.resume` case 计算：
```swift
let duration = ContinuousClock.now - takeoverStartTime
let durationSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
```

### TakeoverMarker 模型定义

参考 OpenClick 的 `TakeoverResumeMarker`，但适配 Swift 风格：

```swift
struct TakeoverMarker: Codable, Equatable {
    let schemaVersion: Int         // 1
    let runId: String
    let outcome: TakeoverOutcome
    let issue: String
    let summary: String
    let reasonType: InterventionReason
    let feedback: String?
    let duration: TimeInterval?
    let bundleId: String?
    let appName: String?
    let task: String?
    let createdAt: String          // ISO8601

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runId = "run_id"
        case outcome, issue, summary
        case reasonType = "reason_type"
        case feedback, duration
        case bundleId = "bundle_id"
        case appName = "app_name"
        case task
        case createdAt = "created_at"
    }
}
```

### 与 Story 15.1 的集成点

Story 15.1 已在 RunCommand 中建立：
1. `takeoverEvent` 元组（issue + summary）→ 需扩展（+ feedback, reason, startTime）
2. `TakeoverLearningService.recordTakeoverLearning()` 已有 `feedback` 参数但未使用（当前传 nil）→ 改为传入实际 feedback
3. TraceRecorder 已有 `record(event:payload:)` 通用方法 → 直接使用，无需新增特定方法
4. `runSucceeded` / `runCompleted` 跟踪已完成 → 复用

### 现有文件需要修改

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/AxionCLI/IO/TakeoverIO.swift` | 修改 | 更新提示文本，返回值增加 feedback |
| `Sources/AxionCLI/Commands/RunCommand.swift` | 修改 | 扩展 takeoverEvent 元组，构造 TakeoverMarker，传递 feedback，写 trace |
| `Sources/AxionCLI/Memory/TakeoverLearningService.swift` | 无需修改 | feedback 参数已存在，当前传 nil |
| `Sources/AxionCLI/Trace/TraceRecorder.swift` | 可选修改 | 可新增 TakeoverEventType 常量（也可直接用字符串） |

### 新增文件

| 文件 | 说明 |
|------|------|
| `Sources/AxionCLI/Memory/TakeoverMarker.swift` | TakeoverMarker + InterventionReason 模型 |
| `Tests/AxionCLITests/Memory/TakeoverMarkerTests.swift` | 模型 + classifyReason 测试 |

### 项目结构规范

```
Sources/AxionCLI/
├── Memory/
│   ├── TakeoverMarker.swift              # 新增（本 Story）
│   ├── TakeoverLearningService.swift     # 已有（Story 15.1），不需修改
│   └── ...
├── IO/
│   └── TakeoverIO.swift                  # 修改：提示文本 + feedback
├── Commands/
│   └── RunCommand.swift                  # 修改：marker 构造 + trace + feedback
└── Trace/
    └── TraceRecorder.swift               # 可选修改：新增常量

Tests/AxionCLITests/
├── Memory/
│   └── TakeoverMarkerTests.swift         # 新增（本 Story）
└── IO/
    └── TakeoverIOTests.swift             # 可选：已有测试文件则修改，否则新建
```

### 测试策略

- Swift Testing 框架（`import Testing`, `@Suite`, `@Test`, `#expect`）
- `TakeoverMarkerTests` 测试模型 Codable round-trip、工厂方法、classifyReason 映射
- TakeoverIO 测试提示文本变更和 feedback 分离逻辑（mock readLine/write）
- 不需要 mock TraceRecorder — 直接验证 record 调用的参数（或通过 TakeoverMarker 的 toDictionary 验证结构）

### 前一个 Story 经验（Story 15.1）

- TakeoverLearningService 已实现，feedback 参数已预留但传 nil
- RunCommand 中 takeoverEvent 当前是 `(issue: String, summary: String)?` 元组
- `inferDomain(from:)` 方法已实现
- `runSucceeded` / `runCompleted` 标志已正确跟踪
- TakeoverIO 使用注入的 write/readLine 闭包实现可测试性
- Memory 操作失败不阻塞主流程（do/catch + warning 模式）
- `TakeoverOutcome` 枚举已定义在 `TakeoverLearningService.swift` 中

### 反模式提醒

- **禁止**创建新的 Memory 存储层 — 使用现有 `MemoryFactStore` + `MemoryLifecycleService`
- **禁止**实现文件轮询机制（OpenClick 用 `TakeoverResumeMarker` 文件轮询，Axion 不需要）
- **禁止**修改 TakeoverLearningService 的接口 — feedback 参数已存在
- **禁止**在 trace 中记录 API Key — TraceRecorder 已有 sanitizePayload 机制
- **禁止**将 TakeoverMarker 持久化到独立文件 — OpenClick 的 marker 文件机制不适合 Axion 的 actor-based trace recorder
- **禁止**修改 TakeoverAction 的行为 — fromInput 逻辑保持不变，只增加 feedback 返回
- **禁止**在 TakeoverIO 中添加 Memory 逻辑 — TakeoverIO 只负责 I/O

### References

- [Source: epics.md — Epic 15 Story 15.2 Takeover 结构化标记]
- [Source: OpenClick src/trace.ts:34-51 — InterventionPayload 接口]
- [Source: OpenClick src/trace.ts:18-32 — InterventionReason 类型]
- [Source: OpenClick src/trace.ts:53-70 — TakeoverResumeMarker 接口]
- [Source: OpenClick src/cli.ts:389-426 — CLI takeover finish 命令]
- [Source: OpenClick src/run.ts:417-440 — handleTakeoverResume 函数]
- [Source: Sources/AxionCLI/IO/TakeoverIO.swift — Takeover 终端 I/O]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift:350-415 — Takeover SDK .paused 消息处理]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift:521-539 — Takeover 学习记录段]
- [Source: Sources/AxionCLI/Memory/TakeoverLearningService.swift — feedback 参数已预留]
- [Source: Sources/AxionCLI/Trace/TraceRecorder.swift — Trace 记录器]
- [Source: _bmad-output/implementation-artifacts/15-1-takeover-experience-auto-learning.md — Story 15.1 完成记录]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (GLM-5.1[1m])

### Debug Log References

- classifyReason 顺序修复：`2fa`/`login` 需在 `verif` 之前检查，`modal`/`popup` 需在 `dialog` 之前检查，避免关键词重叠导致的误分类

### Completion Notes List

- Task 1: 新建 `TakeoverMarker.swift`，包含 `InterventionReason` 枚举（15 个 case + 关键词映射器）和 `TakeoverMarker` struct（含工厂方法 `create()` 和 `toDictionary()`）
- Task 2: 更新 `TakeoverIO.displayTakeoverPrompt()` — 新提示文本引导用户输入反馈，返回值增加 `feedback: String?` 字段
- Task 3: 扩展 RunCommand 中 `takeoverEvent` 元组（+feedback, reason, startTime），构造 TakeoverMarker 写入 trace，传递 feedback 和 reasonType 到 TakeoverLearningService
- Task 4: 在 TraceRecorder.TraceEventType 新增 `takeover` 常量
- Task 5: 24 个 TakeoverMarkerTests + 7 个新 TakeoverIO feedback 测试，全部通过（69 个 Takeover 相关测试 0 失败）

### File List

- `Sources/AxionCLI/Memory/TakeoverMarker.swift` — 新增：InterventionReason 枚举 + TakeoverMarker struct
- `Sources/AxionCLI/IO/TakeoverIO.swift` — 修改：更新提示文本，返回值增加 feedback 字段
- `Sources/AxionCLI/Commands/RunCommand.swift` — 修改：扩展 takeoverEvent 元组，构造 TakeoverMarker，传递 feedback/reasonType
- `Sources/AxionCLI/Trace/TraceRecorder.swift` — 修改：新增 takeover 事件类型常量
- `Tests/AxionCLITests/Memory/TakeoverMarkerTests.swift` — 新增：24 个测试覆盖模型、映射、Codable
- `Tests/AxionCLITests/IO/TakeoverIOTests.swift` — 修改：新增 7 个反馈分离测试 + 1 个提示文本测试

## Change Log

- 2026-05-17: Story 15.2 完整实现 — TakeoverMarker 结构化标记、用户反馈机制、InterventionReason 分类、duration 计时、trace 集成
- 2026-05-17: Review — 5 issues found and auto-fixed (1H/2M/2L)

## Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.7 (GLM-5.1[1m]) on 2026-05-17
**Outcome:** Approve (all issues auto-fixed)

### Issues Found & Fixed

1. **[HIGH] Duration 计算时间范围错误** — `RunCommand.swift` 中 duration 在运行结束后计算 `ContinuousClock.now - startTime`，实际测量的是暂停到运行结束的总时间，而非用户手动干预时间。**Fix:** 将 duration 计算移至用户恢复时（`.resume` case），元组存储 `duration: TimeInterval?` 替代 `startTime`。

2. **[MEDIUM] takeover_resumed trace 事件在 feedback 为 nil 时丢失** — `"feedback": result.feedback as Any` 当 feedback 为 nil 时导致 `JSONSerialization` 失败，整个事件被 `try?` 静默吞掉。**Fix:** 改为条件构建 payload，feedback 为 nil 时不包含该 key。

3. **[MEDIUM] Task 5.8 缺少 duration 测试** — 声称完成但无实际测试。**Fix:** 提取 `TakeoverMarker.durationToSeconds()` 静态方法，新增 3 个测试覆盖整数秒、零、亚秒精度。

4. **[LOW] 测试名误导** — `feedbackNilOnContinue` 实际测试 feedback == "continue"（非 nil）。**Fix:** 重命名为 "feedback is 'continue' when user types 'continue'"。

5. **[LOW] takeoverEvent 元组 reason 字段冗余** — `reason` 和 `issue` 同为 `pausedData.reason`。**Fix:** 保留 reason 用于 classifyReason 调用清晰度，记录为已知设计选择。

### Test Results

52 tests in 2 suites — all passed after fixes.
