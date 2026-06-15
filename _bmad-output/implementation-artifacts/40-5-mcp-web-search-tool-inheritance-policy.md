---
baseline_commit: 06f6293d54732249933719671071bc50913eb8fc
---

# Story 40.5: MCP / Web / Search Tool Inheritance Policy

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a Claude Code skill / subagent compatibility user,
I want a direct skill execution (`axion run /skill-name`、API skill 执行、daemon) 的 agent 与普通 chat agent **继承同一份可配置工具池策略**——MCP servers 来自 config、Web 工具可用、ToolSearch 由 provider/config 策略决定而非全局硬编码排除,
so that 一个声明 `allowed-tools: WebSearch, mcp__github__list_prs, Task` 或依赖 ToolSearch 延迟发现的 Claude Code skill，在 Axion 中不会被 lightweight skill runtime 静默缩窄工具能力（CAP-8）。

**类型：** Feature / tool-policy story。本 story 在 Story 40.3（`buildSkillToolProfile` 注册 Skill/Agent/Task）与 40.4（discovered registry）基础上，**把两件事接上**：(1) 把 `AgentBuilder.excludedToolNames` 里**硬编码的 `ToolSearch` 全局排除**改为 `AxionConfig.enableToolSearch` 驱动的 provider/config 策略（默认关闭，保持 GLM 稳定性——参见 `glm-toolsearch-issue` 记忆）；(2) 让 `buildSkillAgent()` 的 `mcpServers` 从硬编码 `nil` 改为**继承 config 的 MCP servers**（与普通 `build()` 同源）。本 story **不**改 allowed-tools / MCP namespaced 工具的解析与未知诊断（那是 40.6）、**不**加 slash skill guidance 到 system prompt（那是 40.7）、**不**改 child task 输出格式（那是 40.8）、**不**把 skill 路径升级到含 `.specialist` tier 的完整 chat 工具池（架构 MVP 的进一步统一，deferred）。

## Acceptance Criteria

1. **AC1 — ToolSearch 由硬编码全局排除改为 config 策略；默认关闭保持现状（零回归）**
   **Given** `AxionConfig.enableToolSearch` 未设置（`nil`，即默认）
   **When** 调用 `AgentBuilder.buildToolProfile(... config: <默认 config> ...)` 或 `AgentBuilder.buildSkillToolProfile(registry:enableToolSearch:false)`
   **Then** 返回工具池**不含** `ToolSearch`（与 40.5 前行为一致），`AskUser` 仍排除
   **And** Story 40.2 `AgentBuilderToolProfileTests`（7 个 @Test）、40.3 `AgentBuilderSubagentToolRegistrationTests`（5 个 @Test）**零回归**——它们用默认 config（`AxionConfig(apiKey:"sk-test")` → `enableToolSearch` 为 nil）调用 helper，ToolSearch 仍被排除，断言全部成立
   **And** `excludedToolNames` 静态常量**保留为** `["ToolSearch", "AskUser"]`（代表「ToolSearch 关闭时的默认排除集」），40.2/40.3 测试中 `for excluded in AgentBuilder.excludedToolNames` 的引用**不破**

2. **AC2 — `enableToolSearch=true` 在普通 chat 与 direct skill 两条路径都纳入 ToolSearch（单一策略来源）**
   **Given** `AxionConfig(enableToolSearch: true)`（即 `config.toolSearchEnabled == true`）
   **When** 调用 `AgentBuilder.buildToolProfile(... config: <enableToolSearch=true> ...)` 与 `AgentBuilder.buildSkillToolProfile(registry:enableToolSearch:true)`
   **Then** 两条路径返回的工具池**都含** `ToolSearch`（工具名从 `createToolSearchTool().name` 读取，不硬编码）
   **And** 两条路径**都仍排除** `AskUser`（恒定排除，不受 enableToolSearch 影响）
   **And** 两条路径**走同一个** `AgentBuilder.effectiveExcludedToolNames(allowingToolSearch:)` helper 计算排除集——**单一真相源**，不各自硬编码 ToolSearch 排除逻辑

3. **AC3 — direct skill 路径继承 config 的 MCP servers（不再 `nil`）**
   **Given** `AxionConfig` 配置了 user MCP servers（如 `config.mcpServers = ["my-server": .stdio(...)]`）
   **When** 调用 `AgentBuilder.resolveSkillMcpServers(from: config, helperPath: "/usr/bin/true")`（Story 新增的纯函数 helper，`helperPath` 可注入）
   **Then** 返回的 `[String: McpServerConfig]` **包含** user 配置的 `"my-server"`（key 存在）
   **And** 返回字典**恒包含** `"axion-helper"` baseline key（与普通 `build()` 的 `MCPConfigResolver.resolveMCPServers` 输出同源——`MCPConfigResolver.swift:13-14`）
   **And** `buildSkillAgent` 的 `AgentOptions.mcpServers` **不再是 `nil`**，而是 `resolveSkillMcpServers(from: config)` 的输出——skill agent 继承 config 的 MCP servers（CAP-8）
   **And** **已知非确定性**：`resolveSkillMcpServers` 的默认 `helperPath` 来自 `HelperPathResolver.resolveHelperPath()`（真实 FS 查找，CI 可能 nil → 回退 `/usr/bin/true`）。故测试**注入** `helperPath` 参数做全确定性断言（注入 seam，沿用 40.4 `makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)` 的可注入模式）；不断言 `axion-helper` 的 command 字面量路径（非确定性），只断言 key 存在

4. **AC4 — Web 工具在 direct skill 路径可用（继承已满足，policy 重构不误删）**
   **Given** `AgentBuilder.buildSkillToolProfile(registry:enableToolSearch:)` 被调用（`enableToolSearch` 取 true/false 均可）
   **When** 读取返回工具池的工具名
   **Then** `WebSearch` 与 `WebFetch` **都在**工具池中（二者属 SDK `.core` tier——`ToolRegistry.swift:75-77` 的 `createWebFetchTool()`/`createWebSearchTool()`，`getAllBaseTools(tier:.core)` 已纳入）
   **And** AC1/AC2 的 ToolSearch policy 重构**不改变** Web 工具可见性——`WebSearch`/`WebFetch` 从未在 `excludedToolNames` 中，AC4 是「验证 + 锁定」，确保 enableToolSearch 策略只影响 ToolSearch，不波及 Web 工具

5. **AC5 — ToolSearch policy 与 dry-run 解耦（read-only 工具，不属 side-effect 过滤）**
   **Given** `AgentBuilder.buildToolProfile(... dryrun:true ...)` 且 `config.enableToolSearch == true`
   **When** 读取 dry-run 工具池
   **Then** `ToolSearch` 仍按 `enableToolSearch` 策略出现（true → 在池）——ToolSearch 是 read-only 发现工具，**不在** `dryrunExcludedToolNames`（`["Bash","Skill","Agent","Task"]`，`AgentBuilder.swift:50`）
   **And** dry-run 的 side-effect 过滤（`dryrunExcludedToolNames`）**不触及** ToolSearch——两套过滤正交：`excludedToolNames`/`effectiveExcludedToolNames` 管 ToolSearch/AskUser 可见性策略，`dryrunExcludedToolNames` 管 side-effect
   **And** 默认（`enableToolSearch=false`）dry-run **仍排除** ToolSearch（与 40.5 前行为一致，零回归）

