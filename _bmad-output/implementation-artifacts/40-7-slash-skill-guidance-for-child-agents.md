---
baseline_commit: fec2c963fd9689b8813dfe140ead357f8b42eb61
---

# Story 40.7: Slash-Skill Guidance for Child Agents

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a Claude Code skill / subagent compatibility user,
I want 一个**带 `Skill` 与 `Task` 两个工具的 agent** 在其系统提示里显式被告知：(a) 当任务/prompt 里出现 `/skill-name args` 时应通过 `Skill` 工具执行，而不是当作普通聊天；(b) 当 skill 内容里出现 `Task(subagent_type:, prompt:)` 片段时应调用 `Task` 工具，而不是把片段当文本打印,
so that BMAD pipeline 这类 Claude Code workflow skill 在 Axion 中能**稳定**走「父 agent 调 Task → 子 agent 调 Skill 执行单步 skill」的链路（CAP-1/CAP-2/CAP-3），而不是靠模型偶然猜中。

**类型：** Feature / system-prompt-guidance story。本 story 是 Epic 40「让 `Task(...)` 子代理链路可稳定执行」的**提示收口**：40.1（SDK 0.10.0 readiness）→ 40.2（parity helper）→ 40.3（注册 Skill/Agent/Task）→ 40.4（discovered registry 传给子代理）→ 40.5（ToolSearch/MCP 继承）→ 40.6（permission/diagnostics 一致性）已经把**工具池、注册、registry 继承、权限、诊断**全部对齐。到 40.6 结束，一个带 `Skill`+`Task` 的 agent **工具层面**已具备执行 Claude Code Task 子代理链路的全部能力——但模型**并不知道**该把 `/skill-name args` 当作 Skill 工具调用、把 `Task(...)` 片段当作 Task 工具调用。SPEC Risk 表（implementation-plan.md 第 197–205 行）明确指出两个失败模式：①「Child agent treats `/skill` as chat」②「Model still prints `Task(...)` instead of calling tool」。本 story 用**系统提示注入**闭合这两个失败模式，是 Axion 侧（不编辑 SDK）唯一可控的杠杆。

本 story **不**改 `buildToolProfile`/`buildSkillToolProfile` 的工具集合（属 40.2/40.3/40.5，已 done）、**不**改 permission/diagnostics 逻辑（属 40.6，已 done）、**不**改 child task 的 progress/failure/summary 输出格式（属 40.8）、**不**编辑 SDK `.build/checkouts/`（SPEC Constraint：「不引入 Node/Python 编排层」「优先复用 SDK 已有 public 符号」；40.6 已建立「不编辑 `.build/checkouts/`」先例）、**不**实现 filesystem subagent discovery / `.claude/agents/*.md`（架构 §7 deferred，SPEC Non-goal）。

## Acceptance Criteria

1. **AC1 — `slashSkillAndTaskGuidance(noSkills:dryrun:)` 纯函数 helper 产出 Claude Code 兼容提示块**
   **Given** Axion agent 的工具池注册条件可由 `(noSkills, dryrun)` 判定（`buildToolProfile`：`Skill` 需 `!noSkills && !dryrun`，`Agent`/`Task` 需 `!dryrun`，故「Skill 与 Task 同时可用」⟺ `!noSkills && !dryrun`；`AgentBuilder.swift:376-389`）
   **When** 调用 `AgentBuilder.slashSkillAndTaskGuidance(noSkills:dryrun:)`（本 story 新增的纯函数 static helper，置于 `AgentBuilder+PromptBuilding.swift`，与 `buildSystemPrompt`/`buildFullSystemPrompt`/`appendModeInstructions` 同族的 prompt-fragment helper）
   **Then** 当 `!noSkills && !dryrun` 时返回**非空** `String`（一个独立的 `## Skill & Subagent Execution` 段落），**否则返回 `nil`**（dry-run 不暴露 side-effect Skill/Task 工具——`buildToolProfile:386` 的 `if !dryrun` 注册门；`--no-skills` 不注册 Skill 工具——`buildToolProfile:376`）
   **And** helper 是**纯函数**：不 resolveApiKey、不连 MCP、不起 Helper、不读文件系统、不调真实 `build()`/`buildSkillAgent()`——只做字符串拼接（与 40.6 `diagnoseToolAvailability`/`effectiveSkillToolPool` 的「注入 seam」哲学一致）
   **And** 返回值在**同一 `(noSkills,dryrun)` 输入下确定**（无随机/无时间依赖），可直接被单元测试断言

2. **AC2 — 提示块措辞同时覆盖「slash-skill 执行」与「Task 工具调用」两条指引（CAP-3 + CAP-1/CAP-2 父侧）**
   **Given** AC1 的 helper 在 `!noSkills && !dryrun` 下返回的提示块文本
   **When** 检查该文本内容
   **Then** 提示块**包含**「slash-skill 执行」指引（架构 §4 第 113-116 行原文语义）：一段明确告诉 agent「当 task prompt 要求执行 `/<skill-name> <args>` 时，用 `Skill` 工具调用 `skill="<skill-name>" args="<args>"`，**不要**把 slash 命令当作普通聊天文本」的指令——闭合 SPEC CAP-3（「子代理收到 `Execute /bmad-create-story 1-1 yolo ...` 时，可以通过 Skill tool 执行」）与 implementation-plan Risk 表第 200 行（「Child agent treats `/skill` as chat → Add slash-skill guidance and ensure SkillTool is inherited」）
   **And** 提示块**包含**「Task 工具调用」指引（implementation-plan Risk 表第 198 行原文语义）：一段明确告诉 agent「Claude Code workflow skill 用 `Task(subagent_type:, description:, prompt:)` 片段派生子代理；当 skill 内容要求你调用 Task/Agent 时，用 `Task` 工具传入对应参数，**不要**把 `Task(...)` 片段当普通文本打印；每次 Task 调用会运行到完成再继续下一步」的指令——闭合 SPEC CAP-1/CAP-2（模型稳定调用 `Task` 工具而非猜）与 implementation-plan Risk 表第 198 行（「Model still prints `Task(...)` instead of calling tool → system prompt should say Claude Code Task snippets map to the `Task` tool」）
   **And** 两条指引置于**同一个** `## Skill & Subagent Execution (Claude Code Compatibility)` 段落下（紧凑、单次注入），措辞与架构 §4 + Risk 表**同源**——dev 实现时直接以本 story AC2 的措辞为唯一真源，**不**另造措辞（避免「措辞漂移导致模型行为不稳定」）

3. **AC3 — `buildSystemPrompt`（chat / `axion run` / Path A 交互式 `/skill-name`）注入提示块**
   **Given** `AgentBuilder.build()`（`AgentBuilder.swift:182`）调用 `buildSystemPrompt(config:task:…:noSkills:dryrun:…)`（`AgentBuilder+PromptBuilding.swift:46-98`），其 `systemPrompt` 即被 Path A 交互式 chat 复用的 chat agent 的系统提示（`ChatCommand.swift:620` 在**已建好的 chat agent** 上 `executeSkillStream`，故父 agent 系统提示 = `buildSystemPrompt` 产物）
   **When** `buildSystemPrompt` 内部在组装完 mode 指令（`appendModeInstructions`，`:89`）、**CLAUDE.md 项目指令**（`:92-95`）之前/之后任一稳定位置，调用 `slashSkillAndTaskGuidance(noSkills:noSkills, dryrun:dryrun)` 并在非 nil 时追加到 `prompt`
   **Then** Path A 的父 agent 系统提示在 `!noSkills && !dryrun` 时**包含** AC2 的两段指引；在 dry-run 或 `--no-skills` 时**不包含**
   **And** `buildSystemPrompt` **签名零改动**（`noSkills`/`dryrun` 已是其参数，`:53`/`:55`）——注入在函数体内，调用方（`build()`、`BuildConfig`、Mock、E2E）**零改动**（沿用 40.4/40.5/40.6 的「最小爆炸半径」约束）
   **And** 提示块追加位置**在 CLAUDE.md 项目指令之前**（即属于 Axion 内核系统提示，而非用户项目指令），避免被项目 CLAUDE.md 误覆盖；具体 seam 由 dev 选定并固定（建议：`appendModeInstructions` 之后、`loadClaudeMd` 之前，`:89` 与 `:92` 之间）

