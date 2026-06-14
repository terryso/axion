---
baseline_commit: 20c1f5784bd71862cde0b910384c39b1cd70647c
---

# Story 40.1: SDK Runtime Readiness Gate

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As an Axion maintainer,
I want a deterministic gate proving SDK Epic 29 runtime support is available in the resolved Axion dependency,
so that Axion integration work (Stories 40.2–40.10) does not start on missing or unstable SDK APIs.

**类型：** Enabling story / dependency gate. 这是 Epic 40 的线性链首节点，全部后续 story（40.2 → ... → 40.10）都直接或间接依赖本 story 完成。

## Acceptance Criteria

1. **AC1 — Package.swift 版本升级**
   **Given** Axion `Package.swift` 当前声明 `open-agent-sdk-swift` `from: "0.8.0"`
   **When** 升级到 `from: "0.10.0"` 并执行 `swift package update`
   **Then** `Package.resolved` 中 `open-agent-sdk-swift` 的 `version` 变为 `0.10.0`、`revision` 变为 `4285aac6535236dae014e945eed694ed7fe6bd4b`（commit `4285aac`）

2. **AC2 — SDK 工厂函数可 import 并实例化（编译级 gate）**
   **Given** Axion resolve 到 SDK 0.10.0+
   **When** 在 Axion 源码中 `import OpenAgentSDK` 后引用 `createAgentTool()`、`createTaskTool()`、`createSkillTool(registry:)`
   **Then** 三者均可解析、可调用，返回 `ToolProtocol`，Axion 整体编译通过（`swift build` 无错误）

3. **AC3 — Task / Agent 工具名与 schema 兼容**
   **Given** 调用 `createTaskTool()` 与 `createAgentTool()`
   **When** 读取两者的 `name` 属性
   **Then** `createTaskTool().name == "Task"` 且 `createAgentTool().name == "Agent"`
   **And** 两者 schema 等价（共享输入字段 `prompt`、`description`、`subagent_type` 等，仅 `name` 不同）

4. **AC4 — Task/Agent schema 包含 skills 与 mcpServers 字段**
   **Given** `createTaskTool()` / `createAgentTool()` 返回的输入 schema
   **When** 检查字段
   **Then** 包含 `skills` 与 `mcpServers`（或 `mcp_servers`）字段（SDK 0.10.0 wiring）

5. **AC5 — direct executeSkillStream 注入 skill package context**
   **Given** Axion 通过 SDK `executeSkillStream(skillName, args:)` 执行一个含 `baseDir` 与 `supportingFiles` 的 filesystem skill
   **When** SDK 生成 skill prompt
   **Then** prompt 包含 `Skill package context:` 块（含 `baseDir` 与 supporting files 列表）
   **And** 原有 `User request: <args>` 后缀保留

6. **AC6 — gate 失败时不得关闭 Epic**
   **Given** Axion 未 resolve 到 SDK 0.10.0+
   **When** 评估 Epic 40 进度
   **Then** 后续 Axion stories 必须标记为 blocked/deferred，不能关闭整个 Epic

## Tasks / Subtasks

- [x] **Task 1 — 升级 SDK 依赖声明（AC1）**
  - [x] 1.1 编辑 `Package.swift` 第 18 行：`from: "0.8.0"` → `from: "0.10.0"`
  - [x] 1.2 执行 `swift package update open-agent-sdk-swift`（或 `swift package update`）重新 resolve
  - [x] 1.3 验证 `Package.resolved` 中 `open-agent-sdk-swift` 的 `version: "0.10.0"` 且 `revision: "4285aac..."` 开头
  - [x] 1.4 执行 `swift build` 确认整体编译通过（SDK 0.10.0 是非破坏性升级，Axion 现有 `createSkillTool` 调用不受影响）

