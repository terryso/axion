---
epic: "40"
title: "Epic 40 手工验收手册（真实命令）"
created: 2026-06-16
status: living
related_stories: [40.3, 40.4, 40.5, 40.6, 40.7, 40.8, 40.9, 40.10]
---

# Epic 40 手工验收手册（真实命令跑）

> **目的**：用**真实命令**端到端验收 Epic 40「Run Claude Code/BMAD Workflow Skills End-to-End」的全部能力（40.3–40.10）。本手册按可重复执行的命令组织，每条命令配「预期 / 实际记录」栏，供每次回归或发版前手工复跑。
>
> 与 `_bmad-output/implementation-artifacts/40-10-*.md` 的关系：40.10 是 **story 级** capstone 记录（一次性、已填）；本文件是 **epic 级** 可重复手册（living），并把 40.10 首次真实运行的证据整合为「§首次验收记录」。

---

## 0. 验收基线（每次执行前核对填写）

| 项 | 取值方法 | 本次值 |
|----|---------|--------|
| Axion commit | `git -C /Users/nick/CascadeProjects/axion rev-parse HEAD` | `d0997be`（文档创建时；验收时以实际为准） |
| Axion 分支 | `git branch --show-current` | `spec/task-subagent-skill-compat` |
| Axion runtime 版本 | `swift run AxionCLI --version`（或启动 banner） | `Axion v0.13.5`（40.10 验收时） |
| SDK product | `grep open-agent-sdk Package.swift` | `open-agent-sdk-swift` (terryso/open-agent-sdk-swift) |
| SDK commit | `git -C .build/checkouts/open-agent-sdk-swift rev-parse HEAD` | `4285aac`（describe `0.7.9-15-g4285aac`，即 0.10.0 开发版，未正式 tag） |
| Pipeline skill 包 | `ls ~/.agents/skills/bmad-story-pipeline/{SKILL.md,references/workflow-steps.md}` | 已安装（源 `~/CascadeProjects/claude-bmad-skills/`） |
| 单步 skill 包 | `ls .claude/skills/{bmad-create-story,bmad-testarch-atdd,bmad-dev-story,bmad-code-review,bmad-testarch-trace}/SKILL.md` | 均存在 |
| 模型 | 启动 banner | `glm-5.2[1m]`（API 限流/超时较常见，见 §caveat） |
| 执行人 / 日期 | — | __ |

> ⚠️ **必须用 `swift run AxionCLI`**，不要用 homebrew 旧版 `axion`（项目反模式：homebrew 版滞后，测不到当前改动）。

---

## 1. 前置条件

- [ ] API key 已配置（`axion setup` 或 keychain；无 key 时 LLM-dependent 步骤会跳过/失败）
- [ ] Axion 能 resolve 到 `open-agent-sdk-swift` ≥ 0.10.0 开发版（`4285aac`）
- [ ] `~/.agents/skills/bmad-story-pipeline/{SKILL.md, references/workflow-steps.md}` 存在且命令名一致（见 M0）
- [ ] `.claude/skills/` 下 5 个单步 BMAD skill 存在
- [ ] `make test` 基线绿（见 M7），作为「改 code 前后零回归」参照

---

## 2. 安全约定（避免污染真实 sprint）

真实 `/bmad-story-pipeline <id>` 会**派生子代理、创建/改 story 文件、提交**。为避免污染活跃 sprint：

- **不要**对真实生产 sprint 活跃 story 跑全 5 步 pipeline。
- 验收用**安全 story-id**：`99-1`（epic 99 不存在 → 前置校验干净停止，零副作用）、或 backlog 但不触发的 id（如 `1-1`/`33-1`）。
- 验收「缺失/旧命令失败路径」用 **broken 副本**：`cp -r ~/.agents/skills/bmad-story-pipeline ~/.axion/skills/bmad-story-pipeline-broken`，把 step-1 命令改成旧名 `/bmad-bmm-create-story`，验收后**删除副本**。
- 每次验收后 `git status` 核对无意外产物。

---

## 3. 验收命令矩阵

每条命令配 **预期** + **实际记录**（空栏，执行时填）。✅ = 首次验收（§4）已确认。

### M0 — 环境就绪 & 命令名一致性（40.10 前置）

```bash
# 0.1 runtime 可启动
swift run AxionCLI --help | head -5
```
- 预期：打印 Axion CLI 帮助，无崩溃。
- 实际：__

