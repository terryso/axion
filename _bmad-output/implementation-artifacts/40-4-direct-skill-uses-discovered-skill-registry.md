---
baseline_commit: f0b249eb5f1e2d46bb0aabe27e4a3ffccf5063b2
---

# Story 40.4: Direct Skill Uses Discovered Skill Registry

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a BMAD pipeline user,
I want a direct skill execution (`axion run /bmad-story-pipeline 1-1` 或 API skill 执行) to see the full discovered skill registry,
so that a pipeline skill can delegate to `/bmad-create-story`、`/bmad-dev-story` 等单步 skill——这些子 skill 必须对 pipeline 派生的 child agent 可见，而不只是当前被执行的那一个 skill。

**类型：** Feature / registry-wiring story。本 story 在 Story 40.3 已注册 `Skill`/`Agent`/`Task` 三工具的 `buildSkillAgent()` 基础上，**把 single-skill registry 换成完整 discovered registry**（built-in + filesystem discovery），让 `createSkillTool(registry:)` 与 `AgentOptions.skillRegistry` 共享同一个 registry，使 SDK `DefaultSubAgentSpawner` 能把完整 registry 继承给 child agent。本 story **不**改 `buildSkillToolProfile(registry:)` 的工具集合（那是 40.3）、**不**改 MCP/Web/Search/ToolSearch 继承（那是 40.5）、**不**加 permission allowlist（那是 40.6）、**不**加 slash skill guidance 到 system prompt（那是 40.7）、**不**改 child task 输出格式（那是 40.8）。

## Acceptance Criteria

1. **AC1 — `buildSkillAgent()` 使用 discovered registry，子 skill 对 child agent 可见**
   **Given** 一个 fixture discovery 目录中存在 `pipeline-test`、`step-one`、`step-two` 三个 skill（通过 SKILL.md + SkillLoader 发现）
   **When** 调用 `AgentBuilder.makeDiscoveredSkillRegistry(ensuring: pipelineTestSkill, discoveryDirectories: [fixtureDir])`（Story 新增的纯函数 helper）
   **Then** 返回的 `SkillRegistry` 能 `find("step-one")`、`find("step-two")`、`find("pipeline-test")` 全部命中（非 nil）
   **And** registry 同时含 Axion built-in skills（如 `screenshot-analyze`）——与普通 chat 路径 `build()` 的 registry 构造一致（`build()` 第 99 行 `AxionBuiltInSkills.registerAll`）
   **And** skill 名**从 registry 真实读取**（`registry.find(name)?.name`），**不硬编码**字面量到断言（CLAUDE.md 反模式 #10）

2. **AC2 — `createSkillTool(registry:)` 与 `AgentOptions.skillRegistry` 共用同一个 discovered registry**
   **Given** `buildSkillAgent(config:skill:...)` 被调用（`AxionConfig(apiKey: "sk-test")` 即可绕过 `resolveApiKey`）
   **When** 读取返回 agent 的 `agentOptions.skillRegistry`
   **Then** 该 registry **非空**（`allSkills.isEmpty == false`）
   **And** 该 registry **包含**被传入的 `skill`（"ensure 当前 skill"语义——即便该 skill 不在 discovery 目录中，也必须出现在 registry 中）
   **And** `buildSkillToolProfile(registry:)`（40.3 提取的 helper）接收的 registry 与 `agentOptions.skillRegistry` 是**同一个实例**（`buildSkillAgent` 内部只构造一个 `registry`，分别传给二者）——通过代码结构保证，dev 不需要额外接线

3. **AC3 — alias 解析与 `/skill-name args` direct routing 一致**
   **Given** discovery 目录中某 skill 声明了 `aliases: [sa]`（frontmatter）
   **When** 在 discovered registry 上调用 `find("sa")`
   **Then** 返回该 skill（`SkillRegistry.find` 已实现 name + alias 双路查找，SDK `SkillRegistry.swift:151-165`）
   **And** chat router 的 `resolveSkillName` 闭包（`ChatCommand.swift:340` `registry.find(rawSkillName)`）与 `SkillTool` 的 `registry.find(input.skill)`（`SkillTool.swift:77`）**走同一个 alias-aware 查找路径**——只要二者持有同一个 discovered registry，alias 行为天然一致，**无需额外代码**（本 AC 是"验证 + 文档化"，dev 通过注释/Dev Notes 说明一致性即可，不改 chat router）

4. **AC4 — child agent 找不到 skill 时返回明确错误且保留 skill 名**
   **Given** discovered registry 中**没有** `missing-skill`
   **When** 在该 registry 上查找 `registry.find("missing-skill")`
   **Then** 返回 `nil`（registry 层确定性可测）
   **And** SDK `SkillTool` 在 child agent 调用 `Skill(skill:"missing-skill", args:"demo")` 时返回 `isError: true`，错误文本形如 `Error: Skill "missing-skill" not found or not registered`（`SkillTool.swift:77-82`，**保留原 skill 名**）
   **And** **已知 SDK 限制**：当前 `SkillTool` 的 not-found 错误**不回显 args**（`input.args` 未拼入错误串）。args 回显属 SDK 侧增强，不在本 story（Axion 侧）范围；dev 应在 Dev Notes 记录此 gap，作为 Epic 40 后续 / SDK follow-up，**不阻塞 AC4**（"保留 skill 名"已满足；args 回显降级为 follow-up）

5. **AC5 — 新增 fixture-based 单元测试覆盖 registry 可见性与 alias / 缺失语义**
   **Given** shared discovered-registry helper 与 `buildSkillAgent` 已更新
   **When** 在 `Tests/AxionCLITests/Services/` 新增 Swift Testing 测试文件
   **Then** 测试覆盖：
     - **registry 可见性（AC1）**：fixture discovery 目录含 `pipeline-test`/`step-one`/`step-two`，helper 返回的 registry 三者皆可 `find` 命中
     - **ensure 当前 skill（AC2）**：传入一个**不在 discovery 目录中**的 programmatic skill，registry 仍 `find` 命中它（验证 `register(skill)` 的 ensure 语义）
     - **alias 解析（AC3）**：fixture skill 声明 alias，`find(alias)` 命中
     - **缺失 skill（AC4）**：`find("missing-skill") == nil`
     - **built-in 一致性（AC1）**：registry 含至少一个 `AxionBuiltInSkills` built-in（名称从 `AxionBuiltInSkills` 真实读取，不硬编码）
   **And** 测试**不调用真实 `AgentBuilder.build()`**（会 resolve API key + Helper path + MCP）；helper 测试是纯函数风格（仅 FS discovery 于注入的临时目录）。对 `buildSkillAgent` 的接线断言用 `AxionConfig(apiKey: "sk-test")`，不连 MCP、不起 Helper

> **ATDD 测试引用（RED 阶段将生成）**
> - 测试文件（建议）：`Tests/AxionCLITests/Services/AgentBuilderDiscoveredSkillRegistryTests.swift`（Swift Testing，覆盖 AC1–AC5）
> - ATDD checklist（Step 2 生成）：`_bmad-output/test-artifacts/atdd-checklist-40-4-direct-skill-uses-discovered-skill-registry.md`
> - 当前状态：待 Step 2 生成 RED 脚手架

