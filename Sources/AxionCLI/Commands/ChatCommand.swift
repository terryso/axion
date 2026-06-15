import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

private final class CurrentChatAgentReference: @unchecked Sendable {
    private let lock = NSLock()
    private var agent: Agent

    init(_ agent: Agent) {
        self.agent = agent
    }

    func update(_ agent: Agent) {
        lock.lock()
        self.agent = agent
        lock.unlock()
    }

    func interrupt() {
        lock.lock()
        let agent = self.agent
        lock.unlock()
        agent.interrupt()
    }

    /// 从 `.system(.paused)` 恢复执行，注入人类上下文。镜像 `interrupt()` 的加锁访问模式。
    func resume(context: String) {
        lock.lock()
        let agent = self.agent
        lock.unlock()
        agent.resume(context: context)
    }
}

/// Interactive multi-turn chat mode — `axion` with no arguments.
///
/// Uses `agent.stream()` per turn for full streaming events (partial messages,
/// tool use, tool results) with session-persisted conversation history.
/// MCP connections are reused across turns via cached MCPClientManager.
struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "交互模式：多轮对话"
    )

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    @Flag(name: .long, help: "禁用 Memory 上下文注入")
    var noMemory: Bool = false

    @Flag(name: .long, help: "禁用技能系统")
    var noSkills: Bool = false

    @Option(name: .long, help: "单次运行最大步骤数")
    var maxSteps: Int?

    @Flag(name: .long, help: "自动允许文件编辑")
    var acceptEdits: Bool = false

    @Flag(name: .long, help: "跳过所有权限确认")
    var dangerouslySkipPermissions: Bool = false

    mutating func run() async throws {
        let cliOverrides = CLIOverrides(maxSteps: maxSteps)
        let config = try await ConfigManager.loadConfig(cliOverrides: cliOverrides)

        let sessionsDir = ConfigManager.sessionsDirectory
        let sessionId = "chat-\(UUID().uuidString.prefix(8))"

        // Compute permission mode from CLI flags
        let permissionMode = PermissionHandler.resolveMode(
            acceptEdits: acceptEdits,
            dangerouslySkipPermissions: dangerouslySkipPermissions
        )

        // AC3: Session allow list — shared across all canUseTool callbacks in this REPL session
        let sessionAllowList = SessionAllowListRef()

        // ESC listener ref — bridges per-turn listener lifecycle to the once-created canUseTool closure
        let escListenerRef = EscapeInterruptListenerRef()

        // Create canUseTool callback (controls tool-level permissions)
        // AC3/AC5: v2 overload injects sessionAllowList for dynamic approval options
        // escListenerRef: pauses ESC listener before rendering prompt, resumes after read
        // Story 39.4: surfaceApproving — chat 逐项审批 storage execute 工具（计划项级，正交于工具级权限）。
        let storageCollector = ChatApprovalCollector(
            writeStdout: { msg in fputs(msg, stderr) },
            readLine: { Swift.readLine() }
        )
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: permissionMode,
            sessionAllowList: sessionAllowList,
            escListenerRef: escListenerRef,
            surfaceApproving: storageCollector
        )

        let buildParams = ChatREPLState.BuildParams(
            config: config,
            noMemory: noMemory,
            noSkills: noSkills,
            maxSteps: maxSteps,
            verbose: verbose,
            permissionMode: permissionMode,
            canUseTool: canUseTool
        )

        let buildConfig = AgentBuilder.BuildConfig.forChat(
            config: config,
            noMemory: noMemory,
            noSkills: noSkills,
            maxSteps: maxSteps,
            verbose: verbose,
            sessionId: sessionId,
            sessionStore: SessionStore(sessionsDir: sessionsDir),
            permissionMode: permissionMode,
            canUseTool: canUseTool
        )

        var buildResult: AgentBuildResult
        let buildMs: Int
        do {
            let buildStart = ContinuousClock.now
            buildResult = try await AgentBuilder.build(buildConfig)
            let buildElapsed = ContinuousClock.now - buildStart
            buildMs = durationToMs(buildElapsed)
        } catch {
            fputs("[axion] 初始化失败: \(error.localizedDescription)\n", stderr)
            throw ExitCode(1)
        }

        // 抑制 SDK 内部的 Ctrl+C 取消错误日志（JSON 输出到 stderr）
        // Agent.init() 已配置 Logger，这里覆盖 output 为自定义过滤器
        Logger.configure(level: verbose ? .debug : .info, output: .custom { jsonLine in
            // 过滤 Ctrl+C 导致的 api_error + cancelled — 不是真正的错误
            if jsonLine.contains("\"api_error\"") && jsonLine.contains("\"cancelled\"") {
                return
            }
            FileHandle.standardError.write((jsonLine + "\n").data(using: .utf8) ?? Data())
        })

        // AC1: 启动横幅 — 显示版本、模型、CWD、session ID、上下文窗口、构建耗时
        let contextWindow = getContextWindowSize(model: buildResult.agent.model)
        fputs(
            BannerRenderer.renderBanner(
                version: AxionVersion.current,
                model: buildResult.agent.model,
                cwd: FileManager.default.currentDirectoryPath,
                sessionId: sessionId,
                contextWindow: contextWindow,
                buildTimeMs: buildMs
            ),
            stderr
        )

        // Terminal title — Codex-inspired tab bar status
        let terminalTitle = TerminalTitleRenderer()
        terminalTitle.setIdle()

        // Desktop notifications — Codex-inspired OSC 9 / BEL pattern
        let desktopNotifier = DesktopNotifier()

        // Initialize REPL state
        var state = ChatREPLState(
            buildResult: buildResult,
            buildConfig: buildConfig,
            sessionId: sessionId,
            sessionUsage: TokenUsage(inputTokens: 0, outputTokens: 0),
            contextTokens: 0,
            contextWindow: contextWindow,
            sessionUserMessages: [],
            resumedMessageBaseCount: 0,
            lastInterruptTime: nil,
            lastResumeList: [],
            consecutiveCompactFailures: 0
        )

        // Skill registry — 用于 /skills 列表和 /skill-name 直接执行
        let skillRegistry: SkillRegistry?
        if !noSkills {
            let registry = SkillRegistry()
            AxionBuiltInSkills.registerAll(into: registry)
            registry.registerDiscoveredSkills(from: ConfigManager.skillDiscoveryDirectories)
            skillRegistry = registry
        } else {
            skillRegistry = nil
        }

        // Agent reference for SIGINT handler. Session switches update the
        // reference while the installed signal handler remains stable.
        let currentAgent = CurrentChatAgentReference(state.buildResult.agent)
        SignalHandler.install {
            currentAgent.interrupt()
        }

        // Cross-session command history (Codex-inspired)
        let historyStore = CommandHistoryStore.live()
        let historyPath = ConfigManager.historyFilePath
        let persistentHistory = historyStore.load(filePath: historyPath)

        // Compact history file on startup if it's grown too large
        historyStore.compact(filePath: historyPath)
        var recentSlashUsageCounts = historyStore.recentSlashUsageCounts(filePath: historyPath)

        // Codex-inspired startup tip — first-run welcome or random feature discovery tip
        let isFirstRun = StartupTipProvider.isFirstRun(historyFilePath: historyPath)
        if let tipLine = StartupTipProvider.renderTip(
            StartupTipProvider.getTip(isFirstRun: isFirstRun),
            isTTY: isatty(STDERR_FILENO) != 0,
            colorProfile: TerminalColorProfile.detect()
        ) {
            fputs(tipLine, stderr)
        }

        // Session transcript logger — Codex-inspired session_log.rs
        // Persists full conversation (user/assistant/tool/system) to JSONL for post-session review.
        let transcriptLogger = SessionTranscriptLogger.live(dirPath: sessionsDir)
        transcriptLogger.open(
            sessionId: sessionId,
            dirPath: sessionsDir,
            model: buildResult.agent.model,
            cwd: FileManager.default.currentDirectoryPath
        )

        // AC9: ChatComposer replaces MultiLineInputReader as the REPL input component.
        var composer = ChatComposer()
        composer.enableBracketPaste()
        defer { composer.disableBracketPaste() }

        // Story 38.9: 注入 skill 列表到 composer
        if let registry = skillRegistry {
            composer.availableSkills = registry.userInvocableSkills.map { skill in
                SkillInfo(name: skill.name, description: skill.description, aliases: skill.aliases)
            }
        }

        // Story 38.5: InputQueue — 忙时输入排队
        var inputQueue = InputQueue()

        // Codex-inspired session metrics: turn counter, total tools, session start time
        var sessionTurnCount = 0
        var sessionTotalTools = 0
        var sessionLastAssistantText = ""  // /copy 需要：跨 turn 持久化
        let sessionStartTime = ContinuousClock.now
        var sessionToolUsage = ToolUsageTracker()  // Codex-inspired tool analytics

        // REPL loop: each turn calls agent.stream() for full streaming events.
        var skipNextRead = false

        chatLoop: while true {
            SignalHandler.reset()

            // Story 38.5: 同步 inputQueue 到 composer
            composer.inputQueue = inputQueue
            composer.slashUsageCounts = recentSlashUsageCounts

            // AC2: 动态提示符（含上下文进度条 + 回合计数 + 累计成本 + Git 分支）
            let colorProfile = TerminalColorProfile.detect()
            // Codex-inspired: 计算累计会话成本显示在提示符中
            let sessionCost = BannerRenderer.estimateCostString(
                model: state.buildResult.agent.model,
                usage: state.sessionUsage
            )
            // Codex-inspired (branch_summary.rs): 检测当前 git 分支显示在提示符中
            let promptCfg = config.promptDisplay ?? PromptDisplayConfig()
            let gitStatus = GitBranchDetector.detect()
            let gitBranch = gitStatus.map { $0.displayString(maxLength: promptCfg.branchMaxLength) }
            let prompt = BannerRenderer.renderPrompt(
                usedTokens: state.contextTokens,
                contextWindow: state.contextWindow,
                turnNumber: sessionTurnCount,
                estimatedCost: sessionCost,
                gitBranch: gitBranch,
                isTTY: isatty(STDERR_FILENO) != 0,
                colorProfile: colorProfile,
                displayConfig: promptCfg
            )

            // 上下文使用率警告标题
            let contextPct = state.contextWindow > 0
                ? Int(Double(state.contextTokens) / Double(state.contextWindow) * 100)
                : 0
            if contextPct > 80 {
                terminalTitle.setContextWarning(pct: contextPct)
            } else {
                terminalTitle.setIdle()
            }

            // Story 38.5 AC6: 排队预览
            if let preview = composer.renderQueuePreview() {
                fputs("\(preview)\n", stderr)
            }

            // AC1/AC2: 注入会话历史到 composer（跨会话持久化 + 当前会话）
            composer.history = persistentHistory + state.sessionUserMessages

            // Story 38.5 AC2: 优先消费队列
            let trimmed: String
            if skipNextRead, let queued = inputQueue.dequeue() {
                trimmed = queued.text
                fputs("📤 自动发送排队消息: \"\(String(trimmed.prefix(40)))\"\n", stderr)
                composer.inputQueue = inputQueue
            } else {
                skipNextRead = false
                let line = composer.readInput(
                    prompt: prompt,
                    continuationPrompt: "...> "
                )
                if SignalHandler.fireCount() > 0 {
                    state.lastInterruptTime = ContinuousClock.now
                    continue
                }
                guard let line else {
                    // Ctrl+C 且输入为空 — 检查双击退出
                    let now = ContinuousClock.now
                    if let last = state.lastInterruptTime,
                       chatShouldExit(lastInterrupt: last, now: now) {
                        break  // 2 秒内第二次 Ctrl+C → 退出
                    }
                    state.lastInterruptTime = now
                    continue  // 首次 Ctrl+C → 不退出，继续循环
                }
                let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
                if lineTrimmed.isEmpty { continue }
                if lineTrimmed == "^C" { continue }

                if let updatedQueue = composer.inputQueue {
                    inputQueue = updatedQueue
                }

                trimmed = lineTrimmed
            }

            let route = ChatCommandInputRouter.route(
                input: trimmed,
                resumeSessionIds: state.lastResumeList.map(\.sessionId),
                resolveSkillName: { rawSkillName in
                    guard let registry = skillRegistry,
                          let matchedSkill = registry.find(rawSkillName),
                          matchedSkill.userInvocable
                    else {
                        return nil
                    }
                    return matchedSkill.name
                }
            )
            if case .ignore = route {
                continue
            }

            let isGeneratedTaskSlash: Bool = {
                guard case .builtIn(let command, _) = route else {
                    return false
                }
                return command == .apps || command == .storage
            }()
            let recordUserInput: (String) -> Void = { text in
                state.sessionUserMessages.append(text)
                // Persist to cross-session history file (Codex-inspired)
                historyStore.append(text: text, filePath: historyPath)
                recentSlashUsageCounts = historyStore.recentSlashUsageCounts(filePath: historyPath)
                // Persist to session transcript (Codex-inspired session_log.rs)
                transcriptLogger.logUserInput(text, sessionId: sessionId, dirPath: sessionsDir)
            }
            if !isGeneratedTaskSlash {
                recordUserInput(trimmed)
            }

            // ── Slash command handling ──────────────────────────────────

            // taskText: 实际发给 agent 的文本
            // matchedSkillExec: SkillRegistry 匹配时使用 executeSkillStream
            var taskText = trimmed
            var matchedSkillExec: (name: String, args: String?)?

            switch route {
            case .ignore:
                continue
            case .builtIn(let cmd, let argument):
                if cmd == .apps {
                    guard let generatedTask = await handleAppsSlash(argument: argument, config: config) else {
                        continue
                    }
                    taskText = generatedTask
                    recordUserInput(generatedTask)
                } else if cmd == .arch {
                    await handleArchitectureSlash(argument: argument)
                    continue
                } else if cmd == .mcp {
                    handleMCPSlash(argument: argument, config: config, buildConfig: state.buildConfig)
                    continue
                } else if cmd == .storage {
                    guard let generatedTask = SlashCommandHandler.buildStorageTask(argument: argument) else {
                        fputs(SlashCommandHandler.handleStorageHelp(), stderr)
                        continue
                    }
                    taskText = generatedTask
                    recordUserInput(generatedTask)
                } else {
                    // AC1 (/resume 无参数): 在 REPL 中直接列出会话
                    if cmd == .resume && (argument == nil || argument!.isEmpty) {
                        state.lastResumeList = await handleResumeList(
                            buildConfig: state.buildConfig,
                            sessionsDir: sessionsDir,
                            includeArchived: false
                        )
                        continue
                    }

                    // 38.7 AC4: /resume --all
                    if cmd == .resume && argument == "--all" {
                        state.lastResumeList = await handleResumeList(
                            buildConfig: state.buildConfig,
                            sessionsDir: sessionsDir,
                            includeArchived: true
                        )
                        continue
                    }

                    // /compact
                    if cmd == .compact {
                        fputs(
                            await SlashCommandHandler.handleCompactNow(
                                agent: state.buildResult.agent,
                                contextTokens: state.contextTokens,
                                contextWindow: state.contextWindow
                            ),
                            stderr
                        )
                        continue
                    }

                    // /clear — 清除对话上下文（Claude Code 风格）
                    if cmd == .clear {
                        // 1. 清空 session store 中当前会话的消息
                        if let store = state.buildConfig.sessionStore {
                            let cwd = FileManager.default.currentDirectoryPath
                            try? await store.save(
                                sessionId: state.sessionId,
                                messages: [],
                                metadata: PartialSessionMetadata(
                                    cwd: cwd,
                                    model: state.buildResult.agent.model
                                )
                            )
                        }
                        // 2. 清空 agent 内存状态
                        state.buildResult.agent.clear()
                        // 3. 重置 REPL 状态
                        state.sessionUserMessages = []
                        state.contextTokens = 0
                        state.sessionUsage = TokenUsage(inputTokens: 0, outputTokens: 0)
                        state.resumedMessageBaseCount = 0
                        // 4. 清屏
                        fputs("\u{1B}[2J\u{1B}[H", stdout)
                        fflush(stdout)
                        fputs("🗑️ 对话上下文已清除\n", stderr)
                        continue
                    }

                    // 38.7: /new — 创建新会话
                    if cmd == .newSession {
                        let newSessionId = "chat-\(UUID().uuidString.prefix(8))"
                        do {
                            let result = try await state.switchToSession(
                                newSessionId,
                                params: buildParams
                            )
                            currentAgent.update(result.newAgent)
                            fputs(SessionWorkflowHandler.formatNewSuccess(sessionId: newSessionId), stderr)
                        } catch {
                            fputs("[axion] ❌ 创建新会话失败: \(error.localizedDescription)\n", stderr)
                        }
                        continue
                    }

                    // 38.7: /fork — 分叉当前会话
                    if cmd == .fork {
                        guard let store = state.buildConfig.sessionStore else {
                            fputs("[axion] 无法访问会话存储\n", stderr)
                            continue
                        }
                        let messageCount = state.resumedMessageBaseCount + state.sessionUserMessages.count
                        let action = await SessionWorkflowHandler.handleFork(
                            sessionId: state.sessionId,
                            sessionStore: store,
                            messageCount: messageCount
                        )
                        if case .forkSession(let newId, let sourceId) = action {
                            do {
                                let oldBaseCount = state.resumedMessageBaseCount + state.sessionUserMessages.count
                                let result = try await state.switchToSession(
                                    newId,
                                    params: buildParams,
                                    resetBaseCount: false
                                )
                                state.resumedMessageBaseCount = oldBaseCount
                                currentAgent.update(result.newAgent)
                                fputs(SessionWorkflowHandler.formatForkSuccess(newId: newId, sourceId: sourceId), stderr)
                            } catch {
                                fputs("[axion] ❌ 分叉会话恢复失败: \(error.localizedDescription)\n", stderr)
                            }
                        }
                        continue
                    }

                    // 38.7: /archive — 归档当前会话
                    if cmd == .archive {
                        guard let store = state.buildConfig.sessionStore else {
                            fputs("[axion] 无法访问会话存储\n", stderr)
                            continue
                        }
                        let messageCount = state.resumedMessageBaseCount + state.sessionUserMessages.count
                        let action = await SessionWorkflowHandler.handleArchive(
                            sessionId: state.sessionId,
                            sessionStore: store,
                            messageCount: messageCount
                        )
                        if case .archiveSession = action {
                            // AC3: 归档完成 — 继续当前会话（不退出）
                        }
                        continue
                    }

                    let action = SlashCommandHandler.handle(
                        cmd,
                        argument: argument,
                        agent: state.buildResult.agent,
                        config: config,
                        sessionUsage: state.sessionUsage,
                        buildConfig: state.buildConfig,
                        contextWindow: state.contextWindow,
                        contextTokens: state.contextTokens,
                        skillRegistry: skillRegistry,
                        lastAssistantText: sessionLastAssistantText,
                        sessionStartTime: sessionStartTime,
                        sessionTurnCount: sessionTurnCount,
                        sessionTotalTools: sessionTotalTools,
                        sessionToolUsage: sessionToolUsage
                    )

                    switch action {
                    case .none:
                        continue
                    case .exit:
                        break chatLoop
                    case .resumeSession(let rawArg):
                        let targetSessionId = await resolveResumeTarget(
                            rawArg: rawArg,
                            state: &state,
                            sessionsDir: sessionsDir
                        )
                        if let result = await state.resumeSession(
                            targetSessionId: targetSessionId,
                            params: buildParams
                        ) {
                            currentAgent.update(result.newAgent)
                        }
                        continue
                    case .newSession, .forkSession, .archiveSession:
                        continue
                    }
                }
            case .resumeListedSession(let targetSessionId):
                // Direct number input after /resume list — resume session by index
                state.lastResumeList = []
                if let result = await state.resumeSession(
                    targetSessionId: targetSessionId,
                    params: buildParams
                ) {
                    currentAgent.update(result.newAgent)
                }
                continue
            case .agentTask(let text, let matchedSkill):
                taskText = text
                if let matchedSkill {
                    // SkillRegistry 匹配到 — 使用 executeSkillStream（SDK 专用 skill 执行路径）
                    matchedSkillExec = (name: matchedSkill.name, args: matchedSkill.args)
                }
                // 无论是否匹配 SkillRegistry，都落入 agent stream 执行
                // agent 会通过 SkillTool 处理未知的 /xxx 输入
            }

            // ── Execute agent stream ────────────────────────────────────

            let chatTheme = ChatTheme(profile: colorProfile, isTTY: isatty(STDERR_FILENO) != 0)
            let transcriptRenderer = TranscriptRenderer(theme: chatTheme)

            fputs(transcriptRenderer.renderUserMessage(text: taskText), stderr)

            composer.slashContext = SlashCommandContext(isAgentBusy: true, isSideSession: false)

            // Turn metrics tracking
            let turnStartTime = ContinuousClock.now
            let preTurnUsage = state.sessionUsage
            var turnToolCount = 0
            var lastAssistantText = ""  // For desktop notification preview
            var turnFileTracker = TurnFileChangeTracker()  // Codex-inspired file change tracking
            var responseSpeedTracker = ResponseSpeedTracker()  // Codex-inspired TTFT + tok/s
            sessionTurnCount += 1

            let outputHandler = ChatOutputFormatter(theme: chatTheme)
            outputHandler.startLLMWaiting()
            terminalTitle.setThinking()
            // ESC / Ctrl+C 中断监听 — agent streaming 期间并发检测按键。
            // raw mode 关闭 ISIG 后 Ctrl+C 不再产生 SIGINT、而作为 0x03 字节进入 stdin，
            // 故监听器须同时捕获 0x1B(ESC) 与 0x03(Ctrl+C)，统一走 simulateFire()+interrupt()
            // （不经 SignalHandler，避免污染 REPL 双击退出状态机；与 /apps 扫描路径同模式）。
            let escListener = EscapeInterruptListener(
                onEscape: {
                    SignalHandler.simulateFire()
                    currentAgent.interrupt()
                },
                interruptBytes: [0x1B, 0x03]
            )
            escListenerRef.set(escListener)

            let messageStream: AsyncStream<SDKMessage>
            if let skillExec = matchedSkillExec {
                // Story 40.6 Path A: surface tool-availability diagnostics for the matched skill on the
                // interactive chat path (mirrors buildSkillAgent's Path B emit, same shared helper). The
                // skill executes on the already-built chat agent, inheriting its permission context (AC4),
                // so we diagnose against that agent's assembled tool pool. `enableToolSearch` is derived
                // from pool membership — ToolSearch is assembled iff config enables it (Story 40.5 build
                // invariant), so this is semantically equivalent to reading AxionConfig.toolSearchEnabled
                // without threading config into the REPL turn loop.
                if let skill = state.buildResult.skillRegistry.find(skillExec.name) {
                    let chatToolNames = (state.buildResult.agentOptions.tools ?? []).map { $0.name.lowercased() }
                    let toolSearchOn = chatToolNames.contains(
                        OpenAgentSDK.ToolRestriction.toolSearch.rawValue.lowercased()
                    )
                    let diag = AgentBuilder.diagnoseToolAvailability(
                        skill: skill,
                        availableToolNames: chatToolNames,
                        enableToolSearch: toolSearchOn
                    )
                    AgentBuilder.emitToolAvailabilityDiagnostics(diag, skillName: skill.name)
                }
                // SkillRegistry 匹配 — 使用 SDK 专用 skill 执行路径
                messageStream = state.buildResult.agent.executeSkillStream(skillExec.name, args: skillExec.args)
            } else {
                // 普通对话 或 未知 /xxx（agent 通过 SkillTool 自行处理）
                messageStream = state.buildResult.agent.stream(taskText)
            }
            for await message in messageStream {
                // Ctrl+C 中断时：抑制 "执行错误" 显示
                if SignalHandler.fireCount() > 0 {
                    outputHandler.suppressInterruptError = true
                }
                outputHandler.handle(message)
                switch message {
                case .toolUse(let data):
                    turnToolCount += 1
                    sessionToolUsage.record(toolName: data.toolName)  // Codex-inspired analytics
                    terminalTitle.setToolExecuting(data.toolName)
                    turnFileTracker.recordToolUse(toolName: data.toolName, input: data.input)
                    transcriptLogger.logToolUse(
                        toolName: data.toolName, input: data.input,
                        sessionId: sessionId, dirPath: sessionsDir
                    )
                case .assistant(let data):
                    // Codex-inspired: 标记首个输出 token 到达时刻
                    responseSpeedTracker.markFirstToken()
                    if !data.text.isEmpty {
                        lastAssistantText = data.text
                        sessionLastAssistantText = data.text  // /copy 需要：持久化到 session 级别
                        transcriptLogger.logAssistant(
                            data.text, sessionId: sessionId, dirPath: sessionsDir
                        )
                    }
                case .result(let data):
                    if let usage = data.usage {
                        state.sessionUsage = state.sessionUsage + usage
                    }
                    // 使用 SDK 报告的最后一次 LLM 调用 input_tokens 作为上下文大小
                    // 这是精确的当前上下文快照，而非累计 totalUsage.inputTokens
                    if let lastTokens = data.lastTurnInputTokens {
                        state.contextTokens = lastTokens
                    } else {
                        // 降级：从消息估算（如 skill 错误路径无 LLM 调用）
                        let messages = state.buildResult.agent.getMessages()
                        state.contextTokens = ContextManager.estimateContextTokens(messages: messages)
                    }
                case .system(let data):
                    if data.subtype == .compactBoundary {
                        if data.compactResult == "failed" {
                            state.consecutiveCompactFailures += 1
                            fputs(
                                ContextManager.formatCompactFailureMessage(
                                    failureCount: state.consecutiveCompactFailures
                                ),
                                stderr
                            )
                        } else if let metadata = data.compactMetadata,
                                  let postTokens = metadata.postTokens,
                                  let preTokens = metadata.preTokens
                        {
                            state.contextTokens = postTokens
                            state.consecutiveCompactFailures = 0
                            fputs(
                                ContextManager.formatCompactMessage(
                                    beforeTokens: preTokens,
                                    afterTokens: postTokens,
                                    contextWindow: state.contextWindow
                                ),
                                stderr
                            )
                        } else {
                            let messages = state.buildResult.agent.getMessages()
                            state.contextTokens = ContextManager.estimateContextTokens(
                                messages: messages
                            )
                            fputs(
                                ContextManager.formatCompactMessage(
                                    beforeTokens: state.contextTokens * 3,
                                    afterTokens: state.contextTokens,
                                    contextWindow: state.contextWindow
                                ),
                                stderr
                            )
                        }
                    } else if data.subtype == .paused {
                        // pause_for_human 触发：agent 挂起在 CheckedContinuation，必须 resume/interrupt 才能解除，
                        // 否则 for await 永久阻塞 → REPL 卡死（用户既无法输入也无法取消）。
                        guard let pausedData = data.pausedData else {
                            // 防御：无 payload 时仍须解除挂起，避免死锁
                            currentAgent.interrupt()
                            break
                        }
                        // 边界 E：若 Ctrl+C 已在途，短路不读输入直接中断
                        if SignalHandler.fireCount() > 0 {
                            currentAgent.interrupt()
                            break
                        }
                        // stdin 协调：暂停 ESC raw-mode 轮询 Task + 恢复 canonical mode，
                        // 否则轮询 Task 会吞掉用户输入字节（与 PermissionHandler 权限提示同一既定模式）。
                        let escPaused = escListener.pause()
                        defer { if escPaused { escListener.resume() } }
                        let takeoverIO = TakeoverIO(
                            write: { fputs($0 + "\n", stderr); fflush(stderr) },
                            readLine: { Swift.readLine() }
                        )
                        let input = takeoverIO.displayConfirmationPrompt(
                            reason: pausedData.reason,
                            completedSteps: sessionTurnCount
                        )
                        switch PausedEventDecider.decide(
                            canResume: pausedData.canResume,
                            action: input.action,
                            text: input.userInput
                        ) {
                        case .resume(let context):
                            currentAgent.resume(context: context)
                        case .interrupt:
                            // 风险 #3：pause-abort 经 readLine 触发，不经 Ctrl+C/ESC →
                            // simulateFire 让 turn-end 逻辑当作中断（不消费队列、不显示"完成"摘要）
                            SignalHandler.simulateFire()
                            currentAgent.interrupt()
                        }
                    }
                default:
                    break
                }
            }

            escListener.cancel()
            escListenerRef.set(nil)

            composer.slashContext = SlashCommandContext(isAgentBusy: false, isSideSession: false)

            // Reset terminal title to idle or context warning
            if contextPct > 80 {
                terminalTitle.setContextWarning(pct: contextPct)
            } else {
                terminalTitle.setIdle()
            }

            // Story 38.5 AC2: Turn 结束后检查队列 — 仅正常完成时自动消费，中断时不消费
            // （避免 Ctrl+C 中断后排队消息被自动发送，用户被迫多次 Ctrl+C）
            let interruptCount = SignalHandler.fireCount()
            if interruptCount > 0 {
                let now = ContinuousClock.now
                if let last = state.lastInterruptTime,
                   chatShouldExit(lastInterrupt: last, now: now)
                {
                    break
                }
                state.lastInterruptTime = now
                // 中断：不显示 turn summary / file summary
                // 不预填上次输入 — 用户中断通常想重新开始，需要重发可用 ↑ 历史导航
            } else {
                // Turn completion summary — Codex-inspired "worked for Xs" pattern
                let turnElapsed = ContinuousClock.now - turnStartTime
                let turnDuration = formatDuration(turnElapsed)
                let turnInputDelta = state.sessionUsage.inputTokens - preTurnUsage.inputTokens
                let turnOutputDelta = state.sessionUsage.outputTokens - preTurnUsage.outputTokens
                sessionTotalTools += turnToolCount

                // 计算上下文使用百分比（Codex-inspired: 在 turn summary 中显示上下文进度）
                let contextPct: Int? = state.contextWindow > 0
                    ? min(Int(Double(state.contextTokens) / Double(state.contextWindow) * 100), 200)
                    : nil

                // 估算本 turn 成本
                let turnCost: String? = {
                    let turnUsage = TokenUsage(
                        inputTokens: turnInputDelta,
                        outputTokens: turnOutputDelta
                    )
                    let costStr = BannerRenderer.estimateCostString(
                        model: state.buildResult.agent.model,
                        usage: turnUsage
                    )
                    return costStr
                }()

                // Codex-inspired: 计算响应速度（TTFT + tok/s）
                let turnResponseSpeed = responseSpeedTracker.computeSpeed(
                    outputTokens: turnOutputDelta,
                    endTime: ContinuousClock.now
                )

                fputs(
                    transcriptRenderer.renderTurnSummary(
                        duration: turnDuration,
                        toolCount: turnToolCount,
                        inputTokens: BannerRenderer.formatTokenCount(turnInputDelta),
                        outputTokens: BannerRenderer.formatTokenCount(turnOutputDelta),
                        contextPct: contextPct,
                        estimatedCost: turnCost,
                        responseSpeed: turnResponseSpeed
                    ),
                    stderr
                )

                // Codex-inspired file change summary — show files modified this turn
                if let fileSummary = turnFileTracker.renderSummary(
                    isTTY: isatty(STDERR_FILENO) != 0,
                    profile: colorProfile
                ) {
                    fputs(fileSummary, stderr)
                }

                // Codex-inspired context warning — proactive /compact suggestion at 70-80%
                if let contextWarning = ContextManager.formatTurnEndContextWarning(
                    usedTokens: state.contextTokens,
                    contextWindow: state.contextWindow,
                    isTTY: isatty(STDERR_FILENO) != 0,
                    profile: colorProfile
                ) {
                    fputs(contextWarning, stderr)
                }

                // Desktop notification — Codex-inspired OSC 9 / BEL on turn complete
                desktopNotifier.notify(.agentTurnComplete(preview: lastAssistantText))

                // 正常完成 → 检查队列，非空则下轮自动消费
                if !inputQueue.isEmpty {
                    skipNextRead = true
                }
                state.lastInterruptTime = nil
                outputHandler.displayCompletion()
                fputs("\n", stdout)
            }
        }

        SignalHandler.uninstall()
        try? await state.buildResult.agent.close()
        terminalTitle.clear()
        let sessionDurationMs = durationToMs(ContinuousClock.now - sessionStartTime)
        // Close session transcript — Codex-inspired session_log.rs
        transcriptLogger.close(
            sessionId: sessionId,
            dirPath: sessionsDir,
            turns: sessionTurnCount,
            totalTokens: state.sessionUsage.totalTokens,
            durationMs: sessionDurationMs
        )
        fputs(
            BannerRenderer.renderExit(
                sessionId: state.sessionId,
                sessionDurationMs: sessionDurationMs,
                turns: sessionTurnCount,
                totalTools: sessionTotalTools,
                usage: state.sessionUsage,
                model: state.buildResult.agent.model,
                toolUsage: sessionToolUsage
            ),
            stderr
        )
    }

    private func handleAppsSlash(argument: String?, config: AxionConfig) async -> String? {
        let parsed = parseAppsArgument(argument)
        let service = AppListService()
        let detailProvider = AppDetailAnalysisService(config: config)
        // 首次扫描被 Esc/Ctrl+C 中断 → 回提示符，不进入选择列表
        guard var result = await listAppsForSlash(service: service, filter: parsed.filter, scope: parsed.deep ? .deep : .fast) else {
            return nil
        }

        while true {
            let prompt = AppSelectionPrompt(
                isTTY: isatty(STDIN_FILENO) != 0,
                writeOutput: { fputs($0, stderr) },
                detailProvider: detailProvider
            )
            switch await prompt.run(result: result) {
            case .selected(let item):
                return AppListFormatter.uninstallRequest(for: item)
            case .requestDeepSearch:
                // 深度搜索被中断 → 回提示符
                guard let deep = await listAppsForSlash(service: service, filter: parsed.filter, scope: .deep) else {
                    return nil
                }
                result = deep
            case .cancelled, .nonTTYListOnly:
                return nil
            }
        }
    }

    private func handleMCPSlash(
        argument: String?,
        config: AxionConfig,
        buildConfig: AgentBuilder.BuildConfig
    ) {
        let normalized = argument?.trimmingCharacters(in: .whitespacesAndNewlines)
        if buildConfig.dryrun || normalized == "--all" {
            fputs(SlashCommandHandler.handleMCPStatus(config: config, buildConfig: buildConfig), stderr)
            return
        }

        if let normalized, !normalized.isEmpty {
            fputs("[axion] /mcp 仅支持 --all 参数\n", stderr)
            return
        }

        let entries = SlashCommandHandler.mcpStatusEntries(config: config, buildConfig: buildConfig)
        let prompt = MCPSelectionPrompt(
            isTTY: isatty(STDIN_FILENO) != 0,
            writeOutput: { fputs($0, stderr) }
        )
        _ = prompt.run(entries: entries)
    }

    private func listAppsForSlash(service: any AppListing, filter: String?, scope: AppSearchScope) async -> AppListResult? {
        // 扫描期间显示 spinner（与"思考中"同一组件），非 TTY 自跳过。
        // fast 用 200ms 延迟避免秒级扫描闪烁；deep 恒慢，立即显示。
        let spinner = SpinnerRenderer()
        spinner.start(
            message: scope == .deep ? "正在深度搜索 App" : "正在扫描 App",
            delayMs: scope == .deep ? 0 : 200
        )
        defer { spinner.stop() }  // 安全网：stop() 幂等

        // 扫描期间监听 Esc / Ctrl+C：raw mode 下 Ctrl+C 不再产生 SIGINT 而作为 0x03 字节进入 stdin，
        // 与 Esc(0x1B) 由同一监听器统一捕获。任一中断字节 → 取消扫描 Task，放弃结果、回提示符。
        // 不经 SignalHandler，故不污染 REPL 的中断计数/双击退出状态机。
        let scanTask: _Concurrency.Task<AppListResult, Never> = _Concurrency.Task {
            await service.list(filter: filter, scope: scope)
        }
        let listener = EscapeInterruptListener(
            onEscape: { scanTask.cancel() },
            interruptBytes: [0x1B, 0x03]
        )
        defer { listener.cancel() }  // 恢复 termios + tcflush 清残留中断字节

        let start = Date()
        let result = await scanTask.value
        // service.list 已在取消检查点快速 break（partial）；此处丢弃结果、回提示符。
        if scanTask.isCancelled { return nil }

        // 必须先 stop() 清行，再写完成摘要——动画帧用 \r 回行首覆写，
        // 否则摘要与下一帧交错写到同一行会错位/残影。
        spinner.stop()

        if scope == .deep {
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            let warningSuffix = result.warnings.isEmpty ? "" : "，\(result.warnings.count) 条提示"
            fputs("[axion] App 深度搜索完成：\(result.candidates.count) 个候选，用时 \(elapsedMs)ms\(warningSuffix)\n", stderr)
        }
        return result
    }

    private func parseAppsArgument(_ argument: String?) -> (filter: String?, deep: Bool) {
        let parts = (argument ?? "")
            .split(separator: " ")
            .map(String.init)
        let deep = parts.contains("--all")
        let filter = parts
            .filter { $0 != "--all" }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (filter.isEmpty ? nil : filter, deep)
    }

    private func handleArchitectureSlash(argument: String?) async {
        guard let options = AppArchitectureFormatter.parseOptions(argument: argument) else {
            fputs(AppArchitectureFormatter.helpText() + "\n", stderr)
            return
        }

        guard let result = await scanArchitectureForSlash(
            scanner: AppArchitectureScanService(),
            options: options
        ) else {
            return
        }
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: isatty(STDIN_FILENO) != 0,
            writeOutput: { fputs($0, stderr) }
        )
        _ = prompt.run(result: result)
    }

    private func scanArchitectureForSlash(
        scanner: any AppArchitectureScanning,
        options: AppArchitectureScanOptions
    ) async -> AppArchitectureScanResult? {
        let spinner = SpinnerRenderer()
        spinner.start(message: "正在扫描软件架构", delayMs: 200)
        defer { spinner.stop() }

        let scanTask: _Concurrency.Task<AppArchitectureScanResult, Never> = _Concurrency.Task {
            await scanner.scan(options: options)
        }
        let listener = EscapeInterruptListener(
            onEscape: { scanTask.cancel() },
            interruptBytes: [0x1B, 0x03]
        )
        defer { listener.cancel() }

        let result = await scanTask.value
        if scanTask.isCancelled { return nil }

        spinner.stop()
        return result
    }
}
