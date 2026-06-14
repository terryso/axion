---
project: axion
epic: epic40
date: '2026-06-15'
stepsCompleted:
  - step-01-document-discovery
filesIncluded:
  epic: docs/epics/epic-40-claude-code-skill-subagent-compat.md
  spec:
    - _bmad-output/specs/spec-task-subagent-skill-compat/SPEC.md
    - _bmad-output/specs/spec-task-subagent-skill-compat/architecture.md
    - _bmad-output/specs/spec-task-subagent-skill-compat/implementation-plan.md
    - _bmad-output/specs/spec-task-subagent-skill-compat/test-plan.md
    - _bmad-output/specs/spec-task-subagent-skill-compat/brownfield-analysis.md
    - _bmad-output/specs/spec-task-subagent-skill-compat/.decision-log.md
  baseline_reference:
    - _bmad-output/planning-artifacts/architecture.md
    - _bmad-output/planning-artifacts/prd.md
    - _bmad-output/planning-artifacts/epics.md
  ux: null
---

# Implementation Readiness Assessment Report

**Date:** 2026-06-15
**Project:** axion
**Epic:** epic40 — Claude Code 技能/子代理兼容性

---

## Step 1: Document Discovery（文档发现）

### 评估采用的文档（Epic40 焦点集）

| 类型 | 路径 | 大小 | 修改日期 |
|------|------|------|----------|
| Epic | `docs/epics/epic-40-claude-code-skill-subagent-compat.md` | 26.6 KB | 2026-06-14 23:59 |
| SPEC | `_bmad-output/specs/spec-task-subagent-skill-compat/SPEC.md` | 9.6 KB | 2026-06-15 00:00 |
| Architecture | `_bmad-output/specs/spec-task-subagent-skill-compat/architecture.md` | 11.8 KB | 2026-06-15 00:00 |
| Implementation Plan | `_bmad-output/specs/spec-task-subagent-skill-compat/implementation-plan.md` | 10.8 KB | 2026-06-15 00:00 |
| Test Plan | `_bmad-output/specs/spec-task-subagent-skill-compat/test-plan.md` | 7.3 KB | 2026-06-15 00:00 |
| Brownfield Analysis | `_bmad-output/specs/spec-task-subagent-skill-compat/brownfield-analysis.md` | 10.0 KB | 2026-06-14 10:34 |

### 项目基线文档（对照参考）

| 类型 | 路径 | 大小 | 修改日期 |
|------|------|------|----------|
| 主 PRD | `planning-artifacts/prd.md` | 26.6 KB | 2026-05-08 |
| 主 Architecture | `planning-artifacts/architecture.md` | 90.5 KB | 2026-06-13 |
| 主 Epics | `planning-artifacts/epics.md` | 165.2 KB | 2026-06-12 |

### 发现的问题

1. **无 UX 文档（WARNING，预计 N/A）**：epic40 是开发者侧/CLI 兼容功能，预计无需 UI/UX 设计。后续步骤确认。
2. **存在 2026-06-14 旧报告**：epic40 配套文档于 2026-06-15 00:00 刚更新，本次报告反映最新内容。
3. **无重复格式冲突**：epic40 无「整体 + 分片」并存情况。

---

## Step 2: PRD Analysis（需求提取）

### 需求来源说明

epic40 采用新 BMAD spec 格式：以 **Capabilities (CAP-1..8)** 表达功能能力、**Constraints** 表达功能/非功能约束、**Stories 40.1..40.10** 各带 Acceptance Criteria。本节将其映射为等价的 FR/NFR，便于 traceability 验证。需求完全来自 epic40 专属 spec 集（Epic + SPEC）；主 PRD（2026-05-08）早于 epic40，不含 epic40 需求。

### Functional Requirements（功能需求，源自 CAP + Story AC）

**FR1（CAP-1）：顺序子任务执行** — 用户可在 Axion 直接运行含 Claude Code `Task(...)` 指令的 filesystem skill，安装 `bmad-story-pipeline` 及引用的单步 skills 后，`/bmad-story-pipeline <story-id>` 按 workflow 文件顺序派生每个 Task 子任务，父等待每个子任务完成后再进入下一步。

**FR2（CAP-2）：Agent/Task 工具别名** — 工具池存在 `Agent` 和兼容名 `Task` 两个 subagent launcher；共用同一 schema 和执行体，接受 `prompt`、`description`、`subagent_type`；模型调用任一名称时 SDK 提供非空 `SubAgentSpawner`，返回子代理结果而非 `Agent spawner not available`。

