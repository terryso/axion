---
epic_id: epic-testing-migration
title: "XCTest → Swift Testing 框架迁移"
status: draft
created: 2026-05-15
author: John (PM)
phase: "Phase 3.5 — 技术债务清理"
motivation: "统一测试框架，消除双框架维护成本，利用 Swift Testing 的现代特性"
---

# Epic: XCTest → Swift Testing 框架迁移

## 背景与动机

Axion 项目目前同时使用 XCTest 和 Swift Testing 两套测试框架：
- **XCTest 文件**: 106 个（需要迁移）
- **Swift Testing 文件**: 29 个（已完成迁移，作为参考模板）
- **总计**: 136 个测试文件

**为什么要迁移：**
1. **消除双框架维护成本** — 两套断言 API、两套生命周期管理，新人困惑
2. **Swift Testing 是 Apple 官方推荐的未来方向** — Xcode 16+ 原生支持，Swift 6.1 深度集成
3. **更好的测试表达力** — `@Test("描述")` / `#expect` / `@Suite` 更简洁
4. **更快的编译速度** — 基于宏的 Swift Testing 不需要 Objective-C 运行时
5. **AxionBar 已全部迁移** — 证明模式可行，有现成参考

## 现状数据

### 按模块分布

| 模块 | XCTest | Swift Testing | 迁移量 |
|------|--------|---------------|--------|
| AxionCoreTests | 11 | 3 | 11 文件 |
| AxionHelperTests | 31 | 2 | 31 文件 |
| AxionCLITests | 59 | 10 | 59 文件 |
| AxionBarTests | 0 | 14 | 已完成 |
| AxionE2ETests | ~5 | 0 | ~5 文件 |
| **合计** | **106** | **29** | **106 文件** |

### XCTest 断言模式使用频率

| XCTest 模式 | 使用次数 | Swift Testing 映射 |
|-------------|---------|-------------------|
| `XCTAssertEqual` | 1191 | `#expect(a == b)` |
| `XCTAssertTrue` | 686 | `#expect(expr)` |
| `XCTAssertNotNil` | 256 | `#expect(x != nil)` / `let v = try #require(x)` |
| `XCTAssertFalse` | 235 | `#expect(!expr)` |
| `XCTAssertThrowsError` | 57 | `#expect(throws: Error.self) { ... }` |
| `XCTAssertNil` | 70 | `#expect(x == nil)` |
| `XCTFail` | 102 | `Issue.record("reason")` |
| `XCTAssertGreaterThan` | 46 | `#expect(a > b)` |
| `XCTAssertLessThan` | 11 | `#expect(a < b)` |
| `setUp/tearDown` | 37/31 | `init()` / `deinit` 或 suite 生命周期 |

### 需要特殊处理的文件（setUp/tearDown）

15 个文件使用 `setUp` / `tearDown`，迁移时需转换为 struct 的 `init()` / `deinit` 或使用 `@Suite` 生命周期：
- AxionCLITests: ConfigManagerTests, DoctorCommandTests, SetupCommandTests, TraceRecorderTests, TraceWindowContextTests, HelperPathResolverTests, PlannerPromptMultiWindowTests, 4 个 Integration 测试
- AxionE2ETests: 4 个文件

## 迁移规则

### 1-to-1 映射表

```swift
// XCTest → Swift Testing
import XCTest              → import Testing
class FooTests: XCTestCase → @Suite("Foo") struct FooTests {
func test_xxx()            → @Test("xxx") func xxx() {
XCTAssertEqual(a, b)       → #expect(a == b)
XCTAssertTrue(expr)        → #expect(expr)
XCTAssertFalse(expr)       → #expect(!expr)
XCTAssertNil(x)            → #expect(x == nil)
XCTAssertNotNil(x)         → #expect(x != nil) 或 let v = try #require(x)
XCTAssertThrowsError { }   → #expect(throws: Error.self) { try ... }
XCTFail("msg")             → Issue.record("msg")
XCTSkipIf(cond)            → @Test(.disabled(if:)) 或 guard + return
setUp()                    → init() { ... }
tearDown()                 → deinit { ... }
```

### 命名规则

- **Suite**: `@Suite("被测类型")` — 如 `@Suite("WindowState")`
- **Test**: `@Test("场景_预期结果")` — 保持原测试方法名的语义
- **文件名**: 不变，继续镜像源文件结构

### 不迁移的范围

- **Mock 文件**（如 `MockServices.swift`）— 这些不是测试文件，可能继续使用 XCTest mock 模式
- **Integration 测试** — 放在最后迁移，优先迁移单元测试确保模式稳定

