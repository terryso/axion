import Foundation

// MARK: - JSONOutput

/// Accumulates execution data and produces a single structured JSON output via `finalize()`.
/// Designed for `--json` mode where the terminal shows only the final JSON result.
final class JSONOutput {

    // MARK: - Accumulated State

    private var runId: String?
    private var task: String?
    private var mode: String?

    init() {}

    func displayRunStart(runId: String, task: String, mode: String) {
        self.runId = runId
        self.task = task
        self.mode = mode
    }

    // MARK: - Finalize

    /// Serializes accumulated run metadata into a formatted JSON string.
    func finalize() -> String {
        let result: [String: Any] = [
            "runId": runId ?? "",
            "task": task ?? "",
            "mode": mode ?? "",
            "state": "done"
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys, .prettyPrinted]
        ) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