```bash
# 0.2 pipeline 命令名一致性（SKILL.md vs references/workflow-steps.md）
diff <(grep -oE '/bmad-[a-z-]+' ~/.agents/skills/bmad-story-pipeline/SKILL.md | sort -u) \
     <(grep -oE '/bmad-[a-z-]+' ~/.agents/skills/bmad-story-pipeline/references/workflow-steps.md | sort -u)
```
- 预期：两文件引用的 `/bmad-*` 命令集合**完全一致**（diff 无输出）。
- 实际（首次 ✅）：一致，顺序 `/bmad-create-story`、`/bmad-testarch-atdd`、`/bmad-dev-story`、`/bmad-code-review`、`/bmad-testarch-trace`。

### M1 — 工具注册：Agent / Task / Skill（40.3）

```bash
# 1.1 单元层确定性证明（非 dry-run 含 Agent/Task/Skill；dry-run 排除）
make test --filter AxionCLITests 2>&1 | grep -iE "subagent tool registration|buildToolProfile"
```
- 预期：`AgentBuilder subagent tool registration (Story 40.3)` 套件 5/5 passed；`buildToolProfile (Story 40.2)` 7/7 passed。
- 实际（首次 ✅）：5/5 + 7/7 绿。

```bash
# 1.2 真实运行层：交互式 chat 启动，确认父 agent 工具池含 Agent/Task/Skill
swift run AxionCLI
# 进入交互后输入（verbose）：
> /skills        # 应列出 bmad-story-pipeline + 5 个单步 skill
```
- 预期：`/skills` 同时列出全局 `bmad-story-pipeline [fs]` 与项目级 5 个单步 skill。
- 实际（首次 ✅）：`/skills` 列出 pipeline + 5 单步 skill（`/tmp/axion-skills-4010.log` line 21/26/28/55/60/67）。

### M2 — Discovered Skill Registry（40.4）

```bash
make test --filter AxionCLITests 2>&1 | grep -i "DiscoveredSkillRegistry"
```
- 预期：`AgentBuilderDiscoveredSkillRegistryTests` 套件 passed（direct skill agent 用 discovered registry，子代理能 resolve 任意已注册 skill）。
- 实际（首次 ✅）：绿。

```bash
# 真实层：pipeline 父 agent 读 workflow-steps.md 时从 skill 包 baseDir 解析（非 cwd）
swift run AxionCLI
> /bmad-story-pipeline 99-1
```
- 预期：父 agent `[tool] 📄 read: /Users/…/bmad-story-pipeline/references/workflow-steps.md`（路径来自包 baseDir，**非当前 cwd**），随后读 sprint-status、前置校验发现 99-1 不存在 → 干净停止。
- 实际（首次 ✅）：read 路径来自包 baseDir；99-1 前置停止，零污染。

### M3 — MCP/Web/Search 策略 + dry-run（40.5）

```bash
make test --filter AxionCLITests 2>&1 | grep -i "ToolSearchAndMcpInheritance"
```
- 预期：`AgentBuilderToolSearchAndMcpInheritanceTests` passed（ToolSearch 排除改为 config 驱动 `enableToolSearch`；direct skill 路径继承 config MCP servers；dry-run 排除 Skill/Agent/Task）。
- 实际（首次 ✅）：绿。

```bash
# 真实层（可选）：确认 Axion 不静默移除 MCP/Web/Search
swift run AxionCLI run --help | grep -iE "mcp|web|search|tool-search"
# 或在 verbose log 里确认 direct skill agent 的工具池报告
```
- 预期：MCP/Web/Search 可用性由 Axion profile + permission policy 决定，direct skill path 不静默移除。
- 实际：__

### M4 — Permission / Diagnostics 一致性（40.6）

```bash
make test --filter AxionCLITests 2>&1 | grep -i "PermissionAndDiagnosticsConsistency"
```
- 预期：`AgentBuilderPermissionAndDiagnosticsConsistencyTests` passed（`ToolAvailabilityDiagnostics` + `diagnoseToolAvailability` + `effectiveSkillToolPool`；缺失工具被诊断标记）。
- 实际（首次 ✅）：绿。

### M5 — Slash Skill Guidance for Child Agents（40.7）

```bash
make test --filter AxionCLITests 2>&1 | grep -i "SlashSkillGuidance"
```
- 预期：`AgentBuilderSlashSkillGuidanceTests` passed（子代理系统提示含 `/skill-name` 用法引导）。
- 实际（首次 ✅）：绿。

