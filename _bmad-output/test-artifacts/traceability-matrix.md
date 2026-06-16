---
stepsCompleted: ['step-01-load-context', 'step-02-discover-tests', 'step-03-map-criteria', 'step-04-analyze-gaps', 'step-05-gate-decision']
lastStep: 'step-05-gate-decision'
lastSaved: '2026-06-16'
tempCoverageMatrixPath: '/tmp/tea-trace-coverage-matrix-epic40.json'
gateStatus: 'PASS'
coverageBasis: 'acceptance_criteria'
oracleConfidence: 'high'
oracleResolutionMode: 'formal_requirements'
oracleSources:
  - '_bmad-output/specs/spec-task-subagent-skill-compat/SPEC.md'
  - '_bmad-output/specs/spec-task-subagent-skill-compat/test-plan.md'
  - '_bmad-output/specs/spec-task-subagent-skill-compat/architecture.md'
  - '_bmad-output/specs/spec-task-subagent-skill-compat/implementation-plan.md'
externalPointerStatus: 'not_used'
scope: 'Epic 40 — Claude Code skill/subagent 兼容（增量单元测试覆盖追溯）'
---

# Traceability Matrix & Quality Gate — Epic 40

> 范围：Epic 40（SPEC `task-subagent-skill-compat`）的可追溯矩阵与质量门决策。oracle = SPEC.md 的 CAP-1..CAP-8 验收标准。本轮新增 RunTaskTool 的 run_locked/failed/completed 三组单测（T1/T2/T3）一并纳入追溯。上一份完整 trace（Story 38.1，2026-06-07）已备份为 `traceability-matrix-story-38.1-2026-06-07.md`。

## Step 1: 覆盖 Oracle 解析

### Oracle 选择

| 项 | 值 |
|----|----|
| coverageBasis | `acceptance_criteria` |
| oracleResolutionMode | `formal_requirements` |
| oracleConfidence | **high** |
| externalPointerStatus | `not_used` |

**为何选此 oracle**：Epic 40 拥有完整保真合约（SPEC.md + 4 companion）。SPEC 用 8 条 capability（CAP-1..CAP-8）定义 intent + success criteria，`test-plan.md` 给出 CAP→Unit/E2E/Manual 映射。比「从源码推断 synthetic journey」更强的覆盖基准，故优先 formal requirements，无需降级到 synthetic oracle。

### 验收能力（Oracle 主体）

| CAP | Intent（摘要） | Success 关键判据 |
|-----|---------------|-----------------|
| CAP-1 | 直接运行含 `Task(...)` 的 filesystem skill，获得顺序子任务语义 | `/bmad-story-pipeline <id>` 按 workflow 顺序派生 Task 子任务；父等待每步完成 |
| CAP-2 | 识别 `Task` 工具形状，映射为 SDK `Agent` 别名 | 工具池有 `Agent`+兼容名 `Task`，同 schema/执行体；调用时 SDK 提供非空 `SubAgentSpawner` |
| CAP-3 | Task 子代理执行 `/skill-name args`，复用父 SkillRegistry | 子代理可经 Skill tool 执行 skill，而非当聊天文本/未知命令 |
| CAP-4 | 直接执行 filesystem skill 时可靠访问 supporting files | 能读取 skill 包内 `references/workflow-steps.md`，不依赖 cwd |
| CAP-5 | 保持 dry-run/no-skills/权限/工具边界语义 | dry-run 不暴露 Task/Skill/Bash；`--no-skills` 禁 pipeline；子代理默认不递归派生 |
| CAP-6 | streaming 可见每步开始/完成/失败/摘要 | 显示每个 Task 的 description、`/skill args`、状态、错误；失败则停止并报告 |
| CAP-7 | 可隔离单元测试 + 少量可选 E2E，不依赖真实外部服务 | Swift Testing 单测覆盖注册/schema/spawner/过滤/prompt 注入/dry-run；E2E 可跳过 |
| CAP-8 | 工具声明不被 lightweight runtime 静默缩窄 | direct skill + Task child 从同一可配池继承 core/specialist/Skill/Agent/Task/Web/MCP/ToolSearch；未知名产生诊断 |