- [x] **Task 2 — 新增编译/单元级 gate 测试（AC2, AC3, AC4, AC5）**
  - [x] 2.1 在 `Tests/AxionCLITests/Services/` 新增测试文件 `SDKRuntimeReadinessGateTests.swift`，使用 **Swift Testing**（`import Testing`、`@Suite`、`@Test`、`#expect`）
  - [x] 2.2 `@Suite("SDK Runtime Readiness Gate (Story 40.1)")` 包含以下 `@Test`：
    - [x] 2.2.1 `test_createAgentTool_resolvesAndReturnsAgentName` — 调用 `createAgentTool()`，断言 `.name == "Agent"` 且为 `ToolProtocol`（覆盖 AC2/AC3）
    - [x] 2.2.2 `test_createTaskTool_resolvesAndReturnsTaskName` — 调用 `createTaskTool()`，断言 `.name == "Task"`（覆盖 AC2/AC3）
    - [x] 2.2.3 `test_createSkillTool_resolvesWithRegistry` — 用 `SkillRegistry()` 构造 registry，调用 `createSkillTool(registry:)`，断言返回 `ToolProtocol` 且 `.name == "Skill"`（覆盖 AC2）
    - [x] 2.2.4 `test_taskAndAgent_shareEquivalentSchema` — 验证两者完整输入 schema 等价（仅 name 不同），并断言两者均成功构造、`name` 不同（`"Task"` vs `"Agent"`）（覆盖 AC3）
    - [x] 2.2.5 `test_taskAndAgent_schemaIncludesSkillsAndMcpServers` — 验证输入 schema 包含 `skills` 与 `mcpServers`/`mcp_servers` 字段。优先用 schema 反射；若无反射 API，构造含这些字段的输入 JSON 并断言 `decode` 不抛错（覆盖 AC4）
  - [x] 2.3 skill package context 测试（AC5）：`test_filesystemSkill_promptIncludesPackageContext`。**不调用真实 LLM**。做法二选一（见 Dev Notes）：
    - 方案 A（推荐）：若 SDK 暴露纯函数可构造 skill prompt（如 `Agent` 内部 `resolveSkillForExecution` 或公开的 prompt builder helper），用 `Skill(baseDir:supportingFiles:promptTemplate:...)` 构造含 `baseDir` + `supportingFiles` 的 filesystem skill，断言生成的 prompt 含 `"Skill package context:"` 与 `baseDir` 值。
    - 方案 B（降级）：仅断言 filesystem skill 的 `Skill.baseDir != nil && !supportingFiles.isEmpty` 时 SDK 会进入 package-context 分支（用 `@testable import OpenAgentSDK` 访问内部逻辑，或直接断言 SDK 已在该 commit 提供此能力，作为集成点冒烟测试）。
    - 若两条路径都需要调用真实 `Agent` / `executeSkillStream`（涉及 API key / 网络），**放弃该断言式测试**，改为在 Completion Notes 中记录 SDK commit 与 prompt 样例，并把该 AC 标记为"SDK 行为验证，由 SDK 单测覆盖"。**禁止在单元测试中调用真实外部依赖。**
    - **执行结果**：采用降级路径。AC5 测试以 `.disabled(...)` 保留，并在 Completion Notes 记录 SDK commit / 代码路径作为集成点冒烟证据。
  - [x] 2.4 确认新测试不调用真实 `AgentBuilder.build()`、真实 MCP、真实 Helper、真实 API key、真实 `executeSkillStream`（符合 CLAUDE.md 单元测试 Mock 规则）

- [x] **Task 3 — 验证 Epic 40 后续 story 的 gate 守护（AC6）**
  - [x] 3.1 在 Completion Notes 中明确记录：SDK version `0.10.0`、commit `4285aac6535236dae014e945eed694ed7fe6bd4b`
  - [x] 3.2 在 Completion Notes 中说明：若 SDK 未 resolve 到 0.10.0+，Story 40.5/40.6（MCP/custom tool restriction parity、deferred diagnostics）与 Epic 40 整体不得标记 done

- [x] **Task 4 — 运行默认单元测试（不跑集成/E2E）**
  - [x] 4.1 执行 `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`（CLAUDE.md 指定命令）
  - [x] 4.2 新增 gate 测试必须包含在 `AxionCLITests` filter 命中范围
  - [x] 4.3 不运行 `Tests/**/Integration/`、`Tests/**/AxionE2ETests/`（无 AX 权限、无 API key）

## Dev Notes