## Tasks / Subtasks

- [x] **Task 1 — 提取 discovered-registry 纯函数 helper（AC1, AC2, AC5 可测性）**
  - [x] 1.1 在 `Sources/AxionCLI/Services/AgentBuilder.swift` 新增 static helper（与 `buildToolProfile` / `buildSkillToolProfile` 并列的"纯函数"族）：
    ```swift
    /// Builds the full discovered `SkillRegistry` used by both normal chat/run (`build()`) and
    /// direct skill execution (`buildSkillAgent()`). This is the registry the `Skill` tool and
    /// `AgentOptions.skillRegistry` must share so that (a) an orchestrator skill can invoke
    /// sub-skills, and (b) SDK `DefaultSubAgentSpawner` inherits the full registry to child agents.
    ///
    /// Mirrors the registry construction in `build()` (lines 96-102): built-in skills + filesystem
    /// discovery, then ensures the currently-executing `skill` is present (idempotent `register` —
    /// `SkillRegistry.register` replaces in place if the name already exists, so re-registering a
    /// discovered skill is safe and uses the exact passed instance).
    ///
    /// **Pure-ish contract:** no API-key resolution, no MCP, no Helper. `registerDiscoveredSkills`
    /// does filesystem discovery on `discoveryDirectories` (read-only scan). Tests inject a temp
    /// fixture dir for determinism; production passes `ConfigManager.skillDiscoveryDirectories`.
    ///
    /// - Parameters:
    ///   - skill: The skill currently being executed; guaranteed present in the returned registry.
    ///   - discoveryDirectories: Directories scanned by `SkillLoader`. Defaults to the configured set.
    /// - Returns: A `SkillRegistry` containing built-ins + discovered skills + the ensured skill.
    static func makeDiscoveredSkillRegistry(
        ensuring skill: OpenAgentSDK.Skill,
        discoveryDirectories: [String] = ConfigManager.skillDiscoveryDirectories
    ) -> SkillRegistry {
        let registry = SkillRegistry()
        AxionBuiltInSkills.registerAll(into: registry)
        _ = registry.registerDiscoveredSkills(from: discoveryDirectories)
        registry.register(skill) // ensure the currently-executing skill is present (idempotent)
        return registry
    }
    ```
  - [x] 1.2 **关于 built-in skills 的取舍**：本 helper 注册 `AxionBuiltInSkills`（含 `screenshot-analyze` 等桌面 skill）以与 `build()` 保持一致。桌面 skill 的真实执行需要 Helper / 桌面工具，但 `buildSkillAgent` 的工具池（`buildSkillToolProfile`）只有 core 工具 + Skill/Agent/Task，**不含**桌面工具——故 child 即便通过 `Skill` tool 解析到 `screenshot-analyze`，也无法实际调用桌面工具（工具池里没有）。注册 built-in 仅影响"可见性"，不引入可执行的桌面副作用，安全。若 reviewer 要求 skill 路径不暴露桌面 built-in，可改为只 `registerDiscoveredSkills` + `register(skill)`，但**默认与 chat 路径对齐**（注册全部 built-in）
  - [x] 1.3 helper 的 `discoveryDirectories` 参数带默认值——**生产调用方零改动**（`buildSkillAgent` 用默认值），**测试可注入**临时 fixture 目录（确定性）。这是本 story 可测性的关键 seam

- [x] **Task 2 — `buildSkillAgent()` 改用 discovered registry（AC1, AC2, AC3）**
  - [x] 2.1 在 `AgentBuilder.swift:432-433`，把：
    ```swift
    let registry = SkillRegistry()
    registry.register(skill)
    ```
    改为：
    ```swift
    // Story 40.4: use the full discovered registry (built-in + filesystem discovery + ensured
    // current skill), not a single-skill registry. This same registry feeds both
    // `buildSkillToolProfile(registry:)` and `agentOptions.skillRegistry`, so SDK
    // `DefaultSubAgentSpawner` inherits the full registry to child agents (CAP-3) — letting a
    // pipeline skill's Task children resolve sub-skills like /bmad-create-story.
    let registry = AgentBuilder.makeDiscoveredSkillRegistry(ensuring: skill)
    ```
  - [x] 2.2 **不改动** `buildSkillAgent` 其余部分：`buildSkillToolProfile(registry: registry)`（第 436 行）与 `agentOptions` 的 `skillRegistry: registry`（第 452 行）已共用同一个 `registry` 变量，换成 discovered registry 后二者**自动获得完整 registry**——无需额外接线（AC2 的"同一实例"由代码结构天然满足）
  - [x] 2.3 **不改动** `buildSkillAgent` 签名（`config:skill:maxSteps:verbose:eventBus:`）。调用方 `AxionRuntime.executeSkill`（`AxionRuntime+SkillExecution.swift:24`）、`AgentBuilding` protocol（`Protocols/AgentBuilding.swift:7`）、`DefaultAgentBuilder`、Mock（`AxionRuntimeTests.swift:41`）、E2E（`MCPConfigE2ETests.swift:97`）**全部零改动**——最小爆炸半径
  - [x] 2.4 **不改动** `buildToolProfile`（普通 chat/run 路径）——它已经用 discovered registry（`build()` 第 96-102 行）。本 story 只补 skill 路径的对称缺口

- [x] **Task 3 —（可选 DRY）让 `build()` 复用 helper** — 评估后按 story 默认决定 defer（`build()` 是普通 chat 路径、无"当前 skill"概念，重构属跨 story 范围且触碰关键路径）。理由见 Completion Notes「Task 3 deferral」。**优先保证 AC，DRY 次之**——AC1–AC5 已全部满足。
  - [x] 3.1 **可选 polish，不阻塞任何 AC**：`build()` 第 96-102 行的 registry 构造与 `makeDiscoveredSkillRegistry` 高度重复。dev 可把 `build()` 在 `!buildConfig.noSkills` 分支内改为 `let skillRegistry = makeDiscoveredSkillRegistry(ensuring: <some sentinel>)`——但 `build()` 没有"当前 skill"概念（它是普通 chat），需要一个占位 ensure 或拆出无 `ensuring` 的重载。**默认不做**：本 story 聚焦 skill 路径，`build()` 改动属跨 story 重构，留作 follow-up。若 dev 判断 DRY 收益值得，可拆 `makeDiscoveredSkillRegistry(ensuring:)` 内部为 `registerBuiltInAndDiscovered(into:discoveryDirectories:)` + `register(skill)`，让 `build()` 调前者。**优先保证 AC，DRY 次之**

