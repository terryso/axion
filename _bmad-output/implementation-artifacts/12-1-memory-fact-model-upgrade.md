# Story 12.1: Memory Fact 模型升级

Status: done

## Story

As a 系统,
I want Memory 条目有生命周期状态和置信度评分,
So that 记忆质量随使用不断提升，一次性失败不会产生错误的长期记忆.

## Acceptance Criteria

1. **AC1: AppMemoryFact 模型定义**
   Given 当前 KnowledgeEntry 模型（SDK `MemoryTypes.swift`，不可修改）
   When 在 AxionCLI 层定义新的 AppMemoryFact 模型
   Then 新增字段：status（candidate/active/retired）、confidence（Double 0.0-1.0）、evidenceCount（Int）、source（local/imported）、scope（可选 String）、cause（可选 String）、kind（affordance/avoid/observation）、updatedAt（Date）、evidence（[String]）
   And AppMemoryFact 遵循 Codable + Equatable + Sendable

2. **AC2: 新记忆以 candidate 状态写入**
   Given 一次任务执行产生新的记忆
   When AppMemoryExtractor 提取 App 操作模式
   Then 新记忆以 candidate 状态写入，confidence 初始值 0.5-0.7（根据操作复杂度调整：成功 0.7，失败 0.5，含 workaround 0.6）

3. **AC3: evidence_count 累积自动提升**
   Given 同一事实被后续运行重复观察到
   When evidenceCount 累积到 >= 2 且 confidence >= 0.65
   Then 自动提升为 active 状态，confidence 提升 0.1（上限 1.0）

4. **AC4: 矛盾事实处理**
   Given 同一事实的后续观察与已有记忆矛盾
   When 冲突检测（同 domain + 同 description 但不同 kind 或不同 success/failure 标记）
   Then 不自动覆盖，而是创建新的 candidate 条目，由证据累积决定最终状态

5. **AC5: 30 天未验证自动降级**
   Given active 状态的记忆连续 30 天未被验证
   When MemoryLifecycleService 执行定期检查
   Then 自动降级为 retired 状态

6. **AC6: retired 状态可重新激活**
   Given retired 状态的记忆再次被观察到
   When 同 description 的事实再次产生
   Then 恢复为 candidate 状态，evidenceCount 重置为 1

7. **AC7: 现有记忆数据兼容**
   Given ~/.axion/memory/ 中已有的 KnowledgeEntry JSON 文件
   When 首次运行升级后系统
   Then 现有数据可被读取，迁移策略为：旧条目作为 observation + candidate + confidence 0.5 导入（惰性迁移，读时升级）

8. **AC8: MemoryLifecycleService 替代 MemoryCleanupService**
   Given 现有 MemoryCleanupService（仅按时间删除）
   When 新的 MemoryLifecycleService 接管
   Then 旧 MemoryCleanupService 保留但不再主动调用，新服务负责 candidate→active 提升、active→retired 降级、retired 重新激活

## Tasks / Subtasks

