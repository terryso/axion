import Foundation
import OpenAgentSDK

import AxionCore

extension AgentBuilder {

    // MARK: - Memory Context

    /// Builds both fact-based and universal memory contexts for `buildSystemPrompt`.
    static func buildMemoryContexts(
        task: String,
        memoryStore: FileBasedMemoryStore,
        memoryDir: String,
        noMemory: Bool
    ) async -> (memoryContext: String?, universalMemoryContext: String?) {
        guard !noMemory else { return (nil, nil) }

        let contextProvider = MemoryContextProvider()
        let factStore = AxionFactStore(memoryDir: memoryDir)

        var memoryContext: String?
        do {
            if let factContext = await contextProvider.buildFactMemoryContext(
                task: task,
                factStore: factStore
            ) {
                memoryContext = factContext
            } else {
                memoryContext = try await contextProvider.buildMemoryContext(
                    task: task,
                    store: memoryStore
                )
            }
        } catch {
            // Non-fatal: continue without memory context
        }

        let universalMemoryContext = await contextProvider.buildUniversalMemoryContext(memoryDir: memoryDir)
        return (memoryContext, universalMemoryContext)
    }

    // MARK: - Desktop Automation Prompt

    /// Builds the full system prompt for desktop automation.
    static func buildSystemPrompt(
        config: AxionConfig,
        task: String,
        memoryStore: FileBasedMemoryStore,
        memoryDir: String,
        skillRegistry: SkillRegistry,
        noMemory: Bool,
        noSkills: Bool,
        fast: Bool,
        dryrun: Bool,
        includeSaveSkillGuidance: Bool = false
    ) async -> String {
        let promptDir = PromptBuilder.resolvePromptDirectory()
        let mcpPrefixedToolNames = ToolNames.allToolNames.map { "mcp__axion-helper__\($0)" }
        let cwd = FileManager.default.currentDirectoryPath

        // Memory context
        let (memoryContext, universalMemoryContext) = await buildMemoryContexts(
            task: task,
            memoryStore: memoryStore,
            memoryDir: memoryDir,
            noMemory: noMemory
        )

        let baseSystemPrompt = (try? PromptBuilder.load(
            name: "planner-system",
            variables: [
                "tools": PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames),
                "max_steps": String(config.maxSteps),
                "cwd": cwd,
            ],
            fromDirectory: promptDir
        )) ?? ""

        let skillsPrompt = noSkills ? "" : skillRegistry.formatSkillsForPrompt()

        var prompt = buildFullSystemPrompt(
            basePrompt: baseSystemPrompt,
            memoryContext: memoryContext,
            universalMemoryContext: universalMemoryContext,
            skillsPrompt: skillsPrompt,
            includeSaveSkillGuidance: includeSaveSkillGuidance
        )
        prompt = appendModeInstructions(to: prompt, fast: fast, dryrun: dryrun)

        // Story 40.7: inject Claude Code skill/subagent compatibility guidance when both the Skill
        // and Task tools are registered (i.e. !noSkills && !dryrun). Tells the model to execute
        // /skill-name via the Skill tool and to call the Task tool for Task(...) snippets instead of
        // printing them — closes CAP-1/CAP-2/CAP-3 prompt gap (architecture §4 + impl-plan Risk table).
        // Placed after appendModeInstructions (mode-level guidance, same layer) and before CLAUDE.md
        // (this is Axion-kernel system prompt, not user project instruction — must not be overridden).
        if let guidance = slashSkillAndTaskGuidance(noSkills: noSkills, dryrun: dryrun) {
            prompt += "\n\n\(guidance)"
        }

        // Append CLAUDE.md project instructions — shared by run and interactive chat
        let claudeMdContent = loadClaudeMd(cwd: cwd)
        if !claudeMdContent.isEmpty {
            prompt += "\n\n\(claudeMdContent)"
        }