### Knowledge Base 已加载（栈无关 core）

- `test-priorities-matrix.md`（P0–P3 评分）
- `risk-governance.md` + `probability-impact.md`（质量门打分/阈值）
- `test-quality.md`（DoD / 隔离 / green 判据）
- `selective-testing.md`（选择性执行）

> 与 automate 工作流一致：TEA 片段偏 Web，仅加载与追溯/质量门正交的核心片段。

### 工件清单（已定位）

- ✅ SPEC.md（8 CAP + Constraints + Non-goals）
- ✅ test-plan.md（CAP→覆盖矩阵 + 建议套件 + 默认验证命令）
- ✅ architecture.md / implementation-plan.md（设计决策与风险表，供 CAP 证据溯源）
- ✅ 本仓库实际测试文件（Step 2 发现）
- ℹ️ SDK 侧套件来源：`open-agent-sdk-swift` 0.10.0（远程仓库，本仓库 `swift test` 不可达 → 标外部覆盖）

### Next

→ 加载 `step-02-discover-tests.md`，发现本仓库实际测试工件，与 CAP 逐一建立追溯映射。

---

## Step 2: 发现并分类测试工件

### 测试目录扫描结果

Epic 40 相关测试集中在 `Tests/AxionCLITests/`，按层级分类：

#### Unit（本仓库 `swift test` 可达，默认验证范围）

| 文件 | case 数 | 层级 | 主要覆盖 |
|------|--------|------|---------|
| `Services/AgentBuilderToolProfileTests` | 7 | Unit | 工具 profile 字节级 parity（CAP-5/8） |
| `Services/AgentBuilderSubagentToolRegistrationTests` | 5 | Unit | Agent/Task/Skill 注册门（CAP-2/5） |
| `Services/AgentBuilderDiscoveredSkillRegistryTests` | 6 | Unit | discovered skill registry（CAP-1/3） |
| `Services/AgentBuilderPermissionAndDiagnosticsConsistencyTests` | 7 | Unit | allowed-tools 诊断/权限一致性（CAP-8） |
| `Services/AgentBuilderSlashSkillGuidanceTests` | 8 | Unit | slash-skill + Task prompt 引导（CAP-3） |
| `Services/AgentBuilderToolSearchAndMcpInheritanceTests` | 7 | Unit | ToolSearch/MCP/Web 继承（CAP-8） |
| `Services/SDKRuntimeReadinessGateTests` | 6 | Unit | SDK 0.10.0 Agent/Task/Skill schema 就绪（CAP-2/7） |
| `MCP/RunTaskToolTests` | **12** | Unit | run_task 异步执行 + **本轮新增 T1/T2/T3**（CAP-1/6） |
| `Fixtures/FixturePipelineAcceptanceTests` | 7 | Unit（fixture 驱动，无 live model） | pipeline 链路纯函数验收（CAP-1/3/4/5） |
| `Chat/ChatOutputFormatterChildTaskTests` | 5 | Unit | 子任务 streaming 输出（CAP-6） |

**本仓库 Unit 合计：10 文件 / 70 case**（RunTaskToolTests 含本轮 T1/T2/T3）

#### External（SDK 仓库 `open-agent-sdk-swift`，本仓库 `swift test` 不可达）

| 套件（test-plan.md 建议） | 主要覆盖 | 状态 |
|---------------------------|---------|------|
| `SubAgentToolAliasTests` | Task/Agent alias schema + spawner（CAP-2） | 🔶 外部仓库 |
| `DefaultSubAgentSpawnerToolFilteringTests` | 子代理工具过滤（排除 Agent/Task）（CAP-5） | 🔶 外部仓库 |
| `SkillExecutionPromptContextTests` | package context baseDir/supportingFiles（CAP-4） | 🔶 外部仓库 |
| `SkillToolDeclarationCompatibilityTests` | skill 工具声明兼容（CAP-8） | 🔶 外部仓库 |