### 本 Story 的本质：确定性依赖 gate，不是功能开发

这是 enabling story。**本 story 不实现任何新 Axion 运行时功能**：不注册 `Agent`/`Task` 工具（那是 Story 40.3）、不做 tool profile helper（Story 40.2）、不改 `buildSkillAgent`（Story 40.4）。本 story 只做三件事：(1) 升 SDK 版本，(2) 加编译/单测证明 SDK API 可达，(3) 记录 gate 元数据。**避免越界实现后续 story 的内容**，否则会破坏线性链的隔离性，让 40.2–40.10 的验收失去意义。

### 关键事实（已代码级核实，来自 readiness report 2026-06-15）

| 事实 | 当前值 | 目标值 | 证据 |
|------|--------|--------|------|
| Axion `Package.swift:18` 版本约束 | `from: "0.8.0"` | `from: "0.10.0"` | `Package.swift` |
| `Package.resolved` pin | `version: "0.8.3"`, revision `3a42f5c05b8bc61e33ca8e01da9215304680b893` | `version: "0.10.0"`, revision `4285aac...` | `Package.resolved` |
| SDK 远程 tag 0.10.0 | 已发布 | — | 远程 `refs/tags/0.10.0` → commit `4285aac`（在 `origin/main`） |
| SDK 本地 clone HEAD | `4285aac...`（0.10.0） | — | `/Users/nick/CascadeProjects/open-agent-sdk-swift`（注意：Axion 用**远程 URL** resolve，非本地 path） |

**重要修正**：`project-context.md` 第 29/38/890 行声称 OpenAgentSDK 是「本地 path-based SPM 依赖」，**不准确**。`Package.swift:18` 实际声明为远程 URL `https://github.com/terryso/open-agent-sdk-swift.git`，`from: "0.8.0"`，当前 resolve 到远程 commit `3a42f5c`（0.8.3）。本 story 把约束升到 `from: "0.10.0"` 后，`swift package update` 会从远程 resolve 到 `4285aac`（0.10.0），**不需要改成 path 依赖**。本地 clone `/Users/nick/CascadeProjects/open-agent-sdk-swift` 仅用于查阅 SDK 源码与运行 SDK 侧测试，不参与 Axion 的 SPM resolve。

### SDK API 可用性（已核实存在于 commit `4285aac`）

```
Sources/OpenAgentSDK/OpenAgentSDK.swift:62-63,133   # 文档导出声明
Sources/OpenAgentSDK/Tools/Advanced/AgentTool.swift:294  public func createAgentTool() -> ToolProtocol
Sources/OpenAgentSDK/Tools/Advanced/AgentTool.swift:312  public func createTaskTool() -> ToolProtocol
Sources/OpenAgentSDK/Tools/Advanced/SkillTool.swift:34   public func createSkillTool(registry: SkillRegistry) -> ToolProtocol
Sources/OpenAgentSDK/Core/Agent.swift:3293-3319         # resolveSkillForExecution + skill package context 注入
```

`createTaskTool()` 与 `createAgentTool()` 共享同一内部 launcher factory，仅 `name` 不同（`"Task"` vs `"Agent"`），schema 完全等价。SDK 侧已有 `SubAgentToolAliasTests`、`DefaultSubAgentSpawnerToolFilteringTests`、`SkillExecutionPromptContextTests` 覆盖这些行为（见 SDK test-plan）。**Axion 侧 gate 测试只需证明「可达且可实例化」，不重复 SDK 已有的 schema 等价性深度测试。**

### Axion 当前工具注册现状（理解基线，本 story 不改）

- `Sources/AxionCLI/Services/AgentBuilder.swift:144-145`：`build()` 在 `!noSkills && !dryrun` 时注册 `createSkillTool(registry: skillRegistry)`。**目前未注册 `createAgentTool()` / `createTaskTool()`**（那是 Story 40.3）。
- `Sources/AxionCLI/Services/AgentBuilder.swift:302-340`：`buildSkillAgent()` 是 lightweight skill agent，仅注册 core tools + 单个 skill 的 registry，无 MCP、无 `Skill`/`Agent`/`Task`（那是 Story 40.2/40.3/40.4）。
- `AgentBuilder.excludedToolNames = ["ToolSearch", "AskUser"]`（第 40 行）：硬编码排除，Story 40.5 才会改。

