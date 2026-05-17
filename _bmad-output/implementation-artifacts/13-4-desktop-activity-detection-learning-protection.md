# Story 13.4: 桌面活动检测与学习保护

Status: done

## Story

As a 系统,
I want 在 shared-seat 模式下检测用户的桌面操作,
so that 被用户操作"污染"的运行不会产生错误的 Memory.

## Acceptance Criteria

1. **AC1: 外部活动检测**
   - **Given** shared-seat 模式运行中（未设置 --allow-foreground）
   - **When** 检测到用户手动操作了桌面（鼠标移动 >= 8px 或前台应用切换）
   - **Then** 标记该次运行为 "externally modified"，TraceRecorder 记录 `external_activity_detected` 事件

2. **AC2: Memory 提取禁用**
   - **Given** 运行被标记为 externally modified
   - **When** 任务完成，准备 Memory 提取
   - **Then** 跳过 AppMemoryExtractor 调用（不调用 extract 和 extractFacts），输出提示 "检测到外部桌面操作，本次运行的经验不会被记忆"

3. **AC3: 验证逻辑不受影响**
   - **Given** 运行被标记为 externally modified
   - **When** verifier 评估
   - **Then** 正常验证，不跳过验证逻辑（仅影响 Memory 学习）

4. **AC4: foreground 模式不检测**
   - **Given** --allow-foreground 模式运行
   - **When** 检测逻辑
   - **Then** 不创建 SeatActivityMonitor，不检测外部活动（foreground 模式本身就是用户协作模式）

5. **AC5: 非目标窗口操作不标记**
   - **Given** 用户在运行期间手动操作了非目标窗口（前台应用未变化）
   - **When** 仅鼠标小幅移动（< 8px）
   - **Then** 不标记为 externally modified

6. **AC6: Trace 记录基线与检测**
   - **Given** SeatActivityMonitor 创建成功
   - **When** 创建时
   - **Then** TraceRecorder 记录 `seat_baseline` 事件，包含初始光标位置和前台应用信息

7. **AC7: 一次性报告**
   - **Given** 首次检测到外部活动
   - **When** 记录
   - **Then** 输出警告 "[axion] 检测到外部桌面操作，本次运行的经验不会被记忆"，后续检测不再重复输出

8. **AC8: API Runner 也受保护**
   - **Given** API server 提交的 live run 在 shared-seat 模式下
   - **When** 检测到外部活动
   - **Then** 同样禁用 Memory 提取

## Tasks / Subtasks