> 4 套件位于远程 SDK 仓库，本仓库依赖以 `from: "0.10.0"` 解析。需在 `open-agent-sdk-swift` 本地 checkout 单独运行（test-plan.md 已注明）。

#### Manual / E2E（非默认验证，需 live model / 真实 AX）

- `test-plan.md` Manual Acceptance：真实 `/bmad-story-pipeline 1-1` 全链路（CAP-1/3/4/6）
- `_bmad-output/implementation-artifacts/epic-40-manual-acceptance-2026-06-16.md`：Epic 40 实测验收手册
- 可选 E2E：`Tests/AxionE2ETests/Interactive/`（需 API key + live model，可跳过）

### 执行状态标志

- 本仓库 70 case：全部 `enabled`，无 `skipped`/`pending`/`fixme`（本轮 `swift test --filter "RunTaskToolTests"` 12/12 绿）
- 外部 4 套件：本仓库不可达，状态未知（需 SDK 仓库验证）
- E2E：默认跳过（无 API key 环境）

### Coverage Heuristics 清单（供 Step 3/4 盲点检测）

- **错误路径覆盖**：✅ 强。dry-run/no-skills 排除、未知工具诊断、missing skill 失败渲染、`run_locked` 排他锁、executeTask 失败→`.failed` 均有显式负路径测试
- **权限/授权覆盖**：✅ 强。allowed-tools 交集收窄、permissionMode 透传、ToolSearch policy opt-in、surface 差异（telegram 保守等在 Storage 域，本 Epic 为 permission mode/dry-run）
- **API/契约覆盖**：N/A（无 HTTP 契约；CAP 是工具组装语义，非 REST 端点）
- **UI journey 覆盖**：N/A（命令行/agent 工具，非 UI 路由）
- **可观测盲点**：CAP-6（streaming 输出）仅 Unit 级格式化测试，真实 streaming 时序靠 Manual/E2E —— 已知降级覆盖

### Next

→ 加载 `step-03-map-criteria.md`，将 70 个 case + 外部/Manual 证据与 CAP-1..CAP-8 逐一建立追溯映射。

---

## Step 3: 追溯矩阵（CAP → 测试）

### 优先级分配（test-priorities-matrix）

| 优先级 | CAP | 依据 |
|--------|-----|------|
| **P0** | CAP-1, CAP-2 | 核心路径 / 硬阻塞：CAP-1 是 epic 头条能力；CAP-2 缺失则 "Agent spawner not available" |
| **P1** | CAP-3, CAP-4, CAP-5, CAP-8 | 主路径 + 安全边界（dry-run/no-skills/权限/工具可见性） |
| **P2** | CAP-6, CAP-7 | 可观测性（streaming）+ 可测性元能力 |

### 覆盖状态口径

- **FULL** = 本仓库 Unit 覆盖 Axion 侧逻辑 **且** 适当的更高级别验证存在（文档化 Manual 验收 / SDK 侧套件）
- **UNIT-ONLY** = 仅 Unit，缺适当更高级别
- **PARTIAL / NONE** = 部分 / 无覆盖

> 注：Epic 40 已完成（retro 10/10 story、0 CRITICAL/0 HIGH、Manual 验收已执行）。live-model 行为按 SPEC 设计由 Manual + 可选 E2E 覆盖，E2E 可跳过属设计意图非缺口。

### 追溯矩阵