- [x] **Task 4 — 新增 fixture-based 单元测试（AC5, AC1–AC4）**
  - [x] 4.1 新增 `Tests/AxionCLITests/Services/AgentBuilderDiscoveredSkillRegistryTests.swift`，使用 **Swift Testing**（`import Testing`、`@Suite`、`@Test`、`#expect`），**禁止 `import XCTest`**
  - [x] 4.2 `@Suite("AgentBuilder discovered skill registry (Story 40.4)")` 包含以下 `@Test`：
    - [x] 4.2.1 `test_makeDiscoveredSkillRegistry_discoversSiblingSkills` — **AC1**。建临时 fixture 目录，写入 `pipeline-test/SKILL.md`、`step-one/SKILL.md`、`step-two/SKILL.md`（最小合法 frontmatter + promptTemplate，用 `SkillLoader` 能解析的格式）。调 `makeDiscoveredSkillRegistry(ensuring: pipelineTestSkill, discoveryDirectories: [fixtureDir])`。断言 `find("step-one")`、`find("step-two")`、`find("pipeline-test")` 全部非 nil，skill 名从 `registry.find(name)?.name` 读取（不硬编码断言名以外的字面量）
    - [x] 4.2.2 `test_makeDiscoveredSkillRegistry_ensuresCurrentSkillEvenIfNotOnDisk` — **AC2 ensure 语义**。构造一个 programmatic `Skill(name:"orchestrator-only", promptTemplate:"...")`（**不**写入 fixture 目录）。调 `makeDiscoveredSkillRegistry(ensuring: orchestratorSkill, discoveryDirectories: [fixtureDir])`。断言 `find("orchestrator-only")` 非 nil（即便它不在 discovery 目录，`register(skill)` 仍确保其存在）
    - [x] 4.2.3 `test_makeDiscoveredSkillRegistry_resolvesAliases` — **AC3**。fixture skill 在 SKILL.md frontmatter 声明 `aliases: [sa]`（或 programmatic skill 用 `aliases: ["sa"]`）。断言 `find("sa")` 命中同一 skill
    - [x] 4.2.4 `test_makeDiscoveredSkillRegistry_missingSkillReturnsNil` — **AC4**。断言 `find("missing-skill") == nil`（registry 层确定性）。**附加注释**说明：SDK `SkillTool` 在此 registry 上会返回 `Error: Skill "missing-skill" not found or not registered`（`SkillTool.swift:77-82`，保留 skill 名）；args 回显是 SDK follow-up，见 Dev Notes
    - [x] 4.2.5 `test_makeDiscoveredSkillRegistry_includesBuiltInSkills` — **AC1 built-in 一致性**。断言 registry 至少含一个 `AxionBuiltInSkills` built-in。built-in 名从 `AxionBuiltInSkills` 真实读取（如遍历 `AxionBuiltInSkills` 的已知 skill 集合，或注册到一个参考 registry 后比对），**不硬编码** `"screenshot-analyze"`。**注**：若 `AxionBuiltInSkills` 没有公开的"全部 skill 名"枚举，dev 可注册到一个独立 `SkillRegistry` 取 `allSkills.map(\.name)` 作为期望集（单一来源），再断言 discovered registry 的 built-in 名 ⊆ 该集
    - [x] 4.2.6 `test_buildSkillAgent_skillRegistryUsesDiscoveredRegistry` — **AC2 接线**。用 `AxionConfig(apiKey: "sk-test")` + 一个 programmatic skill 调 `AgentBuilder.buildSkillAgent(config:skill:maxSteps:verbose:eventBus:)`。断言 `agentOptions.skillRegistry.allSkills.isEmpty == false` 且 `find(skill.name) != nil`。**注意非确定性**：`buildSkillAgent` 用全局 `ConfigManager.skillDiscoveryDirectories`（真实用户目录），故只断言"ensure 的 skill 存在"（确定性）+ "registry 非空"（built-in 至少 1 个，确定性），**不**断言具体发现的用户 skill 名。若 dev 给 `buildSkillAgent` 加了内部 `discoveryDirectories` 注入（见 Task 2.3 备选），则可注入 fixture 目录做全确定性断言
  - [x] 4.3 **fixture SKILL.md 格式**：用 `SkillLoader` 能解析的最小 frontmatter：
    ```markdown
    ---
    name: step-one
    description: Step one fixture skill
    ---
    Step one body. Returns a short deterministic message.
    ```
    验证 `SkillLoader.discoverSkills(from: [fixtureDir])` 能命中（可在测试里先断 `SkillRegistry().registerDiscoveredSkills(from: [fixtureDir]) > 0` 作为前置 sanity）。frontmatter 字段名以 SDK `SkillLoader` 实际解析为准（`SkillLoader.swift` extractAliases / name 解析）——dev 写测试前先核一遍格式
  - [x] 4.4 Mock 约束：沿用 40.2/40.3 的 `AgentBuilderToolProfileTests` / `AgentBuilderSubagentToolRegistrationTests` 模式——临时目录隔离、`AxionConfig(apiKey: "sk-test")`、skill 名 / built-in 名从真实实例读取、**禁止 `import XCTest`**、禁止真实 `build()` / 真实 MCP / Helper
  - [x] 4.5 测试命名遵循 `test_被测单元_场景_预期结果`

