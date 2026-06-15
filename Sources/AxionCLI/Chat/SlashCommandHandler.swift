import AxionCore
import Foundation
import OpenAgentSDK

/// SlashCommandHandler.handle() 的返回类型。

/// SlashCommandHandler.handle() 的返回类型。
///
/// 支持 REPL 循环根据不同 action 执行不同的后续逻辑。
enum SlashCommandAction: Equatable, Sendable {
    case none              // 继续循环
    case exit              // 退出 REPL
    case resumeSession(String)  // 恢复指定 session
    case newSession                                    // AC1: /new (38.7)
    case forkSession(newId: String, sourceId: String)  // AC2: /fork (38.7)
    case archiveSession                                // AC3: /archive (38.7)
}

/// 处理 REPL 斜杠命令的具体逻辑。
///
/// 所有方法为 `static`，不持有状态。`Agent` 等引用通过参数传入。
struct SlashCommandHandler {

    // MARK: - Public entry point

    /// 处理 slash 命令。返回 action 指示 REPL 循环的后续行为。
    static func handle(
        _ command: SlashCommand,
        argument: String?,
        agent: Agent,
        config: AxionConfig,
        sessionUsage: TokenUsage,
        buildConfig: AgentBuilder.BuildConfig,
        contextWindow: Int = 0,
        contextTokens: Int = 0,
        isAgentBusy: Bool = false,  // AC6: 38.7
        skillRegistry: SkillRegistry? = nil,
        lastAssistantText: String = "",  // /copy 需要
        sessionStartTime: ContinuousClock.Instant? = nil,
        sessionTurnCount: Int = 0,
        sessionTotalTools: Int = 0,
        sessionToolUsage: ToolUsageTracker = ToolUsageTracker()
    ) -> SlashCommandAction {
        switch command {
        case .help:
            fputs(handleHelp(), stderr)
        case .clear:
            return .none  // 由 ChatCommand 直接处理上下文清理
        case .compact:
            fputs(handleCompact(contextTokens: contextTokens, contextWindow: contextWindow), stderr)
        case .model:
            handleModel(argument: argument, agent: agent)
        case .cost:
            fputs(handleCost(usage: sessionUsage, model: agent.model, contextTokens: contextTokens, contextWindow: contextWindow), stderr)
        case .resume:
            return handleResume(argument: argument)
        case .config:
            fputs(
                handleConfig(
                    model: agent.model,
                    maxTokens: buildConfig.maxTokens ?? 4096,
                    maxSteps: buildConfig.maxSteps ?? config.maxSteps,
                    noMemory: buildConfig.noMemory,
                    noSkills: buildConfig.noSkills,
                    permissionMode: PermissionHandler.modeDisplayName(buildConfig.permissionMode)
                ),
                stderr
            )
        case .diff: // AC4
            fputs(
                handleDiff(
                    cwd: FileManager.default.currentDirectoryPath,
                    processLauncher: defaultProcessLauncher
                ),
                stderr
            )
        case .status: // AC5
            fputs(
                handleStatus(
                    model: agent.model,
                    permissionMode: PermissionHandler.modeDisplayName(buildConfig.permissionMode),
                    sessionId: buildConfig.sessionId ?? "unknown",
                    contextTokens: contextTokens,
                    contextWindow: contextWindow,
                    cwd: FileManager.default.currentDirectoryPath,
                    usage: sessionUsage,
                    sessionStartTime: sessionStartTime,
                    turnCount: sessionTurnCount,
                    totalToolsUsed: sessionTotalTools,
                    toolUsage: sessionToolUsage
                ),
                stderr
            )
        case .newSession:    // 38.7 AC1/AC6
            if isAgentBusy {
                fputs(SessionWorkflowHandler.formatAgentBusy("new"), stderr)
                return .none
            }
            return .newSession
        case .fork:          // 38.7 AC2/AC6 — async, handled in ChatCommand
            return .none
        case .archive:       // 38.7 AC3/AC6 — async, handled in ChatCommand
            return .none
        case .exit:
            return .exit
        case .skills:
            fputs(handleSkills(registry: skillRegistry), stderr)
        case .copy:
            fputs(handleCopy(lastAssistantText: lastAssistantText), stderr)
        case .mcp:
            fputs(handleMCPStatus(config: config, buildConfig: buildConfig), stderr)
        case .apps:
            return .none
        case .arch:
            return .none
        case .storage:
            return .none
        }
        return .none
    }