| CAP | 优先级 | 覆盖 | 本仓库 Unit 证据（文件:要点） | 外部/Manual 证据 | 启发式 |
|-----|--------|------|------------------------------|------------------|--------|
| **CAP-1** Task skill 顺序执行 | P0 | **FULL** | `RunTaskToolTests`(run_id 提交/跟踪 + **T1 lock/T2 fail/T3 complete**); `FixturePipelineAcceptanceTests`(step-one→step-two 顺序、missing-skill 停止); `AgentBuilderDiscoveredSkillRegistryTests`(registry ensure 当前+同级); `AgentBuilderSubagentToolRegistrationTests`(Task 非 dryrun 注册) | Manual: `/bmad-story-pipeline` 实跑; SDK: SubAgentSpawner 顺序派生 | error-path ✅(T1/T2 + missing-skill) |
| **CAP-2** Task→Agent 别名+spawner | P0 | **FULL** | `SDKRuntimeReadinessGateTests`(createAgentTool→'Agent', createTaskTool→'Task', 共享 schema, 含 skills/mcpServers); `AgentBuilderSubagentToolRegistrationTests`(Agent+Task 同 profile) | SDK: `SubAgentToolAliasTests`, `DefaultSubAgentSpawnerToolFilteringTests` 🔶 | — |
| **CAP-3** 子代理执行 /skill + 复用 registry | P1 | **FULL** | `AgentBuilderSlashSkillGuidanceTests`(slash-skill+Task prompt 注入 8 case); `AgentBuilderDiscoveredSkillRegistryTests`(registry 复用); `FixturePipelineAcceptanceTests`(registry 解析 skill) | Manual: child 执行 /bmad-create-story | — |
| **CAP-4** supporting files 访问 | P1 | **FULL** | `FixturePipelineAcceptanceTests`(supporting file 路径解析、不依赖 cwd) | SDK: `SkillExecutionPromptContextTests`(baseDir/supportingFiles) 🔶; Manual: 读 workflow-steps.md | — |
| **CAP-5** dry-run/no-skills/权限边界 | P1 | **FULL** | `AgentBuilderToolProfileTests`(dry-run 排除 Bash/Skill/save_skill; no-skills 仅省 Skill); `AgentBuilderSubagentToolRegistrationTests`(dry-run 排除 Agent/Task); `AgentBuilderPermissionAndDiagnosticsConsistencyTests`(permissionMode/allowed-tools 交集); `RunTaskToolTests` **T1**(run_locked 排他) | SDK: `DefaultSubAgentSpawnerToolFilteringTests`(child 排除 Agent/Task) 🔶 | auth-neg ✅; error-path ✅ |
| **CAP-6** streaming 输出可见 | P2 | **FULL** ⚠️ | `ChatOutputFormatterChildTaskTests`(Task start/fail/success 渲染、无跨轮泄漏 5 case) | Manual: live streaming 显示 | 弱点：live 时序/中断仅 Manual |
| **CAP-7** 可隔离单测+可选 E2E | P2 | **FULL** | 70 个 in-repo Unit case 本身即证据（无真实外部服务）; `FixturePipelineAcceptanceTests` AC4+AC5(无网络、纯函数) | E2E 可选/可跳过（SPEC 设计意图） | — |
| **CAP-8** 工具声明不被静默缩窄 | P1 | **FULL** | `AgentBuilderToolProfileTests`(core/specialist/Memory/Storage 含); `AgentBuilderToolSearchAndMcpInheritanceTests`(Web/MCP/ToolSearch 继承); `AgentBuilderPermissionAndDiagnosticsConsistencyTests`(未知工具→诊断、绝不静默无限制) | SDK: `SkillToolDeclarationCompatibilityTests` 🔶 | error-path ✅(未知名诊断) |

### 覆盖逻辑校验

- ✅ P0/P1 全部有覆盖（CAP-1/2 P0；CAP-3/4/5/8 P1）
- ✅ 无重复覆盖问题：Fixture/Unit 各司其职，无同行为多层级冗余
- ✅ 非 happy-path-only：dry-run/no-skills 负路径、unknown-tool 诊断、run_locked、executeTask 失败、missing-skill 停止均有显式测试
- N/A API/auth/UI-journey（命令行 agent 工具，非 REST/UI）

### Next

→ Step 4 缺口分析 + 覆盖统计 + Phase 1 矩阵 JSON。

---

## Step 4: 缺口分析 + 覆盖统计（Phase 1）

**执行模式**：sequential（同 automate 理由：单 epic 范围、上下文完整、无需并行 fan-out）。

### 缺口分析

