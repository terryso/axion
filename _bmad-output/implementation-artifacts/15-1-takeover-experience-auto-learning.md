# Story 15.1: Takeover 经验自动学习

Status: done

## Story

As a 系统,
I want 用户手动接管后自动将接管经验转化为 Memory,
So that 人工干预成为可复用的自动化知识，减少未来同类任务被阻塞的概率.

## Acceptance Criteria

1. **AC1: Takeover 成功恢复自动记录 Memory**
   - **Given** 任务进入 takeover 状态，用户手动完成后按 Enter 恢复
   - **When** 系统恢复执行（`.resume` action）
   - **Then** 自动调用 Memory 系统，记录一条 takeover 学习（kind: affordance, confidence: 0.72, status: candidate）

2. **AC2: Takeover 成功恢复的 Memory 内容**
   - **Given** Takeover 成功恢复（用户按 Enter 或输入操作描述）
   - **When** 生成 Memory 条目
   - **Then** kind = affordance, description 格式为 "当被 {issue} 阻塞时，用户手动 {summary} 成功", confidence = 0.72, status = candidate, cause = "takeover_demonstration"

3. **AC3: Takeover 后任务仍失败记录 avoid**
   - **Given** Takeover 恢复后任务最终失败（run result 为 failed）
   - **When** 生成 Memory 条目
   - **Then** kind = avoid, description 格式为 "当被 {issue} 阻塞时，{summary} 未解决问题", confidence = 0.66, status = candidate, cause = "takeover_unresolved"

4. **AC4: Takeover 学习注入 Planner prompt**
   - **Given** Takeover 学习已记录
   - **When** 后续运行遇到同类 App 的任务
   - **Then** Planner prompt 中注入对应的 affordance/avoid 记忆（通过 `buildFactMemoryContext` 已有机制自动生效，无需额外代码）

5. **AC5: CLI `axion memory learn-takeover` 命令**
   - **Given** `axion memory learn-takeover --bundle-id com.apple.finder --issue "文件选择对话框无法通过 AX 定位" --summary "使用 Cmd+Shift+G 直接输入路径"`
   - **When** 手动记录 takeover 经验
   - **Then** 直接创建 Memory 条目（kind: affordance, confidence: 0.72, status: candidate），无需等待运行触发

6. **AC6: Memory 生命周期集成**
   - **Given** Takeover 学习以 candidate 状态写入
   - **When** 同一事实被后续运行重复观察（evidenceCount >= 2, confidence >= 0.65）
   - **Then** 通过 `MemoryLifecycleService` 自动提升为 active

7. **AC7: Takeover 学习失败不阻塞任务**
   - **Given** Memory 系统写入失败
   - **When** Takeover 学习记录过程中
   - **Then** 仅记录 warning 日志，不影响任务继续执行

8. **AC8: 尊重 --no-memory 标志**
   - **Given** 用户使用 `axion run "task" --no-memory`
   - **When** Takeover 发生并恢复
   - **Then** 不记录 takeover 学习（与现有 Memory 提取行为一致）

9. **AC9: 尊重外部桌面活动检测**
   - **Given** 运行过程中检测到外部桌面活动（`externallyModified = true`, Story 13.4）
   - **When** Takeover 恢复后
   - **Then** 不记录 takeover 学习（防止「污染证据」变成错误记忆）

10. **AC10: Codable round-trip**
    - **Given** TakeoverLearningFact 实例（如有新模型）
    - **When** JSON 编码再解码
    - **Then** 所有字段完整保留

## Tasks / Subtasks

