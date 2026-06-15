---
baseline_commit: 932a51328118dff963746ed65a82c8784fa32d4b
---

# Story 40.6: Permission, Allowlist, and Diagnostics Consistency

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a Claude Code skill / subagent compatibility user,
I want permission 决策（permission mode、session allowlist）与 tool-availability diagnostics 在 ordinary agent、direct skill agent、child agent 三条路径上**行为一致且可观察**,
so that workflow skill 不会绕过审批门（CAP-5），也不会静默吞掉「skill 声明的工具不可用」这类信号（CAP-8 / 棕地分析「Skill 工具限制当前状态」结论）。

**类型：** Feature / consistency-and-observability story。本 story 是 Epic 40 工具策略收口的**最后一块拼图**：SDK 0.10.0 已经在 SDK 侧实现 `allowed-tools` 的**无损解析**（`ToolDeclaration` / `ToolDeclarationDiagnostics`，SDK Story 29.4）、**统一过滤**（`filterToolsByDeclarations` → `(filtered, ToolFilterDiagnostics)`，SDK Story 29.5）以及**子代理继承 `canUseTool`/`permissionMode`**（`DefaultSubAgentSpawner.swift:218-219`）。Axion 侧剩余的不是「重新实现解析/过滤/权限」，而是**一致性 + 可观察性**：(1) 把 SDK 计算、但当前被丢弃 / 未展示的 tool-availability diagnostics（unmatched / unknown / pattern-not-enforced / config-disabled）在 Axion 输出中**显式可见**（AC1–AC3）；(2) 验证并锁定 permission mode + session allowlist 在 chat skill 执行（Path A）与 child agent 上的**非扩张继承**（AC4）；(3) 验证并锁定过滤顺序——`allowed-tools` 先收窄、再叠 session/permission policy（交集而非并集，AC5）。

本 story **不**改 `AgentBuilder.buildToolProfile` / `buildSkillToolProfile` 的工具集合（属 40.2/40.3/40.5）、**不**加 slash skill guidance 到 system prompt（属 40.7）、**不**改 child task 的 progress / failure / summary 输出格式（属 40.8）、**不**编辑 SDK `.build/checkouts/`（复用 SDK 已发布的 public pure helper）、**不**实现 filesystem subagent discovery / background / resume / isolation（架构 §7 deferred）。

## Acceptance Criteria

1. **AC1 — `diagnoseToolAvailability(...)` 纯函数 helper 产出结构化 availability diagnostics**
   **Given** 一个声明了 `allowed-tools` 的 `Skill`（其 `toolDeclarations` / `toolDeclarationDiagnostics` 已由 SDK `SkillLoader` 解析填充），与一个已组装的工具池名称列表（如 `buildSkillToolProfile(...)` 的输出工具名）
   **When** 调用 `AgentBuilder.diagnoseToolAvailability(skill:availableToolNames:enableToolSearch:)`（本 story 新增的纯函数 static helper，与 `effectiveExcludedToolNames` / `resolveSkillMcpServers` 并列）
   **Then** 返回的 `ToolAvailabilityDiagnostics`（本 story 新增 struct）**至少**包含四类字段：`unmatchedDeclarations`（声明的 allowed-tool 在可用池中无匹配，如未连接的 MCP 工具 `mcp__github__list_prs`、拼错的工具名）、`unsupportedDeclarations`（status == `.unknown` 的显式声明）、`patternDeclarations`（携带 `Bash(git diff:*)` 形式 pattern、parsed-but-not-enforced）、`configDisabledDeclarations`（声明的工具被当前 Axion config policy 禁用，如 `ToolSearch` 在 `enableToolSearch == false` 时）
   **And** helper 是**纯函数**：复用 SDK 已发布 public 符号（`OpenAgentSDK.ToolDeclaration`、`OpenAgentSDK.filterToolsByDeclarations`、`skill.toolDeclarations`、`skill.toolDeclarationDiagnostics`），**不** resolveApiKey、**不**连 MCP、**不**起 Helper 进程、**不**调真实 `AgentBuilder.build()`
   **And** helper 的诊断语义与 SDK `filterToolsByDeclarations` 运行时诊断**同源**——SDK `DefaultSubAgentSpawner.filterTools`（`DefaultSubAgentSpawner.swift:414-433`）已返回 `ToolFilterDiagnostics`，但 spawner boundary **丢弃**了它（`DefaultSubAgentSpawner.swift:151-156` 注释「we currently discard diagnostics at the spawner boundary」）；本 helper 在 Axion build/route 时刻用**同一份** pure logic 复算，使该信号可观察

2. **AC2 — 未知 / 不可用 allowed-tools 条目被显式诊断，绝不静默退化为「无限制」**
   **Given** skill 声明 `allowed-tools: Read, Grep, UnknownTool, mcp__github__list_prs`（其中 `UnknownTool` 是 SDK parse 时无法分类的 `.unknown`，`mcp__github__list_prs` 是当前未连接的 MCP 工具）
   **When** 调用 `diagnoseToolAvailability(skill:availableToolNames:["read","grep","bash","websearch",...], enableToolSearch:false)`
   **Then** 返回 diagnostics **非空**：`unsupportedDeclarations` 含 `UnknownTool`、`unmatchedDeclarations` 含 `mcp__github__list_prs`
   **And** 诊断**不**改变「该 skill 有 restriction」这一事实——即「全部未知 → 不退化为 nil/无限制」由 SDK `ToolDeclaration` 模型保证（`ToolDeclaration.swift` Dev Notes「`.unknown` is not the same as unrestricted」），本 helper 只是把它**显式带出**
   **And** 反向断言：一个**未声明** `allowed-tools` 的 skill（`toolDeclarations == nil`）调 helper 返回**空** diagnostics（区分「显式声明但不可用」与「根本无声明」）

3. **AC3 — config policy 冲突产生可观察诊断（接上 40.5 的 ToolSearch config 天花板）**
   **Given** skill 声明 `allowed-tools: Read, ToolSearch`，且 `AxionConfig.enableToolSearch == false`（40.5 默认，GLM 稳定）
   **When** 调用 `diagnoseToolAvailability(skill:availableToolNames:enableToolSearch:false)`
   **Then** `configDisabledDeclarations` **包含** `ToolSearch` 的声明（normalized name `"toolsearch"`）——明确告诉用户「skill 请求了 ToolSearch，但当前 config 关闭」
   **And** `enableToolSearch == true` 时，同样的 skill 调 helper，`configDisabledDeclarations` **不含** ToolSearch（config 已放行 → 不产生冲突诊断；若可用池仍无 ToolSearch，则落入 `unmatchedDeclarations` 而非 `configDisabledDeclarations`）
   **And** 这正闭合 SPEC Constraint（第 72 行）与架构 §3（第 102 行）：「skill/subagent 声明 ToolSearch 只是 opt-in request，不能覆盖用户 config」——本 helper 把「请求被 policy 拒绝」变成**可见信号**，而非静默丢失

4. **AC4 — permission mode + session allowlist 在 chat skill 执行（Path A）与 child agent 上非扩张继承**
   **Given** interactive chat REPL 已用 `PermissionHandler.resolveMode(...)` 计算 `permissionMode`、用 `PermissionHandler.createCanUseTool(mode:sessionAllowList:...)` 创建 `canUseTool`（`ChatCommand.swift:74-99`），并通过 `BuildConfig.forChat(permissionMode:canUseTool:)` 注入
   **When** 用户输入 `/skill-name args` 走 **Path A**（`state.buildResult.agent.executeSkillStream(...)`，`ChatCommand.swift:620`）——skill 在**已建好的 chat agent 上执行**，复用其 `agentOptions.canUseTool` / `permissionMode`
   **Then** Path A 的 skill 执行与该 session 的普通 chat turn **共享同一个 `canUseTool` 闭包 + `SessionAllowListRef`**——session allowlist 已批准的命令可继承，未批准的 write/side-effect 工具仍走审批门（AC1 of epic：session allowlist 只允许 `Read`/`Grep` → 不会继承 `Write`/`Edit`/`Bash`/side-effect MCP，它们在 `canUseTool` 处被拦截）
   **And** Task/Agent 子代理经 SDK `DefaultSubAgentSpawner` 继承**同一** `canUseTool` + `permissionMode`（`DefaultSubAgentSpawner.swift:218-219`：`permissionMode: mode ?? inheritanceContext.permissionMode ?? .default`、`canUseTool: inheritanceContext.canUseTool`）——child agent 不获得比父 session 更宽的权限
   **And** **已知且有意**：非交互路径 `buildSkillAgent`（Path B：API / `axion run` / daemon）使用 `permissionMode: .bypassPermissions` + `canUseTool: nil`（`AgentBuilder.swift:557`、`AgentBuilder+Config.swift:167-168` 的 `forSkillExecution`）——非交互无 TTY 无法逐项审批，bypass 是既定策略；本 story **不**改变它，但通过单元测试**锁定并文档化**该决策（见 AC6 的 `forSkillExecution` 断言）