| 类别 | 数量 | 明细 |
|------|------|------|
| Critical gaps (P0 NONE) | **0** | CAP-1/2 均 FULL |
| High gaps (P1 NONE) | **0** | CAP-3/4/5/8 均 FULL |
| Medium gaps (P2 NONE) | **0** | CAP-6/7 均 FULL |
| Low gaps (P3 NONE) | 0 | 无 P3 |
| Partial coverage | 0 | — |
| Unit-only（缺适当更高级别） | 0 | 所有 CAP 的更高级别验证（Manual/SDK）均存在或按设计可跳过 |

### 启发式盲点检查

| 启发式 | 状态 | 说明 |
|--------|------|------|
| endpoints_without_tests | N/A | 非 REST 项目 |
| auth_negative_path_gaps | **0 (present)** | CAP-5 dry-run/no-skills/permission/lock 均有负路径 |
| happy_path_only_criteria | **0 (present)** | run_locked/fail/missing-skill/unknown-tool 诊断均有 |
| ui_journey_gaps | N/A | 非 UI |
| ui_state_gaps | N/A | 非 UI |

### 覆盖统计

| 指标 | 值 |
|------|----|
| 总需求数 | 8 |
| 完全覆盖 (FULL) | 8 |
| 部分覆盖 | 0 |
| 未覆盖 | 0 |
| **总体覆盖** | **100%** |
| P0 | 2/2 = **100%** |
| P1 | 4/4 = **100%** |
| P2 | 2/2 = **100%** |
| P3 | 0/0 = 100%（无 P3） |

### 去重测试清单

- 文件：**10**；case：**70**；skipped/fixme/pending：**0/0/0**
- by_level：unit=70（FixturePipelineAcceptanceTests 属 AxionCLITests unit target）；e2e/api/component=0

### Phase 1 矩阵 JSON

已写入 `/tmp/tea-trace-coverage-matrix-epic40.json`（frontmatter `tempCoverageMatrixPath` 记录）。

---

## Step 5: 质量门决策（Phase 2）

### 门决策逻辑

- collection_status = `COLLECTED`，allow_gate = `true` → **gateEligible = true**
- Rule 1（P0 必须 100%）：P0 = 100% → 通过
- Rule 2（总体 ≥ 80%）：overall = 100% → 通过
- Rule 3（P1 ≥ 80%）：P1 = 100% → 通过
- Rule 4（P1 ≥ 90% 且 P0 100% 且 overall ≥ 80%）→ **PASS**

### 🚨 GATE DECISION: ✅ PASS

**Rationale**：P0 覆盖 100%、P1 覆盖 100%（目标 90%）、总体覆盖 100%（下限 80%）。8 个 CAP 均有本仓库 Unit 证据覆盖 Axion 侧逻辑，并有文档化 Manual/SDK 覆盖端到端 success criteria。

| 门标准 | 要求 | 实际 | 状态 |
|--------|------|------|------|
| P0 覆盖 | 100% | 100% | **MET** |
| P1 覆盖（PASS 目标 / 下限） | 90% / 80% | 100% | **MET** |
| 总体覆盖 | ≥80% | 100% | **MET** |

### 覆盖摘要

- 总需求：8 · 完全覆盖：8 · 总体：**100%**
- P0 2/2 · P1 4/4 · P2 2/2 · P3 0/0
- 测试清单：10 文件 / 70 case / 0 skipped / 0 fixme / 0 pending
- 风险敞口：critical 0 · high 0 · medium 0 · low 0

### 诚实声明（PASS 的前提条件与保留意见）

> 这是一个**带保留意见的 PASS**，不是无条件绿灯。以下事实须明确：