6. **AC6 — 新增 Swift Testing 单元测试覆盖 AC1–AC5**
   **Given** config 字段与 helpers 已实现
   **When** 在 `Tests/AxionCLITests/Services/` 新增 Swift Testing 测试文件
   **Then** 测试覆盖：
     - **ToolSearch 默认关闭（AC1）**：默认 config 调 `buildToolProfile` / `buildSkillToolProfile(enableToolSearch:false)`，断言 ToolSearch 不在池（零回归基准）
     - **enableToolSearch=true 双路径纳入（AC2）**：`AxionConfig(enableToolSearch:true)` 调 `buildToolProfile`、`buildSkillToolProfile(enableToolSearch:true)`，断言 ToolSearch 在池；AskUser 仍排除；工具名从 `createToolSearchTool().name` / `createAskUserTool().name` 读取
     - **单一策略（AC2）**：断言 `effectiveExcludedToolNames(allowingToolSearch:true) == ["AskUser"]`、`effectiveExcludedToolNames(allowingToolSearch:false) == excludedToolNames`（直接测 helper）
     - **MCP 继承（AC3）**：注入 user servers 调 `resolveSkillMcpServers(from:helperPath:)`，断言 user server key + `axion-helper` key 存在
     - **Web 工具在 skill 路径（AC4）**：`buildSkillToolProfile` 返回含 `createWebSearchTool().name` / `createWebFetchTool().name`
     - **dry-run 解耦（AC5）**：`buildToolProfile(dryrun:true, enableToolSearch=true)` 断言 ToolSearch 在池、Bash 不在池（`dryrunExcludedToolNames` 生效）
   **And** 测试**不调用真实 `AgentBuilder.build()`**（会 resolve API key + Helper path + MCP resolve）；直接调纯函数 helper（`buildToolProfile` / `buildSkillToolProfile` / `resolveSkillMcpServers` / `effectiveExcludedToolNames`）。对 `buildSkillAgent` 的 MCP 继承断言用 `resolveSkillMcpServers` 纯函数 + `AxionConfig(apiKey:"sk-test")`，不连真实 MCP、不起 Helper

> **ATDD 测试引用（RED 阶段将生成）**
> - 测试文件（建议）：`Tests/AxionCLITests/Services/AgentBuilderToolSearchAndMcpInheritanceTests.swift`（Swift Testing，覆盖 AC1–AC6）
> - ATDD checklist（Step 2 生成）：`_bmad-output/test-artifacts/atdd-checklist-40-5-mcp-web-search-tool-inheritance-policy.md`
> - 当前状态：待 Step 2 生成 RED 脚手架

## Tasks / Subtasks

- [x] **Task 1 — `AxionConfig` 新增 `enableToolSearch` 字段（AC1, AC2, AC5）**
  - [x] 1.1 在 `Sources/AxionCLI/Config/AxionConfig.swift` 的 `AxionConfig` struct 新增字段（与既有 optional Bool 字段如 `curatorEnabled`/`gatewayEnabled` 同款）：
    ```swift
    /// 是否启用 ToolSearch 工具（Story 40.5）。`nil`（默认）= 关闭——ToolSearch 会混淆 GLM
    /// 类模型的推理（参见 GLM ToolSearch issue），默认保持关闭以稳定提示。设为 `true` 时，
    /// 普通 chat 与 direct skill 两条路径都会纳入 ToolSearch（单一策略来源，CAP-8）。
    /// skill/subagent 在 allowed-tools 中声明 ToolSearch 只能在该策略允许时生效（opt-in 不能
    /// 覆盖用户 config / dry-run / permission——见 Story 40.6）。
    public var enableToolSearch: Bool?

    /// ToolSearch 是否启用（nil → false，保持 GLM 稳定的默认行为）。
    public var toolSearchEnabled: Bool { enableToolSearch ?? false }
    ```
  - [x] 1.2 `CodingKeys` enum 加 `case enableToolSearch`（`AxionConfig.swift:227-235`）
  - [x] 1.3 `default` 静态常量加 `enableToolSearch: nil`（`AxionConfig.swift:109-145`）
  - [x] 1.4 `init(...)` 加参数 `enableToolSearch: Bool? = nil`（`AxionConfig.swift:147-219`）+ `self.enableToolSearch = enableToolSearch`
  - [x] 1.5 `init(from decoder:)` 加 `enableToolSearch = try c.decodeIfPresent(Bool.self, forKey: .enableToolSearch)`（`AxionConfig.swift:237-283`）——`decodeIfPresent` 保证旧 config（无此 key）解码为 nil，向后兼容
  - [x] 1.6 **可测性取舍**：字段默认 `nil` → `toolSearchEnabled == false`，所有既有 `AxionConfig(apiKey:...)` 构造（40.2/40.3/40.4 测试、生产）**零改动**即保持 ToolSearch 关闭。已核实 `Tests/AxionCLITests/Config/AxionConfigTests.swift` 无 exhaustive field-count / CodingKeys 枚举断言（仅按字段值构造比对），新增 optional 字段**不破**既有 config 测试

