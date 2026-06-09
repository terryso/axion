import Foundation

/// Writes review-related trace events as JSON-lines to the run trace directory.
enum TraceRecorder {

    /// Records a successful review completion event.
    static func recordReviewCompleted(
        runId: String,
        reviewSummary: String,
        memoryChanges: [String],
        skillChanges: [String],
        traceDir: String
    ) {
        let event: [String: Any] = [
            "ts": axionISO8601Formatter.string(from: Date()),
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
            "ts": axionISO8601Formatter.string(from: Date()),
            "event": "review_failed",
            "run_id": runId,
            "error": error,
        ]
        appendEvent(event, to: runId, traceDir: traceDir)
    }

    /// Records a successful curator completion event.
    static func recordCuratorCompleted(
        runId: String,
        consolidations: Int,
        prunings: Int,
        transitionsApplied: Int,
        traceDir: String
    ) {
        let event: [String: Any] = [
            "ts": axionISO8601Formatter.string(from: Date()),
            "event": "curator_completed",
            "run_id": runId,
            "consolidations": consolidations,
            "prunings": prunings,
            "transitions_applied": transitionsApplied,
        ]
        appendEvent(event, to: runId, traceDir: traceDir)
    }

    /// Records a curator failure event.
    static func recordCuratorFailed(
        runId: String,
        error: String,
        traceDir: String
    ) {
        let event: [String: Any] = [
            "ts": axionISO8601Formatter.string(from: Date()),
            "event": "curator_failed",
            "run_id": runId,
            "error": error,
        ]
        appendEvent(event, to: runId, traceDir: traceDir)
    }

    // MARK: - Private

    private static func appendEvent(_ event: [String: Any], to runId: String, traceDir: String) {
        let dir = (traceDir as NSString).appendingPathComponent(runId)
        let filePath = (dir as NSString).appendingPathComponent("review-trace.jsonl")
        appendJSONLRecord(event, to: filePath)
    }
}