### M6 — Child Task 进度/失败/摘要输出渲染（40.8）

```bash
make test --filter AxionCLITests 2>&1 | grep -iE "ChildTask|ToolCategoryFormatter|ChatOutputFormatter"
```
- 预期：`ChatOutputFormatterChildTaskTests` + `ToolCategoryFormatterTests` + `ToolOutputFormatterTests` 全 passed（Task 工具 start/result 按序渲染；失败含名称 + 可重试命令）。
- 实际（首次 ✅）：绿。

### M7 — Fixture 确定性基线（40.9）+ make test 零回归

```bash
make test 2>&1 | tail -20
```
- 预期：`FixturePipelineAcceptanceTests`（`Tests/AxionCLITests/Fixtures/`）7/7 passed；总测试数 ~4000+；Epic 40 全部套件零回归。
- 实际（首次 ✅）：4067 tests / 272 suites。唯一失败 = `DesktopNotifier`（7 个 OSC-9 tmux 环境性，见 §caveat，可忽略）；Epic 40 套件全绿。
- 已知：__
- 实际（本次）：__

### M8 — 真实 Pipeline 端到端 capstone（40.10）

> 这是 Epic 40 的真实性证据核心。用安全 story-id + broken 副本，避免污染真实 sprint。

```bash
# 8.a 顺序派生 Task 子代理执行单步 skill（AC1）
swift run AxionCLI
> /bmad-story-pipeline 99-1     # 安全 id（epic 99 不存在 → 前置停止，但能捕获派生证据）
```
- 预期：父 agent 读 pipeline → 建 5 步 Todo → **按序**派生 `Task`/`Agent` 子代理执行各单步 skill。
- 实际（首次 ✅，用 broken 副本 + backlog `33-1` 触发以捕获派生）：父 agent 按序建 5 步 Todo → `[tool] 🚀 task: Creates story file 33-1 … — /bmad-create-story 类单步 skill` 派生子代理。

```bash
# 8.b 缺失/旧命令失败路径（AC2）—— 用 broken 副本
cp -r ~/.agents/skills/bmad-story-pipeline ~/.axion/skills/bmad-story-pipeline-broken
# 编辑 ~/.axion/skills/bmad-story-pipeline-broken/references/workflow-steps.md
#   把 step-1 命令改成旧名 /bmad-bmm-create-story
swift run AxionCLI
> /bmad-story-pipeline-broken 33-1 yolo
# 验收后清理：
rm -rf ~/.axion/skills/bmad-story-pipeline-broken
```
- 预期：Axion **不硬编码** `/bmad-bmm-*`→`/bmad-*` 映射；子代理执行旧命令失败，输出**保留**原始缺失 skill 名 + **可重试命令**（`retry: /bmad-bmm-create-story 33-1 yolo`）。
- 实际（首次 ✅）：子代理 `[warn] ✗ failed … retry: /bmad-bmm-create-story 33-1 yolo`（`/tmp/axion-ac2-33-1-4010.log` line 50），保留原名 + 可重试命令（沿用 40.8 `extractSlashSkillCommand` + `retry:` 格式）。

```bash
# 8.c 不硬编码核对（静态）
grep -rnE "bmad-bmm|bmad-tea" Sources/
```
- 预期：**空**（exit 1）——Axion 源码无任何旧命令硬编码映射。
- 实际（首次 ✅）：空。

```bash
# 8.d 副作用核对（零污染）
git status --short
```
- 预期：无 `99-1`/`33-1`/`bmad-story-pipeline-broken` 任何产物。
- 实际（首次 ✅）：无。

---

## 4. 首次验收记录（2026-06-16，整合 40.10 dev 真实运行证据）

> 首次真实命令验收由 Story 40.10 dev 会话执行（commit `3a17830`），证据已落入 `_bmad-output/implementation-artifacts/40-10-*.md`「Dev Agent Record / 手工验收记录（AC1–AC3）」。摘要：

