import Foundation
import OpenAgentSDK

/// Chat 模式专用输出格式化器 — 替代 SDKTerminalOutputHandler 的 [axion] 前缀格式。
/// 提供工具调用摘要、LLM 文本直接输出、进度 spinner。
///
/// Spinner 生命周期：
/// - LLM 等待：`startLLMWaiting()` 或 `.toolResult` 后启动延迟 spinner（500ms）
/// - 工具执行：`.toolUse` 时立即启动
/// - 所有 spinner 在 `.partialMessage` / `.assistant` / `.result` 时停止
final class ChatOutputFormatter: OpenAgentSDK.SDKMessageOutputHandler, @unchecked Sendable {
    private let writeStdout: (String) -> Void
    private let writeStderr: (String) -> Void
    private let spinner: SpinnerRenderer
    private var toolStartTimes: [String: ContinuousClock.Instant] = [:]
    private var toolNames: [String: String] = [:]  // toolUseId → toolName lookup
    private var hasOutputText = false  // 跟踪是否已输出 LLM 文本（用于空行分隔）

    // AC1/AC2/AC3: 角色视觉语义层
    private let theme: ChatTheme?
    private let transcriptRenderer: TranscriptRenderer?
    private var assistantBlockStarted = false  // 同一轮 assistant 输出共享圆点标记
    private var pendingAssistantPrefix: String?  // 缓冲的 ● 前缀，延迟到首行非边框输出时拼接

    // 流式代码块渲染器 — 检测代码围栏并渲染视觉边框
    private var codeBlockRenderer: StreamingCodeBlockRenderer

    // 流式 Markdown 内联格式化器 — 增强标题、粗体、内联代码等
    private let markdownFormatter: StreamingMarkdownFormatter

    // 文件变更追踪器 — Codex 风格回合结束摘要
    private(set) var fileChangeTracker = FileChangeTracker()

    /// 中断标记：为 true 时，.cancelled 和 .errorDuringExecution 不输出警告。
    /// 由 ChatCommand 在检测到 Ctrl+C 中断后设置。
    var suppressInterruptError: Bool = false

    init(
        writeStdout: @escaping (String) -> Void = { fputs($0, stdout); fflush(stdout) },
        writeStderr: @escaping (String) -> Void = { fputs($0, stderr); fflush(stderr) },
        spinner: SpinnerRenderer? = nil,
        theme: ChatTheme? = nil,  // AC7: 可选注入，nil 时保持原有行为
        codeBlockRenderer: StreamingCodeBlockRenderer? = nil,
        markdownFormatter: StreamingMarkdownFormatter? = nil
    ) {
        self.writeStdout = writeStdout
        self.writeStderr = writeStderr
        self.spinner = spinner ?? SpinnerRenderer()
        self.theme = theme
        self.transcriptRenderer = theme.map { TranscriptRenderer(theme: $0) }
        let resolvedProfile = theme?.profile ?? TerminalColorProfile.detect()
        let resolvedIsTTY = theme?.isTTY ?? (isatty(STDOUT_FILENO) != 0)
        self.markdownFormatter = markdownFormatter ?? StreamingMarkdownFormatter(
            profile: resolvedProfile,
            isTTY: resolvedIsTTY
        )
        self.codeBlockRenderer = codeBlockRenderer ?? StreamingCodeBlockRenderer(
            profile: resolvedProfile,
            isTTY: resolvedIsTTY,
            plainTextFormatter: { [markdownFormatter = self.markdownFormatter] line in
                markdownFormatter.formatLine(line)
            }
        )
    }

    /// 开始等待 LLM 首次响应（用户提交 prompt 后调用）。
    /// Spinner 在 500ms 后才显示，避免短暂等待闪烁。
    func startLLMWaiting() {
        spinner.start(message: "思考中", delayMs: 500)
    }

    // MARK: - Themed Output Helpers

    /// Writes a themed warning to stderr, using the transcript renderer when available.
    private func writeWarning(_ message: String) {
        if let renderer = transcriptRenderer {
            writeStderr(renderer.renderWarning(message: message))
        } else {
            writeStderr("\(message)\n")
        }
    }

