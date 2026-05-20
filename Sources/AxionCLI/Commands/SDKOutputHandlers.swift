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
        write("[axion] \u{6A21}\u{5F0F}: \(mode)")
        write("[axion] \u{8FD0}\u{884C} ID: \(runId)")
        write("[axion] \u{4EFB}\u{52A1}: \(task)")
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
            write("[axion] \u{6267}\u{884C}: \(data.toolName)")

        case .toolResult(let data):
            flushStreamBuffer()
            if data.isError {
                write("[axion] \u{7ED3}\u{679C}: \u{9519}\u{8BEF} \u{2014} \(String(data.content.prefix(100)))")
            } else {
                let snippet = summarizeResult(data.content)
                write("[axion] \u{7ED3}\u{679C}: \(snippet)")
            }

        case .result(let data):
            flushStreamBuffer()
            let isFast = mode == "fast"
            switch data.subtype {
            case .success:
                if isFast {
                    let elapsed = computeElapsedSeconds()
                    write("[axion] Fast mode \u{5B8C}\u{6210}\u{3002}\(totalSteps) \u{6B65}\u{FF0C}\u{8017}\u{65F6} \(elapsed) \u{79D2}\u{3002}")
                    write("[axion] \u{5982}\u{9700}\u{66F4}\u{7CBE}\u{786E}\u{6267}\u{884C}\u{FF0C}\u{53EF}\u{53BB}\u{6389} --fast \u{91CD}\u{8BD5}\u{3002}")
                }
            case .errorMaxTurns:
                write("[axion] \u{8FBE}\u{5230}\u{6700}\u{5927}\u{6B65}\u{6570}\u{9650}\u{5236} (\(data.numTurns) \u{6B65})")
                if isFast {
                    write("[axion] \u{5EFA}\u{8BAE}\u{53BB}\u{6389} --fast \u{91CD}\u{65B0}\u{5C1D}\u{8BD5}\u{FF0C}\u{5141}\u{8BB8}\u{66F4}\u{591A}\u{6B65}\u{9AA4}\u{5B8C}\u{6210}\u{3002}")
                }
            case .errorMaxBudgetUsd:
                write("[axion] \u{9884}\u{7B97}\u{8D85}\u{9650}")
            case .cancelled:
                write("[axion] \u{5DF2}\u{53D6}\u{6D88}")
            case .errorDuringExecution:
                write("[axion] \u{6267}\u{884C}\u{9519}\u{8BEF}")
                if isFast {
                    write("[axion] \u{5EFA}\u{8BAE}\u{53BB}\u{6389} --fast \u{91CD}\u{65B0}\u{5C1D}\u{8BD5}\u{3002}")
                }
            case .errorMaxStructuredOutputRetries:
                write("[axion] \u{7ED3}\u{6784}\u{5316}\u{8F93}\u{51FA}\u{91CD}\u{8BD5}\u{8D85}\u{9650}")
            case .errorMaxModelCalls:
                write("[axion] \u{5DF2}\u{8FBE}\u{5230}\u{6A21}\u{578B}\u{8C03}\u{7528}\u{4E0A}\u{9650}")
            }

        case .partialMessage(let data):
            streamBuffer += data.text

        case .system(let data):
            switch data.subtype {
            case .paused:
                flushStreamBuffer()
                if let pausedData = data.pausedData {
                    write("[axion] \u{4EFB}\u{52A1}\u{6682}\u{505C}: \(pausedData.reason)")
                }
            case .pausedTimeout:
                flushStreamBuffer()
                write("[axion] \u{63A5}\u{7BA1}\u{8D85}\u{65F6}\u{FF08}5 \u{5206}\u{949F}\u{65E0}\u{64CD}\u{4F5C}\u{FF09}\u{FF0C}\u{4EFB}\u{52A1}\u{7EC8}\u{6B62}\u{3002}")
            default:
                break
            }

        default:
            break
        }
    }

    func displayCompletion() {
        flushStreamBuffer()
        write("[axion] \u{8FD0}\u{884C}\u{7ED3}\u{675F}\u{3002}")
    }

    private func flushStreamBuffer() {
        if !streamBuffer.isEmpty {
            write("[axion] \(streamBuffer)")
            streamBuffer = ""
        }
    }

    private func summarizeResult(_ content: String) -> String {
        if content.hasPrefix("{\"action\":\"screenshot\"") || content.contains("image_data") || content.contains("[\u{5FAE}\u{538B}\u{7F29}]") {
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