| 能力 | 证据 | 结论 |
|------|------|------|
| M0 命令名一致 | SKILL.md ↔ workflow-steps.md `/bmad-*` 集合 diff 空 | ✅ |
| M1 工具注册 | `make test` 40.3 套件 5/5、40.2 套件 7/7；`/skills` 列出 6 skill | ✅ |
| M2 discovered registry | 40.4 套件绿；pipeline read 路径来自包 baseDir（非 cwd） | ✅ |
| M3 MCP/策略 + dry-run | 40.5 套件绿 | ✅ |
| M4 permission/diagnostics | 40.6 套件绿 | ✅ |
| M5 slash guidance | 40.7 套件绿 | ✅ |
| M6 child output | 40.8 套件绿 | ✅ |
| M7 fixture + make test | 40.9 套件 7/7；4067 tests，唯一失败 DesktopNotifier 环境性 | ✅ |
| M8a 顺序派生 Task 子代理 | 父 agent 按序建 5 步 Todo → `[tool] 🚀 task: …` 派生子代理 | ✅ |
| M8b 缺失 skill 失败 | 旧命令原样执行失败，保留 `/bmad-bmm-create-story` 名 + `retry:` 可重试命令 | ✅ |
| M8c 不硬编码 | `grep -rnE "bmad-bmm\|bmad-tea" Sources/` = 空 | ✅ |
| M8d 零污染 | `git status` 无 99-1/33-1/broken 产物 | ✅ |

**诚实性边界**：AC1「step-1 成功 → 进入 step-2」的**正向端到端**未在真实 LLM 运行中完整捕获（为遵守「不对真实活跃 sprint 跑全 5 步」红线，刻意用安全 id / broken 副本，导致 step-1 要么前置停止、要么走缺失-skill 失败路径）。该正向完成路径的**确定性证明**由 40.9 fixture（7/7 绿）提供——这是 Epic 设计的「确定性证据 + 真实性证据并存」。真实运行已覆盖：pipeline 加载、包上下文解析、顺序派生 Task 子代理、缺失-skill 失败 + 保留名 + 可重试命令、零硬编码。

---

## 5. 已知环境性 caveat

- **`DesktopNotifier` OSC-9 失败**：`make test` 中 7 个 `DesktopNotifier` 用例在 tmux 环境（`TMUX`/`TERM_PROGRAM=tmux`，`Ptmux;` DCS 透传）下失败。**与 Epic 40 无关、可忽略**；在非 tmux 终端复跑即绿。
- **GLM API 限流/超时**：`glm-5.2[1m]` 在长会话（尤其 pipeline 多步派生）偶发 429 / `operation timed out` / 流停滞。M8 真实运行时如遇，重试或换时段；子代理单步 300s timeout 中断属安全策略，关键证据应在中断前捕获。
- **`swift run AxionCLI` vs homebrew `axion`**：一律用前者；homebrew 版滞后测不到当前改动（项目反模式）。

---

## 6. 失败排查速查

| 现象 | 排查 |
|------|------|
| `/bmad-story-pipeline` 不在 `/skills` | 确认 `~/.agents/skills/bmad-story-pipeline/SKILL.md` 存在；skill 发现路径（全局 `.agents` + 项目 `.claude`） |
| 子代理报 skill not found | M0 命令名一致性；确认单步 skill 在 `.claude/skills/`；broken 副本 step 名是否拼错 |
| 子代理派生后无输出 | M6（40.8 渲染）；verbose 模式看 `🚀 task` / `📄 read` 行 |
| make test Epic 40 套件失败 | 先排除 DesktopNotifier 环境性；再 `make test --filter <套件名>` 定位 |
| 旧命令被静默改写 | 违反 AC2；`grep -rnE "bmad-bmm\|bmad-tea" Sources/` 应空，否则是回归 |

---

## 7. 结论栏（本次验收）

- **总体结论**：☐ 全部通过　☐ 部分通过（见下）　☐ 阻塞
- **未通过项**：__
- **回归风险**：__
- **建议**：__
- **执行人 / 日期**：__

---

## 参考

- Epic：`docs/epics/epic-40-claude-code-skill-subagent-compat.md`（§手工验收、§默认测试策略 `make test`）
- Story capstone 记录：`_bmad-output/implementation-artifacts/40-10-local-bmad-pipeline-manual-verification.md`（Dev Agent Record / 手工验收记录 AC1–AC3）
- Retrospective：`_bmad-output/implementation-artifacts/epic-40-retro-2026-06-16.md`（10/10 done，0 CRITICAL/0 HIGH）
- 项目测试规则：`CLAUDE.md`（Swift Testing、单元测试 Mock、只跑单元测试、`make test`、`swift run AxionCLI` 反模式）