**FR3（CAP-3）：子代理执行 slash skill** — 子代理收到 `Execute /bmad-create-story 1-1 yolo ...` 时，可通过 `Skill` tool 执行该 skill，而非把 slash 文本当聊天或报未知命令；复用父会话已发现的 SkillRegistry。

**FR4（CAP-4）：skill 包 supporting files 访问** — 直接 `/bmad-story-pipeline 1-1` 时，agent 能从 skill 目录 `baseDir` 定位并读取 `references/workflow-steps.md`，不依赖当前工作目录碰巧存在同名相对路径。

**FR5（CAP-5）：保持既有权限/工具边界** — dry-run 不暴露 side-effect Task/Skill/Bash 工具；`--no-skills` 不允许 pipeline 执行；子代理默认不继承 `Agent`/`Task` 递归派生能力（除非未来显式开启嵌套）。

**FR6（CAP-6）：streaming 进度可见性** — 运行 pipeline 时终端至少显示每个 Task 的 `description`、被执行的 `/skill-name args`、完成状态、错误信息；任一步失败时父 pipeline 停止并报告失败步骤。

**FR7（CAP-7）：可隔离测试** — Swift Testing 单元测试覆盖 tool 注册、Task schema、spawner 注入、子代理工具过滤、skill supporting-file prompt 注入、dry-run/no-skills 行为；真实 API E2E 仅作为可跳过验证，不进入默认单元测试。

**FR8（CAP-8）：工具声明不被静默缩窄** — direct skill execution 和 Task child agent 从同一份可配置工具池继承 SDK core/specialist、Skill、Agent/Task、WebSearch/WebFetch、MCP resource/tool、ToolSearch 可见性策略；`allowed-tools`/subagent `tools` 能过滤这些工具，未知/不支持工具名产生可诊断信息，而非退化为「无限制」或静默忽略。

**FR9（Story 40.1）：SDK readiness gate** — Axion `Package.swift` 升到 `open-agent-sdk-swift` 0.10.0+ 并更新 `Package.resolved`；可 import 并注册 `createAgentTool()`、`createTaskTool()`、`createSkillTool(registry:)`；`executeSkillStream` 已由 SDK 注入 skill package context。

**FR10（Story 40.2）：shared tool profile helper** — 从 `AgentBuilder.build()` 提取可复用 tool profile helper，先复刻当前 chat/run 工具集（不引入新行为），保持 `build()`/`buildSkillAgent()` 现有可见行为；helper 返回 `[ToolProtocol]` 或 debug metadata 供测试。

**FR11（Story 40.3）：跨路径注册 Agent/Task/Skill** — 普通 chat/run agent（非 dry-run）注册 `createAgentTool()`+`createTaskTool()`；direct skill agent（非 dry-run）注册 `Agent`+`Task`+`Skill`；`--no-skills` 禁用 `/skill-name` routing 和 `Skill` tool 但不禁用 generic `Agent/Task`；dry-run 移除 `Skill`/`Agent`/`Task`。

**FR12（Story 40.4）：direct skill 使用 discovered registry** — `buildSkillAgent()` 使用 discovered `SkillRegistry`（非仅当前 skill）；`createSkillTool(registry:)` 和 `AgentOptions.skillRegistry` 使用同一 registry，让 SDK child registry inheritance 生效；child 找不到 skill 时错误保留原 skill 名和 args。

**FR13（Story 40.5）：MCP/Web/Search 工具继承** — shared tool profile 覆盖 MCP resource/connected tools、WebSearch、WebFetch、ToolSearch；skill agent 按同一 profile 继承，除非 config/dry-run/permission/restriction 移除；非 read-only MCP/custom tools 在 dry-run/禁止写入模式被过滤。

**FR14（Story 40.6）：权限/allowlist/diagnostics 一致** — session allowlist 父已允许的 tool name/pattern 可被 skill/child agent 继承但不扩大；permission mode 跨三类 agent 一致；`allowed-tools` 先收窄再应用 session allowlist；SDK deferred/unsupported diagnostics 在 Axion 输出或 verbose logs 可见，不被吞为成功摘要。

**FR15（Story 40.7）：child agent slash skill guidance** — `Skill`+`Agent/Task` 同时可用时，父/子 system prompt 加入 guidance，明确 `Execute /<skill-name> <args>` 应调用 `Skill(skill:..., args:...)`。

**FR16（Story 40.8）：child task 输出格式** — tool input preview 显示 `description`；tool result 含 child 文本摘要；child error 时 `Task` 返回 `isError: true` 并保留 error text；compact mode 不重复打印大段 child prompt。