    // MARK: - Individual handlers

    /// /help — 格式化输出命令列表和键盘快捷键。
    ///
    /// Codex-inspired: 在命令列表下方追加快捷键分组提示，
    /// 帮助用户发现编辑、导航、队列等交互操作。
    static func handleHelp() -> String {
        // 动态计算命令名列宽：rawValue 最大字符数 + 2（间距）
        let maxNameWidth = SlashCommand.allCases.map(\.rawValue.count).max() ?? 0
        let columnWidth = max(maxNameWidth + 2, 12)
        var lines = ["可用命令:\n"]
        for cmd in SlashCommand.allCases {
            lines.append("  \(cmd.rawValue.padding(toLength: columnWidth, withPad: " ", startingAt: 0))\(cmd.helpText)")
        }
        lines.append("  /quit".padding(toLength: columnWidth + 2, withPad: " ", startingAt: 0) + "退出交互模式（/exit 同义）")
        lines.append("")
        lines.append(KeyHintsFormatter.renderFull())
        return lines.joined(separator: "\n") + "\n"
    }

    /// /clear — ANSI escape 清屏。
    static func handleClear() {
        fputs("\u{1B}[2J\u{1B}[H", stdout)
        fflush(stdout)
    }

    /// /model — 生成显示当前模型名称的文本（无参数时）。
    static func handleModelDisplay(model: String) -> String {
        "当前模型: \(model)\n"
    }

    /// /model — 生成切换模型成功的确认文本。
    static func handleModelSwitchSuccess(_ modelName: String) -> String {
        "[axion] 模型已切换为 \(modelName)\n"
    }

    /// /model — 生成切换失败的错误文本。
    static func handleModelSwitchError(_ error: Error) -> String {
        "[axion] 切换失败: \(error.localizedDescription)\n"
    }

    /// /model — 显示当前模型或切换模型。
    static func handleModel(argument: String?, agent: Agent) {
        if let arg = argument, !arg.isEmpty {
            do {
                try agent.switchModel(arg)
                fputs(handleModelSwitchSuccess(arg), stderr)
            } catch {
                fputs(handleModelSwitchError(error), stderr)
            }
        } else {
            fputs(handleModelDisplay(model: agent.model), stderr)
        }
    }

    /// /config — 显示当前生效的关键配置项。
    static func handleConfig(
        model: String,
        maxTokens: Int,
        maxSteps: Int,
        noMemory: Bool,
        noSkills: Bool,
        permissionMode: String
    ) -> String {
        """
        当前配置:
          模型:         \(model)
          最大输出:     \(maxTokens) tokens
          最大步骤:     \(maxSteps)
          Memory:       \(noMemory ? "关闭" : "开启")
          技能系统:     \(noSkills ? "关闭" : "开启")
          权限模式:     \(permissionMode)

        """
    }

    /// /compact — 显示当前上下文状态（同步降级版本）。
    ///
    /// 用于 `handle()` 内部同步调用路径。实际压缩由 ``handleCompactNow(agent:contextTokens:contextWindow:)`` 执行。
    static func handleCompact(contextTokens: Int = 0, contextWindow: Int = 0) -> String {
        ContextManager.formatCompactStatus(
            usedTokens: contextTokens,
            contextWindow: contextWindow
        )
    }

