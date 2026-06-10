import ArgumentParser
import Foundation
import OpenAgentSDK

import AxionCore

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
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: permissionMode,
            sessionAllowList: sessionAllowList,
            escListenerRef: escListenerRef
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

        // Agent reference for SIGINT handler — uses nonisolated(unsafe) to satisfy
        // Sendable closure requirement. Agent.interrupt() is thread-safe.
        nonisolated(unsafe) var currentAgent = state.buildResult.agent
        SignalHandler.install {
            currentAgent.interrupt()
        }

        // Cross-session command history (Codex-inspired)
        let historyStore = CommandHistoryStore.live()
        let historyPath = ConfigManager.historyFilePath
        let persistentHistory = historyStore.load(filePath: historyPath)

        // Compact history file on startup if it's grown too large
        historyStore.compact(filePath: historyPath)

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

        // Story 38.5: InputQueue — 忙时输入排队
        var inputQueue = InputQueue()

        // Codex-inspired session metrics: turn counter, total tools, session start time
        var sessionTurnCount = 0
        var sessionTotalTools = 0
        var sessionLastAssistantText = ""  // /copy 需要：跨 turn 持久化
        let sessionStartTime = ContinuousClock.now

        // REPL loop: each turn calls agent.stream() for full streaming events.
        var skipNextRead = false

        while true {
            SignalHandler.reset()

            // Story 38.5: 同步 inputQueue 到 composer
            composer.inputQueue = inputQueue

            // AC2: 动态提示符（含上下文进度条 + 回合计数 + 累计成本 + Git 分支）
            let colorProfile = TerminalColorProfile.detect()
            // Codex-inspired: 计算累计会话成本显示在提示符中
            let sessionCost = BannerRenderer.estimateCostString(
                model: state.buildResult.agent.model,
                usage: state.sessionUsage
            )
            // Codex-inspired (branch_summary.rs): 检测当前 git 分支显示在提示符中
            let gitBranch = GitBranchDetector.detect()?.displayString
            let prompt = BannerRenderer.renderPrompt(
                usedTokens: state.contextTokens,
                contextWindow: state.contextWindow,
                turnNumber: sessionTurnCount,
                estimatedCost: sessionCost,
                gitBranch: gitBranch,
                isTTY: isatty(STDERR_FILENO) != 0,
                colorProfile: colorProfile
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

            state.sessionUserMessages.append(trimmed)
            // Persist to cross-session history file (Codex-inspired)
            historyStore.append(text: trimmed, filePath: historyPath)
            // Persist to session transcript (Codex-inspired session_log.rs)
            transcriptLogger.logUserInput(trimmed, sessionId: sessionId, dirPath: sessionsDir)

            // ── Slash command handling ──────────────────────────────────

            // taskText: 实际发给 agent 的文本
            // matchedSkillExec: SkillRegistry 匹配时使用 executeSkillStream
            let taskText = trimmed
            var matchedSkillExec: (name: String, args: String?)?

            if let cmd = SlashCommand.parse(trimmed) {
                let argument = SlashCommand.parseArgument(trimmed)

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
                        currentAgent = result.newAgent
                        SignalHandler.install { currentAgent.interrupt() }
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
                            currentAgent = result.newAgent
                            SignalHandler.install { currentAgent.interrupt() }
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
                    sessionTotalTools: sessionTotalTools
                )

                switch action {
                case .none:
                    continue
                case .exit:
                    break
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
                        currentAgent = result.newAgent
                        SignalHandler.install { currentAgent.interrupt() }
                    }
                    continue
                case .newSession, .forkSession, .archiveSession:
                    continue
                }

                if action == .exit { break }
                continue
            } else if !state.lastResumeList.isEmpty, let index = Int(trimmed), index > 0, index <= state.lastResumeList.count {
                // Direct number input after /resume list — resume session by index
                let targetSessionId = state.lastResumeList[index - 1].sessionId
                state.lastResumeList = []
                if let result = await state.resumeSession(
                    targetSessionId: targetSessionId,
                    params: buildParams
                ) {
                    currentAgent = result.newAgent
                    SignalHandler.install { currentAgent.interrupt() }
                }
                continue
            } else if trimmed.hasPrefix("/") {
                // /xxx 不是内置命令 — 参考 TG 模式：直接发给 agent 执行
                // 如果 SkillRegistry 中匹配到 skill，使用 promptTemplate（优化路径）
                let rawSkillName = String(trimmed.split(separator: " ", maxSplits: 1)[0].dropFirst())
                let skillArg = trimmed.split(separator: " ", maxSplits: 1).count > 1
                    ? String(trimmed.split(separator: " ", maxSplits: 1)[1])
                    : nil

                if let registry = skillRegistry,
                   let matchedSkill = registry.find(rawSkillName),
                   matchedSkill.userInvocable
                {
                    // SkillRegistry 匹配到 — 使用 executeSkillStream（SDK 专用 skill 执行路径）
                    matchedSkillExec = (name: matchedSkill.name, args: skillArg)
                }
                // 无论是否匹配 SkillRegistry，都落入 agent stream 执行
                // agent 会通过 SkillTool 处理未知的 /xxx 输入
            }

            // ── Execute agent stream ────────────────────────────────────

            let chatTheme = ChatTheme(profile: colorProfile, isTTY: isatty(STDERR_FILENO) != 0)
            let transcriptRenderer = TranscriptRenderer(theme: chatTheme)

            fputs(transcriptRenderer.renderUserMessage(text: trimmed), stderr)

            composer.slashContext = SlashCommandContext(isAgentBusy: true, isSideSession: false)

            // Turn metrics tracking
            let turnStartTime = ContinuousClock.now
            let preTurnUsage = state.sessionUsage
            var turnToolCount = 0
            var lastAssistantText = ""  // For desktop notification preview
            var turnFileTracker = TurnFileChangeTracker()  // Codex-inspired file change tracking
            sessionTurnCount += 1

            let outputHandler = ChatOutputFormatter(theme: chatTheme)
            outputHandler.startLLMWaiting()
            terminalTitle.setThinking()
            // ESC 键中断监听 — agent streaming 期间并发检测 ESC 按键
            // 与 Ctrl+C 共用 SignalHandler 中断路径：suppressInterruptError + 预填 + 不显示 summary
            let escListener = EscapeInterruptListener {
                SignalHandler.simulateFire()
                currentAgent.interrupt()
            }
            escListenerRef.set(escListener)

            let messageStream: AsyncStream<SDKMessage>
            if let skillExec = matchedSkillExec {
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
                    terminalTitle.setToolExecuting(data.toolName)
                    turnFileTracker.recordToolUse(toolName: data.toolName, input: data.input)
                    transcriptLogger.logToolUse(
                        toolName: data.toolName, input: data.input,
                        sessionId: sessionId, dirPath: sessionsDir
                    )
                case .assistant(let data):
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
                // 中断：不显示 turn summary / file summary，预填上次输入
                composer.prefill = trimmed
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

                fputs(
                    transcriptRenderer.renderTurnSummary(
                        duration: turnDuration,
                        toolCount: turnToolCount,
                        inputTokens: BannerRenderer.formatTokenCount(turnInputDelta),
                        outputTokens: BannerRenderer.formatTokenCount(turnOutputDelta),
                        contextPct: contextPct,
                        estimatedCost: turnCost
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
                model: state.buildResult.agent.model
            ),
            stderr
        )
    }
}
