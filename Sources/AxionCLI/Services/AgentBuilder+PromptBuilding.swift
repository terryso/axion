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