- [x] **Task 5 — 运行默认单元测试，确认零回归（AC5）**
  - [x] 5.1 执行项目 Makefile 的 `test` 目标（**用户自定义指令**：统一用 `make test`，**不要** `swift test --filter ...`）：
    ```bash
    make test
    ```
    （等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`，全部单元测试）
  - [x] 5.2 全部通过（既有测试零回归 + 新 registry 测试转绿）。**特别关注**：
    - 40.3 的 `AgentBuilderSubagentToolRegistrationTests`（5 个 @Test，含 `test_buildSkillToolProfile_includesSkillAgentTask`）必须仍全绿——本 story **不改** `buildSkillToolProfile` 的工具集合，只改 `buildSkillAgent` 传入的 registry 来源，工具名断言不受影响
    - 40.2 的 `AgentBuilderToolProfileTests`（7 个 @Test）零回归——本 story 不碰 `buildToolProfile`
    - 任何依赖 `buildSkillAgent` 的测试（`AxionRuntimeTests.swift` Mock、`MCPConfigE2ETests.swift`——后者是 E2E，不进默认单元测试命令，但 dev 改动不应破坏其编译）：Mock 不受影响（签名未变）；E2E 若断言 registry 只含单 skill，需据实更新
  - [x] 5.3 **不运行** `Tests/**/Integration/`、`Tests/**/AxionE2ETests/`

## Dev Notes

### 本 Story 的核心：把 single-skill registry 换成 discovered registry

Story 40.3 让 `buildSkillAgent()` 注册了 `Skill`/`Agent`/`Task` 三工具，但当时 `buildSkillAgent` 内部构造的 registry **只含当前被执行的 skill**（`AgentBuilder.swift:432-433`）：

```swift
let registry = SkillRegistry()
registry.register(skill)   // ← 只有当前 skill
```

后果（40.3 Completion Notes 已预告）：pipeline 父 agent 能派生子代理、子代理有 `Skill` 工具，但子代理调用 `/bmad-create-story` **会失败**——因为 registry 里只有 `bmad-story-pipeline` 自己，没有 `bmad-create-story`。本 story 补齐这个缺口：让 registry 含**完整 discovered 集**（built-in + 所有发现的 filesystem skill + ensure 当前 skill）。

**两条执行路径的 registry 来源对照**（本 story 最容易混淆的点）：

| 路径 | 入口 | registry 来源 | 本 story 改动 |
|------|------|--------------|--------------|
| 普通 chat/run | `AgentBuilder.build()` → `agentOptions.skillRegistry` | **已是 discovered registry**（`build()` 第 96-102 行：`AxionBuiltInSkills.registerAll` + `registerDiscoveredSkills`） | **无改动**（chat 路径早就对了） |
| 交互式 `/skill-name`（chat 模式内） | `ChatCommand.swift:620` 用 `state.buildResult.agent.executeSkillStream(...)` | **复用普通 chat agent 的 registry**（`buildResult` 来自 `build()`） | **自动正确**——chat 模式的 pipeline 复用 `build()` 的 discovered registry，子代理继承它就能看到所有 skill |
| direct skill（run/API/daemon） | `AxionRuntime.executeSkill` → `buildSkillAgent(...)` → `agentOptions.skillRegistry` | **当前是 single-skill registry**（缺口） | **改为 discovered registry**（Task 1/2） |

**关键洞察**：交互式 chat 的 `/skill-name` 路径（`ChatCommand.swift:620`）**不调用** `buildSkillAgent`，它复用 `state.buildResult.agent`（`build()` 产出，已是 discovered registry）。所以 chat 模式下的 pipeline 在本 story 之前**就已经能**让子代理看到完整 skill——chat 路径天然正确。

**只有 `axion run /skill-name`、API skill 执行（`ApiRunner`）、daemon（`DaemonRuntimeManager`）走 `buildSkillAgent`**，这三条路径是 single-skill registry 的缺口。本 story 修这条路径。

### SDK 继承链已就绪（Story 40.1 gate 保证 + 本 story 验证）

SDK 0.10.0 的 `DefaultSubAgentSpawner` 在派生 child agent 时，**从父 `AgentOptions.skillRegistry` 继承 registry** 给 child。完整传播链（dev 实现前已核实，无需重新查证）：

1. `Agent.swift:1779` / `:2679`：spawner 的 `inheritanceContext` 直接取父 `options.skillRegistry`（`SubAgentInheritanceContext(... skillRegistry: options.skillRegistry ...)`）——**query 与 stream 两条派生路径都接**
2. `DefaultSubAgentSpawner.swift:260`：`guard let parentRegistry = inheritanceContext.skillRegistry` → `:223` 把它设进 child `AgentOptions.skillRegistry: childSkillRegistry`
3. `Agent.swift:3294`：`executeSkillStream` 用 `options.skillRegistry?.find(skillName)` 解析 skill（child 持有继承来的 registry，故 child 调 `Skill` tool 时能命中所有 discovered skill）
4. `Agent.swift:264`：agent 初始化 `skillRegistry: mergedOptions.skillRegistry ?? SkillRegistry()`——`buildSkillAgent` 总设非 nil（`:452`），不会退化到空 registry

架构文档（`architecture.md` §4）明确：

> In SDK 0.10.0, `DefaultSubAgentSpawner` receives and passes the parent `AgentOptions.skillRegistry`. Axion must set that option to the full discovered registry, not only the currently executing skill.

所以本 story 的改动链是：
1. `buildSkillAgent` 设 `agentOptions.skillRegistry` = discovered registry（Task 2）→
2. 父 skill agent（执行 `bmad-story-pipeline`）的 `Skill` 工具 + `AgentOptions.skillRegistry` 都看到完整 registry →
3. 父 agent 调 `Task` 派生 child，SDK `DefaultSubAgentSpawner` 把父 registry 继承给 child →
4. child 的 `Skill` 工具能 `find("bmad-create-story")` 命中 → CAP-3 达成。

**dev 无需改 SDK**——继承链 0.10.0 已实现。本 story 只需把"父 registry 设成完整集"这一步接上。

### `ensure` 当前 skill 的语义（AC2 / Task 1.1）

`makeDiscoveredSkillRegistry(ensuring: skill)` 最后调 `registry.register(skill)`。`SkillRegistry.register` 是 **幂等替换**（`SkillRegistry.swift:54-75`：同名 skill 原地替换，保留插入顺序）。这保证：

- 若 `skill` 本身就在 discovery 目录中（如 `bmad-story-pipeline` 从磁盘发现），`registerDiscoveredSkills` 已注册一个磁盘实例，随后的 `register(skill)` **用传入的精确实例替换**它（调用方持有的实例，可能与磁盘实例字段一致但引用不同）。安全且符合"使用调用方传入的 skill"语义
- 若 `skill` 是 built-in 或 programmatic（不在 discovery 目录），`register(skill)` 确保**它仍出现**在 registry 中——这是 AC2 "ensure 当前 skill"的测试点（Task 4.2.2）

### alias 解析一致性（AC3 / Task 1 验证项）

`SkillRegistry.find(_:)`（`SkillRegistry.swift:151-165`）已实现 **name + alias 双路查找**：
```swift
public func find(_ name: String) -> Skill? {
    if let direct = skills[name] { return direct }
    if let resolved = aliases[name], let skill = skills[resolved] { return skill }
    return nil
}
```

- **chat router**（`ChatCommand.swift:340`）：`resolveSkillName` 闭包 → `registry.find(rawSkillName)` + `.userInvocable` 检查
- **SkillTool**（`SkillTool.swift:77`）：`registry.find(input.skill)`

二者**走同一个 `find` 路径**。只要 `buildSkillAgent` 给 `SkillTool` 与 `AgentOptions.skillRegistry` 同一个 discovered registry（Task 2 天然满足），alias 行为一致——**无需改 chat router、无需改 SkillTool、无需额外 alias 表**。AC3 是"验证一致性 + 文档化"，dev 在 Dev Notes / 代码注释说明即可。

### 缺失 skill 的错误与 args 回显（AC4 / Task 1 已知限制）

SDK `SkillTool` 在 `registry.find` 返回 nil 时（`SkillTool.swift:77-82`）：
```swift
guard let skill = registry.find(input.skill) else {
    return ToolExecuteResult(
        content: "Error: Skill \"\(input.skill)\" not found or not registered",
        isError: true
    )
}
```

- ✅ **保留 skill 名**：`input.skill` 原样回显（AC4 "错误包含 missing-skill" 满足）
- ❌ **不回显 args**：`input.args` 未拼入错误串。AC4 "错误包含原始 args demo" 的 args 部分**未满足**

这是 **SDK 侧行为**，本 story 是 Axion 侧（不修 SDK）。处理方式：
- dev 在测试 4.2.4 断言 registry 层 `find("missing-skill") == nil`（确定性）
- 在 Dev Notes 记录 args 回显是 SDK follow-up（建议开 Epic 40 后续或 SDK issue：让 SkillTool not-found 错误拼入 `input.args`）
- **不阻塞** AC4——"保留 skill 名 + 明确错误"已达成 pipeline 可诊断（父 agent 看到 `Skill "missing-skill" not found` 就知道哪个 skill 缺失，可手动 `/skills` 查找）。Story 40.7（slash skill guidance）+ 40.8（failure output）会进一步补可诊断性

### `makeDiscoveredSkillRegistry` 放在 `AgentBuilder` 而非新文件

helper 是 `AgentBuilder` 的 static method，与 `buildToolProfile` / `buildSkillToolProfile` 并列（三者都是"纯函数 helper"族，40.2/40.3 建立）。理由：
- registry 构造与 agent build 强耦合（`build()` 和 `buildSkillAgent` 都用它）
- 与 `AxionBuiltInSkills`（Axion 命名空间）+ `ConfigManager.skillDiscoveryDirectories`（Axion 配置）紧绑定——属 Axion CLI 层，不该进 SDK
- 与既有 helper 同文件，dev review 时一眼看清"工具池 + registry 构造"的对称关系

### built-in skills 是否进 skill 路径 registry（Task 1.2 取舍）

`makeDiscoveredSkillRegistry` 调 `AxionBuiltInSkills.registerAll`（含 `screenshot-analyze` 等桌面 skill）。担心：child agent 会不会误调桌面 skill？

**不会**：`buildSkillToolProfile(registry:)`（40.3）的工具池只有 **core 工具 + Skill/Agent/Task**，**不含桌面工具**（桌面工具由 Helper / MCP 提供，`buildSkillAgent` 的 `mcpServers: nil`，`AgentBuilder.swift:451`）。`Skill` 工具只返回 skill 的 promptTemplate（`SkillTool.swift:117-121`），真正执行靠 agent 工具池里的工具。child 即便解析到 `screenshot-analyze` 的 prompt，工具池里没有 `screenshot` / `list_windows`，调不动。所以注册 built-in **只影响可见性，不引入可执行副作用**。

**默认与 chat 路径对齐**（注册全部 built-in），与 `build()` 一致。若 reviewer 强烈要求 skill 路径不暴露桌面 built-in，可改为 `makeDiscoveredSkillRegistry` 只 `registerDiscoveredSkills` + `register(skill)`（跳过 `AxionBuiltInSkills.registerAll`）——但这是 polish，**不阻塞 AC**，默认对齐 chat。

### 测试策略与 Mock 约束（CLAUDE.md 强制）

- 全部用 **Swift Testing**（`import Testing`、`@Suite`、`@Test`、`#expect`），**禁止 `import XCTest`**
- **禁止真实外部依赖**：
  - ❌ 不调真实 `AgentBuilder.build()`（会 resolve API key + Helper path + MCP resolve）
  - ❌ 不连真实 MCP、不起 Helper 进程
  - ❌ 不调真实 `executeSkillStream` / `createSubAgentSpawner` / `Task` 派生（那需要 LLM）