4. **AC4 — `buildSkillAgent`（Path B 非 interactive `/skill-name` / API / daemon）注入提示块**
   **Given** `AxionRuntime.executeSkill` → `buildSkillAgent`（`AgentBuilder.swift:717-781`）用 `buildSkillToolProfile`（`:496-498` **总是**注册 `Skill`+`Agent`+`Task`，无 dryrun/noSkills 门）组装工具池，其内联 `systemPrompt`（`:759` 字符串字面量）是 Path B 父 agent（运行 bmad-story-pipeline 这类 pipeline skill 的 agent）的系统提示
   **When** `buildSkillAgent` 构造 `AgentOptions` 的 `systemPrompt:` 时，把 `slashSkillAndTaskGuidance(noSkills:false, dryrun:false)`（skill 路径恒 `!noSkills && !dryrun`，故恒非 nil）追加到既有内联提示之后
   **Then** Path B 的父 agent 系统提示**总是包含** AC2 的两段指引（skill 路径恒注册 Skill+Task）
   **And** `buildSkillAgent` **签名零改动**（沿用 40.3/40.4/40.5/40.6）；注入在 `systemPrompt:` 字面量拼接处（`:759`），其余 `agentOptions` 字段不变
   **And** 该内联提示的「工作目录 + `[结果]` 摘要」既有语义**完整保留**（不破坏 Path B 既有输出契约——`[结果]` 摘要行属既有行为，本 story 只在其后追加，不改写）