本 story **不修改上述任何行为**。若升级 SDK 后 `swift build` 因 SDK 0.10.0 的 API 变更导致现有代码编译失败，再按最小改动修复编译——但预期 0.8.3→0.10.0 是非破坏性升级（SDK 29 epic 只新增 API，不改既有 `createSkillTool` 签名）。

### 测试策略与 Mock 约束（CLAUDE.md 强制）

- 全部用 **Swift Testing**（`import Testing`、`@Suite`、`@Test`、`#expect`），**禁止 `import XCTest`**。
- **禁止真实外部依赖**：不调真实 `AgentBuilder.build()`、不连 MCP、不起 Helper 进程、不发真实 API key、不调真实 `executeSkillStream`。`createAgentTool()` / `createTaskTool()` / `createSkillTool(registry:)` 是纯工厂函数，**调用它们本身不触发网络/进程**，可作为单测对象。
- gate 测试只验证「SDK API 在 Axion resolve 的版本里可达且行为符合 AC」，**不验证 LLM 子代理实际派生行为**（那是 Story 40.3+ 与可选 E2E）。
- 参考既有 scaffold 风格测试：`Tests/AxionCLITests/Services/AgentBuilderCodingTests.swift`（`@testable import AxionCLI` + Swift Testing + temp dir 模式）。
- 测试命名遵循 `test_被测单元_场景_预期结果` 模式。

### AC5（skill package context）的验证边界

这是本 story 最需要审慎处理的 AC。SDK commit `4285aac` 的 `Agent.swift:3293-3319`（`resolveSkillForExecution` / package-context 分支）负责注入。验证优先级：
1. **首选**：若 SDK 提供可独立调用的纯函数/公开 helper 来构造 skill prompt（不实例化 `Agent`、不发 LLM 请求），直接对其断言。
2. **次选**：用 `@testable import OpenAgentSDK` 访问 `resolveSkillForExecution` 内部逻辑（需确认该类型 `internal` 可见性，且不触发 API key 校验）。
3. **降级**：若上述都需要真实 `Agent` 构造（`createAgent(options:)` 内部可能校验 API key），**不要在单测里绕过校验去碰真实 SDK 运行时**。改为：在 Completion Notes 记录 SDK commit、贴出 SDK prompt 生成代码路径与样例 prompt，并把该 AC 标记为「SDK 行为，由 SDK 单测覆盖」。这是合规的降级——单元测试规则禁止真实运行时副作用。

### 为什么不改成 path 依赖

即便本地有 `/Users/nick/CascadeProjects/open-agent-sdk-swift`，readiness report 已核实远程 tag 0.10.0 可 resolve。改 path 依赖会引入本地环境耦合，破坏 CI 与其他贡献者的构建。保持远程 URL + `from: "0.10.0"` 是正确做法。

### 测试套件归属

新文件 `SDKRuntimeReadinessGateTests.swift` 放在 `Tests/AxionCLITests/Services/`（镜像 `Sources/AxionCLI/Services/AgentBuilder.swift` 的工具注册逻辑所在层）。它在 `AxionCLITests` testTarget 内，被默认单元测试命令的 `--filter "AxionCLITests"` 命中。

### Project Structure Notes

- `Package.swift`（根目录）：唯一改动点 = 第 18 行版本约束。
- `Package.resolved`（根目录）：由 `swift package update` 自动生成，**不要手动编辑**（SPM 会校验 originHash）。
- `Tests/AxionCLITests/Services/SDKRuntimeReadinessGateTests.swift`：新增测试文件。
- 本 story 不碰 `Sources/AxionCLI/`（除非升级 SDK 后编译失败需最小修复）。
- 与 `_bmad-output/project-context.md` 第 29/38/890 行「path-based 依赖」描述不符，但那是文档卫生问题，**不在本 story 范围**（readiness report 已列为 minor concern）。若 dev 想顺手修正文档，可单独提交，不计入本 story AC。