5. **AC5 — 过滤顺序：`allowed-tools` 先收窄，再叠 session/permission policy（交集而非并集）**
   **Given** 一个声明 `allowed-tools: Read, Grep` 的只读 skill，与一个已组装工具池（含 `Read`、`Grep`、`Bash`、`Write`、`WebSearch` 等）
   **When** 调用 `AgentBuilder.effectiveSkillToolPool(skill:available:)`（本 story 新增的纯函数 static helper，薄封装 SDK `filterToolsByDeclarations(available:allowed:disallowed:)`）
   **Then** 返回的工具池**只含** `Read`、`Grep`（skill restriction 收窄生效，available 中其余工具被移除）——**交集**语义
   **And** 即便 session allowlist / `canUseTool` 允许更多工具（如 `Bash`），它们**也不**出现在 effective pool 中——因为 allowed-tools 收窄发生在 canUseTool 运行时门**之前**（架构 §3 第 104 行「filter the assembled pool after deduplication」）
   **And** 一个**未声明** `allowed-tools` 的 skill（`toolDeclarations == nil` 且 `toolRestrictions == nil`）调 `effectiveSkillToolPool` 返回**全部** `available`（无收窄）
   **And** session/permission policy 在**运行时**由 `canUseTool` 进一步门控（与 build-time 收窄正交）——本 AC 只断言 build-time 的 allowed-tools 收窄，运行时门控由 AC4 的 SDK 继承保证

