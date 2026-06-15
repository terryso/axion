---
stepsCompleted: ['step-01-load-context', 'step-02-discover-tests', 'step-03-map-criteria', 'step-04-analyze-gaps', 'step-05-gate-decision']
lastStep: 'step-05-gate-decision'
lastSaved: '2026-06-15'
storyId: '40.2'
storyKey: '40-2-shared-tool-profile-helper-with-behavior-parity'
storyFile: '_bmad-output/implementation-artifacts/40-2-shared-tool-profile-helper-with-behavior-parity.md'
gateTestFile: 'Tests/AxionCLITests/Services/AgentBuilderToolProfileTests.swift'
atddChecklist: '_bmad-output/test-artifacts/atdd-checklist-40-2-shared-tool-profile-helper-with-behavior-parity.md'
coverageBasis: 'acceptance_criteria'
oracleResolutionMode: 'formal_requirements'
oracleConfidence: 'high'
oracleSources:
  - '_bmad-output/implementation-artifacts/40-2-shared-tool-profile-helper-with-behavior-parity.md'
  - '_bmad-output/test-artifacts/atdd-checklist-40-2-shared-tool-profile-helper-with-behavior-parity.md'
  - 'Tests/AxionCLITests/Services/AgentBuilderToolProfileTests.swift'
  - 'Tests/AxionCLITests/Services/AgentBuilderCodingTests.swift'
  - 'Sources/AxionCLI/Services/AgentBuilder.swift'
externalPointerStatus: 'not_used'
gateDecision: 'PASS'
executionMode: 'yolo (非交互 Create)'
framework: 'Swift Testing (import Testing / @Suite / @Test / #expect)'
---

# 可追溯性矩阵与质量门决策 — Story 40.2 Shared Tool Profile Helper With Behavior Parity

**生成时间：** 2026-06-15
**Story：** 40.2（`40-2-shared-tool-profile-helper-with-behavior-parity`）
**覆盖基准（Oracle）：** 正式验收标准（formal requirements），置信度 high
**质量门决策：** **PASS**
**测试套件：** `@Suite("AgentBuilder.buildToolProfile (Story 40.2)")` — 7 个 `@Test`（单测文件 `Tests/AxionCLITests/Services/AgentBuilderToolProfileTests.swift`）

---

## 1. 可追溯性矩阵（AC → 验证方式 → 证据 → 覆盖状态）

| AC | 描述 | 验证层级 | 具体 @Test / 证据 | 覆盖状态 |
|----|------|----------|------------------|----------|
| **AC1** | 提取 shared tool profile helper，非 dry-run / dry-run 工具集 parity | **单测**（纯函数直接调用） | `test_buildToolProfile_nonDryrun_includesSkillMemoryStorageAndSaveSkill`（非 dry-run 含 Skill/Memory/6 Storage/save_skill）；`test_buildToolProfile_nonDryrun_excludesToolSearchAndAskUser`（沿用 `excludedToolNames`）；`test_buildToolProfile_nonDryrun_includesCoreAndSpecialistBaseTools`（core + specialist 全集）；`test_buildToolProfile_noSkillsTrue_omitsSkillToolOnly`（noSkills 仅省略 Skill） | ✅ FULL（4/4 绿） |
| **AC2** | helper 返回 `[ToolProtocol]`，`.name` 可读，纯函数无副作用 | **单测**（返回值 `.name` 反射） | `test_buildToolProfile_returnsToolProtocolsWithNameAccessible`（返回值非空、每个 `.name` 非空、工具名唯一性） | ✅ FULL（绿） |
| **AC3** | `build()` / `buildSkillAgent()` 可见行为不变 | **既有回归守护**（不新增 @Test） | 既有 `AgentBuilder.loadClaudeMd` 回归套件（`AgentBuilderCodingTests.swift` 5 个 `@Test`：`test_noClaudeMdFiles_returnsEmpty`、`test_allClaudeMdFiles_mergesContent`、`test_partialClaudeMdFiles_mergesExisting`、`test_emptyClaudeMdFiles_skipped`、`test_fileHeader_containsFilename`）；`build()` 现在调用提取的 `buildToolProfile(...)`（`AgentBuilder.swift` GREEN 阶段）；`buildSkillAgent()` 本 story 零改动。运行证据：`swift test --filter "AxionCLITests.AgentBuilder"` → `Test run with 12 tests in 2 suites passed`（含 7 新 ATDD + 5 既有 `loadClaudeMd`，零回归） | ✅ FULL（回归守护，非缺口） |
| **AC4** | dry-run 工具过滤不回退（排 Bash/Skill/Memory/Storage/save_skill） | **单测**（dry-run 入参排除集断言） | `test_buildToolProfile_dryrun_excludesBashAndSkill`（排 `["Bash","Skill"]`）；`test_buildToolProfile_dryrun_excludesSideEffectTools`（排 Memory/6 Storage/save_skill） | ✅ FULL（2/2 绿） |
| **AC5** | 新增单元测试覆盖非 dry-run 与 dry-run 工具名 parity | **单测**（本文件全部 @Test） | 全部 7 个 `@Test`（非 dry-run 路径 1/2/3/7 + dry-run 路径 4/5 + noSkills 隔离 6） | ✅ FULL（7/7 绿） |