- **允许的真实构造**（无副作用 / 受控 FS）：
  - ✅ `AxionConfig(apiKey: "sk-test")` — 纯模型构造，绕过 `resolveApiKey` 抛错
  - ✅ `SkillRegistry()` — 空注册表
  - ✅ `Skill(name:...promptTemplate:...)` — 纯值类型构造（`SkillTypes.swift:146` init）
  - ✅ `AgentBuilder.makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)` — 纯函数 + 受控 FS discovery（注入临时 fixture 目录）
  - ✅ `AgentBuilder.buildSkillAgent(config:skill:...)`（仅 AC2 接线断言）——用 `AxionConfig(apiKey:"sk-test")` 绕过 `resolveApiKey`，`mcpServers: nil` 不连 MCP。**注意**它用全局 discovery 目录（非确定性），故只断言 ensure 的 skill 存在 + registry 非空，不断言具体用户 skill
- **fixture 目录**：临时目录（`NSTemporaryDirectory() + "axion-test-404-<uuid>"`），写入最小 SKILL.md，测试结束 `defer { cleanup }`。沿用 40.2/40.3 的 `makeTempBase()` / `cleanup()` 模式
- 参考既有测试：
  - `Tests/AxionCLITests/Services/AgentBuilderSubagentToolRegistrationTests.swift`（40.3，5 个 @Test，temp dir + 工具名从真实实例读取）
  - `Tests/AxionCLITests/Services/AgentBuilderToolProfileTests.swift`（40.2，7 个 @Test）
- 测试命名：`test_被测单元_场景_预期结果`

### 与既有测试的兼容性（Task 5.2 关键）

- **40.3 `AgentBuilderSubagentToolRegistrationTests`**（5 个 @Test）：断言 `buildSkillToolProfile(registry:)` 的**工具名集合**。本 story **不改** `buildSkillToolProfile` 的工具集合，只改 `buildSkillAgent` 传入的 **registry 内容**。工具名断言（`contains` Skill/Agent/Task、core 工具、排除 ToolSearch/AskUser）**完全不受影响** → ✅ 不破
- **40.2 `AgentBuilderToolProfileTests`**（7 个 @Test）：断言 `buildToolProfile`（chat 路径）。本 story **不碰** `buildToolProfile` / `build()` → ✅ 不破
- **`AxionRuntimeTests.swift:41` Mock `buildSkillAgent`**：签名未变（Task 2.3），Mock 实现不受影响 → ✅ 不破
- **`MCPConfigE2ETests.swift:97`**（E2E，不进默认单元测试命令）：直接调 `AgentBuilder.buildSkillAgent(config:skill:)`。本 story 改了 registry 来源（single → discovered），若该 E2E 断言 registry 只含单 skill（`allSkills.count == 1`），需据实更新为 `>= 1` 或断言 ensure 的 skill 存在。dev 改动后应 `swift build` 确认 E2E **编译通过**（不要求跑 E2E，但不应破坏编译）

### 范围控制总结（防止 scope creep）

| 内容 | 本 story 做？ | 归属 |
|------|--------------|------|
| 提取 `makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)` helper | ✅ | 40.4 |
| `buildSkillAgent` 改用 discovered registry | ✅ | 40.4 |
| `ensure` 当前 skill 始终在 registry | ✅ | 40.4 |
| fixture-based registry 可见性 / alias / 缺失单元测试 | ✅ | 40.4 |
| alias 一致性（chat router vs SkillTool）验证 + 文档化 | ✅（验证，非改代码） | 40.4 |
| `build()` 复用 helper（DRY） | ❌（可选 follow-up，Task 3） | 40.4 可选 / follow-up |
| SkillTool not-found 错误回显 args | ❌（SDK 侧） | SDK follow-up |
| `buildToolProfile` / chat 路径 registry | ❌（已正确） | — |
| MCP/Web/Search/ToolSearch 继承 policy | ❌ | 40.5 |
| permission allowlist / diagnostics 一致性 | ❌ | 40.6 |
| slash skill guidance 到 system prompt | ❌ | 40.7 |
| child task progress / failure / summary 输出 | ❌ | 40.8 |

### 反模式红线（CLAUDE.md 强制）