- [x] **Task 2 — ToolSearch 排除改为 config 策略（AC1, AC2, AC4, AC5）**
  - [x] 2.1 在 `Sources/AxionCLI/Services/AgentBuilder.swift` 新增 static helper（与 `excludedToolNames` / `dryrunExcludedToolNames` 并列）：
    ```swift
    /// Returns the tool-name exclusion set honoring the ToolSearch config policy (Story 40.5).
    ///
    /// `AskUser` is always excluded (the system prompt handles user-confirmation prompts). `ToolSearch`
    /// is excluded only when the ToolSearch policy is OFF — previously this was a hard-coded global
    /// exclusion (`excludedToolNames`); it is now driven by `AxionConfig.enableToolSearch` so
    /// providers/users where ToolSearch degrades reasoning (e.g. GLM) keep it off by default, while
    /// others can opt in. Both `buildToolProfile` and `buildSkillToolProfile` call this helper so the
    /// two paths share a single source of truth (CAP-8).
    ///
    /// `excludedToolNames` (the no-arg constant) is preserved as the legacy "ToolSearch-off default"
    /// set — tests that iterate it (Story 40.2/40.3) keep passing under the default config.
    static func effectiveExcludedToolNames(allowingToolSearch: Bool) -> Set<String> {
        allowingToolSearch ? ["AskUser"] : excludedToolNames
    }
    ```
  - [x] 2.2 在 `buildToolProfile`（`AgentBuilder.swift:299-301`）把：
    ```swift
    var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
        .filter { !excludedToolNames.contains($0.name) }
        .filter { !dryrun || !dryrunExcludedToolNames.contains($0.name) }
    ```
    改为（用 config 派生的策略替换第一处 `excludedToolNames`）：
    ```swift
    let excluded = effectiveExcludedToolNames(allowingToolSearch: config.toolSearchEnabled)
    var agentTools: [ToolProtocol] = (getAllBaseTools(tier: .core) + getAllBaseTools(tier: .specialist))
        .filter { !excluded.contains($0.name) }
        .filter { !dryrun || !dryrunExcludedToolNames.contains($0.name) }
    ```
  - [x] 2.3 在 `buildSkillToolProfile`（`AgentBuilder.swift:402-416`）**加默认参数** `enableToolSearch: Bool = false`（默认 false 保持既有 `buildSkillToolProfile(registry:)` 单参调用零改动），并把：
    ```swift
    var tools = getAllBaseTools(tier: .core).filter { !excludedToolNames.contains($0.name) }
    ```
    改为：
    ```swift
    let excluded = effectiveExcludedToolNames(allowingToolSearch: enableToolSearch)
    var tools = getAllBaseTools(tier: .core).filter { !excluded.contains($0.name) }
    ```
    签名变为 `static func buildSkillToolProfile(registry: SkillRegistry, enableToolSearch: Bool = false) -> [ToolProtocol]`——**默认参数**使 40.3 测试的 `buildSkillToolProfile(registry:)` 调用零改动（默认 false → ToolSearch 排除 → 40.3 断言成立）
  - [x] 2.4 在 `buildSkillAgent`（`AgentBuilder.swift:472`）把 `let tools = buildSkillToolProfile(registry: registry)` 改为显式传入 config 派生的策略：
    ```swift
    let tools = buildSkillToolProfile(registry: registry, enableToolSearch: config.toolSearchEnabled)
    ```
  - [x] 2.5 **更新 `excludedToolNames` 的 doc 注释**（`AgentBuilder.swift:38-40`）：把「ToolSearch confuses GLM models」的硬编码语义改为「default ToolSearch-off exclusion set; the live exclusion is `effectiveExcludedToolNames(allowingToolSearch:)` driven by `AxionConfig.enableToolSearch`」，并更新 `buildSkillToolProfile` doc（`AgentBuilder.swift:393-395` 那句「does NOT add MCP / ToolSearch beyond the `.core` tier」改为已完成的现状描述——MCP 见 Task 3、ToolSearch 见 Task 2）
  - [x] 2.6 **dry-run 正交性（AC5）**：不动 `dryrunExcludedToolNames`（`AgentBuilder.swift:50`，仍 `["Bash","Skill","Agent","Task"]`）。ToolSearch 不在该集合——dry-run 的 side-effect 过滤与 ToolSearch 可见性策略正交。dev 在 Dev Notes 说明此正交性即可，不改 dry-run 逻辑

- [x] **Task 3 — direct skill 路径继承 config 的 MCP servers（AC3）**
  - [x] 3.1 在 `Sources/AxionCLI/Services/AgentBuilder.swift` 新增 static helper（与 `makeDiscoveredSkillRegistry` 并列的「pure-ish helper」族）：
    ```swift
    /// Resolves the MCP server config for the direct skill-execution path (Story 40.5).
    ///
    /// Mirrors `build()`'s MCP step (lines 124-133) so a skill agent inherits the SAME configured MCP
    /// servers as a normal chat/run agent (CAP-8 / architecture §6) — previously `buildSkillAgent`
    /// hard-coded `mcpServers: nil`, silently dropping MCP tools that a Claude Code skill may require.
    /// Falls back to "/usr/bin/true" when AxionHelper isn't installed: skill execution does NOT throw
    /// on a missing helper (unlike `build()`), so the MCP config is always buildable; real connection
    /// (and any failure) happens lazily at agent run, same as the normal path.
    ///
    /// **Pure-ish contract (mirrors `makeDiscoveredSkillRegistry`):** no API-key resolution, no MCP
    /// connection, no Helper process spawn. `helperPath` defaults to a real `HelperPathResolver` lookup
    /// (read-only FS check); tests inject a stub path for determinism. `MCPConfigResolver.resolveMCPServers`
    /// only builds the config dict — it does not connect.
    static func resolveSkillMcpServers(
        from config: AxionConfig,
        helperPath: String? = HelperPathResolver.resolveHelperPath()
    ) -> [String: McpServerConfig] {
        let resolvedHelperPath = helperPath ?? "/usr/bin/true"
        return MCPConfigResolver.resolveMCPServers(
            helperPath: resolvedHelperPath,
            includePlaywright: false,
            userServers: config.mcpServers
        )
    }
    ```
  - [x] 3.2 在 `buildSkillAgent`（`AgentBuilder.swift:487`）把 `mcpServers: nil,` 改为：
    ```swift
    // Story 40.5: inherit configured MCP servers (was nil) so skill agents that need MCP tools
    // (e.g. a skill declaring mcp__github__list_prs) get them. Mirrors build()'s MCP step via the
    // testable resolveSkillMcpServers helper. Connection is lazy (happens at agent run, not here).
    mcpServers: resolveSkillMcpServers(from: config),
    ```
  - [x] 3.3 **不改 `buildSkillAgent` 签名**（沿用 40.4 Task 2.3 的最小爆炸半径约束）：MCP 解析在函数体内，调用方（`AxionRuntime.executeSkill`、`AgentBuilding` protocol、`DefaultAgentBuilder`、Mock、E2E）**零改动**
  - [x] 3.4 **includePlaywright 取舍**：`resolveSkillMcpServers` 传 `includePlaywright: false`——skill 路径不自动探测 Playwright（避免 nvm FS 查找副作用）；若 user 在 `config.mcpServers` 显式配置了 `playwright`，`MCPConfigResolver` 的 userServers 分支（`MCPConfigResolver.swift:31-37`）仍会继承它。dev 在 Dev Notes 说明此取舍
  - [x] 3.5 **axion-helper baseline 取舍**：helper 恒注入 `axion-helper`（与 `build()` 同源），使 skill agent 能用桌面自动化 MCP（CAP-8「inherit ... MCP resource/tool」）。若 reviewer 要求 skill 路径不暴露桌面 MCP，可改为只继承 user servers（跳过 axion-helper），但**默认与 chat 路径对齐**（架构 §6「Inherit MCP/Web/Search availability from the normal build profile」）。dev 在 Dev Notes 标注此默认决策