> **AC3 覆盖说明（覆盖风格注记，非缺口）：** AC3 的性质是「行为不变」（parity-only refactor）。ATDD checklist §6.5 与 dev Completion Notes 均明确：AC3 **有意**由既有回归测试守护，而非新增断言式测试——因为「不变」的最佳证据是既有测试不受影响，新增断言反而可能掩盖回归。本 trace 接受此为正确策略（与 parity-only refactor 的本质一致），**不计为缺口**。

---

## 2. 覆盖率分析

### 2.1 单测可覆盖的 AC 通过率

单测可覆盖的 AC：**AC1 / AC2 / AC4 / AC5**（4 个，均为纯函数直接调用）。

- 通过：4/4 = **100%**
- 运行证据：`swift test --filter "AxionCLITests.AgentBuilderToolProfileTests"` →
  `Test run with 7 tests in 1 suite passed`（0.041s）

### 2.2 整体 AC 覆盖（含回归守护）

全部 5 个 AC 覆盖情况：

- **单测覆盖（绿）：** AC1、AC2、AC4、AC5 — 4 个
- **回归守护覆盖：** AC3（既有 `loadClaudeMd` 套件零回归 + `build()` 调用 helper） — 1 个

**整体 AC 覆盖率：5/5 = 100%**（无未解释缺口 / 无 unresolved gap）。

> 说明：AC3 在性质上不是新增断言式测试的对象（parity-only refactor 的验证方式是「既有测试零回归」）。按 BMAD trace 工作流与 risk-governance，未解释的覆盖缺口（unresolved gap）才会触发 FAIL；此处 AC3 有明确证据与解释，不计为缺口。

### 2.3 测试清单（去重）

| # | @Test | 文件 | AC | 层级 | 状态 |
|---|-------|------|----|------|------|
| 1 | `test_buildToolProfile_nonDryrun_includesSkillMemoryStorageAndSaveSkill` | `AgentBuilderToolProfileTests.swift` | AC1/AC5 | Unit | active |
| 2 | `test_buildToolProfile_nonDryrun_excludesToolSearchAndAskUser` | `AgentBuilderToolProfileTests.swift` | AC1/AC5 | Unit | active |
| 3 | `test_buildToolProfile_nonDryrun_includesCoreAndSpecialistBaseTools` | `AgentBuilderToolProfileTests.swift` | AC1/AC5 | Unit | active |
| 4 | `test_buildToolProfile_dryrun_excludesBashAndSkill` | `AgentBuilderToolProfileTests.swift` | AC4/AC5 | Unit | active |
| 5 | `test_buildToolProfile_dryrun_excludesSideEffectTools` | `AgentBuilderToolProfileTests.swift` | AC4/AC5 | Unit | active |
| 6 | `test_buildToolProfile_noSkillsTrue_omitsSkillToolOnly` | `AgentBuilderToolProfileTests.swift` | AC1 | Unit | active |
| 7 | `test_buildToolProfile_returnsToolProtocolsWithNameAccessible` | `AgentBuilderToolProfileTests.swift` | AC2 | Unit | active |
| R1–R5 | `test_noClaudeMdFiles_returnsEmpty` 等 5 个 `loadClaudeMd` 回归 | `AgentBuilderCodingTests.swift` | AC3（回归守护） | Unit | active |

**去重后测试总数：** 12 个（7 新 ATDD + 5 既有回归守护）；**skipped/fixme/pending：0**。

---

## 3. 质量门决策：**PASS**

### 决策依据（基于 risk-governance gate 规则）

按 gate 决策引擎逻辑（priority-thresholds 模式）：

1. **P0 覆盖：** 本 story 无 P0 标记的 AC（refactor/parity-only story，无收入/安全/破坏性数据风险） → P0 N/A（视同 100% MET）。
2. **P1 覆盖（PASS 目标 90%，最低 80%）：** 全部 5 个 AC（AC1–AC5）在 parity-only story 中均为高优先级行为守护，全部 FULL → **100% ≥ 90%** → MET。
3. **Overall 覆盖（最低 80%）：** 5/5 = **100% ≥ 80%** → MET。
4. **未解释覆盖缺口（unresolved gaps）：0** — AC3 有回归守护证据，非缺口。
5. **FAIL 条件（critical > 0 或 unresolved gap > 0 或 overall < 80%）：** 不满足。

→ 决策为 **PASS**。

### 关键证据

