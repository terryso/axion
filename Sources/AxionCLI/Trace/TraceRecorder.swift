import Foundation
import os

/// Writes review-related trace events as JSON-lines to the run trace directory.
enum TraceRecorder {

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Records a successful review completion event.
    static func recordReviewCompleted(
        runId: String,
        reviewSummary: String,
        memoryChanges: [String],
        skillChanges: [String],
        traceDir: String
    ) {
        let event: [String: Any] = [
            "ts": isoFormatter.string(from: Date()),
            "event": "review_completed",
            "run_id": runId,
            "review_summary": reviewSummary,
            "memory_changes": memoryChanges,
            "skill_changes": skillChanges,
        ]
        appendEvent(event, to: runId, traceDir: traceDir)
    }

    /// Records a review failure event.
    static func recordReviewFailed(
        runId: String,
        error: String,
        traceDir: String
    ) {
        let event: [String: Any] = [
            "ts": isoFormatter.string(from: Date()),
            "event": "review_failed",
            "run_id": runId,
            "error": error,
        ]
        appendEvent(event, to: runId, traceDir: traceDir)
    }

    // MARK: - Private

    private static func appendEvent(_ event: [String: Any], to runId: String, traceDir: String) {
        let dir = (traceDir as NSString).appendingPathComponent(runId)
        let filePath = (dir as NSString).appendingPathComponent("review-trace.jsonl")
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }

        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: filePath)) else {
            // File doesn't exist yet — create it
            try? line.appending("\n").write(toFile: filePath, atomically: true, encoding: .utf8)
            return
        }
        handle.seekToEndOfFile()
        handle.write((line + "\n").data(using: .utf8)!)
        handle.closeFile()
    }
}
