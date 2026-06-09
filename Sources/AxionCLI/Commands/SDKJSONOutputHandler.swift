import Foundation
import OpenAgentSDK

// MARK: - SDKJSONOutputHandler

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
    private var toolStartTimes: [String: ContinuousClock.Instant] = [:]
    private var llmTimings: [[String: Any]] = []
    private var llmRound = 0
    private var llmWaitStart: ContinuousClock.Instant?

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
        llmWaitStart = .now
    }

    func handle(_ message: SDKMessage) {
        switch message {
        case .toolUse(let data):
            toolStartTimes[data.toolUseId] = .now
            steps.append([
                "tool": data.toolName,
                "toolUseId": data.toolUseId
            ])
        case .toolResult(let data):
            llmWaitStart = .now
            if let start = toolStartTimes.removeValue(forKey: data.toolUseId) {
                let elapsed = ContinuousClock.now - start
                let ms = durationToMs(elapsed)
                if let lastIdx = steps.indices.last, steps[lastIdx]["toolUseId"] as? String == data.toolUseId {
                    steps[lastIdx]["duration_ms"] = ms
                }
            }
            if data.isError {
                errors.append([
                    "toolUseId": data.toolUseId,
                    "message": String(data.content.prefix(200))
                ])
            }
        case .result(let data):
            if let waitStart = llmWaitStart {
                llmRound += 1
                let elapsed = ContinuousClock.now - waitStart
                let ms = durationToMs(elapsed)
                llmTimings.append(["round": llmRound, "duration_ms": ms])
            }
            resultData = data
        case .assistant:
            if let waitStart = llmWaitStart {
                llmRound += 1
                let elapsed = ContinuousClock.now - waitStart
                let ms = durationToMs(elapsed)
                llmTimings.append(["round": llmRound, "duration_ms": ms])
                llmWaitStart = nil
            }
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
        result["llm_timings"] = llmTimings
        result["mode"] = mode

        let jsonData = (try? JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys, .prettyPrinted]
        )) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        write(jsonString)
    }
}
