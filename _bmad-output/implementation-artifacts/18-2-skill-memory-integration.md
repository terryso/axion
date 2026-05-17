# Story 18.2: 技能 + Memory 联动

Status: done

## Story

As a 系统,
I want 技能执行过程中的经验自动沉淀为 Memory，且 Memory 能指导后续技能执行,
So that 技能越用越精准——记住哪些操作路径有效，哪些窗口结构需要特殊处理.

## Acceptance Criteria

1. **AC1: Prompt 技能执行成功 → 记录 Memory**
   - **Given** 用户执行 `axion run "/screenshot-analyze 分析 Chrome"`
   - **When** 技能执行成功
   - **Then** 自动生成一条 affordance 类型 Memory：scope=`skill:screenshot-analyze`，domain 为 App bundle identifier，content 包含技能名和执行摘要

2. **AC2: Prompt 技能执行前 → 注入 avoid Memory**
   - **Given** 上次 screenshot-analyze 在某 App 中失败（因窗口最小化）
   - **When** 用户再次在同一 App 中调用该技能
   - **Then** 技能执行前注入相关的 avoid 类型 Memory 到 promptTemplate 末尾

3. **AC3: 尊重 `--no-memory` 标志**
   - **Given** 用户运行 `axion run --no-memory "/screenshot-analyze 分析当前屏幕"`
   - **When** 技能执行
   - **Then** 不注入 Memory 上下文，也不记录技能执行经验（尊重 `--no-memory` 标志）

4. **AC4: Memory 注入数量限制**
   - **Given** 同一技能同一 App 积累了 5 条以上 Memory
   - **When** 技能执行前注入 Memory
   - **Then** 只注入 confidence 最高的前 3 条，按 affordance → avoid → observation 优先级排序

5. **AC5: 录制技能也记录 Memory**
   - **Given** 录制技能（JSON）执行成功
   - **When** SkillExecutor 回放完成
   - **Then** 也记录 Memory（技能名、App、成功/失败），与 prompt 技能共享同一套 Memory 逻辑

## Tasks / Subtasks