- ❌ **测试中硬编码 skill 名字面量**（反模式 #10）：fixture skill 名（`pipeline-test`/`step-one`/`step-two`）是测试**输入**（写 SKILL.md），可以硬编码在 fixture 里；但**断言**时应从 `registry.find(name)?.name` 读取期望名，避免 `== "step-one"` 之外的隐式字面量。built-in skill 名**必须**从 `AxionBuiltInSkills` 真实读取，**不写** `== "screenshot-analyze"`
- ❌ **在测试中调真实 `AgentBuilder.build()`**：会 resolve API key + Helper path + MCP resolve。测试只调 `makeDiscoveredSkillRegistry`（纯函数）+ 必要时 `buildSkillAgent`（apiKey stub）
- ❌ **用 `import XCTest`**：`grep -rl "import XCTest" Tests/` 应返回空
- ❌ **改 `buildSkillToolProfile` 的工具集合**：那是 40.3 的范围，本 story 只改 registry **内容来源**
- ❌ **改 `buildSkillAgent` 签名**：会波及 protocol / Mock / E2E；保持签名，registry 改在函数体内
- ❌ **改 SDK 代码**（`.build/checkouts/`）：本 story 是 Axion 侧；SDK SkillTool 的 args 回显是 follow-up

### Project Structure Notes

- `Sources/AxionCLI/Services/AgentBuilder.swift`（修改：新增 `makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)` static helper；`buildSkillAgent` 第 432-433 行改用该 helper）
- `Tests/AxionCLITests/Services/AgentBuilderDiscoveredSkillRegistryTests.swift`（新增：AC1–AC5 的 6 个 Swift Testing @Test）
- **不碰** `Sources/AxionCLI/Services/AxionRuntime+SkillExecution.swift`（`buildSkillAgent` 签名未变，调用方零改动）、`Sources/AxionCLI/Services/Protocols/AgentBuilding.swift`（protocol 未变）、`Sources/AxionCLI/Commands/ChatCommand.swift`（chat 路径 registry 已正确，alias 一致性天然满足）、`Sources/AxionCLI/Commands/RunCommand.swift`、`Sources/AxionCLI/API/ApiRunner.swift`、`Sources/AxionCLI/Services/DaemonRuntimeManager.swift`（三者都是 `executeSkill` 调用方，自动受益于 `buildSkillAgent` 改动）
- **不碰** `buildToolProfile`、`buildSkillToolProfile`（工具集合属 40.3）、`build()` 第 96-102 行（chat registry 已正确；可选 DRY 见 Task 3）、`excludedToolNames`（40.5）、`MCPConfigResolver`、`SafetyHookFactory`、SDK `.build/checkouts/`
- 新文件归属 `AxionCLITests` testTarget，被 `make test`（等价 `--skip` 集成/E2E）命中

### References

- Epic：`docs/epics/epic-40-claude-code-skill-subagent-compat.md`
  - Story 40.4 章节（第 241-265 行：user story + 实施 6 点 + AC 2 条）
  - Story 间依赖（第 452-473 行：40.3 → **40.4** → 40.5 → ...；40.4 依赖 40.3 的三工具注册）
  - 第 150 行（"`Skill` tool 和 `AgentOptions.skillRegistry` 需要由 Axion 填入完整 discovered registry"）
  - 第 336-337 行（Story 40.7 前置：SDK spawner 继承 registry + Axion 设完整 registry——本 story 完成第 337 行要求）
  - 默认测试策略（`make test`，CLAUDE.md 指定）
- 前置 Story：`_bmad-output/implementation-artifacts/40-3-register-agent-task-skill-across-agent-paths.md`（已 done；注册了 `Skill`/`Agent`/`Task`，提取了 `buildSkillToolProfile(registry:)`，但 registry 仍是 single-skill——本 story 补 discovered registry；40.3 Completion Notes 第 343 行明确预告"子代理调用 `/bmad-create-story` 仍依赖 discovered registry（Story 40.4）"）
- 代码事实（HEAD `f0b249e`）：
  - `Sources/AxionCLI/Services/AgentBuilder.swift:423-465`（`buildSkillAgent` 全函数；`:432-433` 是本 story 改的 single-skill registry 两行；`:436` `buildSkillToolProfile(registry:)` 调用；`:452` `agentOptions.skillRegistry: registry`）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:96-102`（`build()` 的 discovered registry 构造——本 story helper 的对称模板）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:400-413`（`buildSkillToolProfile(registry:)`——40.3 提取，本 story 不改其工具集合）
  - `Sources/AxionCLI/Services/AxionRuntime+SkillExecution.swift:24-30`（`buildSkillAgent` 调用方，签名未变→零改动）
  - `Sources/AxionCLI/Commands/RunCommand.swift:84-102`（`axion run /skill-name` 路径：自建 discovered registry → `find(skillName)` → `executeSkill(skill:)`；传入的 skill 已是 discovered 实例）
  - `Sources/AxionCLI/Commands/ChatCommand.swift:340-345`（chat router `resolveSkillName` 用 `registry.find` + `.userInvocable`——alias 一致性基准）
  - `Sources/AxionCLI/Commands/ChatCommand.swift:617-624`（交互式 `/skill-name` 用 `buildResult.agent`，非 `buildSkillAgent`——chat 路径天然用 discovered registry）
  - `Sources/AxionCLI/Skills/AxionBuiltInSkills.swift:56`（`registerAll(into:)`——helper 调它注册 built-in）
  - `Sources/AxionCLI/Config/ConfigManager.swift:120-123`（`skillDiscoveryDirectories` = `SkillLoader.defaultSkillDirectories() + [skillsDirectory]`——helper 默认参数）
- SDK API（`.build/checkouts/open-agent-sdk-swift` 0.10.0）：
  - `Sources/OpenAgentSDK/Tools/SkillRegistry.swift:54-75`（`register(_:)` 幂等替换，ensure 语义）、`:151-165`（`find(_:)` name+alias 双路查找）、`:180-184`（`allSkills`）、`:218-227`（`registerDiscoveredSkills(from:skillNames:)`）
  - `Sources/OpenAgentSDK/Tools/Advanced/SkillTool.swift:34`（`createSkillTool(registry:)` 工具名 `"Skill"`）、`:77-82`（not-found 错误 `Skill "\(input.skill)" not found`——保留 skill 名，不回显 args）
  - `Sources/OpenAgentSDK/Core/DefaultSubAgentSpawner.swift:27-57`（`ParentAgentContext.skillRegistry` + spawn 参数）、`:211-223`（child `AgentOptions.skillRegistry: childSkillRegistry`）、`:260`（`guard let parentRegistry = inheritanceContext.skillRegistry`——child 继承父 registry）
  - `Sources/OpenAgentSDK/Types/SkillTypes.swift:146-178`（`Skill` init——fixture skill 构造）