    /// /compact — 手动触发上下文压缩，显示压缩结果。
    ///
    /// 调用 `agent.compactNow()` 执行实际压缩。如果无 session store 或压缩失败，
    /// 降级显示当前上下文状态。
    /// 由 ChatCommand 在 REPL 循环中直接 await 调用（不经过同步的 `handle()` 路径）。
    static func handleCompactNow(agent: Agent, contextTokens: Int = 0, contextWindow: Int = 0) async -> String {
        let result = await agent.compactNow()
        if result.success && result.preTokens > 0 {
            return ContextManager.formatCompactMessage(
                beforeTokens: result.preTokens,
                afterTokens: result.postTokens,
                contextWindow: contextWindow
            )
        } else if !result.success {
            return "[axion] ⚠️ 上下文压缩失败: \(result.error ?? "未知错误")\n"
        }
        // No session or empty — show status
        return ContextManager.formatCompactStatus(
            usedTokens: contextTokens,
            contextWindow: contextWindow
        )
    }

    /// /resume — 处理会话恢复请求。
    ///
    /// 无参数时返回 `.none`（由 ChatCommand 显示会话列表），
    /// 有参数时返回 `.resumeSession(id)`（由 ChatCommand 执行 agent 重建）。
    static func handleResume(argument: String?) -> SlashCommandAction {
        guard let arg = argument, !arg.isEmpty else {
            // 无参数 — 通知 ChatCommand 显示会话列表
            return .none
        }
        return .resumeSession(arg)
    }

    /// /unknown — 未知命令提示。
    static func handleUnknown(_ input: String) -> String {
        "[axion] 未知命令: \(input)，输入 /help 查看可用命令\n"
    }

    /// /skills — 列出所有可用技能。
    ///
    /// 从 `SkillRegistry` 获取 `userInvocableSkills`，格式化输出名称、描述和来源。
    static func handleSkills(registry: SkillRegistry?) -> String {
        guard let registry else {
            return "[axion] 技能系统未启用\n"
        }
        let skills = registry.userInvocableSkills.sorted { $0.name < $1.name }
        guard !skills.isEmpty else {
            return "暂无可用技能\n"
        }

        // 计算列宽（包含 [fs] 标记）
        let displayNameWidths = skills.map { skill in
            let tag = skill.baseDir != nil ? " [fs]" : ""
            return (skill.name + tag).count
        }
        let columnWidth = max((displayNameWidths.max() ?? 0) + 2, 12)

        var lines = ["可用技能:\n"]
        for skill in skills {
            let sourceTag: String
            if skill.baseDir != nil {
                sourceTag = " [fs]"
            } else {
                sourceTag = ""
            }
            let namePart = (skill.name + sourceTag).padding(toLength: columnWidth, withPad: " ", startingAt: 0)
            let desc = skill.description.count > 60
                ? String(skill.description.prefix(57)) + "..."
                : skill.description
            lines.append("  \(namePart)\(desc)")
            if !skill.aliases.isEmpty {
                lines.append("  \("".padding(toLength: columnWidth, withPad: " ", startingAt: 0))别名: \(skill.aliases.joined(separator: ", "))")
            }
        }
        lines.append("\n提示: 直接输入 /技能名 即可执行，例如 /\(skills[0].name)")
        return lines.joined(separator: "\n") + "\n"
    }

    /// /copy — 复制最后一条 assistant 响应到剪贴板。
    ///
    /// Codex-inspired (clipboard_copy.rs): 支持多种剪贴板后端自动降级。
    /// 使用 ClipboardService 执行实际复制操作。
    ///
    /// - Parameters:
    ///   - lastAssistantText: 最后一条 assistant 响应文本
    ///   - copyFn: 剪贴板复制闭包（默认使用 ClipboardService.copy）
    static func handleCopy(
        lastAssistantText: String,
        copyFn: (String) -> ClipboardService.CopyResult = { ClipboardService.copy(text: $0) }
    ) -> String {
        guard !lastAssistantText.isEmpty else {
            return ClipboardService.formatNoContent()
        }

        let result = copyFn(lastAssistantText)
        switch result {
        case .success(let backend):
            return ClipboardService.formatSuccess(
                backend: backend,
                charCount: lastAssistantText.count
            )
        case .failure(let error):
            return ClipboardService.formatFailure(error)
        }
    }
}