- [x] Task 1: 创建 TakeoverLearningService (AC: #1, #2, #3, #5, #7)
  - [x] 1.1 新建 `Sources/AxionCLI/Memory/TakeoverLearningService.swift`
  - [x] 1.2 实现 `recordTakeoverLearning(bundleId:appName:task:issue:summary:outcome:reasonType:feedback:)` 方法
  - [x] 1.3 outcome 参数类型为 `TakeoverOutcome` 枚举（`.success`, `.failed`, `.cancelled`），默认 `.success`
  - [x] 1.4 根据 outcome 决定 kind（success → affordance, 其他 → avoid）和 confidence（success → 0.72, 其他 → 0.66）
  - [x] 1.5 构造 evidence 数组：`["task: {task}", "issue: {issue}", "reason_type: {reasonType}", "outcome: {outcome}", "takeover: {summary}", "feedback: {feedback}"]`（过滤 nil/空值）
  - [x] 1.6 构造 description：success → "当被 {issue} 阻塞时，用户手动 {summary} 成功", failed → "当被 {issue} 阻塞时，{summary} 未解决问题"
  - [x] 1.7 调用 `MemoryFactStore.save(domain:fact:)` 写入，使用 `MemoryLifecycleService.addFact` 处理合并
  - [x] 1.8 整个方法用 do/catch 包裹，catch 时仅 `fputs` warning，不 rethrow
  - [x] 1.9 scope 设为 "user takeover"，cause 设为 "takeover_demonstration" 或 "takeover_unresolved"

- [x] Task 2: 集成 Takeover 学习到 RunCommand (AC: #1, #8, #9)
  - [x] 2.1 在 RunCommand 的 `.paused` case 处理 `.resume` action 时，收集 takeover 上下文：issue（pausedData.reason）、summary（userAction）、completedSteps
  - [x] 2.2 将 takeover 上下文暂存到局部变量 `takeoverEvent: (issue: String, summary: String, domain: String?)?`
  - [x] 2.3 在任务完成后的 Memory 提取阶段，检查 `takeoverEvent` 是否存在
  - [x] 2.4 如果存在且 `!noMemory && !externallyModified`，调用 `TakeoverLearningService.recordTakeoverLearning()`
  - [x] 2.5 确定任务最终 outcome：如果 run 成功 → `.success`，如果 run 失败 → `.failed`
  - [x] 2.6 确定当前 App 的 bundleId：从最近执行的 `launch_app` 工具结果中提取 domain，或从 `takeoverEvent.domain` 获取
  - [x] 2.7 Takeover 学习写入独立于 AppMemoryExtractor 的 fact 提取（两者并存，不互相影响）

- [x] Task 3: 添加 `axion memory learn-takeover` CLI 子命令 (AC: #5)
  - [x] 3.1 新建 `Sources/AxionCLI/Commands/MemoryLearnTakeoverCommand.swift`
  - [x] 3.2 定义 `@ArgumentParser` struct `MemoryLearnTakeoverCommand`，实现 `ParsableCommand`
  - [x] 3.3 参数：`--bundle-id`（必需）、`--issue`（必需）、`--summary`（必需）、`--app-name`（可选）、`--task`（可选）、`--outcome`（可选，默认 success）
  - [x] 3.4 在 `run()` 中调用 `TakeoverLearningService.recordTakeoverLearning()`
  - [x] 3.5 输出确认消息：`"[axion] 已保存 takeover 学习到 {bundleId}"`
  - [x] 3.6 在 `MemoryCommand.swift` 中注册为子命令

- [x] Task 4: 单元测试 (All ACs)
  - [x] 4.1 新建 `Tests/AxionCLITests/Memory/TakeoverLearningServiceTests.swift`
  - [x] 4.2 测试 `recordTakeoverLearning` 成功 → affordance, confidence 0.72, cause "takeover_demonstration"
  - [x] 4.3 测试 `recordTakeoverLearning` 失败 → avoid, confidence 0.66, cause "takeover_unresolved"
  - [x] 4.4 测试 description 格式正确性（success/failed 两种模板）
  - [x] 4.5 测试 evidence 数组构造（过滤 nil/空值）
  - [x] 4.6 测试合并逻辑：同一事实再次 takeover 时 evidenceCount 累加
  - [x] 4.7 测试写入失败不抛异常（do/catch 防护）
  - [x] 4.8 新建 `Tests/AxionCLITests/Commands/MemoryLearnTakeoverCommandTests.swift`
  - [x] 4.9 测试 CLI 参数解析和调用（必需参数、可选参数、默认 outcome）
  - [x] 4.10 测试 `--outcome failed` 生成 avoid 类型

## Dev Notes

### 核心设计：Takeover 经验如何变成 Memory

本 Story 的核心是将 Takeover（用户手动接管）的经验记录为结构化的 `AppMemoryFact`。关键流程：

```
Takeover 发生 → 用户操作 → 按 Enter 恢复 → 记录 takeover 上下文
                                                   ↓
                              任务完成 → 判断最终 outcome（成功/失败）
                                                   ↓
                              调用 TakeoverLearningService → 写入 AppMemoryFact
                                                   ↓
                              后续运行 → buildFactMemoryContext 注入 Planner prompt
```

**与 OpenClick 的关键差异：**

| 方面 | OpenClick (TypeScript) | Axion (Swift) |
|------|----------------------|---------------|
| 触发机制 | 文件轮询 `TakeoverResumeMarker` + `waitForTakeoverResume()` | 直接在 SDK `.paused` 消息处理中内联（无需文件轮询） |
| 延迟记录 | `handleTakeoverResume()` 在恢复时立即记录 | 延迟到任务完成后记录（需要知道最终 outcome） |
| 数据模型 | `addAppMemoryFact()` 直接操作 JSON | `MemoryFactStore` actor + `MemoryLifecycleService` |
| 生命周期 | `maybePromoteFact()` 内联逻辑 | 已有 `MemoryLifecycleService.maybePromote()` |

### 插入点：RunCommand.swift

当前 takeover 恢复逻辑在 `RunCommand.swift:361-370`：

```swift
case .resume:
    let userAction = result.userInput?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? result.userInput! : "用户已完成手动操作"
    takeoverIO.write("[axion] 正在恢复执行...")
    agent.resume(context: userAction)
    await tracer?.record(event: "takeover_resumed", payload: [
        "context": userAction,
        "method": "resume"
    ])
```

**需要做的修改：**

1. 在此 case 块中新增局部变量暂存 takeover 信息：
   ```swift
   takeoverEvent = (issue: pausedData.reason, summary: userAction)
   ```

2. 在任务完成后（约 L430-502 的 Memory 提取段），在现有 fact 提取循环之前或之后，添加 takeover 学习记录：
   ```swift
   if let event = takeoverEvent, !noMemory, !externallyModified {
       let outcome: TakeoverOutcome = runSucceeded ? .success : .failed
       let service = TakeoverLearningService()
       let domain = inferDomainFromCollectedPairs()  // 从 collectedPairs 提取
       service.recordTakeoverLearning(
           bundleId: domain,
           issue: event.issue,
           summary: event.summary,
           outcome: outcome
       )
   }
   ```

3. 需要追踪 `runSucceeded` 布尔值（从 agent 最终结果推断）。

### TakeoverLearningService 设计

纯 Swift struct，无状态，通过构造函数注入 `MemoryFactStore` 和 `MemoryLifecycleService`：

```swift
struct TakeoverLearningService {
    let factStore: MemoryFactStore
    let lifecycleService: MemoryLifecycleService

    enum TakeoverOutcome: String, Codable {
        case success, failed, cancelled
    }

    func recordTakeoverLearning(
        bundleId: String,
        appName: String? = nil,
        task: String? = nil,
        issue: String,
        summary: String,
        outcome: TakeoverOutcome = .success,
        reasonType: String? = nil,
        feedback: String? = nil
    ) {
        // 1. Build kind + confidence based on outcome
        // 2. Build description from template
        // 3. Build evidence array (filter nil/empty)
        // 4. Create AppMemoryFact via AppMemoryFact.create(...)
        // 5. Load existing facts, merge via lifecycleService.addFact
        // 6. Save via factStore.save(domain:fact:)
        // Wrapped in do/catch, warning on failure
    }
}
```

### domain/bundleId 推断

RunCommand 已有 `collectedPairs`（tool-use/result 对），其中包含 `launch_app` 结果。可通过以下方式获取当前 domain：

1. 优先使用 takeover 恢复时最近活跃的 App（从 collectedPairs 中最后一个 `launch_app` 的 bundleId）
2. 也可利用 `MemoryContextProvider.appNameMap`（已有 16 个常见 macOS App 的 keyword → bundleId 映射）
3. 实现一个简单的 `inferDomain(from: [ToolUsePair]) -> String?` 辅助方法

### CLI 子命令注册

当前 `MemoryCommand` 子命令列表（`MemoryCommand.swift`）：
- `list` → `MemoryListCommand`
- `clear` → `MemoryClearCommand`
- `export` → `MemoryExportCommand`
- `import` → `MemoryImportCommand`

需要新增：
- `learn-takeover` → `MemoryLearnTakeoverCommand`

注册方式与其他子命令一致，在 `MemoryCommand` 的 `ParsableCommand` 实现中添加。

### 现有 Memory 系统已覆盖 AC4

AC4（Takeover 学习注入 Planner prompt）**不需要额外代码**。`MemoryContextProvider.buildFactMemoryContext()` 已读取所有 active facts（不限 kind），自动将 affordance 注入为"推荐路径"、avoid 注入为"注意事项"。只要 takeover 学习通过 `MemoryFactStore` 写入并经过 `MemoryLifecycleService` 提升，后续运行的 Planner 就会自动获取这些记忆。

### 现有 Memory 系统已覆盖 AC6

AC6（Memory 生命周期集成）**不需要额外代码**。`MemoryLifecycleService.addFact()` 已实现 candidate → active 提升（evidenceCount >= 2, confidence >= 0.65 + boost 0.1）。Takeover 学习作为 candidate 写入后，如果后续 takeover 或普通运行观察到相同事实，会自动合并和提升。

### 项目结构规范

```
Sources/AxionCLI/
├── Memory/
│   ├── TakeoverLearningService.swift    # 新增（本 Story）
│   ├── AppMemoryFact.swift              # 已有（Epic 12）
│   ├── MemoryFactStore.swift            # 已有（Epic 12）
│   ├── MemoryLifecycleService.swift     # 已有（Epic 12）
│   ├── MemoryContextProvider.swift       # 已有（Epic 4/12）
│   └── AppMemoryExtractor.swift         # 已有（Epic 4/12）
├── Commands/
│   ├── RunCommand.swift                 # 修改：添加 takeover 学习记录
│   ├── MemoryCommand.swift              # 修改：注册 learn-takeover 子命令
│   └── MemoryLearnTakeoverCommand.swift # 新增（本 Story）
└── IO/
    └── TakeoverIO.swift                 # 已有（Epic 7），不需修改

Tests/AxionCLITests/
├── Memory/
│   └── TakeoverLearningServiceTests.swift  # 新增（本 Story）
└── Commands/
    └── MemoryLearnTakeoverCommandTests.swift  # 新增（本 Story）
```

### 测试策略

- Swift Testing 框架（`import Testing`, `@Suite`, `@Test`, `#expect`）
- `TakeoverLearningServiceTests` 使用真实 `MemoryFactStore`（临时目录），验证 fact 写入、kind/confidence/cause/evidence 正确性
- `MemoryLearnTakeoverCommandTests` 验证参数解析和命令执行（可通过 mock 或真实临时目录）
- 已有测试文件参考模式：`AppMemoryFactTests.swift`, `MemoryFactStoreTests.swift`, `MemoryLifecycleServiceTests.swift`

### 前一个 Story 经验

- Epic 13/14 已建立成熟的 Memory 生命周期管线
- `MemoryFactStore` 是 actor 隔离的，测试中需 `await` 调用
- `AppMemoryFact.create()` 是工厂方法，自动设置 factId（djb2 hash）、updatedAt、默认值
- Memory 操作失败不应阻塞主流程（do/catch + warning 模式，参见 RunCommand L434-501）
- `collectedPairs` 在 RunCommand 中已是局部变量，可在 Memory 提取阶段访问
- `noMemory` 和 `externallyModified` 标志已控制 Memory 提取行为，takeover 学习应复用相同守卫

### 反模式提醒

- **禁止**实现文件轮询机制 — OpenClick 用 `waitForTakeoverResume()` 轮询 marker 文件，Axion 直接在 SDK 消息处理中内联，无需轮询
- **禁止**创建新的 Memory 存储层 — 使用现有 `MemoryFactStore` + `MemoryLifecycleService`
- **禁止**在 takeover 学习中使用与 `AppMemoryExtractor` 不同的 factId 算法 — 必须使用 `AppMemoryFact.factId(kind:description:)` 确保 dedup
- **禁止**在 TakeoverIO 中添加 Memory 逻辑 — TakeoverIO 只负责 I/O，Memory 逻辑在 RunCommand 或 TakeoverLearningService 中
- **禁止**跳过 `noMemory` 和 `externallyModified` 守卫 — takeover 学习必须与现有 Memory 提取受相同约束
- **禁止**在 takeover 恢复时立即记录 — 需等到任务完成以确定最终 outcome（成功 → affordance, 失败 → avoid）

### References

- [Source: epics.md — Epic 15 Story 15.1 Takeover 经验自动学习]
- [Source: OpenClick src/memory.ts:48-86 — recordTakeoverLearning() 函数]
- [Source: OpenClick src/cli.ts:239-258 — memory learn-takeover CLI 命令]
- [Source: OpenClick src/run.ts:417-440 — handleTakeoverResume() 函数]
- [Source: OpenClick src/trace.ts:53-70 — TakeoverResumeMarker 接口]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift:349-384 — Takeover SDK .paused 消息处理]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift:430-502 — Memory 提取阶段]
- [Source: Sources/AxionCLI/Memory/AppMemoryFact.swift — AppMemoryFact 模型 + factId + create]
- [Source: Sources/AxionCLI/Memory/MemoryFactStore.swift — actor 持久化层]
- [Source: Sources/AxionCLI/Memory/MemoryLifecycleService.swift — 生命周期管理]
- [Source: Sources/AxionCLI/Memory/MemoryContextProvider.swift — Memory prompt 注入]
- [Source: Sources/AxionCLI/IO/TakeoverIO.swift — Takeover 终端 I/O]
- [Source: Sources/AxionCLI/Commands/MemoryCommand.swift — Memory CLI 子命令注册]
- [Source: project-context.md — Memory 系统架构]

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

None.

### Completion Notes List

- Implemented TakeoverLearningService with TakeoverOutcome enum, async recordTakeoverLearning method
- Integrated takeover event capture in RunCommand .paused/.resume handler
- Added runSucceeded tracking via .result message subtype
- Added inferDomain(from:) helper to extract bundleId from collectedPairs
- Takeover learning recorded after memory extraction, guarded by !noMemory && !externallyModified
- Created MemoryLearnTakeoverCommand with --bundle-id, --issue, --summary, --outcome options
- Registered learn-takeover as subcommand of MemoryCommand
- 15 unit tests all passing (TakeoverLearningServiceTests + MemoryLearnTakeoverCommandTests)
- AC4 and AC6 covered by existing MemoryLifecycleService and MemoryContextProvider (no code needed)
- Pre-existing test failures in AxionAPISkillRoutesTests (4 issues) are unrelated to this story

### Senior Developer Review (AI)

**Reviewed:** 2026-05-17
**Outcome:** Approved with fixes applied

**Issues Found:** 1 High, 2 Medium, 2 Low → All HIGH and MEDIUM auto-fixed

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| H1 | HIGH | Takeover learning inside same do/catch as memory extraction — extraction failure silently skips takeover | Moved takeover learning block outside do/catch |
| M1 | MEDIUM | `inferDomain` discards toolUse, does O(n²) search | Use tuple's toolUse directly |
| M2 | MEDIUM | Cancelled runs generate incorrect avoid fact | Added `runCompleted` flag; skip learning for non-completed runs |
| L1 | LOW | No test for `TakeoverOutcome.cancelled` | Added test |
| L2 | LOW | `resolveMemoryDir()` duplicates path logic | Noted, accepted for single-use case |

**Tests after fixes:** 16 passing (added cancelled outcome test)

### File List

- Sources/AxionCLI/Memory/TakeoverLearningService.swift (new)
- Sources/AxionCLI/Commands/MemoryLearnTakeoverCommand.swift (new)
- Sources/AxionCLI/Commands/RunCommand.swift (modified: takeover event capture + learning recording + inferDomain helper)
- Sources/AxionCLI/Commands/MemoryCommand.swift (modified: registered learn-takeover subcommand)
- Tests/AxionCLITests/Memory/TakeoverLearningServiceTests.swift (new)
- Tests/AxionCLITests/Commands/MemoryLearnTakeoverCommandTests.swift (new)

## Change Log

- 2026-05-17: Story 15.1 创建 — Takeover 经验自动学习
- 2026-05-17: Story 15.1 实施完成 — TakeoverLearningService + RunCommand 集成 + CLI 子命令 + 15 测试全部通过
- 2026-05-17: Senior Developer Review — 5 issues found (1H/2M/2L), all H+M auto-fixed, 16 tests passing, status → done