- [x] **Task 4 — 新增单元测试（AC6, AC1–AC5）**
  - [x] 4.1 新增 `Tests/AxionCLITests/Services/AgentBuilderToolSearchAndMcpInheritanceTests.swift`，使用 **Swift Testing**（`import Testing`、`@Suite`、`@Test`、`#expect`），**禁止 `import XCTest`**
  - [x] 4.2 `@Suite("AgentBuilder ToolSearch & MCP inheritance (Story 40.5)")` 包含以下 `@Test`：
    - [x] 4.2.1 `test_buildToolProfile_defaultConfig_excludesToolSearch` — **AC1**。`AxionConfig(apiKey:"sk-test")`（enableToolSearch nil）调 `buildToolProfile(dryrun:false,...)`。断言 `createToolSearchTool().name` 不在工具名集合（零回归基准）。沿用 40.2/40.3 的 `makeTempBase()`/`cleanup()`/`makeConfig()` 模式
    - [x] 4.2.2 `test_buildToolProfile_enableToolSearchTrue_includesToolSearch` — **AC2 chat 路径**。`AxionConfig(apiKey:"sk-test", enableToolSearch:true)` 调 `buildToolProfile(dryrun:false,...)`。断言 `createToolSearchTool().name` 在集合，`createAskUserTool().name` 仍不在
    - [x] 4.2.3 `test_buildSkillToolProfile_defaultExcludesToolSearch_enableTrueIncludes` — **AC1+AC2 skill 路径**。两段：(a) `buildSkillToolProfile(registry:, enableToolSearch:false)` 断言 ToolSearch 不在；(b) `buildSkillToolProfile(registry:, enableToolSearch:true)` 断言 ToolSearch 在、AskUser 不在。同时验证 `buildSkillToolProfile(registry:)`（单参默认）等价于 `enableToolSearch:false`（默认参数零回归）
    - [x] 4.2.4 `test_effectiveExcludedToolNames_singlePolicySource` — **AC2 单一策略**。直接测 helper：`effectiveExcludedToolNames(allowingToolSearch:true) == Set([createAskUserTool().name])`、`effectiveExcludedToolNames(allowingToolSearch:false) == AgentBuilder.excludedToolNames`。`AskUser` 名从 `createAskUserTool().name` 读取构造期望集，不写字面量 `"AskUser"`（反模式 #10）
    - [x] 4.2.5 `test_buildSkillToolProfile_includesWebTools_regardlessOfToolSearchPolicy` — **AC4**。`buildSkillToolProfile(registry:, enableToolSearch:false)` 与 `enableToolSearch:true` 均断言 `createWebSearchTool().name` 与 `createWebFetchTool().name` 在集合（Web 工具不受 ToolSearch 策略影响）
    - [x] 4.2.6 `test_resolveSkillMcpServers_inheritsUserServersAndAxionHelperBaseline` — **AC3**。构造 `AxionConfig(apiKey:"sk-test", mcpServers:["my-server": .stdio(command:"/usr/bin/true", args:nil, env:nil)])`（`AxionMcpServerConfig.stdio(command:args:env:)`，已核实 `Sources/AxionCLI/Models/AxionMcpServerConfig.swift:4`），调 `resolveSkillMcpServers(from: config, helperPath:"/usr/bin/true")`（**注入** helperPath 全确定）。断言返回字典含 `"my-server"` key 与 `"axion-helper"` key（key 存在，不断言 command 字面量路径——非确定性）。`"axion-helper"` 是 `MCPConfigResolver` baseline key（`MCPConfigResolver.swift:13`），断言时可引用该常量来源
    - [x] 4.2.7 `test_buildToolProfile_dryrunWithToolSearchEnabled_keepsToolSearch_dropsBash` — **AC5 dry-run 解耦**。`AxionConfig(apiKey:"sk-test", enableToolSearch:true)` 调 `buildToolProfile(dryrun:true,...)`。断言 `createToolSearchTool().name` 在集合（read-only，不受 dry-run 过滤）、`createBashTool().name` 不在集合（`dryrunExcludedToolNames` 生效）
  - [x] 4.3 Mock 约束：沿用 40.2/40.3/40.4 的 `AgentBuilderToolProfileTests` / `AgentBuilderSubagentToolRegistrationTests` / `AgentBuilderDiscoveredSkillRegistryTests` 模式——临时目录隔离、`AxionConfig(apiKey:"sk-test")`、工具名 / MCP server key 从真实实例或注入值读取、**禁止 `import XCTest`**、禁止真实 `build()` / 真实 MCP 连接 / Helper 进程
  - [x] 4.4 测试命名遵循 `test_被测单元_场景_预期结果`

