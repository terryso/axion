# Story 16.2: API Server 持久化运行恢复

Status: done

## Story

As a 系统,
I want API server 重启后能恢复之前运行中的任务状态,
So that daemon 模式下的重启不会留下僵尸任务.

## Acceptance Criteria

1. **AC1: 运行状态持久化写入**
   - **Given** API server 有正在运行的异步任务
   - **When** 任务状态发生变更（submit / update / intervention）
   - **Then** 将 `TrackedRun` 序列化为 JSON 写入 `~/.axion/runs/{runId}/api-output.json`

2. **AC2: SSE 事件持久化写入**
   - **Given** SSE 事件被 emit 到 EventBroadcaster
   - **When** 事件广播
   - **Then** 将 SSEEvent 追加写入 `~/.axion/runs/{runId}/api-events.jsonl`（每行一个 JSON）

3. **AC3: Server 启动时加载持久化记录**
   - **Given** API server 重启
   - **When** ServerCommand 初始化 RunTracker
   - **Then** 扫描 `~/.axion/runs/` 目录，从 `api-output.json` 加载所有持久化的 TrackedRun

4. **AC4: 运行中任务自动标记为 failed**
   - **Given** 持久化状态中 status = "running" / "queued" / "resuming" / "user_takeover"
   - **When** 恢复检查
   - **Then** 标记为 `failed`，error = "server interrupted"，更新 api-output.json

5. **AC5: intervention_needed 状态保持**
   - **Given** 持久化状态中 status = "intervention_needed"
   - **When** 恢复
   - **Then** 保持 `intervention_needed` 状态不变，等待用户通过 AxionBar 或 CLI 处理

6. **AC6: SSE 历史事件重放**
   - **Given** 新的 SSE 连接订阅已恢复的任务
   - **When** 发送历史事件
   - **Then** 从 `api-events.jsonl` 读取所有历史事件，重放到 SSE 流，然后继续推送新事件

7. **AC7: 持久化失败不阻塞主流程**
   - **Given** 磁盘写入失败（权限、空间不足等）
   - **When** 持久化操作
   - **Then** 记录 warning 日志，不阻塞任务提交和执行

## Tasks / Subtasks

