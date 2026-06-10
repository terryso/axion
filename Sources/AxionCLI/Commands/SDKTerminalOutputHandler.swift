import Foundation
import OpenAgentSDK

// MARK: - SDKTerminalOutputHandler

/// Terminal output handler — displays human-readable progress via [axion]-prefixed lines.
/// Buffers streaming text from .partialMessage and flushes it as a single line
/// when a structured event (.assistant, .toolUse, .toolResult, .result) arrives.
final class SDKTerminalOutputHandler: OpenAgentSDK.SDKMessageOutputHandler, @unchecked Sendable {
    private let write: (String) -> Void
    private let mode: String
    private var streamBuffer = ""
    private var lastFlushedText = ""
    private var startTime: ContinuousClock.Instant?
    private var totalSteps = 0
    private var toolStartTimes: [String: ContinuousClock.Instant] = [:]
    private var llmWaitStart: ContinuousClock.Instant?
    private var llmRound = 0

    init(write: @escaping (String) -> Void = { fputs($0 + "\n", stdout); fflush(stdout) }, mode: String = "standard") {
        self.write = write
        self.mode = mode
    }

    func displayRunStart(runId: String, task: String) {
        startTime = ContinuousClock.now
        llmWaitStart = .now
        write("[axion] 模式: \(mode)")
        write("[axion] 运行 ID: \(runId)")
        write("[axion] 任务: \(task)")
    }

    func handle(_ message: SDKMessage) {
        switch message {
        case .assistant(let data):
            if let waitStart = llmWaitStart {
                llmRound += 1
                let elapsed = ContinuousClock.now - waitStart
                write("[axion] LLM #\(llmRound): \(formatDuration(elapsed))")
                llmWaitStart = nil
            }
            if !streamBuffer.isEmpty {
                flushStreamBuffer()
            } else if !data.text.isEmpty && data.text != lastFlushedText {
                write("[axion] \(data.text)")
                lastFlushedText = data.text
            }

        case .toolUse(let data):
            flushStreamBuffer()
            totalSteps += 1
            toolStartTimes[data.toolUseId] = .now
            write("[axion] 执行: \(data.toolName)")

        case .toolResult(let data):
            flushStreamBuffer()
            llmWaitStart = .now
            let toolDuration = toolStartTimes.removeValue(forKey: data.toolUseId).map { formatDuration(ContinuousClock.now - $0) }
            if data.isError {
                write("[axion] 结果: 错误 — \(String(data.content.prefix(100)))\(toolDuration.map { " [\($0)]" } ?? "")")
            } else {
                let snippet = summarizeToolContent(data.content, maxLines: 4)
                write("[axion] 结果: \(snippet)\(toolDuration.map { " [\($0)]" } ?? "")")
            }

        case .result(let data):
            flushStreamBuffer()
            let isFast = mode == "fast"
            switch data.subtype {
            case .success:
                if isFast {
                    let elapsed = computeElapsedSeconds()
                    write("[axion] Fast mode 完成。\(totalSteps) 步，耗时 \(elapsed) 秒。")
                    write("[axion] 如需更精确执行，可去掉 --fast 重试。")
                }
            case .errorMaxTurns:
                write("[axion] 达到最大步数限制 (\(data.numTurns) 步)")
                if isFast {
                    write("[axion] 建议去掉 --fast 重新尝试，允许更多步骤完成。")
                }
            case .errorMaxBudgetUsd:
                write("[axion] 预算超限")
            case .cancelled:
                write("[axion] 已取消")
            case .errorDuringExecution:
                if let errors = data.errors, !errors.isEmpty {
                    write("[axion] 执行错误: \(errors.joined(separator: ", "))")
                } else {
                    write("[axion] 执行错误")
                }
                if isFast {
                    write("[axion] 建议去掉 --fast 重新尝试。")
                }
            case .errorMaxStructuredOutputRetries:
                write("[axion] 结构化输出重试超限")
            case .errorMaxModelCalls:
                write("[axion] 已达到模型调用上限")
            }

        case .partialMessage(let data):
            if let waitStart = llmWaitStart {
                llmRound += 1
                let elapsed = ContinuousClock.now - waitStart
                write("[axion] LLM #\(llmRound): \(formatDuration(elapsed))")
                llmWaitStart = nil
            }
            streamBuffer += data.text

        case .system(let data):
            switch data.subtype {
            case .paused:
                flushStreamBuffer()
                if let pausedData = data.pausedData {
                    write("[axion] 任务暂停: \(pausedData.reason)")
                }
            case .pausedTimeout:
                flushStreamBuffer()
                write("[axion] 接管超时（5 分钟无操作），任务终止。")
            default:
                break
            }

        case .hookStarted:
            break

        case .hookResponse:
            break

        default:
            break
        }
    }

    func displayCompletion() {
        flushStreamBuffer()
        write("[axion] 运行结束。")
    }

    private func flushStreamBuffer() {
        if !streamBuffer.isEmpty {
            lastFlushedText = streamBuffer
            write("[axion] \(streamBuffer)")
            streamBuffer = ""
        }
    }

    private func computeElapsedSeconds() -> Int {
        guard let startTime else { return 0 }
        let elapsed = ContinuousClock.now - startTime
        return Int(elapsed.components.seconds)
    }
}