**FR17（Story 40.9）：fixture pipeline 验收** — fixture skills `pipeline-test`/`step-one`/`step-two`，覆盖 success/missing-skill failure/dry-run filtering 三条 path；无 API key 时跳过 LLM-dependent path，单元层仍验证 registry/profile/prompt guidance。

**FR18（Story 40.10）：本地 BMAD pipeline 手工验收** — 验证 `~/.agents/skills/bmad-story-pipeline/SKILL.md` 与 `references/workflow-steps.md` 命令名一致；不硬编码 `/bmad-bmm-*`→`/bmad-*` 映射；记录 SDK commit/hash、Axion commit/hash、skill package 路径。

**Total FRs: 18**

### Non-Functional Requirements（非功能需求，源自 Constraints）

**NFR1：技术栈约束** — 必须用 Swift + 现有 `open-agent-sdk-swift` path dependency，运行时不得引入 Node.js 或 Python 编排层（对齐项目反模式 #3、#4）。

**NFR2：路由优先级不变** — 必须保持现有 `/skill-name args` 路由：built-in slash command 优先 → SkillRegistry 匹配第二 → 未知 `/xxx` 透传普通 agent。

**NFR3：复用优先（不复制 runtime）** — 必须优先复用 SDK 已有 `AgentTool`、`SubAgentSpawner`、`SkillTool`、`SkillRegistry`、`executeSkillStream`，避免在 Axion 侧复制 agent runtime。

**NFR4：side-effect tool 安全语义** — `Task` 是 side-effect tool；dry-run、权限模式、tool allowlist、session allowlist 必须按现有工具规则处理（对齐 SafetyHook、sharedSeatMode）。

**NFR5：递归防护** — 子代理默认移除 `Agent` 与 `Task`，避免无限递归/失控并发；未来 nested subagents 必须显式开启并有深度/预算限制。

**NFR6：能力不静默丢失** — 不允许因 lightweight path 一刀切移除 MCP、WebSearch/WebFetch、ToolSearch 或跨 skill 调用能力；这些工具由 config/permission/allowed-tools/mcpServers/dry-run/no-skills 共同决定。

**NFR7：ToolSearch 策略** — `ToolSearch` 启用由 provider/config policy 决定；skill/subagent 声明 `ToolSearch` 仅作 opt-in request，不能覆盖用户禁用、dry-run、permission、安全策略（对齐 GLM ToolSearch 问题）。

**NFR8：allowed-tools 解析健壮性** — `allowed-tools` 解析必须能表达 Claude Code 工具名、SDK 工具名、`Agent`/`Task`/`Skill`/Web tools/MCP namespaced tool；遇到未知工具名不退化为无限制。

**NFR9：单元测试隔离** — 单元测试必须用 Swift Testing，不能调用真实 `AgentBuilder.build()`、真实 MCP、真实 Helper 进程或桌面通知（对齐 CLAUDE.md 测试规则）。

**NFR10：默认验证范围** — 开发完成后默认只运行项目定义的单元测试范围，不运行 `Tests/**/Integration/` 或 `Tests/**/AxionE2ETests/`（对齐 CLAUDE.md）。

**Total NFRs: 10**

### Additional Requirements（约束/假设/延后项）

**前置依赖（hard）：**
- SDK Epic 29 MVP Gate（Story 29.1/29.2/29.3/29.7）已发布于 SDK 0.10.0（commit `4285aac6535236dae014e945eed694ed7fe6bd4b`）。
- Policy/Diagnostics Gate（Story 29.4/29.5/29.6）—— Story 40.5/40.6 全量完成需 SDK 0.10.0+。

**假设：**
- `Task(subagent_type: "general-purpose", ...)` 是主要兼容目标形状。
- `general-purpose` 子代理不需专门 AgentDefinition，可继承父模型和默认系统提示。
- BMAD 单步 skills 已通过 `.agents/skills` 或 `.claude/skills` 安装并可被 SkillRegistry 发现。
- 真实 pipeline 长耗时行为由现有 maxSteps 和权限策略约束，本 spec 不新增独立预算系统。

**明确非目标（延后项）：**
- 加载 `.claude/agents/*.md` / `.agents/agents/*.md` filesystem subagent definitions。
- background/resume/isolation/team semantics。
- skill listing budget、visibility overrides、`disable-model-invocation` 大规模 skill library 体验。
- MCP `alwaysLoad` 配置和 individual tool `_meta` 支持。

