import Foundation
import Hummingbird

// MARK: - APIRunStatus

/// External-facing run status subset exposed via HTTP API.
/// Maps to a subset of the internal RunState values.
enum APIRunStatus: String, Codable, Equatable, Sendable {
    case running
    case done
    case failed
    case cancelled
}

// MARK: - CreateRunRequest

/// Request body for `POST /v1/runs`.
struct CreateRunRequest: Codable, Equatable, Sendable {
    let task: String
    let maxSteps: Int?
    let maxBatches: Int?
    let allowForeground: Bool?

    enum CodingKeys: String, CodingKey {
        case task
        case maxSteps = "max_steps"
        case maxBatches = "max_batches"
        case allowForeground = "allow_foreground"
    }

    init(task: String, maxSteps: Int? = nil, maxBatches: Int? = nil, allowForeground: Bool? = nil) {
        self.task = task
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
        self.allowForeground = allowForeground
    }
}

// MARK: - CreateRunResponse

/// Response body for `POST /v1/runs` (202 Accepted).
struct CreateRunResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let runId: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
    }
}

// MARK: - RunStatusResponse

/// Response body for `GET /v1/runs/{runId}`.
struct RunStatusResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let runId: String
    let status: String
    let task: String
    let totalSteps: Int
    let durationMs: Int?
    let replanCount: Int
    let submittedAt: String
    let completedAt: String?
    let steps: [StepSummary]

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case task
        case totalSteps = "total_steps"
        case durationMs = "duration_ms"
        case replanCount = "replan_count"
        case submittedAt = "submitted_at"
        case completedAt = "completed_at"
        case steps
    }
}

// MARK: - StepSummary

/// Summary of a single executed step within a run.
struct StepSummary: Codable, Equatable, Sendable {
    let index: Int
    let tool: String
    let purpose: String
    let success: Bool
}

// MARK: - HealthResponse

/// Response body for `GET /v1/health`.
struct HealthResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let status: String
    let version: String
}

// MARK: - APIErrorResponse

/// Standard error response format for all API errors.
struct APIErrorResponse: Codable, Equatable, Sendable, ResponseEncodable {
    let error: String
    let message: String
}

// MARK: - TrackedRun

/// Internal representation of a tracked run, stored in RunTracker.
struct TrackedRun: Codable, Equatable, Sendable {
    let runId: String
    let task: String
    var status: APIRunStatus
    let submittedAt: String
    var completedAt: String?
    var totalSteps: Int
    var durationMs: Int?
    var replanCount: Int
    var steps: [StepSummary]
}

// MARK: - RunOptions

/// Options for running an agent task, derived from CreateRunRequest.
struct RunOptions: Codable, Equatable, Sendable {
    let task: String
    let maxSteps: Int?
    let maxBatches: Int?
    let allowForeground: Bool?

    init(task: String, maxSteps: Int? = nil, maxBatches: Int? = nil, allowForeground: Bool? = nil) {
        self.task = task
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
        self.allowForeground = allowForeground
    }
}

// MARK: - SSE Event Types (Story 5.2)

/// Data payload for a `step_started` SSE event.
struct StepStartedData: Codable, Equatable, Sendable {
    let stepIndex: Int
    let tool: String

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case tool
    }
}

/// Data payload for a `step_completed` SSE event.
struct StepCompletedData: Codable, Equatable, Sendable {
    let stepIndex: Int
    let tool: String
    let purpose: String
    let success: Bool
    let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case tool
        case purpose
        case success
        case durationMs = "duration_ms"
    }
}

/// Data payload for a `run_completed` SSE event.
struct RunCompletedData: Codable, Equatable, Sendable {
    let runId: String
    let finalStatus: String
    let totalSteps: Int
    let durationMs: Int?
    let replanCount: Int

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case finalStatus = "final_status"
        case totalSteps = "total_steps"
        case durationMs = "duration_ms"
        case replanCount = "replan_count"
    }
}

/// SSE event types emitted during agent execution.
enum SSEEvent: Equatable, Sendable {
    case stepStarted(StepStartedData)
    case stepCompleted(StepCompletedData)
    case runCompleted(RunCompletedData)

    /// The SSE event type name string.
    var eventType: String {
        switch self {
        case .stepStarted: return "step_started"
        case .stepCompleted: return "step_completed"
        case .runCompleted: return "run_completed"
        }
    }

    /// Encode this event as an SSE-formatted text string.
    /// - Parameter sequenceId: Sequential event ID for SSE `id:` field.
    /// - Returns: Formatted SSE text: `event: ...\ndata: ...\nid: ...\n\n`
    func encodeToSSE(sequenceId: Int) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        switch self {
        case .stepStarted(let d):
            data = try encoder.encode(d)
        case .stepCompleted(let d):
            data = try encoder.encode(d)
        case .runCompleted(let d):
            data = try encoder.encode(d)
        }

        let jsonString = String(data: data, encoding: .utf8) ?? "{}"
        return "event: \(eventType)\ndata: \(jsonString)\nid: \(sequenceId)\n\n"
    }
}