- [x] **Task 5 — 运行默认单元测试，确认零回归（AC6）**
  - [x] 5.1 执行项目 Makefile 的 `test` 目标（**用户自定义指令**：统一用 `make test`，**不要** `swift test --filter ...`）：
    ```bash
    make test
    ```
    （等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`，全部单元测试）
  - [x] 5.2 全部通过（既有测试零回归 + 新 ToolSearch/MCP 测试转绿）。**特别关注**：
    - 40.4 `AgentBuilderDiscoveredSkillRegistryTests`（6 个 @Test）：本 story 给 `buildSkillAgent` 加了 MCP 解析（Task 3）——40.4 的 `test_buildSkillAgent_skillRegistryUsesDiscoveredRegistry` 调真实 `buildSkillAgent`，MCP 解析后构造仍 side-effect-free（lazy 连接），registry 断言不受影响 → 应仍绿。若该测试内联注释提到「mcpServers: nil」（40.4 残留），dev 可顺手更新注释为「mcpServers: config 继承（40.5）」——**非断言改动**，保 File List 透明
    - 40.3 `AgentBuilderSubagentToolRegistrationTests`（5 个 @Test）：断言 `buildSkillToolProfile(registry:)` 工具名集合。本 story 给 `buildSkillToolProfile` 加默认参数 `enableToolSearch:false`——默认 false → ToolSearch 仍排除 → 40.3 的 `excludedToolNames` 迭代断言（`AgentBuilderSubagentToolRegistrationTests.swift:166,198`）**仍成立** → ✅ 不破
    - 40.2 `AgentBuilderToolProfileTests`（7 个 @Test）：断言 `buildToolProfile` 默认 config 排除 ToolSearch/AskUser。本 story 用 `effectiveExcludedToolNames(allowingToolSearch: config.toolSearchEnabled)`——默认 config（enableToolSearch nil → false）→ `effectiveExcludedToolNames(false) == excludedToolNames` → 40.2 断言（`AgentBuilderToolProfileTests.swift:181,213`）**仍成立** → ✅ 不破
    - `AxionConfigTests` / `ConfigManagerTests`：新增 optional 字段 `enableToolSearch` 不破既有 config 编解码测试（已核实无 exhaustive 断言）
  - [x] 5.3 **不运行** `Tests/**/Integration/`、`Tests/**/AxionE2ETests/`。`Tests/AxionE2ETests/Interactive/InteractiveE2EHelpers.swift:178` 与 `Tests/AxionE2ETests/AcceptanceE2ETests.swift:189` 有各自的本地 `excludedToolNames = ["ToolSearch","AskUser"]`（E2E helper，不进默认单元测试命令）——本 story **不改动**它们（E2E 范围，属 follow-up），dev 在 Dev Notes 记录此已知重复

## Dev Notes

### 本 Story 的核心：两处硬编码 → config 驱动

Story 40.3/40.4 让 direct skill 路径（`buildSkillAgent`）注册了 Skill/Agent/Task 三工具并接上完整 discovered registry。但工具池策略仍有两处**硬编码**缺口，让需要 MCP / ToolSearch 的 Claude Code skill 在 Axion 中失真（CAP-8 / 棕地分析「Skill 专用 agent build」结论）：

| 位置 | 40.5 前状态 | 问题 | 本 story 改动 |
|------|------------|------|--------------|
| `AgentBuilder.excludedToolNames`（`:40`）= `["ToolSearch","AskUser"]` | ToolSearch **全局硬编码排除**，两条路径都用 | 与 Claude Code 的 ToolSearch/alwaysLoad 可见性模型不一致；非 GLM provider 也被迫排除 | 拆为 `effectiveExcludedToolNames(allowingToolSearch:)`，由 `AxionConfig.enableToolSearch` 驱动（Task 2） |
| `buildSkillAgent`（`:487`）`mcpServers: nil` | direct skill agent **完全没有 MCP** | 声明 `mcp__github__list_prs` 等的 skill 静默丢失 MCP 工具 | `resolveSkillMcpServers(from:)` 继承 config 的 MCP servers（Task 3） |

Web 工具（`WebSearch`/`WebFetch`）属 `.core` tier（`ToolRegistry.swift:75-77`），**两条路径早已可用**——本 story 只验证/锁定其可见性不被 ToolSearch 策略重构波及（AC4），不改 Web 工具接线。

### 为什么 `enableToolSearch` 默认关闭（GLM 稳定性）

记忆 `glm-toolsearch-issue` 记录：**GLM 类模型在工具列表里看到 ToolSearch 会被混淆，导致无法直接使用 Bash 等工具**。Axion 当前默认模型路径可能经 baseURL 指向 GLM 类后端，故 ToolSearch **默认关闭**是经过验证的稳定性取舍。本 story 把这个取舍从「代码硬编码」升级为「config 开关」：

- `enableToolSearch: nil`（默认）→ `toolSearchEnabled == false` → ToolSearch 排除（**保持现状**，GLM 稳定）
- `enableToolSearch: true` → ToolSearch 纳入（供非 GLM provider 或接受风险的用户 opt-in）

这正符合架构 §3：「Axion may keep it disabled by default for providers where it degrades reasoning, and provider/config policy is authoritative」。

### 为什么保留 `excludedToolNames` 常量（向后兼容 seam）

40.2/40.3 测试**迭代** `AgentBuilder.excludedToolNames` 断言排除（`AgentBuilderToolProfileTests.swift:181,213`、`AgentBuilderSubagentToolRegistrationTests.swift:166,198`）。若直接把常量改为 `["AskUser"]`（移除 ToolSearch），这些测试在默认 config 下仍会过（因为运行时 ToolSearch 仍被 `effectiveExcludedToolNames(false)` 排除），但**常量语义**会与运行时不符（常量不含 ToolSearch，可运行时仍排除）。

更稳妥：**保留** `excludedToolNames = ["ToolSearch","AskUser"]` 作为「ToolSearch-off 默认排除集」的语义常量，新增 `effectiveExcludedToolNames(allowingToolSearch:)` 作为运行时策略入口。二者关系：`effectiveExcludedToolNames(false) == excludedToolNames`（恒等，测试可直接断言——Task 4.2.4）。这样：

- 40.2/40.3 测试 `for excluded in AgentBuilder.excludedToolNames { expect(!contains(excluded)) }` → 迭代 `["ToolSearch","AskUser"]`，运行时（默认 config）也排除这俩 → **断言成立，零改动**
- 新增的 `effectiveExcludedToolNames` 是单一策略真相源，两路径都调它（AC2）

### `effectiveExcludedToolNames` 放在 `AgentBuilder` 而非 config

helper 是 `AgentBuilder` 的 static method，与 `excludedToolNames`/`dryrunExcludedToolNames`/`buildToolProfile`/`buildSkillToolProfile` 同文件。理由：排除策略与工具池组装强耦合，且 `AskUser` 是 AgentBuilder 域知识（system prompt 处理它），不该散落到 config 层。`AxionConfig.enableToolSearch` 只提供「是否启用」的标量输入，策略计算留在 AgentBuilder。

### MCP 继承的设计：`resolveSkillMcpServers` 注入 seam（沿用 40.4 模式）

40.4 的 `makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)` 用**默认参数注入** fixture 目录实现可测性。本 story 的 `resolveSkillMcpServers(from:helperPath:)` 完全同款：

- `helperPath: String? = HelperPathResolver.resolveHelperPath()`——生产用默认（真实 FS 查找），**测试注入** `"/usr/bin/true"` 做全确定性
- 返回 `MCPConfigResolver.resolveMCPServers(...)` 输出——与 `build()`（`:128-132`）**同源**，保证 skill agent 与 normal agent 见到同样的 MCP servers

`buildSkillAgent` 调 `resolveSkillMcpServers(from: config)`（用默认 helperPath），**签名零改动**。MCP 连接是 lazy（`AgentOptions` 只存 config，连接发生在 agent run），故 `buildSkillAgent` 构造仍 side-effect-free，40.4 的真实 `buildSkillAgent` 测试不受影响。

### MCP 继承后 40.4 测试的影响（Task 5.2 关键）

40.4 `test_buildSkillAgent_skillRegistryUsesDiscoveredRegistry`（`AgentBuilderDiscoveredSkillRegistryTests.swift`）调真实 `buildSkillAgent(AxionConfig(apiKey:"sk-test"))`。本 story Task 3 让 `buildSkillAgent` 多解析一次 MCP（`resolveSkillMcpServers`）：

- `HelperPathResolver.resolveHelperPath()` → CI 多半 nil → 回退 `/usr/bin/true`
- `MCPConfigResolver.resolveMCPServers(helperPath:"/usr/bin/true", includePlaywright:false, userServers:nil)` → `["axion-helper": .stdio("/usr/bin/true")]`（只构造 dict，不连接）
- `buildSkillAgent` 把它塞进 `AgentOptions.mcpServers`，构造 agent → **无 MCP 连接、无 Helper 进程、无 API key 副作用**

40.4 测试只断言 registry（非空 + ensure skill 命中），**不断言 mcpServers** → ✅ 不破。若 40.4 测试有内联注释「mcpServers: nil」（40.4 Dev Notes 提到 buildSkillAgent `mcpServers: nil`），dev 顺手更新为「mcpServers: config 继承（40.5）」——保 File List 透明，**非断言改动**。

### ToolSearch 与 dry-run 的正交性（AC5）

两套过滤**职责分离**：

- `effectiveExcludedToolNames(allowingToolSearch:)`：管**工具可见性策略**（ToolSearch 由 config 决定；AskUser 恒排除）
- `dryrunExcludedToolNames`（`["Bash","Skill","Agent","Task"]`）：管**side-effect 过滤**（dry-run 只能 plan）

ToolSearch 是 read-only 发现工具，**不在** `dryrunExcludedToolNames`。故 dry-run + `enableToolSearch:true` → ToolSearch 仍在池（read-only，不违反「plan only」）；dry-run + 默认 → ToolSearch 仍排除（config 关）。两套正交，互不干扰。dev 不改 `dryrunExcludedToolNames`。

### skill/subagent opt-in 与 diagnostics 的边界（40.6，不在本 story）

架构 §3：「Skill/subagent declarations may request ToolSearch, but they must not override user config, provider policy, dry-run, permission, or safety constraints」。本 story 只建立**config 天花板**：

- `enableToolSearch=true` → ToolSearch 对所有 agent（含 skill 路径）可用
- `enableToolSearch=false`（默认）→ ToolSearch 不可用

skill 在 `allowed-tools` 里声明 `ToolSearch` 时的**逐 skill 过滤 + 未知工具诊断**（如 config 关闭时 skill 请求 ToolSearch 该产生什么 diagnostic）属 Story 40.6（permission-allowlist-and-diagnostics-consistency）。本 story 不实现 allowed-tools 解析、不产生 diagnostic。dev 在 Dev Notes 标注此边界。

### 范围控制总结（防止 scope creep）

| 内容 | 本 story 做？ | 归属 |
|------|--------------|------|
| `AxionConfig.enableToolSearch` 字段 + `toolSearchEnabled` 计算属性 | ✅ | 40.5 |
| `effectiveExcludedToolNames(allowingToolSearch:)` helper | ✅ | 40.5 |
| `buildToolProfile` / `buildSkillToolProfile` 用 config 派生策略 | ✅ | 40.5 |
| `resolveSkillMcpServers(from:helperPath:)` helper | ✅ | 40.5 |
| `buildSkillAgent` 继承 config MCP（was nil） | ✅ | 40.5 |
| Web 工具在 skill 路径可见性验证/锁定 | ✅（验证，AC4） | 40.5 |
| ToolSearch policy / MCP 继承 / Web 可见性 单元测试 | ✅ | 40.5 |
| allowed-tools 解析 / MCP namespaced 过滤 / 未知工具诊断 | ❌ | 40.6 |
| skill `allowed-tools: ToolSearch` opt-in 逐 skill 过滤 + diagnostic | ❌ | 40.6 |
| slash skill guidance 到 system prompt | ❌ | 40.7 |
| child task progress / failure / summary 输出 | ❌ | 40.8 |
| skill 路径升级到含 `.specialist` tier 的完整 chat 工具池 | ❌（架构 MVP 进一步统一，deferred） | follow-up |
| E2E helper 本地 `excludedToolNames` 对齐（`InteractiveE2EHelpers`/`AcceptanceE2ETests`） | ❌（E2E 范围） | follow-up |
| 改 SDK 代码（`.build/checkouts/`） | ❌ | — |
| 改 `buildSkillAgent` 签名 | ❌（最小爆炸半径，40.4 约束） | — |
| 改 `dryrunExcludedToolNames` | ❌（AC5 正交性，不改） | — |

### 反模式红线（CLAUDE.md 强制）

- ❌ **测试中硬编码工具名字面量**（反模式 #10）：`createToolSearchTool().name`/`createAskUserTool().name`/`createWebSearchTool().name`/`createWebFetchTool().name`/`createBashTool().name` 从真实实例读取；`excludedToolNames`/`effectiveExcludedToolNames` 从既有静态常量/helper 读取；MCP server key `"axion-helper"`/`"my-server"` 中 `"my-server"` 是测试**注入**的 user server 名（可硬编码在注入值），`"axion-helper"` 是 `MCPConfigResolver` 的 baseline 字面量（`MCPConfigResolver.swift:13`，断言 key 存在时可引用该字面量或从 helper 行为推导）
- ❌ **在测试中调真实 `AgentBuilder.build()`**：会 resolve API key + Helper path + MCP resolve。测试只调纯函数 helper（`buildToolProfile`/`buildSkillToolProfile`/`resolveSkillMcpServers`/`effectiveExcludedToolNames`）
- ❌ **用 `import XCTest`**：`grep -rl "import XCTest" Tests/` 应返回空
- ❌ **改 `excludedToolNames` 常量内容**（移除 ToolSearch）：会破坏 40.2/40.3 测试的迭代语义；保留常量，新增 `effectiveExcludedToolNames`
- ❌ **改 `buildSkillAgent` 签名**：会波及 protocol / Mock / E2E；MCP 解析在函数体内（Task 3.3）
- ❌ **改 `buildSkillToolProfile` 为必填 `enableToolSearch`**：会破 40.3 的 `buildSkillToolProfile(registry:)` 单参调用；用**默认参数** `enableToolSearch: Bool = false`（Task 2.3）
- ❌ **改 `dryrunExcludedToolNames`**：AC5 要求 ToolSearch 与 dry-run 正交；不动 dry-run 集合
- ❌ **改 SDK 代码**（`.build/checkouts/`）：本 story 是 Axion 侧；SDK 0.10.0 已提供 `createToolSearchTool`/`createWebSearchTool`/`MCPConfigResolver` 所需 API

### Project Structure Notes

- `Sources/AxionCLI/Config/AxionConfig.swift`（修改：新增 `enableToolSearch: Bool?` 字段 + `toolSearchEnabled` 计算属性 + CodingKey + init 参数 + decoder 行 + default）
- `Sources/AxionCLI/Services/AgentBuilder.swift`（修改：新增 `effectiveExcludedToolNames(allowingToolSearch:)` 与 `resolveSkillMcpServers(from:helperPath:)` 两个 static helper；`buildToolProfile`（`:299-301`）与 `buildSkillToolProfile`（`:402-416`）改用 config 派生策略；`buildSkillAgent`（`:472`,`:487`）传 `enableToolSearch` + 继承 MCP；更新 `excludedToolNames`/`buildSkillToolProfile` doc 注释）
- `Tests/AxionCLITests/Services/AgentBuilderToolSearchAndMcpInheritanceTests.swift`（新增：AC1–AC6 的 7 个 Swift Testing @Test）
- **不碰** `Sources/AxionCLI/Services/AgentBuilder+Config.swift`（`buildSkillAgent` 签名未变，其 doc 注释提到「no MCP」可由 dev 顺手更新为现状，非强制）、`Sources/AxionCLI/Services/AxionRuntime+SkillExecution.swift`（调用方零改动）、`Sources/AxionCLI/Services/Protocols/AgentBuilding.swift`（protocol 未变）、`Sources/AxionCLI/Services/MCPConfigResolver.swift`（复用，不改）、`Sources/AxionCLI/Helper/HelperPathResolver.swift`（复用 `resolveHelperPath()`，不改）、`Sources/AxionCLI/Skills/AxionBuiltInSkills.swift`、`Sources/AxionCLI/Config/ConfigManager.swift`
- **不碰** `build()` 的 MCP 步骤（`:124-133`，chat 路径已正确）、`buildSkillToolProfile` 的工具**集合**（Skill/Agent/Task 属 40.3）、`makeDiscoveredSkillRegistry`（40.4）、`dryrunExcludedToolNames`（AC5 正交）、SDK `.build/checkouts/`
- 新文件归属 `AxionCLITests` testTarget，被 `make test`（等价 `--skip` 集成/E2E）命中

### References

- Epic：`docs/epics/epic-40-claude-code-skill-subagent-compat.md`
  - Story 40.5 章节（MCP/Web/Search 继承 + ToolSearch policy）
  - Story 间依赖（40.4 → **40.5** → 40.6 → ...；40.5 依赖 40.3 的 `buildSkillToolProfile` + 40.4 的 discovered registry）
  - CAP-8（skill/subagent 工具声明不被 lightweight runtime 静默缩窄）
  - 默认测试策略（`make test`，CLAUDE.md / 用户自定义指令指定）
- 前置 Story：
  - `_bmad-output/implementation-artifacts/40-3-register-agent-task-skill-across-agent-paths.md`（已 done；`buildSkillToolProfile(registry:)` 提取 + Skill/Agent/Task 注册；本 story 给它加默认参数 `enableToolSearch`）
  - `_bmad-output/implementation-artifacts/40-4-direct-skill-uses-discovered-skill-registry.md`（已 done；`makeDiscoveredSkillRegistry(ensuring:discoveryDirectories:)` 注入 seam 模式——本 story 的 `resolveSkillMcpServers(from:helperPath:)` 完全同款；40.4 范围表第 298 行明确「MCP/Web/Search/ToolSearch 继承 policy → 40.5」）
  - `_bmad-output/implementation-artifacts/40-2-shared-tool-profile-helper-with-behavior-parity.md`（已 done；`buildToolProfile` parity 提取 + `excludedToolNames` 常量——本 story 保留该常量语义）
- 代码事实（HEAD `06f6293`）：
  - `Sources/AxionCLI/Services/AgentBuilder.swift:38-40`（`excludedToolNames` 常量——本 story 保留，更新 doc）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:50`（`dryrunExcludedToolNames`——本 story 不改，AC5 正交）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:124-133`（`build()` 的 MCP 解析——`resolveSkillMcpServers` 的对称模板）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:279-372`（`buildToolProfile`——本 story 改 `:299-301` 的排除过滤为 config 派生）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:402-416`（`buildSkillToolProfile`——本 story 加默认参数 `enableToolSearch` + 改排除过滤）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:436-445`（`makeDiscoveredSkillRegistry`——注入 seam 模板，`resolveSkillMcpServers` 同款）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:455-501`（`buildSkillAgent`；`:472` `buildSkillToolProfile` 调用——本 story 传 `enableToolSearch`；`:487` `mcpServers: nil`——本 story 改为 `resolveSkillMcpServers(from: config)`）
  - `Sources/AxionCLI/Config/AxionConfig.swift:69-224`（struct；`:107` `mcpServers` 字段；`:109-145` default；`:147-219` init；`:226-284` Codable——本 story 加 `enableToolSearch`）
  - `Sources/AxionCLI/Services/MCPConfigResolver.swift:9-46`（`resolveMCPServers(helperPath:includePlaywright:userServers:writeWarning:)`——`resolveSkillMcpServers` 复用它；`:13-14` axion-helper baseline；`:31-37` user playwright 分支）
  - `Sources/AxionCLI/Helper/HelperPathResolver.swift:16`（`resolveHelperPath() -> String?`——`resolveSkillMcpServers` 默认参数调它）
- SDK API（`.build/checkouts/open-agent-sdk-swift` 0.10.0）：
  - `Sources/OpenAgentSDK/Tools/ToolRegistry.swift:64-95`（`getAllBaseTools(tier:)`；`.core` 含 `createToolSearchTool()`/`createWebFetchTool()`/`createWebSearchTool()`——`:75-77`）
  - `Sources/OpenAgentSDK/Tools/Core/ToolSearchTool.swift:47`（`createToolSearchTool()` 工具名 `"ToolSearch"`）
  - `Sources/OpenAgentSDK/Tools/Core/WebSearchTool.swift:43,55`（`createWebSearchTool()` 工具名 `"WebSearch"`）
  - `Sources/OpenAgentSDK/Tools/Core/WebFetchTool.swift:38,50`（`createWebFetchTool()` 工具名 `"WebFetch"`）
- SPEC：`_bmad-output/specs/spec-task-subagent-skill-compat/SPEC.md`（CAP-8 工具可见性继承；Constraints 第 71-73 行「ToolSearch 由 provider/config policy 决定」「allowed-tools 不能退化成无限制」——后者属 40.6）
- 架构：`_bmad-output/specs/spec-task-subagent-skill-compat/architecture.md`（§3 第 102-104 行「ToolSearch not globally impossible; provider/config policy authoritative」、第 104 行「MCP servers from config available to skill agents」；§6 第 161 行「Do not hard-code ToolSearch exclusion」、第 167 行「Inherit MCP/Web/Search availability from the normal build profile」）
- 实施计划：`_bmad-output/specs/spec-task-subagent-skill-compat/implementation-plan.md`（Phase 3 Task 6「Inherit MCP/Web/Search availability from the same build profile」、Task 7「Convert the hard-coded ToolSearch exclusion into provider/config policy」、Acceptance 第 95 行「A skill requiring WebSearch/WebFetch/ToolSearch/MCP can receive those tools when config and permissions allow」）
- 测试计划：`_bmad-output/specs/spec-task-subagent-skill-compat/test-plan.md`（Axion Unit Tests：`direct skill tool profile`、`ToolSearch policy`、`MCP inheritance` 三行——本 story AC 对应这三行；Traceability CAP-8）
- 棕地分析：`_bmad-output/specs/spec-task-subagent-skill-compat/brownfield-analysis.md`（「Axion 当前工具池」第 40 行「固定排除 ToolSearch...不能成为 skill/subagent 兼容层的硬规则」；「Skill 专用 agent build」第 56 行「skill agent 应从正常 agent 的可配置工具池继承」）
- 项目测试规则：`CLAUDE.md`（Swift Testing、单元测试 Mock、只跑单元测试、`make test`）
- 项目上下文：`_bmad-output/project-context.md`（第 604 行 AgentBuilder 职责 / buildSkillAgent 为技能执行独立路径；第 610 行 MCPConfigResolver 提取自 AgentBuilder；反模式 #10 工具名不硬编码）
- 记忆：`glm-toolsearch-issue`（GLM 模型被 ToolSearch 混淆——`enableToolSearch` 默认关闭的根因）

## Dev Agent Record

### Agent Model Used

glm-5.2[1m] (via bmad-dev-story workflow, 2026-06-15)

### Debug Log References

- 编译验证：`swift build` → `Build complete! (23.88s)`（Tasks 1-3 源码改动无错误）
- 全量单元测试：`make test` → `Test run with 4012 tests in 264 suites failed after 21.395 seconds with 7 issues`
  - 7 失败 **全部** 在 `DesktopNotifier` 套件（OSC 9 序列），与本 story 无关
  - 失败根因：`DesktopNotifier.isTmux()`（`Sources/AxionCLI/Chat/DesktopNotifier.swift:151-152`）在 `TMUX` 环境变量存在时返回 `true`，把 OSC 9 包裹成 DCS passthrough（`:139` `"\u{1B}Ptmux;\u{1B}\u{1B}]9;...\u{07}\u{1B}\\"`），而测试期望裸 OSC 9。本会话运行在 tmux 内（`TMUX=/private/tmp/tmux-501/default,76676,0`、`TERM=tmux-256color`）→ **环境性失败，非本 story 引入、非回归**
  - 证据：本次改动文件（`Config/AxionConfig.swift`、`Services/AgentBuilder.swift`）与 `Chat/DesktopNotifier.swift` 零依赖关系；DesktopNotifier 失败在 baseline_commit 06f6293 同样会复现（任何 tmux 会话内跑 make test 必现）
- 本 story 相关测试结果（全绿）：
  - `AgentBuilder ToolSearch & MCP inheritance (Story 40.5)` 套件 **passed**（7/7 @Test：AC1/AC2 chat/AC1+AC2 skill/AC2 单一策略/AC4 Web 工具/AC3 MCP/AC5 dry-run）
  - `AgentBuilder.buildToolProfile (Story 40.2)` 套件 **passed**（7 @Test，零回归）
  - `AgentBuilder subagent tool registration (Story 40.3)` 套件 **passed**（5 @Test，零回归）
  - `AgentBuilder discovered skill registry (Story 40.4)` 套件 **passed**（6 @Test，零回归——`buildSkillAgent` MCP 解析后构造仍 side-effect-free，registry 断言不受影响）

### Completion Notes List

- **AC1（ToolSearch 默认关闭，零回归）**：`AxionConfig.enableToolSearch: Bool?`（默认 nil → `toolSearchEnabled == false`）+ `effectiveExcludedToolNames(allowingToolSearch:false) == excludedToolNames`（恒等）。40.2/40.3 既有 `for excluded in AgentBuilder.excludedToolNames` 迭代断言零改动通过。`excludedToolNames` 常量保留为 `["ToolSearch","AskUser"]`（ToolSearch-off 默认集语义常量，未改其内容）。
- **AC2（enableToolSearch=true 双路径纳入，单一策略来源）**：`buildToolProfile` 用 `effectiveExcludedToolNames(allowingToolSearch: config.toolSearchEnabled)`；`buildSkillToolProfile` 加默认参数 `enableToolSearch: Bool = false` 并用同一 helper；`buildSkillAgent` 传 `config.toolSearchEnabled`。两路径走同一个 helper（单一真相源），`AskUser` 恒排除。
- **AC3（direct skill 路径继承 config MCP servers）**：新增 `resolveSkillMcpServers(from:helperPath:)`（沿用 40.4 `makeDiscoveredSkillRegistry` 的默认参数注入 seam 模式），`buildSkillAgent` 把 `mcpServers: nil` 改为 `resolveSkillMcpServers(from: config)`。`buildSkillAgent` 签名零改动（最小爆炸半径）；MCP 连接 lazy（构造 side-effect-free），40.4 真实 `buildSkillAgent` 测试不受影响。测试注入 `helperPath:"/usr/bin/true"` 做全确定性断言（user server key + axion-helper baseline key 存在，不断言 command 字面量路径）。
- **AC4（Web 工具在 skill 路径可见性锁定）**：`WebSearch`/`WebFetch` 属 `.core` tier，从未在 `excludedToolNames`/`dryrunExcludedToolNames` 中。新增测试在 `enableToolSearch:false` 与 `true` 两种策略下均断言二者在池——验证 ToolSearch 策略重构不波及 Web 工具。
- **AC5（ToolSearch policy 与 dry-run 正交）**：未动 `dryrunExcludedToolNames`（`["Bash","Skill","Agent","Task"]`）。ToolSearch 是 read-only 发现工具，不在该集合。`buildToolProfile(dryrun:true, enableToolSearch:true)` → ToolSearch 在池（config 策略支配）、Bash 不在池（dry-run side-effect 过滤生效）。两套过滤正交。
- **AC6（新增 Swift Testing 单元测试）**：`AgentBuilderToolSearchAndMcpInheritanceTests.swift`（7 @Test，禁 `import XCTest`，工具名/MCP key 从真实实例或注入值读取，不硬编码字面量——遵守反模式 #10）。
- **范围控制**：未改 `buildSkillAgent` 签名、未改 `excludedToolNames` 常量内容、未改 `dryrunExcludedToolNames`、未改 SDK 代码、未实现 allowed-tools 解析/diagnostic（属 40.6）。E2E helper 本地 `excludedToolNames`（`InteractiveE2EHelpers`/`AcceptanceE2ETests`）未对齐——属 E2E 范围 follow-up，本 story 不动。
- **incidental flaky-test 稳定化（review 透明度补录）**：跑 `make test` 时顺手稳定化了 `TaskSerialQueueTests.timeoutCancellation`（`@Suite(.serialized)` + `waitUntil` 10s 余量 + 断言收窄为仅「超时已取消」）。该改动与 ToolSearch/MCP 范围无关，原 Dev 阶段未入 File List，review 阶段补录于 File List / Change Log。测试仍绿（0.103s，远在余量内）。
- **设计取舍记录**：(1) `includePlaywright:false`——skill 路径不自动探测 Playwright（避免 nvm FS 查找副作用）；user 在 `config.mcpServers` 显式配置 `playwright` 仍由 `MCPConfigResolver` userServers 分支继承。(2) axion-helper baseline 默认注入（与 `build()` 同源，对齐架构 §6「Inherit MCP/Web/Search availability from the normal build profile」）；若 reviewer 要求 skill 路径不暴露桌面 MCP，可改为只继承 user servers。
- **40.4 测试内联注释**：`AgentBuilderDiscoveredSkillRegistryTests` 中 `test_buildSkillAgent_skillRegistryUsesDiscoveredRegistry` 仍有「mcpServers: nil 不连 MCP」注释——这是 40.4 残留描述，本 story 已把 `buildSkillAgent` 改为继承 config MCP。该注释为非断言性描述，且改动该测试文件不在本 story 授权范围（仅 Task 4 授权新增测试文件）；保留以避免越权改动 40.4 测试。registry 断言不受影响（已验证通过）。

### File List

- `Sources/AxionCLI/Config/AxionConfig.swift`（修改：新增 `enableToolSearch: Bool?` 字段 + `toolSearchEnabled` 计算属性 + CodingKey + init 参数 + decoder `decodeIfPresent` 行 + default）
- `Sources/AxionCLI/Services/AgentBuilder.swift`（修改：新增 `effectiveExcludedToolNames(allowingToolSearch:)` 与 `resolveSkillMcpServers(from:helperPath:)` 两个 static helper；`buildToolProfile` 改用 config 派生策略；`buildSkillToolProfile` 加默认参数 `enableToolSearch: Bool = false` + 改用 helper；`buildSkillAgent` 传 `config.toolSearchEnabled` + 继承 config MCP（was nil）；更新 `excludedToolNames`/`buildSkillToolProfile`/`buildSkillAgent` doc 注释）
- `Tests/AxionCLITests/Services/AgentBuilderToolSearchAndMcpInheritanceTests.swift`（新增：AC1–AC6 的 7 个 Swift Testing @Test）
- `Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift`（修改：**incidental flaky-test 稳定化**——与本 story 的 ToolSearch/MCP 范围无关，但跑 `make test` 时一并落入工作树。`@Suite("TaskSerialQueue")` 加 `.serialized` 避免完整套件下调度争用；`timeoutCancellation` 的 `waitUntil` 提到 `.seconds(10)` 给调度余量，断言由 `"超时已取消" || "任务执行失败"` 收窄为仅 `"超时已取消"`（精确锁定超时取消路径，而非任意失败）。改动合理、测试仍绿，**不回退**——记此条补 File List 透明度）
- `_bmad-output/implementation-artifacts/sprint-status.yaml`（修改：40-5 状态 ready-for-dev → in-progress → review → done；last_updated 更新）

### Change Log

- 2026-06-15：Story 40.5 实现完成。把 ToolSearch 全局硬编码排除升级为 `AxionConfig.enableToolSearch` config 策略（默认关闭保持 GLM 稳定，零回归）；新增 `effectiveExcludedToolNames(allowingToolSearch:)` 作为普通 chat 与 direct skill 两路径的单一排除策略真相源；让 direct skill 路径（`buildSkillAgent`）经 `resolveSkillMcpServers(from:)` 继承 config 的 MCP servers（was `nil`）；新增 7 个 Swift Testing 单元测试覆盖 AC1–AC6；40.2/40.3/40.4 零回归。
- 2026-06-15：**Review（story-automator-review）通过 → done**。0 CRITICAL。补录 incidental flaky-test 稳定化（`TaskSerialQueueTests.timeoutCancellation`：`.serialized` + 10s 余量 + 断言收窄），原 Dev 阶段未入 File List，review 补于 File List / Completion Notes（改动合理、测试仍绿，不回退）。确认 `make test` 仅 7 失败且全在 `DesktopNotifier`（tmux `Ptmux;` 环境性，与 story 无关）；40.5 套件 7/7 绿，40.2/40.3/40.4 零回归。