**Open Questions（4 项，需决策但不阻塞 MVP）：**
- OQ1：Task 子代理层级 tree 显示 vs 现有 tool progress+文本摘要。
- OQ2：旧 BMAD 命令名 `/bmad-bmm-create-story` 的 alias migration 提示 vs 要求用户同步 skill 包。
- OQ3：是否补齐 `.claude/agents/*.md` filesystem subagent discovery。
- OQ4：`ToolSearch` 是否补齐完整 deferred tool index / alwaysLoad 体验。

### PRD 完整性初评

- **清晰度高**：每条 capability 都有可观测的 success 信号；每条 story 都有 Given/When/Then AC。
- **范围明确**：What's in / What's out（非目标 + 延后项）边界清晰，明确「不实现 workflow/DAG 引擎」「不硬编码 BMAD 命令映射」。
- **可追溯性强**：Story 间依赖链（40.1→40.2→...→40.10）显式定义。
- **前置 gate 严谨**：SDK readiness gate 明确区分 MVP Gate（必须先完成）与 Policy/Diagnostics Gate（全量验收需要）。
- **潜在缺口**：4 个 Open Questions 未决策（标记为不阻塞 MVP，但 FR17/FR18 验收时 OQ2 可能影响手工验收路径）。

---

## Step 3: Epic Coverage Validation（覆盖验证）

### 覆盖范围说明

本次为单 epic 就绪性检查，被验证的「epics document」即 epic40 自身（Epic + Stories 40.1–40.10）。下表把 Step 2 提取的 18 个 FR 映射到实现它们的 Story/AC，验证每条 FR 都有可追溯路径。

### Coverage Matrix（覆盖矩阵）

| FR | 需求（缩写） | 覆盖 Story / AC | 状态 |
|----|------|------|------|
| FR1 (CAP-1) | 顺序子任务执行 | 40.3+40.4+40.7+40.8+40.9+40.10 | ✓ Covered |
| FR2 (CAP-2) | Agent/Task 工具别名 | 40.1 (SDK gate: createTaskTool+schema) + 40.3 (register) | ✓ Covered |
| FR3 (CAP-3) | 子代理执行 slash skill | 40.4 (registry) + 40.7 (guidance) | ✓ Covered |
| FR4 (CAP-4) | supporting files 访问 | 40.1 (SDK package context AC) + 40.10 | ✓ Covered |
| FR5 (CAP-5) | 权限/dry-run/no-skills 边界 | 40.3 (dry-run移除) + 40.5 + 40.6 | ✓ Covered |
| FR6 (CAP-6) | streaming 进度可见 | 40.8 | ✓ Covered |
| FR7 (CAP-7) | 可隔离测试 | 40.9 | ✓ Covered |
| FR8 (CAP-8) | 工具不被静默缩窄 | 40.2 (shared profile) + 40.5 (inheritance) | ✓ Covered |
| FR9 (Story 40.1) | SDK readiness gate | 40.1 | ✓ Covered |
| FR10 (Story 40.2) | shared tool profile helper | 40.2 | ✓ Covered |
| FR11 (Story 40.3) | 跨路径注册 Agent/Task/Skill | 40.3 | ✓ Covered |
| FR12 (Story 40.4) | direct skill 用 discovered registry | 40.4 | ✓ Covered |
| FR13 (Story 40.5) | MCP/Web/Search 继承 | 40.5 | ✓ Covered |
| FR14 (Story 40.6) | 权限/allowlist/diagnostics 一致 | 40.6 | ✓ Covered |
| FR15 (Story 40.7) | child agent slash guidance | 40.7 | ✓ Covered |
| FR16 (Story 40.8) | child task 输出格式 | 40.8 | ✓ Covered |
| FR17 (Story 40.9) | fixture pipeline 验收 | 40.9 | ✓ Covered |
| FR18 (Story 40.10) | 本地 BMAD 手工验收 | 40.10 | ✓ Covered |

### Missing FR Coverage（缺失项）

**无 Critical 缺失，无 High Priority 缺失。** 18/18 FR 均有可追溯的 Story 实现。

### 覆盖质量观察（非缺失，但值得注意）

1. **能力级 FR 多 Story 协同覆盖**：FR1（顺序子任务）需 6 个 story 协同（注册→registry→guidance→输出→fixture→手工验收）。这是 workflow 能力的固有特性，非冗余。**建议**：40.9 fixture 应作为 FR1 的集成回归锚点，确保协同路径不被任一 story 单独破坏。

