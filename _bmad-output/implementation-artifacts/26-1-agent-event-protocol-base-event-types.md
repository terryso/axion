# Story 26.1: AgentEvent Protocol 与 Base Event 类型

Status: done

## Story

As a SDK 开发者,
I want 定义统一的 AgentEvent protocol 和事件分类,
so that 所有 runtime 事件有统一的类型约束和命名规范.

## Acceptance Criteria

1. **AC1: AgentEvent protocol 定义**
   - Given `AgentEvent` protocol 被定义
   - When 一个 struct 遵循 `AgentEvent`
   - Then 必须提供 `id: String` 和 `timestamp: Date`

2. **AC2: BaseAgentEvent 默认实现**
   - Given `BaseAgentEvent` 被创建
   - When 检查其属性
   - Then `id` 是自动生成的 UUID 字符串
   - And `timestamp` 是初始化时的 `Date()`

3. **AC3: AgentEventCategory 分类枚举**
   - Given `AgentEventCategory` 被定义
   - When 检查其所有 case
   - Then 包含 session / agent / tool / llm / memory / subAgent

4. **AC4: 类型约束**
   - All event types 为 `struct`（value type）
   - All event types 遵循 `Sendable`
   - All event types 遵循 `Codable`（未来 JSON 序列化和 SQLite 存储需求）

5. **AC5: 不改现有 API**
   - 不修改 `SDKMessage`、`Agent.stream()` 或任何现有类型
   - 纯新增文件

## Tasks / Subtasks

