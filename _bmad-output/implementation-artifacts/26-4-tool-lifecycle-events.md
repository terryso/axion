# Story 26.4: Tool Lifecycle Events

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a SDK 开发者,
I want 定义 tool 执行生命周期事件类型,
So that 上层可以追踪每个 tool 调用的开始、输出、完成、失败.

## Acceptance Criteria

1. **AC1: ToolStartedEvent 定义**
   - Given `ToolStartedEvent` 被构造
   - When 检查其 payload
   - Then 包含 `sessionId: String?`、`toolName: String`、`toolUseId: String`、`input: String?`
   - And 遵循 `AgentEvent` protocol（通过组合 `base: BaseAgentEvent`）

2. **AC2: ToolStreamingEvent 定义**
   - Given `ToolStreamingEvent` 被构造
   - When 检查其 payload
   - Then 包含 `sessionId: String?`、`toolUseId: String`、`chunk: String`

3. **AC3: ToolCompletedEvent 定义**
   - Given `ToolCompletedEvent` 被构造
   - When 检查其 payload
   - Then 包含 `sessionId: String?`、`toolUseId: String`、`toolName: String`、`durationMs: Int`、`isError: Bool`

4. **AC4: ToolFailedEvent 定义**
   - Given `ToolFailedEvent` 被构造
   - When 检查其 payload
   - Then 包含 `sessionId: String?`、`toolUseId: String`、`toolName: String`、`error: String`

5. **AC5: 类型约束**
   - All 4 event types 为 `struct`（value type）
   - All 4 event types 遵循 `Sendable`
   - All 4 event types 遵循 `Codable`（protocol 继承要求）
   - All payload 字段为 `let`（不可变）

6. **AC6: 不改现有 API**
   - 不修改 `AgentEvent`、`BaseAgentEvent`、`AgentEventCategory`、`SessionFinalStatus` 或任何现有类型
   - 纯追加到 `AgentEventTypes.swift`

## Tasks / Subtasks