2. **OQ2 实际已在 Story 层决策**：Open Question「旧命令名 alias migration」在 Story 40.10 AC 中已有明确立场（不硬编码映射，错误提示建议同步 skill 包或添加 aliases）。**建议**：把 OQ2 状态从「未决策」更新为「已决策（不硬编码）」，避免实施时重复讨论。

3. **diagnostics 渲染归属明确**：CAP-8「未知工具名产生可诊断信息」由 Story 40.6 point 4（Axion terminal/verbose logs 显示 SDK diagnostics）承接。**建议**：40.6 实施时明确 diagnostics 的输出 formatter branch（与 40.8 的 tool result 输出协调，避免双重格式化——对齐项目反模式 #17）。

4. **FR4（supporting files）依赖 SDK gate**：Axion 侧无独立实现 story，完全依赖 Story 40.1 验证 SDK 0.10.0 已注入 package context。**风险**：若 SDK 行为与 AC 预期不符，Axion 无回退实现路径。**建议**：40.1 AC 中的「skill prompt 包含 SDK package context」必须是断言式验证（非人工目测）。

### Coverage Statistics（覆盖统计）

- Total PRD FRs: 18
- FRs covered in epics: 18
- Coverage percentage: **100%**

---

## Step 4: UX Alignment（UX 对齐验证）

### UX Document Status

**未找到 epic40 专属 UX 文档。** Step 1 搜索确认：`planning-artifacts/` 与 `docs/` 下无 epic40 相关 UX/设计文档（仅存在 epic-38 等 TUI UX 文档，与本 epic 无关）。

### UX 是否隐含需要（评估）

逐项检查：

| 检查项 | 结论 |
|--------|------|
| PRD 提及用户界面（GUI）？ | 否 — epic40 全部为 CLI/runtime/工具池行为 |
| 隐含 web/mobile 组件？ | 否 — 纯 Swift CLI + SDK runtime |
| 是否面向终端用户的图形应用？ | 否 — 开发者侧/CLI 兼容功能 |
| 是否有终端文本输出 UX 面？ | **是** — FR6/FR16（child task 进度/失败输出） |

### 终端输出 UX 是否已规约

**是，已在 epic 内内联规约。** Story 40.8 提供了具体的 success/failure 输出格式样例：

```
[Task] Create story
  command: /bmad-create-story 1-1 yolo
  status: running → completed
  summary: Story draft created and saved.
```

```
[Task] Create story
  command: /missing-skill demo
  status: failed
  error: Skill "missing-skill" not found or not registered
  retry: /missing-skill demo
```

Story 40.8 同时明确：compact mode 不重复打印大段 child prompt；verbose/debug mode 可显示更多 tool detail；默认复用现有 `SDKMessage.toolUse`/`toolProgress` 输出，仅不足时新增 formatter branch。这些是终端 UX 的充分规约。

### Alignment Issues

**无 UX ↔ PRD / UX ↔ Architecture 对齐问题**（因无独立 UX 文档，终端输出 UX 直接由 Story 40.8 AC 规约，且由 architecture 中 streaming event 管线支撑）。

### Warnings

**无阻塞 warning。** 一项低优先级备注：

- **OQ1 相关**（Task 子代理层级 tree 显示 vs 现有 tool progress+文本摘要）：这是一个 UX 呈现选择，目前在 Story 40.8 倾向「现有 tool progress + 文本摘要」（不引入 tree）。若未来用户反馈需要层级 tree，需新增 formatter。**不阻塞 MVP。**

### 结论

UX 文档缺失是 **预期内且可接受** 的（epic40 无图形界面），终端输出 UX 已在 Story 40.8 充分规约。无需补充 UX 文档即可进入实施。

---

## Step 5: Epic Quality Review（Epic 质量审查）

### 已验证的 Brownfield 事实（代码级核实）

在应用 best-practices 标准前，先核实 epic 声称的代码事实与 SDK 前置依赖是否真实——这是 readiness 的事实基础：