- [x] Task 1: 创建 AgentEventTypes.swift 类型文件 (AC: #1, #2, #3, #4)
  - [x] 1.1 定义 `AgentEvent` protocol（`id: String`, `timestamp: Date`, 继承 `Sendable`）
  - [x] 1.2 定义 `BaseAgentEvent` struct（提供 `id` UUID 自动生成和 `timestamp` 默认值）
  - [x] 1.3 定义 `AgentEventCategory` enum（session, agent, tool, llm, memory, subAgent）
  - [x] 1.4 让 `BaseAgentEvent` 遵循 `Codable` 和 `Equatable`
- [x] Task 2: 更新 OpenAgentSDK.swift 重新导出 (AC: #5)
  - [x] 2.1 在模块入口文件中添加 `AgentEvent`、`BaseAgentEvent`、`AgentEventCategory` 的文档引用
- [x] Task 3: 编写单元测试 (AC: #1-#4)
  - [x] 3.1 创建 `Tests/OpenAgentSDKTests/Types/AgentEventTypesTests.swift`
  - [x] 3.2 测试 `AgentEvent` protocol 约束（编译时验证）
  - [x] 3.3 测试 `BaseAgentEvent` 属性（id 非空、timestamp 合理）
  - [x] 3.4 测试 `BaseAgentEvent` 的 `Codable` round-trip
  - [x] 3.5 测试 `BaseAgentEvent` 的 `Equatable` 行为
  - [x] 3.6 测试 `AgentEventCategory` 所有 rawValue 和 CaseIterable

## Dev Notes

### Architecture Context

本 Story 是 Runtime Event Layer 的基础（S1 phase），Epic 26-28 全部依赖此 Story 定义的 `AgentEvent` protocol。

**关键设计决策：**
- `AgentEvent` 是 protocol（不是 class），让具体事件类型用 struct 实现，满足 Sendable + value semantics
- `BaseAgentEvent` 提供通用的 `id` + `timestamp` 实现，具体事件类型可组合使用（不继承，用组合）
- `AgentEventCategory` 是分类枚举，用于 EventBus 的类型过滤 subscribe 和日志分类
- 所有类型都是 `Codable` — Epic 28 会将 AgentEvent 映射为 SSE event，Axion 需要 JSON 序列化

**与现有类型的关系（不要混淆）：**
- `SDKMessage`（`Types/SDKMessage.swift`）— LLM 消息级抽象，**不改**
- `AgentSSEEvent`（`HTTP/APITypes.swift:215`）— SSE 推送用枚举，AgentEvent 是其上游数据源
- `HookEvent`（`Types/HookTypes.swift`）— Hook 系统的生命周期事件枚举，与 AgentEvent 是不同层级

**sessionId 设计：** 所有具体事件类型中的 `sessionId` 字段应为 `String?`（不是所有 agent 都配置 SessionStore）。

### File Location

- 新文件：`Sources/OpenAgentSDK/Types/AgentEventTypes.swift`
- 遵循现有命名模式：`*Types.swift`（参考 `CostTypes.swift`、`HookTypes.swift`、`ExperienceTypes.swift`）
- 测试文件：`Tests/OpenAgentSDKTests/Types/AgentEventTypesTests.swift`

### Implementation Pattern

参考 `ExperienceTypes.swift` 中的 protocol + struct 模式：

```swift
// Pattern: Protocol with Sendable constraint
public protocol AgentEvent: Sendable {
    var id: String { get }
    var timestamp: Date { get }
}

// Pattern: Base struct with auto-generated id
public struct BaseAgentEvent: AgentEvent, Codable, Equatable {
    public let id: String
    public let timestamp: Date

    public init() {
        self.id = UUID().uuidString
        self.timestamp = Date()
    }
}

// Pattern: Category enum with String rawValue + Codable + CaseIterable
public enum AgentEventCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case session
    case agent
    case tool
    case llm
    case memory
    case subAgent
}
```

### Project Structure Notes

- Types/ 目录是叶节点，不依赖其他模块 — AgentEventTypes 纯类型定义，零出站依赖
- 所有 event 类型放在同一个文件 `AgentEventTypes.swift` 中（Story 26.2-26.5 的具体事件也在此文件中追加）
- 不需要创建新目录

### Testing Standards

- 使用 XCTest 框架（不是 Swift Testing 的 `@Test`）
- 测试文件格式：`import XCTest` + `@testable import OpenAgentSDK` + `final class XxxTests: XCTestCase`
- 参考 `ExperienceTypesTests.swift` 的测试模式
- 纯 struct 构造测试，不需要 mock 或 LLM

### References

- [Source: docs/epics/epic-26-agent-event-types.md#Story 26.1]
- [Source: docs/runtime-event-layer-roadmap.md#S1]
- [Source: Sources/OpenAgentSDK/Types/ExperienceTypes.swift — protocol + struct pattern]
- [Source: Sources/OpenAgentSDK/Types/HookTypes.swift — enum with String rawValue pattern]
- [Source: Sources/OpenAgentSDK/Types/CostTypes.swift — simple struct with Sendable pattern]
- [Source: _bmad-output/project-context.md — rules 1, 4, 12-13, 20-21, 39-45]

### Scope Boundaries

**本 Story 只做：**
- `AgentEvent` protocol
- `BaseAgentEvent` struct
- `AgentEventCategory` enum
- 对应单元测试

**不做（后续 Story）：**
- 具体事件类型（Session/Agent/Tool/LLM events → Story 26.2-26.5）
- EventBus actor（→ Story 26.6）
- Agent 内部 emit 点（→ Epic 27）
- SSE 映射（→ Epic 28）

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (via Claude Code)

### Debug Log References

No issues encountered.

### Completion Notes List

- Implemented `AgentEvent` protocol with `Sendable` inheritance and `id`/`timestamp` requirements
- Implemented `BaseAgentEvent` struct with auto-generated UUID id and Date() timestamp, conforming to `Codable` and `Equatable`
- Implemented `AgentEventCategory` enum with 6 cases (session, agent, tool, llm, memory, subAgent) conforming to `Codable`, `Sendable`, `Equatable`, `CaseIterable`
- Added doc references in OpenAgentSDK.swift under new "Runtime Event Layer" section
- Created 28 unit tests covering all ACs: protocol conformance, Sendable compliance, default/custom init, Codable round-trip, Equatable, category rawValues/CaseIterable, struct value semantics, composition pattern, existential usage, JSON key structure, edge cases, concurrent access
- All 6167 tests pass (0 regressions)

### File List

- Sources/OpenAgentSDK/Types/AgentEventTypes.swift (new)
- Sources/OpenAgentSDK/OpenAgentSDK.swift (modified — added Runtime Event Layer doc section)
- Tests/OpenAgentSDKTests/Types/AgentEventTypesTests.swift (new)

## Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.7 (adversarial code review)
**Date:** 2026-05-25

### Findings (4 total: 1 HIGH, 2 MEDIUM, 1 LOW)

| # | Severity | Issue | File | Status |
|---|----------|-------|------|--------|
| H1 | HIGH | `AgentEvent` protocol missing `Codable` inheritance — AC4 requires all event types to be Codable but protocol only enforced `Sendable` | AgentEventTypes.swift:10 | Fixed |
| M1 | MEDIUM | Completion Notes claimed 18 tests but 28 were written | Story file | Fixed |
| M2 | MEDIUM | `AgentEventCategory` missing `Hashable` conformance — needed for EventBus Set/Dictionary operations | AgentEventTypes.swift:45 | Fixed |
| L1 | LOW | `BaseAgentEvent.init(id:)` accepts empty strings silently | AgentEventTypes.swift:34 | Noted |

### Fixes Applied

1. Added `Codable` to `AgentEvent` protocol inheritance: `public protocol AgentEvent: Sendable, Codable`
2. Added `Hashable` to `AgentEventCategory`: `public enum AgentEventCategory: String, Codable, Sendable, Equatable, Hashable, CaseIterable`
3. Updated test composition structs to declare `Codable` conformance (required by updated protocol)
4. Corrected Completion Notes test count from 18 to 28

### Verification

- Build: Passes
- Tests: 6179 passing, 0 failures (28 AgentEventTypes tests)
- No regressions from review fixes
