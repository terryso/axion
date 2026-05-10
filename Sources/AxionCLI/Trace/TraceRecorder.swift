import Foundation

import AxionCore

// MARK: - TraceRecorder

/// Records execution trace events to a JSONL file (one JSON object per line).
/// Uses Actor isolation to ensure file writes are serialized, preventing
/// interleaved JSON lines when multiple modules call `record` concurrently.
///
/// File location: `{baseURL}/{runId}/trace.jsonl`
/// Default baseURL: `~/.axion/runs/`
///
/// Each event contains:
/// - `ts`: ISO8601 timestamp (auto-added)
/// - `event`: snake_case event name
/// - Additional payload fields as key-value pairs
actor TraceRecorder {

    // MARK: - Trace Event Type Constants

    enum TraceEventType {
        static let runStart = "run_start"
        static let planCreated = "plan_created"
        static let stepStart = "step_start"
        static let stepDone = "step_done"
        static let stateChange = "state_change"
        static let verificationResult = "verification_result"
        static let replan = "replan"
        static let runDone = "run_done"
        static let error = "error"
    }

    // MARK: - Properties

    private var fileHandle: FileHandle?
    private let enabled: Bool
    private let dateFormatter: ISO8601DateFormatter

    // MARK: - Initialization

    /// Creates a TraceRecorder that writes to `{baseURL}/{runId}/trace.jsonl`.
    ///
    /// - Parameters:
    ///   - runId: Unique run identifier (format: `YYYYMMDD-{6random}`)
    ///   - config: AxionConfig containing `traceEnabled` flag
    ///   - baseURL: Base directory for trace files. Defaults to `~/.axion/runs/`
    init(runId: String, config: AxionConfig, baseURL: URL? = nil) throws {
        self.enabled = config.traceEnabled
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if enabled {
            let runsDir = baseURL ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".axion/runs")

            // Create directory for this run: {runsDir}/{runId}/
            let runDir = runsDir.appendingPathComponent(runId)
            try FileManager.default.createDirectory(
                at: runDir,
                withIntermediateDirectories: true
            )

            // Create or open trace file
            let fileURL = runDir.appendingPathComponent("trace.jsonl")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
            try self.fileHandle?.seekToEnd()
        }
    }

    // MARK: - Core Recording

    /// Appends a JSONL event to the trace file.
    /// Automatically adds `ts` (ISO8601) and `event` fields.
    /// Silently ignores write failures — trace errors must not interrupt task execution.
    ///
    /// - Parameters:
    ///   - event: snake_case event name (e.g., "step_done", "run_start")
    ///   - payload: Additional key-value pairs for the event
    func record(event: String, payload: [String: Any] = [:]) {
        guard enabled, let handle = fileHandle else { return }

        var record = payload
        record["ts"] = dateFormatter.string(from: Date())
        record["event"] = event

        // Sanitize: remove sensitive keys and redact sensitive values
        record = sanitizePayload(record)

        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              var jsonLine = String(data: data, encoding: .utf8) else { return }
        jsonLine.append("\n")
        guard let lineData = jsonLine.data(using: .utf8) else { return }
        handle.write(lineData)
    }

    // MARK: - Payload Sanitization

    /// Removes sensitive keys and redacts sensitive values from the payload.
    /// Ensures API keys and secrets never appear in trace output (NFR9).
    private func sanitizePayload(_ payload: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]

        // Keys that should be completely removed
        let sensitiveKeys: Set<String> = [
            "apiKey", "api_key", "secret", "token",
            "password", "credential", "authorization"
        ]

        for (key, value) in payload {
            // Remove sensitive keys entirely
            let keyLower = key.lowercased()
            if sensitiveKeys.contains(where: { keyLower == $0.lowercased() }) {
                continue
            }

            // Sanitize string values that might contain API key patterns
            if let stringValue = value as? String {
                result[key] = sanitizeString(stringValue)
            } else if let dictValue = value as? [String: Any] {
                result[key] = sanitizePayload(dictValue)
            } else {
                result[key] = value
            }
        }

        return result
    }

    /// Removes API key patterns from string values.
    private func sanitizeString(_ value: String) -> String {
        var result = value

        // Remove common API key patterns (sk-..., key-..., etc.)
        let patterns = [
            "apiKey=[^,\\s}]+",
            "api_key=[^,\\s}]+",
            "sk-[a-zA-Z0-9_-]{10,}",
            "key-[a-zA-Z0-9_-]{10,}"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: range,
                    withTemplate: "[REDACTED]"
                )
            }
        }

        // Also redact any remaining apiKey substring (case insensitive)
        result = result.replacingOccurrences(of: "apiKey", with: "[REDACTED]", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "api_key", with: "[REDACTED]", options: .caseInsensitive)

        return result
    }

    // MARK: - Close

    /// Flushes and closes the trace file handle.
    func close() {
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil
    }

    // MARK: - Convenience Methods

    /// Records a run_start event.
    func recordRunStart(runId: String, task: String, mode: String) {
        record(event: TraceEventType.runStart, payload: [
            "runId": runId,
            "task": task,
            "mode": mode
        ])
    }

    /// Records a plan_created event.
    func recordPlanCreated(stepCount: Int, stopWhenCount: Int) {
        record(event: TraceEventType.planCreated, payload: [
            "steps": stepCount,
            "stopWhenCount": stopWhenCount
        ])
    }

    /// Records a step_start event.
    func recordStepStart(index: Int, tool: String, purpose: String) {
        record(event: TraceEventType.stepStart, payload: [
            "index": index,
            "tool": tool,
            "purpose": purpose
        ])
    }

    /// Records a step_done event.
    func recordStepDone(index: Int, tool: String, success: Bool, resultSnippet: String) {
        record(event: TraceEventType.stepDone, payload: [
            "index": index,
            "tool": tool,
            "success": success,
            "resultSnippet": resultSnippet
        ])
    }

    /// Records a state_change event.
    func recordStateChange(from: String, to: String) {
        record(event: TraceEventType.stateChange, payload: [
            "from": from,
            "to": to
        ])
    }

    /// Records a verification_result event.
    func recordVerificationResult(state: String, reason: String) {
        record(event: TraceEventType.verificationResult, payload: [
            "state": state,
            "reason": reason
        ])
    }

    /// Records a replan event.
    func recordReplan(attempt: Int, maxRetries: Int, reason: String) {
        record(event: TraceEventType.replan, payload: [
            "attempt": attempt,
            "maxRetries": maxRetries,
            "reason": reason
        ])
    }

    /// Records a run_done event.
    func recordRunDone(totalSteps: Int, durationMs: Int, replanCount: Int) {
        record(event: TraceEventType.runDone, payload: [
            "totalSteps": totalSteps,
            "durationMs": durationMs,
            "replanCount": replanCount
        ])
    }

    /// Records an error event.
    func recordError(error: String, message: String) {
        record(event: TraceEventType.error, payload: [
            "error": error,
            "message": message
        ])
    }

    // MARK: - Deinit

    deinit {
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
    }
}