5. **AC5 — 新增 Swift Testing 单元测试覆盖 AC1–AC4；`make test` 通过；40.2–40.6 零回归**
   **Given** AC1–AC4 的 helper / wiring 已实现
   **When** 在 `Tests/AxionCLITests/Services/` 新增 Swift Testing 测试文件
   **Then** 测试覆盖：
     - **AC1**：`slashSkillAndTaskGuidance(noSkills:false, dryrun:false)` → 非 nil；`(noSkills:true, dryrun:false)` → nil；`(noSkills:false, dryrun:true)` → nil；`(noSkills:true, dryrun:true)` → nil（四象限条件真值表）
     - **AC2**：非 nil 返回值包含「slash-skill 执行」关键短语（如 `"invoke the Skill tool"` + `"Do not treat the slash command as plain chat"`）**和**「Task 工具调用」关键短语（如 `"Task(subagent_type"` + `"invoke the Task tool"` + `"do not"`/`"instead of printing"`）。**措辞断言用关键短语子串匹配**（这些是 SPEC/Risk 表 canonical 措辞，非工具名硬编码——区别见 Dev Notes「反模式 #10 边界」）
     - **AC3**：构造一个**最小可测**的 `buildSystemPrompt` 调用（注入空 `SkillRegistry`、`noMemory:true` 避免真实 memory 副作用、`task:""`），断言 `(noSkills:false, dryrun:false)` 产出的提示**包含** AC2 关键短语，`(dryrun:true)` 产出的提示**不含**。**若 `buildSystemPrompt` 的 async/memory 副作用使直接调用过重**，dev 可改为：断言 `buildSystemPrompt` 内**调用了** `slashSkillAndTaskGuidance`（通过提取注入点为可单独测试的 helper，或通过 `appendSlashSkillGuidance(to:noSkills:dryrun:) -> String` 这类薄 helper 间接断言）——但**首选**直接对 `slashSkillAndTaskGuidance` 纯 helper 做四象限 + 措辞断言（AC1+AC2），AC3 的 wiring 用「调用 helper」这一事实 + 一条集成式 smoke（可选）覆盖
     - **AC4**：断言 `buildSkillAgent` 的 systemPrompt 包含 AC2 关键短语——**但禁止调真实 `buildSkillAgent()`**（会 resolveApiKey + Helper）。改用：把 `buildSkillAgent` 的「内联提示 + 指引拼接」提取为可测的纯 helper（如 `skillExecutionSystemPrompt(cwd:) -> String`，或直接复用 `slashSkillAndTaskGuidance(noSkills:false,dryrun:false)` 断言其非 nil + 包含关键短语），证明 Path B 会注入。**若提取 helper 风险过大**，dev 可只在 Dev Notes 引用 `:759` 为证 + AC1/AC2 纯 helper 覆盖，AC4 wiring 作为 smoke（标注「真实 `buildSkillAgent` 行为由 40.3/40.4 测试间接覆盖」）
   **And** 测试**不调用真实 `AgentBuilder.build()` / `buildSkillAgent()`**（会 resolveApiKey + 起 Helper + 真实 MCP resolve）；只调纯函数 helper（`slashSkillAndTaskGuidance`）+ 必要时调 `buildSystemPrompt`（注入空 registry / `noMemory:true`，无外部副作用——`buildSystemPrompt` 只读 prompt 目录 + memoryStore，memoryStore 可传空 store）
   **And** 工具名**不硬编码字面量做期望**（反模式 #10）：若测试需要引用工具名，从 `createSkillTool().name` / `createTaskTool().name` / `createAgentTool().name` 读取（这些 SDK 工厂是 side-effect-free 纯构造，40.3/40.6 测试已验证可安全调用）；**但 AC2 的措辞断言属 canonical 短语匹配，不是工具名期望**——见 Dev Notes
   **And** 执行 `make test`（**用户自定义指令**：统一 `make test`，等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`），全部通过；40.2 `AgentBuilderToolProfileTests`、40.3 `AgentBuilderSubagentToolRegistrationTests`、40.4 `AgentBuilderDiscoveredSkillRegistryTests`、40.5 `AgentBuilderToolSearchAndMcpInheritanceTests`、40.6 `AgentBuilderPermissionAndDiagnosticsConsistencyTests` **零回归**

> **ATDD 测试引用（RED 阶段将生成）**
> - 测试文件：`Tests/AxionCLITests/Services/AgentBuilderSlashSkillGuidanceTests.swift`（Swift Testing，覆盖 AC1–AC5）
> - ATDD checklist（Step 2 生成）：`_bmad-output/test-artifacts/atdd-checklist-40-7-slash-skill-guidance-for-child-agents.md`
> - 当前状态：待 Step 2 生成 RED 脚手架

## Tasks / Subtasks

- [x] **Task 1 — 新增 `slashSkillAndTaskGuidance(noSkills:dryrun:)` 纯函数 helper（AC1, AC2）**
  - [x] 1.1 在 `Sources/AxionCLI/Services/AgentBuilder+PromptBuilding.swift`（`AgentBuilder` extension 内，与 `appendModeInstructions`/`buildFullSystemPrompt` 并列）新增 static helper：
    ```swift
    /// Claude Code skill/subagent 兼容提示块（Story 40.7）。
    ///
    /// 当一个 agent 同时注册了 `Skill` 与 `Task` 工具（即 `!noSkills && !dryrun`，与
    /// `buildToolProfile`/`buildSkillToolProfile` 的注册门同源）时，返回一段系统提示，
    /// 告诉模型两件事：
    /// 1. **slash-skill 执行**（架构 §4 / CAP-3）：task prompt 里的 `/<skill-name> <args>`
    ///    要用 `Skill` 工具执行，不要当普通聊天。
    /// 2. **Task 工具调用**（implementation-plan Risk 表 / CAP-1/CAP-2）：skill 内容里的
    ///    `Task(subagent_type:, prompt:)` 片段要用 `Task` 工具调用，不要打印成文本。
    ///
    /// 这闭合两个已知失败模式（implementation-plan.md 第 198/200 行）：
    /// - 「Model still prints `Task(...)` instead of calling tool」
    /// - 「Child agent treats `/skill` as chat」
    ///
    /// **纯函数**：无副作用、无外部依赖、无随机/时间——同 `(noSkills,dryrun)` 输入恒定输出，
    /// 可直接单元测试（与 40.6 `diagnoseToolAvailability` 同族「注入 seam」helper）。
    ///
    /// - Parameters:
    ///   - noSkills: 是否 `--no-skills`（不注册 Skill 工具）。
    ///   - dryrun: 是否 dry-run（不注册 Skill/Agent/Task side-effect 工具）。
    /// - Returns: 提示块字符串（`!noSkills && !dryrun` 时非 nil），否则 nil。
    static func slashSkillAndTaskGuidance(noSkills: Bool, dryrun: Bool) -> String? {
        // 「Skill 与 Task 同时可用」⟺ !noSkills && !dryrun
        // —— 与 buildToolProfile 的注册门（Skill: !noSkills && !dryrun；Agent/Task: !dryrun）
        //    同源，是 Axion 侧判定「该 agent 能否走 Claude Code Task 子代理链路」的唯一真值。
        guard !noSkills, !dryrun else { return nil }
        return """

        ## Skill & Subagent Execution (Claude Code Compatibility)

        Some skills and workflow files use Claude Code conventions. Follow these rules exactly:

        - **Slash-skill execution**: When a task prompt asks you to execute `/<skill-name> <args>`
          (for example `Execute /bmad-create-story 1-1 yolo`), invoke the `Skill` tool with
          `skill="<skill-name>"` and `args="<args>"`. Do not treat the slash command as plain
          chat text — it is an instruction to run that skill.
        - **Task tool calls**: When a skill's content tells you to call
          `Task(subagent_type:, description:, prompt:)` or `Agent(...)` to spawn a child agent,
          invoke the `Task` tool with those arguments. Do not print the `Task(...)` snippet as
          plain text. Each Task call runs its child to completion before you continue to the
          next step; if a child fails, stop and report the failed step.
        """
    }
    ```
  - [x] 1.2 **措辞锁定**：提示块文本以 AC2 的关键短语为唯一真源（`"invoke the Skill tool"`、`"Do not treat the slash command as plain chat"`、`"Task(subagent_type:, description:, prompt:)"`、`"invoke the `Task` tool"`、`"Do not print the `Task(...)` snippet"`）。dev 可润色连接词，但**这五个关键短语必须逐字保留**（测试断言锚点 + 模型行为稳定性）
  - [x] 1.3 **不**在该 helper 内做任何工具池查询或 registry 访问——`(noSkills, dryrun)` 是它需要的全部输入（保持纯函数 + 全确定性）。返回类型用 `String?`（nil = 不注入），调用点用 `if let`/`.map` 拼接

- [x] **Task 2 — wiring `buildSystemPrompt`（Path A / run）注入提示块（AC3）**
  - [x] 2.1 在 `buildSystemPrompt`（`AgentBuilder+PromptBuilding.swift:46-98`）中，于 `prompt = appendModeInstructions(to: prompt, fast: fast, dryrun: dryrun)`（`:89`）**之后**、`let claudeMdContent = loadClaudeMd(cwd: cwd)`（`:92`）**之前**插入：
    ```swift
    // Story 40.7: inject Claude Code skill/subagent compatibility guidance when both the Skill
    // and Task tools are registered (i.e. !noSkills && !dryrun). Tells the model to execute
    // /skill-name via the Skill tool and to call the Task tool for Task(...) snippets instead of
    // printing them — closes CAP-1/CAP-2/CAP-3 prompt gap (architecture §4 + impl-plan Risk table).
    if let guidance = slashSkillAndTaskGuidance(noSkills: noSkills, dryrun: dryrun) {
        prompt += "\n\n\(guidance)"
    }
    ```
  - [x] 2.2 位置选择理由（固定并文档化）：放在 `appendModeInstructions` 之后（mode 指令优先级更高，先追加）、CLAUDE.md 之前（本指引属 Axion 内核系统提示，非用户项目指令，不应被项目 CLAUDE.md 覆盖）。**不**放在 `buildFullSystemPrompt` 内（那是「base + memory + skills 段」的组合，本指引是 mode-level 兼容提示，与 `appendModeInstructions` 同层）
  - [x] 2.3 **签名零改动**（`noSkills`/`dryrun` 已是 `buildSystemPrompt` 参数）；调用方（`build()`）零改动。dry-run / `--no-skills` 时 helper 返回 nil → 不追加 → 行为与 40.6 前一致

- [x] **Task 3 — wiring `buildSkillAgent`（Path B）注入提示块（AC4）**
  - [x] 3.1 在 `buildSkillAgent`（`AgentBuilder.swift:717-781`）中，把 `:759` 的内联 `systemPrompt:` 字面量改为「既有提示 + 指引」拼接。建议把既有字面量提取为局部常量再拼接（提升可读性 + 可测性）：
    ```swift
    let baseSkillPrompt = "All filesystem and terminal operations must use \(cwd) as the working directory. Do NOT invent or guess paths — always resolve relative paths against \(cwd).\n\n# Task Summary — MANDATORY\n\nEVERY response MUST end with exactly one summary line in this format:\n[结果] <one-line summary, max 100 chars>\nThis is NOT optional. Even if the task failed, you MUST include this line."
    // Story 40.7: skill path always registers Skill+Agent+Task (buildSkillToolProfile:496-498,
    // no dryrun/noSkills gating), so the guidance is always injected here. This is the PARENT
    // agent prompt for a pipeline skill (e.g. bmad-story-pipeline) running via axion run / API.
    let skillSystemPrompt = baseSkillPrompt
        + (slashSkillAndTaskGuidance(noSkills: false, dryrun: false).map { "\n\n\($0)" } ?? "")
    ```
    并把 `AgentOptions(... systemPrompt: skillSystemPrompt ...)` 用 `skillSystemPrompt` 替换原字面量
  - [x] 3.2 **签名零改动**（`buildSkillAgent(config:skill:maxSteps:verbose:eventBus:)` 不变）；`agentOptions` 其余字段（model/maxTurns/permissionMode/tools/mcpServers/skillRegistry/...）不动
  - [x] 3.3 既有「`[结果]` 摘要」契约**完整保留**（指引追加在既有提示**之后**，不重写、不前置覆盖）

- [x] **Task 4 — 新增单元测试（AC5, AC1–AC4）**
  - [x] 4.1 新增 `Tests/AxionCLITests/Services/AgentBuilderSlashSkillGuidanceTests.swift`，使用 **Swift Testing**（`import Testing`、`@Suite`、`@Test`、`#expect`），**禁止 `import XCTest`**
  - [x] 4.2 `@Suite("AgentBuilder slash-skill guidance (Story 40.7)")` 包含以下 `@Test`：
    - [x] 4.2.1 `test_slashSkillAndTaskGuidance_returnsBlockWhenBothAvailable` — **AC1 正向**。`slashSkillAndTaskGuidance(noSkills:false, dryrun:false)` → 非 nil
    - [x] 4.2.2 `test_slashSkillAndTaskGuidance_nilWhenNoSkills` — **AC1**。`(noSkills:true, dryrun:false)` → nil（Task 可能注册但 Skill 不注册 → 不注入 slash 指引）
    - [x] 4.2.3 `test_slashSkillAndTaskGuidance_nilWhenDryRun` — **AC1**。`(noSkills:false, dryrun:true)` → nil（dry-run 不注册 side-effect 工具）
    - [x] 4.2.4 `test_slashSkillAndTaskGuidance_nilWhenBothOff` — **AC1 四象限补全**。`(noSkills:true, dryrun:true)` → nil
    - [x] 4.2.5 `test_slashSkillAndTaskGuidance_containsSlashSkillExecutionPhrase` — **AC2 slash**。非 nil 返回值包含 `"invoke the Skill tool"` **与** `"Do not treat the slash command as plain"`
    - [x] 4.2.6 `test_slashSkillAndTaskGuidance_containsTaskInvocationPhrase` — **AC2 Task**。非 nil 返回值包含 `"Task(subagent_type"` **与** `"invoke the `Task` tool"` **与** `"Do not print the"`（三个锚点短语）
    - [x] 4.2.7 `test_slashSkillAndTaskGuidance_doesNotMentionDisabledState` — **范围守护**（可选）。非 nil 返回值在 `(false,false)` 下**不含** `"disabled"`/`"not available"`（确认正向指引，非降级提示；若 dev 在 Task 1 选了「降级 nil」策略则此测试成立）
    - [x] 4.2.8 `test_buildSystemPrompt_includesGuidanceWhenBothAvailable` — **AC3 wiring smoke**（推荐）。构造 `await buildSystemPrompt(config: makeConfig(), task: "", memoryStore: FileBasedMemoryStore(memoryDir: tmpDir), memoryDir: tmpDir, skillRegistry: SkillRegistry(), noMemory: true, noSkills: false, fast: false, dryrun: false, includeSaveSkillGuidance: false)`，断言返回值包含 AC2 关键短语；**对照组** `dryrun: true` 的返回值**不含**。`makeConfig()` 沿用 40.5/40.6 测试的 `AxionConfig(apiKey:"sk-test")` 工厂；`noMemory:true` 避免真实 memory 副作用；`SkillRegistry()` 空 registry（不触发发现）。**若该测试因 `buildSystemPrompt` 的 `PromptBuilder.load`/memory 副作用在 CI 不稳，dev 可降级为「断言 buildSystemPrompt 调用了 helper」——但首选真实 smoke**
  - [x] 4.3 Mock 约束：**禁止**调真实 `AgentBuilder.build()` / `buildSkillAgent()`；4.2.1–4.2.7 只调纯函数 `slashSkillAndTaskGuidance`（零外部依赖）；4.2.8 调 `buildSystemPrompt`（注入空 registry + `noMemory:true`，无网络/无 Helper/无 MCP）；**禁止 `import XCTest`**；`grep -rl "import XCTest" Tests/` 应返回空
  - [x] 4.4 测试命名遵循 `test_被测单元_场景_预期结果`（与 40.6 测试族一致）