- `swift build --target AxionCLITests` → Build complete（GREEN 阶段，RED gate `no member 'buildToolProfile'` 消除）
- gate 套件实测：`swift test --filter "AxionCLITests.AgentBuilderToolProfileTests"` → `Test run with 7 tests in 1 suite passed`（0.041s）
- 回归守护实测：`swift test --filter "AxionCLITests.AgentBuilder"` → `Test run with 12 tests in 2 suites passed`（7 新 + 5 既有 `loadClaudeMd`，零回归）
- 全量单元测试（CLAUDE.md 命令）：`3820 tests in 247 suites`，仅 2 个 flaky 失败位于 `ReviewScheduler`/`CuratorScheduler`（异步事件发布 race，与 `buildToolProfile` 零耦合，grep 确认引用计数为 0）
- code-review 报告：**PASS**（fresh-context adversarial review，3 层 Blind Hunter / Edge Case Hunter / Acceptance Auditor）；5 个 AC 全满足，6 条 scope 红线全 clean

---

## 4. 缺口与风险

### 4.1 真实缺口

**无。** 单测可覆盖的 AC（1/2/4/5）通过率 100%，AC3 由既有回归守护覆盖，无任何未解释缺口。

### 4.2 覆盖风格注记（非缺口）

- **AC3 回归守护（parity-only refactor 的正确策略）：** AC3 不新增断言式 @Test，而由既有 `AgentBuilder.loadClaudeMd` 套件（5 个 `@Test`）+ `build()` 调用 helper 的事实共同守护「可见行为不变」。
  - **理由：** 「行为不变」的最佳证据是既有测试不受影响；新增断言式测试反而可能掩盖回归（ATDD checklist §6.5 与 dev Completion Notes 明确记录此决策）。
  - **性质：** 这是 parity-only refactor 的标准做法，**非缺陷、非阻塞**。

### 4.3 ATDD deviation（已据实处理，非缺口）

- **Deviation #1（save_skill 字面量）：** SDK `createSaveSkillTool` 要求非可选 `usageStore`，但 dry-run 路径测试传 `usageStore: nil`。dry-run @Test 用固定字面量 `"save_skill"` 断言「不应出现」（注释标明这是唯一无法从真实实例读取的场景，因构造 `createSaveSkillTool` 需非可选 store）。其余 @Test 中 save_skill 名一律从真实 `createSaveSkillTool(...).name` 读取。**符合** CLAUDE.md 反模式 #10 精神（工具名不硬编码）的唯一合规例外。
- **Deviation #2（返回类型）：** dev 选择返回裸 `[ToolProtocol]`（非 `ToolProfile` 结构体），与 ATDD checklist 入参标签完全一致，测试文件零改动即转 GREEN。Task 1.5 的 `ToolProfile` 选项未采用（YAGNI）。

### 4.4 已知预存在 flaky 测试（与本 story 无关）

code-review 记录：2 个 `ReviewScheduler`/`CuratorScheduler` flaky 测试为**预存在、与本 story 无关**的问题（grep 确认对 `AgentBuilder`/`buildToolProfile` 引用计数为 0），不构成 quality gate 阻塞。

---

## 5. 建议下一步

1. **推进 sprint-status 与 story 状态：** 将 Story 40.2 状态由 `done`（code-review 后已 done）确认并解锁依赖链下一节点。
2. **进入 Epic 40 线性链下一节点：** Story 40.3（注册 `Agent`/`Task` 工具到共享 helper）。gate 已证明 `buildToolProfile` 是可复用的纯函数组装点，后续 story（40.3 注册 Agent/Task、40.4 让 skill agent 用 discovered registry、40.5 MCP/Web/Search inheritance、40.6 permission policy）可安全在此 helper 上扩展。
3. **Review defer 跟踪项（可选，非本 story 范围）：** code-review 记录的 3 个 defer 项（`UniversalMemoryStore.init` 写盘措辞、`save_skill` 隐式耦合 `dryrun`/`noMemory`、`noMemory=true` 连带禁用 save_skill）均为 pre-existing 行为，已记录至 `deferred-work.md`。建议 Story 40.3+ 复用此 helper 前补一个局部 `if let usageStore, !dryrun` 防御性 guard（review 明确建议）。

---

## 附：gate 测试套件运行实测（2026-06-15，来自 story Debug Log）

```
RED gate 验证（实现前）：
  swift build --target AxionCLITests → error: type 'AgentBuilder' has no member 'buildToolProfile'（7 处调用全报错，确定性 RED）

GREEN 验证（实现后）：
  swift build --target AxionCLTests → Build complete（31.26s），RED gate 消除

gate 套件单跑：
  swift test --filter "AxionCLITests.AgentBuilderToolProfileTests"
  → Test run with 7 tests in 1 suite passed (0.041s)

回归守护：
  swift test --filter "AxionCLITests.AgentBuilder"
  → Test run with 12 tests in 2 suites passed（含 7 新 ATDD + 5 既有 loadClaudeMd，零回归）

全量单元测试（CLAUDE.md 命令）：
  → 3820 tests in 247 suites，仅 2 个 flaky 失败（ReviewScheduler/CuratorScheduler，与本 story 零耦合）
```
