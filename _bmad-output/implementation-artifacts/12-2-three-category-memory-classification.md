# Story 12.2: 三类记忆分类

Status: done

## Story

As a Planner,
I want 记忆分为 affordance（可用能力）、avoid（避坑规则）和 observation（观察）三类,
So that planner prompt 可以根据类型注入不同策略的上下文.

## Acceptance Criteria

1. **AC1: Affordance 分类 — 成功路径发现**
   Given 任务成功完成，发现新的操作路径或高效操作方式
   When AppMemoryExtractor 提取记忆
   Then 记录为 affordance 类型（如 "Finder 中 Cmd+Shift+G 可直接导航到指定路径"）
   And confidence = 0.72，status = candidate

2. **AC2: Avoid 分类 — 失败经验记录**
   Given 任务执行中某操作失败，触发重规划后成功
   When AppMemoryExtractor 提取记忆
   Then 失败操作记录为 avoid 类型（如 "避免在 Chrome 中使用 AX 定位地址栏，截图坐标更可靠"）
   And confidence = 0.5（保持 Story 12.1 现有行为不变）

3. **AC3: Observation 分类 — 环境信息记录**
   Given 任务执行中发现非操作性的环境信息
   When AppMemoryExtractor 提取记忆
   Then 记录为 observation 类型（如 "Calculator 在 macOS 14 中的窗口标题为 'Calculator'"）
   And confidence = 0.7（保持 Story 12.1 现有行为不变）

4. **AC4: Planner prompt 三类分类注入**
   Given Planner 生成计划时
   When 注入 Memory 上下文
   Then affordance 注入为推荐路径提示（前缀 "推荐路径"）
   And avoid 注入为避坑警告（前缀 "注意/不建议"）
   And observation 注入为环境备注（前缀 "环境备注"）

5. **AC5: Avoid 为软性建议**
   Given avoid 类型的记忆被注入 planner prompt
   When Planner 规划
   Then 为软性建议（"不建议使用 X"），不是硬性禁止，Planner 可以在必要时忽略
   And prompt 文本中包含 "These are soft hints, not hard rules" 声明

6. **AC6: MemoryListCommand 展示分类信息**
   Given 运行 `axion memory list`
   When 查看列表
   Then 每条记忆显示状态图标（✓ active / ○ candidate / ✗ retired）、类型（affordance/avoid/observation）和 evidence_count

## Tasks / Subtasks