## Story 分解

### Story TM-1: 迁移 AxionCoreTests（11 文件）

**优先级**: P0 — 最简单，最独立，用于验证迁移模式和 CI 配置

**范围**:
- `AxionConfigTests.swift`
- `AxionErrorTests.swift`
- `ExecutedStepTests.swift`
- `OutputProtocolTests.swift`
- `PlanTests.swift`
- `RunContextTests.swift`
- `RunStateTests.swift`
- `SPMScaffoldTests.swift`
- `StopConditionTests.swift`
- `ValueTests.swift`
- `VerificationResultTests.swift`

**验收标准**:
- [ ] 所有 11 个文件改为 `import Testing` + `@Suite` + `@Test`
- [ ] 断言全部替换为 `#expect`
- [ ] `swift test --filter "AxionCoreTests"` 全部通过
- [ ] CI 单元测试流水线通过

**估计**: 1 个 Story Session

---

### Story TM-2: 迁移 AxionHelperTests 单元测试 — Models & Services（14 文件）

**优先级**: P1

**范围**:
- Models (4): `WindowStateTests`, `AXElementTests`, `AppInfoTests`, `WindowInfoTests`
- Services (8): `InputSimulationServiceTests`, `AppLauncherServiceTests`, `AccessibilityEngineServiceTests`, `SelectorResolverTests`, `ScreenshotServiceTests`, `URLOpenerServiceTests`, `ServiceContainerTests`, `EventRecorderTests`
- Mocks (1): `MockServices.swift` — 检查是否需要调整
- MCP (1): `HelperScaffoldTests`

**验收标准**:
- [ ] 所有文件改为 Swift Testing
- [ ] `swift test --filter "AxionHelperTests.Models"` 通过
- [ ] `swift test --filter "AxionHelperTests.Services"` 通过

**估计**: 1 个 Story Session

---

### Story TM-3: 迁移 AxionHelperTests 单元测试 — Tools（7 文件）

**优先级**: P1

**范围**:
- `AppBundleTests.swift`
- `InputToolsTests.swift`
- `LaunchAppToolTests.swift`
- `MouseKeyboardToolTests.swift`
- `ScreenshotAndMiscToolTests.swift`
- `ScreenshotUrlToolTests.swift`
- `WindowManagementToolTests.swift`

**验收标准**:
- [ ] 所有文件改为 Swift Testing
- [ ] `swift test --filter "AxionHelperTests.Tools"` 通过

**估计**: 1 个 Story Session

---

### Story TM-4: 迁移 AxionHelperTests MCP 测试（3 文件）

**优先级**: P1

**范围**:
- `HelperMCPServerTests.swift`
- `HelperProcessSmokeTests.swift`
- `RecordingToolE2ETests.swift`（已部分使用 Testing，需确认一致性）

**验收标准**:
- [ ] 所有文件统一使用 Swift Testing
- [ ] `swift test --filter "AxionHelperTests.MCP"` 通过

**估计**: 0.5 个 Story Session

---

### Story TM-5: 迁移 AxionCLITests 单元测试 — Core（18 文件）

**优先级**: P1

**范围**:
- Config (1): `ConfigManagerTests` ⚠️ 有 setUp/tearDown
- Planner (5): `PlanParserTests`, `LLMPlannerTests`, `PromptBuilderTests`, `CrossAppWorkflowTests`, `PlannerPromptMultiWindowTests` ⚠️ 有 setUp
- Executor (3): `PlaceholderResolverTests`, `SafetyCheckerTests`, `StepExecutorTests`
- Engine (2): `RunEngineTests`, `RunEngineExtraTests`
- Verifier (2): `StopConditionEvaluatorTests`, `TaskVerifierTests`
- IO (1): `TakeoverIOTests`
- Helper (2): `HelperPathResolverTests` ⚠️ 有 setUp, `HelperProcessManagerTests`
- Trace (2): `TraceRecorderTests` ⚠️ 有 setUp, `TraceWindowContextTests` ⚠️ 有 setUp

**验收标准**:
- [ ] 所有文件改为 Swift Testing
- [ ] setUp/tearDown 转换为 init/deinit 模式
- [ ] 所有对应 filter 的测试通过

**估计**: 1.5 个 Story Session

---

### Story TM-6: 迁移 AxionCLITests 单元测试 — API & MCP（14 文件）

**优先级**: P1