- [x] Task 1: 定义 AppMemoryFact 模型 (AC: #1)
  - [x] 1.1 在 `Sources/AxionCLI/Memory/` 新建 `AppMemoryFact.swift`
  - [x] 1.2 定义 `MemoryFactStatus` 枚举（candidate/active/retired, String, Codable）
  - [x] 1.3 定义 `MemoryFactSource` 枚举（local/imported, String, Codable）
  - [x] 1.4 定义 `MemoryKind` 枚举（affordance/avoid/observation, String, Codable）
  - [x] 1.5 定义 `AppMemoryFact` struct（Codable + Equatable + Sendable）
  - [x] 1.6 实现 `normalizeFact()` 静态方法：校验 confidence [0,1]，evidenceCount >= 0，默认 status 为 candidate
  - [x] 1.7 实现 `factId(kind:description:)` 生成确定性 ID（hash(description)）

- [x] Task 2: 实现 MemoryLifecycleService (AC: #3, #5, #6, #8)
  - [x] 2.1 在 `Sources/AxionCLI/Memory/` 新建 `MemoryLifecycleService.swift`
  - [x] 2.2 实现 `addFact(domain:kind:description:confidence:scope:cause:)` — 新增或合并记忆
  - [x] 2.3 实现 `mergeFact(existing:incoming:)` — 合并策略：max confidence、累加 evidenceCount、保留最新 updatedAt
  - [x] 2.4 实现 `maybePromote(fact:)` — evidenceCount >= 2 且 confidence >= 0.65 时 promoteToActive
  - [x] 2.5 实现 `demoteRetired(facts:lastVerifiedBefore:)` — 30 天未验证降级
  - [x] 2.6 实现 `reactivateRetired(fact:)` — retired→candidate，evidenceCount 重置为 1
  - [x] 2.7 实现 `selectActiveFacts(domain:)` — 只返回 active 状态的记忆，按 confidence 降序

- [x] Task 3: 改造 AppMemoryExtractor (AC: #2)
  - [x] 3.1 修改 `extract()` 返回类型从 `[KnowledgeEntry]` 改为 `[AppMemoryFact]`
  - [x] 3.2 成功任务 → kind=observation, confidence=0.7, status=candidate
  - [x] 3.3 失败任务 → kind=avoid, confidence=0.5, status=candidate
  - [x] 3.4 含修正路径的任务 → kind=observation, confidence=0.6, status=candidate, cause=workaround
  - [x] 3.5 保留旧 KnowledgeEntry 生成逻辑（双写，兼容期），标记 @available(*, deprecated)

- [x] Task 4: 实现持久化层 (AC: #1, #7)
  - [x] 4.1 在 `Sources/AxionCLI/Memory/` 新建 `MemoryFactStore.swift`
  - [x] 4.2 使用 actor 隔离，文件路径 `~/.axion/memory/{domain}-facts.json`
  - [x] 4.3 实现 `save(domain:fact:)`、`query(domain:filter:)`、`listDomains()`、`delete(domain:)`
  - [x] 4.4 实现惰性迁移：读取旧 KnowledgeEntry 文件时自动升级为 AppMemoryFact
  - [x] 4.5 JSON 序列化使用 JSONEncoder + Codable（sortedKeys + prettyPrinted）

- [x] Task 5: 改造 RunCommand 集成 (AC: #2, #8)
  - [x] 5.1 RunCommand 中注入 MemoryFactStore + MemoryLifecycleService
  - [x] 5.2 任务完成后调用 `addFact()` 替代直接 `store.save()`
  - [x] 5.3 启动时调用 `demoteRetired()` 替代旧的 `cleanupExpired()`
  - [x] 5.4 保留旧 MemoryCleanupService 调用（兼容期，可移除）

- [x] Task 6: 单元测试 (AC: #1-#8)
  - [x] 6.1 `AppMemoryFactTests` — 模型 Codable round-trip、normalizeFact 边界测试、factId 确定性
  - [x] 6.2 `MemoryLifecycleServiceTests` — promote/demote/reactivate 生命周期测试
  - [x] 6.3 `MemoryFactStoreTests` — 持久化 CRUD、惰性迁移、合并策略测试
  - [x] 6.4 更新 `AppMemoryExtractorTests` — 验证新的返回类型和 confidence/kind 赋值

## Dev Notes

### 核心设计决策

**D1: AppMemoryFact 是 AxionCLI 层模型，不修改 SDK KnowledgeEntry**
- SDK 的 `KnowledgeEntry`（`MemoryTypes.swift`）是通用接口，Axion 不能修改
- AppMemoryFact 是 Axion 的应用层增强模型，与 KnowledgeEntry 并行存在
- 迁移期双写：新系统写 AppMemoryFact，旧系统保留 KnowledgeEntry 生成（deprecated）

**D2: 文件格式和存储路径**
- 旧格式：`~/.axion/memory/{domain}.json` — KnowledgeEntry 数组
- 新格式：`~/.axion/memory/{domain}-facts.json` — AppMemoryFact 数组
- 两套文件并存，MemoryFactStore 只操作 `-facts.json` 文件
- 惰性迁移：当读取旧 `{domain}.json` 时自动转换为 AppMemoryFact 并写入新文件

**D3: 生命周期状态机**
```
candidate ──(evidenceCount >= 2 && confidence >= 0.65)──► active
    ▲                                                       │
    │                                              (30 天未验证)
    │                                                       ▼
    └──────────────(再次观察到)────────────────────── retired
```

**D4: 确定性 ID 生成**
- 参考 OpenClick `factId()`：`"{kind}-{hash(description)}"`
- Swift 实现使用 `description.lowercased().trimmed.hashValue`
- 同一事实的重复观察通过 ID 匹配合并

**D5: 与后续 Story 12.2 的关系**
- Story 12.1 定义 `MemoryKind` 枚举但仅使用 observation 和 avoid
- Story 12.2 将实现完整的 affordance 分类逻辑和 prompt 注入
- 本次实现中 AppMemoryExtractor 只在失败时标记 avoid，成功时标记 observation

### 现有代码修改清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/AxionCLI/Memory/AppMemoryFact.swift` | **新建** | 模型 + normalizeFact + factId |
| `Sources/AxionCLI/Memory/MemoryLifecycleService.swift` | **新建** | 生命周期管理服务 |
| `Sources/AxionCLI/Memory/MemoryFactStore.swift` | **新建** | actor 隔离持久化层 |
| `Sources/AxionCLI/Memory/AppMemoryExtractor.swift` | **修改** | 返回 AppMemoryFact，双写 |
| `Sources/AxionCLI/Commands/RunCommand.swift` | **修改** | 集成新服务 |
| `Tests/AxionCLITests/Memory/AppMemoryFactTests.swift` | **新建** | 模型测试 |
| `Tests/AxionCLITests/Memory/MemoryLifecycleServiceTests.swift` | **新建** | 生命周期测试 |
| `Tests/AxionCLITests/Memory/MemoryFactStoreTests.swift` | **新建** | 持久化测试 |
| `Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift` | **修改** | 更新断言 |

### 不修改的文件（必须遵守）

- `Sources/OpenAgentSDK/Types/MemoryTypes.swift` — SDK 模型，不可修改
- `Sources/OpenAgentSDK/Stores/MemoryStore.swift` — SDK 存储，不可修改
- `Sources/AxionCore/` — 本 Story 不涉及 AxionCore

### OpenClick 参考映射

| Axion 组件 | OpenClick 参考 | 关键差异 |
|-----------|---------------|---------|
| AppMemoryFact | `src/memory.ts:11-32` AppMemoryFact | Swift struct vs TS interface；增加 Codable |
| normalizeFact | `src/memory.ts:318-338` | 逻辑相同，Swift 类型安全替代运行时检查 |
| addFact / mergeFact | `src/memory.ts:120-170` addAppMemoryFact | OpenClick 直接写文件，Axion 通过 actor 隔离 |
| maybePromote | `src/memory.ts:414-427` | OpenClick 仅 avoid 需要 evidence 累积，Axion 统一所有 kind |
| demoteRetired | OpenClick 无直接对应 | Axion 新增：30 天未验证自动降级 |
| selectActiveFacts | `src/memory.ts:391-398` | 逻辑相同：只选 active，按 confidence 排序 |

### 测试策略

- 使用 Swift Testing 框架（`import Testing`、`@Suite`、`@Test`、`#expect`）
- MemoryFactStore 测试使用临时目录（`FileManager.default.temporaryDirectory`）
- Mock 策略：MemoryLifecycleService 是纯计算 struct，无需 mock
- 边界测试重点：confidence 溢出（<0, >1）、evidenceCount 为 0、空 description、retired 不可变

### 关键反模式提醒

- **不修改 SDK 的 KnowledgeEntry** — AppMemoryFact 是独立的应用层模型
- **不创建新的错误类型** — 统一使用 `AxionError`
- **不在 AxionCore 中添加 Memory 相关类型** — Memory 是 AxionCLI 层关注点
- **JSON 输出必须使用 JSONEncoder** — 不手动拼接字符串
- **文件路径使用 FileManager + URL API** — 不拼接字符串
- **所有 Memory 操作失败不阻塞任务执行** — do/catch + warning 日志

### Project Structure Notes

- 新文件放在 `Sources/AxionCLI/Memory/`，与现有 Memory 服务同目录
- 测试文件放在 `Tests/AxionCLITests/Memory/`，镜像源文件结构
- 不在 AxionCore 中添加任何类型（Memory 是 CLI 层关注点）

### References

- SDK KnowledgeEntry: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/MemoryTypes.swift]
- SDK MemoryStore: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Stores/MemoryStore.swift]
- OpenClick AppMemoryFact: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:11-32]
- OpenClick addAppMemoryFact: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:120-170]
- OpenClick maybePromoteFact: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:414-427]
- OpenClick normalizeFact: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:309-349]
- OpenClick mergeFacts: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:357-381]
- OpenClick selectActiveFacts: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:389-394]
- 现有 AppMemoryExtractor: [Source: Sources/AxionCLI/Memory/AppMemoryExtractor.swift]
- 现有 MemoryCleanupService: [Source: Sources/AxionCLI/Memory/MemoryCleanupService.swift]
- 现有 FamiliarityTracker: [Source: Sources/AxionCLI/Memory/FamiliarityTracker.swift]
- 现有 AppProfileAnalyzer: [Source: Sources/AxionCLI/Memory/AppProfileAnalyzer.swift]
- 现有 MemoryContextProvider: [Source: Sources/AxionCLI/Memory/MemoryContextProvider.swift]
- RunCommand Memory 集成: [Source: Sources/AxionCLI/Commands/RunCommand.swift:82-320]
- Epics (Epic 12): [Source: _bmad-output/planning-artifacts/epics.md:1693-1734]
- Project Context: [Source: _bmad-output/project-context.md]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Fixed domain extraction bug in `MemoryFactStore.listDomains()` — was incorrectly stripping domain names
- Fixed floating-point precision in lifecycle tests (0.7 + 0.1 ≠ exactly 0.8 in Double)
- Fixed workaround detection order in `buildFact()` — must check hasError+workaround before hasError alone