- [x] Task 1: 定义 ToolStartedEvent (AC: #1)
  - [x] 1.1 创建 struct，组合 `base: BaseAgentEvent`，payload: `sessionId: String?`, `toolName: String`, `toolUseId: String`, `input: String?`
  - [x] 1.2 实现 `AgentEvent` protocol（`id`/`timestamp` 转发到 `base`）
  - [x] 1.3 添加 `CodingKeys` 用 snake_case 映射 JSON 字段
  - [x] 1.4 实现显式 `init(from:)` 和 `encode(to:)`（扁平 JSON 结构）
- [x] Task 2: 定义 ToolStreamingEvent (AC: #2)
  - [x] 2.1 创建 struct，payload: `sessionId: String?`, `toolUseId: String`, `chunk: String`
  - [x] 2.2 实现 `AgentEvent` protocol + `CodingKeys` + 显式 Codable
- [x] Task 3: 定义 ToolCompletedEvent (AC: #3)
  - [x] 3.1 创建 struct，payload: `sessionId: String?`, `toolUseId: String`, `toolName: String`, `durationMs: Int`, `isError: Bool`
  - [x] 3.2 实现 `AgentEvent` protocol + `CodingKeys` + 显式 Codable
- [x] Task 4: 定义 ToolFailedEvent (AC: #4)
  - [x] 4.1 创建 struct，payload: `sessionId: String?`, `toolUseId: String`, `toolName: String`, `error: String`
  - [x] 4.2 实现 `AgentEvent` protocol + `CodingKeys` + 显式 Codable
- [x] Task 5: 编写单元测试 (AC: #1-#5)
  - [x] 5.1 在 `AgentEventTypesTests.swift` 中追加测试（不新建文件）
  - [x] 5.2 测试每个 event 的构造和 AgentEvent protocol conformance
  - [x] 5.3 测试每个 event 的 Codable round-trip（含 snake_case JSON key 验证）
  - [x] 5.4 测试 `sessionId` 和 `input` 可为 nil
  - [x] 5.5 测试 Sendable conformance（编译时验证）
  - [x] 5.6 测试 Equatable 和 existential 用法（`any AgentEvent`）
- [x] Task 6: 编写 E2E 测试 (AC: #1-#5)
  - [x] 6.1 在 `AgentEventTypesE2ETests.swift` 中追加测试
  - [x] 6.2 E2E 测试覆盖: 全 lifecycle 模拟、Codable Date 精度、concurrent usage、existential dispatch、SSE-compatible JSON format
  - [x] 6.3 在 `main.swift` 中接线（SECTION 87-101 → 更新注释为 87-113）

## Dev Notes

### Architecture Context

本 Story 是 Epic 26 的第四个 Story，在 26.1（AgentEvent protocol + BaseAgentEvent）和 26.2（Session Lifecycle Events）之上定义 tool lifecycle event 类型。

**与 26.1 的关系：**
- 26.1 已创建 `AgentEvent` protocol（`Sendable` + `Codable`）、`BaseAgentEvent` struct、`AgentEventCategory` enum
- `AgentEventCategory` 包含 `.tool` case，本 Story 的 event 类型属于该分类

**与 26.2/26.3 的关系：**
- 26.2 在同一文件中追加了 4 个 session event struct + `SessionFinalStatus` enum
- 26.3 在同一文件中追加了 5 个 agent event struct
- 本 Story 使用完全相同的组合模式（`base: BaseAgentEvent`）和 Codable 实现

**与后续 Story 的关系：**
- 26.5 LLM Cost Events 会使用相同的组合模式
- 26.6 EventBus 会消费这些 event 类型
- Epic 27 Agent Emitter 会在 `QueryEngine` 的 tool 执行路径中 emit 这些 event

**Emit 场景（Epic 27 参考，本 Story 不实现）：**

| Event | Emit 时机 | Emit 位置（未来） |
|-------|-----------|------------------|
| `ToolStartedEvent` | tool 开始执行 | `QueryEngine` 执行 tool call 前 |
| `ToolStreamingEvent` | tool 输出流式数据 | tool 实现内部 streaming callback |
| `ToolCompletedEvent` | tool 执行完成 | `QueryEngine` 收到 `ToolResult` 后 |
| `ToolFailedEvent` | tool 执行失败 | `QueryEngine` catch tool 错误时 |

### File Location

- **UPDATE**: `Sources/OpenAgentSDK/Types/AgentEventTypes.swift` — 在文件末尾（`AgentResumedEvent` 之后）追加 tool event 类型
- **UPDATE**: `Tests/OpenAgentSDKTests/Types/AgentEventTypesTests.swift` — 在文件末尾追加测试
- **UPDATE**: `Sources/E2ETest/AgentEventTypesE2ETests.swift` — 追加 E2E 测试
- **UPDATE**: `Sources/E2ETest/main.swift` — 更新 SECTION 注释（87-101 → 87-109+）

### Implementation Pattern

严格遵循 26.2/26.3 建立的模式：

```swift
// MARK: - Tool Events

/// Emitted when a tool starts executing.
public struct ToolStartedEvent: AgentEvent, Equatable {
    public let base: BaseAgentEvent
    public let sessionId: String?
    public let toolName: String
    public let toolUseId: String
    public let input: String?

    public var id: String { base.id }
    public var timestamp: Date { base.timestamp }

    enum CodingKeys: String, CodingKey {
        case id, timestamp
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolUseId = "tool_use_id"
        case input
    }

    public init(base: BaseAgentEvent = BaseAgentEvent(), sessionId: String?, toolName: String, toolUseId: String, input: String?) {
        self.base = base
        self.sessionId = sessionId
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.input = input
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = BaseAgentEvent(
            id: try c.decode(String.self, forKey: .id),
            timestamp: try c.decode(Date.self, forKey: .timestamp)
        )
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        toolName = try c.decode(String.self, forKey: .toolName)
        toolUseId = try c.decode(String.self, forKey: .toolUseId)
        input = try c.decodeIfPresent(String.self, forKey: .input)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(base.id, forKey: .id)
        try c.encode(base.timestamp, forKey: .timestamp)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encode(toolName, forKey: .toolName)
        try c.encode(toolUseId, forKey: .toolUseId)
        try c.encodeIfPresent(input, forKey: .input)
    }
}
```

**关键设计点：**
- `sessionId: String?`（nullable）— 不是所有 agent 都配置了 SessionStore
- `toolName: String` — 工具名称（如 "BashTool"、"FileReadTool"）
- `toolUseId: String` — 每次工具调用的唯一 ID，与 `SDKMessage.ToolUseData.toolUseId` 对应
- `input: String?`（nullable）— 工具输入 JSON，可为 nil（敏感数据场景，emit 方决定是否包含）
- `chunk: String` — 流式输出片段
- `durationMs: Int` — 毫秒级精度（不是 Double），与 agent events 一致
- `isError: Bool` — 区分成功完成和失败完成（与 `SDKMessage.ToolResultData.isError` 对应）
- `error: String`（非 nil）— 失败原因描述
- JSON 字段使用 snake_case（`session_id`、`tool_name`、`tool_use_id`、`duration_ms`、`is_error`）匹配 Anthropic API 风格

**CodingKeys 策略（与 26.2/26.3 完全一致）：**
- `id` 和 `timestamp` 顶层序列化（不嵌套 `base`），保持 JSON 扁平结构
- Swift 属性 camelCase，JSON 字段 snake_case

### 与现有类型的关联

- `SDKMessage.ToolUseData`（`Types/SDKMessage.swift:192`）— `toolName`、`toolUseId`、`input` 字段直接对应 `ToolStartedEvent` 的 payload
- `SDKMessage.ToolResultData`（`Types/SDKMessage.swift:208`）— `toolUseId`、`isError` 对应 `ToolCompletedEvent` 的 payload
- `SDKMessage.ToolProgressData`（`Types/SDKMessage.swift:519`）— streaming 概念的参考，但 `ToolStreamingEvent.chunk` 是字符串而非 elapsedTime
- `ToolProtocol`（`Types/ToolTypes.swift`）— `name` 属性即 `toolName` 的来源
- `ToolResult`（`Types/ToolTypes.swift`）— 工具执行结果，`isError` 和内容来自此类型

### Testing Standards

- 追加到已有 `AgentEventTypesTests.swift`，不新建单元测试文件
- 使用 XCTest 框架（`XCTestCase`），不是 Swift Testing
- 纯 struct 构造测试，不需要 mock 或 LLM
- 每个事件测试：构造 + AgentEvent conformance + Codable round-trip + Sendable 编译检查
- E2E 测试追加到 `AgentEventTypesE2ETests.swift`，使用真实的 JSONEncoder/JSONDecoder
- 测试编号从 102 开始（当前最后一个测试是 101）

### Project Structure Notes

- Types/ 目录是叶节点，零出站依赖
- 所有 tool event 类型追加到 `AgentEventTypes.swift`（26.1-26.3 已建立此文件，当前 447 行）
- 不创建新目录或新源文件（E2E 测试在现有文件中追加）

### References

- [Source: docs/epics/epic-26-agent-event-types.md#Story 26.4]
- [Source: docs/runtime-event-layer-roadmap.md#S1 — Tool event types table]
- [Source: Sources/OpenAgentSDK/Types/AgentEventTypes.swift — 26.1-26.3 已有类型]
- [Source: Sources/OpenAgentSDK/Types/SDKMessage.swift:192-237 — ToolUseData, ToolResultData, ToolExecutionPair]
- [Source: Sources/OpenAgentSDK/Types/SDKMessage.swift:519-534 — ToolProgressData]
- [Source: _bmad-output/project-context.md — rules 1, 4, 12-13, 20-21, 39-45]

### Scope Boundaries

**本 Story 只做：**
- `ToolStartedEvent` struct
- `ToolStreamingEvent` struct
- `ToolCompletedEvent` struct
- `ToolFailedEvent` struct
- 对应单元测试和 E2E 测试

**不做（后续 Story）：**
- LLM 具体事件类型（→ Story 26.5）
- EventBus actor（→ Story 26.6）
- Agent 内部 emit 点（→ Epic 27）
- SSE 映射（→ Epic 28）

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (via Claude Code)

### Debug Log References

None.

### Completion Notes List

- ✅ Implemented 4 tool lifecycle event structs (ToolStartedEvent, ToolStreamingEvent, ToolCompletedEvent, ToolFailedEvent) following the composition pattern from 26.2/26.3
- ✅ All structs are `AgentEvent`, `Equatable`, `Sendable`, `Codable` with flat JSON serialization (snake_case keys)
- ✅ 58 unit tests added covering construction, protocol conformance, Codable round-trip, snake_case JSON, nil handling, Equatable, edge cases (empty strings, zero values), and actor boundary crossing
- ✅ 12 E2E tests added (tests 102-113) covering full lifecycle, Date precision, concurrent usage, existential dispatch, SSE-compatible JSON format, and cross-category dispatch
- ✅ All 6362 tests pass, 0 regressions
- ✅ No existing API modified — pure addition to AgentEventTypes.swift

### File List

- `Sources/OpenAgentSDK/Types/AgentEventTypes.swift` — Added 4 tool event structs (ToolStartedEvent, ToolStreamingEvent, ToolCompletedEvent, ToolFailedEvent)
- `Tests/OpenAgentSDKTests/Types/AgentEventTypesTests.swift` — Added tool event unit tests (including edge cases)
- `Sources/E2ETest/AgentEventTypesE2ETests.swift` — Added tool event E2E tests (102-113) and TestActor methods
- `Sources/E2ETest/main.swift` — Updated SECTION comment (87-101 → 87-113)
- `_bmad-output/implementation-artifacts/26-4-tool-lifecycle-events.md` — Story file updated
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Status updated to review
- `_bmad-output/implementation-artifacts/tests/test-summary-26-4.md` — Test summary
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Status updated to review

### Change Log

- 2026-05-26: Story 26.4 implementation complete — 4 tool lifecycle event types + unit tests + E2E tests, all 6362 tests passing
- 2026-05-26: Review fix — Added 6 edge case tests (empty strings, zero values), corrected E2E test count (12, not 8), updated File List, fixed task 6.3 comment