**范围**:
- API (6): `APITypesTests`, `AuthMiddlewareTests`, `AxionAPIRoutesTests`, `ConcurrencyLimiterTests`, `EventBroadcasterTests`, `RunTrackerTests`, `SSEEventTests`
- MCP (6): `HelpOutputTests`, `MCPProtocolIntegrationTests`, `QueryTaskStatusToolTests`, `RunTaskToolTests`, `StdoutPurityTests`, `TaskQueueTests`
- Output (3): `JSONOutputTests`, `TerminalOutputTests`, `OutputImplementationTests`
- Other (1): `SDKOutputHandlerTests`

**验收标准**:
- [ ] 所有文件改为 Swift Testing
- [ ] `swift test --filter "AxionCLITests.API"` 通过
- [ ] `swift test --filter "AxionCLITests.MCP"` 通过

**估计**: 1 个 Story Session

---

### Story TM-7: 迁移 AxionCLITests 单元测试 — Commands（20 文件）

**优先级**: P2

**范围**:
- Commands 目录下所有 XCTest 文件（~20 个）
- 包括 `RunCommandATDDTests`, `RunCommandProfileContentTests`, `SDKBoundaryAuditTests`, `SDKIntegrationATDDTests` 等

**验收标准**:
- [ ] 所有文件改为 Swift Testing
- [ ] `swift test --filter "AxionCLITests.Commands"` 通过

**估计**: 1 个 Story Session

---

### Story TM-8: 迁移所有 Integration 测试（15 文件）

**优先级**: P2 — 最后迁移，因为依赖真实系统环境

**范围**:
- AxionHelperTests/Integration (10): AccessibilityEngineRealTests, AppLauncherServiceRealTests, FullToolRegistrationTests, HelperStartupPerformanceTests, InputSimulationRealTests, LaunchAppIntegrationTests, ScreenshotServiceRealTests, SingleOperationPerformanceTests, URLOpenerServiceRealTests, WindowManagementIntegrationTests
- AxionCLITests/Integration (5): RunEngineIntegrationTests, EndToEndSmokeTests, OutputTraceIntegrationTests, SDKAgentIntegrationTests, VerifierIntegrationTests

**验收标准**:
- [ ] 所有 Integration 测试文件改为 Swift Testing
- [ ] `make test` 单元测试通过
- [ ] Integration 测试本地验证通过（CI 不跑 Integration）

**估计**: 1 个 Story Session

---

### Story TM-9: 迁移 AxionE2ETests & 清理 XCTest 依赖

**优先级**: P3

**范围**:
- 迁移 `Tests/AxionE2ETests/` 下所有文件
- 从 `Package.swift` 移除 XCTest 依赖（如果可以完全移除）
- 验证 `make test` 和 `swift test --filter` 全部通过
- 更新 `project-context.md` 中的测试规则文档
- 更新 CLAUDE.md 中的测试命令说明

**验收标准**:
- [ ] `grep -rl "import XCTest" Tests/` 返回空
- [ ] `swift test` 全量通过
- [ ] CI 绿色
- [ ] 项目文档更新完毕

**估计**: 1 个 Story Session

---

## 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Swift Testing 的 `#expect` 在复杂表达式中产生错误信息不如 XCTest 清晰 | 中 | 在 `#expect` 中使用简洁表达式，必要时拆分为多个 `#expect` |
| `setUpWithError` 抛出错误的场景需要特殊处理 | 低 | 使用 `init() throws` 或 `@Test` 的 `.disabled()` trait |
| 部分测试使用 `XCTExpectFailure` | 低 | 迁移为 `withKnownIssue { ... }` |
| CI 环境中 Swift Testing 的并行执行可能导致测试顺序问题 | 低 | Swift Testing 默认并行，但测试应无相互依赖 |

## 执行顺序

```
TM-1 (Core) → TM-2 (Helper Models/Services) → TM-3 (Helper Tools)
    → TM-4 (Helper MCP) → TM-5 (CLI Core) → TM-6 (CLI API/MCP)
    → TM-7 (CLI Commands) → TM-8 (Integration) → TM-9 (E2E + 清理)
```

**建议分配策略**:
- TM-1 到 TM-4 可并行执行（不同模块互不依赖）
- TM-5 到 TM-7 可并行执行（同模块不同目录）
- TM-8 和 TM-9 必须串行（等单元测试全部稳定后再迁移集成测试）

## 总估计

| Story | 估计 |
|-------|------|
| TM-1 | 1 session |
| TM-2 | 1 session |
| TM-3 | 1 session |
| TM-4 | 0.5 session |
| TM-5 | 1.5 sessions |
| TM-6 | 1 session |
| TM-7 | 1 session |
| TM-8 | 1 session |
| TM-9 | 1 session |
| **合计** | **~9 sessions** |
