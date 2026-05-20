import Foundation
import Hummingbird

// MARK: - APIRunStatus

/// Run status exposed via the HTTP API.
public enum APIRunStatus: String, Codable, Equatable, Sendable, CaseIterable {
    case queued
    case running
    case completed
    case failed
    case cancelled
    case interventionNeeded = "intervention_needed"
}

// MARK: - CreateRunRequest

/// Request body for `POST /v1/runs`.
public struct CreateRunRequest: Codable, Equatable, Sendable {
    public let task: String
    public let maxSteps: Int?
    public let maxBatches: Int?

    enum CodingKeys: String, CodingKey {
        case task
        case maxSteps = "max_steps"
        case maxBatches = "max_batches"
    }

    public init(task: String, maxSteps: Int? = nil, maxBatches: Int? = nil) {
        self.task = task
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
    }
}

// MARK: - RunResponse

/// Response body for `POST /v1/runs` and `GET /v1/runs/{id}`.
public struct RunResponse: Codable, Equatable, Sendable, ResponseEncodable {
    public let runId: String
    public let status: APIRunStatus
    public let task: String
    public let createdAt: String
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case status
        case task
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(runId: String, status: APIRunStatus, task: String, createdAt: String, updatedAt: String? = nil) {
        self.runId = runId
        self.status = status
        self.task = task
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - HealthResponse

/// Response body for `GET /v1/health`.
public struct HealthResponse: Codable, Equatable, Sendable, ResponseEncodable {
    public let status: String
    public let version: String

    public init(status: String = "ok", version: String = "1.0.0") {
        self.status = status
        self.version = version
    }
}

// MARK: - APIErrorResponse

/// Standard error response format for all API errors.
public struct APIErrorResponse: Codable, Equatable, Sendable, ResponseEncodable {
    public let error: String
    public let message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

// MARK: - SSE Event Data Types

/// Data payload for a `step_started` SSE event.
public struct StepStartedData: Codable, Equatable, Sendable {
    public let stepIndex: Int
    public let tool: String

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case tool
    }

    public init(stepIndex: Int, tool: String) {
        self.stepIndex = stepIndex
        self.tool = tool
    }
}

/// Data payload for a `step_completed` SSE event.
public struct StepCompletedData: Codable, Equatable, Sendable {
    public let stepIndex: Int
    public let tool: String
    public let success: Bool
    public let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case stepIndex = "step_index"
        case tool
        case success
        case durationMs = "duration_ms"
    }

    public init(stepIndex: Int, tool: String, success: Bool, durationMs: Int? = nil) {
        self.stepIndex = stepIndex
        self.tool = tool
        self.success = success
        self.durationMs = durationMs
    }
}

/// Data payload for a `run_completed` SSE event.
public struct RunCompletedData: Codable, Equatable, Sendable {
    public let runId: String
    public let finalStatus: String
    public let totalSteps: Int
    public let durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case finalStatus = "final_status"
        case totalSteps = "total_steps"
        case durationMs = "duration_ms"
    }

    public init(runId: String, finalStatus: String, totalSteps: Int, durationMs: Int? = nil) {
        self.runId = runId
        self.finalStatus = finalStatus
        self.totalSteps = totalSteps
        self.durationMs = durationMs
    }
}

// MARK: - AgentSSEEvent

/// SSE event types emitted during agent execution via the HTTP API.
/// Named `AgentSSEEvent` to avoid conflict with the existing `SSEEvent` in the API layer.
public enum AgentSSEEvent: Equatable, Sendable {
    case stepStarted(StepStartedData)
    case stepCompleted(StepCompletedData)
    case runCompleted(RunCompletedData)

    /// The SSE event type name string.
    public var eventType: String {
        switch self {
        case .stepStarted: return "step_started"
        case .stepCompleted: return "step_completed"
        case .runCompleted: return "run_completed"
        }
    }

    /// Encode this event as an SSE-formatted text string.
    public func encodeToSSE(sequenceId: Int) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        switch self {
        case .stepStarted(let d): data = try encoder.encode(d)
        case .stepCompleted(let d): data = try encoder.encode(d)
        case .runCompleted(let d): data = try encoder.encode(d)
        }

        let jsonString = String(data: data, encoding: .utf8) ?? "{}"
        return "event: \(eventType)\ndata: \(jsonString)\nid: \(sequenceId)\n\n"
    }
}

// MARK: - PersistedSSEEvent

/// Codable wrapper for persisting SSEEvent to JSONL.
struct PersistedSSEEvent: Codable, Equatable, Sendable {
    let eventType: String
    let stepStarted: StepStartedData?
    let stepCompleted: StepCompletedData?
    let runCompleted: RunCompletedData?

    init(from event: AgentSSEEvent) {
        self.eventType = event.eventType
        switch event {
        case .stepStarted(let data):
            self.stepStarted = data
            self.stepCompleted = nil
            self.runCompleted = nil
        case .stepCompleted(let data):
            self.stepStarted = nil
            self.stepCompleted = data
            self.runCompleted = nil
        case .runCompleted(let data):
            self.stepStarted = nil
            self.stepCompleted = nil
            self.runCompleted = data
        }
    }

    func toSSEEvent() -> AgentSSEEvent? {
        switch eventType {
        case "step_started":
            guard let data = stepStarted else { return nil }
            return .stepStarted(data)
        case "step_completed":
            guard let data = stepCompleted else { return nil }
            return .stepCompleted(data)
        case "run_completed":
            guard let data = runCompleted else { return nil }
            return .runCompleted(data)
        default:
            return nil
        }
    }
}

// MARK: - TrackedRun

/// Internal representation of a tracked run, stored in RunTracker.
public struct TrackedRun: Codable, Equatable, Sendable {
    public let runId: String
    public var status: APIRunStatus
    public let task: String
    public let createdAt: String
    public var updatedAt: String?
    public var totalSteps: Int
    public var durationMs: Int?
    public var resultText: String?
    public var error: String?

    public init(
        runId: String,
        status: APIRunStatus,
        task: String,
        createdAt: String,
        updatedAt: String? = nil,
        totalSteps: Int = 0,
        durationMs: Int? = nil,
        resultText: String? = nil,
        error: String? = nil
    ) {
        self.runId = runId
        self.status = status
        self.task = task
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalSteps = totalSteps
        self.durationMs = durationMs
        self.resultText = resultText
        self.error = error
    }

    func toResponse() -> RunResponse {
        RunResponse(
            runId: runId,
            status: status,
            task: task,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
