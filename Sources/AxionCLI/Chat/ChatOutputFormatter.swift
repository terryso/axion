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
    private var hasOutputText = false  // 跟踪是否已输出 LLM 文本（用于空行分隔）

    // AC1/AC2/AC3: 角色视觉语义层
    private let theme: ChatTheme?
    private let transcriptRenderer: TranscriptRenderer?
    private var assistantBlockStarted = false  // 同一轮 assistant 输出共享圆点标记

    init(
        writeStdout: @escaping (String) -> Void = { fputs($0, stdout); fflush(stdout) },
        writeStderr: @escaping (String) -> Void = { fputs($0, stderr); fflush(stderr) },
        spinner: SpinnerRenderer? = nil,
        theme: ChatTheme? = nil  // AC7: 可选注入，nil 时保持原有行为
    ) {
        self.writeStdout = writeStdout
        self.writeStderr = writeStderr
        self.spinner = spinner ?? SpinnerRenderer()
        self.theme = theme
        self.transcriptRenderer = theme.map { TranscriptRenderer(theme: $0) }
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

            // AC2: 首次 partialMessage 时输出 assistant 圆点（如果 theme 可用）
            if let renderer = transcriptRenderer, !assistantBlockStarted {
                writeStdout(renderer.renderAssistantBlockStart())
                assistantBlockStarted = true
            }

            // 直接输出 LLM 文本，无前缀
            if !data.text.isEmpty {
                writeStdout(data.text)
                hasOutputText = true
            }

        case .assistant(let data):
            spinner.stop()

            // 如果 assistant 有文本且与 partial 不同，输出换行
            if !data.text.isEmpty && hasOutputText {
                writeStdout("\n")
            }

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

            // AC3: 工具事件角色标识（增量添加，保留原有 ⏳ 图标）
            let inputSummary = summarizeInput(data.input)
            writeToolLine(role: .tool, content: "⏳ \(data.toolName): \(inputSummary)\n")

            // 启动工具执行 spinner（立即，无延迟）
            spinner.start(message: data.toolName)

            // 重置 assistant block
            assistantBlockStarted = false

        case .toolResult(let data):
            spinner.stop()

            let toolDuration = toolStartTimes.removeValue(forKey: data.toolUseId).map {
                formatDuration(ContinuousClock.now - $0)
            }
            let durationStr = toolDuration.map { " [\($0)]" } ?? ""

            if data.isError {
                let errorSummary = summarizeToolContent(String(data.content.prefix(200)), maxLines: 3)
                // AC3: 错误结果使用红色圆点
                writeToolLine(role: .warning, content: "\r❌ \(errorSummary)\(durationStr)\n")
            } else {
                let resultSummary = summarizeToolContent(data.content, maxLines: 3)
                // AC3: 成功结果使用黄色圆点
                writeToolLine(role: .tool, content: "\r✅ \(resultSummary)\(durationStr)\n")
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
                writeWarning("⚠️ 已取消")
            case .errorDuringExecution:
                writeWarning("❌ 执行错误")
            case .errorMaxStructuredOutputRetries:
                writeWarning("❌ 结构化输出重试超限")
            case .errorMaxModelCalls:
                writeWarning("⚠️ 已达到模型调用上限")
            }

            // 重置 assistant block
            assistantBlockStarted = false

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