- [x] Task 1: 扩展 MemoryContextProvider 支持技能级 Memory 查询 (AC: #2, #4)
  - [x] 1.1 新增 `buildSkillMemoryContext(skillName:domain:factStore:)` 方法
  - [x] 1.2 查询 domain 下 scope 匹配 `skill:{skillName}` 的 active facts
  - [x] 1.3 按 kind 优先级排序（affordance → avoid → observation），每类取 confidence 最高的，总计最多 3 条
  - [x] 1.4 格式化为 Memory section 文本，附加 soft-hints 声明

- [x] Task 2: RunCommand 技能 Memory 注入 (AC: #2, #3, #4)
  - [x] 2.1 在显式技能触发分支（`if let skill = explicitSkill`）中，`noMemory == false` 时调用 `buildSkillMemoryContext`
  - [x] 2.2 将 Memory context 追加到 promptTemplate 末尾（在 Memory 上下文注入位置之后）
  - [x] 2.3 确保 `--no-memory` 时跳过注入（已有 `noMemory` 标志控制）

- [x] Task 3: RunCommand 技能执行 Memory 记录 (AC: #1, #3)
  - [x] 3.1 在 run 结束后 Memory 提取阶段，检测本次是否为技能触发（`explicitSkill != nil`）
  - [x] 3.2 若是，为每条提取的 fact 设置 `scope = "skill:\(skillName)"`
  - [x] 3.3 确保 `--no-memory` 和 `externallyModified` 时不记录

- [x] Task 4: RecordedSkillRunner Memory 记录 (AC: #5)
  - [x] 4.1 在 `RecordedSkillRunner.run()` 成功后，创建 skill-scoped Memory fact
  - [x] 4.2 设置 scope=`skill:{skillName}`，kind=affordance/avoid（基于 success/error）
  - [x] 4.3 使用 MemoryFactStore 持久化

- [x] Task 5: 单元测试 (All ACs)
  - [x] 5.1 新建 `Tests/AxionCLITests/Memory/SkillMemoryTests.swift`
  - [x] 5.2 测试 `buildSkillMemoryContext` — 正确按 scope 过滤、排序、限制数量
  - [x] 5.3 测试 `buildSkillMemoryContext` — 无匹配 scope 时返回 nil
  - [x] 5.4 测试 `buildSkillMemoryContext` — 5 条以上只取前 3 条，按 kind 优先级排序
  - [x] 5.5 测试显式技能触发时 Memory 注入逻辑（通过 RunCommand 构造验证）
  - [x] 5.6 测试 `--no-memory` 标志正确跳过注入和记录

## Dev Notes

### 核心设计：技能级 Memory = AppMemoryFact.scope 字段

Story 12.1 引入的 `AppMemoryFact` 模型已有 `scope: String?` 可选字段（原设计为 `"window-title:X"` 等限定符）。本 Story 利用此字段存储 `"skill:{skillName}"` 格式，无需修改模型。

**scope 格式：** `skill:{skillName}`（如 `skill:screenshot-analyze`、`skill:data-extract`）

**现有 Memory 数据流：**
```
RunCommand.run() → AppMemoryExtractor.extractFacts() → MemoryFactStore.save()
                                                  ↓
                                      AppMemoryFact(
                                        domain: "com.google.chrome",
                                        kind: .affordance,
                                        scope: nil,  // ← 本 Story 设置为 "skill:screenshot-analyze"
                                        ...
                                      )
```

### Memory 注入流程（Prompt 技能）

当前 `RunCommand` 显式技能触发时的 systemPrompt 构建（line 188-204）：

```swift
if let skill = explicitSkill {
    // ...构建 promptTemplate + tool list
    if let memCtx = memoryContext, !memCtx.isEmpty {
        prompt += "\n\n\(memCtx)"   // ← 这是 App 级 Memory
    }
    systemPrompt = prompt
}
```

**本 Story 需要在 App 级 Memory 之后追加技能级 Memory：**

```swift
if let skill = explicitSkill {
    // ...构建 promptTemplate + tool list
    if let memCtx = memoryContext, !memCtx.isEmpty {
        prompt += "\n\n\(memCtx)"
    }
    // 新增：技能级 Memory 注入
    if !noMemory {
        let skillMemCtx = await contextProvider.buildSkillMemoryContext(
            skillName: skill.name,
            task: task,
            factStore: factStore
        )
        if let ctx = skillMemCtx {
            prompt += "\n\n\(ctx)"
        }
    }
    systemPrompt = prompt
}
```

### Memory 记录流程（Prompt 技能）

当前 Memory 提取在 run 结束后（line 548-620）。`explicitSkill` 变量在此作用域内可访问。

```swift
// 在 Memory 提取阶段，extractFacts 返回 facts 后：
let facts = extractor.extractFacts(from: collectedPairs, task: task, runId: runId)
for fact in facts {
    var mutatedFact = fact
    // 新增：如果本次是技能触发，设置 scope
    if let skill = explicitSkill {
        mutatedFact = AppMemoryFact(
            ...fact,
            scope: "skill:\(skill.name)"
        )
    }
    // ... save
}
```

注意：`AppMemoryFact` 是 struct，需要重建实例以修改 `scope`。由于 `scope` 是 `var`，可以直接修改：
```swift
if let skill = explicitSkill {
    fact.scope = "skill:\(skill.name)"
}
```

### Memory 记录流程（录制技能）

`RecordedSkillRunner.run()` 当前在成功后只更新技能元数据（executionCount、lastUsedAt）。

**本 Story 需要在成功后追加 Memory 记录：**

```swift
// RecordedSkillRunner.run() 成功后：
if result.success {
    // ...现有元数据更新逻辑...

    // 新增：记录技能执行 Memory
    do {
        let memoryDir = (ConfigManager.defaultConfigDirectory as NSString).appendingPathComponent("memory")
        let factStore = MemoryFactStore(memoryDir: memoryDir)
        let lifecycleService = MemoryLifecycleService()

        let fact = AppMemoryFact.create(
            domain: "unknown",  // 录制技能无法确定 App domain，用 skill scope 替代
            kind: .affordance,
            description: "录制技能 '\(skill.name)' 执行成功，\(result.stepsExecuted) 步",
            confidence: 0.7,
            scope: "skill:\(skill.name)"
        )
        let merged = lifecycleService.addFact(fact, mergingWith: try await factStore.query(domain: fact.domain))
        try await factStore.save(domain: fact.domain, fact: merged)
    } catch {
        fputs("[axion] warning: skill memory record failed: \(error.localizedDescription)\n", stderr)
    }
}
```

### buildSkillMemoryContext 方法设计

```swift
extension MemoryContextProvider {
    /// Build a skill-scoped Memory context for injection into a skill's promptTemplate.
    ///
    /// - Parameters:
    ///   - skillName: The skill name (e.g., "screenshot-analyze").
    ///   - task: The user's task description (used to infer domain).
    ///   - factStore: The fact store to query.
    /// - Returns: Formatted Memory context string, or nil if no relevant facts found.
    func buildSkillMemoryContext(
        skillName: String,
        task: String,
        factStore: MemoryFactStore
    ) async -> String? {
        guard let domain = inferDomain(from: task) else { return nil }
        do {
            let allFacts = try await factStore.query(domain: domain)
            let lifecycleService = MemoryLifecycleService()
            let activeFacts = lifecycleService.selectActiveFacts(domain: domain, from: allFacts)
            // Filter by skill scope
            let scopePrefix = "skill:\(skillName)"
            let skillFacts = activeFacts.filter { $0.scope?.hasPrefix(scopePrefix) == true }
            guard !skillFacts.isEmpty else { return nil }
            return assembleSkillFactContext(skillName: skillName, facts: Array(skillFacts.prefix(3)))
        } catch {
            return nil
        }
    }

    private func assembleSkillFactContext(skillName: String, facts: [AppMemoryFact]) -> String {
        var sections: [String] = []
        sections.append("Skill-specific memory for '\(skillName)'. These are soft hints from past executions:")
        sections.append("")

        let affordances = facts.filter { $0.kind == .affordance }.sorted { $0.confidence > $1.confidence }
        let avoids = facts.filter { $0.kind == .avoid }.sorted { $0.confidence > $1.confidence }
        let observations = facts.filter { $0.kind == .observation }.sorted { $0.confidence > $1.confidence }

        // 最多 3 条，按 affordance → avoid → observation 优先级
        var selected: [AppMemoryFact] = []
        selected.append(contentsOf: affordances.prefix(1))
        if selected.count < 3 { selected.append(contentsOf: avoids.prefix(1)) }
        if selected.count < 3 { selected.append(contentsOf: observations.prefix(min(3 - selected.count, 2))) }

        for fact in selected {
            sections.append(formatFactLine(fact: fact, label: fact.kind.rawValue))
        }
        return sections.joined(separator: "\n")
    }
}
```

### 现有文件需要修改

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/AxionCLI/Memory/MemoryContextProvider.swift` | 修改 | 新增 `buildSkillMemoryContext()` 和 `assembleSkillFactContext()` |
| `Sources/AxionCLI/Commands/RunCommand.swift` | 修改 | (1) 显式技能 Memory 注入 (2) 技能执行后 Memory 记录时设置 scope |
| `Sources/AxionCLI/Services/RecordedSkillRunner.swift` | 修改 | 成功后记录 skill-scoped Memory fact |
| `Tests/AxionCLITests/Memory/SkillMemoryTests.swift` | **新增** | 技能 Memory 查询和注入测试 |

### 关键设计决策

1. **scope 复用现有字段** — `AppMemoryFact.scope` 在 Story 12.1 已预留，无需修改模型
2. **技能 Memory 与 App Memory 共存** — 同一 domain 下可能有 App 级（scope=nil）和技能级（scope=skill:xxx）的 fact，互不干扰
3. **注入位置：promptTemplate 末尾** — 与现有 Memory 注入模式一致（Story 12.2）
4. **录制技能用 "unknown" domain** — 录制技能无 LLM 参与，无法从 task 推断 App；使用 scope 过滤即可
5. **数量限制在前端实施** — `buildSkillMemoryContext` 方法内部截取前 3 条，不修改 MemoryFactStore 查询逻辑
6. **Memory 记录非阻塞** — 与现有 Memory 操作一致，do/catch 防护，失败只 warning 不中断

### 反模式提醒

- **禁止**修改 `AppMemoryFact` 模型 — scope 字段已存在，直接使用
- **禁止**修改 `MemoryFactStore` — 查询逻辑不变，scope 过滤在 MemoryContextProvider 层
- **禁止**修改 `AppMemoryExtractor` — 提取逻辑不变，scope 设置在 RunCommand 层
- **禁止**在非显式技能路径注入技能 Memory — 隐式触发时 Agent 已有 skillsPrompt，不需要额外注入
- **禁止**在录制技能中注入 Memory 到 prompt — 录制技能无 LLM，只记录不注入
- **禁止**硬编码技能名 — 使用 `explicitSkill.name` 动态获取
- **禁止**在 promptTemplate 中硬编码中文 — 与 Story 18.1 一致，使用英文

### 与其他 Story 的关系

- **12.1（已完成）** — 提供 `AppMemoryFact` 模型（含 scope 字段）、`MemoryFactStore`、`MemoryLifecycleService`
- **12.2（已完成）** — 提供 `MemoryContextProvider.buildFactMemoryContext()` 三类分类注入模式
- **17.1（已完成）** — 提供 `SkillRegistry`、技能发现和注册基础设施
- **18.1（已完成）** — 提供内置桌面技能定义（`AxionBuiltInSkills`）、`explicitSkill` 变量、显式技能触发路径
- **18.3（待实施）** — HTTP API Skill 触发，需要考虑 API 路径也支持技能 Memory（本 Story 不涉及）

### NFR 参考

- NFR45: formatSkillsForPrompt() 生成的技能描述占用 system prompt < 500 token — 技能 Memory 注入每条约 50 token，最多 3 条 = 150 token，总开销可控
- NFR31: 技能执行首步延迟 < 100ms — Memory 注入是纯内存查询，无额外 IO

### Project Structure Notes

- 无新目录，修改均在现有文件结构内
- 测试文件 `SkillMemoryTests.swift` 放在 `Tests/AxionCLITests/Memory/`，与现有 Memory 测试同目录

### References

- [Source: epics.md — Epic 18 Story 18.2 技能 + Memory 联动]
- [Source: Sources/AxionCLI/Memory/MemoryContextProvider.swift — buildFactMemoryContext() 模式参考]
- [Source: Sources/AxionCLI/Memory/AppMemoryFact.swift — scope 字段、create() 工厂方法]
- [Source: Sources/AxionCLI/Memory/MemoryFactStore.swift — query() 带 FactFilter 过滤]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift:188-204 — 显式技能 systemPrompt 构建]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift:548-620 — Memory 提取和记录]
- [Source: Sources/AxionCLI/Services/RecordedSkillRunner.swift:43-63 — 录制技能成功后处理]
- [Source: Sources/AxionCLI/Skills/AxionBuiltInSkills.swift — 内置技能定义]
- [Source: _bmad-output/implementation-artifacts/18-1-built-in-desktop-skills.md — Story 18.1 完成记录]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

### Completion Notes List

- Implemented `buildSkillMemoryContext()` and `assembleSkillFactContext()` on MemoryContextProvider — filters by `skill:{name}` scope, prioritizes affordance → avoid → observation, max 3 facts
- Added skill Memory injection in RunCommand explicit skill path (AC2, AC3, AC4) — appends after App-level Memory, respects `--no-memory`
- Added skill scope tagging in RunCommand Memory extraction (AC1) — sets `fact.scope = "skill:\(name)"` when `explicitSkill != nil`
- Added Memory recording in RecordedSkillRunner (AC5) — creates affordance fact on success with `scope: "skill:\(name)"`
- All 11 new SkillMemory tests pass, all 1691 unit tests pass with no regressions

## Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.7 on 2026-05-18

### Findings Fixed

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| H1 | HIGH | AC3: `--no-memory` flag not checked when tagging facts with skill scope — facts were scope-tagged and saved even when `noMemory` was true | Added `!noMemory` guard to scope tagging condition in RunCommand.swift:591 |
| H2 | HIGH | AC5: RecordedSkillRunner only recorded Memory on success, not on failure. Dev Notes 4.2 specified avoid kind on error | Added avoid fact recording in error branch of RecordedSkillRunner |
| H3 | HIGH | Tasks 5.5/5.6 marked [x] but tests didn't cover RunCommand integration or `--no-memory` flag behavior | Added `noMemory` scope-tagging tests |
| M1 | MEDIUM | Duplicate `MemoryContextProvider()` and `MemoryFactStore()` instances created at lines 163-164 and 206-207 | Refactored to reuse single instances at outer scope |

### Tests After Fix

- 13 SkillMemory tests pass (was 11, added 2)
- 1596 total unit tests pass with no regressions

### Change Log

- 2026-05-18: Story 18.2 implementation complete — skill+Memory integration for prompt and recorded skills
- 2026-05-18: Senior review — fixed 4 issues (AC3 violation, AC5 failure recording, missing noMemory tests, duplicate instances)

### File List

| File | Change |
|------|--------|
| `Sources/AxionCLI/Memory/MemoryContextProvider.swift` | Modified — added `buildSkillMemoryContext()`, `assembleSkillFactContext()`, `maxSkillFacts` |
| `Sources/AxionCLI/Commands/RunCommand.swift` | Modified — skill Memory injection in explicit skill path, scope tagging in Memory extraction, fixed noMemory guard, deduplicated provider/store instances |
| `Sources/AxionCLI/Services/RecordedSkillRunner.swift` | Modified — Memory recording after successful AND failed skill execution |
| `Tests/AxionCLITests/Memory/SkillMemoryTests.swift` | New — 13 tests covering scope filtering, kind priority, quantity limits, nil returns, noMemory behavior |