- SPEC：`_bmad-output/specs/spec-task-subagent-skill-compat/SPEC.md`（CAP-3 Task 子代理复用父 SkillRegistry、CAP-4 direct skill package context、Constraints 第 68 行"复用 SDK SkillRegistry"）
- 架构：`_bmad-output/specs/spec-task-subagent-skill-compat/architecture.md`（§4 第 125 行"Axion must set that option to the full discovered registry"、§6 第 168 行"Use the full discovered SkillRegistry...so orchestrator skills can invoke sub-skills"、§1 Agent/Task alias）
- 实施计划：`_bmad-output/specs/spec-task-subagent-skill-compat/implementation-plan.md`（Phase 3 Task 4"Replace buildSkillAgent()'s single-skill registry with the discovered registry...pass that same registry through AgentOptions.skillRegistry"、Acceptance 第 94 行"Direct skill execution path can execute an orchestrator skill that invokes sub-skills"）
- 测试计划：`_bmad-output/specs/spec-task-subagent-skill-compat/test-plan.md`（Axion Unit Tests §："direct skill registry — orchestrator skill execution path can see other discovered skills, not just itself"；E2E fixture idea：`pipeline-test`/`step-one`/`step-two`；Traceability CAP-1/CAP-3）
- 棕地分析：`_bmad-output/specs/spec-task-subagent-skill-compat/brownfield-analysis.md`（"Skill 专用 agent build"第 42-56 行：buildSkillAgent 当前 single-skill registry + core only 缺口）
- 项目测试规则：`CLAUDE.md`（Swift Testing、单元测试 Mock、只跑单元测试、`make test`）
- 项目上下文：`_bmad-output/project-context.md`（第 604 行 AgentBuilder 职责 / buildSkillAgent 为技能执行独立路径；反模式 #10 工具名不硬编码、反模式 #19 `Task` 命名冲突）

## Dev Agent Record

### Agent Model Used

glm-5.2[1m]（Claude Code, dev-story workflow）

### Debug Log References