| Epic 声称 | 核实结果 |
|----------|----------|
| Axion `Package.swift` 当前 `from: "0.8.0"` | ✓ 准确（`Package.swift:18`） |
| `Package.resolved` pin 到 0.8.3 | ✓ 准确（revision `3a42f5c`） |
| `ChatCommandInputRouter` 存在并路由 `/skill-name` | ✓ 存在（`Sources/AxionCLI/Chat/ChatCommandInputRouter.swift`） |
| `executeSkillStream(name,args:)` 存在 | ✓ 存在（`ChatCommand.swift`、`AxionRuntime+SkillExecution.swift`） |
| `AgentBuilder.buildSkillAgent(...)` 存在 | ✓ 存在（`AgentBuilder.swift:302`） |
| `AgentBuilder.build(...)` 存在 | ✓ 存在（`AgentBuilder.swift:62`） |
| SDK 0.10.0 已发布 | ✓ 已发布（远程 `refs/tags/0.10.0` → commit `4285aac`，在 `origin/main`） |
| SDK commit `4285aac...` | ✓ 准确（本地 SDK repo HEAD 即此 commit） |
| `createTaskTool()` 存在（Story 29.1） | ✓ 存在（SDK `Tools/Advanced/AgentTool.swift:312`） |
| `createAgentTool()` 存在 | ✓ 存在（SDK `Tools/Advanced/AgentTool.swift:294`） |
| `createSkillTool(registry:)` 存在 | ✓ 存在（SDK `Tools/Advanced/SkillTool.swift:34`） |
| `DefaultSubAgentSpawner` 存在（Story 29.2） | ✓ 存在（SDK `Tools/Advanced/AgentTool.swift`） |
| SDK Epic 29 文档存在 | ✓ 存在（SDK `docs/epics/epic-29-claude-code-skill-subagent-compat.md`） |

**结论：epic 的全部 brownfield 事实与 SDK gate 前置依赖经代码级核实均 ACCURATE，SDK 0.10.0 已发布到远程，Story 40.1 gate 可达。** 这是该 epic 最大的 readiness 优势——风险前置且已验证。

### Best Practices 合规清单

| 检查项 | 结果 | 说明 |
|--------|------|------|
| Epic 交付用户价值 | ✓ PASS | 「端到端运行 Claude Code/BMAD workflow skill」是用户可感知结果 |
| Epic 可独立运作 | ✓ PASS | 仅依赖已发布的 Axion 功能 + 外部 SDK Epic 29（跨仓 gate），无前向 Axion-epic 依赖、无循环依赖 |
| Story 大小合适 | ~ 基本合规 | 40.1/40.2/40.9 为 enabling/maintainer story（3/10），但显式标注且是兼容 epic 的固有需要 |
| 无前向依赖 | ✓ PASS | 线性链 40.1→…→40.10，每个 story 仅依赖**先前** story，无对未来 story 的引用 |
| Database 按需创建 | N/A | 本 epic 无数据库 |
| AC 清晰（Given/When/Then） | ✓ PASS | 10 个 story 全部使用 BDD Given/When/Then 结构 |
| FR 可追溯性 | ✓ PASS | 100% 覆盖（Step 3） |

### A. Epic 用户价值焦点

- **Epic 标题**「Run Claude Code/BMAD Workflow Skills End-to-End」：用户中心（用户能做什么），非技术里程碑。✓
- **产品目标** 6 条全部用户视角：「用户可以在 Axion 中运行 /bmad-story-pipeline... 并看到子任务按顺序执行」。✓
- **非 epic 级技术里程碑**：对比反例「Refactor AgentBuilder」——epic40 把重构（40.2）作为**手段**而非 epic 目标，epic 目标是运行 workflow skill。✓ PASS。

### B. Epic 独立性

- 跨仓依赖：SDK Epic 29（外部），由 Story 40.1 gate 隔离（fail-fast 模式）。✓
- 仓内依赖：仅依赖**已发布**的 Axion 能力（skill discovery、`/skill-name` routing、`SDKMessage` streaming），这些是早期 epic 已交付的功能。✓
- 无对 epic41+ 的前向引用。✓ PASS。

### C. Story 质量评估

| Story | 用户价值 | 独立可完成 | AC 质量 | 错误条件覆盖 |
|-------|----------|-----------|---------|------------|
| 40.1 SDK gate | enabling（显式标注） | ✓ | Given/When/Then ✓ | blocked/deferred 分支 ✓ |
| 40.2 profile helper | refactor（显式标注） | ✓ | parity 测试 ✓ | dry-run 回归 ✓ |
| 40.3 register | ✓ | ✓ | 三路径 tool name 检查 ✓ | dry-run/--no-skills ✓ |
| 40.4 discovered registry | ✓ | ✓ | fixture skills ✓ | missing-skill 错误 ✓ |
| 40.5 MCP/Web/Search | ✓ | ✓ | 可用性+过滤 ✓ | policy-disabled+dry-run ✓ |
| 40.6 permission/diagnostics | ✓ | ✓ | allowlist 收窄 ✓ | diagnostics 可见 ✓ |
| 40.7 slash guidance | ✓ | ✓ | guidance 文本+工具 ✓ | missing-skill 停止 ✓ |
| 40.8 child task 输出 | ✓ | ✓ | 5-step 进度 ✓ | 失败停止+重试命令 ✓ |
| 40.9 fixture 验收 | maintainer | ✓ | success/failure/dry-run ✓ | missing-skill ✓ |
| 40.10 本地 BMAD 手工 | ✓ | ✓ | 命令名一致性 ✓ | 旧命令名+建议 ✓ |