- [x] Task 1: 创建 RunPersistenceService 持久化服务 (AC: #1, #2, #7)
  - [x] 1.1 新建 `Sources/AxionCLI/API/RunPersistenceService.swift`
  - [x] 1.2 定义 `RunPersistenceService: Sendable`（非 actor，方法为纯函数调用，内部使用 FileManager）
  - [x] 1.3 实现 `runsDirectory() -> String` — 返回 `~/.axion/api-runs/`（与 CLI trace 的 `~/.axion/runs/` 分开，避免混淆）
  - [x] 1.4 实现 `runDirectory(runId:) -> String` — 返回 `~/.axion/api-runs/{runId}/`，自动创建目录
  - [x] 1.5 实现 `persistRecord(_ run: TrackedRun) throws` — 将 TrackedRun 编码为 JSON，原子写入 `api-output.json`（先写临时文件再 rename）
  - [x] 1.6 实现 `persistEvent(runId: String, event: SSEEvent) throws` — 将 SSEEvent 编码为 JSON，追加到 `api-events.jsonl`
  - [x] 1.7 实现 `loadRecord(runId: String) -> TrackedRun?` — 从 `api-output.json` 加载 TrackedRun
  - [x] 1.8 实现 `loadEvents(runId: String) -> [SSEEvent]` — 从 `api-events.jsonl` 逐行解码 SSEEvent
  - [x] 1.9 实现 `loadAllPersistedRuns() -> [TrackedRun]` — 扫描 `~/.axion/api-runs/` 所有子目录，加载全部 TrackedRun
  - [x] 1.10 实现安全包装方法 `persistRecordSafely(_:)` 和 `persistEventSafely(runId:event:)` — catch + print warning，不抛出

- [x] Task 2: RunTracker 集成持久化 (AC: #1)
  - [x] 2.1 修改 `RunTracker`，添加 `private let persistenceService: RunPersistenceService?` 属性
  - [x] 2.2 修改 `init`，接受可选 `persistenceService` 参数
  - [x] 2.3 在 `submitRun()` 末尾调用 `persistenceService?.persistRecordSafely(run)`
  - [x] 2.4 在 `updateRun()` 末尾调用 `persistenceService?.persistRecordSafely(runs[runId])`
  - [x] 2.5 在 `updateRunResult()` 末尾调用 `persistenceService?.persistRecordSafely(runs[runId])`
  - [x] 2.6 在 `updateRunIntervention()` 末尾调用 `persistenceService?.persistRecordSafely(runs[runId])`

- [x] Task 3: EventBroadcaster 集成持久化 (AC: #2)
  - [x] 3.1 修改 `EventBroadcaster`，添加 `private let persistenceService: RunPersistenceService?` 属性
  - [x] 3.2 修改 `init`，接受可选 `persistenceService` 参数
  - [x] 3.3 在 `emit()` 方法中追加 `persistenceService?.persistEventSafely(runId:event:)` 调用

- [x] Task 4: 恢复逻辑 — RunRecoveryService (AC: #3, #4, #5)
  - [x] 4.1 新建 `Sources/AxionCLI/API/RunRecoveryService.swift`
  - [x] 4.2 实现 `static func recover(from tracker: RunTracker, persistenceService: RunPersistenceService) async` — 扫描所有持久化记录，注入到 RunTracker
  - [x] 4.3 对每个加载的 TrackedRun，判断状态：
    - `running` / `queued` / `resuming` / `userTakeover` → 改为 `failed`，error = "server interrupted"，写回 `api-output.json`
    - `interventionNeeded` → 保持不变
    - `completed` / `failed` / `cancelled` → 保持不变
  - [x] 4.4 将恢复的 TrackedRun 注入 RunTracker（新增 `restoreRun(_: TrackedRun)` 方法）
  - [x] 4.5 对恢复的运行中任务，加载 `api-events.jsonl` 中的历史事件到 EventBroadcaster 的 replay buffer（新增 `restoreReplayBuffer(runId:events:)` 方法）

- [x] Task 5: ServerCommand 启动集成 (AC: #3)
  - [x] 5.1 修改 `ServerCommand.swift`，在创建 RunTracker 和 EventBroadcaster 时注入 RunPersistenceService
  - [x] 5.2 在 server 启动路由注册之前，调用 `RunRecoveryService.recover(from:tracker:persistenceService:)` 恢复任务
  - [x] 5.3 将 RunPersistenceService 传入 AxionAPI.registerRoutes 的参数链

- [x] Task 6: SSE 事件磁盘重放集成 (AC: #6)
  - [x] 6.1 修改 `EventBroadcaster`，添加 `restoreReplayBuffer(runId: String, events: [SSEEvent])` 方法
  - [x] 6.2 在 SSE 路由中，如果内存 replay buffer 为空但 `api-events.jsonl` 存在，从磁盘加载历史事件重放
  - [x] 6.3 SSE endpoint 的 `subscribeWithReplay` 优先从磁盘加载（如果内存 replay buffer 为空）

- [x] Task 7: 单元测试 (All ACs)
  - [x] 7.1 新建 `Tests/AxionCLITests/API/RunPersistenceServiceTests.swift`
  - [x] 7.2 测试 `persistRecord` + `loadRecord` round-trip：写入 TrackedRun，读回，验证所有字段一致
  - [x] 7.3 测试 `persistEvent` + `loadEvents`：追加多个 SSEEvent，读回，验证顺序和内容
  - [x] 7.4 测试原子写入：验证写入的是 `api-output.json` 而非临时文件
  - [x] 7.5 测试 `loadAllPersistedRuns`：创建多个 run 目录，验证全部加载
  - [x] 7.6 测试持久化失败不崩溃：使用无效路径，验证 `persistRecordSafely` 不抛出
  - [x] 7.7 测试恢复逻辑：创建 running/queued 状态的持久化记录，recover 后验证变为 failed
  - [x] 7.8 测试 intervention_needed 不变：恢复后状态保持
  - [x] 7.9 测试 completed/failed/cancelled 不变：恢复后状态保持
  - [x] 7.10 测试 RunTracker 集成：submitRun/updateRun 后验证 api-output.json 文件存在且内容正确
  - [x] 7.11 测试 EventBroadcaster 集成：emit 后验证 api-events.jsonl 文件存在且内容正确
  - [x] 7.12 测试 SSE 历史重放：从 api-events.jsonl 加载事件到 replay buffer

## Dev Notes

### 核心设计：任务状态持久化与恢复

本 Story 为 API server 添加磁盘持久化，确保 daemon 模式下（Story 16.1）server 崩溃/重启后能恢复任务状态。参考 OpenClick `src/api-runs.ts` 的实现模式，适配为 Swift。

**OpenClick 参考映射：**

| Axion 文件 | 参考 OpenClick 文件 | 提取什么 |
|-----------|-------------------|---------|
| `RunPersistenceService.swift` | `src/api-runs.ts:460-464` | `persistRecord()` — 将 StandardTaskOutput 写入 `api-output.json` |
| `RunPersistenceService.swift` | `src/api-runs.ts:466-469` | `persistEvent()` — 将 ApiRunEvent 追加写入 `api-events.jsonl` |
| `RunPersistenceService.swift` | `src/api-runs.ts:472-490` | `loadPersistedRecord()` — 从文件加载记录和事件，重建状态 |
| `RunRecoveryService.swift` | `src/api-runs.ts:273-292` | `recoverLoadedRecord()` — 对 running/queued 状态标记为 failed |

### 存储路径设计

**关键决策：使用 `~/.axion/api-runs/` 而非 `~/.axion/runs/`**

- CLI trace 使用 `~/.axion/runs/{runId}/trace.jsonl`（由 TraceRecorder 管理）
- API 运行状态使用 `~/.axion/api-runs/{runId}/api-output.json` 和 `api-events.jsonl`
- 两者分开，避免 CLI trace 和 API 状态文件混在同一个目录
- RunTracker 和 CLI 的 TraceRecorder 互不干扰

```
~/.axion/
├── api-runs/                          # API 持久化目录（本 Story 新增）
│   ├── 20260517-abc123/
│   │   ├── api-output.json            # TrackedRun JSON（每次 update 原子覆写）
│   │   └── api-events.jsonl           # SSE 事件追加写入
│   └── 20260517-def456/
│       ├── api-output.json
│       └── api-events.jsonl
├── runs/                              # CLI trace 目录（已有，TraceRecorder 使用）
│   └── {runId}/
│       └── trace.jsonl
├── config.json
├── memory/
└── ...
```

### 原子写入策略

`api-output.json` 使用原子写入避免损坏：
1. 写入临时文件 `api-output.json.tmp`
2. `FileManager.moveItem` 覆盖 `api-output.json`
3. rename 是原子操作（POSIX 保证同文件系统下 rename 原子性）

```swift
func persistRecord(_ run: TrackedRun) throws {
    let dir = runDirectory(runId: run.runId)
    let tmpPath = (dir as NSString).appendingPathComponent("api-output.json.tmp")
    let finalPath = (dir as NSString).appendingPathComponent("api-output.json")

    let data = try JSONEncoder().encode(run)
    try data.write(to: URL(fileURLWithPath: tmpPath), options: .atomic)
    // .atomic 已经做了 write-to-tmp + rename
}
```

### SSEEvent 编码为 JSONL

SSEEvent 是 enum，需要先转为可编码的中间类型再写入 JSONL：

```swift
// SSEEvent 已有各 case 的 Data payload (StepStartedData, StepCompletedData, RunCompletedData)
// 持久化时保存 { "event_type": "step_started", ...payload }
struct PersistedSSEEvent: Codable {
    let eventType: String
    let stepStarted: StepStartedData?
    let stepCompleted: StepCompletedData?
    let runCompleted: RunCompletedData?
}
```

或者更简洁的方式：直接将 SSEEvent 的 eventType + encoded data 拼为一个 Codable wrapper。

### 恢复状态映射

OpenClick 的 `recoverLoadedRecord()` 逻辑：

| 恢复前状态 | 恢复后状态 | 说明 |
|-----------|-----------|------|
| `queued` | `failed` | 未开始执行，标记中断 |
| `running` | `failed` | 执行中被中断 |
| `resuming` | `failed` | takeover 恢复中被中断 |
| `user_takeover` | `failed` | 用户接管期间中断 |
| `intervention_needed` | `intervention_needed` | 保持，等待用户处理 |
| `completed` | `completed` | 已完成，不变 |
| `failed` | `failed` | 已失败，不变 |
| `cancelled` | `cancelled` | 已取消，不变 |

### RunTracker 新增方法

```swift
/// 恢复一个持久化的 run 到内存（不生成新 ID，使用原 ID）。
/// 仅在 server 启动恢复时调用。
func restoreRun(_ run: TrackedRun) {
    runs[run.runId] = run
}
```

### EventBroadcaster 新增方法

```swift
/// 恢复持久化的事件到 replay buffer。
/// 在 server 启动恢复时调用，使 SSE 订阅者能获取历史事件。
func restoreReplayBuffer(runId: String, events: [SSEEvent]) {
    replayBuffer[runId] = events
}
```

### ServerCommand 启动流程变更

```
ServerCommand.run()
    │
    ├── ConfigManager.loadConfig()
    │
    ├── RunPersistenceService()                        # 新增：创建持久化服务
    ├── RunTracker(eventBroadcaster: broadcaster,      # 修改：传入 persistenceService
    │              persistenceService: persistence)
    ├── EventBroadcaster(persistenceService: persistence)  # 修改：传入 persistenceService
    │
    ├── RunRecoveryService.recover(from: tracker,      # 新增：启动时恢复
    │                               persistenceService: persistence,
    │                               eventBroadcaster: broadcaster)
    │
    └── AxionAPI.registerRoutes(...)                   # 不变
```

### 现有文件需要修改

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/AxionCLI/API/RunTracker.swift` | 修改 | 添加 persistenceService 属性，submitRun/updateRun/updateRunResult/updateRunIntervention 中触发持久化，新增 restoreRun 方法 |
| `Sources/AxionCLI/API/EventBroadcaster.swift` | 修改 | 添加 persistenceService 属性，emit 中触发事件持久化，新增 restoreReplayBuffer 方法 |
| `Sources/AxionCLI/Commands/ServerCommand.swift` | 修改 | 创建 RunPersistenceService，注入到 RunTracker/EventBroadcaster，启动时调用恢复逻辑 |

### 新增文件

| 文件 | 说明 |
|------|------|
| `Sources/AxionCLI/API/RunPersistenceService.swift` | 磁盘持久化：写入/加载 TrackedRun 和 SSEEvent |
| `Sources/AxionCLI/API/RunRecoveryService.swift` | 恢复逻辑：扫描磁盘记录，注入 RunTracker，标记中断任务 |
| `Tests/AxionCLITests/API/RunPersistenceServiceTests.swift` | 持久化和恢复测试 |

### 项目结构

```
Sources/AxionCLI/API/
├── RunTracker.swift                    # 修改：注入持久化
├── EventBroadcaster.swift              # 修改：注入持久化
├── RunPersistenceService.swift         # 新增（本 Story）
├── RunRecoveryService.swift            # 新增（本 Story）
├── AgentRunner.swift                   # 不变
├── AxionAPI.swift                      # 不变
├── ConcurrencyLimiter.swift            # 不变
├── AuthMiddleware.swift                # 不变
└── Models/APITypes.swift              # 不变

Sources/AxionCLI/Commands/
└── ServerCommand.swift                 # 修改：启动恢复流程

Tests/AxionCLITests/API/
├── RunTrackerTests.swift               # 可能需扩展：restoreRun 测试
├── EventBroadcasterTests.swift         # 可能需扩展：restoreReplayBuffer 测试
└── RunPersistenceServiceTests.swift    # 新增（本 Story）
```

### 测试策略

- Swift Testing 框架（`import Testing`, `@Suite`, `@Test`, `#expect`）
- 所有测试使用临时目录（`NSTemporaryDirectory` + UUID 子目录），不写入真实 `~/.axion/`
- RunPersistenceServiceTests 测试：
  - persistRecord + loadRecord round-trip
  - persistEvent + loadEvents（多事件追加和读取）
  - 原子写入验证
  - loadAllPersistedRuns（多个 run 目录）
  - 持久化失败容错（无效路径）
- RunRecoveryService 逻辑通过注入 mock RunTracker + mock PersistenceService 测试
  - 验证 running → failed 转换
  - 验证 intervention_needed 保持不变
  - 验证 completed/failed/cancelled 保持不变
- RunTracker 已有测试需扩展：验证持久化调用（通过注入 mock PersistenceService）
- EventBroadcaster 已有测试需扩展：验证持久化调用

### 与 Story 16.1 的集成

- Story 16.1 实现了 `axion daemon install`，将 server 注册为 launchd 守护进程
- 本 Story 确保守护进程崩溃/重启后任务状态可恢复
- 两者配合：daemon 自动重启（16.1） + 重启后状态恢复（16.2）= 生产级可靠性

### 前一个 Story 经验（Story 16.1）

- DaemonService 使用注入 `@Sendable` 闭包实现可测试性 — RunPersistenceService 可考虑类似模式
- XML 转义辅助方法放在 struct 内部 — RunPersistenceService 的文件操作方法也应该是 static 或 struct 方法
- 文件路径使用 `NSString.appendingPathComponent` — 不使用字符串拼接
- 文件操作先创建目录再写入 — `persistRecord` 必须先确保 run 目录存在
- Story 16.1 新增了 DaemonService + DaemonCommand，本 Story 的 RunPersistenceService 独立于 daemon 功能

### 反模式提醒

- **禁止**修改 AgentRunner 的核心执行逻辑 — 只修改 RunTracker/EventBroadcaster 的状态管理
- **禁止**在 AxionAPI 路由中直接调用持久化 — 持久化由 RunTracker/EventBroadcaster 内部触发
- **禁止**创建新的错误类型体系 — 使用 print + warning 日志处理持久化失败
- **禁止**在测试中写入真实 `~/.axion/` 目录 — 使用临时目录
- **禁止**同步文件 I/O 阻塞 actor 方法 — FileManager 操作在 actor 内是同步的但很快（JSON < 100KB），可接受
- **禁止**修改 TrackedRun 或 StandardTaskOutput 的字段结构 — 本 Story 只添加持久化行为，不改模型
- **禁止**修改 SSE 事件的格式 — api-events.jsonl 中的 JSON 是 SSEEvent 的内部表示，不是 SSE 文本格式
- **禁止**使用 `api-runs` 作为 CLI trace 的目录 — 与 TraceRecorder 的 `runs` 目录分开

### 性能考量

- `api-output.json` 每次状态更新覆写（不是追加），文件很小（< 50KB）
- `api-events.jsonl` 追加写入，每次事件 < 1KB
- 恢复时扫描目录只在启动时执行一次，不影响运行时性能
- 满足 NFR41: StandardTaskOutput 序列化/反序列化 < 5ms（已有，本 Story 不改变）
- 满足 NFR40: Daemon 崩溃到自动重启 < 15 秒（16.1 保证），恢复加载应 < 1 秒

### References

- [Source: epics.md — Epic 16 Story 16.2 API Server 持久化运行恢复]
- [Source: OpenClick src/api-runs.ts:460-464 — persistRecord() 函数]
- [Source: OpenClick src/api-runs.ts:466-469 — persistEvent() 函数]
- [Source: OpenClick src/api-runs.ts:472-490 — loadPersistedRecord() 函数]
- [Source: OpenClick src/api-runs.ts:262-271 — getOrLoadRecord() 内存/磁盘双层查询]
- [Source: OpenClick src/api-runs.ts:273-292 — recoverLoadedRecord() 中断任务恢复逻辑]
- [Source: Sources/AxionCLI/API/RunTracker.swift — 现有内存任务追踪]
- [Source: Sources/AxionCLI/API/EventBroadcaster.swift — 现有 SSE 事件广播]
- [Source: Sources/AxionCLI/API/Models/APITypes.swift — TrackedRun, SSEEvent, APIRunStatus 模型]
- [Source: Sources/AxionCLI/Commands/ServerCommand.swift — 现有 server 启动逻辑]
- [Source: _bmad-output/implementation-artifacts/16-1-launchd-daemon-support.md — 前一个 Story 完成记录]
- [Source: _bmad-output/planning-artifacts/architecture.md — 项目结构与 API 模块定义]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- Implemented RunPersistenceService as a Sendable struct with configurable base directory (default ~/.axion/api-runs/)
- Created PersistedSSEEvent Codable wrapper to bridge SSEEvent enum to JSONL format
- Integrated persistence into RunTracker via optional injection: submitRun, updateRun, updateRunResult, updateRunIntervention all persist records
- Integrated persistence into EventBroadcaster: emit() now appends events to api-events.jsonl
- Created RunRecoveryService as an enum with static recover() method for startup recovery
- Recovery marks running/queued/resuming/userTakeover as failed with "server interrupted" error
- Recovery preserves interventionNeeded, completed, failed, cancelled states unchanged
- Added restoreRun() to RunTracker and restoreReplayBuffer() to EventBroadcaster for recovery injection
- subscribeWithReplay now falls back to disk loading when memory buffer is empty
- ServerCommand creates RunPersistenceService and runs recovery before route registration
- All 22 tests pass (20 new + 2 backward compat); all existing RunTracker and EventBroadcaster tests still pass (no regressions)
- 5 pre-existing test failures in unrelated suites (AxionAPISkillRoutes, ConfigManager) confirmed not caused by this story

### Senior Developer Review (AI)

**Reviewer:** terryso on 2026-05-17
**Outcome:** Approved (with auto-fixes applied)

**Findings (3 total, all fixed):**

1. **[MEDIUM] subscribeWithReplay disk fallback not cached in replayBuffer** (EventBroadcaster.swift:57)
   - Each new subscriber for an unbuffered runId triggered a fresh disk read instead of caching the loaded events.
   - **Fix:** Changed to check `replayBuffer` first, then load from disk and populate `replayBuffer` on first load, so subsequent subscribers get the cached version.

2. **[MEDIUM] Missing tests for resuming/userTakeover recovery** (RunPersistenceServiceTests.swift)
   - AC4 explicitly requires resuming and userTakeover states to be marked as failed on recovery, but only running/queued were tested.
   - **Fix:** Added `recoveryMarksResumingAsFailed` and `recoveryMarksUserTakeoverAsFailed` tests.

3. **[LOW] Dev notes test count inaccurate** (story Completion Notes)
   - Claimed 17 tests but file had 20. Updated to reflect actual count (22 after review fixes).

**Test Results:** 22/22 pass (RunPersistenceService), 29/29 pass (RunTracker + EventBroadcaster). Zero regressions.

### Change Log

- 2026-05-17: Story 16.2 implementation complete — API server persistence and recovery for daemon mode
- 2026-05-17: Senior Developer Review — 3 issues found and auto-fixed (disk cache, missing tests, doc accuracy)

### File List

- `Sources/AxionCLI/API/RunPersistenceService.swift` — 新增：磁盘持久化服务（TrackedRun + SSEEvent 读写）
- `Sources/AxionCLI/API/RunRecoveryService.swift` — 新增：启动恢复逻辑（状态映射 + replay buffer 恢复）
- `Sources/AxionCLI/API/RunTracker.swift` — 修改：添加 persistenceService 注入 + restoreRun 方法
- `Sources/AxionCLI/API/EventBroadcaster.swift` — 修改：添加 persistenceService 注入 + restoreReplayBuffer + subscribeWithReplay 磁盘缓存回退
- `Sources/AxionCLI/Commands/ServerCommand.swift` — 修改：创建 RunPersistenceService 并在启动时执行恢复
- `Tests/AxionCLITests/API/RunPersistenceServiceTests.swift` — 新增：22 个测试覆盖所有 AC（含 review 补充的 2 个）