        return prompt
    }

    /// Appends fast/dryrun mode instructions to a system prompt.
    static func appendModeInstructions(to prompt: String, fast: Bool, dryrun: Bool) -> String {
        var prompt = prompt
        if fast {
            prompt += """

            IMPORTANT: You are in FAST mode. Generate the MINIMUM steps needed (1-3 steps max).
            - Skip discovery steps (list_apps, list_windows, get_accessibility_tree) when the target app is obvious
            - Do NOT call screenshot for verification — trust tool results
            - Prefer direct actions (launch_app, type_text, hotkey) over exploration
            - If a step fails, do NOT retry with alternative approaches — report failure immediately
            """
        }
        if dryrun {
            prompt += "\n\nIMPORTANT: You are in DRYRUN mode. Generate a plan but do NOT execute any tools. Return a plan JSON with status 'done' and the steps you would execute."
        }
        return prompt
    }

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
    /// 耦合点（单源真值）：「Skill 与 Task 同时可用」⟺ `!noSkills && !dryrun` 投影自
    /// `buildToolProfile` 的注册门（Skill: `!noSkills && !dryrun`；Agent/Task: `!dryrun`，
    /// `AgentBuilder.swift:376-389`）。若未来 40.3 的注册门改变，本 guard 同步更新。
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
          (for example `Execute /bmad-create-story 1-1 yolo`), invoke the Skill tool with
          `skill="<skill-name>"` and `args="<args>"`. Do not treat the slash command as plain chat
          text — it is an instruction to run that skill.
        - **Task tool calls**: When a skill's content tells you to call
          `Task(subagent_type:, description:, prompt:)` or `Agent(...)` to spawn a child agent,
          invoke the `Task` tool with those arguments. Do not print the `Task(...)` snippet as
          plain text. Each Task call runs its child to completion before you continue to the
          next step; if a child fails, stop and report the failed step.
        """
    }

    /// Builds the full system prompt with memory context and skills section appended.
    static func buildFullSystemPrompt(
        basePrompt: String,
        memoryContext: String? = nil,
        universalMemoryContext: String? = nil,
        skillsPrompt: String = "",
        includeSaveSkillGuidance: Bool = false
    ) -> String {
        var prompt = basePrompt

        if let memoryContext, !memoryContext.isEmpty {
            prompt += "\n\n\(memoryContext)"
        }

        if let universalMemoryContext, !universalMemoryContext.isEmpty {
            prompt += "\n\n\(universalMemoryContext)"
        }
        prompt += """

        ## Universal Memory Operations

        Treat Universal Memory as long-lived memory, not live repository state.
        - If the user asks you to remember or save a durable preference/fact, use the `memory` tool with `add`.
        - If the user corrects, updates, or rephrases something already in Universal Memory, prefer the `memory` tool with `replace` (or `remove` + `add`) instead of searching the repo or editing files, unless the user explicitly asks to change code, docs, or configuration.
        - If the user asks you to forget or delete a remembered preference/fact, use the `memory` tool with `remove`.
        - For explicit memory-management requests (`remember/save/update/delete this memory`), do not short-circuit based on your own safety judgment. Call the `memory` tool first and let its security scanner accept or reject the content.
        - If the `memory` tool rejects content with `security_rejection`, tell the user that the save/update was blocked by the security scanner and do not fall back to storing it elsewhere.
        - Use target `user` for personal preferences and target `memory` for durable project/environment facts.
        """
        if includeSaveSkillGuidance {
            prompt += "\n- When you identify a reusable pattern, user preference, or workflow during conversation, use the `save_skill` tool to persist it as a skill. Saved skills are written to disk and automatically loaded in future sessions. Skills should be class-level general instructions, not session-level temporary notes."
        }

        if !skillsPrompt.isEmpty {
            prompt += """

            ## Available Skills

            When the user's task matches a skill's TRIGGER condition, call the `Skill` tool with the skill name and arguments. Parameters: `skill` (skill name, required) and `args` (user arguments, optional). The tool returns a JSON with `prompt` (the skill's prompt template) — follow that prompt as your operating instructions for the rest of the task.

            \(skillsPrompt)
            """
        }

        return prompt
    }

    // MARK: - Coding Agent Prompt

    /// Loads and merges CLAUDE.md instruction files from standard paths.
    ///
    /// Scans in priority order:
    /// 1. `<homeDir>/.claude/CLAUDE.md` — global instructions
    /// 2. `<cwd>/.claude/CLAUDE.md` — project team instructions
    /// 3. `<cwd>/CLAUDE.md` — project root instructions
    /// 4. `<cwd>/.axion/instructions.md` — Axion-specific instructions (optional)
    static func loadClaudeMd(cwd: String, homeDir: String = NSHomeDirectory()) -> String {
        var parts: [String] = []
        let candidates = [
            homeDir + "/.claude/CLAUDE.md",
            cwd + "/.claude/CLAUDE.md",
            cwd + "/CLAUDE.md",
            cwd + "/.axion/instructions.md",
        ]
        for path in candidates {
            if let content = try? String(contentsOfFile: path),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                let fileName = URL(fileURLWithPath: path).lastPathComponent
                parts.append("## 项目指令 (\(fileName))\n\(content)")
            }
        }
        return parts.joined(separator: "\n\n")
    }

}