全部 story AC 测试性、完整性良好，错误条件覆盖充分。

### D. 依赖分析（仓内）

显式依赖链（epic 自带）：

```
40.1 → 40.2 → 40.3 → 40.4 → 40.5 → 40.6 → 40.7 → 40.8 → 40.9 → 40.10
```

- 方向正确：每个 story 仅依赖**先前** story（无前向引用、无循环）。✓
- 每个 story 在其位置独立可完成并交付增量价值。✓

### E. Brownfield 特殊检查（epic40 为 brownfield 集成）

- ✓ 与现有系统集成点明确（且经代码核实存在，见上表）
- ✓ 迁移/兼容 story 齐备：40.1（SDK 版本迁移）、40.2（parity 重构）、40.10（BMAD 命令名兼容）
- ✓ Brownfield 文档质量优秀：epic 含「当前代码事实」+「Axion 当前缺口」章节 + `brownfield-analysis.md` companion
- ✓ Starter template / CI early setup：N/A（brownfield，无新项目脚手架）

### Findings by Severity（按严重度归类）

#### 🔴 Critical Violations

**无。**

#### 🟠 Major Issues

**无。** （初判的 SDK 依赖接线风险已解除：SDK 0.10.0 经核实已发布到远程 `refs/tags/0.10.0`，`from: "0.10.0"` 升级可正常 resolve。）

#### 🟡 Minor Concerns

1. **project-context.md 文档不准确**：声称「OpenAgentSDK 本地 path-based SPM 依赖」，但实际 `Package.swift:18` 声明为**远程 URL** `from: "0.8.0"`。当前构建实际用远程 ~0.8.x（commit `3a42f5c`），而非本地 0.10.0 repo。
   - **影响**：低（功能正常）。但 Story 40.1 实施者若误信「path 依赖」可能困惑。
   - **建议**：Story 40.1 完成时同步修正 project-context.md 的 SDK 依赖描述为「远程 URL + from: 版本」。

2. **3/10 story 为 enabling/maintainer-facing**（40.1 SDK gate、40.2 profile helper、40.9 fixture）：兼容/集成 epic 的固有特性，已显式标注。首个用户可见价值落地在 40.3+。
   - **建议**：保持现状（标注清晰）。可选：在 sprint planning 时把 40.1+40.2 合并为一个「SDK 接入」迭代，减少 enabling-only 迭代数。

3. **严格线性 10-story 链阻止并行**：delivery 效率问题，非 readiness 违规。每个 story 仅依赖先前，方向正确。
   - **建议**：评估 40.2（parity helper）能否与 40.1 并行（40.2 是对现有 `build()` 的纯重构，理论上不依赖 40.1 的新 SDK API）；若可，缩短关键路径。

4. **Story 40.10 仅手工验收真实 BMAD pipeline**：epic 自身已认知并明确「should not be the only proof of correctness」，由 40.9 fixture 配对提供确定性证明。✓ 已缓解。