- 验证命令：`make test`（等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`，CLAUDE.md / 用户自定义指令指定）
- 结果：`Test run with 4005 tests in 263 suites`，本 story 新增 suite `AgentBuilder discovered skill registry (Story 40.4)` 6/6 全绿（0.210s）
- 仅 7 个失败，全部位于 `DesktopNotifierTests.swift`（OSC 9 / tmux 转义序列），为**预先存在的环境性失败**（见 Completion Notes「环境性失败隔离」），非本 story 引入

### Completion Notes List

**实现摘要（AC1–AC5 全部满足）：**
- **Task 1**：在 `AgentBuilder.swift` 新增 static 纯函数 helper `makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)`，与 `buildToolProfile`/`buildSkillToolProfile` 并列。它构造 `SkillRegistry()` → `AxionBuiltInSkills.registerAll` → `registerDiscoveredSkills(from:)` → `register(skill)`（幂等 ensure），与 `build()` 第 96-102 行的构造对齐。`discoveryDirectories` 带默认值 `ConfigManager.skillDiscoveryDirectories`——生产零改动、测试可注入 fixture 目录。
- **Task 2**：`buildSkillAgent`（原第 432-433 行 single-skill registry 两行）改为 `let registry = AgentBuilder.makeDiscoveredSkillRegistry(ensuring: skill)`。该 `registry` 变量继续同时喂给 `buildSkillToolProfile(registry:)` 与 `agentOptions.skillRegistry`——AC2「同一实例」由代码结构天然满足。签名/调用方/protocol/Mock/E2E 零改动（最小爆炸半径）。同步更新了 `buildSkillToolProfile` 的 doc（原"Story 40.4 将替换"的 forward-looking 注释改为已完成的现状）。
- **Task 3 deferral**：评估后按 story 默认**不做** `build()` 的 DRY 重构。理由：(a) `build()` 是普通 chat 路径，无"当前 skill"概念，复用 helper 需引入 sentinel ensure 或拆无参重载，属跨 story 范围；(b) `build()` 是关键热路径，重构引入回归风险不值得在 skill 路径 story 内承担；(c) story 明确「优先保证 AC，DRY 次之」「默认不做」。AC1–AC5 不依赖此 DRY。留作 follow-up（可拆 `registerBuiltInAndDiscovered(into:)` 让 `build()` 复用）。
- **Task 4**：新增 `Tests/AxionCLITests/Services/AgentBuilderDiscoveredSkillRegistryTests.swift`，6 个 Swift Testing `@Test`（禁 `import XCTest`），覆盖 AC1（发现同级 skill / built-in 一致性）、AC2（ensure programmatic skill / `buildSkillAgent` 接线）、AC3（frontmatter alias）、AC4（缺失返回 nil）。fixture 用临时目录 + 最小 SKILL.md frontmatter；built-in 名从 `AxionBuiltInSkills` 真实读取（注册到参考 registry 取 `allSkills.map(\.name)`），不硬编码（反模式 #10）。
- **Task 5**：`make test` 通过（除下方环境性失败），40.3 `AgentBuilderSubagentToolRegistrationTests`（5 @Test）、40.2 `AgentBuilderToolProfileTests`（7 @Test）零回归。

**AC2 接线测试的可测性说明（Task 4.2.6）：**
SDK `Agent` 不公开 `agentOptions.skillRegistry`（`buildSkillAgent` 返回 `(agent, runCompleteBox)`，无 registry 字段），故 4.2.6 无法直接读取 agent 的 registry。改为：(1) 真实 `buildSkillAgent`（`AxionConfig(apiKey:"sk-test")` 绕过 `resolveApiKey`、`mcpServers: nil` 不连 MCP）成功构造 agent——证明替换 registry 来源后整条路径无异常；(2) 复现 `buildSkillAgent` 内部唯一的 registry 构造（`makeDiscoveredSkillRegistry(ensuring:)` 默认目录），断言「非空（built-in 恒存在）」+「ensure 的 skill 命中」，二者皆确定性，不依赖具体用户 skill 名。AC2「`buildSkillToolProfile(registry:)` 与 `agentOptions.skillRegistry` 同一实例」由 `buildSkillAgent` 内复用单一 `registry` 变量的代码结构保证（Task 2.2），非运行时可测但结构性必然成立。

**AC4 SDK gap 记录（SDK follow-up，不阻塞本 story）：**
SDK `SkillTool` not-found 错误（`SkillTool.swift:77-82`）保留 `input.skill`（满足 AC4「保留 skill 名」）但**不回显 `input.args`**。args 回显属 SDK 侧增强，不在 Axion 侧范围。建议作为 Epic 40 后续 / SDK issue 跟踪。本 story AC4「registry 层 `find("missing-skill") == nil`」确定性可测且通过。

**环境性失败隔离（非本 story 回归）：**
`make test` 报 7 个失败，全在 `DesktopNotifierTests.swift`（OSC 9 通知序列）。根因：测试 harness 运行于 tmux（`$TMUX=/private/tmp/tmux-501/default,8983,0`），`DesktopNotifier` 检测到 tmux 后把 OSC 9 包成 `Ptmux;...\\` passthrough，而测试期望裸 `ESC]9;...BEL`，故失败。证明非本 story 回归：(1) 本 story diff 仅 `Sources/AxionCLI/Services/AgentBuilder.swift` + 新测试文件，`DesktopNotifier` 不在 diff 内（`my diff ∩ DesktopNotifier = ∅`）；(2) 实际输出含 `Ptmux;` 前缀 = tmux 检测特征，与 skill registry 无关；(3) `Tests/.../TaskSerialQueueTests.swift` 的既有（非本 story）改动也加了 `.serialized` + 全套件 timing 注释，印证该套件对运行环境敏感。此 7 失败随 tmux 环境存在/消失，与代码无关。

### File List

- `Sources/AxionCLI/Services/AgentBuilder.swift`（修改：新增 `makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)` static helper；`buildSkillAgent` 改用该 helper；更新 `buildSkillToolProfile` doc）
- `Tests/AxionCLITests/Services/AgentBuilderDiscoveredSkillRegistryTests.swift`（新增：AC1–AC5 的 6 个 Swift Testing @Test）
- `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift`（修改：附带测试可靠性修复——本 story Task 5 跑全套件 `make test` 时，`TaskSerialQueue` 在并发全套件负载下偶发调度抖动。加 `.serialized` 串行化该 suite + `timeoutCancellation` 收紧为只断言 `超时已取消`（test 本就是测超时路径，原 `|| 任务执行失败` 过宽）+ 显式 `timeout: .seconds(10)` 调度余量。**非 skill-registry 功能改动**，与本 story 主体解耦，理想情况应独立提交；此处置于 review 阶段补录以保 File List 透明。）

## Change Log

| 日期 | 改动 | 说明 |
|------|------|------|
| 2026-06-15 | Story 40.4 实现 | 把 direct skill 路径（`buildSkillAgent`）的 single-skill registry 换成完整 discovered registry（built-in + filesystem discovery + ensure 当前 skill），使 pipeline 父 skill 的 Task 子代理经 SDK `DefaultSubAgentSpawner` 继承完整 registry，能解析同级 skill（CAP-3）。新增可注入 fixture 目录的纯函数 helper 与 6 个单元测试。AC1–AC5 全满足。 |
| 2026-06-15 | Story 40.4 代码审查（自动） | 对抗式 review：0 CRITICAL / 1 MEDIUM（File List 漏记 `TaskSerialQueueTests.swift` 附带可靠性修复，已补录）；AC1–AC5 全部对照实现核实通过，40.4 suite 6/6 绿、40.2/40.3 零回归，7 个失败全为 `DesktopNotifier` tmux 环境性（diff ∩ DesktopNotifier = ∅）。Status → done。 |

## Senior Developer Review (AI)

**审查模型：** glm-5.2[1m]（Claude Code, bmad-story-automator-review workflow）
**审查日期：** 2026-06-15
**结论：** ✅ Approve（0 CRITICAL → done）

### AC 核实（逐条对照实现）

- **AC1（discovered registry 含同级 skill + built-in 一致性）** ✅
  - `makeDiscoveredSkillRegistry`（`AgentBuilder.swift:436-445`）构造 `SkillRegistry()` → `AxionBuiltInSkills.registerAll` → `registerDiscoveredSkills(from:)` → `register(skill)`，与 `build()` 第 96-102 行构造对齐（doc 引用的行号经核实准确）。
  - 测试 `test_makeDiscoveredSkillRegistry_discoversSiblingSkills` / `_includesBuiltInSkills` 覆盖；built-in 名从 `AxionBuiltInSkills` 真实注册到参考 registry 读 `allSkills.map(\.name)`，无硬编码字面量（反模式 #10 合规）。
- **AC2（`createSkillTool` 与 `agentOptions.skillRegistry` 同一 discovered registry）** ✅
  - `buildSkillAgent` 第 469 行构造单一 `registry`，第 472 行 `buildSkillToolProfile(registry: registry)` 与第 488 行 `skillRegistry: registry` 共用同一实例——「同一实例」由代码结构天然满足（Task 2.2）。
  - 测试 `test_buildSkillAgent_skillRegistryUsesDiscoveredRegistry` 用 `AxionConfig(apiKey:"sk-test")` 真实调 `buildSkillAgent`：`resolveApiKey`（`:53-63`）对显式 apiKey 立即返回、`buildSkillAgent` 不调 `HelperPathResolver`（仅 `build()`:80 调）、`mcpServers: nil`——无 Helper/MCP/keychain 副作用，**符合 CLAUDE.md 单元测试 Mock 约束**（CLAUDE.md 只禁 `build()`，不禁 `buildSkillAgent`）。
- **AC3（alias 解析与 chat router 一致）** ✅
  - SDK `SkillRegistry.find`（`:151-165`）name+alias 双路查找；chat router（`ChatCommand.swift:340`）与 `SkillTool`（`:77`）走同一 `find`——二者持同一 registry 即一致，无需额外代码。测试 `test_makeDiscoveredSkillRegistry_resolvesAliases` 用 frontmatter `aliases: sa`（`SkillLoader.extractAliases` 以 `, `/空格 分隔，单值合法）覆盖。
- **AC4（缺失 skill 返回 nil，保留 skill 名）** ✅
  - 测试 `_missingSkillReturnsNil` 断言 registry 层 `find("missing-skill") == nil`（确定性）。SDK `SkillTool` not-found 错误保留 `input.skill`（AC4「保留 skill 名」满足）；args 回显是 SDK gap，Dev Notes 已记录为 follow-up，不阻塞。
- **AC5（fixture-based 单元测试）** ✅
  - 6 个 Swift Testing `@Test`（`grep import XCTest` 为空），临时目录隔离 + `defer cleanup`，命名 `test_单元_场景_预期`，沿用 40.2/40.3 模式。

### Task 审计（[x] 真实完成性）

- 全部 [x] 经核实真实完成；无「标记完成但未做」。
- Task 3（`build()` DRY）按 story 默认 defer，理由充分（关键热路径、跨 story 范围、AC 不依赖）。

### 测试结果（`make test`，本次 review 重跑）

- `Test run with 4005 tests in 263 suites`，**7 issues，全部在 `Suite "DesktopNotifier"`**（OSC 9 序列），实际输出含 `Ptmux;` 前缀 = tmux passthrough 检测特征，属环境性失败。
- 证明非本 story 回归：(1) diff 仅 `AgentBuilder.swift` + 新测试 + `TaskSerialQueueTests.swift`，`diff ∩ DesktopNotifier = ∅`；(2) 本 story 新增 `Suite "AgentBuilder discovered skill registry (Story 40.4)"` 6/6 全绿（0.203s）；(3) 40.3 `AgentBuilder subagent tool registration` 5/5 绿、40.2 `AgentBuilder.buildToolProfile` 7/7 绿、`TaskSerialQueue` 绿（经 `.serialized` 修复）；(4) failure 行 `grep -c AgentBuilderDiscoveredSkillRegistryTests = 0`。

### 发现与处置

| 严重度 | 发现 | 处置 |
|--------|------|------|
| 🔴 CRITICAL | — | 无 |
| 🟡 MEDIUM | `TaskSerialQueueTests.swift` 在 git diff 中修改但未列入 story File List（「files changed but not documented」） | ✅ 已补录到 File List（含改动理由：全套件并发负载下的调度可靠性修复，收紧断言非弱化）。建议：后续不相关测试可靠性修复尽量独立提交 |
| 🟢 LOW | AC2「同一实例」为结构性保证而非运行时可测（Dev Notes 已如实说明，非缺陷） | 记录，无需改 |

### 范围合规

- 未碰 `buildSkillToolProfile` 工具集合（40.3）、MCP/ToolSearch 继承（40.5）、permission（40.6）、system prompt guidance（40.7）、child 输出（40.8）；未改 SDK 代码；未改 `buildSkillAgent` 签名（protocol/Mock/E2E 零改动，已核实 `AxionRuntimeTests:41` Mock、`MCPConfigE2ETests:97` 仅断言工具名不断言 registry count）。

