import Foundation
import OpenAgentSDK

// MARK: - SDK Message Output Handlers

/// Terminal output handler — displays human-readable progress via [axion]-prefixed lines.
/// Buffers streaming text from .partialMessage and flushes it as a single line
/// when a structured event (.assistant, .toolUse, .toolResult, .result) arrives.
final class SDKTerminalOutputHandler: OpenAgentSDK.SDKMessageOutputHandler, @unchecked Sendable {
    private let write: (String) -> Void
    private let mode: String
    private var streamBuffer = ""
    private var startTime: ContinuousClock.Instant?
    private var totalSteps = 0

    init(write: @escaping (String) -> Void = { fputs($0 + "\n", stdout); fflush(stdout) }, mode: String = "standard") {
        self.write = write
        self.mode = mode
    }

    func displayRunStart(runId: String, task: String) {
        startTime = ContinuousClock.now
        write("[axion] 模式: \(mode)")
        write("[axion] 运行 ID: \(runId)")
        write("[axion] 任务: \(task)")
    }

    func handle(_ message: SDKMessage) {
        switch message {
        case .assistant(let data):
            if !streamBuffer.isEmpty {
                flushStreamBuffer()
            } else if !data.text.isEmpty {
                write("[axion] \(data.text)")
            }

        case .toolUse(let data):
            flushStreamBuffer()
            totalSteps += 1
            write("[axion] 执行: \(data.toolName)")

        case .toolResult(let data):
            flushStreamBuffer()
            if data.isError {
                write("[axion] 结果: 错误 — \(String(data.content.prefix(100)))")
            } else {
                let snippet = summarizeResult(data.content)
                write("[axion] 结果: \(snippet)")
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
                write("[axion] 执行错误")
                if isFast {
                    write("[axion] 建议去掉 --fast 重新尝试。")
                }
            case .errorMaxStructuredOutputRetries:
                write("[axion] 结构化输出重试超限")
            case .errorMaxModelCalls:
                write("[axion] 已达到模型调用上限")
            }

        case .partialMessage(let data):
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
            write("[axion] \(streamBuffer)")
            streamBuffer = ""
        }
    }

    private func summarizeResult(_ content: String) -> String {
        if content.hasPrefix("{\"action\":\"screenshot\"") || content.contains("image_data") || content.contains("[微压缩]") {
            return "[screenshot captured]"
        }
        if content.contains("Base64") || content.contains("base64") {
            return "[screenshot captured]"
        }
        return String(content.prefix(120))
    }

    private func computeElapsedSeconds() -> Int {
        guard let startTime else { return 0 }
        let elapsed = ContinuousClock.now - startTime
        return Int(elapsed.components.seconds)
    }
}

/// JSON output handler — accumulates data and produces structured JSON at completion.
final class SDKJSONOutputHandler: OpenAgentSDK.SDKMessageOutputHandler, @unchecked Sendable {
    private let write: (String) -> Void
    private let writeEvent: (String) -> Void
    private let mode: String
    private var runId: String = ""
    private var task: String = ""
    private var steps: [[String: Any]] = []
    private var errors: [[String: String]] = []
    private var resultData: SDKMessage.ResultData?

    init(
        mode: String = "standard",
        write: @escaping (String) -> Void = { print($0) },
        writeEvent: @escaping (String) -> Void = { print($0) }
    ) {
        self.mode = mode
        self.write = write
        self.writeEvent = writeEvent
    }

    func displayRunStart(runId: String, task: String) {
        self.runId = runId
        self.task = task
    }

    func handle(_ message: SDKMessage) {
        switch message {
        case .toolUse(let data):
            steps.append([
                "tool": data.toolName,
                "toolUseId": data.toolUseId
            ])
        case .toolResult(let data):
            if data.isError {
                errors.append([
                    "toolUseId": data.toolUseId,
                    "message": String(data.content.prefix(200))
                ])
            }
        case .result(let data):
            resultData = data
        case .system(let data):
            switch data.subtype {
            case .paused:
                if let pausedData = data.pausedData {
                    let event: [String: Any] = [
                        "type": "paused",
                        "reason": pausedData.reason,
                        "canResume": pausedData.canResume,
                        "sessionId": data.sessionId ?? ""
                    ]
                    if let jsonData = try? JSONSerialization.data(
                        withJSONObject: event,
                        options: [.sortedKeys]
                    ) {
                        writeEvent(String(data: jsonData, encoding: .utf8) ?? "{}")
                    }
                }
            case .pausedTimeout:
                var event: [String: Any] = [
                    "type": "pausedTimeout",
                    "canResume": false,
                    "sessionId": data.sessionId ?? ""
                ]
                if let reason = data.pausedData?.reason {
                    event["reason"] = reason
                }
                if let jsonData = try? JSONSerialization.data(
                    withJSONObject: event,
                    options: [.sortedKeys]
                ) {
                    writeEvent(String(data: jsonData, encoding: .utf8) ?? "{}")
                }
            default:
                break
            }
        default:
            break
        }
    }

    func displayCompletion() {
        var result: [String: Any] = [:]
        result["runId"] = runId
        result["task"] = task

        if let data = resultData {
            result["status"] = data.subtype.rawValue
            result["text"] = data.text
            result["numTurns"] = data.numTurns
            result["durationMs"] = data.durationMs
        } else {
            result["status"] = "unknown"
        }

        result["steps"] = steps
        result["errors"] = errors
        result["mode"] = mode

        let jsonData = (try? JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys, .prettyPrinted]
        )) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        write(jsonString)
    }
}