### Completion Notes List

- ✅ Task 1: AppMemoryFact model with 3 enums (MemoryFactStatus, MemoryFactSource, MemoryKind), Codable+Equatable+Sendable, normalizeFact(), factId()
- ✅ Task 2: MemoryLifecycleService as pure-computation struct with addFact/mergeFact/maybePromote/demoteRetired/reactivateRetired/selectActiveFacts
- ✅ Task 3: AppMemoryExtractor extended with extractFacts() method, old extract() marked @available(*, deprecated)
- ✅ Task 4: MemoryFactStore actor with CRUD, lazy migration from KnowledgeEntry, sortedKeys+prettyPrinted JSON
- ✅ Task 5: RunCommand integrates new services — demoteRetired at startup, addFact after task completion, old cleanup preserved
- ✅ Task 6: 46 new tests (AppMemoryFactTests: 14, MemoryLifecycleServiceTests: 20, MemoryFactStoreTests: 10, AppMemoryExtractorTests: +5 new)

### File List

- `Sources/AxionCLI/Memory/AppMemoryFact.swift` — new
- `Sources/AxionCLI/Memory/MemoryLifecycleService.swift` — new
- `Sources/AxionCLI/Memory/MemoryFactStore.swift` — new
- `Sources/AxionCLI/Memory/AppMemoryExtractor.swift` — modified
- `Sources/AxionCLI/Commands/RunCommand.swift` — modified
- `Tests/AxionCLITests/Memory/AppMemoryFactTests.swift` — new
- `Tests/AxionCLITests/Memory/MemoryLifecycleServiceTests.swift` — new
- `Tests/AxionCLITests/Memory/MemoryFactStoreTests.swift` — new
- `Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift` — modified

### Change Log

- 2026-05-17: Story 12.1 implementation complete — Memory Fact lifecycle model with candidate/active/retired states, confidence scoring, evidence-based promotion, 30-day demotion, retired reactivation, lazy migration from KnowledgeEntry, 46 new tests
- 2026-05-17: **Senior Developer Review (AI)** — 7 issues found, 4 fixed
  - CRITICAL: `factId()` used `hashValue` (randomized per process launch) — replaced with djb2 deterministic hash (`AppMemoryFact.swift`)
  - HIGH: `mergeFact` didn't update `updatedAt` on promotion — now reuses `maybePromote` result directly (`MemoryLifecycleService.swift`)
  - HIGH: Missing AC4 test — added `addFactCreatesSeparateForContradictory` verifying contradictory facts (same description, different kind) create separate entries
  - MEDIUM: `mergeFact` duplicated promotion logic — eliminated by reusing `maybePromote`
  - Added `factIdDeterministicHash` test verifying djb2 hash output format
  - All 77 memory tests pass (76 original + 2 new, 1 subsumed by hash change)

## Review Outcome: APPROVED (all CRITICAL/HIGH issues fixed)