5. **4 个 Open Questions 未决策**：OQ1（task tree 显示）、OQ2（旧命令 alias）、OQ3（agents/*.md discovery）、OQ4（ToolSearch alwaysLoad）。
   - 其中 **OQ2 实际已在 Story 40.10 AC 决策**（不硬编码映射，建议同步 skill 包/aliases）。
   - OQ1/OQ3/OQ4 均为 deferred/post-MVP，不阻塞。
   - **建议**：把 OQ2 状态更新为「已决策」；OQ1/OQ3/OQ4 在 epic 延后项中已记录，无需 MVP 决策。

### Step 5 总结

epic40 是一份**高质量、充分准备**的 epic：brownfield 事实与 SDK 前置依赖经代码级核实全部准确，SDK gate 可达，FR 覆盖 100%，AC 规范，依赖方向正确，无 critical/major 违规。仅有 5 项 minor concerns（多为文档卫生与 delivery 效率，非阻塞）。

---

## Step 6: Final Assessment（综合评估）

### Overall Readiness Status

# ✅ READY（就绪，可进入实施）

epic40 已满足实施就绪性全部硬性条件。无 Critical、无 Major 问题阻塞实施。发现项均为文档卫生或 delivery 效率类的 minor concerns。

### 就绪性证据摘要

| 维度 | 结果 |
|------|------|
| 文档完整性 | ✓ Epic + SPEC + architecture + implementation-plan + test-plan + brownfield-analysis 齐全 |
| 需求提取 | ✓ 18 FR + 10 NFR，清晰度高、可观测 success 信号 |
| FR 覆盖率 | ✓ 100%（18/18，每条 FR 有可追溯 Story） |
| UX 对齐 | ✓ N/A（CLI 功能，终端输出 UX 已在 Story 40.8 规约） |
| Epic 用户价值 | ✓ PASS（端到端运行 workflow skill，非技术里程碑） |
| Epic 独立性 | ✓ PASS（仅依赖已发布功能 + 外部 SDK gate） |
| 依赖方向 | ✓ PASS（线性链，无前向引用/循环） |
| AC 规范性 | ✓ PASS（10 story 全部 Given/When/Then + 错误条件覆盖） |
| Brownfield 事实核实 | ✓ 全部 ACCURATE（代码级核实 12 项） |
| SDK gate 可达性 | ✓ SDK 0.10.0 已发布远程，全部 API 存在 |

### Critical Issues Requiring Immediate Action

**无。** 无需在实施前解决的阻塞性问题。

### Recommended Next Steps（建议行动项）

**P0 — 实施起点（关键路径入口）：**

1. **启动 Story 40.1（SDK Runtime Readiness Gate）**：
   - 将 `Package.swift:18` 的 `from: "0.8.0"` 升到 `from: "0.10.0"`，`swift package update` 重新 resolve 到 commit `4285aac`（SDK 0.10.0 已确认在远程）。
   - 新增编译/单元测试验证可 import `createAgentTool()` / `createTaskTool()` / `createSkillTool(registry:)`。
   - 验证 `executeSkillStream` 的 skill package context 注入（断言式，非目测）。

**P1 — 文档卫生（随 40.1 一起做）：**

2. **修正 `project-context.md` SDK 依赖描述**：当前误述为「本地 path-based SPM 依赖」，实际是远程 URL `from:` 版本依赖。改为准确描述。

3. **更新 epic 的 OQ2 状态**：Open Question「旧 BMAD 命令名 alias migration」实际已在 Story 40.10 AC 决策（不硬编码映射）。把 OQ2 标记为「已决策」，避免实施时重复讨论。

**P2 — Delivery 效率优化（可选）：**

4. **评估 40.1 ∥ 40.2 并行可行性**：Story 40.2 是对现有 `AgentBuilder.build()` 的纯 parity 重构，理论上不依赖 40.1 的新 SDK API。若可并行，关键路径从 10 缩短为 9，减少 enabling-only 迭代。

5. **以 Story 40.9 fixture 作为 FR1 集成回归锚点**：FR1（顺序子任务执行）需 6 个 story 协同（40.3→40.4→40.7→40.8→40.9→40.10）。40.9 的 fixture（pipeline-test/step-one/step-two）应作为跨 story 回归测试，防止单 story 破坏协同链路。

**P3 — 实施时注意（非文档改动）：**

6. **40.6 实施 diagnostics 输出时与 40.8 tool result 输出协调**：避免双重格式化（对齐项目反模式 #17 — 格式化所有权归单一组件）。

### Final Note

本次评估横跨 6 个维度（文档发现、需求提取、覆盖验证、UX 对齐、Epic 质量、综合评估），共发现 **0 个 Critical、0 个 Major、5 个 Minor** 问题。

**epic40 处于就绪状态**，其最大优势是**风险前置且已验证**：epic 声称的全部 brownfield 代码事实与 SDK Epic 29 前置依赖经代码级核实均准确无误，SDK 0.10.0 已发布到远程且包含 Story 40.1 gate 所需的全部 API（`createTaskTool`/`createAgentTool`/`createSkillTool`/`DefaultSubAgentSpawner`）。

建议直接从 Story 40.1 启动实施，P1 文档卫生项随 40.1 一并完成。这些 finding 可用于改进现有 artifact，亦可选择按现状推进——不影响实施就绪判定。

---

**Assessor:** Claude Code（bmad-check-implementation-readiness skill）
**Date:** 2026-06-15
**Project:** axion
**Epic:** epic40 — Claude Code 技能/子代理兼容性





