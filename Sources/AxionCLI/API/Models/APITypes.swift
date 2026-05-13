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