- [x] **Task 5 — 运行默认单元测试，确认零回归（AC5）**
  - [x] 5.1 执行项目 Makefile 的 `test` 目标（**用户自定义指令**：统一用 `make test`，**不要** `swift test --filter ...`）：
    ```bash
    make test
    ```
    （等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`，全部单元测试）
  - [x] 5.2 全部通过（既有测试零回归 + 新 slash-skill guidance 测试转绿）。**特别关注**：
    - 40.6 `AgentBuilderPermissionAndDiagnosticsConsistencyTests`（7 @Test）：本 story 给 `buildSkillAgent` 的 `systemPrompt` 追加指引——`systemPrompt` 字符串变化**不影响** `diagnoseToolAvailability`/`effectiveSkillToolPool`/`emitToolAvailabilityDiagnostics` 的断言（它们不读 systemPrompt）→ ✅ 不破
    - 40.4 `AgentBuilderDiscoveredSkillRegistryTests`（6 @Test）：调真实 `buildSkillAgent`，本 story Task 3 改其 systemPrompt 字面量——registry 断言（`agentOptions.skillRegistry`、tools 含 Skill/Agent/Task）**不读 systemPrompt** → ✅ 不破（注意：若 40.4 有断言 systemPrompt **精确字面量**的测试，需同步更新——dev 实现时 `grep -n 'systemPrompt' Tests/AxionCLITests/Services/AgentBuilderDiscoveredSkillRegistryTests.swift` 核实，若有则更新断言为「包含既有 `[结果]` 短语」而非全等）
    - 40.3 `AgentBuilderSubagentToolRegistrationTests`（5 @Test）/ 40.2 `AgentBuilderToolProfileTests`（7 @Test）/ 40.5 `AgentBuilderToolSearchAndMcpInheritanceTests`（7 @Test）：本 story **不**改 `buildToolProfile`/`buildSkillToolProfile` 工具集合、**不**改 ToolSearch/MCP helper → ✅ 不破
    - 既有 prompt 相关测试（`PromptBuilderTests`、`AgentBuilderCodingTests`、`AgentBuilder loadClaudeMd` 套件）：本 story 在 `buildSystemPrompt` 追加指引——若有断言 `buildSystemPrompt` 输出**精确长度/全等**的测试，dev 核实并按需放宽为「包含既有关键段」；`grep -rn 'buildSystemPrompt\|buildFullSystemPrompt' Tests/` 先排查
  - [x] 5.3 **不运行** `Tests/**/Integration/`、`Tests/**/AxionE2ETests/`。若本会话在 tmux 内（`TMUX` 环境变量存在），`DesktopNotifier` 套件可能因 OSC 9/DCS passthrough 环境性失败（40.5/40.6 Debug Log 已记录）——属环境性，非本 story 引入、非回归

## Dev Notes

### 本 Story 的核心：工具层已就绪，只缺「告诉模型怎么用」

Epic 40 的 40.1–40.6 已经把 Claude Code Task 子代理链路的**工具基础设施**全部对齐：

| 层 | Story | 已完成内容 |
|----|-------|-----------|
| SDK readiness | 40.1 | resolve 到 `open-agent-sdk-swift` 0.10.0+（`Task` alias、skill package context、child registry 继承在 SDK 侧） |
| 工具池 parity | 40.2 | `buildToolProfile` parity helper |
| 注册 Skill/Agent/Task | 40.3 | `buildToolProfile`（chat/run）+ `buildSkillToolProfile`（skill path）都注册 `Skill`+`Agent`+`Task` |
| discovered registry | 40.4 | `makeDiscoveredSkillRegistry` → `AgentOptions.skillRegistry` → SDK `DefaultSubAgentSpawner` 继承**全量** registry 给子代理 |
| ToolSearch/MCP 继承 | 40.5 | `enableToolSearch` config + `resolveSkillMcpServers` |
| permission/diagnostics | 40.6 | `diagnoseToolAvailability` + `effectiveSkillToolPool` + permission 继承锁定 |

**到 40.6 结束**，一个带 `Skill`+`Task` 的 Axion agent **工具层面**已能：父 agent 调 `Task` 工具 → SDK `DefaultSubAgentSpawner` 派生子代理 → 子代理继承 `Skill` 工具 + 全量 registry → 子代理理论上能调 `Skill` 工具执行 `/skill-name`。

**但模型并不知道该这么做**。SPEC Risk 表（implementation-plan.md 第 197–205 行）明确列出两个剩余失败模式：

| 失败模式 | 根因 | 本 story 闭合 |
|---------|------|--------------|
| **Model still prints `Task(...)` instead of calling tool**（第 198 行） | 父 agent 读到 pipeline skill 里的 `Task(subagent_type:, prompt:)` 片段，**打印**它而不是调用 `Task` 工具 | AC2「Task 工具调用」指引 + AC3/AC4 注入到父 agent 系统提示 |
| **Child agent treats `/skill` as chat**（第 200 行） | 子 agent 收到 `prompt: "Execute /bmad-create-story ..."`，把它当**普通聊天**而不是调 `Skill` 工具 | AC2「slash-skill 执行」指引（注：见下「子代理系统提示」机制说明——Axion 只能在**父**系统提示注入；子代理侧见「为何子代理提示不在本 story 范围」） |

implementation-plan.md 第 198 行 Mitigation 原文：「Tool name must be exactly `Task`; system prompt should say Claude Code Task snippets map to the `Task` tool」。第 200 行 Mitigation 原文：「Add slash-skill guidance and ensure SkillTool is inherited」。**SkillTool 继承已在 40.3/40.4 完成；剩余的就是「system prompt guidance」——这正是 40.7。**

### 关键机制：Axion 只能控「父」系统提示，「子」系统提示由 SDK 决定（不编辑 SDK 的硬约束）

这是本 story 最关键的架构事实，dev 必须先理解再动手：

**子代理（Task/Agent 派生）的系统提示由 SDK 决定，Axion 无法在不编辑 SDK 的前提下改它。** 证据链（SDK 0.10.0，HEAD `fec2c96`、SDK commit `4285aac`）：

1. `AgentTool.perform`（`AgentTool.swift:245-258`）调 `spawner.spawn(... systemPrompt: agentDef?.systemPrompt ...)`。
2. `agentDef = BUILTIN_AGENTS[agentType]`（`AgentTool.swift:239`），`agentType = input.subagent_type ?? "general-purpose"`（`:238`）。
3. `BUILTIN_AGENTS`（`AgentTool.swift:6-23`）只有 `"Explore"` 和 `"Plan"` 两个条目——**没有 `"general-purpose"`**。故 BMAD pipeline 用的 `subagent_type: "general-purpose"` 命中 `agentDef == nil` → `systemPrompt: nil` 传给 spawner。
4. `DefaultSubAgentSpawner.spawn`（`DefaultSubAgentSpawner.swift:134-230`）把收到的 `systemPrompt`（nil）原样塞进 `AgentOptions(systemPrompt: systemPrompt, ...)`（`:216`）→ 子代理系统提示 = SDK 默认（nil/空）。
5. **`SubAgentInheritanceContext`（`DefaultSubAgentSpawner.swift:25-50`）没有 `systemPrompt` 字段**——只有 `mcpServers`/`skillRegistry`/`permissionMode`/`canUseTool`/`cwd`/`env`/`sandbox`/`eventBus`/`maxSkillRecursionDepth`。故 Axion **无法**通过 inheritance context 注入子代理系统提示。

**结论**：在 SPEC Constraint「优先复用 SDK 已有 public 符号」「不引入 Node/Python 编排层」+ 40.6「不编辑 `.build/checkouts/`」先例下，Axion 侧唯一可控的系统提示是**父 agent 的系统提示**（`buildSystemPrompt` 产物，覆盖 chat/run/Path A；`buildSkillAgent` 内联提示，覆盖 Path B）。

**架构 §4（第 118 行）原文给了「或」**：「This instruction should be added to the **parent agent system prompt** when `Skill` and `Task` are both registered, **or** to the child agent system prompt in the subagent tool factory.」——本 story 取**前者**（父系统提示），后者（子代理 factory）属 SDK 改动，超出 Epic 40 范围（SPEC Non-goal：「不在 Axion 实现 SDK Epic 29 公共 runtime 能力」）。

**那「Child agent treats `/skill` as chat」如何在父系统提示注入后闭合？** 分两层：
1. **父 agent 直接执行 slash skill 的场景**（skill 内容里直接写「现在执行 `/bmad-create-story ...`」给**同一个** agent，不经 Task 子代理）：父系统提示的 slash 指引**直接生效**——父 agent 调 `Skill` 工具。✅ 完全闭合。
2. **BMAD pipeline 经 Task 子代理的场景**（父调 `Task(prompt:"Execute /bmad-create-story ...")`，子代理执行）：父系统提示的 slash 指引**不直接传给子**（子系统提示是 SDK 默认）。但子代理**已继承 `Skill` 工具 + 全量 registry**（40.3/40.4），且子的 task prompt（父用 Task 工具传入的 `prompt:`）会显式写「Execute /bmad-create-story ...」。配合父系统提示的「Task 工具调用」指引（AC2 第二段），父会把 slash 命令**原样**放进 Task prompt——子代理看到 `Skill` 工具可用 + 明确的 `/skill-name args` 指令，**有能力的模型**会调 `Skill` 工具。**子代理系统提示的显式 slash 指引属 SDK follow-up**（架构 §4「或」的另一支 + §7 deferred），本 story 不实现，但在 Completion Notes 标注为已知 follow-up。

**这一取舍与 SPEC 一致**：CAP-3 success 原文「子代理收到 `Execute /bmad-create-story 1-1 yolo ...` 时，**可以**通过 Skill tool 执行」——「可以」是能力可用性（Skill 工具 + registry 已继承），不是「保证」。本 story 把父侧提示补齐后，链路在**有能力的模型**下稳定可达；子侧显式提示作为 SDK follow-up 记录。

### 注入点判定（为何是 `buildSystemPrompt` + `buildSkillAgent` 两处）

Axion 侧**所有** agent 的系统提示都经这两个出口：

| 出口 | 文件:行 | 覆盖路径 | 父/子 |
|------|--------|---------|-------|
| `buildSystemPrompt` | `AgentBuilder+PromptBuilding.swift:46-98`（被 `build()` 在 `AgentBuilder.swift:182` 调用） | chat REPL（Path A：`ChatCommand.swift:620` 在 chat agent 上 `executeSkillStream`）、`axion run`（run command 用 `build()`） | **父** agent 系统提示 |
| `buildSkillAgent` 内联 `systemPrompt:` | `AgentBuilder.swift:759`（被 `AxionRuntime+SkillExecution.swift:24` 调用） | 非 interactive `/skill-name`（API / daemon / `axion run` 经 skill runtime） | **父** agent 系统提示（运行 pipeline skill 的 agent） |

两处都注入 = 覆盖 Axion 侧全部父 agent 路径。子 agent 路径（SDK `DefaultSubAgentSpawner`）不在 Axion 可控范围（见上）。

**为何不用 `buildFullSystemPrompt`（`:120-164`）作为注入点？** `buildFullSystemPrompt` 组合的是「base prompt + memory + universal memory + skills 段」，是**内容组合层**；本指引是 **mode-level 兼容提示**（与 fast/dryrun mode 指令 `appendModeInstructions` 同层，依赖 `noSkills`/`dryrun` 判定）。放 `appendModeInstructions` 之后、CLAUDE.md 之前（AC3 Task 2.2）语义最清晰，且 `buildFullSystemPrompt` 不接收 `dryrun` 参数（签名 `:120-126` 只有 `includeSaveSkillGuidance`），强行塞入要改其签名——违背最小爆炸半径。

### 「Skill 与 Task 同时可用」为何 ⟺ `!noSkills && !dryrun`

直接读 `buildToolProfile`（`AgentBuilder.swift:376-389`）的注册门：
- `Skill`：`if !noSkills, !dryrun`（`:376`）→ 需 `!noSkills && !dryrun`
- `Agent`/`Task`：`if !dryrun`（`:386`）→ 需 `!dryrun`

「同时可用」= 两者注册门的**交集** = `(!noSkills && !dryrun) && (!dryrun)` = `!noSkills && !dryrun`。

skill 路径 `buildSkillToolProfile`（`:496-498`）**无门**（恒注册三者），故 Path B 恒 `!noSkills && !dryrun` → 恒注入（AC4 Task 3.1 传 `noSkills:false, dryrun:false`）。

**这一判定与 40.3 的注册逻辑同源**（不是新规则），helper `(noSkills, dryrun)` 入参正是 `buildToolProfile` 的注册条件投影——单源真值，未来若 40.3 的注册门变了（如加新的 side-effect 门），本 helper 的 guard 同步更新即可（dev 在 Dev Notes 标注此耦合点）。

### 反模式 #10 边界：措辞断言 ≠ 工具名硬编码

CLAUDE.md 反模式 #10「测试中硬编码工具名字面量做期望」——本 story 测试需小心区分两类断言：

| 断言类型 | 是否反模式 #10 | 正确做法 |
|---------|---------------|---------|
| **工具可用性逻辑**（如「`buildToolProfile` 注册了 Skill 工具」） | ✅ 是反模式 | 从 `createSkillTool().name` / `createTaskTool().name` 真实实例读取（SDK 工厂 side-effect-free，40.3/40.6 已验证） |
| **canonical 措辞**（如「提示包含 `"invoke the Skill tool"`」） | ❌ 不是反模式 | 这是 SPEC/Risk 表**指定的**模型行为锚点措辞，是产品契约的一部分。子串匹配这些短语 = 断言产品契约，不是「硬编码工具名做期望」 |

AC2/Task 4.2.5–4.2.6 的措辞断言属第二类——`"invoke the Skill tool"`、`"invoke the `Task` tool"`、`"Task(subagent_type"` 是 implementation-plan Risk 表 + 架构 §4 钦定的措辞，**测试锚定它们是为了防止措辞漂移导致模型行为不稳**，与反模式 #10 无关。dev 实现时**不要**把措辞断言误改成「从工具实例读名」——那样反而丢失了对 canonical 措辞的守护。

### 范围控制总结（防止 scope creep）

| 内容 | 本 story 做？ | 归属 |
|------|--------------|------|
| `slashSkillAndTaskGuidance(noSkills:dryrun:)` 纯 helper（slash + Task 两段指引） | ✅ | 40.7 |
| `buildSystemPrompt`（Path A / run）注入 | ✅ | 40.7 |
| `buildSkillAgent`（Path B）内联提示注入 | ✅ | 40.7 |
| AC1–AC5 Swift Testing 单元测试 | ✅ | 40.7 |
| 改 `buildToolProfile`/`buildSkillToolProfile` 工具集合 | ❌ | 40.2/40.3/40.5（已完成） |
| 改 permission/diagnostics 逻辑 | ❌ | 40.6（已完成） |
| child task progress/failure/summary 输出格式 | ❌ | 40.8 |
| 子代理系统提示注入（SDK `DefaultSubAgentSpawner` / AgentTool factory） | ❌（需编辑 SDK） | SDK follow-up（架构 §4「或」另一支 + §7 deferred） |
| filesystem subagent discovery / `.claude/agents/*.md` | ❌ | 架构 §7 deferred |
| 改 `buildSystemPrompt`/`buildSkillAgent` 签名 | ❌（最小爆炸半径） | — |
| 编辑 SDK `.build/checkouts/` | ❌（SPEC Constraint + 40.6 先例） | — |
| E2E（真实 BMAD pipeline 端到端跑通） | ❌（E2E 范围，40.9/40.10） | follow-up |

### 反模式红线（CLAUDE.md 强制）

- ❌ **在测试中调真实 `AgentBuilder.build()` / `buildSkillAgent()`**：会 resolveApiKey + Helper + MCP。测试只调纯函数 `slashSkillAndTaskGuidance` + 必要时 `buildSystemPrompt`（空 registry + `noMemory:true`）
- ❌ **用 `import XCTest`**：`grep -rl "import XCTest" Tests/` 应返回空
- ❌ **编辑 SDK `.build/checkouts/`**：本 story 纯 Axion 侧系统提示注入，复用 SDK public 符号（`createSkillTool`/`createTaskTool` 仅在测试里读 `.name`）
- ❌ **改 `buildSystemPrompt`/`buildSkillAgent` 签名**：注入在函数体内（Task 2.3/3.2），波及 `build()`/`BuildConfig`/Mock/E2E
- ❌ **改 `buildToolProfile`/`buildSkillToolProfile` 工具集合**：属 40.2/40.3/40.5；本 story 只加提示
- ❌ **措辞断言误用反模式 #10 规避**：AC2 的 canonical 短语断言是产品契约守护，不是工具名硬编码——见上「反模式 #10 边界」
- ❌ **把指引放在 CLAUDE.md 之后**：本指引属 Axion 内核系统提示（mode-level），应放在 `loadClaudeMd`（`:92`）**之前**，不被项目 CLAUDE.md 覆盖
- ❌ **破坏 Path B `[结果]` 摘要契约**：Task 3 只**追加**指引到既有内联提示之后，不重写、不前置

### Project Structure Notes

- `Sources/AxionCLI/Services/AgentBuilder+PromptBuilding.swift`（修改：新增 `slashSkillAndTaskGuidance(noSkills:dryrun:)` static helper；`buildSystemPrompt` 在 `appendModeInstructions`（`:89`）后、`loadClaudeMd`（`:92`）前注入）
- `Sources/AxionCLI/Services/AgentBuilder.swift`（修改：`buildSkillAgent`（`:759`）内联 `systemPrompt:` 字面量提取为 `baseSkillPrompt` + 追加 `slashSkillAndTaskGuidance(noSkills:false, dryrun:false)` → `skillSystemPrompt`）
- `Tests/AxionCLITests/Services/AgentBuilderSlashSkillGuidanceTests.swift`（新增：AC1–AC5 的 Swift Testing @Test，≥7 个用例）
- **不碰** `Sources/AxionCLI/Services/AgentBuilder+Config.swift`（`forChat`/`forSkillExecution` 不涉 prompt）、`Sources/AxionCLI/Commands/ChatCommand.swift`（Path A 复用 chat agent 系统提示，无需改）、`Sources/AxionCLI/Chat/PermissionHandler.swift`（permission 不涉）、`Sources/AxionCLI/Config/AxionConfig.swift`（无新 config）、SDK `.build/checkouts/`
- 新文件归属 `AxionCLITests` testTarget，被 `make test`（等价 `--skip` 集成/E2E）命中

### References

- Epic：`docs/epics/epic-40-claude-code-skill-subagent-compat.md`
  - Story 40.7 章节（Slash-Skill Guidance for Child Agents）——本 story AC 直接对应 epic 的 CAP-3（slash-skill 执行）/CAP-1/CAP-2（Task 工具调用）
  - Story 间依赖（40.6 → **40.7** → 40.8 → …；40.7 依赖 40.3 的 Skill/Agent/Task 注册 + 40.4 的 discovered registry 继承 + 40.6 的 system-prompt 注入 seam 已稳定）
  - CAP-1（pipeline 顺序 Task 执行）、CAP-2（Task alias）、CAP-3（子代理执行 `/skill-name`）
  - 默认测试策略（`make test`，`:483-491`）
- SPEC：`_bmad-output/specs/spec-task-subagent-skill-compat/SPEC.md`（CAP-1/CAP-2/CAP-3；Constraints 第 66-68 行「优先复用 SDK 已有 public 符号」「不引入 Node/Python 编排层」；Non-goals 第 84 行「不让 `Task(...)` 代码块在宿主层被静态解析执行——执行仍由模型通过工具调用完成，但工具名和 **prompt guidance** 必须让该调用稳定可达、可测」——本 story 正是「prompt guidance 让调用稳定可达」）
- 架构：`_bmad-output/specs/spec-task-subagent-skill-compat/architecture.md`
  - **§4「Skill Command Guidance for Child Agents」第 109-125 行**（slash-skill 指引原文 + 「parent system prompt **or** child factory」取舍）——本 story AC2/Dev Notes 直接引用
  - §6「Axion Tool Registration Policy」第 153-168 行（noSkills 下 Task 仍注册但 skill pipeline 不能执行 `/skill-name`）
  - §8「Progress and Error Contract」第 192-207 行（child 失败时父停止——属 40.8，本 story 只在指引里提「stop and report the failed step」）
- 实施计划：`_bmad-output/specs/spec-task-subagent-skill-compat/implementation-plan.md`
  - **Phase 3 Task 8（第 86 行）**：「Add system prompt guidance for slash-form skill execution inside Task/Agent prompts when `Skill` and `Task` are both available」——本 story 直接对应
  - **Risks 表第 197-205 行**：「Model still prints `Task(...)` instead of calling tool → system prompt should say Claude Code Task snippets map to the `Task` tool」「Child agent treats `/skill` as chat → Add slash-skill guidance and ensure SkillTool is inherited」——本 story AC2 措辞锚点
- 测试计划：`_bmad-output/specs/spec-task-subagent-skill-compat/test-plan.md`（Axion Unit Tests 第 67 行：「prompt guidance | system prompt includes slash-skill guidance when Task and Skill are available」——本 story AC3 对应；Traceability CAP-3「prompt guidance and SkillTool inheritance tests」）
- 前置 Story：
  - `_bmad-output/implementation-artifacts/40-6-permission-allowlist-and-diagnostics-consistency.md`（已 done；Dev Notes 第 364/389 行明确「slash skill guidance 到 system prompt 属 40.7」「`AgentBuilder+PromptBuilding.swift` 属 40.7」——本 story 直接落地该 seam；40.6 的纯函数 helper 注入模式（`diagnoseToolAvailability`/`emitToolAvailabilityDiagnostics`）是本 story `slashSkillAndTaskGuidance` 的范式）
  - `_bmad-output/implementation-artifacts/40-3-register-agent-task-skill-across-agent-paths.md`（已 done；`buildToolProfile`/`buildSkillToolProfile` 注册 Skill/Agent/Task——本 story 的「同时可用」判定源自其注册门）
  - `_bmad-output/implementation-artifacts/40-4-direct-skill-uses-discovered-skill-registry.md`（已 done；`makeDiscoveredSkillRegistry` → 子代理继承全量 registry——本 story 的子代理「有 Skill 工具可用」前提）
- 代码事实（HEAD `fec2c96`，Axion 侧）：
  - `Sources/AxionCLI/Services/AgentBuilder+PromptBuilding.swift:46-98`（`buildSystemPrompt`；`:53`/`:55` `noSkills`/`dryrun` 参数；`:80` skillsPrompt；`:82-88` buildFullSystemPrompt；`:89` appendModeInstructions；`:92-95` loadClaudeMd——本 story Task 2 在 `:89`-`:92` 间注入）
  - `Sources/AxionCLI/Services/AgentBuilder+PromptBuilding.swift:101-117`（`appendModeInstructions`——本指引与之同层）、`:120-164`（`buildFullSystemPrompt`——**不**在此注入，见 Dev Notes）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:376-389`（`buildToolProfile` 注册门：Skill `!noSkills && !dryrun`、Agent/Task `!dryrun`——「同时可用」判定源）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:496-498`（`buildSkillToolProfile` 恒注册 Skill/Agent/Task——Path B 恒注入依据）
  - `Sources/AxionCLI/Services/AgentBuilder.swift:717-781`（`buildSkillAgent`；`:731` makeDiscoveredSkillRegistry；`:736` buildSkillToolProfile；`:744-749` 40.6 diagnostics；`:759` 内联 systemPrompt——本 story Task 3 改此行）
  - `Sources/AxionCLI/Services/AxionRuntime+SkillExecution.swift:9-70`（`executeSkill` → `buildSkillAgent` Path B 调用方——本 story 不改）
  - `Sources/AxionCLI/Commands/ChatCommand.swift:620`（Path A `executeSkillStream` 在 chat agent 上执行——复用 `buildSystemPrompt` 产物，故 Path A 父提示自动含指引）
- SDK API（`.build/checkouts/open-agent-sdk-swift` 0.10.0，commit `4285aac`，**全部 public**）：
  - `Sources/OpenAgentSDK/Tools/Advanced/AgentTool.swift:6-23`（`BUILTIN_AGENTS`——仅 Explore/Plan，无 general-purpose，故子系统提示 = nil）、`:238-258`（perform：`agentDef?.systemPrompt` → spawner）、`:294-314`（`createAgentTool()`/`createTaskTool()`，name `"Agent"`/`"Task"`——测试读 `.name`）
  - `Sources/OpenAgentSDK/Tools/Advanced/SkillTool.swift:34`/`:58`（`createSkillTool()` name `"Skill"`——测试读 `.name`）
  - `Sources/OpenAgentSDK/Core/DefaultSubAgentSpawner.swift:25-50`（`SubAgentInheritanceContext` **无 systemPrompt 字段**——Axion 无法注入子系统提示的铁证）、`:134-230`（`spawn` 把 `systemPrompt` 原样塞 AgentOptions，`:216`）、`:218-219`（继承 permissionMode/canUseTool——40.6 AC4 已锁定）
- 项目测试规则：`CLAUDE.md`（Swift Testing、单元测试 Mock、只跑单元测试、`make test`、反模式 #10 工具名不硬编码）
- 项目上下文：`_bmad-output/project-context.md`（AgentBuilder 职责 / `buildSystemPrompt` vs `buildSkillAgent` 双出口；反模式 #10）
- 记忆：`bmad-pipeline-stale-skill-names`（旧 BMAD 命令兼容——本 story 指引不硬编码 `bmad-*` 别名，命令名解析属 skill 包/alias，见架构 §6）

## Dev Agent Record

### Agent Model Used

glm-5.2[1m] (via Claude Code harness)

### Debug Log References

- `make test`（等价 `swift test --no-parallel --skip AxionHelperIntegrationTests --skip AxionCLIIntegrationTests --skip AxionE2ETests`）运行结果：**4027 tests / 266 suites，7 issues**——7 个 issue **全部**位于 `DesktopNotifier` 套件（OSC 9 / DCS `Ptmux;` passthrough），属本会话在 tmux 内（`TMUX=/private/tmp/tmux-501/default,97339,0`）的**环境性失败**，与本 story 代码改动**无关**（story Task 5.3 已预先记录该已知现象，40.5/40.6 Debug Log 同样命中）。**注意 `make` 退出码**：因这 7 个 DesktopNotifier 环境性失败，`make test` 退出码为非零（`Error 1` / 退出码 2）——这是**预先存在的环境性**退出，**非本 story 引入、非回归**。所有 in-scope 套件（40.2–40.6 + 40.7 + TaskSerialQueue）全部转绿。
- **范围校正（2026-06-16 checkpoint）**：此前 review 记录曾把 `TaskSerialQueueTests.swift` 的 flaky 修复写入 File List；复核 `fec2c963..df5ec07` 后确认 40.7 实现提交**未修改**该文件。该项保留为后续/工作树观察，不再计入 40.7 File List。
- **RED→GREEN 迭代**：首次 `make test` 我的套件有 2 个 @Test 失败——发现 Task 1.1 模板写 `` invoke the `Skill` tool ``（带反引号），与 Task 1.2 锁定的 canonical 短语 `"invoke the Skill tool"`（无反引号）冲突；同时 `"plain chat"` 被 wrap 拆行。按「措辞锁定——五个短语必须逐字保留」原则修正**实现**（去掉 `Skill` 外层反引号、把 `plain chat` 挪到同一行），二次 `make test` 全部 8 个 @Test 转绿。
- 验证零回归：40.2 `AgentBuilder.buildToolProfile`（7 @Test）、40.3 `AgentBuilder subagent tool registration`（5 @Test）、40.4 `AgentBuilder discovered skill registry`（6 @Test）、40.5 `AgentBuilder ToolSearch & MCP inheritance`（7 @Test）、40.6 `AgentBuilder permission & diagnostics consistency`（7 @Test）**全部 passed**——本 story 仅在 `buildSystemPrompt`/`buildSkillAgent` 的 systemPrompt **字符串**追加指引，不触工具池/注册/permission/diagnostics 逻辑，故这些断言（不读 systemPrompt）零影响。

### Completion Notes List

- ✅ **AC1**：`slashSkillAndTaskGuidance(noSkills:dryrun:) -> String?` 纯函数 helper 已新增于 `AgentBuilder+PromptBuilding.swift`，置于 `appendModeInstructions` 与 `buildFullSystemPrompt` 之间（mode-level helper 同层）。`guard !noSkills, !dryrun else { return nil }`——四象限真值表由 4 个 @Test（4.2.1–4.2.4）锁定。无副作用/无 resolveApiKey/无 MCP/无 Helper/无文件系统——只字符串拼接，同 `(noSkills,dryrun)` 输入恒定输出。
- ✅ **AC2**：提示块为单段 `## Skill & Subagent Execution (Claude Code Compatibility)`，含「slash-skill 执行」+「Task 工具调用」两条指引，措辞同源架构 §4 + implementation-plan Risk 表。五个 canonical 锁定短语已逐字保留：`"invoke the Skill tool"`、`"Do not treat the slash command as plain chat"`、`"Task(subagent_type:, description:, prompt:)"`、`` "invoke the `Task` tool" ``、`"Do not print the `Task(...)` snippet"`（4.2.5/4.2.6 子串断言锚定）。
- ✅ **AC3**：`buildSystemPrompt` 在 `appendModeInstructions` 之后、`loadClaudeMd` 之前注入 helper（`if let guidance = slashSkillAndTaskGuidance(...) { prompt += "\n\n\(guidance)" }`）。**签名零改动**（`noSkills`/`dryrun` 已是参数）；dry-run / `--no-skills` 时 helper 返回 nil → 不追加。注入位置在 CLAUDE.md **之前**（属 Axion 内核系统提示，不被项目 CLAUDE.md 覆盖）。4.2.8 wiring smoke 验证（含/不含对照组）。
- ✅ **AC4**：`buildSkillAgent`（Path B）把 `:759` 内联 `systemPrompt:` 字面量提取为 `baseSkillPrompt` 常量，拼接 `slashSkillAndTaskGuidance(noSkills:false, dryrun:false)`（skill 路径恒注册 Skill+Agent+Task → 恒非 nil）成 `skillSystemPrompt`，用于 `AgentOptions(systemPrompt:)`。**签名零改动**；既有「`[结果]` 摘要」契约完整保留（指引追加在其后）。AC4 不调真实 `buildSkillAgent()`（会 resolveApiKey + Helper）——遵循 story AC5 的降级策略：用纯 helper `slashSkillAndTaskGuidance(false,false)`（4.2.1/4.2.5/4.2.6 已证其非 nil + 含关键短语）+ Dev Notes 引用 `AgentBuilder.swift` 事实为证；真实 `buildSkillAgent` 行为由 40.3/40.4 测试间接覆盖。
- ✅ **AC5**：新增 `Tests/AxionCLITests/Services/AgentBuilderSlashSkillGuidanceTests.swift`（8 个 @Test，Swift Testing，**无 `import XCTest`**——`grep -E '^\s*import XCTest' Tests/` 返回空）。`make test` 复跑（Review 独立验证）：**4027 tests / 266 suites**，in-scope 全部转绿——40.7 套件（0.007s）、40.2–40.6 套件、`TaskSerialQueue` 套件（3.009s）均 passed；唯一失败为 `DesktopNotifier` 的 7 个环境性 issue（tmux OSC passthrough，非本 story 引入）。**退出码非零仅因 DesktopNotifier**（见 Debug Log），非回归。40.2–40.6 零回归。
- **反模式 #10 边界**已正确处理：AC2 的措辞断言是 SPEC/Risk 表 canonical 短语（产品契约守护），**非**工具名硬编码——故用子串匹配，不从工具实例读名。
- **已知 follow-up（非本 story 范围）**：子代理（Task/Agent 派生）系统提示由 SDK `DefaultSubAgentSpawner` 决定，`SubAgentInheritanceContext` 无 `systemPrompt` 字段——Axion 在「不编辑 SDK」约束下无法注入子系统提示。本 story 仅闭合**父**侧提示（架构 §4「或」的前一支）；子侧显式 slash 指引属 SDK follow-up（架构 §4「或」另一支 + §7 deferred）。CAP-3 的「可以」是能力可用性（Skill 工具 + registry 已被 40.3/40.4 继承），父侧提示补齐后链路在有能力的模型下稳定可达。

### File List

- `Sources/AxionCLI/Services/AgentBuilder+PromptBuilding.swift`（修改：新增 `slashSkillAndTaskGuidance(noSkills:dryrun:)` static 纯函数 helper；`buildSystemPrompt` 在 `appendModeInstructions` 后、`loadClaudeMd` 前注入该块）
- `Sources/AxionCLI/Services/AgentBuilder.swift`（修改：`buildSkillAgent` 内联 `systemPrompt:` 字面量提取为 `baseSkillPrompt` + 追加 `slashSkillAndTaskGuidance(noSkills:false, dryrun:false)` → `skillSystemPrompt`）
- `Tests/AxionCLITests/Services/AgentBuilderSlashSkillGuidanceTests.swift`（新增：AC1–AC5 的 Swift Testing @Test，8 个用例）

**范围说明（2026-06-16 checkpoint）**：`Tests/AxionCLITests/Services/Gateway/TaskSerialQueueTests.swift` 曾在 review 记录中作为 drive-by flaky 修复出现，但 `df5ec07` / `fec2c963..df5ec07` 未包含该文件改动，因此不属于 Story 40.7 实现 File List。

### Senior Developer Review (AI)

**Reviewer:** story-automator-review（adversarial review，autonomous auto-fix）
**Date:** 2026-06-15
**Outcome:** ✅ Approve → Status `done`（0 CRITICAL / 0 HIGH）

#### AC / Task 实现核验（逐条）

- **AC1 ✅**：`slashSkillAndTaskGuidance(noSkills:dryrun:) -> String?`（`AgentBuilder+PromptBuilding.swift:154`）为纯函数，`guard !noSkills, !dryrun else { return nil }` 四象限真值表由 4 个 @Test（4.2.1–4.2.4）锁定；无 resolveApiKey/MCP/Helper/文件系统副作用。
- **AC2 ✅**：单段 `## Skill & Subagent Execution (Claude Code Compatibility)`，Task 1.2 锁定的五个 canonical 短语**逐字保留**——`"invoke the Skill tool"`、`"Do not treat the slash command as plain chat"`、`"Task(subagent_type:, description:, prompt:)"`、`` "invoke the `Task` tool" ``、`"Do not print the `Task(...)` snippet"`（4.2.5/4.2.6 子串断言锚定）。多行字符串闭合 `"""` 缩进正确（8 空格剥离），生成的 markdown 行首无多余缩进。
- **AC3 ✅**：`buildSystemPrompt`（`:97-99`）在 `appendModeInstructions`（`:89`）后、`loadClaudeMd`（`:102`）前注入，签名零改动；4.2.8 wiring smoke 含「注入 / dryrun 不注入」对照组。
- **AC4 ✅**：`buildSkillAgent`（`AgentBuilder.swift:762-764`）把 `:759` 内联字面量提取为 `baseSkillPrompt`，拼接 `slashSkillAndTaskGuidance(false,false)` 成 `skillSystemPrompt`；既有 `[结果]` 摘要契约完整保留（仅追加），签名零改动。
- **AC5 ✅**：8 个 Swift Testing @Test，无 `import XCTest`；`make test` 独立复跑 in-scope 全绿（详见 Debug Log / 上方 AC5 note）。

#### Git vs Story 一致性

- 三个 File List 主张（两个 Source 修改 + 一个新增测试）与 40.7 实现提交 `df5ec07` / diff `fec2c963..df5ec07` 完全吻合。
- **2026-06-16 checkpoint 校正**：`TaskSerialQueueTests.swift` 属于此前 review/工作树观察，不属于 `df5ec07`；已从 40.7 File List 移出，避免把非本 story 提交内容误归因到 40.7。

#### Findings 与处置

- **🔴 CRITICAL：0**。所有 `[x]` task 经核验确已实现；无虚假主张。
- **🟠 HIGH：0**。AC1–AC5 全部实现；签名零改动；40.2–40.6 零回归。
- **🟡 MEDIUM：2（已 auto-fix）**
  - **M1 — 文档范围误归因（`TaskSerialQueueTests.swift`）**：2026-06-16 checkpoint 复核确认该文件不在 `df5ec07` / `fec2c963..df5ec07` 中，已从 40.7 File List 移出；作为后续/工作树观察保留，不计入本 story 实现范围。
  - **M2 — Debug Log 措辞不精确**（"`make test` 通过"）：实际 `make test` 因 7 个 DesktopNotifier 环境性失败而退出码非零。已把 Debug Log / AC5 Completion Notes 改写为「in-scope 全绿；退出码非零仅因 DesktopNotifier 环境性失败，非回归」，使记录与实际退出码一致（避免误导 sprint automator 的 pass/fail 信号）。
- **🟢 LOW：2（informational，不阻塞）**
  - **L1** — `grep -rl "import XCTest" Tests/` 返回 6 个文件，但**全部**是同一条 `禁止 \`import XCTest\`` 文档注释（40.2–40.7 套件共有），无真实 `import XCTest` 语句（`grep -E '^\s*import XCTest' Tests/` 为空）。CLAUDE.md 实质要求满足；注释使 proxy grep 噪音化属可接受代价（保留有益文档）。
  - **L2** — AC4 的 `baseSkillPrompt + guidance` 拼接逻辑无直接单测（仅经纯 helper 测试 + story AC5 明示的降级策略间接覆盖）。真实 `buildSkillAgent` 被 CLAUDE.md 禁止在测试中调用，story 已在 AC5/Dev Notes 显式接受此降级路径；拼接为平凡字符串运算，风险可忽略。
- **环境性观察（非本 story，不处置）**：`DesktopNotifier` 7 个失败为 tmux OSC 9/DCS passthrough 环境性断言失败（40.5/40.6 已记录），非 40.7 引入、非回归。CI 若跑 `make test` 会因它退出非零——属预先存在的环境性问题，超出 40.7 范围，留待 DesktopNotifier 套件单独治理（建议：检测 `TMUX` 后 skip/adjust OSC 断言）。

#### 零回归核验（Review 独立 `make test`）

| Suite | 结果 |
|-------|------|
| AgentBuilder slash-skill guidance (Story 40.7) | ✅ passed (0.007s) |
| AgentBuilder.buildToolProfile (Story 40.2) | ✅ passed |
| AgentBuilder subagent tool registration (Story 40.3) | ✅ passed |
| AgentBuilder discovered skill registry (Story 40.4) | ✅ passed |
| AgentBuilder ToolSearch & MCP inheritance (Story 40.5) | ✅ passed |
| AgentBuilder permission & diagnostics consistency (Story 40.6) | ✅ passed |
| TaskSerialQueue | ✅ passed (3.009s) |
| DesktopNotifier | ❌ 7 issues（环境性，见上） |

**Status 判定**：0 CRITICAL → `done`。

## Change Log

- 2026-06-15 — Story 40.7 创建：新增 `slashSkillAndTaskGuidance(noSkills:dryrun:)` 纯函数 helper（架构 §4 slash-skill 执行指引 + implementation-plan Risk 表 Task 工具调用指引，`!noSkills && !dryrun` 时返回提示块）；`buildSystemPrompt`（Path A / run）与 `buildSkillAgent`（Path B）父 agent 系统提示注入该块（闭合 CAP-1/CAP-2/CAP-3 提示缺口）。子代理系统提示注入属 SDK follow-up（架构 §4「或」另一支），本 story 不编辑 SDK。状态 → ready-for-dev。
- 2026-06-15 — Story 40.7 实现完成（dev）：三处代码改动 + 8 个 Swift Testing @Test 全绿；`make test` 4027 测试仅余 7 个 DesktopNotifier 环境性失败（tmux OSC passthrough，非回归）。修正了 Task 1.1 模板（`` `Skill` `` 带反引号）与 Task 1.2 锁定短语（`Skill` 无反引号）的冲突——以锁定短语为唯一真源。状态 → review。
- 2026-06-15 — Story 40.7 adversarial review（story-automator-review，autonomous）：核验 AC1–AC5 全部实现、五个 canonical 短语逐字保留、签名零改动、40.2–40.6 零回归；**0 CRITICAL / 0 HIGH**。修复 Debug Log / AC5 Notes 的「`make test` 通过」措辞，使其与实际退出码一致（in-scope 全绿；退出码非零仅因 DesktopNotifier 环境性失败）。Review 独立复跑 `make test` 确认 40.7 套件 + 40.2–40.6 + TaskSerialQueue 全绿，仅 DesktopNotifier 7 个环境性失败。状态 → done。
- 2026-06-16 — Checkpoint 文档范围校正：复核 40.7 实现提交 `df5ec07` 与 baseline diff `fec2c963..df5ec07`，确认 `TaskSerialQueueTests.swift` 不属于 Story 40.7 提交内容；从 File List 移除，仅作为后续/工作树观察保留，避免审计追溯误归因。