6. **AC6 — 新增 Swift Testing 单元测试覆盖 AC1–AC5；`make test` 通过；40.2–40.5 零回归**
   **Given** AC1–AC5 的 helper / 断言已实现
   **When** 在 `Tests/AxionCLITests/Services/` 新增 Swift Testing 测试文件
   **Then** 测试覆盖：
     - **AC1**：声明 `allowed-tools` 的 fixture skill 调 `diagnoseToolAvailability`，断言四类字段存在且语义正确（构造 `Skill(name:..., toolDeclarations:[ToolDeclaration.parse("Read"), ...], ...)`，或经 `SkillLoader` 从临时目录解析真实 frontmatter——dev 二选一，优先直接构造 `ToolDeclaration` 做确定性）
     - **AC2**：`allowed-tools: Read, Grep, UnknownTool, mcp__github__list_prs` → `unsupportedDeclarations` 含 unknown、`unmatchedDeclarations` 含 MCP；未声明 allowed-tools 的 skill → 空 diagnostics
     - **AC3**：`allowed-tools: Read, ToolSearch` 在 `enableToolSearch:false` → `configDisabledDeclarations` 含 ToolSearch；`enableToolSearch:true` → 不含
     - **AC4**：`BuildConfig.forChat(permissionMode:canUseTool:)` 保留传入的 `permissionMode` + `canUseTool`（纯 struct 构造，可断言）；`BuildConfig.forSkillExecution(...)` 的 `.permissionMode == .bypassPermissions` 且 `.canUseTool == nil`（锁定 Path B 有意 bypass）
     - **AC5**：`effectiveSkillToolPool(skill: allowed [read,grep], available: [Read,Grep,Bash,Write])` → 仅 Read/Grep；未声明 restriction 的 skill → 全 available
   **And** 测试**不调用真实 `AgentBuilder.build()` / `buildSkillAgent()`**（会 resolveApiKey + 起 Helper + 真实 MCP resolve）；只调纯函数 helper（`diagnoseToolAvailability` / `effectiveSkillToolPool`）与纯 struct 构造（`BuildConfig.forChat` / `forSkillExecution`）
   **And** 工具名 / declaration 名**不硬编码字面量做期望**（反模式 #10）：期望名从 `createReadTool().name` / `createGrepTool().name` / `createBashTool().name` / `createWriteTool().name` 读取；`ToolDeclaration` 用 `ToolDeclaration.parse("Read")` / `.parse("ToolSearch")` 构造，不手写 normalizedName 字面量做比对
   **And** 执行 `make test`（**用户自定义指令**：统一 `make test`，等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`），全部通过；40.2 `AgentBuilderToolProfileTests`、40.3 `AgentBuilderSubagentToolRegistrationTests`、40.4 `AgentBuilderDiscoveredSkillRegistryTests`、40.5 `AgentBuilderToolSearchAndMcpInheritanceTests` **零回归**

> **ATDD 测试引用（RED 阶段将生成）**
> - 测试文件（建议）：`Tests/AxionCLITests/Services/AgentBuilderPermissionAndDiagnosticsConsistencyTests.swift`（Swift Testing，覆盖 AC1–AC6）
> - ATDD checklist（Step 2 生成）：`_bmad-output/test-artifacts/atdd-checklist-40-6-permission-allowlist-and-diagnostics-consistency.md`
> - 当前状态：待 Step 2 生成 RED 脚手架

## Tasks / Subtasks

- [x] **Task 1 — 新增 `ToolAvailabilityDiagnostics` struct + `diagnoseToolAvailability(...)` 纯函数 helper（AC1, AC2, AC3）**
  - [x] 1.1 在 `Sources/AxionCLI/Services/AgentBuilder.swift` 新增 `ToolAvailabilityDiagnostics` struct（与 `AxionConfig`/`AgentBuilder` 同模块，`Sendable` + `Equatable`，供测试与输出层共用）：
    ```swift
    /// Structured tool-availability diagnostics for a skill execution path (Story 40.6).
    ///
    /// Mirrors the diagnostics the SDK computes at runtime (`ToolFilterDiagnostics` /
    /// `ToolDeclarationDiagnostics`) but that `DefaultSubAgentSpawner` currently discards
    /// at the spawner boundary (SDK `DefaultSubAgentSpawner.swift:151-156`). This Axion-side
    /// recomputation runs at build/route time using SDK pure helpers, making the signal
    /// observable (CAP-8 / architecture §3 lines 104-105: unknown allowed-tools must not
    /// silently become unrestricted).
    public struct ToolAvailabilityDiagnostics: Sendable, Equatable {
        /// Allowed-tool declarations that matched NO available tool — e.g. an MCP tool that
        /// isn't connected (`mcp__github__list_prs`) or a typo'd name. These affect availability.
        public let unmatchedDeclarations: [OpenAgentSDK.ToolDeclaration]
        /// Explicitly-declared-but-unresolvable names (status == `.unknown`). The SDK parser
        /// still records these (non-nil) so the skill is never silently unrestricted.
        public let unsupportedDeclarations: [OpenAgentSDK.ToolDeclaration]
        /// Declarations carrying a `Bash(git diff:*)`-style pattern — parsed but NOT enforced
        /// (fine-grained Bash pattern enforcement is a deferred epic item). Surfaced so the user
        /// knows the pattern was accepted but not honored.
        public let patternDeclarations: [OpenAgentSDK.ToolDeclaration]
        /// Declarations requesting a tool the current Axion config policy disables — e.g.
        /// `ToolSearch` while `AxionConfig.enableToolSearch == false` (Story 40.5 config ceiling).
        public let configDisabledDeclarations: [OpenAgentSDK.ToolDeclaration]

        public init(
            unmatchedDeclarations: [OpenAgentSDK.ToolDeclaration] = [],
            unsupportedDeclarations: [OpenAgentSDK.ToolDeclaration] = [],
            patternDeclarations: [OpenAgentSDK.ToolDeclaration] = [],
            configDisabledDeclarations: [OpenAgentSDK.ToolDeclaration] = []
        ) {
            self.unmatchedDeclarations = unmatchedDeclarations
            self.unsupportedDeclarations = unsupportedDeclarations
            self.patternDeclarations = patternDeclarations
            self.configDisabledDeclarations = configDisabledDeclarations
        }

        /// `true` when no diagnostics of any kind were produced.
        public var isEmpty: Bool {
            unmatchedDeclarations.isEmpty && unsupportedDeclarations.isEmpty
                && patternDeclarations.isEmpty && configDisabledDeclarations.isEmpty
        }

        /// `true` when any diagnostic affects actual tool availability (unmatched / unknown /
        /// config-disabled). Pattern-only diagnostics are informational and do not by themselves
        /// remove a tool.
        public var affectsAvailability: Bool {
            !unmatchedDeclarations.isEmpty || !unsupportedDeclarations.isEmpty
                || !configDisabledDeclarations.isEmpty
        }
    }
    ```
  - [x] 1.2 在 `AgentBuilder` 新增 static helper（与 `effectiveExcludedToolNames` / `resolveSkillMcpServers` / `buildSkillToolProfile` 并列的「pure-ish helper」族，沿用 40.4 `makeDiscoveredSkillRegistry` / 40.5 `resolveSkillMcpServers` 的注入 seam 风格）：
    ```swift
    /// Computes tool-availability diagnostics for a skill's `allowed-tools` against an assembled
    /// tool pool + Axion config policy (Story 40.6).
    ///
    /// Reuses SDK pure helpers (`OpenAgentSDK.filterToolsByDeclarations`, `skill.toolDeclarations`,
    /// `skill.toolDeclarationDiagnostics`) — no SDK edits, no live model, no MCP connection, no API
    /// key resolution. The SDK computes equivalent diagnostics at runtime, but
    /// `DefaultSubAgentSpawner` discards the `ToolFilterDiagnostics` it returns (SDK
    /// `DefaultSubAgentSpawner.swift:151-156`); this helper mirrors that logic at Axion build/route
    /// time so the signal is observable (CAP-8).
    ///
    /// `enableToolSearch` is the SAME `AxionConfig.toolSearchEnabled` value that governs tool-pool
    /// assembly (Story 40.5), so a skill requesting ToolSearch under a disabled policy surfaces as
    /// `configDisabledDeclarations` rather than being silently dropped.
    ///
    /// - Parameters:
    ///   - skill: The skill whose `allowed-tools` (via `toolDeclarations` / `toolDeclarationDiagnostics`)
    ///     is being diagnosed. A skill with `toolDeclarations == nil` (no `allowed-tools` frontmatter)
    ///     yields empty diagnostics.
    ///   - availableToolNames: Lowercased names of the assembled tool pool (e.g. from
    ///     `buildSkillToolProfile(...).map { $0.name.lowercased() }`).
    ///   - enableToolSearch: Whether Axion config currently enables ToolSearch.
    /// - Returns: A `ToolAvailabilityDiagnostics` describing unmatched / unsupported / pattern /
    ///   config-disabled declarations.
    static func diagnoseToolAvailability(
        skill: OpenAgentSDK.Skill,
        availableToolNames: [String],
        enableToolSearch: Bool
    ) -> ToolAvailabilityDiagnostics {
        guard let declarations = skill.toolDeclarations, !declarations.isEmpty else {
            return ToolAvailabilityDiagnostics()  // no allowed-tools → no diagnostics
        }
        let availableLower = Set(availableToolNames.map { $0.lowercased() })

        // 1. unsupported (.unknown) — from parse-time diagnostics (SDK Story 29.4)
        let unsupported = skill.toolDeclarationDiagnostics?.unsupportedDeclarations
            ?? declarations.filter { $0.status == .unknown }

        // 2. pattern (parsed-not-enforced) — from parse-time diagnostics
        let patterns = skill.toolDeclarationDiagnostics?.patternDeclarations
            ?? declarations.filter { $0.pattern != nil }

        // 3. unmatched — allowed declaration whose normalizedName is not in the available pool.
        //    (Mirrors SDK `filterToolsByDeclarations` → `ToolFilterDiagnostics.unmatchedDeclarations`.)
        let unmatched = declarations.filter { !availableLower.contains($0.normalizedName) }

        // 4. config-disabled — currently only ToolSearch is config-gated (Story 40.5). A declaration
        //    requesting a tool that config policy disables (here: ToolSearch when enableToolSearch
        //    is false) is separated from generic `unmatched` so the user sees the *policy* reason.
        let configDisabled: [OpenAgentSDK.ToolDeclaration]
        if enableToolSearch {
            configDisabled = []
        } else {
            let toolSearchName = OpenAgentSDK.ToolRestriction.toolSearch.rawValue  // "toolsearch"
            configDisabled = declarations.filter { $0.normalizedName == toolSearchName }
        }

        return ToolAvailabilityDiagnostics(
            unmatchedDeclarations: unmatched,
            unsupportedDeclarations: unsupported,
            patternDeclarations: patterns,
            configDisabledDeclarations: configDisabled
        )
    }
    ```
  - [x] 1.3 **可测性取舍**：helper 接受**已组装池的名称列表**（`[String]`）而非 `[ToolProtocol]`，使测试可直接传入 `["read","grep","bash",...]` 而无需构造真实 `ToolProtocol` 实例（避免任何副作用）。生产调用点从 `buildSkillToolProfile(...).map { $0.name.lowercased() }` 取名
  - [x] 1.4 **不**在该 helper 内 emit 任何输出——纯计算，副作用归 Task 2/3 的 wiring 点。`affectsAvailability` 计算属性供 wiring 点决定「warning vs informational」

- [x] **Task 2 — `effectiveSkillToolPool(...)` 纯函数 helper（AC5 过滤顺序）**
  - [x] 2.1 在 `AgentBuilder` 新增 static helper（薄封装 SDK `filterToolsByDeclarations`，暴露交集语义供测试）：
    ```swift
    /// The effective tool pool after applying a skill's `allowed-tools` to the assembled pool
    /// (Story 40.6 AC5 — filtering order: allowed-tools narrow FIRST, then session/permission
    /// policy gates at runtime).
    ///
    /// Thin wrapper over SDK `filterToolsByDeclarations(available:allowed:disallowed:)` that
    /// surfaces the build-time intersection for testability. Returns all `available` when the
    /// skill declares no restrictions (`toolDeclarations` nil/empty AND `toolRestrictions`
    /// nil/empty). The runtime `canUseTool` gate (inherited by child agents, AC4) further
    /// restricts on top of this — orthogonal, not duplicated here.
    static func effectiveSkillToolPool(
        skill: OpenAgentSDK.Skill,
        available: [OpenAgentSDK.ToolProtocol]
    ) -> [OpenAgentSDK.ToolProtocol] {
        let declarations = skill.toolDeclarations?.isEmpty == false ? skill.toolDeclarations : nil
        // If no lossless declarations but legacy toolRestrictions exist, normalize them via
        // ToolDeclaration.fromToolNames so both forms share one filter path (SDK Story 29.5 unification).
        let allowed = declarations
            ?? skill.toolRestrictions.map { OpenAgentSDK.ToolDeclaration.fromToolNames($0.map(\.rawValue)) }
        guard let allowed, !allowed.isEmpty else { return available }
        let (filtered, _) = OpenAgentSDK.filterToolsByDeclarations(
            available: available, allowed: allowed, disallowed: nil
        )
        return filtered
    }
    ```
  - [x] 2.2 **不**在 `buildSkillAgent` / `buildToolProfile` 内改用它替换既有过滤（SDK `executeSkillStream` 已在运行时应用 `toolDeclarations`，见 `Agent.swift:1289-1302`/`1369-1379`；本 helper 只是**测试 + 可观察**的镜像，不重复运行时过滤）

- [x] **Task 3 — wiring：在 `buildSkillAgent`（Path B）emit availability diagnostics warning（AC1–AC3 的可观察出口）**
  - [x] 3.1 在 `buildSkillAgent`（`AgentBuilder.swift:525-576`）组装完 `tools`（`:544`）后、构造 `agentOptions`（`:550`）前，插入诊断计算 + warning emit：
    ```swift
    // Story 40.6: surface tool-availability diagnostics so a skill requesting an unavailable tool
    // (unknown name, unconnected MCP, config-disabled ToolSearch) is visible instead of silently
    // lost. Mirrors the SDK diagnostics that DefaultSubAgentSpawner discards at its boundary.
    let diag = diagnoseToolAvailability(
        skill: skill,
        availableToolNames: tools.map { $0.name.lowercased() },
        enableToolSearch: config.toolSearchEnabled
    )
    if diag.affectsAvailability {
        fputs("[axion] ⚠️ skill \"\(skill.name)\" 声明的部分工具当前不可用:\n", stderr)
        for d in diag.unmatchedDeclarations where d.status != .unknown {
            fputs("[axion]   - 未匹配: \(d.rawName)\n", stderr)
        }
        for d in diag.unsupportedDeclarations {
            fputs("[axion]   - 未知工具名: \(d.rawName)\n", stderr)
        }
        for d in diag.configDisabledDeclarations {
            fputs("[axion]   - 被 config 策略禁用: \(d.rawName)\n", stderr)
        }
    }
    if !diag.patternDeclarations.isEmpty {
        fputs("[axion] ℹ️ skill \"\(skill.name)\" 声明了 pattern 限制（已解析，暂不强制）:\n", stderr)
        for d in diag.patternDeclarations {
            fputs("[axion]   - \(d.rawName)\n", stderr)
        }
    }
    ```
  - [x] 3.2 **warning 不受 `verbose` 门控**：`affectsAvailability` 的诊断（unmatched/unknown/config-disabled）**始终** emit 到 stderr（epic 实施步骤 5：「影响 tool availability，应显示为 warning」）；pattern-only 的 informational 诊断也 emit（属「parsed but not enforced」的可观察信号），但用 ℹ️ 区分级别
  - [x] 3.3 **不改 `buildSkillAgent` 签名**（沿用 40.4/40.5 的最小爆炸半径约束）；诊断在函数体内，调用方（`AxionRuntime.executeSkill`、`AgentBuilding` protocol、`DefaultAgentBuilder`、Mock、E2E）**零改动**
  - [x] 3.4 **Path A（interactive chat）wiring**（可选但推荐，闭合 BMAD pipeline 主场景）：在 `ChatCommand` 的 skill 执行分支（`ChatCommand.swift:576-624`，`messageStream = state.buildResult.agent.executeSkillStream(...)` 之前），从 registry 解析匹配的 `Skill` 对象，调 `AgentBuilder.diagnoseToolAvailability(skill:availableToolNames: state.buildResult 的 chat 工具池名, enableToolSearch: config.toolSearchEnabled)`，若 `affectsAvailability` 则同款 stderr warning。dev 决定具体 seam（registry lookup 已在 `ChatCommandInputRouter.resolveSkillName` 附近可用）；若 Path A wiring 风险过大，可只在 Dev Notes 标注「Path A 复用同一 helper，wiring 作为 follow-up」，但 **AC1–AC3 的 helper 测试不依赖 wiring**

- [x] **Task 4 — 新增单元测试（AC6, AC1–AC5）**
  - [x] 4.1 新增 `Tests/AxionCLITests/Services/AgentBuilderPermissionAndDiagnosticsConsistencyTests.swift`，使用 **Swift Testing**（`import Testing`、`@Suite`、`@Test`、`#expect`），**禁止 `import XCTest`**
  - [x] 4.2 沿用 40.5 测试的 helper 模式（`makeTempBase()`/`cleanup()`/`makeConfig()`、`AxionConfig(apiKey:"sk-test")`、工具名从真实实例 `.name` 读取、`import OpenAgentSDK` 取 `ToolDeclaration`/`ToolRestriction`）。`@Suite("AgentBuilder permission & diagnostics consistency (Story 40.6)")` 包含以下 `@Test`：
    - [x] 4.2.1 `test_diagnoseToolAvailability_unmatchedAndUnknownSurface` — **AC1+AC2**。构造 `Skill(name:"s", toolDeclarations:[.parse("Read"), .parse("Grep"), .parse("UnknownTool"), .parse("mcp__github__list_prs")], ...)`，调 `diagnoseToolAvailability(skill:availableToolNames:[createReadTool().name.lowercased(), createGrepTool().name.lowercased(), createBashTool().name.lowercased()], enableToolSearch:false)`。断言 `unsupportedDeclarations` 含 `UnknownTool`（rawName）、`unmatchedDeclarations` 含 `mcp__github__list_prs`
    - [x] 4.2.2 `test_diagnoseToolAvailability_noDeclarationsYieldsEmpty` — **AC2 反向**。构造 `Skill(name:"s", promptTemplate:"")`（无 toolDeclarations），调 helper → 断言 `diag.isEmpty == true`（区分「无声明」与「声明但不可用」）
    - [x] 4.2.3 `test_diagnoseToolAvailability_toolSearchConfigConflict` — **AC3**。`Skill(toolDeclarations:[.parse("Read"), .parse("ToolSearch")])`：(a) `enableToolSearch:false` → `configDisabledDeclarations` 含 ToolSearch（normalizedName `"toolsearch"`）；(b) `enableToolSearch:true` → `configDisabledDeclarations` 不含 ToolSearch
    - [x] 4.2.4 `test_diagnoseToolAvailability_patternDeclarationsParsedNotEnforced` — **AC1 pattern**。`Skill(toolDeclarations:[.parse("Bash(git diff:*)")])` → `patternDeclarations` 含该声明（`pattern == "git diff:*"`）
    - [x] 4.2.5 `test_forChat_preservesPermission_forSkillExecutionBypasses` — **AC4**。纯 struct 断言：`BuildConfig.forChat(config:makeConfig(), permissionMode:.acceptEdits, canUseTool:{_,_,_ in .allow()})` → `.permissionMode == .acceptEdits`、`.canUseTool != nil`；`BuildConfig.forSkillExecution(config:makeConfig(), skill:<fixture>)` → `.permissionMode == .bypassPermissions`、`.canUseTool == nil`（锁定 Path B 有意 bypass）
    - [x] 4.2.6 `test_effectiveSkillToolPool_restrictionsNarrowToIntersection` — **AC5**。`Skill(toolDeclarations:[.parse("Read"), .parse("Grep")])`，`available:[createReadTool(), createGrepTool(), createBashTool(), createWriteTool()]` → `effectiveSkillToolPool` 返回仅 Read/Grep（按名匹配，断言工具名集合 == {read,grep}）
    - [x] 4.2.7 `test_effectiveSkillToolPool_noRestrictionsReturnsAll` — **AC5 反向**。`Skill(name:"s", promptTemplate:"")`（无 restriction）→ `effectiveSkillToolPool(skill:available:pool)` 返回全部 `pool`
  - [x] 4.3 Mock 约束：**禁止**调真实 `AgentBuilder.build()` / `buildSkillAgent()`（会 resolveApiKey + Helper + MCP）；只调纯函数 helper（`diagnoseToolAvailability` / `effectiveSkillToolPool`）+ 纯 struct 构造（`BuildConfig.forChat` / `forSkillExecution`）+ 直接构造 `Skill`/`ToolDeclaration`；**禁止 `import XCTest`**；`ToolDeclaration` 用 `.parse(...)` 构造，期望名从真实工具实例 `.name` 读取（反模式 #10）
  - [x] 4.3.1 **`Skill` 构造注意**：`Skill.init` 的 `promptTemplate: String` **必填无默认**——测试构造 fixture skill 时一律传 `promptTemplate: ""`（如 `Skill(name:"s", promptTemplate:"", toolDeclarations:[.parse("Read"), ...])`）。程序化构造的 `Skill`（不经 `SkillLoader`）其 `toolDeclarationDiagnostics` 为 `nil`——`diagnoseToolAvailability` 内已用 `?? declarations.filter { ... }` 回退，故程序化构造的 `Skill` 仍能正确产出 `unsupported`/`pattern` 诊断（无需手动填 `toolDeclarationDiagnostics`）
  - [x] 4.4 测试命名遵循 `test_被测单元_场景_预期结果`

