import OpenAgentSDK

import AxionCore

extension AgentBuilder {

    // MARK: - Configuration

    /// Agent operation mode — determines prompt template and tool selection.
    enum AgentMode: String, Sendable {
        case desktopAutomation  // axion run — desktop automation via Helper MCP
        case codingAgent        // axion (interactive chat) — coding-focused agent
    }

    struct BuildConfig: Sendable {
        let config: AxionConfig
        let task: String
        let noMemory: Bool
        let noSkills: Bool
        let includePlaywright: Bool
        let allowForeground: Bool
        let maxSteps: Int?
        let maxTokens: Int?
        let verbose: Bool
        let dryrun: Bool
        let fast: Bool
        let runId: String?
        let sessionId: String?
        let sessionStore: SessionStore?
        let emitTokenStream: Bool
        let mode: AgentMode
        let permissionMode: PermissionMode
        let canUseTool: CanUseToolFn?

        static func forCLI(
            config: AxionConfig,
            task: String,
            noMemory: Bool = false,
            noSkills: Bool = false,
            allowForeground: Bool = false,
            maxSteps: Int? = nil,
            maxTokens: Int? = nil,
            verbose: Bool = false,
            dryrun: Bool = false,
            fast: Bool = false,
            runId: String? = nil,
            sessionId: String? = nil,
            sessionStore: SessionStore? = nil
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: task,
                noMemory: noMemory,
                noSkills: noSkills,
                includePlaywright: true,
                allowForeground: allowForeground,
                maxSteps: maxSteps,
                maxTokens: maxTokens,
                verbose: verbose,
                dryrun: dryrun,
                fast: fast,
                runId: runId,
                sessionId: sessionId,
                sessionStore: sessionStore,
                emitTokenStream: false,
                mode: .desktopAutomation,
                permissionMode: .bypassPermissions,
                canUseTool: nil
            )
        }

        /// Build config for interactive chat mode (`axion` with no arguments).
        /// Uses coding-agent system prompt, 128K max tokens, and no MCP/Playwright.
        static func forChat(
            config: AxionConfig,
            noMemory: Bool = false,
            noSkills: Bool = false,
            maxSteps: Int? = nil,
            verbose: Bool = false,
            sessionId: String? = nil,
            sessionStore: SessionStore? = nil,
            permissionMode: PermissionMode = .default,
            canUseTool: CanUseToolFn? = nil
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: "",
                noMemory: noMemory,
                noSkills: noSkills,
                includePlaywright: false,
                allowForeground: false,
                maxSteps: maxSteps,
                maxTokens: 131_072,  // 128K
                verbose: verbose,
                dryrun: false,
                fast: false,
                runId: sessionId,
                sessionId: sessionId,
                sessionStore: sessionStore,
                emitTokenStream: false,
                mode: .codingAgent,
                permissionMode: permissionMode,
                canUseTool: canUseTool
            )
        }

        static func forAPI(
            config: AxionConfig,
            task: String,
            request: CreateRunRequest
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: task,
                noMemory: false,
                noSkills: false,
                includePlaywright: false,
                allowForeground: request.allowForeground ?? false,
                maxSteps: request.maxSteps,
                maxTokens: nil,
                verbose: false,
                dryrun: false,
                fast: false,
                runId: nil,
                sessionId: nil,
                sessionStore: nil,
                emitTokenStream: false,
                mode: .desktopAutomation,
                permissionMode: .bypassPermissions,
                canUseTool: nil
            )
        }

        /// Build config for skill execution via SDK's `executeSkillStream()`.
        /// Creates a minimal agent: no MCP, no SkillTool, core tools only (no ToolSearch/AskUser).
        static func forSkillExecution(
            config: AxionConfig,
            skill: OpenAgentSDK.Skill,
            maxSteps: Int? = nil,
            verbose: Bool = false
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: "",
                noMemory: true,
                noSkills: true,
                includePlaywright: false,
                allowForeground: false,
                maxSteps: maxSteps,
                maxTokens: nil,
                verbose: verbose,
                dryrun: false,
                fast: false,
                runId: nil,
                sessionId: nil,
                sessionStore: nil,
                emitTokenStream: false,
                mode: .desktopAutomation,
                permissionMode: .bypassPermissions,
                canUseTool: nil
            )
        }

        /// Build config for MCP Server mode (`axion mcp`).
        /// No skills, no Playwright, no fast/dryrun modes. Memory context included.
        static func forMCP(
            config: AxionConfig,
            verbose: Bool = false
        ) -> BuildConfig {
            BuildConfig(
                config: config,
                task: "",
                noMemory: false,
                noSkills: true,
                includePlaywright: false,
                allowForeground: false,
                maxSteps: nil,
                maxTokens: nil,
                verbose: verbose,
                dryrun: false,
                fast: false,
                runId: nil,
                sessionId: nil,
                sessionStore: nil,
                emitTokenStream: false,
                mode: .desktopAutomation,
                permissionMode: .bypassPermissions,
                canUseTool: nil
            )
        }
    }
}