    /// Writes a tool/output line to stdout with the role dot prefix when available.
    private func writeToolLine(role: TranscriptRole, content: String) {
        if let renderer = transcriptRenderer {
            let dotPrefix = renderer.theme.formatRoleDot(role: role)
            writeStdout("\(dotPrefix) \(content)")
        } else {
            writeStdout(content)
        }
    }

    func displayRunStart(runId: String, task: String) {
        // Chat 模式不显示 run start 信息
    }

    func handle(_ message: SDKMessage) {
        switch message {
        case .partialMessage(let data):
            // 收到首个 partial → 停止等待 spinner（无论是否已启动动画）
            spinner.stop()

            // AC2: 首次 partialMessage 时缓冲 assistant 圆点（延迟到首行输出时拼接）
            if let renderer = transcriptRenderer, !assistantBlockStarted {
                pendingAssistantPrefix = renderer.renderAssistantBlockStart()
                assistantBlockStarted = true
            }

            // 通过代码块渲染器处理 LLM 文本 — 检测代码围栏并渲染视觉边框
            if !data.text.isEmpty {
                codeBlockRenderer.process(data.text) { [weak self] output in
                    guard let self else { return }
                    if let prefix = self.pendingAssistantPrefix {
                        self.pendingAssistantPrefix = nil
                        if output.contains("┌") {
                            // 代码块边框：圆点独占一行，边框另起一行（避免挤偏边框）
                            self.writeStdout(prefix + "\n" + output)
                        } else {
                            // 普通文本：圆点和文本在同一行
                            self.writeStdout(prefix + output)
                        }
                    } else {
                        self.writeStdout(output)
                    }
                }
                hasOutputText = true
            }

        case .assistant(let data):
            spinner.stop()

            // 兜底：如果 ● 前缀未被消费（极端情况如空回复），直接输出
            if let prefix = pendingAssistantPrefix {
                writeStdout(prefix + "\n")
                pendingAssistantPrefix = nil
            }

            // 如果 assistant 有文本且与 partial 不同，输出换行
            if !data.text.isEmpty && hasOutputText {
                writeStdout("\n")
            }

            // 刷新代码块渲染器缓冲区并重置状态
            codeBlockRenderer.flush { [writeStdout] output in
                writeStdout(output)
            }
            codeBlockRenderer.reset()

            // assistant 结束标记后重置 block 状态
            assistantBlockStarted = false

        case .toolUse(let data):
            spinner.stop()

            // 如果前面有 LLM 文本，插入空行分隔
            if hasOutputText {
                writeStdout("\n")
                hasOutputText = false
            }

            toolStartTimes[data.toolUseId] = .now
            toolNames[data.toolUseId] = data.toolName

            // Codex-inspired: 按工具类别使用不同的视觉样式
            let startedLine = ToolCategoryFormatter.formatStarted(
                toolName: data.toolName,
                input: data.input
            )
            writeToolLine(role: .tool, content: startedLine)

            // Codex-inspired: 追踪文件变更用于回合结束摘要
            if let info = FileChangeTracker.extractFileInfo(toolName: data.toolName, input: data.input) {
                switch info.kind {
                case .created:
                    fileChangeTracker.recordWrite(filePath: info.filePath, contentLineCount: info.linesAdded)
                case .edited:
                    fileChangeTracker.recordEdit(filePath: info.filePath, linesAdded: info.linesAdded, linesRemoved: info.linesRemoved)
                case .read:
                    fileChangeTracker.recordRead(filePath: info.filePath)
                }
            }

            // 启动工具执行 spinner（立即，无延迟）
            spinner.start(message: data.toolName)

            // 重置 assistant block 和代码块渲染器（工具调用中断 LLM 流式输出）
            codeBlockRenderer.reset()
            assistantBlockStarted = false

        case .toolResult(let data):
            spinner.stop()

            let toolDurationMs = toolStartTimes.removeValue(forKey: data.toolUseId).map {
                durationToMs(ContinuousClock.now - $0)
            }
            let resolvedToolName = toolNames.removeValue(forKey: data.toolUseId) ?? "unknown"

            // Codex-inspired: 按工具类别使用不同的结果格式化
            let completedLine = ToolCategoryFormatter.formatCompleted(
                toolName: resolvedToolName,
                content: data.content,
                isError: data.isError,
                durationMs: toolDurationMs
            )
            if data.isError {
                writeToolLine(role: .warning, content: "\r\(completedLine)")
            } else {
                writeToolLine(role: .tool, content: "\r\(completedLine)")
            }

            // 工具结果后开始等待 LLM 下一轮响应（500ms 延迟 spinner）
            spinner.start(message: "思考中", delayMs: 500)

        case .result(let data):
            spinner.stop()

            if hasOutputText {
                writeStdout("\n")
                hasOutputText = false
            }

            switch data.subtype {
            case .success:
                break  // 正常完成，不额外输出
            case .errorMaxTurns:
                writeWarning("⚠️ 达到最大步数限制 (\(data.numTurns) 步)")
            case .errorMaxBudgetUsd:
                writeWarning("⚠️ 预算超限")
            case .cancelled:
                if !suppressInterruptError {
                    writeWarning("⚠️ 已取消")
                }
                suppressInterruptError = false
            case .errorDuringExecution:
                if !suppressInterruptError {
                    if let errors = data.errors, !errors.isEmpty {
                        writeWarning("❌ 执行错误: \(errors.joined(separator: ", "))")
                    } else {
                        writeWarning("❌ 执行错误")
                    }
                }
                suppressInterruptError = false
            case .errorMaxStructuredOutputRetries:
                writeWarning("❌ 结构化输出重试超限")
            case .errorMaxModelCalls:
                writeWarning("⚠️ 已达到模型调用上限")
            }

            // 重置 assistant block 和代码块渲染器
            codeBlockRenderer.reset()
            assistantBlockStarted = false

            // Codex-inspired: 输出文件变更摘要（仅在有变更时）
            if fileChangeTracker.hasChanges {
                let summary = fileChangeTracker.renderSummary()
                if !summary.isEmpty {
                    writeStdout(summary)
                }
                fileChangeTracker.reset()
            }

        case .system(let data):
            switch data.subtype {
            case .paused:
                spinner.stop()
                // AC3: paused 使用红色圆点
                if let pausedData = data.pausedData {
                    writeWarning("⏸️ 任务暂停: \(pausedData.reason)")
                }
            case .pausedTimeout:
                spinner.stop()
                writeWarning("⏸️ 接管超时（5 分钟无操作），任务终止。")

            // Codex-inspired: 上下文压缩事件
            case .compactBoundary:
                if let output = SystemEventRenderer.renderCompaction(
                    metadata: data.compactMetadata,
                    isTTY: theme?.isTTY ?? (isatty(STDOUT_FILENO) != 0),
                    colorProfile: theme?.profile ?? .detect()
                ) {
                    writeStdout(output)
                }

            // Codex-inspired: 系统状态事件（compacting/requesting）
            case .status:
                if let output = SystemEventRenderer.renderStatus(
                    statusValue: data.statusValue,
                    compactResult: data.compactResult,
                    compactError: data.compactError,
                    isTTY: theme?.isTTY ?? (isatty(STDOUT_FILENO) != 0),
                    colorProfile: theme?.profile ?? .detect()
                ) {
                    writeStdout(output)
                }

            // Codex-inspired: 速率限制警告
            case .rateLimit:
                if let output = SystemEventRenderer.renderRateLimit(
                    rateLimitInfo: data.rateLimitInfo,
                    isTTY: theme?.isTTY ?? (isatty(STDOUT_FILENO) != 0),
                    colorProfile: theme?.profile ?? .detect()
                ) {
                    writeStderr(output)
                }

            // Codex-inspired: 任务完成通知
            case .taskNotification:
                if let output = SystemEventRenderer.renderTaskNotification(
                    taskInfo: data.taskNotificationInfo,
                    isTTY: theme?.isTTY ?? (isatty(STDOUT_FILENO) != 0),
                    colorProfile: theme?.profile ?? .detect()
                ) {
                    writeStdout(output)
                }

            default:
                break
            }

        case .hookStarted, .hookResponse:
            break

        default:
            break
        }
    }

    func displayCompletion() {
        spinner.stop()
        // Chat 模式不显示 "运行结束" — 由 REPL 循环控制
    }

    // MARK: - Content Summary Helpers
    // Extracted to ChatOutputFormatter+ContentSummary.swift
}