### References

- Epic：`docs/epics/epic-40-claude-code-skill-subagent-compat.md`（Story 40.1 章节，第 153–183 行）
- SPEC 内核：`_bmad-output/specs/spec-task-subagent-skill-compat/SPEC.md`（Constraints、Assumptions）
- 架构：`_bmad-output/specs/spec-task-subagent-skill-compat/architecture.md`（Components §1/§5、Compatibility Matrix）
- 实现计划：`_bmad-output/specs/spec-task-subagent-skill-compat/implementation-plan.md`（Phase 1/2 Status: completed upstream；Rollout Strategy §1）
- 测试计划：`_bmad-output/specs/spec-task-subagent-skill-compat/test-plan.md`（SDK Unit Tests、Default Verification Command）
- Readiness 评审：`_bmad-output/planning-artifacts/implementation-readiness-report-2026-06-15.md`（第 277–291 行 brownfield 事实核实；第 419 行升级指引）
- 项目测试规则：`CLAUDE.md`（Swift Testing、单元测试 Mock、只跑单元测试）
- 代码事实：`Package.swift:18`、`Package.resolved`、`Sources/AxionCLI/Services/AgentBuilder.swift:40,144,302-340`
- SDK 源码：`/Users/nick/CascadeProjects/open-agent-sdk-swift` @ `4285aac`（`Tools/Advanced/AgentTool.swift:294,312`、`Tools/Advanced/SkillTool.swift:34`、`Core/Agent.swift:3293-3319`）

## Dev Agent Record

### Agent Model Used

Claude Code (bmad-dev-story skill)

### Debug Log References

- `swift package update open-agent-sdk-swift` → `Working copy of https://github.com/terryso/open-agent-sdk-swift.git resolved at 0.10.0`
- `swift build` → `Build complete! (27.88s)`，0.8.3→0.10.0 非破坏性升级，**无任何 Axion 源码编译修复**
- 单元测试（CLAUDE.md 指定命令）→ `Test run with 3813 tests in 246 suites passed`；checkpoint 复跑 gate 套件 → `Test run with 6 tests in 1 suite passed after 0.007 seconds`

### Completion Notes List

**SDK 版本与 commit（AC1/AC6 gate 元数据）**
- 升级后 `Package.resolved` 中 `open-agent-sdk-swift`：
  - `version: "0.10.0"`
  - `revision: "4285aac6535236dae014e945eed694ed7fe6bd4b"`（完整匹配 AC1 要求的 commit，以 `4285aac` 开头）
- 约束 `Package.swift:18` 由 `from: "0.8.0"` 升至 `from: "0.10.0"`，保持**远程 URL 依赖**（`https://github.com/terryso/open-agent-sdk-swift.git`），**未改成本地 path 依赖**，避免 CI/其他贡献者环境耦合。

**AC2/AC3/AC4 gate 测试结果（已转绿）**
- `test_createAgentTool_resolvesAndReturnsAgentName` → passed（`createAgentTool().name == "Agent"`）
- `test_createTaskTool_resolvesAndReturnsTaskName` → passed（`createTaskTool().name == "Task"`）
- `test_createSkillTool_resolvesWithRegistry` → passed（`createSkillTool(registry:).name == "Skill"`，同时回归验证 0.10.0 未破坏既有 `createSkillTool` 签名）
- `test_taskAndAgent_shareEquivalentSchema` → passed（Agent/Task 完整 `inputSchema` 规范化 JSON 等价，仅工具 name 不同）
- `test_taskAndAgent_schemaIncludesSkillsAndMcpServers` → passed（两者 schema 均含 `skills` 与 `mcpServers` 字段）
- 注：本次运行同时观察到 SDK 自带的 `createSkillTool does not crash with empty/non-empty registry` 两个测试也 passed，进一步佐证 createSkillTool 在 0.10.0 行为稳定。