- [x] Task 1: 增强 AppMemoryExtractor 分类逻辑 (AC: #1, #2, #3)
  - [x] 1.1 在 `buildFact()` 中新增 affordance 检测：当任务成功完成且工具序列包含 hotkey/click 等直接操作（非 AX 探索型操作）时，标记为 `.affordance`，confidence = 0.72
  - [x] 1.2 将现有 `buildFact()` 中第 135-148 行的 `if/else if/else` 块提取为独立方法 `classifyKind()`，便于测试和维护
  - [x] 1.3 确保 avoid 分类逻辑不变（hasError && 无 workaround → .avoid, confidence=0.5）
  - [x] 1.4 确保 observation 分类逻辑不变（环境信息、workaround → .observation, confidence=0.6-0.7）
  - [x] 1.5 新增 affordance description 生成：包含具体的操作步骤描述（如 "在 {appName} 中使用 {hotkey} 可{效果}"）

- [x] Task 2: 升级 MemoryContextProvider 支持分类注入 (AC: #4, #5)
  - [x] 2.1 新增 `buildFactMemoryContext(task:factStore:)` async 方法，读取 `MemoryFactStore` 中的 active facts（使用 `MemoryLifecycleService.selectActiveFacts(domain:from:)` 过滤）
  - [x] 2.2 按 kind 分组渲染：affordance→"推荐路径" section，avoid→"注意事项" section，observation→"环境备注" section
  - [x] 2.3 每类最多显示 5 条（按 confidence 降序），格式为 `{kind_label} (confidence: {n}, evidence: {count}): {description}`
  - [x] 2.4 添加软性建议声明："These are soft hints, not hard rules. Cautions should change strategy probabilities, not disable capabilities."
  - [x] 2.5 保留旧 `buildMemoryContext(task:store:)` 方法（兼容期），新方法优先调用

- [x] Task 3: RunCommand 集成分类上下文注入 (AC: #4, #5)
  - [x] 3.1 注意：RunCommand 中已有 `MemoryFactStore` 实例（用于 `demoteRetired` 和保存 facts），但作用域在独立的 do-catch 块中。需要将 factStore 实例提升到 prompt 构建可访问的作用域，或在 prompt 构建处重新创建实例
  - [x] 3.2 调用 `buildFactMemoryContext()` 替代旧的 `buildMemoryContext()`（当 factStore 非空时优先使用新方法）
  - [x] 3.3 旧方法保留为 fallback（factStore 为空或新方法返回 nil 时使用旧方法）
  - [x] 3.4 在系统 prompt 中注入分类后的 Memory 上下文

- [x] Task 4: 升级 MemoryListCommand 展示分类信息 (AC: #6)
  - [x] 4.1 改用 `MemoryFactStore` 读取 fact 数据（替代直接读旧 JSON）
  - [x] 4.2 按 domain 分组，每个 fact 显示：状态图标 + kind + description 摘要 + confidence + evidence_count
  - [x] 4.3 状态图标映射：active→"✓"，candidate→"○"，retired→"✗"
  - [x] 4.4 kind 显示映射：affordance→"推荐"，avoid→"警告"，observation→"备注"

- [x] Task 5: 单元测试 (AC: #1-#6)
  - [x] 5.1 更新 `AppMemoryExtractorTests` — 新增 affordance 分类测试：纯成功 hotkey/click 序列 → .affordance
  - [x] 5.2 新增边界测试：mixed 序列（成功 AX 探索 + 成功 click）→ 仍为 .affordance
  - [x] 5.3 确保现有 avoid/observation 分类测试不受影响
  - [x] 5.4 新增 `MemoryContextProviderTests`（或更新现有）— 测试 `buildFactMemoryContext` 三类分类渲染
  - [x] 5.5 测试每类最多 5 条限制
  - [x] 5.6 测试软性建议声明存在
  - [x] 5.7 测试 only active facts 被注入（candidate/retired 不注入）
  - [x] 5.8 新增 `MemoryListCommandTests` — 测试状态图标和 kind 显示格式

## Dev Notes

### 核心设计决策

**D1: Affordance 检测策略**
- OpenClick 的 `recordTakeoverLearning()` 仅在 Takeover（用户手动接管）成功时标记 affordance
- Axion 在 Story 12.2 中实现自动化 affordance 检测：当任务成功完成且工具序列以直接操作（click/type_text/hotkey）为主（非 AX 探索型如 get_window_state/get_accessibility_tree），标记为 affordance
- 具体判定逻辑：`任务成功完成 && 无 error && 工具序列中直接操作占比 >= 50% && 总步骤 <= 5` → affordance
- 不满足 affordance 条件的成功任务仍标记为 observation

**D2: MemoryContextProvider 双模式**
- 旧方法 `buildMemoryContext(task:store:)` 使用 SDK `MemoryStoreProtocol`（KnowledgeEntry 数据）
- 新方法 `buildFactMemoryContext(task:factStore:)` 使用 AxionCLI 的 `MemoryFactStore`（AppMemoryFact 数据）
- RunCommand 中优先调用新方法，旧方法作为 fallback
- 未来可完全移除旧方法（在 Memory 系统完全迁移后）

**D3: Prompt 注入格式（参考 OpenClick renderRelevantMemoriesForPrompt）**
```
Relevant local app memories. These are soft hints, not hard rules. Cautions should change strategy probabilities, not disable capabilities:

## com.apple.finder — Memory Context

### 推荐路径 (affordance)
- [推荐] (confidence: 0.82, evidence: 3): Finder 中 Cmd+Shift+G 可直接导航到指定路径
- [推荐] (confidence: 0.72, evidence: 1): 使用 list_windows 定位 Finder 窗口后直接 click 打开

### 注意事项 (avoid)
- [警告] (confidence: 0.65, evidence: 2): 不建议使用 AX click 定位 Finder 侧边栏项目，坐标不可靠
- [警告] (confidence: 0.55, evidence: 1): 避免在 Finder 中使用 type_text 输入路径

### 环境备注 (observation)
- [备注] (confidence: 0.80, evidence: 4): Finder 窗口标题格式为文件夹名称
```

**D4: 与后续 Story 的关系**
- Story 12.2 的分类逻辑是 Story 15.1（Takeover 学习）的基础
- Story 15.1 将在 Takeover 成功时调用 `addFact(kind: .affordance, ...)` 和 Takeover 失败时 `addFact(kind: .avoid, ...)`
- Story 12.3（Memory 导入/导出）将使用 `MemoryFactStore` 序列化所有三类记忆

### 现有代码修改清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/AxionCLI/Memory/AppMemoryExtractor.swift` | **修改** | 新增 `classifyKind()` 方法，增强 affordance 检测 |
| `Sources/AxionCLI/Memory/MemoryContextProvider.swift` | **修改** | 新增 `buildFactMemoryContext(task:factStore:)` 方法 |
| `Sources/AxionCLI/Commands/RunCommand.swift` | **修改** | 集成 fact-based memory context 注入 |
| `Sources/AxionCLI/Commands/MemoryListCommand.swift` | **修改** | 改用 MemoryFactStore，展示分类信息 |
| `Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift` | **修改** | 新增 affordance 分类测试 |
| `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift` | **新建/修改** | 测试三类分类渲染逻辑 |

### 不修改的文件（必须遵守）

- `Sources/AxionCLI/Memory/AppMemoryFact.swift` — MemoryKind 枚举已在 Story 12.1 定义，无需修改
- `Sources/AxionCLI/Memory/MemoryLifecycleService.swift` — 生命周期逻辑不变
- `Sources/AxionCLI/Memory/MemoryFactStore.swift` — 持久化层不变，已有 kind 过滤功能
- `Sources/OpenAgentSDK/` — SDK 不修改

### OpenClick 参考映射

| Axion 组件 | OpenClick 参考 | 关键差异 |
|-----------|---------------|---------|
| classifyKind | `src/memory.ts:46-83` recordTakeoverLearning | OpenClick 仅 Takeover 时分类，Axion 增加自动检测 |
| buildFactMemoryContext | `src/memory.ts:226-250` renderRelevantMemoriesForPrompt | 格式相同，Axion 从 MemoryFactStore 读取而非旧格式 |
| Affordance confidence=0.72 | `src/memory.ts:60` confidence: 0.72 | 值相同 |
| Avoid confidence=0.66 (OC) | Axion 保持 0.5（Story 12.1 已定） | Axion 对 avoid 更保守 |
| Soft hints 声明 | `src/memory.ts:228-229` | 文案直接复用 |

### 分类判定逻辑（classifyKind 伪代码）

```
func classifyKind(pairs: [ToolPair], hasError: Bool, workaround: String?) -> (kind: MemoryKind, confidence: Double, cause: String?) {
    if hasError && workaround != nil {
        return (.observation, 0.6, "workaround")  // 保持 Story 12.1 不变
    }
    if hasError {
        return (.avoid, 0.5, nil)  // 保持 Story 12.1 不变
    }

    // 成功任务 — 判断是否为 affordance
    let directOps = pairs.filter { ["click", "type_text", "hotkey", "double_click"].contains(stripMcpPrefix($0.toolUse.toolName)) }
    let exploreOps = pairs.filter { ["get_window_state", "get_accessibility_tree", "screenshot", "list_windows"].contains(stripMcpPrefix($0.toolUse.toolName)) }

    // 直接操作占比高 && 步骤数合理 → 可能是新发现的操作能力
    if directOps.count >= exploreOps.count && pairs.count <= 5 && !directOps.isEmpty {
        return (.affordance, 0.72, nil)
    }

    // 默认成功 → observation
    return (.observation, 0.7, nil)  // 保持 Story 12.1 不变
}
```

### 关键反模式提醒

- **不修改 AppMemoryFact.swift** — MemoryKind 枚举和模型已在 Story 12.1 定义完毕
- **不修改 MemoryLifecycleService** — 生命周期逻辑不受分类影响
- **不修改 MemoryFactStore** — 已有 kind 过滤查询功能
- **不创建新的错误类型** — 统一使用 `AxionError`
- **不破坏现有 avoid/observation 分类** — 现有测试必须全部通过
- **Memory 操作失败不阻塞任务执行** — do/catch + warning 日志
- **不手动拼接 JSON 字符串** — 使用 JSONEncoder + Codable
- **文件路径使用 FileManager + URL API** — 不拼接字符串
- **avoid 为软性建议** — prompt 文本中不得出现 "禁止" 或 "不得" 等硬性语言

### 测试策略

- 使用 Swift Testing 框架（`import Testing`、`@Suite`、`@Test`、`#expect`）
- MemoryFactStore 测试使用临时目录
- Mock 策略：`MemoryContextProvider` 的 `buildFactMemoryContext` 是 async 方法（需要 await MemoryFactStore actor），测试时传入内存中的 MemoryFactStore 实例（使用临时目录）
- 边界测试重点：
  - affordance 检测边界：directOps=exploreOps 时归为 affordance
  - 空 pairs → observation（保持现有行为）
  - 无直接操作的成功任务 → observation
  - 纯 AX 探索成功 → observation
- 确保 `AppMemoryExtractorTests` 中所有 Story 12.1 的现有测试继续通过

### Project Structure Notes

- 新测试文件放在 `Tests/AxionCLITests/Memory/`，镜像源文件结构
- 不在 AxionCore 中添加任何类型（Memory 是 CLI 层关注点）
- MemoryContextProviderTests 可能需要新建（如果还没有专门的测试文件）

### References

- SDK KnowledgeEntry: [Source: /Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/MemoryTypes.swift]
- OpenClick AppMemory: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:22-31]
- OpenClick MemoryKind + recordTakeoverLearning: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:46-83]
- OpenClick renderRelevantMemoriesForPrompt: [Source: /Users/nick/CascadeProjects/openclick/src/memory.ts:226-250]
- 现有 AppMemoryFact (MemoryKind 已定义): [Source: Sources/AxionCLI/Memory/AppMemoryFact.swift:17-21]
- 现有 AppMemoryExtractor (avoid/observation 分类): [Source: Sources/AxionCLI/Memory/AppMemoryExtractor.swift:130-148]
- 现有 MemoryContextProvider: [Source: Sources/AxionCLI/Memory/MemoryContextProvider.swift]
- 现有 MemoryFactStore (kind 过滤): [Source: Sources/AxionCLI/Memory/MemoryFactStore.swift]
- 现有 MemoryListCommand: [Source: Sources/AxionCLI/Commands/MemoryListCommand.swift]
- RunCommand Memory 集成: [Source: Sources/AxionCLI/Commands/RunCommand.swift:82-120]
- Story 12.1 完成记录: [Source: _bmad-output/implementation-artifacts/12-1-memory-fact-model-upgrade.md]
- Epics (Epic 12 Story 12.2): [Source: _bmad-output/planning-artifacts/epics.md:1735-1768]
- Project Context: [Source: _bmad-output/project-context.md]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- ✅ Task 1: Extracted `classifyKind()` method from inline if/else block; added affordance detection (direct ops >= explore ops, steps <= 5 → .affordance, confidence=0.72). Existing avoid/observation logic preserved unchanged.
- ✅ Task 2: Added `buildFactMemoryContext(task:factStore:)` to MemoryContextProvider. Groups by kind (affordance/avoid/observation), max 5 per kind by confidence desc, soft hints declaration included. Old `buildMemoryContext()` preserved as fallback.
- ✅ Task 3: RunCommand now tries `buildFactMemoryContext()` first, falls back to old `buildMemoryContext()`.
- ✅ Task 4: MemoryListCommand rewritten to use MemoryFactStore. Displays status icons (✓/○/✗), kind labels (推荐/警告/备注), confidence, evidence_count per fact.
- ✅ Task 5: 31 AppMemoryExtractor tests (6 new), 32 MemoryContextProvider tests (6 new), 11 MemoryListCommand tests (6 new). All 74 memory tests pass. Full suite: 1366/1370 pass (4 pre-existing failures in AxionAPISkillRoutesTests unrelated to this story).

### File List

- `Sources/AxionCLI/Memory/AppMemoryExtractor.swift` — Modified: extracted `classifyKind()`, added affordance detection
- `Sources/AxionCLI/Memory/MemoryContextProvider.swift` — Modified: added `buildFactMemoryContext()` and `assembleFactContext()`
- `Sources/AxionCLI/Commands/RunCommand.swift` — Modified: integrated fact-based memory context with fallback
- `Sources/AxionCLI/Commands/MemoryListCommand.swift` — Modified: rewritten to use MemoryFactStore with classified display
- `Tests/AxionCLITests/Memory/AppMemoryExtractorTests.swift` — Modified: updated existing test for new affordance behavior, added 6 new classification tests
- `Tests/AxionCLITests/Memory/MemoryContextProviderTests.swift` — Modified: added 6 new fact-based context tests
- `Tests/AxionCLITests/Commands/MemoryListCommandTests.swift` — Modified: rewritten with MemoryFactStore, added 6 new classification display tests
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Modified: updated story status to in-progress → review
- `_bmad-output/implementation-artifacts/12-2-three-category-memory-classification.md` — Modified: task checkboxes, dev record, file list

### Change Log

- 2026-05-17: Story 12.2 implementation complete — three-category memory classification (affordance/avoid/observation) with prompt injection and list display
- 2026-05-17: Senior Developer Review (AI) — 5 issues found (1 HIGH, 2 MEDIUM, 2 LOW), 2 auto-fixed:
  - [FIXED-HIGH] assembleFactContext multi-line description rendering → added `formatFactLine()` with proper continuation-line indentation
  - [FIXED-MEDIUM] Task 1.5 affordance description → added concise affordance summary line in `buildFact()` when classification is .affordance
  - [NOTED-MEDIUM] RunCommand creates 3 MemoryFactStore instances — works correctly, cosmetic concern
  - [NOTED-LOW] classifyKind could be static func
  - [NOTED-LOW] No test verifying exact prompt bullet format
  - All 90 memory tests pass, 1112/1116 total pass (4 pre-existing AxionAPISkillRoutes failures)