- [x] Task 1: 创建 SeatActivityMonitor (AC: #1, #5, #6)
  - [x] 1.1 创建 `Sources/AxionCLI/Services/SeatActivityMonitor.swift`
  - [x] 1.2 定义 `SeatActivityMonitor` actor，维护 baseline 光标位置 (`CGPoint?`) 和前台应用信息 (`String?` bundleId)
  - [x] 1.3 维护 `reported: Set<String>` 防止重复报告同一类型变化
  - [x] 1.4 维护 `externallyModified: Bool` 标记
  - [x] 1.5 实现 `static func create() -> SeatActivityMonitor?` — 采样初始光标位置（`NSEvent.mouseLocation`）和前台应用（`NSWorkspace.shared.frontmostApplication?.bundleIdentifier`），两者都获取失败则返回 nil
  - [x] 1.6 实现 `describeBaseline() -> String` — 返回基线描述字符串（用于 trace）
  - [x] 1.7 实现 `check() -> String?` — 采样当前光标和前台应用，比较基线：光标移动 >= 8px（`hypot`）或前台应用 bundleId 变化 → 返回变化描述，否则返回 nil
  - [x] 1.8 每个变化类型只报告一次（`reported` Set 去重）

- [x] Task 2: 添加 Trace 事件类型 (AC: #1, #6)
  - [x] 2.1 在 `TraceRecorder.TraceEventType` 添加 `externalActivityDetected = "external_activity_detected"` 常量
  - [x] 2.2 添加 `seatBaseline = "seat_baseline"` 常量
  - [x] 2.3 添加 `recordExternalActivityDetected(description: String, phase: String)` 便捷方法
  - [x] 2.4 添加 `recordSeatBaseline(baseline: String)` 便捷方法

- [x] Task 3: 集成到 RunCommand 消息流 (AC: #1, #3, #4, #6, #7)
  - [x] 3.1 在 `RunCommand.run()` 中，shared-seat 模式下创建 `SeatActivityMonitor`（仅当 `config.sharedSeatMode && !allowForeground && !dryrun`）
  - [x] 3.2 创建后立即记录 `seat_baseline` trace 事件
  - [x] 3.3 在 `.assistant` 消息处理前调用 `seatMonitor?.check()` — 如果返回非 nil，设置 `externallyModified = true`，记录 `external_activity_detected` trace
  - [x] 3.4 首次检测到时输出警告到 stderr："[axion] 检测到外部桌面操作，本次运行的经验不会被记忆"
  - [x] 3.5 在 Memory 提取代码块前检查 `externallyModified` — 为 true 时跳过整个 Memory 提取，仅输出提示

- [x] Task 4: 集成到 AgentRunner (API) (AC: #8)
  - [x] 4.1 在 `AgentRunner` 中复用 SeatActivityMonitor — 在 shared-seat 模式下创建并检查
  - [x] 4.2 将 `externallyModified` 状态传递给 Memory 提取逻辑的跳过判断

- [x] Task 5: 单元测试 (All ACs)
  - [x] 5.1 创建 `Tests/AxionCLITests/Services/SeatActivityMonitorTests.swift`
  - [x] 5.2 测试：check() 检测到光标变化返回描述
  - [x] 5.3 测试：check() 检测到前台应用变化返回描述
  - [x] 5.4 测试：check() 无变化返回 nil
  - [x] 5.5 测试：同一类型变化只报告一次（reported Set 去重）
  - [x] 5.6 测试：externallyModified 标记正确设置
  - [x] 5.7 测试：describeBaseline() 返回正确格式
  - [x] 5.8 测试：create() 基线采样逻辑（mock NSEvent/NSWorkspace）
  - [x] 5.9 测试：TraceRecorder 新事件类型记录格式正确

## Dev Notes

### 核心设计决策

**D1: SeatActivityMonitor 为 actor**
- 遵循项目 actor 隔离模式（RunLockService、RunTracker、VisualDeltaTracker、CostTracker）
- 管理 externallyModified、reported 等可变状态
- check() 需要原子性：采样 + 比较 + 更新 reported + 设置标记

**D2: CLI 侧实现，不需要 Helper**
- `NSEvent.mouseLocation` 可从任何进程获取光标位置（不需要 AX 权限）
- `NSWorkspace.shared.frontmostApplication` 可从任何进程获取前台应用
- 与 OpenClick 不同（OpenClick 用 `runCuaDriverCapture` 和 `Bun.spawn swift -e`），Axion 直接用 AppKit API
- **不要在 Helper 端做活动检测** — Helper 只做 AX 操作

**D3: 轮询检测而非持续监听**
- OpenClick 的 `SeatActivityMonitor.check()` 是轮询式（在每个批次前后调用）
- Axion 在每条 `.assistant` 消息处理前调用 check()（相当于 OpenClick 的 before_batch/after_batch）
- 不使用 CGEvent Tap 持续监听 — CGEvent Tap 需要 AX 权限且 CPU 开销更大
- 8px 阈值与 OpenClick 一致 — 足够过滤鼠标抖动，足够捕获真实操作

**D4: 仅影响 Memory，不影响执行**
- externallyModified 标记只控制 Memory 提取是否跳过
- 验证（verifier）、成本追踪、trace 记录等全部正常执行
- 这是一个"学习保护"机制，不是"安全阻止"机制

**D5: Memory 跳过范围**
- 跳过 `AppMemoryExtractor.extract()` — 不生成 KnowledgeEntry
- 跳过 `AppMemoryExtractor.extractFacts()` — 不生成 AppMemoryFact
- 跳过 AppProfileAnalyzer 分析 — 不更新 profile
- 跳过 FamiliarityTracker — 不更新熟悉度
- 即跳过 RunCommand 中 Memory 提取代码块的整个 do-catch 块

**D6: 条件创建**
- 仅当 `config.sharedSeatMode && !allowForeground && !dryrun` 时创建 monitor
- 其他模式（foreground、非 shared-seat、dryrun）不创建，seatMonitor 为 nil
- 这样 `seatMonitor?.check()` 在其他模式下自动 no-op

### 与 OpenClick 的关键差异

| Axion | OpenClick | 说明 |
|-------|-----------|------|
| NSEvent.mouseLocation 直接获取 | `runCuaDriverCapture("get_cursor_position")` 外部进程调用 | Axion 原生 AppKit，零延迟 |
| NSWorkspace.shared.frontmostApplication | `Bun.spawn(["swift", "-e", script])` | Axion 直接 API，不需要子进程 |
| actor 隔离 | class + mutable fields | Swift 并发安全 |
| .assistant 消息前检查 | before_batch/after_batch 回调 | Axion 在消息流循环中检查 |
| Memory 提取完全跳过 | `learningDisabled` 禁用 learn 选项 | Axion 在 RunCommand 层控制 |

### 现有代码修改清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/AxionCLI/Services/SeatActivityMonitor.swift` | NEW | SeatActivityMonitor actor |
| `Sources/AxionCLI/Commands/RunCommand.swift` | UPDATE | 创建 monitor、消息流中检查、条件跳过 Memory 提取 |
| `Sources/AxionCLI/Trace/TraceRecorder.swift` | UPDATE | 添加 external_activity_detected、seat_baseline 事件类型和便捷方法 |
| `Sources/AxionCLI/API/AgentRunner.swift` | UPDATE | API 模式下也创建 monitor 并传递 externallyModified 状态 |
| `Tests/AxionCLITests/Services/SeatActivityMonitorTests.swift` | NEW | SeatActivityMonitor 单元测试 |

### 不修改的文件

- `RunLockService.swift` — 运行锁与活动检测独立
- `VisualDeltaTracker.swift` — 视觉增量检查与活动检测独立
- `CostTracker.swift` — 成本追踪不受活动检测影响
- `AppMemoryExtractor.swift` — 不修改 extractor 本身，由 RunCommand 控制是否调用
- `AxionConfig.swift` — 不添加新配置字段（检测行为由 sharedSeatMode 控制）
- `AxionError.swift` — 不添加新错误 case（外部活动不是错误，只是学习保护）
- `AxionHelper` — 不修改 Helper，所有检测在 CLI 侧

### 关键反模式提醒

- **不要在 Helper 端做活动检测** — Helper 只做 AX 操作，活动检测在 CLI 侧用 NSEvent/NSWorkspace
- **不要使用 CGEvent Tap** — 需要 AX 权限，CPU 开销大；用 NSEvent.mouseLocation 轮询足够
- **不要让活动检测影响执行流程** — 只影响 Memory 提取，verifier/trace/cost 全部正常
- **不要在 foreground 模式下检测** — foreground 本身就是用户协作模式，检测无意义
- **不要在 dryrun 模式下检测** — dryrun 不执行实际操作，无需保护
- **不要每次 check 都输出警告** — 只在首次检测时输出一次警告
- **不要忘记 API Runner** — AgentRunner 也需要此保护（通过参数传递 externallyModified）
- **不要创建新的配置字段** — 检测行为完全由 sharedSeatMode && !allowForeground 控制
- **不要在 AxionCore 中添加检测逻辑** — 检测是 CLI 层服务，Core 是纯模型层
- **不要导入 AppKit 到 AxionCore** — NSEvent/NSWorkspace 是 AppKit，只能在 AxionCLI 中使用

### OpenClick 参考映射

| Axion 组件 | OpenClick 参考 | 关键差异 |
|-----------|---------------|---------|
| SeatActivityMonitor.create() | `src/run.ts:2857-2863` SeatActivityMonitor.create() | Axion 用 NSEvent/NSWorkspace，OpenClick 用外部进程 |
| SeatActivityMonitor.check() | `src/run.ts:2877-2907` check() | 同上，但逻辑相同（cursor distance + frontmost app） |
| .assistant 消息前 check | `src/run.ts:645` noteSeatActivity("before_batch") | Axion 在消息流中，OpenClick 在 run loop 中 |
| externallyModified 标记 | `src/run.ts:407` learningDisabled = true | 语义相同，Axion 跳过 Memory 提取，OpenClick 禁用 learn 选项 |
| 首次警告输出 | `src/run.ts:409-414` console.warn | Axion 输出到 stderr，OpenClick 到 console |
| seat_baseline trace | `src/run.ts:400-402` trace.event("seat_baseline") | 格式一致 |
| external_activity_detected trace | `src/run.ts:408` trace.event("external_seat_activity") | Axion 用 external_activity_detected |

### RunCommand 集成详解

```
RunCommand.run() 中 SeatActivityMonitor 集成点：

// 1. 创建 monitor（在消息流循环之前）
let seatMonitor = (config.sharedSeatMode && !allowForeground && !dryrun)
    ? await SeatActivityMonitor.create() : nil
if let monitor = seatMonitor {
    await tracer?.recordSeatBaseline(baseline: await monitor.describeBaseline())
}
var externallyModified = false
var seatActivityReported = false

// 2. 在消息流循环中检查
for await message in messageStream {
    switch message {
    case .assistant(let data):
        // [NEW] 检查外部活动
        if let activity = await seatMonitor?.check() {
            externallyModified = true
            await tracer?.recordExternalActivityDetected(
                description: activity, phase: "before_llm")
            if !seatActivityReported {
                fputs("[axion] 检测到外部桌面操作，本次运行的经验不会被记忆\n", stderr)
                seatActivityReported = true
            }
        }
        // ... existing budget tracking code ...
    // ... existing cases ...
    }
}

// 3. Memory 提取条件跳过
if externallyModified {
    fputs("[axion] 检测到外部桌面操作，本次运行的经验不会被记忆\n", stderr)
    // Skip entire memory extraction block
} else {
    // ... existing memory extraction code (extract, extractFacts, profile, familiarity) ...
}
```

### SeatActivityMonitor 模型

```swift
import AppKit
import Foundation

actor SeatActivityMonitor {
    private let baselineCursor: CGPoint?
    private let baselineFrontmost: String? // bundleId
    private var reported: Set<String> = []
    private(set) var externallyModified: Bool = false

    static func create() -> SeatActivityMonitor? {
        let cursor = NSEvent.mouseLocation
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // 如果两者都无法获取，返回 nil
        // NSEvent.mouseLocation 总会返回值，所以通常不会返回 nil
        return SeatActivityMonitor(
            baselineCursor: cursor,
            baselineFrontmost: frontmost
        )
    }

    func describeBaseline() -> String {
        var parts: [String] = []
        if let cursor = baselineCursor {
            parts.append("cursor=(\(Int(cursor.x)),\(Int(cursor.y)))")
        }
        if let frontmost = baselineFrontmost {
            parts.append("frontmost=\(frontmost)")
        }
        return parts.joined(separator: " ")
    }

    func check() -> String? {
        var changes: [String] = []
        let currentCursor = NSEvent.mouseLocation
        let currentFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Check cursor movement
        if let baseline = baselineCursor {
            let distance = hypot(currentCursor.x - baseline.x, currentCursor.y - baseline.y)
            if distance >= 8 && !reported.contains("cursor") {
                reported.insert("cursor")
                changes.append("cursor moved \(Int(round(distance)))px from baseline (\(Int(baseline.x)),\(Int(baseline.y)))")
            }
        }

        // Check frontmost app change
        if let baseline = baselineFrontmost, let current = currentFrontmost,
           current != baseline && !reported.contains("frontmost") {
            reported.insert("frontmost")
            changes.append("frontmost app changed from \(baseline) to \(current)")
        }

        if !changes.isEmpty {
            externallyModified = true
            return changes.joined(separator: "; ")
        }
        return nil
    }
}
```

### Project Structure Notes

- SeatActivityMonitor 放在 `Sources/AxionCLI/Services/` — 属于 CLI 层服务（与 RunLockService、CostTracker 同目录）
- 需要导入 AppKit（NSEvent、NSWorkspace）— 只能在 AxionCLI target 中使用，不能放在 AxionCore
- TraceRecorder 新事件遵循已有模式（static let 常量 + record 便捷方法）
- 测试需要 mock NSEvent.mouseLocation 和 NSWorkspace — 通过 protocol 注入或直接测试 actor 逻辑

### 测试策略

- 使用 Swift Testing 框架（`@Suite`、`@Test`、`#expect`）
- SeatActivityMonitor 是 actor，测试需要 `await` 调用
- 光标位置和前台应用测试需要 mock：
  - 方案 A：将 NSEvent.mouseLocation 和 NSWorkspace.frontmostApplication 抽象为 protocol，测试时注入 mock
  - 方案 B：直接测试 actor 内部逻辑（传入 baseline 和当前值比较），跳过 AppKit API 调用
  - **推荐方案 B** — 保持简单，测试核心逻辑而非 API 集成
- TraceRecorder 新事件测试验证格式正确
- 测试 externallyModified 标记在首次检测时设置
- 测试 reported Set 去重（同类型变化只报告一次）

### Previous Story Intelligence (Story 13.1 + 13.2 + 13.3)

- **Actor 隔离模式** — RunLockService、VisualDeltaTracker、CostTracker 都是 actor，SeatActivityMonitor 也应该是
- **TraceRecorder 便捷方法** — 在 TraceRecorder actor 中添加 recordXxx 便捷方法（如 recordExternalActivityDetected）
- **消息流结构** — `for await message in agent.stream(task)` + `switch message` 分支处理
- **条件创建模式** — `let visualDeltaTracker = noVisualDelta ? nil : VisualDeltaTracker()` — 同样用于 seatMonitor
- **Defer 不支持 await** — Swift 限制 defer 块中不能包含 await（actor 隔离方法）
- **stderr 输出模式** — `fputs("消息\n", stderr)` 用于非 JSON 模式的提示输出
- **JSON 模式兼容** — `--json` flag 时，警告信息也输出到 stderr（不污染 JSON stdout）
- **Memory 提取在消息流结束后** — RunCommand 中 Memory 提取代码块在 `withTaskCancellationHandler` 之后
- **AgentRunner 与 RunCommand 共享逻辑** — API 模式通过 AgentRunner 运行，需同步更新

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 13 Story 13.4]
- [Source: project-context.md — Actor 隔离边界、模块依赖规则、AxionCore 纯模型层约束]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift — 消息流处理、sharedSeatMode、Memory 提取代码块]
- [Source: Sources/AxionCLI/Trace/TraceRecorder.swift — TraceEventType 和 trace 事件记录]
- [Source: Sources/AxionCLI/Services/CostTracker.swift — actor 模式参考]
- [Source: Sources/AxionCLI/Services/RunLockService.swift — actor 条件创建模式参考]
- [Source: Sources/AxionCore/Constants/ToolNames.swift — foregroundToolNames 定义]
- [Source: Sources/AxionCLI/API/AgentRunner.swift — API Agent 执行逻辑]
- [Source: _bmad-output/implementation-artifacts/13-3-fine-grained-budget-cost-telemetry.md — Previous story learnings]
- [Source: _bmad-output/implementation-artifacts/13-2-visual-delta-check.md — Previous story learnings]
- [Source: _bmad-output/implementation-artifacts/13-1-desktop-level-run-lock.md — Previous story learnings]
- [OpenClick: src/run.ts:2849-2907 — SeatActivityMonitor 类实现]
- [OpenClick: src/run.ts:398-415 — noteSeatActivity 回调和 learningDisabled 设置]
- [OpenClick: src/run.ts:2857-2863 — create() 静态方法采样基线]
- [OpenClick: src/run.ts:2877-2907 — check() 方法和变化检测逻辑]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- ✅ Task 1: Created `SeatActivityMonitor` actor with baseline sampling (`NSEvent.mouseLocation` + `NSWorkspace.shared.frontmostApplication`), 8px cursor movement threshold, frontmost app change detection, `reported` Set dedup, and `externallyModified` flag. Extracted `checkState()` for testability.
- ✅ Task 2: Added `externalActivityDetected` and `seatBaseline` trace event constants + convenience methods to `TraceRecorder`.
- ✅ Task 3: Integrated into `RunCommand.run()` — conditional monitor creation (`sharedSeatMode && !allowForeground && !dryrun`), seat baseline trace on creation, activity check before `.assistant` message handling, first-detection stderr warning, and `externallyModified` guard wrapping entire Memory extraction block.
- ✅ Task 4: Integrated into `AgentRunner.runAgent()` — same conditional monitor creation and activity check in API message stream.
- ✅ Task 5: Created 12 unit tests covering all ACs — describeBaseline formats, cursor movement detection (≥8px and <8px), frontmost app change, no-change nil, reported Set dedup, externallyModified flag, create() sampling, and trace event constants. All tests pass.

### File List

- `Sources/AxionCLI/Services/SeatActivityMonitor.swift` (NEW)
- `Sources/AxionCLI/Trace/TraceRecorder.swift` (MODIFIED)
- `Sources/AxionCLI/Commands/RunCommand.swift` (MODIFIED)
- `Sources/AxionCLI/API/AgentRunner.swift` (MODIFIED)
- `Sources/AxionCLI/API/AxionAPI.swift` (MODIFIED — review fix)
- `Tests/AxionCLITests/Services/SeatActivityMonitorTests.swift` (NEW)

## Change Log

- 2026-05-17: Story 13.4 implementation complete — SeatActivityMonitor actor detects external desktop operations during shared-seat runs and disables memory extraction to prevent corrupted learning
- 2026-05-17: **Senior Developer Review (AI)** — Found 4 issues (1 CRITICAL, 1 HIGH, 2 MEDIUM), all auto-fixed:
  - **C1**: AgentRunner `externallyModified` was dead code — added to return tuple so API callers can skip memory extraction. Updated completion callback signature and all 3 callers in AxionAPI.swift.
  - **H1**: AgentRunner missing trace events — added TraceRecorder creation, seat_baseline recording on monitor creation, and external_activity_detected recording on activity detection.
  - **M1**: RunCommand do-catch block inside `else` was mis-indented — fixed indentation for readability.
  - **M2**: Missing boundary test for exactly 8px cursor movement — added test case verifying detection triggers at exactly 8px threshold.