- [x] **Task 5 — 运行默认单元测试，确认零回归（AC6）**
  - [x] 5.1 执行项目 Makefile 的 `test` 目标（**用户自定义指令**：统一用 `make test`，**不要** `swift test --filter ...`）：
    ```bash
    make test
    ```
    （等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`，全部单元测试）
  - [x] 5.2 全部通过（既有测试零回归 + 新 permission/diagnostics 测试转绿）。**特别关注**：
    - 40.5 `AgentBuilderToolSearchAndMcpInheritanceTests`（7 @Test）：本 story 给 `buildSkillAgent` 加诊断 emit（Task 3.1）——该 emit 走 stderr、无返回值改动、不触碰 ToolSearch/MCP helper → 40.5 的 `buildSkillToolProfile` / `resolveSkillMcpServers` 断言不受影响 → ✅ 不破
    - 40.4 `AgentBuilderDiscoveredSkillRegistryTests`（6 @Test）：调真实 `buildSkillAgent`，本 story Task 3 在其中插入诊断计算（`diagnoseToolAvailability` 是纯函数，无副作用）+ stderr emit → registry 断言不受影响，stderr emit 不影响测试断言 → ✅ 不破（注意：若 CI 捕获 stderr 使测试输出噪音增加，不影响 pass/fail）
    - 40.2 `AgentBuilderToolProfileTests`（7 @Test）/ 40.3 `AgentBuilderSubagentToolRegistrationTests`（5 @Test）：本 story **不**改 `buildToolProfile`/`buildSkillToolProfile` 工具集合（只新增 helper + wiring）→ ✅ 不破
  - [x] 5.3 **不运行** `Tests/**/Integration/`、`Tests/**/AxionE2ETests/`。若本会话在 tmux 内（`TMUX` 环境变量存在），`DesktopNotifier` 套件可能因 OSC 9/DCS passthrough 环境性失败（40.5 Debug Log 已记录）——属环境性，非本 story 引入、非回归

## Dev Notes

### 本 Story 的核心：SDK 已做完重活，Axion 只缺「一致性 + 可观察性」

Epic 40 的工具策略经历了 40.2（parity helper）→ 40.3（注册 Skill/Agent/Task）→ 40.4（discovered registry）→ 40.5（ToolSearch config + MCP 继承）。到 40.5 时，**工具池组装**已对齐 chat/skill 两路径。但 SPEC CAP-8 与架构 §3 还剩两条**可观察性 + 一致性**缺口，正是 40.6 的范围：

| 缺口 | 40.6 前状态 | 问题 | 本 story 改动 |
|------|------------|------|--------------|
| **tool-availability diagnostics 不可见** | SDK 计算 `ToolFilterDiagnostics`（runtime）+ `ToolDeclarationDiagnostics`（parse-time），但 `DefaultSubAgentSpawner` 在 boundary **丢弃** runtime 诊断（`DefaultSubAgentSpawner.swift:151-156`）；Axion 侧**完全不展示**任何诊断 | 一个声明 `allowed-tools: WebSearch, mcp__github__list_prs, ToolSearch` 的 skill，当 WebSearch 在池、MCP 未连、ToolSearch 被 config 关时，用户**看不到**后两者被丢——「不静默放权」红线未闭合 | 新增 `diagnoseToolAvailability(...)` 纯 helper（复用 SDK pure 符号），在 `buildSkillAgent`（+ 可选 chat Path A）emit warning（Task 1/3） |
| **permission 一致性未锁定** | Path A（chat skill 执行）复用 chat agent 的 `canUseTool`/`permissionMode`（已对）；child agent 经 SDK spawner 继承（`DefaultSubAgentSpawner.swift:218-219`，已对）；但**无测试锁定**，且 `forSkillExecution`/`buildSkillAgent` 的 `.bypassPermissions` 未被文档化为有意决策 | 未来 refactor 可能误改继承链或误把 bypass 当 bug 修掉 | AC4 + Task 4.2.5 用纯 struct 断言锁定 `forChat` 保留 permission、`forSkillExecution` 有意 bypass |
| **过滤顺序未锁定** | SDK `executeSkillStream` 在运行时用 `filterToolsByDeclarations` 收窄（`Agent.swift:1289-1302`）；canUseTool 运行时再门控——顺序**已对**，但**无测试** | 无 | AC5 + Task 2/4.2.6–4.2.7 用 `effectiveSkillToolPool` 纯 helper 锁定「allowed-tools 收窄 → 交集」 |

**关键事实**（来自 SDK 0.10.0 代码核实，HEAD `932a513`、SDK commit `4285aac`）：
- `OpenAgentSDK.ToolDeclaration` / `ToolDeclarationStatus` / `ToolDeclarationDiagnostics` / `ToolFilterDiagnostics` / `filterToolsByDeclarations(...)` 全部 **public 且经 `OpenAgentSDK.swift:128-132` re-export**——Axion `import OpenAgentSDK` 即可用，**无需编辑 `.build/checkouts/`**
- `Skill.toolDeclarations` / `Skill.toolDeclarationDiagnostics` 已由 SDK `SkillLoader` 解析填充（SDK Story 29.4）
- `Agent.executeSkill` / `executeSkillStream` **优先用 `toolDeclarations`**（lossless 路径），仅对无 declaration 的旧 skill 回退 `toolRestrictions`（`Agent.swift:1289-1302`、`:1369-1379`）
- `DefaultSubAgentSpawner.filterTools`（`:414-433`）用 `ToolDeclaration.fromToolNames` + `filterToolsByDeclarations` + 剥离 subagent launcher，但**丢弃**返回的 `ToolFilterDiagnostics`（`:151-156` 注释明确「we currently discard diagnostics at the spawner boundary」）——这就是 Axion 必须自己复算的诊断缺口

### 为什么 helper 接受 `[String]` 而非 `[ToolProtocol]`（可测性）

`diagnoseToolAvailability` 的 `availableToolNames: [String]` 让测试直接传 `["read","grep","bash"]`，无需构造 `ToolProtocol` 实例（避免任何工具实例化的副作用风险）。生产调用点从 `buildSkillToolProfile(...).map { $0.name.lowercased() }` 取名——`buildSkillToolProfile` 已是 40.3 的纯 helper。这与 40.4 `makeDiscoveredSkillRegistry` / 40.5 `resolveSkillMcpServers` 的「注入 seam」哲学一致：纯函数 + 可注入输入 = 全确定性测试。

`effectiveSkillToolPool` 则接受 `[ToolProtocol]`（薄封装 `filterToolsByDeclarations`，后者签名要求 `[ToolProtocol]`）；测试用 `createReadTool()`/`createGrepTool()`/`createBashTool()`/`createWriteTool()` 构造——这些 SDK 工厂是 side-effect-free 的纯构造（40.5 测试已验证可安全调用）。

### 为什么不复用 SDK 运行时诊断而要复算

SDK 在 agent **运行时**（`executeSkillStream` / spawner）计算诊断，但：
1. `DefaultSubAgentSpawner` **丢弃** runtime `ToolFilterDiagnostics`——Axion 拿不到
2. `executeSkillStream` 的诊断在 SDK 内部，**不**经 `SDKMessage` 暴露给 Axion 输出层（`SDKTerminalOutputHandler`/`SDKJSONOutputHandler` 不消费它）

Axion 要展示诊断，有两条路：(a) 编辑 SDK 让它经 `SDKMessage` 回传（违反「不编辑 `.build/checkouts/`」+ Epic 40 非目标「不在 Axion 实现 SDK Epic 29 公共 runtime 能力」）；(b) 在 Axion **build/route 时刻用同一份 pure logic 复算**（`filterToolsByDeclarations` + `toolDeclarations` 都是 public pure 函数）。本 story 选 (b)：零 SDK 改动、全可测、语义与 SDK 同源（同样的 lowercased base-name 匹配规则）。

### permission 继承链（AC4）的完整说明

三条路径的 permission 行为：

| 路径 | 入口 | permissionMode / canUseTool 来源 | 是否经审批门 |
|------|------|--------------------------------|------------|
| **Path A — chat skill 执行** | `ChatCommand.swift:620` `state.buildResult.agent.executeSkillStream(...)` | 复用**已建好的 chat agent** 的 `agentOptions.canUseTool`/`permissionMode`（`forChat` 注入，`ChatCommand.swift:93-119`） | ✅ 是（与普通 chat turn 同一个 `canUseTool` + `SessionAllowListRef`） |
| **Path A child agent**（Task/Agent 子代理） | SDK `DefaultSubAgentSpawner` | 继承父（chat agent）的 `canUseTool`/`permissionMode`（`DefaultSubAgentSpawner.swift:218-219`） | ✅ 是（SDK 继承，child 不比父宽） |
| **Path B — 非 interactive skill 执行** | `AxionRuntime.executeSkill` → `buildSkillAgent`（API/run/daemon） | `forSkillExecution` → `.bypassPermissions` + `canUseTool: nil`（`AgentBuilder.swift:557`、`AgentBuilder+Config.swift:167-168`） | ❌ 否（无 TTY，无法逐项审批；bypass 是既定策略） |

AC4 锁定的事实：
- Path A 的 skill 执行**不另建 agent**，直接在 chat agent 上跑 → 自动继承 chat 的 permission 上下文 → session allowlist 非扩张（已对，Task 4.2.5 用 `forChat` struct 断言锁定 permission 透传）
- child agent 经 SDK spawner 继承（已对，dev 在 Dev Notes 引用 `DefaultSubAgentSpawner.swift:218-219` 为证，**不**单测 spawner——那需跑真实 SDK runtime）
- Path B bypass 是**有意**（非 interactive），Task 4.2.5 用 `forSkillExecution` struct 断言锁定，防未来误改

**session allowlist 语义澄清**：`SessionAllowListRef`（`ChatCommand.swift:81`）是 `canUseTool` 的**运行时审批缓存**（已批准命令免再问），**不是** build-time 池收窄机制。架构 §State and Permissions 明确「Session allowlist inheritance should follow current canUseTool callback behavior」——故 epic AC1「session allowlist 只允许 Read/Grep → 不继承 Write/Edit/Bash」指的是**运行时门**：那些工具在 `canUseTool` 处被拦截（未批准 → 提示/拒绝），而非从池中移除。本 AC 不引入新的池收窄 allowlist 概念。

### 过滤顺序（AC5）：build-time 收窄 ⊥ runtime 门控

两套过滤**正交**（与 40.5 的 ToolSearch/dry-run 正交性同构）：

1. **build-time 收窄**（`effectiveSkillToolPool` / SDK `executeSkillStream`）：`filterToolsByDeclarations(assembled, skill.toolDeclarations)` → 只留 allowed 声明匹配的工具。这是**交集**（allowed ∩ assembled）。
2. **runtime 门控**（`canUseTool`）：对池中每个工具的实际调用做审批。这是**叠加在已收窄池上**的进一步限制。

顺序：build-time 收窄**先**（决定池里有什么），runtime 门控**后**（决定池里的工具能否被调用）。AC5 只断言 build-time 收窄的交集语义（Task 2/4.2.6–4.2.7）；runtime 门控由 AC4 的 SDK 继承保证。

### 为什么 `configDisabledDeclarations` 目前只覆盖 ToolSearch

当前 Axion config 唯一**主动禁用**工具的策略是 `enableToolSearch`（40.5）。MCP 工具的可用性由「是否连接」决定（落入 `unmatched`），Web 工具恒在 `.core` tier（不属 config 禁用）。故 `configDisabled` 的具体实例就是 ToolSearch。struct 字段保持通用（`configDisabledDeclarations: [ToolDeclaration]`），未来若加 `enableWeb`/`disableSkill` 等 config 策略，只需扩展 helper 内的判定，不改 struct 形状。dev 在 Dev Notes 标注此扩展点。

### 范围控制总结（防止 scope creep）

| 内容 | 本 story 做？ | 归属 |
|------|--------------|------|
| `ToolAvailabilityDiagnostics` struct | ✅ | 40.6 |
| `diagnoseToolAvailability(...)` 纯 helper | ✅ | 40.6 |
| `effectiveSkillToolPool(...)` 纯 helper（AC5 锁定） | ✅ | 40.6 |
| `buildSkillAgent`（Path B）emit diagnostics warning | ✅ | 40.6 |
| chat Path A emit diagnostics warning（可选 wiring） | ✅（推荐，复用同 helper） | 40.6 |
| AC4/AC5 单元测试（纯 struct + 纯 helper 断言） | ✅ | 40.6 |
| 改 `buildToolProfile`/`buildSkillToolProfile` 工具集合 | ❌ | 40.2/40.3/40.5（已完成） |
| slash skill guidance 到 system prompt | ❌ | 40.7 |
| child task progress/failure/summary 输出格式 | ❌ | 40.8 |
| 改 SDK `.build/checkouts/`（让 spawner 不丢弃诊断 / 经 SDKMessage 回传） | ❌ | SDK follow-up（Epic 40 非目标） |
| filesystem subagent discovery / background / resume / isolation | ❌ | 架构 §7 deferred |
| 改 `forSkillExecution`/`buildSkillAgent` 的 `.bypassPermissions` | ❌（有意，AC4 锁定） | — |
| 改 `buildSkillAgent` 签名 | ❌（最小爆炸半径） | — |
| 单测 SDK `DefaultSubAgentSpawner` 继承 | ❌（需真实 runtime；Dev Notes 引用代码为证） | — |
| E2E（真实 pipeline diagnostics 可见性） | ❌（E2E 范围，40.9/40.10） | follow-up |

### 反模式红线（CLAUDE.md 强制）

- ❌ **测试中硬编码工具名字面量做期望**（反模式 #10）：`createReadTool().name`/`createGrepTool().name`/`createBashTool().name`/`createWriteTool().name` 从真实实例读取；`ToolDeclaration` 用 `.parse("Read")`/`.parse("ToolSearch")`/`.parse("Bash(git diff:*)")` 构造，不手写 `normalizedName` 字面量做比对；`ToolRestriction.toolSearch.rawValue` 从枚举读取（不写字面量 `"toolsearch"`）
- ❌ **在测试中调真实 `AgentBuilder.build()` / `buildSkillAgent()`**：会 resolveApiKey + Helper + MCP。测试只调纯函数 helper（`diagnoseToolAvailability` / `effectiveSkillToolPool`）+ 纯 struct 构造（`BuildConfig.forChat` / `forSkillExecution`）+ 直接构造 `Skill`/`ToolDeclaration`
- ❌ **用 `import XCTest`**：`grep -rl "import XCTest" Tests/` 应返回空
- ❌ **编辑 SDK `.build/checkouts/`**：本 story 复用 SDK 已发布 public 符号（`ToolDeclaration`/`filterToolsByDeclarations`/`ToolDeclarationDiagnostics`）；diagnostics 复算在 Axion 侧（Task 1.2），不改 SDK
- ❌ **改 `buildSkillAgent` 签名**：诊断计算 + emit 在函数体内（Task 3.3），波及 protocol/Mock/E2E
- ❌ **改 `buildToolProfile`/`buildSkillToolProfile` 工具集合**：属 40.2/40.3/40.5；本 story 只新增 helper + wiring
- ❌ **把 Path B 的 `.bypassPermissions` 当 bug 修**：AC4 锁定它是有意的非交互策略
- ❌ **diagnostics 被 verbose 门控吞掉**：`affectsAvailability` 的诊断**始终** emit（epic 实施步骤 5）

### Project Structure Notes

- `Sources/AxionCLI/Services/AgentBuilder.swift`（修改：新增 `ToolAvailabilityDiagnostics` struct + `diagnoseToolAvailability(...)` 与 `effectiveSkillToolPool(...)` 两个 static helper；`buildSkillAgent`（`:544` 后）插入诊断计算 + stderr warning emit）
- `Sources/AxionCLI/Commands/ChatCommand.swift`（**可选**修改：skill 执行分支 `:576-624` 调 `diagnoseToolAvailability` emit Path A warning——dev 评估 seam 风险后决定；不强制）
- `Tests/AxionCLITests/Services/AgentBuilderPermissionAndDiagnosticsConsistencyTests.swift`（新增：AC1–AC6 的 Swift Testing @Test）
- **不碰** `Sources/AxionCLI/Services/AgentBuilder+Config.swift`（`forSkillExecution`/`forChat` 已正确；AC4 只读取断言）、`Sources/AxionCLI/Services/AgentBuilder+PromptBuilding.swift`（slash guidance 属 40.7）、`Sources/AxionCLI/Chat/PermissionHandler.swift`（permission 逻辑已对）、`Sources/AxionCLI/Chat/ChatCommand+SessionManagement.swift`（session allowlist 已对）、`Sources/AxionCLI/Config/AxionConfig.swift`（`enableToolSearch`/`toolSearchEnabled` 属 40.5，复用不改）、SDK `.build/checkouts/`
- 新文件归属 `AxionCLITests` testTarget，被 `make test`（等价 `--skip` 集成/E2E）命中

### References

- Epic：`docs/epics/epic-40-claude-code-skill-subagent-compat.md`
  - Story 40.6 章节（Permission, Allowlist, and Diagnostics Consistency，`:298-324`）——本 story AC 直接对应 epic 的 AC1（session allowlist 非扩张）/AC2（diagnostics 可见）/AC3（过滤顺序）
  - Story 间依赖（40.5 → **40.6** → 40.7 → ...；40.6 依赖 40.5 的 `toolSearchEnabled`/`resolveSkillMcpServers` + 40.2/40.3 的 `buildToolProfile`/`buildSkillToolProfile`）
  - CAP-5（dry-run/permission/no-skills 一致）、CAP-8（工具可见性不被静默缩窄、未知工具产生诊断）
  - 默认测试策略（`make test`，`:483-491`）
- 前置 Story：
  - `_bmad-output/implementation-artifacts/40-5-mcp-web-search-tool-inheritance-policy.md`（已 done；`AxionConfig.enableToolSearch`/`toolSearchEnabled` + `effectiveExcludedToolNames(allowingToolSearch:)`——本 story 的 `configDisabledDeclarations` 复用 `toolSearchEnabled`；40.5 Dev Notes 第 290-291 行明确「allowed-tools 解析 / MCP namespaced 过滤 / 未知工具诊断 → 40.6」）
  - `_bmad-output/implementation-artifacts/40-3-register-agent-task-skill-across-agent-paths.md`（已 done；`buildSkillToolProfile(registry:enableToolSearch:)`——本 story `diagnoseToolAvailability` 从其输出取名）
  - `_bmad-output/implementation-artifacts/40-2-shared-tool-profile-helper-with-behavior-parity.md`（已 done；`buildToolProfile` parity——本 story 不改其集合）
- 代码事实（HEAD `932a513`，Axion 侧）：
  - `Sources/AxionCLI/Services/AgentBuilder.swift:38-40`（`excludedToolNames`）、`:50`（`dryrunExcludedToolNames`）、`:225-237`（`build()` 注入 `canUseTool`）、`:435`（`buildSkillToolProfile`）、`:502`（`resolveSkillMcpServers`）、`:525-576`（`buildSkillAgent`；`:544` 工具组装、`:557` `.bypassPermissions`、`:562` MCP 继承——本 story 在 `:544` 后插诊断、不改其余）
  - `Sources/AxionCLI/Services/AgentBuilder+Config.swift:80-112`（`forChat` 透传 permissionMode/canUseTool）、`:144-171`（`forSkillExecution` → `.bypassPermissions` + `canUseTool:nil`）
  - `Sources/AxionCLI/Chat/PermissionHandler.swift:56-152`（`createCanUseTool(mode:sessionAllowList:...)`——session allowlist 运行时缓存语义）
  - `Sources/AxionCLI/Commands/ChatCommand.swift:74-119`（permissionMode/canUseTool/sessionAllowList 创建 + `forChat` 注入）、`:576-624`（skill 执行分支 Path A——可选 wiring 点）、`:620`（`executeSkillStream`）
  - `Sources/AxionCLI/Services/AxionRuntime+SkillExecution.swift:9-70`（`executeSkill` → `buildSkillAgent` Path B 调用方）
- SDK API（`.build/checkouts/open-agent-sdk-swift` 0.10.0，commit `4285aac`，**全部 public + re-export**）：
  - `Sources/OpenAgentSDK/Types/ToolDeclaration.swift:62`（`ToolDeclaration`）、`:137`（`parse(_:)`）、`:203`（`fromToolNames(_:)`）、`:308`（`ToolFilterDiagnostics`）、`:374`（`filterToolsByDeclarations(available:allowed:disallowed:options:)`）、`:445`（`ToolDeclarationDiagnostics`）
  - `Sources/OpenAgentSDK/Types/SkillTypes.swift:12-35`（`ToolRestriction` enum，含 `.toolSearch`）、`:69-70`（`Skill.toolDeclarations` / `toolDeclarationDiagnostics` 字段）
  - `Sources/OpenAgentSDK/Core/Agent.swift:1289-1302`/`1369-1379`（`executeSkill`/`executeSkillStream` 优先 `toolDeclarations` lossless 路径）
  - `Sources/OpenAgentSDK/Core/DefaultSubAgentSpawner.swift:151-156`（**丢弃** runtime `ToolFilterDiagnostics` 的 boundary）、`:218-219`（继承 `permissionMode`/`canUseTool` 给 child）、`:414-433`（`filterTools` 用 `filterToolsByDeclarations` + 剥离 launcher）
  - `Sources/OpenAgentSDK/OpenAgentSDK.swift:128-132`（`ToolDeclaration`/`ToolDeclarationDiagnostics`/`filterToolsByDeclarations` re-export 文档）
- SPEC：`_bmad-output/specs/spec-task-subagent-skill-compat/SPEC.md`（CAP-5 权限一致、CAP-8 工具可见性诊断；Constraints 第 69-73 行「Task 是 side-effect tool，dry-run/permission/tool allowlist 按现有规则」「allowed-tools 不能退化成无限制」）
- 架构：`_bmad-output/specs/spec-task-subagent-skill-compat/architecture.md`（§3 第 104-105 行「filter the assembled pool after deduplication, including MCP namespaced tools」「Unknown allowed-tools entries are reported, must not silently become nil」；§6 第 174 行「Add a diagnostic when a skill/subagent requests a tool unavailable because of config/dry-run/no-skills/permission/SDK support」；State and Permissions「Session allowlist inheritance should follow current canUseTool callback behavior」）
- 实施计划：`_bmad-output/specs/spec-task-subagent-skill-compat/implementation-plan.md`（Phase 4「Skill/Subagent Tool Declaration Compatibility」Task 4「surface unsupported/unrecognized entries in diagnostics; do not silently convert all-unknown into no restriction」、Acceptance 第 118-120 行——本 story AC2 对应；Phase 3 Task 7 ToolSearch policy 属 40.5 已完成）
- 测试计划：`_bmad-output/specs/spec-task-subagent-skill-compat/test-plan.md`（Axion Unit Tests：`allowed-tools common names`/`allowed-tools MCP names`/`allowed-tools unknown names`/`subagent tools filter` 行——本 story AC1/AC2 对应；Traceability CAP-8）
- 棕地分析：`_bmad-output/specs/spec-task-subagent-skill-compat/brownfield-analysis.md`（「Skill 工具限制当前状态」第 58-77 行——SDK enum-only `ToolRestriction` 已升级为 `toolDeclarations` lossless 模型；本 story 是 Axion 侧的「可观察性」收口）
- 项目测试规则：`CLAUDE.md`（Swift Testing、单元测试 Mock、只跑单元测试、`make test`）
- 项目上下文：`_bmad-output/project-context.md`（AgentBuilder 职责 / buildSkillAgent 独立路径；反模式 #10 工具名不硬编码）
- 记忆：`glm-toolsearch-issue`（ToolSearch 默认关闭根因——`configDisabledDeclarations` 的 ToolSearch 实例由此而来）

## Dev Agent Record

### Agent Model Used

glm-5.2[1m] (Claude Code CLI, dev-story workflow)

### Debug Log References

- **首次 `make test` 编译失败（已修）**：测试构造 `Skill(name:promptTemplate:toolDeclarations:)` 时 Swift 报 `argument 'toolDeclarations' must precede argument 'promptTemplate'`。根因：`Skill.init` 的参数声明顺序为 `name, description, aliases, userInvocable, toolRestrictions, toolDeclarations(#6), …, promptTemplate(#10)`，Swift 强制实参按声明顺序传递。修复：4 处 fixture skill 改为 `Skill(name:toolDeclarations:promptTemplate:)` 顺序（跳过带默认值的中间参数合法，只要相对顺序不变）。重新 `make test` 编译通过。
- **`make test` 7 项失败 = 全部在 `DesktopNotifier` 套件（OSC 9/DCS passthrough），非回归**：本会话 `TMUX=/private/tmp/tmux-501/...` 处于 tmux 内，DesktopNotifier 的 OSC 9 序列被 tmux DCS passthrough 包裹成 `\ePtmux;\e\e]9;…\e\\`，与测试期望的 `\e]9;…\a` 不符。正是 Task 5.3 预先记录的环境性失败（40.5 Debug Log 亦记录在案）。本 story 改动仅触及 `AgentBuilder.swift` / `ChatCommand.swift` / 新测试文件，**未触碰**任何 Notification/DesktopNotifier 代码（`git diff --name-only | grep -i notif` 为空），故判定为环境性、非本 story 引入。
- **Story spec 代码片段的一处 bug（实现时已纠正）**：Task 1.2 的 `configDisabledDeclarations` 判定写作 `let toolSearchName = OpenAgentSDK.ToolRestriction.toolSearch.rawValue  // "toolsearch"`，但 Swift String-backed 枚举 `case toolSearch` 的 `rawValue` 是 **camelCase** `"toolSearch"`（非 `"toolsearch"`），而 `ToolDeclaration.normalizedName` 恒为小写 `"toolsearch"`。直接 `==` 比对**永不命中**，会导致 AC3（test 4.2.3）失败。实现时改为 `.rawValue.lowercased()`，与 SDK 自身 `restrictionByLowercasedName` 的归一化（`restriction.rawValue.lowercased()`）完全同源。已在 `AgentBuilder.swift` 该处加 NOTE 注释说明。
- **Review（2026-06-15）修复 config-disabled 双重报告**：原实现中 `diagnoseToolAvailability` 的 `unmatched` = 「normalizedName 不在可用池」会**同时**命中 ToolSearch（当 `enableToolSearch == false` 时，ToolSearch 既不在池 → unmatched，又 normalizedName == "toolsearch" → configDisabled），导致同一声明在 `unmatchedDeclarations` 与 `configDisabledDeclarations` 两类都出现。emit helper 仅对 `.unknown` 做了去重（`where d.status != .unknown`），漏了 configDisabled 的去重 → 用户会看到误导性的 `未匹配: ToolSearch` **和**准确的 `被 config 策略禁用: ToolSearch`。修复：在 helper 内把 `unsupported` + `configDisabled` 的 normalizedName 从 `unmatched` 中排除，使四类互斥；emit helper 移除现在多余的 `.unknown` 过滤（互斥保证每个声明只报一次）。在 AC3 测试追加回归断言「config-disabled 声明不同时进入 unmatched」。`make test` 复跑：Story 40.6 全部 7 个 @Test PASSED（含新断言），40.2–40.5 零回归；仅 `DesktopNotifier` 套件 7 issues（tmux OSC 9/DCS 环境性，非回归）。

### Completion Notes List

- **Task 1（AC1–AC3）**：在 `Sources/AxionCLI/Services/AgentBuilder.swift` 新增 `ToolAvailabilityDiagnostics` struct（4 字段 `unmatchedDeclarations` / `unsupportedDeclarations` / `patternDeclarations` / `configDisabledDeclarations`，均 `[OpenAgentSDK.ToolDeclaration]`；`isEmpty` 与 `affectsAvailability` 计算属性）+ `diagnoseToolAvailability(skill:availableToolNames:enableToolSearch:)` 纯函数 static helper。helper 复用 SDK public 符号（`skill.toolDeclarations` / `skill.toolDeclarationDiagnostics` / `ToolDeclaration.status` / `ToolRestriction.toolSearch`），无 resolveApiKey / 无 MCP / 无 Helper / 无真实 `build()`。`toolDeclarationDiagnostics` 为 nil（程序化构造 Skill）时用 `?? declarations.filter { … }` 回退产出 unsupported/pattern 诊断。**访问级别选 internal**（与同文件 `AgentBuildResult` / `BuildConfig` / `RunCompleteContextBox` 一致，经 `@testable import AxionCLI` 可测）。
- **Task 2（AC5）**：新增 `effectiveSkillToolPool(skill:available:)` 薄封装 SDK `filterToolsByDeclarations(available:allowed:disallowed:)`，暴露 build-time 交集语义。无 declaration 时回退 `toolRestrictions`（经 `ToolDeclaration.fromToolNames` 统一到同一过滤路径，SDK 29.5 unification），二者皆 nil/empty → 返回全部 `available`。
- **Task 3（AC1–AC3 可观察出口）**：`buildSkillAgent`（Path B）在组装 `tools` 后、构造 `agentOptions` 前，调 `diagnoseToolAvailability` + `emitToolAvailabilityDiagnostics` 写 stderr。**warning 不受 `verbose` 门控**（`affectsAvailability` 始终 emit，pattern-only 用 ℹ️ 区分级别）。`buildSkillAgent` 签名零改动（诊断在函数体内）。**Task 3.4 Path A（interactive chat `/skill-name`）wiring 已做**（非 follow-up）：`ChatCommand` skill 执行分支在 `executeSkillStream` 前，用 `state.buildResult.skillRegistry.find(skillExec.name)` 取 Skill、`state.buildResult.agentOptions.tools` 取 chat 池名，`enableToolSearch` 由池成员推导（ToolSearch 在池 ⇔ config 开启，40.5 build 不变量）——与读 `AxionConfig.toolSearchEnabled` 语义等价，但无需把 config 穿入 REPL turn loop。为避免两路径重复，把 emit 逻辑抽成共享 static helper `emitToolAvailabilityDiagnostics(_:skillName:)`，Path A / Path B 共用（纯重构、行为不变）。
- **Task 4（AC6, AC1–AC5）**：新增 `Tests/AxionCLITests/Services/AgentBuilderPermissionAndDiagnosticsConsistencyTests.swift`（Swift Testing，7 个 `@Test`：4.2.1 AC1+AC2 unmatched/unknown、4.2.2 AC2 反向 empty、4.2.3 AC3 ToolSearch config 冲突、4.2.4 AC1 pattern、4.2.5 AC4 forChat 透传/forSkillExecution bypass、4.2.6 AC5 交集收窄、4.2.7 AC5 反向全返回）。禁止 `import XCTest`；工具名从 `createReadTool().name` / `createGrepTool().name` / `createBashTool().name` / `createWriteTool().name` 真实实例读取（反模式 #10）；`normalizedName` 比对用 `ToolRestriction.toolSearch.rawValue.lowercased()`（不写字面量）；不调真实 `build()` / `buildSkillAgent()`，只调纯 helper + 纯 struct 构造。
- **Task 5（AC6 零回归）**：`make test`（等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`，**遵循用户自定义指令统一 `make test`**）。结果：**4019 tests，本 story 7 个新测试全部 PASSED**；40.2 `AgentBuilder.buildToolProfile` / 40.3 `AgentBuilder subagent tool registration` / 40.4 `AgentBuilder discovered skill registry` / 40.5 `AgentBuilder ToolSearch & MCP inheritance` / `AgentBuilder.BuildConfig.forChat` / `AgentBuilder.loadClaudeMd` 套件**全部 PASSED（零回归）**；唯一失败的 `DesktopNotifier` 套件（7 issues）为 tmux OSC 9/DCS 环境性失败（见 Debug Log），非本 story 引入。

### File List

- `Sources/AxionCLI/Services/AgentBuilder.swift`（修改：新增 `ToolAvailabilityDiagnostics` struct + `diagnoseToolAvailability(...)` / `effectiveSkillToolPool(...)` / `emitToolAvailabilityDiagnostics(_:skillName:)` 三个 static helper；`buildSkillAgent` 在 `tools` 组装后插入诊断计算 + stderr emit）
- `Sources/AxionCLI/Commands/ChatCommand.swift`（修改：skill 执行分支 `if let skillExec = matchedSkillExec` 在 `executeSkillStream` 前插入 Path A 诊断 emit，复用同一 helper）
- `Tests/AxionCLITests/Services/AgentBuilderPermissionAndDiagnosticsConsistencyTests.swift`（新增：AC1–AC6 的 Swift Testing @Test，7 个用例）
- `_bmad-output/implementation-artifacts/sprint-status.yaml`（修改：`40-6-…` ready-for-dev → review）

> 注：`Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` 在本会话开始前已被修改（pre-existing，与本 story 无关），未列入 File List。

## Change Log

- 2026-06-15 — Story 40.6 实现：新增 `ToolAvailabilityDiagnostics` + `diagnoseToolAvailability` / `effectiveSkillToolPool` 纯函数 helper（复用 SDK public 符号，复算 `DefaultSubAgentSpawner` 在 boundary 丢弃的 tool-availability diagnostics，CAP-8 闭合）；`buildSkillAgent`（Path B）与 `ChatCommand`（Path A）emit 同款 stderr warning（共享 `emitToolAvailabilityDiagnostics` helper）；锁定 AC4 permission 继承（`forChat` 透传 / `forSkillExecution` 有意 bypass）与 AC5 过滤顺序（allowed-tools 先收窄 → 交集）。新增 7 个 Swift Testing 单元测试，`make test` 通过（40.2–40.5 零回归；DesktopNotifier tmux 环境性失败非回归）。状态 → review。
- 2026-06-15 — **Senior Developer Review (AI)（autonomous story-automator review）**：
  - **结论：0 CRITICAL / 0 HIGH / 1 MEDIUM（已修）/ 2 LOW（记录）→ 状态 done。**
  - **MEDIUM（已修）— config-disabled 声明双重报告**：AC3 场景（`allowed-tools: Read, ToolSearch` + `enableToolSearch:false`）下，ToolSearch 同时进入 `unmatchedDeclarations` 与 `configDisabledDeclarations`；emit helper 仅对 `.unknown` 去重、漏 configDisabled → stderr 同时输出误导性的 `未匹配` 与准确的 `被 config 策略禁用`。修复：helper 内使四类互斥（从 unmatched 排除已归类的 unsupported/configDisabled），emit 移除冗余 `.unknown` 过滤；AC3 测试追加回归断言锁定。
  - **LOW（记录，未改）— helper 形态不对称**：`effectiveSkillToolPool` 回退 legacy `toolRestrictions`，但 `diagnoseToolAvailability` 仅认 `toolDeclarations`。SDK `SkillLoader` 恒填充 `toolDeclarations`（lossless），程序化只设 `toolRestrictions` 的 skill 不触发诊断。属设计取舍（diagnostics 仅服务于 lossless 形态），与 Task 1.2 文档一致，不改。
  - **LOW（记录，未改）— `TaskSerialQueueTests.swift` 工作区改动**：`.serialized` + 10s timeout + 收窄断言（timeout 测试全量套件下的稳定性修复），story File List 注明为 pre-existing/unrelated。未纳入本 story File List。
  - **验证**：`make test` → 4019 tests，Story 40.6 全部 7 个 @Test PASSED（含 AC3 新回归断言），40.2 `buildToolProfile` / 40.3 subagent tool registration / 40.4 discovered skill registry / 40.5 ToolSearch & MCP inheritance **零回归**；唯一失败的 `DesktopNotifier`（7 issues）为 tmux OSC 9/DCS 环境性（`TMUX` 已设；CI 无 tmux 不受影响），非本 story 引入。git 确认 40.6 未触碰任何 notification 代码。
  - **Sprint sync**：`sprint-status.yaml` `40-6-permission-allowlist-and-diagnostics-consistency` review → done。