1. **FULL 的口径**：本仓库 Unit 覆盖 **Axion 侧逻辑**（工具组装/profile/registry/prompt 注入/run_task 提交与状态/输出渲染），端到端 success criteria 由**文档化 Manual 验收**（Epic 40 已完成、retro 0 CRITICAL/0 HIGH）+ **SDK 侧套件**共同覆盖。live-model 行为按 SPEC 设计由 Manual + 可选 E2E 覆盖，E2E 可跳过属设计意图。
2. **外部验证依赖（✅ 已验证）**：test-plan.md 建议的 4 个套件**字面名不存在**于 SDK 仓库，但其描述的行为由**更厚的真实文件**覆盖，且已在本会话于 `open-agent-sdk-swift`（tag 0.10.0，工作树干净）实跑全绿（**289 tests, 0 failures**）。详见下文「外部 SDK 验证结果」。
3. **CAP-6 弱点**：streaming 输出的 live 时序/中断仅 Manual 覆盖，Unit 只测渲染逻辑。
4. 本次追溯**未改任何源码**，仅本轮 automate 新增的 RunTaskTool T1/T2/T3 已纳入 CAP-1/5/6 证据。

### 建议（非阻塞）

| 优先级 | 行动 | 状态 |
|--------|------|------|
| ~~MEDIUM~~ | ~~在 `open-agent-sdk-swift` 仓库验证 4 个 SDK 侧套件~~ | ✅ **已完成**（289 tests / 0 failures，见下） |
| LOW | 若 streaming 鲁棒性变关键，为 CAP-6 增加可选 E2E fixture | 待定 |
| LOW | 运行 `/bmad-testarch-test-review` 复核 Epic 40 单测套件质量 | 待定 |

### 外部 SDK 验证结果（2026-06-16，本会话实测）

SDK 仓库 `/Users/nick/CascadeProjects/open-agent-sdk-swift`：tag **0.10.0**，HEAD `4285aac`（含 Epic 40 subagent/skill 继承），工作树干净。

**test-plan.md 建议套件名 → 实际 SDK 文件映射 + 实跑结果：**

| 建议套件（test-plan.md） | 覆盖的 CAP | 实际 SDK 文件 | case | 结果 |
|--------------------------|-----------|--------------|------|------|
| `SubAgentToolAliasTests` | CAP-2 | `Tools/Advanced/TaskToolsTests` + `Tools/Advanced/AgentToolTests` | 57 + 30 | ✅ pass |
| `DefaultSubAgentSpawnerToolFilteringTests` | CAP-2/5 | `Core/AgentSpawnerDetectionTests` + `Core/DefaultSubAgentSpawnerTests` | 8 + 39 | ✅ pass |
| `SkillExecutionPromptContextTests` | CAP-4 | `Tools/Advanced/ExecuteSkillTests` + `ExecuteSkillStreamTests` + `Skills/SkillLoaderTests` | 16 + 15 + 61 | ✅ pass |
| `SkillToolDeclarationCompatibilityTests` | CAP-8 | `Tools/Advanced/SkillToolTests` + `Compat/SubagentSystemCompatTests` | 21 + 42 | ✅ pass |

**合计：289 tests，0 failures**（CAP-2/5 批 134 + CAP-4/8 批 155）。运行命令（SDK 仓库内）：
```bash
swift test --filter "TaskToolsTests" --filter "AgentToolTests" --filter "AgentSpawnerDetectionTests" --filter "DefaultSubAgentSpawnerTests"
swift test --filter "ExecuteSkillTests" --filter "ExecuteSkillStreamTests" --filter "SkillToolTests" --filter "SkillLoaderTests" --filter "SubagentSystemCompatTests"
```

**结论**：外部覆盖**已坐实**，PASS 门置信度从「带保留」提升为「证据充分」。test-plan.md 的建议名仅作占位，真实覆盖更厚（如 TaskToolsTests 单文件 57 case）。

### 机器可读输出

- `traceability/e2e-trace-summary-epic-40.json` —— 完整机器可读摘要（CI/仪表盘可消费）
- `traceability/gate-decision-epic-40.json` —— 精简门信号（`gate_status: PASS`）
- `/tmp/tea-trace-coverage-matrix-epic40.json` —— Phase 1 完整覆盖矩阵

### Next

工作流结束。`on_complete` 钩子为空，正常退出。