**AC5 降级处理（skill package context）**
- 降级原因：SDK commit `4285aac` 的 skill package-context 注入逻辑位于 `Core/Agent.swift:3293-3319`（`resolveSkillForExecution` / package-context 分支），需要真实 `Agent` 运行时实例才能完整触发；实例化 `Agent` 会触发 API key 校验与潜在网络副作用。方案 A（纯函数 prompt builder）与方案 B（`@testable` 访问内部分支）在当前 SDK 公开 API 下均无法在不带副作用的前提下隔离复现，按 story Dev Notes 与 CLAUDE.md「单元测试禁止真实运行时副作用」规则，**不在单测里绕过校验去碰真实 SDK 运行时**。
- 处置：AC5 测试 `test_filesystemSkill_promptIncludesPackageContext` 以 `.disabled(...)` 保留，运行时 skipped。该行为由 SDK 侧 `SkillExecutionPromptContextTests`（SDK test-plan）单测覆盖；此处仅作集成点冒烟证据登记。
- SDK prompt 生成代码路径：`Sources/OpenAgentSDK/Core/Agent.swift:3293-3319` @ commit `4285aac`，注入 `"Skill package context:"` 块（含 `baseDir` 与 supporting files 列表），并在其后保留 `User request: <args>` 后缀。
- 若后续 SDK 暴露无副作用的纯函数 prompt builder（不实例化 Agent、不发请求），dev 可将该测试激活为断言式单测（断言生成的 prompt 含 `"Skill package context:"` 与 baseDir 值、`User request:` 后缀）。

**Gate 守护策略（AC6）**
- 本 story 是 Epic 40 线性链首节点。**若 Axion 未 resolve 到 SDK 0.10.0+（`Package.resolved` 不是 `4285aac`），则：**
  - Story 40.5（MCP/WebSearch tool inheritance parity）、40.6（permission allowlist + deferred diagnostics）以及依赖它们的后续 story 必须标记为 **blocked/deferred**。
  - **Epic 40 整体不得标记 done。**
- 守护机制：`SDKRuntimeReadinessGateTests`（AC2/AC3/AC4）为编译/单测级 gate——若 SDK 缺 `createAgentTool/createTaskTool/createSkillTool` 或 schema 不含 `skills`/`mcpServers`，gate 套件即编译失败或运行失败，从而阻断 Epic 40 的后续 story 进入 done。

**范围控制（未越界）**
- 本 story 仅做三件事：升 SDK 版本、加 gate 测试、记元数据。
- **未**注册 `Agent`/`Task` 工具（Story 40.3）、**未**做 tool profile helper（40.2）、**未**改 `buildSkillAgent`（40.4）、**未**改 `excludedToolNames`（40.5）。
- `Sources/AxionCLI/` **零改动**（SDK 升级后 `swift build` 直接通过，无需最小编译修复）。

### File List

- `Package.swift`（修改：第 18 行 `from: "0.8.0"` → `from: "0.10.0"`）
- `Package.resolved`（SPM 自动生成：`open-agent-sdk-swift` 升至 version `0.10.0` / revision `4285aac6535236dae014e945eed694ed7fe6bd4b`）
- `Tests/AxionCLITests/Services/SDKRuntimeReadinessGateTests.swift`（gate 测试：验证 SDK 工厂函数可达、Agent/Task schema 等价、skills/mcpServers 字段存在；checkpoint 阶段收紧 AC3 为完整 schema 比对）
- `_bmad-output/implementation-artifacts/40-1-sdk-runtime-readiness-gate.md`（本 story 文件：补 frontmatter `baseline_commit`、Tasks 打勾、Dev Agent Record、File List、Change Log、Status → review）

## Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-06-15 | 0.1 | Story 40.1 实现：升 OpenAgentSDK 0.8.0→0.10.0（commit 4285aac），gate 测试转绿（AC2/AC3/AC4），AC5 降级（SDK 行为由 SDK 单测覆盖），记录 gate 守护策略（AC6）。`swift build` 通过、3813 单测全绿。 | bmad-dev-story (Claude Code) |
| 2026-06-15 | 0.2 | Checkpoint review 收紧 AC3 gate：`test_taskAndAgent_shareEquivalentSchema` 从 properties 键集合比对升级为完整 `inputSchema` 规范化 JSON 比对，并清理测试文件中过时的 RED phase 注释。 | bmad-checkpoint-preview |
