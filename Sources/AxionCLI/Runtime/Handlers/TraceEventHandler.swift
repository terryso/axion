import Foundation
import OpenAgentSDK

import AxionCore

actor TraceEventHandler: EventHandler {
    let identifier = "trace"
    let subscribedEventTypes: [any AgentEvent.Type] = []

    private let traceDir: String?
    private var runId: String?

    init(traceDir: String?) {
        self.traceDir = traceDir
    }

    func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
        guard let traceDir else { return }

        if runId == nil {
            runId = context.sessionId ?? UUID().uuidString
        }

        let record = mapEvent(event)
        appendRecord(record, traceDir: traceDir)
    }

    private func mapEvent(_ event: any AgentEvent) -> [String: Any] {
        var record: [String: Any] = [
            "ts": ISO8601DateFormatter().string(from: event.timestamp),
            "event_type": String(describing: type(of: event)),
        ]

        if let e = event as? AgentStartedEvent {
            record["trace_type"] = "agent_started"
            record["task"] = e.task
        } else if let e = event as? AgentCompletedEvent {
            record["trace_type"] = "agent_completed"
            record["total_steps"] = e.totalSteps
            record["duration_ms"] = e.durationMs
        } else if let e = event as? ToolStartedEvent {
            record["trace_type"] = "tool_started"
            record["tool_name"] = e.toolName
        } else if let e = event as? ToolCompletedEvent {
            record["trace_type"] = "tool_completed"
            record["tool_name"] = e.toolName
            record["duration_ms"] = e.durationMs
            record["is_error"] = e.isError
        } else if let e = event as? LLMCostEvent {
            record["trace_type"] = "llm_cost"
            record["model"] = e.model
            record["input_tokens"] = e.inputTokens
            record["output_tokens"] = e.outputTokens
            record["cost_usd"] = e.estimatedCostUsd
        }

        return record
    }

    private func appendRecord(_ record: [String: Any], traceDir: String) {
        guard let rid = runId,
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }

        let dir = (traceDir as NSString).appendingPathComponent(rid)
        let filePath = (dir as NSString).appendingPathComponent("events.jsonl")

        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: filePath)) else {
            try? line.appending("\n").write(toFile: filePath, atomically: true, encoding: .utf8)
            return
        }
        handle.seekToEndOfFile()
        handle.write((line + "\n").data(using: .utf8)!)
        handle.closeFile()
    }
}
